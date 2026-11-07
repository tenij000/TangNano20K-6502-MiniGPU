`timescale 1ns / 1ps

module top(
    input  wire       sys_clk,    // 27 MHz built-in clock
    input  wire       s1,         // Button S1
    output wire [2:0] tmds_d_p,   // HDMI Data
    output wire [2:0] tmds_d_n,
    output wire       tmds_clk_p, // HDMI Clock
    output wire       tmds_clk_n,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    input  wire       ps2_data,   // Pin 73 (PS/2 Data)
    input  wire       ps2_clk,    // Pin 74 (PS/2 Clock)
    output wire       sd_clk,     // Pin 83 (MicroSD CLK)
    output wire       sd_mosi,    // Pin 82 (MicroSD CMD/MOSI)
    input  wire       sd_miso,    // Pin 84 (MicroSD DAT0/MISO)
    output wire       sd_cs,      // Pin 81 (MicroSD DAT3/CS)
    output wire       sd_dat1,    // Pin 85 (MicroSD DAT1)
    output wire       sd_dat2,    // Pin 80 (MicroSD DAT2)
    output wire       w5500_cs,   // Pin 27 (W5500 SCSn)
    output wire       w5500_sclk, // Pin 28 (W5500 SCLK)
    output wire       w5500_mosi, // Pin 25 (W5500 MOSI)
    input  wire       w5500_miso, // Pin 26 (W5500 MISO)
    output wire       w5500_rst,  // Pin 29 (W5500 RSTn)
    output wire [1:0] led,

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
    output wire [3:0]  O_sdram_dqm
);

    // --- Clock Generation ---
    wire hclk5;  // 371.25 MHz (720p 5x pixel clock)
    wire hclk;   // 74.25 MHz  (720p pixel clock)
    wire pll_lock;

    gowin_pll_hdmi pll_hdmi (
        .clkin(sys_clk),
        .clkout(hclk5),
        .lock(pll_lock)
    );

    // Proper reset sequence for SDRAM (wait for PLL lock)
    reg [15:0] reset_timer = 0;
    reg rst_n = 0;
    always @(posedge hclk) begin
        if (!pll_lock) begin
            reset_timer <= 0;
            rst_n <= 0;
        end else if (reset_timer != 16'hFFFF) begin
            reset_timer <= reset_timer + 1;
            rst_n <= 0;
        end else begin
            rst_n <= 1;
        end
    end

    wire reset = ~rst_n;

    CLKDIV #(.DIV_MODE(5)) div5 (
        .CLKOUT(hclk),
        .HCLKIN(hclk5),
        .RESETN(1'b1),
        .CALIB(1'b0)
    );

    // --- UART Receiver & Transmitter (115200 baud) ---
    wire [7:0] uart_data;
    wire       uart_valid;

    uart_rx #(
        .CLK_FREQ(27_000_000),
        .BAUD_RATE(115200)
    ) uart_inst (
        .clk(sys_clk),
        .reset(reset),
        .rx(UART_RXD),
        .data(uart_data),
        .valid(uart_valid)
    );

    reg [7:0] term_rx_data_cpu  = 0;
    reg       term_rx_valid_cpu = 0;

    uart_tx_fifo #(
        .CLK_FREQ(27_000_000),
        .BAUD_RATE(115200)
    ) uart_tx_inst (
        .clk(sys_clk),
        .reset(reset),
        .tx_start(term_rx_valid_cpu),
        .tx_data(term_rx_data_cpu),
        .tx(UART_TXD)
    );

    // --- PS/2 Keyboard, Live Multi-Key Arcade Joypad ($A004) & Alt+Arrow Hardware Mouse ($A00C-$A00F) ---
    wire [7:0] ps2_ascii_code;
    wire       ps2_ascii_valid;
    wire [7:0] ps2_joypad;
    wire [7:0] ps2_mouse;
    reg  [7:0] pc_joypad         = 8'h00; // Live multi-key state from PC terminal (0x80 | bits)
    reg  [7:0] uart_joypad       = 8'h00; // Fallback pulse for plain serial terminals
    reg  [3:0] uart_joy_timer    = 4'd0;
    reg        ps2_fire_prev     = 1'b0;
    reg        fire_latch        = 1'b0;  // Hardware edge-latch so brief Spacebar taps are never missed
    reg        ps2_led_toggle    = 1'b1;

    reg  [9:0] mouse_x           = 10'd320;
    reg  [8:0] mouse_y           = 9'd180;
    reg        mouse_en          = 1'b1;
    reg  [4:0] mouse_accel       = 5'd0;
    reg  [4:0] pc_mouse          = 5'd0;
    reg  [3:0] pc_mouse_timer    = 4'd0;
    reg        mouse_btn_prev    = 1'b0;
    reg        mouse_click_latch = 1'b0;

    wire        mouse_up   = ps2_mouse[0] | pc_mouse[0];
    wire        mouse_dn   = ps2_mouse[1] | pc_mouse[1];
    wire        mouse_lt   = ps2_mouse[2] | pc_mouse[2];
    wire        mouse_rt   = ps2_mouse[3] | pc_mouse[3];
    wire        mouse_lmb  = ps2_mouse[4] | pc_mouse[4];
    wire        mouse_rmb  = ps2_mouse[5];
    wire [9:0]  mouse_step = (ps2_mouse[6] || (mouse_accel >= 5'd14)) ? 10'd4 : 10'd2;

    wire signed [7:0]  usb_mouse_dx;
    wire signed [7:0]  usb_mouse_dy;
    wire               usb_mouse_valid;
    wire signed [11:0] next_usb_mx = $signed({2'b00, mouse_x}) + $signed({{4{usb_mouse_dx[7]}}, usb_mouse_dx});
    wire signed [11:0] next_usb_my = $signed({3'b000, mouse_y}) + $signed({{4{usb_mouse_dy[7]}}, usb_mouse_dy});

    ps2_keyboard ps2_inst (
        .clk(sys_clk),
        .reset(reset),
        .ps2_clk(ps2_clk),
        .ps2_data(ps2_data),
        .ascii_code(ps2_ascii_code),
        .ascii_valid(ps2_ascii_valid),
        .joypad_state(ps2_joypad),
        .mouse_state(ps2_mouse),
        .usb_mouse_dx(usb_mouse_dx),
        .usb_mouse_dy(usb_mouse_dy),
        .usb_mouse_valid(usb_mouse_valid)
    );

    // --- UART Router (Mode Switch for backward compatibility with PC scripts) ---
    // 0 = Standalone MiniGPU-BASIC, 1 = Raw Framebuffer, 2 = External PC GPU stream
    reg [1:0]  uart_mode = 0;
    reg [31:0] magic_seq = 0;
    always @(posedge sys_clk) begin
        if (reset) begin
            uart_mode <= 0;
            magic_seq <= 0;
        end else if (uart_valid) begin
            magic_seq <= {magic_seq[23:0], uart_data};
            if ({magic_seq[23:0], uart_data} == 32'h1B494D47) uart_mode <= 1; // ESC I M G
            if ({magic_seq[23:0], uart_data} == 32'h1B545854) uart_mode <= 0; // ESC T X T
            if ({magic_seq[23:0], uart_data} == 32'h1B475055) uart_mode <= 2; // ESC G P U
        end
    end

    // --- 6502 CPU & Memory (12 KB Fast BSRAM + 8 KB MiniGPU-BASIC ROM) ---
    wire [15:0] cpu_ab;
    wire [7:0]  cpu_do;
    reg  [7:0]  cpu_di;
    wire        cpu_we;

    // 8 KB Lower RAM ($0000 - $1FFF: 4 BSRAMs) + 4 KB Upper RAM ($2000 - $2FFF: 2 BSRAMs)
    // Split into power-of-2 arrays so Gowin synthesizes exact 4 + 2 = 6 BSRAMs (instead of rounding 12KB up to 16KB / 8 BSRAMs!)
    reg [7:0] cpu_ram_lo [0:8191];
    reg [7:0] cpu_ram_hi [0:4095];
    reg [7:0] cpu_rom    [0:8191];

    initial begin
        $readmemh("minigpu_basic.hex", cpu_rom);
    end

    // --- MicroSD SPI Master ($A010 = Data, $A011 = Control) ---
    reg [1:0]  sd_ctrl = 2'b11; // Bit 0 = CS (1=inactive), Bit 1 = Slow Clock (1=210kHz)
    assign sd_cs   = sd_ctrl[0];
    assign sd_dat1 = 1'b1;
    assign sd_dat2 = 1'b1;

    wire       sd_start = cpu_rdy && cpu_we && (cpu_ab == 16'hA010);
    wire [7:0] sd_rx_data;
    wire       sd_busy;

    sd_spi sd_spi_inst (
        .clk(sys_clk),
        .reset(reset),
        .start(sd_start),
        .tx_data(cpu_do),
        .slow_mode(sd_ctrl[1]),
        .rx_data(sd_rx_data),
        .busy(sd_busy),
        .sd_clk(sd_clk),
        .sd_mosi(sd_mosi),
        .sd_miso(sd_miso)
    );

    // --- W5500 Hardwired TCP/IP SPI Master ($A030 = Data, $A031 = Control) ---
    reg [1:0]  w5500_ctrl  = 2'b11; // Bit 0 = CS (1=inactive), Bit 1 = RSTn (1=normal)
    assign w5500_cs        = w5500_ctrl[0];
    assign w5500_rst       = w5500_ctrl[1];

    wire       w5500_start = cpu_rdy && cpu_we && (cpu_ab == 16'hA030);
    wire [7:0] w5500_rx_data;
    wire       w5500_busy;

    sd_spi w5500_spi_inst (
        .clk(sys_clk),
        .reset(reset),
        .start(w5500_start),
        .tx_data(cpu_do),
        .slow_mode(1'b0),
        .rx_data(w5500_rx_data),
        .busy(w5500_busy),
        .sd_clk(w5500_sclk),
        .sd_mosi(w5500_mosi),
        .sd_miso(w5500_miso)
    );

    // --- 4 MB Internal SDRAM-Disk ($A012 - $A015) ---
    reg [7:0]  rd_addr_lo    = 8'h00;
    reg [7:0]  rd_addr_hi    = 8'h00;
    reg [5:0]  rd_addr_bank  = 6'h00;
    wire [7:0] rd_dout;
    reg        rd_req_toggle = 1'b0;
    reg        rd_req_we     = 1'b0;
    reg [21:0] rd_req_addr   = 22'd0;
    reg [7:0]  rd_req_wdata  = 8'h00;
    wire       rd_ack_toggle;
    reg [2:0]  rd_ack_sync   = 3'b000;
    wire       rd_busy       = (rd_req_toggle != rd_ack_sync[2]);

    // --- 6502 -> DONDERDAG MiniGPU Command Port ($A020) ---
    reg        cpu_gpu_req_toggle    = 1'b0;
    reg [7:0]  cpu_gpu_data          = 8'h00;
    wire       cpu_gpu_ack_toggle;
    reg [2:0]  cpu_gpu_ack_sync      = 3'b000;
    wire       cpu_gpu_busy          = (cpu_gpu_req_toggle != cpu_gpu_ack_sync[2]);

    // --- Automatic BASIC Planets / Farm Landscape Background Restore ---
    reg        cpu_gfx_mode          = 1'b0; // 0 = MODE 0 (BASIC), 1 = MODE 1 (Full-screen App/Game)
    reg        bg_theme              = 1'b1; // 0 = Space Planets, 1 = Boerderij Landschap
    reg [2:0]  s1_sync               = 3'b000;
    reg [19:0] s1_debounce           = 20'd0;
    reg        restore_bg_req_toggle = 1'b0;
    wire       restore_bg_ack_toggle;
    reg [2:0]  restore_bg_ack_sync   = 3'b000;
    wire       restore_bg_busy       = (restore_bg_req_toggle != restore_bg_ack_sync[2]);

    // --- Hardware Delay Timer ($A002: 1 unit = 10 ms) ---
    reg [23:0] delay_counter = 0;
    reg        delay_active  = 0;

    always @(posedge sys_clk) begin
        if (reset) begin
            delay_active <= 0;
        end else if (cpu_rdy && cpu_we && cpu_ab == 16'hA002) begin
            delay_counter <= cpu_do * 24'd270_000;
            delay_active  <= (cpu_do != 0);
        end else if (delay_active) begin
            if (delay_counter > 0)
                delay_counter <= delay_counter - 1;
            else
                delay_active <= 0;
        end
    end

    // --- Hardware 8-Bit PCM / WAV Sample DAC ($A016 = Sample, $A017 = Sample Rate Timer)
    //     + Autonomous SDRAM Audio Co-Processor / Hulp-CPU ($A018=Bank, $A019=PagesLo, $A01A=PagesHi, $A01B=Ctrl) ---
    reg [7:0]  pcm_dac_reg      = 8'h80;
    reg [7:0]  pcm_pending_reg  = 8'h80;
    reg        pcm_wait_active  = 1'b0;
    reg [2:0]  pcm_rate_reg     = 3'd0;
    reg [11:0] pcm_timer        = 12'd0;
    reg [21:0] pcm_idle_cnt     = 22'd0;

    reg [5:0]  adma_start_bank  = 6'd62;
    reg [15:0] adma_total_pages = 16'd128;
    reg [15:0] adma_rem_pages   = 16'd0;
    reg [21:0] adma_cur_addr    = 22'd0;
    reg [2:0]  adma_rate        = 3'd0;
    reg        adma_loop        = 1'b0;
    reg        adma_active      = 1'b0;
    reg        adma_need_byte   = 1'b0;
    reg        adma_fetching    = 1'b0;
    reg [11:0] adma_timer       = 12'd0;
    reg        a012_reading     = 1'b0;
    reg [7:0]  a014_latch       = 8'h00;

    wire [2:0] eff_pcm_rate = adma_active ? adma_rate : pcm_rate_reg;
    reg [11:0] pcm_period;
    always @(*) begin
        case (eff_pcm_rate)
            3'd1:    pcm_period = 12'd3374; //  8,000 Hz
            3'd2:    pcm_period = 12'd2448; // 11,025 Hz
            3'd3:    pcm_period = 12'd1686; // 16,000 Hz
            3'd4:    pcm_period = 12'd1223; // 22,050 Hz
            3'd5:    pcm_period = 12'd2249; // 12,000 Hz
            3'd6:    pcm_period = 12'd1124; // 24,000 Hz
            3'd7:    pcm_period = 12'd843;  // 32,000 Hz
            default: pcm_period = 12'd0;    // Immediate (no wait)
        endcase
    end

    wire pcm_wait = pcm_wait_active;

    wire term_busy;
    // Direct Memory-Mapped SDRAM ($3000-$9FFF = 28KB in Bank 63, $B000-$DFFF = 12KB Banked Window)
    wire is_sdram_mem     = (cpu_ab >= 16'h3000 && cpu_ab < 16'hA000) ||
                            (cpu_ab >= 16'hB000 && cpu_ab < 16'hE000);
    reg  sdram_data_phase = 1'b0;
    wire adma_steal_cycle = adma_active && adma_need_byte && !adma_fetching && !rd_busy && !sdram_data_phase &&
                            !a012_reading;
    wire cpu_rdy          = !delay_active && !pcm_wait && !cpu_gpu_busy && !restore_bg_busy && !sd_busy &&
                            !w5500_busy && !term_busy && !term_rx_valid_cpu && !rd_busy &&
                            !adma_steal_cycle && !adma_fetching;

    // --- 100 Hz Hardware System Timer ($A003), LFSR ($A005) & Hardware RTC ($A007-$A009) ---
    reg [18:0] sys_timer_cnt = 0;
    reg [7:0]  timer_ticks   = 0;
    reg [15:0] lfsr          = 16'hACE1;

    reg [24:0] rtc_div       = 25'd0;
    reg [4:0]  rtc_hour      = 5'd12;
    reg [5:0]  rtc_min       = 6'd0;
    reg [5:0]  rtc_sec       = 6'd0;
    reg [1:0]  rtc_rx_state  = 2'd0;
    reg [24:0] rtc_hud_data  = 25'h1_12_00_00;

    function [7:0] to_bcd6(input [5:0] v);
        reg [5:0] rem;
        begin
            if      (v >= 6'd50) begin rem = v - 6'd50; to_bcd6 = {4'd5, rem[3:0]}; end
            else if (v >= 6'd40) begin rem = v - 6'd40; to_bcd6 = {4'd4, rem[3:0]}; end
            else if (v >= 6'd30) begin rem = v - 6'd30; to_bcd6 = {4'd3, rem[3:0]}; end
            else if (v >= 6'd20) begin rem = v - 6'd20; to_bcd6 = {4'd2, rem[3:0]}; end
            else if (v >= 6'd10) begin rem = v - 6'd10; to_bcd6 = {4'd1, rem[3:0]}; end
            else                 begin                  to_bcd6 = {4'd0, v[3:0]};   end
        end
    endfunction

    always @(posedge sys_clk) begin
        rtc_hud_data <= {(rtc_div < 25'd13_500_000), to_bcd6({1'b0, rtc_hour}), to_bcd6(rtc_min), to_bcd6(rtc_sec)};
        if (reset) begin
            sys_timer_cnt <= 0;
            timer_ticks   <= 0;
            lfsr          <= 16'hACE1;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            if (sys_timer_cnt == 19'd269_999) begin
                sys_timer_cnt <= 0;
                timer_ticks   <= timer_ticks + 8'd1;
            end else begin
                sys_timer_cnt <= sys_timer_cnt + 19'd1;
            end
        end
    end

    // --- Keyboard Input & I/O Registers ---
    reg [7:0] kbd_data       = 0;
    reg       kbd_ready      = 0;
    reg       term_enable    = 1'b1;
    reg [7:0] synth_inst_reg = 8'h08; // $A00A: 0..7 = Instrument, 8 = Default Studio Mix
    reg       synth_inst_we  = 1'b0;
    reg [7:0] synth_fx_reg   = 8'h07; // $A00B: Bit0=Auto-ADSR, Bit1=LPF, Bit2=Stereo, Bit3=Vibrato

    always @(posedge sys_clk) begin
        rd_ack_sync         <= {rd_ack_sync[1:0], rd_ack_toggle};
        cpu_gpu_ack_sync    <= {cpu_gpu_ack_sync[1:0], cpu_gpu_ack_toggle};
        restore_bg_ack_sync <= {restore_bg_ack_sync[1:0], restore_bg_ack_toggle};

        if (reset) begin
            kbd_ready             <= 0;
            kbd_data              <= 0;
            term_rx_valid_cpu     <= 0;
            term_enable           <= 1'b1;
            cpu_gfx_mode          <= 1'b0;
            restore_bg_req_toggle <= 1'b0;
            sd_ctrl               <= 2'b11;
            w5500_ctrl         <= 2'b11;
            rd_addr_lo         <= 8'h00;
            rd_addr_hi         <= 8'h00;
            rd_addr_bank       <= 6'h00;
            rd_req_toggle      <= 1'b0;
            cpu_gpu_req_toggle <= 1'b0;
            pc_joypad          <= 8'h00;
            uart_joypad        <= 8'h00;
            uart_joy_timer     <= 4'd0;
            ps2_fire_prev      <= 1'b0;
            fire_latch         <= 1'b0;
            mouse_x            <= 10'd320;
            mouse_y            <= 9'd180;
            mouse_en           <= 1'b1;
            mouse_accel        <= 5'd0;
            pc_mouse           <= 5'd0;
            pc_mouse_timer     <= 4'd0;
            mouse_btn_prev     <= 1'b0;
            mouse_click_latch  <= 1'b0;
            sdram_data_phase   <= 1'b0;
            pcm_dac_reg        <= 8'h80;
            pcm_pending_reg    <= 8'h80;
            pcm_wait_active    <= 1'b0;
            pcm_rate_reg       <= 3'd0;
            pcm_timer          <= 12'd0;
            pcm_idle_cnt       <= 22'd0;
            adma_start_bank    <= 6'd62;
            adma_total_pages   <= 16'd128;
            adma_rem_pages     <= 16'd0;
            adma_cur_addr      <= 22'd0;
            adma_rate          <= 3'd0;
            adma_loop          <= 1'b0;
            adma_active        <= 1'b0;
            adma_need_byte     <= 1'b0;
            adma_fetching      <= 1'b0;
            adma_timer         <= 12'd0;
            a012_reading       <= 1'b0;
            a014_latch         <= 8'h00;
        end else begin
            if (a012_reading && !rd_busy) begin
                a014_latch   <= rd_dout;
                a012_reading <= 1'b0;
            end
            if (adma_active) begin
                if (adma_timer > 12'd1) begin
                    adma_timer <= adma_timer - 12'd1;
                end else begin
                    adma_timer     <= pcm_period;
                    adma_need_byte <= 1'b1;
                end
            end
            if (adma_steal_cycle) begin
                adma_need_byte <= 1'b0;
                adma_fetching  <= 1'b1;
                rd_req_addr    <= adma_cur_addr;
                rd_req_we      <= 1'b0;
                rd_req_toggle  <= ~rd_req_toggle;
            end else if (adma_fetching && !rd_busy) begin
                adma_fetching  <= 1'b0;
                pcm_dac_reg    <= rd_dout;
                pcm_idle_cnt   <= 22'd4_000_000;
                adma_cur_addr  <= adma_cur_addr + 22'd1;
                if (adma_cur_addr[7:0] == 8'hFF) begin
                    if (adma_rem_pages <= 16'd1) begin
                        if (adma_loop) begin
                            adma_cur_addr  <= {adma_start_bank, 16'h0000};
                            adma_rem_pages <= (adma_total_pages == 16'd0) ? 16'd128 : adma_total_pages;
                        end else begin
                            adma_active    <= 1'b0;
                            adma_rem_pages <= 16'd0;
                        end
                    end else begin
                        adma_rem_pages <= adma_rem_pages - 16'd1;
                    end
                end
            end
            if (pcm_timer != 12'd0) begin
                if (pcm_timer == 12'd1 && pcm_wait_active) begin
                    pcm_dac_reg     <= pcm_pending_reg;
                    pcm_timer       <= pcm_period;
                    pcm_wait_active <= 1'b0;
                end else begin
                    pcm_timer <= pcm_timer - 12'd1;
                end
            end else if (pcm_wait_active) begin
                pcm_dac_reg     <= pcm_pending_reg;
                pcm_timer       <= pcm_period;
                pcm_wait_active <= 1'b0;
            end
            if (pcm_idle_cnt != 22'd0) begin
                pcm_idle_cnt <= pcm_idle_cnt - 22'd1;
            end else begin
                pcm_dac_reg <= 8'h80;
            end
            if (cpu_rdy) begin
                sdram_data_phase <= is_sdram_mem && !cpu_we;
                if (is_sdram_mem) begin
                    rd_req_addr   <= (cpu_ab < 16'hA000) ? {6'd63, cpu_ab} : {rd_addr_bank, cpu_ab};
                    rd_req_we     <= cpu_we;
                    rd_req_wdata  <= cpu_do;
                    rd_req_toggle <= ~rd_req_toggle;
                end
            end

            ps2_fire_prev <= ps2_joypad[4] | pc_joypad[4];
            if ((ps2_joypad[4] | pc_joypad[4]) && !ps2_fire_prev) begin
                fire_latch <= 1'b1;
            end else if (cpu_rdy && !cpu_we && cpu_ab == 16'hA004) begin
                fire_latch <= 1'b0;
            end

            mouse_btn_prev <= mouse_lmb;
            if (mouse_lmb && !mouse_btn_prev) begin
                mouse_click_latch <= 1'b1;
                mouse_en          <= 1'b1;
            end else if (cpu_rdy && !cpu_we && cpu_ab == 16'hA00F) begin
                mouse_click_latch <= 1'b0;
            end

            if (usb_mouse_valid) begin
                mouse_en       <= 1'b1;
                ps2_led_toggle <= ~ps2_led_toggle;
                if (next_usb_mx < 12'sd0)        mouse_x <= 10'd0;
                else if (next_usb_mx > 12'sd639) mouse_x <= 10'd639;
                else                             mouse_x <= next_usb_mx[9:0];

                if (next_usb_my < 12'sd0)        mouse_y <= 9'd0;
                else if (next_usb_my > 12'sd359) mouse_y <= 9'd359;
                else                             mouse_y <= next_usb_my[8:0];
            end else if (sys_timer_cnt == 19'd269_999) begin
                if (uart_joy_timer != 4'd0)
                    uart_joy_timer <= uart_joy_timer - 4'd1;
                else
                    uart_joypad <= 8'h00;

                if (pc_mouse_timer != 4'd0)
                    pc_mouse_timer <= pc_mouse_timer - 4'd1;
                else
                    pc_mouse <= 5'd0;

                if (mouse_up | mouse_dn | mouse_lt | mouse_rt) begin
                    mouse_en <= 1'b1;
                    if (mouse_accel != 5'd31) mouse_accel <= mouse_accel + 5'd1;
                    if (mouse_up) mouse_y <= (mouse_y >= mouse_step[8:0]) ? (mouse_y - mouse_step[8:0]) : 9'd0;
                    if (mouse_dn) mouse_y <= (mouse_y + mouse_step[8:0] < 9'd360) ? (mouse_y + mouse_step[8:0]) : 9'd359;
                    if (mouse_lt) mouse_x <= (mouse_x >= mouse_step) ? (mouse_x - mouse_step) : 10'd0;
                    if (mouse_rt) mouse_x <= (mouse_x + mouse_step < 10'd640) ? (mouse_x + mouse_step) : 10'd639;
                end else begin
                    mouse_accel <= 5'd0;
                end
            end

            // RAM write ($0000 - $2FFF)
            if (cpu_rdy && cpu_we && cpu_ab < 16'h2000) begin
                cpu_ram_lo[cpu_ab[12:0]] <= cpu_do;
            end
            if (cpu_rdy && cpu_we && cpu_ab >= 16'h2000 && cpu_ab < 16'h3000) begin
                cpu_ram_hi[cpu_ab[11:0]] <= cpu_do;
            end

            // Terminal / UART output ($A001)
            term_rx_valid_cpu <= 0;
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA001) begin
                term_rx_data_cpu  <= cpu_do;
                term_rx_valid_cpu <= 1;
                if ((cpu_do == 8'h0C) && !cpu_gfx_mode) begin
                    restore_bg_req_toggle <= ~restore_bg_req_toggle;
                end
            end

            // Terminal overlay visibility & Hardware Background Theme ($A006)
            //   0 = MODE 1 (full gfx tilemap), 1 = MODE 0 (text + current theme),
            //   2 = Full-screen 720p Hardware Panorama (hide text overlay),
            //   3 = Boerderij Thema, 5 = Space Thema, 6 = Toggle Thema
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA006) begin
                if (cpu_do == 8'h06) begin
                    bg_theme <= ~bg_theme;
                end else if (cpu_do == 8'h02) begin
                    term_enable  <= 1'b0;
                    cpu_gfx_mode <= 1'b0;
                    restore_bg_req_toggle <= ~restore_bg_req_toggle;
                end else begin
                    term_enable  <= cpu_do[0];
                    cpu_gfx_mode <= ~cpu_do[0];
                    if (cpu_do == 8'h03) bg_theme <= 1'b1;
                    if (cpu_do == 8'h05) bg_theme <= 1'b0;
                    if (cpu_do[0] && cpu_gfx_mode) begin
                        restore_bg_req_toggle <= ~restore_bg_req_toggle;
                    end
                end
            end

            // Physical S1 button on Tang Nano 20K toggles Space <-> Boerderij in MODE 0
            s1_sync <= {s1_sync[1:0], s1};
            if (s1_debounce != 20'd0) begin
                s1_debounce <= s1_debounce - 20'd1;
            end else if (s1_sync[1] && !s1_sync[2] && !cpu_gfx_mode) begin
                bg_theme    <= ~bg_theme;
                s1_debounce <= 20'hFFFFF;
            end

            // MicroSD & 4 MB SDRAM-Disk registers ($A011 - $A015)
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA011) begin
                sd_ctrl <= cpu_do[1:0];
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA012) begin
                rd_addr_lo    <= cpu_do;
                rd_req_addr   <= {rd_addr_bank, rd_addr_hi, cpu_do};
                rd_req_we     <= 1'b0; // Trigger SDRAM Read Prefetch into rd_dout
                rd_req_toggle <= ~rd_req_toggle;
                a012_reading  <= 1'b1;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA013) begin
                rd_addr_hi <= cpu_do;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA014) begin
                rd_req_addr   <= {rd_addr_bank, rd_addr_hi, rd_addr_lo};
                rd_req_wdata  <= cpu_do;
                rd_req_we     <= 1'b1; // Trigger SDRAM Write
                rd_req_toggle <= ~rd_req_toggle;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA015) begin
                rd_addr_bank <= cpu_do[5:0];
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA016) begin
                adma_active    <= 1'b0;
                adma_need_byte <= 1'b0;
                pcm_idle_cnt   <= 22'd4_000_000;
                if (pcm_rate_reg == 3'd0 || pcm_timer == 12'd0) begin
                    pcm_dac_reg     <= cpu_do;
                    pcm_timer       <= pcm_period;
                    pcm_wait_active <= 1'b0;
                end else begin
                    pcm_pending_reg <= cpu_do;
                    pcm_wait_active <= 1'b1;
                end
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA017) begin
                adma_active     <= 1'b0;
                adma_need_byte  <= 1'b0;
                pcm_rate_reg    <= cpu_do[2:0];
                pcm_timer       <= 12'd0;
                pcm_wait_active <= 1'b0;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA018) begin
                adma_start_bank <= cpu_do[5:0];
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA019) begin
                adma_total_pages[7:0] <= cpu_do;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA01A) begin
                adma_total_pages[15:8] <= cpu_do;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA01B) begin
                if (cpu_do[2:0] == 3'd0) begin
                    adma_active    <= 1'b0;
                    adma_need_byte <= 1'b0;
                    pcm_dac_reg    <= 8'h80;
                end else begin
                    adma_rate      <= cpu_do[2:0];
                    adma_loop      <= cpu_do[7];
                    adma_cur_addr  <= {adma_start_bank, 16'h0000};
                    adma_rem_pages <= (adma_total_pages == 16'd0) ? 16'd128 : adma_total_pages;
                    adma_timer     <= 12'd1;
                    adma_need_byte <= 1'b0;
                    adma_active    <= 1'b1;
                end
            end

            // DONDERDAG MiniGPU Command Stream byte ($A020)
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA020) begin
                cpu_gpu_data       <= cpu_do;
                cpu_gpu_req_toggle <= ~cpu_gpu_req_toggle;
            end

            // W5500 Ethernet SPI Control ($A031: Bit 0 = CS, Bit 1 = RSTn)
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA031) begin
                w5500_ctrl <= cpu_do[1:0];
            end

            // 16-Bit Stereo Sound Card Instrument ($A00A) & FX/ADSR Control ($A00B)
            synth_inst_we <= 1'b0;
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA00A) begin
                synth_inst_reg <= cpu_do;
                synth_inst_we  <= 1'b1;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA00B) begin
                synth_fx_reg <= cpu_do;
            end

            // Hardware Sprite Mouse Pointer Position & Control ($A00C - $A00F)
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA00C) begin
                mouse_x[7:0] <= cpu_do;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA00D) begin
                mouse_x[9:8] <= cpu_do[1:0];
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA00E) begin
                mouse_y[7:0] <= cpu_do;
            end
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA00F) begin
                if (cpu_do[7]) begin
                    mouse_en <= cpu_do[6];
                end else begin
                    mouse_y[8] <= cpu_do[0];
                    mouse_en   <= 1'b1;
                end
            end

            // Reading $A001 clears kbd_ready
            if (cpu_rdy && !cpu_we && cpu_ab == 16'hA001) begin
                kbd_ready <= 0;
            end

            // Hardware Real-Time Clock 1 Hz tick (27,000,000 cycles @ 27 MHz) + CPU write ($A007-$A009)
            if (cpu_rdy && cpu_we && cpu_ab == 16'hA007) begin
                rtc_hour <= (cpu_do < 8'd24) ? cpu_do[4:0] : 5'd0;
            end else if (cpu_rdy && cpu_we && cpu_ab == 16'hA008) begin
                rtc_min  <= (cpu_do < 8'd60) ? cpu_do[5:0] : 6'd0;
            end else if (cpu_rdy && cpu_we && cpu_ab == 16'hA009) begin
                rtc_sec  <= (cpu_do < 8'd60) ? cpu_do[5:0] : 6'd0;
                rtc_div  <= 25'd0;
            end else if (rtc_div == 25'd26_999_999) begin
                rtc_div <= 25'd0;
                if (rtc_sec == 6'd59) begin
                    rtc_sec <= 6'd0;
                    if (rtc_min == 6'd59) begin
                        rtc_min  <= 6'd0;
                        rtc_hour <= (rtc_hour == 5'd23) ? 5'd0 : (rtc_hour + 5'd1);
                    end else begin
                        rtc_min <= rtc_min + 6'd1;
                    end
                end else begin
                    rtc_sec <= rtc_sec + 6'd1;
                end
            end else begin
                rtc_div <= rtc_div + 25'd1;
            end

            // Live Multi-Key Joypad packet (0x80..0xBF), Theme Control (0xF0..0xF3), or RTC Sync (0xF4 + 3 bytes)
            if (uart_valid && (uart_mode == 0) && uart_data[7]) begin
                if (uart_data == 8'hF4) begin
                    rtc_rx_state <= 2'd1;
                end else if (rtc_rx_state == 2'd1) begin
                    rtc_hour     <= (uart_data[5:0] < 6'd24) ? uart_data[4:0] : 5'd0;
                    rtc_rx_state <= 2'd2;
                end else if (rtc_rx_state == 2'd2) begin
                    rtc_min      <= (uart_data[5:0] < 6'd60) ? uart_data[5:0] : 6'd0;
                    rtc_rx_state <= 2'd3;
                end else if (rtc_rx_state == 2'd3) begin
                    rtc_sec      <= (uart_data[5:0] < 6'd60) ? uart_data[5:0] : 6'd0;
                    rtc_div      <= 25'd0;
                    rtc_rx_state <= 2'd0;
                end else if (uart_data == 8'hF0) begin
                    bg_theme <= 1'b0;
                    if (cpu_gfx_mode) begin cpu_gfx_mode <= 1'b0; restore_bg_req_toggle <= ~restore_bg_req_toggle; end
                end else if (uart_data == 8'hF1) begin
                    bg_theme <= 1'b1;
                    if (cpu_gfx_mode) begin cpu_gfx_mode <= 1'b0; restore_bg_req_toggle <= ~restore_bg_req_toggle; end
                end else if (uart_data == 8'hF2) begin
                    bg_theme <= ~bg_theme;
                    if (cpu_gfx_mode) begin cpu_gfx_mode <= 1'b0; restore_bg_req_toggle <= ~restore_bg_req_toggle; end
                end else if (uart_data == 8'hF3) begin
                    term_enable  <= ~term_enable;
                    if (cpu_gfx_mode) begin cpu_gfx_mode <= 1'b0; restore_bg_req_toggle <= ~restore_bg_req_toggle; end
                end else if (!uart_data[6]) begin
                    pc_joypad <= {1'b0, uart_data[6:0]};
                end else if (!uart_data[5]) begin
                    // 0xC0..0xDF: Live PC Alt+Arrow Mouse packet (bits 0..3 = Up/Dn/Lt/Rt, bit 4 = Click)
                    pc_mouse       <= uart_data[4:0];
                    pc_mouse_timer <= 4'd8;
                    if (uart_data[4]) begin
                        mouse_click_latch <= 1'b1;
                        mouse_en          <= 1'b1;
                    end
                end
            end else if (uart_valid && (uart_mode == 0) && (
                (uart_data >= 8'h20 && uart_data < 8'h7F) ||
                uart_data == 8'h0D || uart_data == 8'h0A ||
                uart_data == 8'h08 || uart_data == 8'h1B ||
                uart_data == 8'h09 || uart_data == 8'h0E
            )) begin
                rtc_rx_state <= 2'd0;
                if (!kbd_ready || kbd_data != 8'h1B) begin
                    kbd_data  <= uart_data;
                    kbd_ready <= 1;
                end
                if (uart_data == 8'h1B) begin term_enable <= 1'b1; adma_active <= 1'b0; adma_need_byte <= 1'b0; end
                case (uart_data)
                    "W", "w": begin uart_joypad[0] <= 1'b1; uart_joy_timer <= 4'd6; end
                    "S", "s": begin uart_joypad[1] <= 1'b1; uart_joy_timer <= 4'd6; end
                    "A", "a": begin uart_joypad[2] <= 1'b1; uart_joy_timer <= 4'd6; end
                    "D", "d": begin uart_joypad[3] <= 1'b1; uart_joy_timer <= 4'd6; end
                    " ", "Z", "z": begin uart_joypad[4] <= 1'b1; uart_joy_timer <= 4'd6; fire_latch <= 1'b1; end
                    "X", "x": begin uart_joypad[5] <= 1'b1; uart_joy_timer <= 4'd6; end
                    default: ;
                endcase
            end else if (ps2_ascii_valid && (uart_mode == 0)) begin
                // PS/2 joypad directions are tracked directly in hardware (ps2_joypad) with 0ms release latency!
                if (!kbd_ready || kbd_data != 8'h1B) begin
                    kbd_data  <= ps2_ascii_code;
                    kbd_ready <= 1;
                end
                ps2_led_toggle <= ~ps2_led_toggle;
                if (ps2_ascii_code == 8'h1B) begin term_enable <= 1'b1; adma_active <= 1'b0; adma_need_byte <= 1'b0; end
            end
        end
    end

    // Combinational LUT-ROM Extension at $A400-$AFFF (0 BSRAMs, 1-cycle sync read via cpu_di)
    wire [7:0] ext_rom_dout;
    basic_ext_rom ext_rom_inst (
        .addr(cpu_ab[11:0]),
        .dout(ext_rom_dout)
    );

    // Synchronous CPU DI Multiplexer (gated by cpu_rdy so cycle-stealing DMA preserves DI/AB)
    always @(posedge sys_clk) begin
        if (cpu_rdy) begin
            if (cpu_ab < 16'h2000) begin
                cpu_di <= cpu_ram_lo[cpu_ab[12:0]];
            end else if (cpu_ab < 16'h3000) begin
                cpu_di <= cpu_ram_hi[cpu_ab[11:0]];
            end else if (cpu_ab == 16'hA000) begin
                cpu_di <= {(kbd_ready && (kbd_data == 8'h1B || kbd_data == 8'h03)), 5'b00000, 1'b1, kbd_ready};
            end else if (cpu_ab == 16'hA001) begin
                cpu_di <= kbd_data;
            end else if (cpu_ab == 16'hA003) begin
                cpu_di <= timer_ticks;
            end else if (cpu_ab == 16'hA004) begin
                cpu_di <= ps2_joypad | pc_joypad | uart_joypad | {s1, 2'b00, fire_latch, 4'b0000};
            end else if (cpu_ab == 16'hA005) begin
                cpu_di <= lfsr[7:0];
            end else if (cpu_ab == 16'hA006) begin
                cpu_di <= {6'b000000, bg_theme, term_enable};
            end else if (cpu_ab == 16'hA007) begin
                cpu_di <= {3'b000, rtc_hour};
            end else if (cpu_ab == 16'hA008) begin
                cpu_di <= {2'b00, rtc_min};
            end else if (cpu_ab == 16'hA009) begin
                cpu_di <= {2'b00, rtc_sec};
            end else if (cpu_ab == 16'hA00A) begin
                cpu_di <= synth_inst_reg;
            end else if (cpu_ab == 16'hA00B) begin
                cpu_di <= synth_fx_reg;
            end else if (cpu_ab == 16'hA00C) begin
                cpu_di <= mouse_x[7:0];
            end else if (cpu_ab == 16'hA00D) begin
                cpu_di <= {6'b000000, mouse_x[9:8]};
            end else if (cpu_ab == 16'hA00E) begin
                cpu_di <= mouse_y[7:0];
            end else if (cpu_ab == 16'hA00F) begin
                cpu_di <= {ps2_mouse[7], mouse_en, 2'b00, mouse_click_latch, mouse_rmb, mouse_lmb, mouse_y[8]};
            end else if (cpu_ab == 16'hA010) begin
                cpu_di <= sd_rx_data;
            end else if (cpu_ab == 16'hA014) begin
                cpu_di <= a012_reading ? rd_dout : a014_latch;
            end else if (cpu_ab == 16'hA016) begin
                cpu_di <= pcm_dac_reg;
            end else if (cpu_ab == 16'hA017) begin
                cpu_di <= {4'b0000, (pcm_timer != 12'd0), pcm_rate_reg};
            end else if (cpu_ab == 16'hA018) begin
                cpu_di <= {2'b00, adma_cur_addr[21:16]};
            end else if (cpu_ab == 16'hA019) begin
                cpu_di <= adma_rem_pages[7:0];
            end else if (cpu_ab == 16'hA01A) begin
                cpu_di <= adma_rem_pages[15:8];
            end else if (cpu_ab == 16'hA01B) begin
                cpu_di <= {adma_active, adma_loop, 3'b000, adma_rate};
            end else if (cpu_ab == 16'hA030) begin
                cpu_di <= w5500_rx_data;
            end else if (cpu_ab == 16'hA031) begin
                cpu_di <= {6'b000000, w5500_ctrl};
            end else if (cpu_ab >= 16'hA400 && cpu_ab < 16'hB000) begin
                cpu_di <= ext_rom_dout;
            end else if (cpu_ab >= 16'hE000) begin
                cpu_di <= cpu_rom[cpu_ab[12:0]];
            end else begin
                cpu_di <= 8'hEA;
            end
        end
    end

    cpu cpu_inst (
        .clk(sys_clk),
        .reset(reset),
        .AB(cpu_ab),
        .DI(sdram_data_phase ? rd_dout : cpu_di),
        .DO(cpu_do),
        .WE(cpu_we),
        .IRQ(1'b0),
        .NMI(1'b0),
        .RDY(cpu_rdy)
    );

    // --- HDMI Output & Framebuffer ---
    wire [11:0] cx, cy;
    wire [2:0]  tmds_d;
    wire        tmds_c;

    wire fb_rx_valid = uart_valid && (uart_mode == 1 || uart_mode == 2);

    wire [23:0] rgb_bg;
    wire        audio_we;
    wire [1:0]  audio_channel;
    wire [23:0] audio_phase_inc;
    wire [7:0]  audio_volume;

    sdram_framebuffer fb_inst (
        .clk(hclk),
        .rst_n(~reset),
        .rx_data(uart_data),
        .rx_valid(fb_rx_valid),
        .uart_mode(uart_mode),
        .cpu_gpu_req_toggle(cpu_gpu_req_toggle),
        .cpu_gpu_data(cpu_gpu_data),
        .cpu_gpu_ack_toggle(cpu_gpu_ack_toggle),
        .space_bg_en(~cpu_gfx_mode && (uart_mode == 2'd0)),
        .bg_theme(bg_theme),
        .rtc_hud_data(rtc_hud_data),
        .restore_bg_req_toggle(restore_bg_req_toggle),
        .restore_bg_ack_toggle(restore_bg_ack_toggle),
        .rd_req_toggle(rd_req_toggle),
        .rd_req_we(rd_req_we),
        .rd_req_addr(rd_req_addr),
        .rd_req_wdata(rd_req_wdata),
        .rd_rdata(rd_dout),
        .rd_ack_toggle(rd_ack_toggle),
        .cx(cx),
        .cy(cy),
        .rgb(rgb_bg),
        .O_sdram_clk(O_sdram_clk),
        .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n),
        .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq),
        .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm),
        .audio_we(audio_we),
        .audio_channel(audio_channel),
        .audio_phase_inc(audio_phase_inc),
        .audio_volume(audio_volume)
    );

    // --- Terminal Module ---
    wire [23:0] rgb_term;
    wire        term_active;

    terminal term_inst (
        .clk_pixel(hclk),
        .clk_sys(sys_clk),
        .rst_n(~reset),
        .rx_data(term_rx_data_cpu),
        .rx_valid(term_rx_valid_cpu),
        .term_enable(term_enable && (uart_mode == 0)),
        .busy(term_busy),
        .cx(cx),
        .cy(cy),
        .term_rgb(rgb_term),
        .term_active(term_active)
    );

    // --- Hardware Sprite Mouse Pointer Overlay (12x16 Arrow, 0 BSRAMs, Top-Most Layer) ---
    reg [9:0] mouse_x_s0 = 10'd320, mouse_x_frame = 10'd320;
    reg [8:0] mouse_y_s0 = 9'd180,  mouse_y_frame = 9'd180;
    reg       mouse_en_s0 = 1'b1,   mouse_en_frame = 1'b1;
    reg       mouse_bt_s0 = 1'b0,   mouse_bt_frame = 1'b0;

    always @(posedge hclk) begin
        mouse_x_s0  <= mouse_x;
        mouse_y_s0  <= mouse_y;
        mouse_en_s0 <= mouse_en;
        mouse_bt_s0 <= mouse_lmb | mouse_rmb;
        if (cx == 12'd0 && cy == 12'd720) begin
            mouse_x_frame  <= mouse_x_s0;
            mouse_y_frame  <= mouse_y_s0;
            mouse_en_frame <= mouse_en_s0;
            mouse_bt_frame <= mouse_bt_s0;
        end
    end

    wire [9:0] scr_x = cx[10:1];
    wire [8:0] scr_y = cy[9:1];
    wire [9:0] cur_dx = scr_x - mouse_x_frame;
    wire [8:0] cur_dy = scr_y - mouse_y_frame;
    wire       cur_in_box = mouse_en_frame && (cx < 12'd1280) && (cy < 12'd720) &&
                            (scr_x >= mouse_x_frame) && (cur_dx < 10'd12) &&
                            (scr_y >= mouse_y_frame) && (cur_dy < 9'd16);

    reg [11:0] cur_border_bits;
    reg [11:0] cur_fill_bits;
    always @(*) begin
        case (cur_dy[3:0])
            4'd0:  begin cur_border_bits = 12'b1000_0000_0000; cur_fill_bits = 12'b0000_0000_0000; end
            4'd1:  begin cur_border_bits = 12'b1100_0000_0000; cur_fill_bits = 12'b0000_0000_0000; end
            4'd2:  begin cur_border_bits = 12'b1010_0000_0000; cur_fill_bits = 12'b0100_0000_0000; end
            4'd3:  begin cur_border_bits = 12'b1001_0000_0000; cur_fill_bits = 12'b0110_0000_0000; end
            4'd4:  begin cur_border_bits = 12'b1000_1000_0000; cur_fill_bits = 12'b0111_0000_0000; end
            4'd5:  begin cur_border_bits = 12'b1000_0100_0000; cur_fill_bits = 12'b0111_1000_0000; end
            4'd6:  begin cur_border_bits = 12'b1000_0010_0000; cur_fill_bits = 12'b0111_1100_0000; end
            4'd7:  begin cur_border_bits = 12'b1000_0001_0000; cur_fill_bits = 12'b0111_1110_0000; end
            4'd8:  begin cur_border_bits = 12'b1000_0000_1000; cur_fill_bits = 12'b0111_1111_0000; end
            4'd9:  begin cur_border_bits = 12'b1000_0000_0100; cur_fill_bits = 12'b0111_1111_1000; end
            4'd10: begin cur_border_bits = 12'b1000_0011_1110; cur_fill_bits = 12'b0111_1100_0000; end
            4'd11: begin cur_border_bits = 12'b1001_0010_0000; cur_fill_bits = 12'b0110_1100_0000; end
            4'd12: begin cur_border_bits = 12'b1010_1001_0000; cur_fill_bits = 12'b0100_0110_0000; end
            4'd13: begin cur_border_bits = 12'b1100_1001_0000; cur_fill_bits = 12'b0000_0110_0000; end
            4'd14: begin cur_border_bits = 12'b1000_0100_1000; cur_fill_bits = 12'b0000_0011_0000; end
            4'd15: begin cur_border_bits = 12'b0000_0111_0000; cur_fill_bits = 12'b0000_0000_0000; end
        endcase
    end

    wire [3:0]  cur_bit_idx   = 4'd11 - cur_dx[3:0];
    wire        cur_is_fill   = cur_in_box && cur_fill_bits[cur_bit_idx];
    wire        cur_is_border = cur_in_box && cur_border_bits[cur_bit_idx];
    wire [23:0] rgb_base      = term_active ? rgb_term : rgb_bg;
    wire [23:0] rgb           = cur_is_fill   ? (mouse_bt_frame ? 24'hFF8800 : 24'hFFFFFF) :
                                cur_is_border ? 24'h000000 : rgb_base;

    // --- 16-Bit Stereo FM / Wavetable / ADSR Audio Synthesizer ---
    wire clk_audio;
    wire [15:0] audio_sample_l;
    wire [15:0] audio_sample_r;

    audio_synth synth_inst (
        .clk_pixel(hclk),
        .rst_n(~reset),
        .audio_we(audio_we),
        .audio_channel(audio_channel),
        .phase_inc(audio_phase_inc),
        .volume(audio_volume),
        .cfg_inst_we(synth_inst_we),
        .cfg_inst_data(synth_inst_reg),
        .cfg_fx_mode(synth_fx_reg),
        .pcm_sample(pcm_dac_reg),
        .pcm_rate(eff_pcm_rate),
        .clk_audio(clk_audio),
        .sample_out_l(audio_sample_l),
        .sample_out_r(audio_sample_r)
    );

    wire [15:0] audio_sample_word [1:0];
    assign audio_sample_word[0] = audio_sample_l;
    assign audio_sample_word[1] = audio_sample_r;

    hdmi #(
        .VIDEO_ID_CODE(4),
        .DVI_OUTPUT(1'b0),
        .VIDEO_REFRESH_RATE(60.0),
        .AUDIO_RATE(48000),
        .AUDIO_BIT_WIDTH(16)
    ) hdmi_inst (
        .clk_pixel_x5(hclk5),
        .clk_pixel(hclk),
        .clk_audio(clk_audio),
        .reset(reset),
        .rgb(rgb),
        .audio_sample_word(audio_sample_word),
        .tmds(tmds_d),
        .tmds_clock(tmds_c),
        .cx(cx),
        .cy(cy),
        .frame_width(),
        .frame_height(),
        .screen_width(),
        .screen_height()
    );

    ELVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_c, tmds_d}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

    assign led[0] = ps2_led_toggle;
    assign led[1] = ~pll_lock;

endmodule
