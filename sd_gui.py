import os
import re
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, simpledialog
import serial
import serial.tools.list_ports

from sd_tools import (
    SDCARD_DIR,
    find_tang_port,
    inspect_local_file,
    ensure_basic_prompt,
    select_storage_target,
    read_sd_catalog,
    upload_file_to_sdcard,
    _send_line_reliable,
)


class SDUploaderGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("MiniGPU SD-Kaart & SDRAM-Disk Uploader Studio (Tang Nano 20K)")
        self.root.geometry("1180x760")
        self.root.minsize(1020, 640)
        self.root.configure(bg="#111827")

        self.pc_folder = SDCARD_DIR
        os.makedirs(self.pc_folder, exist_ok=True)

        self.port_var = tk.StringVar(value=find_tang_port("COM6"))
        self.media_var = tk.StringVar(value="SD")      # "SD" of "SDRAM"
        self.drive_var = tk.IntVar(value=0)            # 0..3
        self.sd_path_var = tk.StringVar(value="/")     # Huidige map op SD
        self.custom_name_var = tk.StringVar(value="")  # Optionele eigen naam op SD
        self.run_after_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value="Klaar. Kies links een of meer bestanden en rechts het gewenste SD-station (D0..D3).")
        self.busy = False

        self.pc_files_meta = []
        self.sd_slots_meta = []

        self._setup_styles()
        self._build_ui()
        self.refresh_ports()
        self.refresh_pc_files()
        # Lees na opstarten automatisch de SD-catalogus als de poort vrij is
        self.root.after(350, self.refresh_sd_catalog)

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
            "Upload.Horizontal.TProgressbar",
            troughcolor="#0f172a",
            background="#22c55e",
            thickness=18,
        )

    def _build_ui(self):
        # === 1. Titelbalk ===
        hdr = tk.Frame(self.root, bg="#0f172a", pady=8, padx=14)
        hdr.pack(fill=tk.X)
        tk.Label(
            hdr,
            text="💾 MiniGPU SD-Kaart & SDRAM-Disk Uploader Studio",
            font=("Segoe UI", 15, "bold"),
            fg="#38bdf8",
            bg="#0f172a",
        ).pack(side=tk.LEFT)
        tk.Label(
            hdr,
            text="Kies links je PC-bestanden (.asm / .bas / .txt / .bin) en rechts het station (SD/SDRAM Drive D0..D3)",
            font=("Segoe UI", 10),
            fg="#94a3b8",
            bg="#0f172a",
        ).pack(side=tk.RIGHT)

        # === 2. Bovenbalk: COM-poort + Doel-Medium (SD / SDRAM) + Drive (D0..D3) ===
        top_bar = tk.Frame(self.root, bg="#1e293b", pady=8, padx=12, bd=1, relief=tk.GROOVE)
        top_bar.pack(fill=tk.X, padx=10, pady=(8, 4))

        # COM-poort
        tk.Label(top_bar, text="Tang Nano Poort:", font=("Segoe UI", 10, "bold"), fg="#e2e8f0", bg="#1e293b").pack(side=tk.LEFT)
        self.port_combo = ttk.Combobox(top_bar, textvariable=self.port_var, width=10, font=("Consolas", 10))
        self.port_combo.pack(side=tk.LEFT, padx=(6, 4))
        tk.Button(
            top_bar,
            text="🔄 Poort",
            command=self.refresh_ports,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.LEFT, padx=(0, 16))

        # Opslagmedium: SD vs SDRAM
        tk.Label(top_bar, text="Doel-Opslag:", font=("Segoe UI", 10, "bold"), fg="#fbbf24", bg="#1e293b").pack(side=tk.LEFT)
        for val, lbl in [("SD", "💾 MicroSD-Kaart (Permanent)"), ("SDRAM", "⚡ SDRAM-Disk (4 MB RAM)")]:
            tk.Radiobutton(
                top_bar,
                text=lbl,
                variable=self.media_var,
                value=val,
                command=self.on_target_changed,
                bg="#1e293b",
                fg="#f8fafc",
                selectcolor="#0f172a",
                activebackground="#1e293b",
                activeforeground="#38bdf8",
                font=("Segoe UI", 10, "bold"),
            ).pack(side=tk.LEFT, padx=6)

        # Drive D0..D3 knoppen
        tk.Label(top_bar, text="   Station (Drive):", font=("Segoe UI", 10, "bold"), fg="#fbbf24", bg="#1e293b").pack(side=tk.LEFT, padx=(10, 4))
        self.drive_btns = []
        for d in range(4):
            btn = tk.Radiobutton(
                top_bar,
                text=f"Drive D{d}",
                variable=self.drive_var,
                value=d,
                indicatoron=False,
                command=self.on_target_changed,
                font=("Consolas", 10, "bold"),
                bg="#334155",
                fg="#f8fafc",
                selectcolor="#0284c7",
                activebackground="#0369a1",
                padx=10,
                pady=3,
            )
            btn.pack(side=tk.LEFT, padx=3)
            self.drive_btns.append(btn)

        # === 3. Hoofdpaneel (Links = PC, Midden = Upload-acties, Rechts = SD-Kaart Catalogus) ===
        main_frame = tk.Frame(self.root, bg="#111827")
        main_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=6)
        main_frame.columnconfigure(0, weight=5)
        main_frame.columnconfigure(1, weight=0)
        main_frame.columnconfigure(2, weight=5)
        main_frame.rowconfigure(0, weight=1)

        # --- LINKER PANEEL: PC Bestanden ---
        left_frame = tk.LabelFrame(
            main_frame,
            text=" 💻 1. Bestanden op je PC (Kies wat je wilt uploaden) ",
            font=("Segoe UI", 10, "bold"),
            fg="#38bdf8",
            bg="#111827",
            padx=8,
            pady=6,
        )
        left_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 6))

        pc_top = tk.Frame(left_frame, bg="#111827")
        pc_top.pack(fill=tk.X, pady=(0, 6))
        self.lbl_pc_dir = tk.Label(
            pc_top,
            text=f"Map: {self.pc_folder}",
            font=("Consolas", 9),
            fg="#94a3b8",
            bg="#111827",
            anchor="w",
        )
        self.lbl_pc_dir.pack(side=tk.LEFT, fill=tk.X, expand=True)
        tk.Button(
            pc_top,
            text="📂 Andere Map...",
            command=self.choose_pc_folder,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.RIGHT, padx=2)
        tk.Button(
            pc_top,
            text="📄 Los Bestand...",
            command=self.choose_single_pc_file,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.RIGHT, padx=2)

        pc_tree_frame = tk.Frame(left_frame, bg="#111827")
        pc_tree_frame.pack(fill=tk.BOTH, expand=True)

        cols_pc = ("filename", "sd_name", "type", "org", "size")
        self.tree_pc = ttk.Treeview(pc_tree_frame, columns=cols_pc, show="headings", selectmode="extended")
        self.tree_pc.heading("filename", text="PC Bestandsnaam")
        self.tree_pc.heading("sd_name", text="SD Naam")
        self.tree_pc.heading("type", text="Type")
        self.tree_pc.heading("org", text="Adres")
        self.tree_pc.heading("size", text="Grootte (max 4095B)")

        self.tree_pc.column("filename", width=135, anchor="w")
        self.tree_pc.column("sd_name", width=95, anchor="w")
        self.tree_pc.column("type", width=105, anchor="w")
        self.tree_pc.column("org", width=65, anchor="center")
        self.tree_pc.column("size", width=120, anchor="e")

        sb_pc = ttk.Scrollbar(pc_tree_frame, orient=tk.VERTICAL, command=self.tree_pc.yview)
        self.tree_pc.configure(yscrollcommand=sb_pc.set)
        self.tree_pc.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sb_pc.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree_pc.bind("<<TreeviewSelect>>", self.on_pc_select)
        self.tree_pc.bind("<Double-1>", lambda e: self.upload_selected(run_override=False))

        pc_bot = tk.Frame(left_frame, bg="#111827", pady=6)
        pc_bot.pack(fill=tk.X)
        tk.Button(
            pc_bot,
            text="☑️ Alles Selecteren",
            command=self.select_all_pc,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.LEFT, padx=2)
        tk.Button(
            pc_bot,
            text="🔄 Ververs PC-Lijst",
            command=self.refresh_pc_files,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.LEFT, padx=4)

        # Eigen SD-naam optie
        name_row = tk.Frame(left_frame, bg="#1e293b", padx=8, pady=6)
        name_row.pack(fill=tk.X, pady=(2, 0))
        tk.Label(
            name_row,
            text="Opslaan op SD onder naam:",
            font=("Segoe UI", 9, "bold"),
            fg="#fbbf24",
            bg="#1e293b",
        ).pack(side=tk.LEFT)
        self.ent_sd_name = tk.Entry(
            name_row,
            textvariable=self.custom_name_var,
            width=16,
            font=("Consolas", 10, "bold"),
            bg="#0f172a",
            fg="#38bdf8",
            insertbackground="#38bdf8",
        )
        self.ent_sd_name.pack(side=tk.LEFT, padx=6)
        tk.Label(
            name_row,
            text="(leeg = originele naam)",
            font=("Segoe UI", 8),
            fg="#94a3b8",
            bg="#1e293b",
        ).pack(side=tk.LEFT)

        # --- MIDDEN KOLOM: Actieknoppen ---
        mid_frame = tk.Frame(main_frame, bg="#111827", padx=6)
        mid_frame.grid(row=0, column=1, sticky="ns")

        tk.Label(mid_frame, text="ACTIES", font=("Segoe UI", 9, "bold"), fg="#94a3b8", bg="#111827").pack(pady=(35, 8))

        self.btn_upload = tk.Button(
            mid_frame,
            text="➡️ Upload naar\nSD-Kaart",
            command=lambda: self.upload_selected(run_override=None),
            font=("Segoe UI", 10, "bold"),
            bg="#16a34a",
            fg="#ffffff",
            activebackground="#15803d",
            relief=tk.FLAT,
            width=17,
            pady=10,
        )
        self.btn_upload.pack(pady=6)

        self.btn_upload_run = tk.Button(
            mid_frame,
            text="🚀 Upload &\nDirect Starten!",
            command=lambda: self.upload_selected(run_override=True),
            font=("Segoe UI", 10, "bold"),
            bg="#0284c7",
            fg="#ffffff",
            activebackground="#0369a1",
            relief=tk.FLAT,
            width=17,
            pady=10,
        )
        self.btn_upload_run.pack(pady=6)

        self.btn_ram_only = tk.Button(
            mid_frame,
            text="⚡ Test in RAM\n(Zonder SD-Save)",
            command=lambda: self.upload_selected(run_override=True, save_to_sd=False),
            font=("Segoe UI", 9, "bold"),
            bg="#d97706",
            fg="#ffffff",
            activebackground="#b45309",
            relief=tk.FLAT,
            width=17,
            pady=8,
        )
        self.btn_ram_only.pack(pady=6)

        tk.Checkbutton(
            mid_frame,
            text="Start na upload",
            variable=self.run_after_var,
            bg="#111827",
            fg="#e2e8f0",
            selectcolor="#0f172a",
            activebackground="#111827",
            font=("Segoe UI", 9),
        ).pack(pady=6)

        ttk.Separator(mid_frame, orient=tk.HORIZONTAL).pack(fill=tk.X, pady=12)

        tk.Button(
            mid_frame,
            text="🗂️ Start MC\nop Tang Nano",
            command=lambda: self.run_sd_command('BRUN "MC"'),
            font=("Segoe UI", 9, "bold"),
            bg="#4f46e5",
            fg="#ffffff",
            relief=tk.FLAT,
            width=17,
            pady=7,
        ).pack(pady=4)

        tk.Button(
            mid_frame,
            text="🛑 Stop App (ESC)\nNaar BASIC",
            command=self.stop_running_app,
            font=("Segoe UI", 9),
            bg="#dc2626",
            fg="#ffffff",
            relief=tk.FLAT,
            width=17,
            pady=6,
        ).pack(pady=4)

        # --- RECHTER PANEEL: Tang Nano 20K SD-Kaart Catalogus ---
        right_frame = tk.LabelFrame(
            main_frame,
            text=" 💾 2. Bestemming op Tang Nano 20K (15 Slots per Drive / Map) ",
            font=("Segoe UI", 10, "bold"),
            fg="#fbbf24",
            bg="#111827",
            padx=8,
            pady=6,
        )
        right_frame.grid(row=0, column=2, sticky="nsew", padx=(6, 0))

        sd_top = tk.Frame(right_frame, bg="#111827")
        sd_top.pack(fill=tk.X, pady=(0, 6))
        self.lbl_sd_hdr = tk.Label(
            sd_top,
            text="[SD-KAART D0] Pad: /",
            font=("Consolas", 10, "bold"),
            fg="#22c55e",
            bg="#111827",
            anchor="w",
        )
        self.lbl_sd_hdr.pack(side=tk.LEFT, fill=tk.X, expand=True)

        tk.Button(
            sd_top,
            text="⬆️ Map Omhoog (..)",
            command=self.sd_cd_up,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=7,
        ).pack(side=tk.RIGHT, padx=2)
        tk.Button(
            sd_top,
            text="📁 Nieuwe Map",
            command=self.sd_mkdir,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=7,
        ).pack(side=tk.RIGHT, padx=2)
        tk.Button(
            sd_top,
            text="🔄 Lees SD (CAT)",
            command=self.refresh_sd_catalog,
            bg="#0284c7",
            fg="#ffffff",
            font=("Segoe UI", 9, "bold"),
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.RIGHT, padx=2)

        sd_tree_frame = tk.Frame(right_frame, bg="#111827")
        sd_tree_frame.pack(fill=tk.BOTH, expand=True)

        cols_sd = ("slot", "name", "type", "size", "status")
        self.tree_sd = ttk.Treeview(sd_tree_frame, columns=cols_sd, show="headings", selectmode="browse")
        self.tree_sd.heading("slot", text="Slot")
        self.tree_sd.heading("name", text="Naam op SD-Kaart")
        self.tree_sd.heading("type", text="Type")
        self.tree_sd.heading("size", text="Grootte")
        self.tree_sd.heading("status", text="Slot Status")

        self.tree_sd.column("slot", width=55, anchor="center")
        self.tree_sd.column("name", width=140, anchor="w")
        self.tree_sd.column("type", width=95, anchor="center")
        self.tree_sd.column("size", width=90, anchor="e")
        self.tree_sd.column("status", width=130, anchor="w")

        sb_sd = ttk.Scrollbar(sd_tree_frame, orient=tk.VERTICAL, command=self.tree_sd.yview)
        self.tree_sd.configure(yscrollcommand=sb_sd.set)
        self.tree_sd.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sb_sd.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree_sd.bind("<<TreeviewSelect>>", self.on_sd_select)
        self.tree_sd.bind("<Double-1>", self.on_sd_double_click)

        sd_bot = tk.Frame(right_frame, bg="#111827", pady=6)
        sd_bot.pack(fill=tk.X)
        tk.Button(
            sd_bot,
            text="▶️ Start op Tang Nano (BRUN)",
            command=self.start_selected_sd_item,
            bg="#16a34a",
            fg="#ffffff",
            font=("Segoe UI", 9, "bold"),
            relief=tk.FLAT,
            padx=10,
        ).pack(side=tk.LEFT, padx=2)
        tk.Button(
            sd_bot,
            text="📜 Laad als BASIC (LOAD)",
            command=self.load_selected_sd_basic,
            bg="#334155",
            fg="#f8fafc",
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.LEFT, padx=4)
        tk.Button(
            sd_bot,
            text="🗑️ Wis van SD (DEL)",
            command=self.delete_selected_sd_item,
            bg="#dc2626",
            fg="#ffffff",
            relief=tk.FLAT,
            padx=8,
        ).pack(side=tk.RIGHT, padx=2)

        # === 4. Onderbalk: Voortgangsbalk + Logvenster ===
        bot_frame = tk.Frame(self.root, bg="#0f172a", padx=12, pady=8)
        bot_frame.pack(fill=tk.X, padx=10, pady=(2, 8))

        prog_row = tk.Frame(bot_frame, bg="#0f172a")
        prog_row.pack(fill=tk.X, pady=(0, 6))
        self.lbl_status = tk.Label(
            prog_row,
            textvariable=self.status_var,
            font=("Consolas", 10, "bold"),
            fg="#38bdf8",
            bg="#0f172a",
            anchor="w",
        )
        self.lbl_status.pack(side=tk.LEFT, fill=tk.X, expand=True)

        self.progress = ttk.Progressbar(
            bot_frame,
            orient=tk.HORIZONTAL,
            mode="determinate",
            style="Upload.Horizontal.TProgressbar",
        )
        self.progress.pack(fill=tk.X, pady=(0, 6))

        self.log_text = tk.Text(
            bot_frame,
            height=5,
            bg="#020617",
            fg="#a7f3d0",
            font=("Consolas", 9),
            relief=tk.FLAT,
            padx=8,
            pady=4,
        )
        self.log_text.pack(fill=tk.X)
        self.log("Welkom! Selecteer links een bestand (of meerdere met Ctrl/Shift) en klik op 'Upload naar SD-Kaart'.")

    def log(self, msg):
        def _append():
            self.log_text.insert(tk.END, msg.rstrip() + "\n")
            self.log_text.see(tk.END)
        self.root.after(0, _append)

    def set_progress(self, done, total, msg=None):
        def _upd():
            pct = (done * 100.0 / total) if total > 0 else 0
            self.progress["value"] = pct
            if msg:
                self.status_var.set(msg)
        self.root.after(0, _upd)

    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        if not ports:
            ports = ["COM6"]
        self.port_combo["values"] = ports
        detected = find_tang_port(self.port_var.get() or "COM6")
        if detected in ports:
            self.port_var.set(detected)

    def refresh_pc_files(self):
        self.lbl_pc_dir.config(text=f"Map: {self.pc_folder}")
        for item in self.tree_pc.get_children():
            self.tree_pc.delete(item)
        self.pc_files_meta.clear()

        if not os.path.isdir(self.pc_folder):
            return

        files = sorted(
            f for f in os.listdir(self.pc_folder)
            if os.path.splitext(f)[1].lower() in (".bas", ".asm", ".s", ".bin", ".txt", ".img", ".png", ".jpg", ".jpeg", ".bmp", ".gif")
        )
        for fn in files:
            full = os.path.join(self.pc_folder, fn)
            meta = inspect_local_file(full)
            self.pc_files_meta.append(meta)
            sz = meta["size_bytes"]
            pct = min(100, int(round(sz * 100 / 4095))) if sz else 0
            sz_str = f"{sz} B ({pct}%)" if not meta["error"] else "FOUT!"
            self.tree_pc.insert(
                "",
                tk.END,
                iid=full,
                values=(meta["filename"], meta["sd_name"], meta["type_label"], meta["org_hex"], sz_str),
            )

    def choose_pc_folder(self):
        folder = filedialog.askdirectory(initialdir=self.pc_folder, title="Kies map met MiniGPU bestanden")
        if folder:
            self.pc_folder = folder
            self.refresh_pc_files()

    def choose_single_pc_file(self):
        fp = filedialog.askopenfilename(
            initialdir=self.pc_folder,
            title="Kies een .asm, .bas, .txt, .img, .png, .jpg of .bin bestand",
            filetypes=[
                ("MiniGPU & Plaatjes", "*.asm *.s *.bas *.txt *.bin *.img *.png *.jpg *.jpeg *.bmp *.gif"),
                ("Alle bestanden", "*.*"),
            ],
        )
        if fp:
            self.pc_folder = os.path.dirname(fp)
            self.refresh_pc_files()
            if fp in self.tree_pc.get_children():
                self.tree_pc.selection_set(fp)
                self.tree_pc.see(fp)
                self.on_pc_select(None)

    def select_all_pc(self):
        self.tree_pc.selection_set(self.tree_pc.get_children())

    def on_pc_select(self, _event):
        sel = self.tree_pc.selection()
        if len(sel) == 1:
            vals = self.tree_pc.item(sel[0], "values")
            if vals:
                self.custom_name_var.set(vals[1])
        elif len(sel) > 1:
            self.custom_name_var.set("")

    def on_sd_select(self, _event):
        sel = self.tree_sd.selection()
        if not sel:
            return
        vals = self.tree_sd.item(sel[0], "values")
        if vals and vals[1] and vals[1] != "- vrij slot -":
            # Klikken op een bestaand SD-slot neemt die naam over als je hem wilt overschrijven
            if len(self.tree_pc.selection()) <= 1:
                self.custom_name_var.set(vals[1])

    def on_target_changed(self):
        self.sd_path_var.set("/")
        self.refresh_sd_catalog()

    def _run_serial_task(self, task_fn):
        if self.busy:
            messagebox.showinfo("Even geduld", "Er loopt al een communicatie-actie met de Tang Nano 20K.")
            return
        self.busy = True
        self.btn_upload.config(state=tk.DISABLED)
        self.btn_upload_run.config(state=tk.DISABLED)
        self.btn_ram_only.config(state=tk.DISABLED)

        def _worker():
            ser = None
            try:
                port = self.port_var.get().strip() or "COM6"
                ser = serial.Serial(port, 115200, timeout=0.5)
                task_fn(ser)
            except Exception as e:
                self.log(f"[FOUT] {e}")
                self.set_progress(0, 100, f"Fout op {self.port_var.get()}: {e}")
            finally:
                if ser and ser.is_open:
                    ser.close()
                self.busy = False
                self.root.after(0, lambda: (
                    self.btn_upload.config(state=tk.NORMAL),
                    self.btn_upload_run.config(state=tk.NORMAL),
                    self.btn_ram_only.config(state=tk.NORMAL),
                ))

        threading.Thread(target=_worker, daemon=True).start()

    def _populate_sd_tree(self, slots, header):
        def _upd():
            for item in self.tree_sd.get_children():
                self.tree_sd.delete(item)
            used_count = sum(1 for s in slots if s["used"])
            media_lbl = "SD-KAART" if self.media_var.get() == "SD" else "SDRAM-DISK"
            drv = self.drive_var.get()
            path = self.sd_path_var.get()
            self.lbl_sd_hdr.config(
                text=f"[{media_lbl} D{drv}] Pad: {path}  ({used_count}/15 slots bezet)"
            )
            for s in slots:
                slot_id = f"#{s['slot']}"
                if s["used"]:
                    if s["is_dir"]:
                        self.tree_sd.insert(
                            "",
                            tk.END,
                            iid=str(s["slot"]),
                            values=(slot_id, s["name"], "📁 <MAP>", "--", "Submap (dubbelklik)"),
                        )
                    else:
                        self.tree_sd.insert(
                            "",
                            tk.END,
                            iid=str(s["slot"]),
                            values=(slot_id, s["name"], "Bestand", f"{s['size']} B", "Bezet (klik = overschrijf)"),
                        )
                else:
                    self.tree_sd.insert(
                        "",
                        tk.END,
                        iid=str(s["slot"]),
                        values=(slot_id, "- vrij slot -", "Leeg", "0 B", "Beschikbaar (4095 B vrij)"),
                    )
        self.root.after(0, _upd)

    def refresh_sd_catalog(self):
        def _task(ser):
            media = self.media_var.get()
            drv = self.drive_var.get()
            self.set_progress(10, 100, f"Lezen van [{media} D{drv}] catalogus...")
            slots, hdr, _raw = read_sd_catalog(ser, media=media, drive=drv)
            self.sd_slots_meta = slots
            self._populate_sd_tree(slots, hdr)
            used = sum(1 for s in slots if s["used"])
            self.set_progress(100, 100, f"[{media} D{drv}] Catalogus geladen: {used}/15 slots in gebruik.")
            self.log(f"[CAT] [{media} D{drv}] ({self.sd_path_var.get()}): {used}/15 slots bezet.")

        self._run_serial_task(_task)

    def upload_selected(self, run_override=None, save_to_sd=True):
        sel = list(self.tree_pc.selection())
        if not sel:
            messagebox.showwarning("Geen bestand gekozen", "Selecteer eerst links in de PC-lijst één of meer bestanden om te uploaden!")
            return

        media = self.media_var.get()
        drv = self.drive_var.get()
        custom_name = self.custom_name_var.get().strip() if len(sel) == 1 else None
        do_run = self.run_after_var.get() if run_override is None else run_override

        def _task(ser):
            total_files = len(sel)
            for idx, filepath in enumerate(sel, 1):
                fname = os.path.basename(filepath)
                run_this = do_run and (idx == total_files)
                self.log(f"Start upload ({idx}/{total_files}): {fname} -> [{media} D{drv}]...")
                sd_name, ftype = upload_file_to_sdcard(
                    ser,
                    filepath,
                    run_after=run_this,
                    sd_name_override=custom_name if total_files == 1 else None,
                    media=media,
                    drive=drv,
                    save_to_sd=save_to_sd,
                    progress_cb=self.set_progress,
                )
                if save_to_sd:
                    self.log(f"✅ '{fname}' opgeslagen als '{sd_name}' ({ftype}) op [{media} D{drv}]!")
                else:
                    self.log(f"⚡ '{fname}' direct in RAM geladen en gestart!")

            if save_to_sd and not do_run:
                slots, hdr, _ = read_sd_catalog(ser, media=media, drive=drv)
                self.sd_slots_meta = slots
                self._populate_sd_tree(slots, hdr)
                self.set_progress(100, 100, f"Klaar! {total_files} bestand(en) opgeslagen op [{media} D{drv}].")
            elif do_run:
                self.set_progress(100, 100, f"Klaar! '{sd_name}' draait nu live op je Tang Nano 20K scherm!")

        self._run_serial_task(_task)

    def on_sd_double_click(self, _event):
        sel = self.tree_sd.selection()
        if not sel:
            return
        slot_idx = int(sel[0])
        if slot_idx < len(self.sd_slots_meta):
            slot = self.sd_slots_meta[slot_idx]
            if not slot["used"]:
                return
            if slot["is_dir"]:
                self.sd_cd_into(slot["name"])
            else:
                self.start_selected_sd_item()

    def sd_cd_into(self, dirname):
        def _task(ser):
            ensure_basic_prompt(ser)
            select_storage_target(ser, media=self.media_var.get(), drive=self.drive_var.get())
            out = _send_line_reliable(ser, f'CD "{dirname}"', char_delay=0.003, line_wait=0.8)
            self.log(f'CD "{dirname}" -> {out.strip()}')
            cur = self.sd_path_var.get().rstrip("/")
            self.sd_path_var.set(f"{cur}/{dirname}")
            slots, hdr, _ = read_sd_catalog(ser)
            self.sd_slots_meta = slots
            self._populate_sd_tree(slots, hdr)

        self._run_serial_task(_task)

    def sd_cd_up(self):
        def _task(ser):
            ensure_basic_prompt(ser)
            select_storage_target(ser, media=self.media_var.get(), drive=self.drive_var.get())
            out = _send_line_reliable(ser, "CD ..", char_delay=0.003, line_wait=0.8)
            self.log(f"CD .. -> {out.strip()}")
            cur = self.sd_path_var.get().rstrip("/")
            if "/" in cur:
                parent = cur.rsplit("/", 1)[0] or "/"
            else:
                parent = "/"
            self.sd_path_var.set(parent)
            slots, hdr, _ = read_sd_catalog(ser)
            self.sd_slots_meta = slots
            self._populate_sd_tree(slots, hdr)

        self._run_serial_task(_task)

    def sd_mkdir(self):
        name = simpledialog.askstring("Nieuwe Map (MKDIR)", "Geef een naam voor de nieuwe map op de SD-kaart (max 14 tekens):")
        if not name:
            return
        clean = re.sub(r"[^A-Z0-9_]", "", name.upper())[:14]
        if not clean:
            return

        def _task(ser):
            ensure_basic_prompt(ser)
            select_storage_target(ser, media=self.media_var.get(), drive=self.drive_var.get())
            out = _send_line_reliable(ser, f'MKDIR "{clean}"', char_delay=0.003, line_wait=1.2)
            self.log(f'MKDIR "{clean}" -> {out.strip()}')
            slots, hdr, _ = read_sd_catalog(ser)
            self.sd_slots_meta = slots
            self._populate_sd_tree(slots, hdr)

        self._run_serial_task(_task)

    def start_selected_sd_item(self):
        sel = self.tree_sd.selection()
        if not sel:
            messagebox.showinfo("Kies een SD-slot", "Selecteer eerst rechts in de SD-lijst een programma om te starten.")
            return
        slot_idx = int(sel[0])
        if slot_idx >= len(self.sd_slots_meta) or not self.sd_slots_meta[slot_idx]["used"]:
            messagebox.showinfo("Leeg slot", "Dit SD-slot is leeg.")
            return
        slot = self.sd_slots_meta[slot_idx]
        if slot["is_dir"]:
            self.sd_cd_into(slot["name"])
            return
        name = slot["name"]
        self.run_sd_command(f'BRUN "{name}"')

    def load_selected_sd_basic(self):
        sel = self.tree_sd.selection()
        if not sel:
            return
        slot_idx = int(sel[0])
        if slot_idx >= len(self.sd_slots_meta) or not self.sd_slots_meta[slot_idx]["used"]:
            return
        name = self.sd_slots_meta[slot_idx]["name"]

        def _task(ser):
            ensure_basic_prompt(ser)
            select_storage_target(ser, media=self.media_var.get(), drive=self.drive_var.get())
            out = _send_line_reliable(ser, f'LOAD "{name}"', char_delay=0.003, line_wait=1.2)
            self.log(f'LOAD "{name}" -> {out.strip()}')
            _send_line_reliable(ser, "RUN", char_delay=0.003, line_wait=0.4)
            self.set_progress(100, 100, f'BASIC programma "{name}" geladen en gestart (RUN)!')

        self._run_serial_task(_task)

    def delete_selected_sd_item(self):
        sel = self.tree_sd.selection()
        if not sel:
            return
        slot_idx = int(sel[0])
        if slot_idx >= len(self.sd_slots_meta) or not self.sd_slots_meta[slot_idx]["used"]:
            return
        name = self.sd_slots_meta[slot_idx]["name"]
        media = self.media_var.get()
        drv = self.drive_var.get()
        if not messagebox.askyesno("Bevestig Wissen", f'Wil je "{name}" echt wissen van [{media} D{drv}]?'):
            return

        def _task(ser):
            ensure_basic_prompt(ser)
            select_storage_target(ser, media=media, drive=drv)
            out = _send_line_reliable(ser, f'DEL "{name}"', char_delay=0.003, line_wait=1.2)
            self.log(f'DEL "{name}" -> {out.strip()}')
            slots, hdr, _ = read_sd_catalog(ser, media=media, drive=drv)
            self.sd_slots_meta = slots
            self._populate_sd_tree(slots, hdr)
            self.set_progress(100, 100, f'"{name}" gewist van [{media} D{drv}].')

        self._run_serial_task(_task)

    def run_sd_command(self, cmd):
        def _task(ser):
            ensure_basic_prompt(ser)
            select_storage_target(ser, media=self.media_var.get(), drive=self.drive_var.get())
            _send_line_reliable(ser, cmd, char_delay=0.003, line_wait=0.6)
            self.log(f"Uitgevoerd op Tang Nano: {cmd}")
            self.set_progress(100, 100, f"Commando uitgevoerd: {cmd}")

        self._run_serial_task(_task)

    def stop_running_app(self):
        def _task(ser):
            ensure_basic_prompt(ser)
            self.log("Gestopt (ESC) -> Terug op BASIC '>' prompt.")
            self.set_progress(100, 100, "Programma gestopt; Tang Nano staat klaar op de BASIC '>' prompt.")

        self._run_serial_task(_task)


def launch_gui():
    root = tk.Tk()
    app = SDUploaderGUI(root)
    root.mainloop()


if __name__ == "__main__":
    launch_gui()
