; ============================================================================
; MUIS.asm - MiniGPU Hardware Sprite Muis-Test, Doelwit-Game & Teken-Studio
; Geassembleerd op $8000 (past in 1 SD-slot naast Midnight Commander op $9000)
; Besturing:
;   Alt + Pijltjes (Omhoog/Omlaag/Links/Rechts) = Beweeg Hardware Muispijl
;   Alt + Shift + Pijltjes                      = Turbo-snelheid
;   Alt + Spatie of Alt + Enter (of Alt + Z)    = Linkermuisknop (Klik / Teken)
;   Alt + X of Alt + Ctrl                       = Rechtermuisknop (Gum op canvas)
;   Toets 1..8 = Kies kleur | C = Wis canvas | B = 720p Boerderij/Space | Q/ESC = Stop
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
IO_GPU          = $A020

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
CUR_MY_HI       = $53
CUR_MST         = $54
PREV_MX_LO      = $55
PREV_MX_HI      = $56
PREV_MY_LO      = $57
PREV_MY_HI      = $58
PREV_MST        = $59

SEL_COLOR_IDX   = $5A
BRUSH_SIZE      = $5B
BG_TRANSPARENT  = $5C
STAMP_MODE      = $5D
SCORE_LO        = $5E
SCORE_HI        = $5F
TGT_X_LO        = $60
TGT_X_HI        = $61
TGT_Y_LO        = $62
SND_TIMER       = $63
TEMP_IDX        = $64
DEC_HUND        = $65
DEC_TENS        = $66

START:
        ; Verberg tekst-terminal en zet 720p Boerderij klaar voor transparante modus
        LDA #3
        STA IO_MODE
        LDA #2
        STA IO_MODE

        ; Teken rechtstreeks naar het zichtbare scherm (TARGET 1)
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU

        ; Zet Hardware Muispijl AAN in het midden (320, 180)
        LDA #<320
        STA IO_MOUSE_XL
        LDA #>320
        STA IO_MOUSE_XH
        LDA #180
        STA IO_MOUSE_YL
        LDA #0
        STA IO_MOUSE_ST

        ; Standaard instellingen
        LDA #1                  ; Geel ($FC) als startkleur
        STA SEL_COLOR_IDX
        LDA #4                  ; 4x4 penseel
        STA BRUSH_SIZE
        LDA #0                  ; Donkerblauw canvas (0) of 720p Boerderij (1)
        STA BG_TRANSPARENT
        STA STAMP_MODE
        STA SCORE_LO
        STA SCORE_HI
        STA SND_TIMER

        ; Geluidskaart op Piano/Synth met Auto-ADSR
        LDA #0
        STA IO_SYNTH_INST
        LDA #7
        STA IO_SYNTH_FX

        ; Kies eerste doelwit-positie en teken volledige UI
        JSR SPAWN_TARGET_POS
        JSR DRAW_FULL_UI
        JSR FORCE_STATUS_UPDATE

MAIN_LOOP:
        ; Wacht 10ms (100 Hz)
        LDA #1
        STA IO_DELAY

        ; Demp kort geluid na afloop van SND_TIMER
        LDA SND_TIMER
        BEQ ML_READ_MOUSE
        DEC SND_TIMER
        BNE ML_READ_MOUSE
        JSR SILENCE_CH0

ML_READ_MOUSE:
        LDA IO_MOUSE_XL
        STA CUR_MX_LO
        LDA IO_MOUSE_XH
        AND #$03
        STA CUR_MX_HI
        LDA IO_MOUSE_YL
        STA CUR_MY_LO
        LDA IO_MOUSE_ST
        STA CUR_MST
        AND #$01
        STA CUR_MY_HI

        ; Controleer of X, Y of knopstatus veranderd is voor de onderste statusbalk
        LDA CUR_MX_LO
        CMP PREV_MX_LO
        BNE ML_UPD_HUD
        LDA CUR_MX_HI
        CMP PREV_MX_HI
        BNE ML_UPD_HUD
        LDA CUR_MY_LO
        CMP PREV_MY_LO
        BNE ML_UPD_HUD
        LDA CUR_MY_HI
        CMP PREV_MY_HI
        BNE ML_UPD_HUD
        LDA CUR_MST
        AND #$06
        STA TEMP_IDX
        LDA PREV_MST
        AND #$06
        CMP TEMP_IDX
        BEQ ML_CHK_CLICK
ML_UPD_HUD:
        JSR DRAW_STATUS_VALUES

ML_CHK_CLICK:
        ; Is er een nieuwe linker-klik (rising edge op bit 1 of klik-latch bit 3)?
        LDA CUR_MST
        AND #$08                ; Klik-latch bit 3
        BNE ML_GOT_EDGE_CLICK
        LDA CUR_MST
        AND #$02
        BEQ ML_CHK_DRAG
        LDA PREV_MST
        AND #$02
        BNE ML_CHK_DRAG

ML_GOT_EDGE_CLICK:
        JSR HANDLE_LEFT_CLICK
        JMP ML_SAVE_PREV

ML_CHK_DRAG:
        ; Als linkermuisknop ingedrukt gehouden wordt (bit 1) in het canvas -> tekenen!
        LDA CUR_MST
        AND #$02
        BEQ ML_CHK_RIGHT
        JSR HANDLE_CANVAS_PAINT
        JMP ML_SAVE_PREV

ML_CHK_RIGHT:
        ; Als rechtermuisknop ingedrukt is (bit 2: Alt+X / Alt+Ctrl) -> gummen!
        LDA CUR_MST
        AND #$04
        BEQ ML_SAVE_PREV
        JSR HANDLE_CANVAS_ERASE

ML_SAVE_PREV:
        LDA CUR_MX_LO
        STA PREV_MX_LO
        LDA CUR_MX_HI
        STA PREV_MX_HI
        LDA CUR_MY_LO
        STA PREV_MY_LO
        LDA CUR_MY_HI
        STA PREV_MY_HI
        LDA CUR_MST
        STA PREV_MST

        ; Controleer toetsenbord sneltoetsen
        LDA IO_STATUS
        BPL ML_CHK_KEY_RDY
        LDA IO_TERM
        JMP EXIT_TO_BASIC
ML_CHK_KEY_RDY:
        AND #$01
        BEQ MAIN_LOOP
        LDA IO_TERM
        CMP #$1B                ; ESC
        BEQ GO_EXIT
        CMP #'q'
        BEQ GO_EXIT
        CMP #'Q'
        BEQ GO_EXIT
        CMP #'c'
        BEQ KEY_CLEAR
        CMP #'C'
        BEQ KEY_CLEAR
        CMP #'b'
        BEQ KEY_BG
        CMP #'B'
        BEQ KEY_BG
        CMP #'d'
        BEQ KEY_SIZE
        CMP #'D'
        BEQ KEY_SIZE
        CMP #'s'
        BEQ KEY_STAMP
        CMP #'S'
        BEQ KEY_STAMP
        CMP #'1'
        BCC GO_MAIN_LOOP
        CMP #'9'
        BCS GO_MAIN_LOOP
        SEC
        SBC #'1'
        STA SEL_COLOR_IDX
        JSR PLAY_CLICK_BEEP
        JSR DRAW_TOOLBAR
        JSR DRAW_STATUS_VALUES
GO_MAIN_LOOP:
        JMP MAIN_LOOP

GO_EXIT:
        JMP EXIT_TO_BASIC

KEY_CLEAR:
        JSR CLEAR_CANVAS_AND_TARGET
        JMP MAIN_LOOP

KEY_BG:
        JSR TOGGLE_BG_MODE
        JMP MAIN_LOOP

KEY_SIZE:
        JSR CYCLE_BRUSH_SIZE
        JMP MAIN_LOOP

KEY_STAMP:
        LDA STAMP_MODE
        EOR #1
        STA STAMP_MODE
        JSR PLAY_CLICK_BEEP
        JSR DRAW_TOOLBAR
        JMP MAIN_LOOP

; ============================================================================
; Afhandeling van een Linker Muisklik (Knoppenbalk, Doelwit of Stempel/Teken)
; ============================================================================
HANDLE_LEFT_CLICK:
        ; Zit de muis in de knoppenbalk (Y = 24..53, dus MY_HI == 0 en MY_LO < 54)?
        LDA CUR_MY_HI
        BNE HLC_IN_CANVAS
        LDA CUR_MY_LO
        CMP #24
        BCC HLC_DONE
        CMP #54
        BCS HLC_IN_CANVAS

        ; Muis klikt in de knoppenbalk!
        ; Kleurknoppen 0..7: X = 8..325 (elke knop 40px breed)
        LDA CUR_MX_HI
        BNE HLC_HI_BTNS
        LDA CUR_MX_LO
        CMP #8
        BCC HLC_DONE
        SEC
        SBC #8
        LSR A
        LSR A
        LSR A                   ; / 8
        ; Deel door 5 (want 40 = 8 * 5): zoek in tabel
        LDX #0
HLC_COL_LP:
        CMP #5
        BCC HLC_SET_COL
        SEC
        SBC #5
        INX
        CPX #7
        BCC HLC_COL_LP
HLC_SET_COL:
        STX SEL_COLOR_IDX
        JSR PLAY_CLICK_BEEP
        JSR DRAW_TOOLBAR
        JSR DRAW_STATUS_VALUES
HLC_DONE:
        RTS

HLC_HI_BTNS:
        ; X >= 256:
        ; Kleur 6 (Groen): X = 248..285 (MX_LO < 30)
        ; Kleur 7 (Blauw): X = 288..325 (MX_LO = 32..69)
        ; Knop [DIKTE]:    X = 334..405 (MX_LO = 78..149)
        ; Knop [STEMPEL]:  X = 410..481 (MX_LO = 154..225)
        ; Knop [720P BG]:  X = 486..557 (MX_LO >= 230 of MX_HI == 2, MX_LO < 46)
        ; Knop [WIS ALL]:  X = 562..631 (MX_HI == 2, MX_LO >= 50)
        LDA CUR_MX_HI
        CMP #2
        BCS HLC_HI2_BTNS

        ; MX_HI == 1 (X = 256..511)
        LDA CUR_MX_LO
        CMP #30
        BCC HLC_COL6
        CMP #72
        BCC HLC_COL7
        CMP #150
        BCC HLC_BTN_SIZE
        CMP #228
        BCC HLC_BTN_STAMP
        JMP TOGGLE_BG_MODE

HLC_COL6:
        LDA #6
        STA SEL_COLOR_IDX
        JSR PLAY_CLICK_BEEP
        JSR DRAW_TOOLBAR
        JMP DRAW_STATUS_VALUES

HLC_COL7:
        LDA #7
        STA SEL_COLOR_IDX
        JSR PLAY_CLICK_BEEP
        JSR DRAW_TOOLBAR
        JMP DRAW_STATUS_VALUES

HLC_BTN_SIZE:
        JMP CYCLE_BRUSH_SIZE

HLC_BTN_STAMP:
        LDA STAMP_MODE
        EOR #1
        STA STAMP_MODE
        JSR PLAY_CLICK_BEEP
        JMP DRAW_TOOLBAR

HLC_HI2_BTNS:
        ; MX_HI == 2 (X = 512..639)
        LDA CUR_MX_LO
        CMP #48
        BCC HLC_BTN_BG2
        JMP CLEAR_CANVAS_AND_TARGET
HLC_BTN_BG2:
        JMP TOGGLE_BG_MODE

; --- Klik in het Teken-Canvas (Y = 54..333) ---
HLC_IN_CANVAS:
        ; Controleer eerst of het gouden Doelwit geraakt is!
        ; Doelwit box: TGT_X .. TGT_X + 20, TGT_Y .. TGT_Y + 20
        SEC
        LDA CUR_MX_LO
        SBC TGT_X_LO
        TAX
        LDA CUR_MX_HI
        SBC TGT_X_HI
        BNE HLC_NOT_TGT
        CPX #22
        BCS HLC_NOT_TGT

        ; X klopt! Controleer Y (TGT_Y is altijd 70..290, dus maar 16-bit vergelijking nodig):
        LDA CUR_MY_HI
        BNE HLC_MY_HI1
        LDA CUR_MY_LO
        SEC
        SBC TGT_Y_LO
        BCS HLC_CHK_TY_SPAN
        BCC HLC_NOT_TGT
HLC_MY_HI1:
        ; Als CUR_MY >= 256, dan moet TGT_Y >= 235 zijn:
        LDA TGT_Y_LO
        CMP #234
        BCC HLC_NOT_TGT
        LDA CUR_MY_LO
        CLC
        ADC #256 - 234
        ; Vereenvoudigd: houd TGT_Y tussen 64 en 230 zodat TGT_Y altijd MY_HI == 0 heeft!
        JMP HLC_NOT_TGT

HLC_CHK_TY_SPAN:
        CMP #22
        BCS HLC_NOT_TGT

        ; RAAK! Doelwit geraakt!
        JSR ERASE_OLD_TARGET
        CLC
        LDA SCORE_LO
        ADC #10
        STA SCORE_LO
        BCC HLC_SC_OK
        INC SCORE_HI
HLC_SC_OK:
        JSR PLAY_HIT_FANFARE
        JSR SPAWN_TARGET_POS
        JSR DRAW_TARGET
        JSR DRAW_STATUS_VALUES
        RTS

HLC_NOT_TGT:
        ; Als STEMPEL-modus aan staat, plaats een gekleurde cirkel/ster-stempel!
        LDA STAMP_MODE
        BEQ HLC_PAINT_NOW
        JSR DRAW_STAMP_AT_MOUSE
        RTS
HLC_PAINT_NOW:
        JMP HANDLE_CANVAS_PAINT

; ============================================================================
; Tekenen & Gummen op het Canvas (Y = 56..328)
; ============================================================================
CHECK_IN_CANVAS:
        ; Geeft Carry Clear (CLC) als Y tussen 56 en 326 ligt, anders SEC
        LDA CUR_MY_HI
        BNE CIC_HI1
        LDA CUR_MY_LO
        CMP #56
        BCC CIC_OUT
        CLC
        RTS
CIC_HI1:
        LDA CUR_MY_LO
        CMP #70                 ; 256 + 70 = 326
        BCS CIC_OUT
        CLC
        RTS
CIC_OUT:
        SEC
        RTS

HANDLE_CANVAS_PAINT:
        JSR CHECK_IN_CANVAS
        BCS HCP_RTS
        LDA CUR_MX_LO
        STA ZP_X_LO
        LDA CUR_MX_HI
        STA ZP_X_HI
        LDA CUR_MY_LO
        STA ZP_Y_LO
        LDA CUR_MY_HI
        STA ZP_Y_HI
        LDA BRUSH_SIZE
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #0
        STA ZP_W_HI
        STA ZP_H_HI
        LDX SEL_COLOR_IDX
        LDA PALETTE_TBL,X
        STA ZP_COL
        JMP GPU_RECT
HCP_RTS:
        RTS

HANDLE_CANVAS_ERASE:
        JSR CHECK_IN_CANVAS
        BCS HCP_RTS
        LDA CUR_MX_LO
        STA ZP_X_LO
        LDA CUR_MX_HI
        STA ZP_X_HI
        LDA CUR_MY_LO
        STA ZP_Y_LO
        LDA CUR_MY_HI
        STA ZP_Y_HI
        LDA #10
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #0
        STA ZP_W_HI
        STA ZP_H_HI
        JSR GET_CANVAS_BG_COL
        STA ZP_COL
        JMP GPU_RECT

DRAW_STAMP_AT_MOUSE:
        JSR CHECK_IN_CANVAS
        BCS HCP_RTS
        ; Teken gevulde schijf (DISK = cmd 5) met straal 10 in gekozen kleur + wit hart
        LDA #5
        STA IO_GPU
        LDA CUR_MX_LO
        STA IO_GPU
        LDA CUR_MX_HI
        STA IO_GPU
        LDA CUR_MY_LO
        STA IO_GPU
        LDA CUR_MY_HI
        STA IO_GPU
        LDA #10
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDX SEL_COLOR_IDX
        LDA PALETTE_TBL,X
        STA IO_GPU

        LDA #4                  ; Open cirkel rand (cmd 4) in wit
        STA IO_GPU
        LDA CUR_MX_LO
        STA IO_GPU
        LDA CUR_MX_HI
        STA IO_GPU
        LDA CUR_MY_LO
        STA IO_GPU
        LDA CUR_MY_HI
        STA IO_GPU
        LDA #10
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA #$FF
        STA IO_GPU
        JMP PLAY_CLICK_BEEP

; ============================================================================
; Actie-knoppen: Penseeldikte, 720p Achtergrond & Wis Scherm
; ============================================================================
CYCLE_BRUSH_SIZE:
        LDA BRUSH_SIZE
        CMP #2
        BEQ CBS_TO_4
        CMP #4
        BEQ CBS_TO_8
        LDA #2
        BNE CBS_STORE
CBS_TO_4:
        LDA #4
        BNE CBS_STORE
CBS_TO_8:
        LDA #8
CBS_STORE:
        STA BRUSH_SIZE
        JSR PLAY_CLICK_BEEP
        JMP DRAW_TOOLBAR

TOGGLE_BG_MODE:
        LDA BG_TRANSPARENT
        EOR #1
        STA BG_TRANSPARENT
        JSR PLAY_CLICK_BEEP
        JSR DRAW_TOOLBAR
        JMP CLEAR_CANVAS_AND_TARGET

CLEAR_CANVAS_AND_TARGET:
        ; Vul het canvasgebied (X=0..639, Y=54..334, H=280) met canvas-achtergrondkleur
        LDA #0
        STA ZP_X_LO
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #54
        STA ZP_Y_LO
        LDA #<640
        STA ZP_W_LO
        LDA #>640
        STA ZP_W_HI
        LDA #<280
        STA ZP_H_LO
        LDA #>280
        STA ZP_H_HI
        JSR GET_CANVAS_BG_COL
        STA ZP_COL
        JSR GPU_RECT

        ; Teken subtiele hulptekst bovenin het canvas
        LDA #16
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #60
        STA ZP_Y_LO
        LDA #$92
        STA ZP_COL
        LDA #<STR_CANVAS_HINT
        LDY #>STR_CANVAS_HINT
        JSR DRAW_STR_AY

        JSR SPAWN_TARGET_POS
        JSR DRAW_TARGET
        JMP PLAY_CLICK_BEEP

GET_CANVAS_BG_COL:
        LDA BG_TRANSPARENT
        BNE GCB_TRANS
        LDA #$01                ; Donkerblauw tekenvel
        RTS
GCB_TRANS:
        LDA #$E3                ; Transparant -> 720p Boerderij/Space zichtbaar!
        RTS

; ============================================================================
; Doelwit (Bullseye) Spawnen, Wissen & Tekenen
; ============================================================================
SPAWN_TARGET_POS:
        ; X tussen 40 en 550, Y tussen 76 en 225 (zodat Y altijd < 256 is)
        LDA IO_RND
        AND #$FF
        CLC
        ADC #40
        STA TGT_X_LO
        LDA #0
        ADC #0
        STA TGT_X_HI
        LDA IO_RND
        AND #$01
        BEQ STP_Y
        CLC
        LDA TGT_X_LO
        ADC #200
        STA TGT_X_LO
        BCC STP_Y
        INC TGT_X_HI
STP_Y:
        LDA IO_RND
        AND #$7F                ; 0..127
        CLC
        ADC #78                 ; 78..205
        STA TGT_Y_LO
        RTS

ERASE_OLD_TARGET:
        LDA TGT_X_LO
        STA ZP_X_LO
        LDA TGT_X_HI
        STA ZP_X_HI
        LDA TGT_Y_LO
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        STA ZP_W_HI
        STA ZP_H_HI
        LDA #22
        STA ZP_W_LO
        STA ZP_H_LO
        JSR GET_CANVAS_BG_COL
        STA ZP_COL
        JMP GPU_RECT

DRAW_TARGET:
        ; Buitenste rode vierkant (20x20)
        LDA TGT_X_LO
        STA ZP_X_LO
        LDA TGT_X_HI
        STA ZP_X_HI
        LDA TGT_Y_LO
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        STA ZP_W_HI
        STA ZP_H_HI
        LDA #20
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #$E0                ; Rood
        STA ZP_COL
        JSR GPU_RECT

        ; Middelste witte vierkant (12x12 op +4, +4)
        CLC
        LDA TGT_X_LO
        ADC #4
        STA ZP_X_LO
        LDA TGT_X_HI
        ADC #0
        STA ZP_X_HI
        CLC
        LDA TGT_Y_LO
        ADC #4
        STA ZP_Y_LO
        LDA #12
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #$FF                ; Wit
        STA ZP_COL
        JSR GPU_RECT

        ; Binnenste gouden roos (6x6 op +7, +7)
        CLC
        LDA TGT_X_LO
        ADC #7
        STA ZP_X_LO
        LDA TGT_X_HI
        ADC #0
        STA ZP_X_HI
        CLC
        LDA TGT_Y_LO
        ADC #7
        STA ZP_Y_LO
        LDA #6
        STA ZP_W_LO
        STA ZP_H_LO
        LDA #$FC                ; Goud-Geel
        STA ZP_COL
        JMP GPU_RECT

; ============================================================================
; Volledige UI, Knoppenbalk & Statusbalk Tekenen
; ============================================================================
DRAW_FULL_UI:
        ; Bovenste titelbalk (Y = 0..23)
        LDA #0
        STA ZP_X_LO
        STA ZP_X_HI
        STA ZP_Y_LO
        STA ZP_Y_HI
        LDA #<640
        STA ZP_W_LO
        LDA #>640
        STA ZP_W_HI
        LDA #24
        STA ZP_H_LO
        LDA #0
        STA ZP_H_HI
        LDA #$0B
        STA ZP_COL
        JSR GPU_RECT

        LDA #10
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #8
        STA ZP_Y_LO
        LDA #$FC
        STA ZP_COL
        LDA #<STR_TITLE
        LDY #>STR_TITLE
        JSR DRAW_STR_AY

        ; Onderste statusbalk achtergrond (Y = 334..359)
        LDA #0
        STA ZP_X_LO
        STA ZP_X_HI
        LDA #<334
        STA ZP_Y_LO
        LDA #>334
        STA ZP_Y_HI
        LDA #<640
        STA ZP_W_LO
        LDA #>640
        STA ZP_W_HI
        LDA #26
        STA ZP_H_LO
        LDA #0
        STA ZP_H_HI
        LDA #$09
        STA ZP_COL
        JSR GPU_RECT

        LDA #10
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<343
        STA ZP_Y_LO
        LDA #>343
        STA ZP_Y_HI
        LDA #$1F
        STA ZP_COL
        LDA #<STR_STATUS_LBL
        LDY #>STR_STATUS_LBL
        JSR DRAW_STR_AY

        JSR DRAW_TOOLBAR
        JMP CLEAR_CANVAS_AND_TARGET

DRAW_TOOLBAR:
        ; Achtergrond van de knoppenbalk (Y = 24..53)
        LDA #0
        STA ZP_X_LO
        STA ZP_X_HI
        STA ZP_Y_HI
        LDA #24
        STA ZP_Y_LO
        LDA #<640
        STA ZP_W_LO
        LDA #>640
        STA ZP_W_HI
        LDA #30
        STA ZP_H_LO
        LDA #0
        STA ZP_H_HI
        LDA #$25
        STA ZP_COL
        JSR GPU_RECT

        ; Teken de 8 Kleur-knoppen (elk 36px breed, 20px hoog, stap 40px vanaf X=8)
        LDA #0
        STA TEMP_IDX
DTB_COL_LP:
        LDX TEMP_IDX
        LDA COL_BTN_XL,X
        STA ZP_X_LO
        LDA COL_BTN_XH,X
        STA ZP_X_HI
        LDA #29
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        STA ZP_W_HI
        STA ZP_H_HI
        LDA #36
        STA ZP_W_LO
        LDA #20
        STA ZP_H_LO
        LDA PALETTE_TBL,X
        STA ZP_COL
        JSR GPU_RECT

        ; Als dit de geselecteerde kleur is, zet er een witte indicator-balk onder!
        LDX TEMP_IDX
        CPX SEL_COLOR_IDX
        BNE DTB_NEXT_COL
        LDA COL_BTN_XL,X
        STA ZP_X_LO
        LDA COL_BTN_XH,X
        STA ZP_X_HI
        LDA #50
        STA ZP_Y_LO
        LDA #36
        STA ZP_W_LO
        LDA #3
        STA ZP_H_LO
        LDA #$FF
        STA ZP_COL
        JSR GPU_RECT

DTB_NEXT_COL:
        INC TEMP_IDX
        LDA TEMP_IDX
        CMP #8
        BCC DTB_COL_LP

        ; Knop [DIKTE:n] op X = 334, W = 72
        LDA #<334
        STA ZP_X_LO
        LDA #>334
        STA ZP_X_HI
        LDA #29
        STA ZP_Y_LO
        LDA #0
        STA ZP_Y_HI
        LDA #72
        STA ZP_W_LO
        LDA #20
        STA ZP_H_LO
        LDA #$49
        STA ZP_COL
        JSR GPU_RECT

        LDA #<340
        STA ZP_X_LO
        LDA #>340
        STA ZP_X_HI
        LDA #35
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA #<STR_BTN_SIZE
        LDY #>STR_BTN_SIZE
        JSR DRAW_STR_AY
        LDA BRUSH_SIZE
        CLC
        ADC #'0'
        JSR DRAW_CHAR_ADV

        ; Knop [STEMPEL] op X = 410, W = 72
        LDA #<410
        STA ZP_X_LO
        LDA #>410
        STA ZP_X_HI
        LDA #29
        STA ZP_Y_LO
        LDA #72
        STA ZP_W_LO
        LDA #20
        STA ZP_H_LO
        LDA STAMP_MODE
        BEQ DTB_ST_OFF
        LDA #$1C                ; Groen als Stempel-modus AAN staat
        BNE DTB_ST_DRAW
DTB_ST_OFF:
        LDA #$49
DTB_ST_DRAW:
        STA ZP_COL
        JSR GPU_RECT

        LDA #<418
        STA ZP_X_LO
        LDA #>418
        STA ZP_X_HI
        LDA #35
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA #<STR_BTN_STAMP
        LDY #>STR_BTN_STAMP
        JSR DRAW_STR_AY

        ; Knop [720P BG] op X = 486, W = 72
        LDA #<486
        STA ZP_X_LO
        LDA #>486
        STA ZP_X_HI
        LDA #29
        STA ZP_Y_LO
        LDA #72
        STA ZP_W_LO
        LDA #20
        STA ZP_H_LO
        LDA BG_TRANSPARENT
        BEQ DTB_BG_OFF
        LDA #$F0                ; Oranje als 720p Boerderij AAN staat
        BNE DTB_BG_DRAW
DTB_BG_OFF:
        LDA #$49
DTB_BG_DRAW:
        STA ZP_COL
        JSR GPU_RECT

        LDA #<494
        STA ZP_X_LO
        LDA #>494
        STA ZP_X_HI
        LDA #35
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA #<STR_BTN_BG
        LDY #>STR_BTN_BG
        JSR DRAW_STR_AY

        ; Knop [WIS ALL] op X = 562, W = 70
        LDA #<562
        STA ZP_X_LO
        LDA #>562
        STA ZP_X_HI
        LDA #29
        STA ZP_Y_LO
        LDA #70
        STA ZP_W_LO
        LDA #20
        STA ZP_H_LO
        LDA #$A0                ; Donkerrood
        STA ZP_COL
        JSR GPU_RECT

        LDA #<570
        STA ZP_X_LO
        LDA #>570
        STA ZP_X_HI
        LDA #35
        STA ZP_Y_LO
        LDA #$FF
        STA ZP_COL
        LDA #<STR_BTN_CLR
        LDY #>STR_BTN_CLR
        JMP DRAW_STR_AY

FORCE_STATUS_UPDATE:
        LDA #$FF
        STA PREV_MX_LO
        JMP DRAW_STATUS_VALUES

; ============================================================================
; Teken alleen de dynamische X, Y, Knop & Score waarden in de onderste balk
; ============================================================================
DRAW_STATUS_VALUES:
        ; Wis X-veld (X=66..92), Y-veld (X=122..148), KNOP-veld (X=204..268), SCORE-veld (X=348..384)
        LDA #66
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<341
        STA ZP_Y_LO
        LDA #>341
        STA ZP_Y_HI
        LDA #28
        STA ZP_W_LO
        LDA #0
        STA ZP_W_HI
        LDA #12
        STA ZP_H_LO
        LDA #0
        STA ZP_H_HI
        LDA #$09
        STA ZP_COL
        JSR GPU_RECT

        LDA #66
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<343
        STA ZP_Y_LO
        LDA #>343
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_COL
        LDA CUR_MX_LO
        LDY CUR_MX_HI
        JSR DRAW_DEC16_3DIG

        ; Wis & teken Y-veld (X=122)
        LDA #122
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<341
        STA ZP_Y_LO
        LDA #>341
        STA ZP_Y_HI
        LDA #28
        STA ZP_W_LO
        LDA #12
        STA ZP_H_LO
        LDA #$09
        STA ZP_COL
        JSR GPU_RECT

        LDA #122
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<343
        STA ZP_Y_LO
        LDA #>343
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_COL
        LDA CUR_MY_LO
        LDY CUR_MY_HI
        JSR DRAW_DEC16_3DIG

        ; Wis & teken KNOP-veld (X=204..274)
        LDA #204
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<341
        STA ZP_Y_LO
        LDA #>341
        STA ZP_Y_HI
        LDA #70
        STA ZP_W_LO
        LDA #12
        STA ZP_H_LO
        LDA #$09
        STA ZP_COL
        JSR GPU_RECT

        LDA #204
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        LDA #<343
        STA ZP_Y_LO
        LDA #>343
        STA ZP_Y_HI
        LDA CUR_MST
        AND #$02
        BNE DSV_LMB
        LDA CUR_MST
        AND #$04
        BNE DSV_RMB
        LDA #$92
        STA ZP_COL
        LDA #<STR_BTN_NONE
        LDY #>STR_BTN_NONE
        JSR DRAW_STR_AY
        JMP DSV_SCORE
DSV_LMB:
        LDA #$FC
        STA ZP_COL
        LDA #<STR_BTN_LEFT
        LDY #>STR_BTN_LEFT
        JSR DRAW_STR_AY
        JMP DSV_SCORE
DSV_RMB:
        LDA #$F0
        STA ZP_COL
        LDA #<STR_BTN_RIGHT
        LDY #>STR_BTN_RIGHT
        JSR DRAW_STR_AY

DSV_SCORE:
        ; Wis & teken SCORE-veld (X=346..380)
        LDA #<346
        STA ZP_X_LO
        LDA #>346
        STA ZP_X_HI
        LDA #<341
        STA ZP_Y_LO
        LDA #>341
        STA ZP_Y_HI
        LDA #32
        STA ZP_W_LO
        LDA #12
        STA ZP_H_LO
        LDA #$09
        STA ZP_COL
        JSR GPU_RECT

        LDA #<346
        STA ZP_X_LO
        LDA #>346
        STA ZP_X_HI
        LDA #<343
        STA ZP_Y_LO
        LDA #>343
        STA ZP_Y_HI
        LDA #$1C
        STA ZP_COL
        LDA SCORE_LO
        LDY SCORE_HI
        JMP DRAW_DEC16_3DIG

; ============================================================================
; 3-Cijferige 16-bit Decimale Printer (000..999) voor (A=lo, Y=hi)
; ============================================================================
DRAW_DEC16_3DIG:
        LDX #'0'
        STX DEC_HUND
        STX DEC_TENS
DD16_100:
        CPY #0
        BNE DD16_SUB100
        CMP #100
        BCC DD16_10
DD16_SUB100:
        SEC
        SBC #100
        BCS DD16_INC100
        DEY
DD16_INC100:
        INC DEC_HUND
        BNE DD16_100
DD16_10:
        CMP #10
        BCC DD16_OUT
        SBC #10
        INC DEC_TENS
        BNE DD16_10
DD16_OUT:
        PHA
        LDA DEC_HUND
        JSR DRAW_CHAR_ADV
        LDA DEC_TENS
        JSR DRAW_CHAR_ADV
        PLA
        CLC
        ADC #'0'
        JMP DRAW_CHAR_ADV

; ============================================================================
; GPU & Geluid Hulproutines
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
        LDA ZP_H_HI
        STA IO_GPU
        LDA ZP_COL
        STA IO_GPU
        RTS

DRAW_STR_AY:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DSA_LP:
        LDY #0
        LDA (ZP_PTR_LO),Y
        BEQ DSA_RTS
        INC ZP_PTR_LO
        BNE DSA_DO
        INC ZP_PTR_HI
DSA_DO:
        JSR DRAW_CHAR_ADV
        JMP DSA_LP
DSA_RTS:
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
        LDA ZP_COL
        STA IO_GPU
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCA_OK
        INC ZP_X_HI
DCA_OK:
        RTS

PLAY_CLICK_BEEP:
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$00
        STA IO_GPU
        LDA #$48
        STA IO_GPU
        LDA #$02
        STA IO_GPU
        LDA #160
        STA IO_GPU
        LDA #4
        STA SND_TIMER
        RTS

PLAY_HIT_FANFARE:
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        LDA #$00
        STA IO_GPU
        LDA #$68
        STA IO_GPU
        LDA #$03
        STA IO_GPU
        LDA #210
        STA IO_GPU
        LDA #10
        STA SND_TIMER
        RTS

SILENCE_CH0:
        LDA #16
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        RTS

EXIT_TO_BASIC:
        JSR SILENCE_CH0
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
; Kleurentabellen & Teksten
; ============================================================================
PALETTE_TBL:
        .BYTE $FF, $FC, $F0, $E0, $C3, $1F, $1C, $07

COL_BTN_XL:
        .BYTE <8, <48, <88, <128, <168, <208, <248, <288
COL_BTN_XH:
        .BYTE >8, >48, >88, >128, >168, >208, >248, >288

STR_TITLE:
        .ASCIIZ "HARDWARE MUIS- & TEKEN-STUDIO  [ALT+PIJLTJES]=MUIS  [ALT+SPATIE]=KLIK"
STR_CANVAS_HINT:
        .ASCIIZ "KLIK OP HET DOELWIT (+10) OF TEKEN MET [ALT+SPATIE]! ([ALT+X]=GUM)"
STR_BTN_SIZE:
        .ASCIIZ "DIKTE:"
STR_BTN_STAMP:
        .ASCIIZ "STEMPEL"
STR_BTN_BG:
        .ASCIIZ "720P BG"
STR_BTN_CLR:
        .ASCIIZ "WIS ALL"
STR_STATUS_LBL:
        .ASCIIZ "MUIS X:    Y:     KNOP:          SCORE:     [1-8]KLEUR [B]720P [Q]UIT"
STR_BTN_NONE:
        .ASCIIZ "LOS     "
STR_BTN_LEFT:
        .ASCIIZ "KLIK!   "
STR_BTN_RIGHT:
        .ASCIIZ "GUM(R)  "
