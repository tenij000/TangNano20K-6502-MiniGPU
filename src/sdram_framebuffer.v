`timescale 1ns / 1ps

module sdram_framebuffer (
    input  wire        clk,        // 74.25 MHz pixel clock
    input  wire        rst_n,

    // External UART write interface (for PC Python scripts in mode 1 & 2)
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire [1:0]  uart_mode,

    // 6502 CPU -> GPU Command Stream Interface ($A020)
    input  wire        cpu_gpu_req_toggle,
    input  wire [7:0]  cpu_gpu_data,
    output reg         cpu_gpu_ack_toggle = 0,

    // Hardware Space Planets / Farm Landscape Auto-Background (MODE 0 / BASIC) + 720p Hardware RTC HUD
    input  wire        space_bg_en,
    input  wire        bg_theme,
    input  wire [24:0] rtc_hud_data,
    input  wire        restore_bg_req_toggle,
    output reg         restore_bg_ack_toggle = 0,

    // 6502 CPU -> 4 MB SDRAM-Disk Interface ($A012-$A015, upper 4 MB of SDRAM)
    input  wire        rd_req_toggle,
    input  wire        rd_req_we,
    input  wire [21:0] rd_req_addr,
    input  wire [7:0]  rd_req_wdata,
    output reg  [7:0]  rd_rdata = 0,
    output reg         rd_ack_toggle = 0,

    // HDMI read interface
    input  wire [10:0] cx,         // current X
    input  wire [9:0]  cy,         // current Y
    output wire [23:0] rgb,        // output color

    // SDRAM Physical Pins
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    inout  wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm,

    output wire        audio_we,
    output wire [1:0]  audio_channel,
    output wire [23:0] audio_phase_inc,
    output wire [7:0]  audio_volume
);

    // ==========================================
    // UART Writer State Machine
    // ==========================================
    reg [9:0]  write_x = 0;
    reg [8:0]  write_y = 0;
    reg        uart_write_req = 0;
    reg [20:0] uart_word_addr = 0;
    reg [31:0] uart_din = 0;
    reg [3:0]  uart_wstrb = 0;
    wire       uart_write_ack;

    reg [2:0] rx_valid_sync = 0;
    wire rx_valid_pulse = rx_valid_sync[1] && !rx_valid_sync[2];

    always @(posedge clk) begin
        if (!rst_n) begin
            write_x <= 0;
            write_y <= 0;
            uart_write_req <= 0;
            rx_valid_sync <= 0;
        end else begin
            rx_valid_sync <= {rx_valid_sync[1:0], rx_valid};

            if (uart_write_ack) uart_write_req <= 0;

            if (rx_valid_pulse && (uart_mode == 1)) begin
                uart_word_addr <= (write_y * 160) + write_x[9:2];

                case (write_x[1:0])
                    2'b00: begin uart_wstrb <= 4'b0001; uart_din <= {24'd0, rx_data}; end
                    2'b01: begin uart_wstrb <= 4'b0010; uart_din <= {16'd0, rx_data, 8'd0}; end
                    2'b10: begin uart_wstrb <= 4'b0100; uart_din <= {8'd0, rx_data, 16'd0}; end
                    2'b11: begin uart_wstrb <= 4'b1000; uart_din <= {rx_data, 24'd0}; end
                endcase

                uart_write_req <= 1;

                if (write_x == 639) begin
                    write_x <= 0;
                    if (write_y == 359) write_y <= 0;
                    else write_y <= write_y + 1;
                end else begin
                    write_x <= write_x + 1;
                end
            end
        end
    end

    // ==========================================
    // Line Fetcher State Machine
    // ==========================================
    reg [1:0] lb_fetch_state = 0;
    reg [7:0] lb_fetch_col = 0;
    reg [8:0] lb_fetch_y = 0;

    reg       lb_read_req = 0;
    wire      lb_read_ack;

    wire      lb_we;       // from arbiter
    wire [31:0] lb_wdata;  // from arbiter

    always @(posedge clk) begin
        if (!rst_n) begin
            lb_fetch_state <= 0;
            lb_read_req <= 0;
        end else begin
            case (lb_fetch_state)
                0: begin
                    if (cx == 0 && cy[0] == 0) begin
                        if (cy == 748) begin
                            lb_fetch_y     <= 9'd0;
                            lb_fetch_col   <= 0;
                            lb_fetch_state <= 1;
                        end else if ((cy >> 1) < 359) begin
                            lb_fetch_y     <= (cy >> 1) + 9'd1;
                            lb_fetch_col   <= 0;
                            lb_fetch_state <= 1;
                        end
                    end
                end
                1: begin
                    lb_read_req    <= 1;
                    lb_fetch_state <= 2;
                end
                2: begin
                    if (lb_read_ack) begin
                        lb_read_req <= 0;
                        lb_fetch_state <= 3;
                    end
                end
                3: begin
                    if (lb_we) begin
                        if (lb_fetch_col == 159) begin
                            lb_fetch_state <= 0; // done
                        end else begin
                            lb_fetch_col   <= lb_fetch_col + 1;
                            lb_read_req    <= 1;
                            lb_fetch_state <= 2; // next column immediately (no bubble)
                        end
                    end
                end
            endcase
        end
    end

    // ==========================================
    // BRAM Line Buffer (Ping-Pong)
    // ==========================================
    reg [31:0] line_buffer [0:511];
    wire [8:0] lb_waddr = {lb_fetch_y[0], lb_fetch_col};

    always @(posedge clk) begin
        if (lb_we) begin
            line_buffer[lb_waddr] <= lb_wdata;
        end
    end

    // Output pixels
    wire [9:0] fb_x = cx[10:1];
    wire [8:0] fb_y = cy[9:1];

    wire [31:0] lb_rword = line_buffer[ {fb_y[0], fb_x[9:2]} ];
    reg [7:0]   lb_rbyte;

    always @(*) begin
        case (fb_x[1:0])
            2'b00: lb_rbyte = lb_rword[7:0];
            2'b01: lb_rbyte = lb_rword[15:8];
            2'b10: lb_rbyte = lb_rword[23:16];
            2'b11: lb_rbyte = lb_rword[31:24];
        endcase
    end

    // Big Sprite Hardware Engine wires
    wire        big_spr_we_ctrl;
    wire        big_spr_ctrl_slot;
    wire        big_spr_ctrl_enable;
    wire signed [15:0] big_spr_ctrl_x;
    wire signed [15:0] big_spr_ctrl_y;
    wire [7:0]  big_spr_ctrl_flags;
    wire        big_spr_we_ram;
    wire        big_spr_ram_slot;
    wire [13:0] big_spr_ram_addr;
    wire [7:0]  big_spr_ram_din;
    wire [7:0]  big_spr_color;
    wire        big_spr_active;

    wire [7:0] bg_color;
    wire [7:0] space_bg_color;
    wire [7:0] farm_bg_color;

    reg [1:0]  space_bg_en_sync = 2'b11;
    reg [1:0]  bg_theme_sync    = 2'b11;
    reg [24:0] rtc_sync0        = 25'h1_12_00_00;
    reg [24:0] rtc_sync1        = 25'h1_12_00_00;
    reg [24:0] rtc_frame        = 25'h1_12_00_00;

    always @(posedge clk) begin
        rtc_sync0 <= rtc_hud_data;
        rtc_sync1 <= rtc_sync0;
        if (cx == 11'd0 && cy == 10'd720) begin
            rtc_frame <= rtc_sync1;
        end
        if (!rst_n) begin
            space_bg_en_sync <= 2'b11;
            bg_theme_sync    <= 2'b11;
        end else begin
            space_bg_en_sync <= {space_bg_en_sync[0], space_bg_en};
            bg_theme_sync    <= {bg_theme_sync[0], bg_theme};
        end
    end

    // =========================================================================
    // 2-Stage Pipelined 720p Hardware Real-Time Clock HUD (Top-Right: 1104..1259, 10..46)
    // =========================================================================
    wire [10:0] hx    = cx + 11'd2;
    wire [9:0]  hy    = cy;
    wire [6:0]  rel_x = hx[6:0] - 7'd94; // (hx - 1118) mod 128 since 1118 = 8*128 + 94

    reg       s1_in_box     = 0;
    reg       s1_border_out = 0;
    reg       s1_border_in  = 0;
    reg       s1_in_digits  = 0;
    reg       s1_is_colon   = 0;
    reg       s1_is_sec     = 0;
    reg [3:0] s1_dx         = 0;
    reg [4:0] s1_dy         = 0;
    reg [3:0] s1_bcd        = 0;

    always @(posedge clk) begin
        s1_in_box     <= (hx >= 11'd1104) && (hx <= 11'd1259) && (hy >= 10'd10) && (hy <= 10'd46) &&
                         !((hx == 11'd1104 || hx == 11'd1259) && (hy == 10'd10 || hy == 10'd46));
        s1_border_out <= (hx <= 11'd1105) || (hx >= 11'd1258) || (hy <= 10'd11) || (hy >= 10'd45);
        s1_border_in  <= (hx == 11'd1107) || (hx == 11'd1256) || (hy == 10'd13) || (hy == 10'd43);
        s1_in_digits  <= (hx >= 11'd1118) && (hx <= 11'd1245) && (hy >= 10'd16) && (hy <= 10'd40);
        s1_is_colon   <= (rel_x[6:4] == 3'd2) || (rel_x[6:4] == 3'd5);
        s1_is_sec     <= (rel_x[6:4] >= 3'd6);
        s1_dx         <= rel_x[3:0];
        s1_dy         <= hy[4:0] - 5'd16;
        case (rel_x[6:4])
            3'd0:    s1_bcd <= rtc_frame[23:20];
            3'd1:    s1_bcd <= rtc_frame[19:16];
            3'd3:    s1_bcd <= rtc_frame[15:12];
            3'd4:    s1_bcd <= rtc_frame[11:8];
            3'd6:    s1_bcd <= rtc_frame[7:4];
            default: s1_bcd <= rtc_frame[3:0];
        endcase
    end

    reg [6:0] seg_mask;
    always @(*) begin
        case (s1_bcd)
            4'd0:    seg_mask = 7'b1111110;
            4'd1:    seg_mask = 7'b0110000;
            4'd2:    seg_mask = 7'b1101101;
            4'd3:    seg_mask = 7'b1111001;
            4'd4:    seg_mask = 7'b0110011;
            4'd5:    seg_mask = 7'b1011011;
            4'd6:    seg_mask = 7'b1011111;
            4'd7:    seg_mask = 7'b1110000;
            4'd8:    seg_mask = 7'b1111111;
            4'd9:    seg_mask = 7'b1111011;
            default: seg_mask = 7'b0000000;
        endcase
    end

    wire seg_a     = (s1_dy <= 5'd2)  && (s1_dx >= 4'd2)  && (s1_dx <= 4'd13);
    wire seg_g     = (s1_dy >= 5'd11) && (s1_dy <= 5'd13) && (s1_dx >= 4'd2)  && (s1_dx <= 4'd13);
    wire seg_d     = (s1_dy >= 5'd22) && (s1_dy <= 5'd24) && (s1_dx >= 4'd2)  && (s1_dx <= 4'd13);
    wire seg_f     = (s1_dx >= 4'd2)  && (s1_dx <= 4'd4)  && (s1_dy <= 5'd12);
    wire seg_b     = (s1_dx >= 4'd11) && (s1_dx <= 4'd13) && (s1_dy <= 5'd12);
    wire seg_e     = (s1_dx >= 4'd2)  && (s1_dx <= 4'd4)  && (s1_dy >= 5'd12) && (s1_dy <= 5'd24);
    wire seg_c     = (s1_dx >= 4'd11) && (s1_dx <= 4'd13) && (s1_dy >= 5'd12) && (s1_dy <= 5'd24);
    wire seg_any   = seg_a | seg_b | seg_c | seg_d | seg_e | seg_f | seg_g;
    wire seg_lit   = (seg_a & seg_mask[6]) | (seg_b & seg_mask[5]) | (seg_c & seg_mask[4]) |
                     (seg_d & seg_mask[3]) | (seg_e & seg_mask[2]) | (seg_f & seg_mask[1]) | (seg_g & seg_mask[0]);
    wire colon_dot = (s1_dx >= 4'd6) && (s1_dx <= 4'd9) &&
                     (((s1_dy >= 5'd6) && (s1_dy <= 5'd9)) || ((s1_dy >= 5'd15) && (s1_dy <= 5'd18)));

    reg       rtc_hud_active = 0;
    reg [7:0] rtc_hud_color  = 0;

    always @(posedge clk) begin
        rtc_hud_active <= s1_in_box;
        if (s1_border_out) begin
            rtc_hud_color <= bg_theme_sync[1] ? 8'hFC : 8'h1F;
        end else if (s1_border_in) begin
            rtc_hud_color <= bg_theme_sync[1] ? 8'h88 : 8'h0B;
        end else if (s1_in_digits && s1_is_colon && colon_dot) begin
            rtc_hud_color <= rtc_frame[24] ? (bg_theme_sync[1] ? 8'hFC : 8'h1F)
                                           : (bg_theme_sync[1] ? 8'h44 : 8'h05);
        end else if (s1_in_digits && !s1_is_colon && seg_lit) begin
            rtc_hud_color <= s1_is_sec ? (bg_theme_sync[1] ? 8'hFC : 8'h1F) : 8'hFF;
        end else if (s1_in_digits && !s1_is_colon && seg_any) begin
            rtc_hud_color <= bg_theme_sync[1] ? 8'h20 : 8'h01;
        end else begin
            rtc_hud_color <= 8'h00;
        end
    end

    // Mix layers:
    // Top: Big Sprites (2x 128x128 Hardware Sprites) if active and != 0xE3
    // Middle: SDRAM Framebuffer (lb_rbyte) if != 0xE3 (Transparant)
    // Bottom: Space Planets or Farm Landscape + Hardware RTC HUD (in MODE 0 / BASIC) or Background Tilemap (in MODE 1)
    wire [7:0] base_hw_bg    = bg_theme_sync[1] ? farm_bg_color : space_bg_color;
    wire [7:0] hw_bg_color   = rtc_hud_active ? rtc_hud_color : base_hw_bg;
    wire [7:0] base_bg_color = space_bg_en_sync[1] ? hw_bg_color : bg_color;
    wire [7:0] fb_or_bg      = (lb_rbyte == 8'hE3) ? base_bg_color : lb_rbyte;
    wire [7:0] final_color   = (big_spr_active && (big_spr_color != 8'hE3)) ? big_spr_color : fb_or_bg;

    // Convert 8-bit RGB332 to 24-bit RGB888
    wire [2:0] r3 = final_color[7:5];
    wire [2:0] g3 = final_color[4:2];
    wire [1:0] b2 = final_color[1:0];

    wire [7:0] r8 = {r3, r3, r3[2:1]};
    wire [7:0] g8 = {g3, g3, g3[2:1]};
    wire [7:0] b8 = {b2, b2, b2, b2};

    // Active display region check
    wire active = (cx < 1280 && cy < 720);
    assign rgb = active ? {r8, g8, b8} : 24'd0;

    // ==========================================
    // 6502 CPU -> GPU Command Synchronizer & Auto-Restore Synchronizer
    // ==========================================
    wire       gpu_busy;
    reg  [2:0] cpu_gpu_sync = 0;
    reg  [1:0] cpu_gpu_state = 0;
    reg        cpu_gpu_pulse = 0;
    reg  [7:0] cpu_gpu_latched = 0;

    reg  [2:0] restore_bg_sync = 0;
    reg  [1:0] restore_bg_state = 0;
    reg        restore_bg_pulse = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            cpu_gpu_sync          <= 0;
            cpu_gpu_state         <= 0;
            cpu_gpu_pulse         <= 0;
            cpu_gpu_ack_toggle    <= 0;
            cpu_gpu_latched       <= 0;
            restore_bg_sync       <= 0;
            restore_bg_state      <= 0;
            restore_bg_pulse      <= 0;
            restore_bg_ack_toggle <= 0;
        end else begin
            cpu_gpu_sync     <= {cpu_gpu_sync[1:0], cpu_gpu_req_toggle};
            cpu_gpu_pulse    <= 0;
            restore_bg_sync  <= {restore_bg_sync[1:0], restore_bg_req_toggle};
            restore_bg_pulse <= 0;

            case (cpu_gpu_state)
                0: begin
                    if ((cpu_gpu_sync[2] != cpu_gpu_ack_toggle) && !gpu_busy && (restore_bg_state == 0)) begin
                        cpu_gpu_latched <= cpu_gpu_data;
                        cpu_gpu_pulse   <= 1;
                        cpu_gpu_state   <= 1;
                    end
                end
                1: begin
                    // Wait 1 cycle for gpu_engine to assert start_draw / busy if applicable
                    cpu_gpu_state <= 2;
                end
                2: begin
                    if (!gpu_busy) begin
                        cpu_gpu_ack_toggle <= cpu_gpu_sync[2];
                        cpu_gpu_state      <= 0;
                    end
                end
            endcase

            case (restore_bg_state)
                0: begin
                    if ((restore_bg_sync[2] != restore_bg_ack_toggle) && !gpu_busy && (cpu_gpu_state == 0) && !(cpu_gpu_sync[2] != cpu_gpu_ack_toggle)) begin
                        restore_bg_pulse <= 1;
                        restore_bg_state <= 1;
                    end
                end
                1: begin
                    restore_bg_state <= 2;
                end
                2: begin
                    if (!gpu_busy) begin
                        restore_bg_ack_toggle <= restore_bg_sync[2];
                        restore_bg_state      <= 0;
                    end
                end
            endcase
        end
    end

    wire       uart_gpu_valid = rx_valid_pulse && (uart_mode == 2);
    wire       gpu_rx_valid   = cpu_gpu_pulse | uart_gpu_valid;
    wire [7:0] gpu_rx_data    = cpu_gpu_pulse ? cpu_gpu_latched : rx_data;

    // ==========================================
    // GPU Engine Integration
    // ==========================================
    wire        gpu_write_req;
    wire        gpu_write_ack;
    wire [20:0] gpu_word_addr;
    wire [31:0] gpu_din;
    wire [3:0]  gpu_wstrb;

    wire front_buffer;

    // Background wires
    wire        we_tileset;
    wire [13:0] addr_tileset;
    wire [7:0]  din_tileset;
    wire        we_tilemap;
    wire [11:0] addr_tilemap;
    wire [7:0]  din_tilemap;
    wire [9:0]  scroll_x;
    wire [9:0]  scroll_y;

    gpu_engine gpu_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(gpu_rx_data),
        .rx_valid(gpu_rx_valid),
        .restore_bg_pulse(restore_bg_pulse),
        .mem_req(gpu_write_req),
        .mem_ack(gpu_write_ack),
        .mem_addr(gpu_word_addr),
        .mem_data(gpu_din),
        .mem_wstrb(gpu_wstrb),
        .front_buffer(front_buffer),
        .we_tileset(we_tileset),
        .addr_tileset(addr_tileset),
        .din_tileset(din_tileset),
        .we_tilemap(we_tilemap),
        .addr_tilemap(addr_tilemap),
        .din_tilemap(din_tilemap),
        .scroll_x(scroll_x),
        .scroll_y(scroll_y),
        .audio_we(audio_we),
        .audio_channel(audio_channel),
        .audio_phase_inc(audio_phase_inc),
        .audio_volume(audio_volume),
        .big_spr_we_ctrl(big_spr_we_ctrl),
        .big_spr_ctrl_slot(big_spr_ctrl_slot),
        .big_spr_ctrl_enable(big_spr_ctrl_enable),
        .big_spr_ctrl_x(big_spr_ctrl_x),
        .big_spr_ctrl_y(big_spr_ctrl_y),
        .big_spr_ctrl_flags(big_spr_ctrl_flags),
        .big_spr_we_ram(big_spr_we_ram),
        .big_spr_ram_slot(big_spr_ram_slot),
        .big_spr_ram_addr(big_spr_ram_addr),
        .big_spr_ram_din(big_spr_ram_din),
        .busy(gpu_busy)
    );

    bg_layer bg_inst (
        .clk_pixel(clk),
        .rst_n(rst_n),
        .cx(cx),
        .cy(cy),
        .bg_color(bg_color),
        .we_tileset(we_tileset),
        .addr_tileset(addr_tileset),
        .din_tileset(din_tileset),
        .we_tilemap(we_tilemap),
        .addr_tilemap(addr_tilemap),
        .din_tilemap(din_tilemap),
        .scroll_x(scroll_x),
        .scroll_y(scroll_y)
    );

    space_planets_bg space_bg_inst (
        .clk_pixel(clk),
        .rst_n(rst_n),
        .cx(cx),
        .cy(cy),
        .space_color(space_bg_color)
    );

    farm_landscape_bg farm_bg_inst (
        .clk_pixel(clk),
        .rst_n(rst_n),
        .cx(cx),
        .cy(cy),
        .farm_color(farm_bg_color)
    );

    big_sprite_engine big_spr_inst (
        .clk_pixel(clk),
        .rst_n(rst_n),
        .cx(cx),
        .cy(cy),
        .spr_color(big_spr_color),
        .spr_active(big_spr_active),
        .clear_all(restore_bg_pulse),
        .we_ctrl(big_spr_we_ctrl),
        .ctrl_slot(big_spr_ctrl_slot),
        .ctrl_enable(big_spr_ctrl_enable),
        .ctrl_x(big_spr_ctrl_x),
        .ctrl_y(big_spr_ctrl_y),
        .ctrl_flags(big_spr_ctrl_flags),
        .we_ram(big_spr_we_ram),
        .ram_slot(big_spr_ram_slot),
        .ram_addr(big_spr_ram_addr),
        .ram_din(big_spr_ram_din)
    );

    // ==========================================
    // SDRAM Arbiter (with 4 MB CPU SDRAM-Disk Port)
    // ==========================================
    wire sdram_busy;
    wire sdram_data_ready;
    wire [31:0] sdram_dout;

    reg sdram_rd = 0;
    reg sdram_wr = 0;
    reg sdram_refresh = 0;
    reg [20:0] sdram_addr = 0;
    reg [31:0] sdram_din = 0;
    reg [3:0]  sdram_wstrb = 0;

    reg [9:0] refresh_counter = 0;
    reg refresh_req = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            refresh_counter <= 0;
            refresh_req <= 0;
        end else begin
            if (refresh_counter >= 500) begin
                refresh_counter <= 0;
                refresh_req <= 1;
            end else begin
                refresh_counter <= refresh_counter + 1;
            end
            if (arb_state == ARB_REFRESH && !sdram_busy) begin
                refresh_req <= 0;
            end
        end
    end

    localparam ARB_IDLE      = 0;
    localparam ARB_WAIT_BUSY = 1;
    localparam ARB_REFRESH   = 2;
    localparam ARB_WRITE     = 3;
    localparam ARB_READ      = 4;
    localparam ARB_WRITE_GPU = 5;
    localparam ARB_WRITE_CPU = 6;
    localparam ARB_READ_CPU  = 7;

    reg [2:0] arb_state = 0;
    reg [2:0] arb_next_state = 0;

    reg lb_read_ack_reg = 0;
    reg lb_we_reg = 0;
    reg [31:0] lb_wdata_reg = 0;
    reg uart_write_ack_reg = 0;
    reg gpu_write_ack_reg = 0;

    reg [2:0] rd_req_sync = 0;
    reg [1:0] rd_byte_sel = 0;

    assign lb_read_ack = lb_read_ack_reg;
    assign lb_we = lb_we_reg;
    assign lb_wdata = lb_wdata_reg;
    assign uart_write_ack = uart_write_ack_reg;
    assign gpu_write_ack = gpu_write_ack_reg;

    // Prioritize finishing the scanline prefetch during the second half of the scanline pair (cy[0] == 1)
    wire lb_urgent = (lb_fetch_state != 0) && (cy[0] == 1);

    always @(posedge clk) begin
        if (!rst_n) begin
            arb_state <= ARB_IDLE;
            sdram_rd <= 0;
            sdram_wr <= 0;
            sdram_refresh <= 0;
            rd_req_sync <= 0;
            rd_ack_toggle <= 0;
            rd_rdata <= 0;
        end else begin
            rd_req_sync <= {rd_req_sync[1:0], rd_req_toggle};
            lb_read_ack_reg <= 0;
            lb_we_reg <= 0;
            uart_write_ack_reg <= 0;
            gpu_write_ack_reg <= 0;
            sdram_rd <= 0;
            sdram_wr <= 0;
            sdram_refresh <= 0;

            case (arb_state)
                ARB_IDLE: begin
                    if (!sdram_busy) begin
                        if (refresh_req) begin
                            sdram_refresh <= 1;
                            arb_next_state <= ARB_REFRESH;
                            arb_state <= ARB_WAIT_BUSY;
                        end else if (lb_read_req) begin
                            sdram_addr <= (lb_fetch_y * 160) + lb_fetch_col + (front_buffer ? 21'd57600 : 21'd0);
                            sdram_rd <= 1;
                            lb_read_ack_reg <= 1;
                            arb_next_state <= ARB_READ;
                            arb_state <= ARB_WAIT_BUSY;
                        end else if (lb_urgent) begin
                            // Hold arbiter ready for lb_read_req during second scanline half (cy[0] == 1)
                        end else if (rd_req_sync[2] != rd_ack_toggle) begin
                            // Upper 4 MB of SDRAM (word address bit 20 = 1) - High priority for zero-jitter Audio Hulp-CPU & 6502 RAM
                            sdram_addr  <= {1'b1, rd_req_addr[21:2]};
                            rd_byte_sel <= rd_req_addr[1:0];
                            if (rd_req_we) begin
                                case (rd_req_addr[1:0])
                                    2'b00: begin sdram_wstrb <= 4'b0001; sdram_din <= {24'd0, rd_req_wdata}; end
                                    2'b01: begin sdram_wstrb <= 4'b0010; sdram_din <= {16'd0, rd_req_wdata, 8'd0}; end
                                    2'b10: begin sdram_wstrb <= 4'b0100; sdram_din <= {8'd0, rd_req_wdata, 16'd0}; end
                                    2'b11: begin sdram_wstrb <= 4'b1000; sdram_din <= {rd_req_wdata, 24'd0}; end
                                endcase
                                sdram_wr       <= 1;
                                arb_next_state <= ARB_WRITE_CPU;
                            end else begin
                                sdram_rd       <= 1;
                                arb_next_state <= ARB_READ_CPU;
                            end
                            arb_state <= ARB_WAIT_BUSY;
                        end else if (gpu_write_req) begin
                            sdram_addr <= gpu_word_addr;
                            sdram_din <= gpu_din;
                            sdram_wstrb <= gpu_wstrb;
                            sdram_wr <= 1;
                            gpu_write_ack_reg <= 1;
                            arb_next_state <= ARB_WRITE_GPU;
                            arb_state <= ARB_WAIT_BUSY;
                        end else if (uart_write_req) begin
                            sdram_addr <= uart_word_addr;
                            sdram_din <= uart_din;
                            sdram_wstrb <= uart_wstrb;
                            sdram_wr <= 1;
                            uart_write_ack_reg <= 1;
                            arb_next_state <= ARB_WRITE;
                            arb_state <= ARB_WAIT_BUSY;
                        end
                    end
                end
                ARB_WAIT_BUSY: begin
                    arb_state <= arb_next_state;
                end
                ARB_REFRESH: begin
                    if (!sdram_busy) begin
                        arb_state <= ARB_IDLE;
                    end
                end
                ARB_WRITE: begin
                    if (!sdram_busy) begin
                        arb_state <= ARB_IDLE;
                    end
                end
                ARB_WRITE_GPU: begin
                    if (!sdram_busy) begin
                        arb_state <= ARB_IDLE;
                    end
                end
                ARB_READ: begin
                    if (sdram_data_ready) begin
                        lb_wdata_reg <= sdram_dout;
                        lb_we_reg <= 1;
                        arb_state <= ARB_IDLE;
                    end
                end
                ARB_WRITE_CPU: begin
                    if (!sdram_busy) begin
                        rd_ack_toggle <= rd_req_sync[2];
                        arb_state     <= ARB_IDLE;
                    end
                end
                ARB_READ_CPU: begin
                    if (sdram_data_ready) begin
                        case (rd_byte_sel)
                            2'b00: rd_rdata <= sdram_dout[7:0];
                            2'b01: rd_rdata <= sdram_dout[15:8];
                            2'b10: rd_rdata <= sdram_dout[23:16];
                            2'b11: rd_rdata <= sdram_dout[31:24];
                        endcase
                        rd_ack_toggle <= rd_req_sync[2];
                        arb_state     <= ARB_IDLE;
                    end
                end
            endcase
        end
    end

    // ==========================================
    // SDRAM Controller Instantiation
    // ==========================================
    sdram #(
        .FREQ(74_250_000)
    ) sdram_inst (
        .clk        (clk),
        .clk_sdram  (~clk),
        .resetn     (rst_n),
        .rd         (sdram_rd),
        .wr         (sdram_wr),
        .refresh    (sdram_refresh),
        .addr       (sdram_addr),
        .din        (sdram_din),
        .wstrb      (sdram_wstrb),
        .dout       (sdram_dout),
        .data_ready (sdram_data_ready),
        .busy       (sdram_busy),

        .SDRAM_DQ   (IO_sdram_dq),
        .SDRAM_A    (O_sdram_addr),
        .SDRAM_BA   (O_sdram_ba),
        .SDRAM_nCS  (O_sdram_cs_n),
        .SDRAM_nWE  (O_sdram_wen_n),
        .SDRAM_nRAS (O_sdram_ras_n),
        .SDRAM_nCAS (O_sdram_cas_n),
        .SDRAM_CLK  (O_sdram_clk),
        .SDRAM_CKE  (O_sdram_cke),
        .SDRAM_DQM  (O_sdram_dqm)
    );

endmodule
