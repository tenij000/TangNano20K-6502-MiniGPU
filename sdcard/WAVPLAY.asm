; ============================================================================
; MP3PLAY.asm - MiniGPU Midnight-Commander Dual-Pane .MP3 & .WAV Speler ($8000)
; Aangedreven door de Hardware Audio Hulp-CPU ($A018-$A01B) + 48 kHz HDMI Audio
;
; Linker Paneel : 8 Lange .MP3 Liedjes van MicroSD (Sector $2001 / $2410+,
;                 elk 256 sectoren = 128 KB = 512 pagina's = 16,4 sec @ 8 kHz,
;                 gecachet in SDRAM Banken 44..59).
; Rechter Paneel: Alle 16 .WAV Geluiden van MicroSD (Sector $2000 / $2010+,
;                 elk 64 sectoren = 32 KB = 128 pagina's = 4,1 sec @ 8 kHz,
;                 Pagina 1 = #1..#8, Pagina 2 = #9..#16, gecachet in Bank 28..43).
;
; Besturing (Toetsenbord, Joypad & USB/Alt+Pijltjes Muis):
;   PIJL OMHOOG/OMLAAG (of W/X) = Beweeg MC-selectiebalk (muziek speelt door!)
;   TAB of PIJL LINKS/RECHTS    = Wissel tussen Linker (.MP3) en Rechter (.WAV) paneel
;   ENTER of 3 of Muis-Klik     = Laad & Speel geselecteerd .MP3/.WAV bestand op Hulp-CPU
;   1..8                        = Kies & Speel direct nummer 1..8 in actief paneel
;   SPATIE                      = Pauzeer / Hervat Audio Hulp-CPU op huidige pagina
;   S                           = Wissel Sample Rate / Pitch live (8k/11k/16k/22k Hz)
;   L                           = Wissel LOOP (1 nummer) <-> ALBUM (Auto-DJ volgende!)
;   P                           = Wissel Rechter Paneel tussen WAV Pagina 1/2 en 2/2
;   M                           = Zet 4-Kanaals Stereo FM Synth Pad Aan/Uit onder muziek
;   R                           = Herlaad huidig bestand vers vanaf de MicroSD-kaart
;   B                           = Sluit af naar MC/BASIC terwijl MP3 op achtergrond doorspeelt!
;   ESC of Q                    = Stop muziek en sluit af naar MC ($9000) of BASIC
; ============================================================================
        ORG $8000

IO_STATUS       = $A000
IO_TERM         = $A001
IO_DELAY        = $A002
IO_TIMER        = $A003
IO_JOY          = $A004
IO_RND          = $A005
IO_MODE         = $A006
IO_SYNTH_INST   = $A00A
IO_SYNTH_FX     = $A00B
IO_MOUSE_XL     = $A00C
IO_MOUSE_XH     = $A00D
IO_MOUSE_YL     = $A00E
IO_MOUSE_ST     = $A00F
IO_RD_LO        = $A012
IO_RD_HI        = $A013
IO_RD_DATA      = $A014
IO_RD_BANK      = $A015
IO_PCM_DAC      = $A016
IO_PCM_RATE     = $A017
IO_ADMA_BANK    = $A018
IO_ADMA_PG_L    = $A019
IO_ADMA_PG_H    = $A01A
IO_ADMA_CTRL    = $A01B
IO_GPU          = $A020

ZP_DST          = $1C
DISK_FORCE_RD   = $0491
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67

MP3_DIR_BUF     = $7800         ; 512B SD-kaart MP3 Directory buffer (Sector $2001)
WAV_DIR_BUF     = $7A00         ; 512B SD-kaart WAV Directory buffer (Sector $2000)
SEC_TMP_BUF     = $0600         ; 512B Sector laad-buffer in snelle interne BSRAM ($0600-$07FF)
BSRAM_COPY_SEC  = $02C0         ; Snelle BSRAM 512B sector -> SDRAM kopieer-routine

; Zero-Page variabelen ($40..$6A)
ZP_X_LO         = $40
ZP_X_HI         = $41
ZP_Y_LO         = $42
ZP_Y_HI         = $43
ZP_W_LO         = $44
ZP_W_HI         = $45
ZP_H_LO         = $46
ZP_H_HI         = $47
ZP_COL          = $48
ZP_PTR_LO       = $4A
ZP_PTR_HI       = $4B

CUR_MX_LO       = $4C
CUR_MX_HI       = $4D
CUR_MY_LO       = $4E
CUR_MST         = $4F

ACTIVE_PANE     = $50           ; 0 = Linker Paneel (.MP3), 1 = Rechter Paneel (.WAV)
SEL_MP3         = $51           ; Geselecteerde rij in Linker .MP3 paneel (0..7)
SEL_WAV         = $52           ; Geselecteerde rij in Rechter .WAV paneel (0..7)
WAV_PAGE        = $53           ; 0 = WAV #1..#8, 1 = WAV #9..#16
PLAY_PANE       = $54           ; 0 = Speelt nu .MP3 (512 pag), 1 = Speelt nu .WAV (128 pag)
PLAY_IDX        = $55           ; Index van huidig spelend nummer (0..7 voor MP3, 0..15 voor WAV)
IS_PLAYING      = $56           ; 1 = Audio Hulp-CPU actief, 0 = Gepauzeerd
CUR_RATE        = $57           ; Sample rate code (1=8kHz, 2=11kHz, 3=16kHz, 4=22kHz)
ALBUM_MODE      = $58           ; 0 = Loop 1 nummer ($80|rate), 1 = Album Auto-DJ (volgende!)
FM_PAD_EN       = $59           ; 1 = 4-Kanaals FM Synth Pad meespelen, 0 = Uit
PLAY_START_BANK = $5A           ; Start SDRAM Bank van huidig nummer (44..58 of 28..43)
TOTAL_PG_LO     = $5B           ; Totaal aantal pagina's low (0 voor MP3, 128 voor WAV)
TOTAL_PG_HI     = $5C           ; Totaal aantal pagina's high (2 voor MP3 = 512, 0 voor WAV)
PAUSE_REM_LO    = $5D           ; Resterende pagina's bij pauzeren (low)
PAUSE_REM_HI    = $5E           ; Resterende pagina's bij pauzeren (high)
LOAD_SEC_CNT    = $60           ; Aantal 512B sectoren nog te laden (0 = 256!)
LOAD_PAGE_PTR   = $61           ; Huidige pagina binnen SDRAM bank (0..255)
CUR_LOAD_BANK   = $62           ; Huidige SDRAM bank tijdens laden
PROG_X_LO       = $63           ; Berekende voortgangsbalk breedte (0..512, low)
PROG_X_HI       = $64           ; Berekende voortgangsbalk breedte (0..512, high)
TEMP_IDX        = $65
PREV_JOY        = $66
LAST_TIMER      = $67
EQ_PHASE        = $68
SAMPLE_PEAK     = $69
REM_BG_BANKS    = $6A

START:
        CLD
        LDX #56
INIT_BSRAM_LP:
        LDA BSRAM_SRC,X
        STA BSRAM_COPY_SEC,X
        DEX
        BPL INIT_BSRAM_LP

        LDA #0
        STA IO_ADMA_CTRL
        STA IO_PCM_RATE
        LDA #128
        STA IO_PCM_DAC
        JSR ROM_SILENCE

        LDA #0
        STA IO_MODE
        STA IO_MOUSE_XH
        STA IO_MOUSE_ST
        STA ACTIVE_PANE
        STA SEL_MP3
        STA SEL_WAV
        STA WAV_PAGE
        STA PLAY_PANE
        STA PLAY_IDX
        STA ALBUM_MODE
        STA FM_PAD_EN
        STA EQ_PHASE
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        STA CUR_RATE
        STA IS_PLAYING
        LDA #160
        STA IO_MOUSE_XL
        LDA #120
        STA IO_MOUSE_YL

        LDX #23
        LDA #0
CLR_CACHE_LP:
        STA MP3_CACHED,X
        DEX
        BPL CLR_CACHE_LP

        JSR READ_DIRECTORIES
        JSR DRAW_FULL_UI
        JSR LOAD_AND_PLAY_SELECTED

        LDA IO_JOY
        STA PREV_JOY
        LDA IO_TIMER
        STA LAST_TIMER

; ============================================================================
; Hoofdlus: Audio Hulp-CPU ($A018-$A01B) speelt de .MP3/.WAV 100% op de
; achtergrond af; de 6502 tekent op 25 Hz de 16-staven spectrum-equalizer.
; ============================================================================
MAIN_LOOP:
        LDA IO_TIMER
        SEC
        SBC LAST_TIMER
        CMP #4
        BCC ML_CHECK_INPUT
        LDA IO_TIMER
        STA LAST_TIMER

        LDA IS_PLAYING
        BEQ ML_CHECK_INPUT

        LDA IO_ADMA_CTRL
        BMI ML_STILL_PLAYING

        ; Nummer is afgelopen! Als ALBUM_MODE = 1 -> stap naar volgend nummer!
        LDA ALBUM_MODE
        BEQ ML_RESTART_CUR
        LDA PLAY_PANE
        BNE ML_NEXT_WAV_AUTO
        INC SEL_MP3
        LDA SEL_MP3
        AND #$07
        STA SEL_MP3
        LDA #0
        STA ACTIVE_PANE
        JSR LOAD_AND_PLAY_SELECTED
        JMP ML_CHECK_INPUT

ML_NEXT_WAV_AUTO:
        INC SEL_WAV
        LDA SEL_WAV
        CMP #8
        BCC ML_NWA_OK
        LDA #0
        STA SEL_WAV
        LDA WAV_PAGE
        EOR #1
        STA WAV_PAGE
ML_NWA_OK:
        LDA #1
        STA ACTIVE_PANE
        JSR LOAD_AND_PLAY_SELECTED
        JMP ML_CHECK_INPUT

ML_RESTART_CUR:
        JSR START_HULP_CPU_FULL

ML_STILL_PLAYING:
        LDA REM_BG_BANKS
        BEQ ML_VIS_GO
        LDX #4
ML_BG_LP:
        STX TEMP_IDX
        LDA #<SEC_TMP_BUF
        STA ZP_DST
        LDA #>SEC_TMP_BUF
        STA ZP_DST+1
        JSR ROM_READ_SEC
        JSR BSRAM_COPY_SEC
        DEC LOAD_SEC_CNT
        BNE ML_BG_NX
        LDA #128
        STA LOAD_SEC_CNT
        DEC REM_BG_BANKS
        BEQ ML_VIS_GO
ML_BG_NX:
        LDX TEMP_IDX
        DEX
        BNE ML_BG_LP
ML_VIS_GO:
        JSR UPDATE_LIVE_VISUALS

ML_CHECK_INPUT:
        LDA IO_MOUSE_XL
        STA CUR_MX_LO
        LDA IO_MOUSE_XH
        AND #$03
        STA CUR_MX_HI
        LDA IO_MOUSE_YL
        STA CUR_MY_LO
        LDA IO_MOUSE_ST
        STA CUR_MST
        AND #$08
        BEQ ML_CHECK_JOY
        JSR HANDLE_MOUSE_CLICK

ML_CHECK_JOY:
        LDA IO_JOY
        STA TEMP_IDX
        TAX
        EOR PREV_JOY
        AND TEMP_IDX
        STX PREV_JOY
        TAY
        BEQ ML_CHECK_KEYS

        LDA IO_STATUS
        AND #1
        BNE ML_CHECK_KEYS

        TYA
        AND #1
        BEQ MJ_CHK_DN
        JSR MOVE_CURSOR_UP
        JMP MAIN_LOOP
MJ_CHK_DN:
        TYA
        AND #2
        BEQ MJ_CHK_LT
        JSR MOVE_CURSOR_DOWN
        JMP MAIN_LOOP
MJ_CHK_LT:
        TYA
        AND #4
        BEQ MJ_CHK_RT
        LDA #0
        BEQ MJ_SET_PN
MJ_CHK_RT:
        TYA
        AND #8
        BEQ ML_CHECK_KEYS
        LDA #1
MJ_SET_PN:
        STA ACTIVE_PANE
        JSR DRAW_BOTH_PANES
        JMP MAIN_LOOP

ML_CHECK_KEYS:
        LDA IO_STATUS
        BPL MK_CHK_READY
        LDA IO_TERM
        JMP EXIT_STOP_AUDIO
MK_CHK_READY:
        AND #$01
        BNE MK_READ_KEY
        JMP MAIN_LOOP

MK_READ_KEY:
        LDA IO_TERM
        LDX IO_JOY
        STX PREV_JOY

        CMP #27
        BNE MK_NOT_ESC
        JMP EXIT_STOP_AUDIO
MK_NOT_ESC:
        CMP #'a'
        BCC MK_UP_OK
        CMP #'z'+1
        BCS MK_UP_OK
        AND #$DF
MK_UP_OK:
        CMP #'Q'
        BEQ MK_GO_EXIT
        CMP #'0'
        BNE MK_NOT_0
MK_GO_EXIT:
        JMP EXIT_STOP_AUDIO
MK_NOT_0:
        CMP #'B'                ; B = Sluit af maar laat MP3 op achtergrond spelen!
        BNE MK_NOT_B
        JMP EXIT_KEEP_AUDIO
MK_NOT_B:
        CMP #9                  ; TAB = Wissel paneel
        BNE MK_NOT_TAB
        LDA ACTIVE_PANE
        EOR #1
        JMP MJ_SET_PN
MK_NOT_TAB:
        CMP #13                 ; ENTER of '3' = Laad & Speel
        BEQ MK_DO_PLAY_SEL
        CMP #'3'
        BNE MK_NOT_ENTER
MK_DO_PLAY_SEL:
        JSR LOAD_AND_PLAY_SELECTED
        JMP MAIN_LOOP
MK_NOT_ENTER:
        CMP #' '                ; SPATIE of '4' = Pauze / Hervat
        BEQ MK_DO_PAUSE
        CMP #'4'
        BNE MK_NOT_SPACE
MK_DO_PAUSE:
        JSR TOGGLE_PLAY_PAUSE
        JMP MAIN_LOOP
MK_NOT_SPACE:
        CMP #'W'
        BNE MK_NOT_W
        JSR MOVE_CURSOR_UP
        JMP MAIN_LOOP
MK_NOT_W:
        CMP #'X'
        BNE MK_NOT_X
        JSR MOVE_CURSOR_DOWN
        JMP MAIN_LOOP
MK_NOT_X:
        CMP #'A'
        BNE MK_NOT_A
        LDA #0
        JMP MJ_SET_PN
MK_NOT_A:
        CMP #'D'
        BNE MK_NOT_D
        LDA #1
        JMP MJ_SET_PN
MK_NOT_D:
        CMP #'S'
        BNE MK_NOT_S
        JSR CYCLE_SAMPLE_RATE
        JMP MAIN_LOOP
MK_NOT_S:
        CMP #'L'
        BNE MK_NOT_L
        JSR TOGGLE_ALBUM_MODE
        JMP MAIN_LOOP
MK_NOT_L:
        CMP #'P'
        BNE MK_NOT_P
        JSR TOGGLE_WAV_PAGE
        JMP MAIN_LOOP
MK_NOT_P:
        CMP #'M'
        BNE MK_NOT_M
        JSR TOGGLE_FM_PAD
        JMP MAIN_LOOP
MK_NOT_M:
        CMP #'H'
        BNE MK_NOT_H
        JSR RESTART_TRACK_BEGIN
        JMP MAIN_LOOP
MK_NOT_H:
        CMP #'R'
        BNE MK_CHK_DIGITS
        JSR INVALIDATE_SELECTED_CACHE
        JSR LOAD_AND_PLAY_SELECTED
        JMP MAIN_LOOP

MK_CHK_DIGITS:
        CMP #'1'
        BCC MK_DONE
        CMP #'9'
        BCS MK_DONE
        SEC
        SBC #'1'
        LDX ACTIVE_PANE
        BNE MK_SET_WAV_DIG
        STA SEL_MP3
        JMP MK_PLAY_DIG
MK_SET_WAV_DIG:
        STA SEL_WAV
MK_PLAY_DIG:
        JSR LOAD_AND_PLAY_SELECTED
MK_DONE:
        JMP MAIN_LOOP

; ============================================================================
; Cursor- & Knop-Acties
; ============================================================================
MOVE_CURSOR_UP:
        LDX ACTIVE_PANE
        DEC SEL_MP3,X
        BPL MCU_DONE
        LDA #7
        STA SEL_MP3,X
MCU_DONE:
        JMP DRAW_BOTH_PANES

MOVE_CURSOR_DOWN:
        LDX ACTIVE_PANE
        INC SEL_MP3,X
        LDA SEL_MP3,X
        CMP #8
        BCC MCD_DONE
        LDA #0
        STA SEL_MP3,X
MCD_DONE:
        JMP DRAW_BOTH_PANES

TOGGLE_WAV_PAGE:
        LDA WAV_PAGE
        EOR #1
        STA WAV_PAGE
        JSR DRAW_WAV_PANE
        JMP DRAW_TRANSPORT_BTNS

TOGGLE_FM_PAD:
        LDA FM_PAD_EN
        EOR #1
        STA FM_PAD_EN
        JSR UPDATE_FM_PAD
        JMP DRAW_RATE_BTNS

RESTART_TRACK_BEGIN:
        LDA #1
        STA IS_PLAYING
        JSR START_HULP_CPU_FULL
        JMP DRAW_TRANSPORT_BTNS

CYCLE_SAMPLE_RATE:
        LDX CUR_RATE
        INX
        CPX #5
        BCC CSR_OK
        LDX #1
CSR_OK:
        STX CUR_RATE
        JSR DRAW_RATE_BTNS
        JMP APPLY_LIVE_ADMA_CHANGE

TOGGLE_ALBUM_MODE:
        LDA ALBUM_MODE
        EOR #1
        STA ALBUM_MODE
        JSR DRAW_TRANSPORT_BTNS
APPLY_LIVE_ADMA_CHANGE:
        LDA IS_PLAYING
        BEQ ALAC_RTS
        LDA IO_ADMA_PG_L
        STA PAUSE_REM_LO
        LDA IO_ADMA_PG_H
        STA PAUSE_REM_HI
        JMP RESUME_HULP_CPU
ALAC_RTS:
        RTS

TOGGLE_PLAY_PAUSE:
        LDA IS_PLAYING
        BEQ TPP_RESUME
        LDA IO_ADMA_PG_L
        STA PAUSE_REM_LO
        LDA IO_ADMA_PG_H
        STA PAUSE_REM_HI
        LDA #0
        STA IO_ADMA_CTRL
        STA IS_PLAYING
        LDA #128
        STA IO_PCM_DAC
        JSR UPDATE_FM_PAD
        JMP DRAW_TRANSPORT_BTNS
TPP_RESUME:
        LDA #1
        STA IS_PLAYING
        JSR RESUME_HULP_CPU
        JSR UPDATE_FM_PAD
        JMP DRAW_TRANSPORT_BTNS

START_HULP_CPU_FULL:
        LDA PLAY_START_BANK
        STA IO_ADMA_BANK
        LDA TOTAL_PG_LO
        STA IO_ADMA_PG_L
        STA PAUSE_REM_LO
        LDA TOTAL_PG_HI
        STA IO_ADMA_PG_H
        STA PAUSE_REM_HI
        JMP TRIGGER_ADMA_CTRL

RESUME_HULP_CPU:
        LDA PLAY_PANE
        BNE RHC_WAV
        LDA PAUSE_REM_HI
        BNE RHC_MP3_B0
        LDA PAUSE_REM_LO
        BEQ START_HULP_CPU_FULL
        LDX PLAY_START_BANK
        INX
        STX IO_ADMA_BANK
        STA IO_ADMA_PG_L
        LDA #0
        STA IO_ADMA_PG_H
        JMP TRIGGER_ADMA_CTRL
RHC_MP3_B0:
        LDA PLAY_START_BANK
        STA IO_ADMA_BANK
        LDA PAUSE_REM_LO
        STA IO_ADMA_PG_L
        LDA PAUSE_REM_HI
        STA IO_ADMA_PG_H
        JMP TRIGGER_ADMA_CTRL
RHC_WAV:
        LDA PLAY_START_BANK
        STA IO_ADMA_BANK
        LDA PAUSE_REM_LO
        BNE RHC_W_OK
        LDA TOTAL_PG_LO
RHC_W_OK:
        STA IO_ADMA_PG_L
        LDA #0
        STA IO_ADMA_PG_H

TRIGGER_ADMA_CTRL:
        LDA CUR_RATE
        LDX ALBUM_MODE
        BNE TAC_NO_LOOP
        ORA #$80
TAC_NO_LOOP:
        STA IO_ADMA_CTRL
        RTS

INVALIDATE_SELECTED_CACHE:
        LDA ACTIVE_PANE
        BNE ISC_WAV
        LDX SEL_MP3
        LDA #0
        STA MP3_CACHED,X
        RTS
ISC_WAV:
        LDA WAV_PAGE
        ASL A
        ASL A
        ASL A
        CLC
        ADC SEL_WAV
        TAX
        LDA #0
        STA WAV_CACHED,X
        RTS

; ============================================================================
; HANDLE_MOUSE_CLICK
; ============================================================================
HANDLE_MOUSE_CLICK:
        LDA CUR_MY_LO
        CMP #22
        BCC HMC_RET
        CMP #42
        BCC HMC_PANE_HDR_CLICK
        CMP #210
        BCS HMC_CHK_RATE_ROW

        SEC
        SBC #42
        LDX #0
HMC_DIV21:
        CMP #21
        BCC HMC_GOT_ROW
        SBC #21
        INX
        CPX #7
        BCC HMC_DIV21
HMC_GOT_ROW:
        LDA CUR_MX_HI
        BEQ HMC_LEFT_CLICK
        CMP #1
        BNE HMC_RIGHT_CLICK
        LDA CUR_MX_LO
        CMP #<320
        BCS HMC_RIGHT_CLICK
HMC_LEFT_CLICK:
        LDA #0
        STA ACTIVE_PANE
        STX SEL_MP3
        JMP LOAD_AND_PLAY_SELECTED
HMC_RIGHT_CLICK:
        LDA #1
        STA ACTIVE_PANE
        STX SEL_WAV
        JMP LOAD_AND_PLAY_SELECTED

HMC_PANE_HDR_CLICK:
        LDA CUR_MX_HI
        BEQ HMC_RET
        JMP TOGGLE_WAV_PAGE
HMC_RET:
        RTS

HMC_CHK_RATE_ROW:
        CMP #252
        BCC HMC_RET
        CMP #280
        BCS HMC_CHK_TRANS_ROW
        LDA CUR_MX_HI
        BNE HMC_RATE_HI1
        LDA CUR_MX_LO
        CMP #70
        BCC HMC_SET_R1
        CMP #126
        BCC HMC_SET_R2
        CMP #182
        BCC HMC_SET_R3
        CMP #238
        BCC HMC_SET_R4
        JMP TOGGLE_FM_PAD
HMC_RATE_HI1:
        LDA CUR_MX_LO
        CMP #<316
        BCS HMC_RET
        JMP TOGGLE_FM_PAD
HMC_SET_R1:
        LDA #1
        BNE HMC_APPLY_RT
HMC_SET_R2:
        LDA #2
        BNE HMC_APPLY_RT
HMC_SET_R3:
        LDA #3
        BNE HMC_APPLY_RT
HMC_SET_R4:
        LDA #4
HMC_APPLY_RT:
        STA CUR_RATE
        JSR DRAW_RATE_BTNS
        JMP APPLY_LIVE_ADMA_CHANGE

HMC_CHK_TRANS_ROW:
        CMP #<306
        BCC HMC_RET
        CMP #<338
        BCS HMC_RET
        LDA CUR_MX_HI
        BNE HMC_TR_HI1
        LDA CUR_MX_LO
        CMP #140
        BCC HMC_DO_PLAY
        CMP #248
        BCC HMC_DO_BEGIN
        JMP TOGGLE_ALBUM_MODE
HMC_TR_HI1:
        CMP #1
        BNE HMC_DO_QUIT
        LDA CUR_MX_LO
        CMP #<384
        BCC HMC_DO_ALBUM
        CMP #<516
        BCC HMC_DO_WAVPG
HMC_DO_QUIT:
        PLA
        PLA
        JMP EXIT_STOP_AUDIO
HMC_DO_PLAY:
        JMP TOGGLE_PLAY_PAUSE
HMC_DO_BEGIN:
        JMP RESTART_TRACK_BEGIN
HMC_DO_ALBUM:
        JMP TOGGLE_ALBUM_MODE
HMC_DO_WAVPG:
        JMP TOGGLE_WAV_PAGE

; ============================================================================
; READ_DIRECTORIES: Sector $2001 (MP3_DIR_BUF) en Sector $2000 (WAV_DIR_BUF)
; ============================================================================
READ_DIRECTORIES:
        LDA #0
        STA DISK_FORCE_RD
        JSR ROM_SD_INIT

        LDA #$01
        STA DISK_SEC_LO
        LDA #$20
        STA DISK_SEC_HI
        LDA #<MP3_DIR_BUF
        STA ZP_DST
        LDA #>MP3_DIR_BUF
        STA ZP_DST+1
        JSR ROM_READ_SEC

        LDA #$00
        STA DISK_SEC_LO
        LDA #$20
        STA DISK_SEC_HI
        LDA #<WAV_DIR_BUF
        STA ZP_DST
        LDA #>WAV_DIR_BUF
        STA ZP_DST+1
        JMP ROM_READ_SEC

; ============================================================================
; LOAD_AND_PLAY_SELECTED
; ============================================================================
LOAD_AND_PLAY_SELECTED:
        LDA #0
        STA IO_ADMA_CTRL
        STA IO_PCM_RATE
        STA REM_BG_BANKS
        LDA #128
        STA IO_PCM_DAC

        LDA ACTIVE_PANE
        STA PLAY_PANE
        BNE LAPS_SETUP_WAV

        LDA SEL_MP3
        STA PLAY_IDX
        JSR SET_MP3_DIR_PTR
        LDY #22
        LDA (ZP_PTR_LO),Y
        STA LOAD_SEC_CNT
        INY
        LDA (ZP_PTR_LO),Y
        BNE LAPS_MP3_HI_OK
        LDA #2
LAPS_MP3_HI_OK:
        STA TOTAL_PG_HI
        LDA #0
        STA TOTAL_PG_LO
        INY
        LDA (ZP_PTR_LO),Y
        BNE LAPS_MP3_RT_OK
        LDA #1
LAPS_MP3_RT_OK:
        STA CUR_RATE

        LDA TOTAL_PG_HI
        CMP #3
        BCC LAPS_MP3_SHORT
        LDA #17
        STA PLAY_START_BANK
        STA CUR_LOAD_BANK
        LDA #0
        STA LOAD_SEC_CNT
        BEQ LAPS_MP3_UI
LAPS_MP3_SHORT:
        LDA SEL_MP3
        ASL A
        CLC
        ADC #46
        STA PLAY_START_BANK
        STA CUR_LOAD_BANK

LAPS_MP3_UI:
        JSR DRAW_BOTH_PANES
        JSR DRAW_NOW_PLAYING
        JSR DRAW_RATE_BTNS

        LDA TOTAL_PG_HI
        CMP #3
        BCS LAPS_MP3_DO_SD
        LDX SEL_MP3
        LDA MP3_CACHED,X
        BNE LAPS_START_READY

LAPS_MP3_DO_SD:
        JSR SET_MP3_DIR_PTR
        LDY #20
        LDA (ZP_PTR_LO),Y
        STA DISK_SEC_LO
        INY
        LDA (ZP_PTR_LO),Y
        STA DISK_SEC_HI

        JSR STREAM_SECTORS_FROM_SD
        LDA TOTAL_PG_HI
        CMP #3
        BCC LAPS_MP3_SET_CACHED
        SEC
        SBC #2
        STA REM_BG_BANKS
        LDA #128
        STA LOAD_SEC_CNT
        BNE LAPS_START_READY
LAPS_MP3_SET_CACHED:
        LDX SEL_MP3
        LDA #1
        STA MP3_CACHED,X
        BNE LAPS_START_READY

LAPS_SETUP_WAV:
        LDA WAV_PAGE
        ASL A
        ASL A
        ASL A
        CLC
        ADC SEL_WAV
        STA PLAY_IDX
        ADC #1
        STA PLAY_START_BANK
        STA CUR_LOAD_BANK

        JSR SET_WAV_DIR_PTR
        LDY #23
        LDA (ZP_PTR_LO),Y
        BNE LAPS_WPG_OK
        LDA #128
LAPS_WPG_OK:
        STA TOTAL_PG_LO
        LDA #0
        STA TOTAL_PG_HI
        INY
        LDA (ZP_PTR_LO),Y
        BNE LAPS_WRT_OK
        LDA #1
LAPS_WRT_OK:
        STA CUR_RATE

        JSR DRAW_BOTH_PANES
        JSR DRAW_NOW_PLAYING
        JSR DRAW_RATE_BTNS

        LDX PLAY_IDX
        LDA WAV_CACHED,X
        BNE LAPS_START_READY

        JSR SET_WAV_DIR_PTR
        LDY #20
        LDA (ZP_PTR_LO),Y
        STA DISK_SEC_LO
        INY
        LDA (ZP_PTR_LO),Y
        STA DISK_SEC_HI
        LDA #64
        STA LOAD_SEC_CNT

        JSR STREAM_SECTORS_FROM_SD
        LDX PLAY_IDX
        LDA #1
        STA WAV_CACHED,X

LAPS_START_READY:
        LDA #1
        STA IS_PLAYING
        JSR START_HULP_CPU_FULL
        JSR UPDATE_FM_PAD
        JSR DRAW_NOW_PLAYING
        JMP DRAW_TRANSPORT_BTNS

SET_MP3_DIR_PTR:
        LDA PLAY_IDX
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        STA ZP_PTR_LO
        LDA #>MP3_DIR_BUF
        STA ZP_PTR_HI
        RTS

SET_WAV_DIR_PTR:
        LDA PLAY_IDX
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        STA ZP_PTR_LO
        LDA #>WAV_DIR_BUF
        ADC #0
        STA ZP_PTR_HI
        RTS

; ============================================================================
; STREAM_SECTORS_FROM_SD
; ============================================================================
STREAM_SECTORS_FROM_SD:
        LDX #80                 ; Box 10: Wis statusregel
        JSR DRAW_BOX_FROM_TBL
        LDA #18
        LDX #0
        LDY #240
        JSR SET_XY
        LDA #$FC
        STA ZP_COL
        LDA #<STR_LOADING_SD
        LDX #>STR_LOADING_SD
        JSR GPU_TEXT_AX

        LDX #88                 ; Box 11: Wis voortgangsbalk naar zwart
        JSR DRAW_BOX_FROM_TBL

        LDA #0
        STA DISK_FORCE_RD
        STA LOAD_PAGE_PTR
        STA PROG_X_LO
        STA PROG_X_HI
        JSR ROM_SD_INIT
        LDA CUR_LOAD_BANK
        STA IO_RD_BANK

SSFS_LP:
        LDA #<SEC_TMP_BUF
        STA ZP_DST
        LDA #>SEC_TMP_BUF
        STA ZP_DST+1
        JSR ROM_READ_SEC
        JSR BSRAM_COPY_SEC

        LDA LOAD_SEC_CNT
        AND #$03
        BNE SSFS_NEXT
        LDA #32
        CLC
        ADC PROG_X_LO
        STA ZP_X_LO
        LDA #0
        ADC PROG_X_HI
        STA ZP_X_HI
        LDA #<286
        STA ZP_Y_LO
        LDA #>286
        STA ZP_Y_HI
        LDA #8
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #12
        STA ZP_H_LO
        LDA #$1F
        STA ZP_COL
        JSR GPU_RECT

        LDA PLAY_PANE
        BNE SSFS_ADV32
        LDA TOTAL_PG_HI
        CMP #1
        BEQ SSFS_ADV16
        LDA #8
        BNE SSFS_ADD_PX
SSFS_ADV16:
        LDA #16
        BNE SSFS_ADD_PX
SSFS_ADV32:
        LDA #32
SSFS_ADD_PX:
        CLC
        ADC PROG_X_LO
        STA PROG_X_LO
        BCC SSFS_NEXT
        INC PROG_X_HI
SSFS_NEXT:
        DEC LOAD_SEC_CNT
        BNE SSFS_LP
        RTS

; ============================================================================
; UPDATE_LIVE_VISUALS: 16-Band Spectrum Equalizer & Voortgangsbalk
; ============================================================================
UPDATE_LIVE_VISUALS:
        LDA TOTAL_PG_LO
        SEC
        SBC IO_ADMA_PG_L
        STA PROG_X_LO
        LDA TOTAL_PG_HI
        SBC IO_ADMA_PG_H
        BPL ULV_PG_POS
        LDA #0
        STA PROG_X_LO
ULV_PG_POS:
        STA PROG_X_HI

        LDA PLAY_START_BANK
        CLC
        ADC PROG_X_HI
        STA IO_RD_BANK
        LDA PROG_X_LO
        STA IO_RD_HI

        LDA PLAY_PANE
        BNE ULV_SCALE_WAV
        LDA TOTAL_PG_HI
        CMP #1
        BNE ULV_CHK_LONG
        ASL PROG_X_LO
        ROL PROG_X_HI
        JMP ULV_DRAW_PBAR
ULV_CHK_LONG:
        CMP #3
        BCC ULV_DRAW_PBAR
        LSR PROG_X_HI
        ROR PROG_X_LO
        CMP #5
        BCC ULV_DRAW_PBAR
        LSR PROG_X_HI
        ROR PROG_X_LO
        CMP #9
        BCC ULV_DRAW_PBAR
        LSR PROG_X_HI
        ROR PROG_X_LO
        CMP #17
        BCC ULV_DRAW_PBAR
        LSR PROG_X_HI
        ROR PROG_X_LO
        JMP ULV_DRAW_PBAR
ULV_SCALE_WAV:
        ASL PROG_X_LO
        ROL PROG_X_HI
        ASL PROG_X_LO
        ROL PROG_X_HI

ULV_DRAW_PBAR:
        LDA PROG_X_HI
        CMP #2
        BCC ULV_PB_OK
        LDA #2
        STA PROG_X_HI
        LDA #0
        STA PROG_X_LO
ULV_PB_OK:
        LDA #<286
        STA ZP_Y_LO
        LDA #>286
        STA ZP_Y_HI
        LDA #12
        STA ZP_H_LO

        LDA PROG_X_LO
        ORA PROG_X_HI
        BEQ ULV_PB_RIGHT
        LDA #32
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA PROG_X_LO
        STA ZP_W_LO
        LDA PROG_X_HI
        STA ZP_W_HI
        LDA #$1C
        STA ZP_COL
        JSR GPU_RECT

ULV_PB_RIGHT:
        LDA #0
        SEC
        SBC PROG_X_LO
        STA ZP_W_LO
        LDA #2
        SBC PROG_X_HI
        STA ZP_W_HI
        ORA ZP_W_LO
        BEQ ULV_DRAW_EQ
        LDA #32
        CLC
        ADC PROG_X_LO
        STA ZP_X_LO
        LDA #0
        ADC PROG_X_HI
        STA ZP_X_HI
        LDA #$00
        STA ZP_COL
        JSR GPU_RECT

ULV_DRAW_EQ:
        INC EQ_PHASE
        LDX #0
ULV_EQ_LP:
        STX TEMP_IDX
        TXA
        ASL A
        ASL A
        ASL A
        ASL A
        EOR EQ_PHASE
        STA IO_RD_LO
        LDA IO_RD_DATA
        SEC
        SBC #128
        BPL ULV_ABS_OK
        EOR #$FF
        CLC
        ADC #1
ULV_ABS_OK:
        LSR A
        CLC
        ADC #4
        CMP #38
        BCC ULV_H_OK
        LDA #38
ULV_H_OK:
        STA SAMPLE_PEAK

        LDX TEMP_IDX
        LDA EQ_BAR_XL,X
        STA ZP_X_LO
        LDA EQ_BAR_XH,X
        STA ZP_X_HI
        LDA #13
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        STA ZP_Y_HI

        LDA #238
        STA ZP_Y_LO
        LDA #40
        SEC
        SBC SAMPLE_PEAK
        STA ZP_H_LO
        LDA #$01
        STA ZP_COL
        JSR GPU_RECT

        LDA #278
        SEC
        SBC SAMPLE_PEAK
        STA ZP_Y_LO
        LDA SAMPLE_PEAK
        STA ZP_H_LO
        LDX TEMP_IDX
        LDA EQ_BAR_COL,X
        STA ZP_COL
        JSR GPU_RECT

        LDX TEMP_IDX
        INX
        CPX #16
        BCC ULV_EQ_LP
        RTS

; ============================================================================
; UPDATE_FM_PAD
; ============================================================================
UPDATE_FM_PAD:
        LDA FM_PAD_EN
        BEQ UFP_OFF
        LDA IS_PLAYING
        BEQ UFP_OFF
        LDA #2
        STA IO_SYNTH_INST
        LDA #7
        STA IO_SYNTH_FX
        LDX #0
        LDA #$30
        LDY #$96
        JSR SET_FM_CH
        LDX #1
        LDA #$48
        LDY #$E1
        JSR SET_FM_CH
        LDX #2
        LDA #$32
        LDY #$7A
        JMP SET_FM_CH
UFP_OFF:
        LDX #0
        JSR SET_FM_SILENT
        LDX #1
        JSR SET_FM_SILENT
        LDX #2
SET_FM_SILENT:
        LDA #16
        STA IO_GPU
        STX IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        RTS
SET_FM_CH:
        PHA
        LDA #16
        STA IO_GPU
        STX IO_GPU
        PLA
        STA IO_GPU
        STY IO_GPU
        LDA #0
        STA IO_GPU
        LDA #75
        STA IO_GPU
        RTS

; ============================================================================
; Midnight-Commander Dual-Pane UI Tekenroutines
; ============================================================================
DRAW_FULL_UI:
        LDA #1
        STA IO_GPU
        LDA #$02
        STA IO_GPU

        ; Teken alle 8 hoofd-kaders uit UI_BOX_TBL (8 * 8 = 64 bytes)
        LDX #0
DFU_BOX_LP:
        STX TEMP_IDX
        JSR DRAW_BOX_FROM_TBL
        LDX TEMP_IDX
        TXA
        CLC
        ADC #8
        TAX
        CPX #64
        BCC DFU_BOX_LP

        LDA #10
        LDX #0
        LDY #5
        JSR SET_XY
        LDA #$00
        STA ZP_COL
        LDA #<STR_TOP_BAR
        LDX #>STR_TOP_BAR
        JSR GPU_TEXT_AX

        LDA #<334
        LDX #>334
        LDY #224
        JSR SET_XY
        LDA #$1F
        STA ZP_COL
        LDA #<STR_EQ_HDR
        LDX #>STR_EQ_HDR
        JSR GPU_TEXT_AX

        LDA #6
        LDX #0
        LDY #<347
        JSR SET_XY
        LDA #1
        STA ZP_Y_HI
        LDA #$00
        STA ZP_COL
        LDA #<STR_MC_FKEYS
        LDX #>STR_MC_FKEYS
        JSR GPU_TEXT_AX

        JSR DRAW_BOTH_PANES
        JSR DRAW_NOW_PLAYING
        JSR DRAW_RATE_BTNS
        JMP DRAW_TRANSPORT_BTNS

DRAW_BOX_FROM_TBL:
        LDA UI_BOX_TBL,X
        STA ZP_X_LO
        LDA UI_BOX_TBL+1,X
        STA ZP_X_HI
        LDA UI_BOX_TBL+2,X
        STA ZP_Y_LO
        LDA UI_BOX_TBL+3,X
        STA ZP_Y_HI
        LDA UI_BOX_TBL+4,X
        STA ZP_W_LO
        LDA UI_BOX_TBL+5,X
        STA ZP_W_HI
        LDA UI_BOX_TBL+6,X
        STA ZP_H_LO
        LDA UI_BOX_TBL+7,X
        STA ZP_COL
        JMP GPU_RECT

SET_XY:
        STA ZP_X_LO
        STX ZP_X_HI
        STY ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        RTS

GPU_TEXT_AX:
        STA ZP_PTR_LO
        STX ZP_PTR_HI
        JMP GPU_TEXT_1X

; ============================================================================
; DRAW_BOTH_PANES
; ============================================================================
DRAW_BOTH_PANES:
        JSR DRAW_MP3_PANE
        JMP DRAW_WAV_PANE

DRAW_MP3_PANE:
        LDX #64                 ; Box 8: Linker Paneel Header
        LDA ACTIVE_PANE
        BEQ DMP_HDR_ACT
        LDA #$05
        BNE DMP_HDR_GO
DMP_HDR_ACT:
        LDA #$FC
DMP_HDR_GO:
        STA UI_BOX_TBL+71
        JSR DRAW_BOX_FROM_TBL

        LDA #16
        LDX #0
        LDY #28
        JSR SET_XY
        LDA ACTIVE_PANE
        BEQ DMP_HTXT_ACT
        LDA #$1F
        BNE DMP_HTXT_GO
DMP_HTXT_ACT:
        LDA #$00
DMP_HTXT_GO:
        STA ZP_COL
        LDA #<STR_MP3_HDR
        LDX #>STR_MP3_HDR
        JSR GPU_TEXT_AX

        LDA #0
        STA TEMP_IDX
DMP_ROW_LP:
        LDX TEMP_IDX
        LDA ROW_Y_TBL,X
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        STA ZP_X_HI
        LDA #12
        STA ZP_X_LO
        LDA #<298
        STA ZP_W_LO
        LDA #>298
        STA ZP_W_HI
        LDA #19
        STA ZP_H_LO

        LDA ACTIVE_PANE
        BNE DMP_CHK_PLAYING
        LDA TEMP_IDX
        CMP SEL_MP3
        BNE DMP_CHK_PLAYING
        LDA #$1F
        BNE DMP_DRAW_ROW_BG
DMP_CHK_PLAYING:
        LDA PLAY_PANE
        BNE DMP_ROW_NORM
        LDA TEMP_IDX
        CMP PLAY_IDX
        BNE DMP_ROW_NORM
        LDA #$1C
        BNE DMP_DRAW_ROW_BG
DMP_ROW_NORM:
        LDA TEMP_IDX
        CMP SEL_MP3
        BNE DMP_ROW_DARK
        LDA #$05
        BNE DMP_DRAW_ROW_BG
DMP_ROW_DARK:
        LDA #$01
DMP_DRAW_ROW_BG:
        JSR DRAW_ROW_AND_SET_FG

        LDA TEMP_IDX
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #4
        STA ZP_PTR_LO
        LDA #>MP3_DIR_BUF
        STA ZP_PTR_HI

        LDA #20
        STA ZP_X_LO
        LDX TEMP_IDX
        LDA ROW_Y_TBL,X
        CLC
        ADC #6
        STA ZP_Y_LO
        JSR GPU_TEXT_1X

        LDY #6
        LDA (ZP_PTR_LO),Y
        LDX #'0'
DMP_MIN_LP:
        CMP #60
        BCC DMP_MIN_DN
        SBC #60
        INX
        BNE DMP_MIN_LP
DMP_MIN_DN:
        STX STR_MP3_SIZE+1
        LDX #'0'
DMP_TEN_LP:
        CMP #10
        BCC DMP_TEN_DN
        SBC #10
        INX
        BNE DMP_TEN_LP
DMP_TEN_DN:
        STX STR_MP3_SIZE+3
        CLC
        ADC #'0'
        STA STR_MP3_SIZE+4
        LDA #<236
        STA ZP_X_LO
        LDA #<STR_MP3_SIZE
        LDX #>STR_MP3_SIZE
        JSR GPU_TEXT_AX

        INC TEMP_IDX
        LDA TEMP_IDX
        CMP #8
        BCC DMP_ROW_LP
        RTS

DRAW_ROW_AND_SET_FG:
        STA ZP_COL
        JSR GPU_RECT
        LDA ZP_COL
        CMP #$1F
        BEQ DRSF_BLK
        CMP #$1C
        BEQ DRSF_BLK
        LDA #$FF
        BNE DRSF_SET
DRSF_BLK:
        LDA #$00
DRSF_SET:
        STA ZP_COL
        RTS

DRAW_WAV_PANE:
        LDX #72                 ; Box 9: Rechter Paneel Header
        LDA ACTIVE_PANE
        BNE DWP_HDR_ACT
        LDA #$05
        BNE DWP_HDR_GO
DWP_HDR_ACT:
        LDA #$FC
DWP_HDR_GO:
        STA UI_BOX_TBL+79
        JSR DRAW_BOX_FROM_TBL

        LDA #<334
        LDX #>334
        LDY #28
        JSR SET_XY
        LDA ACTIVE_PANE
        BNE DWP_HTXT_ACT
        LDA #$1F
        BNE DWP_HTXT_GO
DWP_HTXT_ACT:
        LDA #$00
DWP_HTXT_GO:
        STA ZP_COL
        LDA WAV_PAGE
        BNE DWP_HDR_P2
        LDA #<STR_WAV_HDR1
        LDX #>STR_WAV_HDR1
        BNE DWP_HDR_PRT
DWP_HDR_P2:
        LDA #<STR_WAV_HDR2
        LDX #>STR_WAV_HDR2
DWP_HDR_PRT:
        JSR GPU_TEXT_AX

        LDA #0
        STA TEMP_IDX
DWP_ROW_LP:
        LDX TEMP_IDX
        LDA ROW_Y_TBL,X
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #<330
        STA ZP_X_LO
        LDA #>330
        STA ZP_X_HI
        LDA #<298
        STA ZP_W_LO
        LDA #>298
        STA ZP_W_HI
        LDA #19
        STA ZP_H_LO

        LDA WAV_PAGE
        ASL A
        ASL A
        ASL A
        CLC
        ADC TEMP_IDX
        TAY

        LDA ACTIVE_PANE
        BEQ DWP_CHK_PLAYING
        LDA TEMP_IDX
        CMP SEL_WAV
        BNE DWP_CHK_PLAYING
        LDA #$1F
        BNE DWP_DRAW_ROW_BG
DWP_CHK_PLAYING:
        LDA PLAY_PANE
        BEQ DWP_ROW_NORM
        CPY PLAY_IDX
        BNE DWP_ROW_NORM
        LDA #$1C
        BNE DWP_DRAW_ROW_BG
DWP_ROW_NORM:
        LDA TEMP_IDX
        CMP SEL_WAV
        BNE DWP_ROW_DARK
        LDA #$05
        BNE DWP_DRAW_ROW_BG
DWP_ROW_DARK:
        LDA #$01
DWP_DRAW_ROW_BG:
        JSR DRAW_ROW_AND_SET_FG

        LDA WAV_PAGE
        ASL A
        ASL A
        ASL A
        CLC
        ADC TEMP_IDX
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #4
        STA ZP_PTR_LO
        LDA #>WAV_DIR_BUF
        ADC #0
        STA ZP_PTR_HI

        LDA #<338
        STA ZP_X_LO
        LDA #>338
        STA ZP_X_HI
        LDX TEMP_IDX
        LDA ROW_Y_TBL,X
        CLC
        ADC #6
        STA ZP_Y_LO
        JSR GPU_TEXT_1X

        LDA #<554
        STA ZP_X_LO
        LDA #>554
        STA ZP_X_HI
        LDA #<STR_WAV_SIZE
        LDX #>STR_WAV_SIZE
        JSR GPU_TEXT_AX

        INC TEMP_IDX
        LDA TEMP_IDX
        CMP #8
        BCC DWP_ROW_LP
        RTS

; ============================================================================
; DRAW_NOW_PLAYING, DRAW_RATE_BTNS & DRAW_TRANSPORT_BTNS
; ============================================================================
DRAW_NOW_PLAYING:
        LDX #96                 ; Box 12: Wis Now Playing gebied
        JSR DRAW_BOX_FROM_TBL

        LDA #16
        LDX #0
        LDY #224
        JSR SET_XY
        LDA #$1F
        STA ZP_COL
        LDA #<STR_NOW_LBL
        LDX #>STR_NOW_LBL
        JSR GPU_TEXT_AX

        LDA PLAY_PANE
        BNE DNP_WAV_PTR
        JSR SET_MP3_DIR_PTR
        JMP DNP_ADD4
DNP_WAV_PTR:
        JSR SET_WAV_DIR_PTR
DNP_ADD4:
        LDA ZP_PTR_LO
        CLC
        ADC #4
        STA ZP_PTR_LO
        LDA #104
        LDX #0
        LDY #224
        JSR SET_XY
        LDA #$FC
        STA ZP_COL
        JSR GPU_TEXT_1X

        LDA #16
        LDX #0
        LDY #240
        JSR SET_XY
        LDA #$1C
        STA ZP_COL
        LDA PLAY_PANE
        BNE DNP_STAT_WAV
        LDA #<STR_STAT_MP3
        LDX #>STR_STAT_MP3
        JMP GPU_TEXT_AX
DNP_STAT_WAV:
        LDA #<STR_STAT_WAV
        LDX #>STR_STAT_WAV
        JMP GPU_TEXT_AX

DRAW_RATE_BTNS:
        LDX #0
DRB_LP:
        STX TEMP_IDX
        LDA RATE_BTN_XL,X
        LDY #254
        LDX #0
        JSR SET_XY
        LDA #52
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #22
        STA ZP_H_LO

        LDX TEMP_IDX
        INX
        TXA
        CMP CUR_RATE
        BEQ DRB_ACT
        LDA #$24
        BNE DRB_RECT
DRB_ACT:
        LDA #$FC
DRB_RECT:
        JSR DRAW_ROW_AND_SET_FG

        LDX TEMP_IDX
        LDA RATE_BTN_XL,X
        CLC
        ADC #6
        STA ZP_X_LO
        LDA #261
        STA ZP_Y_LO
        LDA RATE_LBL_LO,X
        LDY RATE_LBL_HI,X
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        JSR GPU_TEXT_1X

        LDX TEMP_IDX
        INX
        CPX #4
        BCC DRB_LP

        LDA #242
        LDX #0
        LDY #254
        JSR SET_XY
        LDA #66
        STA ZP_W_LO
        LDA #22
        STA ZP_H_LO
        LDA FM_PAD_EN
        BEQ DRB_FM_OFF
        LDA #$E2
        BNE DRB_FM_GO
DRB_FM_OFF:
        LDA #$24
DRB_FM_GO:
        STA ZP_COL
        JSR GPU_RECT

        LDA #250
        STA ZP_X_LO
        LDA #261
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA #<STR_BTN_FM
        LDX #>STR_BTN_FM
        JMP GPU_TEXT_AX

DRAW_TRANSPORT_BTNS:
        LDX #0
DTB_LP:
        STX TEMP_IDX
        LDA TBTN_XL,X
        STA ZP_X_LO
        LDA TBTN_XH,X
        STA ZP_X_HI
        LDA #<306
        STA ZP_Y_LO
        LDA #>306
        STA ZP_Y_HI
        LDA TBTN_W,X
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #28
        STA ZP_H_LO

        ; Kies knopkleur per knop 0..4
        CPX #0
        BNE DTB_C1
        LDA IS_PLAYING
        BEQ DTB_YEL
        LDA #$1C
        BNE DTB_DO_RECT
DTB_C1:
        CPX #2
        BNE DTB_C4
        LDA ALBUM_MODE
        BNE DTB_YEL
        LDA #$17
        BNE DTB_DO_RECT
DTB_C4:
        CPX #4
        BNE DTB_DARK
        LDA #$E0
        BNE DTB_DO_RECT
DTB_YEL:
        LDA #$FC
        BNE DTB_DO_RECT
DTB_DARK:
        LDA #$24
DTB_DO_RECT:
        JSR DRAW_ROW_AND_SET_FG

        LDX TEMP_IDX
        LDA TBTN_XL,X
        CLC
        ADC #8
        STA ZP_X_LO
        LDA TBTN_XH,X
        ADC #0
        STA ZP_X_HI
        LDA #<316
        STA ZP_Y_LO
        LDA #>316
        STA ZP_Y_HI

        ; Kies label voor knop X
        CPX #0
        BNE DTB_L2
        LDA IS_PLAYING
        BNE DTB_STD_LBL
        LDA #<STR_BTN_PAUSED
        LDX #>STR_BTN_PAUSED
        BNE DTB_PRT_LBL
DTB_L2:
        CPX #2
        BNE DTB_L3
        LDA ALBUM_MODE
        BEQ DTB_STD_LBL
        LDA #<STR_BTN_ALBUM
        LDX #>STR_BTN_ALBUM
        BNE DTB_PRT_LBL
DTB_L3:
        CPX #3
        BNE DTB_STD_LBL
        LDA WAV_PAGE
        BEQ DTB_STD_LBL
        LDA #<STR_BTN_WAVP2
        LDX #>STR_BTN_WAVP2
        BNE DTB_PRT_LBL
DTB_STD_LBL:
        LDY TEMP_IDX
        LDA TBTN_LBL_LO,Y
        LDX TBTN_LBL_HI,Y
DTB_PRT_LBL:
        JSR GPU_TEXT_AX

        LDX TEMP_IDX
        INX
        CPX #5
        BCC DTB_LP
        RTS

; ============================================================================
; GPU Primitieven & Exit
; ============================================================================
GPU_RECT:
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
        LDA ZP_W_HI
        STA IO_GPU
        LDA ZP_H_LO
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA ZP_COL
        STA IO_GPU
        RTS

GPU_TEXT_1X:
        LDA ZP_X_LO
        PHA
        LDA ZP_X_HI
        PHA
GTS_LP:
        LDY #0
        LDA (ZP_PTR_LO),Y
        BEQ GTS_DN
        INC ZP_PTR_LO
        BNE GTS_SEND
        INC ZP_PTR_HI
GTS_SEND:
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
        LDA ZP_COL
        STA IO_GPU
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC GTS_LP
        INC ZP_X_HI
        JMP GTS_LP
GTS_DN:
        PLA
        STA ZP_X_HI
        PLA
        STA ZP_X_LO
        RTS

EXIT_STOP_AUDIO:
        LDA #0
        STA IO_ADMA_CTRL
        STA IO_PCM_RATE
        LDA #128
        STA IO_PCM_DAC
        JSR ROM_SILENCE
EXIT_KEEP_AUDIO:
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        STA IO_GPU
        STA IO_MODE
        LDA #$E3
        STA IO_GPU
        LDA #12
        STA IO_TERM
        RTS

; ============================================================================
; BSRAM Sector-naar-SDRAM Kopieer-Routine ($02C0, 53 bytes)
; ============================================================================
BSRAM_SRC:
        LDA CUR_LOAD_BANK
        STA IO_RD_BANK
        LDA LOAD_PAGE_PTR
        STA IO_RD_HI
        LDY #0
BCS_P0:
        STY IO_RD_LO
        LDA SEC_TMP_BUF,Y
        STA IO_RD_DATA
        INY
        BNE BCS_P0
        INC LOAD_PAGE_PTR
        LDA LOAD_PAGE_PTR
        STA IO_RD_HI
        LDY #0
BCS_P1:
        STY IO_RD_LO
        LDA SEC_TMP_BUF+$100,Y
        STA IO_RD_DATA
        INY
        BNE BCS_P1
        INC LOAD_PAGE_PTR
        BNE BCS_DONE
        INC CUR_LOAD_BANK
        LDA CUR_LOAD_BANK
        STA IO_RD_BANK
BCS_DONE:
        RTS

; ============================================================================
; Tabellen, UI-Boxen & Teksten
; ============================================================================
MP3_CACHED:
        DB 0, 0, 0, 0, 0, 0, 0, 0
WAV_CACHED:
        DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; UI_BOX_TBL: 13 boxen van 8 bytes (x_lo, x_hi, y_lo, y_hi, w_lo, w_hi, h_lo, col)
UI_BOX_TBL:
        DB 0, 0, 0, 0, <640, >640, 18, $17          ; 0  (0): Top bar
        DB 6, 0, 20, 0, <310, >310, 194, $1F        ; 1  (8): Left border
        DB 8, 0, 22, 0, <306, >306, 190, $01        ; 2 (16): Left inner
        DB <324, >324, 20, 0, <310, >310, 194, $1F  ; 3 (24): Right border
        DB <326, >326, 22, 0, <306, >306, 190, $01  ; 4 (32): Right inner
        DB 6, 0, 218, 0, <310, >310, 64, $01        ; 5 (40): Deck left
        DB <324, >324, 218, 0, <310, >310, 64, $01  ; 6 (48): Deck right
        DB 0, 0, <342, >342, <640, >640, 18, $17    ; 7 (56): Bottom FKey bar
        DB 10, 0, 24, 0, <302, >302, 15, $FC        ; 8 (64): Left pane header
        DB <328, >328, 24, 0, <302, >302, 15, $05   ; 9 (72): Right pane header
        DB 16, 0, 238, 0, <294, >294, 12, $01       ; 10(80): Status line clear
        DB 32, 0, <286, >286, <512, >512, 12, $00   ; 11(88): Progress bar clear
        DB 12, 0, 222, 0, <298, >298, 30, $01       ; 12(96): Now Playing clear

ROW_Y_TBL:
        DB 42, 63, 84, 105, 126, 147, 168, 189

RATE_BTN_XL:
        DB 14, 70, 126, 182
RATE_LBL_LO:
        DB <STR_R8K, <STR_R11K, <STR_R16K, <STR_R22K
RATE_LBL_HI:
        DB >STR_R8K, >STR_R11K, >STR_R16K, >STR_R22K

TBTN_XL:
        DB 8, 144, <252, <388, <520
TBTN_XH:
        DB 0, 0, >252, >388, >520
TBTN_W:
        DB 128, 100, 128, 124, 114
TBTN_LBL_LO:
        DB <STR_BTN_PLAYING, <STR_BTN_BEGIN, <STR_BTN_LOOP1, <STR_BTN_WAVP1, <STR_BTN_EXIT
TBTN_LBL_HI:
        DB >STR_BTN_PLAYING, >STR_BTN_BEGIN, >STR_BTN_LOOP1, >STR_BTN_WAVP1, >STR_BTN_EXIT

EQ_BAR_XL:
        DB <334, <351, <368, <385, <402, <419, <436, <453
        DB <470, <487, <504, <521, <538, <555, <572, <589
EQ_BAR_XH:
        DB >334, >351, >368, >385, >402, >419, >436, >453
        DB >470, >487, >504, >521, >538, >555, >572, >589
EQ_BAR_COL:
        DB $1C, $1C, $1D, $1F, $1F, $3F, $7C, $FC
        DB $FC, $F8, $F4, $F0, $E0, $E2, $E7, $FF

STR_R8K:          DB "8kHz", 0
STR_R11K:         DB "11kHz", 0
STR_R16K:         DB "16kHz", 0
STR_R22K:         DB "22kHz", 0
STR_BTN_FM:       DB "M:+FM", 0

STR_TOP_BAR:      DB "MP3Commander 2.1 | Links: .MP3 (tot 4m!) | Rechts: .WAV (32KB) | Hulp-CPU", 0
STR_MP3_HDR:      DB "LINKER PANEEL: SD .MP3 LIEDJES", 0
STR_WAV_HDR1:     DB "RECHTER PANEEL: SD .WAV (PAG 1/2)", 0
STR_WAV_HDR2:     DB "RECHTER PANEEL: SD .WAV (PAG 2/2)", 0
STR_MP3_SIZE:     DB "00:16 MP3", 0
STR_WAV_SIZE:     DB "00:04 WAV", 0
STR_NOW_LBL:      DB "NU SPEELT:", 0
STR_STAT_MP3:     DB "HULP-CPU ($A018): .MP3 STREAMING ACTIEF", 0
STR_STAT_WAV:     DB "HULP-CPU ($A018): 32KB .WAV (128 PAG)", 0
STR_LOADING_SD:   DB ">> LADEN VAN MICROSD NAAR SDRAM...", 0
STR_EQ_HDR:       DB "16-BAND LIVE SPECTRUM EQUALIZER:", 0
STR_BTN_PLAYING:  DB "|> SPEELT AF", 0
STR_BTN_PAUSED:   DB "|| GEPAUZEERD", 0
STR_BTN_BEGIN:    DB "|<< BEGIN", 0
STR_BTN_LOOP1:    DB "L:LOOP NUMMER", 0
STR_BTN_ALBUM:    DB "L:ALBUM AUTO", 0
STR_BTN_WAVP1:    DB "P:WAV PAG 1/2", 0
STR_BTN_WAVP2:    DB "P:WAV PAG 2/2", 0
STR_BTN_EXIT:     DB "ESC:SLUITEN", 0
STR_MC_FKEYS:     DB "PIJL/TAB:Kies ENTER:Speel 1-8:Track SPATIE:Pauze S:Hz L:Album B:BgPlay ESC:Stop", 0
