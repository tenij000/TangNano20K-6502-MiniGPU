; ============================================================================
; READER.asm - MiniGPU TextReader 6502 (Tekst-, BASIC-, Writer- & Hex-Lezer)
; Geassembleerd op $8000 in SDRAM (<= 4095 bytes, dus veilig naast MC op $9000).
;
; Mogelijkheden:
;   * Leest platte tekstbestanden (.TXT op $6000) met automatische woordafbreking
;   * Leest én detokeniseert BASIC-programma's (.BAS) direct vanaf de SD-kaart
;   * Leest LibreWriter 6502 documenten (Sectors $03F8..$03FB)
;   * Ingebouwde grafische SD-Kaart Bestands-Kiezer (O / Enter) voor D0..D3 & Mappen
;   * Live Hex + ASCII Dump Modus (H) voor het inspecteren van .ASM/.BIN/.TXT/.BAS
;   * 4 Kleurthema's (C): Wit Papier, Dark Mode, Retro Amber & Matrix Groen
;   * Regelnummers Aan/Uit (R), Scrollbar, PageUp/PageDown & Top/End navigatie
;
; Starten vanuit BASIC met:             BRUN READER
; Of vanuit Midnight Commander (MC):    Selecteer READER en druk op ENTER
; ============================================================================
        ORG $8000

; --- Systeem & Hardware I/O Adressen ---
IO_STATUS       = $A000         ; Bit 7 = ESC, Bit 0 = Toets klaar
IO_TERM         = $A001         ; Lees/schrijf ASCII karakter (UART / PS/2)
IO_TIMER        = $A003         ; 100 Hz hardware systeemtimer (10ms ticks)
IO_JOY          = $A004         ; Joypad / PS/2 Pijltjes status
IO_MODE         = $A006         ; 0 = MODE 1 (volledig scherm graphics), 1 = MODE 0
IO_GPU          = $A020         ; MiniGPU commando-stream poort

; --- Vaste ROM ABI-Routines & Systeemvariabelen ---
ZP_TMP          = $1A           ; 16-bit ROM scratch pointer ($1A-$1B)
ZP_DST          = $1C           ; 16-bit ROM sector doelpointer ($1C-$1D)
DISK_DRIVE      = $0490         ; Actieve drive/map (0..3 of submap 4..63)
DISK_SLOT       = $0493         ; Huidige bestandsslot (0..14)
DISK_SEC_LO     = $0496         ; SD/SDRAM sector nummer Lo
DISK_SEC_HI     = $0497         ; SD/SDRAM sector nummer Hi

ROM_SILENCE     = $E8DC         ; Zet alle 4 audiokanalen stil
ROM_SD_INIT     = $E96A         ; Initialiseer MicroSD / SDRAM-Disk
ROM_READ_SEC    = $EA67         ; Lees 512-byte sector naar (ZP_DST), ZP_DST += $0200

; --- Eigen Zero Page Variabelen ($60..$87) ---
ZP_PTR_LO       = $60           ; Algemene 16-bit pointer voor strings/streams
ZP_PTR_HI       = $61
ZP_SRC_LO       = $62           ; 16-bit bronpointer voor parser / renderer
ZP_SRC_HI       = $63
ZP_OUT_LO       = $64           ; 16-bit doelpointer bij tekst-opbouw
ZP_OUT_HI       = $65
ZP_X_LO         = $66           ; 16-bit GPU X-coördinaat
ZP_X_HI         = $67
ZP_Y_LO         = $68           ; 16-bit GPU Y-coördinaat
ZP_Y_HI         = $69
ZP_FG_COL       = $6A           ; Huidige tekst voorgrondkleur
ZP_BG_COL       = $6B           ; Huidige achtergrondkleur

TOP_LINE        = $6C           ; Eerste zichtbare regel op het scherm (0..239)
TOTAL_LINES     = $6D           ; Totaal aantal regels in document (1..240)
VIEW_MODE       = $6E           ; 0 = Tekst-weergave, 1 = Hex + ASCII Dump
SHOW_LINENUMS   = $6F           ; 1 = Toon regelnummers (001..), 0 = Verberg
THEME_IDX       = $70           ; Kleurthema (0=Papier, 1=Donker, 2=Amber, 3=Matrix)
PAPER_BG        = $71           ; Actuele papier-achtergrondkleur
PAPER_FG        = $72           ; Actuele standaard tekstkleur
HEAD_FG         = $73           ; Kleur voor kopteksten (#, ===, [)
ACCENT_FG       = $74           ; Kleur voor regelnummers & opsommingen (*, -)

MENU_OPEN       = $75           ; 1 = Bovenste ESC-menubalk geopend
FILE_DLG_OPEN   = $76           ; 1 = SD-Kaart Bestands-Kiezer geopend
DLG_SEL         = $77           ; Geselecteerd slot in Bestands-Kiezer (0..14)
PREV_JOY        = $79           ; Vorige IO_JOY status

CHAR_CNT_LO     = $7A           ; 16-bit teller voor aantal tekens
CHAR_CNT_HI     = $7B
RAW_LEN_LO      = $7C           ; 16-bit bestandsgrootte in bytes
RAW_LEN_HI      = $7D
RAW_BASE_LO     = $7E           ; 16-bit startadres voor Hex-dump ($6000/$0800/$8000)
RAW_BASE_HI     = $7F

ZP_SAV_ROW      = $80           ; Huidige schermrij (0..17)
ZP_SAV_COL      = $81           ; Tijdelijke kolom/teller
ZP_LINE_IDX     = $82           ; Document-regelindex (TOP_LINE + ZP_SAV_ROW)
ZP_CUR_LEN      = $83           ; Lengte van huidige tekstregel
NUM_TMP_LO      = $84           ; 16-bit werkregister voor decimaal afdrukken
NUM_TMP_HI      = $85
STATUS_MSG_LO   = $86           ; Pointer naar statusbericht rechtsonder
STATUS_MSG_HI   = $87

; --- SDRAM Geheugenbuffers ($3000..$6FFF, vrij van BASIC $0800 & MC $5C00/$9000) ---
RAW_BUF         = $3000         ; Ruwe bestandsbuffer vanaf SD-kaart (max 8 KB)
DIR_BUF         = $5000         ; 512-byte directory buffer voor Bestands-Kiezer
LINE_PTR_LO     = $5200         ; Tabel met startadres Lo per regel (max 240 regels)
LINE_PTR_HI     = $5300         ; Tabel met startadres Hi per regel
LINE_LEN_TBL    = $5400         ; Tabel met lengte (0..64) per regel
CUR_FILENAME    = $5500         ; Huidige bestandsnaam (16 bytes ASCIIZ)
DOC_MAGIC       = $5520         ; $A5 als er al een geldig document geladen is
DEC_BUF         = $5528         ; 5-byte buffer voor 16-bit decimaal getal
TEXT_BUF        = $6000         ; Geformatteerde ASCII tekstbuffer ($6000..$6FFF, 4 KB)

VISIBLE_ROWS    = 18            ; 18 tekstregels tegelijk zichtbaar op het scherm
MAX_LINE_COLS   = 64            ; Max kolommen per tekstregel
MAX_LINES       = 240           ; Maximaal aantal geïndexeerde regels

; ============================================================================
; Startpunt ($8000)
; ============================================================================
START:
        LDA #12
        STA IO_TERM
        LDA #0
        STA IO_MODE             ; Zet volledig grafisch scherm (MODE 1) aan
        STA MENU_OPEN
        STA FILE_DLG_OPEN
        STA TOP_LINE
        STA VIEW_MODE
        STA DLG_SEL

        LDA #1
        STA SHOW_LINENUMS       ; Regelnummers standaard aan

        LDX #0
IG_LP:
        LDA GPU_INIT_STREAM,X
        STA IO_GPU
        INX
        CPX #(GPU_INIT_STREAM_END - GPU_INIT_STREAM)
        BCC IG_LP

        ; Controleer of er al een document klaarstaat in TEXT_BUF ($6000)
        LDA DOC_MAGIC
        CMP #$A5
        BEQ WARM_DOC_READY

        LDA #0
        STA THEME_IDX
        JSR APPLY_THEME

        ; Zoek automatisch een .TXT bestand (zoals LEESMIJ) op de actieve SD-drive;
        ; als niet gevonden, laad de ingebouwde Handleiding!
        JSR TRY_AUTOLOAD_TXT
        BCC DOC_INIT_DONE
        JSR LOAD_BUILTIN_GUIDE
        JMP DOC_INIT_DONE

WARM_DOC_READY:
        JSR APPLY_THEME
        JSR BUILD_LINE_INDEX
        LDA #(STR_MSG_READY - STR_MSG_BASE)
        JSR SET_STATUS_MSG

DOC_INIT_DONE:
        LDA IO_JOY
        STA PREV_JOY
        JSR REDRAW_SCREEN

; ============================================================================
; Hoofdlus: Toetsenbord & Joypad / Pijltjes Navigatie
; ============================================================================
MAIN_LOOP:
        LDA IO_TIMER
W10_POLL:
        CMP IO_TIMER
        BEQ W10_POLL

        ; 1. Controleer op ESC (Bit 7 van IO_STATUS)
        LDA IO_STATUS
        BPL CHK_JOY_INPUT
        LDA IO_TERM             ; Lees en wis ESC ($1B)
        LDA FILE_DLG_OPEN
        BNE CLOSE_FILE_DLG
        LDA MENU_OPEN
        BNE EXIT_TO_BASIC_OR_MC ; Nogmaals ESC in het menu = Afsluiten!
        LDA #1
        STA MENU_OPEN
        BNE REDRAW_AND_LOOP

CLOSE_FILE_DLG:
        LDA #0
        STA FILE_DLG_OPEN
        LDA #(STR_MSG_READY - STR_MSG_BASE)
        JMP FINISH_ACT_MSG

EXIT_TO_BASIC_OR_MC:
        JSR ROM_SILENCE
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU              ; Zet GPU terug op frontbuffer (TARGET 1)
        STA IO_GPU              ; Cmd 1 = CLEAR
        STA IO_MODE             ; Zet groene tekst-terminal weer zichtbaar
        LDA #$E3
        STA IO_GPU              ; Wis scherm naar transparant ($E3)
        LDA #12
        STA IO_TERM
        RTS

; --- 2. Controleer Joypad / PS/2 Pijltjestoetsen (Rising Edge) ---
CHK_JOY_INPUT:
        LDA IO_JOY
        STA ZP_SAV_COL
        TAX
        EOR PREV_JOY
        AND ZP_SAV_COL
        STX PREV_JOY
        TAY
        BEQ CHK_ASCII_KEY

        LDA IO_STATUS
        AND #1
        BEQ HANDLE_JOY_BITS
        LDA IO_TERM
        CMP #$0D
        BEQ KEY_ENTER_ACT
HANDLE_JOY_BITS:
        TYA
        AND #1
        BNE ACT_UP
        TYA
        AND #2
        BNE ACT_DOWN
        TYA
        AND #4
        BNE ACT_PAGE_UP
        TYA
        AND #8
        BNE ACT_PAGE_DOWN
        TYA
        AND #$40
        BNE ACT_TOGGLE_MENU
        TYA
        AND #16
        BEQ MAIN_LOOP
        LDA FILE_DLG_OPEN
        BNE KEY_ENTER_ACT
        BEQ ACT_PAGE_DOWN

; --- 3. Controleer Standaard ASCII Toetsaanslagen via Sneltoets-Tabel ---
CHK_ASCII_KEY:
        LDA IO_STATUS
        AND #1
        BEQ MAIN_LOOP
        LDA IO_TERM
        LDX IO_JOY
        STX PREV_JOY

        CMP #'a'
        BCC CAK_UPP
        CMP #'z'+1
        BCS CAK_UPP
        AND #$DF
CAK_UPP:
        STA ZP_SAV_COL

        LDX FILE_DLG_OPEN
        BNE HANDLE_DLG_KEY

        ; Als ESC-menu open staat, sluit menu bij elke toets en voer de sneltoets uit
        LDX #0
        STX MENU_OPEN

        LDX #(KEY_TBL_END - KEY_TBL - 1)
CAK_SCAN:
        CMP KEY_TBL,X
        BEQ CAK_EXEC
        DEX
        BPL CAK_SCAN
REDRAW_AND_LOOP:
        JSR REDRAW_SCREEN
        JMP MAIN_LOOP
CAK_EXEC:
        LDA KEY_ACT_LO,X
        STA ZP_PTR_LO
        LDA KEY_ACT_HI,X
        STA ZP_PTR_HI
        JMP (ZP_PTR_LO)

KEY_ENTER_ACT:
        LDA FILE_DLG_OPEN
        BNE DLG_OPEN_SELECTED
        JMP OPEN_FILE_DIALOG

; ============================================================================
; Navigatie & Weergave Acties (Scrollen, Pagina, Thema, Hex, Regelnummers)
; ============================================================================
ACT_UP:
        LDA FILE_DLG_OPEN
        BNE DLG_MOVE_UP
        LDA TOP_LINE
        BEQ AU_DONE
        DEC TOP_LINE
        BPL REDRAW_AND_LOOP
AU_DONE:
        JMP MAIN_LOOP

DLG_MOVE_UP:
        DEC DLG_SEL
        BPL REDRAW_AND_LOOP
        LDA #14
        STA DLG_SEL
        BPL REDRAW_AND_LOOP

ACT_DOWN:
        LDA FILE_DLG_OPEN
        BNE DLG_MOVE_DOWN
        LDA TOP_LINE
        CLC
        ADC #1
        CMP TOTAL_LINES
        BCS AU_DONE
        STA TOP_LINE
        BCC REDRAW_AND_LOOP

DLG_MOVE_DOWN:
        INC DLG_SEL
        LDA DLG_SEL
        CMP #15
        BCC REDRAW_AND_LOOP
        LDA #0
        STA DLG_SEL
        BEQ REDRAW_AND_LOOP

ACT_PAGE_UP:
        LDA FILE_DLG_OPEN
        BNE DLG_MOVE_UP
        LDA TOP_LINE
        SEC
        SBC #VISIBLE_ROWS
        BCS APU_SET
        LDA #0
APU_SET:
        STA TOP_LINE
        JMP REDRAW_AND_LOOP

ACT_PAGE_DOWN:
        LDA FILE_DLG_OPEN
        BNE DLG_MOVE_DOWN
        JSR CALC_MAX_TOP
        STA ZP_SAV_COL
        LDA TOP_LINE
        CLC
        ADC #VISIBLE_ROWS
        CMP ZP_SAV_COL
        BCC APD_SET
        LDA ZP_SAV_COL
APD_SET:
        STA TOP_LINE
        JMP REDRAW_AND_LOOP

ACT_HOME:
        LDA #0
        BEQ AE_SET

ACT_END:
        JSR CALC_MAX_TOP
AE_SET:
        STA TOP_LINE
        JMP REDRAW_AND_LOOP

CALC_MAX_TOP:
        LDA TOTAL_LINES
        SEC
        SBC #VISIBLE_ROWS
        BCS CMT_RTS
        LDA #0
CMT_RTS:
        RTS

ACT_TOGGLE_HEX:
        LDA #0
        STA TOP_LINE
        LDA VIEW_MODE
        EOR #1
        STA VIEW_MODE
        BEQ ATH_TXT
        JSR CALC_HEX_LINES
        JMP REDRAW_AND_LOOP
ATH_TXT:
        JSR BUILD_LINE_INDEX
        JMP REDRAW_AND_LOOP

ACT_TOGGLE_LINENUMS:
        LDA SHOW_LINENUMS
        EOR #1
        STA SHOW_LINENUMS
        JMP REDRAW_AND_LOOP

ACT_NEXT_THEME:
        INC THEME_IDX
        LDA THEME_IDX
        AND #3
        STA THEME_IDX
        JSR APPLY_THEME
        JMP REDRAW_AND_LOOP

ACT_TOGGLE_MENU:
        LDA #1
        STA MENU_OPEN
        BNE REDRAW_AND_LOOP

ACT_NEXT_DRIVE:
        LDA DISK_DRIVE
        CLC
        ADC #1
        AND #3
        STA DISK_DRIVE
        LDA FILE_DLG_OPEN
        BEQ AND_MSG
        JSR READ_CURRENT_DIR
AND_MSG:
        LDA #(STR_MSG_READY - STR_MSG_BASE)
        BNE FINISH_ACT_MSG

ACT_LOAD_WRITER:
        LDA #0
        STA FILE_DLG_OPEN
        JSR LOAD_WRITER_DOC
        JMP REDRAW_AND_LOOP

ACT_LOAD_GUIDE:
        LDA #0
        STA FILE_DLG_OPEN
        JSR LOAD_BUILTIN_GUIDE
        JMP REDRAW_AND_LOOP

FINISH_ACT_MSG:
        JSR SET_STATUS_MSG
        JMP REDRAW_AND_LOOP

; ============================================================================
; Bestands-Kiezer Toetsafhandeling
; ============================================================================
OPEN_FILE_DIALOG:
        LDA #1
        STA FILE_DLG_OPEN
        JSR READ_CURRENT_DIR
        LDA #(STR_MSG_PICK - STR_MSG_BASE)
        BNE FINISH_ACT_MSG

HANDLE_DLG_KEY:
        CMP #$08                ; Backspace = Terug naar hoofd-drive D0
        BEQ HDK_ROOT
        CMP #'D'
        BEQ ACT_NEXT_DRIVE
        CMP #'Q'
        BNE HDK_DRV
        JMP CLOSE_FILE_DLG
HDK_DRV:
        CMP #'1'
        BCC CAK_SCAN_DIRECT
        CMP #'4'+1
        BCS CAK_SCAN_DIRECT
        SEC
        SBC #'1'
        BCS HDK_SET_DRV
HDK_ROOT:
        LDA #0
HDK_SET_DRV:
        STA DISK_DRIVE
        LDA #0
        STA DLG_SEL
        JSR READ_CURRENT_DIR
        JMP REDRAW_AND_LOOP
CAK_SCAN_DIRECT:
        LDX #(KEY_TBL_END - KEY_TBL - 1)
        JMP CAK_SCAN

DLG_OPEN_SELECTED:
        LDA DLG_SEL
        STA DISK_SLOT
        JSR GET_DIR_SLOT_PTR
        JSR CHECK_SLOT_MAGIC
        BEQ DOS_VALID
        LDA #(STR_MSG_EMPTY - STR_MSG_BASE)
        JMP FINISH_ACT_MSG

DOS_VALID:
        LDY #22
        LDA (ZP_TMP),Y
        CMP #'D'
        BNE DOS_LOAD_FILE
        LDY #23
        LDA (ZP_TMP),Y
        JMP HDK_SET_DRV

DOS_LOAD_FILE:
        LDA #0
        STA FILE_DLG_OPEN
        JSR LOAD_SLOT_INTO_READER
        JMP REDRAW_AND_LOOP

; ============================================================================
; SD-Kaart & Bestands-Laad Routines
; ============================================================================
READ_CURRENT_DIR:
        JSR ROM_SD_INIT
        LDA DISK_DRIVE
        AND #$3F
        ASL A
        ASL A
        CLC
        ADC #$03
        STA DISK_SEC_HI
        LDA #$FF
        STA DISK_SEC_LO
        LDA #<DIR_BUF
        STA ZP_DST
        LDA #>DIR_BUF
        STA ZP_DST+1
        JMP ROM_READ_SEC

TRY_AUTOLOAD_TXT:
        JSR READ_CURRENT_DIR
        LDA #0
        STA ZP_SAV_ROW
TAT_LP:
        LDA ZP_SAV_ROW
        JSR GET_DIR_SLOT_PTR
        JSR CHECK_SLOT_MAGIC
        BNE TAT_NEXT
        LDY #22
        LDA (ZP_TMP),Y
        CMP #'B'
        BNE TAT_NEXT
        LDY #24
        LDA (ZP_TMP),Y
        CMP #$60
        BEQ TAT_FOUND
TAT_NEXT:
        INC ZP_SAV_ROW
        LDA ZP_SAV_ROW
        CMP #15
        BCC TAT_LP
        SEC
        RTS
TAT_FOUND:
        LDA ZP_SAV_ROW
        STA DISK_SLOT
        STA DLG_SEL
        JSR LOAD_SLOT_INTO_READER
        CLC
        RTS

LOAD_SLOT_INTO_READER:
        LDA DISK_SLOT
        JSR GET_DIR_SLOT_PTR

        LDY #4
        LDX #0
LSIR_FN:
        LDA (ZP_TMP),Y
        STA CUR_FILENAME,X
        BEQ LSIR_FN_DN
        INY
        INX
        CPX #14
        BCC LSIR_FN
        LDA #0
        STA CUR_FILENAME,X
LSIR_FN_DN:
        LDY #20
        LDA (ZP_TMP),Y
        STA RAW_LEN_LO
        INY
        LDA (ZP_TMP),Y
        STA RAW_LEN_HI

        LDY #22
        LDA (ZP_TMP),Y
        PHA
        LDY #23
        LDA (ZP_TMP),Y
        STA RAW_BASE_LO
        INY
        LDA (ZP_TMP),Y
        STA RAW_BASE_HI

        JSR SETUP_SLOT_SECTOR

        LDA RAW_LEN_HI
        LSR A
        CLC
        ADC #1
        CMP #9
        BCC LSIR_SEC_OK
        LDA #8
LSIR_SEC_OK:
        TAX
        JSR READ_X_SECTORS_RAW

        ; Zet altijd een 0-terminator aan het einde van het geladen bestand in RAW_BUF
        LDA RAW_LEN_LO
        STA ZP_SRC_LO
        LDA RAW_LEN_HI
        AND #$0F
        CLC
        ADC #>RAW_BUF
        STA ZP_SRC_HI
        LDY #0
        TYA
        STA (ZP_SRC_LO),Y

        PLA
        CMP #'M'
        BEQ FORMAT_AS_BASIC

        JSR COPY_RAW_TO_TEXT
        LDA RAW_BASE_HI
        CMP #$60
        BEQ LSIR_IS_TXT

        ; 6502 Binary (.ASM / .BIN): start direct in Hex + ASCII Dump Modus!
        LDA #1
        STA VIEW_MODE
        LDA #0
        STA TOP_LINE
        JSR CALC_HEX_LINES
        LDA #$A5
        STA DOC_MAGIC
        LDA #(STR_MSG_BIN - STR_MSG_BASE)
        JMP SET_STATUS_MSG

READ_X_SECTORS_RAW:
        LDA #<RAW_BUF
        STA ZP_DST
        LDA #>RAW_BUF
        STA ZP_DST+1
RXSR_LP:
        TXA
        PHA
        JSR ROM_READ_SEC
        PLA
        TAX
        DEX
        BNE RXSR_LP
        RTS

LSIR_IS_TXT:
        LDA #0
        STA VIEW_MODE
        STA TOP_LINE
        LDA #$A5
        STA DOC_MAGIC
        JSR BUILD_LINE_INDEX
        LDA #(STR_MSG_LOADED - STR_MSG_BASE)
        JMP SET_STATUS_MSG

COPY_RAW_TO_TEXT:
        JSR INIT_RAW_TO_TEXT_PTRS
        LDX #16
        LDY #0
CRTT_LP:
        LDA (ZP_SRC_LO),Y
        STA (ZP_OUT_LO),Y
        INY
        BNE CRTT_LP
        INC ZP_SRC_HI
        INC ZP_OUT_HI
        DEX
        BNE CRTT_LP
        RTS

INIT_RAW_TO_TEXT_PTRS:
        LDA #<RAW_BUF
        STA ZP_SRC_LO
        LDA #>RAW_BUF
        STA ZP_SRC_HI
        LDA #<TEXT_BUF
        STA ZP_OUT_LO
        LDA #>TEXT_BUF
        STA ZP_OUT_HI
        RTS

; --- Detokeniseer een MiniGPU-BASIC programma (.BAS) naar leesbare ASCII-regels ---
FORMAT_AS_BASIC:
        LDA #$00
        STA RAW_BASE_LO
        LDA #$08
        STA RAW_BASE_HI
        JSR INIT_RAW_TO_TEXT_PTRS

FAB_LINE_LP:
        LDA ZP_OUT_HI
        CMP #$6F
        BCS FAB_DONE
        LDY #0
        LDA (ZP_SRC_LO),Y
        BEQ FAB_DONE
        CMP #128
        BCS FAB_DONE
        STA ZP_CUR_LEN

        INY
        LDA (ZP_SRC_LO),Y
        STA NUM_TMP_LO
        INY
        LDA (ZP_SRC_LO),Y
        STA NUM_TMP_HI
        JSR APPEND_DEC16_TO_OUT
        LDA #' '
        JSR APPEND_CHAR_TO_OUT

        LDY #3
FAB_CH_LP:
        CPY ZP_CUR_LEN
        BCS FAB_LN_END
        LDA (ZP_SRC_LO),Y
        BEQ FAB_LN_END
        JSR APPEND_CHAR_TO_OUT
        INY
        BNE FAB_CH_LP

FAB_LN_END:
        LDA #$0A
        JSR APPEND_CHAR_TO_OUT
        LDA ZP_CUR_LEN
        JSR ADD_A_TO_ZP_SRC
        JMP FAB_LINE_LP

FAB_DONE:
        LDA #0
        JSR APPEND_CHAR_TO_OUT
        JSR LSIR_IS_TXT
        LDA #(STR_MSG_BAS - STR_MSG_BASE)
        JMP SET_STATUS_MSG

; --- Lees LibreWriter 6502 Document (Sectors $03F8..$03FB) in ---
LOAD_WRITER_DOC:
        JSR ROM_SD_INIT
        LDA #$F8
        STA DISK_SEC_LO
        LDA #$03
        STA DISK_SEC_HI
        LDX #4
        JSR READ_X_SECTORS_RAW

        LDA #<STR_FN_WRITER
        LDY #>STR_FN_WRITER
        JSR SET_CUR_FILENAME

        LDA #$00
        STA RAW_LEN_LO
        STA RAW_BASE_LO
        LDA #$08
        STA RAW_LEN_HI
        LDA #$70
        STA RAW_BASE_HI

        JSR INIT_RAW_TO_TEXT_PTRS
        LDX #16
LWD_ROW_LP:
        LDY #0
LWD_CH_LP:
        LDA (ZP_SRC_LO),Y
        CMP #$20
        BCS LWD_PUT
        LDA #' '
LWD_PUT:
        JSR APPEND_CHAR_TO_OUT
        INY
        CPY #62
        BCC LWD_CH_LP
        LDA #$0A
        JSR APPEND_CHAR_TO_OUT
        LDA #128
        JSR ADD_A_TO_ZP_SRC
        DEX
        BNE LWD_ROW_LP
        JMP FAB_DONE

; --- Laad de ingebouwde Nederlandstalige Handleiding ---
LOAD_BUILTIN_GUIDE:
        LDA #<STR_FN_GUIDE
        LDY #>STR_FN_GUIDE
        JSR SET_CUR_FILENAME

        LDA #<(BUILTIN_TEXT_END - BUILTIN_TEXT)
        STA RAW_LEN_LO
        LDA #>(BUILTIN_TEXT_END - BUILTIN_TEXT)
        STA RAW_LEN_HI
        LDA #0
        STA RAW_BASE_LO
        LDA #$60
        STA RAW_BASE_HI

        LDX #0
LBG_CP:
        LDA BUILTIN_TEXT,X
        STA RAW_BUF,X
        LDA BUILTIN_TEXT+$100,X
        STA RAW_BUF+$100,X
        INX
        BNE LBG_CP
        JSR COPY_RAW_TO_TEXT
        JSR LSIR_IS_TXT
        LDA #(STR_MSG_GUIDE - STR_MSG_BASE)
        JMP SET_STATUS_MSG

SET_CUR_FILENAME:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
        LDY #0
SCF_LP:
        LDA (ZP_PTR_LO),Y
        STA CUR_FILENAME,Y
        BEQ SCF_RTS
        INY
        BNE SCF_LP
SCF_RTS:
        RTS

; ============================================================================
; BUILD_LINE_INDEX: Indexeer regels in TEXT_BUF ($6000) met woordafbreking
; ============================================================================
BUILD_LINE_INDEX:
        JSR INIT_RAW_TO_TEXT_PTRS
        LDA ZP_OUT_LO
        STA ZP_SRC_LO
        LDA ZP_OUT_HI
        STA ZP_SRC_HI
        LDA #0
        STA TOTAL_LINES
        STA CHAR_CNT_LO
        STA CHAR_CNT_HI

BLI_LINE_LP:
        LDX TOTAL_LINES
        CPX #MAX_LINES
        BCS BLI_DONE
        LDA ZP_SRC_HI
        CMP #$70
        BCS BLI_DONE
        LDY #0
        LDA (ZP_SRC_LO),Y
        BEQ BLI_DONE
        CMP #$0D
        BNE BLI_REC_START
        JSR INC_ZP_SRC
        JMP BLI_LINE_LP

BLI_REC_START:
        LDA ZP_SRC_LO
        STA LINE_PTR_LO,X
        LDA ZP_SRC_HI
        STA LINE_PTR_HI,X

        LDY #0
BLI_CH_LP:
        LDA (ZP_SRC_LO),Y
        BEQ BLI_AT_NUL
        CMP #$0A
        BEQ BLI_AT_LF
        CMP #$0D
        BEQ BLI_AT_CR

        INC CHAR_CNT_LO
        BNE BLI_C_OK
        INC CHAR_CNT_HI
BLI_C_OK:
        INY
        CPY #MAX_LINE_COLS
        BCC BLI_CH_LP

        STY ZP_CUR_LEN
BLI_WRAP_SP:
        CPY #38
        BCC BLI_WRAP_HARD
        DEY
        LDA (ZP_SRC_LO),Y
        CMP #' '
        BNE BLI_WRAP_SP
        STY ZP_CUR_LEN
        INY
        TYA
        BNE BLI_ADV_A

BLI_WRAP_HARD:
        LDA ZP_CUR_LEN
        BNE BLI_ADV_A

BLI_AT_CR:
        STY ZP_CUR_LEN
        INY
        LDA (ZP_SRC_LO),Y
        CMP #$0A
        BNE BLI_ADV_Y
        INY
        BNE BLI_ADV_Y

BLI_AT_LF:
        STY ZP_CUR_LEN
        INY
        BNE BLI_ADV_Y

BLI_AT_NUL:
        STY ZP_CUR_LEN
BLI_ADV_Y:
        TYA
BLI_ADV_A:
        JSR ADD_A_TO_ZP_SRC
        LDX TOTAL_LINES
        LDA ZP_CUR_LEN
        STA LINE_LEN_TBL,X
        INC TOTAL_LINES
        JMP BLI_LINE_LP

BLI_DONE:
        LDA TOTAL_LINES
        BNE BLI_RTS
        LDA #<TEXT_BUF
        STA LINE_PTR_LO
        LDA #>TEXT_BUF
        STA LINE_PTR_HI
        LDA #0
        STA LINE_LEN_TBL
        LDA #1
        STA TOTAL_LINES
BLI_RTS:
        RTS

CALC_HEX_LINES:
        LDA RAW_LEN_LO
        CLC
        ADC #15
        STA NUM_TMP_LO
        LDA RAW_LEN_HI
        ADC #0
        STA NUM_TMP_HI
        LDX #4
CHL_SH:
        LSR NUM_TMP_HI
        ROR NUM_TMP_LO
        DEX
        BNE CHL_SH
        LDA NUM_TMP_HI
        BNE CHL_MAX
        LDA NUM_TMP_LO
        BEQ CHL_MIN
        CMP #MAX_LINES
        BCC CHL_SET
CHL_MAX:
        LDA #MAX_LINES
        BNE CHL_SET
CHL_MIN:
        LDA #1
CHL_SET:
        STA TOTAL_LINES
        RTS

; ============================================================================
; Volledige Flikkervrije Scherm-Opbouw (Double-Buffered: TARGET 0 + FLIP)
; ============================================================================
REDRAW_SCREEN:
        LDX #0
RS_GUI_LP:
        LDA GUI_STREAM,X
        STA IO_GPU
        INX
        CPX #(GUI_STREAM_END - GUI_STREAM)
        BCC RS_GUI_LP
        LDA PAPER_BG
        STA IO_GPU              ; Kleur voor het grote leesvenster-papiervlak!

        ; Titelbalk tekst: "TextReader 6502 - [BESTANDSNAAM]"
        LDA #24
        LDY #4
        JSR SET_XY_LO
        LDA #$FF
        STA ZP_FG_COL
        LDA #<STR_TITLE_L
        LDY #>STR_TITLE_L
        JSR DRAW_STR_AY

        LDA #$FC
        STA ZP_FG_COL
        LDA #<CUR_FILENAME
        LDY #>CUR_FILENAME
        JSR DRAW_STR_AY

        LDA #$FF
        STA ZP_FG_COL
        LDA #']'
        JSR DRAW_CHAR_ADV

        ; Rechtsboven modus ([TEKST] of [HEX]) en Drive (D0..D3)
        LDA #$FA
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        LDA #$1F
        STA ZP_FG_COL
        LDA #<STR_MODE_TXT
        LDY #>STR_MODE_TXT
        LDX VIEW_MODE
        BEQ RS_HDR_MD
        LDA #<STR_MODE_HEX
        LDY #>STR_MODE_HEX
RS_HDR_MD:
        JSR DRAW_STR_AY
        LDA DISK_DRIVE
        JSR DRAW_DEC2

        ; Werkbalk of Geopende ESC-Menubalk op Y = 16..32
        LDA #8
        LDY #21
        JSR SET_XY_LO
        LDA #$00
        STA ZP_FG_COL
        LDA #<STR_TOOLBAR
        LDY #>STR_TOOLBAR
        LDX MENU_OPEN
        BEQ DTB_TXT
        LDA #$80
        STA ZP_FG_COL
        LDA #<STR_MENUBAR
        LDY #>STR_MENUBAR
DTB_TXT:
        JSR DRAW_STR_AY

        LDA #16
        LDY #36
        JSR SET_XY_LO
        LDA #<STR_RULER_TXT
        LDY #>STR_RULER_TXT
        LDX VIEW_MODE
        BEQ RS_RUL_DRW
        LDA #<STR_RULER_HEX
        LDY #>STR_RULER_HEX
RS_RUL_DRW:
        JSR DRAW_STR_AY

        LDA VIEW_MODE
        BNE RS_DRAW_HEX
        JSR DRAW_TEXT_ROWS
        JMP RS_AFTER_ROWS
RS_DRAW_HEX:
        JSR DRAW_HEX_ROWS
RS_AFTER_ROWS:
        JSR DRAW_SCROLLBAR
        JSR DRAW_STATUS_BAR

        LDA FILE_DLG_OPEN
        BEQ RS_FLIP
        JSR DRAW_FILE_DIALOG

RS_FLIP:
        LDA #11
        STA IO_GPU
        RTS

; ============================================================================
; Teken de 18 Zichtbare Regels in Tekst-Modus
; ============================================================================
DRAW_TEXT_ROWS:
        JSR INIT_ROW_LOOP
DTR_ROW_LP:
        LDA TOP_LINE
        CLC
        ADC ZP_SAV_ROW
        STA ZP_LINE_IDX
        CMP TOTAL_LINES
        BCS DTR_RTS

        LDA #20
        JSR SET_X_LO
        LDA SHOW_LINENUMS
        BEQ DTR_LINE_BODY

        LDA #18
        STA ZP_X_LO
        LDA ACCENT_FG
        STA ZP_FG_COL
        LDA ZP_LINE_IDX
        CLC
        ADC #1
        STA NUM_TMP_LO
        LDA #0
        STA NUM_TMP_HI
        JSR DRAW_DEC3
        LDA #56
        STA ZP_X_LO

DTR_LINE_BODY:
        LDX ZP_LINE_IDX
        LDA LINE_PTR_LO,X
        STA ZP_SRC_LO
        LDA LINE_PTR_HI,X
        STA ZP_SRC_HI
        LDA LINE_LEN_TBL,X
        STA ZP_CUR_LEN
        BEQ DTR_NEXT_ROW

        LDA PAPER_FG
        STA ZP_FG_COL
        LDY #0
        LDA (ZP_SRC_LO),Y
        CMP #'#'
        BEQ DTR_HEAD_COL
        CMP #'='
        BEQ DTR_HEAD_COL
        CMP #'['
        BEQ DTR_HEAD_COL
        CMP #'*'
        BEQ DTR_ACC_COL
        CMP #'-'
        BNE DTR_CH_LP
DTR_ACC_COL:
        LDA ACCENT_FG
        BNE DTR_SET_COL
DTR_HEAD_COL:
        LDA HEAD_FG
DTR_SET_COL:
        STA ZP_FG_COL

DTR_CH_LP:
        STY ZP_SAV_COL
        LDA (ZP_SRC_LO),Y
        CMP #$21
        BCC DTR_SKIP_SP
        JSR DRAW_CHAR_AT_XY
DTR_SKIP_SP:
        JSR ADV_X_8
        LDY ZP_SAV_COL
        INY
        CPY ZP_CUR_LEN
        BCC DTR_CH_LP

DTR_NEXT_ROW:
        JSR NEXT_ROW_Y
        BCC DTR_ROW_LP
DTR_RTS:
        RTS

; ============================================================================
; Teken de 18 Zichtbare Rijen in Hex + ASCII Dump Modus (16 bytes per rij)
; ============================================================================
DRAW_HEX_ROWS:
        JSR INIT_ROW_LOOP
DHR_ROW_LP:
        LDA TOP_LINE
        CLC
        ADC ZP_SAV_ROW
        STA ZP_LINE_IDX
        CMP TOTAL_LINES
        BCS DHR_RTS

        LDA ZP_LINE_IDX
        STA NUM_TMP_LO
        LDA #0
        ASL NUM_TMP_LO
        ROL A
        ASL NUM_TMP_LO
        ROL A
        ASL NUM_TMP_LO
        ROL A
        ASL NUM_TMP_LO
        ROL A
        STA NUM_TMP_HI

        CLC
        LDA NUM_TMP_LO
        ADC #<RAW_BUF
        STA ZP_SRC_LO
        LDA NUM_TMP_HI
        ADC #>RAW_BUF
        STA ZP_SRC_HI

        LDA #16
        JSR SET_X_LO
        LDA HEAD_FG
        STA ZP_FG_COL
        LDA #'$'
        JSR DRAW_CHAR_ADV
        CLC
        LDA NUM_TMP_LO
        ADC RAW_BASE_LO
        PHA
        LDA NUM_TMP_HI
        ADC RAW_BASE_HI
        JSR DRAW_HEX8
        PLA
        JSR DRAW_HEX8
        LDA #':'
        JSR DRAW_CHAR_ADV

        LDA #72
        STA ZP_X_LO
        LDA PAPER_FG
        STA ZP_FG_COL
        LDY #0
DHR_HEX_LP:
        STY ZP_SAV_COL
        LDA (ZP_SRC_LO),Y
        JSR DRAW_HEX8
        JSR ADV_X_8
        LDY ZP_SAV_COL
        INY
        CPY #16
        BCC DHR_HEX_LP

        LDA #$D0
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        LDA ACCENT_FG
        STA ZP_FG_COL
        LDA #'|'
        JSR DRAW_CHAR_ADV
        LDA PAPER_FG
        STA ZP_FG_COL

        LDY #0
DHR_ASC_LP:
        STY ZP_SAV_COL
        LDA (ZP_SRC_LO),Y
        CMP #$20
        BCC DHR_DOT
        CMP #$7F
        BCC DHR_PRT
DHR_DOT:
        LDA #'.'
DHR_PRT:
        JSR DRAW_CHAR_ADV
        LDY ZP_SAV_COL
        INY
        CPY #16
        BCC DHR_ASC_LP

        LDA ACCENT_FG
        STA ZP_FG_COL
        LDA #'|'
        JSR DRAW_CHAR_ADV

        JSR NEXT_ROW_Y
        BCC DHR_ROW_LP
DHR_RTS:
        RTS

; ============================================================================
; Teken Rechter Scrollbar & Onderste Statusbalk
; ============================================================================
DRAW_SCROLLBAR:
        LDA TOP_LINE
        LSR A
        CLC
        ADC #48
        STA ZP_Y_LO
        LDA #2
        STA IO_GPU
        LDA #$6F
        STA IO_GPU
        LDA #$02
        STA IO_GPU
        LDA ZP_Y_LO
        STA IO_GPU
        LDX #0
DSB_TAIL:
        LDA SB_RECT_TAIL,X
        STA IO_GPU
        INX
        CPX #6
        BCC DSB_TAIL
        RTS

DRAW_STATUS_BAR:
        LDA #10
        JSR SET_X_LO
        LDA #$5B
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$FF
        STA ZP_FG_COL

        LDA #<STR_ST_LINE
        LDY #>STR_ST_LINE
        JSR DRAW_STR_AY

        LDA TOP_LINE
        CLC
        ADC #1
        STA NUM_TMP_LO
        LDA #0
        STA NUM_TMP_HI
        JSR DRAW_DEC3

        LDA #'/'
        JSR DRAW_CHAR_ADV

        LDA TOTAL_LINES
        STA NUM_TMP_LO
        LDA #0
        STA NUM_TMP_HI
        JSR DRAW_DEC3

        LDA #<STR_ST_CHARS
        LDY #>STR_ST_CHARS
        JSR DRAW_STR_AY

        LDA CHAR_CNT_LO
        STA NUM_TMP_LO
        LDA CHAR_CNT_HI
        STA NUM_TMP_HI
        JSR DRAW_DEC4

        LDA #$A4
        STA ZP_X_LO
        LDA #$01
        STA ZP_X_HI
        LDA #$FC
        STA ZP_FG_COL
        LDA STATUS_MSG_LO
        LDY STATUS_MSG_HI
        JMP DRAW_STR_AY

; ============================================================================
; Teken het Grafische SD-Kaart Bestands-Kiezer Venster (Modal Overlay)
; ============================================================================
DRAW_FILE_DIALOG:
        LDX #0
DFD_BOX_LP:
        LDA DLG_BOX_STREAM,X
        STA IO_GPU
        INX
        CPX #(DLG_BOX_STREAM_END - DLG_BOX_STREAM)
        BCC DFD_BOX_LP

        LDA #116
        LDY #41
        JSR SET_XY_LO
        LDA #$FC
        STA ZP_FG_COL
        LDA #<STR_DLG_HDR
        LDY #>STR_DLG_HDR
        JSR DRAW_STR_AY
        LDA DISK_DRIVE
        JSR DRAW_DEC2

        LDA #116
        LDY #56
        JSR SET_XY_LO
        LDA #$1F
        STA ZP_FG_COL
        LDA #<STR_DLG_COLS
        LDY #>STR_DLG_COLS
        JSR DRAW_STR_AY

        LDA #0
        STA ZP_SAV_ROW
        STA ZP_Y_HI
        LDA #72
        STA ZP_Y_LO
DFD_SLOT_LP:
        LDA #108
        JSR SET_X_LO
        LDA #$FF
        STA ZP_FG_COL
        LDA #' '
        LDX ZP_SAV_ROW
        CPX DLG_SEL
        BNE DFD_DRAW_SLOT
        LDA #$FC
        STA ZP_FG_COL
        LDA #'>'
DFD_DRAW_SLOT:
        JSR DRAW_CHAR_ADV
        LDA ZP_SAV_ROW
        JSR DRAW_DEC2
        JSR ADV_X_16

        LDA ZP_SAV_ROW
        JSR GET_DIR_SLOT_PTR
        JSR CHECK_SLOT_MAGIC
        BNE DFD_SLOT_EMPTY

        LDY #4
DFD_FN_LP:
        LDA (ZP_TMP),Y
        BEQ DFD_FN_PAD
        JSR DRAW_CHAR_ADV
        INY
        CPY #16
        BCC DFD_FN_LP
        BCS DFD_SLOT_TYPE
DFD_FN_PAD:
        JSR ADV_X_8
        INY
        CPY #16
        BCC DFD_FN_PAD

DFD_SLOT_TYPE:
        JSR ADV_X_8
        LDY #22
        LDA (ZP_TMP),Y
        CMP #'D'
        BEQ DFD_T_DIR
        CMP #'M'
        BEQ DFD_T_BAS
        LDY #24
        LDA (ZP_TMP),Y
        CMP #$60
        BEQ DFD_T_TXT
        LDA #<STR_T_ASM
        LDY #>STR_T_ASM
        BNE DFD_T_OUT
DFD_T_TXT:
        LDA #<STR_T_TXT
        LDY #>STR_T_TXT
        BNE DFD_T_OUT
DFD_T_BAS:
        LDA #<STR_T_BAS
        LDY #>STR_T_BAS
        BNE DFD_T_OUT
DFD_T_DIR:
        LDA #<STR_T_DIR
        LDY #>STR_T_DIR
        JSR DRAW_STR_AY
        JMP DFD_NEXT_SLOT

DFD_T_OUT:
        JSR DRAW_STR_AY
        LDA #'$'
        JSR DRAW_CHAR_ADV
        LDY #21
        LDA (ZP_TMP),Y
        JSR DRAW_HEX8
        LDY #20
        LDA (ZP_TMP),Y
        JSR DRAW_HEX8
        JMP DFD_NEXT_SLOT

DFD_SLOT_EMPTY:
        LDA #<STR_T_EMPTY
        LDY #>STR_T_EMPTY
        JSR DRAW_STR_AY

DFD_NEXT_SLOT:
        CLC
        LDA ZP_Y_LO
        ADC #15
        STA ZP_Y_LO
        BCC DFD_Y_OK
        INC ZP_Y_HI
DFD_Y_OK:
        INC ZP_SAV_ROW
        LDA ZP_SAV_ROW
        CMP #15
        BCC DFD_SLOT_LP

        LDA #112
        JSR SET_X_LO
        LDA #$30
        STA ZP_Y_LO
        LDA #$01
        STA ZP_Y_HI
        LDA #$FC
        STA ZP_FG_COL
        LDA #<STR_DLG_FOOT
        LDY #>STR_DLG_FOOT
        JMP DRAW_STR_AY

; ============================================================================
; Hulproutines voor SD, Kleuren, Getallen & GPU Tekst
; ============================================================================
SET_XY_LO:
        STY ZP_Y_LO
        LDY #0
        STY ZP_Y_HI
SET_X_LO:
        STA ZP_X_LO
        LDA #0
        STA ZP_X_HI
        RTS

APPLY_THEME:
        LDX THEME_IDX
        LDA THEME_BG_TBL,X
        STA PAPER_BG
        LDA THEME_FG_TBL,X
        STA PAPER_FG
        LDA THEME_HD_TBL,X
        STA HEAD_FG
        LDA THEME_AC_TBL,X
        STA ACCENT_FG
        RTS

SET_STATUS_MSG:
        CLC
        ADC #<STR_MSG_BASE
        STA STATUS_MSG_LO
        LDA #0
        ADC #>STR_MSG_BASE
        STA STATUS_MSG_HI
        RTS

GET_DIR_SLOT_PTR:
        STA ZP_TMP
        LDA #0
        STA ZP_TMP+1
        LDY #5
GDSP_LP:
        ASL ZP_TMP
        ROL ZP_TMP+1
        DEY
        BNE GDSP_LP
        LDA ZP_TMP+1
        CLC
        ADC #>DIR_BUF
        STA ZP_TMP+1
        RTS

CHECK_SLOT_MAGIC:
        LDY #0
        LDA (ZP_TMP),Y
        CMP #'B'
        BNE CSM_NO
        INY
        LDA (ZP_TMP),Y
        CMP #'B'
        BNE CSM_NO
        INY
        LDA (ZP_TMP),Y
        CMP #'C'
        BNE CSM_NO
        INY
        LDA (ZP_TMP),Y
        CMP #'!'
CSM_NO:
        RTS

SETUP_SLOT_SECTOR:
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
        AND #$3F
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

INIT_ROW_LOOP:
        LDA #0
        STA ZP_SAV_ROW
        STA ZP_Y_HI
        LDA #50
        STA ZP_Y_LO
        RTS

NEXT_ROW_Y:
        CLC
        LDA ZP_Y_LO
        ADC #16
        STA ZP_Y_LO
        BCC NRY_INC
        INC ZP_Y_HI
NRY_INC:
        INC ZP_SAV_ROW
        LDA ZP_SAV_ROW
        CMP #VISIBLE_ROWS
        RTS

INC_ZP_SRC:
        INC ZP_SRC_LO
        BNE IZS_RTS
        INC ZP_SRC_HI
IZS_RTS:
        RTS

INC_ZP_OUT:
        INC ZP_OUT_LO
        BNE IZO_RTS
        INC ZP_OUT_HI
IZO_RTS:
        RTS

ADD_A_TO_ZP_SRC:
        CLC
        ADC ZP_SRC_LO
        STA ZP_SRC_LO
        BCC AAZS_RTS
        INC ZP_SRC_HI
AAZS_RTS:
        RTS

APPEND_CHAR_TO_OUT:
        STY ZP_SAV_COL
        PHA
        LDA ZP_OUT_HI
        CMP #$70
        BCS ACTO_SKIP
        PLA
        LDY #0
        STA (ZP_OUT_LO),Y
        LDY ZP_SAV_COL
        JMP INC_ZP_OUT
ACTO_SKIP:
        PLA
        LDY ZP_SAV_COL
        RTS

; Converteer 16-bit NUM_TMP_LO/HI naar 5 ASCII-cijfers in DEC_BUF+0..4
CALC_DEC5:
        LDX #0
CD5_LP:
        LDY #'0'
CD5_SUB:
        LDA NUM_TMP_LO
        CMP POW10_LO,X
        LDA NUM_TMP_HI
        SBC POW10_HI,X
        BCC CD5_DIG
        LDA NUM_TMP_LO
        SBC POW10_LO,X
        STA NUM_TMP_LO
        LDA NUM_TMP_HI
        SBC POW10_HI,X
        STA NUM_TMP_HI
        INY
        BNE CD5_SUB
CD5_DIG:
        TYA
        STA DEC_BUF,X
        INX
        CPX #5
        BCC CD5_LP
        RTS

APPEND_DEC16_TO_OUT:
        JSR CALC_DEC5
        LDX #1
AD16_OUT:
        LDA DEC_BUF,X
        STX ZP_LINE_IDX
        JSR APPEND_CHAR_TO_OUT
        LDX ZP_LINE_IDX
        INX
        CPX #5
        BCC AD16_OUT
        RTS

DRAW_DEC2:
        STA NUM_TMP_LO
        LDA #0
        STA NUM_TMP_HI
        LDX #3
        BNE DD_FROM_X
DRAW_DEC3:
        LDX #2
        BNE DD_FROM_X
DRAW_DEC4:
        LDX #1
DD_FROM_X:
        STX ZP_SAV_COL
        JSR CALC_DEC5
        LDX ZP_SAV_COL
DD_PRT_LP:
        LDA DEC_BUF,X
        STX ZP_SAV_COL
        JSR DRAW_CHAR_ADV
        LDX ZP_SAV_COL
        INX
        CPX #5
        BCC DD_PRT_LP
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

DRAW_STR_AY:
        STA ZP_PTR_LO
        STY ZP_PTR_HI
DRAW_ZP_STR:
        LDY #0
        LDA (ZP_PTR_LO),Y
        BEQ DZS_RTS
        INC ZP_PTR_LO
        BNE DZS_CH
        INC ZP_PTR_HI
DZS_CH:
        JSR DRAW_CHAR_ADV
        JMP DRAW_ZP_STR
DZS_RTS:
        RTS

ADV_X_16:
        JSR ADV_X_8
        JMP ADV_X_8

DRAW_CHAR_ADV:
        JSR DRAW_CHAR_AT_XY
ADV_X_8:
        CLC
        LDA ZP_X_LO
        ADC #8
        STA ZP_X_LO
        BCC DCAD_RTS
        INC ZP_X_HI
DCAD_RTS:
        RTS

DRAW_CHAR_AT_XY:
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
        RTS

; ============================================================================
; Sneltoets-Tabellen (Werkt zowel in Leesvenster als in ESC-Menu 1..7!)
; ============================================================================
KEY_TBL:
        .BYTE '8', 'W', '2', 'S', '4', 'A', '6', 'D', ' ', 'T'
        .BYTE 'E', $0D, 'O', '1', 'V', '3', 'L', 'H', '5', 'R'
        .BYTE 'C', '7', 'I', 'M', 'Q'
KEY_TBL_END:

KEY_ACT_LO:
        .BYTE <ACT_UP, <ACT_UP, <ACT_DOWN, <ACT_DOWN, <ACT_PAGE_UP, <ACT_PAGE_UP, <ACT_PAGE_DOWN, <ACT_PAGE_DOWN, <ACT_PAGE_DOWN, <ACT_HOME
        .BYTE <ACT_END, <KEY_ENTER_ACT, <KEY_ENTER_ACT, <OPEN_FILE_DIALOG, <ACT_NEXT_DRIVE, <ACT_LOAD_WRITER, <ACT_LOAD_WRITER, <ACT_TOGGLE_HEX, <ACT_TOGGLE_LINENUMS, <ACT_TOGGLE_LINENUMS
        .BYTE <ACT_NEXT_THEME, <ACT_LOAD_GUIDE, <ACT_LOAD_GUIDE, <ACT_TOGGLE_MENU, <EXIT_TO_BASIC_OR_MC

KEY_ACT_HI:
        .BYTE >ACT_UP, >ACT_UP, >ACT_DOWN, >ACT_DOWN, >ACT_PAGE_UP, >ACT_PAGE_UP, >ACT_PAGE_DOWN, >ACT_PAGE_DOWN, >ACT_PAGE_DOWN, >ACT_HOME
        .BYTE >ACT_END, >KEY_ENTER_ACT, >KEY_ENTER_ACT, >OPEN_FILE_DIALOG, >ACT_NEXT_DRIVE, >ACT_LOAD_WRITER, >ACT_LOAD_WRITER, >ACT_TOGGLE_HEX, >ACT_TOGGLE_LINENUMS, >ACT_TOGGLE_LINENUMS
        .BYTE >ACT_NEXT_THEME, >ACT_LOAD_GUIDE, >ACT_LOAD_GUIDE, >ACT_TOGGLE_MENU, >EXIT_TO_BASIC_OR_MC

POW10_LO:       .BYTE <10000, <1000, <100, <10, <1
POW10_HI:       .BYTE >10000, >1000, >100, >10, >1

; 4 Thema's: 0=Klassiek Wit Papier, 1=Dark Mode, 2=Retro Amber, 3=Matrix Groen
THEME_BG_TBL:   .BYTE $FF, $00, $FE, $00
THEME_FG_TBL:   .BYTE $00, $FF, $00, $1C
THEME_HD_TBL:   .BYTE $03, $FC, $E0, $FF
THEME_AC_TBL:   .BYTE $49, $1F, $84, $10

GPU_INIT_STREAM:
        .BYTE 12, 1                     ; TARGET 1
        .BYTE 21, 0, 0, 0, 0, 0, 0, 0   ; BIGSPR 0 uit
        .BYTE 21, 1, 0, 0, 0, 0, 0, 0   ; BIGSPR 1 uit
        .BYTE 15, 0, 0, 0, 0            ; SCROLL 0, 0
GPU_INIT_STREAM_END:

GUI_STREAM:
        .BYTE 12, 0                     ; TARGET 0 (backbuffer)
        .BYTE 2, 0,0, 16,0, $80,$02, 17,0, $B6
        .BYTE 2, 0,0, 33,0, $80,$02, $35,$01, $49
        .BYTE 2, 0,0, 0,0, $80,$02, 16,0, $0B
        .BYTE 2, 8,0, 3,0, 10,0, 10,0, $1F
        .BYTE 2, 12,0, 34,0, $6C,$02, 11,0, $DF
        .BYTE 2, 16,0, 50,0, $5E,$02, $24,$01, $00
        .BYTE 2, $6E,$02, 46,0, 10,0, $24,$01, $00
        .BYTE 2, 0,0, $56,$01, $80,$02, 18,0, $0B
        .BYTE 3, 0,0, $56,$01, $7F,$02, $56,$01, $1F
        .BYTE 2, 12,0, 46,0, $5E,$02, $24,$01
GUI_STREAM_END:

SB_RECT_TAIL:
        .BYTE 0, 8, 0, 26, 0, $1F

DLG_BOX_STREAM:
        .BYTE 2, 102,0, 40,0, $BC,$01, $1A,$01, $00
        .BYTE 2, 96,0,  35,0, $BC,$01, $1A,$01, $1F
        .BYTE 2, 98,0,  37,0, $B8,$01, $16,$01, $0B
        .BYTE 3, 98,0,  67,0, $19,$02, 67,0,    $1F
        .BYTE 3, 98,0,  $2B,$01, $19,$02, $2B,$01, $1F
DLG_BOX_STREAM_END:

STR_TITLE_L:    .ASCIIZ "TextReader 6502 - ["
STR_MODE_TXT:   .ASCIIZ "[TEKST] D"
STR_MODE_HEX:   .ASCIIZ "[HEX]   D"

STR_TOOLBAR:
        .ASCIIZ "O/ENT:Open  PIJLTJES:Scroll  H:Hex/Txt  R:Regelnr  C:Thema  L:Writer  ESC:Menu"
STR_MENUBAR:
        .ASCIIZ "[1]OpenSD [V]Drive [3]WriterDoc [H]Hex/Txt [R]Regelnr [C]Thema [7]Help [ESC]MC"

STR_RULER_TXT:
        .ASCIIZ "RGL  TEKST (O=OPEN, W/S=SCROLL, A/D=PAGINA, H=HEX, C=THEMA)"
STR_RULER_HEX:
        .ASCIIZ "ADRES  00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  |0123456789ABCDEF|"

STR_ST_LINE:    .ASCIIZ "RGL:"
STR_ST_CHARS:   .ASCIIZ " TEKENS:"

STR_DLG_HDR:    .ASCIIZ "OPEN BESTAND VAN SD / DRIVE D"
STR_DLG_COLS:   .ASCIIZ "  SL  BESTANDSNAAM  TYPE       BYTES"
STR_DLG_FOOT:   .ASCIIZ "W/S:Kies  ENTER:Open  D:Drive  L:Writer  ESC:Sluit"

STR_T_TXT:      .ASCIIZ "TXT Tekst  "
STR_T_BAS:      .ASCIIZ "BAS BASIC  "
STR_T_ASM:      .ASCIIZ "ASM 6502   "
STR_T_DIR:      .ASCIIZ "<MAP>      --DIR--"
STR_T_EMPTY:    .ASCIIZ "- leeg -"

STR_FN_GUIDE:   .ASCIIZ "HANDLEIDING"
STR_FN_WRITER:  .ASCIIZ "WRITER.DOC"

STR_MSG_BASE:
STR_MSG_READY:  .ASCIIZ "O=OPEN | PIJL=SCROLL"
STR_MSG_PICK:   .ASCIIZ "KIES BESTAND + ENTER"
STR_MSG_LOADED: .ASCIIZ "TEKST GELADEN!"
STR_MSG_BAS:    .ASCIIZ "BASIC GELADEN!"
STR_MSG_BIN:    .ASCIIZ "BIN IN HEX-MODUS!"
STR_MSG_GUIDE:  .ASCIIZ "HULP ACTIEF"
STR_MSG_EMPTY:  .ASCIIZ "SLOT IS LEEG!"

; ============================================================================
; Ingebouwd Nederlandstalig Tekstdocument (wordt getoond als voorbeeld/hulp)
; ============================================================================
BUILTIN_TEXT:
        .BYTE "# MINIGPU TEXTREADER 6502 - HANDLEIDING", $0A
        .BYTE "========================================", $0A
        .BYTE "Lees .TXT, .BAS, LibreWriter & 6502 .ASM vanaf SD-kaart!", $0A, $0A
        .BYTE "# SNELTOETSEN", $0A
        .BYTE "* O / ENTER : Open SD Bestands-Kiezer (D0..D3 & Mappen)", $0A
        .BYTE "* W/S / Pijl: Scroll 1 regel | A/D/Spatie: Pagina (PgUp/Dn)", $0A
        .BYTE "* T / E     : Begin / Einde  | H : Hex + ASCII Dump Modus", $0A
        .BYTE "* R : Regelnummers | C : Thema (4x) | L : LibreWriter Doc", $0A
        .BYTE "* ESC : Menubalk / Terug naar BASIC of Midnight Commander", $0A
        .BYTE 0
BUILTIN_TEXT_END:
