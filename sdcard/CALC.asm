; ============================================================================
; CALC.asm - LibreCalc / Excel 6502 (Spreadsheet & Live Grafiek voor MiniGPU)
; Geassembleerd op $8000 in SDRAM. Spreadsheet-geheugen (5x10) op $7800-$7CFF.
; Ondersteunt getallen, tekst, formules (=A1+B1, =D2*2, =SUM(B2:B7), =AVG(B2:B7))
; én een live schalende Staafdiagram / Grafiek aan de rechterkant!
; Starten vanuit Midnight Commander (BRUN MC) of via: BRUN CALC
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- ROM Routines voor SD-Kaart Opslag (Sectors $03FC..$03FE) ---
ZP_DST          = $1C
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA

; --- Eigen Zero Page Variabelen ($60..$8F) ---
ZP_CELL_LO      = $60           ; Pointer naar huidige cel (16 bytes per cel in $7800)
ZP_CELL_HI      = $61
ZP_PTR_LO       = $62           ; Algemene 16-bit pointer
ZP_PTR_HI       = $63
ZP_X_LO         = $64           ; 16-bit GPU X
ZP_X_HI         = $65
ZP_Y_LO         = $66           ; 16-bit GPU Y
ZP_Y_HI         = $67
ZP_FG_COL       = $68
ZP_BG_COL       = $69

CUR_COL         = $6A           ; Geselecteerde kolom (0..4 = A..E)
CUR_ROW         = $6B           ; Geselecteerde rij (0..9 = 1..10)
OLD_COL         = $6C
OLD_ROW         = $6D
EDIT_MODE       = $6E           ; 0 = Navigatie, 1 = Formulebalk bewerken, 2 = ESC-Menu
EDIT_LEN        = $6F           ; Lengte in EDIT_BUF (0..11)
CHART_COL       = $70           ; Kolom (1..4 = B..E) die in de Live Grafiek getoond wordt
PREV_JOY        = $71

; Reken-registers voor 16-bit Formule-Evaluator
ACC_LO          = $72
ACC_HI          = $73
OP_LO           = $74
OP_HI           = $75
MUL_LO          = $76
MUL_HI          = $77
SIGN_FLG        = $78
F_IDX           = $79           ; Parse-index in cel-string
CUR_OP          = $7A           ; Huidige operator ('+', '-', '*', '/')
R_COL1          = $7B           ; Range start/eind voor SUM/AVG
R_ROW1          = $7C
R_COL2          = $7D
R_ROW2          = $7E
CNT_CELLS       = $7F

ZP_ITER_R       = $80
ZP_ITER_C       = $81
ZP_SAV_X        = $82
ZP_SAV_Y        = $83
MAX_VAL_LO      = $84           ; Maximum waarde voor automatische grafiek-schaal
MAX_VAL_HI      = $85
BAR_H           = $86           ; Berekende staafhoogte (0..180 px)

EDIT_BUF        = $0280         ; 16-byte invoerbuffer tijdens bewerken van een cel
NUM_STR_BUF     = $0290         ; Tijdelijke buffer voor rechts-uitgelijnde getallen

SHEET_RAM       = $7800         ; 10 rijen x 128 bytes ($7800..$7CFF)
SHEET_MAGIC     = $7CFF         ; $5A als spreadsheet al in geheugen geladen is
NUM_COLS        = 5             ; Kolommen A..E
NUM_ROWS        = 10            ; Rijen 1..10

; ============================================================================
; Startpunt ($8000)
; ============================================================================
START:
        LDA #12
        STA IO_TERM
        LDA #0
        STA IO_MODE
        STA EDIT_MODE
        LDA #1                  ; Start op cel B2 (col=1, row=1)
        STA CUR_COL
        STA CUR_ROW
        STA OLD_COL
        STA OLD_ROW
        LDA #3                  ; Standaard Grafiek op Kolom D (col=3 = HALFJAAR)
        STA CHART_COL

        JSR INIT_GPU

        ; Controleer of het rekenblad al in SDRAM ($7800) staat
        LDA SHEET_MAGIC
        CMP #$5A
        BEQ SHEET_READY
        JSR LOAD_DEMO_SHEET
SHEET_READY:
        JSR RECALC_ALL
        JSR FULL_REDRAW
        LDA #<STR_MSG_READY
        LDY #>STR_MSG_READY
        JSR SHOW_STATUS_MSG

        LDA IO_JOY
        STA PREV_JOY

; ============================================================================
; Hoofdlus: Invoer & Navigatie
; ============================================================================
MAIN_LOOP:
        LDA #1
        JSR WAIT_10MS

        ; 1. Check of op ESC is gedrukt (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_NAV_JOY
        LDA IO_TERM             ; Lees en wis ESC ($1B)
        LDA EDIT_MODE
        CMP #1
        BEQ CANCEL_CELL_EDIT
        CMP #2
        BEQ EXIT_TO_MC          ; Nogmaals ESC in het menu = Terug naar MC!
        JSR OPEN_ESC_MENU
        JMP MAIN_LOOP

CANCEL_CELL_EDIT:
        LDA #0
        STA EDIT_MODE
        JSR DRAW_FORMULA_BAR
        LDA #<STR_MSG_CANCEL
        LDY #>STR_MSG_CANCEL
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

EXIT_TO_MC:
        JSR ROM_SILENCE
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

CHK_NAV_JOY:
        ; 2. In Navigatie-modus (EDIT_MODE == 0): ondersteun PS/2 Pijltjes, WASD & TAB!
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

        ; Als richting of TAB via IO_JOY binnenkwam, wis eventuele echo in IO_TERM
        TYA
        AND #$40                ; Bit 6 = TAB -> Wissel Grafiek-kolom (B/C/D/E)!
        BNE DO_CYCLE_CHART

        LDA IO_TERM             ; Wis bijbehorende pijl/WASD karakter uit IO_TERM
        TYA
        AND #1                  ; Omhoog
        BNE MOVE_CELL_UP
        TYA
        AND #2                  ; Omlaag
        BNE MOVE_CELL_DOWN
        TYA
        AND #4                  ; Links
        BNE MOVE_CELL_LEFT
        TYA
        AND #8                  ; Rechts
        BNE MOVE_CELL_RIGHT
        JMP MAIN_LOOP

DO_CYCLE_CHART:
        JSR CYCLE_CHART_COL
        JMP MAIN_LOOP

MOVE_CELL_UP:
        JSR SAVE_OLD_RC
        LDA CUR_ROW
        BEQ MCU_WRAP
        DEC CUR_ROW
        JMP UPDATE_SELECTION
MCU_WRAP:
        LDA #(NUM_ROWS - 1)
        STA CUR_ROW
        JMP UPDATE_SELECTION

MOVE_CELL_DOWN:
        JSR SAVE_OLD_RC
        LDA CUR_ROW
        CMP #(NUM_ROWS - 1)
        BCS MCD_WRAP
        INC CUR_ROW
        JMP UPDATE_SELECTION
MCD_WRAP:
        LDA #0
        STA CUR_ROW
        JMP UPDATE_SELECTION

MOVE_CELL_LEFT:
        JSR SAVE_OLD_RC
        LDA CUR_COL
        BEQ MCL_WRAP
        DEC CUR_COL
        JMP UPDATE_SELECTION
MCL_WRAP:
        LDA #(NUM_COLS - 1)
        STA CUR_COL
        JMP UPDATE_SELECTION

MOVE_CELL_RIGHT:
        JSR SAVE_OLD_RC
        LDA CUR_COL
        CMP #(NUM_COLS - 1)
        BCS MCR_WRAP
        INC CUR_COL
        JMP UPDATE_SELECTION
MCR_WRAP:
        LDA #0
        STA CUR_COL
        JMP UPDATE_SELECTION

SAVE_OLD_RC:
        LDA CUR_COL
        STA OLD_COL
        LDA CUR_ROW
        STA OLD_ROW
        RTS

UPDATE_SELECTION:
        ; Herteken alleen de oude cel en de nieuwe geselecteerde cel (< 0.5 ms!)
        LDX OLD_COL
        LDA OLD_ROW
        JSR DRAW_ONE_CELL
        LDX CUR_COL
        LDA CUR_ROW
        JSR DRAW_ONE_CELL
        JSR DRAW_FORMULA_BAR
        JSR UPDATE_STATUS_BAR
        JMP MAIN_LOOP

CHK_TERM_CHAR:
        LDA IO_STATUS
        AND #1
        BEQ MAIN_LOOP_JMP
        LDA IO_TERM
        STA ZP_SAV_Y
        LDA IO_JOY
        STA PREV_JOY

        LDA EDIT_MODE
        BEQ NAV_KEY_HANDLER
        CMP #1
        BEQ EDIT_KEY_HANDLER
        JMP MENU_KEY_HANDLER
MAIN_LOOP_JMP:
        JMP MAIN_LOOP

; ============================================================================
; Toetsen in Navigatie-Modus (EDIT_MODE == 0)
; ============================================================================
NAV_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #$0D                ; Enter = Bewerk huidige cel
        BEQ START_EDIT_EMPTY
        CMP #$08                ; Backspace = Wis huidige cel
        BEQ DO_CLEAR_CELL
        CMP #$7F
        BEQ DO_CLEAR_CELL
        CMP #'`'                ; ` of G = Wissel Grafiek-kolom
        BEQ DO_CYCLE_CHART

        ; Check sneltoetsen G (Grafiek), C (Clear), Q (Quit) of direct intypen van = / cijfer!
        CMP #'='
        BEQ START_EDIT_WITH_CHAR
        CMP #'-'
        BEQ START_EDIT_WITH_CHAR
        CMP #'0'
        BCC NK_LETTERS
        CMP #':'
        BCC START_EDIT_WITH_CHAR

NK_LETTERS:
        AND #$DF
        CMP #'G'
        BEQ DO_CYCLE_CHART
        CMP #'C'
        BEQ DO_CLEAR_CELL
        CMP #'E'
        BEQ START_EDIT_EMPTY
        JMP MAIN_LOOP

DO_CLEAR_CELL:
        LDX CUR_COL
        LDA CUR_ROW
        JSR GET_CELL_PTR
        LDY #0
        LDA #0
        STA (ZP_CELL_LO),Y
        JMP RECALC_AND_REDRAW

START_EDIT_EMPTY:
        LDA #0
        STA EDIT_LEN
        STA EDIT_BUF
        JMP FINISH_EDIT_INIT

START_EDIT_WITH_CHAR:
        LDA ZP_SAV_Y
        STA EDIT_BUF
        LDA #0
        STA EDIT_BUF+1
        LDA #1
        STA EDIT_LEN
FINISH_EDIT_INIT:
        LDA #1
        STA EDIT_MODE
        JSR DRAW_FORMULA_BAR
        LDA #<STR_MSG_EDIT
        LDY #>STR_MSG_EDIT
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; ============================================================================
; Toetsen tijdens Formulebalk Bewerken (EDIT_MODE == 1)
; ============================================================================
EDIT_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #$0D                ; Enter = Sla cel op & Herbereken alles!
        BEQ COMMIT_CELL_EDIT
        CMP #$08                ; Backspace
        BEQ EDIT_BACKSPACE
        CMP #$7F
        BEQ EDIT_BACKSPACE
        CMP #$20
        BCC EKH_DONE
        CMP #$7F
        BCS EKH_DONE

        ; Voeg karakter toe aan EDIT_BUF (max 11 tekens)
        LDX EDIT_LEN
        CPX #11
        BCS EKH_DONE
        ; Maak kleine letters automatisch hoofdletters voor cel-referenties (a1 -> A1, sum -> SUM)
        CMP #'a'
        BCC EKH_STORE
        CMP #('z' + 1)
        BCS EKH_STORE
        SEC
        SBC #$20
EKH_STORE:
        STA EDIT_BUF,X
        INX
        STX EDIT_LEN
        LDA #0
        STA EDIT_BUF,X
        JSR DRAW_FORMULA_BAR
EKH_DONE:
        JMP MAIN_LOOP

EDIT_BACKSPACE:
        LDX EDIT_LEN
        BEQ EKH_DONE
        DEX
        STX EDIT_LEN
        LDA #0
        STA EDIT_BUF,X
        JSR DRAW_FORMULA_BAR
        JMP MAIN_LOOP

COMMIT_CELL_EDIT:
        ; Kopieer EDIT_BUF naar huidige cel in SHEET_RAM
        LDX CUR_COL
        LDA CUR_ROW
        JSR GET_CELL_PTR
        LDY #0
CCE_CP:
        LDA EDIT_BUF,Y
        STA (ZP_CELL_LO),Y
        BEQ RECALC_AND_REDRAW
        INY
        CPY #11
        BCC CCE_CP
        LDA #0
        STA (ZP_CELL_LO),Y
RECALC_AND_REDRAW:
        LDA #0
        STA EDIT_MODE
        ; Herbereken alle 50 cellen én werk tabel + live grafiek bij!
        JSR RECALC_ALL
        JSR REDRAW_ALL_CELLS
        JSR DRAW_CHART_PANEL
        JSR DRAW_FORMULA_BAR
        JSR UPDATE_STATUS_BAR
        LDA #<STR_MSG_OK
        LDY #>STR_MSG_OK
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; ============================================================================
; Top Menu Balk (geopend met ESC)
; ============================================================================
OPEN_ESC_MENU:
        LDA #2
        STA EDIT_MODE
        LDX #0                  ; Rect 0: Gele menubalk (0, 16, 640, 16, $FC)
        JSR SEND_RECT_10
        LDA #<STR_ESC_MENU
        LDY #>STR_ESC_MENU
        JMP DRAW_BAR_TEXT

CLOSE_ESC_MENU:
        LDA #0
        STA EDIT_MODE
        JSR DRAW_TOOLBAR
        LDA #<STR_MSG_READY
        LDY #>STR_MSG_READY
        JMP SHOW_STATUS_MSG

MENU_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #' '
        BEQ CEM_JMP
        CMP #$0D
        BEQ CEM_JMP
        CMP #'1'
        BEQ MENU_NEW_SHEET
        CMP #'2'
        BEQ MENU_DEMO_SHEET
        CMP #'3'
        BEQ MENU_SAVE_SHEET
        CMP #'4'
        BEQ MENU_LOAD_SHEET
        CMP #'5'
        BEQ MENU_CHART_COL

        AND #$DF
        CMP #'Q'
        BNE MKH_1
        JMP EXIT_TO_MC
MKH_1:  CMP #'N'
        BEQ MENU_NEW_SHEET
        CMP #'D'
        BEQ MENU_DEMO_SHEET
        CMP #'S'
        BEQ MENU_SAVE_SHEET
        CMP #'L'
        BEQ MENU_LOAD_SHEET
        CMP #'G'
        BEQ MENU_CHART_COL
        JMP MAIN_LOOP

CEM_JMP:
        JSR CLOSE_ESC_MENU
        JMP MAIN_LOOP

MENU_CHART_COL:
        JSR CLOSE_ESC_MENU
        JSR CYCLE_CHART_COL
        JMP MAIN_LOOP

MENU_NEW_SHEET:
        JSR CLEAR_ALL_CELLS
        JMP FINISH_SHEET_LOAD

MENU_DEMO_SHEET:
        JSR LOAD_DEMO_SHEET
        JMP FINISH_SHEET_LOAD

MENU_SAVE_SHEET:
        JSR CLOSE_ESC_MENU
        JSR SAVE_SHEET_SD
        LDA #<STR_MSG_SAVED
        LDY #>STR_MSG_SAVED
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

MENU_LOAD_SHEET:
        JSR LOAD_SHEET_SD
FINISH_SHEET_LOAD:
        LDA #0
        STA EDIT_MODE
        JSR RECALC_ALL
        JSR FULL_REDRAW
        LDA #<STR_MSG_OK
        LDY #>STR_MSG_OK
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

CYCLE_CHART_COL:
        INC CHART_COL
        LDA CHART_COL
        CMP #NUM_COLS
        BCC CCC_OK
        LDA #1                  ; Kolom B..E (1..4)
        STA CHART_COL
CCC_OK:
        JMP DRAW_CHART_PANEL

; ============================================================================
; SD-Kaart Opslag & Laden (Sectors $03FC..$03FE = 1.5 KB voor $7800..$7DFF)
; ============================================================================
PREP_SHEET_SD:
        JSR ROM_SD_INIT
        LDA #$FC
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDA #$00
        STA ZP_DST
        LDA #$78
        STA ZP_DST+1
        LDX #3
        RTS

SAVE_SHEET_SD:
        JSR PREP_SHEET_SD
SSS_LP:
        TXA
        PHA
        JSR ROM_WRITE_SEC
        PLA
        TAX
        DEX
        BNE SSS_LP
        RTS

LOAD_SHEET_SD:
        JSR PREP_SHEET_SD
LSS_LP:
        TXA
        PHA
        JSR ROM_READ_SEC
        PLA
        TAX
        DEX
        BNE LSS_LP
        LDA SHEET_MAGIC
        CMP #$5A
        BEQ LSS_OK
        JMP LOAD_DEMO_SHEET
LSS_OK:
        RTS

; ============================================================================
; 16-Bit Spreadsheet Formule-Evaluator & Herberekening (RECALC_ALL)
; ============================================================================
RECALC_ALL:
        ; Voer 2 evaluatie-rondes uit zodat ketting-formules (bijv. E2 = D2*2 en D9 = SUM(D2:D7)) kloppen!
        JSR RECALC_PASS
        JMP RECALC_PASS

RECALC_PASS:
        LDA #0
        STA ZP_ITER_R
RP_ROW:
        LDA #0
        STA ZP_ITER_C
RP_COL:
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR GET_CELL_PTR
        JSR EVAL_CURRENT_CELL
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #NUM_COLS
        BCC RP_COL
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #NUM_ROWS
        BCC RP_ROW
        RTS

; Evalueer de cel waar ZP_CELL_LO/HI naar wijst; zet CELL_TYPE (offset 12) en VAL (offset 14..15)
EVAL_CURRENT_CELL:
        LDY #0
        LDA (ZP_CELL_LO),Y
        BNE ECC_NON_EMPTY
        ; Lege cel -> type 0, waarde 0
        LDY #12
        STA (ZP_CELL_LO),Y
        LDY #14
        STA (ZP_CELL_LO),Y
        INY
        STA (ZP_CELL_LO),Y
        RTS

ECC_NON_EMPTY:
        CMP #'='
        BEQ ECC_IS_FORMULA

        ; Check of de cel begint met een cijfer ('0'..'9') of '-'
        CMP #'-'
        BEQ ECC_CHK_NEG_NUM
        JSR IS_CHAR_DIGIT
        BCS ECC_IS_NUMBER
ECC_IS_TEXT:
        LDY #12
        LDA #1                  ; Type 1 = Tekstlabel
        STA (ZP_CELL_LO),Y
        LDA #0
        LDY #14
        STA (ZP_CELL_LO),Y
        INY
        STA (ZP_CELL_LO),Y
        RTS

ECC_CHK_NEG_NUM:
        LDY #1
        LDA (ZP_CELL_LO),Y
        JSR IS_CHAR_DIGIT
        BCC ECC_IS_TEXT

ECC_IS_NUMBER:
        LDY #12
        LDA #2                  ; Type 2 = Getal
        STA (ZP_CELL_LO),Y
        LDA #0
        STA F_IDX
        JSR PARSE_TERM_AT_FIDX
        JMP STORE_ACC_TO_CELL

ECC_IS_FORMULA:
        LDY #12
        LDA #3                  ; Type 3 = Formule!
        STA (ZP_CELL_LO),Y
        LDA #1
        STA F_IDX

        ; Check of de formule begint met SUM( / SOM( of AVG( / GEM(
        LDY #1
        LDA (ZP_CELL_LO),Y
        CMP #'S'
        BEQ ECC_DO_SUM
        CMP #'A'
        BEQ ECC_DO_AVG
        CMP #'G'
        BEQ ECC_DO_AVG

        ; Anders: Rekenkundige expressie met ketting van +, -, *, / (bijv. =B2+C2 of =D2*2)
        JSR PARSE_TERM_AT_FIDX
ECC_EXPR_LP:
        LDY F_IDX
        LDA (ZP_CELL_LO),Y
        BEQ STORE_ACC_TO_CELL
        STA CUR_OP
        INC F_IDX
        ; Bewaar huidige ACC op stack terwijl we de volgende term parsen
        LDA ACC_LO
        PHA
        LDA ACC_HI
        PHA
        LDA CUR_OP
        PHA
        JSR PARSE_TERM_AT_FIDX
        LDA ACC_LO
        STA OP_LO
        LDA ACC_HI
        STA OP_HI
        PLA
        STA CUR_OP
        PLA
        STA ACC_HI
        PLA
        STA ACC_LO
        JSR APPLY_BINARY_OP
        JMP ECC_EXPR_LP

STORE_ACC_TO_CELL:
        LDY #14
        LDA ACC_LO
        STA (ZP_CELL_LO),Y
        INY
        LDA ACC_HI
        STA (ZP_CELL_LO),Y
        RTS

; Bereken =SUM(B2:B7) of =AVG(B2:B7)
ECC_DO_SUM:
        LDA #0
        JMP ECC_RANGE_FUNC
ECC_DO_AVG:
        LDA #1
ECC_RANGE_FUNC:
        STA CUR_OP              ; 0 = SUM, 1 = AVG
        ; Zoek openingshaakje '(' (meestal op offset 4)
        LDA #5
        STA F_IDX
        JSR PARSE_CELL_REF
        STX R_COL1
        STA R_ROW1
        ; Sla ':' over
        INC F_IDX
        JSR PARSE_CELL_REF
        STX R_COL2
        STA R_ROW2

        ; Bewaar ZP_CELL_LO/HI op stack tijdens sommatie
        LDA ZP_CELL_LO
        PHA
        LDA ZP_CELL_HI
        PHA

        LDA #0
        STA ACC_LO
        STA ACC_HI
        STA CNT_CELLS

        LDA R_ROW1
        STA R_ROW1
ERF_R_LP:
        LDA R_ROW1
        CMP #NUM_ROWS
        BCS ERF_DONE_LP
        CMP R_ROW2
        BEQ ERF_C_INIT
        BCS ERF_DONE_LP
ERF_C_INIT:
        LDA R_COL1
        STA R_COL1
        STA ZP_SAV_X
ERF_C_LP:
        LDX ZP_SAV_X
        CPX #NUM_COLS
        BCS ERF_NXT_R
        CPX R_COL2
        BEQ ERF_DO_ADD
        BCS ERF_NXT_R
ERF_DO_ADD:
        LDA R_ROW1
        JSR GET_CELL_PTR
        CLC
        LDY #14
        LDA ACC_LO
        ADC (ZP_CELL_LO),Y
        STA ACC_LO
        INY
        LDA ACC_HI
        ADC (ZP_CELL_LO),Y
        STA ACC_HI
        INC CNT_CELLS
        INC ZP_SAV_X
        JMP ERF_C_LP
ERF_NXT_R:
        INC R_ROW1
        JMP ERF_R_LP

ERF_DONE_LP:
        PLA
        STA ZP_CELL_HI
        PLA
        STA ZP_CELL_LO

        ; Als CUR_OP == 1 (AVG): deel ACC door CNT_CELLS!
        LDA CUR_OP
        BEQ STORE_ACC_TO_CELL
        LDA CNT_CELLS
        BEQ STORE_ACC_TO_CELL
        STA OP_LO
        LDA #0
        STA OP_HI
        JSR DIV16_SIGNED
        JMP STORE_ACC_TO_CELL

; Parse één term (getal of cel-referentie A1..E10) vanaf F_IDX in (ZP_CELL_LO) -> resultaat in ACC_LO/HI
PARSE_TERM_AT_FIDX:
        LDA #0
        STA ACC_LO
        STA ACC_HI
        STA SIGN_FLG
        LDY F_IDX
        LDA (ZP_CELL_LO),Y
        CMP #'-'
        BNE PTA_CHK_REF
        LDA #1
        STA SIGN_FLG
        INC F_IDX
        INY
        LDA (ZP_CELL_LO),Y

PTA_CHK_REF:
        ; Is het een cel-kolom 'A'..'E'?
        CMP #'A'
        BCC PTA_NUM_LP
        CMP #('E' + 1)
        BCS PTA_NUM_LP

        ; Ja! Parse cel-referentie (bijv. B2 of D10) en haal de waarde op
        JSR PARSE_CELL_REF
        PHA
        LDA ZP_CELL_LO
        STA ZP_PTR_LO
        LDA ZP_CELL_HI
        STA ZP_PTR_HI
        PLA
        JSR GET_CELL_PTR
        LDY #14
        LDA (ZP_CELL_LO),Y
        STA ACC_LO
        INY
        LDA (ZP_CELL_LO),Y
        STA ACC_HI
        LDA ZP_PTR_LO
        STA ZP_CELL_LO
        LDA ZP_PTR_HI
        STA ZP_CELL_HI
        JMP PTA_APPLY_SIGN

PTA_NUM_LP:
        LDY F_IDX
        LDA (ZP_CELL_LO),Y
        JSR IS_CHAR_DIGIT
        BCC PTA_APPLY_SIGN
        SEC
        SBC #'0'
        PHA
        ; ACC = ACC * 10 + digit
        ASL ACC_LO
        ROL ACC_HI              ; ACC * 2
        LDA ACC_LO
        STA OP_LO
        LDA ACC_HI
        STA OP_HI               ; OP = ACC * 2
        ASL ACC_LO
        ROL ACC_HI              ; ACC * 4
        ASL ACC_LO
        ROL ACC_HI              ; ACC * 8
        CLC
        LDA ACC_LO
        ADC OP_LO
        STA ACC_LO
        LDA ACC_HI
        ADC OP_HI
        STA ACC_HI              ; ACC * 10
        PLA
        CLC
        ADC ACC_LO
        STA ACC_LO
        BCC PTA_N1
        INC ACC_HI
PTA_N1:
        INC F_IDX
        JMP PTA_NUM_LP

PTA_APPLY_SIGN:
        LDA SIGN_FLG
        BEQ PTA_RTS
        SEC
        LDA #0
        SBC ACC_LO
        STA ACC_LO
        LDA #0
        SBC ACC_HI
        STA ACC_HI
PTA_RTS:
        RTS

; Parse cel-referentie op F_IDX -> X = col (0..4), A = row (0..9)
PARSE_CELL_REF:
        LDY F_IDX
        LDA (ZP_CELL_LO),Y
        SEC
        SBC #'A'
        CMP #NUM_COLS
        BCC PCR_C_OK
        LDA #0
PCR_C_OK:
        TAX
        INC F_IDX
        LDY F_IDX
        LDA (ZP_CELL_LO),Y
        SEC
        SBC #'1'
        CMP #9
        BCC PCR_R_OK
        LDA #0
PCR_R_OK:
        STA OP_LO
        INC F_IDX
        ; Check of er nog een '0' achter staat (rij 10 = index 9!)
        LDY F_IDX
        LDA (ZP_CELL_LO),Y
        CMP #'0'
        BNE PCR_DONE
        INC F_IDX
        LDA #9
        RTS
PCR_DONE:
        LDA OP_LO
        RTS

; Voer CUR_OP ('+', '-', '*', '/') uit op ACC en OP -> resultaat in ACC
APPLY_BINARY_OP:
        LDA CUR_OP
        CMP #'+'
        BNE ABO_SUB
        CLC
        LDA ACC_LO
        ADC OP_LO
        STA ACC_LO
        LDA ACC_HI
        ADC OP_HI
        STA ACC_HI
        RTS
ABO_SUB:
        CMP #'-'
        BNE ABO_MUL
        SEC
        LDA ACC_LO
        SBC OP_LO
        STA ACC_LO
        LDA ACC_HI
        SBC OP_HI
        STA ACC_HI
        RTS
ABO_MUL:
        CMP #'*'
        BNE ABO_DIV
        JMP MUL16_SIGNED
ABO_DIV:
        CMP #'/'
        BNE ABO_RTS
        JMP DIV16_SIGNED
ABO_RTS:
        RTS

MUL16_SIGNED:
        LDA #0
        STA MUL_LO
        STA MUL_HI
        LDX #16
M16_LP:
        LSR OP_HI
        ROR OP_LO
        BCC M16_NXT
        CLC
        LDA MUL_LO
        ADC ACC_LO
        STA MUL_LO
        LDA MUL_HI
        ADC ACC_HI
        STA MUL_HI
M16_NXT:
        ASL ACC_LO
        ROL ACC_HI
        DEX
        BNE M16_LP
        LDA MUL_LO
        STA ACC_LO
        LDA MUL_HI
        STA ACC_HI
        RTS

DIV16_SIGNED:
        ; Check deling door 0
        LDA OP_LO
        ORA OP_HI
        BEQ D16_ZERO
        LDA ACC_HI
        EOR OP_HI
        STA SIGN_FLG
        LDA ACC_HI
        BPL D16_A_POS
        SEC
        LDA #0
        SBC ACC_LO
        STA ACC_LO
        LDA #0
        SBC ACC_HI
        STA ACC_HI
D16_A_POS:
        LDA OP_HI
        BPL D16_O_POS
        SEC
        LDA #0
        SBC OP_LO
        STA OP_LO
        LDA #0
        SBC OP_HI
        STA OP_HI
D16_O_POS:
        LDA #0
        STA MUL_LO
        STA MUL_HI
        LDX #16
D16_LP:
        ASL ACC_LO
        ROL ACC_HI
        ROL MUL_LO
        ROL MUL_HI
        LDA MUL_LO
        CMP OP_LO
        LDA MUL_HI
        SBC OP_HI
        BCC D16_NO_SUB
        LDA MUL_LO
        SBC OP_LO
        STA MUL_LO
        LDA MUL_HI
        SBC OP_HI
        STA MUL_HI
        INC ACC_LO
D16_NO_SUB:
        DEX
        BNE D16_LP
        LDA SIGN_FLG
        BPL D16_RTS
        SEC
        LDA #0
        SBC ACC_LO
        STA ACC_LO
        LDA #0
        SBC ACC_HI
        STA ACC_HI
D16_RTS:
        RTS
D16_ZERO:
        LDA #0
        STA ACC_LO
        STA ACC_HI
        RTS

IS_CHAR_DIGIT:
        CMP #'0'
        BCC ICD_NO
        CMP #':'
        BCS ICD_NO
        SEC
        RTS
ICD_NO:
        CLC
        RTS

; ============================================================================
; Scherm Opbouw: Spreadsheet Tabel + Formulebalk + Live Staafdiagram
; ============================================================================
FULL_REDRAW:
        LDX #0
FR_GUI_LP:
        LDA CALC_GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #CALC_GUI_STREAM_END - CALC_GUI_STREAM
        BCC FR_GUI_LP

        JSR DRAW_TOOLBAR

        ; Teken vaste teksten (Titelbalk + Kolomheaders A..E)
        LDA #<CALC_TEXT_TBL
        STA ZP_PTR_LO
        LDA #>CALC_TEXT_TBL
        STA ZP_PTR_HI
FR_TXT_LP:
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #$FF
        BEQ FR_ROW_HDRS
        JSR DRAW_NEXT_POS_STR
        JMP FR_TXT_LP

DRAW_POS_STR:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DRAW_NEXT_POS_STR:
        LDX #0
DPS_LP:
        JSR NEXT_PTR_BYTE
        STA ZP_X_LO,X
        INX
        CPX #5
        BCC DPS_LP
        JMP DRAW_ZP_STR

FR_ROW_HDRS:
        ; Teken Rijnummers 01..10 links in de tabel (X=12, Y=78 + r*24)
        LDA #0
        STA ZP_ITER_R
FR_RH_LP:
        LDA ZP_ITER_R
        JSR CALC_CELL_Y
        CLC
        LDA ZP_Y_LO
        ADC #7
        STA ZP_Y_LO
        BCC FR_RH_YOK
        INC ZP_Y_HI
FR_RH_YOK:
        LDA #12
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$00
        STA ZP_FG_COL
        LDA ZP_ITER_R
        CLC
        ADC #1
        JSR DRAW_DEC2
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #NUM_ROWS
        BCC FR_RH_LP

        JSR REDRAW_ALL_CELLS
        JSR DRAW_CHART_PANEL
        JSR DRAW_FORMULA_BAR
        JMP UPDATE_STATUS_BAR

DRAW_TOOLBAR:
        LDX #10                 ; Rect 10: Grijze werkbalk (0, 16, 640, 16, $B6)
        JSR SEND_RECT_10
        LDA #<STR_TOOLBAR
        LDY #>STR_TOOLBAR
DRAW_BAR_TEXT:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDA #8
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        STA ZP_FG_COL
        LDA #20
        STA ZP_Y_LO
        JMP DRAW_ZP_STR

SEND_RECT_10:
        LDY #10
SR10_LP:
        LDA UI_RECT_TBL,X
        STA IO_GPU
        INX
        DEY
        BNE SR10_LP
        RTS

REDRAW_ALL_CELLS:
        LDA #0
        STA ZP_ITER_R
RAC_R:
        LDA #0
        STA ZP_ITER_C
RAC_C:
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR DRAW_ONE_CELL
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #NUM_COLS
        BCC RAC_C
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #NUM_ROWS
        BCC RAC_R
        RTS

; Teken één cel op kolom X (0..4) en rij A (0..9)
DRAW_ONE_CELL:
        STX ZP_SAV_X
        STA ZP_SAV_Y
        JSR GET_CELL_PTR

        ; Bereken cel X = 32 + col * 80, Y = 72 + row * 24
        LDX ZP_SAV_X
        LDA COL_X_LO,X
        STA ZP_X_LO
        LDA COL_X_HI,X
        STA ZP_X_HI
        LDA ZP_SAV_Y
        JSR CALC_CELL_Y

        ; Bepaal achtergrond- en voorgrondkleur van deze cel
        LDA #$00                ; Standaard donkere cel-achtergrond
        STA ZP_BG_COL
        LDA #$FF                ; Standaard witte tekst
        STA ZP_FG_COL

        ; Rij 0 (Header rij) = Donkergroen ($10) met Gele tekst ($FC)
        LDA ZP_SAV_Y
        BNE DOC_CHK_TOT
        LDA #$10
        STA ZP_BG_COL
        LDA #$FC
        STA ZP_FG_COL
        JMP DOC_CHK_SEL

DOC_CHK_TOT:
        ; Rij 8 & 9 (TOTAAL / GEMIDDELD) = Donkerblauw ($02) met Cyaan/Gele tekst
        CMP #8
        BCC DOC_CHK_FORM
        LDA #$02
        STA ZP_BG_COL
        LDA #$3F
        STA ZP_FG_COL
        JMP DOC_CHK_SEL

DOC_CHK_FORM:
        ; Als het een formule-cel is (type 3): geef cyaan kleur ($1F)!
        LDY #12
        LDA (ZP_CELL_LO),Y
        CMP #3
        BNE DOC_CHK_SEL
        LDA #$1F
        STA ZP_FG_COL

DOC_CHK_SEL:
        ; Is dit de geselecteerde cel (CUR_COL, CUR_ROW)?
        LDA ZP_SAV_X
        CMP CUR_COL
        BNE DOC_DRAW_BG
        LDA ZP_SAV_Y
        CMP CUR_ROW
        BNE DOC_DRAW_BG
        ; Ja! Helder cyaan cursor-achtergrond ($1F) met zwarte tekst ($00)
        LDA #$1F
        STA ZP_BG_COL
        LDA #$00
        STA ZP_FG_COL

DOC_DRAW_BG:
        ; Teken cel-rechthoek van 78x22 px binnen de roosterlijnen
        LDA #2
        STA IO_GPU
        CLC
        LDA ZP_X_LO
        ADC #1
        STA IO_GPU
        LDA ZP_X_HI
        ADC #0
        STA IO_GPU
        CLC
        LDA ZP_Y_LO
        ADC #1
        STA IO_GPU
        LDA ZP_Y_HI
        ADC #0
        STA IO_GPU
        LDA #78
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #22
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_BG_COL
        STA IO_GPU

        ; Tekst Y = cel Y + 7, Tekst X = cel X + 4
        CLC
        LDA ZP_Y_LO
        ADC #7
        STA ZP_Y_LO
        BCC DOC_Y_OK
        INC ZP_Y_HI
DOC_Y_OK:
        CLC
        LDA ZP_X_LO
        ADC #4
        STA ZP_X_LO
        BCC DOC_X_OK
        INC ZP_X_HI
DOC_X_OK:

        ; Check cel-type (0=Leeg, 1=Tekst, 2=Getal, 3=Formule)
        LDY #12
        LDA (ZP_CELL_LO),Y
        BEQ DOC_RTS
        CMP #1
        BEQ DOC_DRAW_LABEL

        ; Type 2 of 3: Teken de 16-bit berekende waarde rechts-uitgelijnd!
        LDY #14
        LDA (ZP_CELL_LO),Y
        STA ACC_LO
        INY
        LDA (ZP_CELL_LO),Y
        STA ACC_HI
        JMP DRAW_INT16_RIGHT

DOC_DRAW_LABEL:
        ; Teken max 9 karakters van het tekstlabel in de cel
        LDY #0
DOC_LBL_LP:
        LDA (ZP_CELL_LO),Y
        BEQ DOC_RTS
        STY F_IDX
        JSR DRAW_CHAR_ADV
        LDY F_IDX
        INY
        CPY #9
        BCC DOC_LBL_LP
DOC_RTS:
        RTS

; ============================================================================
; Live Staafdiagram / Grafiek Rechts (X = 440..632, Y = 52..334)
; ============================================================================
DRAW_CHART_PANEL:
        ; Wis grafiek-achtergrond + groene header + hulplijnen in één stream!
        LDX #0
DCP_GRID_LP:
        LDA CHART_GRID_STREAM,X
        STA IO_GPU
        INX
        CPX #CHART_GRID_STREAM_END - CHART_GRID_STREAM
        BCC DCP_GRID_LP

        ; Teken titel: "GRAFIEK: " + Kolomnaam uit rij 0
        LDA #<STR_CHART_HDR
        LDY #>STR_CHART_HDR
        JSR DRAW_POS_STR

        LDX CHART_COL
        LDA #0
        JSR GET_CELL_PTR
        LDA ZP_CELL_LO
        STA ZP_PTR_LO
        LDA ZP_CELL_HI
        STA ZP_PTR_HI
        LDA #$FF
        STA ZP_FG_COL
        JSR DRAW_ZP_STR

        ; Zoek maximale positieve waarde in rijen 1..6 (R2..R7) van CHART_COL
        LDA #10                 ; Minimum schaal = 10 zodat we nooit door 0 delen
        STA MAX_VAL_LO
        LDA #0
        STA MAX_VAL_HI
        LDA #1
        STA ZP_ITER_R
DCP_MAX_LP:
        LDX CHART_COL
        LDA ZP_ITER_R
        JSR GET_CELL_PTR
        LDY #15
        LDA (ZP_CELL_LO),Y
        BMI DCP_MAX_NXT         ; Negeer negatieve waarden voor max
        STA OP_HI
        DEY
        LDA (ZP_CELL_LO),Y
        STA OP_LO
        CMP MAX_VAL_LO
        LDA OP_HI
        SBC MAX_VAL_HI
        BCC DCP_MAX_NXT
        LDA OP_LO
        STA MAX_VAL_LO
        LDA OP_HI
        STA MAX_VAL_HI
DCP_MAX_NXT:
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #7
        BCC DCP_MAX_LP

        ; Teken de 6 gekleurde staven voor rijen 1..6 (R2..R7)!
        LDA #1
        STA ZP_ITER_R
DCP_BAR_LP:
        LDX CHART_COL
        LDA ZP_ITER_R
        JSR GET_CELL_PTR
        LDY #15
        LDA (ZP_CELL_LO),Y
        BPL DCP_POS_VAL
        LDA #0
        STA ACC_LO
        STA ACC_HI
        JMP DCP_CALC_H
DCP_POS_VAL:
        STA ACC_HI
        DEY
        LDA (ZP_CELL_LO),Y
        STA ACC_LO

DCP_CALC_H:
        ; Bereken BAR_H = (ACC * 180) / MAX_VAL (in pixels, 0..180)
        LDA #180
        STA OP_LO
        LDA #0
        STA OP_HI
        JSR MUL16_SIGNED
        LDA MAX_VAL_LO
        STA OP_LO
        LDA MAX_VAL_HI
        STA OP_HI
        JSR DIV16_SIGNED
        LDA ACC_LO
        CMP #181
        BCC DCP_H_OK
        LDA #180
DCP_H_OK:
        STA BAR_H
        BEQ DCP_DRAW_LBL

        ; Staaf X = 454 + (ZP_ITER_R - 1) * 28, Staaf Y = 290 - BAR_H, breedte = 20
        LDX ZP_ITER_R
        LDA BAR_X_LO,X
        STA ZP_X_LO
        LDA BAR_X_HI,X
        STA ZP_X_HI
        SEC
        LDA #<290
        SBC BAR_H
        STA ZP_Y_LO
        LDA #>290
        SBC #0
        STA ZP_Y_HI

        LDA #2
        STA IO_GPU
        LDA ZP_X_LO
        STA IO_GPU
        LDA ZP_X_HI
        STA IO_GPU
        LDA ZP_Y_LO
        STA IO_GPU
        LDA ZP_Y_HI
        STA IO_GPU
        LDA #20
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA BAR_H
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDX ZP_ITER_R
        LDA BAR_COLORS,X
        STA IO_GPU

DCP_DRAW_LBL:
        ; Teken eerste 2 letters van Kolom A onderaan de staaf op Y=298!
        LDX ZP_ITER_R
        LDA BAR_X_LO,X
        CLC
        ADC #2
        STA ZP_X_LO
        LDA BAR_X_HI,X
        ADC #0
        STA ZP_X_HI
        LDA #<298
        STA ZP_Y_LO
        LDA #>298
        STA ZP_Y_HI
        LDA BAR_COLORS,X
        STA ZP_FG_COL

        LDX #0                  ; Kolom A (omschrijving)
        LDA ZP_ITER_R
        JSR GET_CELL_PTR
        LDY #0
        LDA (ZP_CELL_LO),Y
        BNE DCP_L1
        LDA #'R'
DCP_L1: JSR DRAW_CHAR_ADV
        LDY #1
        LDA (ZP_CELL_LO),Y
        BNE DCP_L2
        LDA ZP_ITER_R
        CLC
        ADC #'1'
DCP_L2: JSR DRAW_CHAR_ADV

        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #7
        BCS DCP_FOOTER
        JMP DCP_BAR_LP

DCP_FOOTER:
        ; Toon onderin het grafiekpaneel op (454, 316)
        LDA #<STR_CHART_SUB
        LDY #>STR_CHART_SUB
        JMP DRAW_POS_STR

; ============================================================================
; Formulebalk (Y = 32..49) & Statusbalk (Y = 342..359)
; ============================================================================
DRAW_FORMULA_BAR:
        LDX #20                 ; Rect 20: Wis formulebalk (0, 32, 640, 18, $00)
        JSR SEND_RECT_10
        LDX #30                 ; Rect 30: Groene cel-badge (6, 34, 38, 14, $10)
        JSR SEND_RECT_10

        ; Teken cel-coördinaat (bijv. B02) op (13, 37)
        LDA #13
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #37
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_FG_COL
        LDA CUR_COL
        CLC
        ADC #'A'
        JSR DRAW_CHAR_ADV
        LDA CUR_ROW
        CLC
        ADC #1
        JSR DRAW_DEC2

        ; Teken "fx :" op (52, 37)
        LDA #52
        STA ZP_X_LO
        LDA #$1F
        STA ZP_FG_COL
        LDA #<STR_FX_LBL
        STA ZP_PTR_LO
        LDA #>STR_FX_LBL
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR

        ; Als EDIT_MODE == 1: toon EDIT_BUF + geel '_' cursor-teken!
        LDA #92
        STA ZP_X_LO
        LDA EDIT_MODE
        CMP #1
        BEQ DFB_EDITING

        ; Anders: toon de rauwe inhoud (formule of tekst/getal) van de geselecteerde cel
        LDA #$FF
        STA ZP_FG_COL
        LDX CUR_COL
        LDA CUR_ROW
        JSR GET_CELL_PTR
        LDA ZP_CELL_LO
        STA ZP_PTR_LO
        LDA ZP_CELL_HI
        STA ZP_PTR_HI
        JMP DRAW_ZP_STR

DFB_EDITING:
        LDA #$FC
        STA ZP_FG_COL
        LDA #<EDIT_BUF
        STA ZP_PTR_LO
        LDA #>EDIT_BUF
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR
        LDA #'_'
        JMP DRAW_CHAR_ADV

UPDATE_STATUS_BAR:
        LDX #40                 ; Rect 40: Wis linker statusveld (8, 344, 440, 14, $10)
        JSR SEND_RECT_10

        LDA #<STR_ST_CEL
        LDY #>STR_ST_CEL
        JSR DRAW_POS_STR

        LDA CUR_COL
        CLC
        ADC #'A'
        JSR DRAW_CHAR_ADV
        LDA CUR_ROW
        CLC
        ADC #1
        JSR DRAW_DEC2

        LDA #<STR_ST_VAL
        STA ZP_PTR_LO
        LDA #>STR_ST_VAL
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR

        LDX CUR_COL
        LDA CUR_ROW
        JSR GET_CELL_PTR
        LDY #14
        LDA (ZP_CELL_LO),Y
        STA ACC_LO
        INY
        LDA (ZP_CELL_LO),Y
        STA ACC_HI
        LDA #$FC
        STA ZP_FG_COL
        JMP DRAW_INT16_LEFT

SHOW_STATUS_MSG:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDX #50                 ; Rect 50: Wis rechter statusveld (456, 344, 180, 14, $10)
        JSR SEND_RECT_10

        LDA #$CC                ; 460 = $01CC
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #$5B                ; 347 = $015B
        STA ZP_Y_LO
        LDA #$3F
        STA ZP_FG_COL
        JMP DRAW_ZP_STR

; ============================================================================
; Hulproutines & Getal-Formattering
; ============================================================================
; Zet ZP_CELL_LO/HI op $7800 + A*128 + X*16 (A = row 0..9, X = col 0..4)
GET_CELL_PTR:
        LSR A
        STA ZP_CELL_HI
        LDA #0
        ROR A
        ORA COL_OFFSET_16,X
        STA ZP_CELL_LO
        LDA ZP_CELL_HI
        CLC
        ADC #$78
        STA ZP_CELL_HI
        RTS

; Bereken ZP_Y_LO/HI = 72 + A * 24 (voor rij A = 0..9)
CALC_CELL_Y:
        TAX
        LDA ROW_Y_LO,X
        STA ZP_Y_LO
        LDA ROW_Y_HI,X
        STA ZP_Y_HI
        RTS

; Teken 16-bit signed getal in ACC_LO/HI rechts-uitgelijnd over 9 karakters vanaf ZP_X_LO/HI
DRAW_INT16_RIGHT:
        JSR FORMAT_INT16_TO_BUF
        ; Tel lengte van NUM_STR_BUF
        LDY #0
DIR_LEN:
        LDA NUM_STR_BUF,Y
        BEQ DIR_PAD
        INY
        JMP DIR_LEN
DIR_PAD:
        ; Voeg (9 - Y) spaties toe voor rechts-uitlijnen!
        STY F_IDX
        SEC
        LDA #9
        SBC F_IDX
        BCC DIR_STR
        BEQ DIR_STR
        TAX
DIR_SP_LP:
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DIR_SP1
        INC ZP_X_HI
DIR_SP1:
        DEX
        BNE DIR_SP_LP
DIR_STR:
        LDA #<NUM_STR_BUF
        STA ZP_PTR_LO
        LDA #>NUM_STR_BUF
        STA ZP_PTR_HI
        JMP DRAW_ZP_STR

DRAW_INT16_LEFT:
        JSR FORMAT_INT16_TO_BUF
        LDA #<NUM_STR_BUF
        STA ZP_PTR_LO
        LDA #>NUM_STR_BUF
        STA ZP_PTR_HI
        JMP DRAW_ZP_STR

FORMAT_INT16_TO_BUF:
        LDY #0
        LDA ACC_HI
        BPL FIT_POS
        LDA #'-'
        STA NUM_STR_BUF,Y
        INY
        SEC
        LDA #0
        SBC ACC_LO
        STA ACC_LO
        LDA #0
        SBC ACC_HI
        STA ACC_HI
FIT_POS:
        STY F_IDX
        LDA #0
        STA SIGN_FLG            ; 1 zodra eerste cijfer != 0 gezien is
        LDX #0
FIT_POW_LP:
        LDY #'0'
FIT_SUB:
        LDA ACC_LO
        CMP POW10_LO,X
        LDA ACC_HI
        SBC POW10_HI,X
        BCC FIT_DIG_DONE
        LDA ACC_LO
        SBC POW10_LO,X
        STA ACC_LO
        LDA ACC_HI
        SBC POW10_HI,X
        STA ACC_HI
        INY
        JMP FIT_SUB
FIT_DIG_DONE:
        CPX #4
        BEQ FIT_EMIT
        CPY #'0'
        BNE FIT_EMIT
        LDA SIGN_FLG
        BEQ FIT_NEXT_P
FIT_EMIT:
        LDA #1
        STA SIGN_FLG
        TYA
        LDY F_IDX
        STA NUM_STR_BUF,Y
        INC F_IDX
FIT_NEXT_P:
        INX
        CPX #5
        BCC FIT_POW_LP
        LDY F_IDX
        LDA #0
        STA NUM_STR_BUF,Y
        RTS

DRAW_DEC2:
        LDY #'0'
DD2_LP:
        CMP #10
        BCC DD2_OUT
        SBC #10
        INY
        JMP DD2_LP
DD2_OUT:
        PHA
        TYA
        JSR DRAW_CHAR_ADV
        PLA
        CLC
        ADC #'0'
        JMP DRAW_CHAR_ADV

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

INIT_GPU:
        LDX #0
IG_LP:
        LDA GPU_INIT_STREAM,X
        STA IO_GPU
        INX
        CPX #GPU_INIT_STREAM_END - GPU_INIT_STREAM
        BCC IG_LP
        RTS

WAIT_10MS:
        TAX
        BEQ W10_RTS
W10_OUTER:
        LDA IO_TIMER
W10_POLL:
        CMP IO_TIMER
        BEQ W10_POLL
        DEX
        BNE W10_OUTER
W10_RTS:
        RTS

; ============================================================================
; Spreadsheet Initialisatie & Voorbeeld-Rekenblad (BUDGET2026.XLS)
; ============================================================================
CLEAR_ALL_CELLS:
        LDA #$78
        STA ZP_CELL_HI
        LDA #0
        STA ZP_CELL_LO
        TAY
        LDX #5
CAC_PG:
        STA (ZP_CELL_LO),Y
        INY
        BNE CAC_PG
        INC ZP_CELL_HI
        DEX
        BNE CAC_PG
        LDA #$5A
        STA SHEET_MAGIC
        RTS

LOAD_DEMO_SHEET:
        JSR CLEAR_ALL_CELLS
        LDA #<DEMO_SHEET_TBL
        STA ZP_PTR_LO
        LDA #>DEMO_SHEET_TBL
        STA ZP_PTR_HI
LDS_LP:
        JSR NEXT_PTR_BYTE
        CMP #$FF
        BEQ LDS_GEN_FORM
        STA ZP_ITER_C           ; col
        JSR NEXT_PTR_BYTE
        STA ZP_ITER_R           ; row
        LDX ZP_ITER_C
        JSR GET_CELL_PTR
        LDY #0
LDS_CH:
        STY F_IDX
        JSR NEXT_PTR_BYTE
        LDY F_IDX
        STA (ZP_CELL_LO),Y
        TAX
        BEQ LDS_LP
        INY
        JMP LDS_CH

LDS_GEN_FORM:
        ; 1. Genereer Kolom D (=B2+C2..=B7+C7) en Kolom E (=D2*2..=D7*2) voor rijen 1..6
        LDA #1
        STA ZP_ITER_R
LDS_GF_LP:
        LDX #3                  ; Kolom D (col=3)
        LDA ZP_ITER_R
        JSR GET_CELL_PTR
        LDY #6
LDS_GF_C1:
        LDA TPL_SUM_BC,Y
        STA (ZP_CELL_LO),Y
        DEY
        BPL LDS_GF_C1
        LDA ZP_ITER_R
        CLC
        ADC #'1'
        LDY #2
        STA (ZP_CELL_LO),Y
        LDY #5
        STA (ZP_CELL_LO),Y

        LDX #4                  ; Kolom E (col=4)
        LDA ZP_ITER_R
        JSR GET_CELL_PTR
        LDY #5
LDS_GF_C2:
        LDA TPL_MUL_D2,Y
        STA (ZP_CELL_LO),Y
        DEY
        BPL LDS_GF_C2
        LDA ZP_ITER_R
        CLC
        ADC #'1'
        LDY #2
        STA (ZP_CELL_LO),Y

        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #7
        BCC LDS_GF_LP

        ; 2. Genereer Rij 8 (=SUM(B2:B7)..=SUM(E2:E7)) en Rij 9 (=AVG(B2:B7)..=AVG(E2:E7)) voor kolommen 1..4
        LDA #1
        STA ZP_ITER_C
LDS_GT_LP:
        LDX ZP_ITER_C
        LDA #8
        JSR GET_CELL_PTR
        LDY #11
LDS_GT_C1:
        LDA TPL_SUM_COL,Y
        STA (ZP_CELL_LO),Y
        DEY
        BPL LDS_GT_C1
        JSR PATCH_COL_LETTER

        LDX ZP_ITER_C
        LDA #9
        JSR GET_CELL_PTR
        LDY #11
LDS_GT_C2:
        LDA TPL_AVG_COL,Y
        STA (ZP_CELL_LO),Y
        DEY
        BPL LDS_GT_C2
        JSR PATCH_COL_LETTER

        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #5
        BCC LDS_GT_LP
        RTS

PATCH_COL_LETTER:
        LDA ZP_ITER_C
        CLC
        ADC #'A'
        LDY #5
        STA (ZP_CELL_LO),Y
        LDY #8
        STA (ZP_CELL_LO),Y
        RTS

TPL_SUM_BC:     .ASCIIZ "=B2+C2"
TPL_MUL_D2:     .ASCIIZ "=D2*2"
TPL_SUM_COL:    .ASCIIZ "=SUM(B2:B7)"
TPL_AVG_COL:    .ASCIIZ "=AVG(B2:B7)"

; ============================================================================
; Tabellen & GPU Streams
; ============================================================================
COL_OFFSET_16:  .BYTE $00, $10, $20, $30, $40
COL_X_LO:       .BYTE 32,  112, 192, 16,  96    ; 32, 112, 192, 272 ($0110), 352 ($0160)
COL_X_HI:       .BYTE 0,   0,   0,   1,   1

; Rij Y = 72 + row * 24 (72, 96, 120, 144, 168, 192, 216, 240, 264, 288)
ROW_Y_LO:       .BYTE 72, 96, 120, 144, 168, 192, 216, 240, 8,  32
ROW_Y_HI:       .BYTE 0,  0,  0,   0,   0,   0,   0,   0,   1,  1

; X-posities van de 6 staven in het grafiekpaneel (index 1..6): 454, 482, 510, 538, 566, 594
BAR_X_LO:       .BYTE 0, $C6, $E2, $FE, $1A, $36, $52
BAR_X_HI:       .BYTE 0, 1,   1,   1,   2,   2,   2
BAR_COLORS:     .BYTE 0, $1F, $F3, $1C, $FC, $F0, $E0

POW10_LO:       .BYTE $10, $E8, 100, 10, 1
POW10_HI:       .BYTE $27, $03, 0,   0,  0

GPU_INIT_STREAM:
        .BYTE 12, 1                     ; TARGET 1 (frontbuffer)
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0   ; BIGSPR 0 uit
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0   ; BIGSPR 1 uit
        .BYTE 15, 0, 0, 0, 0            ; SCROLL 0, 0
GPU_INIT_STREAM_END:

CALC_GUI_STREAM:
        ; Donkergrijs bureaublad: RECT(0, 50, 640, 292, $49)
        .BYTE 2, 0,0, 50,0, $80,$02, $24,$01, $49
        ; Smaragdgroene Titelbalk: RECT(0, 0, 640, 16, $10)
        .BYTE 2, 0,0, 0,0, $80,$02, 16,0, $10
        ; Wit spreadsheet-icoontje linksboven: RECT(8, 3, 10, 10, $FF)
        .BYTE 2, 8,0, 3,0, 10,0, 10,0, $FF
        ; Kolom-header balk (A..E): RECT(8, 54, 424, 18, $B6)
        .BYTE 2, 8,0, 54,0, $A8,$01, 18,0, $B6
        ; Rij-header kolom (01..10): RECT(8, 72, 24, 240, $B6)
        .BYTE 2, 8,0, 72,0, 24,0, 240,0, $B6
        ; Cyaan kader om het Live Grafiek Paneel rechts: RECT(440, 52, 192, 280, $1F)
        .BYTE 2, $B8,$01, 52,0, 192,0, $18,$01, $1F
        ; Onderste Statusbalk: RECT(0, 342, 640, 18, $10)
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $10
        ; Groene lijn onder formulebalk: LINE(0, 50, 639, 50, $1C)
        .BYTE 3, 0,0, 50,0, $7F,$02, 50,0, $1C
CALC_GUI_STREAM_END:

UI_RECT_TBL:
        ; Offset 0: Gele ESC-menubalk (0, 16, 640, 16, $FC)
        .BYTE 2, 0,0, 16,0, $80,$02, 16,0, $FC
        ; Offset 10: Grijze werkbalk (0, 16, 640, 16, $B6)
        .BYTE 2, 0,0, 16,0, $80,$02, 16,0, $B6
        ; Offset 20: Wis formulebalk (0, 32, 640, 18, $00)
        .BYTE 2, 0,0, 32,0, $80,$02, 18,0, $00
        ; Offset 30: Groene cel-badge links (6, 34, 38, 14, $10)
        .BYTE 2, 6,0, 34,0, 38,0, 14,0, $10
        ; Offset 40: Wis linker statusveld (8, 344, 440, 14, $10)
        .BYTE 2, 8,0, $58,$01, $B8,$01, 14,0, $10
        ; Offset 50: Wis rechter statusveld (456, 344, 180, 14, $10)
        .BYTE 2, $C8,$01, $58,$01, 180,0, 14,0, $10

CHART_GRID_STREAM:
        ; Wis grafiek-achtergrond: RECT(442, 54, 188, 276, $00)
        .BYTE 2, $BA,$01, 54,0, 188,0, $14,$01, $00
        ; Groene titel-header in grafiek: RECT(442, 54, 188, 18, $10)
        .BYTE 2, $BA,$01, 54,0, 188,0, 18,0, $10
        ; Horizontale hulplijnen in grafiek (X=450..624 op Y=110, 170, 230) en witte X-as op Y=290
        .BYTE 3, $C2,$01, 110,0, $70,$02, 110,0, $49
        .BYTE 3, $C2,$01, 170,0, $70,$02, 170,0, $49
        .BYTE 3, $C2,$01, 230,0, $70,$02, 230,0, $49
        .BYTE 3, $C0,$01, $22,$01, $72,$02, $22,$01, $FF
CHART_GRID_STREAM_END:

CALC_TEXT_TBL:
        .BYTE 24,0, 4,0, $FF, "LibreCalc 6502 - [BUDGET2026.XLS]                  MiniOffice Suite", 0
        .BYTE 12,0, 59,0, $00, "NR     A:POST      B:KWART1    C:KWART2    D:SOM(B+C)  E:JAAR(*2)", 0
        .BYTE $FF

STR_TOOLBAR:
        .ASCIIZ "PIJLTJES/WASD:Cel  ENTER/=:Formule  TAB/G:Grafiek  C:Wis  ESC:Menu/MC"
STR_ESC_MENU:
        .ASCIIZ "[1]Nieuw [2]Demo [3]Opslaan [4]Laden [5]Grafiek [SPAT]Verder [ESC]MC"

STR_FX_LBL:     .ASCIIZ "fx :"
STR_CHART_HDR:  .BYTE $C2,$01, 59,0, $FC, "GRAFIEK: ", 0
STR_CHART_SUB:  .BYTE $C6,$01, $3C,$01, $FF, "TAB/G = WISSEL KOLOM", 0
STR_ST_CEL:     .BYTE 10,0, $5B,$01, $FF, "CEL:", 0
STR_ST_VAL:     .ASCIIZ " | WAARDE = "

STR_MSG_READY:  .ASCIIZ "ENTER=BEWERK | TAB=GRAF"
STR_MSG_EDIT:   .ASCIIZ "TYP WAARDE/FORMULE+ENTER"
STR_MSG_OK:     .ASCIIZ "HERBEREKEND & GRAFIEK OK"
STR_MSG_CANCEL: .ASCIIZ "BEWERKING GEANNULEERD"
STR_MSG_SAVED:  .ASCIIZ "OPGESLAGEN OP SD!"

; Voorbeeld-spreadsheet: col (0..4), row (0..9), "inhoud", 0
DEMO_SHEET_TBL:
        ; Rij 1 (row=0): Kolomkoppen
        .BYTE 0,0, "AFDELING", 0
        .BYTE 1,0, "KWARTAAL1", 0
        .BYTE 2,0, "KWARTAAL2", 0
        .BYTE 3,0, "HALFJAAR", 0
        .BYTE 4,0, "JAARPROG", 0

        ; Rij 2..7 (row=1..6): Kolom A..C (D en E worden als =B2+C2 en =D2*2 gegenereerd)
        .BYTE 0,1, "HARDWARE", 0
        .BYTE 1,1, "420", 0
        .BYTE 2,1, "580", 0

        .BYTE 0,2, "SOFTWARE", 0
        .BYTE 1,2, "310", 0
        .BYTE 2,2, "440", 0

        .BYTE 0,3, "CLOUD/AI", 0
        .BYTE 1,3, "250", 0
        .BYTE 2,3, "350", 0

        .BYTE 0,4, "SUPPORT", 0
        .BYTE 1,4, "180", 0
        .BYTE 2,4, "220", 0

        .BYTE 0,5, "TRAINING", 0
        .BYTE 1,5, "140", 0
        .BYTE 2,5, "160", 0

        .BYTE 0,6, "LICENTIE", 0
        .BYTE 1,6, "200", 0
        .BYTE 2,6, "250", 0

        ; Rij 9 & 10 (row=8, 9): Labels (formules =SUM en =AVG worden gegenereerd)
        .BYTE 0,8, "TOTAAL", 0
        .BYTE 0,9, "GEMIDDELD", 0
        .BYTE $FF
