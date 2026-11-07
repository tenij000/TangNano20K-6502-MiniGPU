; ============================================================================
; MC.asm - Midnight Commander 2.2 (Dual-Pane + Pull-Down Menu's + MD & Rename)
; Geassembleerd op $9000 in SDRAM zodat $0800 (BASIC) en $8000 (ASM) vrij zijn!
; Linker paneel (DIR_L_BUF = $5C00) & Rechter paneel (DIR_R_BUF = $5E00)
; met Alt Pull-Down Menu's, Submappen (MD / <MAP>), Rename, Copy, Move & Del!
; Starten in BASIC vanaf SD-kaart met:   BRUN MC
; ============================================================================
        ORG $9000

ZP_PRGEND       = $14
ZP_OP           = $18
ZP_TMP          = $1A
ZP_DST          = $1C
ZP_SIGN         = $22
DISK_DRIVE      = $0490
DISK_SLOT       = $0493
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497
SD_BUF          = $0500

ROM_STMT_RUN    = $E876
ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA

INP_LEN         = $45
MENU_OPEN       = $46
MENU_IDX        = $47
MENU_ITEM       = $48
MC_SEL          = $49
MC_ROW          = $4A
MC_X_LO         = $4B
MC_X_HI         = $4C
MC_Y_LO         = $4D
MC_Y_HI         = $4E
MC_COLOR        = $4F
MC_PTR_LO       = $50
MC_PTR_HI       = $51
MC_PREV_JOY     = $52
MC_BG_COL       = $53

ACTIVE_PANE     = $54
DRV_L           = $55
DRV_R           = $56
SEL_L           = $57
SEL_R           = $58
CUR_PANE        = $59
FILE_CNT        = $5A
SRC_SEC_LO      = $5B
SRC_SEC_HI      = $5C
DST_SEC_LO      = $5D
DST_SEC_HI      = $5E

STATUS_MSG_LO   = $88
STATUS_MSG_HI   = $89
DST_SLOT_TMP    = $8A
SRC_SLOT_TMP    = $8B
DST_DRIVE_TMP   = $8C
SRC_DRIVE_TMP   = $8D
COPY_SEC_CNT    = $8E

INP_BUF         = $5BE0
MC_MAGIC_ADDR   = $5BFE

DIR_L_BUF       = $5C00
DIR_R_BUF       = $5E00

START:
        LDA #12
        STA IO_TERM
        LDA #0
        STA IO_MODE
        STA MC_Y_HI
        STA MENU_OPEN
        STA MENU_IDX
        STA MENU_ITEM

        LDA MC_MAGIC_ADDR
        CMP #$5A
        BEQ WARM_START
        LDA #$5A
        STA MC_MAGIC_ADDR
        LDA #0
        STA ACTIVE_PANE
        STA DRV_L
        STA SEL_L
        STA SEL_R
        LDA #1
        STA DRV_R
        LDA #$02
        STA MC_BG_COL

WARM_START:
        LDA #STR_MSG_READY - STR_MSG_BASE
        JSR SET_STATUS_MSG
        LDA IO_JOY
        STA MC_PREV_JOY

READ_BOTH_DIRS:
        JSR LOAD_BOTH_DIRS

MAIN_LOOP:
        JSR DRAW_MC_SCREEN
        JMP WAIT_INPUT

LOAD_BOTH_DIRS:
        JSR ROM_SD_INIT
        LDX #0
        JSR READ_PANE_DIR
        LDX #1
        JSR READ_PANE_DIR
        JMP SYNC_ACTIVE_DRIVE

READ_PANE_DIR:
        STX CUR_PANE
        LDA DRV_L,X
        JSR MC_SETUP_DIR
        LDX CUR_PANE
        JSR SET_PANE_BUF_DST
        JMP ROM_READ_SEC

SET_PANE_BUF_DST:
        LDA #0
        STA ZP_DST
        LDA #>DIR_L_BUF
        CPX #0
        BEQ SPBD_OK
        LDA #>DIR_R_BUF
SPBD_OK:
        STA ZP_DST+1
        RTS

; --- Cursor Beweging in het Actieve Paneel of in het Pull-Down Menu ---
MOVE_UP:
        LDA MENU_OPEN
        BNE MENU_MOVE_UP
        LDX ACTIVE_PANE
        DEC SEL_L,X
        BPL GO_MAIN_1
        LDA #14
        STA SEL_L,X
        BNE GO_MAIN_1
MENU_MOVE_UP:
        DEC MENU_ITEM
        BPL GO_MAIN_1
        LDA #4
        STA MENU_ITEM
        BNE GO_MAIN_1

MOVE_DOWN:
        LDA MENU_OPEN
        BNE MENU_MOVE_DOWN
        LDX ACTIVE_PANE
        INC SEL_L,X
        LDA SEL_L,X
        CMP #15
        BCC GO_MAIN_1
        LDA #0
        STA SEL_L,X
        BEQ GO_MAIN_1
MENU_MOVE_DOWN:
        INC MENU_ITEM
        LDA MENU_ITEM
        CMP #5
        BCC GO_MAIN_1
        LDA #0
        STA MENU_ITEM
        BEQ GO_MAIN_1

MOVE_LEFT_ACT:
        LDA MENU_OPEN
        BNE MENU_PREV_COL
        LDA #0
        BEQ SET_ACT_PANE
MENU_PREV_COL:
        DEC MENU_IDX
        BPL GO_MAIN_1
        LDA #4
        STA MENU_IDX
        BNE GO_MAIN_1

MOVE_RIGHT_ACT:
        LDA MENU_OPEN
        BNE MENU_NEXT_COL
        LDA #1
        BNE SET_ACT_PANE
MENU_NEXT_COL:
        INC MENU_IDX
        LDA MENU_IDX
        CMP #5
        BCC GO_MAIN_1
        LDA #0
        STA MENU_IDX
        BEQ GO_MAIN_1

TOGGLE_PANE:
        LDA MENU_OPEN
        BNE MENU_NEXT_COL
        LDA ACTIVE_PANE
        EOR #1
SET_ACT_PANE:
        STA ACTIVE_PANE
        JSR SYNC_ACTIVE_DRIVE
GO_MAIN_1:
        JMP MAIN_LOOP

TOGGLE_MENU_BAR:
        LDA MENU_OPEN
        EOR #1
        STA MENU_OPEN
        LDA #0
        STA MENU_ITEM
        BEQ GO_MAIN_1

SYNC_ACTIVE_DRIVE:
        LDX ACTIVE_PANE
        LDA DRV_L,X
        AND #$3F
        STA DISK_DRIVE
        RTS

; ============================================================================
; Toetsenbord & Joypad Invoer-lus
; ============================================================================
WAIT_INPUT:
        JSR DELAY_10MS

        LDA IO_STATUS
        BPL CHK_JOY_BITS
        LDA IO_TERM
        LDA MENU_OPEN
        BNE CLOSE_MENU_BAR
        JMP QUIT_MC

CLOSE_MENU_BAR:
        LDA #0
        STA MENU_OPEN
        BEQ GO_MAIN_1

CHK_JOY_BITS:
        LDA IO_JOY
        STA ZP_SIGN
        TAX
        EOR MC_PREV_JOY
        AND ZP_SIGN
        STX MC_PREV_JOY
        TAY
        BEQ CHECK_TERM_KEY

        LDA IO_STATUS
        AND #1
        BEQ JOY_NO_ECHO
        LDA IO_TERM
        CMP #$0D
        BEQ GO_ENTER_ACT
        CMP #$0E
        BEQ TOGGLE_MENU_BAR
JOY_NO_ECHO:
        TYA
        AND #1
        BNE MOVE_UP
        TYA
        AND #2
        BNE MOVE_DOWN
        TYA
        AND #4
        BNE MOVE_LEFT_ACT
        TYA
        AND #8
        BNE MOVE_RIGHT_ACT
        TYA
        AND #$40
        BNE TOGGLE_PANE
        TYA
        AND #16
        BNE GO_ENTER_ACT
        BEQ WAIT_INPUT

GO_ENTER_ACT:
        LDA MENU_OPEN
        BNE EXEC_MENU_ITEM
        JMP EXEC_SELECTED

CHECK_TERM_KEY:
        LDA IO_STATUS
        AND #1
        BEQ WAIT_INPUT
        LDA IO_TERM
        CMP #$0E
        BEQ TOGGLE_MENU_BAR
        CMP #'/'
        BEQ TOGGLE_MENU_BAR
        CMP #$0D
        BEQ GO_ENTER_ACT
        CMP #' '
        BEQ GO_ENTER_ACT
        CMP #$09
        BEQ TOGGLE_PANE

        CMP #$08
        BEQ GO_UP_OR_DEL

        CMP #'a'
        BCC CTK_CHK_MENU
        CMP #'z'+1
        BCS CTK_CHK_MENU
        AND #$DF
CTK_CHK_MENU:
        LDX MENU_OPEN
        BNE CHECK_OPEN_MENU_KEYS
CTK_SCAN:
        LDX #KEY_TBL_END - KEY_TBL - 1
CTK_LP:
        CMP KEY_TBL,X
        BEQ CTK_FOUND
        DEX
        BPL CTK_LP
        BMI WAIT_INPUT
CTK_FOUND:
        LDA KEY_ACT_LO,X
        STA MC_PTR_LO
        LDA KEY_ACT_HI,X
        STA MC_PTR_HI
        JMP (MC_PTR_LO)

CHECK_OPEN_MENU_KEYS:
        LDX #4
COMK_LP:
        CMP MENU_HOTKEYS,X
        BEQ OPEN_MENU_X
        DEX
        BPL COMK_LP
        CMP #'Q'
        BEQ CLOSE_MENU_BAR
        CMP #'0'
        BCC CTK_SCAN
        CMP #'9'+1
        BCS CTK_SCAN
        LDX #0
        STX MENU_OPEN
        BEQ CTK_SCAN

OPEN_MENU_L:
        LDX #0
        BEQ OPEN_MENU_X
OPEN_MENU_O:
        LDX #3
        BNE OPEN_MENU_X
OPEN_MENU_R:
        LDX #4
OPEN_MENU_X:
        STX MENU_IDX
        LDA #0
        STA MENU_ITEM
        LDA #1
        STA MENU_OPEN
        JMP MAIN_LOOP

GO_UP_OR_DEL:
        LDX ACTIVE_PANE
        LDA DRV_L,X
        CMP #4
        BCC GO_DEL_NOW
        SBC #4
        LDY #0
GUD_DIV:
        CMP #15
        BCC GUD_SET
        SBC #15
        INY
        BNE GUD_DIV
GUD_SET:
        TYA
        STA DRV_L,X
        LDA #0
        STA SEL_L,X
        JMP READ_BOTH_DIRS
GO_DEL_NOW:
        JMP DO_DELETE_FILE

; ============================================================================
; Uitvoeren van een gekozen optie uit één van de 5 Pull-Down Menu's!
; ============================================================================
EXEC_MENU_ITEM:
        LDA #0
        STA MENU_OPEN
        LDX MENU_IDX
        LDY MENU_ITEM
        CPX #0
        BEQ EMI_LEFT
        CPX #4
        BEQ EMI_RIGHT

        DEX
        TXA
        ASL A
        ASL A
        ADC MENU_IDX
        SEC
        SBC #1
        CLC
        ADC MENU_ITEM
        TAX
        LDA MENU_ACT_LO,X
        STA MC_PTR_LO
        LDA MENU_ACT_HI,X
        STA MC_PTR_HI
        JMP (MC_PTR_LO)

EMI_RIGHT:
        CPY #4
        BCS EMI_RESCAN
        STY DRV_R
        LDA #0
        STA SEL_R
        LDA #1
        BNE EMI_DRV_SET
EMI_LEFT:
        CPY #4
        BCS EMI_RESCAN
        STY DRV_L
        LDA #0
        STA SEL_L
EMI_DRV_SET:
        STA ACTIVE_PANE
        JMP NEXT_DRV_MSG
EMI_RESCAN:
        JMP READ_BOTH_DIRS

EMI_FOC_R:
        LDA #1
        BNE EMI_SET_FOC
EMI_FOC_L:
        LDA #0
EMI_SET_FOC:
        JMP SET_ACT_PANE

EMI_BG_BLUE:
        LDA #$02
        BNE SET_BG_A
SET_BG_TRANS:
        LDA #$E3
SET_BG_A:
        STA MC_BG_COL
        JMP MAIN_LOOP

TOGGLE_BG:
        LDA MC_BG_COL
        CMP #$02
        BEQ SET_BG_TRANS
        BNE EMI_BG_BLUE

NEXT_ACTIVE_DRIVE:
        LDX ACTIVE_PANE
        LDA DRV_L,X
        CLC
        ADC #1
        AND #3
        STA DRV_L,X
        LDA #0
        STA SEL_L,X
NEXT_DRV_MSG:
        LDA #STR_MSG_DRV - STR_MSG_BASE
        JSR SET_STATUS_MSG
        JMP READ_BOTH_DIRS

SWAP_DRIVES:
        LDA DRV_L
        LDX DRV_R
        STA DRV_R
        STX DRV_L
        LDA SEL_L
        LDX SEL_R
        STA SEL_R
        STX SEL_L
        LDA #STR_MSG_SWAP - STR_MSG_BASE
        JSR SET_STATUS_MSG
        JMP READ_BOTH_DIRS

SET_STATUS_MSG:
        CLC
        ADC #<STR_MSG_BASE
        STA STATUS_MSG_LO
        LDA #0
        ADC #>STR_MSG_BASE
        STA STATUS_MSG_HI
        RTS

QUIT_MC:
        JSR SYNC_ACTIVE_DRIVE
        JSR ROM_SILENCE
        LDA #1
        STA IO_GPU
        LDA #$E3
        STA IO_GPU
        LDA #12
        STA IO_TERM
        RTS

; ============================================================================
; RENAME (4/F4/N) & MKDIR / MD (7/F7/K) MET INTERACTIEF INVOERVENSTER
; ============================================================================
DO_RENAME_FILE:
        LDX ACTIVE_PANE
        LDA SEL_L,X
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE DRF_EMPTY
        JSR IS_PROTECTED_SLOT
        BEQ DRF_PROT

        LDA #STR_DLG_REN - STR_MSG_BASE
        JSR INPUT_NAME_DIALOG
        BCS DRF_DONE

        LDX ACTIVE_PANE
        LDA SEL_L,X
        JSR GET_PANE_SLOT_PTR
        JSR WRITE_INP_TO_SLOT
        LDX ACTIVE_PANE
        JSR SAVE_PANE_DIR
        LDA #STR_MSG_REN - STR_MSG_BASE
        JSR SET_STATUS_MSG
        JMP READ_BOTH_DIRS
DRF_EMPTY:
        JMP DDF_EMPTY
DRF_PROT:
        JMP DDF_PROT
DRF_DONE:
        JMP MAIN_LOOP

DO_MKDIR:
        LDX ACTIVE_PANE
        LDA DRV_L,X
        CMP #4
        BCS DRF_PROT

        JSR FIND_FREE_SLOT_X
        BCS DRF_DONE
        STA DST_SLOT_TMP

        LDA #STR_DLG_MD - STR_MSG_BASE
        JSR INPUT_NAME_DIALOG
        BCS DRF_DONE

        LDX ACTIVE_PANE
        LDA DRV_L,X
        STA SRC_DRIVE_TMP
        ASL A
        ASL A
        ASL A
        ASL A
        SEC
        SBC SRC_DRIVE_TMP
        CLC
        ADC #4
        ADC DST_SLOT_TMP
        STA DST_DRIVE_TMP

        LDY #0
        TYA
DMK_CLR_SD:
        STA SD_BUF,Y
        STA SD_BUF+$100,Y
        INY
        BNE DMK_CLR_SD

        LDA #'B'
        STA SD_BUF+0
        STA SD_BUF+1
        LDA #'C'
        STA SD_BUF+2
        LDA #'!'
        STA SD_BUF+3
        LDA #'.'
        STA SD_BUF+4
        STA SD_BUF+5
        LDA #'D'
        STA SD_BUF+22
        LDA SRC_DRIVE_TMP
        STA SD_BUF+23

        LDA DST_DRIVE_TMP
        JSR MC_SETUP_DIR
        LDA #0
        STA ZP_DST
        LDA #>SD_BUF
        STA ZP_DST+1
        JSR ROM_WRITE_SEC

        LDX ACTIVE_PANE
        LDA DST_SLOT_TMP
        STA SEL_L,X
        JSR GET_PANE_SLOT_PTR
        LDY #23
DMK_CP_HDR:
        LDA SD_BUF,Y
        STA (ZP_TMP),Y
        DEY
        BPL DMK_CP_HDR
        JSR WRITE_INP_TO_SLOT
        LDY #23
        LDA DST_DRIVE_TMP
        STA (ZP_TMP),Y

        LDX ACTIVE_PANE
        JSR SAVE_PANE_DIR

        LDA #STR_MSG_MD - STR_MSG_BASE
        JSR SET_STATUS_MSG
        JMP READ_BOTH_DIRS

FIND_FREE_SLOT_X:
        STX CUR_PANE
        LDA SEL_L,X
        STA MC_ROW
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE FFS_FOUND
        LDA #0
        STA MC_ROW
FFS_LP:
        LDX CUR_PANE
        LDA MC_ROW
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE FFS_FOUND
        INC MC_ROW
        LDA MC_ROW
        CMP #15
        BCC FFS_LP
        LDA #STR_MSG_FULL - STR_MSG_BASE
        JSR SET_STATUS_MSG
        SEC
        RTS
FFS_FOUND:
        LDA MC_ROW
        CLC
        RTS

WRITE_INP_TO_SLOT:
        LDY #4
        LDA #0
WITS_CLR:
        STA (ZP_TMP),Y
        INY
        CPY #16
        BCC WITS_CLR
        LDX #0
        LDY #4
WITS_CP:
        CPX INP_LEN
        BCS WITS_RTS
        LDA INP_BUF,X
        STA (ZP_TMP),Y
        INX
        INY
        BNE WITS_CP
WITS_RTS:
        RTS

; --- Interactief Invoer-dialoogvenster voor Rename & MkDir (MD) ---
INPUT_NAME_DIALOG:
        JSR SET_STATUS_MSG
        LDA #0
        STA INP_LEN
        STA INP_BUF

IND_LOOP:
        LDX #0
IND_GPU_LP:
        LDA DLG_STREAM,X
        STA IO_GPU
        INX
        CPX #DLG_STREAM_END - DLG_STREAM
        BCC IND_GPU_LP

        LDA #200
        STA MC_X_LO
        LDA #0
        STA MC_X_HI
        STA MC_Y_HI
        LDA #147
        STA MC_Y_LO
        LDA #$FC
        STA MC_COLOR
        LDA STATUS_MSG_LO
        LDY STATUS_MSG_HI
        JSR DRAW_STR_AY

        LDA #212
        STA MC_X_LO
        LDA #0
        STA MC_X_HI
        LDA #170
        STA MC_Y_LO
        LDA #$FF
        STA MC_COLOR
        LDA #<INP_BUF
        LDY #>INP_BUF
        JSR DRAW_STR_AY
        LDA #'_'
        JSR DRAW_CHAR_ADV

IND_WAIT:
        JSR DELAY_10MS
        LDA IO_STATUS
        BPL IND_CHK_KEY
        LDA IO_TERM
        JMP IND_CANCEL
IND_CHK_KEY:
        AND #1
        BEQ IND_WAIT
        LDA IO_TERM
        CMP #$1B
        BEQ IND_CANCEL
        CMP #$0D
        BEQ IND_OK
        CMP #$08
        BEQ IND_BS
        CMP #$7F
        BEQ IND_BS
        CMP #' '
        BCC IND_WAIT
        CMP #'a'
        BCC IND_UPPER
        CMP #'z'+1
        BCS IND_WAIT
        AND #$DF
IND_UPPER:
        LDX INP_LEN
        CPX #11
        BCS IND_WAIT
        STA INP_BUF,X
        INX
        STX INP_LEN
        LDA #0
        STA INP_BUF,X
        BEQ IND_LOOP

IND_BS:
        LDX INP_LEN
        BEQ IND_WAIT
        DEX
        STX INP_LEN
        LDA #0
        STA INP_BUF,X
        BEQ IND_LOOP

IND_OK:
        LDA INP_LEN
        BEQ IND_CANCEL
        CLC
        BCC IND_EXIT
IND_CANCEL:
        SEC
IND_EXIT:
        PHP
        LDA #STR_MSG_READY - STR_MSG_BASE
        JSR SET_STATUS_MSG
        PLP
        RTS

; ============================================================================
; KOPIEER (5/C), VERPLAATS (6/M) & WIS (8/X) TUSSEN LINKER EN RECHTER PANEEL
; ============================================================================
DO_COPY_FILE:
        JSR INTERNAL_COPY_FILE
        JMP MAIN_LOOP

DO_MOVE_FILE:
        JSR INTERNAL_COPY_FILE
        BCS DMF_DONE
        LDA SRC_DRIVE_TMP
        CMP DST_DRIVE_TMP
        BNE DMF_DEL_SRC
        LDA SRC_SLOT_TMP
        CMP DST_SLOT_TMP
        BEQ DMF_DONE
DMF_DEL_SRC:
        LDA SRC_SLOT_TMP
        LDX ACTIVE_PANE
        JSR GET_PANE_SLOT_PTR
        JSR IS_PROTECTED_SLOT
        BEQ DMF_DONE
        JSR CLEAR_SLOT_AT_TMP
        LDX ACTIVE_PANE
        JSR SAVE_PANE_DIR
        LDA #STR_MSG_MOVED - STR_MSG_BASE
        JSR SET_STATUS_MSG
        JMP READ_BOTH_DIRS
DMF_DONE:
        JMP MAIN_LOOP

DO_DELETE_FILE:
        LDX ACTIVE_PANE
        LDA SEL_L,X
        STA SRC_SLOT_TMP
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE DDF_EMPTY

        JSR IS_PROTECTED_SLOT
        BNE DDF_DO_IT
DDF_PROT:
        LDA #STR_MSG_PROT - STR_MSG_BASE
        JSR SET_STATUS_MSG
        JMP MAIN_LOOP

IS_PROTECTED_SLOT:
        LDY #4
        LDA (ZP_TMP),Y
        CMP #'.'
        BNE IPS_CHK_MC
        LDY #22
        LDA (ZP_TMP),Y
        CMP #'D'
        RTS
IPS_CHK_MC:
        LDX ACTIVE_PANE
        LDA DRV_L,X
        BNE IPS_RTS
        LDA (ZP_TMP),Y
        CMP #'M'
        BNE IPS_RTS
        INY
        LDA (ZP_TMP),Y
        CMP #'C'
        BNE IPS_RTS
        INY
        LDA (ZP_TMP),Y
        CMP #0
IPS_RTS:
        RTS

DDF_DO_IT:
        JSR CLEAR_SLOT_AT_TMP
        LDX ACTIVE_PANE
        JSR SAVE_PANE_DIR
        LDA #STR_MSG_DEL - STR_MSG_BASE
        JSR SET_STATUS_MSG
        JMP READ_BOTH_DIRS

DDF_EMPTY:
        LDA #STR_MSG_EMPTY - STR_MSG_BASE
        JSR SET_STATUS_MSG
        JMP MAIN_LOOP

; --- Kernroutine voor Kopiëren van Actief Paneel -> Ander Paneel ---
INTERNAL_COPY_FILE:
        LDX ACTIVE_PANE
        LDA DRV_L,X
        STA SRC_DRIVE_TMP
        LDA SEL_L,X
        STA SRC_SLOT_TMP
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE ICF_ERR_EMPTY
        LDY #22
        LDA (ZP_TMP),Y
        CMP #'D'
        BNE ICF_SRC_OK
ICF_ERR_EMPTY:
        LDA #STR_MSG_EMPTY - STR_MSG_BASE
        JSR SET_STATUS_MSG
        SEC
        RTS

ICF_SRC_OK:
        LDA ZP_TMP
        STA MC_PTR_LO
        LDA ZP_TMP+1
        STA MC_PTR_HI

        LDA ACTIVE_PANE
        EOR #1
        TAX
        LDA DRV_L,X
        STA DST_DRIVE_TMP

        CMP SRC_DRIVE_TMP
        BEQ ICF_USE_FREE
        LDA #0
        STA MC_ROW
ICF_SAME_LP:
        LDA ACTIVE_PANE
        EOR #1
        TAX
        LDA MC_ROW
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE ICF_SAME_NXT
        LDY #4
ICF_CMP_NM:
        LDA (MC_PTR_LO),Y
        CMP (ZP_TMP),Y
        BNE ICF_SAME_NXT
        CMP #0
        BEQ ICF_FOUND_SAME
        INY
        CPY #16
        BCC ICF_CMP_NM
ICF_FOUND_SAME:
        LDA MC_ROW
        JMP ICF_GOT_DST_SLOT
ICF_SAME_NXT:
        INC MC_ROW
        LDA MC_ROW
        CMP #15
        BCC ICF_SAME_LP

ICF_USE_FREE:
        LDA ACTIVE_PANE
        EOR #1
        TAX
        JSR FIND_FREE_SLOT_X
        BCC ICF_GOT_DST_SLOT
        RTS

ICF_GOT_DST_SLOT:
        STA DST_SLOT_TMP
        LDY SRC_DRIVE_TMP
        CPY DST_DRIVE_TMP
        BNE ICF_DO_SECTORS
        CMP SRC_SLOT_TMP
        BNE ICF_DO_SECTORS
        LDA #STR_MSG_PROT - STR_MSG_BASE
        JSR SET_STATUS_MSG
        SEC
        RTS

ICF_DO_SECTORS:
        LDY #21
        LDA (MC_PTR_LO),Y
        LSR A
        CLC
        ADC #1
        STA COPY_SEC_CNT

        LDA SRC_DRIVE_TMP
        STA DISK_DRIVE
        LDA SRC_SLOT_TMP
        STA DISK_SLOT
        JSR MC_SETUP_SLOT
        LDA DISK_SEC_LO
        STA SRC_SEC_LO
        LDA DISK_SEC_HI
        STA SRC_SEC_HI

        LDA DST_DRIVE_TMP
        STA DISK_DRIVE
        LDA DST_SLOT_TMP
        STA DISK_SLOT
        JSR MC_SETUP_SLOT
        LDA DISK_SEC_LO
        STA DST_SEC_LO
        LDA DISK_SEC_HI
        STA DST_SEC_HI

ICF_SEC_LP:
        LDA SRC_SEC_LO
        LDY SRC_SEC_HI
        JSR SET_SD_BUF_SEC
        JSR ROM_READ_SEC
        LDA DISK_SEC_LO
        STA SRC_SEC_LO
        LDA DISK_SEC_HI
        STA SRC_SEC_HI

        LDA DST_SEC_LO
        LDY DST_SEC_HI
        JSR SET_SD_BUF_SEC
        JSR ROM_WRITE_SEC
        LDA DISK_SEC_LO
        STA DST_SEC_LO
        LDA DISK_SEC_HI
        STA DST_SEC_HI

        DEC COPY_SEC_CNT
        BNE ICF_SEC_LP

        LDA ACTIVE_PANE
        EOR #1
        TAX
        LDA DST_SLOT_TMP
        STA SEL_L,X
        JSR GET_PANE_SLOT_PTR
        LDY #31
ICF_DIR_CP:
        LDA (MC_PTR_LO),Y
        STA (ZP_TMP),Y
        DEY
        BPL ICF_DIR_CP

        LDA ACTIVE_PANE
        EOR #1
        TAX
        JSR SAVE_PANE_DIR
        JSR LOAD_BOTH_DIRS

        LDA #STR_MSG_COPIED - STR_MSG_BASE
        JSR SET_STATUS_MSG
        CLC
        RTS

SET_SD_BUF_SEC:
        STA DISK_SEC_LO
        STY DISK_SEC_HI
        LDA #0
        STA ZP_DST
        LDA #>SD_BUF
        STA ZP_DST+1
        RTS

CLEAR_SLOT_AT_TMP:
        LDY #31
        LDA #0
CSAT_LP:
        STA (ZP_TMP),Y
        DEY
        BPL CSAT_LP
        RTS

SAVE_PANE_DIR:
        STX CUR_PANE
        LDA DRV_L,X
        JSR MC_SETUP_DIR
        LDX CUR_PANE
        JSR SET_PANE_BUF_DST
        JSR ROM_WRITE_SEC
        JMP SYNC_ACTIVE_DRIVE

MC_SETUP_DIR:
        STA DISK_DRIVE
        ASL A
        ASL A
        CLC
        ADC #$03
        STA DISK_SEC_HI
        LDA #$FF
        STA DISK_SEC_LO
        RTS

MC_SETUP_SLOT:
        LDA DISK_SLOT
        AND #3
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        STA DISK_SEC_LO
        LDA DISK_DRIVE
        ASL A
        ASL A
        CLC
        ADC #$04
        STA DISK_SEC_HI
        LDA DISK_SLOT
        LSR A
        LSR A
        CLC
        ADC DISK_SEC_HI
        STA DISK_SEC_HI
        RTS

; ============================================================================
; EXEC_SELECTED: Open <MAP> óf start het geselecteerde programma!
; ============================================================================
EXEC_SELECTED:
        LDX ACTIVE_PANE
        LDA DRV_L,X
        STA DISK_DRIVE
        LDA SEL_L,X
        STA DISK_SLOT
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE GO_MAIN_LOOP_2

        LDY #22
        LDA (ZP_TMP),Y
        CMP #'D'
        BNE EX_NOT_DIR

        LDY #23
        LDA (ZP_TMP),Y
        LDX ACTIVE_PANE
        STA DRV_L,X
        LDA #0
        STA SEL_L,X
        JMP NEXT_DRV_MSG

EX_NOT_DIR:
        LDY #20
        LDA (ZP_TMP),Y
        STA ZP_OP
        INY
        LDA (ZP_TMP),Y
        STA ZP_OP+1
        ORA ZP_OP
        BEQ EX_EMPTY_SLOT

        LDY #22
        LDA (ZP_TMP),Y
        CMP #'B'
        BEQ EXEC_ASM_FILE

        JSR MC_SETUP_SLOT
        LDA #$00
        STA ZP_DST
        LDA #$08
        STA ZP_DST+1
        JSR LOAD_SLOT_SECTORS
        JSR SYNC_ACTIVE_DRIVE

        CLC
        LDA #$00
        ADC ZP_OP
        STA ZP_PRGEND
        LDA #$08
        ADC ZP_OP+1
        STA ZP_PRGEND+1
        LDA ZP_PRGEND
        BNE EX_BAS_DEC
        DEC ZP_PRGEND+1
EX_BAS_DEC:
        DEC ZP_PRGEND
        LDY #0
        TYA
        STA (ZP_PRGEND),Y

        LDA #12
        STA IO_TERM
        STA IO_GPU
        LDA #1
        STA IO_GPU
        JSR ROM_SILENCE
        JSR ROM_STMT_RUN
        LDA $20
        BMI GOT_ASM_KEY
        BPL ENTER_WAIT_KEY

EX_EMPTY_SLOT:
        JMP DDF_EMPTY

GO_MAIN_LOOP_2:
        JMP MAIN_LOOP

EXEC_ASM_FILE:
        LDY #23
        LDA (ZP_TMP),Y
        STA ZP_DST
        STA MC_PTR_LO
        INY
        LDA (ZP_TMP),Y
        STA ZP_DST+1
        STA MC_PTR_HI

        CMP #$08
        BCC EX_EMPTY_SLOT
        CMP #$90
        BCS GO_MAIN_LOOP_2
        JSR MC_SETUP_SLOT
        JSR LOAD_SLOT_SECTORS
        JSR SYNC_ACTIVE_DRIVE
        LDA MC_PTR_HI
        BMI EXEC_DO_CALL
        CMP #$50
        BEQ LAUNCH_VIEWER_FOR_IMG
        CMP #$60
        BEQ LAUNCH_READER_FOR_TXT
        BCS GO_MAIN_LOOP_2

EXEC_DO_CALL:
        LDA IO_TERM
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        JSR CALL_LOADED_ASM
        LDA IO_MODE
        BNE GOT_ASM_KEY

ENTER_WAIT_KEY:
        JSR DELAY_10MS
        LDA IO_TERM
        LDA IO_JOY
        LDA IO_JOY
        STA MC_PREV_JOY
WAIT_ASM_KEY:
        JSR DELAY_10MS
        LDA IO_STATUS
        BMI GOT_ASM_KEY
        AND #1
        BNE GOT_ASM_KEY
        LDA IO_JOY
        TAX
        EOR MC_PREV_JOY
        STX MC_PREV_JOY
        AND MC_PREV_JOY
        AND #$1F
        BEQ WAIT_ASM_KEY
GOT_ASM_KEY:
        JSR ROM_SILENCE
        JSR DELAY_10MS
        LDA IO_TERM
        JMP START

; --- Start automatisch VIEWER ($8000) voor $5000 .IMG plaatjes of READER voor $6000 .TXT ---
LAUNCH_READER_FOR_TXT:
        LDA #0
        STA $5520               ; DOC_MAGIC = 0 zodat READER het .TXT bestand inlaadt
        LDA #'R'                ; Zoek "READER" op Drive D0
        BNE FIND_HELPER_APP
LAUNCH_VIEWER_FOR_IMG:
        LDA #'V'                ; Zoek "VIEWER" op Drive D0
FIND_HELPER_APP:
        STA MC_ROW
        LDA #0
        STA DISK_SLOT
        LDA #3                  ; Zoek READER/VIEWER op Office Drive D3
        JSR MC_SETUP_DIR
        LDX #1
        JSR SET_PANE_BUF_DST    ; Gebruik DIR_R_BUF ($5E00) tijdelijk als zoekbuffer
        JSR ROM_READ_SEC
FHA_LP:
        LDX #1
        LDA DISK_SLOT
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE FHA_NXT
        LDY #24
        LDA (ZP_TMP),Y
        CMP #$80
        BNE FHA_NXT
        LDY #4
        LDA (ZP_TMP),Y
        CMP MC_ROW
        BEQ FHA_RUN
FHA_NXT:
        INC DISK_SLOT
        LDA DISK_SLOT
        CMP #15
        BCC FHA_LP
        JMP READ_BOTH_DIRS
FHA_RUN:
        JMP EX_NOT_DIR

CALL_LOADED_ASM:
        JMP (MC_PTR_LO)

DELAY_10MS:
        LDA IO_TIMER
D10_LP:
        CMP IO_TIMER
        BEQ D10_LP
        RTS

LOAD_SLOT_SECTORS:
        LDA ZP_OP+1
        LSR A
        CLC
        ADC #1
        STA ZP_SIGN
LSS_LP:
        JSR ROM_READ_SEC
        DEC ZP_SIGN
        BNE LSS_LP
        RTS

; ============================================================================
; DRAW_MC_SCREEN: Tekent het Dual-Pane Midnight Commander scherm + Pull-Down Menu
; ============================================================================
DRAW_MC_SCREEN:
        LDA #12
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA MC_X_HI
        STA MC_Y_HI
        STA MC_COLOR
        LDA #1
        STA IO_GPU
        LDA MC_BG_COL
        STA IO_GPU

        LDX #0
UI_LP:
        LDA UI_STREAM,X
        STA IO_GPU
        INX
        CPX #UI_STREAM_END - UI_STREAM
        BCC UI_LP

        LDA #12
        STA MC_X_LO
        LDA #4
        STA MC_Y_LO
        LDA #<STR_TOP_BAR
        LDY #>STR_TOP_BAR
        JSR DRAW_STR_AY

        LDA #8
        STA MC_X_LO
        LDA #0
        STA MC_X_HI
        LDA #$5A
        STA MC_Y_LO
        LDA #$01
        STA MC_Y_HI
        LDA #0
        STA MC_COLOR
        LDA #<STR_BOT_BAR
        LDY #>STR_BOT_BAR
        JSR DRAW_STR_AY

        LDA #0
        STA CUR_PANE
        JSR DRAW_ONE_PANE
        LDA #1
        STA CUR_PANE
        JSR DRAW_ONE_PANE

        LDA #$50
        STA MC_X_LO
        LDA #$01
        STA MC_X_HI
        STA MC_Y_HI
        LDA #$3C
        STA MC_Y_LO
        LDA #$FC
        STA MC_COLOR
        LDA STATUS_MSG_LO
        LDY STATUS_MSG_HI
        JSR DRAW_STR_AY

        LDA MENU_OPEN
        BEQ DMS_FLIP
        JSR DRAW_PULLDOWN_MENU

DMS_FLIP:
        LDA #11
        STA IO_GPU
        RTS

; ============================================================================
; DRAW_PULLDOWN_MENU: Tekent het actieve uitklapmenu (Left/File/Command/Options/Right)
; ============================================================================
DRAW_PULLDOWN_MENU:
        LDX MENU_IDX

        LDA MENU_BAR_X_LO,X
        STA MC_X_LO
        LDA MENU_BAR_X_HI,X
        STA MC_X_HI
        LDA #1
        STA MC_Y_LO
        LDA #0
        STA MC_Y_HI
        STA MC_COLOR
        TAY
        LDA MENU_BAR_W,X
        LDX #13
        JSR GPU_RECT

        LDX MENU_IDX
        CLC
        LDA MENU_BAR_X_LO,X
        ADC #6
        STA MC_X_LO
        LDA MENU_BAR_X_HI,X
        ADC #0
        STA MC_X_HI
        LDA #4
        STA MC_Y_LO
        LDA #$FC
        STA MC_COLOR
        LDA MENU_TITLE_LO,X
        LDY MENU_TITLE_HI,X
        JSR DRAW_STR_AY

        LDA #144
        STA ZP_TMP
        LDA #84
        STA ZP_TMP+1
        LDA #$00
        STA MC_COLOR
        LDA #4
        LDY #19
        JSR GPU_WIN_RECT

        LDA #$1F
        STA MC_COLOR
        LDA #0
        LDY #15
        JSR GPU_WIN_RECT

        LDA #140
        STA ZP_TMP
        LDA #80
        STA ZP_TMP+1
        LDA #$0B
        STA MC_COLOR
        LDA #2
        LDY #17
        JSR GPU_WIN_RECT

        LDX MENU_IDX
        LDA MENU_LIST_LO,X
        STA MC_PTR_LO
        LDA MENU_LIST_HI,X
        STA MC_PTR_HI

        LDA #0
        STA MC_ROW
DPM_ITEM_LP:
        LDA MC_ROW
        ASL A
        ASL A
        ASL A
        ASL A
        SEC
        SBC MC_ROW
        CLC
        ADC #21
        STA MC_Y_LO
        LDA #0
        STA MC_Y_HI

        LDA MC_ROW
        CMP MENU_ITEM
        BNE DPM_NOT_SEL

        LDA #136
        STA ZP_TMP
        LDA #13
        STA ZP_TMP+1
        LDA #$00
        STA MC_COLOR
        LDY MC_Y_LO
        DEY
        DEY
        LDA #4
        JSR GPU_WIN_RECT
        INC MC_Y_LO
        INC MC_Y_LO

        LDA #$FC
        STA MC_COLOR
        BNE DPM_DRAW_TXT

DPM_NOT_SEL:
        LDA #$FF
        STA MC_COLOR

DPM_DRAW_TXT:
        LDX MENU_IDX
        CLC
        LDA MENU_WIN_X_LO,X
        ADC #8
        STA MC_X_LO
        LDA MENU_WIN_X_HI,X
        ADC #0
        STA MC_X_HI

        JSR DRAW_STR

DPM_NEXT_ITEM:
        INC MC_ROW
        LDA MC_ROW
        CMP #5
        BCC DPM_ITEM_LP
        RTS

; Input: A = X-offset op MENU_WIN_X, Y = Y_LO, ZP_TMP = W, ZP_TMP+1 = H, MC_COLOR = Kleur
GPU_WIN_RECT:
        LDX MENU_IDX
        CLC
        ADC MENU_WIN_X_LO,X
        STA MC_X_LO
        LDA MENU_WIN_X_HI,X
        ADC #0
        STA MC_X_HI
        STY MC_Y_LO
        LDA #0
        STA MC_Y_HI
        TAY
        LDA ZP_TMP
        LDX ZP_TMP+1
; Universele GPU_RECT: MC_X_LO/HI, MC_Y_LO/HI, A=W_LO, Y=W_HI, X=H_LO, MC_COLOR
GPU_RECT:
        PHA
        LDA #2
        JSR GPU_CMD_XY
        PLA
        STA IO_GPU
        STY IO_GPU
        STX IO_GPU
        LDA #0
        STA IO_GPU
        LDA MC_COLOR
        STA IO_GPU
        RTS

GPU_CMD_XY:
        STA IO_GPU
        LDA MC_X_LO
        STA IO_GPU
        LDA MC_X_HI
        STA IO_GPU
        LDA MC_Y_LO
        STA IO_GPU
        LDA MC_Y_HI
        STA IO_GPU
        RTS

; ============================================================================
; DRAW_ONE_PANE: Tekent Paneel CUR_PANE (0 = Links op X=6, 1 = Rechts op X=326)
; ============================================================================
DRAW_ONE_PANE:
        LDX CUR_PANE
        LDA SEL_L,X
        STA MC_SEL
        LDA #0
        STA FILE_CNT
        STA MC_Y_HI

        CPX ACTIVE_PANE
        BNE DOP_HDR_TXT
        LDA PANE_HDR_RECT_X_LO,X
        STA MC_X_LO
        LDA PANE_HDR_RECT_X_HI,X
        STA MC_X_HI
        LDA #20
        STA MC_Y_LO
        LDA #$FC
        STA MC_COLOR
        LDA #224
        LDY #0
        LDX #12
        JSR GPU_RECT

DOP_HDR_TXT:
        LDX CUR_PANE
        LDA PANE_HDR_TXT_X_LO,X
        STA MC_X_LO
        LDA PANE_HDR_TXT_X_HI,X
        STA MC_X_HI
        LDA #22
        STA MC_Y_LO
        LDA #$FC
        CPX ACTIVE_PANE
        BNE DOP_HDR_COL
        LDA #$00
DOP_HDR_COL:
        STA MC_COLOR
        LDA #<STR_DRV_HDR
        LDY #>STR_DRV_HDR
        JSR DRAW_STR_AY
        LDX CUR_PANE
        LDA DRV_L,X
        JSR DRAW_DEC2
        LDA #' '
        JSR DRAW_CHAR_ADV
        LDA #'>'
        JSR DRAW_CHAR_ADV

        LDX CUR_PANE
        LDA PANE_TXT_X_LO,X
        STA MC_X_LO
        LDA PANE_TXT_X_HI,X
        STA MC_X_HI
        LDA #35
        STA MC_Y_LO
        LDA #$FC
        STA MC_COLOR
        LDA #<STR_COL_HDR
        LDY #>STR_COL_HDR
        JSR DRAW_STR_AY

        LDA #0
        STA MC_ROW
DOP_ROW_LP:
        LDA MC_ROW
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC MC_ROW
        ADC #50
        STA MC_Y_LO
        LDA #0
        ADC #0
        STA MC_Y_HI

        LDA MC_ROW
        CMP MC_SEL
        BNE DOP_NOT_SEL

        LDX CUR_PANE
        LDA PANE_BAR_X_LO,X
        STA MC_X_LO
        LDA PANE_BAR_X_HI,X
        STA MC_X_HI
        LDA #$49
        CPX ACTIVE_PANE
        BNE DOP_BAR_COL
        LDA #$1F
DOP_BAR_COL:
        STA MC_COLOR
        LDA #$2C
        LDY #$01
        LDX #11
        JSR GPU_RECT

        LDX CUR_PANE
        LDA #$FC
        CPX ACTIVE_PANE
        BNE DOP_SEL_TCOL
        LDA #$00
DOP_SEL_TCOL:
        STA MC_COLOR
        JMP DOP_DRAW_ROW

DOP_NOT_SEL:
        LDA #$FF
        STA MC_COLOR

DOP_DRAW_ROW:
        LDX CUR_PANE
        LDA PANE_TXT_X_LO,X
        STA MC_X_LO
        LDA PANE_TXT_X_HI,X
        STA MC_X_HI

        LDA MC_ROW
        JSR DRAW_DEC2
        LDA #' '
        JSR DRAW_CHAR_ADV

        LDX CUR_PANE
        LDA MC_ROW
        JSR GET_PANE_SLOT_PTR
        JSR CHECK_MAGIC_TMP
        BNE DOP_ROW_EMPTY

        INC FILE_CNT

        LDY #4
DOP_NAME_LP:
        LDA (ZP_TMP),Y
        BEQ DOP_NAME_PAD
        JSR DRAW_CHAR_ADV
        INY
        CPY #16
        BCC DOP_NAME_LP
        BCS DOP_TYPE
DOP_NAME_PAD:
        LDA #' '
        JSR DRAW_CHAR_ADV
        INY
        CPY #16
        BCC DOP_NAME_PAD

DOP_TYPE:
        LDY #22
        LDA (ZP_TMP),Y
        CMP #'D'
        BEQ DOP_IS_DIR
        CMP #'B'
        BEQ DOP_IS_ASM
        LDA #<STR_BAS_TYPE
        LDY #>STR_BAS_TYPE
        JSR DRAW_STR_AY
        JMP DOP_SIZE

DOP_IS_DIR:
        LDA #<STR_DIR_TYPE
        LDY #>STR_DIR_TYPE
        JSR DRAW_STR_AY
        JMP DOP_ROW_NEXT

DOP_IS_ASM:
        JSR DRAW_BIN_TYPE
        LDY #24
        LDA (ZP_TMP),Y
        JSR DRAW_HEX8
        LDY #23
        LDA (ZP_TMP),Y
        JSR DRAW_HEX8

DOP_SIZE:
        LDA #' '
        JSR DRAW_CHAR_ADV
        LDA #'$'
        JSR DRAW_CHAR_ADV
        LDY #21
        LDA (ZP_TMP),Y
        JSR DRAW_HEX8
        LDY #20
        LDA (ZP_TMP),Y
        JSR DRAW_HEX8
        JMP DOP_ROW_NEXT

DOP_ROW_EMPTY:
        LDA MC_ROW
        CMP MC_SEL
        BEQ DOP_EMP_COL
        LDA #$5B
        STA MC_COLOR
DOP_EMP_COL:
        LDA #<STR_EMPTY
        LDY #>STR_EMPTY
        JSR DRAW_STR_AY

DOP_ROW_NEXT:
        INC MC_ROW
        LDA MC_ROW
        CMP #15
        BCS DOP_FOOTER
        JMP DOP_ROW_LP

DOP_FOOTER:
        LDA CUR_PANE
        BNE DOP_RTS
        LDA #16
        STA MC_X_LO
        LDA #0
        STA MC_X_HI
        LDA #$3C
        STA MC_Y_LO
        LDA #$01
        STA MC_Y_HI
        LDA #$1F
        STA MC_COLOR
        LDA #<STR_FOOT_L
        LDY #>STR_FOOT_L
        JSR DRAW_STR_AY
        LDA FILE_CNT
        JSR DRAW_DEC2
        LDA #<STR_FOOT_MID
        LDY #>STR_FOOT_MID
        JMP DRAW_STR_AY
DOP_RTS:
        RTS

; ============================================================================
; Hulproutines
; ============================================================================
GET_PANE_SLOT_PTR:
        STA ZP_TMP
        LDA #0
        STA ZP_TMP+1
        LDY #5
GPSP_LP:
        ASL ZP_TMP
        ROL ZP_TMP+1
        DEY
        BNE GPSP_LP
        LDA #>DIR_L_BUF
        CPX #0
        BEQ GPSP_ADD
        LDA #>DIR_R_BUF
GPSP_ADD:
        CLC
        ADC ZP_TMP+1
        STA ZP_TMP+1
        RTS

CHECK_MAGIC_TMP:
        LDY #0
        LDA (ZP_TMP),Y
        CMP #'B'
        BNE CMT_NO
        INY
        LDA (ZP_TMP),Y
        CMP #'B'
        BNE CMT_NO
        INY
        LDA (ZP_TMP),Y
        CMP #'C'
        BNE CMT_NO
        INY
        LDA #'!'
        STA (ZP_TMP),Y
        CMP #'!'
CMT_NO:
        RTS

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
        STA MC_PTR_LO
        STY MC_PTR_HI
DRAW_STR:
        LDY #0
        LDA (MC_PTR_LO),Y
        INC MC_PTR_LO
        BNE DS_CHK
        INC MC_PTR_HI
DS_CHK:
        CMP #0
        BEQ DS_DONE
        JSR DRAW_CHAR_ADV
        JMP DRAW_STR
DS_DONE:
        RTS

DRAW_CHAR_ADV:
        PHA
        LDA #8
        JSR GPU_CMD_XY
        PLA
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA MC_COLOR
        STA IO_GPU

        CLC
        LDA MC_X_LO
        ADC #8
        STA MC_X_LO
        BCC DCA_RTS
        INC MC_X_HI
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

DRAW_BIN_TYPE:
        LDY #24
        LDA (ZP_TMP),Y
        LDX #<STR_IMG_TYPE
        CMP #$50
        BEQ DBT_GO
        LDX #<STR_TXT_TYPE
        CMP #$60
        BEQ DBT_GO
        LDX #<STR_ASM_TYPE
DBT_GO:
        TXA
        LDY #>STR_ASM_TYPE
        JMP DRAW_STR_AY

; ============================================================================
; Sneltoets- & Menu-Actietabellen
; ============================================================================
KEY_TBL:
        .BYTE '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'
        .BYTE 'Q', 'T', 'F', 'N', 'C', 'M', 'K', 'X', 'L', 'O', 'R', 'W', 'S', 'A', 'D'
KEY_TBL_END:

KEY_ACT_LO:
        .BYTE <TOGGLE_MENU_BAR, <NEXT_ACTIVE_DRIVE, <EXEC_SELECTED, <DO_RENAME_FILE, <DO_COPY_FILE
        .BYTE <DO_MOVE_FILE, <DO_MKDIR, <DO_DELETE_FILE, <TOGGLE_BG, <QUIT_MC
        .BYTE <QUIT_MC, <TOGGLE_BG, <NEXT_ACTIVE_DRIVE, <DO_RENAME_FILE, <DO_COPY_FILE
        .BYTE <DO_MOVE_FILE, <DO_MKDIR, <DO_DELETE_FILE, <OPEN_MENU_L, <OPEN_MENU_O, <OPEN_MENU_R
        .BYTE <MOVE_UP, <MOVE_DOWN, <MOVE_LEFT_ACT, <MOVE_RIGHT_ACT

KEY_ACT_HI:
        .BYTE >TOGGLE_MENU_BAR, >NEXT_ACTIVE_DRIVE, >EXEC_SELECTED, >DO_RENAME_FILE, >DO_COPY_FILE
        .BYTE >DO_MOVE_FILE, >DO_MKDIR, >DO_DELETE_FILE, >TOGGLE_BG, >QUIT_MC
        .BYTE >QUIT_MC, >TOGGLE_BG, >NEXT_ACTIVE_DRIVE, >DO_RENAME_FILE, >DO_COPY_FILE
        .BYTE >DO_MOVE_FILE, >DO_MKDIR, >DO_DELETE_FILE, >OPEN_MENU_L, >OPEN_MENU_O, >OPEN_MENU_R
        .BYTE >MOVE_UP, >MOVE_DOWN, >MOVE_LEFT_ACT, >MOVE_RIGHT_ACT

MENU_HOTKEYS:
        .BYTE 'L', 'F', 'C', 'O', 'R'

MENU_ACT_LO:
        .BYTE <EXEC_SELECTED, <DO_RENAME_FILE, <DO_COPY_FILE, <DO_MOVE_FILE, <DO_MKDIR
        .BYTE <DO_DELETE_FILE, <TOGGLE_PANE, <SWAP_DRIVES, <NEXT_ACTIVE_DRIVE, <QUIT_MC
        .BYTE <EMI_BG_BLUE, <SET_BG_TRANS, <TOGGLE_BG, <EMI_FOC_L, <EMI_FOC_R

MENU_ACT_HI:
        .BYTE >EXEC_SELECTED, >DO_RENAME_FILE, >DO_COPY_FILE, >DO_MOVE_FILE, >DO_MKDIR
        .BYTE >DO_DELETE_FILE, >TOGGLE_PANE, >SWAP_DRIVES, >NEXT_ACTIVE_DRIVE, >QUIT_MC
        .BYTE >EMI_BG_BLUE, >SET_BG_TRANS, >TOGGLE_BG, >EMI_FOC_L, >EMI_FOC_R

; ============================================================================
; Coördinaten-tabellen voor Linker/Rechter Paneel & 5 Pull-Down Menu's
; ============================================================================
PANE_HDR_RECT_X_LO: .BYTE 48,   <$0170
PANE_HDR_RECT_X_HI: .BYTE 0,    >$0170
PANE_HDR_TXT_X_LO:  .BYTE 68,   <$0184
PANE_HDR_TXT_X_HI:  .BYTE 0,    >$0184
PANE_BAR_X_LO:      .BYTE 10,   <$014A
PANE_BAR_X_HI:      .BYTE 0,    >$014A
PANE_TXT_X_LO:      .BYTE 16,   <$0150
PANE_TXT_X_HI:      .BYTE 0,    >$0150

MENU_BAR_X_LO:      .BYTE 6,    62,   118,  198,  <$0116
MENU_BAR_X_HI:      .BYTE 0,    0,    0,    0,    >$0116
MENU_BAR_W:         .BYTE 44,   44,   68,   68,   52

MENU_WIN_X_LO:      .BYTE 6,    56,   112,  188,  <$0108
MENU_WIN_X_HI:      .BYTE 0,    0,    0,    0,    >$0108

MENU_TITLE_LO:      .BYTE <STR_MT_L, <STR_MT_F, <STR_MT_C, <STR_MT_O, <STR_MT_R
MENU_TITLE_HI:      .BYTE >STR_MT_L, >STR_MT_F, >STR_MT_C, >STR_MT_O, >STR_MT_R

MENU_LIST_LO:       .BYTE <MENU_ITEMS_DRV, <MENU_ITEMS_F, <MENU_ITEMS_C, <MENU_ITEMS_O, <MENU_ITEMS_DRV
MENU_LIST_HI:       .BYTE >MENU_ITEMS_DRV, >MENU_ITEMS_F, >MENU_ITEMS_C, >MENU_ITEMS_O, >MENU_ITEMS_DRV

STR_MT_L:           .ASCIIZ "Left"
STR_MT_F:           .ASCIIZ "File"
STR_MT_C:           .ASCIIZ "Command"
STR_MT_O:           .ASCIIZ "Options"
STR_MT_R:           .ASCIIZ "Right"

MENU_ITEMS_DRV:
        .ASCIIZ "Drive D0"
        .ASCIIZ "Drive D1"
        .ASCIIZ "Drive D2"
        .ASCIIZ "Drive D3"
        .ASCIIZ "Verversen"

MENU_ITEMS_F:
        .ASCIIZ "Open/Run"
        .ASCIIZ "Hernoem"
        .ASCIIZ "Kopieer"
        .ASCIIZ "Verplaats"
        .ASCIIZ "Maak Map"

MENU_ITEMS_C:
        .ASCIIZ "Wissen"
        .ASCIIZ "Paneel"
        .ASCIIZ "Ruil L<>R"
        .ASCIIZ "Drive"
        .ASCIIZ "Einde"

MENU_ITEMS_O:
        .ASCIIZ "Blauw"
        .ASCIIZ "Transparant"
        .ASCIIZ "Wissel"
        .ASCIIZ "Focus L"
        .ASCIIZ "Focus R"

; ============================================================================
; GPU Streams: Dialoogvenster & Dual-Pane Kaders
; ============================================================================
DLG_STREAM:
        .BYTE 12, 1
        .BYTE 2, 188,0, 135,0, $08,$01, 64,0, $1F
        .BYTE 2, 190,0, 137,0, $04,$01, 60,0, $0B
        .BYTE 2, 204,0, 165,0, 232,0,   16,0, $00
DLG_STREAM_END:

UI_STREAM:
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 0
        .BYTE 2, 0,0, 0,0, $80,$02, 15,0, $1F

        .BYTE 3, 6,0, 18,0, $3A,$01, 18,0, $1F
        .BYTE 3, 6,0, $4E,$01, $3A,$01, $4E,$01, $1F
        .BYTE 3, 6,0, 18,0, 6,0, $4E,$01, $1F
        .BYTE 3, $3A,$01, 18,0, $3A,$01, $4E,$01, $1F
        .BYTE 3, 6,0, 46,0, $3A,$01, 46,0, $1F
        .BYTE 3, 6,0, $34,$01, $3A,$01, $34,$01, $1F

        .BYTE 3, $46,$01, 18,0, $7A,$02, 18,0, $1F
        .BYTE 3, $46,$01, $4E,$01, $7A,$02, $4E,$01, $1F
        .BYTE 3, $46,$01, 18,0, $46,$01, $4E,$01, $1F
        .BYTE 3, $7A,$02, 18,0, $7A,$02, $4E,$01, $1F
        .BYTE 3, $46,$01, 46,0, $7A,$02, 46,0, $1F
        .BYTE 3, $46,$01, $34,$01, $7A,$02, $34,$01, $1F

        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $1F
UI_STREAM_END:

STR_TOP_BAR:
        .ASCIIZ "Left   File   Command   Options   Right      MiniGPU MC 2.2 Dual"
STR_BOT_BAR:
        .ASCIIZ "1Menu  2Drv   3Run   4Ren   5Copy  6Move  7MkDir 8Del   9BgMod 0Quit"

STR_COL_HDR:
        .ASCIIZ "SL BESTANDSNAAM TYPE ADRES BYTES"
STR_DRV_HDR:
        .ASCIIZ "< SD DRV/MAP "
STR_BAS_TYPE:
        .ASCIIZ " BAS $0800"
STR_ASM_TYPE:
        .ASCIIZ " ASM $"
STR_IMG_TYPE:
        .ASCIIZ " IMG $"
STR_TXT_TYPE:
        .ASCIIZ " TXT $"
STR_DIR_TYPE:
        .ASCIIZ " <MAP>   --DIR--"
STR_EMPTY:
        .ASCIIZ "- leeg -"
STR_FOOT_L:
        .ASCIIZ "ITEMS:"
STR_FOOT_MID:
        .ASCIIZ "/15 | PAD:"

STR_MSG_BASE:
STR_DLG_REN:
        .ASCIIZ "HERNOEM (ENTER):"
STR_DLG_MD:
        .ASCIIZ "MAAK MAP (ENTER):"
STR_MSG_READY:
        .ASCIIZ "ALT:Menu 4:Ren 5:Cpy 7:MD"
STR_MSG_COPIED:
        .ASCIIZ "GEKOPIEERD!"
STR_MSG_MOVED:
        .ASCIIZ "VERPLAATST!"
STR_MSG_REN:
        .ASCIIZ "HERNOEMD!"
STR_MSG_MD:
        .ASCIIZ "MAP GEMAAKT!"
STR_MSG_DEL:
        .ASCIIZ "GEWIST!"
STR_MSG_EMPTY:
        .ASCIIZ "LEEG SLOT!"
STR_MSG_FULL:
        .ASCIIZ "MAP IS VOL!"
STR_MSG_DRV:
        .ASCIIZ "MAP/DRIVE OK"
STR_MSG_SWAP:
        .ASCIIZ "L<->R GERUILD"
STR_MSG_PROT:
        .ASCIIZ "BEVEILIGD!"
