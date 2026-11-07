#!/usr/bin/env python3
"""
MiniGPU-BASIC 1.1 "Voor Dummies" Live Test Server & COM-Poort Bridge
--------------------------------------------------------------------
Serves MiniGPU_BASIC_voor_Dummies.html on http://127.0.0.1:8765 and provides
a thread-safe REST bridge to the Tang Nano 20K UART (COM port at 115200 baud),
with CORS + Private-Network headers so even opening the HTML via file:// works!
"""

import argparse
import datetime
import html
import json
import os
import re
import socket
import sys
import threading
import time
import unicodedata
import urllib.parse
import urllib.request
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

import serial
import serial.tools.list_ports

HOST = "127.0.0.1"
PORT = 8765
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
W5500_TELETEKST_IP = "192.168.178.201"
W5500_TELETEKST_PORT = 80

# ============================================================================
# Live NOS Teletekst (https://teletekst-data.nos.nl) -> W5500 25x40 Bridge
# ============================================================================
NOS_COLOR_MAP = {
    "black": 0, "red": 1, "green": 2, "yellow": 3,
    "blue": 4, "magenta": 5, "cyan": 6, "white": 7,
}
NL_DAYS = ["MA", "DI", "WO", "DO", "VR", "ZA", "ZO"]
NL_MONTHS = ["", "JAN", "FEB", "MRT", "APR", "MEI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEC"]

_NOS_CACHE = {}          # key -> (timestamp, json_dict)
_NOS_LAST_BASE = ""      # last requested 3-digit base page (for automatic subpage cycling)
_NOS_LAST_QUERY = ""     # last requested query (e.g. "702" or "702-2")
_NOS_PUSH_LOCK = threading.Lock()


def _parse_nos_html_line(line_html):
    chars = [ord(" ")] * 40
    attrs = [0x07] * 40
    col = 0
    fg_stack = [7]
    bg_stack = [0]
    tokens = re.split(r"(<[^>]+>)", line_html or "")
    for tok in tokens:
        if not tok:
            continue
        if tok.startswith("<"):
            tl = tok.lower()
            if tl.startswith("</span") or tl.startswith("</a"):
                if len(fg_stack) > 1:
                    fg_stack.pop()
                if len(bg_stack) > 1:
                    bg_stack.pop()
            elif tl.startswith("<span") or tl.startswith("<a"):
                fg = fg_stack[-1]
                bg = bg_stack[-1]
                m = re.search(r'class=["\']([^"\']*)["\']', tl)
                if m:
                    for cls in m.group(1).split():
                        if cls in NOS_COLOR_MAP:
                            fg = NOS_COLOR_MAP[cls]
                        elif cls.startswith("bg-") and cls[3:] in NOS_COLOR_MAP:
                            bg = NOS_COLOR_MAP[cls[3:]]
                fg_stack.append(fg)
                bg_stack.append(bg)
        else:
            txt = html.unescape(tok)
            fg = fg_stack[-1]
            bg = bg_stack[-1]
            attr = ((bg & 7) << 4) | (fg & 7)
            for ch in txt:
                if col >= 40:
                    break
                cp = ord(ch)
                if 0xF020 <= cp <= 0xF07F:
                    # ETS 300 706 2x3 Teletext G1 mosaic character:
                    # bit 0=TL, 1=TR, 2=ML, 3=MR, 4=BL, bit 6 (0x40)=BR
                    raw = cp & 0x7F
                    b6 = (raw & 0x1F) | ((raw & 0x40) >> 1)
                    chars[col] = 0x80 | b6
                elif 32 <= cp <= 126:
                    chars[col] = cp
                else:
                    if ch == "€":
                        chars[col] = ord("E")
                    else:
                        norm = unicodedata.normalize("NFKD", ch).encode("ascii", "ignore").decode("ascii")
                        chars[col] = ord(norm[0]) if norm else ord(" ")
                attrs[col] = attr
                col += 1
    return chars, attrs


def _clean_3dig(val, fallback="100"):
    s = re.sub(r"\D", "", str(val or ""))
    return s[:3] if len(s) >= 3 else fallback


def build_nos_teletekst_packet(page_str):
    """
    Fetch live NOS Teletekst page (100..899, with automatic subpage cycling on repeat requests)
    and pack into a 2046-byte 'TT' W5500 frame:
      [0..1]     b'TT'
      [2..1001]  CELL_CHAR (25 * 40 = 1000 bytes) -> $4000..$43E7
      [1002..1025] LIVE_META (24 bytes)           -> $43E8..$43FF
      [1026..2025] CELL_ATTR (25 * 40 = 1000 bytes) -> $4400..$47E7
      [2026..2045] 20 zero pad bytes
    """
    global _NOS_LAST_BASE, _NOS_LAST_QUERY
    base_p = _clean_3dig(page_str, "100")
    query_p = base_p

    # If the user requests the exact same 3-digit page again and it has a nextSubPage, cycle subpages!
    if base_p == _NOS_LAST_BASE and _NOS_LAST_QUERY in _NOS_CACHE:
        _, prev_data = _NOS_CACHE[_NOS_LAST_QUERY]
        nxt_sub = (prev_data or {}).get("nextSubPage", "")
        if nxt_sub:
            query_p = nxt_sub
        else:
            query_p = base_p

    now_ts = time.time()
    data = None
    if query_p in _NOS_CACHE and (now_ts - _NOS_CACHE[query_p][0]) < 25.0:
        data = _NOS_CACHE[query_p][1]
    else:
        url = f"https://teletekst-data.nos.nl/json?p={urllib.parse.quote(query_p)}"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (TangNano20K-MiniGPU)"})
        try:
            with urllib.request.urlopen(req, timeout=4.0) as resp:
                data = json.loads(resp.read().decode("utf-8", errors="replace"))
            _NOS_CACHE[query_p] = (now_ts, data)
        except Exception:
            data = None

    _NOS_LAST_BASE = base_p
    _NOS_LAST_QUERY = query_p

    cell_chars = [ord(" ")] * 1000
    cell_attrs = [0x07] * 1000

    if data and "content" in data:
        raw_lines = data["content"].split("\n")
        for r in range(min(25, len(raw_lines))):
            c_row, a_row = _parse_nos_html_line(raw_lines[r])
            off = r * 40
            cell_chars[off:off + 40] = c_row
            cell_attrs[off:off + 40] = a_row
        prev_p = _clean_3dig(data.get("prevPage"), base_p)
        next_p = _clean_3dig(data.get("nextPage"), base_p)
        fast_links = data.get("fastTextLinks") or []
        fast_pages = []
        for i in range(4):
            if i < len(fast_links) and isinstance(fast_links[i], dict):
                fast_pages.append(_clean_3dig(fast_links[i].get("page"), "100"))
            else:
                fast_pages.append(["101", "702", "818", "100"][i])
    else:
        # Page does not exist on NOS server -> build a clean Teletext notice grid
        prev_n = max(100, min(899, int(base_p) - 1))
        next_n = max(100, min(899, int(base_p) + 1))
        prev_p = f"{prev_n:03d}"
        next_p = f"{next_n:03d}"
        fast_pages = ["101", "702", "818", "100"]
        hdr = f"                      NOS Teletekst {base_p} "
        for i, ch in enumerate(hdr[:40]):
            cell_chars[i] = ord(ch)
            cell_attrs[i] = 0x03 if i >= 35 else 0x02
        msg_lines = [
            (8,  0x43, f"   PAGINA {base_p} BESTAAT NIET BIJ DE NOS   "),
            (11, 0x07, "   Kies een ander paginanummer:         "),
            (13, 0x03, "   100 = Hoofdindex    702 = Weerkaart  "),
            (14, 0x06, "   101 = Nieuws        818 = Eredivisie "),
            (15, 0x02, "   601 = Sport         900 = Kabelkrant "),
        ]
        for r_idx, attr_val, text_str in msg_lines:
            off = r_idx * 40
            for c_idx, ch in enumerate(text_str[:40]):
                cell_chars[off + c_idx] = ord(ch)
                cell_attrs[off + c_idx] = attr_val

    # Overlay live TV page badge 'Pxxx' + Dutch Date & Clock into Row 0 cols 1..20
    dt = datetime.datetime.now()
    clock_str = f"{NL_DAYS[dt.weekday()]} {dt.day:02d} {NL_MONTHS[dt.month]} {dt.hour:02d}:{dt.minute:02d}"
    p_badge = f"P{base_p}"
    for i, ch in enumerate(p_badge):
        cell_chars[1 + i] = ord(ch)
        cell_attrs[1 + i] = 0x02  # Bright green
    for i, ch in enumerate(clock_str[:15]):
        cell_chars[6 + i] = ord(ch)
        cell_attrs[6 + i] = 0x06  # Cyan

    # Pack 24-byte LIVE_META ($43E8..$43FF):
    # [0..2]=CUR, [3..5]=PREV, [6..8]=NEXT, [9..11]=FAST0, [12..14]=FAST1, [15..17]=FAST2, [18..20]=FAST3
    meta_str = (
        base_p + prev_p + next_p
        + fast_pages[0] + fast_pages[1] + fast_pages[2] + fast_pages[3]
        + "   "
    )[:24].ljust(24, " ")
    meta_bytes = meta_str.encode("ascii", errors="replace")

    payload = (
        b"TT"
        + bytes(cell_chars)
        + meta_bytes
        + bytes(cell_attrs)
        + (b"\x00" * 20)
    )
    return payload, query_p


def push_nos_page_to_w5500(page_str, w5500_ip=W5500_TELETEKST_IP, w5500_port=W5500_TELETEKST_PORT):
    """Fetch live NOS page and push the 2046-byte 'TT' packet over TCP to W5500 Socket 3 (:80)."""
    with _NOS_PUSH_LOCK:
        try:
            payload, resolved_q = build_nos_teletekst_packet(page_str)
        except Exception as e:
            print(f"[NOS-TT] Fout bij ophalen pagina {page_str}: {e}")
            return False

        for attempt in range(6):
            try:
                with socket.create_connection((w5500_ip, w5500_port), timeout=0.6) as s:
                    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    s.sendall(payload)
                    time.sleep(0.04)
                print(f"[NOS-TT] Live NOS Teletekst pagina {resolved_q} ({len(payload)} B) naar {w5500_ip}:{w5500_port} gestuurd!")
                return True
            except Exception:
                time.sleep(0.08)
        print(f"[NOS-TT] Kon {w5500_ip}:{w5500_port} niet bereiken voor pagina {page_str}")
        return False


class SerialBridge:
    def __init__(self):
        self.lock = threading.Lock()
        self.write_lock = threading.Lock()
        self.run_lock = threading.Lock()
        self.ser = None
        self.port_name = ""
        self.baud = 115200
        self.running = False
        self.reader_thread = None

        # Rolling receive log with absolute sequence counter
        self.rx_chunks = []       # list of (start_seq, end_seq, text)
        self.rx_seq = 0           # total characters received since boot
        self.max_keep = 32768

    def list_ports(self):
        ports = []
        usb_serial_ports = []
        for p in sorted(serial.tools.list_ports.comports(), key=lambda x: x.device):
            ports.append({
                "port": p.device,
                "desc": p.description or p.device,
                "hwid": p.hwid or "",
            })
            desc_low = (p.description or "").lower()
            if "usb serial" in desc_low or "uart" in desc_low or "ch340" in desc_low or "ftdi" in desc_low:
                usb_serial_ports.append(p.device)

        # On Tang Nano 20K (dual-port USB debugger), the higher USB Serial Port (e.g. COM21) is UART!
        def port_num(dev):
            digits = "".join(ch for ch in dev if ch.isdigit())
            return int(digits) if digits else 0

        recommended = ""
        if self.port_name and self.is_connected():
            recommended = self.port_name
        elif usb_serial_ports:
            recommended = sorted(usb_serial_ports, key=port_num)[-1]
        elif ports:
            recommended = ports[-1]["port"]

        return {
            "ok": True,
            "ports": ports,
            "recommended": recommended,
            "connected": self.is_connected(),
            "port": self.port_name if self.is_connected() else "",
            "baud": self.baud,
        }

    def is_connected(self):
        return self.ser is not None and self.ser.is_open

    def _append_rx(self, text):
        if not text:
            return
        with self.lock:
            start = self.rx_seq
            end = start + len(text)
            self.rx_chunks.append((start, end, text))
            self.rx_seq = end
            # Trim old chunks beyond max_keep
            cutoff = self.rx_seq - self.max_keep
            while len(self.rx_chunks) > 1 and self.rx_chunks[0][1] <= cutoff:
                self.rx_chunks.pop(0)

    def get_rx_since(self, since_seq):
        with self.lock:
            cur_seq = self.rx_seq
            if since_seq < 0:
                # Initial attach: return last ~4096 chars
                since_seq = max(0, cur_seq - 4096)
            if since_seq >= cur_seq:
                return cur_seq, ""
            out = []
            for start, end, txt in self.rx_chunks:
                if end <= since_seq:
                    continue
                if start < since_seq:
                    out.append(txt[since_seq - start:])
                else:
                    out.append(txt)
            return cur_seq, "".join(out)

    def sync_rtc(self):
        if not self.is_connected():
            return False
        now = datetime.datetime.now()
        pkt = bytes([0xF4, 0x80 | (now.hour & 0x1F), 0x80 | (now.minute & 0x3F), 0x80 | (now.second & 0x3F)])
        try:
            with self.write_lock:
                self.ser.write(pkt)
                self.ser.flush()
            return True
        except Exception:
            return False

    def _reader_loop(self, ser_obj):
        tt_buf = ""
        last_rtc_sync = 0.0
        while self.running and ser_obj and ser_obj.is_open:
            try:
                waiting = ser_obj.in_waiting
                data = ser_obj.read(waiting if waiting > 0 else 1)
                if data:
                    txt = data.decode("latin1", errors="replace")
                    if "\x0c" in txt and (time.time() - last_rtc_sync) > 2.0:
                        last_rtc_sync = time.time()
                        threading.Thread(target=self.sync_rtc, daemon=True).start()
                    tt_buf = (tt_buf + txt)[-32:]
                    m = re.search(r"@TT(\d{3})\r", tt_buf)
                    if m:
                        p_num = m.group(1)
                        tt_buf = ""
                        threading.Thread(target=push_nos_page_to_w5500, args=(p_num,), daemon=True).start()
                    clean_txt = re.sub(r"\r?@TT\d{0,3}\r?\x0c?", "", txt)
                    if clean_txt:
                        self._append_rx(clean_txt)
            except Exception:
                break

    def connect(self, port, baud=115200):
        port = (port or "").strip()
        if not port:
            return {"ok": False, "error": "Geen COM-poort opgegeven."}
        if self.is_connected() and self.port_name.upper() == port.upper() and self.baud == int(baud):
            self.sync_rtc()
            return {"ok": True, "port": self.port_name, "baud": self.baud, "already": True}

        self.disconnect()
        try:
            ser_obj = serial.Serial(port, int(baud), timeout=0.03, write_timeout=1.5)
        except Exception as e:
            return {"ok": False, "error": f"Kan {port} niet openen: {e}"}

        self.ser = ser_obj
        self.port_name = port
        self.baud = int(baud)
        self.running = True
        self.sync_rtc()
        self.reader_thread = threading.Thread(target=self._reader_loop, args=(ser_obj,), daemon=True)
        self.reader_thread.start()
        self._append_rx(f"\r\n[Verbonden met {port} @ {self.baud} baud]\r\n")
        return {"ok": True, "port": self.port_name, "baud": self.baud}

    def disconnect(self):
        self.running = False
        old_ser = self.ser
        old_port = self.port_name
        self.ser = None
        self.port_name = ""
        if old_ser is not None:
            try:
                old_ser.close()
            except Exception:
                pass
        if self.reader_thread is not None and self.reader_thread.is_alive():
            self.reader_thread.join(timeout=0.3)
        self.reader_thread = None
        if old_port:
            self._append_rx(f"\r\n[Verbinding met {old_port} gesloten]\r\n")
        return {"ok": True}

    def send_raw(self, text, char_delay_s=0.0):
        if not self.is_connected():
            return {"ok": False, "error": "Niet verbonden met een COM-poort."}
        raw = text.encode("latin1", errors="replace")
        try:
            with self.write_lock:
                if char_delay_s > 0.0 and 1 < len(raw) <= 64:
                    for b in raw:
                        self.ser.write(bytes([b]))
                        self.ser.flush()
                        time.sleep(char_delay_s)
                else:
                    # Pace writes in 32-byte chunks so the Tang Nano 20K BL616 64-byte USB-UART
                    # endpoint buffer never overflows on long (>64 char) PIX / BASIC lines!
                    chunk_sz = 32
                    for off in range(0, len(raw), chunk_sz):
                        part = raw[off:off + chunk_sz]
                        self.ser.write(part)
                        self.ser.flush()
                        if off + chunk_sz < len(raw):
                            time.sleep(0.004)
            return {"ok": True, "sent": len(raw)}
        except Exception as e:
            return {"ok": False, "error": f"Schrijffout op {self.port_name}: {e}"}

    def _wait_for_text(self, start_seq, needle=">", timeout_s=1.5):
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            _, chunk = self.get_rx_since(start_seq)
            if needle in chunk:
                return True, chunk
            time.sleep(0.008)
        _, chunk = self.get_rx_since(start_seq)
        return (needle in chunk), chunk

    def run_basic_code(self, code, port="", baud=115200):
        with self.run_lock:
            if not self.is_connected():
                if not port:
                    info = self.list_ports()
                    port = info.get("recommended", "")
                res = self.connect(port, baud)
                if not res.get("ok"):
                    return res
                time.sleep(0.08)

            raw_lines = [ln.rstrip() for ln in (code or "").splitlines() if ln.strip()]
            if not raw_lines:
                return {"ok": False, "error": "Geen BASIC-regels om te verzenden."}

            # Step 1: Ensure BASIC is at the '> ' prompt without latching a stale break_flag
            seq0, _ = self.get_rx_since(self.rx_seq)
            res = self.send_raw("\r")
            if not res.get("ok"):
                return res
            got_prompt, _ = self._wait_for_text(seq0, ">", timeout_s=0.18)
            if not got_prompt:
                # A program, INPUT, or 6502 binary (like FTP/MC) is running -> send ESC (and 'q' fallback)
                seq1, _ = self.get_rx_since(self.rx_seq)
                self.send_raw("\x1b")
                got_prompt, _ = self._wait_for_text(seq1, ">", timeout_s=0.35)
                if not got_prompt:
                    seq_q, _ = self.get_rx_since(self.rx_seq)
                    self.send_raw("q\x1b\r")
                    got_prompt, _ = self._wait_for_text(seq_q, ">", timeout_s=0.35)
                if not got_prompt:
                    seq2, _ = self.get_rx_since(self.rx_seq)
                    self.send_raw("\r")
                    self._wait_for_text(seq2, ">", timeout_s=0.20)

            # Step 2: Upload & execute line by line
            error_lines = []
            lines_sent = 0
            for ln in raw_lines:
                stripped = ln.strip()
                upper = stripped.upper()
                seq_before, _ = self.get_rx_since(self.rx_seq)
                res = self.send_raw(stripped + "\r")
                if not res.get("ok"):
                    return res
                lines_sent += 1

                if upper == "RUN" or upper.startswith("RUN "):
                    # Wait briefly to catch immediate syntax errors or a stale *Break*
                    time.sleep(0.24)
                    _, resp = self.get_rx_since(seq_before)
                    if "*Break*" in resp:
                        seq_retry, _ = self.get_rx_since(self.rx_seq)
                        self.send_raw("RUN\r")
                        time.sleep(0.20)
                        _, resp = self.get_rx_since(seq_retry)
                    if "?Syntax" in resp or "?Undefined" in resp:
                        error_lines.append({"line": stripped, "resp": resp.strip()})
                else:
                    # Wait for BASIC '> ' prompt before sending the next line
                    # Numbered lines take ~5ms; direct commands like BEEP take up to ~1s
                    _, resp = self._wait_for_text(seq_before, ">", timeout_s=2.0)
                    if "?Syntax" in resp or "?Undefined" in resp:
                        error_lines.append({"line": stripped, "resp": resp.strip()})

            return {
                "ok": True,
                "port": self.port_name,
                "lines_sent": lines_sent,
                "errors": len(error_lines),
                "error_lines": error_lines,
            }


BRIDGE = SerialBridge()


class DummiesRequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BASE_DIR, **kwargs)

    def log_message(self, fmt, *args):
        # Keep console quiet for frequent /api/poll requests
        if len(args) >= 1 and "/api/poll" in str(args[0]):
            return
        super().log_message(fmt, *args)

    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Cache-Control", "no-store")

    def _send_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/" or path == "":
            self.path = "/MiniGPU_BASIC_voor_Dummies.html"
            return super().do_GET()

        if path == "/api/ports":
            return self._send_json(BRIDGE.list_ports())

        if path == "/api/poll":
            qs = urllib.parse.parse_qs(parsed.query)
            try:
                since = int(qs.get("since", ["-1"])[0])
            except ValueError:
                since = -1
            seq, data = BRIDGE.get_rx_since(since)
            return self._send_json({
                "ok": True,
                "connected": BRIDGE.is_connected(),
                "port": BRIDGE.port_name if BRIDGE.is_connected() else "",
                "seq": seq,
                "data": data,
            })

        if path == "/api/teletekst":
            qs = urllib.parse.parse_qs(parsed.query)
            p_num = qs.get("p", ["100"])[0]
            ok = push_nos_page_to_w5500(p_num)
            return self._send_json({"ok": ok, "page": p_num})

        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw_body = self.rfile.read(length) if length > 0 else b"{}"
        try:
            body = json.loads(raw_body.decode("utf-8"))
        except Exception:
            body = {}

        if path == "/api/connect":
            return self._send_json(BRIDGE.connect(body.get("port", ""), body.get("baud", 115200)))

        if path == "/api/disconnect":
            return self._send_json(BRIDGE.disconnect())

        if path == "/api/send":
            return self._send_json(BRIDGE.send_raw(body.get("data", ""), char_delay_s=0.015))

        if path == "/api/run":
            return self._send_json(BRIDGE.run_basic_code(
                body.get("code", ""),
                port=body.get("port", ""),
                baud=body.get("baud", 115200),
            ))

        return self._send_json({"ok": False, "error": "Onbekend endpoint"}, status=404)


def is_port_in_use(host, port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.25)
        return s.connect_ex((host, port)) == 0


def main():
    parser = argparse.ArgumentParser(description="MiniGPU-BASIC Voor Dummies Live Studio Server")
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--no-browser", action="store_true", help="Do not open browser automatically")
    args = parser.parse_args()

    url = f"http://{HOST}:{args.port}/"
    if is_port_in_use(HOST, args.port):
        print(f"Dummies Live Server draait al op {url}")
        if not args.no_browser:
            webbrowser.open(url)
        return

    httpd = ThreadingHTTPServer((HOST, args.port), DummiesRequestHandler)
    print(f"============================================================")
    print(f" MiniGPU-BASIC 1.2 'Voor Dummies' Live Test-Server actief!")
    print(f" Open in je browser: {url}")
    print(f" (Druk op Ctrl+C of sluit dit venster om te stoppen)")
    print(f"============================================================")

    if not args.no_browser:
        threading.Timer(0.35, lambda: webbrowser.open(url)).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer wordt afgesloten...")
    finally:
        BRIDGE.disconnect()
        httpd.server_close()


if __name__ == "__main__":
    main()
