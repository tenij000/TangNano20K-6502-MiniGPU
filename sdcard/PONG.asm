; ============================================================================
; PONG.asm v1.0 - Twente Arcade Pong Deluxe 6502 (60 FPS + 720p Boerderij/Space!)
; Geassembleerd voor $8000 (Past in 1 SD-slot van 4 KB, naast MC op $9000!)
;
; Kenmerken:
;   - Boterzachte 50 FPS Partial-Erase Engine (nul geflikker, nul vertraging!)
;   - Non-blocking 16-Bit Stereo Geluidseffecten (Ping, Pong, Muur, Smash, Score!)
;   - 1-Speler tegen slimme CPU (3 niveaus: Makkelijk, Normaal, Pro) óf 2-Spelers!
;   - 5-Zone Hoek-Fysica op het batje + Rally-versnelling + Turbo-Smash [SPATIE]!
;   - Druk op [B] om live bovenop de 720p Twentse Boerderij of Space te spelen!
;
; Besturing:
;   [W] / [S] of Pijltjes : Beweeg Linker Batje (Speler 1)
;   [I] / [K]             : Beweeg Rechter Batje (in 2-Speler modus)
;   [SPATIE]              : Serveer bal / Geef Gouden Turbo-Smash!
;   [1] / [2]             : Kies 1-Speler (tegen CPU) of 2-Speler modus
;   [M]                   : Wissel CPU Moeilijkheid (1=MAKKELIJK, 2=NORMAAL, 3=PRO)
;   [B]                   : Wissel Stadion <-> 720p Boerderij / Space Achtergrond!
;   [R]                   : Nieuwe Wedstrijd (Reset scores naar 0 - 0)
;   [ESC] / [Q]           : Afsluiten naar BASIC / Midnight Commander
; ============================================================================

        .ORG $8000

; --- Hardware I/O Registers ---
IO_STATUS       = $A000         ; Bit 0 = char ready, Bit 7 = ESC
IO_TERM         = $A001         ; ASCII karakter
IO_TIMER        = $A003         ; 100 Hz systeemtimer
IO_JOY          = $A004         ; Joypad / Pijltjes
IO_RND          = $A005         ; Hardware LFSR Random byte
IO_MODE         = $A006         ; 0=MODE 1, 1=MODE 0, 2=720p Panorama, 6=Toggle Thema
IO_INST         = $A00A         ; 16-Bit Stereo Sound Card Instrument
IO_FX           = $A00B         ; 16-Bit Stereo Sound Card FX
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- Speelveld Constanten (640x360) ---
ARENA_TOP       = 44            ; Bovenwand onderkant (wand op Y=40..43)
ARENA_BOT       = 249           ; Onderwand bovenkant (wand op Y=249..252)
PAD_H           = 48            ; Hoogte van elk batje (48 px)
PAD_W           = 10            ; Breedte van elk batje (10 px)
PAD_MIN_Y       = 46            ; Hoogste batje-positie
PAD_MAX_Y       = 200           ; Laagste batje-positie (248 - 48, past in 8-bit!)
PAD1_X          = 24            ; X-positie Linker Batje
PAD2_X_LO       = (606 & $FF)   ; X-positie Rechter Batje (606)
PAD2_X_HI       = (606 >> 8)
BALL_SZ         = 10            ; Bal grootte (10x10 px)
BALL_MIN_Y      = 45
BALL_MAX_Y      = 238           ; 248 - 10 (past in 8-bit!)
WIN_SCORE       = 7             ; Eerste tot 7 punten wint!

; --- Zero-Page Variabelen ($50..$7F) ---
ZP_PTR_LO       = $50
ZP_PTR_HI       = $51
ZP_X_LO         = $52
ZP_X_HI         = $53
ZP_Y_LO         = $54
ZP_Y_HI         = $55
ZP_W_LO         = $56
ZP_H_LO         = $57
ZP_COL          = $58
ZP_FG_COL       = $59

PAD1_Y          = $5A           ; Linker batje Y (46..266)
PAD2_Y          = $5B           ; Rechter batje Y (46..266)
OLD_PAD1_Y      = $5C
OLD_PAD2_Y      = $5D

BALL_X_LO       = $5E           ; Bal X (16-bit: 0..639)
BALL_X_HI       = $5F
BALL_Y          = $60           ; Bal Y (45..304)
OLD_BX_LO       = $61
OLD_BX_HI       = $62
OLD_BY          = $63

BALL_DX         = $64           ; Signed X-snelheid (-9..+9)
BALL_DY         = $65           ; Signed Y-snelheid (-6..+6)
BALL_SPEED      = $66           ; Huidige horizontale snelheid (4..9)
RALLY_CNT       = $67           ; Aantal treffers in huidige rally
MAX_RALLY       = $68           ; Hoogste rally in deze wedstrijd

SCORE_P1        = $69           ; Score Speler 1 (0..7)
SCORE_P2        = $6A           ; Score CPU / Speler 2 (0..7)
TWO_PLAYERS     = $6B           ; 0 = 1P vs CPU, 1 = 2P Versus
CPU_DIFF        = $6C           ; 0 = Makkelijk, 1 = Normaal, 2 = Pro
BG_MODE         = $6D           ; 0 = Arcade Stadion ($01), 1 = Boerderij, 2 = Space ($E3)
BG_COL          = $6E           ; $01 in Stadion, $E3 (transparant) in 720p modus
GAME_STATE      = $6F           ; 0 = Serveer-wacht, 1 = Bal in spel, 2 = Gewonnen!
SERVE_DIR       = $70           ; 0 = Naar rechts, 1 = Naar links
SMASH_ARMED     = $71           ; >0 als Speler 1 op SPATIE drukte voor Turbo-Smash
SFX_TIMER       = $72           ; Non-blocking audio gate teller (in frames)
LAST_TIMER      = $73
TEMP_A          = $74
TEMP_B          = $75

; ============================================================================
; Hoofdprogramma Start
; ============================================================================
START:
        CLD
        LDA #0
        STA IO_MODE             ; Start in strakke MODE 1 (Arcade Stadion)
        STA ZP_Y_HI
        STA TWO_PLAYERS
        STA BG_MODE
        STA SERVE_DIR
        LDA #1
        STA CPU_DIFF            ; Standaard: 2=NORMAAL (index 1)
        LDA #$01
        STA BG_COL              ; Donkerblauw Arcade-stadion

        ; Stel 16-Bit Stereo Sound Card in op heldere Studio Mix ($A00A=8, $A00B=5)
        LDA #8
        STA IO_INST
        LDA #5
        STA IO_FX

        JSR INIT_MATCH
        JMP MAIN_LOOP

; ============================================================================
; Initialiseer Nieuwe Wedstrijd (0 - 0) & Serveer-Positie
; ============================================================================
INIT_MATCH:
        LDA #0
        STA SCORE_P1
        STA SCORE_P2
        STA RALLY_CNT
        STA MAX_RALLY
        STA SFX_TIMER
        LDA #122
        STA PAD1_Y
        STA PAD2_Y
        STA OLD_PAD1_Y
        STA OLD_PAD2_Y
        JSR RESET_BALL_CENTER
        JSR DRAW_FULL_ARENA
        JSR SFX_START_CHORD
        RTS

RESET_BALL_CENTER:
        LDA #0
        STA GAME_STATE          ; 0 = Klaar om te serveren (of auto-serveer)
        STA RALLY_CNT
        STA SMASH_ARMED
        LDA #<315
        STA BALL_X_LO
        STA OLD_BX_LO
        LDA #>315
        STA BALL_X_HI
        STA OLD_BX_HI
        LDA #142
        STA BALL_Y
        STA OLD_BY
        LDA #5
        STA BALL_SPEED
        ; Kies serveer-richting (+5 of -5)
        LDA SERVE_DIR
        BNE RBC_LEFT
        LDA #5
        BNE RBC_SET_DX
RBC_LEFT:
        LDA #(256 - 5)
RBC_SET_DX:
        STA BALL_DX
        ; Willekeurige lichte Y-hoek (-2, -1, +1 of +2)
        LDA IO_RND
        AND #1
        CLC
        ADC #1
        BIT IO_RND
        BPL RBC_DY_OK
        EOR #$FF
        CLC
        ADC #1
RBC_DY_OK:
        STA BALL_DY
        RTS

; ============================================================================
; Hoofdlus (50 Hz Frame-Locked op IO_TIMER = $A003)
; ============================================================================
MAIN_LOOP:
        ; Check ESC bit (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL ML_CHK_KEY
        LDA IO_TERM
        JMP QUIT_TO_BASIC

ML_CHK_KEY:
        LDA IO_STATUS
        AND #$01
        BEQ ML_WAIT_TICK
        LDA IO_TERM
        JSR HANDLE_KEY

ML_WAIT_TICK:
        ; Wacht op 2 ticks van de 100 Hz timer (= exact 50 FPS = 20ms per frame!)
        LDA IO_TIMER
        SEC
        SBC LAST_TIMER
        CMP #2
        BCC MAIN_LOOP
        LDA IO_TIMER
        STA LAST_TIMER

        ; Beheer non-blocking geluidseffect-timer (zodat audio nooit het beeld vertraagt!)
        LDA SFX_TIMER
        BEQ ML_JOY
        DEC SFX_TIMER
        BNE ML_JOY
        JSR SILENCE_ALL_AUDIO

ML_JOY:
        ; Lees live Joypad / Pijltjes / W/S status op $A004 voor boterzachte batje-beweging!
        LDA IO_JOY
        TAY
        AND #$01                ; Omhoog / W
        BEQ ML_J_DN
        JSR MOVE_PAD1_UP
ML_J_DN:
        TYA
        AND #$02                ; Omlaag / S
        BEQ ML_J_FIRE
        JSR MOVE_PAD1_DOWN
ML_J_FIRE:
        TYA
        AND #$10                ; Vuurknop / Spatie
        BEQ ML_AI_STEP
        JSR TRIGGER_SERVE_OR_SMASH

ML_AI_STEP:
        ; Als 1-Speler modus actief is: beweeg CPU-batje (Rechts)
        LDA TWO_PLAYERS
        BNE ML_BALL_STEP
        JSR UPDATE_CPU_PADDLE

ML_BALL_STEP:
        LDA GAME_STATE
        CMP #1
        BNE ML_RENDER
        JSR UPDATE_BALL_PHYSICS

ML_RENDER:
        JSR RENDER_FRAME_DELTA
        JMP MAIN_LOOP

; ============================================================================
; Toetsenbord Afhandeling
; ============================================================================
HANDLE_KEY:
        CMP #$1B                ; ESC
        BNE HK_NOT_ESC
        PLA
        PLA
        JMP QUIT_TO_BASIC
HK_NOT_ESC:
        CMP #'a'
        BCC HK_UPPER
        CMP #'z'+1
        BCS HK_UPPER
        AND #$DF
HK_UPPER:
        CMP #'Q'
        BNE HK_NOT_Q
        PLA
        PLA
        JMP QUIT_TO_BASIC
HK_NOT_Q:
        CMP #'W'
        BEQ MOVE_PAD1_UP
        CMP #'S'
        BEQ MOVE_PAD1_DOWN
        CMP #'I'
        BEQ MOVE_PAD2_UP
        CMP #'O'
        BEQ MOVE_PAD2_UP
        CMP #'K'
        BEQ MOVE_PAD2_DOWN
        CMP #'L'
        BEQ MOVE_PAD2_DOWN
        CMP #' '
        BEQ TRIGGER_SERVE_OR_SMASH
        CMP #$0D
        BEQ TRIGGER_SERVE_OR_SMASH
        CMP #'1'
        BNE HK_NOT_1
        LDA #0
        STA TWO_PLAYERS
        JSR SFX_WALL_BEEP
        JMP DRAW_HUD_HEADER
HK_NOT_1:
        CMP #'2'
        BNE HK_NOT_2
        LDA #1
        STA TWO_PLAYERS
        JSR SFX_WALL_BEEP
        JMP DRAW_HUD_HEADER
HK_NOT_2:
        CMP #'M'
        BNE HK_NOT_M
        INC CPU_DIFF
        LDA CPU_DIFF
        CMP #3
        BCC HK_M_OK
        LDA #0
        STA CPU_DIFF
HK_M_OK:
        JSR SFX_WALL_BEEP
        JMP DRAW_HUD_HEADER
HK_NOT_M:
        CMP #'B'
        BNE HK_NOT_B
        JMP TOGGLE_BG_MODE
HK_NOT_B:
        CMP #'R'
        BNE HK_RTS
        JMP INIT_MATCH
HK_RTS:
        RTS

; ============================================================================
; Batje Beweging (Speler 1 Links, Speler 2 / CPU Rechts)
; ============================================================================
MOVE_PAD1_UP:
        LDA PAD1_Y
        SEC
        SBC #6
        CMP #PAD_MIN_Y
        BCS MP1U_OK
        LDA #PAD_MIN_Y
MP1U_OK:
        STA PAD1_Y
        RTS

MOVE_PAD1_DOWN:
        LDA PAD1_Y
        CLC
        ADC #6
        CMP #PAD_MAX_Y
        BCC MP1D_OK
        LDA #PAD_MAX_Y
MP1D_OK:
        STA PAD1_Y
        RTS

MOVE_PAD2_UP:
        LDA #1
        STA TWO_PLAYERS         ; Zodra I/K gedrukt wordt, schakel 2P in!
        LDA PAD2_Y
        SEC
        SBC #6
        CMP #PAD_MIN_Y
        BCS MP2U_OK
        LDA #PAD_MIN_Y
MP2U_OK:
        STA PAD2_Y
        RTS

MOVE_PAD2_DOWN:
        LDA #1
        STA TWO_PLAYERS
        LDA PAD2_Y
        CLC
        ADC #6
        CMP #PAD_MAX_Y
        BCC MP2D_OK
        LDA #PAD_MAX_Y
MP2D_OK:
        STA PAD2_Y
        RTS

TRIGGER_SERVE_OR_SMASH:
        LDA GAME_STATE
        BEQ TSOS_SERVE
        CMP #2
        BNE TSOS_SMASH
        JMP INIT_MATCH
TSOS_SERVE:
        LDA #1
        STA GAME_STATE
        JSR DRAW_STATUS_MSG
        JMP SFX_PAD_LEFT
TSOS_SMASH:
        LDA #12                 ; 12 frames Smash-window actief!
        STA SMASH_ARMED
        RTS

; ============================================================================
; Wissel Achtergrond ([B]: 0=Arcade Stadion -> 1=720p Boerderij -> 2=720p Space)
; ============================================================================
TOGGLE_BG_MODE:
        INC BG_MODE
        LDA BG_MODE
        CMP #3
        BCC TBM_OK
        LDA #0
        STA BG_MODE
TBM_OK:
        CMP #0
        BNE TBM_720P
        ; Terug naar Klassiek Donkerblauw Arcade-Stadion (MODE 1)
        LDA #0
        STA IO_MODE
        LDA #$01
        STA BG_COL
        JMP DRAW_FULL_ARENA

TBM_720P:
        CMP #1
        BNE TBM_SPACE
        LDA #3                  ; Kies Boerderij thema
        BNE TBM_SET_PANO
TBM_SPACE:
        LDA #5                  ; Kies Space Planets thema
TBM_SET_PANO:
        STA IO_MODE
        LDA #2                  ; Zet 720p Panorama modus aan (verbergt tekstlaag & vult $E3)
        STA IO_MODE
        LDA #$E3                ; Transparante wis-kleur!
        STA BG_COL
        ; Wacht kort tot hardware-clear naar $E3 klaar is
        LDX #4
        JSR WAIT_X_TICKS
        JMP DRAW_FULL_ARENA

; ============================================================================
; Slimme CPU Tegenstander voor Rechter Batje (3 Niveaus: Makkelijk, Normaal, Pro)
; ============================================================================
UPDATE_CPU_PADDLE:
        LDA GAME_STATE
        CMP #1
        BNE UCP_RTS

        ; Snelheid per CPU-niveau (Makkelijk=3, Normaal=4, Pro=6 px/frame)
        LDX CPU_DIFF
        LDA CPU_SPEED_TBL,X
        STA TEMP_A

        ; Als de bal naar links beweegt, keert CPU rustig terug naar het midden (Y=122)
        LDA BALL_DX
        BMI UCP_CENTER
        ; Op Makkelijk reageert CPU pas als de bal over de middenlijn is (BALL_X_HI > 0)
        CPX #0
        BNE UCP_TRACK
        LDA BALL_X_HI
        BEQ UCP_RTS

UCP_TRACK:
        ; Richt het midden van het CPU-batje (PAD2_Y + 20) op BALL_Y
        LDA PAD2_Y
        CLC
        ADC #20
        JMP UCP_COMPARE

UCP_CENTER:
        LDA #1
        STA TEMP_A
        LDA PAD2_Y
        CMP #122
        BEQ UCP_RTS

UCP_COMPARE:
        CMP BALL_Y
        BEQ UCP_RTS
        BCS UCP_UP
        ; Beweeg omlaag met snelheid TEMP_A
        LDA PAD2_Y
        CLC
        ADC TEMP_A
        CMP #PAD_MAX_Y
        BCC UCP_SET
        LDA #PAD_MAX_Y
        BCS UCP_SET
UCP_UP:
        ; Beweeg omhoog met snelheid TEMP_A
        LDA PAD2_Y
        SEC
        SBC TEMP_A
        CMP #PAD_MIN_Y
        BCS UCP_SET
        LDA #PAD_MIN_Y
UCP_SET:
        STA PAD2_Y
UCP_RTS:
        RTS

; ============================================================================
; Bal Fysica, Muur-Stuiten, 5-Zone Batje-Botsing & Score Checks
; ============================================================================
UPDATE_BALL_PHYSICS:
        LDA SMASH_ARMED
        BEQ UBP_MOVE_X
        DEC SMASH_ARMED

UBP_MOVE_X:
        ; 1. Verplaats BALL_X met signed 8-bit BALL_DX
        LDA BALL_DX
        BMI UBP_DX_NEG
        CLC
        ADC BALL_X_LO
        STA BALL_X_LO
        BCC UBP_MOVE_Y
        INC BALL_X_HI
        JMP UBP_MOVE_Y
UBP_DX_NEG:
        CLC
        ADC BALL_X_LO
        STA BALL_X_LO
        BCS UBP_MOVE_Y
        DEC BALL_X_HI

UBP_MOVE_Y:
        ; 2. Verplaats BALL_Y met signed 8-bit BALL_DY
        LDA BALL_Y
        CLC
        ADC BALL_DY
        STA BALL_Y

        ; Check bovenwand (BALL_MIN_Y = 45)
        CMP #BALL_MIN_Y
        BCS UBP_CHK_BOT
        LDA #BALL_MIN_Y
        STA BALL_Y
        JMP UBP_BOUNCE_Y

UBP_CHK_BOT:
        ; Check onderwand (BALL_MAX_Y = 304 -> maar in 8-bit: we houden onderwand op Y=246!)
        ; Wacht: BALL_Y is 1 byte (0..255)!
        ; Daarom plaatsen we de onderwand op Y = 250 (zodat BALL_Y = 45..240 altijd in 1 byte past!)
        CMP #238
        BCC UBP_CHK_LEFT
        LDA #238
        STA BALL_Y

UBP_BOUNCE_Y:
        LDA BALL_DY
        EOR #$FF
        CLC
        ADC #1
        STA BALL_DY
        JSR SFX_WALL_BEEP

UBP_CHK_LEFT:
        ; 3. Check Linker Batje (X = 24..34, dus BALL_X_HI == 0 en BALL_X_LO tussen 16 en 34)
        LDA BALL_DX
        BPL UBP_CHK_RIGHT
        LDA BALL_X_HI
        BNE UBP_RTS_JMP
        LDA BALL_X_LO
        CMP #35
        BCS UBP_RTS_JMP
        CMP #16
        BCC UBP_CHK_P2_SCORE

        ; Check of BALL_Y + 9 >= PAD1_Y en BALL_Y <= PAD1_Y + 48
        LDA BALL_Y
        CLC
        ADC #9
        CMP PAD1_Y
        BCC UBP_CHK_P2_SCORE
        LDA PAD1_Y
        CLC
        ADC #PAD_H
        CMP BALL_Y
        BCC UBP_CHK_P2_SCORE

        ; RAAK OP LINKER BATJE (SPELER 1)!
        LDA #34
        STA BALL_X_LO
        LDX PAD1_Y
        JSR CALC_BOUNCE_ANGLE
        ; Check of Turbo-Smash actief is!
        LDA SMASH_ARMED
        BEQ UBP_L_NORM
        LDA #0
        STA SMASH_ARMED
        LDA BALL_SPEED
        CLC
        ADC #2
        CMP #10
        BCC UBP_L_SM_OK
        LDA #9
UBP_L_SM_OK:
        STA BALL_DX
        JSR SFX_SMASH_HIT
        JMP UBP_INC_RALLY
UBP_L_NORM:
        LDA BALL_SPEED
        STA BALL_DX
        JSR SFX_PAD_LEFT
        JMP UBP_INC_RALLY

UBP_CHK_P2_SCORE:
        LDA BALL_X_LO
        CMP #8
        BCS UBP_RTS_JMP
        ; Punt voor Speler 2 / CPU!
        INC SCORE_P2
        LDA #0
        STA SERVE_DIR
        JMP HANDLE_POINT_SCORED

UBP_RTS_JMP:
        RTS

UBP_CHK_RIGHT:
        ; 4. Check Rechter Batje (PAD2_X = 606 -> BALL_X + 10 >= 606 => BALL_X >= 596 = $0254)
        LDA BALL_X_HI
        CMP #2
        BCC UBP_RTS_JMP
        LDA BALL_X_LO
        CMP #(596 & $FF)        ; 84
        BCC UBP_RTS_JMP
        CMP #(614 & $FF)        ; 102
        BCS UBP_CHK_P1_SCORE

        ; Check Y-overlap met PAD2_Y
        LDA BALL_Y
        CLC
        ADC #9
        CMP PAD2_Y
        BCC UBP_CHK_P1_SCORE
        LDA PAD2_Y
        CLC
        ADC #PAD_H
        CMP BALL_Y
        BCC UBP_CHK_P1_SCORE

        ; RAAK OP RECHTER BATJE (CPU / SPELER 2)!
        LDA #(595 & $FF)
        STA BALL_X_LO
        LDX PAD2_Y
        JSR CALC_BOUNCE_ANGLE
        LDA BALL_SPEED
        EOR #$FF
        CLC
        ADC #1
        STA BALL_DX
        JSR SFX_PAD_RIGHT

UBP_INC_RALLY:
        INC RALLY_CNT
        LDA RALLY_CNT
        CMP MAX_RALLY
        BCC UBP_CHK_ACCEL
        STA MAX_RALLY
UBP_CHK_ACCEL:
        ; Elke 4 treffers versnelt de bal (+1 tot max 8)!
        LDA RALLY_CNT
        AND #3
        BNE UBP_UPD_RALLY_HUD
        LDA BALL_SPEED
        CMP #8
        BCS UBP_UPD_RALLY_HUD
        INC BALL_SPEED
UBP_UPD_RALLY_HUD:
        JMP DRAW_RALLY_NUM

UBP_CHK_P1_SCORE:
        LDA BALL_X_LO
        CMP #(624 & $FF)        ; 112
        BCC UBP_RTS2
        ; Punt voor Speler 1!
        INC SCORE_P1
        LDA #1
        STA SERVE_DIR

HANDLE_POINT_SCORED:
        ; Wis bal op oude plek, werk scorebord bij en speel score-geluid!
        JSR ERASE_OLD_BALL
        JSR DRAW_CENTER_NET
        JSR RESET_BALL_CENTER
        JSR DRAW_BALL_NEW
        JSR DRAW_SCORE_NUMS

        ; Check of iemand 7 punten heeft bereikt!
        LDA SCORE_P1
        CMP #WIN_SCORE
        BCS HPS_WIN
        LDA SCORE_P2
        CMP #WIN_SCORE
        BCS HPS_WIN

        JSR DRAW_STATUS_MSG
        JMP SFX_POINT_LOST

HPS_WIN:
        LDA #2
        STA GAME_STATE
        JSR DRAW_STATUS_MSG
        JMP SFX_VICTORY_FANFARE

UBP_RTS2:
        RTS

; ============================================================================
; Bereken 5-Zone Hoek op Batje (X = PAD_Y): zet BALL_DY op -4, -2, -1, +1, +2 of +4
; ============================================================================
CALC_BOUNCE_ANGLE:
        STX TEMP_A
        LDA BALL_Y
        CLC
        ADC #5                  ; Midden van de bal
        SEC
        SBC TEMP_A              ; Relatieve treffer-positie op batje (0..52)
        BCS CBA_POS
        LDA #0
CBA_POS:
        LSR A
        LSR A
        LSR A                   ; Deel door 8 -> zone 0..6
        CMP #6
        BCC CBA_LOOK
        LDA #6
CBA_LOOK:
        TAY
        LDA BOUNCE_DY_TBL,Y
        STA BALL_DY
        RTS

; ============================================================================
; Boterzachte Delta-Renderer (Wist alleen veranderde posities & tekent nieuw!)
; ============================================================================
RENDER_FRAME_DELTA:
        ; 1. Als PAD1_Y veranderd is: wis oud batje en teken nieuw batje!
        LDA PAD1_Y
        CMP OLD_PAD1_Y
        BEQ RFD_CHK_P2
        LDY OLD_PAD1_Y
        LDA #<PAD1_X
        LDX #>PAD1_X
        JSR ERASE_PADDLE_AT
        LDA PAD1_Y
        STA OLD_PAD1_Y
        JSR DRAW_PAD1

RFD_CHK_P2:
        ; 2. Als PAD2_Y veranderd is: wis oud batje en teken nieuw batje!
        LDA PAD2_Y
        CMP OLD_PAD2_Y
        BEQ RFD_CHK_BALL
        LDY OLD_PAD2_Y
        LDA #PAD2_X_LO
        LDX #PAD2_X_HI
        JSR ERASE_PADDLE_AT
        LDA PAD2_Y
        STA OLD_PAD2_Y
        JSR DRAW_PAD2

RFD_CHK_BALL:
        ; 3. Als de bal bewogen is: wis oude bal, herstel middenlijn indien nodig, teken nieuwe bal!
        LDA BALL_X_LO
        CMP OLD_BX_LO
        BNE RFD_DO_BALL
        LDA BALL_Y
        CMP OLD_BY
        BEQ RFD_RTS

RFD_DO_BALL:
        JSR ERASE_OLD_BALL

        ; Als de oude bal vlakbij de middenlijn (X = 304..326 -> HI=1, LO=48..70) was, herstel middenlijn!
        LDA OLD_BX_HI
        CMP #1
        BNE RFD_DRAW_NEW_B
        LDA OLD_BX_LO
        CMP #46
        BCC RFD_DRAW_NEW_B
        CMP #74
        BCS RFD_DRAW_NEW_B
        JSR DRAW_CENTER_NET

RFD_DRAW_NEW_B:
        LDA BALL_X_LO
        STA OLD_BX_LO
        LDA BALL_X_HI
        STA OLD_BX_HI
        LDA BALL_Y
        STA OLD_BY
        JMP DRAW_BALL_NEW

RFD_RTS:
        RTS

ERASE_OLD_BALL:
        LDA OLD_BX_LO
        STA ZP_X_LO
        LDA OLD_BX_HI
        STA ZP_X_HI
        LDA OLD_BY
        STA ZP_Y_LO
        LDA #BALL_SZ
        STA ZP_W_LO
        STA ZP_H_LO
        LDA BG_COL
        STA ZP_COL
        JMP DRAW_RECT_ZP

DRAW_BALL_NEW:
        LDA BALL_X_LO
        STA ZP_X_LO
        LDA BALL_X_HI
        STA ZP_X_HI
        LDA BALL_Y
        STA ZP_Y_LO
        LDA #BALL_SZ
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #$FC                ; Goudgele/Witte Arcade Bal
        LDY SMASH_ARMED
        BEQ DBN_COL
        LDA #$E0                ; Vuurrode bal tijdens Smash!
DBN_COL:
        STA ZP_COL
        JSR DRAW_RECT_ZP
        ; Witte glans-kern (6x6) binnenin de bal
        INC ZP_X_LO
        BNE DBN_X1
        INC ZP_X_HI
DBN_X1: INC ZP_X_LO
        BNE DBN_X2
        INC ZP_X_HI
DBN_X2: INC ZP_Y_LO
        INC ZP_Y_LO
        LDA #6
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #$FF
        STA ZP_COL
        JMP DRAW_RECT_ZP

ERASE_PADDLE_AT:
        STA ZP_X_LO
        STX ZP_X_HI
        STY ZP_Y_LO
        LDA #PAD_W
        STA ZP_W_LO
        LDA #PAD_H
        STA ZP_H_LO
        LDA BG_COL
        STA ZP_COL
        JMP DRAW_RECT_ZP

DRAW_PAD1:
        LDA #<PAD1_X
        STA ZP_X_LO
        LDA #>PAD1_X
        STA ZP_X_HI
        LDA PAD1_Y
        LDY #$1F                ; Helder Cyaan-Blauw voor Speler 1
        JMP DRAW_PADDLE_3ZONE

DRAW_PAD2:
        LDA #PAD2_X_LO
        STA ZP_X_LO
        LDA #PAD2_X_HI
        STA ZP_X_HI
        LDA PAD2_Y
        LDY #$E0                ; Felrood/Oranje voor CPU / Speler 2

DRAW_PADDLE_3ZONE:
        STA ZP_Y_LO
        STY ZP_COL
        LDA #PAD_W
        STA ZP_W_LO
        LDA #PAD_H
        STA ZP_H_LO
        JSR DRAW_RECT_ZP
        ; Gouden Smash-Kern in het midden van het batje (Y+14, hoogte 20)
        LDA ZP_Y_LO
        CLC
        ADC #14
        STA ZP_Y_LO
        LDA #20
        STA ZP_H_LO
        LDA #$FC
        STA ZP_COL
        JMP DRAW_RECT_ZP

; ============================================================================
; Volledig Stadion, Middenlijn, Scorebord & Statusbalk Tekenen
; ============================================================================
DRAW_FULL_ARENA:
        ; Als we in Klassieke Stadion-modus (BG_MODE == 0) zitten: vul achtergrond met $01
        LDA BG_MODE
        BNE DFA_STREAM
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #$01
        STA IO_GPU

DFA_STREAM:
        LDX #0
DFA_LP:
        LDA ARENA_FRAME_STREAM,X
        STA IO_GPU
        INX
        CPX #(ARENA_FRAME_STREAM_END - ARENA_FRAME_STREAM)
        BCC DFA_LP

        LDA #<STR_STATIC_HUD
        STA ZP_PTR_LO
        LDA #>STR_STATIC_HUD
        STA ZP_PTR_HI
        JSR DRAW_TEXT_LIST

        JSR DRAW_CENTER_NET
        JSR DRAW_PAD1
        JSR DRAW_PAD2
        JSR DRAW_BALL_NEW
        JSR DRAW_HUD_HEADER
        JSR DRAW_SCORE_NUMS
        JSR DRAW_RALLY_NUM
        JMP DRAW_STATUS_MSG

; Teken gestippelde middenlijn van Y=48 tot Y=244 op X=318
DRAW_CENTER_NET:
        LDA #48
        STA TEMP_B
DCN_LP:
        LDA #<318
        STA ZP_X_LO
        LDA #>318
        STA ZP_X_HI
        LDA TEMP_B
        STA ZP_Y_LO
        LDA #4
        STA ZP_W_LO
        LDA #10
        STA ZP_H_LO
        LDA #$49
        STA ZP_COL
        JSR DRAW_RECT_ZP
        LDA TEMP_B
        CLC
        ADC #18
        STA TEMP_B
        CMP #246
        BCC DCN_LP
        RTS

DRAW_HUD_HEADER:
        ; Wis modus-vak in bovenbalk (X=224, Y=6, W=196, H=14)
        LDX #0
        JSR SEND_UI_RECT
        LDA #<230
        STA ZP_X_LO
        LDA #>230
        STA ZP_X_HI
        LDA #8
        STA ZP_Y_LO
        LDA #$1C
        STA ZP_FG_COL
        LDA TWO_PLAYERS
        BEQ DHH_1P
        LDA #<STR_MODE_2P
        LDY #>STR_MODE_2P
        JMP DRAW_AY_STR
DHH_1P:
        LDX CPU_DIFF
        LDA DIFF_STR_LO,X
        LDY DIFF_STR_HI,X
        JMP DRAW_AY_STR

DRAW_SCORE_NUMS:
        ; Wis en teken Score Speler 1 (X=148, Y=24) & Speler 2 (X=484, Y=24)
        LDX #10
        JSR SEND_UI_RECT
        LDX #20
        JSR SEND_UI_RECT

        LDA #152
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #25
        STA ZP_Y_LO
        LDA #$1F
        STA ZP_FG_COL
        LDA SCORE_P1
        JSR DRAW_DEC_A2

        LDA #<488
        STA ZP_X_LO
        LDA #>488
        STA ZP_X_HI
        LDA #$E0
        STA ZP_FG_COL
        LDA SCORE_P2
        JMP DRAW_DEC_A2

DRAW_RALLY_NUM:
        LDX #30
        JSR SEND_UI_RECT
        LDA #<312
        STA ZP_X_LO
        LDA #>312
        STA ZP_X_HI
        LDA #25
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_FG_COL
        LDA RALLY_CNT
        JMP DRAW_DEC_A2

DRAW_STATUS_MSG:
        LDX #40
        JSR SEND_UI_RECT
        LDA #16
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #(338 & $FF)
        STA ZP_Y_LO
        LDA #(338 >> 8)
        STA ZP_Y_HI
        LDA #$FC
        STA ZP_FG_COL

        LDA GAME_STATE
        BEQ DSM_SERVE
        CMP #1
        BEQ DSM_PLAYING
        ; Iemand heeft gewonnen!
        LDA SCORE_P1
        CMP #WIN_SCORE
        BCS DSM_P1_WON
        LDA #<STR_WIN_P2
        LDY #>STR_WIN_P2
        BNE DSM_PRINT
DSM_P1_WON:
        LDA #<STR_WIN_P1
        LDY #>STR_WIN_P1
        BNE DSM_PRINT
DSM_SERVE:
        LDA #<STR_MSG_SERVE
        LDY #>STR_MSG_SERVE
        BNE DSM_PRINT
DSM_PLAYING:
        LDA #<STR_MSG_PLAY
        LDY #>STR_MSG_PLAY
DSM_PRINT:
        JSR DRAW_AY_STR
        LDA #0
        STA ZP_Y_HI
        RTS

; ============================================================================
; Non-Blocking 16-Bit Stereo Arcade Audio ($A00A / $A00B + CMD 16)
; ============================================================================
SFX_PAD_LEFT:
        ; Heldere "PONG!" op CH0 (Piano FM)
        LDA #$10
        STA IO_INST
        LDA #$D6                ; ~440 Hz A4
        LDY #$01
        LDX #3                  ; 3 frames (60 ms) non-blocking!
        JMP TRIG_SFX_CH0

SFX_PAD_RIGHT:
        ; Hogere "PING!" op CH0 (Piano FM)
        LDA #$10
        STA IO_INST
        LDA #$4C                ; ~587 Hz D5
        LDY #$02
        LDX #3
        JMP TRIG_SFX_CH0

SFX_WALL_BEEP:
        ; Korte muur-stuit op CH0 (262 Hz C4)
        LDA #$10
        STA IO_INST
        LDA #$16
        LDY #$01
        LDX #2                  ; 2 frames (40 ms)
        JMP TRIG_SFX_CH0

SFX_SMASH_HIT:
        ; Krachtige Turbo-Smash akkoord-puls (CH0 Brass + CH3 Snare)!
        LDA #$14
        STA IO_INST
        LDA #$BA
        LDY #$02
        LDX #5
        JSR TRIG_SFX_CH0
        LDA #16
        STA IO_GPU
        LDA #3
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$40
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #250
        STA IO_GPU
        RTS

SFX_POINT_LOST:
        ; Punt gescoord signaal op CH0 (FM Bells)
        LDA #$16
        STA IO_INST
        LDA #$70
        LDY #$01
        LDX #8
        JMP TRIG_SFX_CH0

SFX_START_CHORD:
        LDA #$10
        STA IO_INST
        LDA #$16
        LDY #$02
        LDX #6
        JMP TRIG_SFX_CH0

SFX_VICTORY_FANFARE:
        LDA #$14                ; Brass Fanfare
        STA IO_INST
        LDA #$D6
        LDY #$01
        LDX #6
        JSR TRIG_SFX_CH0
        LDX #8
        JSR WAIT_X_TICKS
        LDA #$4C
        LDY #$02
        LDX #6
        JSR TRIG_SFX_CH0
        LDX #8
        JSR WAIT_X_TICKS
        LDA #$BA
        LDY #$02
        LDX #14
        JMP TRIG_SFX_CH0

TRIG_SFX_CH0:
        STX SFX_TIMER
        PHA
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        PLA
        STA IO_GPU
        STY IO_GPU
        LDA #248
        STA IO_GPU
        RTS

SILENCE_ALL_AUDIO:
        LDX #0
SAA_LP:
        LDA #16
        STA IO_GPU
        STX IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        INX
        CPX #4
        BCC SAA_LP
        RTS

WAIT_X_TICKS:
        LDA IO_TIMER
        CLC
        ADC #2
WXT_LP:
        CMP IO_TIMER
        BNE WXT_LP
        DEX
        BNE WAIT_X_TICKS
        RTS

; ============================================================================
; Afsluiten naar BASIC / Midnight Commander
; ============================================================================
QUIT_TO_BASIC:
        JSR SILENCE_ALL_AUDIO
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

; ============================================================================
; MiniGPU Primitieven (RECT & GTEXT)
; ============================================================================
SEND_CMD_XY:
        STA IO_GPU
        LDA ZP_X_LO
        STA IO_GPU
        LDA ZP_X_HI
        STA IO_GPU
        LDA ZP_Y_LO
        STA IO_GPU
        LDA ZP_Y_HI
        STA IO_GPU
        RTS

DRAW_RECT_ZP:
        LDA #2
        JSR SEND_CMD_XY
        LDA ZP_W_LO
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_H_LO
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_COL
        STA IO_GPU
        RTS

SEND_UI_RECT:
        LDY #10
SUR_LP:
        LDA UI_RECT_TBL,X
        STA IO_GPU
        INX
        DEY
        BNE SUR_LP
        RTS

DRAW_DEC_A2:
        LDY #'0'
DDA2_LP:
        CMP #10
        BCC DDA2_PR
        SEC
        SBC #10
        INY
        BNE DDA2_LP
DDA2_PR:
        PHA
        TYA
        JSR DRAW_CHAR_ADV
        PLA
        CLC
        ADC #'0'
        JMP DRAW_CHAR_ADV

DRAW_TEXT_LIST:
        JSR NEXT_PTR_BYTE
        BNE DTL_GO
        STA ZP_Y_HI
        RTS
DTL_GO:
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
        JMP DRAW_TEXT_LIST

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
        JSR SEND_CMD_XY
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
; Tabellen, Stadion-Layout & Teksten
; ============================================================================
; CPU-batje snelheid per niveau: Makkelijk=3, Normaal=4, Pro=6
CPU_SPEED_TBL:
        .BYTE 3, 4, 6

; 7-Zone Stuithoek Tabel (DY: -4, -3, -1, +1, +2, +3, +4)
BOUNCE_DY_TBL:
        .BYTE (256-4), (256-2), (256-1), 1, 2, 3, 4

ARENA_FRAME_STREAM:
        .BYTE 12, 1
        ; Bovenste Score- & Titelbalk (Y=0..39)
        .BYTE 2, 0,0, 0,0, $80,$02, 40,0, $01
        ; Gouden Stadion Bovenwand (Y=40..43)
        .BYTE 2, 0,0, 40,0, $80,$02, 4,0, $FC
        ; Gouden Stadion Onderwand (Y=249..252)
        .BYTE 2, 0,0, 249,0, $80,$02, 4,0, $FC
        ; Onderste Bedieningspaneel (Y=296..359)
        .BYTE 2, 0,0, (296 & $FF),(296 >> 8), $80,$02, 2,0, $1F
        .BYTE 2, 0,0, (298 & $FF),(298 >> 8), $80,$02, 34,0, $01
        .BYTE 2, 0,0, (332 & $FF),(332 >> 8), $80,$02, 28,0, $00
ARENA_FRAME_STREAM_END:

UI_RECT_TBL:
        ; Offset 0: Wis Modus-tekst in bovenbalk (224, 6, 196, 12, $01)
        .BYTE 2, 224,0, 6,0, 196,0, 12,0, $01
        ; Offset 10: Wis Score Speler 1 (148, 23, 24, 12, $01)
        .BYTE 2, 148,0, 23,0, 24,0, 12,0, $01
        ; Offset 20: Wis Score Speler 2 (484, 23, 24, 12, $01)
        .BYTE 2, (484 & $FF),(484 >> 8), 23,0, 24,0, 12,0, $01
        ; Offset 30: Wis Rally teller (308, 23, 24, 12, $01)
        .BYTE 2, (308 & $FF),(308 >> 8), 23,0, 24,0, 12,0, $01
        ; Offset 40: Wis onderste statusbalk (0, 332, 640, 26, $00)
        .BYTE 2, 0,0, (332 & $FF),(332 >> 8), $80,$02, 26,0, $00

STR_STATIC_HUD:
        .BYTE 12,0, 8,0, $FC, "TWENTE ARCADE PONG DELUXE", 0
        .BYTE (444 & $FF),(444 >> 8), 8,0, $1F, "EERSTE TOT 7 PT!", 0
        .BYTE 44,0, 25,0, $1F, "SPELER 1:", 0
        .BYTE (252 & $FF),(252 >> 8), 25,0, $FF, "RALLY:", 0
        .BYTE (380 & $FF),(380 >> 8), 25,0, $E0, "TEGENSTANDER:", 0
        .BYTE 12,0, (304 & $FF),(304 >> 8), $FC, "[W/S of PIJL] Batje Links   [I/K] Batje Rechts(2P)   [SPATIE] Serveer / Smash!", 0
        .BYTE 12,0, (318 & $FF),(318 >> 8), $FF, "[1/2] 1P/2P Modus  [M] CPU Niveau  [B] 720p Boerderij/Space!  [R] Reset  [ESC]", 0
        .BYTE 0

DIFF_STR_LO:    .BYTE <STR_M_EASY, <STR_M_NORM, <STR_M_PRO
DIFF_STR_HI:    .BYTE >STR_M_EASY, >STR_M_NORM, >STR_M_PRO
STR_M_EASY:     .ASCIIZ "1P VS CPU (1:MAKKELIJK)"
STR_M_NORM:     .ASCIIZ "1P VS CPU (2:NORMAAL)"
STR_M_PRO:      .ASCIIZ "1P VS CPU (3:PRO!)"
STR_MODE_2P:    .ASCIIZ "2-SPELERS DUEL (W/S & I/K)"

STR_MSG_SERVE:  .ASCIIZ "DRUK OP [SPATIE] OM DE BAL TE SERVEREN! ([B] = 720P BOERDERIJ/SPACE)"
STR_MSG_PLAY:   .ASCIIZ "RALLY ACTIEF! DRUK VLAK VOOR HET RAKEN OP [SPATIE] VOOR TURBO-SMASH!"
STR_WIN_P1:     .ASCIIZ "GEFELICITEERD! SPELER 1 WINT DE WEDSTRIJD (7 PT)! DRUK [SPATIE] OF [R]."
STR_WIN_P2:     .ASCIIZ "RECHTER SPELER / CPU WINT DE WEDSTRIJD (7 PT)! DRUK [SPATIE] OF [R]."
