; ============================================================================
; UFO.asm v1.0 - UFO: Enemy Unknown 6502 (X-COM Twente Tactical Defense)
; Geassembleerd voor $8000 (Past in 1 SD-slot van 4 KB, naast MC op $9000!)
;
; Turn-Based Tactical Squad Combat geïnspireerd door MicroProse X-COM (1994):
;   - 16x10 Tactische Battlescape met Fog of War, Boerderij-muren, Bomen & UFO!
;   - 3 X-COM Soldaten (1:CMD.ROB, 2:SGT.JAN, 3:CPL.EVA) met Time Units (TU) & HP
;   - 4 Aliens (SECTOID, FLOATER, MUTON, COMMANDER) + Elerium-115 UFO Reactor!
;   - Vernietigbare Muren & UFO-Romp met Alien Granaten (3x3 explosie!)
;   - "HIDDEN MOVEMENT" Alien AI-beurt met groen plasma-vuur & 16-Bit Stereo FX!
;
; Besturing:
;   [WASD / Pijltjes] : Loop met actieve soldaat (4 TU per vakje, onthult Fog!)
;   [1] [2] [3] [TAB] : Kies X-COM Soldaat 1, 2 of 3
;   [T]               : Wissel van zichtbaar Alien-doelwit (Rood Vizier)
;   [SPATIE]          : Snap Shot (8 TU)  - Snel laser-salvo op doelwit
;   [F]               : Aimed Shot (14 TU)- Precisie-schot met hoge schade
;   [G]               : Alien Granaat (12 TU) - 3x3 Explosie & blaast muren op!
;   [H]               : Medikit (10 TU)   - Genees actieve soldaat (+18 HP)
;   [E] / [ENTER]     : Einde Beurt       - Start "HIDDEN MOVEMENT" Alien-beurt
;   [R]               : Nieuwe UFO Missie / Volgende Sector
;   [ESC] / [Q]       : Afsluiten naar BASIC / Midnight Commander
; ============================================================================

        .ORG $8000

; --- Hardware I/O Registers ---
IO_STATUS       = $A000         ; Bit 0 = char ready, Bit 7 = ESC
IO_TERM         = $A001         ; ASCII karakter
IO_TIMER        = $A003         ; 100 Hz systeemtimer
IO_JOY          = $A004         ; Joypad / Pijltjes
IO_RND          = $A005         ; Hardware LFSR Random byte
IO_MODE         = $A006         ; 0=MODE 1 (640x360 Graphics), 1=MODE 0
IO_INST         = $A00A         ; 16-Bit Stereo Sound Card Instrument
IO_FX           = $A00B         ; 16-Bit Stereo Sound Card FX
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- Werkgeheugen voor 16x10 Map & Fog of War ($3000..$31FF) ---
MAP_TILES       = $3000         ; 160 bytes: 0=Gras, 1=Muur, 2=Boom, 3=UFO-Wand, 4=UFO-Vloer, 5=Elerium-Kern
MAP_FOG         = $3100         ; 160 bytes: 0=Fog of War, 1=Zichtbaar

; --- Zero-Page Variabelen ($50..$8F) ---
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
ZP_X2_LO        = $5A
ZP_X2_HI        = $5B
ZP_Y2_LO        = $5C
ITER_X          = $5D
ITER_Y          = $5E
ITER_IDX        = $5F

CUR_SOL         = $60           ; Actieve X-COM soldaat (0..2)
TARGET_ALN      = $61           ; Geselecteerd Alien doelwit (0..3)
TURN_NUM        = $62           ; Huidige beurt (1..99)
MISSION_SECTOR  = $63           ; Sector (0..2)
GRENADES_LEFT   = $64           ; Aantal Alien-granaten (start op 3)
GAME_STATE      = $65           ; 0=Actief, 1=Gewonnen, 2=Verloren
LAST_JOY        = $66
TEMP_A          = $67
TEMP_B          = $68
TEMP_DX         = $69
TEMP_DY         = $6A
LOG_PTR_LO      = $6B
LOG_PTR_HI      = $6C
LOG_COL         = $6D

; 3 X-COM Soldaten Status ($70..$7E)
SOL_X           = $70           ; 3 bytes (0..15)
SOL_Y           = $73           ; 3 bytes (0..9)
SOL_HP          = $76           ; 3 bytes (0..40, 0=KIA)
SOL_TU          = $79           ; 3 bytes (0..28)
SOL_MAX_TU      = $7C           ; 3 bytes

; 4 Aliens Status ($80..$8F)
ALN_X           = $80           ; 4 bytes (0..15)
ALN_Y           = $84           ; 4 bytes (0..9)
ALN_HP          = $88           ; 4 bytes (0..40, 0=Dood)

BSRAM_EXIT_MC   = $02D8         ; Veilige exit-stub

; ============================================================================
; Hoofdprogramma Start
; ============================================================================
START:
        CLD
        LDA #0
        STA IO_MODE             ; Zet MODE 1 (640x360 Graphics) aan
        STA MISSION_SECTOR
        STA LAST_JOY
        LDA #8
        STA IO_INST
        LDA #7
        STA IO_FX
        JSR INIT_MISSION

; ============================================================================
; Hoofdlus: Toetsenbord & Joypad Afhandeling
; ============================================================================
MAIN_LOOP:
        LDA IO_STATUS
        BPL CHK_JOY
        LDA IO_TERM
        JMP QUIT_TO_BASIC

CHK_JOY:
        LDA IO_JOY
        TAX
        EOR LAST_JOY
        AND IO_JOY
        STX LAST_JOY
        TAY
        AND #$01
        BNE MOVE_UP
        TYA
        AND #$02
        BNE MOVE_DOWN
        TYA
        AND #$04
        BNE MOVE_LEFT
        TYA
        AND #$08
        BNE MOVE_RIGHT
        TYA
        AND #$10
        BNE ACTION_SNAP_SHOT

CHK_KEY:
        LDA IO_STATUS
        AND #$01
        BEQ MAIN_LOOP
        LDA IO_TERM
        CMP #$1B                ; ESC
        BEQ QUIT_JMP
        CMP #$09                ; TAB = Volgende soldaat
        BEQ NEXT_SOLDIER
        CMP #$0D                ; ENTER = Einde Beurt
        BEQ END_TURN_JMP
        CMP #'a'
        BCC UPPER_OK
        CMP #'z'+1
        BCS UPPER_OK
        AND #$DF
UPPER_OK:
        CMP #'Q'
        BEQ QUIT_JMP
        CMP #'W'
        BEQ MOVE_UP
        CMP #'S'
        BEQ MOVE_DOWN
        CMP #'A'
        BEQ MOVE_LEFT
        CMP #'D'
        BEQ MOVE_RIGHT
        CMP #'1'
        BCC NOT_SOL_NUM
        CMP #'3'+1
        BCS NOT_SOL_NUM
        SEC
        SBC #'1'
        JMP SELECT_SOL_A
NOT_SOL_NUM:
        CMP #'T'
        BEQ CYCLE_TARGET_ALIEN
        CMP #' '
        BEQ ACTION_SNAP_SHOT
        CMP #'F'
        BEQ ACTION_AIMED_SHOT
        CMP #'G'
        BEQ ACTION_GRENADE
        CMP #'H'
        BEQ ACTION_MEDIKIT
        CMP #'E'
        BEQ END_TURN_JMP
        CMP #'R'
        BNE MAIN_LOOP
        INC MISSION_SECTOR
        LDA MISSION_SECTOR
        CMP #3
        BCC R_SEC_OK
        LDA #0
        STA MISSION_SECTOR
R_SEC_OK:
        JSR INIT_MISSION
        JMP MAIN_LOOP

QUIT_JMP:
        JMP QUIT_TO_BASIC
END_TURN_JMP:
        JMP ACTION_END_TURN

; ============================================================================
; Initialiseer UFO Missie, 16x10 Map, Fog of War, 3 Soldaten & 4 Aliens
; ============================================================================
INIT_MISSION:
        LDA #0
        STA CUR_SOL
        STA TARGET_ALN
        STA GAME_STATE
        LDA #1
        STA TURN_NUM
        LDA #3
        STA GRENADES_LEFT

        ; Pak 80 bytes MAP_PACKED uit naar 160 tegels in MAP_TILES en wis MAP_FOG
        LDX #0
        LDY #0
IM_CP:
        LDA #0
        STA MAP_FOG,Y
        STA MAP_FOG+1,Y
        LDA MAP_PACKED,X
        PHA
        LSR A
        LSR A
        LSR A
        LSR A
        STA MAP_TILES,Y
        INY
        PLA
        AND #$0F
        STA MAP_TILES,Y
        INY
        INX
        CPX #80
        BCC IM_CP

        ; Zet de 3 X-COM Soldaten klaar bij de Skyranger Dropzone
        LDX #2
IM_SOL:
        LDA INIT_SOL_X,X
        STA SOL_X,X
        LDA INIT_SOL_Y,X
        STA SOL_Y,X
        LDA INIT_SOL_HP,X
        STA SOL_HP,X
        LDA INIT_SOL_TU,X
        STA SOL_TU,X
        STA SOL_MAX_TU,X
        DEX
        BPL IM_SOL

        ; Zet de 4 Aliens klaar (met sector-variatie)
        LDX #3
IM_ALN:
        LDA INIT_ALN_X,X
        STA ALN_X,X
        LDA INIT_ALN_Y,X
        CLC
        ADC MISSION_SECTOR
        CMP #8
        BCC IM_AY_OK
        SBC #3
IM_AY_OK:
        STA ALN_Y,X
        LDA INIT_ALN_HP,X
        STA ALN_HP,X
        DEX
        BPL IM_ALN

        JSR UPDATE_FOG_OF_WAR
        JSR AUTO_PICK_TARGET
        LDX #0
        JSR SET_LOG_X
        JSR DRAW_FULL_SCREEN
        JMP SFX_XCOM_CHORD

; ============================================================================
; Soldaat Selectie ([1]..[3] of [TAB])
; ============================================================================
NEXT_SOLDIER:
        LDX CUR_SOL
        INX
        CPX #3
        BCC NS_TRY
        LDX #0
NS_TRY:
        TXA
SELECT_SOL_A:
        TAX
        LDA SOL_HP,X
        BNE SSA_SET
        JSR FIND_LIVING_SOLDIER
        BEQ SSA_DONE
        TYA
        TAX
SSA_SET:
        STX CUR_SOL
        JSR SFX_STEP
        JSR REDRAW_MAP_AND_HUD
SSA_DONE:
        JMP MAIN_LOOP

; ============================================================================
; Loop met Actieve Soldaat (4 TU per stap)
; ============================================================================
MOVE_UP:
        LDA #0
        LDY #$FF
        JMP TRY_MOVE_SOL
MOVE_DOWN:
        LDA #0
        LDY #1
        JMP TRY_MOVE_SOL
MOVE_LEFT:
        LDA #$FF
        LDY #0
        JMP TRY_MOVE_SOL
MOVE_RIGHT:
        LDA #1
        LDY #0

TRY_MOVE_SOL:
        STA TEMP_DX
        STY TEMP_DY
        LDA GAME_STATE
        BNE SSA_DONE
        LDX CUR_SOL
        LDA SOL_HP,X
        BEQ NEXT_SOLDIER
        LDA SOL_TU,X
        CMP #4
        BCS TMS_COORDS
        JMP LOG_NO_TU_ERR

TMS_COORDS:
        LDA SOL_X,X
        CLC
        ADC TEMP_DX
        CMP #16
        BCS TMS_BLOCKED
        STA TEMP_A              ; Nieuwe X
        LDA SOL_Y,X
        CLC
        ADC TEMP_DY
        CMP #10
        BCS TMS_BLOCKED
        STA TEMP_B              ; Nieuwe Y

        ; Check of een andere soldaat hier al staat
        LDY #2
TMS_CHK_SOL:
        LDA SOL_HP,Y
        BEQ TMS_CS_NXT
        LDA SOL_X,Y
        CMP TEMP_A
        BNE TMS_CS_NXT
        LDA SOL_Y,Y
        CMP TEMP_B
        BEQ TMS_BLOCKED
TMS_CS_NXT:
        DEY
        BPL TMS_CHK_SOL

        ; Check of er een levende Alien op dit vakje staat -> Snap Shot!
        LDY #3
TMS_CHK_ALN:
        LDA ALN_HP,Y
        BEQ TMS_CA_NXT
        LDA ALN_X,Y
        CMP TEMP_A
        BNE TMS_CA_NXT
        LDA ALN_Y,Y
        CMP TEMP_B
        BNE TMS_CA_NXT
        STY TARGET_ALN
        JMP ACTION_SNAP_SHOT
TMS_CA_NXT:
        DEY
        BPL TMS_CHK_ALN

        ; Check Terrein-Tegel op (TEMP_A, TEMP_B)
        JSR CHK_TILE_BLOCKED
        BCS TMS_BLOCKED

        ; Tegel is vrij (0=Gras, 4=UFO-Vloer, 5=Elerium-115 Kern)!
        LDX CUR_SOL
        LDA TEMP_A
        STA SOL_X,X
        LDA TEMP_B
        STA SOL_Y,X
        LDA SOL_TU,X
        SEC
        SBC #4
        STA SOL_TU,X

        ; Check of de soldaat de Elerium-115 UFO Kern (tegel 5) heeft veroverd!
        LDA MAP_TILES,Y
        CMP #5
        BNE TMS_NORMAL_STEP
        JMP VICTORY_CORE_CAPTURED

TMS_NORMAL_STEP:
        JSR SFX_STEP
        JSR UPDATE_FOG_OF_WAR
        JSR AUTO_PICK_TARGET
        JSR REDRAW_MAP_AND_HUD
        JMP MAIN_LOOP

TMS_BLOCKED:
        JSR SFX_ERROR
        JMP MAIN_LOOP

LOG_NO_TU_ERR:
        LDX #1
        JSR SHOW_LOG_X
        JMP TMS_BLOCKED

; ============================================================================
; Wissel Zichtbaar Alien Doelwit ([T])
; ============================================================================
CYCLE_TARGET_ALIEN:
        LDX TARGET_ALN
        LDY #4
CTA_LP:
        INX
        CPX #4
        BCC CTA_OK
        LDX #0
CTA_OK:
        JSR IS_ALIEN_X_VISIBLE
        BNE CTA_FOUND
        DEY
        BNE CTA_LP
        JMP MAIN_LOOP
CTA_FOUND:
        STX TARGET_ALN
        JSR SFX_STEP
        JSR REDRAW_MAP_AND_HUD
        JMP MAIN_LOOP

AUTO_PICK_TARGET:
        LDX TARGET_ALN
        JSR IS_ALIEN_X_VISIBLE
        BNE APT_RTS
        LDX #0
APT_LP:
        JSR IS_ALIEN_X_VISIBLE
        BNE APT_SET
        INX
        CPX #4
        BCC APT_LP
        RTS
APT_SET:
        STX TARGET_ALN
APT_RTS:
        RTS

; Geeft Z=0 (A=1) als Alien X leeft én zichtbaar is in MAP_FOG
IS_ALIEN_X_VISIBLE:
        LDA ALN_HP,X
        BEQ IAXV_NO
        LDA ALN_Y,X
        ASL A
        ASL A
        ASL A
        ASL A
        ORA ALN_X,X
        TAY
        LDA MAP_FOG,Y
IAXV_NO:
        RTS

; ============================================================================
; Snap Shot (8 TU, 14..21 schade) & Aimed Shot (14 TU, 23..30 schade)
; ============================================================================
ACTION_SNAP_SHOT:
        LDA #8                  ; 8 TU kosten
        STA TEMP_A
        LDA #14                 ; Basis schade
        BNE EXEC_LASER_SHOT

ACTION_AIMED_SHOT:
        LDA #14                 ; 14 TU kosten
        STA TEMP_A
        LDA #23                 ; Precisie schade

EXEC_LASER_SHOT:
        STA TEMP_B
        LDA GAME_STATE
        BNE ELS_DONE
        JSR AUTO_PICK_TARGET
        LDX TARGET_ALN
        JSR IS_ALIEN_X_VISIBLE
        BNE ELS_CHK_TU
        LDX #2
        JSR SHOW_LOG_X
        JMP TMS_BLOCKED

ELS_CHK_TU:
        LDX CUR_SOL
        LDA SOL_HP,X
        BEQ NEXT_SOLDIER
        LDA SOL_TU,X
        CMP TEMP_A
        BCC LOG_NO_TU_ERR
        SEC
        SBC TEMP_A
        STA SOL_TU,X

        ; Teken Laserstraal van actieve soldaat naar TARGET_ALN!
        LDX TARGET_ALN
        LDA ALN_X,X
        LDY ALN_Y,X
        JSR SET_TILE_CENTER_AY
        JSR COPY_XY_TO_XY2

        LDX CUR_SOL
        LDA SOL_X,X
        LDY SOL_Y,X
        JSR SET_TILE_CENTER_AY

        LDA #$FC                ; Goudgele X-COM Laserstraal
        STA ZP_COL
        JSR DRAW_LINE_ZP
        JSR SFX_LASER_FIRE

        ; Bereken trefferkans (Aimed Shot mist niet; Snap Shot ~82%)
        LDA TEMP_A
        CMP #14
        BEQ ELS_HIT
        LDA IO_RND
        CMP #46
        BCS ELS_HIT

        ; Misgeschoten!
        JSR REDRAW_MAP_AND_HUD
        LDX #3
        JSR SHOW_LOG_X
ELS_DONE:
        JMP MAIN_LOOP

ELS_HIT:
        ; Treffer flits op Alien (op ZP_X2/Y2)!
        LDX TARGET_ALN
        LDA ALN_X,X
        LDY ALN_Y,X
        JSR SET_TILE_CENTER_AY
        LDA #9
        LDY #$E0
        JSR DRAW_DISK_AY

        ; Trek schade af van ALN_HP
        LDA IO_RND
        AND #7
        CLC
        ADC TEMP_B
        STA TEMP_B
        LDX TARGET_ALN
        LDA ALN_HP,X
        SEC
        SBC TEMP_B
        BCS ELS_NOT_ZERO
        LDA #0
ELS_NOT_ZERO:
        STA ALN_HP,X
        BNE ELS_STILL_ALIVE

        ; Alien uitgeschakeld!
        JSR SFX_ALIEN_SCREAM
        JSR AUTO_PICK_TARGET
        JSR CHECK_ALL_ALIENS_DEAD
        JSR REDRAW_MAP_AND_HUD
        LDA GAME_STATE
        BNE ELS_DONE
        LDX #5
        BNE ELS_SHOW_LOG

ELS_STILL_ALIVE:
        JSR REDRAW_MAP_AND_HUD
        LDX #4
ELS_SHOW_LOG:
        JSR SHOW_LOG_X
        JMP MAIN_LOOP

; ============================================================================
; Alien Granaat ([G], 12 TU) - 3x3 Explosie & Vernietigt Muren/UFO-Wand!
; ============================================================================
ACTION_GRENADE:
        LDA GAME_STATE
        BNE ELS_DONE
        LDA GRENADES_LEFT
        BEQ TMS_BLOCKED
        LDX CUR_SOL
        LDA SOL_HP,X
        BEQ NEXT_SOLDIER
        LDA SOL_TU,X
        CMP #12
        BCS AG_THROW
        JMP LOG_NO_TU_ERR

AG_THROW:
        SEC
        SBC #12
        STA SOL_TU,X
        DEC GRENADES_LEFT

        ; Als er een zichtbare alien is, gooi naar TARGET_ALN; anders 2 vakjes rechts van soldaat!
        JSR AUTO_PICK_TARGET
        LDX TARGET_ALN
        JSR IS_ALIEN_X_VISIBLE
        BEQ AG_AHEAD
        LDA ALN_X,X
        STA TEMP_A
        LDA ALN_Y,X
        STA TEMP_B
        JMP AG_BOOM

AG_AHEAD:
        LDX CUR_SOL
        LDA SOL_X,X
        CLC
        ADC #2
        CMP #15
        BCC AG_AX_OK
        LDA #14
AG_AX_OK:
        STA TEMP_A
        LDA SOL_Y,X
        STA TEMP_B

AG_BOOM:
        ; Teken grote 3x3 Vuurbal op (TEMP_A, TEMP_B)
        LDA TEMP_A
        LDY TEMP_B
        JSR SET_TILE_CENTER_AY
        LDA #30
        LDY #$E0
        JSR DRAW_DISK_AY
        LDA #16
        LDY #$FC
        JSR DRAW_DISK_AY
        JSR SFX_EXPLOSION

        ; Blaas Muren (1), Bomen (2) en UFO-Romp (3) op in een 3x3 gebied rond (TEMP_A, TEMP_B)!
        LDA #2
        STA TEMP_DX
        LDY #0
AG_MAP_LP:
        JSR CHK_TILE_RADIUS
        BCS AG_MAP_NXT
        LDA #1
        STA MAP_FOG,Y
        LDA MAP_TILES,Y
        CMP #1
        BEQ AG_DESTROY_T
        CMP #2
        BEQ AG_DESTROY_T
        CMP #3
        BNE AG_MAP_NXT
        LDA #4                  ; UFO-wand wordt open UFO-vloer (bres!)
        BNE AG_SET_T
AG_DESTROY_T:
        LDA #0                  ; Muur/boom wordt open gras
AG_SET_T:
        STA MAP_TILES,Y
AG_MAP_NXT:
        INY
        CPY #160
        BCC AG_MAP_LP

        ; Breng 24 schade toe aan alle Aliens binnen 3x3 van (TEMP_A, TEMP_B)
        LDX #3
AG_ALN_LP:
        LDA ALN_HP,X
        BEQ AG_ALN_NXT
        LDA ALN_X,X
        JSR ABS_DIFF_TEMPA
        CMP #2
        BCS AG_ALN_NXT
        LDA ALN_Y,X
        JSR ABS_DIFF_TEMPB
        CMP #2
        BCS AG_ALN_NXT
        LDA ALN_HP,X
        SEC
        SBC #24
        BCS AG_AHP_OK
        LDA #0
AG_AHP_OK:
        STA ALN_HP,X
AG_ALN_NXT:
        DEX
        BPL AG_ALN_LP

        JSR UPDATE_FOG_OF_WAR
        JSR AUTO_PICK_TARGET
        JSR CHECK_ALL_ALIENS_DEAD
        JSR REDRAW_MAP_AND_HUD
        LDA GAME_STATE
        BNE AG_END
        LDX #6
        JSR SHOW_LOG_X
AG_END:
        JMP MAIN_LOOP

; ============================================================================
; Medikit ([H], 10 TU -> +18 HP voor actieve soldaat)
; ============================================================================
ACTION_MEDIKIT:
        LDX CUR_SOL
        LDA SOL_HP,X
        BEQ AG_END
        LDA SOL_TU,X
        CMP #10
        BCS AM_OK
        JMP LOG_NO_TU_ERR
AM_OK:
        SEC
        SBC #10
        STA SOL_TU,X
        LDA SOL_HP,X
        CLC
        ADC #18
        CMP #40
        BCC AM_HP_OK
        LDA #40
AM_HP_OK:
        STA SOL_HP,X
        JSR SFX_XCOM_CHORD
        JSR DRAW_HUD_PANEL
        LDX #7
        JSR SHOW_LOG_X
        JMP MAIN_LOOP

; ============================================================================
; Einde Beurt ([E] / [ENTER]) -> "HIDDEN MOVEMENT" Alien AI Beurt!
; ============================================================================
ACTION_END_TURN:
        LDA GAME_STATE
        BNE AG_END

        ; Toon iconische "HIDDEN MOVEMENT - ALIEN ACTIVITY" balk midden op de kaart!
        LDX #20
        JSR SEND_RECT_10
        LDX #128
        LDA #0
        LDY #148
        JSR SET_HUD_XY
        LDA #$FC
        STA ZP_FG_COL
        LDA #<STR_HIDDEN_MOV
        LDY #>STR_HIDDEN_MOV
        JSR DRAW_AY_STR
        JSR SFX_ALIEN_TURN

        ; Laat elke levende Alien bewegen richting soldaat & vuren!
        LDX #0
AET_ALN_LP:
        STX ITER_IDX
        LDA ALN_HP,X
        BEQ AET_ALN_NXT
        JSR FIND_LIVING_SOLDIER
        BEQ AET_CHECK_LOSS

        ; Beweeg Alien X 1 stap horizontaal richting soldaat Y als dat vakje vrij is
        LDA SOL_X,Y
        STA TEMP_A
        LDA ALN_X,X
        JSR STEP_TOWARD_TEMPA
        STA TEMP_A
        LDA ALN_Y,X
        STA TEMP_B
        JSR CHK_TILE_BLOCKED
        BCS AET_TRY_Y
        LDX ITER_IDX
        LDA TEMP_A
        STA ALN_X,X

AET_TRY_Y:
        JSR FIND_LIVING_SOLDIER
        LDX ITER_IDX
        LDA SOL_Y,Y
        STA TEMP_A
        LDA ALN_Y,X
        JSR STEP_TOWARD_TEMPA
        STA TEMP_B
        LDA ALN_X,X
        STA TEMP_A
        JSR CHK_TILE_BLOCKED
        BCS AET_CHK_FIRE
        LDX ITER_IDX
        LDA TEMP_B
        STA ALN_Y,X

AET_CHK_FIRE:
        ; Als Alien X zichtbaar is in MAP_FOG, vuurt hij een groene Plasma-straal!
        LDX ITER_IDX
        JSR IS_ALIEN_X_VISIBLE
        BEQ AET_ALN_NXT

        JSR DRAW_BATTLESCAPE
        JSR FIND_LIVING_SOLDIER
        STY TEMP_A
        LDA SOL_X,Y
        pha
        LDA SOL_Y,Y
        TAY
        PLA
        JSR SET_TILE_CENTER_AY
        JSR COPY_XY_TO_XY2

        LDX ITER_IDX
        LDA ALN_X,X
        LDY ALN_Y,X
        JSR SET_TILE_CENTER_AY

        LDA #$1C                ; Felgroene Alien Plasma Bolt!
        STA ZP_COL
        JSR DRAW_LINE_ZP
        JSR SFX_PLASMA_BOLT

        ; Plasma schade (7..14 HP) op soldaat TEMP_A
        LDA IO_RND
        AND #7
        CLC
        ADC #7
        STA TEMP_B
        LDY TEMP_A
        LDA SOL_HP,Y
        SEC
        SBC TEMP_B
        BCS AET_SHP_OK
        LDA #0
AET_SHP_OK:
        STA SOL_HP,Y

AET_ALN_NXT:
        LDX ITER_IDX
        INX
        CPX #4
        BCC AET_ALN_LP

        ; Vul Time Units (TU) van alle overlevende X-COM soldaten weer aan!
        INC TURN_NUM
        LDX #2
AET_REFILL:
        LDA SOL_HP,X
        BEQ AET_RF_NXT
        LDA SOL_MAX_TU,X
        STA SOL_TU,X
AET_RF_NXT:
        DEX
        BPL AET_REFILL

AET_CHECK_LOSS:
        JSR FIND_LIVING_SOLDIER
        BNE AET_STILL_OK
        LDA #2
        STA GAME_STATE
        LDX #11
        JSR SET_LOG_X
        JSR DRAW_FULL_SCREEN
        JSR SFX_ALIEN_SCREAM
        JMP MAIN_LOOP

AET_STILL_OK:
        STY CUR_SOL
        JSR UPDATE_FOG_OF_WAR
        JSR AUTO_PICK_TARGET
        LDX #8
        JSR SET_LOG_X
        JSR DRAW_FULL_SCREEN
        JMP MAIN_LOOP

STEP_TOWARD_TEMPA:
        CMP TEMP_A
        BEQ STT_RTS
        BCS STT_DEC
        ADC #1
        RTS
STT_DEC:
        SBC #1
STT_RTS:
        RTS

; Geeft Y = index van levende soldaat (bij voorkeur CUR_SOL), Z=1 als iedereen KIA is
FIND_LIVING_SOLDIER:
        LDY CUR_SOL
        LDA SOL_HP,Y
        BNE FLS_RTS
        LDY #0
FLS_LP:
        LDA SOL_HP,Y
        BNE FLS_RTS
        INY
        CPY #3
        BCC FLS_LP
        LDA #0
FLS_RTS:
        RTS

; Geeft Y = (TEMP_B << 4) | TEMP_A, A = MAP_TILES,Y, en C=1 als geblokkeerd (tegel 1, 2 of 3)
CHK_TILE_BLOCKED:
        LDA TEMP_B
        ASL A
        ASL A
        ASL A
        ASL A
        ORA TEMP_A
        TAY
        LDA MAP_TILES,Y
        BEQ CTB_FREE
        CMP #4
        BCC CTB_BLK
CTB_FREE:
        CLC
        RTS
CTB_BLK:
        SEC
        RTS

; ============================================================================
; Overwinning Checks (Alle Aliens uitgeschakeld of Elerium-115 UFO Kern veroverd!)
; ============================================================================
CHECK_ALL_ALIENS_DEAD:
        LDA ALN_HP
        ORA ALN_HP+1
        ORA ALN_HP+2
        ORA ALN_HP+3
        BNE CAAD_RTS
        LDA #1
        STA GAME_STATE
        LDX #9
        JSR SET_LOG_X
        JSR DRAW_TOP_BAR
        JMP SFX_VICTORY
CAAD_RTS:
        RTS

VICTORY_CORE_CAPTURED:
        LDA #1
        STA GAME_STATE
        LDX #0
        TXA
        SEC
        ROL A                   ; A = 1
VCC_REV:
        STA MAP_FOG,X
        INX
        CPX #160
        BCC VCC_REV
        LDX #10
        JSR SET_LOG_X
        JSR DRAW_FULL_SCREEN
        JSR SFX_VICTORY
        JMP MAIN_LOOP

; ============================================================================
; Update Fog of War & Tegel-Afstand Hulpfuncties
; ============================================================================
UPDATE_FOG_OF_WAR:
        LDA #5                  ; Zichtstraal rond elke levende soldaat (onthult muren & erf!)
        STA TEMP_DX
        LDX #2
UFW_SOL_LP:
        STX ITER_IDX
        LDA SOL_HP,X
        BEQ UFW_NEXT_SOL
        LDA SOL_X,X
        STA TEMP_A
        LDA SOL_Y,X
        STA TEMP_B
        LDY #0
UFW_TILE_LP:
        JSR CHK_TILE_RADIUS
        BCS UFW_T_NXT
        LDA #1
        STA MAP_FOG,Y
UFW_T_NXT:
        INY
        CPY #160
        BCC UFW_TILE_LP
UFW_NEXT_SOL:
        LDX ITER_IDX
        DEX
        BPL UFW_SOL_LP
        RTS

; Controleert of tegel Y (0..159) binnen TEMP_DX van (TEMP_A, TEMP_B) ligt (C=0 als binnen)
CHK_TILE_RADIUS:
        TYA
        AND #$0F
        JSR ABS_DIFF_TEMPA
        CMP TEMP_DX
        BCS CTR_OUT
        TYA
        LSR A
        LSR A
        LSR A
        LSR A
        JSR ABS_DIFF_TEMPB
        CMP TEMP_DX
CTR_OUT:
        RTS

ABS_DIFF_TEMPA:
        SEC
        SBC TEMP_A
        BPL ADT_RTS
        EOR #$FF
        ADC #1
ADT_RTS:
        RTS

ABS_DIFF_TEMPB:
        SEC
        SBC TEMP_B
        BPL ADT_RTS
        EOR #$FF
        ADC #1
        RTS

; ============================================================================
; Grafische Rendering: Scherm, 16x10 Tactische Kaart, Soldaten, Aliens & HUD
; ============================================================================
DRAW_FULL_SCREEN:
        LDX #0
DFS_STREAM:
        LDA GUI_FRAME_STREAM,X
        STA IO_GPU
        INX
        CPX #(GUI_FRAME_STREAM_END - GUI_FRAME_STREAM)
        BCC DFS_STREAM

        LDA #<STR_STATIC_LABELS
        STA ZP_PTR_LO
        LDA #>STR_STATIC_LABELS
        STA ZP_PTR_HI
        JSR DRAW_TEXT_LIST
        JSR DRAW_TOP_BAR
        JSR REDRAW_MAP_AND_HUD
        JMP DRAW_LOG_BAR

REDRAW_MAP_AND_HUD:
        JSR DRAW_BATTLESCAPE
        JMP DRAW_HUD_PANEL

DRAW_TOP_BAR:
        LDX #0
        JSR SEND_RECT_10
        LDX #<460
        LDA #>460
        LDY #7
        JSR SET_HUD_XY
        LDA #$FC
        STA ZP_FG_COL
        LDA TURN_NUM
        JSR DRAW_DEC_A2

        LDY #0
        LDX #3
DTB_CNT:
        LDA ALN_HP,X
        BEQ DTB_CN
        INY
DTB_CN: DEX
        BPL DTB_CNT
        LDA #<556
        STA ZP_X_LO
        LDA #>556
        STA ZP_X_HI
        LDA #$1C
        STA ZP_FG_COL
        TYA
        CLC
        ADC #'0'
        JMP DRAW_CHAR_ADV

; ============================================================================
; Teken de 16x10 Tactische Battlescape Tegels + 3 Soldaten + 4 Aliens
; ============================================================================
DRAW_BATTLESCAPE:
        LDY #0
        STY ITER_Y
DB_ROW_LP:
        LDX #0
        STX ITER_X
DB_COL_LP:
        LDX ITER_X
        LDA TILE_X_LO,X
        STA ZP_X_LO
        STA TEMP_A
        LDA TILE_X_HI,X
        STA ZP_X_HI
        STA TEMP_B
        LDY ITER_Y
        LDA TILE_Y_TBL,Y
        STA ZP_Y_LO
        STA TEMP_DY

        ; Bereken map-index X = (ITER_Y << 4) | ITER_X
        TYA
        ASL A
        ASL A
        ASL A
        ASL A
        ORA ITER_X
        TAX

        LDA #27
        STA ZP_W_LO
        LDA #24
        STA ZP_H_LO

        LDA MAP_FOG,X
        BNE DB_VISIBLE
        LDA #$02                ; Fog of War tegel
        STA ZP_COL
        JSR DRAW_RECT_ZP
        JMP DB_NEXT_TILE

DB_VISIBLE:
        LDY MAP_TILES,X
        LDA TILE_BG_COL,Y
        STA ZP_COL
        STY TEMP_DX
        JSR DRAW_RECT_ZP

        LDA TEMP_DX
        BEQ DB_T_GRASS
        CMP #1
        BEQ DB_T_WALL
        CMP #2
        BEQ DB_T_TREE
        CMP #3
        BEQ DB_T_UFO_HULL
        CMP #5
        BNE DB_NEXT_TILE

        ; Tegel 5: Gloeiende Elerium-115 UFO Reactor!
        LDX ITER_X
        TXA
        LDY ITER_Y
        JSR SET_TILE_CENTER_AY
        LDA #9
        LDY #$E0
        JSR DRAW_DISK_AY
        LDA #5
        LDY #$FC
        JSR DRAW_DISK_AY
        JMP DB_NEXT_TILE

DB_T_TREE:
        LDX ITER_X
        TXA
        LDY ITER_Y
        JSR SET_TILE_CENTER_AY
        LDA #8
        LDY #$1C
        JSR DRAW_DISK_AY
        JMP DB_NEXT_TILE

DB_T_GRASS:
        LDX #0
        BEQ DB_DO_BOX
DB_T_WALL:
        LDX #5
        BNE DB_DO_BOX
DB_T_UFO_HULL:
        LDX #10
DB_DO_BOX:
        JSR DRAW_UNIT_BOX

DB_NEXT_TILE:
        INC ITER_X
        LDA ITER_X
        CMP #16
        BCC DB_COL_LP
        INC ITER_Y
        LDA ITER_Y
        CMP #10
        BCC DB_ROW_LP

; --- Teken de 3 X-COM Soldaten ---
        LDX #0
DB_SOL_LP:
        STX ITER_IDX
        LDA SOL_HP,X
        BEQ DB_SOL_NXT
        LDY SOL_X,X
        LDA TILE_X_LO,Y
        STA TEMP_A
        LDA TILE_X_HI,Y
        STA TEMP_B
        LDY SOL_Y,X
        LDA TILE_Y_TBL,Y
        STA TEMP_DY

        CPX CUR_SOL
        BNE DB_SOL_BODY
        LDX #15                 ; Gouden selectie-rand boven + onder
        JSR DRAW_UNIT_BOX
        JSR DRAW_UNIT_BOX
DB_SOL_BODY:
        LDX #25                 ; Blauw X-COM pantser + Gouden vizier
        JSR DRAW_UNIT_BOX
        JSR DRAW_UNIT_BOX

        ; Soldaat nummer (1..3)
        LDX #35
        JSR SET_UNIT_OFFSET
        LDA #$FF
        STA ZP_FG_COL
        LDA ITER_IDX
        CLC
        ADC #'1'
        JSR DRAW_CHAR_ADV
DB_SOL_NXT:
        LDX ITER_IDX
        INX
        CPX #3
        BCC DB_SOL_LP

; --- Teken de 4 Aliens (alleen als ze leven én in zichtbaar gebied staan!) ---
        LDX #0
DB_ALN_LP:
        STX ITER_IDX
        JSR IS_ALIEN_X_VISIBLE
        BEQ DB_ALN_NXT
        LDY ALN_X,X
        LDA TILE_X_LO,Y
        STA TEMP_A
        LDA TILE_X_HI,Y
        STA TEMP_B
        LDY ALN_Y,X
        LDA TILE_Y_TBL,Y
        STA TEMP_DY

        CPX TARGET_ALN
        BNE DB_ALN_BODY
        LDX #37                 ; Rood doelwit-vizier boven + onder
        JSR DRAW_UNIT_BOX
        JSR DRAW_UNIT_BOX
DB_ALN_BODY:
        LDX #47                 ; Alien lichaam
        JSR DRAW_UNIT_BOX_ALN
        JSR DRAW_UNIT_BOX       ; Linker oog
        JSR DRAW_UNIT_BOX       ; Rechter oog
DB_ALN_NXT:
        LDX ITER_IDX
        INX
        CPX #4
        BCC DB_ALN_LP
        RTS

; Hulpfunctie: zet ZP_X/Y op (TEMP_A/B + tbl[X], TEMP_DY + tbl[X+1]) en teken box
DRAW_UNIT_BOX_ALN:
        JSR SET_UNIT_OFFSET
        JSR LOAD_BOX_WH
        LDY ITER_IDX
        LDA ALN_COL_TBL,Y
        STA ZP_COL
        INX
        JMP DRAW_RECT_ZP

DRAW_UNIT_BOX:
        JSR SET_UNIT_OFFSET
        JSR LOAD_BOX_WH
        LDA UNIT_BOX_TBL,X
        STA ZP_COL
        INX
        JMP DRAW_RECT_ZP

SET_UNIT_OFFSET:
        LDA TEMP_A
        CLC
        ADC UNIT_BOX_TBL,X
        STA ZP_X_LO
        LDA TEMP_B
        ADC #0
        STA ZP_X_HI
        LDA TEMP_DY
        CLC
        ADC UNIT_BOX_TBL+1,X
        STA ZP_Y_LO
        INX
        INX
        RTS

LOAD_BOX_WH:
        LDA UNIT_BOX_TBL,X
        STA ZP_W_LO
        LDA UNIT_BOX_TBL+1,X
        STA ZP_H_LO
        INX
        INX
        RTS

; ============================================================================
; Rechter X-COM Tactical HUD Paneel (X=462..634, Y=26..285)
; ============================================================================
DRAW_HUD_PANEL:
        LDX #10
        JSR SEND_RECT_10

        ; 1. Actieve Soldaat Naam op X=472, Y=52
        LDY #52
        LDA #$FC
        JSR SET_HUD_472
        LDX CUR_SOL
        LDA SOL_NAME_LO,X
        LDY SOL_NAME_HI,X
        JSR DRAW_AY_STR

        ; 2. Time Units (TU) op X=512, Y=74
        LDY #74
        LDA #$1C
        JSR SET_HUD_512
        LDX CUR_SOL
        LDA SOL_TU,X
        JSR DRAW_DEC_A2

        ; 3. Health (HP) op X=512, Y=94
        LDY #94
        LDA #$E0
        JSR SET_HUD_512
        LDX CUR_SOL
        LDA SOL_HP,X
        JSR DRAW_DEC_A2

        ; 4. Granaten over op X=512, Y=114
        LDY #114
        LDA #$FC
        JSR SET_HUD_512
        LDA GRENADES_LEFT
        CLC
        ADC #'0'
        JSR DRAW_CHAR_ADV

        ; 5. Alien Doelwit op X=472, Y=164
        LDY #164
        LDA #$92
        JSR SET_HUD_472
        LDX TARGET_ALN
        JSR IS_ALIEN_X_VISIBLE
        BEQ DHP_NO_TARGET

        LDA #$E0
        STA ZP_FG_COL
        LDX TARGET_ALN
        LDA ALN_NAME_LO,X
        LDY ALN_NAME_HI,X
        JSR DRAW_AY_STR

        ; Alien HP op X=512, Y=182
        LDY #182
        LDA #$FC
        JSR SET_HUD_512
        LDX TARGET_ALN
        LDA ALN_HP,X
        JSR DRAW_DEC_A2
        JMP DHP_ROSTER_START

DHP_NO_TARGET:
        LDA #<STR_NO_ALIEN
        LDY #>STR_NO_ALIEN
        JSR DRAW_AY_STR

DHP_ROSTER_START:
        ; 6. Squad Overzicht (3 soldaten TU op Y=226, 244, 262)
        LDX #0
DHP_R_LP:
        STX ITER_IDX
        LDY SQUAD_Y_TBL,X
        LDA #$FF
        CPX CUR_SOL
        BNE DHP_R_COL
        LDA #$FC
DHP_R_COL:
        JSR SET_HUD_472
        LDX ITER_IDX
        LDA SOL_NAME_LO,X
        LDY SOL_NAME_HI,X
        JSR DRAW_AY_STR

        LDA #<584
        STA ZP_X_LO
        LDA #>584
        STA ZP_X_HI
        LDX ITER_IDX
        LDA SOL_HP,X
        BEQ DHP_R_KIA
        LDA #$1C
        STA ZP_FG_COL
        LDA SOL_TU,X
        JSR DRAW_DEC_A2
        JMP DHP_R_NXT
DHP_R_KIA:
        LDA #$E0
        STA ZP_FG_COL
        LDA #'X'
        JSR DRAW_CHAR_ADV
DHP_R_NXT:
        LDX ITER_IDX
        INX
        CPX #3
        BCC DHP_R_LP
        RTS

SET_HUD_472:
        STA ZP_FG_COL
        LDX #<472
        LDA #>472
        BNE SET_HUD_XY
SET_HUD_512:
        STA ZP_FG_COL
        LDX #<512
        LDA #>512
SET_HUD_XY:
        STX ZP_X_LO
        STA ZP_X_HI
        STY ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        RTS

; ============================================================================
; Onderste Status & Gevechtslog Balk (Y=338..359)
; ============================================================================
SET_LOG_X:
        LDA LOG_PTR_LO_TBL,X
        STA LOG_PTR_LO
        LDA LOG_PTR_HI_TBL,X
        STA LOG_PTR_HI
        LDA LOG_COL_TBL,X
        STA LOG_COL
        RTS

SHOW_LOG_X:
        JSR SET_LOG_X
DRAW_LOG_BAR:
        LDX #30
        JSR SEND_RECT_10
        LDA #12
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #(345 & $FF)
        STA ZP_Y_LO
        LDA #(345 >> 8)
        STA ZP_Y_HI
        LDA LOG_COL
        STA ZP_FG_COL
        LDA LOG_PTR_LO
        LDY LOG_PTR_HI
        JSR DRAW_AY_STR
        LDA #0
        STA ZP_Y_HI
        RTS

; ============================================================================
; 16-Bit Stereo X-COM Sound Effects ($A00A / $A00B + CMD 16)
; ============================================================================
SFX_STEP:
        LDA #$10
        LDY #$08
        JSR TRIG_CH3_NOISE
        JMP SILENCE_AFTER_SHORT

SFX_ERROR:
        LDA #$90
        LDY #$00
        JSR TRIG_TONE_CH0
        JMP SILENCE_AFTER_SHORT

SFX_LASER_FIRE:
        LDA #$14                ; CH0 = Brass FM
        STA IO_INST
        LDA #$06
        STA TEMP_B
SLF_LP:
        LDA #$80
        LDY TEMP_B
        JSR TRIG_TONE_CH0
        JSR WAIT_20MS
        DEC TEMP_B
        BNE SLF_LP
        JMP SILENCE_ALL_AUDIO

SFX_PLASMA_BOLT:
        LDA #$11                ; CH0 = Hammond
        STA IO_INST
        LDA #$40
        LDY #$03
        JSR TRIG_TONE_W40
        LDA #$A0
        LDY #$01
        JSR TRIG_TONE_W40
        JMP SILENCE_ALL_AUDIO

SFX_EXPLOSION:
        LDA #$20
        LDY #$00
        JSR TRIG_CH3_NOISE
        JSR WAIT_40MS
        LDA #$E0
        LDY #$00
        JSR TRIG_CH3_NOISE
        JSR WAIT_40MS
        JMP SILENCE_AFTER_SHORT

SFX_ALIEN_SCREAM:
        LDA #$14
        STA IO_INST
        LDA #$04
        STA TEMP_B
SAS_LP:
        LDA #$40
        LDY TEMP_B
        JSR TRIG_TONE_W40
        DEC TEMP_B
        BNE SAS_LP
        JMP SILENCE_ALL_AUDIO

SFX_ALIEN_TURN:
        LDA #$16                ; CH0 = FM Bells
        STA IO_INST
        LDA #$20
        LDY #$01
        JSR TRIG_TONE_W40
        JMP SILENCE_AFTER_SHORT

SFX_XCOM_CHORD:
        LDA #$10                ; CH0 = Piano FM
        STA IO_INST
        LDA #$D6
        LDY #$01
        JSR TRIG_TONE_W40
        JMP SILENCE_ALL_AUDIO

SFX_VICTORY:
        LDA #$14                ; CH0 = Brass Fanfare
        STA IO_INST
        LDA #$D6
        LDY #$01
        JSR TRIG_TONE_W40
        LDA #$4C
        LDY #$02
        JSR TRIG_TONE_W40
        LDA #$BA
        LDY #$02
        JSR TRIG_TONE_W40
        JMP SILENCE_AFTER_SHORT

TRIG_TONE_W40:
        JSR TRIG_TONE_CH0
        JMP WAIT_40MS

TRIG_TONE_CH0:
        LDX #0
        BEQ TRIG_CHX
TRIG_CH3_NOISE:
        LDX #3
TRIG_CHX:
        PHA
        LDA #16
        STA IO_GPU
        STX IO_GPU
        LDA #0
        STA IO_GPU
        PLA
        STA IO_GPU
        STY IO_GPU
        LDA #248
        STA IO_GPU
        RTS

SILENCE_AFTER_SHORT:
        JSR WAIT_20MS
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

WAIT_40MS:
        JSR WAIT_20MS
WAIT_20MS:
        LDA IO_TIMER
        CLC
        ADC #2
W20_LP:
        CMP IO_TIMER
        BNE W20_LP
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
; MiniGPU Primitieven & Coördinaat Hulpfuncties
; ============================================================================
; Zet ZP_X_LO/HI = TILE_X[A] + 14, ZP_Y_LO = TILE_Y[Y] + 12
SET_TILE_CENTER_AY:
        TAX
        LDA TILE_X_LO,X
        CLC
        ADC #14
        STA ZP_X_LO
        LDA TILE_X_HI,X
        ADC #0
        STA ZP_X_HI
        LDA TILE_Y_TBL,Y
        CLC
        ADC #12
        STA ZP_Y_LO
        RTS

COPY_XY_TO_XY2:
        LDA ZP_X_LO
        STA ZP_X2_LO
        LDA ZP_X_HI
        STA ZP_X2_HI
        LDA ZP_Y_LO
        STA ZP_Y2_LO
        RTS

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

DRAW_DISK_AY:
        STA ZP_W_LO
        STY ZP_COL
DRAW_DISK_ZP:
        LDA #5
        JSR SEND_CMD_XY
        LDA ZP_W_LO
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA ZP_COL
        STA IO_GPU
        RTS

DRAW_LINE_ZP:
        LDA #3
        JSR SEND_CMD_XY
        LDA ZP_X2_LO
        STA IO_GPU
        LDA ZP_X2_HI
        STA IO_GPU
        LDA ZP_Y2_LO
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_COL
        STA IO_GPU
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
; Tabellen, Coördinaten, 16x10 UFO Crash Map & Teksten
; ============================================================================
TILE_X_LO:
        .BYTE 8, 36, 64, 92, 120, 148, 176, 204, 232, 4, 32, 60, 88, 116, 144, 172
TILE_X_HI:
        .BYTE 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1
TILE_Y_TBL:
        .BYTE 26, 51, 76, 101, 126, 151, 176, 201, 226, 251

; Achtergrondkleur per tegeltype: 0=Gras, 1=BaksteenMuur, 2=Boom, 3=UFO-Wand, 4=UFO-Vloer, 5=Elerium-Kern
TILE_BG_COL:
        .BYTE $10, $A4, $10, $4B, $25, $25

; Relatieve rechthoekjes voor tegels, soldaten en aliens: (dx, dy, w, h, col)
UNIT_BOX_TBL:
        .BYTE 3,  3,  4,  3, $18        ; Offset 0: Graspolletje
        .BYTE 0, 10, 27,  3, $FC        ; Offset 5: Baksteen voeg
        .BYTE 0, 10, 27,  3, $1F        ; Offset 10: UFO-Romp naad
        .BYTE 0,  0, 27,  2, $FC        ; Offset 15: Soldaat selectie boven
        .BYTE 0, 22, 27,  2, $FC        ; Offset 20: Soldaat selectie onder
        .BYTE 7,  4, 13, 16, $1F        ; Offset 25: Blauw X-COM pantser
        .BYTE 10, 6,  8,  3, $FC        ; Offset 30: Gouden vizier & geweer
        .BYTE 2,  3                     ; Offset 35: Soldaat-nummer dx, dy
        .BYTE 0,  0, 27,  2, $E0        ; Offset 37: Alien vizier boven
        .BYTE 0, 22, 27,  2, $E0        ; Offset 42: Alien vizier onder
        .BYTE 7,  4, 13, 16, $00        ; Offset 47: Alien lichaam (kleur uit ALN_COL_TBL)
        .BYTE 9,  7,  3,  3, $00        ; Offset 52: Alien linkeroog
        .BYTE 15, 7,  3,  3, $00        ; Offset 57: Alien rechteroog

; Startposities & stats van de 3 X-COM Soldaten
INIT_SOL_X:     .BYTE 1, 2, 1
INIT_SOL_Y:     .BYTE 2, 5, 8
INIT_SOL_HP:    .BYTE 40, 36, 32
INIT_SOL_TU:    .BYTE 24, 24, 28

; Startposities & stats van de 4 Aliens (Sectoid, Floater, Muton, Commander)
INIT_ALN_X:     .BYTE 6, 8, 11, 13
INIT_ALN_Y:     .BYTE 2, 6, 3,  5
INIT_ALN_HP:    .BYTE 20, 24, 30, 38
ALN_COL_TBL:    .BYTE $92, $E2, $1C, $FC

SQUAD_Y_TBL:    .BYTE 226, 244, 262

GUI_FRAME_STREAM:
        .BYTE 12, 1
        .BYTE 1, $00
        .BYTE 2, 0,0, 0,0, $80,$02, 22,0, $01
        .BYTE 2, 0,0, 22,0, $80,$02, 2,0, $FC
        .BYTE 2, (460 & $FF),(460 >> 8), 26,0, 174,0, (260 & $FF),(260 >> 8), $01
        .BYTE 2, (460 & $FF),(460 >> 8), 26,0, 174,0, 18,0, $48
        .BYTE 2, (460 & $FF),(460 >> 8), 140,0, 174,0, 18,0, $40
        .BYTE 2, (460 & $FF),(460 >> 8), 204,0, 174,0, 18,0, $02
        .BYTE 2, 0,0, (288 & $FF),(288 >> 8), $80,$02, 2,0, $FC
        .BYTE 2, 0,0, (290 & $FF),(290 >> 8), $80,$02, 48,0, $24
        .BYTE 2, 0,0, (338 & $FF),(338 >> 8), $80,$02, 22,0, $00
GUI_FRAME_STREAM_END:

UI_RECT_TBL:
        .BYTE 2, (456 & $FF),(456 >> 8), 5,0, 130,0, 14,0, $01
        .BYTE 2, (466 & $FF),(466 >> 8), 48,0, 164,0, 148,0, $01
        .BYTE 2, 104,0, 134,0, (264 & $FF),(264 >> 8), 36,0, $00
        .BYTE 2, 0,0, (338 & $FF),(338 >> 8), $80,$02, 22,0, $00

STR_STATIC_LABELS:
        .BYTE 10,0, 7,0, $FC, "UFO: ENEMY UNKNOWN 6502 (X-COM)", 0
        .BYTE (404 & $FF),(404 >> 8), 7,0, $FF, "BEURT:    ALIENS:", 0
        .BYTE (468 & $FF),(468 >> 8), 31,0, $FC, "X-COM SOLDAAT", 0
        .BYTE (472 & $FF),(472 >> 8), 74,0, $FF, "TU:", 0
        .BYTE (472 & $FF),(472 >> 8), 94,0, $FF, "HP:", 0
        .BYTE (472 & $FF),(472 >> 8), 114,0, $FF, "GRN:", 0
        .BYTE (468 & $FF),(468 >> 8), 145,0, $FC, "DOELWIT [T]", 0
        .BYTE (472 & $FF),(472 >> 8), 182,0, $FF, "HP:", 0
        .BYTE (468 & $FF),(468 >> 8), 209,0, $1F, "SKYRANGER SQUAD", 0
        .BYTE 10,0, (297 & $FF),(297 >> 8), $FC, "[WASD] Loop(4TU) [SPAT] Snap(8TU) [F] Aimed(14TU) [G] Granaat(12TU)", 0
        .BYTE 10,0, (317 & $FF),(317 >> 8), $FF, "[1-3/TAB] Soldaat [T] Doelwit [H] Medikit(10TU) [E] Beurt [R] Sector", 0
        .BYTE 0

SOL_NAME_LO:    .BYTE <STR_SOL_0, <STR_SOL_1, <STR_SOL_2
SOL_NAME_HI:    .BYTE >STR_SOL_0, >STR_SOL_1, >STR_SOL_2
STR_SOL_0:      .ASCIIZ "1.CMD.ROB"
STR_SOL_1:      .ASCIIZ "2.SGT.JAN"
STR_SOL_2:      .ASCIIZ "3.CPL.EVA"

ALN_NAME_LO:    .BYTE <STR_ALN_0, <STR_ALN_1, <STR_ALN_2, <STR_ALN_3
ALN_NAME_HI:    .BYTE >STR_ALN_0, >STR_ALN_1, >STR_ALN_2, >STR_ALN_3
STR_ALN_0:      .ASCIIZ "SECTOID"
STR_ALN_1:      .ASCIIZ "FLOATER"
STR_ALN_2:      .ASCIIZ "MUTON"
STR_ALN_3:      .ASCIIZ "COMMANDER"
STR_NO_ALIEN:   .ASCIIZ "GEEN ZICHT"

LOG_PTR_LO_TBL:
        .BYTE <STR_LOG_0, <STR_LOG_1, <STR_LOG_2, <STR_LOG_3
        .BYTE <STR_LOG_4, <STR_LOG_5, <STR_LOG_6, <STR_LOG_7
        .BYTE <STR_LOG_8, <STR_LOG_9, <STR_LOG_10, <STR_LOG_11
LOG_PTR_HI_TBL:
        .BYTE >STR_LOG_0, >STR_LOG_1, >STR_LOG_2, >STR_LOG_3
        .BYTE >STR_LOG_4, >STR_LOG_5, >STR_LOG_6, >STR_LOG_7
        .BYTE >STR_LOG_8, >STR_LOG_9, >STR_LOG_10, >STR_LOG_11
LOG_COL_TBL:
        .BYTE $1C, $E0, $FC, $FC, $FC, $1C, $FC, $1C, $1F, $1C, $1C, $E0

STR_HIDDEN_MOV: .ASCIIZ "HIDDEN MOVEMENT - ALIEN TURN"
STR_LOG_0:      .ASCIIZ "SKYRANGER GELAND! BESTORM DE UFO!"
STR_LOG_1:      .ASCIIZ "GEEN TU MEER! DRUK [TAB] OF [E] BEURT."
STR_LOG_2:      .ASCIIZ "GEEN ALIEN IN ZICHT! VERKEN FOG OF WAR."
STR_LOG_3:      .ASCIIZ "LASER SALVO MIST DOELWIT!"
STR_LOG_4:      .ASCIIZ "VOLTREFFER OP ALIEN!"
STR_LOG_5:      .ASCIIZ "ALIEN UITGESCHAKELD! GOED SCHOT!"
STR_LOG_6:      .ASCIIZ "3X3 GRANAAT EXPLOSIE! MUUR VERNIETIGD!"
STR_LOG_7:      .ASCIIZ "MEDIKIT GEBRUIKT (+18 HP)!"
STR_LOG_8:      .ASCIIZ "NIEUWE X-COM BEURT: TU AANGEVULD!"
STR_LOG_9:      .ASCIIZ "OVERWINNING! ALIENS VERSLAGEN! [R]=MISSIE"
STR_LOG_10:     .ASCIIZ "OVERWINNING! UFO KERN VEROVERD! [R]=MISSIE"
STR_LOG_11:     .ASCIIZ "TEAM UITGESCHAKELD... DRUK [R] HERSTART."

MAP_PACKED:
        .BYTE $00, $20, $01, $11, $00, $20, $00, $20, $00, $00, $01, $01, $00, $03, $33, $00
        .BYTE $00, $02, $00, $01, $00, $34, $44, $30, $00, $00, $01, $00, $03, $44, $44, $43
        .BYTE $00, $20, $01, $12, $04, $44, $45, $43, $00, $00, $00, $00, $04, $44, $44, $43
        .BYTE $00, $02, $01, $11, $03, $44, $44, $43, $00, $00, $01, $00, $00, $34, $44, $30
        .BYTE $00, $20, $01, $01, $00, $03, $33, $00, $00, $00, $20, $00, $20, $00, $20, $00
