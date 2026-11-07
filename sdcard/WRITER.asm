; ============================================================================
; WRITER.asm - LibreWriter 6502 (WYSIWYG Tekstverwerker voor MiniGPU-BASIC 1.1)
; Geassembleerd op $8000 in SDRAM. Documentbuffer (16x70) op $7000-$77FF.
; Starten vanuit Midnight Commander (BRUN MC) of via: BRUN WRITER
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer (10ms ticks)
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- ROM Routines voor SD-Kaart Opslag (Sectors $03F8..$03FB) ---
ZP_TMP          = $1A
ZP_DST          = $1C
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA

; --- Eigen Zero Page Variabelen ($60..$7F) ---
ZP_LINE_LO      = $60           ; Pointer naar huidige tekstregel in $7000..$77FF
ZP_LINE_HI      = $61
ZP_PTR_LO       = $62           ; Algemene 16-bit pointer voor strings/streams
ZP_PTR_HI       = $63
ZP_X_LO         = $64           ; 16-bit GPU X
ZP_X_HI         = $65
ZP_Y_LO         = $66           ; 16-bit GPU Y
ZP_Y_HI         = $67
ZP_FG_COL       = $68           ; Tekst voorgrondkleur
ZP_BG_COL       = $69           ; Tekst achtergrondkleur

CUR_COL         = $6A           ; Huidige kolom (0..69)
CUR_ROW         = $6B           ; Huidige regel (0..15)
OLD_COL         = $6C           ; Vorige kolom (voor snelle cursor-update)
OLD_ROW         = $6D           ; Vorige regel
THEME_IDX       = $6E           ; Papier-thema: 0=Wit, 1=Donker, 2=Sepia
PAPER_BG        = $6F           ; Actuele papier-achtergrondkleur
PAPER_FG        = $70           ; Actuele standaard tekstkleur
BLINK_CNT       = $71           ; Cursor knipperteller
CUR_VIS         = $72           ; 1 = Cursor blokje zichtbaar, 0 = normaal
MENU_OPEN       = $73           ; 1 = ESC-menubalk actief, 0 = typ-modus
CHAR_CNT_LO     = $74           ; 16-bit teller voor aantal tekens in document
CHAR_CNT_HI     = $75
ZP_SAV_ROW      = $76           ; Tijdelijke rij-index bij tekenen
ZP_SAV_COL      = $77           ; Tijdelijke kolom-index bij tekenen
ZP_STYLE        = $78           ; Stijl van huidige regel (0..4)
PREV_JOY        = $79           ; Vorige IO_JOY status

DOC_RAM         = $7000         ; 16 regels x 128 bytes ($7000..$77FF)
DOC_MAGIC       = $77FF         ; $A5 als document al in geheugen staat
LINE_LEN        = 70            ; 70 kolommen per regel (560 px breed)
NUM_ROWS        = 16            ; 16 regels per pagina

; ============================================================================
; Startpunt ($8000)
; ============================================================================
START:
        LDA #12
        STA IO_TERM
        LDA #0
        STA IO_MODE
        STA CUR_COL
        STA CUR_ROW
        STA OLD_COL
        STA OLD_ROW
        STA MENU_OPEN
        STA BLINK_CNT
        LDA #1
        STA CUR_VIS

        ; Zet GPU op TARGET 1 (frontbuffer), BIGSPR uit, SCROLL 0,0
        JSR INIT_GPU

        ; Controleer of er al een document in SDRAM ($7000) staat
        LDA DOC_MAGIC
        CMP #$A5
        BEQ DOC_READY
        LDA #0
        STA THEME_IDX
        JSR LOAD_DEMO_DOC
DOC_READY:
        JSR APPLY_THEME_COLORS
        JSR FULL_REDRAW
        LDA #<STR_READY
        LDY #>STR_READY
        JSR SHOW_STATUS_MSG

        LDA IO_JOY
        STA PREV_JOY

; ============================================================================
; Hoofdlus: Cursor Knipperen & Toetsenbord / Pijltjes Invoer
; ============================================================================
MAIN_LOOP:
        LDA #1
        JSR WAIT_10MS

        ; Knipper de cursor elke 25 ticks (250 ms)
        INC BLINK_CNT
        LDA BLINK_CNT
        CMP #25
        BCC CHK_INPUT
        LDA #0
        STA BLINK_CNT
        LDA CUR_VIS
        EOR #1
        STA CUR_VIS
        JSR DRAW_CURSOR_CELL

CHK_INPUT:
        ; 1. Is op ESC gedrukt (bit 7 van IO_STATUS)?
        LDA IO_STATUS
        BPL CHK_TAB_KEY
        LDA IO_TERM             ; Lees en wis het ESC-karakter ($1B)
        LDA MENU_OPEN
        BNE EXIT_TO_MC          ; Nogmaals ESC in het menu = Afsluiten naar MC!
        JSR OPEN_TOP_MENU
        JMP MAIN_LOOP

EXIT_TO_MC:
        JSR ROM_SILENCE
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

CHK_TAB_KEY:
        ; 2. Check of TAB op PS/2 toetsenbord is ingedrukt (IO_JOY bit 6 zonder IO_TERM)
        LDA IO_STATUS
        AND #1
        BNE READ_KEY_CHAR

        ; Als MENU_OPEN == 1, laat ook Joypad pijl-omlaag/vuur werken
        LDA IO_JOY
        TAX
        EOR PREV_JOY
        AND IO_JOY
        STX PREV_JOY
        AND #$40                ; Bit 6 = TAB toets!
        BEQ MAIN_LOOP
        JSR CYCLE_LINE_STYLE
        JMP MAIN_LOOP

READ_KEY_CHAR:
        LDA IO_TERM
        STA ZP_SAV_COL          ; Bewaar gelezen ASCII byte
        LDA IO_JOY
        STA PREV_JOY

        ; Zet cursor direct zichtbaar bij elke toetsaanslag
        LDA #0
        STA BLINK_CNT
        LDA #1
        STA CUR_VIS

        ; Is het ESC-menu bovenin geopend?
        LDA MENU_OPEN
        BEQ EDIT_MODE_KEYS
        JMP HANDLE_MENU_KEY

; ============================================================================
; Invoer in normale Tekstverwerker-modus
; ============================================================================
EDIT_MODE_KEYS:
        LDA ZP_SAV_COL

        ; Check of dit een PS/2 Pijltjestoets is ('8','2','4','6' + IO_JOY bit 0..3)
        CMP #'8'
        BNE EM_CHK_DN
        LDA PREV_JOY
        AND #1
        BEQ EM_NOT_UP
        JMP DO_CUR_UP
EM_NOT_UP:
        LDA #'8'
        JMP INSERT_CHAR

EM_CHK_DN:
        CMP #'2'
        BNE EM_CHK_LT
        LDA PREV_JOY
        AND #2
        BEQ EM_NOT_DN
        JMP DO_CUR_DOWN
EM_NOT_DN:
        LDA #'2'
        JMP INSERT_CHAR

EM_CHK_LT:
        CMP #'4'
        BNE EM_CHK_RT
        LDA PREV_JOY
        AND #4
        BEQ EM_NOT_LT
        JMP DO_CUR_LEFT
EM_NOT_LT:
        LDA #'4'
        JMP INSERT_CHAR

EM_CHK_RT:
        CMP #'6'
        BNE EM_CHK_SPEC
        LDA PREV_JOY
        AND #8
        BEQ EM_NOT_RT
        JMP DO_CUR_RIGHT
EM_NOT_RT:
        LDA #'6'
        JMP INSERT_CHAR

EM_CHK_SPEC:
        ; Speciale toetsen: Enter ($0D), Backspace ($08), ` (Stijl), ~ (Thema), \ (Wis regel)
        CMP #$0D
        BNE EM_CHK_BS
        JMP DO_ENTER_KEY
EM_CHK_BS:
        CMP #$08
        BNE EM_CHK_DEL
        JMP DO_BACKSPACE
EM_CHK_DEL:
        CMP #$7F
        BNE EM_CHK_BTICK
        JMP DO_BACKSPACE
EM_CHK_BTICK:
        CMP #'`'
        BNE EM_CHK_TILDE
        JSR CYCLE_LINE_STYLE
        JMP MAIN_LOOP
EM_CHK_TILDE:
        CMP #'~'
        BNE EM_CHK_BSLASH
        JSR CYCLE_THEME
        JMP MAIN_LOOP
EM_CHK_BSLASH:
        CMP #'\'
        BNE EM_CHK_PRINT
        JSR CLEAR_CURRENT_LINE
        JMP MAIN_LOOP

EM_CHK_PRINT:
        ; Afdrukbare ASCII tekens ($20..$7E)
        CMP #$20
        BCC ML_JMP
        CMP #$7F
        BCS ML_JMP
        JMP INSERT_CHAR
ML_JMP:
        JMP MAIN_LOOP

; ============================================================================
; Cursor Beweging & Tekst Bewerking
; ============================================================================
DO_CUR_UP:
        JSR RESTORE_OLD_CELL
        LDA CUR_ROW
        BEQ DCU_DONE
        DEC CUR_ROW
DCU_DONE:
        JSR UPDATE_CURSOR_AND_STATUS
        JMP MAIN_LOOP

DO_CUR_DOWN:
        JSR RESTORE_OLD_CELL
        LDA CUR_ROW
        CMP #(NUM_ROWS - 1)
        BCS DCD_DONE
        INC CUR_ROW
DCD_DONE:
        JSR UPDATE_CURSOR_AND_STATUS
        JMP MAIN_LOOP

DO_CUR_LEFT:
        JSR RESTORE_OLD_CELL
        LDA CUR_COL
        BNE DCL_DEC
        LDA CUR_ROW
        BEQ DCL_DONE
        DEC CUR_ROW
        LDA #(LINE_LEN - 1)
        STA CUR_COL
        JMP DCL_DONE
DCL_DEC:
        DEC CUR_COL
DCL_DONE:
        JSR UPDATE_CURSOR_AND_STATUS
        JMP MAIN_LOOP

DO_CUR_RIGHT:
        JSR RESTORE_OLD_CELL
        LDA CUR_COL
        CMP #(LINE_LEN - 1)
        BCC DCR_INC
        LDA CUR_ROW
        CMP #(NUM_ROWS - 1)
        BCS DCR_DONE
        INC CUR_ROW
        LDA #0
        STA CUR_COL
        JMP DCR_DONE
DCR_INC:
        INC CUR_COL
DCR_DONE:
        JSR UPDATE_CURSOR_AND_STATUS
        JMP MAIN_LOOP

DO_ENTER_KEY:
        JSR RESTORE_OLD_CELL
        LDA #0
        STA CUR_COL
        LDA CUR_ROW
        CMP #(NUM_ROWS - 1)
        BCS DEK_DONE
        INC CUR_ROW
DEK_DONE:
        JSR UPDATE_CURSOR_AND_STATUS
        JMP MAIN_LOOP

DO_BACKSPACE:
        JSR RESTORE_OLD_CELL
        LDA CUR_COL
        BNE DBS_SAME_ROW
        LDA CUR_ROW
        BEQ DBS_DONE
        DEC CUR_ROW
        LDA #(LINE_LEN - 1)
        STA CUR_COL
        JMP DBS_ERASE_CHAR
DBS_SAME_ROW:
        DEC CUR_COL
        ; Schuif rest van de regel 1 positie naar links zodat tekst netjes aansluit!
        LDA CUR_ROW
        JSR GET_LINE_PTR
        LDY CUR_COL
DBS_SHIFT:
        CPY #(LINE_LEN - 1)
        BCS DBS_PAD_END
        INY
        LDA (ZP_LINE_LO),Y
        DEY
        STA (ZP_LINE_LO),Y
        INY
        JMP DBS_SHIFT
DBS_PAD_END:
        LDA #' '
        LDY #(LINE_LEN - 1)
        STA (ZP_LINE_LO),Y
        LDA CUR_ROW
        JSR DRAW_SINGLE_ROW
        JMP DBS_DONE

DBS_ERASE_CHAR:
        LDA CUR_ROW
        JSR GET_LINE_PTR
        LDY CUR_COL
        LDA #' '
        STA (ZP_LINE_LO),Y
        JSR RESTORE_OLD_CELL
DBS_DONE:
        JSR UPDATE_CURSOR_AND_STATUS
        JMP MAIN_LOOP

INSERT_CHAR:
        PHA
        LDA CUR_ROW
        JSR GET_LINE_PTR
        ; Schuif karakters vanaf einde regel (69) t/m CUR_COL+1 één plek naar rechts!
        LDY #(LINE_LEN - 1)
IC_SHIFT_R:
        CPY CUR_COL
        BEQ IC_STORE
        BCC IC_STORE
        DEY
        LDA (ZP_LINE_LO),Y
        INY
        STA (ZP_LINE_LO),Y
        DEY
        JMP IC_SHIFT_R
IC_STORE:
        LDY CUR_COL
        PLA
        STA (ZP_LINE_LO),Y

        ; Teken de bijgewerkte regel op het scherm
        LDA CUR_ROW
        JSR DRAW_SINGLE_ROW

        ; Verplaats cursor naar rechts (met automatische regeloverloop)
        LDA CUR_COL
        CMP #(LINE_LEN - 1)
        BCC IC_NEXT_COL
        LDA CUR_ROW
        CMP #(NUM_ROWS - 1)
        BCS IC_STAY
        INC CUR_ROW
        LDA #0
        STA CUR_COL
        JMP IC_STAY
IC_NEXT_COL:
        INC CUR_COL
IC_STAY:
        JSR UPDATE_CURSOR_AND_STATUS
        JMP MAIN_LOOP

; ============================================================================
; Top Menu Balk (geopend met ESC)
; ============================================================================
OPEN_TOP_MENU:
        LDA #1
        STA MENU_OPEN
        ; Teken gele menubalk op Y=16..33
        LDA #2
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$80
        STA IO_GPU
        LDA #$02
        STA IO_GPU
        LDA #18
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$FC                ; Helder geel
        STA IO_GPU

        LDA #8
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #21
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #$00
        STA ZP_FG_COL
        LDA #<STR_MENU_BAR
        STA ZP_PTR_LO
        LDA #>STR_MENU_BAR
        STA ZP_PTR_HI
        JMP DRAW_ZP_STR

CLOSE_TOP_MENU:
        LDA #0
        STA MENU_OPEN
        JSR DRAW_TOOLBAR
        LDA #<STR_READY
        LDY #>STR_READY
        JMP SHOW_STATUS_MSG

CTM_JMP:
        JSR CLOSE_TOP_MENU
        JMP MAIN_LOOP

MENU_STYLE:
        JSR CLOSE_TOP_MENU
        JSR CYCLE_LINE_STYLE
        JMP MAIN_LOOP

MENU_THEME:
        JSR CLOSE_TOP_MENU
        JSR CYCLE_THEME
        JMP MAIN_LOOP

MENU_CLR_LINE:
        JSR CLOSE_TOP_MENU
        JSR CLEAR_CURRENT_LINE
        JMP MAIN_LOOP

HANDLE_MENU_KEY:
        LDA ZP_SAV_COL
        CMP #' '
        BEQ CTM_JMP
        CMP #$0D
        BEQ CTM_JMP
        CMP #'1'
        BEQ MENU_NEW_DOC
        CMP #'2'
        BEQ MENU_DEMO_DOC
        CMP #'3'
        BEQ MENU_SAVE_SD
        CMP #'4'
        BEQ MENU_LOAD_SD
        CMP #'5'
        BEQ MENU_STYLE
        CMP #'6'
        BEQ MENU_THEME
        CMP #'7'
        BEQ MENU_CLR_LINE

        AND #$DF                ; Hoofdletter
        CMP #'Q'
        BNE HMK_C1
        JMP EXIT_TO_MC
HMK_C1: CMP #'N'
        BEQ MENU_NEW_DOC
        CMP #'D'
        BEQ MENU_DEMO_DOC
        CMP #'S'
        BEQ MENU_SAVE_SD
        CMP #'L'
        BEQ MENU_LOAD_SD
        CMP #'K'
        BEQ MENU_STYLE
        CMP #'T'
        BEQ MENU_THEME
        CMP #'Y'
        BEQ MENU_CLR_LINE
        JMP MAIN_LOOP

MENU_NEW_DOC:
        LDA #0
        STA MENU_OPEN
        JSR CLEAR_ALL_DOC
        LDA #<STR_MSG_NEW
        LDY #>STR_MSG_NEW
        JMP MENU_REDRAW_MSG

MENU_DEMO_DOC:
        LDA #0
        STA MENU_OPEN
        JSR LOAD_DEMO_DOC
        LDA #<STR_MSG_DEMO
        LDY #>STR_MSG_DEMO
        JMP MENU_REDRAW_MSG

MENU_SAVE_SD:
        JSR CLOSE_TOP_MENU
        JSR SAVE_DOC_TO_SD
        LDA #<STR_MSG_SAVED
        LDY #>STR_MSG_SAVED
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

MENU_LOAD_SD:
        LDA #0
        STA MENU_OPEN
        JSR LOAD_DOC_FROM_SD
        LDA #<STR_MSG_LOADED
        LDY #>STR_MSG_LOADED
MENU_REDRAW_MSG:
        PHA
        TYA
        PHA
        JSR FULL_REDRAW
        PLA
        TAY
        PLA
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; ============================================================================
; Stijl, Thema & Regel Acties
; ============================================================================
CYCLE_LINE_STYLE:
        LDA CUR_ROW
        JSR GET_LINE_PTR
        LDY #70
        LDA (ZP_LINE_LO),Y
        CLC
        ADC #1
        CMP #5
        BCC CLS_SET
        LDA #0
CLS_SET:
        STA (ZP_LINE_LO),Y
        LDA CUR_ROW
        JSR DRAW_SINGLE_ROW
        JSR DRAW_CURSOR_CELL
        JMP UPDATE_STATUS_BAR

CYCLE_THEME:
        INC THEME_IDX
        LDA THEME_IDX
        CMP #3
        BCC CT_OK
        LDA #0
        STA THEME_IDX
CT_OK:
        JSR APPLY_THEME_COLORS
        JMP FULL_REDRAW

APPLY_THEME_COLORS:
        LDX THEME_IDX
        LDA THEME_BG_TBL,X
        STA PAPER_BG
        LDA THEME_FG_TBL,X
        STA PAPER_FG
        RTS

CLEAR_CURRENT_LINE:
        LDA CUR_ROW
        JSR GET_LINE_PTR
        LDY #0
        LDA #' '
CCL_LP:
        STA (ZP_LINE_LO),Y
        INY
        CPY #LINE_LEN
        BCC CCL_LP
        LDA #0
        STA (ZP_LINE_LO),Y      ; Stijl = 0 (Normaal)
        STA CUR_COL
        LDA CUR_ROW
        JSR DRAW_SINGLE_ROW
        JMP UPDATE_CURSOR_AND_STATUS

; ============================================================================
; SD-Kaart Opslag & Laden (Sectors $03F8..$03FB = 2 KB voor $7000..$77FF)
; ============================================================================
SAVE_DOC_TO_SD:
        JSR ROM_SD_INIT
        LDA #$F8
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDA #$00
        STA ZP_DST
        LDA #$70
        STA ZP_DST+1
        LDX #4
SDS_LP:
        TXA
        PHA
        JSR ROM_WRITE_SEC
        PLA
        TAX
        DEX
        BNE SDS_LP
        RTS

LOAD_DOC_FROM_SD:
        JSR ROM_SD_INIT
        LDA #$F8
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDA #$00
        STA ZP_DST
        LDA #$70
        STA ZP_DST+1
        LDX #4
LDFS_LP:
        TXA
        PHA
        JSR ROM_READ_SEC
        PLA
        TAX
        DEX
        BNE LDFS_LP
        LDA DOC_MAGIC
        CMP #$A5
        BEQ LDFS_OK
        JMP LOAD_DEMO_DOC
LDFS_OK:
        RTS

; ============================================================================
; Document Initialisatie & Voorbeeld-Document
; ============================================================================
CLEAR_ALL_DOC:
        LDA #0
        STA ZP_SAV_ROW
CAD_ROW:
        LDA ZP_SAV_ROW
        JSR GET_LINE_PTR
        LDY #0
        LDA #' '
CAD_COL:
        STA (ZP_LINE_LO),Y
        INY
        CPY #LINE_LEN
        BCC CAD_COL
        LDA #0
        STA (ZP_LINE_LO),Y      ; Stijl 0
        INC ZP_SAV_ROW
        LDA ZP_SAV_ROW
        CMP #NUM_ROWS
        BCC CAD_ROW
        LDA #$A5
        STA DOC_MAGIC
        LDA #0
        STA CUR_COL
        STA CUR_ROW
        RTS

LOAD_DEMO_DOC:
        JSR CLEAR_ALL_DOC
        LDA #<DEMO_DOC_TBL
        STA ZP_PTR_LO
        LDA #>DEMO_DOC_TBL
        STA ZP_PTR_HI
LDD_LP:
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #$FF
        BEQ LDD_DONE
        STA ZP_SAV_ROW
        JSR GET_LINE_PTR
        ; Lees stijl-byte
        LDY #1
        LDA (ZP_PTR_LO),Y
        LDY #70
        STA (ZP_LINE_LO),Y
        ; Tel 2 op bij ZP_PTR
        CLC
        LDA ZP_PTR_LO
        ADC #2
        STA ZP_PTR_LO
        BCC LDD_CH_INIT
        INC ZP_PTR_HI
LDD_CH_INIT:
        LDY #0
LDD_CH_LP:
        LDA (ZP_PTR_LO),Y
        BEQ LDD_NEXT_REC
        STA (ZP_LINE_LO),Y
        INY
        BNE LDD_CH_LP
LDD_NEXT_REC:
        INY
        TYA
        CLC
        ADC ZP_PTR_LO
        STA ZP_PTR_LO
        BCC LDD_LP
        INC ZP_PTR_HI
        JMP LDD_LP
LDD_DONE:
        ; Zet cursor op regel 12 (eerste lege notitieregel)
        LDA #12
        STA CUR_ROW
        LDA #0
        STA CUR_COL
        RTS

; ============================================================================
; Scherm Opbouw & Snelle Incrementele Redraw Routines
; ============================================================================
FULL_REDRAW:
        ; Teken vaste GUI-layout (Achtergrond, Titelbalk, Liniaal, Schaduw, Statusbalk)
        LDX #0
FR_STREAM:
        LDA GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #GUI_STREAM_END - GUI_STREAM
        BCC FR_STREAM

        JSR DRAW_TOOLBAR

        ; Teken het A4 Papiervlak in PAPER_BG: RECT(28, 50, 584, 280, PAPER_BG)
        LDA #2
        STA IO_GPU
        LDA #28
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #50
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$48                ; 584 = $0248
        STA IO_GPU
        LDA #$02
        STA IO_GPU
        LDA #$18                ; 280 = $0118
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA PAPER_BG
        STA IO_GPU

        ; Rode kantlijn links op het papier: LINE(35, 50, 35, 329, $E9)
        LDA #3
        STA IO_GPU
        LDA #35
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #50
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #35
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$49                ; 329 = $0149
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #$E9
        STA IO_GPU

        ; Teken vaste teksten (Titelbalk + Liniaal)
        LDA #<GUI_TEXT_TBL
        STA ZP_PTR_LO
        LDA #>GUI_TEXT_TBL
        STA ZP_PTR_HI
FR_TXT_LP:
        JSR NEXT_PTR_BYTE
        CMP #$FF
        BEQ FR_ROWS
        STA ZP_X_LO
        JSR NEXT_PTR_BYTE
        STA ZP_X_HI
        JSR NEXT_PTR_BYTE
        STA ZP_Y_LO
        JSR NEXT_PTR_BYTE
        STA ZP_Y_HI
        JSR NEXT_PTR_BYTE
        STA ZP_FG_COL
        JSR DRAW_ZP_STR
        JMP FR_TXT_LP

FR_ROWS:
        LDA #0
        STA ZP_SAV_ROW
FR_ROW_LP:
        LDA ZP_SAV_ROW
        JSR DRAW_SINGLE_ROW
        INC ZP_SAV_ROW
        LDA ZP_SAV_ROW
        CMP #NUM_ROWS
        BCC FR_ROW_LP

        JMP UPDATE_CURSOR_AND_STATUS

DRAW_TOOLBAR:
        ; Grijze werkbalk op Y=16..32: RECT(0, 16, 640, 17, $B6)
        LDA #2
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$80
        STA IO_GPU
        LDA #$02
        STA IO_GPU
        LDA #17
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$B6
        STA IO_GPU

        LDA #8
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #21
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #$00
        STA ZP_FG_COL
        LDA #<STR_TOOLBAR
        STA ZP_PTR_LO
        LDA #>STR_TOOLBAR
        STA ZP_PTR_HI
        JMP DRAW_ZP_STR

; Teken één volledige tekstregel A (0..15) inclusief opmaak/stijl!
DRAW_SINGLE_ROW:
        STA ZP_SAV_ROW
        JSR GET_LINE_PTR
        LDY #70
        LDA (ZP_LINE_LO),Y
        STA ZP_STYLE

        ; Bereken Y = 58 + row * 16
        LDA ZP_SAV_ROW
        JSR CALC_ROW_Y

        ; Bepaal achtergrond- en tekstkleur voor deze stijl
        JSR GET_STYLE_COLORS

        ; Wis de regel-achtergrond: RECT(38, Y-2, 568, 15, ZP_BG_COL)
        LDA #2
        STA IO_GPU
        LDA #38
        STA IO_GPU
        LDA #0
        STA IO_GPU
        SEC
        LDA ZP_Y_LO
        SBC #2
        STA IO_GPU
        LDA ZP_Y_HI
        SBC #0
        STA IO_GPU
        LDA #$38                ; 568 = $0238
        STA IO_GPU
        LDA #$02
        STA IO_GPU
        LDA #15
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_BG_COL
        STA IO_GPU

        ; Als Stijl == 1 (Koptekst 1): teken blauwe onderstreping onder de regel!
        LDA ZP_STYLE
        CMP #1
        BNE DSR_NO_UL
        LDA #2
        STA IO_GPU
        LDA #40
        STA IO_GPU
        LDA #0
        STA IO_GPU
        CLC
        LDA ZP_Y_LO
        ADC #10
        STA IO_GPU
        LDA ZP_Y_HI
        ADC #0
        STA IO_GPU
        LDA #$30                ; 560 = $0230
        STA IO_GPU
        LDA #$02
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_FG_COL
        STA IO_GPU
DSR_NO_UL:

        ; Teken alle niet-spatie karakters van deze regel (kolom 0..69)
        LDA #40
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDY #0
DSR_CH_LP:
        STY ZP_SAV_COL
        LDA (ZP_LINE_LO),Y
        CMP #' '
        BEQ DSR_SKIP_SP
        JSR DRAW_CHAR_AT_XY
DSR_SKIP_SP:
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DSR_NXT
        INC ZP_X_HI
DSR_NXT:
        LDY ZP_SAV_COL
        INY
        CPY #LINE_LEN
        BCC DSR_CH_LP
        RTS

; Herstel het karakter op (CUR_COL, CUR_ROW) zonder cursor-blokje
RESTORE_OLD_CELL:
        LDA #0
        STA CUR_VIS
        JMP DRAW_CURSOR_CELL

UPDATE_CURSOR_AND_STATUS:
        LDA #1
        STA CUR_VIS
        JSR DRAW_CURSOR_CELL
        JMP UPDATE_STATUS_BAR

; Teken de cel op (CUR_COL, CUR_ROW) met of zonder knipperende cursor
DRAW_CURSOR_CELL:
        LDA CUR_ROW
        JSR GET_LINE_PTR
        LDY #70
        LDA (ZP_LINE_LO),Y
        STA ZP_STYLE
        JSR GET_STYLE_COLORS

        ; Bereken Y = 58 + CUR_ROW * 16
        LDA CUR_ROW
        JSR CALC_ROW_Y

        ; Bereken X = 40 + CUR_COL * 8
        LDA CUR_COL
        STA ZP_X_LO
        LDA #0
        ASL ZP_X_LO
        ROL A
        ASL ZP_X_LO
        ROL A
        ASL ZP_X_LO
        ROL A
        STA ZP_X_HI
        CLC
        LDA ZP_X_LO
        ADC #40
        STA ZP_X_LO
        BCC DCC_X_OK
        INC ZP_X_HI
DCC_X_OK:
        ; Als CUR_VIS == 1: teken blauw/cyaan cursorblokje ($1F) met zwarte tekst ($00)
        LDA CUR_VIS
        BEQ DCC_NORM
        LDA #$1F
        STA ZP_BG_COL
        LDA #$00
        STA ZP_FG_COL
DCC_NORM:
        ; Teken 8x11 achtergrondblokje op (ZP_X, ZP_Y-1)
        LDA #2
        STA IO_GPU
        LDA ZP_X_LO
        STA IO_GPU
        LDA ZP_X_HI
        STA IO_GPU
        SEC
        LDA ZP_Y_LO
        SBC #1
        STA IO_GPU
        LDA ZP_Y_HI
        SBC #0
        STA IO_GPU
        LDA #8
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #10
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_BG_COL
        STA IO_GPU

        ; Teken het karakter zelf
        LDY CUR_COL
        LDA (ZP_LINE_LO),Y
        CMP #' '
        BEQ DCC_RTS
        JMP DRAW_CHAR_AT_XY
DCC_RTS:
        RTS

; ============================================================================
; Statusbalk onderaan (Y = 342..359): Regel, Kolom, Tekens & Stijl
; ============================================================================
UPDATE_STATUS_BAR:
        ; Wis linker statusveld: RECT(8, 344, 460, 14, $0B)
        LDA #2
        STA IO_GPU
        LDA #8
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$58                ; 344 = $0158
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #$CC                ; 460 = $01CC
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #14
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$0B
        STA IO_GPU

        LDA #10
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$5B                ; Y = 347 ($015B)
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_FG_COL

        ; "RGL:" + (CUR_ROW + 1)
        LDA #<STR_ST_ROW
        STA ZP_PTR_LO
        LDA #>STR_ST_ROW
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR
        LDA CUR_ROW
        CLC
        ADC #1
        JSR DRAW_DEC2
        LDA #<STR_ST_COL
        STA ZP_PTR_LO
        LDA #>STR_ST_COL
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR
        LDA CUR_COL
        CLC
        ADC #1
        JSR DRAW_DEC2

        ; Tel aantal niet-spatie tekens in het document
        JSR COUNT_DOC_CHARS
        LDA #<STR_ST_CHR
        STA ZP_PTR_LO
        LDA #>STR_ST_CHR
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR
        JSR DRAW_CHAR_COUNT

        ; Toon naam van de huidige regel-stijl
        LDA #<STR_ST_STL
        STA ZP_PTR_LO
        LDA #>STR_ST_STL
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR

        LDA CUR_ROW
        JSR GET_LINE_PTR
        LDY #70
        LDA (ZP_LINE_LO),Y
        ASL A
        TAX
        LDA STYLE_NAME_PTRS,X
        STA ZP_PTR_LO
        LDA STYLE_NAME_PTRS+1,X
        STA ZP_PTR_HI
        LDA #$FC
        STA ZP_FG_COL
        JMP DRAW_ZP_STR

; Toon statusbericht rechts onderin op (476, 347)
SHOW_STATUS_MSG:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDA #2
        STA IO_GPU
        LDA #$DC                ; 476 = $01DC
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #$58                ; 344 = $0158
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #160
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #14
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$0B
        STA IO_GPU

        LDA #$E0                ; 480 = $01E0
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        LDA #$5B                ; 347 = $015B
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$3F
        STA ZP_FG_COL
        JMP DRAW_ZP_STR

; ============================================================================
; Hulproutines
; ============================================================================
; Zet ZP_LINE_LO/HI op $7000 + A * 128
GET_LINE_PTR:
        LSR A
        STA ZP_LINE_HI
        LDA #0
        ROR A
        STA ZP_LINE_LO
        LDA ZP_LINE_HI
        CLC
        ADC #$70
        STA ZP_LINE_HI
        RTS

; Bereken ZP_Y_LO/HI = 58 + A * 16
CALC_ROW_Y:
        STA ZP_Y_LO
        LDA #0
        ASL ZP_Y_LO
        ROL A
        ASL ZP_Y_LO
        ROL A
        ASL ZP_Y_LO
        ROL A
        ASL ZP_Y_LO
        ROL A
        STA ZP_Y_HI
        CLC
        LDA ZP_Y_LO
        ADC #58
        STA ZP_Y_LO
        BCC CRY_RTS
        INC ZP_Y_HI
CRY_RTS:
        RTS

; Bepaal ZP_BG_COL en ZP_FG_COL op basis van ZP_STYLE (0..4) en PAPER_BG/FG
GET_STYLE_COLORS:
        LDA PAPER_BG
        STA ZP_BG_COL
        LDA PAPER_FG
        STA ZP_FG_COL
        LDX ZP_STYLE
        BEQ GSC_RTS
        CPX #4
        BNE GSC_FG_ONLY
        ; Stijl 4 = Blauwe Titelbalk met Gele tekst!
        LDA #$0B
        STA ZP_BG_COL
        LDA #$FC
        STA ZP_FG_COL
        RTS
GSC_FG_ONLY:
        LDA THEME_IDX
        CMP #1
        BEQ GSC_DARK
        LDA STYLE_FG_LIGHT,X
        STA ZP_FG_COL
        RTS
GSC_DARK:
        LDA STYLE_FG_DARK,X
        STA ZP_FG_COL
GSC_RTS:
        RTS

COUNT_DOC_CHARS:
        LDA #0
        STA CHAR_CNT_LO
        STA CHAR_CNT_HI
        STA ZP_SAV_ROW
CDC_ROW:
        LDA ZP_SAV_ROW
        JSR GET_LINE_PTR
        LDY #0
CDC_COL:
        LDA (ZP_LINE_LO),Y
        CMP #' '
        BEQ CDC_NXT
        INC CHAR_CNT_LO
        BNE CDC_NXT
        INC CHAR_CNT_HI
CDC_NXT:
        INY
        CPY #LINE_LEN
        BCC CDC_COL
        INC ZP_SAV_ROW
        LDA ZP_SAV_ROW
        CMP #NUM_ROWS
        BCC CDC_ROW
        RTS

DRAW_CHAR_COUNT:
        LDX #1
DCC_POW_LP:
        LDY #'0'
DCC_SUB:
        LDA CHAR_CNT_LO
        CMP POW10_LO,X
        LDA CHAR_CNT_HI
        SBC POW10_HI,X
        BCC DCC_OUT
        LDA CHAR_CNT_LO
        SBC POW10_LO,X
        STA CHAR_CNT_LO
        LDA CHAR_CNT_HI
        SBC POW10_HI,X
        STA CHAR_CNT_HI
        INY
        JMP DCC_SUB
DCC_OUT:
        TYA
        STX ZP_SAV_COL
        JSR DRAW_CHAR_ADV
        LDX ZP_SAV_COL
        INX
        CPX #4
        BCC DCC_POW_LP
        RTS

; Print getal A (0..99) als 2 cijfers
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
        JSR DRAW_CHAR_AT_XY
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCAD_RTS
        INC ZP_X_HI
DCAD_RTS:
        RTS

DRAW_CHAR_AT_XY:
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
; Data Tabellen, Kleuren & Voorbeeld-Document
; ============================================================================
POW10_LO:       .BYTE $E8, 100, 10, 1
POW10_HI:       .BYTE $03, 0,   0,  0

THEME_BG_TBL:   .BYTE $FF, $00, $FE     ; 0=Wit, 1=Donker, 2=Sepia
THEME_FG_TBL:   .BYTE $00, $FF, $00

STYLE_FG_LIGHT: .BYTE $00, $03, $E0, $10, $FC
STYLE_FG_DARK:  .BYTE $FF, $1F, $E9, $1C, $FC

STYLE_NAME_PTRS:
        .WORD STR_STL0, STR_STL1, STR_STL2, STR_STL3, STR_STL4

STR_STL0:       .ASCIIZ "NORMAAL"
STR_STL1:       .ASCIIZ "KOPTEKST"
STR_STL2:       .ASCIIZ "BELANGRIJK"
STR_STL3:       .ASCIIZ "NOTITIE"
STR_STL4:       .ASCIIZ "TITELBALK"

STR_TOOLBAR:
        .ASCIIZ "PIJLTJES:Cursor  TAB/`:Stijl  ~:Thema  \:WisRgl  ESC:Menu/Opslaan/MC"
STR_MENU_BAR:
        .ASCIIZ "[1]Nieuw [2]Demo [3]Opslaan [4]Laden [5]Stijl [6]Thema [SPAT]Typ [ESC]MC"

STR_ST_ROW:     .ASCIIZ "RGL:"
STR_ST_COL:     .ASCIIZ " KOL:"
STR_ST_CHR:     .ASCIIZ " TEKENS:"
STR_ST_STL:     .ASCIIZ " STIJL:"

STR_READY:      .ASCIIZ "ESC=MENU | TAB=STIJL"
STR_MSG_NEW:    .ASCIIZ "NIEUW LEEG DOCUMENT"
STR_MSG_DEMO:   .ASCIIZ "DEMO DOCUMENT GELADEN"
STR_MSG_SAVED:  .ASCIIZ "OPGESLAGEN OP SD!"
STR_MSG_LOADED: .ASCIIZ "GELADEN VANAF SD!"

GPU_INIT_STREAM:
        .BYTE 12, 1                     ; TARGET 1 (frontbuffer)
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0   ; BIGSPR 0 uit
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0   ; BIGSPR 1 uit
        .BYTE 15, 0, 0, 0, 0            ; SCROLL 0, 0
GPU_INIT_STREAM_END:

GUI_STREAM:
        ; Bureaublad achtergrond: RECT(0, 33, 640, 309, $49 donkergrijs)
        .BYTE 2, 0,0, 33,0, $80,$02, $35,$01, $49
        ; Bovenste Titelbalk: RECT(0, 0, 640, 16, $0B donkerblauw)
        .BYTE 2, 0,0, 0,0, $80,$02, 16,0, $0B
        ; Document-icoontje linksboven: RECT(8, 3, 10, 10, $FF)
        .BYTE 2, 8,0, 3,0, 10,0, 10,0, $FF
        ; Liniaalbalk: RECT(28, 35, 584, 12, $DF)
        .BYTE 2, 28,0, 35,0, $48,$02, 12,0, $DF
        ; 3D Schaduw onder & rechts van het A4 papier: RECT(33, 55, 584, 280, $00)
        .BYTE 2, 33,0, 55,0, $48,$02, $18,$01, $00
        ; Onderste Statusbalk: RECT(0, 342, 640, 18, $0B)
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $0B
        ; Cyaan scheidingslijn boven statusbalk: LINE(0, 342, 639, 342, $1F)
        .BYTE 3, 0,0, $56,$01, $7F,$02, $56,$01, $1F
GUI_STREAM_END:

GUI_TEXT_TBL:
        .BYTE 24,0, 4,0, $FF, "LibreWriter 6502 - [DOCUMENT1.DOC]                  MiniOffice Suite", 0
        .BYTE 40,0, 37,0, $49, "1...5...10...15...20...25...30...35...40...45...50...55...60...65...70", 0
        .BYTE $FF

; Voorbeeld-document: rij, stijl (0..4), "tekst", 0
DEMO_DOC_TBL:
        .BYTE 0, 4, "          LIBREWRITER 6502 - TEKSTVERWERKER VOOR MINIGPU             ", 0
        .BYTE 1, 0, "", 0
        .BYTE 2, 1, "1. WELKOM BIJ MINIOFFICE OP DE TANG NANO 20K!", 0
        .BYTE 3, 0, "Dit is een volwaardige WYSIWYG tekstverwerker in 6502 machinecode.", 0
        .BYTE 4, 0, "Je kunt direct typen met alle letters, cijfers en leestekens.", 0
        .BYTE 5, 0, "", 0
        .BYTE 6, 1, "2. HANDIGE SNELTOETSEN & OPMAAK:", 0
        .BYTE 7, 3, "* Gebruik de PIJLTJESTOETSEN om de cursor door de tekst te bewegen.", 0
        .BYTE 8, 3, "* Druk op TAB (of `) voor 5 alinea-stijlen (Koptekst/Rood/Titelbalk).", 0
        .BYTE 9, 2, "* Druk op ESC voor het Menu (Opslaan/Laden op SD-kaart of Nieuw).", 0
        .BYTE 10, 0, "", 0
        .BYTE 11, 1, "3. JOUW NOTITIES (TYP HIERONDER):", 0
        .BYTE 12, 0, "Type hier je eigen tekst...", 0
        .BYTE $FF
