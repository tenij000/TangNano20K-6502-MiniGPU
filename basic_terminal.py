import ctypes
import importlib
import msvcrt
import os
import subprocess
import sys
import threading
import time
import urllib.request
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, simpledialog

import serial
import serial.tools.list_ports

import sd_tools
import bg_loader

PORT = sd_tools.find_tang_port("COM6")
BAUD = 115200

user32 = ctypes.windll.user32

VK_UP = 0x26
VK_DOWN = 0x28
VK_LEFT = 0x25
VK_RIGHT = 0x27
VK_SPACE = 0x20
VK_CONTROL = 0x11
VK_MENU = 0x12
VK_NUMPAD0 = 0x60
VK_NUMPAD2 = 0x62
VK_NUMPAD4 = 0x64
VK_NUMPAD6 = 0x66
VK_NUMPAD8 = 0x68


PID_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".basic_terminal.pid")


def _release_previous_instance():
    """Als er nog een oude basic_terminal.py op de achtergrond COM6 vasthoudt, sluit die eerst netjes af."""
    my_pid = os.getpid()
    if os.path.exists(PID_FILE):
        try:
            with open(PID_FILE, "r", encoding="utf-8") as f:
                old_pid = int(f.read().strip())
            if old_pid != my_pid:
                subprocess.run(
                    ["taskkill", "/PID", str(old_pid), "/T", "/F"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                time.sleep(0.25)
        except Exception:
            pass
    try:
        with open(PID_FILE, "w", encoding="utf-8") as f:
            f.write(str(my_pid))
    except Exception:
        pass


def _release_dummies_server_port():
    """Als dummies_server.py (op poort 8765) COM6 vasthoudt, vraag die dan netjes om COM6 vrij te geven."""
    try:
        req = urllib.request.Request(
            "http://127.0.0.1:8765/api/disconnect",
            data=b"{}",
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=0.6)
        time.sleep(0.15)
    except Exception:
        pass


def _restore_dummies_server_port(port="COM6"):
    """Geef COM6 bij afsluiten van basic_terminal.py weer terug aan dummies_server.py."""
    try:
        req = urllib.request.Request(
            "http://127.0.0.1:8765/api/connect",
            data=f'{{"port":"{port}"}}'.encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=0.6)
    except Exception:
        pass


def is_pressed(vk):
    return (user32.GetAsyncKeyState(vk) & 0x8000) != 0


class BasicTerminalControlCenter:
    """
    Uitgebreide MiniGPU BASIC-Terminal & Afstandsbediening (GUI)
    met bedieningsknoppen voor Midnight Commander (MC), ImageViewer (VIEWER),
    SmartReader (READER), MiniExcel (EXCEL), FruityLoops (FRUITY), MON6502,
    BASIC-commando's, Hardware Achtergronden en SD-Kaart Uploads.
    """

    def __init__(self, root):
        self.root = root
        self.root.title("MiniGPU BASIC-Terminal & MC Control Deck (Tang Nano 20K)")
        self.root.geometry("1260x820")
        self.root.minsize(1080, 680)
        self.root.configure(bg="#0f172a")

        self.port_var = tk.StringVar(value=PORT)
        self.status_var = tk.StringVar(value="Verbinden met Tang Nano 20K...")
        self.cmd_var = tk.StringVar(value="")
        self.direct_keys_var = tk.BooleanVar(value=True)
        self.drive_var = tk.IntVar(value=0)

        self.ser = None
        self.ser_lock = threading.Lock()
        self.running = True
        self.paused_for_tool = False
        self.user_disconnected = False

        self.last_joy = 0
        self.pulse_joy = 0
        self.pulse_until = 0.0
        self.held_keys = set()

        self.cmd_history = []
        self.hist_idx = -1

        _release_previous_instance()
        self._setup_styles()
        self._build_ui()
        self.connect_serial(retries=4)

        # Start achtergrond-threads voor seriële ontvangst, 100 Hz Joypad polling & Auto-Reconnect
        self.rx_thread = threading.Thread(target=self._serial_rx_loop, daemon=True)
        self.rx_thread.start()
        self.root.after(15, self._joypad_poll_tick)
        self.root.after(1500, self._auto_reconnect_tick)

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

    def _setup_styles(self):
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except Exception:
            pass
        style.configure("TNotebook", background="#0f172a", borderwidth=0)
        style.configure(
            "TNotebook.Tab",
            background="#1e293b",
            foreground="#cbd5e1",
            padding=(12, 6),
            font=("Segoe UI", 9, "bold"),
        )
        style.map(
            "TNotebook.Tab",
            background=[("selected", "#2563eb")],
            foreground=[("selected", "#ffffff")],
        )

    def _make_btn(self, parent, text, cmd, bg="#334155", fg="#f8fafc", width=None, font=("Segoe UI", 9, "bold"), pady=5, padx=8):
        b = tk.Button(
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
            takefocus=0,
        )
        if width:
            b.configure(width=width)
        return b

    def _build_ui(self):
        # =====================================================================
        # 1. BOVENBALK: Poort, Verbinding, SD-Uploader & Achtergronden
        # =====================================================================
        top = tk.Frame(self.root, bg="#1e293b", pady=6, padx=10, bd=1, relief=tk.GROOVE)
        top.pack(fill=tk.X, padx=8, pady=(6, 4))

        tk.Label(
            top,
            text="🖥 MiniGPU Terminal & MC Deck",
            font=("Segoe UI", 12, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
        ).pack(side=tk.LEFT, padx=(0, 12))

        tk.Label(top, text="Poort:", font=("Segoe UI", 9, "bold"), fg="#e2e8f0", bg="#1e293b").pack(side=tk.LEFT)
        self.port_combo = ttk.Combobox(top, textvariable=self.port_var, width=8, font=("Consolas", 10))
        self.port_combo.pack(side=tk.LEFT, padx=4)
        self.refresh_ports()

        self.conn_btn = self._make_btn(top, "🔌 Verbonden", self.toggle_serial, bg="#16a34a")
        self.conn_btn.pack(side=tk.LEFT, padx=4)

        tk.Frame(top, width=2, bg="#475569").pack(side=tk.LEFT, fill=tk.Y, padx=8, pady=2)

        self._make_btn(top, "📤 Upload Bestand (F5)", self.quick_upload_dialog, bg="#2563eb").pack(side=tk.LEFT, padx=3)
        self._make_btn(top, "💾 SD Studio GUI", self.launch_sd_gui, bg="#0284c7").pack(side=tk.LEFT, padx=3)
        self._make_btn(top, "🎵 WAV Studio GUI", self.launch_wav_gui, bg="#0d9488").pack(side=tk.LEFT, padx=3)
        self._make_btn(top, "🚜 Boerderij 720p", lambda: self.set_hw_bg_theme(1), bg="#15803d").pack(side=tk.LEFT, padx=3)
        self._make_btn(top, "🪐 Space 720p", lambda: self.set_hw_bg_theme(0), bg="#4f46e5").pack(side=tk.LEFT, padx=3)
        self._make_btn(top, "👁 Panorama Vol Scherm", self.toggle_hw_panorama, bg="#d97706").pack(side=tk.LEFT, padx=3)
        self._make_btn(top, "🌌 Achtergrond (F6)", self.open_bg_dialog, bg="#7c3aed").pack(side=tk.LEFT, padx=3)

        tk.Frame(top, width=2, bg="#475569").pack(side=tk.LEFT, fill=tk.Y, padx=8, pady=2)

        self._make_btn(top, "🛑 ESC", lambda: self.send_raw(b"\x1b"), bg="#dc2626").pack(side=tk.LEFT, padx=3)
        self._make_btn(top, "⏎ Naar BASIC (>)", self.exit_to_basic_prompt, bg="#ea580c").pack(side=tk.LEFT, padx=3)

        # =====================================================================
        # 2. SNELSTART-BALK: 1-Klik SD-Kaart Apps & BASIC Commando's
        # =====================================================================
        launch_bar = tk.Frame(self.root, bg="#0f172a", pady=4, padx=8)
        launch_bar.pack(fill=tk.X, padx=8)

        tk.Label(
            launch_bar,
            text="SNELSTART SD-APPS:",
            font=("Segoe UI", 9, "bold"),
            fg="#94a3b8",
            bg="#0f172a",
        ).pack(side=tk.LEFT, padx=(0, 6))

        apps = [
            ("🟦 MC (Bestanden)", "MC", "#1d4ed8"),
            ("🖼 VIEWER (Plaatjes)", "VIEWER", "#0369a1"),
            ("📖 READER (Tekst)", "READER", "#0f766e"),
            ("📊 EXCEL (Sheet)", "EXCEL", "#15803d"),
            ("🎹 FRUITY (Muziek)", "FRUITY", "#6d28d9"),
            ("🛠 MON6502 (Debug)", "MON6502", "#b45309"),
        ]
        for label, app_name, color in apps:
            self._make_btn(
                launch_bar,
                label,
                lambda a=app_name: self.launch_sd_app(a),
                bg=color,
                pady=4,
                padx=8,
            ).pack(side=tk.LEFT, padx=3)

        tk.Frame(launch_bar, width=2, bg="#334155").pack(side=tk.LEFT, fill=tk.Y, padx=8, pady=2)

        basic_cmds = [
            ("📋 DIR", "DIR"),
            ("🧹 CLS", "CLS"),
            ("📜 LIST", "LIST"),
            ("▶ RUN", "RUN"),
        ]
        for lbl, bcmd in basic_cmds:
            self._make_btn(
                launch_bar,
                lbl,
                lambda c=bcmd: self.send_basic_command(c),
                bg="#334155",
                pady=4,
                padx=7,
            ).pack(side=tk.LEFT, padx=2)

        # =====================================================================
        # 3. HOOFDGEBIED: Links Terminal, Rechts MC & App Bedieningspaneel
        # =====================================================================
        main_pane = tk.PanedWindow(self.root, orient=tk.HORIZONTAL, bg="#0f172a", sashwidth=6, bd=0)
        main_pane.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)

        # --- LINKER KOLOM: Live Seriële Terminal + Commando-invoer ---
        term_frame = tk.Frame(main_pane, bg="#1e293b", bd=1, relief=tk.GROOVE)
        main_pane.add(term_frame, minsize=520, width=680)

        term_hdr = tk.Frame(term_frame, bg="#0f172a", pady=5, padx=8)
        term_hdr.pack(fill=tk.X)
        tk.Label(
            term_hdr,
            text="💻 Live Seriële Terminal (Klik in het zwarte scherm om direct te typen / besturen)",
            font=("Segoe UI", 9, "bold"),
            fg="#38bdf8",
            bg="#0f172a",
        ).pack(side=tk.LEFT)

        tk.Checkbutton(
            term_hdr,
            text="Directe Toetsen & Pijltjes actief",
            variable=self.direct_keys_var,
            bg="#0f172a",
            fg="#a7f3d0",
            selectcolor="#1e293b",
            activebackground="#0f172a",
            font=("Segoe UI", 9),
        ).pack(side=tk.RIGHT)

        txt_wrap = tk.Frame(term_frame, bg="#020617")
        txt_wrap.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        self.term_text = tk.Text(
            txt_wrap,
            bg="#020617",
            fg="#4ade80",
            insertbackground="#38bdf8",
            font=("Consolas", 11),
            wrap=tk.CHAR,
            relief=tk.FLAT,
            padx=8,
            pady=6,
        )
        sb = ttk.Scrollbar(txt_wrap, orient=tk.VERTICAL, command=self.term_text.yview)
        self.term_text.configure(yscrollcommand=sb.set)
        self.term_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sb.pack(side=tk.RIGHT, fill=tk.Y)

        # Bind toetsenbord zowel op het hoofdvenster als op het terminal-veld
        self.root.bind("<KeyPress>", self._on_term_keypress)
        self.root.bind("<KeyRelease>", self._on_term_keyrelease)
        self.term_text.bind("<KeyPress>", self._on_term_keypress)
        self.term_text.bind("<KeyRelease>", self._on_term_keyrelease)

        # Onderbalk in terminal: Regel-invoer (handig voor lange BASIC regels)
        cmd_bar = tk.Frame(term_frame, bg="#1e293b", pady=6, padx=6)
        cmd_bar.pack(fill=tk.X)
        tk.Label(cmd_bar, text="BASIC Regel:", font=("Segoe UI", 9, "bold"), fg="#cbd5e1", bg="#1e293b").pack(side=tk.LEFT)
        self.cmd_entry = tk.Entry(
            cmd_bar,
            textvariable=self.cmd_var,
            bg="#0f172a",
            fg="#f8fafc",
            insertbackground="#38bdf8",
            font=("Consolas", 11),
            relief=tk.FLAT,
        )
        self.cmd_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6, ipady=4)
        self.cmd_entry.bind("<Return>", lambda e: self.send_entry_line())
        self.cmd_entry.bind("<Up>", self._hist_prev)
        self.cmd_entry.bind("<Down>", self._hist_next)

        self._make_btn(cmd_bar, "Verzend ⏎", self.send_entry_line, bg="#16a34a").pack(side=tk.LEFT, padx=2)
        self._make_btn(cmd_bar, "Wis Scherm", lambda: self.term_text.delete("1.0", tk.END), bg="#475569").pack(side=tk.LEFT, padx=2)

        # --- RECHTER KOLOM: Universele D-Pad + Tabbladen voor MC, VIEWER, READER/EXCEL, FRUITY/MON ---
        ctrl_frame = tk.Frame(main_pane, bg="#1e293b", bd=1, relief=tk.GROOVE)
        main_pane.add(ctrl_frame, minsize=460, width=550)

        # A. Universele Navigatie / D-Pad (werkt in MC, Viewer, Reader, Excel, Fruity, Mon6502 & Games)
        dpad_box = tk.LabelFrame(
            ctrl_frame,
            text=" 🎮 Universele Cursor & Joypad Besturing (MC / Viewer / Games) ",
            font=("Segoe UI", 9, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        dpad_box.pack(fill=tk.X, padx=8, pady=(8, 6))

        dpad_grid = tk.Frame(dpad_box, bg="#1e293b")
        dpad_grid.pack()

        self._make_btn(dpad_grid, "▲ Omhoog", lambda: self.pulse_direction(0x01), bg="#2563eb", width=12).grid(row=0, column=1, padx=4, pady=3)
        self._make_btn(dpad_grid, "◄ Links", lambda: self.pulse_direction(0x04), bg="#2563eb", width=12).grid(row=1, column=0, padx=4, pady=3)
        self._make_btn(dpad_grid, "⏎ ENTER / Open", lambda: self.send_raw(b"\r"), bg="#16a34a", width=14).grid(row=1, column=1, padx=4, pady=3)
        self._make_btn(dpad_grid, "► Rechts", lambda: self.pulse_direction(0x08), bg="#2563eb", width=12).grid(row=1, column=2, padx=4, pady=3)
        self._make_btn(dpad_grid, "▼ Omlaag", lambda: self.pulse_direction(0x02), bg="#2563eb", width=12).grid(row=2, column=1, padx=4, pady=3)

        # Extra navigatie-knoppen rechts naast D-Pad
        self._make_btn(dpad_grid, "↹ TAB (Paneel)", lambda: self.send_raw(b"\t"), bg="#0284c7", width=14).grid(row=0, column=3, padx=(12, 4), pady=3)
        self._make_btn(dpad_grid, "⌫ Map .. (BS)", lambda: self.send_raw(b"\x08"), bg="#475569", width=14).grid(row=1, column=3, padx=(12, 4), pady=3)
        self._make_btn(dpad_grid, "␣ Spatie / Actie", lambda: self.send_raw(b" "), bg="#475569", width=14).grid(row=2, column=3, padx=(12, 4), pady=3)

        # B. Tabbladen per Programma (MC staat standaard voorop!)
        self.nb = ttk.Notebook(ctrl_frame)
        self.nb.pack(fill=tk.BOTH, expand=True, padx=8, pady=(2, 8))

        self._build_mc_tab()
        self._build_viewer_tab()
        self._build_reader_excel_tab()
        self._build_fruity_mon_tab()

        # =====================================================================
        # 4. STATUSBALK ONDERAAN
        # =====================================================================
        status_bar = tk.Frame(self.root, bg="#020617", pady=4, padx=10)
        status_bar.pack(fill=tk.X, side=tk.BOTTOM)
        tk.Label(
            status_bar,
            textvariable=self.status_var,
            font=("Segoe UI", 9),
            fg="#94a3b8",
            bg="#020617",
        ).pack(side=tk.LEFT)
        tk.Label(
            status_bar,
            text="Sneltoetsen: Pijltjes = Beweeg | Enter = Open | Tab = Wissel Paneel | F5 = Upload | F6 = Achtergrond",
            font=("Segoe UI", 9),
            fg="#64748b",
            bg="#020617",
        ).pack(side=tk.RIGHT)

        self._append_terminal(
            "============================================================\n"
            f"  MiniGPU BASIC-Terminal & MC Control Deck ({PORT} @ {BAUD})\n"
            "  * Klik op de knoppen rechts om Midnight Commander (MC),\n"
            "    ImageViewer (VIEWER), Reader, Excel of Fruity te besturen!\n"
            "  * Of klik in dit zwarte scherm om direct te typen.\n"
            "============================================================\n"
        )

    def _build_mc_tab(self):
        tab = tk.Frame(self.nb, bg="#1e293b", padx=8, pady=8)
        self.nb.add(tab, text="🟦 Midnight Commander (MC)")

        # 1. Start / Herstart MC + MP3PLAY + Paneel wisselen
        top_row = tk.Frame(tab, bg="#1e293b")
        top_row.pack(fill=tk.X, pady=(0, 8))
        self._make_btn(top_row, "🚀 Start MC vanaf SD", lambda: self.launch_sd_app("MC"), bg="#1d4ed8", width=18).pack(side=tk.LEFT, padx=3)
        self._make_btn(top_row, "🎵 Start MP3PLAY", lambda: self.launch_sd_app("MP3PLAY"), bg="#15803d", width=16).pack(side=tk.LEFT, padx=3)
        self._make_btn(top_row, "↹ Wissel L/R Paneel (TAB)", lambda: self.send_raw(b"\t"), bg="#0284c7", width=20).pack(side=tk.LEFT, padx=3)
        self._make_btn(top_row, "🚪 Sluit MC (0 / Q)", lambda: self.send_raw(b"0"), bg="#dc2626", width=15).pack(side=tk.LEFT, padx=3)

        # 2. Pull-Down Menu Balk knoppen (Left, File, Command, Options, Right)
        menu_box = tk.LabelFrame(
            tab,
            text=" ☰ MC Pull-Down Menu's (Bovenbalk) ",
            font=("Segoe UI", 9, "bold"),
            fg="#fde047",
            bg="#1e293b",
            padx=6,
            pady=6,
        )
        menu_box.pack(fill=tk.X, pady=4)

        m_row = tk.Frame(menu_box, bg="#1e293b")
        m_row.pack(fill=tk.X)
        menus = [
            ("1: Menu Balk", b"1", "#475569"),
            ("Left (L)", b"L", "#0369a1"),
            ("File (F)", b"F", "#0369a1"),
            ("Command (C)", b"C", "#0369a1"),
            ("Options (O)", b"O", "#0369a1"),
            ("Right (R)", b"R", "#0369a1"),
        ]
        for txt, key_b, col in menus:
            self._make_btn(m_row, txt, lambda k=key_b: self.send_raw(k), bg=col, padx=7, pady=4).pack(side=tk.LEFT, padx=2, expand=True, fill=tk.X)

        # 3. MC Bestandsacties (Functietoetsen 1..0)
        act_box = tk.LabelFrame(
            tab,
            text=" 📂 MC Bestandsbeheer & Acties (Snelknoppen 1 t/m 0) ",
            font=("Segoe UI", 9, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        act_box.pack(fill=tk.X, pady=6)

        grid = tk.Frame(act_box, bg="#1e293b")
        grid.pack(fill=tk.X)
        for c in range(2):
            grid.columnconfigure(c, weight=1)

        mc_actions = [
            ("⏎  3: Open / Run / Bekijk Plaatje", lambda: self.send_raw(b"3"), "#16a34a", 0, 0),
            ("💾  2: Wissel Drive (D0 -> D1 -> D2 -> D3)", lambda: self.send_raw(b"2"), "#0284c7", 0, 1),
            ("✏  4: Hernoem Geselecteerd Bestand...", self.mc_rename_dialog, "#d97706", 1, 0),
            ("📋  5: Kopieer Bestand (Actief -> Ander Paneel)", lambda: self.send_raw(b"5"), "#2563eb", 1, 1),
            ("✂  6: Verplaats Bestand (Move L <-> R)", lambda: self.send_raw(b"6"), "#7c3aed", 2, 0),
            ("📁  7: Nieuwe Submap Maken (MkDir)...", self.mc_mkdir_dialog, "#0d9488", 2, 1),
            ("🗑  8: Wis Bestand / Lege Map (Delete)", self.mc_delete_confirm, "#dc2626", 3, 0),
            ("🎨  9: Wissel Thema (Blauw / Transparant)", lambda: self.send_raw(b"9"), "#4f46e5", 3, 1),
        ]
        for label, cmd, col, r, c in mc_actions:
            self._make_btn(grid, label, cmd, bg=col, pady=6).grid(row=r, column=c, sticky="ew", padx=4, pady=3)

        # 4. Snel Drive Kiezen voor Linker of Rechter Paneel via Pull-Down Menu
        drv_box = tk.LabelFrame(
            tab,
            text=" 💿 Kies Direct Drive voor Linker of Rechter Paneel in MC ",
            font=("Segoe UI", 9, "bold"),
            fg="#a7f3d0",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        drv_box.pack(fill=tk.X, pady=4)

        l_row = tk.Frame(drv_box, bg="#1e293b")
        l_row.pack(fill=tk.X, pady=2)
        tk.Label(l_row, text="Linker Paneel:", font=("Segoe UI", 9, "bold"), fg="#cbd5e1", bg="#1e293b", width=14, anchor="w").pack(side=tk.LEFT)
        for d in range(4):
            self._make_btn(
                l_row,
                f"Links = D{d}",
                lambda idx=d: self.mc_select_pane_drive("L", idx),
                bg="#334155",
                pady=3,
            ).pack(side=tk.LEFT, padx=3, expand=True, fill=tk.X)

        r_row = tk.Frame(drv_box, bg="#1e293b")
        r_row.pack(fill=tk.X, pady=2)
        tk.Label(r_row, text="Rechter Paneel:", font=("Segoe UI", 9, "bold"), fg="#cbd5e1", bg="#1e293b", width=14, anchor="w").pack(side=tk.LEFT)
        for d in range(4):
            self._make_btn(
                r_row,
                f"Rechts = D{d}",
                lambda idx=d: self.mc_select_pane_drive("R", idx),
                bg="#334155",
                pady=3,
            ).pack(side=tk.LEFT, padx=3, expand=True, fill=tk.X)

    def _build_viewer_tab(self):
        tab = tk.Frame(self.nb, bg="#1e293b", padx=8, pady=8)
        self.nb.add(tab, text="🖼 ImageViewer")

        top_row = tk.Frame(tab, bg="#1e293b")
        top_row.pack(fill=tk.X, pady=(0, 8))
        self._make_btn(top_row, "🚀 Start VIEWER vanaf SD", lambda: self.launch_sd_app("VIEWER"), bg="#0369a1", width=22).pack(side=tk.LEFT, padx=3)
        self._make_btn(top_row, "📂 Open SD Plaatjes-Kiezer (O)", lambda: self.send_raw(b"O"), bg="#16a34a", width=24).pack(side=tk.LEFT, padx=3)
        self._make_btn(top_row, "🚪 Sluit Viewer (Q)", lambda: self.send_raw(b"Q"), bg="#dc2626", width=15).pack(side=tk.LEFT, padx=3)

        mode_box = tk.LabelFrame(
            tab,
            text=" 🎨 Kies Kunst- &Weergavemodus (1 t/m 5) ",
            font=("Segoe UI", 9, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        mode_box.pack(fill=tk.X, pady=4)

        modes = [
            ("[1] SD / RLE Pixel-Art Plaatje ($5000)", b"1", "#2563eb"),
            ("[2] Scifi-Schilderij 'Ruimtehaven Tang-20K'", b"2", "#7c3aed"),
            ("[3] Hardware Sprite-Sheet (32 Sprites + 2 BigSprites)", b"3", "#0d9488"),
            ("[4] 64x64 Wereldmap & Tegel-Atlas (Scrollbaar)", b"4", "#15803d"),
            ("[5] 256-Kleuren RGB332 Master Palet & Kiezer", b"5", "#d97706"),
        ]
        for txt, kb, col in modes:
            self._make_btn(mode_box, txt, lambda k=kb: self.send_raw(k), bg=col, pady=5).pack(fill=tk.X, pady=2)

        ctrl_box = tk.LabelFrame(
            tab,
            text=" 🔍 Zoom, Diashow, Kader & Sprites ",
            font=("Segoe UI", 9, "bold"),
            fg="#fde047",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        ctrl_box.pack(fill=tk.X, pady=6)

        g = tk.Frame(ctrl_box, bg="#1e293b")
        g.pack(fill=tk.X)
        for c in range(2):
            g.columnconfigure(c, weight=1)

        v_btns = [
            ("⏭ Volgend SD-Plaatje (N)", b"N", "#16a34a", 0, 0),
            ("🎬 Start/Stop Diashow (P)", b"P", "#d97706", 0, 1),
            ("🔍 Zoom 1x / 2x / 3x (Z)", b"Z", "#0284c7", 1, 0),
            ("🖼 Wissel Lijst-Thema (C)", b"C", "#7c3aed", 1, 1),
            ("⛶ Volledig Scherm Aan/Uit (F)", b"F", "#4f46e5", 2, 0),
            ("🌅 Standaard Cyber-Sunset (R)", b"R", "#0369a1", 2, 1),
            ("📥 Laad SPREDIT Sprites (L)", b"L", "#0d9488", 3, 0),
            ("↔ Spiegel BigSprites (M)", b"M", "#b45309", 3, 1),
        ]
        for lbl, kb, col, r, c in v_btns:
            self._make_btn(g, lbl, lambda k=kb: self.send_raw(k), bg=col, pady=5).grid(row=r, column=c, sticky="ew", padx=4, pady=3)

    def _build_reader_excel_tab(self):
        tab = tk.Frame(self.nb, bg="#1e293b", padx=8, pady=8)
        self.nb.add(tab, text="📖 Reader & 📊 Excel")

        # --- SmartReader ---
        rd_box = tk.LabelFrame(
            tab,
            text=" 📖 SmartReader (READER - E-Book / BASIC / Hex Viewer) ",
            font=("Segoe UI", 9, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        rd_box.pack(fill=tk.X, pady=(0, 8))

        rg = tk.Frame(rd_box, bg="#1e293b")
        rg.pack(fill=tk.X)
        for c in range(2):
            rg.columnconfigure(c, weight=1)

        r_btns = [
            ("🚀 Start READER", lambda: self.launch_sd_app("READER"), "#0f766e", 0, 0),
            ("📂 Open SD-Bestand (O)", lambda: self.send_raw(b"O"), "#16a34a", 0, 1),
            ("🔀 Modus TXT / BAS / HEX (M)", lambda: self.send_raw(b"M"), "#2563eb", 1, 0),
            ("🎨 Kleurenthema (T)", lambda: self.send_raw(b"T"), "#7c3aed", 1, 1),
            ("❓ Help-Scherm (H)", lambda: self.send_raw(b"H"), "#d97706", 2, 0),
            ("🚪 Sluit Reader (Q)", lambda: self.send_raw(b"Q"), "#dc2626", 2, 1),
        ]
        for lbl, cmd, col, r, c in r_btns:
            self._make_btn(rg, lbl, cmd, bg=col, pady=5).grid(row=r, column=c, sticky="ew", padx=4, pady=3)

        # --- MiniExcel ---
        ex_box = tk.LabelFrame(
            tab,
            text=" 📊 MiniExcel (EXCEL - Spreadsheet & Grafieken) ",
            font=("Segoe UI", 9, "bold"),
            fg="#4ade80",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        ex_box.pack(fill=tk.X, pady=4)

        eg = tk.Frame(ex_box, bg="#1e293b")
        eg.pack(fill=tk.X)
        for c in range(2):
            eg.columnconfigure(c, weight=1)

        e_btns = [
            ("🚀 Start EXCEL", lambda: self.launch_sd_app("EXCEL"), "#15803d", 0, 0),
            ("✏ Bewerk Cel (ENTER)", lambda: self.send_raw(b"\r"), "#16a34a", 0, 1),
            ("∑ Formule Invoeren (=)", lambda: self.send_raw(b"="), "#2563eb", 1, 0),
            ("🧹 Wis Cel (C)", lambda: self.send_raw(b"C"), "#d97706", 1, 1),
            ("🎨 Cel-Kleur (F)", lambda: self.send_raw(b"F"), "#7c3aed", 2, 0),
            ("💾 Sync naar BASIC Arrays (B)", lambda: self.send_raw(b"B"), "#0284c7", 2, 1),
            ("📄 Nieuw Werkblad (N)", lambda: self.send_raw(b"N"), "#475569", 3, 0),
            ("🚪 Sluit Excel (Q)", lambda: self.send_raw(b"Q"), "#dc2626", 3, 1),
        ]
        for lbl, cmd, col, r, c in e_btns:
            self._make_btn(eg, lbl, cmd, bg=col, pady=5).grid(row=r, column=c, sticky="ew", padx=4, pady=3)

    def _build_fruity_mon_tab(self):
        tab = tk.Frame(self.nb, bg="#1e293b", padx=8, pady=8)
        self.nb.add(tab, text="🎹 Fruity & 🛠 Mon6502")

        # --- FruityLoops ---
        fr_box = tk.LabelFrame(
            tab,
            text=" 🎹 FruityLoops Studio (FRUITY - 4-Kanaals Synthesizer Sequencer) ",
            font=("Segoe UI", 9, "bold"),
            fg="#c084fc",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        fr_box.pack(fill=tk.X, pady=(0, 8))

        fg_grid = tk.Frame(fr_box, bg="#1e293b")
        fg_grid.pack(fill=tk.X)
        for c in range(2):
            fg_grid.columnconfigure(c, weight=1)

        f_btns = [
            ("🚀 Start FRUITY", lambda: self.launch_sd_app("FRUITY"), "#6d28d9", 0, 0),
            ("▶ Play / Pause (P)", lambda: self.send_raw(b"P"), "#16a34a", 0, 1),
            ("➕ Noot / Waarde Omhoog (+)", lambda: self.send_raw(b"+"), "#2563eb", 1, 0),
            ("➖ Noot / Waarde Omlaag (-)", lambda: self.send_raw(b"-"), "#2563eb", 1, 1),
            ("🐢 Tempo Langzamer ([)", lambda: self.send_raw(b"["), "#0284c7", 2, 0),
            ("🐇 Tempo Sneller (])", lambda: self.send_raw(b"]"), "#0284c7", 2, 1),
            ("🎼 Demo Song 1..4 (1/2/3/4)", lambda: self.send_raw(b"2"), "#d97706", 3, 0),
            ("🚪 Sluit Fruity (Q)", lambda: self.send_raw(b"Q"), "#dc2626", 3, 1),
        ]
        for lbl, cmd, col, r, c in f_btns:
            self._make_btn(fg_grid, lbl, cmd, bg=col, pady=5).grid(row=r, column=c, sticky="ew", padx=4, pady=3)

        # --- MON6502 ---
        mn_box = tk.LabelFrame(
            tab,
            text=" 🛠 Machine Code Studio (MON6502 - Hex, Disassembler & Assembler) ",
            font=("Segoe UI", 9, "bold"),
            fg="#fbbf24",
            bg="#1e293b",
            padx=8,
            pady=6,
        )
        mn_box.pack(fill=tk.X, pady=4)

        mg = tk.Frame(mn_box, bg="#1e293b")
        mg.pack(fill=tk.X)
        for c in range(2):
            mg.columnconfigure(c, weight=1)

        m_btns = [
            ("🚀 Start MON6502", lambda: self.launch_sd_app("MON6502"), "#b45309", 0, 0),
            ("↹ Wissel Venster (TAB)", lambda: self.send_raw(b"\t"), "#0284c7", 0, 1),
            ("👣 Single-Step Instructie (S)", lambda: self.send_raw(b"S"), "#16a34a", 1, 0),
            ("▶ Voer Code Uit vanaf PC (G)", lambda: self.send_raw(b"G"), "#2563eb", 1, 1),
            ("🎨 Kleurenthema (T)", lambda: self.send_raw(b"T"), "#7c3aed", 2, 0),
            ("🚪 Sluit Monitor (Q)", lambda: self.send_raw(b"Q"), "#dc2626", 2, 1),
        ]
        for lbl, cmd, col, r, c in m_btns:
            self._make_btn(mg, lbl, cmd, bg=col, pady=5).grid(row=r, column=c, sticky="ew", padx=4, pady=3)

    # =========================================================================
    # Seriële Poort Beheer
    # =========================================================================
    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        if not ports:
            ports = ["COM6"]
        self.port_combo["values"] = ports

    def connect_serial(self, retries=3):
        with self.ser_lock:
            if self.ser and self.ser.is_open:
                self.user_disconnected = False
                return True
            port = self.port_var.get().strip() or sd_tools.find_tang_port("COM6")
            self.port_var.set(port)
            _release_dummies_server_port()
            last_err = None
            for attempt in range(max(1, retries)):
                try:
                    self.ser = serial.Serial(port, BAUD, timeout=0.01)
                    self.user_disconnected = False
                    t_now = time.localtime()
                    self.ser.write(bytes([0xF4, 0x80 | (t_now.tm_hour & 0x1F), 0x80 | (t_now.tm_min & 0x3F), 0x80 | (t_now.tm_sec & 0x3F)]))
                    self.conn_btn.configure(text=f"🔌 Verbonden ({port})", bg="#16a34a")
                    self.status_var.set(f"Verbonden met {port} @ {BAUD} baud (Hardware RTC gesynchroniseerd).")
                    return True
                except Exception as e:
                    last_err = e
                    self.ser = None
                    if attempt + 1 < retries:
                        time.sleep(0.2)
            self.conn_btn.configure(text="🔌 Niet Verbonden", bg="#dc2626")
            self.status_var.set(f"Kan {port} niet openen: {last_err}")
            return False

    def disconnect_serial(self, manual=True):
        with self.ser_lock:
            if manual:
                self.user_disconnected = True
            if self.ser:
                try:
                    if self.last_joy != 0:
                        self.ser.write(bytes([0x80]))
                        self.last_joy = 0
                    self.ser.close()
                except Exception:
                    pass
                self.ser = None
            self.conn_btn.configure(text="🔌 Verbinden", bg="#475569")
            self.status_var.set("Seriële poort ontkoppeld (klik op '🔌 Verbinden' om te herverbinden).")

    def toggle_serial(self):
        if self.ser and self.ser.is_open:
            self.disconnect_serial(manual=True)
        else:
            self.user_disconnected = False
            self.connect_serial(retries=3)

    def _auto_reconnect_tick(self):
        if not self.running:
            return
        if not self.user_disconnected and not self.paused_for_tool:
            if not self.ser or not self.ser.is_open:
                self.connect_serial(retries=1)
        self.root.after(1500, self._auto_reconnect_tick)

    def _serial_rx_loop(self):
        while self.running:
            if self.paused_for_tool or not self.ser or not self.ser.is_open:
                time.sleep(0.05)
                continue
            chunk = b""
            with self.ser_lock:
                try:
                    if self.ser and self.ser.is_open and self.ser.in_waiting:
                        chunk = self.ser.read(min(512, self.ser.in_waiting))
                except Exception:
                    chunk = b""
            if chunk:
                text = chunk.decode("ascii", errors="replace").replace("\r\n", "\n").replace("\r", "")
                self.root.after(0, self._append_terminal, text)
            else:
                time.sleep(0.01)

    def _append_terminal(self, text):
        if not text:
            return
        # Verwerk form-feed (CLS = ASCII 12)
        if "\x0c" in text:
            parts = text.split("\x0c")
            self.term_text.delete("1.0", tk.END)
            text = parts[-1]
        self.term_text.insert(tk.END, text)
        # Houd buffer compact
        lines = int(self.term_text.index("end-1c").split(".")[0])
        if lines > 800:
            self.term_text.delete("1.0", f"{lines - 600}.0")
        self.term_text.see(tk.END)

    def send_raw(self, data: bytes):
        if not self.ser or not self.ser.is_open:
            if not self.connect_serial():
                return
        with self.ser_lock:
            try:
                self.ser.write(data)
            except Exception as e:
                self.status_var.set(f"Schrijffout: {e}")

    def pulse_direction(self, joy_bit: int, duration=0.065):
        """Stuur zowel WASD-karakter (blijft gelatcht in IO_TERM) als joypad-puls (IO_JOY)."""
        key_map = {0x01: b"W", 0x02: b"S", 0x04: b"A", 0x08: b"D"}
        if joy_bit in key_map:
            self.send_raw(key_map[joy_bit])
        self.pulse_joy |= joy_bit
        self.pulse_until = time.time() + duration

    def _joypad_poll_tick(self):
        if not self.running:
            return
        now = time.time()
        if now >= self.pulse_until:
            self.pulse_joy = 0

        joy = self.pulse_joy
        for k in list(self.held_keys):
            if k == "Up":
                joy |= 0x01
            elif k == "Down":
                joy |= 0x02
            elif k == "Left":
                joy |= 0x04
            elif k == "Right":
                joy |= 0x08

        if joy != self.last_joy and self.ser and self.ser.is_open and not self.paused_for_tool:
            with self.ser_lock:
                try:
                    self.ser.write(bytes([0x80 | joy]))
                    self.last_joy = joy
                except Exception:
                    pass

        self.root.after(15, self._joypad_poll_tick)

    # =========================================================================
    # Toetsenbord afhandeling in het Terminal-venster
    # =========================================================================
    def _on_term_keypress(self, event):
        # Als de gebruiker in het BASIC Regel invoerveld of de COM-poort typt, laat die normaal werken
        if event.widget in (self.cmd_entry, self.port_combo):
            return
        if not self.direct_keys_var.get():
            return "break"

        ks = event.keysym
        if ks == "F5":
            self.quick_upload_dialog()
            return "break"
        if ks == "F6":
            self.open_bg_dialog()
            return "break"

        if ks in ("Up", "Down", "Left", "Right"):
            if is_pressed(VK_MENU) or (event.state & 0x20000):
                mbit = {"Up": 0x01, "Down": 0x02, "Left": 0x04, "Right": 0x08}[ks]
                self.send_raw(bytes([0xC0 | mbit]))
                return "break"
            self.held_keys.add(ks)
            bit = {"Up": 0x01, "Down": 0x02, "Left": 0x04, "Right": 0x08}[ks]
            self.pulse_direction(bit, duration=0.06)
            return "break"

        if (is_pressed(VK_MENU) or (event.state & 0x20000)) and ks in ("Return", "space"):
            self.send_raw(bytes([0xD0]))
            return "break"

        if ks == "Return":
            self.send_raw(b"\r")
            return "break"
        if ks == "BackSpace":
            self.send_raw(b"\x08")
            return "break"
        if ks == "Tab":
            self.send_raw(b"\t")
            return "break"
        if ks == "Escape":
            self.send_raw(b"\x1b")
            return "break"

        if event.char and len(event.char) == 1:
            ch = event.char.encode("ascii", errors="ignore")
            if ch:
                self.send_raw(ch)
        return "break"

    def _on_term_keyrelease(self, event):
        if event.keysym in self.held_keys:
            self.held_keys.discard(event.keysym)
        return "break"

    # =========================================================================
    # Commando-balk & Snel-Acties
    # =========================================================================
    def send_entry_line(self):
        line = self.cmd_var.get()
        if line.strip():
            self.cmd_history.append(line)
            self.hist_idx = len(self.cmd_history)
        self.cmd_var.set("")
        self.send_basic_command(line)

    def _hist_prev(self, event):
        if self.cmd_history and self.hist_idx > 0:
            self.hist_idx -= 1
            self.cmd_var.set(self.cmd_history[self.hist_idx])
        return "break"

    def _hist_next(self, event):
        if self.cmd_history and self.hist_idx < len(self.cmd_history) - 1:
            self.hist_idx += 1
            self.cmd_var.set(self.cmd_history[self.hist_idx])
        else:
            self.hist_idx = len(self.cmd_history)
            self.cmd_var.set("")
        return "break"

    def send_basic_command(self, cmd: str):
        def _worker():
            if not self.ser or not self.ser.is_open:
                if not self.connect_serial():
                    return
            exp_cmd, used_drv = sd_tools.expand_mp3_in_basic_line(cmd)
            with self.ser_lock:
                if used_drv:
                    for ch in sd_tools.MP3_DRIVER_BOOT_CMD:
                        self.ser.write(ch.encode("ascii", errors="ignore"))
                        time.sleep(0.0008)
                    self.ser.write(b"\r")
                    time.sleep(0.05)
                for ch in exp_cmd:
                    self.ser.write(ch.encode("ascii", errors="ignore"))
                    time.sleep(0.001)
                self.ser.write(b"\r")
            self.status_var.set(f"Verzonden: {cmd}")

        threading.Thread(target=_worker, daemon=True).start()

    def set_hw_bg_theme(self, theme_id: int):
        """Schakel direct tussen 720p Hardware Achtergrond: 0 = Space Planeten, 1 = Boerderij Landschap."""
        opcode = b"\xf1" if theme_id == 1 else b"\xf0"
        naam = "Boerderij Landschap (720p @ 60 FPS)" if theme_id == 1 else "Space Planeten (720p @ 60 FPS)"
        self.send_raw(opcode)
        self.status_var.set(f"Hardware 720p Achtergrond geschakeld naar: {naam}")

    def toggle_hw_panorama(self):
        """Toon/verberg de BASIC tekst-overlay zodat het 1280x720 Hardware Panorama beeldvullend zichtbaar is."""
        self.send_raw(b"\xf3")
        self.status_var.set("Volledig 1280x720 Hardware Panorama getoggled (klik nogmaals voor tekst-overlay).")

    def exit_to_basic_prompt(self):
        """Sluit elk draaiend 6502- of BASIC-programma netjes af terug naar de '>' prompt."""
        def _worker():
            if not self.ser or not self.ser.is_open:
                if not self.connect_serial():
                    return
            self.paused_for_tool = True
            try:
                with self.ser_lock:
                    sd_tools.ensure_basic_prompt(self.ser)
                    self.ser.write(b"\r")
                self.status_var.set("Teruggekeerd naar de BASIC '>' prompt.")
            finally:
                self.paused_for_tool = False

        threading.Thread(target=_worker, daemon=True).start()

    def launch_sd_app(self, app_name: str):
        """Keer eerst netjes terug naar de BASIC '>' prompt en start dan BRUN \"<app_name>\" op D0."""
        def _worker():
            if not self.ser or not self.ser.is_open:
                if not self.connect_serial():
                    return
            self.status_var.set(f"Starten van {app_name} vanaf SD-kaart...")
            self.paused_for_tool = True
            try:
                with self.ser_lock:
                    sd_tools.ensure_basic_prompt(self.ser)
                    sd_tools._send_line_reliable(self.ser, "SD : DRIVE 0", line_wait=0.35)
                    sd_tools._send_line_reliable(self.ser, f'BRUN "{app_name}"', line_wait=0.65)
                self.status_var.set(f"{app_name} is gestart! Gebruik de knoppen rechts of het toetsenbord.")
                # Schakel automatisch naar het bijbehorende tabblad
                tab_map = {"MC": 0, "VIEWER": 1, "READER": 2, "EXCEL": 2, "FRUITY": 3, "MON6502": 3}
                if app_name in tab_map:
                    self.root.after(0, lambda: self.nb.select(tab_map[app_name]))
            finally:
                self.paused_for_tool = False

        threading.Thread(target=_worker, daemon=True).start()

    # =========================================================================
    # Midnight Commander (MC) Specifieke Helpers
    # =========================================================================
    def mc_rename_dialog(self):
        new_name = simpledialog.askstring(
            "MC Bestand Hernoemen (4)",
            "Typ de nieuwe naam voor het geselecteerde slot in MC (max 11 tekens):",
            parent=self.root,
        )
        if not new_name:
            return
        clean = "".join(ch for ch in new_name.strip().upper() if ch.isalnum() or ch in ("_", "-"))[:11]
        if not clean:
            return

        def _worker():
            self.send_raw(b"4")
            time.sleep(0.18)
            for ch in clean:
                self.send_raw(ch.encode("ascii"))
                time.sleep(0.03)
            self.send_raw(b"\r")
            self.status_var.set(f"MC: Bestand hernoemd naar '{clean}'.")

        threading.Thread(target=_worker, daemon=True).start()

    def mc_mkdir_dialog(self):
        folder_name = simpledialog.askstring(
            "MC Nieuwe Map Maken (7)",
            "Typ de naam voor de nieuwe submap in MC (max 11 tekens):",
            parent=self.root,
        )
        if not folder_name:
            return
        clean = "".join(ch for ch in folder_name.strip().upper() if ch.isalnum() or ch in ("_", "-"))[:11]
        if not clean:
            return

        def _worker():
            self.send_raw(b"7")
            time.sleep(0.18)
            for ch in clean:
                self.send_raw(ch.encode("ascii"))
                time.sleep(0.03)
            self.send_raw(b"\r")
            self.status_var.set(f"MC: Submap '{clean}' aangemaakt.")

        threading.Thread(target=_worker, daemon=True).start()

    def mc_delete_confirm(self):
        if messagebox.askyesno(
            "MC Bestand Wissen (8)",
            "Wil je het geselecteerde bestand (of lege submap) in het actieve MC-paneel wissen?",
            parent=self.root,
        ):
            self.send_raw(b"8")
            self.status_var.set("MC: Slot gewist (8).")

    def mc_select_pane_drive(self, side: str, drive_idx: int):
        """Open het Left ('L') of Right ('R') pull-down menu in MC en kies Drive D0..D3."""
        def _worker():
            # Open Left of Right menu (item 0 staat bovenaan)
            self.send_raw(side.encode("ascii"))
            time.sleep(0.12)
            for _ in range(drive_idx):
                self.pulse_direction(0x02, duration=0.05)
                time.sleep(0.09)
            self.send_raw(b"\r")
            self.status_var.set(f"MC: {'Linker' if side == 'L' else 'Rechter'} paneel ingesteld op Drive D{drive_idx}.")

        threading.Thread(target=_worker, daemon=True).start()

    # =========================================================================
    # SD-Kaart Upload & Hardware Achtergrond vanuit de Terminal
    # =========================================================================
    def quick_upload_dialog(self):
        filepath = filedialog.askopenfilename(
            title="Kies bestand om naar SD-kaart (D0) te uploaden",
            initialdir=sd_tools.SDCARD_DIR,
            filetypes=[
                ("Alle MiniGPU bestanden", "*.asm *.s *.bas *.txt *.img *.png *.jpg *.jpeg *.bmp *.gif *.bin"),
                ("6502 Assembly / Plaatjes", "*.asm *.img *.png *.jpg *.bmp"),
                ("BASIC & Tekst", "*.bas *.txt"),
                ("Alle bestanden", "*.*"),
            ],
            parent=self.root,
        )
        if not filepath:
            return

        run_after = messagebox.askyesno(
            "Direct starten na upload?",
            f"Bestand: {os.path.basename(filepath)}\n\nWil je het bestand na het uploaden naar SD-kaart D0 ook direct starten?",
            parent=self.root,
        )

        def _worker():
            if not self.ser or not self.ser.is_open:
                if not self.connect_serial():
                    return
            self.paused_for_tool = True
            self.status_var.set(f"Bezig met uploaden van {os.path.basename(filepath)} naar SD D0...")
            try:
                importlib.reload(sd_tools)
                with self.ser_lock:
                    sd_tools.upload_file_to_sdcard(
                        self.ser,
                        filepath,
                        run_after=run_after,
                        media="SD",
                        drive=0,
                    )
                self.status_var.set(f"Upload voltooid: {os.path.basename(filepath)} staat op SD-kaart D0!")
            except Exception as e:
                self.status_var.set(f"Upload fout: {e}")
            finally:
                self.paused_for_tool = False

        threading.Thread(target=_worker, daemon=True).start()

    def launch_sd_gui(self):
        """Ontkoppel de seriële poort tijdelijk en open de volledige SD-Kaart Uploader Studio GUI."""
        self.disconnect_serial()
        self.status_var.set("SD Studio GUI geopend (Klik op '🔌 Verbinden' zodra je klaar bent in SD Studio).")
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sd_gui.py")
        subprocess.Popen([sys.executable, script])

    def launch_wav_gui(self):
        """Ontkoppel de seriële poort tijdelijk en open de MiniGPU WAV Studio & SD Audio Uploader GUI."""
        self.disconnect_serial()
        self.status_var.set("WAV Studio GUI geopend (Klik op '🔌 Verbinden' zodra je klaar bent in WAV Studio).")
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wav_gui.py")
        subprocess.Popen([sys.executable, script])

    def open_bg_dialog(self):
        win = tk.Toplevel(self.root)
        win.title("🌌 Hardware Achtergrond Kiezer (1024x1024 Tile-Engine)")
        win.geometry("460x340")
        win.configure(bg="#1e293b")
        win.transient(self.root)

        tk.Label(
            win,
            text="Kies een Hardware Achtergrond:",
            font=("Segoe UI", 11, "bold"),
            fg="#38bdf8",
            bg="#1e293b",
        ).pack(pady=(12, 8))

        presets = [
            ("1. Deep Space / Melkweg & Planeet", "1", "#1d4ed8"),
            ("2. Cyberpunk / Synthwave Neon Grid", "2", "#7c3aed"),
            ("3. Retro RPG Kasteel & Fakkels", "3", "#d97706"),
            ("4. Tropisch Eiland & Koraalzee", "4", "#0284c7"),
            ("5. Boerderij Achtergrond", "5", "#0f766e"),
            ("6. Eigen Foto (.png/.jpg) Kiezen...", "6", "#16a34a"),
        ]

        def _apply_bg(choice_code):
            img_path = None
            if choice_code == "6":
                img_path = filedialog.askopenfilename(
                    title="Kies afbeelding als Hardware Achtergrond",
                    filetypes=[("Afbeeldingen", "*.png *.jpg *.jpeg *.bmp")],
                    parent=win,
                )
                if not img_path:
                    return
            win.destroy()

            def _worker():
                if not self.ser or not self.ser.is_open:
                    if not self.connect_serial():
                        return
                self.paused_for_tool = True
                self.status_var.set(f"Bezig met laden van Hardware Achtergrond ({choice_code})...")
                try:
                    importlib.reload(bg_loader)
                    with self.ser_lock:
                        sd_tools.ensure_basic_prompt(self.ser)
                        if choice_code == "6" and img_path:
                            tiles, tilemap = bg_loader.make_image_tiles_theme(img_path)
                        else:
                            _, builder = bg_loader.THEMES[choice_code]
                            tiles, tilemap = builder()
                        bg_loader.upload_bg_to_fpga(self.ser, tiles, tilemap)
                    self.status_var.set("Hardware Achtergrond geactiveerd!")
                except Exception as e:
                    self.status_var.set(f"Fout bij achtergrond laden: {e}")
                finally:
                    self.paused_for_tool = False

            threading.Thread(target=_worker, daemon=True).start()

        for lbl, code, col in presets:
            self._make_btn(win, lbl, lambda c=code: _apply_bg(c), bg=col, pady=6).pack(fill=tk.X, padx=24, pady=3)

    def on_close(self):
        self.running = False
        port = self.port_var.get().strip() or "COM6"
        self.disconnect_serial()
        _restore_dummies_server_port(port)
        self.root.destroy()


def run_cli_mode():
    """Originele tekst-console modus (beschikbaar via: python basic_terminal.py --cli)."""
    print("============================================================")
    print(f"  DONDERDAG MiniGPU-BASIC PC-Terminal ({PORT} @ {BAUD} baud)")
    print("============================================================")
    _release_dummies_server_port()
    ser = serial.Serial(PORT, BAUD, timeout=0.005)
    last_joy = 0
    pulse_joy = 0
    pulse_until = 0.0
    try:
        while True:
            data = ser.read(256)
            if data:
                sys.stdout.write(data.decode("ascii", errors="replace"))
                sys.stdout.flush()
            now = time.time()
            if now >= pulse_until:
                pulse_joy = 0
            while msvcrt.kbhit():
                ch = msvcrt.getch()
                if ch == b"\x11":
                    return
                elif ch in (b"\x00", b"\xe0"):
                    ext = msvcrt.getch()
                    if ext == b"H":
                        pulse_joy |= 0x01
                        pulse_until = now + 0.055
                    elif ext == b"P":
                        pulse_joy |= 0x02
                        pulse_until = now + 0.055
                    elif ext == b"K":
                        pulse_joy |= 0x04
                        pulse_until = now + 0.055
                    elif ext == b"M":
                        pulse_joy |= 0x08
                        pulse_until = now + 0.055
                else:
                    ser.write(ch)
            if is_pressed(VK_MENU):
                m = 0
                if is_pressed(VK_UP):
                    m |= 0x01
                if is_pressed(VK_DOWN):
                    m |= 0x02
                if is_pressed(VK_LEFT):
                    m |= 0x04
                if is_pressed(VK_RIGHT):
                    m |= 0x08
                if is_pressed(VK_SPACE):
                    m |= 0x10
                if m:
                    ser.write(bytes([0xC0 | m]))
            else:
                joy = pulse_joy
                if is_pressed(VK_UP) or is_pressed(VK_NUMPAD8):
                    joy |= 0x01
                if is_pressed(VK_DOWN) or is_pressed(VK_NUMPAD2):
                    joy |= 0x02
                if is_pressed(VK_LEFT) or is_pressed(VK_NUMPAD4):
                    joy |= 0x04
                if is_pressed(VK_RIGHT) or is_pressed(VK_NUMPAD6):
                    joy |= 0x08
                if is_pressed(VK_SPACE) or is_pressed(VK_NUMPAD0):
                    joy |= 0x10
                if is_pressed(VK_CONTROL):
                    joy |= 0x20
                if joy != last_joy:
                    ser.write(bytes([0x80 | joy]))
                    last_joy = joy
            time.sleep(0.005)
    finally:
        ser.close()


if __name__ == "__main__":
    if "--cli" in sys.argv:
        run_cli_mode()
    else:
        root = tk.Tk()
        app = BasicTerminalControlCenter(root)
        root.mainloop()
