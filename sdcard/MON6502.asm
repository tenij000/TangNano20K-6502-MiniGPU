; ============================================================================
; MON6502.asm - MiniGPU 6502 Machinecode Monitor, Lijn-Assembler & Disassembler
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC op $9000).
;
; Speciaal ontworpen voor het intypen, disassembleren en uitvoeren van 6502
; machinecode-listings uit jaren '80 tijdschriften (Elektuur, Compute!, Byte,
; KIM-1, C64, Apple II & Acorn):
;   * Volledige 6502 Disassembler (alle 56 mnemonics & 13 adresseringsmodi)
;   * Interactieve 6502 Lijn-Assembler (bijv. LDA #$41, JSR $FFD2, BNE $3002)
;   * Tijdschrift Hex-Dump Editor (8 bytes per rij + automatische Checksum!)
;   * Ingebouwde $FFD2 (CHROUT) ondersteuning met live grafisch Uitvoer-venster
;   * Live 6502 CPU Register-weergave (A, X, Y, SP en NV-BDIZC vlaggen)
;   * 3 Ingebouwde Tijdschrift-Demo's + Opslaan/Laden op MicroSD-kaart!
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_RNG          = $A005         ; Hardware LFSR Random byte
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- ROM Routines voor MicroSD Opslag (Sector $03FB voor $3000..$31FF) ---
ZP_DST          = $1C
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA

; --- Zero Page Variabelen ($50..$8F) ---
EDIT_BUF        = $50           ; $50..$67 = 24-byte invoerbuffer voor ASM/HEX/ADRES
ZP_PTR_LO       = $68           ; Algemene 16-bit pointer
ZP_PTR_HI       = $69
ZP_X_LO         = $6A           ; 16-bit GPU X
ZP_X_HI         = $6B
ZP_Y_LO         = $6C           ; 16-bit GPU Y
ZP_Y_HI         = $6D
ZP_FG_COL       = $6E

CUR_LO          = $70           ; Huidig geselecteerd adres Low ($3000 standaard)
CUR_HI          = $71           ; Huidig geselecteerd adres High
DIS_LO          = $72           ; Tijdelijk disassembler-adres Low
DIS_HI          = $73           ; Tijdelijk disassembler-adres High
HEX_BASE_LO     = $74           ; Basisadres voor het rechter 64-byte Hex-venster
HEX_BASE_HI     = $75

EDIT_MODE       = $76           ; 0=Nav, 1=ASM, 2=HEX-rij, 3=Adres(T), 4=ESC-Menu
EDIT_LEN        = $77           ; Lengte in EDIT_BUF
PREV_JOY        = $78
ROW_IDX         = $79           ; Rij-teller bij tekenen
INST_LEN        = $7A           ; Lengte van huidige 6502 instructie (1..3 bytes)
CUR_NEXT_LO     = $7B           ; Adres van instructie na CUR_LO/HI (voor pijl omlaag)
CUR_NEXT_HI     = $7C
CHKSUM          = $7D           ; 8-bit Tijdschrift-Checksum per rij van 8 bytes

; Assembler werk-variabelen
ASM_MNEM        = $7E           ; Gevonden mnemonic-index (0..55)
ASM_MODE        = $7F           ; Gevonden addressing mode (0..12)
ASM_VAL_LO      = $80           ; Geassembleerde operand Low
ASM_VAL_HI      = $81           ; Geassembleerde operand High
ASM_DIGITS      = $82           ; Aantal hex-cijfers gelezen (2 = ZP, 4 = ABS)
PARSE_IDX       = $83           ; Index in EDIT_BUF tijdens parsen
ZP_SAV_X        = $84
ZP_SAV_Y        = $85
OPC_BYTE        = $86           ; Huidige opcode byte
MODE_BYTE       = $87           ; Huidige addressing mode byte

; Virtuele 6502 CPU Registers (bewaard voor & na 'G' Run!)
REG_A           = $88
REG_X           = $89
REG_Y           = $8A
REG_SP          = $8B
REG_P           = $8C
OUT_LEN         = $8D           ; Aantal tekens in het $FFD2 Uitvoer-venster (0..44)

; --- Vaste Buffers & Trampolines in BSRAM ($02A0..$02E2) ---
OUT_BUF         = $02A0         ; 48-byte ASCIIZ buffer voor $FFD2 (CHROUT) uitvoer
CHROUT_VEC      = $02D2         ; $02D2: JMP MON_CHROUT (vangt JSR $FFD2 op!)
CALL_TRAMP      = $02D5         ; $02D5: JMP ($0070) om gebruikerscode via JSR aan te roepen
BSRAM_EXIT_MC   = $02D8         ; $02D8: 11-byte BSRAM Exit naar BASIC/MC

; Adresseringsmodi constanten (ZP+4 == ABS, ZPX+4 == ABSX, ZPY+4 == ABSY)
MODE_IMP        = 0
MODE_ACC        = 1
MODE_IMM        = 2
MODE_ZP         = 3
MODE_ZPX        = 4
MODE_ZPY        = 5
MODE_REL        = 6
MODE_ABS        = 7
MODE_ABSX       = 8
MODE_ABSY       = 9
MODE_IND        = 10
MODE_INDX       = 11
MODE_INDY       = 12

; ============================================================================
; Startpunt ($8000)
; ============================================================================
START:
        ; Installeer $02D2 CHROUT-vector, CALL-trampoline en BSRAM_EXIT_MC
        LDX #16
INIT_BSRAM_LP:
        LDA BSRAM_INIT_TBL,X
        STA CHROUT_VEC,X
        DEX
        BPL INIT_BSRAM_LP

        LDA #0
        STA IO_MODE
        STA EDIT_MODE
        STA REG_A
        STA REG_X
        STA REG_Y
        LDA #$30                ; Standaard statusvlaggen (nv-Bdizc = $30)
        STA REG_P
        TSX
        STX REG_SP

        JSR RESET_ADDR_3000

        ; Controleer of in $3000 al code staat; zo niet, laad Tijdschrift Demo #1!
        LDA $3000
        ORA $3001
        BNE S_HAS_CODE
        LDA #0
        JSR LOAD_DEMO_IDX
        JSR FULL_REDRAW
        JMP DO_RUN_CODE
S_HAS_CODE:
        JSR FULL_REDRAW
        LDA #(STR_MSG_READY - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        LDA IO_JOY
        STA PREV_JOY

; ============================================================================
; Hoofdlus: Navigatie, Invoer & ESC-Menu
; ============================================================================
MAIN_LOOP:
        LDA IO_TIMER
W10_POLL:
        CMP IO_TIMER
        BEQ W10_POLL

        ; 1. Check ESC (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_NAV_JOY
        LDA IO_TERM             ; Lees en wis ESC ($1B)
        LDA #0
        STA IO_MODE             ; Houd terminal-overlay uit (top.v zet term_enable=1 bij ESC!)
        LDA EDIT_MODE
        BEQ OPEN_MENU_NOW
        CMP #4
        BEQ EXIT_TO_MC          ; Nogmaals ESC in het menu = Terug naar BASIC/MC!
        ; Annuleer huidige invoer (ASM / HEX / ADRES)
        LDA #0
        STA EDIT_MODE
        JSR DRAW_INPUT_BAR
        LDA #(STR_MSG_CANCEL - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

OPEN_MENU_NOW:
        JSR OPEN_ESC_MENU
        JMP MAIN_LOOP

EXIT_TO_MC:
        JSR ROM_SILENCE
        JMP BSRAM_EXIT_MC

CHK_NAV_JOY:
        LDA EDIT_MODE
        BNE CHK_TERM_CHAR

        LDA IO_JOY
        STA ZP_SAV_X
        TAX
        EOR PREV_JOY
        AND ZP_SAV_X
        STX PREV_JOY
        TAY
        BEQ CHK_TERM_CHAR

        LDA IO_TERM             ; Wis bijbehorende pijl/WASD uit IO_TERM
        TYA
        AND #1                  ; Pijl Omhoog
        BNE NAV_UP
        TYA
        AND #2                  ; Pijl Omlaag
        BNE NAV_DOWN
        TYA
        AND #4                  ; Pijl Links (-1 byte)
        BNE NAV_LEFT
        TYA
        AND #8                  ; Pijl Rechts (+1 byte)
        BNE NAV_RIGHT
        JMP MAIN_LOOP

NAV_LEFT:
        LDA CUR_LO
        BNE NL_DEC
        DEC CUR_HI
NL_DEC:
        DEC CUR_LO
        JMP NAV_REDRAW

NAV_RIGHT:
        LDA #1
        JSR ADV_CUR_BY_A
        JMP NAV_REDRAW

NAV_DOWN:
        LDA CUR_NEXT_LO
        STA CUR_LO
        LDA CUR_NEXT_HI
        STA CUR_HI
        JMP NAV_REDRAW

NAV_UP:
        ; Stap slim 1 instructie terug (zoek 1..3 bytes terug of die precies op CUR_LO uitkomt)
        LDY #3
NU_TRY:
        STY ZP_SAV_Y
        SEC
        LDA CUR_LO
        SBC ZP_SAV_Y
        STA DIS_LO
        LDA CUR_HI
        SBC #0
        STA DIS_HI
        JSR GET_DIS_LEN
        CLC
        ADC DIS_LO
        CMP CUR_LO
        BEQ NU_FOUND
        LDY ZP_SAV_Y
        DEY
        CPY #1
        BNE NU_TRY
NU_FOUND:
        LDA DIS_LO
        STA CUR_LO
        LDA DIS_HI
        STA CUR_HI
NAV_REDRAW:
        JSR REFRESH_CODE_VIEWS
        JMP MAIN_LOOP

CHK_TERM_CHAR:
        LDA IO_STATUS
        AND #1
        BEQ MAIN_LOOP
        LDA IO_TERM
        STA ZP_SAV_Y
        LDA IO_JOY
        STA PREV_JOY

        LDA EDIT_MODE
        BEQ NAV_KEY_HANDLER
        CMP #4
        BNE EDIT_KEY_HANDLER
        JMP MENU_KEY_HANDLER

; ============================================================================
; Toetsen in Navigatie-Modus (EDIT_MODE == 0)
; ============================================================================
NAV_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #$0D                ; Enter = Start 6502 Lijn-Assembler op huidig adres!
        BEQ START_ASM_MODE
        CMP #':'                ; ':' = Start Tijdschrift Hex-Rij Editor!
        BEQ START_HEX_MODE
        CMP #'1'
        BCC NKH_ALPHA
        CMP #'4'
        BCC DO_DEMO_KEY
NKH_ALPHA:
        AND #$DF                ; Maak hoofdletter
        CMP #'A'                ; A = Assembleer instructie op huidig adres
        BEQ START_ASM_MODE
        CMP #'M'                ; M = Memory Hex-Rij invoeren
        BEQ START_HEX_MODE
        CMP #'T'                ; T = Typ nieuw Adres (Goto Address)
        BEQ START_ADDR_MODE
        CMP #'G'                ; G = Go / Run machinecode vanaf huidig adres!
        BEQ DO_RUN_CODE
        CMP #'R'                ; R = Reset adres naar $3000
        BEQ DO_RESET_3000
        CMP #'N'                ; N = Nieuw leeg programma op $3000
        BEQ MKH_NEW
        CMP #'C'                ; C = Wis Uitvoer-venster ($FFD2 console)
        BEQ DO_CLEAR_OUT
        JMP MAIN_LOOP

START_ASM_MODE:
        LDA #1
        BNE INIT_EDIT_BAR
START_HEX_MODE:
        LDA #2
        BNE INIT_EDIT_BAR
START_ADDR_MODE:
        LDA #3
INIT_EDIT_BAR:
        STA EDIT_MODE
        JSR CLEAR_EDIT_BUF
        JSR DRAW_INPUT_BAR
        LDA #(STR_MSG_EDIT - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

DO_RESET_3000:
        JSR RESET_ADDR_3000
        JMP NAV_REDRAW

DO_CLEAR_OUT:
        JSR CLEAR_OUT_CONSOLE
        JSR DRAW_OUTPUT_PANEL
        JMP MAIN_LOOP

DO_DEMO_KEY:
        SEC
        SBC #'1'
        JSR LOAD_DEMO_IDX
        LDA #0
        STA EDIT_MODE
        JSR RESET_ADDR_3000
        JSR FULL_REDRAW
DO_RUN_CODE:
        JSR RUN_USER_CODE_SILENT
        JSR DRAW_HEX_PANEL
        JSR DRAW_REGS_PANEL
        JSR DRAW_OUTPUT_PANEL
        LDA #(STR_MSG_RAN - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; ============================================================================
; Bewerken in de Invoerbalk (EDIT_MODE 1=ASM, 2=HEX, 3=ADRES)
; ============================================================================
EDIT_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #$0D
        BEQ COMMIT_EDIT_LINE
        CMP #$08
        BEQ EDIT_BS
        CMP #$7F
        BEQ EDIT_BS
        CMP #$20
        BCC EKH_RTS
        CMP #$7B
        BCS EKH_RTS
        CMP #'a'
        BCC EKH_CHK_LEN
        CMP #'z'+1
        BCS EKH_CHK_LEN
        AND #$DF
EKH_CHK_LEN:
        LDX EDIT_LEN
        CPX #23
        BCS EKH_RTS
        STA EDIT_BUF,X
        INX
        STX EDIT_LEN
        LDA #0
        STA EDIT_BUF,X
        JSR DRAW_INPUT_BAR
EKH_RTS:
        JMP MAIN_LOOP

EDIT_BS:
        LDX EDIT_LEN
        BEQ EKH_RTS
        DEX
        STX EDIT_LEN
        LDA #0
        STA EDIT_BUF,X
        JSR DRAW_INPUT_BAR
        JMP MAIN_LOOP

COMMIT_EDIT_LINE:
        LDA EDIT_LEN
        BNE CEL_NON_EMPTY
        LDA #0
        STA EDIT_MODE
        JSR DRAW_INPUT_BAR
        LDA #(STR_MSG_READY - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

CEL_NON_EMPTY:
        LDA EDIT_MODE
        CMP #1
        BEQ COMMIT_ASM_LINE
        CMP #2
        BEQ COMMIT_HEX_LINE
        LDA #0
        STA PARSE_IDX
        JSR PARSE_HEX_VALUE
        LDA ASM_DIGITS
        BEQ CEL_ERR
        LDA ASM_VAL_LO
        STA CUR_LO
        LDA ASM_VAL_HI
        STA CUR_HI
        LDA #0
        STA EDIT_MODE
        LDA #(STR_MSG_READY - STR_MSG_BASE)
        BNE FINISH_EDIT_OK

COMMIT_ASM_LINE:
        JSR ASSEMBLE_LINE
        BCS CEL_ERR
        JMP FINISH_ASM_HEX

COMMIT_HEX_LINE:
        JSR PARSE_HEX_ROW
        BCS CEL_ERR
FINISH_ASM_HEX:
        LDA #(STR_MSG_ASMD - STR_MSG_BASE)
FINISH_EDIT_OK:
        PHA
        JSR CLEAR_EDIT_BUF
        JSR REFRESH_CODE_VIEWS
        PLA
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

CEL_ERR:
        LDA #(STR_MSG_ERR - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

CLEAR_EDIT_BUF:
        LDA #0
        STA EDIT_LEN
        STA EDIT_BUF
        RTS

REFRESH_CODE_VIEWS:
        JSR SYNC_HEX_BASE
        JSR DRAW_DISASM_PANEL
        JSR DRAW_HEX_PANEL
        JMP DRAW_INPUT_BAR

; ============================================================================
; ESC Popup-Menu (Met volledige hertekening bij sluiten!)
; ============================================================================
OPEN_ESC_MENU:
        LDA #4
        STA EDIT_MODE
        LDX #70                 ; 3 rechthoeken voor het popup-venster (offset 70..99)
        JSR SEND_RECT_10
        JSR SEND_RECT_10
        JSR SEND_RECT_10
        LDA #<STR_POPUP_MENU
        LDY #>STR_POPUP_MENU
        JMP DRAW_HDR_LIST

CLOSE_ESC_MENU:
        LDA #0
        STA EDIT_MODE
        JSR FULL_REDRAW
        LDA #(STR_MSG_READY - STR_MSG_BASE)
        JMP SHOW_STATUS_MSG

MENU_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #' '
        BEQ MKH_CLOSE
        CMP #$0D
        BEQ MKH_CLOSE
        CMP #'1'
        BCC MKH_CHK_LET
        CMP #'4'
        BCC DO_DEMO_KEY
        CMP #'4'
        BEQ MKH_NEW
        CMP #'5'
        BEQ MKH_SAVE
        CMP #'6'
        BEQ MKH_LOAD
MKH_CHK_LET:
        AND #$DF
        CMP #'N'
        BEQ MKH_NEW
        CMP #'S'
        BEQ MKH_SAVE
        CMP #'L'
        BEQ MKH_LOAD
        CMP #'Q'
        BNE MKH_END
        JMP EXIT_TO_MC
MKH_END:
        JMP MAIN_LOOP

MKH_CLOSE:
        JSR CLOSE_ESC_MENU
        JMP MAIN_LOOP

MKH_NEW:
        JSR CLEAR_USER_MEM
        JSR CLEAR_OUT_CONSOLE
        JSR RESET_ADDR_3000
        JMP MKH_CLOSE

MKH_SAVE:
        JSR PREP_SD_SEC
        JSR ROM_WRITE_SEC
        JSR CLOSE_ESC_MENU
        LDA #(STR_MSG_SAVED - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

MKH_LOAD:
        JSR PREP_SD_SEC
        JSR ROM_READ_SEC
        JMP MKH_CLOSE

PREP_SD_SEC:
        JSR ROM_SD_INIT
        LDA #$FB                ; Sector $03FB = 512 bytes voor $3000..$31FF
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDA #$00
        STA ZP_DST
        LDA #$30
        STA ZP_DST+1
        RTS

; ============================================================================
; Uitvoeren van Gebruikers-Machinecode ('G') + $FFD2 (CHROUT) Ondersteuning
; ============================================================================
RUN_USER_CODE_SILENT:
        JSR CLEAR_OUT_CONSOLE
        ; Vervang tijdelijk JSR $FFD2 (20 D2 FF) in $3000..$31FC door JSR $02D2 (20 D2 02)
        LDA #$FF
        LDY #$02
        JSR PATCH_FFD2

        ; Laad de virtuele 6502 registers en voer JSR (CUR_LO) uit!
        LDA REG_P
        PHA
        LDA REG_A
        LDX REG_X
        LDY REG_Y
        PLP
        JSR CALL_TRAMP

        ; Bewaar de resulterende 6502 registers na RTS!
        PHP
        STA REG_A
        STX REG_X
        STY REG_Y
        PLA
        STA REG_P
        TSX
        STX REG_SP

        ; Zet JSR $02D2 (20 D2 02) in $3000..$31FC weer netjes terug naar JSR $FFD2 (20 D2 FF)!
        LDA #$02
        LDY #$FF
PATCH_FFD2:
        STA ASM_VAL_LO
        STY ASM_VAL_HI
        LDA #$00
        STA ZP_PTR_LO
        LDA #$30
        STA ZP_PTR_HI
PFF_LP:
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #$20                ; Opcode $20 = JSR
        BNE PFF_NXT
        INY
        LDA (ZP_PTR_LO),Y
        CMP #$D2
        BNE PFF_NXT
        INY
        LDA (ZP_PTR_LO),Y
        CMP ASM_VAL_LO
        BNE PFF_NXT
        LDA ASM_VAL_HI
        STA (ZP_PTR_LO),Y
PFF_NXT:
        INC ZP_PTR_LO
        BNE PFF_LP
        INC ZP_PTR_HI
        LDA ZP_PTR_HI
        CMP #$32
        BCC PFF_LP
        RTS

; Wordt aangeroepen via $02D2 wanneer een tijdschrift-programma JSR $FFD2 doet!
MON_CHROUT:
        PHA
        TXA
        PHA
        TYA
        PHA
        TSX
        LDA $0103,X
        CMP #$20
        BCC MCO_DONE
        LDX OUT_LEN
        CPX #44
        BCS MCO_DONE
        STA OUT_BUF,X
        INX
        STX OUT_LEN
        LDA #0
        STA OUT_BUF,X
MCO_DONE:
        PLA
        TAY
        PLA
        TAX
        PLA
        RTS

CLEAR_OUT_CONSOLE:
        LDA #0
        STA OUT_LEN
        STA OUT_BUF
        LDX #50
        JMP SEND_RECT_10

; ============================================================================
; 6502 Lijn-Assembler (Vertaalt tekst in EDIT_BUF naar machinecode op CUR_LO/HI)
; Ondersteunt alle 56 mnemonics, 13 modi, relatieve sprongen én hex met/zonder '$'
; ============================================================================
ASSEMBLE_LINE:
        LDA #0
        STA PARSE_IDX
        JSR SKIP_BUF_SPACES
        LDX PARSE_IDX
        LDA EDIT_BUF,X
        BEQ ASL_ERR_RET
        LDA EDIT_BUF+1,X
        BEQ ASL_ERR_RET
        LDA EDIT_BUF+2,X
        BEQ ASL_ERR_RET

        LDY #0
ASL_FIND_M:
        LDA EDIT_BUF,X
        CMP MNEM_C0,Y
        BNE ASL_NEXT_M
        LDA EDIT_BUF+1,X
        CMP MNEM_C1,Y
        BNE ASL_NEXT_M
        LDA EDIT_BUF+2,X
        CMP MNEM_C2,Y
        BEQ ASL_GOT_M
ASL_NEXT_M:
        INY
        CPY #56
        BCC ASL_FIND_M
ASL_ERR_RET:
        SEC
        RTS

ASL_GOT_M:
        STY ASM_MNEM
        TXA
        CLC
        ADC #3
        STA PARSE_IDX
        JSR SKIP_BUF_SPACES

        LDX PARSE_IDX
        LDA EDIT_BUF,X
        BNE ASL_HAS_OP
        LDA #MODE_IMP
        JSR FIND_OPCODE_A
        BCC ASL_EMIT_1
        LDA #MODE_ACC
        JSR FIND_OPCODE_A
        BCS ASL_ERR_RET
ASL_EMIT_1:
        LDY #0
        STA (CUR_LO),Y
        LDA #1
        JMP ADV_CUR_BY_A

ASL_HAS_OP:
        CMP #'A'
        BNE ASL_CHK_IMM
        LDA EDIT_BUF+1,X
        BNE ASL_CHK_IMM
        LDA #MODE_ACC
        JSR FIND_OPCODE_A
        BCC ASL_EMIT_1
        RTS

ASL_CHK_IMM:
        CMP #'#'
        BNE ASL_CHK_IND
        INC PARSE_IDX
        JSR PARSE_HEX_VALUE
        LDA ASM_DIGITS
        BEQ ASL_ERR_RET
        LDA #MODE_IMM
        JMP TRY_MODE_EMIT2

ASL_CHK_IND:
        CMP #'('
        BNE ASL_DIRECT_ADDR
        INC PARSE_IDX
        JSR PARSE_HEX_VALUE
        LDA ASM_DIGITS
        BEQ ASL_ERR_RET
        JSR SKIP_BUF_SPACES
        LDX PARSE_IDX
        LDA EDIT_BUF,X
        CMP #','
        BEQ ASL_IND_X
        CMP #')'
        BNE ASL_ERR_RET
        INC PARSE_IDX
        JSR SKIP_BUF_SPACES
        LDX PARSE_IDX
        LDA EDIT_BUF,X
        BEQ ASL_IND_ABS
        CMP #','
        BNE ASL_ERR_RET
        LDA EDIT_BUF+1,X
        CMP #'Y'
        BNE ASL_ERR_RET
        LDA #MODE_INDY
        JMP TRY_MODE_EMIT2

ASL_IND_ABS:
        LDA #MODE_IND
        JSR FIND_OPCODE_A
        BCS ASL_ERR_RET
        JMP ASL_EMIT_3

ASL_IND_X:
        LDA EDIT_BUF+1,X
        CMP #'X'
        BNE ASL_ERR_RET
        LDA EDIT_BUF+2,X
        CMP #')'
        BNE ASL_ERR_RET
        LDA #MODE_INDX
TRY_MODE_EMIT2:
        JSR FIND_OPCODE_A
        BCC ASL_EMIT_2
        RTS

ASL_DIRECT_ADDR:
        JSR PARSE_HEX_VALUE
        LDA ASM_DIGITS
        BEQ ASL_ERR_RET
        JSR SKIP_BUF_SPACES
        LDX PARSE_IDX
        LDA EDIT_BUF,X
        BEQ ASL_NO_INDEX
        CMP #','
        BNE ASL_ERR_RET
        LDA EDIT_BUF+1,X
        LDY #MODE_ZPX
        CMP #'X'
        BEQ ASL_TRY_ZP_ABS
        LDY #MODE_ZPY
        CMP #'Y'
        BEQ ASL_TRY_ZP_ABS
        SEC
        RTS

ASL_NO_INDEX:
        LDA #MODE_REL
        JSR FIND_OPCODE_A
        BCS ASL_NOT_REL
        PHA
        CLC
        LDA CUR_LO
        ADC #2
        STA DIS_LO
        LDA CUR_HI
        ADC #0
        STA DIS_HI
        SEC
        LDA ASM_VAL_LO
        SBC DIS_LO
        STA ASM_VAL_LO
        LDA ASM_VAL_HI
        SBC DIS_HI
        LDX ASM_VAL_LO
        BMI ASL_REL_NEG
        CMP #$00
        BEQ ASL_REL_OK
ASL_REL_BAD:
        PLA
        SEC
        RTS
ASL_REL_NEG:
        CMP #$FF
        BNE ASL_REL_BAD
ASL_REL_OK:
        PLA
        JMP ASL_EMIT_2

ASL_NOT_REL:
        LDY #MODE_ZP
ASL_TRY_ZP_ABS:
        STY ASM_MODE
        LDA ASM_VAL_HI
        BNE ASL_TRY_ABS4
        LDA ASM_DIGITS
        CMP #3
        BCS ASL_TRY_ABS4
        LDA ASM_MODE
        JSR FIND_OPCODE_A
        BCC ASL_EMIT_2
ASL_TRY_ABS4:
        LDA ASM_MODE
        CLC
        ADC #4
        JSR FIND_OPCODE_A
        BCS ASL_RET_SEC
ASL_EMIT_3:
        LDY #0
        STA (CUR_LO),Y
        INY
        LDA ASM_VAL_LO
        STA (CUR_LO),Y
        INY
        LDA ASM_VAL_HI
        STA (CUR_LO),Y
        LDA #3
        BNE ADV_CUR_BY_A

ASL_EMIT_2:
        LDY #0
        STA (CUR_LO),Y
        INY
        LDA ASM_VAL_LO
        STA (CUR_LO),Y
        LDA #2
ADV_CUR_BY_A:
        CLC
        ADC CUR_LO
        STA CUR_LO
        BCC ACBA_OK
        INC CUR_HI
ACBA_OK:
        CLC
ASL_RET_SEC:
        RTS

FIND_OPCODE_A:
        STA ASM_MODE
        LDX #0
FO_LP:
        LDA OPC_MNEM,X
        CMP ASM_MNEM
        BNE FO_NXT
        JSR GET_OPC_MODE
        CMP ASM_MODE
        BEQ FO_FOUND
FO_NXT:
        INX
        BNE FO_LP
        SEC
        RTS
FO_FOUND:
        TXA
        CLC
        RTS

GET_OPC_MODE:
        TXA
        LSR A
        TAY
        LDA OPC_MODE_NIB,Y
        BCC GOM_LO
        LSR A
        LSR A
        LSR A
        LSR A
GOM_LO:
        AND #$0F
        RTS

; ============================================================================
; Tijdschrift Hex-Rij Parser (M-modus: bijv. "A9 41 20 D2 FF E8 E0 5B")
; ============================================================================
PARSE_HEX_ROW:
        LDA #0
        STA PARSE_IDX
        STA ROW_IDX
PHR_LP:
        JSR SKIP_BUF_SPACES
        LDX PARSE_IDX
        LDA EDIT_BUF,X
        BEQ PHR_DONE
        CMP #':'
        BEQ PHR_DONE
        JSR PARSE_HEX_VALUE
        LDA ASM_DIGITS
        BEQ PHR_ERR
        LDY #0
        LDA ASM_VAL_LO
        STA (CUR_LO),Y
        LDA #1
        JSR ADV_CUR_BY_A
        INC ROW_IDX
        JMP PHR_LP
PHR_DONE:
        LDA ROW_IDX
        BEQ PHR_ERR
        CLC
        RTS
PHR_ERR:
        SEC
        RTS

SKIP_BUF_SPACES:
        LDX PARSE_IDX
SBS_LP:
        LDA EDIT_BUF,X
        CMP #' '
        BNE SBS_DONE
        INX
        BNE SBS_LP
SBS_DONE:
        STX PARSE_IDX
        RTS

PARSE_HEX_VALUE:
        LDA #0
        STA ASM_VAL_LO
        STA ASM_VAL_HI
        STA ASM_DIGITS
        JSR SKIP_BUF_SPACES
        LDX PARSE_IDX
        LDA EDIT_BUF,X
        CMP #'$'
        BNE PHV_LP
        INX
        STX PARSE_IDX
PHV_LP:
        LDX PARSE_IDX
        LDA EDIT_BUF,X
        JSR CHAR_TO_HEX_NIB
        BCS PHV_DONE
        LDY #4
PHV_SH:
        ASL ASM_VAL_LO
        ROL ASM_VAL_HI
        DEY
        BNE PHV_SH
        ORA ASM_VAL_LO
        STA ASM_VAL_LO
        INC ASM_DIGITS
        INC PARSE_IDX
        JMP PHV_LP
PHV_DONE:
        RTS

CHAR_TO_HEX_NIB:
        CMP #'0'
        BCC CTH_NO
        CMP #'9'+1
        BCC CTH_DIG
        CMP #'A'
        BCC CTH_NO
        CMP #'F'+1
        BCS CTH_NO
        SBC #('A' - 10 - 1)
        CLC
        RTS
CTH_DIG:
        SBC #('0' - 1)
        CLC
        RTS
CTH_NO:
        SEC
        RTS

; ============================================================================
; 6502 Disassembler & Schermopbouw (Volledig Scherm 640x360)
; ============================================================================
FULL_REDRAW:
        LDX #0
FR_GUI_LP:
        LDA GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #(GUI_STREAM_END - GUI_STREAM)
        BCC FR_GUI_LP

        LDA #<STR_HEADERS
        LDY #>STR_HEADERS
        JSR DRAW_HDR_LIST
        JSR REFRESH_CODE_VIEWS
        JSR DRAW_REGS_PANEL
        LDX #50
        JSR SEND_RECT_10
        JMP DRAW_OUTPUT_PANEL

DRAW_HDR_LIST:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DHL_LP:
        JSR NEXT_PTR_BYTE
        BEQ DHL_RTS
        STA ZP_X_LO
        JSR NEXT_PTR_BYTE
        STA ZP_X_HI
        JSR NEXT_PTR_BYTE
        STA ZP_Y_LO
        LDY #0
        CMP #(283 & $FF)
        BNE DHL_Y0
        INY
DHL_Y0:
        STY ZP_Y_HI
        JSR NEXT_PTR_BYTE
        STA ZP_FG_COL
        JSR DRAW_ZP_STR
        JMP DHL_LP
DHL_RTS:
        RTS

GET_DIS_LEN:
        LDY #0
        LDA (DIS_LO),Y
        STA OPC_BYTE
        TAX
        JSR GET_OPC_MODE
        STA MODE_BYTE
        TAY
        LDA MODE_LEN_TBL,Y
        STA INST_LEN
        RTS

DRAW_DISASM_PANEL:
        LDA CUR_LO
        STA DIS_LO
        LDA CUR_HI
        STA DIS_HI
        LDA #0
        STA ROW_IDX
DDP_ROW_LP:
        LDA ROW_IDX
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #68
        STA ZP_Y_LO
        STA DIS_ROW_Y
        LDX #$00
        LDA ROW_IDX
        BNE DDP_SET_BG
        LDX #$13
DDP_SET_BG:
        STX DIS_ROW_COL
        LDX #40
        JSR SEND_RECT_10

        CLC
        LDA ZP_Y_LO
        ADC #4
        TAY
        LDA #14
        JSR SET_XY_POS
        LDA #$1F
        STA ZP_FG_COL
        JSR DRAW_DOL_DIS_HEX

        JSR GET_DIS_LEN
        LDA #66
        STA ZP_X_LO
        LDA #$B6
        STA ZP_FG_COL
        LDY #0
DDP_HEX_LP:
        STY ZP_SAV_Y
        LDA (DIS_LO),Y
        JSR DRAW_HEX_BYTE
        LDA #' '
        JSR DRAW_CHAR_ADV
        LDY ZP_SAV_Y
        INY
        CPY INST_LEN
        BCC DDP_HEX_LP

        LDA #150
        STA ZP_X_LO
        LDA #$FC
        STA ZP_FG_COL
        LDX OPC_BYTE
        LDY OPC_MNEM,X
        LDA MNEM_C0,Y
        JSR DRAW_CHAR_ADV
        LDA MNEM_C1,Y
        JSR DRAW_CHAR_ADV
        LDA MNEM_C2,Y
        JSR DRAW_CHAR_ADV
        LDA #' '
        JSR DRAW_CHAR_ADV

        LDA #$FF
        STA ZP_FG_COL
        JSR DRAW_DIS_OPERAND

        CLC
        LDA DIS_LO
        ADC INST_LEN
        STA DIS_LO
        BCC DDP_NXT_OK
        INC DIS_HI
DDP_NXT_OK:
        LDA ROW_IDX
        BNE DDP_NOT_FIRST
        LDA DIS_LO
        STA CUR_NEXT_LO
        LDA DIS_HI
        STA CUR_NEXT_HI
DDP_NOT_FIRST:
        INC ROW_IDX
        LDA ROW_IDX
        CMP #12
        BCC DDP_ROW_LP
        RTS

DRAW_DIS_OPERAND:
        LDA MODE_BYTE
        BEQ DDO_RTS
        CMP #MODE_ACC
        BNE DDO_CHK_IMM
        LDA #'A'
        JMP DRAW_CHAR_ADV
DDO_CHK_IMM:
        CMP #MODE_IMM
        BNE DDO_CHK_REL
        LDA #'#'
        JSR DRAW_CHAR_ADV
        JMP DDO_ZP_VAL
DDO_CHK_REL:
        CMP #MODE_REL
        BNE DDO_CHK_IND
        CLC
        LDA DIS_LO
        ADC #2
        STA ASM_VAL_LO
        LDA DIS_HI
        ADC #0
        STA ASM_VAL_HI
        LDY #1
        LDA (DIS_LO),Y
        BPL DDO_R_POS
        DEC ASM_VAL_HI
DDO_R_POS:
        CLC
        ADC ASM_VAL_LO
        PHA
        LDA ASM_VAL_HI
        ADC #0
        PHA
        LDA #'$'
        JSR DRAW_CHAR_ADV
        PLA
        JSR DRAW_HEX_BYTE
        PLA
        JMP DRAW_HEX_BYTE

DDO_CHK_IND:
        CMP #MODE_IND
        BCC DDO_ZP_OR_ABS
        LDA #'('
        JSR DRAW_CHAR_ADV
        LDA MODE_BYTE
        CMP #MODE_IND
        BNE DDO_IND_ZP
        JSR DDO_ABS_VAL
        LDA #')'
        JMP DRAW_CHAR_ADV
DDO_IND_ZP:
        JSR DDO_ZP_VAL
        LDA MODE_BYTE
        CMP #MODE_INDX
        BNE DDO_IND_Y
        JSR DDO_COMMA_X
        LDA #')'
        JMP DRAW_CHAR_ADV
DDO_IND_Y:
        LDA #')'
        JSR DRAW_CHAR_ADV
        JMP DDO_COMMA_Y

DDO_ZP_OR_ABS:
        CMP #MODE_ABS
        BCS DDO_IS_ABS
        JSR DDO_ZP_VAL
        JMP DDO_CHK_XY
DDO_IS_ABS:
        JSR DDO_ABS_VAL
DDO_CHK_XY:
        LDA MODE_BYTE
        AND #3
        BEQ DDO_COMMA_X
        CMP #1
        BEQ DDO_COMMA_Y
DDO_RTS:
        RTS

DDO_COMMA_X:
        LDX #'X'
        BNE DDO_COMMA_CH
DDO_COMMA_Y:
        LDX #'Y'
DDO_COMMA_CH:
        LDA #','
        JSR DRAW_CHAR_ADV
        TXA
        JMP DRAW_CHAR_ADV

DDO_ZP_VAL:
        LDA #'$'
        JSR DRAW_CHAR_ADV
        LDY #1
        LDA (DIS_LO),Y
        JMP DRAW_HEX_BYTE

DDO_ABS_VAL:
        LDA #'$'
        JSR DRAW_CHAR_ADV
        LDY #2
        LDA (DIS_LO),Y
        JSR DRAW_HEX_BYTE
        LDY #1
        LDA (DIS_LO),Y
        JMP DRAW_HEX_BYTE

; ============================================================================
; Tijdschrift Hex-Dump Paneel + Checksum (Rechtsboven: X=364..632, Y=68..196)
; ============================================================================
SYNC_HEX_BASE:
        LDA CUR_LO
        AND #$F8
        STA HEX_BASE_LO
        LDA CUR_HI
        STA HEX_BASE_HI
        RTS

DRAW_HEX_PANEL:
        LDX #20
        JSR SEND_RECT_10
        LDA HEX_BASE_LO
        STA DIS_LO
        LDA HEX_BASE_HI
        STA DIS_HI
        LDA #0
        STA ROW_IDX
DHP_ROW_LP:
        LDA ROW_IDX
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #72
        TAY
        LDA #(368 & $FF)
        JSR SET_XY_POS
        INC ZP_X_HI
        LDA #0
        STA CHKSUM
        LDA #$1F
        STA ZP_FG_COL
        JSR DRAW_DIS_HEX
        LDA #':'
        JSR DRAW_CHAR_ADV

        LDA #$FF
        STA ZP_FG_COL
        LDY #0
DHP_BYTE_LP:
        STY ZP_SAV_Y
        LDA (DIS_LO),Y
        PHA
        CLC
        ADC CHKSUM
        STA CHKSUM
        PLA
        JSR DRAW_HEX_BYTE
        LDA #' '
        JSR DRAW_CHAR_ADV
        LDY ZP_SAV_Y
        INY
        CPY #8
        BCC DHP_BYTE_LP

        LDA #$1C
        STA ZP_FG_COL
        LDA #':'
        JSR DRAW_CHAR_ADV
        LDA CHKSUM
        JSR DRAW_HEX_BYTE

        CLC
        LDA DIS_LO
        ADC #8
        STA DIS_LO
        BCC DHP_NXT
        INC DIS_HI
DHP_NXT:
        INC ROW_IDX
        LDA ROW_IDX
        CMP #8
        BCC DHP_ROW_LP
        RTS

; ============================================================================
; 6502 CPU Registers (Rechtsonder: X=364..632, Y=216..234)
; ============================================================================
DRAW_REGS_PANEL:
        LDX #30
        JSR SEND_RECT_10

        LDY #220
        LDA #(370 & $FF)
        JSR SET_XY_POS
        INC ZP_X_HI
        LDA #$FC
        STA ZP_FG_COL

        LDX #0
DRP_REG_LP:
        STX ZP_SAV_X
        LDA REG_NAMES,X
        JSR DRAW_CHAR_ADV
        LDA #'='
        JSR DRAW_CHAR_ADV
        LDX ZP_SAV_X
        LDA REG_A,X
        JSR DRAW_HEX_BYTE
        LDA #' '
        JSR DRAW_CHAR_ADV
        LDX ZP_SAV_X
        INX
        CPX #4
        BCC DRP_REG_LP

        LDA #$1C
        STA ZP_FG_COL
        LDX #0
        LDA REG_P
        STA ASM_VAL_LO
DRP_FLG_LP:
        STX ZP_SAV_X
        ASL ASM_VAL_LO
        LDA #'0'
        ADC #0
        JSR DRAW_CHAR_ADV
        LDX ZP_SAV_X
        INX
        CPX #8
        BCC DRP_FLG_LP
        RTS

; ============================================================================
; Programma Uitvoer Paneel ($FFD2 CHROUT Console: X=8..632, Y=286..336)
; ============================================================================
DRAW_OUTPUT_PANEL:
        LDY #50
        LDA #16
        JSR SET_XY_POS
        INC ZP_Y_HI
        LDA #$1C
        STA ZP_FG_COL
        LDA #<OUT_BUF
        LDY #>OUT_BUF
        JMP DRAW_AY_STR

; ============================================================================
; Invoerbalk (Y=32..49) & Statusbalk (Y=342..359)
; ============================================================================
DRAW_INPUT_BAR:
        LDX #0
        JSR SEND_RECT_10
        JSR SEND_RECT_10

        LDY #37
        LDA #12
        JSR SET_XY_POS
        LDA #$FC
        STA ZP_FG_COL
        LDA #'$'
        JSR DRAW_CHAR_ADV
        LDA CUR_HI
        JSR DRAW_HEX_BYTE
        LDA CUR_LO
        JSR DRAW_HEX_BYTE

        LDA #66
        STA ZP_X_LO
        LDA #$1F
        STA ZP_FG_COL
        LDX EDIT_MODE
        LDA PROMPT_LO,X
        LDY PROMPT_HI,X
        JSR DRAW_AY_STR

        LDA EDIT_MODE
        BEQ DIB_RTS
        CMP #4
        BEQ DIB_RTS
        LDA #$FF
        STA ZP_FG_COL
        LDA #<EDIT_BUF
        LDY #>EDIT_BUF
        JSR DRAW_AY_STR
        LDA #'_'
        JMP DRAW_CHAR_ADV
DIB_RTS:
        RTS

SHOW_STATUS_MSG:
        CLC
        ADC #<STR_MSG_BASE
        STA ZP_PTR_LO
        LDA #>STR_MSG_BASE
        ADC #0
        STA ZP_PTR_HI
        LDX #60
        JSR SEND_RECT_10
        LDY #$5B
        LDA #12
        JSR SET_XY_POS
        INC ZP_Y_HI
        LDA #$FC
        STA ZP_FG_COL
        JMP DRAW_ZP_STR

; ============================================================================
; Hulproutines voor Hex & GPU Tekst
; ============================================================================
SET_XY_POS:
        STA ZP_X_LO
        STY ZP_Y_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        RTS

DRAW_DOL_DIS_HEX:
        LDA #'$'
        JSR DRAW_CHAR_ADV
DRAW_DIS_HEX:
        LDA DIS_HI
        JSR DRAW_HEX_BYTE
        LDA DIS_LO
DRAW_HEX_BYTE:
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
        ADC #('A' - 10 - 1)
        JMP DRAW_CHAR_ADV
DHN_DIG:
        ADC #'0'
        JMP DRAW_CHAR_ADV

SEND_RECT_10:
        LDY #10
SR10_LP:
        LDA UI_RECT_TBL,X
        STA IO_GPU
        INX
        DEY
        BNE SR10_LP
        RTS

DRAW_AY_STR:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DRAW_ZP_STR:
        JSR NEXT_PTR_BYTE
        BEQ DZS_RTS
        JSR DRAW_CHAR_ADV
        JMP DRAW_ZP_STR
DZS_RTS:
        RTS

NEXT_PTR_BYTE:
        LDY #0
        LDA (ZP_PTR_LO),Y
        INC ZP_PTR_LO
        BNE NPB_RTS
        INC ZP_PTR_HI
NPB_RTS:
        CMP #0
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
        LDA ZP_FG_COL
        STA IO_GPU
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCAD_RTS
        INC ZP_X_HI
DCAD_RTS:
        RTS

RESET_ADDR_3000:
        LDA #$00
        STA CUR_LO
        LDA #$30
        STA CUR_HI
        RTS

CLEAR_USER_MEM:
        LDY #0
        TYA
CUM_LP:
        STA $3000,Y
        STA $3100,Y
        INY
        BNE CUM_LP
        RTS

; ============================================================================
; 3 Ingebouwde Jaren '80 Tijdschrift Machinecode Demo's (Laden op $3000)
; ============================================================================
LOAD_DEMO_IDX:
        PHA
        JSR CLEAR_USER_MEM
        PLA
        TAX
        LDA DEMO_LEN,X
        STA ZP_SAV_X
        LDY DEMO_OFFS,X
        LDX #0
LDI_LP:
        LDA DEMO_BLOBS,Y
        STA $3000,X
        INY
        INX
        CPX ZP_SAV_X
        BCC LDI_LP
        RTS

DEMO_OFFS:
        .BYTE 0, (DEMO2_CODE - DEMO_BLOBS), (DEMO3_CODE - DEMO_BLOBS)
DEMO_LEN:
        .BYTE (DEMO2_CODE - DEMO1_CODE), (DEMO3_CODE - DEMO2_CODE), (DEMO_END - DEMO3_CODE)

DEMO_BLOBS:
; Tijdschrift Demo #1 (Compute! / KIM-1 1983): Druk A..Z en 0..9 af via JSR $FFD2!
DEMO1_CODE:
        .BYTE $A2, $41          ; 3000: LDX #$41 ('A')
        .BYTE $8A               ; 3002: TXA
        .BYTE $20, $D2, $FF     ; 3003: JSR $FFD2 (CHROUT)
        .BYTE $E8               ; 3006: INX
        .BYTE $E0, $5B          ; 3007: CPX #$5B ('Z'+1)
        .BYTE $D0, $F7          ; 3009: BNE $3002
        .BYTE $A9, $20          ; 300B: LDA #$20 (' ')
        .BYTE $20, $D2, $FF     ; 300D: JSR $FFD2
        .BYTE $A2, $30          ; 3010: LDX #$30 ('0')
        .BYTE $8A               ; 3012: TXA
        .BYTE $20, $D2, $FF     ; 3013: JSR $FFD2
        .BYTE $E8               ; 3016: INX
        .BYTE $E0, $3A          ; 3017: CPX #$3A ('9'+1)
        .BYTE $D0, $F7          ; 3019: BNE $3012
        .BYTE $60               ; 301B: RTS

; Tijdschrift Demo #2 (Elektuur 1984): Bereken 13 Fibonacci-getallen in $3020..$302C!
DEMO2_CODE:
        .BYTE $A9, $01          ; 3000: LDA #$01
        .BYTE $8D, $20, $30     ; 3002: STA $3020
        .BYTE $8D, $21, $30     ; 3005: STA $3021
        .BYTE $A2, $00          ; 3008: LDX #$00
        .BYTE $18               ; 300A: CLC
        .BYTE $BD, $20, $30     ; 300B: LDA $3020,X
        .BYTE $7D, $21, $30     ; 300E: ADC $3021,X
        .BYTE $9D, $22, $30     ; 3011: STA $3022,X
        .BYTE $E8               ; 3014: INX
        .BYTE $E0, $0B          ; 3015: CPX #$0B (13 getallen: 1,1,2,3,5,8,13..233)
        .BYTE $D0, $F1          ; 3017: BNE $300A
        .BYTE $A9, $46          ; 3019: LDA #$46 ('F')
        .BYTE $20, $D2, $FF     ; 301B: JSR $FFD2
        .BYTE $60               ; 301E: RTS

; Tijdschrift Demo #3 (Tang Nano 20K Special): Teken 15 GPU Kleur-Blokken via $A020!
DEMO3_CODE:
        .BYTE $A2, $14          ; 3000: LDX #$14 (Start X = 20)
        .BYTE $8E, $1E, $30     ; 3002: STX $301E (Patch X in GPU pakket)
        .BYTE $8E, $26, $30     ; 3005: STX $3026 (Patch Kleur in GPU pakket)
        .BYTE $A0, $00          ; 3008: LDY #$00
        .BYTE $B9, $1D, $30     ; 300A: LDA $301D,Y
        .BYTE $8D, $20, $A0     ; 300D: STA $A020 (Stuur naar MiniGPU!)
        .BYTE $C8               ; 3010: INY
        .BYTE $C0, $0A          ; 3011: CPY #$0A (10 bytes per RECT)
        .BYTE $D0, $F5          ; 3013: BNE $300A
        .BYTE $18, $8A, $69, $10; 3015: CLC / TXA / ADC #$10 (X += 16)
        .BYTE $AA               ; 3019: TAX
        .BYTE $90, $E5          ; 301A: BCC $3002 (Herhaal voor 15 blokken!)
        .BYTE $60               ; 301C: RTS
        .BYTE $02, $14, $00, $2C, $01, $0E, $00, $1C, $00, $14 ; 301D: GPU RECT pakket
DEMO_END:

; ============================================================================
; BSRAM Trampolines ($02D2..$02E2) & Tabellen
; ============================================================================
BSRAM_INIT_TBL:
        JMP MON_CHROUT          ; $02D2: Vangt JSR $FFD2 op
        .BYTE $6C, CUR_LO, $00  ; $02D5: JMP ($0070)
        LDA #1                  ; $02D8: BSRAM_EXIT_MC
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

REG_NAMES:
        .BYTE "AXYS"

MODE_LEN_TBL:
        .BYTE 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 2, 2

PROMPT_LO:
        .BYTE <STR_PR_NAV, <STR_PR_ASM, <STR_PR_HEX, <STR_PR_ADR, <STR_PR_NAV
PROMPT_HI:
        .BYTE >STR_PR_NAV, >STR_PR_ASM, >STR_PR_HEX, >STR_PR_ADR, >STR_PR_NAV

STR_PR_NAV:     .ASCIIZ "A/ENTER:Asm M:Hex G:Run T:Adres ESC:Menu"
STR_PR_ASM:     .ASCIIZ "ASM > "
STR_PR_HEX:     .ASCIIZ "HEX > "
STR_PR_ADR:     .ASCIIZ "ADRES $ > "

GUI_STREAM:
        .BYTE 12, 1                     ; TARGET 1 (frontbuffer)
        .BYTE 2, 0,0, 0,0, $80,$02, 16,0, $10
        .BYTE 2, 0,0, 16,0, $80,$02, 16,0, $B6
        .BYTE 2, 0,0, 50,0, $80,$02, $24,$01, $25
        .BYTE 2, 8,0, 52,0, $5A,$01, 16,0, $14
        .BYTE 2, 8,0, 68,0, $5A,$01, 196,0, $00
        .BYTE 2, $6A,$01, 52,0, $0E,$01, 16,0, $14
        .BYTE 2, $6A,$01, 202,0, $0E,$01, 14,0, $14
        .BYTE 2, $6A,$01, 234,0, $0E,$01, 40,0, $00
        .BYTE 2, 8,0, $18,$01, $70,$02, 14,0, $14
GUI_STREAM_END:

UI_RECT_TBL:
        ; Offset 0: Wis invoerbalk (0, 32, 640, 18, $00)
        .BYTE 2, 0,0, 32,0, $80,$02, 18,0, $00
        ; Offset 10: Groene adres-badge (6, 34, 52, 14, $10)
        .BYTE 2, 6,0, 34,0, 52,0, 14,0, $10
        ; Offset 20: Wis Hex-paneel binnenkant (362, 68, 270, 132, $00)
        .BYTE 2, $6A,$01, 68,0, $0E,$01, 132,0, $00
        ; Offset 30: Wis Register-paneel binnenkant (362, 216, 270, 18, $00)
        .BYTE 2, $6A,$01, 216,0, $0E,$01, 18,0, $00
        ; Offset 40: Disassembler-rij balk (10, Y, 342, 15, COL)
        .BYTE 2, 10,0
DIS_ROW_Y:
        .BYTE 68, 0, $56,$01, 15,0
DIS_ROW_COL:
        .BYTE $00
        ; Offset 50: Wis Uitvoer-paneel binnenkant (8, 294, 624, 42, $00)
        .BYTE 2, 8,0, $26,$01, $70,$02, 42,0, $00
        ; Offset 60: Wis Statusbalk (0, 342, 640, 18, $10)
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $10
        ; Offset 70..99: ESC Popup-venster (Rand + Zwart vlak + Gele titelbalk)
        .BYTE 2, 146,0, 86,0, 92,1, 148,0, $1F
        .BYTE 2, 148,0, 88,0, 88,1, 144,0, $00
        .BYTE 2, 148,0, 88,0, 88,1, 18,0, $FC

STR_HEADERS:
        .BYTE 12,0, 4, $FF, "MiniGPU MON6502 - 6502 Assembler, Disassembler & Hex-Monitor", 0
        .BYTE 12,0, 20, $00, "PIJL:Scroll A/ENTER:Asm M:Hex G:Run T:Adres 1-3:Demo ESC:Menu", 0
        .BYTE 14,0, 56, $FC, "6502 DISASSEMBLER / ASSEMBLER", 0
        .BYTE $70,$01, 56, $FC, "HEX-DUMP + CHECKSUM", 0
        .BYTE $70,$01, 205, $FC, "6502 CPU REGISTERS", 0
        .BYTE $72,$01, 238, $1F, "$FFD2=CHROUT  $A001=TERM", 0
        .BYTE $72,$01, 252, $B6, "$A005=RANDOM  $A020=GPU", 0
        .BYTE 14,0, 283, $FC, "UITVOER ($FFD2 CHROUT / MINIGPU)", 0
        .BYTE 0

STR_POPUP_MENU:
        .BYTE 164,0, 93,  $00, "== MON6502 TIJDSCHRIFT MENU ==", 0
        .BYTE 164,0, 114, $FF, "[1] Demo 1: ASCII ($FFD2)", 0
        .BYTE 164,0, 130, $FF, "[2] Demo 2: Fibonacci ($3020)", 0
        .BYTE 164,0, 146, $FF, "[3] Demo 3: MiniGPU Balken", 0
        .BYTE 164,0, 162, $FF, "[4/N] Nieuw Leeg ($3000)", 0
        .BYTE 164,0, 178, $FF, "[5/S] Opslaan  [6/L] Laden SD", 0
        .BYTE 164,0, 202, $1F, "[SPAT] Sluit   [ESC/Q] Uit", 0
        .BYTE 0

STR_MSG_BASE:
STR_MSG_READY:  .ASCIIZ "MON6502 GEREED ($3000)"
STR_MSG_EDIT:   .ASCIIZ "TYP CODE/HEX + ENTER"
STR_MSG_ASMD:   .ASCIIZ "OK! TYP VOLGENDE REGEL"
STR_MSG_RAN:    .ASCIIZ "CODE UITGEVOERD (RTS)!"
STR_MSG_CANCEL: .ASCIIZ "GEANNULEERD"
STR_MSG_ERR:    .ASCIIZ "SYNTAX / BRANCH FOUT!"
STR_MSG_SAVED:  .ASCIIZ "OPGESLAGEN OP SD!"

MNEM_C0: ; Eerste letter van de 57 mnemonics
        .BYTE $41, $41, $41, $42, $42, $42, $42, $42, $42, $42, $42, $42, $42, $43, $43, $43
        .BYTE $43, $43, $43, $43, $44, $44, $44, $45, $49, $49, $49, $4A, $4A, $4C, $4C, $4C
        .BYTE $4C, $4E, $4F, $50, $50, $50, $50, $52, $52, $52, $52, $53, $53, $53, $53, $53
        .BYTE $53, $53, $54, $54, $54, $54, $54, $54, $3F
MNEM_C1: ; Tweede letter van de 57 mnemonics
        .BYTE $44, $4E, $53, $43, $43, $45, $49, $4D, $4E, $50, $52, $56, $56, $4C, $4C, $4C
        .BYTE $4C, $4D, $50, $50, $45, $45, $45, $4F, $4E, $4E, $4E, $4D, $53, $44, $44, $44
        .BYTE $53, $4F, $52, $48, $48, $4C, $4C, $4F, $4F, $54, $54, $42, $45, $45, $45, $54
        .BYTE $54, $54, $41, $41, $53, $58, $58, $59, $3F
MNEM_C2: ; Derde letter van de 57 mnemonics
        .BYTE $43, $44, $4C, $43, $53, $51, $54, $49, $45, $4C, $4B, $43, $53, $43, $44, $49
        .BYTE $56, $50, $58, $59, $43, $58, $59, $52, $43, $58, $59, $50, $52, $41, $58, $59
        .BYTE $52, $50, $41, $41, $50, $41, $50, $4C, $52, $49, $53, $43, $43, $44, $49, $41
        .BYTE $58, $59, $58, $59, $58, $41, $53, $41, $3F
OPC_MNEM: ; Mnemonic-index (0..56) voor elke opcode $00..$FF
        .BYTE $0A, $22, $38, $38, $38, $22, $02, $38, $24, $22, $02, $38, $38, $22, $02, $38
        .BYTE $09, $22, $38, $38, $38, $22, $02, $38, $0D, $22, $38, $38, $38, $22, $02, $38
        .BYTE $1C, $01, $38, $38, $06, $01, $27, $38, $26, $01, $27, $38, $06, $01, $27, $38
        .BYTE $07, $01, $38, $38, $38, $01, $27, $38, $2C, $01, $38, $38, $38, $01, $27, $38
        .BYTE $29, $17, $38, $38, $38, $17, $20, $38, $23, $17, $20, $38, $1B, $17, $20, $38
        .BYTE $0B, $17, $38, $38, $38, $17, $20, $38, $0F, $17, $38, $38, $38, $17, $20, $38
        .BYTE $2A, $00, $38, $38, $38, $00, $28, $38, $25, $00, $28, $38, $1B, $00, $28, $38
        .BYTE $0C, $00, $38, $38, $38, $00, $28, $38, $2E, $00, $38, $38, $38, $00, $28, $38
        .BYTE $38, $2F, $38, $38, $31, $2F, $30, $38, $16, $38, $35, $38, $31, $2F, $30, $38
        .BYTE $03, $2F, $38, $38, $31, $2F, $30, $38, $37, $2F, $36, $38, $38, $2F, $38, $38
        .BYTE $1F, $1D, $1E, $38, $1F, $1D, $1E, $38, $33, $1D, $32, $38, $1F, $1D, $1E, $38
        .BYTE $04, $1D, $38, $38, $1F, $1D, $1E, $38, $10, $1D, $34, $38, $1F, $1D, $1E, $38
        .BYTE $13, $11, $38, $38, $13, $11, $14, $38, $1A, $11, $15, $38, $13, $11, $14, $38
        .BYTE $08, $11, $38, $38, $38, $11, $14, $38, $0E, $11, $38, $38, $38, $11, $14, $38
        .BYTE $12, $2B, $38, $38, $12, $2B, $18, $38, $19, $2B, $21, $38, $12, $2B, $18, $38
        .BYTE $05, $2B, $38, $38, $38, $2B, $18, $38, $2D, $2B, $38, $38, $38, $2B, $18, $38
OPC_MODE_NIB: ; 4-bit Adresseringsmodus (0..12) per opcode (2 per byte)
        .BYTE $B0, $00, $30, $03, $20, $01, $70, $07, $C6, $00, $40, $04, $90, $00, $80, $08
        .BYTE $B7, $00, $33, $03, $20, $01, $77, $07, $C6, $00, $40, $04, $90, $00, $80, $08
        .BYTE $B0, $00, $30, $03, $20, $01, $77, $07, $C6, $00, $40, $04, $90, $00, $80, $08
        .BYTE $B0, $00, $30, $03, $20, $01, $7A, $07, $C6, $00, $40, $04, $90, $00, $80, $08
        .BYTE $B0, $00, $33, $03, $00, $00, $77, $07, $C6, $00, $44, $05, $90, $00, $80, $00
        .BYTE $B2, $02, $33, $03, $20, $00, $77, $07, $C6, $00, $44, $05, $90, $00, $88, $09
        .BYTE $B2, $00, $33, $03, $20, $00, $77, $07, $C6, $00, $40, $04, $90, $00, $80, $08
        .BYTE $B2, $00, $33, $03, $20, $00, $77, $07, $C6, $00, $40, $04, $90, $00, $80, $08
