; ============================================================================
; RFTS.asm - Reach for the Stars (1983) - 6502 Galactic 4X Strategy Game
; Geïnspireerd op de klassieker van Roger Keating & Ian Trout (SSG, 1983).
; Geassembleerd op $8000 in SDRAM. Spelstatus op $6600-$67FF (met SD-Save!).
; Bevat 16 Sterrenstelsels, Hyperspace-routes, Kolonisatie, Industrie (IND),
; Planetaire Afweer (DEF), Tech-onderzoek, Vlootbewegingen, Ruimteslagen &
; een actieve Xenon Imperium AI-tegenstander op een 640x360 scherm!
; Starten vanuit Midnight Commander (BRUN MC) of in BASIC met: BRUN RFTS
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_RND          = $A005         ; Hardware LFSR willekeurig getal (0..255)
IO_MODE         = $A006         ; 0 = MODE 1 (640x360 graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- ROM Routines voor Geluid & SD-Kaart Savegame (Sector $03EC) ---
ZP_DST          = $1C
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA

; --- Eigen Zero Page Variabelen ($60..$7F) ---
ZP_PTR_LO       = $60           ; Algemene 16-bit pointer voor strings/streams
ZP_PTR_HI       = $61
ZP_X_LO         = $62           ; 16-bit GPU X
ZP_X_HI         = $63
ZP_Y_LO         = $64           ; 16-bit GPU Y
ZP_Y_HI         = $65
ZP_COLOR        = $66           ; Huidige tekenkleur

CUR_STAR        = $67           ; Geselecteerd sterrenstelsel (0..15)
MOVE_SRC        = $68           ; Bron-stelsel voor vlootverplaatsing ($FF = geen)
MENU_OPEN       = $69           ; 0 = Spel actief, 1 = ESC-Menu open
PREV_JOY        = $6A           ; Vorige joypad-status
STAR_IDX        = $6B           ; Lus-index voor sterren (0..15)
MSG_ID          = $6C           ; Huidig logbericht-ID onderin
TERRAN_CNT      = $6D           ; Aantal stelsels in bezit van speler
XENON_CNT       = $6E           ; Aantal stelsels in bezit van Xenon AI
TMP_VAL         = $6F           ; Tijdelijke rekenwaarde

; --- Spelstatus in SDRAM ($6600..$67FF = 512 bytes voor directe SD-opslag!) ---
SAVE_BASE       = $6600
STAR_OWNER      = $6600         ; 16 bytes: 0=Neutraal, 1=Terran(Jij), 2=Xenon(AI)
STAR_SHIPS      = $6610         ; 16 bytes: Aantal ruimteschepen in baan (0..99)
STAR_IND        = $6620         ; 16 bytes: Industrie-niveau (1..15)
STAR_DEF        = $6630         ; 16 bytes: Planetaire raketbases (0..15)

YEAR_LO         = $6640         ; Huidig jaartal (start 2400)
YEAR_HI         = $6641
RP_LO           = $6642         ; Research & Productie Credits (16-bit)
RP_HI           = $6643
TECH_LVL        = $6644         ; Terran Tech-niveau (1..9)
AI_TECH_LVL     = $6645         ; Xenon AI Tech-niveau (1..9)
GAME_MAGIC      = $6646         ; $5A als spel al gestart is

; ============================================================================
; Start & Initialisatie
; ============================================================================
START:
        JSR ROM_SILENCE
        LDA #0
        STA IO_MODE             ; MODE 1 (volledige 640x360 GUI)
        STA ZP_Y_HI
        STA MENU_OPEN
        LDA #$FF
        STA MOVE_SRC

        LDA GAME_MAGIC
        CMP #$5A
        BEQ WARM_START
        JSR INIT_NEW_GAME

WARM_START:
        LDA IO_JOY
        STA PREV_JOY

MAIN_LOOP:
        JSR COUNT_EMPIRES
        JSR DRAW_SCREEN

WAIT_LOOP:
        JSR DELAY_10MS

        ; Controleer ESC-bit (bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_JOY
        LDA IO_TERM
        LDA MOVE_SRC
        BMI ESC_CHK_MENU
        ; Annuleer actieve vloot-selectie met ESC
        LDA #$FF
        STA MOVE_SRC
        LDA #0
        STA MSG_ID
        JMP MAIN_LOOP

ESC_CHK_MENU:
        LDA MENU_OPEN
        BNE EXIT_TO_BASIC
        LDA #1
        STA MENU_OPEN
        JMP MAIN_LOOP

EXIT_TO_BASIC:
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        STA IO_GPU
        LDA #$E3
        STA IO_GPU
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

CHK_JOY:
        LDA IO_JOY
        STA TMP_VAL
        TAX
        EOR PREV_JOY
        AND TMP_VAL
        STX PREV_JOY
        TAY
        BEQ CHK_KEY

        ; Slik WASD/Spatie/Enter echo weg
        LDA IO_STATUS
        AND #1
        BEQ JOY_DO
        LDA IO_TERM
        CMP #$0D
        BEQ KEY_DO_ENTER
        CMP #$0E
        BEQ TOGGLE_MENU
JOY_DO:
        LDA MENU_OPEN
        BNE CHK_KEY
        TYA
        AND #5                  ; Omhoog of Links -> Vorige ster
        BNE PREV_STAR
        TYA
        AND #10                 ; Omlaag of Rechts -> Volgende ster
        BNE NEXT_STAR
        TYA
        AND #16                 ; Vuur / Spatie -> Vloot actie
        BNE DO_FLEET_ACTION
        BEQ WAIT_LOOP

PREV_STAR:
        DEC CUR_STAR
        BPL GO_MAIN_1
        LDA #15
        STA CUR_STAR
        BNE GO_MAIN_1

NEXT_STAR:
        INC CUR_STAR
        LDA CUR_STAR
        AND #$0F
        STA CUR_STAR
GO_MAIN_1:
        JMP MAIN_LOOP

TOGGLE_MENU:
        LDA MENU_OPEN
        EOR #1
        STA MENU_OPEN
        JMP MAIN_LOOP

KEY_DO_ENTER:
        JMP DO_NEXT_TURN

; ============================================================================
; Toetsenbord-invoer
; ============================================================================
CHK_KEY:
        LDA IO_STATUS
        AND #1
        BEQ WAIT_LOOP
        LDA IO_TERM

        CMP #$0E                ; Alt / F9 -> Open/sluit Menu
        BEQ TOGGLE_MENU

        CMP #'a'
        BCC CK_UPPER
        CMP #'z'+1
        BCS CK_UPPER
        AND #$DF
CK_UPPER:
        LDX MENU_OPEN
        BNE KEY_IN_MENU

        CMP #$09                ; TAB -> Volgende ster
        BEQ NEXT_STAR
        CMP #' '                ; Spatie -> Vloot selecteren / sturen
        BEQ DO_FLEET_ACTION
        CMP #'5'
        BEQ DO_FLEET_ACTION
        CMP #'M'
        BEQ DO_FLEET_ACTION
        CMP #$0D                ; ENTER -> Volgende beurt (Jaar +1)
        BEQ KEY_DO_ENTER
        CMP #'6'
        BEQ KEY_DO_ENTER
        CMP #'E'
        BEQ KEY_DO_ENTER

        CMP #'1'
        BEQ DO_BUILD_SHIP
        CMP #'B'
        BEQ DO_BUILD_SHIP
        CMP #'2'
        BEQ DO_BUILD_IND
        CMP #'I'
        BEQ DO_BUILD_IND
        CMP #'3'
        BEQ DO_BUILD_DEF
        CMP #'D'
        BEQ DO_BUILD_DEF
        CMP #'4'
        BEQ DO_UPGRADE_TECH
        CMP #'T'
        BEQ DO_UPGRADE_TECH
        CMP #'Q'
        BEQ EXIT_TO_BASIC
        JMP WAIT_LOOP

KEY_IN_MENU:
        CMP #'1'
        BEQ MENU_NEW_GAME
        CMP #'N'
        BEQ MENU_NEW_GAME
        CMP #'2'
        BEQ MENU_SAVE_SD
        CMP #'S'
        BEQ MENU_SAVE_SD
        CMP #'3'
        BEQ MENU_LOAD_SD
        CMP #'L'
        BEQ MENU_LOAD_SD
        CMP #'4'
        BEQ TOGGLE_MENU
        CMP #'0'
        BEQ EXIT_TO_BASIC
        CMP #'Q'
        BEQ EXIT_TO_BASIC
        JMP WAIT_LOOP

MENU_NEW_GAME:
        LDA #0
        STA MENU_OPEN
        JSR INIT_NEW_GAME
        JMP MAIN_LOOP

MENU_SAVE_SD:
        JSR SETUP_SD_SAVE
        JSR ROM_WRITE_SEC
        LDA #9
        STA MSG_ID
        JMP MAIN_LOOP

MENU_LOAD_SD:
        JSR SETUP_SD_SAVE
        JSR ROM_READ_SEC
        LDA #10
        STA MSG_ID
        JMP MAIN_LOOP

SETUP_SD_SAVE:
        LDA #0
        STA MENU_OPEN
        STA ZP_DST
        JSR ROM_SD_INIT
        LDA #$EC
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDA #>SAVE_BASE
        STA ZP_DST+1
        RTS

; ============================================================================
; Bouw- & Onderzoeks-orders (Schepen, Industrie, Afweer, Tech)
; ============================================================================
; 1 / B: Bouw Ruimteschip (Kost 15 RP)
DO_BUILD_SHIP:
        LDX CUR_STAR
        LDA STAR_OWNER,X
        CMP #1
        BNE ORD_NOT_YOURS
        LDA STAR_SHIPS,X
        CMP #99
        BCS ORD_MAX
        LDA #15
        JSR SPEND_RP_A
        BCC ORD_NO_RP
        LDX CUR_STAR
        LDA STAR_SHIPS,X
        CLC
        ADC #1
        STA STAR_SHIPS,X
        LDA #1                  ; "RUIMTESCHIP GEBOUWD (+1 VLOOT)!"
        STA MSG_ID
        JMP MAIN_LOOP

; 2 / I: Bouw Planetaire Industrie (Kost 25 RP)
DO_BUILD_IND:
        LDX CUR_STAR
        LDA STAR_OWNER,X
        CMP #1
        BNE ORD_NOT_YOURS
        LDA STAR_IND,X
        CMP #15
        BCS ORD_MAX
        LDA #25
        JSR SPEND_RP_A
        BCC ORD_NO_RP
        LDX CUR_STAR
        LDA STAR_IND,X
        CLC
        ADC #1
        STA STAR_IND,X
        LDA #2                  ; "INDUSTRIE UITGEBREID (+1 IND)!"
        STA MSG_ID
        JMP MAIN_LOOP

; 3 / D: Bouw Planetaire Afweerbasis (Kost 20 RP)
DO_BUILD_DEF:
        LDX CUR_STAR
        LDA STAR_OWNER,X
        CMP #1
        BNE ORD_NOT_YOURS
        LDA STAR_DEF,X
        CMP #15
        BCS ORD_MAX
        LDA #20
        JSR SPEND_RP_A
        BCC ORD_NO_RP
        LDX CUR_STAR
        LDA STAR_DEF,X
        CLC
        ADC #1
        STA STAR_DEF,X
        LDA #3                  ; "RAKETBASIS GEBOUWD (+1 DEF)!"
        STA MSG_ID
        JMP MAIN_LOOP

; 4 / T: Onderzoek Nieuwe Technologie (Kost 50 RP)
DO_UPGRADE_TECH:
        LDA TECH_LVL
        CMP #9
        BCS ORD_MAX
        LDA #50
        JSR SPEND_RP_A
        BCC ORD_NO_RP
        INC TECH_LVL
        LDA #4                  ; "NIEUW TECH-NIVEAU BEREIKT!"
        STA MSG_ID
        JMP MAIN_LOOP

ORD_NOT_YOURS:
        LDA #5                  ; "NIET JOUW STERRENSTELSEL!"
        STA MSG_ID
        JMP MAIN_LOOP
ORD_NO_RP:
        LDA #6                  ; "ONVOLDOENDE CREDITS (RP)!"
        STA MSG_ID
        JMP MAIN_LOOP
ORD_MAX:
        JMP MAIN_LOOP

; Trek A credits af van RP_LO/HI als er genoeg is (Carry=1 bij succes)
SPEND_RP_A:
        STA TMP_VAL
        LDA RP_HI
        BNE SRA_OK
        LDA RP_LO
        CMP TMP_VAL
        BCC SRA_FAIL
SRA_OK:
        SEC
        LDA RP_LO
        SBC TMP_VAL
        STA RP_LO
        LDA RP_HI
        SBC #0
        STA RP_HI
        SEC
        RTS
SRA_FAIL:
        CLC
        RTS

; ============================================================================
; Vloot Beweging, Kolonisatie & Ruimteslagen (5 / M / Spatie)
; ============================================================================
DO_FLEET_ACTION:
        LDA MOVE_SRC
        BPL DFA_EXECUTE_MOVE

        ; Stap 1: Selecteer bron-stelsel (moet van speler zijn én schepen hebben)
        LDX CUR_STAR
        LDA STAR_OWNER,X
        CMP #1
        BNE ORD_NOT_YOURS
        LDA STAR_SHIPS,X
        CMP #2
        BCC DFA_NEED_SHIPS
        STX MOVE_SRC
        LDA #7                  ; "KIES DOELSTELSEL EN DRUK OP SPATIE/5"
        STA MSG_ID
        JMP MAIN_LOOP

DFA_NEED_SHIPS:
        LDA #8                  ; "MINIMAAL 2 SCHEPEN NODIG OM TE ZENDEN!"
        STA MSG_ID
        JMP MAIN_LOOP

DFA_EXECUTE_MOVE:
        CMP CUR_STAR
        BNE DFA_DO_SEND
        ; Zelfde ster gekozen -> annuleer
        LDA #$FF
        STA MOVE_SRC
        LDA #0
        STA MSG_ID
        JMP MAIN_LOOP

DFA_DO_SEND:
        ; Stuur de helft van de schepen (minimaal 1) van MOVE_SRC naar CUR_STAR
        LDX MOVE_SRC
        LDA STAR_SHIPS,X
        LSR A                   ; Helft van de vloot
        BNE DFA_HAS_AMT
        LDA #1
DFA_HAS_AMT:
        STA TMP_VAL             ; Aantal verzonden schepen
        SEC
        LDA STAR_SHIPS,X
        SBC TMP_VAL
        STA STAR_SHIPS,X

        LDA #$FF
        STA MOVE_SRC

        LDX CUR_STAR
        LDA STAR_OWNER,X
        CMP #1
        BEQ DFA_REINFORCE

        ; --- Aanval of Kolonisatie op ster X met TMP_VAL schepen! ---
        LDA TMP_VAL
        CLC
        ADC TECH_LVL
        STA ZP_X_LO             ; Aanvalskracht

        LDA STAR_SHIPS,X
        CLC
        ADC STAR_DEF,X
        CMP ZP_X_LO
        BCS DFA_REPULSED

        ; Overwinning! Stelsel X wordt veroverd / gekoloniseerd door Terran (1)!
        LDA #1
        STA STAR_OWNER,X
        LDA TMP_VAL
        SEC
        SBC STAR_DEF,X
        BCS DFA_SURV_OK
        LDA #1
DFA_SURV_OK:
        BNE DFA_SET_SHP
        LDA #1
DFA_SET_SHP:
        STA STAR_SHIPS,X
        LDA #11                 ; "OVERWINNING! STELSEL GEKOLONISEERD!"
        STA MSG_ID
        JMP MAIN_LOOP

DFA_REPULSED:
        LDA STAR_SHIPS,X
        LSR A
        STA STAR_SHIPS,X
        LDA #12                 ; "AANVAL AFGESLAGEN DOOR VERDEDIGING!"
        STA MSG_ID
        JMP MAIN_LOOP

DFA_REINFORCE:
        LDA STAR_SHIPS,X
        CLC
        ADC TMP_VAL
        CMP #99
        BCC DFA_RF_OK
        LDA #99
DFA_RF_OK:
        STA STAR_SHIPS,X
        LDA #13                 ; "VLOOT AANGEKOMEN BIJ KOLONIE!"
        STA MSG_ID
        JMP MAIN_LOOP

; ============================================================================
; Einde Beurt / Volgend Jaar (6 / E / Enter): Productie & Xenon AI!
; ============================================================================
DO_NEXT_TURN:
        LDA #$FF
        STA MOVE_SRC

        ; 1. Jaartal +1
        INC YEAR_LO
        BNE DNT_PROD
        INC YEAR_HI

DNT_PROD:
        ; 2. Doorloop alle 16 sterrenstelsels voor Terran & Xenon productie
        LDX #0
DNT_LP:
        LDA STAR_OWNER,X
        BEQ DNT_NEXT            ; Neutraal doet niets
        CMP #1
        BNE DNT_XENON_STAR

        ; --- Terran Kolonie: + (IND * 4) RP Credits + 1 gratis schip bij IND >= 4 ---
        LDA STAR_IND,X
        ASL A
        ASL A
        CLC
        ADC RP_LO
        STA RP_LO
        LDA RP_HI
        ADC #0
        STA RP_HI

        LDA STAR_IND,X
        CMP #4
        BCC DNT_NEXT
        LDA STAR_SHIPS,X
        CMP #95
        BCS DNT_NEXT
        CLC
        ADC #1
        STA STAR_SHIPS,X
        JMP DNT_NEXT

DNT_XENON_STAR:
        ; --- Xenon AI Planeet: bouwt elke beurt +2 schepen ---
        LDA STAR_SHIPS,X
        CMP #90
        BCS DNT_AI_EXP
        CLC
        ADC #2
        STA STAR_SHIPS,X

DNT_AI_EXP:
        ; Als Xenon planeet >= 10 schepen heeft, stuur 5 schepen naar buur-ster!
        LDA STAR_SHIPS,X
        CMP #10
        BCC DNT_NEXT
        SEC
        SBC #5
        STA STAR_SHIPS,X

        ; Kies doel-ster (X - 1, richting SOL!)
        TXA
        BEQ DNT_NEXT
        TAY
        DEY
        LDA STAR_OWNER,Y
        CMP #2
        BEQ DNT_AI_REINF

        ; AI valt ster Y aan met 5 schepen
        LDA STAR_SHIPS,Y
        CLC
        ADC STAR_DEF,Y
        CMP #6
        BCS DNT_AI_REPEL
        ; AI verovert ster Y!
        LDA #2
        STA STAR_OWNER,Y
        LDA #4
        STA STAR_SHIPS,Y
        JMP DNT_NEXT

DNT_AI_REPEL:
        LDA STAR_SHIPS,Y
        LSR A
        STA STAR_SHIPS,Y
        JMP DNT_NEXT

DNT_AI_REINF:
        LDA STAR_SHIPS,Y
        CLC
        ADC #5
        STA STAR_SHIPS,Y

DNT_NEXT:
        INX
        CPX #16
        BCC DNT_LP

        LDA #14                 ; "NIEUW JAAR: PRODUCTIE & AI VERWERKT"
        STA MSG_ID
        JMP MAIN_LOOP

; ============================================================================
; Nieuw Spel Initialiseren (16 Sterrenstelsels)
; ============================================================================
INIT_NEW_GAME:
        LDA #$5A
        STA GAME_MAGIC
        LDA #$60                ; Jaar 2400 ($0960)
        STA YEAR_LO
        LDA #$09
        STA YEAR_HI
        LDA #120                ; Start met 120 RP Credits
        STA RP_LO
        LDA #0
        STA RP_HI
        STA CUR_STAR            ; Start op SOL (0)
        STA MSG_ID
        LDA #1
        STA TECH_LVL
        STA AI_TECH_LVL
        LDA #$FF
        STA MOVE_SRC

        LDX #15
ING_LP:
        LDA INIT_OWNER_TBL,X
        STA STAR_OWNER,X
        LDA INIT_SHIPS_TBL,X
        STA STAR_SHIPS,X
        LDA INIT_IND_TBL,X
        STA STAR_IND,X
        LDA INIT_DEF_TBL,X
        STA STAR_DEF,X
        DEX
        BPL ING_LP
        RTS

COUNT_EMPIRES:
        LDA #0
        STA TERRAN_CNT
        STA XENON_CNT
        LDX #15
CE_LP:
        LDA STAR_OWNER,X
        CMP #1
        BNE CE_CHK_X
        INC TERRAN_CNT
        JMP CE_NXT
CE_CHK_X:
        CMP #2
        BNE CE_NXT
        INC XENON_CNT
CE_NXT:
        DEX
        BPL CE_LP

        ; Check overwinning (alle 16 of Xenon = 0)
        LDA XENON_CNT
        BNE CE_RTS
        LDA #15                 ; "GALACTISCHE OVERWINNING! XENON VERSLAGEN!"
        STA MSG_ID
CE_RTS:
        RTS

; ============================================================================
; Volledig Scherm Opbouwen (640x360) via MiniGPU ($A020)
; ============================================================================
DRAW_SCREEN:
        LDX #0
DS_UI_LP:
        LDA UI_STREAM,X
        STA IO_GPU
        INX
        CPX #UI_STREAM_END - UI_STREAM
        BCC DS_UI_LP

        LDX #0
DS_LANES_LP:
        LDA LANES_STREAM,X
        STA IO_GPU
        INX
        CPX #LANES_STREAM_END - LANES_STREAM
        BCC DS_LANES_LP

        ; Top Titelbalk
        LDA #14
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #4
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_COLOR
        LDA #<STR_TOP_BAR
        LDY #>STR_TOP_BAR
        JSR DRAW_STR_AY

        ; Teken actieve Vloot-Aanvalslijn als MOVE_SRC geselecteerd is!
        LDX MOVE_SRC
        BMI DS_STAR_INIT
        LDY CUR_STAR
        LDA #3                  ; LINE cmd 3
        STA IO_GPU
        LDA STAR_X_LO,X
        STA IO_GPU
        LDA STAR_X_HI,X
        STA IO_GPU
        LDA STAR_Y_LO,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA STAR_X_LO,Y
        STA IO_GPU
        LDA STAR_X_HI,Y
        STA IO_GPU
        LDA STAR_Y_LO,Y
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$1C                ; Felgroene vloot-route!
        STA IO_GPU

DS_STAR_INIT:
        ; --- 1. Teken alle 16 Sterrenstelsels op de Sterrenkaart ---
        LDA #0
        STA STAR_IDX
DS_STAR_LP:
        LDX STAR_IDX

        ; Kies eigenaar-kleur voor halo-cirkel: 0=Geel($FC), 1=Cyaan($1F), 2=Rood($E0)
        LDY STAR_OWNER,X
        LDA OWNER_COL_TBL,Y
        STA ZP_COLOR

        ; Als dit het geselecteerde stelsel is: teken witte selectie-ring (r=11)
        CPX CUR_STAR
        BNE DS_CHK_SRC
        LDA #4                  ; CIRCLE
        ldy #11
        LDA #$FF
        JSR DRAW_STAR_RING

DS_CHK_SRC:
        CPX MOVE_SRC
        BNE DS_DRAW_CORE
        LDA #4                  ; CIRCLE voor vloot-bron (Groen $1C, r=13)
        LDY #13
        LDA #$1C
        JSR DRAW_STAR_RING

DS_DRAW_CORE:
        ; Teken eigenaar-ring (r=8) in eigenaar-kleur
        LDX STAR_IDX
        LDY STAR_OWNER,X
        LDA OWNER_COL_TBL,Y
        LDY #8
        JSR DRAW_STAR_RING

        ; Teken gevulde ster-kern (DISK cmd 5, r=4)
        LDX STAR_IDX
        LDA #5
        STA IO_GPU
        LDA STAR_X_LO,X
        STA IO_GPU
        LDA STAR_X_HI,X
        STA IO_GPU
        LDA STAR_Y_LO,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #4
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA STAR_CORE_COL,X
        STA IO_GPU

        ; Teken Ster-naam onder de ster (X - 16, Y + 11)
        LDX STAR_IDX
        SEC
        LDA STAR_X_LO,X
        SBC #16
        STA ZP_X_LO
        LDA STAR_X_HI,X
        SBC #0
        STA ZP_X_HI
        CLC
        LDA STAR_Y_LO,X
        ADC #11
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI

        LDY STAR_OWNER,X
        LDA OWNER_COL_TBL,Y
        STA ZP_COLOR
        LDA STAR_NAME_LO,X
        LDY STAR_NAME_HI,X
        JSR DRAW_STR_AY

        ; Teken vloot-aantal rechtsboven de ster als STAR_SHIPS > 0
        LDX STAR_IDX
        LDA STAR_SHIPS,X
        BEQ DS_STAR_NEXT
        CLC
        LDA STAR_X_LO,X
        ADC #10
        STA ZP_X_LO
        LDA STAR_X_HI,X
        ADC #0
        STA ZP_X_HI
        SEC
        LDA STAR_Y_LO,X
        SBC #10
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COLOR
        LDA STAR_SHIPS,X
        JSR DRAW_DEC2

DS_STAR_NEXT:
        INC STAR_IDX
        LDA STAR_IDX
        CMP #16
        BCS DS_RIGHT_PANEL
        JMP DS_STAR_LP

; --- Hulproutine: Teken CIRCLE (cmd 4) rond STAR_IDX met straal Y en kleur A ---
DRAW_STAR_RING:
        PHA
        LDA #4
        STA IO_GPU
        LDA STAR_X_LO,X
        STA IO_GPU
        LDA STAR_X_HI,X
        STA IO_GPU
        LDA STAR_Y_LO,X
        STA IO_GPU
        LDA #0
        STA IO_GPU
        TYA
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        PLA
        STA IO_GPU
        RTS

; ============================================================================
; 2. Teken Rechter Commando- & Sterrenstelsel-Paneel (X = 422..630)
; ============================================================================
DS_RIGHT_PANEL:
        ; Kop: KEIZERRIJK STATUS
        LDY #24
        LDA #$FC
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_EMP
        LDY #>STR_PNL_EMP
        JSR DRAW_STR_AY

        ; Jaartal
        LDY #40
        LDA #$FF
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_YR
        LDY #>STR_PNL_YR
        JSR DRAW_STR_AY
        LDA YEAR_HI
        JSR DRAW_HEX8
        LDA YEAR_LO
        JSR DRAW_HEX8

        ; Credits (RP)
        LDY #54
        LDA #$1C
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_RP
        LDY #>STR_PNL_RP
        JSR DRAW_STR_AY
        LDA RP_HI
        JSR DRAW_HEX8
        LDA RP_LO
        JSR DRAW_HEX8

        ; Tech & Werelden
        LDY #68
        LDA #$1F
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_TECH
        LDY #>STR_PNL_TECH
        JSR DRAW_STR_AY
        LDA TECH_LVL
        JSR DRAW_DEC2

        LDY #82
        LDA #$FF
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_WLD
        LDY #>STR_PNL_WLD
        JSR DRAW_STR_AY
        LDA TERRAN_CNT
        JSR DRAW_DEC2
        LDA #'/'
        JSR DRAW_CHAR_ADV
        LDA #16
        JSR DRAW_DEC2

        ; --- Geselecteerd Sterrenstelsel Info ---
        LDY #108
        LDA #$FC
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_SYS
        LDY #>STR_PNL_SYS
        JSR DRAW_STR_AY
        LDX CUR_STAR
        LDA STAR_NAME_LO,X
        LDY STAR_NAME_HI,X
        JSR DRAW_STR_AY

        ; Eigenaar
        LDX CUR_STAR
        LDY STAR_OWNER,X
        LDA OWNER_COL_TBL,Y
        LDY #124
        JSR SET_PANEL_XY_COL
        LDX CUR_STAR
        LDY STAR_OWNER,X
        LDA OWNER_STR_LO,Y
        PHA
        LDA OWNER_STR_HI,Y
        TAY
        PLA
        JSR DRAW_STR_AY

        ; Schepen in baan
        LDY #140
        LDA #$FF
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_SHP
        LDY #>STR_PNL_SHP
        JSR DRAW_STR_AY
        LDX CUR_STAR
        LDA STAR_SHIPS,X
        JSR DRAW_DEC2

        ; Industrie (IND)
        LDY #154
        LDA #$1C
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_IND
        LDY #>STR_PNL_IND
        JSR DRAW_STR_AY
        LDX CUR_STAR
        LDA STAR_IND,X
        JSR DRAW_DEC2

        ; Planetaire Afweer (DEF)
        LDY #168
        LDA #$1F
        JSR SET_PANEL_XY_COL
        LDA #<STR_PNL_DEF
        LDY #>STR_PNL_DEF
        JSR DRAW_STR_AY
        LDX CUR_STAR
        LDA STAR_DEF,X
        JSR DRAW_DEC2

        ; --- Bouw- & Vloot-commando's op het Rechter Paneel (7 regels via lus) ---
        LDA #0
        STA STAR_IDX
DS_CMD_LP:
        LDX STAR_IDX
        LDY CMD_Y_TBL,X
        LDA CMD_COL_TBL,X
        JSR SET_PANEL_XY_COL
        LDX STAR_IDX
        LDA CMD_STR_LO,X
        LDY CMD_STR_HI,X
        JSR DRAW_STR_AY
        INC STAR_IDX
        LDA STAR_IDX
        CMP #7
        BCC DS_CMD_LP

        ; --- Onderste Galactische Logbalk (Y = 322) & Sneltoetsbalk (Y = 347) ---
        LDA #14
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$42                ; Y = 322 ($0142)
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$FC
        STA ZP_COLOR
        LDX MSG_ID
        LDA MSG_TBL_LO,X
        LDY MSG_TBL_HI,X
        JSR DRAW_STR_AY

        LDA #10
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #$5B                ; Y = 347 ($015B)
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_COLOR
        LDA #<STR_BOT_BAR
        LDY #>STR_BOT_BAR
        JSR DRAW_STR_AY

        LDA MENU_OPEN
        BEQ DS_RTS
        JMP DRAW_ESC_MENU
DS_RTS:
        RTS

SET_PANEL_XY_COL:
        STA ZP_COLOR
        LDA #$A6
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        STY ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        RTS

; ============================================================================
; ESC / Alt Menu (Nieuw Spel, Opslaan op SD, Laden van SD, Afsluiten)
; ============================================================================
DRAW_ESC_MENU:
        LDX #0
DEM_LP:
        LDA MENU_STREAM,X
        STA IO_GPU
        INX
        CPX #MENU_STREAM_END - MENU_STREAM
        BCC DEM_LP

        LDA #0
        STA STAR_IDX
DEM_TXT_LP:
        LDX STAR_IDX
        LDA #176
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA MENU_Y_TBL,X
        STA ZP_Y_LO
        LDA #$FF
        CPX #0
        BEQ DEM_YEL
        CPX #5
        BNE DEM_COL_OK
DEM_YEL:
        LDA #$FC
DEM_COL_OK:
        STA ZP_COLOR
        LDA MENU_STR_LO,X
        LDY MENU_STR_HI,X
        JSR DRAW_STR_AY
        INC STAR_IDX
        LDA STAR_IDX
        CMP #6
        BCC DEM_TXT_LP
        RTS

; ============================================================================
; Tekst, Getal & Timer Hulproutines
; ============================================================================
DRAW_DEC2:
        LDY #'0'
DD2_LP:
        CMP #10
        BCC DD2_OUT
        SBC #10
        INY
        BNE DD2_LP
DD2_OUT:
        PHA
        TYA
        JSR DRAW_CHAR_ADV
        PLA
        CLC
        ADC #'0'
        JMP DRAW_CHAR_ADV

DRAW_STR_AY:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DRAW_STR:
        LDY #0
        LDA (ZP_PTR_LO),Y
        INC ZP_PTR_LO
        BNE DST_CHK
        INC ZP_PTR_HI
DST_CHK:
        CMP #0
        BEQ DST_RTS
        JSR DRAW_CHAR_ADV
        JMP DRAW_STR
DST_RTS:
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
        LDA ZP_COLOR
        STA IO_GPU
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCA_RTS
        INC ZP_X_HI
DCA_RTS:
        RTS

DRAW_HEX8:
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
        CLC
        ADC #('A' - 10)
        JMP DRAW_CHAR_ADV
DHN_DIG:
        CLC
        ADC #'0'
        JMP DRAW_CHAR_ADV

DELAY_10MS:
        LDA IO_TIMER
D10_WAIT:
        CMP IO_TIMER
        BEQ D10_WAIT
        RTS

; ============================================================================
; Sterrenstelsel Coördinaten, Startwaarden & GPU Streams
; ============================================================================
OWNER_COL_TBL:
        .BYTE $FC, $1F, $E0     ; 0=Neutraal(Geel), 1=Terran(Cyaan), 2=Xenon(Rood)

; 16 Sterrenstelsels (X_LO, X_HI, Y_LO) op de sterrenkaart (X = 36..380, Y = 42..282)
STAR_X_LO:
        .BYTE 48,  112, 64,  148, 88,  188, 160, 236
        .BYTE 116, 224, <280, <260, <320, <296, <356, <368
STAR_X_HI:
        .BYTE 0,   0,   0,   0,   0,   0,   0,   0
        .BYTE 0,   0,   1,   1,   1,   1,   1,   >368
; Let op: 280=$0118, 260=$0104, 320=$0140, 296=$0128, 356=$0164, 368=$0170!
STAR_Y_LO:
        .BYTE 60,  46,  124, 96,  196, 152, 240, 82
        .BYTE 276, 208, 56,  144, 112, 236, 184, 272

STAR_CORE_COL:
        .BYTE $FC, $FF, $1F, $1F, $E0, $FC, $FF, $1F
        .BYTE $E0, $FC, $1F, $F4, $FF, $FC, $1F, $E0

INIT_OWNER_TBL:
        .BYTE 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2
INIT_SHIPS_TBL:
        .BYTE 12, 2, 3, 3, 4, 4, 3, 5, 4, 5, 5, 6, 6, 5, 7, 14
INIT_IND_TBL:
        .BYTE 6,  2, 3, 4, 3, 4, 2, 5, 3, 4, 4, 5, 4, 3, 5, 7
INIT_DEF_TBL:
        .BYTE 3,  1, 1, 2, 1, 2, 1, 2, 2, 2, 2, 3, 2, 2, 3, 4

STAR_NAME_LO:
        .BYTE <S_N0, <S_N1, <S_N2, <S_N3, <S_N4, <S_N5, <S_N6, <S_N7
        .BYTE <S_N8, <S_N9, <S_N10, <S_N11, <S_N12, <S_N13, <S_N14, <S_N15
STAR_NAME_HI:
        .BYTE >S_N0, >S_N1, >S_N2, >S_N3, >S_N4, >S_N5, >S_N6, >S_N7
        .BYTE >S_N8, >S_N9, >S_N10, >S_N11, >S_N12, >S_N13, >S_N14, >S_N15

OWNER_STR_LO:
        .BYTE <STR_OWN_0, <STR_OWN_1, <STR_OWN_2
OWNER_STR_HI:
        .BYTE >STR_OWN_0, >STR_OWN_1, >STR_OWN_2

CMD_Y_TBL:
        .BYTE 196, 212, 226, 240, 254, 270, 286
CMD_COL_TBL:
        .BYTE $FC, $FF, $FF, $FF, $FF, $1C, $FC
CMD_STR_LO:
        .BYTE <STR_CMD_HDR, <STR_CMD_1, <STR_CMD_2, <STR_CMD_3, <STR_CMD_4, <STR_CMD_5, <STR_CMD_6
CMD_STR_HI:
        .BYTE >STR_CMD_HDR, >STR_CMD_1, >STR_CMD_2, >STR_CMD_3, >STR_CMD_4, >STR_CMD_5, >STR_CMD_6

MENU_Y_TBL:
        .BYTE 108, 132, 150, 168, 186, 208
MENU_STR_LO:
        .BYTE <STR_M_HDR, <STR_M_1, <STR_M_2, <STR_M_3, <STR_M_4, <STR_M_0
MENU_STR_HI:
        .BYTE >STR_M_HDR, >STR_M_1, >STR_M_2, >STR_M_3, >STR_M_4, >STR_M_0

MSG_TBL_LO:
        .BYTE <STR_MSG_0, <STR_MSG_1, <STR_MSG_2, <STR_MSG_3
        .BYTE <STR_MSG_4, <STR_MSG_5, <STR_MSG_6, <STR_MSG_7
        .BYTE <STR_MSG_8, <STR_MSG_9, <STR_MSG_10, <STR_MSG_11
        .BYTE <STR_MSG_12, <STR_MSG_13, <STR_MSG_14, <STR_MSG_15
MSG_TBL_HI:
        .BYTE >STR_MSG_0, >STR_MSG_1, >STR_MSG_2, >STR_MSG_3
        .BYTE >STR_MSG_4, >STR_MSG_5, >STR_MSG_6, >STR_MSG_7
        .BYTE >STR_MSG_8, >STR_MSG_9, >STR_MSG_10, >STR_MSG_11
        .BYTE >STR_MSG_12, >STR_MSG_13, >STR_MSG_14, >STR_MSG_15

UI_STREAM:
        .BYTE 12, 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 0
        .BYTE 1, $01

        ; Top Titelbalk (0,0, 640x15, $03)
        .BYTE 2, 0,0, 0,0, $80,$02, 15,0, $03

        ; Linker Sterrenkaart Venster (6,18, 404x293, Zwart $00) + Cyaan rand
        .BYTE 2, 6,0, 18,0, $94,$01, $25,$01, $00
        .BYTE 3, 6,0, 18,0, $9A,$01, 18,0, $1F
        .BYTE 3, 6,0, $37,$01, $9A,$01, $37,$01, $1F
        .BYTE 3, 6,0, 18,0, 6,0, $37,$01, $1F
        .BYTE 3, $9A,$01, 18,0, $9A,$01, $37,$01, $1F

        ; Rechter Commando-Paneel (414,18, 220x293, Donkerblauw $02) + Cyaan rand
        .BYTE 2, $9E,$01, 18,0, 220,0, $25,$01, $02
        .BYTE 3, $9E,$01, 18,0, $7A,$02, 18,0, $1F
        .BYTE 3, $9E,$01, 98,0, $7A,$02, 98,0, $1F
        .BYTE 3, $9E,$01, 186,0, $7A,$02, 186,0, $1F
        .BYTE 3, $9E,$01, $37,$01, $7A,$02, $37,$01, $1F

        ; Galactische Logbalk op Y=315 ($013B), hoogte 23
        .BYTE 2, 6,0, $3B,$01, $74,$02, 23,0, $02
        .BYTE 3, 6,0, $3B,$01, $7A,$02, $3B,$01, $1F
        .BYTE 3, 6,0, $52,$01, $7A,$02, $52,$01, $1F

        ; Onderste Sneltoetsbalk op Y=342 ($0156), hoogte 18 (tot Y=360!)
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $03
UI_STREAM_END:

LANES_STREAM:
        ; Hyperspace Jump Lanes (Donkerblauw $03) tussen sterrenstelsels
        .BYTE 3, 48,0,  60,0,  112,0, 46,0,  $03
        .BYTE 3, 48,0,  60,0,  64,0,  124,0, $03
        .BYTE 3, 112,0, 46,0,  148,0, 96,0,  $03
        .BYTE 3, 64,0,  124,0, 148,0, 96,0,  $03
        .BYTE 3, 64,0,  124,0, 88,0,  196,0, $03
        .BYTE 3, 148,0, 96,0,  188,0, 152,0, $03
        .BYTE 3, 148,0, 96,0,  236,0, 82,0,  $03
        .BYTE 3, 88,0,  196,0, 160,0, 240,0, $03
        .BYTE 3, 188,0, 152,0, 224,0, 208,0, $03
        .BYTE 3, 236,0, 82,0,  $18,1, 56,0,  $03
        .BYTE 3, 236,0, 82,0,  $04,1, 144,0, $03
        .BYTE 3, $18,1, 56,0,  $40,1, 112,0, $03
        .BYTE 3, $04,1, 144,0, $40,1, 112,0, $03
        .BYTE 3, 224,0, 208,0, $28,1, 236,0, $03
        .BYTE 3, $40,1, 112,0, $64,1, 184,0, $03
        .BYTE 3, $28,1, 236,0, $70,1, 272,0, $03
        .BYTE 3, $64,1, 184,0, $70,1, 272,0, $03
LANES_STREAM_END:

MENU_STREAM:
        .BYTE 2, 160,0, 96,0, $40,$01, 134,0, $1F
        .BYTE 2, 162,0, 98,0, $3C,$01, 130,0, $02
MENU_STREAM_END:

; ============================================================================
; Tekst-strings
; ============================================================================
STR_TOP_BAR:
        .ASCIIZ "REACH FOR THE STARS (1983) - 6502 GALACTIC 4X EDITION"
STR_BOT_BAR:
        .ASCIIZ "PIJL/TAB:Ster 1:Schip 2:Ind 3:Def 4:Tech 5/SPC:Vloot 6/ENT:Beurt"

S_N0:   .ASCIIZ "SOL"
S_N1:   .ASCIIZ "CENTAURI"
S_N2:   .ASCIIZ "SIRIUS"
S_N3:   .ASCIIZ "VEGA"
S_N4:   .ASCIIZ "RIGEL"
S_N5:   .ASCIIZ "ALTAIR"
S_N6:   .ASCIIZ "PROCYON"
S_N7:   .ASCIIZ "DENEB"
S_N8:   .ASCIIZ "ANTARES"
S_N9:   .ASCIIZ "POLARIS"
S_N10:  .ASCIIZ "ORION"
S_N11:  .ASCIIZ "ARCTURUS"
S_N12:  .ASCIIZ "SPICA"
S_N13:  .ASCIIZ "CAPELLA"
S_N14:  .ASCIIZ "REGULUS"
S_N15:  .ASCIIZ "XENOS"

STR_PNL_EMP:    .ASCIIZ "== TERRAN IMPERIUM =="
STR_PNL_YR:     .ASCIIZ "JAAR (HEX): $"
STR_PNL_RP:     .ASCIIZ "CREDITS   : $"
STR_PNL_TECH:   .ASCIIZ "TECH LVL  : "
STR_PNL_WLD:    .ASCIIZ "STELSELS  : "

STR_PNL_SYS:    .ASCIIZ "STELSEL: "
STR_OWN_0:      .ASCIIZ "STATUS : NEUTRAAL"
STR_OWN_1:      .ASCIIZ "STATUS : TERRAN (JIJ)"
STR_OWN_2:      .ASCIIZ "STATUS : XENON VIJAND"
STR_PNL_SHP:    .ASCIIZ "SCHEPEN (VLOOT): "
STR_PNL_IND:    .ASCIIZ "INDUSTRIE (IND): "
STR_PNL_DEF:    .ASCIIZ "AFWEER    (DEF): "

STR_CMD_HDR:    .ASCIIZ "== ORDERS & BOUW =="
STR_CMD_1:      .ASCIIZ "1/B: Bouw Schip (15)"
STR_CMD_2:      .ASCIIZ "2/I: Industrie  (25)"
STR_CMD_3:      .ASCIIZ "3/D: Afweer     (20)"
STR_CMD_4:      .ASCIIZ "4/T: Tech Lvl   (50)"
STR_CMD_5:      .ASCIIZ "5/SPC: Stuur Vloot"
STR_CMD_6:      .ASCIIZ "6/ENT: Volgend Jaar"

STR_M_HDR:      .ASCIIZ "== REACH FOR THE STARS MENU =="
STR_M_1:        .ASCIIZ "1 / N : Nieuw Melkwegstelsel"
STR_M_2:        .ASCIIZ "2 / S : Spel Opslaan op SD"
STR_M_3:        .ASCIIZ "3 / L : Spel Laden van SD"
STR_M_4:        .ASCIIZ "4     : Terug naar Sterrenkaart"
STR_M_0:        .ASCIIZ "0/ESC : Afsluiten naar BASIC"

STR_MSG_0:      .ASCIIZ "Welkom Admiraal! Verover de Melkweg vanaf SOL."
STR_MSG_1:      .ASCIIZ "Scheepswerf: Nieuw sterrenschip gebouwd (+1)!"
STR_MSG_2:      .ASCIIZ "Kolonie: Planetaire industrie uitgebreid (+1)!"
STR_MSG_3:      .ASCIIZ "Defensie: Planetaire raketbasis gebouwd (+1)!"
STR_MSG_4:      .ASCIIZ "Wetenschap: Nieuw Tech-niveau bereikt!"
STR_MSG_5:      .ASCIIZ "Bevel geweigerd: Stelsel niet in jouw bezit!"
STR_MSG_6:      .ASCIIZ "Onvoldoende Credits! Druk op 6/ENTER voor beurt."
STR_MSG_7:      .ASCIIZ "VLOOT KLAAR: Kies doel-ster en druk op SPATIE/5!"
STR_MSG_8:      .ASCIIZ "Vloot te klein: Minimaal 2 schepen nodig!"
STR_MSG_9:      .ASCIIZ "SD-KAART: Campagne opgeslagen!"
STR_MSG_10:     .ASCIIZ "SD-KAART: Campagne geladen!"
STR_MSG_11:     .ASCIIZ "OVERWINNING! Stelsel veroverd door onze vloot!"
STR_MSG_12:     .ASCIIZ "SLAG VERLOREN! Vloot afgeslagen door afweer!"
STR_MSG_13:     .ASCIIZ "Versterking: Vloot aangekomen bij kolonie!"
STR_MSG_14:     .ASCIIZ "Nieuw Jaar: Inkomsten & Scheepsbouw verwerkt!"
STR_MSG_15:     .ASCIIZ "TOTALE OVERWINNING! Xenon Imperium verslagen!"
