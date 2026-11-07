; ============================================================================
; VIEWER.asm - MiniGPU ImageViewer & Art Gallery 6502 (Plaatjes, Sprites & Palet)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC.asm op $9000).
;
; Mogelijkheden:
;   * Modus [1] SD / RLE Pixel-Art Plaatjes ($5000, "MIMG"-formaat + Ingebouwd
;     120x80 Cyber-Sunset kunstwerk) met 1x / 2x / 3x Zoom (Z) & Pan (Pijltjes)!
;   * Modus [2] Scifi-Schilderij "Ruimtehaven Tang-20K" (Vector GPU Galerij)
;   * Modus [3] Hardware Sprite-Sheet (alle 32x 16x16 Sprites + 2x 128x128
;     BigSprites + L = Laad eigen SPREDIT-sprites vanaf SD-sector $03F0!)
;   * Modus [4] 64x64 Wereldmap & Tegel-Atlas (Scrollbaar met Pijltjes/WASD!)
;   * Modus [5] 256-Kleuren RGB332 Master Palet & Interactieve Kleuren-Kiezer!
;   * Grafische SD-Kaart Plaatjes-Kiezer (O of ENTER) voor Drive D0..D3 (1..4)
;   * Automatische Diashow / Slideshow (P of Spatie), 4 Lijst-Thema's (C)
;     en Volledig Scherm modus (F).
; Starten vanuit BASIC of Midnight Commander met:  BRUN VIEWER
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter (UART / PS/2)
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (640x360 graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- ROM Routines voor SD-Kaart & Geluid ---
ZP_DST          = $1C           ; 16-bit doeladres voor ROM_READ_SEC
DISK_DRIVE      = $0490         ; Huidige drive (0..3)
DISK_SLOT       = $0493         ; Huidig slot (0..14)
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497

ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67

; --- Afbeeldingsbuffer in SDRAM ($5000-$5FFF = 4 KB voor .IMG bestanden) ---
IMG_BUF         = $5000         ; "MIMG" + W + H + Scale + BG + Scanline RLE
DIR_CACHE       = $5E00         ; 512-byte cache voor SD-Bestandskiezer
SPR_LOAD_BUF    = $6000         ; Tijdelijke buffer voor SPREDIT sprites ($03F0)

; --- Zero Page Variabelen ($60..$85) ---
ZP_PTR_LO       = $60           ; Algemene 16-bit pointer
ZP_PTR_HI       = $61
ZP_X_LO         = $62           ; 16-bit GPU X
ZP_X_HI         = $63
ZP_Y_LO         = $64           ; 16-bit GPU Y
ZP_Y_HI         = $65
ZP_W_LO         = $66           ; 16-bit GPU W
ZP_W_HI         = $67
ZP_H_LO         = $68           ; 8-bit GPU H
ZP_COL          = $69           ; Huidige GPU kleur
ZP_FG_COL       = $6A           ; Tekstkleur

ZP_CUR_X_LO     = $6B           ; Huidige pixel X tijdens RLE tekenen
ZP_CUR_X_HI     = $6C
ZP_CUR_Y_LO     = $6D           ; Huidige pixel Y tijdens RLE tekenen
ZP_CUR_Y_HI     = $6E
ZP_BASE_X_LO    = $6F           ; Linkerrand van het plaatje op scherm
ZP_BASE_X_HI    = $70
ZP_BASE_Y_LO    = $71           ; Bovenrand van het plaatje op scherm
ZP_BASE_Y_HI    = $72
ZP_ROW_REM      = $73           ; Resterende pixels op huidige beeldlijn
ZP_ROWS_LEFT    = $74           ; Resterende beeldlijnen

VIEW_MODE       = $75           ; 0=RLE Plaatje, 1=Ruimtehaven, 2=Sprites, 3=Wereldmap, 4=256-Palet
ZOOM_LVL        = $76           ; 1, 2 of 3 (schaalfactor voor Modus 1)
PAN_X           = $77           ; Horizontale verschuiving
PAN_Y           = $78           ; Verticale verschuiving
FRAME_THEME     = $79           ; 0..3 Kader-kleurenthema
FULLSCREEN      = $7A           ; 0 = Met balken, 1 = Volledig scherm
SLIDESHOW       = $7B           ; 0 = Handmatig, 1 = Automatische Diashow
SLIDE_TIMER     = $7C           ; Afteltimer voor diashow
LAST_TICK       = $7D           ; Laatste IO_TIMER waarde
PREV_JOY        = $7E           ; Vorige joypad-status
PAL_SEL         = $7F           ; Geselecteerde kleur (0..255) in Modus 5
BIG_MIRROR      = $80           ; Spiegel-vlag (0 of 1) voor BigSprites
MAP_SCR_X       = $81           ; Scroll X/8 voor Modus 4 (Wereldmap)
MAP_SCR_Y       = $82           ; Scroll Y/8 voor Modus 4
DLG_SEL         = $83           ; Geselecteerd slot (0..14) in SD-Kiezer
ZP_TMP_CNT      = $84           ; Teller
ZP_STR_LEN      = $85           ; Stream-lengte voor SEND_GPU_STREAM

; ============================================================================
; Hoofdprogramma Start ($8000)
; ============================================================================
START:
        CLD
        JSR ROM_SILENCE

        ; Zet volledig scherm 640x360 graphics aan (IO_MODE = 0) en wis variabelen
        LDA #0
        STA IO_MODE
        LDX #(ZP_STR_LEN - VIEW_MODE)
CLR_ZP: STA VIEW_MODE,X
        DEX
        BPL CLR_ZP

        LDA #$1F
        STA PAL_SEL
        LDA #3
        STA ZOOM_LVL

        ; Controleer of er al een geldig "MIMG" plaatje op $5000 staat;
        ; zo niet, kopieer het ingebouwde Cyber-Sunset kunstwerk naar $5000!
        JSR CHECK_MIMG_HEADER
        BEQ INIT_DRAW
        JSR INSTALL_DEFAULT_IMG

INIT_DRAW:
        LDA IO_TERM
        LDA IO_JOY
        STA PREV_JOY
        LDA IO_TIMER
        STA LAST_TICK
        LDA #240
        STA SLIDE_TIMER
        JSR DRAW_FULL_SCREEN

; ============================================================================
; Hoofdlus: Timer (Diashow) + Gecombineerde Toetsenbord/Joypad Invoer
; ============================================================================
MAIN_LOOP:
        LDA IO_TIMER
        CMP LAST_TICK
        BEQ CHK_INPUT
        STA LAST_TICK

        LDA SLIDESHOW
        BEQ CHK_INPUT
        DEC SLIDE_TIMER
        BNE CHK_INPUT
        LDA #240
        STA SLIDE_TIMER
        JSR NEXT_SD_IMG

CHK_INPUT:
        JSR POLL_INPUT          ; Geeft 0 als niets ingedrukt, anders hoofdletter / $1B / $0D
        BEQ MAIN_LOOP

        CMP #$1B                ; ESC -> Open ESC-Menu
        BNE CK_MODES
        JMP OPEN_ESC_MENU

CK_MODES:
        CMP #'1'
        BCC CK_NAV
        CMP #'6'
        BCS CK_NAV
        SEC
        SBC #'1'
        STA VIEW_MODE
        JSR RESET_PAN_ZOOM
        JMP REDRAW_AND_MAIN

CK_NAV:
        LDX #3
CK_N_LP:
        CMP JOY_CHAR_TBL,X
        BEQ CK_N_HIT
        DEX
        BPL CK_N_LP
        JMP CK_BRK
CK_N_HIT:
        LDY NAV_MAP_D,X
        LDA NAV_PAL_D,X
        PHA
        TXA
        AND #2
        BNE CK_N_H
        LDA NAV_PAN_D,X
        TAX
        PLA
        JSR MOVE_VERT
        JMP MAIN_LOOP
CK_N_H:
        LDA NAV_PAN_D,X
        TAX
        PLA
        JSR MOVE_HORIZ
        JMP MAIN_LOOP

CK_BRK:
        CMP #'['
        BNE CK_NEXT
        JSR PREV_VIEW_MODE
        JMP MAIN_LOOP
CK_NEXT:
        CMP #']'
        BNE CK_ZOOM
        JSR NEXT_VIEW_MODE
        JMP MAIN_LOOP

CK_ZOOM:
        CMP #'Z'
        BEQ DO_ZOOM_CYCLE
        CMP #'+'
        BEQ DO_ZOOM_IN
        CMP #'='
        BEQ DO_ZOOM_IN
        CMP #'-'
        BEQ DO_ZOOM_OUT
        JMP CK_OTHER

DO_ZOOM_CYCLE:
        LDX ZOOM_LVL
        INX
        CPX #4
        BCC SET_ZM
        LDX #1
SET_ZM: STX ZOOM_LVL
REDRAW_AND_MAIN:
        JSR DRAW_FULL_SCREEN
        JMP MAIN_LOOP

DO_ZOOM_IN:
        LDX ZOOM_LVL
        CPX #3
        BCS MAIN_LOOP_JMP
        INX
        JMP SET_ZM

DO_ZOOM_OUT:
        LDX ZOOM_LVL
        CPX #2
        BCC MAIN_LOOP_JMP
        DEX
        JMP SET_ZM

MAIN_LOOP_JMP:
        JMP MAIN_LOOP

CK_OTHER:
        CMP #'O'                ; O of Enter = Open SD-Kaart Plaatjes-Kiezer
        BEQ DO_OPEN_DLG
        CMP #$0D
        BEQ DO_OPEN_DLG
        CMP #'P'                ; P of Spatie = Diashow aan/uit
        BEQ DO_SLIDE
        CMP #' '
        BEQ DO_SLIDE
        CMP #'C'                ; C of ~ = Kader-thema wisselen
        BEQ DO_THEME
        CMP #'~'
        BEQ DO_THEME
        CMP #'F'                ; F = Volledig scherm (balken aan/uit)
        BEQ DO_FULLSCR
        CMP #'M'                ; M = Spiegel BigSprites (in Modus 3)
        BEQ DO_MIRROR
        CMP #'L'                ; L = Laad SPREDIT sprites vanaf SD ($03F0)
        BEQ DO_LOAD_SPREDIT
        CMP #'R'                ; R = Reset standaard Cyber-Sunset plaatje
        BEQ DO_RESET_IMG
        CMP #'N'                ; N = Volgend SD-Kaart Plaatje
        BEQ DO_NEXT_IMG
        CMP #'Q'
        BNE MAIN_LOOP_JMP
        JMP EXIT_VIEWER

DO_NEXT_IMG:
        JSR NEXT_SD_IMG
        JMP MAIN_LOOP
DO_OPEN_DLG:
        JSR OPEN_FILE_DIALOG
        JMP MAIN_LOOP
DO_SLIDE:
        LDA SLIDESHOW
        EOR #1
        STA SLIDESHOW
        LDA #240
        STA SLIDE_TIMER
        JSR DRAW_BOT_BAR
        JMP MAIN_LOOP
DO_THEME:
        INC FRAME_THEME
        LDA FRAME_THEME
        AND #3
        STA FRAME_THEME
        JMP REDRAW_AND_MAIN
DO_FULLSCR:
        LDA FULLSCREEN
        EOR #1
        STA FULLSCREEN
        JMP REDRAW_AND_MAIN
DO_MIRROR:
        LDA BIG_MIRROR
        EOR #1
        STA BIG_MIRROR
        LDA #2
        STA VIEW_MODE
        JMP REDRAW_AND_MAIN
DO_LOAD_SPREDIT:
        JSR LOAD_SPREDIT_FROM_SD
        LDA #2
        STA VIEW_MODE
        JMP REDRAW_AND_MAIN
DO_RESET_IMG:
        JSR INSTALL_DEFAULT_IMG
        LDA #0
        STA VIEW_MODE
        JSR RESET_PAN_ZOOM
        JMP REDRAW_AND_MAIN

; ============================================================================
; Gecombineerde Invoer-Routine (Pollt ESC, Joypad-Flank en Toetsenbord)
; Retourneert A = 0 (geen toets) of hoofdletter ASCII / $1B / $0D
; ============================================================================
POLL_INPUT:
        LDA IO_STATUS
        BPL PI_JOY
        LDA IO_TERM
        LDA #$1B
        RTS
PI_JOY:
        LDA IO_JOY
        TAX
        EOR PREV_JOY
        AND IO_JOY
        STX PREV_JOY
        TAY
        BEQ PI_KEY
        LDA IO_STATUS
        AND #1
        BEQ PI_MAP_J
        LDA IO_TERM
PI_MAP_J:
        LDX #4
PI_J_LP:
        TYA
        AND JOY_MASK_TBL,X
        BNE PI_J_HIT
        DEX
        BPL PI_J_LP
        LDA #0
        RTS
PI_J_HIT:
        LDA JOY_CHAR_TBL,X
        RTS

PI_KEY:
        LDA IO_STATUS
        AND #1
        BEQ PI_NONE
        LDA IO_TERM
        CMP #'a'
        BCC PI_RTS
        CMP #'z'+1
        BCS PI_RTS
        SEC
        SBC #$20
PI_RTS: RTS
PI_NONE:
        LDA #0
        RTS

; ============================================================================
; Navigatie & Modus-Wissel Helpers
; ============================================================================
RESET_PAN_ZOOM:
        LDA #0
        STA PAN_X
        STA PAN_Y
        RTS

PREV_VIEW_MODE:
        LDX VIEW_MODE
        BNE PVM_DEC
        LDX #5
PVM_DEC:
        DEX
        STX VIEW_MODE
        JSR RESET_PAN_ZOOM
        JMP DRAW_FULL_SCREEN

NEXT_VIEW_MODE:
        LDX VIEW_MODE
        INX
        CPX #5
        BCC NVM_SET
        LDX #0
NVM_SET:
        STX VIEW_MODE
        JSR RESET_PAN_ZOOM
        JMP DRAW_FULL_SCREEN

MOVE_VERT:
        PHA
        LDA VIEW_MODE
        CMP #4
        BEQ MV_PAL
        CMP #3
        BEQ MV_MAP
        PLA
        TXA
        CLC
        ADC PAN_Y
        STA PAN_Y
        JMP DRAW_FULL_SCREEN
MV_MAP:
        PLA
        TYA
        CLC
        ADC MAP_SCR_Y
        STA MAP_SCR_Y
        JMP UPDATE_MAP_SCROLL
MV_PAL:
        PLA
        CLC
        ADC PAL_SEL
        STA PAL_SEL
        JMP DRAW_FULL_SCREEN

MOVE_HORIZ:
        PHA
        LDA VIEW_MODE
        CMP #4
        BEQ MV_PAL
        CMP #3
        BEQ MH_MAP
        PLA
        TXA
        CLC
        ADC PAN_X
        STA PAN_X
        JMP DRAW_FULL_SCREEN
MH_MAP:
        PLA
        TYA
        CLC
        ADC MAP_SCR_X
        STA MAP_SCR_X
        JMP UPDATE_MAP_SCROLL

UPDATE_MAP_SCROLL:
        LDA #15                 ; GPU CMD 15 = SET_SCROLL(xl, xh, yl, yh)
        STA IO_GPU
        LDA MAP_SCR_X
        JSR SEND_SCR_COORD
        LDA MAP_SCR_Y
SEND_SCR_COORD:
        PHA
        ASL A
        ASL A
        ASL A
        STA IO_GPU
        PLA
        LSR A
        LSR A
        LSR A
        LSR A
        LSR A
        AND #3
        STA IO_GPU
        RTS

; ============================================================================
; Volledig Scherm Opbouwen op basis van VIEW_MODE (0..4)
; ============================================================================
DRAW_FULL_SCREEN:
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU

        JSR HIDE_BIG_SPRITES

        LDA VIEW_MODE
        CMP #3                  ; Modus 4 (index 3) = Wereldmap doorkijk ($E3)!
        BNE DFS_BG_NORM
        LDA #$E3
        JMP DFS_CLR
DFS_BG_NORM:
        LDX FRAME_THEME
        LDA THEME_BG_COL,X
DFS_CLR:
        PHA
        LDA #1                  ; GPU CMD 1 = CLEAR
        STA IO_GPU
        PLA
        STA IO_GPU

        LDA VIEW_MODE
        BEQ DFS_M0
        CMP #1
        BEQ DFS_M1
        CMP #2
        BEQ DFS_M2
        CMP #3
        BEQ DFS_M3
        JSR DRAW_MODE_PALETTE
        JMP DFS_BARS
DFS_M0: JSR DRAW_MODE_RLE_IMG
        JMP DFS_BARS
DFS_M1: JSR DRAW_MODE_SPACEPORT
        JMP DFS_BARS
DFS_M2: JSR DRAW_MODE_SPRITES
        JMP DFS_BARS
DFS_M3: JSR UPDATE_MAP_SCROLL

DFS_BARS:
        LDA FULLSCREEN
        BNE DFS_RTS
        JSR DRAW_TOP_BAR
        JSR DRAW_BOT_BAR
DFS_RTS:
        RTS

HIDE_BIG_SPRITES:
        LDX #0
HBS_LP: LDA #21
        STA IO_GPU
        TXA
        STA IO_GPU
        LDA #0
        LDY #6
HBS_Z:  STA IO_GPU
        DEY
        BNE HBS_Z
        INX
        CPX #2
        BCC HBS_LP
        RTS

; ============================================================================
; MODUS 1 (index 0): RLE Pixel-Art Plaatje uit $5000 ("MIMG" + Scanline RLE)
; ============================================================================
CHECK_MIMG_HEADER:
        LDX #3
CMH_LP: LDA IMG_BUF,X
        CMP BUILTIN_IMG_DATA,X
        BNE CMH_FAIL
        DEX
        BPL CMH_LP
        LDA #0
CMH_FAIL:
        RTS

INSTALL_DEFAULT_IMG:
        LDA #<BUILTIN_IMG_DATA
        STA ZP_PTR_LO
        LDA #>BUILTIN_IMG_DATA
        STA ZP_PTR_HI
        LDA #<IMG_BUF
        STA ZP_DST
        LDA #>IMG_BUF
        STA ZP_DST+1
        LDX #3
IDI_PG: LDY #0
IDI_LP: LDA (ZP_PTR_LO),Y
        STA (ZP_DST),Y
        INY
        BNE IDI_LP
        INC ZP_PTR_HI
        INC ZP_DST+1
        DEX
        BNE IDI_PG
        RTS

DRAW_MODE_RLE_IMG:
        JSR CHECK_MIMG_HEADER
        BEQ DMRI_OK
        JSR INSTALL_DEFAULT_IMG
DMRI_OK:
        LDX ZOOM_LVL
        DEX
        CPX #3
        BCC DMRI_Z_OK
        LDX #2
DMRI_Z_OK:
        LDY #0
        LDA PAN_X
        BPL PX_POS
        DEY
PX_POS: CLC
        ADC ZOOM_BASE_X_LO,X
        STA ZP_BASE_X_LO
        TYA
        ADC ZOOM_BASE_X_HI,X
        STA ZP_BASE_X_HI

        CLC
        LDA ZOOM_BASE_Y,X
        ADC PAN_Y
        STA ZP_BASE_Y_LO
        LDA #0
        STA ZP_BASE_Y_HI

        ; Teken schilderij-lijst / kader rondom het plaatje
        SEC
        LDA ZP_BASE_X_LO
        SBC #4
        STA ZP_X_LO
        LDA ZP_BASE_X_HI
        SBC #0
        STA ZP_X_HI
        SEC
        LDA ZP_BASE_Y_LO
        SBC #4
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        LDA ZOOM_FRAME_W_LO,X
        STA ZP_W_LO
        LDA ZOOM_FRAME_W_HI,X
        STA ZP_W_HI
        LDA ZOOM_FRAME_H,X
        STA ZP_H_LO

        LDY FRAME_THEME
        LDA THEME_BORDER_COL,Y
        STA ZP_COL
        JSR DRAW_RECT_16W

        ; Start Scanline RLE-decoder vanaf IMG_BUF+8
        LDA #<(IMG_BUF+8)
        STA ZP_PTR_LO
        LDA #>(IMG_BUF+8)
        STA ZP_PTR_HI

        LDA ZP_BASE_Y_LO
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA IMG_BUF+5           ; Hoogte in beeldlijnen (80)
        STA ZP_ROWS_LEFT

RLE_ROW_LOOP:
        LDA ZP_BASE_X_LO
        STA ZP_X_LO
        LDA ZP_BASE_X_HI
        STA ZP_X_HI
        LDA IMG_BUF+4           ; Breedte in pixels (120)
        STA ZP_ROW_REM

RLE_SEG_LOOP:
        JSR NEXT_PTR_BYTE
        BEQ RLE_DONE
        STA ZP_TMP_CNT
        JSR NEXT_PTR_BYTE
        STA ZP_COL

        LDA #0
        STA ZP_W_LO
        STA ZP_W_HI
        LDX ZOOM_LVL
RLE_MUL_W:
        CLC
        LDA ZP_W_LO
        ADC ZP_TMP_CNT
        STA ZP_W_LO
        BCC RLE_MW_N
        INC ZP_W_HI
RLE_MW_N:
        DEX
        BNE RLE_MUL_W

        ; Teken RLE-segment als hardware RECT(ZP_X, ZP_Y, W, ZOOM_LVL, COL)
        LDA ZOOM_LVL
        STA ZP_H_LO
        JSR DRAW_RECT_16W

        CLC
        LDA ZP_X_LO
        ADC ZP_W_LO
        STA ZP_X_LO
        LDA ZP_X_HI
        ADC ZP_W_HI
        STA ZP_X_HI

        SEC
        LDA ZP_ROW_REM
        SBC ZP_TMP_CNT
        STA ZP_ROW_REM
        BEQ RLE_NEXT_ROW
        BCS RLE_SEG_LOOP

RLE_NEXT_ROW:
        CLC
        LDA ZP_Y_LO
        ADC ZOOM_LVL
        STA ZP_Y_LO
        BCC RLE_NR_NH
        INC ZP_Y_HI
RLE_NR_NH:
        DEC ZP_ROWS_LEFT
        BNE RLE_ROW_LOOP
RLE_DONE:
        RTS

; ============================================================================
; MODUS 2 (index 1): Vector-Meesterwerk "Ruimtehaven Tang-20K"
; ============================================================================
DRAW_MODE_SPACEPORT:
        LDA #<SPACEPORT_STREAM
        LDY #>SPACEPORT_STREAM
        LDX #(SPACEPORT_END - SPACEPORT_STREAM)
        JSR SEND_GPU_STREAM
        LDA #<STR_ART2_CAPTION
        LDY #>STR_ART2_CAPTION
        JMP DRAW_HDR_LIST

; ============================================================================
; MODUS 3 (index 2): 32x 16x16 Hardware Sprites + 2x 128x128 BigSprites
; ============================================================================
DRAW_MODE_SPRITES:
        LDA #<SPR_PANEL_STREAM
        LDY #>SPR_PANEL_STREAM
        LDX #(SPR_PANEL_END - SPR_PANEL_STREAM)
        JSR SEND_GPU_STREAM

        ; Teken alle 32 hardware sprites (0..31) in een 8x4 rooster
        LDX #0
SPR_GRID_LP:
        STX ZP_TMP_CNT
        TXA
        AND #7
        ASL A
        ASL A
        ASL A                   ; * 8
        STA ZP_W_LO
        ASL A
        ASL A                   ; * 32
        CLC
        ADC ZP_W_LO             ; * 40
        ADC #32
        STA ZP_X_LO
        LDA #0
        ADC #0
        STA ZP_X_HI

        TXA
        LSR A
        LSR A
        LSR A
        TAY
        LDA SPR_ROW_Y,Y
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        LDA #$FC
        STA ZP_FG_COL
        LDA ZP_TMP_CNT
        JSR DRAW_HEX_BYTE

        SEC
        LDA ZP_X_LO
        SBC #16
        STA ZP_X_LO
        LDA ZP_X_HI
        SBC #0
        STA ZP_X_HI
        CLC
        LDA ZP_Y_LO
        ADC #12
        STA ZP_Y_LO

        LDA #10                 ; GPU CMD 10 = DRAW_SPRITE
        STA IO_GPU
        LDA ZP_X_LO
        STA IO_GPU
        LDA ZP_X_HI
        STA IO_GPU
        LDA ZP_Y_LO
        STA IO_GPU
        LDA #0
        LDY #5
SG_Z:   STA IO_GPU
        DEY
        BNE SG_Z
        LDA ZP_TMP_CNT
        STA IO_GPU

        LDX ZP_TMP_CNT
        INX
        CPX #32
        BCC SPR_GRID_LP

        ; Zet BigSprite 0 op (366, 72) en BigSprite 1 op (500, 72) aan
        LDX #0
BS_EN_LP:
        LDA #21
        STA IO_GPU
        TXA
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA BIGSPR_X_LO,X
        STA IO_GPU
        LDA BIGSPR_X_HI,X
        STA IO_GPU
        LDA #72
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA BIG_MIRROR
        STA IO_GPU
        INX
        CPX #2
        BCC BS_EN_LP

        LDA #<STR_SPR_HEADERS
        LDY #>STR_SPR_HEADERS
        JMP DRAW_HDR_LIST

LOAD_SPREDIT_FROM_SD:
        JSR ROM_SD_INIT
        LDA #$F0
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDA #<SPR_LOAD_BUF
        STA ZP_DST
        LDA #>SPR_LOAD_BUF
        STA ZP_DST+1
        LDX #4
LSP_SEC:
        TXA
        PHA
        JSR ROM_READ_SEC
        PLA
        TAX
        DEX
        BNE LSP_SEC

        LDA #<SPR_LOAD_BUF
        STA ZP_PTR_LO
        LDA #>SPR_LOAD_BUF
        STA ZP_PTR_HI
        LDX #24
LSP_UP:
        LDA #9
        STA IO_GPU
        TXA
        STA IO_GPU
        LDY #0
LSP_BY:
        LDA (ZP_PTR_LO),Y
        STA IO_GPU
        INY
        BNE LSP_BY
        INC ZP_PTR_HI
        INX
        CPX #32
        BCC LSP_UP
        RTS

; ============================================================================
; MODUS 5 (index 4): 256-Kleuren RGB332 Master Palet & Kleuren-Inspecteur
; ============================================================================
DRAW_MODE_PALETTE:
        LDX #0
PAL_LP:
        STX ZP_TMP_CNT
        TXA
        AND #$0F
        ASL A
        ASL A
        ASL A                   ; * 8
        STA ZP_W_LO
        ASL A                   ; * 16
        CLC
        ADC ZP_W_LO             ; * 24
        ADC #48
        STA ZP_X_LO
        LDA #0
        ADC #0
        STA ZP_X_HI

        TXA
        LSR A
        LSR A
        LSR A
        LSR A
        STA ZP_H_LO
        ASL A
        ASL A
        ASL A
        ASL A                   ; * 16
        CLC
        ADC ZP_H_LO             ; * 17
        ADC #32
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        LDX ZP_TMP_CNT
        CPX PAL_SEL
        BNE PAL_SWATCH
        DEC ZP_X_LO
        DEC ZP_Y_LO
        LDA #22
        STA ZP_W_LO
        LDA #15
        STA ZP_H_LO
        LDA #$FF
        STA ZP_COL
        JSR DRAW_RECT_ZP
        INC ZP_X_LO
        INC ZP_Y_LO

PAL_SWATCH:
        LDA #20
        STA ZP_W_LO
        LDA #13
        STA ZP_H_LO
        LDA ZP_TMP_CNT
        CMP #$E3                ; Vermijd transparant gat in het palet-rooster!
        BNE PAL_C_OK
        LDA #$E2
PAL_C_OK:
        STA ZP_COL
        JSR DRAW_RECT_ZP

        LDX ZP_TMP_CNT
        INX
        BNE PAL_LP

        ; Teken rechts het Kleuren-Inspectie Paneel + grote swatch
        LDA #<PAL_PANEL_STREAM
        LDY #>PAL_PANEL_STREAM
        LDX #(PAL_PANEL_END - PAL_PANEL_STREAM)
        JSR SEND_GPU_STREAM

        LDA #<468
        STA ZP_X_LO
        LDA #>468
        STA ZP_X_HI
        LDA #68
        STA ZP_Y_LO
        LDA #136
        STA ZP_W_LO
        LDA #76
        STA ZP_H_LO
        LDA PAL_SEL
        CMP #$E3
        BNE PAL_SW_OK
        LDA #$E2
PAL_SW_OK:
        STA ZP_COL
        JSR DRAW_RECT_ZP

        LDA #<STR_PAL_PANEL
        LDY #>STR_PAL_PANEL
        JSR DRAW_HDR_LIST

        ; Toon RGB(r, g, b) componenten direct achter laatst getekende label!
        LDA #$1F
        STA ZP_FG_COL
        LDA PAL_SEL
        LSR A
        LSR A
        LSR A
        LSR A
        LSR A
        JSR DRAW_HEX_NIB
        LDA #','
        JSR DRAW_CHAR_ADV
        LDA PAL_SEL
        LSR A
        LSR A
        AND #7
        JSR DRAW_HEX_NIB
        LDA #','
        JSR DRAW_CHAR_ADV
        LDA PAL_SEL
        AND #3
        JSR DRAW_HEX_NIB

        ; Toon HEX waarde ($XX) op (540, 162)
        LDA #<540
        STA ZP_X_LO
        LDA #>540
        STA ZP_X_HI
        LDA #162
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_FG_COL
        LDA #'$'
        JSR DRAW_CHAR_ADV
        LDA PAL_SEL
        JMP DRAW_HEX_BYTE

; ============================================================================
; Bovenste Titelbalk & Onderste Statusbalk
; ============================================================================
DRAW_TOP_BAR:
        LDY #0
        LDA #18
        JSR DRAW_FULL_BAR

        LDA #<STR_TOP_HDR
        LDY #>STR_TOP_HDR
        JSR DRAW_HDR_LIST

        LDA #<416
        STA ZP_X_LO
        LDA #>416
        STA ZP_X_HI
        LDA #$FC
        STA ZP_FG_COL
        LDX VIEW_MODE
        LDA MODE_TITLE_LO,X
        LDY MODE_TITLE_HI,X
        JMP DRAW_AY_STR

DRAW_BOT_BAR:
        LDY #<340
        LDA #20
        JSR DRAW_FULL_BAR_340

        LDA #<STR_BOT_HDR
        LDY #>STR_BOT_HDR
        JSR DRAW_HDR_LIST

        LDA #<548
        STA ZP_X_LO
        LDA #>548
        STA ZP_X_HI
        LDA SLIDESHOW
        BEQ DBB_ZOOM
        LDA #$1C
        STA ZP_FG_COL
        LDA #<STR_SLIDE_ON
        LDY #>STR_SLIDE_ON
        JMP DRAW_AY_STR
DBB_ZOOM:
        LDA #$FC
        STA ZP_FG_COL
        LDA #<STR_ZM_LBL
        LDY #>STR_ZM_LBL
        JSR DRAW_AY_STR
        LDA ZOOM_LVL
        JSR DRAW_HEX_NIB
        LDA #'X'
        JMP DRAW_CHAR_ADV

DRAW_FULL_BAR_340:
        STY ZP_Y_LO
        LDY #1
        STY ZP_Y_HI
        JMP DFB_GO
DRAW_FULL_BAR:
        STY ZP_Y_LO
        STY ZP_Y_HI
DFB_GO:
        STA ZP_H_LO
        LDA #0
        STA ZP_X_LO
        STA ZP_X_HI
        LDA #<640
        STA ZP_W_LO
        LDA #>640
        STA ZP_W_HI
        LDX FRAME_THEME
        LDA THEME_BAR_COL,X
        STA ZP_COL
        JMP DRAW_RECT_16W

; ============================================================================
; Grafische SD-Kaart Plaatjes-Kiezer (O of ENTER) voor Drive D0..D3
; ============================================================================
OPEN_FILE_DIALOG:
        JSR READ_DIR_TO_CACHE
OFD_REDRAW:
        LDA #<DLG_BOX_STREAM
        LDY #>DLG_BOX_STREAM
        LDX #(DLG_BOX_END - DLG_BOX_STREAM)
        JSR SEND_GPU_STREAM

        LDA #154
        LDY #53
        JSR SET_XY_POS
        LDA #$00
        STA ZP_FG_COL
        LDA #<STR_DLG_TITLE
        LDY #>STR_DLG_TITLE
        JSR DRAW_AY_STR
        LDA DISK_DRIVE
        AND #3
        JSR DRAW_HEX_NIB

        LDX #0
OFD_SLOT_LP:
        STX ZP_TMP_CNT
        TXA
        ASL A
        ASL A                   ; * 4
        STA ZP_Y_LO
        ASL A                   ; * 8
        CLC
        ADC ZP_Y_LO             ; * 12
        ADC #72
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        CPX DLG_SEL
        BNE OFD_NO_HL
        LDA #148
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<344
        STA ZP_W_LO
        LDA #>344
        STA ZP_W_HI
        LDA #11
        STA ZP_H_LO
        LDA #$FC
        STA ZP_COL
        JSR DRAW_RECT_16W
        LDA #$00
        STA ZP_FG_COL
        JMP OFD_PRT_SL
OFD_NO_HL:
        LDA #$FF
        STA ZP_FG_COL

OFD_PRT_SL:
        LDA #156
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        INC ZP_Y_LO
        LDA #'#'
        JSR DRAW_CHAR_ADV
        LDA ZP_TMP_CNT
        JSR DRAW_HEX_NIB
        LDA #':'
        JSR DRAW_CHAR_ADV

        LDA ZP_TMP_CNT
        JSR SET_CACHE_SLOT_PTR
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #'B'
        BNE OFD_EMPTY
        INY
        LDA (ZP_PTR_LO),Y
        CMP #'B'
        BNE OFD_EMPTY

        LDY #4
OFD_FN_LP:
        LDA (ZP_PTR_LO),Y
        BEQ OFD_NEXT_S
        STY ZP_ROW_REM
        JSR DRAW_CHAR_ADV
        LDY ZP_ROW_REM
        INY
        CPY #18
        BCC OFD_FN_LP
        JMP OFD_NEXT_S

OFD_EMPTY:
        LDA #<STR_SLOT_FREE
        LDY #>STR_SLOT_FREE
        JSR DRAW_AY_STR

OFD_NEXT_S:
        LDX ZP_TMP_CNT
        INX
        CPX #15
        BCC OFD_SLOT_LP

        LDA #<STR_DLG_FOOT_HDR
        LDY #>STR_DLG_FOOT_HDR
        JSR DRAW_HDR_LIST

OFD_WAIT:
        JSR POLL_INPUT
        BEQ OFD_WAIT
        CMP #$1B
        BEQ OFD_CLOSE
        CMP #' '
        BEQ OFD_CLOSE
        CMP #'W'
        BEQ OFD_UP
        CMP #'S'
        BEQ OFD_DN
        CMP #$0D
        BEQ OFD_LOAD_SEL
        CMP #'1'
        BCC OFD_WAIT
        CMP #'5'
        BCS OFD_WAIT
        SEC
        SBC #'1'
        STA DISK_DRIVE
        JSR READ_DIR_TO_CACHE
        JMP OFD_REDRAW

OFD_UP:
        DEC DLG_SEL
        BPL OFD_REDRAW
        LDA #14
        STA DLG_SEL
        JMP OFD_REDRAW

OFD_DN:
        INC DLG_SEL
        LDA DLG_SEL
        CMP #15
        BCC OFD_REDRAW
        LDA #0
        STA DLG_SEL
        JMP OFD_REDRAW

NEXT_SD_IMG:
        JSR READ_DIR_TO_CACHE
        LDX #15
NSI_LP:
        INC DLG_SEL
        LDA DLG_SEL
        CMP #15
        BCC NSI_CHK
        LDA #0
        STA DLG_SEL
NSI_CHK:
        JSR SET_CACHE_SLOT_PTR
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #'B'
        BNE NSI_NXT
        LDY #24
        LDA (ZP_PTR_LO),Y
        CMP #>IMG_BUF
        BEQ OFD_DO_LOAD
NSI_NXT:
        DEX
        BNE NSI_LP
        JMP NEXT_VIEW_MODE

OFD_LOAD_SEL:
        LDA DLG_SEL
        JSR SET_CACHE_SLOT_PTR
        LDY #0
        LDA (ZP_PTR_LO),Y
        CMP #'B'
        BNE OFD_CLOSE
        LDY #24
        LDA (ZP_PTR_LO),Y
        CMP #>IMG_BUF
        BNE OFD_CLOSE
OFD_DO_LOAD:
        LDA DLG_SEL
        STA DISK_SLOT
        JSR SETUP_SLOT_SECTOR
        LDA #<IMG_BUF
        STA ZP_DST
        LDA #>IMG_BUF
        STA ZP_DST+1
        LDX #8
OFD_RD_LP:
        TXA
        PHA
        JSR ROM_READ_SEC
        PLA
        TAX
        DEX
        BNE OFD_RD_LP
        LDA #0
        STA VIEW_MODE
        JSR RESET_PAN_ZOOM

OFD_CLOSE:
        JMP DRAW_FULL_SCREEN

READ_DIR_TO_CACHE:
        JSR ROM_SD_INIT
        LDA #$FF
        STA DISK_SEC_LO
        LDA DISK_DRIVE
        AND #$3F
        ASL A
        ASL A
        CLC
        ADC #$03
        STA DISK_SEC_HI
        LDA #<DIR_CACHE
        STA ZP_DST
        LDA #>DIR_CACHE
        STA ZP_DST+1
        JMP ROM_READ_SEC

SET_CACHE_SLOT_PTR:
        STA ZP_PTR_LO
        LDA #0
        STA ZP_PTR_HI
        LDY #5
SCSP_LP:
        ASL ZP_PTR_LO
        ROL ZP_PTR_HI
        DEY
        BNE SCSP_LP
        CLC
        LDA ZP_PTR_LO
        ADC #<DIR_CACHE
        STA ZP_PTR_LO
        LDA ZP_PTR_HI
        ADC #>DIR_CACHE
        STA ZP_PTR_HI
        RTS

SETUP_SLOT_SECTOR:
        LDA DISK_SLOT
        AND #3
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        STA DISK_SEC_LO
        LDA DISK_DRIVE
        AND #$3F
        ASL A
        ASL A
        CLC
        ADC #$04
        STA DISK_SEC_HI
        LDA DISK_SLOT
        LSR A
        LSR A
        CLC
        ADC DISK_SEC_HI
        STA DISK_SEC_HI
        RTS

; ============================================================================
; ESC Popup-Menu (Spatie = Sluit zonder restjes, ESC/Q = Afsluiten)
; ============================================================================
OPEN_ESC_MENU:
        JSR HIDE_BIG_SPRITES
        LDA #<ESC_BOX_STREAM
        LDY #>ESC_BOX_STREAM
        LDX #(ESC_BOX_END - ESC_BOX_STREAM)
        JSR SEND_GPU_STREAM

        LDA #<STR_ESC_MENU
        LDY #>STR_ESC_MENU
        JSR DRAW_HDR_LIST

OEM_WAIT:
        JSR POLL_INPUT
        BEQ OEM_WAIT
        CMP #$1B
        BEQ EXIT_VIEWER
        CMP #'Q'
        BEQ EXIT_VIEWER
        CMP #' '
        BEQ OEM_CLS
        CMP #'O'
        BEQ DO_OPEN_DLG
        CMP #'R'
        BEQ DO_RESET_IMG
        CMP #'1'
        BCC OEM_WAIT
        CMP #'6'
        BCS OEM_WAIT
        JMP CK_MODES
OEM_CLS:
        JMP REDRAW_AND_MAIN

EXIT_VIEWER:
        JSR HIDE_BIG_SPRITES
        JSR ROM_SILENCE
        LDA #<EXIT_GPU_STREAM
        LDY #>EXIT_GPU_STREAM
        LDX #(EXIT_GPU_END - EXIT_GPU_STREAM)
        JSR SEND_GPU_STREAM
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

; ============================================================================
; GPU Teken-, Stream- en Tekst-Hulproutines
; ============================================================================
SEND_GPU_STREAM:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        STX ZP_STR_LEN
        LDY #0
SGS_LP: LDA (ZP_PTR_LO),Y
        STA IO_GPU
        INY
        CPY ZP_STR_LEN
        BCC SGS_LP
        RTS

DRAW_RECT_ZP:
        LDA #0
        STA ZP_W_HI
DRAW_RECT_16W:
        LDA #2
        STA IO_GPU
        LDX #0
DR16_LP:
        LDA ZP_X_LO,X
        STA IO_GPU
        INX
        CPX #7
        BCC DR16_LP
        LDA #0
        STA IO_GPU
        LDA ZP_COL
        STA IO_GPU
        RTS

SET_XY_POS:
        STA ZP_X_LO
        STY ZP_Y_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        RTS

DRAW_HDR_LIST:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DHL_LP:
        JSR NEXT_PTR_BYTE
        STA ZP_X_LO
        JSR NEXT_PTR_BYTE
        STA ZP_X_HI
        LDA ZP_X_LO
        ORA ZP_X_HI
        BEQ DHL_RTS
        JSR NEXT_PTR_BYTE
        STA ZP_Y_LO
        JSR NEXT_PTR_BYTE
        STA ZP_Y_HI
        JSR NEXT_PTR_BYTE
        STA ZP_FG_COL
        JSR DRAW_ZP_STR
        JMP DHL_LP
DHL_RTS:
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
DRAW_CHAR_ADV:
        PHA
        LDA #8
        STA IO_GPU
        LDX #0
DCA_XY: LDA ZP_X_LO,X
        STA IO_GPU
        INX
        CPX #4
        BCC DCA_XY
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
        BCC DCA_RTS
        INC ZP_X_HI
DCA_RTS:
        RTS

; ============================================================================
; Tabellen, Streams & Teksten
; ============================================================================
JOY_MASK_TBL:   .BYTE $01, $02, $04, $08, $10
JOY_CHAR_TBL:   .BYTE 'W', 'S', 'A', 'D', ' '
NAV_PAN_D:      .BYTE $F0, 16,  $F0, 16
NAV_MAP_D:      .BYTE $FE, 2,   $FE, 2
NAV_PAL_D:      .BYTE $F0, 16,  $FF, 1

THEME_BG_COL:     .BYTE $01, $00, $20, $49
THEME_BAR_COL:    .BYTE $09, $44, $42, $24
THEME_BORDER_COL: .BYTE $1F, $FC, $EB, $FF

ZOOM_BASE_X_LO: .BYTE <(260), <(200), <(140)
ZOOM_BASE_X_HI: .BYTE >(260), >(200), >(140)
ZOOM_BASE_Y:    .BYTE 140,    100,    60
ZOOM_FRAME_W_LO:.BYTE <(128), <(248), <(368)
ZOOM_FRAME_W_HI:.BYTE >(128), >(248), >(368)
ZOOM_FRAME_H:   .BYTE 88,     168,    248

SPR_ROW_Y:      .BYTE 76, 134, 192, 250
BIGSPR_X_LO:    .BYTE <366, <500
BIGSPR_X_HI:    .BYTE >366, >500

MODE_TITLE_LO:  .BYTE <STR_M0_T, <STR_M1_T, <STR_M2_T, <STR_M3_T, <STR_M4_T
MODE_TITLE_HI:  .BYTE >STR_M0_T, >STR_M1_T, >STR_M2_T, >STR_M3_T, >STR_M4_T

STR_M0_T:       .ASCIIZ "[1:SD/RLE PLAATJE]"
STR_M1_T:       .ASCIIZ "[2:RUIMTEHAVEN 20K]"
STR_M2_T:       .ASCIIZ "[3:32 SPRITES+BIG]"
STR_M3_T:       .ASCIIZ "[4:64X64 WERELDMAP]"
STR_M4_T:       .ASCIIZ "[5:256 KLEURENPALET]"

STR_TOP_HDR:    .BYTE 10,0, 5,0, $FF, "MiniGPU IMAGEVIEWER & ART GALLERY 6502", 0, 0,0
STR_BOT_HDR:    .BYTE 8,0, (346 & $FF),(346 >> 8), $FF, "1-5:Beeld O/ENT:SD Z:Zoom PIJL:Pan P:Show F:Vol ESC:Menu", 0, 0,0
STR_SLIDE_ON:   .ASCIIZ "[DIASHOW]"
STR_ZM_LBL:     .ASCIIZ "ZOOM:"
STR_DLG_TITLE:  .ASCIIZ "SD-KAART PLAATJES KIEZER - DRIVE D"
STR_SLOT_FREE:  .ASCIIZ " - vrij -"

; Vector-kunstwerk Modus 2 ("Ruimtehaven Tang-20K")
SPACEPORT_STREAM:
        .BYTE 2, 0,0, 18,0, $80,$02, 210,0, $01
        .BYTE 2, 0,0, 228,0, $80,$02, 112,0, $20
        .BYTE 5, $EA,$01, 105,0, 44,0, 0,0, $83
        .BYTE 5, $E2,$01, 98,0,  32,0, 0,0, $EB
        .BYTE 4, $EA,$01, 105,0, 44,0, 0,0, $FF
        .BYTE 3, $A4,$01, 125,0, $2E,$02, 85,0, $FC
        .BYTE 3, $A4,$01, 127,0, $2E,$02, 87,0, $F0
        .BYTE 5, 110,0, 82,0, 24,0, 0,0, $FC
        .BYTE 5, 104,0, 76,0, 16,0, 0,0, $FF
        .BYTE 7, 20,0, 228,0, 140,0, 118,0, 155,0, 228,0, $1F
        .BYTE 7, 155,0, 228,0, 140,0, 118,0, $10,$01, 228,0, $09
        .BYTE 7, 220,0, 228,0, $54,$01, 96,0, $68,$01, 228,0, $E8
        .BYTE 7, $68,$01, 228,0, $54,$01, 96,0, $DC,$01, 228,0, $80
        .BYTE 2, 180,0, 260,0, $18,$01, 14,0, $6D
        .BYTE 2, 200,0, 274,0, 240,0, 10,0, $49
        .BYTE 7, 250,0, 258,0, $40,$01, 195,0, $86,$01, 258,0, $FF
        .BYTE 6, 250,0, 258,0, $40,$01, 195,0, $86,$01, 258,0, $1F
        .BYTE 5, $40,$01, 236,0, 14,0, 0,0, $1F
SPACEPORT_END:

; Kaders voor Modus 3 (32 Sprites + 2x 128x128 BigSprites met $E3 doorkijkvensters!)
SPR_PANEL_STREAM:
        .BYTE 2, 16,0, 34,0, $50,$01, $20,$01, $24
        .BYTE 2, $68,$01, 34,0, $0A,$01, $20,$01, $24
        .BYTE 2, $6E,$01, 72,0, 128,0, 128,0, $E3
        .BYTE 2, $F4,$01, 72,0, 128,0, 128,0, $E3
SPR_PANEL_END:

PAL_PANEL_STREAM:
        .BYTE 2, $C0,$01, 34,0, 176,0, 254,0, $24
PAL_PANEL_END:

DLG_BOX_STREAM:
        .BYTE 2, 140,0, 46,0, $68,$01, $0C,$01, $1F
        .BYTE 2, 142,0, 48,0, $64,$01, $08,$01, $01
        .BYTE 2, 142,0, 48,0, $64,$01, 18,0, $1F
DLG_BOX_END:

ESC_BOX_STREAM:
        .BYTE 2, 144,0, 76,0, $60,$01, 168,0, $FC
        .BYTE 2, 146,0, 78,0, $5C,$01, 164,0, $00
        .BYTE 2, 146,0, 78,0, $5C,$01, 18,0, $FC
ESC_BOX_END:

EXIT_GPU_STREAM:
        .BYTE 15, 0,0,0,0
        .BYTE 12, 1, 1, $E3
EXIT_GPU_END:

STR_ART2_CAPTION:
        .BYTE 196,0, (302 & $FF),(302 >> 8), $FC, "KUNSTWERK #2: RUIMTEHAVEN TANG-20K", 0
        .BYTE 0,0

STR_SPR_HEADERS:
        .BYTE 26,0, 44,0, $FC, "ALLE 32 SPRITES (16X16):", 0
        .BYTE $72,$01, 44,0, $1F, "2X 128X128 BIGSPRITES:", 0
        .BYTE $72,$01, 216,0, $FF, "BIGSPR 0       BIGSPR 1", 0
        .BYTE $72,$01, 248,0, $FC, "M:Spiegel  L:Laad SPREDIT", 0
        .BYTE 0,0

STR_PAL_PANEL:
        .BYTE $CA,$01, 44,0, $FC, "256-KLEUREN KIEZER", 0
        .BYTE $CA,$01, 162,0, $FF, "HEX CODE :", 0
        .BYTE $CA,$01, 216,0, $1C, "Pijltjes/WASD: Kies", 0
        .BYTE $CA,$01, 244,0, $FC, "$E3:Doorkijk $EB:Roze", 0
        .BYTE $CA,$01, 184,0, $FF, "RGB(r,g,b):", 0
        .BYTE 0,0

STR_DLG_FOOT_HDR:
        .BYTE 152,0, (298 & $FF),(298 >> 8), $1F, "1-4:Drv PIJL+ENT:Open SPATIE:Sluit", 0
        .BYTE 0,0

STR_ESC_MENU:
        .BYTE 168,0, 83,0,  $00, "== IMAGEVIEWER 6502 MENU ==", 0
        .BYTE 160,0, 110,0, $FF, "[1-5] Kies Galerij / Modus", 0
        .BYTE 160,0, 130,0, $1F, "[O/N] Open / Volgend Plaatje", 0
        .BYTE 160,0, 150,0, $1C, "[R]   Reset Cyber-Sunset", 0
        .BYTE 160,0, 180,0, $FC, "[SPATIE] Sluit [ESC/Q] Stop", 0
        .BYTE 0,0

BUILTIN_IMG_DATA:
        .BYTE $4D, $49, $4D, $47, $78, $50, $03, $01, $78, $01, $78, $01, $78, $01, $30, $01
        .BYTE $01, $FF, $47, $01, $0E, $01, $01, $FF, $69, $01, $56, $01, $01, $FF, $21, $01
        .BYTE $78, $01, $78, $01, $78, $02, $78, $02, $6A, $02, $01, $FF, $0D, $02, $78, $02
        .BYTE $78, $02, $78, $02, $78, $02, $78, $42, $3C, $42, $01, $FC, $3B, $42, $37, $42
        .BYTE $0B, $FC, $36, $42, $34, $42, $11, $FC, $33, $42, $33, $42, $13, $FC, $32, $42
        .BYTE $31, $42, $17, $FC, $30, $42, $30, $42, $19, $FC, $2F, $42, $2F, $82, $1B, $FC
        .BYTE $2E, $82, $2E, $82, $1D, $FC, $2D, $82, $2E, $82, $1D, $FC, $2D, $82, $2D, $82
        .BYTE $1F, $FC, $2C, $82, $2C, $82, $21, $FC, $2B, $82, $2C, $82, $21, $FC, $2B, $82
        .BYTE $2C, $82, $21, $F8, $2B, $82, $2B, $C2, $23, $F8, $2A, $C2, $2B, $C2, $23, $F8
        .BYTE $2A, $C2, $0F, $C2, $0C, $00, $10, $C2, $23, $F8, $2A, $C2, $0C, $C2, $12, $00
        .BYTE $0D, $C2, $23, $F8, $2A, $C2, $09, $C2, $18, $00, $0A, $C2, $23, $F8, $2A, $C2
        .BYTE $08, $C2, $1A, $00, $08, $C2, $25, $F8, $29, $C2, $0A, $E4, $13, $00, $0E, $E4
        .BYTE $23, $F8, $2A, $E4, $15, $E4, $03, $00, $13, $E4, $23, $F0, $0C, $E4, $01, $20
        .BYTE $1D, $E4, $15, $E4, $03, $00, $01, $20, $40, $E4, $03, $20, $1C, $E4, $15, $E4
        .BYTE $03, $00, $02, $20, $11, $E4, $23, $F0, $0A, $E4, $05, $20, $1B, $E4, $15, $E4
        .BYTE $03, $00, $03, $20, $10, $E4, $23, $F0, $09, $E4, $07, $20, $1A, $E4, $15, $E4
        .BYTE $03, $00, $04, $20, $3A, $E4, $09, $20, $19, $E4, $14, $F0, $01, $20, $03, $00
        .BYTE $05, $20, $37, $F0, $0D, $20, $17, $F0, $13, $F0, $01, $20, $03, $00, $07, $20
        .BYTE $35, $F0, $0F, $20, $16, $F0, $11, $F0, $03, $20, $03, $00, $09, $20, $32, $F0
        .BYTE $11, $20, $15, $F0, $10, $F0, $04, $20, $03, $00, $0A, $20, $30, $F0, $13, $20
        .BYTE $14, $F0, $0F, $FC, $05, $20, $03, $00, $0B, $20, $2D, $FC, $17, $20, $12, $FC
        .BYTE $0E, $FC, $06, $20, $03, $00, $0C, $20, $0C, $FC, $1B, $F0, $04, $FC, $19, $20
        .BYTE $11, $FC, $0D, $FC, $07, $20, $03, $00, $0D, $20, $29, $FC, $1B, $20, $10, $FC
        .BYTE $14, $1F, $03, $00, $17, $1F, $1D, $FC, $2D, $1F, $14, $09, $03, $00, $61, $09
        .BYTE $13, $05, $03, $00, $19, $05, $1B, $FC, $2E, $05, $13, $09, $03, $00, $62, $09
        .BYTE $13, $05, $03, $00, $1A, $05, $19, $FC, $2F, $05, $13, $09, $03, $00, $62, $09
        .BYTE $13, $1F, $03, $00, $1B, $1F, $17, $FC, $30, $1F, $13, $09, $03, $00, $62, $09
        .BYTE $13, $05, $03, $00, $1C, $05, $15, $FC, $31, $05, $13, $09, $03, $00, $62, $09
        .BYTE $12, $05, $03, $00, $1E, $05, $13, $F0, $32, $05, $12, $09, $03, $00, $63, $09
        .BYTE $12, $05, $03, $00, $1F, $05, $11, $F0, $33, $05, $12, $09, $03, $00, $63, $09
        .BYTE $12, $1F, $03, $00, $20, $1F, $0F, $F0, $34, $1F, $12, $09, $03, $00, $63, $09
        .BYTE $10, $00, $02, $05, $03, $00, $21, $05, $0D, $F0, $35, $05, $11, $00, $67, $09
        .BYTE $12, $00, $25, $05, $0B, $F0, $36, $05, $13, $00, $65, $09, $14, $00, $24, $05
        .BYTE $09, $F0, $37, $05, $15, $00, $63, $09, $16, $00, $23, $05, $07, $F0, $38, $05
        .BYTE $17, $00, $61, $09, $18, $00, $22, $1F, $05, $F0, $39, $1F, $19, $00, $5F, $09
        .BYTE $1A, $00, $21, $05, $03, $F0, $3A, $05, $1B, $00, $5D, $09, $1C, $00, $5C, $05
        .BYTE $1D, $00, $5B, $09, $1E, $00, $5A, $05, $1F, $00, $59, $09, $00
