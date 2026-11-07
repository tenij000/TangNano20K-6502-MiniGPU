; ============================================================================
; JUKEBOX.asm v1.0 - MiniGPU 16-Bit 48kHz Stereo Music Jukebox & Visualizer
; Geassembleerd voor $8000 (Past in 1 SD-slot van 4 KB, naast MC op $9000!)
;
; 8 Complete 4-Kanaals 16-Bit Stereo Liedjes (32 stappen x 4 sporen):
;   1. Fuer Elise (Beethoven FM)      - Piano FM + Strings + Sub Bass + 808
;   2. Axel F (Synthwave 1984)        - Brass FM + Piano FM + Sub Bass + 808
;   3. Popcorn (Stereo Bells)         - FM Bells + Hammond + Sub Bass + 808
;   4. Twentse Ode an die Freude      - Gitaar + Hammond + Sub Bass + 808
;   5. Super Mario Overworld FM       - Brass FM + Gitaar + Sub Bass + 808
;   6. Tetris Korobeiniki Dance       - Hammond + Gitaar + Sub Bass + 808
;   7. Space Odyssey (Oxygene 4)      - Strings (Vibrato) + FM Bells + Sub Bass
;   8. Pirates of the Caribbean       - Brass FM + Strings + Sub Bass + 808
; ============================================================================

        .ORG $8000

; --- Hardware I/O Registers ---
IO_STATUS       = $A000         ; Bit 0 = char ready, Bit 7 = ESC ingedrukt
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer (1 tick = 10 ms)
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0=MODE 1, 1=MODE 0, 3=Farm, 5=Space, 6=Toggle
IO_INST         = $A00A         ; 16-Bit Stereo Sound Card Instrument Register
IO_FX           = $A00B         ; 16-Bit Stereo Sound Card FX / ADSR Register
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- Zero-Page Variabelen ($50..$8D) ---
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
ITER_CH         = $5C
ITER_STEP       = $5D

CUR_SONG        = $60           ; Huidig liedje (0..7)
IS_PLAYING      = $61           ; 1 = Playing, 0 = Paused
PLAY_STEP       = $62           ; Huidige stap (0..31)
SPEED_TICKS     = $63           ; Ticks (10 ms) per 16e stap
TICK_ACCUM      = $64           ; Tick teller
LAST_TIMER      = $65           ; Laatste $A003 waarde
LAST_JOY        = $66           ; Edge-detect voor pijltjes
AUTO_DJ         = $67           ; 1 = Auto-DJ aan (wissel na 2 loops), 0 = Loop
LOOP_CNT        = $68           ; Aantal loops van huidig liedje
PANO_MODE       = $69           ; 0 = Volledige Studio UI, 1 = 720p Panorama Balk

ENV_VOL         = $70           ; $70..$73: Actueel VU-volume per kanaal 0..3
CH_NOTE         = $74           ; $74..$77: Actieve noot (1..48) of drum (1..4)
CH_INST         = $78           ; $78..$7B: Actief 16-Bit instrument (0..7) per spoor
DRM_FREQ_MID    = $7C
DRM_FREQ_HI     = $7D
DRM_DECAY       = $7E
CUR_FX          = $7F           ; 0 = Stereo ($07), 1 = Vibrato ($0F), 2 = Chip8 ($01)
ACTIVE_SEMI     = $80           ; $80..$82: Actieve halve toon (0..11 of $FF) voor CH0..CH2
ZP_W_HI_TMP     = $8B
ZP_SONG_LO      = $8C           ; Pointer naar huidig liedje (112 bytes in SONG_BLOBS)
ZP_SONG_HI      = $8D

BSRAM_EXIT_MC   = $02D8         ; Veilige exit-stub terug naar BASIC / MC

; ============================================================================
; Hoofdprogramma Start
; ============================================================================
START:
        CLD
        LDA #1
        STA IO_MODE             ; MODE 0 + 720p Boerderij/Space actief
        STA IS_PLAYING
        STA AUTO_DJ
        LDA #0
        STA PANO_MODE
        STA LAST_JOY
        STA LOOP_CNT

        LDA IO_TIMER
        STA LAST_TIMER

        LDA #0
        JSR LOAD_SONG_A
        JSR DRAW_FULL_UI
        JSR TRIGGER_CURRENT_STEP

; ============================================================================
; Hoofdlus: 100 Hz Audio Sequencer + VU-Meters + Toetsenbord
; ============================================================================
MAIN_LOOP:
        LDA IO_TIMER
        CMP LAST_TIMER
        BEQ CHK_INPUT
        STA LAST_TIMER
        JSR UPDATE_AUDIO_TICK
        JSR DRAW_LIVE_VISUALS

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
        AND #$05                ; Omhoog of Links = Vorig liedje
        BNE PREV_SONG_JMP
        TYA
        AND #$0A                ; Omlaag of Rechts = Volgend liedje
        BNE NEXT_SONG_JMP

        LDA IO_STATUS
        AND #$01
        BEQ MAIN_LOOP
        LDA IO_TERM

        CMP #$1B                ; ESC
        BNE NOT_ESC_KEY
        JMP QUIT_TO_BASIC
NOT_ESC_KEY:
        CMP #'a'
        BCC KEY_UPPER_OK
        CMP #'z'+1
        BCS KEY_UPPER_OK
        AND #$DF
KEY_UPPER_OK:
        CMP #'Q'
        BNE NOT_Q_KEY
        JMP QUIT_TO_BASIC
NOT_Q_KEY:
        CMP #'1'
        BCC NOT_DIGIT_SONG
        CMP #'8'+1
        BCS NOT_DIGIT_SONG
        SEC
        SBC #'1'
        JSR SELECT_NEW_SONG_A
        JMP MAIN_LOOP
NOT_DIGIT_SONG:
        CMP #' '
        BEQ TOGGLE_PLAY
        CMP #'P'
        BEQ TOGGLE_PLAY
        CMP #'N'
        BEQ NEXT_SONG_JMP
        CMP #'S'
        BEQ NEXT_SONG_JMP
        CMP #'W'
        BEQ PREV_SONG_JMP
        CMP #'A'
        BEQ TOGGLE_AUTODJ
        CMP #'I'
        BEQ REMIX_CH0_INST
        CMP #$09
        BEQ REMIX_CH0_INST
        CMP #'H'
        BEQ REMIX_CH1_INST
        CMP #'F'
        BEQ CYCLE_FX_MODE
        CMP #'V'
        BEQ TOGGLE_PANO_VIEW
        CMP #'B'
        BEQ TOGGLE_FARM_SPACE
        CMP #'K'
        BEQ PLAY_COW_MOO
        CMP #'+'
        BEQ SPEED_FASTER
        CMP #'='
        BEQ SPEED_FASTER
        CMP #']'
        BEQ SPEED_FASTER
        CMP #'-'
        BEQ SPEED_SLOWER
        CMP #'['
        BEQ SPEED_SLOWER
        JMP MAIN_LOOP

PREV_SONG_JMP:
        LDX CUR_SONG
        DEX
        BPL PS_OK
        LDX #7
PS_OK:
        TXA
        JSR SELECT_NEW_SONG_A
        JMP MAIN_LOOP

NEXT_SONG_JMP:
        LDX CUR_SONG
        INX
        CPX #8
        BCC NS_OK
        LDX #0
NS_OK:
        TXA
        JSR SELECT_NEW_SONG_A
        JMP MAIN_LOOP

TOGGLE_PLAY:
        LDA IS_PLAYING
        EOR #1
        STA IS_PLAYING
        BNE TP_RESUME
        JSR SILENCE_ALL_AUDIO
        JMP TP_DRAW
TP_RESUME:
        LDA #0
        STA TICK_ACCUM
        JSR TRIGGER_CURRENT_STEP
TP_DRAW:
        JSR DRAW_HEADER_STATUS
        JMP MAIN_LOOP

TOGGLE_AUTODJ:
        LDA AUTO_DJ
        EOR #1
        STA AUTO_DJ
        LDA #0
        STA LOOP_CNT
        JSR DRAW_HEADER_STATUS
        JMP MAIN_LOOP

REMIX_CH0_INST:
        LDX #0
        JMP REMIX_CH_X
REMIX_CH1_INST:
        LDX #1
REMIX_CH_X:
        LDA CH_INST,X
        CLC
        ADC #1
        AND #7
        STA CH_INST,X
        JSR SYNC_ALL_CH_INST
        JSR DRAW_CHANNELS_PANEL
        JMP MAIN_LOOP

CYCLE_FX_MODE:
        LDX CUR_FX
        INX
        CPX #3
        BCC CFM_OK
        LDX #0
CFM_OK:
        STX CUR_FX
        LDA FX_VAL_TBL,X
        STA IO_FX
        JSR DRAW_HEADER_STATUS
        JMP MAIN_LOOP

TOGGLE_PANO_VIEW:
        LDA PANO_MODE
        EOR #1
        STA PANO_MODE
        JSR DRAW_FULL_UI
        JMP MAIN_LOOP

TOGGLE_FARM_SPACE:
        LDA #6
        STA IO_MODE
        JMP MAIN_LOOP

PLAY_COW_MOO:
        ; Toets [K]: Speel een echte Twentse Boerderij Koe ("Mooooo!") op CH3!
        LDX #3
        LDA #5
        JSR TRIGGER_CH_X_NOTE_A
        JMP MAIN_LOOP

SPEED_FASTER:
        LDA SPEED_TICKS
        CMP #6
        BCC SF_DONE
        DEC SPEED_TICKS
        JSR DRAW_HEADER_STATUS
SF_DONE:
        JMP MAIN_LOOP

SPEED_SLOWER:
        LDA SPEED_TICKS
        CMP #28
        BCS SS_DONE
        INC SPEED_TICKS
        JSR DRAW_HEADER_STATUS
SS_DONE:
        JMP MAIN_LOOP

SELECT_NEW_SONG_A:
        JSR LOAD_SONG_A
        LDA #1
        STA IS_PLAYING
        JSR DRAW_SONG_LIST_UPDATE
        JSR DRAW_HEADER_STATUS
        JSR DRAW_CHANNELS_PANEL
        JMP TRIGGER_CURRENT_STEP

; ============================================================================
; 100 Hz Audio Engine (48 kHz 16-Bit Stereo ADSR + Smart 808 Drum Kit)
; ============================================================================
UPDATE_AUDIO_TICK:
        LDX #0
UAT_MEL_LP:
        LDA ENV_VOL,X
        BEQ UAT_MEL_NXT
        SEC
        SBC #5
        BCS UAT_MEL_ST
        LDA #0
UAT_MEL_ST:
        STA ENV_VOL,X
        JSR SEND_CH_X_AUDIO
UAT_MEL_NXT:
        INX
        CPX #3
        BCC UAT_MEL_LP

        LDA ENV_VOL+3
        BEQ UAT_CHK_STEP
        SEC
        SBC DRM_DECAY
        BCS UAT_DRM_ST
        LDA #0
UAT_DRM_ST:
        STA ENV_VOL+3
        LDX #3
        JSR SEND_CH_X_AUDIO

UAT_CHK_STEP:
        LDA IS_PLAYING
        BEQ UAT_RTS
        INC TICK_ACCUM
        LDA TICK_ACCUM
        CMP SPEED_TICKS
        BCC UAT_RTS
        LDA #0
        STA TICK_ACCUM

        INC PLAY_STEP
        LDA PLAY_STEP
        CMP #32
        BCC UAT_TRIG
        LDA #0
        STA PLAY_STEP
        LDA AUTO_DJ
        BEQ UAT_TRIG
        INC LOOP_CNT
        LDA LOOP_CNT
        CMP #2
        BCC UAT_TRIG
        LDA #0
        STA LOOP_CNT
        LDX CUR_SONG
        INX
        CPX #8
        BCC UAT_ADJ_OK
        LDX #0
UAT_ADJ_OK:
        TXA
        JSR LOAD_SONG_A
        JSR DRAW_SONG_LIST_UPDATE
        JSR DRAW_CHANNELS_PANEL
UAT_TRIG:
        JSR TRIGGER_CURRENT_STEP
        JSR DRAW_HEADER_STATUS
UAT_RTS:
        RTS

; Trigger alle 4 sporen op PLAY_STEP (0..31) via (ZP_SONG_LO),Y
TRIGGER_CURRENT_STEP:
        LDX #0
TCS_LP:
        STX ITER_CH
        CPX #3
        BEQ TCS_DRUM_IDX
        TXA
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A                   ; ch * 32 (0, 32, 64)
        ORA PLAY_STEP
        TAY
        JMP TCS_FETCH
TCS_DRUM_IDX:
        LDA PLAY_STEP
        AND #15
        ORA #96                 ; CH3 staat op offset 96..111
        TAY
TCS_FETCH:
        LDA (ZP_SONG_LO),Y
        BEQ TCS_NXT             ; 0 = Sustain
        CMP #49
        BEQ TCS_REST_OFF        ; 49 = Staccato rust
        JSR TRIGGER_CH_X_NOTE_A
        JMP TCS_NXT
TCS_REST_OFF:
        LDA #0
        STA ENV_VOL,X
        STA CH_NOTE,X
        JSR SEND_CH_X_AUDIO
TCS_NXT:
        LDX ITER_CH
        INX
        CPX #4
        BCC TCS_LP
        RTS

TRIGGER_CH_X_NOTE_A:
        STA CH_NOTE,X
        LDA #0
        STA ENV_VOL,X
        JSR SEND_CH_X_AUDIO
        CPX #3
        BEQ TCXN_DRUM
        LDA CH_INIT_VOL,X
        STA ENV_VOL,X
        JMP SEND_CH_X_AUDIO

TCXN_DRUM:
        LDY CH_NOTE+3
        LDA DRM_INIT_VOL,Y
        STA ENV_VOL+3
        LDA DRM_INIT_DECAY,Y
        STA DRM_DECAY
        LDA DRM_INIT_MID,Y
        STA DRM_FREQ_MID
        LDA DRM_INIT_HI,Y
        STA DRM_FREQ_HI
        JMP SEND_CH_X_AUDIO

SEND_CH_X_AUDIO:
        LDA #16
        STA IO_GPU
        STX IO_GPU
        CPX #3
        BEQ SCXA_DRUM
        LDY CH_NOTE,X
        LDA NOTE_INC_LO,Y
        STA IO_GPU
        LDA NOTE_INC_MID,Y
        STA IO_GPU
        LDA NOTE_INC_HI,Y
        STA IO_GPU
        LDA ENV_VOL,X
        STA IO_GPU
        RTS
SCXA_DRUM:
        LDA #$00
        STA IO_GPU
        LDA DRM_FREQ_MID
        STA IO_GPU
        LDA DRM_FREQ_HI
        STA IO_GPU
        LDA ENV_VOL+3
        STA IO_GPU
        RTS

SILENCE_ALL_AUDIO:
        LDX #0
SAA_LP:
        LDA #0
        STA ENV_VOL,X
        JSR SEND_CH_X_AUDIO
        INX
        CPX #4
        BCC SAA_LP
        RTS

; ============================================================================
; Laad Liedje A (0..7) en stel 16-Bit Stereo Synth in
; ============================================================================
LOAD_SONG_A:
        AND #7
        STA CUR_SONG
        LDA #0
        STA PLAY_STEP
        STA TICK_ACCUM
        STA LOOP_CNT

        LDX CUR_SONG
        LDA SONG_SPEED_TBL,X
        STA SPEED_TICKS
        LDA SONG_FX_TBL,X
        STA CUR_FX
        TAY
        LDA FX_VAL_TBL,Y
        STA IO_FX

        LDA CUR_SONG
        ASL A
        ASL A
        TAY
        LDX #0
LSA_INST_LP:
        LDA SONG_INST_TBL,Y
        STA CH_INST,X
        INY
        INX
        CPX #4
        BCC LSA_INST_LP
        JSR SYNC_ALL_CH_INST

        ; Zet ZP_SONG_LO/HI op SONG_BLOBS + CUR_SONG * 112
        LDA #<SONG_BLOBS
        STA ZP_SONG_LO
        LDA #>SONG_BLOBS
        STA ZP_SONG_HI
        LDX CUR_SONG
        BEQ LSA_DONE
LSA_ADD_112:
        CLC
        LDA ZP_SONG_LO
        ADC #112
        STA ZP_SONG_LO
        BCC LSA_ADD_OK
        INC ZP_SONG_HI
LSA_ADD_OK:
        DEX
        BNE LSA_ADD_112
LSA_DONE:
        RTS

SYNC_ALL_CH_INST:
        LDX #0
SACI_LP:
        TXA
        ASL A
        ASL A
        ASL A
        ASL A
        ORA #$10
        ORA CH_INST,X
        STA IO_INST
        INX
        CPX #4
        BCC SACI_LP
        RTS

; ============================================================================
; Grafische Jukebox Interface & 720p Panorama Mini-Speler
; ============================================================================
DRAW_FULL_UI:
        LDX #0
DFU_CLR_LP:
        LDA CLR_E3_STREAM,X
        STA IO_GPU
        INX
        CPX #(CLR_E3_STREAM_END - CLR_E3_STREAM)
        BCC DFU_CLR_LP

        LDA PANO_MODE
        BEQ DFU_STUDIO
        LDX #0
DFU_PANO_LP:
        LDA PANO_GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #(PANO_GUI_STREAM_END - PANO_GUI_STREAM)
        BCC DFU_PANO_LP
        JMP DRAW_HEADER_STATUS

DFU_STUDIO:
        LDX #0
DFU_GUI_LP:
        LDA STUDIO_GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #(STUDIO_GUI_STREAM_END - STUDIO_GUI_STREAM)
        BCC DFU_GUI_LP

        LDA #<STR_STUDIO_HDRS
        STA ZP_PTR_LO
        LDA #>STR_STUDIO_HDRS
        STA ZP_PTR_HI
        JSR DRAW_TEXT_LIST

        JSR DRAW_SONG_LIST_UPDATE
        JSR DRAW_CHANNELS_PANEL
        JSR DRAW_HEADER_STATUS
        JMP DRAW_LIVE_VISUALS

DRAW_SONG_LIST_UPDATE:
        LDA PANO_MODE
        BNE DSL_RTS
        LDX #0
DSL_LP:
        STX ITER_STEP
        TXA
        ASL A
        STA ZP_Y_LO
        ASL A
        ASL A
        ASL A
        CLC
        ADC ZP_Y_LO
        ADC #64
        STA ZP_Y_LO

        LDA #14
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #244
        STA ZP_W_LO
        LDA #16
        STA ZP_H_LO
        LDA #$01
        CPX CUR_SONG
        BNE DSL_BG_OK
        LDA #$1F
DSL_BG_OK:
        STA ZP_COL
        JSR DRAW_RECT_ZP

        LDX ITER_STEP
        LDA #20
        STA ZP_X_LO
        CLC
        LDA ZP_Y_LO
        ADC #4
        STA ZP_Y_LO
        LDA #$FF
        CPX CUR_SONG
        BNE DSL_FG_OK
        LDA #$00
DSL_FG_OK:
        STA ZP_FG_COL
        LDA SONG_TITLE_LO,X
        LDY SONG_TITLE_HI,X
        JSR DRAW_AY_STR

        LDX ITER_STEP
        INX
        CPX #8
        BCC DSL_LP
DSL_RTS:
        RTS

DRAW_CHANNELS_PANEL:
        LDA PANO_MODE
        BNE DCP_RTS
        LDX #0
DCP_LP:
        STX ITER_CH
        LDA CH_ROW_Y,X
        STA ZP_Y_LO

        LDA #<278
        JSR SET_X_1XX
        LDA #126
        STA ZP_W_LO
        LDA #26
        STA ZP_H_LO
        LDA #$00
        STA ZP_COL
        JSR DRAW_RECT_ZP

        LDX ITER_CH
        LDA #<284
        JSR SET_X_1XX
        LDA CH_ROW_Y,X
        CLC
        ADC #4
        STA ZP_Y_LO
        LDA TRACK_ACT_COL,X
        STA ZP_FG_COL
        LDA #'C'
        JSR DRAW_CHAR_ADV
        LDA #'H'
        JSR DRAW_CHAR_ADV
        LDA ITER_CH
        CLC
        ADC #'0'
        JSR DRAW_CHAR_ADV
        LDA #':'
        JSR DRAW_CHAR_ADV

        LDX ITER_CH
        LDY CH_INST,X
        LDA INST_NAME_LO,Y
        PHA
        LDA INST_NAME_HI,Y
        TAY
        PLA
        JSR DRAW_AY_STR

        LDX ITER_CH
        INX
        CPX #4
        BCC DCP_LP
DCP_RTS:
        RTS

DRAW_HEADER_STATUS:
        LDA PANO_MODE
        BEQ DHS_STUDIO

        ; 720p Panorama Balk onderin (Y=324)
        LDX #10
        JSR SEND_RECT_10
        LDA #14
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<328
        STA ZP_Y_LO
        LDA #>328
        STA ZP_Y_HI
        LDA #$FC
        STA ZP_FG_COL
        LDX CUR_SONG
        LDA SONG_TITLE_LO,X
        LDY SONG_TITLE_HI,X
        JMP DRAW_AY_STR

DHS_STUDIO:
        LDX #0
        JSR SEND_RECT_10

        LDA #12
        LDY #24
        JSR SET_XY_POS
        LDA IS_PLAYING
        BEQ DHS_PAUSED
        LDA #$1C
        STA ZP_FG_COL
        LDA #<STR_PLAYING
        LDY #>STR_PLAYING
        JMP DHS_PRT_PL
DHS_PAUSED:
        LDA #$E0
        STA ZP_FG_COL
        LDA #<STR_PAUSED
        LDY #>STR_PAUSED
DHS_PRT_PL:
        JSR DRAW_AY_STR

        LDA #84
        LDY #24
        JSR SET_XY_POS
        LDA #$FC
        STA ZP_FG_COL
        LDX CUR_SONG
        LDA SONG_TITLE_LO,X
        LDY SONG_TITLE_HI,X
        JSR DRAW_AY_STR

        LDA #<308
        JSR SET_X_1XX
        LDA AUTO_DJ
        BEQ DHS_LOOP1
        LDA #$1F
        STA ZP_FG_COL
        LDA #<STR_AUTODJ_ON
        LDY #>STR_AUTODJ_ON
        JMP DHS_PRT_ADJ
DHS_LOOP1:
        LDA #$FF
        STA ZP_FG_COL
        LDA #<STR_AUTODJ_OFF
        LDY #>STR_AUTODJ_OFF
DHS_PRT_ADJ:
        JSR DRAW_AY_STR

        LDA #<428
        JSR SET_X_1XX
        LDA #$FF
        STA ZP_FG_COL
        LDA #<STR_STEP_LBL
        LDY #>STR_STEP_LBL
        JSR DRAW_AY_STR
        LDA PLAY_STEP
        CLC
        ADC #1
        JSR DRAW_HEX_BYTE

        LDA #<516
        STA ZP_X_LO
        LDA #>516
        STA ZP_X_HI
        LDA #$1C
        STA ZP_FG_COL
        LDX CUR_FX
        LDA FX_NAME_LO,X
        LDY FX_NAME_HI,X
        JMP DRAW_AY_STR

; ============================================================================
; Live VU-Meters, Noot-Indicators & 24-Toetsen Spook-Piano Visualizer
; ============================================================================
DRAW_LIVE_VISUALS:
        LDA PANO_MODE
        BEQ DLV_STUDIO

        LDX #0
DLV_PANO_LP:
        STX ITER_CH
        LDA #<270
        JSR SET_X_1XX
        TXA
        ASL A
        ASL A
        CLC
        ADC #<324
        STA ZP_Y_LO
        LDA #>324
        ADC #0
        STA ZP_Y_HI
        LDA #128
        STA ZP_W_LO
        LDA #3
        STA ZP_H_LO
        LDA #$00
        STA ZP_COL
        JSR DRAW_RECT_ANY_Y

        LDX ITER_CH
        LDA ENV_VOL,X
        LSR A
        BEQ DLV_PANO_NXT
        STA ZP_W_LO
        LDA TRACK_ACT_COL,X
        STA ZP_COL
        JSR DRAW_RECT_ANY_Y
DLV_PANO_NXT:
        LDX ITER_CH
        INX
        CPX #4
        BCC DLV_PANO_LP
        RTS

DLV_STUDIO:
        LDX #0
DLV_CH_LP:
        STX ITER_CH
        LDA #<408
        JSR SET_X_1XX
        LDA CH_ROW_Y,X
        CLC
        ADC #4
        STA ZP_Y_LO
        LDA #28
        STA ZP_W_LO
        LDA #10
        STA ZP_H_LO
        LDA #$00
        STA ZP_COL
        JSR DRAW_RECT_ZP

        LDX ITER_CH
        LDA #<410
        JSR SET_X_1XX
        LDA #$FF
        STA ZP_FG_COL
        LDA ENV_VOL,X
        BEQ DLV_NO_NOTE
        LDA CH_NOTE,X
        BEQ DLV_NO_NOTE
        CPX #3
        BEQ DLV_DRM_NOTE
        JSR DRAW_NOTE_3CHARS
        JMP DLV_VU_BAR
DLV_DRM_NOTE:
        LDY CH_NOTE+3
        LDA DRM_C0,Y
        JSR DRAW_CHAR_ADV
        LDA DRM_C1,Y
        JSR DRAW_CHAR_ADV
        LDA DRM_C2,Y
        JSR DRAW_CHAR_ADV
        JMP DLV_VU_BAR
DLV_NO_NOTE:
        LDA #$92
        STA ZP_FG_COL
        LDA #'-'
        JSR DRAW_CHAR_ADV
        LDA #'-'
        JSR DRAW_CHAR_ADV
        LDA #'-'
        JSR DRAW_CHAR_ADV

DLV_VU_BAR:
        LDX ITER_CH
        LDA #<448
        JSR SET_X_1XX
        LDA CH_ROW_Y,X
        CLC
        ADC #4
        STA ZP_Y_LO
        LDA #166
        STA ZP_W_LO
        LDA #18
        STA ZP_H_LO
        LDA #$24
        STA ZP_COL
        JSR DRAW_RECT_ZP

        LDX ITER_CH
        LDA ENV_VOL,X
        LSR A
        STA ZP_W_LO
        LSR A
        LSR A
        CLC
        ADC ZP_W_LO
        BEQ DLV_CH_NXT
        CMP #164
        BCC DLV_W_OK
        LDA #164
DLV_W_OK:
        STA ZP_W_LO
        LDA TRACK_ACT_COL,X
        STA ZP_COL
        JSR DRAW_RECT_ZP

DLV_CH_NXT:
        LDX ITER_CH
        INX
        CPX #4
        BCC DLV_CH_LP

        ; 32-Staps Progress-Bar (X=284, Y=198)
        LDX #20
        JSR SEND_RECT_10

        LDA PLAY_STEP
        ASL A
        STA ZP_SAV_X
        ASL A
        ASL A
        CLC
        ADC ZP_SAV_X
        ADC #<284
        STA ZP_X_LO
        LDA #>284
        ADC #0
        STA ZP_X_HI
        LDA #198
        STA ZP_Y_LO
        LDA #10
        STA ZP_W_LO
        LDA #6
        STA ZP_H_LO
        LDA #$FC
        STA ZP_COL
        JSR DRAW_RECT_ZP

; ============================================================================
; 24-Toetsen Live Spook-Piano Visualizer (X=16..380, Y=238..296)
; ============================================================================
DRAW_PIANO_VISUALIZER:
        LDX #0
DPV_SEMI_LP:
        LDA ENV_VOL,X
        CMP #24
        BCC DPV_NO_S
        LDA CH_NOTE,X
        BEQ DPV_NO_S
        CMP #49
        BCS DPV_NO_S
        SEC
        SBC #1
DPV_MOD12:
        CMP #12
        BCC DPV_GOT_S
        SBC #12
        BCS DPV_MOD12
DPV_NO_S:
        LDA #$FF
DPV_GOT_S:
        STA ACTIVE_SEMI,X
        INX
        CPX #3
        BCC DPV_SEMI_LP

        ; 1. Teken alle 24 toetsen (0..13 = wit, 14..23 = zwart) in 1 compacte lus!
        LDX #0
DPV_KEY_LP:
        STX ITER_STEP
        LDA WHITE_KEY_X,X
        STA ZP_X_LO
        LDA WHITE_KEY_XH,X
        STA ZP_X_HI
        LDA #238
        STA ZP_Y_LO
        LDA #$FF
        LDY #23
        CPX #14
        BCC DPV_IS_W
        LDA #$00
        LDY #15
DPV_IS_W:
        STA ZP_SAV_Y
        STY ZP_W_LO
        LDA #58
        CPX #14
        BCC DPV_H_OK
        LDA #34
DPV_H_OK:
        STA ZP_H_LO
        LDA WHITE_KEY_SEMI,X
        JSR GET_KEY_HIGHLIGHT
        STA ZP_COL
        JSR DRAW_RECT_ZP
        LDX ITER_STEP
        INX
        CPX #24
        BCC DPV_KEY_LP
        RTS

GET_KEY_HIGHLIGHT:
        CMP ACTIVE_SEMI
        BNE GKH_1
        LDA #$1F
        RTS
GKH_1:
        CMP ACTIVE_SEMI+1
        BNE GKH_2
        LDA #$EB
        RTS
GKH_2:
        CMP ACTIVE_SEMI+2
        BNE GKH_DEF
        LDA #$1C
        RTS
GKH_DEF:
        LDA ZP_SAV_Y
        RTS

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
DRAW_NOTE_3CHARS:
        SEC
        SBC #1
        LDY #'2'
DN3_MOD12:
        CMP #12
        BCC DN3_GOT_OCT
        SBC #12
        INY
        BNE DN3_MOD12
DN3_GOT_OCT:
        TAX
        TYA
        PHA
        LDA SEMI_CHAR0,X
        JSR DRAW_CHAR_ADV
        LDA SEMI_CHAR1,X
        JSR DRAW_CHAR_ADV
        PLA
        JMP DRAW_CHAR_ADV

DRAW_RECT_ZP:
        LDA #0
        STA ZP_Y_HI
DRAW_RECT_ANY_Y:
        LDA #0
        STA ZP_W_HI_TMP
DRAW_RECT_WIDE:
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

SET_X_1XX:
        STA ZP_X_LO
        LDA #1
        STA ZP_X_HI
        RTS

SET_XY_POS:
        STA ZP_X_LO
        STY ZP_Y_LO
        LDA #0
        STA ZP_X_HI
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
; Tabellen, GUI Streams, 48-Noot Frequenties & 8 Complete Stereo Liedjes
; ============================================================================
CH_ROW_Y:
        .BYTE 66, 98, 130, 162

TRACK_ACT_COL:
        .BYTE $1F, $EB, $1C, $FC

CH_INIT_VOL:
        .BYTE 230, 195, 245, 245

DRM_INIT_VOL:
        .BYTE 0, 250, 235, 195, 220, 255
DRM_INIT_DECAY:
        .BYTE 0, 58,  52,  85,  32,  6
DRM_INIT_MID:
        .BYTE 0, $18, $E8, $80, $20, $48
DRM_INIT_HI:
        .BYTE 0, $00, $00, $06, $04, $00

DRM_C0: .BYTE '-', 'K', 'S', 'H', 'O', 'K'
DRM_C1: .BYTE '-', 'C', 'N', 'A', 'P', 'O'
DRM_C2: .BYTE '-', 'K', 'R', 'T', 'N', 'E'

SEMI_CHAR0:
        .BYTE "CCDDEFFGGAAB"
SEMI_CHAR1:
        .BYTE "-#-#--#-#-#-"

WHITE_KEY_X:
        .BYTE 16, 42, 68, 94, 120, 146, 172, 198, 224, 250, 276, 302, 328, 354
        .BYTE 33, 59, 111, 137, 163, 215, 241, 37, 63, 89
WHITE_KEY_XH:
        .BYTE 0,  0,  0,  0,  0,   0,   0,   0,   0,   0,   1,   1,   1,   1
        .BYTE 0,  0,  0,   0,   0,   0,   0,   1,  1,  1
WHITE_KEY_SEMI:
        .BYTE 0,  2,  4,  5,  7,   9,   11,  0,   2,   4,   5,   7,   9,   11
        .BYTE 1,  3,  6,   8,   10,  1,   3,   6,  8,  10

INST_NAME_LO:
        .BYTE <STR_IN0, <STR_IN1, <STR_IN2, <STR_IN3, <STR_IN4, <STR_IN5, <STR_IN6, <STR_IN7
INST_NAME_HI:
        .BYTE >STR_IN0, >STR_IN1, >STR_IN2, >STR_IN3, >STR_IN4, >STR_IN5, >STR_IN6, >STR_IN7

STR_IN0:        .ASCIIZ "PIANO FM"
STR_IN1:        .ASCIIZ "HAMMOND "
STR_IN2:        .ASCIIZ "STRINGS "
STR_IN3:        .ASCIIZ "GITAAR  "
STR_IN4:        .ASCIIZ "BRASS FM"
STR_IN5:        .ASCIIZ "SUB BASS"
STR_IN6:        .ASCIIZ "FM BELLS"
STR_IN7:        .ASCIIZ "808 DRUM"

FX_VAL_TBL:
        .BYTE $07, $0F, $01
FX_NAME_LO:
        .BYTE <STR_FX0, <STR_FX1, <STR_FX2
FX_NAME_HI:
        .BYTE >STR_FX0, >STR_FX1, >STR_FX2
STR_FX0:        .ASCIIZ "FX:STEREO"
STR_FX1:        .ASCIIZ "FX:VIBRAT"
STR_FX2:        .ASCIIZ "FX:CHIP8 "

STR_PLAYING:    .ASCIIZ "[PLAY] "
STR_PAUSED:     .ASCIIZ "[PAUZE]"
STR_AUTODJ_ON:  .ASCIIZ "AUTO-DJ:AAN"
STR_AUTODJ_OFF: .ASCIIZ "LOOP:1 LIED"
STR_STEP_LBL:   .ASCIIZ "STAP:$"

CLR_E3_STREAM:
        .BYTE 12, 1
        .BYTE 1, $E3
CLR_E3_STREAM_END:

PANO_GUI_STREAM:
        .BYTE 2, 0,0, (318 & $FF),(318 >> 8), $80,$02, 42,0, $24
        .BYTE 2, 0,0, (318 & $FF),(318 >> 8), $80,$02, 2,0,  $FC
PANO_GUI_STREAM_END:

STUDIO_GUI_STREAM:
        .BYTE 2, 0,0, 0,0, $80,$02, 18,0, $C0
        .BYTE 2, 0,0, 18,0, $80,$02, 20,0, $24
        .BYTE 2, 8,0, 44,0, 0,1, 16,0, $48
        .BYTE 2, 8,0, 60,0, 0,1, 152,0, $01
        .BYTE 2, (272 & $FF),(272 >> 8), 44,0, (360 & $FF),(360 >> 8), 16,0, $48
        .BYTE 2, (272 & $FF),(272 >> 8), 60,0, (360 & $FF),(360 >> 8), 152,0, $00
        .BYTE 2, 8,0, 218,0, (624 & $FF),(624 >> 8), 16,0, $48
        .BYTE 2, 8,0, 234,0, (624 & $FF),(624 >> 8), 102,0, $24
        .BYTE 2, 0,0, (340 & $FF),(340 >> 8), $80,$02, 20,0, $48
STUDIO_GUI_STREAM_END:

UI_RECT_TBL:
        ; Offset 0: Wis Studio Transportbalk (0, 18, 640, 20, $24)
        .BYTE 2, 0,0, 18,0, $80,$02, 20,0, $24
        ; Offset 10: Wis Pano Titelbalk (12, 324, 248, 14, $24)
        .BYTE 2, 12,0, (324 & $FF),(324 >> 8), 248,0, 14,0, $24
        ; Offset 20: Wis 32-Staps Progress-Bar (284, 198, 320, 6, $24)
        .BYTE 2, (284 & $FF),(284 >> 8), 198,0, (320 & $FF),(320 >> 8), 6,0, $24

STR_STUDIO_HDRS:
        .BYTE 12,0, 5,0, $FF, "MiniGPU 16-BIT 48kHz STEREO JUKEBOX & SYNTH STUDIO", 0
        .BYTE 14,0, 48,0, $FC, "8-TRACK PLAYLIST [1-8]", 0
        .BYTE (280 & $FF),(280 >> 8), 48,0, $FC, "16-BIT KANAAL, NOOT & VU", 0
        .BYTE 14,0, 222,0, $FC, "24-TOETSEN PIANO VISUALIZER & BEDIENING", 0
        .BYTE (394 & $FF),(394 >> 8), 244,0, $1F, "[1-8/WS] Kies Liedje", 0
        .BYTE (394 & $FF),(394 >> 8), 262,0, $1C, "[SPAT]Play [I/H]Remix", 0
        .BYTE (394 & $FF),(394 >> 8), 280,0, $EB, "[F]FX [A]DJ [+/-]Spd", 0
        .BYTE (394 & $FF),(394 >> 8), 298,0, $FC, "[V]720p [B]Bg [K]Koe!", 0
        .BYTE 12,0, (346 & $FF),(346 >> 8), $FF, "1-8:Lied SPAT:Play I/H:Instr F:FX A:DJ V:720p B:Bg K:Koe ESC:Uit", 0
        .BYTE 0

SONG_SPEED_TBL:
        .BYTE 13, 11, 10, 12, 10, 10, 13, 10

SONG_FX_TBL:
        .BYTE 0, 0, 0, 0, 0, 0, 1, 0

SONG_INST_TBL:
        .BYTE 0, 2, 5, 7
        .BYTE 4, 0, 5, 7
        .BYTE 6, 1, 5, 7
        .BYTE 3, 1, 5, 7
        .BYTE 4, 3, 5, 7
        .BYTE 1, 3, 5, 7
        .BYTE 2, 6, 5, 7
        .BYTE 4, 2, 5, 7

SONG_TITLE_LO:
        .BYTE <STR_SNG0, <STR_SNG1, <STR_SNG2, <STR_SNG3, <STR_SNG4, <STR_SNG5, <STR_SNG6, <STR_SNG7
SONG_TITLE_HI:
        .BYTE >STR_SNG0, >STR_SNG1, >STR_SNG2, >STR_SNG3, >STR_SNG4, >STR_SNG5, >STR_SNG6, >STR_SNG7

STR_SNG0: .ASCIIZ "1.FUER ELISE (BEETHOVEN)"
STR_SNG1: .ASCIIZ "2.AXEL F (SYNTHWAVE 84)"
STR_SNG2: .ASCIIZ "3.POPCORN (STEREO BELLS)"
STR_SNG3: .ASCIIZ "4.TWENTSE ODE AN FREUDE"
STR_SNG4: .ASCIIZ "5.SUPER MARIO OVERWORLD"
STR_SNG5: .ASCIIZ "6.TETRIS KOROBEINIKI FM"
STR_SNG6: .ASCIIZ "7.SPACE ODYSSEY OXYGENE"
STR_SNG7: .ASCIIZ "8.PIRATES OF CARIBBEAN "

NOTE_INC_LO:
        .BYTE $00, $4D, $9D, $3D, $33, $83, $34, $4B, $CD, $C2, $30, $1E, $94, $9A, $39, $7A
        .BYTE $65, $07, $68, $95, $9A, $84, $60, $3C, $28, $35, $72, $F3, $CB, $0D, $D0, $2A
        .BYTE $34, $08, $BF, $78, $51, $6A, $E5, $E7, $96, $1A, $A0, $55, $69, $0F, $7E, $F0
        .BYTE $A1, $00
NOTE_INC_MID:
        .BYTE $00, $59, $5E, $64, $6A, $70, $77, $7E, $85, $8D, $96, $9F, $A8, $B2, $BD, $C8
        .BYTE $D4, $E1, $EE, $FC, $0B, $1B, $2C, $3E, $51, $65, $7A, $90, $A8, $C2, $DC, $F9
        .BYTE $17, $37, $58, $7C, $A2, $CA, $F4, $21, $51, $84, $B9, $F2, $2E, $6E, $B1, $F8
        .BYTE $44, $00
NOTE_INC_HI:
        .BYTE $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
        .BYTE $02, $02, $02, $02, $02, $02, $02, $03, $03, $03, $03, $03, $04, $04, $04, $04
        .BYTE $05, $00

SONG_BLOBS:
; --- Song 1: 1.FUER ELISE (BEETHOVEN) (112 bytes: 32B CH0, 32B CH1, 32B CH2, 16B CH3) ---
        .BYTE $29, $28, $29, $28, $29, $24, $27, $25, $22, $00, $19, $1D, $22, $24, $00, $1D
        .BYTE $21, $24, $25, $00, $1D, $29, $28, $29, $28, $29, $24, $27, $25, $22, $00, $31
        .BYTE $31, $00, $00, $00, $31, $00, $00, $00, $19, $00, $1D, $00, $22, $21, $1D, $00
        .BYTE $18, $00, $1D, $00, $21, $1D, $19, $00, $31, $00, $00, $00, $1D, $19, $16, $00
        .BYTE $0A, $00, $00, $00, $05, $00, $00, $00, $0A, $00, $11, $00, $0A, $00, $05, $00
        .BYTE $05, $00, $0C, $00, $11, $00, $0C, $00, $0A, $00, $05, $00, $0A, $00, $0A, $31
        .BYTE $01, $00, $03, $00, $02, $00, $03, $00, $01, $00, $03, $00, $02, $00, $04, $00
; --- Song 2: 2.AXEL F (SYNTHWAVE 84) (112 bytes: 32B CH0, 32B CH1, 32B CH2, 16B CH3) ---
        .BYTE $1E, $31, $21, $00, $1E, $1E, $23, $1E, $1C, $1E, $31, $25, $00, $1E, $1E, $26
        .BYTE $25, $21, $1E, $25, $2A, $1E, $1C, $1C, $19, $20, $1E, $00, $00, $00, $00, $31
        .BYTE $19, $00, $19, $00, $15, $00, $17, $00, $14, $00, $15, $00, $19, $00, $17, $00
        .BYTE $15, $00, $19, $00, $19, $00, $17, $00, $14, $00, $19, $00, $15, $00, $19, $00
        .BYTE $06, $12, $06, $12, $04, $10, $04, $10, $02, $0E, $02, $0E, $04, $10, $05, $0D
        .BYTE $06, $12, $06, $12, $04, $10, $04, $10, $02, $0E, $04, $10, $06, $0D, $06, $31
        .BYTE $01, $03, $02, $03, $01, $01, $02, $03, $01, $03, $02, $03, $01, $04, $02, $03
; --- Song 3: 3.POPCORN (STEREO BELLS) (112 bytes: 32B CH0, 32B CH1, 32B CH2, 16B CH3) ---
        .BYTE $22, $20, $22, $1D, $19, $1D, $16, $31, $22, $20, $22, $1D, $19, $1D, $16, $31
        .BYTE $22, $24, $25, $24, $25, $22, $24, $22, $24, $20, $22, $1E, $20, $1D, $22, $31
        .BYTE $31, $19, $31, $19, $31, $1D, $31, $19, $31, $19, $31, $19, $31, $1D, $31, $19
        .BYTE $31, $1D, $31, $1D, $31, $1B, $31, $1B, $31, $1B, $31, $19, $31, $18, $19, $31
        .BYTE $0A, $00, $11, $00, $0A, $00, $11, $00, $0A, $00, $11, $00, $0A, $00, $05, $00
        .BYTE $0A, $00, $16, $00, $0F, $00, $03, $00, $08, $00, $06, $00, $05, $00, $0A, $00
        .BYTE $01, $03, $02, $03, $01, $03, $02, $04, $01, $03, $02, $03, $01, $02, $04, $03
; --- Song 4: 4.TWENTSE ODE AN FREUDE (112 bytes: 32B CH0, 32B CH1, 32B CH2, 16B CH3) ---
        .BYTE $1D, $1D, $1E, $20, $20, $1E, $1D, $1B, $19, $19, $1B, $1D, $1D, $00, $1B, $1B
        .BYTE $1D, $1D, $1E, $20, $20, $1E, $1D, $1B, $19, $19, $1B, $1D, $1B, $00, $19, $00
        .BYTE $19, $19, $1B, $1D, $1D, $1B, $19, $18, $16, $16, $18, $19, $19, $00, $18, $18
        .BYTE $19, $19, $1B, $1D, $1D, $1B, $19, $18, $16, $16, $18, $19, $18, $00, $14, $00
        .BYTE $01, $00, $08, $00, $0D, $00, $08, $00, $0A, $00, $05, $00, $08, $00, $08, $00
        .BYTE $01, $00, $08, $00, $05, $00, $08, $00, $0A, $00, $06, $00, $08, $00, $01, $00
        .BYTE $01, $00, $03, $00, $02, $00, $03, $00, $01, $00, $03, $00, $02, $00, $04, $00
; --- Song 5: 5.SUPER MARIO OVERWORLD (112 bytes: 32B CH0, 32B CH1, 32B CH2, 16B CH3) ---
        .BYTE $29, $29, $31, $29, $31, $25, $29, $00, $2C, $00, $00, $31, $20, $00, $00, $31
        .BYTE $25, $00, $31, $20, $00, $31, $1D, $00, $31, $22, $31, $24, $31, $23, $22, $00
        .BYTE $1F, $1F, $31, $1F, $31, $1F, $22, $00, $24, $00, $00, $31, $20, $00, $00, $31
        .BYTE $1D, $00, $31, $19, $00, $31, $14, $00, $31, $19, $31, $1B, $31, $1A, $19, $00
        .BYTE $0F, $0F, $31, $0F, $31, $0F, $08, $00, $14, $00, $00, $31, $08, $00, $00, $31
        .BYTE $14, $00, $31, $11, $00, $31, $0D, $00, $31, $12, $31, $14, $31, $13, $12, $00
        .BYTE $01, $02, $00, $02, $00, $01, $02, $00, $01, $00, $02, $03, $01, $00, $02, $04
; --- Song 6: 6.TETRIS KOROBEINIKI FM (112 bytes: 32B CH0, 32B CH1, 32B CH2, 16B CH3) ---
        .BYTE $29, $00, $24, $25, $27, $00, $25, $24, $22, $00, $22, $25, $29, $00, $27, $25
        .BYTE $24, $00, $24, $25, $27, $00, $29, $00, $25, $00, $22, $00, $22, $00, $00, $31
        .BYTE $31, $21, $31, $21, $31, $21, $31, $21, $31, $1D, $31, $1D, $31, $22, $31, $1D
        .BYTE $31, $21, $31, $21, $31, $21, $31, $21, $31, $1D, $31, $19, $16, $00, $00, $31
        .BYTE $05, $11, $05, $11, $05, $11, $09, $11, $0A, $16, $0A, $16, $0A, $16, $05, $0A
        .BYTE $05, $11, $05, $11, $09, $11, $0C, $11, $0A, $11, $0A, $11, $0A, $00, $00, $31
        .BYTE $01, $03, $02, $03, $01, $03, $02, $03, $01, $03, $02, $03, $01, $03, $02, $04
; --- Song 7: 7.SPACE ODYSSEY OXYGENE (112 bytes: 32B CH0, 32B CH1, 32B CH2, 16B CH3) ---
        .BYTE $20, $00, $00, $1E, $1C, $00, $19, $00, $1E, $00, $00, $1C, $1B, $00, $19, $00
        .BYTE $1C, $00, $00, $1B, $19, $00, $17, $00, $19, $00, $00, $00, $20, $00, $00, $00
        .BYTE $19, $1C, $20, $25, $20, $1C, $19, $14, $17, $1B, $1E, $23, $1E, $1B, $17, $12
        .BYTE $15, $19, $1C, $21, $1C, $19, $15, $10, $14, $19, $1C, $20, $24, $20, $1B, $18
        .BYTE $01, $00, $08, $00, $0D, $00, $08, $00, $0B, $00, $06, $00, $0B, $00, $06, $00
        .BYTE $09, $00, $04, $00, $09, $00, $04, $00, $08, $00, $03, $00, $08, $00, $08, $00
        .BYTE $01, $00, $03, $00, $02, $00, $03, $04, $01, $00, $03, $00, $02, $00, $03, $04
; --- Song 8: 8.PIRATES OF CARIBBEAN (112 bytes: 32B CH0, 32B CH1, 32B CH2, 16B CH3) ---
        .BYTE $22, $25, $27, $27, $31, $27, $29, $2A, $2A, $31, $2A, $2C, $29, $29, $31, $27
        .BYTE $25, $25, $27, $00, $31, $22, $25, $27, $27, $31, $27, $2A, $2C, $2C, $31, $2C
        .BYTE $1E, $00, $22, $00, $1E, $00, $22, $00, $1B, $00, $1E, $00, $20, $00, $1D, $00
        .BYTE $1D, $00, $1E, $00, $22, $00, $1E, $00, $1E, $00, $22, $00, $23, $00, $20, $00
        .BYTE $03, $0F, $03, $0F, $0B, $06, $0B, $06, $06, $12, $06, $12, $01, $0D, $0A, $0A
        .BYTE $01, $0D, $03, $0F, $03, $0F, $0A, $03, $03, $0F, $03, $0F, $08, $14, $08, $08
        .BYTE $01, $03, $01, $02, $01, $03, $02, $03, $01, $03, $01, $02, $01, $02, $04, $03
