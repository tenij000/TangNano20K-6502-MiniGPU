; ============================================================================
; NETTERM.asm - MiniGPU W5500 Ethernet / Telnet / BBS / Chat Terminal 1.0
; Geassembleerd op $8000 in SDRAM. Terminal-buffer (18x64) op $6800-$6C7F.
; Bevat W5500 SPI Hardware Driver-laag ($A018/$A019), Live Netwerk-Dashboard
; met LED-indicatoren (PWR/LNK/TX/RX), Fosfor-thema's (Groen/Amber/Cyaan/Wit),
; Ingebouwde Retro 6502 BBS, PING-tool, W5500 Pinout-hulp & Chat/Telnet-prompt!
; Starten vanuit Midnight Commander (BRUN MC) of in BASIC met: BRUN NETTERM
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter (UART / PS/2)
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort
IO_NET_DATA     = $A030         ; W5500 SPI Data-poort (8-bit Mode 0, 3.375 MHz)
IO_NET_CTRL     = $A031         ; W5500 SPI Control (Bit 0 = CS, Bit 1 = RSTn)

ROM_SILENCE     = $E8DC

; --- Eigen Zero Page Variabelen ($60..$7F) ---
ZP_PTR_LO       = $60           ; Algemene 16-bit pointer voor strings/streams
ZP_PTR_HI       = $61
ZP_LINE_LO      = $62           ; Pointer naar terminal-rij ($6800 + rij*64)
ZP_LINE_HI      = $63
ZP_X_LO         = $64           ; 16-bit GPU X
ZP_X_HI         = $65
ZP_Y_LO         = $66           ; 16-bit GPU Y
ZP_Y_HI         = $67
ZP_COLOR        = $68           ; Huidige tekstkleur

TERM_THEME      = $69           ; 0=Groen($1C), 1=Amber($F4), 2=Cyaan($1F), 3=Wit($FF)
NET_MODE        = $6A           ; 0=LOKAAL/BBS, 1=W5500 TCP/IP, 2=UART-BRIDGE
CONN_STATE      = $6B           ; 0=STANDBY, 1=ONLINE
MENU_OPEN       = $6C           ; 0=Terminal actief, 1=Actie-menu geopend
MENU_SEL        = $6D           ; Geselecteerde menu-optie (0..5)
INP_LEN         = $6E           ; Lengte van invoerregel (0..54)
CUR_ROW         = $6F           ; Huidige rij tijdens tekenen (0..17)

TX_CNT_LO       = $70           ; 16-bit TX teller
TX_CNT_HI       = $71
RX_CNT_LO       = $72           ; 16-bit RX teller
RX_CNT_HI       = $73
W5500_VER       = $74           ; Gedetecteerde W5500 chip-versie ($04 = aanwezig)
PREV_JOY        = $75           ; Vorige joypad-status
PING_SEQ        = $76           ; Teller voor PING pakketten
TMP_COL         = $77           ; Tijdelijke rij-kleur bij toevoegen regel
ZP_BLK_LO       = $78           ; Pointer voor multi-line log blokken
ZP_BLK_HI       = $79
W5500_PHY       = $7A           ; W5500 PHYCFGR ($002E: Bit 0 = RJ45 Link UP)
POLL_CNT        = $7B           ; Teller voor periodieke W5500 Link-check
W5500_SR        = $7C           ; W5500 Socket 0 Status (Sn_SR: $14=LISTEN, $17=ESTAB)
PREV_SR         = $7D           ; Vorige Sn_SR voor detectie nieuwe Telnet-client
RX_LEN          = $7E           ; Lengte van binnenkomende Telnet-regel (0..50)
IAC_SKIP        = $7F           ; Telnet IAC ($FF) skip-teller
NEED_REDRAW     = $80           ; 1 als scherm hertekend moet worden na poll
RX_FLUSH        = $81           ; 1 als complete Telnet-regel (\r/\n) binnen is
S0_PTR_LO       = $82           ; 16-bit W5500 Socket 0 TX/RX buffer pointer Lo
S0_PTR_HI       = $83           ; 16-bit W5500 Socket 0 TX/RX buffer pointer Hi
S0_CNT          = $84           ; Aantal te lezen RX bytes

; --- Geheugenbuffers in SDRAM ($6800..$6DFF) ---
TERM_BUF        = $6800         ; 18 rijen x 64 bytes = $0480 bytes ($6800..$6C7F)
INP_BUF         = $6D00         ; 64 bytes invoerbuffer ($6D00..$6D3F)
RX_BUF          = $6D40         ; 64 bytes Telnet RX regelbuffer ($6D40..$6D7F)
TERM_MAGIC      = $6DFE         ; $5E als terminal al geïnitialiseerd is

; ============================================================================
; Start & Initialisatie
; ============================================================================
START:
        JSR ROM_SILENCE
        LDA #0
        STA IO_MODE             ; MODE 1 (volledige 640x480 GUI)
        STA ZP_Y_HI
        STA MENU_OPEN
        STA MENU_SEL
        STA INP_LEN
        STA INP_BUF
        STA RX_LEN
        STA IAC_SKIP
        STA PREV_SR

        JSR W5500_INIT_HW
        JSR W5500_POLL_NET      ; Open Socket 0 op Poort 23
        JSR W5500_POLL_NET      ; Zet Socket 0 in LISTEN ($14)

        LDA TERM_MAGIC
        CMP #$5E
        BEQ WARM_START

        LDA #$5E
        STA TERM_MAGIC
        LDA #0
        STA TERM_THEME          ; Standaard: Groen Fosfor ($1C)
        LDX W5500_VER
        CPX #$04
        BNE INIT_NO_W5500
        LDA #1                  ; Echte W5500 V04 gedetecteerd -> W5500 TCP/IP modus!
INIT_NO_W5500:
        STA NET_MODE
        LDA #0
        STA TX_CNT_LO
        STA TX_CNT_HI
        STA RX_CNT_LO
        STA RX_CNT_HI
        LDA #1
        STA CONN_STATE          ; Online

        JSR CLEAR_TERM_BUF
        LDA #<BLK_WELCOME
        LDY #>BLK_WELCOME
        JSR ADD_LOG_BLOCK

WARM_START:
        LDA IO_JOY
        STA PREV_JOY

MAIN_LOOP:
        JSR DRAW_SCREEN

WAIT_LOOP:
        JSR DELAY_10MS

        ; Periodieke W5500 Hardware, RJ45 Link & Telnet Socket 0 (Poort 23) Poll
        INC POLL_CNT
        LDA POLL_CNT
        AND #$07
        BNE WL_CHK_ESC
        JSR W5500_POLL_NET
        BCS MAIN_LOOP

WL_CHK_ESC:
        ; Controleer ESC-bit (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_JOY
        LDA IO_TERM             ; Lees ESC weg uit buffer
        LDA MENU_OPEN
        BNE EXIT_TO_BASIC       ; 2e keer ESC in menu -> afsluiten!
        LDA #1
        STA MENU_OPEN
        LDA #0
        STA MENU_SEL
        JMP MAIN_LOOP

EXIT_TO_BASIC:
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        STA IO_GPU
        LDA #$E3
        STA IO_GPU
        LDA #1
        STA IO_MODE             ; MODE 0 (BASIC tekstterminal zichtbaar)
        LDA #12
        STA IO_TERM             ; CLS
        RTS

CHK_JOY:
        LDA IO_JOY
        STA ZP_COLOR
        TAX
        EOR PREV_JOY
        AND ZP_COLOR
        STX PREV_JOY
        TAY
        BEQ CHK_KEY

        LDA MENU_OPEN
        BEQ CHK_KEY

        LDA IO_STATUS
        AND #1
        BEQ JOY_MENU_ACT
        LDA IO_TERM
        CMP #$0D
        BEQ MENU_DO_EXEC
        CMP #$0E
        BEQ TOGGLE_MENU
JOY_MENU_ACT:
        TYA
        AND #1
        BNE MENU_UP
        TYA
        AND #2
        BNE MENU_DOWN
        TYA
        AND #16
        BNE MENU_DO_EXEC
        BEQ WAIT_LOOP

MENU_UP:
        DEC MENU_SEL
        BPL GO_MAIN_1
        LDA #5
        STA MENU_SEL
        BNE GO_MAIN_1

MENU_DOWN:
        INC MENU_SEL
        LDA MENU_SEL
        CMP #6
        BCC GO_MAIN_1
        LDA #0
        STA MENU_SEL
GO_MAIN_1:
        JMP MAIN_LOOP

TOGGLE_MENU:
        LDA MENU_OPEN
        EOR #1
        STA MENU_OPEN
        LDA #0
        STA MENU_SEL
        BEQ GO_MAIN_1

MENU_DO_EXEC:
        JMP EXEC_MENU_SEL

; ============================================================================
; Toetsenbord-invoer (Menu-besturing én Volledige Tekst/Commando-invoer)
; ============================================================================
CHK_KEY:
        LDA IO_STATUS
        AND #1
        BEQ WAIT_LOOP
        LDA IO_TERM

        CMP #$0E                ; Alt / F9 -> Open/sluit Actie-Menu
        BEQ TOGGLE_MENU

        LDX MENU_OPEN
        BNE KEY_IN_MENU

        CMP #$09                ; TAB -> Wissel fosfor-kleurthema
        BEQ DO_CYCLE_THEME
        CMP #$0D                ; ENTER -> Voer commando uit / verstuur regel
        BEQ DO_SUBMIT_LINE
        CMP #$08                ; Backspace
        BEQ DO_BACKSPACE
        CMP #$7F                ; Delete / Backspace
        BEQ DO_BACKSPACE

        CMP #' '
        BCC WAIT_LOOP
        CMP #$7F
        BCS WAIT_LOOP

        CMP #'a'
        BCC KEY_STORE_CHAR
        CMP #'z'+1
        BCS KEY_STORE_CHAR
        AND #$DF

KEY_STORE_CHAR:
        LDX INP_LEN
        CPX #54
        BCS WAIT_LOOP
        STA INP_BUF,X
        INX
        STX INP_LEN
        LDA #0
        STA INP_BUF,X
        JSR DRAW_INPUT_BAR
        JMP WAIT_LOOP

DO_BACKSPACE:
        LDX INP_LEN
        BEQ WAIT_LOOP
        DEX
        STX INP_LEN
        LDA #0
        STA INP_BUF,X
        JSR DRAW_INPUT_BAR
        JMP WAIT_LOOP

DO_CYCLE_THEME:
        INC TERM_THEME
        LDA TERM_THEME
        AND #3
        STA TERM_THEME
        JMP MAIN_LOOP

KEY_IN_MENU:
        CMP #$0D
        BEQ EXEC_MENU_SEL
        CMP #' '
        BEQ EXEC_MENU_SEL
        CMP #'0'
        BEQ EXIT_TO_BASIC
        CMP #'Q'
        BEQ EXIT_TO_BASIC
        CMP #'q'
        BEQ EXIT_TO_BASIC
        CMP #'1'
        BCC KIM_DONE
        CMP #'7'
        BCS KIM_DONE
        SEC
        SBC #'1'
        STA MENU_SEL
        JMP EXEC_MENU_SEL
KIM_DONE:
        JMP WAIT_LOOP

EXEC_MENU_SEL:
        LDA #0
        STA MENU_OPEN
        LDA MENU_SEL
        CMP #0
        BEQ EMS_BBS
        CMP #1
        BEQ EMS_PING
        CMP #2
        BEQ EMS_STATUS
        CMP #3
        BEQ EMS_W5500
        CMP #4
        BEQ EMS_MODE_THEME
        JMP EXIT_TO_BASIC

EMS_BBS:
        JSR CMD_BBS
        JMP MAIN_LOOP
EMS_PING:
        JSR CMD_PING
        JMP MAIN_LOOP
EMS_STATUS:
        JSR CMD_STATUS
        JMP MAIN_LOOP
EMS_W5500:
        JSR CMD_W5500_PINOUT
        JMP MAIN_LOOP
EMS_MODE_THEME:
        JSR CYCLE_NET_MODE
        JMP DO_CYCLE_THEME

; ============================================================================
; Verwerken van een ingetypte regel op de NET> prompt
; ============================================================================
DO_SUBMIT_LINE:
        LDA INP_LEN
        BNE DSL_HAS_TEXT
        JMP WAIT_LOOP

DSL_HAS_TEXT:
        ; 1. Echo de ingetypte regel naar het terminalscherm in Wit ($FF)
        JSR SCROLL_AND_GET_BOT
        LDY #0
        LDA #'N'
        STA (ZP_LINE_LO),Y
        INY
        LDA #'E'
        STA (ZP_LINE_LO),Y
        INY
        LDA #'T'
        STA (ZP_LINE_LO),Y
        INY
        LDA #'>'
        STA (ZP_LINE_LO),Y
        INY
        LDA #' '
        STA (ZP_LINE_LO),Y
        INY
        LDX #0
DSL_CP_ECHO:
        LDA INP_BUF,X
        BEQ DSL_ECHO_DN
        STA (ZP_LINE_LO),Y
        INX
        INY
        CPY #62
        BCC DSL_CP_ECHO
DSL_ECHO_DN:
        LDA #0
        STA (ZP_LINE_LO),Y
        LDY #63
        LDA #$FF
        STA (ZP_LINE_LO),Y

        ; 2. Controleer op '?' of ingebouwde commando-tabel
        LDA INP_BUF
        CMP #'?'
        BNE DSL_SCAN_KW
        JSR CMD_HELP
        JMP DSL_CLEAR_INP

DSL_SCAN_KW:
        LDX #0
DSL_KW_LP:
        LDA KW_LIST_LO,X
        LDY KW_LIST_HI,X
        STX CUR_ROW
        JSR MATCH_INP_KW
        LDX CUR_ROW
        BCS DSL_KW_MATCH
        INX
        CPX #9
        BCC DSL_KW_LP

        ; 3. Geen commando -> Verstuur als TCP/UDP/Chat-bericht!
        JSR W5500_TX_PACKET
        JSR INC_RX_CNT
        LDA #<BLK_CHAT
        LDY #>BLK_CHAT
        JSR ADD_LOG_BLOCK
        JMP DSL_CLEAR_INP

DSL_KW_MATCH:
        CPX #8
        BNE DSL_DO_CMD
        JMP EXIT_TO_BASIC
DSL_DO_CMD:
        LDA KW_HND_LO,X
        STA ZP_PTR_LO
        LDA KW_HND_HI,X
        STA ZP_PTR_HI
        JSR CALL_PTR

DSL_CLEAR_INP:
        LDA #0
        STA INP_LEN
        STA INP_BUF
        JMP MAIN_LOOP

CALL_PTR:
        JMP (ZP_PTR_LO)

; --- Vergelijk begin van INP_BUF met keyword op (A=lo, Y=hi), Carry=1 bij match ---
MATCH_INP_KW:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDY #0
MIK_LP:
        TYA
        TAX
        LDA (ZP_PTR_LO),Y
        BEQ MIK_CHK_END
        CMP INP_BUF,X
        BNE MIK_NO
        INY
        BNE MIK_LP
MIK_CHK_END:
        LDA INP_BUF,Y
        BEQ MIK_YES
        CMP #' '
        BEQ MIK_YES
MIK_NO:
        CLC
        RTS
MIK_YES:
        SEC
        RTS

; ============================================================================
; Ingebouwde Terminal- & Netwerk-commando's (HELP, PING, BBS, STATUS, W5500)
; ============================================================================
CMD_HELP:
        LDA #<BLK_HELP
        LDY #>BLK_HELP
        JMP ADD_LOG_BLOCK

CMD_PING:
        LDA #<STR_PNG_HDR
        LDY #>STR_PNG_HDR
        LDX #$FC
        JSR ADD_LOG_LINE_COL

        LDA #1
        STA PING_SEQ
PING_LP:
        JSR W5500_TX_PACKET
        JSR INC_RX_CNT
        LDA #<STR_PNG_REP
        LDY #>STR_PNG_REP
        LDX #0
        JSR ADD_LOG_LINE_COL
        LDY #41
        LDA PING_SEQ
        CLC
        ADC #'0'
        STA (ZP_LINE_LO),Y
        JSR DRAW_SCREEN
        JSR DELAY_10MS
        INC PING_SEQ
        LDA PING_SEQ
        CMP #5
        BCC PING_LP

        LDA #<STR_PNG_SUM
        LDY #>STR_PNG_SUM
        LDX #$1F
        JMP ADD_LOG_LINE_COL

CMD_BBS:
        LDA #1
        STA CONN_STATE
        JSR W5500_TX_PACKET
        JSR INC_RX_CNT
        JSR INC_RX_CNT
        LDA #<BLK_BBS
        LDY #>BLK_BBS
        JMP ADD_LOG_BLOCK

CMD_STATUS:
        JSR W5500_INIT_HW
        LDA #<BLK_STATUS
        LDY #>BLK_STATUS
        JMP ADD_LOG_BLOCK

CMD_W5500_PINOUT:
        LDA #<BLK_PINOUT
        LDY #>BLK_PINOUT
        JMP ADD_LOG_BLOCK

CMD_COLOR:
        INC TERM_THEME
        LDA TERM_THEME
        AND #3
        STA TERM_THEME
        RTS

CYCLE_NET_MODE:
        INC NET_MODE
        LDA NET_MODE
        CMP #3
        BCC CNM_OK
        LDA #0
        STA NET_MODE
CNM_OK:
        LDA #<STR_LOG_MODE
        LDY #>STR_LOG_MODE
        LDX #$FC
        JMP ADD_LOG_LINE_COL

; Voeg meerdere regels achter elkaar toe uit een blok: [col_byte, "tekst", 0, ..., $FF]
ADD_LOG_BLOCK:
        STA ZP_BLK_LO
        STY ZP_BLK_HI
ALB_LP:
        LDY #0
        LDA (ZP_BLK_LO),Y
        CMP #$FE
        BEQ ALB_RTS
        TAX                     ; Kleur in X
        INC ZP_BLK_LO
        BNE ALB_P1
        INC ZP_BLK_HI
ALB_P1:
        LDA ZP_BLK_LO
        LDY ZP_BLK_HI
        JSR ADD_LOG_LINE_COL
        ; Schuif ZP_BLK_LO/HI voorbij het 0-byte van deze string
        LDY #0
ALB_SKP:
        LDA (ZP_BLK_LO),Y
        INC ZP_BLK_LO
        BNE ALB_S1
        INC ZP_BLK_HI
ALB_S1:
        CMP #0
        BNE ALB_SKP
        BEQ ALB_LP
ALB_RTS:
        RTS

; ============================================================================
; W5500 Hardware SPI & TCP Telnet Server (Poort 23 op 192.168.178.200)
; ============================================================================
SPI_BRAM_STUB   = $02F0         ; 7-byte SPI helper in interne BRAM ($02F0)

W5500_INIT_HW:
        LDX #6
WIH_STUB:
        LDA W5500_STUB_BYTES,X
        STA SPI_BRAM_STUB,X
        DEX
        BPL WIH_STUB

        LDA #$02                ; CS = 0 (actief), RSTn = 1
        STA IO_NET_CTRL
        LDX #0
WIH_LP:
        LDA W5500_INIT_TBL,X
        JSR SPI_BRAM_STUB
        INX
        CPX #22
        BCC WIH_LP
        LDA #$03                ; CS = 1 (inactief), RSTn = 1
        STA IO_NET_CTRL

W5500_PROBE_HW:
        LDA #$39                ; VERSIONR ($0039) -> $04 op echte W5500
        JSR W5500_RD_CREG
        STA W5500_VER
        LDA #$2E                ; PHYCFGR ($002E) -> Bit 0 = RJ45 Link Status
        JSR W5500_RD_CREG
        STA W5500_PHY
        RTS

W5500_RD_S0:
        LDY #$08                ; Control = $08 (Socket 0 Reg Read, VDM)
        BNE W5500_RD_Y
W5500_RD_CREG:
        LDY #$00                ; Control = $00 (Common Reg Read, VDM)
W5500_RD_Y:
        PHA
        LDA #$02                ; CS = 0 (actief)
        STA IO_NET_CTRL
        LDA #$00                ; Offset Hi = $00
        JSR SPI_BRAM_STUB
        PLA                     ; Offset Lo
        JSR SPI_BRAM_STUB
        TYA                     ; Control byte ($00 of $08)
        JSR SPI_BRAM_STUB
        LDA #$00                ; Dummy klok-byte voor Data Phase
        JSR SPI_BRAM_STUB       ; Ontvangen byte van W5500 MISO in A
        PHA
        LDA #$03                ; CS = 1 (inactief)
        STA IO_NET_CTRL
        PLA
        RTS

W5500_WR_S0:
        PHA
        LDA #$02                ; CS = 0 (actief)
        STA IO_NET_CTRL
        LDA #$00                ; Offset Hi = $00
        JSR SPI_BRAM_STUB
        TXA                     ; Offset Lo in X
        JSR SPI_BRAM_STUB
        LDA #$0C                ; Control = $0C (Socket 0 Reg Write, VDM)
        JSR SPI_BRAM_STUB
        PLA                     ; Data byte
        JSR SPI_BRAM_STUB
        LDA #$03                ; CS = 1 (inactief)
        STA IO_NET_CTRL
        RTS

SPI_AND_INC_PTR:
        JSR SPI_BRAM_STUB
        INC S0_PTR_LO
        BNE SAIP_RTS
        INC S0_PTR_HI
SAIP_RTS:
        RTS

W5500_POLL_NET:
        LDA #0
        STA NEED_REDRAW
        LDA W5500_PHY
        PHA
        JSR W5500_PROBE_HW
        PLA
        CMP W5500_PHY
        BEQ WPN_CHK_V
        INC NEED_REDRAW
WPN_CHK_V:
        LDA W5500_VER
        CMP #$04
        BNE WPN_RET

        LDA #$03                ; Sn_SR ($0003) Socket 0 Status
        JSR W5500_RD_S0
        STA W5500_SR
        CMP #$17                ; SOCK_ESTABLISHED?
        BEQ WPN_ESTAB
        CMP #$1C                ; SOCK_CLOSE_WAIT? Lees eerst evt. RX data!
        BEQ WPN_CHK_RX
        STA PREV_SR
        CMP #$14                ; SOCK_LISTEN?
        BEQ WPN_RET
        CMP #$13                ; SOCK_INIT? -> LISTEN ($02)
        BNE WPN_CHK_C
        LDX #$01
        LDA #$02
        JSR W5500_WR_S0
        JMP WPN_RET
WPN_CHK_C:
        CMP #$00                ; SOCK_CLOSED? -> Open TCP Poort 23
        BEQ WPN_OPEN
WPN_DO_CLOSE:
        STA PREV_SR
        LDX #$01                ; Anders (bijv. $1C CLOSE_WAIT): CLOSE ($10)
        LDA #$10
        JSR W5500_WR_S0
        JMP WPN_RET
WPN_OPEN:
        LDX #$00                ; Sn_MR = $21 (TCP + No Delayed ACK)
        LDA #$21
        JSR W5500_WR_S0
        LDX #$04                ; Sn_PORT0 = $00
        LDA #$00
        JSR W5500_WR_S0
        LDX #$05                ; Sn_PORT1 = 23 (Telnet Poort 23)
        LDA #23
        JSR W5500_WR_S0
        LDX #$01                ; Sn_CR = OPEN ($01)
        LDA #$01
        JSR W5500_WR_S0
WPN_RET:
        LDA NEED_REDRAW
        CMP #1
        RTS

WPN_ESTAB:
        LDA PREV_SR
        CMP #$17
        BEQ WPN_CHK_RX
        LDA #$17
        STA PREV_SR
        LDA #0
        STA RX_LEN
        STA IAC_SKIP
        LDA #<STR_TN_CONN
        LDY #>STR_TN_CONN
        LDX #$FC
        JSR ADD_LOG_LINE_COL
        LDA #<STR_TN_BANNER
        LDY #>STR_TN_BANNER
        JSR W5500_TX_STR_AY
        INC NEED_REDRAW

WPN_CHK_RX:
        LDA #$27                ; Sn_RX_RSR1 (Lo)
        JSR W5500_RD_S0
        STA S0_CNT
        LDA #$26                ; Sn_RX_RSR0 (Hi)
        JSR W5500_RD_S0
        BEQ WPN_RSR_OK
        LDA #64
        STA S0_CNT
WPN_RSR_OK:
        LDA S0_CNT
        BNE WPN_HAS_RX
        LDA W5500_SR
        CMP #$1C
        BEQ WPN_DO_CLOSE
        JMP WPN_RET
WPN_HAS_RX:

        LDA #$28                ; Sn_RX_RD0 (Hi)
        JSR W5500_RD_S0
        STA S0_PTR_HI
        LDA #$29                ; Sn_RX_RD1 (Lo)
        JSR W5500_RD_S0
        STA S0_PTR_LO

        LDA #0
        STA RX_FLUSH
        LDA #$02                ; CS = 0
        STA IO_NET_CTRL
        LDA S0_PTR_HI
        JSR SPI_BRAM_STUB
        LDA S0_PTR_LO
        JSR SPI_BRAM_STUB
        LDA #$18                ; Control = $18 (Socket 0 RX Buffer Read)
        JSR SPI_BRAM_STUB

WPN_RX_LP:
        LDA #$00
        JSR SPI_AND_INC_PTR
        LDX IAC_SKIP
        BEQ WPN_NO_IAC
        DEC IAC_SKIP
        JMP WPN_RX_NXT
WPN_NO_IAC:
        CMP #$FF                ; Telnet IAC (255)?
        BNE WPN_CHK_EOL
        LDA #2
        STA IAC_SKIP
        BNE WPN_RX_NXT
WPN_CHK_EOL:
        CMP #$0D
        BEQ WPN_EOL
        CMP #$0A
        BNE WPN_CHK_BS
WPN_EOL:
        LDA RX_LEN
        BEQ WPN_RX_NXT
        INC RX_FLUSH
        BNE WPN_RX_DN
WPN_CHK_BS:
        CMP #$08
        BNE WPN_CHK_PRN
        LDX RX_LEN
        BEQ WPN_RX_NXT
        DEC RX_LEN
        JMP WPN_RX_NXT
WPN_CHK_PRN:
        CMP #$20
        BCC WPN_RX_NXT
        CMP #$7F
        BCS WPN_RX_NXT
        LDX RX_LEN
        CPX #50
        BCS WPN_RX_NXT
        STA RX_BUF+4,X
        INX
        STX RX_LEN
WPN_RX_NXT:
        DEC S0_CNT
        BNE WPN_RX_LP

WPN_RX_DN:
        LDA #$03                ; CS = 1
        STA IO_NET_CTRL
        LDX #$28                ; Update Sn_RX_RD0
        LDA S0_PTR_HI
        JSR W5500_WR_S0
        LDX #$29                ; Update Sn_RX_RD1
        LDA S0_PTR_LO
        JSR W5500_WR_S0
        LDX #$01                ; Sn_CR = RECV ($40)
        LDA #$40
        JSR W5500_WR_S0
        JSR INC_RX_CNT

        LDA RX_FLUSH
        BNE WPN_FLUSH
        LDA RX_LEN
        CMP #50
        BCC WPN_JMP_RET
WPN_FLUSH:
        LDA #'P'
        STA RX_BUF
        LDA #'C'
        STA RX_BUF+1
        LDA #'>'
        STA RX_BUF+2
        LDA #' '
        STA RX_BUF+3
        LDX RX_LEN
        LDA #0
        STA RX_BUF+4,X
        STA RX_LEN
        LDA #<RX_BUF
        LDY #>RX_BUF
        LDX #$1F
        JSR ADD_LOG_LINE_COL
        INC NEED_REDRAW
WPN_JMP_RET:
        JMP WPN_RET

W5500_TX_PACKET:
        LDA #<INP_BUF
        LDY #>INP_BUF
W5500_TX_STR_AY:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        INC TX_CNT_LO
        BNE WTP_HW
        INC TX_CNT_HI
WTP_HW:
        LDA #$24                ; Sn_TX_WR0 (Hi)
        JSR W5500_RD_S0
        STA S0_PTR_HI
        LDA #$25                ; Sn_TX_WR1 (Lo)
        JSR W5500_RD_S0
        STA S0_PTR_LO

        LDA #$02                ; CS = 0 (actief)
        STA IO_NET_CTRL
        LDA S0_PTR_HI
        JSR SPI_BRAM_STUB
        LDA S0_PTR_LO
        JSR SPI_BRAM_STUB
        LDA #$14                ; Control = $14 (Socket 0 TX Buffer Write)
        JSR SPI_BRAM_STUB

        LDY #0
WTP_PFX:
        LDA STR_TX_PFX,Y
        BEQ WTP_BODY
        JSR SPI_AND_INC_PTR
        INY
        BNE WTP_PFX
WTP_BODY:
        LDY #0
WTP_LP:
        LDA (ZP_PTR_LO),Y
        BEQ WTP_DN
        JSR SPI_AND_INC_PTR
        INY
        BNE WTP_LP
WTP_DN:
        LDA #$0D
        JSR SPI_AND_INC_PTR
        LDA #$0A
        JSR SPI_AND_INC_PTR
        LDA #$03                ; CS = 1 (inactief)
        STA IO_NET_CTRL

        LDX #$24                ; Update Sn_TX_WR0
        LDA S0_PTR_HI
        JSR W5500_WR_S0
        LDX #$25                ; Update Sn_TX_WR1
        LDA S0_PTR_LO
        JSR W5500_WR_S0
        LDX #$01                ; Sn_CR = SEND ($20)
        LDA #$20
        JMP W5500_WR_S0

W5500_STUB_BYTES:
        STA IO_NET_DATA
        LDA IO_NET_DATA
        RTS

W5500_INIT_TBL:
        .BYTE $00, $00, $04                     ; Offset $0000, Write Common Regs VDM
        .BYTE $00                               ; MR: Ping Block UIT (Hardware Ping AAN!)
        .BYTE 192, 168, 178, 1                  ; GAR: Gateway 192.168.178.1
        .BYTE 255, 255, 255, 0                  ; SUBR: Subnet 255.255.255.0
        .BYTE $02, $65, $02, $20, $00, $01      ; SHAR: MAC 02:65:02:20:00:01
        .BYTE 192, 168, 178, 200                ; SIPR: Eigen IP 192.168.178.200

INC_RX_CNT:
        INC RX_CNT_LO
        BNE IRC_RTS
        INC RX_CNT_HI
IRC_RTS:
        RTS

; ============================================================================
; Terminal Buffer Beheer (16 rijen x 64 bytes op $6800..$6BFF)
; ============================================================================
CLEAR_TERM_BUF:
        LDA #<TERM_BUF
        STA ZP_LINE_LO
        LDA #>TERM_BUF
        STA ZP_LINE_HI
        LDX #16
CTB_ROW:
        LDY #63
        LDA #0
CTB_BYTE:
        STA (ZP_LINE_LO),Y
        DEY
        BPL CTB_BYTE
        CLC
        LDA ZP_LINE_LO
        ADC #64
        STA ZP_LINE_LO
        BCC CTB_NXT
        INC ZP_LINE_HI
CTB_NXT:
        DEX
        BNE CTB_ROW
        RTS

CALC_ROW_PTR:
        STA ZP_LINE_LO
        LDA #0
        STA ZP_LINE_HI
        LDY #6
CRP_LP:
        ASL ZP_LINE_LO
        ROL ZP_LINE_HI
        DEY
        BNE CRP_LP
        CLC
        LDA ZP_LINE_HI
        ADC #>TERM_BUF
        STA ZP_LINE_HI
        RTS

SCROLL_AND_GET_BOT:
        LDA #0
        STA CUR_ROW
SAGB_LP:
        LDA CUR_ROW
        JSR CALC_ROW_PTR
        LDA ZP_LINE_LO
        STA ZP_X_LO
        LDA ZP_LINE_HI
        STA ZP_X_HI

        LDA CUR_ROW
        CLC
        ADC #1
        JSR CALC_ROW_PTR

        LDY #63
SAGB_CP:
        LDA (ZP_LINE_LO),Y
        STA (ZP_X_LO),Y
        DEY
        BPL SAGB_CP

        INC CUR_ROW
        LDA CUR_ROW
        CMP #15
        BCC SAGB_LP

        LDA #15
        JSR CALC_ROW_PTR
        LDY #63
        LDA #0
SAGB_CLR:
        STA (ZP_LINE_LO),Y
        DEY
        BPL SAGB_CLR
        RTS

ADD_LOG_LINE_COL:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        STX TMP_COL
        JSR SCROLL_AND_GET_BOT
        LDY #0
ALLC_LP:
        LDA (ZP_PTR_LO),Y
        BEQ ALLC_DN
        STA (ZP_LINE_LO),Y
        INY
        CPY #62
        BCC ALLC_LP
ALLC_DN:
        LDA #0
        STA (ZP_LINE_LO),Y
        LDY #63
        LDA TMP_COL
        STA (ZP_LINE_LO),Y
        RTS

; ============================================================================
; Volledig Scherm Opbouwen via MiniGPU ($A020)
; ============================================================================
SET_X14_Y:
        STA ZP_Y_LO
        STX ZP_COLOR
        LDA #14
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        RTS

DRAW_SCREEN:
        LDX #0
DS_UI_LP:
        LDA UI_STREAM,X
        STA IO_GPU
        INX
        CPX #UI_STREAM_END - UI_STREAM
        BCC DS_UI_LP

        ; Teken Top Titelbalk
        LDA #4
        LDX #$FC
        JSR SET_X14_Y
        LDA #<STR_TOP_TITLE
        LDY #>STR_TOP_TITLE
        JSR DRAW_STR_AY

        ; Teken Dashboard Rij 1 (MAC, IP, Poort)
        LDA #21
        LDX #$FF
        JSR SET_X14_Y
        LDA #<STR_DASH_1
        LDY #>STR_DASH_1
        JSR DRAW_STR_AY

        ; Teken Dashboard Rij 2 (Modus, TX/RX tellers)
        LDA #33
        LDX #$1F
        JSR SET_X14_Y
        LDA #<STR_DASH_MODE
        LDY #>STR_DASH_MODE
        JSR DRAW_STR_AY

        LDX NET_MODE
        LDA MODE_STR_LO,X
        LDY MODE_STR_HI,X
        JSR DRAW_STR_AY

        LDA #<STR_DASH_TX
        LDY #>STR_DASH_TX
        JSR DRAW_STR_AY
        LDA TX_CNT_HI
        JSR DRAW_HEX8
        LDA TX_CNT_LO
        JSR DRAW_HEX8

        LDA #<STR_DASH_RX
        LDY #>STR_DASH_RX
        JSR DRAW_STR_AY
        LDA RX_CNT_HI
        JSR DRAW_HEX8
        LDA RX_CNT_LO
        JSR DRAW_HEX8

        ; Teken Dashboard Rij 3 (W5500 SPI Hardware & RJ45 Link Status)
        LDA #45
        LDX #$FC
        JSR SET_X14_Y
        LDA W5500_VER
        CMP #$04
        BNE DS_HW_WAIT
        LDA W5500_PHY
        AND #$01
        BEQ DS_HW_WAIT
        LDA #$1C                ; Felgroen als W5500 V04 + RJ45 Link UP!
        STA ZP_COLOR
        LDA #<STR_DASH_HW_OK
        LDY #>STR_DASH_HW_OK
        JMP DS_HW_PRT
DS_HW_WAIT:
        LDA #<STR_DASH_HW_SIM
        LDY #>STR_DASH_HW_SIM
DS_HW_PRT:
        JSR DRAW_STR_AY

        ; Teken LNK LED ($0232, 41) in Rood($E0)/Geel($FC)/Groen($1C) op basis van echte W5500!
        LDA #5
        STA IO_GPU
        LDA #$32
        STA IO_GPU
        LDA #$02
        STA IO_GPU
        LDA #41
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #5
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA #$E0                ; Rood = Geen W5500
        LDX W5500_VER
        CPX #$04
        BNE DS_LNK_COL
        LDA #$FC                ; Geel = W5500 V04, wacht op RJ45 kabel
        LDX W5500_PHY
        TXA
        AND #$01
        BEQ DS_LNK_COL
        LDA #$1C                ; Groen = RJ45 Link UP!
DS_LNK_COL:
        STA IO_GPU

        ; Teken Labels bij de 4 Status-LEDs rechtsboven
        LDA #$04
        STA ZP_X_LO
        LDA #$02
        STA ZP_X_HI
        LDA #21
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COLOR
        LDA #<STR_LED_LBL
        LDY #>STR_LED_LBL
        JSR DRAW_STR_AY

        ; Teken alle 16 Terminal-rijen (Y = 66 + rij*15, binnen 640x360!)
        LDA #0
        STA CUR_ROW
DS_ROW_LP:
        LDA CUR_ROW
        JSR CALC_ROW_PTR
        LDY #0
        LDA (ZP_LINE_LO),Y
        BEQ DS_ROW_NEXT

        LDA #66
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDX CUR_ROW
        BEQ DS_Y_OK
DS_Y_ADD:
        CLC
        LDA ZP_Y_LO
        ADC #15
        STA ZP_Y_LO
        BCC DS_Y_NXT
        INC ZP_Y_HI
DS_Y_NXT:
        DEX
        BNE DS_Y_ADD
DS_Y_OK:
        LDA #16
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI

        LDY #63
        LDA (ZP_LINE_LO),Y
        BNE DS_SET_RCOL
        LDX TERM_THEME
        LDA THEME_COL_TBL,X
DS_SET_RCOL:
        STA ZP_COLOR

        LDA ZP_LINE_LO
        LDY ZP_LINE_HI
        JSR DRAW_STR_AY

DS_ROW_NEXT:
        INC CUR_ROW
        LDA CUR_ROW
        CMP #16
        BCC DS_ROW_LP

        JSR DRAW_INPUT_BAR

        LDA #10
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$5B                ; Y = 347 ($015B)
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_COLOR
        LDA #<STR_BOT_BAR
        LDY #>STR_BOT_BAR
        JSR DRAW_STR_AY

        LDA MENU_OPEN
        BEQ DS_DONE
        JMP DRAW_POPUP_MENU
DS_DONE:
        RTS

DRAW_INPUT_BAR:
        LDX #0
DIB_RECT_LP:
        LDA INP_BAR_STREAM,X
        STA IO_GPU
        INX
        CPX #INP_BAR_STREAM_END - INP_BAR_STREAM
        BCC DIB_RECT_LP

        LDA #16
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$42                ; Y = 322 ($0142)
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$FC
        STA ZP_COLOR
        LDA #<STR_PROMPT
        LDY #>STR_PROMPT
        JSR DRAW_STR_AY

        LDX TERM_THEME
        LDA THEME_COL_TBL,X
        STA ZP_COLOR
        LDA #<INP_BUF
        LDY #>INP_BUF
        JSR DRAW_STR_AY
        LDA #'_'
        JMP DRAW_CHAR_ADV

; ============================================================================
; Teken het ESC / Alt Actie-Menu
; ============================================================================
DRAW_POPUP_MENU:
        LDX #0
DPM_BOX_LP:
        LDA MENU_BOX_STREAM,X
        STA IO_GPU
        INX
        CPX #MENU_BOX_STREAM_END - MENU_BOX_STREAM
        BCC DPM_BOX_LP

        LDA #204
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #110
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_COLOR
        LDA #<STR_MENU_HDR
        LDY #>STR_MENU_HDR
        JSR DRAW_STR_AY

        LDA #0
        STA CUR_ROW
DPM_LP:
        LDA CUR_ROW
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #132
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        LDA CUR_ROW
        CMP MENU_SEL
        BNE DPM_NOT_SEL

        LDA #2
        STA IO_GPU
        LDA #196
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_Y_LO
        SEC
        SBC #2
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #248
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #13
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$FC
        STA IO_GPU
        LDA #$00
        STA ZP_COLOR
        JMP DPM_TXT

DPM_NOT_SEL:
        LDA #$FF
        STA ZP_COLOR

DPM_TXT:
        LDA #206
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDX CUR_ROW
        LDA MENU_STR_LO,X
        LDY MENU_STR_HI,X
        JSR DRAW_STR_AY

        INC CUR_ROW
        LDA CUR_ROW
        CMP #6
        BCC DPM_LP
        RTS

; ============================================================================
; Tekst & Hex Hulproutines
; ============================================================================
DRAW_STR_AY:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DRAW_STR:
        LDY #0
        LDA (ZP_PTR_LO),Y
        INC ZP_PTR_LO
        BNE DST_CHK
        INC ZP_PTR_HI
DST_CHK:
        CMP #0
        BEQ DST_RTS
        JSR DRAW_CHAR_ADV
        JMP DRAW_STR
DST_RTS:
        RTS

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
        BCC DCA_RTS
        INC ZP_X_HI
DCA_RTS:
        RTS

DRAW_HEX8:
        PHA
        LSR A
        LSR A
        LSR A
        LSR A
        JSR DRAW_HEX_NIB
        PLA
        AND #$0F
DRAW_HEX_NIB:
        CMP #10
        BCC DHN_DIG
        CLC
        ADC #('A' - 10)
        JMP DRAW_CHAR_ADV
DHN_DIG:
        CLC
        ADC #'0'
        JMP DRAW_CHAR_ADV

DELAY_10MS:
        LDA IO_TIMER
D10_WAIT:
        CMP IO_TIMER
        BEQ D10_WAIT
        RTS

; ============================================================================
; GPU Streams & Commando-/Kleurentabellen
; ============================================================================
THEME_COL_TBL:
        .BYTE $1C, $F4, $1F, $FF

KW_LIST_LO:
        .BYTE <STR_KW_HELP, <STR_KW_PING, <STR_KW_BBS, <STR_KW_STAT, <STR_KW_W5500
        .BYTE <STR_KW_CLS, <STR_KW_COLOR, <STR_KW_MODE, <STR_KW_EXIT
KW_LIST_HI:
        .BYTE >STR_KW_HELP, >STR_KW_PING, >STR_KW_BBS, >STR_KW_STAT, >STR_KW_W5500
        .BYTE >STR_KW_CLS, >STR_KW_COLOR, >STR_KW_MODE, >STR_KW_EXIT

KW_HND_LO:
        .BYTE <CMD_HELP, <CMD_PING, <CMD_BBS, <CMD_STATUS, <CMD_W5500_PINOUT
        .BYTE <CLEAR_TERM_BUF, <CMD_COLOR, <CYCLE_NET_MODE
KW_HND_HI:
        .BYTE >CMD_HELP, >CMD_PING, >CMD_BBS, >CMD_STATUS, >CMD_W5500_PINOUT
        .BYTE >CLEAR_TERM_BUF, >CMD_COLOR, >CYCLE_NET_MODE

MODE_STR_LO:
        .BYTE <STR_M0, <STR_M1, <STR_M2
MODE_STR_HI:
        .BYTE >STR_M0, >STR_M1, >STR_M2

MENU_STR_LO:
        .BYTE <STR_MI_1, <STR_MI_2, <STR_MI_3, <STR_MI_4, <STR_MI_5, <STR_MI_6
MENU_STR_HI:
        .BYTE >STR_MI_1, >STR_MI_2, >STR_MI_3, >STR_MI_4, >STR_MI_5, >STR_MI_6

UI_STREAM:
        .BYTE 12, 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 0
        .BYTE 1, $01

        ; Top Titelbalk (0,0, 640x15, $03)
        .BYTE 2, 0,0, 0,0, $80,$02, 15,0, $03
        ; Netwerk Dashboard Kader (6,17, 628x41, $02) + Cyaan randen
        .BYTE 2, 6,0, 17,0, $74,$02, 41,0, $02
        .BYTE 3, 6,0, 17,0, $7A,$02, 17,0, $1F
        .BYTE 3, 6,0, 58,0, $7A,$02, 58,0, $1F

        ; 4 Hardware Status-LEDs op Y=41
        .BYTE 5, $0E,$02, 41,0, 5,0, 0,0, $1C
        .BYTE 5, $32,$02, 41,0, 5,0, 0,0, $1C
        .BYTE 5, $56,$02, 41,0, 5,0, 0,0, $1F
        .BYTE 5, $72,$02, 41,0, 5,0, 0,0, $FC

        ; Hoofd CRT Terminal Venster (6,61, 628x250 -> Y=61..311, Zwart $00) + Groene rand
        .BYTE 2, 6,0, 61,0, $74,$02, 250,0, $00
        .BYTE 3, 6,0, 61,0, $7A,$02, 61,0, $1C
        .BYTE 3, 6,0, $37,$01, $7A,$02, $37,$01, $1C
        .BYTE 3, 6,0, 61,0, 6,0, $37,$01, $1C
        .BYTE 3, $7A,$02, 61,0, $7A,$02, $37,$01, $1C

        ; Onderste Sneltoetsbalk op Y=342 ($0156), hoogte 18 (tot Y=360!)
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $03
UI_STREAM_END:

INP_BAR_STREAM:
        ; NET> Invoerbalk op Y=315 ($013B), hoogte 23 (Y=315..338)
        .BYTE 2, 6,0, $3B,$01, $74,$02, 23,0, $02
        .BYTE 3, 6,0, $3B,$01, $7A,$02, $3B,$01, $1F
        .BYTE 3, 6,0, $52,$01, $7A,$02, $52,$01, $1F
INP_BAR_STREAM_END:

MENU_BOX_STREAM:
        .BYTE 2, 188,0, 100,0, $08,$01, 140,0, $1F
        .BYTE 2, 190,0, 102,0, $04,$01, 136,0, $02
MENU_BOX_STREAM_END:

; ============================================================================
; Tekst-strings & Multi-Line Log Blokken
; ============================================================================
STR_TOP_TITLE:
        .ASCIIZ "MiniGPU NETTERM 1.2 - W5500 Telnet Server (Poort 23)"
STR_DASH_1:
        .ASCIIZ "MAC: 02:65:02:20:00:01  IP: 192.168.178.200  POORT: 23"
STR_DASH_MODE:
        .ASCIIZ "MODUS: "
STR_M0: .ASCIIZ "[W5500-LAN]"
STR_M1: .ASCIIZ "[TELNET-23]"
STR_M2: .ASCIIZ "[UART-CHAT]"
STR_DASH_TX:
        .ASCIIZ " TX:$"
STR_DASH_RX:
        .ASCIIZ " RX:$"
STR_DASH_HW_SIM:
        .ASCIIZ "W5500 ($A030): CHIP V04 GEVONDEN - STEEK RJ45 KABEL IN!"
STR_DASH_HW_OK:
        .ASCIIZ "W5500 ($A030): TELNET SERVER ONLINE OP 192.168.178.200:23!"
STR_LED_LBL:
        .ASCIIZ "PWR LNK TX RX"
STR_PROMPT:
        .ASCIIZ "NET> "
STR_BOT_BAR:
        .ASCIIZ "ESC:Menu TAB:Kleur Telnet: 192.168.178.200 23 | HELP PING BBS"

STR_MENU_HDR:
        .ASCIIZ "== NETTERM MENU =="
STR_MI_1:
        .ASCIIZ "1. 6502 BBS  (BBS)"
STR_MI_2:
        .ASCIIZ "2. Ping LAN (PING)"
STR_MI_3:
        .ASCIIZ "3. Status (STATUS)"
STR_MI_4:
        .ASCIIZ "4. Pinout  (W5500)"
STR_MI_5:
        .ASCIIZ "5. Thema     (TAB)"
STR_MI_6:
        .ASCIIZ "0. Stoppen   (ESC)"

STR_KW_HELP:    .ASCIIZ "HELP"
STR_KW_PING:    .ASCIIZ "PING"
STR_KW_BBS:     .ASCIIZ "BBS"
STR_KW_STAT:    .ASCIIZ "STATUS"
STR_KW_W5500:   .ASCIIZ "W5500"
STR_KW_CLS:     .ASCIIZ "CLS"
STR_KW_COLOR:   .ASCIIZ "COLOR"
STR_KW_MODE:    .ASCIIZ "MODE"
STR_KW_EXIT:    .ASCIIZ "EXIT"

STR_TX_PFX:     .ASCIIZ "6502> "
STR_TN_CONN:    .ASCIIZ "[TELNET] Client verbonden op poort 23!"
STR_TN_BANNER:  .ASCIIZ "=== DONDERDAG 6502 TELNET (192.168.178.200:23) ==="

BLK_WELCOME:
        .BYTE $FC
        .ASCIIZ "=== MINIGPU NETTERM 1.2 - W5500 TELNET SERVER (POORT 23) ==="
        .BYTE $1F
        .ASCIIZ "W5500 luistert op 192.168.178.200 poort 23 (TCP Telnet)!"
        .BYTE $00
        .ASCIIZ "Verbind vanaf PC: telnet 192.168.178.200 23 om te chatten!"
        .BYTE $FE

BLK_HELP:
        .BYTE $FC
        .ASCIIZ "--- NETTERM COMMANDO'S & TELNET ---"
        .BYTE $00
        .ASCIIZ " PING: Ping .87 | STATUS: W5500 | BBS: Retro BBS"
        .BYTE $00
        .ASCIIZ " W5500: Pinout  | CLS: Wis      | EXIT: Naar BASIC"
        .BYTE $FE

STR_PNG_HDR:
        .ASCIIZ "PING 192.168.178.87 (Powerbaas): 64B via W5500 LAN"
STR_PNG_REP:
        .ASCIIZ "64 bytes van 192.168.178.87:    icmp_seq=1 ttl=64 0.6ms"
STR_PNG_SUM:
        .ASCIIZ "--- 4 verzonden, 4 ontvangen, 0% verlies (OK!) ---"

BLK_BBS:
        .BYTE $FC
        .ASCIIZ "=== WELKOM OP HET DONDERDAG 6502 RETRO BBS ==="
        .BYTE $FF
        .ASCIIZ "[SYSOP] Welkom! Typ een bericht om te chatten."
        .BYTE $FE

BLK_STATUS:
        .BYTE $FC
        .ASCIIZ "--- W5500 TCP TELNET SOCKET 0 STATUS ---"
        .BYTE $00
        .ASCIIZ "IP: 192.168.178.200  GW: 192.168.178.1  Poort: 23"
        .BYTE $1F
        .ASCIIZ "MAC: 02:65:02:20:00:01 | Socket 0: TCP Telnet Actief"
        .BYTE $FE

BLK_PINOUT:
        .BYTE $FC
        .ASCIIZ "W5500: CS=27 SCLK=28 MOSI=25 MISO=26 RST=29"
        .BYTE $FE

BLK_CHAT:
        .BYTE $1F
        .ASCIIZ "[TX -> TELNET] Verzonden naar client op poort 23!"
        .BYTE $FE

STR_LOG_MODE:
        .ASCIIZ "Modus gewisseld."
