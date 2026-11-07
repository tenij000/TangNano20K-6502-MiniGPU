`timescale 1ns / 1ps

// ============================================================================
// Hardware Procedural Deep-Space Planets & 3-Layer Parallax Starfield Engine
// Tang Nano 20K (GW2AR-18C) | 74.25 MHz Pixel Clock | 0 BSRAMs!
//
// Features:
//   - Subtle deep-indigo cosmic nebula band (ultra-high contrast for BASIC text)
//   - 3 parallax layers of smoothly drifting & twinkling stars @ 60 FPS
//   - Native 1280x720 3D-shaded planets (curved spherical highlight contours):
//       1) Giant Ringed Gas Giant (Cassini gap, 3D curved bands & ring shadow)
//       2) Crimson Mars World (3D spherical shading, zero flat/black cutoff,
//          curved north polar ice cap & Martian maria)
//       3) Silky-smooth 60 FPS 3D-orbiting silver Moon around Mars
//          (1024-step quarter-wave sub-pixel orbit @ 60 Hz, 0.5-px precision!)
//       4) Turquoise/violet crescent exoplanet & golden dwarf planet
// ============================================================================

module space_planets_bg (
    input  wire        clk_pixel,   // 74.25 MHz HDMI pixel clock
    input  wire        rst_n,
    input  wire [10:0] cx,          // 0..1279 active
    input  wire [9:0]  cy,          // 0..719 active
    output reg  [7:0]  space_color  // RGB332 output (aligned with scanout)
);

    // ========================================================================
    // 1. 60 Hz Hardware Frame Counter & 1024-Step Sub-Pixel 3D Moon Orbit
    // ========================================================================
    reg [15:0] frame_cnt = 16'd115;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            frame_cnt <= 16'd115;
        end else if (cx == 11'd0 && cy == 10'd720) begin
            frame_cnt <= frame_cnt + 16'd1;
        end
    end

    // Updated EVERY single 60 Hz frame (1024 steps = 17.07s full 3D orbit, 0.5-px precision)
    wire [9:0] orb_phase = frame_cnt[9:0];
    wire [1:0] orb_quad  = orb_phase[9:8];
    wire [7:0] orb_idx   = orb_phase[7:0];
    wire [7:0] idx_a     = orb_quad[0] ? orb_idx  : ~orb_idx;
    wire [7:0] idx_b     = orb_quad[0] ? ~orb_idx : orb_idx;

    reg [7:0] lut_a_mag; // 0..168 half-pixels (= 0..84.0 px in 1280x720)
    reg [5:0] lut_b_mag; // 0..52  half-pixels (= 0..26.0 px in 1280x720)

    always @(*) begin
        case (idx_a)
            8'd0: lut_a_mag = 8'd1; 8'd1: lut_a_mag = 8'd2; 8'd2: lut_a_mag = 8'd3; 8'd3: lut_a_mag = 8'd4;
            8'd4: lut_a_mag = 8'd5; 8'd5: lut_a_mag = 8'd6; 8'd6: lut_a_mag = 8'd7; 8'd7: lut_a_mag = 8'd8;
            8'd8: lut_a_mag = 8'd9; 8'd9: lut_a_mag = 8'd10; 8'd10: lut_a_mag = 8'd11; 8'd11: lut_a_mag = 8'd12;
            8'd12: lut_a_mag = 8'd13; 8'd13: lut_a_mag = 8'd14; 8'd14: lut_a_mag = 8'd15; 8'd15: lut_a_mag = 8'd16;
            8'd16: lut_a_mag = 8'd17; 8'd17: lut_a_mag = 8'd18; 8'd18: lut_a_mag = 8'd19; 8'd19: lut_a_mag = 8'd20;
            8'd20: lut_a_mag = 8'd21; 8'd21: lut_a_mag = 8'd22; 8'd22: lut_a_mag = 8'd23; 8'd23: lut_a_mag = 8'd24;
            8'd24: lut_a_mag = 8'd25; 8'd25: lut_a_mag = 8'd26; 8'd26: lut_a_mag = 8'd27; 8'd27: lut_a_mag = 8'd28;
            8'd28: lut_a_mag = 8'd29; 8'd29: lut_a_mag = 8'd30; 8'd30: lut_a_mag = 8'd31; 8'd31: lut_a_mag = 8'd32;
            8'd32: lut_a_mag = 8'd33; 8'd33: lut_a_mag = 8'd34; 8'd34: lut_a_mag = 8'd35; 8'd35: lut_a_mag = 8'd36;
            8'd36: lut_a_mag = 8'd37; 8'd37: lut_a_mag = 8'd38; 8'd38: lut_a_mag = 8'd39; 8'd39: lut_a_mag = 8'd40;
            8'd40: lut_a_mag = 8'd41; 8'd41: lut_a_mag = 8'd42; 8'd42: lut_a_mag = 8'd43; 8'd43: lut_a_mag = 8'd44;
            8'd44: lut_a_mag = 8'd45; 8'd45: lut_a_mag = 8'd46; 8'd46: lut_a_mag = 8'd47; 8'd47: lut_a_mag = 8'd48;
            8'd48: lut_a_mag = 8'd49; 8'd49: lut_a_mag = 8'd50; 8'd50: lut_a_mag = 8'd51; 8'd51: lut_a_mag = 8'd52;
            8'd52: lut_a_mag = 8'd53; 8'd53: lut_a_mag = 8'd54; 8'd54: lut_a_mag = 8'd55; 8'd55: lut_a_mag = 8'd56;
            8'd56: lut_a_mag = 8'd57; 8'd57: lut_a_mag = 8'd58; 8'd58: lut_a_mag = 8'd59; 8'd59: lut_a_mag = 8'd60;
            8'd60: lut_a_mag = 8'd61; 8'd61: lut_a_mag = 8'd62; 8'd62: lut_a_mag = 8'd63; 8'd63: lut_a_mag = 8'd64;
            8'd64: lut_a_mag = 8'd65; 8'd65: lut_a_mag = 8'd66; 8'd66: lut_a_mag = 8'd67; 8'd67: lut_a_mag = 8'd68;
            8'd68: lut_a_mag = 8'd69; 8'd69: lut_a_mag = 8'd69; 8'd70: lut_a_mag = 8'd70; 8'd71: lut_a_mag = 8'd71;
            8'd72: lut_a_mag = 8'd72; 8'd73: lut_a_mag = 8'd73; 8'd74: lut_a_mag = 8'd74; 8'd75: lut_a_mag = 8'd75;
            8'd76: lut_a_mag = 8'd76; 8'd77: lut_a_mag = 8'd77; 8'd78: lut_a_mag = 8'd78; 8'd79: lut_a_mag = 8'd79;
            8'd80: lut_a_mag = 8'd80; 8'd81: lut_a_mag = 8'd81; 8'd82: lut_a_mag = 8'd81; 8'd83: lut_a_mag = 8'd82;
            8'd84: lut_a_mag = 8'd83; 8'd85: lut_a_mag = 8'd84; 8'd86: lut_a_mag = 8'd85; 8'd87: lut_a_mag = 8'd86;
            8'd88: lut_a_mag = 8'd87; 8'd89: lut_a_mag = 8'd88; 8'd90: lut_a_mag = 8'd89; 8'd91: lut_a_mag = 8'd89;
            8'd92: lut_a_mag = 8'd90; 8'd93: lut_a_mag = 8'd91; 8'd94: lut_a_mag = 8'd92; 8'd95: lut_a_mag = 8'd93;
            8'd96: lut_a_mag = 8'd94; 8'd97: lut_a_mag = 8'd95; 8'd98: lut_a_mag = 8'd95; 8'd99: lut_a_mag = 8'd96;
            8'd100: lut_a_mag = 8'd97; 8'd101: lut_a_mag = 8'd98; 8'd102: lut_a_mag = 8'd99; 8'd103: lut_a_mag = 8'd100;
            8'd104: lut_a_mag = 8'd100; 8'd105: lut_a_mag = 8'd101; 8'd106: lut_a_mag = 8'd102; 8'd107: lut_a_mag = 8'd103;
            8'd108: lut_a_mag = 8'd104; 8'd109: lut_a_mag = 8'd105; 8'd110: lut_a_mag = 8'd105; 8'd111: lut_a_mag = 8'd106;
            8'd112: lut_a_mag = 8'd107; 8'd113: lut_a_mag = 8'd108; 8'd114: lut_a_mag = 8'd109; 8'd115: lut_a_mag = 8'd109;
            8'd116: lut_a_mag = 8'd110; 8'd117: lut_a_mag = 8'd111; 8'd118: lut_a_mag = 8'd112; 8'd119: lut_a_mag = 8'd112;
            8'd120: lut_a_mag = 8'd113; 8'd121: lut_a_mag = 8'd114; 8'd122: lut_a_mag = 8'd115; 8'd123: lut_a_mag = 8'd115;
            8'd124: lut_a_mag = 8'd116; 8'd125: lut_a_mag = 8'd117; 8'd126: lut_a_mag = 8'd118; 8'd127: lut_a_mag = 8'd118;
            8'd128: lut_a_mag = 8'd119; 8'd129: lut_a_mag = 8'd120; 8'd130: lut_a_mag = 8'd121; 8'd131: lut_a_mag = 8'd121;
            8'd132: lut_a_mag = 8'd122; 8'd133: lut_a_mag = 8'd123; 8'd134: lut_a_mag = 8'd123; 8'd135: lut_a_mag = 8'd124;
            8'd136: lut_a_mag = 8'd125; 8'd137: lut_a_mag = 8'd126; 8'd138: lut_a_mag = 8'd126; 8'd139: lut_a_mag = 8'd127;
            8'd140: lut_a_mag = 8'd128; 8'd141: lut_a_mag = 8'd128; 8'd142: lut_a_mag = 8'd129; 8'd143: lut_a_mag = 8'd130;
            8'd144: lut_a_mag = 8'd130; 8'd145: lut_a_mag = 8'd131; 8'd146: lut_a_mag = 8'd131; 8'd147: lut_a_mag = 8'd132;
            8'd148: lut_a_mag = 8'd133; 8'd149: lut_a_mag = 8'd133; 8'd150: lut_a_mag = 8'd134; 8'd151: lut_a_mag = 8'd135;
            8'd152: lut_a_mag = 8'd135; 8'd153: lut_a_mag = 8'd136; 8'd154: lut_a_mag = 8'd136; 8'd155: lut_a_mag = 8'd137;
            8'd156: lut_a_mag = 8'd138; 8'd157: lut_a_mag = 8'd138; 8'd158: lut_a_mag = 8'd139; 8'd159: lut_a_mag = 8'd139;
            8'd160: lut_a_mag = 8'd140; 8'd161: lut_a_mag = 8'd141; 8'd162: lut_a_mag = 8'd141; 8'd163: lut_a_mag = 8'd142;
            8'd164: lut_a_mag = 8'd142; 8'd165: lut_a_mag = 8'd143; 8'd166: lut_a_mag = 8'd143; 8'd167: lut_a_mag = 8'd144;
            8'd168: lut_a_mag = 8'd144; 8'd169: lut_a_mag = 8'd145; 8'd170: lut_a_mag = 8'd145; 8'd171: lut_a_mag = 8'd146;
            8'd172: lut_a_mag = 8'd146; 8'd173: lut_a_mag = 8'd147; 8'd174: lut_a_mag = 8'd147; 8'd175: lut_a_mag = 8'd148;
            8'd176: lut_a_mag = 8'd148; 8'd177: lut_a_mag = 8'd149; 8'd178: lut_a_mag = 8'd149; 8'd179: lut_a_mag = 8'd150;
            8'd180: lut_a_mag = 8'd150; 8'd181: lut_a_mag = 8'd151; 8'd182: lut_a_mag = 8'd151; 8'd183: lut_a_mag = 8'd152;
            8'd184: lut_a_mag = 8'd152; 8'd185: lut_a_mag = 8'd153; 8'd186: lut_a_mag = 8'd153; 8'd187: lut_a_mag = 8'd153;
            8'd188: lut_a_mag = 8'd154; 8'd189: lut_a_mag = 8'd154; 8'd190: lut_a_mag = 8'd155; 8'd191: lut_a_mag = 8'd155;
            8'd192: lut_a_mag = 8'd155; 8'd193: lut_a_mag = 8'd156; 8'd194: lut_a_mag = 8'd156; 8'd195: lut_a_mag = 8'd157;
            8'd196: lut_a_mag = 8'd157; 8'd197: lut_a_mag = 8'd157; 8'd198: lut_a_mag = 8'd158; 8'd199: lut_a_mag = 8'd158;
            8'd200: lut_a_mag = 8'd158; 8'd201: lut_a_mag = 8'd159; 8'd202: lut_a_mag = 8'd159; 8'd203: lut_a_mag = 8'd159;
            8'd204: lut_a_mag = 8'd160; 8'd205: lut_a_mag = 8'd160; 8'd206: lut_a_mag = 8'd160; 8'd207: lut_a_mag = 8'd161;
            8'd208: lut_a_mag = 8'd161; 8'd209: lut_a_mag = 8'd161; 8'd210: lut_a_mag = 8'd161; 8'd211: lut_a_mag = 8'd162;
            8'd212: lut_a_mag = 8'd162; 8'd213: lut_a_mag = 8'd162; 8'd214: lut_a_mag = 8'd163; 8'd215: lut_a_mag = 8'd163;
            8'd216: lut_a_mag = 8'd163; 8'd217: lut_a_mag = 8'd163; 8'd218: lut_a_mag = 8'd164; 8'd219: lut_a_mag = 8'd164;
            8'd220: lut_a_mag = 8'd164; 8'd221: lut_a_mag = 8'd164; 8'd222: lut_a_mag = 8'd164; 8'd223: lut_a_mag = 8'd165;
            8'd224: lut_a_mag = 8'd165; 8'd225: lut_a_mag = 8'd165; 8'd226: lut_a_mag = 8'd165; 8'd227: lut_a_mag = 8'd165;
            8'd228: lut_a_mag = 8'd166; 8'd229: lut_a_mag = 8'd166; 8'd230: lut_a_mag = 8'd166; 8'd231: lut_a_mag = 8'd166;
            8'd232: lut_a_mag = 8'd166; 8'd233: lut_a_mag = 8'd166; 8'd234: lut_a_mag = 8'd167; 8'd235: lut_a_mag = 8'd167;
            8'd236: lut_a_mag = 8'd167; 8'd237: lut_a_mag = 8'd167; 8'd238: lut_a_mag = 8'd167; 8'd239: lut_a_mag = 8'd167;
            8'd240: lut_a_mag = 8'd167; 8'd241: lut_a_mag = 8'd167; 8'd242: lut_a_mag = 8'd167; 8'd243: lut_a_mag = 8'd168;
            8'd244: lut_a_mag = 8'd168; 8'd245: lut_a_mag = 8'd168; 8'd246: lut_a_mag = 8'd168; 8'd247: lut_a_mag = 8'd168;
            8'd248: lut_a_mag = 8'd168; 8'd249: lut_a_mag = 8'd168; 8'd250: lut_a_mag = 8'd168; 8'd251: lut_a_mag = 8'd168;
            8'd252: lut_a_mag = 8'd168; 8'd253: lut_a_mag = 8'd168; 8'd254: lut_a_mag = 8'd168; 8'd255: lut_a_mag = 8'd168;
        endcase
    end

    always @(*) begin
        case (idx_b)
            8'd0: lut_b_mag = 6'd0; 8'd1: lut_b_mag = 6'd0; 8'd2: lut_b_mag = 6'd1; 8'd3: lut_b_mag = 6'd1;
            8'd4: lut_b_mag = 6'd1; 8'd5: lut_b_mag = 6'd2; 8'd6: lut_b_mag = 6'd2; 8'd7: lut_b_mag = 6'd2;
            8'd8: lut_b_mag = 6'd3; 8'd9: lut_b_mag = 6'd3; 8'd10: lut_b_mag = 6'd3; 8'd11: lut_b_mag = 6'd4;
            8'd12: lut_b_mag = 6'd4; 8'd13: lut_b_mag = 6'd4; 8'd14: lut_b_mag = 6'd5; 8'd15: lut_b_mag = 6'd5;
            8'd16: lut_b_mag = 6'd5; 8'd17: lut_b_mag = 6'd6; 8'd18: lut_b_mag = 6'd6; 8'd19: lut_b_mag = 6'd6;
            8'd20: lut_b_mag = 6'd7; 8'd21: lut_b_mag = 6'd7; 8'd22: lut_b_mag = 6'd7; 8'd23: lut_b_mag = 6'd7;
            8'd24: lut_b_mag = 6'd8; 8'd25: lut_b_mag = 6'd8; 8'd26: lut_b_mag = 6'd8; 8'd27: lut_b_mag = 6'd9;
            8'd28: lut_b_mag = 6'd9; 8'd29: lut_b_mag = 6'd9; 8'd30: lut_b_mag = 6'd10; 8'd31: lut_b_mag = 6'd10;
            8'd32: lut_b_mag = 6'd10; 8'd33: lut_b_mag = 6'd11; 8'd34: lut_b_mag = 6'd11; 8'd35: lut_b_mag = 6'd11;
            8'd36: lut_b_mag = 6'd12; 8'd37: lut_b_mag = 6'd12; 8'd38: lut_b_mag = 6'd12; 8'd39: lut_b_mag = 6'd12;
            8'd40: lut_b_mag = 6'd13; 8'd41: lut_b_mag = 6'd13; 8'd42: lut_b_mag = 6'd13; 8'd43: lut_b_mag = 6'd14;
            8'd44: lut_b_mag = 6'd14; 8'd45: lut_b_mag = 6'd14; 8'd46: lut_b_mag = 6'd15; 8'd47: lut_b_mag = 6'd15;
            8'd48: lut_b_mag = 6'd15; 8'd49: lut_b_mag = 6'd16; 8'd50: lut_b_mag = 6'd16; 8'd51: lut_b_mag = 6'd16;
            8'd52: lut_b_mag = 6'd16; 8'd53: lut_b_mag = 6'd17; 8'd54: lut_b_mag = 6'd17; 8'd55: lut_b_mag = 6'd17;
            8'd56: lut_b_mag = 6'd18; 8'd57: lut_b_mag = 6'd18; 8'd58: lut_b_mag = 6'd18; 8'd59: lut_b_mag = 6'd19;
            8'd60: lut_b_mag = 6'd19; 8'd61: lut_b_mag = 6'd19; 8'd62: lut_b_mag = 6'd19; 8'd63: lut_b_mag = 6'd20;
            8'd64: lut_b_mag = 6'd20; 8'd65: lut_b_mag = 6'd20; 8'd66: lut_b_mag = 6'd21; 8'd67: lut_b_mag = 6'd21;
            8'd68: lut_b_mag = 6'd21; 8'd69: lut_b_mag = 6'd22; 8'd70: lut_b_mag = 6'd22; 8'd71: lut_b_mag = 6'd22;
            8'd72: lut_b_mag = 6'd22; 8'd73: lut_b_mag = 6'd23; 8'd74: lut_b_mag = 6'd23; 8'd75: lut_b_mag = 6'd23;
            8'd76: lut_b_mag = 6'd24; 8'd77: lut_b_mag = 6'd24; 8'd78: lut_b_mag = 6'd24; 8'd79: lut_b_mag = 6'd24;
            8'd80: lut_b_mag = 6'd25; 8'd81: lut_b_mag = 6'd25; 8'd82: lut_b_mag = 6'd25; 8'd83: lut_b_mag = 6'd25;
            8'd84: lut_b_mag = 6'd26; 8'd85: lut_b_mag = 6'd26; 8'd86: lut_b_mag = 6'd26; 8'd87: lut_b_mag = 6'd27;
            8'd88: lut_b_mag = 6'd27; 8'd89: lut_b_mag = 6'd27; 8'd90: lut_b_mag = 6'd27; 8'd91: lut_b_mag = 6'd28;
            8'd92: lut_b_mag = 6'd28; 8'd93: lut_b_mag = 6'd28; 8'd94: lut_b_mag = 6'd28; 8'd95: lut_b_mag = 6'd29;
            8'd96: lut_b_mag = 6'd29; 8'd97: lut_b_mag = 6'd29; 8'd98: lut_b_mag = 6'd30; 8'd99: lut_b_mag = 6'd30;
            8'd100: lut_b_mag = 6'd30; 8'd101: lut_b_mag = 6'd30; 8'd102: lut_b_mag = 6'd31; 8'd103: lut_b_mag = 6'd31;
            8'd104: lut_b_mag = 6'd31; 8'd105: lut_b_mag = 6'd31; 8'd106: lut_b_mag = 6'd32; 8'd107: lut_b_mag = 6'd32;
            8'd108: lut_b_mag = 6'd32; 8'd109: lut_b_mag = 6'd32; 8'd110: lut_b_mag = 6'd33; 8'd111: lut_b_mag = 6'd33;
            8'd112: lut_b_mag = 6'd33; 8'd113: lut_b_mag = 6'd33; 8'd114: lut_b_mag = 6'd34; 8'd115: lut_b_mag = 6'd34;
            8'd116: lut_b_mag = 6'd34; 8'd117: lut_b_mag = 6'd34; 8'd118: lut_b_mag = 6'd35; 8'd119: lut_b_mag = 6'd35;
            8'd120: lut_b_mag = 6'd35; 8'd121: lut_b_mag = 6'd35; 8'd122: lut_b_mag = 6'd36; 8'd123: lut_b_mag = 6'd36;
            8'd124: lut_b_mag = 6'd36; 8'd125: lut_b_mag = 6'd36; 8'd126: lut_b_mag = 6'd36; 8'd127: lut_b_mag = 6'd37;
            8'd128: lut_b_mag = 6'd37; 8'd129: lut_b_mag = 6'd37; 8'd130: lut_b_mag = 6'd37; 8'd131: lut_b_mag = 6'd38;
            8'd132: lut_b_mag = 6'd38; 8'd133: lut_b_mag = 6'd38; 8'd134: lut_b_mag = 6'd38; 8'd135: lut_b_mag = 6'd38;
            8'd136: lut_b_mag = 6'd39; 8'd137: lut_b_mag = 6'd39; 8'd138: lut_b_mag = 6'd39; 8'd139: lut_b_mag = 6'd39;
            8'd140: lut_b_mag = 6'd39; 8'd141: lut_b_mag = 6'd40; 8'd142: lut_b_mag = 6'd40; 8'd143: lut_b_mag = 6'd40;
            8'd144: lut_b_mag = 6'd40; 8'd145: lut_b_mag = 6'd40; 8'd146: lut_b_mag = 6'd41; 8'd147: lut_b_mag = 6'd41;
            8'd148: lut_b_mag = 6'd41; 8'd149: lut_b_mag = 6'd41; 8'd150: lut_b_mag = 6'd41; 8'd151: lut_b_mag = 6'd42;
            8'd152: lut_b_mag = 6'd42; 8'd153: lut_b_mag = 6'd42; 8'd154: lut_b_mag = 6'd42; 8'd155: lut_b_mag = 6'd42;
            8'd156: lut_b_mag = 6'd43; 8'd157: lut_b_mag = 6'd43; 8'd158: lut_b_mag = 6'd43; 8'd159: lut_b_mag = 6'd43;
            8'd160: lut_b_mag = 6'd43; 8'd161: lut_b_mag = 6'd44; 8'd162: lut_b_mag = 6'd44; 8'd163: lut_b_mag = 6'd44;
            8'd164: lut_b_mag = 6'd44; 8'd165: lut_b_mag = 6'd44; 8'd166: lut_b_mag = 6'd44; 8'd167: lut_b_mag = 6'd45;
            8'd168: lut_b_mag = 6'd45; 8'd169: lut_b_mag = 6'd45; 8'd170: lut_b_mag = 6'd45; 8'd171: lut_b_mag = 6'd45;
            8'd172: lut_b_mag = 6'd45; 8'd173: lut_b_mag = 6'd45; 8'd174: lut_b_mag = 6'd46; 8'd175: lut_b_mag = 6'd46;
            8'd176: lut_b_mag = 6'd46; 8'd177: lut_b_mag = 6'd46; 8'd178: lut_b_mag = 6'd46; 8'd179: lut_b_mag = 6'd46;
            8'd180: lut_b_mag = 6'd47; 8'd181: lut_b_mag = 6'd47; 8'd182: lut_b_mag = 6'd47; 8'd183: lut_b_mag = 6'd47;
            8'd184: lut_b_mag = 6'd47; 8'd185: lut_b_mag = 6'd47; 8'd186: lut_b_mag = 6'd47; 8'd187: lut_b_mag = 6'd47;
            8'd188: lut_b_mag = 6'd48; 8'd189: lut_b_mag = 6'd48; 8'd190: lut_b_mag = 6'd48; 8'd191: lut_b_mag = 6'd48;
            8'd192: lut_b_mag = 6'd48; 8'd193: lut_b_mag = 6'd48; 8'd194: lut_b_mag = 6'd48; 8'd195: lut_b_mag = 6'd48;
            8'd196: lut_b_mag = 6'd49; 8'd197: lut_b_mag = 6'd49; 8'd198: lut_b_mag = 6'd49; 8'd199: lut_b_mag = 6'd49;
            8'd200: lut_b_mag = 6'd49; 8'd201: lut_b_mag = 6'd49; 8'd202: lut_b_mag = 6'd49; 8'd203: lut_b_mag = 6'd49;
            8'd204: lut_b_mag = 6'd49; 8'd205: lut_b_mag = 6'd50; 8'd206: lut_b_mag = 6'd50; 8'd207: lut_b_mag = 6'd50;
            8'd208: lut_b_mag = 6'd50; 8'd209: lut_b_mag = 6'd50; 8'd210: lut_b_mag = 6'd50; 8'd211: lut_b_mag = 6'd50;
            8'd212: lut_b_mag = 6'd50; 8'd213: lut_b_mag = 6'd50; 8'd214: lut_b_mag = 6'd50; 8'd215: lut_b_mag = 6'd50;
            8'd216: lut_b_mag = 6'd50; 8'd217: lut_b_mag = 6'd51; 8'd218: lut_b_mag = 6'd51; 8'd219: lut_b_mag = 6'd51;
            8'd220: lut_b_mag = 6'd51; 8'd221: lut_b_mag = 6'd51; 8'd222: lut_b_mag = 6'd51; 8'd223: lut_b_mag = 6'd51;
            8'd224: lut_b_mag = 6'd51; 8'd225: lut_b_mag = 6'd51; 8'd226: lut_b_mag = 6'd51; 8'd227: lut_b_mag = 6'd51;
            8'd228: lut_b_mag = 6'd51; 8'd229: lut_b_mag = 6'd51; 8'd230: lut_b_mag = 6'd51; 8'd231: lut_b_mag = 6'd51;
            8'd232: lut_b_mag = 6'd51; 8'd233: lut_b_mag = 6'd52; 8'd234: lut_b_mag = 6'd52; 8'd235: lut_b_mag = 6'd52;
            8'd236: lut_b_mag = 6'd52; 8'd237: lut_b_mag = 6'd52; 8'd238: lut_b_mag = 6'd52; 8'd239: lut_b_mag = 6'd52;
            8'd240: lut_b_mag = 6'd52; 8'd241: lut_b_mag = 6'd52; 8'd242: lut_b_mag = 6'd52; 8'd243: lut_b_mag = 6'd52;
            8'd244: lut_b_mag = 6'd52; 8'd245: lut_b_mag = 6'd52; 8'd246: lut_b_mag = 6'd52; 8'd247: lut_b_mag = 6'd52;
            8'd248: lut_b_mag = 6'd52; 8'd249: lut_b_mag = 6'd52; 8'd250: lut_b_mag = 6'd52; 8'd251: lut_b_mag = 6'd52;
            8'd252: lut_b_mag = 6'd52; 8'd253: lut_b_mag = 6'd52; 8'd254: lut_b_mag = 6'd52; 8'd255: lut_b_mag = 6'd52;
        endcase
    end

    wire signed [9:0] orb_dx_w = (orb_quad[1] ^ orb_quad[0]) ?
                                 -$signed({2'b00, lut_a_mag}) :
                                  $signed({2'b00, lut_a_mag});
    wire signed [9:0] orb_dy_w = orb_quad[1] ?
                                 -$signed({4'b0000, lut_b_mag}) :
                                  $signed({4'b0000, lut_b_mag});

    // Register moon center (in 0.5-pixel 720p sub-pixel units) cleanly on clk_pixel
    reg signed [12:0] moon_cx_sub   = 13'sd2248; // 1124.0 * 2
    reg signed [12:0] moon_cy_sub   = 13'sd1136; // 568.0  * 2
    reg               moon_in_front = 1'b1;

    always @(posedge clk_pixel) begin
        moon_cx_sub   <= 13'sd2248 + $signed({{3{orb_dx_w[9]}}, orb_dx_w});
        moon_cy_sub   <= 13'sd1136 + $signed({{3{orb_dy_w[9]}}, orb_dy_w});
        moon_in_front <= ~orb_quad[1];
    end

    // Look ahead 3 pixel clocks to compensate for our 3-stage pipeline!
    wire [10:0] cx_ahead = cx + 11'd3;
    wire [9:0]  px = cx_ahead[10:1]; // 0..639 (for crisp 2x2 starfield & nebula)
    wire [8:0]  py = cy[9:1];        // 0..359

    // ========================================================================
    // STAGE 1: Nebula + 3-Layer Moving Starfield + Native 720p Planet Coords
    // ========================================================================
    wire signed [9:0] neb_val = $signed({3'd0, px[9:3]}) - $signed({3'd0, py[8:2]}) + $signed({8'd0, py[5:4]});
    wire [7:0] neb_col = (neb_val >= 10'sd18 && neb_val <= 10'sd34) ?
                         ((neb_val >= 10'sd25 && neb_val <= 10'sd28 && (px[2] ^ py[2])) ? 8'h21 :
                          ((neb_val >= 10'sd21 && neb_val <= 10'sd31) ? 8'h01 : 8'h00)) : 8'h00;

    // Layer 1: Far slow stars (15 px/sec, 32x32 cells)
    wire [9:0] wx1  = px + frame_cnt[11:2];
    wire [4:0] cx1  = wx1[9:5];
    wire [3:0] cy1  = py[8:5];
    wire [8:0] u1   = {cy1, cx1};
    wire [8:0] m1a  = (u1 + {u1[6:0], 2'b00}) ^ {u1[4:0], 4'b0000} ^ {2'b00, u1[8:2]} ^ 9'h15A;
    wire [8:0] h1   = (m1a + {cx1, 3'b000} + {1'b0, cy1, 4'b0000}) ^ {m1a[5:0], 3'b000} ^ {4'b0000, m1a[8:4]};
    wire [4:0] sx1  = 5'd1 + (h1[4:0] & 5'h1D);
    wire [4:0] sy1  = 5'd1 + (h1[8:4] & 5'h1D);
    wire       en1  = (h1[8:7] != 2'b11) && (wx1[4:0] == sx1) && (py[4:0] == sy1);
    wire [1:0] cs1  = cx1[1:0] ^ cy1[1:0] ^ h1[1:0];
    wire [7:0] col1 = (cs1 == 2'd0) ? 8'h01 : (cs1 == 2'd1) ? 8'h02 : (cs1 == 2'd2) ? 8'h49 : 8'h25;

    // Layer 2: Mid stars with twinkle (30 px/sec, 64x32 cells)
    wire [9:0] wx2  = px + frame_cnt[10:1];
    wire [3:0] cx2  = wx2[9:6];
    wire [3:0] cy2  = py[8:5];
    wire [7:0] u2   = {cy2, cx2};
    wire [8:0] m2a  = ({1'b0, u2} + {u2[6:0], 2'b00}) ^ {u2[4:0], 4'b0000} ^ 9'h0A7;
    wire [8:0] h2   = (m2a + {1'b0, cx2, 4'b0000} + {cy2, 3'b000}) ^ {m2a[4:0], 4'b0000} ^ {3'b000, m2a[8:3]};
    wire [5:0] sx2  = 6'd2 + (h2[5:0] & 6'h3B);
    wire [4:0] sy2  = 5'd1 + (h2[8:4] & 5'h1D);
    wire       en2  = (h2[1:0] != 2'b00) && (wx2[5:0] == sx2) && (py[4:0] == sy2);
    wire [7:0] c2b  = (h2[3:2] == 2'd0) ? 8'h92 : (h2[3:2] == 2'd1) ? 8'h57 : (h2[3:2] == 2'd2) ? 8'hB6 : 8'h53;
    wire [7:0] col2 = (frame_cnt[6:4] == h2[8:6]) ? 8'h49 : c2b;

    // Layer 3: Near fast stars + 4-point starlight cross (60 px/sec, 64x64 cells)
    wire [9:0] wx3  = px + frame_cnt[9:0];
    wire [3:0] cx3  = wx3[9:6];
    wire [2:0] cy3  = py[8:6];
    wire [6:0] u3   = {cy3, cx3};
    wire [8:0] m3a  = ({2'b00, u3} + {u3, 2'b00}) ^ {u3[4:0], 4'b0000} ^ 9'h13D;
    wire [8:0] h3   = (m3a + {1'b0, cx3, 4'b0000} + {1'b0, cy3, 5'b00000}) ^ {m3a[5:0], 3'b000} ^ {4'b0000, m3a[8:4]};
    wire [5:0] sx3  = 6'd4 + (h3[5:0] & 6'h37);
    wire [5:0] sy3  = 6'd4 + (h3[8:3] & 6'h37);
    wire       nz3  = (h3[8:7] != 2'b00);
    wire       cr3  = (h3[7:6] == 2'b00);
    wire       hit3 = nz3 && (wx3[5:0] == sx3) && (py[5:0] == sy3);
    wire       arm3 = nz3 && cr3 && (
                      ((wx3[5:0] == sx3) && ((py[5:0] == sy3 - 6'd1) || (py[5:0] == sy3 + 6'd1))) ||
                      ((py[5:0] == sy3)  && ((wx3[5:0] == sx3 - 6'd1) || (wx3[5:0] == sx3 + 6'd1)))
                      );
    wire [7:0] col3 = (h3[1:0] == 2'd1) ? 8'hDF : (h3[1:0] == 2'd3) ? 8'hFE : 8'hFF;

    // Native 1280x720 signed coordinates for razor-sharp planets
    wire signed [12:0] scx = $signed({2'b00, cx_ahead});
    wire signed [12:0] scy = $signed({3'b000, cy});

    // Planet 1: Ringed Gas Giant at (984, 236), R=80
    wire signed [12:0] w_dx1  = scx - 13'sd984;
    wire signed [12:0] w_dy1  = scy - 13'sd236;
    wire               w_box1 = (w_dx1 >= -13'sd192) && (w_dx1 <= 13'sd192) &&
                                (w_dy1 >= -13'sd96)  && (w_dy1 <= 13'sd96);
    wire signed [12:0] w_tilt_y = w_dy1 - (w_dx1 >>> 2);
    wire signed [12:0] w_rx     = w_dx1 + (w_dy1 >>> 2);
    wire signed [16:0] w_ty13   = (w_tilt_y <<< 3) + (w_tilt_y <<< 2) + w_tilt_y;
    wire signed [12:0] w_ry_sc  = w_ty13 >>> 2;

    // Planet 2: Mars at (1124, 568), R=44
    wire signed [12:0] w_dx2  = scx - 13'sd1124;
    wire signed [12:0] w_dy2  = scy - 13'sd568;
    wire               w_box2 = (w_dx2 >= -13'sd44) && (w_dx2 <= 13'sd44) &&
                                (w_dy2 >= -13'sd44) && (w_dy2 <= 13'sd44);

    // Moon in 0.5-pixel sub-pixel coordinates: R_sub=22 (= 11.0 px in 1280x720)
    wire signed [12:0] scx_sub = $signed({1'b0, cx_ahead, 1'b0});
    wire signed [12:0] scy_sub = $signed({2'b00, cy, 1'b0});
    wire signed [12:0] w_mdx   = scx_sub - moon_cx_sub;
    wire signed [12:0] w_mdy   = scy_sub - moon_cy_sub;
    wire               w_mbox  = (w_mdx >= -13'sd22) && (w_mdx <= 13'sd22) &&
                                 (w_mdy >= -13'sd22) && (w_mdy <= 13'sd22);

    // Planet 3: Turquoise Crescent Exoplanet at (620, 116), R=28
    wire signed [12:0] w_dx3  = scx - 13'sd620;
    wire signed [12:0] w_dy3  = scy - 13'sd116;
    wire               w_box3 = (w_dx3 >= -13'sd28) && (w_dx3 <= 13'sd28) &&
                                (w_dy3 >= -13'sd28) && (w_dy3 <= 13'sd28);

    // Planet 4: Golden Dwarf Planet at (336, 608), R=18
    wire signed [12:0] w_dx4  = scx - 13'sd336;
    wire signed [12:0] w_dy4  = scy - 13'sd608;
    wire               w_box4 = (w_dx4 >= -13'sd18) && (w_dx4 <= 13'sd18) &&
                                (w_dy4 >= -13'sd18) && (w_dy4 <= 13'sd18);

    reg               box1_p1, box2_p1, mbox_p1, box3_p1, box4_p1;
    reg [7:0]         star_neb_p1;
    reg               moon_front_p1;
    reg signed [8:0]  dx1_p1;
    reg signed [7:0]  dy1_p1;
    reg signed [8:0]  tilt_y_p1;
    reg signed [8:0]  rx_p1;
    reg signed [9:0]  ry_sc_p1;
    reg signed [6:0]  dx2_p1, dy2_p1;
    reg signed [5:0]  mdx_p1, mdy_p1;
    reg signed [5:0]  dx3_p1, dy3_p1;
    reg signed [5:0]  dx4_p1, dy4_p1;

    always @(posedge clk_pixel) begin
        star_neb_p1   <= hit3 ? col3 :
                         arm3 ? 8'h07 :
                         en2  ? col2 :
                         en1  ? col1 : neb_col;
        moon_front_p1 <= moon_in_front;

        box1_p1   <= w_box1;
        dx1_p1    <= w_box1 ? w_dx1[8:0]    : 9'sd0;
        dy1_p1    <= w_box1 ? w_dy1[7:0]    : 8'sd0;
        tilt_y_p1 <= w_box1 ? w_tilt_y[8:0] : 9'sd0;
        rx_p1     <= w_box1 ? w_rx[8:0]     : 9'sd0;
        ry_sc_p1  <= w_box1 ? w_ry_sc[9:0]  : 10'sd0;

        box2_p1   <= w_box2;
        dx2_p1    <= w_box2 ? w_dx2[6:0]    : 7'sd0;
        dy2_p1    <= w_box2 ? w_dy2[6:0]    : 7'sd0;

        mbox_p1   <= w_mbox;
        mdx_p1    <= w_mbox ? w_mdx[5:0]    : 6'sd0;
        mdy_p1    <= w_mbox ? w_mdy[5:0]    : 6'sd0;

        box3_p1   <= w_box3;
        dx3_p1    <= w_box3 ? w_dx3[5:0]    : 6'sd0;
        dy3_p1    <= w_box3 ? w_dy3[5:0]    : 6'sd0;

        box4_p1   <= w_box4;
        dx4_p1    <= w_box4 ? w_dx4[5:0]    : 6'sd0;
        dy4_p1    <= w_box4 ? w_dy4[5:0]    : 6'sd0;
    end

    // ========================================================================
    // STAGE 2: Unsigned Magnitudes, Squared Distances & 3D Highlight Terms
    // ========================================================================
    wire [8:0] u_dx1 = dx1_p1[8]   ? (-dx1_p1)   : dx1_p1;
    wire [7:0] u_dy1 = dy1_p1[7]   ? (-dy1_p1)   : dy1_p1;
    wire [8:0] u_rx  = rx_p1[8]    ? (-rx_p1)    : rx_p1;
    wire [9:0] u_ry  = ry_sc_p1[9] ? (-ry_sc_p1) : ry_sc_p1;
    wire [6:0] u_dx2 = dx2_p1[6]   ? (-dx2_p1)   : dx2_p1;
    wire [6:0] u_dy2 = dy2_p1[6]   ? (-dy2_p1)   : dy2_p1;
    wire [5:0] u_mdx = mdx_p1[5]   ? (-mdx_p1)   : mdx_p1;
    wire [5:0] u_mdy = mdy_p1[5]   ? (-mdy_p1)   : mdy_p1;
    wire [5:0] u_dx3 = dx3_p1[5]   ? (-dx3_p1)   : dx3_p1;
    wire [5:0] u_dy3 = dy3_p1[5]   ? (-dy3_p1)   : dy3_p1;
    wire [5:0] u_dx4 = dx4_p1[5]   ? (-dx4_p1)   : dx4_p1;
    wire [5:0] u_dy4 = dy4_p1[5]   ? (-dy4_p1)   : dy4_p1;

    wire [7:0] adx1 = u_dx1[7:0];
    wire [6:0] ady1 = u_dy1[6:0];
    wire [7:0] arx  = u_rx[7:0];
    wire [8:0] ary  = u_ry[8:0];
    wire [5:0] adx2 = u_dx2[5:0];
    wire [5:0] ady2 = u_dy2[5:0];
    wire [4:0] amdx = u_mdx[4:0];
    wire [4:0] amdy = u_mdy[4:0];
    wire [4:0] adx3 = u_dx3[4:0];
    wire [4:0] ady3 = u_dy3[4:0];
    wire [4:0] adx4 = u_dx4[4:0];
    wire [4:0] ady4 = u_dy4[4:0];

    // Sign-extended linear terms for 3D spherical highlight distance:
    // h_sq = (dx + x_h)^2 + (dy + y_h)^2 = d_sq + (2*x_h*dx + 2*y_h*dy + x_h^2 + y_h^2)
    wire signed [15:0] s_dx1 = {{7{dx1_p1[8]}}, dx1_p1};
    wire signed [15:0] s_dy1 = {{8{dy1_p1[7]}}, dy1_p1};
    wire signed [12:0] s_dx2 = {{6{dx2_p1[6]}}, dx2_p1};
    wire signed [12:0] s_dy2 = {{6{dy2_p1[6]}}, dy2_p1};
    wire signed [10:0] s_mdx = {{5{mdx_p1[5]}}, mdx_p1};
    wire signed [10:0] s_mdy = {{5{mdy_p1[5]}}, mdy_p1};
    wire signed [11:0] s_dx3 = {{6{dx3_p1[5]}}, dx3_p1};
    wire signed [11:0] s_dy3 = {{6{dy3_p1[5]}}, dy3_p1};
    wire signed [10:0] s_dx4 = {{5{dx4_p1[5]}}, dx4_p1};
    wire signed [10:0] s_dy4 = {{5{dy4_p1[5]}}, dy4_p1};

    reg [7:0]         star_neb_p2;
    reg               moon_front_p2;
    reg               box1_p2, box2_p2, mbox_p2, box3_p2, box4_p2;

    reg [15:0]        dx1_sq_p2;
    reg [13:0]        dy1_sq_p2;
    reg [15:0]        rx_sq_p2;
    reg [17:0]        ry_sq_p2;
    reg signed [8:0]  tilt_y_p2;
    reg signed [8:0]  dx1_p2;
    reg signed [7:0]  dy1_p2;
    reg signed [15:0] h1_lin_p2;

    reg [10:0]        dx2_sq_p2, dy2_sq_p2;
    reg signed [6:0]  dx2_p2, dy2_p2;
    reg signed [12:0] h2_lin_p2;

    reg [8:0]         mdx_sq_p2, mdy_sq_p2;
    reg signed [10:0] mh_lin_p2;

    reg [9:0]         dx3_sq_p2, dy3_sq_p2;
    reg signed [11:0] h3_lin_p2;

    reg [8:0]         dx4_sq_p2, dy4_sq_p2;
    reg signed [10:0] h4_lin_p2;

    always @(posedge clk_pixel) begin
        star_neb_p2   <= star_neb_p1;
        moon_front_p2 <= moon_front_p1;

        box1_p2   <= box1_p1;
        dx1_sq_p2 <= adx1 * adx1;
        dy1_sq_p2 <= ady1 * ady1;
        rx_sq_p2  <= arx * arx;
        ry_sq_p2  <= ary * ary;
        tilt_y_p2 <= tilt_y_p1;
        dx1_p2    <= dx1_p1;
        dy1_p2    <= dy1_p1;
        // 64*dx1 + 48*dy1 + 1600  (highlight at (-32, -24))
        h1_lin_p2 <= (s_dx1 <<< 6) + (s_dy1 <<< 5) + (s_dy1 <<< 4) + 16'sd1600;

        box2_p2   <= box2_p1;
        dx2_sq_p2 <= adx2 * adx2;
        dy2_sq_p2 <= ady2 * ady2;
        dx2_p2    <= dx2_p1;
        dy2_p2    <= dy2_p1;
        // 36*dx2 + 36*dy2 + 648   (highlight at (-18, -18))
        h2_lin_p2 <= (s_dx2 <<< 5) + (s_dx2 <<< 2) + (s_dy2 <<< 5) + (s_dy2 <<< 2) + 13'sd648;

        mbox_p2   <= mbox_p1;
        mdx_sq_p2 <= amdx * amdx;
        mdy_sq_p2 <= amdy * amdy;
        // 16*mdx + 16*mdy + 128   (highlight at (-8, -8) half-pixels)
        mh_lin_p2 <= (s_mdx <<< 4) + (s_mdy <<< 4) + 11'sd128;

        box3_p2   <= box3_p1;
        dx3_sq_p2 <= adx3 * adx3;
        dy3_sq_p2 <= ady3 * ady3;
        // 24*dx3 + 24*dy3 + 288   (highlight at (-12, -12))
        h3_lin_p2 <= (s_dx3 <<< 4) + (s_dx3 <<< 3) + (s_dy3 <<< 4) + (s_dy3 <<< 3) + 12'sd288;

        box4_p2   <= box4_p1;
        dx4_sq_p2 <= adx4 * adx4;
        dy4_sq_p2 <= ady4 * ady4;
        // 16*dx4 + 16*dy4 + 128   (highlight at (-8, -8))
        h4_lin_p2 <= (s_dx4 <<< 4) + (s_dy4 <<< 4) + 11'sd128;
    end

    // ========================================================================
    // STAGE 3: True 3D Spherical Planet / Ring / Moon Shading & Compositing
    // ========================================================================
    wire [16:0] d1_sq     = {1'b0, dx1_sq_p2} + {3'b000, dy1_sq_p2};
    wire [18:0] r_ring_sq = {3'b000, rx_sq_p2} + {1'b0, ry_sq_p2};
    wire [11:0] d2_sq     = {1'b0, dx2_sq_p2} + {1'b0, dy2_sq_p2};
    wire [9:0]  md_sq     = {1'b0, mdx_sq_p2} + {1'b0, mdy_sq_p2};
    wire [10:0] d3_sq     = {1'b0, dx3_sq_p2} + {1'b0, dy3_sq_p2};
    wire [9:0]  d4_sq     = {1'b0, dx4_sq_p2} + {1'b0, dy4_sq_p2};

    wire signed [18:0] h1_sq = $signed({2'b00, d1_sq}) + $signed({{3{h1_lin_p2[15]}}, h1_lin_p2});
    wire signed [13:0] h2_sq = $signed({2'b00, d2_sq}) + $signed({h2_lin_p2[12], h2_lin_p2});
    wire signed [11:0] mh_sq = $signed({2'b00, md_sq}) + $signed({mh_lin_p2[10], mh_lin_p2});
    wire signed [12:0] h3_sq = $signed({2'b00, d3_sq}) + $signed({h3_lin_p2[11], h3_lin_p2});
    wire signed [11:0] h4_sq = $signed({2'b00, d4_sq}) + $signed({h4_lin_p2[10], h4_lin_p2});

    // Planet 3: Turquoise Crescent Exoplanet (R=28, R^2 < 780)
    wire hit_p3 = box3_p2 && (d3_sq < 11'd780);
    wire [7:0] p3_col = (h3_sq < 13'sd180)  ? 8'h9F :
                        (h3_sq < 13'sd520)  ? 8'h5B :
                        (h3_sq < 13'sd980)  ? 8'h17 :
                        (h3_sq < 13'sd1480) ? 8'h0A :
                        (h3_sq < 13'sd1920) ? 8'h05 : 8'h02;

    // Planet 4: Golden Dwarf Planet (R=18, R^2 < 320)
    wire hit_p4 = box4_p2 && (d4_sq < 10'd320);
    wire [7:0] p4_col = (h4_sq < 12'sd90)  ? 8'hF8 :
                        (h4_sq < 12'sd250) ? 8'hD4 :
                        (h4_sq < 12'sd460) ? 8'h90 : 8'h48;

    // Planet 1: Giant Ringed Gas Giant (R=80, R^2 < 6390) + Tilted Rings
    wire in_ring = box1_p2 && (r_ring_sq >= 19'd10400) && (r_ring_sq <= 19'd29600) &&
                   !((r_ring_sq > 19'd19000) && (r_ring_sq < 19'd21400));
    wire ring_shadow = (tilt_y_p2 < 9'sd0) && (dx1_p2 > 9'sd20) &&
                       (dy1_p2 > -8'sd44) && (dy1_p2 < 8'sd44);
    wire [7:0] ring_col = ring_shadow              ? 8'h20 :
                          (r_ring_sq < 19'd14000)  ? 8'h92 :
                          (r_ring_sq < 19'd19000)  ? (r_ring_sq[9] ? 8'hD5 : 8'hB5) :
                          (r_ring_sq < 19'd25600)  ? 8'h96 : 8'h4E;

    wire hit_p1 = box1_p2 && (d1_sq < 17'd6390);
    wire signed [10:0] p1_lat = $signed({{2{tilt_y_p2[8]}}, tilt_y_p2}) +
                                $signed({4'b0000, dx1_sq_p2[15:9]}) + 11'sd112;
    wire [1:0]         b_mod  = p1_lat[4:3];
    wire [7:0] p1_c_lo  = (b_mod == 2'd0) ? 8'h0A : (b_mod == 2'd1) ? 8'h0F : (b_mod == 2'd2) ? 8'h2E : 8'h0B;
    wire [7:0] p1_c_mid = (b_mod == 2'd0) ? 8'h13 : (b_mod == 2'd1) ? 8'h57 : (b_mod == 2'd2) ? 8'h76 : 8'h33;
    wire [7:0] p1_c_hi  = (b_mod == 2'd0) ? 8'h57 : (b_mod == 2'd1) ? 8'h9B : (b_mod == 2'd2) ? 8'hB7 : 8'h5B;
    wire [7:0] p1_col   = (h1_sq < 19'sd2400)  ? p1_c_hi :
                          (h1_sq < 19'sd6200)  ? p1_c_mid :
                          (h1_sq < 19'sd10400) ? p1_c_lo :
                          (h1_sq < 19'sd14200) ? (b_mod[0] ? 8'h02 : 8'h05) : 8'h01;

    // Silky-smooth 60 FPS Silver Moon (R_sub=22, R_sub^2 < 480) with soft 0.5-px rim
    wire hit_moon = mbox_p2 && (md_sq < 10'd480);
    wire [7:0] moon_rim  = (mh_sq < 12'sd320) ? 8'h92 :
                           (mh_sq < 12'sd760) ? 8'h49 : 8'h24;
    wire [7:0] moon_body = (mh_sq < 12'sd140)  ? 8'hFF :
                           (mh_sq < 12'sd380)  ? 8'hDB :
                           (mh_sq < 12'sd680)  ? 8'hB6 :
                           (mh_sq < 12'sd980)  ? 8'h92 :
                           (mh_sq < 12'sd1260) ? 8'h49 : 8'h24;
    wire [7:0] moon_col  = (md_sq >= 10'd432) ? moon_rim : moon_body;

    // Planet 2: Mars (R=44, R^2 < 1930) - True 3D spherical shading, warm crimson night limb
    wire hit_p2 = box2_p2 && (d2_sq < 12'd1930);
    wire signed [8:0] m_lat = $signed({{2{dy2_p2[6]}}, dy2_p2}) +
                              $signed({5'b00000, dx2_sq_p2[10:7]});
    wire signed [8:0] m_tmp = m_lat + $signed({{5{dx2_p2[6]}}, dx2_p2[6:3]}) + 9'sd64;
    wire [1:0]        mare  = m_tmp[4:3];
    wire signed [8:0] m_pat = $signed({{2{dx2_p2[6]}}, dx2_p2}) +
                              $signed({dy2_p2[6], dy2_p2, 1'b0}) + 9'sd128;
    wire              dark_mare = (mare == 2'd1) && (m_pat[4] == 1'b0);

    wire [7:0] p2_col = ((m_lat < -9'sd31) && (h2_sq < 14'sd2750)) ?
                            ((h2_sq < 14'sd1150) ? 8'hFF : (h2_sq < 14'sd1950) ? 8'hDF : 8'hB6) :
                        (h2_sq < 14'sd420)  ? (dark_mare ? 8'hEC : 8'hF0) :
                        (h2_sq < 14'sd1150) ? (dark_mare ? 8'hC4 : 8'hEC) :
                        (h2_sq < 14'sd2100) ? ((mare == 2'd3) ? 8'hE8 : (dark_mare ? 8'hA0 : 8'hC4)) :
                        (h2_sq < 14'sd3150) ? (dark_mare ? 8'h80 : 8'hA0) :
                        (h2_sq < 14'sd4150) ? (dark_mare ? 8'h60 : 8'h80) :
                        (h2_sq < 14'sd4750) ? 8'h60 : 8'h40;

    reg [7:0] comp_col;
    always @(*) begin
        comp_col = star_neb_p2;
        if (hit_p3)                          comp_col = p3_col;
        if (hit_p4)                          comp_col = p4_col;
        if (in_ring && (tilt_y_p2 < 9'sd0))  comp_col = ring_col;
        if (hit_p1)                          comp_col = p1_col;
        if (in_ring && (tilt_y_p2 >= 9'sd0)) comp_col = ring_col;
        if (!moon_front_p2 && hit_moon)      comp_col = moon_col;
        if (hit_p2)                          comp_col = p2_col;
        if (moon_front_p2 && hit_moon)       comp_col = moon_col;
    end

    always @(posedge clk_pixel) begin
        space_color <= comp_col;
    end

endmodule
