; ============================================================================
; WAVPLAY.asm - MiniGPU SD-Kaart Digitale .WAV Audio Studio & Speler ($8000)
; Speelt echte 8-bit PCM .WAV geluidsbestanden rechtstreeks van de MicroSD-kaart
; (Sector $2000+) via het nieuwe Hardware PCM DAC Register ($A016) & Hardware
; Sample-Rate Timer ($A017: 8 kHz / 11.025 kHz / 16 kHz / 22.05 kHz) over
; 16-bit 48 kHz Stereo HDMI-Audio!
;
; Besturing (USB Muis, Alt+Pijltjes Muis of Toetsenbord):
;   1..8 of Klik op Track   = Kies & Speel .WAV Track van SD-kaart
;   SPATIE of [PLAY/PAUSE]  = Pauzeer / Hervat weergave
;   LINKS / RECHTS of Klik  = Spoel terug / vooruit (Scrub op tijdbalk!)
;   S of Klik [8k/11k/16k/22k] = Wijzig Sample Rate / Pitch live ($A017)
;   L of Klik [LOOP]        = Eindeloos herhalen Aan/Uit
;   M of Klik [+FM SYNTH]   = Mix 4-kanaals FM Synth Pad onder de .WAV audio!
;   R                       = Herlaad track vers van SD-kaart
;   Q of ESC                = Afsluiten (terug naar BASIC / MC)
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
IO_GPU          = $A020

; ROM SD-Card ABI & Variabelen
ZP_DST          = $1C
DISK_FORCE_RD   = $0491
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67

WAV_DIR_BUF     = $7A00         ; 512B SD-kaart WAV Directory buffer ($7A00-$7BFF)
SEC_TMP_BUF     = $0600         ; 512B Sector laad-buffer in snelle interne BSRAM ($0600-$07FF)
BSRAM_PLAY_PAGE = $02A0         ; 33B BSRAM 256-sample playback loop (0 SDRAM instructie-fetches!)
BSRAM_COPY_SEC  = $02C1         ; 43B BSRAM 512B sector -> SDRAM kopieer-routine
BSRAM_EXIT      = $02EC         ; 11B BSRAM exit: LDA #1 / STA $A006 / LDA #12 / STA $A001 / RTS

; Zero-Page variabelen voor WAVPLAY
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

CUR_MX_LO       = $50
CUR_MX_HI       = $51
CUR_MY_LO       = $52
CUR_MST         = $54

CUR_TRACK       = $55           ; Huidige track index (0..5)
IS_PLAYING      = $56           ; 1 = Speelt af, 0 = Gepauzeerd
PLAY_PAGE       = $57           ; Huidige 256-byte pagina in SDRAM bank (0..NUM_PAGES-1)
NUM_PAGES       = $58           ; Aantal 256-byte pagina's voor huidige track (128 = 32KB)
CUR_RATE        = $59           ; $A017 code: 1=8kHz, 2=11kHz, 3=16kHz, 4=22kHz
LOOP_MODE       = $5A           ; 1 = Loop aan, 0 = Stop aan einde
FM_PAD_EN       = $5B           ; 1 = 4-Kanaals FM Synth Pad meespelen, 0 = Uit
PEAK_AMP        = $5C           ; Gemeten piek-amplitude (0..127) van huidige pagina
SCOPE_X_IDX     = $5D           ; Huidige oscilloscoop kolom (0..31)
LOAD_SEC_CNT    = $5E           ; Teller tijdens laden van SD-kaart
LOAD_PAGE_PTR   = $5F           ; Pagina-teller tijdens laden naar SDRAM
TEMP_IDX        = $60
DEC_TENS        = $61
DEC_ONES        = $62

START:
        ; Installeer 87-byte BSRAM Audio & Sector Engine op $02A0..$02F6 zodat
        ; alle sample-loops in snelle interne FPGA Block RAM draaien (0 SDRAM instructie-fetches!)
        LDX #86
INIT_BSRAM_TRAMP:
        LDA BSRAM_TRAMP_SRC,X
        STA BSRAM_PLAY_PAGE,X
        DEX
        BPL INIT_BSRAM_TRAMP

        ; Zet 640x360 volledige grafische modus aan (verberg terminal)
        LDA #0
        STA IO_MODE

        ; Teken rechtstreeks naar zichtbare schermbuffer (TARGET 1)
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU

        ; Zet Hardware Muispijl AAN op (200, 140)
        LDA #<200
        STA IO_MOUSE_XL
        LDA #>200
        STA IO_MOUSE_XH
        LDA #140
        STA IO_MOUSE_YL
        LDA #0
        STA IO_MOUSE_ST

        ; Zet PCM DAC op rust (128) en demp FM synth
        LDA #128
        STA IO_PCM_DAC
        LDA #0
        STA IO_PCM_RATE
        JSR ROM_SILENCE
        LDA #0
        STA IO_MODE
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU

        ; Standaard instellingen (Start direct op Track 6 = 7.BOERDERIJ WEI!)
        LDA #6
        STA CUR_TRACK
        LDA #0
        STA PLAY_PAGE
        STA FM_PAD_EN
        STA SCOPE_X_IDX
        LDA #1
        STA LOOP_MODE
        STA IS_PLAYING
        LDA #1                  ; 8 kHz standaard (wordt overschreven door track-info)
        STA CUR_RATE
        LDA #128
        STA NUM_PAGES

        ; Wis SDRAM-cache vlaggen zodat tracks vers van SD-kaart geladen worden
        LDX #7
        LDA #0
CLR_CACHE_LP:
        STA TRK_CACHED,X
        DEX
        BPL CLR_CACHE_LP

        ; Lees WAV-Directory van SD-kaart Sector $2000 (8192)
        JSR READ_WAV_DIRECTORY

        ; Teken volledige Studio UI
        JSR DRAW_FULL_UI

        ; Laad en start Track 0 meteen!
        JSR SELECT_AND_LOAD_TRACK

; ============================================================================
; Hoofdlus: Speelt per iteratie 1 pagina (256 samples) hardware-getimed af
; wanneer IS_PLAYING=1, werkt VU-meter/Oscilloscoop bij en leest Muis/Toetsen!
; ============================================================================
MAIN_LOOP:
        LDA IS_PLAYING
        BEQ ML_IDLE_WAIT

        ; --- Speel 1 pagina (256 samples) uit SDRAM Bank (32 + CUR_TRACK) ---
        LDA CUR_TRACK
        CLC
        ADC #32
        STA IO_RD_BANK
        LDA PLAY_PAGE
        STA IO_RD_HI
        LDA CUR_RATE
        STA IO_PCM_RATE

        ; Voer de volledige 256-sample loop uit vanuit interne BSRAM ($02A0)!
        JSR BSRAM_PLAY_PAGE

        ; Verdeel Oscilloscoop, VU-meter en Progress-slice over 4 pagina's (<30us per pagina = 0% audio-stutter!)
        JSR UPDATE_LIVE_VISUALS

ML_ADV_PAGE:
        INC PLAY_PAGE
        LDA PLAY_PAGE
        CMP NUM_PAGES
        BCC ML_CHECK_INPUT

        ; Einde van de track bereikt!
        LDA #0
        STA PLAY_PAGE
        LDA LOOP_MODE
        BNE ML_LOOP_RESTART

        ; Stop aan einde als LOOP_MODE = 0
        STA IS_PLAYING
        STA IO_PCM_RATE
        LDA #128
        STA IO_PCM_DAC
        JSR UPDATE_FM_PAD
        JSR DRAW_TRANSPORT_BTNS
        JSR DRAW_PROGRESS_BAR
        JMP ML_CHECK_INPUT

ML_LOOP_RESTART:
        JSR DRAW_PROGRESS_BAR
        JMP ML_CHECK_INPUT

ML_IDLE_WAIT:
        ; In pauze-stand: zet DAC op rust (128) en wacht 10ms
        LDA #0
        STA IO_PCM_RATE
        LDA #128
        STA IO_PCM_DAC
        LDA #1
        STA IO_DELAY

ML_CHECK_INPUT:
        ; 1. Controleer Hardware Muis Klik ($A00F bit 3 = click latch)
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
        BEQ ML_CHECK_KEYS
        JSR HANDLE_MOUSE_CLICK

ML_CHECK_KEYS:
        ; 2. Controleer Toetsenbord ($A000 bit 0 = key ready, bit 7 = ESC)
        LDA IO_STATUS
        BPL ML_CHK_NORM_KEY
        LDA IO_TERM             ; Clear ESC
        JMP EXIT_PROGRAM
ML_CHK_NORM_KEY:
        AND #$01
        BNE ML_READ_KEY
        JMP MAIN_LOOP

ML_READ_KEY:
        LDA IO_TERM
        CMP #27                 ; ESC
        BNE MK_NOT_ESC
        JMP EXIT_PROGRAM
MK_NOT_ESC:
        CMP #'Q'
        BNE MK_NOT_Q
        JMP EXIT_PROGRAM
MK_NOT_Q:
        CMP #'q'
        BNE MK_NOT_LQ
        JMP EXIT_PROGRAM
MK_NOT_LQ:
        CMP #' '                ; SPATIE = Play / Pause
        BNE MK_NOT_SPACE
        JSR TOGGLE_PLAY_PAUSE
        JMP MAIN_LOOP
MK_NOT_SPACE:
        CMP #'B'
        BEQ MK_DO_REW
        CMP #'b'
        BNE MK_NOT_B
MK_DO_REW:
        LDA #0
        STA PLAY_PAGE
        JSR DRAW_PROGRESS_BAR
        JMP MAIN_LOOP
MK_NOT_B:
        CMP #'L'
        BEQ MK_DO_LOOP
        CMP #'l'
        BNE MK_NOT_L
MK_DO_LOOP:
        LDA LOOP_MODE
        EOR #$01
        STA LOOP_MODE
        JSR DRAW_TRANSPORT_BTNS
        JMP MAIN_LOOP
MK_NOT_L:
        CMP #'M'
        BEQ MK_DO_FM
        CMP #'m'
        BNE MK_NOT_M
MK_DO_FM:
        LDA FM_PAD_EN
        EOR #$01
        STA FM_PAD_EN
        JSR UPDATE_FM_PAD
        JSR DRAW_TRANSPORT_BTNS
        JMP MAIN_LOOP
MK_NOT_M:
        CMP #'S'
        BEQ MK_DO_RATE
        CMP #'s'
        BNE MK_NOT_S
MK_DO_RATE:
        LDX CUR_RATE
        INX
        CPX #5
        BCC MK_SET_RT
        LDX #1
MK_SET_RT:
        STX CUR_RATE
        JSR DRAW_RATE_BTNS
        JMP MAIN_LOOP
MK_NOT_S:
        CMP #'R'
        BEQ MK_DO_RELOAD
        CMP #'r'
        BNE MK_NOT_R
MK_DO_RELOAD:
        LDX CUR_TRACK
        LDA #0
        STA TRK_CACHED,X
        JSR SELECT_AND_LOAD_TRACK
        JMP MAIN_LOOP
MK_NOT_R:
        ; Pijltje Links ('A' / $1C) of Rechts ('D' / $1D) = Scrub -16 / +16 pagina's
        CMP #'A'
        BEQ MK_SEEK_BACK
        CMP #'a'
        BNE MK_CHK_RIGHT
MK_SEEK_BACK:
        LDA PLAY_PAGE
        SEC
        SBC #16
        BCS MK_SB_OK
        LDA #0
MK_SB_OK:
        STA PLAY_PAGE
        JSR DRAW_PROGRESS_BAR
        JMP MAIN_LOOP

MK_CHK_RIGHT:
        CMP #'D'
        BEQ MK_SEEK_FWD
        CMP #'d'
        BNE MK_CHK_UPDN
MK_SEEK_FWD:
        LDA PLAY_PAGE
        CLC
        ADC #16
        CMP NUM_PAGES
        BCC MK_SF_OK
        LDA NUM_PAGES
        SEC
        SBC #1
MK_SF_OK:
        STA PLAY_PAGE
        JSR DRAW_PROGRESS_BAR
        JMP MAIN_LOOP

MK_CHK_UPDN:
        CMP #'W'
        BEQ MK_PREV_TRK
        CMP #'w'
        BNE MK_CHK_DN
MK_PREV_TRK:
        LDA CUR_TRACK
        BEQ MK_WRAP_LAST
        DEC CUR_TRACK
        JMP MK_LOAD_NEW
MK_WRAP_LAST:
        LDA #7
        STA CUR_TRACK
        JMP MK_LOAD_NEW

MK_CHK_DN:
        CMP #'S'-32             ; Fallback
        CMP #'X'
        BEQ MK_NEXT_TRK
        CMP #'x'
        BNE MK_CHK_DIGITS
MK_NEXT_TRK:
        INC CUR_TRACK
        LDA CUR_TRACK
        CMP #8
        BCC MK_LOAD_NEW
        LDA #0
        STA CUR_TRACK
        JMP MK_LOAD_NEW

MK_CHK_DIGITS:
        ; Toets '1'..'8' kiest direct Track 0..7!
        CMP #'1'
        BCC MK_DONE
        CMP #'9'
        BCS MK_DONE
        SEC
        SBC #'1'
        STA CUR_TRACK
MK_LOAD_NEW:
        JSR SELECT_AND_LOAD_TRACK
MK_DONE:
        JMP MAIN_LOOP

; ============================================================================
; TOGGLE_PLAY_PAUSE
; ============================================================================
TOGGLE_PLAY_PAUSE:
        LDA IS_PLAYING
        EOR #$01
        STA IS_PLAYING
        JSR UPDATE_FM_PAD
        JSR DRAW_TRANSPORT_BTNS
        RTS

; ============================================================================
; HANDLE_MOUSE_CLICK: Verwerk klik op Playlist, Rate-knoppen, Scrub-balk & Transport
; ============================================================================
HANDLE_MOUSE_CLICK:
        ; 1. Klik in Playlist-paneel? (X = 16..276, Y = 66..241, 22px per rij voor 8 tracks)
        LDA CUR_MX_HI
        BNE HMC_CHK_RIGHT_PNL
        LDA CUR_MX_LO
        CMP #16
        BCC HMC_CHK_BOTTOM
        LDA CUR_MY_LO
        CMP #66
        BCC HMC_CHK_BOTTOM
        CMP #242
        BCS HMC_CHK_BOTTOM
        SEC
        SBC #66
        LDX #0
HMC_DIV28:
        CMP #22
        BCC HMC_GOT_TRK
        SBC #22
        INX
        CPX #7
        BCC HMC_DIV28
HMC_GOT_TRK:
        STX CUR_TRACK
        JSR SELECT_AND_LOAD_TRACK
        RTS

HMC_CHK_RIGHT_PNL:
        ; 2. Klik op Sample Rate knoppen? (Y = 216..242, X = 300..612)
        LDA CUR_MY_LO
        CMP #214
        BCC HMC_CHK_BOTTOM
        CMP #244
        BCS HMC_CHK_BOTTOM
        ; Bereken welke van de 4 rate-knoppen:
        ; X < 376 -> Rate 1 (8k), X < 456 -> Rate 2 (11k), X < 536 -> Rate 3 (16k), anders Rate 4 (22k)
        LDA CUR_MX_HI
        CMP #1
        BNE HMC_RATE_HI2
        LDA CUR_MX_LO
        CMP #<376
        BCC HMC_SET_R1
        CMP #<456
        BCC HMC_SET_R2
        JMP HMC_SET_R3
HMC_RATE_HI2:
        LDA CUR_MX_LO
        CMP #<536
        BCC HMC_SET_R3
        LDA #4
        JMP HMC_APPLY_RATE
HMC_SET_R1:
        LDA #1
        JMP HMC_APPLY_RATE
HMC_SET_R2:
        LDA #2
        JMP HMC_APPLY_RATE
HMC_SET_R3:
        LDA #3
HMC_APPLY_RATE:
        STA CUR_RATE
        JSR DRAW_RATE_BTNS
        RTS

HMC_CHK_BOTTOM:
        ; 3. Klik op Scrubbing Voortgangsbalk? (Y = 264..290, X = 32..543)
        LDA CUR_MY_LO
        CMP #264
        BCC HMC_CHK_TRANS
        CMP #291
        BCS HMC_CHK_TRANS
        ; PLAY_PAGE = ((MX - 32) >> 2), begrensd op 0..NUM_PAGES-1
        LDA CUR_MX_LO
        SEC
        SBC #32
        STA ZP_X_LO
        LDA CUR_MX_HI
        SBC #0
        BMI HMC_SCRUB_ZERO
        STA ZP_X_HI
        LSR ZP_X_HI
        ROR ZP_X_LO
        LSR ZP_X_HI
        ROR ZP_X_LO
        LDA ZP_X_LO
        CMP NUM_PAGES
        BCC HMC_SCRUB_SET
        LDA NUM_PAGES
        SEC
        SBC #1
        JMP HMC_SCRUB_SET
HMC_SCRUB_ZERO:
        LDA #0
HMC_SCRUB_SET:
        STA PLAY_PAGE
        LDA #1
        STA IS_PLAYING
        JSR UPDATE_FM_PAD
        JSR DRAW_TRANSPORT_BTNS
        JSR DRAW_PROGRESS_BAR
        RTS

HMC_CHK_TRANS:
        ; 4. Klik op Transport-knoppen onderaan? (Y = 296..328)
        LDA CUR_MY_LO
        CMP #296
        BCC HMC_DONE
        CMP #330
        BCS HMC_DONE

        ; Knop 1: [PLAY/PAUSE] (X = 32..168)
        ; Knop 2: [BEGIN]      (X = 180..284)
        ; Knop 3: [LOOP]       (X = 296..436)
        ; Knop 4: [+FM SYNTH]  (X = 448..540)
        ; Knop 5: [STOP/EXIT]  (X = 548..616)
        LDA CUR_MX_HI
        BNE HMC_TR_HI1
        LDA CUR_MX_LO
        CMP #172
        BCC HMC_BTN_PLAY
        JMP HMC_BTN_BEGIN
HMC_TR_HI1:
        CMP #1
        BNE HMC_TR_HI2
        LDA CUR_MX_LO
        CMP #<290
        BCC HMC_BTN_BEGIN
        CMP #<442
        BCC HMC_BTN_LOOP
        JMP HMC_BTN_FM
HMC_TR_HI2:
        LDA CUR_MX_LO
        CMP #<544
        BCC HMC_BTN_FM
        PLA                     ; Pop JSR return adres en sluit netjes af!
        PLA
        JMP EXIT_PROGRAM

HMC_BTN_PLAY:
        JMP TOGGLE_PLAY_PAUSE
HMC_BTN_BEGIN:
        LDA #0
        STA PLAY_PAGE
        JMP DRAW_PROGRESS_BAR
HMC_BTN_LOOP:
        LDA LOOP_MODE
        EOR #$01
        STA LOOP_MODE
        JMP DRAW_TRANSPORT_BTNS
HMC_BTN_FM:
        LDA FM_PAD_EN
        EOR #$01
        STA FM_PAD_EN
        JSR UPDATE_FM_PAD
        JMP DRAW_TRANSPORT_BTNS
HMC_DONE:
        RTS

; ============================================================================
; READ_WAV_DIRECTORY: Lees Sector $2000 (8192) van SD-kaart naar $0500
; Als Sector $2000 nog geen "WAV!" header heeft, kopieer standaard tabel.
; ============================================================================
READ_WAV_DIRECTORY:
        LDA #0
        STA DISK_FORCE_RD
        JSR ROM_SD_INIT
        LDA #$00
        STA DISK_SEC_LO
        LDA #$20
        STA DISK_SEC_HI
        LDA #<WAV_DIR_BUF
        STA ZP_DST
        LDA #>WAV_DIR_BUF
        STA ZP_DST+1
        JSR ROM_READ_SEC

        ; Controleer of eerste én zevende entry beginnen met "WAV!"
        LDA WAV_DIR_BUF
        CMP #'W'
        BNE RWD_FALLBACK
        LDA WAV_DIR_BUF+192
        CMP #'W'
        BNE RWD_FALLBACK
        RTS

RWD_FALLBACK:
        ; Kopieer ingebouwde standaard WAV-directory (8x32 = 256 bytes) naar WAV_DIR_BUF
        LDX #0
RWD_FB_LP:
        LDA DEFAULT_WAV_DIR,X
        STA WAV_DIR_BUF,X
        INX
        BNE RWD_FB_LP
        RTS

; ============================================================================
; SELECT_AND_LOAD_TRACK: Haal metadata voor CUR_TRACK op, laad sectoren van
; SD-kaart naar SDRAM Bank (32 + CUR_TRACK) indien nog niet gecachet, en start!
; ============================================================================
SELECT_AND_LOAD_TRACK:
        ; Demp PCM tijdens wisselen
        LDA #0
        STA IO_PCM_RATE
        LDA #128
        STA IO_PCM_DAC

        ; Bereken pointer naar WAV_DIR_BUF + CUR_TRACK * 32 -> ZP_PTR
        LDA CUR_TRACK
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        STA ZP_PTR_LO
        LDA #>WAV_DIR_BUF
        STA ZP_PTR_HI

        ; Haal NUM_PAGES (+23) en CUR_RATE (+24) op uit directory-entry
        LDY #23
        LDA (ZP_PTR_LO),Y
        BNE SLT_PG_OK
        LDA #128
SLT_PG_OK:
        STA NUM_PAGES
        INY
        LDA (ZP_PTR_LO),Y
        BNE SLT_RT_OK
        LDA #1
SLT_RT_OK:
        STA CUR_RATE

        ; Herteken Playlist-selectie en Rate-knoppen
        JSR DRAW_PLAYLIST
        JSR DRAW_RATE_BTNS
        JSR DRAW_NOW_PLAYING

        ; Controleer of deze track al in SDRAM Bank (32 + CUR_TRACK) staat
        LDX CUR_TRACK
        LDA TRK_CACHED,X
        BNE SLT_READY

        ; --- Laad Track Sectoren van SD-kaart naar SDRAM Bank (32 + CUR_TRACK) ---
        ; Bereken opnieuw ZP_PTR = WAV_DIR_BUF + CUR_TRACK * 32
        LDA CUR_TRACK
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        STA ZP_PTR_LO
        LDA #>WAV_DIR_BUF
        STA ZP_PTR_HI

        LDY #20
        LDA (ZP_PTR_LO),Y
        STA DISK_SEC_LO
        INY
        LDA (ZP_PTR_LO),Y
        STA DISK_SEC_HI
        INY
        LDA (ZP_PTR_LO),Y       ; Aantal 512B sectoren (bijv. 64 = 32KB)
        BNE SLT_SEC_OK
        LDA #64
SLT_SEC_OK:
        STA LOAD_SEC_CNT
        LDA #0
        STA LOAD_PAGE_PTR

        ; Controleer of SD-kaart aanwezig is; zo ja, lees sectoren!
        LDA #0
        STA DISK_FORCE_RD
        STA PLAY_PAGE
        JSR DRAW_PROGRESS_BAR
        JSR ROM_SD_INIT
        LDA CUR_TRACK
        CLC
        ADC #32
        STA IO_RD_BANK

SLT_SECTOR_LP:
        ; Lees 1 sector (512 bytes) van SD-kaart naar SEC_TMP_BUF ($0600-$07FF in BSRAM!)
        LDA #<SEC_TMP_BUF
        STA ZP_DST
        LDA #>SEC_TMP_BUF
        STA ZP_DST+1
        JSR ROM_READ_SEC

        ; Kopieer 512 bytes ($0600-$07FF) vanuit BSRAM ($02C1) naar SDRAM Bank (32 + CUR_TRACK)!
        JSR BSRAM_COPY_SEC

        ; Teken een 16x16px laad-blokje op de progress bar elke 2 sectoren (4 pagina's)
        LDA LOAD_PAGE_PTR
        SEC
        SBC #2
        STA PLAY_PAGE
        JSR ULV_PHASE3_PROG

        DEC LOAD_SEC_CNT
        BNE SLT_SECTOR_LP

        ; Markeer track als geladen in SDRAM!
        LDX CUR_TRACK
        LDA #1
        STA TRK_CACHED,X

SLT_READY:
        LDA #0
        STA PLAY_PAGE
        LDA #1
        STA IS_PLAYING
        JSR UPDATE_FM_PAD
        JSR DRAW_TRANSPORT_BTNS
        JSR DRAW_PROGRESS_BAR
        RTS

; ============================================================================
; UPDATE_LIVE_VISUALS: Tekent live Oscilloscoop-kolom & Stereo VU-Meters
; ============================================================================
UPDATE_LIVE_VISUALS:
        LDA PLAY_PAGE
        AND #$03
        BEQ ULV_PHASE0_SCOPE
        CMP #1
        BEQ ULV_PHASE1_VUL
        CMP #2
        BNE ULV_GO_PHASE3
        JMP ULV_PHASE2_VUR
ULV_GO_PHASE3:
        JMP ULV_PHASE3_PROG

ULV_PHASE0_SCOPE:
        ; Fase 0: Teken 1 Oscilloscoop-kolom (32 kolommen van 8px op X=312..567, H=64)
        LDA SCOPE_X_IDX
        AND #$1F
        ASL A
        ASL A
        ASL A
        CLC
        ADC #<312
        STA ZP_X_LO
        LDA #>312
        ADC #0
        STA ZP_X_HI

        LDA #78
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #6
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #64
        STA ZP_H_LO
        LDA #$01
        STA ZP_COL
        JSR GPU_RECT

        LDA PEAK_AMP
        LSR A
        CLC
        ADC #2
        CMP #32
        BCC ULV_H_OK
        LDA #32
ULV_H_OK:
        STA TEMP_IDX            ; Halve hoogte (2..32)
        LDA #110
        SEC
        SBC TEMP_IDX
        STA ZP_Y_LO
        LDA TEMP_IDX
        ASL A
        STA ZP_H_LO

        LDA #$1C
        LDX TEMP_IDX
        CPX #16
        BCC ULV_COL_OK
        LDA #$FC
        CPX #24
        BCC ULV_COL_OK
        LDA #$E8
ULV_COL_OK:
        STA ZP_COL
        JSR GPU_RECT
        INC SCOPE_X_IDX
        RTS

ULV_PHASE1_VUL:
        ; Fase 1: Linker VU-balk (Y=173, H=6, X=328..567) zonder overlap!
        LDA #173
        STA ZP_Y_LO
        LDA #$1C
        JMP ULV_DRAW_ONE_VU

ULV_PHASE2_VUR:
        ; Fase 2: Rechter VU-balk (Y=189, H=6, X=328..567) zonder overlap!
        LDA #189
        STA ZP_Y_LO
        LDA #$1F

ULV_DRAW_ONE_VU:
        STA ZP_COL
        LDA #0
        STA ZP_Y_HI
        STA ZP_W_HI
        LDA #6
        STA ZP_H_LO

        LDA PEAK_AMP
        ASL A
        BNE ULV_VU_NZ
        LDA #2
ULV_VU_NZ:
        CMP #238
        BCC ULV_VU_OK
        LDA #238
ULV_VU_OK:
        STA TEMP_IDX            ; Gevulde breedte (2..238)
        CMP #160
        BCC ULV_VU_C_OK
        LDA #$FC                ; Geel bij piek
        STA ZP_COL
ULV_VU_C_OK:
        LDA #<328
        STA ZP_X_LO
        LDA #>328
        STA ZP_X_HI
        LDA TEMP_IDX
        STA ZP_W_LO
        JSR GPU_RECT

        ; Wis alleen het resterende rechterdeel (240 - TEMP_IDX) in zwart ($00)
        LDA #<328
        CLC
        ADC TEMP_IDX
        STA ZP_X_LO
        LDA #>328
        ADC #0
        STA ZP_X_HI
        LDA #240
        SEC
        SBC TEMP_IDX
        STA ZP_W_LO
        LDA #$00
        STA ZP_COL
        JMP GPU_RECT

ULV_PHASE3_PROG:
        ; Fase 3: Teken incrementeel blokje (16x16 px) op de Progress-Balk!
        LDA PLAY_PAGE
        AND #$FC
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        ASL ZP_X_LO
        ROL ZP_X_HI
        ASL ZP_X_LO
        ROL ZP_X_HI
        LDA ZP_X_LO
        CLC
        ADC #32
        STA ZP_X_LO
        LDA ZP_X_HI
        ADC #0
        STA ZP_X_HI
        LDA #<268
        STA ZP_Y_LO
        LDA #>268
        STA ZP_Y_HI
        LDA #16
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #16
        STA ZP_H_LO
        LDA #$1F
        STA ZP_COL
        JMP GPU_RECT


; ============================================================================
; UPDATE_FM_PAD: Zet 4-kanaals FM Strings/Pad akkoord AAN of UIT onder de .WAV!
; ============================================================================
UPDATE_FM_PAD:
        LDA FM_PAD_EN
        BEQ UFP_OFF
        LDA IS_PLAYING
        BEQ UFP_OFF

        ; Kies Strijkers/Strings (Instrument 2) met Stereo Chorus
        LDA #2
        STA IO_SYNTH_INST
        LDA #7
        STA IO_SYNTH_FX

        ; CH0: A2 (110 Hz -> phase_inc = 38448 = $009630), vol = 95
        LDX #0
        LDA #$30
        LDY #$96
        JSR SET_FM_CH
        ; CH1: E3 (165 Hz -> phase_inc = 57672 = $00E148), vol = 85
        LDX #1
        LDA #$48
        LDY #$E1
        JSR SET_FM_CH
        ; CH2: C#4 (277 Hz -> phase_inc = 96818 = $017A32), vol = 80
        LDA #16
        STA IO_GPU
        LDA #2
        STA IO_GPU
        LDA #$32
        STA IO_GPU
        LDA #$7A
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #80
        STA IO_GPU
        RTS

UFP_OFF:
        LDX #0
        LDA #0
        LDY #0
        JSR SET_FM_CH_SILENT
        LDX #1
        JSR SET_FM_CH_SILENT
        LDX #2
        JSR SET_FM_CH_SILENT
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
        LDA #90
        STA IO_GPU
        RTS

SET_FM_CH_SILENT:
        LDA #16
        STA IO_GPU
        STX IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        RTS

; ============================================================================
; UI Tekenroutines (640x360 Grafische WAV Studio)
; ============================================================================
DRAW_FULL_UI:
        ; Wis scherm donkerblauw (GPU Opcode 1 = CLEAR_SCREEN, kleur $02)
        LDA #1
        STA IO_GPU
        LDA #$02
        STA IO_GPU

        ; Bovenste Titelbalk (0, 0, 640, 34, kleur $03)
        LDA #0
        STA ZP_X_LO
        STA ZP_X_HI
        STA ZP_Y_LO
        STA ZP_Y_HI
        LDA #<640
        STA ZP_W_LO
        LDA #>640
        STA ZP_W_HI
        LDA #34
        STA ZP_H_LO
        LDA #$03
        STA ZP_COL
        JSR GPU_RECT

        ; Cyaan accentlijn onder titelbalk (Y=34)
        LDA #34
        STA ZP_Y_LO
        LDA #2
        STA ZP_H_LO
        LDA #$1F
        STA ZP_COL
        JSR GPU_RECT

        ; Titeltekst
        LDA #14
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #10
        STA ZP_Y_LO
        LDA #$FC                ; Geel
        STA ZP_COL
        LDA #<STR_HEADER
        STA ZP_PTR_LO
        LDA #>STR_HEADER
        STA ZP_PTR_HI
        JSR GPU_TEXT_2X

        ; Linker Playlist Paneel (X=12, Y=44, W=268, H=206, kleur $01)
        LDA #12
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #44
        STA ZP_Y_LO
        LDA #<268
        STA ZP_W_LO
        LDA #>268
        STA ZP_W_HI
        LDA #206
        STA ZP_H_LO
        LDA #$01
        STA ZP_COL
        JSR GPU_RECT

        LDA #20
        STA ZP_X_LO
        LDA #52
        STA ZP_Y_LO
        LDA #$1F
        STA ZP_COL
        LDA #<STR_PLAYLIST_HDR
        STA ZP_PTR_LO
        LDA #>STR_PLAYLIST_HDR
        STA ZP_PTR_HI
        JSR GPU_TEXT_1X

        ; Rechter Visualizer & Sample-Rate Paneel (X=292, Y=44, W=336, H=206, kleur $01)
        LDA #<292
        STA ZP_X_LO
        LDA #>292
        STA ZP_X_HI
        LDA #44
        STA ZP_Y_LO
        LDA #<336
        STA ZP_W_LO
        LDA #>336
        STA ZP_W_HI
        LDA #206
        STA ZP_H_LO
        LDA #$01
        STA ZP_COL
        JSR GPU_RECT

        LDA #<304
        STA ZP_X_LO
        LDA #>304
        STA ZP_X_HI
        LDA #52
        STA ZP_Y_LO
        LDA #$1F
        STA ZP_COL
        LDA #<STR_SCOPE_HDR
        STA ZP_PTR_LO
        LDA #>STR_SCOPE_HDR
        STA ZP_PTR_HI
        JSR GPU_TEXT_1X

        ; VU-Meter Labels ("L" en "R")
        LDA #<308
        STA ZP_X_LO
        LDA #>308
        STA ZP_X_HI
        LDA #173
        STA ZP_Y_LO
        LDA #$1C
        STA ZP_COL
        LDA #<STR_VU_L
        STA ZP_PTR_LO
        LDA #>STR_VU_L
        STA ZP_PTR_HI
        JSR GPU_TEXT_1X

        LDA #189
        STA ZP_Y_LO
        LDA #$1F
        STA ZP_COL
        LDA #<STR_VU_R
        STA ZP_PTR_LO
        LDA #>STR_VU_R
        STA ZP_PTR_HI
        JSR GPU_TEXT_1X

        ; Onderste Transport-paneel (X=12, Y=256, W=616, H=96, kleur $01)
        LDA #12
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<256
        STA ZP_Y_LO
        LDA #>256
        STA ZP_Y_HI
        LDA #<616
        STA ZP_W_LO
        LDA #>616
        STA ZP_W_HI
        LDA #96
        STA ZP_H_LO
        LDA #$01
        STA ZP_COL
        JSR GPU_RECT

        ; Help-voettekst onderaan (Y=336)
        LDA #24
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<336
        STA ZP_Y_LO
        LDA #>336
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_COL
        LDA #<STR_FOOTER
        STA ZP_PTR_LO
        LDA #>STR_FOOTER
        STA ZP_PTR_HI
        JSR GPU_TEXT_1X

        JSR DRAW_PLAYLIST
        JSR DRAW_RATE_BTNS
        JSR DRAW_TRANSPORT_BTNS
        JSR DRAW_PROGRESS_BAR
        RTS

; ============================================================================
; DRAW_PLAYLIST: Teken de 8 SD-Kaart WAV tracks links (X=20..272, Y=66..241)
; ============================================================================
DRAW_PLAYLIST:
        LDA #0
        STA TEMP_IDX
DPL_LP:
        ; Y = 66 + TEMP_IDX * 22
        LDA TEMP_IDX
        ASL A
        STA ZP_Y_LO
        ASL A
        CLC
        ADC ZP_Y_LO
        STA ZP_Y_LO
        LDA TEMP_IDX
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC ZP_Y_LO
        ADC #66
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        ; Knop achtergrond: Groen ($1C) als geselecteerd, anders donkerpaars/blauw ($05)
        LDA #20
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #252
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #19
        STA ZP_H_LO
        LDA #0
        STA ZP_H_HI

        LDA TEMP_IDX
        CMP CUR_TRACK
        BEQ DPL_ACTIVE
        LDA #$05
        JMP DPL_RECT
DPL_ACTIVE:
        LDA #$1C
DPL_RECT:
        STA ZP_COL
        JSR GPU_RECT

        ; Teken Track-titel uit WAV_DIR_BUF + TEMP_IDX*32 + 4
        LDA TEMP_IDX
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #4
        STA ZP_PTR_LO
        LDA #>WAV_DIR_BUF
        STA ZP_PTR_HI

        LDA #28
        STA ZP_X_LO
        LDA ZP_Y_LO
        CLC
        ADC #6
        STA ZP_Y_LO

        LDA TEMP_IDX
        CMP CUR_TRACK
        BEQ DPL_TXT_ACT
        LDA #$FF
        JMP DPL_TXT_GO
DPL_TXT_ACT:
        LDA #$00
DPL_TXT_GO:
        STA ZP_COL
        JSR GPU_TEXT_1X

        INC TEMP_IDX
        LDA TEMP_IDX
        CMP #8
        BCC DPL_LP
        RTS

; ============================================================================
; DRAW_NOW_PLAYING: Toon actieve tracknaam bovenin de Oscilloscoop
; ============================================================================
DRAW_NOW_PLAYING:
        LDA #<430
        STA ZP_X_LO
        LDA #>430
        STA ZP_X_HI
        LDA #50
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #188
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #12
        STA ZP_H_LO
        LDA #$01
        STA ZP_COL
        JSR GPU_RECT

        LDA CUR_TRACK
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #4
        STA ZP_PTR_LO
        LDA #>WAV_DIR_BUF
        STA ZP_PTR_HI
        LDA #<434
        STA ZP_X_LO
        LDA #>434
        STA ZP_X_HI
        LDA #52
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_COL
        JSR GPU_TEXT_1X
        RTS

; ============================================================================
; DRAW_RATE_BTNS: Teken de 4 Sample-Rate knoppen (8k / 11k / 16k / 22k Hz)
; ============================================================================
DRAW_RATE_BTNS:
        LDX #0
DRB_LP:
        STX TEMP_IDX
        LDA RATE_BTN_XL,X
        STA ZP_X_LO
        LDA RATE_BTN_XH,X
        STA ZP_X_HI
        LDA #216
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #72
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #24
        STA ZP_H_LO

        INX
        TXA
        CMP CUR_RATE
        BEQ DRB_ACT
        LDA #$24
        JMP DRB_RECT
DRB_ACT:
        LDA #$FC                ; Geel voor actieve sample rate!
DRB_RECT:
        STA ZP_COL
        JSR GPU_RECT

        LDX TEMP_IDX
        LDA RATE_BTN_XL,X
        CLC
        ADC #12
        STA ZP_X_LO
        LDA RATE_BTN_XH,X
        ADC #0
        STA ZP_X_HI
        LDA #224
        STA ZP_Y_LO
        LDA RATE_LBL_LO,X
        STA ZP_PTR_LO
        LDA RATE_LBL_HI,X
        STA ZP_PTR_HI

        INX
        TXA
        CMP CUR_RATE
        BEQ DRB_TACT
        LDA #$FF
        JMP DRB_TGO
DRB_TACT:
        LDA #$00
DRB_TGO:
        STA ZP_COL
        JSR GPU_TEXT_1X

        LDX TEMP_IDX
        INX
        CPX #4
        BCC DRB_LP
        RTS

; ============================================================================
; DRAW_PROGRESS_BAR: Teken Scrubbing Tijdbalk (X=32..543, Y=268, W=512, H=16)
; ============================================================================
DRAW_PROGRESS_BAR:
        ; Achtergrond van balk (512 px breed = 4 px per pagina voor 128 pagina's)
        LDA #32
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<268
        STA ZP_Y_LO
        LDA #>268
        STA ZP_Y_HI
        LDA #<512
        STA ZP_W_LO
        LDA #>512
        STA ZP_W_HI
        LDA #16
        STA ZP_H_LO
        LDA #0
        STA ZP_H_HI
        LDA #$00
        STA ZP_COL
        JSR GPU_RECT

        ; Gevulde balk = PLAY_PAGE * 4
        LDA PLAY_PAGE
        BEQ DPB_CURSOR
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        ASL ZP_W_LO
        ROL ZP_W_HI
        ASL ZP_W_LO
        ROL ZP_W_HI
        LDA #$1F                ; Helder Cyaan voortgangsbalk
        STA ZP_COL
        JSR GPU_RECT

DPB_CURSOR:
        ; Teken gele scrub-knop op (32 + PLAY_PAGE * 4)
        LDA PLAY_PAGE
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        ASL ZP_X_LO
        ROL ZP_X_HI
        ASL ZP_X_LO
        ROL ZP_X_HI
        LDA ZP_X_LO
        CLC
        ADC #32
        STA ZP_X_LO
        LDA ZP_X_HI
        ADC #0
        STA ZP_X_HI
        LDA #6
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #$FC
        STA ZP_COL
        JSR GPU_RECT
        RTS

; ============================================================================
; DRAW_TRANSPORT_BTNS: Teken [PLAY/PAUSE], [BEGIN], [LOOP], [+FM SYNTH], [EXIT]
; ============================================================================
DRAW_TRANSPORT_BTNS:
        ; 1. [PLAY / PAUSE] (X=32, Y=296, W=136, H=28)
        LDA #32
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<296
        STA ZP_Y_LO
        LDA #>296
        STA ZP_Y_HI
        LDA #136
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #28
        STA ZP_H_LO
        LDA #0
        STA ZP_H_HI
        LDA IS_PLAYING
        BEQ DTB_PAUSED
        LDA #$1C                ; Groen tijdens afspelen
        JMP DTB_P1
DTB_PAUSED:
        LDA #$FC                ; Geel op pauze
DTB_P1:
        STA ZP_COL
        JSR GPU_RECT

        LDA #44
        STA ZP_X_LO
        LDA #<306
        STA ZP_Y_LO
        LDA #>306
        STA ZP_Y_HI
        LDA #$00
        STA ZP_COL
        LDA IS_PLAYING
        BEQ DTB_P_TXT
        LDA #<STR_BTN_PLAYING
        STA ZP_PTR_LO
        LDA #>STR_BTN_PLAYING
        STA ZP_PTR_HI
        JMP DTB_P_GO
DTB_P_TXT:
        LDA #<STR_BTN_PAUSED
        STA ZP_PTR_LO
        LDA #>STR_BTN_PAUSED
        STA ZP_PTR_HI
DTB_P_GO:
        JSR GPU_TEXT_1X

        ; 2. [|<< BEGIN] (X=180, Y=296, W=104, H=28)
        LDA #180
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<296
        STA ZP_Y_LO
        LDA #104
        STA ZP_W_LO
        LDA #28
        STA ZP_H_LO
        LDA #$24
        STA ZP_COL
        JSR GPU_RECT

        LDA #194
        STA ZP_X_LO
        LDA #<306
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA #<STR_BTN_BEGIN
        STA ZP_PTR_LO
        LDA #>STR_BTN_BEGIN
        STA ZP_PTR_HI
        JSR GPU_TEXT_1X

        ; 3. [LOOP AAN/UIT] (X=296, Y=296, W=136, H=28)
        LDA #<296
        STA ZP_X_LO
        LDA #>296
        STA ZP_X_HI
        LDA #<296
        STA ZP_Y_LO
        LDA #136
        STA ZP_W_LO
        LDA #28
        STA ZP_H_LO
        LDA LOOP_MODE
        BEQ DTB_LP_OFF
        LDA #$17                ; Blauw/Cyaan als Loop AAN
        JMP DTB_LP_R
DTB_LP_OFF:
        LDA #$24
DTB_LP_R:
        STA ZP_COL
        JSR GPU_RECT

        LDA #<312
        STA ZP_X_LO
        LDA #>312
        STA ZP_X_HI
        LDA #<306
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA LOOP_MODE
        BEQ DTB_LPT_OFF
        LDA #<STR_BTN_LOOP_ON
        STA ZP_PTR_LO
        LDA #>STR_BTN_LOOP_ON
        STA ZP_PTR_HI
        JMP DTB_LPT_GO
DTB_LPT_OFF:
        LDA #<STR_BTN_LOOP_OFF
        STA ZP_PTR_LO
        LDA #>STR_BTN_LOOP_OFF
        STA ZP_PTR_HI
DTB_LPT_GO:
        JSR GPU_TEXT_1X

        ; 4. [+FM SYNTH] (X=444, Y=296, W=96, H=28)
        LDA #<444
        STA ZP_X_LO
        LDA #>444
        STA ZP_X_HI
        LDA #<296
        STA ZP_Y_LO
        LDA #96
        STA ZP_W_LO
        LDA #28
        STA ZP_H_LO
        LDA FM_PAD_EN
        BEQ DTB_FM_OFF
        LDA #$E3                ; Magenta/Paars als FM Pad AAN
        JMP DTB_FM_R
DTB_FM_OFF:
        LDA #$24
DTB_FM_R:
        STA ZP_COL
        JSR GPU_RECT

        LDA #<454
        STA ZP_X_LO
        LDA #>454
        STA ZP_X_HI
        LDA #<306
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA #<STR_BTN_FMPAD
        STA ZP_PTR_LO
        LDA #>STR_BTN_FMPAD
        STA ZP_PTR_HI
        JSR GPU_TEXT_1X

        ; 5. [STOP] (X=550, Y=296, W=66, H=28)
        LDA #<550
        STA ZP_X_LO
        LDA #>550
        STA ZP_X_HI
        LDA #<296
        STA ZP_Y_LO
        LDA #66
        STA ZP_W_LO
        LDA #28
        STA ZP_H_LO
        LDA #$E0                ; Rood
        STA ZP_COL
        JSR GPU_RECT

        LDA #<562
        STA ZP_X_LO
        LDA #>562
        STA ZP_X_HI
        LDA #<306
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA #<STR_BTN_EXIT
        STA ZP_PTR_LO
        LDA #>STR_BTN_EXIT
        STA ZP_PTR_HI
        JSR GPU_TEXT_1X
        RTS

; ============================================================================
; GPU Primitieven (Opcode 2 = RECTANGLE, Opcode 8 = TEXT 8x8 karakter)
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

GPU_TEXT_2X:
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

; ============================================================================
; EXIT_PROGRAM: Zet PCM DAC op rust (128), herstel MODE 0 en keer terug
; ============================================================================
EXIT_PROGRAM:
        LDA #0
        STA IO_PCM_RATE
        LDA #128
        STA IO_PCM_DAC
        JSR ROM_SILENCE
        LDA #1
        STA IO_GPU
        LDA #$E3
        STA IO_GPU
        JMP BSRAM_EXIT

; 87-byte BSRAM Audio & Sector Engine (gekopieerd naar $02A0..$02F6 bij opstarten)
BSRAM_TRAMP_SRC:
        ; --- $02A0: BSRAM_PLAY_PAGE (33 bytes) ---
        LDY #0                  ; +0 (2)
        STY PEAK_AMP            ; +2 (2)
BPP_LP:
        STY IO_RD_LO            ; +4 (3)
        LDA IO_RD_DATA          ; +7 (3)
        STA IO_PCM_DAC          ; +10 (3)
        SEC                     ; +13 (1)
        SBC #128                ; +14 (2)
        BPL BPP_ABS             ; +16 (2)
        EOR #$FF                ; +18 (2)
        CLC                     ; +20 (1)
        ADC #1                  ; +21 (2)
BPP_ABS:
        CMP PEAK_AMP            ; +23 (2)
        BCC BPP_NXT             ; +25 (2)
        STA PEAK_AMP            ; +27 (2)
BPP_NXT:
        INY                     ; +29 (1)
        BNE BPP_LP              ; +30 (2)
        RTS                     ; +32 (1) -> totaal 33 bytes ($02A0..$02C0)

        ; --- $02C1: BSRAM_COPY_SEC (43 bytes) ---
        LDA LOAD_PAGE_PTR       ; +33 (2)
        STA IO_RD_HI            ; +35 (3)
        LDY #0                  ; +38 (2)
BCS_P0:
        STY IO_RD_LO            ; +40 (3)
        LDA SEC_TMP_BUF,Y       ; +43 (3)
        STA IO_RD_DATA          ; +46 (3)
        INY                     ; +49 (1)
        BNE BCS_P0              ; +50 (2)
        INC LOAD_PAGE_PTR       ; +52 (2)
        LDA LOAD_PAGE_PTR       ; +54 (2)
        STA IO_RD_HI            ; +56 (3)
        LDY #0                  ; +59 (2)
BCS_P1:
        STY IO_RD_LO            ; +61 (3)
        LDA SEC_TMP_BUF+$100,Y  ; +64 (3)
        STA IO_RD_DATA          ; +67 (3)
        INY                     ; +70 (1)
        BNE BCS_P1              ; +71 (2)
        INC LOAD_PAGE_PTR       ; +73 (2)
        RTS                     ; +75 (1) -> totaal 43 bytes ($02C1..$02EB)

        ; --- $02EC: BSRAM_EXIT (11 bytes) ---
        LDA #1                  ; +76 (2)
        STA IO_MODE             ; +78 (3)
        LDA #12                 ; +81 (2)
        STA IO_TERM             ; +83 (3)
        RTS                     ; +86 (1) -> totaal 87 bytes ($02A0..$02F6)

; ============================================================================
; Tabellen & Teksten
; ============================================================================
TRK_CACHED:
        DB 0, 0, 0, 0, 0, 0, 0, 0

RATE_BTN_XL:
        DB <304, <382, <460, <538
RATE_BTN_XH:
        DB >304, >382, >460, >538
RATE_LBL_LO:
        DB <STR_R8K, <STR_R11K, <STR_R16K, <STR_R22K
RATE_LBL_HI:
        DB >STR_R8K, >STR_R11K, >STR_R16K, >STR_R22K

STR_R8K:          DB "8 kHz", 0
STR_R11K:         DB "11kHz", 0
STR_R16K:         DB "16kHz", 0
STR_R22K:         DB "22kHz", 0

STR_HEADER:       DB "MINIGPU SD-KAART .WAV & PCM DIGITAL AUDIO STUDIO ($A016 / $A017)", 0
STR_PLAYLIST_HDR: DB "SD-KAART .WAV TRACKS (1-8):", 0
STR_SCOPE_HDR:    DB "OSCILLOSCOOP:", 0
STR_VU_L:         DB "L:", 0
STR_VU_R:         DB "R:", 0
STR_BTN_PLAYING:  DB "|> SPEELT AF", 0
STR_BTN_PAUSED:   DB "|| GEPAUZEERD", 0
STR_BTN_BEGIN:    DB "|<< BEGIN", 0
STR_BTN_LOOP_ON:  DB "LOOP: AAN", 0
STR_BTN_LOOP_OFF: DB "LOOP: UIT", 0
STR_BTN_FMPAD:    DB "+FM SYNTH", 0
STR_BTN_EXIT:     DB "STOP", 0
STR_FOOTER:       DB "MUIS: Klik Track/Tijdbalk/Knop | 1-8:Track | SPATIE:Pauze | S:Hz | Q:Stop", 0

; Standaard WAV Directory (8 entries van exact 32 bytes voor Sector $2000)
; Formaat: "WAV!" (4B) + Titel (15B + 0) + sec_lo, sec_hi, secs, pages, rate, dur + 6x0 = 32B
DEFAULT_WAV_DIR:
        ; Track 0: Sector $2010, 64 sectoren (32KB = 128 pages), Rate 1 (8000 Hz)
        DB "WAV!", "1.TANG NANO STM", 0, $10, $20, 64, 128, 1, 4, 0, 0, 0, 0, 0, 0
        ; Track 1: Sector $2050, 64 sectoren (32KB = 128 pages), Rate 1 (8000 Hz)
        DB "WAV!", "2.FUNK DRUMBEAT", 0, $50, $20, 64, 128, 1, 4, 0, 0, 0, 0, 0, 0
        ; Track 2: Sector $2090, 64 sectoren (32KB = 128 pages), Rate 2 (11025 Hz)
        DB "WAV!", "3.WINDOWS TADA!", 0, $90, $20, 64, 128, 2, 3, 0, 0, 0, 0, 0, 0
        ; Track 3: Sector $20D0, 64 sectoren (32KB = 128 pages), Rate 1 (8000 Hz)
        DB "WAV!", "4.CYBER ACID BS", 0, $D0, $20, 64, 128, 1, 4, 0, 0, 0, 0, 0, 0
        ; Track 4: Sector $2110, 64 sectoren (32KB = 128 pages), Rate 2 (11025 Hz)
        DB "WAV!", "5.STUDIO CHIMES", 0, $10, $21, 64, 128, 2, 3, 0, 0, 0, 0, 0, 0
        ; Track 5: Sector $2150, 64 sectoren (32KB = 128 pages), Rate 1 (8000 Hz)
        DB "WAV!", "6.SPACE RADIO  ", 0, $50, $21, 64, 128, 1, 4, 0, 0, 0, 0, 0, 0
        ; Track 6: Sector $2190, 64 sectoren (32KB = 128 pages), Rate 1 (8000 Hz)
        DB "WAV!", "7.BOERDERIJ WEI", 0, $90, $21, 64, 128, 1, 4, 0, 0, 0, 0, 0, 0
        ; Track 7: Sector $21D0, 64 sectoren (32KB = 128 pages), Rate 1 (8000 Hz)
        DB "WAV!", "8.OCHTENDVOGELS", 0, $D0, $21, 64, 128, 1, 4, 0, 0, 0, 0, 0, 0
