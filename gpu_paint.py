import tkinter as tk
from tkinter import colorchooser, ttk, messagebox, simpledialog, filedialog
import serial
import serial.tools.list_ports
import struct
import time
import os
import sys
from PIL import Image, ImageTk, ImageDraw, ImageFont

# =============================================================================
# OPTIONELE IMPORT VAN BESTAANDE TILES, SPRITES & BASIC SD-TOOLS
# =============================================================================
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
for _cand_dir in [
    _THIS_DIR,
    os.path.join(_THIS_DIR, "DONDERDAG_BASIC"),
    os.path.join(_THIS_DIR, "DONDERDAG"),
    os.path.join(os.path.dirname(_THIS_DIR), "DONDERDAG_BASIC"),
    os.path.join(os.path.dirname(_THIS_DIR), "DONDERDAG"),
]:
    if os.path.isdir(_cand_dir) and _cand_dir not in sys.path:
        sys.path.insert(0, _cand_dir)

try:
    from boerderij_game import TILES as FARM_TILES, SPRITES as FARM_SPRITES, PAL_RGB332
except Exception:
    FARM_TILES = {}
    FARM_SPRITES = {}
    PAL_RGB332 = {
        'T': 0xE3, 'Z': 0x00, 'W': 0xFF, 'G': 0x1C, 'V': 0x08, 'A': 0x54,
        'B': 0x03, 'U': 0x5F, 'S': 0x7F, 'D': 0x48, 'L': 0x4D, 'K': 0x24,
        'O': 0xEC, 'Y': 0xFC, 'R': 0xE0, 'M': 0xC4, 'P': 0xF3, 'E': 0xF6,
        'H': 0x68, 'J': 0x8C, 'N': 0xFF, 'I': 0x92, 'C': 0x49
    }

def _find_asset_file(filename):
    for d in sys.path:
        p = os.path.join(d, filename)
        if os.path.isfile(p):
            return p
    return filename

# Namen van de 42 standaard tegels
TILE_NAMES = {
    0: "Fris Weidegras", 1: "Zandpad / Aarde", 2: "Droge Akkergrond", 3: "Natte Akkergrond",
    4: "Hek Horizontaal", 5: "Hek Verticaal", 6: "Hekpaal / Hoek", 7: "Schuur Houten Muur",
    8: "Schuur Rood Dak", 9: "Schuur Houten Deur", 10: "Huis Houten Muur", 11: "Huis Blauw Dak",
    12: "Huis Houten Deur", 13: "Loofboom / Bos", 14: "Appelboom", 15: "Houtstronk",
    16: "Rots / Kei", 17: "Blauw Vijverwater", 18: "Waterlelie", 19: "Verkoopkist (Shipping)",
    20: "Voertrog Hooi", 21: "Nestkast met Ei", 22: "Gouden Hooibaal", 23: "Boerderijbed",
    24: "Houten Tafel", 25: "Houten Stoel", 26: "Houten Brug", 27: "Bloembed",
    28: "Wortels Volgroeid", 29: "Tarwe Volgroeid", 30: "Aardbeien Volgroeid", 31: "Maïs Volgroeid",
    32: "Kiem / Zaailing", 33: "Waterput / Pomp", 34: "Lieve Melkkoe", 35: "Schaap Fluffy (met wol)",
    36: "Schaap Geschoren", 37: "Kakelverse Legkip", 38: "Roze Varkentje", 39: "Trouwe Boerderijhond",
    40: "Gezellige Eend", 41: "Dorpshandelaar"
}

# 24 Levendige Retro 8-bit Kleuren voor Sprites en Tegels
PALETTE_24 = [
    (0x00, "#000000", "Zwart"),
    (0x49, "#494955", "Donkergrijs"),
    (0x92, "#9292aa", "Grijs"),
    (0xFF, "#ffffff", "Wit"),
    (0xE0, "#ff0000", "Rood"),
    (0x80, "#920000", "Donkerrood"),
    (0xEC, "#ff9200", "Oranje"),
    (0xFC, "#ffff00", "Geel"),
    (0x7C, "#92ff00", "Limoen"),
    (0x1C, "#00ff00", "Grasgroen"),
    (0x0C, "#009200", "Donkergroen"),
    (0x08, "#004900", "Woudgroen"),
    (0x1E, "#00ffaa", "Muntgroen"),
    (0x1F, "#00ffff", "Cyaan"),
    (0x5B, "#4992ff", "Hemelsblauw"),
    (0x03, "#0000ff", "Blauw"),
    (0x01, "#000055", "Marine"),
    (0x83, "#9200ff", "Paars"),
    (0xF2, "#ff49aa", "Roze"),
    (0xFD, "#ffff55", "Lichtgeel"),
    (0xED, "#ff9255", "Huid / Perzik"),
    (0xB5, "#dbb655", "Zandpad"),
    (0x68, "#804900", "Houtbruin"),
    (0x48, "#492400", "Donkerbruin"),
]

# =============================================================================
# HOOFDAPPLICATIE: MINIGPU STUDIO & PAINT
# =============================================================================

class MiniGPUPaint:
    def __init__(self, root):
        self.root = root
        self.root.title("MiniGPU-BASIC Paint & Studio 1.1 - Tang Nano 20K FPGA (115200 Baud + BASIC Export)")
        self.root.geometry("920x680")
        self.root.minsize(860, 620)
        
        self.ser = None
        self.current_tool = "line"
        self.color_rgb332 = 0xFF # Startkleur wit
        self.points = []
        self.basic_commands = ["MODE 1", "CLEAR $00"]
        
        # Tekst & Lettergrootte instellingen (1x=8px t/m 8x=64px met het vaste 8x8 FPGA font)
        self.font8x8 = self.load_font8x8()
        self.text_scale_var = tk.IntVar(value=2)
        
        # 32 Sprites in geheugen (elk 256 bytes, 0xE3 = transparant)
        self.sprite_bank = self.create_default_sprites()
        
        # 64 Tegels in geheugen (elk 256 bytes, BRAM achtergrond)
        self.tile_bank = self.create_default_tiles()
        
        # 64x64 Achtergrondkaart (4096 bytes)
        self.tilemap = self.create_default_tilemap()

        # 2 Gigantische Hardware Sprites (128x128 pixels, elk 16.384 bytes)
        self.big_sprite_bank = self.create_default_big_sprites()
        self.big_spr_x = [256, 100]
        self.big_spr_y = [116, 80]
        self.big_spr_en = [False, False]
        self.big_spr_flip = [False, False]
        
        self.setup_ui()
        self.refresh_ports()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close_window)

    def record_basic(self, stmt):
        """Registreer een MiniGPU-BASIC commando voor export/opslag naar de SD-kaart."""
        if stmt:
            self.basic_commands.append(stmt)

    def on_close_window(self):
        if self.ser is not None:
            try:
                self._switch_to_basic_mode()
                self.ser.close()
            except Exception:
                pass
            self.ser = None
        self.root.destroy()

    def _switch_to_gpu_mode(self):
        """Schakelt de Tang Nano 20K vanuit MiniGPU-BASIC veilig naar raw GPU-modus (\x1BGPU) met MODE 1."""
        if not self.ser:
            return
        self.ser.write(b'\x1bTXT\x08\x08\x08\x08\r\x1b')
        time.sleep(0.12)
        self.ser.write(b'\rMODE 1\r')
        time.sleep(0.10)
        try:
            self.ser.read(4096)
        except Exception:
            pass
        self.ser.write(b'\x1BGPU')
        time.sleep(0.04)

    def _switch_to_basic_mode(self):
        """Schakelt de Tang Nano 20K terug naar de MiniGPU-BASIC prompt zonder 'GPU' in de invoerbuffer."""
        if not self.ser:
            return
        self.ser.write(b'\x1BTXT\x08\x08\x08\x08\rMODE 0\r')
        time.sleep(0.10)
        try:
            self.ser.read(4096)
        except Exception:
            pass
        
    def rgb332_to_hex(self, color_val):
        r = ((color_val >> 5) & 0x07) * 255 // 7
        g = ((color_val >> 2) & 0x07) * 255 // 7
        b = (color_val & 0x03) * 255 // 3
        return f"#{r:02x}{g:02x}{b:02x}"

    def rgb332_to_tk(self, color_val):
        if color_val == 0xE3:
            return ""
        return self.rgb332_to_hex(color_val)

    def get_tk_color(self):
        return self.rgb332_to_tk(self.color_rgb332) or "#ffffff"

    def get_default_sd_path(self):
        sd_dir = os.path.join(_THIS_DIR, "sdcard")
        if os.path.isdir(sd_dir):
            return sd_dir
        for drive in ["D:\\", "E:\\", "F:\\"]:
            if os.path.exists(drive):
                return drive
        return os.getcwd()

    # -------------------------------------------------------------------------
    # STANDAARD SPRITES & TEGELS LADEN (UIT DEFAULT_*.HEX OF *.BIN)
    # -------------------------------------------------------------------------
    def create_default_sprites(self):
        bank = [bytearray([0xE3]*256) for _ in range(32)]
        hex_p = _find_asset_file("default_sprites.hex")
        if os.path.exists(hex_p):
            try:
                with open(hex_p, "r") as f:
                    vals = [int(ln.strip(), 16) for ln in f if ln.strip()]
                for s_id in range(min(32, len(vals) // 256)):
                    bank[s_id] = bytearray(vals[s_id*256 : (s_id+1)*256])
                return bank
            except Exception:
                pass

        bin_p = _find_asset_file("sprites.bin")
        if os.path.exists(bin_p):
            try:
                with open(bin_p, "rb") as f:
                    data = f.read()
                num = min(32, len(data) // 256)
                for s_id in range(num):
                    bank[s_id] = bytearray(data[s_id*256 : (s_id+1)*256])
                return bank
            except Exception:
                pass
                
        if FARM_SPRITES:
            for s_id, pat in FARM_SPRITES.items():
                if 0 <= s_id < 32:
                    buf = bytearray(256)
                    for y in range(16):
                        row = pat[y] if y < len(pat) else " "*16
                        for x in range(16):
                            ch = row[x] if x < len(row) else 'T'
                            buf[y*16 + x] = PAL_RGB332.get(ch, 0xE3)
                    bank[s_id] = buf
        return bank

    def create_default_tiles(self):
        bank = [bytearray([0x1C]*256) for _ in range(64)] # Standaard groen gras
        hex_p = _find_asset_file("default_tileset.hex")
        if os.path.exists(hex_p):
            try:
                with open(hex_p, "r") as f:
                    vals = [int(ln.strip(), 16) for ln in f if ln.strip()]
                for t_id in range(min(64, len(vals) // 256)):
                    bank[t_id] = bytearray(vals[t_id*256 : (t_id+1)*256])
                return bank
            except Exception:
                pass

        bin_p = _find_asset_file("tiles.bin")
        if os.path.exists(bin_p):
            try:
                with open(bin_p, "rb") as f:
                    data = f.read()
                num = min(64, len(data) // 256)
                for t_id in range(num):
                    bank[t_id] = bytearray(data[t_id*256 : (t_id+1)*256])
                return bank
            except Exception:
                pass
                
        if FARM_TILES:
            for t_id, pat in FARM_TILES.items():
                if 0 <= t_id < 64:
                    buf = bytearray(256)
                    for y in range(16):
                        row = pat[y] if y < len(pat) else " "*16
                        for x in range(16):
                            ch = row[x] if x < len(row) else 'G'
                            buf[y*16 + x] = PAL_RGB332.get(ch, 0x1C)
                    bank[t_id] = buf
        return bank

    def create_default_tilemap(self):
        hex_p = _find_asset_file("default_tilemap.hex")
        if os.path.exists(hex_p):
            try:
                with open(hex_p, "r") as f:
                    vals = [int(ln.strip(), 16) for ln in f if ln.strip()]
                if len(vals) >= 4096:
                    return [vals[r*64 : (r+1)*64] for r in range(64)]
            except Exception:
                pass
        try:
            from boerderij_game import build_farm_world
            return build_farm_world()
        except Exception:
            return [[0 for _ in range(64)] for _ in range(64)]

    def create_default_big_sprites(self):
        bank = [bytearray([0xE3] * (128 * 128)) for _ in range(2)]
        for slot in range(2):
            hex_path = _find_asset_file(f"default_bigspr{slot}.hex")
            if os.path.exists(hex_path):
                try:
                    with open(hex_path, "r") as f:
                        vals = [int(ln.strip(), 16) for ln in f if ln.strip()]
                    if len(vals) >= 128 * 128:
                        bank[slot] = bytearray(vals[:128 * 128])
                        continue
                except Exception:
                    pass
            bin_path = _find_asset_file(f"big_sprite_{slot}.bin")
            if os.path.exists(bin_path):
                try:
                    with open(bin_path, "rb") as f:
                        data = f.read(128 * 128)
                        if len(data) == 128 * 128:
                            bank[slot] = bytearray(data)
                except Exception:
                    pass
        return bank

    def load_font8x8(self):
        """Laadt het 8x8 FPGA bitmap font uit src/font8x8.hex (128 karakters x 8 rijen)."""
        font_data = [[0]*8 for _ in range(128)]
        path = _find_asset_file("font8x8.hex")
        candidates = [
            path,
            os.path.join(_THIS_DIR, "src", "font8x8.hex"),
            os.path.join(_THIS_DIR, "font8x8.hex"),
            os.path.join(os.path.dirname(_THIS_DIR), "src", "font8x8.hex"),
        ]
        for p in candidates:
            if os.path.exists(p):
                try:
                    with open(p, "r") as f:
                        vals = [int(line.strip(), 16) for line in f if line.strip()]
                    for ch in range(min(128, len(vals) // 8)):
                        font_data[ch] = vals[ch*8 : (ch+1)*8]
                    return font_data
                except Exception:
                    pass
        return font_data

    # -------------------------------------------------------------------------
    # GEBRUIKERSINTERFACE
    # -------------------------------------------------------------------------
    def setup_ui(self):
        # 1. COM Poort & BASIC Export statusbalk
        top_frame = tk.Frame(self.root, bg="#f0f0f0")
        top_frame.pack(fill=tk.X, padx=5, pady=5)
        
        tk.Label(top_frame, text="COM Poort (115200):", font=("Arial", 9, "bold"), bg="#f0f0f0").pack(side=tk.LEFT)
        self.port_var = tk.StringVar()
        self.port_combo = ttk.Combobox(top_frame, textvariable=self.port_var, state="readonly", width=10)
        self.port_combo.pack(side=tk.LEFT, padx=4)
        
        tk.Button(top_frame, text="🔄 Refresh", command=self.refresh_ports).pack(side=tk.LEFT)
        self.connect_btn = tk.Button(top_frame, text="⚡ Verbinden", bg="#e8ffe8", font=("Arial", 9, "bold"), command=self.toggle_connection)
        self.connect_btn.pack(side=tk.LEFT, padx=5)

        # Nieuwe MiniGPU-BASIC knoppen!
        tk.Button(top_frame, text="📝 BASIC Code (.BAS)", bg="#dbeafe", font=("Arial", 9, "bold"), command=self.open_basic_code_dialog).pack(side=tk.LEFT, padx=4)
        tk.Button(top_frame, text="💾 Stuur als BASIC naar SD-Kaart!", bg="#fef08a", font=("Arial", 9, "bold"), command=self.upload_drawing_to_sdcard).pack(side=tk.LEFT, padx=4)

        tk.Button(top_frame, text="🧹 Reset FPGA / Wis", bg="#ffcccc", font=("Arial", 9, "bold"), command=self.hard_reset_fpga).pack(side=tk.RIGHT, padx=5)
        
        # 2. Gereedschappen Werkbalk
        toolbar = tk.Frame(self.root, bg="#e8e8e8", relief=tk.RAISED, bd=1)
        toolbar.pack(fill=tk.X, padx=5, pady=2)
        
        tools = [
            ("✏️ Lijn", "line"),
            ("⬛ Rechthoek", "rect"),
            ("⚪ Cirkel", "circle"),
            ("🔺 Driehoek", "triangle"),
            ("🔤 Tekst", "text"),
            ("👾 Sprite Stempel", "sprite")
        ]
        
        for text, mode in tools:
            btn = tk.Button(toolbar, text=text, command=lambda m=mode: self.set_tool(m))
            btn.pack(side=tk.LEFT, padx=2, pady=2)
            
        self.fill_var = tk.BooleanVar(value=False)
        tk.Checkbutton(toolbar, text="Gevuld (Fill)", variable=self.fill_var, bg="#e8e8e8").pack(side=tk.LEFT, padx=6)
        
        self.color_btn = tk.Button(toolbar, text="Kleur", bg=self.get_tk_color(), width=5, command=self.choose_color)
        self.color_btn.pack(side=tk.LEFT, padx=4)

        # Quick Swatches
        quick_colors = [
            ("Zwart", 0x00, "#000000"), ("Wit", 0xFF, "#ffffff"),
            ("Rood", 0xE0, "#ff0000"), ("Groen", 0x1C, "#00ff00"),
            ("Blauw", 0x03, "#0000ff"), ("Geel", 0xFC, "#ffff00"),
            ("Bruin", 0x68, "#884400"), ("L.Blauw", 0x5F, "#55ffff"),
            ("Trans", 0xE3, "#475569")
        ]
        for name, col_code, hex_c in quick_colors:
            btn = tk.Button(toolbar, text="T" if name == "Trans" else "", bg=hex_c, fg="white" if name == "Trans" else "black", width=2, command=lambda c=col_code, h=hex_c: self.set_quick_color(c, h))
            btn.pack(side=tk.LEFT, padx=1)

        tk.Button(toolbar, text="🪣 CLS Scherm (Kleur)", bg="#fed7aa", font=("Arial", 9, "bold"), command=self.cls_selected_color).pack(side=tk.LEFT, padx=6)

        # 2b. Tekst Grootte Werkbalk (Vergroten & Verkleinen van ons 8x8 FPGA Font)
        text_bar = tk.Frame(self.root, bg="#fef9c3", relief=tk.RAISED, bd=1)
        text_bar.pack(fill=tk.X, padx=5, pady=2)

        tk.Label(text_bar, text="🔤 FPGA Font Grootte:", font=("Arial", 9, "bold"), bg="#fef9c3").pack(side=tk.LEFT, padx=(6, 4))
        tk.Button(text_bar, text="🔎- Verkleinen", bg="#fee2e2", font=("Arial", 9, "bold"), padx=8, command=self.decrease_font_size).pack(side=tk.LEFT, padx=2, pady=2)

        self.font_size_lbl = tk.Label(text_bar, text="2x (16x16 px)", font=("Courier", 10, "bold"), bg="#ffffff", fg="#1e293b", width=14, relief=tk.SUNKEN, bd=1)
        self.font_size_lbl.pack(side=tk.LEFT, padx=4, pady=2)

        tk.Button(text_bar, text="🔎+ Vergroten", bg="#dcfce7", font=("Arial", 9, "bold"), padx=8, command=self.increase_font_size).pack(side=tk.LEFT, padx=2, pady=2)

        # Snelkeuze knoppen (1x t/m 8x)
        tk.Label(text_bar, text="Snelkeuze:", font=("Arial", 9), bg="#fef9c3").pack(side=tk.LEFT, padx=(10, 2))
        for s in [1, 2, 3, 4, 5, 6, 8]:
            tk.Button(text_bar, text=f"{s}x", font=("Arial", 8, "bold"), width=3, bg="#f1f5f9",
                      command=lambda sc=s: self.set_font_scale(sc)).pack(side=tk.LEFT, padx=1)

        # 3. Studio Knoppen (Rij 1: Sprite, Tegel & Kaart Editors)
        studio_bar1 = tk.Frame(self.root, bg="#ddeeff", relief=tk.RAISED, bd=1)
        studio_bar1.pack(fill=tk.X, padx=5, pady=2)

        tk.Button(studio_bar1, text="🎨 Sprite Editor (32 Sprites)", bg="#cce5ff", font=("Arial", 9, "bold"), command=self.open_sprite_editor).pack(side=tk.LEFT, padx=5, pady=3)
        tk.Label(studio_bar1, text="Actieve Sprite ID:", bg="#ddeeff").pack(side=tk.LEFT, padx=2)
        self.sprite_id_var = tk.IntVar(value=0)
        self.sprite_spin = tk.Spinbox(studio_bar1, from_=0, to=31, textvariable=self.sprite_id_var, width=4)
        self.sprite_spin.pack(side=tk.LEFT, padx=2)

        tk.Button(studio_bar1, text="🧱 Tegel Editor (64 Tegels)", bg="#d4edda", font=("Arial", 9, "bold"), command=self.open_tile_editor).pack(side=tk.LEFT, padx=8, pady=3)
        tk.Button(studio_bar1, text="🗺️ Wereldkaart Placer (64x64 Map)", bg="#fff3cd", font=("Arial", 9, "bold"), command=self.open_tilemap_editor).pack(side=tk.LEFT, padx=4, pady=3)

        tk.Button(studio_bar1, text="Flip Buffer", command=self.flip_buffer).pack(side=tk.RIGHT, padx=5)
        self.live_mode_var = tk.BooleanVar(value=True)
        tk.Checkbutton(studio_bar1, text="Live Mode", variable=self.live_mode_var, command=self.toggle_live_mode, bg="#ddeeff").pack(side=tk.RIGHT, padx=5)

        # 4. Wereld & Hardware Studio (Rij 2: Big Sprites, Wereld Tools & Web Studio)
        studio_bar2 = tk.Frame(self.root, bg="#e2e8f0", relief=tk.RAISED, bd=1)
        studio_bar2.pack(fill=tk.X, padx=5, pady=2)

        tk.Button(studio_bar2, text="🌍 Vul Wereld met Tegel", bg="#dcfce7", font=("Arial", 9, "bold"), command=self.fill_tilemap_with_selected_tile).pack(side=tk.LEFT, padx=4, pady=3)
        tk.Button(studio_bar2, text="👁️ Toon Tegels Wereld", bg="#e0e7ff", font=("Arial", 9, "bold"), command=self.show_tilemap_world).pack(side=tk.LEFT, padx=4, pady=3)
        tk.Button(studio_bar2, text="🌌 Thema Achtergrond", bg="#c7d2fe", font=("Arial", 9, "bold"), command=self.open_bg_theme_picker).pack(side=tk.LEFT, padx=4, pady=3)
        
        # Zeer opvallende knop voor de 128x128 Big Sprites
        tk.Button(studio_bar2, text="👾 Big Sprites (128x128 Hardware)", bg="#ec4899", fg="white", font=("Arial", 9, "bold"), padx=8, pady=2, command=self.open_big_sprite_manager).pack(side=tk.LEFT, padx=6, pady=3)
        
        tk.Button(studio_bar2, text="🌐 Web Studio", bg="#e9d5ff", font=("Arial", 9, "bold"), command=self.open_web_studio).pack(side=tk.LEFT, padx=4, pady=3)
        tk.Button(studio_bar2, text="📰 Web Kiosk", bg="#bae6fd", font=("Arial", 9, "bold"), command=self.open_web_kiosk).pack(side=tk.LEFT, padx=4, pady=3)

        # 4. Teken Canvas (640x360 SDRAM formaat)
        self.canvas = tk.Canvas(self.root, width=640, height=360, bg="black", cursor="cross")
        self.canvas.pack(padx=10, pady=6)
        
        self.canvas.bind("<Button-1>", self.on_click)
        self.canvas.bind("<B1-Motion>", self.on_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_release)
        self.canvas.bind("<MouseWheel>", self.on_canvas_mousewheel)
        
        self.status_var = tk.StringVar(value="MiniGPU-BASIC Paint & Studio gereed (115200 baud). Alles wat je tekent wordt ook als BASIC-programma bijgehouden!")
        tk.Label(self.root, textvariable=self.status_var, bd=1, relief=tk.SUNKEN, anchor=tk.W).pack(side=tk.BOTTOM, fill=tk.X)

    def set_quick_color(self, col_code, hex_color):
        self.color_rgb332 = col_code
        self.color_btn.config(bg=hex_color)

    def refresh_ports(self):
        ports = serial.tools.list_ports.comports()
        val_list = [p.device for p in ports]
        self.port_combo['values'] = val_list
        if "COM6" in val_list:
            self.port_combo.set("COM6")
        elif "COM21" in val_list:
            self.port_combo.set("COM21")
        elif val_list:
            self.port_combo.current(len(val_list)-1)
            
    def toggle_connection(self):
        if self.ser is None:
            port = self.port_var.get()
            if not port:
                messagebox.showerror("Fout", "Selecteer een COM poort")
                return
            try:
                self.ser = serial.Serial(port, 115200, timeout=1)
                self._switch_to_gpu_mode()
                self.toggle_live_mode()
                self.connect_btn.config(text="❌ Verbreek", bg="#ffcccc")
                self.status_var.set(f"Status: Verbonden met {port} (115200 baud) in MiniGPU-BASIC GPU-modus!")
            except Exception as e:
                messagebox.showerror("Connectie Fout", str(e))
        else:
            try:
                self._switch_to_basic_mode()
                self.ser.close()
            except Exception:
                pass
            self.ser = None
            self.connect_btn.config(text="⚡ Verbinden", bg="#e8ffe8")
            self.status_var.set("Status: Niet verbonden (teruggeschakeld naar MiniGPU-BASIC)")

    def get_basic_program_lines(self):
        """Genereer genummerde MiniGPU-BASIC programmaregels van de huidige tekening."""
        lines = []
        line_num = 10
        for cmd in self.basic_commands:
            lines.append(f"{line_num} {cmd}")
            line_num += 10
        for slot in (0, 1):
            if self.big_spr_en[slot]:
                en = 1
                bx = int(self.big_spr_x[slot])
                by = int(self.big_spr_y[slot])
                fl = 1 if self.big_spr_flip[slot] else 0
                lines.append(f"{line_num} BIGSPR {slot},{en},{bx},{by},{fl}")
                line_num += 10
        lines.append(f"{line_num} IF KEY=0 THEN {line_num}")
        lines.append(f"{line_num + 10} MODE 0")
        return lines

    def open_basic_code_dialog(self):
        """Toont de gegenereerde MiniGPU-BASIC code van de huidige tekening om te kopiëren of op te slaan als .BAS."""
        dlg = tk.Toplevel(self.root)
        dlg.title("📝 Gegenereerde MiniGPU-BASIC Code van jouw Tekening")
        dlg.geometry("620x480")
        dlg.transient(self.root)

        top_info = tk.Label(
            dlg,
            text="Elke vorm, tekst en sprite die je tekent wordt automatisch vertaald naar MiniGPU-BASIC!",
            font=("Arial", 9, "bold"), bg="#dbeafe", pady=6
        )
        top_info.pack(fill=tk.X)

        txt_box = tk.Text(dlg, font=("Consolas", 10), bg="#0f172a", fg="#4ade80", insertbackground="white")
        txt_box.pack(fill=tk.BOTH, expand=True, padx=10, pady=8)
        prog_text = "\n".join(self.get_basic_program_lines())
        txt_box.insert("1.0", prog_text)

        btn_row = tk.Frame(dlg, pady=6)
        btn_row.pack(fill=tk.X, padx=10)

        def save_bas_file():
            filename = filedialog.asksaveasfilename(
                parent=dlg,
                title="Sla tekening op als MiniGPU-BASIC programma (.bas)",
                initialdir=self.get_default_sd_path(),
                initialfile="PAINT.bas",
                defaultextension=".bas",
                filetypes=[("MiniGPU-BASIC Programma (*.bas)", "*.bas"), ("Alle bestanden", "*.*")]
            )
            if not filename:
                return
            with open(filename, "w", encoding="utf-8") as f:
                f.write(txt_box.get("1.0", tk.END).strip() + "\n")
            messagebox.showinfo("Opgeslagen", f"BASIC-programma opgeslagen als:\n{filename}", parent=dlg)

        tk.Button(btn_row, text="💾 Opslaan als .BAS Bestand...", bg="#22c55e", fg="white", font=("Arial", 9, "bold"), padx=10, command=save_bas_file).pack(side=tk.LEFT, padx=4)
        tk.Button(btn_row, text="🚀 Direct naar FPGA SD-Kaart sturen!", bg="#f59e0b", fg="white", font=("Arial", 9, "bold"), padx=10, command=lambda: [dlg.destroy(), self.upload_drawing_to_sdcard()]).pack(side=tk.LEFT, padx=4)
        tk.Button(btn_row, text="Sluiten", command=dlg.destroy).pack(side=tk.RIGHT, padx=4)

    def upload_drawing_to_sdcard(self):
        """Stuurt de huidige tekening als een uitvoerbaar MiniGPU-BASIC programma naar de SD-kaart op de FPGA."""
        if not self.ser:
            messagebox.showerror("Niet Verbonden", "Verbind eerst met de COM-poort (bijv. COM6) van de Tang Nano 20K!")
            return
        prog_name = simpledialog.askstring(
            "Opslaan op FPGA SD-Kaart",
            "Geef een naam voor je tekening op de SD-kaart (max 12 letters, bijv. PAINT):",
            initialvalue="PAINT",
            parent=self.root
        )
        if not prog_name:
            return
        import re
        sd_name = re.sub(r"[^A-Z0-9_]", "", prog_name.upper())[:12] or "PAINT"
        lines = self.get_basic_program_lines()
        try:
            import sd_tools
            self.status_var.set(f"Bezig met opslaan van '{sd_name}' ({len(lines)} BASIC-regels) naar SD-kaart...")
            self.root.update_idletasks()
            # 1. Schakel tijdelijk naar BASIC-modus
            self._switch_to_basic_mode()
            sd_tools._send_line_reliable(self.ser, "NEW", line_wait=0.25)
            for idx, ln in enumerate(lines, 1):
                self.status_var.set(f"Verzenden BASIC regel {idx}/{len(lines)}: {ln}...")
                self.root.update_idletasks()
                sd_tools._send_line_reliable(self.ser, ln, char_delay=0.0004, line_wait=0.25)
            out = sd_tools._send_line_reliable(self.ser, f'SAVE "{sd_name}"', line_wait=2.0)
            # Sla ook een kopie op in de lokale sdcard/ map
            sd_dir = os.path.join(_THIS_DIR, "sdcard")
            if os.path.isdir(sd_dir):
                with open(os.path.join(sd_dir, f"{sd_name}.bas"), "w", encoding="utf-8") as f:
                    f.write("\n".join(lines) + "\n")
            # 2. Schakel terug naar GPU-modus
            self._switch_to_gpu_mode()
            self.toggle_live_mode()
            self.status_var.set(f"✅ Tekening opgeslagen op SD-kaart als '{sd_name}'! (Startbaar in BASIC of Midnight Commander MC)")
            messagebox.showinfo(
                "Opgeslagen op SD-Kaart!",
                f"Jouw tekening ({len(lines)} BASIC-regels) staat nu op de SD-kaart als '{sd_name}'!\n\n"
                f"Je kunt hem op elk moment starten vanuit Midnight Commander (BRUN MC)\n"
                f"of in BASIC met: LOAD \"{sd_name}\" en RUN!"
            )
        except Exception as e:
            self._switch_to_gpu_mode()
            messagebox.showerror("Fout bij SD-Kaart Opslag", str(e))

    def render_tilemap_on_canvas(self, scroll_x=0, scroll_y=0):
        """Rendert het 640x360 zichtbare deel van de 64x64 tegelwereld direct op het Tkinter canvas."""
        img = Image.new("RGB", (640, 360))
        pixels = img.load()
        for y in range(360):
            wy = (y + scroll_y) & 1023
            ty = wy >> 4
            py = wy & 15
            row_map = self.tilemap[ty]
            row_offset = py * 16
            for x in range(640):
                wx = (x + scroll_x) & 1023
                tx = wx >> 4
                px = wx & 15
                tid = row_map[tx] & 0x3F
                c = self.tile_bank[tid][row_offset + px]
                r = ((c >> 5) & 7) * 255 // 7
                g = ((c >> 2) & 7) * 255 // 7
                b = (c & 3) * 255 // 3
                pixels[x, y] = (r, g, b)
        self._bg_tk_img = ImageTk.PhotoImage(img)
        self.canvas.delete("bg_tilemap")
        img_id = self.canvas.create_image(0, 0, anchor=tk.NW, image=self._bg_tk_img, tags="bg_tilemap")
        self.canvas.tag_lower(img_id)

    def open_bg_theme_picker(self):
        """Kies een van de 5 ingebouwde 1024x1024 thema-achtergronden uit bg_loader.py of een eigen foto."""
        dlg = tk.Toplevel(self.root)
        dlg.title("🌌 Kies 1024x1024 Hardware Achtergrond Thema")
        dlg.geometry("460x380")
        dlg.transient(self.root)
        tk.Label(dlg, text="Kies een achtergrond voor het Canvas & FPGA HDMI:", font=("Arial", 10, "bold"), pady=8).pack()

        themes = [
            ("🌌 1. Space / Sterrennevel & Planeten", "1", "#dbeafe"),
            ("🌃 2. Cyberpunk Neon Stad & Synthwave", "2", "#fce7f3"),
            ("🏰 3. Kasteel / Dungeon & Fakkels", "3", "#fef3c7"),
            ("🏝️ 4. Tropisch Eiland & Koraalzee", "4", "#d1fae5"),
            ("🚜 5. Boerderij Wereld (Origineel)", "5", "#dcfce7"),
        ]

        def upload_and_display_tiles(tiles, tmap, title_name):
            # 1. Kopieer de 64 tegels en 64x64 wereldkaart naar geheugen
            for tid in range(64):
                self.tile_bank[tid] = bytearray(tiles[tid])
            if isinstance(tmap, (bytes, bytearray)):
                for r in range(64):
                    self.tilemap[r] = list(tmap[r * 64 : (r + 1) * 64])
            else:
                for r in range(64):
                    self.tilemap[r] = list(tmap[r])

            # 2. Teken de nieuwe achtergrond direct op het Tkinter Canvas!
            self.canvas.delete("all")
            self.render_tilemap_on_canvas(0, 0)
            self.basic_commands = ["MODE 1", "CLEAR $E3"]

            # 3. Als we nog niet verbonden zijn, probeer automatisch te verbinden met de gekozen COM-poort
            if not self.ser:
                try:
                    self.toggle_connection()
                except Exception:
                    pass

            # 4. Upload naar de FPGA indien verbonden
            if self.ser:
                self.status_var.set(f"Uploaden van achtergrond '{title_name}' (64 tegels + 64x64 kaart) naar FPGA...")
                self.root.update_idletasks()
                # Zorg dat we zeker in GPU-modus zitten
                self.ser.write(b'\x1BGPU')
                time.sleep(0.03)
                # Maak SDRAM voor- en achterbuffer transparant (0xE3) zodat de tegelwereld zichtbaar is
                self.ser.write(bytes([0x0C, 0, 0x01, 0xE3]))
                time.sleep(0.04)
                self.ser.write(bytes([0x0C, 1, 0x01, 0xE3]))
                time.sleep(0.04)
                # Reset scroll naar (0, 0)
                self.ser.write(bytes([0x0F, 0, 0, 0, 0]))
                time.sleep(0.01)
                # Upload 64 tiles (256 bytes per tile)
                for tid in range(64):
                    self.ser.write(bytes([0x0D, tid & 0x3F]) + bytes(self.tile_bank[tid]))
                    if tid % 8 == 7:
                        self.status_var.set(f"Thema '{title_name}' uploaden: tegels {tid+1}/64...")
                        self.root.update_idletasks()
                self.ser.flush()
                # Upload 64 tilemap rijen (64 bytes per rij)
                for r in range(64):
                    self.ser.write(bytes([0x0E, r & 0x3F]) + bytes(self.tilemap[r]))
                self.ser.flush()
                time.sleep(0.03)
                self.toggle_live_mode()
                self.status_var.set(f"✅ Achtergrond '{title_name}' geladen op Canvas én live op FPGA HDMI!")
            else:
                self.status_var.set(f"✅ Achtergrond '{title_name}' getoond op Canvas! (Verbind met COM6 voor HDMI)")

        def apply_theme(t_key):
            try:
                import bg_loader
                desc, fn = bg_loader.THEMES[t_key]
                tiles, tmap = fn()
                dlg.destroy()
                upload_and_display_tiles(tiles, tmap, desc.split("(")[0].strip())
            except Exception as e:
                messagebox.showerror("Fout bij laden achtergrond", str(e), parent=dlg)

        def apply_custom_image():
            filename = filedialog.askopenfilename(
                parent=dlg,
                title="Kies een foto/afbeelding voor de achtergrond",
                filetypes=[("Afbeeldingen", "*.png *.jpg *.jpeg *.bmp *.webp"), ("Alle bestanden", "*.*")]
            )
            if not filename:
                return
            try:
                import bg_loader
                tiles, tmap = bg_loader.make_image_tiles_theme(filename)
                dlg.destroy()
                upload_and_display_tiles(tiles, tmap, os.path.basename(filename))
            except Exception as e:
                messagebox.showerror("Fout bij inladen afbeelding", str(e), parent=dlg)

        for label, key, col in themes:
            tk.Button(dlg, text=label, bg=col, font=("Arial", 9, "bold"), pady=5, command=lambda k=key: apply_theme(k)).pack(fill=tk.X, padx=20, pady=3)

        tk.Button(dlg, text="🖼️ 6. Eigen Foto / Afbeelding (.png/.jpg) kiezen...", bg="#e0e7ff", font=("Arial", 9, "bold"), pady=6, command=apply_custom_image).pack(fill=tk.X, padx=20, pady=6)

    def hard_reset_fpga(self):
        if not self.ser:
            messagebox.showerror("Fout", "Niet verbonden met GPU!")
            return
        try:
            self.status_var.set("FPGA Hard Reset uitvoeren...")
            self.canvas.delete("all")
            self.basic_commands = ["MODE 1", "CLEAR $00"]
            # 1. GPU modus afdwingen
            self.ser.write(b'\x1BGPU')
            time.sleep(0.02)
            # 2. Geluid dempen (4 kanalen)
            for ch in range(4):
                self.ser.write(bytes([0x10, ch, 0, 0, 0, 0]))
            # 3. Hardware entiteiten legen (8 slots)
            for slot in range(8):
                self.ser.write(bytes([0x13, slot]))
            # 4. Big Sprites (128x128) uitschakelen (slot 0 en slot 1)
            self.ser.write(struct.pack('<BBBh h B', 0x15, 0, 0, 0, 0, 0))
            self.ser.write(struct.pack('<BBBh h B', 0x15, 1, 0, 0, 0, 0))
            self.big_spr_en = [False, False]
            # 5. Scroll reset naar (0, 0)
            self.ser.write(bytes([0x0F, 0, 0, 0, 0]))
            # 5. Wis tegelkaart 64x64 naar 0
            blank_row = bytearray(64)
            for r in range(64):
                self.ser.write(bytes([0x0E, r]))
                self.ser.write(blank_row)
                time.sleep(0.003)
            # 6. Wis SDRAM voor- en achterbuffer
            self.ser.write(bytes([0x0C, 1]))
            time.sleep(0.01)
            self.ser.write(struct.pack('<BB', 0x01, 0x00))
            time.sleep(0.04)
            self.ser.write(bytes([0x0B]))
            time.sleep(0.01)
            self.ser.write(struct.pack('<BB', 0x01, 0x00))
            time.sleep(0.04)
            self.status_var.set("✅ FPGA hardware volledig schoongemaakt en gereset!")
            messagebox.showinfo("Gereset", "FPGA hardware is 100% schoongemaakt en gereset!")
        except Exception as e:
            messagebox.showerror("Fout", f"Kon FPGA niet resetten: {e}")

    def cls_selected_color(self):
        """Vult het SDRAM framebuffer scherm met de geselecteerde kleur (Opcode 0x01)."""
        col_code = self.color_rgb332
        tk_col = self.get_tk_color()
        self.canvas.delete("all")
        self.canvas.config(bg=tk_col)
        self.points = []
        self.basic_commands = ["MODE 1", f"CLEAR ${col_code:02X}"]
        if self.ser:
            try:
                # Opcode 0x01: CLEAR_SCREEN met geselecteerde kleur
                self.ser.write(struct.pack('<BB', 0x01, col_code))
                time.sleep(0.04)
                if not self.live_mode_var.get():
                    self.ser.write(b'\x0B') # Flip buffer zodat het direct zichtbaar is
                    time.sleep(0.01)
                    self.ser.write(struct.pack('<BB', 0x01, col_code))
                    time.sleep(0.04)
                self.status_var.set(f"✅ Scherm (CLS) gevuld met kleur 0x{col_code:02X} ({tk_col})!")
            except Exception as e:
                messagebox.showerror("Fout", f"Kon scherm niet vullen: {e}")
        else:
            self.status_var.set(f"Scherm lokaal gewist naar kleur {tk_col}. (Niet verbonden met FPGA)")

    def fill_tilemap_with_selected_tile(self, tile_id=None):
        """Vult de volledige 64x64 tegelwereld kaart met een gekozen tegel."""
        if tile_id is None:
            tile_str = simpledialog.askstring(
                "Tegel Wereld Vullen",
                "Voer Tegel ID in (0 t/m 63) om de hele 64x64 wereld mee te vullen:\n(Bijv: 0=Weidegras, 1=Bos, 2=Zandpad, 4=Water)",
                initialvalue="0",
                parent=self.root
            )
            if tile_str is None:
                return
            try:
                tile_id = int(tile_str)
                if not (0 <= tile_id <= 63):
                    raise ValueError()
            except ValueError:
                messagebox.showerror("Ongeldig ID", "Voer een getal tussen 0 en 63 in!")
                return

        name = TILE_NAMES.get(tile_id, f"Tegel {tile_id}")
        for r in range(64):
            self.tilemap[r] = [tile_id] * 64

        if self.ser:
            try:
                self.status_var.set(f"Bezig met uploaden van 64x64 kaart gevuld met [{tile_id}] {name}...")
                self.root.update_idletasks()
                row_bytes = bytearray([tile_id] * 64)
                for r in range(64):
                    self.ser.write(bytes([0x0E, r & 0x3F]))
                    self.ser.write(row_bytes)
                    time.sleep(0.003)
                # Automatisch de voorgrond transparant maken (CLS 0xE3) zodat de tegelwereld direct zichtbaar is!
                self.ser.write(struct.pack('<BB', 0x01, 0xE3))
                time.sleep(0.04)
                if not self.live_mode_var.get():
                    self.ser.write(b'\x0B')
                    time.sleep(0.01)
                    self.ser.write(struct.pack('<BB', 0x01, 0xE3))
                    time.sleep(0.04)
                self.canvas.delete("all")
                self.render_tilemap_on_canvas(0, 0)
                self.status_var.set(f"✅ Wereldkaart (64x64) live op FPGA gevuld met [{tile_id}] {name} en direct zichtbaar!")
                messagebox.showinfo("Tegel Wereld Gevuld", f"De hele achtergrond tegelwereld is nu gevuld met [{tile_id}] {name} en direct getoond op het scherm!")
            except Exception as e:
                messagebox.showerror("Fout", f"Kon tegelkaart niet naar FPGA sturen: {e}")
        else:
            self.canvas.delete("all")
            self.render_tilemap_on_canvas(0, 0)
            self.status_var.set(f"Tegelwereld lokaal gevuld met [{tile_id}] {name}. (Niet verbonden met FPGA)")

    def show_tilemap_world(self):
        """Wist de voorgrond naar transparant (0xE3) zodat de achtergrond tegelwereld direct zichtbaar is."""
        self.set_quick_color(0xE3, "#475569")
        self.cls_selected_color()
        self.render_tilemap_on_canvas(0, 0)
        self.status_var.set("👁️ Voorgrond transparant (0xE3). Tegels wereld is nu op het Canvas én live zichtbaar op HDMI!")

    def flip_buffer(self):
        if self.ser:
            self.ser.write(b'\x0B')

    def open_web_studio(self):
        import subprocess
        web_server_script = os.path.join(os.path.dirname(__file__), "web_studio", "server.py")
        subprocess.Popen([sys.executable, web_server_script])
        self.status_var.set("🌐 Web Studio server gestart en geopend in browser!")

    def open_web_kiosk(self):
        import subprocess
        kiosk_script = os.path.join(os.path.dirname(__file__), "web_kiosk_browser.py")
        subprocess.Popen([sys.executable, kiosk_script])
        self.status_var.set("📰 Web Kiosk Simulator geopend!")

    def toggle_live_mode(self):
        if self.ser:
            val = 1 if self.live_mode_var.get() else 0
            self.ser.write(struct.pack('<BB', 0x0C, val))

    def set_tool(self, tool):
        self.current_tool = tool
        self.points = []
        self.status_var.set(f"Actief gereedschap: {tool}")

    def choose_color(self, parent=None):
        color = colorchooser.askcolor(parent=parent)[0]
        if color:
            r, g, b = [int(c) for c in color]
            r3 = (r >> 5) & 0x07
            g3 = (g >> 5) & 0x07
            b2 = (b >> 6) & 0x03
            self.color_rgb332 = (r3 << 5) | (g3 << 2) | b2
            hex_color = f"#{r:02x}{g:02x}{b:02x}"
            self.color_btn.config(bg=hex_color)

    # -------------------------------------------------------------------------
    # 🎨 SPRITE EDITOR (32 SPRITES, 0 t/m 31)
    # -------------------------------------------------------------------------
    def open_sprite_editor(self):
        editor = tk.Toplevel(self.root)
        editor.title("MiniGPU Sprite Editor (32 Sprites | 16x16 Pixels | 8-Bit Kleur)")
        editor.geometry("960x760")
        editor.minsize(920, 700)
        editor.transient(self.root)

        curr_id = [self.sprite_id_var.get() & 0x1F]
        grid_colors = [[self.sprite_bank[curr_id[0]][y*16 + x] for x in range(16)] for y in range(16)]
        
        active_tool = ["pen"]
        
        # 1. TOP BALK 1: NAVIGATIE & HARDWARE FPGA UPLOAD
        top_bar1 = tk.Frame(editor, bg="#2d3748", padx=8, pady=6)
        top_bar1.pack(fill=tk.X)
        
        tk.Label(top_bar1, text="Sprite ID:", font=("Arial", 10, "bold"), fg="white", bg="#2d3748").pack(side=tk.LEFT, padx=(0, 4))
        
        id_var = tk.IntVar(value=curr_id[0])
        
        def on_id_change():
            nid = id_var.get()
            if 0 <= nid < 32 and nid != curr_id[0]:
                save_grid_to_bank(curr_id[0])
                curr_id[0] = nid
                self.sprite_id_var.set(nid)
                id_badge.config(text=f"Sprite #{nid:02d}")
                load_bank_to_grid(nid)

        def prev_sprite():
            nid = (curr_id[0] - 1) % 32
            id_var.set(nid)
            on_id_change()

        def next_sprite():
            nid = (curr_id[0] + 1) % 32
            id_var.set(nid)
            on_id_change()

        tk.Button(top_bar1, text="◀", font=("Arial", 9, "bold"), width=3, bg="#4a5568", fg="white", command=prev_sprite).pack(side=tk.LEFT, padx=2)
        spin = tk.Spinbox(top_bar1, from_=0, to=31, textvariable=id_var, width=4, font=("Arial", 10, "bold"), command=on_id_change)
        spin.pack(side=tk.LEFT, padx=2)
        spin.bind("<Return>", lambda e: on_id_change())
        tk.Button(top_bar1, text="▶", font=("Arial", 9, "bold"), width=3, bg="#4a5568", fg="white", command=next_sprite).pack(side=tk.LEFT, padx=2)

        id_badge = tk.Label(top_bar1, text=f"Sprite #{curr_id[0]:02d}", font=("Arial", 10, "bold"), fg="#63b3ed", bg="#2d3748", width=12)
        id_badge.pack(side=tk.LEFT, padx=6)

        # FPGA Upload knoppen
        def upload_current():
            if not self.ser:
                messagebox.showerror("Niet Verbonden", "Verbind eerst met de COM-poort van de FPGA!")
                return
            save_grid_to_bank(curr_id[0])
            s_id = curr_id[0]
            self.ser.write(bytes([0x09, s_id & 0x1F]))
            self.ser.write(self.sprite_bank[s_id])
            status_lbl.config(text=f"✅ Sprite #{s_id} direct geüpload naar FPGA Sprite RAM!")
            self.status_var.set(f"Sprite #{s_id} geüpload naar FPGA!")

        def upload_all():
            if not self.ser:
                messagebox.showerror("Niet Verbonden", "Verbind eerst met de COM-poort van de FPGA!")
                return
            save_grid_to_bank(curr_id[0])
            for s_id in range(32):
                self.ser.write(bytes([0x09, s_id & 0x1F]))
                self.ser.write(self.sprite_bank[s_id])
                time.sleep(0.004)
            status_lbl.config(text="⚡ Alle 32 sprites succesvol naar FPGA geüpload!")
            self.status_var.set("Alle 32 sprites geüpload naar FPGA!")
            messagebox.showinfo("FPGA Upload Voltooid", "Alle 32 sprites (8 KB) zijn live geladen in het FPGA Sprite RAM!")

        tk.Button(top_bar1, text="🚀 Upload Huidige naar FPGA", bg="#28a745", fg="white", font=("Arial", 9, "bold"), padx=8, pady=2, command=upload_current).pack(side=tk.LEFT, padx=6)
        tk.Button(top_bar1, text="⚡ Upload Alle 32 naar FPGA", bg="#007bff", fg="white", font=("Arial", 9, "bold"), padx=8, pady=2, command=upload_all).pack(side=tk.LEFT, padx=6)

        conn_text = "🟢 FPGA Verbonden" if self.ser else "⚪ FPGA Niet Verbonden"
        conn_col = "#68d391" if self.ser else "#cbd5e0"
        tk.Label(top_bar1, text=conn_text, font=("Arial", 9), fg=conn_col, bg="#2d3748").pack(side=tk.RIGHT, padx=6)

        # 2. TOP BALK 2: BESTANDSBEHEER (BIN & PNG OPSLAAN & LADEN)
        top_bar2 = tk.Frame(editor, bg="#edf2f7", padx=8, pady=4, relief=tk.RIDGE, bd=1)
        top_bar2.pack(fill=tk.X)

        def save_current_bin():
            save_grid_to_bank(curr_id[0])
            filename = filedialog.asksaveasfilename(
                parent=editor, title=f"Sla Sprite #{curr_id[0]} op als .BIN (256 bytes)",
                initialfile=f"sprite_{curr_id[0]:02d}.bin", defaultextension=".bin",
                filetypes=[("Sprite Bin (256 bytes)", "*.bin"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            with open(filename, "wb") as f:
                f.write(self.sprite_bank[curr_id[0]])
            status_lbl.config(text=f"💾 Opgeslagen: {os.path.basename(filename)} (256 bytes)")
            messagebox.showinfo("Opgeslagen", f"Sprite #{curr_id[0]} opgeslagen als 256 bytes binair bestand:\n{filename}")

        def save_current_png():
            save_grid_to_bank(curr_id[0])
            filename = filedialog.asksaveasfilename(
                parent=editor, title=f"Sla Sprite #{curr_id[0]} op als PNG",
                initialfile=f"sprite_{curr_id[0]:02d}.png", defaultextension=".png",
                filetypes=[("PNG Afbeelding", "*.png"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            img = Image.new("RGBA", (16, 16))
            for y in range(16):
                for x in range(16):
                    c_val = grid_colors[y][x]
                    if c_val == 0xE3:
                        img.putpixel((x, y), (0, 0, 0, 0))
                    else:
                        r = ((c_val >> 5) & 7) * 255 // 7
                        g = ((c_val >> 2) & 7) * 255 // 7
                        b = (c_val & 3) * 255 // 3
                        img.putpixel((x, y), (r, g, b, 255))
            img.resize((128, 128), Image.Resampling.NEAREST).save(filename)
            status_lbl.config(text=f"🖼️ PNG Opgeslagen: {os.path.basename(filename)}")
            messagebox.showinfo("Opgeslagen", f"Sprite opgeslagen als PNG:\n{filename}")

        def save_all_bin():
            save_grid_to_bank(curr_id[0])
            filename = filedialog.asksaveasfilename(
                parent=editor, title="Sla Alle 32 Sprites op (8 KB BIN)",
                initialfile="sprites.bin", defaultextension=".bin",
                filetypes=[("Sprite Bank (32 sprites, 8KB)", "*.bin"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            with open(filename, "wb") as f:
                for s_id in range(32):
                    f.write(self.sprite_bank[s_id])
            status_lbl.config(text=f"💾 Alle 32 sprites opgeslagen: {os.path.basename(filename)} (8.192 bytes)")
            messagebox.showinfo("Opgeslagen", f"Alle 32 sprites succesvol opgeslagen in:\n{filename} (8.192 bytes)")

        def load_file():
            filename = filedialog.askopenfilename(
                parent=editor, title="Open Sprite (.BIN of .PNG / .JPG)",
                filetypes=[("Ondersteunde bestanden", "*.bin *.png *.jpg *.jpeg *.bmp"), ("BIN Bestanden", "*.bin"), ("Afbeeldingen", "*.png *.jpg *.bmp"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            if filename.lower().endswith((".png", ".jpg", ".jpeg", ".bmp")):
                try:
                    img = Image.open(filename).convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
                    for y in range(16):
                        for x in range(16):
                            r, g, b, a = img.getpixel((x, y))
                            if a < 128:
                                grid_colors[y][x] = 0xE3
                            else:
                                r3 = (r >> 5) & 7
                                g3 = (g >> 5) & 7
                                b2 = (b >> 6) & 3
                                grid_colors[y][x] = (r3 << 5) | (g3 << 2) | b2
                    save_grid_to_bank(curr_id[0])
                    load_bank_to_grid(curr_id[0])
                    status_lbl.config(text=f"📂 Afbeelding geïmporteerd in Sprite #{curr_id[0]}")
                    messagebox.showinfo("Geladen", f"Afbeelding geïmporteerd in Sprite #{curr_id[0]}!")
                except Exception as e:
                    messagebox.showerror("Fout", f"Kan afbeelding niet openen:\n{e}")
            else:
                try:
                    with open(filename, "rb") as f:
                        data = f.read()
                    if len(data) == 256:
                        self.sprite_bank[curr_id[0]] = bytearray(data)
                        load_bank_to_grid(curr_id[0])
                        status_lbl.config(text=f"📂 Sprite #{curr_id[0]} ingeladen (256 bytes)")
                        messagebox.showinfo("Geladen", f"Sprite #{curr_id[0]} ingeladen vanuit 256 bytes binair bestand!")
                    else:
                        num = min(32, len(data) // 256)
                        for s_id in range(num):
                            self.sprite_bank[s_id] = bytearray(data[s_id*256 : (s_id+1)*256])
                        load_bank_to_grid(curr_id[0])
                        status_lbl.config(text=f"📂 {num} sprites ingeladen uit {os.path.basename(filename)}")
                        messagebox.showinfo("Geladen", f"{num} sprites ingeladen uit bestand ({len(data)} bytes)!")
                except Exception as e:
                    messagebox.showerror("Fout", f"Fout bij inladen:\n{e}")

        tk.Button(top_bar2, text="💾 Sla Huidige BIN op (256B)", bg="#e2e8f0", command=save_current_bin).pack(side=tk.LEFT, padx=3)
        tk.Button(top_bar2, text="🖼️ Sla Huidige PNG op", bg="#e2e8f0", command=save_current_png).pack(side=tk.LEFT, padx=3)
        tk.Button(top_bar2, text="💾 Sla Alle 32 op (sprites.bin)", bg="#c6f6d5", font=("Arial", 9, "bold"), command=save_all_bin).pack(side=tk.LEFT, padx=5)
        tk.Button(top_bar2, text="📂 Laad Bestand (.bin / .png)", bg="#feebc8", font=("Arial", 9, "bold"), command=load_file).pack(side=tk.LEFT, padx=5)

        # 3. BALK 3: GEREEDSCHAPPEN & KLEUR SELECTIE
        tools_frame = tk.Frame(editor, bg="#f7fafc", padx=8, pady=5)
        tools_frame.pack(fill=tk.X)

        tk.Label(tools_frame, text="Kleur:", font=("Arial", 9, "bold"), bg="#f7fafc").pack(side=tk.LEFT, padx=(0, 4))
        color_swatch = tk.Canvas(tools_frame, width=28, height=24, bg=self.rgb332_to_hex(self.color_rgb332), relief=tk.SOLID, bd=1)
        color_swatch.pack(side=tk.LEFT, padx=2)

        def update_swatch():
            if self.color_rgb332 == 0xE3:
                color_swatch.config(bg="#f0f0f0")
                color_label.config(text="0xE3 (Transparant)")
            else:
                hex_c = self.rgb332_to_hex(self.color_rgb332)
                color_swatch.config(bg=hex_c)
                color_label.config(text=f"0x{self.color_rgb332:02X} ({hex_c})")
            self.color_btn.config(bg=self.get_tk_color())

        color_label = tk.Label(tools_frame, text=f"0x{self.color_rgb332:02X}", font=("Courier", 9, "bold"), bg="#f7fafc", width=16, anchor=tk.W)
        color_label.pack(side=tk.LEFT, padx=2)

        def choose_custom_color():
            color = colorchooser.askcolor(parent=editor, title="Kies een Kleur voor Sprite")[0]
            if color:
                r, g, b = [int(c) for c in color]
                r3 = (r >> 5) & 7
                g3 = (g >> 5) & 7
                b2 = (b >> 6) & 3
                self.color_rgb332 = (r3 << 5) | (g3 << 2) | b2
                set_tool("pen")
                update_swatch()

        tk.Button(tools_frame, text="🎨 Kies Kleur...", bg="#bee3f8", font=("Arial", 9, "bold"), command=choose_custom_color).pack(side=tk.LEFT, padx=4)

        def set_eraser():
            self.color_rgb332 = 0xE3
            set_tool("eraser")
            update_swatch()

        tk.Button(tools_frame, text="⬜ Gum (Transparant)", bg="#edf2f7", command=set_eraser).pack(side=tk.LEFT, padx=4)

        # Tool selectie
        tool_btns = {}
        def set_tool(t_name):
            active_tool[0] = t_name
            for k, btn in tool_btns.items():
                if k == t_name:
                    btn.config(relief=tk.SUNKEN, bg="#cbd5e0")
                else:
                    btn.config(relief=tk.RAISED, bg="#edf2f7")

        tool_btns["pen"] = tk.Button(tools_frame, text="✏️ Pen", command=lambda: set_tool("pen"))
        tool_btns["pen"].pack(side=tk.LEFT, padx=2)
        tool_btns["bucket"] = tk.Button(tools_frame, text="🪣 Vul Emmer", command=lambda: set_tool("bucket"))
        tool_btns["bucket"].pack(side=tk.LEFT, padx=2)
        tool_btns["picker"] = tk.Button(tools_frame, text="🔍 Pipet", command=lambda: set_tool("picker"))
        tool_btns["picker"].pack(side=tk.LEFT, padx=2)
        set_tool("pen")

        # Transformatie tools
        def flip_h():
            for y in range(16): grid_colors[y].reverse()
            save_grid_to_bank(curr_id[0]); load_bank_to_grid(curr_id[0])
        def flip_v():
            grid_colors.reverse()
            save_grid_to_bank(curr_id[0]); load_bank_to_grid(curr_id[0])
        def rotate_90():
            new_g = [[grid_colors[15-x][y] for x in range(16)] for y in range(16)]
            for y in range(16):
                for x in range(16): grid_colors[y][x] = new_g[y][x]
            save_grid_to_bank(curr_id[0]); load_bank_to_grid(curr_id[0])
        def clear_sprite():
            if messagebox.askyesno("Wissen", f"Weet je zeker dat je Sprite #{curr_id[0]} helemaal wilt wissen (transparant)?", parent=editor):
                for y in range(16):
                    for x in range(16): grid_colors[y][x] = 0xE3
                save_grid_to_bank(curr_id[0]); load_bank_to_grid(curr_id[0])

        tk.Button(tools_frame, text="↔️ Spiegel H", command=flip_h).pack(side=tk.LEFT, padx=3)
        tk.Button(tools_frame, text="↕️ Spiegel V", command=flip_v).pack(side=tk.LEFT, padx=3)
        tk.Button(tools_frame, text="🔄 Roteer 90°", command=rotate_90).pack(side=tk.LEFT, padx=3)
        tk.Button(tools_frame, text="🧹 Wis Alles", bg="#fed7d7", command=clear_sprite).pack(side=tk.LEFT, padx=3)

        # 4. BALK 4: SNELPALET (24 KLEUREN)
        palette_frame = tk.Frame(editor, bg="#e2e8f0", padx=8, pady=3)
        palette_frame.pack(fill=tk.X)
        tk.Label(palette_frame, text="Snelpalet:", font=("Arial", 9, "bold"), bg="#e2e8f0").pack(side=tk.LEFT, padx=(0, 4))

        def on_palette_click(c_code):
            self.color_rgb332 = c_code
            set_tool("pen")
            update_swatch()

        for col_code, hex_c, c_name in PALETTE_24:
            b = tk.Button(palette_frame, bg=hex_c, width=2, height=1, relief=tk.RAISED, bd=1,
                          command=lambda c=col_code: on_palette_click(c))
            b.pack(side=tk.LEFT, padx=1)

        # 5. MIDDEN: CANVAS & SPRITE GALERIJ
        content_frame = tk.Frame(editor, padx=10, pady=8)
        content_frame.pack(fill=tk.BOTH, expand=True)

        left_box = tk.Frame(content_frame)
        left_box.pack(side=tk.LEFT, fill=tk.BOTH, padx=(0, 10))

        canvas_size = 352
        cell_size = canvas_size // 16 # 22 pixels per cel

        c = tk.Canvas(left_box, width=canvas_size, height=canvas_size, bg="#4a5568", cursor="pencil")
        c.pack()

        rects = {}
        for y in range(16):
            for x in range(16):
                chk_bg = "#e2e8f0" if (x+y)%2 == 0 else "#cbd5e0"
                c.create_rectangle(x*cell_size, y*cell_size, (x+1)*cell_size, (y+1)*cell_size, fill=chk_bg, outline="")
                r = c.create_rectangle(x*cell_size, y*cell_size, (x+1)*cell_size, (y+1)*cell_size, fill="", outline="#718096", width=1)
                rects[(x, y)] = r

        coord_label = tk.Label(left_box, text="X: --, Y: -- | Kleur: --", font=("Courier", 9), anchor=tk.W)
        coord_label.pack(fill=tk.X, pady=(4, 0))

        help_label = tk.Label(left_box, text="Linkermuisknop = Tekenen / Actie | Rechts = Gum (Transparant) | Middenknop/Shift = Pipet", font=("Arial", 8), fg="#4a5568")
        help_label.pack(fill=tk.X)

        # Rechter paneel: Mini Gallery van alle 32 Sprites (4x8 grid)
        gallery_frame = tk.LabelFrame(content_frame, text="32 Sprites Galerij (Klik om direct te openen)", padx=6, pady=6)
        gallery_frame.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

        gallery_canvas = tk.Canvas(gallery_frame, width=200, height=360, bg="#1a202c")
        gallery_canvas.pack(fill=tk.BOTH, expand=True)

        def save_grid_to_bank(s_id):
            for y in range(16):
                for x in range(16):
                    self.sprite_bank[s_id][y*16 + x] = grid_colors[y][x]

        def load_bank_to_grid(s_id):
            for y in range(16):
                for x in range(16):
                    c_val = self.sprite_bank[s_id][y*16 + x]
                    grid_colors[y][x] = c_val
                    if c_val == 0xE3:
                        c.itemconfig(rects[(x, y)], fill="")
                    else:
                        c.itemconfig(rects[(x, y)], fill=self.rgb332_to_hex(c_val))
            draw_gallery()

        def draw_gallery():
            gallery_canvas.delete("all")
            for sid in range(32):
                col = sid % 4
                row = sid // 4
                gx = col * 46 + 6
                gy = row * 44 + 6
                is_cur = (sid == curr_id[0])
                outline_c = "#ecc94b" if is_cur else "#4a5568"
                bg_box = "#2d3748" if is_cur else "#171923"
                gallery_canvas.create_rectangle(gx, gy, gx+40, gy+38, fill=bg_box, outline=outline_c, width=2 if is_cur else 1)
                
                buf = self.sprite_bank[sid]
                for py in range(16):
                    for px in range(16):
                        c_val = buf[py*16 + px]
                        if c_val != 0xE3:
                            tk_c = self.rgb332_to_hex(c_val)
                            gallery_canvas.create_rectangle(gx+4+px*2, gy+3+py*2, gx+4+px*2+2, gy+3+py*2+2, fill=tk_c, outline="")
                gallery_canvas.create_text(gx+34, gy+32, text=f"{sid}", fill="#e2e8f0" if is_cur else "#a0aec0", font=("Arial", 7, "bold"))

        def on_gallery_click(event):
            col = (event.x - 6) // 46
            row = (event.y - 6) // 44
            if 0 <= col < 4 and 0 <= row < 8:
                sid = row * 4 + col
                if 0 <= sid < 32 and sid != curr_id[0]:
                    save_grid_to_bank(curr_id[0])
                    curr_id[0] = sid
                    self.sprite_id_var.set(sid)
                    id_var.set(sid)
                    id_badge.config(text=f"Sprite #{sid:02d}")
                    load_bank_to_grid(sid)

        gallery_canvas.bind("<Button-1>", on_gallery_click)

        # Canvas Acties (Tekenen, Vullen, Gummen, Pipet)
        def flood_fill(sx, sy, fill_col):
            if not (0 <= sx < 16 and 0 <= sy < 16): return
            target_col = grid_colors[sy][sx]
            if target_col == fill_col: return
            queue = [(sx, sy)]
            visited = set()
            while queue:
                x, y = queue.pop(0)
                if (x, y) in visited: continue
                visited.add((x, y))
                if 0 <= x < 16 and 0 <= y < 16 and grid_colors[y][x] == target_col:
                    grid_colors[y][x] = fill_col
                    if fill_col == 0xE3:
                        c.itemconfig(rects[(x, y)], fill="")
                    else:
                        c.itemconfig(rects[(x, y)], fill=self.rgb332_to_hex(fill_col))
                    queue.extend([(x+1, y), (x-1, y), (x, y+1), (x, y-1)])
            save_grid_to_bank(curr_id[0])
            draw_gallery()

        def on_canvas_click(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if not (0 <= x < 16 and 0 <= y < 16): return

            tool = active_tool[0]
            if tool == "picker":
                picked = grid_colors[y][x]
                self.color_rgb332 = picked
                set_tool("pen")
                update_swatch()
            elif tool == "bucket":
                flood_fill(x, y, self.color_rgb332)
            elif tool == "eraser":
                grid_colors[y][x] = 0xE3
                c.itemconfig(rects[(x, y)], fill="")
                save_grid_to_bank(curr_id[0])
                draw_gallery()
            else: # Pen
                grid_colors[y][x] = self.color_rgb332
                if self.color_rgb332 == 0xE3:
                    c.itemconfig(rects[(x, y)], fill="")
                else:
                    c.itemconfig(rects[(x, y)], fill=self.rgb332_to_hex(self.color_rgb332))
                save_grid_to_bank(curr_id[0])
                draw_gallery()

        def on_canvas_drag(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if not (0 <= x < 16 and 0 <= y < 16): return
            tool = active_tool[0]
            if tool in ("pen", "eraser"):
                col = 0xE3 if tool == "eraser" else self.color_rgb332
                grid_colors[y][x] = col
                if col == 0xE3:
                    c.itemconfig(rects[(x, y)], fill="")
                else:
                    c.itemconfig(rects[(x, y)], fill=self.rgb332_to_hex(col))
                save_grid_to_bank(curr_id[0])

        def on_canvas_release(event):
            draw_gallery()

        def on_canvas_right(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if 0 <= x < 16 and 0 <= y < 16:
                grid_colors[y][x] = 0xE3
                c.itemconfig(rects[(x, y)], fill="")
                save_grid_to_bank(curr_id[0])
                draw_gallery()

        def on_canvas_motion(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if 0 <= x < 16 and 0 <= y < 16:
                c_val = grid_colors[y][x]
                if c_val == 0xE3:
                    coord_label.config(text=f"X: {x:02d}, Y: {y:02d} | Transparant (0xE3)")
                else:
                    hex_c = self.rgb332_to_hex(c_val)
                    coord_label.config(text=f"X: {x:02d}, Y: {y:02d} | Kleur: 0x{c_val:02X} ({hex_c})")

        def on_shift_click(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if 0 <= x < 16 and 0 <= y < 16:
                flood_fill(x, y, self.color_rgb332)

        def on_middle_click(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if 0 <= x < 16 and 0 <= y < 16:
                self.color_rgb332 = grid_colors[y][x]
                set_tool("pen")
                update_swatch()

        c.bind("<Button-1>", on_canvas_click)
        c.bind("<B1-Motion>", on_canvas_drag)
        c.bind("<ButtonRelease-1>", on_canvas_release)
        c.bind("<Button-2>", on_middle_click)
        c.bind("<Button-3>", on_canvas_right)
        c.bind("<B3-Motion>", on_canvas_right)
        c.bind("<Shift-Button-1>", on_shift_click)
        c.bind("<Motion>", on_canvas_motion)

        # 6. STATUS BALK ONDERAAN
        status_lbl = tk.Label(editor, text="Sprite Editor gereed.", bd=1, relief=tk.SUNKEN, anchor=tk.W, bg="#edf2f7", font=("Arial", 9))
        status_lbl.pack(side=tk.BOTTOM, fill=tk.X)

        update_swatch()
        load_bank_to_grid(curr_id[0])

    # -------------------------------------------------------------------------
    # 🧱 TEGEL EDITOR (64 TEGELS, 0 t/m 63)
    # -------------------------------------------------------------------------
    def open_tile_editor(self):
        editor = tk.Toplevel(self.root)
        editor.title("MiniGPU Tegel Editor (64 BRAM Tiles | 16x16 Pixels)")
        editor.geometry("980x760")
        editor.minsize(940, 700)
        editor.transient(self.root)

        curr_t_id = [0]
        grid_colors = [[self.tile_bank[curr_t_id[0]][y*16 + x] for x in range(16)] for y in range(16)]
        
        active_tool = ["pen"]
        
        # 1. TOP BALK 1: NAVIGATIE & HARDWARE FPGA BRAM UPLOAD
        top_bar1 = tk.Frame(editor, bg="#276749", padx=8, pady=6)
        top_bar1.pack(fill=tk.X)
        
        tk.Label(top_bar1, text="Tegel ID:", font=("Arial", 10, "bold"), fg="white", bg="#276749").pack(side=tk.LEFT, padx=(0, 4))
        
        tile_spin_var = tk.IntVar(value=curr_t_id[0])
        
        def on_tile_change():
            nid = tile_spin_var.get()
            if 0 <= nid < 64 and nid != curr_t_id[0]:
                save_grid_to_bank(curr_t_id[0])
                curr_t_id[0] = nid
                name = TILE_NAMES.get(nid, f"Tegel #{nid}")
                tile_name_label.config(text=f"[{nid:02d}] {name}")
                load_bank_to_grid(nid)

        def prev_tile():
            nid = (curr_t_id[0] - 1) % 64
            tile_spin_var.set(nid)
            on_tile_change()

        def next_tile():
            nid = (curr_t_id[0] + 1) % 64
            tile_spin_var.set(nid)
            on_tile_change()

        tk.Button(top_bar1, text="◀", font=("Arial", 9, "bold"), width=3, bg="#2f855a", fg="white", command=prev_tile).pack(side=tk.LEFT, padx=2)
        spin = tk.Spinbox(top_bar1, from_=0, to=63, textvariable=tile_spin_var, width=4, font=("Arial", 10, "bold"), command=on_tile_change)
        spin.pack(side=tk.LEFT, padx=2)
        spin.bind("<Return>", lambda e: on_tile_change())
        tk.Button(top_bar1, text="▶", font=("Arial", 9, "bold"), width=3, bg="#2f855a", fg="white", command=next_tile).pack(side=tk.LEFT, padx=2)

        name = TILE_NAMES.get(0, "Tegel #0")
        tile_name_label = tk.Label(top_bar1, text=f"[00] {name}", font=("Arial", 10, "bold"), fg="#9ae6b4", bg="#276749", width=24, anchor=tk.W)
        tile_name_label.pack(side=tk.LEFT, padx=6)

        # FPGA BRAM Upload knoppen
        def upload_current_tile():
            if not self.ser:
                messagebox.showerror("Niet Verbonden", "Verbind eerst met de COM-poort van de FPGA!")
                return
            save_grid_to_bank(curr_t_id[0])
            tid = curr_t_id[0]
            self.ser.write(bytes([0x0D, tid & 0x3F]))
            self.ser.write(self.tile_bank[tid])
            status_lbl.config(text=f"✅ Tegel #{tid} direct geüpload naar FPGA BRAM!")
            self.status_var.set(f"Tegel #{tid} geüpload naar FPGA!")

        def upload_all_tiles():
            if not self.ser:
                messagebox.showerror("Niet Verbonden", "Verbind eerst met de COM-poort van de FPGA!")
                return
            save_grid_to_bank(curr_t_id[0])
            for tid in range(64):
                self.ser.write(bytes([0x0D, tid & 0x3F]))
                self.ser.write(self.tile_bank[tid])
                time.sleep(0.003)
            # Maak SDRAM voorgrond transparant zodat tegels direct te zien zijn op HDMI
            self.ser.write(struct.pack('<BB', 0x01, 0xE3))
            time.sleep(0.04)
            if not self.live_mode_var.get():
                self.ser.write(b'\x0B')
                time.sleep(0.01)
                self.ser.write(struct.pack('<BB', 0x01, 0xE3))
                time.sleep(0.04)
            self.canvas.delete("all")
            status_lbl.config(text="⚡ Alle 64 tegels succesvol naar FPGA BRAM geüpload en live zichtbaar!")
            self.status_var.set("Alle 64 tegels geüpload naar FPGA!")
            messagebox.showinfo("FPGA Upload Voltooid", "Alle 64 tegels (16 KB) zijn geladen en direct live zichtbaar op het scherm!")

        tk.Button(top_bar1, text="🚀 Upload Huidige naar FPGA BRAM", bg="#38a169", fg="white", font=("Arial", 9, "bold"), padx=8, pady=2, command=upload_current_tile).pack(side=tk.LEFT, padx=6)
        tk.Button(top_bar1, text="⚡ Upload Alle 64 naar FPGA", bg="#3182ce", fg="white", font=("Arial", 9, "bold"), padx=8, pady=2, command=upload_all_tiles).pack(side=tk.LEFT, padx=6)

        conn_text = "🟢 FPGA Verbonden" if self.ser else "⚪ FPGA Niet Verbonden"
        conn_col = "#9ae6b4" if self.ser else "#cbd5e0"
        tk.Label(top_bar1, text=conn_text, font=("Arial", 9), fg=conn_col, bg="#276749").pack(side=tk.RIGHT, padx=6)

        # 2. TOP BALK 2: BESTANDSBEHEER (BIN & PNG)
        top_bar2 = tk.Frame(editor, bg="#edf2f7", padx=8, pady=4, relief=tk.RIDGE, bd=1)
        top_bar2.pack(fill=tk.X)

        def save_tile_bin():
            save_grid_to_bank(curr_t_id[0])
            filename = filedialog.asksaveasfilename(
                parent=editor, title=f"Sla Tegel #{curr_t_id[0]} op als BIN (256 bytes)",
                initialfile=f"tile_{curr_t_id[0]:02d}.bin", defaultextension=".bin",
                filetypes=[("Tegel Bin (256 bytes)", "*.bin"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            with open(filename, "wb") as f:
                f.write(self.tile_bank[curr_t_id[0]])
            status_lbl.config(text=f"💾 Opgeslagen: {os.path.basename(filename)} (256 bytes)")
            messagebox.showinfo("Opgeslagen", f"Tegel #{curr_t_id[0]} opgeslagen als 256 bytes:\n{filename}")

        def save_tile_png():
            save_grid_to_bank(curr_t_id[0])
            filename = filedialog.asksaveasfilename(
                parent=editor, title=f"Sla Tegel #{curr_t_id[0]} op als PNG",
                initialfile=f"tile_{curr_t_id[0]:02d}.png", defaultextension=".png",
                filetypes=[("PNG Afbeelding", "*.png"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            img = Image.new("RGB", (16, 16))
            for y in range(16):
                for x in range(16):
                    c_val = grid_colors[y][x]
                    r = ((c_val >> 5) & 7) * 255 // 7
                    g = ((c_val >> 2) & 7) * 255 // 7
                    b = (c_val & 3) * 255 // 3
                    img.putpixel((x, y), (r, g, b))
            img.resize((128, 128), Image.Resampling.NEAREST).save(filename)
            status_lbl.config(text=f"🖼️ PNG Opgeslagen: {os.path.basename(filename)}")
            messagebox.showinfo("Opgeslagen", f"Tegel opgeslagen als PNG:\n{filename}")

        def save_all_tiles_bin():
            save_grid_to_bank(curr_t_id[0])
            filename = filedialog.asksaveasfilename(
                parent=editor, title="Sla Alle 64 Tegels op (tiles.bin - 16 KB)",
                initialfile="tiles.bin", defaultextension=".bin",
                filetypes=[("Tegelbank (64 tegels, 16KB)", "*.bin"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            with open(filename, "wb") as f:
                for tid in range(64):
                    f.write(self.tile_bank[tid])
            status_lbl.config(text=f"💾 Alle 64 tegels opgeslagen: {os.path.basename(filename)} (16.384 bytes)")
            messagebox.showinfo("Opgeslagen", f"Alle 64 tegels succesvol opgeslagen in:\n{filename} (16.384 bytes)")

        def load_tile_file():
            filename = filedialog.askopenfilename(
                parent=editor, title="Open Tegel (.BIN of .PNG / .JPG)",
                filetypes=[("Ondersteunde bestanden", "*.bin *.png *.jpg *.jpeg *.bmp"), ("BIN Bestanden", "*.bin"), ("Afbeeldingen", "*.png *.jpg *.bmp"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            if filename.lower().endswith((".png", ".jpg", ".jpeg", ".bmp")):
                try:
                    img = Image.open(filename).convert("RGB").resize((16, 16), Image.Resampling.NEAREST)
                    for y in range(16):
                        for x in range(16):
                            r, g, b = img.getpixel((x, y))
                            r3 = (r >> 5) & 7
                            g3 = (g >> 5) & 7
                            b2 = (b >> 6) & 3
                            grid_colors[y][x] = (r3 << 5) | (g3 << 2) | b2
                    save_grid_to_bank(curr_t_id[0])
                    load_bank_to_grid(curr_t_id[0])
                    status_lbl.config(text=f"📂 Afbeelding geïmporteerd in Tegel #{curr_t_id[0]}")
                    messagebox.showinfo("Geladen", f"Afbeelding geïmporteerd in Tegel #{curr_t_id[0]}!")
                except Exception as e:
                    messagebox.showerror("Fout", f"Kan afbeelding niet openen:\n{e}")
            else:
                try:
                    with open(filename, "rb") as f:
                        data = f.read()
                    if len(data) == 256:
                        self.tile_bank[curr_t_id[0]] = bytearray(data)
                        load_bank_to_grid(curr_t_id[0])
                        status_lbl.config(text=f"📂 Tegel #{curr_t_id[0]} ingeladen (256 bytes)")
                        messagebox.showinfo("Geladen", f"Tegel #{curr_t_id[0]} ingeladen uit 256 bytes bestand!")
                    else:
                        num = min(64, len(data) // 256)
                        for tid in range(num):
                            self.tile_bank[tid] = bytearray(data[tid*256 : (tid+1)*256])
                        load_bank_to_grid(curr_t_id[0])
                        status_lbl.config(text=f"📂 {num} tegels ingeladen uit {os.path.basename(filename)}")
                        messagebox.showinfo("Geladen", f"{num} tegels ingeladen uit bestand ({len(data)} bytes)!")
                except Exception as e:
                    messagebox.showerror("Fout", f"Fout bij inladen:\n{e}")

        tk.Button(top_bar2, text="💾 Sla Huidige BIN op (256B)", bg="#e2e8f0", command=save_tile_bin).pack(side=tk.LEFT, padx=3)
        tk.Button(top_bar2, text="🖼️ Sla Huidige PNG op", bg="#e2e8f0", command=save_tile_png).pack(side=tk.LEFT, padx=3)
        tk.Button(top_bar2, text="💾 Sla Alle 64 op (tiles.bin)", bg="#c6f6d5", font=("Arial", 9, "bold"), command=save_all_tiles_bin).pack(side=tk.LEFT, padx=5)
        tk.Button(top_bar2, text="📂 Laad Bestand (.bin / .png)", bg="#feebc8", font=("Arial", 9, "bold"), command=load_tile_file).pack(side=tk.LEFT, padx=5)

        # 3. BALK 3: GEREEDSCHAPPEN & KLEUR SELECTIE
        tools_frame = tk.Frame(editor, bg="#f7fafc", padx=8, pady=5)
        tools_frame.pack(fill=tk.X)

        tk.Label(tools_frame, text="Kleur:", font=("Arial", 9, "bold"), bg="#f7fafc").pack(side=tk.LEFT, padx=(0, 4))
        color_swatch = tk.Canvas(tools_frame, width=28, height=24, bg=self.rgb332_to_hex(self.color_rgb332), relief=tk.SOLID, bd=1)
        color_swatch.pack(side=tk.LEFT, padx=2)

        def update_swatch():
            hex_c = self.rgb332_to_hex(self.color_rgb332)
            color_swatch.config(bg=hex_c)
            color_label.config(text=f"0x{self.color_rgb332:02X} ({hex_c})")
            self.color_btn.config(bg=self.get_tk_color())

        color_label = tk.Label(tools_frame, text=f"0x{self.color_rgb332:02X}", font=("Courier", 9, "bold"), bg="#f7fafc", width=16, anchor=tk.W)
        color_label.pack(side=tk.LEFT, padx=2)

        def choose_custom_color():
            color = colorchooser.askcolor(parent=editor, title="Kies een Kleur voor Tegel")[0]
            if color:
                r, g, b = [int(c) for c in color]
                r3 = (r >> 5) & 7
                g3 = (g >> 5) & 7
                b2 = (b >> 6) & 3
                self.color_rgb332 = (r3 << 5) | (g3 << 2) | b2
                set_tool("pen")
                update_swatch()

        tk.Button(tools_frame, text="🎨 Kies Kleur...", bg="#bee3f8", font=("Arial", 9, "bold"), command=choose_custom_color).pack(side=tk.LEFT, padx=4)

        # Tool selectie
        tool_btns = {}
        def set_tool(t_name):
            active_tool[0] = t_name
            for k, btn in tool_btns.items():
                if k == t_name:
                    btn.config(relief=tk.SUNKEN, bg="#cbd5e0")
                else:
                    btn.config(relief=tk.RAISED, bg="#edf2f7")

        tool_btns["pen"] = tk.Button(tools_frame, text="✏️ Pen", command=lambda: set_tool("pen"))
        tool_btns["pen"].pack(side=tk.LEFT, padx=2)
        tool_btns["bucket"] = tk.Button(tools_frame, text="🪣 Vul Emmer", command=lambda: set_tool("bucket"))
        tool_btns["bucket"].pack(side=tk.LEFT, padx=2)
        tool_btns["picker"] = tk.Button(tools_frame, text="🔍 Pipet", command=lambda: set_tool("picker"))
        tool_btns["picker"].pack(side=tk.LEFT, padx=2)
        set_tool("pen")

        # Transformatie tools
        def flip_h():
            for y in range(16): grid_colors[y].reverse()
            save_grid_to_bank(curr_t_id[0]); load_bank_to_grid(curr_t_id[0])
        def flip_v():
            grid_colors.reverse()
            save_grid_to_bank(curr_t_id[0]); load_bank_to_grid(curr_t_id[0])
        def rotate_90():
            new_g = [[grid_colors[15-x][y] for x in range(16)] for y in range(16)]
            for y in range(16):
                for x in range(16): grid_colors[y][x] = new_g[y][x]
            save_grid_to_bank(curr_t_id[0]); load_bank_to_grid(curr_t_id[0])
        def fill_all():
            for y in range(16):
                for x in range(16): grid_colors[y][x] = self.color_rgb332
            save_grid_to_bank(curr_t_id[0]); load_bank_to_grid(curr_t_id[0])

        tk.Button(tools_frame, text="↔️ Spiegel H", command=flip_h).pack(side=tk.LEFT, padx=3)
        tk.Button(tools_frame, text="↕️ Spiegel V", command=flip_v).pack(side=tk.LEFT, padx=3)
        tk.Button(tools_frame, text="🔄 Roteer 90°", command=rotate_90).pack(side=tk.LEFT, padx=3)
        tk.Button(tools_frame, text="🪣 Vul Hele Tegel", command=fill_all).pack(side=tk.LEFT, padx=3)

        # 4. BALK 4: SNELPALET (24 KLEUREN)
        palette_frame = tk.Frame(editor, bg="#e2e8f0", padx=8, pady=3)
        palette_frame.pack(fill=tk.X)
        tk.Label(palette_frame, text="Snelpalet:", font=("Arial", 9, "bold"), bg="#e2e8f0").pack(side=tk.LEFT, padx=(0, 4))

        def on_palette_click(c_code):
            self.color_rgb332 = c_code
            set_tool("pen")
            update_swatch()

        for col_code, hex_c, c_name in PALETTE_24:
            b = tk.Button(palette_frame, bg=hex_c, width=2, height=1, relief=tk.RAISED, bd=1,
                          command=lambda c=col_code: on_palette_click(c))
            b.pack(side=tk.LEFT, padx=1)

        # 5. MIDDEN: CANVAS & TEGEL GALERIJ
        content_frame = tk.Frame(editor, padx=10, pady=8)
        content_frame.pack(fill=tk.BOTH, expand=True)

        left_box = tk.Frame(content_frame)
        left_box.pack(side=tk.LEFT, fill=tk.BOTH, padx=(0, 10))

        canvas_size = 352
        cell_size = canvas_size // 16 # 22 pixels per cel

        c = tk.Canvas(left_box, width=canvas_size, height=canvas_size, bg="#111111", cursor="pencil")
        c.pack()

        rects = {}
        for y in range(16):
            for x in range(16):
                r = c.create_rectangle(x*cell_size, y*cell_size, (x+1)*cell_size, (y+1)*cell_size, fill="#000000", outline="#2d3748", width=1)
                rects[(x, y)] = r

        coord_label = tk.Label(left_box, text="X: --, Y: -- | Kleur: --", font=("Courier", 9), anchor=tk.W)
        coord_label.pack(fill=tk.X, pady=(4, 0))

        help_label = tk.Label(left_box, text="Linkermuisknop = Tekenen / Actie | Rechts/Shift = Pipet | Shift+Links = Emmer", font=("Arial", 8), fg="#4a5568")
        help_label.pack(fill=tk.X)

        # Rechter paneel: Mini Gallery van alle 64 Tegels (8x8 grid)
        gallery_frame = tk.LabelFrame(content_frame, text="64 BRAM Tegels Galerij (Klik om direct te bewerken)", padx=6, pady=6)
        gallery_frame.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

        gallery_canvas = tk.Canvas(gallery_frame, width=290, height=360, bg="#1a202c")
        gallery_canvas.pack(fill=tk.BOTH, expand=True)

        def save_grid_to_bank(tid):
            for y in range(16):
                for x in range(16):
                    self.tile_bank[tid][y*16 + x] = grid_colors[y][x]

        def load_bank_to_grid(tid):
            for y in range(16):
                for x in range(16):
                    c_val = self.tile_bank[tid][y*16 + x]
                    grid_colors[y][x] = c_val
                    c.itemconfig(rects[(x, y)], fill=self.rgb332_to_hex(c_val))
            tname = TILE_NAMES.get(tid, f"Tegel #{tid}")
            tile_name_label.config(text=f"[{tid:02d}] {tname}")
            draw_tile_gallery()

        def draw_tile_gallery():
            gallery_canvas.delete("all")
            for tid in range(64):
                col = tid % 8
                row = tid // 8
                gx = col * 35 + 4
                gy = row * 35 + 4
                is_cur = (tid == curr_t_id[0])
                outline_c = "#ecc94b" if is_cur else "#4a5568"
                bg_box = "#2d3748" if is_cur else "#111111"
                gallery_canvas.create_rectangle(gx, gy, gx+33, gy+33, fill=bg_box, outline=outline_c, width=2 if is_cur else 1)
                
                buf = self.tile_bank[tid]
                for py in range(16):
                    for px in range(16):
                        c_val = buf[py*16 + px]
                        tk_c = self.rgb332_to_hex(c_val)
                        gallery_canvas.create_rectangle(gx+1+px*2, gy+1+py*2, gx+1+px*2+2, gy+1+py*2+2, fill=tk_c, outline="")

        def on_gallery_click(event):
            col = (event.x - 4) // 35
            row = (event.y - 4) // 35
            if 0 <= col < 8 and 0 <= row < 8:
                tid = row * 8 + col
                if 0 <= tid < 64 and tid != curr_t_id[0]:
                    save_grid_to_bank(curr_t_id[0])
                    curr_t_id[0] = tid
                    tile_spin_var.set(tid)
                    load_bank_to_grid(tid)

        gallery_canvas.bind("<Button-1>", on_gallery_click)

        # Canvas interacties
        def flood_fill(sx, sy, fill_col):
            if not (0 <= sx < 16 and 0 <= sy < 16): return
            target_col = grid_colors[sy][sx]
            if target_col == fill_col: return
            queue = [(sx, sy)]
            visited = set()
            while queue:
                x, y = queue.pop(0)
                if (x, y) in visited: continue
                visited.add((x, y))
                if 0 <= x < 16 and 0 <= y < 16 and grid_colors[y][x] == target_col:
                    grid_colors[y][x] = fill_col
                    c.itemconfig(rects[(x, y)], fill=self.rgb332_to_hex(fill_col))
                    queue.extend([(x+1, y), (x-1, y), (x, y+1), (x, y-1)])
            save_grid_to_bank(curr_t_id[0])
            draw_tile_gallery()

        def on_canvas_click(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if not (0 <= x < 16 and 0 <= y < 16): return

            tool = active_tool[0]
            if tool == "picker":
                picked = grid_colors[y][x]
                self.color_rgb332 = picked
                set_tool("pen")
                update_swatch()
            elif tool == "bucket":
                flood_fill(x, y, self.color_rgb332)
            else: # Pen
                grid_colors[y][x] = self.color_rgb332
                c.itemconfig(rects[(x, y)], fill=self.rgb332_to_hex(self.color_rgb332))
                save_grid_to_bank(curr_t_id[0])
                draw_tile_gallery()

        def on_canvas_drag(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if not (0 <= x < 16 and 0 <= y < 16): return
            if active_tool[0] == "pen":
                grid_colors[y][x] = self.color_rgb332
                c.itemconfig(rects[(x, y)], fill=self.rgb332_to_hex(self.color_rgb332))
                save_grid_to_bank(curr_t_id[0])

        def on_canvas_release(event):
            draw_tile_gallery()

        def on_canvas_right(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if 0 <= x < 16 and 0 <= y < 16:
                self.color_rgb332 = grid_colors[y][x]
                set_tool("pen")
                update_swatch()

        def on_canvas_motion(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if 0 <= x < 16 and 0 <= y < 16:
                c_val = grid_colors[y][x]
                hex_c = self.rgb332_to_hex(c_val)
                coord_label.config(text=f"X: {x:02d}, Y: {y:02d} | Kleur: 0x{c_val:02X} ({hex_c})")

        def on_shift_click(event):
            x = event.x // cell_size
            y = event.y // cell_size
            if 0 <= x < 16 and 0 <= y < 16:
                flood_fill(x, y, self.color_rgb332)

        c.bind("<Button-1>", on_canvas_click)
        c.bind("<B1-Motion>", on_canvas_drag)
        c.bind("<ButtonRelease-1>", on_canvas_release)
        c.bind("<Button-3>", on_canvas_right)
        c.bind("<Shift-Button-1>", on_shift_click)
        c.bind("<Motion>", on_canvas_motion)

        # 6. STATUS BALK ONDERAAN
        status_lbl = tk.Label(editor, text="Tegel Editor gereed.", bd=1, relief=tk.SUNKEN, anchor=tk.W, bg="#edf2f7", font=("Arial", 9))
        status_lbl.pack(side=tk.BOTTOM, fill=tk.X)

        update_swatch()
        load_bank_to_grid(0)

    # -------------------------------------------------------------------------
    # 🗺️ WERELDKAART PLACER (64x64 TILEMAP)
    # -------------------------------------------------------------------------
    def open_tilemap_editor(self):
        editor = tk.Toplevel(self.root)
        editor.title("MiniGPU Wereldkaart Placer (64x64 Achtergrond)")
        editor.geometry("900x640")
        editor.minsize(860, 600)
        editor.transient(self.root)
        
        selected_tile = [0]
        map_size = 512
        cell_size = map_size // 64 # 8 pixels per tegel
        
        main_frame = tk.Frame(editor)
        main_frame.pack(padx=10, pady=10)
        
        mc = tk.Canvas(main_frame, width=map_size, height=map_size, bg="#000000", cursor="crosshair")
        mc.pack(side=tk.LEFT, padx=10)
        
        def render_full_map():
            mc.delete("all")
            for r in range(64):
                for c_idx in range(64):
                    tid = self.tilemap[r][c_idx]
                    # Bepaal gemiddelde kleur van tegel
                    c_val = self.tile_bank[tid & 0x3F][120]
                    tk_c = self.rgb332_to_tk(c_val) or "#000000"
                    mc.create_rectangle(c_idx*cell_size, r*cell_size, (c_idx+1)*cell_size, (r+1)*cell_size, fill=tk_c, outline="")

        def paint_map(event):
            c_idx = event.x // cell_size
            r = event.y // cell_size
            if 0 <= r < 64 and 0 <= c_idx < 64:
                tid = selected_tile[0]
                self.tilemap[r][c_idx] = tid
                c_val = self.tile_bank[tid & 0x3F][120]
                tk_c = self.rgb332_to_tk(c_val) or "#000000"
                mc.create_rectangle(c_idx*cell_size, r*cell_size, (c_idx+1)*cell_size, (r+1)*cell_size, fill=tk_c, outline="")
                # Upload direct de gewijzigde rij naar FPGA als we verbonden zijn
                if self.ser:
                    self.ser.write(bytes([0x0E, r & 0x3F]))
                    self.ser.write(bytes(self.tilemap[r]))

        def pick_map_tile(event):
            c_idx = event.x // cell_size
            r = event.y // cell_size
            if 0 <= r < 64 and 0 <= c_idx < 64:
                tid = self.tilemap[r][c_idx]
                selected_tile[0] = tid
                sel_spin_var.set(tid)
                name = TILE_NAMES.get(tid, f"Tegel {tid}")
                sel_label.config(text=f"Actief: [{tid}] {name}")

        mc.bind("<Button-1>", paint_map)
        mc.bind("<B1-Motion>", paint_map)
        mc.bind("<Button-3>", pick_map_tile)

        # Besturing
        right_frame = tk.Frame(main_frame)
        right_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=10)

        tk.Label(right_frame, text="Plaats Tegel:", font=("Arial", 10, "bold")).pack(anchor=tk.W, pady=3)
        sel_spin_var = tk.IntVar(value=0)

        def on_sel_change():
            tid = sel_spin_var.get()
            selected_tile[0] = tid
            name = TILE_NAMES.get(tid, f"Tegel {tid}")
            sel_label.config(text=f"Actief: [{tid}] {name}")

        tk.Spinbox(right_frame, from_=0, to=63, textvariable=sel_spin_var, width=5, command=on_sel_change).pack(anchor=tk.W)
        sel_label = tk.Label(right_frame, text="[0] Fris Weidegras", font=("Arial", 9, "bold"), fg="#006600")
        sel_label.pack(anchor=tk.W, pady=5)

        # Camera Hardware Scrolling Sliders
        cam_frame = tk.LabelFrame(right_frame, text="Hardware Camera Scroll", padx=5, pady=5)
        cam_frame.pack(fill=tk.X, pady=10)

        tk.Label(cam_frame, text="Scroll X:").pack(anchor=tk.W)
        cam_x_scale = tk.Scale(cam_frame, from_=0, to=1023, orient=tk.HORIZONTAL)
        cam_x_scale.pack(fill=tk.X)

        tk.Label(cam_frame, text="Scroll Y:").pack(anchor=tk.W)
        cam_y_scale = tk.Scale(cam_frame, from_=0, to=1023, orient=tk.HORIZONTAL)
        cam_y_scale.pack(fill=tk.X)

        def on_scroll_change(val=None):
            sx = int(cam_x_scale.get())
            sy = int(cam_y_scale.get())
            self.render_tilemap_on_canvas(sx, sy)
            if self.ser:
                self.ser.write(bytes([0x0F, sx & 0xFF, (sx >> 8) & 0x03, sy & 0xFF, (sy >> 8) & 0x03]))

        cam_x_scale.config(command=on_scroll_change)
        cam_y_scale.config(command=on_scroll_change)

        # Upload & Kaart Knoppen
        def upload_full_tilemap():
            self.canvas.delete("all")
            self.render_tilemap_on_canvas(int(cam_x_scale.get()), int(cam_y_scale.get()))
            if not self.ser:
                messagebox.showerror("Fout", "Op canvas getoond, maar niet verbonden met GPU voor HDMI!")
                return
            for r in range(64):
                self.ser.write(bytes([0x0E, r & 0x3F]))
                self.ser.write(bytes(self.tilemap[r]))
                time.sleep(0.004)
            # Maak SDRAM voorgrond transparant zodat tegelwereld direct zichtbaar is op HDMI
            self.ser.write(struct.pack('<BB', 0x01, 0xE3))
            time.sleep(0.04)
            if not self.live_mode_var.get():
                self.ser.write(b'\x0B')
                time.sleep(0.01)
                self.ser.write(struct.pack('<BB', 0x01, 0xE3))
                time.sleep(0.04)
            self.status_var.set("Volledige 64x64 wereldkaart geüpload naar FPGA en live zichtbaar!")
            messagebox.showinfo("GPU Upload", "De volledige 1024x1024 tegelkaart staat direct live op je scherm!")

        tk.Button(right_frame, text="🚀 Upload Hele Kaart (64 Rijen)", bg="#c3e6cb", font=("Arial", 9, "bold"), command=upload_full_tilemap).pack(fill=tk.X, pady=4)
        
        def fill_entire_world():
            tid = selected_tile[0]
            name = TILE_NAMES.get(tid, f"Tegel {tid}")
            if messagebox.askyesno("Wereld Vullen", f"Weet je zeker dat je de hele 64x64 wereld wilt vullen met tegel [{tid}] {name}?", parent=editor):
                for r in range(64):
                    self.tilemap[r] = [tid] * 64
                render_full_map()
                if self.ser:
                    upload_full_tilemap()
                self.status_var.set(f"Hele wereldkaart gevuld met tegel [{tid}] {name}!")

        tk.Button(right_frame, text="🌍 Vul Hele Wereld (CLS)", bg="#fef08a", font=("Arial", 9, "bold"), command=fill_entire_world).pack(fill=tk.X, pady=4)
        
        def save_tilemap_file():
            filename = filedialog.asksaveasfilename(
                parent=editor, title="Sla Wereldkaart op (4 KB)",
                initialfile="farm_world.bin", defaultextension=".bin",
                filetypes=[("Tilemap Bin (4096 bytes)", "*.bin"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            with open(filename, "wb") as f:
                for r in range(64):
                    f.write(bytes(self.tilemap[r]))
            messagebox.showinfo("Opgeslagen", f"Wereldkaart opgeslagen in:\n{filename}")

        def load_tilemap_file():
            filename = filedialog.askopenfilename(
                parent=editor, title="Open Wereldkaart (4 KB)",
                filetypes=[("Tilemap Bin", "*.bin"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            with open(filename, "rb") as f:
                data = f.read()
            if len(data) >= 4096:
                for r in range(64):
                    self.tilemap[r] = list(data[r*64 : (r+1)*64])
                render_full_map()
                messagebox.showinfo("Geladen", "Wereldkaart succesvol ingeladen!")

        tk.Button(right_frame, text="💾 Sla Kaart op", command=save_tilemap_file).pack(fill=tk.X, pady=2)
        tk.Button(right_frame, text="📂 Laad Kaart", command=load_tilemap_file).pack(fill=tk.X, pady=2)

        render_full_map()

    # -------------------------------------------------------------------------
    # 🦖 BIG SPRITE STUDIO (2x 128x128 HARDWARE SPRITES)
    # -------------------------------------------------------------------------
    def set_big_sprite_hardware_pos(self, slot):
        if self.ser:
            try:
                en = 1 if self.big_spr_en[slot] else 0
                x = int(self.big_spr_x[slot])
                y = int(self.big_spr_y[slot])
                flip = 1 if self.big_spr_flip[slot] else 0
                cmd = struct.pack('<BBBh h B', 0x15, slot & 1, en, x, y, flip)
                self.ser.write(cmd)
            except Exception as e:
                print(f"Fout bij instellen big sprite pos: {e}")

    def upload_big_sprite_to_fpga(self, slot, progress_cb=None):
        if not self.ser:
            return False, "Niet verbonden met FPGA!"
        try:
            data = self.big_sprite_bank[slot]
            for line in range(128):
                line_bytes = data[line * 128 : (line + 1) * 128]
                cmd = struct.pack('<BBB', 0x16, slot & 1, line)
                self.ser.write(cmd + line_bytes)
                time.sleep(0.003)
                if progress_cb:
                    progress_cb(line + 1, 128)
            # Activeer direct positie
            self.set_big_sprite_hardware_pos(slot)
            return True, f"Slot {slot} succesvol geüpload (16 KB)!"
        except Exception as e:
            return False, str(e)

    def open_big_sprite_manager(self):
        editor = tk.Toplevel(self.root)
        editor.title("🦖 MiniGPU Big Sprite Studio (2x 128x128 Hardware Sprites)")
        editor.geometry("1020x780")
        editor.minsize(980, 720)
        editor.transient(self.root)

        curr_slot = [0]
        brush_size_var = tk.IntVar(value=1)
        is_eraser = [False]
        anim_running = [False]
        anim_step_val = [0.0]

        # ---------------------------------------------------------------------
        # 1. TOP STATUS & SLOT BALK
        # ---------------------------------------------------------------------
        top_bar = tk.Frame(editor, bg="#1e293b", padx=10, pady=8)
        top_bar.pack(fill=tk.X)

        tk.Label(top_bar, text="🦖 Big Sprite Slot:", font=("Arial", 11, "bold"), fg="#f8fafc", bg="#1e293b").pack(side=tk.LEFT, padx=6)
        
        slot_var = tk.IntVar(value=0)
        def on_slot_select():
            curr_slot[0] = slot_var.get()
            s = curr_slot[0]
            en_var.set(self.big_spr_en[s])
            flip_var.set(self.big_spr_flip[s])
            x_slider.set(self.big_spr_x[s])
            y_slider.set(self.big_spr_y[s])
            slot_info_lbl.config(text=f"Actief: Slot {s} ({'Slot 0 (Baas / Speler)' if s == 0 else 'Slot 1 (Metgezel / Vijand)'})")
            update_preview()

        r0 = tk.Radiobutton(top_bar, text="Slot 0 (Baas / Speler)", variable=slot_var, value=0, font=("Arial", 9, "bold"),
                            command=on_slot_select, selectcolor="#0ea5e9", fg="#f8fafc", bg="#1e293b", activebackground="#1e293b", activeforeground="white")
        r0.pack(side=tk.LEFT, padx=6)

        r1 = tk.Radiobutton(top_bar, text="Slot 1 (Metgezel / Vijand)", variable=slot_var, value=1, font=("Arial", 9, "bold"),
                            command=on_slot_select, selectcolor="#0ea5e9", fg="#f8fafc", bg="#1e293b", activebackground="#1e293b", activeforeground="white")
        r1.pack(side=tk.LEFT, padx=6)

        conn_text = "🟢 FPGA Verbonden" if self.ser else "⚪ FPGA Niet Verbonden"
        conn_col = "#4ade80" if self.ser else "#94a3b8"
        tk.Label(top_bar, text=conn_text, font=("Arial", 9, "bold"), fg=conn_col, bg="#1e293b").pack(side=tk.RIGHT, padx=8)

        def make_fb_transparent():
            if self.ser:
                self.ser.write(struct.pack('<BB', 0x01, 0xE3))
                self.canvas.delete("all")
                self.canvas.config(bg="#475569")
                status_lbl.config(text="👁️ SDRAM Framebuffer gewist naar transparant (0xE3). Big Sprites & Wereld zichtbaar!")
            else:
                messagebox.showerror("Niet Verbonden", "Verbind eerst met de FPGA via de hoofdinterface!")

        tk.Button(top_bar, text="👁️ Maak Scherm Transparant (0xE3)", bg="#334155", fg="white", font=("Arial", 9, "bold"), command=make_fb_transparent).pack(side=tk.RIGHT, padx=6)

        # ---------------------------------------------------------------------
        # HOOFD LAYOUT (2 KOLOMMEN: LINKS PREVIEW & TOOLS, RECHTS BESTURING)
        # ---------------------------------------------------------------------
        body_frame = tk.Frame(editor, bg="#f1f5f9", padx=10, pady=8)
        body_frame.pack(fill=tk.BOTH, expand=True)

        # Linker paneel: Canvas & Tekentools
        left_panel = tk.Frame(body_frame, bg="#ffffff", relief=tk.RIDGE, bd=2, padx=10, pady=10)
        left_panel.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 6))

        slot_info_lbl = tk.Label(left_panel, text="Actief: Slot 0 (Baas / Speler)", font=("Arial", 10, "bold"), fg="#0f172a", bg="#ffffff")
        slot_info_lbl.pack(anchor=tk.W, pady=(0, 4))

        # Canvas (384x384 voor 128x128 pixels bij 3x vergroting)
        canvas_preview = tk.Canvas(left_panel, width=384, height=384, bg="#cbd5e1", relief=tk.SUNKEN, bd=2, cursor="crosshair")
        canvas_preview.pack(pady=4)

        coord_lbl = tk.Label(left_panel, text="Pixel: X=0, Y=0 | Kleur: 0xE3 (Transparant)", font=("Courier", 9, "bold"), fg="#334155", bg="#ffffff")
        coord_lbl.pack(pady=2)

        # Toolbalk onder canvas
        tool_bar = tk.Frame(left_panel, bg="#ffffff", pady=4)
        tool_bar.pack(fill=tk.X)

        color_swatch = tk.Label(tool_bar, text="   ", bg=self.get_tk_color(), relief=tk.SOLID, bd=1, width=3)
        color_swatch.pack(side=tk.LEFT, padx=3)

        def update_swatch():
            if is_eraser[0]:
                color_swatch.config(bg="#475569", text="T", fg="white")
            else:
                color_swatch.config(bg=self.get_tk_color(), text="   ")

        def choose_custom():
            is_eraser[0] = False
            self.choose_color(parent=editor)
            update_swatch()

        tk.Button(tool_bar, text="🎨 Kleur...", bg="#e0e7ff", font=("Arial", 9, "bold"), command=choose_custom).pack(side=tk.LEFT, padx=3)

        def set_erase():
            is_eraser[0] = True
            update_swatch()

        def set_pen():
            is_eraser[0] = False
            update_swatch()

        tk.Button(tool_bar, text="✏️ Pen", bg="#e2e8f0", command=set_pen).pack(side=tk.LEFT, padx=2)
        tk.Button(tool_bar, text="⬜ Gum (Transparant)", bg="#fee2e2", command=set_erase).pack(side=tk.LEFT, padx=2)

        tk.Label(tool_bar, text="Penseel:", bg="#ffffff").pack(side=tk.LEFT, padx=(6, 2))
        tk.Spinbox(tool_bar, from_=1, to=8, textvariable=brush_size_var, width=3).pack(side=tk.LEFT)

        # Snelle kleurtjes
        quick_bar = tk.Frame(left_panel, bg="#ffffff", pady=2)
        quick_bar.pack(fill=tk.X)
        q_cols = [
            ("Zwart", 0x00, "#000000"), ("Wit", 0xFF, "#ffffff"),
            ("Rood", 0xE0, "#ff0000"), ("Groen", 0x1C, "#00ff00"),
            ("Blauw", 0x03, "#0000ff"), ("Geel", 0xFC, "#ffff00"),
            ("Oranje", 0xEC, "#ff9200"), ("Paars", 0x83, "#9200ff"),
            ("Cyaan", 0x1F, "#00ffff"), ("Trans", 0xE3, "#475569")
        ]
        for name, code, hex_c in q_cols:
            def make_cmd(c=code, h=hex_c, n=name):
                if n == "Trans":
                    return set_erase
                def cmd():
                    is_eraser[0] = False
                    self.set_quick_color(c, h)
                    update_swatch()
                return cmd
            btn = tk.Button(quick_bar, text="T" if name == "Trans" else "", bg=hex_c, fg="white" if name == "Trans" else "black", width=2, command=make_cmd())
            btn.pack(side=tk.LEFT, padx=1)

        # Transformatie tools
        trans_bar = tk.Frame(left_panel, bg="#ffffff", pady=4)
        trans_bar.pack(fill=tk.X)

        def flip_horiz():
            slot = curr_slot[0]
            data = self.big_sprite_bank[slot]
            for y in range(128):
                row = data[y*128 : (y+1)*128]
                row.reverse()
                data[y*128 : (y+1)*128] = row
            update_preview()

        def flip_vert():
            slot = curr_slot[0]
            data = self.big_sprite_bank[slot]
            for y in range(64):
                opp = 127 - y
                r1 = data[y*128 : (y+1)*128]
                r2 = data[opp*128 : (opp+1)*128]
                data[y*128 : (y+1)*128] = r2
                data[opp*128 : (opp+1)*128] = r1
            update_preview()

        def clear_big_sprite():
            slot = curr_slot[0]
            if messagebox.askyesno("Wissen", f"Weet je zeker dat je Big Sprite Slot {slot} helemaal wilt wissen (transparant)?", parent=editor):
                self.big_sprite_bank[slot] = bytearray([0xE3] * (128 * 128))
                update_preview()

        tk.Button(trans_bar, text="↔️ Spiegel H", command=flip_horiz).pack(side=tk.LEFT, padx=3)
        tk.Button(trans_bar, text="↕️ Spiegel V", command=flip_vert).pack(side=tk.LEFT, padx=3)
        tk.Button(trans_bar, text="🧹 Wis Alles", bg="#fee2e2", command=clear_big_sprite).pack(side=tk.LEFT, padx=3)

        # Render preview functie
        def update_preview():
            slot = curr_slot[0]
            raw = self.big_sprite_bank[slot]
            img = Image.new("RGBA", (128, 128))
            pixels = img.load()
            for y in range(128):
                for x in range(128):
                    c = raw[y * 128 + x]
                    if c == 0xE3:
                        cb = 238 if ((x // 4) + (y // 4)) % 2 == 0 else 210
                        pixels[x, y] = (cb, cb, cb, 255)
                    else:
                        r = ((c >> 5) & 7) * 255 // 7
                        g = ((c >> 2) & 7) * 255 // 7
                        b = (c & 3) * 255 // 3
                        pixels[x, y] = (r, g, b, 255)
            tk_img = ImageTk.PhotoImage(img.resize((384, 384), Image.Resampling.NEAREST))
            canvas_preview.img_ref = tk_img
            canvas_preview.delete("all")
            canvas_preview.create_image(0, 0, anchor=tk.NW, image=tk_img)

        # Muis interactie op canvas
        def on_canvas_paint(event):
            x = event.x // 3
            y = event.y // 3
            if 0 <= x < 128 and 0 <= y < 128:
                col = 0xE3 if is_eraser[0] else self.color_rgb332
                brush = brush_size_var.get()
                slot = curr_slot[0]
                for by in range(brush):
                    for bx in range(brush):
                        nx, ny = x + bx, y + by
                        if 0 <= nx < 128 and 0 <= ny < 128:
                            self.big_sprite_bank[slot][ny * 128 + nx] = col
                update_preview()

        def on_canvas_hover(event):
            x = event.x // 3
            y = event.y // 3
            if 0 <= x < 128 and 0 <= y < 128:
                c = self.big_sprite_bank[curr_slot[0]][y * 128 + x]
                hex_c = "Transparant (0xE3)" if c == 0xE3 else f"0x{c:02X} ({self.rgb332_to_hex(c)})"
                coord_lbl.config(text=f"Pixel: X={x:3d}, Y={y:3d} | Kleur: {hex_c}")

        canvas_preview.bind("<Button-1>", on_canvas_paint)
        canvas_preview.bind("<B1-Motion>", on_canvas_paint)
        canvas_preview.bind("<Motion>", on_canvas_hover)

        # ---------------------------------------------------------------------
        # RECHTER PANEEL: BESTANDEN, VOORBEELDEN & FPGA BESTURING
        # ---------------------------------------------------------------------
        right_panel = tk.Frame(body_frame, bg="#ffffff", relief=tk.RIDGE, bd=2, padx=12, pady=10)
        right_panel.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

        # Sectie 1: FPGA Hardware Besturing (Live)
        sec_fpga = tk.LabelFrame(right_panel, text="⚡ FPGA Hardware Besturing (HDMI Scanout)", font=("Arial", 10, "bold"), fg="#0f172a", bg="#ffffff", padx=8, pady=6)
        sec_fpga.pack(fill=tk.X, pady=(0, 8))

        progress_bar = ttk.Progressbar(sec_fpga, orient=tk.HORIZONTAL, length=280, mode='determinate')
        progress_bar.pack(fill=tk.X, pady=4)

        def upload_current():
            slot = curr_slot[0]
            status_lbl.config(text=f"Uploaden van 128 rijen naar FPGA Slot {slot}...")
            progress_bar['value'] = 0
            editor.update()
            
            def cb(cur, tot):
                progress_bar['value'] = int((cur / tot) * 100)
                editor.update()

            ok, msg = self.upload_big_sprite_to_fpga(slot, cb)
            if ok:
                en_var.set(True)
                self.big_spr_en[slot] = True
                self.set_big_sprite_hardware_pos(slot)
                status_lbl.config(text=f"✅ Slot {slot} (16 KB) live geladen in FPGA BRAM!")
                messagebox.showinfo("FPGA Upload Voltooid", f"Big Sprite Slot {slot} (128x128 pixels, 16.384 bytes) is succesvol geüpload naar de FPGA BRAM en direct actief!")
            else:
                messagebox.showerror("Upload Fout", msg)

        tk.Button(sec_fpga, text="🚀 Upload Sprite naar FPGA (16 KB)", bg="#10b981", fg="white", font=("Arial", 10, "bold"), pady=4, command=upload_current).pack(fill=tk.X, pady=3)

        ctrl_opts_frame = tk.Frame(sec_fpga, bg="#ffffff")
        ctrl_opts_frame.pack(fill=tk.X, pady=4)

        en_var = tk.BooleanVar(value=self.big_spr_en[curr_slot[0]])
        flip_var = tk.BooleanVar(value=self.big_spr_flip[curr_slot[0]])

        def on_toggle_ctrl():
            slot = curr_slot[0]
            self.big_spr_en[slot] = en_var.get()
            self.big_spr_flip[slot] = flip_var.get()
            self.set_big_sprite_hardware_pos(slot)

        tk.Checkbutton(ctrl_opts_frame, text="👁️ Zichtbaar op HDMI (Enable)", variable=en_var, font=("Arial", 9, "bold"), bg="#ffffff", command=on_toggle_ctrl).pack(side=tk.LEFT, padx=6)
        tk.Checkbutton(ctrl_opts_frame, text="↔️ Spiegelen (Flip H)", variable=flip_var, font=("Arial", 9, "bold"), bg="#ffffff", command=on_toggle_ctrl).pack(side=tk.LEFT, padx=6)

        # Positie sliders
        pos_frame = tk.Frame(sec_fpga, bg="#ffffff")
        pos_frame.pack(fill=tk.X, pady=4)

        pos_lbl = tk.Label(pos_frame, text=f"Positie: ({self.big_spr_x[curr_slot[0]]}, {self.big_spr_y[curr_slot[0]]})", font=("Arial", 9, "bold"), bg="#ffffff")
        pos_lbl.pack(anchor=tk.W)

        def on_slider_move(val):
            slot = curr_slot[0]
            self.big_spr_x[slot] = int(x_slider.get())
            self.big_spr_y[slot] = int(y_slider.get())
            pos_lbl.config(text=f"Positie: ({self.big_spr_x[slot]}, {self.big_spr_y[slot]})")
            self.set_big_sprite_hardware_pos(slot)

        tk.Label(pos_frame, text="X Positie (-128 .. 640):", bg="#ffffff").pack(anchor=tk.W)
        x_slider = tk.Scale(pos_frame, from_=-128, to=640, orient=tk.HORIZONTAL, bg="#ffffff", command=on_slider_move)
        x_slider.set(self.big_spr_x[curr_slot[0]])
        x_slider.pack(fill=tk.X)

        tk.Label(pos_frame, text="Y Positie (-128 .. 360):", bg="#ffffff").pack(anchor=tk.W)
        y_slider = tk.Scale(pos_frame, from_=-128, to=360, orient=tk.HORIZONTAL, bg="#ffffff", command=on_slider_move)
        y_slider.set(self.big_spr_y[curr_slot[0]])
        y_slider.pack(fill=tk.X)

        # D-pad en snelknoppen
        dpad_frame = tk.Frame(sec_fpga, bg="#ffffff")
        dpad_frame.pack(fill=tk.X, pady=4)

        step_var = tk.IntVar(value=8)
        tk.Label(dpad_frame, text="Stap:", bg="#ffffff").pack(side=tk.LEFT)
        for st in [1, 8, 32]:
            tk.Radiobutton(dpad_frame, text=f"{st}px", variable=step_var, value=st, bg="#ffffff").pack(side=tk.LEFT)

        def nudge(dx, dy):
            step = step_var.get()
            x_slider.set(x_slider.get() + dx * step)
            y_slider.set(y_slider.get() + dy * step)

        tk.Button(dpad_frame, text="◄", width=3, command=lambda: nudge(-1, 0)).pack(side=tk.LEFT, padx=2)
        tk.Button(dpad_frame, text="▲", width=3, command=lambda: nudge(0, -1)).pack(side=tk.LEFT, padx=2)
        tk.Button(dpad_frame, text="▼", width=3, command=lambda: nudge(0, 1)).pack(side=tk.LEFT, padx=2)
        tk.Button(dpad_frame, text="►", width=3, command=lambda: nudge(1, 0)).pack(side=tk.LEFT, padx=2)

        def center_sprite():
            x_slider.set(256)
            y_slider.set(116)

        tk.Button(dpad_frame, text="🎯 Centreer", bg="#e2e8f0", command=center_sprite).pack(side=tk.RIGHT, padx=4)

        # Vloeiende demo animatie
        def toggle_animation():
            if anim_running[0]:
                anim_running[0] = False
                anim_btn.config(text="✨ Start HDMI Animatie", bg="#e0e7ff")
            else:
                anim_running[0] = True
                anim_btn.config(text="⏹️ Stop Animatie", bg="#fecaca")
                en_var.set(True)
                self.big_spr_en[curr_slot[0]] = True
                def anim_loop():
                    if not anim_running[0] or not editor.winfo_exists():
                        return
                    anim_step_val[0] += 0.05
                    import math
                    t = anim_step_val[0]
                    new_x = int(256 + 180 * math.cos(t))
                    new_y = int(116 + 80 * math.sin(t * 1.5))
                    flip = 1 if math.sin(t) < 0 else 0
                    flip_var.set(bool(flip))
                    x_slider.set(new_x)
                    y_slider.set(new_y)
                    editor.after(25, anim_loop)
                anim_loop()

        anim_btn = tk.Button(sec_fpga, text="✨ Start HDMI Animatie", bg="#e0e7ff", font=("Arial", 9, "bold"), command=toggle_animation)
        anim_btn.pack(fill=tk.X, pady=3)

        # Sectie 2: Bestanden & Importeren
        sec_files = tk.LabelFrame(right_panel, text="📁 Bestanden & Importeren", font=("Arial", 10, "bold"), fg="#0f172a", bg="#ffffff", padx=8, pady=6)
        sec_files.pack(fill=tk.X, pady=(0, 8))

        def import_image():
            filename = filedialog.askopenfilename(
                parent=editor, title="Kies afbeelding om te converteren naar 128x128 Big Sprite",
                filetypes=[("Afbeeldingen", "*.png *.jpg *.jpeg *.bmp *.gif *.webp"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            try:
                src = Image.open(filename).convert("RGBA")
                resized = src.resize((128, 128), Image.Resampling.LANCZOS)
                slot = curr_slot[0]
                buf = bytearray(128 * 128)
                for y in range(128):
                    for x in range(128):
                        r, g, b, a = resized.getpixel((x, y))
                        if a < 128:
                            buf[y * 128 + x] = 0xE3
                        else:
                            r3 = (r >> 5) & 7
                            g3 = (g >> 5) & 7
                            b2 = (b >> 6) & 3
                            buf[y * 128 + x] = (r3 << 5) | (g3 << 2) | b2
                self.big_sprite_bank[slot] = buf
                update_preview()
                status_lbl.config(text=f"🖼️ {os.path.basename(filename)} geïmporteerd naar Slot {slot}!")
                messagebox.showinfo("Geïmporteerd", f"Afbeelding succesvol geschaald naar 128x128 RGB332 in Slot {slot}!\nKlik op 'Upload naar FPGA' om hem live te tonen!")
            except Exception as e:
                messagebox.showerror("Import Fout", str(e))

        def export_png():
            slot = curr_slot[0]
            filename = filedialog.asksaveasfilename(
                parent=editor, title=f"Sla Slot {slot} op als PNG (128x128)",
                initialfile=f"big_sprite_slot{slot}.png", defaultextension=".png",
                filetypes=[("PNG Afbeelding", "*.png"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            raw = self.big_sprite_bank[slot]
            img = Image.new("RGBA", (128, 128))
            pixels = img.load()
            for y in range(128):
                for x in range(128):
                    c = raw[y * 128 + x]
                    if c == 0xE3:
                        pixels[x, y] = (0, 0, 0, 0)
                    else:
                        r = ((c >> 5) & 7) * 255 // 7
                        g = ((c >> 2) & 7) * 255 // 7
                        b = (c & 3) * 255 // 3
                        pixels[x, y] = (r, g, b, 255)
            img.save(filename)
            status_lbl.config(text=f"PNG opgeslagen: {os.path.basename(filename)}")
            messagebox.showinfo("Opgeslagen", f"Big Sprite opgeslagen in:\n{filename}")

        def save_bin():
            slot = curr_slot[0]
            filename = filedialog.asksaveasfilename(
                parent=editor, title=f"Sla Slot {slot} op als .BIN (16.384 bytes)",
                initialfile=f"big_sprite_{slot}.bin", defaultextension=".bin",
                filetypes=[("Big Sprite Bin (*.bin)", "*.bin"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            with open(filename, "wb") as f:
                f.write(self.big_sprite_bank[slot])
            status_lbl.config(text=f"BIN opgeslagen: {os.path.basename(filename)}")
            messagebox.showinfo("Opgeslagen", f"16 KB BRAM bestand opgeslagen in:\n{filename}")

        def load_bin():
            filename = filedialog.askopenfilename(
                parent=editor, title="Open Big Sprite .BIN (16.384 bytes)",
                filetypes=[("Big Sprite Bin (*.bin)", "*.bin"), ("Alle bestanden", "*.*")]
            )
            if not filename: return
            try:
                with open(filename, "rb") as f:
                    data = f.read(128 * 128)
                if len(data) == 128 * 128:
                    self.big_sprite_bank[curr_slot[0]] = bytearray(data)
                    update_preview()
                    status_lbl.config(text=f"BIN geladen: {os.path.basename(filename)}")
                    messagebox.showinfo("Geladen", f"16.384 bytes succesvol geladen in Slot {curr_slot[0]}!")
            except Exception as e:
                messagebox.showerror("Fout", str(e))

        file_btn_frame = tk.Frame(sec_files, bg="#ffffff")
        file_btn_frame.pack(fill=tk.X)

        tk.Button(file_btn_frame, text="📁 Importeer Afbeelding...", bg="#dbeafe", font=("Arial", 9, "bold"), command=import_image).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=2)
        tk.Button(file_btn_frame, text="🖼️ Exporteer PNG", bg="#f1f5f9", command=export_png).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=2)

        file_btn_frame2 = tk.Frame(sec_files, bg="#ffffff")
        file_btn_frame2.pack(fill=tk.X, pady=3)
        tk.Button(file_btn_frame2, text="💾 Sla op als .BIN (16 KB)", bg="#f1f5f9", command=save_bin).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=2)
        tk.Button(file_btn_frame2, text="📂 Laad .BIN (16 KB)", bg="#f1f5f9", command=load_bin).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=2)

        # Sectie 3: Kant-en-klare Voorbeelden
        sec_samples = tk.LabelFrame(right_panel, text="🎨 Kant-en-klare Voorbeelden", font=("Arial", 10, "bold"), fg="#0f172a", bg="#ffffff", padx=8, pady=6)
        sec_samples.pack(fill=tk.X)

        def load_sample_file(path, name):
            found = _find_asset_file(path)
            if found and os.path.exists(found):
                with open(found, "rb") as f:
                    data = f.read(128 * 128)
                if len(data) == 128 * 128:
                    self.big_sprite_bank[curr_slot[0]] = bytearray(data)
                    update_preview()
                    status_lbl.config(text=f"Voorbeeld '{name}' geladen in Slot {curr_slot[0]}!")
                    return
            # Fallback naar default_bigspr hex
            hex_fallback = "default_bigspr0.hex" if "0" in path else "default_bigspr1.hex"
            found_hex = _find_asset_file(hex_fallback)
            if found_hex:
                data = _load_hex_bytes(found_hex, 128 * 128)
                if data:
                    self.big_sprite_bank[curr_slot[0]] = data
                    update_preview()
                    status_lbl.config(text=f"Voorbeeld '{name}' geladen uit {hex_fallback} in Slot {curr_slot[0]}!")

        sample_btn_frame = tk.Frame(sec_samples, bg="#ffffff")
        sample_btn_frame.pack(fill=tk.X, pady=2)

        tk.Button(sample_btn_frame, text="🐉 Baas Draak", bg="#fee2e2", font=("Arial", 9, "bold"),
                  command=lambda: load_sample_file("big_sprite_0.bin", "Baas Draak")).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=2)
        tk.Button(sample_btn_frame, text="💎 Cyber Kristal", bg="#ede9fe", font=("Arial", 9, "bold"),
                  command=lambda: load_sample_file("big_sprite_1.bin", "Cyber Kristal")).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=2)
        tk.Button(sample_btn_frame, text="🤖 Mecha Robot", bg="#ccfbf1", font=("Arial", 9, "bold"),
                  command=lambda: load_sample_file("big_sprite_mecha.bin", "Mecha Robot")).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=2)

        # Statusbalk onderaan
        status_lbl = tk.Label(editor, text="🦖 Big Sprite Studio gereed. Slot 0 & 1 hebben elk 16 KB BRAM in de FPGA.", bd=1, relief=tk.SUNKEN, anchor=tk.W, bg="#f8fafc", padx=6, pady=4)
        status_lbl.pack(side=tk.BOTTOM, fill=tk.X)

        # Eerste keer tekenen
        update_preview()

    # -------------------------------------------------------------------------
    # TEKST & LETTERGROOTTE FUNCTIES (1x=8x8 px t/m 8x=64x64 px met het 8x8 FPGA Font)
    # -------------------------------------------------------------------------
    def set_font_scale(self, scale):
        scale = max(1, min(8, int(scale)))
        self.text_scale_var.set(scale)
        self.font_size_lbl.config(text=f"{scale}x ({scale*8}x{scale*8} px)")
        self.current_tool = "text"
        self.status_var.set(f"🔤 Tekst gereedschap actief | FPGA 8x8 Font Grootte: {scale}x ({scale*8}x{scale*8} px)")
        if hasattr(self, "_live_text_update_cb") and self._live_text_update_cb:
            self._live_text_update_cb()

    def increase_font_size(self):
        self.set_font_scale(self.text_scale_var.get() + 1)

    def decrease_font_size(self):
        self.set_font_scale(self.text_scale_var.get() - 1)

    def on_canvas_mousewheel(self, event):
        """Scroll met het muiswiel om het FPGA 8x8 font direct te vergroten/verkleinen in tekst-modus."""
        if self.current_tool == "text":
            if event.delta > 0:
                self.increase_font_size()
            elif event.delta < 0:
                self.decrease_font_size()

    def _grid_to_merged_rects(self, grid, w, h, scale=1):
        """Zet een 2D 1-bit pixelmatrix om in optimaal samengevoegde 2D rechthoeken (x, y, w, h)."""
        active = {}
        rects = []
        for y in range(h):
            runs = []
            x = 0
            row = grid[y]
            while x < w:
                if row[x]:
                    x0 = x
                    while x < w and row[x]:
                        x += 1
                    runs.append((x0, x))
                else:
                    x += 1
            new_active = {}
            for r in runs:
                if r in active:
                    new_active[r] = [active[r][0], y + 1]
                    del active[r]
                else:
                    new_active[r] = [y, y + 1]
            for r, (y0, y1) in active.items():
                rects.append((r[0] * scale, y0 * scale, (r[1] - r[0]) * scale, (y1 - y0) * scale))
            active = new_active
        for r, (y0, y1) in active.items():
            rects.append((r[0] * scale, y0 * scale, (r[1] - r[0]) * scale, (y1 - y0) * scale))
        return rects

    def get_text_rectangles(self, text, scale=None):
        """Genereert (rx, ry, rw, rh) rechthoeken van het vaste 8x8 FPGA font op schaal 1x t/m 8x."""
        if not text:
            return []
        if scale is None:
            scale = self.text_scale_var.get()
        scale = max(1, min(8, int(scale)))

        w = len(text) * 8
        h = 8
        grid = [[0] * w for _ in range(h)]
        for idx, ch in enumerate(text):
            code = ord(ch) if ord(ch) < 128 else 63
            rows = self.font8x8[code]
            ox = idx * 8
            for ry in range(8):
                row_bits = rows[ry]
                for rx in range(8):
                    if (row_bits >> rx) & 1:
                        grid[ry][ox + rx] = 1
        return self._grid_to_merged_rects(grid, w, h, scale=scale)

    def draw_scaled_text_on_canvas_and_fpga(self, text, x1, y1, scale=None):
        """Tekent het geschaalde 8x8 FPGA font op het Tkinter canvas én stuurt deze naar de FPGA."""
        if not text:
            return
        if scale is None:
            scale = self.text_scale_var.get()
        scale = max(1, min(8, int(scale)))

        color = self.get_tk_color()
        rects = self.get_text_rectangles(text, scale)

        # 1. Teken exact op het Tkinter Canvas
        for rx, ry, rw, rh in rects:
            self.canvas.create_rectangle(
                x1 + rx, y1 + ry, x1 + rx + rw, y1 + ry + rh,
                fill=color, outline=color
            )

        # 2. Neem op in MiniGPU-BASIC geschiedenis (.BAS)
        if scale == 1:
            safe_txt = text.replace('"', "'")
            self.record_basic(f'GTEXT {x1},{y1},"{safe_txt}",${self.color_rgb332:02X}')
        else:
            for rx, ry, rw, rh in rects:
                fx, fy = x1 + rx, y1 + ry
                if fx >= 640 or fy >= 360 or fx + rw <= 0 or fy + rh <= 0:
                    continue
                cx0 = max(0, fx)
                cy0 = max(0, fy)
                cw = min(640, fx + rw) - cx0
                ch_h = min(360, fy + rh) - cy0
                if cw > 0 and ch_h > 0:
                    self.record_basic(f'RECT {cx0},{cy0},{cw},{ch_h},${self.color_rgb332:02X}')

        # 3. Stuur naar de FPGA (indien verbonden)
        if self.ser:
            if scale == 1:
                curr_x = x1
                for char in text:
                    char_code = ord(char) if ord(char) < 128 else 63
                    self.ser.write(struct.pack('<BhhhhB', 0x08, curr_x, y1, char_code, 0, self.color_rgb332))
                    curr_x += 8
                    time.sleep(0.0012)
            else:
                for rx, ry, rw, rh in rects:
                    fx, fy = x1 + rx, y1 + ry
                    if fx >= 640 or fy >= 360 or fx + rw <= 0 or fy + rh <= 0:
                        continue
                    cx0 = max(0, fx)
                    cy0 = max(0, fy)
                    cw = min(640, fx + rw) - cx0
                    ch_h = min(360, fy + rh) - cy0
                    if cw > 0 and ch_h > 0:
                        self.ser.write(struct.pack('<BhhhhB', 0x02, cx0, cy0, cw, ch_h, self.color_rgb332))
                        px_count = cw * ch_h
                        if px_count > 5000:
                            time.sleep(0.0015)
                        elif px_count > 1000:
                            time.sleep(0.003)
                        else:
                            time.sleep(0.0012)

        self.status_var.set(f"✅ Tekst '{text}' geplaatst op ({x1}, {y1}) | FPGA 8x8 Font Grootte: {scale}x ({scale*8}x{scale*8} px)")

    def open_text_input_dialog(self, x1, y1):
        """Opent het Tekst & Grootte venster voor ons vaste 8x8 FPGA font met live voorbeeld op het canvas!"""
        dlg = tk.Toplevel(self.root)
        dlg.title("🔤 Tekst Plaatsen (8x8 FPGA Font Vergroten / Verkleinen)")
        dlg.geometry("480x230")
        dlg.resizable(False, False)
        dlg.transient(self.root)
        dlg.configure(bg="#f8fafc")

        txt_var = tk.StringVar(value="")
        pos_x_var = tk.IntVar(value=x1)
        pos_y_var = tk.IntVar(value=y1)

        # Rij 1: Tekst Invoer
        row1 = tk.Frame(dlg, bg="#f8fafc", padx=12, pady=8)
        row1.pack(fill=tk.X)
        tk.Label(row1, text="Typ je tekst:", font=("Arial", 10, "bold"), bg="#f8fafc").pack(side=tk.LEFT)
        txt_entry = tk.Entry(row1, textvariable=txt_var, font=("Courier", 12, "bold"), width=30, bg="#ffffff")
        txt_entry.pack(side=tk.LEFT, padx=8, fill=tk.X, expand=True)

        # Rij 2: Lettergrootte Vergroten & Verkleinen
        row2 = tk.LabelFrame(dlg, text="🔎 FPGA 8x8 Font Vergroten & Verkleinen (Live op Canvas!)", font=("Arial", 9, "bold"), bg="#fef9c3", padx=10, pady=6)
        row2.pack(fill=tk.X, padx=12, pady=4)

        dlg_size_lbl = tk.Label(row2, text=f"{self.text_scale_var.get()}x ({self.text_scale_var.get()*8}x{self.text_scale_var.get()*8} px)",
                                font=("Courier", 10, "bold"), bg="#ffffff", width=13, relief=tk.SUNKEN, bd=1)

        def update_live_preview(*args):
            self.canvas.delete("live_text_preview")
            s = self.text_scale_var.get()
            dlg_size_lbl.config(text=f"{s}x ({s*8}x{s*8} px)")
            t = txt_var.get()
            try:
                px = pos_x_var.get()
                py = pos_y_var.get()
            except Exception:
                px, py = x1, y1

            if not t:
                h_box = s * 8
                self.canvas.create_rectangle(
                    px, py, px + h_box * 3, py + h_box,
                    outline="#38bdf8", dash=(3, 3), width=1, tags="live_text_preview"
                )
                return

            color = self.get_tk_color()
            rects = self.get_text_rectangles(t, s)
            max_x, max_y = px + len(t) * 8 * s, py + 8 * s
            for rx, ry, rw, rh in rects:
                self.canvas.create_rectangle(
                    px + rx, py + ry, px + rx + rw, py + ry + rh,
                    fill=color, outline=color, tags="live_text_preview"
                )

            self.canvas.create_rectangle(
                px - 2, py - 2, max_x + 2, max_y + 2,
                outline="#38bdf8", dash=(3, 3), width=1, tags="live_text_preview"
            )

        self._live_text_update_cb = update_live_preview

        tk.Button(row2, text="🔎- Kleiner", bg="#fee2e2", font=("Arial", 9, "bold"), padx=6,
                  command=self.decrease_font_size).pack(side=tk.LEFT, padx=2)
        dlg_size_lbl.pack(side=tk.LEFT, padx=4)
        tk.Button(row2, text="🔎+ Groter", bg="#dcfce7", font=("Arial", 9, "bold"), padx=6,
                  command=self.increase_font_size).pack(side=tk.LEFT, padx=2)

        for sc in [1, 2, 3, 4, 6, 8]:
            tk.Button(row2, text=f"{sc}x", font=("Arial", 8, "bold"), width=2, bg="#ffffff",
                      command=lambda v=sc: self.set_font_scale(v)).pack(side=tk.LEFT, padx=1)

        # Rij 3: Positie fijnafstellen
        row3 = tk.Frame(dlg, bg="#f8fafc", padx=12, pady=4)
        row3.pack(fill=tk.X)
        tk.Label(row3, text="Positie op scherm:", font=("Arial", 9, "bold"), bg="#f8fafc").pack(side=tk.LEFT)
        tk.Label(row3, text="X:", font=("Arial", 9), bg="#f8fafc").pack(side=tk.LEFT, padx=(8, 2))
        tk.Spinbox(row3, from_=0, to=639, textvariable=pos_x_var, width=5, command=update_live_preview).pack(side=tk.LEFT)
        tk.Label(row3, text="Y:", font=("Arial", 9), bg="#f8fafc").pack(side=tk.LEFT, padx=(8, 2))
        tk.Spinbox(row3, from_=0, to=359, textvariable=pos_y_var, width=5, command=update_live_preview).pack(side=tk.LEFT)

        txt_var.trace_add("write", update_live_preview)
        pos_x_var.trace_add("write", update_live_preview)
        pos_y_var.trace_add("write", update_live_preview)

        def confirm_text(event=None):
            self._live_text_update_cb = None
            self.canvas.delete("live_text_preview")
            final_text = txt_var.get()
            try:
                fx, fy = pos_x_var.get(), pos_y_var.get()
            except Exception:
                fx, fy = x1, y1
            dlg.destroy()
            if final_text:
                self.draw_scaled_text_on_canvas_and_fpga(final_text, fx, fy)

        def cancel_text(event=None):
            self._live_text_update_cb = None
            self.canvas.delete("live_text_preview")
            dlg.destroy()

        # Rij 4: Bevestig & Annuleer knoppen
        row4 = tk.Frame(dlg, bg="#f8fafc", padx=12, pady=6)
        row4.pack(fill=tk.X)

        tk.Button(row4, text="✅ Plaats Tekst op Scherm & FPGA (Enter)", bg="#22c55e", fg="white",
                  font=("Arial", 10, "bold"), padx=12, pady=4, command=confirm_text).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))
        tk.Button(row4, text="❌ Annuleren", bg="#ef4444", fg="white",
                  font=("Arial", 9, "bold"), padx=10, pady=4, command=cancel_text).pack(side=tk.RIGHT)

        txt_entry.bind("<Return>", confirm_text)
        dlg.bind("<Escape>", cancel_text)
        dlg.protocol("WM_DELETE_WINDOW", cancel_text)

        update_live_preview()
        txt_entry.focus_set()

    # -------------------------------------------------------------------------
    # CANVAS TEKEN ACTIES (SDRAM FRAMEBUFFER)
    # -------------------------------------------------------------------------
    def on_click(self, event):
        if self.current_tool == "triangle":
            self.points.append((event.x, event.y))
            if len(self.points) == 3:
                self.draw_final_triangle(self.points)
                self.points = []
            else:
                r = 2
                self.canvas.create_oval(event.x-r, event.y-r, event.x+r, event.y+r, fill=self.get_tk_color())
        else:
            self.start_x = event.x
            self.start_y = event.y
            self.temp_item = None
            
    def on_drag(self, event):
        if self.current_tool == "triangle":
            return
        if self.temp_item:
            self.canvas.delete(self.temp_item)
            
        color = self.get_tk_color()
        if self.current_tool == "line":
            self.temp_item = self.canvas.create_line(self.start_x, self.start_y, event.x, event.y, fill=color)
        elif self.current_tool == "rect":
            self.temp_item = self.canvas.create_rectangle(self.start_x, self.start_y, event.x, event.y, outline=color)
        elif self.current_tool == "circle":
            r = int(((event.x - self.start_x)**2 + (event.y - self.start_y)**2)**0.5)
            self.temp_item = self.canvas.create_oval(self.start_x-r, self.start_y-r, self.start_x+r, self.start_y+r, outline=color)
            
    def on_release(self, event):
        if self.current_tool == "triangle":
            return
        if self.temp_item:
            self.canvas.delete(self.temp_item)
            
        x0, y0 = self.start_x, self.start_y
        x1, y1 = event.x, event.y
        color = self.get_tk_color()
        filled = self.fill_var.get()
        
        if self.current_tool == "sprite":
            s_id = self.sprite_id_var.get() & 0x1F
            s_data = self.sprite_bank[s_id]
            for py in range(16):
                for px in range(16):
                    c_val = s_data[py*16 + px]
                    if c_val != 0xE3:
                        tk_col = self.rgb332_to_tk(c_val)
                        self.canvas.create_rectangle(x1 + px, y1 + py, x1 + px + 1, y1 + py + 1, fill=tk_col, outline=tk_col)
            self.record_basic(f"SPRITE {s_id},{x1},{y1}")
            if self.ser:
                self.ser.write(struct.pack('<BhhhhB', 0x0A, x1, y1, 0, 0, s_id))
            return
            
        if self.current_tool == "text":
            self.open_text_input_dialog(x1, y1)
            return
            
        if self.current_tool == "line":
            self.canvas.create_line(x0, y0, x1, y1, fill=color)
            self.record_basic(f"LINE {x0},{y0},{x1},{y1},${self.color_rgb332:02X}")
            if self.ser:
                self.ser.write(struct.pack('<BhhhhB', 0x03, x0, y0, x1, y1, self.color_rgb332))
        elif self.current_tool == "rect":
            w = abs(x1 - x0)
            h = abs(y1 - y0)
            rx = min(x0, x1)
            ry = min(y0, y1)
            if filled:
                self.canvas.create_rectangle(rx, ry, rx+w, ry+h, fill=color, outline=color)
                self.record_basic(f"RECT {rx},{ry},{w},{h},${self.color_rgb332:02X}")
                if self.ser:
                    self.ser.write(struct.pack('<BhhhhB', 0x02, rx, ry, w, h, self.color_rgb332))
            else:
                self.canvas.create_rectangle(rx, ry, rx+w, ry+h, outline=color)
                self.record_basic(f"LINE {rx},{ry},{rx+w},{ry},${self.color_rgb332:02X}")
                self.record_basic(f"LINE {rx+w},{ry},{rx+w},{ry+h},${self.color_rgb332:02X}")
                self.record_basic(f"LINE {rx+w},{ry+h},{rx},{ry+h},${self.color_rgb332:02X}")
                self.record_basic(f"LINE {rx},{ry+h},{rx},{ry},${self.color_rgb332:02X}")
                if self.ser:
                    self.ser.write(struct.pack('<BhhhhB', 0x03, rx, ry, rx+w, ry, self.color_rgb332))
                    self.ser.write(struct.pack('<BhhhhB', 0x03, rx+w, ry, rx+w, ry+h, self.color_rgb332))
                    self.ser.write(struct.pack('<BhhhhB', 0x03, rx+w, ry+h, rx, ry+h, self.color_rgb332))
                    self.ser.write(struct.pack('<BhhhhB', 0x03, rx, ry+h, rx, ry, self.color_rgb332))
        elif self.current_tool == "circle":
            r = int(((x1 - x0)**2 + (y1 - y0)**2)**0.5)
            if filled:
                self.canvas.create_oval(x0-r, y0-r, x0+r, y0+r, fill=color, outline=color)
                self.record_basic(f"DISK {x0},{y0},{r},${self.color_rgb332:02X}")
                if self.ser:
                    self.ser.write(struct.pack('<BhhhhB', 0x05, x0, y0, r, 0, self.color_rgb332))
            else:
                self.canvas.create_oval(x0-r, y0-r, x0+r, y0+r, outline=color)
                self.record_basic(f"CIRCLE {x0},{y0},{r},${self.color_rgb332:02X}")
                if self.ser:
                    self.ser.write(struct.pack('<BhhhhB', 0x04, x0, y0, r, 0, self.color_rgb332))
                    
    def draw_final_triangle(self, pts):
        x1, y1 = pts[0]
        x2, y2 = pts[1]
        x3, y3 = pts[2]
        color = self.get_tk_color()
        filled = self.fill_var.get()
        if filled:
            self.canvas.create_polygon(x1, y1, x2, y2, x3, y3, fill=color, outline=color)
            self.record_basic(f"FTRI {x1},{y1},{x2},{y2},{x3},{y3},${self.color_rgb332:02X}")
            if self.ser:
                self.ser.write(struct.pack('<BhhhhhhB', 0x07, x1, y1, x2, y2, x3, y3, self.color_rgb332))
        else:
            self.canvas.create_polygon(x1, y1, x2, y2, x3, y3, fill='', outline=color)
            self.record_basic(f"TRI {x1},{y1},{x2},{y2},{x3},{y3},${self.color_rgb332:02X}")
            if self.ser:
                self.ser.write(struct.pack('<BhhhhhhB', 0x06, x1, y1, x2, y2, x3, y3, self.color_rgb332))

if __name__ == "__main__":
    root = tk.Tk()
    app = MiniGPUPaint(root)
    root.mainloop()
