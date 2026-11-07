; ============================================================================
; IMPRESS.asm - LibreImpress & Draw 6502 (Presentatie & Vector Tekenstudio)
; Geassembleerd op $8000 in SDRAM. Vector-objecten (max 32) op $7D00-$7EFF.
; Bevat 4 grafische presentatie-dia's (met Driehoeken, Cirkels, Diagrammen),
; een Dia-Overzichtspaneel links, Automatische Diavoorstelling (P), én een
; interactieve Vector Tekenstudio (R=Rechthoek, C=Cirkel, D=Driehoek, L=Lijn).
; Starten vanuit Midnight Commander (BRUN MC) of via: BRUN IMPRESS
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort
ROM_SILENCE     = $E8DC

; --- Eigen Zero Page Variabelen ($60..$7F) ---
ZP_PTR_LO       = $60           ; Algemene 16-bit pointer voor streams/tekst
ZP_PTR_HI       = $61
ZP_X_LO         = $62           ; 16-bit X voor GPU
ZP_X_HI         = $63
ZP_Y_LO         = $64           ; 16-bit Y voor GPU
ZP_Y_HI         = $65
ZP_FG_COL       = $66

CUR_SLIDE       = $67           ; Actieve dia (0..3 = Dia 1..4)
MENU_OPEN       = $68           ; 0 = Normaal, 1 = ESC-Menu geopend
AUTO_PLAY       = $69           ; 0 = Handmatig, 1 = Automatische Diashow actief
AUTO_TICKS      = $6A           ; Timer voor automatische dia-wissel
PREV_JOY        = $6B

CUR_X_LO        = $6C           ; Vector-cursor X (130..616)
CUR_X_HI        = $6D
CUR_Y_LO        = $6E           ; Vector-cursor Y (60..320)
CUR_Y_HI        = $6F
PREV_X_LO       = $70           ; Vorige punt voor Lijn-tool (L)
PREV_X_HI       = $71
PREV_Y_LO       = $72
PREV_Y_HI       = $73

DRAW_COL_IDX    = $74           ; Huidige tekenkleur-index (0..7)
DRAW_SIZE_IDX   = $75           ; Huidige vorm-grootte index (0..2 = 12, 22, 34 px)
ZP_ITER         = $76
ZP_SAV_A        = $77
ZP_SAV_X        = $78
ZP_SHP_LO       = $79
ZP_SHP_HI       = $7A
SHP_SZ          = $7B

; --- Vector Objecten Opslag in SDRAM ($7D00..$7EFF) ---
; Elk vector-object is 8 bytes:
;   +0: Type (1=RECT, 2=DISC/Cirkel, 3=TRI/Driehoek, 4=LINE)
;   +1: Kleur (RGB332)
;   +2..3: X (16-bit)
;   +4..5: Y (16-bit)
;   +6: Grootte / Radius (of X2_LO bij Lijn)
;   +7: Slide-nummer (0..3)
VEC_RAM         = $7D00
VEC_COUNT       = $7EFE         ; Aantal getekende vector-vormen (0..32)
VEC_MAGIC       = $7EFF         ; $5A als vector-geheugen al geïnitialiseerd is
MAX_VECS        = 32

; ============================================================================
; Startpunt ($8000)
; ============================================================================
START:
        LDA #12
        STA IO_TERM
        LDA #0
        STA IO_MODE
        STA CUR_SLIDE
        STA MENU_OPEN
        STA AUTO_PLAY
        STA AUTO_TICKS
        STA DRAW_COL_IDX        ; Kleur 0 = Geel ($FC)
        LDA #1
        STA DRAW_SIZE_IDX       ; Middelgrote vorm (20 px)

        ; Zet vector-cursor midden op het dia-canvas (X = 374 = $0176, Y = 190 = $00BE)
        LDA #$76
        STA CUR_X_LO
        STA PREV_X_LO
        LDA #$01
        STA CUR_X_HI
        STA PREV_X_HI
        LDA #190
        STA CUR_Y_LO
        STA PREV_Y_LO
        LDA #0
        STA CUR_Y_HI
        STA PREV_Y_HI

        JSR INIT_GPU

        ; Initialiseer vector-buffer bij eerste start met voorbeeld-figuren op Dia 4
        LDA VEC_MAGIC
        CMP #$5A
        BEQ VEC_READY
        JSR LOAD_DEMO_VECS
VEC_READY:
        JSR FULL_REDRAW
        LDA #<STR_MSG_WELCOME
        LDY #>STR_MSG_WELCOME
        JSR SHOW_STATUS_MSG

        LDA IO_JOY
        STA PREV_JOY

; ============================================================================
; Hoofdlus: Navigatie, Vector-Tekenen & Automatische Diavoorstelling
; ============================================================================
MAIN_LOOP:
        LDA #1
        JSR WAIT_10MS

        ; 1. Check of op ESC is gedrukt (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_AUTOPLAY
        LDA IO_TERM             ; Wis ESC uit IO_TERM
        LDA #0
        STA AUTO_PLAY
        LDA MENU_OPEN
        BNE EXIT_TO_MC          ; Nogmaals ESC in het menu = Terug naar MC!
        JSR OPEN_ESC_MENU
        JMP MAIN_LOOP

EXIT_TO_MC:
        JSR ROM_SILENCE
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

CHK_AUTOPLAY:
        LDA MENU_OPEN
        BNE CHK_KEY_CHAR

        ; Als Automatische Diavoorstelling (AUTO_PLAY == 1) aan staat: wissel elke 2.5 sec!
        LDA AUTO_PLAY
        BEQ CHK_CURSOR_MOVE
        INC AUTO_TICKS
        LDA AUTO_TICKS
        CMP #220
        BCC CHK_CURSOR_MOVE
        LDA #0
        STA AUTO_TICKS
        JSR NEXT_SLIDE
        JMP MAIN_LOOP

CHK_CURSOR_MOVE:
        ; 2. Houd PS/2 Pijltjes of WASD ingedrukt om de vector-cursor soepel te bewegen!
        LDA IO_JOY
        STA ZP_SAV_X
        AND #$0F                ; Richtingsknoppen (bits 0..3)
        BEQ CHK_JOY_EDGE

        ; Wis eventuele ASCII-echo uit IO_TERM tijdens pijl/WASD beweging
        LDA IO_STATUS
        AND #1
        BEQ DO_MOVE_CUR
        LDA IO_TERM
DO_MOVE_CUR:
        ; Wis oude cursor door huidige slide + vormen snel te verversen of teken cursor
        LDA ZP_SAV_X
        AND #1                  ; Omhoog
        BEQ DMC_DN
        JSR MOVE_CUR_UP
DMC_DN:
        LDA ZP_SAV_X
        AND #2                  ; Omlaag
        BEQ DMC_LT
        JSR MOVE_CUR_DOWN
DMC_LT:
        LDA ZP_SAV_X
        AND #4                  ; Links
        BEQ DMC_RT
        JSR MOVE_CUR_LEFT
DMC_RT:
        LDA ZP_SAV_X
        AND #8                  ; Rechts
        BEQ DMC_DONE
        JSR MOVE_CUR_RIGHT
DMC_DONE:
        JSR DRAW_ACTIVE_SLIDE
        JSR UPDATE_STATUS_BAR
        LDA ZP_SAV_X
        STA PREV_JOY
        JMP MAIN_LOOP

CHK_JOY_EDGE:
        ; Check TAB (bit 6) via flank-detectie voor kleurwissel
        LDA ZP_SAV_X
        TAX
        EOR PREV_JOY
        AND ZP_SAV_X
        STX PREV_JOY
        AND #$40
        BEQ CHK_KEY_CHAR
        JSR CYCLE_COLOR
        JMP MAIN_LOOP

CHK_KEY_CHAR:
        LDA IO_STATUS
        AND #1
        BEQ MAIN_LOOP_JMP
        LDA IO_TERM
        STA ZP_SAV_A
        LDA IO_JOY
        STA PREV_JOY

        LDA MENU_OPEN
        BEQ NORMAL_KEY_HANDLER
        JMP MENU_KEY_HANDLER
MAIN_LOOP_JMP:
        JMP MAIN_LOOP

; ============================================================================
; Sneltoetsen in Presentatie- & Tekenmodus
; ============================================================================
NORMAL_KEY_HANDLER:
        LDA ZP_SAV_A
        CMP #'1'
        BCC NKH_SPEC
        CMP #'5'
        BCS NKH_SPEC
        ; Toets '1'..'4': Spring direct naar Dia 1..4!
        SEC
        SBC #'1'
        STA CUR_SLIDE
        LDA #0
        STA AUTO_PLAY
        JSR UPDATE_SLIDE_VIEW
        JMP MAIN_LOOP

NKH_SPEC:
        CMP #'['
        BEQ DO_PREV_SLIDE
        CMP #']'
        BEQ DO_NEXT_SLIDE
        CMP #$09                ; TAB = Volgende kleur
        BEQ DO_CYCLE_COL
        CMP #'`'
        BEQ DO_CYCLE_COL
        CMP #'+'
        BEQ DO_CYCLE_SIZE
        CMP #'='
        BEQ DO_CYCLE_SIZE
        CMP #$08                ; Backspace = Undo laatste vorm
        BEQ DO_UNDO_VEC
        CMP #$7F
        BEQ DO_UNDO_VEC
        CMP #' '                ; Spatie of Enter = Plaats Rechthoek (of op Dia 1..3: volgende dia? Nee, vorm!)
        BEQ DO_ADD_RECT
        CMP #$0D
        BEQ DO_ADD_RECT

        AND #$DF                ; Maak hoofdletter
        CMP #'N'                ; N = Volgende dia
        BEQ DO_NEXT_SLIDE
        CMP #'B'                ; B = Vorige dia
        BEQ DO_PREV_SLIDE
        CMP #'P'                ; P = Automatische Diavoorstelling (Play/Stop)
        BEQ DO_TOGGLE_PLAY
        CMP #'K'                ; K = Kleur wisselen
        BEQ DO_CYCLE_COL
        CMP #'G'                ; G = Grootte wisselen (Klein/Middel/Groot)
        BEQ DO_CYCLE_SIZE
        CMP #'R'                ; R = Teken gevulde Rechthoek
        BEQ DO_ADD_RECT
        CMP #'C'                ; C = Teken gevulde Cirkel (DISC)
        BEQ DO_ADD_DISC
        CMP #'D'                ; D = Teken gevulde Driehoek (TRI)
        BEQ DO_ADD_TRI
        CMP #'L'                ; L = Teken Lijn (LINE) vanaf vorig punt
        BEQ DO_ADD_LINE
        CMP #'Z'                ; Z = Undo laatste vorm
        BEQ DO_UNDO_VEC
        CMP #'X'                ; X = Wis alle vormen op huidige dia
        BEQ DO_CLEAR_VECS
        JMP MAIN_LOOP

DO_PREV_SLIDE:
        LDA #0
        STA AUTO_PLAY
        LDA CUR_SLIDE
        BNE DPS_1
        LDA #4
DPS_1:
        SEC
        SBC #1
        STA CUR_SLIDE
        JSR UPDATE_SLIDE_VIEW
        JMP MAIN_LOOP

DO_NEXT_SLIDE:
        LDA #0
        STA AUTO_PLAY
        JSR NEXT_SLIDE
        JMP MAIN_LOOP

NEXT_SLIDE:
        INC CUR_SLIDE
        LDA CUR_SLIDE
        CMP #4
        BCC NS_OK
        LDA #0
        STA CUR_SLIDE
NS_OK:
        JMP UPDATE_SLIDE_VIEW

DO_TOGGLE_PLAY:
        LDA AUTO_PLAY
        EOR #1
        STA AUTO_PLAY
        LDA #0
        STA AUTO_TICKS
        LDA AUTO_PLAY
        BEQ DTP_STOP
        LDA #<STR_MSG_PLAY
        LDY #>STR_MSG_PLAY
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP
DTP_STOP:
        LDA #<STR_MSG_STOP
        LDY #>STR_MSG_STOP
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

DO_CYCLE_COL:
        JSR CYCLE_COLOR
        JMP MAIN_LOOP

CYCLE_COLOR:
        INC DRAW_COL_IDX
        LDA DRAW_COL_IDX
        AND #7
        STA DRAW_COL_IDX
        JSR DRAW_CURSOR_CROSS
        JMP UPDATE_STATUS_BAR

DO_CYCLE_SIZE:
        INC DRAW_SIZE_IDX
        LDA DRAW_SIZE_IDX
        CMP #3
        BCC DCS_OK
        LDA #0
        STA DRAW_SIZE_IDX
DCS_OK:
        JSR DRAW_ACTIVE_SLIDE
        JMP UPDATE_STATUS_BAR

DO_ADD_RECT:
        LDA #1                  ; Type 1 = Rechthoek
        JMP ADD_VECTOR_SHAPE
DO_ADD_DISC:
        LDA #2                  ; Type 2 = Cirkel / Schijf
        JMP ADD_VECTOR_SHAPE
DO_ADD_TRI:
        LDA #3                  ; Type 3 = Driehoek
        JMP ADD_VECTOR_SHAPE
DO_ADD_LINE:
        LDA #4                  ; Type 4 = Lijn
        JMP ADD_VECTOR_SHAPE

ADD_VECTOR_SHAPE:
        STA ZP_SAV_A
        LDA VEC_COUNT
        CMP #MAX_VECS
        BCS AVS_FULL
        JSR GET_VEC_PTR
        LDY #0
        LDA ZP_SAV_A
        STA (ZP_SHP_LO),Y       ; +0: Type (1..4)
        INY
        LDX DRAW_COL_IDX
        LDA PALETTE_COLS,X
        STA (ZP_SHP_LO),Y       ; +1: Kleur
        INY
        LDA CUR_X_LO
        STA (ZP_SHP_LO),Y       ; +2: X_LO
        INY
        LDA CUR_X_HI
        STA (ZP_SHP_LO),Y       ; +3: X_HI
        INY
        LDA CUR_Y_LO
        STA (ZP_SHP_LO),Y       ; +4: Y_LO
        INY
        LDX DRAW_SIZE_IDX
        LDA SHAPE_SIZES,X
        STA (ZP_SHP_LO),Y       ; +5: Grootte / Radius
        INY
        LDA PREV_X_LO
        STA (ZP_SHP_LO),Y       ; +6: PREV_X_LO (voor Lijn)
        INY
        LDA CUR_SLIDE
        STA (ZP_SHP_LO),Y       ; +7: Slide-nummer (0..3)

        ; Update vorig punt naar huidig punt
        LDA CUR_X_LO
        STA PREV_X_LO
        LDA CUR_X_HI
        STA PREV_X_HI
        LDA CUR_Y_LO
        STA PREV_Y_LO

        INC VEC_COUNT
        LDA #<STR_MSG_ADDED
        LDY #>STR_MSG_ADDED
AFTER_VEC_CHANGE:
        PHA
        TYA
        PHA
        JSR DRAW_ACTIVE_SLIDE
        JSR UPDATE_STATUS_BAR
        PLA
        TAY
        PLA
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

AVS_FULL:
        LDA #<STR_MSG_FULL
        LDY #>STR_MSG_FULL
        JSR SHOW_STATUS_MSG
        JMP MAIN_LOOP

DO_UNDO_VEC:
        LDA VEC_COUNT
        BEQ DUV_DONE
        DEC VEC_COUNT
        LDA #<STR_MSG_UNDO
        LDY #>STR_MSG_UNDO
        JMP AFTER_VEC_CHANGE
DUV_DONE:
        JMP MAIN_LOOP

DO_CLEAR_VECS:
        LDA #0
        STA VEC_COUNT
        LDA #<STR_MSG_CLEAR
        LDY #>STR_MSG_CLEAR
        JMP AFTER_VEC_CHANGE

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
        LDA #<STR_MSG_WELCOME
        LDY #>STR_MSG_WELCOME
        JMP SHOW_STATUS_MSG

MENU_KEY_HANDLER:
        LDA ZP_SAV_A
        CMP #' '
        BEQ CEM_JMP
        CMP #$0D
        BEQ CEM_JMP
        CMP #'1'
        BCC MKH_LET
        CMP #'5'
        BCS MKH_LET
        SEC
        SBC #'1'
        STA CUR_SLIDE
        JSR CLOSE_ESC_MENU
        JSR UPDATE_SLIDE_VIEW
        JMP MAIN_LOOP

MKH_LET:
        AND #$DF
        CMP #'Q'
        BNE MKH_1
        JMP EXIT_TO_MC
MKH_1:  CMP #'P'
        BNE MKH_2
        JSR CLOSE_ESC_MENU
        JMP DO_TOGGLE_PLAY
MKH_2:  CMP #'Z'
        BNE MKH_3
        JSR CLOSE_ESC_MENU
        JMP DO_UNDO_VEC
MKH_3:  CMP #'X'
        BNE MKH_4
        JSR CLOSE_ESC_MENU
        JMP DO_CLEAR_VECS
MKH_4:  CMP #'D'
        BNE CEM_JMP
        JSR CLOSE_ESC_MENU
        JSR LOAD_DEMO_VECS
        JSR DRAW_ACTIVE_SLIDE
        JMP MAIN_LOOP
CEM_JMP:
        JSR CLOSE_ESC_MENU
        JMP MAIN_LOOP

; ============================================================================
; Cursor Beweging binnen het Dia-Canvas (X = 140..604, Y = 92..220)
; ============================================================================
MOVE_CUR_UP:
        LDA CUR_Y_LO
        CMP #92
        BCC MCU_RTS
        SEC
        SBC #4
        STA CUR_Y_LO
MCU_RTS:
        RTS

MOVE_CUR_DOWN:
        LDA CUR_Y_LO
        CMP #220
        BCS MCD_RTS
        CLC
        ADC #4
        STA CUR_Y_LO
MCD_RTS:
        RTS

MOVE_CUR_LEFT:
        LDA CUR_X_HI
        BNE MCL_DO
        LDA CUR_X_LO
        CMP #140
        BCC MCL_RTS
MCL_DO:
        SEC
        LDA CUR_X_LO
        SBC #4
        STA CUR_X_LO
        BCS MCL_RTS
        DEC CUR_X_HI
MCL_RTS:
        RTS

MOVE_CUR_RIGHT:
        LDA CUR_X_HI
        CMP #2
        BCC MCR_DO
        LDA CUR_X_LO
        CMP #92                 ; 604 = $025C (92)
        BCS MCR_RTS
MCR_DO:
        CLC
        LDA CUR_X_LO
        ADC #4
        STA CUR_X_LO
        BCC MCR_RTS
        INC CUR_X_HI
MCR_RTS:
        RTS

; ============================================================================
; Scherm Opbouw: Studio-GUI, Dia-Kiezer Links & Actieve Dia Rechts
; ============================================================================
FULL_REDRAW:
        LDX #0
FR_GUI_LP:
        LDA IMPRESS_GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #IMPRESS_GUI_STREAM_END - IMPRESS_GUI_STREAM
        BCC FR_GUI_LP

        JSR DRAW_TOOLBAR
        LDA #<STR_WIN_TITLE
        LDY #>STR_WIN_TITLE
        JSR DRAW_POS_STR

UPDATE_SLIDE_VIEW:
        JSR DRAW_SLIDE_SORTER
        JSR DRAW_ACTIVE_SLIDE
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

; Teken de 4 Miniatuur-Dia's (DIA 1..4) in het linker overzichtspaneel (X=12..104)
DRAW_SLIDE_SORTER:
        LDA #0
        STA ZP_ITER
DSS_LP:
        LDX ZP_ITER
        LDA THUMB_Y_TBL,X
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        ; Kies randkleur: Geel ($FC) voor actieve dia, Grijs ($6D) voor andere dia's
        LDA #$6D
        CPX CUR_SLIDE
        BNE DSS_BORDER
        LDA #$FC
DSS_BORDER:
        LDY #0                  ; Sub-rect 0: (14, Y+0, 88, 56)
        JSR SEND_THUMB_RECT
        LDA #$02
        LDY #4                  ; Sub-rect 4: (16, Y+2, 84, 52)
        JSR SEND_THUMB_RECT
        LDX ZP_ITER
        LDA SLIDE_ACCENT_COL,X
        LDY #8                  ; Sub-rect 8: (20, Y+6, 76, 8)
        JSR SEND_THUMB_RECT

        ; Teken "DIA 1".."DIA 4" en ondertitel in de miniatuur
        LDA #24
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA ZP_Y_LO
        CLC
        ADC #22
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_FG_COL
        LDA #<STR_DIA_PREFIX
        STA ZP_PTR_LO
        LDA #>STR_DIA_PREFIX
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR
        LDA ZP_ITER
        CLC
        ADC #'1'
        JSR DRAW_CHAR_ADV

        ; Korte naam van de dia op Y+36
        LDA #24
        STA ZP_X_LO
        LDA ZP_Y_LO
        CLC
        ADC #14
        STA ZP_Y_LO
        LDX ZP_ITER
        LDA SLIDE_ACCENT_COL,X
        STA ZP_FG_COL
        LDA THUMB_NAME_LO,X
        STA ZP_PTR_LO
        LDA THUMB_NAME_HI,X
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR

        INC ZP_ITER
        LDA ZP_ITER
        CMP #4
        BCC DSS_LP
        RTS

SEND_THUMB_RECT:
        PHA
        LDA #2
        STA IO_GPU
        LDA THUMB_SUB_TBL,Y
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_Y_LO
        CLC
        ADC THUMB_SUB_TBL+1,Y
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA THUMB_SUB_TBL+2,Y
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA THUMB_SUB_TBL+3,Y
        STA IO_GPU
        LDA #0
        STA IO_GPU
        PLA
        STA IO_GPU
        RTS

THUMB_SUB_TBL:
        .BYTE 14, 0, 88, 56
        .BYTE 16, 2, 84, 52
        .BYTE 20, 6, 76, 8

; ============================================================================
; Teken de Actieve Dia (0..3) + Gebruikers-Vectorvormen + Cursor op het Canvas
; ============================================================================
DRAW_ACTIVE_SLIDE:
        ; 1. Wis het hoofd-canvas (X=120..628, Y=42..330) en teken de dia-achtergrond
        LDX #0
DAS_BG_LP:
        LDA SLIDE_CANVAS_STREAM,X
        STA IO_GPU
        INX
        CPX #SLIDE_CANVAS_STREAM_END - SLIDE_CANVAS_STREAM
        BCC DAS_BG_LP

        ; 2. Stuur de grafische vector-stream van de gekozen dia (DIA 1..4)!
        LDX CUR_SLIDE
        LDA SLIDE_GFX_LO,X
        STA ZP_PTR_LO
        LDA SLIDE_GFX_HI,X
        STA ZP_PTR_HI
        JSR SEND_GPU_STREAM_PTR

        ; 3. Teken alle tekstregels van de gekozen dia (DIA 1..4)!
        LDX CUR_SLIDE
        LDA SLIDE_TXT_LO,X
        STA ZP_PTR_LO
        LDA SLIDE_TXT_HI,X
        STA ZP_PTR_HI
        JSR DRAW_POS_STR_LIST

        ; 4. Teken alle door de gebruiker geplaatste Vector-Vormen voor deze dia!
        JSR DRAW_USER_VECS

        ; 5. Teken de interactieve Vector-Crosshair Cursor op (CUR_X, CUR_Y)
        JMP DRAW_CURSOR_CROSS

; Stuur een byte-stream naar IO_GPU tot byte $FF (voorafgegaan door lengte-blokken!)
; Formaat in tabel: [aantal_bytes, byte1, byte2, ...], afgesloten met 0!
SEND_GPU_STREAM_PTR:
        JSR NEXT_PTR_BYTE
        BEQ SGSP_RTS
        TAX
SGSP_BLK:
        JSR NEXT_PTR_BYTE
        STA IO_GPU
        DEX
        BNE SGSP_BLK
        JMP SEND_GPU_STREAM_PTR
SGSP_RTS:
        RTS

DRAW_POS_STR_LIST:
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #$FF
        BEQ DPSL_RTS
        JSR DRAW_NEXT_POS_STR
        JMP DRAW_POS_STR_LIST
DPSL_RTS:
        RTS

; ============================================================================
; Render alle Gebruikers-Vectorobjecten uit VEC_RAM ($7D00) op CUR_SLIDE
; ============================================================================
DRAW_USER_VECS:
        LDA #0
        STA ZP_ITER
DUV_LP:
        LDA ZP_ITER
        CMP VEC_COUNT
        BCS DUV_RTS
        JSR GET_VEC_PTR

        ; Check of deze vorm op CUR_SLIDE hoort (of op Dia 4 staat)
        LDY #7
        LDA (ZP_SHP_LO),Y
        CMP CUR_SLIDE
        BNE DUV_NEXT

        ; Lees gemeenschappelijke velden: Kleur (+1), X (+2..3), Y (+4), Size (+5)
        LDY #1
        LDA (ZP_SHP_LO),Y
        STA ZP_FG_COL
        INY
        LDA (ZP_SHP_LO),Y
        STA ZP_X_LO
        INY
        LDA (ZP_SHP_LO),Y
        STA ZP_X_HI
        INY
        LDA (ZP_SHP_LO),Y
        STA ZP_Y_LO
        INY
        LDA (ZP_SHP_LO),Y
        STA SHP_SZ

        LDY #0
        LDA (ZP_SHP_LO),Y       ; +0: Type (1=RECT, 2=DISC, 3=TRI, 4=LINE)
        CMP #1
        BEQ DUV_DO_RECT
        CMP #2
        BEQ DUV_DO_DISC
        CMP #3
        BEQ DUV_DO_TRI
        JMP DUV_DO_LINE

SEND_CMD_XY:
        STA IO_GPU
        LDA ZP_X_LO
        STA IO_GPU
        LDA ZP_X_HI
        STA IO_GPU
        LDA ZP_Y_LO
        STA IO_GPU
        LDA #0
        STA IO_GPU
        RTS

DUV_DO_RECT:
        ; GPU Cmd 2: RECT(X, Y, SZ*2, SZ, COL)
        LDA #2
        JSR SEND_CMD_XY
        LDA SHP_SZ
        ASL A
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA SHP_SZ
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_FG_COL
        STA IO_GPU
        JMP DUV_NEXT

DUV_DO_DISC:
        ; GPU Cmd 5: FILLED_CIRCLE / DISC(X, Y, SZ, 0, COL) -> 10 bytes!
        LDA #5
        JSR SEND_CMD_XY
        LDA SHP_SZ
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA ZP_FG_COL
        STA IO_GPU
        JMP DUV_NEXT

DUV_DO_TRI:
        ; GPU Cmd 7: FILLED_TRIANGLE(X, Y-SZ, X-SZ, Y+SZ, X+SZ, Y+SZ, COL) -> 14 bytes!
        LDA #7
        STA IO_GPU
        ; Punt 1: (X, Y - SZ)
        LDA ZP_X_LO
        STA IO_GPU
        LDA ZP_X_HI
        STA IO_GPU
        SEC
        LDA ZP_Y_LO
        SBC SHP_SZ
        STA IO_GPU
        LDA #0
        STA IO_GPU
        ; Punt 2: (X - SZ, Y + SZ)
        SEC
        LDA ZP_X_LO
        SBC SHP_SZ
        STA IO_GPU
        LDA ZP_X_HI
        SBC #0
        STA IO_GPU
        CLC
        LDA ZP_Y_LO
        ADC SHP_SZ
        STA IO_GPU
        LDA #0
        STA IO_GPU
        ; Punt 3: (X + SZ, Y + SZ)
        CLC
        LDA ZP_X_LO
        ADC SHP_SZ
        STA IO_GPU
        LDA ZP_X_HI
        ADC #0
        STA IO_GPU
        CLC
        LDA ZP_Y_LO
        ADC SHP_SZ
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_FG_COL
        STA IO_GPU
        JMP DUV_NEXT

DUV_DO_LINE:
        ; GPU Cmd 3: LINE(X, Y, X+SZ*2, Y-SZ, COL)
        LDA #3
        JSR SEND_CMD_XY
        CLC
        LDA ZP_X_LO
        ADC SHP_SZ
        ADC SHP_SZ
        STA IO_GPU
        LDA ZP_X_HI
        ADC #0
        STA IO_GPU
        SEC
        LDA ZP_Y_LO
        SBC SHP_SZ
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_FG_COL
        STA IO_GPU

DUV_NEXT:
        INC ZP_ITER
        JMP DUV_LP
DUV_RTS:
        RTS

; Teken het vizier/kruisje van de Vector-Cursor op (CUR_X, CUR_Y) in de huidige tekenkleur
DRAW_CURSOR_CROSS:
        LDX DRAW_COL_IDX
        LDA PALETTE_COLS,X
        STA ZP_FG_COL
        ; Klein gekleurd vierkantje van 5x5 px op (CUR_X-2, CUR_Y-2)
        LDA #2
        STA IO_GPU
        SEC
        LDA CUR_X_LO
        SBC #2
        STA IO_GPU
        LDA CUR_X_HI
        SBC #0
        STA IO_GPU
        SEC
        LDA CUR_Y_LO
        SBC #2
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #5
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #5
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_FG_COL
        STA IO_GPU
        RTS

; ============================================================================
; Statusbalk onderaan (Y = 342..359)
; ============================================================================
UPDATE_STATUS_BAR:
        LDX #20                 ; Rect 20: Wis linker statusveld (8, 344, 420, 14, $80)
        JSR SEND_RECT_10

        LDA #<STR_ST_DIA
        LDY #>STR_ST_DIA
        JSR DRAW_POS_STR

        LDA CUR_SLIDE
        CLC
        ADC #'1'
        JSR DRAW_CHAR_ADV

        LDA #<STR_ST_VECS
        STA ZP_PTR_LO
        LDA #>STR_ST_VECS
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR

        LDA VEC_COUNT
        JSR DRAW_DEC2

        LDA #<STR_ST_COL
        STA ZP_PTR_LO
        LDA #>STR_ST_COL
        STA ZP_PTR_HI
        JSR DRAW_ZP_STR

        ; Teken kleur-voorbeeldblokje in de statusbalk op (296, 345, 24, 10)
        LDA #2
        STA IO_GPU
        LDA #$28                ; 296 = $0128
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #$59                ; 345 = $0159
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #24
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #10
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDX DRAW_COL_IDX
        LDA PALETTE_COLS,X
        STA IO_GPU
        RTS

SHOW_STATUS_MSG:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDX #30                 ; Rect 30: Wis rechter statusveld (436, 344, 198, 14, $80)
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
; Hulproutines & Demo Vector-Objecten op Dia 4
; ============================================================================
; Zet ZP_SHP_LO/HI op $7D00 + A * 8 (A = 0..31)
GET_VEC_PTR:
        ASL A
        ASL A
        ASL A
        STA ZP_SHP_LO
        LDA #$7D
        ADC #0
        STA ZP_SHP_HI
        RTS

LOAD_DEMO_VECS:
        LDX #0
LDV_LP:
        LDA DEMO_VEC_TBL,X
        STA VEC_RAM,X
        INX
        CPX #DEMO_VEC_TBL_END - DEMO_VEC_TBL
        BCC LDV_LP
        LDA #5                  ; 5 start-objecten op Dia 4 (index 3)
        STA VEC_COUNT
        LDA #$5A
        STA VEC_MAGIC
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
DPS_LP:
        JSR NEXT_PTR_BYTE
        STA ZP_X_LO,X
        INX
        CPX #5
        BCC DPS_LP
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
; Tabellen, Kleurenpalet & De 4 Grafische Presentatie-Dia's
; ============================================================================
PALETTE_COLS:   .BYTE $FC, $1F, $E0, $1C, $F3, $EC, $FF, $03
SHAPE_SIZES:    .BYTE 12, 20, 32
THUMB_Y_TBL:    .BYTE 44, 114, 184, 254
SLIDE_ACCENT_COL: .BYTE $EC, $1F, $1C, $FC

THUMB_NAME_LO:  .BYTE <STR_TH1, <STR_TH2, <STR_TH3, <STR_TH4
THUMB_NAME_HI:  .BYTE >STR_TH1, >STR_TH2, >STR_TH3, >STR_TH4

SLIDE_GFX_LO:   .BYTE <SLIDE1_GFX, <SLIDE2_GFX, <SLIDE3_GFX, <SLIDE4_GFX
SLIDE_GFX_HI:   .BYTE >SLIDE1_GFX, >SLIDE2_GFX, >SLIDE3_GFX, >SLIDE4_GFX

SLIDE_TXT_LO:   .BYTE <SLIDE1_TXT, <SLIDE2_TXT, <SLIDE3_TXT, <SLIDE4_TXT
SLIDE_TXT_HI:   .BYTE >SLIDE1_TXT, >SLIDE2_TXT, >SLIDE3_TXT, >SLIDE4_TXT

STR_DIA_PREFIX: .ASCIIZ "DIA "
STR_TH1:        .ASCIIZ "OVERZICHT"
STR_TH2:        .ASCIIZ "HARDWARE"
STR_TH3:        .ASCIIZ "BENCHMARK"
STR_TH4:        .ASCIIZ "TEKENBORD"

; 5 Voorbeeld Vector-Vormen op Dia 4 (index 3): [Type, Col, X_lo, X_hi, Y_lo, Size, PrevX, Slide=3]
DEMO_VEC_TBL:
        .BYTE 2, $FC, $10,$01, 210, 26, 0, 3    ; Gele Zon/Cirkel op (272, 210)
        .BYTE 3, $1C, $70,$01, 220, 30, 0, 3    ; Groene Driehoek/Heuvel op (368, 220)
        .BYTE 1, $1F, $C8,$01, 205, 22, 0, 3    ; Cyaan Gebouw/Rechthoek op (456, 205)
        .BYTE 3, $E0, $DE,$01, 185, 22, 0, 3    ; Rood Dak/Driehoek op (478, 185)
        .BYTE 2, $F3, $30,$02, 210, 20, 0, 3    ; Magenta Cirkel op (560, 210)
DEMO_VEC_TBL_END:

GPU_INIT_STREAM:
        .BYTE 12, 1                     ; TARGET 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0   ; BIGSPR 0 uit
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0   ; BIGSPR 1 uit
        .BYTE 15, 0, 0, 0, 0            ; SCROLL 0, 0
GPU_INIT_STREAM_END:

IMPRESS_GUI_STREAM:
        ; Donkergrijs studio-achtergrond: RECT(0, 32, 640, 310, $24)
        .BYTE 2, 0,0, 32,0, $80,$02, $36,$01, $24
        ; Amber/Oranje LibreImpress Titelbalk: RECT(0, 0, 640, 16, $C4)
        .BYTE 2, 0,0, 0,0, $80,$02, 16,0, $C4
        ; Gele dia-icoon linksboven: RECT(8, 3, 10, 10, $FC)
        .BYTE 2, 8,0, 3,0, 10,0, 10,0, $FC
        ; Linker Dia-Sorter Paneel achtergrond: RECT(8, 38, 100, 296, $49)
        .BYTE 2, 8,0, 38,0, 100,0, $28,$01, $49
        ; Onderste Statusbalk: RECT(0, 342, 640, 18, $80)
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $80
IMPRESS_GUI_STREAM_END:

SLIDE_CANVAS_STREAM:
        ; Schaduw achter de dia: RECT(122, 44, 510, 290, $00)
        .BYTE 2, 122,0, 44,0, $FE,$01, $22,$01, $00
        ; Helder cyaan/witte rand om dia: RECT(116, 38, 512, 292, $FF)
        .BYTE 2, 116,0, 38,0, $00,$02, $24,$01, $FF
        ; Donkerblauwe presentatie-achtergrond: RECT(118, 40, 508, 288, $01)
        .BYTE 2, 118,0, 40,0, $FC,$01, $20,$01, $01
SLIDE_CANVAS_STREAM_END:

UI_RECT_TBL:
        ; Offset 0: Gele ESC-menubalk (0, 16, 640, 16, $FC)
        .BYTE 2, 0,0, 16,0, $80,$02, 16,0, $FC
        ; Offset 10: Grijze werkbalk (0, 16, 640, 16, $B6)
        .BYTE 2, 0,0, 16,0, $80,$02, 16,0, $B6
        ; Offset 20: Wis linker statusveld (8, 344, 420, 14, $80)
        .BYTE 2, 8,0, $58,$01, $A4,$01, 14,0, $80
        ; Offset 30: Wis rechter statusveld (436, 344, 198, 14, $80)
        .BYTE 2, $B4,$01, $58,$01, 198,0, 14,0, $80

; --- DIA 1: Titel & MiniOffice 6502 Overzicht ---
SLIDE1_GFX:
        ; Oranje kop-banner: RECT(118, 40, 508, 38, $C4) + Gele sierlijn
        .BYTE 10, 2, 118,0, 40,0, $FC,$01, 38,0, $C4
        .BYTE 10, 2, 118,0, 78,0, $FC,$01, 3,0, $FC
        ; 3 Grafische App-Kaarten: LibreWriter (Blauw), LibreCalc (Groen), LibreImpress (Oranje)
        .BYTE 10, 2, 140,0, 100,0, 140,0, 90,0, $0B
        .BYTE 10, 2, $28,$01, 100,0, 140,0, 90,0, $10
        .BYTE 10, 2, $C0,$01, 100,0, 140,0, 90,0, $80
        ; Cirkel- en Driehoek-emblemen in de 3 kaarten (Cmd 5 = DISC 10B, Cmd 7 = FILLED_TRI 14B)
        .BYTE 10, 5, 210,0, 132,0, 16,0, 0,0, $1F
        .BYTE 10, 5, $6E,$01, 132,0, 16,0, 0,0, $1C
        .BYTE 14, 7, $06,$02, 116,0, $F4,$01, 146,0, $18,$02, 146,0, $FC
        .BYTE 0

SLIDE1_TXT:
        .BYTE 140,0, 50,0, $FC, "MINIOFFICE 6502 SUITE - TANG NANO 20K", 0
        .BYTE 140,0, 64,0, $FF, "Supersnel Kantoorpakket in 6502 Assembly", 0
        .BYTE 156,0, 162,0, $FF, "1. WRITER", 0
        .BYTE 152,0, 175,0, $1F, "Tekst & Thema", 0
        .BYTE $3C,$01, 162,0, $FF, "2. CALC", 0
        .BYTE $32,$01, 175,0, $1C, "Formule+Grafiek", 0
        .BYTE $CC,$01, 162,0, $FF, "3. IMPRESS", 0
        .BYTE $CA,$01, 175,0, $FC, "Dia's & Vector", 0
        .BYTE 140,0, 214,0, $FC, "* Start direct vanuit Midnight Commander (MC)", 0
        .BYTE 140,0, 234,0, $1F, "* Opslag van Document & Sheet op SD-Kaart D0", 0
        .BYTE 140,0, 254,0, $1C, "* 640x360 MiniGPU Hardware Vector Graphics", 0
        .BYTE 140,0, $1E,$01, $FF, "Toets [1..4] of [ ] = Dia, [P] = AutoShow!", 0
        .BYTE $FF

; --- DIA 2: Tang Nano 20K Hardware Architectuur Blokschema ---
SLIDE2_GFX:
        ; Cyaan kop-banner: RECT(118, 40, 508, 34, $0B)
        .BYTE 10, 2, 118,0, 40,0, $FC,$01, 34,0, $0B
        ; 4 Hardware Blokken: [MOS 6502 CPU], [SDRAM 64KB+8MB], [MINIGPU 2D], [RANDAPPARATUUR]
        .BYTE 10, 2, 140,0, 100,0, 130,0, 64,0, $80
        .BYTE 10, 2, $40,$01, 100,0, 130,0, 64,0, $10
        .BYTE 10, 2, $E0,$01, 100,0, 130,0, 64,0, $43
        .BYTE 10, 2, 200,0, 210,0, $50,$01, 60,0, $25
        ; Gele bus-lijnen tussen de blokken (LINE)
        .BYTE 10, 3, $0E,$01, 132,0, $40,$01, 132,0, $FC
        .BYTE 10, 3, $C2,$01, 132,0, $E0,$01, 132,0, $FC
        .BYTE 10, 3, $80,$01, 164,0, $80,$01, 210,0, $1F
        .BYTE 0

SLIDE2_TXT:
        .BYTE 140,0, 52,0, $1F, "DIA 2: TANG NANO 20K FPGA ARCHITECTUUR", 0
        .BYTE 156,0, 118,0, $FC, "MOS 6502 CPU", 0
        .BYTE 156,0, 136,0, $FF, "SDRAM Engine", 0
        .BYTE $52,$01, 118,0, $1C, "SDRAM 8MB", 0
        .BYTE $52,$01, 136,0, $FF, "64KB + Video", 0
        .BYTE $F2,$01, 118,0, $F3, "MINIGPU 2D", 0
        .BYTE $F2,$01, 136,0, $FF, "640x360 HDMI", 0
        .BYTE 216,0, 224,0, $FC, "I/O: PS/2 Keyboard + SD-Kaart D0..D3 + PSG", 0
        .BYTE 216,0, 244,0, $1F, "RAM: $7000=DOC $7800=XLS $8000=APP $9000=MC", 0
        .BYTE 140,0, $26,$01, $FF, "Tip: Beweeg cursor met Pijltjes en druk R/C/D!", 0
        .BYTE $FF

; --- DIA 3: Prestaties & Geheugen Benchmarks ---
SLIDE3_GFX:
        ; Groene kop-banner: RECT(118, 40, 508, 34, $10)
        .BYTE 10, 2, 118,0, 40,0, $FC,$01, 34,0, $10
        ; Horizontale snelheids-staven:
        ; 6502 Native ASM (420 px breed, Groen $1C)
        .BYTE 10, 2, 150,0, 116,0, $A4,$01, 22,0, $1C
        ; Hardware Blitter/GPU (450 px breed, Cyaan $1F)
        .BYTE 10, 2, 150,0, 174,0, $C2,$01, 22,0, $1F
        ; BASIC Interpreter (90 px breed, Oranje $EC)
        .BYTE 10, 2, 150,0, 232,0, 90,0, 22,0, $EC
        .BYTE 0

SLIDE3_TXT:
        .BYTE 140,0, 52,0, $FC, "DIA 3: SNELHEID & GEHEUGEN BENCHMARKS", 0
        .BYTE 150,0, 102,0, $FF, "6502 NATIVE ASSEMBLY ($8000) - IO_GPU:", 0
        .BYTE 160,0, 123,0, $00, "100% SNELHEID (< 2 ms per scherm!)", 0
        .BYTE 150,0, 160,0, $FF, "MINIGPU BLITTER (RECT/LINE/TRI/DISC):", 0
        .BYTE 160,0, 181,0, $00, "27 MHz Pixel Engine (640x360 @ 60Hz)", 0
        .BYTE 150,0, 218,0, $FF, "BASIC INTERPRETER ($0500):", 0
        .BYTE 250,0, 239,0, $FC, "15x trager dan 6502 ASM", 0
        .BYTE 150,0, $1E,$01, $1F, "Alle 3 MiniOffice apps < 4 KB naast MC!", 0
        .BYTE $FF

; --- DIA 4: Interactieve LibreDraw Vector Tekenstudio ---
SLIDE4_GFX:
        ; Paarse/Magenta kop-banner: RECT(118, 40, 508, 34, $42)
        .BYTE 10, 2, 118,0, 40,0, $FC,$01, 34,0, $42
        ; Teken-kadertje op Dia 4: horizon-lijn op Y=250
        .BYTE 10, 3, 130,0, 250,0, $68,$02, 250,0, $49
        .BYTE 0

SLIDE4_TXT:
        .BYTE 140,0, 52,0, $FC, "DIA 4: INTERACTIEF VECTOR TEKENBORD", 0
        .BYTE 140,0, 84,0, $1F, "Beweeg het vizier met Pijltjes of WASD:", 0
        .BYTE 140,0, 102,0, $FF, "[R/SPAT]=Rechthoek [C]=Cirkel [D]=Driehoek [L]=Lijn", 0
        .BYTE 140,0, 118,0, $FC, "[K/TAB]=Kleur  [G/+]=Grootte  [Z]=Undo  [X]=Wis", 0
        .BYTE $FF

STR_WIN_TITLE:
        .BYTE 24,0, 4,0, $FF, "LibreImpress & Draw 6502 - [PRESENTATIE.ODP]       MiniOffice", 0

STR_TOOLBAR:
        .ASCIIZ "1-4/[]:Dia P:Show R:Recht C:Cirkel D:Drie L:Lijn K:Kleur ESC:Menu"
STR_ESC_MENU:
        .ASCIIZ "[1-4]Dia [P]AutoShow [Z]Undo [X]Wis [D]Demo [SPAT]Sluit [ESC/Q]MC"

STR_ST_DIA:     .BYTE 12,0, $5B,$01, $FF, "DIA:", 0
STR_ST_VECS:    .ASCIIZ "/4 | VORMEN:"
STR_ST_COL:     .ASCIIZ "/32 | KLEUR:"

STR_MSG_WELCOME: .ASCIIZ "1-4=DIA | R/C/D/L=TEKEN"
STR_MSG_PLAY:    .ASCIIZ "AUTOSHOW AAN! (P=STOP)"
STR_MSG_STOP:    .ASCIIZ "AUTOSHOW GESTOPT"
STR_MSG_ADDED:   .ASCIIZ "VECTOR-VORM GEPLAATST!"
STR_MSG_UNDO:    .ASCIIZ "LAATSTE VORM GEWIST"
STR_MSG_CLEAR:   .ASCIIZ "CANVAS SCHOONGEWIST"
STR_MSG_FULL:    .ASCIIZ "MAX 32 VORMEN BEREIKT!"
