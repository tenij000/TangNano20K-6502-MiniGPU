`timescale 1ns / 1ps

module bg_layer (
    input  wire        clk_pixel, // 74.25 MHz
    input  wire        rst_n,

    // Coordinates from HDMI
    input  wire [10:0] cx,
    input  wire [9:0]  cy,
    
    // Background color output
    output wire [7:0]  bg_color,
    
    // Write interface (from GPU engine)
    input  wire        we_tileset,
    input  wire [13:0] addr_tileset, // 64 tiles * 256 bytes = 16384 bytes
    input  wire [7:0]  din_tileset,
    
    input  wire        we_tilemap,
    input  wire [11:0] addr_tilemap, // 64x64 tiles = 4096 bytes
    input  wire [7:0]  din_tilemap,
    
    input  wire [9:0]  scroll_x,
    input  wire [9:0]  scroll_y
);

    // BRAM for Tileset (16KB)
    reg [7:0] tileset_ram [0:16383];
    // BRAM for Tilemap (4KB)
    reg [7:0] tilemap_ram [0:4095];

    initial begin
        $readmemh("default_tileset.hex", tileset_ram);
        $readmemh("default_tilemap.hex", tilemap_ram);
    end

    // Write ports
    always @(posedge clk_pixel) begin
        if (we_tileset) tileset_ram[addr_tileset] <= din_tileset;
        if (we_tilemap) tilemap_ram[addr_tilemap] <= din_tilemap;
    end

    // Read pipeline
    // cx and cy change every clock. Look ahead 2 clocks to compensate for 2-cycle pipeline delay!
    wire [10:0] cx_ahead = cx + 2;
    wire [9:0] px = cx_ahead[10:1];
    wire [8:0] py = cy[9:1];
    
    // Step 1: calculate absolute coordinates (wrapping)
    wire [9:0] abs_x = px + scroll_x;
    wire [9:0] abs_y = py + scroll_y;

    // Step 2: calculate tile coordinates
    wire [5:0] tile_x = abs_x[9:4];
    wire [5:0] tile_y = abs_y[9:4];
    
    // Step 3: Fetch Tile ID
    reg [3:0] fetch_pixel_x;
    reg [3:0] fetch_pixel_y;
    reg [7:0] tile_id;
    
    always @(posedge clk_pixel) begin
        tile_id <= tilemap_ram[{tile_y, tile_x}];
        fetch_pixel_x <= abs_x[3:0];
        fetch_pixel_y <= abs_y[3:0];
    end
    
    // Step 4: Fetch Color
    reg [7:0] color_out;
    always @(posedge clk_pixel) begin
        color_out <= tileset_ram[{tile_id[5:0], fetch_pixel_y, fetch_pixel_x}];
    end
    
    assign bg_color = color_out;

endmodule
