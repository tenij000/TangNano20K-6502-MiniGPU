; ============================================================================
; FTP.asm - MiniGPU FTP & Web-Server 1.1 (6502 + W5500 RFC 959 FTP + HTTP :80)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, werkt naast MC op $9000).
;   - Volledige Dual-Protocol Server op W5500 (3 gelijktijdige hardware sockets):
;       * Socket 1 ($28): TCP Poort 21   (RFC 959 FTP Control: USER, PASS, SYST,
;         FEAT, PWD, CWD, TYPE, PASV, SIZE, LIST, NLST, RETR, STOR, DELE, QUIT)
;       * Socket 2 ($48): TCP Poort 2121 (FTP Data-kanaal voor Passive Mode PASV)
;       * Socket 3 ($68): TCP Poort 80   (HTTP Web-Server: open direct in je
;         webbrowser via http://192.168.178.201/ om D0/D1/R0/R1 te bekijken
;         en bestanden met één klik te downloaden!)
;   - Directe koppeling met MicroSD (SD-D0, SD-D1) & 4MB SDRAM-Disk (R0, R1)
;   - Grafisch 640x360 Split-Screen Live Dashboard (overscan-safe!)
; ============================================================================
        ORG $8000

IO_STATUS       = $A000
IO_TERM         = $A001
IO_TIMER        = $A003
IO_JOY          = $A004
IO_MODE         = $A006
IO_GPU          = $A020
IO_NET_DATA     = $A030
IO_NET_CTRL     = $A031

ZP_DST          = $1C
DISK_DRIVE      = $0490
DISK_FORCE_RAM  = $0491
DISK_MEDIA      = $0492
DISK_SLOT       = $0493
DISK_SEC_LO     = $0496
DISK_SEC_HI     = $0497

ROM_SILENCE     = $E8DC
ROM_SD_INIT     = $E96A
ROM_READ_SEC    = $EA67
ROM_WRITE_SEC   = $EADA
SPI_BRAM_STUB   = $02F0

ZP_PTR_LO       = $60
ZP_PTR_HI       = $61
ZP_SRC_LO       = $62
ZP_SRC_HI       = $63
ZP_SLOT_LO      = $64
ZP_SLOT_HI      = $65
ZP_X_LO         = $66
ZP_X_HI         = $67
ZP_Y_LO         = $68
ZP_Y_HI         = $69
ZP_COLOR        = $6A

SOCK_BASE       = $6B           ; $28 = S1 (:21), $48 = S2 (:2121), $68 = S3 (:80)
SX_PTR_LO       = $6C
SX_PTR_HI       = $6D
SX_LEN_LO       = $6E
SX_LEN_HI       = $6F

W5500_VER       = $70
W5500_PHY       = $71
S1_GREETED      = $72
ROW_Y_SAV       = $73           ; Rij Y-positie tijdens DRAW_SCREEN (veilig voor DEC16!)
CMD_LEN         = $74
ARG_IDX         = $75
CUR_SLOT        = $76
FILE_SIZE_LO    = $77
FILE_SIZE_HI    = $78
LOAD_HI_TMP     = $79
FILE_TYPE_TMP   = $7A
SEC_CNT         = $7B
NEED_REDRAW     = $7C
POLL_DIV        = $7D
TMP_A           = $7E
TMP_B           = $7F

DEC_LO          = $86
DEC_HI          = $87
S3_GREETED      = $80
CTRL_SOCK       = $81

FILE_BUF        = $3000         ; 8 KB Bestandsoverdracht buffer ($3000..$4FFF)
DIR_BUF         = $5000         ; 512 B Actieve Directory Sector ($5000..$51FF)
CMD_BUF         = $5200         ; Ontvangen FTP/HTTP-commandoregel ($5200..$527F)
FNAME_BUF       = $5280         ; Geformatteerde 11-teken bestandsnaam ($5280..$528F)
TX_LINE_BUF     = $5300         ; Tijdelijke opmaakbuffer voor LIST/PASV/HTML ($5300..$53FF)
LOG_BUF         = $5400         ; 8 regels x 32 B Live Server Log ($5400..$55FF)

XFER_CNT        = $5604
LAST_STATUS     = $5605

; ============================================================================
; Start & Hoofdlus
; ============================================================================
START:
        JSR ROM_SILENCE
        LDA #0
        STA IO_MODE
        STA ZP_Y_HI
        STA XFER_CNT
        STA CLI_IP0
        STA DISK_DRIVE
        STA DISK_FORCE_RAM
        TAX
CLG_L:  STA LOG_BUF,X
        INX
        BNE CLG_L
        LDA #12
        STA IO_TERM

        JSR W5500_INIT_HW
        JSR S1_LISTEN_21
        JSR S3_LISTEN_80
        JSR LOAD_CUR_DIR

        LDA #<STR_LOG_BOOT
        LDY #>STR_LOG_BOOT
        JSR ADD_LOG_STR

MAIN_LOOP:
        JSR DRAW_SCREEN
        LDA #0
        STA NEED_REDRAW

WAIT_LOOP:
        JSR DELAY_10MS

        JSR POLL_FTP_SERVER
        JSR POLL_HTTP_SERVER
        LDA NEED_REDRAW
        BNE MAIN_LOOP

        INC POLL_DIV
        LDA POLL_DIV
        AND #$1F
        BNE WL_KEY
        JSR W5500_PROBE_HW
        JSR DRAW_LED_ONLY

WL_KEY: LDA IO_STATUS
        AND #1
        BEQ WAIT_LOOP
        LDA IO_JOY
        LDA IO_TERM
        LDX #0
        STX IO_MODE

        CMP #'1'
        BCC WL_K2
        CMP #'5'
        BCS WL_K2
        SBC #'1'
        TAY
        AND #1
        STA DISK_DRIVE
        TYA
        AND #2
        BEQ KEY_SET_RAM
        LDX #$80
KEY_SET_RAM:
        STX DISK_FORCE_RAM
KEY_RELOAD:
        JSR LOAD_CUR_DIR
        JMP MAIN_LOOP

WL_K2:  ORA #$20
        CMP #'q'
        BEQ EXIT_TO_BASIC
        CMP #$3B                ; ESC ($1B | $20)
        BEQ EXIT_TO_BASIC
        CMP #'r'
        BEQ KEY_RELOAD
        CMP #'k'
        BNE WAIT_LOOP
        JSR S1_DISCON_RELISTEN
        JSR S3_LISTEN_80
        JMP MAIN_LOOP

EXIT_TO_BASIC:
        LDA #$68
EX_LP:  STA SOCK_BASE
        JSR SX_CLOSE
        LDA SOCK_BASE
        SEC
        SBC #$20
        CMP #$20
        BCS EX_LP
        LDX #GS_EXIT - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #1
        STA IO_MODE
        LDA #12
        STA IO_TERM
        RTS

; ============================================================================
; Socket 1 (TCP Poort 21 FTP) & Socket 3 (TCP Poort 80 HTTP + FTP) Luister-setup
; ============================================================================
S3_LISTEN_80:
        LDA #0
        STA S3_GREETED
        LDA #$68
        LDX #80
        BNE SX_LISTEN_0

S1_LISTEN_21:
        LDA #0
        STA S1_GREETED
        STA LAST_STATUS
        LDA #$28
        LDX #21
SX_LISTEN_0:
        LDY #0
SX_LISTEN_PORT:
        STA SOCK_BASE
        STX SX_PTR_LO
        STY SX_PTR_HI
        JSR SX_CLOSE
        LDA #$01                ; TCP Mode
        LDX #$00
        JSR SX_WR
        LDA #$04                ; Sn_PORT0
        LDY #$01                ; OPEN
        JSR SX_PTR_CMD
        LDA #$02                ; LISTEN
        JMP SX_CMD

S1_DISCON_RELISTEN:
        LDA #$28
        STA SOCK_BASE
        JSR DATA_CLOSE_SOCK
        INC NEED_REDRAW
        JMP S1_LISTEN_21

; ============================================================================
; FTP & HTTP Control Server State Machine (Poort 21 op S1 & Poort 80 op S3)
; ============================================================================
POLL_FTP_SERVER:
        LDA #$28
        STA SOCK_BASE
        LDA #$03
        JSR SX_RD
        CMP #$17
        BEQ PFS_EST
        CMP #$1C
        BEQ S1_DISCON_RELISTEN
        CMP #$00
        BEQ S1_LISTEN_21
        RTS

PFS_EST:
        LDA S1_GREETED
        BNE PFS_RX
        INC S1_GREETED
PFS_GREET:
        LDY SOCK_BASE
        STY CTRL_SOCK
        JSR READ_CLI_IP_Y
        LDA #<STR_LOG_CONN
        LDY #>STR_LOG_CONN
        JSR ADD_LOG_STR
        LDA #STR_220 - FTP_REPS
        JMP S1_SEND_REP_A

PFS_RX: JSR SX_GET_RX_LEN
        BEQ PFS_RTS
PFS_HAVE_RX:
        LDA SX_LEN_HI
        BNE PFS_CL
        LDA SX_LEN_LO
        CMP #62
        BCC PFS_GO
PFS_CL: LDA #62
PFS_GO: STA TMP_B

        JSR SX_RX_PTR_HDR
        LDY #0
PFS_LP: LDA #0
        JSR SPI_BRAM_STUB
        CMP #$0D
        BEQ PFS_EOL
        CMP #$0A
        BEQ PFS_EOL
        STA CMD_BUF,Y
        INY
        DEC TMP_B
        BNE PFS_LP
PFS_EOL:
        LDA #0
        STA CMD_BUF,Y
        STY TMP_B
        JSR W5500_CS_HI
        LDA SX_PTR_LO
        CLC
        ADC SX_LEN_LO
        STA SX_PTR_LO
        LDA SX_PTR_HI
        ADC SX_LEN_HI
        STA SX_PTR_HI
        LDA #$28
        LDY #$40
        JSR SX_PTR_CMD
        LDA TMP_B
        BEQ PFS_RTS
        LDY SOCK_BASE
        STY CTRL_SOCK
        JMP HANDLE_FTP_CMD
PFS_RTS:
        RTS

READ_CLI_IP_Y:
        LDA #$0C
        JSR W5500_HDR_0
        LDX #0
RCI_LP: LDA #0
        JSR SPI_BRAM_STUB
        STA CLI_IP0,X
        INX
        CPX #4
        BCC RCI_LP
        LDA #1
        STA LAST_STATUS
        STA NEED_REDRAW
        JMP W5500_CS_HI

; ============================================================================
; HTTP Web-Server + FTP Fallback op Socket 3 (TCP Poort 80)
; ============================================================================
POLL_HTTP_SERVER:
        LDA #$68
        STA SOCK_BASE
        LDA #$03
        JSR SX_RD
        CMP #$17
        BEQ PHS_EST
        CMP #$1C
        BEQ S3_CLOSE_RELISTEN
        CMP #$00
        BEQ S3_LISTEN_80
        RTS

PHS_EST:
        JSR SX_GET_RX_LEN
        BNE PHS_RX
        LDA S3_GREETED
        BMI PFS_RTS
        INC S3_GREETED
        LDA S3_GREETED
        CMP #15
        BEQ PFS_GREET
        CMP #250
        BEQ S3_CLOSE_RELISTEN
        RTS
PHS_RX: LDA #$80
        STA S3_GREETED
        BNE PFS_HAVE_RX

DO_HTTP_GET:
        LDX #4
PHS_SP: LDA CMD_BUF,X
        BEQ PHS_S0
        CMP #' '
        BEQ PHS_S0
        INX
        BNE PHS_SP
PHS_S0: LDA #0
        STA CMD_BUF,X

        ; Negeer automatische "/favicon.ico" verzoeken van webbrowsers
        LDA CMD_BUF+5
        ORA #$20
        CMP #'f'
        BNE PHS_LOG
        LDA CMD_BUF+6
        ORA #$20
        CMP #'a'
        BEQ S3_CLOSE_RELISTEN

PHS_LOG:
        LDA #<CMD_BUF
        LDY #>CMD_BUF
        JSR ADD_LOG_STR

        LDY #4
        STY ARG_IDX
        JSR CHECK_PATH_DRV
        LDY ARG_IDX
        LDA CMD_BUF,Y
        CMP #'/'
        BNE PHS_C1
        INY
        STY ARG_IDX
PHS_C1: LDA CMD_BUF,Y
        BNE PHS_FN
        CPY #5
        BNE PHS_DIR
        LDX #5
PHS_IX: LDA STR_INDEX,X
        STA FNAME_BUF,X
        DEX
        BPL PHS_IX
        JSR LOAD_CUR_DIR
        JSR PAF_SR
        BCS PHS_SRV
        BCC PHS_D1

PHS_FN: JSR PARSE_AND_FIND_FILE
        BCC PHS_DIR
PHS_SRV:
        JSR READ_CUR_SLOT_FILE
        INC XFER_CNT
        LDA FILE_BUF
        CMP #'<'
        BEQ PHS_BN
        LDY #24
        LDA (ZP_SLOT_LO),Y
        CMP #$60
        BEQ PHS_TX
        CMP #$7A
        BNE PHS_BN
PHS_TX: JSR SEND_HTTP_TOP
        JSR SX_SEND_FILE_BUF
        JMP PHS_ET

PHS_BN: JSR SEND_HTTP_OK
        JSR SX_SEND_FILE_BUF
        JMP S3_CLOSE_RELISTEN

PHS_DIR:
        JSR LOAD_CUR_DIR
PHS_D1: JSR SEND_HTTP_TOP
        JSR SEND_DIR_LIST_SOCK
PHS_ET: LDA #<STR_H_END
        LDY #>STR_H_END
        JSR S1_SEND_STR

S3_CLOSE_RELISTEN:
        LDA #$68
        STA SOCK_BASE
        JSR DATA_CLOSE_SOCK
        JMP S3_LISTEN_80

SEND_HTTP_TOP:
        JSR GET_DRV_CHARS
        STA STR_H_DRV
        STX STR_H_DRV+1
        JSR SEND_HTTP_OK
        LDA #<STR_HTTP_HTML
        LDY #>STR_HTTP_HTML
        JMP S1_SEND_STR

SEND_HTTP_OK:
        LDA #<STR_HTTP_BIN
        LDY #>STR_HTTP_BIN
        JMP S1_SEND_STR

; ============================================================================
; FTP & HTTP Commando-Parser & Afhandeling (RFC 959 + HTTP/1.0 GET)
; ============================================================================
HANDLE_FTP_CMD:
        LDY CTRL_SOCK
        JSR READ_CLI_IP_Y
        LDA CMD_BUF
        CMP #'G'
        BNE HFC_FTP
        LDA CMD_BUF+1
        CMP #'E'
        BEQ DO_HTTP_GET

HFC_FTP:
        LDA #<CMD_BUF
        LDY #>CMD_BUF
        JSR ADD_LOG_STR

        LDX #0
HFC_UP: LDA CMD_BUF,X
        BEQ HFC_A0
        CMP #' '
        BEQ HFC_SP
        CMP #'a'
        BCC HFC_U1
        CMP #'z'+1
        BCS HFC_U1
        AND #$DF
        STA CMD_BUF,X
HFC_U1: INX
        BNE HFC_UP
HFC_SP: LDA #0
        STA CMD_BUF,X
        INX
HFC_SK: LDA CMD_BUF,X
        CMP #' '
        BNE HFC_A0
        INX
        BNE HFC_SK
HFC_A0: STX ARG_IDX

        LDA CMD_BUF
        LDX CMD_BUF+1
        CMP #'U'                ; USER
        BNE FC_1
        LDA #STR_331 - FTP_REPS
        BNE S1_SEND_REP_A
FC_1:   CMP #'P'
        BNE FC_2
        CPX #'A'
        BNE FC_P1
        LDA CMD_BUF+3
        CMP #'V'
        BEQ DO_FTP_PASV
        LDA #STR_230 - FTP_REPS
        BNE S1_SEND_REP_A
FC_P1:  CPX #'W'
        BEQ DO_FTP_PWD
        BNE FTP_SEND_200

FC_2:   CMP #'S'
        BNE FC_3
        CPX #'Y'
        BNE FC_S1
        LDA #STR_215 - FTP_REPS
        BNE S1_SEND_REP_A
FC_S1:  CPX #'I'
        BNE FC_S2
        LDA CMD_BUF+2
        CMP #'Z'
        BEQ DO_FTP_SIZE
        BNE FTP_SEND_200
FC_S2:  CPX #'T'
        BNE FTP_SEND_200
        LDA CMD_BUF+2
        CMP #'O'
        BNE FTP_SEND_200
        JMP DO_FTP_STOR

FC_3:   CMP #'F'
        BNE FC_4
        LDA #STR_211 - FTP_REPS
        BNE S1_SEND_REP_A

FC_4:   CMP #'C'
        BEQ DO_FTP_CWD
        CMP #'L'
        BEQ DO_FTP_LIST
        CMP #'N'
        BEQ DO_FTP_LIST

FC_7:   CMP #'R'
        BNE FC_8
        CPX #'E'
        BNE FTP_SEND_200
        JMP DO_FTP_RETR

FC_8:   CMP #'D'
        BNE FC_9
        JMP DO_FTP_DELE

FC_9:   CMP #'Q'
        BNE FC_10
        LDA #STR_221 - FTP_REPS
        JSR S1_SEND_REP_A
        LDA CTRL_SOCK
        CMP #$68
        BEQ S3_CLOSE_RELISTEN
        JMP S1_DISCON_RELISTEN

FC_10:  CMP #'X'
        BNE FTP_SEND_200
        CPX #'P'
        BEQ DO_FTP_PWD
        BNE DO_FTP_CWD

FTP_SEND_200:
        LDA #STR_200 - FTP_REPS
S1_SEND_REP_A:
        CLC
        ADC #<FTP_REPS
        LDY #>FTP_REPS
        BCC S1_SEND_STR_J
        INY
S1_SEND_STR_J:
        JMP S1_SEND_STR

DO_FTP_PWD:
        JSR GET_DRV_CHARS
        STA STR_257_DRV
        STX STR_257_DRV+1
        LDA #STR_257 - FTP_REPS
        BNE S1_SEND_REP_A

GET_DRV_CHARS:
        LDA #'D'
        LDX DISK_FORCE_RAM
        BEQ GDC_1
        LDA #'R'
GDC_1:  PHA
        LDA DISK_DRIVE
        AND #3
        CLC
        ADC #'0'
        TAX
        PLA
        RTS

DO_FTP_CWD:
        LDY ARG_IDX
        JSR CHECK_PATH_DRV
FTP_SEND_250:
        LDA #STR_250 - FTP_REPS
        BNE S1_SEND_REP_A

CHECK_PATH_DRV:
        LDA CMD_BUF,Y
        BEQ CPD_RTS
        CMP #'/'
        BNE CPD_1
        INY
        LDA CMD_BUF,Y
        BEQ CPD_RTS
CPD_1:  AND #$DF
        LDX #$00
        CMP #'D'
        BEQ CPD_2
        CMP #'S'
        BEQ CPD_2
        LDX #$80
        CMP #'R'
        BNE CPD_RTS
CPD_2:  INY
        LDA CMD_BUF,Y
        SEC
        SBC #'0'
        CMP #4
        BCS CPD_RTS
        STA TMP_A
        INY
        LDA CMD_BUF,Y
        BEQ CPD_3
        CMP #'/'
        BNE CPD_RTS
        INY
CPD_3:  STY ARG_IDX
        LDA TMP_A
        STA DISK_DRIVE
        STX DISK_FORCE_RAM
        JMP LOAD_CUR_DIR
CPD_RTS:
        RTS

; --- PASV: Open Socket 2 op TCP Poort 2121 (8*256 + 73) ---
DO_FTP_PASV:
        LDA #$48
        LDX #73
        LDY #8
        JSR SX_LISTEN_PORT

        LDY #0
        LDX #SP_227_PFX - STR_POOL
        JSR APPEND_POOL_X
        LDX #0
PASV_IL:
        STX TMP_A
        LDA W5500_INIT_TBL+18,X
        JSR APPEND_DEC_BYTE
        LDA #','
        STA TX_LINE_BUF,Y
        INY
        LDX TMP_A
        INX
        CPX #4
        BCC PASV_IL
        LDX #SP_227_SFX - STR_POOL
        JSR APPEND_POOL_X
        JMP S1_SEND_TX_LINE

; --- SIZE <bestandsnaam> ---
DO_FTP_SIZE:
        JSR PARSE_AND_FIND_FILE
        BCC SIZE_NF
        LDY #0
        LDX #SP_213_PFX - STR_POOL
        JSR APPEND_POOL_X
        JSR APPEND_SLOT_SIZE_Y
        LDA #0
        STA TX_LINE_BUF,Y
S1_SEND_TX_LINE:
        LDA #<TX_LINE_BUF
        LDY #>TX_LINE_BUF
        JMP S1_SEND_STR
SIZE_NF:
        LDA #STR_550 - FTP_REPS
        JMP S1_SEND_REP_A

; --- DELE <bestandsnaam> ---
DO_FTP_DELE:
        JSR PARSE_AND_FIND_FILE
        BCC SIZE_NF
        JSR CLEAR_CUR_SLOT
        JSR SAVE_CUR_DIR
        JMP FTP_SEND_250

; --- LIST / NLST (deelt de 15-slot opmaaklus met HTTP Poort 80!) ---
DO_FTP_LIST:
        LDY ARG_IDX
        LDA CMD_BUF,Y
        BEQ DFL_1
        CMP #'-'
        BEQ DFL_1
        JSR CHECK_PATH_DRV
DFL_1:  JSR LOAD_CUR_DIR
        JSR SEND_150_WAIT_DATA
        BCC DFL_ERR
        JSR SEND_DIR_LIST_SOCK
        JMP CLOSE_DATA_226
DFL_ERR:
        LDA #STR_425 - FTP_REPS
        JMP S1_SEND_REP_A

SEND_150_WAIT_DATA:
        LDA #STR_150 - FTP_REPS
        JSR S1_SEND_REP_A
        JMP DATA_OPEN_WAIT

CLOSE_DATA_226:
        JSR DATA_CLOSE
        LDA #STR_226 - FTP_REPS
        JMP S1_SEND_REP_A

; Stuur 15 slots naar huidige SOCK_BASE ($48 = FTP LIST, $68 = HTTP Web met <a href>)
SEND_DIR_LIST_SOCK:
        LDA #0
        STA CUR_SLOT
DFL_LP: LDA CUR_SLOT
        JSR GET_SLOT_PTR
        JSR CHECK_SLOT_USED
        BNE DFL_NX

        LDY #0
        LDX #SP_LIST_PFX - STR_POOL
        JSR APPEND_POOL_X
        JSR APPEND_SLOT_SIZE_Y
        LDX #SP_LIST_DATE - STR_POOL
        JSR APPEND_POOL_X

        LDA SOCK_BASE
        CMP #$48
        BEQ DFL_NM
        LDX #SP_H_A1 - STR_POOL
        JSR APPEND_POOL_X
        JSR GET_DRV_CHARS
        STA TX_LINE_BUF,Y
        INY
        TXA
        STA TX_LINE_BUF,Y
        INY
        LDA #'/'
        STA TX_LINE_BUF,Y
        INY
        JSR COPY_SLOT_NAME_Y
        LDA #'>'
        STA TX_LINE_BUF,Y
        INY
DFL_NM: JSR COPY_SLOT_NAME_Y
        LDA SOCK_BASE
        CMP #$48
        BEQ DFL_NE
        LDX #SP_H_A2 - STR_POOL
        JSR APPEND_POOL_X
DFL_NE: LDA #0
        STA TX_LINE_BUF,Y
        LDX SOCK_BASE
        LDA #<TX_LINE_BUF
        LDY #>TX_LINE_BUF
        JSR SX_SEND_STR

DFL_NX: INC CUR_SLOT
        LDA CUR_SLOT
        CMP #15
        BCC DFL_LP
        RTS

APPEND_POOL_X:
APX_L:  LDA STR_POOL,X
        BEQ APX_R
        STA TX_LINE_BUF,Y
        INY
        INX
        BNE APX_L
        STA TX_LINE_BUF,Y
APX_R:  RTS

COPY_SLOT_NAME_Y:
        STY TMP_A
        LDY #4
CSN_L:  LDA (ZP_SLOT_LO),Y
        BEQ CSN_D
        LDX TMP_A
        STA TX_LINE_BUF,X
        INC TMP_A
        INY
        CPY #16
        BCC CSN_L
CSN_D:  LDY TMP_A
        RTS

APPEND_SLOT_SIZE_Y:
        STY TMP_A
        LDY #20
        LDA (ZP_SLOT_LO),Y
        STA DEC_LO
        INY
        LDA (ZP_SLOT_LO),Y
        STA DEC_HI
        LDY TMP_A
        JMP APPEND_DEC16

; --- RETR <bestandsnaam>: Stuur bestand vanaf SD/RAM-Disk naar PC! ---
DO_FTP_RETR:
        JSR PARSE_AND_FIND_FILE
        BCC SIZE_NF
        JSR READ_CUR_SLOT_FILE
        JSR SEND_150_WAIT_DATA
        BCC DFL_ERR
        JSR SX_SEND_FILE_BUF
        INC XFER_CNT
        JMP CLOSE_DATA_226

READ_CUR_SLOT_FILE:
        LDY #20
        LDA (ZP_SLOT_LO),Y
        STA FILE_SIZE_LO
        INY
        LDA (ZP_SLOT_LO),Y
        STA FILE_SIZE_HI
        JSR SETUP_FILE_XFER
RCS_RD: JSR ROM_READ_SEC
        DEC SEC_CNT
        BNE RCS_RD
        RTS

SX_SEND_FILE_BUF:
        LDA #<FILE_BUF
        STA ZP_SRC_LO
        LDA #>FILE_BUF
        STA ZP_SRC_HI
SFB_LP: LDA FILE_SIZE_LO
        ORA FILE_SIZE_HI
        BEQ SFB_RTS
        LDA FILE_SIZE_HI
        BNE SFB_C2
        LDA FILE_SIZE_LO
        BNE SFB_C3
SFB_C2: LDA #0
SFB_C3: STA TMP_B

        JSR SX_TX_PTR_HDR
        LDY #0
SFB_BL: LDA (ZP_SRC_LO),Y
        JSR SPI_AND_INC_SX
        INY
        CPY TMP_B
        BNE SFB_BL
        JSR W5500_CS_HI
        JSR SX_FLUSH_SEND

        LDA TMP_B
        BNE SFB_DN
        INC ZP_SRC_HI
        DEC FILE_SIZE_HI
        JMP SFB_LP
SFB_DN: LDA #0
        STA FILE_SIZE_LO
        STA FILE_SIZE_HI
SFB_RTS:
        RTS

; --- STOR <bestandsnaam>: Ontvang bestand van PC en schrijf naar SD/RAM-Disk! ---
DO_FTP_STOR:
        JSR PARSE_AND_FIND_FILE
        BCS DFS_GOT
        JSR FIND_FREE_DIR_SLOT
        BCC DFS_GOT
        LDA #STR_552 - FTP_REPS
        JMP S1_SEND_REP_A

DFS_GOT:
        JSR SEND_150_WAIT_DATA
        BCS DFS_CON
        JMP DFL_ERR

DFS_CON:
        LDA #<FILE_BUF
        STA ZP_PTR_LO
        LDA #>FILE_BUF
        STA ZP_PTR_HI
        LDA #0
        STA FILE_SIZE_LO
        STA FILE_SIZE_HI

DFS_RLP:
        JSR SX_GET_RX_LEN
        BNE DFS_GOT_B
        LDA #$03
        JSR SX_RD
        CMP #$17
        BEQ DFS_RLP
        JSR SX_GET_RX_LEN
        BEQ DFS_RDN

DFS_GOT_B:
        LDA SX_LEN_HI
        BNE DFS_CL
        LDA SX_LEN_LO
        CMP #250
        BCC DFS_C2
DFS_CL: LDA #250
DFS_C2: STA TMP_B

        JSR SX_RX_PTR_HDR
        LDY #0
DFS_BL: LDA #0
        JSR SPI_AND_INC_SX
        LDX ZP_PTR_HI
        CPX #$50
        BCS DFS_SK
        STA (ZP_PTR_LO),Y
        INC ZP_PTR_LO
        BNE DFS_I1
        INC ZP_PTR_HI
DFS_I1: INC FILE_SIZE_LO
        BNE DFS_SK
        INC FILE_SIZE_HI
DFS_SK: DEC TMP_B
        BNE DFS_BL

        JSR W5500_CS_HI
        LDA #$28
        LDY #$40
        JSR SX_PTR_CMD
        JMP DFS_RLP

DFS_RDN:
        JSR DATA_CLOSE

        LDA FILE_BUF
        CMP #'M'
        BNE DFS_W1
        LDA FILE_BUF+1
        CMP #'I'
        BNE DFS_W1
        LDA #$50
        STA LOAD_HI_TMP
        LDA #'B'
        STA FILE_TYPE_TMP

DFS_W1: JSR SETUP_FILE_XFER
DFS_WR: JSR ROM_WRITE_SEC
        DEC SEC_CNT
        BNE DFS_WR

        JSR CLEAR_CUR_SLOT
        LDY #3
DFS_MG: LDA STR_BBC,Y
        STA (ZP_SLOT_LO),Y
        DEY
        BPL DFS_MG

        LDX #0
        LDY #4
DFS_NM: LDA FNAME_BUF,X
        BEQ DFS_META
        STA (ZP_SLOT_LO),Y
        INX
        INY
        CPY #15
        BCC DFS_NM

DFS_META:
        LDY #20
        LDA FILE_SIZE_LO
        STA (ZP_SLOT_LO),Y
        INY
        LDA FILE_SIZE_HI
        STA (ZP_SLOT_LO),Y
        INY
        LDA FILE_TYPE_TMP
        STA (ZP_SLOT_LO),Y
        INY
        LDA #$00
        STA (ZP_SLOT_LO),Y
        INY
        LDA LOAD_HI_TMP
        STA (ZP_SLOT_LO),Y

        JSR SAVE_CUR_DIR
        INC XFER_CNT
        LDA #STR_226 - FTP_REPS
        JMP S1_SEND_REP_A

; ============================================================================
; Socket 2 Data-Kanaal (PASV Poort 2121) & Socket-Sluiten
; ============================================================================
DATA_OPEN_WAIT:
        LDA #2
        STA LAST_STATUS
        LDA #$48
        STA SOCK_BASE
        LDX #250
DOW_LP: STX TMP_A
        LDA #$03
        JSR SX_RD
        CMP #$17
        BEQ DOW_OK
        CMP #$1C
        BEQ DOW_OK
        JSR DELAY_10MS
        LDX TMP_A
        DEX
        BNE DOW_LP
        JSR DATA_CLOSE
        CLC
        RTS
DOW_OK: SEC
        RTS

DATA_CLOSE:
        LDA #$48
        STA SOCK_BASE
DATA_CLOSE_SOCK:
        LDX #40
DC_WT:  STX TMP_A
        LDA #$20
        JSR SX_RD
        CMP #$08
        BEQ DC_FIN
        JSR DELAY_10MS
        LDX TMP_A
        DEX
        BNE DC_WT
DC_FIN: LDA #$08
        JSR SX_CMD
        JSR DELAY_10MS
        JSR SX_CLOSE
        LDA CTRL_SOCK
        STA SOCK_BASE
        LDA #1
        STA LAST_STATUS
        RTS

S1_SEND_STR:
        LDX CTRL_SOCK
SX_SEND_STR:
        STX SOCK_BASE
        STA ZP_SRC_LO
        STY ZP_SRC_HI
        JSR SX_TX_PTR_HDR
        LDY #0
SSS_LP: LDA (ZP_SRC_LO),Y
        BEQ SSS_DN
        JSR SPI_AND_INC_SX
        INY
        BNE SSS_LP
SSS_DN: LDA #$0D
        JSR SPI_AND_INC_SX
        LDA #$0A
        JSR SPI_AND_INC_SX
        JSR W5500_CS_HI
        JMP SX_FLUSH_SEND

; ============================================================================
; MicroSD & SDRAM-Disk Catalogus en Bestandsnaam Hulproutines
; ============================================================================
CLEAR_CUR_SLOT:
        LDA CUR_SLOT
        JSR GET_SLOT_PTR
        LDY #31
        LDA #0
CCS_L:  STA (ZP_SLOT_LO),Y
        DEY
        BPL CCS_L
        RTS

SETUP_FILE_XFER:
        LDA FILE_SIZE_HI
        LSR A
        CLC
        ADC #1
        STA SEC_CNT
        LDA CUR_SLOT
        STA DISK_SLOT
        JSR SETUP_SLOT_SEC
        LDA #$00
        STA ZP_DST
        LDA #>FILE_BUF
        STA ZP_DST+1
        RTS

LOAD_CUR_DIR:
        JSR ROM_SD_INIT
        JSR SETUP_DIR_SEC
        JMP ROM_READ_SEC

SAVE_CUR_DIR:
        JSR SETUP_DIR_SEC
        JMP ROM_WRITE_SEC

SETUP_DIR_SEC:
        JSR DRIVE_X4_P3
        LDA #$FF
        STA DISK_SEC_LO
        LDA #$00
        STA ZP_DST
        LDA #>DIR_BUF
        STA ZP_DST+1
        RTS

DRIVE_X4_P3:
        LDA DISK_DRIVE
        ASL A
        ASL A
        ADC #$03
        STA DISK_SEC_HI
        RTS

SETUP_SLOT_SEC:
        JSR DRIVE_X4_P3
        LDA DISK_SLOT
        LSR A
        LSR A
        SEC
        ADC DISK_SEC_HI
        STA DISK_SEC_HI
        LDA DISK_SLOT
        AND #3
        LSR A
        ROR A
        ROR A
        STA DISK_SEC_LO
        RTS

GET_SLOT_PTR:
        LDY #>DIR_BUF
        CMP #8
        BCC GSP_1
        INY
GSP_1:  STY ZP_SLOT_HI
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        STA ZP_SLOT_LO
        RTS

CHECK_SLOT_USED:
        LDY #0
        LDA (ZP_SLOT_LO),Y
        CMP #'B'
        BNE CSU_R
        INY
        LDA (ZP_SLOT_LO),Y
        CMP #'B'
        BNE CSU_R
        INY
        LDA (ZP_SLOT_LO),Y
        CMP #'C'
CSU_R:  RTS

PARSE_AND_FIND_FILE:
        LDY ARG_IDX
        JSR CHECK_PATH_DRV
        LDY ARG_IDX
PAF_0:  STY TMP_A
PAF_SL: LDA CMD_BUF,Y
        BEQ PAF_CP
        CMP #'/'
        BNE PAF_S1
        INY
        STY TMP_A
        BNE PAF_SL
PAF_S1: INY
        BNE PAF_SL

PAF_CP: LDY TMP_A
        LDX #0
        LDA #'B'
        STA FILE_TYPE_TMP
        LDA #$80
        STA LOAD_HI_TMP
PAF_CL: LDA CMD_BUF,Y
        BEQ PAF_CE
        CMP #' '
        BEQ PAF_CE
        CMP #'.'
        BEQ PAF_EXT
        CMP #'a'
        BCC PAF_U
        CMP #'z'+1
        BCS PAF_U
        AND #$DF
PAF_U:  CPX #11
        BCS PAF_N1
        STA FNAME_BUF,X
        INX
PAF_N1: INY
        BNE PAF_CL

PAF_EXT:
        INY
        LDA CMD_BUF,Y
        AND #$DF
        CMP #'I'
        BNE PAF_E1
        LDA #$50
        BNE PAF_SLH
PAF_E1: CMP #'T'
        BEQ PAF_TX
        CMP #'H'
        BNE PAF_E2
PAF_TX: LDA #$60
        BNE PAF_SLH
PAF_E2: CMP #'B'
        BNE PAF_CE
        INY
        LDA CMD_BUF,Y
        AND #$DF
        CMP #'A'
        BNE PAF_CE
        LDA #0
        STA FILE_TYPE_TMP
        LDA #$08
PAF_SLH:
        STA LOAD_HI_TMP

PAF_CE: LDA #0
        STA FNAME_BUF,X
        LDA FNAME_BUF
        CMP #'M'
        BNE PAF_SR
        LDA FNAME_BUF+1
        CMP #'C'
        BNE PAF_SR
        LDA FNAME_BUF+2
        BNE PAF_SR
        LDA #$90
        STA LOAD_HI_TMP

PAF_SR: LDA #0
        STA CUR_SLOT
PAF_LP: LDA CUR_SLOT
        JSR GET_SLOT_PTR
        JSR CHECK_SLOT_USED
        BNE PAF_NX
        LDY #4
        LDX #0
PAF_CM: LDA FNAME_BUF,X
        CMP (ZP_SLOT_LO),Y
        BNE PAF_NX
        CMP #0
        BEQ PAF_OK
        INX
        INY
        CPY #15
        BCC PAF_CM
PAF_OK: SEC
        RTS
PAF_NX: INC CUR_SLOT
        LDA CUR_SLOT
        CMP #15
        BCC PAF_LP
        CLC
        RTS

FIND_FREE_DIR_SLOT:
        LDA #0
        STA CUR_SLOT
FFD_LP: LDA CUR_SLOT
        JSR GET_SLOT_PTR
        JSR CHECK_SLOT_USED
        BNE FFD_OK
        INC CUR_SLOT
        LDA CUR_SLOT
        CMP #15
        BCC FFD_LP
        SEC
        RTS
FFD_OK: CLC
        RTS

; ============================================================================
; W5500 Multi-Socket SPI Driver (SOCK_BASE = $28, $48, $68)
; ============================================================================
W5500_INIT_HW:
        LDX #6
WIH_CP: LDA W5500_STUB_BYTES,X
        STA SPI_BRAM_STUB,X
        DEX
        BPL WIH_CP
        LDA #$03
        STA IO_NET_CTRL
        JSR W5500_PROBE_HW
        BNE WIH_R
        LDA #$0F
        JSR W5500_RD_CREG
        CMP #192
        BNE WIH_W
        LDA #$12
        JSR W5500_RD_CREG
        STA W5500_INIT_TBL+21
        RTS
WIH_W:  LDA #$02
        STA IO_NET_CTRL
        LDX #0
WIH_L:  LDA W5500_INIT_TBL,X
        JSR SPI_BRAM_STUB
        INX
        CPX #22
        BCC WIH_L
        JMP W5500_CS_HI
WIH_R:  RTS

W5500_PROBE_HW:
        LDA #$2E
        JSR W5500_RD_CREG
        STA W5500_PHY
        LDA #$39
        JSR W5500_RD_CREG
        STA W5500_VER
        CMP #$04
        RTS

W5500_HDR_0:
        LDX #$00
W5500_HDR:
        PHA
        LDA #$02
        STA IO_NET_CTRL
        TXA
        JSR SPI_BRAM_STUB
        PLA
        JSR SPI_BRAM_STUB
        TYA
        JMP SPI_BRAM_STUB

SX_RD:  LDY SOCK_BASE
        BNE W5500_RD_Y
W5500_RD_CREG:
        LDY #$00
W5500_RD_Y:
        JSR W5500_HDR_0
        LDA #$00
        JSR SPI_BRAM_STUB
        PHA
        JSR W5500_CS_HI
        PLA
        RTS

W5500_CS_HI:
        LDA #$03
        STA IO_NET_CTRL
        RTS

SX_WR:  PHA
        LDA SOCK_BASE
        ORA #$04
        TAY
        TXA
        JSR W5500_HDR_0
        PLA
        JSR SPI_BRAM_STUB
        JMP W5500_CS_HI

SX_CLOSE:
        LDA #$10
SX_CMD: LDX #$01
        JSR SX_WR
SXC_W:  LDA #$01
        JSR SX_RD
        BNE SXC_W
        RTS

SX_FLUSH_SEND:
        LDA #$24
        LDY #$20
SX_PTR_CMD:
        STY TMP_A
        PHA
        LDA SOCK_BASE
        ORA #$04
        TAY
        PLA
        JSR W5500_HDR_0
        LDA SX_PTR_HI
        JSR SPI_BRAM_STUB
        LDA SX_PTR_LO
        JSR SPI_BRAM_STUB
        JSR W5500_CS_HI
        LDA TMP_A
        JMP SX_CMD

SX_TX_PTR_HDR:
        LDA #$24
        LDX #$0C
        BNE SX_PTR_HDR
SX_RX_PTR_HDR:
        LDA #$28
        LDX #$10
SX_PTR_HDR:
        PHA
        TXA
        CLC
        ADC SOCK_BASE
        STA TMP_A
        PLA
        PHA
        JSR SX_RD
        STA SX_PTR_HI
        PLA
        CLC
        ADC #1
        JSR SX_RD
        STA SX_PTR_LO
        LDX SX_PTR_HI
        LDY TMP_A
        JMP W5500_HDR

SPI_AND_INC_SX:
        JSR SPI_BRAM_STUB
        INC SX_PTR_LO
        BNE SAIS_R
        INC SX_PTR_HI
SAIS_R: RTS

SX_GET_RX_LEN:
        LDA #$26
        JSR SX_RD
        STA SX_LEN_HI
        LDA #$27
        JSR SX_RD
        STA SX_LEN_LO
        ORA SX_LEN_HI
        RTS

; ============================================================================
; Tekst/Getal Opmaak & Live Server Logbuffer
; ============================================================================
APPEND_DEC_BYTE:
        STA DEC_LO
        LDA #0
        STA DEC_HI
APPEND_DEC16:
        STY SEC_CNT
        LDX #0
AD16_L: LDA #0
        STA TMP_B
AD16_S: LDA DEC_LO
        SEC
        SBC POW10_LO,X
        PHA
        LDA DEC_HI
        SBC POW10_HI,X
        BCC AD16_N
        STA DEC_HI
        PLA
        STA DEC_LO
        INC TMP_B
        BNE AD16_S
AD16_N: PLA
        LDA TMP_B
        BNE AD16_P
        CPX #4
        BEQ AD16_P
        CPY SEC_CNT
        BEQ AD16_X
AD16_P: LDA TMP_B
        CLC
        ADC #'0'
        STA TX_LINE_BUF,Y
        INY
AD16_X: INX
        CPX #5
        BCC AD16_L
        RTS

ADD_LOG_STR:
        STA ZP_SRC_LO
        STY ZP_SRC_HI
        LDX #0
ALS_S:  LDA LOG_BUF+32,X
        STA LOG_BUF,X
        INX
        CPX #7*32
        BCC ALS_S
        LDY #0
ALS_C:  LDA (ZP_SRC_LO),Y
        BEQ ALS_P
        STA LOG_BUF+7*32,Y
        INY
        CPY #31
        BCC ALS_C
ALS_P:  LDA #0
        STA LOG_BUF+7*32,Y
        RTS

; ============================================================================
; Grafische 640x360 Split-Screen FTP/Web-Server UI op MiniGPU ($A020)
; ============================================================================
SET_XY_COL:
        STA ZP_Y_LO
        STX ZP_COLOR
        STY ZP_X_LO
        LDA #0
        STA ZP_X_HI
        STA ZP_Y_HI
        RTS

SEND_STREAM_X:
        LDY GPU_STREAMS,X
SSX_L:  INX
        LDA GPU_STREAMS,X
        STA IO_GPU
        DEY
        BNE SSX_L
        STY ZP_Y_HI
        RTS

DRAW_SCREEN:
        LDX #GS_UI - GPU_STREAMS
        JSR SEND_STREAM_X
        JSR W5500_PROBE_HW
        JSR DRAW_LED_ONLY

        ; Teken alle vaste UI-titels vanuit de tabel UI_LABELS
        LDA #<UI_LABELS
        STA ZP_PTR_LO
        LDA #>UI_LABELS
        STA ZP_PTR_HI
DSL_LP: JSR READ_PTR_B
        BEQ DSL_DN
        STA ZP_Y_LO
        JSR READ_PTR_B
        STA ZP_X_LO
        JSR READ_PTR_B
        STA ZP_X_HI
        JSR READ_PTR_B
        STA ZP_COLOR
        JSR DRAW_PTR_STR
        JMP DSL_LP
DSL_DN:
        ; Na het laatste label ("http & ftp://" op Y=29) staat de cursor klaar voor IP!
        LDA #$FF
        STA ZP_COLOR
        LDX #0
        JSR DRAW_IP_X
        LDA #<STR_URL_PORT
        LDY #>STR_URL_PORT
        JSR DRAW_STR_AY
        LDA #$FC
        STA ZP_COLOR
        JSR GET_DRV_CHARS
        JSR DRAW_CHAR_ADV
        TXA
        JSR DRAW_CHAR_ADV

        LDA #$38
        STA ZP_X_LO
        LDA #$02
        STA ZP_X_HI
        LDX LAST_STATUS
        LDA STATUS_COLS,X
        STA ZP_COLOR
        TXA
        ASL A
        ASL A
        TAX
        LDY #4
DS_STB: LDA STATUS_TBL,X
        JSR DRAW_CHAR_ADV
        INX
        DEY
        BNE DS_STB

        ; Linker Paneel: 15 slots op Y=64..246 (< 256!)
        LDA #64
        STA ROW_Y_SAV
        LDA #0
        STA CUR_SLOT
DS_SL:  LDA ROW_Y_SAV
        LDX #$92
        LDY #18
        JSR SET_XY_COL
        LDA CUR_SLOT
        CMP #10
        BCC DS_S1
        LDA #'1'
        JSR DRAW_CHAR_ADV
        LDA CUR_SLOT
        SEC
        SBC #10
        JMP DS_S2
DS_S1:  PHA
        LDA #'0'
        JSR DRAW_CHAR_ADV
        PLA
DS_S2:  CLC
        ADC #'0'
        JSR DRAW_CHAR_ADV
        LDA #' '
        JSR DRAW_CHAR_ADV

        LDA CUR_SLOT
        JSR GET_SLOT_PTR
        JSR CHECK_SLOT_USED
        BNE DS_SEMP

        LDA #$FF
        STA ZP_COLOR
        LDY #4
DS_SNM: LDA (ZP_SLOT_LO),Y
        BEQ DS_SPD
        JSR DRAW_CHAR_ADV
        INY
        CPY #16
        BCC DS_SNM
        BCS DS_STP
DS_SPD: LDA #' '
        JSR DRAW_CHAR_ADV
        INY
        CPY #16
        BCC DS_SPD

DS_STP: LDA #$1C
        STA ZP_COLOR
        LDY #0
        JSR APPEND_SLOT_SIZE_Y
        LDA #'B'
        STA TX_LINE_BUF,Y
        INY
        LDA #0
        STA TX_LINE_BUF,Y
        LDA #<TX_LINE_BUF
        LDY #>TX_LINE_BUF
        JSR DRAW_STR_AY
        JMP DS_SNX

DS_SEMP:
        LDA #<STR_FREE_SLOT
        LDY #>STR_FREE_SLOT
        JSR DRAW_STR_AY

DS_SNX: CLC
        LDA ROW_Y_SAV
        ADC #13
        STA ROW_Y_SAV
        INC CUR_SLOT
        LDA CUR_SLOT
        CMP #15
        BCC DS_SL

        ; Rechter Paneel: Client-IP & Overdrachtsteller
        LDA #68
        LDX #$FF
        LDY #144
        JSR SET_XY_COL
        INC ZP_X_HI
        LDA CLI_IP0
        BNE DS_CIP
        LDA #<STR_NO_CLI
        LDY #>STR_NO_CLI
        JSR DRAW_STR_AY
        JMP DS_XFR
DS_CIP: LDX #4
        JSR DRAW_IP_X

DS_XFR: LDA #85
        LDX #$1C
        LDY #192
        JSR SET_XY_COL
        INC ZP_X_HI
        LDA XFER_CNT
        JSR DRAW_DEC_BYTE

        ; 8 Log-regels op Y=124..236 (< 256!)
        LDA #124
        STA ROW_Y_SAV
        LDA #0
        STA CUR_SLOT
DS_LLP: LDA ROW_Y_SAV
        LDX #$1C
        LDY #72
        JSR SET_XY_COL
        INC ZP_X_HI
        LDA CUR_SLOT
        ASL A
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #<LOG_BUF
        PHA
        LDA #>LOG_BUF
        ADC #0
        TAY
        PLA
        JSR DRAW_STR_AY
        CLC
        LDA ROW_Y_SAV
        ADC #16
        STA ROW_Y_SAV
        INC CUR_SLOT
        LDA CUR_SLOT
        CMP #8
        BCC DS_LLP

        LDA #$4E
        LDX #$FF
        LDY #16
        JSR SET_XY_COL
        INC ZP_Y_HI
        LDA #<STR_BOT_BAR
        LDY #>STR_BOT_BAR
        JMP DRAW_STR_AY

DRAW_IP_X:
        LDA #4
        STA CUR_SLOT
DIX_1:  STX TMP_A
        LDA W5500_INIT_TBL+18,X
        JSR DRAW_DEC_BYTE
        DEC CUR_SLOT
        BEQ DIX_2
        LDA #'.'
        JSR DRAW_CHAR_ADV
        LDX TMP_A
        INX
        BNE DIX_1
DIX_2:  RTS

DRAW_DEC_BYTE:
        LDY #0
        JSR APPEND_DEC_BYTE
        LDA #0
        STA TX_LINE_BUF,Y
        LDA #<TX_LINE_BUF
        LDY #>TX_LINE_BUF
        JMP DRAW_STR_AY

DRAW_LED_ONLY:
        LDX #GS_LED - GPU_STREAMS
        JSR SEND_STREAM_X
        LDA #$E0
        LDX W5500_VER
        CPX #$04
        BNE DLO_C
        LDA W5500_PHY
        AND #$01
        BEQ DLO_Y
        LDA #$1C
        BNE DLO_C
DLO_Y:  LDA #$FC
DLO_C:  STA IO_GPU
        RTS

READ_PTR_B:
        LDY #0
        LDA (ZP_PTR_LO),Y
        INC ZP_PTR_LO
        BNE RPB_R
        INC ZP_PTR_HI
RPB_R:  CMP #0
        RTS

DRAW_STR_AY:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DRAW_PTR_STR:
        JSR READ_PTR_B
        BEQ DCA_R
        JSR DRAW_CHAR_ADV
        JMP DRAW_PTR_STR

DRAW_CHAR_ADV:
        CMP #' '+1
        BCC ADV_X8
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
ADV_X8: CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCA_R
        INC ZP_X_HI
DCA_R:  RTS

DELAY_10MS:
        LDA IO_TIMER
D10_W:  CMP IO_TIMER
        BEQ D10_W
        RTS

; ============================================================================
; Tabellen, GPU-Streams & FTP/HTTP-Antwoordstrings
; ============================================================================
POW10_LO:       .BYTE <10000, <1000, <100, <10, <1
POW10_HI:       .BYTE >10000, >1000, >100, >10, >1

STATUS_COLS:    .BYTE $FC, $1C, $1F
STATUS_TBL:     .BYTE "WCHTONLNDATA"
STR_BBC:        .BYTE "BBC!"

W5500_STUB_BYTES:
        STA IO_NET_DATA
        LDA IO_NET_DATA
        RTS

W5500_INIT_TBL:
        .BYTE $00, $00, $04, $00
        .BYTE 192, 168, 178, 1
        .BYTE 255, 255, 255, 0
        .BYTE $02, $65, $02, $20, $00, $03
        .BYTE 192, 168, 178, 201
CLI_IP0:
        .BYTE 0, 0, 0, 0

GPU_STREAMS:
GS_UI:
        .BYTE GS_LED - GS_UI - 1
        .BYTE 12, 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0
        .BYTE 15, 0, 0, 0, 0
        .BYTE 1, $00
        .BYTE 2, 0,0, 7,0, $80,$02, 15,0, $21
        .BYTE 2, 8,0, 23,0, $70,$02, 19,0, $01
        .BYTE 2, 8,0, 44,0, $32,$01, $1A,$01, $1F
        .BYTE 2, 9,0, 45,0, $30,$01, $18,$01, $00
        .BYTE 2, $42,$01, 44,0, $36,$01, $1A,$01, $1F
        .BYTE 2, $43,$01, 45,0, $34,$01, $18,$01, $00
        .BYTE 2, 0,0, $4B,$01, $80,$02, 16,0, $21
GS_LED:
        .BYTE GS_EXIT - GS_LED - 1
        .BYTE 5, $68,$02, 14,0, 4,0, 0,0
GS_EXIT:
        .BYTE UI_LABELS - GS_EXIT - 1
        .BYTE 12, 1, 1, $E3

; Vaste UI-labels: .BYTE Y_LO, X_LO, X_HI, COLOR, "tekst", 0
UI_LABELS:
        .BYTE 11, 16, 0, $FC, "MiniGPU FTP & Web Server 1.1 (:21/:80)", 0
        .BYTE 49, 18, 0, $FC, "SL BESTAND       GROOTTE", 0
        .BYTE 49, 72, 1, $FC, "FTP + WEB STATUS & LOG", 0
        .BYTE 68, 72, 1, $1F, "Client : ", 0
        .BYTE 85, 72, 1, $1F, "Overdrachten : ", 0
        .BYTE 106, 72, 1, $FC, "LAATSTE COMMANDO'S:", 0
        .BYTE 29, 16, 0, $1F, "http & ftp://", 0
        .BYTE 0

STR_URL_PORT:   .ASCIIZ " (:80/:21) /"
STR_NO_CLI:     .ASCIIZ "Wacht op :21 / :80"
STR_FREE_SLOT:  .ASCIIZ "(vrij)"
STR_BOT_BAR:    .ASCIIZ "1:SD0 2:SD1 3:RAM0 4:RAM1  R:Ververs  K:Kick  Q:Stop"

STR_LOG_BOOT:   .ASCIIZ "* Server op :21 & :80"
STR_LOG_CONN:   .ASCIIZ "* Client verbonden"

; --- Gedeelde String-Pool voor APPEND_POOL_X (< 256 B) ---
STR_POOL:
SP_227_PFX:     .ASCIIZ "227 Entering Passive Mode ("
SP_227_SFX:     .ASCIIZ "8,73)"
SP_213_PFX:     .ASCIIZ "213 "
SP_LIST_PFX:    .ASCIIZ "-rw-r--r-- 1 ftp ftp "
SP_LIST_DATE:   .ASCIIZ " Jan 01 12:00 "
SP_H_A1:        .ASCIIZ "<a href=/"
SP_H_A2:        .ASCIIZ "</a>"

; --- RFC 959 FTP Server Replies (< 256 B vanaf FTP_REPS) ---
FTP_REPS:
STR_220:        .ASCIIZ "220 MiniGPU FTP Ready"
STR_331:        .ASCIIZ "331 Password?"
STR_230:        .ASCIIZ "230 Login OK"
STR_215:        .ASCIIZ "215 UNIX Type: L8"
STR_211:        .BYTE "211-FEAT", 13, 10, " PASV", 13, 10, "211 End", 0
STR_200:        .ASCIIZ "200 OK"
STR_250:        .ASCIIZ "250 OK"
STR_257:        .BYTE "257 ", 34, "/"
STR_257_DRV:    .BYTE "D0", 34, " OK", 0
STR_150:        .ASCIIZ "150 Data OK"
STR_226:        .ASCIIZ "226 Done"
STR_221:        .ASCIIZ "221 Bye"
STR_425:        .ASCIIZ "425 Err"
STR_550:        .ASCIIZ "550 Err"
STR_552:        .ASCIIZ "552 Full"

; --- HTTP :80 Web-Server Strings ---
STR_INDEX:      .ASCIIZ "INDEX"
STR_HTTP_BIN:   .BYTE "HTTP/1.0 200 OK", 13, 10, 0
STR_HTTP_HTML:  .BYTE "<body bgcolor=#002 text=#0ff link=#ff0><pre><b>MiniGPU /"
STR_H_DRV:      .BYTE "D0</b> <a href=/>[Web]</a> <a href=/D0>[D0]</a> <a href=/D1>[D1]</a> "
                .BYTE "<a href=/R0>[R0]</a> <a href=/R1>[R1]</a><hr>", 0
STR_H_END:      .ASCIIZ "<hr>FTP :21/:80</pre>"
