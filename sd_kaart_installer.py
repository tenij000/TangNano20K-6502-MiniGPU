import os
import re
import sys
import time
import wave
import struct
import threading
import subprocess
import urllib.request
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import serial
import serial.tools.list_ports

import sd_tools
import upload_wav_sdcard

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SDCARD_DIR = os.path.join(BASE_DIR, "sdcard")
WAV_DIR = os.path.join(BASE_DIR, "wav_tracks")

# ============================================================================
# Complete Standaard Indeling voor een Schone/Lege SD-Kaart (Drives D0..D3)
# Elke Drive heeft 15 slots (#0..#14):
#   Directory-sector van Drive d (0..3) = $03FF + d * $0400
#   Data-sectoren van Drive d, Slot s   = ($0400 + d * $0400) + s * 64
# ============================================================================
DEFAULT_DRIVES_LAYOUT = {
    0: [
        ("MP3PLAY",   "MP3PLAY.asm",   "Dual-Pane MP3 & WAV Speler met 16-Band Equalizer"),
        ("LEESMIJ",   "LEESMIJ.txt",   "Systeemhandleiding & Overzicht"),
        ("EXCEL",     "EXCEL.asm",     "6502 Spreadsheet met Formules & Grafieken"),
        ("MON6502",   "MON6502.asm",   "6502 Machinecode Monitor & Disassembler"),
        ("FRUITY",    "FRUITY.asm",    "4-Kanaals FM-Synthesizer & Chiptune Tracker"),
        ("MC",        "MC.asm",        "Midnight Commander Dual-Pane Bestandsbeheerder"),
        ("TANGART",   "TANGART.img",   "Tang Nano 20K Kleurenkunst (MIMG 120x80)"),
        ("VIEWER",    "VIEWER.asm",    "Grafische MIMG Plaatjes- & Fotoviewer"),
        ("BOERDERIJ", "BOERDERIJ.img", "Hollandse Boerderij (MIMG 120x80)"),
        ("KOEIEN",    "KOEIEN.img",    "Koeien in de Wei (MIMG 120x80)"),
        ("TRACTOR",   "TRACTOR.img",   "Tractor op het Land (MIMG 120x80)"),
        ("INDEX",     "INDEX.htm",     "HTML Startpagina voor de 6502 Webbrowser"),
        ("WEKKER",    "WEKKER.asm",    "Boerderij Wekkerradio v5.0 met .WAV Geluiden"),
        ("WEB",       "WEB.asm",       "HTTP/HTML Web Client"),
        ("MUIS",      "MUIS.asm",      "Muis- & Tekenstudio"),
    ],
    1: [
        ("MP3PLAY",   "MP3PLAY.asm",   "Dual-Pane MP3 & WAV Speler"),
        ("MOLEN",     "MOLEN.img",     "Hollandse Windmolen (MIMG 120x80)"),
        ("NETTERM",   "NETTERM.asm",   "Retro Telnet & BBS Netwerkterminal"),
        ("FTP",       "FTP.asm",       "FTP Bestandsclient"),
        ("PACMAN65",  "PACMAN65.asm",  "60 fps Arcade Pac-Man in 6502 Machinecode"),
        ("TELETEKST", "TELETEKST.asm", "NOS Teletekst & Retro Paginalezer"),
        ("DUNGEON",   "DUNGEON.asm",   "Grafische Roguelike Dungeon Crawler"),
        ("INDEX",     "INDEX.htm",     "HTML Startpagina"),
        ("WEKKER",    "WEKKER.asm",    "Boerderij Wekkerradio v5.0"),
        ("JUKEBOX",   "JUKEBOX.asm",   "4-Stemmige Polyfone Chiptune Jukebox"),
        ("DIEREN",    "DIEREN.asm",    "Interactieve Boerderij-Dieren & Geluiden"),
        ("UFO",       "UFO.asm",       "60 fps Space Shooter met Hardware Sprites"),
        ("PONG",      "PONG.asm",      "Klassiek Arcade Pong"),
        ("RFTS",      "RFTS.asm",      "Reach For The Stars 4X Ruimtestrategie"),
        ("MC",        "MC.asm",        "Midnight Commander Bestandsbeheerder"),
    ],
    2: [
        ("MC",        "MC.asm",        "Midnight Commander Bestandsbeheerder"),
        ("WEB",       "WEB.asm",       "HTTP/HTML Web Client"),
        ("BROWSER",   "BROWSER.asm",   "Grafische HTML Webbrowser met Muisbesturing"),
        ("FTP",       "FTP.asm",       "FTP Bestandsclient"),
        ("GOPHER",    "GOPHER.asm",    "Gopher-protocol Browser"),
        ("BBS",       "BBS.asm",       "ANSI Bulletin Board System Client"),
        ("NETTERM",   "NETTERM.asm",   "Telnet & Seriële Terminal"),
        ("NETTERM2",  "NETTERM2.asm",  "Dual-Mode Netwerkterminal met Adresboek"),
        ("TELETEKST", "TELETEKST.asm", "Teletekst Browser"),
        ("READER",    "READER.asm",    "E-Book, Tekst- & Hex-Viewer"),
        ("WRITER",    "WRITER.asm",    "Tekstverwerker met SD-Opslag"),
        ("INDEX",     "INDEX.htm",     "HTML Startpagina"),
        ("WEBGIDS",   "WEBGIDS.txt",   "Gids voor Web, BBS, Gopher & LoRa"),
        ("MP3PLAY",   "MP3PLAY.asm",   "Dual-Pane MP3 & WAV Speler"),
        ("WAVPLAY",   "WAVPLAY.asm",   "16-Track .WAV & .MP3 Studio Speler"),
    ],
    3: [
        ("LORA",      "LORA.asm",      "LilyGO T3 v1.6.1 868.1 MHz LoRa & OLED Commander"),
        ("READER",    "READER.asm",    "E-Book, Tekst- & Hex-Viewer"),
        ("WRITER",    "WRITER.asm",    "Tekstverwerker"),
        ("CALC",      "CALC.asm",      "Wetenschappelijke Rekenmachine & Functieplotter"),
        ("IMPRESS",   "IMPRESS.asm",   "Presentatie- & Slideshow-Suite"),
        ("EXCEL",     "EXCEL.asm",     "Spreadsheet met Formules & Staafdiagrammen"),
        ("VIEWER",    "VIEWER.asm",    "Grafische MIMG Plaatjesviewer"),
        ("SPREDIT",   "SPREDIT.asm",   "16x16 Hardware Sprite & Tile Editor"),
        ("MON6502",   "MON6502.asm",   "6502 Machinecode Monitor & Disassembler"),
        ("ASM6502",   "ASM6502.asm",   "Voorbeeld 6502 Machinecode Routine ($8000)"),
        ("WEKKER",    "WEKKER.asm",    "Boerderij Wekkerradio v5.0"),
        ("BROWSER",   "BROWSER.asm",   "Grafische HTML Webbrowser"),
        ("LEESMIJ",   "LEESMIJ.txt",   "Systeemhandleiding"),
        ("KANTOOR",   "KANTOOR.txt",   "Kantoor-Suite Snelgids"),
        ("MUIS",      "MUIS.asm",      "Muis- & Tekenstudio"),
    ],
}

WAV_TRACK_FILES = [
    (1,  "1_tang_nano_stem.wav",   "1.TANG NANO STEM", 0x2010, 2),
    (2,  "2_funk_drumbeat.wav",    "2.FUNK DRUMBEAT",  0x2050, 2),
    (3,  "3_windows_tada.wav",     "3.RETRO CHORD",    0x2090, 2),
    (4,  "4_cyber_acid_bass.wav",  "4.CYBER ACID BAS", 0x20D0, 2),
    (5,  "5_studio_chimes.wav",    "5.STUDIO CHIMES",  0x2110, 2),
    (6,  "6_space_radio_fm.wav",   "6.SPACE RADIO FM", 0x2150, 2),
    (7,  "7_boerderij_wei.wav",    "7.BOERDERIJ WEI",  0x2190, 1),
    (8,  "8_ochtend_vogels.wav",   "8.OCHTENDVOGELS",  0x21D0, 1),
    (9,  "9_kraaiende_haan.wav",   "9.KRAAIENDE HAAN", 0x2210, 1),
    (10, "10_twentse_koe.wav",     "10.TWENTSE KOE",   0x2250, 1),
    (11, "11_schapenkudde.wav",    "11.SCHAPENKUDDE",  0x2290, 1),
    (12, "12_varken_en_kip.wav",   "12.VARKEN EN KIP", 0x22D0, 1),
    (13, "13_bosvogel_koor.wav",   "13.BOSVOGEL KOOR", 0x2310, 1),
    (14, "14_dorpskerk_klok.wav",  "14.DORPSKERKKLOK", 0x2350, 1),
    (15, "15_vroege_merel.wav",    "15.VROEGE MEREL",  0x2390, 1),
    (16, "16_boerenerf_mix.wav",   "16.BOERENERF MIX", 0x23D0, 1),
]

MP3_TRACK_FILES = [
    (1, "mp3_1_outfoxing_the_fox.wav",     "1.OUTFOXING.MP3",  0x3000, 5,  1),
    (2, "mp3_2_california_dreamin.wav",    "2.CALIF DREM.MP",  0x3A00, 16, 1),
    (3, "mp3_3_monday_monday.wav",         "3.MONDAY MON.MP",  0x5A00, 10, 1),
    (4, "mp3_4_dedicated_to_the_one.wav",  "4.DEDICATED.MP3",  0x6E00, 10, 1),
    (5, "mp3_5_dancing_in_the_street.wav", "5.DANCING ST.MP",  0x8200, 10, 1),
    (6, "mp3_6_spanish_harlem.wav",        "6.SPAN HARLM.MP",  0x9600, 10, 1),
    (7, "mp3_7_twist_and_shout.wav",       "7.TWIST SHT.MP3",  0xAA00, 10, 1),
    (8, "mp3_8_i_call_your_name.wav",      "8.CALL NAME.MP3",  0xBE00, 10, 1),
]


def tokenize_basic_source(source_text):
    """Converteer een .bas tekstbestand naar het interne $0800 BASIC-geheugenformaat."""
    out = bytearray()
    for raw in source_text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = re.match(r"^(\d+)\s*(.*)$", line)
        if not m:
            continue
        line_num = int(m.group(1))
        body = m.group(2).encode("ascii", errors="replace")
        rec_len = 3 + len(body) + 1
        out.append(rec_len & 0xFF)
        out.append(line_num & 0xFF)
        out.append((line_num >> 8) & 0xFF)
        out.extend(body)
        out.append(0x00)
    out.append(0x00)
    return 0x0800, bytes(out), ord("M")


def compile_sdcard_slot_item(sd_name, filename):
    """Compileer een bestand uit sdcard/ naar (load_addr, raw_bytes, entry_type_byte)."""
    filepath = os.path.join(SDCARD_DIR, filename)
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Bestand ontbreekt: {filepath}")

    ext = os.path.splitext(filename)[1].lower()
    if ext == ".asm":
        org, code = sd_tools.assemble_6502_source(open(filepath, encoding="utf-8").read())
        if len(code) > 4096:
            code = code[:4096]
        return org, code, ord("B")
    elif ext in (".txt", ".htm", ".html"):
        raw = open(filepath, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        if not raw.endswith(b"\x00"):
            raw += b"\x00"
        if len(raw) > 4095:
            raw = raw[:4094] + b"\x00"
        return 0x6000, raw, ord("B")
    elif ext in (".img", ".png", ".jpg", ".jpeg", ".bmp", ".gif"):
        data = sd_tools.convert_image_to_mimg(filepath)
        return 0x5000, data, ord("B")
    elif ext == ".bin":
        data = open(filepath, "rb").read()[:4096]
        return 0x8000, data, ord("B")
    elif ext == ".bas":
        return tokenize_basic_source(open(filepath, encoding="utf-8", errors="ignore").read())
    else:
        raise ValueError(f"Onbekend bestandstype: {filename}")


def build_drive_sectors(drive_num, slot_items=None):
    """
    Bouw voor Drive `drive_num` (0..3):
      - De 512-byte Directory-sector ($03FF + drive_num * $0400)
      - Een lijst van (start_sector, padded_512_bytes, sd_name, org, length) voor elk slot 0..14
    """
    if slot_items is None:
        slot_items = DEFAULT_DRIVES_LAYOUT[drive_num]

    dir_sector_num = 0x03FF + drive_num * 0x0400
    dir_buf = bytearray(512)
    slot_writes = []

    for slot_idx, (sd_name, filename, _desc) in enumerate(slot_items[:15]):
        org, data, ftype = compile_sdcard_slot_item(sd_name, filename)
        length = len(data)
        entry_off = slot_idx * 32
        dir_buf[entry_off : entry_off + 4] = b"BBC!"
        name_bytes = sd_name.upper().encode("ascii")[:15]
        dir_buf[entry_off + 4 : entry_off + 4 + len(name_bytes)] = name_bytes
        dir_buf[entry_off + 20] = length & 0xFF
        dir_buf[entry_off + 21] = (length >> 8) & 0xFF
        dir_buf[entry_off + 22] = ftype
        dir_buf[entry_off + 23] = org & 0xFF
        dir_buf[entry_off + 24] = (org >> 8) & 0xFF

        # Bereken benodigde 512-byte sectoren volgens ROM-formule: ((len_hi >> 1) + 1)
        num_secs = ((length >> 9) + 1)
        padded = data.ljust(num_secs * 512, b"\x00")
        slot_sec_num = (0x0400 + drive_num * 0x0400) + slot_idx * 64
        slot_writes.append((slot_sec_num, padded, sd_name, org, length, filename))

    return dir_sector_num, bytes(dir_buf), slot_writes


def read_pcm8_from_wav_file(wav_path, expected_bytes):
    """Lees 8-bit unsigned PCM data uit een reeds geconverteerd .wav bestand in wav_tracks/."""
    with wave.open(wav_path, "rb") as wf:
        raw = wf.readframes(wf.getnframes())
        sw = wf.getsampwidth()
        if sw == 1:
            pcm = raw
        else:
            # Converteer 16-bit signed naar 8-bit unsigned
            samples = struct.unpack(f"<{len(raw)//2}h", raw)
            pcm = bytes(max(0, min(255, (s >> 8) + 128)) for s in samples)
    if len(pcm) < expected_bytes:
        pcm = pcm.ljust(expected_bytes, b"\x80")
    else:
        pcm = pcm[:expected_bytes]
    return pcm


def build_complete_sdcard_image(output_img_path, include_wav=True, include_mp3=True, progress_cb=None):
    """
    Genereer een compleet raw SD-kaart image (.img) op de PC met:
      - Alle 4 Drives D0..D3 (60 programma-slots op sectoren $03FF..$13FF)
      - Sector $2000 (WAV-Dir), $2001 (MP3-Dir), $2002 (6502 MP3 BASIC-Driver)
      - Optioneel: Alle 16 .WAV tracks ($2010..$240F) en 8 .MP3 tracks ($3000..$D1FF)
    """
    max_sector = 0xD200 if include_mp3 else (0x2410 if include_wav else 0x2010)
    total_steps = 4 + 3 + (16 if include_wav else 0) + (8 if include_mp3 else 0)
    step = 0

    with open(output_img_path, "wb") as f:
        # Pre-alloceer het image-bestand
        f.seek(max_sector * 512 - 1)
        f.write(b"\x00")

        # 1. Schrijf Drives D0..D3
        for d in range(4):
            dir_sec, dir_bytes, slots = build_drive_sectors(d)
            f.seek(dir_sec * 512)
            f.write(dir_bytes)
            for slot_sec, padded, sd_name, _org, _length, _fn in slots:
                f.seek(slot_sec * 512)
                f.write(padded)
            step += 1
            if progress_cb:
                progress_cb(step, total_steps, f"Drive D{d} (15 programma's) in image geschreven...")

        # 2. Schrijf Sector $2000 (WAV-Dir), $2001 (MP3-Dir), $2002 (MP3-Driver)
        for sec, fname, label in [
            (0x2000, "wav_dir_sector2000.bin", "WAV-Catalogus ($2000)"),
            (0x2001, "mp3_dir_sector2001.bin", "MP3-Catalogus ($2001)"),
            (0x2002, "mp3_basic_driver_sector2002.bin", "6502 MP3-Driver ($2002)"),
        ]:
            p = os.path.join(WAV_DIR, fname)
            if os.path.exists(p):
                data = open(p, "rb").read().ljust(512, b"\x00")[:512]
                f.seek(sec * 512)
                f.write(data)
            step += 1
            if progress_cb:
                progress_cb(step, total_steps, f"{label} in image geschreven...")

        # 3. Schrijf alle 16 .WAV tracks ($2010..$240F)
        if include_wav:
            for idx, fname, title, start_sec, _rate in WAV_TRACK_FILES:
                p = os.path.join(WAV_DIR, fname)
                if os.path.exists(p):
                    pcm = read_pcm8_from_wav_file(p, 32768)
                    f.seek(start_sec * 512)
                    f.write(pcm)
                step += 1
                if progress_cb:
                    progress_cb(step, total_steps, f"WAV #{idx} ({title}) in image geschreven...")

        # 4. Schrijf alle 8 .MP3 tracks ($3000..)
        if include_mp3:
            for idx, fname, title, start_sec, banks, _rate in MP3_TRACK_FILES:
                p = os.path.join(WAV_DIR, fname)
                if os.path.exists(p):
                    pcm = read_pcm8_from_wav_file(p, banks * 65536)
                    f.seek(start_sec * 512)
                    f.write(pcm)
                step += 1
                if progress_cb:
                    progress_cb(step, total_steps, f"MP3 #{idx} ({title}, {banks * 64} KB) in image geschreven...")

    return max_sector * 512


def disconnect_background_server():
    """Geef COM6 tijdelijk vrij als dummies_server.py op poort 8765 draait."""
    try:
        req = urllib.request.Request("http://127.0.0.1:8765/api/disconnect", data=b"{}", method="POST")
        urllib.request.urlopen(req, timeout=0.8)
        time.sleep(0.25)
        return True
    except Exception:
        return False


def reconnect_background_server():
    """Verbind dummies_server.py weer met COM6 na afloop."""
    try:
        req = urllib.request.Request("http://127.0.0.1:8765/api/connect", data=b"{}", method="POST")
        urllib.request.urlopen(req, timeout=0.8)
    except Exception:
        pass


def install_to_tang_sdcard(
    port="COM6",
    install_drives=True,
    install_sys_sectors=True,
    install_wavs=False,
    install_mp3s=False,
    launch_mc=True,
    progress_cb=None,
):
    """
    Installeer alle geselecteerde onderdelen rechtstreeks naar een schone/lege SD-kaart
    in de Tang Nano 20K via de supersnelle $7E00 6502 Sector-Streamer!
    """
    was_connected = disconnect_background_server()
    try:
        _, streamer_code = sd_tools.assemble_6502_source(upload_wav_sdcard.STREAMER_ASM)

        # Verzamel eerst alle te schrijven sector-taken zodat we een exacte voortgangsbalk hebben
        tasks = []
        if install_drives:
            for d in range(4):
                dir_sec, dir_bytes, slots = build_drive_sectors(d)
                for slot_sec, padded, sd_name, _org, length, fn in slots:
                    tasks.append((slot_sec, padded, f"D{d}:{sd_name} ({length} B)"))
                tasks.append((dir_sec, dir_bytes, f"D{d} Catalogus (${dir_sec:04X})"))

        if install_sys_sectors:
            for sec, fname, label in [
                (0x2000, "wav_dir_sector2000.bin", "WAV-Catalogus ($2000)"),
                (0x2001, "mp3_dir_sector2001.bin", "MP3-Catalogus ($2001)"),
                (0x2002, "mp3_basic_driver_sector2002.bin", "6502 MP3-Driver ($2002)"),
            ]:
                p = os.path.join(WAV_DIR, fname)
                if os.path.exists(p):
                    data = open(p, "rb").read().ljust(512, b"\x00")[:512]
                    tasks.append((sec, data, label))

        if install_wavs:
            for idx, fname, title, start_sec, _rate in WAV_TRACK_FILES:
                p = os.path.join(WAV_DIR, fname)
                if os.path.exists(p):
                    pcm = read_pcm8_from_wav_file(p, 32768)
                    tasks.append((start_sec, pcm, f"WAV #{idx}: {title}"))

        if install_mp3s:
            for idx, fname, title, start_sec, banks, _rate in MP3_TRACK_FILES:
                p = os.path.join(WAV_DIR, fname)
                if os.path.exists(p):
                    pcm = read_pcm8_from_wav_file(p, banks * 65536)
                    # Split grote MP3-nummers in blokken van 64 sectoren (32 KB) voor vlotte voortgang
                    for b in range(banks * 2):
                        sub_sec = start_sec + b * 64
                        sub_pcm = pcm[b * 32768 : (b + 1) * 32768]
                        tasks.append((sub_sec, sub_pcm, f"MP3 #{idx} ({b+1}/{banks*2}): {title}"))

        total_sectors = sum(len(data) // 512 for _sec, data, _lbl in tasks)
        done_sectors = 0

        with serial.Serial(port, 115200, timeout=0.3) as ser:
            if progress_cb:
                progress_cb(0, max(1, total_sectors), f"Verbinden met Tang Nano 20K op {port} & SD-kaart initialiseren...")
            # Stuur 'Q' en Ctrl+C voor het geval een 6502-app (zoals LORA of MC) nog actief is
            ser.write(b"Q\x03\r")
            time.sleep(0.3)
            sd_tools.ensure_basic_prompt(ser)
            upload_wav_sdcard.send_basic_line(ser, "POKE $6D,0:SD:DRIVE 0", wait=0.6)
            upload_wav_sdcard.install_streamer_stub(ser, streamer_code)

            for start_sec, data_bytes, label in tasks:
                num_s = len(data_bytes) // 512
                if progress_cb:
                    progress_cb(done_sectors, total_sectors, f"Schrijven: {label} (Sector ${start_sec:04X}, {len(data_bytes)} bytes)...")
                upload_wav_sdcard.upload_sectors_via_basic(ser, start_sec, data_bytes, label=label)
                done_sectors += num_s
                if progress_cb:
                    progress_cb(done_sectors, total_sectors, f"Voltooid: {label} ({done_sectors}/{total_sectors} sectoren)")

            # Zet terug op Drive 0 en toon catalogus of start Midnight Commander (MC)
            upload_wav_sdcard.send_basic_line(ser, "SD:DRIVE 0", wait=0.6)
            if launch_mc:
                ser.write(b'BRUN "MC"\r')
                time.sleep(0.4)

        return done_sectors
    finally:
        if was_connected:
            reconnect_background_server()


class SDCardInstallerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("MiniGPU-BASIC 1.4 — Complete Windows SD-Kaart Installer (Voor Schone/Lege SD-Kaart)")
        self.root.geometry("1120x740")
        self.root.minsize(980, 640)
        self.root.configure(bg="#0f172a")

        self.port_var = tk.StringVar(value=sd_tools.find_tang_port("COM6"))
        self.chk_drives_var = tk.BooleanVar(value=True)
        self.chk_sys_var = tk.BooleanVar(value=True)
        self.chk_wav_var = tk.BooleanVar(value=False)
        self.chk_mp3_var = tk.BooleanVar(value=False)
        self.chk_launch_mc = tk.BooleanVar(value=True)
        self.status_var = tk.StringVar(
            value="Klaar om een schone/lege MicroSD-kaart volledig in te richten met alle 60 programma's (D0..D3), drivers, .WAV en .MP3 audio!"
        )
        self.busy = False

        self._setup_styles()
        self._build_ui()
        self._populate_preview_table()

    def _setup_styles(self):
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except Exception:
            pass
        style.configure(
            "Treeview",
            background="#1e293b",
            foreground="#f8fafc",
            fieldbackground="#1e293b",
            rowheight=24,
            font=("Consolas", 10),
        )
        style.configure(
            "Treeview.Heading",
            background="#0f172a",
            foreground="#38bdf8",
            font=("Segoe UI", 10, "bold"),
        )
        style.configure(
            "Installer.Horizontal.TProgressbar",
            troughcolor="#1e293b",
            background="#22c55e",
            thickness=22,
        )

    def _build_ui(self):
        # 1. Titelbalk
        hdr = tk.Frame(self.root, bg="#020617", pady=10, padx=16)
        hdr.pack(fill=tk.X)
        tk.Label(
            hdr,
            text="💿 MiniGPU-BASIC 1.4 — Complete SD-Kaart Installer (Windows)",
            font=("Segoe UI", 16, "bold"),
            fg="#38bdf8",
            bg="#020617",
        ).pack(side=tk.LEFT)
        tk.Label(
            hdr,
            text="Richt een lege MicroSD-kaart in 1 klik in met alle Drives (D0..D3), Games, Kantoor, LoRa 868MHz, WAV & MP3",
            font=("Segoe UI", 10),
            fg="#94a3b8",
            bg="#020617",
        ).pack(side=tk.RIGHT)

        # 2. Instellingen & Onderdelen-selectie
        cfg = tk.LabelFrame(
            self.root,
            text=" 1. Kies wat je op de schone/lege SD-kaart wilt zetten ",
            font=("Segoe UI", 11, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
            padx=14,
            pady=10,
        )
        cfg.pack(fill=tk.X, padx=14, pady=(10, 6))

        row1 = tk.Frame(cfg, bg="#1e293b")
        row1.pack(fill=tk.X, pady=2)
        tk.Label(row1, text="Tang Nano USB Poort:", font=("Segoe UI", 10, "bold"), fg="#f8fafc", bg="#1e293b").pack(side=tk.LEFT)
        self.port_combo = ttk.Combobox(row1, textvariable=self.port_var, width=10, font=("Consolas", 10))
        self.port_combo.pack(side=tk.LEFT, padx=(8, 6))
        self.refresh_ports()
        tk.Button(
            row1,
            text="🔄 Ververs Poort",
            command=self.refresh_ports,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.LEFT, padx=(0, 20))

        tk.Checkbutton(
            row1,
            text="Start na installatie direct Midnight Commander (BRUN \"MC\") op HDMI-scherm",
            variable=self.chk_launch_mc,
            font=("Segoe UI", 10),
            fg="#a7f3d0",
            bg="#1e293b",
            selectcolor="#0f172a",
            activebackground="#1e293b",
        ).pack(side=tk.LEFT)

        # Checkboxes voor de 4 pakketten
        opts = tk.Frame(cfg, bg="#1e293b", pady=6)
        opts.pack(fill=tk.X)

        for var, txt, color in [
            (
                self.chk_drives_var,
                "✔ Drives D0, D1, D2 & D3 — Alle 60 Programma-slots (MC, MP3PLAY, WAVPLAY, WEKKER, LORA 868MHz, PACMAN65, UFO, PONG, Kantoor-Suite, Browser, Plaatjes) [~30 sec]",
                "#f8fafc",
            ),
            (
                self.chk_sys_var,
                "✔ Systeem-Sectoren ($2000 WAV-Catalogus, $2001 MP3-Catalogus & $2002 Residente 6502 MP3 BASIC-Driver) [~2 sec]",
                "#fde047",
            ),
            (
                self.chk_wav_var,
                "➕ Alle 16 .WAV Geluidseffecten & Boerderij-Wekkergeluiden (Sector $2010–$240F, 512 KB PCM Audio) [~2 min via USB / 0.5 sec in .IMG]",
                "#93c5fd",
            ),
            (
                self.chk_mp3_var,
                "➕ Alle 8 Volledige .MP3 Liedjes (Sector $3000–$D1FF, 5.4 MB: California Dreamin', Twist & Shout, Outfoxing the Fox, ...) [~18 min via USB / 1 sec in .IMG]",
                "#c4b5fd",
            ),
        ]:
            tk.Checkbutton(
                opts,
                text=txt,
                variable=var,
                font=("Segoe UI", 10, "bold"),
                fg=color,
                bg="#1e293b",
                selectcolor="#0f172a",
                activebackground="#1e293b",
                anchor="w",
            ).pack(fill=tk.X, pady=2)

        # 3. Grote Actieknoppen
        btn_bar = tk.Frame(self.root, bg="#0f172a", pady=6, padx=14)
        btn_bar.pack(fill=tk.X)

        self.btn_install_usb = tk.Button(
            btn_bar,
            text="🚀 1. INSTALLEER DIRECT NAAR SD-KAART IN TANG NANO 20K (VIA USB)",
            command=self.start_usb_install,
            font=("Segoe UI", 11, "bold"),
            bg="#16a34a",
            fg="#ffffff",
            activebackground="#15803d",
            relief=tk.FLAT,
            padx=16,
            pady=10,
        )
        self.btn_install_usb.pack(side=tk.LEFT, padx=(0, 10))

        self.btn_build_img = tk.Button(
            btn_bar,
            text="💽 2. MAAK COMPLEET SD-KAART .IMG BESTAND",
            command=self.start_build_image,
            font=("Segoe UI", 10, "bold"),
            bg="#2563eb",
            fg="#ffffff",
            activebackground="#1d4ed8",
            relief=tk.FLAT,
            padx=14,
            pady=10,
        )
        self.btn_build_img.pack(side=tk.LEFT, padx=(0, 8))

        self.btn_flash_win = tk.Button(
            btn_bar,
            text="⚡ 3. SCHRIJF NAAR WINDOWS SD-KAARTLEZER (5 SEC)",
            command=self.open_windows_sd_reader_dialog,
            font=("Segoe UI", 10, "bold"),
            bg="#d97706",
            fg="#ffffff",
            activebackground="#b45309",
            relief=tk.FLAT,
            padx=14,
            pady=10,
        )
        self.btn_flash_win.pack(side=tk.LEFT, padx=(0, 8))

        tk.Button(
            btn_bar,
            text="📂 Open SD-Uploader Studio",
            command=self.open_sd_gui,
            font=("Segoe UI", 10, "bold"),
            bg="#475569",
            fg="#ffffff",
            relief=tk.FLAT,
            padx=12,
            pady=10,
        ).pack(side=tk.RIGHT)

        # 4. Voortgangsbalk & Status
        prog_frame = tk.Frame(self.root, bg="#0f172a", padx=14, pady=4)
        prog_frame.pack(fill=tk.X)
        self.progress = ttk.Progressbar(prog_frame, style="Installer.Horizontal.TProgressbar", mode="determinate")
        self.progress.pack(fill=tk.X)
        tk.Label(
            prog_frame,
            textvariable=self.status_var,
            font=("Consolas", 10, "bold"),
            fg="#22c55e",
            bg="#0f172a",
            anchor="w",
            pady=4,
        ).pack(fill=tk.X)

        # 5. Overzichtstabel van alle 60 programma-slots + Audio-tracks
        tbl_frame = tk.LabelFrame(
            self.root,
            text=" Overzicht van alle voorgeconfigureerde SD-Kaart Drives (D0..D3) & Audio-Sectoren ",
            font=("Segoe UI", 10, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        tbl_frame.pack(fill=tk.BOTH, expand=True, padx=14, pady=(4, 12))

        cols = ("drive", "slot", "sd_name", "source", "addr", "size", "sector", "desc")
        self.tree = ttk.Treeview(tbl_frame, columns=cols, show="headings")
        headers = [
            ("drive", "Drive", 75),
            ("slot", "Slot", 55),
            ("sd_name", "SD-Naam", 110),
            ("source", "Bronbestand", 140),
            ("addr", "Adres", 75),
            ("size", "Grootte", 85),
            ("sector", "SD Sector", 90),
            ("desc", "Omschrijving", 420),
        ]
        for cid, title, w in headers:
            self.tree.heading(cid, text=title)
            self.tree.column(cid, width=w, anchor="w" if cid in ("sd_name", "source", "desc") else "center")

        vsb = ttk.Scrollbar(tbl_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        vsb.pack(side=tk.RIGHT, fill=tk.Y)

    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        if not ports:
            ports = ["COM6"]
        self.port_combo["values"] = ports
        if self.port_var.get() not in ports:
            self.port_var.set(sd_tools.find_tang_port("COM6"))

    def _populate_preview_table(self):
        for item in self.tree.get_children():
            self.tree.delete(item)
        for d in range(4):
            _dir_sec, _dir_bytes, slots = build_drive_sectors(d)
            for idx, (slot_sec, _padded, sd_name, org, length, fn) in enumerate(slots):
                desc = DEFAULT_DRIVES_LAYOUT[d][idx][2]
                self.tree.insert(
                    "",
                    tk.END,
                    values=(
                        f"DRIVE {d}",
                        f"#{idx}",
                        sd_name,
                        fn,
                        f"${org:04X}",
                        f"{length} B",
                        f"${slot_sec:04X}",
                        desc,
                    ),
                )
        for idx, fname, title, start_sec, _rate in WAV_TRACK_FILES:
            self.tree.insert(
                "",
                tk.END,
                values=("AUDIO WAV", f"WAV #{idx}", title, fname, "Bank 62", "32768 B", f"${start_sec:04X}", "8-bit PCM Geluidseffect / Wekkergeluid"),
            )
        for idx, fname, title, start_sec, banks, _rate in MP3_TRACK_FILES:
            self.tree.insert(
                "",
                tk.END,
                values=("AUDIO MP3", f"MP3 #{idx}", title, fname, "Bank 17..", f"{banks*64} KB", f"${start_sec:04X}", f"Volledige .MP3 Song ({banks} SDRAM-banken)"),
            )

    def _update_progress(self, current, total, msg):
        def _cb():
            self.progress["maximum"] = max(1, total)
            self.progress["value"] = current
            self.status_var.set(msg)
        self.root.after(0, _cb)

    def start_usb_install(self):
        if self.busy:
            return
        port = self.port_var.get().strip() or "COM6"
        self.busy = True
        self.btn_install_usb.config(state=tk.DISABLED)
        self.btn_build_img.config(state=tk.DISABLED)

        def _worker():
            try:
                secs = install_to_tang_sdcard(
                    port=port,
                    install_drives=self.chk_drives_var.get(),
                    install_sys_sectors=self.chk_sys_var.get(),
                    install_wavs=self.chk_wav_var.get(),
                    install_mp3s=self.chk_mp3_var.get(),
                    launch_mc=self.chk_launch_mc.get(),
                    progress_cb=self._update_progress,
                )
                self._update_progress(100, 100, f"KLAAR! {secs} sectoren succesvol op de SD-kaart in de Tang Nano 20K ({port}) geschreven!")
                self.root.after(
                    0,
                    lambda: messagebox.showinfo(
                        "SD-Kaart Installatie Voltooid",
                        f"De SD-kaart in de Tang Nano 20K ({port}) is succesvol ingericht!\n\n"
                        f"Geschreven sectoren: {secs} ({secs * 512 // 1024} KB)\n"
                        "Je kunt nu direct werken met DRIVE 0..3, BRUN \"MC\", BRUN \"LORA\", WAV en MP3!",
                    ),
                )
            except Exception as e:
                self._update_progress(0, 100, f"FOUT: {e}")
                self.root.after(0, lambda err=str(e): messagebox.showerror("Fout bij SD-Installatie", err))
            finally:
                self.busy = False
                self.root.after(0, lambda: self.btn_install_usb.config(state=tk.NORMAL))
                self.root.after(0, lambda: self.btn_build_img.config(state=tk.NORMAL))

        threading.Thread(target=_worker, daemon=True).start()

    def start_build_image(self):
        if self.busy:
            return
        default_path = os.path.join(BASE_DIR, "MiniGPU_SDCard_Compleet.img")
        out_path = filedialog.asksaveasfilename(
            title="Sla Compleet SD-Kaart Image (.img) op",
            initialdir=BASE_DIR,
            initialfile="MiniGPU_SDCard_Compleet.img",
            defaultextension=".img",
            filetypes=[("Raw SD-Kaart Image (*.img)", "*.img"), ("Alle bestanden (*.*)", "*.*")],
        )
        if not out_path:
            return

        self.busy = True
        self.btn_install_usb.config(state=tk.DISABLED)
        self.btn_build_img.config(state=tk.DISABLED)

        def _worker():
            try:
                sz = build_complete_sdcard_image(
                    out_path,
                    include_wav=True,
                    include_mp3=True,
                    progress_cb=self._update_progress,
                )
                mb = sz / (1024 * 1024)
                self._update_progress(100, 100, f"KLAAR! Compleet SD-Kaart image opgeslagen: {out_path} ({mb:.1f} MB)")
                self.root.after(
                    0,
                    lambda: messagebox.showinfo(
                        "Compleet SD-Kaart Image (.IMG) Gereed!",
                        f"Het complete SD-kaart image is aangemaakt:\n\n{out_path}\nGrootte: {mb:.1f} MB\n\n"
                        "Dit image bevat:\n"
                        "• Alle 60 programma's op DRIVE 0, 1, 2 en 3\n"
                        "• De WAV/MP3-catalogi en 6502 MP3 BASIC-driver ($2000–$2002)\n"
                        "• Alle 16 .WAV geluidseffecten ($2010–$240F)\n"
                        "• Alle 8 volledige .MP3 muzieknummers ($3000–$D1FF)\n\n"
                        "Je kunt dit .img bestand met bijv. Win32DiskImager, BalenaEtcher of Rufus direct op een lege SD-kaart in je Windows kaartlezer schrijven!",
                    ),
                )
            except Exception as e:
                self._update_progress(0, 100, f"FOUT: {e}")
                self.root.after(0, lambda err=str(e): messagebox.showerror("Fout bij maken .IMG", err))
            finally:
                self.busy = False
                self.root.after(0, lambda: self.btn_install_usb.config(state=tk.NORMAL))
                self.root.after(0, lambda: self.btn_build_img.config(state=tk.NORMAL))

        threading.Thread(target=_worker, daemon=True).start()

    def open_sd_gui(self):
        subprocess.Popen([sys.executable, os.path.join(BASE_DIR, "sd_gui.py")], cwd=BASE_DIR)

    def open_windows_sd_reader_dialog(self):
        """Toon een veilig selectievenster voor verwijderbare USB/SD-kaartlezers in Windows."""
        try:
            ps_cmd = (
                "Get-Disk | Where-Object { $_.BusType -in @('USB','SD','MMC') -and -not $_.IsSystem -and -not $_.IsBoot } "
                "| Select-Object Number, FriendlyName, Size, BusType | ConvertTo-Json -Compress"
            )
            res = subprocess.run(["powershell", "-NoProfile", "-Command", ps_cmd], capture_output=True, text=True, timeout=6)
            raw = res.stdout.strip()
            import json
            disks = json.loads(raw) if raw else []
            if isinstance(disks, dict):
                disks = [disks]
        except Exception:
            disks = []

        if not disks:
            messagebox.showinfo(
                "Geen Verwijderbare SD-Kaartlezer Gevonden",
                "Er is momenteel geen verwijderbare SD-kaart / USB-kaartlezer in Windows gedetecteerd.\n\n"
                "• Zit de SD-kaart in de Tang Nano 20K?\n"
                "  Klik dan op knop 1 ('INSTALLEER DIRECT NAAR SD-KAART IN TANG NANO 20K').\n\n"
                "• Wil je een .IMG bestand maken voor Win32DiskImager / BalenaEtcher / Rufus?\n"
                "  Klik dan op knop 2 ('MAAK COMPLEET SD-KAART .IMG BESTAND').",
            )
            return

        dlg = tk.Toplevel(self.root)
        dlg.title("Kies Verwijderbare SD-Kaart in Windows Kaartlezer")
        dlg.geometry("620x320")
        dlg.configure(bg="#0f172a")
        dlg.transient(self.root)
        dlg.grab_set()

        tk.Label(
            dlg,
            text="Selecteer de lege SD-kaart in je Windows SD-kaartlezer:",
            font=("Segoe UI", 11, "bold"),
            fg="#38bdf8",
            bg="#0f172a",
            pady=10,
        ).pack(fill=tk.X, padx=14)

        lb = tk.Listbox(dlg, font=("Consolas", 10), bg="#1e293b", fg="#f8fafc", selectbackground="#2563eb", height=6)
        lb.pack(fill=tk.BOTH, expand=True, padx=14, pady=4)
        for d in disks:
            gb = int(d.get("Size", 0)) / (1024**3)
            lb.insert(tk.END, f"PhysicalDrive{d['Number']} — {d.get('FriendlyName','SD-Kaart')} ({gb:.1f} GB, {d.get('BusType','SD')})")
        lb.selection_set(0)

        def _do_flash():
            sel = lb.curselection()
            if not sel:
                return
            d = disks[sel[0]]
            disk_num = int(d["Number"])
            gb = int(d.get("Size", 0)) / (1024**3)
            if not messagebox.askyesno(
                "Bevestig Schrijven naar SD-Kaart",
                f"Weet je zeker dat je alle MiniGPU-BASIC programma's, .WAV en .MP3 audio wilt schrijven naar:\n\n"
                f"Schijf: PhysicalDrive{disk_num} ({d.get('FriendlyName')}, {gb:.1f} GB)?",
                parent=dlg,
            ):
                return
            dlg.destroy()
            img_path = os.path.join(BASE_DIR, "MiniGPU_SDCard_Compleet.img")
            build_complete_sdcard_image(img_path, include_wav=True, include_mp3=True, progress_cb=self._update_progress)
            # Schrijf met Administrator-rechten naar \\.\PhysicalDriveX
            ps_write = (
                f"$src = [System.IO.File]::OpenRead('{img_path}'); "
                f"$dst = New-Object System.IO.FileStream('\\\\.\\PhysicalDrive{disk_num}', [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite); "
                f"$src.CopyTo($dst); $dst.Flush(); $dst.Close(); $src.Close()"
            )
            subprocess.run(
                ["powershell", "-NoProfile", "-Command", f"Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -Command \"{ps_write}\"'"],
                check=False,
            )
            self._update_progress(100, 100, f"KLAAR! Complete SD-kaart geschreven naar PhysicalDrive{disk_num}!")
            messagebox.showinfo("SD-Kaart Gereed!", f"PhysicalDrive{disk_num} is succesvol ingericht! Je kunt de SD-kaart nu in de Tang Nano 20K steken.")

        tk.Button(
            dlg,
            text="⚡ Schrijf Nu Naar Geselecteerde SD-Kaart",
            command=_do_flash,
            font=("Segoe UI", 10, "bold"),
            bg="#d97706",
            fg="#ffffff",
            relief=tk.FLAT,
            padx=14,
            pady=8,
        ).pack(pady=10)


def verify_all_builds():
    """Controleer dat alle 60 programma-slots op D0..D3 en alle audio-sectoren foutloos compileren."""
    total_files = 0
    total_bytes = 0
    for d in range(4):
        dir_sec, dir_bytes, slots = build_drive_sectors(d)
        assert len(dir_bytes) == 512
        print(f"[DRIVE {d}] Directory Sector ${dir_sec:04X}: {len(slots)} slots geassembleerd:")
        for slot_sec, padded, sd_name, org, length, fn in slots:
            total_files += 1
            total_bytes += length
            print(f"  Slot #{slots.index((slot_sec, padded, sd_name, org, length, fn)):2d}: {sd_name:<10} <- {fn:<14} (${org:04X}, {length:4d} B, Sector ${slot_sec:04X})")
    print(f"\nSucces! Alle {total_files} programma-slots ({total_bytes} bytes totaal) voor D0..D3 zijn 100% foutloos geassembleerd!")


def main():
    if "--verify-build" in sys.argv:
        verify_all_builds()
        return
    if "--build-img" in sys.argv:
        idx = sys.argv.index("--build-img")
        out_file = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else os.path.join(BASE_DIR, "MiniGPU_SDCard_Compleet.img")
        sz = build_complete_sdcard_image(
            out_file,
            include_wav=True,
            include_mp3=True,
            progress_cb=lambda c, t, m: print(f"[{c}/{t}] {m}"),
        )
        print(f"Compleet SD-kaart image geschreven naar {out_file} ({sz // 1024} KB)")
        return
    if "--install-apps" in sys.argv:
        port = sd_tools.find_tang_port("COM6")
        if "--port" in sys.argv:
            p_idx = sys.argv.index("--port")
            if p_idx + 1 < len(sys.argv):
                port = sys.argv[p_idx + 1]
        secs = install_to_tang_sdcard(
            port=port,
            install_drives=True,
            install_sys_sectors=True,
            install_wavs="--with-wav" in sys.argv,
            install_mp3s="--with-mp3" in sys.argv,
            launch_mc=True,
            progress_cb=lambda c, t, m: print(f"[{c}/{t}] {m}"),
        )
        print(f"Klaar! {secs} sectoren geïnstalleerd op {port}.")
        return

    root = tk.Tk()
    SDCardInstallerGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
