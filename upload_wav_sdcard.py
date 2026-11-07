import os
import sys
import wave
import math
import time
import struct
import ctypes
import tempfile
import subprocess
import serial
import sd_tools

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WAV_DIR = os.path.join(BASE_DIR, "wav_tracks")


class _ACMSTREAMHEADER(ctypes.Structure):
    _pack_ = 1
    _fields_ = [
        ("cbStruct", ctypes.c_uint32),
        ("fdwStatus", ctypes.c_uint32),
        ("dwUser", ctypes.c_size_t),
        ("pbSrc", ctypes.c_void_p),
        ("cbSrcLength", ctypes.c_uint32),
        ("cbSrcLengthUsed", ctypes.c_uint32),
        ("dwSrcUser", ctypes.c_size_t),
        ("pbDst", ctypes.c_void_p),
        ("cbDstLength", ctypes.c_uint32),
        ("cbDstLengthUsed", ctypes.c_uint32),
        ("dwDstUser", ctypes.c_size_t),
        ("dwReservedDriver", ctypes.c_size_t * 15),
    ]


def ensure_wav_file(filepath):
    """If filepath is an .MP3 file, decode it via Windows ACM (l3codeca.acm) to a temporary 16-bit .WAV file and return its path."""
    if not filepath.lower().endswith(".mp3"):
        return filepath

    cache_dir = os.path.join(tempfile.gettempdir(), "tang_nano_mp3_cache")
    os.makedirs(cache_dir, exist_ok=True)
    stat = os.stat(filepath)
    cache_name = f"{os.path.splitext(os.path.basename(filepath))[0]}_{int(stat.st_size)}_{int(stat.st_mtime)}.wav"
    out_wav = os.path.join(cache_dir, cache_name)
    if os.path.exists(out_wav) and os.path.getsize(out_wav) > 100:
        return out_wav

    mp3_bytes = open(filepath, "rb").read()
    off = 0
    if mp3_bytes[:3] == b"ID3" and len(mp3_bytes) >= 10:
        sz = (
            ((mp3_bytes[6] & 0x7F) << 21)
            | ((mp3_bytes[7] & 0x7F) << 14)
            | ((mp3_bytes[8] & 0x7F) << 7)
            | (mp3_bytes[9] & 0x7F)
        )
        off = 10 + sz

    while off < len(mp3_bytes) - 4:
        if mp3_bytes[off] == 0xFF and (mp3_bytes[off + 1] & 0xE0) == 0xE0:
            hdr_b = mp3_bytes[off : off + 4]
            layer = (hdr_b[1] >> 1) & 3
            br_idx = (hdr_b[2] >> 4) & 0x0F
            sr_idx = (hdr_b[2] >> 2) & 0x03
            if layer != 0 and br_idx not in (0, 15) and sr_idx != 3:
                break
        off += 1

    hdr_b = mp3_bytes[off : off + 4] if off < len(mp3_bytes) - 4 else b"\xff\xfb\x90\x00"
    sr_tbl = [44100, 48000, 32000, 44100]
    ver = (hdr_b[1] >> 3) & 3
    sr = sr_tbl[(hdr_b[2] >> 2) & 3]
    if ver == 2:
        sr //= 2
    elif ver == 0:
        sr //= 4
    ch = 1 if ((hdr_b[3] >> 6) & 3) == 3 else 2

    msacm32 = ctypes.windll.msacm32
    src_fmt = struct.pack("<HHIIHHHHIHHH", 0x0055, ch, sr, 16000, 1, 0, 12, 1, 2, 417, 1, 0)
    dst_fmt = struct.pack("<HHIIHHH", 1, ch, sr, sr * ch * 2, ch * 2, 16, 0)

    has = ctypes.c_void_p()
    res = msacm32.acmStreamOpen(ctypes.byref(has), None, src_fmt, dst_fmt, None, 0, 0, 4)
    if res != 0:
        raise RuntimeError(f"Windows MP3 ACM codec fout (code {res})")

    try:
        payload = mp3_bytes[off:]
        src_buf = ctypes.create_string_buffer(payload)
        dst_cap = max(65536, len(payload) * 14)
        dst_buf = ctypes.create_string_buffer(dst_cap)

        cbs = 128 if ctypes.sizeof(ctypes.c_void_p) == 8 else 84
        ash = _ACMSTREAMHEADER()
        ash.cbStruct = cbs
        ash.pbSrc = ctypes.cast(src_buf, ctypes.c_void_p)
        ash.cbSrcLength = len(payload)
        ash.pbDst = ctypes.cast(dst_buf, ctypes.c_void_p)
        ash.cbDstLength = dst_cap

        if msacm32.acmStreamPrepareHeader(has, ctypes.byref(ash), 0) != 0:
            raise RuntimeError("acmStreamPrepareHeader mislukt")
        try:
            msacm32.acmStreamConvert(has, ctypes.byref(ash), 0)
            pcm_data = dst_buf.raw[: ash.cbDstLengthUsed]
        finally:
            msacm32.acmStreamUnprepareHeader(has, ctypes.byref(ash), 0)
    finally:
        msacm32.acmStreamClose(has, 0)

    with wave.open(out_wav, "wb") as wf:
        wf.setnchannels(ch)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm_data)
    return out_wav


def load_and_resample_wav(filepath, target_rate=11025, num_samples=32768):
    """Read any 8-bit or 16-bit Mono/Stereo .WAV or .MP3 file, normalize, and resample to 8-bit unsigned PCM."""
    filepath = ensure_wav_file(filepath)
    with wave.open(filepath, "rb") as wf:
        n_channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)

    # Decode to float [-1.0, +1.0]
    mono = []
    if sampwidth == 2:
        total_shorts = len(raw) // 2
        shorts = struct.unpack(f"<{total_shorts}h", raw[: total_shorts * 2])
        for i in range(0, len(shorts), n_channels):
            mono.append(shorts[i] / 32768.0)
    elif sampwidth == 1:
        for i in range(0, len(raw), n_channels):
            mono.append((raw[i] - 128) / 128.0)
    else:
        # 24-bit or 32-bit
        step = sampwidth * n_channels
        for i in range(0, len(raw) - step + 1, step):
            val = int.from_bytes(raw[i : i + sampwidth], "little", signed=True)
            mono.append(val / float(1 << (8 * sampwidth - 1)))

    if not mono:
        return bytearray([128] * num_samples)

    # Trim leading near-silence
    start_idx = 0
    for idx, s in enumerate(mono):
        if abs(s) > 0.02:
            start_idx = max(0, idx - int(framerate * 0.02))
            break
    mono = mono[start_idx:]

    # Apply Blackman-windowed Sinc anti-aliasing low-pass filter before downsampling
    if framerate > target_rate and len(mono) >= 33:
        cutoff = (target_rate * 0.43) / float(framerate)
        n_taps = 49
        mid = n_taps // 2
        kernel = []
        for k in range(n_taps):
            x = k - mid
            sinc = 1.0 if x == 0 else math.sin(2.0 * math.pi * cutoff * x) / (math.pi * x)
            win = 0.42 - 0.5 * math.cos(2.0 * math.pi * k / (n_taps - 1)) + 0.08 * math.cos(4.0 * math.pi * k / (n_taps - 1))
            kernel.append(sinc * win)
        ksum = sum(kernel)
        kernel = [w / ksum for w in kernel]
        try:
            import numpy as np
            mono = np.convolve(np.array(mono, dtype=np.float64), np.array(kernel, dtype=np.float64), mode="same").tolist()
        except ImportError:
            pass

    # Resample to target_rate
    out_floats = []
    ratio = float(framerate) / float(target_rate)
    for i in range(num_samples):
        src_pos = i * ratio
        idx = int(src_pos)
        if idx >= len(mono) - 1:
            out_floats.append(0.0)
        else:
            frac = src_pos - idx
            out_floats.append(mono[idx] * (1.0 - frac) + mono[idx + 1] * frac)

    # Remove DC offset
    mean_v = sum(out_floats) / max(1, len(out_floats))
    out_floats = [x - mean_v for x in out_floats]

    # Peak normalize cleanly without harsh clipping
    peak = max(max(abs(x) for x in out_floats), 0.01)
    out_bytes = bytearray(num_samples)
    for i, x in enumerate(out_floats):
        comp = (x / peak) * 0.90
        # Apply smooth 30ms fade-out at end to prevent loop/end click
        if i > num_samples - 300:
            comp *= (num_samples - 1 - i) / 300.0
        b = int(round(128.0 + comp * 78.0))
        out_bytes[i] = max(40, min(216, b))
    return out_bytes


def save_pcm8_wav(filepath, pcm_bytes, sample_rate):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with wave.open(filepath, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(1)
        wf.setframerate(sample_rate)
        wf.writeframes(bytes(pcm_bytes))


def load_real_wav_slice(filepath, start_s, dur_s, out_len, target_rate=8000, gain=1.0):
    """Load a slice [start_s : start_s + dur_s] from a real .WAV or .MP3 file, anti-alias filter, resample to target_rate, and normalize cleanly."""
    filepath = ensure_wav_file(filepath)
    with wave.open(filepath, "rb") as wf:
        n_ch = wf.getnchannels()
        sw = wf.getsampwidth()
        sr = wf.getframerate()
        raw = wf.readframes(wf.getnframes())

    if sw == 2:
        shorts = struct.unpack(f"<{len(raw) // 2}h", raw[: (len(raw) // 2) * 2])
        if n_ch == 2:
            mono = [(shorts[i] + shorts[i + 1]) / 65536.0 for i in range(0, len(shorts) - 1, 2)]
        else:
            mono = [shorts[i] / 32768.0 for i in range(0, len(shorts), n_ch)]
    else:
        mono = [(raw[i] - 128) / 128.0 for i in range(0, len(raw), n_ch)]

    i0 = max(0, int(start_s * sr))
    i1 = min(len(mono), int((start_s + dur_s) * sr))
    seg = mono[i0:i1]
    if not seg:
        return [0.0] * out_len

    # Remove DC offset
    mean_v = sum(seg) / len(seg)
    seg = [x - mean_v for x in seg]

    # True Blackman-windowed Sinc low-pass anti-aliasing filter (cutoff at 0.38 * target_rate = 3040 Hz @ 8kHz)
    # Preserves crisp musical melody & vocals while preventing aliasing into the 48 kHz 3-pole reconstruction filter
    if sr > target_rate and len(seg) >= 101:
        cutoff = (target_rate * 0.38) / float(sr)
        n_taps = 101
        mid = n_taps // 2
        kernel = []
        for k in range(n_taps):
            x = k - mid
            sinc = 1.0 if x == 0 else math.sin(2.0 * math.pi * cutoff * x) / (math.pi * x)
            win = 0.42 - 0.5 * math.cos(2.0 * math.pi * k / (n_taps - 1)) + 0.08 * math.cos(4.0 * math.pi * k / (n_taps - 1))
            kernel.append(sinc * win)
        ksum = sum(kernel)
        kernel = [w / ksum for w in kernel]
        try:
            import numpy as np
            seg = np.convolve(np.array(seg, dtype=np.float64), np.array(kernel, dtype=np.float64), mode="same").tolist()
        except ImportError:
            pass

    # Fractional linear interpolation resampling
    out = []
    max_idx = len(seg) - 1
    ratio = max_idx / float(max(1, out_len - 1))
    for i in range(out_len):
        pos = i * ratio
        idx = int(pos)
        if idx >= max_idx:
            out.append(seg[max_idx])
        else:
            frac = pos - idx
            out.append(seg[idx] * (1.0 - frac) + seg[idx + 1] * frac)

    # Gentle 25 Hz subsonic DC blocker (alpha=0.985) + light HF smoothing
    hp = []
    prev_x = out[0]
    prev_y = 0.0
    prev_lp = 0.0
    alpha = 0.985
    for x in out:
        y = alpha * (prev_y + x - prev_x)
        prev_x = x
        prev_y = y
        prev_lp = prev_lp * 0.22 + y * 0.78
        hp.append(prev_lp)

    # Smooth Sliding-Window RMS Automatic Gain Control (AGC) + Soft-Knee Mastering Limiter
    # Prevents a single transient peak in an .MP3/.WAV song from crushing quieter verses into 8-bit silence!
    n_hp = len(hp)
    win_half = max(64, int(target_rate * 0.20))
    prefix_sq = [0.0] * (n_hp + 1)
    for idx_s, val_s in enumerate(hp):
        prefix_sq[idx_s + 1] = prefix_sq[idx_s] + val_s * val_s
    global_rms = math.sqrt(prefix_sq[n_hp] / max(1, n_hp))
    noise_gate = max(0.002, global_rms * 0.08)
    target_rms = 0.42

    leveled = []
    cur_gain = 1.0
    for i, x in enumerate(hp):
        w0 = max(0, i - win_half)
        w1 = min(n_hp, i + win_half)
        loc_rms = math.sqrt((prefix_sq[w1] - prefix_sq[w0]) / max(1, w1 - w0))
        if loc_rms > noise_gate:
            desired_g = min(6.5, max(0.4, target_rms / loc_rms))
        else:
            desired_g = min(2.5, target_rms / max(noise_gate, 0.005))
        cur_gain = cur_gain * 0.995 + desired_g * 0.005
        leveled.append(x * cur_gain)

    peak = max(max(abs(x) for x in leveled), 0.005)
    fade = min(160, out_len // 20)
    tanh_norm = math.tanh(1.55)
    res = []
    for i, x in enumerate(leveled):
        env = 1.0
        if i < fade:
            env = i / float(fade)
        elif i > out_len - fade:
            env = (out_len - 1 - i) / float(fade)
        norm = (x / peak) * 1.35 * gain * env
        soft = (math.tanh(norm * 1.55) / tanh_norm) * 0.94
        res.append(max(-0.98, min(0.98, soft)))
    return res


def generate_all_demo_wavs():
    """Generate 6 real 32KB (64-sector) 8-bit unsigned .WAV tracks in wav_tracks/."""
    os.makedirs(WAV_DIR, exist_ok=True)
    num_samples = 32768  # 64 sectors * 512 bytes = 32,768 bytes per track

    # -------------------------------------------------------------------------
    # Track 1: Real Spoken Voice via Windows SpeechSynthesizer + Intro Chime (8000 Hz)
    # -------------------------------------------------------------------------
    chime_len = 2400  # 0.30s crisp 3-note intro chime before speech begins
    voice_len = num_samples - chime_len
    tts_tmp = os.path.join(WAV_DIR, "_tts_raw.wav")
    ps_cmd = (
        "Add-Type -AssemblyName System.Speech; "
        "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
        "$s.Rate = 1; "
        f"$s.SetOutputToWaveFile('{tts_tmp}'); "
        "$s.Speak('Welcome to Tang Nano twenty K! Real digital wave audio streaming from the Micro S D card!'); "
        "$s.Dispose()"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", ps_cmd], check=False)
    if os.path.exists(tts_tmp):
        voice_pcm = load_and_resample_wav(tts_tmp, target_rate=8000, num_samples=voice_len)
        try:
            os.remove(tts_tmp)
        except OSError:
            pass
    else:
        voice_pcm = bytearray([128] * voice_len)

    trk1 = bytearray(num_samples)
    # Place clean 3-note chime (C5 -> E5 -> G5) in the first 0.30s before the voice
    for i in range(chime_len):
        t = i / 8000.0
        note_idx = 0 if i < 750 else (1 if i < 1500 else 2)
        nt = (i - note_idx * 750) / 8000.0
        env = math.exp(-nt * 12.0) * (1.0 - math.exp(-nt * 180.0))
        freq = (523.25, 659.25, 783.99)[note_idx]
        sig = (0.75 * math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(4 * math.pi * freq * t)) * env
        trk1[i] = max(40, min(216, int(round(128.0 + sig * 72.0))))
    trk1[chime_len:] = voice_pcm
    save_pcm8_wav(os.path.join(WAV_DIR, "1_tang_nano_stem.wav"), trk1, 8000)

    # -------------------------------------------------------------------------
    # Track 2: Funk Drum & Slap-Bass Breakbeat Loop (8000 Hz, seamless 16-step loop)
    # -------------------------------------------------------------------------
    trk2 = bytearray(num_samples)
    sr = 8000.0
    step_len = num_samples // 16  # 2048 samples per 16th note (exact loop!)
    kick_steps = {0, 3, 6, 8, 10, 14}
    snare_steps = {4, 12, 15}
    bass_freqs = [110.0, 110.0, 220.0, 110.0, 130.81, 146.83, 164.81, 146.83] * 2
    lfsr = 0xACE1
    for i in range(num_samples):
        step = (i // step_len) % 16
        pos_in_step = i % step_len
        ts = pos_in_step / sr
        lfsr = ((lfsr >> 1) ^ (-(lfsr & 1) & 0xB400)) & 0xFFFF
        noise = ((lfsr & 0xFF) - 128) / 128.0

        sig = 0.0
        # Punchy studio kick drum
        if step in kick_steps:
            k_env = math.exp(-ts * 18.0)
            k_freq = 52.0 + 140.0 * math.exp(-ts * 45.0)
            sig += math.sin(2 * math.pi * k_freq * ts) * k_env * 0.65

        # Crisp snare drum
        if step in snare_steps:
            s_env = math.exp(-ts * 22.0)
            sig += (noise * 0.75 + math.sin(2 * math.pi * 185.0 * ts) * 0.35) * s_env * 0.60

        # 16th-note closed/open hi-hat
        hh_decay = 16.0 if (step % 4 == 2) else 45.0
        sig += noise * math.exp(-ts * hh_decay) * 0.22

        # Funky slap bass
        bf = bass_freqs[step]
        b_env = math.exp(-ts * 8.5)
        b_mod = math.sin(2 * math.pi * bf * 2.0 * ts) * math.exp(-ts * 24.0) * 2.2
        sig += math.sin(2 * math.pi * bf * ts + b_mod) * b_env * 0.45

        comp = math.tanh(sig * 1.15)
        trk2[i] = max(40, min(216, int(round(128.0 + comp * 78.0))))
    for i in range(1, num_samples - 1):
        trk2[i] = (trk2[i - 1] + 2 * trk2[i] + trk2[i + 1]) >> 2
    save_pcm8_wav(os.path.join(WAV_DIR, "2_funk_drumbeat.wav"), trk2, 8000)

    # -------------------------------------------------------------------------
    # Track 3: Real Microsoft Studio Recording (tada.wav / Ring05.wav @ 11025 Hz)
    # -------------------------------------------------------------------------
    win_tada = r"C:\Windows\Media\tada.wav"
    win_ring = r"C:\Windows\Media\Ring05.wav"
    src3 = win_tada if os.path.exists(win_tada) else (win_ring if os.path.exists(win_ring) else None)
    if src3:
        trk3 = load_and_resample_wav(src3, target_rate=11025, num_samples=num_samples)
    else:
        trk3 = bytearray(trk2)
    save_pcm8_wav(os.path.join(WAV_DIR, "3_windows_tada.wav"), trk3, 11025)

    # -------------------------------------------------------------------------
    # Track 4: Cyber Acid TB-303 Synth + 909 House Groove (8000 Hz, seamless loop)
    # -------------------------------------------------------------------------
    trk4 = bytearray(num_samples)
    acid_notes = [
        55.0, 110.0, 82.41, 110.0, 130.81, 110.0, 98.0, 146.83,
        55.0, 110.0, 164.81, 146.83, 130.81, 110.0, 82.41, 98.0,
    ]
    lp1 = 0.0
    lp2 = 0.0
    phase = 0.0
    for i in range(num_samples):
        step = (i // step_len) % 16
        pos_in_step = i % step_len
        ts = pos_in_step / sr
        t_global = i / sr

        # 4-on-the-floor 909 Kick on steps 0, 4, 8, 12
        beat_pos = (i % (step_len * 4)) / sr
        k_env = math.exp(-beat_pos * 15.0)
        kick = math.sin(2 * math.pi * (48.0 + 130.0 * math.exp(-beat_pos * 40.0)) * beat_pos) * k_env * 0.55

        # Resonant TB-303 Sawtooth Acid Line (warm 100-900 Hz sweep, stable below Nyquist)
        freq = acid_notes[step]
        phase = (phase + freq / sr) % 1.0
        saw = 2.0 * phase - 1.0
        cutoff = 0.08 + (0.26 * math.exp(-ts * 14.0)) * (0.65 + 0.35 * math.sin(2 * math.pi * 0.5 * t_global))
        res = 1.35
        fb = res * (lp1 - lp2)
        lp1 += cutoff * (saw - lp1 + fb)
        lp2 += cutoff * (lp1 - lp2)
        acid = math.tanh(lp2 * 1.4) * 0.55

        # Rave chord stab on steps 2, 6, 10, 14
        stab = 0.0
        if step % 4 == 2:
            st_env = math.exp(-ts * 12.0)
            stab = (
                math.sin(2 * math.pi * 220.0 * ts)
                + math.sin(2 * math.pi * 261.63 * ts)
                + math.sin(2 * math.pi * 329.63 * ts)
            ) * st_env * 0.22

        comp = math.tanh((kick + acid + stab) * 1.15)
        trk4[i] = max(40, min(216, int(round(128.0 + comp * 78.0))))
    for i in range(1, num_samples - 1):
        trk4[i] = (trk4[i - 1] + 2 * trk4[i] + trk4[i + 1]) >> 2
    save_pcm8_wav(os.path.join(WAV_DIR, "4_cyber_acid_bass.wav"), trk4, 8000)

    # -------------------------------------------------------------------------
    # Track 5: Real Microsoft Studio Melody (Ring08.wav / chimes.wav @ 11025 Hz)
    # -------------------------------------------------------------------------
    win_r8 = r"C:\Windows\Media\Ring08.wav"
    win_ch = r"C:\Windows\Media\chimes.wav"
    src5 = win_r8 if os.path.exists(win_r8) else (win_ch if os.path.exists(win_ch) else None)
    if src5:
        trk5 = load_and_resample_wav(src5, target_rate=11025, num_samples=num_samples)
    else:
        trk5 = bytearray(trk4)
    save_pcm8_wav(os.path.join(WAV_DIR, "5_studio_chimes.wav"), trk5, 11025)

    # -------------------------------------------------------------------------
    # Track 6: Space Radio FM Telemetry, Quindar Beep & Cosmic Synth (8000 Hz)
    # -------------------------------------------------------------------------
    trk6 = bytearray(num_samples)
    arp_notes = [261.63, 329.63, 392.00, 523.25, 659.25, 523.25, 392.00, 329.63]
    for i in range(num_samples):
        t = i / 8000.0
        # Apollo Quindar intro beep (2525 Hz for first 0.25s)
        quindar = math.sin(2 * math.pi * 2525.0 * t) * 0.45 if t < 0.22 else 0.0
        # Sci-fi radio scanner sweep + cosmic arpeggio
        arp_idx = int(t * 8.0) % len(arp_notes)
        af = arp_notes[arp_idx]
        a_ts = (t * 8.0) % 1.0
        a_env = math.exp(-a_ts * 3.5)
        arp = math.sin(2 * math.pi * af * t + 1.8 * math.sin(2 * math.pi * (af * 0.5) * t)) * a_env * 0.45
        pad = (
            math.sin(2 * math.pi * 130.81 * t)
            + 0.6 * math.sin(2 * math.pi * 196.00 * t)
            + 0.4 * math.sin(2 * math.pi * 246.94 * t)
        ) * 0.22
        lfo_sweep = math.sin(2 * math.pi * (600.0 + 400.0 * math.sin(2 * math.pi * 1.5 * t)) * t) * 0.14
        comp = math.tanh((quindar + arp + pad + lfo_sweep) * 1.15)
        trk6[i] = max(40, min(216, int(round(128.0 + comp * 78.0))))
    for i in range(1, num_samples - 1):
        trk6[i] = (trk6[i - 1] + 2 * trk6[i] + trk6[i + 1]) >> 2
    save_pcm8_wav(os.path.join(WAV_DIR, "6_space_radio_fm.wav"), trk6, 8000)

    # -------------------------------------------------------------------------
    # Track 7: Echte Boerderij Opnames (Haan + Melkkoe + Schaap uit ESC-50 @ 8000 Hz)
    # -------------------------------------------------------------------------
    inet_dir = os.path.join(WAV_DIR, "internet_samples")
    rooster_wav = os.path.join(inet_dir, "rooster1.wav")
    cow_wav = os.path.join(inet_dir, "cow1.wav")
    sheep_wav = os.path.join(inet_dir, "sheep4.wav")
    if os.path.exists(rooster_wav) and os.path.exists(cow_wav) and os.path.exists(sheep_wav):
        # 1.65s echte Haan (13200 samples) + 1.35s echte Koe (10800 samples) + 1.096s echt Schaap (8768 samples)
        s_rooster = load_real_wav_slice(rooster_wav, 0.05, 13200 / 8000.0, 13200, target_rate=8000)
        s_cow = load_real_wav_slice(cow_wav, 0.05, 10800 / 8000.0, 10800, target_rate=8000)
        s_sheep = load_real_wav_slice(sheep_wav, 0.95, (num_samples - 24000) / 8000.0, num_samples - 24000, target_rate=8000)
        trk7_flt = s_rooster + s_cow + s_sheep
        trk7 = bytearray(num_samples)
        for i, x in enumerate(trk7_flt):
            trk7[i] = max(40, min(216, int(round(128.0 + x * 78.0))))
    else:
        trk7 = bytearray([128] * num_samples)
    save_pcm8_wav(os.path.join(WAV_DIR, "7_boerderij_wei.wav"), trk7, 8000)

    # -------------------------------------------------------------------------
    # Track 8: Echte Ochtendvogels & Dorpsklok Opnames (ESC-50 @ 8000 Hz)
    # -------------------------------------------------------------------------
    b1_wav = os.path.join(inet_dir, "birds1.wav")
    b2_wav = os.path.join(inet_dir, "birds2.wav")
    b10_wav = os.path.join(inet_dir, "birds10.wav")
    bell_wav = os.path.join(inet_dir, "bells1.wav")
    if os.path.exists(b1_wav) and os.path.exists(b2_wav) and os.path.exists(b10_wav):
        s_b1 = load_real_wav_slice(b1_wav, 0.02, 11000 / 8000.0, 11000, target_rate=8000)
        s_b2 = load_real_wav_slice(b2_wav, 2.05, 12000 / 8000.0, 12000, target_rate=8000)
        s_b3 = load_real_wav_slice(b10_wav, 0.15, (num_samples - 23000) / 8000.0, num_samples - 23000, target_rate=8000)
        trk8_flt = s_b1 + s_b2 + s_b3
        if os.path.exists(bell_wav):
            s_bell = load_real_wav_slice(bell_wav, 4.10, (num_samples - 23000) / 8000.0, num_samples - 23000, target_rate=8000, gain=0.45)
            for idx in range(len(s_bell)):
                pos = 23000 + idx
                trk8_flt[pos] = max(-0.98, min(0.98, trk8_flt[pos] * 0.78 + s_bell[idx]))
        trk8 = bytearray(num_samples)
        for i, x in enumerate(trk8_flt):
            trk8[i] = max(40, min(216, int(round(128.0 + x * 78.0))))
    else:
        trk8 = bytearray([128] * num_samples)
    save_pcm8_wav(os.path.join(WAV_DIR, "8_ochtend_vogels.wav"), trk8, 8000)

    def make_composite_wav(slices):
        """Combine list of (wav_filename, start_s, dur_s, out_samples) into 32KB PCM8 at exact 1:1 natural pitch."""
        flt = []
        for fn, st_s, _du_s, n_smp in slices:
            p = os.path.join(inet_dir, fn)
            if os.path.exists(p):
                flt.extend(load_real_wav_slice(p, st_s, n_smp / 8000.0, n_smp, target_rate=8000))
            else:
                flt.extend([0.0] * n_smp)
        flt = (flt + [0.0] * num_samples)[:num_samples]
        out = bytearray(num_samples)
        for i, x in enumerate(flt):
            out[i] = max(40, min(216, int(round(128.0 + x * 78.0))))
        return out

    trk9 = make_composite_wav([
        ("rooster1.wav", 0.05, 1.70, 12000),
        ("rooster3.wav", 0.05, 1.80, 11000),
        ("rooster2.wav", 0.20, 1.60, num_samples - 23000),
    ])
    save_pcm8_wav(os.path.join(WAV_DIR, "9_kraaiende_haan.wav"), trk9, 8000)

    trk10 = make_composite_wav([
        ("cow1.wav", 0.05, 1.45, 13000),
        ("cow2.wav", 0.50, 1.45, 10000),
        ("cow2.wav", 3.00, 1.45, num_samples - 23000),
    ])
    save_pcm8_wav(os.path.join(WAV_DIR, "10_twentse_koe.wav"), trk10, 8000)

    trk11 = make_composite_wav([
        ("sheep4.wav", 0.95, 1.50, 12000),
        ("sheep3.wav", 0.50, 1.50, 11000),
        ("sheep2.wav", 3.40, 1.40, num_samples - 23000),
    ])
    save_pcm8_wav(os.path.join(WAV_DIR, "11_schapenkudde.wav"), trk11, 8000)

    trk12 = make_composite_wav([
        ("pig1.wav", 0.05, 1.60, 12000),
        ("hen1.wav", 0.35, 0.90, 8000),
        ("pig1.wav", 2.20, 1.60, num_samples - 20000),
    ])
    save_pcm8_wav(os.path.join(WAV_DIR, "12_varken_en_kip.wav"), trk12, 8000)

    trk13 = make_composite_wav([
        ("birds2.wav", 2.05, 1.50, 11500),
        ("birds7.wav", 2.00, 1.60, 11500),
        ("birds9.wav", 3.20, 1.50, num_samples - 23000),
    ])
    save_pcm8_wav(os.path.join(WAV_DIR, "13_bosvogel_koor.wav"), trk13, 8000)

    trk14 = make_composite_wav([
        ("bells1.wav", 0.05, 2.00, 15000),
        ("birds1.wav", 0.02, 1.20, 9000),
        ("bells1.wav", 4.00, 1.00, num_samples - 24000),
    ])
    save_pcm8_wav(os.path.join(WAV_DIR, "14_dorpskerk_klok.wav"), trk14, 8000)

    trk15 = make_composite_wav([
        ("birds4.wav", 2.00, 1.60, 11500),
        ("birds8.wav", 1.50, 1.60, 11500),
        ("birds10.wav", 0.10, 1.40, num_samples - 23000),
    ])
    save_pcm8_wav(os.path.join(WAV_DIR, "15_vroege_merel.wav"), trk15, 8000)

    trk16 = make_composite_wav([
        ("rooster2.wav", 0.25, 1.50, 9000),
        ("hen1.wav", 0.35, 0.80, 6500),
        ("pig1.wav", 2.30, 1.20, 8500),
        ("cow2.wav", 3.00, 1.35, num_samples - 24000),
    ])
    save_pcm8_wav(os.path.join(WAV_DIR, "16_boerenerf_mix.wav"), trk16, 8000)

    tracks = [
        # SD-Kaart Pagina 1 (Tracks 0..7: Boerderij, Vogels & Dorpsklok)
        ("1.BOERDERIJ WEI", trk7,  0x2190, 1, 4),
        ("2.OCHTENDVOGELS", trk8,  0x21D0, 1, 4),
        ("3.KRAAIENDE HN ", trk9,  0x2210, 1, 4),
        ("4.TWENTSE KOE  ", trk10, 0x2250, 1, 4),
        ("5.SCHAPENKUDDE ", trk11, 0x2290, 1, 4),
        ("6.VARKEN & KIP ", trk12, 0x22D0, 1, 4),
        ("7.BOSVOGEL KOOR", trk13, 0x2310, 1, 4),
        ("8.DORPSKERK KLK", trk14, 0x2350, 1, 4),
        # SD-Kaart Pagina 2 (Tracks 8..15: Extra Vogels & Studio .WAVs)
        ("1.VROEGE MEREL ", trk15, 0x2390, 1, 4),
        ("2.BOERENERF MIX", trk16, 0x23D0, 1, 4),
        ("3.TANG NANO STM", trk1,  0x2010, 1, 4),
        ("4.FUNK DRUMBEAT", trk2,  0x2050, 1, 4),
        ("5.WINDOWS TADA!", trk3,  0x2090, 2, 3),
        ("6.CYBER ACID BS", trk4,  0x20D0, 1, 4),
        ("7.STUDIO CHIMES", trk5,  0x2110, 2, 3),
        ("8.SPACE RADIO  ", trk6,  0x2150, 1, 4),
    ]
    return tracks


def build_wav_directory_sector(tracks):
    """Build the 512-byte WAV Directory Sector for SD Card Sector $2000."""
    sec = bytearray(512)
    for idx, (title, pcm, start_sec, rate_code, dur_sec) in enumerate(tracks[:16]):
        off = idx * 32
        sec[off : off + 4] = b"WAV!"
        t_bytes = title.encode("ascii", errors="ignore")[:15]
        sec[off + 4 : off + 4 + len(t_bytes)] = t_bytes
        sec[off + 19] = 0
        num_secs = len(pcm) // 512
        num_pages = (len(pcm) // 256) & 0xFF
        sec[off + 20] = start_sec & 0xFF
        sec[off + 21] = (start_sec >> 8) & 0xFF
        sec[off + 22] = num_secs
        sec[off + 23] = num_pages
        sec[off + 24] = rate_code
        sec[off + 25] = dur_sec
    return sec


# Fast 6502 UART-to-SD-Card Sector Streamer at $7E00:
# Reads 1024 uppercase hex chars ('0'-'9','A'-'F') per 512B sector from UART ($A000/$A001),
# writes each sector via ROM_WRITE_SEC ($EADA), and sends 'R' before each sector & 'D' when done!
STREAMER_ASM = """
        ORG $7E00
        LDA #0
        STA $0491       ; DISK_FORCE_RD = 0 (SD card)
        JSR $E96A       ; ROM_SD_INIT

SEC_LOOP:
        LDA #'R'
        STA $A001       ; Send 'R' (Ready for next 512-byte sector)

        LDY #0
PG0_LP:
        JSR GET_BYTE
        STA $0600,Y
        INY
        BNE PG0_LP

        LDY #0
PG1_LP:
        JSR GET_BYTE
        STA $0700,Y
        INY
        BNE PG1_LP

        LDA #$00
        STA $1C         ; ZP_DST = $0600
        LDA #$06
        STA $1D
        JSR $EADA       ; ROM_WRITE_SEC (writes $0600-$07FF to DISK_SEC and increments DISK_SEC)

        DEC $60         ; SEC_CNT_LO
        BNE SEC_LOOP
        DEC $61         ; SEC_CNT_HI
        BNE SEC_LOOP

        LDA #'D'
        STA $A001       ; Send 'D' (Done!)
        RTS

GET_BYTE:
        JSR GET_NIB
        ASL A
        ASL A
        ASL A
        ASL A
        STA $62
        JSR GET_NIB
        ORA $62
        RTS

GET_NIB:
        LDA $A000
        LSR A
        BCC GET_NIB
        LDA $A001
        CMP #'0'
        BCC GET_NIB
        SEC
        SBC #'0'
        CMP #10
        BCC GN_OK
        SBC #7
GN_OK:
        AND #$0F
        RTS
"""


def send_basic_line(ser, line, wait=0.25):
    if ser.in_waiting:
        ser.read(ser.in_waiting)
    for ch in line:
        ser.write(ch.encode("ascii"))
        time.sleep(0.0005)
    ser.write(b"\r")
    t0 = time.time()
    buf = b""
    while time.time() - t0 < wait:
        if ser.in_waiting:
            buf += ser.read(ser.in_waiting)
            if b">" in buf:
                break
        time.sleep(0.01)
    return buf.decode("ascii", errors="ignore")


def install_streamer_stub(ser, streamer_code, base_addr=0x7E00):
    sd_tools.ensure_basic_prompt(ser)
    send_basic_line(ser, "CLS", wait=0.3)
    for i in range(0, len(streamer_code), 7):
        chunk = streamer_code[i : i + 7]
        stmts = [f"POKE ${base_addr + i + j:04X},${b:02X}" for j, b in enumerate(chunk)]
        send_basic_line(ser, ":".join(stmts), wait=0.35)


def upload_sectors_via_basic(ser, start_sector, data_bytes, label="SD"):
    """Stream arbitrary 512-byte sectors to the MicroSD card at high speed via $7E00 stub."""
    assert len(data_bytes) % 512 == 0
    num_sectors = len(data_bytes) // 512

    cnt_lo = num_sectors & 0xFF
    cnt_hi = ((num_sectors - 1) >> 8) + 1
    cmd = (
        f"POKE $0496,${start_sector & 0xFF:02X}:"
        f"POKE $0497,${(start_sector >> 8) & 0xFF:02X}:"
        f"POKE $60,${cnt_lo:02X}:POKE $61,${cnt_hi:02X}:CALL $7E00"
    )
    if ser.in_waiting:
        ser.read(ser.in_waiting)
    for ch in cmd:
        ser.write(ch.encode("ascii"))
        time.sleep(0.0005)
    ser.write(b"\r")

    # Wait until the echoed command 'CALL $7E00' has been received before looking for 'R'
    t0 = time.time()
    echo_buf = b""
    while time.time() - t0 < 2.0:
        if ser.in_waiting:
            echo_buf += ser.read(1)
            if echo_buf.endswith(b"\n"):
                break

    for s in range(num_sectors):
        t0 = time.time()
        got_r = False
        while time.time() - t0 < 3.0:
            ch = ser.read(1)
            if ch == b"R":
                got_r = True
                break
        if not got_r:
            raise RuntimeError(f"Timeout waiting for 'R' on sector {s}/{num_sectors} ({label})")

        chunk = data_bytes[s * 512 : (s + 1) * 512]
        hex_payload = chunk.hex().upper().encode("ascii")
        ser.write(hex_payload)
        if (s + 1) % 8 == 0 or (s + 1) == num_sectors:
            print(f"\r  [{label}] Sector {s + 1}/{num_sectors} ({(s + 1) * 512} B) geschreven...", end="", flush=True)

    # Wait for 'D' completion and '>' prompt
    t0 = time.time()
    tail = b""
    while time.time() - t0 < 3.0:
        if ser.in_waiting:
            tail += ser.read(ser.in_waiting)
            if b">" in tail:
                break
        time.sleep(0.01)
    print()


RAM_STREAMER_ASM = """
        ORG $0600
        LDA #$00
        STA $60
        LDA #$80
        STA $61
        LDX #13
PAGE_LP:
        LDA #'R'
        STA $A001
        LDY #0
BYTE_LP:
        JSR GET_HEX
        STA ($60),Y
        INY
        BNE BYTE_LP
        INC $61
        DEX
        BNE PAGE_LP
        LDA #'D'
        STA $A001
        RTS
GET_HEX:
        JSR GET_NIB
        ASL A
        ASL A
        ASL A
        ASL A
        STA $62
        JSR GET_NIB
        ORA $62
        RTS
GET_NIB:
        LDA $A000
        LSR A
        BCC GET_NIB
        LDA $A001
        CMP #'0'
        BCC GET_NIB
        SEC
        SBC #'0'
        CMP #10
        BCC GN_OK
        SBC #7
GN_OK:
        AND #$0F
        RTS
"""


def install_and_run_wekker(ser):
    """Upload WEKKER v5.0 (8 .WAV sounds, 3090 bytes) at high speed to $8000, BSAVE to D0 & D1, and launch!"""
    wekker_bin_path = os.path.join(BASE_DIR, "sdcard", "wekker.bin")
    wekker_bin = open(wekker_bin_path, "rb").read()
    padded = wekker_bin + b"\x00" * (13 * 256 - len(wekker_bin))
    _, stub = sd_tools.assemble_6502_source(RAM_STREAMER_ASM)
    print("Installeren van snelle BSRAM-Loader ($0600) voor WEKKER v5.0 (8 .WAV geluiden)...")
    install_streamer_stub(ser, stub, base_addr=0x0600)
    if ser.in_waiting:
        ser.read(ser.in_waiting)
    ser.write(b"CALL $0600\r")
    t0 = time.time()
    buf = b""
    while time.time() - t0 < 2.0:
        if ser.in_waiting:
            buf += ser.read(1)
            if buf.endswith(b"\n"):
                break
    for p in range(13):
        t0 = time.time()
        while time.time() - t0 < 2.0:
            if ser.read(1) == b"R":
                break
        ser.write(padded[p * 256 : (p + 1) * 256].hex().upper().encode("ascii"))
    time.sleep(0.3)
    if ser.in_waiting:
        ser.read(ser.in_waiting)
    print(f"WEKKER v5.0 ({len(wekker_bin)} bytes) geladen op $8000! Opslaan naar SD-kaart D0 en D1...")
    send_basic_line(ser, "POKE $6D,0", wait=0.3)
    send_basic_line(ser, "SD", wait=0.4)
    send_basic_line(ser, "DRIVE 0", wait=0.4)
    out0 = send_basic_line(ser, f'BSAVE "WEKKER",$8000,${len(wekker_bin):04X}', wait=2.5)
    print("  D0:", out0.strip())
    send_basic_line(ser, "DRIVE 1", wait=0.4)
    out1 = send_basic_line(ser, f'BSAVE "WEKKER",$8000,${len(wekker_bin):04X}', wait=2.5)
    print("  D1:", out1.strip())
    send_basic_line(ser, "DRIVE 0", wait=0.4)
    print("Starten van WEKKER v5.0 (speelt direct 1: BOERDERIJ WEI .WAV)...")
    ser.write(b'BRUN "WEKKER"\r')
    time.sleep(5.5)
    print("Demonstratie Geluid 2: OCHTENDVOGELS (.WAV)...")
    ser.write(b"2")
    time.sleep(5.5)
    print("Terug naar Geluid 1: BOERDERIJ WEI (.WAV)...")
    ser.write(b"1")
    time.sleep(4.5)
    print("Klaar! WEKKER v5.0 met alle 8 .WAV geluiden staat nu op de SD-kaart en draait live!")


def main():
    if "--gui" in sys.argv:
        import wav_gui
        wav_gui.main()
        return
    app_only = "--app-only" in sys.argv
    track1_only = "--track1-and-app" in sys.argv
    new_wavs_only = "--new-wavs-only" in sys.argv
    install_wekker_only = "--install-wekker" in sys.argv
    had_terminal = False
    pid_file = os.path.join(BASE_DIR, ".basic_terminal.pid")
    if os.path.exists(pid_file):
        try:
            old_pid = int(open(pid_file, encoding="utf-8").read().strip())
            res = subprocess.run(["taskkill", "/PID", str(old_pid), "/T", "/F"], capture_output=True)
            if res.returncode == 0:
                had_terminal = True
                time.sleep(0.4)
        except Exception:
            pass
    try:
        import urllib.request
        req = urllib.request.Request("http://127.0.0.1:8765/api/disconnect", data=b"{}", method="POST")
        urllib.request.urlopen(req, timeout=1.0)
        time.sleep(0.3)
    except Exception:
        pass

    wavplay_path = os.path.join(BASE_DIR, "sdcard", "WAVPLAY.asm")
    wavplay_org, wavplay_code = sd_tools.assemble_6502_source(open(wavplay_path, encoding="utf-8").read())
    print(f"WAVPLAY.asm geassembleerd: {len(wavplay_code)} bytes op ${wavplay_org:04X}")

    # Soft-reset FPGA SRAM so GPU parser and CPU start 100% clean
    subprocess.run(
        [
            r"C:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer_cli.exe",
            "--device",
            "GW2AR-18C",
            "--run",
            "2",
            "-f",
            os.path.join(BASE_DIR, "impl", "pnr", "MiniGPU_BASIC.fs"),
        ],
        check=False,
    )
    time.sleep(1.5)

    port = sd_tools.find_tang_port("COM21")
    with serial.Serial(port, 115200, timeout=0.2) as ser:
        if install_wekker_only:
            install_and_run_wekker(ser)
            if had_terminal:
                subprocess.Popen([sys.executable, os.path.join(BASE_DIR, "basic_terminal.py")], cwd=BASE_DIR)
            return
        if not app_only:
            print(f"Genereren van 6 echte .WAV geluidsbestanden in {WAV_DIR}...")
            tracks = generate_all_demo_wavs()
            dir_sector = build_wav_directory_sector(tracks)
            _, streamer_code = sd_tools.assemble_6502_source(STREAMER_ASM)
            print(f"Verbonden met Tang Nano 20K op {port}. Installeren van snelle SD-Sector Streamer ($7E00)...")
            install_streamer_stub(ser, streamer_code)

            # 1. Write WAV Directory to Sector $2000
            print("Schrijven van WAV Directory naar SD Sector $2000...")
            upload_sectors_via_basic(ser, 0x2000, dir_sector, label="WAV-DIR $2000")

            # 2. Write .WAV Tracks (64 sectors = 32 KB each)
            if track1_only:
                tracks_to_write = tracks[:1]
            elif new_wavs_only:
                tracks_to_write = tracks[2:10]
            else:
                tracks_to_write = tracks
            for title, pcm, start_sec, _, _ in tracks_to_write:
                upload_sectors_via_basic(ser, start_sec, pcm, label=f"{title.strip()} (${start_sec:04X})")
            if new_wavs_only:
                print("Alle 16 .WAV tracks en WAV-DIR $2000 staan nu op de SD-kaart!")
                if "--launch-wekker" in sys.argv:
                    install_and_run_wekker(ser)
                    if had_terminal:
                        subprocess.Popen([sys.executable, os.path.join(BASE_DIR, "basic_terminal.py")], cwd=BASE_DIR)
                    return
        else:
            sd_tools.ensure_basic_prompt(ser)

        # 3. Upload WAVPLAY.asm ($8000) and save to DRIVE 0 and DRIVE 1
        sd_tools.upload_file_to_sdcard(ser, wavplay_path, run_after=False, media="SD", drive=0, save_to_sd=True)
        send_basic_line(ser, "DRIVE 1", wait=0.5)
        out = send_basic_line(ser, f'BSAVE "WAVPLAY",${wavplay_org:04X},${len(wavplay_code):04X}', wait=2.2)
        print(out.strip())

        # Switch back to DRIVE 0 and launch WAVPLAY immediately!
        send_basic_line(ser, "DRIVE 0", wait=0.5)
        print("Starten van WAVPLAY op de Tang Nano 20K...")
        ser.write(b'BRUN "WAVPLAY"\r')
        time.sleep(0.5)
        print("Klaar! WAVPLAY draait nu live op de Tang Nano 20K!")


if __name__ == "__main__":
    main()
