; ============================================================================
; STER6502.asm - 6502 Assembly Concentrische Neon Cirkels & Ster-Demo ($8000)
; Starten vanaf SD-kaart in BASIC met:  BRUN STER6502  of  CALL $8000
; ============================================================================
        ORG $8000

START:
        ; Wis eerst de groene terminaltekst (CLS = karakter 12 naar IO_TERM $A001)
        LDA #12
        STA IO_TERM

        ; TARGET 1 & CLEAR $00 (Zwart scherm)
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #0
        STA IO_GPU

        ; Teken 25 concentrische neon-cirkels vanuit het midden (320, 180)
        LDX #1
RING_LOOP:
        LDA #4          ; GPU commando 4 = CIRCLE (10 bytes: cmd, x, y, r, 0, 0, kleur)
        STA IO_GPU
        LDA #$40        ; x = 320 ($0140)
        STA IO_GPU
        LDA #$01
        STA IO_GPU
        LDA #180        ; y = 180
        STA IO_GPU
        LDA #0
        STA IO_GPU

        TXA             ; r = X * 6
        ASL A
        STA $42
        ASL A
        CLC
        ADC $42
        STA IO_GPU
        LDA #0
        STA IO_GPU

        ; 2 dummy bytes (arg3_lo, arg3_hi) voor het 10-byte GPU pakket!
        STA IO_GPU
        STA IO_GPU

        TXA             ; kleur = X * 9 + $1C
        ASL A
        ASL A
        ASL A
        ADC #$1C
        STA IO_GPU

        INX
        CPX #26
        BCC RING_LOOP

        ; Teken midden-disk en titelbox via STREAM (20 bytes)
        LDX #0
BOX_LOOP:
        LDA STREAM,X
        STA IO_GPU
        INX
        CPX #STREAM_END - STREAM
        BCC BOX_LOOP

        ; Teken GPU-tekst (cmd 8 = DRAW_CHAR) op (116 + X*8, 22)
        LDX #0
TXT_LOOP:
        LDA MSG,X
        BEQ DONE
        PHA
        LDA #8
        STA IO_GPU
        TXA
        ASL A
        ASL A
        ASL A
        CLC
        ADC #116
        STA IO_GPU
        LDA #0
        ADC #0
        STA IO_GPU
        LDA #22
        STA IO_GPU
        LDA #0
        STA IO_GPU
        PLA
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA #$3F
        STA IO_GPU
        INX
        BNE TXT_LOOP

DONE:
        LDA #99
        RTS

STREAM:
        ; DISK 320 ($0140), 180, 12, $FC (Gele kern in het midden - 10 bytes)
        .BYTE 5, $40, $01, 180, 0, 12, 0, 0, 0, $FC
        ; RECT 90, 14, 460 ($01CC), 24, $08 (Groene balk bovenin - 10 bytes)
        .BYTE 2, 90, 0, 14, 0, $CC, $01, 24, 0, $08
STREAM_END:

MSG:
        .ASCIIZ "STER6502: 6502 ASM NEON RINGS @ $8000"
