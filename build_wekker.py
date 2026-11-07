import os

# ==============================================================================
# 6502 Mini-Assembler for WEKKER.asm v5.0 (SD-Kaart .WAV PCM Audio Wekker)
#   - Speelt 8 echte 8-bit PCM .WAV bestanden (elk 32 KB / 64 sectoren)
#     rechtstreeks vanaf de MicroSD-kaart ($2010..$220F) via SDRAM Bank 32..39
#     ($A012..$A015) en de Hardware PCM DAC ($A016 / $A017):
#       1: BOERDERIJ WEI (.WAV)   - Haan, Melkkoe, Schaap & Eend ($2190, 8 kHz)
#       2: OCHTENDVOGELS (.WAV)   - Roodborstje, Nachtegaal, Koekoek ($21D0, 8 kHz)
#       3: TANG NANO STEM (.WAV)  - Welkomststem + Akkoord ($2010, 8 kHz)
#       4: FUNK DRUMBEAT (.WAV)   - Kick, Snare, Hi-Hat & Slap Bass ($2050, 8 kHz)
#       5: WINDOWS TADA! (.WAV)   - Klassieke Orkest Fanfare ($2090, 11.025 kHz)
#       6: CYBER ACID BASS (.WAV) - TB-303 Acid Synth & Beats ($20D0, 8 kHz)
#       7: STUDIO CHIMES (.WAV)   - Kristallen Carillon Belletjes ($2110, 11.025 kHz)
#       8: SPACE RADIO FM (.WAV)  - Sci-Fi Telemetry & Theremin ($2150, 8 kHz)
#   - Volledige Toetsenbord + Hardware Muis ($A00C..$A00F) besturing
#   - Top-Right Wekker-Icoon naast de 720p Hardware Klok
# ==============================================================================

code = bytearray()
labels = {}
fixups = []  # (offset, label_name, mode) where mode is 'abs', 'rel', 'lo', 'hi'

def org(addr):
    global start_addr
    start_addr = addr

def pc():
    return start_addr + len(code)

def label(name):
    labels[name] = pc()

def emit(*bytes_list):
    for b in bytes_list:
        code.append(b & 0xFF)

def emit_word(w):
    emit(w & 0xFF, (w >> 8) & 0xFF)

def emit_abs(opcode, target):
    emit(opcode)
    if isinstance(target, str):
        fixups.append((len(code), target, 'abs'))
        emit_word(0x0000)
    else:
        emit_word(target)

def emit_lo(opcode, target):
    emit(opcode)
    fixups.append((len(code), target, 'lo'))
    emit(0x00)

def emit_hi(opcode, target):
    emit(opcode)
    fixups.append((len(code), target, 'hi'))
    emit(0x00)

def emit_byte_lo(target):
    fixups.append((len(code), target, 'lo'))
    emit(0x00)

def emit_byte_hi(target):
    fixups.append((len(code), target, 'hi'))
    emit(0x00)

def emit_rel(opcode, target):
    emit(opcode)
    if isinstance(target, str):
        fixups.append((len(code), target, 'rel'))
        emit(0x00)
    else:
        offset = target - (pc() + 1)
        assert -128 <= offset <= 127, f"Branch out of range: {offset}"
        emit(offset & 0xFF)

# 6502 Instructions
def lda_imm(v): emit(0xA9, v)
def lda_zp(a):  emit(0xA5, a)
def lda_zpx(a): emit(0xB5, a)
def lda_abs(a): emit_abs(0xAD, a)
def lda_abx(a): emit_abs(0xBD, a)
def lda_aby(a): emit_abs(0xB9, a)
def lda_iny(a): emit(0xB1, a)
def sta_zp(a):  emit(0x85, a)
def sta_zpx(a): emit(0x95, a)
def sta_abs(a): emit_abs(0x8D, a)
def sta_abx(a): emit_abs(0x9D, a)

def ldx_imm(v): emit(0xA2, v)
def ldx_zp(a):  emit(0xA6, a)
def stx_zp(a):  emit(0x86, a)
def stx_abs(a): emit_abs(0x8E, a)
def inx():      emit(0xE8)
def dex():      emit(0xCA)
def cpx_imm(v): emit(0xE0, v)
def cpx_zp(a):  emit(0xE4, a)

def ldy_imm(v): emit(0xA0, v)
def ldy_zp(a):  emit(0xA4, a)
def sty_zp(a):  emit(0x84, a)
def sty_abs(a): emit_abs(0x8C, a)
def iny():      emit(0xC8)
def dey():      emit(0x88)
def cpy_imm(v): emit(0xC0, v)
def cpy_zp(a):  emit(0xC4, a)

def cmp_imm(v): emit(0xC9, v)
def cmp_zp(a):  emit(0xC5, a)
def cmp_abs(a): emit_abs(0xCD, a)

def and_imm(v): emit(0x29, v)
def ora_imm(v): emit(0x09, v)
def ora_zp(a):  emit(0x05, a)
def eor_imm(v): emit(0x49, v)

def clc():      emit(0x18)
def sec():      emit(0x38)
def adc_imm(v): emit(0x69, v)
def adc_zp(a):  emit(0x65, a)
def adc_abx(a): emit_abs(0x7D, a)
def sbc_imm(v): emit(0xE9, v)
def sbc_zp(a):  emit(0xE5, a)
def sbc_abx(a): emit_abs(0xFD, a)

def asl_a():    emit(0x0A)
def lsr_a():    emit(0x4A)
def ror_a():    emit(0x6A)
def lsr_zp(a):  emit(0x46, a)

def inc_zp(a):  emit(0xE6, a)
def dec_zp(a):  emit(0xC6, a)

def pha():      emit(0x48)
def pla():      emit(0x68)
def tax():      emit(0xAA)
def txa():      emit(0x8A)
def tay():      emit(0xA8)
def tya():      emit(0x98)
def rts():      emit(0x60)

def jsr(target): emit_abs(0x20, target)
def jmp(target): emit_abs(0x4C, target)

def beq(target): emit_rel(0xF0, target)
def bne(target): emit_rel(0xD0, target)
def bcc(target): emit_rel(0x90, target)
def bcs(target): emit_rel(0xB0, target)
def bmi(target): emit_rel(0x30, target)
def bpl(target): emit_rel(0x10, target)

def jeq(target):
    emit(0xD0, 0x03)
    jmp(target)

def jne(target):
    emit(0xF0, 0x03)
    jmp(target)

# Zero Page Map ($50..$7A)
ZP_ALARM_H    = 0x50  # Alarm Hour (0..23)
ZP_ALARM_M    = 0x51  # Alarm Minute (0..59)
ZP_ARMED      = 0x52  # 0=UIT, 1=AAN
ZP_RINGING    = 0x53  # 0=Stil, 1=Rinkelt!
ZP_MELODY     = 0x54  # 0..7 (8 SD-Kaart .WAV Wekker-Geluiden)
ZP_CURSOR     = 0x55  # 0=H1, 1=H0, 2=M1, 3=M0
ZP_UI_MODE    = 0x56  # 1=Instel-venster open, 0=Venster gesloten (alleen icoon rechtsboven)
ZP_DIRTY      = 0x57  # 1=GPU hertekenen nodig
ZP_FLASH_CNT  = 0x58  # Teller voor knipperende alarm-banner
ZP_FLASH      = 0x59  # Knipper-status tijdens alarm (0/1)
ZP_DISMISSED  = 0x5A  # Voorkomt her-trigger in dezelfde minuut
ZP_LAST_M     = 0x5B  # Vorige RTC minuut voor dismiss-reset
ZP_SEG_MASK   = 0x5C  # 7-segment bitmasker tijdens tekenen
ZP_X_LO       = 0x5D
ZP_X_HI       = 0x5E
ZP_Y_LO       = 0x5F
ZP_COLOR      = 0x60
ZP_SEG_IDX    = 0x61
ZP_VAL        = 0x62
ZP_W_LO       = 0x63
ZP_H_LO       = 0x64
ZP_H_TENS     = 0x65  # $65..$68: 4 consecutive alarm digits (H1, H0, M1, M0)
ZP_H_ONES     = 0x66
ZP_M_TENS     = 0x67
ZP_M_ONES     = 0x68
ZP_STR_LO     = 0x69
ZP_STR_HI     = 0x6A
ZP_TEMP       = 0x6B
ZP_MX_LO      = 0x6C
ZP_INIT_MAGIC = 0x6D
ZP_MX_HI      = 0x6E
ZP_MY_LO      = 0x6F

# SD-Card .WAV & PCM Engine Zero-Page ($70..$7A)
ZP_IS_ACT     = 0x70  # 1 = .WAV speelt nu af (preview of alarm), 0 = stil
ZP_PLAY_PAGE  = 0x71  # Huidige 256-sample pagina (0..127) in SDRAM Bank (32 + ZP_MELODY)
ZP_LOAD_PAGE  = 0x72  # Pagina-teller (0..127) tijdens laden van SD-kaart naar SDRAM
ZP_LOAD_SEC   = 0x73  # Sector-teller (64..1) tijdens laden van SD-kaart
ZP_CUR_RATE   = 0x74  # $A017 sample-rate code (1 = 8000 Hz, 2 = 11025 Hz)
ZP_EFF_W_LO   = 0x75  # Voor korte UI-beeps (CMD 16)
ZP_EFF_W_HI   = 0x76
ZP_EFF_VOL    = 0x77
ZP_WAV_PAGE   = 0x78  # 0 = SD-Kaart .WAV Pagina 1 (1..8), 8 = Pagina 2 (9..16)
ZP_CUR_ITEM   = 0x79  # Tijdelijke SD-kaart .WAV index (0..15) tijdens tekenen

# ROM SD-Card ABI & BSRAM Buffers
ZP_DST          = 0x1C   # ROM_READ_SEC destination pointer ($1C..$1D)
DISK_FORCE_RD   = 0x0491
DISK_SEC_LO     = 0x0496
DISK_SEC_HI     = 0x0497
ROM_SD_INIT     = 0xE96A
ROM_READ_SEC    = 0xEA67

WAV_DIR_BUF     = 0x7A00 # 512B SD-Kaart .WAV Directory buffer ($7A00..$7BFF, 16 files!)
SEC_TMP_BUF     = 0x0600 # 512B sector buffer in fast internal BSRAM ($0600..$07FF)
BSRAM_PLAY_PAGE = 0x02A0 # 15B BSRAM 256-sample PCM playback loop ($02A0..$02AE)
BSRAM_COPY_SEC  = 0x02AF # 43B BSRAM 512B sector -> SDRAM Bank copy routine ($02AF..$02D9)

# Hardware I/O Registers
IO_STATUS     = 0xA000  # Bit 0 = kbd_ready, Bit 7 = ESC/Ctrl+C
IO_TERM       = 0xA001  # Read = kbd_data, Write = terminal char (12 = CLS)
IO_TIMER      = 0xA003  # 100 Hz hardware timer ticks (1 tick = 10 ms)
IO_MODE       = 0xA006  # 0=MODE1, 1=MODE0, 2=720p Panorama(no text), 3=Boerderij, 6=Toggle
IO_RTC_H      = 0xA007  # Hardware RTC Hour (0..23)
IO_RTC_M      = 0xA008  # Hardware RTC Minute (0..59)
IO_RTC_S      = 0xA009  # Hardware RTC Second (0..59)
IO_INST       = 0xA00A  # 16-Bit Stereo Sound Card Instrument
IO_FX         = 0xA00B  # Sound FX/ADSR
IO_MOUSE_X_LO = 0xA00C  # Hardware Mouse X[7:0] (0..639)
IO_MOUSE_X_HI = 0xA00D  # Hardware Mouse X[9:8]
IO_MOUSE_Y_LO = 0xA00E  # Hardware Mouse Y[7:0] (0..359)
IO_MOUSE_STAT = 0xA00F  # Bit 3 = click_latch, Bit 1 = LMB, Bit 0 = Y[8]
IO_RD_LO      = 0xA012  # SDRAM Ramdisk byte offset (0..255)
IO_RD_HI      = 0xA013  # SDRAM Ramdisk page index (0..255)
IO_RD_DATA    = 0xA014  # SDRAM Ramdisk read/write data byte
IO_RD_BANK    = 0xA015  # SDRAM 64KB Bank select (Banks 32..39 = 8 .WAV tracks)
IO_PCM_DAC    = 0xA016  # 8-bit unsigned PCM DAC met hardware sample wait-state
IO_PCM_RATE   = 0xA017  # Sample Rate: 0=Off, 1=8000 Hz, 2=11025 Hz, 3=16000 Hz, 4=22050 Hz
IO_GPU        = 0xA020  # MiniGPU & Audio Command Stream Port

# ==============================================================================
# 8 MicroSD .WAV Wekker-Geluiden (Sector $2010..$220F, elk 64 sectoren = 32 KB)
# ==============================================================================
SOUNDS = [
    {
        "label": "1: BOERDERIJ WEI (.WAV)",
        "badge": ord('B'),
        "sec":   0x2190,
        "rate":  1,  # 8000 Hz
    },
    {
        "label": "2: OCHTENDVOGELS (.WAV)",
        "badge": ord('V'),
        "sec":   0x21D0,
        "rate":  1,  # 8000 Hz
    },
    {
        "label": "3: TANG NANO STEM (.WAV)",
        "badge": ord('S'),
        "sec":   0x2010,
        "rate":  1,  # 8000 Hz
    },
    {
        "label": "4: FUNK DRUMBEAT (.WAV)",
        "badge": ord('F'),
        "sec":   0x2050,
        "rate":  1,  # 8000 Hz
    },
    {
        "label": "5: WINDOWS TADA! (.WAV)",
        "badge": ord('T'),
        "sec":   0x2090,
        "rate":  2,  # 11025 Hz
    },
    {
        "label": "6: CYBER ACID BASS (.WAV)",
        "badge": ord('A'),
        "sec":   0x20D0,
        "rate":  1,  # 8000 Hz
    },
    {
        "label": "7: STUDIO CHIMES (.WAV)",
        "badge": ord('C'),
        "sec":   0x2110,
        "rate":  2,  # 11025 Hz
    },
    {
        "label": "8: SPACE RADIO FM (.WAV)",
        "badge": ord('R'),
        "sec":   0x2150,
        "rate":  1,  # 8000 Hz
    },
]

gpu_blobs = []

def make_rect_bytes(x, y, w, h, color):
    return (
        2,
        x & 0xFF, (x >> 8) & 0xFF,
        y & 0xFF, (y >> 8) & 0xFF,
        w & 0xFF, (w >> 8) & 0xFF,
        h & 0xFF, (h >> 8) & 0xFF,
        color & 0xFF
    )

def make_disk_bytes(x, y, r, color):
    return (
        5,
        x & 0xFF, (x >> 8) & 0xFF,
        y & 0xFF, (y >> 8) & 0xFF,
        r & 0xFF, (r >> 8) & 0xFF,
        0, 0,
        color & 0xFF
    )

def gpu_stream(shapes):
    lbl = f"GPU_BLOB_{len(gpu_blobs)}"
    flat = []
    for sh in shapes:
        flat.extend(sh)
    assert len(flat) <= 250
    gpu_blobs.append((lbl, tuple(flat)))
    emit_lo(0xA2, lbl)
    emit_hi(0xA0, lbl)
    lda_imm(len(flat))
    jsr("GPU_SEND_BLOB")

def gpu_target(buf_id):
    lda_imm(12)
    sta_abs(IO_GPU)
    lda_imm(buf_id)
    sta_abs(IO_GPU)

def gpu_clear(color):
    lda_imm(1)
    sta_abs(IO_GPU)
    lda_imm(color)
    sta_abs(IO_GPU)

def gpu_flip():
    lda_imm(11)
    sta_abs(IO_GPU)

def draw_str_at(x, y, color, str_label):
    lda_imm(x & 0xFF)
    sta_zp(ZP_X_LO)
    lda_imm((x >> 8) & 0xFF)
    sta_zp(ZP_X_HI)
    lda_imm(y & 0xFF)
    sta_zp(ZP_Y_LO)
    lda_imm(color)
    sta_zp(ZP_COLOR)
    emit_lo(0xA2, str_label)
    emit_hi(0xA0, str_label)
    jsr("DRAW_STR_SUB")

org(0x8000)

# ==============================================================================
# ENTRY POINT ($8000)
# ==============================================================================
label("START")
# Install 58-byte BSRAM Audio & Sector Engine at $02A0..$02D9
ldx_imm(57)
label("INIT_BSRAM_LP")
lda_abx("BSRAM_ENGINE_SRC")
sta_abx(BSRAM_PLAY_PAGE)
dex()
bpl("INIT_BSRAM_LP")

lda_imm(12)
sta_abs(IO_TERM)
lda_abs(IO_TERM)
lda_abs(IO_MOUSE_STAT)

lda_imm(7)
sta_abs(IO_FX)
jsr("SILENCE_AUDIO")

# Select 720p Boerderij Theme ($A006 = 3) and hide BASIC text ($A006 = 2)
lda_imm(3)
sta_abs(IO_MODE)
lda_imm(2)
sta_abs(IO_MODE)

ldx_imm(2)
jsr("DELAY_10MS_X")

lda_zp(ZP_INIT_MAGIC)
cmp_imm(0xA9)
beq("INIT_REOPEN")

lda_imm(0xA9)
sta_zp(ZP_INIT_MAGIC)
lda_imm(7)            # Default 07:30
sta_zp(ZP_ALARM_H)
lda_imm(30)
sta_zp(ZP_ALARM_M)
lda_imm(1)            # Default Armed = AAN
sta_zp(ZP_ARMED)
lda_imm(0)            # Default Sound = 0 (eerste .WAV van SD-kaart)
sta_zp(ZP_MELODY)
sta_zp(ZP_WAV_PAGE)

label("INIT_REOPEN")
# Lees altijd de actuele .WAV-bestandslijst (16 bestanden) van SD-Kaart Sector $2000!
jsr("READ_SD_WAV_DIR")
lda_zp(ZP_MELODY)
and_imm(0x08)
sta_zp(ZP_WAV_PAGE)
lda_imm(0)
sta_zp(ZP_RINGING)
sta_zp(ZP_CURSOR)
sta_zp(ZP_FLASH_CNT)
sta_zp(ZP_FLASH)
sta_zp(ZP_DISMISSED)
lda_abs(IO_RTC_M)
sta_zp(ZP_LAST_M)

lda_imm(1)
sta_zp(ZP_UI_MODE)
sta_zp(ZP_DIRTY)
jsr("DRAW_SCREEN")
lda_imm(0)
sta_zp(ZP_DIRTY)
lda_zp(ZP_MELODY)
jsr("START_SOUND_A")

# ==============================================================================
# MAIN LOOP: Streams 256-sample .WAV pages when active, or waits 10ms when idle
# ==============================================================================
label("MAIN_LOOP")
lda_zp(ZP_DIRTY)
beq("SKIP_DRAW")
jsr("DRAW_SCREEN")
lda_imm(0)
sta_zp(ZP_DIRTY)

label("SKIP_DRAW")
lda_abs(IO_STATUS)
and_imm(0x01)
beq("CHECK_MOUSE")
lda_abs(IO_TERM)
jmp("HANDLE_KEY")

label("CHECK_MOUSE")
lda_abs(IO_MOUSE_STAT)
tax()
and_imm(0x08)
beq("NO_INPUT_YET")
jsr("HANDLE_MOUSE_CLICK")
jmp("MAIN_LOOP")

label("NO_INPUT_YET")
lda_zp(ZP_IS_ACT)
beq("ML_IDLE_WAIT")

# --- Stream 1 page (256 samples) from SDRAM Bank (32 + ZP_MELODY) via $A016 ---
lda_zp(ZP_MELODY)
clc()
adc_imm(32)
sta_abs(IO_RD_BANK)
lda_zp(ZP_PLAY_PAGE)
sta_abs(IO_RD_HI)
lda_zp(ZP_CUR_RATE)
sta_abs(IO_PCM_RATE)
jsr(BSRAM_PLAY_PAGE)

inc_zp(ZP_PLAY_PAGE)
lda_zp(ZP_PLAY_PAGE)
cmp_imm(128)
bcc("ML_CHECK_RTC")

# End of 32 KB (128 pages) .WAV track reached!
lda_imm(0)
sta_zp(ZP_PLAY_PAGE)
lda_zp(ZP_RINGING)
bne("ML_WAV_RING_LOOP")
jsr("SILENCE_AUDIO")
jmp("ML_CHECK_RTC")

label("ML_WAV_RING_LOOP")
# Toggle flash banner at loop boundary while alarm is ringing
lda_zp(ZP_FLASH)
eor_imm(0x01)
sta_zp(ZP_FLASH)
lda_imm(1)
sta_zp(ZP_DIRTY)
jmp("ML_CHECK_RTC")

label("ML_IDLE_WAIT")
jsr("DELAY_10MS")

label("ML_CHECK_RTC")
lda_abs(IO_RTC_M)
cmp_zp(ZP_LAST_M)
beq("SAME_MINUTE")
sta_zp(ZP_LAST_M)
lda_imm(0)
sta_zp(ZP_DISMISSED)
label("SAME_MINUTE")

lda_zp(ZP_RINGING)
bne("ML_TO_TOP")

label("CHECK_ALARM_TRIGGER")
lda_zp(ZP_ARMED)
beq("ML_TO_TOP")
lda_zp(ZP_DISMISSED)
bne("ML_TO_TOP")

lda_abs(IO_RTC_H)
cmp_zp(ZP_ALARM_H)
bne("ML_TO_TOP")
lda_abs(IO_RTC_M)
cmp_zp(ZP_ALARM_M)
bne("ML_TO_TOP")
lda_abs(IO_RTC_S)
cmp_imm(2)
bcs("ML_TO_TOP")

jmp("TRIGGER_TEST_ALARM")

label("ML_TO_TOP")
jmp("MAIN_LOOP")

# ==============================================================================
# HARDWARE MOUSE CLICK HANDLER ($A00C..$A00F)
# ==============================================================================
label("HANDLE_MOUSE_CLICK")
txa()
and_imm(0x01)
sta_zp(ZP_TEMP)
lda_abs(IO_MOUSE_X_LO)
sta_zp(ZP_MX_LO)
lda_abs(IO_MOUSE_X_HI)
sta_zp(ZP_MX_HI)
lda_abs(IO_MOUSE_Y_LO)
sta_zp(ZP_MY_LO)

lda_zp(ZP_RINGING)
beq("MC_NOT_RINGING")
pla()
pla()
jmp("DO_STOP_ALARM")

label("MC_NOT_RINGING")
lda_zp(ZP_UI_MODE)
bne("MC_IN_WIN")
pla()
pla()
jmp("OPEN_SETUP_WIN")

label("MC_IN_WIN")
lda_zp(ZP_TEMP)
beq("MC_Y_LOW")
label("MC_EARLY_RET")
rts()

label("MC_Y_LOW")
lda_zp(ZP_MY_LO)
cmp_imm(98)
bcc("MC_EARLY_RET")
cmp_imm(140)
bcs("MC_CHK_SOUNDS")

lda_zp(ZP_MX_HI)
bne("MC_TIME_HI1")
lda_imm(0)
jmp("MC_INC_DIG_A")

label("MC_TIME_HI1")
lda_zp(ZP_MX_LO)
cmp_imm(304 - 256)
bcc("MC_T_D01")
cmp_imm(342 - 256)
bcc("MC_T_D2")
lda_imm(3)
jmp("MC_INC_DIG_A")
label("MC_T_D2")
lda_imm(2)
jmp("MC_INC_DIG_A")
label("MC_T_D01")
cmp_imm(270 - 256)
bcc("MC_T_D0")
lda_imm(1)
jmp("MC_INC_DIG_A")
label("MC_T_D0")
lda_imm(0)

label("MC_INC_DIG_A")
sta_zp(ZP_CURSOR)
pla()
pla()
jmp("DO_INC_FIELD")

label("MC_CHK_SOUNDS")
cmp_imm(140)
bcc("MC_EARLY_RET")
cmp_imm(156)
bcs("MC_CHK_SND_ROWS")
# Klik op [P: WISSEL SD-KAART .WAV PAGINA 1/2] balk (Y = 140..155)!
pla()
pla()
lda_zp(ZP_MELODY)
eor_imm(0x08)
jmp("SELECT_SOUND")

label("MC_CHK_SND_ROWS")
cmp_imm(228)
bcs("MC_CHK_BTNS")

ldx_imm(0)
cmp_imm(174)
bcc("MC_GOT_ROW")
ldx_imm(1)
cmp_imm(192)
bcc("MC_GOT_ROW")
ldx_imm(2)
cmp_imm(210)
bcc("MC_GOT_ROW")
ldx_imm(3)

label("MC_GOT_ROW")
lda_zp(ZP_MX_HI)
beq("MC_LEFT_COL")
lda_zp(ZP_MX_LO)
cmp_imm(320 - 256)
bcc("MC_LEFT_COL")
txa()
clc()
adc_imm(4)
tax()
label("MC_LEFT_COL")
txa()
ora_zp(ZP_WAV_PAGE)
pla()
pla()
jmp("SELECT_SOUND")

label("MC_CHK_BTNS")
cmp_imm(234)
bcc("MC_EARLY_RET")
pla()
pla()
lda_zp(ZP_MX_HI)
beq("MC_BTN_START")
lda_zp(ZP_MX_LO)
cmp_imm(344 - 256)
bcc("MC_BTN_START")
cmp_imm(448 - 256)
bcc("MC_BTN_TEST")
jmp("DISARM_AND_CLOSE")
label("MC_BTN_TEST")
jmp("TRIGGER_TEST_ALARM")
label("MC_BTN_START")
jmp("ARM_AND_CLOSE")

# ==============================================================================
# KEYBOARD HANDLER
# ==============================================================================
label("HANDLE_KEY")
cmp_imm(0x61)
bcc("NOT_LOWER")
cmp_imm(0x7B)
bcs("NOT_LOWER")
sec()
sbc_imm(0x20)
label("NOT_LOWER")
sta_zp(ZP_TEMP)

cmp_imm(ord('Q'))
beq("DO_EXIT")
cmp_imm(0x1B)
bne("NOT_EXIT_KEY")

label("DO_EXIT")
jsr("SILENCE_AUDIO")
lda_imm(8)
sta_abs(IO_INST)
gpu_target(1)
gpu_clear(0xE3)
lda_imm(1)
sta_abs(IO_MODE)
rts()

label("NOT_EXIT_KEY")
cmp_imm(ord('B'))
bne("NOT_KEY_B")
lda_imm(6)
sta_abs(IO_MODE)
jmp("MAIN_LOOP")

label("NOT_KEY_B")
lda_zp(ZP_RINGING)
beq("NOT_RINGING_KEYS")

lda_zp(ZP_TEMP)
cmp_imm(ord('Z'))
beq("DO_SNOOZE")
cmp_imm(ord(' '))
beq("DO_STOP_ALARM")
cmp_imm(0x0D)
beq("DO_STOP_ALARM")
cmp_imm(0x0A)
beq("DO_STOP_ALARM")
cmp_imm(ord('X'))
beq("DO_STOP_ALARM")
jmp("MAIN_LOOP")

label("DO_STOP_ALARM")
lda_imm(0)
sta_zp(ZP_RINGING)
jsr("SILENCE_AUDIO")
lda_imm(1)
sta_zp(ZP_DISMISSED)
lda_imm(0)
sta_zp(ZP_UI_MODE)
lda_imm(1)
sta_zp(ZP_DIRTY)
jmp("MAIN_LOOP")

label("DO_SNOOZE")
lda_imm(0)
sta_zp(ZP_RINGING)
jsr("SILENCE_AUDIO")
lda_zp(ZP_ALARM_M)
clc()
adc_imm(5)
cmp_imm(60)
bcc("SNOOZE_M_OK")
sec()
sbc_imm(60)
sta_zp(ZP_ALARM_M)
lda_zp(ZP_ALARM_H)
clc()
adc_imm(1)
cmp_imm(24)
bcc("SNOOZE_H_OK")
lda_imm(0)
label("SNOOZE_H_OK")
sta_zp(ZP_ALARM_H)
jmp("SNOOZE_DONE")
label("SNOOZE_M_OK")
sta_zp(ZP_ALARM_M)
label("SNOOZE_DONE")
lda_imm(1)
sta_zp(ZP_ARMED)
lda_imm(0)
sta_zp(ZP_DISMISSED)
sta_zp(ZP_UI_MODE)
lda_imm(1)
sta_zp(ZP_DIRTY)
jmp("MAIN_LOOP")

label("NOT_RINGING_KEYS")
lda_zp(ZP_UI_MODE)
bne("SETUP_WINDOW_KEYS")

lda_zp(ZP_TEMP)
cmp_imm(0x0D)
beq("OPEN_SETUP_WIN")
cmp_imm(0x0A)
beq("OPEN_SETUP_WIN")
cmp_imm(ord(' '))
beq("OPEN_SETUP_WIN")
cmp_imm(ord('I'))
beq("OPEN_SETUP_WIN")
cmp_imm(ord('T'))
beq("TRIGGER_TEST_ALARM")
jmp("MAIN_LOOP")

label("OPEN_SETUP_WIN")
lda_imm(1)
sta_zp(ZP_UI_MODE)
sta_zp(ZP_DIRTY)
jsr("PLAY_UI_BEEP")
jmp("MAIN_LOOP")

label("TRIGGER_TEST_ALARM")
lda_imm(1)
sta_zp(ZP_RINGING)
lda_imm(0)
sta_zp(ZP_FLASH_CNT)
sta_zp(ZP_FLASH)
jsr("DRAW_SCREEN")
lda_imm(0)
sta_zp(ZP_DIRTY)
lda_zp(ZP_MELODY)
jsr("START_SOUND_A")
jmp("MAIN_LOOP")

# ==============================================================================
# SETUP WINDOW KEYS (ZP_UI_MODE == 1)
# ==============================================================================
label("SETUP_WINDOW_KEYS")
lda_zp(ZP_TEMP)

cmp_imm(0x0D)
beq("ARM_AND_CLOSE")
cmp_imm(0x0A)
beq("ARM_AND_CLOSE")
cmp_imm(ord(' '))
beq("ARM_AND_CLOSE")

cmp_imm(ord('X'))
bne("CHK_TEST_IN_WIN")
label("DISARM_AND_CLOSE")
jsr("SILENCE_AUDIO")
lda_imm(0)
sta_zp(ZP_ARMED)
sta_zp(ZP_UI_MODE)
lda_imm(1)
sta_zp(ZP_DIRTY)
jsr("PLAY_UI_BEEP")
jmp("MAIN_LOOP")

label("ARM_AND_CLOSE")
jsr("SILENCE_AUDIO")
lda_imm(1)
sta_zp(ZP_ARMED)
lda_imm(0)
sta_zp(ZP_DISMISSED)
sta_zp(ZP_UI_MODE)
lda_imm(1)
sta_zp(ZP_DIRTY)
jsr("DRAW_SCREEN")
lda_imm(0)
sta_zp(ZP_DIRTY)
jsr("PLAY_CONFIRM_CHIME")
jmp("MAIN_LOOP")

label("CHK_TEST_IN_WIN")
cmp_imm(ord('T'))
beq("TRIGGER_TEST_ALARM")

# Sound Selection: '1'..'8' (op huidige SD-pagina), 'P' (wissel SD-pagina 1/2), 'M' (volgende van 16), 'R' (herlaad SD)
cmp_imm(ord('R'))
bne("CHK_SND_P")
jsr("READ_SD_WAV_DIR")
lda_zp(ZP_MELODY)
jmp("SELECT_SOUND")

label("CHK_SND_P")
cmp_imm(ord('P'))
bne("CHK_SND_18")
lda_zp(ZP_MELODY)
eor_imm(0x08)
jmp("SELECT_SOUND")

label("CHK_SND_18")
cmp_imm(ord('1'))
bcc("CHK_SND_M")
cmp_imm(ord('8') + 1)
bcs("CHK_SND_M")
sec()
sbc_imm(ord('1'))
ora_zp(ZP_WAV_PAGE)
jmp("SELECT_SOUND")

label("CHK_SND_M")
cmp_imm(ord('M'))
bne("CHK_NAV_KEYS")
lda_zp(ZP_MELODY)
clc()
adc_imm(1)
and_imm(0x0F)

label("SELECT_SOUND")
and_imm(0x0F)
sta_zp(ZP_MELODY)
and_imm(0x08)
sta_zp(ZP_WAV_PAGE)
jsr("DRAW_SCREEN")
lda_imm(0)
sta_zp(ZP_DIRTY)
lda_zp(ZP_MELODY)
jsr("START_SOUND_A")
jmp("MAIN_LOOP")

label("CHK_NAV_KEYS")
cmp_imm(ord('D'))
beq("CURSOR_NEXT")
cmp_imm(0x09)
beq("CURSOR_NEXT")
cmp_imm(ord('A'))
beq("CURSOR_PREV")
cmp_imm(0x08)
beq("CURSOR_PREV")
jmp("CHK_PLUS_MINUS")

label("CURSOR_NEXT")
lda_zp(ZP_CURSOR)
clc()
adc_imm(1)
and_imm(0x03)
sta_zp(ZP_CURSOR)
lda_imm(1)
sta_zp(ZP_DIRTY)
jmp("MAIN_LOOP")

label("CURSOR_PREV")
lda_zp(ZP_CURSOR)
sec()
sbc_imm(1)
and_imm(0x03)
sta_zp(ZP_CURSOR)
lda_imm(1)
sta_zp(ZP_DIRTY)
jmp("MAIN_LOOP")

# Compact Table-Driven Digit Edit (W/+/= Increment, S/- Decrement, 0..9 Direct Entry)
label("CHK_PLUS_MINUS")
cmp_imm(ord('W'))
beq("DO_INC_FIELD")
cmp_imm(ord('+'))
beq("DO_INC_FIELD")
cmp_imm(ord('='))
beq("DO_INC_FIELD")
cmp_imm(ord('S'))
beq("DO_DEC_FIELD")
cmp_imm(ord('-'))
beq("DO_DEC_FIELD")
jmp("CHK_DIGIT_ENTRY")

# Return max_plus_1 for digit X=ZP_CURSOR in ZP_VAL (3, 10/4, 6, 10)
label("PREP_DIGIT_EDIT")
jsr("SPLIT_ALARM_DIGITS")
ldx_zp(ZP_CURSOR)
lda_abx("DIG_MAX_TBL")
cpx_imm(1)
bne("PDE_OK")
ldy_zp(ZP_H_TENS)
cpy_imm(2)
bne("PDE_OK")
lda_imm(4)
label("PDE_OK")
sta_zp(ZP_VAL)
rts()

label("DO_INC_FIELD")
jsr("PREP_DIGIT_EDIT")
lda_zpx(ZP_H_TENS)
clc()
adc_imm(1)
cmp_zp(ZP_VAL)
bcc("DIF_ST")
lda_imm(0)
label("DIF_ST")
sta_zpx(ZP_H_TENS)
jmp("REBUILD_HHMM")

label("DO_DEC_FIELD")
jsr("PREP_DIGIT_EDIT")
lda_zpx(ZP_H_TENS)
bne("DDF_SUB")
lda_zp(ZP_VAL)
label("DDF_SUB")
sec()
sbc_imm(1)
sta_zpx(ZP_H_TENS)
jmp("REBUILD_HHMM")

label("CHK_DIGIT_ENTRY")
cmp_imm(ord('0'))
bcc("KEY_IGNORED")
cmp_imm(ord('9') + 1)
bcs("KEY_IGNORED")
sec()
sbc_imm(ord('0'))
sta_zp(ZP_TEMP)
jsr("PREP_DIGIT_EDIT")
lda_zp(ZP_TEMP)
cmp_zp(ZP_VAL)
bcs("KEY_IGNORED")
sta_zpx(ZP_H_TENS)
lda_zp(ZP_CURSOR)
clc()
adc_imm(1)
and_imm(0x03)
sta_zp(ZP_CURSOR)

label("REBUILD_HHMM")
# Clamp H_ONES to 3 if H_TENS == 2
lda_zp(ZP_H_TENS)
cmp_imm(2)
bne("RB_H_OK")
lda_zp(ZP_H_ONES)
cmp_imm(4)
bcc("RB_H_OK")
lda_imm(3)
sta_zp(ZP_H_ONES)
label("RB_H_OK")
lda_zp(ZP_H_TENS)
jsr("MUL10")
clc()
adc_zp(ZP_H_ONES)
sta_zp(ZP_ALARM_H)
lda_zp(ZP_M_TENS)
jsr("MUL10")
clc()
adc_zp(ZP_M_ONES)
sta_zp(ZP_ALARM_M)

lda_imm(0)
sta_zp(ZP_DISMISSED)
lda_imm(1)
sta_zp(ZP_DIRTY)
jsr("PLAY_UI_BEEP")
label("KEY_IGNORED")
jmp("MAIN_LOOP")

# ==============================================================================
# SD-CARD .WAV DIRECTORY READER ($2000 -> $7A00) & PCM DAC ENGINE ($A012..$A017)
# ==============================================================================
label("READ_SD_WAV_DIR")
ldx_imm(15)
lda_imm(0)
label("CLR_CACHE_LP")
sta_abx("TRK_CACHED")
dex()
bpl("CLR_CACHE_LP")

lda_imm(0)
sta_abs(DISK_FORCE_RD)
jsr(ROM_SD_INIT)
lda_imm(0x00)
sta_abs(DISK_SEC_LO)
lda_imm(0x20)
sta_abs(DISK_SEC_HI)
lda_imm(WAV_DIR_BUF & 0xFF)
sta_zp(ZP_DST)
lda_imm((WAV_DIR_BUF >> 8) & 0xFF)
sta_zp(ZP_DST + 1)
jmp(ROM_READ_SEC)

# Input: A = track index (0..15)
# Output: ZP_STR_LO / ZP_STR_HI = $7A00 + A * 32
label("GET_WAV_DIR_PTR")
ldy_imm(0x7A)
cmp_imm(8)
bcc("GWDP_LOW8")
ldy_imm(0x7B)
and_imm(0x07)
label("GWDP_LOW8")
asl_a()
asl_a()
asl_a()
asl_a()
asl_a()
sta_zp(ZP_STR_LO)
sty_zp(ZP_STR_HI)
rts()

label("START_SOUND_A")
and_imm(0x0F)
sta_zp(ZP_MELODY)
and_imm(0x08)
sta_zp(ZP_WAV_PAGE)
jsr("SILENCE_AUDIO")

lda_zp(ZP_MELODY)
jsr("GET_WAV_DIR_PTR")
ldy_imm(24)
lda_iny(ZP_STR_LO)
bne("SSA_RATE_OK")
lda_imm(1)
label("SSA_RATE_OK")
sta_zp(ZP_CUR_RATE)

ldx_zp(ZP_MELODY)
lda_abx("TRK_CACHED")
bne("SSA_CACHED")

# Load 64 sectors (32 KB) from MicroSD card into SDRAM Bank (32 + ZP_MELODY)
lda_imm(0)
sta_abs(DISK_FORCE_RD)
jsr(ROM_SD_INIT)

lda_zp(ZP_MELODY)
jsr("GET_WAV_DIR_PTR")
ldy_imm(20)
lda_iny(ZP_STR_LO)
sta_abs(DISK_SEC_LO)
iny()
lda_iny(ZP_STR_LO)
sta_abs(DISK_SEC_HI)

lda_zp(ZP_MELODY)
clc()
adc_imm(32)
sta_abs(IO_RD_BANK)

lda_imm(64)
sta_zp(ZP_LOAD_SEC)
lda_imm(0)
sta_zp(ZP_LOAD_PAGE)

label("SSA_LOAD_LP")
lda_imm(SEC_TMP_BUF & 0xFF)
sta_zp(ZP_DST)
lda_imm((SEC_TMP_BUF >> 8) & 0xFF)
sta_zp(ZP_DST + 1)
jsr(ROM_READ_SEC)
jsr(BSRAM_COPY_SEC)
dec_zp(ZP_LOAD_SEC)
bne("SSA_LOAD_LP")

ldx_zp(ZP_MELODY)
lda_imm(1)
sta_abx("TRK_CACHED")

label("SSA_CACHED")
lda_imm(0)
sta_zp(ZP_PLAY_PAGE)
lda_imm(1)
sta_zp(ZP_IS_ACT)
rts()

label("SEND_CH_X_EFF")
lda_imm(16)
sta_abs(IO_GPU)
stx_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
lda_zp(ZP_EFF_W_LO)
sta_abs(IO_GPU)
lda_zp(ZP_EFF_W_HI)
sta_abs(IO_GPU)
lda_zp(ZP_EFF_VOL)
sta_abs(IO_GPU)
rts()

label("SILENCE_AUDIO")
lda_imm(0)
sta_zp(ZP_IS_ACT)
sta_abs(IO_PCM_RATE)
lda_imm(128)
sta_abs(IO_PCM_DAC)
lda_imm(0)
sta_zp(ZP_EFF_VOL)
sta_zp(ZP_EFF_W_LO)
sta_zp(ZP_EFF_W_HI)
ldx_imm(0)
label("SIL_LOOP")
jsr("SEND_CH_X_EFF")
inx()
cpx_imm(4)
bcc("SIL_LOOP")
rts()

label("PLAY_UI_BEEP")
jsr("SILENCE_AUDIO")
lda_imm(0x10)
sta_abs(IO_INST)
lda_imm(784 * 65536 // 48000 & 0xFF)
sta_zp(ZP_EFF_W_LO)
lda_imm((784 * 65536 // 48000) >> 8)
sta_zp(ZP_EFF_W_HI)
lda_imm(220)
sta_zp(ZP_EFF_VOL)
ldx_imm(0)
jsr("SEND_CH_X_EFF")
ldx_imm(3)
jsr("DELAY_10MS_X")
jmp("SILENCE_AUDIO")

label("PLAY_CONFIRM_CHIME")
jsr("SILENCE_AUDIO")
lda_imm(0x16)
sta_abs(IO_INST)
lda_imm(523 * 65536 // 48000 & 0xFF)
sta_zp(ZP_EFF_W_LO)
lda_imm((523 * 65536 // 48000) >> 8)
sta_zp(ZP_EFF_W_HI)
lda_imm(240)
sta_zp(ZP_EFF_VOL)
ldx_imm(0)
jsr("SEND_CH_X_EFF")
ldx_imm(8)
jsr("DELAY_10MS_X")
lda_imm(1047 * 65536 // 48000 & 0xFF)
sta_zp(ZP_EFF_W_LO)
lda_imm((1047 * 65536 // 48000) >> 8)
sta_zp(ZP_EFF_W_HI)
ldx_imm(0)
jsr("SEND_CH_X_EFF")
ldx_imm(12)
jsr("DELAY_10MS_X")
jmp("SILENCE_AUDIO")

# ==============================================================================
# DRAW_SCREEN: Double-Buffered Render of Top-Right Wekker Badge + Setup Window
# ==============================================================================
label("DRAW_SCREEN")
gpu_target(0)
gpu_clear(0xE3)

jsr("SPLIT_ALARM_DIGITS")

lda_zp(ZP_ARMED)
bne("DO_DRAW_BADGE")
lda_zp(ZP_UI_MODE)
bne("DO_DRAW_BADGE")
jmp("AFTER_BADGE")

label("DO_DRAW_BADGE")
lda_zp(ZP_RINGING)
jeq("BADGE_NORMAL_BORDER")
lda_zp(ZP_FLASH)
jeq("BADGE_NORMAL_BORDER")
gpu_stream([
    make_rect_bytes(450, 5, 98, 19, 0xE0),
    make_rect_bytes(451, 6, 96, 17, 0x60),
])
jmp("BADGE_ICON")

label("BADGE_NORMAL_BORDER")
gpu_stream([
    make_rect_bytes(450, 5, 98, 19, 0xFC),
    make_rect_bytes(451, 6, 96, 17, 0x01),
])

label("BADGE_ICON")
gpu_stream([
    make_rect_bytes(455, 8, 3, 2, 0xFC),
    make_rect_bytes(466, 8, 3, 2, 0xFC),
    make_rect_bytes(461, 7, 2, 2, 0xFF),
    make_disk_bytes(462, 15, 5, 0xFC),
    make_disk_bytes(462, 15, 3, 0x01),
    make_rect_bytes(462, 12, 1, 4, 0xFF),
    make_rect_bytes(462, 15, 3, 1, 0xFF),
])

lda_imm(474 & 0xFF)
sta_zp(ZP_X_LO)
lda_imm(474 >> 8)
sta_zp(ZP_X_HI)
lda_imm(11)
sta_zp(ZP_Y_LO)
lda_zp(ZP_ARMED)
bne("BADGE_TIME_GREEN")
lda_imm(0x92)
jmp("BADGE_TIME_COL_SET")
label("BADGE_TIME_GREEN")
lda_imm(0x1C)
label("BADGE_TIME_COL_SET")
sta_zp(ZP_COLOR)

lda_zp(ZP_H_TENS)
clc()
adc_imm(ord('0'))
jsr("DRAW_CHAR_ADV")
lda_zp(ZP_H_ONES)
clc()
adc_imm(ord('0'))
jsr("DRAW_CHAR_ADV")
lda_imm(ord(':'))
jsr("DRAW_CHAR_ADV")
lda_zp(ZP_M_TENS)
clc()
adc_imm(ord('0'))
jsr("DRAW_CHAR_ADV")
lda_zp(ZP_M_ONES)
clc()
adc_imm(ord('0'))
jsr("DRAW_CHAR_ADV")

lda_imm(535 & 0xFF)
sta_zp(ZP_X_LO)
lda_imm(535 >> 8)
sta_zp(ZP_X_HI)
lda_imm(0xFC)
sta_zp(ZP_COLOR)
lda_zp(ZP_MELODY)
jsr("GET_WAV_DIR_PTR")
ldy_imm(6)
lda_iny(ZP_STR_LO)
jsr("DRAW_CHAR_ADV")

label("AFTER_BADGE")

# 2. If Alarm is Ringing, draw Top Alarm Banner (X=96..544, Y=28..52)
lda_zp(ZP_RINGING)
jeq("CHECK_DRAW_WIN")

lda_zp(ZP_FLASH)
jeq("RING_BANNER_GOLD")
gpu_stream([
    make_rect_bytes(96, 28, 448, 24, 0xFF),
    make_rect_bytes(98, 30, 444, 20, 0xE0),
])
draw_str_at(124, 36, 0xFF, "STR_RING_BANNER")
jmp("CHECK_DRAW_WIN")

label("RING_BANNER_GOLD")
gpu_stream([
    make_rect_bytes(96, 28, 448, 24, 0xE0),
    make_rect_bytes(98, 30, 444, 20, 0xFC),
])
draw_str_at(124, 36, 0x00, "STR_RING_BANNER")

label("CHECK_DRAW_WIN")
lda_zp(ZP_UI_MODE)
jne("DO_DRAW_SETUP_WIN")
jmp("FINISH_DRAW")

# ==============================================================================
# DRAW CENTERED SETUP WINDOW (X=80..560, Y=56..286)
# ==============================================================================
label("DO_DRAW_SETUP_WIN")
gpu_stream([
    make_rect_bytes(80,  56, 480, 230, 0xFC),
    make_rect_bytes(82,  58, 476, 226, 0x02),
    make_rect_bytes(84,  60, 472, 18,  0x0B),
    make_rect_bytes(224, 96, 192, 42,  0x1F),
    make_rect_bytes(226, 98, 188, 38,  0x01),
    make_rect_bytes(302, 108, 4,  4,   0x1F),
    make_rect_bytes(302, 118, 4,  4,   0x1F),
    make_rect_bytes(92,  236, 244, 20, 0xFC),
    make_rect_bytes(94,  238, 240, 16, 0x14),
    make_rect_bytes(344, 236, 98,  20, 0x1F),
    make_rect_bytes(346, 238, 94,  16, 0x0B),
    make_rect_bytes(450, 236, 98,  20, 0xE0),
    make_rect_bytes(452, 238, 94,  16, 0x60),
])

draw_str_at(148, 65,  0xFC, "STR_WIN_TITLE")
draw_str_at(96,  84,  0xFF, "STR_LBL_TIME")
draw_str_at(96,  144, 0xFF, "STR_LBL_SOUND")
# Teken klikbare [P = WISSEL SD-KAART .WAV LIJST 1/2] knop op (X=346, Y=140, W=202, H=14)
gpu_stream([
    make_rect_bytes(346, 140, 202, 14, 0x1F),
    make_rect_bytes(347, 141, 200, 12, 0x0B),
])
lda_zp(ZP_WAV_PAGE)
bne("DRAW_PG2_LBL")
draw_str_at(355, 143, 0xFC, "STR_SD_PAGE1")
jmp("AFTER_PG_LBL")
label("DRAW_PG2_LBL")
draw_str_at(355, 143, 0xFC, "STR_SD_PAGE2")
label("AFTER_PG_LBL")

draw_str_at(118, 242, 0xFF, "STR_BTN_START")
draw_str_at(361, 242, 0xFC, "STR_BTN_TEST")
draw_str_at(471, 242, 0xFF, "STR_BTN_STOP")
draw_str_at(96,  266, 0x9F, "STR_FOOTER_HINT")

lda_imm(102)
sta_zp(ZP_Y_LO)

ldx_imm(0)
label("DRAW_DIG_LP")
stx_zp(ZP_VAL)
lda_abx("DIGIT_X_LO")
sta_zp(ZP_X_LO)
lda_abx("DIGIT_X_HI")
sta_zp(ZP_X_HI)
lda_imm(0xFF)
cpx_zp(ZP_CURSOR)
bne("DDIG_COL_OK")
lda_imm(0xFC)
label("DDIG_COL_OK")
sta_zp(ZP_COLOR)
lda_zpx(ZP_H_TENS)
jsr("DRAW_SEG7_DIGIT")
ldx_zp(ZP_VAL)
inx()
cpx_imm(4)
bcc("DRAW_DIG_LP")

ldx_zp(ZP_CURSOR)
lda_abx("DIGIT_X_LO")
sta_zp(ZP_X_LO)
lda_abx("DIGIT_X_HI")
sta_zp(ZP_X_HI)
lda_imm(131)
sta_zp(ZP_Y_LO)
lda_imm(16)
sta_zp(ZP_W_LO)
lda_imm(3)
sta_zp(ZP_H_LO)
lda_imm(0xFC)
sta_zp(ZP_COLOR)
jsr("DRAW_RECT_ZP")

ldx_imm(0)
label("DRAW_SND_LP")
stx_zp(ZP_VAL)
txa()
ora_zp(ZP_WAV_PAGE)
sta_zp(ZP_CUR_ITEM)

lda_abx("SND_BTN_X_LO")
sta_zp(ZP_X_LO)
lda_abx("SND_BTN_X_HI")
sta_zp(ZP_X_HI)
lda_abx("SND_BTN_Y")
sta_zp(ZP_Y_LO)
lda_imm(222)
sta_zp(ZP_W_LO)
lda_imm(16)
sta_zp(ZP_H_LO)

lda_imm(0x01)
ldy_zp(ZP_CUR_ITEM)
cpy_zp(ZP_MELODY)
bne("DSND_BG_OK")
lda_imm(0x14)
label("DSND_BG_OK")
sta_zp(ZP_COLOR)
jsr("DRAW_RECT_ZP")

ldx_zp(ZP_VAL)
lda_abx("SND_BTN_X_LO")
clc()
adc_imm(6)
sta_zp(ZP_X_LO)
lda_abx("SND_BTN_X_HI")
adc_imm(0)
sta_zp(ZP_X_HI)
lda_abx("SND_BTN_Y")
clc()
adc_imm(4)
sta_zp(ZP_Y_LO)

lda_imm(0x9F)
ldy_zp(ZP_CUR_ITEM)
cpy_zp(ZP_MELODY)
bne("DSND_FG_OK")
lda_imm(0xFC)
label("DSND_FG_OK")
sta_zp(ZP_COLOR)

# Lees .WAV-bestandsnaam rechtstreeks uit de SD-Kaart Directory ($7A00 + ZP_CUR_ITEM * 32 + 4)!
lda_zp(ZP_CUR_ITEM)
jsr("GET_WAV_DIR_PTR")
clc()
lda_zp(ZP_STR_LO)
adc_imm(4)
sta_zp(ZP_STR_LO)
jsr("DRAW_STR_PTR")

ldx_zp(ZP_VAL)
inx()
cpx_imm(8)
bcc("DRAW_SND_LP")

label("FINISH_DRAW")
gpu_flip()
rts()

# ==============================================================================
# UTILITY SUBROUTINES
# ==============================================================================
label("DRAW_RECT_ZP")
lda_imm(2)
sta_abs(IO_GPU)
lda_zp(ZP_X_LO)
sta_abs(IO_GPU)
lda_zp(ZP_X_HI)
sta_abs(IO_GPU)
lda_zp(ZP_Y_LO)
sta_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
lda_zp(ZP_W_LO)
sta_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
lda_zp(ZP_H_LO)
sta_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
lda_zp(ZP_COLOR)
sta_abs(IO_GPU)
rts()

label("GPU_SEND_BLOB")
stx_zp(ZP_STR_LO)
sty_zp(ZP_STR_HI)
tax()
ldy_imm(0)
label("BLOB_LOOP")
lda_iny(ZP_STR_LO)
sta_abs(IO_GPU)
iny()
dex()
bne("BLOB_LOOP")
rts()

label("DRAW_STR_SUB")
stx_zp(ZP_STR_LO)
sty_zp(ZP_STR_HI)
label("DRAW_STR_PTR")
ldy_imm(0)
label("STR_SUB_LOOP")
lda_iny(ZP_STR_LO)
beq("STR_SUB_DONE")
sty_zp(ZP_TEMP)
jsr("DRAW_CHAR_ADV")
ldy_zp(ZP_TEMP)
iny()
jmp("STR_SUB_LOOP")
label("STR_SUB_DONE")
rts()

label("DRAW_CHAR_ADV")
pha()
lda_imm(8)
sta_abs(IO_GPU)
lda_zp(ZP_X_LO)
sta_abs(IO_GPU)
lda_zp(ZP_X_HI)
sta_abs(IO_GPU)
lda_zp(ZP_Y_LO)
sta_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
pla()
sta_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
sta_abs(IO_GPU)
sta_abs(IO_GPU)
lda_zp(ZP_COLOR)
sta_abs(IO_GPU)

clc()
lda_zp(ZP_X_LO)
adc_imm(8)
sta_zp(ZP_X_LO)
bcc("ADV_X_DONE")
inc_zp(ZP_X_HI)
label("ADV_X_DONE")
rts()

label("DRAW_SEG7_DIGIT")
tax()
lda_abx("SEG7_MASK_TBL")
sta_zp(ZP_SEG_MASK)
ldx_imm(0)
stx_zp(ZP_SEG_IDX)
label("SEG7_LOOP")
lsr_zp(ZP_SEG_MASK)
bcc("SEG7_NEXT")
ldx_zp(ZP_SEG_IDX)
lda_imm(2)
sta_abs(IO_GPU)
clc()
lda_zp(ZP_X_LO)
adc_abx("SEG7_DX_TBL")
sta_abs(IO_GPU)
lda_zp(ZP_X_HI)
adc_imm(0)
sta_abs(IO_GPU)
clc()
lda_zp(ZP_Y_LO)
adc_abx("SEG7_DY_TBL")
sta_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
lda_abx("SEG7_W_TBL")
sta_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
lda_abx("SEG7_H_TBL")
sta_abs(IO_GPU)
lda_imm(0)
sta_abs(IO_GPU)
lda_zp(ZP_COLOR)
sta_abs(IO_GPU)
label("SEG7_NEXT")
inc_zp(ZP_SEG_IDX)
lda_zp(ZP_SEG_IDX)
cmp_imm(7)
bcc("SEG7_LOOP")
rts()

label("SPLIT_ALARM_DIGITS")
lda_zp(ZP_ALARM_H)
jsr("DIV10")
sta_zp(ZP_H_ONES)
stx_zp(ZP_H_TENS)
lda_zp(ZP_ALARM_M)
jsr("DIV10")
sta_zp(ZP_M_ONES)
stx_zp(ZP_M_TENS)
rts()

label("DIV10")
ldx_imm(0)
label("DIV10_LOOP")
cmp_imm(10)
bcc("DIV10_DONE")
sec()
sbc_imm(10)
inx()
jmp("DIV10_LOOP")
label("DIV10_DONE")
rts()

label("MUL10")
asl_a()
sta_zp(ZP_VAL)
asl_a()
asl_a()
clc()
adc_zp(ZP_VAL)
rts()

label("DELAY_10MS")
lda_abs(IO_TIMER)
label("D10_WAIT")
cmp_abs(IO_TIMER)
beq("D10_WAIT")
rts()

label("DELAY_10MS_X")
jsr("DELAY_10MS")
dex()
bne("DELAY_10MS_X")
rts()

# ==============================================================================
# 58-BYTE BSRAM AUDIO & SECTOR ENGINE (Copied to $02A0..$02D9 at startup)
# ==============================================================================
label("BSRAM_ENGINE_SRC")
# --- $02A0: BSRAM_PLAY_PAGE (15 bytes) ---
ldy_imm(0)
label("BPP_LP")
sty_abs(IO_RD_LO)
lda_abs(IO_RD_DATA)
sta_abs(IO_PCM_DAC)
iny()
bne("BPP_LP")
rts()

# --- $02AF: BSRAM_COPY_SEC (43 bytes) ---
label("BSRAM_COPY_SEC_SRC")
lda_zp(ZP_LOAD_PAGE)
sta_abs(IO_RD_HI)
ldy_imm(0)
label("BCS_P0")
sty_abs(IO_RD_LO)
lda_aby(SEC_TMP_BUF)
sta_abs(IO_RD_DATA)
iny()
bne("BCS_P0")
inc_zp(ZP_LOAD_PAGE)
lda_zp(ZP_LOAD_PAGE)
sta_abs(IO_RD_HI)
ldy_imm(0)
label("BCS_P1")
sty_abs(IO_RD_LO)
lda_aby(SEC_TMP_BUF + 0x100)
sta_abs(IO_RD_DATA)
iny()
bne("BCS_P1")
inc_zp(ZP_LOAD_PAGE)
rts()
label("BSRAM_ENGINE_END")

assert labels["BSRAM_COPY_SEC_SRC"] - labels["BSRAM_ENGINE_SRC"] == 15
assert labels["BSRAM_ENGINE_END"] - labels["BSRAM_ENGINE_SRC"] == 58

# ==============================================================================
# DATA TABLES & STRINGS
# ==============================================================================
label("TRK_CACHED")
emit(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

label("DIG_MAX_TBL")
emit(3, 10, 6, 10)

label("SEG7_MASK_TBL")
emit(0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F)
label("SEG7_DX_TBL")
emit(2, 13, 13, 2, 0, 0, 2)
label("SEG7_DY_TBL")
emit(0, 2, 13, 21, 13, 2, 10)
label("SEG7_W_TBL")
emit(12, 3, 3, 12, 3, 3, 12)
label("SEG7_H_TBL")
emit(3, 9, 9, 3, 9, 9, 3)

label("DIGIT_X_LO")
emit(246 & 0xFF, 274 & 0xFF, 318 & 0xFF, 346 & 0xFF)
label("DIGIT_X_HI")
emit(246 >> 8,   274 >> 8,   318 >> 8,   346 >> 8)

label("SND_BTN_X_LO")
emit(92, 92, 92, 92, 326 & 0xFF, 326 & 0xFF, 326 & 0xFF, 326 & 0xFF)
label("SND_BTN_X_HI")
emit(0,  0,  0,  0,  326 >> 8,   326 >> 8,   326 >> 8,   326 >> 8)
label("SND_BTN_Y")
emit(156, 174, 192, 210, 156, 174, 192, 210)

def emit_str(lbl, s):
    label(lbl)
    for ch in s:
        emit(ord(ch))
    emit(0)

emit_str("STR_WIN_TITLE",   "WEKKER + SD-KAART .WAV KIEZER (16 TRACKS)")
emit_str("STR_LBL_TIME",    "1. WEKKERTIJD (TYP 0-9, W/S OF KLIK OP CIJFER):")
emit_str("STR_LBL_SOUND",   "2. KIES .WAV VAN SD-KAART (1-8/KLIK):")
emit_str("STR_SD_PAGE1",    "P: SD LIJST 1/2 (1-8) >")
emit_str("STR_SD_PAGE2",    "P: SD LIJST 2/2 (9-16)>")
emit_str("STR_BTN_START",   "ENTER = START WEKKER & SLUIT")
emit_str("STR_BTN_TEST",    "T = TEST")
emit_str("STR_BTN_STOP",    "X = UIT")
emit_str("STR_FOOTER_HINT", "1-8=KIES .WAV  P=SD LIJST 1/2  M=VOLGENDE  Q=STOP")
emit_str("STR_RING_BANNER", "TRING! WEKKER!  SPATIE/KLIK=UIT  Z=SNOOZE(+5M)")

for lbl, blob in gpu_blobs:
    label(lbl)
    emit(*blob)

# ==============================================================================
# RESOLVE FIXUPS
# ==============================================================================
for offset, target, mode in fixups:
    assert target in labels, f"Undefined label: {target}"
    addr = labels[target]
    if mode == 'rel':
        rel = addr - (start_addr + offset + 1)
        assert -128 <= rel <= 127, f"Relative branch to {target} out of range: {rel}"
        code[offset] = rel & 0xFF
    elif mode == 'abs':
        code[offset] = addr & 0xFF
        code[offset + 1] = (addr >> 8) & 0xFF
    elif mode == 'lo':
        code[offset] = addr & 0xFF
    elif mode == 'hi':
        code[offset] = (addr >> 8) & 0xFF

print(f"Assembled WEKKER.asm v6.0 (SD-Card .WAV Picker): {len(code)} bytes ($8000..${0x8000 + len(code) - 1:04X})")
assert len(code) <= 4094, f"WEKKER.asm exceeds 4094-byte SD slot limit: {len(code)} bytes!"

lines = []
lines.append("; ======================================================================")
lines.append("; WEKKER.asm v6.0 - Dynamische SD-Kaart .WAV Bestands-Kiezer (16 .WAVs)")
lines.append(f"; Geassembleerd: $8000..${0x8000 + len(code) - 1:04X} ({len(code)} bytes)")
lines.append("; Starten vanaf SD:  BRUN \"WEKKER\"")
lines.append("; ======================================================================")

chunk_size = 6
line_num = 10
for i in range(0, len(code), chunk_size):
    chunk = code[i:i+chunk_size]
    addr = 0x8000 + i
    pokes = ":".join(f"POKE ${addr+j:04X},${b:02X}" for j, b in enumerate(chunk))
    lines.append(f"{line_num} {pokes}")
    line_num += 10

lines.append(f"{line_num} CALL $8000")
asm_text = "\n".join(lines) + "\n"

base_dir = os.path.dirname(os.path.abspath(__file__))
bin_path = os.path.join(base_dir, "sdcard", "wekker.bin")
with open(bin_path, "wb") as bf:
    bf.write(code)
print(f"Wrote binary {bin_path} ({len(code)} bytes)")

asm_path = os.path.join(base_dir, "sdcard", "WEKKER.asm")
with open(asm_path, "w", encoding="utf-8") as f:
    f.write(asm_text)
print(f"Wrote {asm_path}")

