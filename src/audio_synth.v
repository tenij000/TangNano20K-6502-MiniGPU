`timescale 1ns / 1ps

// ============================================================================
// MiniGPU 16-Bit Stereo FM / Wavetable / ADSR & Multi-FX Sound Card (v2.2)
// Runs at 74.25 MHz (clk_pixel) with 48 kHz Stereo HDMI Audio Output.
// Uses a 4-stage registered pipeline per channel (20 clocks out of 1546 per
// 48 kHz sample) for clean timing and 0 BSRAMs.
//
// 8 Built-in Instruments (selectable per channel via $A00A or phase_inc[23:20]):
//   0: Grand Piano / E-Piano (2-Operator FM hammer strike + warm string body)
//   1: Hammond / Kerkorgel   (4-Drawbar Additive Sine 1x+2x+3x+4x + Vibrato)
//   2: Strijkers / Strings   (Dual Detuned SuperSaw + Slow Bow Attack + Filter)
//   3: Akoestische Gitaar    (Harmonic Karplus-style Pluck + Dynamic Low-Pass)
//   4: Koperblazers / Brass  (Saw + 2x FM Brass Lip-Swell Attack + Vibrato)
//   5: Diepe Sub-Bas / Slap  (Fundamental Sine + Triangle Sub + Slap Harmonic)
//   6: FM Kerkklok / Marimba (Inharmonic 1 : 3.5 FM Bell Shimmer)
//   7: Retro 8-Bit / Smart Drums (CH0-2: Classic 8-bit, CH3: Kick/Snare/HiHat)
// ============================================================================

module audio_synth (
    input  wire               clk_pixel,      // 74.25 MHz
    input  wire               rst_n,
    input  wire               audio_we,
    input  wire [1:0]         audio_channel,
    input  wire [23:0]        phase_inc,
    input  wire [7:0]         volume,

    // CPU configuration registers ($A00A = Instrument, $A00B = FX/ADSR control, $A016 = 8-bit PCM DAC)
    input  wire               cfg_inst_we,
    input  wire [7:0]         cfg_inst_data,
    input  wire [7:0]         cfg_fx_mode,    // Bit0=Auto-ADSR, Bit1=LPF, Bit2=Stereo, Bit3=Vibrato
    input  wire [7:0]         pcm_sample,     // $A016: 8-bit Unsigned PCM Sample (128 = silence)
    input  wire [2:0]         pcm_rate,       // Active PCM sample rate code (1=8kHz .. 7=32kHz)

    output reg                clk_audio,      // 48 kHz HDMI Audio Clock
    output reg signed [15:0]  sample_out_l,   // 16-bit Left Channel
    output reg signed [15:0]  sample_out_r    // 16-bit Right Channel
);

    // --- Per-Channel State Registers ---
    reg [19:0] ch_phase_inc [0:3];
    reg [7:0]  ch_vol       [0:3];
    reg [2:0]  ch_inst      [0:3];
    reg [23:0] ch_phase     [0:3];
    reg [23:0] ch_phase2    [0:3]; // Detuned 2nd oscillator / 3.5x FM modulator phase

    // Hardware Envelopes (updated at 3 kHz = 48 kHz / 16 via env_tick)
    reg [15:0] ch_amp_env    [0:3]; // 16-bit amplitude envelope (0..65535)
    reg [15:0] ch_bright_env [0:3]; // 16-bit FM/harmonic brightness envelope
    reg        ch_attack_ph  [0:3]; // 1 = in rising attack phase (Strings/Brass)
    reg [10:0] ch_write_age  [0:3]; // 48 kHz ticks since last audio_we (for repeat-note detection)

    // Per-Channel Warm 1-Pole Low-Pass Filter & Output state
    reg signed [15:0] ch_lpf [0:3];
    reg signed [15:0] ch_out [0:3];

    // Note-On / Note-Off request flags between write logic and 48 kHz state machine
    reg [3:0] note_trig_req = 4'b0000;
    reg [3:0] note_off_req  = 4'b0000;
    reg [3:0] note_trig_ack = 4'b0000;
    reg [3:0] note_off_ack  = 4'b0000;

    // Synchronize CPU $A00A / $A00B / $A016 into clk_pixel domain
    reg [2:0] cfg_we_sync   = 3'b000;
    reg [7:0] cfg_data_lat  = 8'h08;
    reg [7:0] fx_mode_sync  = 8'h07;
    reg [7:0] pcm_sync0     = 8'h80;
    reg [7:0] pcm_sync1     = 8'h80;
    reg [2:0] pcm_rate_sync = 3'd1;
    always @(posedge clk_pixel) begin
        cfg_we_sync   <= {cfg_we_sync[1:0], cfg_inst_we};
        if (cfg_inst_we) cfg_data_lat <= cfg_inst_data;
        fx_mode_sync  <= cfg_fx_mode;
        pcm_sync0     <= pcm_sample;
        pcm_sync1     <= pcm_sync0;
        pcm_rate_sync <= pcm_rate;
    end
    wire cfg_inst_pulse = cfg_we_sync[1] && !cfg_we_sync[2];

    // 8-Bit Unsigned PCM DAC ($A016) -> 16-Bit Signed 48 kHz 3-Pole Anti-Aliasing Interpolation Filter
    // Scaled by 192x (128x + 64x = -2.5 dBFS full-bodied volume without clipping HDMI sinks!)
    wire signed [8:0]  pcm_centered = $signed({1'b0, pcm_sync1}) - 9'sd128;
    wire signed [15:0] pcm_x128     = $signed({pcm_centered[8], pcm_centered[7:0], 7'b0});
    wire signed [15:0] pcm_x64      = $signed({{2{pcm_centered[8]}}, pcm_centered[7:0], 6'b0});
    wire signed [15:0] pcm_target   = (pcm_sync1 == 8'h80) ? 16'sd0 : (pcm_x128 + pcm_x64);
    reg  signed [15:0] pcm_lpf1     = 16'sd0;
    reg  signed [15:0] pcm_lpf2     = 16'sd0;
    reg  signed [15:0] pcm_lpf3     = 16'sd0;
    wire signed [16:0] pcm_diff1    = $signed({pcm_target[15], pcm_target}) - $signed({pcm_lpf1[15], pcm_lpf1});
    wire signed [16:0] pcm_diff2    = $signed({pcm_lpf1[15], pcm_lpf1})     - $signed({pcm_lpf2[15], pcm_lpf2});
    wire signed [16:0] pcm_diff3    = $signed({pcm_lpf2[15], pcm_lpf2})     - $signed({pcm_lpf3[15], pcm_lpf3});
    wire               pcm_hi_rate  = (pcm_rate_sync == 3'd3) || (pcm_rate_sync == 3'd4) ||
                                      (pcm_rate_sync == 3'd6) || (pcm_rate_sync == 3'd7);
    wire signed [15:0] pcm_step1    = $signed(pcm_diff1[16:1]);
    wire signed [15:0] pcm_step2    = pcm_hi_rate ? $signed(pcm_diff2[16:1]) : $signed({{2{pcm_diff2[16]}}, pcm_diff2[16:2]});
    wire signed [15:0] pcm_step3    = pcm_hi_rate ? $signed(pcm_diff3[16:1]) : $signed({{2{pcm_diff3[16]}}, pcm_diff3[16:2]});

    // Stereo Chorus Delay Line (16 samples at 48 kHz = ~0.33 ms Stereo spread in FFs)
    reg signed [15:0] chorus_buf [0:15] /* synthesis syn_ramstyle = "registers" */;
    reg [3:0]         chorus_wr = 4'd0;

    integer k;
    initial begin
        ch_inst[0] = 3'd0; // CH0 Default: Grand Piano / E-Piano
        ch_inst[1] = 3'd2; // CH1 Default: Warm Strings / Pad
        ch_inst[2] = 3'd5; // CH2 Default: Deep Sub-Bass / Organ
        ch_inst[3] = 3'd7; // CH3 Default: Smart Drum & Percussion Synth
        for (k = 0; k < 4; k = k + 1) begin
            ch_phase_inc[k]  = 20'd0;
            ch_vol[k]        = 8'd0;
            ch_phase[k]      = 24'd0;
            ch_phase2[k]     = 24'd0;
            ch_amp_env[k]    = 16'd0;
            ch_bright_env[k] = 16'd0;
            ch_attack_ph[k]  = 1'b0;
            ch_write_age[k]  = 11'd2047;
            ch_lpf[k]        = 16'sd0;
            ch_out[k]        = 16'sd0;
        end
        for (k = 0; k < 16; k = k + 1) begin
            chorus_buf[k] = 16'sd0;
        end
        clk_audio    = 1'b0;
        sample_out_l = 16'sd0;
        sample_out_r = 16'sd0;
    end

    // --- Handle Instrument Config ($A00A) and Note Writes (CMD 16) ---
    wire [19:0] new_inc = phase_inc[19:0];
    wire [3:0]  hi_inst = phase_inc[23:20];

    always @(posedge clk_pixel) begin
        if (!rst_n) begin
            ch_inst[0] <= 3'd0;
            ch_inst[1] <= 3'd2;
            ch_inst[2] <= 3'd5;
            ch_inst[3] <= 3'd7;
            for (k = 0; k < 4; k = k + 1) begin
                ch_vol[k]       <= 8'd0;
                ch_phase_inc[k] <= 20'd0;
                note_trig_req[k]<= 1'b0;
                note_off_req[k] <= 1'b0;
            end
        end else begin
            // 1. CPU POKE $A00A instrument selection
            if (cfg_inst_pulse) begin
                if (cfg_data_lat < 8'd8) begin
                    // 0..7: Set all melodic channels (CH0..CH2) to instrument 0..7
                    ch_inst[0] <= cfg_data_lat[2:0];
                    ch_inst[1] <= cfg_data_lat[2:0];
                    ch_inst[2] <= cfg_data_lat[2:0];
                    ch_inst[3] <= 3'd7;
                end else if (cfg_data_lat == 8'd8) begin
                    // 8: Restore Default Studio Mix (Piano + Strings + Bass + Smart Drums)
                    ch_inst[0] <= 3'd0;
                    ch_inst[1] <= 3'd2;
                    ch_inst[2] <= 3'd5;
                    ch_inst[3] <= 3'd7;
                end else begin
                    // >= 16: Set specific channel (bits [5:4] = ch, bits [2:0] = inst)
                    ch_inst[cfg_data_lat[5:4]] <= cfg_data_lat[2:0];
                end
            end

            // Clear handshake requests once acknowledged by 48 kHz engine
            for (k = 0; k < 4; k = k + 1) begin
                if (note_trig_ack[k]) note_trig_req[k] <= 1'b0;
                if (note_off_ack[k])  note_off_req[k]  <= 1'b0;
            end

            // 2. MiniGPU CMD 16 / SOUND write
            if (audio_we) begin
                // Optional inline instrument override in phase_inc[23:20] (1..8 -> inst 0..7)
                if (hi_inst >= 4'd1 && hi_inst <= 4'd8) begin
                    ch_inst[audio_channel] <= hi_inst[2:0] - 3'd1;
                end

                if (volume == 8'd0 || new_inc == 20'd0) begin
                    ch_vol[audio_channel]       <= 8'd0;
                    ch_phase_inc[audio_channel] <= 20'd0;
                    note_off_req[audio_channel] <= 1'b1;
                end else begin
                    // Detect Note-On vs 100 Hz software volume envelope step:
                    if (ch_vol[audio_channel] == 8'd0 ||
                        new_inc != ch_phase_inc[audio_channel] ||
                        volume > ch_vol[audio_channel] ||
                        (volume == ch_vol[audio_channel] && ch_write_age[audio_channel] > 11'd600)) begin
                        note_trig_req[audio_channel] <= 1'b1;
                    end
                    ch_phase_inc[audio_channel] <= new_inc;
                    ch_vol[audio_channel]       <= volume;
                end
            end
        end
    end

    // --- Exact 48.000000 kHz Sample Clock Generator locked to 74.25 MHz ---
    // 74,250,000 / 48,000 = 1546.875 clocks/sample (7 * 1547 + 1 * 1546 = 12,375 clocks per 8 samples)
    // Produces exact HDMI ACR CTS = 74,250 (0.000 ppm drift) so HDMI monitors never drop audio or blank!
    reg [10:0] sample_div  = 11'd0;
    reg [2:0]  sample_frac = 3'd0;
    wire [10:0] sample_period = (sample_frac == 3'd7) ? 11'd1545 : 11'd1546;
    reg        sample_tick = 1'b0;
    always @(posedge clk_pixel) begin
        if (!rst_n) begin
            sample_div  <= 11'd0;
            sample_frac <= 3'd0;
            clk_audio   <= 1'b0;
            sample_tick <= 1'b0;
        end else if (sample_div >= sample_period) begin
            sample_div  <= 11'd0;
            sample_frac <= sample_frac + 3'd1;
            clk_audio   <= 1'b1;
            sample_tick <= 1'b1;
        end else begin
            sample_div  <= sample_div + 11'd1;
            sample_tick <= 1'b0;
            if (sample_div == 11'd773)
                clk_audio <= 1'b0;
        end
    end

    // --- 3 kHz Envelope Prescaler (48 kHz / 16 = 3,000 Hz = 0.333 ms per tick) ---
    reg [3:0] env_div  = 4'd0;
    wire      env_tick = (env_div == 4'd0);

    // --- Global 6 Hz Vibrato / Chorus LFO (updated at 48 kHz) ---
    reg [15:0] lfo_phase = 16'd0;
    wire [7:0] lfo_tri   = lfo_phase[15] ? ~lfo_phase[14:7] : lfo_phase[14:7];
    wire signed [8:0] lfo_signed = $signed({1'b0, lfo_tri}) - 9'sd128; // -128..+127

    // --- 17-bit LFSR Noise & Metallic Ring Generator ---
    reg [16:0] lfsr = 17'h1ACE1;

    // --- Quarter-Wave 256-Step Signed Sine Function (-127 .. +127) ---
    reg [7:0]        lut_theta;
    reg signed [8:0] lut_sin;
    reg [5:0]        lut_idx;
    reg [6:0]        lut_mag;
    always @(*) begin
        lut_idx = lut_theta[6] ? ~lut_theta[5:0] : lut_theta[5:0];
        case (lut_idx)
            6'd0:  lut_mag = 7'd0;   6'd1:  lut_mag = 7'd3;   6'd2:  lut_mag = 7'd6;   6'd3:  lut_mag = 7'd9;
            6'd4:  lut_mag = 7'd12;  6'd5:  lut_mag = 7'd16;  6'd6:  lut_mag = 7'd19;  6'd7:  lut_mag = 7'd22;
            6'd8:  lut_mag = 7'd25;  6'd9:  lut_mag = 7'd28;  6'd10: lut_mag = 7'd31;  6'd11: lut_mag = 7'd34;
            6'd12: lut_mag = 7'd37;  6'd13: lut_mag = 7'd40;  6'd14: lut_mag = 7'd43;  6'd15: lut_mag = 7'd46;
            6'd16: lut_mag = 7'd49;  6'd17: lut_mag = 7'd51;  6'd18: lut_mag = 7'd54;  6'd19: lut_mag = 7'd57;
            6'd20: lut_mag = 7'd60;  6'd21: lut_mag = 7'd63;  6'd22: lut_mag = 7'd65;  6'd23: lut_mag = 7'd68;
            6'd24: lut_mag = 7'd71;  6'd25: lut_mag = 7'd73;  6'd26: lut_mag = 7'd76;  6'd27: lut_mag = 7'd78;
            6'd28: lut_mag = 7'd81;  6'd29: lut_mag = 7'd83;  6'd30: lut_mag = 7'd85;  6'd31: lut_mag = 7'd88;
            6'd32: lut_mag = 7'd90;  6'd33: lut_mag = 7'd92;  6'd34: lut_mag = 7'd94;  6'd35: lut_mag = 7'd96;
            6'd36: lut_mag = 7'd98;  6'd37: lut_mag = 7'd100; 6'd38: lut_mag = 7'd102; 6'd39: lut_mag = 7'd104;
            6'd40: lut_mag = 7'd106; 6'd41: lut_mag = 7'd107; 6'd42: lut_mag = 7'd109; 6'd43: lut_mag = 7'd111;
            6'd44: lut_mag = 7'd112; 6'd45: lut_mag = 7'd113; 6'd46: lut_mag = 7'd115; 6'd47: lut_mag = 7'd116;
            6'd48: lut_mag = 7'd117; 6'd49: lut_mag = 7'd118; 6'd50: lut_mag = 7'd120; 6'd51: lut_mag = 7'd121;
            6'd52: lut_mag = 7'd122; 6'd53: lut_mag = 7'd122; 6'd54: lut_mag = 7'd123; 6'd55: lut_mag = 7'd124;
            6'd56: lut_mag = 7'd125; 6'd57: lut_mag = 7'd125; 6'd58: lut_mag = 7'd126; 6'd59: lut_mag = 7'd126;
            6'd60: lut_mag = 7'd126; 6'd61: lut_mag = 7'd127; 6'd62: lut_mag = 7'd127; 6'd63: lut_mag = 7'd127;
        endcase
        lut_sin = lut_theta[7] ? -$signed({2'b00, lut_mag}) : $signed({2'b00, lut_mag});
    end

    // --- 4-Stage Per-Channel Pipeline State Machine ---
    reg        pipe_run = 1'b0;
    reg [1:0]  cur_ch   = 2'd0;
    reg [1:0]  sub_step = 2'd0;
    reg        mix_step = 1'b0;

    // Pipeline registers between sub_steps
    reg signed [8:0]  r_s_mod     = 9'sd0;
    reg signed [8:0]  r_s_th3     = 9'sd0;
    reg [7:0]         r_fm_offset = 8'd0;
    reg [8:0]         r_gain9     = 9'd0;
    reg signed [10:0] r_raw_wave  = 11'sd0;

    // Current channel signals
    wire [23:0] p1      = ch_phase[cur_ch];
    wire [23:0] p2      = ch_phase2[cur_ch];
    wire [19:0] inc_cur = ch_phase_inc[cur_ch];
    wire [2:0]  inst    = ch_inst[cur_ch];
    wire [7:0]  br_env  = ch_bright_env[cur_ch][15:8];
    wire [7:0]  am_env  = ch_amp_env[cur_ch][15:8];
    wire        ch_act  = (ch_vol[cur_ch] != 8'd0) && (inc_cur != 20'd0);

    // Harmonic phases: 1x, 2x, 3x, 4x, and 3.5x (for FM Bell)
    wire [7:0] th1       = p1[23:16];
    wire [7:0] th2       = p1[22:15];
    wire [7:0] th3       = p1[23:16] + p1[22:15];
    wire [7:0] th4       = p1[21:14];
    wire [7:0] th_bell   = p2[23:16];
    wire [7:0] mod_theta = (inst == 3'd6) ? th_bell : th2;

    // Time-multiplex the single Sine LUT across sub_step 0, 1, 2:
    always @(*) begin
        case (sub_step)
            2'd0:    lut_theta = mod_theta;
            2'd1:    lut_theta = (inst == 3'd1 && p1[16]) ? th4 : th3;
            default: lut_theta = th1 + r_fm_offset;
        endcase
    end

    // FM modulation index:
    wire [7:0] fm_depth = (inst == 3'd0) ? ((br_env >> 2) + 8'd22) :
                          (inst == 3'd4) ? ((br_env >> 2) + 8'd36) :
                          (inst == 3'd6) ? ((br_env >> 1) + 8'd48) :
                          (inst == 3'd5) ? (br_env >> 2) : 8'd0;

    // Multiplier 1 (used in sub_step 1): FM modulator * fm_depth
    wire signed [17:0] fm_prod = r_s_mod * $signed({1'b0, fm_depth});

    // Multiplier 2 (used in sub_step 1): Software volume * ADSR envelope
    wire [7:0]  eff_env = fx_mode_sync[0] ? am_env : (ch_act ? 8'd235 : 8'd0);
    wire [15:0] gain16  = ch_vol[cur_ch] * eff_env;

    // Basic Geometric Waveforms (-128..+127)
    wire signed [8:0] saw1     = $signed({1'b0, p1[23:16]}) - 9'sd128;
    wire signed [8:0] saw2     = $signed({1'b0, p2[23:16]}) - 9'sd128;
    wire [7:0]        tri_u    = p1[23] ? ~p1[22:15] : p1[22:15];
    wire signed [8:0] tri_wave = $signed({1'b0, tri_u}) - 9'sd128;
    wire signed [8:0] sq50     = p1[23] ? 9'sd115 : -9'sd115;
    wire signed [8:0] sq25     = (p1[23:22] == 2'b00) ? 9'sd115 : -9'sd115;

    // Smart Drum Generator for CH3 (Kick / Snare / Hi-Hat based on frequency)
    wire is_kick  = (ch_phase_inc[3] < 20'd55000);
    wire is_snare = (ch_phase_inc[3] >= 20'd55000) && (ch_phase_inc[3] < 20'd220000);
    wire signed [8:0] noise_s = lfsr[0] ? 9'sd115 : -9'sd115;
    wire signed [8:0] metal_s = (lfsr[0] ^ p1[21] ^ p2[19]) ? 9'sd115 : -9'sd115;

    // Assemble raw waveform per instrument in sub_step 2 (using lut_sin as carrier!)
    reg signed [10:0] raw_wave_comb;
    always @(*) begin
        if (cur_ch == 2'd3 && inst == 3'd7) begin
            if (!fx_mode_sync[0]) begin
                raw_wave_comb = noise_s * 11'sd2;
            end else if (is_kick) begin
                raw_wave_comb = (lut_sin * 11'sd2) + ((br_env > 8'd180) ? (noise_s >>> 1) : 11'sd0);
            end else if (is_snare) begin
                raw_wave_comb = lut_sin + (noise_s * 11'sd2);
            end else begin
                raw_wave_comb = (metal_s * 11'sd2);
            end
        end else begin
            case (inst)
                3'd0: begin
                    // 0: Grand Piano / E-Piano (2-Op FM + 3rd harmonic hammer click)
                    raw_wave_comb = (lut_sin * 11'sd2) + ((br_env > 8'd110) ? (r_s_th3 >>> 1) : (r_s_th3 >>> 2));
                end
                3'd1: begin
                    // 1: Hammond / Kerkorgel (Drawbars: 1x + 2x + 3x/4x)
                    raw_wave_comb = lut_sin + (r_s_mod >>> 1) + (r_s_th3 >>> 1);
                end
                3'd2: begin
                    // 2: Strijkers / Strings & Warm Synth Pad (Dual Detuned SuperSaw + Octave)
                    raw_wave_comb = saw1 + saw2 + (r_s_mod >>> 1);
                end
                3'd3: begin
                    // 3: Akoestische Gitaar / Harp Pluck (Bright pick transient -> warm wood body)
                    raw_wave_comb = lut_sin + ((br_env > 8'd130) ? saw1 : (br_env > 8'd65) ? (saw1 >>> 1) : (tri_wave >>> 1));
                end
                3'd4: begin
                    // 4: Koperblazers / Synth Brass (Saw + 2x FM Brass Swell)
                    raw_wave_comb = lut_sin + saw1 + (r_s_th3 >>> 2);
                end
                3'd5: begin
                    // 5: Diepe Sub-Bas / Slap Bass (Fat Sine + Triangle Sub)
                    raw_wave_comb = (lut_sin * 11'sd2) + tri_wave;
                end
                3'd6: begin
                    // 6: FM Kerkklok / Marimba / Bell (1 : 3.5 Inharmonic FM Bell)
                    raw_wave_comb = (lut_sin * 11'sd2) + (r_s_th3 >>> 1);
                end
                3'd7: begin
                    // 7: Retro 8-Bit Chiptune (CH0=Sq50, CH1=Sq25, CH2=Tri)
                    raw_wave_comb = (cur_ch == 2'd0) ? (sq50 * 11'sd2) :
                                    (cur_ch == 2'd1) ? (sq25 * 11'sd2) : (tri_wave * 11'sd2);
                end
            endcase
        end
    end

    // Multiplier 3 (used in sub_step 3): Scale r_raw_wave by r_gain9 with +6dB boost
    wire signed [19:0] scaled_wave = r_raw_wave * $signed(r_gain9);
    wire signed [16:0] wave_boost  = $signed(scaled_wave[17:1]);
    wire signed [15:0] wave_16     = (r_gain9 == 9'd0) ? 16'sd0 :
                                     (wave_boost > 17'sd28000)  ? 16'sd28000 :
                                     (wave_boost < -17'sd28000) ? -16'sd28000 : wave_boost[15:0];

    // Properly Sign-Extended 1-Pole Warm Low-Pass Filter (used in sub_step 3)
    wire signed [15:0] lpf_cur       = ch_lpf[cur_ch];
    wire signed [16:0] lpf_diff      = $signed({wave_16[15], wave_16}) - $signed({lpf_cur[15], lpf_cur});
    wire signed [15:0] lpf_step_qtr  = {{2{lpf_diff[16]}}, lpf_diff[16:2]}; // Exact signed /4!
    wire signed [15:0] lpf_step_half = {lpf_diff[16], lpf_diff[16:1]};      // Exact signed /2!
    wire               deep_lpf      = (inst == 3'd2) || (inst == 3'd5) || (inst == 3'd3 && br_env < 8'd100);
    wire signed [15:0] lpf_next      = (r_gain9 == 9'd0 && (lpf_cur > -16'sd8 && lpf_cur < 16'sd8)) ? 16'sd0 :
                                       fx_mode_sync[1] ? (deep_lpf ? (lpf_cur + lpf_step_qtr) : (lpf_cur + lpf_step_half)) :
                                       wave_16;

    // Subtle natural pitch vibrato on all acoustic instruments (stronger on Organ/Strings/Brass)
    wire               strong_vib = fx_mode_sync[3] || (inst == 3'd1) || (inst == 3'd2) || (inst == 3'd4);
    wire signed [20:0] vib_prod   = $signed({1'b0, inc_cur[19:9]}) * lfo_signed;
    wire signed [23:0] vib_off    = !ch_act    ? 24'sd0 :
                                    strong_vib ? {{7{vib_prod[20]}}, vib_prod[20:4]} :
                                                 {{9{vib_prod[20]}}, vib_prod[20:6]};

    // Drum pitch-drop sweep for Kick & Snare on CH3
    wire [23:0] drum_sweep = (cur_ch == 2'd3 && inst == 3'd7 && fx_mode_sync[0] && ch_act) ?
                             (is_kick  ? {8'd0, ch_bright_env[3][15:0]} :
                              is_snare ? {9'd0, ch_bright_env[3][15:1]} : 24'd0) : 24'd0;

    // Phase 2 increment: 3.5x for Bell (inst 6), detuned 1.008x for Strings (inst 2), 2x otherwise
    wire [23:0] inc2_val = !ch_act       ? 24'd0 :
                           (inst == 3'd6) ? ({4'd0, inc_cur} + {3'd0, inc_cur, 1'b0} + {5'd0, inc_cur[19:1]}) :
                           (inst == 3'd2) ? ({4'd0, inc_cur} + {11'd0, inc_cur[19:7]} + 24'd18) :
                                            {3'd0, inc_cur, 1'b0};
    wire [23:0] next_p1  = ch_phase[cur_ch] + {4'd0, inc_cur} + drum_sweep + vib_off;

    // Stereo Chorus & Left/Right Mixing signals (evaluated during mix_step)
    // Note: Stereo Chorus is applied ONLY to the 4 FM synthesizer channels (synth_sum);
    // PCM / WAV / MP3 audio (pcm_lpf3) is mixed phase-coherently onto both Left & Right!
    wire [3:0]         chorus_tap     = chorus_wr - 4'd7 - lfo_tri[7:5];
    wire signed [15:0] chorus_delayed = chorus_buf[chorus_tap];
    wire signed [17:0] synth_sum      = $signed({{2{ch_out[0][15]}}, ch_out[0]}) +
                                        $signed({{2{ch_out[1][15]}}, ch_out[1]}) +
                                        $signed({{2{ch_out[2][15]}}, ch_out[2]}) +
                                        $signed({{2{ch_out[3][15]}}, ch_out[3]});
    wire signed [17:0] pcm_clean      = $signed({{2{pcm_lpf3[15]}}, pcm_lpf3});
    wire signed [17:0] mono_sum       = synth_sum + pcm_clean;

    wire signed [17:0] ch1_qtr        = $signed({{4{ch_out[1][15]}}, ch_out[1][15:2]});
    wire signed [17:0] ch0_qtr        = $signed({{4{ch_out[0][15]}}, ch_out[0][15:2]});
    wire signed [17:0] chor_half      = $signed({{3{chorus_delayed[15]}}, chorus_delayed[15:1]});

    wire signed [17:0] pan_l = synth_sum - ch1_qtr + chor_half + pcm_clean;
    wire signed [17:0] pan_r = synth_sum - ch0_qtr - chor_half + pcm_clean;

    wire signed [16:0] raw_l = fx_mode_sync[2] ? $signed(pan_l[16:0]) : $signed(mono_sum[16:0]);
    wire signed [16:0] raw_r = fx_mode_sync[2] ? $signed(pan_r[16:0]) : $signed(mono_sum[16:0]);

    // Soft-clipping limiter to 16-bit signed (-32767 .. +32767)
    wire signed [15:0] lim_l = (raw_l > 17'sd32767)  ? 16'sd32767 :
                               (raw_l < -17'sd32767) ? -16'sd32767 : raw_l[15:0];
    wire signed [15:0] lim_r = (raw_r > 17'sd32767)  ? 16'sd32767 :
                               (raw_r < -17'sd32767) ? -16'sd32767 : raw_r[15:0];

    // --- Main 48 kHz 4-Stage Sequential Pipeline ---
    always @(posedge clk_pixel) begin
        if (!rst_n) begin
            pipe_run      <= 1'b0;
            cur_ch        <= 2'd0;
            sub_step      <= 2'd0;
            mix_step      <= 1'b0;
            env_div       <= 4'd0;
            sample_out_l  <= 16'sd0;
            sample_out_r  <= 16'sd0;
            pcm_lpf1      <= 16'sd0;
            pcm_lpf2      <= 16'sd0;
            pcm_lpf3      <= 16'sd0;
            note_trig_ack <= 4'b0000;
            note_off_ack  <= 4'b0000;
            for (k = 0; k < 4; k = k + 1) begin
                ch_lpf[k] <= 16'sd0;
                ch_out[k] <= 16'sd0;
            end
        end else if (sample_tick) begin
            // Kick off 4-channel synthesis + 48 kHz 3-pole PCM anti-aliasing interpolation
            lfo_phase <= lfo_phase + 16'd819; // ~6 Hz vibrato/chorus LFO
            lfsr      <= {lfsr[15:0], lfsr[16] ^ lfsr[13]};
            env_div   <= env_div + 4'd1;      // Divide by 16 -> 3,000 Hz envelope clock
            pcm_lpf1  <= (pcm_sync1 == 8'h80 && pcm_lpf1 > -16'sd8 && pcm_lpf1 < 16'sd8) ? 16'sd0 : (pcm_lpf1 + pcm_step1);
            pcm_lpf2  <= (pcm_sync1 == 8'h80 && pcm_lpf2 > -16'sd8 && pcm_lpf2 < 16'sd8) ? 16'sd0 : (pcm_lpf2 + pcm_step2);
            pcm_lpf3  <= (pcm_sync1 == 8'h80 && pcm_lpf3 > -16'sd8 && pcm_lpf3 < 16'sd8) ? 16'sd0 : (pcm_lpf3 + pcm_step3);
            pipe_run  <= 1'b1;
            cur_ch    <= 2'd0;
            sub_step  <= 2'd0;
            mix_step  <= 1'b0;
        end else if (pipe_run) begin
            case (sub_step)
                2'd0: begin
                    // Stage 0: Latch sin8(mod_theta) & update ADSR envelopes for cur_ch
                    r_s_mod <= lut_sin;

                    if (note_off_req[cur_ch]) begin
                        note_off_ack[cur_ch] <= 1'b1;
                        ch_attack_ph[cur_ch] <= 1'b0;
                    end else begin
                        note_off_ack[cur_ch] <= 1'b0;
                    end

                    if (note_trig_req[cur_ch]) begin
                        note_trig_ack[cur_ch] <= 1'b1;
                        ch_write_age[cur_ch]  <= 11'd0;
                        ch_bright_env[cur_ch] <= 16'hFFFF;
                        if (cur_ch == 2'd3 && inst == 3'd7) begin
                            ch_phase[3] <= 24'd0;
                        end
                        if ((inst == 3'd2 || inst == 3'd4) && cur_ch != 2'd3) begin
                            ch_attack_ph[cur_ch] <= 1'b1;
                            if (ch_amp_env[cur_ch] < 16'h4000)
                                ch_amp_env[cur_ch] <= 16'h4000;
                        end else begin
                            ch_attack_ph[cur_ch] <= 1'b0;
                            ch_amp_env[cur_ch]   <= 16'hFFFF;
                        end
                    end else begin
                        note_trig_ack[cur_ch] <= 1'b0;
                        if (ch_write_age[cur_ch] != 11'd2047)
                            ch_write_age[cur_ch] <= ch_write_age[cur_ch] + 11'd1;

                        if (!ch_act) begin
                            // Fast anti-pop release (~6 ms at 48 kHz) to exact 0
                            if (ch_amp_env[cur_ch] > 16'd160)
                                ch_amp_env[cur_ch] <= ch_amp_env[cur_ch] - (ch_amp_env[cur_ch] >> 4) - 16'd96;
                            else
                                ch_amp_env[cur_ch] <= 16'd0;
                            ch_bright_env[cur_ch] <= 16'd0;
                        end else if (env_tick) begin
                            // Prescaled 3,000 Hz Envelope Updates (realistic musical time constants!):
                            // 1. Brightness / FM / Drum Pitch-Drop Envelope (~85 ms time constant)
                            if (ch_bright_env[cur_ch] > 16'd32)
                                ch_bright_env[cur_ch] <= ch_bright_env[cur_ch] - (ch_bright_env[cur_ch] >> 7) - 16'd16;
                            else
                                ch_bright_env[cur_ch] <= 16'd0;

                            // 2. Amplitude ADSR Envelope
                            if (ch_attack_ph[cur_ch]) begin
                                // Rising Attack phase (~90 ms for Strings, ~45 ms for Brass)
                                if (ch_amp_env[cur_ch] >= 16'hF800) begin
                                    ch_amp_env[cur_ch]   <= 16'hFFFF;
                                    ch_attack_ph[cur_ch] <= 1'b0;
                                end else begin
                                    ch_amp_env[cur_ch] <= ch_amp_env[cur_ch] + ((inst == 3'd2) ? 16'd240 : 16'd480);
                                end
                            end else if (cur_ch == 2'd3 && inst == 3'd7) begin
                                // Smart Drums percussive decay (~220 ms for Kick, ~140 ms for Snare/Hat)
                                if (ch_amp_env[3] > 16'd64)
                                    ch_amp_env[3] <= ch_amp_env[3] - (is_kick ? (ch_amp_env[3] >> 8) : (ch_amp_env[3] >> 7)) - 16'd24;
                                else
                                    ch_amp_env[3] <= 16'd0;
                            end else begin
                                case (inst)
                                    3'd1, 3'd2, 3'd4, 3'd7: begin
                                        // 1: Organ, 2: Strings, 4: Brass, 7: Chiptune -> Full rich sustain!
                                        ch_amp_env[cur_ch] <= 16'hFFFF;
                                    end
                                    3'd3, 3'd5: begin
                                        // 3: Guitar Pluck, 5: Slap Bass -> Pluck decay (~250ms) to 38% warm sustain floor
                                        if (ch_amp_env[cur_ch] > 16'h6000)
                                            ch_amp_env[cur_ch] <= ch_amp_env[cur_ch] - (ch_amp_env[cur_ch] >> 8) - 16'd8;
                                    end
                                    default: begin
                                        // 0: Grand Piano, 6: FM Bell -> Hammer/Bell decay (~400ms) to 45% warm sustain floor
                                        if (ch_amp_env[cur_ch] > 16'h7200)
                                            ch_amp_env[cur_ch] <= ch_amp_env[cur_ch] - (ch_amp_env[cur_ch] >> 9) - 16'd6;
                                    end
                                endcase
                            end
                        end
                    end
                    sub_step <= 2'd1;
                end

                2'd1: begin
                    // Stage 1: Latch sin8(th3), FM offset (r_s_mod * fm_depth), and gain9 (vol * env)
                    r_s_th3     <= lut_sin;
                    r_fm_offset <= fm_prod[15:8];
                    r_gain9     <= {1'b0, gain16[15:8]};
                    sub_step    <= 2'd2;
                end

                2'd2: begin
                    // Stage 2: Latch assembled waveform (using lut_sin = sin8(th1 + r_fm_offset))
                    r_raw_wave  <= raw_wave_comb;
                    sub_step    <= 2'd3;
                end

                2'd3: begin
                    // Stage 3: Scale by envelope, update sign-safe LPF & advance phase
                    ch_lpf[cur_ch] <= lpf_next;
                    ch_out[cur_ch] <= lpf_next;

                    if (cur_ch == 2'd3 && ch_act && (ch_phase[3][23] != next_p1[23])) begin
                        lfsr <= {lfsr[15:0], lfsr[16] ^ lfsr[13]};
                    end
                    if (ch_act) begin
                        ch_phase[cur_ch]  <= next_p1;
                        ch_phase2[cur_ch] <= ch_phase2[cur_ch] + inc2_val;
                    end else if (r_gain9 == 9'd0) begin
                        ch_phase[cur_ch]  <= 24'd0;
                        ch_phase2[cur_ch] <= 24'd0;
                    end

                    sub_step <= 2'd0;
                    if (cur_ch == 2'd3) begin
                        pipe_run <= 1'b0;
                        mix_step <= 1'b1;
                    end else begin
                        cur_ch <= cur_ch + 2'd1;
                    end
                end
            endcase
        end else if (mix_step) begin
            mix_step      <= 1'b0;
            note_trig_ack <= 4'b0000;
            note_off_ack  <= 4'b0000;

            // Update 16-tap stereo chorus buffer (FM synth only) and latch Left/Right 16-bit HDMI samples
            chorus_buf[chorus_wr] <= $signed(synth_sum[16:1]);
            chorus_wr             <= chorus_wr + 4'd1;
            sample_out_l          <= lim_l;
            sample_out_r          <= lim_r;
        end
    end

endmodule
