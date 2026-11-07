`timescale 1ns / 1ps

// ============================================================================
// MiniGPU - Hardware Entity Engine (Autonome FPGA Vijanden & Sprites)
// ============================================================================
// Beheert 8 hardwarematige entiteiten die zelfstandig leven in de FPGA:
// - Vaste wereldposities (1024x1024 Hyrule veld)
// - Automatische hardware camera-transformatie (scroll_x, scroll_y)
// - Hardware AI (Patrouilleren, Willekeurig dwalen met LFSR, of Link achtervolgen)
// - Automatische animatie (tentakels wiebelen)
// - Real-time HDMI scanout compositing (0 SDRAM overhead, 0 tearing)
// - Hardware botsingsdetectie met de speler
// ============================================================================

module entity_engine (
    input  wire        clk_pixel,   // 74.25 MHz HDMI pixel clock
    input  wire        rst_n,

    // HDMI Scanout Coördinaten
    input  wire [10:0] cx,
    input  wire [9:0]  cy,

    // Hardware Camera Scroll
    input  wire [9:0]  scroll_x,
    input  wire [9:0]  scroll_y,

    // Speler (Link) Coördinaten
    input  wire [9:0]  player_x,
    input  wire [9:0]  player_y,

    // Commando-interface vanuit gpu_engine
    input  wire        cmd_we,
    input  wire [3:0]  cmd_type,
    input  wire [2:0]  cmd_slot,
    input  wire [4:0]  cmd_spr_base,
    input  wire [4:0]  cmd_spr_alt,
    input  wire [9:0]  cmd_x,
    input  wire [9:0]  cmd_y,
    input  wire [2:0]  cmd_ai_mode,
    input  wire [2:0]  cmd_speed,
    input  wire [2:0]  cmd_hp,
    input  wire [1:0]  cmd_dir,

    // Sprite RAM Leesport (Port B)
    output reg  [12:0] spr_read_addr,
    input  wire [7:0]  spr_read_data,

    // Video Output (naar Framebuffer Compositor)
    output reg  [7:0]  entity_color,

    // Hardware Botsingsstatus
    output wire [7:0]  collision_flags,
    output wire        collision_any
);

    // ========================================================================
    // Entity Registers (8 Hardware Slots)
    // ========================================================================
    reg [9:0]  ent_x          [0:7];
    reg [9:0]  ent_y          [0:7];
    reg [9:0]  ent_min_coord  [0:7];
    reg [9:0]  ent_max_coord  [0:7];
    reg [4:0]  ent_spr_base   [0:7];
    reg [4:0]  ent_spr_alt    [0:7];
    reg        ent_anim_frame [0:7];
    reg [1:0]  ent_dir        [0:7]; // 0=Rechts, 1=Links, 2=Onder, 3=Boven
    reg [2:0]  ent_ai_mode    [0:7]; // 0=Static, 1=Patrol H, 2=Patrol V, 3=Wander, 4=Chase
    reg [2:0]  ent_speed      [0:7];
    reg [2:0]  ent_hp         [0:7];
    reg        ent_active     [0:7];
    reg [5:0]  ent_hurt_timer [0:7]; // Schade-knipperteller

    // ========================================================================
    // Hardware Timers & LFSR (Willekeurige getallenen-generator)
    // ========================================================================
    wire vsync_tick = (cx == 0 && cy == 720);

    // AI stap: elke 16 frames = ~266 ms (~3.75 stappen per seconde)
    reg [3:0] ai_frame_cnt = 0;
    always @(posedge clk_pixel) begin
        if (!rst_n) ai_frame_cnt <= 0;
        else if (vsync_tick) ai_frame_cnt <= ai_frame_cnt + 1;
    end
    wire ai_step = vsync_tick && (ai_frame_cnt == 0);

    // 16-bits Galois LFSR voor hardwarematige pseudo-random bewegingen
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge clk_pixel) begin
        if (!rst_n) lfsr <= 16'hACE1;
        else lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // ========================================================================
    // Autonome Hardware AI & Commando Verwerking
    // ========================================================================
    integer k;
    always @(posedge clk_pixel) begin
        if (!rst_n) begin
            for (k = 0; k < 8; k = k + 1) begin
                ent_active[k]     <= 0;
                ent_hp[k]         <= 0;
                ent_anim_frame[k] <= 0;
                ent_hurt_timer[k] <= 0;
                ent_x[k]          <= 0;
                ent_y[k]          <= 0;
                ent_min_coord[k]  <= 0;
                ent_max_coord[k]  <= 0;
                ent_spr_base[k]   <= 0;
                ent_spr_alt[k]    <= 0;
                ent_dir[k]        <= 0;
                ent_ai_mode[k]    <= 0;
                ent_speed[k]      <= 0;
            end
        end else begin
            // 1. Commando's vanuit UART verwerken
            if (cmd_we) begin
                case (cmd_type)
                    // 1 = Spawn Entity
                    4'd1: begin
                        ent_active[cmd_slot]     <= 1;
                        ent_spr_base[cmd_slot]   <= cmd_spr_base;
                        ent_spr_alt[cmd_slot]    <= cmd_spr_alt;
                        ent_x[cmd_slot]          <= cmd_x;
                        ent_y[cmd_slot]          <= cmd_y;
                        ent_min_coord[cmd_slot]  <= (cmd_ai_mode == 3'd2) ? (cmd_y - 10'd48) : (cmd_x - 10'd48);
                        ent_max_coord[cmd_slot]  <= (cmd_ai_mode == 3'd2) ? (cmd_y + 10'd48) : (cmd_x + 10'd48);
                        ent_ai_mode[cmd_slot]    <= cmd_ai_mode;
                        ent_speed[cmd_slot]      <= (cmd_speed == 0) ? 3'd4 : cmd_speed;
                        ent_hp[cmd_slot]         <= (cmd_hp == 0) ? 3'd2 : cmd_hp;
                        ent_anim_frame[cmd_slot] <= 0;
                        ent_hurt_timer[cmd_slot] <= 0;
                        ent_dir[cmd_slot]        <= cmd_dir;
                    end
                    // 2 = Kill Entity
                    4'd2: begin
                        ent_active[cmd_slot] <= 0;
                        ent_hp[cmd_slot]     <= 0;
                    end
                    // 3 = Damage Entity
                    4'd3: begin
                        if (ent_hp[cmd_slot] <= cmd_hp) begin
                            ent_hp[cmd_slot]     <= 0;
                            ent_active[cmd_slot] <= 0; // Verslagen!
                        end else begin
                            ent_hp[cmd_slot]         <= ent_hp[cmd_slot] - cmd_hp;
                            ent_hurt_timer[cmd_slot] <= 6'd20; // Knipperen
                        end
                    end
                endcase
            end

            // 2. Autonome AI Stap
            if (ai_step) begin
                for (k = 0; k < 8; k = k + 1) begin
                    if (ent_active[k] && ent_hp[k] > 0) begin
                        // Wissel animatieframe (tentakels wiebelen)
                        ent_anim_frame[k] <= ~ent_anim_frame[k];

                        // Schade-teller verminderen
                        if (ent_hurt_timer[k] > 0)
                            ent_hurt_timer[k] <= ent_hurt_timer[k] - 1;

                        // AI Bewegingspatroon
                        case (ent_ai_mode[k])
                            // Mode 1: Horizontale Patrouille
                            3'd1: begin
                                if (ent_dir[k] == 0) begin // Rechts
                                    if (ent_x[k] >= ent_max_coord[k]) ent_dir[k] <= 1;
                                    else ent_x[k] <= ent_x[k] + {7'd0, ent_speed[k]};
                                end else begin // Links
                                    if (ent_x[k] <= ent_min_coord[k]) ent_dir[k] <= 0;
                                    else ent_x[k] <= ent_x[k] - {7'd0, ent_speed[k]};
                                end
                            end

                            // Mode 2: Verticale Patrouille
                            3'd2: begin
                                if (ent_dir[k] == 2) begin // Omlaag
                                    if (ent_y[k] >= ent_max_coord[k]) ent_dir[k] <= 3;
                                    else ent_y[k] <= ent_y[k] + {7'd0, ent_speed[k]};
                                end else begin // Omhoog
                                    if (ent_y[k] <= ent_min_coord[k]) ent_dir[k] <= 2;
                                    else ent_y[k] <= ent_y[k] - {7'd0, ent_speed[k]};
                                end
                            end

                            // Mode 3: Willekeurig Dwalen (LFSR)
                            3'd3: begin
                                case (k)
                                    0: if (lfsr[1:0] == 2'b11) ent_dir[0] <= lfsr[3:2];
                                    1: if (lfsr[3:2] == 2'b11) ent_dir[1] <= lfsr[5:4];
                                    2: if (lfsr[5:4] == 2'b11) ent_dir[2] <= lfsr[7:6];
                                    3: if (lfsr[7:6] == 2'b11) ent_dir[3] <= lfsr[9:8];
                                    4: if (lfsr[9:8] == 2'b11) ent_dir[4] <= lfsr[11:10];
                                    5: if (lfsr[11:10] == 2'b11) ent_dir[5] <= lfsr[13:12];
                                    6: if (lfsr[13:12] == 2'b11) ent_dir[6] <= lfsr[15:14];
                                    7: if (lfsr[15:14] == 2'b11) ent_dir[7] <= lfsr[1:0];
                                endcase
                                case (ent_dir[k])
                                    2'd0: ent_x[k] <= ent_x[k] + {7'd0, ent_speed[k]};
                                    2'd1: ent_x[k] <= ent_x[k] - {7'd0, ent_speed[k]};
                                    2'd2: ent_y[k] <= ent_y[k] + {7'd0, ent_speed[k]};
                                    2'd3: ent_y[k] <= ent_y[k] - {7'd0, ent_speed[k]};
                                endcase
                            end

                            // Mode 4: Link Achtervolgen (Seek Player)
                            3'd4: begin
                                if (player_x > ent_x[k] + 10'd6)
                                    ent_x[k] <= ent_x[k] + {7'd0, ent_speed[k]};
                                else if (player_x + 10'd6 < ent_x[k])
                                    ent_x[k] <= ent_x[k] - {7'd0, ent_speed[k]};

                                if (player_y > ent_y[k] + 10'd6)
                                    ent_y[k] <= ent_y[k] + {7'd0, ent_speed[k]};
                                else if (player_y + 10'd6 < ent_y[k])
                                    ent_y[k] <= ent_y[k] - {7'd0, ent_speed[k]};
                            end
                        endcase
                    end
                end
            end
        end
    end

    // ========================================================================
    // Hardware Botsingsdetectie (Link vs Vijanden)
    // ========================================================================
    reg [7:0] coll_reg = 0;
    always @(posedge clk_pixel) begin
        if (!rst_n) coll_reg <= 0;
        else if (vsync_tick) begin
            for (k = 0; k < 8; k = k + 1) begin
                if (ent_active[k] && ent_hp[k] > 0) begin
                    if (((player_x >= ent_x[k]) ? (player_x - ent_x[k]) : (ent_x[k] - player_x)) < 10'd14 &&
                        ((player_y >= ent_y[k]) ? (player_y - ent_y[k]) : (ent_y[k] - player_y)) < 10'd14)
                        coll_reg[k] <= 1;
                    else
                        coll_reg[k] <= 0;
                end else begin
                    coll_reg[k] <= 0;
                end
            end
        end
    end

    assign collision_flags = coll_reg;
    assign collision_any   = |coll_reg;

    // ========================================================================
    // Real-Time HDMI Scanout Compositor (2-Cycle Pipeline)
    // ========================================================================
    // 2 klokcycli vooruitkijken (cx + 2) om exact synchroon te lopen met bg_layer!
    wire [10:0] cx_ahead = cx + 11'd2;
    wire [9:0]  px = cx_ahead[10:1]; // 0..639
    wire [8:0]  py = cy[9:1];        // 0..359

    // Schermposities en bounding box controle per entiteit
    wire signed [10:0] dx0 = ent_x[0] - scroll_x;
    wire signed [10:0] sx0 = (dx0 < -11'sd512) ? (dx0 + 11'sd1024) : (dx0 > 11'sd512) ? (dx0 - 11'sd1024) : dx0;
    wire signed [10:0] dy0 = ent_y[0] - scroll_y;
    wire signed [10:0] sy0 = (dy0 < -11'sd512) ? (dy0 + 11'sd1024) : (dy0 > 11'sd512) ? (dy0 - 11'sd1024) : dy0;
    wire in_box0 = (px >= sx0) && (px < sx0 + 16) && (py >= sy0) && (py < sy0 + 16) && ent_active[0] && (ent_hp[0] > 0);

    wire signed [10:0] dx1 = ent_x[1] - scroll_x;
    wire signed [10:0] sx1 = (dx1 < -11'sd512) ? (dx1 + 11'sd1024) : (dx1 > 11'sd512) ? (dx1 - 11'sd1024) : dx1;
    wire signed [10:0] dy1 = ent_y[1] - scroll_y;
    wire signed [10:0] sy1 = (dy1 < -11'sd512) ? (dy1 + 11'sd1024) : (dy1 > 11'sd512) ? (dy1 - 11'sd1024) : dy1;
    wire in_box1 = (px >= sx1) && (px < sx1 + 16) && (py >= sy1) && (py < sy1 + 16) && ent_active[1] && (ent_hp[1] > 0);

    wire signed [10:0] dx2 = ent_x[2] - scroll_x;
    wire signed [10:0] sx2 = (dx2 < -11'sd512) ? (dx2 + 11'sd1024) : (dx2 > 11'sd512) ? (dx2 - 11'sd1024) : dx2;
    wire signed [10:0] dy2 = ent_y[2] - scroll_y;
    wire signed [10:0] sy2 = (dy2 < -11'sd512) ? (dy2 + 11'sd1024) : (dy2 > 11'sd512) ? (dy2 - 11'sd1024) : dy2;
    wire in_box2 = (px >= sx2) && (px < sx2 + 16) && (py >= sy2) && (py < sy2 + 16) && ent_active[2] && (ent_hp[2] > 0);

    wire signed [10:0] dx3 = ent_x[3] - scroll_x;
    wire signed [10:0] sx3 = (dx3 < -11'sd512) ? (dx3 + 11'sd1024) : (dx3 > 11'sd512) ? (dx3 - 11'sd1024) : dx3;
    wire signed [10:0] dy3 = ent_y[3] - scroll_y;
    wire signed [10:0] sy3 = (dy3 < -11'sd512) ? (dy3 + 11'sd1024) : (dy3 > 11'sd512) ? (dy3 - 11'sd1024) : dy3;
    wire in_box3 = (px >= sx3) && (px < sx3 + 16) && (py >= sy3) && (py < sy3 + 16) && ent_active[3] && (ent_hp[3] > 0);

    wire signed [10:0] dx4 = ent_x[4] - scroll_x;
    wire signed [10:0] sx4 = (dx4 < -11'sd512) ? (dx4 + 11'sd1024) : (dx4 > 11'sd512) ? (dx4 - 11'sd1024) : dx4;
    wire signed [10:0] dy4 = ent_y[4] - scroll_y;
    wire signed [10:0] sy4 = (dy4 < -11'sd512) ? (dy4 + 11'sd1024) : (dy4 > 11'sd512) ? (dy4 - 11'sd1024) : dy4;
    wire in_box4 = (px >= sx4) && (px < sx4 + 16) && (py >= sy4) && (py < sy4 + 16) && ent_active[4] && (ent_hp[4] > 0);

    wire signed [10:0] dx5 = ent_x[5] - scroll_x;
    wire signed [10:0] sx5 = (dx5 < -11'sd512) ? (dx5 + 11'sd1024) : (dx5 > 11'sd512) ? (dx5 - 11'sd1024) : dx5;
    wire signed [10:0] dy5 = ent_y[5] - scroll_y;
    wire signed [10:0] sy5 = (dy5 < -11'sd512) ? (dy5 + 11'sd1024) : (dy5 > 11'sd512) ? (dy5 - 11'sd1024) : dy5;
    wire in_box5 = (px >= sx5) && (px < sx5 + 16) && (py >= sy5) && (py < sy5 + 16) && ent_active[5] && (ent_hp[5] > 0);

    wire signed [10:0] dx6 = ent_x[6] - scroll_x;
    wire signed [10:0] sx6 = (dx6 < -11'sd512) ? (dx6 + 11'sd1024) : (dx6 > 11'sd512) ? (dx6 - 11'sd1024) : dx6;
    wire signed [10:0] dy6 = ent_y[6] - scroll_y;
    wire signed [10:0] sy6 = (dy6 < -11'sd512) ? (dy6 + 11'sd1024) : (dy6 > 11'sd512) ? (dy6 - 11'sd1024) : dy6;
    wire in_box6 = (px >= sx6) && (px < sx6 + 16) && (py >= sy6) && (py < sy6 + 16) && ent_active[6] && (ent_hp[6] > 0);

    wire signed [10:0] dx7 = ent_x[7] - scroll_x;
    wire signed [10:0] sx7 = (dx7 < -11'sd512) ? (dx7 + 11'sd1024) : (dx7 > 11'sd512) ? (dx7 - 11'sd1024) : dx7;
    wire signed [10:0] dy7 = ent_y[7] - scroll_y;
    wire signed [10:0] sy7 = (dy7 < -11'sd512) ? (dy7 + 11'sd1024) : (dy7 > 11'sd512) ? (dy7 - 11'sd1024) : dy7;
    wire in_box7 = (px >= sx7) && (px < sx7 + 16) && (py >= sy7) && (py < sy7 + 16) && ent_active[7] && (ent_hp[7] > 0);

    // Prioriteitskiezer (Slot 0 heeft voorrang)
    reg [2:0] sel_id;
    reg       sel_active;
    reg [3:0] sel_u;
    reg [3:0] sel_v;

    always @(*) begin
        sel_active = 0;
        sel_id = 0;
        sel_u  = 0;
        sel_v  = 0;
        if (in_box0) begin
            sel_active = 1; sel_id = 0;
            sel_u = px[3:0] - sx0[3:0]; sel_v = py[3:0] - sy0[3:0];
        end else if (in_box1) begin
            sel_active = 1; sel_id = 1;
            sel_u = px[3:0] - sx1[3:0]; sel_v = py[3:0] - sy1[3:0];
        end else if (in_box2) begin
            sel_active = 1; sel_id = 2;
            sel_u = px[3:0] - sx2[3:0]; sel_v = py[3:0] - sy2[3:0];
        end else if (in_box3) begin
            sel_active = 1; sel_id = 3;
            sel_u = px[3:0] - sx3[3:0]; sel_v = py[3:0] - sy3[3:0];
        end else if (in_box4) begin
            sel_active = 1; sel_id = 4;
            sel_u = px[3:0] - sx4[3:0]; sel_v = py[3:0] - sy4[3:0];
        end else if (in_box5) begin
            sel_active = 1; sel_id = 5;
            sel_u = px[3:0] - sx5[3:0]; sel_v = py[3:0] - sy5[3:0];
        end else if (in_box6) begin
            sel_active = 1; sel_id = 6;
            sel_u = px[3:0] - sx6[3:0]; sel_v = py[3:0] - sy6[3:0];
        end else if (in_box7) begin
            sel_active = 1; sel_id = 7;
            sel_u = px[3:0] - sx7[3:0]; sel_v = py[3:0] - sy7[3:0];
        end
    end

    // Sprite slot bepalen (Wisselend animatieframe A/B)
    wire [4:0] cur_spr_slot = (ent_anim_frame[sel_id] == 0) ? ent_spr_base[sel_id] : ent_spr_alt[sel_id];

    // Schade-knipperen (invulnerability flash)
    wire hurt_flash_hide = (ent_hurt_timer[sel_id] > 0) && ent_hurt_timer[sel_id][1];
    wire final_hit = sel_active && !hurt_flash_hide;

    // Pipeline Fase 1: Adres berekenen en BRAM uitlezen
    reg pipe1_active = 0;
    always @(posedge clk_pixel) begin
        pipe1_active <= final_hit;
        spr_read_addr <= {cur_spr_slot, sel_v, sel_u};
    end

    // Pipeline Fase 2: Kleur doorsturen naar compositor (0xE3 = transparant)
    always @(posedge clk_pixel) begin
        if (pipe1_active) begin
            entity_color <= spr_read_data;
        end else begin
            entity_color <= 8'hE3; // Transparant
        end
    end

endmodule
