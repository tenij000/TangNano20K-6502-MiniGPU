; ============================================================================
; BROWSER.asm - MiniGPU WebNavigator 1.0 (6502 HTTP/1.0 Browser & Powerbaas UI)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes).
; Verbindt via de W5500 (Poort $A030/$A031) als echte TCP HTTP/1.0 Client met
; http://192.168.178.87/json (Powerbaas Energy Manager op poort 80), parseert
; live de JSON-velden (Verbruik/Zon-overschot, Weer, Zonuren, Slimme Meter,
; Gas, 3-Fase Spanning/Stroom/Vermogen) en stuurt de 3 KAKU-schakelaars aan!
; Bevat tevens een 'view-source:' HTTP/JSON-broncode-tabblad (TAB-toets).
; Starten vanuit BASIC met: BRUN BROWSER
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
SPI_BRAM_STUB   = $02F0         ; 7-byte SPI helper in interne BRAM ($02F0)

; --- Zero Page Variabelen ($60..$88) ---
ZP_PTR_LO       = $60           ; Algemene 16-bit pointer voor strings/streams
ZP_PTR_HI       = $61
ZP_KEY_LO       = $62           ; Pointer naar gezochte JSON-sleutel
ZP_KEY_HI       = $63
ZP_X_LO         = $64           ; 16-bit GPU X
ZP_X_HI         = $65
ZP_Y_LO         = $66           ; 16-bit GPU Y
ZP_Y_HI         = $67
ZP_COLOR        = $68           ; Huidige tekstkleur

ZP_SCAN_LO      = $69           ; 16-bit pointer in HTTP_BUF ($6800..$69FF)
ZP_SCAN_HI      = $6A
S0_PTR_LO       = $6B           ; W5500 Socket 0 TX/RX pointer Lo
S0_PTR_HI       = $6C           ; W5500 Socket 0 TX/RX pointer Hi
S0_LEN_LO       = $6D           ; Ontvangen HTTP lengte Lo
S0_LEN_HI       = $6E           ; Ontvangen HTTP lengte Hi

W5500_VER       = $70           ; W5500 VERSIONR ($04 = aanwezig)
W5500_PHY       = $71           ; W5500 PHYCFGR (Bit 0 = Link UP)
HTTP_STATUS     = $72           ; 0=Wacht, 1=200 OK, 2=Offline/Simulatie
VIEW_MODE       = $73           ; 0=Grafische Webpagina, 1=HTTP/JSON Broncode
AUTO_TIMER      = $74           ; Teller voor automatische verversing (~3 sec)
LOCAL_PORT_LO   = $75           ; Ephemeral TCP bronpoort Lo ($C000 + teller)
REQ_CNT_LO      = $76           ; Aantal uitgevoerde HTTP-requests Lo
REQ_CNT_HI      = $77           ; Aantal uitgevoerde HTTP-requests Hi
SURPLUS_FLAG    = $78           ; 1 als powerUsage negatief is (Zon-overschot!)
USAGE_BAR_W     = $79           ; Breedte van de grafische Watt-balk (0..200)
SW1_STATE       = $7A           ; Status KAKU schakelaar 1 (0=UIT, 1=AAN)
SW2_STATE       = $7B           ; Status KAKU schakelaar 2 (0=UIT, 1=AAN)
SW3_STATE       = $7C           ; Status KAKU schakelaar 3 (0=UIT, 1=AAN)
CUR_ROW         = $7D           ; Rij-teller voor broncode-weergave
CHAR_COL        = $7E           ; Kolom-teller voor broncode-weergave

; --- Geheugenbuffers in SDRAM ($6800..$6BFF) ---
HTTP_BUF        = $6800         ; 512 bytes HTTP/JSON ontvangstbuffer ($6800..$69FF)

; ============================================================================
; Start & Initialisatie
; ============================================================================
START:
        JSR ROM_SILENCE
        LDA #0
        STA IO_MODE             ; MODE 1 (volledige 640x360 GUI)
        STA ZP_Y_HI
        STA VIEW_MODE
        STA AUTO_TIMER
        STA REQ_CNT_LO
        STA REQ_CNT_HI
        STA SW1_STATE
        STA SW2_STATE
        STA SW3_STATE

        ; Gebruik hardware LFSR ($A005) als startpunt voor ephemeral TCP poort
        LDA $A005
        ORA #$01
        STA LOCAL_PORT_LO

        ; Kopieer standaard fallback-JSON naar HTTP_BUF voor het geval .87 offline is
        JSR LOAD_FALLBACK_JSON

        ; Initialiseer W5500 en haal direct live /json op van 192.168.178.87!
        JSR W5500_INIT_HW
        LDA #<STR_REQ_JSON
        LDY #>STR_REQ_JSON
        JSR HTTP_GET_REQUEST

MAIN_LOOP:
        JSR DRAW_BROWSER

WAIT_LOOP:
        JSR DELAY_10MS

        ; Automatische live verversing elke ~2.5 seconden (250 * 10ms)
        INC AUTO_TIMER
        LDA AUTO_TIMER
        CMP #200
        BCC WL_CHK_ESC
        LDA #0
        STA AUTO_TIMER
        LDA #<STR_REQ_JSON
        LDY #>STR_REQ_JSON
        JSR HTTP_GET_REQUEST
        JMP MAIN_LOOP

WL_CHK_ESC:
        LDA IO_STATUS
        BPL CHK_KEY
        LDA IO_TERM             ; Lees ESC weg
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

CHK_KEY:
        LDA IO_STATUS
        AND #1
        BEQ WAIT_LOOP
        LDA IO_TERM

        CMP #'q'
        BEQ EXIT_TO_BASIC
        CMP #'Q'
        BEQ EXIT_TO_BASIC

        CMP #$09                ; TAB -> Wissel Dashboard <-> HTTP Broncode
        BEQ DO_TOGGLE_VIEW
        CMP #'v'
        BEQ DO_TOGGLE_VIEW
        CMP #'V'
        BEQ DO_TOGGLE_VIEW

        CMP #'r'                ; R of SPATIE -> Nu verversen!
        BEQ DO_REFRESH
        CMP #'R'
        BEQ DO_REFRESH
        CMP #' '
        BEQ DO_REFRESH

        CMP #'1'                ; Toets 1 -> KAKU Schakelaar 1 (ventilator)
        BEQ DO_SW1
        CMP #'2'                ; Toets 2 -> KAKU Schakelaar 2 (stroom te veel)
        BEQ DO_SW2
        CMP #'3'                ; Toets 3 -> KAKU Schakelaar 3 (stroom te VEEL)
        BEQ DO_SW3
        JMP WAIT_LOOP

DO_TOGGLE_VIEW:
        LDA VIEW_MODE
        EOR #1
        STA VIEW_MODE
        JMP MAIN_LOOP

DO_REFRESH:
        LDA #0
        STA AUTO_TIMER
        LDA #<STR_REQ_JSON
        LDY #>STR_REQ_JSON
        JSR HTTP_GET_REQUEST
        JMP MAIN_LOOP

DO_SW1:
        LDA SW1_STATE
        EOR #1
        STA SW1_STATE
        BEQ DSW1_OFF
        LDA #<STR_REQ_SW1_ON
        LDY #>STR_REQ_SW1_ON
        JMP DSW_SEND
DSW1_OFF:
        LDA #<STR_REQ_SW1_OFF
        LDY #>STR_REQ_SW1_OFF
        JMP DSW_SEND

DO_SW2:
        LDA SW2_STATE
        EOR #1
        STA SW2_STATE
        BEQ DSW2_OFF
        LDA #<STR_REQ_SW2_ON
        LDY #>STR_REQ_SW2_ON
        JMP DSW_SEND
DSW2_OFF:
        LDA #<STR_REQ_SW2_OFF
        LDY #>STR_REQ_SW2_OFF
        JMP DSW_SEND

DO_SW3:
        LDA SW3_STATE
        EOR #1
        STA SW3_STATE
        BEQ DSW3_OFF
        LDA #<STR_REQ_SW3_ON
        LDY #>STR_REQ_SW3_ON
        JMP DSW_SEND
DSW3_OFF:
        LDA #<STR_REQ_SW3_OFF
        LDY #>STR_REQ_SW3_OFF

DSW_SEND:
        JSR HTTP_GET_REQUEST
        ; Haal direct daarna weer actuele /json op!
        LDA #<STR_REQ_JSON
        LDY #>STR_REQ_JSON
        JSR HTTP_GET_REQUEST
        JMP MAIN_LOOP

; ============================================================================
; W5500 Hardware SPI & TCP HTTP/1.0 Client (Socket 1: $28/$2C/$34/$38)
; Gebruikt Socket 1 zodat Socket 0 (Telnet poort 23) vrij blijft!
; ============================================================================
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
        LDA #$39                ; VERSIONR ($0039) -> $04
        JSR W5500_RD_CREG
        STA W5500_VER
        LDA #$2E                ; PHYCFGR ($002E) -> Bit 0 = Link
        JSR W5500_RD_CREG
        STA W5500_PHY
        RTS

W5500_RD_S1:
        LDY #$28                ; Control = $28 (Socket 1 Reg Read, BSB=00101)
        BNE W5500_RD_Y
W5500_RD_CREG:
        LDY #$00                ; Control = $00 (Common Reg Read)
W5500_RD_Y:
        PHA
        LDA #$02
        STA IO_NET_CTRL
        LDA #$00
        JSR SPI_BRAM_STUB
        PLA
        JSR SPI_BRAM_STUB
        TYA
        JSR SPI_BRAM_STUB
        LDA #$00
        JSR SPI_BRAM_STUB
        PHA
        LDA #$03
        STA IO_NET_CTRL
        PLA
        RTS

W5500_WR_S1:
        PHA
        LDA #$02
        STA IO_NET_CTRL
        LDA #$00
        JSR SPI_BRAM_STUB
        TXA
        JSR SPI_BRAM_STUB
        LDA #$2C                ; Control = $2C (Socket 1 Reg Write, BSB=00101)
        JSR SPI_BRAM_STUB
        PLA
        JSR SPI_BRAM_STUB
        LDA #$03
        STA IO_NET_CTRL
        RTS

SPI_AND_INC_PTR:
        JSR SPI_BRAM_STUB
        INC S0_PTR_LO
        BNE SAIP_RTS
        INC S0_PTR_HI
SAIP_RTS:
        RTS

; --- Voer een echte TCP HTTP/1.0 GET-request uit naar 192.168.178.87:80 ---
; Invoer: A/Y = pointer naar pad-string (bijv. "/json" of "/handle/switch/...")
HTTP_GET_REQUEST:
        STA ZP_PTR_LO
        STY ZP_PTR_HI

        JSR W5500_PROBE_HW
        LDA W5500_VER
        CMP #$04
        BEQ HGR_HAS_CHIP
HGR_FAIL_OFFLINE:
        LDA #2                  ; 2 = Offline / Simulatie-data actief
        STA HTTP_STATUS
        JMP PARSE_POWER_BAR

HGR_HAS_CHIP:
        LDA W5500_PHY
        AND #$01
        BEQ HGR_FAIL_OFFLINE

        ; 1. Sluit Socket 1 eerst voor schone start (Sn_CR = $10 CLOSE) en wis Sn_IR
        LDX #$01
        LDA #$10
        JSR W5500_WR_S1
        LDX #$02
        LDA #$FF
        JSR W5500_WR_S1

        ; 2. Kies een nieuw lokaal poortnummer ($C000 + ++LOCAL_PORT_LO)
        INC LOCAL_PORT_LO
        BNE HGR_PORT_OK
        INC LOCAL_PORT_LO
HGR_PORT_OK:
        LDX #$00                ; Sn_MR = $21 (TCP + No Delayed ACK)
        LDA #$21
        JSR W5500_WR_S1
        LDX #$04                ; Sn_PORT0 = $C0
        LDA #$C0
        JSR W5500_WR_S1
        LDX #$05                ; Sn_PORT1 = LOCAL_PORT_LO
        LDA LOCAL_PORT_LO
        JSR W5500_WR_S1

        ; 3. Stel doel-IP (192.168.178.87) en doelpoort (80) in op Socket 1
        LDX #$0C                ; Sn_DIPR0 = 192
        LDA #192
        JSR W5500_WR_S1
        LDX #$0D                ; Sn_DIPR1 = 168
        LDA #168
        JSR W5500_WR_S1
        LDX #$0E                ; Sn_DIPR2 = 178
        LDA #178
        JSR W5500_WR_S1
        LDX #$0F                ; Sn_DIPR3 = 87 (Powerbaas!)
        LDA #87
        JSR W5500_WR_S1
        LDX #$10                ; Sn_DPORT0 = 0
        LDA #0
        JSR W5500_WR_S1
        LDX #$11                ; Sn_DPORT1 = 80 (HTTP poort 80)
        LDA #80
        JSR W5500_WR_S1

        ; 4. Open Socket 1 (Sn_CR = $01 OPEN) en wacht op SOCK_INIT ($13)
        LDX #$01
        LDA #$01
        JSR W5500_WR_S1
        LDY #10
HGR_WAIT_INIT:
        LDA #$03
        JSR W5500_RD_S1
        CMP #$13
        BEQ HGR_DO_CONN
        DEY
        BNE HGR_WAIT_INIT
        BEQ HGR_FAIL_OFFLINE

        ; 5. Verbind met Powerbaas (Sn_CR = $04 CONNECT)
HGR_DO_CONN:
        LDX #$01
        LDA #$04
        JSR W5500_WR_S1

        ; Wacht max ~400 ms (40 * 10ms) op SOCK_ESTABLISHED ($17) of CLOSE_WAIT ($1C)
        LDA #40
        STA S0_LEN_LO
HGR_WAIT_EST:
        LDA #$03
        JSR W5500_RD_S1
        CMP #$17
        BEQ HGR_CONNECTED
        CMP #$1C
        BEQ HGR_CONNECTED
        CMP #$00                ; SOCK_CLOSED (Refused/Timeout)?
        BEQ HGR_FAIL_OFFLINE
        JSR DELAY_10MS
        DEC S0_LEN_LO
        BNE HGR_WAIT_EST
        BEQ HGR_FAIL_OFFLINE

        ; 6. Verstuur "GET <pad> HTTP/1.0\r\nHost: 192.168.178.87\r\n\r\n"
HGR_CONNECTED:
        LDA #$24                ; Sn_TX_WR0 (Hi)
        JSR W5500_RD_S1
        STA S0_PTR_HI
        LDA #$25                ; Sn_TX_WR1 (Lo)
        JSR W5500_RD_S1
        STA S0_PTR_LO

        LDA #$02                ; CS = 0
        STA IO_NET_CTRL
        LDA S0_PTR_HI
        JSR SPI_BRAM_STUB
        LDA S0_PTR_LO
        JSR SPI_BRAM_STUB
        LDA #$34                ; Control = $34 (Socket 1 TX Buffer Write, BSB=00110)
        JSR SPI_BRAM_STUB

        ; Schrijf "GET "
        LDY #0
HGR_TX_GET:
        LDA STR_HTTP_GET,Y
        BEQ HGR_TX_PATH
        JSR SPI_AND_INC_PTR
        INY
        BNE HGR_TX_GET

        ; Schrijf het pad (bijv. "/json")
HGR_TX_PATH:
        LDY #0
HGR_TX_PLP:
        LDA (ZP_PTR_LO),Y
        BEQ HGR_TX_TAIL
        JSR SPI_AND_INC_PTR
        INY
        BNE HGR_TX_PLP

        ; Schrijf " HTTP/1.0\r\nHost: 192.168.178.87\r\n\r\n"
HGR_TX_TAIL:
        LDY #0
HGR_TX_TLP:
        LDA STR_HTTP_TAIL,Y
        BEQ HGR_TX_DONE
        JSR SPI_AND_INC_PTR
        INY
        BNE HGR_TX_TLP

HGR_TX_DONE:
        LDA #$03                ; CS = 1
        STA IO_NET_CTRL

        LDX #$24                ; Update Sn_TX_WR0
        LDA S0_PTR_HI
        JSR W5500_WR_S1
        LDX #$25                ; Update Sn_TX_WR1
        LDA S0_PTR_LO
        JSR W5500_WR_S1
        LDX #$01                ; Sn_CR = SEND ($20)
        LDA #$20
        JSR W5500_WR_S1

        ; 7. Wacht tot Powerbaas antwoordt en verbinding sluit ($1C CLOSE_WAIT of >=512B)
        LDA #80
        STA S0_LEN_LO
HGR_WAIT_RX:
        JSR DELAY_10MS
        LDA #$03                ; Sn_SR
        JSR W5500_RD_S1
        CMP #$1C                ; SOCK_CLOSE_WAIT (volledig antwoord is binnen!)
        BEQ HGR_READ_RX
        CMP #$00                ; Of al gesloten na antwoord
        BEQ HGR_READ_RX
        LDA #$26                ; Sn_RX_RSR0 (Hi)
        JSR W5500_RD_S1
        CMP #2                  ; >= 512 bytes?
        BCS HGR_READ_RX
        DEC S0_LEN_LO
        BNE HGR_WAIT_RX

HGR_READ_RX:
        LDA #$26                ; Sn_RX_RSR0 (Hi)
        JSR W5500_RD_S1
        STA S0_LEN_HI
        LDA #$27                ; Sn_RX_RSR1 (Lo)
        JSR W5500_RD_S1
        STA S0_LEN_LO
        ORA S0_LEN_HI
        BNE HGR_HAS_BYTES
        JMP HGR_CLOSE_SOCK

HGR_HAS_BYTES:
        ; Controleer of dit een "/json" request was (begint ZP_PTR_LO+1 met 'j'?)
        LDY #1
        LDA (ZP_PTR_LO),Y
        CMP #'j'
        BNE HGR_OK_DONE         ; Bij "/handle/switch/..." hoeven we HTTP_BUF niet te overschrijven!

        ; Lees Sn_RX_RD0 ($28) en Sn_RX_RD1 ($29)
        LDA #$28
        JSR W5500_RD_S1
        STA S0_PTR_HI
        LDA #$29
        JSR W5500_RD_S1
        STA S0_PTR_LO

        ; Lees 512 bytes uit Socket 1 RX Buffer (Control = $38, BSB=00111) naar HTTP_BUF ($6800..$69FF)
        LDA #$02                ; CS = 0
        STA IO_NET_CTRL
        LDA S0_PTR_HI
        JSR SPI_BRAM_STUB
        LDA S0_PTR_LO
        JSR SPI_BRAM_STUB
        LDA #$38                ; Control = $38 (Socket 1 RX Buffer Read)
        JSR SPI_BRAM_STUB

        LDY #0
HGR_RD_P0:
        LDA #$00
        JSR SPI_BRAM_STUB
        STA HTTP_BUF,Y
        INY
        BNE HGR_RD_P0

        LDY #0
HGR_RD_P1:
        LDA #$00
        JSR SPI_BRAM_STUB
        STA HTTP_BUF+$100,Y
        INY
        BNE HGR_RD_P1

        LDA #$03                ; CS = 1
        STA IO_NET_CTRL

        ; Zet 0-terminator aan het einde van het ontvangen pakket (indien < 512 bytes)
        LDA S0_LEN_HI
        CMP #2
        BCS HGR_FORCE_TERM
        CLC
        ADC #>HTTP_BUF
        STA ZP_SCAN_HI
        LDA S0_LEN_LO
        STA ZP_SCAN_LO
        LDY #0
        TYA
        STA (ZP_SCAN_LO),Y
HGR_FORCE_TERM:
        LDA #0
        STA HTTP_BUF+$1FF

HGR_OK_DONE:
        INC REQ_CNT_LO
        BNE HGR_CNT_OK
        INC REQ_CNT_HI
HGR_CNT_OK:
        LDA #1                  ; 1 = Live 200 OK!
        STA HTTP_STATUS

HGR_CLOSE_SOCK:
        LDX #$01                ; Sn_CR = CLOSE ($10)
        LDA #$10
        JSR W5500_WR_S1
        JMP PARSE_POWER_BAR

W5500_STUB_BYTES:
        STA IO_NET_DATA
        LDA IO_NET_DATA
        RTS

W5500_INIT_TBL:
        .BYTE $00, $00, $04                     ; Offset $0000, Write Common Regs VDM
        .BYTE $00                               ; MR: Ping Block UIT
        .BYTE 192, 168, 178, 1                  ; GAR: Gateway 192.168.178.1
        .BYTE 255, 255, 255, 192                ; SUBR: .192 zodat .87 (Wi-Fi) via Gateway .1 loopt!
        .BYTE $02, $65, $02, $20, $00, $01      ; SHAR: MAC 02:65:02:20:00:01
        .BYTE 192, 168, 178, 200                ; SIPR: Eigen IP 192.168.178.200

; ============================================================================
; JSON-Parser & Vermogensbalk-berekening uit HTTP_BUF ($6800..$69FF)
; ============================================================================
LOAD_FALLBACK_JSON:
        LDX #0
LFJ_LP:
        LDA FALLBACK_JSON_PART1,X
        STA HTTP_BUF,X
        LDA FALLBACK_JSON_PART1+160,X
        STA HTTP_BUF+160,X
        INX
        CPX #160
        BCC LFJ_LP
        RTS

; Bereken SURPLUS_FLAG (0=Netverbruik, 1=Zon-overschot) en USAGE_BAR_W (8..220 px)
PARSE_POWER_BAR:
        LDA #0
        STA SURPLUS_FLAG
        LDA #24
        STA USAGE_BAR_W

        LDA #<KEY_USAGE
        LDY #>KEY_USAGE
        JSR FIND_JSON_KEY
        BCC PPB_RTS

        LDY #0
PPB_SKIP_SEP:
        LDA (ZP_SCAN_LO),Y
        CMP #'"'
        BEQ PPB_S1
        CMP #':'
        BEQ PPB_S1
        CMP #' '
        BNE PPB_CHK_NEG
PPB_S1:
        INY
        BNE PPB_SKIP_SEP
PPB_CHK_NEG:
        CMP #'-'
        BNE PPB_POS
        LDA #1
        STA SURPLUS_FLAG
        INY
PPB_POS:
        ; Parseer decimaal getal in S0_PTR_LO/HI om balkbreedte te schalen
        LDA #0
        STA S0_PTR_LO
        STA S0_PTR_HI
PPB_DIG:
        LDA (ZP_SCAN_LO),Y
        CMP #'0'
        BCC PPB_SCALE
        CMP #':'
        BCS PPB_SCALE
        SEC
        SBC #'0'
        PHA
        ; S0_PTR = S0_PTR * 10 + A
        ASL S0_PTR_LO
        ROL S0_PTR_HI
        LDA S0_PTR_LO
        STA ZP_KEY_LO
        LDA S0_PTR_HI
        STA ZP_KEY_HI
        ASL S0_PTR_LO
        ROL S0_PTR_HI
        ASL S0_PTR_LO
        ROL S0_PTR_HI
        CLC
        LDA S0_PTR_LO
        ADC ZP_KEY_LO
        STA S0_PTR_LO
        LDA S0_PTR_HI
        ADC ZP_KEY_HI
        STA S0_PTR_HI
        PLA
        CLC
        ADC S0_PTR_LO
        STA S0_PTR_LO
        BCC PPB_NXT
        INC S0_PTR_HI
PPB_NXT:
        INY
        BNE PPB_DIG

PPB_SCALE:
        ; Deel S0_PTR door 8 voor pixelbreedte (bijv. 300W -> 37px, 1600W -> 200px)
        LSR S0_PTR_HI
        ROR S0_PTR_LO
        LSR S0_PTR_HI
        ROR S0_PTR_LO
        LSR S0_PTR_HI
        ROR S0_PTR_LO
        LDA S0_PTR_HI
        BNE PPB_MAX
        LDA S0_PTR_LO
        CMP #220
        BCC PPB_MIN
PPB_MAX:
        LDA #220
PPB_MIN:
        CMP #8
        BCS PPB_SET
        LDA #8
PPB_SET:
        STA USAGE_BAR_W
PPB_RTS:
        RTS

; --- Zoek JSON-sleutel op (A=lo, Y=hi) in HTTP_BUF ($6800..$69FF) ---
; Bij succes: Carry=1 en ZP_SCAN_LO/HI wijst direct naar de waarde na de sleutel!
FIND_JSON_KEY:
        STA ZP_KEY_LO
        STY ZP_KEY_HI
        LDA #<HTTP_BUF
        STA ZP_SCAN_LO
        LDA #>HTTP_BUF
        STA ZP_SCAN_HI

FJK_OUTER:
        LDY #0
        LDA (ZP_SCAN_LO),Y
        BEQ FJK_NOT_FOUND
FJK_INNER:
        LDA (ZP_KEY_LO),Y
        BEQ FJK_FOUND           ; Hele sleutel gematcht!
        CMP (ZP_SCAN_LO),Y
        BNE FJK_ADV
        INY
        BNE FJK_INNER

FJK_ADV:
        INC ZP_SCAN_LO
        BNE FJK_OUTER
        INC ZP_SCAN_HI
        LDA ZP_SCAN_HI
        CMP #>(HTTP_BUF + $0200)
        BCC FJK_OUTER
FJK_NOT_FOUND:
        CLC
        RTS

FJK_FOUND:
        TYA
        CLC
        ADC ZP_SCAN_LO
        STA ZP_SCAN_LO
        BCC FJK_FOUND_OK
        INC ZP_SCAN_HI
FJK_FOUND_OK:
        SEC
        RTS

; --- Zoek JSON-sleutel op (A=lo, Y=hi) en teken de waarde direct op scherm ---
DRAW_JSON_VAL:
        JSR FIND_JSON_KEY
        BCC DJV_DASH
        LDY #0
        ; Sla ", :, niet-ASCII (UTF-8 emoji bytes >= $80) en leidende spaties over
DJV_SKIP_LEAD:
        LDA (ZP_SCAN_LO),Y
        BEQ DJV_RTS
        CMP #'"'
        BEQ DJV_SKIP_1
        CMP #':'
        BEQ DJV_SKIP_1
        CMP #' '
        BEQ DJV_SKIP_1
        CMP #$7F
        BCC DJV_LOOP
DJV_SKIP_1:
        INY
        CPY #32
        BCC DJV_SKIP_LEAD

DJV_LOOP:
        LDA (ZP_SCAN_LO),Y
        BEQ DJV_RTS
        CMP #'"'
        BEQ DJV_RTS
        CMP #','
        BEQ DJV_RTS
        CMP #'}'
        BEQ DJV_RTS
        CMP #$20
        BCC DJV_NEXT
        CMP #$7F
        BCS DJV_NEXT
        STY CUR_ROW
        JSR DRAW_CHAR_ADV
        LDY CUR_ROW
DJV_NEXT:
        INY
        CPY #28
        BCC DJV_LOOP
DJV_RTS:
        RTS

DJV_DASH:
        LDA #'-'
        JMP DRAW_CHAR_ADV

; ============================================================================
; Grafische Browser Weergave (640x360)
; ============================================================================
SET_POS_X16:
        STA ZP_Y_LO
        STX ZP_COLOR
        LDA #16
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        RTS

SET_POS_X332:
        STA ZP_Y_LO
        STX ZP_COLOR
        LDA #$4C                ; X = 332 ($014C)
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        LDA #0
        STA ZP_Y_HI
        RTS

DRAW_BROWSER:
        LDA VIEW_MODE
        BEQ DB_CARDS
        JMP DRAW_SOURCE_VIEW

DB_CARDS:
        LDX #0
DB_UI_LP:
        LDA UI_STREAM,X
        STA IO_GPU
        INX
        CPX #UI_STREAM_END - UI_STREAM
        BCC DB_UI_LP

        ; Teken de 3 KAKU-kaarten onderaan via tweede stream (<255 bytes!)
        LDX #0
DB_KAKU_LP:
        LDA KAKU_STREAM,X
        STA IO_GPU
        INX
        CPX #KAKU_STREAM_END - KAKU_STREAM
        BCC DB_KAKU_LP

        ; 1. Titelbalk & URL-adresbalk
        LDA #4
        LDX #$FC
        JSR SET_POS_X16
        LDA #<STR_TITLE
        LDY #>STR_TITLE
        JSR DRAW_STR_AY

        LDA #24
        LDX #$FF
        JSR SET_POS_X16
        LDA #<STR_URL_BAR
        LDY #>STR_URL_BAR
        JSR DRAW_STR_AY

        ; Status-indicator rechts in de URL-balk
        LDA #$E0                ; Rood = Offline
        LDX #<STR_ST_SIM
        LDY #>STR_ST_SIM
        LDA HTTP_STATUS
        CMP #1
        BNE DB_URL_ST
        LDA #$1C                ; Groen = 200 OK Live
        LDX #<STR_ST_OK
        LDY #>STR_ST_OK
        JMP DB_URL_ST_GO
DB_URL_ST:
        LDA #$FC                ; Geel bij simulatie/cache
DB_URL_ST_GO:
        STA ZP_COLOR
        TXA
        JSR DRAW_STR_AY

        ; 2. Grote Hero-Card (Y = 43..105)
        ; Kies kaderkleur: Groen ($1C) bij Zon-overschot, Cyaan/Blauw ($1F) bij Netverbruik
        LDA #49
        LDX #$1F
        LDA SURPLUS_FLAG
        BEQ DB_HERO_SUB
        LDX #$1C
        LDA #49
        JSR SET_POS_X16
        LDA #<STR_HERO_SURP
        LDY #>STR_HERO_SURP
        JMP DB_HERO_SUB_PRT
DB_HERO_SUB:
        LDA #49
        LDX #$1F
        JSR SET_POS_X16
        LDA #<STR_HERO_USE
        LDY #>STR_HERO_USE
DB_HERO_SUB_PRT:
        JSR DRAW_STR_AY

        ; Actueel Vermogen in Watt
        LDA #65
        LDX #$FF
        JSR SET_POS_X16
        LDA #<STR_LBL_VERMOGEN
        LDY #>STR_LBL_VERMOGEN
        JSR DRAW_STR_AY
        LDA #$FC
        STA ZP_COLOR
        LDA #<KEY_USAGE
        LDY #>KEY_USAGE
        JSR DRAW_JSON_VAL
        LDA #<STR_UNIT_WATT
        LDY #>STR_UNIT_WATT
        JSR DRAW_STR_AY

        ; Teken Live Grafische Vermogensbalk op de Hero-Card (X=16, Y=83, B=USAGE_BAR_W, H=14)
        LDA #2                  ; GPU_FILL_RECT
        STA IO_GPU
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #83
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA USAGE_BAR_W
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #14
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$1C                ; Groen onder ~500W / Zon-overschot
        LDX SURPLUS_FLAG
        BNE DB_BAR_COL
        LDX USAGE_BAR_W
        CPX #65
        BCC DB_BAR_COL
        LDA #$FC                ; Geel boven ~500W
        CPX #140
        BCC DB_BAR_COL
        LDA #$E0                ; Rood boven ~1100W
DB_BAR_COL:
        STA IO_GPU

        ; 3. Linker Kaart Rij 1: Weer Vandaag (Y = 110..176)
        LDA #116
        LDX #$1F
        JSR SET_POS_X16
        LDA #<STR_HDR_WEER
        LDY #>STR_HDR_WEER
        JSR DRAW_STR_AY

        LDA #134
        LDX #$FF
        JSR SET_POS_X16
        LDA #<KEY_DESC
        LDY #>KEY_DESC
        JSR DRAW_JSON_VAL

        LDA #152
        LDX #$FC
        JSR SET_POS_X16
        LDA #<STR_LBL_TEMP
        LDY #>STR_LBL_TEMP
        JSR DRAW_STR_AY
        LDA #<KEY_TEMP
        LDY #>KEY_TEMP
        JSR DRAW_JSON_VAL
        LDA #<STR_LBL_MAXT
        LDY #>STR_LBL_MAXT
        JSR DRAW_STR_AY
        LDA #<KEY_MAXT
        LDY #>KEY_MAXT
        JSR DRAW_JSON_VAL
        LDA #'C'
        JSR DRAW_CHAR_ADV

        ; 4. Rechter Kaart Rij 1: Zonuren & Verwachting (Y = 110..176)
        LDA #116
        LDX #$1F
        JSR SET_POS_X332
        LDA #<STR_HDR_ZON
        LDY #>STR_HDR_ZON
        JSR DRAW_STR_AY

        LDA #134
        LDX #$FC
        JSR SET_POS_X332
        LDA #<KEY_SUN
        LDY #>KEY_SUN
        JSR DRAW_JSON_VAL
        LDA #<STR_UNIT_ZON
        LDY #>STR_UNIT_ZON
        JSR DRAW_STR_AY

        LDA #152
        LDX #$1C
        JSR SET_POS_X332
        LDA #<KEY_SOLAR
        LDY #>KEY_SOLAR
        JSR DRAW_JSON_VAL

        ; 5. Linker Kaart Rij 2: Meterstanden & Gas (Y = 181..268)
        LDA #187
        LDX #$1F
        JSR SET_POS_X16
        LDA #<STR_HDR_METER
        LDY #>STR_HDR_METER
        JSR DRAW_STR_AY

        LDA #203
        LDX #$FF
        JSR SET_POS_X16
        LDA #<STR_M_DAL
        LDY #>STR_M_DAL
        JSR DRAW_STR_AY
        LDA #<KEY_DLOW
        LDY #>KEY_DLOW
        JSR DRAW_JSON_VAL
        LDA #<STR_KWH
        LDY #>STR_KWH
        JSR DRAW_STR_AY

        LDA #218
        LDX #$FF
        JSR SET_POS_X16
        LDA #<STR_M_PIEK
        LDY #>STR_M_PIEK
        JSR DRAW_STR_AY
        LDA #<KEY_DHIGH
        LDY #>KEY_DHIGH
        JSR DRAW_JSON_VAL
        LDA #<STR_KWH
        LDY #>STR_KWH
        JSR DRAW_STR_AY

        LDA #233
        LDX #$1C
        JSR SET_POS_X16
        LDA #<STR_M_TERUG
        LDY #>STR_M_TERUG
        JSR DRAW_STR_AY
        LDA #<KEY_RLOW
        LDY #>KEY_RLOW
        JSR DRAW_JSON_VAL
        LDA #'/'
        JSR DRAW_CHAR_ADV
        LDA #<KEY_RHIGH
        LDY #>KEY_RHIGH
        JSR DRAW_JSON_VAL

        LDA #248
        LDX #$FC
        JSR SET_POS_X16
        LDA #<STR_M_GAS
        LDY #>STR_M_GAS
        JSR DRAW_STR_AY
        LDA #<KEY_GAS
        LDY #>KEY_GAS
        JSR DRAW_JSON_VAL
        LDA #<STR_M3
        LDY #>STR_M3
        JSR DRAW_STR_AY

        ; 6. Rechter Kaart Rij 2: 3-Fase Inzicht L1/L2/L3 (Y = 181..268)
        LDA #187
        LDX #$1F
        JSR SET_POS_X332
        LDA #<STR_HDR_FASE
        LDY #>STR_HDR_FASE
        JSR DRAW_STR_AY

        LDA #203
        LDX #$1C
        JSR SET_POS_X332
        LDA #<STR_F_L1
        LDY #>STR_F_L1
        JSR DRAW_STR_AY
        LDA #<KEY_VL1
        LDY #>KEY_VL1
        JSR DRAW_JSON_VAL
        LDA #<STR_F_V
        LDY #>STR_F_V
        JSR DRAW_STR_AY
        LDA #<KEY_CL1
        LDY #>KEY_CL1
        JSR DRAW_JSON_VAL
        LDA #<STR_F_A
        LDY #>STR_F_A
        JSR DRAW_STR_AY
        LDA #<KEY_PL1
        LDY #>KEY_PL1
        JSR DRAW_JSON_VAL
        LDA #'W'
        JSR DRAW_CHAR_ADV

        LDA #218
        LDX #$FF
        JSR SET_POS_X332
        LDA #<STR_F_L2
        LDY #>STR_F_L2
        JSR DRAW_STR_AY

        LDA #233
        LDX #$FF
        JSR SET_POS_X332
        LDA #<STR_F_L3
        LDY #>STR_F_L3
        JSR DRAW_STR_AY

        LDA #248
        LDX #$FC
        JSR SET_POS_X332
        LDA #<STR_F_REQ
        LDY #>STR_F_REQ
        JSR DRAW_STR_AY
        LDA REQ_CNT_HI
        JSR DRAW_HEX8
        LDA REQ_CNT_LO
        JSR DRAW_HEX8

        ; 7. De 3 Slimme KAKU Schakelaar-kaarten (Y = 273..337)
        ; Kaart 1: X = 16
        LDA #280
        LDX #$FC
        JSR SET_POS_X16
        LDA #<STR_SW1_TIT
        LDY #>STR_SW1_TIT
        JSR DRAW_STR_AY
        LDA #298
        LDX #$FF
        JSR SET_POS_X16
        LDX SW1_STATE
        JSR DRAW_SW_STATE
        LDA #316
        LDX #$1F
        JSR SET_POS_X16
        LDA #<STR_SW1_SUB
        LDY #>STR_SW1_SUB
        JSR DRAW_STR_AY

        ; Kaart 2: X = 226
        LDA #226
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #280
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_COLOR
        LDA #<STR_SW2_TIT
        LDY #>STR_SW2_TIT
        JSR DRAW_STR_AY
        LDA #226
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #298
        STA ZP_Y_LO
        LDX SW2_STATE
        JSR DRAW_SW_STATE
        LDA #226
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #316
        STA ZP_Y_LO
        LDA #$1F
        STA ZP_COLOR
        LDA #<STR_SW2_SUB
        LDY #>STR_SW2_SUB
        JSR DRAW_STR_AY

        ; Kaart 3: X = 436 ($01B4)
        LDA #$B4
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        LDA #280
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_COLOR
        LDA #<STR_SW3_TIT
        LDY #>STR_SW3_TIT
        JSR DRAW_STR_AY
        LDA #$B4
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        LDA #298
        STA ZP_Y_LO
        LDX SW3_STATE
        JSR DRAW_SW_STATE
        LDA #$B4
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        LDA #316
        STA ZP_Y_LO
        LDA #$1F
        STA ZP_COLOR
        LDA #<STR_SW3_SUB
        LDY #>STR_SW3_SUB
        JSR DRAW_STR_AY

        ; 8. Onderste Sneltoetsbalk op Y = 347 ($015B)
DRAW_BOT_BAR:
        LDA #10
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$5B
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_COLOR
        LDA #<STR_BOT_BAR
        LDY #>STR_BOT_BAR
        JMP DRAW_STR_AY

DRAW_SW_STATE:
        TXA
        BNE DSS_ON
        LDA #$E0
        STA ZP_COLOR
        LDA #<STR_SW_OFF
        LDY #>STR_SW_OFF
        JMP DRAW_STR_AY
DSS_ON:
        LDA #$1C
        STA ZP_COLOR
        LDA #<STR_SW_ON
        LDY #>STR_SW_ON
        JMP DRAW_STR_AY

; ============================================================================
; Tabblad 2: view-source:http://192.168.178.87/json (Rauwe HTTP & JSON View)
; ============================================================================
DRAW_SOURCE_VIEW:
        LDX #0
DSV_UI:
        LDA SRC_STREAM,X
        STA IO_GPU
        INX
        CPX #SRC_STREAM_END - SRC_STREAM
        BCC DSV_UI

        LDA #4
        LDX #$FC
        JSR SET_POS_X16
        LDA #<STR_TITLE
        LDY #>STR_TITLE
        JSR DRAW_STR_AY

        LDA #24
        LDX #$1F
        JSR SET_POS_X16
        LDA #<STR_SRC_URL
        LDY #>STR_SRC_URL
        JSR DRAW_STR_AY

        ; Teken de inhoud van HTTP_BUF ($6800..$69FF) netjes gewrapt op 74 kolommen!
        LDA #<HTTP_BUF
        STA ZP_SCAN_LO
        LDA #>HTTP_BUF
        STA ZP_SCAN_HI
        LDA #52
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        STA CHAR_COL
        LDA #16
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$1C
        STA ZP_COLOR

DSV_LP:
        LDY #0
        LDA (ZP_SCAN_LO),Y
        BEQ DSV_DONE
        CMP #$0D
        BEQ DSV_SKIP
        CMP #$0A
        BNE DSV_CHK_PRN
        ; Nieuwe regel bij \n
        LDA CHAR_COL
        BEQ DSV_SKIP
        JSR DSV_NEWLINE
        JMP DSV_NEXT
DSV_CHK_PRN:
        CMP #$20
        BCC DSV_SKIP
        CMP #$7F
        BCS DSV_SKIP
        JSR DRAW_CHAR_ADV
        INC CHAR_COL
        LDA CHAR_COL
        CMP #74
        BCC DSV_SKIP
        JSR DSV_NEWLINE
DSV_SKIP:
        LDA ZP_Y_HI
        BNE DSV_CHK_YHI
DSV_NEXT:
        INC ZP_SCAN_LO
        BNE DSV_LP
        INC ZP_SCAN_HI
        LDA ZP_SCAN_HI
        CMP #>(HTTP_BUF + $0200)
        BCC DSV_LP
DSV_DONE:
        JMP DRAW_BOT_BAR

DSV_CHK_YHI:
        LDA ZP_Y_LO
        CMP #$40                ; Stop bij Y = 320 ($0140)
        BCS DSV_DONE
        BCC DSV_NEXT

DSV_NEWLINE:
        LDA #0
        STA CHAR_COL
        LDA #16
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        CLC
        LDA ZP_Y_LO
        ADC #14
        STA ZP_Y_LO
        BCC DSVN_RTS
        INC ZP_Y_HI
DSVN_RTS:
        RTS

; ============================================================================
; Tekst, Hex & Timer Hulproutines
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
; MiniGPU UI Streams (Elke stream < 255 bytes!)
; ============================================================================
UI_STREAM:
        .BYTE 12, 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 0
        .BYTE 1, $01

        ; Top Titelbalk (0,0, 640x15, $03)
        .BYTE 2, 0,0, 0,0, $80,$02, 15,0, $03
        ; Browser URL-Adresbalk (8,18, 624x21, $02) + Cyaan rand
        .BYTE 2, 8,0, 18,0, $70,$02, 21,0, $02
        .BYTE 3, 8,0, 18,0, $78,$02, 18,0, $1F
        .BYTE 3, 8,0, 39,0, $78,$02, 39,0, $1F

        ; Grote Hero-Card (8,43, 624x62, $02) + Cyaan randen
        .BYTE 2, 8,0, 43,0, $70,$02, 62,0, $02
        .BYTE 3, 8,0, 43,0, $78,$02, 43,0, $1F
        .BYTE 3, 8,0, 105,0, $78,$02, 105,0, $1F
        ; Achtergrond van de Watt-meterbalk (16,83, 220x14, Zwart $00)
        .BYTE 2, 16,0, 83,0, 220,0, 14,0, $00

        ; Rij 1 Kaart Links: Weer (8,110, 306x64, $02) + Rand
        .BYTE 2, 8,0, 110,0, $32,$01, 64,0, $02
        .BYTE 3, 8,0, 110,0, $3A,$01, 110,0, $1F
        ; Rij 1 Kaart Rechts: Zonuren (324,110, 308x64, $02) + Rand
        .BYTE 2, $44,$01, 110,0, $34,$01, 64,0, $02
        .BYTE 3, $44,$01, 110,0, $78,$02, 110,0, $1F

        ; Rij 2 Kaart Links: Meterstanden (8,180, 306x86, $02) + Rand
        .BYTE 2, 8,0, 180,0, $32,$01, 86,0, $02
        .BYTE 3, 8,0, 180,0, $3A,$01, 180,0, $1F
        ; Rij 2 Kaart Rechts: 3-Fase Inzicht (324,180, 308x86, $02) + Rand
        .BYTE 2, $44,$01, 180,0, $34,$01, 86,0, $02
        .BYTE 3, $44,$01, 180,0, $78,$02, 180,0, $1F
UI_STREAM_END:

KAKU_STREAM:
        ; 3 KAKU Schakelaar-kaarten op Y=272..336 (hoogte 64)
        .BYTE 2, 8,0, $10,$01, 200,0, 64,0, $02
        .BYTE 3, 8,0, $10,$01, 208,0, $10,$01, $1C
        .BYTE 2, 218,0, $10,$01, 200,0, 64,0, $02
        .BYTE 3, 218,0, $10,$01, $A2,$01, $10,$01, $1C
        .BYTE 2, $AC,$01, $10,$01, 204,0, 64,0, $02
        .BYTE 3, $AC,$01, $10,$01, $78,$02, $10,$01, $1C
        ; Onderste Sneltoetsbalk op Y=342 ($0156), hoogte 18 (tot Y=360!)
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $03
KAKU_STREAM_END:

SRC_STREAM:
        .BYTE 12, 1
        .BYTE 1, $01
        .BYTE 2, 0,0, 0,0, $80,$02, 15,0, $03
        .BYTE 2, 8,0, 18,0, $70,$02, 21,0, $02
        .BYTE 2, 8,0, 44,0, $70,$02, $24,$01, $00
        .BYTE 3, 8,0, 44,0, $78,$02, 44,0, $1C
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $03
SRC_STREAM_END:

; ============================================================================
; HTTP Request-strings, JSON-sleutels & UI-teksten
; ============================================================================
STR_HTTP_GET:       .ASCIIZ "GET "
STR_HTTP_TAIL:      .ASCIIZ " HTTP/1.0", $0D, $0A, "Host: 192.168.178.87", $0D, $0A, $0D, $0A

STR_REQ_JSON:       .ASCIIZ "/json"
STR_REQ_SW1_ON:     .ASCIIZ "/handle/switch/on/8648104"
STR_REQ_SW1_OFF:    .ASCIIZ "/handle/switch/off/8648104"
STR_REQ_SW2_ON:     .ASCIIZ "/handle/switch/on/1221404"
STR_REQ_SW2_OFF:    .ASCIIZ "/handle/switch/off/1221404"
STR_REQ_SW3_ON:     .ASCIIZ "/handle/switch/on/1982333"
STR_REQ_SW3_OFF:    .ASCIIZ "/handle/switch/off/1982333"

; JSON-sleutels van Powerbaas (/json)
KEY_USAGE:          .ASCIIZ "powerUsage"
KEY_DLOW:           .ASCIIZ "powerDeliverLow"
KEY_DHIGH:          .ASCIIZ "powerDeliverHigh"
KEY_RLOW:           .ASCIIZ "powerReturnLow"
KEY_RHIGH:          .ASCIIZ "powerReturnHigh"
KEY_GAS:            .ASCIIZ "gas"
KEY_VL1:            .ASCIIZ "voltageL1"
KEY_CL1:            .ASCIIZ "currentL1"
KEY_PL1:            .ASCIIZ "powerL1"
KEY_TEMP:           .ASCIIZ "temp"
KEY_MAXT:           .ASCIIZ "maxTemp"
KEY_SUN:            .ASCIIZ "sunHours"
KEY_SOLAR:          .ASCIIZ "solarRating"
KEY_DESC:           .ASCIIZ "description"

STR_TITLE:
        .ASCIIZ "MiniGPU WebNavigator 1.0 - Powerbaas Energy Manager (6502 HTTP)"
STR_URL_BAR:
        .ASCIIZ "< > [R]  http://192.168.178.87/json       "
STR_SRC_URL:
        .ASCIIZ "view-source:http://192.168.178.87/json (HTTP/1.0 200 OK)"
STR_ST_OK:
        .ASCIIZ "[200 OK LIVE]"
STR_ST_SIM:
        .ASCIIZ "[CACHE/WACHT]"

STR_HERO_USE:
        .ASCIIZ "ACTUEEL NETVERBRUIK (ENERGIE UIT HET NET - P1 METER)"
STR_HERO_SURP:
        .ASCIIZ "ZON-OVERSCHOT! (ACTIEVE TERUGLEVERING AAN HET NET)"
STR_LBL_VERMOGEN:
        .ASCIIZ "VERMOGEN: "
STR_UNIT_WATT:
        .ASCIIZ " Watt"

STR_HDR_WEER:       .ASCIIZ "WEER VANDAAG"
STR_LBL_TEMP:       .ASCIIZ "Temp: "
STR_LBL_MAXT:       .ASCIIZ "C / Max: "
STR_HDR_ZON:        .ASCIIZ "ZONUREN & VERWACHTING"
STR_UNIT_ZON:       .ASCIIZ " uur zon"

STR_HDR_METER:      .ASCIIZ "METERSTANDEN & GAS (P1)"
STR_M_DAL:          .ASCIIZ "Dal  : "
STR_M_PIEK:         .ASCIIZ "Piek : "
STR_M_TERUG:        .ASCIIZ "Terug: "
STR_M_GAS:          .ASCIIZ "Gas  : "
STR_KWH:            .ASCIIZ " kWh"
STR_M3:             .ASCIIZ " m3"

STR_HDR_FASE:       .ASCIIZ "3-FASE INZICHT (L1/L2/L3)"
STR_F_L1:           .ASCIIZ "L1: "
STR_F_V:            .ASCIIZ "V "
STR_F_A:            .ASCIIZ "A "
STR_F_L2:           .ASCIIZ "L2: 0.0V  0.0A  0W"
STR_F_L3:           .ASCIIZ "L3: 0.0V  0.0A  0W"
STR_F_REQ:          .ASCIIZ "HTTP GET Requests: $"

STR_SW1_TIT:        .ASCIIZ "[1] ventilator"
STR_SW1_SUB:        .ASCIIZ "KAKU #8648104 (>0W)"
STR_SW2_TIT:        .ASCIIZ "[2] stroom te veel"
STR_SW2_SUB:        .ASCIIZ "KAKU #1221404 (>0W)"
STR_SW3_TIT:        .ASCIIZ "[3] stroom te VEEL"
STR_SW3_SUB:        .ASCIIZ "KAKU #1982333 (>396W)"
STR_SW_ON:          .ASCIIZ "Status: [AAN] (Toets=Uit)"
STR_SW_OFF:         .ASCIIZ "Status: [UIT] (Toets=Aan)"

STR_BOT_BAR:
        .ASCIIZ "R/SPATIE:Ververs  1/2/3:KAKU Schakelaar Aan/Uit  TAB:Broncode  ESC:Stop"

; Standaard fallback-JSON (als netwerk nog niet verbonden is)
FALLBACK_JSON_PART1:
        .BYTE "HTTP/1.0 200 OK", $0D, $0A, $0D, $0A, "{powerUsage:294,powerDeliverHigh:5167.39,powerDeliverLow:4078.44,powerReturnHigh:0.00,powerReturnLow:0.01,gas:0.00,voltageL1:236.0,currentL1:1.0,powerL1:288,"
FALLBACK_JSON_PART2:
        .ASCIIZ "weather:{temp:9.1,maxTemp:13.7,sunHours:8.3,solarRating:Uitstekend (Hoge opbrengst),description:Licht bewolkt}}"
