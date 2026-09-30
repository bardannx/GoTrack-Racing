#!/usr/bin/env python3
"""Rough software render of a circuit dumped by tools/sim/maps.luau --dump.

    python3 tools/sim/render.py <id> [<id> ...] [--views aerial,grid,top] [--size 960x540]

Writes tools/sim/out/<id>_<view>.png. It's a painter's-algorithm box renderer (no
textures, balls and cylinders drawn as boxes/prisms): good enough to judge layout,
density, colours and whether a map looks different from the others.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent / "out"

MAT_GLOW = {"Neon"}


def unit_box():
    v = np.array([[x, y, z] for x in (-0.5, 0.5) for y in (-0.5, 0.5) for z in (-0.5, 0.5)])
    # faces as vertex index lists (outward winding not required, normals computed)
    faces = [
        [0, 1, 3, 2],  # -x
        [4, 6, 7, 5],  # +x
        [0, 4, 5, 1],  # -y
        [2, 3, 7, 6],  # +y
        [0, 2, 6, 4],  # -z
        [1, 5, 7, 3],  # +z
    ]
    return v, faces


def unit_wedge():
    # Roblox WedgePart: full height at +Z, slope down to the bottom front edge (-Z)
    v = np.array([
        [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5],
        [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5],
        [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5],
    ])
    faces = [[0, 1, 3, 2], [2, 3, 5, 4], [0, 1, 5, 4], [0, 2, 4], [1, 3, 5]]
    return v, faces


def unit_cyl(n=8):
    # axis along X, radius 0.5 in Y/Z
    v = []
    for x in (-0.5, 0.5):
        for k in range(n):
            a = 2 * math.pi * k / n
            v.append([x, 0.5 * math.cos(a), 0.5 * math.sin(a)])
    v = np.array(v)
    faces = [list(range(n)), list(range(n, 2 * n))]
    for k in range(n):
        faces.append([k, (k + 1) % n, n + (k + 1) % n, n + k])
    return v, faces


def unit_ball(n=8):
    # octahedral-ish prism approximation: two stacked 8-gons
    v = []
    for y, r in ((-0.35, 0.35), (0.0, 0.5), (0.35, 0.35)):
        for k in range(n):
            a = 2 * math.pi * k / n
            v.append([r * math.cos(a), y, r * math.sin(a)])
    v.append([0, -0.5, 0])
    v.append([0, 0.5, 0])
    v = np.array(v)
    faces = []
    for ring in range(2):
        for k in range(n):
            a, b = ring * n + k, ring * n + (k + 1) % n
            faces.append([a, b, b + n, a + n])
    bot, top = 3 * n, 3 * n + 1
    for k in range(n):
        faces.append([k, (k + 1) % n, bot])
        faces.append([2 * n + k, 2 * n + (k + 1) % n, top])
    return v, faces


SHAPES = {"Block": unit_box(), "Wedge": unit_wedge(), "Cylinder": unit_cyl(), "Ball": unit_ball()}


def look_at(eye, target):
    f = target - eye
    f = f / np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0])
    r = r / np.linalg.norm(r)
    u = np.cross(r, f)
    return f, r, u


def render(data, view, size):
    W, H = size
    parts = data["parts"]
    track = np.array(data["track"])
    sky = data["sky"]
    night = sky.get("night")
    cx, cz = track[:, 0].mean(), track[:, 2].mean()
    span = max(np.ptp(track[:, 0]), np.ptp(track[:, 2]))
    if view == "aerial":
        eye = np.array([cx + span * 0.15, span * 0.55 + 250, cz + span * 0.85 + 300])
        target = np.array([cx, 0, cz - span * 0.05])
        fov = 55
    elif view == "top":
        eye = np.array([cx, span * 1.25 + 600, cz + 1])
        target = np.array([cx, 0, cz])
        fov = 50
    else:  # grid: behind the start line, low
        p0, p1 = track[0], track[3]
        d = (p1 - p0)
        d = d / np.linalg.norm(d)
        eye = p0 - d * 140 + np.array([0, 38, 0])
        target = p0 + d * 260 + np.array([0, 4, 0])
        fov = 70
    f, r, u = look_at(eye, target)
    fl = (H / 2) / math.tan(math.radians(fov) / 2)
    light = np.array([0.4, 0.85, 0.35])
    light = light / np.linalg.norm(light)

    polys = []
    for p in parts:
        if p["t"] >= 0.98:
            continue
        shape = "Wedge" if p["k"] == "WedgePart" else p["s"]
        sz = np.array(p["z"], dtype=float)
        if p.get("e"):
            shape = "Ball"  # SpecialMesh sphere: a stretched ellipsoid
        elif shape == "Ball":
            sz = np.full(3, sz.min())  # Roblox balls are always round
        elif shape == "Cylinder":
            sz[1] = sz[2] = min(sz[1], sz[2])
        verts, faces = SHAPES.get(shape, SHAPES["Block"])
        c = p["c"]
        pos = np.array(c[0:3])
        rot = np.array([[c[3], c[4], c[5]], [c[6], c[7], c[8]], [c[9], c[10], c[11]]])
        world = (verts * sz) @ rot.T + pos
        rel = world - eye
        zc = rel @ f
        if zc.max() < 1:
            continue
        xs = rel @ r
        ys = rel @ u
        big = sz.max() > 1500
        col = np.array(p["col"], dtype=float)
        glow = p["m"] in MAT_GLOW
        alpha = int(255 * (1 - p["t"]))
        centre_rel = pos - eye
        for fi in faces:
            fz = zc[fi]
            if fz.min() < 1:
                continue
            a, b, cc = world[fi[0]], world[fi[1]], world[fi[2]]
            n = np.cross(b - a, cc - a)
            nl = np.linalg.norm(n)
            if nl < 1e-9:
                continue
            n = n / nl
            fc = world[fi].mean(axis=0)
            # make the normal point outward (away from the part centre)
            if np.dot(n, fc - pos) < 0:
                n = -n
            if np.dot(n, fc - eye) >= 0:
                continue  # back face
            px = W / 2 + xs[fi] / fz * fl
            py = H / 2 - ys[fi] / fz * fl
            if px.max() < -50 or px.min() > W + 50 or py.max() < -50 or py.min() > H + 50:
                continue
            if glow:
                shade = col
            else:
                lam = max(0.0, float(np.dot(n, light)))
                shade = col * (0.5 + 0.55 * lam) * (0.75 if night else 1.0)
            depth = float(np.linalg.norm(fc - eye))
            # fog
            fog = min(1.0, depth / (span * 4 + 2500))
            fogc = np.array([60, 70, 110]) if night else np.array([190, 210, 235])
            shade = shade * (1 - fog * 0.6) + fogc * fog * 0.6
            key = -1e12 + depth if False else depth
            if big:
                key = 1e12 + depth  # ground and sea first
            polys.append((key, list(zip(px.tolist(), py.tolist())), tuple(int(max(0, min(255, v))) for v in shade) + (alpha,)))
    polys.sort(key=lambda x: -x[0])
    top = (40, 50, 95) if night else (120, 170, 230)
    bot = (110, 90, 140) if night else (215, 228, 245)
    img = Image.new("RGBA", (W, H))
    grad = np.linspace(0, 1, H)[:, None]
    arr = (np.array(top)[None, :] * (1 - grad) + np.array(bot)[None, :] * grad).astype(np.uint8)
    img = Image.fromarray(np.repeat(arr[:, None, :], W, axis=1), "RGB").convert("RGBA")
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, "RGBA")
    for _, pts, colr in polys:
        if len(pts) >= 3:
            draw.polygon(pts, fill=colr)
    return img.convert("RGB")


def main():
    args = sys.argv[1:]
    views = ["aerial", "grid"]
    size = (960, 540)
    ids = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--views":
            views = args[i + 1].split(",")
            i += 2
            continue
        if a == "--size":
            w, h = args[i + 1].split("x")
            size = (int(w), int(h))
            i += 2
            continue
        ids.append(a)
        i += 1
    for cid in ids:
        data = json.loads((OUT / f"{cid}.json").read_text())
        for v in views:
            img = render(data, v, size)
            path = OUT / f"{cid}_{v}.png"
            img.save(path)
            print(path)


if __name__ == "__main__":
    main()
