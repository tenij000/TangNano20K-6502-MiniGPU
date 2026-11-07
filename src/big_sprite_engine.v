`timescale 1ns / 1ps

// ============================================================================
// MiniGPU Big Sprite Engine (2x 128x128 Hardware Sprites)
// Tang Nano 20K FPGA | Gowin GW2AR-18C
// ============================================================================

module big_sprite_engine (
    input  wire        clk_pixel,  // 74.25 MHz HDMI klok
    input  wire        rst_n,

    // HDMI Raster Coördinaten
    input  wire [10:0] cx,         // 0..1279
    input  wire [9:0]  cy,         // 0..719

    // Pixel Output naar Compositor
    output reg  [7:0]  spr_color,
    output reg         spr_active,

    // Besturingsregisters (via Opcode 0x15)
    input  wire        clear_all,
    input  wire        we_ctrl,
    input  wire        ctrl_slot,     // 0 of 1
    input  wire        ctrl_enable,
    input  wire signed [15:0] ctrl_x, // Signed X positie
    input  wire signed [15:0] ctrl_y, // Signed Y positie
    input  wire [7:0]  ctrl_flags,    // bit 0 = flip_h

    // BRAM Upload Interface (via Opcode 0x16)
    input  wire        we_ram,
    input  wire        ram_slot,      // 0 of 1
    input  wire [13:0] ram_addr,      // 0..16383 (128x128 pixels)
    input  wire [7:0]  ram_din
);

    // ========================================================================
    // Sprite Geheugen (2x 16KB Block RAM)
    // ========================================================================
    reg [7:0] ram_slot0 [0:16383];
    reg [7:0] ram_slot1 [0:16383];

    initial begin
        $readmemh("default_bigspr0.hex", ram_slot0);
        $readmemh("default_bigspr1.hex", ram_slot1);
    end

    // BRAM Write Port
    always @(posedge clk_pixel) begin
        if (we_ram) begin
            if (ram_slot == 1'b0) ram_slot0[ram_addr] <= ram_din;
            else                  ram_slot1[ram_addr] <= ram_din;
        end
    end

    // ========================================================================
    // Besturingsregisters
    // ========================================================================
    reg               spr0_en = 0;
    reg signed [15:0] spr0_x = 0;
    reg signed [15:0] spr0_y = 0;
    reg               spr0_flip_h = 0;

    reg               spr1_en = 0;
    reg signed [15:0] spr1_x = 0;
    reg signed [15:0] spr1_y = 0;
    reg               spr1_flip_h = 0;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            spr0_en <= 0; spr0_x <= 0; spr0_y <= 0; spr0_flip_h <= 0;
            spr1_en <= 0; spr1_x <= 0; spr1_y <= 0; spr1_flip_h <= 0;
        end else if (clear_all) begin
            spr0_en <= 0;
            spr1_en <= 0;
        end else if (we_ctrl) begin
            if (ctrl_slot == 1'b0) begin
                spr0_en     <= ctrl_enable;
                spr0_x      <= ctrl_x;
                spr0_y      <= ctrl_y;
                spr0_flip_h <= ctrl_flags[0];
            end else begin
                spr1_en     <= ctrl_enable;
                spr1_x      <= ctrl_x;
                spr1_y      <= ctrl_y;
                spr1_flip_h <= ctrl_flags[0];
            end
        end
    end

    // ========================================================================
    // HDMI Scanout Pipeline (2 cycli compensatie voor BRAM read)
    // ========================================================================
    wire [10:0] cx_ahead = cx + 11'd2;
    wire [9:0]  px = cx_ahead[10:1]; // 0..639
    wire [8:0]  py = cy[9:1];        // 0..359

    // --- Pijplijn Stap 1: Bounding Box & Relatieve Coördinaten ---
    wire signed [15:0] rel_x0 = $signed({6'd0, px}) - spr0_x;
    wire signed [15:0] rel_y0 = $signed({7'd0, py}) - spr0_y;
    wire in_box0 = spr0_en && (rel_x0 >= 16'sd0) && (rel_x0 < 16'sd128) && (rel_y0 >= 16'sd0) && (rel_y0 < 16'sd128);

    wire signed [15:0] rel_x1 = $signed({6'd0, px}) - spr1_x;
    wire signed [15:0] rel_y1 = $signed({7'd0, py}) - spr1_y;
    wire in_box1 = spr1_en && (rel_x1 >= 16'sd0) && (rel_x1 < 16'sd128) && (rel_y1 >= 16'sd0) && (rel_y1 < 16'sd128);

    // Flip-H spiegeling berekenen
    wire [6:0] u0 = spr0_flip_h ? (7'd127 - rel_x0[6:0]) : rel_x0[6:0];
    wire [6:0] v0 = rel_y0[6:0];
    wire [13:0] addr0 = {v0, u0};

    wire [6:0] u1 = spr1_flip_h ? (7'd127 - rel_x1[6:0]) : rel_x1[6:0];
    wire [6:0] v1 = rel_y1[6:0];
    wire [13:0] addr1 = {v1, u1};

    // --- Pijplijn Stap 2: Synchroon BRAM Uitlezen ---
    reg [7:0] pix0;
    reg [7:0] pix1;
    reg       in_box0_p1;
    reg       in_box1_p1;

    always @(posedge clk_pixel) begin
        pix0       <= ram_slot0[addr0];
        pix1       <= ram_slot1[addr1];
        in_box0_p1 <= in_box0;
        in_box1_p1 <= in_box1;
    end

    // --- Pijplijn Stap 3: Prioriteit Multiplexer & Chroma-Key (0xE3) ---
    wire valid0 = in_box0_p1 && (pix0 != 8'hE3);
    wire valid1 = in_box1_p1 && (pix1 != 8'hE3);

    always @(posedge clk_pixel) begin
        if (valid0) begin
            spr_color  <= pix0;
            spr_active <= 1'b1;
        end else if (valid1) begin
            spr_color  <= pix1;
            spr_active <= 1'b1;
        end else begin
            spr_color  <= 8'hE3;
            spr_active <= 1'b0;
        end
    end

endmodule
