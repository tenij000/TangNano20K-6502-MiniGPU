; ============================================================================
; SPREDIT.asm - PixelStudio 6502 (16x16 Hardware Sprite & Animatie Editor)
; Geassembleerd op $8000 in SDRAM. 8 Sprites (8 x 256B = 2KB) op $6000-$67FF.
; Bevat 16x16 Zoom-Grid, 16-Kleuren Palet, Echte Hardware Sprite Preview (1x,
; Spiegel-X/Y, 2x Zoom & Live Animatie), Spiegel-X/Y, 90-graden Rotatie,
; Pipet, Vlakvulling, Kopieer/Plak én SD-Kaart Opslag (Sectors $03F0..$03F3).
; Starten vanuit Midnight Commander (BRUN MC) of via: BRUN SPREDIT
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- ROM Routines voor SD-Kaart Opslag (Sectors $03F0..$03F3) ---
ZP_DST          = $1C
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA

; --- Eigen Zero Page Variabelen ($60..$7F) ---
ZP_SPR_LO       = $60           ; Pointer naar huidige sprite ($6000 + slot*256)
ZP_SPR_HI       = $61
ZP_PTR_LO       = $62           ; Algemene 16-bit pointer
ZP_PTR_HI       = $63
ZP_X_LO         = $64           ; 16-bit GPU X
ZP_X_HI         = $65
ZP_Y_LO         = $66           ; 16-bit GPU Y
ZP_Y_HI         = $67
ZP_FG_COL       = $68
ZP_BG_COL       = $69

CUR_X           = $6A           ; Cursor X in sprite (0..15)
CUR_Y           = $6B           ; Cursor Y in sprite (0..15)
OLD_X           = $6C
OLD_Y           = $6D
CUR_SLOT        = $6E           ; Actieve sprite-slot (0..7 = Sprite 1..8)
CUR_COL_IDX     = $6F           ; Actieve kleur-index in palet (0..15)
MENU_OPEN       = $70           ; 0 = Editor, 1 = ESC-Menu
ANIM_ON         = $71           ; 1 = Live animatie aan, 0 = Uit
ANIM_TICK       = $72           ; Timer voor animatie-preview
ANIM_FRAME      = $73           ; Huidig animatie-frame (0..3)
PREV_JOY        = $74

ZP_ITER_X       = $75
ZP_ITER_Y       = $76
ZP_SAV_A        = $77
ZP_SAV_X        = $78
TARGET_COL      = $79           ; Doelkleur voor Vlakvulling (Fill)
NEW_COL         = $7A

; --- Geheugen-Indeling in SDRAM ($6000..$69FF) ---
SPR_BANK_RAM    = $6000         ; 8 sprites x 256 bytes ($6000..$67FF)
SPR_MAGIC       = $6800         ; $5A als sprites al in SDRAM geladen zijn
CLIP_RAM        = $6800 + $100  ; $6900..$69FF: 256-byte klembord & rotatie-buffer
TEMP_RAM        = $6A00         ; $6A00..$6AFF: 256-byte werkbuffer voor 90-gr rotatie

HW_SPR_BASE     = 24            ; Gebruik Hardware Sprite ID's 24..31 in FPGA BRAM

; ============================================================================
; Startpunt ($8000)
; ============================================================================
START:
        LDA #12
        STA IO_TERM
        LDA #0
        STA IO_MODE
        STA CUR_SLOT
        STA MENU_OPEN
        STA ANIM_TICK
        STA ANIM_FRAME
        LDA #1
        STA ANIM_ON             ; Live animatie standaard AAN
        LDA #3                  ; Kleur 3 = Geel ($FC)
        STA CUR_COL_IDX
        LDA #7
        STA CUR_X
        STA CUR_Y
        STA OLD_X
        STA OLD_Y

        JSR INIT_GPU

        ; Controleer of de 8 sprites al in SDRAM ($6000..$67FF) staan
        LDA SPR_MAGIC
        CMP #$5A
        BEQ BANK_READY
        JSR LOAD_DEMO_SPRITES
BANK_READY:
        JSR UPLOAD_ALL_HW_SPRITES
        JSR FULL_REDRAW
        LDA #<STR_MSG_READY
        LDY #>STR_MSG_READY
        JSR SHOW_STATUS_MSG

        LDA IO_JOY
        STA PREV_JOY

; ============================================================================
; Hoofdlus: Cursor, Tekentools & Live Hardware Sprite Animatie
; ============================================================================
MAIN_LOOP:
        LDA #1
        JSR WAIT_10MS

        ; 1. Check of op ESC is gedrukt (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_ANIM_TICK
        LDA IO_TERM             ; Wis ESC uit IO_TERM
        LDA MENU_OPEN
        BNE EXIT_TO_MC          ; Nogmaals ESC in het menu = Terug naar MC!
        JSR OPEN_ESC_MENU
        JMP MAIN_LOOP

EXIT_TO_MC:
        ; Verberg preview-sprites voor we terugkeren naar Midnight Commander
        JSR HIDE_PREVIEW_SPRITES
        JSR ROM_SILENCE
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

CHK_ANIM_TICK:
        ; 2. Werk elke 180 ms de Live Hardware Animatie-Preview bij!
        INC ANIM_TICK
        LDA ANIM_TICK
        CMP #18
        BCC CHK_JOY_INPUT
        LDA #0
        STA ANIM_TICK
        LDA ANIM_ON
        BEQ CHK_JOY_INPUT
        INC ANIM_FRAME
        JSR DRAW_ANIM_SPRITE

CHK_JOY_INPUT:
        LDA MENU_OPEN
        BNE CHK_TERM_KEY

        ; 3. Flank-detectie op IO_JOY voor Pijltjes / WASD / TAB
        LDA IO_JOY
        STA ZP_SAV_X
        TAX
        EOR PREV_JOY
        AND ZP_SAV_X
        STX PREV_JOY
        TAY
        BEQ CHK_TERM_KEY

        ; Check TAB (bit 6) = Volgende kleur in palet
        TYA
        AND #$40
        BNE DO_NEXT_COL

        ; Als richting (bits 0..3) actief is, wis eventuele pijl/WASD echo in IO_TERM
        TYA
        AND #$0F
        BEQ CHK_TERM_KEY
        LDA IO_STATUS
        AND #1
        BEQ HANDLE_DIRS
        LDA IO_TERM             ; Slok pijl/WASD karakter op
HANDLE_DIRS:
        JSR SAVE_OLD_XY
        TYA
        AND #1                  ; Omhoog
        BEQ HD_DN
        LDA CUR_Y
        SEC
        SBC #1
        AND #15
        STA CUR_Y
HD_DN:  TYA
        AND #2                  ; Omlaag
        BEQ HD_LT
        LDA CUR_Y
        CLC
        ADC #1
        AND #15
        STA CUR_Y
HD_LT:  TYA
        AND #4                  ; Links
        BEQ HD_RT
        LDA CUR_X
        SEC
        SBC #1
        AND #15
        STA CUR_X
HD_RT:  TYA
        AND #8                  ; Rechts
        BEQ HD_UPD
        LDA CUR_X
        CLC
        ADC #1
        AND #15
        STA CUR_X
HD_UPD:
        ; Herteken alleen de oude en nieuwe pixel-cel in het 16x16 grid (< 0.3 ms!)
        LDX OLD_X
        LDY OLD_Y
        JSR DRAW_GRID_CELL
        LDX CUR_X
        LDY CUR_Y
        JSR DRAW_GRID_CELL
        JSR UPDATE_STATUS_BAR
        JMP MAIN_LOOP

DO_NEXT_COL:
        LDA IO_STATUS
        AND #1
        BEQ DNC_1
        LDA IO_TERM
DNC_1:  JSR NEXT_PALETTE_COL
        JMP MAIN_LOOP

CHK_TERM_KEY:
        LDA IO_STATUS
        AND #1
        BEQ MAIN_LOOP_JMP
        LDA IO_TERM
        STA ZP_SAV_A
        LDA IO_JOY
        STA PREV_JOY

        LDA MENU_OPEN
        BEQ EDITOR_KEY_HANDLER
        JMP MENU_KEY_HANDLER
MAIN_LOOP_JMP:
        JMP MAIN_LOOP

; ============================================================================
; Sneltoetsen in de Sprite Editor
; ============================================================================
EDITOR_KEY_HANDLER:
        LDA ZP_SAV_A
        ; Toets '1'..'8': Selecteer Sprite Slot 1..8!
        CMP #'1'
        BCC EKH_SPEC
        CMP #'9'
        BCS EKH_SPEC
        SEC
        SBC #'1'
        STA CUR_SLOT
        JSR SWITCH_SPRITE_SLOT
        JMP MAIN_LOOP

EKH_SPEC:
        CMP #' '                ; Spatie of Enter = Zet pixel met huidige kleur!
        BEQ DO_PLOT_PIXEL
        CMP #$0D
        BEQ DO_PLOT_PIXEL
        CMP #$08                ; Backspace = Gum pixel (Transparant $E3)
        BEQ DO_ERASE_PIXEL
        CMP #$7F
        BEQ DO_ERASE_PIXEL
        CMP #$09                ; TAB = Volgende kleur
        BEQ DO_NEXT_COL
        CMP #'.'                ; . = Volgende kleur
        BEQ DO_NEXT_COL
        CMP #','                ; , = Vorige kleur
        BEQ DO_PREV_COL
        CMP #'['                ; [ = Vorige sprite slot
        BEQ DO_PREV_SLOT
        CMP #']'                ; ] = Volgende sprite slot
        BEQ DO_NEXT_SLOT

        AND #$DF                ; Maak hoofdletter
        CMP #'X'                ; X = Gum pixel (Transparant $E3)
        BEQ DO_ERASE_PIXEL
        CMP #'K'                ; K = Volgende kleur
        BEQ DO_NEXT_COL
        CMP #'I'                ; I = Pipet (pak kleur onder cursor)
        BEQ DO_EYEDROPPER
        CMP #'F'                ; F = Flood Fill / Vlakvulling
        BEQ DO_FLOOD_FILL
        CMP #'M'                ; M = Spiegel Horizontaal (Mirror X)
        BEQ DO_MIRROR_H
        CMP #'V'                ; V = Spiegel Verticaal (Flip Y)
        BEQ DO_FLIP_V
        CMP #'R'                ; R = Roteer 90 graden met de klok mee
        BEQ DO_ROTATE_90
        CMP #'C'                ; C = Kopieer sprite naar klembord
        BEQ DO_COPY_SPR
        CMP #'P'                ; P = Plak klembord in huidige sprite
        BEQ DO_PASTE_SPR
        CMP #'N'                ; N = Wis huidige sprite (transparant)
        BEQ DO_CLEAR_SPR
        CMP #'G'                ; G = Zet Live Animatie AAN/UIT
        BEQ DO_TOGGLE_ANIM
        JMP MAIN_LOOP

; --- Pixel Tekenen & Gummen ---
DO_PLOT_PIXEL:
        LDX CUR_COL_IDX
        LDA PALETTE_16,X
        JMP SET_CUR_PIXEL

DO_ERASE_PIXEL:
        LDA #$E3                ; $E3 = Transparant in MiniGPU!
SET_CUR_PIXEL:
        PHA
        JSR GET_CUR_SPR_PTR
        JSR GET_CUR_PIXEL_OFFSET
        PLA
        STA (ZP_SPR_LO),Y
        ; Werk zowel de ingezoomde cel als de echte Hardware Sprite bij!
        LDX CUR_X
        LDY CUR_Y
        JSR DRAW_GRID_CELL
        JSR SYNC_CUR_SPRITE_PREVIEW
        JMP MAIN_LOOP

; --- Kleurenpalet & Pipet ---
DO_PREV_COL:
        DEC CUR_COL_IDX
        LDA CUR_COL_IDX
        AND #15
        STA CUR_COL_IDX
        JSR DRAW_PALETTE_PANEL
        JSR UPDATE_STATUS_BAR
        JMP MAIN_LOOP

NEXT_PALETTE_COL:
        INC CUR_COL_IDX
        LDA CUR_COL_IDX
        AND #15
        STA CUR_COL_IDX
        JSR DRAW_PALETTE_PANEL
        JMP UPDATE_STATUS_BAR

DO_EYEDROPPER:
        JSR GET_CUR_SPR_PTR
        JSR GET_CUR_PIXEL_OFFSET
        LDA (ZP_SPR_LO),Y
        LDX #15
DEY_LP:
        CMP PALETTE_16,X
        BEQ DEY_FOUND
        DEX
        BPL DEY_LP
        JMP MAIN_LOOP
DEY_FOUND:
        STX CUR_COL_IDX
        JSR DRAW_PALETTE_PANEL
        JSR UPDATE_STATUS_BAR
        LDA #<STR_MSG_PICK
        LDY #>STR_MSG_PICK
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; --- Wissel Sprite Slot (1..8) ---
DO_PREV_SLOT:
        DEC CUR_SLOT
        LDA CUR_SLOT
        AND #7
        STA CUR_SLOT
        JSR SWITCH_SPRITE_SLOT
        JMP MAIN_LOOP

DO_NEXT_SLOT:
        INC CUR_SLOT
        LDA CUR_SLOT
        AND #7
        STA CUR_SLOT
        JSR SWITCH_SPRITE_SLOT
        JMP MAIN_LOOP

SWITCH_SPRITE_SLOT:
        JSR DRAW_SLOT_TABS
        JSR DRAW_ALL_GRID_CELLS
        JSR DRAW_PREVIEW_SPRITES
        JMP UPDATE_STATUS_BAR

DO_TOGGLE_ANIM:
        LDA ANIM_ON
        EOR #1
        STA ANIM_ON
        JSR DRAW_ANIM_SPRITE
        JMP MAIN_LOOP

; ============================================================================
; Geavanceerde Sprite-Transformaties: Vlakvulling, Spiegelen, Roteren, Klembord
; ============================================================================
; 1. Vlakvulling (vervang alle pixels met dezelfde kleur als onder de cursor)
DO_FLOOD_FILL:
        JSR GET_CUR_SPR_PTR
        JSR GET_CUR_PIXEL_OFFSET
        LDA (ZP_SPR_LO),Y
        STA TARGET_COL
        LDX CUR_COL_IDX
        LDA PALETTE_16,X
        STA NEW_COL
        CMP TARGET_COL
        BEQ DFF_DONE
        LDY #0
DFF_LP:
        LDA (ZP_SPR_LO),Y
        CMP TARGET_COL
        BNE DFF_NXT
        LDA NEW_COL
        STA (ZP_SPR_LO),Y
DFF_NXT:
        INY
        BNE DFF_LP
        LDA #<STR_MSG_FILL
        LDY #>STR_MSG_FILL
        JMP FINISH_SPR_TRANSFORM
DFF_DONE:
        JMP MAIN_LOOP

; 2. Horizontaal Spiegelen (links <-> rechts per rij)
DO_MIRROR_H:
        JSR GET_CUR_SPR_PTR
        LDA #0
        STA ZP_ITER_Y
DMH_ROW:
        LDA ZP_ITER_Y
        ASL A
        ASL A
        ASL A
        ASL A
        STA ZP_SAV_A            ; Rij-offset = Y * 16
        LDX #0
DMH_COL:
        TXA
        CLC
        ADC ZP_SAV_A
        TAY
        LDA (ZP_SPR_LO),Y
        PHA                     ; Bewaar pixel (X, Y)
        TXA
        EOR #15
        CLC
        ADC ZP_SAV_A
        TAY
        LDA (ZP_SPR_LO),Y       ; Lees pixel (15-X, Y)
        STA TARGET_COL
        PLA
        STA (ZP_SPR_LO),Y       ; Schrijf oude (X,Y) naar (15-X,Y)
        TXA
        CLC
        ADC ZP_SAV_A
        TAY
        LDA TARGET_COL
        STA (ZP_SPR_LO),Y       ; Schrijf oude (15-X,Y) naar (X,Y)
        INX
        CPX #8
        BCC DMH_COL
        INC ZP_ITER_Y
        LDA ZP_ITER_Y
        CMP #16
        BCC DMH_ROW
        LDA #<STR_MSG_MIRROR
        LDY #>STR_MSG_MIRROR
        JMP FINISH_SPR_TRANSFORM

; 3. Verticaal Spiegelen (boven <-> onder)
DO_FLIP_V:
        JSR GET_CUR_SPR_PTR
        LDA #0
        STA ZP_ITER_Y
DFV_ROW:
        LDA ZP_ITER_Y
        ASL A
        ASL A
        ASL A
        ASL A
        STA ZP_SAV_A            ; Bovenste rij = Y * 16
        LDA ZP_ITER_Y
        EOR #15
        ASL A
        ASL A
        ASL A
        ASL A
        STA ZP_SAV_X            ; Onderste rij = (15-Y) * 16
        LDX #0
DFV_COL:
        TXA
        CLC
        ADC ZP_SAV_A
        TAY
        LDA (ZP_SPR_LO),Y
        PHA
        TXA
        CLC
        ADC ZP_SAV_X
        TAY
        LDA (ZP_SPR_LO),Y
        STA TARGET_COL
        PLA
        STA (ZP_SPR_LO),Y
        TXA
        CLC
        ADC ZP_SAV_A
        TAY
        LDA TARGET_COL
        STA (ZP_SPR_LO),Y
        INX
        CPX #16
        BCC DFV_COL
        INC ZP_ITER_Y
        LDA ZP_ITER_Y
        CMP #8
        BCC DFV_ROW
        LDA #<STR_MSG_MIRROR
        LDY #>STR_MSG_MIRROR
        JMP FINISH_SPR_TRANSFORM

; 4. Roteer 90 graden met de klok mee: Nieuwe (15-Y, X) = Oude (X, Y)
DO_ROTATE_90:
        JSR GET_CUR_SPR_PTR
        LDA #0
        STA ZP_ITER_Y
DR9_Y:
        LDA #0
        STA ZP_ITER_X
DR9_X:
        ; Lees oude pixel op Y = ZP_ITER_Y*16 + ZP_ITER_X
        LDA ZP_ITER_Y
        ASL A
        ASL A
        ASL A
        ASL A
        ORA ZP_ITER_X
        TAY
        LDA (ZP_SPR_LO),Y
        PHA
        ; Schrijf naar TEMP_RAM op offset = ZP_ITER_X*16 + (15 - ZP_ITER_Y)
        LDA ZP_ITER_Y
        EOR #15
        STA ZP_SAV_A
        LDA ZP_ITER_X
        ASL A
        ASL A
        ASL A
        ASL A
        ORA ZP_SAV_A
        TAX
        PLA
        STA TEMP_RAM,X
        INC ZP_ITER_X
        LDA ZP_ITER_X
        CMP #16
        BCC DR9_X
        INC ZP_ITER_Y
        LDA ZP_ITER_Y
        CMP #16
        BCC DR9_Y

        ; Kopieer TEMP_RAM terug naar huidige sprite
        LDY #0
DR9_CP:
        LDA TEMP_RAM,Y
        STA (ZP_SPR_LO),Y
        INY
        BNE DR9_CP
        LDA #<STR_MSG_ROT
        LDY #>STR_MSG_ROT
        JMP FINISH_SPR_TRANSFORM

; 5. Kopieer / Plak / Wis huidige sprite
DO_COPY_SPR:
        JSR GET_CUR_SPR_PTR
        LDY #0
DCS_LP:
        LDA (ZP_SPR_LO),Y
        STA CLIP_RAM,Y
        INY
        BNE DCS_LP
        LDA #<STR_MSG_COPY
        LDY #>STR_MSG_COPY
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

DO_PASTE_SPR:
        JSR GET_CUR_SPR_PTR
        LDY #0
DPS_LP:
        LDA CLIP_RAM,Y
        STA (ZP_SPR_LO),Y
        INY
        BNE DPS_LP
        LDA #<STR_MSG_PASTE
        LDY #>STR_MSG_PASTE
        JMP FINISH_SPR_TRANSFORM

DO_CLEAR_SPR:
        JSR GET_CUR_SPR_PTR
        LDY #0
        LDA #$E3                ; Transparant
DCLS_LP:
        STA (ZP_SPR_LO),Y
        INY
        BNE DCLS_LP
        LDA #<STR_MSG_CLEAR
        LDY #>STR_MSG_CLEAR
FINISH_SPR_TRANSFORM:
        PHA
        TYA
        PHA
        JSR DRAW_ALL_GRID_CELLS
        JSR SYNC_CUR_SPRITE_PREVIEW
        PLA
        TAY
        PLA
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; ============================================================================
; Top Menu Balk (geopend met ESC)
; ============================================================================
OPEN_ESC_MENU:
        LDA #1
        STA MENU_OPEN
        LDX #0                  ; Rect 0: Gele menubalk (0, 16, 640, 16, $FC)
        JSR SEND_RECT_10
        LDA #<STR_ESC_MENU
        LDY #>STR_ESC_MENU
        JMP DRAW_BAR_TEXT

CLOSE_ESC_MENU:
        LDA #0
        STA MENU_OPEN
        JSR DRAW_TOOLBAR
        LDA #<STR_MSG_READY
        LDY #>STR_MSG_READY
        JMP SHOW_STATUS_MSG

MENU_KEY_HANDLER:
        LDA ZP_SAV_A
        CMP #' '
        BEQ CEM_JMP
        CMP #$0D
        BEQ CEM_JMP
        CMP #'1'
        BEQ MENU_CLEAR_SPR
        CMP #'2'
        BEQ MENU_LOAD_DEMO
        CMP #'3'
        BEQ MENU_SAVE_SD
        CMP #'4'
        BEQ MENU_LOAD_SD
        CMP #'5'
        BEQ MENU_MIRROR
        CMP #'6'
        BEQ MENU_ROTATE

        AND #$DF
        CMP #'Q'
        BNE MKH_1
        JMP EXIT_TO_MC
MKH_1:  CMP #'N'
        BEQ MENU_CLEAR_SPR
        CMP #'D'
        BEQ MENU_LOAD_DEMO
        CMP #'S'
        BEQ MENU_SAVE_SD
        CMP #'L'
        BEQ MENU_LOAD_SD
        JMP MAIN_LOOP

CEM_JMP:
        JSR CLOSE_ESC_MENU
        JMP MAIN_LOOP

MENU_CLEAR_SPR:
        JSR CLOSE_ESC_MENU
        JMP DO_CLEAR_SPR

MENU_MIRROR:
        JSR CLOSE_ESC_MENU
        JMP DO_MIRROR_H

MENU_ROTATE:
        JSR CLOSE_ESC_MENU
        JMP DO_ROTATE_90

MENU_LOAD_DEMO:
        LDA #0
        STA MENU_OPEN
        JSR LOAD_DEMO_SPRITES
        JMP FINISH_BANK_LOAD

MENU_SAVE_SD:
        JSR CLOSE_ESC_MENU
        JSR SAVE_SPRITES_SD
        LDA #<STR_MSG_SAVED
        LDY #>STR_MSG_SAVED
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

MENU_LOAD_SD:
        LDA #0
        STA MENU_OPEN
        JSR LOAD_SPRITES_SD
FINISH_BANK_LOAD:
        JSR UPLOAD_ALL_HW_SPRITES
        JSR FULL_REDRAW
        LDA #<STR_MSG_LOADED
        LDY #>STR_MSG_LOADED
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

; ============================================================================
; SD-Kaart Opslag & Laden van alle 8 Sprites ($6000..$67FF -> Sectors $03F0..$03F3)
; ============================================================================
PREP_SD_BANK:
        JSR ROM_SD_INIT
        LDA #$F0
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDA #$00
        STA ZP_DST
        LDA #$60
        STA ZP_DST+1
        LDX #4                  ; 4 sectoren = 2048 bytes (8 sprites x 256B)
        RTS

SAVE_SPRITES_SD:
        JSR PREP_SD_BANK
SSS_LP:
        TXA
        PHA
        JSR ROM_WRITE_SEC
        PLA
        TAX
        DEX
        BNE SSS_LP
        RTS

LOAD_SPRITES_SD:
        JSR PREP_SD_BANK
LSS_LP:
        TXA
        PHA
        JSR ROM_READ_SEC
        PLA
        TAX
        DEX
        BNE LSS_LP
        LDA #$5A
        STA SPR_MAGIC
        RTS

; ============================================================================
; Scherm Opbouw: 16x16 Zoom-Grid + 16-Kleuren Palet + Hardware Sprite Preview
; ============================================================================
FULL_REDRAW:
        LDX #0
FR_GUI_LP:
        LDA SPREDIT_GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #SPREDIT_GUI_STREAM_END - SPREDIT_GUI_STREAM
        BCC FR_GUI_LP

        JSR DRAW_TOOLBAR

        ; Teken vaste paneel-titels en sneltoets-legende
        LDA #<SPREDIT_TEXT_TBL
        STA ZP_PTR_LO
        LDA #>SPREDIT_TEXT_TBL
        STA ZP_PTR_HI
FR_TXT_LP:
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #$FF
        BEQ FR_PANELS
        JSR DRAW_NEXT_POS_STR
        JMP FR_TXT_LP

FR_PANELS:
        JSR DRAW_PALETTE_PANEL
        JSR DRAW_SLOT_TABS
        JSR DRAW_ALL_GRID_CELLS
        JSR DRAW_PREVIEW_SPRITES
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

; Teken alle 256 cellen van het 16x16 Zoom-Grid (X = 20..275, Y = 56..311)
DRAW_ALL_GRID_CELLS:
        LDA #0
        STA ZP_ITER_Y
DAGC_Y:
        LDA #0
        STA ZP_ITER_X
DAGC_X:
        LDX ZP_ITER_X
        LDY ZP_ITER_Y
        JSR DRAW_GRID_CELL
        INC ZP_ITER_X
        LDA ZP_ITER_X
        CMP #16
        BCC DAGC_X
        INC ZP_ITER_Y
        LDA ZP_ITER_Y
        CMP #16
        BCC DAGC_Y
        RTS

; Teken één cel (X = 0..15, Y = 0..15) in het 16x16 Zoom-Grid
; Elke cel is 16x16 px op scherm: scherm_X = 20 + X*16, scherm_Y = 56 + Y*16
DRAW_GRID_CELL:
        STX ZP_SAV_A            ; kolom X (0..15)
        STY ZP_SAV_X            ; rij Y (0..15)
        JSR GET_CUR_SPR_PTR
        LDA ZP_SAV_X
        ASL A
        ASL A
        ASL A
        ASL A
        ORA ZP_SAV_A
        TAY
        LDA (ZP_SPR_LO),Y
        STA ZP_FG_COL           ; De daadwerkelijke sprite-pixelkleur!

        ; Bereken 16-bit scherm-X = 20 + X*16
        LDA ZP_SAV_A
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #20
        STA ZP_X_LO
        LDA #0
        ADC #0
        STA ZP_X_HI

        ; Bereken 16-bit scherm-Y = 56 + Y*16
        LDA ZP_SAV_X
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #56
        STA ZP_Y_LO
        LDA #0
        ADC #0
        STA ZP_Y_HI

        ; Is dit de huidige cursor-positie (CUR_X, CUR_Y)?
        ; Zo ja, teken een wit/geel kader (15x15) eromheen, anders donkergrijs ($24)
        LDA #$24
        LDX ZP_SAV_A
        CPX CUR_X
        BNE DGC_OUTER
        LDY ZP_SAV_X
        CPY CUR_Y
        BNE DGC_OUTER
        LDA #$FF                ; Helder wit kader om de geselecteerde pixel!
DGC_OUTER:
        STA ZP_BG_COL
        LDA #15
        JSR DRAW_SQUARE_AT_XY

        ; Teken binnenin de cel (X+1, Y+1, 13x13) de pixelkleur (of dambord-patroon als $E3 transparant!)
        INC ZP_X_LO
        BNE DGC_1
        INC ZP_X_HI
DGC_1:  INC ZP_Y_LO
        BNE DGC_2
        INC ZP_Y_HI
DGC_2:
        LDA ZP_FG_COL
        CMP #$E3
        BNE DGC_SOLID
        ; Transparante pixel ($E3): toon donkerblauw/grijs ($49) zodat het zichtbaar leeg is
        LDA #$49
DGC_SOLID:
        STA ZP_BG_COL
        LDA #13
        JSR DRAW_SQUARE_AT_XY

        ; Als de pixel transparant ($E3) is, zet een klein stipje in het midden (X+5, Y+5, 3x3, $24)
        LDA ZP_FG_COL
        CMP #$E3
        BNE DGC_RTS
        CLC
        LDA ZP_X_LO
        ADC #5
        STA ZP_X_LO
        BCC DGC_3
        INC ZP_X_HI
DGC_3:  CLC
        LDA ZP_Y_LO
        ADC #5
        STA ZP_Y_LO
        BCC DGC_4
        INC ZP_Y_HI
DGC_4:  LDA #$24
        STA ZP_BG_COL
        LDA #3
        JMP DRAW_SQUARE_AT_XY
DGC_RTS:
        RTS

; Hulproutine: teken vierkant van A x A pixels op (ZP_X_LO/HI, ZP_Y_LO/HI) met kleur ZP_BG_COL
DRAW_SQUARE_AT_XY:
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
        PHA
        STA IO_GPU
        LDA #0
        STA IO_GPU
        PLA
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_BG_COL
        STA IO_GPU
        RTS

; ============================================================================
; Middenpaneel: 16-Kleuren RGB332 Palet (X = 296..440, Y = 56..196)
; ============================================================================
DRAW_PALETTE_PANEL:
        LDA #0
        STA ZP_ITER_X
DPP_LP:
        LDX ZP_ITER_X
        ; 4x4 kleuren-grid: col = X & 3, row = X >> 2
        TXA
        AND #3
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A                   ; * 32 px breed per kleurvak
        CLC
        ADC #<302
        STA ZP_X_LO
        LDA #>302
        ADC #0
        STA ZP_X_HI

        TXA
        LSR A
        LSR A
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A                   ; * 32 px hoog per rij
        CLC
        ADC #60
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        ; Rand om kleurvak: Geel ($FC) als dit CUR_COL_IDX is, anders donkergrijs ($49)
        LDA #$49
        CPX CUR_COL_IDX
        BNE DPP_BRD
        LDA #$FC
DPP_BRD:
        STA ZP_BG_COL
        LDA #28
        JSR DRAW_SQUARE_AT_XY

        ; Binnenkant van het kleurvak (24x24 px)
        CLC
        LDA ZP_X_LO
        ADC #2
        STA ZP_X_LO
        BCC DPP_1
        INC ZP_X_HI
DPP_1:  CLC
        LDA ZP_Y_LO
        ADC #2
        STA ZP_Y_LO
        LDX ZP_ITER_X
        LDA PALETTE_16,X
        CMP #$E3
        BNE DPP_COL_OK
        LDA #$49                ; Transparant vakje (kleur 0)
DPP_COL_OK:
        STA ZP_BG_COL
        LDA #24
        JSR DRAW_SQUARE_AT_XY

        ; Als het kleur 0 ($E3 = Transparant) is: zet een 'T' in het vakje!
        LDX ZP_ITER_X
        BNE DPP_NXT
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DPP_T1
        INC ZP_X_HI
DPP_T1: CLC
        LDA ZP_Y_LO
        ADC #8
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_FG_COL
        LDA #'T'
        JSR DRAW_CHAR_ADV

DPP_NXT:
        INC ZP_ITER_X
        LDA ZP_ITER_X
        CMP #16
        BCC DPP_LP
        RTS

; ============================================================================
; Rechterpaneel: Echte Hardware Sprite Preview + 2x Zoom + 8 Slot Tabs
; ============================================================================
; Synchroniseer huidige sprite naar FPGA BRAM en ververs de previews
SYNC_CUR_SPRITE_PREVIEW:
        LDA CUR_SLOT
        JSR UPLOAD_ONE_HW_SPRITE
        JMP DRAW_PREVIEW_SPRITES

UPLOAD_ALL_HW_SPRITES:
        LDA #0
        STA ZP_ITER_X
UAHS_LP:
        LDA ZP_ITER_X
        JSR UPLOAD_ONE_HW_SPRITE
        INC ZP_ITER_X
        LDA ZP_ITER_X
        CMP #8
        BCC UAHS_LP
        RTS

; Upload sprite-slot A (0..7) naar FPGA Hardware Sprite ID (24 + A) via GPU Cmd 9
UPLOAD_ONE_HW_SPRITE:
        PHA
        CLC
        ADC #$60                ; $6000 + slot * $0100
        STA ZP_SPR_HI
        LDA #0
        STA ZP_SPR_LO
        LDA #9                  ; GPU Cmd 9 = DEF SPRITE (256 bytes)
        STA IO_GPU
        PLA
        CLC
        ADC #HW_SPR_BASE
        STA IO_GPU
        LDY #0
UOHS_LP:
        LDA (ZP_SPR_LO),Y
        STA IO_GPU
        INY
        BNE UOHS_LP
        RTS

; Teken de Echte Hardware Sprites (1x Normaal + Live Animatie) én de 2x Zoom + 2x Spiegel Preview!
DRAW_PREVIEW_SPRITES:
        ; Wis preview-vensters: RECT(464, 56, 156, 80, $00)
        LDX #40
        JSR SEND_RECT_10

        ; 1. Teken Echte 16x16 Hardware Sprite op (488, 66) via GPU Cmd 10!
        LDA CUR_SLOT
        CLC
        ADC #HW_SPR_BASE
        LDX #<488
        LDY #>488
        JSR SEND_HW_SPRITE_66

        ; 2. Teken de Live Animatie Hardware Sprite op (586, 66) via GPU Cmd 10!
        JSR DRAW_ANIM_SPRITE

        ; 3. Teken 2x Vergrote Preview (32x32 px) op (480, 94) én 2x Gespiegelde Preview op (534, 94)!
        JSR GET_CUR_SPR_PTR
        LDA #0
        STA ZP_ITER_Y
DPS_Y:
        LDA #0
        STA ZP_ITER_X
DPS_X:
        LDA ZP_ITER_Y
        ASL A
        ASL A
        ASL A
        ASL A
        ORA ZP_ITER_X
        TAY
        LDA (ZP_SPR_LO),Y
        CMP #$E3
        BEQ DPS_SKIP            ; Transparant -> laat zwarte achtergrond staan
        STA ZP_BG_COL

        ; Bereken Y = 94 + ZP_ITER_Y * 2
        LDA ZP_ITER_Y
        ASL A
        CLC
        ADC #94
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        ; Normale 2x Zoom op X = 480 + ZP_ITER_X * 2
        LDA ZP_ITER_X
        ASL A
        CLC
        ADC #<480
        STA ZP_X_LO
        LDA #>480
        ADC #0
        STA ZP_X_HI
        LDA #2
        JSR DRAW_SQUARE_AT_XY

        ; Horizontaal Gespiegelde 2x Zoom op X = 534 + (15 - ZP_ITER_X) * 2
        LDA ZP_ITER_X
        EOR #15
        ASL A
        CLC
        ADC #<534
        STA ZP_X_LO
        LDA #>534
        ADC #0
        STA ZP_X_HI
        LDA #2
        JSR DRAW_SQUARE_AT_XY

DPS_SKIP:
        INC ZP_ITER_X
        LDA ZP_ITER_X
        CMP #16
        BCC DPS_X
        INC ZP_ITER_Y
        LDA ZP_ITER_Y
        CMP #16
        BCC DPS_Y
        RTS

; Stuur GPU Cmd 10 = SPRITE (exact 10 bytes: 10, X_lo, X_hi, Y_lo, Y_hi, 0, 0, 0, 0, spr_id) op Y=66
SEND_HW_SPRITE_66:
        PHA
        LDA #10                 ; GPU Cmd 10 = DRAW_SPRITE (10 bytes!)
        STA IO_GPU
        STX IO_GPU              ; X_LO
        STY IO_GPU              ; X_HI
        LDA #66                 ; Y_LO = 66
        STA IO_GPU
        LDA #0                  ; Y_HI = 0 + 4 opvulbytes (0, 0, 0, 0)
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        PLA
        STA IO_GPU              ; Sprite ID (24..31)
        RTS

DRAW_ANIM_SPRITE:
        ; Wis animatie-vakje op (580, 62, 28, 24, $00) en teken wisselend huidige sprite <-> buur-slot!
        LDX #50
        JSR SEND_RECT_10
        LDA ANIM_FRAME
        AND #1
        EOR CUR_SLOT            ; Wisselt tussen huidige sprite en zijn buur-frame (Slot 1 <-> Slot 2)!
        CLC
        ADC #HW_SPR_BASE
        LDX #<586
        LDY #>586
        JMP SEND_HW_SPRITE_66

HIDE_PREVIEW_SPRITES:
        ; Veeg het scherm schoon bij afsluiten naar MC
        LDA #1
        STA IO_GPU
        LDA #$00
        STA IO_GPU
        RTS

; Teken de 8 Sprite-Slot Knoppen [1]..[8] (X = 464..620, Y = 168..224)
DRAW_SLOT_TABS:
        LDA #0
        STA ZP_ITER_X
DST_LP:
        LDX ZP_ITER_X
        TXA
        AND #3
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #<468
        STA ZP_X_LO
        LDA #>468
        ADC #0
        STA ZP_X_HI

        TXA
        LSR A
        LSR A
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #170
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        LDA #$49
        CPX CUR_SLOT
        BNE DST_BG
        LDA #$FC                ; Actieve sprite-slot = Geel ($FC)!
DST_BG:
        STA ZP_BG_COL
        LDA #26
        JSR DRAW_SQUARE_AT_XY

        CLC
        LDA ZP_X_LO
        ADC #9
        STA ZP_X_LO
        BCC DST_1
        INC ZP_X_HI
DST_1:  CLC
        LDA ZP_Y_LO
        ADC #9
        STA ZP_Y_LO
        LDA #$00
        LDX ZP_ITER_X
        CPX CUR_SLOT
        BEQ DST_FG
        LDA #$FF
DST_FG:
        STA ZP_FG_COL
        TXA
        CLC
        ADC #'1'
        JSR DRAW_CHAR_ADV

        INC ZP_ITER_X
        LDA ZP_ITER_X
        CMP #8
        BCC DST_LP
        RTS

; ============================================================================
; Statusbalk onderaan (Y = 342..359)
; ============================================================================
UPDATE_STATUS_BAR:
        LDX #20                 ; Rect 20: Wis linker statusveld (8, 344, 420, 14, $42)
        JSR SEND_RECT_10

        LDA #<STR_ST_SPR
        LDY #>STR_ST_SPR
        JSR DRAW_POS_STR

        LDA CUR_SLOT
        CLC
        ADC #'1'
        JSR DRAW_CHAR_ADV

        LDA #<STR_ST_XY
        STA ZP_PTR_LO
        LDA #>STR_ST_XY
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR

        LDA CUR_X
        JSR DRAW_DEC2
        LDA #','
        JSR DRAW_CHAR_ADV
        LDA CUR_Y
        JSR DRAW_DEC2

        LDA #<STR_ST_COL
        STA ZP_PTR_LO
        LDA #>STR_ST_COL
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR

        LDX CUR_COL_IDX
        LDA PALETTE_16,X
        JSR DRAW_HEX2
        RTS

SHOW_STATUS_MSG:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDX #30                 ; Rect 30: Wis rechter statusveld (436, 344, 198, 14, $42)
        JSR SEND_RECT_10

        LDA #$B8                ; 440 = $01B8
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #$5B                ; 347 = $015B
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_FG_COL
        JMP DRAW_ZP_STR

; ============================================================================
; Hulproutines & 4 Voorbeeld-Sprites in SDRAM ($6000..$67FF)
; ============================================================================
SAVE_OLD_XY:
        LDA CUR_X
        STA OLD_X
        LDA CUR_Y
        STA OLD_Y
        RTS

GET_CUR_SPR_PTR:
        LDA CUR_SLOT
        CLC
        ADC #$60
        STA ZP_SPR_HI
        LDA #0
        STA ZP_SPR_LO
        RTS

GET_CUR_PIXEL_OFFSET:
        LDA CUR_Y
        ASL A
        ASL A
        ASL A
        ASL A
        ORA CUR_X
        TAY
        RTS

; Laad 4 kleurrijke 16x16 Demo-Sprites in Slots 1..4 (en maak 5..8 transparant)
LOAD_DEMO_SPRITES:
        ; Vul eerst alle 8 sprites ($6000..$67FF) en CLIP_RAM ($6900) met $E3 (Transparant)
        LDA #$60
        STA ZP_SPR_HI
        LDA #0
        STA ZP_SPR_LO
        TAY
        LDA #$E3
        LDX #10
LDS_CLR:
        STA (ZP_SPR_LO),Y
        INY
        BNE LDS_CLR
        INC ZP_SPR_HI
        DEX
        BNE LDS_CLR

        ; Pak de 4 compacte 16x16 2-bpp / 1-bpp demo-patronen uit naar Slots 0..3 ($6000..$63FF)
        LDA #0
        STA ZP_ITER_X           ; Slot 0..3
LDS_SLOT_LP:
        LDX ZP_ITER_X
        TXA
        CLC
        ADC #$60
        STA ZP_SPR_HI
        LDA #0
        STA ZP_SPR_LO

        LDA DEMO_SPR_PTR_LO,X
        STA ZP_PTR_LO
        LDA DEMO_SPR_PTR_HI,X
        STA ZP_PTR_HI
        LDA DEMO_SPR_COL,X
        STA TARGET_COL

        LDY #0                  ; Pixel-index 0..255
LDS_ROW_LP:
        STY ZP_ITER_Y
        JSR NEXT_PTR_BYTE       ; Lees 8 bits van rij (32 bytes = 256 pixels)
        LDY ZP_ITER_Y
        STA ZP_SAV_A
        LDX #8
LDS_B1:
        ASL ZP_SAV_A
        LDA #$E3
        BCC LDS_W1
        LDA TARGET_COL
LDS_W1: STA (ZP_SPR_LO),Y
        INY
        DEX
        BNE LDS_B1

        CPY #0
        BNE LDS_ROW_LP

        INC ZP_ITER_X
        LDA ZP_ITER_X
        CMP #4
        BCC LDS_SLOT_LP

        ; Geef Slot 3 (Blinky spook op $6200) witte ogen ($FF) en blauwe pupillen ($03)!
        LDA #$FF
        STA $6244
        STA $6245
        STA $624A
        STA $624B
        STA $6254
        STA $625A
        LDA #$03
        STA $6255
        STA $625B

        LDA #$5A
        STA SPR_MAGIC
        RTS

SEND_RECT_10:
        LDY #10
SR10_LP:
        LDA UI_RECT_TBL,X
        STA IO_GPU
        INX
        DEY
        BNE SR10_LP
        RTS

DRAW_POS_STR:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DRAW_NEXT_POS_STR:
        LDX #0
DPS2_LP:
        JSR NEXT_PTR_BYTE
        STA ZP_X_LO,X
        INX
        CPX #5
        BCC DPS2_LP
        JMP DRAW_ZP_STR

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

DRAW_HEX2:
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
        ADC #('A' - 11)
        JMP DRAW_CHAR_ADV
DHN_DIG:
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
; Tabellen, 16-Kleuren RGB332 Palet, GUI Streams & 4 Demo-Sprites
; ============================================================================
; 16 Kleuren: 0=Transparant($E3), 1=Zwart, 2=Wit, 3=Geel, 4=Oranje, 5=Rood,
; 6=Donkerrood, 7=Roze, 8=Paars, 9=Blauw, 10=Cyaan, 11=Groen, 12=Donkergroen,
; 13=Goud/Huid, 14=Lichtgrijs, 15=Donkergrijs
PALETTE_16:
        .BYTE $E3, $00, $FF, $FC, $EC, $E0, $A0, $F3
        .BYTE $43, $03, $1F, $1C, $10, $B5, $B6, $49

GPU_INIT_STREAM:
        .BYTE 12, 1                     ; TARGET 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0   ; BIGSPR 0 uit
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0   ; BIGSPR 1 uit
        .BYTE 15, 0, 0, 0, 0            ; SCROLL 0, 0
GPU_INIT_STREAM_END:

SPREDIT_GUI_STREAM:
        ; Donker studio-bureaublad: RECT(0, 32, 640, 310, $24)
        .BYTE 2, 0,0, 32,0, $80,$02, $36,$01, $24
        ; Paars/Magenta PixelStudio Titelbalk: RECT(0, 0, 640, 16, $42)
        .BYTE 2, 0,0, 0,0, $80,$02, 16,0, $42
        ; Geel Sprite-icoon linksboven: RECT(8, 3, 10, 10, $FC)
        .BYTE 2, 8,0, 3,0, 10,0, 10,0, $FC
        ; Cyaan kader om het 16x16 Zoom-Grid links: RECT(18, 54, 260, 260, $1F)
        .BYTE 2, 18,0, 54,0, $04,$01, $04,$01, $1F
        ; Kader om het 16-Kleuren Palet midden: RECT(296, 54, 136, 136, $6D)
        .BYTE 2, $28,$01, 54,0, 136,0, 136,0, $6D
        ; Donkerblauw Sneltoets-paneel midden-onder: RECT(296, 198, 136, 116, $01)
        .BYTE 2, $28,$01, 198,0, 136,0, 116,0, $01
        ; Donkerblauw Sneltoets-paneel rechts-onder: RECT(462, 236, 160, 78, $01)
        .BYTE 2, $CE,$01, 236,0, 160,0, 78,0, $01
        ; Kader om Hardware Preview rechtsboven: RECT(462, 54, 160, 84, $1C)
        .BYTE 2, $CE,$01, 54,0, 160,0, 84,0, $1C
        ; Onderste Statusbalk: RECT(0, 342, 640, 18, $42)
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $42
SPREDIT_GUI_STREAM_END:

UI_RECT_TBL:
        ; Offset 0: Gele ESC-menubalk (0, 16, 640, 16, $FC)
        .BYTE 2, 0,0, 16,0, $80,$02, 16,0, $FC
        ; Offset 10: Grijze werkbalk (0, 16, 640, 16, $B6)
        .BYTE 2, 0,0, 16,0, $80,$02, 16,0, $B6
        ; Offset 20: Wis linker statusveld (8, 344, 420, 14, $42)
        .BYTE 2, 8,0, $58,$01, $A4,$01, 14,0, $42
        ; Offset 30: Wis rechter statusveld (436, 344, 198, 14, $42)
        .BYTE 2, $B4,$01, $58,$01, 198,0, 14,0, $42
        ; Offset 40: Wis Hardware Preview veld (464, 56, 156, 80, $00)
        .BYTE 2, $D0,$01, 56,0, 156,0, 80,0, $00
        ; Offset 50: Wis Animatie-vakje (580, 62, 28, 24, $00)
        .BYTE 2, $44,$02, 62,0, 28,0, 24,0, $00

SPREDIT_TEXT_TBL:
        .BYTE 24,0, 4,0, $FF, "PixelStudio 6502 - [16x16 HARDWARE SPRITE EDITOR]       MiniOffice", 0
        .BYTE 20,0, 42,0, $1F, "16x16 PIXEL CANVAS", 0
        .BYTE $28,$01, 42,0, $FC, "16-KLEUREN PALET", 0
        .BYTE $CE,$01, 42,0, $1C, "HARDWARE PREVIEW", 0
        .BYTE $D2,$01, 154,0, $FC, "SPRITE SLOTS [1..8]:", 0
        .BYTE $30,$01, 206,0, $FC, "GEREEDSCHAP:", 0
        .BYTE $30,$01, 222,0, $FF, "SPAT : Teken", 0
        .BYTE $30,$01, 236,0, $FF, "X/BS : Gum ($E3)", 0
        .BYTE $30,$01, 250,0, $1F, "I:Pipet  F:Fill", 0
        .BYTE $30,$01, $08,$01, $1C, "M:SpiegX V:FlipY", 0
        .BYTE $30,$01, $16,$01, $F3, "R:Roteer 90 gr.", 0
        .BYTE $30,$01, $24,$01, $FC, "C:Kopie  P:Plak", 0
        .BYTE $D4,$01, 246,0, $1F, "[ ]/1-8 : Slot", 0
        .BYTE $D4,$01, $08,$01, $1C, "G : Animatie", 0
        .BYTE $D4,$01, $1A,$01, $FC, "ESC : SD-Menu", 0
        .BYTE $FF

STR_TOOLBAR:
        .ASCIIZ "PIJL/WASD:Cursor SPAT:Zet X:Gum TAB:Kleur M:Spiegel R:Rot 1-8:Slot ESC"
STR_ESC_MENU:
        .ASCIIZ "[1]Wis [2]Demo [3]Opslaan SD [4]Laden SD [5]Spiegel [6]Rot [ESC/Q]MC"

STR_ST_SPR:     .BYTE 12,0, $5B,$01, $FF, "SPRITE:", 0
STR_ST_XY:      .ASCIIZ "/8 | X,Y:"
STR_ST_COL:     .ASCIIZ " | RGB:$"

STR_MSG_READY:  .ASCIIZ "SPAT=ZET X=GUM TAB=KLEUR"
STR_MSG_PICK:   .ASCIIZ "KLEUR OPGEPAKT (PIPET)!"
STR_MSG_FILL:   .ASCIIZ "VLAKVULLING UITGEVOERD!"
STR_MSG_MIRROR: .ASCIIZ "SPRITE GESPIEGELD!"
STR_MSG_ROT:    .ASCIIZ "90 GRADEN GEROTEERD!"
STR_MSG_COPY:   .ASCIIZ "GEKOPIEERD NAAR KLEMBORD"
STR_MSG_PASTE:  .ASCIIZ "GEPLAKT VANAF KLEMBORD!"
STR_MSG_CLEAR:  .ASCIIZ "SPRITE GEWIST ($E3)"
STR_MSG_SAVED:  .ASCIIZ "8 SPRITES OPGESLAGEN!"
STR_MSG_LOADED: .ASCIIZ "SPRITES GELADEN!"

; --- 4 Ingebouwde 16x16 Demo-Sprites (32 bytes per sprite = 16 rijen x 2 bytes) ---
DEMO_SPR_PTR_LO: .BYTE <DEMO_SPR1, <DEMO_SPR2, <DEMO_SPR3, <DEMO_SPR4
DEMO_SPR_PTR_HI: .BYTE >DEMO_SPR1, >DEMO_SPR2, >DEMO_SPR3, >DEMO_SPR4
DEMO_SPR_COL:    .BYTE $FC, $FC, $E0, $1F

; Slot 1: Pac-Man Open Mond ($FC Geel)
DEMO_SPR1:
        .BYTE $07,$E0, $1F,$F8, $3F,$FC, $7F,$FE, $7F,$C0, $FF,$00, $FE,$00, $FC,$00
        .BYTE $FE,$00, $FF,$00, $7F,$C0, $7F,$FE, $3F,$FC, $1F,$F8, $07,$E0, $00,$00

; Slot 2: Pac-Man Dicht / Stap 2 ($FC Geel - animeert met Slot 1!)
DEMO_SPR2:
        .BYTE $07,$E0, $1F,$F8, $3F,$FC, $7F,$FE, $7F,$FE, $FF,$FF, $FF,$F0, $FF,$80
        .BYTE $FF,$F0, $FF,$FF, $7F,$FE, $7F,$FE, $3F,$FC, $1F,$F8, $07,$E0, $00,$00

; Slot 3: Arcade Spook Blinky ($E0 Rood + witte/blauwe ogen)
DEMO_SPR3:
        .BYTE $07,$E0, $1F,$F8, $3F,$FC, $7F,$FE, $7F,$FE, $FF,$FF, $FF,$FF, $FF,$FF
        .BYTE $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $DD,$BB, $88,$11, $00,$00

; Slot 4: Space Invader Alien ($1F Cyaan)
DEMO_SPR4:
        .BYTE $08,$10, $04,$20, $0F,$F0, $1B,$D8, $3F,$FC, $2F,$F4, $28,$14, $06,$60
        .BYTE $00,$00, $0F,$F0, $19,$98, $3F,$FC, $2D,$B4, $20,$04, $08,$10, $00,$00
