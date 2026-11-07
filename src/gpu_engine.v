`timescale 1ns / 1ps

module gpu_engine (
    input  wire        clk,
    input  wire        rst_n,
    
    // UART interface
    input  wire [7:0]  rx_data,
    input  wire        rx_valid, // 1-cycle pulse
    input  wire        restore_bg_pulse,
    
    // Memory interface
    output reg         mem_req,
    input  wire        mem_ack,
    output reg [20:0]  mem_addr, // SDRAM word address
    output reg [31:0]  mem_data,
    output reg [3:0]   mem_wstrb,
    output reg         front_buffer,
    
    // Background Layer Interface
    output reg         we_tileset,
    output reg [13:0]  addr_tileset,
    output reg [7:0]   din_tileset,
    
    output reg         we_tilemap,
    output reg [11:0]  addr_tilemap,
    output reg [7:0]   din_tilemap,
    
    output reg [9:0]   scroll_x,
    output reg [9:0]   scroll_y,
    
    output reg         audio_we,
    output reg [1:0]   audio_channel,
    output reg [23:0]  audio_phase_inc,
    output reg [7:0]   audio_volume,

    // Big Sprite Hardware Engine (2x 128x128)
    output reg         big_spr_we_ctrl,
    output reg         big_spr_ctrl_slot,
    output reg         big_spr_ctrl_enable,
    output reg signed [15:0] big_spr_ctrl_x,
    output reg signed [15:0] big_spr_ctrl_y,
    output reg [7:0]   big_spr_ctrl_flags,
    output reg         big_spr_we_ram,
    output reg         big_spr_ram_slot,
    output reg [13:0]  big_spr_ram_addr,
    output reg [7:0]   big_spr_ram_din,
    output wire        busy
);

    assign busy = draw_busy;

    reg [6:0] big_spr_line_idx = 0;

    // Command parser state machine
    reg [5:0] parse_state = 0;
    reg [7:0] cmd = 0;
    reg [7:0] ent_tmp_x = 0;
    reg [7:0] ent_tmp_y = 0;
    
    reg [15:0] arg_x = 0;
    reg [15:0] arg_y = 0;
    reg [15:0] arg_w = 0;
    reg [15:0] arg_h = 0;
    reg [15:0] arg_x3 = 0;
    reg [15:0] arg_y3 = 0;
    reg [7:0]  arg_c = 0;
    
    // Bresenham line variables
    reg signed [12:0] err = 0;
    reg signed [12:0] dx = 0;
    reg signed [12:0] dy = 0;
    reg [1:0] sx = 0; // 0=none, 1=pos, 2=neg
    reg [1:0] sy = 0; // 0=none, 1=pos, 2=neg

    reg start_draw = 0;
    wire draw_busy;
    reg render_to_front = 0;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            parse_state <= 0;
            start_draw <= 0;
            front_buffer <= 0;
            render_to_front <= 0;
            we_tileset <= 0;
            we_tilemap <= 0;
            scroll_x <= 0;
            scroll_y <= 0;
            audio_phase_inc <= 0;
            audio_volume <= 0;
            audio_we <= 0;
            audio_channel <= 0;
        end else begin
            start_draw <= 0;
            we_tileset <= 0;
            we_tilemap <= 0;
            audio_we <= 0;
            big_spr_we_ctrl <= 0;
            big_spr_we_ram <= 0;
            if (restore_bg_pulse) begin
                parse_state     <= 0;
                render_to_front <= 1'b1;
                cmd             <= 8'd1;
                arg_c           <= 8'hE3;
                start_draw      <= 1'b1;
            end else if (rx_valid && !draw_busy) begin
                case (parse_state)
                    0: begin
                        cmd <= rx_data;
                        if (rx_data == 11) front_buffer <= ~front_buffer;
                        else if (rx_data == 12) parse_state <= 15; // SET_RENDER_TARGET
                        else if (rx_data == 13 || rx_data == 14) parse_state <= 16; // UPLOAD_BG
                        else if (rx_data == 15) parse_state <= 17; // SET_SCROLL
                        else if (rx_data == 16) parse_state <= 23; // SET_AUDIO
                        else if (rx_data == 21) parse_state <= 45; // SET_BIG_SPRITE_POS (0x15)
                        else if (rx_data == 22) parse_state <= 52; // UPLOAD_BIG_SPRITE_LINE (0x16)
                        else if (rx_data == 23) parse_state <= 55; // SET_SINGLE_TILE (0x17: mx, my, tile_id)
                        else if (rx_data >= 1 && rx_data <= 10) parse_state <= 1;
                    end
                    // 0x01: CLEAR_SCREEN (1 arg: color)
                    // 0x02: RECTANGLE (9 args: xl, xh, yl, yh, wl, wh, hl, hh, color)
                    // 0x03: LINE (9 args: x0l, x0h, y0l, y0h, x1l, x1h, y1l, y1h, color)
                    // 0x04: CIRCLE (9 args: x0l, x0h, y0l, y0h, rl, rh, -, -, color)
                    // 0x05: FILLED_CIRCLE (9 args: cx_l, cx_h, cy_l, cy_h, r_l, r_h, -, -, color)
                    // 0x06: TRIANGLE (13 args: x1l, x1h, y1l, y1h, x2l, x2h, y2l, y2h, x3l, x3h, y3l, y3h, color)
                    // 0x07: FILLED_TRIANGLE (13 args)
                    // 0x08: TEXT (9 args: xl, xh, yl, yh, char, -, -, -, color)
                    1: begin
                        if (cmd == 1) begin
                            arg_c <= rx_data;
                            start_draw <= 1;
                            parse_state <= 0;
                        end else if (cmd == 9) begin // UPLOAD_SPRITE
                            sprite_id <= rx_data[4:0];
                            upload_counter <= 0;
                            parse_state <= 14;
                        end else if (cmd >= 2 && cmd <= 10) begin
                            arg_x[7:0] <= rx_data;
                            parse_state <= 2;
                        end
                    end
                    2: begin arg_x[15:8] <= rx_data; parse_state <= 3; end
                    3: begin arg_y[7:0] <= rx_data; parse_state <= 4; end
                    4: begin arg_y[15:8] <= rx_data; parse_state <= 5; end
                    5: begin arg_w[7:0] <= rx_data; parse_state <= 6; end
                    6: begin arg_w[15:8] <= rx_data; parse_state <= 7; end
                    7: begin arg_h[7:0] <= rx_data; parse_state <= 8; end
                    8: begin arg_h[15:8] <= rx_data; parse_state <= 9; end
                    9: begin 
                        if (cmd == 6 || cmd == 7) begin
                            arg_x3[7:0] <= rx_data;
                            parse_state <= 10;
                        end else begin
                            arg_c <= rx_data; 
                            start_draw <= 1;
                            parse_state <= 0; 
                        end
                    end
                    10: begin arg_x3[15:8] <= rx_data; parse_state <= 11; end
                    11: begin arg_y3[7:0] <= rx_data; parse_state <= 12; end
                    12: begin arg_y3[15:8] <= rx_data; parse_state <= 13; end

                    14: begin // UPLOAD_SPRITE loop
                        sprite_ram[{sprite_id, upload_counter[7:0]}] <= rx_data;
                        if (upload_counter == 255) begin
                            parse_state <= 0;
                        end else begin
                            upload_counter <= upload_counter + 1;
                        end
                    end
                    13: begin
                        arg_c <= rx_data;
                        start_draw <= 1;
                        parse_state <= 0;
                    end
                    15: begin // SET_RENDER_TARGET
                        render_to_front <= rx_data[0];
                        parse_state <= 0;
                    end
                    16: begin // BG ID setup
                        bg_upload_id <= rx_data[5:0];
                        upload_counter <= 0;
                        parse_state <= (cmd == 13) ? 18 : 19;
                    end
                    17: begin // SET_SCROLL_X_L
                        scroll_x[7:0] <= rx_data;
                        parse_state <= 20;
                    end
                    20: begin // SET_SCROLL_X_H
                        scroll_x[9:8] <= rx_data[1:0];
                        parse_state <= 21;
                    end
                    21: begin // SET_SCROLL_Y_L
                        scroll_y[7:0] <= rx_data;
                        parse_state <= 22;
                    end
                    22: begin // SET_SCROLL_Y_H
                        scroll_y[9:8] <= rx_data[1:0];
                        parse_state <= 0;
                    end
                    23: begin audio_channel <= rx_data[1:0]; parse_state <= 24; end
                    24: begin audio_phase_inc[7:0] <= rx_data; parse_state <= 25; end
                    25: begin audio_phase_inc[15:8] <= rx_data; parse_state <= 26; end
                    26: begin audio_phase_inc[23:16] <= rx_data; parse_state <= 27; end
                    27: begin audio_volume <= rx_data; audio_we <= 1; parse_state <= 0; end
                    18: begin // UPLOAD_BG_TILESET
                        we_tileset <= 1;
                        addr_tileset <= {bg_upload_id, upload_counter[7:0]};
                        din_tileset <= rx_data;
                        if (upload_counter == 255) parse_state <= 0;
                        else upload_counter <= upload_counter + 1;
                    end
                    19: begin // UPLOAD_BG_TILEMAP
                        we_tilemap <= 1;
                        addr_tilemap <= {bg_upload_id, upload_counter[5:0]};
                        din_tilemap <= rx_data;
                        if (upload_counter == 63) parse_state <= 0;
                        else upload_counter <= upload_counter + 1;
                    end
                    // 0x15 (21): SET_BIG_SPRITE_POS (7 args: slot, enable, xl, xh, yl, yh, flags)
                    45: begin big_spr_ctrl_slot <= rx_data[0]; parse_state <= 46; end
                    46: begin big_spr_ctrl_enable <= rx_data[0]; parse_state <= 47; end
                    47: begin big_spr_ctrl_x[7:0] <= rx_data; parse_state <= 48; end
                    48: begin big_spr_ctrl_x[15:8] <= rx_data; parse_state <= 49; end
                    49: begin big_spr_ctrl_y[7:0] <= rx_data; parse_state <= 50; end
                    50: begin big_spr_ctrl_y[15:8] <= rx_data; parse_state <= 51; end
                    51: begin
                        big_spr_ctrl_flags <= rx_data;
                        big_spr_we_ctrl <= 1;
                        parse_state <= 0;
                    end

                    // 0x16 (22): UPLOAD_BIG_SPRITE_LINE (130 args: slot, line_idx, 128 pixel bytes)
                    52: begin big_spr_ram_slot <= rx_data[0]; parse_state <= 53; end
                    53: begin big_spr_line_idx <= rx_data[6:0]; upload_counter <= 0; parse_state <= 54; end
                    54: begin
                        big_spr_we_ram <= 1;
                        big_spr_ram_addr <= {big_spr_line_idx[6:0], upload_counter[6:0]};
                        big_spr_ram_din <= rx_data;
                        if (upload_counter == 127) parse_state <= 0;
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
                endcase
            end
        end
    end
    
    // Rasterizer state machine
    reg [5:0] draw_state = 0;
    reg [1:0] tri_line = 0;
    reg signed [12:0] draw_x = 0;
    reg signed [12:0] draw_y = 0;
    reg signed [12:0] end_x = 0;
    reg signed [12:0] end_y = 0;
    
    // Circle variables
    reg signed [12:0] circ_x = 0;
    reg signed [12:0] circ_y = 0;
    reg signed [13:0] circ_err = 0;
    reg [2:0] circ_octant = 0;
    
    // Triangle fill variables
    reg signed [12:0] tx0 = 0, ty0 = 0, tx1 = 0, ty1 = 0, tx2 = 0, ty2 = 0;
    reg signed [12:0] scan_y = 0;
    reg tri_half = 0;
    
    // Tracer A (Long edge)
    reg signed [12:0] errA = 0, dxA = 0, dyA = 0;
    reg [1:0] sxA = 0;
    reg signed [12:0] xA = 0, yA = 0, end_xA = 0, end_yA = 0;
    
    // Tracer B (Short edges)
    reg signed [12:0] errB = 0, dxB = 0, dyB = 0;
    reg [1:0] sxB = 0;
    reg signed [12:0] xB = 0, yB = 0, end_xB = 0, end_yB = 0;
    
    // Sprite variables (32 sprites x 256 bytes = 8KB BRAM)
    reg [12:0] sprite_addr = 0;
    reg [7:0]  sprite_ram [0:8191];
    initial begin
        $readmemh("default_sprites.hex", sprite_ram);
    end
    reg [8:0]  upload_counter = 0;
    reg [4:0]  sprite_id = 0;
    reg [5:0] bg_upload_id = 0;

    // Font ROM for TEXT command (0x08)
    reg [7:0] font_rom [0:1023];
    initial begin
        $readmemh("font8x8.hex", font_rom);
    end
    reg [9:0] font_row_addr = 0;
    reg [7:0] font_row_data = 0;
    reg [3:0] char_col = 0;
    reg [3:0] char_row = 0;

    assign draw_busy = (draw_state != 0) || start_draw;
    wire [20:0] fb_offset = (render_to_front ? front_buffer : ~front_buffer) ? 21'd57600 : 21'd0;

    
    always @(posedge clk) begin
        if (!rst_n) begin
            draw_state <= 0;
            mem_req <= 0;
        end else begin
            case (draw_state)
                0: begin
                    if (start_draw) begin
                        if (cmd == 1) begin
                            // CLEAR
                            draw_x <= 0;
                            draw_y <= 0;
                            end_x <= 639;
                            end_y <= 359;
                            draw_state <= 1;
                        end else if (cmd == 2) begin
                            // RECTANGLE
                            draw_x <= arg_x[12:0];
                            draw_y <= arg_y[12:0];
                            end_x <= arg_x[12:0] + arg_w[12:0] - 1;
                            end_y <= arg_y[12:0] + arg_h[12:0] - 1;
                            draw_state <= 1;
                        end else if (cmd == 3) begin
                            // LINE
                            draw_x <= arg_x[12:0];
                            draw_y <= arg_y[12:0];
                            end_x <= arg_w[12:0]; // x1
                            end_y <= arg_h[12:0]; // y1
                            draw_state <= 5;
                        end else if (cmd == 4 || cmd == 5) begin
                            // CIRCLE & FILLED_CIRCLE
                            circ_x <= arg_w[12:0]; // r
                            circ_y <= 0;
                            circ_err <= $signed({1'b0, 10'd1}) - $signed(arg_w[12:0]);
                            circ_octant <= 0;
                            draw_state <= (cmd == 5) ? 10 : 8;
                        end else if (cmd == 6) begin
                            // TRIANGLE OUTLINE
                            tri_line <= 0;
                            draw_x <= arg_x[12:0];
                            draw_y <= arg_y[12:0];
                            end_x <= arg_w[12:0];
                            end_y <= arg_h[12:0];
                            draw_state <= 5;
                        end else if (cmd == 7) begin
                            // FILLED TRIANGLE
                            tx0 <= arg_x[12:0]; ty0 <= arg_y[12:0];
                            tx1 <= arg_w[12:0]; ty1 <= arg_h[12:0];
                            tx2 <= arg_x3[12:0]; ty2 <= arg_y3[12:0];
                            draw_state <= 12;
                        end else if (cmd == 8) begin
                            // TEXT
                            draw_x <= arg_x[12:0];
                            draw_y <= arg_y[12:0];
                            char_col <= 0;
                            char_row <= 0;
                            draw_state <= 24;
                        end else if (cmd == 10) begin
                            // DRAW_SPRITE
                            draw_x <= arg_x[12:0];
                            draw_y <= arg_y[12:0];
                            char_col <= 0;
                            char_row <= 0;
                            draw_state <= 30;
                        end
                    end
                end
                
                1: begin
                    // Issue write
                    if (draw_x >= 0 && draw_x < 640 && draw_y >= 0 && draw_y < 360) begin
                        mem_addr <= (draw_y[8:0] * 160) + draw_x[9:2] + fb_offset;
                        case (draw_x[1:0])
                            2'b00: begin mem_wstrb <= 4'b0001; mem_data <= {24'd0, arg_c}; end
                            2'b01: begin mem_wstrb <= 4'b0010; mem_data <= {16'd0, arg_c, 8'd0}; end
                            2'b10: begin mem_wstrb <= 4'b0100; mem_data <= {8'd0, arg_c, 16'd0}; end
                            2'b11: begin mem_wstrb <= 4'b1000; mem_data <= {arg_c, 24'd0}; end
                        endcase
                        mem_req <= 1;
                        draw_state <= 2;
                    end else begin
                        draw_state <= 4; // Skip pixel if out of bounds
                    end
                end
                
                2: begin
                    // Wait for ack
                    if (mem_ack) begin
                        mem_req <= 0;
                        draw_state <= 3;
                    end
                end
                
                3: begin
                    // One cycle delay to let arbiter see mem_req=0
                    draw_state <= 4;
                end
                
                4: begin
                    // Advance pixel
                    if (cmd == 1 || cmd == 2) begin
                        if (draw_x == end_x) begin
                            draw_x <= (cmd == 1) ? 0 : arg_x[12:0];
                            if (draw_y == end_y) begin
                                draw_state <= 0; // Done
                            end else begin
                                draw_y <= draw_y + 1;
                                draw_state <= 1;
                            end
                        end else begin
                            draw_x <= draw_x + 1;
                            draw_state <= 1;
                        end
                    end else if (cmd == 3) begin
                        if (draw_x == end_x && draw_y == end_y) begin
                            draw_state <= 0; // Done
                        end else begin
                            draw_state <= 7; // Go compute next step
                        end
                    end else if (cmd == 6) begin
                        if (draw_x == end_x && draw_y == end_y) begin
                            if (tri_line == 0) begin
                                tri_line <= 1;
                                draw_x <= arg_w[12:0];
                                draw_y <= arg_h[12:0];
                                end_x <= arg_x3[12:0];
                                end_y <= arg_y3[12:0];
                                draw_state <= 5;
                            end else if (tri_line == 1) begin
                                tri_line <= 2;
                                draw_x <= arg_x3[12:0];
                                draw_y <= arg_y3[12:0];
                                end_x <= arg_x[12:0];
                                end_y <= arg_y[12:0];
                                draw_state <= 5;
                            end else begin
                                draw_state <= 0; // Done
                            end
                        end else begin
                            draw_state <= 7; // Go compute next step
                        end
                    end else if (cmd == 4) begin
                        if (circ_octant == 7) begin
                            draw_state <= 9; // Advance circle math
                        end else begin
                            circ_octant <= circ_octant + 1;
                            draw_state <= 8; // Draw next octant
                        end
                    end else if (cmd == 5) begin
                        if (draw_x >= end_x) begin
                            if (circ_octant == 3) begin
                                draw_state <= 9; // Advance circle math
                            end else begin
                                circ_octant <= circ_octant + 1;
                                draw_state <= 10; // Draw next line
                            end
                        end else begin
                            draw_x <= draw_x + 1;
                            draw_state <= 1;
                        end
                    end else if (cmd == 7) begin
                        if (draw_x >= end_x) begin
                            draw_state <= 21; // Move to next scanline logic
                        end else begin
                            draw_x <= draw_x + 1;
                            draw_state <= 1;
                        end
                    end
                end
                
                5: begin
                    if (end_x > draw_x) begin
                        dx <= $signed({1'b0, end_x}) - $signed({1'b0, draw_x});
                        sx <= 1;
                    end else begin
                        dx <= $signed({1'b0, draw_x}) - $signed({1'b0, end_x});
                        sx <= 2;
                    end
                    
                    if (end_y > draw_y) begin
                        dy <= $signed({1'b0, draw_y}) - $signed({1'b0, end_y}); // -abs()
                        sy <= 1;
                    end else begin
                        dy <= $signed({1'b0, end_y}) - $signed({1'b0, draw_y}); // -abs()
                        sy <= 2;
                    end
                    
                    draw_state <= 6;
                end
                
                6: begin
                    err <= dx + dy;
                    draw_state <= 1; // Go draw first pixel
                end
                
                7: begin
                    if ((err * 2) >= dy && (err * 2) <= dx) begin
                        err <= err + dy + dx;
                        draw_x <= (sx == 1) ? draw_x + 1 : draw_x - 1;
                        draw_y <= (sy == 1) ? draw_y + 1 : draw_y - 1;
                    end else if ((err * 2) >= dy) begin
                        err <= err + dy;
                        draw_x <= (sx == 1) ? draw_x + 1 : draw_x - 1;
                    end else if ((err * 2) <= dx) begin
                        err <= err + dx;
                        draw_y <= (sy == 1) ? draw_y + 1 : draw_y - 1;
                    end
                    
                    draw_state <= 1;
                end
                
                8: begin
                    case (circ_octant)
                        0: begin draw_x <= arg_x[12:0] + circ_x; draw_y <= arg_y[12:0] + circ_y; end
                        1: begin draw_x <= arg_x[12:0] + circ_y; draw_y <= arg_y[12:0] + circ_x; end
                        2: begin draw_x <= arg_x[12:0] - circ_y; draw_y <= arg_y[12:0] + circ_x; end
                        3: begin draw_x <= arg_x[12:0] - circ_x; draw_y <= arg_y[12:0] + circ_y; end
                        4: begin draw_x <= arg_x[12:0] - circ_x; draw_y <= arg_y[12:0] - circ_y; end
                        5: begin draw_x <= arg_x[12:0] - circ_y; draw_y <= arg_y[12:0] - circ_x; end
                        6: begin draw_x <= arg_x[12:0] + circ_y; draw_y <= arg_y[12:0] - circ_x; end
                        7: begin draw_x <= arg_x[12:0] + circ_x; draw_y <= arg_y[12:0] - circ_y; end
                    endcase
                    draw_state <= 1; // Go draw pixel
                end
                
                9: begin
                    if (circ_err <= 0) begin
                        circ_err <= circ_err + (circ_y <<< 1) + 3;
                        circ_y <= circ_y + 1;
                        if (circ_x >= (circ_y + 1)) begin
                            circ_octant <= 0;
                            draw_state <= (cmd == 5) ? 10 : 8;
                        end else begin
                            draw_state <= 0;
                        end
                    end else begin
                        circ_err <= circ_err + (circ_y <<< 1) - (circ_x <<< 1) + 5;
                        circ_x <= (circ_x > 0) ? circ_x - 1 : 0;
                        circ_y <= circ_y + 1;
                        if ((circ_x - 1) >= (circ_y + 1)) begin
                            circ_octant <= 0;
                            draw_state <= (cmd == 5) ? 10 : 8;
                        end else begin
                            draw_state <= 0;
                        end
                    end
                end
                
                10: begin
                    // Sort X endpoints robustly
                    if (circ_octant == 0 || circ_octant == 1) begin
                        if (circ_x < 0) begin
                            draw_x <= arg_x[12:0] + circ_x;
                            end_x  <= arg_x[12:0] - circ_x;
                        end else begin
                            draw_x <= arg_x[12:0] - circ_x;
                            end_x  <= arg_x[12:0] + circ_x;
                        end
                    end else begin
                        if (circ_y < 0) begin
                            draw_x <= arg_x[12:0] + circ_y;
                            end_x  <= arg_x[12:0] - circ_y;
                        end else begin
                            draw_x <= arg_x[12:0] - circ_y;
                            end_x  <= arg_x[12:0] + circ_y;
                        end
                    end
                    
                    case (circ_octant)
                        0: draw_y <= arg_y[12:0] + circ_y;
                        1: draw_y <= arg_y[12:0] - circ_y;
                        2: draw_y <= arg_y[12:0] + circ_x;
                        3: draw_y <= arg_y[12:0] - circ_x;
                    endcase
                    
                    draw_state <= 11;
                end
                
                11: begin
                    if (draw_y < 0 || draw_y >= 360 || draw_x >= 640 || end_x < 0) begin
                        // Skip if entirely out of bounds
                        draw_x <= end_x; // This triggers completion in state 4
                        draw_state <= 4;
                    end else begin
                        // Clip left edge to 0 to save cycles
                        if (draw_x < 0) draw_x <= 0;
                        draw_state <= 1;
                    end
                end
                
                12: begin
                    if (ty0 > ty1) begin
                        tx0 <= tx1; ty0 <= ty1;
                        tx1 <= tx0; ty1 <= ty0;
                    end
                    draw_state <= 13;
                end
                
                13: begin
                    if (ty1 > ty2) begin
                        tx1 <= tx2; ty1 <= ty2;
                        tx2 <= tx1; ty2 <= ty1;
                    end
                    draw_state <= 14;
                end
                
                14: begin
                    if (ty0 > ty1) begin
                        tx0 <= tx1; ty0 <= ty1;
                        tx1 <= tx0; ty1 <= ty0;
                    end
                    draw_state <= 15;
                end
                
                15: begin
                    scan_y <= ty0;
                    tri_half <= 0;
                    xA <= tx0; yA <= ty0; end_xA <= tx2; end_yA <= ty2;
                    xB <= tx0; yB <= ty0; end_xB <= tx1; end_yB <= ty1;
                    draw_state <= 16;
                end
                
                16: begin
                    dxA <= (end_xA > xA) ? (end_xA - xA) : (xA - end_xA);
                    dyA <= (end_yA > yA) ? (yA - end_yA) : (end_yA - yA);
                    sxA <= (end_xA > xA) ? 1 : 2;

                    dxB <= (end_xB > xB) ? (end_xB - xB) : (xB - end_xB);
                    dyB <= (end_yB > yB) ? (yB - end_yB) : (end_yB - yB);
                    sxB <= (end_xB > xB) ? 1 : 2;
                    
                    draw_state <= 17;
                end
                
                17: begin
                    errA <= dxA + dyA;
                    errB <= dxB + dyB;
                    draw_state <= 18;
                end
                
                18: begin
                    if (yA < scan_y && yA < end_yA) begin
                        if ((errA <<< 1) >= dyA && (errA <<< 1) <= dxA) begin
                            errA <= errA + dyA + dxA;
                            xA <= (sxA == 1) ? xA + 1 : xA - 1;
                            yA <= yA + 1;
                        end else if ((errA <<< 1) >= dyA) begin
                            errA <= errA + dyA;
                            xA <= (sxA == 1) ? xA + 1 : xA - 1;
                        end else if ((errA <<< 1) <= dxA) begin
                            errA <= errA + dxA;
                            yA <= yA + 1;
                        end
                    end else begin
                        draw_state <= 19;
                    end
                end
                
                19: begin
                    if (yB < scan_y && yB < end_yB) begin
                        if ((errB <<< 1) >= dyB && (errB <<< 1) <= dxB) begin
                            errB <= errB + dyB + dxB;
                            xB <= (sxB == 1) ? xB + 1 : xB - 1;
                            yB <= yB + 1;
                        end else if ((errB <<< 1) >= dyB) begin
                            errB <= errB + dyB;
                            xB <= (sxB == 1) ? xB + 1 : xB - 1;
                        end else if ((errB <<< 1) <= dxB) begin
                            errB <= errB + dxB;
                            yB <= yB + 1;
                        end
                    end else begin
                        draw_state <= 20;
                    end
                end
                
                20: begin
                    if (scan_y > ty2 || scan_y >= 360) begin
                        draw_state <= 0;
                    end else if (scan_y < 0) begin
                        draw_state <= 21;
                    end else begin
                        draw_y <= scan_y;
                        if (xA < xB) begin
                            draw_x <= xA; end_x <= xB;
                        end else begin
                            draw_x <= xB; end_x <= xA;
                        end
                        draw_state <= 11;
                    end
                end
                
                21: begin
                    if (scan_y >= ty1 && tri_half == 0) begin
                        tri_half <= 1;
                        scan_y <= scan_y + 1;
                        xB <= tx1; yB <= ty1; end_xB <= tx2; end_yB <= ty2;
                        draw_state <= 22;
                    end else begin
                        scan_y <= scan_y + 1;
                        draw_state <= 18;
                    end
                end
                
                22: begin
                    dxB <= (end_xB > xB) ? (end_xB - xB) : (xB - end_xB);
                    dyB <= (end_yB > yB) ? (yB - end_yB) : (end_yB - yB);
                    sxB <= (end_xB > xB) ? 1 : 2;
                    draw_state <= 23;
                end
                
                23: begin
                    errB <= dxB + dyB;
                    draw_state <= 18;
                end
                24: begin
                    font_row_addr <= {arg_w[6:0], char_row[2:0]};
                    draw_state <= 25;
                end
                
                25: begin
                    font_row_data <= font_rom[font_row_addr];
                    draw_state <= 26;
                end
                
                26: begin
                    if (font_row_data[char_col] && draw_x >= 0 && draw_x < 640 && draw_y >= 0 && draw_y < 360) begin
                        mem_addr <= (draw_y[8:0] * 160) + draw_x[9:2] + fb_offset;
                        case (draw_x[1:0])
                            2'b00: begin mem_wstrb <= 4'b0001; mem_data <= {24'd0, arg_c}; end
                            2'b01: begin mem_wstrb <= 4'b0010; mem_data <= {16'd0, arg_c, 8'd0}; end
                            2'b10: begin mem_wstrb <= 4'b0100; mem_data <= {8'd0, arg_c, 16'd0}; end
                            2'b11: begin mem_wstrb <= 4'b1000; mem_data <= {arg_c, 24'd0}; end
                        endcase
                        mem_req <= 1;
                        draw_state <= 27;
                    end else begin
                        draw_state <= 29;
                    end
                end
                
                27: begin
                    if (mem_ack) begin
                        mem_req <= 0;
                        draw_state <= 28;
                    end
                end
                
                28: begin
                    draw_state <= 29;
                end
                
                29: begin
                    if (char_col == 7) begin
                        char_col <= 0;
                        draw_x <= arg_x[12:0];
                        if (char_row == 7) begin
                            draw_state <= 0; // Done
                        end else begin
                            char_row <= char_row + 1;
                            draw_y <= draw_y + 1;
                            draw_state <= 24;
                        end
                    end else begin
                        char_col <= char_col + 1;
                        draw_x <= draw_x + 1;
                        draw_state <= 26;
                    end
                end
                
                30: begin
                    sprite_addr <= {arg_c[4:0], char_row, char_col};
                    draw_state <= 31;
                end
                
                31: begin
                    font_row_data <= sprite_ram[sprite_addr];
                    draw_state <= 32;
                end
                
                32: begin
                    if (font_row_data != 8'hE3 && draw_x >= 0 && draw_x < 640 && draw_y >= 0 && draw_y < 360) begin
                        mem_addr <= (draw_y[8:0] * 160) + draw_x[9:2] + fb_offset;
                        case (draw_x[1:0])
                            2'b00: begin mem_wstrb <= 4'b0001; mem_data <= {24'd0, font_row_data}; end
                            2'b01: begin mem_wstrb <= 4'b0010; mem_data <= {16'd0, font_row_data, 8'd0}; end
                            2'b10: begin mem_wstrb <= 4'b0100; mem_data <= {8'd0, font_row_data, 16'd0}; end
                            2'b11: begin mem_wstrb <= 4'b1000; mem_data <= {font_row_data, 24'd0}; end
                        endcase
                        mem_req <= 1;
                        draw_state <= 33;
                    end else begin
                        draw_state <= 35;
                    end
                end
                
                33: begin
                    if (mem_ack) begin
                        mem_req <= 0;
                        draw_state <= 34;
                    end
                end
                
                34: begin
                    draw_state <= 35;
                end
                
                35: begin
                    if (char_col == 15) begin
                        char_col <= 0;
                        draw_x <= arg_x[12:0];
                        if (char_row == 15) begin
                            draw_state <= 0; // Done
                        end else begin
                            char_row <= char_row + 1;
                            draw_y <= draw_y + 1;
                            draw_state <= 30;
                        end
                    end else begin
                        char_col <= char_col + 1;
                        draw_x <= draw_x + 1;
                        draw_state <= 30;
                    end
                end
            endcase
        end
    end
endmodule
