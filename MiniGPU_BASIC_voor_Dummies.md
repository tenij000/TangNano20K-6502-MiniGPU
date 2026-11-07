# 📘 Programmeren in MiniGPU-BASIC 1.2 voor Dummies

**Door: Het Tang Nano 20K Hardware Team**  
*Editie 1.2 — Compleet bijgewerkt met `FUNC naam ... ENDFUNC`, `DO naam [, slot]`, `DEFSPR` / `DEFTILE` / `DEFBIG` & `PIX "hex"`, 640×360 GPU-graphics, alle 256 kleuren, alle vormen, 3D-planetenachtergrond, SD-kaart & Pico 2 toetsenbord!*

> [!TIP]
> **Nieuw in BASIC 1.2 — Eigen Functie-Blokken (`FUNC` & `DO`) voor Sprites, Tiles & `128×128` BigSprites!**  
> Open het interactieve boek met **`dummies_boek.bat`** (**[MiniGPU_BASIC_voor_Dummies.html](MiniGPU_BASIC_voor_Dummies.html)**): teken in **Hoofdstuk 9** (Tiles) of **Hoofdstuk 13** (`16×16` Sprites én `128×128` BigSprite PNG/JPG-Importer) je eigen graphics en klik op **`➕ Plak FUNC in Mijn Programma`**! Je asset wordt als zelfstandig `FUNC naam ... ENDFUNC` blok netjes onderaan je BASIC-programma geplakt en is overal aan te roepen met **`DO naam`**!

---

## 🖥️ Deel I: Kennismaken met je Retro-Supercomputer

### Hoofdstuk 1 & 2: Wat zit er in de Tang Nano 20K en hoe start je?
In de Gowin FPGA op jouw Tang Nano 20K draaien een **27 MHz 6502-processor** én zeven hardware-engines tegelijk:
1. **DONDERDAG 2D Hardware-GPU (`640×360` dubbelgebufferd canvas op 720p HDMI)** voor lijnen, rechthoeken, cirkels, gevulde schijven (`DISK`), open en gevulde driehoeken (`TRI` / `FTRI`), grafische tekst (`GTEXT`) en 32 sprites.
2. **720p 3D-Planeten & Parallax-Sterren Engine**: Draait in `MODE 0` automatisch op 60 FPS achter je BASIC-tekst op alle transparante (`$E3`) pixels!
3. **64×64 Achtergrond Tile-Engine** (`1024×1024` pixels, zichtbaar in `MODE 1` met `CLEAR $E3`).
4. **2× 128×128 BigSprites** (`BIGSPR 0` en `BIGSPR 1`).
5. **4-Kanaals 48 kHz HDMI Audio-Synthesizer** (`SOUND` en `BEEP`).
6. **MicroSD + 4 MB SDRAM-Disk + W5500 Ethernet** (`CAT`, `SD`, `SDRAM`, `DRIVE 0..3`, `SAVE`, `LOAD`, `BRUN`).

Probeer direct zonder regelnummer:
```basic
PRINT "HALLO WERELD OP DE TANG NANO 20K!"
BEEP 880, 15
DISK 320, 180, 60, RGB(7, 6, 0)
CIRCLE 320, 180, 66, $FF
```
Typ `CLS` om het scherm te wissen en de planeten-achtergrond weer vrij te maken, of probeer `DEMO 1` t/m `DEMO 5` gevolgd door `RUN` (druk op `ESC` en typ `LIST` om de code te bekijken).

---

## 🧮 Deel II: Variabelen, Rekenen & Lussen

### Hoofdstuk 3 & 4: Basisregels, `INPUT` én Eigen Functies met Naam (`FUNC` & `DO`)
- **26 Variabelen (`A` t/m `Z`)**: Gebruik altijd **één letter** per variabele (`X`, `Y`, `R`, `S`, `C`).
- **26 Grote SDRAM-Arrays (`A(0)` t/m `Z(32767)`)**: Direct klaar voor gebruik zonder dat geheugen vol raakt (1,6 MB totaal!).
- **Vragen stellen met `INPUT`**:
  - `INPUT R` — toont `? ` en slaat het ingetypte getal op in `R`.
  - `INPUT "HOE GROOT (10-150)", R` — toont `HOE GROOT (10-150)? ` (let op de **komma `,`** tussen de vraagtekst en de variabele!). Extra slim: de speler mag zelfs een som, `$FC` of `RGB(7,4,0)` intypen!
- **Operatoren**: `+`, `-`, `*`, `/`, `%` (modulo/rest), `&` (bitwise EN), `|` (bitwise OF), `^` (XOR), `ABS(x)` en `RND(max)`.
- **Vergelijkingen in `IF ... THEN`**: `=`, `<>`, `<`, `>`, `<=`, `>=`. Combineer je vergelijkingen met `&` of `|`? Zet dan haakjes rond elke vergelijking:
  ```basic
  IF (X > 40) & (X < 600) THEN X = X + 5
  ```
- **Nieuw in BASIC 1.2 — Genoemde Functie-Blokken (`FUNC naam ... ENDFUNC` & `DO naam [, slot]`)**:
  - Zet elk stukje herbruikbare code (of een eigen Sprite, Tile of BigSprite!) in een **`FUNC naam` ... `ENDFUNC`** blok.
  - **Plak `FUNC`-blokken overal waar je wilt** (bovenaan, middenin of onderaan je programma): komt BASIC tijdens het gewone lopen een `FUNC` tegen, dan slaat hij het hele blok tot en met `ENDFUNC` automatisch over!
  - Roep de functie op naam aan met **`DO naam`** (of met een ander doel-slot via **`DO naam, slot`**, zowel in een programma als direct achter de `> ` prompt!).

---

## 🎨 Deel III: Alles over Kleuren & Vormen (De MiniGPU)

### Hoofdstuk 5: Hoe geef je elke vorm precies de kleur die jij wilt? (`RGB332`)
Bij **elk vorm-commando** (`RECT`, `LINE`, `CIRCLE`, `DISK`, `TRI`, `FTRI`, `GTEXT`) is het **laatste getal altijd de kleur** (`0..255`). Je mag een kleur op **4 manieren** meegeven:

1. **Zelf mengen met `RGB(rood, groen, blauw)` *(Aanrader!)***:
   - `rood`: **`0` t/m `7`** (8 stappen)
   - `groen`: **`0` t/m `7`** (8 stappen)
   - `blauw`: **`0` t/m `3`** (4 stappen)
   - Voorbeeld: `DISK 320, 180, 50, RGB(7, 4, 0)` (warme oranje bol).
2. **Hexadecimaal (`$00` t/m `$FF`)**: Bijv. `$FF` (wit), `$00` (zwart), `$E0` (rood), `$1C` (groen), `$03` (blauw), `$FC` (geel), `$1F` (cyaan), **`$E3` (transparant!)**.
3. **Decimaal (`0` t/m `255`)**: Formule: `rood * 32 + groen * 4 + blauw`.
4. **Via een variabele of willekeurig**: Bijv. `C = RGB(2, 5, 3)` of `RND(256)` of een lus-variabele `RGB(I, 7 - I, 2)` voor vloeiende kleurverlopen!

> [!WARNING]
> **Belangrijk verschil tussen Zwart (`0` / `$00`) en Transparant (`227` / `$E3`):**
> - **`0` (`$00` / `RGB(0,0,0)`)** is **écht dekkend zwart**.
> - **`227` (`$E3` / `RGB(7,0,3)`)** is **transparant (doorkijk)**! In `MODE 0` zie je daar de **3D-planeten & bewegende sterren**, en in `MODE 1` zie je daar de **64×64 Boerderij/Zelda wereldmap**. Wil je dekkend felroze/magenta tekenen zonder doorkijk? Gebruik dan `RGB(7, 0, 2)` (`$E2` / `226`)!

#### De Grote Kleuren-Receptentabel (30 Kleuren)

| Kleur & Toepassing | Met `RGB(r,g,b)` | Hex | Getal |
| :--- | :---: | :---: | :---: |
| **Transparant (Doorkijk naar Planeten / Tilemap!)** | `RGB(7, 0, 3)` | `$E3` | `227` |
| **Pikzwart** (dekkend zwart) | `RGB(0, 0, 0)` | `$00` | `0` |
| **Helderwit** | `RGB(7, 7, 3)` | `$FF` | `255` |
| **Lichtgrijs / Zilver** | `RGB(5, 5, 2)` | `$B6` | `182` |
| **Middengrijs / Steen** | `RGB(3, 3, 1)` | `$6D` | `109` |
| **Donkergrijs / Asfalt** | `RGB(2, 2, 1)` | `$49` | `73` |
| **Felrood** | `RGB(7, 0, 0)` | `$E0` | `224` |
| **Donkerrood / Bordeaux** | `RGB(4, 0, 0)` | `$80` | `128` |
| **Rood-Oranje / Lava** | `RGB(7, 2, 0)` | `$E8` | `232` |
| **Oranje** | `RGB(7, 4, 0)` | `$F0` | `240` |
| **Goud / Amber** | `RGB(7, 6, 0)` | `$F8` | `248` |
| **Zonnegeel** | `RGB(7, 7, 0)` | `$FC` | `252` |
| **Zandgeel / Woestijn** | `RGB(6, 5, 1)` | `$D5` | `213` |
| **Huidskleur / Perzik** | `RGB(7, 5, 2)` | `$F6` | `246` |
| **Bruin / Boomstam / Hout** | `RGB(4, 2, 0)` | `$88` | `136` |
| **Donkerbruin / Chocolade** | `RGB(2, 1, 0)` | `$44` | `68` |
| **Limoengroen** | `RGB(4, 7, 0)` | `$9C` | `156` |
| **Felgroen / Neon** | `RGB(0, 7, 0)` | `$1C` | `28` |
| **Grasgroen** | `RGB(1, 5, 0)` | `$34` | `52` |
| **Donkergroen / Dennenbos** | `RGB(0, 3, 0)` | `$0C` | `12` |
| **Mintgroen / Turkoois** | `RGB(0, 7, 2)` | `$1E` | `30` |
| **Cyaan / Elektrisch Lichtblauw** | `RGB(0, 7, 3)` | `$1F` | `31` |
| **Hemelsblauw** (daglucht) | `RGB(2, 5, 3)` | `$57` | `87` |
| **Oceaanblauw / Water** | `RGB(0, 3, 3)` | `$0F` | `15` |
| **Helder Koningsblauw** | `RGB(0, 0, 3)` | `$03` | `3` |
| **Nachtblauw / Diepe Ruimte** | `RGB(0, 0, 1)` | `$01` | `1` |
| **Paars / Violet** | `RGB(4, 0, 3)` | `$83` | `131` |
| **Dieppaars / Indigo** | `RGB(2, 0, 2)` | `$42` | `66` |
| **Felroze / Magenta** *(dekkend!)* | `RGB(7, 0, 2)` | `$E2` | `226` |
| **Zachtroze** | `RGB(7, 3, 3)` | `$EF` | `239` |

---

### Hoofdstuk 6: Alle Vormen tekenen op het `640×360` Scherm
Het scherm loopt horizontaal van **`X = 0` t/m `639`** en verticaal van **`Y = 0` t/m `359`**. Het exacte midden is **`(320, 180)`**.

1. **Scherm vullen of transparant maken (`CLEAR`)**
   - `CLEAR` (of `CLEAR $E3`): Maakt het hele canvas transparant.
   - `CLEAR kleur`: Vult het hele 640×360 scherm met `kleur` (bijv. `CLEAR 0` voor zwart of `CLEAR RGB(2,5,3)` voor hemelsblauw).
2. **Losse Pixel of Dikke Punt (`RECT x, y, 1, 1, kleur`)**
   - `RECT 320, 180, 1, 1, $FF` zet precies 1 witte pixel. Gebruik `2, 2` of `4, 4` voor een grotere ster of stip!
3. **Rechte Lijn (`LINE x1, y1, x2, y2, kleur`)**
   - Trekt een rechte lijn van `(x1, y1)` naar `(x2, y2)` in `kleur`.
4. **Gevulde Rechthoek & Vensterkader (`RECT x, y, breedte, hoogte, kleur`)**
   - Tekent vanaf linkerbovenhoek `(x, y)` een gevulde rechthoek van `breedte × hoogte` pixels.
   - *Rechthoek met andersgekleurde rand*: Teken eerst een grote `RECT` in de randkleur en daarbinnen op `x+2, y+2` een `4` pixels kleinere `RECT` in de vulkleur!
5. **Open Cirkel (`CIRCLE x, y, straal, kleur`)**
   - Tekent alleen de omtrek (ring) rond middelpunt `(x, y)` met grootte `straal`.
6. **Gevulde Cirkel / Schijf (`DISK x, y, straal, kleur`)**
   - Tekent een massief ingekleurde cirkel! Zet er een `CIRCLE` met dezelfde straal overheen voor een strakke buitenrand, en een klein wit `DISK`-stipje linksboven het midden voor een 3D-glanseffect.
7. **Open Driehoek (`TRI x1, y1, x2, y2, x3, y3, kleur`)**
   - Tekent de 3 zijden tussen hoekpunten `(x1,y1)`, `(x2,y2)` en `(x3,y3)`.
8. **Gevulde Driehoek & Veelhoeken (`FTRI x1, y1, x2, y2, x3, y3, kleur`)**
   - Vult de hele driehoek massief met `kleur`! Door twee of drie `FTRI`'s te combineren bouw je een **ruit/diamant**, **pijl**, **dennenboom**, **huisdak** of **3D-piramide met licht- en schaduwkant**!

#### Compleet Voorbeeldprogramma: Alle Vormen & Kleuren Schilderij
```basic
NEW
10 MODE 1 : TARGET 1 : BIGSPR 0,0,0,0 : BIGSPR 1,0,0,0
20 REM --- 1. Lucht met kleurverloop van nachtblauw naar avondrood ---
30 FOR Y = 0 TO 250 STEP 10
40   RECT 0, Y, 640, 10, RGB(Y / 40, Y / 70, 2)
50 NEXT Y
60 REM --- 2. Grasveld (gevulde rechthoek) + horizonlijn ---
70 RECT 0, 250, 640, 110, RGB(1, 4, 0)
80 LINE 0, 250, 639, 250, RGB(3, 7, 0)
90 REM --- 3. Zon met 3 gloeiringen (DISK + CIRCLEs) ---
100 DISK 100, 80, 36, RGB(7, 7, 0)
110 CIRCLE 100, 80, 42, RGB(7, 5, 0)
120 CIRCLE 100, 80, 48, RGB(7, 2, 0)
130 REM --- 4. 3D Piramide (2 gevulde driehoeken: licht & schaduw!) ---
140 FTRI 150, 250, 260, 110, 275, 250, RGB(7, 6, 1)
150 FTRI 275, 250, 260, 110, 370, 250, RGB(4, 2, 0)
160 REM --- 5. Huisje (RECT muren/ramen/deur + FTRI rood puntdak) ---
170 RECT 420, 180, 110, 70, RGB(6, 5, 3)
180 FTRI 405, 180, 475, 125, 545, 180, RGB(7, 1, 0)
190 TRI  405, 180, 475, 125, 545, 180, $FF
200 RECT 462, 212, 26, 38, RGB(3, 1, 0)
210 RECT 432, 195, 20, 20, $FC : RECT 498, 195, 20, 20, $FC
220 REM --- 6. Dennenboom (RECT stam + 3 groene FTRI lagen) ---
230 RECT 582, 225, 16, 25, RGB(4, 2, 0)
240 FTRI 555, 225, 590, 185, 625, 225, RGB(0, 4, 0)
250 FTRI 560, 198, 590, 160, 620, 198, RGB(0, 5, 0)
260 FTRI 566, 172, 590, 138, 614, 172, RGB(1, 6, 0)
270 REM --- 7. 3D Edelsteen / Ruit & Glanzende Planeetbol ---
280 FTRI 80, 305, 110, 270, 140, 305, RGB(0, 7, 3)
290 FTRI 80, 305, 110, 340, 140, 305, RGB(0, 3, 3)
300 TRI  80, 305, 110, 270, 140, 305, $FF
310 DISK 260, 305, 28, RGB(5, 0, 2)
320 DISK 253, 298, 18, RGB(7, 1, 3)
330 DISK 247, 292, 6, $FF : CIRCLE 260, 305, 28, $FF
340 REM --- 8. Vensterkader (dubbele RECT) met GTEXT ---
350 RECT 340, 282, 276, 46, $FC : RECT 343, 285, 270, 40, RGB(0, 0, 1)
360 GTEXT 358, 294, "ALLE VORMEN & KLEUREN!", $FF
370 GTEXT 358, 309, "DRUK OP ESC VOOR BASIC", $1F
380 GOTO 380
RUN
```

---

### Hoofdstuk 7: `GTEXT`, `MODE` en Flikkervrije 60 FPS Animatie (`TARGET 0` & `FLIP`)
- **`GTEXT x, y, "TEKST", kleur`**: Tekent 8×8 tekst op elke pixelpositie `(x, y)` in `kleur`.
- **`MODE 0` / `MODE 1`**: `MODE 0` toont BASIC + 3D-planeten; `MODE 1` gebruikt het volledige scherm voor games/graphics.
- **Double-Buffering**: Zet één keer `TARGET 0` vóór je game-loop (tekent onzichtbaar op de achterbuffer) en zet onderaan je lus `FLIP : WAIT 1`!

---

## 🕹️ Deel IV: Sprites, Wereldmappen, Audio & Games

### Hoofdstuk 8: Alle 16 Ingebouwde `16×16` Sprites (`SPRITE id, x, y`) & `BIGSPR`
- `0` = Boer/Held • `1` = Groene Alien • `2` = Ruimteschip • `3` = Rode Energiebol • `4` = Gouden Munt/Rupee • `5` = Rood Hartje • `6` = Gouden Sleutel • `7` = Zwaard • `8` = Boom • `9` = Paddenstoel • `10` = Raceauto • `11` = Kikker • `12` = Paars Spookje • `13` = Pac-Man • `14` = Explosie • `15` = Ster.
- **`BIGSPR slot, aan_uit, x, y [, spiegel]`**: Zet 128×128 BigSprite `0` of `1` aan (`1`) of uit (`0`), met optioneel `spiegel = 1`.
- **🎯 Basis — Maar ÉÉN losse `16×16` Sprite midden op het scherm zetten (3 regels):**
  ```basic
  NEW
  10 MODE 1 : TARGET 1 : BIGSPR 0, 0, 0, 0 : CLEAR 0
  20 SPRITE 2, 312, 172
  30 GOTO 30
  RUN
  ```
- **🎯 Basis — Maar ÉÉN losse `128×128` Reuzen-Sprite (`BIGSPR`) midden op het scherm zetten (3 regels, let op `CLEAR $E3`!):**
  ```basic
  NEW
  10 MODE 1 : TARGET 1 : CLEAR $E3
  20 BIGSPR 0, 1, 256, 116
  30 GOTO 30
  RUN
  ```

### Hoofdstuk 9: 🗺️ Oneindige 64×64 Werelden bouwen én Tegels als `FUNC` maken!
Achter het voorgrond-tekencanvas zit in de FPGA een **64×64 Hardware Tile-Engine** (`1024×1024` pixels):
- **Zichtbaar maken**: Zet **`MODE 1`** aan en wis de voorgrond met **`CLEAR $E3`** (of `CLEAR`). Overal waar de voorgrond `$E3` is, kijk je naar de wereldmap (`40` kolommen breed × `22,5` rijen hoog tegelijk in beeld).
- **`SCROLL x, y`**: Verschuift de camera pixel-voor-pixel (`0..1023`) over de hele kaart.
- **`TILE kol, rij, id`**: Plaatst tegel `id` (`0..63`) op kaartvakje `(kol, rij)` (`0..63`).
- **64 Tegel-Vakjes (`16×16` pixels per tegel)**:
  - **12 Standaard Tegels (`0..11`)**: `0`=Weidegras (hoofdveld), `1`=Bloemenveld, `2`=Water/Rivier, `3`=Zandpad, `4`=Baksteen, `5`=Houten brug, `6`=Bos/Struik, `7`=Sterrenhemel, `8`=Akker, `9`=Graanveld, `10`=Gloeiende Lava, `11`=Kasteelsteen.
  - **52 Vrije Eigen Tegels (`12..63`)**: Ontwerp je eigen vloeren en muren — óf overschrijf `TILE 0` (Gras) of `TILE 2` (Water) om in één klap de héle wereldmap van thema te veranderen!
- **🎯 Basis — Maar ÉÉN losse Tegel (`TILE`) midden op het scherm zetten (`CLEAR $E3`!):**
  - *1 tegel op de bestaande kaart:* `10 MODE 1 : BIGSPR 0,0,0,0 : CLEAR $E3 : SCROLL 0,0` / `20 TILE 20, 11, 4` / `30 GOTO 30`.
  - *Écht alléén 1 eigen `FUNC`-tegel midden op een verder leeg/zwart scherm:*
    ```basic
    NEW
    10 DO TEGEL_ZWART : DO TEGEL_GOUD
    20 FOR R = 0 TO 22 : FOR K = 0 TO 39 : TILE K, R, 14 : NEXT K : NEXT R
    30 MODE 1 : BIGSPR 0, 0, 0, 0 : CLEAR $E3 : SCROLL 0, 0
    40 TILE 20, 11, 12
    50 GOTO 50
    1000 FUNC TEGEL_ZWART
    1010   DEFTILE 14 : PIX "7F007F000200"
    1020 ENDFUNC
    1100 FUNC TEGEL_GOUD
    1110   DEFTILE 12
    1120   PIX "11880EFC84F088FC000AFC8400FCF08804FC06FF04FC82F08803FC02FF048802FF"
    1130   PIX "03FC82F08803FC02FF048802FF03FC82F08808FC02FF04FC82F08807FC02FF05FC"
    1140   PIX "82F08806FC02FF06FC82F08806FC028806FC82F0880EFC82F08806FC02FF06FC"
    1150   PIX "82F08806FC028806FC84F088FC000AFC8400FCF0880FF01088"
    1160 ENDFUNC
    RUN
    ```

1. **Manier 1 — Interactieve `16×16` Tegel- (Tile-) & Wereld-Ontwerper in `MiniGPU_BASIC_voor_Dummies.html`**:
   - Open het boek met **`dummies_boek.bat`** en ga naar **Hoofdstuk 9**: teken op het `16×16` rooster, controleer rechts de **`3×3` Naadloze Vloer-Preview**, geef je tegel een eigen **`Functie-naam (FUNC)`** (bijv. `TEGEL_BAKSTEEN`) en klik op **`➕ Plak FUNC in Mijn Programma`** (plakt het losse `FUNC ... ENDFUNC` blok onderaan je eigen spel zonder je spel te wissen!), **`📋 Kopieer FUNC`**, **`▶️ Upload Tegel & Wandel (WASD)!`** of **`⚡ Alleen Tegel Uploaden`**!
2. **Manier 2 — Tegels mooi apart houden als Functie-Blok (`FUNC`, `DEFTILE`, `PIX` & `DO`)**:
   - Zet elke eigen tegel in een zelfstandig **`FUNC naam ... ENDFUNC`** blok met **`DEFTILE slot`** (`0..63`) en **`PIX "hex..."`** (`01..7F`+kleur = herhaal RLE, `81..FF`+`N` kleuren = losse pixels; gebruikt **0 BASIC-variabelen**!) en roep ze in je spel aan met **`DO naam`** (of **`DO naam, ander_slot`**):
   ```basic
   NEW
   10 REM --- Hoofdprogramma: roep onze eigen Tegel-FUNCs op naam aan! ---
   20 DO TEGEL_GOUD : DO TEGEL_SCIFI
   30 FOR R = 0 TO 23 : FOR K = 0 TO 39
   40   T = 13
   50   IF ((K & 3) = 0) & ((R & 3) = 0) THEN T = 12
   60   IF (K = 10) | (K = 29) | (R = 4) | (R = 19) THEN T = 12
   70   TILE K, R, T
   80 NEXT K : NEXT R
   90 MODE 1 : TARGET 0 : BIGSPR 0,0,0,0 : X = 312 : Y = 172 : S = 0
   100 CLEAR $E3 : SCROLL S, S / 2 : RECT 12, 8, 616, 22, 0
   110 GTEXT 20, 15, "TEGELS ALS LOSSE FUNC-BLOKKEN (DO)! WASD=VLIEG ESC=STOP", $FC
   120 SPRITE 2, X, Y : FLIP : WAIT 1 : S = (S + 2) & 1023 : J = JOY
   130 IF J & 1 THEN Y = Y - 4
   140 IF J & 2 THEN Y = Y + 4
   150 IF J & 4 THEN X = X - 4
   160 IF J & 8 THEN X = X + 4
   170 GOTO 100
   1000 REM --- Plak hieronder zoveel losse Tegel-FUNCs als je wilt! ---
   1010 FUNC TEGEL_GOUD
   1020   DEFTILE 12
   1030   PIX "11880EFC84F088FC000AFC8400FCF08804FC06FF04FC82F08803FC02FF048802FF"
   1040   PIX "03FC82F08803FC02FF048802FF03FC82F08808FC02FF04FC82F08807FC02FF05FC"
   1050   PIX "82F08806FC02FF06FC82F08806FC028806FC82F0880EFC82F08806FC02FF06FC"
   1060   PIX "82F08806FC028806FC84F088FC000AFC8400FCF0880FF01088"
   1070 ENDFUNC
   1100 FUNC TEGEL_SCIFI
   1110   DEFTILE 13
   1120   PIX "11490EB6024982B6000A6D8500B64949B60C6D84B64949B60C6D84B64949B60C6D"
   1130   PIX "84B64949B60C6D82B649201F8249B60C6D84B64949B60C6D84B64949B60C6D"
   1140   PIX "84B64949B60C6D85B64949B6000A6D8400B649490EB61149"
   1150 ENDFUNC
   RUN
   ```
   *(Je kunt tegels ook met een wiskundige `FOR`-lus in een `FUNC` berekenen via `POKE $A020, 13 : POKE $A020, slot` gevolgd door 256 kleurbytes!)*

### Hoofdstuk 10: HDMI Audio (`SOUND` & `BEEP`)
- **`BEEP freq_hz, duur_10ms`**: Speelt een toon voor `duur × 10 ms` (bijv. `BEEP 880, 15` = 0,15 sec).
- **`SOUND kanaal, freq_hz, volume`**: Zet kanaal `0..3` aan op `freq_hz` met `volume` van **`0` t/m `255`** (`SOUND 0, 0, 0` = stil).

### Hoofdstuk 11: Besturing (`KEY` & `JOY`) en Project "Rupee Vanger"!
Let op: schrijf `KEY` en `JOY` zonder haakjes!
- `JOY & 1` = Omhoog (`W`/↑) • `JOY & 2` = Omlaag (`S`/↓) • `JOY & 4` = Links (`A`/←) • `JOY & 8` = Rechts (`D`/→) • `JOY & 16` = Vuur (`Spatie`/`Z`).

```basic
NEW
10 MODE 1:TARGET 0:BIGSPR 0,0,0,0
20 X=312:S=0:L=3:H=0
30 R=RND(580)+20:U=28
40 O=RND(580)+20:V=-60
45 E=RND(580)+20:W=-180
50 CLEAR $E3:SCROLL S*4,0
60 RECT 8,6,624,22,0
70 GTEXT 16,13,"RUPEE VANGER!  SCORE:",$FC
72 GTEXT 248,13,"AD/PIJL=BEWEEG  ESC=STOP",$1F
75 P=192:D=S/100:GOSUB 300:P=200:D=(S/10)%10:GOSUB 300:P=208:D=S%10:GOSUB 300
80 FOR I=1 TO L:SPRITE 5,520+I*24,9:NEXT I
90 K=KEY:J=JOY
100 IF (J&4)|(K=97)|(K=65) THEN X=X-10
110 IF (J&8)|(K=100)|(K=68) THEN X=X+10
120 IF X<16 THEN X=16
130 IF X>608 THEN X=608
140 U=U+5:V=V+6:W=W+7
150 SPRITE 0,X,316
160 SPRITE 4,R,U
170 IF V>28 THEN SPRITE 1,O,V
175 IF W>28 THEN SPRITE 12,E,W
180 IF (U>298)&(ABS(X-R)<22) THEN S=S+1:BEEP 880,2:BEEP 1175,3:U=28:R=RND(580)+20
190 IF U>345 THEN U=28:R=RND(580)+20
200 IF (V>298)&(ABS(X-O)<18) THEN SPRITE 14,X,316:L=L-1:H=1:V=-60:O=RND(580)+20
210 IF V>345 THEN V=28:O=RND(580)+20
215 IF (W>298)&(ABS(X-E)<18) THEN SPRITE 14,X,316:L=L-1:H=1:W=-140:E=RND(580)+20
218 IF W>345 THEN W=28:E=RND(580)+20
220 FLIP:WAIT 1
225 IF H THEN BEEP 150,15:H=0
230 IF (L>0)&(K<>113)&(K<>81) THEN 50
240 MODE 0:CLS
250 PRINT "GAME OVER! JOUW SCORE: ";S
260 END
300 POKE $A020,8:POKE $A020,P:POKE $A020,0:POKE $A020,13:POKE $A020,0
310 POKE $A020,48+D:POKE $A020,0:POKE $A020,0:POKE $A020,0:POKE $A020,$FF:RETURN
RUN
```

---

## 💾 Deel V: Opslaan, SD-Kaart Apps & `POKE $A020`

### Hoofdstuk 12: Hoe werkt Opslaan & Laden? (`SD`, `SDRAM`, `DRIVE`, `CAT`, `SAVE`, `LOAD`, `BSAVE`, `BLOAD` & `BRUN`)
De Tang Nano 20K heeft **twee opslagmedia** met precies dezelfde bestandsindeling:
1. **`SD` (`[SD-KAART D0..D3]`)**: Je fysieke **MicroSD-kaart**. Alles wat je hier opslaat blijft **permanent bewaard**, ook als je de stroom uitzet!
2. **`SDRAM` (`[SDRAM-DISK D0..D3]`)**: Een supersnelle **4 MB RAM-schijf** in het SDRAM-geheugen. Ideaal voor razendsnel testen (wordt gewist bij stroom uit).

Elke schijf is verdeeld in **4 virtuele drives (`DRIVE 0` t/m `DRIVE 3`)**. Op elke drive passen **15 bestanden (slots `#0` t/m `#14`)** van maximaal **4095 bytes (4 KB)** per slot, plus **submappen (`MKDIR` / `CD`)**.

#### 1. Navigeren tussen drives en mappen
- **`SD`** — Schakel naar de permanente MicroSD-kaart (`[SD-KAART]`).
- **`SDRAM`** — Schakel naar de tijdelijke SDRAM-Disk (`[SDRAM-DISK]`).
- **`DRIVE 0`** t/m **`DRIVE 3`** — Kies een van de 4 virtuele schijven (`D0`, `D1`, `D2`, `D3`).
- **`CAT`** (of **`DIR`**) — Toon de inhoudsopgave met slotnummers (`#0..#14`), bestandsnamen, groottes en submappen (`<MAP>`).
- **`MKDIR "GAMES"`** (of `MD "GAMES"`), **`CD "GAMES"`** en **`CD ..`** — Maak een submap aan, ga erin, of ga één niveau terug omhoog.
- **`DELETE "NAAM"`** (of `DEL "NAAM"`) — Wis een bestand of lege map.

#### 2. BASIC-programma's opslaan en laden (`$0800`)
- **`SAVE "MIJNGAME"`** — Slaat je huidige BASIC-programma op in het eerstvolgende vrije slot (of overschrijft `"MIJNGAME"` als die al bestaat).
- **`LOAD "MIJNGAME"`** — Laadt het BASIC-programma terug in het geheugen vanaf `$0800` (typ daarna `LIST` om te bekijken of `RUN` om te starten).

#### 3. 6502 Machinecode & Geheugenblokken opslaan, laden en starten
- **`BSAVE "NAAM", adres, lengte`** — Slaat een blok geheugen (max `4095` bytes) als binair bestand op. Voorbeeld: `BSAVE "FRUITY", $8000, 3590`.
- **`BLOAD "NAAM"`** (of `BLOAD "NAAM", adres`) — Laadt een binair bestand terug op zijn originele startadres (of op een zelfgekozen adres, bijv. `BLOAD "LEESMIJ", $6000`).
- **`BRUN "NAAM"`** (of kortweg **`BRUN NAAM`**) — Laadt een 6502-machinecodeprogramma vanaf SD in het geheugen én **start het direct (`CALL`)**!
  *(Zie **[Hoofdstuk 16](#hoofdstuk-16--complete-gids-voor-alle-17-sd-kaart-programmas--games-brun--load)** voor de complete handleiding van alle 17 meegeleverde programma's!)*

#### 4. Bestanden vanaf je Windows-pc naar de SD-kaart sturen (`sd_copy.py`)
Vanuit PowerShell op je pc kun je elk `.bas`, `.asm`, `.txt` of `.bin` bestand uit de map `sdcard/` met één commando rechtstreeks naar de SD-kaart in je Tang Nano 20K sturen:
```powershell
python sd_copy.py sdcard/FRUITY.asm --drive 0 --port COM6
python sd_copy.py sdcard/MON6502.asm --drive 0 --port COM6
python sd_copy.py sdcard --drive 0 --port COM6
```
`sd_copy.py` assembleert `.asm`-bestanden automatisch tot 6502-machinecode, stuurt de bytes naar het juiste SDRAM-adres (`$8000`, `$9000` of `$6000`) en voert `BSAVE` uit op de gekozen drive!

### Hoofdstuk 13: 🎨 Zelf Sprites & `128×128` BigSprites als `FUNC` Maken! (4 Manieren)
Je hebt **32 hardware-sprite vakjes (`SPRITE 0` t/m `SPRITE 31`)**, elk **16 × 16 = 256 pixels** (`RGB332`), én **2 Reuzen-Sprites (`BIGSPR 0` & `BIGSPR 1`)** van **128 × 128 = 16.384 pixels**! Kleur **`$E3` (`227`)** is transparant; **`$00` (`0`)** is dekkend zwart. Vakjes `16..31` zijn vrij voor je eigen `16×16` figuren (en je mag `0..15` ook overschrijven!).

- **🎯 Kortste 4-regelige Basis-Recept om maar ÉÉN eigen `FUNC`-Sprite, Tile of BigSprite op het scherm te zetten:**
  - **1 Eigen Sprite (`16×16`)**: `10 DO SPR_RAKET` → `20 MODE 1 : TARGET 1 : BIGSPR 0,0,0,0 : CLEAR 0` → `30 SPRITE 16, 312, 172` → `40 GOTO 40` (+ `FUNC SPR_RAKET ... ENDFUNC` eronder).
  - **1 Eigen Tile (`16×16`)**: `10 DO MIJN_TEGEL` → `20 MODE 1 : TARGET 1 : BIGSPR 0,0,0,0 : CLEAR $E3 : SCROLL 0,0` → `30 TILE 20, 11, 12` → `40 GOTO 40` (+ `FUNC MIJN_TEGEL ... ENDFUNC` eronder).
  - **1 Eigen BigSprite (`128×128`)**: `10 DO BIG_SMILEY` → `20 MODE 1 : TARGET 1 : CLEAR $E3` → `30 BIGSPR 0, 1, 256, 116` → `40 GOTO 40` (+ `FUNC BIG_SMILEY ... ENDFUNC` eronder; let op `CLEAR $E3` omdat `BIGSPR` achter het voorgrondcanvas ligt!).
  ```basic
  NEW
  10 DO SPR_RAKET
  20 MODE 1 : TARGET 1 : BIGSPR 0, 0, 0, 0 : CLEAR 0
  30 SPRITE 16, 312, 172
  40 GOTO 40
  1000 FUNC SPR_RAKET
  1010   DEFSPR 16
  1020   PIX "07E302E00DE304E00BE302E002FF02E00AE381E004FF81E009E381B606FF81B608E3"
  1030   PIX "88B6FF0F1F1F0FFFB608E388B6FF0F1F1F0FFFB608E381B606FF81B607E382E0B6"
  1040   PIX "06FF82B6E005E302E081B606FF83B6E0E004E302E008B602E003E303E002E30400"
  1050   PIX "02E303E002E302E003E304F003E302E007E384F0FCFCF00CE304FC0DE302FC07E3"
  1060 ENDFUNC
  RUN
  ```

1. **Manier 1 — Interactieve `16×16` Pixel-Art Sprite-Ontwerper in `MiniGPU_BASIC_voor_Dummies.html`**:
   - Open het boek met **`dummies_boek.bat`** en ga naar **Hoofdstuk 13**: teken met je muis op het 16×16 rooster (rechtermuisknop = `$E3` gum), kies een slot (`SPRITE 16..31` of `0..15`) en een **`Functie-naam (FUNC)`** (bijv. `SPR_RAKET`), en klik op **`➕ Plak FUNC in Mijn Programma`** (plakt het losse `FUNC ... ENDFUNC` blok direct in je huidige spel!), **`📋 Kopieer FUNC`**, **`▶️ Upload & Bestuur (WASD)!`** of **`⚡ Alleen Sprite Uploaden`**!
2. **Manier 2 — Sprites & 2-Frame Animatie als `FUNC` bouwen (`DEFSPR`, `PIX` & `DO`)**:
   - Zet elke sprite in een eigen **`FUNC naam ... ENDFUNC`** met **`DEFSPR slot`** (`0..31`) en **`PIX "hex..."`** (of met een `FOR`-lus en `POKE $A020, 9`), en roep hem bovenin je spel aan met **`DO naam`** (of **`DO naam, nieuw_slot`**):
   ```basic
   NEW
   10 REM --- Hoofdprogramma: laad onze sprites netjes op naam met DO! ---
   20 DO SPR_RAKET : DO MAAK_HAPPER
   30 MODE 1 : TARGET 0 : BIGSPR 0,0,0,0 : X = 312 : Y = 180 : T = 0
   40 CLEAR $E3 : SCROLL T * 2, 0 : RECT 10, 8, 620, 22, 0
   50 GTEXT 20, 15, "SPRITE FUNCS (DO)! WASD=VLIEG RAKET + 2-FRAME HAPPER!", $FC
   60 SPRITE 16, X, Y : SPRITE 17 + ((T / 6) & 1), (T * 3) % 600, 110
   70 FLIP : WAIT 1 : T = T + 1 : J = JOY
   80 IF J & 1 THEN Y = Y - 4
   90 IF J & 2 THEN Y = Y + 4
   100 IF J & 4 THEN X = X - 4
   110 IF J & 8 THEN X = X + 4
   120 GOTO 40
   1000 REM --- Los FUNC-blok 1: Pixel-Art Raket in slechts 4 PIX-regels! ---
   1010 FUNC SPR_RAKET
   1020   DEFSPR 16
   1030   PIX "07E302E00DE304E00BE302E002FF02E00AE381E004FF81E009E381B606FF81B608E3"
   1040   PIX "88B6FF0F1F1F0FFFB608E388B6FF0F1F1F0FFFB608E381B606FF81B607E382E0B6"
   1050   PIX "06FF82B6E005E302E081B606FF83B6E0E004E302E008B602E003E303E002E30400"
   1060   PIX "02E303E002E302E003E304F003E302E007E384F0FCFCF00CE304FC0DE302FC07E3"
   1070 ENDFUNC
   1100 REM --- Los FUNC-blok 2: 2-Frame Hap-Monster (SPRITE 17 & 18) ---
   1110 FUNC MAAK_HAPPER
   1120   FOR F = 0 TO 1 : POKE $A020, 9 : POKE $A020, 17 + F
   1130     FOR Y = 0 TO 15 : FOR X = 0 TO 15
   1140       D = (X - 7) * (X - 7) + (Y - 7) * (Y - 7) : C = $E3
   1150       IF D < 54 THEN C = $FC
   1160       IF (D >= 42) & (D < 54) THEN C = RGB(7, 5, 0)
   1170       IF (X = 7) & (Y = 3) THEN C = $FF
   1180       IF (X = 8) & (Y = 3) THEN C = 0
   1190       IF (F = 0) & (X > 7) & (ABS(Y - 7) <= (X - 7)) THEN C = $E3
   1200       IF (F = 1) & (X > 8) & (Y = 7) THEN C = 0
   1210       POKE $A020, C
   1220     NEXT X : NEXT Y
   1230   NEXT F
   1240 ENDFUNC
   RUN
   ```
3. **Manier 3 — Zelfstandig op je Tang Nano 20K tekenen met PixelStudio 6502 (`SD : BRUN SPREDIT`)**:
   - Teken met `WASD`/Pijltjes + `Spatie`, gum met `X` (`$E3`), kies kleur met `TAB`, gebruik `I` (pipet), `F` (vlakvulling), `M`/`V` (spiegelen), `R` (roteer 90°), `1..8` (slot), `G` (live animatie) en `ESC → 3` (opslaan op SD).
   - Jouw 8 getekende sprites staan na afloop direct klaar in BASIC als **`SPRITE 24` t/m `SPRITE 31`**!
4. **Manier 4 — Interactieve `128×128` BigSprite Teken-Editor, `FUNC`-Maker (`DEFBIG` + `PIX`) & PNG/JPG-Importer**:
   - Gebruik in Hoofdstuk 13 van **`MiniGPU_BASIC_voor_Dummies.html`** de nieuwe **🦖 Live `128×128` BigSprite Teken-Editor & PNG/JPG-Studio**: schilder zelf op het grote `128×128` canvas met **Kwast (`1px..10px`), Gum (`$E3`), Vlakvulling (Emmer), Lijn, Kader, Blok, Cirkel, Bol, Pipet en Undo**, kies een sjabloon (`UFO`, `Boss`, `Draak`, `Planeet`, `Smiley`, `Leeg`) óf laad een eigen **`.PNG` / `.JPG`** vanaf je pc om direct bij te tekenen en klik op **`➕ Plak FUNC in Mijn Programma`**!
   - Met **`DEFBIG slot`** (`0` of `1`) + **`PIX "hex..."`** in een `FUNC` vult de 6502 op volle snelheid alle 128 beeldlijnen (`Y = 0..127`), waarna je hem aanroept met `DO BIG_UFO` en toont/beweegt met `BIGSPR slot, 1, X, Y, spiegel`! (Handmatig per lijn kan ook via `POKE $A020, 22 : POKE $A020, slot : POKE $A020, Y`.)

---

## 🔟 Deel VI: Het Deel van de Tienen & Het Grote Spiekbriefje

### Hoofdstuk 14: Tien veelgemaakte fouten (en de snelle oplossing!)
1. **`?Syntax Error` bij een variabelenaam zoals `RX = 10`?** Gebruik altijd **1-letterige variabelen** (`A` t/m `Z`).
2. **`?Syntax Error` bij `KEY()`, `JOY()` of `AND` / `OR`?** Schrijf `KEY` en `JOY` zonder haakjes, en gebruik `&` (EN) en `|` (OF) met haakjes rond vergelijkingen: `IF (X > 10) & (Y < 200) THEN ...`.
3. **Geen tekstcursor meer zichtbaar na `MODE 1`?** Druk op **ESC** (of typ `MODE 0` + Enter) om direct terug te keren naar je BASIC-scherm met de 3D-planeten.
4. **Ik zie de wereldmap of planeten niet na `CLEAR 0`!** Kleur `0` is dekkend zwart; gebruik **`CLEAR $E3`** (of `CLEAR`) voor transparantie!
5. **Er zit een doorkijkgat in mijn felroze vorm!** `$E3` (`RGB(7,0,3)`) is transparant. Gebruik **`RGB(7, 0, 2)` (`$E2`)** voor dekkend felroze!
6. **Mijn animatie knippert!** Zet eenmalig `TARGET 0` vóór je game-loop en eindig elk frame met `FLIP : WAIT 1`.
7. **`BEEP 880, 150` duurt 1,5 seconde!** De duur bij `BEEP` en `WAIT` telt in stapjes van **10 ms** (`3` = 30 ms, `15` = 0,15 s, `100` = 1 s).
8. **`SOUND` klinkt zacht bij volume 15!** Volume van `SOUND ch, freq, vol` loopt van `0` t/m **`255`** (gebruik bijv. `180`..`220`).
9. **Ik zit nog op `[SDRAM-DISK]` i.p.v. mijn SD-kaart!** Typ **`SD`** (en eventueel `DRIVE 0`) om terug te schakelen naar `[SD-KAART D0]`.
10. **Oude regels staan nog door mijn nieuwe programma heen!** Begin een nieuw programma altijd met **`NEW`**.

### Hoofdstuk 15: Interactief W/A/S/D Schilderprogramma
```basic
NEW
10 MODE 1 : TARGET 1 : CLEAR 0 : X = 320 : Y = 180 : C = $FC : R = 6
20 RECT 0, 0, 640, 22, RGB(1, 1, 2)
30 GTEXT 12, 7, "WASD/PIJL=TEKEN  C=KLEUR  +/-=KWAST  X=WIS  ESC=STOP", $FF
40 DISK X, Y, R, C : WAIT 1 : J = JOY : K = KEY
50 IF (J & 1) | (K = 119) THEN IF Y > 28 THEN Y = Y - 3
60 IF (J & 2) | (K = 115) THEN IF Y < 352 THEN Y = Y + 3
70 IF (J & 4) | (K = 97)  THEN IF X > 8 THEN X = X - 3
80 IF (J & 8) | (K = 100) THEN IF X < 632 THEN X = X + 3
90 IF (K = 99) | (K = 67) THEN C = RND(255) + 1 : IF C = $E3 THEN C = $E2
100 IF K = 43 THEN IF R < 30 THEN R = R + 2 : BEEP 900, 2
110 IF K = 45 THEN IF R > 2  THEN R = R - 2 : BEEP 600, 2
120 IF (K = 120) | (K = 88) THEN RECT 0, 22, 640, 338, 0 : BEEP 440, 4
130 GOTO 40
RUN
```

---

## 📀 Deel VII: De Complete Gids voor Alle 17 SD-Kaart Programma's & Games

### Hoofdstuk 16: 📀 Hoe werken alle programma's op de SD-kaart (`sdcard/`)?
In de map **`sdcard/`** staat een compleet 6502 software-pakket klaar: van bestandsbeheer, office-apps en netwerktools tot een 6502 Machine Monitor, een 4-kanaals FruityLoops Chiptune-studio en volledige games!

> [!TIP]
> **Waarom kunnen alle programma's vanuit Midnight Commander (`BRUN MC`) worden gestart?**
> - **BASIC-programma's** staan op adres **`$0800`**.
> - **Midnight Commander (`MC.asm`)** draait speciaal hoog in het geheugen op **`$9000–$9FFF`**.
> - **Alle andere 6502-apps** (`READER`, `EXCEL`, `MON6502`, `FRUITY`, `WRITER`, `CALC`, `IMPRESS`, `SPREDIT`, `BROWSER`, `NETTERM`, `RFTS`, `PACMAN65`) draaien op **`$8000–$8FFF`** (`<= 4095` bytes).
> - Daardoor overschrijven ze `MC` niet! Als je in een app op **`ESC`** drukt om af te sluiten, kijkt de app automatisch of `MC` nog op `$9000` klaarstaat en springt dan direct terug naar je Midnight Commander-scherm (of naar BASIC als je hem los met `BRUN` had gestart).

#### Overzichtstabel van alle 17 Programma's in `sdcard/`

| Nr | Bestand | Startcommando | Adres | SD-Save Sectoren | Categorie & Beschrijving |
| :-: | :--- | :--- | :---: | :---: | :--- |
| **1** | **`MC.asm`** | `BRUN MC` | `$9000` | Catalogus `D0..D3` | **Midnight Commander 2.2** — Dual-Pane bestandsbeheer met pull-down menu's, mappen (`MD`), kopiëren, verplaatsen & starten |
| **2** | **`READER.asm`** | `BRUN READER` | `$8000` | Leest alle slots | **TextReader 6502** — Universele `.TXT`, gedetokeniseerde `.BAS`, `WRITER.DOC` én 16-byte Hex+ASCII viewer |
| **3** | **`EXCEL.asm`** | `BRUN EXCEL` | `$8000` | `$03E0–$03EF` | **MiniGPU Excel 6502** — 26×30 (`A1..Z30`) volledig scherm spreadsheet, gekoppeld aan BASIC-arrays `A(1)..Z(30)`! |
| **4** | **`MON6502.asm`** | `BRUN MON6502` | `$8000` | `$03F9` | **6502 Machine Monitor** — Hex-editor met tijdschrift-checksums (`:XX`), live Disassembler, Line-Assembler & Single-Step |
| **5** | **`FRUITY.asm`** | `BRUN FRUITY` | `$8000` | `$03FA` | **FruityLoops 6502** — 4-kanaals Chiptune Step-Sequencer (16 stappen), Drum-synth, 2-octaaf Piano Roll & 4 VU-meters |
| **6** | **`WRITER.asm`** | `BRUN WRITER` | `$8000` | `$03F8–$03FB` | **LibreWriter 6502** — WYSIWYG tekstverwerker (16×70) met 5 regelstijlen en kleurenthema's |
| **7** | **`CALC.asm`** | `BRUN CALC` | `$8000` | `$03FC–$03FE` | **LibreCalc 6502** — 5×10 rekenblad met formules (`=SUM`, `=AVG`) én een live meeschalend Staafdiagram! |
| **8** | **`IMPRESS.asm`** | `BRUN IMPRESS` | `$8000` | Werkgeheugen `$7D00` | **LibreImpress & Draw 6502** — Presentatiesoftware (4 dia's, AutoShow) + interactieve Vector-Tekenstudio (max 32 vormen) |
| **9** | **`SPREDIT.asm`** | `BRUN SPREDIT` | `$8000` | `$03F0–$03F3` | **PixelStudio 6502** — 16×16 Hardware Sprite & Animatie-Editor (vult direct BASIC `SPRITE 24..31`!) |
| **10** | **`BROWSER.asm`** | `BRUN BROWSER` | `$8000` | Live via W5500 LAN | **WebNavigator 1.0** — Echte 6502 TCP HTTP/1.0 browser voor Powerbaas Slimme Meter JSON + KAKU-schakelaars + `view-source:` |
| **11** | **`NETTERM.asm`** | `BRUN NETTERM` | `$8000` | Live via W5500 LAN | **W5500 NetTerm 1.2** — TCP Telnet-server op `192.168.178.200:23`, Retro 6502 BBS, PING-tool & CRT-thema's |
| **12** | **`RFTS.asm`** | `BRUN RFTS` | `$8000` | `$03EC` | **Reach for the Stars (1983)** — Galactisch 4X strategiespel met 16 sterrenstelsels, kolonisatie, tech & Xenon AI |
| **13** | **`PACMAN65.asm`** | `BRUN PACMAN65` | `$8000` | High-score in RAM | **Pac-Man 6502** — 60 FPS arcade Pac-Man in pure 6502-machinecode met 4 spoken, krachtpillen, fruit & geluid |
| **14** | **`ASM6502.asm`** | `BRUN ASM6502` | `$8000` | — | **6502 Copper/Regenboog-Demo** — Kort leervoorbeeld: tekent razendsnel 32 gekleurde GPU-balken via `$A020` |
| **15** | **`STER6502.asm`** | `BRUN STER6502` | `$8000` | — | **6502 Neon Cirkels-Demo** — Kort leervoorbeeld: tekent 25 concentrische neon-ringen vanuit `(320, 180)` |
| **16** | **`PACMAN.bas`** | `LOAD "PACMAN"` | `$0800` | Standaard BASIC | **Pac-Man in BASIC** — Volledig leesbare en aanpasbare BASIC-versie van Pac-Man (bekijk met `LIST` of in `READER`) |
| **17** | **`SDRAM2S.bas`** | `LOAD "SDRAM2S"`| `$0800` | Standaard BASIC | **SDRAM Array & 2-Schermen Demo** — Demonstreert de 26 grote SDRAM-arrays `A(0)..Z(32767)` met stuiterende vormen |
| **+** | **`LEESMIJ.txt`** | Open in `READER` | `$6000` | Tekstslot op SD | **Nederlandstalige Handleiding** — Standaard tekstbestand dat automatisch in `READER` wordt geopend |

---

#### 1. 🗂️ `MC.asm` — Midnight Commander 2.2 (`BRUN MC`)
Jouw grafische startcentrum en bestandsbeheerder met **twee panelen naast elkaar** (links en rechts kunnen elk op een eigen drive `D0..D3` of submap staan!):
- **Navigeren**: **`Pijltjes Omhoog/Omlaag`** kiest een bestand; **`TAB`** wisselt tussen het linker- en rechterpaneel; **`S`** ruilt links en rechts om.
- **Bestand of Map openen (`Enter` of `3`)**:
  - Op een **`.ASM`** programma (`ASM $8000`): laadt en start het programma direct!
  - Op een **`.BAS`** programma (`BAS $0800`): laadt het BASIC-programma en voert direct `RUN` uit!
  - Op een **`.IMG`** plaatje (`IMG $5000`, zoals `TANGART`): laadt het plaatje in `$5000`, zoekt automatisch **`VIEWER`** op Drive `D0` en toont het plaatje direct op het scherm (druk in `VIEWER` op `Q` om weer terug te keren in `MC`)!
  - Op een **`.TXT`** bestand (`TXT $6000`, zoals `LEESMIJ`): zoekt automatisch **`READER`** op Drive `D0` en opent het tekstbestand daarin (druk op `Q` om terug te keren in `MC`)!
  - Op een **`<MAP>`**: stapt de submap binnen (kies `Backspace` om terug omhoog te gaan).
- **PC-Afstandsbediening (`basic_terminal.py` / `terminal.bat`)**: Naast het toetsenbord kun je `MC`, `VIEWER`, `READER`, `EXCEL`, `FRUITY` en `MON6502` nu ook volledig met de muis besturen via de knoppen rechts in de **MiniGPU BASIC-Terminal & MC Control Deck GUI**!
- **Functietoetsen & Menu's**:
  - **`1` of `Alt`**: Opent de **Pull-Down Menu's** (*Left*, *File*, *Command*, *Options*, *Right*) — navigeer met pijltjes en druk op `Enter` (of `Spatie` om te sluiten).
  - **`2` (`F2`)**: Wissel van Drive (`D0` → `D1` → `D2` → `D3`).
  - **`4` (`F4`)**: **Hernoem** het geselecteerde bestand of map (typ de nieuwe naam + `Enter`).
  - **`5` (`F5`)**: **Kopieer** het geselecteerde bestand van het actieve paneel naar de drive/map in het andere paneel!
  - **`6` (`F6`)**: **Verplaats** het bestand naar het andere paneel.
  - **`7` (`F7`)**: **Maak Map (`MkDir`)** aan op de huidige schijf.
  - **`8` (`F8`)**: **Wis (`Del`)** het geselecteerde bestand of lege map.
  - **`9`**: Wissel achtergrond tussen klassiek Midnight-Commander blauw en **transparant (`$E3`)** (met doorkijk naar de wereldmap!).
  - **`0` of `ESC`**: Verlaat Midnight Commander en keer terug naar BASIC.

---

#### 2. 📖 `READER.asm` — TextReader 6502 (`BRUN READER`)
Universele document-, broncode- en hex-viewer op `640×360`:
- **4 Bestandsformaten in één app**:
  1. **Platte tekst (`.TXT` op `$6000`, zoals `LEESMIJ`)**: Automatische woordafbreking op 64 kolommen, regelnummers en schuifbalk.
  2. **MiniGPU-BASIC programma's (`.BAS` op `$0800`)**: Worden **live gedetokeniseerd** naar leesbare BASIC-broncode met alle sleutelwoorden (`PRINT`, `FOR`, `RECT`, `FUNC`...)!
  3. **LibreWriter documenten (`WRITER.DOC`)**: Druk op **`L`** om je opgeslagen LibreWriter-document direct vanaf SD-sector `$03F8` te lezen.
  4. **16-Byte Hex + ASCII Dump (`.ASM` / `.BIN`)**: Druk op **`H`** om elk bestand byte-voor-byte in hexadecimaal + ASCII te inspecteren!
- **Besturing**:
  - **`O` of `Enter`**: Open de grafische **SD-Bestandskiezer** (druk in het venster op `1..4` voor Drive `D0..D3`, pijltjes + `Enter` om te openen, of **`Spatie`** om het venster schoon te sluiten).
  - **`Pijltjes Omhoog/Omlaag`** (of `W`/`S`): Scroll 1 regel omhoog of omlaag.
  - **`Pijltjes Links/Rechts`** (of `A`/`D` of **`Spatie`**): Pagina omhoog (PageUp) / Pagina omlaag (PageDown).
  - **`T` en `E`**: Spring direct naar het begin (**T**op) of einde (**E**nd) van het document.
  - **`N`**: Zet de kolom met regelnummers (`001:`) aan of uit.
  - **`H`**: Schakel tussen Tekst-weergave en **Hex+ASCII Dump-modus**.
  - **`C` of `~`**: Wissel tussen 4 kleurthema's (*Klassiek Blauw*, *Sepia Perkament*, *Groene CRT-Monitor*, *Nachtmodus*).
  - **`D`**: Laad de ingebouwde Nederlandstalige handleiding.
  - **`ESC` of `Q`**: Sluit af naar `MC` of BASIC.

---

#### 3. 📊 `EXCEL.asm` — MiniGPU Excel 6502 (`BRUN EXCEL`)
Volledig scherm (`640×360`) SDRAM-spreadsheet dat rechtstreeks samenwerkt met je BASIC-programma's:
- **26 Kolommen (`A` t/m `Z`) × 30 Rijen (`01` t/m `30`) = 780 Cellen**: Opgeslagen in de 64 KB Hardware SDRAM Array-banken (`$A012–$A015`, Banken `32..57`). Op het scherm zie je een venster van 7 kolommen × 11 rijen dat vloeiend over alle 780 cellen scrolt.
- **Unieke Live Koppeling met BASIC-arrays `A(1)..Z(30)`**:
  - Elke numerieke waarde in kolom **`A..Z`**, rij **`1..30`** staat op exact dezelfde geheugenplek als de BASIC-array **`A(1)..Z(30)`**!
  - Zet je in `EXCEL` getallen of formules in kolom `B`, verlaat je `EXCEL` met `ESC`, en typ je in BASIC `PRINT B(2), B(8)`, dan heb je direct toegang tot alle uitgerekende resultaten (bijv. om ze in BASIC te plotten met `RECT` of `LINE`)!
- **Ondersteunde Formules (Nederlands én Engels)**:
  - Rekenen met cellen en getallen: `=A1+B1`, `=B2-C2`, `=B3*12`, `=D4/10`
  - Bereikfuncties: `=SUM(B2:B7)` of `=SOM(B2:B7)`, `=AVG(B2:B7)` of `=GEM(B2:B7)`, `=MIN(B2:B7)`, `=MAX(B2:B7)`
- **Besturing**:
  - **`Pijltjestoetsen`**: Navigeer en scroll door `A1..Z30`.
  - **`Enter` of `=`**: Bewerk de huidige cel (typ een getal, label of formule beginnend met `=` en druk op `Enter`; `ESC` annuleert het typen).
  - **`C`, `Backspace` of `Delete`**: Maak de huidige cel leeg.
  - **`H`**: Herbereken alle formules in het werkblad.
  - **`ESC`**: Open het **Excel Menu**:
    - **`1`**: Nieuw leeg werkblad (`A1..Z30` wissen)
    - **`2`**: Laad het ingebouwde **Demo Huishoudboekje & Kwartaaloverzicht**
    - **`3`**: Sla het werkblad op de SD-kaart op (sectoren `$03E0..$03EF`)
    - **`4`**: Laad het werkblad vanaf de SD-kaart
    - **`Spatie`**: Sluit het menu zonder restjes • **`ESC`/`Q`**: Terug naar BASIC / `MC`.

---

#### 4. 🛠️ `MON6502.asm` — 6502 Machine Monitor, Disassembler & Tijdschrift Hex-Editor (`BRUN MON6502`)
Ontwikkel, inspecteer en assembleer echte 6502-machinecode rechtstreeks op je Tang Nano 20K:
- **4 Schermpanelen**:
  1. **Hex + ASCII Geheugendump (links, 16 rijen × 8 bytes)**: Toont achter elke regel van 8 bytes automatisch een **8-bit Tijdschrift-Checksum (`:XX`)** (`(adres_lo + adres_hi + b0..b7) & $FF`). Ideaal om machinecode-listings uit jaren-'80 tijdschriften (*Compute!'s Gazette*, *Elektuur*, *Kim-1/C64 boeken*) foutloos in te kloppen!
  2. **Live 6502 Disassembler (rechtsboven, 16 instructies)**: Vertaalt de bytes vanaf je cursoradres direct naar leesbare 6502-instructies (`LDA #$FC`, `STA $A020`, `BNE $7003`, `LDA ($60),Y`...).
  3. **Interactieve Line-Assembler & Adresbalk (midden)**: Typ direct een 6502-instructie in; de monitor assembleert hem naar de juiste opcode + operandbytes (inclusief relatieve branch-afstanden voor `BNE`, `BEQ`, `BCC`, `BCS`, `BMI`, `BPL`!).
  4. **CPU Register & Vlaggen Dashboard (rechtsonder)**: Toont `PC`, `A`, `X`, `Y`, `SP`, de 8 processorvlaggen `NV-BDIZC` en de 16-bit som-checksum over `$7000–$707F`.
- **Besturing**:
  - **`Pijltjestoetsen`** (en **`TAB`** om tussen hoog en laag hex-nibble te wisselen): Beweeg door het hele 64 KB adresbereik (`$0000–$FFFF`).
  - **`0..9` en `A..F`**: Overschrijf direct het hex-getal onder de cursor (de cursor schuift automatisch door naar de volgende byte!).
  - **`I`**: Start de **Interactieve 6502 Line-Assembler** op het huidige adres! Typ bijv. `LDA #$1F` + `Enter`, daarna `STA $A020` + `Enter` (hij stapt automatisch naar het volgende instructie-adres; druk op `Enter` op een lege regel of `ESC` om te stoppen).
  - **`G`**: **Goto adres** — typ een 4-cijferig hex-adres (bijv. `7000` of `E000`) + `Enter`.
  - **`R`**: **Run (`JSR`)** — voert de machinecode op het cursoradres echt uit op de 27 MHz 6502 CPU! Zodra jouw routine eindigt met `RTS` (`$60`), vangt de monitor de nieuwe waarden van `A`, `X`, `Y` en de processorvlaggen op en toont ze in het dashboard!
  - **`S`**: **Single-Step** — voert veilig 1 instructie op `PC` stap-voor-stap uit en werkt `PC`, `A`, `X`, `Y` en `NV-BDIZC` bij.
  - **`F`**: Vul het werkgeheugen `$7000–$707F` met `$00` (`BRK`).
  - **`1`, `2`, `3`**: Laad 1 van de **3 ingebouwde Tijdschrift-Demo's** op `$7000` (druk daarna op **`R`** om hem uit te voeren!):
    - **`1`**: *MiniGPU Regenboog-Balk* (tekent 64 gekleurde GPU-lijnen midden in beeld)
    - **`2`**: *4-Stemmig Chiptune Akkoord* (stuurt een C-majeur akkoord naar `audio_synth`)
    - **`3`**: *Geheugen-Vuller* (vult `$7100–$71FF` met `00..FF` en zet `X=$00, Y=$FF`)
  - **`ESC`**: Open het **Monitor Menu** (met `1..3` Demo's, `4` Wis `$7000`, `5` Sla `$7000–$71FF` op naar SD-sector `$03F9`, `6` Laad vanaf SD, **`Spatie`** sluit venster schoon, **`ESC`/`Q`** sluit af).

---

#### 5. 🎵 `FRUITY.asm` — MiniGPU FruityLoops 6502 (`BRUN FRUITY`)
Bouw je eigen chiptune-beats en melodieën met deze 4-kanaals Step-Sequencer, Drum-Synthesizer & Piano Roll:
- **De 4 Hardware-Sporen (`48 kHz` via MiniGPU `CMD 16`)**:
  - **`0:LEAD 50%`** *(Cyaan)*: 50% Vierkantgolf voor heldere hoofdmelodieën (`C2..C5`).
  - **`1:PULS 25%`** *(Neon-Roze `$EB`)*: 25% Pulsgolf voor C64/NES-achtige harmonieën en snelle arpeggio's.
  - **`2:BASS TRI`** *(Groen)*: Driehoeksgolf voor diepe, warme baslijnen.
  - **`3:DRUM NLS`** *(Geel)*: 15-bit LFSR Noise Drum-Synthesizer met `100 Hz` pitch-sweep en volume-envelopes:
    - **`KCK`** = Basdrum / Kick (snelle pitch-drop van hoog naar diep laag)
    - **`SNR`** = Snaredrum (midden-frequentie ruis met punch)
    - **`HAT`** = Gesloten Hi-Hat (korte, felle hoge tik)
    - **`OPN`** = Open Hi-Hat / Cymbal (lang uitklinkende hoge ruis)
- **Besturing**:
  - **`Spatie` of `P`**: Start / Pauzeer de sequencer (`[PLAYING]` ↔ `[STOPPED]`).
  - **`Pijltjestoetsen`**: Beweeg de gele cursor door de 4 sporen (omhoog/omlaag) en 16 stappen `01..16` (links/rechts).
  - **`Enter`**: Plaats een noot op de huidige pad (op spoor `3:DRUM` wisselt `Enter` tussen `KCK` → `SNR` → `HAT` → `OPN` → `---`).
  - **`0`, `Backspace` of `Delete`**: Wis de huidige stap (`---`).
  - **2-Octaaf Toetsenbord-Piano** (speelt direct de noot én vult hem in op het geselecteerde spoor!):
    - **Laag octaaf (`C..B`)**: `Z` `S` `X` `D` `C` `V` `G` `B` `H` `N` `J` `M`
    - **Hoog octaaf (`C..B`)**: `Q` `2` `W` `3` `E` `R` `5` `T` `6` `Y` `7` `U`
    - **`<` (of `,`) en `>` (of `.`)**: Octaaf omlaag / omhoog (`OCT:2` t/m `OCT:4`).
  - **`M`**: **Mute / Unmute** het geselecteerde kanaal (`ON [M]` ↔ `MUTE [M]`).
  - **`[` en `]`** (of **`-` en `+`**): Verander het tempo (`SPD`, lagere waarde = sneller).
  - **`1`, `2`, `3`**: Wissel direct tussen de **3 ingebouwde Chiptune Demo-Songs**:
    - **`1`**: *Song 1: 8-Bit Arcade Theme*
    - **`2`**: *Song 2: Demoscene Arpeggio*
    - **`3`**: *Song 3: Fruity Electro Beat*
  - **`ESC`**: Open het **FruityLoops Menu** (`1..3` Demo-songs, `4`/`N` Nieuw leeg patroon, `5`/`S` Sla patroon op naar SD-sector `$03FA`, `6`/`L` Laad patroon van SD, **`Spatie`** sluit venster schoon, **`ESC`/`Q`** stopt geluid en sluit af).

---

#### 6. 📝 `WRITER.asm` — LibreWriter 6502 (`BRUN WRITER`)
Grafische WYSIWYG-tekstverwerker (16 regels × 70 tekens per regel op `$7000–$77FF`):
- **Typen & Navigeren**: Typ direct letters, cijfers en leestekens; gebruik **`Pijltjestoetsen`** om door de pagina te wandelen, **`Enter`** voor de volgende regel, **`Backspace`** om een teken te wissen en **`\`** om de huidige regel in één keer leeg te maken.
- **Opmaak & Thema's**:
  - **`TAB` of `` ` ``**: Wissel de opmaakstijl van de huidige regel tussen **`NORMAAL`**, **`KOPTEKST`** (geel/groot accent), **`BELANGRIJK`** (rood kader), **`NOTITIE`** (cyaan) en **`TITELBALK`** (volle achtergrondbalk!).
  - **`~`**: Wissel het kleurenthema van het papier (Donker, Klassiek Blauw, Wit/Papier, Groene Terminal).
- **`ESC`-Menu**: Druk op **`ESC`** voor **`[1] Nieuw`**, **`[2] Demo`**, **`[3] Opslaan op SD`** (sectoren `$03F8..$03FB` — ook direct te openen in `READER` met toets `L`!), **`[4] Laden van SD`**, **`[5] Stijl`**, **`[6] Thema`**, **`[Spatie] Verder typen`** of nogmaals **`[ESC]`** om af te sluiten.

---

#### 7. 📈 `CALC.asm` — LibreCalc 6502 met Live Staafgrafiek (`BRUN CALC`)
Compacte 5×10 spreadsheet (`A1..E10` op `$7800–$7CFF`) links met een **automatisch schalend Staafdiagram** rechts:
- **Besturing**:
  - **`Pijltjes` / `WASD`**: Kies een cel in kolom `A..E`, rij `1..10`.
  - **`Enter` of `=`**: Voer een tekstlabel, getal of formule in (`=B2+C2`, `=D2*2`, `=SUM(B2:B7)`, `=AVG(B2:B7)`).
  - **`TAB` of `G`**: Kies welke kolom (`B`, `C`, `D` of `E`) live als gekleurde staafgrafiek in het rechterpaneel wordt getekend!
  - **`C`**: Wis de geselecteerde cel.
  - **`ESC`**: Open het menu (`[1] Nieuw`, `[2] Demo`, `[3] Opslaan op SD` op sectoren `$03FC..$03FE`, `[4] Laden van SD`, `[5] Grafiek-kolom`, `[Spatie] Verder`, `[ESC] Sluiten`).

---

#### 8. 📽️ `IMPRESS.asm` — LibreImpress & Draw 6502 (`BRUN IMPRESS`)
Presentatie-suite én interactieve vector-tekenstudio in één:
- **Presentaties & AutoShow**:
  - **`1`, `2`, `3`, `4`** (of **`[` en `]`**): Wissel tussen de 4 dia's (*1: Overzicht*, *2: Hardware*, *3: Benchmark*, *4: Tekenbord*).
  - **`P`**: Start of stop de **Automatische Diavoorstelling** (wisselt elke paar seconden automatisch naar de volgende dia!).
- **Vector Tekenstudio (tot 32 vector-objecten op `$7D00–$7EFF`)**:
  - Beweeg het kruisvizier met de **`Pijltjestoetsen`** over de dia en druk op:
    - **`R`**: Plaats een gevulde **R**echthoek
    - **`C`**: Plaats een gevulde **C**irkel / Bol (`DISK`)
    - **`D`**: Plaats een gevulde **D**riehoek (`FTRI`)
    - **`L`**: Plaats een **L**ijn
    - **`K`**: Kies de volgende tekenkleur
  - **`ESC`-Menu**: **`[Z]`** = Undo (verwijder laatst geplaatste vorm), **`[X]`** = Wis alle eigen vormen, **`[D]`** = Plaats demo-kunstwerk, **`[Spatie]`** = Sluit menu, **`[ESC/Q]`** = Sluiten.

---

#### 9. 🎨 `SPREDIT.asm` — PixelStudio 6502 Sprite- & Animatie-Editor (`BRUN SPREDIT`)
Teken je eigen `16×16` hardware-sprites met directe live-preview op het scherm:
- **Hoe het werkt**: Je bewerkt 8 sprite-slots tegelijk (in RAM op `$6000–$67FF`), die **realtime** naar hardware-slots **`SPRITE 24` t/m `SPRITE 31`** worden gestuurd. Verlaat je `SPREDIT` naar BASIC, dan kun je je getekende figuren dus meteen in BASIC oproepen met `SPRITE 24, X, Y` t/m `SPRITE 31, X, Y`!
- **Besturing**:
  - **`Pijltjes` / `WASD`**: Beweeg over het `16×16` vergrote tekenrooster.
  - **`Spatie` of `Enter`**: Kleur de pixel in met de huidige kwastkleur.
  - **`X` of `Backspace`**: Gum de pixel naar **transparant (`$E3`, gemarkeerd met een `T` / stipje)**.
  - **`TAB` of `C`** (of **`Q`/`E`**): Kies een van de 16 kleuren onderaan.
  - **`1` t/m `8`**: Wissel tussen de 8 sprite-slots (`SPRITE 24..31`) om meer-frame animaties te tekenen!
  - **Gereedschappen**: **`I`** = Pipet (neem kleur onder cursor over), **`F`** = Vlakvulling (emmer), **`M`** = Spiegel horizontaal, **`V`** = Spiegel verticaal, **`R`** = Roteer 90 graden met de klok mee, **`G`** = Zet de wandelende **Live Animatie-Preview** aan/uit!
  - **`ESC`-Menu**: Kopieer/Plak sprites tussen slots, wis een sprite, of sla al je 8 sprites op naar SD-sectoren `$03F0..$03F3` (`[3] Opslaan` / `[4] Laden`).

---

#### 10. 🌐 `BROWSER.asm` — MiniGPU WebNavigator 1.0 & Powerbaas Dashboard (`BRUN BROWSER`)
Echte 6502 HTTP/1.0 webbrowser die via de **W5500 Ethernet-chip** (`$A030/$A031`) communiceert met je lokale netwerk:
- **Wat het doet**: Stuurt een echte TCP `GET /json HTTP/1.0` aanvraag naar `192.168.178.87` (Powerbaas P1 Energiemeter), parseert live de JSON-velden in 6502-assembly en tekent een grafisch energie-dashboard met:
  - **Actueel Netverbruik of Zon-Overschot** in Watt (groene of rode hero-kaart)
  - **Weer Vandaag & Zonuren-verwachting**
  - **Slimme Meterstanden** (Dal, Piek, Teruglevering in kWh & Gas in m³)
  - **3-Fase Inzicht** (`L1/L2/L3` Spanning, Stroom en Vermogen)
- **Besturing**:
  - **`R` of `Spatie`**: Ververs de pagina (stuurt een nieuw HTTP GET verzoek).
  - **`1`, `2`, `3`**: Schakel **KlikAanKlikUit (KAKU) slimme schakelaars #1, #2 of #3** direct aan of uit via een HTTP-request (`/handle/switch/on/...`)!
  - **`TAB`**: Schakel tussen het **Grafische Dashboard** en de **`view-source:` modus** waarin je de ruwe HTTP/1.0-headers en JSON-broncode bekijkt!
  - **`ESC`**: Sluit af naar `MC` of BASIC.

---

#### 11. 📡 `NETTERM.asm` — W5500 Telnet Server, Retro BBS & Chat-Terminal (`BRUN NETTERM`)
Maakt van je Tang Nano 20K een echte **TCP/IP Telnet-server op poort 23** (`192.168.178.200:23`):
- **Inloggen vanaf je pc**: Terwijl `NETTERM` op de Tang Nano 20K draait, kun je vanaf je pc verbinding maken via `python telnet_6502.py` (of `telnet 192.168.178.200 23`). Alles wat je op de pc typt verschijnt live op het HDMI-scherm, en alles wat je op de Tang Nano 20K typt wordt teruggestuurd naar de pc!
- **Ingebouwde Commando's (typ achter `NET> ` + `Enter`)**:
  - **`HELP`**: Toon alle commando's.
  - **`BBS`**: Start het ingebouwde **DONDERDAG 6502 Retro Bulletin Board System**.
  - **`PING`**: Voer een LAN-ping uit naar `192.168.178.87`.
  - **`STATUS`**: Toon de live W5500 Socket 0, IP-, MAC- en TX/RX-status.
  - **`W5500`**: Toon het aansluitschema (FPGA-pinnen `25..29`).
  - **`COLOR` of `TAB`**: Wissel tussen 4 retro CRT-fosforkleuren (Groen, Amber, Cyaan, Wit).
  - **`CLS`**: Wis het terminalscherm • **`EXIT` of `ESC`**: Open menu / sluit af.

---

#### 12. 🚀 `RFTS.asm` — Reach for the Stars (1983) Galactic 4X Strategy (`BRUN RFTS`)
Verover het melkwegstelsel in dit turn-based 4X ruimte-strategiespel op `640×360`:
- **Doel van het spel**: Je begint op thuisplaneet **SOL** met een startvloot en Credits. Verken en koloniseer de **16 sterrenstelsels** (*Centauri*, *Sirius*, *Vega*, *Rigel*, *Altair*, ...), bouw je economie op en versla het vijandige **Xenon Imperium** (dat vanuit *Xenos* ook nieuwe werelden verovert!).
- **Besturing**:
  - **`Pijltjestoetsen` of `TAB`**: Beweeg de cursor over de 16 sterren op de sterrenkaart (rechts zie je van het geselecteerde stelsel de eigenaar, het aantal Schepen, Industrie `IND` en Afweer `DEF`).
  - **`1` of `B`**: **Bouw Sterrenschip** op een eigen planeet (`15 Credits`).
  - **`2` of `I`**: **Bouw Planetaire Industrie (`IND +1`)** — levert elk nieuw jaar extra Credits op (`25 Credits`).
  - **`3` of `D`**: **Bouw Planetaire Raketafweer (`DEF +1`)** — beschermt je kolonie tegen Xenon-aanvallen (`20 Credits`).
  - **`4` of `T`**: **Upgrade Tech-Level** — maakt je schepen en wapens sterker in ruimteslagen (`50 Credits`).
  - **`5` of `Spatie`**: **Stuur Vloot**:
    1. Selecteer eerst een eigen planeet met minimaal 2 schepen en druk op **`5` / `Spatie`**.
    2. Kies met de pijltjes de doelster waar je naartoe wilt vliegen.
    3. Druk nogmaals op **`5` / `Spatie`** om de vloot te lanceren en het stelsel te koloniseren of aan te vallen!
  - **`6` of `Enter`**: **Volgend Jaar (Einde Beurt)** — int inkomsten van al je kolonies en laat de Xenon AI zijn zet doen.
  - **`ESC`**: Open het **Campagne-Menu** (`1/N` = Nieuw Melkwegstelsel, `2/S` = Spel opslaan op SD-sector `$03EC`, `3/L` = Spel laden vanaf SD, `4` = Terug naar kaart, `0/ESC` = Stoppen).

---

#### 13. 🍒 `PACMAN65.asm` — 60 FPS Arcade Pac-Man in 6502 Machinecode (`BRUN PACMAN65`)
De klassieke arcadehal-game op volle 60 beelden per seconde in pure 6502-assembly:
- **Spelregels**: Eet alle gele puntjes in het doolhof terwijl je de 4 spoken ontwijkt! Pak een van de **4 grote knipperende Krachtpillen** in de hoeken om de spoken blauw en kwetsbaar te maken (`200` punten per opgegeten spook!), pak de bonus-kers in het midden en gebruik de zij-tunnels om snel naar de overkant van het scherm te warpen.
- **Besturing**:
  - **`WASD` of `Pijltjestoetsen`**: Stuur Pac-Man (je kunt een bocht alvast ingedrukt houden vlak voor een kruispunt!).
  - **`Spatie`**: Start een nieuw potje na *GAME OVER*.
  - **`ESC` of `Q`**: Keer direct terug naar `MC` of BASIC.

---

#### 14. 🖼️ `VIEWER.asm` — MiniGPU ImageViewer & Art Gallery 6502 (`BRUN VIEWER`)
Een veelzijdige 6502 plaatjes-kijker, sprite-inspecteur en kunstgalerij met **5 weergavemodi**, Zoom, Pan en Automatische Diashow:
- **De 5 Galerij-Modi (kies met toets `1` t/m `5` of `[` en `]`)**:
  1. **`[1] SD / RLE Pixel-Art Plaatjes (`$5000`)`**: Toont een `120×80` Scanline-RLE plaatje in `"MIMG"`-formaat (standaard het ingebouwde **Cyber-Sunset & Retro Island** kunstwerk, of elk `.IMG` / `.PNG` / `.JPG` plaatje dat je vanaf de SD-kaart opent!).
  2. **`[2] Scifi-Schilderij "Ruimtehaven Tang-20K"`**: Hardware-versnelde vector-kunstgalerij met geringde gasplaneet, maan, 3D-bergketen en ruimteschip op een landingsplatform.
  3. **`[3] Alle 32 Hardware Sprites (`16×16`) + 2× `128×128` BigSprites`**: Toont links alle 32 `16×16` sprites (`00..31`) en rechts `BIGSPR 0` en `BIGSPR 1` via twee hardware-transparante (`$E3`) kijkvensters! Druk op **`M`** om de BigSprites live te spiegelen, of op **`L`** om je eigen getekende `SPREDIT`-sprites vanaf SD-sector `$03F0` naar slots `24..31` te laden!
  4. **`[4] 64×64 Wereldmap & Tegel-Atlas`**: Maakt het voorgrond-canvas transparant (`$E3`) zodat je met de **`Pijltjestoetsen` / `WASD`** vrij over de hele `1024×1024` hardware RPG-wereldmap kunt vliegen.
  5. **`[5] 256-Kleuren RGB332 Master Palet & Kleuren-Kiezer`**: Toont alle 256 hardware-kleuren in een `16×16` rooster. Beweeg het witte selectiekader met de **`Pijltjes` / `WASD`** en lees rechts direct de **HEX-code (`$00..$FF`)** en **`RGB(r,g,b)`-formule** af voor je eigen BASIC- en ASM-programma's!
- **Overige Sneltoetsen in `VIEWER`**:
  - **`O` of `Enter`**: Open de grafische **SD-Kaart Plaatjes Kiezer** (wissel met **`1..4`** tussen Drive `D0..D3` en open bijvoorbeeld `TANGART`!).
  - **`Z` of `+` / `-`**: Zoom in/uit (`1x` = `120×80`, `2x` = `240×160`, `3x` = `360×240`).
  - **`Pijltjes` / `WASD`**: Verschuif (Pan) het ingezoomde plaatje, scroll over de wereldmap of kies een kleur in het palet.
  - **`P` of `Spatie`**: Start/stop de **Automatische Diashow** (wisselt elke paar seconden automatisch naar de volgende galerij!).
  - **`C`**: Wissel tussen **4 schilderijlijst- & achtergrondthema's** (Cyaan, Goud, Neon-Roze, Wit).
  - **`F`**: Zet **Volledig Scherm** aan/uit (verbergt de titel- en statusbalk).
  - **`R`**: Herstel het ingebouwde *Cyber-Sunset* kunstwerk • **`ESC`**: Open het popup-menu (`Spatie` = sluit menu, `ESC/Q` = afsluiten).
- **Tip — Eigen `.PNG` / `.JPG` foto's op de SD-kaart zetten**: Start op je pc **`sd_uploader.bat`** (of `python sd_gui.py`), klik op **📄 Los Bestand...** en kies een willekeurig `.png`, `.jpg`, `.bmp` of `.img` plaatje. De uploader zet de afbeelding automatisch om naar het gecomprimeerde `120×80` `"MIMG"` RLE-formaat (`<= 4095` bytes op adres `$5000`) en slaat hem op je SD-kaart op!

---

#### 15. ⚡ `ASM6502.asm`, `STER6502.asm`, `PACMAN.bas` & `SDRAM2S.bas` — Demo's & Leervoorbeelden
- **`BRUN ASM6502`** & **`BRUN STER6502`**: Twee korte, superhelder gedocumenteerde 6502-assembly programma's (`sdcard/ASM6502.asm` en `sdcard/STER6502.asm`). Ze laten zien hoe je in minder dan 60 regels 6502-code rechtstreeks commando's naar GPU-poort `$A020` stuurt. Tip: Laad er eentje in (`BLOAD "STER6502", $7000`) en bekijk hem in **`BRUN MON6502`**!
- **`LOAD "PACMAN"` → `RUN`**: De volledige BASIC-versie van Pac-Man. Druk op `ESC` en typ `LIST` om te zien hoe het doolhof, de spoken en het geluid in BASIC zijn opgebouwd!
- **`LOAD "SDRAM2S"` → `RUN`**: Demonstreert hoe je de grote SDRAM-arrays `X(I)`, `Y(I)`, `U(I)`, `V(I)`, `C(I)` gebruikt om meerdere stuiterende vormen en wisselende schermen op 60 FPS te animeren.

---

#### 16. 🖱️🎨 `MUIS.asm` — Hardware Sprite Muis-Test, Doelwit-Game & Teken-Studio (`SD : DRIVE 0 : BRUN "MUIS"`)
Op **Drive 0 (`D0`, slot `#14`)**, **Drive 3 (`D3`, slot `#14`)** en **Drive 4 (`D4`, slot `#13`)** staat het 6502-machinecodeprogramma **`MUIS`** (`sdcard/MUIS.asm`, `2441 bytes` op `$8000`) om de **12×16 Hardware Sprite Muispijl (`$A00C–$A00F`)** direct uit te proberen:
- **Besturing (`Alt + Pijltjes` én Pico 2 USB-Muis)**:
  - **`Alt + Pijltjestoetsen (`↑` `↓` `←` `→`)`** (of een echte **USB-Muis** aan de Pico 2): Beweeg de witte 12×16 hardware muispijl soepel over het hele 640×360 scherm (`Alt + Shift + Pijltjes` = Turbo-snelheid).
  - **`Alt + Spatie` of `Alt + Enter` (of Linkermuisknop)**: Klik op een knop in de bovenbalk, schiet op het rood-geel-witte **Doelwit (`DOEL:001`)** of teken op het canvas (de pijl kleurt goud-oranje bij het klikken!).
  - **`Alt + X` of `Alt + Ctrl` (of Rechtermuisknop)**: Gum op het canvas.
  - **Klikbare bovenbalk (`Y = 18..43`)**: Klik op een van de **8 kleuren (`1..8`)**, **`DIKTE`** (`4x4`/`8x8`/`14x14`), **`STEMP`** (stempel sterretjes met 16-bit geluid), **`720P`** (teken transparant bovenop de bewegende 720p Twentse Boerderij / Space Planets!) of **`WIS!`**.

---

### 🖱️ Hoofdstuk 17: De Hardware Sprite Muispijl (`Alt + Pijltjes` & Pico 2 USB-Muis) & Muis-Registers (`$A00C–$A00F`)

De Tang Nano 20K heeft in de FPGA (`src/ps2_keyboard.v` & `src/top.v`) een ingebouwde **100 Hz Hardware Muis-Controller** en een **12×16 Hardware Sprite Muispijl** die helemaal bovenaan in de 720p HDMI-pipeline zweeft (0 BSRAMs, 0 CPU-tijd):

| Adres | Lezen (`PEEK`) | Schrijven (`POKE`) |
| :--- | :--- | :--- |
| **`$A00C`** | `MOUSE_X` lage byte (`0..255`) | Zet `MOUSE_X[7:0]` en zet muispijl aan |
| **`$A00D`** | `MOUSE_X` hoge bits (`0..2`) → `X = PEEK($A00C) + PEEK($A00D)*256` (`0..639`) | Zet `MOUSE_X[9:8]` (`0..2`) |
| **`$A00E`** | `MOUSE_Y` lage byte (`0..255`) | Zet `MOUSE_Y[7:0]` en zet muispijl aan |
| **`$A00F`** | **Bit 0 (`1`)**: `MOUSE_Y[8]` → `Y = PEEK($A00E) + (PEEK($A00F) & 1)*256` (`0..359`)<br>**Bit 1 (`2`)**: Linkermuisknop (`Alt + Spatie/Enter` of USB-muis links)<br>**Bit 2 (`4`)**: Rechtermuisknop (`Alt + X/Ctrl` of USB-muis rechts)<br>**Bit 3 (`8`)**: Klik-Latch (onthoudt een klik tot je `PEEK($A00F)` leest)<br>**Bit 6 (`64`)**: Muispijl zichtbaar (`1` = aan) | `POKE $A00F, $C0` (`192`): Toon muispijl<br>`POKE $A00F, $80` (`128`): Verberg muispijl<br>`POKE $A00F, 0` of `1`: Zet `MOUSE_Y[8]` |

#### Voorbeeld 1: Interactief BASIC Muis-Tekenbord & Knoppen-Tester (`MODE 1`)
```basic
10 REM === BASIC HARDWARE SPRITE MUIS-TEKENBORD & TESTER ($A00C-$A00F) ===
20 MODE 1 : CLEAR $01 : CLS
30 POKE $A00C, 64 : POKE $A00D, 1 : POKE $A00E, 180 : POKE $A00F, $C0
40 RECT 0, 0, 640, 32, $04 : GTEXT 12, 4, "HARDWARE MUIS STUDIO: ALT+PIJLTJES = BEWEEG | ALT+SPATIE/ENTER = KLIK/TEKEN", $FC
50 FOR I = 0 TO 7
60   C = $E0 : IF I=1 THEN C=$FC
70   IF I=2 THEN C=$1C
80   IF I=3 THEN C=$1F
90   IF I=4 THEN C=$03
100  IF I=5 THEN C=$E3
110  IF I=6 THEN C=$FF
120  IF I=7 THEN C=$92
130  RECT 12 + I*52, 15, 44, 14, C
140 NEXT I
150 GTEXT 440, 18, "[RECHTS=GUM] [Q=STOP]", $FF
160 K = $FC
180 S = PEEK($A00F)
190 X = PEEK($A00C) + PEEK($A00D) * 256
200 Y = PEEK($A00E) + (S & 1) * 256
210 B = (S / 2) & 3
220 IF (B = 1) & (Y < 32) THEN I = (X - 12) / 52 : IF (I >= 0) & (I <= 7) THEN GOSUB 340
230 IF (B = 1) & (Y >= 34) & (Y < 334) THEN DISK X, Y, 4, K : SOUND 0, 300 + Y, 90
240 IF (B = 2) & (Y >= 34) & (Y < 334) THEN RECT X-6, Y-6, 12, 12, $01 : SOUND 0, 140, 80
250 IF B = 0 THEN SOUND 0, 0, 0
260 RECT 0, 338, 640, 22, $02
270 RECT 270, 343, 24, 12, K
280 GTEXT 12, 345, "KLEUR:", $FC : GTEXT 310, 345, "ALT+PIJLTJES=MUIS  ALT+SPATIE=TEKEN  Q=STOP", $1C
320 Z = KEY : IF (Z = 81) | (Z = 113) THEN GOTO 335
330 GOTO 180
335 SOUND 0, 0, 0 : MODE 0 : CLEAR $E3 : CLS : PRINT "MUIS-STUDIO AFGESLOTEN!" : END
340 IF I=0 THEN K=$E0
350 IF I=1 THEN K=$FC
360 IF I=2 THEN K=$1C
370 IF I=3 THEN K=$1F
380 IF I=4 THEN K=$03
390 IF I=5 THEN K=$ED
400 IF I=6 THEN K=$FF
410 IF I=7 THEN K=$92
420 BEEP 880, 4 : RETURN
```

#### Voorbeeld 2: BASIC "Klik het Doelwit op de 720p Boerderij!" Mini-Game (`MODE 0`)
```basic
10 REM === KLIK HET DOELWIT OP DE 720P BOERDERIJ (ALT+PIJLTJES & ALT+SPATIE) ===
20 MODE 0 : POKE $A006, 3 : CLEAR $E3 : CLS
30 POKE $A00C, 64 : POKE $A00D, 1 : POKE $A00E, 180 : POKE $A00F, $C0
40 P = 0 : X = 320 : Y = 200
50 GOSUB 200
70 S = PEEK($A00F)
80 M = PEEK($A00C) + PEEK($A00D) * 256
90 N = PEEK($A00E) + (S & 1) * 256
100 IF (S & 10) > 0 THEN IF (ABS(M - X) <= 18) & (ABS(N - Y) <= 18) THEN GOSUB 240
110 RECT 180, 334, 280, 22, $01
120 GTEXT 192, 341, "SCHIET OP HET DOELWIT! (Q=STOP)", $FC
140 K = KEY : IF (K = 81) | (K = 113) THEN GOTO 170
150 WAIT 2 : GOTO 70
170 CLEAR $E3 : CLS : PRINT "EINDSCORE DOELWITTEN: "; P : END
200 DISK X, Y, 16, $E0 : DISK X, Y, 10, $FC : DISK X, Y, 4, $FF : RETURN
240 DISK X, Y, 17, $E3 : P = P + 1 : PRINT "RAAK! SCORE = "; P
250 BEEP 523, 4 : BEEP 784, 6
260 X = 80 + RND(480) : Y = 90 + RND(210)
270 GOSUB 200 : RETURN
```

---

### 🎧🤖 Hoofdstuk 19: Het Ingebouwde `WAV`-Commando, `.MP3`-Ondersteuning & De Hardware Audio Hulp-CPU (`$A016–$A01B`)

Naast de 4-kanaals FM-synthesizer (`SOUND 0..3`) heeft de Tang Nano 20K een **8-bit Hardware PCM / `.WAV` DAC (`$A016`)** met een **Hardware Sample-Rate Timer (`$A017`)**, een 2-polig 48 kHz anti-aliasing low-pass filter over 16-bit Stereo HDMI-audio én een autonome **SDRAM Audio-DMA Co-Processor ("Audio Hulp-CPU" op `$A018–$A01B`)**!

#### 1. De Hardware PCM DAC (`$A016–$A017`) & Audio Hulp-CPU Registers (`$A018–$A01B`)

| Register | Naam | Richting | Functie & Waarden |
| :--- | :--- | :--- | :--- |
| **`$A016`** (`40982`) | `IO_PCM_DAC` | Lezen / Schrijven | **8-bit Unsigned PCM Sample (`0..255`, `128` = stilte/midden)**. Wordt door het 48 kHz HDMI-filter gemengd met de 4 FM-kanalen. Na ~0,15 s zonder schrijfactie keert de DAC automatisch geruisloos terug naar `128`. |
| **`$A017`** (`40983`) | `IO_PCM_RATE` | Lezen / Schrijven | **Hardware Sample-Rate Pacing Timer**:<br>• `0` = Direct (geen CPU-wacht)<br>• `1` = **8.000 Hz** (3375 kloktikken @ 27 MHz)<br>• `2` = **11.025 Hz** (2449 kloktikken)<br>• `3` = **16.000 Hz** (1687 kloktikken)<br>• `4` = **22.050 Hz** (1224 kloktikken)<br>• `5` = **12.000 Hz**, `6` = **24.000 Hz**, `7` = **32.000 Hz** |
| **`$A018`** (`40984`) | `IO_ADMA_BANK` | Lezen / Schrijven | **Schrijven:** Start SDRAM-bank (`0..63`, standaard `62` = `$3E`) voor de Audio Hulp-CPU.<br>**Lezen:** Huidige SDRAM-bank waar de Audio Hulp-CPU op dit moment speelt. |
| **`$A019`** (`40985`) | `IO_ADMA_PAGES_LO` | Lezen / Schrijven | **Schrijven:** Aantal pagina's (`256 B`) Laag (`128` = 32 KB).<br>**Lezen:** Resterende pagina's Laag (telt live af tijdens afspelen!). |
| **`$A01A`** (`40986`) | `IO_ADMA_PAGES_HI` | Lezen / Schrijven | **Schrijven:** Aantal pagina's (`256 B`) Hoog (bijv. `2` = 512 pagina's = 128 KB over 2 SDRAM-banken voor 16s MP3-muziek!).<br>**Lezen:** Resterende pagina's Hoog. |
| **`$A01B`** (`40987`) | `IO_ADMA_CTRL` | Lezen / Schrijven | **Schrijven:** `0` = Stop direct (`WAV 0`), `1..7` = Start 1× op de achtergrond op rate `1..7`, **`129..135` (`rate + 128`) = Start in Oneindige Hardware-Loop!**<br>**Lezen:** Bit 7 (`128`) = `1` zolang Hulp-CPU speelt, Bit 6 (`64`) = Loop actief, Bits 2..0 = Rate (`1..7`). |

> [!TIP]
> **Hoe werkt de autonome Audio Hulp-CPU (`$A018–$A01B`)?**
> Zodra de Audio Hulp-CPU gestart wordt (via `WAV` of `POKE $A01B`), haalt hij via *cycle-stealing* van ~6 kloktikken per sample (**< 0,15% CPU-belasting**, **0 extra BSRAMs**) zelfstandig de audiobytes uit het 8 MB SDRAM (en telt automatisch door over meerdere 64 KB SDRAM-banken heen). De 6502 Hoofd-CPU heeft zijn handen 100% vrij voor BASIC, 60 FPS graphics én 4-kanaals FM-synthesizer geluid!

#### 2. Het Ingebouwde `WAV`-Commando in MiniGPU-BASIC 1.2

| BASIC Commando | Voorbeeld | Wat doet het? |
| :--- | :--- | :--- |
| **`WAV`** *(zonder getal)* | `WAV` | Leest MicroSD-sector `$2000` en toont een genummerde lijst van **alle 16 `.WAV`-geluiden (`#1..#16`)**. |
| **`WAV nr`** (`1..16`) | `WAV 2` of `WAV 9` | Laadt geluid `#nr` (32 KB) in 0,5 s naar SDRAM Bank 62 en laat de **Audio Hulp-CPU op de achtergrond spelen** (je krijgt direct de `>` prompt terug!). |
| **`WAV nr, rate`** | `WAV 3, 2` of `WAV 11, 4` | Speelt geluid `#nr` op de achtergrond af met een **eigen sample-rate / pitch (`1..7`)** (`1`=8kHz .. `7`=32kHz). |
| **`WAV nr, rate, 1`** | `WAV 12, 1, 1` | **Oneindige Hardware-Loop op de Audio Hulp-CPU (`mode = 1`)!** Ideaal voor achtergrondmuziek tijdens een game (`WAV 12, 1, 1 : DEMO 3`). |
| **`WAV nr, rate, 2`** | `WAV 1, 1, 2` | **Wacht tot klaar (`mode = 2`):** Wacht tot het geluid helemaal afgelopen is (of tot je op `ESC` drukt). |
| **`WAV 0`** | `WAV 0` | **Stopt** de Audio Hulp-CPU direct (ook de **`ESC`**-toets stopt de Hulp-CPU!). |

#### 3. Overzicht van alle 16 Standaard `.WAV`-Slots op de MicroSD-Kaart (`Sector $2000–$240F`)

| Slot | BASIC Commando | Naam in SD-Directory (`$2000`) | SD-Sectoren | Rate | Omschrijving |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`#1`** | `WAV 1` | `1.BOERDERIJ WEI` | `$2010–$204F` | 8.000 Hz | Twentse boerderij-weide sfeer met vogels & erf |
| **`#2`** | `WAV 2` | `2.OCHTENDVOGELS` | `$2050–$208F` | 8.000 Hz | Zingende ochtendvogels (merel, vink & koekoek) |
| **`#3`** | `WAV 3` | `3.KRAAIENDE HN` | `$2090–$20CF` | 8.000 Hz | Kraaiende boerderij-haan bij zonsopkomst |
| **`#4`** | `WAV 4` | `4.TWENTSE KOE` | `$20D0–$210F` | 8.000 Hz | Loeiende Twentse koe in de wei |
| **`#5`** | `WAV 5` | `5.SCHAPENKUDDE` | `$2110–$214F` | 8.000 Hz | Blatende schapenkudde & lammetjes op de heide |
| **`#6`** | `WAV 6` | `6.VARKEN & KIP` | `$2150–$218F` | 8.000 Hz | Knorrend varken & kakelende kippen op het erf |
| **`#7`** | `WAV 7` | `7.BOSVOGEL KOOR` | `$2190–$21CF` | 8.000 Hz | Meerstemmig bosvogelkoor in de lente |
| **`#8`** | `WAV 8` | `8.DORPSKERK KLK` | `$21D0–$220F` | 8.000 Hz | Luidende Twentse dorpskerkklok met galm |
| **`#9`** | `WAV 9` | `1.VROEGE MEREL` | `$2210–$224F` | 8.000 Hz | Solo zingende vroege merel |
| **`#10`** | `WAV 10` | `2.BOERENERF MIX` | `$2250–$228F` | 8.000 Hz | Complete boerenerf ochtendmix |
| **`#11`** | `WAV 11` | `3.TANG NANO STM` | `$2290–$22CF` | 8.000 Hz | Gesproken Engelse welkomststem + FM-akkoord |
| **`#12`** | `WAV 12` | `4.FUNK DRUMBEAT` | `$22D0–$230F` | 8.000 Hz | Strakke Funk Drumbeat & Slap-Bass loop (`WAV 12,1,1`) |
| **`#13`** | `WAV 13` | `5.WINDOWS TADA!` | `$2310–$234F` | 11.025 Hz | Originele Microsoft Studio `tada.wav` fanfare |
| **`#14`** | `WAV 14` | `6.CYBER ACID BS` | `$2350–$238F` | 8.000 Hz | Resonante TB-303 Acid synth-baslijn & 909 kick |
| **`#15`** | `WAV 15` | `7.STUDIO CHIMES` | `$2390–$23CF` | 11.025 Hz | Originele Microsoft Studio `Ring08.wav` chimes |
| **`#16`** | `WAV 16` | `8.SPACE RADIO` | `$23D0–$240F` | 8.000 Hz | NASA Apollo Quindar-piep & kosmische radio-sweep |

#### 4. De PC `.WAV` & `.MP3` Studio GUI (`wav_gui.py` / `start_wav_gui.bat`) & `WAVPLAY`

- **Eigen `.WAV` of `.MP3` uploaden met de GUI:** Dubbelklik op `start_wav_gui.bat` (of klik in `basic_terminal.py` op **🎵 WAV Studio GUI**). Je kunt elk `.WAV`- of `.MP3`-bestand (bijv. `wav_tracks/outfoxing_song.mp3`) openen, een fragment kiezen op de oscilloscoop, op je pc voorbeluisteren en direct naar Slot `#1..#16` op de MicroSD-kaart uploaden — óf **16 seconden aan één stuk (128 KB over SDRAM Bank 60..61)** naar de Audio Hulp-CPU streamen!
- **Grafische 6502 `.WAV`-Speler op SD (`WAVPLAY`):** Start met `SD : DRIVE 0 : BRUN "WAVPLAY"` voor een volledige oscilloscoop, stereo VU-meters en muis-scrubbing.

#### 5. Zes Praktische BASIC-Voorbeelden met `.WAV`, `.MP3` & de Audio Hulp-CPU

##### Voorbeeld 1: Alle 16 SD-Kaart `.WAV`-bestanden tonen & op de achtergrond afspelen
```basic
10 REM === TOON ALLE 16 SD-KAART WAV-BESTANDEN & SPEEL OCHTENDVOGELS ===
20 CLS : PRINT "=== 16 DIGITALE WAV-SLOTEN OP MICROSD (SECTOR $2000) ==="
30 WAV
40 PRINT "WE STARTEN NU #2 (OCHTENDVOGELS) OP DE AUDIO HULP-CPU..."
50 WAV 2
60 PRINT "TERWIJL DE HULP-CPU SPEELT, REKENT DE 6502 GEWOON DOOR!"
70 FOR I = 1 TO 8
80   PRINT "HULP-CPU STATUS ($A01B): "; PEEK($A01B); " | RESTERENDE PAGINA'S ($A019): "; PEEK($A019)
90   WAIT 45
100 NEXT I
110 PRINT "KLAAR!"
```

##### Voorbeeld 2: Interactief Twents Boerderij & Vogels Geluiden-Bord (`MODE 0`)
```basic
10 REM === TWENTS BOERDERIJ & VOGELS GELUIDEN-BORD OP DE AUDIO HULP-CPU ===
20 MODE 0 : POKE $A006, 3 : CLEAR $E3 : CLS
30 PRINT "=== TWENTS BOERDERIJ & VOGELS SOUND-BOARD (HULP-CPU) ==="
40 PRINT "[1] Boerderij Wei  [2] Ochtendvogels  [3] Kraaiende Haan"
50 PRINT "[4] Twentse Koe    [5] Schapenkudde   [6] Varken & Kip"
60 PRINT "[7] Bosvogel Koor  [8] Dorpskerk Klok [9] Vroege Merel"
70 PRINT "[L] Loop Huidige   [0] Stop Geluid    [Q] Afsluiten"
80 S = 2 : WAV 2
100 K = KEY
110 IF (K >= 49) & (K <= 57) THEN S = K - 48 : WAV S
120 IF (K = 76) | (K = 108) THEN WAV S, 1, 1
130 IF K = 48 THEN WAV 0
140 IF (K = 81) | (K = 113) THEN GOTO 240
150 R = PEEK($A019) : A = PEEK($A01B)
160 RECT 120, 290, 400, 48, $01 : RECT 122, 292, 396, 44, $04
170 GTEXT 136, 300, "ACTIEF SLOT OP AUDIO HULP-CPU", $FC
180 IF A >= 128 THEN GTEXT 384, 300, "[SPEELT]", $1F
190 IF A < 128 THEN GTEXT 384, 300, "[GEREED]", $92
200 RECT 136, 316, 368, 12, $00
210 IF A >= 128 THEN W = (128 - R) * 2 + 16 : RECT 136, 316, W, 12, $1C
220 WAIT 4 : GOTO 100
240 WAV 0 : CLEAR $E3 : CLS : PRINT "SOUND-BOARD AFGESLOTEN!"
```

##### Voorbeeld 3: 60 FPS GPU-Animatie + 4-Kanaals FM-Synth + Oneindige `.WAV` Drum-Loop Tegelijk! (`MODE 1`)
```basic
10 REM === HULP-CPU DRUM-LOOP (WAV 12,1,1) + LIVE FM-SYNTH + 60 FPS GPU SHOW ===
20 WAV 12, 1, 1
30 POKE $A00A, 2 : POKE $A00B, 7
40 MODE 1 : TARGET 0 : X = 320 : Y = 180 : U = 6 : V = 4 : F = 0
60 CLEAR $01
70 RECT 0, 0, 640, 28, $04
80 GTEXT 18, 10, "AUDIO HULP-CPU SPEELT WAV-LOOP + 6502 DOET 60 FPS GPU + FM-SYNTH!", $FC
90 R = PEEK($A019) : B = 128 - R
100 FOR I = 0 TO 15
110   H = 20 + ((B + I * 11) & 127)
120   RECT 40 + I * 35, 310 - H, 26, H, RGB(I & 7, (15 - I) & 7, 3)
130 NEXT I
140 DISK X, Y, 28, $E0 : CIRCLE X, Y, 34, $FC : DISK X - 8, Y - 8, 6, $FF
150 RECT 40, 326, 256, 12, $00 : RECT 40, 326, B * 2, 12, $1C
160 GTEXT 310, 328, "DRUK OP SPATIE OM TE STOPPEN", $FF
170 FLIP : WAIT 1
180 X = X + U : Y = Y + V : F = F + 1
190 IF (X < 50) | (X > 590) THEN U = -U
200 IF (Y < 65) | (Y > 250) THEN V = -V
210 IF (F & 31) = 0 THEN SOUND 0, 220, 140 : SOUND 1, 277, 120 : SOUND 2, 330, 120
220 IF (F & 31) = 16 THEN SOUND 0, 196, 140 : SOUND 1, 247, 120 : SOUND 2, 294, 120
230 IF KEY = 32 THEN GOTO 250
240 GOTO 60
250 WAV 0 : SOUND 0,0,0 : SOUND 1,0,0 : SOUND 2,0,0 : TARGET 1 : MODE 0 : CLS
260 PRINT "SHOW GESTOPT!"
```

##### Voorbeeld 4: Live DJ Pitch-Bender & Beat-Repeat / Stutter Studio (`$A018–$A01B`)
```basic
10 REM === LIVE DJ PITCH-BENDER & BEAT-REPEAT STUDIO ($A018-$A01B) ===
20 CLS : PRINT "=== AUDIO HULP-CPU DJ PITCH & STUTTER STUDIO ==="
30 PRINT "Laden van Funk Drumbeat (#12) in SDRAM Bank 62..."
40 WAV 12, 1, 1
50 PRINT "Toetsen: [1..7]=Pitch  [A]=128p [S]=64p [D]=32p [F]=8p Stutter  [Q]=Stop"
60 R = 1 : P = 128
80 K = KEY
90 IF (K >= 49) & (K <= 55) THEN R = K - 48 : POKE $A019, P : POKE $A01B, R + 128 : PRINT "Pitch Rate = "; R
100 IF (K = 65) | (K = 97) THEN P = 128 : POKE $A019, P : POKE $A01B, R + 128 : PRINT "Loop = 128 pag"
110 IF (K = 83) | (K = 115) THEN P = 64 : POKE $A019, P : POKE $A01B, R + 128 : PRINT "Loop = 64 pag"
120 IF (K = 68) | (K = 100) THEN P = 32 : POKE $A019, P : POKE $A01B, R + 128 : PRINT "Loop = 32 pag"
130 IF (K = 70) | (K = 102) THEN P = 8 : POKE $A019, P : POKE $A01B, R + 128 : PRINT "Loop = 8 pag (Stutter!)"
140 IF (K = 81) | (K = 113) THEN GOTO 170
150 WAIT 2 : GOTO 80
170 WAV 0 : PRINT "DJ STUDIO GESTOPT!"
```

##### Voorbeeld 5: Zelf in BASIC een Golfvorm in SDRAM Bank 61 berekenen & op de Audio Hulp-CPU afspelen
```basic
10 REM === BEREKEN ZELF EEN GOLF IN SDRAM BANK 61 & SPEEL OP DE HULP-CPU ===
20 CLS : PRINT "16 PAGINA'S (4096 SAMPLES) SCI-FI GOLF BEREKENEN IN SDRAM BANK 61..."
30 POKE $A01B, 0 : POKE $A015, 61
40 FOR P = 0 TO 15
50   POKE $A013, P
60   S = 8 + (P & 7) * 3
70   FOR B = 0 TO 255
80     POKE $A012, B
90     POKE $A014, (B * S) & 255
100  NEXT B
110 NEXT P
120 PRINT "START AUDIO HULP-CPU OP BANK 61 (IN ONEINDIGE LOOP)..."
130 POKE $A018, 61 : POKE $A019, 16 : POKE $A01A, 0 : POKE $A01B, 129
140 FOR I = 1 TO 6
150   PRINT "HULP-CPU SPEELT BANK "; PEEK($A018); " PAGINA "; PEEK($A019)
160   WAIT 50
170 NEXT I
180 WAV 0 : PRINT "KLAAR!"
```

##### Voorbeeld 6: 🎶 Complete 16,4-Seconden `.MP3` Jukebox & Visualizer vanaf MicroSD (`Sector $2410–$250F` → SDRAM Bank 60..61)
Op je MicroSD-kaart staat direct achter de 16 WAV-slots (op **Sector `$2410–$250F`**) het 16,4-seconden `.MP3`-liedje **`outfoxing_song.mp3`** (`256 sectoren = 128 KB = 512 pagina's`). Dit BASIC-programma kopieert met een snelle 6502-routine in interne Block-RAM op `$2E00` in 1,8 seconde alle 128 KB van de SD-kaart naar **SDRAM Bank 60 & 61**, start de **Audio Hulp-CPU (`POKE $A018,60 : POKE $A019,0 : POKE $A01A,2 : POKE $A01B,129`)** en toont een live **MP3 Jukebox met spectrum-equalizer en voortgangsbalk**:
```basic
10 REM === VOORBEELD 6: 16-SEC MP3 SPELER VANAF MICROSD ($2410) OP HULP-CPU ===
20 MODE 0 : POKE $A006, 3 : CLEAR $E3 : CLS
30 PRINT "=== MP3 JUKEBOX: OUTFOXING_SONG.MP3 (16,4 SEC / 128 KB) ==="
40 PRINT "Laden van 256 sectoren ($2410-$250F) naar SDRAM Bank 60 & 61..."
50 POKE $2E00,$A9:POKE $2E01,$00:POKE $2E02,$8D:POKE $2E03,$1B:POKE $2E04,$A0:POKE $2E05,$8D
55 POKE $2E06,$91:POKE $2E07,$04:POKE $2E08,$20:POKE $2E09,$6A:POKE $2E0A,$E9:POKE $2E0B,$A9
60 POKE $2E0C,$10:POKE $2E0D,$8D:POKE $2E0E,$96:POKE $2E0F,$04:POKE $2E10,$A9:POKE $2E11,$24
65 POKE $2E12,$8D:POKE $2E13,$97:POKE $2E14,$04:POKE $2E15,$A9:POKE $2E16,$3C:POKE $2E17,$8D
70 POKE $2E18,$15:POKE $2E19,$A0:POKE $2E1A,$A9:POKE $2E1B,$00:POKE $2E1C,$85:POKE $2E1D,$60
75 POKE $2E1E,$A9:POKE $2E1F,$02:POKE $2E20,$85:POKE $2E21,$61:POKE $2E22,$A9:POKE $2E23,$00
80 POKE $2E24,$85:POKE $2E25,$1C:POKE $2E26,$A9:POKE $2E27,$06:POKE $2E28,$85:POKE $2E29,$1D
85 POKE $2E2A,$20:POKE $2E2B,$67:POKE $2E2C,$EA:POKE $2E2D,$A5:POKE $2E2E,$60:POKE $2E2F,$8D
90 POKE $2E30,$13:POKE $2E31,$A0:POKE $2E32,$A0:POKE $2E33,$00:POKE $2E34,$8C:POKE $2E35,$12
95 POKE $2E36,$A0:POKE $2E37,$B9:POKE $2E38,$00:POKE $2E39,$06:POKE $2E3A,$8D:POKE $2E3B,$14
100 POKE $2E3C,$A0:POKE $2E3D,$C8:POKE $2E3E,$D0:POKE $2E3F,$F4:POKE $2E40,$E6:POKE $2E41,$60
105 POKE $2E42,$A5:POKE $2E43,$60:POKE $2E44,$8D:POKE $2E45,$13:POKE $2E46,$A0:POKE $2E47,$8C
110 POKE $2E48,$12:POKE $2E49,$A0:POKE $2E4A,$B9:POKE $2E4B,$00:POKE $2E4C,$07:POKE $2E4D,$8D
115 POKE $2E4E,$14:POKE $2E4F,$A0:POKE $2E50,$C8:POKE $2E51,$D0:POKE $2E52,$F4:POKE $2E53,$E6
120 POKE $2E54,$60:POKE $2E55,$D0:POKE $2E56,$CB:POKE $2E57,$A9:POKE $2E58,$3D:POKE $2E59,$8D
125 POKE $2E5A,$15:POKE $2E5B,$A0:POKE $2E5C,$C6:POKE $2E5D,$61:POKE $2E5E,$D0:POKE $2E5F,$C2
130 POKE $2E60,$60
140 CALL $2E00
150 PRINT "Start Audio Hulp-CPU op SDRAM Bank 60..61 (512 pag = 16,4s MP3 Loop)!"
160 POKE $A018, 60 : POKE $A019, 0 : POKE $A01A, 2 : POKE $A01B, 129
170 PRINT "Toetsen: [1..7]=Pitch/Tempo  [R]=Herstart  [Q/Spatie]=Stop"
180 K = KEY
190 IF (K >= 49) & (K <= 55) THEN POKE $A018,60:POKE $A019,0:POKE $A01A,2:POKE $A01B,(K-48)+128
200 IF (K = 82) | (K = 114) THEN POKE $A018,60:POKE $A019,0:POKE $A01A,2:POKE $A01B,129
210 IF (K = 32) | (K = 81) | (K = 113) THEN GOTO 310
220 H = PEEK($A01A) : L = PEEK($A019) : P = 512 - (H * 256 + L)
230 IF P < 0 THEN P = 0
240 IF P > 512 THEN P = 512
250 RECT 60, 250, 520, 86, $01 : RECT 62, 252, 516, 82, $04
260 GTEXT 78, 260, "MP3: OUTFOXING_SONG.MP3 (128 KB SDRAM BANK 60..61)", $FC
270 FOR I = 0 TO 15 : B = 8 + ((P * 3 + I * 13) & 31)
280   RECT 78 + I * 30, 308 - B, 22, B, RGB(I & 7, 1 + (I & 5), 3)
290 NEXT I
300 RECT 78, 314, 484, 12, $00 : RECT 78, 314, (P * 15) / 16 + 4, 12, $1C : WAIT 3 : GOTO 180
310 WAV 0 : CLEAR $E3 : CLS : PRINT "MP3 SPELER GESTOPT!"
```

##### Voorbeeld 7: 🎧🎵 `BRUN "MP3PLAY"` / `BRUN "WAVPLAY"` — MP3Commander 2.0 (Midnight-Commander Dual-Pane `.MP3` & `.WAV` Speler op `$8000`)
Wil je net als in Midnight Commander (`BRUN "MC"`) met een keuzelijst door al je `.MP3`-liedjes én `.WAV`-geluiden bladeren en ze met `Enter` (of cijfers `1..8`) starten? Op **Drive 0 (`D0`)**, **Drive 1 (`D1`)** en **Drive 2 (`D2`)** staat het 6502 Assembly-programma **`MP3PLAY`** (`sdcard/MP3PLAY.asm`, gekoppeld aan **`WAVPLAY`**):
- **Linker Paneel (`.MP3` Liedjes, Sector `$2001` & `$2410–$290F`, SDRAM Banken `44..59`):**
  1. `1.OUTFOXING.MP3` (`$2410`, 128 KB = 16,4 sec) — *Outfoxing the Fox*
  2. `2.CALIF DREM.MP` (`$2510`, 128 KB = 16,4 sec) — *California Dreamin'*
  3. `3.MONDAY MON.MP` (`$2610`, 64 KB = 8,2 sec) — *Monday, Monday*
  4. `4.DEDICATED.MP3` (`$2690`, 64 KB = 8,2 sec) — *Dedicated To The One I Love*
  5. `5.DANCING ST.MP` (`$2710`, 64 KB = 8,2 sec) — *Dancing In The Street*
  6. `6.SPAN HARLM.MP` (`$2790`, 64 KB = 8,2 sec) — *Spanish Harlem*
  7. `7.TWIST SHT.MP3` (`$2810`, 64 KB = 8,2 sec) — *Twist And Shout*
  8. `8.CALL NAME.MP3` (`$2890`, 64 KB = 8,2 sec) — *I Call Your Name*
- **Rechter Paneel (16 `.WAV` Geluiden, Sector `$2000` & `$2010–$240F`, SDRAM Banken `28..43`):** Pagina 1/2 (`#1..#8`) en Pagina 2/2 (`#9..#16`, wissel met toets `P`).
- **Besturing:** `Pijltjes Omhoog/Omlaag` = Kies bestand • `TAB` / `Pijl Links/Rechts` = Wissel `.MP3` / `.WAV` paneel • `Enter` of `1..8` = Speel gekozen bestand via de **Hardware Audio Hulp-CPU (`$A018–$A01B`)** • `Spatie` = Pauze/Hervat • `L` = Loop Nummer / Album Auto-DJ • `S` = Sample-Rate (`8/11/16/22 kHz`) • `M` = +FM Synth Pad • `B` = Sluit af terwijl het `.MP3`-liedje op de achtergrond doorspeelt • `ESC`/`Q` = Stop & Sluit.
```basic
SD : DRIVE 0 : BRUN "MP3PLAY"
```

---

### 📋 Bijlage A: Het Grote MiniGPU-BASIC 1.2 Spiekbriefje

| Commando / Functie | Werkend Voorbeeld | Wat doet het? |
| :--- | :--- | :--- |
| `FUNC naam .. ENDFUNC` | `FUNC RAKET` ... `ENDFUNC` | Zelfstandig functieblok (mag overal staan; wordt automatisch overgeslagen!) |
| `DO naam [, slot]` | `DO RAKET` of `DO RAKET, 17` | Roept `FUNC naam` aan (optioneel met ander sprite/tile/bigspr `slot`) |
| `DEFSPR / DEFTILE / DEFBIG` | `DEFSPR 16` / `DEFTILE 12` / `DEFBIG 0` | Start snelle 6502 GPU-upload voor Sprite (`0..31`), Tile (`0..63`) of BigSprite (`0..1`) |
| `PIX "hex..."` | `PIX "10E0 83FC1FFF"` | Streamt RLE (`01..7F`+kleur) en Raw (`81..FF`+N kleuren) pixels naar de GPU |
| `RGB(r, g, b)` | `RGB(7, 4, 0)` | Mengt kleur: rood `0..7`, groen `0..7`, blauw `0..3` |
| `CLEAR [kleur]` | `CLEAR $E3` of `CLEAR 0` | Vult 640×360 canvas (`$E3` = transparant, `0` = zwart) |
| `RECT x, y, w, h, c` | `RECT 20, 20, 100, 50, $1C` | Gevulde rechthoek (`w=1, h=1` tekent 1 losse pixel!) |
| `LINE x1, y1, x2, y2, c` | `LINE 0, 0, 639, 359, $1F` | Rechte lijn van `(x1,y1)` naar `(x2,y2)` in kleur `c` |
| `CIRCLE x, y, r, c` | `CIRCLE 320, 180, 50, $FF` | Open cirkel (alleen buitenrand) met straal `r` |
| `DISK x, y, r, c` | `DISK 320, 180, 50, $FC` | Volledig gevulde cirkel / bol in kleur `c` |
| `TRI x1,y1,x2,y2,x3,y3,c` | `TRI 320,40,200,260,440,260,$FF` | Open driehoek tussen 3 hoekpunten |
| `FTRI x1,y1,x2,y2,x3,y3,c` | `FTRI 320,40,200,260,440,260,$E0` | Volledig gevulde driehoek tussen 3 hoekpunten |
| `GTEXT x, y, "..", c` | `GTEXT 20, 20, "SCORE", 252` | Grafische 8×8 tekst op pixelpositie `(x, y)` in kleur `c` |
| `MODE 0` / `MODE 1` | `MODE 1` | `0` = BASIC + 3D-planeten, `1` = volledig scherm graphics |
| `TARGET n` / `FLIP` | `TARGET 0` ... `FLIP` | `TARGET 0` = teken op achterbuffer, `FLIP` = wissel buffers |
| `SPRITE id, x, y` | `SPRITE 0, 312, 316` | Tekent 16×16 sprite (`0..31`) op `(x, y)` |
| `POKE $A020, 9` | `POKE $A020,9:POKE $A020,16` | Upload eigen 16×16 sprite in slot `0..31` (+ 256 pixels, `$E3`=transparant) |
| `BIGSPR id, en, x, y [,f]` | `BIGSPR 0, 1, 440, 180, 0` | Zet 128×128 BigSprite (`0..1`) aan/uit (`f=1` spiegelt!) |
| `POKE $A020, 22` | `POKE $A020,22:POKE $A020,0:POKE $A020,Y` | Upload 1 lijn (128 pixels) van eigen 128×128 BigSprite (`Y = 0..127`) |
| `SCROLL x, y` / `TILE x,y,t` | `TILE 10, 8, 12` | Scrolt of plaatst tegel `0..63` op de 64×64 achtergrond-wereldmap |
| `POKE $A020, 13` | `POKE $A020,13:POKE $A020,12` | Upload eigen 16×16 tegel (Tile) in slot `0..63` (+ 256 kleurbytes) |
| `SOUND ch, hz, vol` | `SOUND 0, 440, 200` | Speelt toon op kanaal `0..3` met volume `0..255` |
| `BEEP hz, duur_10ms` | `BEEP 880, 15` | Pieptoon van `hz` Hz voor `duur × 10 ms` (`15` = 0,15 s) |
| `WAIT duur_10ms` | `WAIT 1` of `WAIT 50` | Wacht `duur × 10 ms` (`1` ≈ 1 frame, `100` = 1 seconde) |
| `INPUT ["vraag",] V` | `INPUT "STRAAL", R` | Vraagt de gebruiker om een getal/formule en slaat op in `V` |
| `KEY` / `JOY` / `TIMER` | `J = JOY : K = KEY` | Leest toets (ASCII), joypad-richtingsbits of 60Hz-teller |
| `PEEK/POKE $A00C..$A00F` | `X=PEEK($A00C)+PEEK($A00D)*256` | Leest of zet de **12×16 Hardware Sprite Muispijl** (`Alt+Pijltjes` / Pico 2 USB-Muis, `$A00F` bit 1/2/3 = knoppen) |
| `POKE $A016, s` / `$A017, r` | `POKE $A017, 1 : POKE $A016, S` | **8-bit Hardware PCM / `.WAV` DAC** (`0..255`, `128`=stilte) & **Sample-Rate Timer** (`1`=8kHz, `2`=11kHz, `3`=16kHz, `4`=22kHz) |
| `WAV [1..16, r, m]` / `WAV 0` | `WAV 2` of `WAV 12, 1, 1` | **Ingebouwd MicroSD `.WAV`-commando:** `WAV`=lijst alle 16 tracks, `WAV 0`=stop, `WAV nr[,rate[,mode]]` speelt op de **Audio Hulp-CPU** (`mode 0`=achtergrond, `1`=oneindige loop, `2`=wacht) |
| `PEEK/POKE $A018..$A01B` | `POKE $A018,62:POKE $A01B,129` | **Hardware Audio Hulp-CPU (SDRAM Audio-DMA):** `$A018`=Bank, `$A019/$A01A`=Pagina's L/H, `$A01B`=Start/Loop (`+128`)/Status |
| `BRUN "MUIS"` | `SD : DRIVE 0 : BRUN "MUIS"` | Start **Hardware Sprite Muis-Test, Doelwit-Game & Teken-Studio** (`Alt+Pijltjes` / USB-Muis) |
| `BRUN "MP3PLAY"` / `"WAVPLAY"` | `SD : DRIVE 0 : BRUN "MP3PLAY"` | Start **MP3Commander 2.0** (Midnight-Commander Dual-Pane `.MP3` & `.WAV` Speler via Hardware Audio Hulp-CPU, 16-Band Spectrum Equalizer, Auto-DJ & Background Play) |
| `CAT` / `SD` / `SDRAM` / `DRIVE` | `SD : DRIVE 0 : CAT` | Beheert bestanden op MicroSD-kaart en 4 MB SDRAM-Disk |
| `SAVE` / `LOAD` / `BSAVE` / `BLOAD` | `SAVE "GAME"` / `BLOAD "LEESMIJ",$6000` | Slaat BASIC of geheugenblok op en laadt het weer in |
| `BRUN MC` / `BRUN READER` | `SD : BRUN MC` | Start Midnight Commander (`$9000`) of TextReader/Hex-viewer (`$8000`) |
| `BRUN EXCEL` / `BRUN MON6502` | `SD : BRUN EXCEL` | Start 26×30 SDRAM Spreadsheet (`A(1)..Z(30)`) of 6502 Machine Monitor |
| `BRUN FRUITY` / `BRUN SPREDIT` | `SD : BRUN FRUITY` | Start 4-Kanaals FruityLoops Chiptune Studio of 16×16 Sprite-Editor |
| `BRUN WRITER` / `CALC` / `IMPRESS` | `SD : BRUN WRITER` | Start LibreOffice 6502 Suite (Tekstverwerker, Grafiek-Calc, Presentatie/Draw) |
| `BRUN BROWSER` / `NETTERM` | `SD : BRUN BROWSER` | Start W5500 HTTP Powerbaas Browser of TCP Telnet Server (poort 23) & BBS |
| `BRUN RFTS` / `BRUN PACMAN65` | `SD : BRUN RFTS` | Start Reach for the Stars (4X Space Strategy) of 60 FPS Arcade Pac-Man |
