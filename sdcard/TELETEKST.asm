; ============================================================================
; TELETEKST.asm - NOS Teletekst 1.0 & Live W5500 Kabelkrant/Afstandsbediening
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC op $9000).
;   - Authentieke 640x360 NOS Teletekst interface (overscan-safe X=16..623)
;   - Interactieve Pagina's:
;       * P100 : NOS Teletekst Hoofdindex & Rubriekenoverzicht
;       * P101 : Binnenland & Actueel Nieuwsoverzicht
;       * P401 : Tech, 720p Wolken-Pipeline & Live W5500 Netwerk (ook P102)
;       * P701 : KNMI Weerbericht & 5-Daagse Verwachtingstabel
;       * P702 : Grafische Weerkaart van Nederland (Zon, Wolken & Regio-temp!)
;       * P818 : Voetbal Eredivisie Standen, Uitslagen & Programma
;       * P900 : Live W5500 Kabelkrant & Web-Gastenboek (ontvangt via HTTP :80!)
;   - Directe 3-cijferige paginakeuze (0..9), Pijltjes/+/-, Fastext-sneltoetsen
;     (N=101, W=702/701, V=818, T=401, K=900, I=100) en B=Bericht typen op P900
;   - Ingebouwde W5500 HTTP Web-Server op TCP Poort 80 (Socket 3):
;     Open http://192.168.178.201/ op je PC of telefoon om live van pagina te
;     zappen op het HDMI-scherm of een bericht naar P900 te sturen!
; ============================================================================
        ORG $8000

IO_STATUS       = $A000
IO_TERM         = $A001
IO_TIMER        = $A003
IO_JOY          = $A004
IO_MODE         = $A006
IO_GPU          = $A020
IO_NET_DATA     = $A030
IO_NET_CTRL     = $A031

ROM_SILENCE     = $E8DC
SPI_BRAM_STUB   = $02F0

; --- Zero Page ($60..$7F: veilig naast BASIC en MC!) ---
ZP_PTR_LO       = $60
ZP_PTR_HI       = $61
ZP_SRC_LO       = $62
ZP_SRC_HI       = $63
ZP_X_LO         = $64
ZP_X_HI         = $65
ZP_Y_LO         = $66
ZP_Y_HI         = $67
ZP_COLOR        = $68
ROW_Y_LO        = $69
ROW_Y_HI        = $6A
SAV_Y           = $6B

SX_PTR_LO       = $6C
SX_PTR_HI       = $6D
SX_LEN_LO       = $6E
SX_LEN_HI       = $6F

W5500_VER       = $70
W5500_PHY       = $71
CUR_PAGE        = $72           ; Huidige pagina-index (0..5)
DIGIT_CNT       = $73           ; Aantal ingetypte paginacijfers (0..3)
EDIT_MODE       = $74           ; 0=Bladeren, 1=Kabelkrant-bericht typen (B)
EDIT_LEN        = $75
NEED_REDRAW     = $76
POLL_DIV        = $77
PREV_JOY        = $78
WEB_HITS        = $79           ; Aantal ontvangen HTTP-verzoeken op :80
MSG_COUNT       = $7A           ; Totaal aantal geplaatste Kabelkrant-berichten
CUR_SLOT        = $7B
TMP_A           = $7C
TMP_B           = $7D
SAV_X           = $7E
LIVE_MODE       = $7F           ; 0=Ingebouwd/P900, 1=Live NOS Teletekst ($4000..$47FF)

NUM_PAGES       = 6

; --- Live NOS Teletekst 25x40 Buffers ($4000..$47FF) & SDRAM ($5000..$52FF) ---
LIVE_CHARS      = $4000         ; 25 x 40 = 1000 B ASCII/Mozaiek ($4000..$43E7)
LIVE_META       = $43E8         ; 24 B: CUR[3], PREV[3], NEXT[3], FAST0..3[12]
LIVE_ATTRS      = $4400         ; 25 x 40 = 1000 B Kleur-attributen ($4400..$47E7)
HTTP_RX_BUF     = $5000         ; Ontvangen HTTP GET-regel ($5000..$507F)
EDIT_BUF        = $5100         ; Invoerbuffer voor nieuw bericht ($5100..$513F)
DIGIT_BUF       = $51C0         ; 3 cijfers voor Pxxx invoer ($51C0..$51C3)
MSG_BUF         = $5200         ; 4 berichten x 64 bytes = 1 pagina ($5200..$52FF)

; ============================================================================
; Start & Initialisatie
; ============================================================================
START:
        JSR ROM_SILENCE
        LDA #0
        STA IO_MODE
        STA ZP_Y_HI
        STA LIVE_MODE
        LDX #7
ST_CLR: STA CUR_PAGE,X
        DEX
        BPL ST_CLR
        LDA #12
        STA IO_TERM

        JSR INIT_MESSAGES
        JSR W5500_INIT_HW
        JSR S3_LISTEN_80
        JSR DRAIN_SERIAL_SHORT

        LDX #0
        JSR LOAD_PAGE_DIGITS_X
        JSR SEND_TT_REQ         ; Vraag bij opstarten meteen live NOS P100 op!

        LDA IO_JOY
        STA PREV_JOY

MAIN_LOOP:
        JSR DRAW_SCREEN
        LDA #0
        STA NEED_REDRAW

WAIT_LOOP:
        LDA IO_TIMER
        CMP POLL_DIV
        BEQ WL_INP
        STA POLL_DIV
        AND #$1F
        BNE WL_NET
        JSR DRAW_LED_ONLY
WL_NET: JSR POLL_HTTP_SERVER
        LDA NEED_REDRAW
        BNE MAIN_LOOP

WL_INP: LDA IO_STATUS
        BMI WL_KEY_RD           ; Bit 7 (ESC-vlag) of Bit 0 (toets klaar)
        AND #1
        BEQ CHK_JOY

WL_KEY_RD:
        LDA IO_JOY
        STA PREV_JOY
        LDX #0
        STX IO_MODE             ; Houd raw keyboard mode actief
        LDA IO_TERM
        BEQ WAIT_LOOP
        BNE HANDLE_KEY

; ============================================================================
; Netjes Afsluiten naar BASIC (met 1x ESC en anti-leak flush)
; ============================================================================
EXIT_TO_BASIC:
        JSR S3_CLOSE
        LDX #15
        JSR DSL_LP
        LDX #GS_EXIT - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

DRAIN_SERIAL_SHORT:
        LDX #4
DSL_LP: JSR DELAY_10MS
        LDA IO_TERM
        LDA #0
        STA IO_MODE
        DEX
        BNE DSL_LP
        RTS

; ============================================================================
; Joystick / Gamepad Navigatie
; ============================================================================
CHK_JOY:
        LDA IO_JOY
        STA TMP_A
        TAX
        EOR PREV_JOY
        AND TMP_A
        STX PREV_JOY
        TAY
        BEQ WAIT_LOOP
        LDA EDIT_MODE
        BNE WAIT_LOOP

        TYA
        and #$15                ; Up(1), Right(8) of Fire(16) -> NEXT, Down/Left -> PREV
        BNE NEXT_PAGE
        BEQ PREV_PAGE

NEXT_PAGE:
        LDA LIVE_MODE
        BEQ NP_OFF
        LDX #6                  ; LIVE_META+6..8 = nextPage van NOS JSON
        BNE REQ_FROM_META_X
NP_OFF: LDX CUR_PAGE
        INX
        CPX #NUM_PAGES
        BCC SET_PAGE_X
        LDX #0
        BEQ SET_PAGE_X

PREV_PAGE:
        LDA LIVE_MODE
        BEQ PP_OFF
        LDX #3                  ; LIVE_META+3..5 = prevPage van NOS JSON
        BNE REQ_FROM_META_X
PP_OFF: LDX CUR_PAGE
        BNE PP_DEC
        LDX #NUM_PAGES
PP_DEC: DEX
SET_PAGE_X:
        TXA
SET_PAGE_A:
        STA CUR_PAGE
        TAX
        JSR LOAD_PAGE_DIGITS_X
        JSR CHECK_SEND_LIVE
CLR_DIG_MAIN:
        LDA #0
        STA DIGIT_CNT
        JMP MAIN_LOOP

SUBPAGE_CYCLE:
        LDA LIVE_MODE
        BEQ HK_REDRAW
        LDX #0                  ; LIVE_META+0..2 = curPage (wissel subpagina 1/2 <-> 2/2)
REQ_FROM_META_X:
        LDA LIVE_META,X
        BEQ HK_REDRAW
        LDY #0
RFM_LP: LDA LIVE_META,X
        STA DIGIT_BUF,Y
        INX
        INY
        CPY #3
        BCC RFM_LP
        JSR LOOKUP_3DIGIT_PAGE
        JMP MAIN_LOOP

; ============================================================================
; Toetsenbord Afhandeling (Cijfers 0..9, Pijltjes, Fastext & Bericht-editor)
; ============================================================================
HANDLE_KEY:
        LDX EDIT_MODE
        BNE KEY_EDIT_MSG

        CMP #$1B                ; ESC of ANSI pijltjestoets (ESC [ A/B/C/D)?
        BNE HK_NOT_ESC

        LDX #3
HK_EW:  JSR DELAY_10MS
        LDA IO_STATUS
        AND #$81
        BNE HK_E2
        DEX
        BNE HK_EW

        LDA DIGIT_CNT
        BEQ EXIT_TO_BASIC       ; Losse ESC -> in 1x terug naar BASIC!
        BNE CLR_DIG_MAIN

HK_E2:  LDA IO_TERM
        LDX #0
        STX IO_MODE
        CMP #'['
        BNE EXIT_TO_BASIC
        JSR DELAY_10MS
        LDA IO_TERM
        LDX #0
        STX IO_MODE
        LSR A                   ; 'A'($41)/'C'($43) oneven -> NEXT, 'B'/'D' -> PREV
        BCS NEXT_PAGE
        BCC PREV_PAGE

HK_NOT_ESC:
        CMP #'0'
        BCC HK_NAV
        CMP #'9'+1
        BCS HK_NAV
        LDX DIGIT_CNT
        BNE HK_D_ADD
        CMP #'0'
        BEQ HK_NAV
HK_D_ADD:
        STA DIGIT_BUF,X
        INX
        STX DIGIT_CNT
        CPX #3
        BCC HK_BURST_CHK
        JSR LOOKUP_3DIGIT_PAGE
HK_REDRAW:
        JMP MAIN_LOOP

HK_BURST_CHK:
        LDY #0
HK_BC1: LDA IO_STATUS
        AND #1
        BNE WL_KEY_RD           ; Volgend cijfer uit Snelcommando-burst al binnen!
        DEY
        BNE HK_BC1
        BEQ HK_REDRAW           ; Losse toetsaanslag -> teken P7.. / P70. linksboven!

HK_NAV:
        CMP #$08
        BEQ CLR_DIG_MAIN
        CMP #$7F
        BEQ CLR_DIG_MAIN
        CMP #'+'
        BEQ NEXT_PAGE
        CMP #'='
        BEQ NEXT_PAGE
        CMP #' '
        BEQ SUBPAGE_CYCLE
        CMP #'-'
        BEQ PREV_PAGE

        ORA #$20
        CMP #'q'
        BEQ EXIT_TO_BASIC
        CMP #'r'
        BEQ SUBPAGE_CYCLE
        CMP #'b'
        BEQ START_MSG_INPUT

        LDX #7
HK_TLP: CMP KEY_CHARS,X
        BEQ HK_THIT
        DEX
        BPL HK_TLP
        JMP WAIT_LOOP
HK_THIT:
        LDA KEY_PAGES,X
        BPL SET_PAGE_A

; --- Nieuw Kabelkrant-bericht typen met toetsenbord (B) ---
START_MSG_INPUT:
        LDA #5
        STA CUR_PAGE
        LDA #0
        STA LIVE_MODE
        STA DIGIT_CNT
        STA EDIT_LEN
        STA EDIT_BUF
        LDA #1
        STA EDIT_MODE
        BNE HK_REDRAW

KEY_EDIT_MSG:
        CMP #$1B                ; ESC annuleert invoer (sluit NIET af!)
        BNE KEM_1
        JSR DRAIN_SERIAL_SHORT
        LDA #0
        STA EDIT_MODE
        BEQ HK_REDRAW
KEM_1:  CMP #$0D                ; ENTER plaatst het bericht op P900!
        BEQ KEM_SEND
        CMP #$08
        BEQ KEM_BS
        CMP #$7F
        BEQ KEM_BS
        CMP #' '
        BCC KEM_WAIT
        LDY EDIT_LEN
        CPY #46
        BCS KEM_WAIT
        STA EDIT_BUF,Y
        INY
        BNE KEM_SET
KEM_BS: LDY EDIT_LEN
        BEQ KEM_WAIT
        DEY
KEM_SET:
        STY EDIT_LEN
        LDA #0
        STA EDIT_BUF,Y
        BEQ HK_REDRAW
KEM_WAIT:
        JMP WAIT_LOOP

KEM_SEND:
        LDA #0
        STA EDIT_MODE
        LDA EDIT_LEN
        BEQ HK_REDRAW
        LDA #<EDIT_BUF
        LDY #>EDIT_BUF
        JSR ADD_KABEL_MSG
        JMP MAIN_LOOP

; --- Zoek 3-cijferig paginanummer & Vraag Live NOS Pagina op (100..899) ---
LOOKUP_3DIGIT_PAGE:
        LDA #0
        STA DIGIT_CNT
        LDA DIGIT_BUF+2
        SEC
        SBC #'0'
        CMP #3
        BCC L3P_1
        LDA #0
L3P_1:  TAX
        LDY #3
L3P_LP: LDA DIGIT_BUF
        CMP PAGE_D0+2,Y         ; "4789"
        BNE L3P_NX
        TYA
        CLC
        ADC #2
        TAX
L3P_NX: DEY
        BPL L3P_LP
        STX CUR_PAGE

CHECK_SEND_LIVE:
        LDA DIGIT_BUF
        CMP #'9'
        BNE SEND_TT_REQ
        LDA #0
        STA LIVE_MODE
        LDA #5
        STA CUR_PAGE
        RTS

SEND_TT_REQ:
        LDA #'P'
        STA LIVE_CHARS+1
        LDA #$02
        STA LIVE_ATTRS+1
        LDX #2
STR_CP: LDA DIGIT_BUF,X
        STA REQ_STR+4,X
        STA LIVE_CHARS+2,X
        LDA #$02
        STA LIVE_ATTRS+2,X
        DEX
        BPL STR_CP
        LDX #0
STR_LP: LDA REQ_STR,X
        STA IO_TERM
        INX
        CPX #9
        BCC STR_LP
        LDA #0
        STA IO_MODE
        RTS

LOAD_PAGE_DIGITS_X:
        LDA PAGE_D0,X
        STA DIGIT_BUF
        LDA #'0'
        CPX #4
        BNE LPD_1
        LDA #'1'
LPD_1:  STA DIGIT_BUF+1
        LDA PAGE_D2,X
        STA DIGIT_BUF+2
        RTS

; ============================================================================
; Kabelkrant Berichtenbuffer (4 x 64 bytes = 256 B op $5200..$52FF)
; ============================================================================
INIT_MESSAGES:
        LDX #0
        TXA
IM_CLR: STA MSG_BUF,X
        INX
        BNE IM_CLR
        STA MSG_COUNT
        LDA #<STR_INIT_M1
        LDY #>STR_INIT_M1

ADD_KABEL_MSG:
        STA ZP_SRC_LO
        STY ZP_SRC_HI
        LDX #0
AKM_S1: LDA MSG_BUF+64,X
        STA MSG_BUF,X
        INX
        CPX #192
        BCC AKM_S1

        LDY #0
AKM_CP: LDA (ZP_SRC_LO),Y
        BEQ AKM_PAD
        STA MSG_BUF+192,Y
        INY
        CPY #50
        BCC AKM_CP
AKM_PAD:
        LDA #0
        STA MSG_BUF+192,Y
        INC MSG_COUNT
        RTS

; ============================================================================
; W5500 HTTP Web-Server & Live NOS Teletekst Receiver op Socket 3 ($68, :80)
; ============================================================================
S3_LISTEN_80:
        JSR S3_CLOSE
        LDX #$00
        LDA #$01
        JSR S3_WR
        LDX #$04
        LDA #0
        JSR S3_WR
        LDX #$05
        LDA #80
        JSR S3_WR
        LDA #$01
        JSR S3_CMD
        LDA #$02
        JMP S3_CMD

POLL_HTTP_SERVER:
        LDA #$03
        JSR S3_RD
        CMP #$17
        BEQ PHS_EST
        CMP #$1C
        BEQ S3_DISCON_RELISTEN
        CMP #$00
        BEQ S3_LISTEN_80
        RTS

PHS_EST:
        LDA #$26
        JSR S3_RD
        STA SX_LEN_HI
        LDA #$27
        JSR S3_RD
        STA SX_LEN_LO
        ORA SX_LEN_HI
        BNE PHS_RX
        RTS

PHS_RX:
        JSR DELAY_10MS          ; Wacht ~15ms zodat beide TCP-segmenten (2046 B) binnen zijn
        JSR DELAY_10MS
        LDA #$26
        JSR S3_RD
        STA SX_LEN_HI
        LDA #$27
        JSR S3_RD
        STA SX_LEN_LO

        LDA #$28
        LDX #$78                ; Socket 3 RX Buffer ($78)
        JSR S3_PTR_HDR
        LDA #$00
        JSR SPI_BRAM_STUB
        CMP #'T'                ; "TT" Live NOS Teletekst binair frame (2046 B)?
        BNE PHS_HTTP_G

        LDA #$00
        JSR SPI_BRAM_STUB       ; Tweede 'T'
        LDA #>LIVE_CHARS
        STA ZP_PTR_HI
        LDY #0
        STY ZP_PTR_LO
        LDX #8                  ; 8 * 256 = 2048 B -> $4000..$47FF
PHS_TTL:
        LDA #$00
        JSR SPI_BRAM_STUB
        STA (ZP_PTR_LO),Y
        INY
        BNE PHS_TTL
        INC ZP_PTR_HI
        DEX
        BNE PHS_TTL
        JSR W5500_CS_HI
        JSR PHS_ACK_RX
        LDA #1
        STA LIVE_MODE
        STA NEED_REDRAW
        JMP S3_DISCON_RELISTEN

PHS_HTTP_G:
        STA HTTP_RX_BUF
        LDY #1
PHS_RL: LDA #$00
        JSR SPI_BRAM_STUB
        STA HTTP_RX_BUF,Y
        INY
        CPY #64
        BCC PHS_RL
        LDA #0
        STA HTTP_RX_BUF,Y
        JSR W5500_CS_HI
        JSR PHS_ACK_RX

        LDA HTTP_RX_BUF+4
        CMP #'/'
        BNE PHS_SEND_PAGE
        LDA HTTP_RX_BUF+5
        CMP #'f'
        BEQ PHS_SEND_PAGE

        INC WEB_HITS
        INC NEED_REDRAW

        CMP #'p'
        BNE PHS_CHK_MSG
        LDA HTTP_RX_BUF+6
        SEC
        SBC #'0'
        CMP #NUM_PAGES
        BCS PHS_SEND_PAGE
        STA CUR_PAGE
        TAX
        JSR LOAD_PAGE_DIGITS_X
        JSR CHECK_SEND_LIVE
        LDA #0
        STA DIGIT_CNT
        BEQ PHS_SEND_PAGE

PHS_CHK_MSG:
        CMP #'?'
        BNE PHS_SEND_PAGE
        LDA HTTP_RX_BUF+7
        CMP #'='
        BNE PHS_SEND_PAGE

        LDX #8
        LDY #0
PHS_DEC:
        LDA HTTP_RX_BUF,X
        BEQ PHS_MDN
        CMP #' '
        BEQ PHS_MDN
        CMP #'&'
        BEQ PHS_MDN
        CMP #'+'
        BNE PHS_ST
        LDA #' '
PHS_ST: STA EDIT_BUF,Y
        INY
        CPY #48
        BCS PHS_MDN
        INX
        BNE PHS_DEC

PHS_MDN:
        LDA #0
        STA EDIT_BUF,Y
        CPY #0
        BEQ PHS_SEND_PAGE
        STA LIVE_MODE           ; Schakel naar P900 Kabelkrant!
        LDA #<EDIT_BUF
        LDY #>EDIT_BUF
        JSR ADD_KABEL_MSG
        LDA #5
        STA CUR_PAGE

PHS_SEND_PAGE:
        LDA #$24
        LDX #$74                ; Socket 3 TX Buffer ($74)
        JSR S3_PTR_HDR
        LDA #<STR_HTTP_HTML1
        LDY #>STR_HTTP_HTML1
        JSR SPI_SEND_STR_AY

        LDX #0
PSP_LP: STX SAV_X
        TXA
        CLC
        ADC #'0'
        STA STR_HTTP_LNK+10
        JSR LOAD_PAGE_DIGITS_X
        LDY #2
PSP_C3: LDA DIGIT_BUF,Y
        STA STR_HTTP_LNK+12,Y
        DEY
        BPL PSP_C3
        LDA #<STR_HTTP_LNK
        LDY #>STR_HTTP_LNK
        JSR SPI_SEND_STR_AY
        LDX SAV_X
        INX
        CPX #NUM_PAGES
        BCC PSP_LP

        LDA #<STR_HTTP_HTML2
        LDY #>STR_HTTP_HTML2
        JSR SPI_SEND_STR_AY
        LDA #<MSG_BUF+192
        LDY #>MSG_BUF+192
        JSR SPI_SEND_STR_AY
        JSR W5500_CS_HI
        LDA #$24
        LDY #$20
        JSR S3_PTR_CMD
        LDX #40
PHS_WT: STX SAV_X
        LDA #$20
        JSR S3_RD
        CMP #$08
        BEQ S3_DISCON_RELISTEN
        JSR DELAY_10MS
        LDX SAV_X
        DEX
        BNE PHS_WT

S3_DISCON_RELISTEN:
        LDA #$08
        JSR S3_CMD
        JSR DELAY_10MS
        JMP S3_LISTEN_80

PHS_ACK_RX:
        CLC
        LDA SX_PTR_LO
        ADC SX_LEN_LO
        STA SX_PTR_LO
        LDA SX_PTR_HI
        ADC SX_LEN_HI
        STA SX_PTR_HI
        LDA #$28
        LDY #$40
        JMP S3_PTR_CMD

SPI_SEND_STR_AY:
        STA ZP_SRC_LO
        STY ZP_SRC_HI
        LDY #0
SSSA_L: LDA (ZP_SRC_LO),Y
        BEQ SSSA_R
        JSR SPI_AND_INC_SX
        INY
        BNE SSSA_L
SSSA_R: RTS

; ============================================================================
; W5500 SPI Driver (Vaste Socket 3: Reg=$68/$6C, TX=$74, RX=$78)
; ============================================================================
W5500_INIT_HW:
        LDX #6
WIH_CP: LDA W5500_STUB_BYTES,X
        STA SPI_BRAM_STUB,X
        DEX
        BPL WIH_CP
        LDA #$03
        STA IO_NET_CTRL
        JSR W5500_PROBE_HW
        BNE SSSA_R
        LDA #$02
        STA IO_NET_CTRL
        LDX #0
WIH_L:  LDA W5500_INIT_TBL,X
        JSR SPI_BRAM_STUB
        INX
        CPX #22
        BCC WIH_L
        JMP W5500_CS_HI

W5500_PROBE_HW:
        LDA #$2E
        JSR W5500_RD_CREG
        STA W5500_PHY
        LDA #$39
        JSR W5500_RD_CREG
        STA W5500_VER
        CMP #$04
        RTS

W5500_HDR_0:
        LDX #$00
W5500_HDR:
        PHA
        LDA #$02
        STA IO_NET_CTRL
        TXA
        JSR SPI_BRAM_STUB
        PLA
        JSR SPI_BRAM_STUB
        TYA
        JMP SPI_BRAM_STUB

S3_RD:  LDY #$68
        BNE W5500_RD_Y
W5500_RD_CREG:
        LDY #$00
W5500_RD_Y:
        JSR W5500_HDR_0
        LDA #$00
        JSR SPI_BRAM_STUB
        PHA
        JSR W5500_CS_HI
        PLA
        RTS

W5500_CS_HI:
        LDA #$03
        STA IO_NET_CTRL
        RTS

S3_WR:  PHA
        LDY #$6C
        TXA
        JSR W5500_HDR_0
        PLA
        JSR SPI_BRAM_STUB
        JMP W5500_CS_HI

S3_CLOSE:
        LDA #$10
S3_CMD: LDX #$01
        JSR S3_WR
S3C_W:  LDA #$01
        JSR S3_RD
        BNE S3C_W
        RTS

S3_PTR_CMD:
        STY TMP_A
        LDY #$6C
        JSR W5500_HDR_0
        LDA SX_PTR_HI
        JSR SPI_BRAM_STUB
        LDA SX_PTR_LO
        JSR SPI_BRAM_STUB
        JSR W5500_CS_HI
        LDA TMP_A
        JMP S3_CMD

S3_PTR_HDR:
        STX TMP_A
        PHA
        JSR S3_RD
        STA SX_PTR_HI
        PLA
        CLC
        ADC #1
        JSR S3_RD
        STA SX_PTR_LO
        LDX SX_PTR_HI
        LDY TMP_A
        JMP W5500_HDR

SPI_AND_INC_SX:
        JSR SPI_BRAM_STUB
        INC SX_PTR_LO
        BNE SAIS_R
        INC SX_PTR_HI
SAIS_R: RTS

; ============================================================================
; Live 25x40 NOS Teletekst Renderer (480x350 op X=80..559, Y=4..353, 12x14 cel)
; ============================================================================
DRAW_LIVE_NOS:
        LDX #GS_CLEAR - GPU_STREAMS
        JSR SEND_STREAM_X

        LDA DIGIT_CNT
        BEQ DLN_GRID
        LDA #'P'
        STA LIVE_CHARS+1
        LDA #$03
        STA LIVE_ATTRS+1
        LDX #0
DLN_DB: LDA #'_'
        CPX DIGIT_CNT
        BCS DLN_D1
        LDA DIGIT_BUF,X
DLN_D1: STA LIVE_CHARS+2,X
        LDA #$03
        STA LIVE_ATTRS+2,X
        INX
        CPX #3
        BCC DLN_DB

DLN_GRID:
        LDA #<LIVE_CHARS
        STA ZP_PTR_LO
        STA ZP_SRC_LO
        LDA #>LIVE_CHARS
        STA ZP_PTR_HI
        LDA #>LIVE_ATTRS
        STA ZP_SRC_HI
        LDA #4
        STA ROW_Y_LO
        LDA #0
        STA ROW_Y_HI
        LDA #25
        STA CUR_SLOT

DLN_ROW:
        LDA #80
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        CLC
        LDA ROW_Y_LO
        ADC #3
        STA ZP_Y_LO
        LDA ROW_Y_HI
        ADC #0
        STA ZP_Y_HI
        LDY #0

DLN_COL:
        STY SAV_Y
        LDA (ZP_SRC_LO),Y
        PHA
        AND #$07
        TAX
        LDA TT_COL8,X
        STA ZP_COLOR
        PLA
        LSR A
        LSR A
        LSR A
        LSR A
        AND #$07
        BEQ DLN_FG
        TAX
        LDA TT_COL8,X
        LDX #6                  ; Volledige 12x14 cel achtergrond
        JSR DRAW_SUBRECT_XA

DLN_FG: LDY SAV_Y
        LDA (ZP_PTR_LO),Y
        CMP #$21
        BCC DLN_NEXT_COL
        BMI DLN_MOSAIC

        INC ZP_X_LO             ; X + 2 (80 + 12*col is altijd deelbaar door 4!)
        INC ZP_X_LO
        JSR DRAW_CHAR_ONLY
        JMP DLN_NEXT_COL

DLN_MOSAIC:
        AND #$3F                ; ETS 300 706 2x3 mozaiek sub-blokken (bits 0..5)
        BEQ DLN_NEXT_COL
        STA TMP_A
        LDX #0
DLN_MLP:
        LSR TMP_A
        BCC DLN_MNX
        LDA ZP_COLOR
        JSR DRAW_SUBRECT_XA
DLN_MNX:
        INX
        CPX #6
        BCC DLN_MLP

DLN_NEXT_COL:
        LDA ZP_X_LO
        AND #$FC
        CLC
        ADC #12
        STA ZP_X_LO
        BCC DLN_NC1
        INC ZP_X_HI
DLN_NC1:
        LDY SAV_Y
        INY
        CPY #40
        BCC DLN_COL

        CLC
        LDA ZP_PTR_LO
        ADC #40
        STA ZP_PTR_LO
        STA ZP_SRC_LO
        BCC DLN_NR1
        INC ZP_PTR_HI
        INC ZP_SRC_HI
DLN_NR1:
        CLC
        LDA ROW_Y_LO
        ADC #14
        STA ROW_Y_LO
        BCC DLN_NR2
        INC ROW_Y_HI
DLN_NR2:
        DEC CUR_SLOT
        BEQ DLN_END
        JMP DLN_ROW
DLN_END:
        JMP DRAW_LED_ONLY

DRAW_SUBRECT_XA:
        PHA
        LDA #2
        STA IO_GPU
        CLC
        LDA ZP_X_LO
        ADC MOS_DX,X
        STA IO_GPU
        LDA ZP_X_HI
        ADC #0
        STA IO_GPU
        CLC
        LDA ROW_Y_LO
        ADC MOS_DY,X
        STA IO_GPU
        LDA ROW_Y_HI
        ADC #0
        STA IO_GPU
        LDA MOS_DW,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA MOS_DH,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        PLA
        STA IO_GPU
        RTS

; ============================================================================
; NOS Teletekst 640x360 HDMI Renderer (Ingebouwd & P900 Kabelkrant)
; ============================================================================
DRAW_SCREEN:
        LDA LIVE_MODE
        BEQ DS_OFFLINE
        JMP DRAW_LIVE_NOS
DS_OFFLINE:
        LDX #GS_FRAME - GPU_STREAMS
        JSR SEND_STREAM_X
        JSR DRAW_LED_ONLY

        ; 1. Teken vaste chrome (zet cursor aan het eind op X=200, Y=38 voor paginatitel!)
        LDA #<PS_CHROME
        STA ZP_PTR_LO
        LDA #>PS_CHROME
        STA ZP_PTR_HI
        JSR RUN_TT_SCRIPT

        ; 2. Op P702 (index 3): teken eerst de grafische Weerkaart van Nederland!
        LDA CUR_PAGE
        CMP #3
        BNE DS_PG
        LDX #GS_NLMAP - GPU_STREAMS
        JSR SEND_STREAM_X

        ; 3. Zoek het CUR_PAGE-de paginascript in PS_POOL en voer het uit!
DS_PG:  LDA #<PS_POOL
        STA ZP_PTR_LO
        LDA #>PS_POOL
        STA ZP_PTR_HI
        LDX CUR_PAGE
        BEQ DS_RUN_P
DS_SKP: JSR READ_PTR_B
        BNE DS_SKP
        DEX
        BNE DS_SKP
DS_RUN_P:
        JSR RUN_TT_SCRIPT

        ; 4. Pagina 900 berichtenlijst (index 5)
        LDA CUR_PAGE
        CMP #5
        BNE DS_BOT
        JSR DRAW_P900_MESSAGES

        ; 5. Onderste balk (Y = 340): Hulpbalk of Bericht-invoer
DS_BOT: LDA #170
        JSR RTS_SETY_A
        LDA EDIT_MODE
        BEQ DS_BHLP
        LDA #<STR_EDIT_PROMPT
        LDY #>STR_EDIT_PROMPT
        JSR DRAW_SRC_AY
        LDA #<EDIT_BUF
        LDY #>EDIT_BUF
        JSR DRAW_SRC_AY
        LDA #'_'
        JMP DRAW_CHAR_ADV
DS_BHLP:
        LDA #<STR_BOT_HELP
        LDY #>STR_BOT_HELP
        JMP DRAW_SRC_AY

; ============================================================================
; Teletekst Script Engine
; ============================================================================
RESET_LINE_START:
        LDA ROW_Y_LO
        STA ZP_Y_LO
        LDA ROW_Y_HI
        STA ZP_Y_HI
        LDA #24
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$FF
        STA ZP_COLOR
        RTS

RUN_TT_SCRIPT:
        JSR READ_PTR_B
        BEQ RTS_DONE
        JSR DO_TT_TOKEN
        JMP RUN_TT_SCRIPT

DO_TT_TOKEN:
        CMP #$C0
        BCS RTS_DICT
        CMP #$80
        BCS SET_COL_A
        CMP #$20
        BCS DRAW_CHAR_ADV
        CMP #$0A
        BEQ RTS_NL13
        CMP #$0D
        BEQ RTS_NL11
        CMP #$09
        BEQ RTS_SETY
        CMP #$11
        BEQ RTS_HDRBAR
        CMP #$12
        BEQ RTS_SECBAR
        CMP #$0C
        BEQ RTS_LNK
        CMP #$0E
        BEQ DRAW_P_BOX
        CMP #$0F
        BEQ DRAW_CUR_PAGE_NUM
        CMP #$10
        BEQ RTS_TICKER
        TAX
        CMP #$07
        BCS RTS_CNT
        LDA TT_PALETTE-1,X
        STA ZP_COLOR
RTS_DONE:
        RTS

RTS_CNT:
        LDA $72,X
        JMP DRAW_DEC_BYTE

DRAW_P_BOX:
        LDA DIGIT_CNT
        BEQ DRAW_CUR_PAGE_NUM
        LDA #$FC
        STA ZP_COLOR
        LDX #0
DS_DG:  LDA #'_'
        CPX DIGIT_CNT
        BCS DS_D1
        LDA DIGIT_BUF,X
DS_D1:  JSR DRAW_CHAR_ADV
        INX
        CPX #3
        BCC DS_DG
        RTS

RTS_TICKER:
        LDA #150
        JSR RTS_SETY_A
        LDA #<STR_EDIT_PROMPT
        LDY #>STR_EDIT_PROMPT
        JSR DRAW_SRC_AY
        LDA #<MSG_BUF+192
        LDY #>MSG_BUF+192
        JMP DRAW_SRC_AY

RTS_LNK:
        LDA W5500_PHY
        LSR A
        LDA #<STR_W55_OK
        LDY #>STR_W55_OK
        BCS RLK_2
        LDA #<STR_W55_CBL
        LDY #>STR_W55_CBL
RLK_2:  JMP DRAW_SRC_AY

RTS_DICT:
        SBC #$C0
        TAX
        LDY #0
RD_SKP: DEX
        BMI RD_PRT
RD_W0:  LDA DICT_POOL,Y
        INY
        CMP #0
        BNE RD_W0
        BEQ RD_SKP
RD_PRT: LDA DICT_POOL,Y
        BEQ RTS_DONE
        INY
        STY SAV_Y
        JSR DO_TT_TOKEN
        LDY SAV_Y
        BNE RD_PRT

RTS_SETY:
        JSR READ_PTR_B
RTS_SETY_A:
        LDX #0
        STX ROW_Y_HI
        ASL A
        ROL ROW_Y_HI
        STA ROW_Y_LO
        JMP RESET_LINE_START

RTS_NL13:
        LDA #13
        BNE RTS_ADD_Y
RTS_NL11:
        LDA #11
RTS_ADD_Y:
        CLC
        ADC ROW_Y_LO
        STA ROW_Y_LO
        BCC RTS_AY1
        INC ROW_Y_HI
RTS_AY1:
        JMP RESET_LINE_START

SET_COL_A:
        AND #$3F
        LDX #0
        STX ZP_X_HI
        ASL A
        ASL A
        ROL ZP_X_HI
        ASL A
        ROL ZP_X_HI
        CLC
        ADC #16
        STA ZP_X_LO
        BCC SCA_R
        INC ZP_X_HI
SCA_R:  RTS

RTS_HDRBAR:
        LDA #33
        JSR RTS_SETY_A
        LDA #$02
        BNE RTS_BAR_A
RTS_SECBAR:
        JSR RTS_NL13
        LDA #$01
RTS_BAR_A:
        PHA
        LDA ROW_Y_LO
        SEC
        SBC #2
        STA GS_BAR+4
        LDX #GS_BAR - GPU_STREAMS
        JSR SEND_STREAM_X
        PLA
        STA IO_GPU
        LDA #$FC
        STA ZP_COLOR
        RTS

; ============================================================================
; P900 Live Kabelkrant Berichtenlijst (4 berichten in $5200..$52FF)
; ============================================================================
DRAW_P900_MESSAGES:
        LDX #0
DP9_LP: STX CUR_SLOT
        JSR RTS_NL13
        JSR RTS_NL11
        LDA #'>'
        JSR DRAW_CHAR_ADV
        LDA #' '
        JSR DRAW_CHAR_ADV
        LDA CUR_SLOT
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        LDY #>MSG_BUF
        JSR DRAW_SRC_AY
        LDX CUR_SLOT
        INX
        CPX #4
        BCC DP9_LP
        RTS

; ============================================================================
; Tekst & Getal Hulproutines
; ============================================================================
DRAW_CUR_PAGE_NUM:
        LDX CUR_PAGE
        LDA PAGE_D0,X
        JSR DRAW_CHAR_ADV
        LDA #'0'
        LDX CUR_PAGE
        CPX #4
        BNE DCPN_2
        LDA #'1'
DCPN_2: JSR DRAW_CHAR_ADV
        LDX CUR_PAGE
        LDA PAGE_D2,X
        JMP DRAW_CHAR_ADV

DRAW_DEC_BYTE:
        LDY #'0'
        SEC
DDB_10: SBC #10
        BCC DDB_1
        INY
        BNE DDB_10
DDB_1:  ADC #10+'0'
        PHA
        TYA
        CMP #'0'
        BEQ DDB_2
        JSR DRAW_CHAR_ADV
DDB_2:  PLA
        JMP DRAW_CHAR_ADV

SEND_STREAM_X:
        LDY GPU_STREAMS,X
SSX_L:  INX
        LDA GPU_STREAMS,X
        STA IO_GPU
        DEY
        BNE SSX_L
        STY ZP_Y_HI
        RTS

DRAW_LED_ONLY:
        JSR W5500_PROBE_HW
        LDX #GS_LED - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #$E0
        LDX W5500_VER
        CPX #$04
        BNE DLO_C
        LDA W5500_PHY
        AND #$01
        BEQ DLO_Y
        LDA #$1C
        BNE DLO_C
DLO_Y:  LDA #$FC
DLO_C:  STA IO_GPU
        RTS

READ_PTR_B:
        LDY #0
        LDA (ZP_PTR_LO),Y
        INC ZP_PTR_LO
        BNE RPB_R
        INC ZP_PTR_HI
RPB_R:  CMP #0
        RTS

DRAW_SRC_AY:
        STA ZP_SRC_LO
        STY ZP_SRC_HI
        LDY #0
DSA_LP: LDA (ZP_SRC_LO),Y
        BEQ DCA_R
        INY
        STY SAV_Y
        JSR DO_TT_TOKEN
        LDY SAV_Y
        BNE DSA_LP

DRAW_CHAR_ADV:
        CMP #' '+1
        BCC ADV_X8
        JSR DRAW_CHAR_ONLY
ADV_X8: CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCA_R
        INC ZP_X_HI
DCA_R:  RTS

DRAW_CHAR_ONLY:
        PHA
        LDA #8
        STA IO_GPU
        LDA ZP_X_LO
        STA IO_GPU
        LDA ZP_X_HI
        STA IO_GPU
        LDA ZP_Y_LO
        STA IO_GPU
        LDA ZP_Y_HI
        STA IO_GPU
        PLA
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA ZP_COLOR
        STA IO_GPU
        RTS

DELAY_10MS:
        LDA IO_TIMER
D10_W:  CMP IO_TIMER
        BEQ D10_W
        RTS

; ============================================================================
; Tabellen, Sneltoetsen, Mozaiek, W5500 Config & GPU-Streams
; ============================================================================
REQ_STR:        .BYTE 13, "@TT100", 13, 12
TT_COL8:        .BYTE $00, $E0, $1C, $FC, $03, $E3, $1F, $FF
MOS_DX:         .BYTE 0, 6, 0, 6, 0, 6, 0
MOS_DY:         .BYTE 0, 0, 5, 5, 9, 9, 0
MOS_DW:         .BYTE 6, 6, 6, 6, 6, 6, 12
MOS_DH:         .BYTE 5, 5, 4, 4, 5, 5, 14

TT_PALETTE:     .BYTE $FF, $FC, $1F, $1C, $E4, $E3
KEY_CHARS:      .BYTE "ihntwvsk"
KEY_PAGES:      .BYTE 0, 0, 1, 2, 3, 4, 4, 5
PAGE_D0:        .BYTE "114789"
PAGE_D2:        .BYTE "011280"

W5500_STUB_BYTES:
        STA IO_NET_DATA
        LDA IO_NET_DATA
        RTS

W5500_INIT_TBL:
        .BYTE $00, $00, $04, $00
        .BYTE 192, 168, 178, 1
        .BYTE 255, 255, 255, 0
        .BYTE $02, $65, $02, $20, $00, $03
        .BYTE 192, 168, 178, 201

GPU_STREAMS:
GS_CLEAR:
        .BYTE 4, 12, 1, 1, $00
GS_FRAME:
        .BYTE GS_NLMAP - GS_FRAME - 1
        .BYTE 12, 1
        .BYTE 1, $00
        .BYTE 2, 16,0, 6,0, $60,$02, 16,0, $01
        .BYTE 2, 16,0, 26,0, 168,0, 30,0, $02
        .BYTE 2, 18,0, 28,0, 6,0, 26,0, $E0
        .BYTE 2, 174,0, 28,0, 8,0, 26,0, $FC
        .BYTE 2, 188,0, 26,0, $B4,$01, 30,0, $FC
        .BYTE 2, 188,0, 28,0, $B4,$01, 26,0, $02
        .BYTE 2, 16,0, $41,$01, 146,0, 13,0, $C0
        .BYTE 2, 166,0, $41,$01, 146,0, 13,0, $1C
        .BYTE 2, $3C,$01, $41,$01, 146,0, 13,0, $FC
        .BYTE 2, $D2,$01, $41,$01, 152,0, 13,0, $03

GS_NLMAP:
        .BYTE GS_LED - GS_NLMAP - 1
        .BYTE 2, 20,0, 64,0, $1C,$01, 226,0, $02
        .BYTE 2, 148,0, 84,0, 104,0, 44,0, $14
        .BYTE 2, 122,0, 128,0, 148,0, 84,0, $14
        .BYTE 2, 78,0, 118,0, 68,0, 108,0, $14
        .BYTE 5, 252,0, 150,0, 10,0, 0,0, $FC

GS_LED:
        .BYTE GS_BAR - GS_LED - 1
        .BYTE 5, $64,$02, 14,0, 4,0, 0,0
GS_BAR:
        .BYTE GS_EXIT - GS_BAR - 1
        .BYTE 2, 16,0, 0,0, $60,$02, 11,0
GS_EXIT:
        .BYTE STR_BOT_HELP - GS_EXIT - 1
        .BYTE 12, 1, 1, $E3

; ============================================================================
; Vaste UI-Strings, Woordenboek ($C0..$D8, <= 255 B) & Pagina-Scripts
; ============================================================================
STR_BOT_HELP:   .BYTE $03,"0-9:Pag +/-:Zap N/W/V/T/K/I B:Typ ESC:Stop",0
STR_EDIT_PROMPT:.BYTE $02,"P900: ",$01,0
STR_W55_OK:     .BYTE $04,"100M ONLINE",0
STR_W55_CBL:    .BYTE $02,"GEEN KABEL",0

STR_INIT_M1:    .ASCIIZ "Open http://192.168.178.201 of toets B!"

DICT_POOL:
        .ASCIIZ "NOS Teletekst"                         ; $C0
        .ASCIIZ "Tang Nano 20K"                         ; $C1
        .ASCIIZ "W5500"                                 ; $C2
        .ASCIIZ "http://192.168.178.201"                ; $C3
        .ASCIIZ "Enschede"                              ; $C4
        .ASCIIZ "FC Twente"                             ; $C5
        .ASCIIZ "Groningen"                             ; $C6
        .ASCIIZ "Amsterdam"                             ; $C7
        .ASCIIZ "Rotterdam"                             ; $C8
        .ASCIIZ "Maastricht"                            ; $C9
        .ASCIIZ "Eredivisie"                            ; $CA
        .ASCIIZ "Weerkaart"                             ; $CB
        .ASCIIZ "Kabelkrant"                            ; $CC
        .ASCIIZ "Nederland"                             ; $CD
        .BYTE $80+15, "11 ", 0                          ; $CE
        .BYTE " .. ", $02, 0                            ; $CF
        .BYTE $80+38, $01, 0                            ; $D0
        .BYTE $80+50, 0                                 ; $D1
        .BYTE $80+57, $02, 0                            ; $D2
        .BYTE $80+35, $03, 0                            ; $D3
        .BYTE $0A, $03,"> ", $01, 0                     ; $D4
        .BYTE $0A, $04, 0                               ; $D5
        .BYTE $0D, $01, 0                               ; $D6
        .BYTE $80+14, ": ", $01, 0                      ; $D7
        .BYTE $0A, $80+38, $03, 0                       ; $D8

PS_CHROME:
        .BYTE $09,5, $81, $04,"P",$0E, $87, $01,"NOS-TT ", $02,$0F, $03," MA 02 NOV", $80+51, $04,$C3
        .BYTE $09,17, $82, $01,"N O S", $09,22, $82, $02,"TELETEKST"
        .BYTE $09,162, $81, $01,"N:101 NIEUWS", $80+20, $01,"W:702 WEERKAART"
        .BYTE $80+39, $05,"V:818 VOETBAL", $80+57, $01,"K:900 KABELKRANT"
        .BYTE $09,19, $80+23, $02,$0F, "  ", $01, 0

; --- 6 Sequentiele Pagina-Scripts in PS_POOL (gescheiden door $00) ---
PS_POOL:
; [0] PAGINA 100: VOORPAGINA & INDEX
        .BYTE "INDEX"
        .BYTE $11," HOOFDPUNTEN", $D1, $03,"PAG"
        .BYTE $D4,"Live ", $C0," (100-899) via ", $C2, $D1, $02,"101"
        .BYTE $D4,"720p Wolken-Pipeline Boerderij", $D1, $02,"401"
        .BYTE $D4,$CB," ", $CD,", ", $C4," 15 C", $D1, $02,"702"
        .BYTE $D4,$CA,": ", $C5,", PSV & Ajax", $D1, $02,"818"
        .BYTE $12," RUBRIEKEN", $80+35, $02,"TOETSEN"
        .BYTE $D5,"Nieuws",     $CF,"101", $D3,"0-9: ", $01,"100-899"
        .BYTE $D5,"Tech/", $C2, $CF,"401", $D3,"+/-: ", $01,"Zap"
        .BYTE $D5,$CB," NL",    $CF,"702", $D3,"SPC: ", $01,"Subpag"
        .BYTE $D5,$CA,          $CF,"818", $D3,"K/B: ", $04,$CC
        .BYTE $10, 0

; [1] PAGINA 101: BINNENLAND & FPGA NIEUWS
        .BYTE "NIEUWS"
        .BYTE $11," ", $C0," OP ", $C1
        .BYTE $0A, $03,$C4," - ", $01,"Live ", $C0," via ", $C2
        .BYTE $D6,"Web: ", $04,$C3
        .BYTE $12," KORT NIEUWS"
        .BYTE $D5,"* ", $01,"Toets 100..899 voor echte NOS-pagina!"
        .BYTE $D5,"* ", $01,"Toets ", $02,"900/B", $01," voor ", $CC,"."
        .BYTE $10, 0

; [2] PAGINA 401 (en 102): TECH, 720P WOLKEN-PIPELINE & W5500 NETWERK
        .BYTE "TECH & ", $C2
        .BYTE $11," 720P PIPELINE & ", $C2
        .BYTE $0A, $03,"FPGA",       $D7,"GW2AR-18C (", $C1,")"
        .BYTE $0D, $03,"Video",      $D7,"640x360 -> 720p HDMI"
        .BYTE $12," ", $C2," NETWERK"
        .BYTE $0A, $03,$C2," Link",  $D7,$0C
        .BYTE $0A, $03,"Web-Remote", $D7,$04,$C3
        .BYTE $0A, $03,"HTTP Hits",  $D7,$02,$07, $D3,$CC,": ", $04,$08, 0

; [3] PAGINA 702 (en 701): GRAFISCHE WEERKAART NL & KNMI 5-DAAGSE
        .BYTE $CB," ", $CD
        .BYTE $09,33, $83, $03,"NOORDZEE", $80+38, $02,"VANDAAG"
        .BYTE $0A, $80+17, $01,$C6," 13",   $D0,$C6, $D1,"13C"
        .BYTE $0A,                          $D0,$C7, $D1,"14C"
        .BYTE $0A, $80+11, $01,"A'DAM 14",  $D0,$C4, $D1,"15C"
        .BYTE $0A, $80+19, $02,$C4," 15",   $D0,$C8, $D1,"14C"
        .BYTE $0A, $80+10, $01,"R'DAM 14",  $D0,$C9, $D1,"16C"
        .BYTE $0A, $80+18, $02,$C9," 16",   $D8,"Di 65% 7/15 ZW3", 0

; [4] PAGINA 818: VOETBAL EREDIVISIE
        .BYTE "VOETBAL ", $CA
        .BYTE $11," ", $CA," STAND", $80+38, $02,"UITSLAGEN"
        .BYTE $0D, $04,"1 PSV",       $CE,"30", $D0,$C5,"-Heracles",$D2,"5-0"
        .BYTE $0D, $04,"2 Ajax",      $CE,"26", $D0,"PSV-Zwolle",$D2,"6-0"
        .BYTE $0D, $02,"3 ", $C5,     $CE,"24", $D0,"Ajax-Feyenoord",$D2,"2-1"
        .BYTE $0D, $03,"4 Utrecht",   $CE,"23", $D0,"AZ-Go Ahead",$D2,"2-2"
        .BYTE $0D, $03,"5 Feyenoord", $CE,"22", $D0,"ZA ", $C5,"-Ajax", 0

; [5] PAGINA 900: LIVE W5500 KABELKRANT
        .BYTE "LIVE ", $CC
        .BYTE $11," LIVE ", $C2," ", $CC," (:80)"
        .BYTE $0A, $01,"Web: ", $04,$C3, $01," of toets ", $02,"B", $01,":"
        .BYTE $12," LAATSTE 4 BERICHTEN:", 0

; ============================================================================
; Compacte HTML Web-Afstandsbediening & Berichtenformulier op Poort 80
; ============================================================================
STR_HTTP_HTML1:
        .BYTE "HTTP/1.0 200 OK", 13, 10, 13, 10
        .ASCIIZ "<body bgcolor=0 text=#ff0><b>NOS-TT</b> "
STR_HTTP_LNK:
        .ASCIIZ "<a href=/p0>100</a> "
STR_HTTP_HTML2:
        .ASCIIZ "<form>P900:<input name=m></form>"
