; ============================================================================
; EXCEL.asm - MiniGPU Excel 6502 (Volledig Scherm SDRAM Spreadsheet Editie)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC op $9000).
;
; Gebruikt de 64 KB Hardware SDRAM Array-banken ($A012-$A015, Banken 32..57):
;   * 26 Kolommen (A..Z) x 30 Rijen (01..30) = 780 Cellen in SDRAM!
;   * Volledig scherm (640x360): 7 kolommen (A..G) x 11 rijen (01..11) tegelijk
;     zichtbaar, scrollbaar over het hele bereik A1..Z30!
;   * Deelt live het SDRAM-geheugen met MiniGPU-BASIC arrays A(1)..Z(30):
;     - Elke celwaarde in Kolom A..Z, Rij 1..30 staat direct in BASIC A(r)..Z(r)!
;   * Formules: +, -, *, /, =SUM(B2:B7), =SOM(B2:B7), =AVG(B2:B7), =GEM(B2:B7),
;               =MAX(B2:B7), =MIN(B2:B7)
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_RD_LO        = $A012         ; SDRAM adres Low byte (0..255)
IO_RD_HI        = $A013         ; SDRAM adres High byte (0..255)
IO_RD_DATA      = $A014         ; SDRAM Data lees/schrijf poort
IO_RD_BANK      = $A015         ; SDRAM 64KB Bank (32..57 = BASIC Arrays A..Z)
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- ROM Routines voor SD-Kaart Opslag (Sectors $03FC..$03FE) ---
ZP_DST          = $1C
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA

; --- Werkbuffer voor Huidige Cel in Zero Page ($50..$5F) ---
CELL_BUF        = $50           ; $50..$5B = 12-byte ASCIIZ inhoud (formule/tekst/getal)
CELL_TYPE       = $5C           ; 0 = Leeg, 1 = Tekst, 2 = Getal/BASIC-Array, 3 = Formule
CELL_VAL_LO     = $5E           ; 16-bit signed waarde Low
CELL_VAL_HI     = $5F           ; 16-bit signed waarde High

; --- Eigen Zero Page Variabelen ($60..$8D) ---
ZP_PTR_LO       = $60           ; Algemene 16-bit pointer
ZP_PTR_HI       = $61
ZP_X_LO         = $62           ; 16-bit GPU X
ZP_X_HI         = $63
ZP_Y_LO         = $64           ; 16-bit GPU Y
ZP_Y_HI         = $65
ZP_FG_COL       = $66
ZP_BG_COL       = $67

CUR_COL         = $68           ; Geselecteerde kolom (0..25 = A..Z)
CUR_ROW         = $69           ; Geselecteerde rij (0..29 = 01..30)
OLD_COL         = $6A
OLD_ROW         = $6B
VIEW_COL        = $6C           ; Eerste zichtbare kolom op scherm (0..21)
VIEW_ROW        = $6D           ; Eerste zichtbare rij op scherm (0..20)
EDIT_MODE       = $6E           ; 0 = Navigatie, 1 = Formulebalk bewerken, 2 = ESC-Menu
EDIT_LEN        = $6F           ; Lengte in EDIT_BUF (0..11)
CHART_COL       = $70           ; Kolom (0..25 = A..Z) voor de Live Grafiek
PREV_JOY        = $71

; Reken-registers voor 16-bit Formule-Evaluator
ACC_LO          = $72
ACC_HI          = $73
OP_LO           = $74
OP_HI           = $75
MUL_LO          = $76
MUL_HI          = $77
SIGN_FLG        = $78
F_IDX           = $79           ; Parse-index in FORM_BUF
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

EDIT_BUF        = CELL_BUF      ; Bewerk direct in CELL_BUF ($50..$5B)
FORM_BUF        = CELL_BUF      ; Evalueer direct vanuit CELL_BUF ($50..$5B)
NUM_STR_BUF     = $88           ; Tijdelijke buffer ($88..$90) voor getal-weergave
SDRAM_RD_Y      = $02E0         ; 7-byte BSRAM trampoline: STY $A012 / LDA $A014 / RTS
BSRAM_EXIT_MC   = $02E7         ; 11-byte BSRAM Exit: LDA #1 / STA IO_MODE / LDA #12 / STA IO_TERM / RTS
SD_STAGE_RAM    = $7800         ; 1.5 KB staging buffer ($7800..$7DFF) voor SD-opslag

NUM_COLS        = 26            ; Kolommen A..Z (SDRAM Banken 32..57)
NUM_ROWS        = 30            ; Rijen 01..30 (SDRAM Pagina's 1..30)
VIS_COLS        = 7             ; 7 kolommen zichtbaar tegelijk op volledig scherm
VIS_ROWS        = 11            ; 11 rijen zichtbaar tegelijk op volledig scherm

; ============================================================================
; Startpunt ($8000)
; ============================================================================
START:
        ; Installeer SDRAM Read Trampoline & Exit-routine in BSRAM ($02F0..$0301)
        ; Zodat instructie-fetches vanaf $8000 (SDRAM Bank 63) rd_dout of restore_bg niet verstoren!
        LDX #17
INIT_TRAMP:
        LDA TRAMP_BYTES,X
        STA SDRAM_RD_Y,X
        DEX
        BPL INIT_TRAMP

        LDA #0
        STA IO_MODE
        STA EDIT_MODE
        STA VIEW_COL
        STA VIEW_ROW
        LDA #1                  ; Start op cel B2 (col=1, row=1)
        STA CUR_COL
        STA CUR_ROW

        ; Controleer in SDRAM Bank 32 ($FFFE..$FFFF) of Excel SDRAM al geïnitialiseerd is
        JSR CHECK_SDRAM_MAGIC
        BEQ SHEET_READY
        JSR LOAD_DEMO_SHEET
SHEET_READY:
        LDA #(STR_MSG_READY - STR_MSG_BASE)
        JMP FINISH_SHEET_MSG

; ============================================================================
; Hoofdlus: Invoer & Navigatie
; ============================================================================
MAIN_LOOP:
        LDA IO_TIMER
W10_POLL:
        CMP IO_TIMER
        BEQ W10_POLL

        ; 1. Check of op ESC is gedrukt (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_NAV_JOY
        LDA IO_TERM             ; Lees en wis ESC ($1B)
        LDA #0
        STA IO_MODE             ; Houd terminal-overlay uit (top.v zet term_enable=1 bij ESC!)
        LDA EDIT_MODE
        CMP #1
        BEQ CANCEL_CELL_EDIT
        CMP #2
        BEQ EXIT_TO_MC          ; Nogmaals ESC in het menu = Terug naar BASIC/MC!
        JSR OPEN_ESC_MENU
        JMP MAIN_LOOP

CANCEL_CELL_EDIT:
        LDA #0
        STA EDIT_MODE
        JSR DRAW_FORMULA_BAR
        LDA #(STR_MSG_CANCEL - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

EXIT_TO_MC:
        JSR ROM_SILENCE
        JMP BSRAM_EXIT_MC

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

        TYA
        AND #$40                ; Bit 6 = TAB -> Kolom naar rechts!
        BNE NAV_TAB_RIGHT

        LDA IO_TERM             ; Wis bijbehorende pijl/WASD karakter uit IO_TERM
        JSR SAVE_OLD_CUR
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

SAVE_OLD_CUR:
        LDA CUR_COL
        STA R_COL1
        LDA CUR_ROW
        STA R_ROW1
        RTS

NAV_TAB_RIGHT:
        JSR SAVE_OLD_CUR
        JMP MOVE_CELL_RIGHT

MOVE_CELL_UP:
        LDA CUR_ROW
        BEQ MCU_DONE
        DEC CUR_ROW
        LDA CUR_ROW
        CMP VIEW_ROW
        BCS UPDATE_SELECTION
        STA VIEW_ROW
        BCC UPDATE_SCROLL

MOVE_CELL_DOWN:
        LDA CUR_ROW
        CMP #(NUM_ROWS - 1)
        BCS MCU_DONE
        INC CUR_ROW
        LDA CUR_ROW
        SEC
        SBC VIEW_ROW
        CMP #VIS_ROWS
        BCC UPDATE_SELECTION
        INC VIEW_ROW
        BCS UPDATE_SCROLL

MOVE_CELL_LEFT:
        LDA CUR_COL
        BEQ MCU_DONE
        DEC CUR_COL
        LDA CUR_COL
        CMP VIEW_COL
        BCS UPDATE_SELECTION
        STA VIEW_COL
        BCC UPDATE_SCROLL

MOVE_CELL_RIGHT:
        LDA CUR_COL
        CMP #(NUM_COLS - 1)
        BCS MCU_DONE
        INC CUR_COL
        LDA CUR_COL
        SEC
        SBC VIEW_COL
        CMP #VIS_COLS
        BCC UPDATE_SELECTION
        INC VIEW_COL
UPDATE_SCROLL:
        JSR DRAW_COL_AND_ROW_HDRS
        JSR REDRAW_ALL_CELLS
        JMP UPDATE_BARS
UPDATE_SELECTION:
        ; Fast-path: herteken alleen de oude en nieuwe cel (38x sneller, 0 flikkering!)
        LDX R_COL1
        LDA R_ROW1
        JSR DRAW_ABS_CELL
        LDX CUR_COL
        LDA CUR_ROW
        JSR DRAW_ABS_CELL
UPDATE_BARS:
        JSR DRAW_FORMULA_BAR
        JSR UPDATE_STATUS_BAR
MCU_DONE:
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
        CMP #$09                ; TAB = Kolom naar rechts!
        BEQ NAV_TAB_RIGHT
        CMP #$0D                ; Enter = Bewerk huidige cel
        BEQ START_EDIT_EMPTY
        CMP #$08                ; Backspace = Wis huidige cel
        BEQ DO_CLEAR_CELL
        CMP #$7F
        BEQ DO_CLEAR_CELL

        ; Direct intypen van =, - of cijfer 0..9 start direct de formulebalk!
        CMP #'='
        BEQ START_EDIT_WITH_CHAR
        CMP #'-'
        BEQ START_EDIT_WITH_CHAR
        JSR IS_CHAR_DIGIT
        BCS START_EDIT_WITH_CHAR

        AND #$DF
        CMP #'C'
        BEQ DO_CLEAR_CELL
        CMP #'E'
        BEQ START_EDIT_EMPTY
        CMP #'R'                ; R = Herbereken alle formules
        BEQ RECALC_AND_REDRAW
        JMP MAIN_LOOP

DO_CLEAR_CELL:
        LDX CUR_COL
        LDA CUR_ROW
        JSR CLEAR_ONE_SDRAM_CELL
        JMP RECALC_AND_REDRAW

START_EDIT_EMPTY:
        LDA #0
        STA EDIT_LEN
        STA EDIT_BUF
        BEQ FINISH_EDIT_INIT

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
        LDA #(STR_MSG_EDIT - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; ============================================================================
; Toetsen tijdens Formulebalk Bewerken (EDIT_MODE == 1)
; ============================================================================
EDIT_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #$0D                ; Enter = Sla cel op in SDRAM & Herbereken!
        BEQ COMMIT_CELL_EDIT
        CMP #$08                ; Backspace
        BEQ EDIT_BACKSPACE
        CMP #$7F
        BEQ EDIT_BACKSPACE
        CMP #$20
        BCC EKH_DONE
        CMP #$7F
        BCS EKH_DONE

        LDX EDIT_LEN
        CPX #11
        BCS EKH_DONE
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
        ; Evalueer en bewaar CELL_BUF direct in SDRAM!
        JSR PARSE_INITIAL_CELL_BUF
        LDX CUR_COL
        LDA CUR_ROW
        JSR SAVE_CELL_SDRAM

RECALC_AND_REDRAW:
        LDA #0
        STA EDIT_MODE
        JSR RECALC_ALL
        JSR REDRAW_ALL_CELLS
        JSR DRAW_FORMULA_BAR
        JSR UPDATE_STATUS_BAR
        LDA #(STR_MSG_OK - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; ============================================================================
; ESC Menu (Balk bovenin + Popup-venster midden op het scherm)
; ============================================================================
OPEN_ESC_MENU:
        LDA #2
        STA EDIT_MODE
        ; Teken gecentreerd Popup-Menu venster (3 rechthoeken vanaf offset 80)
        LDX #80
        LDY #30
OEM_RECT_LP:
        LDA UI_RECT_TBL,X
        STA IO_GPU
        INX
        DEY
        BNE OEM_RECT_LP

        LDA #<STR_POPUP_MENU
        STA ZP_PTR_LO
        LDA #>STR_POPUP_MENU
        STA ZP_PTR_HI
OEM_STR_LP:
        JSR NEXT_PTR_BYTE
        BEQ OEM_DONE
        STA ZP_Y_LO
        JSR NEXT_PTR_BYTE
        STA ZP_FG_COL
        LDA #184
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        JSR DRAW_ZP_STR
        JMP OEM_STR_LP
OEM_DONE:
        RTS

CLOSE_ESC_MENU:
        LDA #0
        STA EDIT_MODE
        JSR FULL_REDRAW
        LDA #(STR_MSG_READY - STR_MSG_BASE)
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
        AND #$DF
        CMP #'N'
        BEQ MENU_NEW_SHEET
        CMP #'D'
        BEQ MENU_DEMO_SHEET
        CMP #'S'
        BEQ MENU_SAVE_SHEET
        CMP #'L'
        BEQ MENU_LOAD_SHEET
        CMP #'Q'
        BNE MKH_DONE
        JMP EXIT_TO_MC
MKH_DONE:
        JMP MAIN_LOOP

CEM_JMP:
        JSR CLOSE_ESC_MENU
        JMP MAIN_LOOP

MENU_NEW_SHEET:
        JSR CLEAR_ALL_CELLS
        LDA #0
        STA CUR_COL
        STA CUR_ROW
        JMP FINISH_SHEET_LOAD

MENU_DEMO_SHEET:
        JSR LOAD_DEMO_SHEET
        JMP FINISH_SHEET_LOAD

MENU_SAVE_SHEET:
        JSR CLOSE_ESC_MENU
        JSR SAVE_SHEET_SD
        LDA #(STR_MSG_SAVED - STR_MSG_BASE)
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

MENU_LOAD_SHEET:
        JSR LOAD_SHEET_SD
FINISH_SHEET_LOAD:
        LDA #0
        STA EDIT_MODE
        STA VIEW_COL
        STA VIEW_ROW
        LDA #(STR_MSG_OK - STR_MSG_BASE)
FINISH_SHEET_MSG:
        PHA
        JSR RECALC_ALL
        JSR FULL_REDRAW
        PLA
        JSR SHOW_STATUS_MSG
        LDA IO_JOY
        STA PREV_JOY
        JMP MAIN_LOOP

; ============================================================================
; Hardware SDRAM Array Routines ($A012..$A015, Banken 32..57 = Kolom A..Z)
;   * Pagina HI = 0, LO = (row + 1) * 2 : 16-bit waarde = BASIC Array A(r)..Z(r)!
;   * Pagina HI = row + 1, LO = 0..15   : 16-byte cel-record (string, type, val)
; ============================================================================
; Zet IO_RD_BANK = 32 + X (col 0..25), IO_RD_HI = A + 1 (row 0..29 -> page 1..30)
SET_SDRAM_CELL_PAGE:
        CLC
        ADC #1
SET_SDRAM_CELL_HI:
        STA IO_RD_HI
        TXA
        CLC
        ADC #32
        STA IO_RD_BANK
        RTS

; Zet IO_RD_BANK = 32 + X (col 0..25), IO_RD_HI = 0, Y = (A + 1) * 2 (BASIC Array!)
SET_SDRAM_BASIC_ARR:
        CLC
        ADC #1
        ASL A
        TAY
        LDA #0
        JMP SET_SDRAM_CELL_HI

; 18-byte BSRAM Trampoline broncode (gekopieerd naar $02F0..$0301 bij opstarten)
TRAMP_BYTES:
        STY IO_RD_LO
        LDA IO_RD_DATA
        RTS
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

; Lees 16-bit waarde van cel (X = col, A = row) uit BASIC SDRAM Array -> OP_LO/HI
GET_SDRAM_VAL:
        JSR SET_SDRAM_BASIC_ARR
        JSR SDRAM_RD_Y
        STA OP_LO
        INY
        JSR SDRAM_RD_Y
        STA OP_HI
        RTS

; Schrijf 16-bit waarde in CELL_VAL_LO/HI naar BASIC SDRAM Array (X = col, A = row)
SET_SDRAM_VAL:
        JSR SET_SDRAM_BASIC_ARR
        STY IO_RD_LO
        LDA CELL_VAL_LO
        STA IO_RD_DATA
        INY
        STY IO_RD_LO
        LDA CELL_VAL_HI
        STA IO_RD_DATA
        RTS

; Laad cel (X = col, A = row) vanuit SDRAM in CELL_BUF ($50..$5F)
; Synchroniseert automatisch met BASIC Array A(r)..Z(r) op pagina 0!
LOAD_CELL_SDRAM:
        PHA
        JSR SET_SDRAM_CELL_PAGE
        LDY #0
LCS_LP:
        JSR SDRAM_RD_Y
        STA CELL_BUF,Y
        INY
        CPY #16
        BCC LCS_LP

        ; Lees altijd de actuele 16-bit waarde uit de gedeelde BASIC Array (HI=0)!
        PLA
        JSR GET_SDRAM_VAL
        LDA OP_LO
        STA CELL_VAL_LO
        STA ACC_LO
        LDA OP_HI
        STA CELL_VAL_HI
        STA ACC_HI

        ; Als de cel-string leeg is, maar BASIC heeft een getal != 0 in A(r)..Z(r) gezet,
        ; promoveer de cel dan automatisch naar Type 2 (Getal uit BASIC)!
        LDA CELL_BUF
        BNE LCS_RTS
        LDA CELL_VAL_LO
        ORA CELL_VAL_HI
        BEQ LCS_EMPTY
        LDA #2
        STA CELL_TYPE
        RTS
LCS_EMPTY:
        LDA #0
        STA CELL_TYPE
LCS_RTS:
        RTS

; Sla CELL_BUF ($50..$5F) op naar SDRAM voor cel (X = col, A = row) én update BASIC Array!
SAVE_CELL_SDRAM:
        PHA
        JSR SET_SDRAM_CELL_PAGE
        LDY #0
SCS_LP:
        STY IO_RD_LO
        LDA CELL_BUF,Y
        STA IO_RD_DATA
        INY
        CPY #16
        BCC SCS_LP
        PLA
        JMP SET_SDRAM_VAL

; Wis één cel (X = col, A = row) volledig in SDRAM (zowel cel-pagina als BASIC Array!)
CLEAR_ONE_SDRAM_CELL:
        PHA
        JSR ZERO_CELL_BUF
        PLA
        JMP SAVE_CELL_SDRAM

ZERO_CELL_BUF:
        LDY #15
        LDA #0
ZCB_LP:
        STA CELL_BUF,Y
        DEY
        BPL ZCB_LP
        RTS

; ============================================================================
; SD-Kaart Opslag & Laden (Sectors $03FC..$03FE via $7800 voor A1..H12)
; ============================================================================
PREP_SHEET_SD:
        JSR ROM_SD_INIT
        LDA #$FC
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        STA ZP_ITER_R           ; 3 sectoren ($03FC..$03FE)
        LDA #$00
        STA ZP_DST
        LDA #$78
        STA ZP_DST+1
        RTS

SAVE_SHEET_SD:
        LDA #0                  ; 0 = SDRAM -> $7800
        JSR COPY_SD_SHEET
        LDA #$5A
        STA $7DFF
        JSR PREP_SHEET_SD
SSS_LP:
        JSR ROM_WRITE_SEC
        DEC ZP_ITER_R
        BNE SSS_LP
        RTS

LOAD_SHEET_SD:
        JSR PREP_SHEET_SD
LSS_LP:
        JSR ROM_READ_SEC
        DEC ZP_ITER_R
        BNE LSS_LP
        LDA $7DFF
        CMP #$5A
        BEQ LSS_UNPACK
        JMP LOAD_DEMO_SHEET

LSS_UNPACK:
        JSR CLEAR_ALL_CELLS
        LDA #1                  ; 1 = $7800 -> SDRAM
        ; Fallthrough naar COPY_SD_SHEET

COPY_SD_SHEET:
        STA CUR_OP
        LDA #<SD_STAGE_RAM
        STA ZP_PTR_LO
        LDA #>SD_STAGE_RAM
        STA ZP_PTR_HI
        LDA #0
        STA ZP_ITER_R
CSS_R:
        LDA #0
        STA ZP_ITER_C
CSS_C:
        LDA CUR_OP
        BNE CSS_FROM_RAM
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR LOAD_CELL_SDRAM
        LDY #15
CSS_TO_RAM:
        LDA CELL_BUF,Y
        STA (ZP_PTR_LO),Y
        DEY
        BPL CSS_TO_RAM
        BMI CSS_NXT
CSS_FROM_RAM:
        LDY #15
CSS_FR_LP:
        LDA (ZP_PTR_LO),Y
        STA CELL_BUF,Y
        DEY
        BPL CSS_FR_LP
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR SAVE_CELL_SDRAM
CSS_NXT:
        CLC
        LDA ZP_PTR_LO
        ADC #16
        STA ZP_PTR_LO
        BCC CSS_P_OK
        INC ZP_PTR_HI
CSS_P_OK:
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #8
        BCC CSS_C
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #12
        BCC CSS_R
        RTS

; ============================================================================
; 16-Bit Spreadsheet Formule-Evaluator & Herberekening in SDRAM (RECALC_ALL)
; ============================================================================
; Bepaalt bij het invoeren van een cel (in CELL_BUF) het initiële type & getalwaarde
PARSE_INITIAL_CELL_BUF:
        LDA #0
        STA CELL_TYPE
        STA CELL_VAL_LO
        STA CELL_VAL_HI
        LDA CELL_BUF
        BEQ PICB_RTS
        CMP #'='
        BEQ PICB_FORM
        CMP #'-'
        BEQ PICB_NEG
        JSR IS_CHAR_DIGIT
        BCS PICB_NUM
        ; Als iemand bijv. "A1+B1" typt zonder '=' (kolomletter gevolgd door cijfer),
        ; voeg dan automatisch '=' vooraan toe zodat het direct als formule werkt!
        LDA CELL_BUF+1
        JSR IS_CHAR_DIGIT
        BCC PICB_TXT
        LDY #10
PICB_SH:
        LDA CELL_BUF,Y
        STA CELL_BUF+1,Y
        DEY
        BPL PICB_SH
        LDA #'='
        STA CELL_BUF
        BNE PICB_FORM
PICB_TXT:
        LDA #1                  ; Type 1 = Tekstlabel
        STA CELL_TYPE
PICB_RTS:
        RTS
PICB_NEG:
        LDA FORM_BUF+1
        JSR IS_CHAR_DIGIT
        BCC PICB_TXT
PICB_NUM:
        LDA #2                  ; Type 2 = Getal (wordt gedeeld met BASIC Array!)
        STA CELL_TYPE
        LDA #0
        STA F_IDX
        JSR PARSE_TERM_AT_FIDX
        JMP STORE_ACC_TO_CELL
PICB_FORM:
        LDA #3                  ; Type 3 = Formule
        STA CELL_TYPE
        RTS

RECALC_ALL:
        ; Voer 2 evaluatie-rondes uit over SDRAM zodat ketting-formules kloppen
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
        JSR SET_SDRAM_CELL_PAGE
        LDY #0
        JSR SDRAM_RD_Y
        CMP #'='
        BNE RP_NEXT             ; Fast-path: alleen formules ('=') laden & herberekenen!
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR LOAD_CELL_SDRAM
        JSR EVAL_FORMULA_CELL
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR SAVE_CELL_SDRAM
RP_NEXT:
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #NUM_COLS
        BCC RP_COL
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #NUM_ROWS
        BCC RP_ROW
        RTS

EVAL_FORMULA_CELL:
        LDA #1
        STA F_IDX

        ; Check of de formule begint met SUM(/SOM(, AVG(/GEM(, MAX( of MIN(
        ; (Bij cel-referenties zoals =A1+B1 is FORM_BUF+2 een cijfer < 'A'!)
        LDA FORM_BUF+2
        CMP #'A'
        BCC ECC_ARITH
        LDA FORM_BUF+1
        CMP #'S'
        BEQ ECC_DO_SUM
        CMP #'A'
        BEQ ECC_DO_AVG
        CMP #'G'
        BEQ ECC_DO_AVG
        CMP #'M'
        BEQ ECC_DO_MINMAX
ECC_ARITH:
        ; Anders: Rekenkundige expressie met echte voorrangsregels (* en / vóór + en -) én haakjes ()!
        JSR EVAL_ARITH_EXPR
STORE_ACC_TO_CELL:
        LDA ACC_LO
        STA CELL_VAL_LO
        LDA ACC_HI
        STA CELL_VAL_HI
        RTS

; Niveau 1: Optellen (+) en Aftrekken (-)
EVAL_ARITH_EXPR:
        JSR PARSE_MUL_DIV
EAE_LP:
        LDY F_IDX
        LDA FORM_BUF,Y
        CMP #'+'
        BEQ EAE_DO
        CMP #'-'
        BNE EAE_RTS
EAE_DO:
        PHA
        LDA ACC_LO
        PHA
        LDA ACC_HI
        PHA
        INC F_IDX
        JSR PARSE_MUL_DIV
        LDA ACC_LO
        STA OP_LO
        LDA ACC_HI
        STA OP_HI
        PLA
        STA ACC_HI
        PLA
        STA ACC_LO
        PLA
        STA CUR_OP
        JSR APPLY_BINARY_OP
        JMP EAE_LP
EAE_RTS:
        RTS

; Niveau 2: Vermenigvuldigen (*) en Delen (/) hebben voorrang op + en -!
PARSE_MUL_DIV:
        JSR PARSE_TERM_AT_FIDX
PMD_LP:
        LDY F_IDX
        LDA FORM_BUF,Y
        CMP #'*'
        BEQ PMD_DO
        CMP #'/'
        BNE EAE_RTS
PMD_DO:
        PHA
        LDA ACC_LO
        PHA
        LDA ACC_HI
        PHA
        INC F_IDX
        JSR PARSE_TERM_AT_FIDX
        LDA ACC_LO
        STA OP_LO
        LDA ACC_HI
        STA OP_HI
        PLA
        STA ACC_HI
        PLA
        STA ACC_LO
        PLA
        STA CUR_OP
        JSR APPLY_BINARY_OP
        JMP PMD_LP

; Bereken =SUM(B2:B7), =AVG(B2:B7), =MAX(B2:B7) of =MIN(B2:B7) uit SDRAM!
ECC_DO_MINMAX:
        LDA FORM_BUF+2
        CMP #'I'
        BEQ ECC_DO_MIN
        LDA #2                  ; 2 = MAX
        BNE ECC_RANGE_FUNC
ECC_DO_MIN:
        LDA #3                  ; 3 = MIN
        BNE ECC_RANGE_FUNC
ECC_DO_SUM:
        LDA #0                  ; 0 = SUM / SOM
        BEQ ECC_RANGE_FUNC
ECC_DO_AVG:
        LDA #1                  ; 1 = AVG / GEM
ECC_RANGE_FUNC:
        STA CUR_OP
        LDA #5
        STA F_IDX
        JSR PARSE_CELL_REF
        STX R_COL1
        STA R_ROW1
        INC F_IDX
        JSR PARSE_CELL_REF
        INX
        STX R_COL2
        STA R_ROW2
        INC R_ROW2

        LDA #0
        STA ACC_LO
        STA ACC_HI
        STA CNT_CELLS

ERF_R_LP:
        LDA R_ROW1
        CMP R_ROW2
        BCS ERF_DONE_LP
        LDA R_COL1
        STA ZP_SAV_X
ERF_C_LP:
        LDX ZP_SAV_X
        CPX R_COL2
        BCS ERF_NXT_R
        LDA R_ROW1
        JSR GET_SDRAM_VAL
        LDA CUR_OP
        CMP #2
        BCC ERF_DO_ADD
        LDA CNT_CELLS
        BEQ ERF_SET_ACC
        ; Signed vergelijking tussen OP en ACC voor MAX (2) / MIN (3)
        LDA OP_LO
        CMP ACC_LO
        LDA OP_HI
        SBC ACC_HI
        BVC ERF_MM_V
        EOR #$80
ERF_MM_V:
        BMI ERF_IS_LESS
        ; OP >= ACC: kopieer als CUR_OP == 2 (MAX)
        LDA CUR_OP
        CMP #2
        BEQ ERF_SET_ACC
        BNE ERF_NXT_C
ERF_IS_LESS:
        ; OP < ACC: kopieer als CUR_OP == 3 (MIN)
        LDA CUR_OP
        CMP #3
        BNE ERF_NXT_C
ERF_SET_ACC:
        LDA OP_LO
        STA ACC_LO
        LDA OP_HI
        STA ACC_HI
        JMP ERF_NXT_C
ERF_DO_ADD:
        JSR ABO_ADD
ERF_NXT_C:
        INC CNT_CELLS
        INC ZP_SAV_X
        BNE ERF_C_LP
ERF_NXT_R:
        INC R_ROW1
        BNE ERF_R_LP

ERF_DONE_LP:
        LDA CUR_OP
        CMP #1
        BNE STORE_ACC_TO_CELL
        LDA CNT_CELLS
        BEQ STORE_ACC_TO_CELL
        STA OP_LO
        LDA #0
        STA OP_HI
        JSR DIV16_SIGNED
        JMP STORE_ACC_TO_CELL

; Parse één term (getal of cel-referentie A1..Z30) vanaf F_IDX in FORM_BUF -> ACC_LO/HI
PARSE_TERM_AT_FIDX:
        LDA #0
        STA ACC_LO
        STA ACC_HI
        STA SIGN_FLG
        LDY F_IDX
        LDA FORM_BUF,Y
        CMP #'-'
        BNE PTA_CHK_REF
        LDA #1
        STA SIGN_FLG
        INC F_IDX
        INY
        LDA FORM_BUF,Y

PTA_CHK_REF:
        ; Ondersteun haakjes (...) in formules, bijv. =(B2+C2)*D2
        CMP #'('
        BNE PTA_CHK_COL
        LDA SIGN_FLG
        PHA
        INC F_IDX
        JSR EVAL_ARITH_EXPR
        LDY F_IDX
        LDA FORM_BUF,Y
        CMP #')'
        BNE PTA_PAR_DONE
        INC F_IDX
PTA_PAR_DONE:
        PLA
        STA SIGN_FLG
        JMP PTA_APPLY_SIGN

PTA_CHK_COL:
        ; Is het een cel-kolom 'A'..'Z'?
        CMP #'A'
        BCC PTA_NUM_LP
        CMP #('Z' + 1)
        BCS PTA_NUM_LP

        JSR PARSE_CELL_REF
        JSR GET_SDRAM_VAL
        LDA OP_LO
        STA ACC_LO
        LDA OP_HI
        STA ACC_HI
        JMP PTA_APPLY_SIGN

PTA_NUM_LP:
        LDY F_IDX
        LDA FORM_BUF,Y
        JSR IS_CHAR_DIGIT
        BCC PTA_APPLY_SIGN
        SEC
        SBC #'0'
        PHA
        JSR MUL_ACC_10
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
        JMP NEG_ACC16
PTA_RTS:
        RTS

MUL_ACC_10:
        ASL ACC_LO
        ROL ACC_HI
        LDA ACC_LO
        STA OP_LO
        LDA ACC_HI
        STA OP_HI
        ASL ACC_LO
        ROL ACC_HI
        ASL ACC_LO
        ROL ACC_HI
        CLC
        LDA ACC_LO
        ADC OP_LO
        STA ACC_LO
        LDA ACC_HI
        ADC OP_HI
        STA ACC_HI
        RTS

; Parse cel-referentie A1..Z30 op F_IDX -> X = col (0..25), A = row (0..29)
PARSE_CELL_REF:
        LDY F_IDX
        LDA FORM_BUF,Y
        SEC
        SBC #'A'
        TAX
        INY
        LDA FORM_BUF,Y
        SEC
        SBC #'0'
        STA OP_LO
        INY
        LDA FORM_BUF,Y
        JSR IS_CHAR_DIGIT
        BCC PCR_1DIG
        SBC #'0'
        STA OP_HI
        LDA OP_LO
        ASL A
        STA OP_LO
        ASL A
        ASL A
        CLC
        ADC OP_LO
        ADC OP_HI
        STA OP_LO
        INY
PCR_1DIG:
        STY F_IDX
        LDY OP_LO
        BEQ PCR_ZERO
        DEY
        TYA
        CMP #NUM_ROWS
        BCC PCR_RTS
PCR_ZERO:
        LDA #0
PCR_RTS:
        RTS

; Voer CUR_OP ('+', '-', '*', '/') uit op ACC en OP -> resultaat in ACC
APPLY_BINARY_OP:
        LDA CUR_OP
        CMP #'+'
        BNE ABO_SUB
ABO_ADD:
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
        LDA OP_LO
        ORA OP_HI
        BEQ D16_ZERO
        LDA ACC_HI
        EOR OP_HI
        STA SIGN_FLG
        LDA ACC_HI
        BPL D16_A_POS
        JSR NEG_ACC16
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
        JMP NEG_ACC16
D16_RTS:
        RTS
D16_ZERO:
        LDA #0
        STA ACC_LO
        STA ACC_HI
        RTS

NEG_ACC16:
        SEC
        LDA #0
        SBC ACC_LO
        STA ACC_LO
        LDA #0
        SBC ACC_HI
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
; Scherm Opbouw: Volledig Scherm Spreadsheet Tabel (7x11) + Formulebalk
; ============================================================================
FULL_REDRAW:
        LDX #0
FR_GUI_LP:
        LDA CALC_GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #(CALC_GUI_STREAM_END - CALC_GUI_STREAM)
        BCC FR_GUI_LP

        JSR DRAW_TOOLBAR

        ; Teken Titelbalk
        LDA #<STR_TITLE_BAR
        LDY #>STR_TITLE_BAR
        JSR DRAW_POS_STR

        JSR DRAW_COL_AND_ROW_HDRS
        JSR REDRAW_ALL_CELLS
        JSR DRAW_FORMULA_BAR
        JMP UPDATE_STATUS_BAR

; Teken dynamisch de 7 zichtbare Kolomkoppen (bijv. A..G) & 11 Rijnummers (01..30)
DRAW_COL_AND_ROW_HDRS:
        LDX #60                 ; Rect 60 & 70: Wis Kolom- en Rij-header balken
        JSR SEND_RECT_10
        JSR SEND_RECT_10

        ; Teken "NR" linksboven in de tabelkop op (12, 59)
        LDA #<STR_NR_HDR
        LDY #>STR_NR_HDR
        JSR DRAW_POS_STR

        ; Teken de 7 zichtbare kolom-letters + "()" array-hint (bijv. "KOL A()")
        LDA #0
        STA ZP_ITER_C
DCRH_COL_LP:
        LDX ZP_ITER_C
        LDA COL_X_LO,X
        CLC
        ADC #15
        STA ZP_X_LO
        LDA COL_X_HI,X
        ADC #0
        STA ZP_X_HI
        LDA VIEW_COL
        CLC
        ADC ZP_ITER_C
        ADC #'A'
        STA STR_KOL_LET
        LDA #<STR_KOL_PREFIX
        LDY #>STR_KOL_PREFIX
        JSR DRAW_AY_STR
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #VIS_COLS
        BCC DCRH_COL_LP

        ; Teken de 11 zichtbare Rijnummers (VIEW_ROW+1 .. VIEW_ROW+11)
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
        STA ZP_FG_COL
        LDA VIEW_ROW
        CLC
        ADC ZP_ITER_R
        ADC #1
        JSR DRAW_DEC2
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #VIS_ROWS
        BCC FR_RH_LP
        RTS

DRAW_POS_STR:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDX #0
DPS_LP:
        JSR NEXT_PTR_BYTE
        STA ZP_X_LO,X
        INX
        CPX #5
        BCC DPS_LP
        JMP DRAW_ZP_STR

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
        LDA VIEW_COL
        CLC
        ADC ZP_ITER_C
        TAX
        LDA VIEW_ROW
        CLC
        ADC ZP_ITER_R
        JSR DRAW_ONE_CELL
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #VIS_COLS
        BCC RAC_C
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #VIS_ROWS
        BCC RAC_R
        RTS

; Teken één cel op kolom X (0..25) en rij A (0..29) door schermpositie te berekenen
DRAW_ABS_CELL:
        STX ZP_SAV_X
        STA ZP_SAV_Y
        SEC
        SBC VIEW_ROW
        STA ZP_ITER_R
        TXA
        SEC
        SBC VIEW_COL
        STA ZP_ITER_C
        LDA ZP_SAV_Y
; Teken één cel op kolom X (0..25) en rij A (0..29) op scherm-positie (ZP_ITER_C, ZP_ITER_R)
DRAW_ONE_CELL:
        STX ZP_SAV_X
        STA ZP_SAV_Y
        JSR LOAD_CELL_SDRAM

        LDX ZP_ITER_C
        LDA COL_X_LO,X
        STA ZP_X_LO
        LDA COL_X_HI,X
        STA ZP_X_HI
        LDA ZP_ITER_R
        JSR CALC_CELL_Y

        LDA #$00                ; Alle cellen dezelfde strakke zwarte achtergrond
        STA ZP_BG_COL
        LDA #$FF                ; Standaard witte tekst
        STA ZP_FG_COL

        LDA CELL_TYPE
        CMP #3
        BNE DOC_CHK_SEL
        LDA #$1F                ; Formule-cel (=...) = Helder Cyaan tekst
        STA ZP_FG_COL

DOC_CHK_SEL:
        LDA ZP_SAV_X
        CMP CUR_COL
        BNE DOC_DRAW_BG
        LDA ZP_SAV_Y
        CMP CUR_ROW
        BNE DOC_DRAW_BG
        LDA #$1F                ; Geselecteerde cel = Cyaan balk met zwarte tekst
        STA ZP_BG_COL
        LDA #$00
        STA ZP_FG_COL

DOC_DRAW_BG:
        INC ZP_X_LO
        BNE DOC_X1
        INC ZP_X_HI
DOC_X1: INC ZP_Y_LO
        BNE DOC_Y1
        INC ZP_Y_HI
DOC_Y1: LDA #84                 ; 84 px breed (7 kolommen van 86 px over 602 px)
        LDY #22
        LDX ZP_BG_COL
        JSR GPU_RECT_ZP

        CLC
        LDA ZP_Y_LO
        ADC #6
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

        LDA CELL_TYPE
        BEQ DOC_RTS
        CMP #1
        BEQ DOC_DRAW_LABEL

        ; Type 2 of 3: Teken de 16-bit waarde (al in ACC_LO/HI!) rechts-uitgelijnd!
        JMP DRAW_INT16_RIGHT

DOC_DRAW_LABEL:
        LDY #0
DOC_LBL_LP:
        LDA CELL_BUF,Y
        BEQ DOC_RTS
        STY F_IDX
        JSR DRAW_CHAR_ADV
        LDY F_IDX
        INY
        CPY #10
        BCC DOC_LBL_LP
DOC_RTS:
        RTS

; ============================================================================
; Formulebalk (Y = 32..49) & Statusbalk met BASIC SDRAM Array-Index (Y = 342..359)
; ============================================================================
DRAW_FORMULA_BAR:
        LDX #20                 ; Rect 20 & 30: Wis formulebalk + Groene cel-badge
        JSR SEND_RECT_10
        JSR SEND_RECT_10

        LDA #13
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #37
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_FG_COL
        JSR DRAW_CUR_COL
        JSR DRAW_CUR_ROW

        LDA #<STR_FX_LBL
        LDY #>STR_FX_LBL
        JSR DRAW_POS_STR

        LDA #92
        STA ZP_X_LO
        LDA EDIT_MODE
        CMP #1
        BEQ DFB_EDITING

        LDA #$FF
        STA ZP_FG_COL
        LDX CUR_COL
        LDA CUR_ROW
        JSR LOAD_CELL_SDRAM
        ; Als het een getal uit BASIC Array is (Type 2) zonder string, toon het getal!
        LDA CELL_BUF
        BNE DFB_SHOW_BUF
        LDA CELL_TYPE
        CMP #2
        BNE DFB_SHOW_BUF
        JMP DRAW_INT16_LEFT

DFB_EDITING:
        LDA #$FC
        STA ZP_FG_COL
DFB_SHOW_BUF:
        LDA #<CELL_BUF
        LDY #>CELL_BUF
        JSR DRAW_AY_STR
        LDA EDIT_MODE
        CMP #1
        BNE DFB_RTS
        LDA #'_'
        JMP DRAW_CHAR_ADV
DFB_RTS:
        RTS

DRAW_CUR_COL:
        LDA CUR_COL
        CLC
        ADC #'A'
        JMP DRAW_CHAR_ADV

DRAW_CUR_ROW:
        LDA CUR_ROW
        CLC
        ADC #1
        JMP DRAW_DEC2

UPDATE_STATUS_BAR:
        LDX #40                 ; Rect 40: Wis linker statusveld (8, 344, 440, 14, $10)
        JSR SEND_RECT_10

        LDA #<STR_ST_CEL
        LDY #>STR_ST_CEL
        JSR DRAW_POS_STR

        ; Toon BASIC SDRAM Array-naam bijv. "B(02) | WAARDE = "
        JSR DRAW_CUR_COL
        LDA #'('
        JSR DRAW_CHAR_ADV
        JSR DRAW_CUR_ROW
        LDA #')'
        JSR DRAW_CHAR_ADV

        LDA #<STR_ST_VAL
        LDY #>STR_ST_VAL
        JSR DRAW_AY_STR

        LDX CUR_COL
        LDA CUR_ROW
        JSR LOAD_CELL_SDRAM
        LDA #$FC
        STA ZP_FG_COL
        JMP DRAW_INT16_LEFT

SHOW_STATUS_MSG:
        CLC
        ADC #<STR_MSG_BASE
        STA ZP_PTR_LO
        LDA #0
        ADC #>STR_MSG_BASE
        STA ZP_PTR_HI
        LDX #50                 ; Rect 50: Wis rechter statusveld (432, 344, 204, 14, $10)
        JSR SEND_RECT_10

        LDA #$B4                ; 436 = $01B4
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
CALC_CELL_Y:
        ASL A
        ASL A
        ASL A
        STA ZP_Y_LO
        ASL A
        CLC
        ADC ZP_Y_LO
        ADC #72
        STA ZP_Y_LO
        LDA #0
        ADC #0
        STA ZP_Y_HI
        RTS

DRAW_INT16_RIGHT:
        JSR FORMAT_INT16_TO_BUF
        LDY #0
DIR_LEN:
        LDA NUM_STR_BUF,Y
        BEQ DIR_PAD
        INY
        BNE DIR_LEN
DIR_PAD:
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
        JMP DRAW_NUM_BUF

DRAW_INT16_LEFT:
        JSR FORMAT_INT16_TO_BUF
DRAW_NUM_BUF:
        LDA #<NUM_STR_BUF
        LDY #>NUM_STR_BUF
        JMP DRAW_AY_STR

GPU_RECT_ZP:
        PHA
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
        PLA
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STY IO_GPU
        STA IO_GPU
        STX IO_GPU
        RTS

FORMAT_INT16_TO_BUF:
        LDY #0
        LDA ACC_HI
        BPL FIT_POS
        LDA #'-'
        STA NUM_STR_BUF,Y
        INY
        JSR NEG_ACC16
FIT_POS:
        STY F_IDX
        LDA #0
        STA SIGN_FLG
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
        BNE FIT_SUB
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
        BNE DD2_LP
DD2_OUT:
        PHA
        TYA
        JSR DRAW_CHAR_ADV
        PLA
        CLC
        ADC #'0'
        JMP DRAW_CHAR_ADV

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

; ============================================================================
; SDRAM Spreadsheet Initialisatie & Voorbeeld-Rekenblad (A1..Z30 in SDRAM)
; ============================================================================
CHECK_SDRAM_MAGIC:
        JSR SET_MAGIC_ADDR
        JSR SDRAM_RD_Y
        CMP #'X'
        BNE CSM_FAIL
        INY
        JSR SDRAM_RD_Y
        CMP #'4'
CSM_FAIL:
        RTS

SET_SDRAM_MAGIC:
        JSR SET_MAGIC_ADDR
        STY IO_RD_LO
        LDA #'X'
        STA IO_RD_DATA
        INY
        STY IO_RD_LO
        LDA #'4'
        STA IO_RD_DATA
        RTS

SET_MAGIC_ADDR:
        LDA #32
        STA IO_RD_BANK
        LDA #$FF
        STA IO_RD_HI
        LDY #$FE
        RTS

CLEAR_ALL_CELLS:
        LDA #0
        STA ZP_ITER_R
CAC_R:
        LDA #0
        STA ZP_ITER_C
CAC_C:
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR CLEAR_ONE_SDRAM_CELL
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #NUM_COLS
        BCC CAC_C
        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #NUM_ROWS
        BCC CAC_R
        JMP SET_SDRAM_MAGIC

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
        PHA
        AND #$0F
        STA ZP_ITER_R
        PLA
        LSR A
        LSR A
        LSR A
        LSR A
        STA ZP_ITER_C
        JSR ZERO_CELL_BUF
        LDY #0
LDS_CH:
        STY F_IDX
        JSR NEXT_PTR_BYTE
        LDY F_IDX
        STA CELL_BUF,Y
        TAX
        BEQ LDS_STORE
        INY
        BNE LDS_CH
LDS_STORE:
        LDA #1
        STA CELL_TYPE
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR SAVE_CELL_SDRAM
        JMP LDS_LP

LDS_GEN_FORM:
        ; 1. Vul voor rijen 1..6:
        ;    Kolom B (col 1) & C (col 2) in BASIC SDRAM Arrays B(2..7) & C(2..7)
        ;    Kolom D..G (col 3..6) met formules =B2+C2, =D2*2, =D2/4, =E2+F2
        LDA #1
        STA ZP_ITER_R
LDS_GF_LP:
        LDY ZP_ITER_R
        LDA DEMO_B_DIV10-1,Y
        LDX #1
        JSR STORE_DEMO_NUM10
        LDY ZP_ITER_R
        LDA DEMO_C_DIV10-1,Y
        LDX #2
        JSR STORE_DEMO_NUM10

        LDA #<TPL_SUM_BC
        STA ZP_PTR_LO
        LDA #>TPL_SUM_BC
        STA ZP_PTR_HI
        LDA #3
        STA ZP_ITER_C
LDS_GR_COL:
        LDY #0
GRF_CP:
        STY F_IDX
        JSR NEXT_PTR_BYTE
        LDY F_IDX
        STA CELL_BUF,Y
        INY
        CPY #7
        BCC GRF_CP
        LDA ZP_ITER_R
        CLC
        ADC #'1'
        STA CELL_BUF+2
        LDA CELL_BUF+5
        CMP #'2'
        BNE GRF_SAVE
        LDA CELL_BUF+2
        STA CELL_BUF+5
GRF_SAVE:
        LDA #3
        STA CELL_TYPE
        LDX ZP_ITER_C
        LDA ZP_ITER_R
        JSR SAVE_CELL_SDRAM
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #7
        BCC LDS_GR_COL

        INC ZP_ITER_R
        LDA ZP_ITER_R
        CMP #7
        BCC LDS_GF_LP

        ; 2. Genereer Rij 7 (=SUM), Rij 8 (=AVG), Rij 9 (=MIN) en Rij 10 (=MAX) voor Kolom B..G
        LDA #1
        STA ZP_ITER_C
LDS_GT_LP:
        LDY #11
GCF_CP:
        LDA TPL_SUM_COL,Y
        STA CELL_BUF,Y
        DEY
        BPL GCF_CP
        LDA ZP_ITER_C
        CLC
        ADC #'A'
        STA CELL_BUF+5
        STA CELL_BUF+8
        LDA #3
        STA CELL_TYPE
        LDX ZP_ITER_C
        LDA #7
        JSR SAVE_CELL_SDRAM
        LDA #'A'
        STA CELL_BUF+1
        LDA #'V'
        STA CELL_BUF+2
        LDA #'G'
        STA CELL_BUF+3
        LDX ZP_ITER_C
        LDA #8
        JSR SAVE_CELL_SDRAM
        LDA #'M'
        STA CELL_BUF+1
        LDA #'I'
        STA CELL_BUF+2
        LDA #'N'
        STA CELL_BUF+3
        LDX ZP_ITER_C
        LDA #9
        JSR SAVE_CELL_SDRAM
        LDA #'A'
        STA CELL_BUF+2
        LDA #'X'
        STA CELL_BUF+3
        LDX ZP_ITER_C
        LDA #10
        JSR SAVE_CELL_SDRAM
        INC ZP_ITER_C
        LDA ZP_ITER_C
        CMP #7
        BCC LDS_GT_LP
        RTS

STORE_DEMO_NUM10:
        STA ACC_LO
        LDA #0
        STA ACC_HI
        JSR MUL_ACC_10
        LDA ACC_LO
        STA CELL_VAL_LO
        LDA ACC_HI
        STA CELL_VAL_HI
        LDA ZP_ITER_R
        JMP SET_SDRAM_VAL

TPL_SUM_BC:     .ASCIIZ "=B2+C2"
TPL_MUL_D2:     .BYTE "=D2*2", 0, 0
TPL_DIV_D4:     .BYTE "=D2/4", 0, 0
TPL_SUM_EF:     .ASCIIZ "=E2+F2"
TPL_SUM_COL:    .ASCIIZ "=SUM(B2:B7)"

; ============================================================================
; Tabellen & GPU Streams
; ============================================================================
; 7 kolommen van 86 px breed (32, 118, 204, 290, 376, 462, 548)
COL_X_LO:       .BYTE 32,  118, 204, 34,  120, 206, 36
COL_X_HI:       .BYTE 0,   0,   0,   1,   1,   1,   2

POW10_LO:       .BYTE $10, $E8, 100, 10, 1
POW10_HI:       .BYTE $27, $03, 0,   0,  0

CALC_GUI_STREAM:
        .BYTE 12, 1                     ; TARGET 1 (frontbuffer)
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0   ; BIGSPR 0 uit
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0   ; BIGSPR 1 uit
        .BYTE 15, 0, 0, 0, 0            ; SCROLL 0, 0
        .BYTE 2, 0,0, 50,0, $80,$02, $24,$01, $49
        .BYTE 2, 0,0, 0,0, $80,$02, 16,0, $10
        .BYTE 2, 8,0, 3,0, 10,0, 10,0, $FF
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $10
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
        ; Offset 40: Wis linker statusveld (8, 344, 416, 14, $10)
        .BYTE 2, 8,0, $58,$01, $A0,$01, 14,0, $10
        ; Offset 50: Wis rechter statusveld (432, 344, 204, 14, $10)
        .BYTE 2, $B0,$01, $58,$01, 204,0, 14,0, $10
        ; Offset 60: Kolom-header balk over volle breedte (8, 54, 626, 18, $B6)
        .BYTE 2, 8,0, 54,0, $72,$02, 18,0, $B6
        ; Offset 70: Rij-header kolom voor 11 rijen (8, 72, 24, 264, $B6)
        .BYTE 2, 8,0, 72,0, 24,0, $08,$01, $B6
        ; Offset 80..100: ESC Popup-venster (Rand + Donker vlak + Gele titelbalk)
        .BYTE 2, 166,0, 110,0, 52,1, 124,0, $1F
        .BYTE 2, 168,0, 112,0, 48,1, 120,0, $00
        .BYTE 2, 168,0, 112,0, 48,1, 18,0, $FC

STR_POPUP_MENU:
        .BYTE 117, $00, "=== EXCEL SDRAM MENU ===", 0
        .BYTE 138, $FF, "[1/N] Nieuw Leeg Blad", 0
        .BYTE 154, $FF, "[2/D] Demo Sommen Laden", 0
        .BYTE 170, $FF, "[3/S] Opslaan op SD", 0
        .BYTE 186, $FF, "[4/L] Laden van SD", 0
        .BYTE 208, $1F, "[SPAT] Sluit [ESC/Q] Uit", 0
        .BYTE 0

STR_TITLE_BAR:
        .BYTE 24,0, 4,0, $FF, "MiniGPU Excel 6502 [SDRAM A(1)..Z(30) = 1.66 MB] Tang Nano 20K", 0
STR_NR_HDR:
        .BYTE 12,0, 59,0, $00, "NR", 0
STR_KOL_PREFIX:
        .BYTE "KOL "
STR_KOL_LET:
        .ASCIIZ "A()"

STR_TOOLBAR:
        .ASCIIZ "PIJL/WASD/TAB:Scroll A1..Z30 ENTER/=:Formule (+-*/ SUM/AVG/MAX/MIN) ESC:Menu"

STR_FX_LBL:     .BYTE 52,0, 37,0, $1F, "fx :", 0
STR_ST_CEL:     .BYTE 10,0, $5B,$01, $FF, "SDRAM ARRAY: ", 0
STR_ST_VAL:     .ASCIIZ " | WAARDE = "

STR_MSG_BASE:
STR_MSG_READY:  .ASCIIZ "SDRAM A(1)..Z(30) ACTIEF"
STR_MSG_EDIT:   .ASCIIZ "TYP WAARDE/FORMULE+ENTER"
STR_MSG_OK:     .ASCIIZ "SDRAM ARRAYS BIJGEWERKT"
STR_MSG_CANCEL: .ASCIIZ "INVOER GEANNULEERD"
STR_MSG_SAVED:  .ASCIIZ "OPGESLAGEN OP SD!"

DEMO_B_DIV10:   .BYTE 42, 31, 25, 18, 14, 20    ; B2..B7: 420, 310, 250, 180, 140, 200
DEMO_C_DIV10:   .BYTE 58, 44, 35, 22, 16, 25    ; C2..C7: 580, 440, 350, 220, 160, 250

DEMO_SHEET_TBL:
        ; Byte 0 = (col << 4) | row, gevolgd door ASCIIZ label
        .BYTE $00, "AFDELING", 0
        .BYTE $10, "KWARTAAL1", 0
        .BYTE $20, "KWARTAAL2", 0
        .BYTE $30, "HALFJAAR", 0
        .BYTE $40, "JAARPROG", 0
        .BYTE $50, "BONUS", 0
        .BYTE $60, "TOTAAL+", 0
        .BYTE $01, "HARDWARE", 0
        .BYTE $02, "SOFTWARE", 0
        .BYTE $03, "CLOUD/AI", 0
        .BYTE $04, "SUPPORT", 0
        .BYTE $05, "TRAINING", 0
        .BYTE $06, "LICENTIE", 0
        .BYTE $07, "TOTAAL", 0
        .BYTE $08, "GEMIDDELD", 0
        .BYTE $09, "MINIMUM", 0
        .BYTE $0A, "MAXIMUM", 0
        .BYTE $FF
