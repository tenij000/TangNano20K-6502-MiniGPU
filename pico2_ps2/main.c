/*
 * pico2_usb_ps2_tangnano - USB-Host to 3.3V PS/2 Set 2 Keyboard + Hardware Mouse Bridge
 * Speciaal voor Raspberry Pi Pico 2 (RP2350) / Pico 1 (RP2040) -> Tang Nano 20K
 *
 * Ondersteunt gelijktijdig:
 *   - USB-Toetsenborden (6KRO, NKRO gaming-toetsenborden, multimedia-toetsenborden)
 *   - USB-Muizen (8-bit, 12-bit en 16-bit muizen: Links, Rechts, Midden + X/Y beweging)
 *   - Draadloze 2.4GHz Toetsenbord + Muis sets op 1 USB-dongle!
 *   - USB-Hubs (sluit zowel een los USB-toetsenbord als een losse USB-muis aan op 1 Pico 2!)
 *
 * 4-Draads Aansluiting tussen Pico 2 en Tang Nano 20K (3.3V Direct, geen extra draden nodig!):
 *   1. Pico 2 Pin 40 (VBUS)  <---> Tang Nano 20K 5V     (Voedt Pico 2 + USB-toetsenbord/muis!)
 *   2. Pico 2 Pin 38 (GND)   <---> Tang Nano 20K GND    (Gezamenlijke massa)
 *   3. Pico 2 GP0    (Pin 1) <---> Tang Nano 20K Pin 73 (ps2_data) [ook actief op GP11 & GP14]
 *   4. Pico 2 GP1    (Pin 2) <---> Tang Nano 20K Pin 74 (ps2_clk)  [ook actief op GP12 & GP15]
 *
 * 3-Byte Muis-Protocol over dezelfde PS/2-lijn naar Tang Nano 20K (ps2_keyboard.v -> $A00C-$A00F):
 *   - Byte 0: 0xF8 | buttons[2:0]  (Bit 0 = Links, Bit 1 = Rechts, Bit 2 = Midden)
 *   - Byte 1: int8_t dx            (-127..+127 pixels X-verplaatsing)
 *   - Byte 2: int8_t dy            (-127..+127 pixels Y-verplaatsing)
 *
 * LED-status op Pico 2 (GP25):
 *   - Korte hartslag (1x per seconde): Firmware draait, wacht op USB-toetsenbord of USB-muis
 *   - Vast GROEN aan:                  USB-toetsenbord en/of USB-muis herkend en klaar!
 *   - Knippert bij toets of muis:      PS/2 scancode of muispakket verstuurd naar Tang Nano 20K!
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

#include "pico/stdlib.h"
#include "hardware/gpio.h"
#include "bsp/board_api.h"
#include "tusb.h"

// Drie parallelle 3.3V PS/2 pin-paren (kies welk paar het handigst uitkomt!)
static const uint8_t PS2_DATA_PINS[] = { 0, 11, 14 }; // GP0 (Pin 1), GP11 (Pin 15), GP14 (Pin 19) -> Tang Nano Pin 73
static const uint8_t PS2_CLK_PINS[]  = { 1, 12, 15 }; // GP1 (Pin 2), GP12 (Pin 16), GP15 (Pin 20) -> Tang Nano Pin 74
#define NUM_PIN_PAIRS 3

#ifdef PICO_DEFAULT_LED_PIN
#define LED_PIN PICO_DEFAULT_LED_PIN
#else
#define LED_PIN 25
#endif

// Ringbuffer voor te versturen PS/2 bytes
#define PS2_QUEUE_SIZE 256
static uint8_t  ps2_queue[PS2_QUEUE_SIZE];
static uint16_t ps2_q_head = 0;
static uint16_t ps2_q_tail = 0;

static uint32_t led_blink_off_until = 0;

static void ps2_enqueue(uint8_t b) {
    uint16_t next = (ps2_q_head + 1) & (PS2_QUEUE_SIZE - 1);
    if (next != ps2_q_tail) {
        ps2_queue[ps2_q_head] = b;
        ps2_q_head = next;
    }
}

// Open-drain met actieve 3.3V stijgflank-boost (immuun voor draadcapaciteit & RP2350-E9!):
static inline void set_data_line(bool high) {
    if (high) {
        for (int i = 0; i < NUM_PIN_PAIRS; i++) {
            uint8_t pin = PS2_DATA_PINS[i];
            gpio_put(pin, 1);
            gpio_set_dir(pin, GPIO_OUT);
        }
        busy_wait_us_32(1);
        for (int i = 0; i < NUM_PIN_PAIRS; i++) {
            uint8_t pin = PS2_DATA_PINS[i];
            gpio_set_dir(pin, GPIO_IN);
            gpio_put(pin, 0);
        }
    } else {
        for (int i = 0; i < NUM_PIN_PAIRS; i++) {
            uint8_t pin = PS2_DATA_PINS[i];
            gpio_put(pin, 0);
            gpio_set_dir(pin, GPIO_OUT);
        }
    }
}

static inline void set_clk_line(bool high) {
    if (high) {
        for (int i = 0; i < NUM_PIN_PAIRS; i++) {
            uint8_t pin = PS2_CLK_PINS[i];
            gpio_put(pin, 1);
            gpio_set_dir(pin, GPIO_OUT);
        }
        busy_wait_us_32(1);
        for (int i = 0; i < NUM_PIN_PAIRS; i++) {
            uint8_t pin = PS2_CLK_PINS[i];
            gpio_set_dir(pin, GPIO_IN);
            gpio_put(pin, 0);
        }
    } else {
        for (int i = 0; i < NUM_PIN_PAIRS; i++) {
            uint8_t pin = PS2_CLK_PINS[i];
            gpio_put(pin, 0);
            gpio_set_dir(pin, GPIO_OUT);
        }
    }
}

static void ps2_gpio_init_all(void) {
    for (int i = 0; i < NUM_PIN_PAIRS; i++) {
        uint8_t d = PS2_DATA_PINS[i];
        uint8_t c = PS2_CLK_PINS[i];

        gpio_init(d);
        gpio_pull_up(d);
        gpio_put(d, 1);
        gpio_set_dir(d, GPIO_OUT);
        busy_wait_us_32(2);
        gpio_set_dir(d, GPIO_IN);
        gpio_put(d, 0);

        gpio_init(c);
        gpio_pull_up(c);
        gpio_put(c, 1);
        gpio_set_dir(c, GPIO_OUT);
        busy_wait_us_32(2);
        gpio_set_dir(c, GPIO_IN);
        gpio_put(c, 0);
    }
    gpio_init(LED_PIN);
    gpio_set_dir(LED_PIN, GPIO_OUT);
    gpio_put(LED_PIN, 0);
}

// Stuur één 11-bits PS/2 frame: Start(0), D0..D7 (LSB eerst), Odd Parity, Stop(1)
static void ps2_tx_byte_blocking(uint8_t data) {
    uint8_t ones = 0;
    for (int i = 0; i < 8; i++) {
        if ((data >> i) & 1) ones++;
    }
    bool odd_parity = ((ones & 1) == 0);

    uint16_t frame = 0;
    frame |= (0 << 0);                          // Bit 0: Start bit (0)
    frame |= ((uint16_t)data << 1);             // Bit 1..8: Data D0..D7
    frame |= ((odd_parity ? 1 : 0) << 9);       // Bit 9: Odd Parity bit
    frame |= (1 << 10);                         // Bit 10: Stop bit (1)

    for (int bit = 0; bit < 11; bit++) {
        bool b = (frame >> bit) & 1;
        set_data_line(b);
        busy_wait_us_32(20);                    // Data setup vóór neergaande klokflank
        set_clk_line(false);                    // Neergaande flank (FPGA leest data)
        busy_wait_us_32(30);                    // Klok laag
        set_clk_line(true);                     // Opgaande flank
        busy_wait_us_32(15);
    }

    // Laat beide lijnen hoog na het Stop-bit + korte rusttijd tussen bytes
    set_data_line(true);
    set_clk_line(true);
    busy_wait_us_32(80);
}

// USB HID Keycode (0x00..0x7F) -> PS/2 Set 2 Scancode tabel
#define EXT(sc) ((sc) | 0x80)

static const uint8_t hid_to_ps2_set2[128] = {
    [0x04] = 0x1C, // A
    [0x05] = 0x32, // B
    [0x06] = 0x21, // C
    [0x07] = 0x23, // D
    [0x08] = 0x24, // E
    [0x09] = 0x2B, // F
    [0x0A] = 0x34, // G
    [0x0B] = 0x33, // H
    [0x0C] = 0x43, // I
    [0x0D] = 0x3B, // J
    [0x0E] = 0x42, // K
    [0x0F] = 0x4B, // L
    [0x10] = 0x3A, // M
    [0x11] = 0x31, // N
    [0x12] = 0x44, // O
    [0x13] = 0x4D, // P
    [0x14] = 0x15, // Q
    [0x15] = 0x2D, // R
    [0x16] = 0x1B, // S
    [0x17] = 0x2C, // T
    [0x18] = 0x3C, // U
    [0x19] = 0x2A, // V
    [0x1A] = 0x1D, // W
    [0x1B] = 0x22, // X
    [0x1C] = 0x35, // Y
    [0x1D] = 0x1A, // Z

    [0x1E] = 0x16, // 1 !
    [0x1F] = 0x1E, // 2 @
    [0x20] = 0x26, // 3 #
    [0x21] = 0x25, // 4 $
    [0x22] = 0x2E, // 5 %
    [0x23] = 0x36, // 6 ^
    [0x24] = 0x3D, // 7 &
    [0x25] = 0x3E, // 8 *
    [0x26] = 0x46, // 9 (
    [0x27] = 0x45, // 0 )

    [0x28] = 0x5A, // Enter
    [0x29] = 0x76, // Escape
    [0x2A] = 0x66, // Backspace
    [0x2B] = 0x0D, // Tab
    [0x2C] = 0x29, // Space
    [0x2D] = 0x4E, // - _
    [0x2E] = 0x55, // = +
    [0x2F] = 0x54, // [ {
    [0x30] = 0x5B, // ] }
    [0x31] = 0x5D, // \ |
    [0x32] = 0x5D, // Non-US # ~ -> \ |
    [0x33] = 0x4C, // ; :
    [0x34] = 0x52, // ' "
    [0x35] = 0x0E, // ` ~
    [0x36] = 0x41, // , <
    [0x37] = 0x49, // . >
    [0x38] = 0x4A, // / ?
    [0x39] = 0x58, // Caps Lock

    [0x3A] = 0x05, // F1
    [0x3B] = 0x06, // F2
    [0x3C] = 0x04, // F3
    [0x3D] = 0x0C, // F4
    [0x3E] = 0x03, // F5
    [0x3F] = 0x0B, // F6
    [0x40] = 0x83, // F7 (0x83 zonder E0, zie functie hieronder)
    [0x41] = 0x0A, // F8
    [0x42] = 0x01, // F9
    [0x43] = 0x09, // F10
    [0x44] = 0x78, // F11
    [0x45] = 0x07, // F12

    [0x4C] = 0x66, // Delete -> Backspace
    [0x4F] = EXT(0x74), // Pijl Rechts (E0 74)
    [0x50] = EXT(0x6B), // Pijl Links  (E0 6B)
    [0x51] = EXT(0x72), // Pijl Omlaag (E0 72)
    [0x52] = EXT(0x75), // Pijl Omhoog (E0 75)

    [0x54] = EXT(0x4A), // Numpad / (E0 4A)
    [0x55] = 0x7C,      // Numpad *
    [0x56] = 0x7B,      // Numpad -
    [0x57] = 0x79,      // Numpad +
    [0x58] = EXT(0x5A), // Numpad Enter (E0 5A)
    [0x59] = 0x69,      // Numpad 1
    [0x5A] = 0x72,      // Numpad 2
    [0x5B] = 0x7A,      // Numpad 3
    [0x5C] = 0x6B,      // Numpad 4
    [0x5D] = 0x73,      // Numpad 5
    [0x5E] = 0x74,      // Numpad 6
    [0x5F] = 0x6C,      // Numpad 7
    [0x60] = 0x75,      // Numpad 8
    [0x61] = 0x7D,      // Numpad 9
    [0x62] = 0x70,      // Numpad 0
    [0x63] = 0x71,      // Numpad .
    [0x64] = 0x61,      // Non-US \ |
};

static void send_hid_key_ps2(uint8_t hid_code, bool pressed) {
    if (hid_code == 0 || hid_code >= 128) return;

    if (hid_code == 0x3F) { // F6
        if (!pressed) ps2_enqueue(0xF0);
        ps2_enqueue(0x0B);
        return;
    }
    if (hid_code == 0x40) { // F7 (0x83 zonder E0!)
        if (!pressed) ps2_enqueue(0xF0);
        ps2_enqueue(0x83);
        return;
    }

    uint8_t mapped = hid_to_ps2_set2[hid_code];
    if (mapped == 0) return;

    bool is_ext = (mapped & 0x80) != 0;
    uint8_t sc  = mapped & 0x7F;

    if (is_ext) ps2_enqueue(0xE0);
    if (!pressed) ps2_enqueue(0xF0);
    ps2_enqueue(sc);
}

static const uint8_t mod_ps2_sc[8]  = { 0x14, 0x12, 0x11, 0x1F, 0x14, 0x59, 0x11, 0x27 };
static const bool    mod_ps2_ext[8] = { false, false, false, true, true, false, true, true };

static void send_modifier_ps2(uint8_t bit, bool pressed) {
    if (mod_ps2_ext[bit]) ps2_enqueue(0xE0);
    if (!pressed)         ps2_enqueue(0xF0);
    ps2_enqueue(mod_ps2_sc[bit]);
}

// Huidige toetsenbordstatus & Typematic auto-repeat
static uint8_t  prev_modifier   = 0;
static uint8_t  prev_keys[6]    = {0};
static uint8_t  prev_nkro[16]   = {0};
static uint8_t  repeat_hid_key  = 0;
static uint32_t repeat_next_ms  = 0;
static uint8_t  mounted_devices = 0;

// Muis-accumulator & knoppenstatus (voorkomt PS/2 wachtrij-vertraging bij 500/1000Hz muizen!)
static int32_t  mouse_acc_dx          = 0;
static int32_t  mouse_acc_dy          = 0;
static uint8_t  mouse_cur_buttons     = 0;
static uint8_t  mouse_prev_buttons    = 0;
static uint8_t  mouse_sent_buttons    = 0;
static uint8_t  mouse_btn_press_latch = 0;

#define MAX_REPORT 8
typedef struct {
    bool     valid;
    uint8_t  report_id;
    uint16_t btn_bit_offset;
    uint16_t x_bit_offset;
    uint16_t y_bit_offset;
    uint8_t  xy_bit_size;
} mouse_layout_t;

static struct {
    uint8_t               report_count;
    tuh_hid_report_info_t report_info[MAX_REPORT];
    bool                  is_keyboard_itf;
    bool                  is_mouse_itf;
    bool                  has_report_id;
    mouse_layout_t        mouse_layouts[MAX_REPORT];
} hid_info[CFG_TUH_HID];

static bool key_in_array(const uint8_t *arr, int count, uint8_t code) {
    for (int i = 0; i < count; i++) {
        if (arr[i] == code) return true;
    }
    return false;
}

static void process_modifiers(uint8_t new_mod) {
    uint8_t mod_diff = new_mod ^ prev_modifier;
    for (uint8_t bit = 0; bit < 8; bit++) {
        if (mod_diff & (1 << bit)) {
            bool pressed = (new_mod & (1 << bit)) != 0;
            send_modifier_ps2(bit, pressed);
            led_blink_off_until = board_millis() + 50;
        }
    }
    prev_modifier = new_mod;
}

static void process_6kro_keys(uint8_t modifier, const uint8_t *keys6) {
    for (int i = 0; i < 6; i++) {
        if (keys6[i] == 0x01) return; // ErrorRollOver
    }

    uint32_t now = board_millis();
    process_modifiers(modifier);

    // 1. Losgelaten toetsen (Break)
    for (int i = 0; i < 6; i++) {
        uint8_t old_k = prev_keys[i];
        if (old_k > 3 && !key_in_array(keys6, 6, old_k)) {
            send_hid_key_ps2(old_k, false);
            led_blink_off_until = now + 50;
            if (repeat_hid_key == old_k) repeat_hid_key = 0;
        }
    }

    // 2. Nieuw ingedrukte toetsen (Make)
    for (int i = 0; i < 6; i++) {
        uint8_t new_k = keys6[i];
        if (new_k > 3 && !key_in_array(prev_keys, 6, new_k)) {
            send_hid_key_ps2(new_k, true);
            led_blink_off_until = now + 50;
            if (new_k != 0x39) {
                repeat_hid_key = new_k;
                repeat_next_ms = now + 450;
            }
        }
    }

    memcpy(prev_keys, keys6, 6);
}

static void process_nkro_bitmap(uint8_t modifier, const uint8_t *bitmap, uint16_t bmlen) {
    uint32_t now = board_millis();
    process_modifiers(modifier);

    uint16_t n = (bmlen < 16) ? bmlen : 16;
    for (uint16_t i = 0; i < n; i++) {
        uint8_t diff = bitmap[i] ^ prev_nkro[i];
        if (diff) {
            for (uint8_t bit = 0; bit < 8; bit++) {
                if (diff & (1 << bit)) {
                    uint8_t hid_code = (uint8_t)(i * 8 + bit);
                    bool pressed = (bitmap[i] & (1 << bit)) != 0;
                    send_hid_key_ps2(hid_code, pressed);
                    led_blink_off_until = now + 50;
                    if (pressed && hid_code != 0x39) {
                        repeat_hid_key = hid_code;
                        repeat_next_ms = now + 450;
                    } else if (!pressed && repeat_hid_key == hid_code) {
                        repeat_hid_key = 0;
                    }
                }
            }
        }
    }
    memcpy(prev_nkro, bitmap, n);
}

// Hulpfuncties om willekeurige bitvelden (8-bit, 12-bit, 16-bit) uit een muis-report te lezen
static uint32_t extract_unsigned_bits(const uint8_t *buf, uint16_t len_bytes, uint16_t bit_offset, uint8_t bit_size) {
    if (bit_size == 0 || bit_size > 24) return 0;
    uint32_t val = 0;
    for (uint8_t b = 0; b < bit_size; b++) {
        uint16_t pos = bit_offset + b;
        uint16_t byte_idx = pos >> 3;
        if (byte_idx < len_bytes) {
            if ((buf[byte_idx] >> (pos & 7)) & 1) {
                val |= (1u << b);
            }
        }
    }
    return val;
}

static int32_t extract_signed_bits(const uint8_t *buf, uint16_t len_bytes, uint16_t bit_offset, uint8_t bit_size) {
    if (bit_size == 0 || bit_size > 24) return 0;
    uint32_t u = extract_unsigned_bits(buf, len_bytes, bit_offset, bit_size);
    uint32_t sign_bit = 1u << (bit_size - 1);
    if (u & sign_bit) {
        u |= (~0u) << bit_size;
    }
    return (int32_t)u;
}

// Parseert het ruwe HID Report Descriptor op zoek naar Muis Knoppen (Usage Page 0x09)
// en Muis X/Y-assen (Usage Page 0x01, Usage 0x30 & 0x31), inclusief 8-bit, 12-bit en 16-bit muizen!
static bool parse_mouse_descriptor_layouts(uint8_t instance, const uint8_t *desc, uint16_t desc_len) {
    memset(hid_info[instance].mouse_layouts, 0, sizeof(hid_info[instance].mouse_layouts));
    hid_info[instance].has_report_id = false;

    if (!desc || desc_len < 4) return false;

    uint16_t usage_page   = 0;
    uint32_t report_size  = 0;
    uint32_t report_count = 0;
    uint8_t  report_id    = 0;

    uint16_t usages[16];
    uint8_t  usage_cnt = 0;

    uint8_t  rpt_ids[MAX_REPORT]  = {0};
    uint16_t bit_offs[MAX_REPORT] = {0};
    uint8_t  num_rpts             = 1; // slot 0 voor report_id 0

    bool found_any_mouse = false;

    uint16_t i = 0;
    while (i < desc_len) {
        uint8_t hdr = desc[i++];
        if (hdr == 0xFE) { // Long item
            if (i + 1 < desc_len) i += 2 + desc[i];
            else break;
            continue;
        }
        uint8_t bSize = hdr & 0x03;
        if (bSize == 3) bSize = 4;
        uint8_t bType = (hdr >> 2) & 0x03;
        uint8_t bTag  = (hdr >> 4) & 0x0F;

        if (i + bSize > desc_len) break;
        uint32_t val = 0;
        for (uint8_t k = 0; k < bSize; k++) {
            val |= ((uint32_t)desc[i + k]) << (8 * k);
        }
        i += bSize;

        if (bType == 1) { // Global
            if (bTag == 0x0) usage_page   = (uint16_t)val;
            if (bTag == 0x7) report_size  = val;
            if (bTag == 0x8) {
                report_id = (uint8_t)val;
                hid_info[instance].has_report_id = true;
            }
            if (bTag == 0x9) report_count = val;
        } else if (bType == 2) { // Local
            if (bTag == 0x0 && usage_cnt < 16) {
                usages[usage_cnt++] = (uint16_t)val;
            }
        } else if (bType == 0) { // Main
            if (bTag == 0x8) { // Input
                // Zoek of maak slot voor dit report_id
                int slot = -1;
                for (uint8_t s = 0; s < num_rpts; s++) {
                    if (rpt_ids[s] == report_id) { slot = s; break; }
                }
                if (slot < 0 && num_rpts < MAX_REPORT) {
                    slot = num_rpts++;
                    rpt_ids[slot]  = report_id;
                    bit_offs[slot] = 0;
                }

                if (slot >= 0 && (val & 0x01) == 0) { // Data (niet Constant)
                    mouse_layout_t *ml = &hid_info[instance].mouse_layouts[slot];
                    ml->report_id = report_id;

                    if (usage_page == 0x09 && ml->btn_bit_offset == 0 && bit_offs[slot] == 0) {
                        ml->btn_bit_offset = bit_offs[slot];
                    } else if (usage_page == 0x09 && !ml->valid) {
                        ml->btn_bit_offset = bit_offs[slot];
                    }

                    if (usage_page == 0x01 && (val & 0x04) != 0) { // Generic Desktop + Relative (X/Y)
                        int x_idx = -1, y_idx = -1;
                        for (uint8_t u = 0; u < usage_cnt; u++) {
                            if (usages[u] == 0x30 && x_idx < 0) x_idx = u;
                            if (usages[u] == 0x31 && y_idx < 0) y_idx = u;
                        }
                        if (x_idx >= 0 && y_idx >= 0 && report_size >= 8 && report_size <= 16) {
                            ml->x_bit_offset = bit_offs[slot] + (uint16_t)(x_idx * report_size);
                            ml->y_bit_offset = bit_offs[slot] + (uint16_t)(y_idx * report_size);
                            ml->xy_bit_size  = (uint8_t)report_size;
                            ml->valid        = true;
                            found_any_mouse  = true;
                        }
                    }
                }
                if (slot >= 0) {
                    bit_offs[slot] += (uint16_t)(report_size * report_count);
                }
            }
            usage_cnt = 0; // Wis lokale usages na elk Main item
        }
    }
    return found_any_mouse;
}

static bool descriptor_has_keyboard(uint8_t const* desc, uint16_t len) {
    if (!desc || len < 4) return false;
    for (uint16_t i = 0; i + 3 < len; i++) {
        if (desc[i] == 0x05 && desc[i+1] == 0x01 &&
            desc[i+2] == 0x09 && desc[i+3] == 0x06) {
            return true;
        }
    }
    return false;
}

static bool descriptor_has_mouse(uint8_t const* desc, uint16_t len) {
    if (!desc || len < 4) return false;
    for (uint16_t i = 0; i + 3 < len; i++) {
        if (desc[i] == 0x05 && desc[i+1] == 0x01 &&
            desc[i+2] == 0x09 && desc[i+3] == 0x02) {
            return true;
        }
    }
    return false;
}

static void record_mouse_movement(uint8_t buttons, int32_t dx, int32_t dy) {
    uint8_t new_btn       = buttons & 0x07;
    uint8_t newly_pressed = new_btn & ~mouse_prev_buttons;
    mouse_btn_press_latch |= newly_pressed;
    mouse_prev_buttons    = new_btn;
    mouse_cur_buttons     = new_btn;

    mouse_acc_dx += dx;
    mouse_acc_dy += dy;
    led_blink_off_until = board_millis() + 30;
}

// TinyUSB Host Callbacks
void tuh_hid_mount_cb(uint8_t dev_addr, uint8_t instance, uint8_t const* desc_report, uint16_t desc_len) {
    uint8_t const itf_protocol = tuh_hid_interface_protocol(dev_addr, instance);

    hid_info[instance].report_count = tuh_hid_parse_report_descriptor(
        hid_info[instance].report_info, MAX_REPORT, desc_report, desc_len
    );

    bool has_mouse_layout = parse_mouse_descriptor_layouts(instance, desc_report, desc_len);

    bool is_kbd   = (itf_protocol == HID_ITF_PROTOCOL_KEYBOARD) || descriptor_has_keyboard(desc_report, desc_len);
    bool is_mouse = (itf_protocol == HID_ITF_PROTOCOL_MOUSE)    || descriptor_has_mouse(desc_report, desc_len) || has_mouse_layout;

    for (uint8_t i = 0; i < hid_info[instance].report_count; i++) {
        if (hid_info[instance].report_info[i].usage_page == HID_USAGE_PAGE_DESKTOP) {
            if (hid_info[instance].report_info[i].usage == HID_USAGE_DESKTOP_KEYBOARD) is_kbd = true;
            if (hid_info[instance].report_info[i].usage == HID_USAGE_DESKTOP_MOUSE ||
                hid_info[instance].report_info[i].usage == HID_USAGE_DESKTOP_POINTER)  is_mouse = true;
        }
    }

    hid_info[instance].is_keyboard_itf = is_kbd;
    hid_info[instance].is_mouse_itf    = is_mouse;

    if (is_kbd || is_mouse) {
        mounted_devices++;
    }
    tuh_hid_receive_report(dev_addr, instance);
}

void tuh_hid_umount_cb(uint8_t dev_addr, uint8_t instance) {
    (void)dev_addr;
    if ((hid_info[instance].is_keyboard_itf || hid_info[instance].is_mouse_itf) && mounted_devices > 0) {
        mounted_devices--;
    }
    hid_info[instance].is_keyboard_itf = false;
    hid_info[instance].is_mouse_itf    = false;
    if (mounted_devices == 0) {
        repeat_hid_key        = 0;
        prev_modifier         = 0;
        mouse_cur_buttons     = 0;
        mouse_prev_buttons    = 0;
        mouse_btn_press_latch = 0;
        memset(prev_keys, 0, sizeof(prev_keys));
        memset(prev_nkro, 0, sizeof(prev_nkro));
    }
}

void tuh_hid_report_received_cb(uint8_t dev_addr, uint8_t instance, uint8_t const* report, uint16_t len) {
    if (len == 0) {
        tuh_hid_receive_report(dev_addr, instance);
        return;
    }

    uint8_t const itf_protocol = tuh_hid_interface_protocol(dev_addr, instance);
    const uint8_t *p = report;
    uint16_t plen = len;
    uint8_t rpt_id = 0;

    // 1. Check of er een geparste Mouse Layout matcht (met of zonder Report-ID)
    if (hid_info[instance].has_report_id) {
        rpt_id = p[0];
        for (int s = 0; s < MAX_REPORT; s++) {
            mouse_layout_t *ml = &hid_info[instance].mouse_layouts[s];
            if (ml->valid && ml->report_id == rpt_id && plen > 1) {
                const uint8_t *mp = p + 1;
                uint16_t mlen = plen - 1;
                uint8_t btns = (uint8_t)extract_unsigned_bits(mp, mlen, ml->btn_bit_offset, 3);
                int32_t dx   = extract_signed_bits(mp, mlen, ml->x_bit_offset, ml->xy_bit_size);
                int32_t dy   = extract_signed_bits(mp, mlen, ml->y_bit_offset, ml->xy_bit_size);
                record_mouse_movement(btns, dx, dy);
                tuh_hid_receive_report(dev_addr, instance);
                return;
            }
        }
    } else {
        mouse_layout_t *ml = &hid_info[instance].mouse_layouts[0];
        if (ml->valid && (!hid_info[instance].is_keyboard_itf || itf_protocol == HID_ITF_PROTOCOL_MOUSE)) {
            uint8_t btns = (uint8_t)extract_unsigned_bits(p, plen, ml->btn_bit_offset, 3);
            int32_t dx   = extract_signed_bits(p, plen, ml->x_bit_offset, ml->xy_bit_size);
            int32_t dy   = extract_signed_bits(p, plen, ml->y_bit_offset, ml->xy_bit_size);
            record_mouse_movement(btns, dx, dy);
            tuh_hid_receive_report(dev_addr, instance);
            return;
        }
    }

    // 2. Fallback voor Boot-Protocol / Standaard Muizen zonder geparste layout
    if (itf_protocol == HID_ITF_PROTOCOL_MOUSE ||
        (hid_info[instance].is_mouse_itf && !hid_info[instance].is_keyboard_itf)) {
        if (hid_info[instance].has_report_id && plen >= 4) {
            p++;
            plen--;
        }
        if (plen >= 3) {
            uint8_t btns = p[0] & 0x07;
            int32_t dx   = (int8_t)p[1];
            int32_t dy   = (int8_t)p[2];
            record_mouse_movement(btns, dx, dy);
        }
        tuh_hid_receive_report(dev_addr, instance);
        return;
    }

    // 3. Toetsenbord-afhandeling (6KRO & NKRO)
    uint8_t const rpt_count = hid_info[instance].report_count;
    tuh_hid_report_info_t* rpt_arr = hid_info[instance].report_info;

    if (rpt_count > 0 && !(rpt_count == 1 && rpt_arr[0].report_id == 0)) {
        rpt_id = p[0];
        for (uint8_t i = 0; i < rpt_count; i++) {
            if (rpt_arr[i].report_id == rpt_id) {
                if (rpt_arr[i].usage_page == HID_USAGE_PAGE_DESKTOP &&
                    rpt_arr[i].usage == HID_USAGE_DESKTOP_KEYBOARD) {
                    p++;
                    plen--;
                } else if (rpt_arr[i].usage_page == HID_USAGE_PAGE_DESKTOP &&
                           (rpt_arr[i].usage == HID_USAGE_DESKTOP_MOUSE ||
                            rpt_arr[i].usage == HID_USAGE_DESKTOP_POINTER)) {
                    p++;
                    plen--;
                    if (plen >= 3) {
                        record_mouse_movement(p[0] & 0x07, (int8_t)p[1], (int8_t)p[2]);
                    }
                    tuh_hid_receive_report(dev_addr, instance);
                    return;
                } else {
                    tuh_hid_receive_report(dev_addr, instance);
                    return;
                }
                break;
            }
        }
    }

    if (hid_info[instance].is_keyboard_itf || itf_protocol == HID_ITF_PROTOCOL_KEYBOARD) {
        if (plen == 8) {
            process_6kro_keys(p[0], p + 2);
        } else if (plen == 7) {
            process_6kro_keys(p[0], p + 1);
        } else if (plen == 9) {
            process_6kro_keys(p[1], p + 3);
        } else if (plen >= 13 && plen <= 32) {
            process_nkro_bitmap(p[0], p + 1, plen - 1);
        }
    }

    tuh_hid_receive_report(dev_addr, instance);
}

int main(void) {
    board_init();
    ps2_gpio_init_all();

    // Gebruik Report Protocol zodat zowel moderne/draadloze USB-toetsenborden als USB-muizen werken!
    tuh_hid_set_default_protocol(HID_PROTOCOL_REPORT);
    tusb_init();

    while (true) {
        tuh_task();

        // Verstuur eerstvolgende PS/2 byte uit de wachtrij
        if (ps2_q_tail != ps2_q_head) {
            uint8_t b = ps2_queue[ps2_q_tail];
            ps2_q_tail = (ps2_q_tail + 1) & (PS2_QUEUE_SIZE - 1);
            ps2_tx_byte_blocking(b);
        } else if (mouse_acc_dx != 0 || mouse_acc_dy != 0 ||
                   mouse_cur_buttons != mouse_sent_buttons || mouse_btn_press_latch != 0) {
            // Wachtrij is leeg -> stuur geaccumuleerde USB-muisbeweging & muisknoppen als 3-byte pakket!
            int32_t dx_send = mouse_acc_dx;
            if (dx_send > 127)  dx_send = 127;
            if (dx_send < -127) dx_send = -127;
            mouse_acc_dx -= dx_send;

            int32_t dy_send = mouse_acc_dy;
            if (dy_send > 127)  dy_send = 127;
            if (dy_send < -127) dy_send = -127;
            mouse_acc_dy -= dy_send;

            uint8_t btn_send = (mouse_cur_buttons | mouse_btn_press_latch) & 0x07;
            mouse_btn_press_latch = 0;
            mouse_sent_buttons    = btn_send;

            ps2_enqueue(0xF8 | btn_send);
            ps2_enqueue((uint8_t)((int8_t)dx_send));
            ps2_enqueue((uint8_t)((int8_t)dy_send));
        }

        uint32_t now = board_millis();

        // Typematic auto-repeat wanneer een toets ingedrukt blijft
        if (repeat_hid_key != 0 && ps2_q_tail == ps2_q_head) {
            if ((int32_t)(now - repeat_next_ms) >= 0) {
                send_hid_key_ps2(repeat_hid_key, true);
                led_blink_off_until = now + 30;
                repeat_next_ms = now + 40; // 25 Hz herhaalsnelheid
            }
        }

        // LED-status op GP25:
        // - Wacht op USB-apparaat: korte hartslag (80 ms aan elke 1000 ms)
        // - Toetsenbord en/of Muis verbonden: vast AAN, met knipper bij elke toets of muisbeweging!
        if (mounted_devices == 0) {
            gpio_put(LED_PIN, (now % 1000) < 80 ? 1 : 0);
        } else {
            gpio_put(LED_PIN, ((int32_t)(led_blink_off_until - now) > 0) ? 0 : 1);
        }
    }
    return 0;
}
