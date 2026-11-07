; ============================================================================
; BBS.asm - MiniGPU BBS-Term 1.0 (6502 + W5500 ANSI / Telnet BBS Terminal!)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC op $9000).
;   - Volledige RFC 854 Telnet Client met actieve IAC ($FF) onderhandeling
;   - Echte UDP DNS-Resolver op W5500 (Poort 53: Router .1 + 1.1.1.1 fallback)
;   - 75x20 ANSI-Kleurenterminal met per-karakter 16-kleuren SGR (ESC[...m),
;     2D cursorpositionering (ESC[H, ESC[r;cH, ESC[A/B/C/D), schermwissen
;     (ESC[2J, ESC[K) en CP437 blokgrafiek-vertaling!
;   - Ingebouwd BBS-Telefoonboek (1-6) + vrije Host:Poort Kiezer (D)
;   - Live karakter-modus (kleine + hoofdletters, ENTER, BS & ANSI-pijltjes!)
; Starten vanuit Midnight Commander (BRUN MC) of in BASIC met: BRUN "BBS"
; ============================================================================
        ORG $8000

IO_STATUS       = $A000
IO_TERM         = $A001
IO_TIMER        = $A003
IO_JOY          = $A004
IO_RND          = $A005
IO_MODE         = $A006
IO_GPU          = $A020
IO_NET_DATA     = $A030
IO_NET_CTRL     = $A031

ROM_SILENCE     = $E8DC
SPI_BRAM_STUB   = $02F0

; --- Zero Page ($60..$87: veilig naast BASIC $10..$45 en MC $45..$5E/$88..$8E) ---
ZP_PTR_LO       = $60
ZP_PTR_HI       = $61
ZP_SRC_LO       = $62
ZP_SRC_HI       = $63
ZP_LINE_LO      = $64
ZP_LINE_HI      = $65
ZP_COL_LO       = $66
ZP_COL_HI       = $67
ZP_X_LO         = $68
ZP_X_HI         = $69
ZP_Y_LO         = $6A
ZP_Y_HI         = $6B
ZP_COLOR        = $6C

S1_PTR_LO       = $6D
S1_PTR_HI       = $6E
S1_LEN_LO       = $6F
S1_LEN_HI       = $70
PORT_ACC_LO     = $6F
PORT_ACC_HI     = $70

W5500_VER       = $71
W5500_PHY       = $72
CONN_STATE      = $73           ; 0=Telefoonboek, 1=Verbonden met BBS
EDIT_MODE       = $74           ; 0=Normaal, 1=Host:Poort invoeren (D)
EDIT_LEN        = $75
STATUS_IDX      = $76           ; 0=KIES, 4=DNS., 8=BEL., 12=ONLN, 16=FOUT
THEME_IDX       = $77           ; 0=ANSI-Wit, 1=Groen, 2=Amber, 3=Cyaan
LOCAL_ECHO      = $78           ; 0=Server echo, 1=Lokale echo (bijv. Tang #1)

CUR_X           = $79           ; Cursor kolom (0..74)
CUR_Y           = $7A           ; Cursor rij (0..19)
CUR_FG          = $7B           ; Huidige RGB332 tekstkleur
CUR_BOLD        = $7C           ; 0 of 8 (ANSI bold/bright bit)
IAC_STATE       = $7D           ; 0=Normaal, 1=IAC, 2=WILL/DO, 3=SB, 4=SB_IAC
ANSI_STATE      = $7E           ; 0=Tekst, 1=ESC, 2=CSI
PREV_JOY        = $7F

DEST_IP0        = $80
DEST_IP1        = $81
DEST_IP2        = $82
DEST_IP3        = $83
DEST_PORT_HI    = $84
DEST_PORT_LO    = $85
TMP_A           = $86
TMP_B           = $87

; --- SDRAM Geheugenindeling (laat MC $5BE0..$5FFF en $9000..$9FFF vrij!) ---
TERM_CHARS      = $3000         ; 20 rijen x 128 B ($3000..$39FF)
TERM_COLORS     = $4000         ; 20 rijen x 128 B ($4000..$49FF)
TERM_ROWS       = 20
TERM_COLS       = 75

DIAL_BUF        = $5800         ; Huidige "host:poort" string
HOST_BUF        = $5880         ; Geparsete hostnaam voor DNS
DNS_BUF         = $5A00         ; UDP DNS pakketbuffer ($5A00..$5ABF)

LOCAL_PORT      = $5900
IAC_CMD         = $5901
SAV_X           = $5902
SAV_Y           = $5903
NEED_REDRAW     = $5904
POLL_DIV        = $5905
CSI_IDX         = $5906
CSI_P0          = $5908
CSI_P1          = $5909
CSI_P2          = $590A
IAC_TX_LEN      = $590B
IAC_TX_BUF      = $5910         ; 48-byte antwoordenbuffer voor Telnet IAC

ST_KIES         = 0
ST_DNS          = 4
ST_BEL          = 8
ST_ONLN         = 12
ST_FOUT         = 16

; ============================================================================
; Start & Hoofdlus
; ============================================================================
START:
        JSR ROM_SILENCE
        LDA #0
        STA IO_MODE
        STA ZP_Y_HI
        STA CONN_STATE
        STA EDIT_MODE
        STA THEME_IDX
        STA LOCAL_ECHO
        LDA #12
        STA IO_TERM

        LDA IO_RND
        ORA #$01
        STA LOCAL_PORT

        JSR W5500_INIT_HW
        LDX #0
        JSR COPY_PRESET_X
        JSR SHOW_PHONEBOOK

        LDA IO_JOY
        STA PREV_JOY

MAIN_LOOP:
        JSR DRAW_SCREEN
        LDA #0
        STA NEED_REDRAW

WAIT_LOOP:
        JSR DELAY_10MS

        LDA CONN_STATE
        BEQ WL_NO_NET
        JSR POLL_TELNET_RX
        LDA NEED_REDRAW
        BNE MAIN_LOOP
WL_NO_NET:
        INC POLL_DIV
        LDA POLL_DIV
        AND #$1F
        BNE WL_INP
        JSR W5500_PROBE_HW
        JSR DRAW_LED_ONLY

WL_INP: LDA IO_STATUS
        AND #1
        BNE CHK_KEY
        JMP CHK_JOY

EXIT_TO_BASIC:
        JSR S1_CLOSE
        LDX #GS_EXIT - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

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
        LDA CONN_STATE
        BEQ WAIT_LOOP

        LDX #0
CJ_LP:  LSR A
        BCS CJ_SEND_ARR
        INX
        CPX #4
        BCC CJ_LP
        BCS WAIT_LOOP

CJ_SEND_ARR:
        LDA ANSI_DIRS,X
        PHA
        JSR S1_TX_PTR_HDR
        LDA #$1B
        JSR SPI_AND_INC_S1
        LDA #'['
        JSR SPI_AND_INC_S1
        PLA
        JSR S1_SEND_END
        JMP WAIT_LOOP

; ============================================================================
; Toetsenbord Afhandeling (Telefoonboek, Host:Poort-invoer & Live BBS-toetsen)
; ============================================================================
CHK_KEY:
        LDA IO_JOY
        STA PREV_JOY
        LDA IO_TERM
        LDX #0
        STX IO_MODE             ; Herstel term_enable=0 direct als ESC ($1B) is ingedrukt!

        LDX EDIT_MODE
        BNE KEY_EDIT_DIAL

        LDX CONN_STATE
        BNE KEY_LIVE_BBS

        ; --- In het Telefoonboek (CONN_STATE == 0) ---
        CMP #'1'
        BCC KB_PB_CH
        CMP #'6'+1
        BCS KB_PB_CH
        SEC
        SBC #'1'
        ASL A
        TAX
        JMP DIAL_PRESET_X

KB_PB_CH:
        CMP #$1B
        BEQ SHOW_PB_MAIN        ; ESC: vernieuw Telefoonboek (nooit per ongeluk afsluiten!)
        ORA #$20
        CMP #'q'
        BEQ EXIT_TO_BASIC
        CMP #'d'
        BEQ START_DIAL_INPUT
        CMP #'g'
        BEQ START_DIAL_INPUT
        CMP #'c'
        BEQ DO_CYCLE_THEME
        CMP #'e'
        BEQ DO_TOGGLE_ECHO
        CMP #'p'
        BEQ SHOW_PB_MAIN
        JMP WAIT_LOOP

SHOW_PB_MAIN:
        JSR SHOW_PHONEBOOK
        JMP MAIN_LOOP

DO_CYCLE_THEME:
        INC THEME_IDX
        LDA THEME_IDX
        AND #3
        STA THEME_IDX
        JSR APPLY_THEME_COLOR
        JMP MAIN_LOOP

DO_TOGGLE_ECHO:
        LDA LOCAL_ECHO
        EOR #1
        STA LOCAL_ECHO
        JMP MAIN_LOOP

START_DIAL_INPUT:
        LDA #0
        STA EDIT_LEN
        STA DIAL_BUF
        LDA #1
        STA EDIT_MODE
        JMP MAIN_LOOP

KEY_EDIT_DIAL:
        CMP #$1B
        BEQ KED_CAN
        CMP #$0D
        BEQ KED_ENTER
        CMP #$08
        BEQ KED_BS
        CMP #$7F
        BEQ KED_BS
        CMP #' '
        BCC KED_WAIT
        CMP #$7F
        BCS KED_WAIT
        LDY EDIT_LEN
        CPY #54
        BCS KED_WAIT
        STA DIAL_BUF,Y
        INY
        BNE KED_SET
KED_BS: LDY EDIT_LEN
        BEQ KED_WAIT
        DEY
KED_SET:
        STY EDIT_LEN
        LDA #0
        STA DIAL_BUF,Y
        JSR DRAW_TOP_BARS
KED_WAIT:
        JMP WAIT_LOOP

KED_CAN:
        LDA #0
        STA EDIT_LEN
KED_ENTER:
        LDA #0
        STA EDIT_MODE
        LDA EDIT_LEN
        BEQ KED_MAIN
        LDA #0
        STA LOCAL_ECHO
        JSR CONNECT_DIAL_BUF
KED_MAIN:
        JMP MAIN_LOOP

; --- Live Verbonden met een BBS: elke toets (ook ESC!) direct over TCP versturen! ---
KEY_LIVE_BBS:
        CMP #$0E                ; F9 -> Ophangen
        BEQ KLB_HUP
        CMP #$18                ; Ctrl+X -> Ophangen
        BEQ KLB_HUP
        CMP #$60                ; ` (toets links naast 1) -> Ophangen
        BNE KLB_SEND
KLB_HUP:
        JSR HANGUP_BBS
        JMP MAIN_LOOP

KLB_SEND:
        PHA
        JSR S1_TX_PTR_HDR
        PLA
        PHA
        JSR SPI_AND_INC_S1
        PLA
        PHA
        CMP #$0D
        BNE KLB_1
        LDA #$0A
        JSR SPI_AND_INC_S1
KLB_1:  JSR W5500_CS_HI
        JSR S1_FLUSH_SEND
KLB_ECHO:
        PLA
        LDX LOCAL_ECHO
        BEQ KED_WAIT
        CMP #$0D
        BNE KLB_E1
        LDA #$0D
        JSR TERM_PUT_BYTE
        LDA #$0A
KLB_E1: JSR TERM_PUT_BYTE
        JMP MAIN_LOOP

; ============================================================================
; Snelkeuze (1..6), Host:Poort Parser & Verbinden via DNS + TCP
; ============================================================================
DIAL_PRESET_X:
        JSR COPY_PRESET_X
        JSR CONNECT_DIAL_BUF
        JMP MAIN_LOOP

COPY_PRESET_X:
        LDA #0
        CPX #10                 ; Preset #6 (index 10) = 192.168.178.200 (Tang #1)
        BNE DPX_EC
        LDA #1
DPX_EC: STA LOCAL_ECHO
        LDA PRESET_PTRS,X
        STA ZP_SRC_LO
        LDA PRESET_PTRS+1,X
        STA ZP_SRC_HI
        LDY #0
DPX_CP: LDA (ZP_SRC_LO),Y
        STA DIAL_BUF,Y
        BEQ DPX_R
        INY
        BNE DPX_CP
DPX_R:  RTS

HANGUP_BBS:
        JSR S1_CLOSE
        LDA #0
        STA CONN_STATE
        LDA #ST_KIES
        STA STATUS_IDX
        JSR TERM_CRLF
        LDA #$FC
        STA CUR_FG
        LDA #<STR_DISCONN
        LDY #>STR_DISCONN
        JMP TERM_PRINT_STR

CONNECT_DIAL_BUF:
        JSR CLEAR_TERM
        LDA #$1F
        STA CUR_FG
        LDA #<STR_DIALING
        LDY #>STR_DIALING
        JSR TERM_PRINT_STR
        LDA #<DIAL_BUF
        LDY #>DIAL_BUF
        JSR TERM_PRINT_STR
        JSR TERM_CRLF

        JSR PARSE_HOST_PORT

        LDA #ST_DNS
        STA STATUS_IDX
        JSR DRAW_SCREEN

        JSR W5500_PROBE_HW
        BNE CDB_ENET
        LDA W5500_PHY
        AND #$01
        BNE CDB_DNS
CDB_ENET:
        LDA #<STR_ERR_NET
        LDY #>STR_ERR_NET
        BNE CDB_FAIL

CDB_DNS:
        JSR DNS_RESOLVE
        BCS CDB_TCP
        LDA #<STR_ERR_DNS
        LDY #>STR_ERR_DNS
        BNE CDB_FAIL

CDB_TCP:
        LDA #ST_BEL
        STA STATUS_IDX
        JSR DRAW_TOP_BARS

        LDA #$01
        JSR S1_OPEN_DEST
        LDA #$04
        JSR S1_CMD

        LDX #250
CDB_WC: STX TMP_A
        LDA #$03
        JSR W5500_RD_S1
        CMP #$17
        BEQ CDB_OK
        CMP #$00
        BEQ CDB_ETCP
        JSR DELAY_10MS
        LDX TMP_A
        DEX
        BNE CDB_WC
CDB_ETCP:
        LDA #<STR_ERR_TCP
        LDY #>STR_ERR_TCP
CDB_FAIL:
        PHA
        TYA
        PHA
        JSR S1_CLOSE
        LDA #0
        STA CONN_STATE
        LDA #ST_FOUT
        STA STATUS_IDX
        LDA #$E0
        STA CUR_FG
        PLA
        TAY
        PLA
        JSR TERM_PRINT_STR
        JMP TERM_CRLF

CDB_OK: LDA #1
        STA CONN_STATE
        LDA #0
        STA IAC_STATE
        STA ANSI_STATE
        LDA #ST_ONLN
        STA STATUS_IDX
        JSR APPLY_THEME_COLOR
        LDA #<STR_CONNECTED
        LDY #>STR_CONNECTED
        JSR TERM_PRINT_STR
        JMP TERM_CRLF

PARSE_HOST_PORT:
        LDA #0
        STA DEST_PORT_HI
        LDA #23
        STA DEST_PORT_LO
        LDX #0
        LDY #0
PHP_HL: LDA DIAL_BUF,X
        BEQ PHP_HD
        CMP #':'
        BEQ PHP_PORT
        CMP #' '
        BEQ PHP_HD
        STA HOST_BUF,Y
        INY
        INX
        CPY #60
        BCC PHP_HL
PHP_HD: LDA #0
        STA HOST_BUF,Y
        RTS

PHP_PORT:
        LDA #0
        STA HOST_BUF,Y
        STA PORT_ACC_LO
        STA PORT_ACC_HI
        INX
PHP_PL: LDA DIAL_BUF,X
        JSR IS_DIGIT_SUB0
        BCC PHP_PD
        JSR ADD_PORT_DIGIT
        INX
        BNE PHP_PL
PHP_PD: LDA PORT_ACC_LO
        ORA PORT_ACC_HI
        BEQ PHP_R
        LDA PORT_ACC_LO
        STA DEST_PORT_LO
        LDA PORT_ACC_HI
        STA DEST_PORT_HI
PHP_R:  RTS

; ============================================================================
; Live Telnet RX Stream + Actieve RFC 854 IAC ($FF) Handshake
; ============================================================================
POLL_TELNET_RX:
        JSR S1_GET_RX_LEN
        BNE PTR_GOT
        LDA #$03
        JSR W5500_RD_S1
        CMP #$17
        BEQ PTR_R
        JSR HANGUP_BBS
        LDA #1
        STA NEED_REDRAW
PTR_R:  RTS

PTR_GOT:
        LDA #0
        STA IAC_TX_LEN
        LDA S1_LEN_HI
        BEQ PTR_C1
        LDA #250
        BNE PTR_C2
PTR_C1: LDA S1_LEN_LO
        CMP #250
        BCC PTR_C2
        LDA #250
PTR_C2: STA S1_LEN_LO

        JSR S1_READ_PTR_HDR
PTR_LP: LDA #0
        JSR SPI_AND_INC_S1
        JSR FEED_TELNET_BYTE
        DEC S1_LEN_LO
        BNE PTR_LP

        JSR W5500_CS_HI
        LDA #$28
        LDY #$40
        JSR S1_PTR_CMD

        LDA IAC_TX_LEN
        BEQ PTR_RD
        JSR S1_TX_PTR_HDR
        LDX #0
PTR_IT: LDA IAC_TX_BUF,X
        JSR SPI_AND_INC_S1
        INX
        CPX IAC_TX_LEN
        BCC PTR_IT
        JSR W5500_CS_HI
        JSR S1_FLUSH_SEND

PTR_RD: LDA #1
        STA NEED_REDRAW
        RTS

FEED_TELNET_BYTE:
        LDX IAC_STATE
        BNE FTB_IAC
        CMP #$FF
        BEQ FTB_SET1
        JMP TERM_PUT_BYTE
FTB_SET1:
        LDA #1
        STA IAC_STATE
        RTS

FTB_IAC:
        DEX
        BNE FTB_I2
        ; IAC_STATE == 1
        CMP #$FF
        BNE FTB_1A
        LDA #0
        STA IAC_STATE
        JMP TERM_PUT_BYTE
FTB_1A: CMP #$FA                ; SB (Subnegotiation)
        BNE FTB_1B
        LDA #3
        STA IAC_STATE
        RTS
FTB_1B: CMP #$FB
        BCC FTB_I0
        CMP #$FF
        BCS FTB_I0
        STA IAC_CMD
        LDA #2
        STA IAC_STATE
        RTS
FTB_I0: LDA #0
        STA IAC_STATE
        RTS

FTB_I2: DEX
        BNE FTB_I3
        ; IAC_STATE == 2: A = optie voor WILL($FB)/WONT($FC)/DO($FD)/DONT($FE)
        PHA
        LDA #0
        STA IAC_STATE
        LDA IAC_CMD
        CMP #$FB                ; WILL
        BEQ FTB_WILL
        CMP #$FD                ; DO
        BEQ FTB_DO
        PLA
        RTS

FTB_WILL:
        PLA
        TAY
        LDX #$FE                ; DONT
        CPY #1                  ; ECHO?
        BEQ FTB_W_DO
        CPY #3                  ; SGA?
        BNE FTB_Q_IAC
FTB_W_DO:
        LDX #$FD                ; DO ECHO / DO SGA!
        BNE FTB_Q_IAC

FTB_DO: PLA
        TAY
        LDX #$FC                ; WONT
        CPY #3                  ; SGA?
        BNE FTB_Q_IAC
        LDX #$FB                ; WILL SGA!

FTB_Q_IAC:
        sty TMP_A
        LDY IAC_TX_LEN
        CPY #45
        BCS FTB_QR
        LDA #$FF
        STA IAC_TX_BUF,Y
        INY
        TXA
        STA IAC_TX_BUF,Y
        INY
        LDA TMP_A
        STA IAC_TX_BUF,Y
        INY
        STY IAC_TX_LEN
FTB_QR: RTS

FTB_I3: DEX
        BNE FTB_I4
        ; IAC_STATE == 3 (in SB)
        CMP #$FF
        BNE FTB_QR
        LDA #4
        STA IAC_STATE
        RTS
FTB_I4: ; IAC_STATE == 4 (in SB na $FF)
        CMP #$F0
        BEQ FTB_I0
        LDA #3
        STA IAC_STATE
        RTS

S1_SEND_END:
        JSR SPI_AND_INC_S1
        JSR W5500_CS_HI
        JMP S1_FLUSH_SEND

; ============================================================================
; 75x20 ANSI Kleurenterminal Emulator (SGR 16-Kleur, 2D Cursor, Scroll, CP437)
; ============================================================================
APPLY_THEME_COLOR:
        LDX THEME_IDX
        LDA THEME_PAL,X
        STA CUR_FG
        LDA #0
        STA CUR_BOLD
        RTS

CLEAR_TERM:
        JSR APPLY_THEME_COLOR
        LDA #0
        STA CUR_X
        STA CUR_Y
        STA ANSI_STATE
        LDX #0
CT_RL:  TXA
        JSR CALC_TERM_ROW
        JSR CLEAR_ROW_PTR
        INX
        CPX #TERM_ROWS
        BCC CT_RL
        RTS

CLEAR_ROW_PTR:
        LDY #TERM_COLS
        LDA #0
        STA (ZP_LINE_LO),Y
        DEY
CRP_L:  LDA #' '
        STA (ZP_LINE_LO),Y
        LDA CUR_FG
        STA (ZP_COL_LO),Y
        DEY
        BPL CRP_L
        RTS

; ZP_LINE = $3000 + A * 128, ZP_COL = $4000 + A * 128
CALC_TERM_ROW:
        LSR A
        PHA
        LDA #0
        ROR A
        STA ZP_LINE_LO
        STA ZP_COL_LO
        PLA
        PHA
        CLC
        ADC #>TERM_CHARS
        STA ZP_LINE_HI
        PLA
        CLC
        ADC #>TERM_COLORS
        STA ZP_COL_HI
        RTS

SCROLL_TERM_UP:
        LDX #0
STU_L:  TXA
        JSR CALC_TERM_ROW
        LDA ZP_LINE_LO
        STA ZP_PTR_LO
        LDA ZP_LINE_HI
        STA ZP_PTR_HI
        LDA ZP_COL_LO
        STA ZP_X_LO
        LDA ZP_COL_HI
        STA ZP_X_HI
        INX
        TXA
        JSR CALC_TERM_ROW
        LDY #TERM_COLS
STU_C:  LDA (ZP_LINE_LO),Y
        STA (ZP_PTR_LO),Y
        LDA (ZP_COL_LO),Y
        STA (ZP_X_LO),Y
        DEY
        BPL STU_C
        CPX #TERM_ROWS-1
        BCC STU_L
        JMP CLEAR_ROW_PTR

TERM_CRLF:
        LDA #0
        STA CUR_X
TERM_LF:
        INC CUR_Y
        LDA CUR_Y
        CMP #TERM_ROWS
        BCC TLF_R
        LDA #TERM_ROWS-1
        STA CUR_Y
        JMP SCROLL_TERM_UP
TLF_R:  RTS

TERM_PRINT_STR:
        STA ZP_SRC_LO
        STY ZP_SRC_HI
TPS_CONT:
        LDY #0
        LDA (ZP_SRC_LO),Y
        INC ZP_SRC_LO
        BNE TPS_1
        INC ZP_SRC_HI
TPS_1:  CMP #0
        BEQ TLF_R
        JSR TERM_PUT_BYTE
        JMP TPS_CONT

TERM_PUT_BYTE:
        LDX ANSI_STATE
        BNE TPB_ANSI

        CMP #$1B
        BNE TPB_NO_ESC
        LDA #1
        STA ANSI_STATE
        RTS

TPB_NO_ESC:
        CMP #$0C
        BEQ CLEAR_TERM
        CMP #$0D
        BNE TPB_NL
        LDA #0
        STA CUR_X
        RTS
TPB_NL: CMP #$0A
        BEQ TERM_LF
        CMP #$08
        BNE TPB_TAB
        LDA CUR_X
        BEQ TLF_R
        DEC CUR_X
        RTS
TPB_TAB:
        CMP #$09
        BNE TPB_CH
        LDA CUR_X
        AND #$F8
        CLC
        ADC #8
        CMP #TERM_COLS
        BCC TPB_TX
        LDA #TERM_COLS-1
TPB_TX: STA CUR_X
        RTS

TPB_CH: CMP #' '
        BCC TLF_R
        CMP #$7F
        BCC TPB_PR
        JSR MAP_CP437_CHAR
TPB_PR: PHA
        LDA CUR_Y
        JSR CALC_TERM_ROW
        LDY CUR_X
        PLA
        STA (ZP_LINE_LO),Y
        LDA CUR_FG
        STA (ZP_COL_LO),Y
        INY
        CPY #TERM_COLS
        BCC TPB_AX
        LDA #0
        STA CUR_X
        JMP TERM_LF
TPB_AX: STY CUR_X
        RTS

MAP_CP437_CHAR:
        LDY #'#'
        CMP #$DB
        BCS MCC_S
        LDY #'|'
        CMP #$B3
        BEQ MCC_S
        CMP #$BA
        BEQ MCC_S
        LDY #'-'
        CMP #$C4
        BEQ MCC_S
        LDY #'+'
MCC_S:  TYA
        RTS

; --- ANSI Escape / CSI Parser (ESC [ p0 ; p1 ; p2 cmd) ---
TPB_ANSI:
        DEX
        BNE TPB_A2
        ; ANSI_STATE == 1 (net na ESC)
        CMP #'['
        BNE TPB_APC
        LDA #2
        STA ANSI_STATE
        LDA #0
        STA CSI_IDX
        STA CSI_P0
        STA CSI_P1
        STA CSI_P2
        RTS
TPB_APC:
        CMP #'_'
        BNE TPB_A_RST
        LDA #3
        STA ANSI_STATE
        RTS
TPB_SET_A1:
        LDA #1
        STA ANSI_STATE
        RTS
TPB_A_RST:
        LDA #0
        STA ANSI_STATE
        RTS

TPB_A2: DEX
        BNE TPB_APC_SKP
TPB_CSI:
        CMP #'?'
        BEQ TPB_CRTS
        JSR IS_DIGIT_SUB0
        BCC TPB_C_ND
        TAY
        LDX CSI_IDX
        LDA CSI_P0,X
        ASL A
        STA TMP_A
        ASL A
        ASL A
        CLC
        ADC TMP_A
        STA CSI_P0,X
        TYA
        CLC
        ADC CSI_P0,X
        STA CSI_P0,X
TPB_CRTS:
        RTS

TPB_APC_SKP:
        CMP #$1B
        BEQ TPB_SET_A1
        CMP #$07
        BEQ TPB_A_RST
        RTS

TPB_C_ND:
        CMP #$3B                ; ';'
        BNE TPB_C_CMD
        LDX CSI_IDX
        CPX #2
        BCS TPB_CRTS
        INC CSI_IDX
        RTS

TPB_C_CMD:
        LDX #0
        STX ANSI_STATE
        CMP #'m'
        BEQ ANSI_DO_SGR_J
        CMP #'J'
        BEQ ANSI_DO_J
        CMP #'K'
        BEQ ANSI_DO_K
        CMP #'H'
        BEQ ANSI_DO_H
        CMP #'f'
        BEQ ANSI_DO_H
        CMP #'A'
        BEQ ANSI_DO_A
        CMP #'B'
        BEQ ANSI_DO_B
        CMP #'C'
        BEQ ANSI_DO_C
        CMP #'D'
        BEQ ANSI_DO_D
        CMP #'s'
        BEQ ANSI_DO_S
        CMP #'u'
        BEQ ANSI_DO_U
        CMP #'n'
        BEQ ANSI_DO_N
        RTS
ANSI_DO_SGR_J:
        JMP ANSI_DO_SGR

ANSI_DO_N:
        LDA CSI_P0
        CMP #6
        BNE ADJ_R
        LDX #0
        LDY IAC_TX_LEN
ADN_L:  CPY #40
        BCS ADJ_R
        LDA STR_CPR_REPLY,X
        BEQ ADN_D
        STA IAC_TX_BUF,Y
        INY
        INX
        BNE ADN_L
ADN_D:  STY IAC_TX_LEN
        RTS

ANSI_DO_J:
        LDA CSI_P0
        CMP #2
        BNE ADJ_R
        JMP CLEAR_TERM
ADJ_R:  RTS

ANSI_DO_K:
        LDA CUR_Y
        JSR CALC_TERM_ROW
        LDY CUR_X
ADK_L:  CPY #TERM_COLS
        BCS ADJ_R
        LDA #' '
        STA (ZP_LINE_LO),Y
        LDA CUR_FG
        STA (ZP_COL_LO),Y
        INY
        BNE ADK_L
        RTS

ANSI_DO_H:
        LDA CSI_P0
        BEQ ADH_Y0
        SEC
        SBC #1
ADH_Y0: JSR CLAMP_SET_Y
        LDA CSI_P1
        BEQ CLAMP_SET_X
        SEC
        SBC #1
CLAMP_SET_X:
        CMP #TERM_COLS
        BCC ADH_XS
        LDA #TERM_COLS-1
ADH_XS: STA CUR_X
        RTS

CLAMP_SET_Y:
        CMP #TERM_ROWS
        BCC ADH_YS
        LDA #TERM_ROWS-1
ADH_YS: STA CUR_Y
        RTS

ANSI_GET_STEP:
        LDA CSI_P0
        BNE AGS_R
        LDA #1
AGS_R:  RTS

ANSI_DO_A:
        JSR ANSI_GET_STEP
        STA TMP_A
        LDA CUR_Y
        SEC
        SBC TMP_A
        BCS ADH_YS
        LDA #0
        BEQ ADH_YS

ANSI_DO_B:
        JSR ANSI_GET_STEP
        CLC
        ADC CUR_Y
        JMP CLAMP_SET_Y

ANSI_DO_C:
        JSR ANSI_GET_STEP
        CLC
        ADC CUR_X
        JMP CLAMP_SET_X

ANSI_DO_D:
        JSR ANSI_GET_STEP
        STA TMP_A
        LDA CUR_X
        SEC
        SBC TMP_A
        BCS ADH_XS
        LDA #0
        BEQ ADH_XS

ANSI_DO_S:
        LDA CUR_X
        STA SAV_X
        LDA CUR_Y
        STA SAV_Y
        RTS

ANSI_DO_U:
        LDA SAV_X
        STA CUR_X
        LDA SAV_Y
        STA CUR_Y
        RTS

ANSI_DO_SGR:
        LDX #0
ADS_LP: LDA CSI_P0,X
        BNE ADS_1
        JSR APPLY_THEME_COLOR
        JMP ADS_NX
ADS_1:  CMP #1
        BNE ADS_22
        LDA #8
        STA CUR_BOLD
        BNE ADS_NX
ADS_22: CMP #22
        BNE ADS_30
        LDA #0
        STA CUR_BOLD
        BEQ ADS_NX
ADS_30: CMP #30
        BCC ADS_NX
        CMP #38
        BCS ADS_90
        SBC #30
        ORA CUR_BOLD
        TAY
        LDA ANSI_PAL,Y
        STA CUR_FG
        JMP ADS_NX
ADS_90: CMP #90
        BCC ADS_NX
        CMP #98
        BCS ADS_NX
        SBC #90-8
        TAY
        LDA ANSI_PAL,Y
        STA CUR_FG
ADS_NX: CPX CSI_IDX
        BCS ADS_R
        INX
        BNE ADS_LP
ADS_R:  RTS

; ============================================================================
; Ingebouwd BBS-Telefoonboek Scherm
; ============================================================================
SHOW_PHONEBOOK:
        LDA #ST_KIES
        STA STATUS_IDX
        JSR CLEAR_TERM
        LDA #<PB_HDR
        LDY #>PB_HDR
        JSR TERM_PRINT_STR
        LDA #'1'
        STA TMP_B
SPB_LP: LDA #1
        STA CUR_X
        LDA #$FC
        STA CUR_FG
        LDA #'['
        JSR TERM_PUT_BYTE
        LDA TMP_B
        JSR TERM_PUT_BYTE
        LDA #']'
        JSR TERM_PUT_BYTE
        LDA #6
        STA CUR_X
        LDA #$FF
        STA CUR_FG
        JSR TPS_CONT
        LDA #36
        STA CUR_X
        LDA #$1C
        STA CUR_FG
        JSR TPS_CONT
        JSR TERM_CRLF
        INC TMP_B
        LDA TMP_B
        CMP #'7'
        BCC SPB_LP
        JMP TPS_CONT

; ============================================================================
; UDP DNS-Resolver (Poort 53) & W5500 Socket 1 Driver
; ============================================================================
IS_DIGIT_SUB0:
        CMP #'0'
        BCC IDS_R
        CMP #'9'+1
        BCS IDS_N
        SBC #$2F
        RTS
IDS_N:  CLC
IDS_R:  RTS

ADD_PORT_DIGIT:
        PHA
        LDA PORT_ACC_LO
        ASL A
        STA TMP_A
        LDA PORT_ACC_HI
        ROL A
        STA TMP_B
        LDA TMP_A
        ASL A
        STA PORT_ACC_LO
        LDA TMP_B
        ROL A
        STA PORT_ACC_HI
        ASL PORT_ACC_LO
        ROL PORT_ACC_HI
        CLC
        LDA PORT_ACC_LO
        ADC TMP_A
        STA PORT_ACC_LO
        LDA PORT_ACC_HI
        ADC TMP_B
        STA PORT_ACC_HI
        PLA
        CLC
        ADC PORT_ACC_LO
        STA PORT_ACC_LO
        BCC APD_R
        INC PORT_ACC_HI
APD_R:  RTS

TRY_PARSE_IPV4:
        LDY #0
        LDX #0
TPI_O:  LDA #0
        STA PORT_ACC_LO
        STA PORT_ACC_HI
        LDA HOST_BUF,Y
        JSR IS_DIGIT_SUB0
        BCC TPI_F
TPI_LP: JSR ADD_PORT_DIGIT
        LDA PORT_ACC_HI
        BNE TPI_F
        INY
        LDA HOST_BUF,Y
        JSR IS_DIGIT_SUB0
        BCS TPI_LP
        LDA PORT_ACC_LO
        STA DEST_IP0,X
        LDA HOST_BUF,Y
        BEQ TPI_E
        CMP #'.'
        BNE TPI_F
        INY
        INX
        CPX #4
        BCC TPI_O
TPI_F:  CLC
        RTS
TPI_E:  CPX #3
        BNE TPI_F
        SEC
        RTS

DNS_RESOLVE:
        JSR TRY_PARSE_IPV4
        BCS DNS_OK_R
        LDA DEST_PORT_LO
        PHA
        LDA DEST_PORT_HI
        PHA
        LDX #3
DR_G1:  LDA W5500_INIT_TBL+4,X
        STA DEST_IP0,X
        DEX
        BPL DR_G1
        JSR DNS_QUERY_ONCE
        BCS DR_REST
        LDA #1
        LDX #3
DR_G2:  STA DEST_IP0,X
        DEX
        BPL DR_G2
        JSR DNS_QUERY_ONCE
DR_REST:
        PLA
        STA DEST_PORT_HI
        PLA
        STA DEST_PORT_LO
DNS_OK_R:
        RTS

DNS_QUERY_ONCE:
        LDX #11
        LDA #0
DQ_C:   STA DNS_BUF,X
        DEX
        BPL DQ_C
        LDA IO_RND
        STA DNS_BUF
        LDA #1
        STA DNS_BUF+2
        STA DNS_BUF+5

        LDX #12
        LDY #0
DQ_LB:  STX TMP_A
        INX
        LDA #0
        STA TMP_B
DQ_CH:  LDA HOST_BUF,Y
        BEQ DQ_LE
        INY
        CMP #'.'
        BEQ DQ_LE
        STA DNS_BUF,X
        INX
        INC TMP_B
        CPX #140
        BCC DQ_CH
DQ_LE:  PHA
        LDX TMP_A
        LDA TMP_B
        STA DNS_BUF,X
        CLC
        ADC TMP_A
        ADC #1
        TAX
        PLA
        BNE DQ_LB

        LDY #0
DQ_TL:  LDA DNS_TAIL_TBL,Y
        STA DNS_BUF,X
        INX
        INY
        CPY #5
        BCC DQ_TL
        STX S1_LEN_LO
        LDA #0
        STA DEST_PORT_HI
        LDA #53
        STA DEST_PORT_LO

        LDA #$02
        JSR S1_OPEN_DEST
        JSR S1_TX_PTR_HDR
        LDX #0
DQ_TX:  LDA DNS_BUF,X
        JSR SPI_AND_INC_S1
        INX
        CPX S1_LEN_LO
        BCC DQ_TX
        JSR W5500_CS_HI
        JSR S1_FLUSH_SEND

        LDX #120
DQ_WT:  STX TMP_A
        JSR S1_GET_RX_LEN
        BNE DQ_GOT
        JSR DELAY_10MS
        LDX TMP_A
        DEX
        BNE DQ_WT
DQ_FAIL:
        JSR S1_CLOSE
        CLC
        RTS

DQ_GOT: LDA S1_LEN_HI
        BNE DQ_CL
        LDA S1_LEN_LO
        CMP #192
        BCC DQ_RL
DQ_CL:  LDA #192
DQ_RL:  STA TMP_B
        JSR S1_READ_PTR_HDR
        LDX #0
DQ_RX:  LDA #0
        JSR SPI_BRAM_STUB
        STA DNS_BUF,X
        INX
        CPX TMP_B
        BCC DQ_RX
        JSR W5500_CS_HI
        JSR S1_CLOSE

        LDA DNS_BUF+11
        AND #$0F
        BNE DQ_FAIL
        LDA DNS_BUF+14
        ORA DNS_BUF+15
        BEQ DQ_FAIL
        LDA DNS_BUF+15
        STA TMP_B

        LDX #20
DQ_SQ:  CPX #176
        BCS DQ_FAIL
        LDA DNS_BUF,X
        INX
        CMP #0
        BNE DQ_SQ
        INX
        INX
        INX
        INX

DQ_AN:  CPX #176
        BCS DQ_FAIL
        LDA DNS_BUF,X
        BEQ DQ_N0
        CMP #$C0
        BCC DQ_NL
        INX
        INX
        BNE DQ_AT
DQ_NL:  CLC
        ADC #1
        STA TMP_A
        TXA
        ADC TMP_A
        TAX
        BCC DQ_AN
        BCS DQ_FAIL
DQ_N0:  INX

DQ_AT:  LDA DNS_BUF,X
        BNE DQ_SK
        LDA DNS_BUF+1,X
        CMP #1
        BNE DQ_SK
        LDA DNS_BUF+9,X
        CMP #4
        BNE DQ_SK
        LDY #0
DQ_CP:  LDA DNS_BUF+10,X
        STA DEST_IP0,Y
        INX
        INY
        CPY #4
        BCC DQ_CP
        SEC
        RTS

DQ_SK:  CLC
        TXA
        ADC #10
        ADC DNS_BUF+9,X
        TAX
        BCS DQ_FAIL
        DEC TMP_B
        BNE DQ_AN
        BEQ DQ_FAIL

S1_OPEN_DEST:
        PHA
        JSR S1_CLOSE
        PLA
        LDX #$00
        JSR W5500_WR_S1
        INC LOCAL_PORT
        BNE S1O_P
        INC LOCAL_PORT
S1O_P:  LDA #$C8
        STA S1_PTR_HI
        LDA LOCAL_PORT
        STA S1_PTR_LO
        LDA #$04
        LDY #$01
        JSR S1_PTR_CMD
        LDA #$0C
        LDY #$2C
        JSR W5500_HDR_0
        LDY #0
S1D_L:  LDA DEST_IP0,Y
        JSR SPI_BRAM_STUB
        INY
        CPY #6
        BCC S1D_L
        JMP W5500_CS_HI

S1_CLOSE:
        LDA #$10
S1_CMD: LDX #$01
        JSR W5500_WR_S1
S1_CW:  LDA #$01
        JSR W5500_RD_S1
        BNE S1_CW
        RTS

S1_FLUSH_SEND:
        LDA #$24
        LDY #$20
S1_PTR_CMD:
        STY TMP_A
        LDY #$2C
        JSR W5500_HDR_0
        LDA S1_PTR_HI
        JSR SPI_BRAM_STUB
        LDA S1_PTR_LO
        JSR SPI_BRAM_STUB
        JSR W5500_CS_HI
        LDA TMP_A
        BNE S1_CMD

S1_TX_PTR_HDR:
        LDA #$24
        LDY #$34
        BNE S1_PTR_HDR
S1_READ_PTR_HDR:
        LDA #$28
        LDY #$38
S1_PTR_HDR:
        STY TMP_A
        PHA
        JSR W5500_RD_S1
        STA S1_PTR_HI
        PLA
        CLC
        ADC #1
        JSR W5500_RD_S1
        STA S1_PTR_LO
        LDX S1_PTR_HI
        LDY TMP_A
        JMP W5500_HDR

W5500_INIT_HW:
        LDX #6
WIH_CP: LDA W5500_STUB_BYTES,X
        STA SPI_BRAM_STUB,X
        DEX
        BPL WIH_CP
        LDA #$03
        STA IO_NET_CTRL
        JSR W5500_PROBE_HW
        BNE WIH_R
        LDA #$0F
        JSR W5500_RD_CREG
        CMP #192
        BNE WIH_W
        LDA #$12
        JSR W5500_RD_CREG
        STA W5500_INIT_TBL+21
        LDA #$0E
        JSR W5500_RD_CREG
        STA W5500_INIT_TBL+17
WIH_W:  LDA #$02
        STA IO_NET_CTRL
        LDX #0
WIH_L:  LDA W5500_INIT_TBL,X
        JSR SPI_BRAM_STUB
        INX
        CPX #22
        BCC WIH_L
        JMP W5500_CS_HI
WIH_R:  RTS

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

W5500_RD_S1:
        LDY #$28
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

W5500_WR_S1:
        PHA
        TXA
        LDY #$2C
        JSR W5500_HDR_0
        PLA
        JSR SPI_BRAM_STUB
        JMP W5500_CS_HI

SPI_AND_INC_S1:
        JSR SPI_BRAM_STUB
        INC S1_PTR_LO
        BNE SAIS_R
        INC S1_PTR_HI
SAIS_R: RTS

S1_GET_RX_LEN:
        LDA #$26
        JSR W5500_RD_S1
        STA S1_LEN_HI
        LDA #$27
        JSR W5500_RD_S1
        STA S1_LEN_LO
        ORA S1_LEN_HI
        RTS

; ============================================================================
; Grafische 640x360 BBS-Term UI op MiniGPU ($A020)
; ============================================================================
SET_XY_COL:
        STA ZP_Y_LO
        STX ZP_COLOR
        STY ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        RTS

SEND_STREAM_X:
        LDY GPU_STREAMS,X
SSX_L:  INX
        LDA GPU_STREAMS,X
        STA IO_GPU
        DEY
        BNE SSX_L
        RTS

DRAW_SCREEN:
        LDX #GS_UI - GPU_STREAMS
        JSR SEND_STREAM_X
        JSR DRAW_TOP_BARS

        LDA #46
        STA TMP_B               ; Y_LO (loopt van 46 tot 46 + 19*14 = 312)
        LDA #0
        STA ZP_Y_HI
        STA TMP_A               ; Rij 0..19

DS_ROW: LDA TMP_A
        JSR CALC_TERM_ROW
        LDA TMP_B
        STA ZP_Y_LO
        LDA #12
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI

        LDY #0
DS_COL: LDA (ZP_COL_LO),Y
        STA ZP_COLOR
        LDA (ZP_LINE_LO),Y
        BEQ DS_RNX
        JSR DRAW_CHAR_ADV
        INY
        CPY #TERM_COLS
        BCC DS_COL

DS_RNX: LDA TMP_A
        CMP CUR_Y
        BNE DS_NXT
        ; Teken cursorblok '_' op (CUR_X, CUR_Y)
        LDA #0
        STA ZP_X_HI
        LDA CUR_X
        ASL A
        ROL ZP_X_HI
        ASL A
        ROL ZP_X_HI
        ASL A
        ROL ZP_X_HI
        CLC
        ADC #12
        STA ZP_X_LO
        BCC DS_C1
        INC ZP_X_HI
DS_C1:  LDA #$FC
        STA ZP_COLOR
        LDA #'_'
        JSR DRAW_CHAR_ADV

DS_NXT: CLC
        LDA TMP_B
        ADC #14
        STA TMP_B
        BCC DS_N1
        INC ZP_Y_HI
DS_N1:  INC TMP_A
        LDA TMP_A
        CMP #TERM_ROWS
        BCC DS_ROW

        LDA #$5B
        LDX #$FF
        LDY #12
        JSR SET_XY_COL
        INC ZP_Y_HI
        LDA #<STR_BOT_PB
        LDY #>STR_BOT_PB
        LDX CONN_STATE
        BEQ DS_BOT
        LDA #<STR_BOT_ON
        LDY #>STR_BOT_ON
DS_BOT: JMP DRAW_STR_AY

DRAW_TOP_BARS:
        LDX #GS_URL - GPU_STREAMS
        JSR SEND_STREAM_X

        LDA #4
        LDX #$FC
        LDY #10
        JSR SET_XY_COL
        LDA #<STR_APP_TITLE
        LDY #>STR_APP_TITLE
        JSR DRAW_STR_AY

        JSR W5500_PROBE_HW
        JSR DRAW_LED_ONLY

        LDA #24
        LDX #$FF
        LDY #14
        JSR SET_XY_COL

        LDA EDIT_MODE
        BEQ DTB_SH
        LDA #$FC
        STA ZP_COLOR
        LDA #<STR_DIAL_PROMPT
        LDY #>STR_DIAL_PROMPT
        BNE DTB_P1
DTB_SH: LDA #$1F
        STA ZP_COLOR
        LDA #<STR_HOST_LBL
        LDY #>STR_HOST_LBL
DTB_P1: JSR DRAW_STR_AY
        LDA #$FF
        STA ZP_COLOR
        LDA #<DIAL_BUF
        LDY #>DIAL_BUF
        LDX #50
        JSR DRAW_STR_N
        LDA EDIT_MODE
        BEQ DTB_ST
        LDA #$FC
        STA ZP_COLOR
        LDA #'_'
        JSR DRAW_CHAR_ADV

DTB_ST: LDA #$48
        STA ZP_X_LO
        LDA #$02
        STA ZP_X_HI
        LDY #$1C
        LDX STATUS_IDX
        CPX #ST_FOUT
        BNE DTB_S1
        LDY #$E0
        BNE DTB_SC
DTB_S1: CPX #ST_ONLN
        BEQ DTB_SC
        LDY #$FC
DTB_SC: STY ZP_COLOR
        LDY #4
DTB_SL: LDA STATUS_TBL,X
        JSR DRAW_CHAR_ADV
        INX
        DEY
        BNE DTB_SL
        RTS

DRAW_LED_ONLY:
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

DRAW_STR_AY:
        LDX #75
DRAW_STR_N:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDY #0
DST_L:  LDA (ZP_PTR_LO),Y
        BEQ DST_R
        JSR DRAW_CHAR_ADV
        INY
        DEX
        BNE DST_L
DST_R:  RTS

DRAW_CHAR_ADV:
        CMP #' '+1
        BCC ADV_X8
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
ADV_X8: CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCA_R
        INC ZP_X_HI
DCA_R:  RTS

DELAY_10MS:
        LDA IO_TIMER
D10_W:  CMP IO_TIMER
        BEQ D10_W
        RTS

; ============================================================================
; Kleurenpaletten, Tabellen, GPU-Streams & Ingebouwd BBS-Telefoonboek
; ============================================================================
; 16-Kleuren ANSI RGB332 Palet (0..7 normaal, 8..15 bright/bold):
;   0=Zwart/Grijs, 1=Rood, 2=Groen, 3=Geel/Bruin, 4=Blauw, 5=Magenta, 6=Cyaan, 7=Wit
ANSI_PAL:
        .BYTE $49, $A0, $14, $AC, $0A, $A2, $16, $B6
        .BYTE $92, $E0, $1C, $FC, $5F, $F3, $1F, $FF

THEME_PAL:      .BYTE $FF, $1C, $F4, $1F
ANSI_DIRS:      .BYTE 'A', 'B', 'D', 'C'

W5500_STUB_BYTES:
        STA IO_NET_DATA
        LDA IO_NET_DATA
        RTS

W5500_INIT_TBL:
        .BYTE $00, $00, $04, $00
        .BYTE 192, 168, 178, 1
        .BYTE 255, 255, 255, 0
        .BYTE $02, $65, $02, $20, $00, $03
        .BYTE 192, 168, 178, 202

DNS_TAIL_TBL:   .BYTE $00, $00, $01, $00, $01

PRESET_PTRS:
        .WORD P_BBS1, P_BBS2, P_BBS3, P_BBS4, P_BBS5, P_BBS6

STR_CPR_REPLY:
        .BYTE 27, "[20", $3B, "75R", 0

GPU_STREAMS:
GS_UI:
        .BYTE GS_URL - GS_UI - 1
        .BYTE 12, 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 0
        .BYTE 1, $00
        .BYTE 2, 0,0, 0,0, $80,$02, 15,0, $21
        .BYTE 2, 5,0, 41,0, $76,$02, $2B,$01, $1F
        .BYTE 2, 6,0, 42,0, $74,$02, $29,$01, $00
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $21
GS_URL:
        .BYTE GS_LED - GS_URL - 1
        .BYTE 2, 5,0, 17,0, $76,$02, 22,0, $01
        .BYTE 2, 9,0, 18,0, $36,$02, 20,0, $1F
        .BYTE 2, 10,0, 19,0, $34,$02, 18,0, $00
GS_LED:
        .BYTE GS_EXIT - GS_LED - 1
        .BYTE 5, $72,$02, 7,0, 4,0, 0,0
GS_EXIT:
        .BYTE STR_APP_TITLE - GS_EXIT - 1
        .BYTE 12, 1, 1, $E3

STR_APP_TITLE:   .ASCIIZ "BBS-Term 1.0 - 6502 W5500 ANSI/Telnet Client"
STR_HOST_LBL:    .ASCIIZ "BBS: "
STR_DIAL_PROMPT: .ASCIIZ "Kies: "
STATUS_TBL:      .BYTE "KIESDNS.BEL.ONLNFOUT"

STR_DIALING:     .ASCIIZ ">> Bel "
STR_CONNECTED:   .ASCIIZ ">> VERBONDEN! (` of F9 = Ophangen)"
STR_DISCONN:     .ASCIIZ ">> Verbroken (1-6=Bel, D=Adres, P=Boek)"
STR_ERR_NET:     .ASCIIZ "!! GEEN LINK !!"
STR_ERR_DNS:     .ASCIIZ "!! DNS FOUT !!"
STR_ERR_TCP:     .ASCIIZ "!! TCP FOUT !!"

STR_BOT_PB:      .ASCIIZ "1-6:Bel BBS  D:Host:Poort  C:Kleur  E:Echo  P:Boek  Q:Stop"
STR_BOT_ON:      .ASCIIZ "LIVE BBS: Typ + ESC naar BBS! (` / F9 / Ctrl+X = Ophangen)"

PB_HDR:
        .BYTE 27, "[96m=== MINIGPU 6502 ANSI/TELNET BBS TELEFOONBOEK (W5500) ===", 13, 10, 13, 10, 0
P_BBS1: .ASCIIZ "telehack.com:23"
        .ASCIIZ "Telehack ARPANET/BBS/Zork"
P_BBS2: .ASCIIZ "blackflag.acid.org:23"
        .ASCIIZ "ACiD Black Flag Mystic BBS"
P_BBS3: .ASCIIZ "vert.synchro.net:23"
        .ASCIIZ "Vertrauen (Synchronet BBS)"
P_BBS4: .ASCIIZ "particlesbbs.dyndns.org:6400"
        .ASCIIZ "Particles! Retro/C64 BBS"
P_BBS5: .ASCIIZ "20forbeers.com:1337"
        .ASCIIZ "20 For Beers ANSI BBS"
P_BBS6: .ASCIIZ "192.168.178.200:23"
        .ASCIIZ "Tang Nano #1 (NETTERM)"
PB_FTR:
        .BYTE 13, 10
        .BYTE 27, "[96m [D] ", 27, "[37mEigen Host:Poort (bijv. bbs.fozztexx.com:23)", 13, 10
        .BYTE 27, "[96m [C] ", 27, "[37mFosfor-kleur  ", 27, "[96m[E] ", 27, "[37mLocal Echo  ", 27, "[96m[P] ", 27, "[37mBoek", 13, 10, 13, 10
        .BYTE 27, "[92mToets [1]-[6] om te bellen of [D] voor eigen adres!", 13, 10, 0
