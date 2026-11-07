import os
import struct

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(BASE_DIR, "src")

# ============================================================================
# Two-Pass 6502 Assembler in Python for MiniGPU-BASIC 1.0 ($E000 - $FFFF)
# ============================================================================

class Asm6502:
    def __init__(self, org=0xE000, size=8192):
        self.org = org
        self.size = size
        self.ops = []
        self.labels = {}

    def set_org(self, addr):
        self.ops.append(("ORG", addr))

    def pin_abi(self, addr, name):
        self.ops.append(("PIN_ABI", addr, name))

    def label(self, name):
        self.ops.append(("LABEL", name))

    def emit(self, *bytes_list):
        self.ops.append(("BYTES", list(bytes_list)))

    def ascii_z(self, text):
        self.ops.append(("BYTES", [ord(c) for c in text] + [0]))

    def word(self, val):
        self.ops.append(("WORD", val))

    def inst(self, opcode, operand=None, size=1):
        self.ops.append(("INST", opcode, operand, size))

    # --- Convenience 6502 Instructions ---
    def lda_imm(self, v): self.inst(0xA9, v, 2)
    def ldx_imm(self, v): self.inst(0xA2, v, 2)
    def ldy_imm(self, v): self.inst(0xA0, v, 2)
    def lda_zp(self, a):  self.inst(0xA5, a, 2)
    def ldx_zp(self, a):  self.inst(0xA6, a, 2)
    def ldy_zp(self, a):  self.inst(0xA4, a, 2)
    def sta_zp(self, a):  self.inst(0x85, a, 2)
    def stx_zp(self, a):  self.inst(0x86, a, 2)
    def sty_zp(self, a):  self.inst(0x84, a, 2)
    def lda_abs(self, a): self.inst(0xAD, a, 3)
    def ldx_abs(self, a): self.inst(0xAE, a, 3)
    def ldy_abs(self, a): self.inst(0xAC, a, 3)
    def ldy_abx(self, a): self.inst(0xBC, a, 3)
    def sta_abs(self, a): self.inst(0x8D, a, 3)
    def stx_abs(self, a): self.inst(0x8E, a, 3)
    def sty_abs(self, a): self.inst(0x8C, a, 3)
    def lda_abx(self, a): self.inst(0xBD, a, 3)
    def lda_aby(self, a): self.inst(0xB9, a, 3)
    def sta_abx(self, a): self.inst(0x9D, a, 3)
    def sta_aby(self, a): self.inst(0x99, a, 3)
    def lda_iny(self, z): self.inst(0xB1, z, 2)
    def sta_iny(self, z): self.inst(0x91, z, 2)

    def inc_zp(self, z):  self.inst(0xE6, z, 2)
    def dec_zp(self, z):  self.inst(0xC6, z, 2)
    def inc_abs(self, a): self.inst(0xEE, a, 3)
    def dec_abs(self, a): self.inst(0xCE, a, 3)

    def inx(self): self.inst(0xE8, None, 1)
    def dex(self): self.inst(0xCA, None, 1)
    def iny(self): self.inst(0xC8, None, 1)
    def dey(self): self.inst(0x88, None, 1)

    def tax(self): self.inst(0xAA, None, 1)
    def txa(self): self.inst(0x8A, None, 1)
    def tay(self): self.inst(0xA8, None, 1)
    def tya(self): self.inst(0x98, None, 1)
    def tsx(self): self.inst(0xBA, None, 1)
    def txs(self): self.inst(0x9A, None, 1)

    def pha(self): self.inst(0x48, None, 1)
    def pla(self): self.inst(0x68, None, 1)
    def php(self): self.inst(0x08, None, 1)
    def plp(self): self.inst(0x28, None, 1)

    def clc(self): self.inst(0x18, None, 1)
    def sec(self): self.inst(0x38, None, 1)
    def cli(self): self.inst(0x58, None, 1)
    def sei(self): self.inst(0x78, None, 1)
    def cld(self): self.inst(0xD8, None, 1)
    def nop(self): self.inst(0xEA, None, 1)
    def rts(self): self.inst(0x60, None, 1)

    def adc_imm(self, v): self.inst(0x69, v, 2)
    def adc_zp(self, z):  self.inst(0x65, z, 2)
    def adc_abs(self, a): self.inst(0x6D, a, 3)
    def adc_abx(self, a): self.inst(0x7D, a, 3)
    def sbc_imm(self, v): self.inst(0xE9, v, 2)
    def sbc_zp(self, z):  self.inst(0xE5, z, 2)
    def sbc_abx(self, a): self.inst(0xFD, a, 3)

    def and_imm(self, v): self.inst(0x29, v, 2)
    def and_zp(self, z):  self.inst(0x25, z, 2)
    def ora_imm(self, v): self.inst(0x09, v, 2)
    def ora_zp(self, z):  self.inst(0x05, z, 2)
    def ora_abs(self, a): self.inst(0x0D, a, 3)
    def eor_imm(self, v): self.inst(0x49, v, 2)
    def eor_zp(self, z):  self.inst(0x45, z, 2)

    def asl_a(self):      self.inst(0x0A, None, 1)
    def lsr_a(self):      self.inst(0x4A, None, 1)
    def rol_a(self):      self.inst(0x2A, None, 1)
    def ror_a(self):      self.inst(0x6A, None, 1)
    def asl_zp(self, z):  self.inst(0x06, z, 2)
    def lsr_zp(self, z):  self.inst(0x46, z, 2)
    def rol_zp(self, z):  self.inst(0x26, z, 2)
    def ror_zp(self, z):  self.inst(0x66, z, 2)

    def cmp_imm(self, v): self.inst(0xC9, v, 2)
    def cmp_zp(self, z):  self.inst(0xC5, z, 2)
    def cmp_abs(self, a): self.inst(0xCD, a, 3)
    def cmp_abx(self, a): self.inst(0xDD, a, 3)
    def cpx_imm(self, v): self.inst(0xE0, v, 2)
    def cpx_zp(self, z):  self.inst(0xE4, z, 2)
    def cpy_imm(self, v): self.inst(0xC0, v, 2)
    def cpy_zp(self, z):  self.inst(0xC4, z, 2)
    def bit_zp(self, z):  self.inst(0x24, z, 2)

    def jmp(self, target): self.inst(0x4C, target, 3)
    def jsr(self, target): self.inst(0x20, target, 3)

    def beq(self, target): self.inst(0xF0, target, 2, )
    def bne(self, target): self.inst(0xD0, target, 2)
    def bcs(self, target): self.inst(0xB0, target, 2)
    def bcc(self, target): self.inst(0x90, target, 2)
    def bmi(self, target): self.inst(0x30, target, 2)
    def bpl(self, target): self.inst(0x10, target, 2)

    def resolve(self, val):
        if isinstance(val, int):
            return val
        if isinstance(val, str):
            if val.startswith("<"):
                return self.labels[val[1:]] & 0xFF
            if val.startswith(">"):
                return (self.labels[val[1:]] >> 8) & 0xFF
            return self.labels[val]
        raise ValueError(f"Unknown operand: {val}")

    def assemble(self, ext_org=0xA400, ext_size=3072):
        # Multi-pass branch relaxation: automatically upgrade out-of-range branches to 5-byte (B!cc +3; JMP target)
        while True:
            pc = self.org
            for item in self.ops:
                kind = item[0]
                if kind == "ORG":
                    pc = item[1]
                elif kind == "PIN_ABI":
                    if pc > item[1]:
                        raise ValueError(f"ABI pin overflow before {item[2]}: PC=${pc:04X} > ${item[1]:04X}")
                    pc = item[1]
                elif kind == "LABEL":
                    self.labels[item[1]] = pc
                elif kind == "BYTES":
                    pc += len(item[1])
                elif kind == "WORD":
                    pc += 2
                elif kind in ("INST", "LONGBRANCH"):
                    pc += item[3]

            changed = False
            pc = self.org
            for idx, item in enumerate(self.ops):
                kind = item[0]
                if kind == "ORG":
                    pc = item[1]
                elif kind == "PIN_ABI":
                    if pc > item[1]:
                        raise ValueError(f"ABI pin overflow before {item[2]}: PC=${pc:04X} > ${item[1]:04X}")
                    pc = item[1]
                elif kind == "LABEL":
                    continue
                elif kind == "BYTES":
                    pc += len(item[1])
                elif kind == "WORD":
                    pc += 2
                elif kind == "LONGBRANCH":
                    pc += 5
                elif kind == "INST":
                    _, opcode, operand, sz = item
                    if sz == 2 and opcode in (0xF0, 0xD0, 0xB0, 0x90, 0x30, 0x10):
                        target = self.resolve(operand)
                        rel = target - (pc + 2)
                        if not (-128 <= rel <= 127):
                            self.ops[idx] = ("LONGBRANCH", opcode ^ 0x20, operand, 5)
                            changed = True
                    pc += sz
            if not changed:
                break

        # Final Pass: Emit machine code into Main ROM ($E000-$FFFF) and Extension LUT-ROM ($A800-$AFFF)
        rom = bytearray([0xEA] * self.size)
        ext_rom = bytearray([0xEA] * ext_size)
        main_end = self.org
        ext_end = ext_org

        def put_byte(addr, val):
            nonlocal main_end, ext_end
            b = val & 0xFF
            if self.org <= addr < self.org + self.size:
                if addr >= 0xFFFA:
                    raise ValueError(f"Main ROM overflow into 6502 vectors at ${addr:04X}!")
                rom[addr - self.org] = b
                if addr + 1 > main_end:
                    main_end = addr + 1
            elif ext_org <= addr < ext_org + ext_size:
                ext_rom[addr - ext_org] = b
                if addr + 1 > ext_end:
                    ext_end = addr + 1
            else:
                raise ValueError(f"ROM address out of bounds: ${addr:04X}")

        pc = self.org
        for item in self.ops:
            kind = item[0]
            if kind == "ORG":
                pc = item[1]
            elif kind == "PIN_ABI":
                if pc > item[1]:
                    raise ValueError(f"ABI pin overflow before {item[2]}: PC=${pc:04X} > ${item[1]:04X}")
                while pc < item[1]:
                    put_byte(pc, 0xEA)
                    pc += 1
            elif kind == "LABEL":
                continue
            elif kind == "BYTES":
                for b in item[1]:
                    put_byte(pc, self.resolve(b))
                    pc += 1
            elif kind == "WORD":
                v = self.resolve(item[1])
                put_byte(pc, v & 0xFF)
                put_byte(pc + 1, (v >> 8) & 0xFF)
                pc += 2
            elif kind == "LONGBRANCH":
                _, inv_op, operand, _ = item
                v = self.resolve(operand)
                put_byte(pc, inv_op)
                put_byte(pc + 1, 0x03)
                put_byte(pc + 2, 0x4C) # JMP abs
                put_byte(pc + 3, v & 0xFF)
                put_byte(pc + 4, (v >> 8) & 0xFF)
                pc += 5
            elif kind == "INST":
                _, opcode, operand, sz = item
                put_byte(pc, opcode)
                if sz == 2:
                    if opcode in (0xF0, 0xD0, 0xB0, 0x90, 0x30, 0x10):
                        target = self.resolve(operand)
                        rel = target - (pc + 2)
                        put_byte(pc + 1, rel & 0xFF)
                    else:
                        v = self.resolve(operand)
                        put_byte(pc + 1, v & 0xFF)
                elif sz == 3:
                    v = self.resolve(operand)
                    put_byte(pc + 1, v & 0xFF)
                    put_byte(pc + 2, (v >> 8) & 0xFF)
                pc += sz

        # Set 6502 hardware vectors at $FFFA-$FFFF
        reset_addr = self.labels["RESET"]
        irq_addr = self.labels.get("IRQ_VEC", reset_addr)
        rom[0xFFFA - self.org] = irq_addr & 0xFF
        rom[0xFFFB - self.org] = (irq_addr >> 8) & 0xFF
        rom[0xFFFC - self.org] = reset_addr & 0xFF
        rom[0xFFFD - self.org] = (reset_addr >> 8) & 0xFF
        rom[0xFFFE - self.org] = irq_addr & 0xFF
        rom[0xFFFF - self.org] = (irq_addr >> 8) & 0xFF
        print(f"Main ROM ($E000-$FFFF): {main_end - self.org} / {self.size - 6} bytes used (${self.org:04X}-${main_end-1:04X})")
        print(f"Ext  ROM ($A800-$AFFF): {ext_end - ext_org} / {ext_size} bytes used (${ext_org:04X}-${max(ext_org, ext_end-1):04X})")
        return rom, ext_rom


def build_rom():
    a = Asm6502(org=0xE000, size=8192)

    # ========================================================================
    # Memory Map & Zero-Page Variables
    # ========================================================================
    ZP_TXT     = 0x10  # 16-bit pointer to current text position ($10-$11)
    ZP_CURLINE = 0x12  # 16-bit pointer to current BASIC program line ($12-$13)
    ZP_PRGEND  = 0x14  # 16-bit pointer to end of BASIC program ($14-$15)
    ZP_ACC     = 0x16  # 16-bit primary math accumulator ($16-$17)
    ZP_OP      = 0x18  # 16-bit secondary math operand ($18-$19)
    ZP_TMP     = 0x1A  # 16-bit scratch pointer ($1A-$1B)
    ZP_DST     = 0x1C  # 16-bit copy destination pointer ($1C-$1D)
    ZP_LINENUM = 0x1E  # 16-bit line number ($1E-$1F)
    ZP_RUN     = 0x20  # 1 = running program, 0 = direct mode
    ZP_JUMPED  = 0x21  # 1 = GOTO/GOSUB/NEXT changed ZP_CURLINE/ZP_TXT
    ZP_SIGN    = 0x22  # Sign flag for division/multiplication/printing
    ZP_VARIDX  = 0x23  # Current variable index (0..25)*2
    ZP_GOSUB_SP = 0x24 # GOSUB stack index (0..15)
    ZP_ARGS    = 0x30  # Parsed command arguments: 8 x 16-bit words ($30..$3F)
    ZP_REM     = 0x40  # 16-bit division remainder ($40-$41)
    ZP_MATH    = 0x42  # 32-bit scratch ($42..$45)
    ZP_FPTR    = 0x46  # 16-bit SD File buffer pointer ($46-$47)

    LINE_BUF    = 0x0200 # 128-byte input line buffer ($0200-$027F)
    NUM_BUF     = 0x0280 # 16-byte number-to-string buffer
    VARS_BASE   = 0x0300 # 26 x 16-bit variables A..Z ($0300-$0333)
    FOR_TARGET  = 0x0340 # 26 x 16-bit FOR limit values ($0340-$0373)
    FOR_STEP    = 0x0380 # 26 x 16-bit FOR step values ($0380-$03B3)
    FOR_LINE    = 0x03C0 # 26 x 16-bit FOR loop ZP_CURLINE ($03C0-$03F3)
    FOR_TXT     = 0x0400 # 26 x 16-bit FOR loop ZP_TXT ($0400-$0433)
    GOSUB_LINE  = 0x0440 # 16 x 16-bit GOSUB ZP_CURLINE ($0440-$045F)
    GOSUB_TXT   = 0x0460 # 16 x 16-bit GOSUB ZP_TXT ($0460-$047F)
    FNAME_BUF   = 0x0480 # 16-byte normalized filename buffer ($0480-$048F)
    DISK_DRIVE  = 0x0490 # Current virtual drive (0..3)
    DISK_FORCE_RD = 0x0491 # $80 = force SDRAM-Disk (*SDRAM), $00 = auto SD Card (*SD)
    DISK_SD_TYPE  = 0x0492 # $80 = SDHC, $01 = SDSC, $00 = SDRAM-Disk fallback
    DISK_SLOT     = 0x0493 # Current slot (0..14)
    DISK_FREE     = 0x0494 # First free slot
    DISK_CTRL_SH  = 0x0495 # Shadow of IO_SD_CTRL ($A011)
    DISK_SEC_LO   = 0x0496 # Sector number low
    DISK_SEC_HI   = 0x0497 # Sector number high

    # Named Function (FUNC..ENDFUNC / DO) & Fast Hardware Pixel Streamer (DEFSPR/DEFTILE/DEFBIG/PIX)
    GFX_KIND         = 0x04A0 # 0=idle, 1=Sprite(256B), 2=Tile(256B), 3=BigSprite(128x128)
    GFX_SLOT         = 0x04A1 # Target slot (0..31 sprite, 0..63 tile, 0..1 bigspr)
    GFX_REM_LO       = 0x04A2 # Remaining pixels low byte (for 256-pixel Sprite/Tile)
    GFX_REM_HI       = 0x04A3 # Remaining pixels high byte
    GFX_BIG_X        = 0x04A4 # Current X pixel on BigSprite scanline (0..127)
    GFX_BIG_Y        = 0x04A5 # Current Y scanline on BigSprite (0..128)
    GFX_CNT          = 0x04A6 # RLE / Raw pixel run counter (1..127)
    FUNC_SLOT_OVR    = 0x04A7 # Optional slot override passed via DO naam, slot ($FF = none)
    FUNC_SCAN_LINE   = 0x04A8 # 16-bit line scan pointer ($04A8-$04A9)
    GFX_PIX_VAL      = 0x04AA # Current pixel color byte being emitted
    GFX_BYTE_TMP     = 0x04AB # High nibble scratch during hex byte decode
    FUNC_CALLER_LINE = 0x04AC # Saved caller ZP_CURLINE ($04AC-$04AD)
    FUNC_CALLER_TXT  = 0x04AE # Saved caller ZP_TXT ($04AE-$04AF)
    FUNC_NAME_BUF    = 0x04B0 # 16-byte uppercased function name buffer ($04B0-$04BF)

    # SD-Card & SDRAM-Disk File Handle State (OPEN / WRITE / READ / GET / PUT / SEEK / EOF / CLOSE)
    FILE_OUT_FLAG    = 0x04C0 # 1 = redirect PUTC to FILE_BUF ($6000) + FILE_PTR, 0 = normal IO_TERM
    FILE_DIRTY       = 0x04C1 # 1 = file modified (needs SD write on CLOSE)
    FILE_PTR_LO      = 0x04C2 # 16-bit current read/write offset (0..4095)
    FILE_PTR_HI      = 0x04C3
    FILE_LEN_LO      = 0x04C4 # 16-bit open file byte length (0..4095)
    FILE_LEN_HI      = 0x04C5
    FILE_MODE        = 0x04C6 # 0 = Read/Write, 1 = New/Overwrite, 2 = Append
    FILE_CHR_TMP     = 0x04C7 # Scratch byte for FILE_PUT_CHAR
    FILE_SLOT_SAVE   = 0x04C8 # Saved DISK_SLOT for currently open file
    FILE_NAME_SAVE   = 0x04D0 # 16-byte saved filename for currently open file ($04D0-$04DF)
    FILE_BUF         = 0x6000 # 4 KB open file buffer in SDRAM ($6000-$6FFF)

    SD_BUF        = 0x0500 # 512-byte sector / directory buffer ($0500-$06FF)

    PRG_BASE    = 0x0800 # BASIC Program storage ($0800 - $2FFF = 10 KB)

    # Hardware I/O Registers
    IO_STATUS   = 0xA000
    IO_TERM     = 0xA001
    IO_DELAY    = 0xA002
    IO_TIMER    = 0xA003
    IO_JOY      = 0xA004
    IO_RND      = 0xA005
    IO_MODE     = 0xA006
    IO_SD_DATA  = 0xA010
    IO_SD_CTRL  = 0xA011
    IO_RD_LO    = 0xA012
    IO_RD_HI    = 0xA013
    IO_RD_DATA  = 0xA014
    IO_RD_BANK       = 0xA015
    IO_PCM_DAC       = 0xA016
    IO_PCM_RATE      = 0xA017
    IO_ADMA_BANK     = 0xA018
    IO_ADMA_PAGES_LO = 0xA019
    IO_ADMA_PAGES_HI = 0xA01A
    IO_ADMA_CTRL     = 0xA01B
    IO_GPU           = 0xA020

    # ========================================================================
    # 1. Reset & Boot Sequence
    # ========================================================================
    a.label("RESET")
    a.sei()
    a.cld()
    a.ldx_imm(0xFF)
    a.txs()

    # Ensure terminal mode is enabled (MODE 0)
    a.lda_imm(1)
    a.sta_abs(IO_MODE)

    # Initialize GPU: set render target to front buffer (cmd 12, 1) and clear to transparent (cmd 1, 0xE3)
    a.lda_imm(12)
    a.sta_abs(IO_GPU)
    a.lda_imm(1)
    a.sta_abs(IO_GPU)
    a.lda_imm(1)
    a.sta_abs(IO_GPU)
    a.lda_imm(0xE3)
    a.sta_abs(IO_GPU)

    # Initialize empty BASIC program at $0800 & disk state
    a.lda_imm(0)
    a.sta_abs(DISK_DRIVE)
    a.sta_abs(DISK_FORCE_RD)
    a.jsr("CMD_NEW_INIT")

    # Clear terminal and print welcome banner
    a.lda_imm(0x0C)
    a.jsr("PUTC")
    a.lda_imm("<STR_BANNER")
    a.ldy_imm(">STR_BANNER")
    a.jsr("PRINT_STR")

    # ========================================================================
    # 2. Main Interactive REPL Loop
    # ========================================================================
    a.label("MAIN_LOOP")
    a.ldx_imm(0xFF)
    a.txs()
    a.lda_imm(0)
    a.sta_zp(ZP_RUN)
    a.lda_imm(1)
    a.sta_abs(IO_MODE) # Always ensure terminal is visible at prompt

    a.lda_imm(ord(">"))
    a.jsr("PUTC")
    a.lda_imm(ord(" "))
    a.jsr("PUTC")

    a.jsr("READ_LINE")

    # Setup ZP_TXT to point to LINE_BUF ($0200)
    a.lda_imm(0x00)
    a.sta_zp(ZP_TXT)
    a.lda_imm(0x02)
    a.sta_zp(ZP_TXT + 1)

    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("MAIN_LOOP") # Empty line

    # Check if first character is a digit ('0'..'9') -> Line Entry/Edit
    a.jsr("IS_DIGIT")
    a.bcc("DIRECT_EXEC")

    # Parse line number into ZP_LINENUM ($1E-$1F)
    a.jsr("PARSE_UINT")
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_LINENUM)
    a.lda_zp(ZP_ACC + 1)
    a.sta_zp(ZP_LINENUM + 1)

    a.jsr("SKIP_SPACES")
    a.jsr("STORE_LINE")
    a.jmp("MAIN_LOOP")

    a.label("DIRECT_EXEC")
    a.jsr("EXEC_LINE_STATEMENTS")
    a.jmp("MAIN_LOOP")

    # ========================================================================
    # 3. Line Storage (Insert / Replace / Delete in $0800..$2FFF)
    # ========================================================================
    # Format of each line in memory:
    #   byte 0: total length of record (4 + strlen), or 0x00 for end-of-program
    #   byte 1: line_num_lo
    #   byte 2: line_num_hi
    #   byte 3..N-2: ASCII text
    #   byte N-1: 0x00 terminator
    a.label("STORE_LINE")
    # 1. First delete existing line with ZP_LINENUM if present
    a.jsr("FIND_LINE")
    a.bcc("SL_CHECK_INSERT")

    # Line exists at ZP_TMP! Delete it by shifting bytes after it down to ZP_TMP
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP) # length of old line
    a.clc()
    a.adc_zp(ZP_TMP)
    a.sta_zp(ZP_OP)
    a.lda_zp(ZP_TMP + 1)
    a.adc_imm(0)
    a.sta_zp(ZP_OP + 1)
    # Copy from ZP_OP..ZP_PRGEND down to ZP_TMP
    a.label("SL_DEL_LOOP")
    a.ldy_imm(0)
    a.lda_iny(ZP_OP)
    a.sta_iny(ZP_TMP)
    a.lda_zp(ZP_OP)
    a.cmp_zp(ZP_PRGEND)
    a.bne("SL_DEL_ADV")
    a.lda_zp(ZP_OP + 1)
    a.cmp_zp(ZP_PRGEND + 1)
    a.beq("SL_DEL_DONE")
    a.label("SL_DEL_ADV")
    a.inc_zp(ZP_OP)
    a.bne("SL_DA1")
    a.inc_zp(ZP_OP + 1)
    a.label("SL_DA1")
    a.inc_zp(ZP_TMP)
    a.bne("SL_DEL_LOOP")
    a.inc_zp(ZP_TMP + 1)
    a.jmp("SL_DEL_LOOP")

    a.label("SL_DEL_DONE")
    # Update ZP_PRGEND to ZP_TMP
    a.lda_zp(ZP_TMP)
    a.sta_zp(ZP_PRGEND)
    a.lda_zp(ZP_TMP + 1)
    a.sta_zp(ZP_PRGEND + 1)

    a.label("SL_CHECK_INSERT")
    # Check if new line text at ZP_TXT is empty (delete-only)
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.bne("SL_DO_INSERT")
    a.rts()

    a.label("SL_DO_INSERT")
    # Compute length of text at ZP_TXT
    a.ldy_imm(0)
    a.label("SL_LEN_LOOP")
    a.lda_iny(ZP_TXT)
    a.beq("SL_LEN_GOT")
    a.iny()
    a.jmp("SL_LEN_LOOP")
    a.label("SL_LEN_GOT")
    # Total record length = Y + 4
    a.tya()
    a.clc()
    a.adc_imm(4)
    a.sta_zp(ZP_SIGN) # Save record length in ZP_SIGN

    # Find insertion position in ZP_TMP
    a.jsr("FIND_LINE")
    # Shift memory from ZP_TMP..ZP_PRGEND up by ZP_SIGN bytes
    # Source = ZP_PRGEND (stored in ZP_OP), Dest = ZP_PRGEND + ZP_SIGN (stored in ZP_DST)
    a.lda_zp(ZP_PRGEND)
    a.sta_zp(ZP_OP)
    a.clc()
    a.adc_zp(ZP_SIGN)
    a.sta_zp(ZP_DST)
    a.sta_zp(ZP_PRGEND) # New ZP_PRGEND!
    a.lda_zp(ZP_PRGEND + 1)
    a.sta_zp(ZP_OP + 1)
    a.adc_imm(0)
    a.sta_zp(ZP_DST + 1)
    a.sta_zp(ZP_PRGEND + 1)

    a.label("SL_INS_SHIFT")
    a.ldy_imm(0)
    a.lda_iny(ZP_OP)
    a.sta_iny(ZP_DST)
    a.lda_zp(ZP_OP)
    a.cmp_zp(ZP_TMP)
    a.bne("SL_IS_DEC")
    a.lda_zp(ZP_OP + 1)
    a.cmp_zp(ZP_TMP + 1)
    a.beq("SL_WRITE_REC")
    a.label("SL_IS_DEC")
    # Decrement ZP_OP and ZP_DST
    a.lda_zp(ZP_OP)
    a.bne("SL_ISD1")
    a.dec_zp(ZP_OP + 1)
    a.label("SL_ISD1")
    a.dec_zp(ZP_OP)
    a.lda_zp(ZP_DST)
    a.bne("SL_ISD2")
    a.dec_zp(ZP_DST + 1)
    a.label("SL_ISD2")
    a.dec_zp(ZP_DST)
    a.jmp("SL_INS_SHIFT")

    a.label("SL_WRITE_REC")
    # Write header at ZP_TMP: [len, line_lo, line_hi]
    a.ldy_imm(0)
    a.lda_zp(ZP_SIGN)
    a.sta_iny(ZP_TMP)
    a.iny()
    a.lda_zp(ZP_LINENUM)
    a.sta_iny(ZP_TMP)
    a.iny()
    a.lda_zp(ZP_LINENUM + 1)
    a.sta_iny(ZP_TMP)

    # Advance ZP_TMP by 3 and copy string + null from ZP_TXT
    a.lda_zp(ZP_TMP)
    a.clc()
    a.adc_imm(3)
    a.sta_zp(ZP_TMP)
    a.bcc("SL_CP_TXT")
    a.inc_zp(ZP_TMP + 1)
    a.label("SL_CP_TXT")
    a.ldy_imm(0)
    a.label("SL_CP_LOOP")
    a.lda_iny(ZP_TXT)
    a.sta_iny(ZP_TMP)
    a.beq("SL_CP_DONE")
    a.iny()
    a.jmp("SL_CP_LOOP")
    a.label("SL_CP_DONE")
    a.rts()

    # ------------------------------------------------------------------------
    # FIND_LINE: Search program for line >= ZP_LINENUM.
    # Returns ZP_TMP pointing to that line (or ZP_PRGEND if at end).
    # Carry = 1 if exact match found, Carry = 0 if not found.
    # ------------------------------------------------------------------------
    a.label("FIND_LINE")
    a.lda_imm(PRG_BASE & 0xFF)
    a.sta_zp(ZP_TMP)
    a.lda_imm(PRG_BASE >> 8)
    a.sta_zp(ZP_TMP + 1)

    a.label("FL_LOOP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.beq("FL_NOT_FOUND") # End of program (len == 0)

    # Compare line_hi (offset 2), then line_lo (offset 1) with ZP_LINENUM
    a.ldy_imm(2)
    a.lda_iny(ZP_TMP)
    a.cmp_zp(ZP_LINENUM + 1)
    a.bcc("FL_NEXT") # line_hi < target_hi -> keep searching
    a.bne("FL_NOT_FOUND") # line_hi > target_hi -> stop here
    a.ldy_imm(1)
    a.lda_iny(ZP_TMP)
    a.cmp_zp(ZP_LINENUM)
    a.bcc("FL_NEXT") # line_lo < target_lo -> keep searching
    a.bne("FL_NOT_FOUND")
    # Exact match!
    a.sec()
    a.rts()

    a.label("FL_NEXT")
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.clc()
    a.adc_zp(ZP_TMP)
    a.sta_zp(ZP_TMP)
    a.bcc("FL_LOOP")
    a.inc_zp(ZP_TMP + 1)
    a.jmp("FL_LOOP")

    a.label("FL_NOT_FOUND")
    a.clc()
    a.rts()

    # ========================================================================
    # 4. Statement Executor (Handles ':' separated statements & RUN loop)
    # ========================================================================
    a.label("EXEC_LINE_STATEMENTS")
    a.lda_imm(0)
    a.sta_zp(ZP_JUMPED)

    a.label("ELS_NEXT_STMT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.bne("ELS_CHECK_COLON")
    a.rts()

    a.label("ELS_CHECK_COLON")
    a.cmp_imm(ord(":"))
    a.bne("ELS_DO_ONE")
    a.jsr("ADV_TXT")
    a.jmp("ELS_NEXT_STMT")

    a.label("ELS_DO_ONE")
    a.jsr("EXEC_SINGLE_STMT")
    a.lda_zp(ZP_JUMPED)
    a.bne("ELS_DONE")
    a.lda_zp(ZP_RUN)
    a.cmp_imm(0xFF) # 0xFF means END/STOP/ERROR occurred
    a.beq("ELS_DONE")

    # Skip to next ':' or end of line
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(":"))
    a.bne("ELS_DONE")
    a.jsr("ADV_TXT")
    a.jmp("ELS_NEXT_STMT")

    a.label("ELS_DONE")
    a.rts()

    # ------------------------------------------------------------------------
    # Keyword Matcher Helper: match string at (A=lo, Y=hi) against ZP_TXT
    # If matched (followed by non-alphanumeric), advances ZP_TXT and sets Carry=1
    # ------------------------------------------------------------------------
    a.label("MATCH_KW")
    a.sta_zp(ZP_TMP)
    a.sty_zp(ZP_TMP + 1)
    a.ldy_imm(0)
    a.label("MK_LOOP")
    a.lda_iny(ZP_TMP)
    a.beq("MK_END_CHECK")
    a.cmp_iny_txt_workaround = True
    # Compare with ZP_TXT[Y]
    a.sta_zp(ZP_MATH)
    a.lda_iny(ZP_TXT)
    a.cmp_zp(ZP_MATH)
    a.bne("MK_FAIL")
    a.iny()
    a.jmp("MK_LOOP")

    a.label("MK_END_CHECK")
    # Ensure next char in ZP_TXT is not 'A'..'Z'
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("A"))
    a.bcc("MK_SUCCESS")
    a.cmp_imm(ord("Z") + 1)
    a.bcc("MK_FAIL")

    a.label("MK_SUCCESS")
    # Advance ZP_TXT by Y
    a.tya()
    a.clc()
    a.adc_zp(ZP_TXT)
    a.sta_zp(ZP_TXT)
    a.bcc("MK_S2")
    a.inc_zp(ZP_TXT + 1)
    a.label("MK_S2")
    a.jsr("SKIP_SPACES")
    a.sec()
    a.rts()

    a.label("MK_FAIL")
    a.clc()
    a.rts()

    def try_kw(kw_label, handler_label):
        skip_lbl = f"SKIP_{kw_label}_{id(handler_label)}"
        a.lda_imm(f"<{kw_label}")
        a.ldy_imm(f">{kw_label}")
        a.jsr("MATCH_KW")
        a.bcc(skip_lbl)
        a.jmp(handler_label)
        a.label(skip_lbl)

    # ========================================================================
    # 5. Single Statement Dispatcher (Table-Driven + Optional '*' Prefix)
    # ========================================================================
    a.label("EXEC_SINGLE_STMT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.bne("ESS_NOT_EMPTY")
    a.rts()
    a.label("ESS_NOT_EMPTY")

    # Optional '*' prefix for MOS-style commands (*CAT, *SD, *SDRAM, *DRIVE, *INFO, *FILES)
    a.cmp_imm(ord("*"))
    a.bne("ESS_NO_STAR")
    a.jsr("ADV_TXT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.bne("ESS_NO_STAR")
    a.rts()
    a.label("ESS_NO_STAR")

    # Shorthand '?' for PRINT and '\'' for REM
    a.cmp_imm(ord("?"))
    a.bne("ESS_CHK_QUOTE")
    a.jsr("ADV_TXT")
    a.jmp("STMT_PRINT")

    a.label("ESS_CHK_QUOTE")
    a.cmp_imm(ord("'"))
    a.bne("ESS_KEYWORDS")
    a.jmp("STMT_REM")

    a.label("ESS_KEYWORDS")
    a.ldx_imm(0)
    a.label("ESS_KW_LP")
    a.ldy_abx("KW_TABLE_HI")
    a.bne("ESS_KW_TRY")
    # End of keyword table -> default to variable assignment (A..Z = expr)
    a.jmp("STMT_LET")

    a.label("ESS_KW_TRY")
    a.lda_abx("KW_TABLE")
    a.stx_zp(ZP_MATH + 2)
    a.jsr("MATCH_KW")
    a.ldx_zp(ZP_MATH + 2)
    a.bcs("ESS_KW_FOUND")
    a.inx()
    a.jmp("ESS_KW_LP")

    a.label("ESS_KW_FOUND")
    a.lda_abx("KW_HND_LO")
    a.sta_zp(ZP_TMP)
    a.lda_abx("KW_HND_HI")
    a.sta_zp(ZP_TMP + 1)
    a.inst(0x6C, ZP_TMP, 3) # JMP (ZP_TMP)

    # ========================================================================
    # 6. Statement Implementations
    # ========================================================================

    # --- REM & DIM ---
    a.label("STMT_REM")
    # Advance ZP_TXT to end of line (null byte)
    a.ldy_imm(0)
    a.label("REM_LP")
    a.lda_iny(ZP_TXT)
    a.beq("REM_DN")
    a.jsr("ADV_TXT")
    a.jmp("REM_LP")
    a.label("REM_DN")
    a.rts()

    # DIM A(100), B(200) -> skip to ':' or end of line (arrays A..Z are pre-allocated at 64KB each in SDRAM!)
    a.label("STMT_DIM")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("REM_DN")
    a.cmp_imm(ord(":"))
    a.beq("REM_DN")
    a.jsr("ADV_TXT")
    a.jmp("STMT_DIM")

    # --- LET / Variable or SDRAM Array Assignment: V = expr  OR  V(idx) = expr ---
    a.label("STMT_LET")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("A"))
    a.bcc("SYNTAX_ERR")
    a.cmp_imm(ord("Z") + 1)
    a.bcs("SYNTAX_ERR")
    a.sec()
    a.sbc_imm(ord("A"))
    a.pha() # Save var_idx (0..25) on stack
    a.jsr("ADV_TXT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("("))
    a.beq("LET_ARRAY")
    a.cmp_imm(ord("="))
    a.bne("SYNTAX_ERR_POP")
    a.jsr("ADV_TXT")
    a.jsr("EVAL_EXPR")
    a.pla()
    a.asl_a()
    a.tax()
    a.lda_zp(ZP_ACC)
    a.sta_abx(VARS_BASE)
    a.lda_zp(ZP_ACC + 1)
    a.sta_abx(VARS_BASE + 1)
    a.rts()

    a.label("LET_ARRAY")
    a.jsr("PARSE_ARR_IDX")
    a.lda_zp(ZP_ACC)
    a.pha() # push offset_lo
    a.lda_zp(ZP_ACC + 1)
    a.pha() # push offset_hi
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("="))
    a.bne("LET_ARR_ERR")
    a.jsr("ADV_TXT")
    a.jsr("EVAL_EXPR")
    a.pla() # offset_hi -> Y
    a.tay()
    a.pla() # offset_lo -> X
    a.tax()
    a.pla() # var_idx (0..25) -> A
    a.jsr("SET_ARR_IO")
    a.lda_zp(ZP_ACC)
    a.sta_abs(IO_RD_DATA)
    a.inx()
    a.stx_abs(IO_RD_LO)
    a.lda_zp(ZP_ACC + 1)
    a.sta_abs(IO_RD_DATA)
    a.rts()

    a.label("LET_ARR_ERR")
    a.pla()
    a.pla()
    a.label("SYNTAX_ERR_POP")
    a.pla()
    a.label("SYNTAX_ERR")
    a.lda_imm("<STR_SYNTAX_ERR")
    a.ldy_imm(">STR_SYNTAX_ERR")
    a.jsr("PRINT_STR")
    a.lda_imm(0xFF)
    a.sta_zp(ZP_RUN)
    a.lda_imm(1)
    a.sta_abs(IO_MODE)
    a.rts()

    # --- PRINT ---
    a.label("STMT_PRINT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("PR_NEWLINE")
    a.cmp_imm(ord(":"))
    a.beq("PR_NEWLINE")

    a.label("PR_LOOP")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("PR_NEWLINE")
    a.cmp_imm(ord(":"))
    a.beq("PR_NEWLINE")
    a.cmp_imm(ord('"'))
    a.bne("PR_EXPR")

    # Print string literal
    a.jsr("ADV_TXT")
    a.label("PR_STR_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("PR_AFTER_ITEM")
    a.cmp_imm(ord('"'))
    a.beq("PR_STR_END")
    a.jsr("PUTC")
    a.jsr("ADV_TXT")
    a.jmp("PR_STR_LP")
    a.label("PR_STR_END")
    a.jsr("ADV_TXT")
    a.jmp("PR_AFTER_ITEM")

    a.label("PR_EXPR")
    a.jsr("EVAL_EXPR")
    a.jsr("PRINT_INT16")

    a.label("PR_AFTER_ITEM")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(";"))
    a.beq("PR_SEMI")
    a.cmp_imm(ord(","))
    a.beq("PR_COMMA")
    a.jmp("PR_NEWLINE")

    a.label("PR_SEMI")
    a.jsr("ADV_TXT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("PR_DONE") # Trailing ';' suppresses newline
    a.cmp_imm(ord(":"))
    a.beq("PR_DONE")
    a.jmp("PR_LOOP")

    a.label("PR_COMMA")
    a.jsr("ADV_TXT")
    a.lda_imm(ord(" "))
    a.jsr("PUTC")
    a.lda_imm(ord(" "))
    a.jsr("PUTC")
    a.jmp("PR_LOOP")

    a.label("PR_NEWLINE")
    a.jsr("NEWLINE")
    a.label("PR_DONE")
    a.rts()

    # --- INPUT [prompt,] V ---
    a.label("STMT_INPUT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord('"'))
    a.bne("INP_GET_VAR")
    a.jsr("ADV_TXT")
    a.label("INP_PR_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("INP_GET_VAR")
    a.cmp_imm(ord('"'))
    a.beq("INP_PR_END")
    a.jsr("PUTC")
    a.jsr("ADV_TXT")
    a.jmp("INP_PR_LP")
    a.label("INP_PR_END")
    a.jsr("ADV_TXT")
    a.jsr("SKIP_COMMA")

    a.label("INP_GET_VAR")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("A"))
    a.bcc("SYNTAX_ERR")
    a.cmp_imm(ord("Z") + 1)
    a.bcs("SYNTAX_ERR")
    a.sec()
    a.sbc_imm(ord("A"))
    a.asl_a()
    a.pha()
    a.jsr("ADV_TXT")

    a.lda_imm(ord("?"))
    a.jsr("PUTC")
    a.lda_imm(ord(" "))
    a.jsr("PUTC")

    # Save ZP_TXT, read user input into LINE_BUF ($0200), evaluate, restore ZP_TXT
    a.lda_zp(ZP_TXT)
    a.pha()
    a.lda_zp(ZP_TXT + 1)
    a.pha()
    a.jsr("READ_LINE")
    a.lda_imm(0x00)
    a.sta_zp(ZP_TXT)
    a.lda_imm(0x02)
    a.sta_zp(ZP_TXT + 1)
    a.jsr("EVAL_EXPR")
    a.pla()
    a.sta_zp(ZP_TXT + 1)
    a.pla()
    a.sta_zp(ZP_TXT)

    a.pla()
    a.tax()
    a.lda_zp(ZP_ACC)
    a.sta_abx(VARS_BASE)
    a.lda_zp(ZP_ACC + 1)
    a.sta_abx(VARS_BASE + 1)
    a.rts()

    # --- IF expr THEN stmt / line_num ---
    a.label("STMT_IF")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.ora_zp(ZP_ACC + 1)
    a.pha() # Save truth value
    a.lda_imm("<KW_THEN")
    a.ldy_imm(">KW_THEN")
    a.jsr("MATCH_KW")
    a.pla()
    a.beq("STMT_REM") # Condition false -> skip rest of line!

    # Condition true! Check if followed by a line number or a statement
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.jsr("IS_DIGIT")
    a.bcs("STMT_GOTO")
    a.jmp("EXEC_SINGLE_STMT")

    # --- GOTO expr ---
    a.label("STMT_GOTO")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_LINENUM)
    a.lda_zp(ZP_ACC + 1)
    a.sta_zp(ZP_LINENUM + 1)
    a.jsr("FIND_LINE")
    a.bcc("GOTO_ERR")
    a.lda_zp(ZP_TMP)
    a.sta_zp(ZP_CURLINE)
    a.clc()
    a.adc_imm(3)
    a.sta_zp(ZP_TXT)
    a.lda_zp(ZP_TMP + 1)
    a.sta_zp(ZP_CURLINE + 1)
    a.adc_imm(0)
    a.sta_zp(ZP_TXT + 1)
    a.lda_imm(1)
    a.sta_zp(ZP_JUMPED)
    a.sta_zp(ZP_RUN)
    a.rts()

    a.label("GOTO_ERR")
    a.lda_imm("<STR_LINE_ERR")
    a.ldy_imm(">STR_LINE_ERR")
    a.jsr("PRINT_STR")
    a.lda_imm(0xFF)
    a.sta_zp(ZP_RUN)
    a.lda_imm(1)
    a.sta_abs(IO_MODE)
    a.rts()

    # --- GOSUB expr & RETURN ---
    a.label("STMT_GOSUB")
    a.jsr("EVAL_EXPR")
    a.ldx_zp(ZP_GOSUB_SP)
    a.cpx_imm(30)
    a.bcs("SYNTAX_ERR")
    a.lda_zp(ZP_CURLINE)
    a.sta_abx(GOSUB_LINE)
    a.lda_zp(ZP_CURLINE + 1)
    a.sta_abx(GOSUB_LINE + 1)
    a.lda_zp(ZP_TXT)
    a.sta_abx(GOSUB_TXT)
    a.lda_zp(ZP_TXT + 1)
    a.sta_abx(GOSUB_TXT + 1)
    a.inx()
    a.inx()
    a.stx_zp(ZP_GOSUB_SP)
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_LINENUM)
    a.lda_zp(ZP_ACC + 1)
    a.sta_zp(ZP_LINENUM + 1)
    a.jsr("FIND_LINE")
    a.bcc("GOTO_ERR")
    a.lda_zp(ZP_TMP)
    a.sta_zp(ZP_CURLINE)
    a.clc()
    a.adc_imm(3)
    a.sta_zp(ZP_TXT)
    a.lda_zp(ZP_TMP + 1)
    a.sta_zp(ZP_CURLINE + 1)
    a.adc_imm(0)
    a.sta_zp(ZP_TXT + 1)
    a.lda_imm(1)
    a.sta_zp(ZP_JUMPED)
    a.rts()

    a.label("STMT_RETURN")
    a.jmp("STMT_ENDFUNC")

    # --- FOR V = start TO limit [STEP step] ---
    a.label("STMT_FOR")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("A"))
    a.bcc("FOR_ERR_JMP")
    a.cmp_imm(ord("Z") + 1)
    a.bcs("FOR_ERR_JMP")
    a.sec()
    a.sbc_imm(ord("A"))
    a.asl_a()
    a.sta_zp(ZP_VARIDX)
    a.jsr("ADV_TXT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("="))
    a.bne("FOR_ERR_JMP")
    a.jsr("ADV_TXT")
    a.jsr("EVAL_EXPR")
    a.ldx_zp(ZP_VARIDX)
    a.lda_zp(ZP_ACC)
    a.sta_abx(VARS_BASE)
    a.lda_zp(ZP_ACC + 1)
    a.sta_abx(VARS_BASE + 1)

    a.lda_imm("<KW_TO")
    a.ldy_imm(">KW_TO")
    a.jsr("MATCH_KW")
    a.bcc("FOR_ERR_JMP")
    a.jsr("EVAL_EXPR")
    a.ldx_zp(ZP_VARIDX)
    a.lda_zp(ZP_ACC)
    a.sta_abx(FOR_TARGET)
    a.lda_zp(ZP_ACC + 1)
    a.sta_abx(FOR_TARGET + 1)

    # Default STEP = 1
    a.lda_imm(1)
    a.sta_abx(FOR_STEP)
    a.lda_imm(0)
    a.sta_abx(FOR_STEP + 1)

    a.lda_imm("<KW_STEP")
    a.ldy_imm(">KW_STEP")
    a.jsr("MATCH_KW")
    a.bcc("FOR_SAVE_POS")
    a.jsr("EVAL_EXPR")
    a.ldx_zp(ZP_VARIDX)
    a.lda_zp(ZP_ACC)
    a.sta_abx(FOR_STEP)
    a.lda_zp(ZP_ACC + 1)
    a.sta_abx(FOR_STEP + 1)

    a.label("FOR_SAVE_POS")
    a.ldx_zp(ZP_VARIDX)
    a.lda_zp(ZP_CURLINE)
    a.sta_abx(FOR_LINE)
    a.lda_zp(ZP_CURLINE + 1)
    a.sta_abx(FOR_LINE + 1)
    a.lda_zp(ZP_TXT)
    a.sta_abx(FOR_TXT)
    a.lda_zp(ZP_TXT + 1)
    a.sta_abx(FOR_TXT + 1)
    a.rts()

    a.label("FOR_ERR_JMP")
    a.jmp("SYNTAX_ERR")

    # --- NEXT V ---
    a.label("STMT_NEXT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("A"))
    a.bcc("FOR_ERR_JMP")
    a.cmp_imm(ord("Z") + 1)
    a.bcs("FOR_ERR_JMP")
    a.sec()
    a.sbc_imm(ord("A"))
    a.asl_a()
    a.tax()
    a.jsr("ADV_TXT")

    # V = V + STEP
    a.clc()
    a.lda_abx(VARS_BASE)
    a.adc_abx(FOR_STEP)
    a.sta_abx(VARS_BASE)
    a.sta_zp(ZP_ACC)
    a.lda_abx(VARS_BASE + 1)
    a.adc_abx(FOR_STEP + 1)
    a.sta_abx(VARS_BASE + 1)
    a.sta_zp(ZP_ACC + 1)

    # Compare V with FOR_TARGET (signed 16-bit comparison depending on step sign)
    a.lda_abx(FOR_TARGET)
    a.sta_zp(ZP_OP)
    a.lda_abx(FOR_TARGET + 1)
    a.sta_zp(ZP_OP + 1)

    a.lda_abx(FOR_STEP + 1)
    a.bmi("NEXT_NEG_STEP")

    # Positive step: loop continues if ZP_ACC <= ZP_OP (i.e. !(ZP_OP < ZP_ACC))
    a.lda_zp(ZP_OP)
    a.cmp_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.sbc_zp(ZP_ACC + 1)
    a.bpl("NEXT_REPEAT")
    a.rts()

    a.label("NEXT_NEG_STEP")
    # Negative step: loop continues if ZP_ACC >= ZP_OP
    a.lda_zp(ZP_ACC)
    a.cmp_zp(ZP_OP)
    a.lda_zp(ZP_ACC + 1)
    a.sbc_zp(ZP_OP + 1)
    a.bpl("NEXT_REPEAT")
    a.rts()

    a.label("NEXT_REPEAT")
    a.lda_abx(FOR_LINE)
    a.sta_zp(ZP_CURLINE)
    a.lda_abx(FOR_LINE + 1)
    a.sta_zp(ZP_CURLINE + 1)
    a.lda_abx(FOR_TXT)
    a.sta_zp(ZP_TXT)
    a.lda_abx(FOR_TXT + 1)
    a.sta_zp(ZP_TXT + 1)
    a.rts()

    # --- WAIT expr ---
    a.label("STMT_WAIT")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.sta_abs(IO_DELAY)
    a.rts()

    # --- POKE addr, val ---
    a.label("STMT_POKE")
    a.jsr("PARSE_2_ARGS")
    a.lda_zp(ZP_ARGS)
    a.sta_zp(ZP_TMP)
    a.lda_zp(ZP_ARGS + 1)
    a.sta_zp(ZP_TMP + 1)
    a.ldy_imm(0)
    a.lda_zp(ZP_ARGS + 2)
    a.sta_iny(ZP_TMP)
    a.rts()

    # --- CALL addr / SYS addr (executes 6502 machine code at addr; passes BASIC A, X, Y in CPU A, X, Y) ---
    a.label("STMT_CALL")
    a.jsr("EVAL_EXPR")
    a.label("CALL_ACC")
    a.lda_abs(VARS_BASE)      # A = low byte of BASIC variable A
    a.ldx_abs(VARS_BASE + 46) # X = low byte of BASIC variable X
    a.ldy_abs(VARS_BASE + 48) # Y = low byte of BASIC variable Y
    a.inst(0x6C, ZP_ACC, 3)   # JMP (ZP_ACC) -> RTS returns to BASIC!

    # --- CLS & MODE ---
    a.label("STMT_CLS")
    a.lda_imm(0x0C)
    a.jmp("PUTC")

    a.label("STMT_MODE")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.bne("MODE_1")
    a.lda_imm(1) # MODE 0 -> terminal visible (1)
    a.sta_abs(IO_MODE)
    a.rts()
    a.label("MODE_1")
    a.lda_imm(0) # MODE 1 -> full screen graphics, terminal hidden (0)
    a.sta_abs(IO_MODE)
    a.rts()

    # ========================================================================
    # 7. DONDERDAG MiniGPU Hardware Graphics & Audio Commands
    # ========================================================================

    # Helper to parse N comma-separated arguments into ZP_ARGS[0..2*N-1]
    a.label("PARSE_N_ARGS")
    # Input: X = number of arguments * 2
    a.stx_zp(ZP_MATH + 2)
    a.ldx_imm(0)
    a.label("PNA_LOOP")
    a.stx_zp(ZP_MATH + 3)
    a.jsr("EVAL_EXPR")
    a.ldx_zp(ZP_MATH + 3)
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_ARGS) # Wait: indexed ZP write! Let's use 0x95 (sta zp,x)
    # Fix: let's write a helper loop using STA ZP_ARGS,X (opcode 0x95)
    a.ops.pop() # remove sta_zp(ZP_ARGS)
    a.inst(0x95, ZP_ARGS, 2) # STA ZP_ARGS,X
    a.lda_zp(ZP_ACC + 1)
    a.inst(0x95, ZP_ARGS + 1, 2) # STA ZP_ARGS+1,X
    a.inx()
    a.inx()
    a.cpx_zp(ZP_MATH + 2)
    a.bcs("PNA_DONE")
    a.jsr("SKIP_COMMA")
    a.jmp("PNA_LOOP")
    a.label("PNA_DONE")
    a.rts()

    a.label("PARSE_2_ARGS")
    a.ldx_imm(4)
    a.jmp("PARSE_N_ARGS")

    a.label("PARSE_3_ARGS")
    a.ldx_imm(6)
    a.jmp("PARSE_N_ARGS")

    a.label("PARSE_4_ARGS")
    a.ldx_imm(8)
    a.jmp("PARSE_N_ARGS")

    a.label("PARSE_5_ARGS")
    a.ldx_imm(10)
    a.jmp("PARSE_N_ARGS")

    a.label("PARSE_7_ARGS")
    a.ldx_imm(14)
    a.jmp("PARSE_N_ARGS")

    # Helper: Send standard 10-byte GPU packet: [cmd=A, arg0_lo, arg0_hi, arg1_lo, arg1_hi, arg2_lo, arg2_hi, arg3_lo, arg3_hi, arg4_lo]
    a.label("SEND_GPU_10")
    a.sta_abs(IO_GPU)
    a.ldx_imm(0)
    a.label("SG10_LP")
    a.inst(0xB5, ZP_ARGS, 2) # LDA ZP_ARGS,X
    a.sta_abs(IO_GPU)
    a.inx()
    a.cpx_imm(9)
    a.bcc("SG10_LP")
    a.rts()

    # --- CLEAR [color] (default 0xE3 transparent) ---
    a.label("STMT_CLEAR")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("CLR_DEFAULT")
    a.cmp_imm(ord(":"))
    a.beq("CLR_DEFAULT")
    a.jsr("EVAL_EXPR")
    a.lda_imm(1)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ACC)
    a.sta_abs(IO_GPU)
    a.rts()
    a.label("CLR_DEFAULT")
    a.lda_imm(1)
    a.sta_abs(IO_GPU)
    a.lda_imm(0xE3)
    a.sta_abs(IO_GPU)
    a.rts()

    # --- RECT x, y, w, h, color (cmd 2) ---
    a.label("STMT_RECT")
    a.jsr("PARSE_5_ARGS")
    a.lda_imm(2)
    a.jmp("SEND_GPU_10")

    # --- LINE x1, y1, x2, y2, color (cmd 3) ---
    a.label("STMT_LINE")
    a.jsr("PARSE_5_ARGS")
    a.lda_imm(3)
    a.jmp("SEND_GPU_10")

    # --- CIRCLE x, y, r, color (cmd 4) ---
    a.label("STMT_CIRCLE")
    a.jsr("PARSE_4_ARGS")
    a.lda_zp(ZP_ARGS + 6) # color -> move to arg4_lo (ZP_ARGS+8)
    a.sta_zp(ZP_ARGS + 8)
    a.lda_imm(4)
    a.jmp("SEND_GPU_10")

    # --- DISK x, y, r, color (cmd 5: filled circle) ---
    a.label("STMT_DISK")
    a.jsr("PARSE_4_ARGS")
    a.lda_zp(ZP_ARGS + 6)
    a.sta_zp(ZP_ARGS + 8)
    a.lda_imm(5)
    a.jmp("SEND_GPU_10")

    # --- TRI / FTRI x1, y1, x2, y2, x3, y3, color (cmd 6 / 7: 14 bytes) ---
    a.label("STMT_TRI")
    a.jsr("PARSE_7_ARGS")
    a.lda_imm(6)
    a.jmp("SEND_GPU_14")

    a.label("STMT_FTRI")
    a.jsr("PARSE_7_ARGS")
    a.lda_imm(7)
    a.label("SEND_GPU_14")
    a.sta_abs(IO_GPU)
    a.ldx_imm(0)
    a.label("SG14_LP")
    a.inst(0xB5, ZP_ARGS, 2)
    a.sta_abs(IO_GPU)
    a.inx()
    a.cpx_imm(13)
    a.bcc("SG14_LP")
    a.rts()

    # --- GTEXT x, y, "string", color (cmd 8 per character) ---
    a.label("STMT_GTEXT")
    a.jsr("PARSE_2_ARGS") # x in ZP_ARGS+0..1, y in ZP_ARGS+2..3
    a.jsr("SKIP_COMMA")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord('"'))
    a.bne("GTEXT_ERR")
    a.jsr("ADV_TXT")
    # Save pointer to start of string in ZP_DST
    a.lda_zp(ZP_TXT)
    a.sta_zp(ZP_DST)
    a.lda_zp(ZP_TXT + 1)
    a.sta_zp(ZP_DST + 1)
    # Advance ZP_TXT past closing '"'
    a.label("GT_SKIP_STR")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("GT_PARSE_COL")
    a.jsr("ADV_TXT")
    a.cmp_imm(ord('"'))
    a.bne("GT_SKIP_STR")

    a.label("GT_PARSE_COL")
    a.jsr("SKIP_COMMA")
    a.jsr("EVAL_EXPR") # color in ZP_ACC
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_ARGS + 8)

    # Loop through characters at ZP_DST and draw each via cmd 8
    a.label("GT_CHAR_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_DST)
    a.beq("GT_DONE")
    a.cmp_imm(ord('"'))
    a.beq("GT_DONE")
    a.sta_zp(ZP_ARGS + 4) # char code
    a.lda_imm(0)
    a.sta_zp(ZP_ARGS + 5)
    a.sta_zp(ZP_ARGS + 6)
    a.sta_zp(ZP_ARGS + 7)
    a.lda_imm(8)
    a.jsr("SEND_GPU_10")
    # Advance X by 8 pixels
    a.lda_zp(ZP_ARGS)
    a.clc()
    a.adc_imm(8)
    a.sta_zp(ZP_ARGS)
    a.bcc("GT_NXT")
    a.inc_zp(ZP_ARGS + 1)
    a.label("GT_NXT")
    a.inc_zp(ZP_DST)
    a.bne("GT_CHAR_LP")
    a.inc_zp(ZP_DST + 1)
    a.jmp("GT_CHAR_LP")
    a.label("GT_DONE")
    a.rts()
    a.label("GTEXT_ERR")
    a.jmp("SYNTAX_ERR")

    # --- SPRITE id, x, y (cmd 10) ---
    a.label("STMT_SPRITE")
    a.jsr("PARSE_3_ARGS") # id=arg0, x=arg1, y=arg2
    a.lda_imm(10)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 2) # x_lo
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 3) # x_hi
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 4) # y_lo
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 5) # y_hi
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(IO_GPU)
    a.sta_abs(IO_GPU)
    a.sta_abs(IO_GPU)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS)     # sprite_id
    a.sta_abs(IO_GPU)
    a.rts()

    # --- BIGSPR slot, en, x, y [, flip] (cmd 21: 8 bytes) ---
    a.label("STMT_BIGSPR")
    a.jsr("PARSE_4_ARGS") # slot, en, x, y
    a.lda_imm(0)
    a.sta_zp(ZP_ARGS + 8) # default flip = 0
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(","))
    a.bne("BS_SEND")
    a.jsr("ADV_TXT")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_ARGS + 8)
    a.label("BS_SEND")
    a.lda_imm(21)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS)     # slot
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 2) # enable
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 4) # x_lo
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 5) # x_hi
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 6) # y_lo
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 7) # y_hi
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 8) # flags (flip_h)
    a.sta_abs(IO_GPU)
    a.rts()

    # --- SCROLL x, y (cmd 15: 5 bytes) ---
    a.label("STMT_SCROLL")
    a.jsr("PARSE_2_ARGS")
    a.lda_imm(15)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 1)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 2)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 3)
    a.sta_abs(IO_GPU)
    a.rts()

    # --- TILE mx, my, tile_id (cmd 23: 4 bytes) ---
    a.label("STMT_TILE")
    a.jsr("PARSE_3_ARGS")
    a.lda_imm(23)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS)     # mx
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 2) # my
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 4) # tile_id
    a.sta_abs(IO_GPU)
    a.rts()

    # --- FLIP (cmd 11) & TARGET n (cmd 12) ---
    a.label("STMT_FLIP")
    a.lda_imm(11)
    a.sta_abs(IO_GPU)
    a.rts()

    a.label("STMT_TARGET")
    a.jsr("EVAL_EXPR")
    a.lda_imm(12)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ACC)
    a.sta_abs(IO_GPU)
    a.rts()

    # --- SOUND ch, freq_hz, vol (cmd 16: 6 bytes) ---
    # phase_inc = freq_hz * 350 (approx (freq_hz << 24) / 48000 = freq_hz * 349.525)
    a.label("STMT_SOUND")
    a.jsr("PARSE_3_ARGS")
    a.jsr("SEND_SOUND_HW")
    a.rts()

    a.label("SEND_SOUND_HW")
    # Multiply ZP_ARGS+2..3 (freq_hz) by 350 ($015E) -> 24-bit result in ZP_MATH..ZP_MATH+2
    a.lda_imm(0)
    a.sta_zp(ZP_MATH)
    a.sta_zp(ZP_MATH + 1)
    a.sta_zp(ZP_MATH + 2)
    a.lda_zp(ZP_ARGS + 2)
    a.sta_zp(ZP_OP)
    a.lda_zp(ZP_ARGS + 3)
    a.sta_zp(ZP_OP + 1)
    a.lda_imm(0)
    a.sta_zp(ZP_REM)
    # Multiplier = 350 ($015E) in ZP_ACC
    a.lda_imm(350 & 0xFF)
    a.sta_zp(ZP_ACC)
    a.lda_imm(350 >> 8)
    a.sta_zp(ZP_ACC + 1)
    a.ldx_imm(16)
    a.label("SND_MUL_LP")
    a.lsr_zp(ZP_ACC + 1)
    a.ror_zp(ZP_ACC)
    a.bcc("SND_MUL_SH")
    a.clc()
    a.lda_zp(ZP_MATH)
    a.adc_zp(ZP_OP)
    a.sta_zp(ZP_MATH)
    a.lda_zp(ZP_MATH + 1)
    a.adc_zp(ZP_OP + 1)
    a.sta_zp(ZP_MATH + 1)
    a.lda_zp(ZP_MATH + 2)
    a.adc_zp(ZP_REM)
    a.sta_zp(ZP_MATH + 2)
    a.label("SND_MUL_SH")
    a.asl_zp(ZP_OP)
    a.rol_zp(ZP_OP + 1)
    a.rol_zp(ZP_REM)
    a.dex()
    a.bne("SND_MUL_LP")

    a.lda_imm(16)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS)     # channel (0..3)
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_MATH)     # phase_inc_lo
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_MATH + 1) # phase_inc_mid
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_MATH + 2) # phase_inc_hi
    a.sta_abs(IO_GPU)
    a.lda_zp(ZP_ARGS + 4) # volume (0..255)
    a.sta_abs(IO_GPU)
    a.rts()

    # --- BEEP freq_hz, duration_10ms ---
    a.label("STMT_BEEP")
    a.jsr("PARSE_2_ARGS")
    # Move dur to ZP_ARGS+6, freq to ZP_ARGS+2..3, ch=0, vol=200
    a.lda_zp(ZP_ARGS + 2)
    a.sta_zp(ZP_ARGS + 6)
    a.lda_zp(ZP_ARGS)
    a.sta_zp(ZP_ARGS + 2)
    a.lda_zp(ZP_ARGS + 1)
    a.sta_zp(ZP_ARGS + 3)
    a.lda_imm(0)
    a.sta_zp(ZP_ARGS)     # ch = 0
    a.lda_imm(200)
    a.sta_zp(ZP_ARGS + 4) # vol = 200
    a.jsr("SEND_SOUND_HW")
    a.lda_zp(ZP_ARGS + 6)
    a.sta_abs(IO_DELAY)
    # Silence channel 0 after delay
    a.lda_imm(0)
    a.sta_zp(ZP_ARGS + 2)
    a.sta_zp(ZP_ARGS + 3)
    a.sta_zp(ZP_ARGS + 4)
    a.jmp("SEND_SOUND_HW")

    # ========================================================================
    # 8. Program Control: LIST, NEW, RUN, END, SAVE, LOAD, CAT, DEMO, HELP
    # ========================================================================

    # --- NEW ---
    a.label("STMT_NEW")
    a.label("CMD_NEW_INIT")
    a.lda_imm(PRG_BASE & 0xFF)
    a.sta_zp(ZP_PRGEND)
    a.lda_imm(PRG_BASE >> 8)
    a.sta_zp(ZP_PRGEND + 1)
    a.ldy_imm(0)
    a.tya()
    a.sta_iny(ZP_PRGEND)
    a.jsr("CLEAR_VARS")
    a.rts()

    a.label("CLEAR_VARS")
    a.jsr("INIT_GFX_FUNC_STATE")
    a.lda_imm(0)
    a.sta_zp(ZP_GOSUB_SP)
    a.ldx_imm(0)
    a.label("CV_LP")
    a.sta_abx(VARS_BASE)
    a.inx()
    a.cpx_imm(52)
    a.bcc("CV_LP")
    a.rts()

    # --- LIST ---
    a.label("STMT_LIST")
    a.lda_imm(PRG_BASE & 0xFF)
    a.sta_zp(ZP_TMP)
    a.lda_imm(PRG_BASE >> 8)
    a.sta_zp(ZP_TMP + 1)

    a.label("LST_LOOP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.beq("LST_DONE")
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ACC)
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ACC + 1)
    a.jsr("PRINT_INT16")
    a.lda_imm(ord(" "))
    a.jsr("PUTC")

    a.ldy_imm(3)
    a.label("LST_CH")
    a.lda_iny(ZP_TMP)
    a.beq("LST_LN_END")
    a.jsr("PUTC")
    a.iny()
    a.jmp("LST_CH")

    a.label("LST_LN_END")
    a.jsr("NEWLINE")
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.clc()
    a.adc_zp(ZP_TMP)
    a.sta_zp(ZP_TMP)
    a.bcc("LST_LOOP")
    a.inc_zp(ZP_TMP + 1)
    a.jmp("LST_LOOP")

    a.label("LST_DONE")
    a.rts()

    # --- END / STOP ---
    a.label("STMT_END")
    a.lda_imm(0xFF)
    a.sta_zp(ZP_RUN)
    a.lda_imm(1)
    a.sta_abs(IO_MODE)
    a.rts()

    # --- RUN (Pinned at $E876 for MicroSD binary ABI: MC.asm ROM_STMT_RUN) ---
    a.pin_abi(0xE876, "STMT_RUN")
    a.label("STMT_RUN")
    a.jsr("CLEAR_VARS")
    # Default render target = 1 (front buffer) so programs without FLIP draw directly
    a.lda_imm(12)
    a.sta_abs(IO_GPU)
    a.lda_imm(1)
    a.sta_abs(IO_GPU)

    a.lda_imm(PRG_BASE & 0xFF)
    a.sta_zp(ZP_CURLINE)
    a.lda_imm(PRG_BASE >> 8)
    a.sta_zp(ZP_CURLINE + 1)
    a.lda_imm(1)
    a.sta_zp(ZP_RUN)

    a.label("RUN_LINE_LOOP")
    # Check for ESC (0x1B) or Ctrl+C (0x03) break via bit 7 of IO_STATUS ($A000)
    # This does NOT consume normal keys from IO_TERM ($A001) so KEY and INPUT work!
    a.lda_abs(IO_STATUS)
    a.bpl("RUN_NO_BREAK")
    a.lda_abs(IO_TERM) # Acknowledge/clear the ESC key
    a.jmp("RUN_BREAK")

    a.label("RUN_NO_BREAK")
    a.ldy_imm(0)
    a.lda_iny(ZP_CURLINE)
    a.beq("RUN_FINISHED") # End of program

    # Set ZP_TXT to ZP_CURLINE + 3
    a.lda_zp(ZP_CURLINE)
    a.clc()
    a.adc_imm(3)
    a.sta_zp(ZP_TXT)
    a.lda_zp(ZP_CURLINE + 1)
    a.adc_imm(0)
    a.sta_zp(ZP_TXT + 1)

    a.jsr("EXEC_LINE_STATEMENTS")
    a.lda_zp(ZP_RUN)
    a.cmp_imm(0xFF)
    a.beq("RUN_FINISHED")

    a.lda_zp(ZP_JUMPED)
    a.bne("RUN_LINE_LOOP") # ZP_CURLINE and ZP_TXT were already updated by GOTO/GOSUB/NEXT!

    # Advance ZP_CURLINE to next line
    a.ldy_imm(0)
    a.lda_iny(ZP_CURLINE)
    a.clc()
    a.adc_zp(ZP_CURLINE)
    a.sta_zp(ZP_CURLINE)
    a.bcc("RUN_LINE_LOOP")
    a.inc_zp(ZP_CURLINE + 1)
    a.jmp("RUN_LINE_LOOP")

    a.label("RUN_BREAK")
    # Silence all 4 audio channels and restore TARGET 1 & MODE 0 on break
    a.jsr("SILENCE_AUDIO")
    a.lda_imm("<STR_BREAK")
    a.ldy_imm(">STR_BREAK")
    a.jsr("PRINT_STR")
    a.lda_imm(0xFF)
    a.sta_zp(ZP_RUN)
    a.rts()

    a.label("RUN_FINISHED")
    a.jmp("SILENCE_AUDIO")

    # Pinned at $E8DC for MicroSD binary ABI (MC, CALC, WRITER, SPREDIT, RFTS, BROWSER, IMPRESS, NETTERM)
    a.pin_abi(0xE8DC, "SILENCE_AUDIO")
    a.label("SILENCE_AUDIO")
    a.jmp("SILENCE_AUDIO_EXT")

    # ========================================================================
    # 9. MicroSD SPI ($A010-$A011) & 4 MB SDRAM-Disk ($A012-$A015) Storage
    #    Supports: CAT/*CAT/FILES/DIR/*INFO, *SD, *SDRAM, *DRIVE 0..3,
    #              SAVE "NAAM" / SAVE 0..14, LOAD "NAAM" / LOAD 0..14
    # ========================================================================

    # --- Low-level SPI & SDHC/SDSC Primitives ---
    a.label("SPI_TXRX")
    a.sta_abs(IO_SD_DATA)
    a.lda_abs(IO_SD_DATA)
    a.rts()

    a.label("SPI_FF")
    a.lda_imm(0xFF)
    a.sta_abs(IO_SD_DATA)
    a.lda_abs(IO_SD_DATA)
    a.rts()

    a.label("SD_DESELECT")
    a.lda_abs(DISK_CTRL_SH)
    a.ora_imm(0x01)
    a.sta_abs(DISK_CTRL_SH)
    a.sta_abs(IO_SD_CTRL)
    a.jmp("SPI_FF")

    a.label("SD_SELECT")
    a.jsr("SPI_FF")
    a.lda_abs(DISK_CTRL_SH)
    a.and_imm(0xFE)
    a.sta_abs(DISK_CTRL_SH)
    a.sta_abs(IO_SD_CTRL)
    a.jmp("SPI_FF")

    a.label("SD_WAIT_R1")
    a.ldx_imm(0x20)
    a.label("SWR1_LP")
    a.jsr("SPI_FF")
    a.tay()
    a.bpl("SWR1_DN")
    a.dex()
    a.bne("SWR1_LP")
    a.label("SWR1_DN")
    a.tya()
    a.rts()

    # Helper: Send SPI command in A with 4 zero argument bytes and CRC in Y, return R1 in A
    a.label("SD_CMD_0000")
    a.ldx_imm(0)
    a.label("SD_CMD_X000") # arg3 in X
    a.pha()
    a.jsr("SD_DESELECT")
    a.jsr("SD_SELECT")
    a.pla()
    a.jsr("SPI_TXRX")
    a.txa()
    a.jsr("SPI_TXRX")
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.tya()
    a.jsr("SPI_TXRX")
    a.jmp("SD_WAIT_R1")

    # Pinned at $E96A for MicroSD binary ABI (ROM_SD_INIT)
    a.pin_abi(0xE96A, "SD_INIT")
    a.label("SD_INIT")
    a.lda_abs(DISK_FORCE_RD)
    a.bmi("SD_NO_CARD")
    a.lda_imm(0x03) # slow_mode=1, CS=1
    a.sta_abs(DISK_CTRL_SH)
    a.sta_abs(IO_SD_CTRL)
    a.ldx_imm(16)
    a.label("SDI_CLK")
    a.jsr("SPI_FF")
    a.dex()
    a.bne("SDI_CLK")

    a.lda_imm(8)
    a.sta_zp(ZP_MATH)
    a.label("SDI_CMD0")
    a.lda_imm(0x40)
    a.ldy_imm(0x95)
    a.jsr("SD_CMD_0000")
    a.cmp_imm(0x01)
    a.beq("SDI_CMD8")
    a.dec_zp(ZP_MATH)
    a.bne("SDI_CMD0")

    a.label("SD_NO_CARD")
    a.lda_imm(0)
    a.sta_abs(DISK_SD_TYPE)
    a.jmp("SD_DESELECT")

    a.label("SDI_CMD8")
    a.jsr("SD_DESELECT")
    a.jsr("SD_SELECT")
    a.lda_imm(0x48)
    a.jsr("SPI_TXRX")
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.lda_imm(1)
    a.jsr("SPI_TXRX")
    a.lda_imm(0xAA)
    a.jsr("SPI_TXRX")
    a.lda_imm(0x87)
    a.jsr("SPI_TXRX")
    a.jsr("SD_WAIT_R1")
    a.ldx_imm(4)
    a.label("SDI_R7")
    a.jsr("SPI_FF")
    a.dex()
    a.bne("SDI_R7")

    a.lda_imm(0)
    a.sta_zp(ZP_MATH)
    a.lda_imm(8)
    a.sta_zp(ZP_MATH + 1)
    a.label("SDI_ACMD41")
    a.lda_imm(0x77) # CMD55
    a.ldy_imm(0x65)
    a.jsr("SD_CMD_0000")
    a.lda_imm(0x69) # ACMD41
    a.ldx_imm(0x40)
    a.ldy_imm(0x77)
    a.jsr("SD_CMD_X000")
    a.cmp_imm(0)
    a.beq("SDI_CMD58")
    a.dec_zp(ZP_MATH)
    a.bne("SDI_ACMD41")
    a.dec_zp(ZP_MATH + 1)
    a.bne("SDI_ACMD41")
    a.jmp("SD_NO_CARD")

    a.label("SDI_CMD58")
    a.lda_imm(0x7A)
    a.ldy_imm(0xFD)
    a.jsr("SD_CMD_0000")
    a.jsr("SPI_FF")
    a.pha()
    a.jsr("SPI_FF")
    a.jsr("SPI_FF")
    a.jsr("SPI_FF")
    a.pla()
    a.and_imm(0x40)
    a.beq("SDI_SDSC")
    a.lda_imm(0x80)
    a.bne("SDI_SET_T")
    a.label("SDI_SDSC")
    a.lda_imm(0x01)
    a.label("SDI_SET_T")
    a.sta_abs(DISK_SD_TYPE)
    a.lda_imm(0x01) # fast SPI mode (3.375 MHz), CS=1
    a.sta_abs(DISK_CTRL_SH)
    a.jmp("SD_DESELECT")

    # Send CMD17 ($51) or CMD24 ($58) in A for sector (DISK_SEC_HI:DISK_SEC_LO)
    a.label("SD_SEND_RW")
    a.pha()
    a.jsr("SD_DESELECT")
    a.jsr("SD_SELECT")
    a.pla()
    a.jsr("SPI_TXRX")
    a.lda_abs(DISK_SD_TYPE)
    a.bmi("SSRW_SDHC")
    a.lda_abs(DISK_SEC_LO)
    a.asl_a()
    a.tax()
    a.lda_abs(DISK_SEC_HI)
    a.rol_a()
    a.tay()
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.tya()
    a.jsr("SPI_TXRX")
    a.txa()
    a.jsr("SPI_TXRX")
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.jmp("SSRW_CRC")
    a.label("SSRW_SDHC")
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.lda_imm(0)
    a.jsr("SPI_TXRX")
    a.lda_abs(DISK_SEC_HI)
    a.jsr("SPI_TXRX")
    a.lda_abs(DISK_SEC_LO)
    a.jsr("SPI_TXRX")
    a.label("SSRW_CRC")
    a.lda_imm(0xFF)
    a.jsr("SPI_TXRX")
    a.jmp("SD_WAIT_R1")

    # Read 512-byte sector (DISK_SEC_HI:DISK_SEC_LO) into (ZP_DST), advances ZP_DST+1 by 2 & increments sector
    # Pinned at $EA67 for MicroSD binary ABI (ROM_READ_SEC)
    a.pin_abi(0xEA67, "DISK_READ_SEC")
    a.label("DISK_READ_SEC")
    a.lda_abs(DISK_SD_TYPE)
    a.bne("DRS_SD")
    a.lda_abs(DISK_SEC_LO)
    a.asl_a()
    a.sta_abs(IO_RD_HI)
    a.lda_abs(DISK_SEC_HI)
    a.rol_a()
    a.sta_abs(IO_RD_BANK)
    a.ldy_imm(0)
    a.label("DRS_RD0")
    a.sty_abs(IO_RD_LO)
    a.lda_abs(IO_RD_DATA)
    a.sta_iny(ZP_DST)
    a.iny()
    a.bne("DRS_RD0")
    a.inc_zp(ZP_DST + 1)
    a.inc_abs(IO_RD_HI)
    a.label("DRS_RD1")
    a.sty_abs(IO_RD_LO)
    a.lda_abs(IO_RD_DATA)
    a.sta_iny(ZP_DST)
    a.iny()
    a.bne("DRS_RD1")
    a.inc_zp(ZP_DST + 1)
    a.jmp("DRS_INC_SEC")

    a.label("DRS_SD")
    a.lda_imm(0x51) # CMD17
    a.jsr("SD_SEND_RW")
    a.ldx_imm(0)
    a.ldy_imm(0)
    a.label("DRS_WFE")
    a.jsr("SPI_FF")
    a.cmp_imm(0xFE)
    a.beq("DRS_GOT_FE")
    a.inx()
    a.bne("DRS_WFE")
    a.iny()
    a.bne("DRS_WFE")
    a.label("DRS_GOT_FE")
    a.ldy_imm(0)
    a.label("DRS_SP0")
    a.jsr("SPI_FF")
    a.sta_iny(ZP_DST)
    a.iny()
    a.bne("DRS_SP0")
    a.inc_zp(ZP_DST + 1)
    a.label("DRS_SP1")
    a.jsr("SPI_FF")
    a.sta_iny(ZP_DST)
    a.iny()
    a.bne("DRS_SP1")
    a.inc_zp(ZP_DST + 1)
    a.jsr("SPI_FF")
    a.jsr("SPI_FF")
    a.jsr("SD_DESELECT")
    a.label("DRS_INC_SEC")
    a.inc_abs(DISK_SEC_LO)
    a.bne("DRS_DN")
    a.inc_abs(DISK_SEC_HI)
    a.label("DRS_DN")
    a.rts()

    # Write 512-byte sector from (ZP_DST) to (DISK_SEC_HI:DISK_SEC_LO)
    # Pinned at $EADA for MicroSD binary ABI (ROM_WRITE_SEC)
    a.pin_abi(0xEADA, "DISK_WRITE_SEC")
    a.label("DISK_WRITE_SEC")
    a.lda_abs(DISK_SD_TYPE)
    a.bne("DWS_SD")
    a.lda_abs(DISK_SEC_LO)
    a.asl_a()
    a.sta_abs(IO_RD_HI)
    a.lda_abs(DISK_SEC_HI)
    a.rol_a()
    a.sta_abs(IO_RD_BANK)
    a.ldy_imm(0)
    a.label("DWS_RD0")
    a.sty_abs(IO_RD_LO)
    a.lda_iny(ZP_DST)
    a.sta_abs(IO_RD_DATA)
    a.iny()
    a.bne("DWS_RD0")
    a.inc_zp(ZP_DST + 1)
    a.inc_abs(IO_RD_HI)
    a.label("DWS_RD1")
    a.sty_abs(IO_RD_LO)
    a.lda_iny(ZP_DST)
    a.sta_abs(IO_RD_DATA)
    a.iny()
    a.bne("DWS_RD1")
    a.inc_zp(ZP_DST + 1)
    a.jmp("DRS_INC_SEC")

    a.label("DWS_SD")
    a.lda_imm(0x58) # CMD24
    a.jsr("SD_SEND_RW")
    a.jsr("SPI_FF")
    a.jsr("SPI_FF")
    a.lda_imm(0xFE)
    a.jsr("SPI_TXRX")
    a.ldy_imm(0)
    a.label("DWS_SP0")
    a.lda_iny(ZP_DST)
    a.jsr("SPI_TXRX")
    a.iny()
    a.bne("DWS_SP0")
    a.inc_zp(ZP_DST + 1)
    a.label("DWS_SP1")
    a.lda_iny(ZP_DST)
    a.jsr("SPI_TXRX")
    a.iny()
    a.bne("DWS_SP1")
    a.inc_zp(ZP_DST + 1)
    a.jsr("SPI_FF")
    a.jsr("SPI_FF")
    a.jsr("SPI_FF")
    a.ldx_imm(0)
    a.ldy_imm(0)
    a.label("DWS_WBSY")
    a.jsr("SPI_FF")
    a.cmp_imm(0xFF)
    a.beq("DWS_WDN")
    a.inx()
    a.bne("DWS_WBSY")
    a.iny()
    a.bne("DWS_WBSY")
    a.label("DWS_WDN")
    a.jsr("SD_DESELECT")
    a.jmp("DRS_INC_SEC")

    # Setup directory sector ($03FF + DISK_DRIVE * $0400) and ZP_DST = SD_BUF ($0500)
    a.label("SETUP_DIR_SEC")
    a.lda_imm(0x00)
    a.sta_zp(ZP_DST)
    a.lda_imm(SD_BUF >> 8)
    a.sta_zp(ZP_DST + 1)
    a.lda_imm(0xFF)
    a.sta_abs(DISK_SEC_LO)
    a.lda_abs(DISK_DRIVE)
    a.and_imm(0x3F)
    a.asl_a()
    a.asl_a()
    a.clc()
    a.adc_imm(0x03)
    a.sta_abs(DISK_SEC_HI)
    a.rts()

    # Setup data sector for slot in DISK_SLOT: ($0400 + DISK_DRIVE*$0400) + slot*64
    a.label("SETUP_SLOT_SEC")
    a.lda_abs(DISK_SLOT)
    a.and_imm(0x03)
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.sta_abs(DISK_SEC_LO)
    a.lda_abs(DISK_DRIVE)
    a.and_imm(0x3F)
    a.asl_a()
    a.asl_a()
    a.clc()
    a.adc_imm(0x04)
    a.sta_abs(DISK_SEC_HI)
    a.lda_abs(DISK_SLOT)
    a.lsr_a()
    a.lsr_a()
    a.clc()
    a.adc_abs(DISK_SEC_HI)
    a.sta_abs(DISK_SEC_HI)
    a.rts()

    # Compute ZP_TMP = SD_BUF + DISK_SLOT * 32
    a.label("CALC_DIR_PTR")
    a.lda_abs(DISK_SLOT)
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.sta_zp(ZP_TMP)
    a.lda_abs(DISK_SLOT)
    a.lsr_a()
    a.lsr_a()
    a.lsr_a()
    a.clc()
    a.adc_imm(SD_BUF >> 8)
    a.sta_zp(ZP_TMP + 1)
    a.rts()

    # Check if directory entry at (ZP_TMP) has magic "BBC!"
    a.label("CHK_BBC_MAGIC")
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("B"))
    a.bne("CBM_NO")
    a.iny()
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("B"))
    a.bne("CBM_NO")
    a.iny()
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("C"))
    a.bne("CBM_NO")
    a.iny()
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("!"))
    a.label("CBM_NO")
    a.rts()

    # Print "[SD-KAART Dx] " or "[SDRAM-DISK Dx] "
    a.label("PRINT_STORAGE_TAG")
    a.lda_abs(DISK_SD_TYPE)
    a.beq("PST_RD")
    a.lda_imm("<STR_TAG_SD")
    a.ldy_imm(">STR_TAG_SD")
    a.jsr("PRINT_STR")
    a.jmp("PST_DRV")
    a.label("PST_RD")
    a.lda_imm("<STR_TAG_RD")
    a.ldy_imm(">STR_TAG_RD")
    a.jsr("PRINT_STR")
    a.label("PST_DRV")
    a.lda_abs(DISK_DRIVE)
    a.sta_zp(ZP_ACC)
    a.lda_imm(0)
    a.sta_zp(ZP_ACC + 1)
    a.jsr("PRINT_INT16")
    a.lda_imm(ord("]"))
    a.jsr("PUTC")
    a.lda_imm(ord(" "))
    a.jmp("PUTC")

    # Parse filename ("NAAM" or unquoted NAAM) or slot number (0..14) into FNAME_BUF ($0480)
    # Sets DISK_SLOT to 0..14 if numeric slot given, or $FF if named file given!
    a.label("PARSE_FILE_SPEC")
    a.jsr("SKIP_SPACES")
    a.ldx_imm(0)
    a.lda_imm(0)
    a.label("PFS_CLR")
    a.sta_abx(FNAME_BUF)
    a.inx()
    a.cpx_imm(16)
    a.bcc("PFS_CLR")

    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("PFS_DEF_SLOT0")
    a.cmp_imm(ord(":"))
    a.beq("PFS_DEF_SLOT0")
    a.cmp_imm(ord('"'))
    a.beq("PFS_QUOTED")
    a.jsr("IS_DIGIT")
    a.bcs("PFS_NUMERIC")

    # Unquoted filename
    a.ldx_imm(0)
    a.label("PFS_UNQ_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("PFS_NAMED_DN")
    a.cmp_imm(ord(" "))
    a.beq("PFS_NAMED_DN")
    a.cmp_imm(ord(":"))
    a.beq("PFS_NAMED_DN")
    a.sta_abx(FNAME_BUF)
    a.jsr("ADV_TXT")
    a.inx()
    a.cpx_imm(15)
    a.bcc("PFS_UNQ_LP")
    a.jmp("PFS_NAMED_DN")

    a.label("PFS_QUOTED")
    a.jsr("ADV_TXT")
    a.ldx_imm(0)
    a.label("PFS_Q_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("PFS_NAMED_DN")
    a.cmp_imm(ord('"'))
    a.beq("PFS_Q_END")
    # Ensure uppercase
    a.cmp_imm(ord("a"))
    a.bcc("PFS_Q_ST")
    a.cmp_imm(ord("z") + 1)
    a.bcs("PFS_Q_ST")
    a.sec()
    a.sbc_imm(0x20)
    a.label("PFS_Q_ST")
    a.sta_abx(FNAME_BUF)
    a.jsr("ADV_TXT")
    a.inx()
    a.cpx_imm(15)
    a.bcc("PFS_Q_LP")
    a.label("PFS_Q_END")
    a.jsr("ADV_TXT")
    a.label("PFS_NAMED_DN")
    a.lda_imm(0xFF)
    a.sta_abs(DISK_SLOT)
    a.rts()

    a.label("PFS_DEF_SLOT0")
    a.lda_imm(0)
    a.jmp("PFS_SET_SLOT")

    a.label("PFS_NUMERIC")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.and_imm(0x0F)
    a.cmp_imm(15)
    a.bcc("PFS_SET_SLOT")
    a.lda_imm(14)
    a.label("PFS_SET_SLOT")
    a.sta_abs(DISK_SLOT)
    # Also build default name "SLOTx" in FNAME_BUF
    a.lda_imm(ord("S"))
    a.sta_abs(FNAME_BUF)
    a.lda_imm(ord("L"))
    a.sta_abs(FNAME_BUF + 1)
    a.lda_imm(ord("O"))
    a.sta_abs(FNAME_BUF + 2)
    a.lda_imm(ord("T"))
    a.sta_abs(FNAME_BUF + 3)
    a.lda_abs(DISK_SLOT)
    a.cmp_imm(10)
    a.bcc("PFS_SL_1D")
    a.pha()
    a.lda_imm(ord("1"))
    a.sta_abs(FNAME_BUF + 4)
    a.pla()
    a.sec()
    a.sbc_imm(10)
    a.clc()
    a.adc_imm(ord("0"))
    a.sta_abs(FNAME_BUF + 5)
    a.rts()
    a.label("PFS_SL_1D")
    a.clc()
    a.adc_imm(ord("0"))
    a.sta_abs(FNAME_BUF + 4)
    a.rts()

    # --- *SD / SD: Switch to MicroSD card and display catalog ---
    a.label("STMT_SD")
    a.lda_imm(0x00)
    a.sta_abs(DISK_FORCE_RD)
    a.jmp("STMT_CAT")

    # --- *SDRAM / SDRAM: Switch to 4 MB SDRAM-Disk and display catalog ---
    a.label("STMT_SDRAM")
    a.lda_imm(0x80)
    a.sta_abs(DISK_FORCE_RD)
    a.jmp("STMT_CAT")

    # --- *DRIVE 0..3 / DRIVE 0..3: Select drive and display catalog ---
    a.label("STMT_DRIVE")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("STMT_CAT")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.and_imm(0x3F)
    a.sta_abs(DISK_DRIVE)
    a.jmp("STMT_CAT")

    # --- CAT / *CAT / FILES / DIR / *INFO ---
    a.label("STMT_CAT")
    a.jsr("SD_INIT")
    a.jsr("SETUP_DIR_SEC")
    a.jsr("DISK_READ_SEC")
    a.jsr("PRINT_STORAGE_TAG")
    a.lda_imm("<STR_CAT_HDR")
    a.ldy_imm(">STR_CAT_HDR")
    a.jsr("PRINT_STR")

    a.lda_imm(0)
    a.sta_abs(DISK_SLOT)
    a.sta_zp(ZP_SIGN) # Count of files found

    a.label("CAT_SLOT_LP")
    a.jsr("CALC_DIR_PTR")
    a.jsr("CHK_BBC_MAGIC")
    a.bne("CAT_NEXT_SLOT")

    a.inc_zp(ZP_SIGN)
    a.lda_imm(ord(" "))
    a.jsr("PUTC")
    a.lda_imm(ord("#"))
    a.jsr("PUTC")
    a.lda_abs(DISK_SLOT)
    a.sta_zp(ZP_ACC)
    a.lda_imm(0)
    a.sta_zp(ZP_ACC + 1)
    a.jsr("PRINT_INT16")
    a.lda_imm(ord(":"))
    a.jsr("PUTC")
    a.lda_imm(ord(" "))
    a.jsr("PUTC")

    # Recompute ZP_TMP (since PRINT_INT16 / PRINT_STR uses ZP_TMP)
    a.jsr("CALC_DIR_PTR")
    a.ldy_imm(4)
    a.label("CAT_FN_LP")
    a.lda_iny(ZP_TMP)
    a.beq("CAT_FN_PAD")
    a.jsr("PUTC")
    a.iny()
    a.cpy_imm(18)
    a.bcc("CAT_FN_LP")
    a.jmp("CAT_PRT_SZ")
    a.label("CAT_FN_PAD")
    a.lda_imm(ord(" "))
    a.jsr("PUTC")
    a.iny()
    a.cpy_imm(18)
    a.bcc("CAT_FN_PAD")

    a.label("CAT_PRT_SZ")
    a.ldy_imm(22)
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("D"))
    a.bne("CAT_PRT_B")
    a.lda_imm("<STR_MAP")
    a.ldy_imm(">STR_MAP")
    a.jmp("CAT_PRT_S")
    a.label("CAT_PRT_B")
    a.lda_imm(ord("("))
    a.jsr("PUTC")
    a.ldy_imm(20)
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ACC)
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ACC + 1)
    a.jsr("PRINT_INT16")
    a.lda_imm("<STR_BYTES")
    a.ldy_imm(">STR_BYTES")
    a.label("CAT_PRT_S")
    a.jsr("PRINT_STR")

    a.label("CAT_NEXT_SLOT")
    a.inc_abs(DISK_SLOT)
    a.lda_abs(DISK_SLOT)
    a.cmp_imm(15)
    a.bcc("CAT_SLOT_LP")

    a.lda_zp(ZP_SIGN)
    a.bne("CAT_DONE")
    a.lda_imm("<STR_CAT_EMPTY")
    a.ldy_imm(">STR_CAT_EMPTY")
    a.jmp("PRINT_STR")
    a.label("CAT_DONE")
    a.rts()

    # Match FNAME_BUF against entry at ZP_TMP (returns Z=1 if match)
    a.label("MATCH_DIR_NAME")
    a.jsr("CHK_BBC_MAGIC")
    a.bne("MDN_NO")
    a.ldx_imm(0)
    a.ldy_imm(4)
    a.label("MDN_LP")
    a.lda_iny(ZP_TMP)
    a.cmp_abx(FNAME_BUF)
    a.bne("MDN_NO")
    a.lda_abx(FNAME_BUF)
    a.beq("MDN_YES")
    a.iny()
    a.inx()
    a.cpx_imm(15)
    a.bcc("MDN_LP")
    a.label("MDN_YES")
    a.lda_imm(0)
    a.rts()
    a.label("MDN_NO")
    a.lda_imm(1)
    a.rts()

    # --- SAVE / BSAVE ["NAAM" | 0..14] [, addr, len] ---
    a.label("STMT_SAVE")
    a.jsr("PARSE_FILE_SPEC")
    # Default: BASIC program at PRG_BASE ($0800), length = (ZP_PRGEND - PRG_BASE) + 1, type = 'M'
    a.lda_imm(PRG_BASE & 0xFF)
    a.sta_zp(ZP_ARGS)
    a.lda_imm(PRG_BASE >> 8)
    a.sta_zp(ZP_ARGS + 1)
    a.sec()
    a.lda_zp(ZP_PRGEND)
    a.sbc_imm(PRG_BASE & 0xFF)
    a.sta_zp(ZP_ARGS + 2)
    a.lda_zp(ZP_PRGEND + 1)
    a.sbc_imm(PRG_BASE >> 8)
    a.sta_zp(ZP_ARGS + 3)
    a.inc_zp(ZP_ARGS + 2)
    a.bne("SV_DEF_OK")
    a.inc_zp(ZP_ARGS + 3)
    a.label("SV_DEF_OK")
    a.lda_imm(ord("M"))
    a.sta_zp(ZP_ARGS + 4)

    # Check if optional [, addr, len] follows for 6502 binary save (BSAVE / SAVE "NAAM", addr, len)
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("SV_DO_INIT")
    a.cmp_imm(ord(":"))
    a.beq("SV_DO_INIT")
    a.jsr("SKIP_COMMA")
    a.jsr("PARSE_2_ARGS") # ZP_ARGS[0..1] = addr, ZP_ARGS[2..3] = len
    a.lda_imm(ord("B"))
    a.sta_zp(ZP_ARGS + 4)

    a.label("SV_DO_INIT")
    a.jsr("SD_INIT")
    a.jsr("SETUP_DIR_SEC")
    a.jsr("DISK_READ_SEC")

    a.lda_abs(DISK_SLOT)
    a.bpl("SV_HAVE_SLOT")

    # Search by filename in slots 0..14, or pick first free slot
    a.lda_imm(0xFF)
    a.sta_abs(DISK_FREE)
    a.lda_imm(0)
    a.sta_abs(DISK_SLOT)
    a.label("SV_FIND_LP")
    a.jsr("CALC_DIR_PTR")
    a.jsr("MATCH_DIR_NAME")
    a.beq("SV_HAVE_SLOT")
    a.jsr("CHK_BBC_MAGIC")
    a.beq("SV_F_NEXT")
    a.lda_abs(DISK_FREE)
    a.bpl("SV_F_NEXT")
    a.lda_abs(DISK_SLOT)
    a.sta_abs(DISK_FREE)
    a.label("SV_F_NEXT")
    a.inc_abs(DISK_SLOT)
    a.lda_abs(DISK_SLOT)
    a.cmp_imm(15)
    a.bcc("SV_FIND_LP")
    a.lda_abs(DISK_FREE)
    a.bpl("SV_SET_FREE")
    a.lda_imm(0)
    a.label("SV_SET_FREE")
    a.sta_abs(DISK_SLOT)

    a.label("SV_HAVE_SLOT")
    a.jsr("CALC_DIR_PTR")
    # Write "BBC!" magic + filename + byte size + 'M'/'B' marker + start_addr
    a.ldy_imm(0)
    a.lda_imm(ord("B"))
    a.sta_iny(ZP_TMP)
    a.iny()
    a.sta_iny(ZP_TMP)
    a.iny()
    a.lda_imm(ord("C"))
    a.sta_iny(ZP_TMP)
    a.iny()
    a.lda_imm(ord("!"))
    a.sta_iny(ZP_TMP)

    a.ldx_imm(0)
    a.ldy_imm(4)
    a.label("SV_WR_FN")
    a.lda_abx(FNAME_BUF)
    a.sta_iny(ZP_TMP)
    a.inx()
    a.iny()
    a.cpx_imm(16)
    a.bcc("SV_WR_FN")

    a.ldy_imm(20)
    a.lda_zp(ZP_ARGS + 2)
    a.sta_iny(ZP_TMP)
    a.iny()
    a.lda_zp(ZP_ARGS + 3)
    a.sta_iny(ZP_TMP)
    a.iny()
    a.lda_zp(ZP_ARGS + 4) # 'M' (BASIC) or 'B' (Binary 6502 code)
    a.sta_iny(ZP_TMP)
    a.iny()
    a.lda_zp(ZP_ARGS)
    a.sta_iny(ZP_TMP)
    a.iny()
    a.lda_zp(ZP_ARGS + 1)
    a.sta_iny(ZP_TMP)

    # Write updated directory sector back
    a.jsr("SETUP_DIR_SEC")
    a.jsr("DISK_WRITE_SEC")

    # Write sectors from ZP_ARGS[0..1] to slot sectors
    a.jsr("SETUP_SLOT_SEC")
    a.lda_zp(ZP_ARGS)
    a.sta_zp(ZP_DST)
    a.lda_zp(ZP_ARGS + 1)
    a.sta_zp(ZP_DST + 1)
    # Number of 512-byte sectors = (len_hi >> 1) + 1
    a.lda_zp(ZP_ARGS + 3)
    a.lsr_a()
    a.clc()
    a.adc_imm(1)
    a.sta_zp(ZP_SIGN)
    a.label("SV_SEC_LP")
    a.jsr("DISK_WRITE_SEC")
    a.dec_zp(ZP_SIGN)
    a.bne("SV_SEC_LP")

    a.jsr("PRINT_STORAGE_TAG")
    a.lda_imm("<STR_SAVED")
    a.ldy_imm(">STR_SAVED")
    a.jmp("PRINT_STR")

    # --- BRUN "NAAM" [, addr] (loads binary from SD card and executes it immediately!) ---
    a.label("STMT_BRUN")
    a.jsr("STMT_LOAD")
    a.lda_zp(ZP_ARGS + 4)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_ARGS + 5)
    a.beq("BRUN_ABORT")
    a.sta_zp(ZP_ACC + 1)
    a.jmp("CALL_ACC")
    a.label("BRUN_ABORT")
    a.rts()

    # --- LOAD / BLOAD ["NAAM" | 0..14] [, addr] ---
    a.label("STMT_LOAD")
    a.jsr("PARSE_FILE_SPEC")
    a.lda_imm(0)
    a.sta_zp(ZP_ARGS + 2)
    a.sta_zp(ZP_ARGS + 5)
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("LD_DO_INIT")
    a.cmp_imm(ord(":"))
    a.beq("LD_DO_INIT")
    a.jsr("SKIP_COMMA")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_ARGS)
    a.lda_zp(ZP_ACC + 1)
    a.sta_zp(ZP_ARGS + 1)
    a.lda_imm(1)
    a.sta_zp(ZP_ARGS + 2)

    a.label("LD_DO_INIT")
    a.jsr("SD_INIT")
    a.jsr("SETUP_DIR_SEC")
    a.jsr("DISK_READ_SEC")

    a.lda_abs(DISK_SLOT)
    a.bpl("LD_CHECK_SLOT")

    # Search by filename in slots 0..14
    a.lda_imm(0)
    a.sta_abs(DISK_SLOT)
    a.label("LD_FIND_LP")
    a.jsr("CALC_DIR_PTR")
    a.jsr("MATCH_DIR_NAME")
    a.beq("LD_FOUND")
    a.inc_abs(DISK_SLOT)
    a.lda_abs(DISK_SLOT)
    a.cmp_imm(15)
    a.bcc("LD_FIND_LP")
    a.jmp("LD_EMPTY")

    a.label("LD_CHECK_SLOT")
    a.jsr("CALC_DIR_PTR")
    a.jsr("CHK_BBC_MAGIC")
    a.bne("LD_EMPTY")

    a.label("LD_FOUND")
    a.ldy_imm(22)
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("D"))
    a.bne("LD_NOT_DIR")
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_abs(DISK_DRIVE)
    a.jmp("STMT_CAT")
    a.label("LD_NOT_DIR")
    a.ldy_imm(20)
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_OP)
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_OP + 1)

    # Determine target load address -> ZP_DST and save copy in ZP_ARGS+4..5
    a.lda_zp(ZP_ARGS + 2)
    a.bne("LD_USE_CUSTOM")
    a.ldy_imm(22)
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("B"))
    a.bne("LD_USE_PRG")
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ARGS)
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ARGS + 1)
    a.jmp("LD_USE_CUSTOM")

    a.label("LD_USE_PRG")
    a.lda_imm(PRG_BASE & 0xFF)
    a.sta_zp(ZP_ARGS)
    a.lda_imm(PRG_BASE >> 8)
    a.sta_zp(ZP_ARGS + 1)

    a.label("LD_USE_CUSTOM")
    a.lda_zp(ZP_ARGS)
    a.sta_zp(ZP_DST)
    a.sta_zp(ZP_ARGS + 4)
    a.lda_zp(ZP_ARGS + 1)
    a.sta_zp(ZP_DST + 1)
    a.sta_zp(ZP_ARGS + 5)

    a.jsr("SETUP_SLOT_SEC")
    a.lda_zp(ZP_OP + 1)
    a.lsr_a()
    a.clc()
    a.adc_imm(1)
    a.sta_zp(ZP_SIGN)
    a.label("LD_SEC_LP")
    a.jsr("DISK_READ_SEC")
    a.dec_zp(ZP_SIGN)
    a.bne("LD_SEC_LP")

    # Only update ZP_PRGEND if loaded into PRG_BASE ($0800)
    a.lda_zp(ZP_ARGS + 4)
    a.bne("LD_SKIP_PRGEND")
    a.lda_zp(ZP_ARGS + 5)
    a.cmp_imm(PRG_BASE >> 8)
    a.bne("LD_SKIP_PRGEND")

    # Set ZP_PRGEND = PRG_BASE + ZP_OP - 1 and ensure null terminator
    a.clc()
    a.lda_imm(PRG_BASE & 0xFF)
    a.adc_zp(ZP_OP)
    a.sta_zp(ZP_PRGEND)
    a.lda_imm(PRG_BASE >> 8)
    a.adc_zp(ZP_OP + 1)
    a.sta_zp(ZP_PRGEND + 1)
    a.lda_zp(ZP_PRGEND)
    a.bne("LD_DEC1")
    a.dec_zp(ZP_PRGEND + 1)
    a.label("LD_DEC1")
    a.dec_zp(ZP_PRGEND)
    a.ldy_imm(0)
    a.tya()
    a.sta_iny(ZP_PRGEND)

    a.label("LD_SKIP_PRGEND")
    a.jsr("PRINT_STORAGE_TAG")
    a.lda_imm("<STR_LOADED")
    a.ldy_imm(">STR_LOADED")
    a.jmp("PRINT_STR")

    a.label("LD_EMPTY")
    a.lda_imm("<STR_SLOT_EMPTY")
    a.ldy_imm(">STR_SLOT_EMPTY")
    a.jmp("PRINT_STR")

    # --- HELP ---
    a.label("STMT_HELP")
    a.lda_imm("<STR_HELP")
    a.ldy_imm(">STR_HELP")
    a.jmp("PRINT_STR")

    # --- DEMO 1..5: Load built-in ROM demo program into $0800 (DEMO 5 also loads 6502 ASM into $8000!) ---
    a.label("STMT_DEMO")
    a.jsr("EVAL_EXPR")
    a.jsr("CMD_NEW_INIT")
    a.lda_zp(ZP_ACC)
    a.cmp_imm(2)
    a.beq("DEMO_2")
    a.cmp_imm(3)
    a.beq("DEMO_3")
    a.cmp_imm(4)
    a.beq("DEMO_4")
    a.cmp_imm(5)
    a.beq("DEMO_5")

    a.lda_imm("<ROM_DEMO1")
    a.ldy_imm(">ROM_DEMO1")
    a.jmp("LOAD_ROM_DEMO")
    a.label("DEMO_2")
    a.lda_imm("<ROM_DEMO2")
    a.ldy_imm(">ROM_DEMO2")
    a.jmp("LOAD_ROM_DEMO")
    a.label("DEMO_3")
    a.lda_imm("<ROM_DEMO3")
    a.ldy_imm(">ROM_DEMO3")
    a.jmp("LOAD_ROM_DEMO")
    a.label("DEMO_4")
    a.lda_imm("<ROM_DEMO4")
    a.ldy_imm(">ROM_DEMO4")
    a.jmp("LOAD_ROM_DEMO")
    a.label("DEMO_5")
    a.ldx_imm(0)
    a.label("D5_CP_LP")
    a.lda_abx("ROM_ASM_CODE")
    a.sta_abx(0x8000)
    a.inx()
    a.cpx_imm(188)
    a.bcc("D5_CP_LP")
    a.lda_imm("<ROM_DEMO5")
    a.ldy_imm(">ROM_DEMO5")

    a.label("LOAD_ROM_DEMO")
    a.sta_zp(ZP_OP)
    a.sty_zp(ZP_OP + 1)
    a.lda_imm(PRG_BASE & 0xFF)
    a.sta_zp(ZP_TMP)
    a.lda_imm(PRG_BASE >> 8)
    a.sta_zp(ZP_TMP + 1)

    a.label("LRD_LINE_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_OP)
    a.sta_iny(ZP_TMP)
    a.beq("LRD_DONE") # 0x00 record length marks end of demo!
    a.tax() # X = record byte length
    a.label("LRD_BYTE_LP")
    a.lda_iny(ZP_OP)
    a.sta_iny(ZP_TMP)
    a.inc_zp(ZP_OP)
    a.bne("LRD_B1")
    a.inc_zp(ZP_OP + 1)
    a.label("LRD_B1")
    a.inc_zp(ZP_TMP)
    a.bne("LRD_B2")
    a.inc_zp(ZP_TMP + 1)
    a.label("LRD_B2")
    a.dex()
    a.bne("LRD_BYTE_LP")
    a.jmp("LRD_LINE_LP")

    a.label("LRD_DONE")
    a.lda_zp(ZP_TMP)
    a.sta_zp(ZP_PRGEND)
    a.lda_zp(ZP_TMP + 1)
    a.sta_zp(ZP_PRGEND + 1)
    a.lda_imm("<STR_DEMO_LOADED")
    a.ldy_imm(">STR_DEMO_LOADED")
    a.jmp("PRINT_STR")

    # ========================================================================
    # 10. Expression Evaluator (16-bit Signed Math + Comparisons + Functions)
    # ========================================================================
    # Precedence:
    #   EVAL_EXPR -> Add/Sub/Bitwise (+, -, &, |, ^) + Comparisons (=, <>, <, >)
    #   EVAL_TERM -> Mul/Div (*, /)
    #   EVAL_FACTOR -> Numbers, $Hex, Variables A..Z, (Expr), Functions
    a.label("EVAL_EXPR")
    a.jsr("EVAL_ADD_SUB")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("="))
    a.beq("CMP_EQ")
    a.cmp_imm(ord("<"))
    a.beq("CMP_LT")
    a.cmp_imm(ord(">"))
    a.beq("CMP_GT")
    a.rts()

    a.label("ADV_EVAL_ADD_SUB")
    a.jsr("ADV_TXT")
    a.label("EVAL_PUSH_ADD_SUB")
    a.lda_zp(ZP_ACC)
    a.pha()
    a.lda_zp(ZP_ACC + 1)
    a.pha()
    a.jsr("EVAL_ADD_SUB")
    a.jmp("POP_OP_RTS")

    a.label("CMP_EQ")
    a.jsr("ADV_EVAL_ADD_SUB")
    a.lda_zp(ZP_OP)
    a.cmp_zp(ZP_ACC)
    a.bne("CMP_FALSE")
    a.lda_zp(ZP_OP + 1)
    a.cmp_zp(ZP_ACC + 1)
    a.bne("CMP_FALSE")
    a.label("CMP_TRUE")
    a.lda_imm(0xFF)
    a.sta_zp(ZP_ACC)
    a.sta_zp(ZP_ACC + 1)
    a.rts()
    a.label("CMP_FALSE")
    a.lda_imm(0)
    a.sta_zp(ZP_ACC)
    a.sta_zp(ZP_ACC + 1)
    a.rts()

    a.label("CMP_LT")
    a.jsr("ADV_TXT")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(">"))
    a.beq("CMP_NE")
    a.cmp_imm(ord("="))
    a.beq("CMP_LE")
    a.jsr("EVAL_PUSH_ADD_SUB")
    # ZP_OP < ZP_ACC (signed)
    a.lda_zp(ZP_OP)
    a.cmp_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.sbc_zp(ZP_ACC + 1)
    a.bmi("CMP_TRUE")
    a.jmp("CMP_FALSE")

    a.label("CMP_NE")
    a.jsr("ADV_EVAL_ADD_SUB")
    a.lda_zp(ZP_OP)
    a.cmp_zp(ZP_ACC)
    a.bne("CMP_TRUE")
    a.lda_zp(ZP_OP + 1)
    a.cmp_zp(ZP_ACC + 1)
    a.bne("CMP_TRUE")
    a.jmp("CMP_FALSE")

    a.label("CMP_LE")
    a.jsr("ADV_EVAL_ADD_SUB")
    # ZP_OP <= ZP_ACC <=> !(ZP_ACC < ZP_OP)
    a.lda_zp(ZP_ACC)
    a.cmp_zp(ZP_OP)
    a.lda_zp(ZP_ACC + 1)
    a.sbc_zp(ZP_OP + 1)
    a.bmi("CMP_FALSE")
    a.jmp("CMP_TRUE")

    a.label("CMP_GT")
    a.jsr("ADV_TXT")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("="))
    a.beq("CMP_GE")
    a.jsr("EVAL_PUSH_ADD_SUB")
    # ZP_OP > ZP_ACC <=> ZP_ACC < ZP_OP
    a.lda_zp(ZP_ACC)
    a.cmp_zp(ZP_OP)
    a.lda_zp(ZP_ACC + 1)
    a.sbc_zp(ZP_OP + 1)
    a.bmi("CMP_TRUE")
    a.jmp("CMP_FALSE")

    a.label("CMP_GE")
    a.jsr("ADV_EVAL_ADD_SUB")
    a.lda_zp(ZP_OP)
    a.cmp_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.sbc_zp(ZP_ACC + 1)
    a.bmi("CMP_FALSE")
    a.jmp("CMP_TRUE")

    # --- Add / Sub / Bitwise (&, |, ^) ---
    a.label("ADV_EVAL_TERM")
    a.jsr("ADV_TXT")
    a.lda_zp(ZP_ACC)
    a.pha()
    a.lda_zp(ZP_ACC + 1)
    a.pha()
    a.jsr("EVAL_TERM")
    a.jmp("POP_OP_RTS")

    a.label("EVAL_ADD_SUB")
    a.jsr("EVAL_TERM")
    a.label("EAS_LOOP")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("+"))
    a.beq("EAS_ADD")
    a.cmp_imm(ord("-"))
    a.beq("EAS_SUB")
    a.cmp_imm(ord("&"))
    a.beq("EAS_AND")
    a.cmp_imm(ord("|"))
    a.beq("EAS_OR")
    a.cmp_imm(ord("^"))
    a.beq("EAS_XOR")
    a.rts()

    a.label("EAS_ADD")
    a.jsr("ADV_EVAL_TERM")
    a.clc()
    a.lda_zp(ZP_OP)
    a.adc_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.adc_zp(ZP_ACC + 1)
    a.sta_zp(ZP_ACC + 1)
    a.jmp("EAS_LOOP")

    a.label("EAS_SUB")
    a.jsr("ADV_EVAL_TERM")
    a.sec()
    a.lda_zp(ZP_OP)
    a.sbc_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.sbc_zp(ZP_ACC + 1)
    a.sta_zp(ZP_ACC + 1)
    a.jmp("EAS_LOOP")

    a.label("EAS_AND")
    a.jsr("ADV_EVAL_TERM")
    a.lda_zp(ZP_OP)
    a.and_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.and_zp(ZP_ACC + 1)
    a.sta_zp(ZP_ACC + 1)
    a.jmp("EAS_LOOP")

    a.label("EAS_OR")
    a.jsr("ADV_EVAL_TERM")
    a.lda_zp(ZP_OP)
    a.ora_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.ora_zp(ZP_ACC + 1)
    a.sta_zp(ZP_ACC + 1)
    a.jmp("EAS_LOOP")

    a.label("EAS_XOR")
    a.jsr("ADV_EVAL_TERM")
    a.lda_zp(ZP_OP)
    a.eor_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.eor_zp(ZP_ACC + 1)
    a.sta_zp(ZP_ACC + 1)
    a.jmp("EAS_LOOP")

    # --- Term: *, /, % ---
    a.label("ADV_EVAL_FACTOR")
    a.jsr("ADV_TXT")
    a.lda_zp(ZP_ACC)
    a.pha()
    a.lda_zp(ZP_ACC + 1)
    a.pha()
    a.jsr("EVAL_FACTOR")
    a.label("POP_OP_RTS")
    a.pla()
    a.sta_zp(ZP_OP + 1)
    a.pla()
    a.sta_zp(ZP_OP)
    a.rts()

    a.label("EVAL_TERM")
    a.jsr("EVAL_FACTOR")
    a.label("ET_LOOP")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("*"))
    a.beq("ET_MUL")
    a.cmp_imm(ord("/"))
    a.beq("ET_DIV")
    a.cmp_imm(ord("%"))
    a.beq("ET_MOD")
    a.rts()

    a.label("ET_MUL")
    a.jsr("ADV_EVAL_FACTOR")
    # 16x16 -> 16-bit multiplication: ZP_ACC = ZP_OP * ZP_ACC
    a.lda_imm(0)
    a.sta_zp(ZP_REM)
    a.sta_zp(ZP_REM + 1)
    a.ldx_imm(16)
    a.label("MUL16_LP")
    a.lsr_zp(ZP_OP + 1)
    a.ror_zp(ZP_OP)
    a.bcc("MUL16_SH")
    a.clc()
    a.lda_zp(ZP_REM)
    a.adc_zp(ZP_ACC)
    a.sta_zp(ZP_REM)
    a.lda_zp(ZP_REM + 1)
    a.adc_zp(ZP_ACC + 1)
    a.sta_zp(ZP_REM + 1)
    a.label("MUL16_SH")
    a.asl_zp(ZP_ACC)
    a.rol_zp(ZP_ACC + 1)
    a.dex()
    a.bne("MUL16_LP")
    a.lda_zp(ZP_REM)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_REM + 1)
    a.sta_zp(ZP_ACC + 1)
    a.jmp("ET_LOOP")

    a.label("ET_DIV")
    a.jsr("ADV_EVAL_FACTOR")
    a.jsr("DIV16") # ZP_ACC = ZP_OP / ZP_ACC, ZP_REM = remainder
    a.jmp("ET_LOOP")

    a.label("ET_MOD")
    a.jsr("ADV_EVAL_FACTOR")
    a.jsr("DIV16")
    a.lda_zp(ZP_REM)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_REM + 1)
    a.sta_zp(ZP_ACC + 1)
    a.jmp("ET_LOOP")

    # Unsigned 16-bit division: ZP_OP / ZP_ACC -> Quotient in ZP_ACC, Remainder in ZP_REM
    a.label("DIV16")
    a.lda_zp(ZP_ACC)
    a.ora_zp(ZP_ACC + 1)
    a.bne("DIV16_OK")
    a.rts() # Avoid divide by zero
    a.label("DIV16_OK")
    a.lda_imm(0)
    a.sta_zp(ZP_REM)
    a.sta_zp(ZP_REM + 1)
    a.ldx_imm(16)
    a.label("DIV16_LP")
    a.asl_zp(ZP_OP)
    a.rol_zp(ZP_OP + 1)
    a.rol_zp(ZP_REM)
    a.rol_zp(ZP_REM + 1)
    a.sec()
    a.lda_zp(ZP_REM)
    a.sbc_zp(ZP_ACC)
    a.tay()
    a.lda_zp(ZP_REM + 1)
    a.sbc_zp(ZP_ACC + 1)
    a.bcc("DIV16_SKIP")
    a.sta_zp(ZP_REM + 1)
    a.sty_zp(ZP_REM)
    a.inc_zp(ZP_OP)
    a.label("DIV16_SKIP")
    a.dex()
    a.bne("DIV16_LP")
    a.lda_zp(ZP_OP)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_OP + 1)
    a.sta_zp(ZP_ACC + 1)
    a.rts()

    # --- Factor: Unary +/-, (expr), $Hex, Number, Functions, Variables & SDRAM Arrays ---
    a.label("EVAL_FACTOR")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("-"))
    a.bne("EF_CHK_PLUS")
    a.jsr("ADV_TXT")
    a.jsr("EVAL_FACTOR")
    a.label("NEG_ACC")
    a.sec()
    a.lda_imm(0)
    a.sbc_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.lda_imm(0)
    a.sbc_zp(ZP_ACC + 1)
    a.sta_zp(ZP_ACC + 1)
    a.rts()

    a.label("EF_CHK_PLUS")
    a.cmp_imm(ord("+"))
    a.bne("EF_CHK_PAREN")
    a.jsr("ADV_TXT")
    a.jmp("EVAL_FACTOR")

    a.label("EF_CHK_PAREN")
    a.cmp_imm(ord("("))
    a.bne("EF_CHK_HEX")
    a.jsr("ADV_TXT")
    a.jsr("EVAL_EXPR")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(")"))
    a.bne("EF_PAREN_DONE")
    a.jsr("ADV_TXT")
    a.label("EF_PAREN_DONE")
    a.rts()

    a.label("EF_CHK_HEX")
    a.cmp_imm(ord("$"))
    a.beq("PARSE_HEX")
    a.jsr("IS_DIGIT")
    a.bcs("PARSE_UINT")

    # Check built-in functions: RGB, RND, ABS, JOY, KEY, TIMER, PEEK, USR, EOF via KW_TABLE
    a.ldx_imm(69)
    a.label("EF_FN_LP")
    a.ldy_abx("KW_TABLE_HI")
    a.beq("EF_VAR")
    a.lda_abx("KW_TABLE")
    a.stx_zp(ZP_MATH + 2)
    a.jsr("MATCH_KW")
    a.ldx_zp(ZP_MATH + 2)
    a.bcc("EF_FN_NXT")
    a.jmp("ESS_KW_FOUND")
    a.label("EF_FN_NXT")
    a.inx()
    a.jmp("EF_FN_LP")

    # Variable A..Z or SDRAM Array A(idx)..Z(idx) (Banks 32..57, 64KB = 32768 ints each!)
    a.label("EF_VAR")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("A"))
    a.bcc("EF_ZERO")
    a.cmp_imm(ord("Z") + 1)
    a.bcs("EF_ZERO")
    a.sec()
    a.sbc_imm(ord("A"))
    a.pha()
    a.jsr("ADV_TXT")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("("))
    a.beq("EF_ARRAY")
    a.pla()
    a.asl_a()
    a.tax()
    a.lda_abx(VARS_BASE)
    a.sta_zp(ZP_ACC)
    a.lda_abx(VARS_BASE + 1)
    a.sta_zp(ZP_ACC + 1)
    a.rts()

    a.label("EF_ARRAY")
    a.jsr("PARSE_ARR_IDX")
    a.ldx_zp(ZP_ACC)
    a.ldy_zp(ZP_ACC + 1)
    a.pla()
    a.jsr("SET_ARR_IO")
    a.lda_abs(IO_RD_DATA)
    a.sta_zp(ZP_ACC)
    a.inx()
    a.stx_abs(IO_RD_LO)
    a.lda_abs(IO_RD_DATA)
    a.sta_zp(ZP_ACC + 1)
    a.rts()

    a.label("PARSE_ARR_IDX")
    a.jsr("EF_CHK_PAREN")
    a.asl_zp(ZP_ACC)
    a.rol_zp(ZP_ACC + 1)
    a.rts()

    a.label("SET_ARR_IO")
    a.clc()
    a.adc_imm(32) # SDRAM Banks 32..57 (1.66 MB dedicated to arrays A..Z)
    a.sta_abs(IO_RD_BANK)
    a.sty_abs(IO_RD_HI)
    a.stx_abs(IO_RD_LO)
    a.rts()

    a.label("EF_ZERO")
    a.lda_imm(0)
    a.label("STORE_ACC_U8")
    a.sta_zp(ZP_ACC)
    a.lda_imm(0)
    a.sta_zp(ZP_ACC + 1)
    a.rts()

    # --- Built-in Functions ---
    a.label("FN_JOY")
    a.lda_abs(IO_JOY)
    a.jmp("STORE_ACC_U8")

    a.label("FN_TIMER")
    a.lda_abs(IO_TIMER)
    a.jmp("STORE_ACC_U8")

    a.label("FN_KEY")
    a.lda_abs(IO_STATUS)
    a.and_imm(1)
    a.beq("STORE_ACC_U8")
    a.lda_abs(IO_TERM)
    a.jmp("STORE_ACC_U8")

    a.label("FN_ABS")
    a.jsr("EVAL_FACTOR")
    a.lda_zp(ZP_ACC + 1)
    a.bmi("NEG_ACC")
    a.rts()

    a.label("FN_PEEK")
    a.jsr("EVAL_FACTOR")
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_TMP)
    a.lda_zp(ZP_ACC + 1)
    a.sta_zp(ZP_TMP + 1)
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.jmp("STORE_ACC_U8")

    a.label("FN_USR")
    a.jsr("EVAL_FACTOR")
    a.jsr("CALL_ACC")
    a.jmp("STORE_ACC_U8")

    a.label("FN_RND")
    a.jsr("EVAL_FACTOR") # range N in ZP_ACC
    a.lda_abs(IO_RND)
    a.sta_zp(ZP_OP)
    a.lda_abs(IO_RND)
    a.and_imm(0x7F)
    a.sta_zp(ZP_OP + 1)
    a.jsr("DIV16") # remainder in ZP_REM
    a.lda_zp(ZP_REM)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_REM + 1)
    a.sta_zp(ZP_ACC + 1)
    a.rts()

    # RGB(r, g, b) -> (r<<5) | (g<<2) | b
    a.label("FN_RGB")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("("))
    a.bne("RGB_S1")
    a.jsr("ADV_TXT")
    a.label("RGB_S1")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.and_imm(7)
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.pha()
    a.jsr("SKIP_COMMA")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.and_imm(7)
    a.asl_a()
    a.asl_a()
    a.sta_zp(ZP_MATH)
    a.pla()
    a.ora_zp(ZP_MATH)
    a.pha()
    a.jsr("SKIP_COMMA")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.and_imm(3)
    a.sta_zp(ZP_MATH)
    a.pla()
    a.ora_zp(ZP_MATH)
    a.sta_zp(ZP_ACC)
    a.lda_imm(0)
    a.sta_zp(ZP_ACC + 1)
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(")"))
    a.bne("RGB_DONE")
    a.jsr("ADV_TXT")
    a.label("RGB_DONE")
    a.rts()

    # --- Number Parsers (Decimal & $Hex) ---
    a.label("PARSE_UINT")
    a.lda_imm(0)
    a.sta_zp(ZP_ACC)
    a.sta_zp(ZP_ACC + 1)
    a.label("PU_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.jsr("IS_DIGIT")
    a.bcc("PU_DONE")
    a.sec()
    a.sbc_imm(ord("0"))
    a.pha()
    # ZP_ACC = ZP_ACC * 10 = (ZP_ACC * 2) + (ZP_ACC * 8)
    a.asl_zp(ZP_ACC)
    a.rol_zp(ZP_ACC + 1)
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_TMP)
    a.lda_zp(ZP_ACC + 1)
    a.sta_zp(ZP_TMP + 1)
    a.asl_zp(ZP_ACC)
    a.rol_zp(ZP_ACC + 1)
    a.asl_zp(ZP_ACC)
    a.rol_zp(ZP_ACC + 1)
    a.clc()
    a.lda_zp(ZP_ACC)
    a.adc_zp(ZP_TMP)
    a.sta_zp(ZP_ACC)
    a.lda_zp(ZP_ACC + 1)
    a.adc_zp(ZP_TMP + 1)
    a.sta_zp(ZP_ACC + 1)
    a.pla()
    a.clc()
    a.adc_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.bcc("PU_NXT")
    a.inc_zp(ZP_ACC + 1)
    a.label("PU_NXT")
    a.jsr("ADV_TXT")
    a.jmp("PU_LP")
    a.label("PU_DONE")
    a.rts()

    a.label("PARSE_HEX")
    a.jsr("ADV_TXT") # skip '$'
    a.lda_imm(0)
    a.sta_zp(ZP_ACC)
    a.sta_zp(ZP_ACC + 1)
    a.label("PH_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.jsr("IS_DIGIT")
    a.bcc("PH_ALPHA")
    a.sec()
    a.sbc_imm(ord("0"))
    a.jmp("PH_SHIFT")
    a.label("PH_ALPHA")
    a.cmp_imm(ord("A"))
    a.bcc("PH_DONE")
    a.cmp_imm(ord("F") + 1)
    a.bcs("PH_DONE")
    a.sec()
    a.sbc_imm(ord("A") - 10)
    a.label("PH_SHIFT")
    a.ldx_imm(4)
    a.label("PH_S4")
    a.asl_zp(ZP_ACC)
    a.rol_zp(ZP_ACC + 1)
    a.dex()
    a.bne("PH_S4")
    a.ora_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.jsr("ADV_TXT")
    a.jmp("PH_LP")
    a.label("PH_DONE")
    a.rts()

    # ========================================================================
    # 11. Text / Terminal I/O Subroutines
    # ========================================================================
    a.label("PUTC")
    a.pha()
    a.lda_abs(FILE_OUT_FLAG)
    a.bne("PUTC_TO_FILE")
    a.pla()
    a.sta_abs(IO_TERM)
    a.rts()
    a.label("PUTC_TO_FILE")
    a.pla()
    a.jmp("FILE_PUT_CHAR")

    a.label("NEWLINE")
    a.lda_imm(0x0D)
    a.jsr("PUTC")
    a.lda_imm(0x0A)
    a.jmp("PUTC")

    a.label("GETC")
    a.lda_abs(IO_STATUS)
    a.and_imm(1)
    a.beq("GETC")
    a.lda_abs(IO_TERM)
    a.rts()

    a.label("PRINT_STR")
    a.sta_zp(ZP_TMP)
    a.sty_zp(ZP_TMP + 1)
    a.ldy_imm(0)
    a.sty_abs(FILE_OUT_FLAG)
    a.label("PS_LP")
    a.lda_iny(ZP_TMP)
    a.beq("PS_DN")
    a.jsr("PUTC")
    a.inc_zp(ZP_TMP)
    a.bne("PS_LP")
    a.inc_zp(ZP_TMP + 1)
    a.jmp("PS_LP")
    a.label("PS_DN")
    a.rts()

    # Print signed 16-bit integer in ZP_ACC
    a.label("PRINT_INT16")
    a.lda_zp(ZP_ACC + 1)
    a.bpl("PI_POS")
    a.lda_imm(ord("-"))
    a.jsr("PUTC")
    a.sec()
    a.lda_imm(0)
    a.sbc_zp(ZP_ACC)
    a.sta_zp(ZP_ACC)
    a.lda_imm(0)
    a.sbc_zp(ZP_ACC + 1)
    a.sta_zp(ZP_ACC + 1)

    a.label("PI_POS")
    a.lda_zp(ZP_ACC)
    a.ora_zp(ZP_ACC + 1)
    a.bne("PI_CONV")
    a.lda_imm(ord("0"))
    a.jmp("PUTC")

    a.label("PI_CONV")
    a.lda_imm(0)
    a.pha() # Null sentinel on stack
    a.label("PI_DIV_LP")
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_OP)
    a.lda_zp(ZP_ACC + 1)
    a.sta_zp(ZP_OP + 1)
    a.lda_imm(10)
    a.sta_zp(ZP_ACC)
    a.lda_imm(0)
    a.sta_zp(ZP_ACC + 1)
    a.jsr("DIV16")
    a.lda_zp(ZP_REM)
    a.clc()
    a.adc_imm(ord("0"))
    a.pha()
    a.lda_zp(ZP_ACC)
    a.ora_zp(ZP_ACC + 1)
    a.bne("PI_DIV_LP")

    a.label("PI_PRT_LP")
    a.pla()
    a.beq("PI_DONE")
    a.jsr("PUTC")
    a.jmp("PI_PRT_LP")
    a.label("PI_DONE")
    a.rts()

    # Read a line from keyboard into LINE_BUF ($0200), auto-capitalizing outside quotes
    a.label("READ_LINE")
    a.ldx_imm(0)
    a.stx_zp(ZP_SIGN) # Quote state (0 = outside quotes, 1 = inside quotes)
    a.label("RL_LP")
    a.jsr("GETC")
    a.cmp_imm(0x0D)
    a.beq("RL_CR")
    a.cmp_imm(0x0A)
    a.beq("RL_CR")
    a.cmp_imm(0x08)
    a.beq("RL_BS")
    a.cmp_imm(0x7F)
    a.beq("RL_BS")
    a.cmp_imm(0x20)
    a.bcc("RL_LP")
    a.cpx_imm(120)
    a.bcs("RL_LP")

    a.cmp_imm(ord('"'))
    a.bne("RL_CHK_LOWER")
    a.pha()
    a.lda_zp(ZP_SIGN)
    a.eor_imm(1)
    a.sta_zp(ZP_SIGN)
    a.pla()
    a.jmp("RL_STORE")

    a.label("RL_CHK_LOWER")
    a.ldy_zp(ZP_SIGN)
    a.bne("RL_STORE") # Inside quotes: preserve case
    a.cmp_imm(ord("a"))
    a.bcc("RL_STORE")
    a.cmp_imm(ord("z") + 1)
    a.bcs("RL_STORE")
    a.sec()
    a.sbc_imm(0x20) # To uppercase

    a.label("RL_STORE")
    a.sta_abx(LINE_BUF)
    a.inx()
    a.jsr("PUTC")
    a.jmp("RL_LP")

    a.label("RL_BS")
    a.cpx_imm(0)
    a.beq("RL_LP")
    a.dex()
    a.lda_abx(LINE_BUF)
    a.cmp_imm(ord('"'))
    a.bne("RL_BS_ECHO")
    a.lda_zp(ZP_SIGN)
    a.eor_imm(1)
    a.sta_zp(ZP_SIGN)
    a.label("RL_BS_ECHO")
    a.lda_imm(0x08)
    a.jsr("PUTC")
    a.jmp("RL_LP")

    a.label("RL_CR")
    a.lda_imm(0)
    a.sta_abx(LINE_BUF)
    a.jmp("NEWLINE")

    # Small parsing helpers
    a.label("ADV_TXT")
    a.inc_zp(ZP_TXT)
    a.bne("AT_DN")
    a.inc_zp(ZP_TXT + 1)
    a.label("AT_DN")
    a.rts()

    a.label("SKIP_SPACES")
    a.ldy_imm(0)
    a.label("SS_LP")
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(" "))
    a.bne("SS_DN")
    a.jsr("ADV_TXT")
    a.jmp("SS_LP")
    a.label("SS_DN")
    a.rts()

    a.label("SKIP_COMMA")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(","))
    a.bne("SC_DN")
    a.jsr("ADV_TXT")
    a.label("SC_DN")
    a.jmp("SKIP_SPACES")

    a.label("IS_DIGIT")
    a.cmp_imm(ord("0"))
    a.bcc("ID_NO")
    a.cmp_imm(ord("9") + 1)
    a.bcs("ID_NO")
    a.sec()
    a.rts()
    a.label("ID_NO")
    a.clc()
    a.rts()

    # ========================================================================
    # 12. Keyword & Message Strings + 5 Built-in Demo Programs
    # ========================================================================
    keywords = [
        ("KW_PRINT",  "PRINT"),
        ("KW_INPUT",  "INPUT"),
        ("KW_IF",     "IF"),
        ("KW_THEN",   "THEN"),
        ("KW_GOTO",   "GOTO"),
        ("KW_GOSUB",  "GOSUB"),
        ("KW_RETURN", "RETURN"),
        ("KW_FOR",    "FOR"),
        ("KW_TO",     "TO"),
        ("KW_STEP",   "STEP"),
        ("KW_NEXT",   "NEXT"),
        ("KW_WAIT",   "WAIT"),
        ("KW_POKE",   "POKE"),
        ("KW_CALL",   "CALL"),
        ("KW_SYS",    "SYS"),
        ("KW_REM",    "REM"),
        ("KW_DIM",    "DIM"),
        ("KW_LET",    "LET"),
        ("KW_CLS",    "CLS"),
        ("KW_MODE",   "MODE"),
        ("KW_CLEAR",  "CLEAR"),
        ("KW_RECT",   "RECT"),
        ("KW_LINE",   "LINE"),
        ("KW_CIRCLE", "CIRCLE"),
        ("KW_DISK",   "DISK"),
        ("KW_TRI",    "TRI"),
        ("KW_FTRI",   "FTRI"),
        ("KW_GTEXT",  "GTEXT"),
        ("KW_SPRITE", "SPRITE"),
        ("KW_BIGSPR", "BIGSPR"),
        ("KW_SCROLL", "SCROLL"),
        ("KW_TILE",   "TILE"),
        ("KW_FLIP",   "FLIP"),
        ("KW_TARGET", "TARGET"),
        ("KW_SOUND",  "SOUND"),
        ("KW_BEEP",   "BEEP"),
        ("KW_LIST",   "LIST"),
        ("KW_NEW",    "NEW"),
        ("KW_RUN",    "RUN"),
        ("KW_END",    "END"),
        ("KW_STOP",   "STOP"),
        ("KW_SAVE",   "SAVE"),
        ("KW_LOAD",   "LOAD"),
        ("KW_BSAVE",  "BSAVE"),
        ("KW_BLOAD",  "BLOAD"),
        ("KW_BRUN",   "BRUN"),
        ("KW_CAT",    "CAT"),
        ("KW_FILES",  "FILES"),
        ("KW_DIR",    "DIR"),
        ("KW_CD",     "CD"),
        ("KW_SDRAM",  "SDRAM"),
        ("KW_SD",     "SD"),
        ("KW_DRIVE",  "DRIVE"),
        ("KW_DEMO",   "DEMO"),
        ("KW_HELP",   "HELP"),
        ("KW_RGB",    "RGB"),
        ("KW_RND",    "RND"),
        ("KW_ABS",    "ABS"),
        ("KW_JOY",    "JOY"),
        ("KW_KEY",    "KEY"),
        ("KW_TIMER",  "TIMER"),
        ("KW_PEEK",   "PEEK"),
        ("KW_USR",    "USR"),
    ]
    for lbl, kw in keywords:
        a.label(lbl)
        a.ascii_z(kw)

    stmt_kw_pairs = [
        ("KW_PRINT",   "STMT_PRINT"),
        ("KW_INPUT",   "STMT_INPUT"),
        ("KW_IF",      "STMT_IF"),
        ("KW_GOTO",    "STMT_GOTO"),
        ("KW_GOSUB",   "STMT_GOSUB"),
        ("KW_RETURN",  "STMT_RETURN"),
        ("KW_FOR",     "STMT_FOR"),
        ("KW_NEXT",    "STMT_NEXT"),
        ("KW_WAIT",    "STMT_WAIT"),
        ("KW_POKE",    "STMT_POKE"),
        ("KW_CALL",    "STMT_CALL"),
        ("KW_SYS",     "STMT_CALL"),
        ("KW_REM",     "STMT_REM"),
        ("KW_DIM",     "STMT_DIM"),
        ("KW_CLS",     "STMT_CLS"),
        ("KW_MODE",    "STMT_MODE"),
        ("KW_CLEAR",   "STMT_CLEAR"),
        ("KW_RECT",    "STMT_RECT"),
        ("KW_LINE",    "STMT_LINE"),
        ("KW_CIRCLE",  "STMT_CIRCLE"),
        ("KW_DISK",    "STMT_DISK"),
        ("KW_TRI",     "STMT_TRI"),
        ("KW_FTRI",    "STMT_FTRI"),
        ("KW_GTEXT",   "STMT_GTEXT"),
        ("KW_SPRITE",  "STMT_SPRITE"),
        ("KW_BIGSPR",  "STMT_BIGSPR"),
        ("KW_SCROLL",  "STMT_SCROLL"),
        ("KW_TILE",    "STMT_TILE"),
        ("KW_FLIP",    "STMT_FLIP"),
        ("KW_TARGET",  "STMT_TARGET"),
        ("KW_FUNC",    "STMT_FUNC"),
        ("KW_ENDFUNC", "STMT_ENDFUNC"),
        ("KW_DO",      "STMT_DO"),
        ("KW_DEFSPR",  "STMT_DEFSPR"),
        ("KW_DEFTILE", "STMT_DEFTILE"),
        ("KW_DEFBIG",  "STMT_DEFBIG"),
        ("KW_PIX",     "STMT_PIX"),
        ("KW_SOUND",   "STMT_SOUND"),
        ("KW_BEEP",    "STMT_BEEP"),
        ("KW_WAV",     "STMT_WAV"),
        ("KW_LIST",    "STMT_LIST"),
        ("KW_NEW",     "STMT_NEW"),
        ("KW_RUN",     "STMT_RUN"),
        ("KW_END",     "STMT_END"),
        ("KW_STOP",    "STMT_END"),
        ("KW_SAVE",    "STMT_SAVE"),
        ("KW_LOAD",    "STMT_LOAD"),
        ("KW_BSAVE",   "STMT_SAVE"),
        ("KW_BLOAD",   "STMT_LOAD"),
        ("KW_BRUN",    "STMT_BRUN"),
        ("KW_CAT",     "STMT_CAT"),
        ("KW_FILES",   "STMT_CAT"),
        ("KW_DIR",     "STMT_CAT"),
        ("KW_CD",      "STMT_LOAD"),
        ("KW_SDRAM",   "STMT_SDRAM"),
        ("KW_SD",      "STMT_SD"),
        ("KW_DRIVE",   "STMT_DRIVE"),
        ("KW_OPEN",    "STMT_OPEN"),
        ("KW_CLOSE",   "STMT_CLOSE"),
        ("KW_WRITE",   "STMT_WRITE"),
        ("KW_READ",    "STMT_READ"),
        ("KW_GET",     "STMT_GET"),
        ("KW_PUT",     "STMT_PUT"),
        ("KW_SEEK",    "STMT_SEEK"),
        ("KW_TYPE",    "STMT_TYPE"),
        ("KW_DEMO",    "STMT_DEMO"),
        ("KW_HELP",    "STMT_HELP"),
        ("KW_LET",     "STMT_LET"),
    ]
    fn_kw_pairs = [
        ("KW_RGB",    "FN_RGB"),
        ("KW_RND",    "FN_RND"),
        ("KW_ABS",    "FN_ABS"),
        ("KW_JOY",    "FN_JOY"),
        ("KW_KEY",    "FN_KEY"),
        ("KW_TIMER",  "FN_TIMER"),
        ("KW_PEEK",   "FN_PEEK"),
        ("KW_USR",    "FN_USR"),
        ("KW_EOF",    "FN_EOF"),
    ]
    assert len(stmt_kw_pairs) + 1 == 69

    a.label("STR_BANNER")
    a.ascii_z(
        "-- TANG NANO 20K MINIGPU-BASIC 1.2 --\r\n"
        "38KB RAM | FUNC/DO | Sprites/Tiles/GPU\r\n"
        "Typ HELP, CAT, CD, DRIVE 0..3, DEMO\r\n"
        "Ready\r\n"
    )

    a.label("STR_SYNTAX_ERR")
    a.ascii_z("?Syntax Error\r\n")
    a.label("STR_LINE_ERR")
    a.ascii_z("?Undefined Line\r\n")
    a.label("STR_BREAK")
    a.ascii_z("\r\n*Break*\r\n")
    a.label("STR_TAG_SD")
    a.ascii_z("[SD-KAART D")
    a.label("STR_TAG_RD")
    a.ascii_z("[SDRAM-DISK D")
    a.label("STR_CAT_HDR")
    a.ascii_z("CATALOGUS:\r\n")
    a.label("STR_CAT_EMPTY")
    a.ascii_z(" (Leeg - 0 bestanden)\r\n")
    a.label("STR_SAVED")
    a.ascii_z("Opgeslagen!\r\n")
    a.label("STR_LOADED")
    a.ascii_z("Geladen!\r\n")
    a.label("STR_SLOT_EMPTY")
    a.ascii_z("?Niet gevonden\r\n")
    a.label("STR_BYTES")
    a.ascii_z(" B)\r\n")
    a.label("STR_MAP")
    a.ascii_z("<MAP>\r\n")
    a.label("STR_DEMO_LOADED")
    a.ascii_z("Demo geladen! Typ RUN.\r\n")

    # Helper to encode a list of (line_num, text) into tokenized BASIC lines in ROM
    def emit_demo(label_name, lines):
        a.label(label_name)
        for lnum, txt in lines:
            raw = [ord(c) for c in txt] + [0]
            rec_len = 3 + len(raw)
            a.emit(rec_len, lnum & 0xFF, (lnum >> 8) & 0xFF, *raw)
        a.emit(0) # End of program marker

    # DEMO 1: Parallax Boerderij, 16x16 Sprites & 128x128 Big Sprites (bestuurbaar met WASD/Pijltjes!)
    emit_demo("ROM_DEMO1", [
        (20, 'MODE 1:TARGET 0:X=100:Y=120:S=0'),
        (40, 'CLEAR $E3:SCROLL S,S/2:BIGSPR 0,1,440,180,(S/16)&1'),
        (70, 'RECT 10,10,220,22,0:GTEXT 18,17,"BOERDERIJ - WASD",$FF'),
        (90, 'SPRITE 0,X,Y:SPRITE 4,200,150:SPRITE 5,230,150:SPRITE 9,260,150'),
        (110, 'FLIP:WAIT 1:S=(S+2)&1023:J=JOY'),
        (130, 'IF J&1 THEN Y=Y-6'),
        (140, 'IF J&2 THEN Y=Y+6'),
        (150, 'IF J&4 THEN X=X-6'),
        (160, 'IF J&8 THEN X=X+6'),
        (170, 'GOTO 40'),
    ])

    # DEMO 2: 60 FPS Hardware 2D/3D Geometrie & Double-Buffer Show
    emit_demo("ROM_DEMO2", [
        (20, 'MODE 1:TARGET 0:BIGSPR 0,0,0,0:X=120:Y=100:U=6:V=4'),
        (40, 'CLEAR 3:FTRI 320,40,180,280,460,280,RGB(0,4,3)'),
        (60, 'RECT 40,300,560,30,RGB(2,6,0):DISK X,Y,32,RGB(7,6,0):CIRCLE X,Y,38,$FF'),
        (90, 'GTEXT 190,16,"TANG NANO 20K MINIGPU",$FF:FLIP:WAIT 1:X=X+U:Y=Y+V'),
        (120, 'IF X<50 THEN U=6:BEEP 523,2'),
        (130, 'IF X>590 THEN U=-6:BEEP 659,2'),
        (140, 'IF Y<50 THEN V=4:BEEP 784,2'),
        (150, 'IF Y>260 THEN V=-4:BEEP 440,2'),
        (160, 'GOTO 40'),
    ])

    # DEMO 3: Space Invaders Arcade Game (2D Vliegen met Pijltjes/WASD + Spatie om te schieten!)
    emit_demo("ROM_DEMO3", [
        (20, 'MODE 1:TARGET 0:BIGSPR 0,0,0,0:X=300:Y=310:A=100:D=4:L=0:M=0'),
        (40, 'CLEAR 0:GTEXT 210,12,"SPACE DEFENDER - SPATIE=VUUR",$FC'),
        (60, 'FOR I=0 TO 5:SPRITE 1,A+I*50,70:NEXT I:SPRITE 2,X,Y'),
        (100, 'IF L>0 THEN RECT M,L,4,14,$FC:L=L-18'),
        (105, 'IF (L>50)&(L<90)&(M>=A)&(M<=A+266) THEN DISK M,78,16,$E0:BEEP 220,2:L=0'),
        (110, 'FLIP:WAIT 1:A=A+D:IF A>320 THEN D=-4'),
        (130, 'IF A<40 THEN D=4'),
        (135, 'J=JOY:IF J&1 THEN Y=Y-6'),
        (138, 'IF J&2 THEN Y=Y+6'),
        (140, 'IF J&4 THEN X=X-8'),
        (160, 'IF J&8 THEN X=X+8'),
        (170, 'IF (J&16)&(L<=0) THEN L=Y-14:M=X+6:BEEP 1200,1'),
        (180, 'GOTO 40'),
    ])

    # DEMO 4: HDMI 48 kHz Chiptune Synthesizer & Visualizer
    emit_demo("ROM_DEMO4", [
        (20, 'MODE 1:TARGET 1:BIGSPR 0,0,0,0:CLEAR 0:GTEXT 180,30,"HDMI 48KHZ AUDIO SYNTH",$FF'),
        (50, 'FOR I=1 TO 16:F=220+I*40:RECT I*32,300-I*12,24,I*12,RGB(I&7,(16-I)&7,3)'),
        (80, 'BEEP F,12:NEXT I:WAIT 50:MODE 0'),
    ])

    # DEMO 5: 6502 Machine Code Demo at $8000 (SDRAM) + Save/Run from SD Card!
    emit_demo("ROM_DEMO5", [
        (10, 'CLS:CALL $8000:BSAVE "ASM6502",$8000,188'),
        (20, 'PRINT "6502 ASM OP SD! TYP: BRUN ASM6502"'),
    ])

    # 188-byte 6502 Machine Code routine assembled for $8000 (copied by DEMO 5 to $8000)
    a.label("ROM_ASM_CODE")
    asm_stream = [
        # RECT 60, 100, 520 ($0208), 145, $00
        2, 60, 0, 100, 0, 0x08, 0x02, 145, 0, 0x00,
        # RECT 60, 100, 520 ($0208), 8, $E0
        2, 60, 0, 100, 0, 0x08, 0x02, 8, 0, 0xE0,
        # DISK 160, 200, 26, $1F
        5, 160, 0, 200, 0, 26, 0, 0x1F,
        # DISK 320 ($0140), 200, 26, $FC
        5, 0x40, 0x01, 200, 0, 26, 0, 0xFC,
        # DISK 480 ($01E0), 200, 26, $E3
        5, 0xE0, 0x01, 200, 0, 26, 0, 0xE3,
        # GTEXT 88, 128, "6502 ASM @ $8000 (VANAF SD-KAART!)", $FC
        15, 88, 0, 128, 0, 0xFC,
        *[ord(c) for c in "6502 ASM @ $8000 (VANAF SD-KAART!)"], 0,
    ]
    asm_code_prefix = [
        # TARGET 1 (cmd 12, 1) & CLEAR $02 (cmd 1, 2)
        0xA9, 12, 0x8D, 0x20, 0xA0, 0xA9, 1, 0x8D, 0x20, 0xA0,
        0xA9, 1,  0x8D, 0x20, 0xA0, 0xA9, 2, 0x8D, 0x20, 0xA0,
        # LDX #0 ; BAR_LP: draw 32 rainbow copper bars via IO_GPU ($A020)
        0xA2, 0x00,
        0xA9, 0x02, 0x8D, 0x20, 0xA0,                         # cmd 2 (RECT)
        0xA9, 20,   0x8D, 0x20, 0xA0, 0xA9, 0, 0x8D, 0x20, 0xA0, # x = 20
        0x8A, 0x0A, 0x0A, 0x0A, 0x18, 0x69, 44, 0x8D, 0x20, 0xA0, # y_lo = 44 + X*8
        0xA9, 0,    0x69, 0,    0x8D, 0x20, 0xA0,             # y_hi
        0xA9, 0x58, 0x8D, 0x20, 0xA0, 0xA9, 2, 0x8D, 0x20, 0xA0, # w = 600 ($0258)
        0xA9, 6,    0x8D, 0x20, 0xA0, 0xA9, 0, 0x8D, 0x20, 0xA0, # h = 6
        0x8A, 0x0A, 0x0A, 0x69, 0x15, 0x8D, 0x20, 0xA0,       # color = X*4 + $15
        0xE8, 0xE0, 32, 0x90, 0xBF,                           # INX : CPX #32 : BCC BAR_LP (-65)
    ]
    stream_offset = len(asm_code_prefix) + 16 # 16 bytes for stream loop + LDA #65 + RTS
    asm_stream_loop = [
        0xA2, 0x00,                                           # LDX #0
        0xBD, stream_offset & 0xFF, 0x80,                     # LDA $8000+stream_offset,X
        0x8D, 0x20, 0xA0,                                     # STA $A020
        0xE8,                                                 # INX
        0xE0, len(asm_stream),                                # CPX #len(asm_stream)
        0x90, 0xF5,                                           # BCC -11
        0xA9, 65,                                             # LDA #65
        0x60,                                                 # RTS
    ]
    full_asm = asm_code_prefix + asm_stream_loop + asm_stream
    assert len(full_asm) == 188, f"Expected 188 bytes, got {len(full_asm)}"
    a.emit(*full_asm)

    a.label("STR_HELP")
    a.ascii_z(
        "GPU: CLEAR|RECT|LINE|CIRCLE|DISK|TRI|FTRI|GTEXT\r\n"
        "     SPRITE|BIGSPR|SCROLL|TILE|TARGET|FLIP\r\n"
        "FNC: FUNC naam..ENDFUNC | DO naam[,slot]\r\n"
        "     DEFSPR/DEFTILE/DEFBIG slot | PIX \"hex\"\r\n"
        "SND: SOUND ch,freq,vol | BEEP freq,duur | WAV [1..16]\r\n"
        "DSK: CAT|CD|DRIVE 0..3|SAVE/LOAD|BSAVE/BLOAD/BRUN\r\n"
        "FIL: OPEN \"f\"[,m]|WRITE|READ|GET|PUT|SEEK|EOF|CLOSE|TYPE\r\n"
        "ASM: CALL/SYS a | USR(a) | POKE a,v | PEEK(a)\r\n"
    )

    # ========================================================================
    # 13. Extension LUT-ROM ($A400 - $AFFF: 3 KB, 0 BSRAMs!)
    #     - Named Functions: FUNC naam ... ENDFUNC & DO naam [, slot]
    #     - Fast Hardware Graphics Streamer: DEFSPR / DEFTILE / DEFBIG & PIX "..."
    #     - SD-Card File I/O: OPEN / WRITE / READ / GET / PUT / SEEK / EOF / CLOSE / TYPE
    #     - Dispatch Tables
    # ========================================================================
    a.set_org(0xA400)

    ext_keywords = [
        ("KW_FUNC",    "FUNC"),
        ("KW_ENDFUNC", "ENDFUNC"),
        ("KW_DO",      "DO"),
        ("KW_DEFSPR",  "DEFSPR"),
        ("KW_DEFTILE", "DEFTILE"),
        ("KW_DEFBIG",  "DEFBIG"),
        ("KW_PIX",     "PIX"),
        ("KW_OPEN",    "OPEN"),
        ("KW_CLOSE",   "CLOSE"),
        ("KW_WRITE",   "WRITE"),
        ("KW_READ",    "READ"),
        ("KW_GET",     "GET"),
        ("KW_PUT",     "PUT"),
        ("KW_SEEK",    "SEEK"),
        ("KW_TYPE",    "TYPE"),
        ("KW_WAV",     "WAV"),
        ("KW_EOF",     "EOF"),
    ]
    for lbl, kw in ext_keywords:
        a.label(lbl)
        a.ascii_z(kw)

    a.label("KW_TABLE")
    a.emit(*[f"<{k}" for k, _ in stmt_kw_pairs], 0, *[f"<{k}" for k, _ in fn_kw_pairs])
    a.label("KW_TABLE_HI")
    a.emit(*[f">{k}" for k, _ in stmt_kw_pairs], 0, *[f">{k}" for k, _ in fn_kw_pairs], 0)
    a.label("KW_HND_LO")
    a.emit(*[f"<{h}" for _, h in stmt_kw_pairs], 0, *[f"<{h}" for _, h in fn_kw_pairs])
    a.label("KW_HND_HI")
    a.emit(*[f">{h}" for _, h in stmt_kw_pairs], 0, *[f">{h}" for _, h in fn_kw_pairs])

    a.label("STR_FUNC_ERR")
    a.ascii_z("?Undefined Func\r\n")

    # --- Reset / Flush GFX & FUNC State ---
    a.label("INIT_GFX_FUNC_STATE")
    a.lda_imm(0)
    a.sta_abs(GFX_KIND)
    a.sta_abs(FILE_OUT_FLAG)
    a.lda_imm(0xFF)
    a.sta_abs(FUNC_SLOT_OVR)
    a.rts()

    a.label("SILENCE_AUDIO_EXT")
    a.lda_imm(0)
    a.sta_abs(IO_PCM_RATE)
    a.lda_imm(128)
    a.sta_abs(IO_PCM_DAC)
    a.jsr("FLUSH_GFX")
    a.lda_imm(12)      # SET_RENDER_TARGET -> TARGET 1 (front buffer!)
    a.sta_abs(IO_GPU)
    a.lda_imm(1)
    a.sta_abs(IO_GPU)
    a.sta_abs(IO_MODE) # MODE 0 (show terminal overlay!)
    a.ldx_imm(0)
    a.label("SA_LP")
    a.lda_imm(16)
    a.sta_abs(IO_GPU)
    a.stx_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(IO_GPU)
    a.sta_abs(IO_GPU)
    a.sta_abs(IO_GPU)
    a.sta_abs(IO_GPU)
    a.inx()
    a.cpx_imm(4)
    a.bcc("SA_LP")
    a.rts()

    # Auto-pad any partial Sprite (256B, $E3), Tile (256B, $00), or BigSprite scanline (128B, $E3)
    # so the FPGA GPU command parser ALWAYS returns cleanly to parse_state = 0!
    a.label("FLUSH_GFX")
    a.lda_abs(GFX_KIND)
    a.beq("FG_DONE")
    a.cmp_imm(4)
    a.bcs("FG_CLR")
    a.cmp_imm(3)
    a.beq("FG_BIG")
    a.ldx_imm(0xE3)
    a.cmp_imm(1)
    a.beq("FG_PAD_LP")
    a.ldx_imm(0x00)
    a.label("FG_PAD_LP")
    a.lda_abs(GFX_REM_LO)
    a.ora_abs(GFX_REM_HI)
    a.beq("FG_CLR")
    a.stx_abs(IO_GPU)
    a.lda_abs(GFX_REM_LO)
    a.bne("FG_DEC_LO")
    a.dec_abs(GFX_REM_HI)
    a.label("FG_DEC_LO")
    a.dec_abs(GFX_REM_LO)
    a.jmp("FG_PAD_LP")

    a.label("FG_BIG")
    a.lda_abs(GFX_BIG_X)
    a.beq("FG_CLR")
    a.lda_imm(0xE3)
    a.label("FG_BIG_LP")
    a.sta_abs(IO_GPU)
    a.inc_abs(GFX_BIG_X)
    a.ldx_abs(GFX_BIG_X)
    a.cpx_imm(128)
    a.bcc("FG_BIG_LP")
    a.lda_imm(0)
    a.sta_abs(GFX_BIG_X)

    a.label("FG_CLR")
    a.lda_imm(0)
    a.sta_abs(GFX_KIND)
    a.label("FG_DONE")
    a.rts()

    # --- DEFSPR slot (0..31), DEFTILE slot (0..63), DEFBIG slot (0..1) ---
    a.label("PARSE_DEF_SLOT")
    a.jsr("FLUSH_GFX")
    a.jsr("EVAL_EXPR")
    a.lda_abs(FUNC_SLOT_OVR)
    a.cmp_imm(0xFF)
    a.beq("PDS_DEF")
    a.ldx_imm(0xFF)
    a.stx_abs(FUNC_SLOT_OVR)
    a.rts()
    a.label("PDS_DEF")
    a.lda_zp(ZP_ACC)
    a.rts()

    a.label("STMT_DEFSPR")
    a.jsr("PARSE_DEF_SLOT")
    a.and_imm(0x1F)
    a.sta_abs(GFX_SLOT)
    a.ldx_imm(9)
    a.stx_abs(IO_GPU)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(GFX_REM_LO)
    a.lda_imm(1)
    a.sta_abs(GFX_REM_HI)
    a.sta_abs(GFX_KIND) # 1 = Sprite
    a.rts()

    a.label("STMT_DEFTILE")
    a.jsr("PARSE_DEF_SLOT")
    a.and_imm(0x3F)
    a.sta_abs(GFX_SLOT)
    a.ldx_imm(13)
    a.stx_abs(IO_GPU)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(GFX_REM_LO)
    a.lda_imm(1)
    a.sta_abs(GFX_REM_HI)
    a.lda_imm(2)
    a.sta_abs(GFX_KIND) # 2 = Tile
    a.rts()

    a.label("STMT_DEFBIG")
    a.jsr("PARSE_DEF_SLOT")
    a.and_imm(0x01)
    a.sta_abs(GFX_SLOT)
    a.lda_imm(0)
    a.sta_abs(GFX_BIG_X)
    a.sta_abs(GFX_BIG_Y)
    a.lda_imm(3)
    a.sta_abs(GFX_KIND) # 3 = BigSprite
    a.rts()

    # --- PIX "RLE/Raw-hex..." Fast 6502 Pixel Decoder ---
    a.label("EMIT_GFX_PIXEL")
    a.lda_abs(GFX_KIND)
    a.beq("EGP_RTS")
    a.cmp_imm(3)
    a.beq("EGP_BIG")
    a.lda_abs(GFX_REM_LO)
    a.ora_abs(GFX_REM_HI)
    a.beq("EGP_DONE_256")
    a.lda_abs(GFX_PIX_VAL)
    a.sta_abs(IO_GPU)
    a.lda_abs(GFX_REM_LO)
    a.bne("EGP_D1")
    a.dec_abs(GFX_REM_HI)
    a.label("EGP_D1")
    a.dec_abs(GFX_REM_LO)
    a.lda_abs(GFX_REM_LO)
    a.ora_abs(GFX_REM_HI)
    a.bne("EGP_RTS")
    a.label("EGP_DONE_256")
    a.lda_imm(0)
    a.sta_abs(GFX_KIND)
    a.label("EGP_RTS")
    a.rts()

    a.label("EGP_BIG")
    a.lda_abs(GFX_BIG_Y)
    a.cmp_imm(128)
    a.bcs("EGP_RTS")
    a.lda_abs(GFX_BIG_X)
    a.bne("EGP_BIG_PX")
    a.lda_imm(22)
    a.sta_abs(IO_GPU)
    a.lda_abs(GFX_SLOT)
    a.sta_abs(IO_GPU)
    a.lda_abs(GFX_BIG_Y)
    a.sta_abs(IO_GPU)
    a.label("EGP_BIG_PX")
    a.lda_abs(GFX_PIX_VAL)
    a.sta_abs(IO_GPU)
    a.inc_abs(GFX_BIG_X)
    a.lda_abs(GFX_BIG_X)
    a.cmp_imm(128)
    a.bcc("EGP_RTS")
    a.lda_imm(0)
    a.sta_abs(GFX_BIG_X)
    a.inc_abs(GFX_BIG_Y)
    a.rts()

    a.label("PIX_READ_NIBBLE")
    a.ldy_imm(0)
    a.label("PRN_LP")
    a.lda_iny(ZP_TXT)
    a.beq("PRN_EOF")
    a.cmp_imm(ord('"'))
    a.beq("PRN_QUOTE")
    a.cmp_imm(ord(" "))
    a.bne("PRN_HEX")
    a.jsr("ADV_TXT")
    a.jmp("PRN_LP")

    a.label("PRN_HEX")
    a.jsr("ADV_TXT")
    a.cmp_imm(ord("0"))
    a.bcc("PRN_EOF")
    a.cmp_imm(ord("9") + 1)
    a.bcs("PRN_ALPHA")
    a.sec()
    a.sbc_imm(ord("0"))
    a.sec()
    a.rts()

    a.label("PRN_ALPHA")
    a.and_imm(0xDF)
    a.cmp_imm(ord("A"))
    a.bcc("PRN_EOF")
    a.cmp_imm(ord("F") + 1)
    a.bcs("PRN_EOF")
    a.sec()
    a.sbc_imm(ord("A") - 10)
    a.sec()
    a.rts()

    a.label("PRN_QUOTE")
    a.jsr("ADV_TXT")
    a.label("PRN_EOF")
    a.clc()
    a.rts()

    a.label("PIX_READ_BYTE")
    a.jsr("PIX_READ_NIBBLE")
    a.bcc("PRB_RET")
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.sta_abs(GFX_BYTE_TMP)
    a.jsr("PIX_READ_NIBBLE")
    a.bcc("PRB_RET")
    a.ora_abs(GFX_BYTE_TMP)
    a.sec()
    a.label("PRB_RET")
    a.rts()

    a.label("STMT_PIX")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord('"'))
    a.beq("PIX_OPEN_OK")
    a.jmp("SYNTAX_ERR")
    a.label("PIX_OPEN_OK")
    a.jsr("ADV_TXT")

    a.label("PIX_CMD_LP")
    a.jsr("PIX_READ_BYTE")
    a.bcc("PIX_RTS")
    a.beq("PIX_CMD_LP")
    a.bmi("PIX_RAW_RUN")
    a.sta_abs(GFX_CNT)
    a.jsr("PIX_READ_BYTE")
    a.bcc("PIX_RTS")
    a.sta_abs(GFX_PIX_VAL)
    a.label("PIX_RLE_LP")
    a.jsr("EMIT_GFX_PIXEL")
    a.dec_abs(GFX_CNT)
    a.bne("PIX_RLE_LP")
    a.jmp("PIX_CMD_LP")

    a.label("PIX_RAW_RUN")
    a.and_imm(0x7F)
    a.sta_abs(GFX_CNT)
    a.label("PIX_RAW_LP")
    a.jsr("PIX_READ_BYTE")
    a.bcc("PIX_RTS")
    a.sta_abs(GFX_PIX_VAL)
    a.jsr("EMIT_GFX_PIXEL")
    a.dec_abs(GFX_CNT)
    a.bne("PIX_RAW_LP")
    a.jmp("PIX_CMD_LP")

    a.label("PIX_RTS")
    a.rts()

    # --- Identifier Helpers for FUNC naam / DO naam ---
    # Reads (ZP_TXT),0: if 'A'..'Z', 'a'..'z' (uppercased), '0'..'9', or '_', returns Carry=1 and char in A
    a.label("READ_IDENT_CHAR")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("_"))
    a.beq("RIC_YES")
    a.jsr("IS_DIGIT")
    a.bcs("RIC_YES")
    a.cmp_imm(ord("a"))
    a.bcc("RIC_CHK_UP")
    a.cmp_imm(ord("z") + 1)
    a.bcs("RIC_NO")
    a.sec()
    a.sbc_imm(0x20)
    a.sec()
    a.rts()
    a.label("RIC_CHK_UP")
    a.cmp_imm(ord("A"))
    a.bcc("RIC_NO")
    a.cmp_imm(ord("Z") + 1)
    a.bcs("RIC_NO")
    a.label("RIC_YES")
    a.sec()
    a.rts()
    a.label("RIC_NO")
    a.clc()
    a.rts()

    a.label("PARSE_FUNC_NAME")
    a.jsr("SKIP_SPACES")
    a.ldx_imm(0)
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord('"'))
    a.beq("PFN_QUOTED")
    a.label("PFN_UNQ_LP")
    a.jsr("READ_IDENT_CHAR")
    a.bcc("PFN_DONE")
    a.cpx_imm(15)
    a.bcs("PFN_UNQ_ADV")
    a.sta_abx(FUNC_NAME_BUF)
    a.inx()
    a.label("PFN_UNQ_ADV")
    a.jsr("ADV_TXT")
    a.jmp("PFN_UNQ_LP")

    a.label("PFN_QUOTED")
    a.jsr("ADV_TXT")
    a.label("PFN_Q_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("PFN_DONE")
    a.cmp_imm(ord('"'))
    a.beq("PFN_Q_END")
    a.cmp_imm(ord("a"))
    a.bcc("PFN_Q_ST")
    a.cmp_imm(ord("z") + 1)
    a.bcs("PFN_Q_ST")
    a.sec()
    a.sbc_imm(0x20)
    a.label("PFN_Q_ST")
    a.cpx_imm(15)
    a.bcs("PFN_Q_ADV")
    a.sta_abx(FUNC_NAME_BUF)
    a.inx()
    a.label("PFN_Q_ADV")
    a.jsr("ADV_TXT")
    a.jmp("PFN_Q_LP")
    a.label("PFN_Q_END")
    a.jsr("ADV_TXT")

    a.label("PFN_DONE")
    a.cpx_imm(0)
    a.beq("PFN_ERR")
    a.lda_imm(0)
    a.sta_abx(FUNC_NAME_BUF)
    a.rts()
    a.label("PFN_ERR")
    a.jmp("SYNTAX_ERR")

    # Compare function name at ZP_TXT against FUNC_NAME_BUF (Carry=1 if exact match, advancing ZP_TXT)
    a.label("MATCH_FUNC_NAME")
    a.jsr("SKIP_SPACES")
    a.ldx_imm(0)
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord('"'))
    a.beq("MFN_QUOTED")
    a.label("MFN_UNQ_LP")
    a.jsr("READ_IDENT_CHAR")
    a.bcc("MFN_CHK_END")
    a.cpx_imm(15)
    a.bcs("MFN_UNQ_ADV")
    a.cmp_abx(FUNC_NAME_BUF)
    a.bne("MFN_NO")
    a.inx()
    a.label("MFN_UNQ_ADV")
    a.jsr("ADV_TXT")
    a.jmp("MFN_UNQ_LP")

    a.label("MFN_QUOTED")
    a.jsr("ADV_TXT")
    a.label("MFN_Q_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("MFN_CHK_END")
    a.cmp_imm(ord('"'))
    a.beq("MFN_Q_END")
    a.cmp_imm(ord("a"))
    a.bcc("MFN_Q_CMP")
    a.cmp_imm(ord("z") + 1)
    a.bcs("MFN_Q_CMP")
    a.sec()
    a.sbc_imm(0x20)
    a.label("MFN_Q_CMP")
    a.cpx_imm(15)
    a.bcs("MFN_Q_ADV")
    a.cmp_abx(FUNC_NAME_BUF)
    a.bne("MFN_NO")
    a.inx()
    a.label("MFN_Q_ADV")
    a.jsr("ADV_TXT")
    a.jmp("MFN_Q_LP")
    a.label("MFN_Q_END")
    a.jsr("ADV_TXT")

    a.label("MFN_CHK_END")
    a.cpx_imm(0)
    a.beq("MFN_NO")
    a.lda_abx(FUNC_NAME_BUF)
    a.bne("MFN_NO")
    a.sec()
    a.rts()
    a.label("MFN_NO")
    a.clc()
    a.rts()

    # Skip current statement at ZP_TXT (respecting REM/' comments and "..." quotes).
    # Returns Carry=1 with ZP_TXT after ':' if another statement follows on this line, else Carry=0 at '\0'.
    a.label("SKIP_STMT_SCAN")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("SSS_EOL")
    a.cmp_imm(ord("'"))
    a.beq("SSS_TO_EOL")
    a.lda_imm("<KW_REM")
    a.ldy_imm(">KW_REM")
    a.jsr("MATCH_KW")
    a.bcs("SSS_TO_EOL")

    a.ldx_imm(0) # Quote state (0 = outside, 1 = inside "...")
    a.label("SSS_CHR_LP")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("SSS_EOL")
    a.cmp_imm(ord("'"))
    a.bne("SSS_CHK_Q")
    a.cpx_imm(0)
    a.beq("SSS_TO_EOL")
    a.label("SSS_CHK_Q")
    a.cmp_imm(ord('"'))
    a.bne("SSS_CHK_COL")
    a.txa()
    a.eor_imm(1)
    a.tax()
    a.jsr("ADV_TXT")
    a.jmp("SSS_CHR_LP")

    a.label("SSS_CHK_COL")
    a.cmp_imm(ord(":"))
    a.bne("SSS_ADV")
    a.cpx_imm(0)
    a.bne("SSS_ADV")
    a.jsr("ADV_TXT")
    a.jsr("SKIP_SPACES")
    a.sec()
    a.rts()

    a.label("SSS_ADV")
    a.jsr("ADV_TXT")
    a.jmp("SSS_CHR_LP")

    a.label("SSS_TO_EOL")
    a.ldy_imm(0)
    a.label("SSS_EOL_LP")
    a.lda_iny(ZP_TXT)
    a.beq("SSS_EOL")
    a.jsr("ADV_TXT")
    a.jmp("SSS_EOL_LP")

    a.label("SSS_EOL")
    a.clc()
    a.rts()

    # --- FUNC naam: When hit during normal flow, skip entire block past ENDFUNC! ---
    a.label("STMT_FUNC")
    a.jsr("SKIP_STMT_SCAN")
    a.bcs("FUNC_CHK_STMT")
    a.jmp("FUNC_NEXT_LINE")

    a.label("FUNC_CHK_STMT")
    a.jsr("SKIP_SPACES")
    a.lda_imm("<KW_ENDFUNC")
    a.ldy_imm(">KW_ENDFUNC")
    a.jsr("MATCH_KW")
    a.bcc("FUNC_SKIP_MORE")
    a.lda_imm(0)
    a.sta_zp(ZP_JUMPED)
    a.rts()

    a.label("FUNC_SKIP_MORE")
    a.jsr("SKIP_STMT_SCAN")
    a.bcs("FUNC_CHK_STMT")

    a.label("FUNC_NEXT_LINE")
    a.lda_zp(ZP_RUN)
    a.beq("FUNC_RTS")
    a.ldy_imm(0)
    a.lda_iny(ZP_CURLINE)
    a.beq("FUNC_EOF")
    a.clc()
    a.adc_zp(ZP_CURLINE)
    a.sta_zp(ZP_CURLINE)
    a.bcc("FUNC_NL_CHK")
    a.inc_zp(ZP_CURLINE + 1)
    a.label("FUNC_NL_CHK")
    a.ldy_imm(0)
    a.lda_iny(ZP_CURLINE)
    a.beq("FUNC_EOF")
    a.lda_zp(ZP_CURLINE)
    a.clc()
    a.adc_imm(3)
    a.sta_zp(ZP_TXT)
    a.lda_zp(ZP_CURLINE + 1)
    a.adc_imm(0)
    a.sta_zp(ZP_TXT + 1)
    a.jmp("FUNC_CHK_STMT")

    a.label("FUNC_EOF")
    a.lda_imm(1)
    a.sta_zp(ZP_JUMPED)
    a.label("FUNC_RTS")
    a.rts()

    # --- ENDFUNC (and RETURN): Flush GFX, clear slot override, pop caller position ---
    a.label("STMT_ENDFUNC")
    a.jsr("FLUSH_GFX")
    a.lda_imm(0xFF)
    a.sta_abs(FUNC_SLOT_OVR)
    a.ldx_zp(ZP_GOSUB_SP)
    a.beq("ENDFUNC_RTS")
    a.dex()
    a.dex()
    a.stx_zp(ZP_GOSUB_SP)
    a.lda_abx(GOSUB_LINE)
    a.sta_zp(ZP_CURLINE)
    a.lda_abx(GOSUB_LINE + 1)
    a.sta_zp(ZP_CURLINE + 1)
    a.lda_abx(GOSUB_TXT)
    a.sta_zp(ZP_TXT)
    a.lda_abx(GOSUB_TXT + 1)
    a.sta_zp(ZP_TXT + 1)
    a.lda_imm(0)
    a.sta_zp(ZP_JUMPED)
    a.lda_zp(ZP_CURLINE + 1)
    a.bne("ENDFUNC_RTS")
    a.sta_zp(ZP_RUN) # Direct-mode DO call finished (sentinel $0000)!
    a.lda_imm(1)
    a.sta_zp(ZP_JUMPED) # Stop inner DO_DIR_LP statement loop so outer DIRECT_EXEC resumes!
    a.label("ENDFUNC_RTS")
    a.rts()

    # --- DO naam [, slot]: Call named FUNC block anywhere in program! ---
    a.label("STMT_DO")
    a.jsr("PARSE_FUNC_NAME")
    a.lda_imm(0xFF)
    a.sta_abs(FUNC_SLOT_OVR)
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(","))
    a.bne("DO_SAVE_POS")
    a.jsr("ADV_TXT")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.sta_abs(FUNC_SLOT_OVR)

    a.label("DO_SAVE_POS")
    a.lda_zp(ZP_CURLINE)
    a.sta_abs(FUNC_CALLER_LINE)
    a.lda_zp(ZP_CURLINE + 1)
    a.sta_abs(FUNC_CALLER_LINE + 1)
    a.lda_zp(ZP_TXT)
    a.sta_abs(FUNC_CALLER_TXT)
    a.lda_zp(ZP_TXT + 1)
    a.sta_abs(FUNC_CALLER_TXT + 1)

    # Scan program from PRG_BASE ($0800) for FUNC <FUNC_NAME_BUF>
    a.lda_imm(PRG_BASE & 0xFF)
    a.sta_abs(FUNC_SCAN_LINE)
    a.lda_imm(PRG_BASE >> 8)
    a.sta_abs(FUNC_SCAN_LINE + 1)

    a.label("DO_LINE_LP")
    a.lda_abs(FUNC_SCAN_LINE)
    a.sta_zp(ZP_TMP)
    a.lda_abs(FUNC_SCAN_LINE + 1)
    a.sta_zp(ZP_TMP + 1)
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.beq("DO_NOT_FOUND")
    a.lda_abs(FUNC_SCAN_LINE)
    a.clc()
    a.adc_imm(3)
    a.sta_zp(ZP_TXT)
    a.lda_abs(FUNC_SCAN_LINE + 1)
    a.adc_imm(0)
    a.sta_zp(ZP_TXT + 1)

    a.label("DO_STMT_LP")
    a.jsr("SKIP_SPACES")
    a.lda_imm("<KW_FUNC")
    a.ldy_imm(">KW_FUNC")
    a.jsr("MATCH_KW")
    a.bcc("DO_SKIP_STMT")
    a.jsr("MATCH_FUNC_NAME")
    a.bcs("DO_FOUND")

    a.label("DO_SKIP_STMT")
    a.jsr("SKIP_STMT_SCAN")
    a.bcs("DO_STMT_LP")
    a.lda_abs(FUNC_SCAN_LINE)
    a.sta_zp(ZP_TMP)
    a.lda_abs(FUNC_SCAN_LINE + 1)
    a.sta_zp(ZP_TMP + 1)
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.clc()
    a.adc_abs(FUNC_SCAN_LINE)
    a.sta_abs(FUNC_SCAN_LINE)
    a.bcc("DO_LINE_LP")
    a.inc_abs(FUNC_SCAN_LINE + 1)
    a.jmp("DO_LINE_LP")

    a.label("DO_RESTORE_CALLER")
    a.lda_abs(FUNC_CALLER_LINE)
    a.sta_zp(ZP_CURLINE)
    a.lda_abs(FUNC_CALLER_LINE + 1)
    a.sta_zp(ZP_CURLINE + 1)
    a.lda_abs(FUNC_CALLER_TXT)
    a.sta_zp(ZP_TXT)
    a.lda_abs(FUNC_CALLER_TXT + 1)
    a.sta_zp(ZP_TXT + 1)
    a.rts()

    a.label("DO_NOT_FOUND")
    a.jsr("DO_RESTORE_CALLER")
    a.lda_imm("<STR_FUNC_ERR")
    a.ldy_imm(">STR_FUNC_ERR")
    a.jsr("PRINT_STR")
    a.lda_imm(0xFF)
    a.sta_zp(ZP_RUN)
    a.lda_imm(1)
    a.sta_abs(IO_MODE)
    a.rts()

    a.label("DO_FOUND")
    a.ldx_zp(ZP_GOSUB_SP)
    a.cpx_imm(30)
    a.bcc("DO_STACK_OK")
    a.jsr("DO_RESTORE_CALLER")
    a.jmp("SYNTAX_ERR")

    a.label("DO_STACK_OK")
    a.lda_zp(ZP_RUN)
    a.beq("DO_FROM_DIRECT")

    # Running program call
    a.lda_abs(FUNC_CALLER_LINE)
    a.sta_abx(GOSUB_LINE)
    a.lda_abs(FUNC_CALLER_LINE + 1)
    a.sta_abx(GOSUB_LINE + 1)
    a.lda_abs(FUNC_CALLER_TXT)
    a.sta_abx(GOSUB_TXT)
    a.lda_abs(FUNC_CALLER_TXT + 1)
    a.sta_abx(GOSUB_TXT + 1)
    a.inx()
    a.inx()
    a.stx_zp(ZP_GOSUB_SP)
    a.lda_abs(FUNC_SCAN_LINE)
    a.sta_zp(ZP_CURLINE)
    a.lda_abs(FUNC_SCAN_LINE + 1)
    a.sta_zp(ZP_CURLINE + 1)
    a.lda_imm(0)
    a.sta_zp(ZP_JUMPED)
    a.rts()

    # Direct-mode call (e.g. "> DO RAKET"): push $0000 sentinel and run until ENDFUNC!
    a.label("DO_FROM_DIRECT")
    a.lda_imm(0)
    a.sta_abx(GOSUB_LINE)
    a.sta_abx(GOSUB_LINE + 1)
    a.lda_abs(FUNC_CALLER_TXT)
    a.sta_abx(GOSUB_TXT)
    a.lda_abs(FUNC_CALLER_TXT + 1)
    a.sta_abx(GOSUB_TXT + 1)
    a.inx()
    a.inx()
    a.stx_zp(ZP_GOSUB_SP)
    a.lda_abs(FUNC_SCAN_LINE)
    a.sta_zp(ZP_CURLINE)
    a.lda_abs(FUNC_SCAN_LINE + 1)
    a.sta_zp(ZP_CURLINE + 1)
    a.lda_imm(1)
    a.sta_zp(ZP_RUN)
    a.jsr("EXEC_LINE_STATEMENTS")

    a.label("DO_DIR_LP")
    a.lda_zp(ZP_RUN)
    a.beq("DO_DIR_RTS")
    a.cmp_imm(0xFF)
    a.beq("DO_DIR_RTS")
    a.lda_abs(IO_STATUS)
    a.bpl("DO_DIR_NOBRK")
    a.lda_abs(IO_TERM)
    a.jmp("RUN_BREAK")
    a.label("DO_DIR_NOBRK")
    a.lda_zp(ZP_JUMPED)
    a.bne("DO_DIR_EXEC")
    a.ldy_imm(0)
    a.lda_iny(ZP_CURLINE)
    a.beq("DO_DIR_EOF")
    a.clc()
    a.adc_zp(ZP_CURLINE)
    a.sta_zp(ZP_CURLINE)
    a.bcc("DO_DIR_EXEC")
    a.inc_zp(ZP_CURLINE + 1)
    a.label("DO_DIR_EXEC")
    a.ldy_imm(0)
    a.lda_iny(ZP_CURLINE)
    a.beq("DO_DIR_EOF")
    a.lda_zp(ZP_CURLINE)
    a.clc()
    a.adc_imm(3)
    a.sta_zp(ZP_TXT)
    a.lda_zp(ZP_CURLINE + 1)
    a.adc_imm(0)
    a.sta_zp(ZP_TXT + 1)
    a.jsr("EXEC_LINE_STATEMENTS")
    a.jmp("DO_DIR_LP")

    a.label("DO_DIR_EOF")
    a.jsr("FLUSH_GFX")
    a.lda_imm(0)
    a.sta_zp(ZP_RUN)
    a.sta_zp(ZP_GOSUB_SP)
    a.jsr("DO_RESTORE_CALLER")
    a.label("DO_DIR_RTS")
    a.lda_imm(0)
    a.sta_zp(ZP_JUMPED)
    a.rts()

    # ========================================================================
    # 14. SD-Card & SDRAM-Disk File Handle Commands:
    #     OPEN "NAAM" [, mode] | WRITE ... | READ V[,V2] | GET V | PUT expr |
    #     SEEK expr | EOF | CLOSE | TYPE ["NAAM"]
    # ========================================================================
    a.label("SET_ZP_FPTR")
    a.lda_abs(FILE_PTR_LO)
    a.sta_zp(ZP_FPTR)
    a.lda_abs(FILE_PTR_HI)
    a.clc()
    a.adc_imm(FILE_BUF >> 8)
    a.sta_zp(ZP_FPTR + 1)
    a.ldy_imm(0)
    a.rts()

    # Compare FILE_PTR vs FILE_LEN: Carry=1 if FILE_PTR >= FILE_LEN (at EOF)
    a.label("CHK_FILE_EOF")
    a.lda_abs(FILE_PTR_HI)
    a.cmp_abs(FILE_LEN_HI)
    a.bne("CFE_DN")
    a.lda_abs(FILE_PTR_LO)
    a.cmp_abs(FILE_LEN_LO)
    a.label("CFE_DN")
    a.rts()

    # --- EOF Function: returns 1 if FILE_PTR >= FILE_LEN, else 0 ---
    a.label("FN_EOF")
    a.jsr("CHK_FILE_EOF")
    a.lda_imm(0)
    a.rol_a()
    a.jmp("STORE_ACC_U8")

    # --- FILE_PUT_CHAR: Write byte A to ($6000 + FILE_PTR), preserving X & Y ---
    a.label("FILE_PUT_CHAR")
    a.sta_abs(FILE_CHR_TMP)
    a.tya()
    a.pha()
    a.lda_abs(FILE_PTR_HI)
    a.cmp_imm(0x0F)
    a.bcc("FPC_OK")
    a.bne("FPC_EXIT")
    a.lda_abs(FILE_PTR_LO)
    a.cmp_imm(0xFF)
    a.bcs("FPC_EXIT")
    a.label("FPC_OK")
    a.lda_abs(FILE_DIRTY)
    a.bne("FPC_WRITE_B")
    a.lda_abs(FILE_PTR_LO)
    a.ora_abs(FILE_PTR_HI)
    a.bne("FPC_WRITE_B")
    a.sta_abs(FILE_LEN_LO)
    a.sta_abs(FILE_LEN_HI)
    a.label("FPC_WRITE_B")
    a.jsr("SET_ZP_FPTR")
    a.lda_abs(FILE_CHR_TMP)
    a.sta_iny(ZP_FPTR)
    a.lda_imm(1)
    a.sta_abs(FILE_DIRTY)
    a.inc_abs(FILE_PTR_LO)
    a.bne("FPC_CHK_LEN")
    a.inc_abs(FILE_PTR_HI)
    a.label("FPC_CHK_LEN")
    a.jsr("CHK_FILE_EOF")
    a.bcc("FPC_EXIT")
    a.lda_abs(FILE_PTR_LO)
    a.sta_abs(FILE_LEN_LO)
    a.lda_abs(FILE_PTR_HI)
    a.sta_abs(FILE_LEN_HI)
    a.jsr("SET_ZP_FPTR")
    a.lda_imm(0)
    a.sta_iny(ZP_FPTR)
    a.label("FPC_EXIT")
    a.pla()
    a.tay()
    a.lda_abs(FILE_CHR_TMP)
    a.rts()

    # --- WRITE expr / "tekst" [, ...] (redirects PRINT to open file buffer at $6000) ---
    a.label("STMT_WRITE")
    a.lda_imm(1)
    a.sta_abs(FILE_OUT_FLAG)
    a.jsr("STMT_PRINT")
    a.lda_imm(0)
    a.sta_abs(FILE_OUT_FLAG)
    a.rts()

    # --- PUT expr (write single raw byte 0..255 to open file) ---
    a.label("STMT_PUT")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.jmp("FILE_PUT_CHAR")

    # --- SEEK expr (set file read/write byte pointer 0..4095) ---
    a.label("STMT_SEEK")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.sta_abs(FILE_PTR_LO)
    a.lda_zp(ZP_ACC + 1)
    a.and_imm(0x0F)
    a.sta_abs(FILE_PTR_HI)
    a.rts()

    # Parse variable name A..Z from ZP_TXT -> returns (var_idx * 2) in X
    a.label("PARSE_VAR_TARGET")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("A"))
    a.bcc("PVT_ERR")
    a.cmp_imm(ord("Z") + 1)
    a.bcs("PVT_ERR")
    a.sec()
    a.sbc_imm(ord("A"))
    a.asl_a()
    a.tax()
    a.jmp("ADV_TXT")
    a.label("PVT_ERR")
    a.pla()
    a.pla()
    a.jmp("SYNTAX_ERR")

    # --- GET V (read single raw byte / ASCII char 0..255 from open file into V, or 0 at EOF) ---
    a.label("STMT_GET")
    a.jsr("PARSE_VAR_TARGET")
    a.lda_imm(0)
    a.sta_abx(VARS_BASE + 1)
    a.jsr("CHK_FILE_EOF")
    a.bcc("GET_OK")
    a.lda_imm(0)
    a.sta_abx(VARS_BASE)
    a.rts()
    a.label("GET_OK")
    a.jsr("SET_ZP_FPTR")
    a.lda_iny(ZP_FPTR)
    a.sta_abx(VARS_BASE)
    a.inc_abs(FILE_PTR_LO)
    a.bne("GET_RTS")
    a.inc_abs(FILE_PTR_HI)
    a.label("GET_RTS")
    a.rts()

    # --- CLOSE: Flush open file at $6000 to SD-Card / SDRAM-Disk if modified ---
    a.label("STMT_CLOSE")
    a.lda_imm(0)
    a.sta_abs(FILE_OUT_FLAG)
    a.lda_abs(FILE_DIRTY)
    a.beq("CLS_FILE_RTS")
    a.lda_imm(0)
    a.sta_abs(FILE_DIRTY)
    a.ldx_imm(0)
    a.label("CLF_CP_FN")
    a.lda_abx(FILE_NAME_SAVE)
    a.sta_abx(FNAME_BUF)
    a.inx()
    a.cpx_imm(16)
    a.bcc("CLF_CP_FN")
    a.lda_abs(FILE_SLOT_SAVE)
    a.sta_abs(DISK_SLOT)
    a.lda_imm(0x00)
    a.sta_zp(ZP_ARGS)
    a.lda_imm(FILE_BUF >> 8)
    a.sta_zp(ZP_ARGS + 1)
    a.lda_abs(FILE_LEN_LO)
    a.ora_abs(FILE_LEN_HI)
    a.bne("CLF_LEN_OK")
    a.inc_abs(FILE_LEN_LO)
    a.label("CLF_LEN_OK")
    a.lda_abs(FILE_LEN_LO)
    a.sta_zp(ZP_ARGS + 2)
    a.lda_abs(FILE_LEN_HI)
    a.sta_zp(ZP_ARGS + 3)
    a.lda_imm(ord("B"))
    a.sta_zp(ZP_ARGS + 4)
    a.jmp("SV_DO_INIT")
    a.label("CLS_FILE_RTS")
    a.rts()

    # --- TYPE ["NAAM"]: Print open file (or open "NAAM" first) to terminal ---
    a.label("STMT_TYPE")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("TYP_REWIND")
    a.cmp_imm(ord(":"))
    a.beq("TYP_REWIND")
    a.jsr("STMT_OPEN")
    a.label("TYP_REWIND")
    a.lda_imm(0)
    a.sta_abs(FILE_OUT_FLAG)
    a.sta_abs(FILE_PTR_LO)
    a.sta_abs(FILE_PTR_HI)
    a.label("TYP_LP")
    a.jsr("CHK_FILE_EOF")
    a.bcs("TYP_DN")
    a.jsr("SET_ZP_FPTR")
    a.lda_iny(ZP_FPTR)
    a.beq("TYP_ADV")
    a.jsr("PUTC")
    a.label("TYP_ADV")
    a.inc_abs(FILE_PTR_LO)
    a.bne("TYP_LP")
    a.inc_abs(FILE_PTR_HI)
    a.jmp("TYP_LP")
    a.label("TYP_DN")
    a.lda_imm(0)
    a.sta_abs(FILE_PTR_LO)
    a.sta_abs(FILE_PTR_HI)
    a.rts()

    # --- READ V [, V2, ...] (read signed 16-bit integer or $hex from open file into V) ---
    a.label("STMT_READ")
    a.jsr("PARSE_VAR_TARGET")
    a.txa()
    a.pha()
    a.lda_zp(ZP_TXT)
    a.sta_abs(FUNC_CALLER_TXT)
    a.lda_zp(ZP_TXT + 1)
    a.sta_abs(FUNC_CALLER_TXT + 1)

    a.label("RD_SKIP_LP")
    a.jsr("CHK_FILE_EOF")
    a.bcc("RD_CHK_CH")
    a.lda_imm(0)
    a.sta_zp(ZP_ACC)
    a.sta_zp(ZP_ACC + 1)
    a.jmp("RD_STORE_V")

    a.label("RD_CHK_CH")
    a.jsr("SET_ZP_FPTR")
    a.lda_iny(ZP_FPTR)
    a.cmp_imm(ord("-"))
    a.beq("RD_PARSE_NUM")
    a.cmp_imm(ord("$"))
    a.beq("RD_PARSE_NUM")
    a.jsr("IS_DIGIT")
    a.bcs("RD_PARSE_NUM")
    a.inc_abs(FILE_PTR_LO)
    a.bne("RD_SKIP_LP")
    a.inc_abs(FILE_PTR_HI)
    a.jmp("RD_SKIP_LP")

    a.label("RD_PARSE_NUM")
    a.lda_zp(ZP_FPTR)
    a.sta_zp(ZP_TXT)
    a.lda_zp(ZP_FPTR + 1)
    a.sta_zp(ZP_TXT + 1)
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("-"))
    a.bne("RD_POS_NUM")
    a.jsr("ADV_TXT")
    a.jsr("RD_UINT_HEX")
    a.jsr("NEG_ACC")
    a.jmp("RD_UPD_PTR")
    a.label("RD_POS_NUM")
    a.jsr("RD_UINT_HEX")

    a.label("RD_UPD_PTR")
    a.lda_zp(ZP_TXT)
    a.sta_abs(FILE_PTR_LO)
    a.lda_zp(ZP_TXT + 1)
    a.sec()
    a.sbc_imm(FILE_BUF >> 8)
    a.sta_abs(FILE_PTR_HI)

    # Skip trailing whitespace / CR / LF / comma so EOF=1 immediately after reading last number
    a.label("RD_TRAIL_LP")
    a.jsr("CHK_FILE_EOF")
    a.bcs("RD_STORE_V")
    a.jsr("SET_ZP_FPTR")
    a.lda_iny(ZP_FPTR)
    a.cmp_imm(ord(","))
    a.beq("RD_TR_ADV")
    a.cmp_imm(0x21)
    a.bcs("RD_STORE_V")
    a.label("RD_TR_ADV")
    a.inc_abs(FILE_PTR_LO)
    a.bne("RD_TRAIL_LP")
    a.inc_abs(FILE_PTR_HI)
    a.jmp("RD_TRAIL_LP")

    a.label("RD_STORE_V")
    a.lda_abs(FUNC_CALLER_TXT)
    a.sta_zp(ZP_TXT)
    a.lda_abs(FUNC_CALLER_TXT + 1)
    a.sta_zp(ZP_TXT + 1)
    a.pla()
    a.tax()
    a.lda_zp(ZP_ACC)
    a.sta_abx(VARS_BASE)
    a.lda_zp(ZP_ACC + 1)
    a.sta_abx(VARS_BASE + 1)
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(","))
    a.bne("RD_DONE")
    a.jsr("ADV_TXT")
    a.jmp("STMT_READ")
    a.label("RD_DONE")
    a.rts()

    a.label("RD_UINT_HEX")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord("$"))
    a.beq("PARSE_HEX")
    a.jmp("PARSE_UINT")

    # --- OPEN "NAAM" [, mode] (0=Read/Write, 1=New/Overwrite, 2=Append) ---
    a.label("STMT_OPEN")
    a.jsr("PARSE_FILE_SPEC")
    a.ldx_imm(0)
    a.label("OPN_CP_FN")
    a.lda_abx(FNAME_BUF)
    a.sta_abx(FILE_NAME_SAVE)
    a.inx()
    a.cpx_imm(16)
    a.bcc("OPN_CP_FN")
    a.lda_abs(DISK_SLOT)
    a.sta_abs(FILE_SLOT_SAVE)

    a.lda_imm(0)
    a.sta_abs(FILE_MODE)
    a.sta_abs(FILE_OUT_FLAG)
    a.sta_abs(FILE_PTR_LO)
    a.sta_abs(FILE_PTR_HI)
    a.sta_abs(FILE_LEN_LO)
    a.sta_abs(FILE_LEN_HI)
    a.sta_abs(FILE_DIRTY)
    a.sta_abs(FILE_BUF)

    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("OPN_DO_DISK")
    a.cmp_imm(ord(":"))
    a.beq("OPN_DO_DISK")
    a.jsr("SKIP_COMMA")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.sta_abs(FILE_MODE)
    a.cmp_imm(1)
    a.bne("OPN_DO_DISK")
    a.sta_abs(FILE_DIRTY)
    a.rts()

    a.label("OPN_DO_DISK")
    a.jsr("SD_INIT")
    a.jsr("SETUP_DIR_SEC")
    a.jsr("DISK_READ_SEC")
    a.lda_abs(DISK_SLOT)
    a.bpl("OPN_CHK_SLOT")
    a.lda_imm(0)
    a.sta_abs(DISK_SLOT)
    a.label("OPN_FIND_LP")
    a.jsr("CALC_DIR_PTR")
    a.jsr("MATCH_DIR_NAME")
    a.beq("OPN_FOUND")
    a.inc_abs(DISK_SLOT)
    a.lda_abs(DISK_SLOT)
    a.cmp_imm(15)
    a.bcc("OPN_FIND_LP")
    a.jmp("OPN_NEW_FILE")

    a.label("OPN_CHK_SLOT")
    a.jsr("CALC_DIR_PTR")
    a.jsr("CHK_BBC_MAGIC")
    a.beq("OPN_FOUND")
    a.label("OPN_NEW_FILE")
    a.lda_imm(1)
    a.sta_abs(FILE_DIRTY)
    a.rts()

    a.label("OPN_FOUND")
    a.ldy_imm(20)
    a.lda_iny(ZP_TMP)
    a.sta_abs(FILE_LEN_LO)
    a.iny()
    a.lda_iny(ZP_TMP)
    a.and_imm(0x0F)
    a.sta_abs(FILE_LEN_HI)

    a.jsr("SETUP_SLOT_SEC")
    a.lda_imm(0x00)
    a.sta_zp(ZP_DST)
    a.lda_imm(FILE_BUF >> 8)
    a.sta_zp(ZP_DST + 1)
    a.lda_abs(FILE_LEN_HI)
    a.lsr_a()
    a.clc()
    a.adc_imm(1)
    a.sta_zp(ZP_SIGN)
    a.label("OPN_SEC_LP")
    a.jsr("DISK_READ_SEC")
    a.dec_zp(ZP_SIGN)
    a.bne("OPN_SEC_LP")

    a.lda_abs(FILE_LEN_LO)
    a.sta_abs(FILE_PTR_LO)
    a.lda_abs(FILE_LEN_HI)
    a.sta_abs(FILE_PTR_HI)
    a.jsr("SET_ZP_FPTR")
    a.lda_imm(0)
    a.sta_iny(ZP_FPTR)

    a.lda_abs(FILE_MODE)
    a.cmp_imm(2)
    a.beq("OPN_DONE")
    a.lda_imm(0)
    a.sta_abs(FILE_PTR_LO)
    a.sta_abs(FILE_PTR_HI)
    a.label("OPN_DONE")
    a.rts()

    # --- WAV [nr [, rate]] (0 or no arg = list 16 SD WAVs, 1..16 = play SD WAV via HDMI PCM DAC) ---
    a.label("WAV_READ_DIR")
    a.lda_imm(0)
    a.sta_abs(DISK_FORCE_RD)
    a.jsr("SD_INIT")
    a.lda_imm(0x00)
    a.sta_zp(ZP_DST)
    a.sta_abs(DISK_SEC_LO)
    a.lda_imm(SD_BUF >> 8)
    a.sta_zp(ZP_DST + 1)
    a.lda_imm(0x20)
    a.sta_abs(DISK_SEC_HI)
    a.jmp("DISK_READ_SEC")

    a.label("WAV_STOP_CMD")
    a.lda_imm(0)
    a.sta_abs(IO_ADMA_CTRL)
    a.rts()

    a.label("STMT_WAV")
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.beq("WAV_LIST")
    a.cmp_imm(ord(":"))
    a.beq("WAV_LIST")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.beq("WAV_STOP_CMD")
    a.sec()
    a.sbc_imm(1)
    a.and_imm(0x0F)
    a.sta_zp(ZP_ARGS)
    a.lda_imm(0)
    a.sta_zp(ZP_ARGS + 1) # rate (0 = default from SD dir)
    a.sta_zp(ZP_ARGS + 5) # mode (0 = background 1x, 1 = background loop, 2 = wait until done)
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(","))
    a.bne("WAV_PLAY_DO")
    a.jsr("SKIP_COMMA")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.and_imm(0x07)
    a.sta_zp(ZP_ARGS + 1)
    a.jsr("SKIP_SPACES")
    a.ldy_imm(0)
    a.lda_iny(ZP_TXT)
    a.cmp_imm(ord(","))
    a.bne("WAV_PLAY_DO")
    a.jsr("SKIP_COMMA")
    a.jsr("EVAL_EXPR")
    a.lda_zp(ZP_ACC)
    a.sta_zp(ZP_ARGS + 5)
    a.jmp("WAV_PLAY_DO")

    a.label("WAV_LIST")
    a.jsr("WAV_READ_DIR")
    a.lda_imm(0)
    a.sta_abs(DISK_SLOT)
    a.label("WAV_LST_LP")
    a.jsr("CALC_DIR_PTR")
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("W"))
    a.bne("WAV_LST_NXT")
    a.lda_imm(ord("#"))
    a.jsr("PUTC")
    a.lda_abs(DISK_SLOT)
    a.clc()
    a.adc_imm(1)
    a.sta_zp(ZP_ACC)
    a.lda_imm(0)
    a.sta_zp(ZP_ACC + 1)
    a.jsr("PRINT_INT16")
    a.lda_imm(ord(":"))
    a.jsr("PUTC")
    a.lda_imm(ord(" "))
    a.jsr("PUTC")
    a.jsr("CALC_DIR_PTR")
    a.lda_zp(ZP_TMP)
    a.clc()
    a.adc_imm(4)
    a.ldy_zp(ZP_TMP + 1)
    a.jsr("PRINT_STR")
    a.jsr("NEWLINE")
    a.label("WAV_LST_NXT")
    a.inc_abs(DISK_SLOT)
    a.lda_abs(DISK_SLOT)
    a.cmp_imm(16)
    a.bcc("WAV_LST_LP")
    a.rts()

    a.label("WAV_PLAY_DO")
    a.jsr("WAV_READ_DIR")
    a.lda_zp(ZP_ARGS)
    a.sta_abs(DISK_SLOT)
    a.jsr("CALC_DIR_PTR")
    a.ldy_imm(0)
    a.lda_iny(ZP_TMP)
    a.cmp_imm(ord("W"))
    a.beq("WAV_DIR_OK")
    a.lda_zp(ZP_ARGS)
    a.and_imm(0x03)
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.clc()
    a.adc_imm(0x10)
    a.sta_abs(DISK_SEC_LO)
    a.lda_zp(ZP_ARGS)
    a.lsr_a()
    a.lsr_a()
    a.clc()
    a.adc_imm(0x20)
    a.sta_abs(DISK_SEC_HI)
    a.lda_imm(64)
    a.sta_zp(ZP_ARGS + 2)
    a.lda_imm(128)
    a.sta_zp(ZP_ARGS + 3)
    a.lda_zp(ZP_ARGS + 1)
    a.bne("WAV_LOAD_SDRAM")
    a.lda_imm(1)
    a.sta_zp(ZP_ARGS + 1)
    a.jmp("WAV_LOAD_SDRAM")

    a.label("WAV_DIR_OK")
    a.ldy_imm(20)
    a.lda_iny(ZP_TMP)
    a.sta_abs(DISK_SEC_LO)
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_abs(DISK_SEC_HI)
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ARGS + 2)
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ARGS + 3)
    a.lda_zp(ZP_ARGS + 1)
    a.bne("WAV_LOAD_SDRAM")
    a.iny()
    a.lda_iny(ZP_TMP)
    a.sta_zp(ZP_ARGS + 1)

    a.label("WAV_LOAD_SDRAM")
    a.lda_imm(0)
    a.sta_abs(IO_ADMA_CTRL)
    a.sta_zp(ZP_ARGS + 4)
    a.label("WAV_LD_LP")
    a.lda_imm(0x00)
    a.sta_zp(ZP_DST)
    a.lda_imm(SD_BUF >> 8)
    a.sta_zp(ZP_DST + 1)
    a.jsr("DISK_READ_SEC")
    a.lda_imm(62)
    a.sta_abs(IO_RD_BANK)
    a.lda_zp(ZP_ARGS + 4)
    a.sta_abs(IO_RD_HI)
    a.ldy_imm(0)
    a.label("WAV_CP0")
    a.sty_abs(IO_RD_LO)
    a.lda_aby(SD_BUF)
    a.sta_abs(IO_RD_DATA)
    a.iny()
    a.bne("WAV_CP0")
    a.inc_zp(ZP_ARGS + 4)
    a.lda_zp(ZP_ARGS + 4)
    a.sta_abs(IO_RD_HI)
    a.label("WAV_CP1")
    a.sty_abs(IO_RD_LO)
    a.lda_aby(SD_BUF + 0x100)
    a.sta_abs(IO_RD_DATA)
    a.iny()
    a.bne("WAV_CP1")
    a.inc_zp(ZP_ARGS + 4)
    a.dec_zp(ZP_ARGS + 2)
    a.bne("WAV_LD_LP")

    # Start Autonomous Audio Co-Processor (Hulp-CPU at $A018..$A01B)
    a.lda_imm(62)
    a.sta_abs(IO_ADMA_BANK)
    a.lda_zp(ZP_ARGS + 3)
    a.sta_abs(IO_ADMA_PAGES_LO)
    a.lda_imm(0)
    a.sta_abs(IO_ADMA_PAGES_HI)
    a.lda_zp(ZP_ARGS + 1)
    a.ldx_zp(ZP_ARGS + 5)
    a.cpx_imm(1)
    a.bne("WAV_DMA_GO")
    a.ora_imm(0x80) # Bit 7 = Hardware Loop Mode!
    a.label("WAV_DMA_GO")
    a.sta_abs(IO_ADMA_CTRL)
    a.cpx_imm(2)
    a.bne("WAV_RTS")
    a.label("WAV_WAIT_DMA")
    a.lda_abs(IO_STATUS)
    a.bmi("WAV_PL_STOP")
    a.lda_abs(IO_ADMA_CTRL)
    a.bmi("WAV_WAIT_DMA")
    a.rts()
    a.label("WAV_PL_STOP")
    a.lda_imm(0)
    a.sta_abs(IO_ADMA_CTRL)
    a.lda_zp(ZP_RUN)
    a.bne("WAV_RTS")
    a.lda_abs(IO_STATUS)
    a.bpl("WAV_RTS")
    a.lda_abs(IO_TERM)
    a.label("WAV_RTS")
    a.rts()

    rom, ext_rom = a.assemble()

    # Hard ABI assertion for all pre-compiled 6502 MicroSD apps (MC, CALC, WRITER, SPREDIT, RFTS, BROWSER, IMPRESS, NETTERM)
    expected_abi = {
        "STMT_RUN":      0xE876,
        "SILENCE_AUDIO": 0xE8DC,
        "SD_INIT":       0xE96A,
        "DISK_READ_SEC": 0xEA67,
        "DISK_WRITE_SEC": 0xEADA,
    }
    for sym, exp_addr in expected_abi.items():
        actual = a.labels.get(sym)
        if actual != exp_addr:
            raise AssertionError(f"ROM ABI mismatch for {sym}: expected ${exp_addr:04X}, got ${actual:04X}")
    print("ROM ABI check PASSED: STMT_RUN=$E876, SILENCE_AUDIO=$E8DC, SD_INIT=$E96A, DISK_READ_SEC=$EA67, DISK_WRITE_SEC=$EADA")
    lines = [f"{b:02X}" for b in rom]
    content = "\n".join(lines) + "\n"
    for folder in (BASE_DIR, SRC_DIR):
        with open(os.path.join(folder, "minigpu_basic.hex"), "w", encoding="utf-8") as f:
            f.write(content)

    # Emit combinational LUT-ROM Verilog module for $A400 - $AFFF (0 BSRAMs!)
    v_lines = [
        "// Auto-generated by build_minigpu_basic_rom.py — $A400-$AFFF LUT-ROM Extension (0 BSRAMs)",
        "module basic_ext_rom (",
        "    input  wire [11:0] addr,",
        "    output reg  [7:0]  dout",
        ");",
        "    always @(*) begin",
        "        case (addr)",
    ]
    for idx, b in enumerate(ext_rom):
        if b != 0xEA:
            v_lines.append(f"            12'h{(idx + 0x400):03X}: dout = 8'h{b:02X};")
    v_lines += [
        "            default: dout = 8'hEA;",
        "        endcase",
        "    end",
        "endmodule",
        "",
    ]
    with open(os.path.join(SRC_DIR, "basic_ext_rom.v"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(v_lines))
    print("Wrote minigpu_basic.hex and src/basic_ext_rom.v successfully!")

if __name__ == "__main__":
    build_rom()
