import os
import math

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(BASE_DIR, "src")
DONDERDAG_DIR = r"E:\hardware\DONDERDAG"

def patch_gpu_engine():
    p = os.path.join(SRC_DIR, "gpu_engine.v")
    with open(p, "r", encoding="utf-8") as f:
        s = f.read().replace("\r\n", "\n")

    if "output wire        busy" not in s:
        s = s.replace(
            "    output reg [7:0]   big_spr_ram_din\n);",
            "    output reg [7:0]   big_spr_ram_din,\n    output wire        busy\n);\n\n    assign busy = draw_busy;",
        )
    if "parse_state <= 55" not in s:
        s = s.replace(
            "else if (rx_data == 22) parse_state <= 52; // UPLOAD_BIG_SPRITE_LINE (0x16)",
            "else if (rx_data == 22) parse_state <= 52; // UPLOAD_BIG_SPRITE_LINE (0x16)\n                        else if (rx_data == 23) parse_state <= 55; // SET_SINGLE_TILE (0x17: mx, my, tile_id)",
        )
        s = s.replace(
            """                        if (upload_counter == 127) parse_state <= 0;
                        else upload_counter <= upload_counter + 1;
                    end
                endcase""",
            """                        if (upload_counter == 127) parse_state <= 0;
                        else upload_counter <= upload_counter + 1;
                    end
                    // 0x17 (23): SET_SINGLE_TILE (3 args: mx (0..63), my (0..63), tile_id (0..63))
                    55: begin ent_tmp_x <= rx_data; parse_state <= 56; end
                    56: begin ent_tmp_y <= rx_data; parse_state <= 57; end
                    57: begin
                        we_tilemap <= 1;
                        addr_tilemap <= {ent_tmp_y[5:0], ent_tmp_x[5:0]};
                        din_tilemap <= rx_data;
                        parse_state <= 0;
                    end
                endcase""",
        )
    if "default_sprites.hex" not in s:
        s = s.replace(
            "reg [7:0]  sprite_ram [0:8191];",
            'reg [7:0]  sprite_ram [0:8191];\n    initial begin\n        $readmemh("default_sprites.hex", sprite_ram);\n    end',
        )
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("gpu_engine.v patched successfully.")

def rgb(r, g, b):
    return ((r & 7) << 5) | ((g & 7) << 2) | (b & 3)

PAL = {
    ".": 0xE3, # Transparant
    "Z": 0x00, # Zwart
    "W": 0xFF, # Wit
    "R": rgb(7, 0, 0), # Rood
    "G": rgb(0, 7, 0), # Groen
    "D": rgb(0, 4, 0), # Donkergroen
    "B": rgb(0, 2, 3), # Blauw
    "L": rgb(2, 5, 3), # Lichtblauw / Cyaan
    "Y": rgb(7, 7, 0), # Geel
    "O": rgb(7, 4, 0), # Oranje
    "P": rgb(6, 2, 3), # Paars
    "S": rgb(7, 5, 2), # Huidskleur
    "M": rgb(4, 2, 0), # Bruin
    "A": rgb(4, 4, 2), # Grijs
}

SPRITE_ART = [
    # 0: Boer / Held
    [
        ".....RRRRRR.....",
        "....RRRRRRRR....",
        "...RRRRRRRRRR...",
        "....ZSSZSSZS....",
        "....SSSSSSSS....",
        "....SSZZZZSS....",
        ".....SSSSSS.....",
        "...BBBBBBBBBB...",
        "..BBBBYYYYBBBB..",
        "..BB.BYYYYB.BB..",
        "..SS.BBBBBB.SS..",
        ".....BBBBBB.....",
        "....BBBBBBBB....",
        "....BBB..BBB....",
        "...MMM....MMM...",
        "...MMM....MMM...",
    ],
    # 1: Alien / Space Invader
    [
        "...G........G...",
        "....G......G....",
        "...GGGGGGGGGG...",
        "..GGGWWGGWWGGG..",
        ".GGGGGGGGGGGGGG.",
        ".G.GGGGGGGGGG.G.",
        ".G.G........G.G.",
        "...GG.GGGG.GG...",
        "....GGGGGGGG....",
        "...G..GGGG..G...",
        "..G..........G..",
        "..G..........G..",
        "................",
        "................",
        "................",
        "................",
    ],
    # 2: Ruimteschip (Player Ship)
    [
        ".......WW.......",
        "......WWWW......",
        "......WLLW......",
        ".....WWLLWW.....",
        ".....WLLLLW.....",
        "....WWLLLLWW....",
        "...RWWLLLLWWR...",
        "..RRWWWWWWWWRR..",
        ".RRRWWLLLLWWRRR.",
        ".R.WWWWWWWWWW.R.",
        "R..WWWWWWWWWW..R",
        "R...WW....WW...R",
        "....OO....OO....",
        "....YY....YY....",
        ".....R....R.....",
        "................",
    ],
    # 3: Bal / Energiebol
    [
        ".....RRRRRR.....",
        "...RRRRRRRRRR...",
        "..RRRWWWRRRRRR..",
        ".RRRWWWWWRRRRRR.",
        ".RRRWWWRRRRRRRR.",
        "RRRRRRRRRRRRRRRR",
        "RRRRRRRRRRRRRRRR",
        "RRRRRRRRRRRRRRRR",
        "RRRRRRRRRRRRRRRR",
        "RRRRRRRRRRRRRRRR",
        ".RRRRRRRRRRRRRR.",
        ".RRRRRRRRRRRRRR.",
        "..RRRRRRRRRRRR..",
        "...RRRRRRRRRR...",
        ".....RRRRRR.....",
        "................",
    ],
    # 4: Gouden Munt
    [
        ".....YYYYYY.....",
        "...YYYYYYYYYY...",
        "..YYOOOOOOOOYY..",
        ".YYOOYYYYYYOOYY.",
        ".YYOYYWWWWYYOYY.",
        "YYOOYYWOOYYOOYYY",
        "YYOOYYWOOYYOOYYY",
        "YYOOYYWOOYYOOYYY",
        "YYOOYYWOOYYOOYYY",
        "YYOOYYWOOYYOOYYY",
        ".YYOYYWWWWYYOYY.",
        ".YYOOYYYYYYOOYY.",
        "..YYOOOOOOOOYY..",
        "...YYYYYYYYYY...",
        ".....YYYYYY.....",
        "................",
    ],
    # 5: Hartje
    [
        "..RRRR....RRRR..",
        ".RRRRRR..RRRRRR.",
        "RRRRWWWW.RRRRRRR",
        "RRRWWWRRRRRRRRRR",
        "RRRRRRRRRRRRRRRR",
        "RRRRRRRRRRRRRRRR",
        ".RRRRRRRRRRRRRR.",
        ".RRRRRRRRRRRRRR.",
        "..RRRRRRRRRRRR..",
        "...RRRRRRRRRR...",
        "....RRRRRRRR....",
        ".....RRRRRR.....",
        "......RRRR......",
        ".......RR.......",
        "................",
        "................",
    ],
    # 6: Sleutel
    [
        ".....YYYYYY.....",
        "....YY....YY....",
        "...YY......YY...",
        "...YY......YY...",
        "....YY....YY....",
        ".....YYYYYY.....",
        ".......YY.......",
        ".......YY.......",
        ".......YY.......",
        ".......YYYYY....",
        ".......YY.......",
        ".......YY.......",
        ".......YYYYYY...",
        ".......YY.......",
        "................",
        "................",
    ],
    # 7: Zwaard
    [
        "..............WW",
        ".............WWW",
        "............WWW.",
        "...........WWW..",
        "..........WWW...",
        ".........WWW....",
        "........WWW.....",
        "...YY..WWW......",
        "....YYWWW.......",
        ".....YYYY.......",
        "....MMYYYY......",
        "...MM..YY.......",
        "..MM............",
        ".YY.............",
        "YY..............",
        "................",
    ],
    # 8: Boom
    [
        ".....GGGGGG.....",
        "...GGGGGGGGGG...",
        "..GGGGGGGGGGGG..",
        ".GGGDDGGGGGGGG..",
        ".GGGGGGGGDDGGGG.",
        ".GGGGGGGGGGGGGG.",
        "..GGGGDDGGGGGG..",
        "...GGGGGGGGGG...",
        ".....GGGGGG.....",
        "......MMMM......",
        "......MMMM......",
        "......MMMM......",
        "......MMMM......",
        ".....MMMMMM.....",
        "....MMMMMMMM....",
        "................",
    ],
    # 9: Paddenstoel
    [
        ".....RRRRRR.....",
        "...RRRRWWWRRR...",
        "..RRRRWWWWWRRR..",
        ".RRRRRRWWWRRRRR.",
        ".RWWWRRRRRRWWWR.",
        "RWWWWWRRRRWWWWWR",
        "RWWWWWRRRRWWWWWR",
        "RRRRRRRRRRRRRRRR",
        "..SSSSSSSSSSSS..",
        "...SSZSSSSZSS...",
        "...SSZSSSSZSS...",
        "...SSSSSSSSSS...",
        "...SSSSSSSSSS...",
        "....SSSSSSSS....",
        "................",
        "................",
    ],
    # 10: Raceauto
    [
        "....RRRRRRRR....",
        "...RRRRRRRRRR...",
        "..ZZRRRRRRRRZZ..",
        "..ZZRLLLLLLRZZ..",
        "...RRLLLLLLRR...",
        "...RRRRRRRRRR...",
        "..RRRRRRRRRRRR..",
        "..RRRRWWWRRRRR..",
        "..RRRRWWWRRRRR..",
        "..ZZRRRRRRRRZZ..",
        "..ZZRRRRRRRRZZ..",
        "...RRRRRRRRRR...",
        "...RRRRRRRRRR...",
        "....YY....YY....",
        "................",
        "................",
    ],
    # 11: Kikker (Frogger)
    [
        "..GG........GG..",
        ".GWWG......GWWG.",
        ".GZZG.GGGG.GZZG.",
        "..GGGGGGGGGGGG..",
        "...GGGGGGGGGG...",
        ".GGGGGGGGGGGGGG.",
        "GG.GGGGGGGGGG.GG",
        "G..GGGGGGGGGG..G",
        "...GGGGGGGGGG...",
        "...GYYYYYYYYG...",
        "..GG.GGGGGG.GG..",
        ".GG..GGGGGG..GG.",
        "GG............GG",
        "G..............G",
        "................",
        "................",
    ],
    # 12: Spookje (Ghost)
    [
        ".....PPPPPP.....",
        "...PPPPPPPPPP...",
        "..PPPPPPPPPPPP..",
        ".PPPWWPPPPWWPPP.",
        ".PPWWWWPPWWWWPP.",
        ".PPWWBBPPWWBBPP.",
        "PPPPPPPPPPPPPPPP",
        "PPPPPPPPPPPPPPPP",
        "PPPPPPPPPPPPPPPP",
        "PPPPPPPPPPPPPPPP",
        "PPPPPPPPPPPPPPPP",
        "PPPPPPPPPPPPPPPP",
        "PPPPPPPPPPPPPPPP",
        "PPP.PPPPPPPP.PPP",
        "PP...PP..PP...PP",
        "................",
    ],
    # 13: Pac-Man
    [
        ".....YYYYYY.....",
        "...YYYYYYYYYY...",
        "..YYYYYYYYYYYY..",
        ".YYYYYYZZYYYYYY.",
        ".YYYYYYYYYYYYYY.",
        "YYYYYYYYYYYY....",
        "YYYYYYYYYY......",
        "YYYYYYYY........",
        "YYYYYYYYYY......",
        "YYYYYYYYYYYY....",
        ".YYYYYYYYYYYYYY.",
        ".YYYYYYYYYYYYYY.",
        "..YYYYYYYYYYYY..",
        "...YYYYYYYYYY...",
        ".....YYYYYY.....",
        "................",
    ],
    # 14: Explosie
    [
        "..R....Y.....R..",
        "...R..YYY...R...",
        ".Y..ROOOOOOR..Y.",
        "..YYOOOOOOOOYY..",
        "...OOYYYYYYOO...",
        "..ROOYYWWYYOOR..",
        ".YROOYWWWWYOORY.",
        "..ROOYWWWWYOOR..",
        "...OOYYWWYYOO...",
        "..YYOOOOOOOOYY..",
        ".Y..ROOOOOOR..Y.",
        "...R..YYY...R...",
        "..R....Y.....R..",
        "................",
        "................",
        "................",
    ],
    # 15: Ster
    [
        ".......YY.......",
        ".......YY.......",
        "......YYYY......",
        "......YYYY......",
        "YYYYYYYYYYYYYYYY",
        ".YYYYYYYYYYYYYY.",
        "..YYYYWWWWYYYY..",
        "...YYYWWWWYYY...",
        "...YYYYYYYYYY...",
        "..YYYYYYYYYYYY..",
        "..YYYY....YYYY..",
        ".YYYY......YYYY.",
        ".YYY........YYY.",
        "YY............YY",
        "................",
        "................",
    ],
]

def write_hex(filename, data_bytes):
    lines = [f"{b:02X}" for b in data_bytes]
    content = "\n".join(lines) + "\n"
    for folder in (BASE_DIR, SRC_DIR):
        with open(os.path.join(folder, filename), "w", encoding="utf-8") as f:
            f.write(content)

def generate_sprites():
    data = bytearray(8192)
    for i in range(8192):
        data[i] = 0xE3
    for idx in range(32):
        art = SPRITE_ART[idx % len(SPRITE_ART)]
        for y in range(16):
            row = art[y]
            for x in range(16):
                ch = row[x] if x < len(row) else "."
                data[idx * 256 + y * 16 + x] = PAL.get(ch, 0xE3)
    write_hex("default_sprites.hex", data)
    print("Generated default_sprites.hex (8192 bytes)")

def generate_tileset_and_map():
    tileset = bytearray(16384)
    # Helper to fill a 16x16 tile
    def set_tile(tid, fn):
        base = tid * 256
        for y in range(16):
            for x in range(16):
                tileset[base + y * 16 + x] = fn(x, y) & 0xFF

    # Tile 0: Gras (groen met sprietjes)
    set_tile(0, lambda x, y: rgb(1, 5, 0) if ((x * 7 + y * 13) % 11 != 0) else rgb(2, 6, 0))
    # Tile 1: Bloemenveld
    set_tile(1, lambda x, y: rgb(7, 7, 0) if ((x - 4) ** 2 + (y - 4) ** 2 <= 2 or (x - 11) ** 2 + (y - 11) ** 2 <= 2) else (rgb(7, 1, 1) if ((x - 11) ** 2 + (y - 4) ** 2 <= 2) else rgb(1, 5, 0)))
    # Tile 2: Water (blauw met golfjes)
    set_tile(2, lambda x, y: rgb(2, 5, 3) if ((y % 4 == 0) and ((x + y) % 6 < 3)) else rgb(0, 3, 3))
    # Tile 3: Zandpad
    set_tile(3, lambda x, y: rgb(6, 5, 1) if ((x * 3 + y * 5) % 7 != 0) else rgb(5, 4, 1))
    # Tile 4: Baksteen muur
    set_tile(4, lambda x, y: rgb(5, 5, 2) if (y % 4 == 0 or ((x + (y // 4) * 4) % 8 == 0)) else rgb(5, 1, 0))
    # Tile 5: Houten brug / planken
    set_tile(5, lambda x, y: rgb(2, 1, 0) if (x % 4 == 0 or y == 0 or y == 15) else rgb(4, 2, 0))
    # Tile 6: Bos / Struik
    set_tile(6, lambda x, y: rgb(0, 3, 0) if ((x - 8) ** 2 + (y - 8) ** 2 > 40) else rgb(0, 5, 0))
    # Tile 7: Sterrenhemel (Space background)
    set_tile(7, lambda x, y: 0xFF if ((x == 3 and y == 4) or (x == 12 and y == 10)) else (rgb(3, 4, 3) if (x == 8 and y == 13) else rgb(0, 0, 1)))
    # Tile 8: Akker (geploegde aarde)
    set_tile(8, lambda x, y: rgb(3, 2, 0) if (y % 3 == 0) else rgb(4, 2, 0))
    # Tile 9: Graanveld
    set_tile(9, lambda x, y: rgb(7, 6, 0) if (x % 2 == 0 and y > 2) else rgb(4, 3, 0))
    # Tile 10: Lava
    set_tile(10, lambda x, y: rgb(7, 6, 0) if ((x + y) % 5 == 0) else rgb(7, 1, 0))
    # Tile 11: Kasteelvloer / Steen
    set_tile(11, lambda x, y: rgb(2, 2, 1) if (x == 0 or y == 0) else rgb(4, 4, 2))
    # Fill remaining tiles 12..63 with colorful patterns
    for tid in range(12, 64):
        c1 = ((tid * 37) & 0xFF)
        c2 = ((tid * 73 + 19) & 0xFF)
        set_tile(tid, lambda x, y, a=c1, b=c2: a if ((x ^ y) & 2) else b)

    write_hex("default_tileset.hex", tileset)
    print("Generated default_tileset.hex (16384 bytes)")

    # Generate 64x64 world tilemap
    tilemap = bytearray(4096)
    for y in range(64):
        for x in range(64):
            t = 0 # Gras
            if (x + y * 3) % 11 == 0:
                t = 1 # Bloemen
            # Border forest
            if x == 0 or x == 63 or y == 0 or y == 63:
                t = 6
            # Horizontal road at y = 10..11
            if 10 <= y <= 11:
                t = 3
            # Vertical road at x = 18..19
            if 18 <= x <= 19:
                t = 3
            # River at x = 30..32
            if 30 <= x <= 32:
                t = 5 if (10 <= y <= 11) else 2 # Bridge over river
            # Farm fields at x = 4..15, y = 3..8
            if 4 <= x <= 9 and 3 <= y <= 8:
                t = 8
            if 10 <= x <= 15 and 3 <= y <= 8:
                t = 9
            # Small house at x = 22..26, y = 4..7
            if 22 <= x <= 26 and 4 <= y <= 7:
                t = 4
            tilemap[y * 64 + x] = t

    write_hex("default_tilemap.hex", tilemap)
    print("Generated default_tilemap.hex (4096 bytes)")

def generate_big_sprites():
    p0 = os.path.join(DONDERDAG_DIR, "big_sprite_pacman.bin")
    p1 = os.path.join(DONDERDAG_DIR, "big_sprite_invaders.bin")
    b0 = open(p0, "rb").read() if os.path.exists(p0) else bytes([0xE3] * 16384)
    b1 = open(p1, "rb").read() if os.path.exists(p1) else bytes([0xE3] * 16384)
    write_hex("default_bigspr0.hex", b0[:16384].ljust(16384, b"\xE3"))
    write_hex("default_bigspr1.hex", b1[:16384].ljust(16384, b"\xE3"))
    print("Generated default_bigspr0.hex and default_bigspr1.hex (2x 16384 bytes)")

if __name__ == "__main__":
    patch_gpu_engine()
    generate_sprites()
    generate_tileset_and_map()
    generate_big_sprites()
