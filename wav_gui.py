import glob
import math
import os
import re
import struct
import subprocess
import sys
import tempfile
import threading
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import urllib.request
import wave
import winsound

import serial
import serial.tools.list_ports

import sd_tools
import upload_wav_sdcard as wav_up

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WAV_DIR = os.path.join(BASE_DIR, "wav_tracks")
INET_DIR = os.path.join(WAV_DIR, "internet_samples")
DOWNLOADS_DIR = os.path.join(os.path.expanduser("~"), "Downloads")
DIR_CACHE_PATH = os.path.join(WAV_DIR, "wav_dir_sector2000.bin")
MP3_DIR_CACHE_PATH = os.path.join(WAV_DIR, "mp3_dir_sector2001.bin")

RATE_OPTIONS = [
    ("1 — 8000 Hz (Standaard MP3/WAV)", 1, 8000),
    ("2 — 11025 Hz (Helderder)", 2, 11025),
    ("3 — 16000 Hz (Hoge Kwaliteit)", 3, 16000),
    ("4 — 22050 Hz (Studio Hi-Fi)", 4, 22050),
]

MP3_BANK_OPTIONS = [
    ("0 — Volledig Liedje (Auto 1..24 Banken, tot 3m16s!)", 0),
    ("1 Bank — 64 KB (8.2 sec @ 8kHz, Snelste ~3s upload)", 1),
    ("2 Banken — 128 KB (16.4 sec @ 8kHz, Standaard ~6s upload)", 2),
    ("4 Banken — 256 KB (32.8 sec @ 8kHz, ~12s upload)", 4),
    ("8 Banken — 512 KB (1 min 05 sec @ 8kHz, ~24s upload)", 8),
    ("12 Banken — 768 KB (1 min 38 sec @ 8kHz, ~36s upload)", 12),
    ("16 Banken — 1.0 MB (2 min 11 sec @ 8kHz — Volledig Liedje!)", 16),
    ("20 Banken — 1.25 MB (2 min 44 sec @ 8kHz — Volledig Liedje!)", 20),
    ("24 Banken — 1.5 MB (3 min 16 sec @ 8kHz — Volledig Liedje!)", 24),
]

RATE_CODE_TO_HZ = {1: 8000, 2: 11025, 3: 16000, 4: 22050}

# Vaste SD-kaart start-sectoren voor de 16 .WAV slots (Sector $2000), elk 64 sectoren (32 KB)
DEFAULT_SLOT_SECTORS = [
    0x2190,  # Slot #1  (Pagina 1 #1)
    0x21D0,  # Slot #2  (Pagina 1 #2)
    0x2210,  # Slot #3  (Pagina 1 #3)
    0x2250,  # Slot #4  (Pagina 1 #4)
    0x2290,  # Slot #5  (Pagina 1 #5)
    0x22D0,  # Slot #6  (Pagina 1 #6)
    0x2310,  # Slot #7  (Pagina 1 #7)
    0x2350,  # Slot #8  (Pagina 1 #8)
    0x2390,  # Slot #9  (Pagina 2 #1)
    0x23D0,  # Slot #10 (Pagina 2 #2)
    0x2010,  # Slot #11 (Pagina 2 #3)
    0x2050,  # Slot #12 (Pagina 2 #4)
    0x2090,  # Slot #13 (Pagina 2 #5)
    0x20D0,  # Slot #14 (Pagina 2 #6)
    0x2110,  # Slot #15 (Pagina 2 #7)
    0x2150,  # Slot #16 (Pagina 2 #8)
]

DEFAULT_SLOT_TITLES = [
    ("1.BOERDERIJ WEI", 1),
    ("2.OCHTENDVOGELS", 1),
    ("3.KRAAIENDE HN ", 1),
    ("4.TWENTSE KOE  ", 1),
    ("5.SCHAPENKUDDE ", 1),
    ("6.VARKEN & KIP ", 1),
    ("7.BOSVOGEL KOOR", 1),
    ("8.DORPSKERK KLK", 1),
    ("1.VROEGE MEREL ", 1),
    ("2.BOERENERF MIX", 1),
    ("3.TANG NANO STM", 1),
    ("4.FUNK DRUMBEAT", 1),
    ("5.WINDOWS TADA!", 2),
    ("6.CYBER ACID BS", 1),
    ("7.STUDIO CHIMES", 2),
    ("8.SPACE RADIO  ", 1),
]

# Standaard 8 .MP3 slots in Sector $2001 (Linker Paneel van MP3PLAY.asm)
# Korte clips (<=2 banken) staan op $2410..$2890; lange volledige liedjes (3..24 banken) krijgen automatisch $3000 + (slot-1)*$1000!
DEFAULT_MP3_SLOTS = [
    ("1.OUTFOXING.MP3", 0x2410, 2, 1, 16),
    ("2.CALIF DREM.MP", 0x2510, 2, 1, 16),
    ("3.MONDAY MON.MP", 0x2610, 1, 1, 8),
    ("4.DEDICATED.MP3", 0x2690, 1, 1, 8),
    ("5.DANCING ST.MP", 0x2710, 1, 1, 8),
    ("6.SPAN HARLM.MP", 0x2790, 1, 1, 8),
    ("7.TWIST SHT.MP3", 0x2810, 1, 1, 8),
    ("8.CALL NAME.MP3", 0x2890, 1, 1, 8),
]


class WavStudioGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("🎵 Tang Nano 20K — MP3 & WAV Converter + MicroSD Studio GUI (MP3Commander 2.1)")
        self.root.geometry("1320x850")
        self.root.minsize(1100, 700)
        self.root.configure(bg="#0f172a")

        os.makedirs(WAV_DIR, exist_ok=True)
        os.makedirs(INET_DIR, exist_ok=True)

        self.port_var = tk.StringVar(value=sd_tools.find_tang_port("COM6"))
        self.folder_var = tk.StringVar(value=WAV_DIR)
        self.selected_pc_file = None
        self.raw_preview_samples = []
        self.raw_preview_sr = 8000
        self.raw_preview_dur = 0.0

        # Active target tab: 0 = .MP3 Liedjes (Sector $2001), 1 = .WAV Geluiden (Sector $2000)
        self.mp3_slot_var = tk.IntVar(value=1)  # 1..8
        self.mp3_title_var = tk.StringVar(value="1.OUTFOXING.MP3")
        self.mp3_banks_combo_var = tk.StringVar(value=MP3_BANK_OPTIONS[2][0])  # Default 2 Banken (16.4s) of 0 (Volledig)

        self.slot_var = tk.IntVar(value=1)  # 1..16 (.WAV)
        self.title_var = tk.StringVar(value="1.BOERDERIJ WEI")
        self.rate_combo_var = tk.StringVar(value=RATE_OPTIONS[0][0])
        self.offset_var = tk.DoubleVar(value=0.0)
        self.gain_var = tk.DoubleVar(value=1.05)
        self.play_after_var = tk.BooleanVar(value=True)
        self.status_var = tk.StringVar(
            value="Klaar! Kies links een .MP3 of .WAV op je PC, en rechts een MP3-Slot (#1..#8) of WAV-Slot (#1..#16) om om te zetten en op de SD-kaart te zetten."
        )
        self.progress_var = tk.DoubleVar(value=0.0)
        self.busy = False

        self.mp3_slots = []
        self.sd_slots = []
        self._init_mp3_slots_state()
        self._init_sd_slots_state()

        self._setup_styles()
        self._build_ui()
        self.refresh_ports()
        self.refresh_pc_list()
        self.refresh_mp3_tree()
        self.refresh_sd_tree()

    # =========================================================================
    # MP3 Directory State (Sector $2001, 8 slots voor MP3PLAY.asm)
    # =========================================================================
    def _init_mp3_slots_state(self):
        if os.path.exists(MP3_DIR_CACHE_PATH):
            try:
                raw = open(MP3_DIR_CACHE_PATH, "rb").read(512)
                if len(raw) == 512 and raw[0:4] == b"MP3!":
                    self._parse_mp3_dir_sector_bytes(raw)
                    return
            except Exception:
                pass

        self.mp3_slots = []
        for i, (title, st_sec, nbanks, rcode, dur) in enumerate(DEFAULT_MP3_SLOTS):
            self.mp3_slots.append(
                {
                    "slot": i + 1,
                    "title": title.ljust(15)[:15],
                    "start_sec": st_sec,
                    "num_secs": (nbanks * 128) & 0xFF,
                    "num_banks": nbanks,
                    "rate_code": rcode,
                    "dur_sec": dur,
                }
            )
        self._save_mp3_dir_cache()

    def _parse_mp3_dir_sector_bytes(self, raw512):
        slots = []
        for i in range(8):
            off = i * 32
            ent = raw512[off : off + 32]
            if ent[0:4] == b"MP3!":
                t_str = ent[4:19].split(b"\x00", 1)[0].decode("ascii", errors="replace").ljust(15)[:15]
                st_sec = ent[20] | (ent[21] << 8)
                n_sec = ent[22]
                n_banks = ent[23] if 1 <= ent[23] <= 30 else 2
                rcode = ent[24] if ent[24] in (1, 2, 3, 4) else 1
                dur = ent[25] if ent[25] > 0 else n_banks * 8
            else:
                t_str, st_sec, n_banks, rcode, dur = DEFAULT_MP3_SLOTS[i]
                n_sec = (n_banks * 128) & 0xFF
            slots.append(
                {
                    "slot": i + 1,
                    "title": t_str,
                    "start_sec": st_sec,
                    "num_secs": n_sec,
                    "num_banks": n_banks,
                    "rate_code": rcode,
                    "dur_sec": dur,
                }
            )
        self.mp3_slots = slots

    def _build_mp3_dir_sector_bytes(self):
        sec = bytearray(512)
        for i, s in enumerate(self.mp3_slots[:8]):
            off = i * 32
            sec[off : off + 4] = b"MP3!"
            tb = s["title"].encode("ascii", errors="ignore")[:15].ljust(15, b" ")
            sec[off + 4 : off + 19] = tb
            sec[off + 19] = 0
            sec[off + 20] = s["start_sec"] & 0xFF
            sec[off + 21] = (s["start_sec"] >> 8) & 0xFF
            sec[off + 22] = (128 if s["num_banks"] == 1 else 0) & 0xFF
            sec[off + 23] = s["num_banks"] & 0xFF
            sec[off + 24] = s["rate_code"] & 0xFF
            sec[off + 25] = min(255, max(1, s["dur_sec"])) & 0xFF
        return bytes(sec)

    def _save_mp3_dir_cache(self):
        try:
            with open(MP3_DIR_CACHE_PATH, "wb") as f:
                f.write(self._build_mp3_dir_sector_bytes())
        except Exception:
            pass

    # =========================================================================
    # WAV Directory State (Sector $2000, 16 slots voor WAV 1..16 & MP3PLAY Rechts)
    # =========================================================================
    def _init_sd_slots_state(self):
        if os.path.exists(DIR_CACHE_PATH):
            try:
                raw = open(DIR_CACHE_PATH, "rb").read(512)
                if len(raw) == 512 and raw[0:4] == b"WAV!":
                    self._parse_dir_sector_bytes(raw)
                    return
            except Exception:
                pass

        self.sd_slots = []
        for i in range(16):
            title, rcode = DEFAULT_SLOT_TITLES[i]
            sec = DEFAULT_SLOT_SECTORS[i]
            hz = RATE_CODE_TO_HZ.get(rcode, 8000)
            dur = max(1, int(round(32768 / hz)))
            self.sd_slots.append(
                {
                    "slot": i + 1,
                    "title": title,
                    "start_sec": sec,
                    "num_secs": 64,
                    "num_pages": 128,
                    "rate_code": rcode,
                    "dur_sec": dur,
                }
            )
        self._save_dir_cache()

    def _parse_dir_sector_bytes(self, raw512):
        slots = []
        for i in range(16):
            off = i * 32
            ent = raw512[off : off + 32]
            if ent[0:4] == b"WAV!":
                t_str = ent[4:19].split(b"\x00", 1)[0].decode("ascii", errors="replace").ljust(15)[:15]
                st_sec = ent[20] | (ent[21] << 8)
                n_sec = ent[22] if ent[22] > 0 else 64
                n_pg = ent[23] if ent[23] > 0 else 128
                rcode = ent[24] if ent[24] in (1, 2, 3, 4) else 1
                dur = ent[25] if ent[25] > 0 else 4
            else:
                t_str, rcode = DEFAULT_SLOT_TITLES[i]
                st_sec = DEFAULT_SLOT_SECTORS[i]
                n_sec, n_pg, dur = 64, 128, 4
            slots.append(
                {
                    "slot": i + 1,
                    "title": t_str,
                    "start_sec": st_sec,
                    "num_secs": n_sec,
                    "num_pages": n_pg,
                    "rate_code": rcode,
                    "dur_sec": dur,
                }
            )
        self.sd_slots = slots

    def _build_dir_sector_bytes(self):
        sec = bytearray(512)
        for i, s in enumerate(self.sd_slots[:16]):
            off = i * 32
            sec[off : off + 4] = b"WAV!"
            tb = s["title"].encode("ascii", errors="ignore")[:15].ljust(15, b" ")
            sec[off + 4 : off + 19] = tb
            sec[off + 19] = 0
            sec[off + 20] = s["start_sec"] & 0xFF
            sec[off + 21] = (s["start_sec"] >> 8) & 0xFF
            sec[off + 22] = s["num_secs"] & 0xFF
            sec[off + 23] = s["num_pages"] & 0xFF
            sec[off + 24] = s["rate_code"] & 0xFF
            sec[off + 25] = s["dur_sec"] & 0xFF
        return bytes(sec)

    def _save_dir_cache(self):
        try:
            with open(DIR_CACHE_PATH, "wb") as f:
                f.write(self._build_dir_sector_bytes())
        except Exception:
            pass

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
            rowheight=26,
            font=("Consolas", 10),
        )
        style.configure(
            "Treeview.Heading",
            background="#0f172a",
            foreground="#38bdf8",
            font=("Segoe UI", 10, "bold"),
        )
        style.map(
            "Treeview",
            background=[("selected", "#2563eb")],
            foreground=[("selected", "#ffffff")],
        )
        style.configure(
            "TNotebook",
            background="#0f172a",
            borderwidth=0,
        )
        style.configure(
            "TNotebook.Tab",
            background="#334155",
            foreground="#e2e8f0",
            padding=(12, 6),
            font=("Segoe UI", 10, "bold"),
        )
        style.map(
            "TNotebook.Tab",
            background=[("selected", "#0284c7")],
            foreground=[("selected", "#ffffff")],
        )
        style.configure(
            "Wav.Horizontal.TProgressbar",
            troughcolor="#0f172a",
            background="#22c55e",
            thickness=22,
        )

    def _make_btn(self, parent, text, cmd, bg="#334155", fg="#f8fafc", font=("Segoe UI", 9, "bold"), padx=10, pady=6):
        return tk.Button(
            parent,
            text=text,
            command=cmd,
            bg=bg,
            fg=fg,
            activebackground="#475569",
            activeforeground="#ffffff",
            relief=tk.FLAT,
            font=font,
            padx=padx,
            pady=pady,
            cursor="hand2",
        )

    def _build_ui(self):
        # === 1. BOVENBALK ===
        hdr = tk.Frame(self.root, bg="#1e293b", pady=8, padx=12, bd=1, relief=tk.GROOVE)
        hdr.pack(fill=tk.X, padx=10, pady=(8, 4))

        tk.Label(
            hdr,
            text="🎵 Tang Nano 20K — MP3 & WAV Converter + MicroSD Studio",
            font=("Segoe UI", 13, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
        ).pack(side=tk.LEFT, padx=(0, 14))

        tk.Label(hdr, text="COM-Poort:", font=("Segoe UI", 10, "bold"), fg="#e2e8f0", bg="#1e293b").pack(side=tk.LEFT)
        self.port_combo = ttk.Combobox(hdr, textvariable=self.port_var, width=8, font=("Consolas", 10))
        self.port_combo.pack(side=tk.LEFT, padx=5)
        self._make_btn(hdr, "🔄", self.refresh_ports, bg="#334155", padx=6, pady=4).pack(side=tk.LEFT, padx=(0, 10))

        self._make_btn(
            hdr,
            "🎧 Start MP3PLAY op Tang Nano",
            lambda: self.run_tang_command('SD : DRIVE 0 : BRUN "MP3PLAY"', "MP3Commander 2.1 gestart op Tang Nano!"),
            bg="#16a34a",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            hdr,
            "💿 Update MP3PLAY.asm op SD",
            self.upload_mp3play_binary_async,
            bg="#0284c7",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            hdr,
            "⏰ Start WEKKER",
            lambda: self.run_tang_command('SD : DRIVE 0 : BRUN "WEKKER"', "WEKKER gestart op Tang Nano!"),
            bg="#6d28d9",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            hdr,
            "🛑 Stop Geluid (ESC)",
            self.stop_tang_audio,
            bg="#dc2626",
        ).pack(side=tk.RIGHT, padx=4)

        # === 2. HOOFDPANEEL (Links PC Bestanden & Golfvorm | Rechts Tabs voor .MP3 en .WAV op MicroSD) ===
        paned = tk.PanedWindow(self.root, orient=tk.HORIZONTAL, bg="#0f172a", sashwidth=6, bd=0)
        paned.pack(fill=tk.BOTH, expand=True, padx=10, pady=4)

        # --- LINKER KOLOM: PC .MP3 & .WAV Bestanden & Golfvorm Editor ---
        left_frame = tk.LabelFrame(
            paned,
            text=" 💻 1. Kies een .MP3 of .WAV Bestand op je PC & Luister Vooraf ",
            font=("Segoe UI", 10, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
            padx=10,
            pady=8,
        )
        paned.add(left_frame, minsize=480, width=560)

        folder_bar = tk.Frame(left_frame, bg="#1e293b")
        folder_bar.pack(fill=tk.X, pady=(0, 6))

        self._make_btn(
            folder_bar,
            "📂 Blader .MP3 / .WAV...",
            self.browse_external_wav,
            bg="#2563eb",
        ).pack(side=tk.LEFT, padx=(0, 5))

        self._make_btn(
            folder_bar,
            "🎵 Map: Downloads (.MP3)",
            lambda: self.switch_pc_folder(DOWNLOADS_DIR),
            bg="#7c3aed",
        ).pack(side=tk.LEFT, padx=3)

        self._make_btn(
            folder_bar,
            "📁 Map: wav_tracks",
            lambda: self.switch_pc_folder(WAV_DIR),
            bg="#334155",
        ).pack(side=tk.LEFT, padx=3)

        self._make_btn(
            folder_bar,
            "🐄 Map: internet_samples",
            lambda: self.switch_pc_folder(INET_DIR),
            bg="#0f766e",
        ).pack(side=tk.LEFT, padx=3)

        pc_tree_wrap = tk.Frame(left_frame, bg="#0f172a")
        pc_tree_wrap.pack(fill=tk.BOTH, expand=True, pady=4)

        self.pc_tree = ttk.Treeview(
            pc_tree_wrap,
            columns=("name", "rate", "ch", "dur", "size"),
            show="headings",
            selectmode="browse",
            height=9,
        )
        self.pc_tree.heading("name", text="Bestandsnaam (.MP3 / .WAV)")
        self.pc_tree.heading("rate", text="Sample Rate")
        self.pc_tree.heading("ch", text="Type")
        self.pc_tree.heading("dur", text="Duur")
        self.pc_tree.heading("size", text="Grootte")

        self.pc_tree.column("name", width=230, anchor=tk.W)
        self.pc_tree.column("rate", width=80, anchor=tk.CENTER)
        self.pc_tree.column("ch", width=55, anchor=tk.CENTER)
        self.pc_tree.column("dur", width=65, anchor=tk.CENTER)
        self.pc_tree.column("size", width=75, anchor=tk.E)

        pc_sb = ttk.Scrollbar(pc_tree_wrap, orient=tk.VERTICAL, command=self.pc_tree.yview)
        self.pc_tree.configure(yscrollcommand=pc_sb.set)
        self.pc_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        pc_sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.pc_tree.bind("<<TreeviewSelect>>", self.on_pc_wav_selected)

        wave_box = tk.LabelFrame(
            left_frame,
            text=" 🌊 Golfvorm & Selectie-Venster (Groen = deel dat naar de MicroSD-kaart gaat) ",
            font=("Segoe UI", 9, "bold"),
            fg="#a7f3d0",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        wave_box.pack(fill=tk.X, pady=6)

        self.wave_canvas = tk.Canvas(
            wave_box, height=110, bg="#020617", highlightthickness=1, highlightbackground="#334155"
        )
        self.wave_canvas.pack(fill=tk.X, pady=(0, 6))
        self.wave_canvas.bind("<Configure>", lambda e: self.draw_waveform())

        sliders = tk.Frame(wave_box, bg="#1e293b")
        sliders.pack(fill=tk.X)

        tk.Label(sliders, text="Start-punt (sec):", font=("Segoe UI", 9, "bold"), fg="#cbd5e1", bg="#1e293b").grid(
            row=0, column=0, sticky="w"
        )
        self.offset_scale = tk.Scale(
            sliders,
            from_=0.0,
            to=10.0,
            resolution=0.1,
            orient=tk.HORIZONTAL,
            variable=self.offset_var,
            command=lambda _: self.draw_waveform(),
            bg="#1e293b",
            fg="#38bdf8",
            highlightthickness=0,
            troughcolor="#0f172a",
            length=190,
        )
        self.offset_scale.grid(row=0, column=1, padx=6)

        tk.Label(sliders, text="Volume (Gain):", font=("Segoe UI", 9, "bold"), fg="#cbd5e1", bg="#1e293b").grid(
            row=0, column=2, sticky="w", padx=(8, 0)
        )
        self.gain_scale = tk.Scale(
            sliders,
            from_=0.3,
            to=2.2,
            resolution=0.05,
            orient=tk.HORIZONTAL,
            variable=self.gain_var,
            command=lambda _: self.draw_waveform(),
            bg="#1e293b",
            fg="#4ade80",
            highlightthickness=0,
            troughcolor="#0f172a",
            length=140,
        )
        self.gain_scale.grid(row=0, column=3, padx=6)

        preview_bar = tk.Frame(wave_box, bg="#1e293b")
        preview_bar.pack(fill=tk.X, pady=(6, 2))

        self._make_btn(
            preview_bar,
            "🔊 Luister Origineel op PC",
            self.preview_original_on_pc,
            bg="#0284c7",
        ).pack(side=tk.LEFT, padx=(0, 6))

        self._make_btn(
            preview_bar,
            "🎧 Luister Gemasterde 8-bit Tang Nano Versie op PC",
            self.preview_converted_on_pc,
            bg="#16a34a",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            preview_bar,
            "⏹ Stop PC",
            lambda: winsound.PlaySound(None, winsound.SND_PURGE),
            bg="#475569",
        ).pack(side=tk.RIGHT)

        # --- RECHTER KOLOM: Notebook met Tab 1 (.MP3 Liedjes $2001) en Tab 2 (.WAV Geluiden $2000) ---
        right_wrap = tk.Frame(paned, bg="#0f172a")
        paned.add(right_wrap, minsize=560, width=680)

        self.notebook = ttk.Notebook(right_wrap)
        self.notebook.pack(fill=tk.BOTH, expand=True)
        self.notebook.bind("<<NotebookTabChanged>>", lambda e: self.draw_waveform())

        # =====================================================================
        # TAB 1: .MP3 LIEDJES (Sector $2001 — Linker Paneel in MP3PLAY #1..#8)
        # =====================================================================
        tab_mp3 = tk.Frame(self.notebook, bg="#1e293b", padx=10, pady=8)
        self.notebook.add(tab_mp3, text=" 🎵 1. MicroSD .MP3 Liedjes (MP3PLAY Linker Lijst #1..#8) ")

        mp3_tree_wrap = tk.Frame(tab_mp3, bg="#0f172a")
        mp3_tree_wrap.pack(fill=tk.BOTH, expand=True, pady=(0, 8))

        self.mp3_tree = ttk.Treeview(
            mp3_tree_wrap,
            columns=("slot", "title", "banks", "dur", "sector", "rate"),
            show="headings",
            selectmode="browse",
            height=9,
        )
        self.mp3_tree.heading("slot", text="MP3 Slot")
        self.mp3_tree.heading("title", text="Titel in MP3PLAY (15 tekens)")
        self.mp3_tree.heading("banks", text="SDRAM Banken / Grootte")
        self.mp3_tree.heading("dur", text="Speelduur")
        self.mp3_tree.heading("sector", text="SD Sectoren")
        self.mp3_tree.heading("rate", text="Sample Rate")

        self.mp3_tree.column("slot", width=70, anchor=tk.CENTER)
        self.mp3_tree.column("title", width=165, anchor=tk.W)
        self.mp3_tree.column("banks", width=140, anchor=tk.CENTER)
        self.mp3_tree.column("dur", width=85, anchor=tk.CENTER)
        self.mp3_tree.column("sector", width=115, anchor=tk.CENTER)
        self.mp3_tree.column("rate", width=80, anchor=tk.CENTER)

        mp3_sb = ttk.Scrollbar(mp3_tree_wrap, orient=tk.VERTICAL, command=self.mp3_tree.yview)
        self.mp3_tree.configure(yscrollcommand=mp3_sb.set)
        self.mp3_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        mp3_sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.mp3_tree.bind("<<TreeviewSelect>>", self.on_mp3_slot_selected)
        self.mp3_tree.bind("<Double-1>", lambda e: self.play_selected_mp3_slot_on_tang())

        # MP3 Configuratie Rij
        mp3_cfg = tk.LabelFrame(
            tab_mp3,
            text=" ⚙️ Instellingen voor .MP3 Conversie & SD-Kaart Upload (Sector $2001) ",
            font=("Segoe UI", 9, "bold"),
            fg="#fbbf24",
            bg="#1e293b",
            padx=10,
            pady=8,
        )
        mp3_cfg.pack(fill=tk.X, pady=(0, 6))

        r1 = tk.Frame(mp3_cfg, bg="#1e293b")
        r1.pack(fill=tk.X, pady=(0, 6))

        tk.Label(r1, text="Doel MP3-Slot (#1..#8):", font=("Segoe UI", 9, "bold"), fg="#fbbf24", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.mp3_slot_spin = tk.Spinbox(
            r1,
            from_=1,
            to=8,
            textvariable=self.mp3_slot_var,
            width=4,
            font=("Consolas", 11, "bold"),
            bg="#0f172a",
            fg="#38bdf8",
            command=self._on_mp3_slot_spin_changed,
        )
        self.mp3_slot_spin.pack(side=tk.LEFT, padx=(6, 14))

        tk.Label(r1, text="Naam in MP3PLAY (15 tekens):", font=("Segoe UI", 9, "bold"), fg="#e2e8f0", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.mp3_title_entry = tk.Entry(
            r1,
            textvariable=self.mp3_title_var,
            width=18,
            font=("Consolas", 11, "bold"),
            bg="#0f172a",
            fg="#4ade80",
            insertbackground="#38bdf8",
        )
        self.mp3_title_entry.pack(side=tk.LEFT, padx=(6, 12))

        r2 = tk.Frame(mp3_cfg, bg="#1e293b")
        r2.pack(fill=tk.X, pady=(0, 6))

        tk.Label(r2, text="Lengte van MP3 op SD:", font=("Segoe UI", 9, "bold"), fg="#a7f3d0", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.mp3_banks_combo = ttk.Combobox(
            r2,
            textvariable=self.mp3_banks_combo_var,
            values=[b[0] for b in MP3_BANK_OPTIONS],
            state="readonly",
            width=48,
            font=("Segoe UI", 9, "bold"),
        )
        self.mp3_banks_combo.pack(side=tk.LEFT, padx=(6, 10))
        self.mp3_banks_combo.bind("<<ComboboxSelected>>", lambda e: self._on_mp3_banks_changed())

        r3 = tk.Frame(mp3_cfg, bg="#1e293b")
        r3.pack(fill=tk.X, pady=(4, 0))

        self.mp3_upload_btn = self._make_btn(
            r3,
            "🚀 ZET GEKOZEN .MP3 OM & UPLOAD NAAR MP3PLAY-SLOT #1 OP SD-KAART",
            self.upload_selected_mp3_async,
            bg="#16a34a",
            font=("Segoe UI", 10, "bold"),
            padx=14,
            pady=8,
        )
        self.mp3_upload_btn.pack(side=tk.LEFT, padx=(0, 8))

        self._make_btn(
            r3,
            "▶ Speel dit MP3-Slot op Tang Nano",
            self.play_selected_mp3_slot_on_tang,
            bg="#0284c7",
            font=("Segoe UI", 9, "bold"),
            pady=8,
        ).pack(side=tk.LEFT, padx=4)

        # =====================================================================
        # TAB 2: .WAV GELUIDEN (Sector $2000 — Rechter Paneel in MP3PLAY #1..#16)
        # =====================================================================
        tab_wav = tk.Frame(self.notebook, bg="#1e293b", padx=10, pady=8)
        self.notebook.add(tab_wav, text=" 🔊 2. MicroSD .WAV Geluiden (WAV 1..16 & WEKKER #1..#16) ")

        sd_tree_wrap = tk.Frame(tab_wav, bg="#0f172a")
        sd_tree_wrap.pack(fill=tk.BOTH, expand=True, pady=(0, 8))

        self.sd_tree = ttk.Treeview(
            sd_tree_wrap,
            columns=("slot", "wekker", "title", "sector", "rate", "basic"),
            show="headings",
            selectmode="browse",
            height=11,
        )
        self.sd_tree.heading("slot", text="Slot")
        self.sd_tree.heading("wekker", text="Pagina / Toets")
        self.sd_tree.heading("title", text="Titel op SD (15 tekens)")
        self.sd_tree.heading("sector", text="SD Sector")
        self.sd_tree.heading("rate", text="Sample Rate")
        self.sd_tree.heading("basic", text="BASIC Commando")

        self.sd_tree.column("slot", width=55, anchor=tk.CENTER)
        self.sd_tree.column("wekker", width=110, anchor=tk.CENTER)
        self.sd_tree.column("title", width=155, anchor=tk.W)
        self.sd_tree.column("sector", width=110, anchor=tk.CENTER)
        self.sd_tree.column("rate", width=85, anchor=tk.CENTER)
        self.sd_tree.column("basic", width=90, anchor=tk.CENTER)

        sd_sb = ttk.Scrollbar(sd_tree_wrap, orient=tk.VERTICAL, command=self.sd_tree.yview)
        self.sd_tree.configure(yscrollcommand=sd_sb.set)
        self.sd_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sd_sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.sd_tree.bind("<<TreeviewSelect>>", self.on_sd_slot_selected)
        self.sd_tree.bind("<Double-1>", lambda e: self.play_selected_slot_on_tang())

        wav_cfg = tk.Frame(tab_wav, bg="#1e293b")
        wav_cfg.pack(fill=tk.X, pady=(0, 6))

        tk.Label(wav_cfg, text="WAV-Slot (#1..#16):", font=("Segoe UI", 9, "bold"), fg="#fbbf24", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.slot_spin = tk.Spinbox(
            wav_cfg,
            from_=1,
            to=16,
            textvariable=self.slot_var,
            width=4,
            font=("Consolas", 11, "bold"),
            bg="#0f172a",
            fg="#38bdf8",
            command=self._on_slot_spin_changed,
        )
        self.slot_spin.pack(side=tk.LEFT, padx=(6, 12))

        tk.Label(wav_cfg, text="Titel (15 tekens):", font=("Segoe UI", 9, "bold"), fg="#e2e8f0", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.title_entry = tk.Entry(
            wav_cfg,
            textvariable=self.title_var,
            width=17,
            font=("Consolas", 11, "bold"),
            bg="#0f172a",
            fg="#4ade80",
            insertbackground="#38bdf8",
        )
        self.title_entry.pack(side=tk.LEFT, padx=(6, 12))

        self.upload_btn = self._make_btn(
            wav_cfg,
            "🚀 Upload 32KB .WAV naar Slot #1",
            self.upload_selected_wav_async,
            bg="#2563eb",
            font=("Segoe UI", 9, "bold"),
            padx=12,
            pady=6,
        )
        self.upload_btn.pack(side=tk.LEFT, padx=4)

        sd_action_bar = tk.Frame(tab_wav, bg="#1e293b")
        sd_action_bar.pack(fill=tk.X)

        self._make_btn(
            sd_action_bar,
            "▶ Speel WAV-Slot (WAV nr)",
            self.play_selected_slot_on_tang,
            bg="#16a34a",
        ).pack(side=tk.LEFT, padx=(0, 4))

        self._make_btn(
            sd_action_bar,
            "🔁 Loop WAV-Slot (WAV nr,1,1)",
            self.loop_selected_slot_on_tang,
            bg="#0284c7",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            sd_action_bar,
            "📋 Lees WAV-Lijst ($2000)",
            lambda: self.read_sd_wav_list_async(silent=False),
            bg="#334155",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            sd_action_bar,
            "📦 Herstel 16 Standaard WAVs",
            self.upload_all_16_defaults_async,
            bg="#b45309",
        ).pack(side=tk.RIGHT)

        # === 3. ONDERPANEEL: Sample Rate + Voortgangsbalk ===
        bot = tk.Frame(self.root, bg="#1e293b", pady=8, padx=14, bd=1, relief=tk.GROOVE)
        bot.pack(fill=tk.X, padx=10, pady=(2, 6))

        tk.Label(bot, text="Sample Rate:", font=("Segoe UI", 10, "bold"), fg="#e2e8f0", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.rate_combo = ttk.Combobox(
            bot,
            textvariable=self.rate_combo_var,
            values=[r[0] for r in RATE_OPTIONS],
            state="readonly",
            width=30,
            font=("Segoe UI", 9, "bold"),
        )
        self.rate_combo.pack(side=tk.LEFT, padx=(6, 14))
        self.rate_combo.bind("<<ComboboxSelected>>", lambda e: self.draw_waveform())

        tk.Checkbutton(
            bot,
            text="Direct na upload starten in MP3PLAY op Tang Nano",
            variable=self.play_after_var,
            bg="#1e293b",
            fg="#a7f3d0",
            selectcolor="#0f172a",
            activebackground="#1e293b",
            font=("Segoe UI", 9, "bold"),
        ).pack(side=tk.LEFT, padx=(0, 14))

        self.pbar = ttk.Progressbar(
            bot,
            variable=self.progress_var,
            maximum=100.0,
            style="Wav.Horizontal.TProgressbar",
        )
        self.pbar.pack(side=tk.LEFT, fill=tk.X, expand=True)

        # === 4. STATUSBALK ===
        status_bar = tk.Frame(self.root, bg="#020617", pady=5, padx=12)
        status_bar.pack(fill=tk.X, side=tk.BOTTOM)
        tk.Label(
            status_bar,
            textvariable=self.status_var,
            font=("Segoe UI", 9, "bold"),
            fg="#38bdf8",
            bg="#020617",
        ).pack(side=tk.LEFT)

    # =========================================================================
    # Helpers voor Poorten, Bestanden & Golfvorm
    # =========================================================================
    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        if not ports:
            ports = ["COM6"]
        self.port_combo["values"] = ports
        if self.port_var.get() not in ports:
            self.port_var.set(sd_tools.find_tang_port("COM6"))

    def switch_pc_folder(self, folder):
        self.folder_var.set(folder)
        self.refresh_pc_list()

    def browse_external_wav(self):
        path = filedialog.askopenfilename(
            title="Kies een .MP3 of .WAV geluidsbestand om naar de Tang Nano 20K te uploaden",
            initialdir=self.folder_var.get(),
            filetypes=[("MP3 & WAV Audio Bestanden", "*.mp3 *.MP3 *.wav *.WAV"), ("Alle bestanden", "*.*")],
            parent=self.root,
        )
        if not path:
            return
        folder = os.path.dirname(path)
        self.folder_var.set(folder)
        self.refresh_pc_list(select_path=path)

    def refresh_pc_list(self, select_path=None):
        for item in self.pc_tree.get_children():
            self.pc_tree.delete(item)

        folder = self.folder_var.get()
        if not os.path.exists(folder):
            return

        # Als we in Downloads zitten, zoek ook in submappen (zoals MP3-albums!)
        found_files = []
        if os.path.normcase(folder) == os.path.normcase(DOWNLOADS_DIR):
            for root_d, _dirs, files in os.walk(folder):
                for f in files:
                    if f.lower().endswith((".mp3", ".wav")):
                        found_files.append(os.path.join(root_d, f))
        else:
            for f in os.listdir(folder):
                if f.lower().endswith((".mp3", ".wav")):
                    found_files.append(os.path.join(folder, f))

        wav_files = sorted(
            found_files,
            key=lambda p: (0 if p.lower().endswith(".mp3") else 1, os.path.basename(p).lower()),
        )
        selected_iid = None
        for idx, fpath in enumerate(wav_files):
            fname = os.path.basename(fpath)
            sz_kb = f"{os.path.getsize(fpath) / 1024.0:.0f} KB"
            if fpath.lower().endswith(".mp3"):
                sr_str, ch_str, dur = "44.1kHz", "MP3", "MP3"
            else:
                try:
                    with wave.open(fpath, "rb") as wf:
                        sr = wf.getframerate()
                        ch = wf.getnchannels()
                        nfr = wf.getnframes()
                        dur = f"{nfr / float(max(1, sr)):.1f}s"
                        sr_str = f"{sr} Hz"
                        ch_str = "WAV" if ch == 1 else f"{ch}ch"
                except Exception:
                    sr_str, ch_str, dur = "?", "WAV", "?"

            iid = f"pc_{idx}"
            self.pc_tree.insert("", tk.END, iid=iid, values=(fname, sr_str, ch_str, dur, sz_kb), tags=(fpath,))
            if select_path and os.path.normcase(fpath) == os.path.normcase(select_path):
                selected_iid = iid

        if not selected_iid and self.pc_tree.get_children():
            selected_iid = self.pc_tree.get_children()[0]
        if selected_iid:
            self.pc_tree.selection_set(selected_iid)
            self.pc_tree.see(selected_iid)
            self.on_pc_wav_selected()

    def _get_selected_rate_code_and_hz(self):
        val = self.rate_combo_var.get()
        for lbl, code, hz in RATE_OPTIONS:
            if lbl == val:
                return code, hz
        return 1, 8000

    def _get_selected_mp3_banks(self):
        val = self.mp3_banks_combo_var.get()
        _, target_hz = self._get_selected_rate_code_and_hz()
        for lbl, b in MP3_BANK_OPTIONS:
            if lbl == val:
                if b == 0:
                    # Bereken automatisch hoeveel banken van 64 KB nodig zijn voor het hele bestand vanaf Start-punt
                    rem_dur = max(1.0, self.raw_preview_dur - self.offset_var.get())
                    needed_bytes = rem_dur * target_hz
                    auto_banks = max(1, min(24, int(math.ceil(needed_bytes / 65536.0))))
                    return auto_banks
                return b
        return 2

    def _is_mp3_tab_active(self):
        try:
            return self.notebook.index(self.notebook.select()) == 0
        except Exception:
            return True

    def on_pc_wav_selected(self, event=None):
        sel = self.pc_tree.selection()
        if not sel:
            return
        iid = sel[0]
        fpath = self.pc_tree.item(iid, "tags")[0]
        self.selected_pc_file = fpath
        self._load_wav_for_preview(fpath)

        base = os.path.splitext(os.path.basename(fpath))[0]
        base = re.sub(r"^\d+[_.\-\s]*", "", base).replace("_", " ").replace("'", "").upper().strip()

        # Update zowel MP3-titel als WAV-titel suggestie
        m_slot = self.mp3_slot_var.get()
        ext_sfx = ".MP3" if len(base) <= 9 else ".MP"
        mp3_auto = f"{m_slot}.{base[:13 - len(ext_sfx)]}{ext_sfx}"[:15].ljust(15)
        self.mp3_title_var.set(mp3_auto)

        w_slot = self.slot_var.get()
        page_num = ((w_slot - 1) % 8) + 1
        wav_auto = f"{page_num}.{base}"[:15].ljust(15)
        self.title_var.set(wav_auto)

        self._update_mp3_upload_btn_text()
        self._update_upload_btn_text()

    def _load_wav_for_preview(self, fpath):
        try:
            self.status_var.set(f"Laden en decoderen van '{os.path.basename(fpath)}'...")
            self.root.update_idletasks()
            wav_p = wav_up.ensure_wav_file(fpath)
            with wave.open(wav_p, "rb") as wf:
                nch = wf.getnchannels()
                sw = wf.getsampwidth()
                sr = wf.getframerate()
                nfr = wf.getnframes()
                raw = wf.readframes(nfr)

            if sw == 1:
                samples = [(b - 128) / 128.0 for b in raw[::nch]]
            elif sw == 2:
                cnt = len(raw) // 2
                ints = struct.unpack(f"<{cnt}h", raw[: cnt * 2])
                if nch == 2:
                    samples = [(ints[i] + ints[i + 1]) / 65536.0 for i in range(0, len(ints) - 1, 2)]
                else:
                    samples = [ints[i] / 32768.0 for i in range(0, len(ints), nch)]
            else:
                samples = [0.0] * max(1, nfr)

            self.raw_preview_samples = samples
            self.raw_preview_sr = max(1, sr)
            self.raw_preview_dur = len(samples) / float(self.raw_preview_sr)

            max_off = max(0.0, round(self.raw_preview_dur - 1.0, 1))
            self.offset_scale.configure(to=max(1.0, max_off))
            if self.offset_var.get() > max_off:
                self.offset_var.set(0.0)
            self.draw_waveform()
            self.status_var.set(
                f"Geselecteerd: {os.path.basename(fpath)} — Duur: {int(self.raw_preview_dur // 60)}m{int(self.raw_preview_dur % 60):02d}s ({self.raw_preview_dur:.1f}s @ {sr} Hz)"
            )
        except Exception as e:
            self.status_var.set(f"Kon audiobestand niet lezen: {e}")

    def draw_waveform(self):
        c = self.wave_canvas
        c.delete("all")
        w = max(200, c.winfo_width())
        h = max(60, c.winfo_height())
        mid = h // 2

        c.create_line(0, mid, w, mid, fill="#1e293b", width=1)
        if not self.raw_preview_samples:
            c.create_text(w // 2, mid, text="Geen .MP3 of .WAV geselecteerd", fill="#64748b", font=("Consolas", 10))
            return

        _, target_hz = self._get_selected_rate_code_and_hz()
        if self._is_mp3_tab_active():
            nbanks = self._get_selected_mp3_banks()
            num_bytes = nbanks * 65536
        else:
            nbanks = 0
            num_bytes = 32768

        slice_dur = num_bytes / float(target_hz)
        total_dur = max(0.01, self.raw_preview_dur)
        start_s = self.offset_var.get()
        gain = self.gain_var.get()

        x0 = int((start_s / total_dur) * w)
        x1 = int(((start_s + slice_dur) / total_dur) * w)
        x0 = max(0, min(w, x0))
        x1 = max(x0 + 2, min(w, x1))
        c.create_rectangle(x0, 2, x1, h - 2, fill="#064e3b", outline="#10b981", width=1)

        n = len(self.raw_preview_samples)
        step = max(1, n // w)
        for x in range(w):
            idx0 = int((x / float(w)) * n)
            idx1 = min(n, idx0 + step)
            chunk = self.raw_preview_samples[idx0:idx1]
            if not chunk:
                continue
            pk = max(abs(v) for v in chunk) * gain
            pk = min(1.0, pk)
            dy = int(pk * (mid - 6))
            col = "#4ade80" if (x0 <= x <= x1) else "#38bdf8"
            c.create_line(x, mid - dy, x, mid + dy, fill=col)

        kb_lbl = f"{num_bytes // 1024} KB"
        c.create_text(
            8,
            10,
            anchor="nw",
            text=f"Bron: {os.path.basename(self.selected_pc_file or '')} ({self.raw_preview_dur:.1f}s) | Selectie: {start_s:.1f}s..{min(total_dur, start_s + slice_dur):.1f}s ({slice_dur:.1f}s = {kb_lbl} @ {target_hz} Hz)",
            fill="#f8fafc",
            font=("Consolas", 9, "bold"),
        )
        self._update_mp3_upload_btn_text()

    def build_converted_pcm(self, num_bytes):
        if not self.selected_pc_file or not os.path.exists(self.selected_pc_file):
            raise RuntimeError("Kies eerst links een .MP3- of .WAV-bestand!")
        _, target_hz = self._get_selected_rate_code_and_hz()
        start_s = self.offset_var.get()
        gain = self.gain_var.get()
        slice_dur = num_bytes / float(target_hz)

        flt = wav_up.load_real_wav_slice(
            self.selected_pc_file,
            start_s,
            slice_dur,
            num_bytes,
            target_rate=target_hz,
            gain=gain,
        )
        out = bytearray(num_bytes)
        for i, x in enumerate(flt):
            val = int(round(128.0 + x * 96.0))
            out[i] = max(24, min(232, val))
        return bytes(out), target_hz

    def preview_original_on_pc(self):
        if not self.selected_pc_file or not os.path.exists(self.selected_pc_file):
            return
        wav_p = wav_up.ensure_wav_file(self.selected_pc_file)
        winsound.PlaySound(wav_p, winsound.SND_FILENAME | winsound.SND_ASYNC)
        self.status_var.set(f"PC speelt origineel af: {os.path.basename(self.selected_pc_file)}")

    def preview_converted_on_pc(self):
        try:
            if self._is_mp3_tab_active():
                nbanks = self._get_selected_mp3_banks()
                num_bytes = nbanks * 65536
            else:
                num_bytes = 32768
            pcm, target_hz = self.build_converted_pcm(num_bytes)
            tmp_wav = os.path.join(tempfile.gettempdir(), "tang_nano_preview_8bit.wav")
            wav_up.save_pcm8_wav(tmp_wav, pcm, target_hz)
            winsound.PlaySound(tmp_wav, winsound.SND_FILENAME | winsound.SND_ASYNC)
            self.status_var.set(
                f"PC speelt gemasterde 8-bit ({target_hz} Hz, {num_bytes // 1024} KB = {num_bytes / target_hz:.1f}s) Tang Nano versie af!"
            )
        except Exception as e:
            messagebox.showerror("Voorluisteren mislukt", str(e), parent=self.root)

    # =========================================================================
    # Tab 1: MicroSD .MP3 Liedjes Tabel (#1 t/m #8, Sector $2001)
    # =========================================================================
    def refresh_mp3_tree(self):
        sel_slot = self.mp3_slot_var.get()
        for item in self.mp3_tree.get_children():
            self.mp3_tree.delete(item)

        target_iid = None
        for s in self.mp3_slots:
            idx = s["slot"]
            nb = s["num_banks"]
            kb = nb * 64
            banks_lbl = f"{nb} Bank{'en' if nb > 1 else ''} ({kb} KB)"
            dur_s = s["dur_sec"]
            dur_lbl = f"{dur_s // 60:02d}:{dur_s % 60:02d} ({dur_s}s)"
            sec_start = s["start_sec"]
            sec_end = sec_start + (nb * 128) - 1
            sec_lbl = f"${sec_start:04X}..${sec_end:04X}"
            hz = RATE_CODE_TO_HZ.get(s["rate_code"], 8000)
            iid = f"mp3_{idx}"
            self.mp3_tree.insert(
                "",
                tk.END,
                iid=iid,
                values=(f"MP3 #{idx}", s["title"], banks_lbl, dur_lbl, sec_lbl, f"{hz} Hz"),
            )
            if idx == sel_slot:
                target_iid = iid

        if target_iid:
            self.mp3_tree.selection_set(target_iid)
            self.mp3_tree.see(target_iid)

    def on_mp3_slot_selected(self, event=None):
        sel = self.mp3_tree.selection()
        if not sel:
            return
        idx = int(sel[0].split("_")[1])
        self.mp3_slot_var.set(idx)
        s = self.mp3_slots[idx - 1]
        if self.selected_pc_file:
            base = os.path.splitext(os.path.basename(self.selected_pc_file))[0]
            base = re.sub(r"^\d+[_.\-\s]*", "", base).replace("_", " ").replace("'", "").upper().strip()
            ext_sfx = ".MP3" if len(base) <= 9 else ".MP"
            self.mp3_title_var.set(f"{idx}.{base[:13 - len(ext_sfx)]}{ext_sfx}"[:15].ljust(15))
        else:
            self.mp3_title_var.set(s["title"])
        self._update_mp3_upload_btn_text()
        self.draw_waveform()

    def _on_mp3_slot_spin_changed(self):
        idx = self.mp3_slot_var.get()
        iid = f"mp3_{idx}"
        if iid in self.mp3_tree.get_children():
            self.mp3_tree.selection_set(iid)
            self.mp3_tree.see(iid)
            self.on_mp3_slot_selected()

    def _on_mp3_banks_changed(self):
        self._update_mp3_upload_btn_text()
        self.draw_waveform()

    def _update_mp3_upload_btn_text(self):
        if not hasattr(self, "mp3_upload_btn"):
            return
        slot = self.mp3_slot_var.get()
        nb = self._get_selected_mp3_banks()
        _, hz = self._get_selected_rate_code_and_hz()
        dur_s = int(round((nb * 65536) / float(hz)))
        self.mp3_upload_btn.configure(
            text=f"🚀 ZET .MP3 OM & UPLOAD NAAR MP3PLAY-SLOT #{slot} ({nb * 64} KB = {dur_s // 60}m{dur_s % 60:02d}s)"
        )

    # =========================================================================
    # Tab 2: MicroSD WAV-Bank (#1 t/m #16, Sector $2000)
    # =========================================================================
    def refresh_sd_tree(self):
        sel_slot = self.slot_var.get()
        for item in self.sd_tree.get_children():
            self.sd_tree.delete(item)

        target_iid = None
        for s in self.sd_slots:
            idx = s["slot"]
            page = "Pag 1/2" if idx <= 8 else "Pag 2/2"
            btn_nr = ((idx - 1) % 8) + 1
            wekker_lbl = f"{page} [#{btn_nr}]"
            sec_start = s["start_sec"]
            sec_end = sec_start + s["num_secs"] - 1
            sec_lbl = f"${sec_start:04X}..${sec_end:04X}"
            hz = RATE_CODE_TO_HZ.get(s["rate_code"], 8000)
            iid = f"sd_{idx}"
            self.sd_tree.insert(
                "",
                tk.END,
                iid=iid,
                values=(f"#{idx}", wekker_lbl, s["title"], sec_lbl, f"{hz} Hz", f"WAV {idx}"),
            )
            if idx == sel_slot:
                target_iid = iid

        if target_iid:
            self.sd_tree.selection_set(target_iid)
            self.sd_tree.see(target_iid)

    def on_sd_slot_selected(self, event=None):
        sel = self.sd_tree.selection()
        if not sel:
            return
        idx = int(sel[0].split("_")[1])
        self.slot_var.set(idx)
        s = self.sd_slots[idx - 1]
        for lbl, code, _ in RATE_OPTIONS:
            if code == s["rate_code"]:
                self.rate_combo_var.set(lbl)
                break
        if self.selected_pc_file:
            page_num = ((idx - 1) % 8) + 1
            base = os.path.splitext(os.path.basename(self.selected_pc_file))[0]
            base = re.sub(r"^\d+[_.\-\s]*", "", base).replace("_", " ").upper().strip()
            self.title_var.set(f"{page_num}.{base}"[:15].ljust(15))
        else:
            self.title_var.set(s["title"])
        self._update_upload_btn_text()
        self.draw_waveform()

    def _on_slot_spin_changed(self):
        idx = self.slot_var.get()
        iid = f"sd_{idx}"
        if iid in self.sd_tree.get_children():
            self.sd_tree.selection_set(iid)
            self.sd_tree.see(iid)
            self.on_sd_slot_selected()

    def _update_upload_btn_text(self):
        if not hasattr(self, "upload_btn"):
            return
        slot = self.slot_var.get()
        sec = self.sd_slots[slot - 1]["start_sec"]
        self.upload_btn.configure(text=f"🚀 Upload 32KB .WAV naar Slot #{slot} (${sec:04X})")

    # =========================================================================
    # Tang Nano Seriële Communicatie (Met automatische dummies_server vrijgave!)
    # =========================================================================
    def _acquire_serial_connection(self):
        """Geeft COM-poort automatisch vrij van dummies_server.py of basic_terminal.py."""
        try:
            req = urllib.request.Request(
                "http://127.0.0.1:8765/api/disconnect",
                data=b"{}",
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=1.5)
            time.sleep(0.3)
        except Exception:
            pass

        pid_file = os.path.join(BASE_DIR, ".basic_terminal.pid")
        had_terminal = False
        if os.path.exists(pid_file):
            try:
                old_pid = int(open(pid_file, encoding="utf-8").read().strip())
                res = subprocess.run(["taskkill", "/PID", str(old_pid), "/T", "/F"], capture_output=True)
                if res.returncode == 0:
                    had_terminal = True
                    time.sleep(0.35)
            except Exception:
                pass
        ser = serial.Serial(self.port_var.get(), 115200, timeout=0.25)
        return ser, had_terminal

    def _release_serial_connection(self, ser):
        try:
            ser.close()
        except Exception:
            pass
        try:
            port = self.port_var.get()
            req = urllib.request.Request(
                "http://127.0.0.1:8765/api/connect",
                data=f'{{"port":"{port}"}}'.encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=1.5)
        except Exception:
            pass

    # =========================================================================
    # Uploaden van .MP3 Liedje naar MP3PLAY Slot (#1..#8, Sector $2001)
    # =========================================================================
    def upload_selected_mp3_async(self):
        if self.busy:
            return
        if not self.selected_pc_file or not os.path.exists(self.selected_pc_file):
            messagebox.showwarning("Geen .MP3/.WAV gekozen", "Kies eerst links een .MP3- of .WAV-bestand!", parent=self.root)
            return

        slot = self.mp3_slot_var.get()
        title = self.mp3_title_var.get().upper().ljust(15)[:15]
        nbanks = self._get_selected_mp3_banks()
        rate_code, target_hz = self._get_selected_rate_code_and_hz()
        num_bytes = nbanks * 65536
        dur_sec = max(1, min(255, int(round(num_bytes / float(target_hz)))))

        # Kies start-sector op MicroSD:
        # <= 2 banken gebruikt de standaard snelle sectoren ($2410..$2890),
        # >= 3 banken (volledige liedjes tot 24 banken = 3072 sectoren) krijgt een eigen 4096-sectoren blok op $3000 + (slot-1)*$1000!
        if nbanks <= 2 and slot == 1:
            start_sec = 0x2410
        elif nbanks <= 2 and slot == 2:
            start_sec = 0x2510
        elif nbanks == 1 and slot >= 3:
            start_sec = DEFAULT_MP3_SLOTS[slot - 1][1]
        else:
            start_sec = 0x3000 + (slot - 1) * 0x1000

        def _worker():
            self.busy = True
            self.progress_var.set(1.0)
            try:
                self.status_var.set(
                    f"Converteren & Masteren van '{os.path.basename(self.selected_pc_file)}' naar {nbanks * 64} KB ({dur_sec}s @ {target_hz} Hz)..."
                )
                pcm_data, _ = self.build_converted_pcm(num_bytes)

                s_info = self.mp3_slots[slot - 1]
                s_info["title"] = title
                s_info["start_sec"] = start_sec
                s_info["num_banks"] = nbanks
                s_info["num_secs"] = (nbanks * 128) & 0xFF
                s_info["rate_code"] = rate_code
                s_info["dur_sec"] = dur_sec
                mp3_dir_bytes = self._build_mp3_dir_sector_bytes()
                self._save_mp3_dir_cache()
                self.root.after(0, self.refresh_mp3_tree)

                self.status_var.set(f"Verbinden met Tang Nano 20K op {self.port_var.get()} & SD-streamer ($7E00) laden...")
                _, streamer_code = sd_tools.assemble_6502_source(wav_up.STREAMER_ASM)
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(bytes([27]))
                    time.sleep(0.25)
                    ser.reset_input_buffer()
                    sd_tools.ensure_basic_prompt(ser)

                    wav_up.install_streamer_stub(ser, streamer_code)
                    self.progress_var.set(4.0)

                    # 1. Schrijf bijgewerkte MP3! Directory naar Sector $2001
                    self._stream_sectors_with_progress(ser, 0x2001, mp3_dir_bytes, 4.0, 2.0, "MP3-DIR $2001")

                    # 2. Schrijf alle sectoren van het .MP3-liedje in blokken van max 256 sectoren (128 KB)
                    total_secs = len(pcm_data) // 512
                    done_secs = 0
                    while done_secs < total_secs:
                        batch_secs = min(256, total_secs - done_secs)
                        chunk_bytes = pcm_data[done_secs * 512 : (done_secs + batch_secs) * 512]
                        base_p = 6.0 + (done_secs / float(total_secs)) * 92.0
                        span_p = (batch_secs / float(total_secs)) * 92.0
                        self._stream_sectors_with_progress(
                            ser,
                            start_sec + done_secs,
                            chunk_bytes,
                            base_p,
                            span_p,
                            f"MP3 #{slot}: {title.strip()} (${start_sec + done_secs:04X})",
                        )
                        done_secs += batch_secs

                    self.progress_var.set(100.0)
                    if self.play_after_var.get():
                        self.status_var.set(f"Starten van MP3PLAY op Tang Nano & afspelen van Slot #{slot} ({title.strip()})...")
                        wav_up.send_basic_line(ser, "SD : DRIVE 0", wait=0.4)
                        ser.write(b'BRUN "MP3PLAY"\r')
                        time.sleep(2.2)
                        if slot > 1:
                            ser.write(str(slot).encode("ascii"))
                            time.sleep(0.3)

                    self.status_var.set(
                        f"✅ Gelukt! '{title.strip()}' ({nbanks * 64} KB, {dur_sec // 60:02d}:{dur_sec % 60:02d}) staat op MicroSD MP3-Slot #{slot} (${start_sec:04X}) en speelt in MP3PLAY!"
                    )
                finally:
                    self._release_serial_connection(ser)
            except Exception as e:
                self.status_var.set(f"❌ MP3 Upload mislukt: {e}")
                messagebox.showerror("MP3 Upload Fout", str(e), parent=self.root)
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    def play_selected_mp3_slot_on_tang(self):
        if self.busy:
            return
        slot = self.mp3_slot_var.get()
        title = self.mp3_slots[slot - 1]["title"].strip()

        def _worker():
            self.busy = True
            try:
                self.status_var.set(f"Starten van MP3PLAY op Tang Nano en kiezen van MP3-Slot #{slot} ({title})...")
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(bytes([27]))
                    time.sleep(0.25)
                    ser.reset_input_buffer()
                    sd_tools.ensure_basic_prompt(ser)
                    wav_up.send_basic_line(ser, "SD : DRIVE 0", wait=0.4)
                    ser.write(b'BRUN "MP3PLAY"\r')
                    time.sleep(2.2)
                    if slot > 1:
                        ser.write(str(slot).encode("ascii"))
                        time.sleep(0.2)
                    self.status_var.set(f"🎵 MP3PLAY speelt nu MP3-Slot #{slot} ({title}) op je HDMI-monitor!")
                finally:
                    self._release_serial_connection(ser)
            except Exception as e:
                self.status_var.set(f"Fout bij starten MP3PLAY: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    def upload_mp3play_binary_async(self):
        if self.busy:
            return

        def _worker():
            self.busy = True
            self.progress_var.set(10.0)
            try:
                self.status_var.set("Assembleren en uploaden van MP3PLAY.asm / WAVPLAY.asm naar SD-kaart (D0/D1/D2)...")
                mp3_path = os.path.join(BASE_DIR, "sdcard", "MP3PLAY.asm")
                mp3_org, mp3_code = sd_tools.assemble_6502_source(open(mp3_path, encoding="utf-8").read())
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(bytes([27]))
                    time.sleep(0.25)
                    ser.reset_input_buffer()
                    sd_tools.ensure_basic_prompt(ser)
                    sd_tools.upload_file_to_sdcard(ser, mp3_path, run_after=False, media="SD", drive=0, save_to_sd=True)
                    self.progress_var.set(70.0)
                    for cmd in [
                        "DRIVE 0",
                        'DELETE "WAVPLAY"',
                        f'BSAVE "WAVPLAY",${mp3_org:04X},${len(mp3_code):04X}',
                        "DRIVE 1",
                        'DELETE "MP3PLAY"',
                        f'BSAVE "MP3PLAY",${mp3_org:04X},${len(mp3_code):04X}',
                        "DRIVE 2",
                        'DELETE "MP3PLAY"',
                        f'BSAVE "MP3PLAY",${mp3_org:04X},${len(mp3_code):04X}',
                        "DRIVE 0",
                    ]:
                        wav_up.send_basic_line(ser, cmd, wait=1.6 if "BSAVE" in cmd else 0.4)
                    self.progress_var.set(100.0)
                    ser.write(b'BRUN "MP3PLAY"\r')
                    time.sleep(1.0)
                    self.status_var.set(f"✅ MP3PLAY ({len(mp3_code)} bytes) opgeslagen op D0, D1, D2 en gestart!")
                finally:
                    self._release_serial_connection(ser)
            except Exception as e:
                self.status_var.set(f"❌ Fout bij uploaden MP3PLAY: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    # =========================================================================
    # WAV-Slot Acties (Sector $2000)
    # =========================================================================
    def read_sd_wav_list_async(self, silent=False):
        if self.busy:
            return

        def _worker():
            self.busy = True
            try:
                self.status_var.set(f"Lezen van WAV-Directory (Sector $2000) via {self.port_var.get()}...")
                ser, _ = self._acquire_serial_connection()
                try:
                    sd_tools.ensure_basic_prompt(ser)
                    ser.reset_input_buffer()
                    ser.write(b"WAV\r\n")
                    t0 = time.time()
                    buf = b""
                    while time.time() - t0 < 2.5:
                        chunk = ser.read(512)
                        if chunk:
                            buf += chunk
                            if b">" in chunk:
                                break
                    txt = buf.decode("ascii", errors="replace")
                    found = 0
                    for line in txt.splitlines():
                        m = re.match(r"^\s*#(\d+):\s*(.+)$", line.strip())
                        if m:
                            idx = int(m.group(1))
                            title = m.group(2).ljust(15)[:15]
                            if 1 <= idx <= 16:
                                self.sd_slots[idx - 1]["title"] = title
                                found += 1
                    self._save_dir_cache()
                    self.root.after(0, self.refresh_sd_tree)
                    if found > 0:
                        self.status_var.set(f"SD-kaart WAV-lijst geladen ({found} geluiden gevonden in Sector $2000).")
                    elif not silent:
                        self.status_var.set("Geen WAV-items ontvangen (controleer of de Tang Nano aan staat).")
                finally:
                    self._release_serial_connection(ser)
            except Exception as e:
                if not silent:
                    self.status_var.set(f"Kon SD WAV-lijst niet lezen: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    def play_selected_slot_on_tang(self):
        if self.busy:
            return
        slot = self.slot_var.get()
        title = self.sd_slots[slot - 1]["title"].strip()

        def _worker():
            self.busy = True
            try:
                self.status_var.set(f"Audio Hulp-CPU speelt nu WAV-Slot #{slot} ({title}) af (WAV {slot})...")
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(bytes([27]))
                    time.sleep(0.2)
                    sd_tools.ensure_basic_prompt(ser)
                    ser.write(f"WAV {slot}\r\n".encode("ascii"))
                    time.sleep(0.35)
                    self.status_var.set(f"🔊 WAV-Slot #{slot} ({title}) speelt nu op de Audio Hulp-CPU!")
                finally:
                    self._release_serial_connection(ser)
            except Exception as e:
                self.status_var.set(f"Fout bij afspelen op Tang Nano: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    def loop_selected_slot_on_tang(self):
        if self.busy:
            return
        slot = self.slot_var.get()
        title = self.sd_slots[slot - 1]["title"].strip()
        rate = self.sd_slots[slot - 1]["rate_code"]

        def _worker():
            self.busy = True
            try:
                self.status_var.set(f"Audio Hulp-CPU start eindeloze loop van WAV-Slot #{slot} ({title})...")
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(bytes([27]))
                    time.sleep(0.2)
                    sd_tools.ensure_basic_prompt(ser)
                    ser.write(f"WAV {slot},{rate},1\r\n".encode("ascii"))
                    time.sleep(0.35)
                    self.status_var.set(f"🔁 WAV-Slot #{slot} ({title}) loopt nu eindeloos op de Audio Hulp-CPU!")
                finally:
                    self._release_serial_connection(ser)
            except Exception as e:
                self.status_var.set(f"Fout bij loopen op Tang Nano: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    def stop_tang_audio(self):
        def _worker():
            try:
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(b"\x1b\r\nWAV 0\r\n")
                    time.sleep(0.2)
                finally:
                    self._release_serial_connection(ser)
                self.status_var.set("Stop-signaal (ESC + WAV 0) verzonden naar Tang Nano 20K.")
            except Exception as e:
                self.status_var.set(f"Fout bij stoppen: {e}")

        threading.Thread(target=_worker, daemon=True).start()

    def run_tang_command(self, cmd, msg):
        if self.busy:
            return

        def _worker():
            self.busy = True
            try:
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(bytes([27]))
                    time.sleep(0.25)
                    sd_tools.ensure_basic_prompt(ser)
                    ser.write(f"{cmd}\r\n".encode("ascii"))
                    time.sleep(0.4)
                finally:
                    self._release_serial_connection(ser)
                self.status_var.set(msg)
            except Exception as e:
                self.status_var.set(f"Fout: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    # =========================================================================
    # Laag-niveau Sector Streamer met Voortgangsbalk
    # =========================================================================
    def _stream_sectors_with_progress(self, ser, start_sector, data_bytes, base_pct, span_pct, label):
        num_sectors = len(data_bytes) // 512
        cnt_lo = num_sectors & 0xFF
        cnt_hi = ((num_sectors - 1) >> 8) + 1
        cmd = (
            f"POKE $0496,${start_sector & 0xFF:02X}:"
            f"POKE $0497,${(start_sector >> 8) & 0xFF:02X}:"
            f"POKE $60,${cnt_lo:02X}:POKE $61,${cnt_hi:02X}:CALL $7E00"
        )
        if ser.in_waiting:
            ser.read(ser.in_waiting)
        for ch in cmd:
            ser.write(ch.encode("ascii"))
            time.sleep(0.0005)
        ser.write(b"\r")

        t0 = time.time()
        echo_buf = b""
        while time.time() - t0 < 2.0:
            if ser.in_waiting:
                echo_buf += ser.read(1)
                if echo_buf.endswith(b"\n"):
                    break

        for s in range(num_sectors):
            t0 = time.time()
            got_r = False
            while time.time() - t0 < 3.0:
                if ser.read(1) == b"R":
                    got_r = True
                    break
            if not got_r:
                raise RuntimeError(f"Timeout bij wachten op 'R' voor sector {s + 1}/{num_sectors} ({label})")

            chunk = data_bytes[s * 512 : (s + 1) * 512]
            ser.write(chunk.hex().upper().encode("ascii"))

            pct = base_pct + ((s + 1) / float(num_sectors)) * span_pct
            self.progress_var.set(pct)
            if (s + 1) % 4 == 0 or (s + 1) == num_sectors:
                self.status_var.set(
                    f"[{label}] Sector {s + 1}/{num_sectors} ({(s + 1) // 2} / {len(data_bytes) // 1024} KB) naar MicroSD geschreven..."
                )

        t0 = time.time()
        tail = b""
        while time.time() - t0 < 3.0:
            if ser.in_waiting:
                tail += ser.read(ser.in_waiting)
                if b">" in tail:
                    break
            time.sleep(0.01)

    def upload_selected_wav_async(self):
        if self.busy:
            return
        if not self.selected_pc_file or not os.path.exists(self.selected_pc_file):
            messagebox.showwarning("Geen bestand gekozen", "Kies eerst links een .MP3- of .WAV-bestand!", parent=self.root)
            return

        slot = self.slot_var.get()
        title = self.title_var.get().upper().ljust(15)[:15]
        rate_code, target_hz = self._get_selected_rate_code_and_hz()
        dur_sec = max(1, int(round(32768.0 / target_hz)))

        try:
            pcm_32kb, _ = self.build_converted_pcm(32768)
        except Exception as e:
            messagebox.showerror("Conversie-fout", str(e), parent=self.root)
            return

        def _worker():
            self.busy = True
            self.progress_var.set(2.0)
            try:
                s_info = self.sd_slots[slot - 1]
                s_info["title"] = title
                s_info["rate_code"] = rate_code
                s_info["dur_sec"] = dur_sec
                start_sec = s_info["start_sec"]
                dir_bytes = self._build_dir_sector_bytes()
                self._save_dir_cache()
                self.root.after(0, self.refresh_sd_tree)

                self.status_var.set(f"Verbinden met Tang Nano 20K op {self.port_var.get()} & SD-streamer ($7E00) laden...")
                _, streamer_code = sd_tools.assemble_6502_source(wav_up.STREAMER_ASM)
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(bytes([27]))
                    time.sleep(0.25)
                    sd_tools.ensure_basic_prompt(ser)
                    wav_up.install_streamer_stub(ser, streamer_code)
                    self.progress_var.set(8.0)

                    self._stream_sectors_with_progress(ser, 0x2000, dir_bytes, 8.0, 4.0, "WAV-DIR $2000")
                    self._stream_sectors_with_progress(
                        ser,
                        start_sec,
                        pcm_32kb,
                        12.0,
                        88.0,
                        f"WAV #{slot}: {title.strip()} (${start_sec:04X})",
                    )

                    self.progress_var.set(100.0)
                    if self.play_after_var.get():
                        self.status_var.set(f"Upload voltooid! Nu live afspelen op Tang Nano: WAV {slot} ({title.strip()})...")
                        ser.write(f"WAV {slot}\r\n".encode("ascii"))
                        time.sleep(0.5)
                    self.status_var.set(
                        f"✅ Gelukt! '{title.strip()}' staat nu op SD-kaart WAV-Slot #{slot} (Sector ${start_sec:04X}). Typ in BASIC: WAV {slot}"
                    )
                finally:
                    self._release_serial_connection(ser)
            except Exception as e:
                self.status_var.set(f"❌ Upload mislukt: {e}")
                messagebox.showerror("Upload Fout", str(e), parent=self.root)
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    def upload_all_16_defaults_async(self):
        if self.busy:
            return
        if not messagebox.askyesno(
            "Alle 16 Standaard .WAVs Herstellen",
            "Wil je alle 16 standaard Boerderij-, Vogel- en Studio-.WAVs (512 KB totaal) opnieuw genereren en naar de MicroSD-kaart schrijven?",
            parent=self.root,
        ):
            return

        def _worker():
            self.busy = True
            self.progress_var.set(1.0)
            try:
                self.status_var.set("Genereren van alle 16 Boerderij, Vogel & Studio .WAV-tracks...")
                tracks = wav_up.generate_all_demo_wavs()
                dir_sector = wav_up.build_wav_directory_sector(tracks)
                self._parse_dir_sector_bytes(dir_sector)
                self._save_dir_cache()
                self.root.after(0, self.refresh_sd_tree)
                self.root.after(0, self.refresh_pc_list)

                _, streamer_code = sd_tools.assemble_6502_source(wav_up.STREAMER_ASM)
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(bytes([27]))
                    time.sleep(0.25)
                    sd_tools.ensure_basic_prompt(ser)
                    wav_up.install_streamer_stub(ser, streamer_code)
                    self._stream_sectors_with_progress(ser, 0x2000, dir_sector, 2.0, 2.0, "WAV-DIR $2000")
                    span = 96.0 / len(tracks)
                    for idx, (t_name, pcm, st_sec, _, _) in enumerate(tracks):
                        base = 4.0 + idx * span
                        self._stream_sectors_with_progress(
                            ser, st_sec, pcm, base, span, f"#{idx + 1} {t_name.strip()}"
                        )
                    self.progress_var.set(100.0)
                    self.status_var.set("✅ Alle 16 Boerderij-, Vogel- & Studio-.WAVs staan weer op de MicroSD-kaart!")
                finally:
                    self._release_serial_connection(ser)
            except Exception as e:
                self.status_var.set(f"❌ Fout bij herstellen van alle 16 .WAVs: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()


def main():
    root = tk.Tk()
    app = WavStudioGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()

The following is a <SYSTEM_MESSAGE> not actually sent by the user. It is provided by the system as important information to pay attention to.

<SYSTEM_MESSAGE>
[Message] timestamp=2026-11-07T19:25:17Z sender=7ba10d30-4f03-4127-9615-103973356754/task-1500 priority=MESSAGE_PRIORITY_HIGH content=Task id "7ba10d30-4f03-4127-9615-103973356754/task-1500" finished with result:
The tool's output was truncated due to being too long. You can find the full output in a file at file:///C:/Users/robte/.gemini/antigravity-cli/brain/7ba10d30-4f03-4127-9615-103973356754/.system_generated/steps/1500/output.txt.

Here is a preview with the middle of the output truncated:
Command exited with code 0.

Command output:
MP3PLAY.asm v2.1 assembled: ORG=$8000, LEN=3943 bytes
  Uploaden naar SDRAM $8000: 7/3943 bytes...  Uploaden naar SDRAM $8000: 14/3943 bytes...  Uploaden naar SDRAM $8000: 21/3943 bytes...  Uploaden naar SDRAM $8000: 28/3943 bytes...  Uploaden naar SDRAM $8000: 35/3943 bytes...  Uploaden naar SDRAM $8000: 42/3943 bytes...  Uploaden naar SDRAM $8000: 49/3943 bytes...  Uploaden naar SDRAM $8000: 56/3943 bytes...  Uploaden naar SDRAM $8000: 63/3943 bytes...  Uploaden naar SDRAM $8000: 70/3943 bytes...  Uploaden naar SDRAM $8000: 77/3943 bytes...  Uploaden naar SDRAM $8000: 84/3943 bytes...  Uploaden naar SDRAM $8000: 91/3943 bytes...  Uploaden naar SDRAM $8000: 98/3943 bytes...  Uploaden naar SDRAM $8000: 105/3943 bytes...  Uploaden naar SDRAM $8000: 112/3943 bytes...  Uploaden naar SDRAM $8000: 119/3943 bytes...  Uploaden naar SDRAM $8000: 126/3943 bytes...  Uploaden naar SDRAM $8000: 133/3943 bytes...  Uploaden naar SDRAM $8000: 140/3943 bytes...  Uploaden naar SDRAM $8000: 147/3943 bytes...  Uploaden naar SDRAM $8000: 154/3943 bytes...  Uploaden naar SDRAM $8000: 161/3943 bytes...  Uploaden naar SDRAM $8000: 168/3943 bytes...  Uploaden naar SDRAM $8000: 175/3943 bytes...  Uploaden naar SDRAM $8000: 182/3943 bytes...  Uploaden naar SDRAM $8000: 189/3943 bytes...  Uploaden naar SDRAM $8000: 196/3943 bytes...  Uploaden naar SDRAM $8000: 203/3943 bytes...  Uploaden naar SDRAM $8000: 210/3943 bytes...  Uploaden naar SDRAM $8000: 217/3943 bytes...  Uploaden naar SDRAM $8000: 224/3943 bytes...  Uploaden naar SDRAM $8000: 231/3943 bytes...  Uploaden naar SDRAM $8000: 238/3943 bytes...  Uploaden naar SDRAM $8000: 245/3943 bytes...  Uploaden naar SDRAM $8000: 252/3943 bytes...  Uploaden naar SDRAM $8000: 259/3943 bytes...  Uploaden naar SDRAM $8000: 266/3943 bytes...  Uploaden naar SDRAM $8000: 273/3943 bytes...  Uploaden naar SDRAM $8000: 280/3943 bytes...  Uploaden naar SDRAM $8000: 287/3943 bytes...  Uploaden naar SDRAM $8000: 294/3943 bytes...  Uploaden naar SDRAM $8000: 301/3943 bytes...  Uploaden naar SDRAM $8000: 308/3943 bytes...  Uploaden naar SDRAM $8000: 315/3943 bytes...  Uploaden naar SDRAM $8000: 322/3943 bytes...  Uploaden naar SDRAM $8000: 329/3943 bytes...  Uploaden naar SDRAM $8000: 336/3943 bytes...  Uploaden naar SDRAM $8000: 343/3943 bytes...  Uploaden naar SDRAM $8000: 350/3943 bytes...  Uploaden naar SDRAM $8000: 357/3943 bytes...  Uploaden naar SDRAM $8000: 364/3943 bytes...  Uploaden naar SDRAM $8000: 371/3943 bytes...  Uploaden naar SDRAM $8000: 378/3943 bytes...  Uploaden naar SDRAM $8000: 385/3943 bytes...  Uploaden naar SDRAM $8000: 392/3943 bytes...  Uploaden naar SDRAM $8000: 399/3943 bytes...  Uploaden naar SDRAM $8000: 406/3943 bytes...  Uploaden naar SDRAM $8000: 413/3943 bytes...  Uploaden naar SDRAM $8000: 420/3943 bytes...  Uploaden naar SDRAM $8000: 427/3943 bytes...  Uploaden naar SDRAM $8000: 434/3943 bytes...  Uploaden naar SDRAM $8000: 441/3943 bytes...  Uploaden naar SDRAM $8000: 448/3943 bytes...  Uploaden naar SDRAM $8000: 455/3943 bytes...  Uploaden naar SDRAM $8000: 462/3943 bytes...  Uploaden naar SDRAM $8000: 469/3943 bytes...  Uploaden naar SDRAM $8000: 476/3943 bytes...  Uploaden naar SDRAM $8000: 483/3943 bytes...  Uploaden naar SDRAM $8000: 490/3943 bytes...  Uploaden naar SDRAM $8000: 497/3943 bytes...  Uploaden naar SDRAM $8000: 504/3943 bytes...  Uploaden naar SDRAM $8000: 511/3943 bytes...  Uploaden naar SDRAM $8000: 518/3943 bytes...  Uploaden naar SDRAM $8000: 525/3943 bytes...  Uploaden naar SDRAM $8000: 532/3943 bytes...  Uploaden naar SDRAM $8000: 539/3943 bytes...  Uploaden naar SDRAM $8000: 546/3943 bytes...  Uploaden naar SDRAM $8000: 553/3943 bytes...  Uploaden naar SDRAM $8000: 560/3943 bytes...  Uploaden naar SDRAM $8000: 567/3943 bytes...  Uploaden naar SDRAM $8000: 574/3943 bytes...  Uploaden naar SDRAM $8000: 581/3943 bytes...  Uploaden naar SDRAM $8000: 588/3943 bytes...  Uploaden naar SDRAM $8000: 595/3943 bytes...  Uploaden naar SDRAM $8000: 602/3943 bytes...  Uploaden naar SDRAM $8000: 609/3943 bytes...  Uploaden naar SDRAM $8000: 616/3943 bytes...  Uploaden naar SDRAM $8000: 623/3943 bytes...  Uploaden naar SDRAM $8000: 630/3943 bytes...  Uploaden naar SDRAM $8000: 637/3943 bytes...  Uploaden naar SDRAM $8000: 644/3943 bytes...  Uploaden naar SDRAM $8000: 651/3943 bytes...  Uploaden naar SDRAM $8000: 658/3943 bytes...  Uploaden naar SDRAM $8000: 665/3943 bytes...  Uploaden naar SDRAM $8000: 672/3943 bytes...  Uploaden naar SDRAM $8000: 679/3943 bytes...  Uploaden naar SDRAM $8000: 686/3943 bytes...  Uploaden naar SDRAM $8000: 693/3943 bytes...  Uploaden naar SDRAM $8000: 700/3943 bytes...  Uploaden naar SDRAM $8000: 707/3943 
<truncated 18602 of 28505 bytes from the middle of the output>
bytes...  Uploaden naar SDRAM $8000: 3325/3943 bytes...  Uploaden naar SDRAM $8000: 3332/3943 bytes...  Uploaden naar SDRAM $8000: 3339/3943 bytes...  Uploaden naar SDRAM $8000: 3346/3943 bytes...  Uploaden naar SDRAM $8000: 3353/3943 bytes...  Uploaden naar SDRAM $8000: 3360/3943 bytes...  Uploaden naar SDRAM $8000: 3367/3943 bytes...  Uploaden naar SDRAM $8000: 3374/3943 bytes...  Uploaden naar SDRAM $8000: 3381/3943 bytes...  Uploaden naar SDRAM $8000: 3388/3943 bytes...  Uploaden naar SDRAM $8000: 3395/3943 bytes...  Uploaden naar SDRAM $8000: 3402/3943 bytes...  Uploaden naar SDRAM $8000: 3409/3943 bytes...  Uploaden naar SDRAM $8000: 3416/3943 bytes...  Uploaden naar SDRAM $8000: 3423/3943 bytes...  Uploaden naar SDRAM $8000: 3430/3943 bytes...  Uploaden naar SDRAM $8000: 3437/3943 bytes...  Uploaden naar SDRAM $8000: 3444/3943 bytes...  Uploaden naar SDRAM $8000: 3451/3943 bytes...  Uploaden naar SDRAM $8000: 3458/3943 bytes...  Uploaden naar SDRAM $8000: 3465/3943 bytes...  Uploaden naar SDRAM $8000: 3472/3943 bytes...  Uploaden naar SDRAM $8000: 3479/3943 bytes...  Uploaden naar SDRAM $8000: 3486/3943 bytes...  Uploaden naar SDRAM $8000: 3493/3943 bytes...  Uploaden naar SDRAM $8000: 3500/3943 bytes...  Uploaden naar SDRAM $8000: 3507/3943 bytes...  Uploaden naar SDRAM $8000: 3514/3943 bytes...  Uploaden naar SDRAM $8000: 3521/3943 bytes...  Uploaden naar SDRAM $8000: 3528/3943 bytes...  Uploaden naar SDRAM $8000: 3535/3943 bytes...  Uploaden naar SDRAM $8000: 3542/3943 bytes...  Uploaden naar SDRAM $8000: 3549/3943 bytes...  Uploaden naar SDRAM $8000: 3556/3943 bytes...  Uploaden naar SDRAM $8000: 3563/3943 bytes...  Uploaden naar SDRAM $8000: 3570/3943 bytes...  Uploaden naar SDRAM $8000: 3577/3943 bytes...  Uploaden naar SDRAM $8000: 3584/3943 bytes...  Uploaden naar SDRAM $8000: 3591/3943 bytes...  Uploaden naar SDRAM $8000: 3598/3943 bytes...  Uploaden naar SDRAM $8000: 3605/3943 bytes...  Uploaden naar SDRAM $8000: 3612/3943 bytes...  Uploaden naar SDRAM $8000: 3619/3943 bytes...  Uploaden naar SDRAM $8000: 3626/3943 bytes...  Uploaden naar SDRAM $8000: 3633/3943 bytes...  Uploaden naar SDRAM $8000: 3640/3943 bytes...  Uploaden naar SDRAM $8000: 3647/3943 bytes...  Uploaden naar SDRAM $8000: 3654/3943 bytes...  Uploaden naar SDRAM $8000: 3661/3943 bytes...  Uploaden naar SDRAM $8000: 3668/3943 bytes...  Uploaden naar SDRAM $8000: 3675/3943 bytes...  Uploaden naar SDRAM $8000: 3682/3943 bytes...  Uploaden naar SDRAM $8000: 3689/3943 bytes...  Uploaden naar SDRAM $8000: 3696/3943 bytes...  Uploaden naar SDRAM $8000: 3703/3943 bytes...  Uploaden naar SDRAM $8000: 3710/3943 bytes...  Uploaden naar SDRAM $8000: 3717/3943 bytes...  Uploaden naar SDRAM $8000: 3724/3943 bytes...  Uploaden naar SDRAM $8000: 3731/3943 bytes...  Uploaden naar SDRAM $8000: 3738/3943 bytes...  Uploaden naar SDRAM $8000: 3745/3943 bytes...  Uploaden naar SDRAM $8000: 3752/3943 bytes...  Uploaden naar SDRAM $8000: 3759/3943 bytes...  Uploaden naar SDRAM $8000: 3766/3943 bytes...  Uploaden naar SDRAM $8000: 3773/3943 bytes...  Uploaden naar SDRAM $8000: 3780/3943 bytes...  Uploaden naar SDRAM $8000: 3787/3943 bytes...  Uploaden naar SDRAM $8000: 3794/3943 bytes...  Uploaden naar SDRAM $8000: 3801/3943 bytes...  Uploaden naar SDRAM $8000: 3808/3943 bytes...  Uploaden naar SDRAM $8000: 3815/3943 bytes...  Uploaden naar SDRAM $8000: 3822/3943 bytes...  Uploaden naar SDRAM $8000: 3829/3943 bytes...  Uploaden naar SDRAM $8000: 3836/3943 bytes...  Uploaden naar SDRAM $8000: 3843/3943 bytes...  Uploaden naar SDRAM $8000: 3850/3943 bytes...  Uploaden naar SDRAM $8000: 3857/3943 bytes...  Uploaden naar SDRAM $8000: 3864/3943 bytes...  Uploaden naar SDRAM $8000: 3871/3943 bytes...  Uploaden naar SDRAM $8000: 3878/3943 bytes...  Uploaden naar SDRAM $8000: 3885/3943 bytes...  Uploaden naar SDRAM $8000: 3892/3943 bytes...  Uploaden naar SDRAM $8000: 3899/3943 bytes...  Uploaden naar SDRAM $8000: 3906/3943 bytes...  Uploaden naar SDRAM $8000: 3913/3943 bytes...  Uploaden naar SDRAM $8000: 3920/3943 bytes...  Uploaden naar SDRAM $8000: 3927/3943 bytes...  Uploaden naar SDRAM $8000: 3934/3943 bytes...  Uploaden naar SDRAM $8000: 3941/3943 bytes...  Uploaden naar SDRAM $8000: 3943/3943 bytes...
F67
[SD-KAART D0] Opgeslagen!
>
  DRIVE 0 -> ['>']
  DELETE "MP3PLAY" -> ['>']
  BSAVE "MP3PLAY",$8000,$0F67 -> ['>']
  DRIVE 1 -> ['>']
  DELETE "WAVPLAY" -> ['>']
  BSAVE "WAVPLAY",$8000,$0F67 -> ['>']
  DELETE "MP3PLAY" -> ['>']
  BSAVE "MP3PLAY",$8000,$0F67 -> ['>']
  DRIVE 2 -> ['>']
  DELETE "MP3PLAY" -> ['>']
  BSAVE "MP3PLAY",$8000,$0F67 -> ['>']
  DRIVE 0 -> ['>']
Done! MP3PLAY v2.1 running live on COM6.

Log: file:///C:/Users/robte/.gemini/antigravity-cli/brain/7ba10d30-4f03-4127-9615-103973356754/.system_generated/tasks/task-1500.log
</SYSTEM_MESSAGE>