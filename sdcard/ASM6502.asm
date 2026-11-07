; ============================================================================
; ASM6502.asm - 6502 Machinecode Demo voor Tang Nano 20K MiniGPU ($8000)
; Starten vanaf SD-kaart in BASIC met:  BRUN ASM6502  of  CALL $8000
; ============================================================================
        ORG $8000

START:
        ; Wis eerst de groene terminaltekst (CLS = karakter 12 naar IO_TERM $A001)
        LDA #12
        STA IO_TERM

        ; Zet GPU op TARGET 1 (frontbuffer) en maak scherm donkerblauw ($02)
        LDA #12
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #1
        STA IO_GPU
        LDA #$02
        STA IO_GPU

        ; Teken 32 horizontale regenboog/copper-balken op volle 6502-snelheid!
        LDX #0
BAR_LOOP:
        LDA #2          ; GPU commando 2 = RECT (10 bytes: cmd, x, y, w, h, kleur)
        STA IO_GPU
        LDA #20         ; x = 20
        STA IO_GPU
        LDA #0
        STA IO_GPU

        TXA             ; y = 44 + X * 8
        ASL A
        ASL A
        ASL A
        CLC
        ADC #44
        STA IO_GPU
        LDA #0
        ADC #0
        STA IO_GPU

        LDA #$58        ; w = 600 ($0258)
        STA IO_GPU
        LDA #$02
        STA IO_GPU

        LDA #6          ; h = 6
        STA IO_GPU
        LDA #0
        STA IO_GPU

        TXA             ; kleur = X * 4 + $15
        ASL A
        ASL A
        ADC #$15
        STA IO_GPU

        INX
        CPX #32
        BCC BAR_LOOP

        ; Stuur het middenvenster en de 3 gekleurde schijven (50 bytes) naar de GPU
        LDX #0
STREAM_LOOP:
        LDA GPU_DATA,X
        STA IO_GPU
        INX
        CPX #GPU_DATA_END - GPU_DATA
        BCC STREAM_LOOP

        ; Teken GPU-tekst (cmd 8 = DRAW_CHAR, 10 bytes per karakter) op (100 + X*8, 125)
        LDX #0
TXT_LOOP:
        LDA MSG,X
        BEQ DONE
        PHA
        LDA #8          ; cmd 8 = DRAW_CHAR
        STA IO_GPU
        TXA             ; x = 100 + X * 8
        ASL A
        ASL A
        ASL A
        CLC
        ADC #100
        STA IO_GPU
        LDA #0
        ADC #0
        STA IO_GPU
        LDA #125        ; y = 125
        STA IO_GPU
        LDA #0
        STA IO_GPU
        PLA             ; ASCII karakter
        STA IO_GPU
        LDA #0
        STA IO_GPU
        STA IO_GPU
        STA IO_GPU
        LDA #$FC        ; Kleur = geel ($FC)
        STA IO_GPU
        INX
        BNE TXT_LOOP

DONE:
        LDA #65
        RTS

GPU_DATA:
        ; RECT 60, 100, 520 ($0208), 145, $00 (Zwart kader - 10 bytes)
        .BYTE 2, 60, 0, 100, 0, $08, $02, 145, 0, $00
        ; RECT 60, 100, 520 ($0208), 8, $E0 (Rode bovenbalk - 10 bytes)
        .BYTE 2, 60, 0, 100, 0, $08, $02, 8, 0, $E0
        ; 3 Gekleurde schijven (DISK: cmd=5, x, y, r, 0, 0, kleur - 10 bytes elk!)
        .BYTE 5, 160, 0, 200, 0, 26, 0, 0, 0, $1F
        .BYTE 5, $40, $01, 200, 0, 26, 0, 0, 0, $FC
        .BYTE 5, $E0, $01, 200, 0, 26, 0, 0, 0, $E2
GPU_DATA_END:

MSG:
        .ASCIIZ "6502 ASM @ $8000 (SD-KAART!)"
