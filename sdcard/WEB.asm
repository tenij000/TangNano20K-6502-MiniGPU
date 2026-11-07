; ============================================================================
; WEB.asm - MiniGPU WebSurf 1.2 (Echte 6502 + W5500 HTTP/HTML Webbrowser!)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC op $9000).
;   - Interactieve URL-adresbalk (U = bewerk URL, N = nieuwe http:// URL)
;   - Web-Zoekfunctie (Z = zoek direct via http://wiby.me/?q=...)
;   - Echte UDP DNS-Resolver op W5500 (Poort 53: Router .1 + 1.1.1.1 fallback)
;   - Streaming TCP HTTP/1.0 Client (tot 6 KB per pagina in SDRAM $3000..$47FF)
;   - 6502 HTML-Parser (<title>, <h1>-<h4>, <hr>, <li>, word-wrap, entities)
;     met tot 15 klikbare <a href> links ([1]-[9] of Pijl L/R + ENTER)!
;   - Terug (B), Herladen (R), Startpagina (H) & HTTP/HTML Broncode (V)
; Starten vanuit Midnight Commander (BRUN MC) of in BASIC met: BRUN WEB
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

; --- Zero Page ($60..$87: veilig naast BASIC en MC!) ---
ZP_PTR_LO       = $60
ZP_PTR_HI       = $61
ZP_SRC_LO       = $62
ZP_SRC_HI       = $63
ZP_LINE_LO      = $64
ZP_LINE_HI      = $65
ZP_X_LO         = $66
ZP_X_HI         = $67
ZP_Y_LO         = $68
ZP_Y_HI         = $69
ZP_COLOR        = $6A

S1_PTR_LO       = $6B
S1_PTR_HI       = $6C
TAG_C0          = $6B           ; Gedeeld tijdens RENDER_DOC (geen S1 SPI actief)
TAG_C1          = $6C
ROW_Y_LO        = $6B           ; Gedeeld tijdens DRAW_BROWSER
ROW_Y_HI        = $6C
S1_LEN_LO       = $6D
S1_LEN_HI       = $6E

W5500_VER       = $6F
W5500_PHY       = $70
HTTP_STATE      = $71           ; 0=Home, 1=OK, 2/3=Fout, 4=Laadt
VIEW_MODE       = $72           ; 0=Webpagina, 1=Broncode
EDIT_MODE       = $73           ; 0=Bladeren, 1=URL/Zoekbalk actief
EDIT_LEN        = $74
SCROLL_TOP      = $75
TOTAL_LINES     = $76
LINK_CNT        = $77
CUR_COL         = $78
CUR_LCLR        = $79
CUR_LNK         = $7A
LAST_SPC        = $7B
LOCAL_PORT      = $7C
PREV_JOY        = $7D
SEL_LINK        = $7E
TAG_CLOSE       = $7F
; Volgorde $80..$85 matcht exact W5500 Sn_DIPR0..3 ($0C..$0F) + Sn_DPORT0..1 ($10..$11)!
DEST_IP0        = $80
DEST_IP1        = $81
DEST_IP2        = $82
DEST_IP3        = $83
DEST_PORT_HI    = $84
DEST_PORT_LO    = $85
TMP_A           = $86
TMP_B           = $87

; --- SDRAM Buffers ($3000..$5B9F en $6000..$79FF: laat MC $5BE0..$5FFF vrij!) ---
RAW_BUF         = $3000         ; 6 KB HTTP + HTML ontvangstbuffer ($3000..$47FF)
RAW_BUF_END_HI  = $48           ; $4800 gebruikt als veilige NUL-guard pagina
LINK_TBL_HI     = $48           ; $4900..$57FF = 15 links (1..15) x 256 bytes
URL_BUF         = $5800
PREV_URL        = $5900
PATH_BUF        = $5A00
DNS_BUF         = $5B00

DOC_LINES       = $6000         ; 96 geformatteerde regels x 64 bytes ($6000..$77FF)
HOST_BUF        = $7800
TITLE_BUF       = $7840
IN_TITLE        = $78C0
TITLE_LEN       = $78C1
HTTP_CODE       = $78C4
EDIT_BUF        = $7900         ; Page-aligned voor snelle STRCPY_PAGE

; ============================================================================
; Start & Hoofdlus
; ============================================================================
START:
        JSR ROM_SILENCE
        LDA #0
        STA IO_MODE
        STA ZP_Y_HI
        STA VIEW_MODE
        STA EDIT_MODE
        STA PREV_URL

        LDA IO_RND
        ORA #$01
        STA LOCAL_PORT

        JSR W5500_INIT_HW
        JSR GO_HOME_PAGE
        LDA IO_JOY
        STA PREV_JOY

MAIN_LOOP:
        JSR DRAW_BROWSER

WAIT_LOOP:
        JSR DELAY_10MS

        LDA IO_STATUS
        BPL CHK_JOY
        LDA IO_TERM
        LDA EDIT_MODE
        BEQ EXIT_TO_BASIC
        LDA #0
        STA EDIT_MODE
        BEQ MAIN_LOOP

EXIT_TO_BASIC:
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
        BEQ CHK_KEY
        LDA EDIT_MODE
        BNE CHK_KEY

        LDA IO_STATUS
        AND #1
        BEQ CJ_B
        LDA IO_TERM
        CMP #$0D
        BEQ OPEN_SEL_LINK
CJ_B:   TYA
        LSR A
        BCS DO_SCR_UP
        LSR A
        BCS DO_SCR_DN
        LSR A
        BCS DO_PRV_LNK
        LSR A
        BCS DO_NXT_LNK
        LSR A
        BCS OPEN_SEL_LINK
WAIT_J1:
        JMP WAIT_LOOP

DO_SCR_UP:
        LDA SCROLL_TOP
        BEQ WAIT_J1
        DEC SCROLL_TOP
MAIN_J1:
        JMP MAIN_LOOP

DO_PAGE_DN:
        LDX #10
        BNE DPD_L
DO_SCR_DN:
        LDX #1
DPD_L:  LDA SCROLL_TOP
        CLC
        ADC #18
        CMP TOTAL_LINES
        BCS DPD_N
        INC SCROLL_TOP
DPD_N:  DEX
        BNE DPD_L
        BEQ MAIN_J1

DO_PRV_LNK:
        LDA LINK_CNT
        BEQ WAIT_J1
        DEC SEL_LINK
        BNE DNL_SC
        STA SEL_LINK
        BNE DNL_SC

DO_NXT_LNK:
        LDA LINK_CNT
        BEQ WAIT_J1
        INC SEL_LINK
        CMP SEL_LINK
        BCS DNL_SC
        LDA #1
        STA SEL_LINK
DNL_SC: JSR SCROLL_TO_LINK
        JMP MAIN_LOOP

OPEN_SEL_LINK:
        LDA SEL_LINK
OPEN_LINK_A:
        BEQ WAIT_J1
        CMP LINK_CNT
        BCC OSL_1
        BNE WAIT_J1
OSL_1:  STA SEL_LINK
        JSR SAVE_PREV_URL
        LDA SEL_LINK
        CLC
        ADC #LINK_TBL_HI
        TAY
        LDA #0
        JSR RESOLVE_HREF
        JMP DO_RELOAD

; ============================================================================
; Toetsenbord & URL/Zoek-invoer
; ============================================================================
CHK_KEY:
        LDA IO_STATUS
        AND #1
        BEQ WAIT_J1
        LDA IO_TERM
        LDX EDIT_MODE
        BNE KEY_EDIT

        CMP #'1'
        BCC KB_TB0
        CMP #'9'+1
        BCS KB_TB0
        SEC
        SBC #'0'
        BNE OPEN_LINK_A

KB_TB0: CMP #'A'
        BCC KB_LP0
        CMP #'Z'+1
        BCS KB_LP0
        ORA #$20
KB_LP0: LDX #15
KB_TB:  CMP KEY_CHARS,X
        BEQ KB_HT
        DEX
        BPL KB_TB
WAIT_J2:
        JMP WAIT_LOOP

KB_HT:  LDA KEY_HND_HI,X
        PHA
        LDA KEY_HND_LO,X
        PHA
        RTS

DO_TOGGLE_VIEW:
        LDA VIEW_MODE
        EOR #1
        STA VIEW_MODE
        JSR RENDER_DOC
        JMP MAIN_LOOP

DO_HOME:
        JSR SAVE_PREV_URL
        JSR GO_HOME_PAGE
        JMP MAIN_LOOP

DO_BACK:
        LDA PREV_URL
        BEQ WAIT_J2
        LDA #<PREV_URL
        LDY #>PREV_URL
        LDX #>URL_BUF
        JSR STRCPY_PAGE
        LDA #0
        STA PREV_URL
DO_RELOAD:
        JSR NAVIGATE_URL
SE_DN:  JMP MAIN_LOOP

KEY_EDIT:
        CMP #$0D
        BEQ SUBMIT_EDIT
        CMP #$08
        BEQ EDIT_BS
        CMP #$7F
        BEQ EDIT_BS
        CMP #' '
        BCC WAIT_J2
        BNE KE_CH
        LDA #'+'
KE_CH:  CMP #$7F
        BCS WAIT_J2
        LDX EDIT_LEN
        CPX #64
        BCS WAIT_J2
        STA EDIT_BUF,X
        INX
        BNE KE_UP
EDIT_BS:
        LDX EDIT_LEN
        BEQ WAIT_J2
        DEX
KE_UP:  STX EDIT_LEN
        LDA #0
        STA EDIT_BUF,X
        JSR DRAW_URL_BAR
        JMP WAIT_LOOP

START_EDIT_URL:
        LDA #<URL_BUF
        LDY #>URL_BUF
        BNE SEU_F
START_SEARCH:
        LDA #<STR_SEARCH_URL
        LDY #>STR_SEARCH_URL
        BNE SEU_F
START_NEW_URL:
        LDA #<STR_HTTP_PFX
        LDY #>STR_HTTP_PFX
SEU_F:  LDX #>EDIT_BUF
        JSR STRCPY_PAGE
        CPY #64
        BCC SEU_D
        LDY #64
        LDA #0
        STA EDIT_BUF+64
SEU_D:  STY EDIT_LEN
        LDA #1
        STA EDIT_MODE
        JMP MAIN_LOOP

SUBMIT_EDIT:
        LDA #0
        STA EDIT_MODE
        LDA EDIT_LEN
        BEQ SE_DN
        JSR SAVE_PREV_URL
        LDA #<EDIT_BUF
        STA ZP_PTR_LO
        LDA #>EDIT_BUF
        STA ZP_PTR_HI
        LDX #0
        LDA EDIT_BUF+4
        CMP #':'
        BEQ SE_CP
        LDA EDIT_BUF+5
        CMP #':'
        BEQ SE_CP
        JSR PUT_HTTP_PFX
SE_CP:  JSR RH_APX
        JMP DO_RELOAD

SAVE_PREV_URL:
        LDA #<URL_BUF
        LDY #>URL_BUF
        LDX #>PREV_URL
STRCPY_PAGE:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        STX ZP_SRC_HI
        LDY #0
        STY ZP_SRC_LO
SCP_L:  LDA (ZP_PTR_LO),Y
        STA (ZP_SRC_LO),Y
        BEQ SCP_R
        INY
        CPY #254
        BCC SCP_L
        LDA #0
        STA (ZP_SRC_LO),Y
SCP_R:  RTS

SCROLL_TO_LINK:
        LDX #0
        TXA
        JSR CALC_DOC_ROW
STL_L:  CPX TOTAL_LINES
        BCS SCP_R
        LDY #62
        LDA (ZP_LINE_LO),Y
        CMP SEL_LINK
        BEQ STL_F
        JSR ADV_LINE_PTR
        INX
        BNE STL_L
        RTS
STL_F:  TXA
        CPX SCROLL_TOP
        BCC STL_S
        SBC #17
        BCC SCP_R
        CMP SCROLL_TOP
        BCC SCP_R
STL_S:  STA SCROLL_TOP
        RTS

; ============================================================================
; Home, HREF Resolver & URL/IPv4 Parser
; ============================================================================
PUT_HTTP_PFX:
        LDX #0
PHP_L:  LDA STR_HTTP_PFX,X
        BEQ PHP_R
        STA URL_BUF,X
        INX
        BNE PHP_L
PHP_R:  RTS

SET_CODE_AY:
        STA HTTP_CODE
        STY HTTP_CODE+1
        LDA #0
        STA HTTP_CODE+2
        RTS

GO_HOME_PAGE:
        LDA #<STR_ABOUT_HOME
        LDY #>STR_ABOUT_HOME
        LDX #>URL_BUF
        JSR STRCPY_PAGE
        LDA #'O'
        LDY #'K'
        JSR SET_CODE_AY
        LDX #0
        LDA #<HOME_HTML
        LDY #>HOME_HTML
        STA ZP_PTR_LO
        STY ZP_PTR_HI
LOAD_HTML_PTR:
        STX HTTP_STATE
        LDA #<RAW_BUF
        STA ZP_SRC_LO
        LDA #>RAW_BUF
        STA ZP_SRC_HI
        LDY #0
        STY VIEW_MODE
LHA_L:  LDA (ZP_PTR_LO),Y
        STA (ZP_SRC_LO),Y
        BEQ LHA_D
        INY
        BNE LHA_L
        INC ZP_PTR_HI
        INC ZP_SRC_HI
        BNE LHA_L
LHA_D:  JMP RENDER_DOC

RESOLVE_HREF:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDX #0
        LDY #4
        LDA (ZP_PTR_LO),Y
        CMP #':'
        BEQ RH_APX
        INY
        LDA (ZP_PTR_LO),Y
        CMP #':'
        BNE RH_NABS
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #'a'
        BEQ RH_APX
        JSR PUT_HTTP_PFX
        LDY #8
        BNE RH_APL

RH_NABS:
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #'#'
        BEQ RH_RTS
        PHA
        CMP #'/'
        BNE RH_BASE
        INY
        LDA (ZP_PTR_LO),Y
        CMP #'/'
        BNE RH_BASE
        PLA
        JSR PUT_HTTP_PFX
        LDX #5
        BNE RH_APX

RH_BASE:
        LDY #0
        STY TMP_A
        STY TMP_B
RH_CP:  LDA PREV_URL,Y
        STA URL_BUF,Y
        BEQ RH_CPD
        CMP #'/'
        BNE RH_CPN
        CPY #7
        BCC RH_CPN
        LDA TMP_A
        BNE RH_CP1
        STY TMP_A
RH_CP1: INY
        STY TMP_B
        BNE RH_CP
RH_CPN: INY
        BNE RH_CP

RH_CPD: LDX TMP_A
        BNE RH_SLK
        STY TMP_A
        LDA #'/'
        STA URL_BUF,Y
        INY
        STY TMP_B
RH_SLK: PLA
        LDX TMP_B
        CMP #'/'
        BNE RH_APX
        LDX TMP_A

RH_APX: LDY #0
RH_APL: LDA (ZP_PTR_LO),Y
        STA URL_BUF,X
        BEQ RH_RTS
        INY
        INX
        CPX #254
        BCC RH_APL
        LDA #0
        STA URL_BUF+254
RH_RTS: RTS

NAVIGATE_URL:
        LDA URL_BUF
        CMP #'a'
        BEQ GO_HOME_PAGE
        LDA #4
        STA HTTP_STATE
        LDA #0
        STA VIEW_MODE
        LDA #'.'
        LDY #'.'
        JSR SET_CODE_AY
        JSR DRAW_URL_BAR

        JSR PARSE_URL
        JSR W5500_PROBE_HW
        LDA W5500_VER
        CMP #$04
        BNE NAV_OFF
        LDA W5500_PHY
        AND #$01
        BEQ NAV_OFF

        JSR TRY_PARSE_IPV4
        BCS NAV_HTTP

        LDX #3                  ; DNS #1: Router 192.168.178.1
NAV_D1: LDA W5500_INIT_TBL+4,X
        STA DEST_IP0,X
        DEX
        BPL NAV_D1
        JSR DNS_QUERY_ONCE
        BCS NAV_HTTP

        LDX #3                  ; DNS #2: Cloudflare 1.1.1.1
        LDA #1
NAV_D2: STA DEST_IP0,X
        DEX
        BPL NAV_D2
        JSR DNS_QUERY_ONCE
        BCS NAV_HTTP

        LDA #<STR_ERR_DNS
        LDY #>STR_ERR_DNS
        BNE LOAD_ERR

NAV_OFF:
        LDA #<STR_ERR_NET
        LDY #>STR_ERR_NET
        BNE LOAD_ERR

NAV_HTTP:
        LDA #0
        STA DEST_PORT_HI
        LDA #80
        STA DEST_PORT_LO
        JSR HTTP_FETCH
        BCS NAV_OK
        LDA #<STR_ERR_HTTP
        LDY #>STR_ERR_HTTP
LOAD_ERR:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDA #'E'
        LDY #'R'
        JSR SET_CODE_AY
        LDX #3
        JMP LOAD_HTML_PTR

NAV_OK: LDA #1
        STA HTTP_STATE
        JMP RENDER_DOC

; --- PARSE_URL: haalt HOST_BUF en PATH_BUF uit URL_BUF ---
PARSE_URL:
        LDX #0
        STX HOST_BUF
        LDA URL_BUF+4
        CMP #':'
        BNE PU_C5
        LDX #7
        BNE PU_HO
PU_C5:  LDA URL_BUF+5
        CMP #':'
        BNE PU_HO
        LDX #8
PU_HO:  LDY #0
PU_HL:  LDA URL_BUF,X
        BEQ PU_HD
        CMP #'/'
        BEQ PU_HD
        CMP #'?'
        BEQ PU_HD
        CMP #':'
        BNE PU_HS
        LDY #62
        BNE PU_HN
PU_HS:  CPY #62
        BCS PU_HN
        STA HOST_BUF,Y
        INY
        LDA #0
        STA HOST_BUF,Y
PU_HN:  INX
        BNE PU_HL
PU_HD:  LDY #0
        LDA URL_BUF,X
        CMP #'/'
        BEQ PU_CP
        LDA #'/'
        STA PATH_BUF
        INY
        LDA URL_BUF,X
        BEQ PU_TM
PU_CP:  LDA URL_BUF,X
        STA PATH_BUF,Y
        BEQ PU_R
        INX
        INY
        CPY #252
        BCC PU_CP
PU_TM:  LDA #0
        STA PATH_BUF,Y
PU_R:   RTS

TRY_PARSE_IPV4:
        LDX #0
        LDY #0
TPI_O:  LDA #0
        STA TMP_A
        STA TMP_B
TPI_D:  LDA HOST_BUF,X
        BEQ TPI_DT
        CMP #'.'
        BEQ TPI_DT
        CMP #'0'
        BCC TPI_N
        CMP #'9'+1
        BCS TPI_N
        SEC
        SBC #'0'
        STA S1_LEN_LO
        LDA TMP_A
        ASL A
        STA TMP_A
        ASL A
        ASL A
        ADC TMP_A
        ADC S1_LEN_LO
        STA TMP_A
        INC TMP_B
        INX
        BNE TPI_D
TPI_DT: LDA TMP_B
        BEQ TPI_N
        CPY #4
        BCS TPI_N
        LDA TMP_A
        STA DEST_IP0,Y
        INY
        LDA HOST_BUF,X
        BEQ TPI_E
        INX
        BNE TPI_O
TPI_E:  CPY #4
        BNE TPI_N
        SEC
        RTS
TPI_N:  CLC
        RTS

; ============================================================================
; W5500 SPI, UDP DNS (Poort 53) & Streaming TCP HTTP/1.0 Client (Socket 1)
; ============================================================================
W5500_INIT_HW:
        LDX #6
WIH_S:  LDA W5500_STUB_BYTES,X
        STA SPI_BRAM_STUB,X
        DEX
        BPL WIH_S

        JSR W5500_PROBE_HW
        LDA W5500_VER
        CMP #$04
        BNE WIH_R

        ; Behoud bestaand IP & MAC van deze Tang Nano (.200 op #1 / .201 op #2)
        LDA #$0F
        JSR W5500_RD_CREG
        CMP #192
        BNE WIH_W
        LDA #$12
        JSR W5500_RD_CREG
        BEQ WIH_W
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
        LDA #$39
        JSR W5500_RD_CREG
        STA W5500_VER
        LDA #$2E
        JSR W5500_RD_CREG
        STA W5500_PHY
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

S1_CLOSE:
        LDX #$01
        LDA #$10
        JMP W5500_WR_S1

S1_BEGIN_TX:
        LDA #$24
        LDY #$34
        BNE S1_BB
S1_BEGIN_RX:
        LDA #$28
        LDY #$38
S1_BB:  STY TMP_B
        PHA
        JSR W5500_RD_S1
        STA S1_PTR_HI
        PLA
        CLC
        ADC #1
        JSR W5500_RD_S1
        STA S1_PTR_LO
        LDX S1_PTR_HI
        LDY TMP_B
        JMP W5500_HDR

S1_COMMIT_TX:
        LDX #$24
        LDY #$20
S1_FINISH_IO:
        STY TMP_B
        JSR W5500_CS_HI
        TXA
        LDY #$2C
        JSR W5500_HDR_0
        LDA S1_PTR_HI
        JSR SPI_BRAM_STUB
        LDA S1_PTR_LO
        JSR SPI_BRAM_STUB
        JSR W5500_CS_HI
        LDX #$01
        LDA TMP_B
        JMP W5500_WR_S1

S1_OPEN_DEST:
        PHA
        JSR S1_CLOSE
        LDX #$02
        LDA #$FF
        JSR W5500_WR_S1
        INC LOCAL_PORT
        BNE SOD_1
        INC LOCAL_PORT
SOD_1:  LDX #$00
        PLA
        JSR W5500_WR_S1
        LDX #$04
        LDA #$C4
        JSR W5500_WR_S1
        LDX #$05
        LDA LOCAL_PORT
        JSR W5500_WR_S1
        LDA #$0C
        LDY #$2C
        JSR W5500_HDR_0
        LDX #0
SOD_I:  LDA DEST_IP0,X
        JSR SPI_BRAM_STUB
        INX
        CPX #6
        BCC SOD_I
        JSR W5500_CS_HI
        LDX #$01
        LDA #$01
        JMP W5500_WR_S1

DNS_QUERY_ONCE:
        LDA #0
        STA DEST_PORT_HI
        LDA #53
        STA DEST_PORT_LO
        LDA #$02
        JSR S1_OPEN_DEST
        JSR DELAY_10MS

        LDA #0
        LDX #11
DQ_HD:  STA DNS_BUF,X
        DEX
        BPL DQ_HD
        LDA #$65
        STA DNS_BUF
        INC DNS_BUF+2
        INC DNS_BUF+5

        LDX #0
        LDY #12
DQ_LB:  STY TMP_A
        INY
DQ_CH:  LDA HOST_BUF,X
        BEQ DQ_EH
        INX
        CMP #'.'
        BEQ DQ_DT
        STA DNS_BUF,Y
        INY
        CPY #140
        BCC DQ_CH
DQ_DT:  JSR DQ_SL
        JMP DQ_LB

DQ_EH:  JSR DQ_SL
        LDX #0
DQ_TL:  LDA DNS_TAIL_TBL,X
        STA DNS_BUF,Y
        INY
        INX
        CPX #5
        BCC DQ_TL
        STY S1_LEN_LO

        JSR S1_BEGIN_TX
        LDY #0
DQ_TX:  LDA DNS_BUF,Y
        JSR SPI_AND_INC_S1
        INY
        CPY S1_LEN_LO
        BCC DQ_TX
        JSR S1_COMMIT_TX

        LDA #40
        STA TMP_A
DQ_WT:  JSR S1_GET_RX_LEN
        BNE DQ_GT
        JSR DELAY_10MS
        DEC TMP_A
        BNE DQ_WT
DQ_FL:  JSR S1_CLOSE
        CLC
        RTS

DQ_SL:  TYA
        CLC
        SBC TMP_A
        STX TMP_B
        LDX TMP_A
        STA DNS_BUF,X
        LDX TMP_B
        RTS

DQ_GT:  JSR S1_BEGIN_RX
        LDY #0
DQ_RX:  LDA #0
        JSR SPI_BRAM_STUB
        STA DNS_BUF,Y
        INY
        CPY #156
        BCC DQ_RX
        JSR W5500_CS_HI
        JSR S1_CLOSE

        LDA DNS_BUF+8
        CMP #$65
        BNE DQ_NO
        LDA DNS_BUF+11
        AND #$0F
        BNE DQ_NO
        LDA DNS_BUF+15
        STA TMP_B
        BEQ DQ_NO

        LDY #20
        JSR DNS_SKIP_NAME
        INY
        INY
        INY
        INY
DQ_AN:  CPY #142
        BCS DQ_NO
        JSR DNS_SKIP_NAME
        LDA DNS_BUF,Y
        BNE DQ_NX
        LDA DNS_BUF+1,Y
        CMP #1
        BNE DQ_NX
        LDA DNS_BUF+9,Y
        CMP #4
        BNE DQ_NX
        LDX #0
DQ_C4:  LDA DNS_BUF+10,Y
        STA DEST_IP0,X
        INY
        INX
        CPX #4
        BCC DQ_C4
        SEC
        RTS
DQ_NX:  TYA
        CLC
        ADC #10
        BCS DQ_NO
        ADC DNS_BUF+9,Y
        BCS DQ_NO
        TAY
        DEC TMP_B
        BNE DQ_AN
DQ_NO:  CLC
        RTS

DNS_SKIP_NAME:
        CPY #150
        BCS DSN_R
        LDA DNS_BUF,Y
        BEQ DSN_Z
        AND #$C0
        CMP #$C0
        BEQ DSN_P
        TYA
        CLC
        ADC DNS_BUF,Y
        TAY
        INY
        BNE DNS_SKIP_NAME
DSN_P:  INY
DSN_Z:  INY
DSN_R:  RTS

HTTP_FETCH:
        LDA #$21
        JSR S1_OPEN_DEST
        JSR DELAY_10MS
        LDA #$03
        JSR W5500_RD_S1
        CMP #$13
        BNE HF_FAIL

        LDX #$01
        LDA #$04
        JSR W5500_WR_S1
        LDA #90
        STA TMP_A
HF_WE:  LDA #$03
        JSR W5500_RD_S1
        CMP #$17
        BEQ HF_RQ
        CMP #$1C
        BEQ HF_RQ
        CMP #$00
        BEQ HF_FAIL
        JSR DELAY_10MS
        DEC TMP_A
        BNE HF_WE
HF_FAIL:
        JMP DQ_FL

HF_RQ:  JSR S1_BEGIN_TX
        LDX #0
HF_TPL: LDA STR_HTTP_REQ,X
        BEQ HF_TPD
        INX
        CMP #3
        BCS HF_TPC
        LDY #>PATH_BUF
        CMP #1
        BEQ HF_TPS
        LDY #>HOST_BUF
HF_TPS: STY ZP_PTR_HI
        LDA #0
        STA ZP_PTR_LO
        TAY
HF_TPB: LDA (ZP_PTR_LO),Y
        BEQ HF_TPL
        JSR SPI_AND_INC_S1
        INY
        BNE HF_TPB
HF_TPC: JSR SPI_AND_INC_S1
        JMP HF_TPL
HF_TPD: JSR S1_COMMIT_TX

        LDA #<RAW_BUF
        STA ZP_SRC_LO
        LDA #>RAW_BUF
        STA ZP_SRC_HI
        LDA #130
        STA TMP_A

HF_RL:  JSR S1_GET_RX_LEN
        BEQ HF_ID

        LDA #40
        STA TMP_A
        LDA S1_LEN_HI
        BNE HF_C8
        LDA S1_LEN_LO
        CMP #128
        BCC HF_GC
HF_C8:  LDA #128
HF_GC:  STA S1_LEN_LO
        JSR S1_BEGIN_RX
        LDY #0
HF_CL:  LDA #0
        JSR SPI_AND_INC_S1
        LDX ZP_SRC_HI
        CPX #RAW_BUF_END_HI
        BCS HF_SK
        STA (ZP_SRC_LO),Y
        INC ZP_SRC_LO
        BNE HF_SK
        INC ZP_SRC_HI
HF_SK:  DEC S1_LEN_LO
        BNE HF_CL

        LDX #$28
        LDY #$40
        JSR S1_FINISH_IO

        LDA ZP_SRC_HI
        CMP #RAW_BUF_END_HI
        BCC HF_RL
        BCS HF_OK

HF_ID:  LDA #$03
        JSR W5500_RD_S1
        CMP #$1C
        BEQ HF_CG
        CMP #$00
        BEQ HF_CG
        JSR DELAY_10MS
        DEC TMP_A
        BNE HF_RL

HF_CG:  LDA ZP_SRC_HI
        CMP #>RAW_BUF
        BNE HF_OK
        LDA ZP_SRC_LO
        BNE HF_OK
        JMP DQ_FL

HF_OK:  LDY #0
        TYA
        STA (ZP_SRC_LO),Y
        JSR S1_CLOSE
        SEC
        RTS

; ============================================================================
; 6502 HTML / JSON / Broncode Parser & Word-Wrapper
; ============================================================================
CALC_DOC_ROW:
        LDY #0
        STY ZP_LINE_LO
        LSR A
        ROR ZP_LINE_LO
        LSR A
        ROR ZP_LINE_LO
        ORA #>DOC_LINES
        STA ZP_LINE_HI
        RTS

ADV_LINE_PTR:
        CLC
        LDA ZP_LINE_LO
        ADC #64
        STA ZP_LINE_LO
        BCC ALP_R
        INC ZP_LINE_HI
ALP_R:  RTS

INIT_NEW_ROW:
        LDA TOTAL_LINES
        JSR CALC_DOC_ROW
        LDA #0
        TAY
        STA (ZP_LINE_LO),Y
        STA CUR_COL
        LDA #1
        STA LAST_SPC
FL_UPD_ATTR:
        LDY #62
        LDA CUR_LNK
        STA (ZP_LINE_LO),Y
        INY
        LDA CUR_LCLR
        STA (ZP_LINE_LO),Y
        RTS

FLUSH_LINE:
        LDA CUR_COL
        BEQ FL_UPD_ATTR
        LDY CUR_COL
        LDA #0
        STA (ZP_LINE_LO),Y
        LDA TOTAL_LINES
        CMP #94
        BCS FL_MX
        INC TOTAL_LINES
FL_MX:  JMP INIT_NEW_ROW

EMIT_SPC:
        LDA #' '
EMIT_CHAR:
        LDX IN_TITLE
        BEQ EC_BD
        LDX TITLE_LEN
        CPX #46
        BCS EC_R0
        STA TITLE_BUF,X
        INX
        STX TITLE_LEN
        LDA #0
        STA TITLE_BUF,X
EC_R0:  RTS

EC_BD:  LDY CUR_COL
        CPY #60
        BCC EC_ST
        CMP #' '
        BEQ FLUSH_LINE
        PHA
        LDY #59
EC_FS:  LDA (ZP_LINE_LO),Y
        CMP #' '
        BEQ EC_SP
        DEY
        CPY #40
        BCS EC_FS
        LDY #60

EC_SP:  LDA TOTAL_LINES
        CMP #94
        BCS EC_PP
        LDA #0
        STA (ZP_LINE_LO),Y
        STY TMP_A
        LDA ZP_LINE_LO
        STA ZP_PTR_LO
        LDA ZP_LINE_HI
        STA ZP_PTR_HI
        INC TOTAL_LINES
        JSR INIT_NEW_ROW
        LDY TMP_A
EC_CPW: INY
        CPY #60
        BCS EC_PL
        LDA (ZP_PTR_LO),Y
        STY TMP_A
        LDY CUR_COL
        JSR EC_S1
        LDY TMP_A
        BNE EC_CPW
EC_PL:  PLA
        LDY CUR_COL
EC_ST:  CMP #' '
        BNE EC_S1
        CPY #0
        BEQ EC_R
EC_S1:  STA (ZP_LINE_LO),Y
        INY
        STY CUR_COL
        LDA #0
        STA (ZP_LINE_LO),Y
EC_R:   RTS
EC_PP:  PLA
        RTS

NEXT_SRC_CHAR:
        LDY #0
        LDA (ZP_SRC_LO),Y
        BEQ NSC_E
        INC ZP_SRC_LO
        BNE NSC_O
        INC ZP_SRC_HI
NSC_O:  SEC
        RTS
NSC_E:  CLC
        RTS

RENDER_DOC:
        LDA #0
        STA SCROLL_TOP
        STA TOTAL_LINES
        STA LINK_CNT
        STA SEL_LINK
        STA CUR_LNK
        STA TITLE_LEN
        LDA #1
        STA IN_TITLE

        LDY #0
RD_PF:  LDA STR_APP_NAME,Y
        BEQ RD_PF1
        JSR EMIT_CHAR
        INY
        BNE RD_PF
RD_PF1: LDY #0
RD_HT:  LDA HOST_BUF,Y
        BEQ RD_IN
        JSR EMIT_CHAR
        INY
        BNE RD_HT

RD_IN:  LDA #0
        STA IN_TITLE
        LDA #$FF
        LDX VIEW_MODE
        BEQ RD_CO
        LDA #$1C
RD_CO:  STA CUR_LCLR
        JSR INIT_NEW_ROW
        LDA #<RAW_BUF
        STA ZP_SRC_LO
        LDA #>RAW_BUF
        STA ZP_SRC_HI

        LDA VIEW_MODE
        BNE RD_PLAIN_LOOP

        LDA RAW_BUF
        CMP #'H'
        BNE RD_CHK_HTML
        LDA RAW_BUF+4
        CMP #'/'
        BNE RD_CHK_HTML
        LDX #2
RD_HC:  LDA RAW_BUF+9,X
        STA HTTP_CODE,X
        DEX
        BPL RD_HC
        LDA #0
        STA HTTP_CODE+3

RD_HD:  JSR NEXT_SRC_CHAR
RD_HD1: BCC RD_FINISH
        CMP #$0A
        BNE RD_HD
        JSR NEXT_SRC_CHAR
        BCC RD_FINISH
        CMP #$0D
        BNE RD_HD2
        JSR NEXT_SRC_CHAR
        BCC RD_FINISH
RD_HD2: CMP #$0A
        BNE RD_HD1

RD_CHK_HTML:
        LDY #0
RD_FL:  LDA (ZP_SRC_LO),Y
        BEQ RD_PLAIN_LOOP
        CMP #'<'
        BEQ RD_HTML_LOOP
        INY
        CPY #240
        BCC RD_FL

RD_PLAIN_LOOP:
        LDA TOTAL_LINES
        CMP #94
        BCS RD_FINISH
        JSR NEXT_SRC_CHAR
        BCC RD_FINISH
        CMP #$0A
        BNE RD_PC
        JSR FLUSH_LINE
        JMP RD_PLAIN_LOOP
RD_PC:  CMP #$20
        BCC RD_PLAIN_LOOP
        CMP #$7F
        BCS RD_PLAIN_LOOP
        JSR EMIT_CHAR
        JMP RD_PLAIN_LOOP

RD_FINISH:
        LDA CUR_COL
        BEQ RDF_1
        INC TOTAL_LINES
RDF_1:  LDA TOTAL_LINES
        BNE RDF_2
        INC TOTAL_LINES
RDF_2:  LDA LINK_CNT
        BEQ RDF_R
        LDA #1
        STA SEL_LINK
RDF_R:  RTS

RD_HTML_LOOP:
        LDA TOTAL_LINES
        CMP #94
        BCS RD_FINISH
        JSR NEXT_SRC_CHAR
        BCC RD_FINISH
        CMP #'<'
        BNE RHL_1
        JSR PARSE_HTML_TAG
        JMP RD_HTML_LOOP
RHL_1:  CMP #'&'
        BNE RHL_2
        JSR PARSE_ENTITY
        JMP RD_HTML_LOOP
RHL_2:  CMP #$80
        BCS RD_HTML_LOOP
        CMP #' '+1
        BCS RHL_P
        LDA LAST_SPC
        BNE RD_HTML_LOOP
        JSR EMIT_SPC
        LDA #1
        STA LAST_SPC
        BNE RD_HTML_LOOP
RHL_P:  JSR EMIT_CHAR
        LDA #0
        STA LAST_SPC
        BEQ RD_HTML_LOOP

PARSE_ENTITY:
        LDY #0
        LDA (ZP_SRC_LO),Y
        ORA #$20
        LDX #4
PE_TB:  CMP ENT_KEYS,X
        BEQ PE_HT
        DEX
        BPL PE_TB
        LDA #' '
        BNE PE_EM
PE_HT:  LDA ENT_VALS,X
PE_EM:  JSR EMIT_CHAR
        LDA #0
        STA LAST_SPC
        LDX #8
PE_SK:  JSR NEXT_SRC_CHAR
        BCC RDF_R
        CMP #$3B
        BEQ RDF_R
        DEX
        BNE PE_SK
        RTS

NSC_IN_TAG:
        JSR NEXT_SRC_CHAR
        BCC NIT_E
        CMP #'>'
        BEQ NIT_G
        SEC
        RTS
NIT_G:  INC TMP_B
NIT_E:  CLC
        RTS

SKIP_TO_GT:
        LDA TMP_B
        BNE STG_R
STG_L:  JSR NSC_IN_TAG
        BCS STG_L
STG_R:  RTS

PARSE_HTML_TAG:
        LDA #0
        STA TAG_CLOSE
        STA TMP_B
        STA TAG_C0
        STA TAG_C1
        JSR NSC_IN_TAG
        BCC STG_R
        CMP #'!'
        BNE PHT_N1
        LDY #0
        LDA (ZP_SRC_LO),Y
        CMP #'-'
        BNE SKIP_TO_GT
PHT_C:  JSR NEXT_SRC_CHAR
        BCC STG_R
        CMP #'-'
        BNE PHT_C
        LDY #1
        LDA (ZP_SRC_LO),Y
        CMP #'>'
        BNE PHT_C
        JMP STG_L

PHT_N1: CMP #'/'
        BNE PHT_RN
        INC TAG_CLOSE
        JSR NSC_IN_TAG
        BCC STG_R

PHT_RN: LDX #0
PHT_NL: CMP #' '+1
        BCC PHT_ND
        CMP #'/'
        BEQ PHT_ND
        ORA #$20
        CPX #2
        BCS PHT_NN
        STA TAG_C0,X
        INX
PHT_NN: JSR NSC_IN_TAG
        BCS PHT_NL
PHT_ND:
        LDA TAG_C0
        CMP #'a'
        BNE PHT_SKR
        LDA TAG_C1
        ORA TAG_CLOSE
        BNE PHT_SKR
        LDA LINK_CNT
        CMP #15
        BCS PHT_SKR
        JMP PHT_FH

PHT_SKR:
        JSR SKIP_TO_GT
        LDA TAG_C0
        LDX TAG_C1
        CMP #'a'
        BNE PHT_CT
        LDA CUR_LNK
        BNE PHT_BLK
        RTS

PHT_CT: CMP #'t'
        BNE PHT_CS
        CPX #'i'
        BNE PHT_TR
        LDA TAG_CLOSE
        EOR #1
        STA IN_TITLE
        BEQ PHT_DR
        LDA #9
        STA TITLE_LEN
PHT_DR: RTS
PHT_TR: CPX #'r'
        BEQ PHT_BLK
        CPX #'d'
        BEQ PHT_TD
        CPX #'h'
        BNE PHT_DR
PHT_TD: JMP EMIT_SPC

PHT_CS: CMP #'s'
        BNE PHT_CH2
        LDA TAG_CLOSE
        BNE PHT_DR
        CPX #'c'
        BEQ PHT_SB
        CPX #'t'
        BNE PHT_DR
PHT_SB: JSR NEXT_SRC_CHAR
        BCC PHT_DR
        CMP #'<'
        BNE PHT_SB
        LDY #0
        LDA (ZP_SRC_LO),Y
        CMP #'/'
        BNE PHT_SB
        INY
        LDA (ZP_SRC_LO),Y
        ORA #$20
        CMP #'s'
        BNE PHT_SB
        JMP STG_L

PHT_BLK:
        LDX #0
        LDA #$FF
PHT_BLX:
        STX TMP_A
        PHA
        JSR FLUSH_LINE
        LDA TMP_A
        STA CUR_LNK
        PLA
        STA CUR_LCLR
        JMP FL_UPD_ATTR

PHT_CH2:
        CMP #'h'
        BNE PHT_CL2
        CPX #'r'
        BEQ PHT_HR
        CPX #'1'
        BCC PHT_R2
        CPX #'5'
        BCS PHT_R2
        LDY TAG_CLOSE
        BNE PHT_BLK
        LDX #0
        LDA #$FC
        BNE PHT_BLX

PHT_HR: LDX #0
        LDA #$1F
        JSR PHT_BLX
        LDY #40
        LDA #0
        STA (ZP_LINE_LO),Y
        STY CUR_COL
        DEY
        LDA #'-'
PHT_HL: STA (ZP_LINE_LO),Y
        DEY
        BPL PHT_HL
        BMI PHT_BLK

PHT_CL2:
        CMP #'l'
        BNE PHT_CB
        CPX #'i'
        BNE PHT_R2
        JSR PHT_BLK
        LDA TAG_CLOSE
        BNE PHT_R2
        LDA #'*'
        JSR EMIT_CHAR
        JMP EMIT_SPC

PHT_CB: CMP #'b'
        BNE PHT_CB2
        CPX #'r'
        BEQ PHT_BLK
PHT_R2: RTS

PHT_CB2:
        LDY #3
PHT_BT: CMP BLK_TAGS,Y
        BEQ PHT_BLK
        DEY
        BPL PHT_BT
        RTS

PHT_FH: JSR NSC_IN_TAG
        BCC PHT_R1
        ORA #$20
        CMP #'h'
        BNE PHT_FH
        LDY #0
        LDA (ZP_SRC_LO),Y
        ORA #$20
        CMP #'r'
        BNE PHT_FH
PHT_WE: JSR NSC_IN_TAG
        BCC PHT_R1
        CMP #'='
        BNE PHT_WE
PHT_WV: JSR NSC_IN_TAG
        BCC PHT_R1
        CMP #' '+1
        BCC PHT_WV

        LDX #0
        CMP #$22
        BEQ PHT_QT
        CMP #$27
        BEQ PHT_QT
        STX TMP_A
        BNE PHT_NK
PHT_R1: RTS

PHT_QT: STA TMP_A
        JSR NSC_IN_TAG
        BCC PHT_R1

PHT_NK: PHA
        INC LINK_CNT
        LDA LINK_CNT
        CLC
        ADC #LINK_TBL_HI
        STA ZP_PTR_HI
        LDA #0
        STA ZP_PTR_LO
        STA S1_LEN_LO
        PLA

PHT_CH: LDX TMP_A
        BEQ PHT_UQ
        CMP TMP_A
        BEQ PHT_HE
        BNE PHT_HC
PHT_UQ: CMP #' '+1
        BCC PHT_HE
PHT_HC: CMP #'&'
        BNE PHT_SH
        LDY #3
        LDA (ZP_SRC_LO),Y
        CMP #$3B
        BNE PHT_SA
        LDX #4
PHT_SL: JSR NEXT_SRC_CHAR
        DEX
        BNE PHT_SL
PHT_SA: LDA #'&'
PHT_SH: LDY S1_LEN_LO
        CPY #250
        BCS PHT_NH
        STA (ZP_PTR_LO),Y
        INY
        STY S1_LEN_LO
PHT_NH: JSR NSC_IN_TAG
        BCS PHT_CH

PHT_HE: JSR SKIP_TO_GT
        LDY S1_LEN_LO
        LDA #0
        STA (ZP_PTR_LO),Y
        LDX CUR_COL
        CPX #2
        BNE PHT_NB
        LDY #0
        LDA (ZP_LINE_LO),Y
        CMP #'*'
        BNE PHT_NB
        STY CUR_COL
PHT_NB: LDX LINK_CNT
        LDA #$1F
        JSR PHT_BLX
        LDA LINK_CNT
        CMP #10
        BCC PHT_D9
        ADC #6
PHT_D9: ADC #'0'
        STA LINK_PFX+1
        LDY #4
PHT_LP: LDA LINK_PFX,Y
        STA (ZP_LINE_LO),Y
        DEY
        BPL PHT_LP
        LDA #4
        STA CUR_COL
        RTS

; ============================================================================
; Grafische 640x360 Browser UI op MiniGPU ($A020)
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

DRAW_BROWSER:
        LDX #GS_UI - GPU_STREAMS
        JSR SEND_STREAM_X

        LDA #4
        LDX #$FC
        LDY #10
        JSR SET_XY_COL
        LDA #<TITLE_BUF
        LDY #>TITLE_BUF
        JSR DRAW_STR_AY

        JSR W5500_PROBE_HW
        LDX #GS_LED - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #$E0
        LDX W5500_VER
        CPX #$04
        BNE DB_LC
        LDA W5500_PHY
        AND #$01
        BEQ DB_LY
        LDA #$1C
        BNE DB_LC
DB_LY:  LDA #$FC
DB_LC:  STA IO_GPU

        JSR DRAW_URL_BAR

        LDA SCROLL_TOP
        JSR CALC_DOC_ROW
        LDA #48
        STA ROW_Y_LO
        LDA #0
        STA ROW_Y_HI
        STA TMP_A
DB_RL:  LDA SCROLL_TOP
        CLC
        ADC TMP_A
        CMP TOTAL_LINES
        BCS DB_BT

        LDA ROW_Y_LO
        STA ZP_Y_LO
        LDA ROW_Y_HI
        STA ZP_Y_HI

        LDY #62
        LDA (ZP_LINE_LO),Y
        BEQ DB_NC
        CMP SEL_LINK
        BNE DB_NC

        LDA ROW_Y_LO
        SEC
        SBC #2
        STA SEL_BAR_Y
        LDA ROW_Y_HI
        SBC #0
        STA SEL_BAR_Y+1
        LDX #GS_SEL - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #$FC
        BNE DB_DL

DB_NC:  LDY #63
        LDA (ZP_LINE_LO),Y
DB_DL:  STA ZP_COLOR
        LDA #14
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA ZP_LINE_LO
        LDY ZP_LINE_HI
        JSR DRAW_STR_AY

        JSR ADV_LINE_PTR
        CLC
        LDA ROW_Y_LO
        ADC #15
        STA ROW_Y_LO
        BCC DB_RN
        INC ROW_Y_HI
DB_RN:  INC TMP_A
        LDA TMP_A
        CMP #19
        BCC DB_RL

DB_BT:  LDA #$5B
        LDX #$FF
        LDY #8
        JSR SET_XY_COL
        INC ZP_Y_HI
        LDA #<STR_BOT_HELP
        LDY #>STR_BOT_HELP
        JMP DRAW_STR_AY

DRAW_URL_BAR:
        LDX #GS_URL - GPU_STREAMS
        JSR SEND_STREAM_X

        LDA #24
        LDX #$FF
        LDY #14
        JSR SET_XY_COL

        LDA EDIT_MODE
        BEQ DUB_SH
        LDA #$FC
        STA ZP_COLOR
        LDA #<EDIT_BUF
        LDY #>EDIT_BUF
        JSR DRAW_STR_AY
        LDA #'_'
        JSR DRAW_CHAR_ADV
        BNE DUB_ST

DUB_SH: LDA #<URL_BUF
        LDY #>URL_BUF
        LDX #70
        JSR DRAW_STR_N

DUB_ST: LDA #$48
        STA ZP_X_LO
        LDA #$02
        STA ZP_X_HI
        LDX #$1C
        LDA HTTP_STATE
        CMP #2
        BCC DUB_SC
        LDX #$FC
        CMP #4
        BEQ DUB_SC
        LDX #$E0
DUB_SC: STX ZP_COLOR
        LDA #<HTTP_CODE
        LDY #>HTTP_CODE
        JMP DRAW_STR_AY

DRAW_STR_AY:
        LDX #76
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
        CLC
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
; Tabellen, Gecombineerde GPU-Streams & Ingebouwde HTML Startpagina
; ============================================================================
BLK_TAGS:       .BYTE 'p','d','u','o'
LINK_PFX:       .ASCIIZ "[1] "

KEY_CHARS:
        .BYTE $09, $0D, ' ', $08, '[', ']'
        .BYTE 'q', 'u', 'n', 'z', 'h', 'r', 'b', 'v', 'w', 's'
KEY_HND_LO:
        .BYTE <(DO_NXT_LNK-1), <(OPEN_SEL_LINK-1), <(DO_PAGE_DN-1), <(DO_BACK-1)
        .BYTE <(DO_PRV_LNK-1), <(DO_NXT_LNK-1)
        .BYTE <(EXIT_TO_BASIC-1), <(START_EDIT_URL-1)
        .BYTE <(START_NEW_URL-1), <(START_SEARCH-1), <(DO_HOME-1)
        .BYTE <(DO_RELOAD-1), <(DO_BACK-1), <(DO_TOGGLE_VIEW-1)
        .BYTE <(DO_SCR_UP-1), <(DO_SCR_DN-1)
KEY_HND_HI:
        .BYTE >(DO_NXT_LNK-1), >(OPEN_SEL_LINK-1), >(DO_PAGE_DN-1), >(DO_BACK-1)
        .BYTE >(DO_PRV_LNK-1), >(DO_NXT_LNK-1)
        .BYTE >(EXIT_TO_BASIC-1), >(START_EDIT_URL-1)
        .BYTE >(START_NEW_URL-1), >(START_SEARCH-1), >(DO_HOME-1)
        .BYTE >(DO_RELOAD-1), >(DO_BACK-1), >(DO_TOGGLE_VIEW-1)
        .BYTE >(DO_SCR_UP-1), >(DO_SCR_DN-1)

ENT_KEYS:       .BYTE 'a','l','g','q','#'
ENT_VALS:       .BYTE '&','<','>',$22,$27

W5500_STUB_BYTES:
        STA IO_NET_DATA
        LDA IO_NET_DATA
        RTS

W5500_INIT_TBL:
        .BYTE $00, $00, $04, $00
        .BYTE 192, 168, 178, 1
        .BYTE 255, 255, 255, 192
        .BYTE $02, $65, $02, $20, $00, $03
        .BYTE 192, 168, 178, 202

DNS_TAIL_TBL:   .BYTE $00, $00, $01, $00, $01

GPU_STREAMS:
GS_UI:
        .BYTE GS_URL - GS_UI - 1
        .BYTE 12, 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 0
        .BYTE 1, $01
        .BYTE 2, 0,0, 0,0, $80,$02, 15,0, $03
        .BYTE 2, 5,0, 41,0, $76,$02, $2B,$01, $1F
        .BYTE 2, 6,0, 42,0, $74,$02, $29,$01, $00
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $03
GS_URL:
        .BYTE GS_LED - GS_URL - 1
        .BYTE 2, 5,0, 17,0, $76,$02, 22,0, $02
        .BYTE 2, 9,0, 18,0, $38,$02, 20,0, $1F
        .BYTE 2, 10,0, 19,0, $36,$02, 18,0, $00
GS_LED:
        .BYTE GS_SEL - GS_LED - 1
        .BYTE 5, $72,$02, 7,0, 4,0, 0,0
GS_SEL:
        .BYTE GS_EXIT - GS_SEL - 1
        .BYTE 2, 10,0
SEL_BAR_Y:
        .BYTE 46,0, $6C,$02, 13,0, $03
GS_EXIT:
        .BYTE STR_APP_NAME - GS_EXIT - 1
        .BYTE 12, 1, 1, $E3

STR_APP_NAME:   .ASCIIZ "WebSurf: "
STR_BOT_HELP:   .ASCIIZ "U:URL N:Nieuw Z:Zoek 1-9:Link B:Terug R:Reload H:Home V:Bron"

STR_HTTP_PFX:   .ASCIIZ "http://"
STR_SEARCH_URL: .ASCIIZ "http://wiby.me/?q="
STR_ABOUT_HOME: .ASCIIZ "about:home"

STR_HTTP_REQ:   .BYTE "GET ", 1, " HTTP/1.0", 13, 10, "Host: ", 2, 13, 10, 13, 10, 0

STR_ERR_NET:    .ASCIIZ "<h1>GEEN LINK</h1>Check LAN"
STR_ERR_DNS:    .ASCIIZ "<h1>DNS FOUT</h1>Geen host"
STR_ERR_HTTP:   .ASCIIZ "<h1>HTTP FOUT</h1>Geen :80"

HOME_HTML:
        .BYTE "<title>Home</title><h1>WEBSURF 6502 (W5500)</h1><hr>"
        .BYTE "<a href=//68k.news/?loc=NL>68k.news NL Nieuws"
        .BYTE "<a href=//info.cern.ch/>info.cern.ch CERN"
        .BYTE "<a href=//wiby.me/>wiby.me Zoeken"
        .BYTE "<a href=//textfiles.com/>textfiles.com BBS"
        .BYTE "<a href=//example.com/>example.com Test"
        .BYTE "<a href=//192.168.178.87/json>Powerbaas .87"
        .BYTE "<hr>1-6:Open Z:Zoek N:URL", 0
