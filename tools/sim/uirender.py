#!/usr/bin/env python3
"""Draws a ScreenGui dumped by tools/sim/dumpui.luau (rough preview of a UI screen).

    python3 tools/sim/uirender.py tools/sim/out/intro_lakeside.json [out.png] [--bg scene.png]

Supports Position/Size/AnchorPoint, AutomaticSize, UIListLayout, UIGridLayout, UIPadding,
UIScale, UICorner, UIStroke, UIGradient (2 colours), rotation, ZIndex (sibling mode),
ClipsDescendants and text (alignment, wrapping, TextScaled). Emoji are drawn with an emoji
font when one is installed. Good enough to check layout, overlap and readability.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 720
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
_fonts = {}


def font(size, bold):
    size = max(6, int(round(size)))
    key = (size, bold)
    if key not in _fonts:
        path = FONT_BOLD if bold else FONT_REG
        try:
            _fonts[key] = ImageFont.truetype(path, size)
        except OSError:
            _fonts[key] = ImageFont.load_default()
    return _fonts[key]


def text_w(t, size, bold):
    f = font(size, bold)
    lines = t.split("\n") if t else [""]
    return max(f.getlength(l) for l in lines)


def mods(n):
    m = {}
    for c in n.get("kids", []):
        k = c["k"]
        if k in ("UICorner", "UIStroke", "UIGradient", "UIListLayout", "UIGridLayout", "UIPadding", "UIScale"):
            m[k] = c
    return m


def is_gui(n):
    return "pos" in n


def gui_kids(n):
    return [c for c in n.get("kids", []) if is_gui(c) and c.get("vis", True)]


def measure(n, pw, ph, k):
    """Size of node n (w, h) inside a parent content box pw x ph, at scale k."""
    s = n["size"]
    w = s[0] * pw + s[1] * k
    h = s[2] * ph + s[3] * k
    auto = n.get("auto", "None")
    if auto != "None":
        m = mods(n)
        pad = m.get("UIPadding", {}).get("p", [0, 0, 0, 0])
        cw, ch = 0, 0
        if "text" in n:
            cw = text_w(n["text"], n["ts"] * k, n.get("bold")) + 2
            ch = n["ts"] * k * 1.2
        lay = m.get("UIListLayout")
        kids = gui_kids(n)
        if lay:
            padv = lay["pad"][1] * k
            sizes = [measure(c, w, h, k) for c in kids]
            if lay["dir"] == "Horizontal":
                cw = max(cw, sum(x[0] for x in sizes) + padv * max(0, len(sizes) - 1))
                ch = max([ch] + [x[1] for x in sizes])
            else:
                ch = max(ch, sum(x[1] for x in sizes) + padv * max(0, len(sizes) - 1))
                cw = max([cw] + [x[0] for x in sizes])
        else:
            for c in kids:
                cs = measure(c, w, h, k)
                cw = max(cw, c["pos"][1] * k + cs[0])
                ch = max(ch, c["pos"][3] * k + cs[1])
        if auto in ("X", "XY"):
            w = max(w, cw + (pad[0] + pad[1]) * k)
        if auto in ("Y", "XY"):
            h = max(h, ch + (pad[2] + pad[3]) * k)
    return w, h


def blend(img, box, fill, radius, stroke, grad, rot):
    x0, y0, x1, y1 = box
    if x1 - x0 < 0.5 or y1 - y0 < 0.5:
        return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if rot and abs(rot) > 0.5:
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        hw, hh = (x1 - x0) / 2, (y1 - y0) / 2
        a = math.radians(rot)
        pts = []
        for sx, sy in ((-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)):
            pts.append((cx + sx * math.cos(a) - sy * math.sin(a), cy + sx * math.sin(a) + sy * math.cos(a)))
        if fill:
            d.polygon(pts, fill=fill)
    else:
        r = min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
        if fill:
            if grad:
                # vertical/horizontal 2-colour gradient multiplied by the fill colour
                c0, c1, grot = grad
                gl = Image.new("RGBA", img.size, (0, 0, 0, 0))
                gd = ImageDraw.Draw(gl)
                horizontal = abs(math.cos(math.radians(grot))) > 0.7
                steps = int((x1 - x0) if horizontal else (y1 - y0)) or 1
                for i in range(steps):
                    t = i / max(1, steps - 1)
                    c = tuple(int(fill[j] * (c0[j] * (1 - t) + c1[j] * t) / 255) for j in range(3)) + (fill[3],)
                    if horizontal:
                        gd.line([(x0 + i, y0), (x0 + i, y1)], fill=c)
                    else:
                        gd.line([(x0, y0 + i), (x1, y0 + i)], fill=c)
                mask = Image.new("L", img.size, 0)
                ImageDraw.Draw(mask).rounded_rectangle([x0, y0, x1, y1], radius=r, fill=255)
                layer.paste(gl, (0, 0), mask)
            else:
                d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=fill)
        if stroke:
            d.rounded_rectangle([x0, y0, x1, y1], radius=r, outline=stroke[0], width=max(1, int(round(stroke[1]))))
    img.alpha_composite(layer)


def draw_text(img, n, box, k):
    t = n.get("text") or ""
    if not t or n.get("tt", 0) >= 0.99:
        return
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0
    bold = n.get("bold")
    size = n["ts"] * k
    if n.get("scaled"):
        size = min(bh * 0.9, size * 3)
        while size > 6 and text_w(t, size, bold) > bw:
            size -= 1
    f = font(size, bold)
    lines = []
    for para in t.replace("<br/>", "\n").split("\n"):
        if n.get("wrap") and bw > 10:
            words, cur = para.split(" "), ""
            for w_ in words:
                trial = (cur + " " + w_).strip()
                if f.getlength(trial) <= bw or not cur:
                    cur = trial
                else:
                    lines.append(cur)
                    cur = w_
            lines.append(cur)
        else:
            lines.append(para)
    lh = size * 1.18
    total = lh * len(lines)
    ty = n.get("ty", "Center")
    if ty == "Top":
        y = y0
    elif ty == "Bottom":
        y = y1 - total
    else:
        y = y0 + (bh - total) / 2
    alpha = int(255 * (1 - n.get("tt", 0)))
    col = tuple(n["tc"]) + (alpha,)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for line in lines:
        lw = f.getlength(line)
        tx = n.get("tx", "Center")
        if tx == "Left":
            x = x0
        elif tx == "Right":
            x = x1 - lw
        else:
            x = x0 + (bw - lw) / 2
        d.text((x, y), line, font=f, fill=col)
        y += lh
    img.alpha_composite(layer)


def render_node(img, n, pbox, k, sort_key=None):
    """pbox: parent's content box (x0, y0, x1, y1). Draws n and its subtree."""
    m = mods(n)
    x0, y0, x1, y1 = pbox
    pw, ph = x1 - x0, y1 - y0
    w, h = measure(n, pw, ph, k)
    if "_abs" in n:  # placed by a layout
        bx, by = n["_abs"]
    else:
        p = n["pos"]
        bx = x0 + p[0] * pw + p[1] * k - n["anchor"][0] * w
        by = y0 + p[2] * ph + p[3] * k - n["anchor"][1] * h
    kk = k
    if "UIScale" in m:
        sc = m["UIScale"]["scale"]
        ax, ay = bx + n["anchor"][0] * w, by + n["anchor"][1] * h
        w, h = w * sc, h * sc
        bx, by = ax - n["anchor"][0] * w, ay - n["anchor"][1] * h
        kk = k * sc
    box = (bx, by, bx + w, by + h)
    if n.get("bgt", 1) < 0.99 and n["k"] not in ("ScreenGui",):
        c = n["bg"]
        fill = (c[0], c[1], c[2], int(255 * (1 - n["bgt"])))
        radius = 0
        if "UICorner" in m:
            r = m["UICorner"]["r"]
            radius = r[0] * min(w, h) + r[1] * kk
        stroke = None
        if "UIStroke" in m and m["UIStroke"]["t"] < 0.99:
            s = m["UIStroke"]
            stroke = (tuple(s["c"]) + (int(255 * (1 - s["t"])),), s["th"] * kk)
        grad = None
        if "UIGradient" in m:
            g = m["UIGradient"]
            grad = (g["c0"], g["c1"], g["rot"])
        blend(img, box, fill, radius, stroke, grad, n.get("rot", 0))
    elif "UIStroke" in m and m["UIStroke"]["t"] < 0.99 and "text" not in n:
        s = m["UIStroke"]
        radius = 0
        if "UICorner" in m:
            r = m["UICorner"]["r"]
            radius = r[0] * min(w, h) + r[1] * kk
        blend(img, box, None, radius, (tuple(s["c"]) + (int(255 * (1 - s["t"])),), s["th"] * kk), None, 0)
    if "text" in n:
        draw_text(img, n, box, kk)
    # children
    pad = m.get("UIPadding", {}).get("p", [0, 0, 0, 0])
    cbox = (box[0] + pad[0] * kk, box[1] + pad[2] * kk, box[2] - pad[1] * kk, box[3] - pad[3] * kk)
    kids = gui_kids(n)
    cw, ch = cbox[2] - cbox[0], cbox[3] - cbox[1]
    if "UIListLayout" in m:
        lay = m["UIListLayout"]
        padv = lay["pad"][0] * (cw if lay["dir"] == "Horizontal" else ch) + lay["pad"][1] * kk
        kids = sorted(kids, key=lambda c: c.get("order", 0))
        sizes = [measure(c, cw, ch, kk) for c in kids]
        if lay["dir"] == "Horizontal":
            total = sum(s[0] for s in sizes) + padv * max(0, len(kids) - 1)
            cx = cbox[0] + ({"Center": (cw - total) / 2, "Right": cw - total}.get(lay["h"], 0))
            for c, s in zip(kids, sizes):
                cy = cbox[1] + ({"Center": (ch - s[1]) / 2, "Bottom": ch - s[1]}.get(lay["v"], 0))
                c["_abs"] = (cx, cy)
                cx += s[0] + padv
        else:
            total = sum(s[1] for s in sizes) + padv * max(0, len(kids) - 1)
            cy = cbox[1] + ({"Center": (ch - total) / 2, "Bottom": ch - total}.get(lay["v"], 0))
            for c, s in zip(kids, sizes):
                cx = cbox[0] + ({"Center": (cw - s[0]) / 2, "Right": cw - s[0]}.get(lay["h"], 0))
                c["_abs"] = (cx, cy)
                cy += s[1] + padv
    elif "UIGridLayout" in m:
        g = m["UIGridLayout"]
        cell_w = g["cell"][0] * cw + g["cell"][1] * kk
        cell_h = g["cell"][2] * ch + g["cell"][3] * kk
        pad_x = g["cpad"][0] * cw + g["cpad"][1] * kk
        pad_y = g["cpad"][2] * ch + g["cpad"][3] * kk
        per_row = max(1, int((cw + pad_x) // max(1, cell_w + pad_x)))
        if g.get("max", 0):
            per_row = min(per_row, g["max"])
        kids = sorted(kids, key=lambda c: c.get("order", 0))
        for i, c in enumerate(kids):
            c["_abs"] = (cbox[0] + (i % per_row) * (cell_w + pad_x), cbox[1] + (i // per_row) * (cell_h + pad_y))
            c["size"] = [0, cell_w / kk, 0, cell_h / kk]
    order = sorted(range(len(kids)), key=lambda i: kids[i].get("z", 1))
    if n.get("clip"):
        sub = Image.new("RGBA", img.size, (0, 0, 0, 0))
        for i in order:
            render_node(sub, kids[i], cbox, kk)
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rectangle([box[0], box[1], box[2], box[3]], fill=255)
        clipped = Image.new("RGBA", img.size, (0, 0, 0, 0))
        clipped.paste(sub, (0, 0), mask)
        img.alpha_composite(clipped)
    else:
        for i in order:
            render_node(img, kids[i], cbox, kk)


def main():
    args = [a for a in sys.argv[1:]]
    bg = None
    if "--bg" in args:
        i = args.index("--bg")
        bg = args[i + 1]
        del args[i:i + 2]
    src = args[0]
    out = args[1] if len(args) > 1 else os.path.splitext(src)[0] + ".png"
    data = json.load(open(src))
    if bg:
        img = Image.open(bg).convert("RGBA").resize((W, H))
    else:
        img = Image.new("RGBA", (W, H), (40, 44, 52, 255))
    for c in data.get("kids", []):
        if is_gui(c) and c.get("vis", True):
            render_node(img, c, (0, 0, W, H), 1)
    img.convert("RGB").save(out)
    print(out)


if __name__ == "__main__":
    main()
