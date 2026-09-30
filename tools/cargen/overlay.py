"""Add titles to the promo renders -> final icon (512) and thumbnails (1920x1080)."""

import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTS = os.environ.get("FONTS", "/usr/share/fonts/truetype/google-fonts")  # folder with the Poppins .ttf files
BI = f"{FONTS}/Poppins-BoldItalic.ttf"
B = f"{FONTS}/Poppins-Bold.ttf"
M = f"{FONTS}/Poppins-Medium.ttf"


def font(p, s):
    """Loads a font at a size."""
    return ImageFont.truetype(p, s)


def shadow_text(img, xy, text, f, fill, shadow=(0, 0, 0, 170), blur=6, off=(4, 5), anchor="la"):
    """Draws text with a soft drop shadow so it reads on any background."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((xy[0] + off[0], xy[1] + off[1]), text, font=f, fill=shadow, anchor=anchor)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(layer)
    ImageDraw.Draw(img).text(xy, text, font=f, fill=fill, anchor=anchor)


def gradient_band(img, y0, y1, top_alpha, bottom_alpha, color=(8, 10, 20)):
    """Darkens a horizontal band with a vertical fade, behind titles."""
    w = img.width
    band = Image.new("RGBA", (w, y1 - y0))
    px = band.load()
    for y in range(y1 - y0):
        a = int(top_alpha + (bottom_alpha - top_alpha) * y / max(1, y1 - y0 - 1))
        for x in range(w):
            px[x, y] = (*color, a)
    img.alpha_composite(band, (0, y0))


def left_fade(img, width, alpha=200, color=(8, 10, 20)):
    """Darkens the left edge with a fade, behind left-aligned text."""
    band = Image.new("RGBA", (width, img.height))
    px = band.load()
    for x in range(width):
        a = int(alpha * (1 - x / width) ** 1.3)
        for y in range(img.height):
            px[x, y] = (*color, a)
    img.alpha_composite(band, (0, 0))


def logo(img, x, y, size):
    """GOTRACK (yellow->red) + RACING wordmark."""
    f = font(BI, size)
    tmp = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((x, y), "GOTRACK", font=f, fill=(255, 255, 255, 255))
    mask = tmp.split()[3]
    grad = Image.new("RGBA", img.size)
    gp = ImageDraw.Draw(grad)
    bbox = mask.getbbox() or (x, y, x + 10, y + 10)
    for yy in range(bbox[1], bbox[3] + 1):
        t = (yy - bbox[1]) / max(1, bbox[3] - bbox[1])
        c = (255, int(214 - 110 * t), int(40 + 10 * t), 255)
        gp.line([(bbox[0], yy), (bbox[2], yy)], fill=c)
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((x + 5, y + 7), "GOTRACK", font=f, fill=(0, 0, 0, 190))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(size // 18)))
    img.paste(grad, (0, 0), mask)
    f2 = font(BI, int(size * 0.38))
    rx = bbox[0] + int(size * 0.06)
    ry = bbox[3] + int(size * 0.1)
    shadow_text(img, (rx, ry), "R A C I N G", f2, (255, 255, 255, 255), blur=4, off=(3, 4))
    # red speed bar
    d = ImageDraw.Draw(img)
    bw = int(size * 0.9)
    by = ry + int(size * 0.5)
    d.polygon([(rx, by), (rx + bw, by), (rx + bw - 14, by + 10), (rx - 14, by + 10)], fill=(230, 30, 45, 255))
    return by + 10


def pill(img, xy, text, f, bg, fg=(255, 255, 255, 255)):
    """A rounded label with a background colour."""
    d = ImageDraw.Draw(img)
    x, y = xy
    tw = d.textlength(text, font=f)
    h = f.size + 22
    d.rounded_rectangle([x, y, x + tw + 44, y + h], radius=h // 2, fill=bg)
    d.text((x + 22, y + h / 2), text, font=f, fill=fg, anchor="lm")
    return x + tw + 44


def main(S, OUT):
    # ---------------------------------------------------------------- icon
    """Builds the icon and thumbnails from the renders in S and saves them to OUT."""
    if os.path.exists(f"{S}/f_icon.png"):
        ic = Image.open(f"{S}/f_icon.png").convert("RGBA")
        gradient_band(ic, 560, 1024, 0, 235)
        f = font(BI, 170)
        shadow_text(ic, (512, 700), "GOTRACK", f, (255, 214, 40, 255), blur=10, off=(6, 8), anchor="mm")
        shadow_text(ic, (512, 842), "R A C I N G", font(BI, 86), (255, 255, 255, 255), blur=6, off=(4, 5), anchor="mm")
        d = ImageDraw.Draw(ic)
        d.polygon([(250, 912), (790, 912), (770, 934), (230, 934)], fill=(230, 30, 45, 255))
        ic.convert("RGB").resize((512, 512), Image.LANCZOS).save(f"{OUT}/GoTrack_Icon_512.png")

    # ---------------------------------------------------------------- thumbnail 1: hero (logo + one line, no badges)
    if os.path.exists(f"{S}/f_hero.png"):
        t1 = Image.open(f"{S}/f_hero.png").convert("RGBA")
        left_fade(t1, 1100, 215)
        yb = logo(t1, 80, 70, 170)
        shadow_text(t1, (86, yb + 40), "Race Formula cars on a 10-car grid", font(B, 52), (255, 255, 255, 255))
        t1.convert("RGB").save(f"{OUT}/GoTrack_Thumbnail_1.png")

    # ---------------------------------------------------------------- thumbnail 2: lineup
    if not os.path.exists(f"{S}/f_lineup.png"):
        return
    t2 = Image.open(f"{S}/f_lineup.png").convert("RGBA")
    gradient_band(t2, 0, 330, 220, 0)
    shadow_text(
        t2, (960, 110), "13 CARS TO COLLECT", font(BI, 110), (255, 214, 40, 255), blur=10, off=(6, 8), anchor="mm"
    )
    shadow_text(
        t2, (960, 215), "Every car is different  •  Paint it your way", font(B, 50), (255, 255, 255, 255), anchor="mm"
    )
    t2.convert("RGB").save(f"{OUT}/GoTrack_Thumbnail_2.png")

    # ---------------------------------------------------------------- thumbnail 3: ranked / modes
    if not os.path.exists(f"{S}/f_battle.png"):
        return
    t3 = Image.open(f"{S}/f_battle.png").convert("RGBA")
    left_fade(t3, 1000, 220)
    shadow_text(t3, (86, 120), "CLIMB THE", font(BI, 96), (255, 255, 255, 255))
    shadow_text(t3, (86, 225), "RANKS", font(BI, 150), (255, 214, 40, 255), blur=10, off=(6, 8))
    shadow_text(t3, (90, 420), "Bronze  ›  Silver  ›  Gold  ›  Champion", font(B, 38), (255, 255, 255, 255))
    y = 520
    for txt, col in (
        ("QUICK RACE", (230, 30, 45, 235)),
        ("RANKED SEASONS", (120, 60, 220, 235)),
        ("TIME TRIAL", (20, 140, 220, 235)),
    ):
        pill(t3, (86, y), txt, font(B, 36), col)
        y += 84
    t3.convert("RGB").save(f"{OUT}/GoTrack_Thumbnail_3.png")
    print("done")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
