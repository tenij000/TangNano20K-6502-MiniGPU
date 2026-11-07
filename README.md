# 🎮 Tang Nano 20K — MiniGPU-BASIC 1.2 (Zelfstandige Retro-Workstation & Audio Hulp-CPU)

Dit project combineert de volledige **720p HDMI MiniGPU** (met 640×360 double-buffered SDRAM framebuffer, 64×64 hardware parallax tilemap, 32 hardware 16×16 sprites, 2 gigantische 128×128 big sprites, hardware muispijl, 4-stemmige 48 kHz FM-synthesizer én een **Autonome Hardware Audio Hulp-CPU / SDRAM Audio-DMA Engine**) met **MiniGPU-BASIC 1.2** op een ingebouwde **6502 CPU** in de **Tang Nano 20K**.

De Tang Nano 20K werkt hiermee **100% zelfstandig** (met USB/PS2-toetsenbord & muis via Raspberry Pi Pico 2 op pinnen 73/74 én USB-UART op 115200 baud), inclusief interactief **MiniGPU-BASIC voor Dummies** boek (`dummies_boek.bat`) en **WAV & MP3 Studio GUI** (`start_wav_gui.bat`).

---

## 🚀 Snel Starten

1. **Naar de Tang Nano 20K flashen**:
   - Tijdelijk (SRAM, 2 sec): dubbelklik op **`flash_sram.bat`**
   - Permanent (SPI Flash, start altijd zelfstandig op): dubbelklik op **`flash_permanent.bat`**
2. **Ingebouwde Demo's proberen**:
   Typ op je PS/2-toetsenbord (of via een seriële terminal op 115200 baud):
   ```basic
   DEMO 1
   LIST
   RUN
   ```
   *(Druk tijdens `RUN` op **`ESC`** om terug te keren naar de `>` BASIC-prompt!)*

   - **`DEMO 1`**: **Boerderij Parallax & Big Sprites** — Wandel met `WASD` of pijltjestoetsen over de scrollende 64×64 wereldkaart met 16×16 sprites en de 128×128 Big Sprite!
   - **`DEMO 2`**: **60 FPS 2D/3D Geometrie & Double-Buffer Show** — Stuiterende gevulde cirkels, driehoeken en rechthoeken met HDMI-geluidseffecten.
   - **`DEMO 3`**: **Space Defender Arcade Game** — Bestuur je ruimteschip met `A`/`D` of `Links`/`Rechts` en schiet lasers met `Spatie`!
   - **`DEMO 4`**: **HDMI 48 kHz Chiptune Synthesizer** — Speelt een toonladder over HDMI met een live kleurenequalizer.

---

## 📖 Overzicht van alle MiniGPU-BASIC Commando's

### 1. Grafische Commando's (640×360 RGB332)
| Commando | Beschrijving | Voorbeeld |
| :--- | :--- | :--- |
| **`MODE 0` / `MODE 1`** | `0` = Groene tekst-terminal zichtbaar, `1` = Volledig scherm graphics | `MODE 1` |
| **`CLS`** | Wist het tekstscherm | `CLS` |
| **`CLEAR [kleur]`** | Wist het grafische scherm (`$E3` = 227 = transparant, toont tilemap!) | `CLEAR $E3` |
| **`RECT x, y, b, h, c`** | Tekent een hardware-gevulde rechthoek | `RECT 50, 50, 200, 100, $E0` |
| **`LINE x1, y1, x2, y2, c`** | Tekent een hardware Bresenham-lijn | `LINE 0, 0, 639, 359, $FF` |
| **`CIRCLE x, y, r, c`** | Tekent een cirkel-omtrek | `CIRCLE 320, 180, 60, $FF` |
| **`DISK x, y, r, c`** | Tekent een hardware-gevulde cirkel/planeet | `DISK 320, 180, 50, RGB(7,6,0)` |
| **`TRI x1,y1,x2,y2,x3,y3,c`** | Tekent een driehoek-omtrek | `TRI 100,200, 200,50, 300,200, $FF` |
| **`FTRI x1,y1,x2,y2,x3,y3,c`** | Tekent een hardware-gevulde 2D/3D driehoek | `FTRI 100,200, 200,50, 300,200, $1C` |
| **`GTEXT x, y, "tekst", c`** | Tekent tekst op pixelcoördinaten `(x, y)` | `GTEXT 20, 20, "SCORE 100", $FF` |
| **`SPRITE id, x, y`** | Tekent 16×16 sprite `id` (`0..31`) op `(x, y)` | `SPRITE 0, 150, 120` |
| **`BIGSPR s, aan, x, y [,flip]`**| Zet 128×128 Big Sprite (`s=0..1`) aan/uit op `(x, y)` | `BIGSPR 0, 1, 400, 150, 0` |
| **`SCROLL x, y`** | Hardware-scroll (`0..1023`) over de 64×64 achtergrond-tilemap | `SCROLL 120, 60` |
| **`TILE mx, my, id`** | Zet tegel `(mx, my)` (`0..63`) in de tilemap op `id` (`0..63`) | `TILE 10, 10, 2` |
| **`TARGET 0` / `TARGET 1`** | `0` = Teken naar back-buffer (voor `FLIP`), `1` = Direct zichtbaar | `TARGET 0` |
| **`FLIP`** | Wisselt back-buffer en front-buffer (flikkervrije 60 fps animatie) | `FLIP` |

### 2. Ingebouwde 16×16 Sprites (`SPRITE id, x, y`)
Bij het opstarten zitten deze 16×16 sprites direct klaar in het FPGA-geheugen:
- `0`: Boer / Held
- `1`: Alien / Space Invader
- `2`: Ruimteschip
- `3`: Rode Bal / Energiebol
- `4`: Gouden Munt
- `5`: Hartje
- `6`: Gouden Sleutel
- `7`: Zwaard
- `8`: Boom
- `9`: Paddenstoel
- `10`: Raceauto
- `11`: Kikker (Frogger)
- `12`: Spookje
- `13`: Pac-Man
- `14`: Explosie
- `15`: Ster

### 3. Ingebouwde Achtergrond-Tegels (`TILE mx, my, id`)
- `0`: Grasveld
- `1`: Bloemenveld
- `2`: Water met golfjes
- `3`: Zandpad
- `4`: Baksteen muur
- `5`: Houten brug / planken
- `6`: Bos / Struik
- `7`: Sterrenhemel
- `8`: Geploegde akker
- `9`: Graanveld
- `10`: Lava
- `11`: Kasteelvloer / Steen

### 4. Geluid, Invoer, Wiskunde & Opslag
- **`SOUND ch, freq_hz, vol`**: Speelt een toon op HDMI-audiokanaal `0..3` met frequentie in Hz en volume `0..255`.
- **`BEEP freq_hz, duur`**: Speelt een toon op kanaal 0 gedurende `duur × 10 ms`.
- **`WAIT n`**: Wacht `n × 10 ms` (bijv. `WAIT 2` = 20 ms = 50 fps).
- **`RGB(r, g, b)`**: Berekent de RGB332-kleur (`r=0..7`, `g=0..7`, `b=0..3`).
- **`JOY`**: Leest live het PS/2 + UART Arcade Joypad uit:
  - `1` = Omhoog / `W`
  - `2` = Omlaag / `S`
  - `4` = Links / `A`
  - `8` = Rechts / `D`
  - `16` = Vuur 1 (`Spatie` / `Z`)
  - `32` = Vuur 2 (`X` / `Shift` / `Ctrl`)
- **`KEY`**: Leest non-blocking de laatst ingedrukte ASCII-toets (`0` als geen toets).
- **`RND(n)`**, **`ABS(x)`**, **`TIMER`**, **`PEEK(addr)`**, **`POKE addr, val`**.
- **`SAVE "NAAM"`**, **`LOAD "NAAM"`**, **`CAT`** (`FILES`): Sla tot 15 programma's per drive (`D0..D3`) op op de MicroSD-kaart of in de 4 MB SDRAM-Disk (`*SD`, `*SDRAM`, `*DRIVE 0..3`).

### 5. Native 6502 Machinecode (ASM), SD-Copy, Achtergronden & Midnight Commander (`MC`)
- **`CALL addr`** / **`SYS addr`**: Voert een echt 6502 machinecode-programma uit op adres `addr` (bijv. `CALL $8000`, keert met `RTS` terug naar BASIC).
- **`USR(addr)`**: Roept een 6502 machinecode-routine aan op `addr` en geeft de A-accumulator (`0..255`) terug als functie-resultaat.
- **`BSAVE "NAAM", addr, len`**: Slaat een 6502 machinecode-blok (`len` bytes vanaf `addr`) op de SD-kaart op met type `'B'`.
- **`BLOAD "NAAM" [, addr]`**: Laadt een 6502 machinecode-programma van de SD-kaart naar het originele of opgegeven adres.
- **`BRUN "NAAM" [, addr]`**: Laadt én start een 6502 machinecode-programma direct vanaf de SD-kaart (bijv. `BRUN STER6502`, `BRUN ASM6502` of `BRUN MC`).
- **`DEMO 5`**: Laadt én toont een ingebouwde 6502 machinecode- en BASIC-demo op `$8000`.
- **Midnight Commander (`BRUN MC`)**: Volledige dual-pane Norton/Midnight Commander bestandsbeheerder en programmastarter in 6502 machinecode op `$9000` (`sdcard/MC.asm`). Besturing met `W`/`S` (cursor), `Enter`/`Spatie` (start BASIC of 6502 ASM programma), `D`/`2` (wissel drive `D0..D3`), `T`/`9` (transparante glas-modus aan/uit), `Q`/`ESC` (terug naar BASIC).
- **Bestanden kopiëren naar SD-kaart (`sd_copy.py` / `F5` in `basic_terminal.py`)**: Kopieert `.bas`, `.asm` (met ingebouwde 2-pass 6502 assembler!) en `.bin` bestanden uit de map `sdcard/` rechtstreeks naar de SD-kaart in de Tang Nano 20K.
- **Hardware Achtergrond-Lader (`bg_loader.py` / `F6` in `basic_terminal.py`)**: Uploadt 1024×1024 hardware-scrollende achtergronden (`space`, `cyber`, `castle`, `island`, `farm` of een eigen `.png`/`.jpg` foto) naar de 64 hardware-tiles en 64×64 tilemap van de MiniGPU.

### 6. Digitale `.WAV` & `.MP3` Audio en Autonome Hardware Audio Hulp-CPU (`$A018..$A01B`)
- **`WAV`**: Toont de ingebouwde MicroSD WAV-catalogus (`#1..#16`, sector `$2000–$240F`).
- **`WAV 1..16 [, rate [, mode]]`**: Laadt track `1..16` (32 KB) vanaf de MicroSD-kaart naar **SDRAM Bank 61** en speelt deze met **0% CPU-belasting** op de achtergrond af via de **Hardware Audio Hulp-CPU**:
  - `rate`: `1`=8000 Hz, `2`=11025 Hz, `3`=16000 Hz, `4`=22050 Hz, `5`=12000 Hz, `6`=24000 Hz, `7`=32000 Hz.
  - `mode`: `0` (standaard) = eindeloze achtergrond-loop, `1` = eenmalig afspelen (one-shot).
- **`WAV 0`**: Stopt het afspelen van `.WAV` / `.MP3` audio direct.
- **Rechtstreekse aansturing van de Audio Hulp-CPU (`$A018..$A01B`)**:
  - `$A018`: Start SDRAM-bank (`0..61`, bijv. `60` voor een 128 KB / 16,4-seconden `.MP3`-stream over Bank `60..61`).
  - `$A019` / `$A01A`: Aantal pagina's van 256 bytes (`Lo` / `Hi`, bijv. `$0200` = 512 pagina's = 128 KB).
  - `$A01B`: Start/Stop & Snelheid (`0` = Stop, `1..7` = One-shot op rate `1..7`, `129..135` (`+128`) = Auto-Loop op rate `1..7`). Lezen met `PEEK($A01B)` geeft `1` zolang de Hulp-CPU speelt.
- **MP3Commander 2.1 (`BRUN "MP3PLAY"` / `sdcard/MP3PLAY.asm`)**:
  - Volledige Midnight-Commander Dual-Pane `.MP3`- & `.WAV`-speler in 6502 machinecode op `$8000` met 16-Band Live Spectrum Equalizer, muis-, joypad- en toetsenbordbesturing:
    - **Linker Paneel (`.MP3` op MicroSD Sector `$2001` / `$3000..$AFFF`)**: 8 lange/complete `.MP3`-liedjes (tot `30` SDRAM-banken = `1.920 KB` = **4m06s** per nummer!) met automatische background-streaming vanaf de MicroSD-kaart naar SDRAM terwijl de Hardware Audio Hulp-CPU speelt.
    - **Rechter Paneel (`.WAV` op MicroSD Sector `$2000` / `$2010..$240F`)**: 16 `.WAV`-geluiden op Pagina 1/2 en Pagina 2/2 (`32 KB` per track).
    - **Auto-DJ Album-modus (`L`)**, live Sample-Rate/Pitch schakelaar (`S`: `8k/11k/16k/22k Hz`), 4-kanaals FM-Synth Pad begeleiding (`M`), en Background-Play (`B`: muziek speelt door terwijl je terugkeert naar `MC` of BASIC!).
- **Zuivere 48 kHz HDMI-Audio Reconstructie**:
  - 3-polig snelheids-adaptief reconstructiefilter (-18 dB/octaaf) in `src/audio_synth.v` + fase-coherente L/R stereo-uitvoer zonder chorus-vervorming of clipping, gecombineerd met een 101-taps Blackman-windowed Sinc anti-aliasing resampler in `upload_wav_sdcard.py`.
- **MP3 & WAV Studio GUI (`wav_gui.py` / `mp3_studio.bat` / `wav_studio.bat`)**:
  - Grafische Windows-tool waarmee je elk `.MP3`- of `.WAV`-bestand op je PC (automatisch gedecodeerd via Windows Media / ACM) kunt beluisteren, het gewenste aantal SDRAM-banken (`1` t/m `30` banken = `8s` t/m `4m06s`) en sample-rate (`8k..32k Hz`) kunt kiezen, en direct met één klik naar een van de **8 MicroSD `.MP3`-slots (`Sector $2001`)** of **16 `.WAV`-slots (`Sector $2000`)** kunt converteren en uploaden.
- **Interactief Handboek (`MiniGPU_BASIC_voor_Dummies.html` / `dummies_boek.bat`)**:
  - Volledig Nederlandstalig handboek met live 1-klik **Stuur naar Tang Nano (`COM6`)** knoppen, inclusief `.WAV` Jukebox en `.MP3` Visualizer met Hulp-CPU streaming.
