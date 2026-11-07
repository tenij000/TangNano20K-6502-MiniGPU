import sys
import time
import serial
import cv2

sys.path.insert(0, r"E:\hardware\DONDERDAG_BASIC")
from build_minigpu_basic_rom import Asm6502

IO_STATUS = 0xA000
IO_TERM   = 0xA001
IO_DELAY  = 0xA002
IO_JOY    = 0xA004
IO_MODE   = 0xA006
IO_GPU    = 0xA020

def build_6502_demo():
    a = Asm6502(org=0x8000, size=512)

    # Entry point at $8000
    a.label("START")
    # Set TARGET 1 (front buffer) so 6502 ASM draws directly at lightning speed
    a.lda_imm(12)
    a.sta_abs(IO_GPU)
    a.lda_imm(1)
    a.sta_abs(IO_GPU)

    # Clear screen to dark navy ($02)
    a.lda_imm(1)
    a.sta_abs(IO_GPU)
    a.lda_imm(0x02)
    a.sta_abs(IO_GPU)

    # Draw 32 horizontal rainbow/copper bars across the screen (Y = 36..292, height = 8)
    # Using X register as loop counter 0..31
    a.ldx_imm(0)
    a.label("BAR_LP")
    a.lda_imm(2) # CMD_FILL_RECT (x, y, w, h, color)
    a.sta_abs(IO_GPU)
    # x = 20
    a.lda_imm(20)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(IO_GPU)
    # y = 44 + X * 8
    a.txa()
    a.asl_a()
    a.asl_a()
    a.asl_a()
    a.clc()
    a.adc_imm(44)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.adc_imm(0)
    a.sta_abs(IO_GPU)
    # w = 600 ($0258)
    a.lda_imm(0x58)
    a.sta_abs(IO_GPU)
    a.lda_imm(0x02)
    a.sta_abs(IO_GPU)
    # h = 6
    a.lda_imm(6)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(IO_GPU)
    # color = X * 7 + $15
    a.txa()
    a.asl_a()
    a.asl_a()
    a.adc_imm(0x15)
    a.sta_abs(IO_GPU)

    a.inx()
    a.cpx_imm(32)
    a.bcc("BAR_LP")

    # Draw center black dialog box: RECT 60, 100, 520, 150, 0
    a.ldx_imm(0)
    a.label("CMD_STREAM_LP")
    a.lda_abx("GPU_STREAM")
    a.sta_abs(IO_GPU)
    a.inx()
    a.cpx_imm(35)
    a.bcc("CMD_STREAM_LP")

    # Print banner string via GPU GTEXT at (85, 118) in yellow ($FC)
    a.lda_imm(15) # CMD_DRAW_TEXT
    a.sta_abs(IO_GPU)
    a.lda_imm(85)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(IO_GPU)
    a.lda_imm(118)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(IO_GPU)
    a.lda_imm(0xFC)
    a.sta_abs(IO_GPU)
    a.ldx_imm(0)
    a.label("TXT1_LP")
    a.lda_abx("STR_ASM1")
    a.sta_abs(IO_GPU)
    a.beq("TXT1_DN")
    a.inx()
    a.bne("TXT1_LP")
    a.label("TXT1_DN")

    # Print second line via GPU GTEXT at (85, 148) in white ($FF)
    a.lda_imm(15)
    a.sta_abs(IO_GPU)
    a.lda_imm(85)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(IO_GPU)
    a.lda_imm(148)
    a.sta_abs(IO_GPU)
    a.lda_imm(0)
    a.sta_abs(IO_GPU)
    a.lda_imm(0xFF)
    a.sta_abs(IO_GPU)
    a.ldx_imm(0)
    a.label("TXT2_LP")
    a.lda_abx("STR_ASM2")
    a.sta_abs(IO_GPU)
    a.beq("TXT2_DN")
    a.inx()
    a.bne("TXT2_LP")
    a.label("TXT2_DN")

    # Return 65 (ASCII 'A') in Accumulator A for USR($8000) and RTS back to BASIC!
    a.lda_imm(65)
    a.rts()

    # Pre-packed GPU command stream for center dialog & circles/triangles
    a.label("GPU_STREAM")
    a.emit(
        # RECT 60, 100, 520 ($0208), 150, $00
        2, 60, 0, 100, 0, 0x08, 0x02, 150, 0, 0x00,
        # RECT 60, 100, 520 ($0208), 8, $E0 (red top border)
        2, 60, 0, 100, 0, 0x08, 0x02, 8, 0, 0xE0,
        # DISK 160, 205, 28, $1F (cyan disk)
        5, 160, 0, 205, 0, 28, 0, 0x1F,
        # DISK 320, 205, 28, $FC (yellow disk)
        5, 0x40, 0x01, 205, 0, 28, 0, 0xFC,
        # DISK 480, 205, 28, $E3 (magenta disk)
        5, 0xE0, 0x01, 205, 0, 28, 0, 0xE3,
    )

    a.label("STR_ASM1")
    a.ascii_z("6502 ASSEMBLY OP $8000 (VANAF SD-KAART!)")
    a.label("STR_ASM2")
    a.ascii_z("BRUN / BLOAD / BSAVE / CALL $8000 ACTIEF!")

    # Assemble raw bytes (without vector table at the end)
    pc = a.org
    for item in a.ops:
        kind = item[0]
        if kind == "LABEL":
            a.labels[item[1]] = pc
        elif kind == "BYTES":
            pc += len(item[1])
        elif kind == "WORD":
            pc += 2
        elif kind == "INST":
            pc += item[3]
    code_len = pc - a.org
    raw = bytearray(code_len)
    pc = a.org
    for item in a.ops:
        kind = item[0]
        if kind == "LABEL":
            continue
        elif kind == "BYTES":
            for b in item[1]:
                raw[pc - a.org] = a.resolve(b) & 0xFF
                pc += 1
        elif kind == "INST":
            _, opcode, operand, sz = item
            raw[pc - a.org] = opcode & 0xFF
            if sz == 2:
                if opcode in (0xF0, 0xD0, 0xB0, 0x90, 0x30, 0x10):
                    target = a.resolve(operand)
                    rel = target - (pc + 2)
                    raw[pc - a.org + 1] = rel & 0xFF
                else:
                    raw[pc - a.org + 1] = a.resolve(operand) & 0xFF
            elif sz == 3:
                v = a.resolve(operand) & 0xFFFF
                raw[pc - a.org + 1] = v & 0xFF
                raw[pc - a.org + 2] = (v >> 8) & 0xFF
            pc += sz
    return bytes(raw)

if __name__ == "__main__":
    code = build_6502_demo()
    print(f"Assembled 6502 binary: {len(code)} bytes at $8000-${0x8000+len(code)-1:04X}")

    ser = serial.Serial("COM6", 115200, timeout=0.5)
    time.sleep(0.3)
    ser.write(b"\x1b")
    time.sleep(0.3)
    ser.read(4096)

    def send_cmd(cmd, wait=0.25):
        for ch in cmd:
            ser.write(ch.encode("ascii"))
            time.sleep(0.002)
        ser.write(b"\r")
        time.sleep(wait)
        out = ser.read(4096).decode("ascii", errors="replace").strip()
        if out:
            print(out)
        return out

    # Upload 6502 machine code into $8000 in batches of 4 POKEs per line
    print("Uploading 6502 machine code to $8000...")
    for i in range(0, len(code), 4):
        chunk = code[i:i+4]
        stmts = [f"POKE ${0x8000 + i + j:04X},${b:02X}" for j, b in enumerate(chunk)]
        line = ":".join(stmts)
        for ch in line:
            ser.write(ch.encode("ascii"))
            time.sleep(0.0015)
        ser.write(b"\r")
        time.sleep(0.08)
        ser.read(4096)

    print("Saving 6502 binary to SD card as ASM6502...")
    send_cmd(f'BSAVE "ASM6502", $8000, {len(code)}', wait=1.5)

    print("Wiping $8000 in RAM to prove BLOAD/BRUN loads from SD card...")
    send_cmd("POKE $8000, 0 : PRINT PEEK($8000)", wait=0.4)

    print("Running CAT to see ASM6502 on SD card...")
    send_cmd("CAT", wait=1.2)

    print("Executing CLS : BRUN \"ASM6502\" from SD card!")
    send_cmd('CLS : BRUN "ASM6502"', wait=1.5)

    print("Testing USR($8000) return value (should be 65):")
    send_cmd("PRINT USR($8000)", wait=0.5)
    ser.close()

    cap = cv2.VideoCapture(1, cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    for _ in range(6):
        cap.read()
    ret, frame = cap.read()
    if ret:
        cv2.imwrite(r"C:\Users\robte\.gemini\antigravity-cli\brain\4f01101f-0ff1-437c-8f89-61e94ca42489\scratch\hdmi_6502_asm.png", frame)
        print("Saved HDMI screenshot to hdmi_6502_asm.png!")
    cap.release()

