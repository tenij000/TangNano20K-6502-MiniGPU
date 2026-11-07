`timescale 1ns / 1ps

// ============================================================================
// Hardware Procedural 720p Dutch/Twentse Farm Landscape Engine (60 FPS)
// Tang Nano 20K (GW2AR-18C) | 74.25 MHz Pixel Clock | 0 BSRAMs!
//
// Features:
//   - Golden-Hour / Sunset sky gradient (100% horizontal, zero vertical streaks)
//   - 3D-shaded setting sun & solar corona at (936, 284) (smooth sphere, no bars)
//   - 2 parallax layers of fluffy white/silver multi-puff cumulus clouds
//     (Fully pipelined across Stages 1 & 2 -> zero vertical carry-ripple glitches!)
//   - Flock of 5 birds taking off from the right meadow (between farmhouse &
//     windmill) and climbing diagonally over the left hill @ 60 FPS!
//   - Rounded 3D rolling Veluwe/Twente hills, pine forest ridge, mist & hedgerows
//   - 3D perspective lush meadow with wildflowers, wooden fence & 3 Friesian cows
//   - Winding reflective meadow brook with 60 FPS shimmering sunset ripples
//   - Natural brown 3D ploughed perspective furrows & green headland
//   - Twentse Saksische Boerderij (single crisp gable roof, vakwerk, silo, oak tree)
//   - Authentic Dutch Stellingmolen with 60 FPS sub-pixel rotating lattice sails
//   - Animated red tractor with plough that turns around at each end and drives back!
// ============================================================================

module farm_landscape_bg (
    input  wire        clk_pixel,   // 74.25 MHz HDMI pixel clock
    input  wire        rst_n,
    input  wire [10:0] cx,          // 0..1279 active
    input  wire [9:0]  cy,          // 0..719 active
    output reg  [7:0]  farm_color   // RGB332 output (aligned with scanout)
);

    // ========================================================================
    // 1. 60 Hz Frame Counter & 512-Step Sin/Cos Table for Windmill Sails
    // ========================================================================
    reg [15:0] frame_cnt = 16'd48;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            frame_cnt <= 16'd48;
        end else if (cx == 11'd0 && cy == 10'd720) begin
            frame_cnt <= frame_cnt + 16'd1;
        end
    end

    // Windmill rotation phase: 512 steps per revolution (~8.5s per full rotation)
    wire [8:0] rot_phase = frame_cnt[8:0];
    wire [1:0] rot_quad  = rot_phase[8:7];
    wire [6:0] rot_idx   = rot_phase[6:0];
    wire [6:0] sin_idx   = rot_quad[0] ? ~rot_idx : rot_idx;
    wire [6:0] cos_idx   = rot_quad[0] ?  rot_idx : ~rot_idx;

    reg [6:0] sin_mag;
    reg [6:0] cos_mag;

    always @(*) begin
        case (sin_idx[6:2])
            5'd0:  sin_mag = 7'd3;   5'd1:  sin_mag = 7'd9;   5'd2:  sin_mag = 7'd15;  5'd3:  sin_mag = 7'd21;
            5'd4:  sin_mag = 7'd27;  5'd5:  sin_mag = 7'd33;  5'd6:  sin_mag = 7'd39;  5'd7:  sin_mag = 7'd45;
            5'd8:  sin_mag = 7'd51;  5'd9:  sin_mag = 7'd56;  5'd10: sin_mag = 7'd62;  5'd11: sin_mag = 7'd67;
            5'd12: sin_mag = 7'd73;  5'd13: sin_mag = 7'd78;  5'd14: sin_mag = 7'd83;  5'd15: sin_mag = 7'd88;
            5'd16: sin_mag = 7'd92;  5'd17: sin_mag = 7'd97;  5'd18: sin_mag = 7'd101; 5'd19: sin_mag = 7'd105;
            5'd20: sin_mag = 7'd108; 5'd21: sin_mag = 7'd112; 5'd22: sin_mag = 7'd115; 5'd23: sin_mag = 7'd117;
            5'd24: sin_mag = 7'd120; 5'd25: sin_mag = 7'd122; 5'd26: sin_mag = 7'd124; 5'd27: sin_mag = 7'd125;
            5'd28: sin_mag = 7'd126; 5'd29: sin_mag = 7'd127; 5'd30: sin_mag = 7'd127; 5'd31: sin_mag = 7'd127;
        endcase
    end

    always @(*) begin
        case (cos_idx[6:2])
            5'd0:  cos_mag = 7'd3;   5'd1:  cos_mag = 7'd9;   5'd2:  cos_mag = 7'd15;  5'd3:  cos_mag = 7'd21;
            5'd4:  cos_mag = 7'd27;  5'd5:  cos_mag = 7'd33;  5'd6:  cos_mag = 7'd39;  5'd7:  cos_mag = 7'd45;
            5'd8:  cos_mag = 7'd51;  5'd9:  cos_mag = 7'd56;  5'd10: cos_mag = 7'd62;  5'd11: cos_mag = 7'd67;
            5'd12: cos_mag = 7'd73;  5'd13: cos_mag = 7'd78;  5'd14: cos_mag = 7'd83;  5'd15: cos_mag = 7'd88;
            5'd16: cos_mag = 7'd92;  5'd17: cos_mag = 7'd97;  5'd18: cos_mag = 7'd101; 5'd19: cos_mag = 7'd105;
            5'd20: cos_mag = 7'd108; 5'd21: cos_mag = 7'd112; 5'd22: cos_mag = 7'd115; 5'd23: cos_mag = 7'd117;
            5'd24: cos_mag = 7'd120; 5'd25: cos_mag = 7'd122; 5'd26: cos_mag = 7'd124; 5'd27: cos_mag = 7'd125;
            5'd28: cos_mag = 7'd126; 5'd29: cos_mag = 7'd127; 5'd30: cos_mag = 7'd127; 5'd31: cos_mag = 7'd127;
        endcase
    end

    reg signed [7:0] sin_t = 8'sd64;
    reg signed [7:0] cos_t = 8'sd110;
    always @(posedge clk_pixel) begin
        sin_t <= rot_quad[1] ? -$signed({1'b0, sin_mag}) : $signed({1'b0, sin_mag});
        cos_t <= (rot_quad[1] ^ rot_quad[0]) ? -$signed({1'b0, cos_mag}) : $signed({1'b0, cos_mag});
    end

    // Frame-rate precomputed cloud puff X-offsets (registered at 60 Hz -> 0 pixel carry chains!)
    reg [8:0] ofs_1a = 9'd12 + 9'd3 - 9'd204;
    reg [8:0] ofs_1b = 9'd12 + 9'd3 - 9'd232;
    reg [8:0] ofs_1c = 9'd12 + 9'd3 - 9'd264;
    reg [8:0] ofs_1d = 9'd12 + 9'd3 - 9'd290;
    reg [8:0] ofs_2a = 9'd24 + 9'd183 - 9'd216;
    reg [8:0] ofs_2b = 9'd24 + 9'd183 - 9'd246;
    reg [8:0] ofs_2c = 9'd24 + 9'd183 - 9'd276;

    always @(posedge clk_pixel) begin
        ofs_1a <= frame_cnt[10:2] + 9'd311; // + 3 - 204 (mod 512)
        ofs_1b <= frame_cnt[10:2] + 9'd283; // + 3 - 232 (mod 512)
        ofs_1c <= frame_cnt[10:2] + 9'd251; // + 3 - 264 (mod 512)
        ofs_1d <= frame_cnt[10:2] + 9'd225; // + 3 - 290 (mod 512)
        ofs_2a <= frame_cnt[9:1]  + 9'd479; // + 183 - 216 (mod 512)
        ofs_2b <= frame_cnt[9:1]  + 9'd449; // + 183 - 246 (mod 512)
        ofs_2c <= frame_cnt[9:1]  + 9'd419; // + 183 - 276 (mod 512)
    end

    // Look ahead 3 pixel clocks to match 3-stage pipeline
    wire [10:0] xx = cx + 11'd3;
    wire [9:0]  yy = cy;
    wire signed [12:0] sxx = $signed({2'b00, xx});
    wire signed [12:0] syy = $signed({3'b000, yy});

    // ========================================================================
    // STAGE 1: Coordinates, Cloud/Bird/Brook/Tractor/Cow Offsets & Sky Gradient
    // ========================================================================
    wire dither  = xx[0] ^ yy[0];
    wire dither2 = xx[1] ^ yy[1];

    // Purely horizontal sky gradient (depends ONLY on yy, zero vertical lines!)
    reg [7:0] sky_c0, sky_c1;
    reg [3:0] sky_sub;
    always @(*) begin
        if (yy < 10'd48) begin
            sky_c0 = 8'h01; sky_c1 = 8'h02; sky_sub = yy[4:1];
        end else if (yy < 10'd96) begin
            sky_c0 = 8'h02; sky_c1 = 8'h06; sky_sub = (yy - 10'd48) >> 1;
        end else if (yy < 10'd144) begin
            sky_c0 = 8'h06; sky_c1 = 8'h26; sky_sub = (yy - 10'd96) >> 1;
        end else if (yy < 10'd192) begin
            sky_c0 = 8'h26; sky_c1 = 8'h2A; sky_sub = (yy - 10'd144) >> 1;
        end else if (yy < 10'd236) begin
            sky_c0 = 8'h2A; sky_c1 = 8'h4A; sky_sub = (yy - 10'd192) >> 1;
        end else if (yy < 10'd276) begin
            sky_c0 = 8'h4A; sky_c1 = 8'h6E; sky_sub = (yy - 10'd236) >> 1;
        end else if (yy < 10'd312) begin
            sky_c0 = 8'h6E; sky_c1 = 8'hAD; sky_sub = (yy - 10'd276) >> 1;
        end else if (yy < 10'd348) begin
            sky_c0 = 8'hAD; sky_c1 = 8'hEC; sky_sub = (yy - 10'd312) >> 1;
        end else if (yy < 10'd384) begin
            sky_c0 = 8'hEC; sky_c1 = 8'hF4; sky_sub = (yy - 10'd348) >> 1;
        end else begin
            sky_c0 = 8'hF4; sky_c1 = 8'hF8; sky_sub = (yy - 10'd384) >> 1;
        end
    end
    wire [7:0] sky_base = (sky_sub < 4'd6)  ? sky_c0 :
                          (sky_sub < 4'd10) ? (yy[0] ? sky_c1 : sky_c0) : sky_c1;

    // Evening stars in upper twilight sky (yy < 108, above clouds)
    wire [8:0] star_h = ((xx[9:1] * 9'd73) ^ (yy[7:1] * 9'd151));
    wire       is_star = (yy < 10'd108) && (star_h == 9'd1) && !xx[0] && !yy[0];
    wire [7:0] sky_with_stars = is_star ? (xx[3] ? 8'h92 : 8'h49) : sky_base;

    // Setting Sun at (936, 284), R=58, Halo R=128
    wire signed [12:0] w_sun_dx = sxx - 13'sd936;
    wire signed [12:0] w_sun_dy = syy - 13'sd284;
    wire               w_sun_box = (w_sun_dx >= -13'sd128) && (w_sun_dx <= 13'sd128) &&
                                   (w_sun_dy >= -13'sd128) && (w_sun_dy <= 13'sd128) && (yy < 10'd415);

    // Windmill Hub at (1090, 304), Sail Box [-96..+96]
    wire signed [12:0] w_hub_dx = sxx - 13'sd1090;
    wire signed [12:0] w_hub_dy = syy - 13'sd304;
    wire               w_hub_box = (w_hub_dx >= -13'sd96) && (w_hub_dx <= 13'sd96) &&
                                   (w_hub_dy >= -13'sd96) && (w_hub_dy <= 13'sd96);

    // Distant Hills: Hill 1A (cx=280), Hill 1B (cx=860), Hill 2A (cx=180), Hill 2B (cx=1060)
    wire [10:0] u_h1a = (xx >= 11'd280)  ? (xx - 11'd280)  : (11'd280 - xx);
    wire [10:0] u_h1b = (xx >= 11'd860)  ? (xx - 11'd860)  : (11'd860 - xx);
    wire [10:0] u_h2a = (xx >= 11'd180)  ? (xx - 11'd180)  : (11'd180 - xx);
    wire [10:0] u_h2b = (xx >= 11'd1060) ? (xx - 11'd1060) : (11'd1060 - xx);

    wire [8:0] c_h1a = (u_h1a > 11'd511) ? 9'd511 : u_h1a[8:0];
    wire [8:0] c_h1b = (u_h1b > 11'd511) ? 9'd511 : u_h1b[8:0];
    wire [8:0] c_h2a = (u_h2a > 11'd511) ? 9'd511 : u_h2a[8:0];
    wire [8:0] c_h2b = (u_h2b > 11'd511) ? 9'd511 : u_h2b[8:0];

    // --- Cloud Layer 1 & 2 Stage-1 Y-Distances (purely horizontal, depends only on yy) ---
    wire signed [10:0] c1_dy_w = $signed({1'b0, yy}) - 11'sd150;
    wire signed [10:0] s_p1a_y_w = c1_dy_w + 11'sd6;
    wire signed [10:0] s_p1b_y_w = c1_dy_w + 11'sd16;
    wire signed [10:0] s_p1c_y_w = c1_dy_w + 11'sd12;
    wire signed [10:0] s_p1d_y_w = c1_dy_w + 11'sd4;

    wire [9:0] ay_1a_w = s_p1a_y_w[10] ? ((-s_p1a_y_w[8:0]) << 1) : (s_p1a_y_w[8:0] << 1);
    wire [9:0] ay_1b_w = s_p1b_y_w[10] ? ((-s_p1b_y_w[8:0]) << 1) : (s_p1b_y_w[8:0] << 1);
    wire [9:0] ay_1c_w = s_p1c_y_w[10] ? ((-s_p1c_y_w[8:0]) << 1) : (s_p1c_y_w[8:0] << 1);
    wire [9:0] ay_1d_w = s_p1d_y_w[10] ? ((-s_p1d_y_w[8:0]) << 1) : (s_p1d_y_w[8:0] << 1);

    wire signed [10:0] c2_dy_w = $signed({1'b0, yy}) - 11'sd228;
    wire signed [10:0] s_p2a_y_w = c2_dy_w + 11'sd5;
    wire signed [10:0] s_p2b_y_w = c2_dy_w + 11'sd14;
    wire signed [10:0] s_p2c_y_w = c2_dy_w + 11'sd7;

    wire [9:0] ay_2a_w = s_p2a_y_w[10] ? ((-s_p2a_y_w[8:0]) << 1) : (s_p2a_y_w[8:0] << 1);
    wire [9:0] ay_2b_w = s_p2b_y_w[10] ? ((-s_p2b_y_w[8:0]) << 1) : (s_p2b_y_w[8:0] << 1);
    wire [9:0] ay_2c_w = s_p2c_y_w[10] ? ((-s_p2c_y_w[8:0]) << 1) : (s_p2c_y_w[8:0] << 1);

    // --- Bird Flock Stage-1 Relative Offsets ---
    wire [9:0]  flight_t = frame_cnt[10:1];
    wire signed [12:0] flock_x = 13'sd950 - $signed({3'b000, flight_t});
    wire signed [12:0] flock_y = 13'sd432 - $signed({5'b00000, flight_t[9:2]}) - $signed({7'b0000000, flight_t[9:4]});
    wire signed [12:0] w_b1_dx = sxx - flock_x;
    wire signed [12:0] w_b1_dy = syy - flock_y;

    // --- Brook & Furrow Stage-1 Offsets ---
    wire       w_in_ground = (yy >= 10'd464);
    wire [7:0] w_dy_g      = w_in_ground ? (yy - 10'd464) : 8'd0;
    wire [6:0] w_s_phase   = w_dy_g[6:0];
    wire [5:0] w_s_tri     = w_s_phase[6] ? (~w_s_phase[5:0]) : w_s_phase[5:0];
    wire signed [12:0] w_s_wave   = w_dy_g[7] ? $signed({8'd0, w_s_tri[5:1]}) : -$signed({8'd0, w_s_tri[5:1]});
    wire signed [12:0] w_brook_cx = 13'sd710 - $signed({5'd0, w_dy_g}) + w_s_wave;
    wire signed [12:0] w_brook_hw = 13'sd6 + $signed({8'd0, w_dy_g[7:3]});
    wire signed [12:0] w_dx_brook = sxx - w_brook_cx;
    wire signed [12:0] w_persp_u  = (sxx - 13'sd680) - $signed({5'd0, w_dy_g}) - $signed({7'd0, w_dy_g[7:2]});

    // --- Tractor Stage-1 Offsets ---
    wire        tr_dir      = frame_cnt[10];
    wire [7:0]  tr_pos      = tr_dir ? (~frame_cnt[9:2]) : frame_cnt[9:2];
    wire [10:0] tr_cx       = 11'd760 + {3'd0, tr_pos};
    wire signed [12:0] w_tdx_raw = sxx - $signed({2'b00, tr_cx});
    wire signed [12:0] w_tdx     = tr_dir ? (-w_tdx_raw) : w_tdx_raw;
    wire signed [12:0] w_tdy     = syy - 13'sd518;

    // Stage 1 Pipeline Registers
    reg [10:0]        xx_p1;
    reg [9:0]         yy_p1;
    reg               dither_p1, dither2_p1;
    reg [7:0]         sky_p1;

    reg               sun_box_p1;
    reg [7:0]         u_sun_dx_p1, u_sun_dy_p1;

    reg               hub_box_p1;
    reg signed [7:0]  hub_dx_p1, hub_dy_p1;

    reg [8:0]         h1a_p1, h1b_p1, h2a_p1, h2b_p1;

    // Cloud Stage-1 registers: direct 9-bit signed puff X-offsets (1 adder from cx[8:0]!)
    reg [8:0]         dx_1a_p1, dx_1b_p1, dx_1c_p1, dx_1d_p1;
    reg [5:0]         ay_1a_p1, ay_1b_p1, ay_1c_p1, ay_1d_p1;
    reg               c1_yband_p1, c1_top_p1, c1_mid_p1;

    reg [8:0]         dx_2a_p1, dx_2b_p1, dx_2c_p1;
    reg [5:0]         ay_2a_p1, ay_2b_p1, ay_2c_p1;
    reg               c2_yband_p1, c2_top_p1, c2_mid_p1;

    // Bird, Brook & Tractor Stage-1 registers
    reg signed [12:0] b1_dx_p1, b1_dy_p1;
    reg               in_ground_p1;
    reg signed [12:0] brook_hw_p1, dx_brook_p1;
    reg [3:0]         furrow_pos_p1;
    reg signed [12:0] tdx_p1, tdy_p1;

    always @(posedge clk_pixel) begin
        xx_p1      <= xx;
        yy_p1      <= yy;
        dither_p1  <= dither;
        dither2_p1 <= dither2;
        sky_p1     <= sky_with_stars;

        sun_box_p1  <= w_sun_box;
        u_sun_dx_p1 <= w_sun_box ? (w_sun_dx[12] ? (-w_sun_dx[7:0]) : w_sun_dx[7:0]) : 8'd0;
        u_sun_dy_p1 <= w_sun_box ? (w_sun_dy[12] ? (-w_sun_dy[7:0]) : w_sun_dy[7:0]) : 8'd0;

        hub_box_p1 <= w_hub_box;
        hub_dx_p1  <= w_hub_box ? w_hub_dx[7:0] : 8'sd0;
        hub_dy_p1  <= w_hub_box ? w_hub_dy[7:0] : 8'sd0;

        h1a_p1     <= c_h1a;
        h1b_p1     <= c_h1b;
        h2a_p1     <= c_h2a;
        h2b_p1     <= c_h2b;

        // Cloud 1 puff X-offsets (single 9-bit addition per puff directly from cx[8:0])
        dx_1a_p1    <= cx[8:0] + ofs_1a;
        dx_1b_p1    <= cx[8:0] + ofs_1b;
        dx_1c_p1    <= cx[8:0] + ofs_1c;
        dx_1d_p1    <= cx[8:0] + ofs_1d;
        ay_1a_p1    <= (|ay_1a_w[9:6]) ? 6'd63 : ay_1a_w[5:0];
        ay_1b_p1    <= (|ay_1b_w[9:6]) ? 6'd63 : ay_1b_w[5:0];
        ay_1c_p1    <= (|ay_1c_w[9:6]) ? 6'd63 : ay_1c_w[5:0];
        ay_1d_p1    <= (|ay_1d_w[9:6]) ? 6'd63 : ay_1d_w[5:0];
        c1_yband_p1 <= (yy >= 10'd110) && (yy <= 10'd155);
        c1_top_p1   <= (c1_dy_w < -11'sd10);
        c1_mid_p1   <= (c1_dy_w < 11'sd1);

        // Cloud 2 puff X-offsets (single 9-bit addition per puff directly from cx[8:0])
        dx_2a_p1    <= cx[8:0] + ofs_2a;
        dx_2b_p1    <= cx[8:0] + ofs_2b;
        dx_2c_p1    <= cx[8:0] + ofs_2c;
        ay_2a_p1    <= (|ay_2a_w[9:6]) ? 6'd63 : ay_2a_w[5:0];
        ay_2b_p1    <= (|ay_2b_w[9:6]) ? 6'd63 : ay_2b_w[5:0];
        ay_2c_p1    <= (|ay_2c_w[9:6]) ? 6'd63 : ay_2c_w[5:0];
        c2_yband_p1 <= (yy >= 10'd190) && (yy <= 10'd233);
        c2_top_p1   <= (c2_dy_w < -11'sd8);
        c2_mid_p1   <= (c2_dy_w < 11'sd1);

        // Bird, Brook & Tractor Stage-1
        b1_dx_p1      <= w_b1_dx;
        b1_dy_p1      <= w_b1_dy;
        in_ground_p1  <= w_in_ground;
        brook_hw_p1   <= w_brook_hw;
        dx_brook_p1   <= w_dx_brook;
        furrow_pos_p1 <= w_persp_u[3:0];
        tdx_p1        <= w_tdx;
        tdy_p1        <= w_tdy;
    end

    // ========================================================================
    // STAGE 2: Squared Distances, Sail Rotation, Hills & Cloud/Bird/Ground Eval
    // ========================================================================
    wire [15:0] w_sun_dx_sq = u_sun_dx_p1 * u_sun_dx_p1;
    wire [15:0] w_sun_dy_sq = u_sun_dy_p1 * u_sun_dy_p1;

    wire signed [15:0] w_u_rot = (hub_dx_p1 * cos_t) + (hub_dy_p1 * sin_t);
    wire signed [15:0] w_v_rot = (-hub_dx_p1 * sin_t) + (hub_dy_p1 * cos_t);

    wire [17:0] sq_h1a = h1a_p1 * h1a_p1;
    wire [17:0] sq_h1b = h1b_p1 * h1b_p1;
    wire [17:0] sq_h2a = h2a_p1 * h2a_p1;
    wire [17:0] sq_h2b = h2b_p1 * h2b_p1;

    wire [9:0] y_h1a_w   = 10'd362 + {3'b000, sq_h1a[17:11]};
    wire [9:0] y_h1b_w   = 10'd368 + {3'b000, sq_h1b[17:11]};
    wire [9:0] y_h1_min  = (y_h1a_w < y_h1b_w) ? y_h1a_w : y_h1b_w;
    wire [9:0] y_hill1_w = (y_h1_min > 10'd404) ? 10'd404 : y_h1_min;

    wire [9:0] y_h2a_w   = 10'd414 + {4'b0000, sq_h2a[17:12]};
    wire [9:0] y_h2b_w   = 10'd418 + {4'b0000, sq_h2b[17:12]};
    wire [9:0] y_h2_min  = (y_h2a_w < y_h2b_w) ? y_h2a_w : y_h2b_w;
    wire [9:0] y_hill2_w = (y_h2_min > 10'd438) ? 10'd438 : y_h2_min;

    // --- Cloud 1 & 2 Fast 6-Bit Octagon Evaluation in Stage 2 (registered into _p2!) ---
    wire in_x_1a = (dx_1a_p1[8:5] == 4'h0) || (dx_1a_p1[8:5] == 4'hF);
    wire in_x_1b = (dx_1b_p1[8:5] == 4'h0) || (dx_1b_p1[8:5] == 4'hF);
    wire in_x_1c = (dx_1c_p1[8:5] == 4'h0) || (dx_1c_p1[8:5] == 4'hF);
    wire in_x_1d = (dx_1d_p1[8:5] == 4'h0) || (dx_1d_p1[8:5] == 4'hF);

    wire [5:0] ax_1a = dx_1a_p1[8] ? (6'd0 - dx_1a_p1[5:0]) : dx_1a_p1[5:0];
    wire [5:0] ax_1b = dx_1b_p1[8] ? (6'd0 - dx_1b_p1[5:0]) : dx_1b_p1[5:0];
    wire [5:0] ax_1c = dx_1c_p1[8] ? (6'd0 - dx_1c_p1[5:0]) : dx_1c_p1[5:0];
    wire [5:0] ax_1d = dx_1d_p1[8] ? (6'd0 - dx_1d_p1[5:0]) : dx_1d_p1[5:0];

    wire [6:0] d_p1a_x = {1'b0, ax_1a} + {2'b00, ay_1a_p1[5:1]};
    wire [6:0] d_p1a_y = {1'b0, ay_1a_p1} + {2'b00, ax_1a[5:1]};
    wire [6:0] d_p1b_x = {1'b0, ax_1b} + {2'b00, ay_1b_p1[5:1]};
    wire [6:0] d_p1b_y = {1'b0, ay_1b_p1} + {2'b00, ax_1b[5:1]};
    wire [6:0] d_p1c_x = {1'b0, ax_1c} + {2'b00, ay_1c_p1[5:1]};
    wire [6:0] d_p1c_y = {1'b0, ay_1c_p1} + {2'b00, ax_1c[5:1]};
    wire [6:0] d_p1d_x = {1'b0, ax_1d} + {2'b00, ay_1d_p1[5:1]};
    wire [6:0] d_p1d_y = {1'b0, ay_1d_p1} + {2'b00, ax_1d[5:1]};

    wire hit_1a = in_x_1a && (d_p1a_x < 7'd24) && (d_p1a_y < 7'd24);
    wire hit_1b = in_x_1b && (d_p1b_x < 7'd32) && (d_p1b_y < 7'd32);
    wire hit_1c = in_x_1c && (d_p1c_x < 7'd28) && (d_p1c_y < 7'd28);
    wire hit_1d = in_x_1d && (d_p1d_x < 7'd22) && (d_p1d_y < 7'd22);
    wire br_1b  = in_x_1b && (d_p1b_x < 7'd22) && (d_p1b_y < 7'd22);
    wire br_1c  = in_x_1c && (d_p1c_x < 7'd20) && (d_p1c_y < 7'd20);

    wire w_in_cloud1 = c1_yband_p1 && (hit_1a || hit_1b || hit_1c || hit_1d);
    wire [7:0] w_cloud1_col = (br_1b || br_1c || c1_top_p1) ? 8'hFF :
                              c1_mid_p1                     ? 8'hDB : 8'hB6;

    wire in_x_2a = (dx_2a_p1[8:5] == 4'h0) || (dx_2a_p1[8:5] == 4'hF);
    wire in_x_2b = (dx_2b_p1[8:5] == 4'h0) || (dx_2b_p1[8:5] == 4'hF);
    wire in_x_2c = (dx_2c_p1[8:5] == 4'h0) || (dx_2c_p1[8:5] == 4'hF);

    wire [5:0] ax_2a = dx_2a_p1[8] ? (6'd0 - dx_2a_p1[5:0]) : dx_2a_p1[5:0];
    wire [5:0] ax_2b = dx_2b_p1[8] ? (6'd0 - dx_2b_p1[5:0]) : dx_2b_p1[5:0];
    wire [5:0] ax_2c = dx_2c_p1[8] ? (6'd0 - dx_2c_p1[5:0]) : dx_2c_p1[5:0];

    wire [6:0] d_p2a_x = {1'b0, ax_2a} + {2'b00, ay_2a_p1[5:1]};
    wire [6:0] d_p2a_y = {1'b0, ay_2a_p1} + {2'b00, ax_2a[5:1]};
    wire [6:0] d_p2b_x = {1'b0, ax_2b} + {2'b00, ay_2b_p1[5:1]};
    wire [6:0] d_p2b_y = {1'b0, ay_2b_p1} + {2'b00, ax_2b[5:1]};
    wire [6:0] d_p2c_x = {1'b0, ax_2c} + {2'b00, ay_2c_p1[5:1]};
    wire [6:0] d_p2c_y = {1'b0, ay_2c_p1} + {2'b00, ax_2c[5:1]};

    wire hit_2a = in_x_2a && (d_p2a_x < 7'd22) && (d_p2a_y < 7'd22);
    wire hit_2b = in_x_2b && (d_p2b_x < 7'd30) && (d_p2b_y < 7'd30);
    wire hit_2c = in_x_2c && (d_p2c_x < 7'd24) && (d_p2c_y < 7'd24);
    wire br_2b  = in_x_2b && (d_p2b_x < 7'd20) && (d_p2b_y < 7'd20);

    wire w_in_cloud2 = c2_yband_p1 && (hit_2a || hit_2b || hit_2c);
    wire [7:0] w_cloud2_col = (br_2b || c2_top_p1) ? 8'hFF :
                              c2_mid_p1            ? 8'hDB : 8'hB6;

    // --- Flock of 5 Birds Evaluation in Stage 2 (registered into _p2!) ---
    wire signed [12:0] b2_dx = b1_dx_p1 - 13'sd16;
    wire signed [12:0] b2_dy = b1_dy_p1 + 13'sd8;
    wire signed [12:0] b3_dx = b1_dx_p1 - 13'sd15;
    wire signed [12:0] b3_dy = b1_dy_p1 - 13'sd8;
    wire signed [12:0] b4_dx = b1_dx_p1 - 13'sd32;
    wire signed [12:0] b4_dy = b1_dy_p1 + 13'sd15;
    wire signed [12:0] b5_dx = b1_dx_p1 - 13'sd30;
    wire signed [12:0] b5_dy = b1_dy_p1 - 13'sd16;

    wire [3:0] u_b1x = b1_dx_p1[12] ? (-b1_dx_p1[3:0]) : b1_dx_p1[3:0];
    wire [3:0] u_b2x = b2_dx[12]    ? (-b2_dx[3:0])    : b2_dx[3:0];
    wire [3:0] u_b3x = b3_dx[12]    ? (-b3_dx[3:0])    : b3_dx[3:0];
    wire [3:0] u_b4x = b4_dx[12]    ? (-b4_dx[3:0])    : b4_dx[3:0];
    wire [3:0] u_b5x = b5_dx[12]    ? (-b5_dx[3:0])    : b5_dx[3:0];

    wire signed [12:0] wing1 = frame_cnt[3] ? $signed({10'd0, u_b1x[3:1]}) : -$signed({10'd0, u_b1x[3:1]});
    wire signed [12:0] wing2 = frame_cnt[3] ? $signed({10'd0, u_b2x[3:1]}) : -$signed({10'd0, u_b2x[3:1]});
    wire signed [12:0] wing3 = frame_cnt[3] ? $signed({10'd0, u_b3x[3:1]}) : -$signed({10'd0, u_b3x[3:1]});
    wire signed [12:0] wing4 = frame_cnt[3] ? $signed({10'd0, u_b4x[3:1]}) : -$signed({10'd0, u_b4x[3:1]});
    wire signed [12:0] wing5 = frame_cnt[3] ? $signed({10'd0, u_b5x[3:1]}) : -$signed({10'd0, u_b5x[3:1]});

    wire w_hit_bird = (yy_p1 < 10'd445) && (
                      (b1_dx_p1 >= -13'sd6 && b1_dx_p1 <= 13'sd6 && (b1_dy_p1 == wing1 || b1_dy_p1 == wing1 + 13'sd1)) ||
                      (b2_dx >= -13'sd6 && b2_dx <= 13'sd6 && (b2_dy == wing2 || b2_dy == wing2 + 13'sd1)) ||
                      (b3_dx >= -13'sd6 && b3_dx <= 13'sd6 && (b3_dy == wing3 || b3_dy == wing3 + 13'sd1)) ||
                      (b4_dx >= -13'sd6 && b4_dx <= 13'sd6 && (b4_dy == wing4 || b4_dy == wing4 + 13'sd1)) ||
                      (b5_dx >= -13'sd6 && b5_dx <= 13'sd6 && (b5_dy == wing5 || b5_dy == wing5 + 13'sd1)));

    // --- Ground, Meadow, Winding Brook & Ploughed Field Evaluation in Stage 2 ---
    wire [12:0] u_dx_brook = dx_brook_p1[12] ? (-dx_brook_p1) : dx_brook_p1;
    wire in_brook  = in_ground_p1 && (u_dx_brook <= brook_hw_p1);
    wire in_bank   = in_ground_p1 && !in_brook && (u_dx_brook <= brook_hw_p1 + 13'sd9);
    wire in_meadow = in_ground_p1 && (dx_brook_p1 < -brook_hw_p1);

    wire [9:0] grass_curve = yy_p1 + {3'd0, xx_p1[10:4]};
    wire       grass_band  = grass_curve[4];
    wire       grass_tuft  = (((xx_p1[5:0] * 6'd17) ^ (yy_p1[5:0] * 6'd29)) & 6'd15) == 6'd0;
    wire [7:0] meadow_base = (yy_p1 < 10'd525) ? (grass_band ? 8'h10 : 8'h0C) :
                             (yy_p1 < 10'd615) ? (grass_band ? 8'h0C : 8'h08) :
                                                 (grass_band ? 8'h08 : 8'h04);
    wire [7:0] fl_hash     = (xx_p1[7:0] * 8'd37) ^ (yy_p1[7:0] * 8'd53);
    wire       is_flower   = (fl_hash == 8'd1) && (yy_p1 < 10'd665);
    wire [7:0] fl_col      = (xx_p1[2:1] == 2'd0) ? 8'hFC : (xx_p1[2:1] == 2'd1) ? 8'hE0 : 8'hFF;
    wire [7:0] meadow_col  = is_flower ? fl_col : grass_tuft ? 8'h14 : meadow_base;

    wire       soil_crumb   = (((xx_p1[3:0] * 4'd13) ^ (yy_p1[3:0] * 4'd7)) & 4'd3) == 4'd0;
    wire [7:0] plough_col   = (furrow_pos_p1 < 4'd3)  ? 8'h20 :
                              (furrow_pos_p1 < 4'd8)  ? 8'h40 :
                              (furrow_pos_p1 < 4'd13) ? (soil_crumb ? 8'h44 : 8'h64) :
                                                        (dither_p1  ? 8'h88 : 8'h64);
    wire [7:0] farmland_col = (yy_p1 < 10'd474) ? (dither_p1 ? 8'h0C : 8'h10) : plough_col;

    wire       horiz_ripple = ((yy_p1[2:1] - frame_cnt[4:3] + xx_p1[3:2]) == 2'b00);
    wire       sun_glint    = (u_dx_brook <= (brook_hw_p1 >>> 1)) && horiz_ripple;
    wire [7:0] water_col    = sun_glint                             ? 8'hF8 :
                              (u_dx_brook >= brook_hw_p1 - 13'sd3)  ? 8'h05 :
                              horiz_ripple                          ? 8'h5B : 8'h17;
    wire [7:0] bank_col     = ((xx_p1[1:0] == 2'b00) && (yy_p1 > 10'd500)) ? 8'h10 :
                              (dither_p1 ? 8'h44 : 8'h08);

    wire [7:0] w_ground_col = in_brook  ? water_col :
                              in_bank   ? bank_col  :
                              in_meadow ? meadow_col : farmland_col;

    // --- Tractor Evaluation in Stage 2 (registered into _p2!) ---
    wire tr_box    = (tdx_p1 >= -13'sd34) && (tdx_p1 <= 13'sd22) && (tdy_p1 >= -13'sd26) && (tdy_p1 <= 13'sd16);
    wire tr_cab    = tr_box && (tdx_p1 >= -13'sd14) && (tdx_p1 <= 13'sd2)  && (tdy_p1 >= -13'sd22) && (tdy_p1 <= -13'sd6);
    wire tr_roof   = tr_box && (tdx_p1 >= -13'sd16) && (tdx_p1 <= 13'sd4)  && (tdy_p1 >= -13'sd24) && (tdy_p1 <= -13'sd22);
    wire tr_win    = tr_box && (tdx_p1 >= -13'sd11) && (tdx_p1 <= -13'sd2) && (tdy_p1 >= -13'sd19) && (tdy_p1 <= -13'sd10);
    wire tr_hood   = tr_box && (tdx_p1 >= -13'sd16) && (tdx_p1 <= 13'sd18) && (tdy_p1 >= -13'sd8)  && (tdy_p1 <= 13'sd4);
    wire tr_exh    = tr_box && (tdx_p1 >= 13'sd12)  && (tdx_p1 <= 13'sd14) && (tdy_p1 >= -13'sd18) && (tdy_p1 <= -13'sd8);
    wire tr_plough = tr_box && (tdx_p1 >= -13'sd32) && (tdx_p1 <= -13'sd20) && (tdy_p1 >= 13'sd4) && (tdy_p1 <= 13'sd12) &&
                     ((tdy_p1 <= 13'sd6) || (((tdx_p1[1:0] + tdy_p1[1:0]) & 2'd3) == 2'd0));
    wire tr_rw     = tr_box && (tdx_p1 >= -13'sd20) && (tdx_p1 <= -13'sd2) && (tdy_p1 >= -13'sd4)  && (tdy_p1 <= 13'sd14) &&
                     !((tdx_p1 == -13'sd20 || tdx_p1 == -13'sd2) && (tdy_p1 == -13'sd4 || tdy_p1 == 13'sd14));
    wire tr_rw_h   = tr_rw  && (tdx_p1 >= -13'sd14) && (tdx_p1 <= -13'sd8) && (tdy_p1 >= 13'sd2)   && (tdy_p1 <= 13'sd8);
    wire tr_fw     = tr_box && (tdx_p1 >= 13'sd8)   && (tdx_p1 <= 13'sd20) && (tdy_p1 >= 13'sd2)   && (tdy_p1 <= 13'sd14);
    wire tr_fw_h   = tr_fw  && (tdx_p1 >= 13'sd12)  && (tdx_p1 <= 13'sd16) && (tdy_p1 >= 13'sd6)   && (tdy_p1 <= 13'sd10);
    wire w_tr_hit  = tr_cab || tr_roof || tr_hood || tr_exh || tr_plough || tr_rw || tr_fw;
    wire [7:0] w_tr_col = (tr_rw_h || tr_fw_h) ? 8'hFC :
                          (tr_rw || tr_fw)     ? 8'h00 :
                          tr_plough            ? 8'h17 :
                          tr_roof              ? 8'hFF :
                          tr_win               ? 8'h5B :
                          tr_exh               ? 8'h24 : 8'hE0;

    reg [10:0]        xx_p2;
    reg [9:0]         yy_p2;
    reg               dither_p2, dither2_p2;
    reg [7:0]         sky_p2;

    reg               sun_box_p2;
    reg [16:0]        sun_d_sq_p2;

    reg               hub_box_p2;
    reg signed [8:0]  u_rot_p2, v_rot_p2;
    reg signed [7:0]  hub_dx_p2, hub_dy_p2;

    reg [9:0]         y_hill1_p2, y_hill2_p2;

    reg               in_cloud1_p2, in_cloud2_p2;
    reg [7:0]         cloud1_col_p2, cloud2_col_p2;
    reg               hit_bird_p2;
    reg               in_ground_p2;
    reg [7:0]         ground_col_p2;
    reg               tr_hit_p2;
    reg [7:0]         tr_col_p2;

    always @(posedge clk_pixel) begin
        xx_p2      <= xx_p1;
        yy_p2      <= yy_p1;
        dither_p2  <= dither_p1;
        dither2_p2 <= dither2_p1;
        sky_p2     <= sky_p1;

        sun_box_p2  <= sun_box_p1;
        sun_d_sq_p2 <= {1'b0, w_sun_dx_sq} + {1'b0, w_sun_dy_sq};

        hub_box_p2 <= hub_box_p1;
        u_rot_p2   <= w_u_rot[15:7];
        v_rot_p2   <= w_v_rot[15:7];
        hub_dx_p2  <= hub_dx_p1;
        hub_dy_p2  <= hub_dy_p1;

        y_hill1_p2 <= y_hill1_w;
        y_hill2_p2 <= y_hill2_w;

        in_cloud1_p2  <= w_in_cloud1;
        cloud1_col_p2 <= w_cloud1_col;
        in_cloud2_p2  <= w_in_cloud2;
        cloud2_col_p2 <= w_cloud2_col;

        hit_bird_p2   <= w_hit_bird;
        in_ground_p2  <= in_ground_p1;
        ground_col_p2 <= w_ground_col;
        tr_hit_p2     <= w_tr_hit;
        tr_col_p2     <= w_tr_col;
    end

    // ========================================================================
    // STAGE 3: Scene Layer Compositing (Back-to-Front Painter's Algorithm)
    // ========================================================================
    wire [10:0] x3 = xx_p2;
    wire [9:0]  y3 = yy_p2;
    wire signed [12:0] sx3 = $signed({2'b00, x3});
    wire signed [12:0] sy3 = $signed({3'b000, y3});

    // --- Layer A: Sun & Solar Halo (Smooth 3D sphere, zero horizontal bars!) ---
    wire in_halo2 = sun_box_p2 && (sun_d_sq_p2 < 17'd16384);
    wire in_halo1 = sun_box_p2 && (sun_d_sq_p2 < 17'd7744);
    wire in_sun   = sun_box_p2 && (sun_d_sq_p2 < 17'd3364);
    wire [7:0] sun_disk_col = (sun_d_sq_p2 < 17'd550)  ? 8'hFF :
                              (sun_d_sq_p2 < 17'd1350) ? 8'hFE :
                              (sun_d_sq_p2 < 17'd2250) ? 8'hFC :
                              (sun_d_sq_p2 < 17'd2950) ? 8'hF8 : 8'hF4;

    // --- Layer C: Distant Forest Ridge, Valley Mist & Midground Hills ---
    wire [2:0] tree_jag = (x3[2:0] * 3'd5) ^ x3[4:2];
    wire       in_forest = (y3 >= (y_hill1_p2 - {7'd0, tree_jag})) && (y3 < 10'd438);
    wire [7:0] forest_col = (y3 < y_hill1_p2 + 10'd6) ? 8'h25 :
                            (y3 < 10'd414)            ? 8'h05 : 8'h09;
    wire       in_mist    = (y3 >= 10'd416) && (y3 < 10'd434) && dither_p2;

    wire       in_hill2   = (y3 >= y_hill2_p2) && (y3 < 10'd468);
    wire [7:0] hill2_col  = (x3 < 11'd760) ?
                            ((y3 < y_hill2_p2 + 10'd12) ? 8'h10 : 8'h0C) :
                            ((y3 < y_hill2_p2 + 10'd12) ? 8'hB4 : 8'h90);
    wire [4:0] bush_x     = x3[4:0];
    wire [2:0] bush_h     = (bush_x >= 5'd6 && bush_x <= 5'd26) ? 3'd6 : 3'd2;
    wire       in_hedge   = (y3 >= (y_hill2_p2 - {7'd0, bush_h})) && (y3 < y_hill2_p2 + 10'd3) && (x3[6:5] != 2'b01);
    wire [7:0] hedge_col  = bush_x[4] ? 8'h08 : 8'h0C;

    // --- Layer E: Oak Tree, Harvest Silo & Twentse Saksische Boerderij (SINGLE CRISP ROOF!) ---
    wire       in_trunk   = (x3 >= 11'd558) && (x3 <= 11'd570) && (y3 >= 10'd420) && (y3 <= 10'd468);
    wire [7:0] trunk_col  = (x3 < 11'd564) ? 8'h40 : 8'h20;
    wire signed [12:0] oak_dx = sx3 - 13'sd564;
    wire signed [12:0] oak_dy = sy3 - 13'sd404;
    wire [12:0] u_oak_dx  = oak_dx[12] ? (-oak_dx) : oak_dx;
    wire [12:0] u_oak_dy  = oak_dy[12] ? (-oak_dy) : oak_dy;
    wire       in_oak     = (y3 >= 10'd374) && (y3 <= 10'd434) && (x3 >= 11'd524) && (x3 <= 11'd602) &&
                            ((u_oak_dx + (u_oak_dy <<< 1)) < 13'd52);
    wire [7:0] oak_col    = (oak_dy < -13'sd10) ? 8'h14 :
                            (oak_dx > 13'sd8)   ? 8'h50 :
                            (oak_dy < 13'sd8)   ? 8'h0C : 8'h04;

    // Silver Harvest Silo at cx=604..640, cy=362..464
    wire       in_silo    = (x3 >= 11'd604) && (x3 <= 11'd640) && (y3 >= 10'd366) && (y3 <= 10'd464) &&
                            !((y3 < 10'd376) && ((x3 < 11'd610) || (x3 > 11'd634)));
    wire [7:0] silo_col   = (y3[3:0] == 4'd0) ? 8'h49 :
                            (x3 < 11'd615)    ? 8'h49 :
                            (x3 < 11'd624)    ? 8'h92 :
                            (x3 < 11'd633)    ? 8'hDB : 8'hFF;

    // Farmhouse Walls (cx=636..820, cy=422..468)
    wire       in_walls   = (x3 >= 11'd636) && (x3 <= 11'd820) && (y3 >= 10'd422) && (y3 <= 10'd468);
    wire       is_beam    = (x3 == 11'd636) || (x3 == 11'd680) || (x3 == 11'd724) || (x3 == 11'd772) || (x3 == 11'd820) ||
                            (y3 == 10'd422) || (y3 == 10'd445) || (y3 == 10'd468);
    wire       in_door    = (x3 >= 11'd650) && (x3 <= 11'd692) && (y3 >= 10'd432) && (y3 <= 10'd468);
    wire       door_trim  = (x3 == 11'd650) || (x3 == 11'd692) || (y3 == 10'd432) || (x3 == 11'd671);
    wire       in_win1    = (x3 >= 11'd702) && (x3 <= 11'd716) && (y3 >= 10'd432) && (y3 <= 10'd452);
    wire       in_win2    = (x3 >= 11'd738) && (x3 <= 11'd758) && (y3 >= 10'd432) && (y3 <= 10'd452);
    wire       in_win3    = (x3 >= 11'd778) && (x3 <= 11'd798) && (y3 >= 10'd432) && (y3 <= 10'd452);
    wire       in_win     = in_win1 || in_win2 || in_win3;
    wire       win_frame  = (y3 == 10'd432) || (y3 == 10'd442) || (y3 == 10'd452) ||
                            (x3 == 11'd702) || (x3 == 11'd709) || (x3 == 11'd716) ||
                            (x3 == 11'd738) || (x3 == 11'd748) || (x3 == 11'd758) ||
                            (x3 == 11'd778) || (x3 == 11'd788) || (x3 == 11'd798);
    wire [7:0] wall_all_c = in_door   ? (door_trim ? 8'hFF : 8'h08) :
                            in_win    ? (win_frame ? 8'hFF : 8'hFC) :
                            is_beam   ? 8'h40 :
                            (x3 < 11'd724) ? 8'h80 : 8'hA4;

    // Single Crisp Gable & Red Tiled Roof (cy=364..422) — Overflow-free shift math!
    wire [9:0]  ry_roof    = (y3 >= 10'd364) ? (y3 - 10'd364) : 10'd0;
    wire [9:0]  half_gable = ry_roof - (ry_roof >> 3);
    wire [10:0] u_gable_dx = (x3 >= 11'd680) ? (x3 - 11'd680) : (11'd680 - x3);
    wire        in_gable   = (y3 >= 10'd364) && (y3 <= 10'd422) && (u_gable_dx <= {1'b0, half_gable});
    wire        in_sroof   = (y3 >= 10'd364) && (y3 <= 10'd422) && (x3 > (11'd680 + {1'b0, half_gable})) &&
                             (x3 <= (11'd828 - {2'b00, (10'd422 - y3) >> 1}));
    wire        in_uilen   = (y3 >= 10'd364) && (y3 <= 10'd378) && (u_gable_dx <= 11'd3);
    wire        in_windv   = in_gable && (half_gable >= 10'd2) && (u_gable_dx >= ({1'b0, half_gable} - 11'd2));
    wire        tile_pat   = ((x3[2:1] + y3[1:0]) == 2'b00);
    wire [7:0]  roof_col   = (in_uilen || in_windv) ? 8'hFF :
                             in_gable               ? ((y3 > 10'd414) ? 8'hA0 : 8'h64) :
                                                      (tile_pat ? 8'hA0 : 8'hE4);

    // Chimney & Rising Animated Smoke
    wire        in_chimney = (x3 >= 11'd792) && (x3 <= 11'd804) && (y3 >= 10'd350) && (y3 <= 10'd370);
    wire [9:0]  smk_y0     = 10'd340 - {6'd0, frame_cnt[5:2]};
    wire [10:0] smk_x0     = 11'd798 + {8'd0, frame_cnt[5:3]};
    wire        in_smoke   = dither_p2 && (
                             ((x3 >= smk_x0 - 11'd7) && (x3 <= smk_x0 + 11'd7) && (y3 >= smk_y0 - 10'd6) && (y3 <= smk_y0 + 10'd6)) ||
                             ((x3 >= smk_x0 + 11'd4) && (x3 <= smk_x0 + 11'd20) && (y3 >= smk_y0 - 10'd24) && (y3 <= smk_y0 - 10'd10)));

    // --- Layer F: Dutch Stellingmolen (Tower + 60 FPS Rotating Lattice Sails) ---
    wire [10:0] u_mill_dx = (x3 >= 11'd1090) ? (x3 - 11'd1090) : (11'd1090 - x3);
    wire [10:0] w_m_base  = 11'd22 + {3'd0, (y3 - 10'd405) >> 2};
    wire        in_m_base = (y3 >= 10'd405) && (y3 <= 10'd468) && (u_mill_dx <= w_m_base);
    wire [10:0] w_m_top   = 11'd14 + {4'd0, (y3 - 10'd310) >> 3};
    wire        in_m_top  = (y3 >= 10'd310) && (y3 < 10'd405) && (u_mill_dx <= w_m_top);
    wire        in_m_cap  = (y3 >= 10'd292) && (y3 <= 10'd312) && (u_mill_dx <= 11'd16) &&
                            ((u_mill_dx + (10'd312 - y3)) <= 11'd24);
    wire        in_m_win  = (u_mill_dx <= 11'd4) && (((y3 >= 10'd340) && (y3 <= 10'd352)) || ((y3 >= 10'd372) && (y3 <= 10'd384)));
    wire        in_balc   = (y3 >= 10'd398) && (y3 <= 10'd406) && (u_mill_dx <= 11'd44) &&
                            ((x3[1:0] == 2'b00) || (y3 == 10'd398) || (y3 == 10'd405));
    wire [7:0]  mill_col  = in_balc  ? 8'hFC :
                            in_m_win ? 8'hFF :
                            in_m_cap ? ((x3 < 11'd1090) ? 8'h49 : 8'h24) :
                            in_m_top ? ((x3 < 11'd1086) ? 8'h64 : (x3 < 11'd1096) ? 8'h44 : 8'h20) :
                                       ((x3 < 11'd1084) ? 8'hA4 : (x3 < 11'd1098) ? 8'h80 : 8'h40);

    // Rotating 4 Windmill Sails (from Stage 2 u_rot_p2, v_rot_p2)
    wire [8:0] abs_u = u_rot_p2[8] ? (-u_rot_p2) : u_rot_p2;
    wire [8:0] abs_v = v_rot_p2[8] ? (-v_rot_p2) : v_rot_p2;
    wire on_beam_u = hub_box_p2 && (abs_u <= 9'd95) && (abs_v <= 9'd1);
    wire on_beam_v = hub_box_p2 && (abs_v <= 9'd95) && (abs_u <= 9'd1);
    wire on_sail_u = hub_box_p2 && (
                     ((u_rot_p2 >= 9'sd12)  && (u_rot_p2 <= 9'sd93)  && (v_rot_p2 >= 9'sd2)  && (v_rot_p2 <= 9'sd11)) ||
                     ((u_rot_p2 <= -9'sd12) && (u_rot_p2 >= -9'sd93) && (v_rot_p2 <= -9'sd2) && (v_rot_p2 >= -9'sd11)));
    wire on_sail_v = hub_box_p2 && (
                     ((v_rot_p2 >= 9'sd12)  && (v_rot_p2 <= 9'sd93)  && (u_rot_p2 <= -9'sd2) && (u_rot_p2 >= -9'sd11)) ||
                     ((v_rot_p2 <= -9'sd12) && (v_rot_p2 >= -9'sd93) && (u_rot_p2 >= 9'sd2)  && (u_rot_p2 <= 9'sd11)));
    wire grid_u    = (abs_u[2:0] == 3'd0) || (abs_v == 9'd11) || (abs_v == 9'd6);
    wire grid_v    = (abs_v[2:0] == 3'd0) || (abs_u == 9'd11) || (abs_u == 9'd6);
    wire in_hub    = hub_box_p2 && (hub_dx_p2 >= -8'sd4) && (hub_dx_p2 <= 8'sd4) &&
                     (hub_dy_p2 >= -8'sd4) && (hub_dy_p2 <= 8'sd4);

    // --- Layer G: 3 Friesian Cows & Wooden Fence ---
    wire signed [12:0] graze_bob = frame_cnt[6] ? 13'sd4 : 13'sd2;

    wire signed [12:0] c1x = (sx3 - 13'sd310) >>> 1;
    wire signed [12:0] c1y = (sy3 - 13'sd545) >>> 1;
    wire signed [12:0] c2x = (13'sd445 - sx3) >>> 1;
    wire signed [12:0] c2y = (sy3 - 13'sd595) >>> 1;
    wire signed [12:0] c3x = (sx3 - 13'sd190) >>> 1;
    wire signed [12:0] c3y = (sy3 - 13'sd625) >>> 1;

    wire in_cow_box1 = (c1x >= -13'sd16) && (c1x <= 13'sd22) && (c1y >= -13'sd10) && (c1y <= 13'sd15);
    wire in_cow_box2 = (c2x >= -13'sd16) && (c2x <= 13'sd22) && (c2y >= -13'sd10) && (c2y <= 13'sd15);
    wire in_cow_box3 = (c3x >= -13'sd16) && (c3x <= 13'sd22) && (c3y >= -13'sd10) && (c3y <= 13'sd15);

    wire signed [12:0] cx_act = in_cow_box1 ? c1x : in_cow_box2 ? c2x : c3x;
    wire signed [12:0] cy_act = in_cow_box1 ? c1y : in_cow_box2 ? c2y : c3y;
    wire signed [12:0] cy_hd  = in_cow_box2 ? -13'sd4 : graze_bob;

    wire cow_any_box = in_cow_box1 || in_cow_box2 || in_cow_box3;
    wire cow_shadow  = cow_any_box && (cx_act >= -13'sd14) && (cx_act <= 13'sd15) && (cy_act >= 13'sd12) && (cy_act <= 13'sd14);
    wire cow_torso   = cow_any_box && (cx_act >= -13'sd13) && (cx_act <= 13'sd12) && (cy_act >= -13'sd6) && (cy_act <= 13'sd5) &&
                       !((cx_act < -13'sd10 || cx_act > 13'sd9) && (cy_act < -13'sd4 || cy_act > 13'sd3));
    wire cow_udder   = cow_any_box && (cx_act >= -13'sd8) && (cx_act <= -13'sd3) && (cy_act >= 13'sd5) && (cy_act <= 13'sd7);
    wire cow_legs    = cow_any_box && (cy_act >= 13'sd5) && (cy_act <= 13'sd13) && (
                       (cx_act >= -13'sd12 && cx_act <= -13'sd10) || (cx_act >= -13'sd7 && cx_act <= -13'sd5) ||
                       (cx_act >= 13'sd5   && cx_act <= 13'sd7)   || (cx_act >= 13'sd9  && cx_act <= 13'sd11));
    wire cow_head    = cow_any_box && (cx_act >= 13'sd11) && (cx_act <= 13'sd20) &&
                       (cy_act >= cy_hd - 13'sd4) && (cy_act <= cy_hd + 13'sd3);
    wire cow_snout   = cow_head && (cx_act >= 13'sd18) && (cy_act >= cy_hd);
    wire cow_eye     = cow_head && (cx_act == 13'sd16) && (cy_act == cy_hd - 13'sd2);
    wire cow_black   = ((cx_act >= -13'sd10 && cx_act <= -13'sd3 && cy_act <= 13'sd2) ||
                        (cx_act >= 13'sd1   && cx_act <= 13'sd7  && cy_act >= -13'sd5 && cy_act <= 13'sd1) ||
                        (cx_act >= 13'sd11));
    wire [7:0] cow_col = cow_snout ? 8'hEC :
                         cow_eye   ? 8'hFF :
                         (cow_torso || cow_head) ? (cow_black ? 8'h00 : (cy_act > 13'sd2 ? 8'hDB : 8'hFF)) :
                         cow_udder ? 8'hEC :
                         cow_legs  ? ((cy_act >= 13'sd11) ? 8'h00 : 8'hFF) : 8'h04;

    // Wooden Fence along foreground meadow (x < 430, y = 668..714)
    wire in_post = (x3 < 11'd430) && (y3 >= 10'd668) && (y3 <= 10'd714) && (x3[5:0] >= 6'd28) && (x3[5:0] <= 6'd34);
    wire in_rail = (x3 < 11'd430) && (((y3 >= 10'd678) && (y3 <= 10'd682)) || ((y3 >= 10'd696) && (y3 <= 10'd700)));
    wire [7:0] fence_col = in_post ? ((x3[5:0] < 6'd31) ? 8'h88 : 8'h40) :
                                     (((y3 == 10'd678) || (y3 == 10'd696)) ? 8'h88 : 8'h64);

    // Master Priority Compositor
    reg [7:0] comp_col;
    always @(*) begin
        comp_col = sky_p2;
        if (in_halo2 && dither2_p2)               comp_col = 8'hF4;
        if (in_halo1)                             comp_col = dither_p2 ? 8'hF8 : 8'hF4;
        if (in_sun)                               comp_col = sun_disk_col;
        if (in_cloud1_p2)                         comp_col = cloud1_col_p2;
        if (in_cloud2_p2)                         comp_col = cloud2_col_p2;
        if (in_forest)                            comp_col = forest_col;
        if (in_mist)                              comp_col = 8'h4E;
        if (in_hill2)                             comp_col = hill2_col;
        if (in_hedge)                             comp_col = hedge_col;
        if (hit_bird_p2)                          comp_col = 8'h20;
        if (in_ground_p2)                         comp_col = ground_col_p2;
        if (in_trunk)                             comp_col = trunk_col;
        if (in_oak)                               comp_col = oak_col;
        if (in_silo)                              comp_col = silo_col;
        if (in_walls)                             comp_col = wall_all_c;
        if (in_chimney)                           comp_col = 8'h80;
        if (in_gable || in_sroof)                 comp_col = roof_col;
        if (in_smoke)                             comp_col = 8'hB6;
        if (in_m_base || in_m_top || in_m_cap || in_balc) comp_col = mill_col;
        if (on_sail_u)                            comp_col = grid_u ? 8'hF8 : 8'hFF;
        if (on_sail_v)                            comp_col = grid_v ? 8'hF8 : 8'hFF;
        if (on_beam_u || on_beam_v)               comp_col = 8'hFC;
        if (in_hub)                               comp_col = 8'hE0;
        if (cow_torso || cow_head || cow_udder || cow_legs || cow_shadow) comp_col = cow_col;
        if (tr_hit_p2)                            comp_col = tr_col_p2;
        if (in_post || in_rail)                   comp_col = fence_col;
    end

    always @(posedge clk_pixel) begin
        farm_color <= comp_col;
    end

endmodule
