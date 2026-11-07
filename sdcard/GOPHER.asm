; ============================================================================
; GOPHER.asm - MiniGPU GopherSurf 1.0 (6502 + W5500 RFC 1436 Gopher Browser!)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC op $9000).
;   - Volledig RFC 1436 Gopher-protocol over TCP (standaard poort 70 + custom)
;   - Echte UDP DNS-Resolver op W5500 (Poort 53: Router .1 + 1.1.1.1 fallback)
;   - 12 KB ontvangstbuffer in SDRAM Bank 60 ($B000..$DEFF via $A015)
;   - 75-koloms weergave (80 regels x 128 B) voor menu's, ASCII-art & tekst!
;   - Tot 24 klikbare items per pagina ([01/D] Map, [02/T] Tekst, [03/?] Zoek)
;   - Direct zoeken in Gopherspace (Z = Veronica-2) & Wikipedia (W = Gopherpedia)
;   - 4-laags Terug-geschiedenis (B), Adresbalk (G/U), Kleurthema (C) & Bron (V)
; Starten vanuit Midnight Commander (BRUN MC) of in BASIC met: BRUN "GOPHER"
; ============================================================================
        ORG $8000

IO_STATUS       = $A000
IO_TERM         = $A001
IO_TIMER        = $A003
IO_JOY          = $A004
IO_RND          = $A005
IO_MODE         = $A006
IO_RD_BANK      = $A015
IO_GPU          = $A020
IO_NET_DATA     = $A030
IO_NET_CTRL     = $A031

ROM_SILENCE     = $E8DC
SPI_BRAM_STUB   = $02F0
GOPHER_BANK     = 60            ; Vrije 64 KB SDRAM-bank voor 12 KB RAW_BUF

; --- Zero Page ($60..$87: veilig naast BASIC $10..$45 en MC $45..$5E/$88..$8E) ---
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
ROW_Y_LO        = $6B
ROW_Y_HI        = $6C
ITEM_TYPE       = $6B
PORT_ACC_LO     = $6C
S1_LEN_LO       = $6D
S1_LEN_HI       = $6E
PORT_ACC_HI     = $6D
IS_LINK_ROW     = $6E

W5500_VER       = $6F
W5500_PHY       = $70
NET_STATE       = $71           ; Offset in STATUS_TBL (0..16=OK, 20=LAAD, 24=FOUT)
VIEW_MODE       = $72           ; 0=Gopher, 1=Ruwe broncode
EDIT_MODE       = $73           ; 0=Bladeren, 1=Gopher-URL, 2=Zoekterm
EDIT_LEN        = $74
SCROLL_TOP      = $75
TOTAL_LINES     = $76
LINK_CNT        = $77
CUR_COL         = $78
LAST_SPC        = $79
THEME_IDX       = $7A           ; 0=Wit ($FF), 1=Groen ($1C), 2=Amber ($F4)
HIST_SP         = $7B           ; 0..4 pagina's in $7C00..$7FFF
LOCAL_PORT      = $7C
PREV_JOY        = $7D
SEL_LINK        = $7E
PENDING_PG      = $7F

DEST_IP0        = $80
DEST_IP1        = $81
DEST_IP2        = $82
DEST_IP3        = $83
DEST_PORT_HI    = $84
DEST_PORT_LO    = $85
TMP_A           = $86
TMP_B           = $87

; --- SDRAM Geheugenindeling (laat MC $5BE0..$5FFF en $9000..$9FFF vrij!) ---
DOC_LINES       = $3000         ; 80 regels x 128 bytes ($3000..$57FF = 10 KB)
MAX_LINES       = 80
MAX_COLS        = 75

URI_BUF         = $5800
EDIT_BUF        = $5900
DNS_BUF         = $5A00

LINK_BASE_HI    = $5F           ; Links 1..24 op pagina's $6000..$77FF
MAX_LINKS       = 24

NAV_PAGE        = $7900
NAV_PAGE_HI     = $79
NAV_TYPE        = $7900
NAV_PORT_LO     = $7901
NAV_PORT_HI     = $7902
NAV_SAV_SCR     = $7903
NAV_SAV_SEL     = $7904
NAV_HOST        = $7908
NAV_SEL         = $7948
NAV_QUERY       = $79E0

VERONICA_PG_HI  = $7A           ; Gecachete Type-7 template voor Veronica-2 (Z)
WIKI_PG_HI      = $7B           ; Gecachete Type-7 template voor Gopherpedia (W)
HIST_BASE_HI    = $7C           ; 4-laags geschiedenisstack: $7C00..$7FFF

RAW_BUF         = $B000         ; 12 KB ontvangstbuffer in Bank 60 ($B000..$DEFF)
RAW_BUF_END_HI  = $DF

ST_HOME         = 0
ST_MENU         = 4
ST_TXT          = 8
ST_SRC          = 12
ST_WEB          = 16
ST_LOAD         = 20
ST_ERR          = 24

; ============================================================================
; Start & Hoofdlus
; ============================================================================
START:
        JSR ROM_SILENCE
        LDA #GOPHER_BANK
        STA IO_RD_BANK
        LDA #0
        STA IO_MODE
        STA ZP_Y_HI
        STA VIEW_MODE
        STA EDIT_MODE
        STA THEME_IDX
        STA HIST_SP

        LDA IO_RND
        ORA #$01
        STA LOCAL_PORT

        JSR W5500_INIT_HW
        JSR LOAD_HOME_PAGE
        ; Bewaar Home link #2 ($61 = Veronica-2) & #4 ($63 = Gopherpedia) in $7A/$7B!
        LDA #$61
        LDY #VERONICA_PG_HI
        JSR COPY_PAGE_A_TO_Y
        LDA #$63
        LDY #WIKI_PG_HI
        JSR COPY_PAGE_A_TO_Y

        LDA IO_JOY
        STA PREV_JOY

MAIN_LOOP:
        JSR DRAW_BROWSER

WAIT_LOOP:
        JSR DELAY_10MS

        LDA IO_STATUS
        BPL CHK_INP
        LDA IO_JOY
        STA PREV_JOY
        LDA IO_TERM
        LDA EDIT_MODE
        BEQ EXIT_TO_BASIC
        LDA #0
        STA EDIT_MODE
        BEQ MAIN_LOOP

EXIT_TO_BASIC:
        LDA #0
        STA IO_RD_BANK
        LDX #GS_EXIT - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

CHK_INP:
        AND #1
        BNE CHK_KEY

CHK_JOY:
        LDA IO_JOY
        STA TMP_A
        TAX
        EOR PREV_JOY
        AND TMP_A
        STX PREV_JOY
        TAY
        BEQ WAIT_J1
        LDA EDIT_MODE
        BNE WAIT_J1

        TYA
        LSR A
        BCS DO_SCR_UP
        LSR A
        BCS DO_SCR_DN
        LSR A
        BCS DO_PRV_LNK
        LSR A
        BCS DO_NXT_LNK
        LSR A
        BCS OPEN_SEL_J
WAIT_J1:
        JMP WAIT_LOOP
OPEN_SEL_J:
        JMP OPEN_SEL_LINK

DO_SCR_UP:
        LDA SCROLL_TOP
        BEQ WAIT_J1
        DEC SCROLL_TOP
MAIN_J1:
        JMP MAIN_LOOP

DO_PAGE_UP:
        LDA SCROLL_TOP
        SEC
        SBC #18
        BCS DPU_S
        LDA #0
DPU_S:  STA SCROLL_TOP
        JMP MAIN_LOOP

DO_PAGE_DN:
        LDX #18
        BNE DPD_L
DO_SCR_DN:
        LDX #1
DPD_L:  LDA SCROLL_TOP
        CLC
        ADC #19
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

DNL_SC: LDX #0
DNL_F:  CPX TOTAL_LINES
        BCS MAIN_J1
        TXA
        JSR CALC_DOC_ROW
        LDY #78
        LDA (ZP_LINE_LO),Y
        CMP SEL_LINK
        BEQ DNL_M
        INX
        BNE DNL_F
DNL_M:  CPX SCROLL_TOP
        BCC DNL_ST
        TXA
        SEC
        SBC #18
        BCC MAIN_J1
        CMP SCROLL_TOP
        BCC MAIN_J1
        TAX
DNL_ST: STX SCROLL_TOP
        JMP MAIN_LOOP

; ============================================================================
; Toetsenbord Afhandeling
; ============================================================================
CHK_KEY:
        LDA IO_JOY
        STA PREV_JOY
        LDA IO_TERM

        LDX EDIT_MODE
        BNE KEY_EDIT

        CMP #'1'
        BCC KB_ND
        CMP #'9'+1
        BCS KB_ND
        SEC
        SBC #'0'
        CMP LINK_CNT
        BEQ KB_GO
        BCS WAIT_J1
KB_GO:  STA SEL_LINK
        JMP OPEN_SEL_LINK

KB_ND:  CMP #'A'
        BCC KB_LK
        CMP #'Z'+1
        BCS KB_LK
        ORA #$20
KB_LK:  LDX #16
KB_LP:  CMP KEY_CHARS,X
        BEQ KB_DIS
        DEX
        BPL KB_LP
        BMI WAIT_J1

KB_DIS: LDA KEY_HND_HI,X
        PHA
        LDA KEY_HND_LO,X
        PHA
        RTS

DO_COLOR:
        LDX THEME_IDX
        INX
        CPX #3
        BCC DC_OK
        LDX #0
DC_OK:  STX THEME_IDX
        JMP RC_AND_DRAW

DO_TOGGLE_VIEW:
        LDA VIEW_MODE
        EOR #1
        STA VIEW_MODE
        LDA #0
        STA SCROLL_TOP
RC_AND_DRAW:
        JSR RENDER_CURRENT
        JMP MAIN_LOOP

DO_HOME:
        JSR PUSH_HISTORY
        JSR LOAD_HOME_PAGE
        JMP MAIN_LOOP

DO_RELOAD:
        LDA NAV_TYPE
        CMP #'H'
        BEQ RC_AND_DRAW
        JMP KE_GO

START_NEW_URL:
        JSR INIT_EDIT_DST
        LDX #<STR_GOPHER_PFX
        LDY #>STR_GOPHER_PFX
        BNE SEU_CP
START_EDIT_URL:
        JSR INIT_EDIT_DST
        LDX #<URI_BUF
        LDY #>URI_BUF
SEU_CP: JSR APPEND_STR_XY
        LDA TMP_A
        STA EDIT_LEN
        LDA #1
        BNE SET_EMODE

START_VERONICA:
        LDA #VERONICA_PG_HI
        BNE START_PROMPT_Q
START_WIKI:
        LDA #WIKI_PG_HI
START_PROMPT_Q:
        STA PENDING_PG
        JSR INIT_EDIT_DST
        STA EDIT_LEN
        LDA #2
SET_EMODE:
        STA EDIT_MODE
        JMP MAIN_LOOP

INIT_EDIT_DST:
        LDA #<EDIT_BUF
        LDY #>EDIT_BUF
        LDX #62
        JMP INIT_BUF_DST

KEY_EDIT:
        CMP #$0D
        BEQ KE_ENTER
        CMP #$08
        BEQ KE_BS
        CMP #$7F
        BEQ KE_BS
        CMP #' '
        BCC KE_WAIT
        CMP #$7F
        BCS KE_WAIT
        LDY EDIT_LEN
        CPY #62
        BCS KE_WAIT
        STA EDIT_BUF,Y
        INY
        BNE KE_SET
KE_BS:  LDY EDIT_LEN
        BEQ KE_WAIT
        DEY
KE_SET: STY EDIT_LEN
        LDA #0
        STA EDIT_BUF,Y
        JSR DRAW_URL_BAR
KE_WAIT:
        JMP WAIT_LOOP

KE_ENTER:
        LDA EDIT_LEN
        BEQ KE_CLR
        JSR PUSH_HISTORY
        LDX EDIT_MODE
        LDA #0
        STA EDIT_MODE
        CPX #2
        BEQ KE_DO_SEARCH
        JSR PARSE_GOPHER_URI
        JMP KE_GO
KE_CLR: STA EDIT_MODE
        BEQ KE_DONE

KE_DO_SEARCH:
        LDA PENDING_PG
        LDY #NAV_PAGE_HI
        JSR COPY_PAGE_A_TO_Y
        LDA #'7'
        STA NAV_TYPE
        LDA #<NAV_QUERY
        LDY #>NAV_QUERY
        LDX #30
        JSR INIT_BUF_DST
        LDX #<EDIT_BUF
        LDY #>EDIT_BUF
        JSR APPEND_STR_XY
KE_GO:  JSR FETCH_AND_RENDER
KE_DONE:
        JMP MAIN_LOOP

; ============================================================================
; Klik op Geselecteerd Gopher-Item (1..24) & 4-laags Terug-knop
; ============================================================================
OPEN_SEL_LINK:
        LDA SEL_LINK
        BEQ KE_DONE
        CMP LINK_CNT
        BCC OSL_OK
        BNE KE_DONE
OSL_OK: CLC
        ADC #LINK_BASE_HI
        STA ZP_SRC_HI
        LDA #0
        STA ZP_SRC_LO
        TAY
        LDA (ZP_SRC_LO),Y
        CMP #'7'
        BNE OSL_GO
        LDA ZP_SRC_HI
        BNE START_PROMPT_Q

OSL_GO: JSR PUSH_HISTORY
        LDA ZP_SRC_HI
        LDY #NAV_PAGE_HI
        JSR COPY_PAGE_A_TO_Y
        JMP KE_GO

DO_BACK:
        LDA HIST_SP
        BEQ KE_DONE
        DEC HIST_SP
        LDA HIST_SP
        CLC
        ADC #HIST_BASE_HI
        LDY #NAV_PAGE_HI
        JSR COPY_PAGE_A_TO_Y
        LDA NAV_TYPE
        CMP #'H'
        BNE DBK_F
        JSR LOAD_HOME_NO_RST
        JMP DBK_RS
DBK_F:  JSR FETCH_AND_RENDER
DBK_RS: LDA NAV_SAV_SCR
        CMP TOTAL_LINES
        BCC DBK_S1
        LDA #0
DBK_S1: STA SCROLL_TOP
        LDA NAV_SAV_SEL
        CMP LINK_CNT
        BCC DBK_S2
        BEQ DBK_S2
        LDA LINK_CNT
DBK_S2: STA SEL_LINK
        JMP MAIN_LOOP

PUSH_HISTORY:
        LDA SCROLL_TOP
        STA NAV_SAV_SCR
        LDA SEL_LINK
        STA NAV_SAV_SEL
        LDA HIST_SP
        CMP #4
        BCC PH_OK
        LDY #HIST_BASE_HI
PH_SH:  TYA
        CLC
        ADC #1
        JSR COPY_PAGE_A_TO_Y
        INY
        CPY #HIST_BASE_HI+3
        BCC PH_SH
        LDA #3
        STA HIST_SP
PH_OK:  CLC
        ADC #HIST_BASE_HI
        TAY
        LDA #NAV_PAGE_HI
        INC HIST_SP

COPY_PAGE_A_TO_Y:
        STA CPY_SRC+2
        STY CPY_DST+2
        LDX #0
CPY_SRC:
        LDA $7900,X
CPY_DST:
        STA $7C00,X
        INX
        BNE CPY_SRC
        RTS

CLEAR_NAV_PAGE:
        LDX #'1'
        LDA #NAV_PAGE_HI
INIT_GOPH_PAGE:
        STA ZP_PTR_HI
        LDA #0
        STA ZP_PTR_LO
        TAY
IGP_L:  STA (ZP_PTR_LO),Y
        INY
        BNE IGP_L
        TXA
        STA (ZP_PTR_LO),Y
        INY
        LDA #70
        STA (ZP_PTR_LO),Y
        RTS

; ============================================================================
; Startpagina, Universele String-Opbouw & RFC 4266 URI-Parser
; ============================================================================
INIT_BUF_DST:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        STX TMP_B
        LDA #0
        STA TMP_A
        TAY
        STA (ZP_PTR_LO),Y
        RTS

APPEND_CH:
        LDY TMP_A
        CPY TMP_B
        BCS ACH_R
        STA (ZP_PTR_LO),Y
        INY
        STY TMP_A
        LDA #0
        STA (ZP_PTR_LO),Y
ACH_R:  RTS

APPEND_STR_XY:
        STX ZP_SRC_LO
        STY ZP_SRC_HI
ASX_L:  JSR NEXT_SRC
        BCC ACH_R
        JSR APPEND_CH
        JMP ASX_L

LOAD_HOME_PAGE:
        JSR CLEAR_NAV_PAGE
        LDA #'H'
        STA NAV_TYPE
LOAD_HOME_NO_RST:
        LDX #0
LHP_U:  LDA STR_ABOUT_HOME,X
        STA URI_BUF,X
        BEQ LHP_D
        INX
        BNE LHP_U
LHP_D:  STA NET_STATE
        STA VIEW_MODE
        STA SCROLL_TOP
        LDA #<HOME_GOPHER
        LDY #>HOME_GOPHER
        JMP PARSE_MENU_AY

BUILD_URI_STR:
        LDA #<URI_BUF
        LDY #>URI_BUF
        LDX #72
        JSR INIT_BUF_DST
        LDX #<STR_GOPHER_PFX
        LDY #>STR_GOPHER_PFX
        JSR APPEND_STR_XY
        LDX #<NAV_HOST
        LDY #>NAV_HOST
        JSR APPEND_STR_XY
        LDA #'/'
        JSR APPEND_CH
        LDA NAV_TYPE
        JSR APPEND_CH
        LDX #<NAV_SEL
        LDY #>NAV_SEL
        JSR APPEND_STR_XY
        LDA NAV_QUERY
        BEQ BUS_R
        LDA #'?'
        JSR APPEND_CH
        LDX #<NAV_QUERY
        LDY #>NAV_QUERY
        JMP APPEND_STR_XY
BUS_R:  RTS

PARSE_GOPHER_URI:
        JSR CLEAR_NAV_PAGE
        LDY #0
PGU_PF: LDA STR_GOPHER_PFX,Y
        BEQ PGU_HP
        LDA EDIT_BUF,Y
        ORA #$20
        CMP STR_GOPHER_PFX,Y
        BNE PGU_H0
        INY
        BNE PGU_PF
PGU_HP: TYA
        TAX
        BNE PGU_HY
PGU_H0: LDX #0
PGU_HY: LDY #0
PGU_HL: LDA EDIT_BUF,X
        BEQ PGU_HD
        CMP #'/'
        BEQ PGU_HD
        CMP #':'
        BEQ PGU_HD
        CPY #60
        BCS PGU_HN
        STA NAV_HOST,Y
        INY
PGU_HN: INX
        BNE PGU_HL
PGU_HD: LDA EDIT_BUF,X
        CMP #':'
        BNE PGU_CS
        INX
        JSR CLR_PORT_ACC
PPE_L:  LDA EDIT_BUF,X
        JSR IS_DIGIT_SUB0
        BCC PPE_D
        JSR ADD_PORT_DIGIT
        INX
        BNE PPE_L
PPE_D:  JSR STORE_PORT_ACC
PGU_CS: LDA EDIT_BUF,X
        BEQ BUS_R
        INX
        LDA EDIT_BUF,X
        BEQ BUS_R
        STA NAV_TYPE
        INX
        LDY #0
PGU_SL: LDA EDIT_BUF,X
        STA NAV_SEL,Y
        BEQ BUS_R
        INX
        INY
        CPY #150
        BCC PGU_SL
        RTS

; ============================================================================
; Netwerk Fetch + Weergave Orchestratie
; ============================================================================
FETCH_AND_RENDER:
        LDA #0
        STA VIEW_MODE
        STA SCROLL_TOP
        JSR BUILD_URI_STR

        LDA NAV_TYPE
        CMP #'h'
        BEQ RENDER_WEB_INFO

        LDA #ST_LOAD
        STA NET_STATE
        JSR DRAW_URL_BAR

        JSR W5500_PROBE_HW
        BNE FAR_ENET
        LDA W5500_PHY
        AND #$01
        BNE FAR_DNS
FAR_ENET:
        LDA #<STR_ERR_NET
        LDY #>STR_ERR_NET
        BNE SHOW_ERR_MSG

FAR_DNS:
        JSR DNS_RESOLVE
        BCS FAR_TCP
        LDA #<STR_ERR_DNS
        LDY #>STR_ERR_DNS
        BNE SHOW_ERR_MSG

FAR_TCP:
        JSR GOPHER_FETCH
        BCS RENDER_CURRENT
        LDA #<STR_ERR_TCP
        LDY #>STR_ERR_TCP
SHOW_ERR_MSG:
        LDX #ST_ERR
        STX NET_STATE
        JMP PARSE_MENU_AY

RENDER_CURRENT:
        LDA NAV_TYPE
        CMP #'H'
        BNE RC_NH
        JMP LOAD_HOME_PAGE
RC_NH:  CMP #'h'
        BEQ RENDER_WEB_INFO
        LDA VIEW_MODE
        BEQ RC_FMT
        LDA #ST_SRC
        STA NET_STATE
        BNE RENDER_PLAIN_RAW

RC_FMT: LDA NAV_TYPE
        CMP #'0'
        BEQ RC_TXT
        LDA #ST_MENU
        STA NET_STATE
        LDA #<RAW_BUF
        LDY #>RAW_BUF
        JMP PARSE_MENU_AY

RC_TXT: LDA #ST_TXT
        STA NET_STATE
RENDER_PLAIN_RAW:
        LDA #<RAW_BUF
        STA ZP_SRC_LO
        LDA #>RAW_BUF
        STA ZP_SRC_HI
        JMP PARSE_PLAIN_TEXT

RENDER_WEB_INFO:
        LDA #ST_WEB
        STA NET_STATE
        LDA #<STR_WEB_INFO
        LDY #>STR_WEB_INFO
        JSR PARSE_MENU_AY
        JSR PREP_CUR_ROW
        LDA #$1F
        LDY #79
        STA (ZP_LINE_LO),Y
        LDY #0
RWI_L:  LDA NAV_SEL,Y
        BEQ RWI_D
        STA (ZP_LINE_LO),Y
        INY
        CPY #MAX_COLS
        BCC RWI_L
RWI_D:  INC TOTAL_LINES
        RTS

; ============================================================================
; RFC 1436 Gopher-Menu Parser (75 kolommen, 80 regels x 128 B, tot 24 links!)
; ============================================================================
INIT_DOC_BUF:
        LDA #0
        STA TOTAL_LINES
        STA LINK_CNT
        STA SEL_LINK
        RTS

PREP_CUR_ROW:
        LDA TOTAL_LINES
        JSR CALC_DOC_ROW
        LDY #79
        LDA #0
PCR_C:  STA (ZP_LINE_LO),Y
        DEY
        BPL PCR_C
        LDX THEME_IDX
        LDA THEME_COLS,X
        LDY #79
        STA (ZP_LINE_LO),Y
        RTS

; ZP_LINE = $3000 + A * 128 (12 bytes!)
CALC_DOC_ROW:
        LSR A
        PHA
        LDA #0
        ROR A
        STA ZP_LINE_LO
        PLA
        CLC
        ADC #>DOC_LINES
        STA ZP_LINE_HI
        RTS

NEXT_SRC:
        LDY #0
        LDA (ZP_SRC_LO),Y
        BEQ NS_EOF
        INC ZP_SRC_LO
        BNE NS_OK
        INC ZP_SRC_HI
NS_OK:  SEC
        RTS
NS_EOF: CLC
        RTS

PARSE_MENU_AY:
        STA ZP_SRC_LO
        STY ZP_SRC_HI
        JSR INIT_DOC_BUF

PGM_LINE:
        LDA TOTAL_LINES
        CMP #MAX_LINES
        BCS PGM_DONE_J
        JSR NEXT_SRC
        BCC PGM_DONE_J
        CMP #$0D
        BEQ PGM_CR0
        CMP #$0A
        BEQ PGM_BLANK
        CMP #'.'
        BNE PGM_GOT_T
        LDY #0
        LDA (ZP_SRC_LO),Y
        BEQ PGM_DONE_J
        CMP #$0D
        BEQ PGM_DONE_J
        CMP #$0A
        BEQ PGM_DONE_J
        LDA #'.'
        BNE PGM_GOT_T
PGM_DONE_J:
        JMP PGM_DONE

PGM_CR0:
        JSR CHK_SKIP_LF
PGM_BLANK:
        JSR PREP_CUR_ROW
        INC TOTAL_LINES
        BNE PGM_LINE

PGM_GOT_T:
        STA ITEM_TYPE
        JSR PREP_CUR_ROW
        JSR CLR_PORT_ACC
        STA IS_LINK_ROW

        LDA ITEM_TYPE
        CMP #'i'
        BEQ PGM_INFO
        CMP #'3'
        BNE PGM_CHK_LNK
        LDA #$E0
        LDY #79
        STA (ZP_LINE_LO),Y
PGM_INFO:
        LDX #0
        BEQ PGM_DISP_LP

PGM_CHK_LNK:
        LDY #3
PGM_TL: CMP GTYPE_CHARS,Y
        BEQ PGM_MK_LNK
        DEY
        BPL PGM_TL

        LDA #$5B
        LDY #79
        STA (ZP_LINE_LO),Y
        LDY #6
PGM_BN: LDA STR_PFX_BIN,Y
        STA (ZP_LINE_LO),Y
        DEY
        BPL PGM_BN
        LDX #7
        BNE PGM_DISP_LP

PGM_MK_LNK:
        LDA LINK_CNT
        CMP #MAX_LINKS
        BCS PGM_INFO
        LDA GTYPE_BADGE,Y
        STA TMP_A
        LDA GTYPE_COLOR,Y
        LDY #79
        STA (ZP_LINE_LO),Y

        INC LINK_CNT
        STY IS_LINK_ROW
        LDA LINK_CNT
        DEY
        STA (ZP_LINE_LO),Y

        CLC
        ADC #LINK_BASE_HI
        LDX ITEM_TYPE
        JSR INIT_GOPH_PAGE

        LDA LINK_CNT
        LDX #'0'
PGM_DC: CMP #10
        BCC PGM_DD
        SBC #10
        INX
        BNE PGM_DC
PGM_DD: ORA #'0'
        STA LINK_PFX_TPL+2
        STX LINK_PFX_TPL+1
        LDA TMP_A
        STA LINK_PFX_TPL+4
        LDY #6
PGM_PF: LDA LINK_PFX_TPL,Y
        STA (ZP_LINE_LO),Y
        DEY
        BPL PGM_PF
        LDX #7

PGM_DISP_LP:
        JSR NEXT_SRC
        BCC PGM_L_END
        CMP #$09
        BEQ PGM_GOT_TAB
        CMP #$0D
        BEQ PGM_TP_CR
        CMP #$0A
        BEQ PGM_L_END
        CMP #' '
        BCC PGM_DISP_LP
        CPX #MAX_COLS
        BCS PGM_DISP_LP
        STX TMP_B
        LDY TMP_B
        STA (ZP_LINE_LO),Y
        INX
        BNE PGM_DISP_LP

PGM_GOT_TAB:
        LDA IS_LINK_ROW
        BEQ PGM_TP_SK

        LDY #$48
        LDA #$DE
        JSR READ_TAB_FIELD
        BCC PGM_L_END

        LDY #$08
        LDA #$46
        JSR READ_TAB_FIELD
        BCC PGM_L_END

PGM_TP: JSR NEXT_SRC
        BCC PGM_TPD
        CMP #$09
        BEQ PGM_TP_SK
        CMP #$0D
        BEQ PGM_TP_CR
        CMP #$0A
        BEQ PGM_TPD
        JSR IS_DIGIT_SUB0
        BCC PGM_TP
        JSR ADD_PORT_DIGIT
        JMP PGM_TP

PGM_TP_SK:
        JSR SKIP_REST_LINE
        JMP PGM_TPD
PGM_TP_CR:
        JSR CHK_SKIP_LF
PGM_TPD:
        JSR STORE_PORT_ACC
PGM_L_END:
        INC TOTAL_LINES
        JMP PGM_LINE

PGM_DONE:
        LDA LINK_CNT
        BEQ PGM_R
        LDA #1
        STA SEL_LINK
PGM_R:  RTS

READ_TAB_FIELD:
        STA TMP_B
RTF_L:  STY TMP_A
        JSR NEXT_SRC
        BCC RTF_E
        CMP #$09
        BEQ RTF_TAB
        CMP #$0D
        BEQ RTF_CR
        CMP #$0A
        BEQ RTF_E
        LDY TMP_A
        CPY TMP_B
        BCS RTF_L
        STA (ZP_PTR_LO),Y
        INY
        BNE RTF_L
RTF_CR: JSR CHK_SKIP_LF
RTF_E:  CLC
        RTS
RTF_TAB:
        SEC
        RTS

SKIP_REST_LINE:
        JSR NEXT_SRC
        BCC SRL_R
        CMP #$0A
        BEQ SRL_R
        CMP #$0D
        BNE SKIP_REST_LINE
CHK_SKIP_LF:
        LDY #0
        LDA (ZP_SRC_LO),Y
        CMP #$0A
        BNE SRL_R
        JMP NEXT_SRC
SRL_R:  RTS

CLR_PORT_ACC:
        LDA #0
        STA PORT_ACC_LO
        STA PORT_ACC_HI
        RTS

STORE_PORT_ACC:
        LDA PORT_ACC_LO
        ORA PORT_ACC_HI
        BEQ SRL_R
        LDY #1
        LDA PORT_ACC_LO
        STA (ZP_PTR_LO),Y
        INY
        LDA PORT_ACC_HI
        STA (ZP_PTR_LO),Y
        RTS

IS_DIGIT_SUB0:
        SEC
        SBC #'0'
        BCC IDS_N
        CMP #10
        BCC IDS_OK
IDS_N:  CLC
        RTS
IDS_OK: SEC
        RTS

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

; ============================================================================
; Type-0 Tekstdocument Parser (75 kolommen met snelle LAST_SPC word-wrap!)
; ============================================================================
PARSE_PLAIN_TEXT:
        JSR INIT_DOC_BUF
        JSR PPT_NEW_ROW

PPT_LP: LDA TOTAL_LINES
        CMP #MAX_LINES
        BCS PPT_FIN
        JSR NEXT_SRC
        BCC PPT_FIN
        CMP #$0D
        BEQ PPT_LP
        CMP #$0A
        BEQ PPT_NL
        CMP #$09
        BNE PPT_CH
        LDA #' '
PPT_CH: CMP #' '
        BCC PPT_LP
        CMP #$7F
        BCS PPT_LP
        JSR PPT_PUT_CHAR
        JMP PPT_LP

PPT_NL: JSR PPT_ADV_ROW
        JMP PPT_LP

PPT_FIN:
        LDA CUR_COL
        BEQ PPT_R
        LDA TOTAL_LINES
        CMP #MAX_LINES
        BCS PPT_R
        INC TOTAL_LINES
PPT_R:  RTS

PPT_ADV_ROW:
        LDA TOTAL_LINES
        CMP #MAX_LINES
        BCS PNR_R
        INC TOTAL_LINES
PPT_NEW_ROW:
        LDA #0
        STA CUR_COL
        STA LAST_SPC
        LDA TOTAL_LINES
        CMP #MAX_LINES
        BCS PNR_R
        JMP PREP_CUR_ROW
PNR_R:  RTS

PPT_PUT_CHAR:
        LDY CUR_COL
        CPY #MAX_COLS
        BCC PPC_OK
        CMP #' '
        BEQ PPT_ADV_ROW
        PHA
        LDY LAST_SPC
        CPY #38
        BCC PPC_NW
        LDA #0
        STA (ZP_LINE_LO),Y
        STY TMP_A
        LDA ZP_LINE_LO
        STA ZP_PTR_LO
        LDA ZP_LINE_HI
        STA ZP_PTR_HI
        JSR PPT_ADV_ROW
        LDA TOTAL_LINES
        CMP #MAX_LINES
        BCS PPC_PL
        INC TMP_A
        LDY TMP_A
        LDX #0
PPC_MV: CPY #MAX_COLS
        BCS PPC_MD
        LDA (ZP_PTR_LO),Y
        STX TMP_B
        LDY TMP_B
        STA (ZP_LINE_LO),Y
        INC TMP_A
        LDY TMP_A
        INX
        BNE PPC_MV
PPC_MD: STX CUR_COL
        BCS PPC_PL
PPC_NW: JSR PPT_ADV_ROW
PPC_PL: PLA
        LDY CUR_COL
PPC_OK: LDX TOTAL_LINES
        CPX #MAX_LINES
        BCS PPC_R
        CMP #' '
        BNE PPC_ST
        STY LAST_SPC
PPC_ST: STA (ZP_LINE_LO),Y
        INY
        STY CUR_COL
PPC_R:  RTS

; ============================================================================
; UDP DNS-Resolver (Poort 53) & Gopher TCP-Client (Poort 70 / Custom)
; ============================================================================
TRY_PARSE_IPV4:
        LDY #0
        LDX #0
TPI_O:  JSR CLR_PORT_ACC
        LDA NAV_HOST,Y
        JSR IS_DIGIT_SUB0
        BCC TPI_F
TPI_LP: JSR ADD_PORT_DIGIT
        LDA PORT_ACC_HI
        BNE TPI_F
        INY
        LDA NAV_HOST,Y
        JSR IS_DIGIT_SUB0
        BCS TPI_LP
        LDA PORT_ACC_LO
        STA DEST_IP0,X
        LDA NAV_HOST,Y
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
        LDX #3
DR_G1:  LDA W5500_INIT_TBL+4,X
        STA DEST_IP0,X
        DEX
        BPL DR_G1
        JSR DNS_QUERY_ONCE
        BCS DNS_OK_R
        LDA #1
        LDX #3
DR_G2:  STA DEST_IP0,X
        DEX
        BPL DR_G2
        JMP DNS_QUERY_ONCE
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
DQ_CH:  LDA NAV_HOST,Y
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

GOPHER_FETCH:
        LDA NAV_PORT_HI
        STA DEST_PORT_HI
        LDA NAV_PORT_LO
        STA DEST_PORT_LO

        LDA #$01
        JSR S1_OPEN_DEST
        LDA #$04
        JSR S1_CMD

        LDX #250
GF_WC:  STX TMP_A
        LDA #$03
        JSR W5500_RD_S1
        CMP #$17
        BEQ GF_CON
        CMP #$00
        BEQ GF_ERR
        JSR DELAY_10MS
        LDX TMP_A
        DEX
        BNE GF_WC
GF_ERR: JSR S1_CLOSE
        CLC
        RTS

GF_CON: JSR S1_TX_PTR_HDR
        LDY #0
GF_SL:  LDA NAV_SEL,Y
        BEQ GF_CHK_Q
        JSR SPI_AND_INC_S1
        INY
        BNE GF_SL

GF_CHK_Q:
        LDA NAV_TYPE
        CMP #'7'
        BNE GF_CRLF
        LDA NAV_QUERY
        BEQ GF_CRLF
        LDA #$09
        JSR SPI_AND_INC_S1
        LDY #0
GF_QL:  LDA NAV_QUERY,Y
        BEQ GF_CRLF
        JSR SPI_AND_INC_S1
        INY
        BNE GF_QL

GF_CRLF:
        LDA #$0D
        JSR SPI_AND_INC_S1
        LDA #$0A
        JSR SPI_AND_INC_S1
        JSR W5500_CS_HI
        JSR S1_FLUSH_SEND

        LDA #<RAW_BUF
        STA ZP_PTR_LO
        LDA #>RAW_BUF
        STA ZP_PTR_HI
        LDA #0
        STA RAW_BUF
        STA $DF00
        LDA #250
        STA TMP_B

GF_RL:  JSR S1_GET_RX_LEN
        BEQ GF_RE

        LDA S1_LEN_HI
        CMP #4
        BCC GF_COK
        LDA #4
        STA S1_LEN_HI
        LDA #0
        STA S1_LEN_LO
GF_COK: JSR S1_READ_PTR_HDR
GF_BL:  LDA #0
        JSR SPI_BRAM_STUB
        LDX ZP_PTR_HI
        CPX #RAW_BUF_END_HI
        BCS GF_SK
        LDY #0
        STA (ZP_PTR_LO),Y
        INC ZP_PTR_LO
        BNE GF_SK
        INC ZP_PTR_HI
GF_SK:  INC S1_PTR_LO
        BNE GF_DC
        INC S1_PTR_HI
GF_DC:  LDA S1_LEN_LO
        BNE GF_D1
        DEC S1_LEN_HI
GF_D1:  DEC S1_LEN_LO
        LDA S1_LEN_LO
        ORA S1_LEN_HI
        BNE GF_BL

        JSR W5500_CS_HI
        LDA #$28
        LDY #$40
        JSR S1_PTR_CMD

        LDY #0
        TYA
        STA (ZP_PTR_LO),Y
        LDA #160
        STA TMP_B
        LDA ZP_PTR_HI
        CMP #RAW_BUF_END_HI
        BCS GF_DN
GF_RL_J:
        JMP GF_RL

GF_RE:  LDA #$03
        JSR W5500_RD_S1
        CMP #$17
        BEQ GF_STL
        JSR S1_GET_RX_LEN
        BNE GF_RL_J
        BEQ GF_DN

GF_STL: JSR DELAY_10MS
        DEC TMP_B
        BNE GF_RL_J
GF_DN:  JSR S1_CLOSE
        LDA ZP_PTR_HI
        CMP #>RAW_BUF
        BNE GF_OK
        LDA ZP_PTR_LO
        BEQ GF_NO
GF_OK:  SEC
        RTS
GF_NO:  CLC
        RTS

; ============================================================================
; W5500 Hardware & Socket 1 Helpers
; ============================================================================
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
; Grafische 640x360 GopherSurf UI op MiniGPU ($A020)
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
        LDA #<STR_APP_NAME
        LDY #>STR_APP_NAME
        JSR DRAW_STR_AY
        LDX #<STR_HOME_TITLE
        LDY #>STR_HOME_TITLE
        LDA NAV_TYPE
        CMP #'H'
        BEQ DB_TT
        LDX #<NAV_HOST
        LDY #>NAV_HOST
DB_TT:  TXA
        LDX #55
        JSR DRAW_STR_N

        JSR W5500_PROBE_HW
        PHP
        LDX #GS_LED - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #$E0
        PLP
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

        LDY #78
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

DB_NC:  LDY #79
        LDA (ZP_LINE_LO),Y
DB_DL:  STA ZP_COLOR
        LDA #12
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA ZP_LINE_LO
        LDY ZP_LINE_HI
        LDX #MAX_COLS
        JSR DRAW_STR_N

        LDA ZP_LINE_LO
        EOR #$80
        STA ZP_LINE_LO
        BNE DB_AN
        INC ZP_LINE_HI
DB_AN:  CLC
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
        LDY #12
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
        LDX #$FC
        STX ZP_COLOR
        CMP #2
        BNE DUB_ED
        LDA #<STR_Q_PROMPT
        LDY #>STR_Q_PROMPT
        JSR DRAW_STR_AY
DUB_ED: LDA #<EDIT_BUF
        LDY #>EDIT_BUF
        JSR DRAW_STR_AY
        LDA #'_'
        JSR DRAW_CHAR_ADV
        JMP DUB_ST

DUB_SH: LDA #<URI_BUF
        LDY #>URI_BUF
        LDX #69
        JSR DRAW_STR_N

DUB_ST: LDA #$48
        STA ZP_X_LO
        LDA #$02
        STA ZP_X_HI
        LDY #$1C
        LDX NET_STATE
        CPX #ST_LOAD
        BCC DUB_SC
        LDY #$FC
        BEQ DUB_SC
        LDY #$E0
DUB_SC: STY ZP_COLOR
        LDY #4
DUB_SL: LDA STATUS_TBL,X
        JSR DRAW_CHAR_ADV
        INX
        DEY
        BNE DUB_SL
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
; Tabellen, GPU-Streams & Ingebouwde Gopher Startpagina
; ============================================================================
THEME_COLS:     .BYTE $FF, $1C, $F4
GTYPE_CHARS:    .BYTE '1', '0', '7', 'h'
GTYPE_BADGE:    .BYTE 'D', 'T', '?', 'W'
GTYPE_COLOR:    .BYTE $1F, $1C, $FC, $F3
LINK_PFX_TPL:   .BYTE "[01/D] "

KEY_CHARS:
        .BYTE $09, $0D, ' ', $08, '[', ']'
        .BYTE 'q', 'g', 'u', 'z', 'w', 'h', 'r', 'b', 'c', 'v', 'p'
KEY_HND_LO:
        .BYTE <(DO_NXT_LNK-1), <(OPEN_SEL_LINK-1), <(DO_PAGE_DN-1), <(DO_BACK-1)
        .BYTE <(DO_PRV_LNK-1), <(DO_NXT_LNK-1)
        .BYTE <(EXIT_TO_BASIC-1), <(START_NEW_URL-1), <(START_EDIT_URL-1)
        .BYTE <(START_VERONICA-1), <(START_WIKI-1), <(DO_HOME-1)
        .BYTE <(DO_RELOAD-1), <(DO_BACK-1), <(DO_COLOR-1)
        .BYTE <(DO_TOGGLE_VIEW-1), <(DO_PAGE_UP-1)
KEY_HND_HI:
        .BYTE >(DO_NXT_LNK-1), >(OPEN_SEL_LINK-1), >(DO_PAGE_DN-1), >(DO_BACK-1)
        .BYTE >(DO_PRV_LNK-1), >(DO_NXT_LNK-1)
        .BYTE >(EXIT_TO_BASIC-1), >(START_NEW_URL-1), >(START_EDIT_URL-1)
        .BYTE >(START_VERONICA-1), >(START_WIKI-1), >(DO_HOME-1)
        .BYTE >(DO_RELOAD-1), >(DO_BACK-1), >(DO_COLOR-1)
        .BYTE >(DO_TOGGLE_VIEW-1), >(DO_PAGE_UP-1)

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

GPU_STREAMS:
GS_UI:
        .BYTE GS_URL - GS_UI - 1
        .BYTE 12, 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 0
        .BYTE 1, $00
        .BYTE 2, 0,0, 0,0, $80,$02, 15,0, $0B
        .BYTE 2, 5,0, 41,0, $76,$02, $2B,$01, $17
        .BYTE 2, 6,0, 42,0, $74,$02, $29,$01, $00
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $0B
GS_URL:
        .BYTE GS_LED - GS_URL - 1
        .BYTE 2, 5,0, 17,0, $76,$02, 22,0, $01
        .BYTE 2, 9,0, 18,0, $36,$02, 20,0, $17
        .BYTE 2, 10,0, 19,0, $34,$02, 18,0, $00
GS_LED:
        .BYTE GS_SEL - GS_LED - 1
        .BYTE 5, $72,$02, 7,0, 4,0, 0,0
GS_SEL:
        .BYTE GS_EXIT - GS_SEL - 1
        .BYTE 2, 10,0
SEL_BAR_Y:
        .BYTE 46,0, $6C,$02, 13,0, $25
GS_EXIT:
        .BYTE STR_APP_NAME - GS_EXIT - 1
        .BYTE 12, 1, 1, $E3

STR_APP_NAME:   .ASCIIZ "GopherSurf: "
STR_HOME_TITLE: .ASCIIZ "Home (:70)"
STR_ABOUT_HOME: .ASCIIZ "gopher://home"
STR_GOPHER_PFX: .ASCIIZ "gopher://"
STR_Q_PROMPT:   .ASCIIZ "Zoek: "
STR_PFX_BIN:    .BYTE "[BIN]  "
STATUS_TBL:     .BYTE "HOMEMENUTKSTBRONWEB LAADFOUT"

STR_WEB_INFO:   .BYTE "iExterne Web-URL (B=Terug):", 10, 0
STR_BOT_HELP:   .ASCIIZ "1-9/RET:Open Z:Zoek W:Wiki G:URL B:Terug C:Kleur V:Bron H:Home"

STR_ERR_NET:    .BYTE "3GEEN LAN-LINK (W5500)", 0
STR_ERR_DNS:    .BYTE "3DNS FOUT - Geen host", 0
STR_ERR_TCP:    .BYTE "3TCP FOUT - Geen :70", 0

HOME_GOPHER:
        .BYTE "i=== GOPHERSURF 6502 - RFC 1436 GOPHER ===", 10, "i", 10
        .BYTE "1Floodgap Portal", 9, 9, "gopher.floodgap.com", 10
        .BYTE "7Veronica-2 Zoeken", 9, "/v2/vs", 9, "gopher.floodgap.com", 10
        .BYTE "1Gopherpedia", 9, 9, "gopherpedia.com", 10
        .BYTE "7Zoek Wikipedia", 9, "/lookup", 9, "gopherpedia.com", 10
        .BYTE "1SDF UNIX Gopher", 9, 9, "sdf.org", 10
        .BYTE "1Circumlunar Space", 9, 9, "zaibatsu.circumlunar.space", 10
        .BYTE "1Bitreich Project", 9, 9, "bitreich.org", 10, "i", 10
        .BYTE "iTAB:Volgende  SPATIE/P:Pagina  ESC:Stop", 0
