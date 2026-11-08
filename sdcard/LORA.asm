; ============================================================================
; LORA.asm - LilyGO T3 v1.6.1 (868 MHz SX1276 LoRa + OLED) Commander ($8000)
; Start vanuit MiniGPU-BASIC met: BRUN "LORA"  (of vanuit Midnight Commander)
;
; Hardware I/O-registers op de Tang Nano 20K (Pin 30 = TXD, Pin 31 = RXD):
;   $A040 (IO_LORA_STATUS) : Bit 7 = RX byte klaar, Bit 6 = TX FIFO ruimte,
;                            Bits 5..0 = Aantal bytes in 64-byte RX FIFO
;                            Schrijf $00 = Normale Hardware-modus (Pin 30/31)
;                            Schrijf $80 = 868 MHz Hardware Simulator-modus
;   $A041 (IO_LORA_DATA)   : Lees = Pop RX byte, Schrijf = Zend TX byte (115200bd)
;   $A042 (IO_LORA_RSSI)   : Laatst ontvangen 868 MHz -RSSI in dBm (bijv. 48 = -48dBm)
;   $A043 (IO_LORA_PKTS)   : Aantal ontvangen 868 MHz LoRa-pakketten (0..255)
; ============================================================================
        ORG $8000

IO_STATUS       = $A000
IO_TERM         = $A001
IO_DELAY        = $A002
IO_MODE         = $A006
IO_GPU          = $A020
IO_LORA_STATUS  = $A040
IO_LORA_DATA    = $A041
IO_LORA_RSSI    = $A042
IO_LORA_PKTS    = $A043

ZP_PTR          = $60
SIM_MODE        = $62

START:
        LDA #$01
        STA IO_MODE             ; MODE 0 (tekst + grafische achtergrond)
        LDA #$00
        STA SIM_MODE
        STA IO_LORA_STATUS      ; Wis LoRa RX FIFO + zet op Hardware Pin 30/31

        JSR DRAW_UI

MAIN_LOOP:
        ; 1. Controleer of er bytes van de LilyGO T3 v1.6.1 in de 64-byte RX FIFO zitten
CheckRx:
        LDA IO_LORA_STATUS
        BPL CheckKey            ; Bit 7 = 0 -> geen RX byte wachtend
        LDA IO_LORA_DATA
        CMP #$0D
        BEQ CheckRx
        JSR PUTCHAR
        CMP #$0A
        BNE CheckRx
        JSR PRINT_STATUS_LINE
        JMP CheckRx

CheckKey:
        LDA IO_STATUS
        AND #$01
        BEQ MAIN_LOOP
        LDA IO_TERM

        CMP #$1B                ; ESC -> Terug naar BASIC
        BEQ EXIT_APP
        CMP #'Q'
        BEQ EXIT_APP
        CMP #'q'
        BEQ EXIT_APP

        CMP #'1'
        BNE Not1
        LDA #<CMD_INFO
        LDY #>CMD_INFO
        JSR SEND_LORA_CMD
        JMP MAIN_LOOP
Not1:
        CMP #'2'
        BNE Not2
        LDA #<CMD_PING
        LDY #>CMD_PING
        JSR SEND_LORA_CMD
        JMP MAIN_LOOP
Not2:
        CMP #'3'
        BNE Not3
        LDA #<CMD_OLED
        LDY #>CMD_OLED
        JSR SEND_LORA_CMD
        JMP MAIN_LOOP
Not3:
        CMP #'4'
        BNE Not4
        LDA #<CMD_SCAN
        LDY #>CMD_SCAN
        JSR SEND_LORA_CMD
        JMP MAIN_LOOP
Not4:
        CMP #'5'
        BNE Not5
        LDA #<CMD_HELLO
        LDY #>CMD_HELLO
        JSR SEND_LORA_CMD
        JMP MAIN_LOOP
Not5:
        CMP #'L'
        BEQ ToggleSim
        CMP #'l'
        BEQ ToggleSim
        CMP #'C'
        BEQ ClearScreen
        CMP #'c'
        BEQ ClearScreen
        CMP #'T'
        BEQ TypeCustom
        CMP #'t'
        BEQ TypeCustom
        JMP MAIN_LOOP

ToggleSim:
        LDA SIM_MODE
        EOR #$80
        STA SIM_MODE
        STA IO_LORA_STATUS
        LDA #<MSG_MODE_PREFIX
        LDY #>MSG_MODE_PREFIX
        JSR PRINT_STR
        LDA SIM_MODE
        BNE SimOnMsg
        LDA #<MSG_MODE_HW
        LDY #>MSG_MODE_HW
        JSR PRINT_STR
        JMP MAIN_LOOP
SimOnMsg:
        LDA #<MSG_MODE_SIM
        LDY #>MSG_MODE_SIM
        JSR PRINT_STR
        JMP MAIN_LOOP

ClearScreen:
        JSR DRAW_UI
        JMP MAIN_LOOP

TypeCustom:
        LDA #<MSG_PROMPT
        LDY #>MSG_PROMPT
        JSR PRINT_STR
TypeLoop:
        LDA IO_STATUS
        AND #$01
        BEQ TypeLoop
        LDA IO_TERM
        CMP #$1B
        BEQ TypeDone
        CMP #$0D
        BEQ TypeEnter
        CMP #$0A
        BEQ TypeEnter
        JSR PUTCHAR
        STA IO_LORA_DATA
        JMP TypeLoop
TypeEnter:
        LDA #$0A
        JSR PUTCHAR
        STA IO_LORA_DATA
TypeDone:
        JMP MAIN_LOOP

EXIT_APP:
        LDA #<MSG_BYE
        LDY #>MSG_BYE
        JSR PRINT_STR
        RTS

; --- Stuur 0-terminated string in A/Y naar LilyGO ($A041) en toon op scherm ---
SEND_LORA_CMD:
        STA ZP_PTR
        STY ZP_PTR+1
        LDA #'>'
        JSR PUTCHAR
        LDA #' '
        JSR PUTCHAR
        LDY #$00
SendLoop:
        LDA (ZP_PTR),Y
        BEQ SendDone
        JSR PUTCHAR
        STA IO_LORA_DATA
        INY
        BNE SendLoop
SendDone:
        RTS

; --- Toon actuele hardware RSSI ($A042) en Packet Counter ($A043) ---
PRINT_STATUS_LINE:
        LDA #<MSG_TELEM1
        LDY #>MSG_TELEM1
        JSR PRINT_STR
        LDA IO_LORA_RSSI
        JSR PRINT_DEC8
        LDA #<MSG_TELEM2
        LDY #>MSG_TELEM2
        JSR PRINT_STR
        LDA IO_LORA_PKTS
        JSR PRINT_DEC8
        LDA #<MSG_TELEM3
        LDY #>MSG_TELEM3
        JSR PRINT_STR
        RTS

; --- Print 8-bit getal in A (0..255) als decimaal ---
PRINT_DEC8:
        LDY #$00
        CMP #100
        BCC DecTens
HundLoop:
        SBC #100
        INY
        CMP #100
        BCS HundLoop
        PHA
        TYA
        CLC
        ADC #'0'
        JSR PUTCHAR
        PLA
        LDY #$00
        JMP TensLoopCheck
DecTens:
        LDY #$00
TensLoopCheck:
        CMP #10
        BCC DecOnes
TensLoop:
        SBC #10
        INY
        CMP #10
        BCS TensLoop
        PHA
        TYA
        CLC
        ADC #'0'
        JSR PUTCHAR
        PLA
DecOnes:
        CLC
        ADC #'0'
        JSR PUTCHAR
        RTS

DRAW_UI:
        LDA #$0C                ; CLS
        JSR PUTCHAR
        LDA #<MSG_HEADER
        LDY #>MSG_HEADER
        JSR PRINT_STR
        JSR PRINT_STATUS_LINE
        RTS

PRINT_STR:
        STA ZP_PTR
        STY ZP_PTR+1
        LDY #$00
PrLoop:
        LDA (ZP_PTR),Y
        BEQ PrDone
        JSR PUTCHAR
        INY
        BNE PrLoop
        INC ZP_PTR+1
        JMP PrLoop
PrDone:
        RTS

PUTCHAR:
        STA IO_TERM
        RTS

; --- Teksten & Commando's ---
MSG_HEADER:
        DB "======================================================", 10
        DB " LILYGO T3 v1.6.1 (868 MHz SX1276 LoRa + OLED) STUDIO", 10
        DB " Tang Nano 20K Pin 30 (TX->IO12) & Pin 31 (RX<-IO4)", 10
        DB "======================================================", 10
        DB " [1] AT+INFO  (Status, 868.1MHz, SF7, RSSI & VBAT)", 10
        DB " [2] AT+PING  (Zend 868 MHz LoRa PING-pakket)", 10
        DB " [3] AT+OLED  (Zet tekst op 0.96 inch LilyGO OLED)", 10
        DB " [4] AT+SCAN  (Scan alle 8 EU868 LoRa-kanalen)", 10
        DB " [5] AT+SEND  (Zend Hallo-bericht via 868 MHz LoRa)", 10
        DB " [T] Typ eigen bericht/AT-commando  [L] Sim/HW Modus", 10
        DB " [C] Wis scherm                     [Q/ESC] Afsluiten", 10
        DB "------------------------------------------------------", 10, 0

MSG_TELEM1:
        DB "[HW $A042-$A043] 868MHz Signaal: -", 0
MSG_TELEM2:
        DB " dBm | Pakketten: ", 0
MSG_TELEM3:
        DB 10, 0

MSG_MODE_PREFIX:
        DB "* Modus gewisseld naar: ", 0
MSG_MODE_HW:
        DB "ECHTE HARDWARE (Pin 30=TXD / Pin 31=RXD)", 10, 0
MSG_MODE_SIM:
        DB "868 MHz HARDWARE SIMULATOR ($A040=128)", 10, 0

MSG_PROMPT:
        DB "Typ 868MHz bericht of AT+commando: ", 0
MSG_BYE:
        DB 10, "Terug naar MiniGPU-BASIC.", 10, 0

CMD_INFO:
        DB "AT+INFO", 10, 0
CMD_PING:
        DB "AT+PING", 10, 0
CMD_OLED:
        DB "AT+OLED=TANG NANO 20K 6502!", 10, 0
CMD_SCAN:
        DB "AT+SCAN", 10, 0
CMD_HELLO:
        DB "AT+SEND=Hallo op 868.1 MHz vanaf de 6502 MiniGPU!", 10, 0
