`timescale 1ns / 1ps

module ps2_keyboard (
    input  wire              clk,            // 27 MHz system clock
    input  wire              reset,
    input  wire              ps2_clk,        // Pin 74 (D+) - PS/2 Clock
    input  wire              ps2_data,       // Pin 73 (D-) - PS/2 Data
    output reg        [7:0]  ascii_code,
    output reg               ascii_valid,
    output reg        [7:0]  joypad_state,   // Live 8-bit Arcade Joypad state ($A004)
    output reg        [7:0]  mouse_state,    // Live Alt + Arrow Keys & USB Mouse Button state
    output reg signed [7:0]  usb_mouse_dx,   // Pico 2 USB Mouse delta X (-127..+127)
    output reg signed [7:0]  usb_mouse_dy,   // Pico 2 USB Mouse delta Y (-127..+127)
    output reg               usb_mouse_valid // 1-clock pulse when 3-byte Pico 2 mouse packet arrives
);

    // --- 1. Synchronizer & Digital Debounce Filter ---
    reg [2:0] clk_sync  = 3'b111;
    reg [2:0] data_sync = 3'b111;
    always @(posedge clk) begin
        clk_sync  <= {clk_sync[1:0],  ps2_clk};
        data_sync <= {data_sync[1:0], ps2_data};
    end

    reg [7:0] clk_filter = 8'hFF;
    reg       ps2_clk_clean = 1'b1;
    reg       ps2_clk_prev  = 1'b1;

    always @(posedge clk) begin
        clk_filter <= {clk_filter[6:0], clk_sync[2]};
        ps2_clk_prev <= ps2_clk_clean;
        if (clk_filter == 8'hFF)
            ps2_clk_clean <= 1'b1;
        else if (clk_filter == 8'h00)
            ps2_clk_clean <= 1'b0;
    end

    wire ps2_clk_falling = (ps2_clk_prev == 1'b1) && (ps2_clk_clean == 1'b0);
    wire ps2_data_clean  = data_sync[2];

    // --- 2. 11-bit Frame Receiver + Timeout Watchdog ---
    reg [3:0]  bit_count = 0;
    reg [10:0] shift_reg = 0;
    reg [15:0] timeout_cnt = 0;
    reg [7:0]  scancode = 0;
    reg        scancode_ready = 0;

    always @(posedge clk) begin
        scancode_ready <= 0;
        if (reset) begin
            bit_count   <= 0;
            timeout_cnt <= 0;
        end else begin
            if (ps2_clk_falling) begin
                timeout_cnt <= 0;
                shift_reg   <= {ps2_data_clean, shift_reg[10:1]};
                if (bit_count == 4'd10) begin
                    bit_count <= 0;
                    // Check Start bit (0) and Stop bit (1)
                    if (shift_reg[1] == 1'b0 && ps2_data_clean == 1'b1) begin
                        scancode       <= shift_reg[9:2];
                        scancode_ready <= 1'b1;
                    end
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end else if (bit_count != 0) begin
                // Reset bit_count if bus idle for > 2.4ms (65535 cycles @ 27MHz)
                if (timeout_cnt == 16'hFFFF) begin
                    bit_count   <= 0;
                    timeout_cnt <= 0;
                end else begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                end
            end
        end
    end

    // --- 3. PS/2 Set 2 Scancode Decoder & Modifier State ---
    reg is_break  = 1'b0;
    reg is_ext    = 1'b0;
    reg shift_l   = 1'b0;
    reg shift_r   = 1'b0;
    reg caps_lock = 1'b1; // Default ON for BBC BASIC uppercase keywords!

    wire shift = shift_l | shift_r;
    wire upper = caps_lock ^ shift;

    reg [7:0] decoded_char;

    always @(*) begin
        decoded_char = 8'h00;
        case (scancode)
            // Letters A - Z
            8'h1C: decoded_char = upper ? "A" : "a";
            8'h32: decoded_char = upper ? "B" : "b";
            8'h21: decoded_char = upper ? "C" : "c";
            8'h23: decoded_char = upper ? "D" : "d";
            8'h24: decoded_char = upper ? "E" : "e";
            8'h2B: decoded_char = upper ? "F" : "f";
            8'h34: decoded_char = upper ? "G" : "g";
            8'h33: decoded_char = upper ? "H" : "h";
            8'h43: decoded_char = upper ? "I" : "i";
            8'h3B: decoded_char = upper ? "J" : "j";
            8'h42: decoded_char = upper ? "K" : "k";
            8'h4B: decoded_char = upper ? "L" : "l";
            8'h3A: decoded_char = upper ? "M" : "m";
            8'h31: decoded_char = upper ? "N" : "n";
            8'h44: decoded_char = upper ? "O" : "o";
            8'h4D: decoded_char = upper ? "P" : "p";
            8'h15: decoded_char = upper ? "Q" : "q";
            8'h2D: decoded_char = upper ? "R" : "r";
            8'h1B: decoded_char = upper ? "S" : "s";
            8'h2C: decoded_char = upper ? "T" : "t";
            8'h3C: decoded_char = upper ? "U" : "u";
            8'h2A: decoded_char = upper ? "V" : "v";
            8'h1D: decoded_char = upper ? "W" : "w";
            8'h22: decoded_char = upper ? "X" : "x";
            8'h35: decoded_char = upper ? "Y" : "y";
            8'h1A: decoded_char = upper ? "Z" : "z";

            // Top row numbers & symbols (US layout)
            8'h16: decoded_char = shift ? "!" : "1";
            8'h1E: decoded_char = shift ? "@" : "2";
            8'h26: decoded_char = shift ? "#" : "3";
            8'h25: decoded_char = shift ? "$" : "4";
            8'h2E: decoded_char = shift ? "%" : "5";
            8'h36: decoded_char = shift ? "^" : "6";
            8'h3D: decoded_char = shift ? "&" : "7";
            8'h3E: decoded_char = shift ? "*" : "8";
            8'h46: decoded_char = shift ? "(" : "9";
            8'h45: decoded_char = shift ? ")" : "0";

            // Numpad numbers & operators
            8'h70: decoded_char = "0";
            8'h69: decoded_char = "1";
            8'h72: decoded_char = "2";
            8'h7A: decoded_char = "3";
            8'h6B: decoded_char = "4";
            8'h73: decoded_char = "5";
            8'h74: decoded_char = "6";
            8'h6C: decoded_char = "7";
            8'h75: decoded_char = "8";
            8'h7D: decoded_char = "9";
            8'h71: decoded_char = ".";
            8'h79: decoded_char = "+";
            8'h7B: decoded_char = "-";
            8'h7C: decoded_char = "*";

            // Punctuation & Special Keys
            8'h29: decoded_char = " ";                  // Space
            8'h5A: decoded_char = 8'h0D;                // Enter -> CR
            8'h66: decoded_char = 8'h08;                // Backspace -> BS
            8'h76: decoded_char = 8'h1B;                // Escape -> ESC
            8'h0D: decoded_char = 8'h09;                // Tab -> HT ($09)
            8'h01: decoded_char = 8'h0E;                // F9 -> Menu ($0E)
            8'h05: decoded_char = "1";                  // F1 -> '1'
            8'h06: decoded_char = "2";                  // F2 -> '2'
            8'h04: decoded_char = "3";                  // F3 -> '3'
            8'h0C: decoded_char = "4";                  // F4 -> '4'
            8'h03: decoded_char = "5";                  // F5 -> '5'
            8'h0B: decoded_char = "6";                  // F6 -> '6'
            8'h83: decoded_char = "7";                  // F7 -> '7'
            8'h0A: decoded_char = "8";                  // F8 -> '8'
            8'h09: decoded_char = "0";                  // F10 -> '0'
            8'h4E: decoded_char = shift ? "_" : "-";
            8'h55: decoded_char = shift ? "+" : "=";
            8'h54: decoded_char = shift ? "{" : "[";
            8'h5B: decoded_char = shift ? "}" : "]";
            8'h5D: decoded_char = shift ? "|" : "\\";
            8'h4C: decoded_char = shift ? ":" : ";";
            8'h52: decoded_char = shift ? "\"" : "'";
            8'h41: decoded_char = shift ? "<" : ",";
            8'h49: decoded_char = shift ? ">" : ".";
            8'h4A: decoded_char = is_ext ? "/" : (shift ? "?" : "/");
            8'h0E: decoded_char = shift ? "~" : "`";
            default: decoded_char = 8'h00;
        endcase
    end

    // --- 4. True Multi-Key N-Key Rollover Hardware State Matrix ---
    // Separate register per physical key so holding multiple keys simultaneously
    // (e.g. Left + Up + Space, or A + Left Arrow) and ignoring PS/2 Fake-Shifts (E0 12 / E0 59)
    // works with zero stickiness and zero dropped releases!
    reg k_up_arr = 0, k_w = 0, k_kp8 = 0;
    reg k_dn_arr = 0, k_s = 0, k_kp2 = 0;
    reg k_lt_arr = 0, k_a = 0, k_kp4 = 0;
    reg k_rt_arr = 0, k_d = 0, k_kp6 = 0;
    reg k_space  = 0, k_z = 0, k_kp0 = 0;
    reg k_x      = 0, k_shl = 0, k_shr = 0, k_ctrl = 0;
    reg k_c      = 0, k_tab = 0;
    reg k_enter  = 0, k_esc = 0;
    reg k_alt    = 0;

    // Pico 2 USB Mouse 3-byte packet state: [0xF8 | btn[2:0], dx, dy]
    reg [1:0]  mouse_pkt_state = 2'd0;
    reg [17:0] mouse_pkt_timer = 18'd0;
    reg [2:0]  usb_mouse_btn   = 3'b000;

    always @(*) begin
        joypad_state[0] = (!k_alt & k_up_arr) | k_w | k_kp8;               // Bit 0: Up
        joypad_state[1] = (!k_alt & k_dn_arr) | k_s | k_kp2;               // Bit 1: Down
        joypad_state[2] = (!k_alt & k_lt_arr) | k_a | k_kp4;               // Bit 2: Left
        joypad_state[3] = (!k_alt & k_rt_arr) | k_d | k_kp6;               // Bit 3: Right
        joypad_state[4] = (!k_alt & k_space)  | k_z | k_kp0;               // Bit 4: Fire 1 (Space / Z)
        joypad_state[5] = k_x      | k_shl | k_shr | k_ctrl;               // Bit 5: Fire 2 (X / Shift / Ctrl)
        joypad_state[6] = k_c      | k_tab;                                // Bit 6: Select (C / Tab)
        joypad_state[7] = (!k_alt & k_enter)  | k_esc;                     // Bit 7: Start  (Enter / Esc)

        mouse_state[0]  = k_alt & k_up_arr;                                // Bit 0: Alt + Arrow Up
        mouse_state[1]  = k_alt & k_dn_arr;                                // Bit 1: Alt + Arrow Down
        mouse_state[2]  = k_alt & k_lt_arr;                                // Bit 2: Alt + Arrow Left
        mouse_state[3]  = k_alt & k_rt_arr;                                // Bit 3: Alt + Arrow Right
        mouse_state[4]  = (k_alt & (k_space | k_enter | k_z | k_kp0)) | usb_mouse_btn[0]; // Bit 4: Left Click
        mouse_state[5]  = (k_alt & (k_x | k_ctrl)) | usb_mouse_btn[1] | usb_mouse_btn[2]; // Bit 5: Right Click
        mouse_state[6]  = k_alt & (k_shl | k_shr);                         // Bit 6: Alt + Shift = Fast Mouse
        mouse_state[7]  = k_alt;                                           // Bit 7: Alt held
    end

    always @(posedge clk) begin
        ascii_valid     <= 1'b0;
        usb_mouse_valid <= 1'b0;
        if (reset) begin
            is_break <= 1'b0;
            is_ext   <= 1'b0;
            shift_l  <= 1'b0;
            shift_r  <= 1'b0;
            caps_lock <= 1'b1;
            k_up_arr <= 0; k_w <= 0; k_kp8 <= 0;
            k_dn_arr <= 0; k_s <= 0; k_kp2 <= 0;
            k_lt_arr <= 0; k_a <= 0; k_kp4 <= 0;
            k_rt_arr <= 0; k_d <= 0; k_kp6 <= 0;
            k_space  <= 0; k_z <= 0; k_kp0 <= 0;
            k_x      <= 0; k_shl <= 0; k_shr <= 0; k_ctrl <= 0;
            k_c      <= 0; k_tab <= 0;
            k_enter  <= 0; k_esc <= 0;
            k_alt    <= 0;
            mouse_pkt_state <= 2'd0;
            mouse_pkt_timer <= 18'd0;
            usb_mouse_btn   <= 3'b000;
            usb_mouse_dx    <= 8'sd0;
            usb_mouse_dy    <= 8'sd0;
        end else if (scancode_ready) begin
            mouse_pkt_timer <= 18'd0;
            if (mouse_pkt_state == 2'd1) begin
                usb_mouse_dx    <= scancode;
                mouse_pkt_state <= 2'd2;
            end else if (mouse_pkt_state == 2'd2) begin
                usb_mouse_dy    <= scancode;
                usb_mouse_valid <= 1'b1;
                mouse_pkt_state <= 2'd0;
            end else if (!is_break && !is_ext && (scancode[7:3] == 5'b11111)) begin
                // Pico 2 USB Mouse Packet Header: 0xF8..0xFF (bits 2:0 = Middle, Right, Left buttons)
                usb_mouse_btn   <= scancode[2:0];
                mouse_pkt_state <= 2'd1;
            end else if (scancode == 8'hF0) begin
                is_break <= 1'b1;
            end else if (scancode == 8'hE0) begin
                is_ext <= 1'b1;
            end else begin
                // Update individual key flip-flops (ignore PS/2 Fake Shift E0 12 / E0 59!)
                if (is_ext) begin
                    case (scancode)
                        8'h75: k_up_arr <= ~is_break; // Arrow Up
                        8'h72: k_dn_arr <= ~is_break; // Arrow Down
                        8'h6B: k_lt_arr <= ~is_break; // Arrow Left
                        8'h74: k_rt_arr <= ~is_break; // Arrow Right
                        8'h14: k_ctrl   <= ~is_break; // Right Ctrl
                        8'h5A: k_enter  <= ~is_break; // Numpad Enter
                        8'h11: k_alt    <= ~is_break; // Right Alt (AltGr)
                        default: ; // Ignore E0 12 / E0 59 Fake Shifts!
                    endcase
                end else begin
                    case (scancode)
                        8'h1D: k_w     <= ~is_break;
                        8'h75: k_kp8   <= ~is_break;
                        8'h1B: k_s     <= ~is_break;
                        8'h72: k_kp2   <= ~is_break;
                        8'h1C: k_a     <= ~is_break;
                        8'h6B: k_kp4   <= ~is_break;
                        8'h23: k_d     <= ~is_break;
                        8'h74: k_kp6   <= ~is_break;
                        8'h29: k_space <= ~is_break;
                        8'h1A: k_z     <= ~is_break;
                        8'h70: k_kp0   <= ~is_break;
                        8'h22: k_x     <= ~is_break;
                        8'h12: k_shl   <= ~is_break;
                        8'h59: k_shr   <= ~is_break;
                        8'h14: k_ctrl  <= ~is_break;
                        8'h21: k_c     <= ~is_break;
                        8'h0D: k_tab   <= ~is_break;
                        8'h5A: k_enter <= ~is_break;
                        8'h76: k_esc   <= ~is_break;
                        8'h11: k_alt   <= ~is_break; // Left Alt
                        default: ;
                    endcase
                end

                if (is_break) begin
                    is_break <= 1'b0;
                    is_ext   <= 1'b0;
                    if (!is_ext && scancode == 8'h12) shift_l <= 1'b0;
                    if (!is_ext && scancode == 8'h59) shift_r <= 1'b0;
                end else begin
                    is_ext <= 1'b0;
                    if (!is_ext && scancode == 8'h12) begin
                        shift_l <= 1'b1;
                    end else if (!is_ext && scancode == 8'h59) begin
                        shift_r <= 1'b1;
                    end else if (scancode == 8'h58) begin
                        caps_lock <= ~caps_lock;
                    end else if (!k_alt && decoded_char != 8'h00) begin
                        ascii_code  <= decoded_char;
                        ascii_valid <= 1'b1;
                    end
                end
            end
        end else if (mouse_pkt_state != 2'd0) begin
            // Reset mouse packet state if > 7.5 ms passes without next byte
            if (mouse_pkt_timer == 18'h3FFFF) begin
                mouse_pkt_state <= 2'd0;
                mouse_pkt_timer <= 18'd0;
            end else begin
                mouse_pkt_timer <= mouse_pkt_timer + 18'd1;
            end
        end
    end

endmodule
