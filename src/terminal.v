`timescale 1ns / 1ps

module terminal (
    input  wire        clk_pixel,   // HDMI pixel clock (74.25 MHz)
    input  wire        clk_sys,     // System clock (27 MHz)
    input  wire        rst_n,

    // Character write interface (from 6502 CPU or UART)
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        term_enable, // 1 = show terminal overlay, 0 = hide (full screen graphics)
    output wire        busy,        // High while clearing screen or scrolling line

    // Screen coordinates from HDMI (1280x720)
    input  wire [11:0] cx,
    input  wire [11:0] cy,

    // Output color
    output wire [23:0] term_rgb,
    output wire        term_active
);

    // Font ROM (1024 bytes: 128 chars * 8 bytes per char)
    reg [7:0] font_rom [0:1023];
    initial begin
        $readmemh("font8x8.hex", font_rom);
    end

    // Text buffer RAM (4096 bytes: 64 rows * 64 cols stride, or 45 rows * 80 cols)
    reg [7:0] text_ram [0:4095];

    parameter MARGIN_LEFT   = 4;
    parameter MARGIN_RIGHT  = 4;
    parameter MARGIN_TOP    = 2;
    parameter MARGIN_BOTTOM = 2;
    parameter MAX_X         = 79 - MARGIN_RIGHT;
    parameter MAX_Y         = 44 - MARGIN_BOTTOM;
    parameter NUM_ROWS      = MAX_Y - MARGIN_TOP + 1; // 41 visible rows

    reg [6:0] cursor_x = MARGIN_LEFT;
    reg [5:0] cursor_y = MARGIN_TOP;
    reg [5:0] scroll_offset = 0;

    // Hardware clear state machine (0 = idle, 1 = clearing full screen, 2 = clearing single row)
    reg [1:0]  clr_state = 1; // Clear on boot
    reg [11:0] clr_addr  = 0;
    reg [6:0]  row_clr_x = 0;
    reg [5:0]  row_clr_y = 0;

    assign busy = (clr_state != 0);

    // Map logical row (MARGIN_TOP..MAX_Y) to physical circular buffer row (MARGIN_TOP..MAX_Y)
    wire [6:0] phys_cursor_sum = cursor_y + scroll_offset;
    wire [5:0] phys_cursor_y   = (phys_cursor_sum > MAX_Y) ? (phys_cursor_sum - NUM_ROWS) : phys_cursor_sum[5:0];

    wire [11:0] cursor_write_addr = (phys_cursor_y << 6) + (phys_cursor_y << 4) + cursor_x;
    wire [11:0] row_clr_addr      = (row_clr_y << 6) + (row_clr_y << 4) + row_clr_x;

    reg        ram_we;
    reg [11:0] ram_waddr;
    reg [7:0]  ram_wdata;

    always @(posedge clk_sys) begin
        if (ram_we) begin
            text_ram[ram_waddr] <= ram_wdata;
        end
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            cursor_x      <= MARGIN_LEFT;
            cursor_y      <= MARGIN_TOP;
            scroll_offset <= 0;
            clr_state     <= 1;
            clr_addr      <= 0;
            ram_we        <= 0;
        end else begin
            ram_we <= 0;

            if (clr_state == 1) begin
                ram_we    <= 1;
                ram_waddr <= clr_addr;
                ram_wdata <= 8'h20;
                if (clr_addr == 12'd4095) begin
                    clr_state <= 0;
                end else begin
                    clr_addr <= clr_addr + 1'b1;
                end
            end else if (clr_state == 2) begin
                ram_we    <= 1;
                ram_waddr <= row_clr_addr;
                ram_wdata <= 8'h20;
                if (row_clr_x == 7'd79) begin
                    clr_state <= 0;
                end else begin
                    row_clr_x <= row_clr_x + 1'b1;
                end
            end else if (rx_valid) begin
                if (rx_data == 8'h0C) begin
                    // Form Feed (CLS): Clear entire screen
                    cursor_x      <= MARGIN_LEFT;
                    cursor_y      <= MARGIN_TOP;
                    scroll_offset <= 0;
                    clr_addr      <= 0;
                    clr_state     <= 1;
                end else if (rx_data == 8'h0D) begin
                    // Carriage Return
                    cursor_x <= MARGIN_LEFT;
                end else if (rx_data == 8'h0A) begin
                    // Line Feed (with hardware scroll at bottom)
                    cursor_x <= MARGIN_LEFT;
                    if (cursor_y >= MAX_Y) begin
                        if (scroll_offset + 1 >= NUM_ROWS)
                            scroll_offset <= 0;
                        else
                            scroll_offset <= scroll_offset + 1'b1;

                        // Clear the newly exposed bottom row
                        row_clr_y <= (phys_cursor_y == MAX_Y) ? MARGIN_TOP : (phys_cursor_y + 1'b1);
                        row_clr_x <= 0;
                        clr_state <= 2;
                    end else begin
                        cursor_y <= cursor_y + 1'b1;
                    end
                end else if (rx_data == 8'h08 || rx_data == 8'h7F) begin
                    // Backspace: move left and erase character
                    if (cursor_x > MARGIN_LEFT) begin
                        cursor_x  <= cursor_x - 1'b1;
                        ram_we    <= 1;
                        ram_waddr <= cursor_write_addr - 1'b1;
                        ram_wdata <= 8'h20;
                    end
                end else if (rx_data >= 8'h20 && rx_data < 8'h7F) begin
                    ram_we    <= 1;
                    ram_waddr <= cursor_write_addr;
                    ram_wdata <= rx_data;

                    if (cursor_x >= MAX_X) begin
                        cursor_x <= MARGIN_LEFT;
                        if (cursor_y >= MAX_Y) begin
                            if (scroll_offset + 1 >= NUM_ROWS)
                                scroll_offset <= 0;
                            else
                                scroll_offset <= scroll_offset + 1'b1;

                            row_clr_y <= (phys_cursor_y == MAX_Y) ? MARGIN_TOP : (phys_cursor_y + 1'b1);
                            row_clr_x <= 0;
                            clr_state <= 2;
                        end else begin
                            cursor_y <= cursor_y + 1'b1;
                        end
                    end else begin
                        cursor_x <= cursor_x + 1'b1;
                    end
                end
            end
        end
    end

    // Read logic for HDMI (clk_pixel)
    wire [6:0] char_x  = cx[10:4];
    wire [5:0] char_y  = cy[9:4];
    wire [2:0] pixel_x = cx[3:1];
    wire [2:0] pixel_y = cy[3:1];

    wire in_vert_bounds = (char_y >= MARGIN_TOP) && (char_y <= MAX_Y);
    wire [6:0] phys_read_sum = char_y + scroll_offset;
    wire [5:0] phys_read_y   = in_vert_bounds ? ((phys_read_sum > MAX_Y) ? (phys_read_sum - NUM_ROWS) : phys_read_sum[5:0]) : char_y;

    wire [11:0] read_addr = (phys_read_y << 6) + (phys_read_y << 4) + char_x;

    reg [7:0] current_char;
    reg [7:0] font_row;

    always @(posedge clk_pixel) begin
        current_char <= text_ram[read_addr];
        font_row     <= font_rom[{current_char[6:0], pixel_y}];
    end

    reg [6:0] char_x_d1, char_x_d2;
    reg [5:0] char_y_d1, char_y_d2;
    reg [2:0] pixel_x_d1, pixel_x_d2;
    always @(posedge clk_pixel) begin
        char_x_d1  <= char_x;
        char_x_d2  <= char_x_d1;
        char_y_d1  <= char_y;
        char_y_d2  <= char_y_d1;
        pixel_x_d1 <= pixel_x;
        pixel_x_d2 <= pixel_x_d1;
    end

    wire pixel_on  = font_row[pixel_x_d2];
    wire is_cursor = (char_x_d2 == cursor_x) && (char_y_d2 == cursor_y);

    assign term_active = term_enable && (pixel_on | is_cursor);
    assign term_rgb    = is_cursor ? 24'hFFFFFF : 24'h00FF80;

endmodule
