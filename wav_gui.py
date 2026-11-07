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
import wave
import winsound

import serial
import serial.tools.list_ports

import sd_tools
import upload_wav_sdcard as wav_up

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WAV_DIR = os.path.join(BASE_DIR, "wav_tracks")
INET_DIR = os.path.join(WAV_DIR, "internet_samples")
DIR_CACHE_PATH = os.path.join(WAV_DIR, "wav_dir_sector2000.bin")

RATE_OPTIONS = [
    ("1 — 8000 Hz (4.1 sec, Standaard)", 1, 8000),
    ("2 — 11025 Hz (3.0 sec, Helderder)", 2, 11025),
    ("3 — 16000 Hz (2.0 sec, Hoge Kwaliteit)", 3, 16000),
    ("4 — 22050 Hz (1.5 sec, Studio Hi-Fi)", 4, 22050),
]

RATE_CODE_TO_HZ = {1: 8000, 2: 11025, 3: 16000, 4: 22050}

# Vaste SD-kaart start-sectoren per slot (0..15), elk 64 sectoren (32 KB)
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


class WavStudioGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("🎵 MiniGPU WAV & MP3 Studio + Audio Hulp-CPU Uploader (Tang Nano 20K)")
        self.root.geometry("1260x820")
        self.root.minsize(1060, 680)
        self.root.configure(bg="#0f172a")

        os.makedirs(WAV_DIR, exist_ok=True)
        os.makedirs(INET_DIR, exist_ok=True)

        self.port_var = tk.StringVar(value=sd_tools.find_tang_port("COM6"))
        self.folder_var = tk.StringVar(value=WAV_DIR)
        self.selected_pc_file = None
        self.raw_preview_samples = []  # Normalized floats -1..1 from selected PC WAV
        self.raw_preview_sr = 8000
        self.raw_preview_dur = 0.0

        self.slot_var = tk.IntVar(value=1)  # 1..16
        self.title_var = tk.StringVar(value="1.BOERDERIJ WEI")
        self.rate_combo_var = tk.StringVar(value=RATE_OPTIONS[0][0])
        self.offset_var = tk.DoubleVar(value=0.0)
        self.gain_var = tk.DoubleVar(value=1.0)
        self.play_after_var = tk.BooleanVar(value=True)
        self.status_var = tk.StringVar(
            value="Klaar. Kies links een .WAV-bestand en rechts een SD-slot (#1 t/m #16) om te uploaden of af te spelen."
        )
        self.progress_var = tk.DoubleVar(value=0.0)
        self.busy = False

        # In-memory state of the 16 SD WAV slots
        self.sd_slots = []
        self._init_sd_slots_state()

        self._setup_styles()
        self._build_ui()
        self.refresh_ports()
        self.refresh_pc_list()
        self.refresh_sd_tree()

        # Lees bij het starten automatisch de WAV-lijst van de Tang Nano als de poort vrij is
        self.root.after(400, lambda: self.read_sd_wav_list_async(silent=True))

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
            rowheight=27,
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
            "Wav.Horizontal.TProgressbar",
            troughcolor="#0f172a",
            background="#22c55e",
            thickness=20,
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
            text="🎵 MiniGPU WAV Studio & SD Audio Uploader",
            font=("Segoe UI", 14, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
        ).pack(side=tk.LEFT, padx=(0, 16))

        tk.Label(hdr, text="COM-Poort:", font=("Segoe UI", 10, "bold"), fg="#e2e8f0", bg="#1e293b").pack(side=tk.LEFT)
        self.port_combo = ttk.Combobox(hdr, textvariable=self.port_var, width=9, font=("Consolas", 10))
        self.port_combo.pack(side=tk.LEFT, padx=6)
        self._make_btn(hdr, "🔄 Poort", self.refresh_ports, bg="#334155", pady=4).pack(side=tk.LEFT, padx=(0, 12))

        self._make_btn(
            hdr,
            "📋 Lees SD WAV-Lijst ($2000)",
            lambda: self.read_sd_wav_list_async(silent=False),
            bg="#0284c7",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            hdr,
            "⏰ Start WEKKER op Tang Nano",
            lambda: self.run_tang_command('BRUN "WEKKER"', "WEKKER v6.0 gestart op Tang Nano!"),
            bg="#15803d",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            hdr,
            "🎹 Start WAVPLAY op Tang Nano",
            lambda: self.run_tang_command('BRUN "WAVPLAY"', "WAVPLAY gestart op Tang Nano!"),
            bg="#6d28d9",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            hdr,
            "🛑 Stop Geluid (ESC)",
            self.stop_tang_audio,
            bg="#dc2626",
        ).pack(side=tk.RIGHT, padx=4)

        # === 2. HOOFDPANEEL (Links PC WAVs + Golfvorm | Rechts MicroSD Slots #1..#16) ===
        paned = tk.PanedWindow(self.root, orient=tk.HORIZONTAL, bg="#0f172a", sashwidth=6, bd=0)
        paned.pack(fill=tk.BOTH, expand=True, padx=10, pady=4)

        # --- LINKER KOLOM: PC .WAV & .MP3 Bestanden & Golfvorm Editor ---
        left_frame = tk.LabelFrame(
            paned,
            text=" 💻 1. Kies .MP3 of .WAV Bestand op je PC & Luister Vooraf ",
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
            "📂 Kies .MP3 of .WAV van PC...",
            self.browse_external_wav,
            bg="#2563eb",
        ).pack(side=tk.LEFT, padx=(0, 6))

        self._make_btn(
            folder_bar,
            "📁 Map: wav_tracks",
            lambda: self.switch_pc_folder(WAV_DIR),
            bg="#334155",
        ).pack(side=tk.LEFT, padx=3)

        self._make_btn(
            folder_bar,
            "🐄 Map: internet_samples (44.1 kHz)",
            lambda: self.switch_pc_folder(INET_DIR),
            bg="#0f766e",
        ).pack(side=tk.LEFT, padx=3)

        # Tabel met PC .WAV bestanden
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
        self.pc_tree.heading("ch", text="Kanalen")
        self.pc_tree.heading("dur", text="Duur")
        self.pc_tree.heading("size", text="Grootte")

        self.pc_tree.column("name", width=210, anchor=tk.W)
        self.pc_tree.column("rate", width=85, anchor=tk.CENTER)
        self.pc_tree.column("ch", width=65, anchor=tk.CENTER)
        self.pc_tree.column("dur", width=65, anchor=tk.CENTER)
        self.pc_tree.column("size", width=75, anchor=tk.E)

        pc_sb = ttk.Scrollbar(pc_tree_wrap, orient=tk.VERTICAL, command=self.pc_tree.yview)
        self.pc_tree.configure(yscrollcommand=pc_sb.set)
        self.pc_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        pc_sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.pc_tree.bind("<<TreeviewSelect>>", self.on_pc_wav_selected)

        # Golfvorm (Oscilloscoop) + Voorluister-knoppen
        wave_box = tk.LabelFrame(
            left_frame,
            text=" 🌊 Golfvorm & 32 KB Selectie-Venster (Groen = stuk dat naar Tang Nano gaat) ",
            font=("Segoe UI", 9, "bold"),
            fg="#a7f3d0",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        wave_box.pack(fill=tk.X, pady=6)

        self.wave_canvas = tk.Canvas(wave_box, height=110, bg="#020617", highlightthickness=1, highlightbackground="#334155")
        self.wave_canvas.pack(fill=tk.X, pady=(0, 6))
        self.wave_canvas.bind("<Configure>", lambda e: self.draw_waveform())

        # Sliders voor Start-offset en Volume/Gain
        sliders = tk.Frame(wave_box, bg="#1e293b")
        sliders.pack(fill=tk.X)

        tk.Label(sliders, text="Start-punt (sec):", font=("Segoe UI", 9, "bold"), fg="#cbd5e1", bg="#1e293b").grid(
            row=0, column=0, sticky="w"
        )
        self.offset_scale = tk.Scale(
            sliders,
            from_=0.0,
            to=10.0,
            resolution=0.05,
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
            from_=0.2,
            to=2.5,
            resolution=0.05,
            orient=tk.HORIZONTAL,
            variable=self.gain_var,
            command=lambda _: self.draw_waveform(),
            bg="#1e293b",
            fg="#4ade80",
            highlightthickness=0,
            troughcolor="#0f172a",
            length=150,
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
            "🎧 Luister 8-bit Tang Nano Versie op PC",
            self.preview_converted_on_pc,
            bg="#16a34a",
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            preview_bar,
            "⏹ Stop PC Audio",
            lambda: winsound.PlaySound(None, winsound.SND_PURGE),
            bg="#475569",
        ).pack(side=tk.RIGHT)

        # --- RECHTER KOLOM: MicroSD WAV-Bank (Sector $2000, Slots #1..#16) ---
        right_frame = tk.LabelFrame(
            paned,
            text=" 💾 2. MicroSD WAV-Bank (Sector $2000 — BASIC: WAV 1..16 & WEKKER Lijst 1/2) ",
            font=("Segoe UI", 10, "bold"),
            fg="#fbbf24",
            bg="#1e293b",
            padx=10,
            pady=8,
        )
        paned.add(right_frame, minsize=500, width=620)

        sd_tree_wrap = tk.Frame(right_frame, bg="#0f172a")
        sd_tree_wrap.pack(fill=tk.BOTH, expand=True, pady=(0, 8))

        self.sd_tree = ttk.Treeview(
            sd_tree_wrap,
            columns=("slot", "wekker", "title", "sector", "rate", "basic"),
            show="headings",
            selectmode="browse",
            height=16,
        )
        self.sd_tree.heading("slot", text="Slot")
        self.sd_tree.heading("wekker", text="Wekker Pagina")
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

        sd_action_bar = tk.Frame(right_frame, bg="#1e293b")
        sd_action_bar.pack(fill=tk.X)

        self._make_btn(
            sd_action_bar,
            "▶ Speel Slot op Hulp-CPU (WAV nr)",
            self.play_selected_slot_on_tang,
            bg="#16a34a",
            font=("Segoe UI", 9, "bold"),
        ).pack(side=tk.LEFT, padx=(0, 4))

        self._make_btn(
            sd_action_bar,
            "🔁 Loop op Hulp-CPU (WAV nr,1,1)",
            self.loop_selected_slot_on_tang,
            bg="#0284c7",
            font=("Segoe UI", 9, "bold"),
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            sd_action_bar,
            "🎶 Stream Lang MP3-Liedje (16s) naar Hulp-CPU",
            self.stream_long_mp3_to_hulp_cpu_async,
            bg="#7c3aed",
            font=("Segoe UI", 9, "bold"),
        ).pack(side=tk.LEFT, padx=4)

        self._make_btn(
            sd_action_bar,
            "📦 Herstel 16 Standaard",
            self.upload_all_16_defaults_async,
            bg="#b45309",
        ).pack(side=tk.RIGHT)

        # === 3. ONDERPANEEL: Upload Instellingen & Grote Upload-Knop ===
        bot = tk.Frame(self.root, bg="#1e293b", pady=10, padx=14, bd=1, relief=tk.GROOVE)
        bot.pack(fill=tk.X, padx=10, pady=(2, 6))

        cfg_row = tk.Frame(bot, bg="#1e293b")
        cfg_row.pack(fill=tk.X, pady=(0, 8))

        tk.Label(cfg_row, text="Doel-Slot op SD:", font=("Segoe UI", 10, "bold"), fg="#fbbf24", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.slot_spin = tk.Spinbox(
            cfg_row,
            from_=1,
            to=16,
            textvariable=self.slot_var,
            width=4,
            font=("Consolas", 11, "bold"),
            bg="#0f172a",
            fg="#38bdf8",
            command=self._on_slot_spin_changed,
        )
        self.slot_spin.pack(side=tk.LEFT, padx=(6, 16))

        tk.Label(cfg_row, text="Titel (max 15 tekens):", font=("Segoe UI", 10, "bold"), fg="#e2e8f0", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.title_entry = tk.Entry(
            cfg_row,
            textvariable=self.title_var,
            width=18,
            font=("Consolas", 11, "bold"),
            bg="#0f172a",
            fg="#4ade80",
            insertbackground="#38bdf8",
        )
        self.title_entry.pack(side=tk.LEFT, padx=(6, 16))

        tk.Label(cfg_row, text="Sample Rate:", font=("Segoe UI", 10, "bold"), fg="#e2e8f0", bg="#1e293b").pack(
            side=tk.LEFT
        )
        self.rate_combo = ttk.Combobox(
            cfg_row,
            textvariable=self.rate_combo_var,
            values=[r[0] for r in RATE_OPTIONS],
            state="readonly",
            width=32,
            font=("Segoe UI", 9, "bold"),
        )
        self.rate_combo.pack(side=tk.LEFT, padx=(6, 16))
        self.rate_combo.bind("<<ComboboxSelected>>", lambda e: self.draw_waveform())

        tk.Checkbutton(
            cfg_row,
            text="Direct na upload laten horen op Tang Nano",
            variable=self.play_after_var,
            bg="#1e293b",
            fg="#a7f3d0",
            selectcolor="#0f172a",
            activebackground="#1e293b",
            font=("Segoe UI", 9, "bold"),
        ).pack(side=tk.LEFT, padx=8)

        # Voortgangsbalk + Grote Upload Knop
        up_row = tk.Frame(bot, bg="#1e293b")
        up_row.pack(fill=tk.X)

        self.upload_btn = self._make_btn(
            up_row,
            "🚀 UPLOAD GEKOZEN .WAV NAAR SD-KAART SLOT #1 (32 KB)",
            self.upload_selected_wav_async,
            bg="#2563eb",
            font=("Segoe UI", 11, "bold"),
            padx=18,
            pady=8,
        )
        self.upload_btn.pack(side=tk.LEFT, padx=(0, 14))

        self.pbar = ttk.Progressbar(
            up_row,
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

        wav_files = sorted(
            [
                os.path.join(folder, f)
                for f in os.listdir(folder)
                if f.lower().endswith((".wav", ".mp3"))
            ],
            key=lambda p: (0 if p.lower().endswith(".mp3") else 1, os.path.basename(p).lower()),
        )
        selected_iid = None
        for idx, fpath in enumerate(wav_files):
            fname = os.path.basename(fpath)
            sz_kb = f"{os.path.getsize(fpath) / 1024.0:.1f} KB"
            try:
                wav_p = wav_up.ensure_wav_file(fpath)
                with wave.open(wav_p, "rb") as wf:
                    sr = wf.getframerate()
                    ch = wf.getnchannels()
                    nfr = wf.getnframes()
                    dur = f"{nfr / float(max(1, sr)):.1f}s"
                    sr_str = f"{sr} Hz"
                    ch_str = "MP3" if fpath.lower().endswith(".mp3") else ("Mono" if ch == 1 else f"{ch}ch")
            except Exception:
                sr_str, ch_str, dur = "?", "?", "?"

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

    def on_pc_wav_selected(self, event=None):
        sel = self.pc_tree.selection()
        if not sel:
            return
        iid = sel[0]
        fpath = self.pc_tree.item(iid, "tags")[0]
        self.selected_pc_file = fpath
        self._load_wav_for_preview(fpath)

        # Stel automatisch een nette 15-teken titel voor bij dit slot
        slot_num = self.slot_var.get()
        page_num = ((slot_num - 1) % 8) + 1
        base = os.path.splitext(os.path.basename(fpath))[0]
        base = re.sub(r"^\d+[_.\-\s]*", "", base).replace("_", " ").upper().strip()
        auto_title = f"{page_num}.{base}"[:15].ljust(15)
        self.title_var.set(auto_title)
        self._update_upload_btn_text()

    def _load_wav_for_preview(self, fpath):
        try:
            wav_p = wav_up.ensure_wav_file(fpath)
            with wave.open(wav_p, "rb") as wf:
                nch = wf.getnchannels()
                sw = wf.getsampwidth()
                sr = wf.getframerate()
                nfr = wf.getnframes()
                raw = wf.readframes(nfr)

            samples = []
            if sw == 1:
                for b in raw:
                    samples.append((b - 128) / 128.0)
            elif sw == 2:
                cnt = len(raw) // 2
                ints = struct.unpack(f"<{cnt}h", raw[: cnt * 2])
                samples = [x / 32768.0 for x in ints]
            else:
                samples = [0.0] * max(1, nfr)

            if nch > 1:
                mono = []
                for i in range(0, len(samples) - nch + 1, nch):
                    mono.append(sum(samples[i : i + nch]) / nch)
                samples = mono

            self.raw_preview_samples = samples
            self.raw_preview_sr = max(1, sr)
            self.raw_preview_dur = len(samples) / float(self.raw_preview_sr)

            max_off = max(0.0, round(self.raw_preview_dur - 0.5, 2))
            self.offset_scale.configure(to=max(0.5, max_off))
            if self.offset_var.get() > max_off:
                self.offset_var.set(0.0)
            self.draw_waveform()
        except Exception as e:
            self.status_var.set(f"Kon .WAV niet lezen: {e}")

    def draw_waveform(self):
        c = self.wave_canvas
        c.delete("all")
        w = max(200, c.winfo_width())
        h = max(60, c.winfo_height())
        mid = h // 2

        c.create_line(0, mid, w, mid, fill="#1e293b", width=1)
        if not self.raw_preview_samples:
            c.create_text(w // 2, mid, text="Geen .WAV geselecteerd", fill="#64748b", font=("Consolas", 10))
            return

        _, target_hz = self._get_selected_rate_code_and_hz()
        slice_dur = 32768.0 / float(target_hz)
        total_dur = max(0.01, self.raw_preview_dur)
        start_s = self.offset_var.get()
        gain = self.gain_var.get()

        # Teken groen selectie-venster (de 32.768 samples die naar de Tang Nano gaan)
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

        c.create_text(
            8,
            12,
            anchor="nw",
            text=f"Bron: {os.path.basename(self.selected_pc_file or '')} ({self.raw_preview_dur:.2f}s @ {self.raw_preview_sr} Hz)  |  Selectie: {start_s:.2f}s .. {start_s + slice_dur:.2f}s ({slice_dur:.1f}s @ {target_hz} Hz)",
            fill="#f8fafc",
            font=("Consolas", 9, "bold"),
        )

    def build_converted_32kb_pcm(self):
        """Converteer het geselecteerde .WAV-bestand met huidige Start-offset, Gain en Sample-rate naar 32.768 bytes 8-bit PCM."""
        if not self.selected_pc_file or not os.path.exists(self.selected_pc_file):
            raise RuntimeError("Kies eerst links een .WAV-bestand!")
        _, target_hz = self._get_selected_rate_code_and_hz()
        start_s = self.offset_var.get()
        gain = self.gain_var.get()
        num_samples = 32768
        slice_dur = num_samples / float(target_hz)

        flt = wav_up.load_real_wav_slice(
            self.selected_pc_file,
            start_s,
            slice_dur,
            num_samples,
            target_rate=target_hz,
            gain=0.92 * gain,
        )
        out = bytearray(num_samples)
        for i, x in enumerate(flt):
            val = int(round(128.0 + x * 92.0))
            out[i] = max(28, min(228, val))
        return bytes(out), target_hz

    def preview_original_on_pc(self):
        if not self.selected_pc_file or not os.path.exists(self.selected_pc_file):
            return
        wav_p = wav_up.ensure_wav_file(self.selected_pc_file)
        winsound.PlaySound(wav_p, winsound.SND_FILENAME | winsound.SND_ASYNC)
        self.status_var.set(f"PC speelt origineel af: {os.path.basename(self.selected_pc_file)}")

    def preview_converted_on_pc(self):
        try:
            pcm, target_hz = self.build_converted_32kb_pcm()
            tmp_wav = os.path.join(tempfile.gettempdir(), "tang_nano_preview_8bit.wav")
            wav_up.save_pcm8_wav(tmp_wav, pcm, target_hz)
            winsound.PlaySound(tmp_wav, winsound.SND_FILENAME | winsound.SND_ASYNC)
            self.status_var.set(f"PC speelt geconverteerde 8-bit ({target_hz} Hz, 32 KB) Tang Nano versie af!")
        except Exception as e:
            messagebox.showerror("Voorluisteren mislukt", str(e), parent=self.root)

    # =========================================================================
    # Rechter Tabel: MicroSD WAV-Bank (#1 t/m #16)
    # =========================================================================
    def refresh_sd_tree(self):
        sel_slot = self.slot_var.get()
        for item in self.sd_tree.get_children():
            self.sd_tree.delete(item)

        target_iid = None
        for s in self.sd_slots:
            idx = s["slot"]
            page = "Lijst 1/2" if idx <= 8 else "Lijst 2/2"
            btn_nr = ((idx - 1) % 8) + 1
            wekker_lbl = f"{page} [Toets {btn_nr}]"
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
        slot = self.slot_var.get()
        sec = self.sd_slots[slot - 1]["start_sec"]
        self.upload_btn.configure(text=f"🚀 UPLOAD GEKOZEN .WAV NAAR SD-SLOT #{slot} (${sec:04X}, 32 KB)")

    # =========================================================================
    # Tang Nano Seriële Communicatie (Automatisch COM6 vrijmaken indien nodig)
    # =========================================================================
    def _acquire_serial_connection(self):
        """Sluit eventuele achtergrond-instantie van basic_terminal.py tijdelijk zodat de COM-poort vrij is."""
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
                        self.status_var.set("Geen WAV-items ontvangen (controleer of de Tang Nano op de BASIC '>' prompt staat).")
                finally:
                    ser.close()
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
                self.status_var.set(f"Audio Hulp-CPU speelt nu Slot #{slot} ({title}) op de achtergrond af (WAV {slot})...")
                ser, _ = self._acquire_serial_connection()
                try:
                    sd_tools.ensure_basic_prompt(ser)
                    ser.write(f"WAV {slot}\r\n".encode("ascii"))
                    time.sleep(0.35)
                    self.status_var.set(f"🎵 Slot #{slot} ({title}) speelt nu op de Audio Hulp-CPU (BASIC is direct vrij)!")
                finally:
                    ser.close()
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
                self.status_var.set(f"Audio Hulp-CPU start eindeloze loop van Slot #{slot} ({title}): WAV {slot},{rate},1 ...")
                ser, _ = self._acquire_serial_connection()
                try:
                    sd_tools.ensure_basic_prompt(ser)
                    ser.write(f"WAV {slot},{rate},1\r\n".encode("ascii"))
                    time.sleep(0.35)
                    self.status_var.set(
                        f"🔁 Slot #{slot} ({title}) loopt nu eindeloos op de Audio Hulp-CPU! (Klik op Stop/ESC of WAV 0 om te stoppen)"
                    )
                finally:
                    ser.close()
            except Exception as e:
                self.status_var.set(f"Fout bij loopen op Tang Nano: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    def stream_long_mp3_to_hulp_cpu_async(self):
        """Stream een lang MP3/WAV-fragment (128 KB = 512 pagina's = ~16.4 sec @ 8 kHz) naar SDRAM Bank 60..61 en start de Audio Hulp-CPU!"""
        if self.busy:
            return
        if not self.selected_pc_file or not os.path.exists(self.selected_pc_file):
            messagebox.showwarning("Geen .MP3/.WAV gekozen", "Kies eerst links een .MP3- of .WAV-bestand!", parent=self.root)
            return

        rate_code, target_hz = self._get_selected_rate_code_and_hz()
        start_s = self.offset_var.get()
        gain = self.gain_var.get()
        num_samples = 131072  # 128 KB (2x 64KB SDRAM Banks 60..61 = 512 pages)
        slice_dur = num_samples / float(target_hz)

        def _worker():
            self.busy = True
            self.progress_var.set(2.0)
            try:
                self.status_var.set(f"Decoderen van {slice_dur:.1f}s uit {os.path.basename(self.selected_pc_file)} (128 KB)...")
                flt = wav_up.load_real_wav_slice(
                    self.selected_pc_file,
                    start_s,
                    slice_dur,
                    num_samples,
                    target_rate=target_hz,
                    gain=0.92 * gain,
                )
                pcm_128kb = bytearray(num_samples)
                for i, x in enumerate(flt):
                    val = int(round(128.0 + x * 92.0))
                    pcm_128kb[i] = max(28, min(228, val))

                # 6502 SDRAM-Bank Streamer op $7E00: leest 256 pagina's (64 KB) per bank van UART naar IO_RD_DATA ($A014)
                sdram_streamer_asm = """
                        ORG $7E00
                        LDA #0
                        STA $A01B       ; Stop Audio Hulp-CPU tijdens laden
                        LDX #0
                PG_LP:
                        STX $A013       ; IO_RD_HI = page (0..255)
                        LDA #'R'
                        STA $A001
                        LDY #0
                BY_LP:
                        STY $A012       ; IO_RD_LO = byte (0..255)
                        JSR GET_HEX
                        STA $A014       ; IO_RD_DATA = sample
                        INY
                        BNE BY_LP
                        INX
                        BNE PG_LP
                        LDA #'D'
                        STA $A001
                        RTS
                GET_HEX:
                        JSR GET_NIB
                        ASL A
                        ASL A
                        ASL A
                        ASL A
                        STA $62
                        JSR GET_NIB
                        ORA $62
                        RTS
                GET_NIB:
                        LDA $A000
                        LSR A
                        BCC GET_NIB
                        LDA $A001
                        CMP #'0'
                        BCC GET_NIB
                        SEC
                        SBC #'0'
                        CMP #10
                        BCC GN_OK
                        SBC #7
                GN_OK:
                        AND #$0F
                        RTS
                """
                _, stub = sd_tools.assemble_6502_source(sdram_streamer_asm)
                ser, _ = self._acquire_serial_connection()
                try:
                    wav_up.install_streamer_stub(ser, stub)
                    for b_idx, bank_num in enumerate((60, 61)):
                        wav_up.send_basic_line(ser, f"POKE $A015,{bank_num}", wait=0.2)
                        if ser.in_waiting:
                            ser.read(ser.in_waiting)
                        ser.write(b"CALL $7E00\r")
                        t0 = time.time()
                        echo = b""
                        while time.time() - t0 < 2.0:
                            if ser.in_waiting:
                                echo += ser.read(1)
                                if echo.endswith(b"\n"):
                                    break
                        bank_bytes = pcm_128kb[b_idx * 65536 : (b_idx + 1) * 65536]
                        for pg in range(256):
                            t0 = time.time()
                            while time.time() - t0 < 2.5:
                                if ser.read(1) == b"R":
                                    break
                            ser.write(bank_bytes[pg * 256 : (pg + 1) * 256].hex().upper().encode("ascii"))
                            done_pg = b_idx * 256 + pg + 1
                            self.progress_var.set((done_pg / 512.0) * 100.0)
                            if done_pg % 16 == 0 or done_pg == 512:
                                self.status_var.set(
                                    f"Streamen naar SDRAM Bank {bank_num}: Pagina {done_pg}/512 ({done_pg // 4} / 128 KB)..."
                                )
                        t0 = time.time()
                        tail = b""
                        while time.time() - t0 < 2.0:
                            if ser.in_waiting:
                                tail += ser.read(ser.in_waiting)
                                if b">" in tail:
                                    break
                            time.sleep(0.01)

                    # Start de Audio Hulp-CPU vanaf Bank 60 voor 512 pagina's ($0200)!
                    cmd = f"POKE $A018,60:POKE $A019,0:POKE $A01A,2:POKE $A01B,{rate_code}"
                    wav_up.send_basic_line(ser, cmd, wait=0.3)
                    self.status_var.set(
                        f"🎶 Audio Hulp-CPU speelt nu {slice_dur:.1f} sec van '{os.path.basename(self.selected_pc_file)}' op de achtergrond (SDRAM Bank 60..61)!"
                    )
                finally:
                    ser.close()
            except Exception as e:
                self.status_var.set(f"❌ Fout bij streamen naar Audio Hulp-CPU: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    def stop_tang_audio(self):
        def _worker():
            try:
                ser, _ = self._acquire_serial_connection()
                try:
                    ser.write(b"\x1b\r\n")
                    time.sleep(0.15)
                finally:
                    ser.close()
                self.status_var.set("Stop-signaal (ESC) verzonden naar Tang Nano 20K.")
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
                    sd_tools.ensure_basic_prompt(ser)
                    ser.write(f"{cmd}\r\n".encode("ascii"))
                    time.sleep(0.3)
                finally:
                    ser.close()
                self.status_var.set(msg)
            except Exception as e:
                self.status_var.set(f"Fout: {e}")
            finally:
                self.busy = False

        threading.Thread(target=_worker, daemon=True).start()

    # =========================================================================
    # Uploaden van 1 .WAV naar een specifiek Slot (#1..#16) of Alle 16 Standaard
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
                    f"[{label}] Sector {s + 1}/{num_sectors} ({(s + 1) * 512} / {len(data_bytes)} bytes) naar MicroSD geschreven..."
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
            messagebox.showwarning("Geen .WAV gekozen", "Kies eerst links een .WAV-bestand!", parent=self.root)
            return

        slot = self.slot_var.get()
        title = self.title_var.get().upper().ljust(15)[:15]
        rate_code, target_hz = self._get_selected_rate_code_and_hz()
        dur_sec = max(1, int(round(32768.0 / target_hz)))

        try:
            pcm_32kb, _ = self.build_converted_32kb_pcm()
        except Exception as e:
            messagebox.showerror("Conversie-fout", str(e), parent=self.root)
            return

        def _worker():
            self.busy = True
            self.progress_var.set(2.0)
            try:
                # Werk slot-metadata bij
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
                    wav_up.install_streamer_stub(ser, streamer_code)
                    self.progress_var.set(8.0)

                    # 1. Schrijf bijgewerkte WAV-Directory naar Sector $2000
                    self._stream_sectors_with_progress(ser, 0x2000, dir_bytes, 8.0, 4.0, "WAV-DIR $2000")

                    # 2. Schrijf de 64 sectoren (32 KB) van dit .WAV-bestand
                    self._stream_sectors_with_progress(
                        ser,
                        start_sec,
                        pcm_32kb,
                        12.0,
                        88.0,
                        f"Slot #{slot}: {title.strip()} (${start_sec:04X})",
                    )

                    self.progress_var.set(100.0)
                    if self.play_after_var.get():
                        self.status_var.set(f"Upload voltooid! Nu live afspelen op Tang Nano: WAV {slot} ({title.strip()})...")
                        ser.write(f"WAV {slot}\r\n".encode("ascii"))
                        t0 = time.time()
                        while time.time() - t0 < (dur_sec + 1.5):
                            b = ser.read(128)
                            if b and b">" in b:
                                break
                    self.status_var.set(
                        f"✅ Gelukt! '{title.strip()}' staat nu op SD-kaart Slot #{slot} (Sector ${start_sec:04X}). Typ in BASIC: WAV {slot}"
                    )
                finally:
                    ser.close()
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
                    ser.close()
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
