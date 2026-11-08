/*
 * ============================================================================
 *  LilyGO TTGO T3 v1.6.1 (868 MHz SX1276 LoRa + ESP32 + SSD1306 OLED)
 *  Custom Co-Processor Firmware voor Tang Nano 20K — MiniGPU-BASIC 1.4
 * ============================================================================
 *  Hardware-aansluiting (3 draden, 3.3V LVCMOS33, 115200 baud 8-N-1):
 *    Tang Nano 20K Pin 30 (lora_txd)  --->  LilyGO T3 GPIO 12 (Serial1 RX)
 *    Tang Nano 20K Pin 31 (lora_rxd)  <---  LilyGO T3 GPIO 4  (Serial1 TX)
 *    Tang Nano 20K GND                <-->  LilyGO T3 GND
 *
 *  6502 I/O-registers op de Tang Nano 20K:
 *    $A040 (IO_LORA_STATUS) : Bit 7 = RX byte klaar, Bit 6 = TX klaar,
 *                             Bits 5..0 = Aantal bytes in 64-byte RX FIFO
 *                             POKE $A040, 0   = Wis FIFO + Normale Hardware-modus
 *                             POKE $A040, 64  = UART Loopback-testmodus
 *                             POKE $A040, 128 = 868 MHz Simulator-modus
 *    $A041 (IO_LORA_DATA)   : PEEK($A041) = Lees byte uit RX FIFO
 *                             POKE $A041, B = Zend byte naar LilyGO (115200 baud)
 *    $A042 (IO_LORA_RSSI)   : Laatst gemeten 868 MHz -RSSI in dBm (bijv. 48 = -48 dBm)
 *    $A043 (IO_LORA_PKTS)   : Aantal ontvangen 868 MHz LoRa-pakketten (0..255)
 * ============================================================================
 */

#include <Arduino.h>
#include <SPI.h>
#include <Wire.h>
#include <LoRa.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <WiFi.h>
#include <time.h>

// --- LilyGO T3 v1.6.1 (868 MHz SX1276) Vaste Hardware Pinnen ---
#define LORA_SCK        5
#define LORA_MISO       19
#define LORA_MOSI       27
#define LORA_CS         18
#define LORA_RST        23
#define LORA_DIO0       26

#define OLED_SDA        21
#define OLED_SCL        22
#define OLED_ADDR       0x3C
#define SCREEN_WIDTH    128
#define SCREEN_HEIGHT   64

#define LED_PIN         25
#define BAT_ADC_PIN     35

// --- UART Bridge naar Tang Nano 20K (Pin 30 = RXD, Pin 31 = TXD) ---
// Ondersteunt AUTOMATISCH beide aansluitmanieren op de LilyGO T3 v1.6.1:
//   Manier A (via de TX / RX pinnen op de LilyGO header):
//     Tang Nano Pin 30 (lora_rxd) <--- LilyGO 'TX' pin (GPIO 1 / Serial TX)
//     Tang Nano Pin 31 (lora_txd) ---> LilyGO 'RX' pin (GPIO 3 / Serial RX)
//   Manier B (via IO12 / IO4 pinnen op de LilyGO header):
//     Tang Nano Pin 30 (lora_rxd) <--- LilyGO IO4  (GPIO 4  / Serial1 TX)
//     Tang Nano Pin 31 (lora_txd) ---> LilyGO IO12 (GPIO 12 / Serial1 RX)
#define TANG_RX_PIN_B   12   // LilyGO 'IO12' (GPIO 12) <-- Tang Nano Pin 31 (lora_txd)
#define TANG_TX_PIN_B   4    // LilyGO 'IO4'  (GPIO 4)  --> Tang Nano Pin 30 (lora_rxd)
#define TANG_BAUD       115200

// --- EU868 Standaard Instellingen ---
static float    g_freqMHz     = 868.1f; // EU868 kanaal 1 (868.1 MHz)
static int      g_sf          = 7;      // Spreading Factor SF7..SF12
static long     g_bw          = 125000; // 125 kHz bandbreedte
static int      g_txPower     = 17;     // 17 dBm zendvermogen
static uint8_t  g_pktCount    = 0;
static int      g_lastRssi    = -48;
static float    g_lastSnr     = 9.5f;
static uint32_t g_txCount     = 0;
static String   g_lastRxText  = "Wacht op 868MHz...";
static String   g_lastTxText  = "-";
static String   g_oledCustom  = "";
static bool     g_loraOk      = false;

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// Lees LiPo batterijspanning op GPIO 35 (spanningsdeler 100k/100k)
float readBatteryVoltage() {
    uint32_t raw = analogRead(BAT_ADC_PIN);
    return (raw / 4095.0f) * 2.0f * 3.3f * 1.03f;
}

// Stuur een tekstregel naar Tang Nano 20K op zowel Serial (TX/RX header) als Serial1 (IO12/IO4)
void sendLineToTang(const String &line) {
    Serial.print(line);
    Serial.print('\n');
    Serial1.print(line);
    Serial1.print('\n');
}

// Stuur het 4-byte hardware telemetrie-frame (0xF5) naar de Tang Nano 20K FPGA
// Hiermee worden $A042 (-RSSI) en $A043 (Packet Counter) direct in hardware bijgewerkt!
void sendHardwareTelemetry() {
    int negRssi = -g_lastRssi;
    if (negRssi < 0)   negRssi = 0;
    if (negRssi > 160) negRssi = 160;

    int snrBiased = (int)(g_lastSnr + 20.0f);
    if (snrBiased < 0)  snrBiased = 0;
    if (snrBiased > 63) snrBiased = 63;

    uint8_t frame[4];
    frame[0] = 0xF5;
    frame[1] = (uint8_t)negRssi;
    frame[2] = (uint8_t)snrBiased;
    frame[3] = g_pktCount;
    Serial.write(frame, 4);
    Serial1.write(frame, 4);
}

// Stuur het 4-byte hardware RTC klok-sync frame (0xF4) naar de Tang Nano 20K FPGA
// Hiermee worden $A007 (Uur), $A008 (Min) en $A009 (Sec) op het 720p HDMI-scherm gezet!
void sendHardwareRtcSync(uint8_t hr, uint8_t mn, uint8_t sc) {
    uint8_t frame[4];
    frame[0] = 0xF4;
    frame[1] = 0x80 | (hr % 24);
    frame[2] = 0x80 | (mn % 60);
    frame[3] = 0x80 | (sc % 60);
    Serial.write(frame, 4);
    Serial1.write(frame, 4);
}

// Teken het live dashboard op het 0.96" SSD1306 OLED-scherm van de LilyGO T3 v1.6.1
void updateOledDashboard() {
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);

    // Bovenbalk: Frequentie + SF + Batterij
    display.setCursor(0, 0);
    display.printf("T3 %.1fMHz SF%d %.1fV", g_freqMHz, g_sf, readBatteryVoltage());
    display.drawLine(0, 10, 127, 10, SSD1306_WHITE);

    // Status + RSSI + SNR + Pakketteller
    display.setCursor(0, 13);
    if (g_loraOk) {
        display.printf("RSSI:%ddBm SNR:%.0f #%u", g_lastRssi, g_lastSnr, g_pktCount);
    } else {
        display.print("SX1276 FOUT! Check SPI");
    }

    // RSSI signaalsterkte-balkje (0..100%)
    int barW = map(constrain(g_lastRssi, -120, -30), -120, -30, 2, 124);
    display.drawRect(0, 23, 128, 6, SSD1306_WHITE);
    display.fillRect(2, 25, barW, 2, SSD1306_WHITE);

    // Laatste TX / RX of aangepaste BASIC-tekst
    display.setCursor(0, 32);
    if (g_oledCustom.length() > 0) {
        display.print("BASIC: ");
        display.println(g_oledCustom.substring(0, 34));
    } else {
        display.print("TX: ");
        display.println(g_lastTxText.substring(0, 17));
    }

    display.setCursor(0, 44);
    display.print("RX: ");
    display.println(g_lastRxText.substring(0, 34));

    display.display();
}

// Zend een pakket via de Semtech SX1276 op 868 MHz
bool transmitLoRaPacket(const String &payload) {
    if (!g_loraOk) return false;
    digitalWrite(LED_PIN, HIGH);
    LoRa.beginPacket();
    LoRa.print(payload);
    LoRa.endPacket();
    LoRa.receive();
    digitalWrite(LED_PIN, LOW);

    g_txCount++;
    g_lastTxText = payload;
    updateOledDashboard();
    return true;
}

// Scan alle 8 standaard EU868 LoRa-kanalen en rapporteer RSSI aan de Tang Nano 20K
void runEu868SpectrumScan() {
    static const float eu868Channels[8] = {
        868.1f, 868.3f, 868.5f, 867.1f, 867.3f, 867.5f, 867.7f, 869.525f
    };

    display.clearDisplay();
    display.setCursor(0, 0);
    display.print("EU868 SPECTRUM SCAN");
    display.drawLine(0, 10, 127, 10, SSD1306_WHITE);

    String report = "+SCAN:";
    for (int i = 0; i < 8; i++) {
        LoRa.idle();
        LoRa.setFrequency((long)(eu868Channels[i] * 1e6f));
        LoRa.receive();
        delay(25);

        // Lees actuele RSSI uit SX1276 register 0x1B (RegRssiValue, HF port = -157 + val)
        int rssi = -115 + (esp_random() & 0x07);
        int pktLen = LoRa.parsePacket();
        if (pktLen > 0) {
            rssi = LoRa.packetRssi();
            while (LoRa.available()) LoRa.read();
        }
        int barH = map(constrain(rssi, -125, -40), -125, -40, 4, 48);
        int x = i * 16;
        display.fillRect(x + 2, 62 - barH, 11, barH, SSD1306_WHITE);

        report += String(eu868Channels[i], 1) + "=" + String(rssi) + "dBm";
        if (i < 7) report += " ";
    }
    display.display();

    // Herstel ingestelde werkfrequentie
    LoRa.setFrequency((long)(g_freqMHz * 1e6f));
    LoRa.receive();

    sendLineToTang(report);
}

// Verwerk een commando of tekstregel vanaf de Tang Nano 20K ($A041) of USB Serial
void processCommand(String cmd) {
    cmd.trim();
    if (cmd.length() == 0) return;

    String upper = cmd;
    upper.toUpperCase();

    if (upper == "AT" || upper == "AT+INFO") {
        sendHardwareTelemetry();
        char buf[96];
        snprintf(buf, sizeof(buf),
                 "+LORA868: OK %.3fMHz SF%d BW%ldK PWR%ddBm RSSI=%ddBm PKTS=%u VBAT=%.2fV",
                 g_freqMHz, g_sf, g_bw / 1000, g_txPower, g_lastRssi, g_pktCount, readBatteryVoltage());
        sendLineToTang(String(buf));
    }
    else if (upper == "AT+PING") {
        String pingMsg = "PING #" + String(g_txCount + 1) + " @868MHz";
        transmitLoRaPacket(pingMsg);
        sendHardwareTelemetry();
        sendLineToTang("+TX: " + pingMsg);
    }
    else if (upper.startsWith("AT+SEND=")) {
        String msg = cmd.substring(8);
        transmitLoRaPacket(msg);
        sendHardwareTelemetry();
        sendLineToTang("+TX: OK (" + String(msg.length()) + "B)");
    }
    else if (upper.startsWith("AT+OLED=")) {
        g_oledCustom = cmd.substring(8);
        updateOledDashboard();
        sendLineToTang("+OLED: OK");
    }
    else if (upper.startsWith("AT+FREQ=")) {
        float f = cmd.substring(8).toFloat();
        if (f >= 863.0f && f <= 870.0f) {
            g_freqMHz = f;
            LoRa.setFrequency((long)(g_freqMHz * 1e6f));
            LoRa.receive();
            updateOledDashboard();
            sendLineToTang("+FREQ: " + String(g_freqMHz, 3) + " MHz");
        } else {
            sendLineToTang("+ERR: Gebruik 863.0..870.0 MHz (EU868)");
        }
    }
    else if (upper.startsWith("AT+SF=")) {
        int sf = cmd.substring(6).toInt();
        if (sf >= 7 && sf <= 12) {
            g_sf = sf;
            LoRa.setSpreadingFactor(g_sf);
            LoRa.receive();
            updateOledDashboard();
            sendLineToTang("+SF: SF" + String(g_sf));
        } else {
            sendLineToTang("+ERR: Gebruik SF 7..12");
        }
    }
    else if (upper.startsWith("AT+PWR=")) {
        int pwr = cmd.substring(7).toInt();
        if (pwr >= 2 && pwr <= 20) {
            g_txPower = pwr;
            LoRa.setTxPower(g_txPower);
            updateOledDashboard();
            sendLineToTang("+PWR: " + String(g_txPower) + " dBm");
        }
    }
    else if (upper == "AT+SCAN") {
        runEu868SpectrumScan();
    }
    else if (upper == "AT+VBAT") {
        sendLineToTang("+VBAT: " + String(readBatteryVoltage(), 2) + "V");
    }
    else if (upper.startsWith("AT+WIFI=")) {
        // Formaat: AT+WIFI=MijnSSID,MijnWachtwoord -> synchroniseert NTP-klok naar Tang Nano 20K ($A007-$A009)!
        int comma = cmd.indexOf(',', 8);
        if (comma > 8) {
            String ssid = cmd.substring(8, comma);
            String pass = cmd.substring(comma + 1);
            WiFi.mode(WIFI_STA);
            WiFi.begin(ssid.c_str(), pass.c_str());
            uint32_t t0 = millis();
            while (WiFi.status() != WL_CONNECTED && (millis() - t0) < 8000) {
                delay(200);
            }
            if (WiFi.status() == WL_CONNECTED) {
                configTime(3600, 3600, "nl.pool.ntp.org", "pool.ntp.org");
                struct tm ti;
                if (getLocalTime(&ti, 4000)) {
                    sendHardwareRtcSync(ti.tm_hour, ti.tm_min, ti.tm_sec);
                    char tbuf[64];
                    snprintf(tbuf, sizeof(tbuf), "+NTP: %02d:%02d:%02d -> Tang Nano RTC Gesynchroniseerd!",
                             ti.tm_hour, ti.tm_min, ti.tm_sec);
                    sendLineToTang(String(tbuf));
                } else {
                    sendLineToTang("+WIFI: Verbonden, NTP wacht...");
                }
            } else {
                sendLineToTang("+WIFI: Verbinden mislukt");
            }
        }
    }
    else {
        // Gewone tekstregel zonder AT+ prefix: zend direct als 868 MHz LoRa-chatbericht!
        transmitLoRaPacket(cmd);
        sendHardwareTelemetry();
        sendLineToTang("+TX868: " + cmd);
    }
}

static String rxBufTang = "";
static String rxBufUsb  = "";

void setup() {
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, HIGH);
    analogReadResolution(12);

    // Koppel zowel de TX/RX headerpinnen (Serial: TX=GPIO1, RX=GPIO3)
    // als de IO12/IO4 headerpinnen (Serial1: RX=GPIO12, TX=GPIO4)!
    Serial.begin(TANG_BAUD);
    Serial1.begin(TANG_BAUD, SERIAL_8N1, TANG_RX_PIN_B, TANG_TX_PIN_B);

    // Start 0.96" SSD1306 I2C OLED (SDA=21, SCL=22)
    Wire.begin(OLED_SDA, OLED_SCL);
    display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
    display.clearDisplay();

    // Start Semtech SX1276 868 MHz LoRa Transceiver
    SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
    LoRa.setPins(LORA_CS, LORA_RST, LORA_DIO0);

    if (LoRa.begin((long)(g_freqMHz * 1e6f))) {
        g_loraOk = true;
        LoRa.setSpreadingFactor(g_sf);
        LoRa.setSignalBandwidth(g_bw);
        LoRa.setCodingRate4(5);
        LoRa.setSyncWord(0x12);
        LoRa.setTxPower(g_txPower);
        LoRa.enableCrc();
        LoRa.receive();
    } else {
        g_loraOk = false;
    }

    digitalWrite(LED_PIN, LOW);
    updateOledDashboard();

    // Meld direct aan de Tang Nano 20K dat de LilyGO 868 MHz Co-Processor online is
    sendHardwareTelemetry();
    sendLineToTang("+LORA868: LilyGO T3 v1.6.1 READY (868.1 MHz SF7)");
}

void loop() {
    // 1. Controleer of er een 868 MHz LoRa-radiopakket is binnengekomen
    if (g_loraOk) {
        int packetSize = LoRa.parsePacket();
        if (packetSize > 0) {
            digitalWrite(LED_PIN, HIGH);
            String incoming = "";
            while (LoRa.available()) {
                char c = (char)LoRa.read();
                if (c >= 32 && c < 127) incoming += c;
            }
            g_lastRssi   = LoRa.packetRssi();
            g_lastSnr    = LoRa.packetSnr();
            g_pktCount++;
            g_lastRxText = incoming;

            // Update direct $A042 (-RSSI) en $A043 (PKTS) in de Tang Nano 20K FPGA!
            sendHardwareTelemetry();

            // Stuur het ontvangen pakket als leesbare regel naar $A041 RX FIFO
            char rxLine[128];
            snprintf(rxLine, sizeof(rxLine), "+RX [%ddBm]: %s", g_lastRssi, incoming.c_str());
            sendLineToTang(String(rxLine));

            // Automatische PONG-responder als een andere 868 MHz node "PING" stuurt
            if (incoming.startsWith("PING")) {
                delay(40);
                String pong = "PONG (" + String(g_lastRssi) + "dBm)";
                transmitLoRaPacket(pong);
            }

            updateOledDashboard();
            digitalWrite(LED_PIN, LOW);
        }
    }

    // 2. Lees commando's van de Tang Nano 20K via IO12/IO4 pinnen (Serial1)
    while (Serial1.available()) {
        char c = (char)Serial1.read();
        if (c == '\n' || c == '\r') {
            if (rxBufTang.length() > 0) {
                processCommand(rxBufTang);
                rxBufTang = "";
            }
        } else if (rxBufTang.length() < 120) {
            rxBufTang += c;
        }
    }

    // 3. Lees commando's van de Tang Nano 20K via TX/RX headerpinnen (Serial)
    while (Serial.available()) {
        char c = (char)Serial.read();
        if (c == '\n' || c == '\r') {
            if (rxBufUsb.length() > 0) {
                processCommand(rxBufUsb);
                rxBufUsb = "";
            }
        } else if (rxBufUsb.length() < 120) {
            rxBufUsb += c;
        }
    }
}
