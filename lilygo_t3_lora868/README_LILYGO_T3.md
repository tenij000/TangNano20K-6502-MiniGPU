# 📡 LilyGO TTGO T3 v1.6.1 (868 MHz LoRa + OLED) Co-Processor

Deze map bevat de complete custom ESP32-firmware ([`lilygo_t3_lora868.ino`](lilygo_t3_lora868.ino)) waarmee je een **LilyGO TTGO T3 v1.6.1 (`868 MHz` Semtech SX1276 LoRa + 0.96" SSD1306 OLED)** gebruikt als draadloze lange-afstands **868 MHz LoRa-, OLED- & Wi-Fi NTP-klok Co-Processor** voor de **Tang Nano 20K — MiniGPU-BASIC 1.4**.

---

## 🔌 Bedrading (Slechts 3 Jumper-draden, 3.3V Logica)

Zowel de **Tang Nano 20K** als de **LilyGO T3 v1.6.1** werken op **3.3V logica** — je hebt dus **geen** level-shifter nodig:

| Tang Nano 20K Pin | Richting | LilyGO T3 v1.6.1 Pin | Functie |
| :--- | :---: | :--- | :--- |
| **Pin `30`** (`lora_txd`) | `--->` | **`GPIO 12`** (`Serial1 RX`) | 6502 TX (`POKE $A041, byte`) @ 115200 baud |
| **Pin `31`** (`lora_rxd`) | `<---` | **`GPIO 4`** (`Serial1 TX`) | 6502 RX (`PEEK($A041)`) + Hardware RSSI/RTC Sync @ 115200 baud |
| **`GND`** | `<-->` | **`GND`** | Gezamenlijke massa (verplicht) |

> **Tip:** Pin `30` en Pin `31` zitten op de rechter pinheader van de Tang Nano 20K direct naast de W5500 Ethernet-pinnen (`25..29`).

---

## 🛠️ Firmware Flashen op de LilyGO T3 v1.6.1

### Optie A: Via Arduino IDE
1. Installeer via **Library Manager**:
   - **`LoRa`** door *Sandeep Mistry*
   - **`Adafruit SSD1306`** en **`Adafruit GFX Library`**
2. Kies unter **Tools -> Board -> ESP32 Arduino -> TTGO LoRa32-OLED** en selecteer Board Revision **`TTGO LoRa32 V2.1 (1.6.1)`**.
3. Open [`lilygo_t3_lora868.ino`](lilygo_t3_lora868.ino) en klik op **Upload**.

### Optie B: Via PlatformIO
```bash
cd C:\6nov26\lilygo_t3_lora868
pio run -t upload
```

---

## 🗺️ 6502 Hardware I/O-Registers (`$A040 – $A043`)

| Adres | Naam | Lezen (`PEEK`) | Schrijven (`POKE`) |
| :--- | :--- | :--- | :--- |
| **`$A040`** | `IO_LORA_STATUS` | **Bit 7 (`128`)**: `1` = RX-byte klaar in 64-byte FIFO<br>**Bit 6 (`64`)**: `1` = TX FIFO heeft ruimte<br>**Bits 5..0 (`0..63`)**: Aantal wachtende bytes in RX FIFO | `POKE $A040, 0` = Wis RX FIFO + Normale Hardware-modus (Pin 30/31)<br>`POKE $A040, 64` = Raw UART Loopback-testmodus<br>`POKE $A040, 128` = **868 MHz LoRa Simulator-modus** (testen zonder draadjes!) |
| **`$A041`** | `IO_LORA_DATA` | Haalt de eerstvolgende ontvangen byte uit de 64-byte hardware RX FIFO | Verzendt 1 byte op 115200 baud via Pin `30` naar de LilyGO (`16-byte TX FIFO` + auto-wait) |
| **`$A042`** | `IO_LORA_RSSI` | Laatst ontvangen 868 MHz **`-RSSI` in dBm** (`0..160`, bijv. `48` betekent **`-48 dBm`**) | Zet/reset de RSSI-waarde handmatig |
| **`$A043`** | `IO_LORA_PKTS` | Teller van ontvangen 868 MHz LoRa-pakketten (`0..255`) | Zet/reset de pakketteller (bijv. `POKE $A043, 0`) |

---

## 📡 Ondersteunde Commando's (vanaf MiniGPU-BASIC of `BRUN "LORA"`)

Stuur een tekstregel afgesloten met `CHR$(10)` (of `CHR$(13)`) naar `$A041`:

- **`AT`** of **`AT+INFO`** — Vraagt status, frequentie (`868.1 MHz`), Spreading Factor, `-RSSI`, pakketteller en LiPo-batterijspanning op.
- **`AT+PING`** — Zendt een `PING #n @868MHz` pakket. Een tweede LilyGO met deze firmware antwoordt automatisch met `PONG` + signaalsterkte!
- **`AT+SEND=Hallo vanaf de 6502!`** (of stuur gewoon een tekstregel zonder `AT+`) — Verzendt direct een 868 MHz LoRa-pakket.
- **`AT+OLED=MiniGPU 6502!`** — Toont jouw tekst uit BASIC rechtstreeks op het **0.96" OLED-scherm** van de LilyGO!
- **`AT+SCAN`** — Scant alle 8 Europese **EU868 LoRa-kanalen** (`868.1` t/m `869.525 MHz`), tekent een live spectrum-analyser op het OLED-scherm en stuurt de dBm-waarden terug naar BASIC.
- **`AT+FREQ=868.3`** — Wisselt de LoRa-frequentie binnen de 863–870 MHz EU-band.
- **`AT+SF=10`** — Zet de Spreading Factor (`SF7` = snelste, `SF12` = maximaal bereik tot > 10 km).
- **`AT+WIFI=MijnSSID,MijnWachtwoord`** — Verbindt met Wi-Fi, haalt de atoomtijd op via NTP (`nl.pool.ntp.org`) en zet via hardware-frame `0xF4` automatisch de 720p HDMI Real-Time Clock (`$A007–$A009`) van de Tang Nano 20K op tijd!
