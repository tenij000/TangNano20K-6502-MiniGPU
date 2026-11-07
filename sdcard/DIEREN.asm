; ============================================================================
; DIEREN.asm v1.0 - Twentse Boerderij Geluiden & 720p Soundboard Studio
; Geassembleerd voor $8000 (Past in 1 SD-slot van 4 KB, naast MC op $9000!)
;
; Combineert de 720p Geanimeerde Twentse Boerderij ($A006 = 3) met een
; 100 Hz 4-Kanaals 16-Bit Stereo Formant-, Glissando- & Vibrato-Synthesizer:
;   [1] KOE (Moooooo!)             [5] VARKEN (Knor & Wiiiiie!)
;   [2] SCHAAP & LAMMETJE (Bèèèh!) [6] PAARD (Hinniken & Galop-Hoeven!)
;   [3] HAAN (Kukelekuuuuu!)       [7] EEND (Kwaak!) & ZANGVOGELTJES
;   [4] RODE TRACTOR (Diesel!)     [8] DORPSKERK & OCHTEND-SYMFONIE
;
; Besturing:
;   [1]..[8]                     : Speel direct dit Boerderij-geluid!
;   [Pijltjes / WASD] + [SPATIE] : Kies knop & speel af
;   [A]                          : Auto-Boerderij Sfeer-Modus AAN / UIT
;   [V]                          : Wissel Soundboard / Full 720p Boerderij View
;   [B]                          : Wissel 720p Boerderij / Space achtergrond
;   [ESC] / [Q]                  : Stop geluid & keer terug naar BASIC / MC
; ============================================================================

        .ORG $8000

; --- Hardware I/O Registers ---
IO_STATUS       = $A000         ; Bit 0 = char ready, Bit 7 = ESC ingedrukt
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer (1 tick = 10 ms)
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_RND          = $A005         ; Hardware LFSR Random byte
IO_MODE         = $A006         ; 0=MODE 1, 1=MODE 0, 3=Farm, 5=Space, 6=Toggle
IO_INST         = $A00A         ; 16-Bit Stereo Sound Card Instrument Register
IO_FX           = $A00B         ; 16-Bit Stereo Sound Card FX / ADSR Register
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- Zero-Page Variabelen ($50..$8E) ---
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
ZP_SAV_X        = $5A
ZP_SAV_Y        = $5B
ITER_IDX        = $5C
ZP_W_HI_TMP     = $5D

CUR_PAD         = $60           ; Geselecteerde Boerderij-knop (0..7)
IS_ACT          = $61           ; 1 = Geluid speelt nu af, 0 = Stil
AUTO_FARM       = $62           ; 1 = Live Boerderij Sfeer-modus AAN, 0 = UIT
AUTO_WAIT       = $63           ; Afteller tussen automatische boerderijgeluiden
PANO_VIEW       = $64           ; 0 = Soundboard onderin, 1 = Full 720p Boerderij
LAST_TIMER      = $65           ; Laatste $A003 waarde
LAST_JOY        = $66           ; Edge-detect voor pijltjes
TICK_PHASE      = $67           ; 100 Hz teller voor vibrato/tremolo

SEG_PTR_LO      = $68           ; Pointer naar huidig 12-byte segment
SEG_PTR_HI      = $69
SEG_REM         = $6A           ; Resterende ticks (10 ms) in huidig segment
SEG_MODE        = $6B           ; Flags & modulatie-type van huidig segment

CH0_W_LO        = $70           ; 16-bit frequentie CH0 (inc[15:8])
CH0_W_HI        = $71           ; (inc[23:16])
CH0_DELTA       = $72           ; Signed 8-bit pitch slope per tick
CH0_VOL         = $73           ; Huidig volume CH0 (0..255)
CH0_VDELTA      = $74           ; Signed 8-bit volume slope per tick

CH1_W_LO        = $75           ; 16-bit frequentie CH1
CH1_W_HI        = $76
CH1_VOL         = $77

CH2_W_LO        = $78           ; 16-bit frequentie CH2 (Sub-Bass)
CH2_W_HI        = $79
CH2_VOL         = $7A

CH3_VOL         = $7B           ; Volume CH3 (Noise/Percussie)
CH3_DECAY       = $7C
CH3_MID         = $7D
CH3_HI          = $7E

EFF_W_LO        = $80           ; Tijdelijke gemoduleerde frequentie
EFF_W_HI        = $81
EFF_VOL         = $82

BSRAM_EXIT_MC   = $02D8         ; Veilige exit-stub terug naar BASIC / MC

; ============================================================================
; Hoofdprogramma Start
; ============================================================================
START:
        CLD
        ; Schakel direct de 720p Geanimeerde Twentse Boerderij in ($A006 = 3)!
        LDA #3
        STA IO_MODE

        LDA #0
        STA CUR_PAD
        STA PANO_VIEW
        STA LAST_JOY
        STA TICK_PHASE
        LDA #1
        STA AUTO_FARM           ; Start met Live Boerderij Sfeer-Modus AAN!
        LDA #120
        STA AUTO_WAIT

        LDA IO_TIMER
        STA LAST_TIMER

        JSR DRAW_FULL_SCREEN
        ; Laat bij het opstarten meteen de Twentse Koe ("Moooooo!") horen!
        LDA #0
        JSR START_SOUND_A

; ============================================================================
; Hoofdlus: 100 Hz Formant-Synthesizer + VU-Meter + Toetsenbord
; ============================================================================
MAIN_LOOP:
        LDA IO_TIMER
        CMP LAST_TIMER
        BEQ CHK_INPUT
        STA LAST_TIMER
        INC TICK_PHASE
        JSR UPDATE_SYNTH_TICK
        JSR DRAW_LIVE_VU

CHK_INPUT:
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
        AND #$01                ; Omhoog (-4)
        BNE PAD_UP
        TYA
        AND #$02                ; Omlaag (+4)
        BNE PAD_DOWN
        TYA
        AND #$04                ; Links (-1)
        BNE PAD_LEFT
        TYA
        AND #$08                ; Rechts (+1)
        BNE PAD_RIGHT
        TYA
        AND #$10                ; Vuurknop = Speel huidig geluid
        BNE TRIG_CUR_PAD

        LDA IO_STATUS
        AND #$01
        BEQ MAIN_LOOP
        LDA IO_TERM

        CMP #$1B                ; ESC
        BNE NOT_ESC_K
        JMP QUIT_TO_BASIC
NOT_ESC_K:
        CMP #'a'
        BCC UPPER_OK
        CMP #'z'+1
        BCS UPPER_OK
        AND #$DF
UPPER_OK:
        CMP #'Q'
        BNE NOT_Q_K
        JMP QUIT_TO_BASIC
NOT_Q_K:
        CMP #'1'
        BCC NOT_DIG_K
        CMP #'8'+1
        BCS NOT_DIG_K
        SEC
        SBC #'1'
        STA CUR_PAD
        JSR DRAW_ALL_PADS
        LDA CUR_PAD
        JSR START_SOUND_A
        JMP MAIN_LOOP
NOT_DIG_K:
        CMP #' '
        BEQ TRIG_CUR_PAD
        CMP #$0D                ; Enter
        BEQ TRIG_CUR_PAD
        CMP #'W'
        BEQ PAD_UP
        CMP #'S'
        BEQ PAD_DOWN
        CMP #'A'
        BEQ TOGGLE_AUTO_FARM
        CMP #'D'
        BEQ PAD_RIGHT
        CMP #'V'
        BEQ TOGGLE_PANO
        CMP #'B'
        BEQ TOGGLE_BG_THEME
        CMP #'X'
        BEQ STOP_NOW
        CMP #'K'
        BNE NOT_K_COW
        LDA #0
        JMP SET_NEW_PAD
NOT_K_COW:
        JMP MAIN_LOOP

PAD_UP:
        LDA CUR_PAD
        SEC
        SBC #4
        AND #7
        JMP SET_NEW_PAD
PAD_DOWN:
        LDA CUR_PAD
        CLC
        ADC #4
        AND #7
        JMP SET_NEW_PAD
PAD_LEFT:
        LDA CUR_PAD
        SEC
        SBC #1
        AND #7
        JMP SET_NEW_PAD
PAD_RIGHT:
        LDA CUR_PAD
        CLC
        ADC #1
        AND #7
SET_NEW_PAD:
        STA CUR_PAD
        JSR DRAW_ALL_PADS
        LDA CUR_PAD
        JSR START_SOUND_A
        JMP MAIN_LOOP

TRIG_CUR_PAD:
        LDA CUR_PAD
        JSR START_SOUND_A
        JMP MAIN_LOOP

TOGGLE_AUTO_FARM:
        LDA AUTO_FARM
        EOR #1
        STA AUTO_FARM
        LDA #60
        STA AUTO_WAIT
        JSR DRAW_STATUS_BAR
        JMP MAIN_LOOP

TOGGLE_PANO:
        LDA PANO_VIEW
        EOR #1
        STA PANO_VIEW
        JSR DRAW_FULL_SCREEN
        JMP MAIN_LOOP

TOGGLE_BG_THEME:
        LDA #6                  ; Wissel 720p Boerderij <-> 3D Space
        STA IO_MODE
        JMP MAIN_LOOP

STOP_NOW:
        JSR SILENCE_ALL_AUDIO
        JSR DRAW_ALL_PADS
        JSR DRAW_STATUS_BAR
        JMP MAIN_LOOP

; ============================================================================
; Start Boerderij-Geluid A (0..7)
; ============================================================================
START_SOUND_A:
        AND #7
        STA CUR_PAD
        JSR SILENCE_ALL_AUDIO

        ; Stel Stereo FX in voor dit geluid
        LDX CUR_PAD
        LDA SND_FX_TBL,X
        STA IO_FX

        ; Stel de 4 16-Bit Instrumenten in ($A00A: 16 + ch*16 + inst)
        TXA
        ASL A
        ASL A
        TAY
        LDX #0
SSA_INST_LP:
        TXA
        ASL A
        ASL A
        ASL A
        ASL A
        ORA #$10
        ORA SND_INST_TBL,Y
        STA IO_INST
        INY
        INX
        CPX #4
        BCC SSA_INST_LP

        ; Zet SEG_PTR_LO/HI op het eerste 12-byte segment van dit geluid
        LDX CUR_PAD
        LDA SND_PTR_LO,X
        STA SEG_PTR_LO
        LDA SND_PTR_HI,X
        STA SEG_PTR_HI

        LDA #1
        STA IS_ACT
        JSR LOAD_NEXT_SEGMENT
        JSR DRAW_ALL_PADS
        JMP DRAW_STATUS_BAR

; ============================================================================
; Laad het volgende 12-byte Segment vanaf (SEG_PTR_LO)
; ============================================================================
LOAD_NEXT_SEGMENT:
        LDY #0
        LDA (SEG_PTR_LO),Y      ; Byte 0 = SEG_TICKS (0 = Einde!)
        BNE LNS_HAS_SEG
        ; Einde van dit boerderijgeluid bereikt!
        JSR SILENCE_ALL_AUDIO
        LDA #140                ; Wacht ~1.4 sec voor volgend Auto-Boerderij geluid
        STA AUTO_WAIT
        JSR DRAW_ALL_PADS
        JMP DRAW_STATUS_BAR

LNS_HAS_SEG:
        STA SEG_REM
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 1 = SEG_MODE
        STA SEG_MODE
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 2 = CH0_W_LO
        STA CH0_W_LO
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 3 = CH0_W_HI
        STA CH0_W_HI
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 4 = CH0_DELTA
        STA CH0_DELTA
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 5 = CH0_VOL
        STA CH0_VOL
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 6 = CH0_VDELTA
        STA CH0_VDELTA
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 7 = CH1_W_LO
        STA CH1_W_LO
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 8 = CH1_W_HI
        STA CH1_W_HI
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 9 = CH1_VOL
        STA CH1_VOL
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 10 = CH2_W_LO
        STA CH2_W_LO
        LDA #0
        STA CH2_W_HI
        LDA #230
        STA CH2_VOL
        INY
        LDA (SEG_PTR_LO),Y      ; Byte 11 = CH3_DRM (0..4)
        BEQ LNS_ADV_PTR
        TAY
        ; Trigger CH3 percussie/ruis/uitlaat
        LDX #3
        LDA #0
        STA EFF_VOL
        JSR SEND_CH_X_EFF
        LDA DRM_INIT_VOL,Y
        STA CH3_VOL
        LDA DRM_INIT_DECAY,Y
        STA CH3_DECAY
        LDA DRM_INIT_MID,Y
        STA CH3_MID
        LDA DRM_INIT_HI,Y
        STA CH3_HI

LNS_ADV_PTR:
        CLC
        LDA SEG_PTR_LO
        ADC #12
        STA SEG_PTR_LO
        BCC LNS_RTS
        INC SEG_PTR_HI
LNS_RTS:
        JMP APPLY_SYNTH_FRAME

; ============================================================================
; 100 Hz Update van Glissando, Formanten, Vibrato & Auto-Boerderij
; ============================================================================
UPDATE_SYNTH_TICK:
        LDA IS_ACT
        BNE UST_ACTIVE

        ; Als stil en AUTO_FARM == 1: tel AUTO_WAIT af en start volgend dier!
        LDA AUTO_FARM
        BEQ UST_RTS
        LDA AUTO_WAIT
        BEQ UST_NEXT_AUTO
        DEC AUTO_WAIT
UST_RTS:
        RTS

UST_NEXT_AUTO:
        LDX CUR_PAD
        INX
        CPX #8
        BCC UST_NA_OK
        LDX #0
UST_NA_OK:
        TXA
        JMP START_SOUND_A

UST_ACTIVE:
        DEC SEG_REM
        BNE UST_STEP_GLIDE
        JMP LOAD_NEXT_SEGMENT

UST_STEP_GLIDE:
        ; 1. Pas signed 8-bit CH0_DELTA toe op 16-bit CH0_W_LO/HI
        LDA CH0_DELTA
        BEQ UST_VOL_UPD
        BMI UST_DELTA_NEG
        CLC
        ADC CH0_W_LO
        STA CH0_W_LO
        BCC UST_VOL_UPD
        INC CH0_W_HI
        JMP UST_VOL_UPD
UST_DELTA_NEG:
        CLC
        ADC CH0_W_LO
        STA CH0_W_LO
        BCS UST_VOL_UPD
        DEC CH0_W_HI

UST_VOL_UPD:
        ; 2. Pas signed 8-bit CH0_VDELTA toe op CH0_VOL (geclampt op 8..255)
        LDA CH0_VDELTA
        BEQ UST_CH3_UPD
        BMI UST_VD_NEG
        CLC
        ADC CH0_VOL
        BCC UST_VD_ST
        LDA #255
        JMP UST_VD_ST
UST_VD_NEG:
        CLC
        ADC CH0_VOL
        BCS UST_VD_MIN
        LDA #8
        JMP UST_VD_ST
UST_VD_MIN:
        CMP #8
        BCS UST_VD_ST
        LDA #8
UST_VD_ST:
        STA CH0_VOL

UST_CH3_UPD:
        ; 3. Laat CH3 ruis/percussie uitsterven
        LDA CH3_VOL
        BEQ APPLY_SYNTH_FRAME
        SEC
        SBC CH3_DECAY
        BCS UST_CH3_OK
        LDA #0
UST_CH3_OK:
        STA CH3_VOL

; ============================================================================
; Bereken Formanten & Modulatie en stuur naar alle 4 de 16-Bit Kanalen
; ============================================================================
APPLY_SYNTH_FRAME:
        ; --- Kanaal 0 (Hoofdstem + Vibrato / Tremolo) ---
        LDA CH0_W_LO
        STA EFF_W_LO
        LDA CH0_W_HI
        STA EFF_W_HI
        LDA CH0_VOL
        STA EFF_VOL
        BEQ ASF_SEND_CH0

        ; Check Modulatie-type in bits 7..6 van SEG_MODE
        LDA SEG_MODE
        AND #$C0
        BEQ ASF_SEND_CH0
        CMP #$40                ; MOD_COW_VIB (Zachte 6 Hz keel-vibrato)
        BEQ ASF_MOD_COW
        CMP #$80                ; MOD_BLEAT (Snelle 16 Hz Schaap/Haan/Paard vibrato + tremolo)
        BEQ ASF_MOD_BLEAT

        ; MOD_GRUNT ($C0: Varken-knor / Tractor-ratel / Eend-rasp: elke tick +/-)
        LDA TICK_PHASE
        AND #1
        BEQ ASF_SEND_CH0
        LDA EFF_W_LO
        CLC
        ADC #38
        STA EFF_W_LO
        BCC ASF_GR_V
        INC EFF_W_HI
ASF_GR_V:
        LDA EFF_VOL
        SEC
        SBC #65
        BCS ASF_GR_VST
        LDA #40
ASF_GR_VST:
        STA EFF_VOL
        JMP ASF_SEND_CH0

ASF_MOD_COW:
        LDA TICK_PHASE
        LSR A
        AND #7
        TAY
        LDA VIB_TRI_COW,Y
        CLC
        ADC EFF_W_LO
        STA EFF_W_LO
        BCC ASF_SEND_CH0
        INC EFF_W_HI
        JMP ASF_SEND_CH0

ASF_MOD_BLEAT:
        LDA TICK_PHASE
        AND #7
        TAY
        LDA VIB_TRI_BLEAT,Y
        CLC
        ADC EFF_W_LO
        STA EFF_W_LO
        BCC ASF_BL_V
        INC EFF_W_HI
ASF_BL_V:
        LDA EFF_VOL
        SEC
        SBC TREM_BLEAT,Y
        BCS ASF_BL_VST
        LDA #40
ASF_BL_VST:
        STA EFF_VOL

ASF_SEND_CH0:
        LDX #0
        JSR SEND_CH_X_EFF

        ; --- Kanaal 1 (Nasale Formant 1.5x of Onafhankelijke Stem) ---
        LDA SEG_MODE
        AND #$20                ; FLG_HARM_15X?
        BEQ ASF_CH1_FIXED
        ; Bereken 1.5x van EFF_W (EFF_W + EFF_W/2) voor echte vocale formant!
        LDA EFF_W_HI
        LSR A
        STA ZP_SAV_Y
        LDA EFF_W_LO
        ROR A
        CLC
        ADC EFF_W_LO
        STA EFF_W_LO
        LDA EFF_W_HI
        ADC ZP_SAV_Y
        STA EFF_W_HI
        LDA CH1_VOL
        STA EFF_VOL
        JMP ASF_SEND_CH1

ASF_CH1_FIXED:
        LDA CH1_W_LO
        STA EFF_W_LO
        LDA CH1_W_HI
        STA EFF_W_HI
        LDA CH1_VOL
        STA EFF_VOL
ASF_SEND_CH1:
        LDX #1
        JSR SEND_CH_X_EFF

        ; --- Kanaal 2 (Diepe Borstkas Sub-Bass 0.5x of Vaste Bas) ---
        LDA SEG_MODE
        AND #$10                ; FLG_SUB_05X?
        BEQ ASF_CH2_FIXED
        LDA CH0_W_HI
        LSR A
        STA EFF_W_HI
        LDA CH0_W_LO
        ROR A
        STA EFF_W_LO
        LDA CH0_VOL
        STA EFF_VOL
        JMP ASF_SEND_CH2

ASF_CH2_FIXED:
        LDA CH2_W_LO
        STA EFF_W_LO
        LDA CH2_W_HI
        STA EFF_W_HI
        LDA CH2_VOL
        STA EFF_VOL
        LDA CH2_W_LO
        BNE ASF_SEND_CH2
        LDA #0
        STA EFF_VOL
ASF_SEND_CH2:
        LDX #2
        JSR SEND_CH_X_EFF

        ; --- Kanaal 3 (16-Bit 808 Ruis / Uitlaat / Snavel / Hoef) ---
        LDA CH3_MID
        STA EFF_W_LO
        LDA CH3_HI
        STA EFF_W_HI
        LDA CH3_VOL
        STA EFF_VOL
        LDX #3
        JMP SEND_CH_X_EFF

; Stuur GPU CMD 16 voor kanaal X met EFF_W_LO (inc_mid), EFF_W_HI (inc_hi), EFF_VOL
SEND_CH_X_EFF:
        LDA #16
        STA IO_GPU
        STX IO_GPU
        LDA #0                  ; inc_lo = 0
        STA IO_GPU
        LDA EFF_W_LO            ; inc_mid
        STA IO_GPU
        LDA EFF_W_HI            ; inc_hi
        STA IO_GPU
        LDA EFF_VOL             ; volume
        STA IO_GPU
        RTS

SILENCE_ALL_AUDIO:
        LDA #0
        STA IS_ACT
        STA CH0_VOL
        STA CH1_VOL
        STA CH2_VOL
        STA CH3_VOL
        STA EFF_VOL
        STA EFF_W_LO
        STA EFF_W_HI
        LDX #0
SAA_LP:
        JSR SEND_CH_X_EFF
        INX
        CPX #4
        BCC SAA_LP
        RTS

; ============================================================================
; Grafisch 720p Boerderij Soundboard Dashboard (Onderin Y=228..359!)
; ============================================================================
DRAW_FULL_SCREEN:
        ; Wis het hele 640x360 scherm naar $E3 (100% transparant voor 720p Boerderij!)
        LDX #0
DFS_CLR:
        LDA CLR_E3_STREAM,X
        STA IO_GPU
        INX
        CPX #(CLR_E3_STREAM_END - CLR_E3_STREAM)
        BCC DFS_CLR

        LDA PANO_VIEW
        BEQ DFS_SOUNDBOARD

        ; --- Full-Screen 720p Boerderij Modus (alleen slanke balk op Y=338..359) ---
        LDX #10
        JSR SEND_RECT_10
        JMP DRAW_STATUS_BAR

DFS_SOUNDBOARD:
        ; --- Soundboard Dashboard onderin beeld (Y=228..359, bovenste 228px is 720p Boerderij!) ---
        LDX #0
DFS_GUI:
        LDA SB_GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #(SB_GUI_STREAM_END - SB_GUI_STREAM)
        BCC DFS_GUI

        LDA #<STR_SB_HDRS
        STA ZP_PTR_LO
        LDA #>STR_SB_HDRS
        STA ZP_PTR_HI
        JSR DRAW_TEXT_LIST

        JSR DRAW_ALL_PADS
        JMP DRAW_STATUS_BAR

; Teken de 8 Boerderij Geluid-Knoppen (2 rijen van 4 knoppen in Y=252..312)
DRAW_ALL_PADS:
        LDA PANO_VIEW
        BNE DAP_RTS
        LDX #0
DAP_LP:
        STX ITER_IDX
        LDA PAD_X_LO,X
        STA ZP_X_LO
        LDA PAD_X_HI,X
        STA ZP_X_HI
        LDA PAD_Y_TBL,X
        STA ZP_Y_LO
        LDA #150
        STA ZP_W_LO
        LDA #26
        STA ZP_H_LO

        LDA #$01                ; Donkerblauw voor inactieve knop
        CPX CUR_PAD
        BNE DAP_BG_OK
        LDA #$FC                ; Goudgeel voor geselecteerde boerderij-knop!
        LDY IS_ACT
        BEQ DAP_BG_OK
        LDA #$1C                ; Felgroen terwijl het dier geluid maakt!
DAP_BG_OK:
        STA ZP_COL
        JSR DRAW_RECT_ZP

        ; Teken de naam van het dier op de knop (max 17 tekens)
        LDX ITER_IDX
        LDA PAD_X_LO,X
        CLC
        ADC #6
        STA ZP_X_LO
        LDA PAD_X_HI,X
        ADC #0
        STA ZP_X_HI
        LDA PAD_Y_TBL,X
        CLC
        ADC #9
        STA ZP_Y_LO

        LDA #$FF
        CPX CUR_PAD
        BNE DAP_FG_OK
        LDA #$00
DAP_FG_OK:
        STA ZP_FG_COL
        LDA SND_NAME_LO,X
        LDY SND_NAME_HI,X
        JSR DRAW_AY_STR_17

        LDX ITER_IDX
        INX
        CPX #8
        BCC DAP_LP
DAP_RTS:
        RTS

; Teken de Statusbalk onderin (Y=342)
DRAW_STATUS_BAR:
        LDX #0
        JSR SEND_RECT_10

        ; 1. Actief boerderijgeluid op X=12, Y=345
        LDA #12
        LDY #(345 & $FF)
        JSR SET_XY_345
        LDA #$FC
        STA ZP_FG_COL
        LDX CUR_PAD
        LDA SND_NAME_LO,X
        LDY SND_NAME_HI,X
        JSR DRAW_AY_STR

        ; 2. Auto-Boerderij Sfeer status op X=210, Y=345
        LDA #210
        LDY #(345 & $FF)
        JSR SET_XY_345
        LDA AUTO_FARM
        BEQ DSB_MANUAL
        LDA #$1C
        STA ZP_FG_COL
        LDA #<STR_AUTO_ON
        LDY #>STR_AUTO_ON
        JMP DSB_PRT_A
DSB_MANUAL:
        LDA #$FF
        STA ZP_FG_COL
        LDA #<STR_AUTO_OFF
        LDY #>STR_AUTO_OFF
DSB_PRT_A:
        JSR DRAW_AY_STR

        ; 3. Sneltoetsen rechtsonder op X=356, Y=345
        LDA #<356
        STA ZP_X_LO
        LDA #>356
        STA ZP_X_HI
        LDA #$FF
        STA ZP_FG_COL
        LDA #<STR_KEYS_HELP
        LDY #>STR_KEYS_HELP
        JMP DRAW_AY_STR

; Teken Live Bewegende VU-Balk tijdens het boerderijgeluid!
DRAW_LIVE_VU:
        LDA PANO_VIEW
        BNE DLV_RTS
        ; Wis VU-strook op X=436, Y=233, W=190, H=10
        LDX #20
        JSR SEND_RECT_10

        LDA CH0_VOL
        ORA CH1_VOL
        ORA CH3_VOL
        LSR A
        BEQ DLV_RTS
        CMP #188
        BCC DLV_W_OK
        LDA #188
DLV_W_OK:
        STA ZP_W_LO
        LDA #<436
        STA ZP_X_LO
        LDA #>436
        STA ZP_X_HI
        LDA #233
        STA ZP_Y_LO
        LDA #10
        STA ZP_H_LO
        LDA #$1C
        STA ZP_COL
        JMP DRAW_RECT_ZP
DLV_RTS:
        RTS

; ============================================================================
; Afsluiten naar BASIC / Midnight Commander
; ============================================================================
QUIT_TO_BASIC:
        JSR SILENCE_ALL_AUDIO
        LDX #7
QTB_CP:
        LDA EXIT_STUB_TBL,X
        STA BSRAM_EXIT_MC,X
        DEX
        BPL QTB_CP
        JMP BSRAM_EXIT_MC

EXIT_STUB_TBL:
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

; ============================================================================
; GPU & Tekst Hulproutines
; ============================================================================
DRAW_RECT_ZP:
        LDA #0
        STA ZP_Y_HI
        STA ZP_W_HI_TMP
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
        LDA ZP_W_LO
        STA IO_GPU
        LDA ZP_W_HI_TMP
        STA IO_GPU
        LDA ZP_H_LO
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

SET_XY_345:
        STA ZP_X_LO
        STY ZP_Y_LO
        LDA #0
        STA ZP_X_HI
        LDA #1
        STA ZP_Y_HI
        RTS

DRAW_TEXT_LIST:
        JSR NEXT_PTR_BYTE
        BNE DTL_HAS
        RTS
DTL_HAS:
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

DRAW_AY_STR_17:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDA #17
        STA ZP_SAV_X
DAS17_LP:
        JSR NEXT_PTR_BYTE
        BEQ DAS17_RTS
        JSR DRAW_CHAR_ADV
        DEC ZP_SAV_X
        BNE DAS17_LP
DAS17_RTS:
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
; Coördinaten, GUI Streams & De 8 Boerderij Geluid-Modellen
; ============================================================================
PAD_X_LO:
        .BYTE 10, 168, (326 & $FF), (484 & $FF)
        .BYTE 10, 168, (326 & $FF), (484 & $FF)
PAD_X_HI:
        .BYTE 0,  0,   (326 >> 8),  (484 >> 8)
        .BYTE 0,  0,   (326 >> 8),  (484 >> 8)
PAD_Y_TBL:
        .BYTE 254, 254, 254, 254
        .BYTE 286, 286, 286, 286

; 16-Bit Percussie/Ruis presets voor CH3 (0=Off, 1=Chug/Hoof, 2=Quack/Snort, 3=Click, 4=Breeze)
DRM_INIT_VOL:
        .BYTE 0, 240, 230, 190, 210
DRM_INIT_DECAY:
        .BYTE 0, 45,  32,  75,  14
DRM_INIT_MID:
        .BYTE 0, $18, $E8, $80, $20
DRM_INIT_HI:
        .BYTE 0, $00, $00, $06, $04

; Vloeiende 8-staps driehoek-vibrato & tremolo tabellen
VIB_TRI_COW:
        .BYTE 0, 2, 4, 6, 4, 2, 0, 1
VIB_TRI_BLEAT:
        .BYTE 0, 8, 18, 26, 18, 8, 0, 4
TREM_BLEAT:
        .BYTE 0, 25, 55, 80, 55, 25, 0, 10

CLR_E3_STREAM:
        .BYTE 12, 1
        .BYTE 1, $E3
CLR_E3_STREAM_END:

SB_GUI_STREAM:
        ; Soundboard kader onderin beeld (Y=228..359) zodat de 720p Boerderij vrij blijft!
        .BYTE 2, 0,0, 226,0, $80,$02, 2,0,  $FC
        .BYTE 2, 0,0, 228,0, $80,$02, 20,0, $48
        .BYTE 2, 0,0, 248,0, $80,$02, 90,0, $24
        .BYTE 2, 0,0, (338 & $FF),(338 >> 8), $80,$02, 22,0, $00
SB_GUI_STREAM_END:

UI_RECT_TBL:
        ; Offset 0: Wis onderste statusbalk (0, 338, 640, 22, $00)
        .BYTE 2, 0,0, (338 & $FF),(338 >> 8), $80,$02, 22,0, $00
        ; Offset 10: Gouden bovenlijn voor Pano-balk (0, 336, 640, 2, $FC)
        .BYTE 2, 0,0, (336 & $FF),(336 >> 8), $80,$02, 2,0,  $FC
        ; Offset 20: Wis VU-meter balk (436, 233, 190, 10, $00)
        .BYTE 2, (436 & $FF),(436 >> 8), 233,0, 190,0, 10,0, $00

STR_SB_HDRS:
        .BYTE 12,0, 234,0, $FC, "TWENTSE BOERDERIJ GELUIDEN STUDIO [1-8]", 0
        .BYTE (396 & $FF),(396 >> 8), 234,0, $1C, "VU:", 0
        .BYTE 12,0, (320 & $FF),(320 >> 8), $FF, "[1-8/PIJL+SPATIE] Speel Dier  [A] Auto-Boerderij  [V] 720p View  [ESC] Uit", 0
        .BYTE 0

STR_AUTO_ON:    .ASCIIZ "SFEER:AAN [A]"
STR_AUTO_OFF:   .ASCIIZ "SFEER:UIT [A]"
STR_KEYS_HELP:  .ASCIIZ "1-8:Geluid V:720p B:Bg ESC:Uit"

SND_FX_TBL:
        .BYTE $07, $0F, $0F, $07, $07, $0F, $07, $07

SND_INST_TBL:
        .BYTE 4, 1, 2, 7
        .BYTE 4, 1, 3, 7
        .BYTE 4, 1, 2, 7
        .BYTE 4, 1, 2, 7
        .BYTE 4, 1, 2, 7
        .BYTE 4, 0, 3, 7
        .BYTE 4, 1, 6, 7
        .BYTE 4, 6, 1, 7

SND_PTR_LO:
        .BYTE <SND_SEGS_0, <SND_SEGS_1, <SND_SEGS_2, <SND_SEGS_3, <SND_SEGS_4, <SND_SEGS_5, <SND_SEGS_6, <SND_SEGS_7
SND_PTR_HI:
        .BYTE >SND_SEGS_0, >SND_SEGS_1, >SND_SEGS_2, >SND_SEGS_3, >SND_SEGS_4, >SND_SEGS_5, >SND_SEGS_6, >SND_SEGS_7

SND_NAME_LO:
        .BYTE <STR_SND_0, <STR_SND_1, <STR_SND_2, <STR_SND_3, <STR_SND_4, <STR_SND_5, <STR_SND_6, <STR_SND_7
SND_NAME_HI:
        .BYTE >STR_SND_0, >STR_SND_1, >STR_SND_2, >STR_SND_3, >STR_SND_4, >STR_SND_5, >STR_SND_6, >STR_SND_7

STR_SND_0: .ASCIIZ "1.KOE (MOOOOOO!)      "
STR_SND_1: .ASCIIZ "2.SCHAAP & LAMMETJE   "
STR_SND_2: .ASCIIZ "3.HAAN (KUKELEKUUU!)  "
STR_SND_3: .ASCIIZ "4.RODE TRACTOR DIESEL "
STR_SND_4: .ASCIIZ "5.VARKEN (KNOR & WIIE)"
STR_SND_5: .ASCIIZ "6.PAARD & HOEFGETRAPPEL"
STR_SND_6: .ASCIIZ "7.EEND & ZANGVOGELTJES"
STR_SND_7: .ASCIIZ "8.DORPSKERK & OCHTEND "

SND_SEGS_0: ; 1.KOE (MOOOOOO!) (6 segs)
        .BYTE $18, $20, $B1, $00, $03, $8C, $05, $00, $00, $E1, $B1, $01
        .BYTE $34, $60, $FE, $00, $FF, $FF, $00, $00, $00, $F5, $FB, $00
        .BYTE $2E, $60, $E0, $00, $FE, $FA, $FC, $00, $00, $DC, $BF, $00
        .BYTE $12, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $12, $20, $CA, $00, $04, $96, $06, $00, $00, $DC, $CA, $01
        .BYTE $2A, $60, $14, $01, $FD, $F5, $FC, $00, $00, $E6, $FD, $00
        .BYTE $00
SND_SEGS_1: ; 2.SCHAAP & LAMMETJE (7 segs)
        .BYTE $06, $20, $2C, $01, $12, $D2, $08, $00, $00, $DC, $00, $02
        .BYTE $30, $B0, $B5, $01, $FF, $FA, $00, $00, $00, $E6, $00, $00
        .BYTE $10, $A0, $85, $01, $FB, $E1, $F5, $00, $00, $B9, $00, $00
        .BYTE $0F, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $05, $20, $66, $02, $18, $D2, $09, $00, $00, $D2, $00, $00
        .BYTE $26, $A0, $EF, $02, $FE, $FA, $FF, $00, $00, $DC, $00, $00
        .BYTE $0F, $A0, $A4, $02, $F8, $D2, $F4, $00, $00, $AA, $00, $00
        .BYTE $00
SND_SEGS_2: ; 3.HAAN (KUKELEKUUU!) (8 segs)
        .BYTE $0D, $20, $EF, $02, $0C, $FA, $00, $00, $00, $E1, $77, $00
        .BYTE $05, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $0D, $20, $77, $03, $0E, $FF, $00, $00, $00, $EB, $BC, $00
        .BYTE $05, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $0D, $20, $1F, $03, $0A, $FA, $00, $00, $00, $E1, $8F, $00
        .BYTE $05, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $30, $B0, $DA, $04, $01, $FF, $00, $00, $00, $F0, $00, $00
        .BYTE $20, $A0, $03, $05, $EF, $F5, $FA, $00, $00, $C8, $00, $00
        .BYTE $00
SND_SEGS_3: ; 4.RODE TRACTOR DIESEL (16 segs)
        .BYTE $0A, $E0, $AB, $00, $FC, $FF, $F8, $00, $00, $F5, $AB, $02
        .BYTE $06, $00, $7B, $00, $00, $5A, $00, $B8, $00, $6E, $00, $03
        .BYTE $0A, $E0, $B8, $00, $FC, $FF, $F8, $00, $00, $F5, $B8, $02
        .BYTE $05, $00, $82, $00, $00, $5F, $00, $C2, $00, $73, $00, $03
        .BYTE $09, $E0, $CA, $00, $FC, $FF, $F8, $00, $00, $FA, $CA, $02
        .BYTE $04, $00, $8F, $00, $00, $64, $00, $D4, $00, $78, $00, $03
        .BYTE $06, $E0, $D4, $00, $FB, $FF, $F6, $00, $00, $F0, $D4, $01
        .BYTE $03, $00, $96, $00, $00, $6E, $00, $00, $00, $00, $00, $03
        .BYTE $06, $E0, $DA, $00, $FB, $FF, $F6, $00, $00, $F0, $DA, $02
        .BYTE $03, $00, $96, $00, $00, $6E, $00, $00, $00, $00, $00, $03
        .BYTE $06, $E0, $DD, $00, $FB, $FF, $F6, $00, $00, $F0, $DD, $01
        .BYTE $03, $00, $9D, $00, $00, $6E, $00, $00, $00, $00, $00, $03
        .BYTE $06, $E0, $E5, $00, $FB, $FF, $F6, $00, $00, $F5, $E5, $02
        .BYTE $03, $00, $A4, $00, $00, $73, $00, $00, $00, $00, $00, $04
        .BYTE $28, $E0, $C6, $00, $04, $FF, $00, $00, $00, $FA, $F6, $02
        .BYTE $20, $E0, $5C, $01, $FB, $F5, $FA, $00, $00, $E1, $C6, $04
        .BYTE $00
SND_SEGS_4: ; 5.VARKEN (KNOR & WIIE) (8 segs)
        .BYTE $10, $E0, $AB, $00, $05, $FF, $FD, $00, $00, $F5, $B1, $02
        .BYTE $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $10, $E0, $B4, $00, $05, $FF, $FD, $00, $00, $FA, $BC, $02
        .BYTE $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $12, $E0, $A4, $00, $06, $FF, $FD, $00, $00, $FF, $AF, $02
        .BYTE $07, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $18, $60, $74, $02, $20, $FF, $00, $00, $00, $EB, $00, $00
        .BYTE $1A, $A0, $3A, $05, $F0, $FA, $F8, $00, $00, $D7, $00, $00
        .BYTE $00
SND_SEGS_5: ; 6.PAARD & HOEFGETRAPPEL (21 segs)
        .BYTE $12, $A0, $8C, $05, $F2, $FF, $00, $00, $00, $D2, $00, $04
        .BYTE $14, $A0, $60, $04, $F0, $F5, $FE, $00, $00, $C3, $00, $00
        .BYTE $12, $E0, $8F, $02, $EE, $F0, $F9, $00, $00, $D2, $00, $04
        .BYTE $09, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $07, $00, $C6, $02, $D3, $FF, $EE, $8C, $05, $FA, $00, $01
        .BYTE $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $07, $00, $A0, $03, $C9, $FF, $EE, $41, $07, $FA, $00, $03
        .BYTE $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $08, $00, $60, $04, $BF, $FF, $EE, $BF, $08, $FF, $00, $02
        .BYTE $0B, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $07, $00, $C6, $02, $D3, $FA, $EE, $8C, $05, $F5, $00, $01
        .BYTE $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $07, $00, $A0, $03, $C9, $FA, $EE, $41, $07, $F5, $00, $03
        .BYTE $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $08, $00, $60, $04, $BF, $FF, $EE, $BF, $08, $FA, $00, $02
        .BYTE $0B, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $07, $00, $C6, $02, $D3, $D2, $F0, $8C, $05, $CD, $00, $01
        .BYTE $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $07, $00, $A0, $03, $C9, $D2, $F0, $41, $07, $CD, $00, $03
        .BYTE $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $08, $00, $60, $04, $BF, $DC, $F0, $BF, $08, $D7, $00, $02
        .BYTE $00
SND_SEGS_6: ; 7.EEND & ZANGVOGELTJES (15 segs)
        .BYTE $0F, $E0, $C6, $02, $F2, $FF, $FC, $00, $00, $FA, $00, $02
        .BYTE $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $0F, $E0, $E1, $02, $F1, $FF, $FC, $00, $00, $FF, $00, $02
        .BYTE $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $12, $E0, $AB, $02, $F3, $FF, $FB, $00, $00, $F5, $00, $02
        .BYTE $0C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $09, $00, $CD, $08, $55, $F0, $FB, $BC, $0B, $C3, $00, $00
        .BYTE $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $09, $00, $55, $09, $5A, $F5, $FB, $89, $0C, $C8, $00, $00
        .BYTE $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $16, $80, $89, $0C, $E7, $F5, $F9, $66, $0A, $C8, $00, $00
        .BYTE $08, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $0E, $00, $2E, $04, $00, $F5, $FB, $5D, $08, $82, $00, $00
        .BYTE $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $18, $00, $84, $03, $00, $FA, $FA, $08, $07, $82, $00, $00
        .BYTE $00
SND_SEGS_7: ; 8.DORPSKERK & OCHTEND (6 segs)
        .BYTE $18, $00, $63, $09, $2D, $C8, $F9, $CA, $02, $FF, $EF, $00
        .BYTE $10, $80, $33, $0B, $E2, $B9, $F8, $CA, $02, $AA, $EF, $00
        .BYTE $0E, $00, $2E, $04, $00, $E6, $FA, $17, $02, $FF, $C9, $00
        .BYTE $18, $00, $84, $03, $00, $EB, $FA, $17, $02, $AA, $C9, $00
        .BYTE $16, $20, $BC, $00, $03, $B4, $04, $00, $00, $E6, $EF, $00
        .BYTE $2E, $60, $01, $01, $FE, $FF, $FC, $00, $00, $F0, $C9, $00
        .BYTE $00
