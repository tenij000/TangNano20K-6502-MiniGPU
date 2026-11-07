; ============================================================================
; FRUITY.asm v2.0 - MiniGPU FruityLoops 6502 (16-Bit 48kHz Stereo Studio)
; Geassembleerd voor $8000 (Past in 1 SD-slot van 4 KB, naast MC op $9000!)
;
; Hardware 16-Bit 48 kHz Stereo FM / Wavetable / ADSR Sound Card:
;   - $A00A (IO_INST): Per-kanaals instrument keuze (16 + ch*16 + inst 0..7):
;       0=PIANO FM, 1=HAMMOND, 2=STRINGS, 3=GITAAR,
;       4=BRASS FM, 5=SUB BASS, 6=FM BELLS, 7=808 DRUM / CHIP8
;   - $A00B (IO_FX):   Bit0=Hardware ADSR, Bit1=Warm LPF, Bit2=Stereo, Bit3=Vibrato
;   - Toets [I] of [TAB]: Wissel live het 16-Bit Instrument van het actieve spoor!
;   - Toets [F]:          Wissel Stereo FX / Vibrato / Raw modus!
; ============================================================================

        .ORG $8000

; --- Hardware I/O Registers ---
IO_STATUS       = $A000         ; Bit 0 = char ready, Bit 7 = ESC ingedrukt
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer (1 tick = 10 ms)
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_INST         = $A00A         ; 16-Bit Stereo Sound Card Instrument Register
IO_FX           = $A00B         ; 16-Bit Stereo Sound Card FX / ADSR Register
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- ROM Routines voor MicroSD Opslag (Sector $03FA voor $3000..$31FF) ---
ZP_DST          = $1C
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA

; --- Patroon-Geheugen in SDRAM ($3000..$304F) ---
PAT_MEM         = $3000         ; 4 sporen x 16 stappen = 64 bytes ($3000..$303F)
PAT_MAGIC       = $3040         ; $F7 = geldig patroon in geheugen
PAT_INST        = $3041         ; $3041..$3044: 4 opgeslagen 16-bit instrumenten per spoor

; --- Zero Page Variabelen ($50..$8F) ---
ZP_PTR_LO       = $50
ZP_PTR_HI       = $51
ZP_X_LO         = $52
ZP_X_HI         = $53
ZP_Y_LO         = $54
ZP_Y_HI         = $55
ZP_W_LO         = $56
ZP_W_HI         = $57
ZP_H_LO         = $58
ZP_COL          = $59
ZP_FG_COL       = $5A

CUR_CH          = $5B           ; Geselecteerd spoor (0..3)
CUR_STEP        = $5C           ; Geselecteerde stap (0..15)
PLAY_STEP       = $5D           ; Huidige afspeel-stap (0..15)
OLD_PLAY_STEP   = $5E           ; Vorige afspeel-stap (voor playhead-update)
IS_PLAYING      = $5F           ; 1 = Afspelen, 0 = Gepauzeerd
TICK_CNT        = $60           ; 100 Hz tick-teller binnen huidige stap
SPEED_TICKS     = $61           ; Ticks per 16e noot (standaard 12 = 125 BPM)
CUR_OCTAVE      = $62           ; Huidig toetsenbord-octaaf (0=C2, 1=C3, 2=C4)
CUR_SONG        = $63           ; Huidig geladen demo-nummer (1..3)
MENU_OPEN       = $64           ; 0 = Sequencer actief, 1 = ESC-menu open
PREV_JOY        = $65
LAST_NOTE       = $66           ; Laatst gespeelde/geselecteerde noot (voor Piano Roll)

ZP_SAV_X        = $67
ZP_SAV_Y        = $68
ITER_CH         = $69
ITER_STEP       = $6A

; 4-Kanaals Synthesizer Envelopes & Mute-status ($70..$7F)
ENV_VOL         = $70           ; $70..$73: Huidig volume (0..255) per kanaal 0..3
CH_NOTE         = $74           ; $74..$77: Huidige actieve noot/drum per kanaal 0..3
CH_MUTE         = $78           ; $78..$7B: 0 = Aan, 1 = Mute per kanaal 0..3
DRM_FREQ_MID    = $7C           ; Huidige drum-frequentie Mid-byte (voor Kick/Snare/Hat)
DRM_FREQ_HI     = $7D           ; Huidige drum-frequentie High-byte
DRM_DECAY       = $7E           ; Snelheid van drum-decay
CH_INST         = $80           ; $80..$83: Huidig 16-bit instrument (0..7) per spoor 0..3
CUR_FX          = $84           ; 0 = Stereo+LPF ($07), 1 = +Vibrato ($0F), 2 = Raw ($01)

BSRAM_EXIT_MC   = $02D8         ; Veilige BSRAM exit-stub terug naar BASIC/MC

; ============================================================================
; Startpunt ($8000)
; ============================================================================
START:
        LDX #10
INIT_EXIT_LP:
        LDA EXIT_STUB_TBL,X
        STA BSRAM_EXIT_MC,X
        DEX
        BPL INIT_EXIT_LP

        LDA #0
        STA IO_MODE
        STA CUR_CH
        STA CUR_STEP
        STA PLAY_STEP
        STA OLD_PLAY_STEP
        STA TICK_CNT
        STA MENU_OPEN
        STA CH_MUTE
        STA CH_MUTE+1
        STA CH_MUTE+2
        STA CH_MUTE+3
        LDA #1
        STA CUR_OCTAVE          ; Standaard octaaf C3..B4 op toetsenbord
        STA IS_PLAYING          ; Start direct met afspelen!
        LDA #12                 ; 12 ticks (120 ms per stap) = 125 BPM
        STA SPEED_TICKS
        LDA #25                 ; C-4 als start-selectie op de Piano Roll
        STA LAST_NOTE

        ; Zet 16-Bit Stereo Sound Card standaard op ADSR + Warm LPF + Stereo Chorus ($07)
        LDA #0
        STA CUR_FX
        LDA #$07
        STA IO_FX

        ; Als er nog geen patroon in $3000 staat, laad dan Demo Song #1!
        LDA PAT_MAGIC
        CMP #$F7
        BEQ S_HAS_PAT
        LDA #0
        JSR LOAD_SONG_A
        JMP S_SYNC_INST
S_HAS_PAT:
        LDX #3
S_REST_INST:
        LDA PAT_INST,X
        AND #7
        STA CH_INST,X
        DEX
        BPL S_REST_INST
S_SYNC_INST:
        JSR SYNC_ALL_CH_INST
        JSR TRIGGER_CURRENT_STEP
        JSR FULL_REDRAW
        LDA IO_JOY
        STA PREV_JOY

; ============================================================================
; Hoofdlus (100 Hz Timer Gesynchroniseerd: Sequencer + Envelopes + Toetsen)
; ============================================================================
MAIN_LOOP:
        LDA IO_TIMER
W10_LP:
        CMP IO_TIMER
        BEQ W10_LP

        ; 1. Update 100 Hz Synth Envelopes & Sequencer Stappen
        JSR UPDATE_AUDIO_TICK

        ; 2. Check ESC (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_JOY_NAV
        LDA IO_TERM             ; Wis ESC uit IO_TERM
        LDA #0
        STA IO_MODE             ; Houd tekst-overlay uit
        LDA MENU_OPEN
        BNE EXIT_FRUITY         ; Tweede ESC in het menu = Afsluiten!
        JSR OPEN_ESC_MENU
        JMP MAIN_LOOP

EXIT_FRUITY:
        JSR ROM_SILENCE
        JMP BSRAM_EXIT_MC

CHK_JOY_NAV:
        LDA MENU_OPEN
        BNE CHK_KEY_INPUT

        LDA IO_JOY
        STA ZP_SAV_X
        TAX
        EOR PREV_JOY
        AND ZP_SAV_X
        STX PREV_JOY
        TAY
        BEQ CHK_KEY_INPUT

        LDA IO_TERM             ; Wis pijl/WASD uit IO_TERM
        TYA
        AND #1                  ; Pijl Omhoog
        BNE JOY_UP
        TYA
        AND #2                  ; Pijl Omlaag
        BNE JOY_DOWN
        TYA
        AND #4                  ; Pijl Links
        BNE JOY_LEFT
        TYA
        AND #8                  ; Pijl Rechts
        BNE JOY_RIGHT
        JMP MAIN_LOOP

JOY_UP:
        DEC CUR_CH
        BPL JU_OK
        LDA #3
        STA CUR_CH
JU_OK:
        JMP REDRAW_NAV_CHANGE

JOY_DOWN:
        INC CUR_CH
        LDA CUR_CH
        CMP #4
        BCC REDRAW_NAV_CHANGE
        LDA #0
        STA CUR_CH
        JMP REDRAW_NAV_CHANGE

JOY_LEFT:
        DEC CUR_STEP
        BPL REDRAW_NAV_CHANGE
        LDA #15
        STA CUR_STEP
        JMP REDRAW_NAV_CHANGE

JOY_RIGHT:
        INC CUR_STEP
        LDA CUR_STEP
        AND #15
        STA CUR_STEP
REDRAW_NAV_CHANGE:
        JSR SYNC_LAST_NOTE
        JSR DRAW_TRACK_LABELS
        JSR DRAW_ALL_PADS
        JSR DRAW_PIANO_KEYS
        JSR DRAW_INFO_BAR
        JMP MAIN_LOOP

CHK_KEY_INPUT:
        LDA IO_STATUS
        AND #1
        BEQ MAIN_LOOP
        LDA IO_TERM
        STA ZP_SAV_Y
        LDA IO_JOY
        STA PREV_JOY

        LDA MENU_OPEN
        BEQ SEQ_KEY_HANDLER
        JMP MENU_KEY_HANDLER

; ============================================================================
; Toetsen in de FruityLoops Sequencer
; ============================================================================
SEQ_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #' '                ; Spatie = Play / Pause!
        BEQ TOGGLE_PLAY
        CMP #$0D                ; Enter = Plaats/Verhoog noot of drum in huidige stap
        BEQ STEP_CYCLE_VAL
        CMP #$09                ; TAB = Wissel 16-Bit Instrument op huidig spoor!
        BEQ CYCLE_CH_INST
        CMP #$08                ; Backspace = Wis huidige stap (---)
        BEQ STEP_CLEAR_VAL
        CMP #$7F                ; Delete = Wis huidige stap (---)
        BEQ STEP_CLEAR_VAL
        CMP #'0'                ; 0 = Wis huidige stap (---)
        BEQ STEP_CLEAR_VAL
        CMP #'['                ; '[' of '-' = Langzamer (BPM omlaag)
        BEQ TEMPO_SLOWER
        CMP #'-'
        BEQ TEMPO_SLOWER
        CMP #']'                ; ']' of '+'/'=' = Sneller (BPM omhoog)
        BEQ TEMPO_FASTER
        CMP #'+'
        BEQ TEMPO_FASTER
        CMP #'='
        BEQ TEMPO_FASTER
        CMP #'1'
        BCC SKH_UPPER
        CMP #'4'
        BCC LOAD_DEMO_KEY

SKH_UPPER:
        AND #$DF                ; Maak hoofdletter
        CMP #'P'                ; P = Play / Pause
        BEQ TOGGLE_PLAY
        CMP #'M'                ; M = Mute / Unmute huidig kanaal
        BEQ TOGGLE_MUTE_CH
        CMP #'I'                ; I = Wissel 16-Bit Instrument op huidig spoor!
        BEQ CYCLE_CH_INST
        CMP #'F'                ; F = Wissel Stereo FX / Vibrato / Raw modus!
        BEQ CYCLE_FX_MODE
        CMP #'<'                ; Octaaf omlaag
        BEQ OCT_DOWN
        CMP #'>'                ; Octaaf omhoog
        BEQ OCT_UP

        ; Check of het een Piano-toets is (Z X C V B N M / Q W E R T Y U enz.)
        JSR TRY_PIANO_KEY
        JMP MAIN_LOOP

TOGGLE_PLAY:
        LDA IS_PLAYING
        EOR #1
        STA IS_PLAYING
        BNE TP_STARTED
        JSR SILENCE_ALL_4
        JSR DRAW_VU_METERS
        JMP TP_DRAW
TP_STARTED:
        LDA #0
        STA TICK_CNT
        JSR TRIGGER_CURRENT_STEP
TP_DRAW:
        JSR DRAW_INFO_BAR
        JMP MAIN_LOOP

TOGGLE_MUTE_CH:
        LDX CUR_CH
        LDA CH_MUTE,X
        EOR #1
        STA CH_MUTE,X
        BEQ TMC_DONE
        LDA #0
        STA ENV_VOL,X
        JSR SEND_CH_X_AUDIO
TMC_DONE:
        JSR DRAW_TRACK_LABELS
        JMP MAIN_LOOP

CYCLE_CH_INST:
        LDX CUR_CH
        LDA CH_INST,X
        CLC
        ADC #1
        AND #7
        STA CH_INST,X
        STA PAT_INST,X
        JSR SYNC_ALL_CH_INST
        JSR DRAW_TRACK_LABELS
        JSR DRAW_INFO_BAR
        ; Laat het nieuwe 16-bit instrument direct horen!
        LDX CUR_CH
        CPX #3
        BEQ CCI_DRM_PREV
        LDA LAST_NOTE
        JMP CCI_TRIG
CCI_DRM_PREV:
        LDA #1
CCI_TRIG:
        JSR TRIGGER_CH_X_NOTE_A
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
        JSR DRAW_INFO_BAR
        JMP MAIN_LOOP

TEMPO_SLOWER:
        LDA SPEED_TICKS
        CMP #24
        BCS TS_DONE
        INC SPEED_TICKS
        JSR DRAW_INFO_BAR
TS_DONE:
        JMP MAIN_LOOP

TEMPO_FASTER:
        LDA SPEED_TICKS
        CMP #6
        BCC TS_DONE
        DEC SPEED_TICKS
        JSR DRAW_INFO_BAR
        JMP MAIN_LOOP

OCT_DOWN:
        LDA CUR_OCTAVE
        BEQ TS_DONE
        DEC CUR_OCTAVE
        JSR DRAW_INFO_BAR
        JMP MAIN_LOOP

OCT_UP:
        LDA CUR_OCTAVE
        CMP #2
        BCS TS_DONE
        INC CUR_OCTAVE
        JSR DRAW_INFO_BAR
        JMP MAIN_LOOP

LOAD_DEMO_KEY:
        SEC
        SBC #'1'
        JSR LOAD_SONG_A
        JMP AFTER_SONG_CHANGE

STEP_CLEAR_VAL:
        LDA #0
        JMP SET_CUR_STEP_A

STEP_CYCLE_VAL:
        JSR GET_CUR_CELL_OFFSET
        LDA PAT_MEM,X
        LDY CUR_CH
        CPY #3
        BEQ SCV_DRUM
        ; Melodisch kanaal: als 0, zet LAST_NOTE; anders +1 halve toon (tot 37, dan 0)
        CMP #0
        BNE SCV_MEL_INC
        LDA LAST_NOTE
        JMP SET_CUR_STEP_A
SCV_MEL_INC:
        CLC
        ADC #1
        CMP #38
        BCC SET_CUR_STEP_A
        LDA #0
        BEQ SET_CUR_STEP_A
SCV_DRUM:
        CLC
        ADC #1
        CMP #5
        BCC SET_CUR_STEP_A
        LDA #0

SET_CUR_STEP_A:
        PHA
        JSR GET_CUR_CELL_OFFSET
        PLA
        STA PAT_MEM,X
        CMP #0
        BEQ SCSA_DRAW
        LDY CUR_CH
        CPY #3
        BEQ SCSA_TRIG
        STA LAST_NOTE
SCSA_TRIG:
        ; Laat de ingevoerde noot of drum direct horen (live preview)!
        LDX CUR_CH
        JSR TRIGGER_CH_X_NOTE_A
SCSA_DRAW:
        JSR DRAW_ALL_PADS
        JSR DRAW_PIANO_KEYS
        JMP DRAW_INFO_BAR

; ============================================================================
; Piano-Toetsenbord Invoer (Z..M = C..B laag octaaf, Q..U = C..B hoog octaaf)
; Op het Drum-spoor (CH3) kiezen toetsen direct 1=KCK, 2=SNR, 3=HAT, 4=OPN!
; ============================================================================
TRY_PIANO_KEY:
        LDX #0
TPK_LP:
        LDA PIANO_KEY_CHARS,X
        BEQ TPK_RTS
        CMP ZP_SAV_Y
        BEQ TPK_FOUND
        INX
        BNE TPK_LP
TPK_RTS:
        RTS

TPK_FOUND:
        LDA CUR_CH
        CMP #3
        BNE TPK_MELODIC
        ; Op CH3 (Drums): elke piano-toets wisselt tussen KCK(1), SNR(2), HAT(3), OPN(4)
        TXA
        AND #3
        CLC
        ADC #1
        JMP SET_CUR_STEP_A

TPK_MELODIC:
        ; Bereken noot = PIANO_KEY_SEMI[X] + CUR_OCTAVE * 12 + 1
        LDA PIANO_KEY_SEMI,X
        LDY CUR_OCTAVE
        BEQ TPK_OCT_DONE
TPK_OCT_LP:
        CLC
        ADC #12
        DEY
        BNE TPK_OCT_LP
TPK_OCT_DONE:
        CMP #37
        BCC TPK_STORE
        LDA #36
TPK_STORE:
         CLC
        ADC #1
        JSR SET_CUR_STEP_A
        RTS

; ============================================================================
; ESC-Menu Afhandeling (Demo's, Nieuw, SD Opslaan/Laden, Sluiten met Spatie)
; ============================================================================
OPEN_ESC_MENU:
        LDA #1
        STA MENU_OPEN
        LDX #10                 ; 3 rechthoeken voor het popup-venster (offset 10..39)
        JSR SEND_RECT_10
        JSR SEND_RECT_10
        JSR SEND_RECT_10
        LDA #<STR_POPUP_MENU
        LDY #>STR_POPUP_MENU
        JMP DRAW_HDR_LIST

CLOSE_ESC_MENU:
        LDA #0
        STA MENU_OPEN
        JMP FULL_REDRAW

MENU_KEY_HANDLER:
        LDA ZP_SAV_Y
        CMP #' '
        BEQ MKH_CLOSE
        CMP #$0D
        BEQ MKH_CLOSE
        CMP #'1'
        BCC MKH_ALPHA
        CMP #'4'
        BCC LOAD_DEMO_KEY
        CMP #'4'
        BEQ MKH_NEW
        CMP #'5'
        BEQ MKH_SAVE
        CMP #'6'
        BEQ MKH_LOAD
MKH_ALPHA:
        AND #$DF
        CMP #'N'
        BEQ MKH_NEW
        CMP #'S'
        BEQ MKH_SAVE
        CMP #'L'
        BEQ MKH_LOAD
        CMP #'Q'
        BNE MKH_RTS
        JMP EXIT_FRUITY
MKH_RTS:
        JMP MAIN_LOOP

MKH_CLOSE:
        JSR CLOSE_ESC_MENU
        JMP MAIN_LOOP

MKH_NEW:
        LDX #63
        LDA #0
MN_CLR:
        STA PAT_MEM,X
        DEX
        BPL MN_CLR
        JMP AFTER_SONG_CHANGE

MKH_SAVE:
        JSR PREP_SD_SEC
        JSR ROM_WRITE_SEC
        JMP MKH_CLOSE

MKH_LOAD:
        JSR PREP_SD_SEC
        JSR ROM_READ_SEC
AFTER_SONG_CHANGE:
        LDA #0
        STA MENU_OPEN
        STA PLAY_STEP
        STA TICK_CNT
        JSR TRIGGER_CURRENT_STEP
        JSR FULL_REDRAW
        JMP MAIN_LOOP

PREP_SD_SEC:
        JSR ROM_SD_INIT
        LDA #$FA                ; Sector $03FA voor FruityLoops patronen ($3000..$31FF)
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDA #$00
        STA ZP_DST
        LDA #$30
        STA ZP_DST+1
        RTS

; ============================================================================
; 100 Hz Audio Engine & Synthesizer Envelopes (CH0..CH3 via GPU CMD 16)
; ============================================================================
UPDATE_AUDIO_TICK:
        ; 1. Update VU-meter envelopes voor CH0..CH2 (48kHz hardware ADSR doet het geluid!)
        ;    Stuur alleen bij ENV_VOL == 0 een Note-Off zodat noten niet elke 10ms trappen.
        LDX #0
UAT_MEL_LP:
        LDA ENV_VOL,X
        BEQ UAT_MEL_NXT
        SEC
        SBC #6
        BCS UAT_MEL_ST
        LDA #0
        STA ENV_VOL,X
        JSR SEND_CH_X_AUDIO
        JMP UAT_MEL_NXT
UAT_MEL_ST:
        STA ENV_VOL,X
UAT_MEL_NXT:
        INX
        CPX #3
        BCC UAT_MEL_LP

        ; 2. Update CH3 (16-Bit Smart Drum Kit: 808 Kick / Snare / Hi-Hat)
        LDA ENV_VOL+3
        BEQ UAT_CHK_STEP
        SEC
        SBC DRM_DECAY
        BCS UAT_DRM_ST
        LDA #0
        STA ENV_VOL+3
        LDX #3
        JSR SEND_CH_X_AUDIO
        JMP UAT_CHK_STEP
UAT_DRM_ST:
        STA ENV_VOL+3

UAT_CHK_STEP:
        ; 3. Teken de 4 live VU-meters
        JSR DRAW_VU_METERS

        ; 4. Als IS_PLAYING == 1, tel ticks tot de volgende 16e stap!
        LDA IS_PLAYING
        BEQ UAT_RTS
        INC TICK_CNT
        LDA TICK_CNT
        CMP SPEED_TICKS
        BCC UAT_RTS
        LDA #0
        STA TICK_CNT

        ; Ga naar de volgende stap (0..15)
        LDA PLAY_STEP
        STA OLD_PLAY_STEP
        CLC
        ADC #1
        AND #15
        STA PLAY_STEP

        JSR TRIGGER_CURRENT_STEP
        JSR UPDATE_PLAYHEAD_BAR
        LDA MENU_OPEN
        BNE UAT_RTS
        JSR DRAW_INFO_BAR
UAT_RTS:
        RTS

TRIGGER_CURRENT_STEP:
        LDX #0
TCS_LP:
        STX ITER_CH
        TXA
        ASL A
        ASL A
        ASL A
        ASL A
        ORA PLAY_STEP
        TAY
        LDA PAT_MEM,Y
        BEQ TCS_NXT             ; Rust (---) = laat vorige noot uitklinken of stil
        LDX ITER_CH
        JSR TRIGGER_CH_X_NOTE_A
TCS_NXT:
        LDX ITER_CH
        INX
        CPX #4
        BCC TCS_LP
        RTS

TRIGGER_CH_X_NOTE_A:
        STA CH_NOTE,X
        LDA CH_MUTE,X
        BNE TCXN_MUTED
        ; Stuur eerst kort vol=0 zodat de 16-bit hardware ADSR (note_trig_req)
        ; altijd een verse aanslag geeft, ook bij 2x dezelfde noot of drum!
        LDA #0
        STA ENV_VOL,X
        JSR SEND_CH_X_AUDIO
        CPX #3
        BEQ TCXN_DRUM
        ; Melodisch spoor (CH0..CH2)
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

TCXN_MUTED:
        LDA #0
        STA ENV_VOL,X
        JMP SEND_CH_X_AUDIO

; Stuur 6-byte GPU Audio pakket: [16, ch, phase_lo, phase_mid, phase_hi, vol]
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

SILENCE_ALL_4:
        LDX #3
SA4_LP:
        LDA #0
        STA ENV_VOL,X
        JSR SEND_CH_X_AUDIO
        DEX
        BPL SA4_LP
        RTS

; ============================================================================
; Grafische Opbouw (640x360 FruityLoops Studio Interface)
; ============================================================================
FULL_REDRAW:
        LDX #0
FR_GUI_LP:
        LDA GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #(GUI_STREAM_END - GUI_STREAM)
        BCC FR_GUI_LP

        LDA #<STR_HEADERS
        LDY #>STR_HEADERS
        JSR DRAW_HDR_LIST

        JSR DRAW_STEP_NUMBERS
        JSR DRAW_TRACK_LABELS
        JSR UPDATE_PLAYHEAD_BAR
        JSR DRAW_ALL_PADS
        JSR DRAW_PIANO_KEYS
        JSR DRAW_VU_METERS
        JMP DRAW_INFO_BAR

DRAW_HDR_LIST:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DHL_LP:
        JSR NEXT_PTR_BYTE
        BEQ DHL_RTS
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
        JMP DHL_LP
DHL_RTS:
        RTS

; Teken stap-nummers 01..16 boven het grid (Y = 47, X = 117 + step*32)
DRAW_STEP_NUMBERS:
        LDA #0
        STA ITER_STEP
DSN_LP:
        LDA ITER_STEP
        JSR CALC_STEP_X
        CLC
        ADC #6
        STA ZP_X_LO
        BCC DSN_XOK
        INC ZP_X_HI
DSN_XOK:
        LDA #47
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_FG_COL

        LDX ITER_STEP
        INX
        TXA
        CMP #10
        BCC DSN_1D
        PHA
        LDA #'1'
        JSR DRAW_CHAR_ADV
        PLA
        SEC
        SBC #10
        JMP DSN_2D
DSN_1D:
        PHA
        LDA #'0'
        JSR DRAW_CHAR_ADV
        PLA
DSN_2D:
        CLC
        ADC #'0'
        JSR DRAW_CHAR_ADV
        INC ITER_STEP
        LDA ITER_STEP
        CMP #16
        BCC DSN_LP
        RTS

; Teken de 4 Kanaal-knoppen links van het grid (X = 8..108, Y = 72, 104, 136, 168)
DRAW_TRACK_LABELS:
        LDX #0
DTL_LP:
        STX ITER_CH
        LDA TRACK_Y_TBL,X
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        STA ZP_X_HI
        LDA #8
        STA ZP_X_LO
        LDA #100
        STA ZP_W_LO
        LDA #26
        STA ZP_H_LO

        ; Kleur op basis van selectie of mute
        LDA #$25
        CPX CUR_CH
        BNE DTL_BG
        LDA #$53
DTL_BG:
        STA ZP_COL
        JSR DRAW_RECT_ZP

        ; Kleurrijke linkerrand per spoor
        LDA #8
        STA ZP_X_LO
        LDA #4
        STA ZP_W_LO
        LDX ITER_CH
        LDA TRACK_ACT_COL,X
        STA ZP_COL
        JSR DRAW_RECT_ZP

        ; Tekst van het kanaal + gekozen 16-Bit Instrument ("0:PIANO FM", enz.)
        LDX ITER_CH
        LDA TRACK_Y_TBL,X
        CLC
        ADC #5
        STA ZP_Y_LO
        LDA #16
        STA ZP_X_LO
        LDA #$FF
        STA ZP_FG_COL
        TXA
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

        ; Mute-status op tweede regel in de kanaal-box
        LDX ITER_CH
        LDA TRACK_Y_TBL,X
        CLC
        ADC #15
        STA ZP_Y_LO
        LDA #16
        STA ZP_X_LO
        LDA CH_MUTE,X
        BNE DTL_MUTED
        LDA #$1C                ; Groen "ON"
        STA ZP_FG_COL
        LDA #<STR_CH_ON
        LDY #>STR_CH_ON
        JMP DTL_PRT_M
DTL_MUTED:
        LDA #$E0                ; Rood "MUTE"
        STA ZP_FG_COL
        LDA #<STR_CH_MUTE
        LDY #>STR_CH_MUTE
DTL_PRT_M:
        JSR DRAW_AY_STR
        LDX ITER_CH
        INX
        CPX #4
        BCC DTL_LP
        RTS

; Update de 16 Playhead-LEDs boven de 16 stappen (Y = 62, H = 6)
UPDATE_PLAYHEAD_BAR:
        LDA MENU_OPEN
        BNE UPB_RTS
        LDA #0
        STA ITER_STEP
UPB_LP:
        LDA ITER_STEP
        JSR CALC_STEP_X
        LDA #61
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #28
        STA ZP_W_LO
        LDA #6
        STA ZP_H_LO
        LDA #$24                ; Donkergrijs als niet op deze stap
        LDX ITER_STEP
        CPX PLAY_STEP
        BNE UPB_DRAW
        LDA #$FC                ; Felgeel op de actieve Playhead-stap!
UPB_DRAW:
        STA ZP_COL
        JSR DRAW_RECT_ZP
        INC ITER_STEP
        LDA ITER_STEP
        CMP #16
        BCC UPB_LP
UPB_RTS:
        RTS

; Teken alle 4 x 16 = 64 FruityLoops Step-Pads
DRAW_ALL_PADS:
        LDA #0
        STA ITER_CH
DAP_CH_LP:
        LDA #0
        STA ITER_STEP
DAP_ST_LP:
        JSR DRAW_SINGLE_PAD
        INC ITER_STEP
        LDA ITER_STEP
        CMP #16
        BCC DAP_ST_LP
        INC ITER_CH
        LDA ITER_CH
        CMP #4
        BCC DAP_CH_LP
        RTS

DRAW_SINGLE_PAD:
        LDA ITER_STEP
        JSR CALC_STEP_X
        LDX ITER_CH
        LDA TRACK_Y_TBL,X
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #28
        STA ZP_W_LO
        LDA #26
        STA ZP_H_LO

        ; Haal waarde uit PAT_MEM (ITER_CH * 16 + ITER_STEP)
        LDA ITER_CH
        ASL A
        ASL A
        ASL A
        ASL A
        ORA ITER_STEP
        TAY
        LDA PAT_MEM,Y
        STA ZP_SAV_Y

        ; Bepaal achtergrondkleur van de pad:
        ; - Als actief (>0): kanaalkleur TRACK_ACT_COL
        ; - Als leeg (0): afwisselend per 4 stappen ($25 voor 0..3/8..11, $44 voor 4..7/12..15)
        CMP #0
        BEQ DSP_EMPTY_COL
        LDX ITER_CH
        LDA TRACK_ACT_COL,X
        BNE DSP_DRAW_BOX
DSP_EMPTY_COL:
        LDA ITER_STEP
        AND #4
        BEQ DSP_DARK_GRP
        LDA #$49                ; Warme paars/bruine FruityLoops 2e maat-groep kleur
        BNE DSP_DRAW_BOX
DSP_DARK_GRP:
        LDA #$25                ; Donkerblauwgrijze 1e maat-groep kleur
DSP_DRAW_BOX:
        STA ZP_COL
        JSR DRAW_RECT_ZP

        ; Als dit de geselecteerde cursor-positie (CUR_CH, CUR_STEP) is, teken witte bovenbalk!
        LDA ITER_CH
        CMP CUR_CH
        BNE DSP_TEXT
        LDA ITER_STEP
        CMP CUR_STEP
        BNE DSP_TEXT
        LDA #4
        STA ZP_H_LO
        LDA #$FF
        STA ZP_COL
        JSR DRAW_RECT_ZP

DSP_TEXT:
        ; Teken de 3-letterige noot ("C-4", "D#3") of drum ("KCK", "SNR") midden in de pad
        LDA ITER_STEP
        JSR CALC_STEP_X
        CLC
        ADC #2
        STA ZP_X_LO
        BCC DSP_XOK
        INC ZP_X_HI
DSP_XOK:
        LDX ITER_CH
        LDA TRACK_Y_TBL,X
        CLC
        ADC #9
        STA ZP_Y_LO

        LDA ZP_SAV_Y
        BNE DSP_HAS_VAL
        LDA #$92                ; Gedimd grijs voor "---"
        STA ZP_FG_COL
        LDA #'-'
        JSR DRAW_CHAR_ADV
        LDA #'-'
        JSR DRAW_CHAR_ADV
        LDA #'-'
        JMP DRAW_CHAR_ADV

DSP_HAS_VAL:
        LDA #$00                ; Zwarte tekst op felgekleurde actieve pad!
        STA ZP_FG_COL
        LDX ITER_CH
        CPX #3
        BEQ DSP_DRUM_TXT
        LDA ZP_SAV_Y
        JMP DRAW_NOTE_3CHARS

DSP_DRUM_TXT:
        LDY ZP_SAV_Y
        LDA DRM_C0,Y
        JSR DRAW_CHAR_ADV
        LDA DRM_C1,Y
        JSR DRAW_CHAR_ADV
        LDA DRM_C2,Y
        JMP DRAW_CHAR_ADV

; Teken noot-index A (1..37) als 3 tekens (bijv. "C-4", "F#3")
DRAW_NOTE_3CHARS:
        SEC
        SBC #1
        LDY #'2'                ; Start bij octaaf '2'
DN3_MOD12:
        CMP #12
        BCC DN3_GOT_OCT
        SBC #12
        INY
        BNE DN3_MOD12
DN3_GOT_OCT:
        TAX
        TYA
        PHA                     ; Bewaar octaaf-cijfer ('2'..'5')
        LDA SEMI_CHAR0,X
        JSR DRAW_CHAR_ADV
        LDA SEMI_CHAR1,X
        JSR DRAW_CHAR_ADV
        PLA
        JMP DRAW_CHAR_ADV

; Bereken X = 114 + A * 32 in ZP_X_LO/HI (en geeft ZP_X_LO terug in A)
CALC_STEP_X:
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDY #5
CSX_SH:
        ASL ZP_X_LO
        ROL ZP_X_HI
        DEY
        BNE CSX_SH
        CLC
        LDA ZP_X_LO
        ADC #114
        STA ZP_X_LO
        BCC CSX_OK
        INC ZP_X_HI
CSX_OK:
        RTS

; ============================================================================
; Visueel Piano-Toetsenbord (Linksonder: X = 14..388, Y = 228..296)
; ============================================================================
DRAW_PIANO_KEYS:
        ; Bepaal actieve semitone (0..11) uit LAST_NOTE (1..37)
        LDA LAST_NOTE
        BEQ DPK_NO_SEMI
        SEC
        SBC #1
DPK_MOD:
        CMP #12
        BCC DPK_GOT_S
        SBC #12
        BCS DPK_MOD
DPK_NO_SEMI:
        LDA #$FF
DPK_GOT_S:
        STA ZP_SAV_Y            ; ZP_SAV_Y = geselecteerde halve toon (0..11)

        ; 1. Teken 14 witte toetsen (2 octaven: C..B, C..B)
        LDX #0
DPK_WHITE_LP:
        STX ITER_STEP
        LDA WHITE_KEY_X,X
        STA ZP_X_LO
        LDA WHITE_KEY_XH,X
        STA ZP_X_HI
        LDA #230
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #23
        STA ZP_W_LO
        LDA #60
        STA ZP_H_LO
        LDA #$FF                ; Witte toets
        LDY WHITE_KEY_SEMI,X
        CPY ZP_SAV_Y
        BNE DPK_W_COL
        LDA #$1F                ; Lichtblauw als deze noot geselecteerd is!
DPK_W_COL:
        STA ZP_COL
        JSR DRAW_RECT_ZP
        LDX ITER_STEP
        INX
        CPX #14
        BCC DPK_WHITE_LP

        ; 2. Teken 10 zwarte toetsen (C#, D#, F#, G#, A# x 2 octaven)
        LDX #0
DPK_BLACK_LP:
        STX ITER_STEP
        LDA BLACK_KEY_X,X
        STA ZP_X_LO
        LDA BLACK_KEY_XH,X
        STA ZP_X_HI
        LDA #230
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #15
        STA ZP_W_LO
        LDA #36
        STA ZP_H_LO
        LDA #$00                ; Zwarte toets
        LDY BLACK_KEY_SEMI,X
        CPY ZP_SAV_Y
        BNE DPK_B_COL
        LDA #$FC                ; Geel als deze zwarte toets geselecteerd is!
DPK_B_COL:
        STA ZP_COL
        JSR DRAW_RECT_ZP
        LDX ITER_STEP
        INX
        CPX #10
        BCC DPK_BLACK_LP
        RTS

; ============================================================================
; Live 4-Kanaals VU-Meters (Rechtsonder: X = 412..624, Y = 232..304)
; ============================================================================
DRAW_VU_METERS:
        LDA MENU_OPEN
        BNE DVM_RTS
        LDX #0
DVM_LP:
        STX ITER_CH
        LDA VU_Y_LO,X
        STA ZP_Y_LO
        LDA VU_Y_HI,X
        STA ZP_Y_HI
        LDA #(452 & $FF)
        STA ZP_X_LO
        LDA #(452 >> 8)
        STA ZP_X_HI
        LDA #164
        STA ZP_W_LO
        LDA #12
        STA ZP_H_LO
        LDA #$00                ; Wis achtergrond van VU-balk
        STA ZP_COL
        JSR DRAW_RECT_ZP

        LDX ITER_CH
        LDA ENV_VOL,X
        LSR A                   ; 0..255 -> 0..127 pixels breed
        BEQ DVM_NXT
        STA ZP_W_LO
        LDA TRACK_ACT_COL,X
        STA ZP_COL
        JSR DRAW_RECT_ZP
DVM_NXT:
        LDX ITER_CH
        INX
        CPX #4
        BCC DVM_LP
DVM_RTS:
        RTS

; ============================================================================
; Status & Transport Balk Bovenin (Y = 18..34)
; ============================================================================
DRAW_INFO_BAR:
        LDX #0
        JSR SEND_RECT_10

        ; 1. Play/Stop status op X=14, Y=21
        LDA #14
        LDY #21
        JSR SET_XY_POS
        LDA IS_PLAYING
        BEQ DIB_STOPPED
        LDA #$1C                ; Groen "[PLAY]"
        STA ZP_FG_COL
        LDA #<STR_PLAYING
        LDY #>STR_PLAYING
        JMP DIB_PRT_ST
DIB_STOPPED:
        LDA #$E0                ; Rood "[STOP]"
        STA ZP_FG_COL
        LDA #<STR_STOPPED
        LDY #>STR_STOPPED
DIB_PRT_ST:
        JSR DRAW_AY_STR

        ; 2. Stap + Noot info op X=114, Y=21
        LDA #114
        STA ZP_X_LO
        LDA #$FF
        STA ZP_FG_COL
        LDA #<STR_LBL_STEP
        LDY #>STR_LBL_STEP
        JSR DRAW_AY_STR
        LDA PLAY_STEP
        CLC
        ADC #1
        JSR DRAW_HEX_BYTE

        ; 3. Octaaf info op X=210, Y=21
        LDA #210
        STA ZP_X_LO
        LDA #$FC
        STA ZP_FG_COL
        LDA #<STR_LBL_OCT
        LDY #>STR_LBL_OCT
        JSR DRAW_AY_STR
        LDA CUR_OCTAVE
        CLC
        ADC #'2'
        JSR DRAW_CHAR_ADV

        ; 4. Speed/Tempo info op X=296, Y=21
        LDA #(296 & $FF)
        STA ZP_X_LO
        LDA #(296 >> 8)
        STA ZP_X_HI
        LDA #$1F
        STA ZP_FG_COL
        LDA #<STR_LBL_SPD
        LDY #>STR_LBL_SPD
        JSR DRAW_AY_STR
        LDA SPEED_TICKS
        JSR DRAW_HEX_BYTE

        ; 5. Song nummer op X=396, Y=21
        LDA #(396 & $FF)
        STA ZP_X_LO
        LDA #(396 >> 8)
        STA ZP_X_HI
        LDA #$FF
        STA ZP_FG_COL
        LDA #<STR_LBL_SONG
        LDY #>STR_LBL_SONG
        JSR DRAW_AY_STR
        LDA CUR_SONG
        CLC
        ADC #'0'
        JSR DRAW_CHAR_ADV

        ; 6. 16-Bit Stereo FX status op X=484, Y=21
        LDA #(484 & $FF)
        STA ZP_X_LO
        LDA #(484 >> 8)
        STA ZP_X_HI
        LDA #$1C
        STA ZP_FG_COL
        LDX CUR_FX
        LDA FX_NAME_LO,X
        LDY FX_NAME_HI,X
        JMP DRAW_AY_STR

; ============================================================================
; Hulproutines voor Patroon, GPU Rechthoeken & Tekst
; ============================================================================
GET_CUR_CELL_OFFSET:
        LDA CUR_CH
        ASL A
        ASL A
        ASL A
        ASL A
        ORA CUR_STEP
        TAX
        RTS

SYNC_LAST_NOTE:
        LDA CUR_CH
        CMP #3
        BEQ SLN_RTS
        JSR GET_CUR_CELL_OFFSET
        LDA PAT_MEM,X
        BEQ SLN_RTS
        STA LAST_NOTE
SLN_RTS:
        RTS

LOAD_SONG_A:
        STA ZP_SAV_X
        CLC
        ADC #1
        STA CUR_SONG
        ; Laad ook de 4 bijbehorende 16-Bit Studio Instrumenten voor deze Song!
        LDA ZP_SAV_X
        ASL A
        ASL A
        TAY
        LDX #0
LSA_INST_LP:
        LDA SONG_INST_TBL,Y
        STA CH_INST,X
        STA PAT_INST,X
        INY
        INX
        CPX #4
        BCC LSA_INST_LP
        JSR SYNC_ALL_CH_INST

        LDA ZP_SAV_X
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A                   ; A * 64
        TAY
        LDX #0
LSA_LP:
        LDA SONG_BLOBS,Y
        STA PAT_MEM,X
        INY
        INX
        CPX #64
        BCC LSA_LP
        LDA #$F7
        STA PAT_MAGIC
        RTS

; Schrijf CH_INST[0..3] naar de 16-Bit Stereo Sound Card ($A00A: 16 + ch*16 + inst)
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

DRAW_RECT_ZP:
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
        LDA #0
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

SET_XY_POS:
        STA ZP_X_LO
        STY ZP_Y_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
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
; Tabellen, Kleuren, Noot-Frequenties & 3 Chiptune Demo-Songs
; ============================================================================
EXIT_STUB_TBL:
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

TRACK_Y_TBL:
        .BYTE 72, 104, 136, 168

VU_Y_LO:
        .BYTE 234, 252, (270 & $FF), (288 & $FF)
VU_Y_HI:
        .BYTE 0,   0,   (270 >> 8),  (288 >> 8)

TRACK_ACT_COL:
        .BYTE $1F, $EB, $1C, $FC        ; CH0=Cyaan, CH1=Neon-Roze ($EB, niet $E3 transparant!), CH2=Groen, CH3=Goudgeel

CH_INIT_VOL:
        .BYTE 220, 190, 245, 240

; 16-Bit Smart Drum Parameters (0=---, 1=KCK <55k, 2=SNR 55k..220k, 3=HAT >=220k, 4=OPN >=220k)
DRM_INIT_VOL:
        .BYTE 0, 255, 240, 200, 225
DRM_INIT_DECAY:
        .BYTE 0, 16,  14,  36,  9
DRM_INIT_MID:
        .BYTE 0, $48, $50, $80, $20
DRM_INIT_HI:
        .BYTE 0, $00, $01, $06, $04

DRM_C0: .BYTE '-', 'K', 'S', 'H', 'O'
DRM_C1: .BYTE '-', 'C', 'N', 'A', 'P'
DRM_C2: .BYTE '-', 'K', 'R', 'T', 'N'

SEMI_CHAR0:
        .BYTE "CCDDEFFGGAAB"
SEMI_CHAR1:
        .BYTE "-#-#--#-#-#-"

; Toetsenbord -> Piano mapping (2 octaven zoals in FruityLoops / FastTracker!)
PIANO_KEY_CHARS:
        .BYTE "ZSXDCVGBHNJMQ2W3ER5T6Y7U", 0
PIANO_KEY_SEMI:
        .BYTE 0,1,2,3,4,5,6,7,8,9,10,11, 12,13,14,15,16,17,18,19,20,21,22,23

; X-coordinaten voor de 14 witte toetsen en 10 zwarte toetsen op het Piano-paneel
WHITE_KEY_X:
        .BYTE 16, 42, 68, 94, 120, 146, 172, 198, 224, 250, 276, 302, 328, 354
WHITE_KEY_XH:
        .BYTE 0,  0,  0,  0,  0,   0,   0,   0,   0,   0,   1,   1,   1,   1
WHITE_KEY_SEMI:
        .BYTE 0,  2,  4,  5,  7,   9,   11,  0,   2,   4,   5,   7,   9,   11

BLACK_KEY_X:
        .BYTE 33, 59, 111, 137, 163, 215, 241, 37, 63, 89
BLACK_KEY_XH:
        .BYTE 0,  0,  0,   0,   0,   0,   0,   1,  1,  1
BLACK_KEY_SEMI:
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
STR_IN7:        .ASCIIZ "808/CHIP"

FX_VAL_TBL:
        .BYTE $07, $0F, $01
FX_NAME_LO:
        .BYTE <STR_FX0, <STR_FX1, <STR_FX2
FX_NAME_HI:
        .BYTE >STR_FX0, >STR_FX1, >STR_FX2
STR_FX0:        .ASCIIZ "FX:STEREO [F]"
STR_FX1:        .ASCIIZ "FX:VIBRAT [F]"
STR_FX2:        .ASCIIZ "FX:CHIP8  [F]"

; Preset 16-Bit Instrumenten per Demo-Song (CH0, CH1, CH2, CH3)
SONG_INST_TBL:
        .BYTE 0, 2, 5, 7        ; Song 1: Grand Piano + Strings + Sub-Bass + 808 Drums
        .BYTE 4, 6, 5, 7        ; Song 2: Royal Brass + FM Bells + Sub-Bass + 808 Drums
        .BYTE 1, 3, 5, 7        ; Song 3: Hammond Organ + Guitar + Sub-Bass + 808 Drums

STR_CH_ON:      .ASCIIZ "ON [I/M]"
STR_CH_MUTE:    .ASCIIZ "MUTE [M]"

STR_PLAYING:    .ASCIIZ "[PLAYING]"
STR_STOPPED:    .ASCIIZ "[STOPPED]"
STR_LBL_STEP:   .ASCIIZ "STAP:$"
STR_LBL_OCT:    .ASCIIZ "OCT:"
STR_LBL_SPD:    .ASCIIZ "SPD:$"
STR_LBL_SONG:   .ASCIIZ "SONG:#"

GUI_STREAM:
        .BYTE 12, 1                             ; TARGET 1 (frontbuffer)
        .BYTE 2, 0,0, 0,0, $80,$02, 16,0, $C0   ; Donkerrode/oranje FruityLoops titelbalk
        .BYTE 2, 0,0, 16,0, $80,$02, 22,0, $24  ; Transportbalk achtergrond
        .BYTE 2, 0,0, 38,0, $80,$02, $30,$01, $00 ; Hoofd-achtergrond
        .BYTE 2, 8,0, 42,0, 100,0, 18,0, $48    ; Koptekst links ("KANAAL")
        .BYTE 2, 112,0, 42,0, $08,$02, 18,0, $48 ; Koptekst rechts (Stap 01..16)
        .BYTE 2, 8,0, 210,0, $80,$01, 16,0, $48 ; Koptekst Piano Roll
        .BYTE 2, 8,0, 226,0, $80,$01, 108,0, $24 ; Piano Roll paneel
        .BYTE 2, $94,$01, 210,0, $E4,$00, 16,0, $48 ; Koptekst VU-Meters
        .BYTE 2, $94,$01, 226,0, $E4,$00, 108,0, $24 ; VU-Meter paneel
        .BYTE 2, 0,0, $54,$01, $80,$02, 20,0, $48 ; Onderste statusbalk
GUI_STREAM_END:

UI_RECT_TBL:
        ; Offset 0: Wis Transportbalk (0, 16, 640, 22, $24)
        .BYTE 2, 0,0, 16,0, $80,$02, 22,0, $24
        ; Offset 10..39: ESC Popup-venster (Rand + Zwart vlak + Oranje/Gele titelbalk)
        .BYTE 2, 146,0, 76,0, 92,1, 156,0, $FC
        .BYTE 2, 148,0, 78,0, 88,1, 152,0, $00
        .BYTE 2, 148,0, 78,0, 88,1, 18,0, $FC

STR_HEADERS:
        .BYTE 12,0, 4,0, $FF, "MiniGPU FRUITYLOOPS 6502 v2.0 - 16-Bit 48kHz Stereo Studio & Sequencer", 0
        .BYTE 12,0, 47,0, $FC, "16-BIT INSTR", 0
        .BYTE 14,0, 214,0, $FC, "PIANO ROLL (Z-M/Q-U:Noot ENTER:Stap 0:Wis)", 0
        .BYTE 16,0, (298 & $FF),(298 >> 8), $FF, "LAAG OCTAAF: Z S X D C V G B H N J M  (<>:Oct)", 0
        .BYTE 16,0, (312 & $FF),(312 >> 8), $1F, "HOOG OCTAAF: Q 2 W 3 E R 5 T 6 Y 7 U  (Drums)", 0
        .BYTE $9C,$01, 214,0, $FC, "16-BIT STEREO VU-METERS", 0
        .BYTE $9C,$01, 236,0, $1F, "CH0:", 0
        .BYTE $9C,$01, 254,0, $EB, "CH1:", 0
        .BYTE $9C,$01, (272 & $FF),(272 >> 8), $1C, "CH2:", 0
        .BYTE $9C,$01, (290 & $FF),(290 >> 8), $FC, "CH3:", 0
        .BYTE $9C,$01, (312 & $FF),(312 >> 8), $FF, "I/TAB:Instr F:FX 1-3:Song", 0
        .BYTE 12,0, (345 & $FF),(345 >> 8), $FF, "SPATIE:Play  I/TAB:Instr  F:FX  M:Mute  ENTER:Zet  Z-M:Piano  ESC:Menu", 0
        .BYTE 0

STR_POPUP_MENU:
        .BYTE 164,0, 83,0,  $00, "== FRUITYLOOPS 6502 MENU ==", 0
        .BYTE 164,0, 106,0, $FF, "[1] Song 1: 8-Bit Arcade Theme", 0
        .BYTE 164,0, 122,0, $FF, "[2] Song 2: Demoscene Arpeggio", 0
        .BYTE 164,0, 138,0, $FF, "[3] Song 3: Fruity Electro Beat", 0
        .BYTE 164,0, 154,0, $FF, "[4/N] Nieuw Leeg Patroon", 0
        .BYTE 164,0, 170,0, $FF, "[5/S] Opslaan   [6/L] Laden SD", 0
        .BYTE 164,0, 198,0, $FC, "[SPAT] Sluit    [ESC/Q] Uit", 0
        .BYTE 0

NOTE_INC_LO: ; 24-bit Phase Increment Low voor rust (0) + 37 noten (C2..C5)
        .BYTE $00, $4D, $9D, $3D, $33, $83, $34, $4B, $CD, $C2, $30, $1E, $94, $9A, $39, $7A
        .BYTE $65, $07, $68, $95, $9A, $84, $60, $3C, $28, $35, $72, $F3, $CB, $0D, $D0, $2A
        .BYTE $34, $08, $BF, $78, $51, $6A
NOTE_INC_MID: ; 24-bit Phase Increment Mid
        .BYTE $00, $59, $5E, $64, $6A, $70, $77, $7E, $85, $8D, $96, $9F, $A8, $B2, $BD, $C8
        .BYTE $D4, $E1, $EE, $FC, $0B, $1B, $2C, $3E, $51, $65, $7A, $90, $A8, $C2, $DC, $F9
        .BYTE $17, $37, $58, $7C, $A2, $CA
NOTE_INC_HI: ; 24-bit Phase Increment High
        .BYTE $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .BYTE $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
        .BYTE $02, $02, $02, $02, $02, $02

SONG_BLOBS: ; 3 Ingebouwde Chiptune Demo-Songs (3 x 64 bytes)
        .BYTE $19, $00, $1D, $20, $22, $00, $20, $1D, $1E, $00, $22, $20, $1D, $1B, $19, $14
        .BYTE $11, $14, $19, $11, $12, $16, $19, $12, $0F, $12, $16, $0F, $14, $18, $1B, $18
        .BYTE $01, $00, $0D, $01, $06, $00, $12, $06, $03, $00, $0F, $03, $08, $08, $0A, $0C
        .BYTE $01, $03, $03, $01, $02, $03, $01, $03, $01, $03, $01, $03, $02, $03, $04, $03
        .BYTE $1D, $20, $24, $1D, $1B, $1F, $22, $1B, $19, $1D, $20, $19, $18, $1C, $1F, $18
        .BYTE $18, $00, $14, $00, $16, $00, $13, $00, $14, $00, $11, $00, $13, $00, $10, $00
        .BYTE $05, $11, $05, $11, $03, $0F, $03, $0F, $01, $0D, $01, $0D, $0C, $0C, $07, $0C
        .BYTE $01, $03, $02, $03, $01, $01, $02, $03, $01, $03, $02, $03, $01, $02, $04, $02
        .BYTE $1E, $00, $21, $1E, $25, $00, $23, $21, $20, $00, $21, $20, $1E, $1C, $19, $00
        .BYTE $00, $19, $00, $19, $00, $1C, $00, $1C, $00, $1A, $00, $1A, $00, $19, $14, $19
        .BYTE $06, $06, $09, $06, $01, $0D, $0B, $09, $02, $02, $06, $02, $01, $08, $0D, $08
        .BYTE $01, $03, $03, $01, $02, $03, $01, $04, $01, $01, $03, $01, $02, $01, $02, $04
