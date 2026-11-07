; ============================================================================
; DUNGEON.asm - "Kerkers van Twente" 3D First-Person Dungeon Crawler (6502)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC op $9000).
;   - Hardware Double-Buffered (cmd 12,0 + cmd 11) 640x360 3D Engine:
;       * 360x224 3D Perspectief Viewport (X=24..384, Y=28..252) met 4 dieptes,
;         trapezium zijmuren (hardware gevulde driehoeken cmd 7), zijgangen,
;         deuren met slot, trappen/portalen, 3D schatkisten, drankjes,
;         Orks, Skeletten, Vuur-Draak eindbaas en 3D Zwaard-animatie!
;       * Live 16x16 Fog-of-War Automap (rechtsboven) + Kompas & Speler-HUD
;       * 3-kanaals Hardware Audio-effecten (voetstappen, zwaard, schat, schade)
;   - Besturing (Toetsenbord, Browser Snelcommando & Joystick):
;       * W / Pijl-Omhoog : Stap vooruit (of open deur / pak kist / trap)
;       * S / Pijl-Omlaag : Stap achteruit
;       * A / Pijl-Links  : Draai 90 graden naar links
;       * D / Pijl-Rechts : Draai 90 graden naar rechts
;       * Q / E           : Zijstap links / rechts
;       * SPATIE / Z / Enter : Zwaard-aanval / Interactie
;       * H               : Drink Heilzame Drank (+15 HP)
;       * R               : Herstart spel
;       * ESC             : Netjes in 1x terug naar BASIC
; ============================================================================
        ORG $8000

IO_STATUS       = $A000
IO_TERM         = $A001
IO_TIMER        = $A003
IO_JOY          = $A004
IO_RND          = $A005
IO_MODE         = $A006
IO_GPU          = $A020

ROM_SILENCE     = $E8DC

; --- Tegeltypes in het 16x16 Kerker-labyrint ---
TILE_EMPTY      = 0
TILE_WALL       = 1
TILE_DOOR       = 2
TILE_STAIRS     = 3
TILE_CHEST      = 4
TILE_POTION     = 5
TILE_ORC        = 6
TILE_SKEL       = 7
TILE_DRAGON     = 8

; --- Zero Page Variabelen ($60..$7F: veilig naast BASIC en MC!) ---
ZP_PTR_LO       = $60
ZP_PTR_HI       = $61
ZP_X_LO         = $62
ZP_X_HI         = $63
ZP_Y_LO         = $64
ZP_Y_HI         = $65
ZP_W_LO         = $66
ZP_W_HI         = $67
ZP_H_LO         = $68
ZP_COLOR        = $69

PX              = $6A           ; Speler X (1..14)
PY              = $6B           ; Speler Y (1..14)
PDIR            = $6C           ; 0=Noord, 1=Oost, 2=Zuid, 3=West
P_HP            = $6D           ; Levenspunten (max 30)
P_MAXHP         = $6E
P_ATK           = $6F           ; Aanvalskracht
P_GOLD          = $70           ; Goud (0..255)
P_KEYS          = $71           ; Sleutels
P_POTS          = $72           ; Heilzame Drankjes
P_FLOOR         = $73           ; Kerker-verdieping (1..9)
MON_HP          = $74           ; Huidige HP van monster vlak voor je
SWING_ANIM      = $75           ; >0 = Zwaard-zwaai animatie actief
CUR_DEPTH       = $76           ; Huidige render-diepte d (3..0)
TMP_X           = $77
TMP_Y           = $78
TMP_A           = $79
TMP_B           = $7A
SAV_X           = $7B
SAV_Y           = $7C
PREV_JOY        = $7D
MSG_ID          = $7E           ; Huidige statusbericht-index
SFX_TIMER       = $7F           ; Timer om geluidseffect automatisch te dempen

; --- SDRAM Buffers ($5000..$51FF) ---
MAP_RAM         = $5000         ; 256 B Actieve 16x16 Kerkerkaart ($5000..$50FF)
FOG_RAM         = $5100         ; 256 B Ontdekte vakjes voor Automap ($5100..$51FF)

; ============================================================================
; Start & Spel-Initialisatie
; ============================================================================
START:
        LDA #12
        STA IO_TERM
        LDA #0
        STA IO_MODE
        STA ZP_Y_HI
        STA SFX_TIMER
        JSR SILENCE_AUDIO
        JSR DRAIN_SERIAL_SHORT

NEW_GAME:
        LDA #30
        STA P_HP
        STA P_MAXHP
        LDA #8
        STA P_ATK
        LDA #0
        STA P_GOLD
        STA P_KEYS
        STA SWING_ANIM
        STA MON_HP
        STA SFX_TIMER
        LDA #2
        STA P_POTS
        LDA #1
        STA P_FLOOR
        JSR INIT_FLOOR
        LDA #0                  ; "WELKOM IN DE KERKERS VAN TWENTE!"
        STA MSG_ID

        LDA IO_JOY
        STA PREV_JOY

MAIN_LOOP:
        JSR REVEAL_AROUND_PLAYER
        JSR DRAW_FRAME
        LDA SWING_ANIM
        BEQ WAIT_INPUT
        LDX #8
        JSR DELAY_X_TICKS
        LDA #0
        STA SWING_ANIM
        JSR SILENCE_AUDIO
        JMP MAIN_LOOP

WAIT_INPUT:
        LDA IO_TIMER
        CMP TMP_B
        BEQ WI_KEYS
        STA TMP_B
        LDA SFX_TIMER
        BEQ WI_KEYS
        DEC SFX_TIMER
        BNE WI_KEYS
        JSR SILENCE_AUDIO

WI_KEYS:
        LDA IO_STATUS
        BMI READ_KEY
        AND #1
        BEQ CHK_JOY

READ_KEY:
        LDA IO_JOY
        STA PREV_JOY
        LDX #0
        STX IO_MODE
        LDA IO_TERM
        BEQ WAIT_INPUT
        JMP HANDLE_KEY

; ============================================================================
; Geluid dempen ZONDER IO_MODE ($A006) naar MODE 0 (Boerderij) te schakelen!
; (ROM_SILENCE op $E8DC zet namelijk IO_MODE=1 en wist de frontbuffer naar $E3!)
; ============================================================================
SILENCE_AUDIO:
        LDX #3
SA_LP:  LDA #16
        STA IO_GPU
        STX IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        DEX
        BPL SA_LP
        RTS

; ============================================================================
; Netjes Afsluiten naar BASIC (1x ESC, scherm herstellen & serieel flushen)
; ============================================================================
EXIT_TO_BASIC:
        JSR SILENCE_AUDIO
        JSR ROM_SILENCE
        LDX #15
        JSR DSL_LP
        LDX #GS_EXIT - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

DRAIN_SERIAL_SHORT:
        LDX #4
DSL_LP: JSR DELAY_10MS
        LDA IO_TERM
        LDA #0
        STA IO_MODE
        DEX
        BNE DSL_LP
        RTS

DELAY_X_TICKS:
        JSR DELAY_10MS
        DEX
        BNE DELAY_X_TICKS
        RTS

DELAY_10MS:
        LDA IO_TIMER
D10_W:  CMP IO_TIMER
        BEQ D10_W
        RTS

; ============================================================================
; Joystick & Toetsenbord Besturing
; ============================================================================
CHK_JOY:
        LDA IO_JOY
        STA TMP_A
        TAX
        EOR PREV_JOY
        AND TMP_A
        STX PREV_JOY
        TAY
        BEQ WAIT_INPUT

        TYA
        AND #$01                ; Joy Up -> Vooruit
        BNE DO_FORWARD
        TYA
        AND #$02                ; Joy Down -> Achteruit
        BNE DO_BACKWARD
        TYA
        AND #$04                ; Joy Left -> Draai Links
        BNE DO_TURN_LEFT
        TYA
        AND #$08                ; Joy Right -> Draai Rechts
        BNE DO_TURN_RIGHT
        TYA
        AND #$30                ; Joy Fire -> Aanval / Interactie
        BNE DO_ACTION
        JMP WAIT_INPUT

HANDLE_KEY:
        CMP #$1B                ; ESC of ANSI pijltjestoets (ESC [ A/B/C/D)?
        BNE HK_NORMAL

        LDX #4
HK_EW:  JSR DELAY_10MS
        LDA IO_STATUS
        AND #$81
        BNE HK_E2
        DEX
        BNE HK_EW
        JMP EXIT_TO_BASIC       ; Losse ESC -> direct naar BASIC!

HK_E2:  LDA IO_TERM
        LDX #0
        STX IO_MODE
        CMP #$1B
        BEQ EXIT_TO_BASIC
        CMP #'['
        BNE HK_NORMAL
        LDX #4
HK_EW2: JSR DELAY_10MS
        LDA IO_STATUS
        AND #$81
        BNE HK_E3
        DEX
        BNE HK_EW2
        JMP WAIT_INPUT
HK_E3:  LDA IO_TERM
        LDX #0
        STX IO_MODE
        CMP #'A'
        BEQ DO_FORWARD
        CMP #'B'
        BEQ DO_BACKWARD
        CMP #'D'
        BEQ DO_TURN_LEFT
        CMP #'C'
        BEQ DO_TURN_RIGHT
        JMP WAIT_INPUT

HK_NORMAL:
        CMP #' '
        BEQ DO_ACTION
        CMP #$0D
        BEQ DO_ACTION
        CMP #'8'
        BEQ DO_FORWARD
        CMP #'2'
        BEQ DO_BACKWARD
        CMP #'4'
        BEQ DO_TURN_LEFT
        CMP #'6'
        BEQ DO_TURN_RIGHT
        CMP #'5'
        BEQ DO_ACTION

        ORA #$20
        CMP #'w'
        BEQ DO_FORWARD
        CMP #'s'
        BEQ DO_BACKWARD
        CMP #'a'
        BEQ DO_TURN_LEFT
        CMP #'d'
        BEQ DO_TURN_RIGHT
        CMP #'q'
        BEQ DO_STRAFE_LEFT
        CMP #'e'
        BEQ DO_STRAFE_RIGHT
        CMP #'z'
        BEQ DO_ACTION
        CMP #'f'
        BEQ DO_ACTION
        CMP #'h'
        BEQ DO_HEAL
        CMP #'p'
        BEQ DO_HEAL
        CMP #'r'
        BNE HK_IGN
        JMP NEW_GAME
HK_IGN: JMP WAIT_INPUT

; --- Draaien & Stappen ---
DO_TURN_LEFT:
        DEC PDIR
        JMP DTL_1
DO_TURN_RIGHT:
        INC PDIR
DTL_1:  LDA PDIR
        AND #3
        STA PDIR
        LDA #0
        STA MON_HP
        JSR SFX_STEP
        JMP MAIN_LOOP

DO_FORWARD:
        LDX PDIR
        JMP TRY_MOVE_DIR_X

DO_BACKWARD:
        LDA PDIR
        EOR #2
        TAX
        JMP TRY_MOVE_DIR_X

DO_STRAFE_LEFT:
        LDA PDIR
        SEC
        SBC #1
        AND #3
        TAX
        JMP TRY_MOVE_DIR_X

DO_STRAFE_RIGHT:
        LDA PDIR
        CLC
        ADC #1
        AND #3
        TAX

TRY_MOVE_DIR_X:
        LDA P_HP
        BNE TMD_ALIVE
        JMP NEW_GAME
TMD_ALIVE:
        CLC
        LDA PX
        ADC DIR_DX,X
        STA TMP_X
        CLC
        LDA PY
        ADC DIR_DY,X
        STA TMP_Y
        JSR GET_TILE_TMP
        CMP #TILE_EMPTY
        BEQ TMD_STEP
        CMP #TILE_WALL
        BEQ TMD_BLOCKED
        CMP #TILE_DOOR
        BEQ TMD_DOOR
        CMP #TILE_STAIRS
        BEQ TMD_STAIRS
        CMP #TILE_CHEST
        BEQ TMD_CHEST
        CMP #TILE_POTION
        BEQ TMD_POTION
        ; Monster op het doelvakje -> voer direct een aanval uit!
        JMP DO_ACTION

TMD_STEP:
        LDA TMP_X
        STA PX
        LDA TMP_Y
        STA PY
        LDA #0
        STA MON_HP
        JSR SFX_STEP
        JMP MAIN_LOOP

TMD_BLOCKED:
        LDA #1                  ; "STEENKOUD MUURWERK BLOKKEERT JE PAD."
        STA MSG_ID
        JSR SFX_THUD
        JMP MAIN_LOOP

TMD_DOOR:
        LDA P_KEYS
        BEQ TMD_NO_KEY
        DEC P_KEYS
        LDA #TILE_EMPTY
        JSR SET_TILE_TMP
        LDA #2                  ; "MET DE GOUDEN SLEUTEL OPEN JE DE DEUR!"
        STA MSG_ID
        JSR SFX_TREASURE
        JMP MAIN_LOOP
TMD_NO_KEY:
        LDA #3                  ; "DEZE EIKEN DEUR ZIT OP SLOT! ZOEK EEN SLEUTEL."
        STA MSG_ID
        JSR SFX_THUD
        JMP MAIN_LOOP

TMD_CHEST:
        LDA #TILE_EMPTY
        JSR SET_TILE_TMP
        INC P_KEYS
        INC P_ATK
        INC P_ATK
        CLC
        LDA P_GOLD
        ADC #40
        STA P_GOLD
        LDA #4                  ; "SCHATKIST! +40 GOUD, +1 SLEUTEL & ZWAARD +2!"
        STA MSG_ID
        JSR SFX_TREASURE
        JMP TMD_STEP

TMD_POTION:
        LDA #TILE_EMPTY
        JSR SET_TILE_TMP
        INC P_POTS
        LDA #5                  ; "JE VINDT EEN HEILZAME ELIXER-FLES (+1 DRANK)!"
        STA MSG_ID
        JSR SFX_TREASURE
        JMP TMD_STEP

TMD_STAIRS:
        INC P_FLOOR
        CLC
        LDA P_GOLD
        ADC #100
        STA P_GOLD
        LDA P_MAXHP
        STA P_HP
        JSR INIT_FLOOR
        LDA #6                  ; "JE DAALT AF NAAR EEN DIEPERE KERKER-VERDIEPING!"
        STA MSG_ID
        JSR SFX_TREASURE
        JMP MAIN_LOOP

; --- Drink Heilzame Drank (H) ---
DO_HEAL:
        LDA P_HP
        BEQ HK_IGN
        LDA P_POTS
        BEQ DH_NONE
        DEC P_POTS
        CLC
        LDA P_HP
        ADC #16
        CMP P_MAXHP
        BCC DH_1
        LDA P_MAXHP
DH_1:   STA P_HP
        LDA #7                  ; "JE DRINKT EEN ELIXER: +16 LEVENSPUNTEN HERSTELD!"
        STA MSG_ID
        JSR SFX_TREASURE
        JMP MAIN_LOOP
DH_NONE:
        LDA #8                  ; "GEEN HEILZAME DRANKJES MEER IN JE TAS!"
        STA MSG_ID
        JMP MAIN_LOOP

; --- Zwaard-Aanval & Interactie op het vakje recht voor je (SPATIE / Z) ---
DO_ACTION:
        LDA P_HP
        BNE DA_1
        JMP NEW_GAME
DA_1:   LDA #1
        STA SWING_ANIM
        JSR SFX_SWORD

        LDX PDIR
        CLC
        LDA PX
        ADC DIR_DX,X
        STA TMP_X
        CLC
        LDA PY
        ADC DIR_DY,X
        STA TMP_Y
        JSR GET_TILE_TMP
        CMP #TILE_DOOR
        BEQ TMD_DOOR
        CMP #TILE_CHEST
        BEQ TMD_CHEST
        CMP #TILE_POTION
        BEQ TMD_POTION
        CMP #TILE_STAIRS
        BEQ TMD_STAIRS
        CMP #TILE_ORC
        BCC DA_MISS

        ; Er staat een Monster (6=Ork, 7=Skelet, 8=Draak) recht voor ons!
        SEC
        SBC #TILE_ORC
        TAX                     ; X = 0 (Ork), 1 (Skelet), 2 (Draak)
        LDA MON_HP
        BNE DA_HIT
        LDA MON_START_HP,X
        CLC
        ADC P_FLOOR
        STA MON_HP

DA_HIT: SEC
        LDA MON_HP
        SBC P_ATK
        BCC DA_KILL
        BEQ DA_KILL
        STA MON_HP

        ; Monster slaat terug!
        SEC
        LDA P_HP
        SBC MON_ATK_TBL,X
        BCC DA_DIED
        BEQ DA_DIED
        STA P_HP
        LDA #9                  ; "VOLTREFFER! HET MONSTER SLAAT TERUG!"
        STA MSG_ID
        JMP MAIN_LOOP

DA_DIED:
        LDA #0
        STA P_HP
        LDA #11                 ; "JE BENT GESNEUVELD! DRUK OP R OF SPATIE."
        STA MSG_ID
        JSR SFX_THUD
        JMP MAIN_LOOP

DA_KILL:
        LDA #0
        STA MON_HP
        LDA #TILE_EMPTY
        CPX #2                  ; Was het de Vuur-Draak (Eindbaas)?
        BNE DAK_1
        LDA #TILE_STAIRS        ; Draak laat het Magische Portaal achter!
DAK_1:  JSR SET_TILE_TMP
        CLC
        LDA P_GOLD
        ADC MON_GOLD_TBL,X
        STA P_GOLD
        LDA #10                 ; "MONSTER VERSLAGEN! JE MAAKT GOUD BUIT!"
        STA MSG_ID
        JSR SFX_TREASURE
        JMP MAIN_LOOP

DA_MISS:
        LDA #12                 ; "JE ZWAAIT JE ZWAARD DOOR DE DUISTERE LUCHT."
        STA MSG_ID
        JMP MAIN_LOOP

; ============================================================================
; Kerker-Kaart Hulproutines (16x16 in MAP_RAM $5000, Fog in FOG_RAM $5100)
; ============================================================================
INIT_FLOOR:
        LDX #0
IF_LP:  LDA DUNGEON_TEMPLATE,X
        STA MAP_RAM,X
        LDA #0
        STA FOG_RAM,X
        INX
        BNE IF_LP
        LDA #1
        STA PX
        STA PY
        STA PDIR                ; Kijk naar het Oosten (1) bij de start
        RTS

REVEAL_AROUND_PLAYER:
        LDX #8
RAP_LP: CLC
        LDA PX
        ADC REV_DX,X
        AND #$0F
        STA TMP_A
        CLC
        LDA PY
        ADC REV_DY,X
        AND #$0F
        ASL A
        ASL A
        ASL A
        ASL A
        ORA TMP_A
        TAY
        LDA #1
        STA FOG_RAM,Y
        DEX
        BPL RAP_LP
        RTS

GET_TILE_TMP:
        LDA TMP_X
        CMP #16
        BCS GTT_W
        LDA TMP_Y
        CMP #16
        BCS GTT_W
        ASL A
        ASL A
        ASL A
        ASL A
        ORA TMP_X
        TAY
        LDA MAP_RAM,Y
        RTS
GTT_W:  LDA #TILE_WALL
        RTS

SET_TILE_TMP:
        PHA
        LDA TMP_Y
        ASL A
        ASL A
        ASL A
        ASL A
        ORA TMP_X
        TAY
        PLA
        STA MAP_RAM,Y
        RTS

; Geeft tegel op (diepte A = 0..4, zij-offset Y = $FF (-1), 0, of 1)
GET_REL_TILE:
        STA TMP_A               ; Diepte d (0..4)
        STY TMP_B               ; Zij-offset s (-1, 0, +1)
        LDX PDIR
        ; X_map = PX + d * DIR_DX[dir] + s * SIDE_DX[dir]
        LDA PX
        LDY TMP_A
        BEQ GRT_S
GRT_DL: CLC
        ADC DIR_DX,X
        DEY
        BNE GRT_DL
GRT_S:  STA TMP_X
        LDA PY
        LDY TMP_A
        BEQ GRT_S2
GRT_D2: CLC
        ADC DIR_DY,X
        DEY
        BNE GRT_D2
GRT_S2: STA TMP_Y

        LDA TMP_B
        BEQ GRT_RD
        BMI GRT_LEFT
        CLC
        LDA TMP_X
        ADC SIDE_DX,X
        STA TMP_X
        CLC
        LDA TMP_Y
        ADC SIDE_DY,X
        STA TMP_Y
        JMP GRT_RD
GRT_LEFT:
        SEC
        LDA TMP_X
        SBC SIDE_DX,X
        STA TMP_X
        SEC
        LDA TMP_Y
        SBC SIDE_DY,X
        STA TMP_Y
GRT_RD: JMP GET_TILE_TMP

; ============================================================================
; 3-Kanaals Hardware Geluidseffecten (via IO_GPU cmd 16)
; ============================================================================
SFX_STEP:
        LDX #GS_SFX_STEP - GPU_STREAMS
        BNE PLAY_SFX_X
SFX_THUD:
        LDX #GS_SFX_THUD - GPU_STREAMS
        BNE PLAY_SFX_X
SFX_SWORD:
        LDX #GS_SFX_SWORD - GPU_STREAMS
        BNE PLAY_SFX_X
SFX_TREASURE:
        LDX #GS_SFX_TREAS - GPU_STREAMS
PLAY_SFX_X:
        LDA #6
        STA SFX_TIMER
        JMP SEND_STREAM_X

; ============================================================================
; Volledige Dubbel-Gebufferde Frame Renderer (640x360)
; ============================================================================
DRAW_FRAME:
        ; 1. Teken naar Back-Buffer: Achtergrond, 3D Plafond & Vloer-perspectief
        LDX #GS_BG_3D - GPU_STREAMS
        JSR SEND_STREAM_X

        ; 2. Als er op diepte 4 een muur staat, sluit de horizon af
        LDA #4
        LDY #0
        JSR GET_REL_TILE
        CMP #TILE_EMPTY
        BEQ DF_D3
        LDX #4
        LDA #$24
        JSR DRAW_FRONT_WALL_X

        ; 3. Painter's Algorithm van achter (d=3) naar voor (d=0)!
DF_D3:  LDA #3
        STA CUR_DEPTH
DF_DLP:
        ; --- Linker zijmuur of zijgang op diepte CUR_DEPTH ---
        LDA CUR_DEPTH
        LDY #$FF
        JSR GET_REL_TILE
        CMP #TILE_WALL
        BEQ DF_LWALL
        CMP #TILE_DOOR
        BEQ DF_LWALL
        ; Open naar links: kijk of d+1 links wel een muur heeft (zijgang!)
        LDA CUR_DEPTH
        CLC
        ADC #1
        LDY #$FF
        JSR GET_REL_TILE
        CMP #TILE_WALL
        BCC DF_CHK_R
        CMP #TILE_STAIRS+1
        BCS DF_CHK_R
        LDX CUR_DEPTH
        JSR DRAW_LEFT_FLAT_X
        JMP DF_CHK_R
DF_LWALL:
        LDX CUR_DEPTH
        JSR DRAW_LEFT_TRAP_X

DF_CHK_R:
        ; --- Rechter zijmuur of zijgang op diepte CUR_DEPTH ---
        LDA CUR_DEPTH
        LDY #1
        JSR GET_REL_TILE
        CMP #TILE_WALL
        BEQ DF_RWALL
        CMP #TILE_DOOR
        BEQ DF_RWALL
        ; Open naar rechts: kijk of d+1 rechts een muur heeft (zijgang!)
        LDA CUR_DEPTH
        CLC
        ADC #1
        LDY #1
        JSR GET_REL_TILE
        CMP #TILE_WALL
        BCC DF_CHK_C
        CMP #TILE_STAIRS+1
        BCS DF_CHK_C
        LDX CUR_DEPTH
        JSR DRAW_RIGHT_FLAT_X
        JMP DF_CHK_C
DF_RWALL:
        LDX CUR_DEPTH
        JSR DRAW_RIGHT_TRAP_X

DF_CHK_C:
        ; --- Midden-tegel op diepte CUR_DEPTH (alleen voor d >= 1) ---
        LDA CUR_DEPTH
        BEQ DF_NEXT_D
        LDY #0
        JSR GET_REL_TILE
        CMP #TILE_EMPTY
        BEQ DF_NEXT_D
        CMP #TILE_STAIRS+1
        BCC DF_CWALL
        ; Het is een 3D Object of Monster (4..8) op diepte CUR_DEPTH!
        JSR DRAW_ENTITY_A
        JMP DF_NEXT_D

DF_CWALL:
        PHA                     ; Bewaar tegeltype (1=Muur, 2=Deur, 3=Trap)
        LDX CUR_DEPTH
        LDA FRONT_COL_TBL,X
        JSR DRAW_FRONT_WALL_X
        PLA
        LDX CUR_DEPTH
        CMP #TILE_DOOR
        BNE DF_CW2
        JSR DRAW_DOOR_X
        JMP DF_NEXT_D
DF_CW2: CMP #TILE_STAIRS
        BNE DF_NEXT_D
        JSR DRAW_STAIRS_X

DF_NEXT_D:
        DEC CUR_DEPTH
        bmi DF_FG
        JMP DF_DLP

DF_FG:
        ; 4. Teken 3D Zwaard rechtsonder in het 3D-venster (of Aanvals-zwaai!)
        LDX #GS_SWORD_IDLE - GPU_STREAMS
        LDA SWING_ANIM
        BEQ DF_SW1
        LDX #GS_SWORD_SLASH - GPU_STREAMS
DF_SW1: JSR SEND_STREAM_X

        ; 5. Teken 16x16 Automap (Fog-of-War), Speler-HUD & Statusbalk
        JSR DRAW_AUTOMAP
        JSR DRAW_HUD_TEXT

        ; 6. Flip Back-Buffer naar Front-Buffer (cmd 11: 0-flicker!)
        LDA #11
        STA IO_GPU
        RTS

; ============================================================================
; 3D Perspectief Muur, Deur, Trap & Monster Tekenroutines
; ============================================================================
; Vlakke voor-muur op vlak X (0..4) met kleur A + baksteen-voegen
DRAW_FRONT_WALL_X:
        STX SAV_X
        STA ZP_COLOR
        LDA VP_XL_LO,X
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA VP_YT,X
        STA ZP_Y_LO
        LDA VP_W_LO,X
        STA ZP_W_LO
        LDA VP_W_HI,X
        STA ZP_W_HI
        LDA VP_H,X
        STA ZP_H_LO
        JSR GPU_FILL_RECT

        ; Kaderlijn boven & onder voor diepte-contrast
        LDX SAV_X
        LDA #$00
        STA ZP_COLOR
        LDA VP_XL_LO,X
        LDY VP_YT,X
        JSR GPU_HLINE_W
        LDX SAV_X
        LDA VP_XL_LO,X
        LDY VP_YB,X
        JMP GPU_HLINE_W

; Linker zijgang-muur (plat rechthoekje tussen XL[X] en XL[X+1] op hoogte X+1)
DRAW_LEFT_FLAT_X:
        LDA FRONT_COL_TBL+1,X
        STA ZP_COLOR
        LDA VP_XL_LO,X
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA VP_YT+1,X
        STA ZP_Y_LO
        LDA VP_DX,X
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA VP_H+1,X
        STA ZP_H_LO
        JMP GPU_FILL_RECT

; Linker trapezium-muur van vlak X naar X+1 (Rechthoek + 2 Gevulde Driehoeken!)
DRAW_LEFT_TRAP_X:
        LDA SIDE_COL_TBL,X
        STA ZP_COLOR
        LDA VP_XL_LO,X
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA VP_YT+1,X
        STA ZP_Y_LO
        LDA VP_DX,X
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA VP_H+1,X
        STA ZP_H_LO
        JSR GPU_FILL_RECT

        LDX CUR_DEPTH
        ; Bovenste driehoek: (XL[X], YT[X]) - (XL[X], YT[X+1]) - (XL[X+1], YT[X+1])
        LDA #7
        STA IO_GPU
        LDA VP_XL_LO,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_YT,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_XL_LO,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_YT+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_XL_LO+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_YT+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_COLOR
        STA IO_GPU

        ; Onderste driehoek: (XL[X], YB[X]) - (XL[X], YB[X+1]) - (XL[X+1], YB[X+1])
        LDA #7
        STA IO_GPU
        LDA VP_XL_LO,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_YB,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_XL_LO,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_YB+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_XL_LO+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_YB+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_COLOR
        STA IO_GPU

        ; Verticale scheidingslijn op XL[X+1]
        LDA VP_XL_LO+1,X
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA VP_YT+1,X
        STA ZP_Y_LO
        LDA #1
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA VP_H+1,X
        STA ZP_H_LO
        LDA #$00
        STA ZP_COLOR
        JMP GPU_FILL_RECT

; Rechter zijgang-muur (plat rechthoekje tussen XR[X+1] en XR[X] op hoogte X+1)
DRAW_RIGHT_FLAT_X:
        LDA FRONT_COL_TBL+1,X
        STA ZP_COLOR
        JMP DRT_RECT

; Rechter trapezium-muur van vlak X naar X+1
DRAW_RIGHT_TRAP_X:
        LDA SIDE_COL_TBL,X
        STA ZP_COLOR
        JSR DRT_RECT

        LDX CUR_DEPTH
        ; Bovenste driehoek: (XR[X], YT[X]) - (XR[X], YT[X+1]) - (XR[X+1], YT[X+1])
        LDA #7
        STA IO_GPU
        LDA VP_XR_LO,X
        STA IO_GPU
        LDA VP_XR_HI,X
        STA IO_GPU
        LDA VP_YT,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_XR_LO,X
        STA IO_GPU
        LDA VP_XR_HI,X
        STA IO_GPU
        LDA VP_YT+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_XR_LO+1,X
        STA IO_GPU
        LDA VP_XR_HI+1,X
        STA IO_GPU
        LDA VP_YT+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_COLOR
        STA IO_GPU

        ; Onderste driehoek: (XR[X], YB[X]) - (XR[X], YB[X+1]) - (XR[X+1], YB[X+1])
        LDA #7
        STA IO_GPU
        LDA VP_XR_LO,X
        STA IO_GPU
        LDA VP_XR_HI,X
        STA IO_GPU
        LDA VP_YB,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_XR_LO,X
        STA IO_GPU
        LDA VP_XR_HI,X
        STA IO_GPU
        LDA VP_YB+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA VP_XR_LO+1,X
        STA IO_GPU
        LDA VP_XR_HI+1,X
        STA IO_GPU
        LDA VP_YB+1,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_COLOR
        STA IO_GPU

        ; Verticale scheidingslijn op XR[X+1]
        LDA VP_XR_LO+1,X
        STA ZP_X_LO
        LDA VP_XR_HI+1,X
        STA ZP_X_HI
        LDA VP_YT+1,X
        STA ZP_Y_LO
        LDA #1
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA VP_H+1,X
        STA ZP_H_LO
        LDA #$00
        STA ZP_COLOR
        JMP GPU_FILL_RECT

DRT_RECT:
        LDA VP_XR_LO+1,X
        STA ZP_X_LO
        LDA VP_XR_HI+1,X
        STA ZP_X_HI
        LDA VP_YT+1,X
        STA ZP_Y_LO
        LDA VP_DX,X
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA VP_H+1,X
        STA ZP_H_LO
        JMP GPU_FILL_RECT

; --- Houten/Gouden Kerkerdeur (TILE_DOOR) of Magische Trap (TILE_STAIRS) ---
DRAW_DOOR_X:
        LDA #$88                ; Kastanjebruin eikenhout
        LDY #$FC                ; Gouden slotplaat
        BNE DD_COMMON
DRAW_STAIRS_X:
        LDA #$03                ; Diepblauw portaal
        LDY #$1F                ; Lichtcyaan magische gloed
DD_COMMON:
        STA ZP_COLOR
        STY SAV_Y
        LDA DOOR_X,X
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA DOOR_Y,X
        STA ZP_Y_LO
        LDA DOOR_W,X
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA DOOR_H,X
        STA ZP_H_LO
        JSR GPU_FILL_RECT
        ; Gouden klink / Magische kern in het midden
        LDX CUR_DEPTH
        LDA #5                  ; FILLED_CIRCLE
        STA IO_GPU
        LDA #204
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #140
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ENT_RAD,X
        LSR A
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA SAV_Y
        STA IO_GPU
        RTS

; --- 3D Objecten (4=Kist, 5=Drank) & Monsters (6=Ork, 7=Skelet, 8=Draak) ---
DRAW_ENTITY_A:
        SEC
        SBC #TILE_CHEST
        TAY                     ; Y = 0(Kist), 1(Drank), 2(Ork), 3(Skelet), 4(Draak)
        LDX CUR_DEPTH
        CPY #2
        BCS DE_MONSTER

        ; Object op de vloer (0=Schatkist, 1=Drankfles)
        LDA ENT_COL_BODY,Y
        STA ZP_COLOR
        LDA ENT_BOX_X,X
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA ENT_FLOOR_Y,X
        STA ZP_Y_LO
        LDA ENT_BOX_W,X
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA ENT_BOX_H,X
        STA ZP_H_LO
        JSR GPU_FILL_RECT
        ; Gouden dekselrand / glans
        LDX CUR_DEPTH
        LDA #$FC
        STA ZP_COLOR
        LDA #4
        STA ZP_H_LO
        JMP GPU_FILL_RECT

DE_MONSTER:
        ; Monster op diepte X (1..3): Torso + Hoofd + Gloeiende Ogen + Wapen!
        STY SAV_Y
        LDA ENT_COL_BODY,Y
        STA ZP_COLOR
        LDA ENT_BOX_X,X
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA ENT_BODY_Y,X
        STA ZP_Y_LO
        LDA ENT_BOX_W,X
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA ENT_BODY_H,X
        STA ZP_H_LO
        JSR GPU_FILL_RECT       ; Torso / Pantser

        ; Monster Hoofd (FILLED_CIRCLE op CX=204, Y=ENT_HEAD_Y, R=ENT_RAD)
        LDX CUR_DEPTH
        LDY SAV_Y
        LDA #5
        STA IO_GPU
        LDA #204
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ENT_HEAD_Y,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ENT_RAD,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA ENT_COL_HEAD,Y
        STA IO_GPU

        ; Twee vurige ogen op het hoofd!
        LDA #198
        STA ZP_X_LO
        LDA ENT_HEAD_Y,X
        STA ZP_Y_LO
        LDA #4
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #$E0                ; Felrood gloeiende ogen
        STA ZP_COLOR
        JSR GPU_FILL_RECT
        LDA #208
        STA ZP_X_LO
        JMP GPU_FILL_RECT

; ============================================================================
; Live 16x16 Fog-of-War Automap (Rechtsboven: X=440..567, Y=40..167, 8x8 cel)
; ============================================================================
DRAW_AUTOMAP:
        LDA #0
        STA TMP_Y
DAM_YL: LDA #0
        STA TMP_X
DAM_XL: LDA TMP_Y
        ASL A
        ASL A
        ASL A
        ASL A
        ORA TMP_X
        TAY
        LDA FOG_RAM,Y
        BEQ DAM_NEXT            ; Nog in de mist (Fog of War)!

        LDA MAP_RAM,Y
        TAX
        LDA MAP_COL_TBL,X
        STA ZP_COLOR

        ; Cel X = 440 + TMP_X * 8, Y = 40 + TMP_Y * 8
        LDA TMP_X
        ASL A
        ASL A
        ASL A
        CLC
        ADC #<440
        STA ZP_X_LO
        LDA #>440
        ADC #0
        STA ZP_X_HI

        LDA TMP_Y
        ASL A
        ASL A
        ASL A
        CLC
        ADC #40
        STA ZP_Y_LO
        LDA #7
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #0
        STA ZP_W_HI
        JSR GPU_FILL_RECT

DAM_NEXT:
        INC TMP_X
        LDA TMP_X
        CMP #16
        BCC DAM_XL
        INC TMP_Y
        LDA TMP_Y
        CMP #16
        BCC DAM_YL

        ; Teken Speler-positie (felwit blokje + kijkrichting-karakter) op de Automap!
        LDA PX
        ASL A
        ASL A
        ASL A
        CLC
        ADC #<440
        STA ZP_X_LO
        LDA #>440
        ADC #0
        STA ZP_X_HI
        LDA PY
        ASL A
        ASL A
        ASL A
        CLC
        ADC #40
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COLOR
        LDX PDIR
        LDA DIR_CHARS,X
        JMP DRAW_CHAR_ONLY

; ============================================================================
; Speler-HUD, Statistieken, Kompas & Gevechtslog (Rechtsonder & Onderbalk)
; ============================================================================
DRAW_HUD_TEXT:
        ; Titelbalk bovenaan op (24, 9)
        LDX #24
        LDY #0
        LDA #9
        JSR SET_CURSOR_XYA
        LDA #$FC
        STA ZP_COLOR
        LDA #<STR_TITLE
        LDY #>STR_TITLE
        JSR DRAW_STR_AY

        ; Kompas-richting op (432, 182)
        LDX #<432
        LDY #>432
        LDA #182
        JSR SET_CURSOR_XYA
        LDA #$1F
        STA ZP_COLOR
        LDA #<STR_KOMPAS
        LDY #>STR_KOMPAS
        JSR DRAW_STR_AY
        LDA #$FC
        STA ZP_COLOR
        LDX PDIR
        LDA DIR_NAME_LO,X
        LDY DIR_NAME_HI,X
        JSR DRAW_STR_AY

        ; Verdieping & Levenspunten op (432, 198)
        LDX #<432
        LDY #>432
        LDA #198
        JSR SET_CURSOR_XYA
        LDA #$FF
        STA ZP_COLOR
        LDA #<STR_VERD
        LDY #>STR_VERD
        JSR DRAW_STR_AY
        LDA P_FLOOR
        JSR DRAW_DEC_A

        ; HP op (432, 214)
        LDX #<432
        LDY #>432
        LDA #214
        JSR SET_CURSOR_XYA
        LDA #$1C
        STA ZP_COLOR
        LDA #<STR_HP
        LDY #>STR_HP
        JSR DRAW_STR_AY
        LDA P_HP
        JSR DRAW_DEC_A
        LDA #'/'
        JSR DRAW_CHAR_ADV
        LDA P_MAXHP
        JSR DRAW_DEC_A

        ; Kracht & Goud op (432, 230)
        LDX #<432
        LDY #>432
        LDA #230
        JSR SET_CURSOR_XYA
        LDA #$FC
        STA ZP_COLOR
        LDA #<STR_ATK
        LDY #>STR_ATK
        JSR DRAW_STR_AY
        LDA P_ATK
        JSR DRAW_DEC_A
        LDA #<STR_GOUD
        LDY #>STR_GOUD
        JSR DRAW_STR_AY
        LDA P_GOLD
        JSR DRAW_DEC_A

        ; Sleutels & Elixer-drankjes op (432, 246)
        LDX #<432
        LDY #>432
        LDA #246
        JSR SET_CURSOR_XYA
        LDA #$1F
        STA ZP_COLOR
        LDA #<STR_SLEUTEL
        LDY #>STR_SLEUTEL
        JSR DRAW_STR_AY
        LDA P_KEYS
        JSR DRAW_DEC_A
        LDA #<STR_DRANK
        LDY #>STR_DRANK
        JSR DRAW_STR_AY
        LDA P_POTS
        JSR DRAW_DEC_A

        ; Actief Status- / Gevechtsbericht op (32, 274)
        LDX #32
        LDY #0
        LDA #274-256            ; Let op: Y=270..340! Zet ZP_Y_HI=1!
        STX ZP_X_LO
        STY ZP_X_HI
        LDA #<274
        STA ZP_Y_LO
        LDA #>274
        STA ZP_Y_HI
        LDA #$FC
        STA ZP_COLOR

        LDA #<MSG_POOL
        STA ZP_PTR_LO
        LDA #>MSG_POOL
        STA ZP_PTR_HI
        LDX MSG_ID
        BEQ DHT_MGO
DHT_MSK:
        LDY #0
        LDA (ZP_PTR_LO),Y
        INC ZP_PTR_LO
        BNE DHT_M1
        INC ZP_PTR_HI
DHT_M1: CMP #0
        BNE DHT_MSK
        DEX
        BNE DHT_MSK
DHT_MGO:
        JSR DRAW_PTR_STR

        ; Hulpbalk onderaan op (32, 332)
        LDA #32
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<332
        STA ZP_Y_LO
        LDA #>332
        STA ZP_Y_HI
        LDA #$1F
        STA ZP_COLOR
        LDA #<STR_HELP
        LDY #>STR_HELP
        JSR DRAW_STR_AY
        LDA #0
        STA ZP_Y_HI
        RTS

; ============================================================================
; MiniGPU Primitieven & Tekst-Hulproutines
; ============================================================================
GPU_FILL_RECT:
        LDA #2
        STA IO_GPU
        LDA ZP_X_LO
        STA IO_GPU
        LDA ZP_X_HI
        STA IO_GPU
        LDA ZP_Y_LO
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_W_LO
        STA IO_GPU
        LDA ZP_W_HI
        STA IO_GPU
        LDA ZP_H_LO
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_COLOR
        STA IO_GPU
        RTS

GPU_HLINE_W:
        STA ZP_X_LO
        STY ZP_Y_LO
        LDA #1
        STA ZP_H_LO
        JMP GPU_FILL_RECT

SET_CURSOR_XYA:
        STX ZP_X_LO
        STY ZP_X_HI
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        RTS

DRAW_STR_AY:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DRAW_PTR_STR:
        LDY #0
DPS_LP: LDA (ZP_PTR_LO),Y
        BEQ DPS_R
        STY SAV_Y
        JSR DRAW_CHAR_ADV
        LDY SAV_Y
        INY
        BNE DPS_LP
DPS_R:  RTS

DRAW_DEC_A:
        LDY #'0'
        SEC
DDA_100:
        SBC #100
        BCC DDA_10A
        INY
        BNE DDA_100
DDA_10A:
        ADC #100
        PHA
        TYA
        CMP #'0'
        BEQ DDA_10B
        JSR DRAW_CHAR_ADV
DDA_10B:
        PLA
        LDY #'0'
        SEC
DDA_10: SBC #10
        BCC DDA_1
        INY
        BNE DDA_10
DDA_1:  ADC #10+'0'
        PHA
        TYA
        CMP #'0'
        BEQ DDA_2
        JSR DRAW_CHAR_ADV
DDA_2:  PLA
        JMP DRAW_CHAR_ADV

DRAW_CHAR_ADV:
        JSR DRAW_CHAR_ONLY
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCA_R
        INC ZP_X_HI
DCA_R:  RTS

DRAW_CHAR_ONLY:
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
        LDA ZP_COLOR
        STA IO_GPU
        RTS

SEND_STREAM_X:
        LDY GPU_STREAMS,X
SSX_L:  INX
        LDA GPU_STREAMS,X
        STA IO_GPU
        DEY
        BNE SSX_L
        RTS

; ============================================================================
; 3D Perspectief Tabellen, Richtingen & Monster-Statistieken
; ============================================================================
; Viewport (X = 24..384, Y = 28..252, W = 360, H = 224, Centrum = 204, 140)
VP_XL_LO:       .BYTE 24,  68,  112, 148, 172
VP_XR_LO:       .BYTE <384,<340,<296,<260,236
VP_XR_HI:       .BYTE >384,>340,>296,>260,0
VP_W_LO:        .BYTE <360,<272,<184,112, 64
VP_W_HI:        .BYTE >360,>272,0,   0,   0
VP_DX:          .BYTE 44,  44,  36,  24
VP_YT:          .BYTE 28,  56,  84,  106, 121
VP_YB:          .BYTE 252, 224, 196, 174, 159
VP_H:           .BYTE 224, 168, 112, 68,  38

FRONT_COL_TBL:  .BYTE $B6, $92, $6D, $49, $24
SIDE_COL_TBL:   .BYTE $92, $6D, $49, $24

; Deur / Trap afmetingen op diepte d = 0..3
DOOR_X:         .BYTE 140, 150, 168, 182
DOOR_Y:         .BYTE 60,  86,  108, 122
DOOR_W:         .BYTE 128, 108, 72,  44
DOOR_H:         .BYTE 192, 138, 88,  52

; 3D Object & Monster afmetingen op diepte d = 0..3
ENT_BOX_X:      .BYTE 164, 168, 180, 190
ENT_BOX_W:      .BYTE 80,  72,  48,  28
ENT_FLOOR_Y:    .BYTE 180, 178, 166, 154
ENT_BOX_H:      .BYTE 44,  38,  26,  16
ENT_BODY_Y:     .BYTE 110, 118, 128, 134
ENT_BODY_H:     .BYTE 90,  88,  56,  34
ENT_HEAD_Y:     .BYTE 88,  98,  114, 124
ENT_RAD:        .BYTE 24,  20,  14,  9

; Kleuren voor [0]=Kist, [1]=Drank, [2]=Ork, [3]=Skelet, [4]=Draak
ENT_COL_BODY:   .BYTE $88, $1C, $18, $DB, $C0
ENT_COL_HEAD:   .BYTE $FC, $1F, $1C, $FF, $E0

; Monster stats: [0]=Ork, [1]=Skelet, [2]=Vuur-Draak
MON_START_HP:   .BYTE 14, 22, 40
MON_ATK_TBL:    .BYTE 3,  5,  8
MON_GOLD_TBL:   .BYTE 25, 45, 100

; Automap kleuren per tegeltype (0..8, nooit $E3 gebruiken want $E3 = transparant!)
MAP_COL_TBL:    .BYTE $24, $6D, $FC, $1F, $F4, $1C, $E0, $E0, $C3

; Richtingsvectoren: 0=Noord, 1=Oost, 2=Zuid, 3=West
DIR_DX:         .BYTE 0,  1,  0,  $FF
DIR_DY:         .BYTE $FF,0,  1,  0
SIDE_DX:        .BYTE 1,  0,  $FF,0
SIDE_DY:        .BYTE 0,  1,  0,  $FF
DIR_CHARS:      .BYTE '^', '>', 'v', '<'

; 3x3 Fog-of-War onthullings-offsets rond de speler
REV_DX:         .BYTE $FF, 0, 1, $FF, 0, 1, $FF, 0, 1
REV_DY:         .BYTE $FF,$FF,$FF, 0, 0, 0,  1,  1, 1

; ============================================================================
; GPU Streams (Dubbel-Gebufferd 3D Kader, Zwaard & Geluidseffecten)
; ============================================================================
GPU_STREAMS:
GS_BG_3D:
        .BYTE GS_SWORD_IDLE - GS_BG_3D - 1
        .BYTE 21, 0, 0, 0,0, 0,0, 0                     ; Zet BigSprite 0 uit
        .BYTE 21, 1, 0, 0,0, 0,0, 0                     ; Zet BigSprite 1 uit
        .BYTE 12, 0                                     ; Render naar Back-Buffer!
        .BYTE 1, $00                                    ; Wis scherm zwart
        ; Bovenbalk (X=16..623, Y=6..20, donkerblauw $02)
        .BYTE 2, 16,0, 6,0, $60,$02, 14,0, $02
        ; 3D Plafond (X=24..384, Y=28..140, donker leisteen $01 + $24)
        .BYTE 2, 24,0, 28,0, $68,$01, 56,0, $01
        .BYTE 2, 24,0, 84,0, $68,$01, 56,0, $24
        ; 3D Vloer (X=24..384, Y=140..252, kerkervloer $44 + $20)
        .BYTE 2, 24,0, 140,0, $68,$01, 56,0, $20
        .BYTE 2, 24,0, 196,0, $68,$01, 56,0, $44
        ; Rechts Automap-paneel (X=416..616, Y=28..252, $01)
        .BYTE 2, $A0,$01, 28,0, 200,0, 224,0, $01
        ; Onderste Statusbalk (X=16..623, Y=264..348, $01)
        .BYTE 2, 16,0, 8,1, $60,$02, 84,0, $01

GS_SWORD_IDLE:
        .BYTE GS_SWORD_SLASH - GS_SWORD_IDLE - 1
        ; Zwaard-gevest & stalen kling rechtsonder in 3D-viewport
        .BYTE 7, <330,>330, 250,0, <350,>350, 250,0, <310,>310, 178,0, $FF
        .BYTE 2, <326,>326, 236,0, 28,0, 6,0, $FC

GS_SWORD_SLASH:
        .BYTE GS_SFX_STEP - GS_SWORD_SLASH - 1
        ;Zwaard-zwaai dwars door het midden van het 3D-beeld + vonken!
        .BYTE 7, <320,>320, 244,0, <342,>342, 236,0, 186,0, 118,0, $FF
        .BYTE 5, 204,0, 136,0, 10,0, 0,0, $FC

GS_SFX_STEP:
        .BYTE GS_SFX_THUD - GS_SFX_STEP - 1
        .BYTE 16, 0, $80, $04, $00, 90

GS_SFX_THUD:
        .BYTE GS_SFX_SWORD - GS_SFX_THUD - 1
        .BYTE 16, 0, $20, $03, $00, 180

GS_SFX_SWORD:
        .BYTE GS_SFX_TREAS - GS_SFX_SWORD - 1
        .BYTE 16, 0, $00, $16, $00, 200

GS_SFX_TREAS:
        .BYTE GS_EXIT - GS_SFX_TREAS - 1
        .BYTE 16, 0, $00, $24, $00, 210
        .BYTE 16, 1, $00, $30, $00, 180

GS_EXIT:
        .BYTE 4
        .BYTE 12, 1, 1, $E3

; ============================================================================
; Tekst-Strings & Statusberichten
; ============================================================================
STR_TITLE:      .ASCIIZ "KERKERS VAN TWENTE - 3D DUNGEON CRAWLER"
STR_KOMPAS:     .ASCIIZ "KOMPAS: "
STR_VERD:       .ASCIIZ "VERDIEPING: "
STR_HP:         .ASCIIZ "HP: "
STR_ATK:        .ASCIIZ "KRACHT:"
STR_GOUD:       .ASCIIZ " GOUD:"
STR_SLEUTEL:    .ASCIIZ "SLEUTEL:"
STR_DRANK:      .ASCIIZ " DRANK:"
STR_HELP:       .ASCIIZ "W/S:Loop A/D:Draai Q/E:Zij SPATIE:Zwaard H:Drank R:Nieuw ESC:Stop"

DIR_N:          .ASCIIZ "NOORD"
DIR_E:          .ASCIIZ "OOST"
DIR_S:          .ASCIIZ "ZUID"
DIR_W:          .ASCIIZ "WEST"
DIR_NAME_LO:    .BYTE <DIR_N, <DIR_E, <DIR_S, <DIR_W
DIR_NAME_HI:    .BYTE >DIR_N, >DIR_E, >DIR_S, >DIR_W

MSG_POOL:
        .ASCIIZ "WELKOM IN DE KERKERS VAN TWENTE! ZOEK DE DRAAK!"         ; 0
        .ASCIIZ "STEENWERK BLOKKEERT JE PAD."                             ; 1
        .ASCIIZ "MET DE SLEUTEL OPEN JE DE KERKERDEUR!"                   ; 2
        .ASCIIZ "DEUR ZIT OP SLOT! ZOEK EEN SLEUTEL."                     ; 3
        .ASCIIZ "SCHATKIST! +40 GOUD, +1 SLEUTEL & ZWAARD +2!"            ; 4
        .ASCIIZ "JE VINDT EEN ELIXER (+1 DRANK)!"                         ; 5
        .ASCIIZ "JE DAALT AF NAAR EEN DIEPERE VERDIEPING!"                ; 6
        .ASCIIZ "ELIXER GEDRONKEN: +16 HP HERSTELD!"                      ; 7
        .ASCIIZ "GEEN DRANKJES MEER IN JE TAS!"                           ; 8
        .ASCIIZ "VOLTREFFER! HET MONSTER SLAAT TERUG!"                    ; 9
        .ASCIIZ "MONSTER VERSLAGEN! GOUD BUITGEMAAKT!"                    ; 10
        .ASCIIZ "GESNEUVELD! DRUK OP R VOOR NIEUW SPEL."                  ; 11
        .ASCIIZ "JE ZWAAIT JE ZWAARD DOOR DE DUISTERE GANG."              ; 12

; ============================================================================
; 16x16 Kerker-Labyrint Template (256 Bytes)
; 0=Gang, 1=Muur, 2=Deur, 3=Trap, 4=Kist, 5=Drank, 6=Ork, 7=Skelet, 8=Draak
; ============================================================================
DUNGEON_TEMPLATE:
        .BYTE 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
        .BYTE 1,0,0,0,1,0,0,6,0,0,1,4,0,5,1,1
        .BYTE 1,0,1,0,1,0,1,1,1,0,1,1,2,1,1,1
        .BYTE 1,0,1,0,0,0,0,0,1,0,0,0,0,6,0,1
        .BYTE 1,0,1,1,1,2,1,0,1,1,1,1,1,1,0,1
        .BYTE 1,0,0,6,1,0,1,0,0,0,5,1,4,1,0,1
        .BYTE 1,1,1,0,1,4,1,1,1,1,0,1,0,1,0,1
        .BYTE 1,5,0,0,1,1,1,0,0,7,0,2,0,7,0,1
        .BYTE 1,0,1,1,1,0,0,0,1,1,1,1,1,1,0,1
        .BYTE 1,0,0,0,2,0,1,0,1,4,0,0,7,1,0,1
        .BYTE 1,1,1,0,1,0,1,0,1,0,1,1,0,1,0,1
        .BYTE 1,4,1,0,1,5,1,7,1,0,1,8,0,2,0,1
        .BYTE 1,0,1,0,1,1,1,0,1,0,1,3,1,1,1,1
        .BYTE 1,0,0,6,0,0,0,0,1,0,1,1,1,4,5,1
        .BYTE 1,1,1,1,1,1,1,0,0,0,2,0,0,0,0,1
        .BYTE 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
