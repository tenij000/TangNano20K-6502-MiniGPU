import math
import os
import sys
import time
import numpy as np
import cv2
import serial

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def rgb_to_332(r, g, b):
    """Convert 8-bit R, G, B (0..255) to 8-bit RGB332 (RRRGGGBB), avoiding 0xE3 transparent key."""
    r3 = min(7, max(0, int(r) >> 5))
    g3 = min(7, max(0, int(g) >> 5))
    b2 = min(3, max(0, int(b) >> 6))
    c = (r3 << 5) | (g3 << 2) | b2
    if c == 0xE3:
        c = 0xE2
    return c


def make_space_theme():
    """Theme 1: Deep Space Nebula, Stars, Ringed Planet & Moon Base (64 tiles + 64x64 map)."""
    tiles = [bytearray(256) for _ in range(64)]
    rng = np.random.RandomState(42)

    # Tiles 0..7: Deep space starfields with varying star densities & colors
    star_cols = [0xFF, 0xDF, 0x9F, 0xFC, 0x1F, 0xFB]
    for tid in range(8):
        bg = 0x00
        t = bytearray([bg] * 256)
        n_stars = 1 if tid < 4 else (3 if tid < 6 else 5)
        for _ in range(n_stars):
            sx = rng.randint(1, 15)
            sy = rng.randint(1, 15)
            col = star_cols[rng.randint(0, len(star_cols))]
            t[sy * 16 + sx] = col
            if tid >= 6 and sx + 1 < 15 and sy + 1 < 15:
                # Twinkle cross star
                t[(sy - 1) * 16 + sx] = 0x03
                t[(sy + 1) * 16 + sx] = 0x03
                t[sy * 16 + (sx - 1)] = 0x03
                t[sy * 16 + (sx + 1)] = 0x03
        tiles[tid] = t

    # Tiles 8..15: Purple/Blue/Magenta Cosmic Nebula clouds
    neb_colors = [0x01, 0x02, 0x21, 0x22, 0x42, 0x43, 0x63, 0x83]
    for idx, tid in enumerate(range(8, 16)):
        t = bytearray(256)
        c1 = neb_colors[idx]
        c2 = neb_colors[min(7, idx + 1)]
        for y in range(16):
            for x in range(16):
                v = math.sin((x + idx * 3) * 0.45) + math.cos((y + idx * 2) * 0.45)
                t[y * 16 + x] = c2 if v > 0.2 else (c1 if v > -0.5 else 0x01)
        # Add a bright star inside nebula
        t[(idx * 3 % 14 + 1) * 16 + (idx * 5 % 14 + 1)] = 0xFF
        tiles[tid] = t

    # Tiles 16..31: 4x4 Giant Ringed Planet (64x64 pixels across 16 tiles)
    for ty in range(4):
        for tx in range(4):
            tid = 16 + ty * 4 + tx
            t = bytearray(256)
            for py in range(16):
                for px in range(16):
                    gx = tx * 16 + px - 32
                    gy = ty * 16 + py - 32
                    dist = math.hypot(gx, gy)
                    # Tilted ring equation
                    rx = gx * 0.92 + gy * 0.38
                    ry = (-gx * 0.38 + gy * 0.92) * 2.6
                    rdist = math.hypot(rx, ry)

                    col = 0x00
                    # Ring behind planet (gy < 0)
                    if gy < 0 and 21.0 <= rdist <= 30.5:
                        col = 0xFC if int(rdist) % 2 == 0 else 0xB4
                    # Planet body
                    if dist <= 17.5:
                        band = int((gy + 18) / 3.5) + int(math.sin(gx * 0.25))
                        shade = 1.0 - max(0.0, (gx + gy) / 36.0)
                        if band % 3 == 0:
                            col = rgb_to_332(40 * shade, 150 * shade, 255 * shade)
                        elif band % 3 == 1:
                            col = rgb_to_332(20 * shade, 100 * shade, 220 * shade)
                        else:
                            col = rgb_to_332(80 * shade, 200 * shade, 255 * shade)
                    # Ring in front of planet (gy >= 0)
                    if gy >= 0 and 21.0 <= rdist <= 30.5:
                        col = 0xFC if int(rdist) % 2 == 0 else 0xB4
                    t[py * 16 + px] = col
            tiles[tid] = t

    # Tiles 32..35: Sci-Fi Space Station / Solar Panels / Tech Grid
    for y in range(16):
        for x in range(16):
            # 32: Solar panel blue grid
            tiles[32][y * 16 + x] = 0x1F if (x % 8 == 0 or y % 4 == 0) else 0x06
            # 33: Hull metallic tile with rivets
            tiles[33][y * 16 + x] = 0x92 if (0 < x < 15 and 0 < y < 15) else 0x49
            if (x in (3, 12)) and (y in (3, 12)):
                tiles[33][y * 16 + x] = 0xFF
            # 34: Glowing cyan energy conduit
            tiles[34][y * 16 + x] = 0x1F if 6 <= y <= 9 else (0x0B if 4 <= y <= 11 else 0x49)
            # 35: Red/Orange docking beacon
            d = math.hypot(x - 7.5, y - 7.5)
            tiles[35][y * 16 + x] = 0xFF if d < 2.5 else (0xE0 if d < 5.5 else 0x49)

    # Build 64x64 Tilemap
    tilemap = bytearray(4096)
    for my in range(64):
        for mx in range(64):
            # Starfield base
            tid = (mx * 7 + my * 13) % 7
            if (mx * 31 + my * 17) % 19 == 0:
                tid = 7
            # Diagonal cosmic nebula band
            neb_d = abs((mx - my) - 6)
            if neb_d < 7:
                tid = 8 + (7 - neb_d)
            # Place 4x4 Ringed Planet at (28..31, 6..9) and (50..53, 36..39)
            if 28 <= mx < 32 and 6 <= my < 10:
                tid = 16 + (my - 6) * 4 + (mx - 28)
            elif 48 <= mx < 52 and 34 <= my < 38:
                tid = 16 + (my - 34) * 4 + (mx - 48)
            # Space station walkway at y = 18..20
            elif my == 19 and (8 <= mx <= 36):
                tid = 34 if mx % 4 != 0 else 35
            elif my in (18, 20) and (12 <= mx <= 32) and mx % 2 == 0:
                tid = 32
            tilemap[my * 64 + mx] = tid

    return tiles, tilemap


def make_cyber_theme():
    """Theme 2: Synthwave / Cyberpunk Neon Grid, Sunset & Mountains."""
    tiles = [bytearray(256) for _ in range(64)]

    # Tiles 0..15: Vertical sky & neon grid gradient
    for tid in range(16):
        t = bytearray(256)
        for y in range(16):
            for x in range(16):
                if tid < 6:
                    # Night sky gradient (dark indigo -> purple)
                    c = 0x01 if tid < 3 else 0x21
                    if (x * 11 + y * 7 + tid * 5) % 43 == 0:
                        c = 0xFF
                    t[y * 16 + x] = c
                elif tid == 6:
                    # Horizon glow bar (magenta/cyan)
                    t[y * 16 + x] = 0xE3 - 1 if y < 6 else (0x1F if y < 10 else 0x42)
                else:
                    # Synthwave perspective neon grid (magenta/cyan lines on dark purple)
                    bg = 0x20 if (tid % 2 == 0) else 0x01
                    is_line = (y == 0) or (y == 8 and tid > 10) or (x == 0) or (x == 8 and tid > 9)
                    t[y * 16 + x] = 0x1F if (y == 0) else (0xC3 if is_line else bg)
        tiles[tid] = t

    # Tiles 16..31: 4x4 Retro Synthwave Striped Sun
    for ty in range(4):
        for tx in range(4):
            tid = 16 + ty * 4 + tx
            t = bytearray(256)
            for py in range(16):
                for px in range(16):
                    gx = tx * 16 + px - 32
                    gy = ty * 16 + py - 32
                    d = math.hypot(gx, gy)
                    col = 0x21
                    if d <= 28.0:
                        # Horizontal scanline cutouts in lower half of sun
                        if gy > 2 and (int(gy) % 5 in (0, 1)):
                            col = 0x21
                        else:
                            r = 255
                            g = max(20, min(240, int(230 - (gy + 28) * 3.5)))
                            b = max(0, min(180, int((gy + 28) * 2.2)))
                            col = rgb_to_332(r, g, b)
                    t[py * 16 + px] = col
            tiles[tid] = t

    # Tiles 32..35: Wireframe Cyber Mountains
    for tid in range(32, 36):
        t = bytearray(256)
        for y in range(16):
            for x in range(16):
                peak = abs(x - 8) if tid % 2 == 0 else (15 - x) // 2
                if y == peak:
                    t[y * 16 + x] = 0x1F
                elif y > peak:
                    t[y * 16 + x] = 0x22 if (x + y) % 4 != 0 else 0x43
                else:
                    t[y * 16 + x] = 0x21
        tiles[tid] = t

    tilemap = bytearray(4096)
    for my in range(64):
        for mx in range(64):
            row_mod = my % 24
            if row_mod < 8:
                tid = min(5, row_mod // 2)
                # Place Synthwave Sun at mx = 18..21, row_mod = 3..6
                if 18 <= mx < 22 and 3 <= row_mod < 7:
                    tid = 16 + (row_mod - 3) * 4 + (mx - 18)
            elif row_mod == 8:
                tid = 32 + (mx % 4)
            elif row_mod == 9:
                tid = 6
            else:
                tid = 7 + min(8, (row_mod - 10) // 2)
            tilemap[my * 64 + mx] = tid

    return tiles, tilemap


def make_castle_theme():
    """Theme 3: Retro RPG Castle, Stone Walls, Cobblestone Courtyard & Moat."""
    tiles = [bytearray(256) for _ in range(64)]
    rng = np.random.RandomState(7)

    # Tile 0..1: Dark Forest Grass
    for tid in (0, 1):
        for y in range(16):
            for x in range(16):
                c = 0x08 if (x + y + tid) % 5 != 0 else 0x0C
                tiles[tid][y * 16 + x] = c
    # Tile 2: Stone Castle Wall Bricks
    for y in range(16):
        for x in range(16):
            row = y // 4
            mortar = (y % 4 == 0) or ((x + (row % 2) * 4) % 8 == 0)
            tiles[2][y * 16 + x] = 0x24 if mortar else (0x6D if (x + y) % 3 else 0x49)
    # Tile 3: Cobblestone Courtyard Floor (dark slate so terminal text is super readable!)
    for y in range(16):
        for x in range(16):
            border = (x % 8 == 0) or (y % 8 == 0)
            tiles[3][y * 16 + x] = 0x00 if border else 0x24
    # Tile 4..5: Deep Blue Moat Water
    for tid in (4, 5):
        for y in range(16):
            for x in range(16):
                wave = (y % 6 == 2 and (x + tid * 3) % 8 in (1, 2, 3))
                tiles[tid][y * 16 + x] = 0x17 if wave else 0x02
    # Tile 6: Glowing Torch on Stone Wall
    tiles[6][:] = tiles[2][:]
    for y in range(4, 13):
        for x in range(6, 10):
            if y < 8:
                tiles[6][y * 16 + x] = 0xFC if (x in (7, 8) and y in (5, 6)) else 0xE0
            else:
                tiles[6][y * 16 + x] = 0x64
    # Tile 7: Royal Red Carpet
    for y in range(16):
        for x in range(16):
            tiles[7][y * 16 + x] = 0xFC if x in (1, 14) else (0x80 if 1 < x < 14 else 0x24)

    tilemap = bytearray(4096)
    for my in range(64):
        for mx in range(64):
            if my in (2, 3, 20, 21):
                tid = 4 + ((mx + my) % 2) # Moat
                if 18 <= mx <= 21:
                    tid = 7 # Bridge carpet
            elif my in (4, 5, 18, 19) or mx in (4, 5, 34, 35):
                tid = 6 if (mx % 5 == 0 and my in (5, 18)) else 2 # Castle walls + torches
            elif 5 < mx < 34 and 5 < my < 18:
                tid = 7 if (18 <= mx <= 21) else 3 # Courtyard + royal carpet
            else:
                tid = (mx + my) % 2
            tilemap[my * 64 + mx] = tid

    return tiles, tilemap


def make_island_theme():
    """Theme 4: Tropical Ocean, Coral Reefs & Sandy Islands."""
    tiles = [bytearray(256) for _ in range(64)]
    for y in range(16):
        for x in range(16):
            # 0: Deep Ocean
            tiles[0][y * 16 + x] = 0x06 if (x + y * 3) % 17 == 0 else 0x02
            # 1: Turquoise Shallow Lagoon
            tiles[1][y * 16 + x] = 0x1F if (x + y * 2) % 13 == 0 else 0x0B
            # 2: Golden Beach Sand
            tiles[2][y * 16 + x] = 0xD4 if (x * 5 + y * 3) % 11 == 0 else 0xF4
            # 3: Lush Tropical Jungle Grass
            tiles[3][y * 16 + x] = 0x10 if (x + y) % 3 == 0 else 0x14
            # 4: Tropical Flower Tile
            tiles[4][y * 16 + x] = tiles[3][y * 16 + x]
            if 5 <= x <= 10 and 5 <= y <= 10:
                tiles[4][y * 16 + x] = 0xFC if (x in (7, 8) and y in (7, 8)) else 0xE2

    tilemap = bytearray(4096)
    for my in range(64):
        for mx in range(64):
            # Two islands centered around (16, 11) and (36, 20)
            d1 = math.hypot((mx - 16) * 0.8, my - 11)
            d2 = math.hypot((mx - 36) * 0.8, my - 20)
            d = min(d1, d2)
            if d < 5.5:
                tid = 4 if (mx * 3 + my * 5) % 7 == 0 else 3
            elif d < 7.5:
                tid = 2
            elif d < 10.5:
                tid = 1
            else:
                tid = 0
            tilemap[my * 64 + mx] = tid

    return tiles, tilemap


def make_farm_theme():
    """Theme 5: Restore original built-in Farm background from default_tileset.hex & default_tilemap.hex."""
    tiles = [bytearray(256) for _ in range(64)]
    ts_path = os.path.join(BASE_DIR, "src", "default_tileset.hex")
    tm_path = os.path.join(BASE_DIR, "src", "default_tilemap.hex")
    with open(ts_path, "r") as f:
        ts_bytes = [int(line.strip(), 16) for line in f if line.strip()]
    for tid in range(64):
        tiles[tid][:] = bytes(ts_bytes[tid * 256 : (tid + 1) * 256])
    with open(tm_path, "r") as f:
        tm_bytes = [int(line.strip(), 16) for line in f if line.strip()]
    return tiles, bytearray(tm_bytes[:4096])


def make_image_tiles_theme(image_path):
    """Convert any image (.png/.jpg) into a 64-tile background + 64x64 tilemap using K-Means tile clustering!"""
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Kan afbeelding niet openen: {image_path}")
    # Resize to 640x368 (40x23 tiles of 16x16) and tile to 1024x1024 (64x64 tiles)
    img_resized = cv2.resize(img, (640, 368), interpolation=cv2.INTER_AREA)
    canvas = np.zeros((1024, 1024, 3), dtype=np.uint8)
    for y in range(0, 1024, 368):
        for x in range(0, 1024, 640):
            h = min(368, 1024 - y)
            w = min(640, 1024 - x)
            canvas[y : y + h, x : x + w] = img_resized[:h, :w]

    # Extract 40x23 = 920 unique 16x16 blocks from the 640x368 image and cluster into 64 representative 16x16 tiles
    blocks = []
    for ty in range(23):
        for tx in range(40):
            patch = img_resized[ty * 16 : (ty + 1) * 16, tx * 16 : (tx + 1) * 16]
            blocks.append(patch.reshape(-1).astype(np.float32))
    blocks_np = np.array(blocks)

    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 15, 1.0)
    _, labels, centers = cv2.kmeans(blocks_np, 64, None, criteria, 3, cv2.KMEANS_PP_CENTERS)

    tiles = [bytearray(256) for _ in range(64)]
    for tid in range(64):
        patch = centers[tid].reshape((16, 16, 3))
        t = bytearray(256)
        for py in range(16):
            for px in range(16):
                b, g, r = patch[py, px]
                t[py * 16 + px] = rgb_to_332(r, g, b)
        tiles[tid] = t

    tilemap = bytearray(4096)
    for my in range(64):
        for mx in range(64):
            sy = my % 23
            sx = mx % 40
            tilemap[my * 64 + mx] = int(labels[sy * 40 + sx, 0])

    return tiles, tilemap


def upload_bg_to_fpga(ser, tiles, tilemap):
    """Stream 64 tiles (cmd 13) + 64x64 tilemap (cmd 14) via \x1bGPU mode, then restore \x1bTXT mode."""
    print("\n[ACHTERGROND] Schakelen naar Hardware GPU-stream en uploaden van 64 tiles + 64x64 tilemap...")
    # Enter GPU stream mode
    ser.write(b"\x1bGPU")
    time.sleep(0.04)

    # Clear SDRAM backbuffer (target 0) to transparent (0xE3) and wait 50ms for GPU rasterizer to finish!
    ser.write(bytes([12, 0, 1, 0xE3]))
    time.sleep(0.05)

    # Clear SDRAM frontbuffer (target 1) to transparent (0xE3) and wait 50ms so background layer shines through!
    ser.write(bytes([12, 1, 1, 0xE3]))
    time.sleep(0.05)

    # Reset scroll to (0, 0)
    ser.write(bytes([15, 0, 0, 0, 0]))
    time.sleep(0.02)

    # Upload 64 tiles (each: [13, tile_id, 256 bytes])
    for tid in range(64):
        pkt = bytes([13, tid]) + bytes(tiles[tid])
        ser.write(pkt)
        if tid % 8 == 7:
            print(f"\r  Tileset uploaden: {tid + 1}/64 tiles...", end="", flush=True)
    print()

    # Upload 64 tilemap rows (each: [14, row_id, 64 bytes])
    for row in range(64):
        pkt = bytes([14, row]) + bytes(tilemap[row * 64 : (row + 1) * 64])
        ser.write(pkt)
    print("  Tilemap (64x64) geupload!")

    time.sleep(0.05)
    # Return to normal MiniGPU-BASIC terminal mode and erase 'GPU' from BASIC input buffer with backspaces
    ser.write(b"\x1bTXT")
    time.sleep(0.03)
    for _ in range(4):
        ser.write(b"\x08")
        time.sleep(0.01)
    ser.read(4096)
    print("[ACHTERGROND] Nieuwe achtergrond is direct actief!\n")


def upload_fullscreen_image(ser, image_path):
    """Stream a 640x360 image directly into the SDRAM framebuffer via \x1bIMG mode."""
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Kan afbeelding niet openen: {image_path}")
    img = cv2.resize(img, (640, 360), interpolation=cv2.INTER_AREA)
    buf = bytearray(640 * 360)
    idx = 0
    for y in range(360):
        for x in range(640):
            b, g, r = img[y, x]
            buf[idx] = rgb_to_332(r, g, b)
            idx += 1

    print(f"\n[FOTO-LOADER] Streaming 640x360 foto '{os.path.basename(image_path)}' (230.400 pixels)...")
    ser.write(b"\x1bIMG")
    time.sleep(0.03)
    chunk_sz = 4096
    for i in range(0, len(buf), chunk_sz):
        ser.write(buf[i : i + chunk_sz])
        print(f"\r  Voortgang: {min(i + chunk_sz, len(buf)) * 100 // len(buf)}%...", end="", flush=True)
    print()
    time.sleep(0.05)
    ser.write(b"\x1bTXT")
    time.sleep(0.03)
    ser.write(b"\x08\x08\x08\x08")
    time.sleep(0.03)
    ser.read(4096)
    print("[FOTO-LOADER] Klaar!\n")


THEMES = {
    "1": ("Space / Melkweg, Sterrennevel & Planeet (Donker & super leesbaar!)", make_space_theme),
    "2": ("Cyberpunk / Synthwave Neon Grid & Zonsondergang", make_cyber_theme),
    "3": ("Retro RPG Kasteel, Fakkels & Binnenplaats", make_castle_theme),
    "4": ("Tropisch Eiland & Koraalzee", make_island_theme),
    "5": ("Originele Boerderij Achtergrond", make_farm_theme),
}


def interactive_bg_menu(ser):
    print("\n" + "=" * 64)
    print("  MINIGPU HARDWARE ACHTERGROND-LOADER (1024x1024 Tile-Engine)")
    print("=" * 64)
    for k, (desc, _) in THEMES.items():
        print(f"  [{k}] {desc}")
    print("  [6] Eigen foto/afbeelding (.png/.jpg) inladen als achtergrond")
    print("-" * 64)
    choice = input("  Kies achtergrond (1..6, of Enter = Annuleren) > ").strip()
    if not choice:
        return
    if choice in THEMES:
        _, builder = THEMES[choice]
        tiles, tilemap = builder()
        upload_bg_to_fpga(ser, tiles, tilemap)
    elif choice == "6":
        path = input("  Pad naar afbeelding (.png/.jpg) > ").strip().strip('"')
        if os.path.exists(path):
            tiles, tilemap = make_image_tiles_theme(path)
            upload_bg_to_fpga(ser, tiles, tilemap)
        else:
            print(f"  Bestand niet gevonden: {path}")


if __name__ == "__main__":
    port = "COM6"
    try:
        ser = serial.Serial(port, 115200, timeout=0.5)
    except Exception as e:
        print(f"Kan {port} niet openen (druk in basic_terminal.py op F6, of sluit basic_terminal.py eerst): {e}")
        sys.exit(1)

    try:
        if len(sys.argv) > 1:
            arg = sys.argv[1].lower()
            name_map = {"space": "1", "cyber": "2", "castle": "3", "island": "4", "farm": "5"}
            key = name_map.get(arg, arg)
            if key in THEMES:
                tiles, tilemap = THEMES[key][1]()
                upload_bg_to_fpga(ser, tiles, tilemap)
            elif os.path.exists(sys.argv[1]):
                if "--full" in sys.argv:
                    upload_fullscreen_image(ser, sys.argv[1])
                else:
                    tiles, tilemap = make_image_tiles_theme(sys.argv[1])
                    upload_bg_to_fpga(ser, tiles, tilemap)
            else:
                interactive_bg_menu(ser)
        else:
            interactive_bg_menu(ser)
    finally:
        ser.close()
