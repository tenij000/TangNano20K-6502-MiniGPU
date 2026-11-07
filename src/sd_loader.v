`timescale 1ns / 1ps

module sd_loader (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_load, // 1 cycle pulse to start/restart
    
    // SD Card SPI
    output wire        spi_cs,
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    
    // Memory Interface
    output reg         mem_req,
    input  wire        mem_ack,
    output reg [20:0]  mem_addr,
    output reg [31:0]  mem_data,
    output reg [3:0]   mem_wstrb,
    
    // Status
    output wire [3:0]  card_stat,
    output wire [2:0]  fs_stat,
    output wire        file_found,
    output wire        done
);

    wire outen;
    wire [7:0] outbyte;
    
    // Instance of the open source module
    sd_spi_file_reader #(
        .FILE_NAME_LEN(9),
        .FILE_NAME("image.bin"),
        .SPI_CLK_DIV(94) // 74.25MHz / (2*94) = ~395 kHz SPI clock (safe for SD init)
    ) reader_inst (
        .rstn(rst_n),
        .clk(clk),
        .spi_ssn(spi_cs),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .card_type(),
        .card_stat(card_stat),
        .filesystem_type(),
        .filesystem_stat(fs_stat),
        .file_found(file_found),
        .outen(outen),
        .outbyte(outbyte)
    );

    // Packer State Machine
    reg [1:0] byte_cnt = 0;
    reg [23:0] shift_reg = 0;
    reg [17:0] pixel_cnt = 0; // 640*360 = 230400 pixels
    
    assign done = (pixel_cnt >= 230400);

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_req <= 0;
            mem_addr <= 0;
            byte_cnt <= 0;
            pixel_cnt <= 0;
        end else begin
            if (start_load) begin
                mem_req <= 0;
                mem_addr <= 0; // Start at front buffer
                byte_cnt <= 0;
                pixel_cnt <= 0;
            end else begin
                if (mem_ack) begin
                    mem_req <= 0;
                    mem_addr <= mem_addr + 1;
                end
                
                if (outen && !done) begin
                    pixel_cnt <= pixel_cnt + 1;
                    
                    if (byte_cnt == 0) begin shift_reg[7:0] <= outbyte; byte_cnt <= 1; end
                    else if (byte_cnt == 1) begin shift_reg[15:8] <= outbyte; byte_cnt <= 2; end
                    else if (byte_cnt == 2) begin shift_reg[23:16] <= outbyte; byte_cnt <= 3; end
                    else if (byte_cnt == 3) begin
                        mem_data <= {outbyte, shift_reg[23:0]};
                        mem_wstrb <= 4'b1111;
                        mem_req <= 1;
                        byte_cnt <= 0;
                    end
                end
            end
        end
    end
endmodule
