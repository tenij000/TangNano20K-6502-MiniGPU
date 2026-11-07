; ============================================================================
; PACMAN65.asm - 60 FPS Arcade Pac-Man in 6502 Machinecode ($8000)
; Voor Tang Nano 20K DONDERDAG MiniGPU-BASIC 1.1
; Starten in BASIC met:  BRUN PACMAN65   (of via Midnight Commander: BRUN MC)
; ============================================================================
        ORG $8000

; --- Zero Page Variabelen ($60..$9F) ---
; Coördinaten X2 en Y2 zijn in stappen van 2 pixels (1 tegel = 8 eenheden = 16 px).
; Hierdoor passen alle X (8..216 -> 16..432 px) en Y (8..168 -> 16..336 px) in 1 byte!
ZP_M_LO         = $60   ; Pointer naar MAZE_RAM ($7800 + my*32)
ZP_M_HI         = $61
ZP_PTR_LO       = $62   ; Algemene 16-bit pointer
ZP_PTR_HI       = $63
ZP_X_LO         = $64   ; 16-bit GPU X & Y voor tekst/HUD
ZP_X_HI         = $65
ZP_Y_LO         = $66
ZP_Y_HI         = $67
ZP_COL          = $68
ZP_TMP1         = $69   ; Huidige mx
ZP_TMP2         = $6A   ; Huidige my
ZP_TMP3         = $6B   ; Kandidaat-richting / kras-register
ZP_TMP4         = $6C   ; Verboden omkeer-richting
ZP_GIDX         = $6D   ; Huidige spook-index (0..3)

FRAME_CNT       = $70
LIVES           = $71
LEVEL           = $72
DOTS_LEFT       = $73
FRIGHT_TIMER    = $74
SND_TIMER       = $75
SND_PITCH       = $76
WAKA_TOGGLE     = $77
HUD_DIRTY       = $78

SCORE_LO        = $79   ; 16-bit Score
SCORE_HI        = $7A
HSCORE_LO       = $7B   ; 16-bit High Score
HSCORE_HI       = $7C

; Pac-Man status (in 2px eenheden: mx*8, my*8)
PAC_X           = $80
PAC_Y           = $81
PAC_OLD_X       = $82
PAC_OLD_Y       = $83
PAC_DIR         = $84   ; 0=Omhoog, 1=Omlaag, 2=Links, 3=Rechts
PAC_WANT        = $85

; 4 Spoken (0=Blinky, 1=Pinky, 2=Inky, 3=Clyde)
G_X             = $86   ; 4 bytes ($86..$89)
G_Y             = $8A   ; 4 bytes ($8A..$8D)
G_OLD_X         = $8E   ; 4 bytes ($8E..$91)
G_OLD_Y         = $92   ; 4 bytes ($92..$95)
G_DIR           = $96   ; 4 bytes ($96..$99)

; Tegel-ID's in Hardware Tilemap (slots 16..21)
T_EMPTY         = 16
T_WALL          = 17
T_DOT           = 18
T_POWER         = 19
T_GATE          = 20
T_CHERRY        = 21

; Sprite-ID's in Hardware Sprite RAM (slots 16..27)
SPR_PAC_R       = 16
SPR_PAC_L       = 17
SPR_PAC_U       = 18
SPR_PAC_D       = 19
SPR_PAC_CL      = 20
SPR_BLINKY      = 21
SPR_PINKY       = 22
SPR_INKY        = 23
SPR_CLYDE       = 24
SPR_GHOST_BLU   = 25
SPR_GHOST_WHT   = 26
SPR_DEATH       = 27

; ============================================================================
; Hoofdprogramma Startpunt ($8000)
; ============================================================================
START:
        ; Wis groene tekst-terminal en schakel naar MODE 1 (volledig scherm graphics)
        LDA #12
        STA IO_TERM
        LDA #0
        STA IO_MODE

        ; Zet BigSprites uit en zet SCROLL op 0, 0
        JSR INIT_GPU_STATE

        ; Upload custom 16x16 Sprites (16..27) naar FPGA BRAM
        JSR UPLOAD_CUSTOM_SPRITES

        ; Initialiseer High Score op 1000 als die nog 0 is
        LDA HSCORE_LO
        ORA HSCORE_HI
        BNE INIT_NEW_GAME
        LDA #$E8        ; 1000 = $03E8
        STA HSCORE_LO
        LDA #$03
        STA HSCORE_HI

INIT_NEW_GAME:
        LDA #0
        STA SCORE_LO
        STA SCORE_HI
        LDA #3
        STA LIVES
        LDA #1
        STA LEVEL

INIT_LEVEL:
        ; Upload custom 16x16 Arcade Tiles (16..21) met Stage-afhankelijke Neon Muurkleur!
        JSR UPLOAD_CUSTOM_TILES

        ; Zet GPU op TARGET 1 (frontbuffer) en maak scherm transparant ($E3) zodat Tilemap zichtbaar is
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #$E3
        STA IO_GPU

        ; Bouw het 27x21 doolhof op in $7800 én in de FPGA Hardware Tilemap
        JSR BUILD_MAZE_AND_TILES

        ; Teken het Arcade Zijpaneel rechts (X = 448..639)
        JSR DRAW_HUD_PANEL
        JSR UPDATE_HUD_NUMBERS

        ; Zet Pac-Man & de 4 Spoken op hun startposities en speel de Intro Jingle
        JSR RESET_POSITIONS
        JSR DRAW_ALL_ENTITIES
        JSR SAVE_OLD_POSITIONS
        JSR PLAY_INTRO_JINGLE

; ============================================================================
; 60 FPS Hoofdlus
; ============================================================================
MAIN_LOOP:
        ; Wacht ~20 ms via 100 Hz hardware timer ($A003) voor vloeiende 50/60 FPS arcade-snelheid
        LDA #2
        JSR WAIT_10MS
        INC FRAME_CNT

        ; 1. Lees Besturing (PS/2 Joypad, Pijltjes, WASD, of ESC/Q om te stoppen)
        JSR READ_CONTROLS
        BCC ML_CONT
        JMP QUIT_GAME
ML_CONT:

        ; 2. Beweeg Pac-Man en controleer opgegeten stippen / krachtpillen / kers
        JSR UPDATE_PACMAN

        ; 3. Beweeg de 4 Spoken (Blinky, Pinky, Inky, Clyde)
        JSR UPDATE_GHOSTS

        ; 4. Controleer botsingen tussen Pac-Man en de 4 Spoken
        JSR CHECK_COLLISIONS
        LDA LIVES
        BNE ML_ALIVE
        JMP HANDLE_GAME_OVER
ML_ALIVE:

        ; 5. Controleer of alle stippen op zijn -> Volgende Level!
        LDA DOTS_LEFT
        BNE ML_RENDER
        JSR LEVEL_CLEAR_SEQ
        INC LEVEL
        JMP INIT_LEVEL

ML_RENDER:
        ; 6. Wis oude 16x16 posities naar $E3 (transparant) en teken nieuwe sprites!
        JSR ERASE_OLD_ENTITIES
        JSR DRAW_ALL_ENTITIES
        JSR SAVE_OLD_POSITIONS

        ; 7. Werk geluidseffecten en Score-display bij
        JSR UPDATE_AUDIO
        LDA HUD_DIRTY
        BEQ MAIN_LOOP
        JSR UPDATE_HUD_NUMBERS
        LDA #0
        STA HUD_DIRTY
        JMP MAIN_LOOP

; ============================================================================
; Besturing & Invoer
; ============================================================================
READ_CONTROLS:
        LDA IO_STATUS
        BMI RC_QUIT_ESC
        AND #1
        BEQ RC_READ_JOY
        LDA IO_TERM
        AND #$DF
        CMP #'Q'
        BEQ RC_QUIT
        CMP #'N'        ; Sneltoets 'N' = Direct naar volgende Stage/Doolhof!
        BNE RC_K0
        LDA #0
        STA DOTS_LEFT
        JMP RC_READ_JOY
RC_K0:  CMP #'W'
        BNE RC_K1
        LDA #0
        STA PAC_WANT
RC_K1:  CMP #'S'
        BNE RC_K2
        LDA #1
        STA PAC_WANT
RC_K2:  CMP #'A'
        BNE RC_K3
        LDA #2
        STA PAC_WANT
RC_K3:  CMP #'D'
        BNE RC_READ_JOY
        LDA #3
        STA PAC_WANT

RC_READ_JOY:
        LDA IO_JOY
        TAX
        AND #1          ; Omhoog
        BEQ RC_J2
        LDA #0
        STA PAC_WANT
        JMP RC_OK
RC_J2:  TXA
        AND #2          ; Omlaag
        BEQ RC_J4
        LDA #1
        STA PAC_WANT
        JMP RC_OK
RC_J4:  TXA
        AND #4          ; Links
        BEQ RC_J8
        LDA #2
        STA PAC_WANT
        JMP RC_OK
RC_J8:  TXA
        AND #8          ; Rechts
        BEQ RC_OK
        LDA #3
        STA PAC_WANT
RC_OK:
        CLC
        RTS
RC_QUIT_ESC:
        LDA IO_TERM
RC_QUIT:
        SEC
        RTS

; ============================================================================
; Pac-Man Beweging, Tunnel-Wrap & Stippen Eten
; ============================================================================
UPDATE_PACMAN:
        ; 180 graden omkeren mag op elk moment (ook midden op een tegel!)
        LDA PAC_DIR
        EOR #1
        CMP PAC_WANT
        BNE UP_CHK_ALIGN
        LDA PAC_WANT
        STA PAC_DIR

UP_CHK_ALIGN:
        ; Staat Pac-Man precies op een 16x16 tegel-kruispunt? ((X2 & 7) == 0 en (Y2 & 7) == 0)
        LDA PAC_X
        AND #7
        BNE UP_DO_MOVE_JMP
        LDA PAC_Y
        AND #7
        BEQ UP_AT_CENTER
UP_DO_MOVE_JMP:
        JMP UP_DO_MOVE

UP_AT_CENTER:
        ; Bereken huidige tegel mx = PAC_X >> 3, my = PAC_Y >> 3
        LDA PAC_X
        LSR A
        LSR A
        LSR A
        STA ZP_TMP1
        TAY
        LDA PAC_Y
        LSR A
        LSR A
        LSR A
        STA ZP_TMP2

        ; Controleer of er een stip, krachtpil of kers op deze tegel ligt!
        JSR GET_MAZE_CELL
        CMP #T_DOT
        BNE UP_CHK_POW
        ; Gewone Pac-Dot (+10 punten)
        LDA #T_EMPTY
        JSR CLEAR_CURRENT_TILE
        DEC DOTS_LEFT
        LDA #10
        JSR ADD_SCORE
        LDA WAKA_TOGGLE
        EOR #1
        STA WAKA_TOGGLE
        BEQ UP_WAKA_HI
        LDA #68
        JMP UP_WAKA_SET
UP_WAKA_HI:
        LDA #92
UP_WAKA_SET:
        STA SND_PITCH
        LDA #4
        STA SND_TIMER
        JMP UP_TURN_LOGIC

UP_CHK_POW:
        CMP #T_POWER
        BNE UP_CHK_CHR
        ; Krachtpil! (+50 punten, spoken worden blauw, duur neemt af per Stage!)
        LDA #T_EMPTY
        JSR CLEAR_CURRENT_TILE
        DEC DOTS_LEFT
        LDA #50
        JSR ADD_SCORE
        LDX LEVEL
        DEX
        CPX #8
        BCC UP_POW_IX
        LDX #7
UP_POW_IX:
        LDA FRIGHT_DUR_TBL,X
        STA FRIGHT_TIMER
        LDA #130
        STA SND_PITCH
        LDA #10
        STA SND_TIMER
        JMP UP_TURN_LOGIC

UP_CHK_CHR:
        CMP #T_CHERRY
        BNE UP_TURN_LOGIC
        ; Bonus Kers! (+100 punten)
        LDA #T_EMPTY
        JSR CLEAR_CURRENT_TILE
        LDA #100
        JSR ADD_SCORE
        LDA #175
        STA SND_PITCH
        LDA #14
        STA SND_TIMER

UP_TURN_LOGIC:
        ; Check Warp-Tunnel op rij my=11 (links mx=1 <-> rechts mx=27)
        LDA ZP_TMP1
        CMP #1
        BNE UP_CHK_R_TUN
        LDA PAC_DIR
        CMP #2
        BNE UP_TRY_WANT
        LDA #216        ; mx = 27 -> 27 * 8 = 216
        STA PAC_X
        RTS
UP_CHK_R_TUN:
        CMP #27
        BNE UP_TRY_WANT
        LDA PAC_DIR
        CMP #3
        BNE UP_TRY_WANT
        LDA #8          ; mx = 1 -> 1 * 8 = 8
        STA PAC_X
        RTS

UP_TRY_WANT:
        ; Kunnen we op dit kruispunt afslaan in richting PAC_WANT?
        LDX PAC_WANT
        JSR CHECK_PASSABLE_FROM_TMP
        BCS UP_CAN_TURN
        ; Zo nee: kunnen we rechtdoor blijven lopen in richting PAC_DIR?
        LDX PAC_DIR
        JSR CHECK_PASSABLE_FROM_TMP
        BCS UP_DO_MOVE
        RTS             ; Muur voor ons -> sta stil!

UP_CAN_TURN:
        LDA PAC_WANT
        STA PAC_DIR

UP_DO_MOVE:
        LDX PAC_DIR
        CPX #0
        BNE UPM_1
        DEC PAC_Y
        RTS
UPM_1:  CPX #1
        BNE UPM_2
        INC PAC_Y
        RTS
UPM_2:  CPX #2
        BNE UPM_3
        DEC PAC_X
        RTS
UPM_3:  INC PAC_X
        RTS

; Zet tegel (ZP_TMP1=mx, ZP_TMP2=my) op A in MAZE_RAM én FPGA Tilemap
CLEAR_CURRENT_TILE:
        PHA
        LDY ZP_TMP1
        LDA ZP_TMP2
        JSR GET_MAZE_CELL
        PLA
        STA (ZP_M_LO),Y
        PHA
        LDA #23         ; GPU cmd 23 = SET_SINGLE_TILE (mx, my+32, id)
        STA IO_GPU
        LDA ZP_TMP1
        STA IO_GPU
        LDA ZP_TMP2
        ORA #32
        STA IO_GPU
        PLA
        STA IO_GPU
        RTS

; Check of buurtegel vanuit (ZP_TMP1=mx, ZP_TMP2=my) in richting X (0..3) vrij is voor Pac-Man
CHECK_PASSABLE_FROM_TMP:
        CLC
        LDA ZP_TMP1
        ADC DIR_DX,X
        TAY
        CLC
        LDA ZP_TMP2
        ADC DIR_DY,X
        JSR GET_MAZE_CELL
        CMP #T_WALL
        BEQ CPF_NO
        CMP #T_GATE
        BEQ CPF_NO
        SEC
        RTS
CPF_NO:
        CLC
        RTS

; ============================================================================
; 4 Spoken AI & Beweging (Blinky, Pinky, Inky, Clyde)
; ============================================================================
UPDATE_GHOSTS:
        LDA FRIGHT_TIMER
        BEQ UG_CHK_SPD
        DEC FRIGHT_TIMER
        LDA FRAME_CNT
        AND #1
        BEQ UG_START_LOOP
        RTS             ; Halve snelheid als spoken blauw zijn!

UG_CHK_SPD:
        ; Oplopende spooksnelheid per Stage:
        ; Stage 1: pauzeer elke 8e frame (87.5% snelheid)
        ; Stage 2: pauzeer elke 16e frame (93.75% snelheid)
        ; Stage 3+: 100% topsnelheid!
        LDA LEVEL
        CMP #1
        BNE UG_SPD_S2
        LDA FRAME_CNT
        AND #7
        BNE UG_START_LOOP
        RTS
UG_SPD_S2:
        CMP #2
        BNE UG_START_LOOP
        LDA FRAME_CNT
        AND #15
        BNE UG_START_LOOP
        RTS

UG_START_LOOP:
        LDX #0
        STX ZP_GIDX
UG_LOOP:
        LDX ZP_GIDX
        ; Check of spook op een 16x16 tegel-kruispunt staat ((G_X & 7) == 0 en (G_Y & 7) == 0)
        LDA G_X,X
        AND #7
        BNE UG_MOVE_JMP
        LDA G_Y,X
        AND #7
        BEQ UG_AT_CENTER
UG_MOVE_JMP:
        JMP UG_MOVE_STEP

UG_AT_CENTER:
        LDA G_X,X
        LSR A
        LSR A
        LSR A
        STA ZP_TMP1
        LDA G_Y,X
        LSR A
        LSR A
        LSR A
        STA ZP_TMP2

        ; Check tunnel wrap op rij my=11
        LDA ZP_TMP1
        CMP #1
        BNE UG_CHK_RT
        LDA G_DIR,X
        CMP #2
        BNE UG_CHOOSE_DIR
        LDA #216
        STA G_X,X
        JMP UG_NEXT_GHOST
UG_CHK_RT:
        CMP #27
        BNE UG_CHOOSE_DIR
        LDA G_DIR,X
        CMP #3
        BNE UG_CHOOSE_DIR
        LDA #8
        STA G_X,X
        JMP UG_NEXT_GHOST

UG_CHOOSE_DIR:
        ; Als spook in het Spookhuis zit (my == 11 en mx tussen 12 en 16) -> naar mx=14 en OMHOOG!
        LDA ZP_TMP2
        CMP #11
        BNE UG_CHK_GATE_ROW
        LDA ZP_TMP1
        CMP #12
        BCC UG_NORMAL_AI
        CMP #17
        BCS UG_NORMAL_AI
        CMP #14
        BEQ UG_EXIT_UP
        BCC UG_EXIT_RIGHT
        LDA #2
        STA G_DIR,X
        JMP UG_MOVE_STEP
UG_EXIT_RIGHT:
        LDA #3
        STA G_DIR,X
        JMP UG_MOVE_STEP
UG_EXIT_UP:
        LDA #0
        STA G_DIR,X
        JMP UG_MOVE_STEP

UG_CHK_GATE_ROW:
        ; Als spook precies OP het hekje staat (my == 10, mx == 14) -> loop door OMHOOG naar my=9!
        CMP #10
        BNE UG_NORMAL_AI
        LDA ZP_TMP1
        CMP #14
        BNE UG_NORMAL_AI
        LDA #0
        STA G_DIR,X
        JMP UG_MOVE_STEP

UG_NORMAL_AI:
        ; Verboden omkeer-richting = G_DIR[X] ^ 1
        LDA G_DIR,X
        EOR #1
        STA ZP_TMP4

        ; Als niet blauw: jaag-kans neemt toe per Stage (Stage 1: ~45% -> Stage 4+: ~90%)
        LDA FRIGHT_TIMER
        BNE UG_RANDOM_PICK
        SEC
        LDA #4
        SBC LEVEL
        BCS UG_AGG_POS
        LDA #0
UG_AGG_POS:
        CLC
        ADC ZP_GIDX
        STA ZP_TMP3
        LDA IO_RND
        AND #7
        CMP ZP_TMP3
        BCC UG_RANDOM_PICK

        LDA IO_RND
        AND #1
        BNE UG_TRY_VERT

        ; Horizontaal richting Pac-Man
        LDA PAC_X
        CMP G_X,X
        BCC UG_WANT_L
        LDA #3
        JMP UG_TRY_CAND
UG_WANT_L:
        LDA #2
        JMP UG_TRY_CAND

UG_TRY_VERT:
        LDA PAC_Y
        CMP G_Y,X
        BCC UG_WANT_U
        LDA #1
        JMP UG_TRY_CAND
UG_WANT_U:
        LDA #0

UG_TRY_CAND:
        CMP ZP_TMP4
        BEQ UG_RANDOM_PICK
        STA ZP_TMP3
        TAX
        JSR CHECK_GHOST_PASSABLE
        BCC UG_RANDOM_PICK
        LDX ZP_GIDX
        LDA ZP_TMP3
        STA G_DIR,X
        JMP UG_MOVE_STEP

UG_RANDOM_PICK:
        LDA IO_RND
        AND #3
        STA ZP_TMP3
        LDY #4
UG_RND_LP:
        LDA ZP_TMP3
        CMP ZP_TMP4
        BEQ UG_RND_NXT
        TAX
        JSR CHECK_GHOST_PASSABLE
        BCC UG_RND_NXT
        LDX ZP_GIDX
        LDA ZP_TMP3
        STA G_DIR,X
        JMP UG_MOVE_STEP
UG_RND_NXT:
        INC ZP_TMP3
        LDA ZP_TMP3
        AND #3
        STA ZP_TMP3
        DEY
        BNE UG_RND_LP
        LDX ZP_GIDX
        LDA ZP_TMP4
        STA G_DIR,X

UG_MOVE_STEP:
        LDX ZP_GIDX
        LDA G_DIR,X
        CMP #0
        BNE UGM_1
        DEC G_Y,X
        JMP UG_NEXT_GHOST
UGM_1:  CMP #1
        BNE UGM_2
        INC G_Y,X
        JMP UG_NEXT_GHOST
UGM_2:  CMP #2
        BNE UGM_3
        DEC G_X,X
        JMP UG_NEXT_GHOST
UGM_3:  INC G_X,X

UG_NEXT_GHOST:
        INC ZP_GIDX
        LDA ZP_GIDX
        CMP #4
        BCS UG_DONE
        JMP UG_LOOP
UG_DONE:
        RTS

; Check of tegel vanuit (ZP_TMP1, ZP_TMP2) in richting X (0..3) vrij is voor een Spook
CHECK_GHOST_PASSABLE:
        STY ZP_X_LO
        CLC
        LDA ZP_TMP1
        ADC DIR_DX,X
        TAY
        CLC
        LDA ZP_TMP2
        ADC DIR_DY,X
        JSR GET_MAZE_CELL
        LDY ZP_X_LO
        CMP #T_WALL
        BEQ CGP_NO
        CMP #T_GATE
        BNE CGP_YES
        CPX #0          ; Alleen richting 0 (Omhoog) mag door het hekje!
        BEQ CGP_YES
CGP_NO:
        CLC
        RTS
CGP_YES:
        SEC
        RTS

; ============================================================================
; Botsing tussen Pac-Man en de 4 Spoken
; ============================================================================
CHECK_COLLISIONS:
        LDX #0
CC_LOOP:
        ; Check |PAC_Y - G_Y[X]| < 5 (10 pixels)
        SEC
        LDA PAC_Y
        SBC G_Y,X
        BPL CC_Y_POS
        EOR #$FF
        CLC
        ADC #1
CC_Y_POS:
        CMP #5
        BCS CC_NEXT

        ; Check |PAC_X - G_X[X]| < 5 (10 pixels)
        SEC
        LDA PAC_X
        SBC G_X,X
        BPL CC_X_POS
        EOR #$FF
        CLC
        ADC #1
CC_X_POS:
        CMP #5
        BCS CC_NEXT

        ; BOTSING MET SPOOK X!
        LDA FRIGHT_TIMER
        BEQ CC_PAC_DIED

        ; Spook is blauw -> opgegeten door Pac-Man! (+200 punten)
        STX ZP_GIDX
        LDA #200
        JSR ADD_SCORE
        LDX ZP_GIDX
        ; Zet spook terug in het Spookhuis op (mx=14, my=11 -> X2=112, Y2=88)
        LDA #112
        STA G_X,X
        LDA #88
        STA G_Y,X
        LDA #0
        STA G_DIR,X
        JSR PLAY_GHOST_EATEN_SFX
        LDX ZP_GIDX

CC_NEXT:
        INX
        CPX #4
        BCC CC_LOOP
        RTS

CC_PAC_DIED:
        JSR PLAY_DEATH_SEQ
        DEC LIVES
        LDA #1
        STA HUD_DIRTY
        LDA LIVES
        BEQ CC_DEAD_RTS
        JSR ERASE_OLD_ENTITIES
        JSR RESET_POSITIONS
        JSR DRAW_ALL_ENTITIES
        JSR SAVE_OLD_POSITIONS
        JSR UPDATE_HUD_NUMBERS
        JSR PLAY_READY_DELAY
CC_DEAD_RTS:
        RTS

; ============================================================================
; Rendering: Wis Oude Sprites ($E3) & Teken Nieuwe Sprites op TARGET 1
; ============================================================================
ERASE_OLD_ENTITIES:
        LDA PAC_OLD_X
        LDY PAC_OLD_Y
        JSR ERASE_16X16_XY2

        LDX #0
EOE_LP:
        STX ZP_GIDX
        LDA G_OLD_X,X
        LDY G_OLD_Y,X
        JSR ERASE_16X16_XY2
        LDX ZP_GIDX
        INX
        CPX #4
        BCC EOE_LP
        RTS

; Wis 16x16 blok op (X2=A, Y2=Y) naar transparant ($E3)
ERASE_16X16_XY2:
        PHA
        LDA #2          ; GPU cmd 2 = RECT(x, y, 16, 16, $E3)
        STA IO_GPU
        PLA
        ASL A
        STA IO_GPU
        LDA #0
        ROL A
        STA IO_GPU
        TYA
        ASL A
        STA IO_GPU
        LDA #0
        ROL A
        STA IO_GPU
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$E3
        STA IO_GPU
        RTS

DRAW_ALL_ENTITIES:
        ; Teken eerst de 4 Spoken
        LDX #0
DAE_GLP:
        STX ZP_GIDX
        LDA FRIGHT_TIMER
        BEQ DAE_NORM_G
        CMP #60
        BCS DAE_BLU_G
        AND #8
        BEQ DAE_WHT_G
DAE_BLU_G:
        LDA #SPR_GHOST_BLU
        JMP DAE_DRAW_G
DAE_WHT_G:
        LDA #SPR_GHOST_WHT
        JMP DAE_DRAW_G
DAE_NORM_G:
        TXA
        CLC
        ADC #SPR_BLINKY
DAE_DRAW_G:
        STA ZP_TMP3
        LDA G_X,X
        LDY G_Y,X
        LDX ZP_TMP3
        JSR DRAW_SPRITE_XY2
        LDX ZP_GIDX
        INX
        CPX #4
        BCC DAE_GLP

        ; Teken Pac-Man bovenop (wissel mond open/dicht elke 4 frames)
        LDA FRAME_CNT
        AND #4
        BEQ DAE_PAC_OPEN
        LDX #SPR_PAC_CL
        JMP DAE_PAC_DO
DAE_PAC_OPEN:
        LDY PAC_DIR
        LDX PAC_DIR_SPR,Y
DAE_PAC_DO:
        LDA PAC_X
        LDY PAC_Y
        JMP DRAW_SPRITE_XY2

; Teken 16x16 sprite X op (X2=A, Y2=Y)
DRAW_SPRITE_XY2:
        PHA
        LDA #10         ; GPU cmd 10 = SPRITE
        STA IO_GPU
        PLA
        ASL A
        STA IO_GPU
        LDA #0
        ROL A
        STA IO_GPU
        TYA
        ASL A
        STA IO_GPU
        LDA #0
        ROL A
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STX IO_GPU
        RTS

SAVE_OLD_POSITIONS:
        LDA PAC_X
        STA PAC_OLD_X
        LDA PAC_Y
        STA PAC_OLD_Y
        LDX #0
SOP_LP:
        LDA G_X,X
        STA G_OLD_X,X
        LDA G_Y,X
        STA G_OLD_Y,X
        INX
        CPX #4
        BCC SOP_LP
        RTS

RESET_POSITIONS:
        ; Pac-Man op (mx=14, my=17 -> X2=112, Y2=136), richting Links (2)
        LDA #112
        STA PAC_X
        LDA #136
        STA PAC_Y
        LDA #2
        STA PAC_DIR
        STA PAC_WANT
        LDA #0
        STA FRIGHT_TIMER
        STA SND_TIMER
        JSR SILENCE_ALL_AUDIO

        ; Zet 4 Spoken op hun startposities uit tabel
        LDX #0
RP_LP:
        LDA G_INIT_X,X
        STA G_X,X
        LDA G_INIT_Y,X
        STA G_Y,X
        LDA G_INIT_D,X
        STA G_DIR,X
        INX
        CPX #4
        BCC RP_LP
        RTS

; ============================================================================
; Doolhof Opbouwen in RAM ($7800) én FPGA Hardware Tilemap
; ============================================================================
; Input: A = my (0..21), Y = mx (0..28). Zet ZP_M_LO/HI op $7800 + my*32 en laadt A = cel
GET_MAZE_CELL:
        STA ZP_M_LO
        LDA #0
        ASL ZP_M_LO
        ROL A
        ASL ZP_M_LO
        ROL A
        ASL ZP_M_LO
        ROL A
        ASL ZP_M_LO
        ROL A
        ASL ZP_M_LO
        ROL A
        CLC
        ADC #$78
        STA ZP_M_HI
        LDA (ZP_M_LO),Y
        RTS

BUILD_MAZE_AND_TILES:
        ; Vul eerst heel MAZE_RAM ($7800..$7AFF) met T_WALL (17) voor veilige randen
        LDA #T_WALL
        LDX #0
BMT_INIT_RAM:
        STA $7800,X
        STA $7900,X
        STA $7A00,X
        INX
        BNE BMT_INIT_RAM

        ; Maak eerst heel het 40x23 zichtbare Tilemap-gebied zwart (T_EMPTY = 16)
        LDA #0
        STA ZP_TMP2     ; my = 0..22
BMT_CLR_Y:
        LDA #0
        STA ZP_TMP1     ; mx = 0..39
BMT_CLR_X:
        LDA #23
        STA IO_GPU
        LDA ZP_TMP1
        STA IO_GPU
        LDA ZP_TMP2
        ORA #32
        STA IO_GPU
        LDA #T_EMPTY
        STA IO_GPU
        INC ZP_TMP1
        LDA ZP_TMP1
        CMP #40
        BCC BMT_CLR_X
        INC ZP_TMP2
        LDA ZP_TMP2
        CMP #23
        BCC BMT_CLR_Y

        ; Kies 1 van de 4 unieke 27x21 Doolhoven op basis van (LEVEL - 1) & 3
        LDX LEVEL
        DEX
        TXA
        AND #3
        TAX
        CLC
        LDA #<MAZE_BITS
        ADC MAZE_OFF_TBL,X
        STA ZP_PTR_LO
        LDA #>MAZE_BITS
        ADC #0
        STA ZP_PTR_HI
        LDA #0
        STA DOTS_LEFT
        LDA #1
        STA ZP_TMP2     ; my = 1..21

BMT_ROW_LP:
        ; Check of rij my (ZP_TMP2) een bitmask-rij is (my = 2..8 of 14..20)
        LDA ZP_TMP2
        CMP #1
        BEQ BMT_START_COLS
        CMP #21
        BEQ BMT_START_COLS
        CMP #9
        BCC BMT_LOAD_BITS
        CMP #14
        BCC BMT_START_COLS
BMT_LOAD_BITS:
        LDY #0
        LDA (ZP_PTR_LO),Y
        STA ZP_TMP3
        INY
        LDA (ZP_PTR_LO),Y
        STA ZP_TMP4
        CLC
        LDA ZP_PTR_LO
        ADC #2
        STA ZP_PTR_LO
        BCC BMT_START_COLS
        INC ZP_PTR_HI

BMT_START_COLS:
        LDA #1
        STA ZP_TMP1     ; mx = 1..27
BMT_COL_LP:
        ; Spiegel kolom rond mx=14: als mx <= 14 dan Y = mx-1, anders Y = 27-mx
        LDA ZP_TMP1
        CMP #15
        BCC BMT_LEFT_COL
        LDA #27
        SEC
        SBC ZP_TMP1
        TAY
        JMP BMT_DECIDE_ROW
BMT_LEFT_COL:
        SEC
        SBC #1
        TAY

BMT_DECIDE_ROW:
        LDA ZP_TMP2
        CMP #1
        BEQ BMT_IS_WALL
        CMP #21
        BEQ BMT_IS_WALL
        CMP #9
        BCC BMT_BIT_ROW
        CMP #14
        BCS BMT_BIT_ROW

        ; Middelste 5 rijen (my = 9..13: Spookhuis + Warp-Tunnel + Kers)
        SEC
        SBC #9
        TAX
        TYA
        CLC
        ADC MID_ROW_OFF,X
        TAY
        LDA MID_ROWS_ASCII,Y
        CMP #'#'
        BEQ BMT_IS_WALL
        CMP #'.'
        BNE BMT_M_C2
        JMP BMT_MAKE_DOT
BMT_M_C2:
        CMP #'-'
        BNE BMT_M_C3
        LDA #T_GATE
        JMP BMT_STORE
BMT_M_C3:
        CMP #'C'
        BNE BMT_M_EMP
        LDA #T_CHERRY
        JMP BMT_STORE
BMT_M_EMP:
        LDA #T_EMPTY
        JMP BMT_STORE

BMT_IS_WALL:
        LDA #T_WALL
        JMP BMT_STORE

BMT_BIT_ROW:
        CPY #8
        BCS BMT_BIT_HI
        LDA ZP_TMP3
        AND BIT_M8,Y
        JMP BMT_BIT_TEST
BMT_BIT_HI:
        TYA
        SEC
        SBC #8
        TAX
        LDA ZP_TMP4
        AND BIT_M8,X
BMT_BIT_TEST:
        BNE BMT_IS_WALL

        ; Open pad! Check of dit Pac-Man's startpositie (my=17, mx=14) is -> leeg!
        LDA ZP_TMP2
        CMP #17
        BNE BMT_CHK_POW_POS
        LDA ZP_TMP1
        CMP #14
        BEQ BMT_M_EMP

BMT_CHK_POW_POS:
        ; 4 Krachtpillen op kolom Y=1 (mx=2 en mx=26) bij rij my=2 en my=17
        CPY #1
        BNE BMT_MAKE_DOT
        LDA ZP_TMP2
        CMP #2
        BEQ BMT_MAKE_POW
        CMP #17
        BNE BMT_MAKE_DOT
BMT_MAKE_POW:
        INC DOTS_LEFT
        LDA #T_POWER
        JMP BMT_STORE

BMT_MAKE_DOT:
        INC DOTS_LEFT
        LDA #T_DOT

BMT_STORE:
        JSR CLEAR_CURRENT_TILE
        INC ZP_TMP1
        LDA ZP_TMP1
        CMP #28
        BCS BMT_NXT_R
        JMP BMT_COL_LP
BMT_NXT_R:
        INC ZP_TMP2
        LDA ZP_TMP2
        CMP #22
        BCS BMT_DONE_RTS
        JMP BMT_ROW_LP
BMT_DONE_RTS:
        RTS

; ============================================================================
; Score, HUD Paneel & Tekst Subroutines
; ============================================================================
; Tel A punten op bij SCORE_LO/HI en werk HSCORE bij indien hoger
ADD_SCORE:
        CLC
        ADC SCORE_LO
        STA SCORE_LO
        BCC AS_CHK_HI
        INC SCORE_HI
AS_CHK_HI:
        LDA #1
        STA HUD_DIRTY
        ; Vergelijk SCORE met HSCORE
        LDA SCORE_HI
        CMP HSCORE_HI
        BCC AS_RTS
        BNE AS_NEW_HI
        LDA SCORE_LO
        CMP HSCORE_LO
        BCC AS_RTS
AS_NEW_HI:
        LDA SCORE_LO
        STA HSCORE_LO
        LDA SCORE_HI
        STA HSCORE_HI
AS_RTS:
        RTS

DRAW_HUD_PANEL:
        ; Teken achtergronden en kaders van het rechter Arcade Paneel
        LDX #0
DHP_STREAM:
        LDA HUD_GPU_STREAM,X
        STA IO_GPU
        INX
        CPX #HUD_GPU_STREAM_END - HUD_GPU_STREAM
        BCC DHP_STREAM

        ; Teken alle vaste HUD teksten uit HUD_TEXT_TBL
        LDA #<HUD_TEXT_TBL
        STA ZP_PTR_LO
        LDA #>HUD_TEXT_TBL
        STA ZP_PTR_HI
DHP_TXT_LP:
        JSR NEXT_PTR_BYTE
        CMP #$FF
        BEQ DHP_GHOSTS
        STA ZP_X_LO
        JSR NEXT_PTR_BYTE
        STA ZP_X_HI
        JSR NEXT_PTR_BYTE
        STA ZP_Y_LO
        JSR NEXT_PTR_BYTE
        STA ZP_Y_HI
        JSR NEXT_PTR_BYTE
        STA ZP_COL
DHP_CH_LP:
        JSR NEXT_PTR_BYTE
        BEQ DHP_TXT_LP
        JSR DRAW_CHAR_ADV
        JMP DHP_CH_LP

DHP_GHOSTS:
        ; Teken de 4 gekleurde Spook-icoontjes in de legenda rechts (X = 468 = X2 234)
        LDX #0
DHP_G_LP:
        STX ZP_GIDX
        TXA
        ASL A
        ASL A
        ASL A           ; * 8 (16 px per rij)
        CLC
        ADC #114        ; Y2 = 114 -> Y = 228
        TAY
        TXA
        CLC
        ADC #SPR_BLINKY
        TAX
        LDA #234        ; X2 = 234 -> X = 468
        JSR DRAW_SPRITE_XY2
        LDX ZP_GIDX
        INX
        CPX #4
        BCC DHP_G_LP
        RTS

UPDATE_HUD_NUMBERS:
        ; Wis vakjes voor Score, High Score, Stage en Levens in het zijpaneel
        LDX #0
UHN_CLR:
        LDA HUD_CLR_STREAM,X
        STA IO_GPU
        INX
        CPX #HUD_CLR_STREAM_END - HUD_CLR_STREAM
        BCC UHN_CLR

        ; 1. Teken SCORE op (516, 70) in wit ($FF)
        LDA #0
        STA ZP_Y_HI
        LDA #$04        ; 516 = $0204
        STA ZP_X_LO
        LDA #$02
        STA ZP_X_HI
        LDA #70
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA SCORE_LO
        sta_s:
        LDY SCORE_HI
        JSR DRAW_UINT16_5D

        ; 2. Teken HIGH SCORE op (516, 114) in geel ($FC)
        LDA #$04
        STA ZP_X_LO
        LDA #$02
        STA ZP_X_HI
        LDA #114
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_COL
        LDA HSCORE_LO
        LDY HSCORE_HI
        JSR DRAW_UINT16_5D

        ; 3. Teken LEVEL op (540, 154) in cyaan ($1F)
        LDA #$1C        ; 540 = $021C
        STA ZP_X_LO
        LDA #$02
        STA ZP_X_HI
        LDA #154
        STA ZP_Y_LO
        LDA #$1F
        STA ZP_COL
        LDA LEVEL
        LDY #0
        JSR DRAW_UINT16_5D

        ; 4. Teken Levens als Pac-Man icoontjes op Y = 188 (Y2 = 94)
        LDX #0
UHN_LV_LP:
        CPX LIVES
        BCS UHN_LV_DN
        STX ZP_GIDX
        TXA
        ASL A
        ASL A           ; * 4 -> * 8 (stap van 20 px = 10 X2)
        ASL A
        CLC
        ADC #236        ; X2 = 236 -> X = 472
        LDY #94         ; Y2 = 94  -> Y = 188
        LDX #SPR_PAC_R
        JSR DRAW_SPRITE_XY2
        LDX ZP_GIDX
        INX
        CPX #5
        BCC UHN_LV_LP
UHN_LV_DN:
        RTS

; Teken 16-bit getal (A=lo, Y=hi) als 5 decimale cijfers (00000..65535)
DRAW_UINT16_5D:
        STA ZP_TMP1
        STY ZP_TMP2
        LDX #0
DU16_DIG_LP:
        LDY #'0'
DU16_SUB_LP:
        LDA ZP_TMP1
        CMP DEC_POW_LO,X
        LDA ZP_TMP2
        SBC DEC_POW_HI,X
        BCC DU16_PRT_D
        SEC
        LDA ZP_TMP1
        SBC DEC_POW_LO,X
        STA ZP_TMP1
        LDA ZP_TMP2
        SBC DEC_POW_HI,X
        STA ZP_TMP2
        INY
        JMP DU16_SUB_LP
DU16_PRT_D:
        TYA
        STX ZP_TMP3
        JSR DRAW_CHAR_ADV
        LDX ZP_TMP3
        INX
        CPX #5
        BCC DU16_DIG_LP
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
        LDA #8          ; GPU cmd 8 = DRAW_CHAR
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
        LDA ZP_COL
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
; Audio & Melodie Subroutines (48 kHz HDMI Synthesizer)
; ============================================================================
; Speel noot A (0 = stil, 1..255 = frequentie ~ A*5.86 Hz) op kanaal X met volume Y
PLAY_NOTE_CH:
        CMP #0
        BEQ PNC_SILENCE
        STA ZP_TMP3
        LDA #0
        STA ZP_TMP4
        ASL ZP_TMP3
        ROL ZP_TMP4
        ASL ZP_TMP3
        ROL ZP_TMP4
        ASL ZP_TMP3
        ROL ZP_TMP4
        LDA #16         ; GPU cmd 16 = SET_AUDIO
        STA IO_GPU
        STX IO_GPU
        LDA #0
        STA IO_GPU      ; phase_lo = 0
        LDA ZP_TMP3
        STA IO_GPU      ; phase_mid
        LDA ZP_TMP4
        STA IO_GPU      ; phase_hi
        STY IO_GPU      ; volume
        RTS
PNC_SILENCE:
        LDA #16
        STA IO_GPU
        STX IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        RTS

SILENCE_ALL_AUDIO:
        LDX #0
SAA_LP:
        LDA #0
        LDY #0
        JSR PLAY_NOTE_CH
        INX
        CPX #4
        BCC SAA_LP
        RTS

UPDATE_AUDIO:
        ; Kanaal 0: Waka-Waka / Kers / Krachtpil geluidseffect
        LDA SND_TIMER
        BEQ UA_CH0_OFF
        DEC SND_TIMER
        LDA SND_PITCH
        CLC
        ADC SND_TIMER
        LDX #0
        LDY #180
        JSR PLAY_NOTE_CH
        JMP UA_CHK_SIREN
UA_CH0_OFF:
        LDA #0
        LDX #0
        LDY #0
        JSR PLAY_NOTE_CH

UA_CHK_SIREN:
        ; Kanaal 1: Krachtpil Sirene zolang FRIGHT_TIMER > 0
        LDA FRIGHT_TIMER
        BEQ UA_CH1_OFF
        AND #15
        ASL A
        CLC
        ADC #45
        LDX #1
        LDY #110
        JMP PLAY_NOTE_CH
UA_CH1_OFF:
        LDA #0
        LDX #1
        LDY #0
        JMP PLAY_NOTE_CH

PLAY_INTRO_JINGLE:
        ; Toon "READY!" in geel op (200, 212) en speel de Pac-Man Intro Melodie!
        JSR SHOW_READY_BANNER
        LDX #0
PIJ_LP:
        LDA IO_STATUS
        BMI PIJ_DONE
        STX ZP_GIDX
        LDA INTRO_NOTES,X
        BEQ PIJ_DONE
        LDY #190
        LDX #0
        JSR PLAY_NOTE_CH
        LDX ZP_GIDX
        LDA INTRO_DURS,X
        JSR WAIT_10MS
        LDA #0
        LDX #0
        LDY #0
        JSR PLAY_NOTE_CH
        LDA #2
        JSR WAIT_10MS
        LDX ZP_GIDX
        INX
        JMP PIJ_LP
PIJ_DONE:
        JMP CLEAR_READY_BANNER

PLAY_READY_DELAY:
        JSR SHOW_READY_BANNER
        LDA #60
        JSR WAIT_10MS
        JMP CLEAR_READY_BANNER

; Wacht A * 10 ms via de 100 Hz hardware systeem-timer ($A003 = IO_TIMER)
WAIT_10MS:
        CLC
        ADC IO_TIMER
W10_LP:
        CMP IO_TIMER
        BNE W10_LP
        RTS

SHOW_READY_BANNER:
        LDA #200
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #212
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_COL
        LDA #<STR_READY
        STA ZP_PTR_LO
        LDA #>STR_READY
        STA ZP_PTR_HI
SRB_LP:
        JSR NEXT_PTR_BYTE
        BEQ SRB_RTS
        JSR DRAW_CHAR_ADV
        JMP SRB_LP
SRB_RTS:
        RTS

CLEAR_READY_BANNER:
        ; Herstel de 6 tegels op rij my=13, mx=12..16 naar transparant ($E3)
        LDA #2
        STA IO_GPU
        LDA #192
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #208
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #64
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$E3
        STA IO_GPU
        RTS

PLAY_GHOST_EATEN_SFX:
        LDA #60
        STA ZP_TMP1
PGE_LP:
        LDA ZP_TMP1
        LDX #0
        LDY #210
        JSR PLAY_NOTE_CH
        LDA #1
        JSR WAIT_10MS
        CLC
        LDA ZP_TMP1
        ADC #12
        STA ZP_TMP1
        CMP #190
        BCC PGE_LP
        JMP SILENCE_ALL_AUDIO

PLAY_DEATH_SEQ:
        JSR SILENCE_ALL_AUDIO
        ; Teken explosie-sprite op Pac-Man positie en speel dalende womp-womp-womp
        LDA PAC_X
        LDY PAC_Y
        LDX #SPR_DEATH
        JSR DRAW_SPRITE_XY2
        LDA #130
        STA ZP_TMP1
PDS_LP:
        LDA ZP_TMP1
        LDX #0
        LDY #200
        JSR PLAY_NOTE_CH
        LDA #3
        JSR WAIT_10MS
        SEC
        LDA ZP_TMP1
        SBC #7
        STA ZP_TMP1
        CMP #28
        BCS PDS_LP
        JSR SILENCE_ALL_AUDIO
        LDA #25
        JSR WAIT_10MS
        RTS

LEVEL_CLEAR_SEQ:
        JSR SILENCE_ALL_AUDIO
        LDX #0
LCS_LP:
        STX ZP_GIDX
        LDA WIN_NOTES,X
        BEQ LCS_DN
        LDX #0
        LDY #200
        JSR PLAY_NOTE_CH
        LDA #10
        JSR WAIT_10MS
        LDX ZP_GIDX
        INX
        JMP LCS_LP
LCS_DN:
        JSR SILENCE_ALL_AUDIO
        LDA #30
        JSR WAIT_10MS
        RTS

HANDLE_GAME_OVER:
        JSR SILENCE_ALL_AUDIO
        ; Teken "GAME OVER" op (192, 212) in rood ($E0)
        LDA #192
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #212
        STA ZP_Y_LO
        LDA #$E0
        STA ZP_COL
        LDA #<STR_GAMEOVER
        STA ZP_PTR_LO
        LDA #>STR_GAMEOVER
        STA ZP_PTR_HI
HGO_LP:
        JSR NEXT_PTR_BYTE
        BEQ HGO_WAIT
        JSR DRAW_CHAR_ADV
        JMP HGO_LP

HGO_WAIT:
        LDA #2
        JSR WAIT_10MS
        LDA IO_STATUS
        BMI QUIT_GAME_ESC
        AND #1
        BEQ HGO_JOY
        LDA IO_TERM
        CMP #' '
        BEQ HGO_RESTART
        CMP #$0D
        BEQ HGO_RESTART
        AND #$DF
        CMP #'Q'
        BEQ QUIT_GAME
HGO_JOY:
        LDA IO_JOY
        AND #16         ; Vuur / Spatie -> Nieuw spel!
        BNE HGO_RESTART
        JMP HGO_WAIT
HGO_RESTART:
        JMP INIT_NEW_GAME

QUIT_GAME_ESC:
        LDA IO_TERM
QUIT_GAME:
        JSR SILENCE_ALL_AUDIO
        ; Zet SCROLL terug naar (0, 0) zodat de originele gras/boerderij wereld onderaan weer zichtbaar is!
        LDA #15
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #$E3
        STA IO_GPU
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

; ============================================================================
; Hardware Initialisatie & Uploaden van Custom 16x16 Tiles en Sprites
; ============================================================================
INIT_GPU_STATE:
        ; BIGSPR 0 & 1 uit, SCROLL 0, 0
        LDX #0
IGS_LP:
        LDA GPU_INIT_BYTES,X
        STA IO_GPU
        INX
        CPX #GPU_INIT_BYTES_END - GPU_INIT_BYTES
        BCC IGS_LP
        RTS

UPLOAD_CUSTOM_TILES:
        ; Kies Stage-afhankelijke Neon Muurkleuren op basis van (LEVEL - 1) & 3
        LDX LEVEL
        DEX
        TXA
        AND #3
        TAX
        LDA WALL_BORDER_COLS,X
        STA ZP_COL
        LDA WALL_FILL_COLS,X
        STA ZP_TMP4

        ; Upload Tiles 16..21 met één gedeelde 16x16 raster-lus!
        LDA #T_EMPTY
        STA ZP_GIDX
UCT_TILE_LP:
        LDA #13         ; GPU cmd 13 = UPLOAD_BG_TILESET
        STA IO_GPU
        LDA ZP_GIDX
        STA IO_GPU
        LDY #0          ; Y = 0..15
UCT_Y_LP:
        LDX #0          ; X = 0..15
UCT_X_LP:
        LDA ZP_GIDX
        CMP #T_WALL
        BEQ UCT_DO_WALL
        CMP #T_DOT
        BEQ UCT_DO_DOT
        CMP #T_GATE
        BEQ UCT_DO_GATE
        CMP #T_POWER
        BEQ UCT_DO_POW
        CMP #T_CHERRY
        BNE UCT_IS_EMP
        JMP UCT_DO_CHR
UCT_IS_EMP:
        LDA #$00        ; T_EMPTY = Zwart
        JMP UCT_PIX_OUT

UCT_DO_DOT:
        CPY #6
        BCC UCT_BLK_J
        CPY #10
        BCS UCT_BLK_J
        CPX #6
        BCC UCT_BLK_J
        CPX #10
        BCS UCT_BLK_J
        LDA #$FC
        JMP UCT_PIX_OUT

UCT_DO_GATE:
        CPY #7
        BNE UCT_G2
        LDA #$FF
        JMP UCT_PIX_OUT
UCT_G2: CPY #8
        BEQ UCT_PNK
        CPY #9
        BNE UCT_BLK_J
UCT_PNK:
        LDA #$F3
        JMP UCT_PIX_OUT
UCT_BLK_J:
        JMP UCT_BLK

UCT_DO_WALL:
        CPY #0
        BEQ UCT_BLK_J
        CPY #15
        BEQ UCT_BLK_J
        CPX #0
        BEQ UCT_BLK_J
        CPX #15
        BEQ UCT_BLK_J
        CPY #1
        BEQ UCT_CYN
        CPY #14
        BEQ UCT_CYN
        CPX #1
        BEQ UCT_CYN
        CPX #14
        BEQ UCT_CYN
        LDA ZP_TMP4
        JMP UCT_PIX_OUT
UCT_CYN:
        LDA ZP_COL
        JMP UCT_PIX_OUT

UCT_DO_POW:
        CPY #4
        BCC UCT_BLK
        CPY #12
        BCS UCT_BLK
        CPX #4
        BCC UCT_BLK
        CPX #12
        BCS UCT_BLK
        CPY #4
        BEQ UCT_P_CRN
        CPY #11
        BNE UCT_P_CORE
UCT_P_CRN:
        CPX #4
        BEQ UCT_BLK
        CPX #11
        BEQ UCT_BLK
UCT_P_CORE:
        LDA #$FC
        CPY #6
        BCC UCT_PIX_OUT
        CPY #10
        BCS UCT_PIX_OUT
        CPX #6
        BCC UCT_PIX_OUT
        CPX #10
        BCS UCT_PIX_OUT
        LDA #$FF
        JMP UCT_PIX_OUT

UCT_DO_CHR:
        CPY #2
        BCC UCT_BLK
        CPY #7
        BCS UCT_C_BER
        CPX #8
        BCC UCT_BLK
        CPX #10
        BCS UCT_BLK
        LDA #$1C
        JMP UCT_PIX_OUT
UCT_C_BER:
        CPY #13
        BCS UCT_BLK
        CPX #3
        BCC UCT_BLK
        CPX #8
        BCC UCT_C_RED
        CPX #9
        BCC UCT_BLK
        CPX #14
        BCS UCT_BLK
UCT_C_RED:
        LDA #$E0
        CPY #9
        BNE UCT_PIX_OUT
        CPX #4
        BEQ UCT_C_WHT
        CPX #10
        BNE UCT_PIX_OUT
UCT_C_WHT:
        LDA #$FF
        JMP UCT_PIX_OUT

UCT_BLK:
        LDA #$00
UCT_PIX_OUT:
        STA IO_GPU
        INX
        CPX #16
        BCS UCT_NEXT_Y
        JMP UCT_X_LP
UCT_NEXT_Y:
        INY
        CPY #16
        BCS UCT_NEXT_T
        JMP UCT_Y_LP
UCT_NEXT_T:
        INC ZP_GIDX
        LDA ZP_GIDX
        CMP #(T_CHERRY + 1)
        BCS UCT_DONE
        JMP UCT_TILE_LP
UCT_DONE:
        RTS

; ============================================================================
; Upload 12 Custom 16x16 Sprites (Pac-Man 4 richtingen + dicht, 4 Spoken, Blauw/Wit, Dood)
; ============================================================================
UPLOAD_CUSTOM_SPRITES:
        ; Upload Pac-Man sprites 16..20 (0=R, 1=L, 2=U, 3=D, 4=Closed) met één gedeelde lus
        LDA #0
        STA ZP_GIDX
UCS_PAC_LP:
        LDA #9
        STA IO_GPU
        LDA ZP_GIDX
        CLC
        ADC #SPR_PAC_R
        STA IO_GPU
        LDY #0
UCS_PY_LP:
        LDX #0
UCS_PX_LP:
        LDA ZP_GIDX
        BNE UCS_P_CHK1
        ; 0: Rechts (rx=X, ry=Y)
        STX ZP_TMP1
        STY ZP_TMP2
        JMP UCS_P_PIX
UCS_P_CHK1:
        CMP #1
        BNE UCS_P_CHK2
        ; 1: Links (rx=15-X, ry=Y)
        TXA
        EOR #15
        STA ZP_TMP1
        STY ZP_TMP2
        JMP UCS_P_PIX
UCS_P_CHK2:
        CMP #2
        BNE UCS_P_CHK3
        ; 2: Omhoog (rx=15-Y, ry=X)
        TYA
        EOR #15
        STA ZP_TMP1
        STX ZP_TMP2
        JMP UCS_P_PIX
UCS_P_CHK3:
        CMP #3
        BNE UCS_P_CHK4
        ; 3: Omlaag (rx=Y, ry=15-X)
        STY ZP_TMP1
        TXA
        EOR #15
        STA ZP_TMP2
        JMP UCS_P_PIX
UCS_P_CHK4:
        ; 4: Mond dicht (rx = X<8 ? X : 15-X, ry=Y)
        TXA
        CMP #8
        BCC UCS_P_CL_OK
        EOR #15
UCS_P_CL_OK:
        STA ZP_TMP1
        STY ZP_TMP2
UCS_P_PIX:
        JSR GET_PAC_BIT
        STA IO_GPU
        INX
        CPX #16
        BCC UCS_PX_LP
        INY
        CPY #16
        BCC UCS_PY_LP
        INC ZP_GIDX
        LDA ZP_GIDX
        CMP #5
        BCC UCS_PAC_LP

        ; 6. 4 Gekleurde Spoken (21..24: Blinky=$E0, Pinky=$F3, Inky=$1F, Clyde=$F0)
        LDX #0
UCS_G_LP:
        STX ZP_GIDX
        LDA #9
        STA IO_GPU
        TXA
        CLC
        ADC #SPR_BLINKY
        STA IO_GPU
        LDA GHOST_COLS,X
        STA ZP_COL
        JSR UPLOAD_ONE_GHOST
        LDX ZP_GIDX
        INX
        CPX #4
        BCC UCS_G_LP

        ; 7. Blauw Bang Spook (25) en Wit Knipperend Spook (26)
        LDA #9
        STA IO_GPU
        LDA #SPR_GHOST_BLU
        STA IO_GPU
        LDA #$03
        STA ZP_COL
        LDA #$FC
        STA ZP_TMP4
        JSR UPLOAD_FRIGHT_GHOST

        LDA #9
        STA IO_GPU
        LDA #SPR_GHOST_WHT
        STA IO_GPU
        LDA #$FF
        STA ZP_COL
        LDA #$E0
        STA ZP_TMP4
        JSR UPLOAD_FRIGHT_GHOST

        ; 8. SPR_DEATH (27): Explosie / Sterrensprankel bij verlies leven
        LDA #9
        STA IO_GPU
        LDA #SPR_DEATH
        STA IO_GPU
        LDY #0
UCS_DT_Y:
        LDX #0
UCS_DT_X:
        LDA #$E3
        STX ZP_TMP1
        CPY ZP_TMP1
        BEQ UCS_DT_HIT
        TYA
        EOR #15
        CMP ZP_TMP1
        BEQ UCS_DT_HIT
        CPY #7
        BEQ UCS_DT_HIT
        CPX #7
        BNE UCS_DT_OUT
UCS_DT_HIT:
        LDA #$FC
        CPY #5
        BCC UCS_DT_OUT
        CPY #11
        BCS UCS_DT_OUT
        LDA #$E0
UCS_DT_OUT:
        STA IO_GPU
        INX
        CPX #16
        BCC UCS_DT_X
        INY
        CPY #16
        BCC UCS_DT_Y
        RTS

; Hulproutine: geeef kleur voor Pac-Man pixel op (ZP_TMP1=rx, ZP_TMP2=ry)
GET_PAC_BIT:
        STX ZP_X_LO
        STY ZP_Y_LO
        ; Donker oogje op ry=3, rx=7..8
        LDA ZP_TMP2
        CMP #3
        BNE GPB_MASK
        LDA ZP_TMP1
        CMP #7
        BEQ GPB_EYE
        CMP #8
        BNE GPB_MASK
GPB_EYE:
        LDA #$00
        JMP GPB_DONE
GPB_MASK:
        LDA ZP_TMP2
        ASL A
        TAY
        LDA ZP_TMP1
        CMP #8
        BCC GPB_LEFT_B
        INY
        SEC
        SBC #8
GPB_LEFT_B:
        TAX
        LDA PAC_MASK,Y
        AND BIT_M8,X
        BEQ GPB_TRANS
        LDA #$FC        ; Geel
        JMP GPB_DONE
GPB_TRANS:
        LDA #$E3        ; Transparant
GPB_DONE:
        LDX ZP_X_LO
        LDY ZP_Y_LO
        RTS

UPLOAD_ONE_GHOST:
        LDY #0
UOG_Y:
        LDX #0
UOG_X:
        STX ZP_TMP1
        STY ZP_TMP2
        JSR GET_GHOST_SIL
        BEQ UOG_TRANS
        ; Ogen op Y=3..6, X=3..6 en X=9..12
        CPY #3
        BCC UOG_BODY
        CPY #7
        BCS UOG_BODY
        CPX #3
        BCC UOG_BODY
        CPX #7
        BCC UOG_EYE
        CPX #9
        BCC UOG_BODY
        CPX #13
        BCS UOG_BODY
UOG_EYE:
        ; Pupillen op Y=4..5, X=5..6 en X=11..12
        CPY #4
        BCC UOG_WHT
        CPY #6
        BCS UOG_WHT
        CPX #5
        BEQ UOG_PUP
        CPX #6
        BEQ UOG_PUP
        CPX #11
        BEQ UOG_PUP
        CPX #12
        BEQ UOG_PUP
UOG_WHT:
        LDA #$FF
        JMP UOG_OUT
UOG_PUP:
        LDA #$03
        JMP UOG_OUT
UOG_BODY:
        LDA ZP_COL
        JMP UOG_OUT
UOG_TRANS:
        LDA #$E3
UOG_OUT:
        STA IO_GPU
        INX
        CPX #16
        BCC UOG_X
        INY
        CPY #16
        BCC UOG_Y
        RTS

UPLOAD_FRIGHT_GHOST:
        LDY #0
UFG_Y:
        LDX #0
UFG_X:
        STX ZP_TMP1
        STY ZP_TMP2
        JSR GET_GHOST_SIL
        BEQ UFG_TRANS
        ; Oogjes op Y=4..5, X=4..5 en X=10..11
        CPY #4
        BCC UFG_BODY
        CPY #6
        BCS UFG_MOUTH
        CPX #4
        BEQ UFG_FACE
        CPX #5
        BEQ UFG_FACE
        CPX #10
        BEQ UFG_FACE
        CPX #11
        BEQ UFG_FACE
        JMP UFG_BODY
UFG_MOUTH:
        ; Golf-mondje op Y=10
        CPY #10
        BNE UFG_BODY
        TXA
        AND #2
        BNE UFG_FACE
UFG_BODY:
        LDA ZP_COL
        JMP UFG_OUT
UFG_FACE:
        LDA ZP_TMP4
        JMP UFG_OUT
UFG_TRANS:
        LDA #$E3
UFG_OUT:
        STA IO_GPU
        INX
        CPX #16
        BCC UFG_X
        INY
        CPY #16
        BCC UFG_Y
        RTS

; Geeft Z=0 (niet-nul) als (ZP_TMP1=X, ZP_TMP2=Y) binnen spook-silhouet valt
GET_GHOST_SIL:
        STX ZP_X_LO
        STY ZP_Y_LO
        LDA ZP_TMP2
        ASL A
        TAY
        LDA ZP_TMP1
        CMP #8
        BCC GGS_LB
        INY
        SEC
        SBC #8
GGS_LB:
        TAX
        LDA GHOST_MASK,Y
        AND BIT_M8,X
        LDX ZP_X_LO
        LDY ZP_Y_LO
        CMP #0
        RTS

; ============================================================================
; Tabellen, Bitmasks, Melodieën & Het 27x21 Arcade Doolhof
; ============================================================================
DIR_DX:         .BYTE 0, 0, $FF, 1
DIR_DY:         .BYTE $FF, 1, 0, 0
PAC_DIR_SPR:    .BYTE SPR_PAC_U, SPR_PAC_D, SPR_PAC_L, SPR_PAC_R
GHOST_COLS:     .BYTE $E0, $F3, $1F, $F0
BIT_M8:         .BYTE $80, $40, $20, $10, $08, $04, $02, $01

; Startposities van de 4 Spoken (X2 = mx*8, Y2 = my*8)
; Blinky (14,9), Pinky (10,9), Inky (18,9), Clyde (14,11 in Spookhuis)
G_INIT_X:       .BYTE 112, 80, 144, 112
G_INIT_Y:       .BYTE 72,  72, 72,  88
G_INIT_D:       .BYTE 2,   2,  3,   0

DEC_POW_LO:     .BYTE $10, $E8, 100, 10, 1
DEC_POW_HI:     .BYTE $27, $03, 0,   0,  0

; 16x16 Bitmask voor Pac-Man Rechts (32 bytes)
PAC_MASK:
        .BYTE $07, $E0, $1F, $F8, $3F, $FC, $7F, $FE
        .BYTE $7F, $FE, $FF, $F0, $FF, $80, $FC, $00
        .BYTE $FC, $00, $FF, $80, $FF, $F0, $7F, $FE
        .BYTE $7F, $FE, $3F, $FC, $1F, $F8, $07, $E0

; 16x16 Bitmask voor Spook-silhouet (32 bytes)
GHOST_MASK:
        .BYTE $07, $E0, $1F, $F8, $3F, $FC, $7F, $FE
        .BYTE $7F, $FE, $7F, $FE, $FF, $FF, $FF, $FF
        .BYTE $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
        .BYTE $FF, $FF, $EE, $EE, $C6, $63, $00, $00

; Pac-Man Intro Melodie
INTRO_NOTES:    .BYTE 84, 168, 126, 105, 168, 126, 105, 89, 178, 134, 112, 178, 134, 112, 0
INTRO_DURS:     .BYTE 7,  7,   7,   7,   4,   8,   12,  7,  7,   7,   7,   4,   8,   12,  0
WIN_NOTES:      .BYTE 89, 112, 134, 178, 134, 178, 0

GPU_INIT_BYTES:
        ; BIGSPR 0,0,0,0 (8B) + BIGSPR 1,0,0,0 (8B) + SCROLL 0,512 (5B)
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 2
GPU_INIT_BYTES_END:

HUD_GPU_STREAM:
        ; Rechter paneel achtergrond: RECT(452, 16, 180, 336, $00)
        .BYTE 2, $C4,$01, 16,0, 180,0, $50,$01, $00
        ; Gele Titelbalk bovenin: RECT(456, 20, 172, 24, $FC)
        .BYTE 2, $C8,$01, 20,0, 172,0, 24,0, $FC
        ; Neon cyaan kaders om zijpaneel (X=452..631, Y=16..351)
        .BYTE 3, $C4,$01, 16,0, $77,$02, 16,0, $1F
        .BYTE 3, $C4,$01, $5F,$01, $77,$02, $5F,$01, $1F
        .BYTE 3, $C4,$01, 16,0, $C4,$01, $5F,$01, $1F
        .BYTE 3, $77,$02, 16,0, $77,$02, $5F,$01, $1F
HUD_GPU_STREAM_END:

HUD_CLR_STREAM:
        ; Wis SCORE (516, 68, 48, 12), HSCORE (516, 112, 48, 12), LEVEL (540, 152, 48, 12), LIVES (468, 186, 150, 20)
        .BYTE 2, $04,$02, 68,0, 48,0, 12,0, $00
        .BYTE 2, $04,$02, 112,0, 48,0, 12,0, $00
        .BYTE 2, $1C,$02, 152,0, 48,0, 12,0, $00
        .BYTE 2, $D4,$01, 186,0, 150,0, 20,0, $00
HUD_CLR_STREAM_END:

HUD_TEXT_TBL:
        .BYTE $DC,$01, 28,0,  $00, "PAC-MAN ARCADE", 0
        .BYTE $D0,$01, 54,0,  $1F, "1UP SCORE", 0
        .BYTE $D0,$01, 98,0,  $FC, "HIGH SCORE", 0
        .BYTE $D0,$01, 154,0, $1F, "STAGE:", 0
        .BYTE $D0,$01, 174,0, $1F, "LIVES:", 0
        .BYTE $EC,$01, 232,0, $E0, "- BLINKY", 0
        .BYTE $EC,$01, 248,0, $F3, "- PINKY", 0
        .BYTE $EC,$01, 8,1,   $1F, "- INKY", 0
        .BYTE $EC,$01, 24,1,  $F0, "- CLYDE", 0
        .BYTE $CC,$01, 56,1,  $3F, "WASD / PIJLTJES", 0
        .BYTE $CC,$01, 72,1,  $FC, "N=STAGE ESC=STOP", 0
        .BYTE $FF

STR_READY:      .ASCIIZ "READY!"
STR_GAMEOVER:   .ASCIIZ "GAME OVER"

; Per-stage muurkleuren (Stage 1: Cyaan/Blauw, Stage 2: Roze/Paars, Stage 3: Smaragdgroen, Stage 4: Goud/Rood)
WALL_BORDER_COLS: .BYTE $1F, $F3, $1C, $FC
WALL_FILL_COLS:   .BYTE $02, $41, $04, $60
FRIGHT_DUR_TBL:   .BYTE 220, 180, 145, 115, 95, 80, 65, 50
MAZE_OFF_TBL:     .BYTE 0, 28, 56, 84
MID_ROW_OFF:      .BYTE 0, 14, 28, 42, 56

; Gedeelde middenrijen (my = 9..13: Spookhuis, Warp-tunnel & Kers)
MID_ROWS_ASCII:
        .TEXT "######.##     "
        .TEXT "######.## ###-"
        .TEXT "      .   #   "
        .TEXT "######.## ####"
        .TEXT "######.##    C"

; 4 Unieke 27x21 Symmetrische Arcade Doolhoven (14 bit-gepakte rijen x 2 bytes = 28 bytes per doolhof)
MAZE_BITS:
        ; Doolhof 1: Classic Arcade (Cyaan/Blauw)
        .BYTE $80, $04, $BD, $F4, $BD, $F4, $80, $00, $BD, $BC, $81, $80, $FD, $F0
        .BYTE $FD, $BC, $80, $04, $BD, $F4, $81, $80, $BD, $BC, $BD, $BC, $80, $00
        ; Doolhof 2: Ms. Pac-Man Wide Arcade (Roze/Paars)
        .BYTE $81, $00, $BD, $7C, $BD, $7C, $80, $00, $BD, $BC, $81, $80, $FD, $F0
        .BYTE $FD, $BC, $81, $80, $BD, $F4, $8C, $00, $ED, $BC, $81, $84, $80, $00
        ; Doolhof 3: Emerald Twin-Corridors (Smaragdgroen)
        .BYTE $80, $04, $BB, $B4, $A0, $34, $AF, $84, $8F, $BC, $E1, $80, $FD, $F0
        .BYTE $FD, $BC, $80, $30, $BF, $B4, $A1, $80, $AD, $BC, $8C, $04, $80, $00
        ; Doolhof 4: Golden Turbo Plaza (Goud/Rood)
        .BYTE $83, $00, $BB, $7C, $A0, $04, $AF, $74, $8F, $64, $E0, $60, $FD, $F0
        .BYTE $FD, $BC, $80, $30, $BD, $B4, $8D, $80, $ED, $BC, $81, $84, $80, $00
