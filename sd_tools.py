import os
import re
import time
import serial.tools.list_ports

SDCARD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sdcard")


def find_tang_port(preferred="COM6"):
    ports = [p.device for p in serial.tools.list_ports.comports()]
    if preferred in ports:
        return preferred
    usb_ports = [p.device for p in serial.tools.list_ports.comports() if "USB" in (p.description or "").upper()]
    if usb_ports:
        return usb_ports[-1]
    return preferred


# Standard 6502 Opcode Table: mnemonic -> {mode: (opcode, size)}
# Modes: 'imp', 'imm', 'zp', 'zpx', 'zpy', 'abs', 'abx', 'aby', 'ind', 'izx', 'izy', 'rel'
OPCODES_6502 = {
    "BRK": {"imp": (0x00, 1)},
    "NOP": {"imp": (0xEA, 1)},
    "CLC": {"imp": (0x18, 1)},
    "SEC": {"imp": (0x38, 1)},
    "CLI": {"imp": (0x58, 1)},
    "SEI": {"imp": (0x78, 1)},
    "CLV": {"imp": (0xB8, 1)},
    "CLD": {"imp": (0xD8, 1)},
    "SED": {"imp": (0xF8, 1)},
    "TAX": {"imp": (0xAA, 1)},
    "TXA": {"imp": (0x8A, 1)},
    "DEX": {"imp": (0xCA, 1)},
    "INX": {"imp": (0xE8, 1)},
    "TAY": {"imp": (0xA8, 1)},
    "TYA": {"imp": (0x98, 1)},
    "DEY": {"imp": (0x88, 1)},
    "INY": {"imp": (0xC8, 1)},
    "TXS": {"imp": (0x9A, 1)},
    "TSX": {"imp": (0xBA, 1)},
    "PHA": {"imp": (0x48, 1)},
    "PLA": {"imp": (0x68, 1)},
    "PHP": {"imp": (0x08, 1)},
    "PLP": {"imp": (0x28, 1)},
    "RTS": {"imp": (0x60, 1)},
    "RTI": {"imp": (0x40, 1)},
    "ASL": {"imp": (0x0A, 1), "zp": (0x06, 2), "zpx": (0x16, 2), "abs": (0x0E, 3), "abx": (0x1E, 3)},
    "LSR": {"imp": (0x4A, 1), "zp": (0x46, 2), "zpx": (0x56, 2), "abs": (0x4E, 3), "abx": (0x5E, 3)},
    "ROL": {"imp": (0x2A, 1), "zp": (0x26, 2), "zpx": (0x36, 2), "abs": (0x2E, 3), "abx": (0x3E, 3)},
    "ROR": {"imp": (0x6A, 1), "zp": (0x66, 2), "zpx": (0x76, 2), "abs": (0x6E, 3), "abx": (0x7E, 3)},
    "LDA": {"imm": (0xA9, 2), "zp": (0xA5, 2), "zpx": (0xB5, 2), "abs": (0xAD, 3), "abx": (0xBD, 3), "aby": (0xB9, 3), "izx": (0xA1, 2), "izy": (0xB1, 2)},
    "STA": {"zp": (0x85, 2), "zpx": (0x95, 2), "abs": (0x8D, 3), "abx": (0x9D, 3), "aby": (0x99, 3), "izx": (0x81, 2), "izy": (0x91, 2)},
    "LDX": {"imm": (0xA2, 2), "zp": (0xA6, 2), "zpy": (0xB6, 2), "abs": (0xAE, 3), "aby": (0xBE, 3)},
    "STX": {"zp": (0x86, 2), "zpy": (0x96, 2), "abs": (0x8E, 3)},
    "LDY": {"imm": (0xA0, 2), "zp": (0xA4, 2), "zpx": (0xB4, 2), "abs": (0xAC, 3), "abx": (0xBC, 3)},
    "STY": {"zp": (0x84, 2), "zpx": (0x94, 2), "abs": (0x8C, 3)},
    "ADC": {"imm": (0x69, 2), "zp": (0x65, 2), "zpx": (0x75, 2), "abs": (0x6D, 3), "abx": (0x7D, 3), "aby": (0x79, 3), "izx": (0x61, 2), "izy": (0x71, 2)},
    "SBC": {"imm": (0xE9, 2), "zp": (0xE5, 2), "zpx": (0xF5, 2), "abs": (0xED, 3), "abx": (0xFD, 3), "aby": (0xF9, 3), "izx": (0xE1, 2), "izy": (0xF1, 2)},
    "AND": {"imm": (0x29, 2), "zp": (0x25, 2), "zpx": (0x35, 2), "abs": (0x2D, 3), "abx": (0x3D, 3), "aby": (0x39, 3), "izx": (0x21, 2), "izy": (0x31, 2)},
    "ORA": {"imm": (0x09, 2), "zp": (0x05, 2), "zpx": (0x15, 2), "abs": (0x0D, 3), "abx": (0x1D, 3), "aby": (0x19, 3), "izx": (0x01, 2), "izy": (0x11, 2)},
    "EOR": {"imm": (0x49, 2), "zp": (0x45, 2), "zpx": (0x55, 2), "abs": (0x4D, 3), "abx": (0x5D, 3), "aby": (0x59, 3), "izx": (0x41, 2), "izy": (0x51, 2)},
    "CMP": {"imm": (0xC9, 2), "zp": (0xC5, 2), "zpx": (0xD5, 2), "abs": (0xCD, 3), "abx": (0xDD, 3), "aby": (0xD9, 3), "izx": (0xC1, 2), "izy": (0xD1, 2)},
    "CPX": {"imm": (0xE0, 2), "zp": (0xE4, 2), "abs": (0xEC, 3)},
    "CPY": {"imm": (0xC0, 2), "zp": (0xC4, 2), "abs": (0xCC, 3)},
    "INC": {"zp": (0xE6, 2), "zpx": (0xF6, 2), "abs": (0xEE, 3), "abx": (0xFE, 3)},
    "DEC": {"zp": (0xC6, 2), "zpx": (0xD6, 2), "abs": (0xCE, 3), "abx": (0xDE, 3)},
    "BIT": {"zp": (0x24, 2), "abs": (0x2C, 3)},
    "JMP": {"abs": (0x4C, 3), "ind": (0x6C, 3)},
    "JSR": {"abs": (0x20, 3)},
    "BCC": {"rel": (0x90, 2)},
    "BCS": {"rel": (0xB0, 2)},
    "BEQ": {"rel": (0xF0, 2)},
    "BNE": {"rel": (0xD0, 2)},
    "BMI": {"rel": (0x30, 2)},
    "BPL": {"rel": (0x10, 2)},
    "BVC": {"rel": (0x50, 2)},
    "BVS": {"rel": (0x70, 2)},
}


def eval_asm_expr(expr_str, symbols, pc=0):
    s = expr_str.strip()
    if not s:
        return 0
    if s.startswith("<"):
        return eval_asm_expr(s[1:], symbols, pc) & 0xFF
    if s.startswith(">"):
        return (eval_asm_expr(s[1:], symbols, pc) >> 8) & 0xFF

    # Replace '*' standalone current PC token, $hex, %bin, 'c', and symbol names
    def repl_token(m):
        tok = m.group(0)
        if tok.startswith("$"):
            return str(int(tok[1:], 16))
        if tok.startswith("%"):
            return str(int(tok[1:], 2))
        if tok.startswith("'") and len(tok) >= 2:
            return str(ord(tok[1]))
        up = tok.upper()
        if up in symbols:
            return str(symbols[up])
        return tok

    s_conv = re.sub(r"\$[0-9A-Fa-f]+|%[01]+|'[^']'|[_A-Za-z][_A-Za-z0-9]*", repl_token, s)
    return int(eval(s_conv, {"__builtins__": {}}, {}))


def assemble_6502_source(source_text):
    """Assemble standard 6502 assembly text into (org_addr, bytes)."""
    org = 0x8000
    symbols = {
        "IO_STATUS": 0xA000,
        "IO_TERM":   0xA001,
        "IO_DELAY":  0xA002,
        "IO_TIMER":  0xA003,
        "IO_JOY":    0xA004,
        "IO_RND":    0xA005,
        "IO_MODE":   0xA006,
        "IO_GPU":    0xA020,
    }
    parsed_lines = []

    for raw_line in source_text.splitlines():
        # Strip comments (; or //) outside quotes
        in_q = False
        clean = []
        for ch in raw_line:
            if ch == '"':
                in_q = not in_q
            if not in_q and ch == ";":
                break
            clean.append(ch)
        line = "".join(clean).strip()
        if not line:
            continue

        # Check constant assignment: NAME = EXPR
        m_eq = re.match(r"^([_A-Za-z][_A-Za-z0-9]*)\s*=\s*(.+)$", line)
        if m_eq:
            symbols[m_eq.group(1).upper()] = eval_asm_expr(m_eq.group(2), symbols)
            continue

        # Check label prefix: LABEL: ...
        while True:
            m_lbl = re.match(r"^([_A-Za-z][_A-Za-z0-9]*):(.*)$", line)
            if m_lbl:
                parsed_lines.append(("LABEL", m_lbl.group(1).upper()))
                line = m_lbl.group(2).strip()
                if not line:
                    break
            else:
                break
        if not line:
            continue

        parts = line.split(None, 1)
        mnem = parts[0].upper()
        arg = parts[1].strip() if len(parts) > 1 else ""
        parsed_lines.append(("OP", mnem, arg))

    # Pass 1: Determine addresses and label values
    pc = org
    items = []
    for entry in parsed_lines:
        if entry[0] == "LABEL":
            symbols[entry[1]] = pc
            items.append(("LABEL", entry[1]))
            continue
        _, mnem, arg = entry
        if mnem in ("ORG", ".ORG", "*="):
            org_val = eval_asm_expr(arg, symbols, pc)
            if not items:
                org = org_val
            pc = org_val
            continue
        elif mnem in (".BYTE", "BYTE", "DB", ".DB", ".ASCIIZ", "ASCIIZ", ".TEXT"):
            data_bytes = []
            # Split by comma outside quotes
            cur = []
            in_q = False
            for ch in arg:
                if ch == '"':
                    in_q = not in_q
                if ch == "," and not in_q:
                    data_bytes.append("".join(cur).strip())
                    cur = []
                else:
                    cur.append(ch)
            if cur:
                data_bytes.append("".join(cur).strip())
            expanded = []
            for item_s in data_bytes:
                if item_s.startswith('"') and item_s.endswith('"'):
                    for c in item_s[1:-1]:
                        expanded.append(ord(c))
                elif item_s:
                    expanded.append(item_s)
            if mnem in (".ASCIIZ", "ASCIIZ"):
                expanded.append(0)
            items.append(("BYTES", pc, expanded))
            pc += len(expanded)
            continue
        elif mnem in (".WORD", "WORD", "DW", ".DW"):
            words = [w.strip() for w in arg.split(",") if w.strip()]
            items.append(("WORDS", pc, words))
            pc += 2 * len(words)
            continue

        if mnem not in OPCODES_6502:
            raise ValueError(f"Onbekende 6502 instructie: {mnem}")

        modes = OPCODES_6502[mnem]
        arg_u = arg.upper()
        if not arg or (arg_u == "A" and "imp" in modes):
            mode = "imp"
            expr = ""
        elif "rel" in modes:
            mode = "rel"
            expr = arg
        elif arg.startswith("#"):
            mode = "imm"
            expr = arg[1:].strip()
        elif arg.startswith("(") and arg_u.endswith(",X)"):
            mode = "izx"
            expr = arg[1:-3].strip()
        elif arg.startswith("(") and arg_u.endswith("),Y"):
            mode = "izy"
            expr = arg[1:-3].strip()
        elif arg.startswith("(") and arg.endswith(")"):
            mode = "ind"
            expr = arg[1:-1].strip()
        elif arg_u.endswith(",X"):
            expr = arg[:-2].strip()
            try:
                v = eval_asm_expr(expr, symbols, pc)
                mode = "zpx" if (0 <= v < 256 and "zpx" in modes) else "abx"
            except Exception:
                mode = "abx"
        elif arg_u.endswith(",Y"):
            expr = arg[:-2].strip()
            try:
                v = eval_asm_expr(expr, symbols, pc)
                mode = "zpy" if (0 <= v < 256 and "zpy" in modes) else "aby"
            except Exception:
                mode = "aby"
        else:
            expr = arg
            try:
                v = eval_asm_expr(expr, symbols, pc)
                mode = "zp" if (0 <= v < 256 and "zp" in modes) else "abs"
            except Exception:
                mode = "abs"

        if mode not in modes:
            raise ValueError(f"Mode {mode} niet ondersteund voor {mnem} {arg}")
        opcode, sz = modes[mode]
        items.append(("INST", pc, opcode, mode, expr, sz))
        pc += sz

    # Pass 1.5: Relax out-of-range relative branches into B!cc +3 ; JMP target (5 bytes)
    while True:
        changed = False
        cur_pc = org
        for it in items:
            kind = it[0]
            if kind == "LABEL":
                symbols[it[1]] = cur_pc
            elif kind == "BYTES":
                cur_pc += len(it[2])
            elif kind == "WORDS":
                cur_pc += 2 * len(it[2])
            elif kind == "LONGBRANCH":
                cur_pc += 5
            elif kind == "INST":
                cur_pc += it[5]
        cur_pc = org
        for idx, it in enumerate(items):
            kind = it[0]
            if kind == "LABEL":
                continue
            elif kind == "BYTES":
                items[idx] = ("BYTES", cur_pc, it[2])
                cur_pc += len(it[2])
            elif kind == "WORDS":
                items[idx] = ("WORDS", cur_pc, it[2])
                cur_pc += 2 * len(it[2])
            elif kind == "LONGBRANCH":
                items[idx] = ("LONGBRANCH", cur_pc, it[2], it[3])
                cur_pc += 5
            elif kind == "INST":
                _, _, opcode, mode, expr, sz = it
                items[idx] = ("INST", cur_pc, opcode, mode, expr, sz)
                if mode == "rel":
                    val = eval_asm_expr(expr, symbols, cur_pc)
                    rel = val - (cur_pc + 2)
                    if not (-128 <= rel <= 127):
                        items[idx] = ("LONGBRANCH", cur_pc, opcode ^ 0x20, expr)
                        changed = True
                        cur_pc += 5
                        continue
                cur_pc += sz
        if not changed:
            break

    # Pass 2: Emit binary bytes
    out = bytearray()
    for it in items:
        kind = it[0]
        if kind == "LABEL":
            continue
        elif kind == "BYTES":
            _, cur_pc, arr = it
            for b in arr:
                val = b if isinstance(b, int) else eval_asm_expr(b, symbols, cur_pc)
                out.append(val & 0xFF)
        elif kind == "WORDS":
            _, cur_pc, arr = it
            for w in arr:
                val = eval_asm_expr(w, symbols, cur_pc) & 0xFFFF
                out.append(val & 0xFF)
                out.append((val >> 8) & 0xFF)
        elif kind == "LONGBRANCH":
            _, cur_pc, inv_op, expr = it
            val = eval_asm_expr(expr, symbols, cur_pc) & 0xFFFF
            out.append(inv_op)
            out.append(0x03)
            out.append(0x4C)
            out.append(val & 0xFF)
            out.append((val >> 8) & 0xFF)
        elif kind == "INST":
            _, cur_pc, opcode, mode, expr, sz = it
            out.append(opcode)
            if sz == 2:
                val = eval_asm_expr(expr, symbols, cur_pc)
                if mode == "rel":
                    rel = val - (cur_pc + 2)
                    out.append(rel & 0xFF)
                else:
                    out.append(val & 0xFF)
            elif sz == 3:
                val = eval_asm_expr(expr, symbols, cur_pc) & 0xFFFF
                out.append(val & 0xFF)
                out.append((val >> 8) & 0xFF)

    return org, bytes(out)


def _sleep_precise(sec):
    t_end = time.perf_counter() + sec
    while time.perf_counter() < t_end:
        pass


def _send_line_reliable(ser, line, char_delay=0.0004, line_wait=0.40):
    for ch in line:
        ser.write(ch.encode("ascii", errors="ignore"))
        _sleep_precise(char_delay)
    _sleep_precise(0.002)
    if ser.in_waiting:
        ser.read(ser.in_waiting)
    ser.write(b"\r")
    buf = bytearray()
    t_end = time.perf_counter() + line_wait
    while time.perf_counter() < t_end:
        avail = ser.in_waiting
        if avail:
            chunk = ser.read(avail)
            buf.extend(chunk)
            if b"\n>" in buf or buf.startswith(b">"):
                break
        else:
            _sleep_precise(0.0005)
    return buf.decode("ascii", errors="replace")


def convert_image_to_mimg(filepath, width=120, height=80, max_bytes=4095):
    """
    Load a .img (already MIMG) or convert a .png/.jpg/.bmp/.gif image to a
    120x80 RGB332 Scanline-RLE 'MIMG' binary (<= 4095 bytes) for VIEWER.asm ($5000).
    """
    with open(filepath, "rb") as f:
        raw = f.read()
    if raw[:4] == b"MIMG" and len(raw) <= max_bytes:
        return raw

    from PIL import Image
    img = Image.open(filepath).convert("RGB").resize((width, height), Image.Resampling.LANCZOS)
    pixels = list(img.getdata())

    # Convert RGB888 to RGB332 (mapping $E3 transparency key to $E2)
    rgb332_grid = []
    for y in range(height):
        row = []
        base = y * width
        for x in range(width):
            r, g, b = pixels[base + x]
            c = ((r & 0xE0)) | ((g & 0xE0) >> 3) | ((b & 0xC0) >> 6)
            if c == 0xE3:
                c = 0xE2
            row.append(c)
        rgb332_grid.append(row)

    # Encode Scanline RLE, increasing horizontal run-grouping if needed to fit <= max_bytes
    for group_step in (1, 2, 3, 4, 6):
        header = bytearray([ord("M"), ord("I"), ord("M"), ord("G"), width, height, 3, 0x01])
        rle = bytearray()
        for y in range(height):
            src_row = rgb332_grid[y]
            if group_step > 1:
                row = [src_row[(x // group_step) * group_step] for x in range(width)]
            else:
                row = src_row
            run_col = row[0]
            run_len = 1
            for x in range(1, width):
                c = row[x]
                if c == run_col and run_len < 255:
                    run_len += 1
                else:
                    rle.append(run_len)
                    rle.append(run_col)
                    run_col = c
                    run_len = 1
            rle.append(run_len)
            rle.append(run_col)
        rle.append(0)
        blob = bytes(header + rle)
        if len(blob) <= max_bytes:
            return blob

    return blob[:max_bytes - 1] + b"\x00"


def inspect_local_file(filepath):
    """Return metadata (sd_name, type, org_hex, size_bytes) for a local PC file."""
    fname = os.path.basename(filepath)
    base, ext = os.path.splitext(fname)
    sd_name = re.sub(r"[^A-Z0-9_]", "", base.upper())[:14] or "PROG"
    ext = ext.lower()
    info = {
        "filepath": filepath,
        "filename": fname,
        "sd_name": sd_name,
        "ext": ext,
        "type_label": "Onbekend",
        "org_hex": "$0800",
        "size_bytes": 0,
        "error": None,
    }
    try:
        if ext == ".bas":
            with open(filepath, "r", encoding="utf-8", errors="replace") as f:
                raw = f.read()
            lines = [ln.strip() for ln in raw.splitlines() if ln.strip() and not ln.strip().startswith(("#", "//"))]
            info["type_label"] = f"BASIC ({len(lines)} rgl)"
            info["org_hex"] = "$0800"
            info["size_bytes"] = len(raw.encode("ascii", errors="ignore"))
        elif ext in (".asm", ".s"):
            with open(filepath, "r", encoding="utf-8", errors="replace") as f:
                src = f.read()
            org, data = assemble_6502_source(src)
            info["type_label"] = "6502 ASM"
            info["org_hex"] = f"${org:04X}"
            info["size_bytes"] = len(data)
        elif ext == ".bin":
            size = os.path.getsize(filepath)
            info["type_label"] = "6502 BIN"
            info["org_hex"] = "$8000"
            info["size_bytes"] = size
        elif ext in (".txt", ".htm", ".html"):
            with open(filepath, "r", encoding="utf-8", errors="replace") as f:
                raw = f.read().replace("\r\n", "\n").replace("\r", "\n")
            info["type_label"] = "Webpagina (.HTM)" if ext.startswith(".htm") else "Tekst (.TXT)"
            info["org_hex"] = "$6000"
            info["size_bytes"] = min(len(raw) + 1, 4095)
        elif ext in (".img", ".png", ".jpg", ".jpeg", ".bmp", ".gif"):
            blob = convert_image_to_mimg(filepath)
            info["type_label"] = "Plaatje (MIMG)"
            info["org_hex"] = "$5000"
            info["size_bytes"] = len(blob)
    except Exception as e:
        info["error"] = str(e)
        info["type_label"] = "FOUT"
    return info


def ensure_basic_prompt(ser):
    """Exit any running 6502 app (including MC, VIEWER/READER, NETTERM, WEB) and return to BASIC '>'."""
    for _ in range(3):
        ser.write(b"\x1b")
        time.sleep(0.42)
        ser.write(b"\x1b")
        time.sleep(0.42)
        if ser.in_waiting:
            ser.read(ser.in_waiting)
        resp = _send_line_reliable(ser, "", char_delay=0.002, line_wait=0.30)
        if ">" in resp:
            return
    ser.write(b"\x1b")
    time.sleep(0.35)
    if ser.in_waiting:
        ser.read(ser.in_waiting)
    _send_line_reliable(ser, "", char_delay=0.002, line_wait=0.30)


def select_storage_target(ser, media=None, drive=None):
    """Switch active storage medium ('SD' or 'SDRAM') and drive (0..3) on Tang Nano 20K."""
    if media:
        cmd = "SDRAM" if str(media).upper().startswith("SDRAM") else "SD"
        _send_line_reliable(ser, cmd, char_delay=0.003, line_wait=0.45)
    if drive is not None:
        d = max(0, min(3, int(drive)))
        _send_line_reliable(ser, f"DRIVE {d}", char_delay=0.003, line_wait=0.45)


def read_sd_catalog(ser, media=None, drive=None):
    """Read the 15-slot directory catalog from the Tang Nano 20K via 'DIR'."""
    ensure_basic_prompt(ser)
    select_storage_target(ser, media=media, drive=drive)
    _send_line_reliable(ser, "CLS", char_delay=0.003, line_wait=0.35)
    if ser.in_waiting:
        ser.read(ser.in_waiting)
    raw = _send_line_reliable(ser, "DIR", char_delay=0.003, line_wait=1.2)
    slots = {
        i: {"slot": i, "name": "", "size": 0, "is_dir": False, "used": False}
        for i in range(15)
    }
    header = ""
    for line in raw.splitlines():
        s = line.strip()
        if "CATALOGUS" in s:
            header = s
        m_file = re.match(r"^#(\d+):\s+(\S+)\s+\((\d+)\s*B\)", s)
        if m_file:
            idx = int(m_file.group(1))
            if 0 <= idx < 15:
                slots[idx] = {
                    "slot": idx,
                    "name": m_file.group(2),
                    "size": int(m_file.group(3)),
                    "is_dir": False,
                    "used": True,
                }
            continue
        m_dir = re.match(r"^#(\d+):\s+(\S+)\s+<MAP>", s)
        if m_dir:
            idx = int(m_dir.group(1))
            if 0 <= idx < 15:
                slots[idx] = {
                    "slot": idx,
                    "name": m_dir.group(2),
                    "size": 0,
                    "is_dir": True,
                    "used": True,
                }
    return [slots[i] for i in range(15)], header, raw


MP3_DRIVER_BOOT_CMD = (
    "POKE $0491,0:CALL $E96A:POKE $0496,2:POKE $0497,$20:"
    "POKE $1C,0:POKE $1D,$2C:CALL $EA67"
)


def expand_mp3_in_basic_line(line: str):
    """
    Vertaal BASIC `MP3`, `MP3 0`, `MP3 nr [, rate [, mode]]` (en `WAV 0`) naar
    calls naar de residente Sector-$2002 MP3 Hulp-CPU driver op $2C00..$2C0C.
    Retourneert (expanded_line, used_mp3_drv).
    """
    out = []
    used_mp3_drv = False
    i = 0
    n = len(line)
    m_num = re.match(r"^(\s*\d+\s*)", line)
    if m_num:
        out.append(m_num.group(1))
        i = m_num.end()

    def repl_mp3_stmt(s):
        nonlocal used_mp3_drv
        m_then = re.match(r"^(\s*IF\b.*?\bTHEN\s+)(.*)$", s, re.IGNORECASE)
        if m_then:
            return m_then.group(1) + repl_mp3_stmt(m_then.group(2))
        m_wav0 = re.match(r"^(\s*)WAV\s+0\s*$", s, re.IGNORECASE)
        if m_wav0:
            return f"{m_wav0.group(1)}POKE $A01B,0"
        m_mp3 = re.match(r"^(\s*)MP3(?:\s+(.*))?$", s, re.IGNORECASE)
        if not m_mp3:
            return s
        lead = m_mp3.group(1)
        args_str = (m_mp3.group(2) or "").strip()
        if not args_str:
            used_mp3_drv = True
            return f"{lead}CALL $2C00"
        args = []
        cur = []
        depth = 0
        q = False
        for c in args_str:
            if c == '"':
                q = not q
            elif not q:
                if c == "(":
                    depth += 1
                elif c == ")":
                    depth = max(0, depth - 1)
                elif c == "," and depth == 0:
                    args.append("".join(cur).strip())
                    cur = []
                    continue
            cur.append(c)
        args.append("".join(cur).strip())
        if len(args) == 1:
            if args[0] == "0":
                return f"{lead}POKE $A01B,0"
            used_mp3_drv = True
            return f"{lead}POKE $63,{args[0]}:CALL $2C04"
        elif len(args) == 2:
            used_mp3_drv = True
            return f"{lead}POKE $63,{args[0]}:POKE $64,{args[1]}:CALL $2C08"
        else:
            used_mp3_drv = True
            return f"{lead}POKE $63,{args[0]}:POKE $64,{args[1]}:POKE $65,{args[2]}:CALL $2C0C"

    while i < n:
        m_rem = re.match(r"^(\s*(?:REM\b|').*)", line[i:], re.IGNORECASE)
        if m_rem:
            out.append(m_rem.group(1))
            break
        j = i
        in_q = False
        while j < n:
            ch = line[j]
            if ch == '"':
                in_q = not in_q
            elif ch == ":" and not in_q:
                break
            j += 1
        out.append(repl_mp3_stmt(line[i:j]))
        if j < n and line[j] == ":":
            out.append(":")
            i = j + 1
        else:
            break
    return "".join(out), used_mp3_drv


def upload_file_to_sdcard(
    ser,
    filepath,
    run_after=False,
    sd_name_override=None,
    media=None,
    drive=None,
    save_to_sd=True,
    progress_cb=None,
):
    """Upload a .bas, .asm, .bin, or .txt file from PC to the Tang Nano 20K SD/SDRAM disk."""
    fname = os.path.basename(filepath)
    base, ext = os.path.splitext(fname)
    raw_name = sd_name_override.strip() if sd_name_override else base
    sd_name = re.sub(r"[^A-Z0-9_]", "", raw_name.upper())[:14] or "PROG"
    ext = ext.lower()

    ensure_basic_prompt(ser)
    if save_to_sd:
        select_storage_target(ser, media=media, drive=drive)

    if ext == ".bas":
        with open(filepath, "r", encoding="utf-8") as f:
            raw_lines = [
                ln.strip()
                for ln in f.read().splitlines()
                if ln.strip() and not ln.strip().startswith(("#", "//"))
            ]
        lines = []
        any_mp3_drv = False
        for ln in raw_lines:
            exp_ln, used_drv = expand_mp3_in_basic_line(ln)
            lines.append(exp_ln)
            if used_drv:
                any_mp3_drv = True
        if any_mp3_drv:
            _send_line_reliable(ser, MP3_DRIVER_BOOT_CMD, char_delay=0.001, line_wait=0.35)
            m_first = re.match(r"^\s*(\d+)", lines[0]) if lines else None
            if m_first and int(m_first.group(1)) > 1:
                lines.insert(0, f"1 {MP3_DRIVER_BOOT_CMD}")
        total = max(1, len(lines))
        msg = f"[SD-COPY] BASIC programma '{fname}' ({len(lines)} regels) -> '{sd_name}'..."
        print(f"\n{msg}")
        if progress_cb:
            progress_cb(0, total, msg)
        _send_line_reliable(ser, "NEW", line_wait=0.2)
        for idx, ln in enumerate(lines, 1):
            print(f"\r  Verzenden regel {idx}/{total}...", end="", flush=True)
            _send_line_reliable(ser, ln, char_delay=0.0012, line_wait=0.35)
            if progress_cb:
                progress_cb(idx, total, f"Verzenden BASIC regel {idx}/{total} ({sd_name})...")
        print()
        if save_to_sd:
            out = _send_line_reliable(ser, f'SAVE "{sd_name}"', char_delay=0.004, line_wait=1.8)
            print(out.strip())
            if progress_cb:
                progress_cb(total, total, out.strip() or f"BASIC '{sd_name}' opgeslagen!")
        if run_after:
            _send_line_reliable(ser, "RUN", line_wait=0.2)
        return sd_name, "BAS"

    elif ext in (".asm", ".s", ".bin"):
        if ext in (".asm", ".s"):
            with open(filepath, "r", encoding="utf-8") as f:
                src = f.read()
            org, data = assemble_6502_source(src)
            msg = f"[SD-COPY] 6502 ASM '{fname}' geassembleerd: {len(data)} bytes op ${org:04X}-${org+len(data)-1:04X}"
            print(f"\n{msg}")
        else:
            with open(filepath, "rb") as f:
                data = f.read()
            org = 0x8000
            msg = f"[SD-COPY] 6502 Binary '{fname}': {len(data)} bytes -> ${org:04X}"
            print(f"\n{msg}")

        total = len(data)
        if progress_cb:
            progress_cb(0, total, msg)

        # Upload in chunks of 7 POKEs per line, synchronized on the '>' prompt
        _send_line_reliable(ser, "CLS", char_delay=0.002, line_wait=0.3)
        for line_idx, i in enumerate(range(0, total, 7)):
            chunk = data[i:i+7]
            stmts = [f"POKE ${org + i + j:04X},${b:02X}" for j, b in enumerate(chunk)]
            if line_idx > 0 and (line_idx % 20) == 0:
                stmts.insert(0, "CLS")
            _send_line_reliable(ser, ":".join(stmts), char_delay=0.0004, line_wait=0.40)
            done = min(i + 7, total)
            print(f"\r  Uploaden naar SDRAM ${org:04X}: {done}/{total} bytes...", end="", flush=True)
            if progress_cb and ((line_idx % 4) == 0 or done == total):
                progress_cb(done, total, f"Uploaden '{sd_name}' naar ${org:04X}: {done}/{total} bytes...")
        print()
        # Resync cleanly with BASIC '>' prompt before BSAVE
        time.sleep(0.15)
        if ser.in_waiting:
            ser.read(ser.in_waiting)
        _send_line_reliable(ser, "CLS", char_delay=0.003, line_wait=0.4)
        if save_to_sd:
            out = _send_line_reliable(ser, f'BSAVE "{sd_name}",${org:04X},${total:04X}', char_delay=0.004, line_wait=2.5)
            print(out.strip())
            if progress_cb:
                progress_cb(total, total, out.strip() or f"'{sd_name}' ({total} B) opgeslagen!")
        if run_after:
            if save_to_sd:
                _send_line_reliable(ser, f'BRUN "{sd_name}"', char_delay=0.004, line_wait=0.5)
            else:
                _send_line_reliable(ser, f"CALL ${org:04X}", char_delay=0.004, line_wait=0.5)
        return sd_name, "ASM"

    elif ext in (".txt", ".htm", ".html"):
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            raw_text = f.read().replace("\r\n", "\n").replace("\r", "\n")
        ascii_bytes = bytearray()
        for ch in raw_text:
            code = ord(ch)
            if ch == "\n":
                ascii_bytes.append(0x0A)
            elif 0x20 <= code < 0x7F:
                ascii_bytes.append(code)
            else:
                ascii_bytes.append(ord("?"))
        if len(ascii_bytes) > 4094:
            ascii_bytes = ascii_bytes[:4094]
        ascii_bytes.append(0x00)
        data = bytes(ascii_bytes)
        org = 0x6000
        total = len(data)
        msg = f"[SD-COPY] Tekstbestand '{fname}': {total} bytes -> ${org:04X}-${org+total-1:04X}"
        print(f"\n{msg}")
        if progress_cb:
            progress_cb(0, total, msg)

        _send_line_reliable(ser, "CLS", char_delay=0.002, line_wait=0.3)
        for line_idx, i in enumerate(range(0, total, 7)):
            chunk = data[i:i+7]
            stmts = [f"POKE ${org + i + j:04X},${b:02X}" for j, b in enumerate(chunk)]
            if line_idx > 0 and (line_idx % 20) == 0:
                stmts.insert(0, "CLS")
            _send_line_reliable(ser, ":".join(stmts), char_delay=0.0004, line_wait=0.40)
            done = min(i + 7, total)
            print(f"\r  Uploaden naar SDRAM ${org:04X}: {done}/{total} bytes...", end="", flush=True)
            if progress_cb and ((line_idx % 4) == 0 or done == total):
                progress_cb(done, total, f"Uploaden tekst '{sd_name}' naar ${org:04X}: {done}/{total} bytes...")
        print()
        # Zet DOC_MAGIC ($5520 = 0) zodat READER.asm het bestand vers vanaf de SD-kaart inlaadt (incl. RAW_BUF voor Hex-modus)
        time.sleep(0.15)
        if ser.in_waiting:
            ser.read(ser.in_waiting)
        _send_line_reliable(ser, "CLS", char_delay=0.003, line_wait=0.4)
        _send_line_reliable(ser, "POKE $5520,0", char_delay=0.003, line_wait=0.25)

        if save_to_sd:
            out = _send_line_reliable(ser, f'BSAVE "{sd_name}",${org:04X},${total:04X}', char_delay=0.004, line_wait=2.5)
            print(out.strip())
            if progress_cb:
                progress_cb(total, total, out.strip() or f"Tekst '{sd_name}' ({total} B) opgeslagen!")
        if run_after:
            _send_line_reliable(ser, 'BRUN "READER"', char_delay=0.004, line_wait=0.5)
        return sd_name, "TXT"

    elif ext in (".img", ".png", ".jpg", ".jpeg", ".bmp", ".gif"):
        data = convert_image_to_mimg(filepath)
        org = 0x5000
        total = len(data)
        msg = f"[SD-COPY] Plaatje '{fname}' (MIMG 120x80 RLE): {total} bytes -> ${org:04X}-${org+total-1:04X}"
        print(f"\n{msg}")
        if progress_cb:
            progress_cb(0, total, msg)

        _send_line_reliable(ser, "CLS", char_delay=0.002, line_wait=0.3)
        for line_idx, i in enumerate(range(0, total, 7)):
            chunk = data[i:i+7]
            stmts = [f"POKE ${org + i + j:04X},${b:02X}" for j, b in enumerate(chunk)]
            if line_idx > 0 and (line_idx % 20) == 0:
                stmts.insert(0, "CLS")
            _send_line_reliable(ser, ":".join(stmts), char_delay=0.0004, line_wait=0.40)
            done = min(i + 7, total)
            print(f"\r  Uploaden naar SDRAM ${org:04X}: {done}/{total} bytes...", end="", flush=True)
            if progress_cb and ((line_idx % 4) == 0 or done == total):
                progress_cb(done, total, f"Uploaden plaatje '{sd_name}' naar ${org:04X}: {done}/{total} bytes...")
        print()
        time.sleep(0.15)
        if ser.in_waiting:
            ser.read(ser.in_waiting)
        _send_line_reliable(ser, "CLS", char_delay=0.003, line_wait=0.4)

        if save_to_sd:
            out = _send_line_reliable(ser, f'BSAVE "{sd_name}",${org:04X},${total:04X}', char_delay=0.004, line_wait=2.5)
            print(out.strip())
            if progress_cb:
                progress_cb(total, total, out.strip() or f"Plaatje '{sd_name}' ({total} B) opgeslagen!")
        if run_after:
            _send_line_reliable(ser, 'BRUN "VIEWER"', char_delay=0.004, line_wait=0.5)
        return sd_name, "IMG"

    else:
        raise ValueError(f"Onbekend bestandstype '{ext}' (gebruik .bas, .asm, .bin, .txt, .img, .png of .jpg)")
