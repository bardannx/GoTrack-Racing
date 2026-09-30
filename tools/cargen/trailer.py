"""A 30-second trailer: the real cars on the real circuits (showcase.clip), title cards,
captions and a synthesized soundtrack, encoded to 1920x1080 H.264.

    python3 tools/cargen/trailer.py clips      # render the circuit clips (~1 h on 4 cores)
    python3 tools/cargen/trailer.py edit       # compose, add sound, encode
    -> assets/launch/trailer/GoTrack_Trailer.mp4

This is for YouTube / social ads. Roblox's own video thumbnails must be real gameplay
recorded in the game, so those are captured in Studio instead.
Needs bpy, numpy, Pillow and imageio-ffmpeg (a bundled ffmpeg).
"""

import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
WORK = ROOT / "tools" / "sim" / "out" / "trailer"
OUT = ROOT / "assets" / "launch" / "trailer"
IMAGES = ROOT / "docs" / "images"
FPS = 24
W, H = 1920, 1080
BEAT = 12  # frames per beat: 120 BPM at 24 fps, every cut lands on a beat

# (id, lap fraction, rig, cars, seconds, caption, sub-caption)
CLIPS = [
    ("capital", 0.50, "front", ["gt1", "falcon", "aeros"], 2.5, "31 CIRCUITS", "around the world"),
    ("canyon", 0.50, "wide", ["falcon", "retro90", "gt1"], 2.5, "RED ROCK CANYON", "Arizona"),
    ("bay", 0.26, "front", ["neonracer", "nova", "gt1"], 2.5, "NEON BAY STREETS", "Tokyo  ·  night race"),
    ("alpine", 0.62, "frontl", ["viper", "gt1", "falcon"], 2.5, "ALPINE RING", "Austria"),
    ("harbor", 0.74, "front", ["aurora", "gt1", "stealth"], 2.5, "AZURE HARBOR", "Monaco"),
    ("sakura", 0.38, "wide", ["aeros", "nova", "gt1"], 29 / 24, "SAKURA HILLS", "Japan"),
]


def clips():
    """Renders the circuit clips and the line-up still into the work folder (skips any that
    already exist, so it can be resumed).
    """
    WORK.mkdir(parents=True, exist_ok=True)
    if not (WORK / "lineup.png").exists():
        # nine of the cars side by side on a grid (promo.py's line-up scene, no text)
        subprocess.run(
            [sys.executable, str(HERE / "promo.py"), "lineup", str(WORK / "lineup.png")], check=True, cwd=str(HERE)
        )
    for cid, frac, rig, cars, secs, *_ in CLIPS:
        d = WORK / cid
        n = int(round(secs * FPS))
        if d.exists() and len(list(d.glob("f_*.png"))) >= n:
            print("have", cid)
            continue
        # one Blender scene per process keeps memory flat
        subprocess.run(
            [
                sys.executable,
                str(HERE / "showcase.py"),
                "clip",
                cid,
                str(frac),
                rig,
                str(secs),
                str(d),
                "960x540",
                "12",
                ",".join(cars),
            ],
            check=True,
        )


# ---------------------------------------------------------------------------- picture
def fonts():
    import overlay as ov

    return ov


def ease(t):
    """Ease-out cubic, 0..1."""
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def caption(img, title, sub, t, n):
    """Title slides in from the left with a red bar, fades out at the end of the shot."""
    ov = fonts()
    a = ease(t / 8) * (1.0 - ease((t - (n - 6)) / 6))
    if a <= 0.01:
        return img
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dx = int((1 - ease(t / 8)) * -120)
    d = ImageDraw.Draw(layer)
    x, y = 90 + dx, 86
    d.polygon([(x, y + 6), (x + 10, y + 6), (x + 4, y + 86), (x - 6, y + 86)], fill=(230, 30, 45, 255))
    ov.shadow_text(layer, (x + 30, y), title, ov.font(ov.BI, 74), (255, 255, 255, 255), blur=6, off=(3, 5))
    if sub:
        ov.shadow_text(layer, (x + 34, y + 92), sub, ov.font(ov.B, 38), (255, 214, 40, 255), blur=5, off=(3, 4))
    alpha = layer.split()[3].point(lambda v: int(v * a))
    layer.putalpha(alpha)
    img.alpha_composite(layer)
    return img


def flash(img, t, strength=0.55, length=5):
    """A white flash that fades over `length` frames after a cut."""
    if t >= length:
        return img
    k = strength * (1 - t / length)
    white = Image.new("RGBA", img.size, (255, 255, 255, int(255 * k)))
    img.alpha_composite(white)
    return img


def vignette():
    """A dark vignette overlay for the whole video."""
    y, x = np.mgrid[0:H, 0:W]
    r = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2)
    a = np.clip((r - 0.75) / 0.7, 0, 1) ** 1.5 * 150
    v = np.zeros((H, W, 4), np.uint8)
    v[..., 3] = a.astype(np.uint8)
    return Image.fromarray(v, "RGBA")


def ken_burns(src, t, n, z0=1.0, z1=1.08, pan=(0.0, 0.0)):
    """Slow zoom and pan across a still, frame `t` of `n`."""
    k = t / max(1, n - 1)
    z = z0 + (z1 - z0) * k
    iw, ih = src.size
    cw, ch = iw / z, ih / z
    cx = iw / 2 + pan[0] * iw * k
    cy = ih / 2 + pan[1] * ih * k
    box = (cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
    return src.resize((W, H), Image.LANCZOS, box=box)


def logo_card(bg, t, n, line, cta=False):
    """The title card: logo, a line of text and, on the last card, the call to action."""
    ov = fonts()
    img = bg.copy()
    s = 1.12 - 0.12 * ease(t / 14)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ov.logo(layer, 0, 0, 230)
    box = layer.getbbox() or (0, 0, 10, 10)
    mark = layer.crop(box)
    mark = mark.resize((int(mark.width * s), int(mark.height * s)), Image.LANCZOS)
    a = ease(t / 10)
    mark.putalpha(mark.split()[3].point(lambda v: int(v * a)))
    img.alpha_composite(mark, ((W - mark.width) // 2, (H - mark.height) // 2 - 80))
    if line and t > 10:
        b = ease((t - 10) / 10)
        txt = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        f = ov.font(ov.B, 54 if cta else 46)
        ov.shadow_text(
            txt, (W // 2, H // 2 + 150), line, f, (255, 214, 40, 255) if cta else (255, 255, 255, 255), anchor="mm"
        )
        txt.putalpha(txt.split()[3].point(lambda v: int(v * b)))
        img.alpha_composite(txt)
    return img


TIERS = [
    ("BRONZE", (214, 132, 62)),
    ("SILVER", (190, 200, 220)),
    ("GOLD", (255, 196, 40)),
    ("PLATINUM", (70, 225, 200)),
    ("DIAMOND", (110, 160, 255)),
    ("CHAMPION", (255, 70, 110)),
]  # Config.Ranked.Tiers


def ranked_card(bg, t, n):
    """The six ranked tiers pop in left to right as diamond badges (the game's badge shape)."""
    ov = fonts()
    img = bg.copy()
    img = caption(img, "RANKED", "race real players  ·  climb to Champion", t, n)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    gap = 270
    x0 = W // 2 - gap * 5 // 2
    cy = H // 2 + 70
    for i, (name, col) in enumerate(TIERS):
        p = ease((t - 6 - i * 4) / 7)
        if p <= 0:
            continue
        big = 1.25 if i == 5 else 1.0
        r = 92 * big * (0.6 + 0.4 * p)
        cx = x0 + i * gap
        dark = tuple(int(c * 0.45) for c in col)
        a = int(255 * p)
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=col + (a,))
        ri = r * 0.62
        d.polygon([(cx, cy - ri), (cx + ri, cy), (cx, cy + ri), (cx - ri, cy)], fill=dark + (a,))
        f = ov.font(ov.B, 34 if i == 5 else 30)
        d.text((cx, cy + r + 40), name, font=f, fill=(255, 255, 255, a), anchor="mm")
    glow = layer.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(glow)
    img.alpha_composite(layer)
    return img


def timeline():
    """[(kind, frames, payload)]"""
    tl = [("logo", 4 * BEAT, None)]
    for c in CLIPS:
        tl.append(("clip", int(round(c[4] * FPS)), c))
    tl.append(("still", 9 * BEAT, (WORK / "lineup.png", "13 CARS", "13 eras of Formula 1", (1.0, 1.1), (0.0, 0.02))))
    tl.append(("ranked", 8 * BEAT, None))
    total = sum(f for _, f, _ in tl)
    tl.append(("end", 30 * FPS - total, None))
    return tl


def compose():
    """Puts every frame together (clips, stills, titles, flashes) into the frames folder."""
    frames_dir = WORK / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    for f in frames_dir.glob("*.png"):
        f.unlink()
    vig = vignette()
    first = Image.open(WORK / CLIPS[0][0] / "f_0001.png").convert("RGB").resize((W, H), Image.LANCZOS)
    dark = ImageEnhance.Brightness(first.filter(ImageFilter.GaussianBlur(18))).enhance(0.35).convert("RGBA")
    bay = WORK / "bay" / "f_0030.png"
    ranked_bg = (
        ImageEnhance.Brightness(
            Image.open(bay).convert("RGB").resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(14))
        )
        .enhance(0.45)
        .convert("RGBA")
    )
    k = 0
    cuts = []
    for kind, n, payload in timeline():
        cuts.append(k)
        for t in range(n):
            if kind == "logo":
                img = logo_card(dark, t, n, "")
            elif kind == "end":
                img = logo_card(dark, t, n, "Play now on Roblox", cta=True)
                img = flash(img, t, 0.7, 6)
            elif kind == "clip":
                cid, _, _, _, _, title, sub = payload
                src = Image.open(WORK / cid / f"f_{t + 1:04d}.png").convert("RGB")
                img = src.resize((W, H), Image.LANCZOS).convert("RGBA")
                img.alpha_composite(vig)
                img = caption(img, title, sub, t, n)
                img = flash(img, t)
            elif kind == "ranked":
                img = ranked_card(ranked_bg, t, n)
                img = flash(img, t)
            else:
                name, title, sub, zoom, pan = payload
                src = Image.open(name).convert("RGB")
                img = ken_burns(src, t, n, zoom[0], zoom[1], pan).convert("RGBA")
                img.alpha_composite(vig)
                img = caption(img, title, sub, t, n)
                img = flash(img, t)
            img.convert("RGB").save(frames_dir / f"{k:05d}.png", compress_level=1)
            k += 1
    print("frames", k)
    return k, cuts


# ---------------------------------------------------------------------------- sound
SR = 48000


def env(n, attack, decay):
    """Attack/decay volume envelope for a synthesized sound, `n` samples long."""
    t = np.arange(n) / SR
    return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-t / decay)


def lowpass(x, k):
    """A simple moving-average low-pass filter."""
    if k <= 1:
        return x
    return np.convolve(x, np.ones(k) / k, mode="same")


def soundtrack(n_frames, cuts):
    """Synthesizes the music and engine sounds, with hits on the cuts. Returns a WAV path."""
    rng = np.random.default_rng(7)
    dur = n_frames / FPS
    N = int(dur * SR)
    L = np.zeros(N)
    R = np.zeros(N)
    beat = BEAT / FPS
    logo_end = 4 * BEAT / FPS
    end_start = cuts[-1] / FPS

    def add(sig, at, pan=0.0, gain=1.0):
        i = int(at * SR)
        if i >= N:
            return
        s = sig[: N - i] * gain
        L[i : i + len(s)] += s * (1 - pan) * 0.5 * 2**0.5
        R[i : i + len(s)] += s * (1 + pan) * 0.5 * 2**0.5

    # kick: pitch sweep 140 -> 45 Hz
    kn = int(0.35 * SR)
    kt = np.arange(kn) / SR
    kick = np.sin(2 * np.pi * np.cumsum(45 + 95 * np.exp(-kt / 0.03)) / SR) * env(kn, 0.002, 0.12)
    hat = lowpass(rng.standard_normal(int(0.05 * SR)), 1)
    hat = (hat - lowpass(hat, 6)) * env(len(hat), 0.001, 0.012)
    snare = (
        rng.standard_normal(int(0.2 * SR)) * 0.6 + np.sin(2 * np.pi * 190 * np.arange(int(0.2 * SR)) / SR) * 0.4
    ) * env(int(0.2 * SR), 0.001, 0.06)
    t = logo_end
    b = 0
    while t < end_start:
        add(kick, t, 0, 0.9)
        add(hat, t + beat / 2, 0.3, 0.25)
        if b % 2 == 1:
            add(snare, t, -0.1, 0.35)
        t += beat
        b += 1
    # bass line on every beat (A, F, C, G), ducked by the kick
    notes = [55.0, 43.65, 65.41, 49.0]
    bn = int(beat * SR)
    t = logo_end
    b = 0
    while t < end_start:
        f = notes[(b // 8) % 4]
        x = np.arange(bn) / SR
        saw = 2 * ((x * f) % 1) - 1
        sig = lowpass(saw, 40) * env(bn, 0.01, 0.35) * (1 - 0.8 * np.exp(-x / 0.08))
        add(sig, t, 0, 0.35)
        t += beat
        b += 1
    # engine: a rising whine through every circuit shot (gear shifts at each cut)
    for i, c in enumerate(cuts[1:-3]):
        start = c / FPS
        seg = (cuts[i + 2] - c) / FPS if i + 2 < len(cuts) else 2.5
        n = int(seg * SR)
        x = np.arange(n) / SR
        f0 = 95 + 120 * (x / seg) ** 0.7
        ph = 2 * np.pi * np.cumsum(f0) / SR
        eng = sum(np.sin(ph * h) / h for h in (1, 2, 3, 4, 6, 8)) + 0.15 * rng.standard_normal(n)
        eng = lowpass(eng, 6) * np.minimum(1, x / 0.08) * np.minimum(1, (seg - x) / 0.1)
        add(eng, start, 0.15 * (-1) ** i, 0.16)
    # whoosh at every cut
    wn = int(0.5 * SR)
    for c in cuts[1:]:
        noise = rng.standard_normal(wn)
        sw = lowpass(noise, 3) - lowpass(noise, 30)
        w = sw * np.sin(np.linspace(0, np.pi, wn)) ** 2
        add(w, c / FPS - 0.25, 0, 0.5)
    # riser into the first shot and a hit on the logo and the end card
    rn = int(logo_end * SR)
    rx = np.arange(rn) / SR
    riser = lowpass(rng.standard_normal(rn), 4) * (rx / logo_end) ** 2 + np.sin(
        2 * np.pi * np.cumsum(200 + 600 * (rx / logo_end) ** 2) / SR
    ) * 0.3 * (rx / logo_end)
    add(riser, 0, 0, 0.35)
    hn = int(2.5 * SR)
    hx = np.arange(hn) / SR
    hit = (np.sin(2 * np.pi * 42 * hx) + 0.5 * np.sin(2 * np.pi * 84 * hx)) * env(hn, 0.003, 0.7) + lowpass(
        rng.standard_normal(hn), 2
    ) * env(hn, 0.001, 0.25) * 0.4
    add(hit, 0.05, 0, 0.8)
    add(hit, end_start, 0, 1.0)
    mix = np.stack([L, R], axis=1)
    mix = np.tanh(mix * 1.1)
    fade = int(0.8 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    mix /= max(1e-6, np.abs(mix).max()) / 0.89
    pcm = (mix * 32767).astype(np.int16)
    path = WORK / "sound.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return path


def encode(n_frames, wav):
    """Encodes the frames and the soundtrack to an H.264 MP4 with ffmpeg."""
    import imageio_ffmpeg

    ff = imageio_ffmpeg.get_ffmpeg_exe()
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "GoTrack_Trailer.mp4"
    subprocess.run(
        [
            ff,
            "-y",
            "-loglevel",
            "error",
            "-framerate",
            str(FPS),
            "-i",
            str(WORK / "frames" / "%05d.png"),
            "-i",
            str(wav),
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "20",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-shortest",
            str(out),
        ],
        check=True,
    )
    print(out, out.stat().st_size)
    return out


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "edit"
    if cmd == "clips":
        clips()
    elif cmd == "edit":
        n, cuts = compose()
        encode(n, soundtrack(n, cuts))
