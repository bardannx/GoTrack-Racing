"""The world-mesh designs: skyscrapers, midrises, houses, a mall, trees, rocks, mountains
and road vehicles. Each design returns {slot: faces}; the slot decides its colour and
material in game (see src/client/WorldMeshes.luau).

Slots
  Glass  curtain-wall glass            Frame  mullions, floor bands, balconies, masts
  Wall   masonry / plaster / brick     Trim   cornices, piers, doors, window frames
  WinA / WinB  window panes: two random sets, so at night some windows glow
  Roof   roofs and rooftop plant       Accent sign bands, awnings, shutters
  Beacon aircraft warning light        Leaf / Trunk / Snow   trees
  Rock / Base / Band   rocks and mountains (Base = the ground colour)
  Body / Dark / Light / TailLight      road vehicles (nose at -z)

Units are studs. A person is ~5 studs, a race car 14.6 studs long, a floor ~10 studs.
"""
import math

import numpy as np

import geom as G
from geom import v

DESIGNS = {}


def design(name, kind, w, d, smooth=False):
    def deco(fn):
        DESIGNS[name] = {"fn": fn, "kind": kind, "w": w, "d": d, "smooth": smooth}
        return fn

    return deco


class Out:
    def __init__(self):
        self.slots = {}

    def add(self, slot, faces):
        if faces:
            self.slots.setdefault(slot, []).extend(faces)
        return self

    def wins(self, pair):
        self.add("WinA", pair[0])
        self.add("WinB", pair[1])


def rng_for(name):
    """Deterministic per design, so every export gives the same meshes."""
    return np.random.default_rng(sum(ord(c) * (i + 1) for i, c in enumerate(name)))


def allp(pair):
    return pair[0] + pair[1]


def slab(top, t):
    """Close a top quad into a slab of thickness t (hanging below it)."""
    n = G.normal(top)
    n = n / np.linalg.norm(n) if n[1] >= 0 else -n / np.linalg.norm(n)
    bot = [p - n * t for p in top]
    faces = [top, bot] + [[top[k], top[(k + 1) % 4], bot[(k + 1) % 4], bot[k]] for k in range(4)]
    return G.outward(faces, G.centroid(top) - n * t / 2)


def gable_slabs(cx, cz, w, d, y0, h, over, t=0.6):
    """Gable roof as two thin sloped slabs (ridge along x): the wall's gable ends stay visible."""
    W2, hd = w / 2 + over, d / 2
    yE = y0 - over * h / hd
    yR = y0 + h
    front = [v(cx - W2, yE, cz - hd - over), v(cx + W2, yE, cz - hd - over), v(cx + W2, yR, cz), v(cx - W2, yR, cz)]
    back = [v(cx - W2, yE, cz + hd + over), v(cx + W2, yE, cz + hd + over), v(cx + W2, yR, cz), v(cx - W2, yR, cz)]
    return slab(front, t) + slab(back, t)


def fins(out, cx, cz, w, d, y0, y1, n_w, n_d, depth=0.8, width=0.7, ang=0.0):
    """Vertical mullion fins standing proud of a w x d glass box."""
    faces = []
    for k in range(1, n_w):
        x = -w / 2 + k * w / n_w
        for z in (-d / 2, d / 2):
            faces += G.ybox(x, z, width, depth, y0, y1, skip=("ny",))
    for k in range(1, n_d):
        z = -d / 2 + k * d / n_d
        for x in (-w / 2, w / 2):
            faces += G.ybox(x, z, depth, width, y0, y1, skip=("ny",))
    for x in (-w / 2, w / 2):
        for z in (-d / 2, d / 2):
            faces += G.ybox(x, z, 1.2, 1.2, y0, y1, skip=("ny",))
    if ang:
        faces = G.rot_y(faces, ang)
    out.add("Frame", G.move(faces, cx, 0, cz))


def bands(out, cx, cz, w, d, ys, t=0.8, over=0.5, slot="Frame", ang=0.0):
    faces = []
    for y in ys:
        faces += G.box(0, y, 0, w + over * 2, t, d + over * 2)
    if ang:
        faces = G.rot_y(faces, ang)
    out.add(slot, G.move(faces, cx, 0, cz))


def rooftop_plant(out, cx, cz, w, d, y, rng, n=3, slot="Roof"):
    faces = G.ybox(cx, cz, w, d, y, y + 1.2, skip=())  # parapet slab
    for _ in range(n):
        x = cx + rng.uniform(-w / 2 + 3, w / 2 - 3)
        z = cz + rng.uniform(-d / 2 + 3, d / 2 - 3)
        faces += G.ybox(x, z, rng.uniform(3, 5), rng.uniform(2.5, 4), y + 1.2, y + 1.2 + rng.uniform(1.6, 3))
    out.add(slot, faces)


def mast(out, x, z, y0, h, r=0.7):
    out.add("Frame", G.frustum(x, z, r, r * 0.45, y0, y0 + h, 6))
    out.add("Beacon", G.box(x, y0 + h + 0.6, z, 1.4, 1.2, 1.4))


# ---------------------------------------------------------------------------
# SKYSCRAPERS (kind "tower")
# ---------------------------------------------------------------------------
@design("tower_glass", "tower", 36, 36)
def tower_glass():
    o, r = Out(), rng_for("tower_glass")
    o.add("Glass", G.ybox(0, 0, 34, 34, 0, 10))  # lobby
    o.add("Frame", G.box(0, 10.4, -18.5, 20, 0.8, 5))  # canopy
    o.add("Glass", G.ybox(0, 0, 32, 32, 10, 170))
    o.add("Glass", G.ybox(0, 0, 25, 25, 170, 214))
    fins(o, 0, 0, 32, 32, 10, 170, 8, 8)
    fins(o, 0, 0, 25, 25, 170, 214, 6, 6)
    bands(o, 0, 0, 32, 32, [10 + 20 * k for k in range(1, 8)] + [170])
    bands(o, 0, 0, 25, 25, [190, 214])
    o.wins(G.box_panes(0, 0, 32, 32, 10, 170, 10, 4, 3, 6.4, 0.18, r))
    o.wins(G.box_panes(0, 0, 25, 25, 170, 214, 10, 4.1, 3, 6.4, 0.18, r))
    o.add("Frame", G.ybox(0, 0, 19, 19, 214, 226, skip=()))  # crown
    o.add("Frame", G.box(0, 220, 0, 22, 2, 22))
    rooftop_plant(o, 0, 0, 17, 17, 226, r, 2)
    mast(o, 0, 0, 228, 34)
    return o


@design("tower_deco", "tower", 40, 40)
def tower_deco():
    o, r = Out(), rng_for("tower_deco")
    tiers = [(40, 0, 120), (32, 120, 190), (24, 190, 236)]
    for w, y0, y1 in tiers:
        o.add("Wall", G.ybox(0, 0, w, w, y0, y1))
        # stone piers between window columns
        cols = int(w // 4.5)
        piers = []
        for k in range(1, cols):
            x = -w / 2 + k * w / cols
            for z in (-w / 2, w / 2):
                piers += G.ybox(x, z, 0.8, 1.2, y0 + (10 if y0 == 0 else 0), y1)
                piers += G.ybox(z, x, 1.2, 0.8, y0 + (10 if y0 == 0 else 0), y1)
        o.add("Trim", piers)
        o.wins(G.box_panes(0, 0, w, w, y0 + (10 if y0 == 0 else 0), y1, 9, w / cols, 2.6, 5.8, 0.12, r))
        o.add("Trim", G.box(0, y1 + 0.8, 0, w + 2, 1.6, w + 2))  # setback ledge
    o.add("Glass", allp(G.box_panes(0, 0, 40, 40, 1, 9, 8, 6, 5, 6, 0.15, r)))
    # stepped crown and spire
    o.add("Trim", G.frustum(0, 0, 11, 9, 237.6, 250, 8, a0=math.pi / 8))
    o.add("Trim", G.frustum(0, 0, 8, 6, 250, 260, 8, a0=math.pi / 8))
    o.add("Trim", G.frustum(0, 0, 5.5, 3.5, 260, 268, 8, a0=math.pi / 8))
    o.add("Frame", G.cone(0, 0, 3.2, 268, 308, 8, a0=math.pi / 8, bottom=False))
    # crown windows (triangular dormers approximated by panes)
    o.wins(G.ring_panes(0, 0, 9.7, 8, 239, 249, 10, 7, 0.15, r, a0=math.pi / 8, fill=0.45))
    o.add("Beacon", G.box(0, 309, 0, 1.2, 1.2, 1.2))
    return o


@design("tower_twist", "tower", 38, 38)
def tower_twist():
    o, r = Out(), rng_for("tower_twist")
    n = 26
    for k in range(n):
        ang = math.radians(k * 3.5)
        y0, y1 = 6 + k * 9, 6 + (k + 1) * 9
        o.add("Glass", G.rot_y(G.ybox(0, 0, 28, 28, y0, y1, skip=("ny",) if k else ()), ang))
        o.add("Frame", G.rot_y(G.box(0, y1, 0, 29.4, 0.7, 29.4), ang))
        a, b = G.box_panes(0, 0, 28, 28, y0, y1, 9, 4, 3, 5.6, 0.16, r)
        o.add("WinA", G.rot_y(a, ang))
        o.add("WinB", G.rot_y(b, ang))
    o.add("Glass", G.ybox(0, 0, 32, 32, 0, 6, skip=()))
    o.add("Frame", G.box(0, 6, 0, 33, 0.8, 33))
    top = 6 + n * 9
    ang = math.radians(n * 3.5)
    o.add("Frame", G.rot_y(G.ybox(0, 0, 22, 22, top, top + 8, skip=()), ang))
    o.add("Frame", G.rot_y(G.ybox(0, 0, 3, 3, top + 8, top + 30), ang + 0.3))
    o.add("Beacon", G.box(0, top + 31, 0, 1.2, 1.2, 1.2))
    return o


@design("tower_round", "tower", 36, 36)
def tower_round():
    o, r = Out(), rng_for("tower_round")
    n, R = 20, 16
    o.add("Glass", G.frustum(0, 0, R + 2, R + 2, 0, 9, n))
    o.add("Glass", G.frustum(0, 0, R, R, 9, 219, n, top=False))
    o.wins(G.ring_panes(0, 0, R, n, 9, 219, 10, 6.6, 0.18, r))
    rings = []
    for k in range(1, 8):
        y = 9 + k * 30
        rings += G.frustum(0, 0, R + 1.4, R + 1.4, y - 0.5, y + 0.5, n, bottom=True)
    o.add("Frame", rings)
    # vertical ribs
    ribs = []
    for k in range(0, n, 2):
        a = 2 * math.pi * k / n
        x, z = math.cos(a) * (R + 0.2), math.sin(a) * (R + 0.2)
        ribs += G.move(G.rot_y(G.ybox(0, 0, 1.0, 0.7, 9, 219), -a), x, 0, z)
    o.add("Frame", ribs)
    o.add("Frame", G.frustum(0, 0, R + 0.8, 11, 219, 234, n))
    o.add("Glass", G.frustum(0, 0, 9, 9, 234, 244, n))
    o.add("Frame", G.frustum(0, 0, 10, 10, 244, 246, n, bottom=True))
    mast(o, 0, 0, 246, 26)
    return o


@design("tower_blade", "tower", 44, 36)
def tower_blade():
    o, r = Out(), rng_for("tower_blade")
    H = 300

    def rect(y):
        k = y / H
        w, d = 40 * (1 - k) + 6 * k, 32 * (1 - k) + 5 * k
        return w, d

    def rect_ring(y, grow=0.0):
        w, d = rect(y)
        w, d = w / 2 + grow, d / 2 + grow
        return [v(-w, y, -d), v(w, y, -d), v(w, y, d), v(-w, y, d)]

    o.add("Glass", G.loft([rect_ring(y) for y in (0, 100, 200, H)], top=True))
    bandsF = []
    for k in range(1, 12):
        y = k * 25
        bandsF += G.loft([rect_ring(y - 0.6, 0.5), rect_ring(y + 0.6, 0.5)], top=True, bottom=True)
    o.add("Frame", bandsF)
    # lit strips: one per floor per face
    A, B = [], []
    for f in range(1, 29):
        y = f * 10 + 5
        w, d = rect(y)
        k = 0.85
        for side, (p0, p1, n) in enumerate([((-w / 2, -d / 2), (w / 2, -d / 2), (0, 0, -1)), ((w / 2, -d / 2), (w / 2, d / 2), (1, 0, 0)), ((w / 2, d / 2), (-w / 2, d / 2), (0, 0, 1)), ((-w / 2, d / 2), (-w / 2, -d / 2), (-1, 0, 0))]):
            # the faces lean inwards: tilt the strip normal to match
            mid = v((p0[0] + p1[0]) / 2, y, (p0[1] + p1[1]) / 2)
            L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
            u = v((p1[0] - p0[0]) / L, 0, (p1[1] - p0[1]) / L)
            nn = v(*n)
            q = G.pane(mid + nn * 0.25, u, nn, L * k, 3.2)
            (A if r.random() < 0.5 else B).append(q)
    o.add("WinA", A)
    o.add("WinB", B)
    # corner spikes at the top
    o.add("Frame", G.cone(0, 0, 3, H, H + 40, 4, a0=math.pi / 4, bottom=False))
    o.add("Beacon", G.box(0, H + 41, 0, 1, 1, 1))
    o.add("Glass", G.ybox(0, 0, 46, 38, 0, 8, skip=()))
    return o


@design("tower_twin", "tower", 64, 28)
def tower_twin():
    o, r = Out(), rng_for("tower_twin")
    for sx in (-18, 18):
        o.add("Glass", G.frustum(sx, 0, 11.5, 11.5, 0, 196, 8, a0=math.pi / 8, top=False))
        o.add("Glass", G.frustum(sx, 0, 11.5, 9, 196, 206, 8, a0=math.pi / 8, top=False))
        o.add("Glass", G.frustum(sx, 0, 9, 9, 206, 226, 8, a0=math.pi / 8, top=False))
        o.add("Glass", G.frustum(sx, 0, 9, 6, 226, 234, 8, a0=math.pi / 8, top=False))
        o.add("Glass", G.frustum(sx, 0, 6, 6, 234, 246, 8, a0=math.pi / 8))
        o.add("Frame", G.cone(sx, 0, 2.6, 246, 290, 8, bottom=False))
        o.add("Beacon", G.box(sx, 291, 0, 1, 1, 1))
        o.wins(G.ring_panes(sx, 0, 11.5, 8, 4, 196, 8, 5.2, 0.15, r, a0=math.pi / 8, fill=0.7))
        o.wins(G.ring_panes(sx, 0, 9, 8, 206, 226, 8, 5.2, 0.15, r, a0=math.pi / 8, fill=0.7))
        fr = []
        for k in range(1, 13):
            y = k * 16
            fr += G.frustum(sx, 0, 12.3, 12.3, y - 0.5, y + 0.5, 8, a0=math.pi / 8, bottom=True)
        o.add("Frame", fr)
    # skybridge with its legs
    o.add("Frame", G.box(0, 124, 0, 16, 5, 6))
    o.add("Glass", G.box(0, 124, 0, 16.4, 3, 5.2))
    for sx in (-1, 1):
        o.add("Frame", G.rot_axis(G.box(sx * 5, 104, 0, 1.4, 42, 1.4), (0, 0, 1), sx * 0.35, (sx * 5, 104, 0)))
    o.add("Wall", G.ybox(0, 0, 64, 28, 0, 8, skip=()))
    return o


@design("tower_stack", "tower", 42, 42)
def tower_stack():
    o, r = Out(), rng_for("tower_stack")
    offs = [(0, 0), (5, -4), (-4, 3), (4, 5), (-3, -5)]
    y = 0
    for k, (dx, dz) in enumerate(offs):
        h = 40
        o.add("Glass", G.ybox(dx, dz, 30, 30, y, y + h, skip=()))
        corners = []
        for x in (-15, 15):
            for z in (-15, 15):
                corners += G.ybox(dx + x, dz + z, 1.4, 1.4, y, y + h, skip=())
        o.add("Frame", corners)
        bands(o, dx, dz, 30, 30, [y + 0.4, y + h - 0.4], t=0.8, over=0.4)
        o.wins(G.box_panes(dx, dz, 30, 30, y, y + h, 10, 4.2, 3.2, 6.4, 0.18, r))
        y += h
    rooftop_plant(o, -3, -5, 22, 22, y, r, 3)
    # sky garden on the setbacks
    o.add("Leaf", G.blob(10, 41.5, 12, 3, 1, 0.2, r, 1, 0.6, 1) + G.blob(-12, 81.5, -9, 3, 1, 0.2, r, 1, 0.6, 1))
    return o


@design("tower_resi", "tower", 40, 24)
def tower_resi():
    o, r = Out(), rng_for("tower_resi")
    W, D, H, fh = 38, 18, 180, 9
    o.add("Wall", G.ybox(0, 0, W, D, 0, H))
    o.wins(G.box_panes(0, 0, W, D, 0, H, fh, 4.6, 3, 5, 0.14, r, skip_floors=1))
    bal = []
    for f in range(1, int(H // fh)):
        y = f * fh + 0.3
        for z in (-D / 2 - 1.6, D / 2 + 1.6):
            bal += G.box(0, y, z, W - 4, 0.6, 3.2)
            bal += G.box(0, y + 1.3, z + (-1.5 if z < 0 else 1.5), W - 4, 2, 0.25)
    o.add("Frame", bal)
    o.add("Glass", allp(G.box_panes(0, 0, W, D, 0.5, 8.5, 8, 6, 5, 6.5, 0.15, r)))
    o.add("Trim", G.box(0, H + 0.6, 0, W + 1, 1.2, D + 1))
    o.add("Roof", G.ybox(6, 0, 16, 10, H + 1.2, H + 8, skip=()))
    o.add("Roof", G.frustum(-10, 0, 3.4, 3.4, H + 1.2, H + 9, 10) + G.cone(-10, 0, 3.8, H + 9, H + 11, 10))
    return o


# ---------------------------------------------------------------------------
# MIDRISES (kind "mid")
# ---------------------------------------------------------------------------
@design("mid_office", "mid", 40, 30)
def mid_office():
    o, r = Out(), rng_for("mid_office")
    W, D = 38, 28
    o.add("Wall", G.ybox(0, 0, W, D, 0, 58))
    ribbons = []
    A, B = [], []
    for f in range(6):
        y = 4 + f * 9
        ribbons += G.box(0, y + 2, 0, W + 0.5, 4, D + 0.5)
        a, b = G.box_panes(0, 0, W + 0.5, D + 0.5, y, y + 4, 4, 6, 5.4, 3.4, 0.12, r)
        A += a
        B += b
    o.add("Glass", ribbons)
    o.add("WinA", A)
    o.add("WinB", B)
    o.add("Glass", G.box(0, 0.1 + 1.7, -D / 2 - 0.1, 14, 3.4, 0.4))
    o.add("Frame", G.box(0, 4.2, -D / 2 - 2, 18, 0.5, 4))
    rooftop_plant(o, 4, 2, 16, 12, 58, r, 3)
    return o


@design("mid_apart", "mid", 32, 24)
def mid_apart():
    o, r = Out(), rng_for("mid_apart")
    W, D, H, fh = 30, 20, 44, 8.4
    o.add("Wall", G.ybox(0, 0, W, D, 0, H))
    o.wins(G.box_panes(0, 0, W, D, 0, H - 2, fh, 5, 2.6, 4, 0.12, r, skip_floors=1))
    bal = []
    for f in range(1, 5):
        y = f * fh + 0.2
        bal += G.box(0, y, -D / 2 - 1.3, W - 6, 0.5, 2.6)
        bal += G.box(0, y + 1.3, -D / 2 - 2.5, W - 6, 2.2, 0.25)
    o.add("Frame", bal)
    o.add("Glass", G.box(0, 3.2, -D / 2 - 0.12, W - 4, 4.4, 0.3))
    o.add("Accent", G.rot_axis(G.box(0, 7.2, -D / 2 - 1.6, W - 3, 0.35, 3.2), (1, 0, 0), -0.25, (0, 7.2, -D / 2)))
    o.add("Trim", G.box(0, H + 0.5, 0, W + 1.2, 1, D + 1.2))
    o.add("Trim", G.box(0, fh - 0.2, 0, W + 0.6, 0.6, D + 0.6))
    # water tank on legs
    t = []
    for dx in (-1.6, 1.6):
        for dz in (-1.6, 1.6):
            t += G.ybox(6 + dx, 3 + dz, 0.5, 0.5, H + 1, H + 5)
    t += G.frustum(6, 3, 3, 3, H + 5, H + 11, 10, bottom=True) + G.cone(6, 3, 3.3, H + 11, H + 13, 10, bottom=False)
    o.add("Roof", t)
    rooftop_plant(o, -6, 0, 12, 12, H + 1, r, 2)
    return o


@design("mid_euro", "mid", 30, 22)
def mid_euro():
    o, r = Out(), rng_for("mid_euro")
    W, D = 28, 18
    o.add("Wall", G.ybox(0, 0, W, D, 0, 32))
    o.wins(G.box_panes(0, 0, W, D, 7, 31, 8, 5.4, 2.6, 5, 0.14, r))
    tr = []
    for y in (7, 15, 23):
        tr += G.box(0, y, 0, W + 0.8, 0.6, D + 0.8)
    tr += G.box(0, 32.3, 0, W + 1.6, 1.2, D + 1.6)
    # window surrounds on the front
    for k in range(5):
        x = -W / 2 + (k + 0.5) * W / 5
        for y in (11, 19, 27):
            tr += G.box(x, y - 3.1, -D / 2 - 0.3, 3.4, 0.5, 0.6)
    o.add("Trim", tr)
    # mansard roof with dormers
    o.add("Roof", G.loft([[v(-W / 2, 32.9, -D / 2), v(W / 2, 32.9, -D / 2), v(W / 2, 32.9, D / 2), v(-W / 2, 32.9, D / 2)], [v(-W / 2 + 4, 41, -D / 2 + 4), v(W / 2 - 4, 41, -D / 2 + 4), v(W / 2 - 4, 41, D / 2 - 4), v(-W / 2 + 4, 41, D / 2 - 4)]], top=True))
    dorm = []
    wa = []
    for k in (-1, 0, 1):
        x = k * 8
        dorm += G.ybox(x, -D / 2 + 3, 3.6, 3, 33.5, 38, skip=())
        s, e = G.gable(x, -D / 2 + 3, 3.6, 3.2, 38, 1.8, 0.2, ridge_x=False)
        dorm += s + e
        wa.append(G.pane(v(x, 35.7, -D / 2 + 1.4), (1, 0, 0), (0, 0, -1), 2, 3))
    o.add("Roof", dorm)
    o.add("WinA", wa)
    o.add("Glass", G.box(0, 3.2, -D / 2 - 0.12, W - 4, 4.6, 0.3))
    o.add("Accent", G.rot_axis(G.box(0, 6.1, -D / 2 - 1.5, W - 2, 0.3, 3), (1, 0, 0), -0.3, (0, 6.1, -D / 2)))
    o.add("Roof", G.ybox(8, 4, 2, 2, 38, 45, skip=()))  # chimney
    return o


@design("mid_loft", "mid", 44, 32)
def mid_loft():
    o, r = Out(), rng_for("mid_loft")
    W, D, H = 42, 28, 36
    o.add("Wall", G.ybox(0, 0, W, D, 0, H))
    o.wins(G.box_panes(0, 0, W, D, 1, H - 3, 8.5, 6, 3.8, 6, 0.14, r))
    tr = G.box(0, H + 0.6, 0, W + 1.4, 1.2, D + 1.4) + G.box(0, 9.5, 0, W + 0.6, 0.8, D + 0.6)
    for k in range(8):
        x = -W / 2 + k * W / 7
        tr += G.ybox(x, -D / 2, 1.2, 1.2, 0, H)
        tr += G.ybox(x, D / 2, 1.2, 1.2, 0, H)
    o.add("Trim", tr)
    # wooden water tower
    t = []
    for dx in (-2.2, 2.2):
        for dz in (-2.2, 2.2):
            t += G.ybox(-10 + dx, 4 + dz, 0.6, 0.6, H + 1, H + 7)
    t += G.frustum(-10, 4, 4, 4, H + 7, H + 15, 12, bottom=True) + G.cone(-10, 4, 4.4, H + 15, H + 19, 12, bottom=False)
    o.add("Roof", t)
    rooftop_plant(o, 8, 0, 16, 16, H + 1, r, 2)
    return o


@design("mall", "mid", 72, 52)
def mall():
    o, r = Out(), rng_for("mall")
    W, D = 70, 50
    o.add("Wall", G.ybox(0, 0, W, D, 0, 16))
    o.add("Glass", G.ybox(0, -D / 2 - 1, 22, 4, 0, 12, skip=()))
    o.add("Frame", G.box(0, 12.5, -D / 2 - 3, 28, 1, 8))
    o.add("Accent", G.box(0, 14.5, -D / 2 - 0.3, 46, 3.6, 0.6))
    o.add("Accent", G.box(0, 16.2, 0, W + 0.4, 0.6, D + 0.4))
    o.add("Glass", G.box(-24, 5, -D / 2 - 0.1, 16, 6, 0.3) + G.box(24, 5, -D / 2 - 0.1, 16, 6, 0.3))
    rooftop_plant(o, 0, 5, 60, 36, 16, r, 7)
    return o


# ---------------------------------------------------------------------------
# HOUSES (kind "house")
# ---------------------------------------------------------------------------
@design("house_gable", "house", 24, 22)
def house_gable():
    o, r = Out(), rng_for("house_gable")
    W, D, H = 20, 14, 13
    o.add("Wall", G.ybox(0, 0, W, D, 0, H))
    o.add("Roof", gable_slabs(0, 0, W, D, H, 6, 1.2))
    o.add("Wall", G.gable(0, 0, W, D, H, 6, 0)[1])
    A, B = G.box_panes(0, 0, W, D, 1, H, 6, 5, 2.4, 3, 0.12, r, margin=1)
    o.add("WinA", A + B)
    o.add("Trim", G.box(-5, 3.2, -D / 2 - 0.15, 3, 6.4, 0.3))  # door
    o.add("Roof", G.box(-5, 7, -D / 2 - 2, 7, 0.4, 4))  # porch roof
    o.add("Trim", G.ybox(-8, -D / 2 - 3.6, 0.5, 0.5, 0, 7) + G.ybox(-2, -D / 2 - 3.6, 0.5, 0.5, 0, 7))
    o.add("Roof", G.ybox(6, 3, 2, 2, H + 2, H + 8, skip=()))  # chimney
    o.add("Trim", G.box(0, 0.3, 0, W + 0.4, 0.6, D + 0.4))
    return o


@design("house_hip", "house", 26, 22)
def house_hip():
    o, r = Out(), rng_for("house_hip")
    W, D, H = 24, 17, 9
    o.add("Wall", G.ybox(0, 0, W, D, 0, H))
    o.add("Roof", G.hip(0, 0, W, D, H, 5.5, 1.4))
    A, B = G.box_panes(0, 0, W, D, 1, H, 8, 5.6, 3, 3.6, 0.12, r, margin=1.5)
    o.add("WinA", A + B)
    o.add("Trim", G.box(6, 3.2, -D / 2 - 0.15, 3, 6.4, 0.3))
    o.add("Trim", G.box(-7, 3, -D / 2 - 0.15, 8, 6, 0.3))  # garage door
    o.add("Trim", G.box(0, 0.3, 0, W + 0.4, 0.6, D + 0.4))
    return o


@design("house_modern", "house", 28, 24)
def house_modern():
    o, r = Out(), rng_for("house_modern")
    o.add("Wall", G.ybox(-2, 0, 24, 18, 0, 8.5))
    o.add("Wall", G.ybox(3, -1, 20, 20, 8.5, 16))
    o.add("Glass", G.box(-4, 4.2, -9.15, 16, 7, 0.3))
    o.add("WinA", [G.pane(v(-4, 4.2, -9.4), (1, 0, 0), (0, 0, -1), 15, 6.4)])
    o.add("Glass", G.box(3, 12.3, -11.15, 16, 5.6, 0.3))
    o.add("WinA", [G.pane(v(3, 12.3, -11.4), (1, 0, 0), (0, 0, -1), 15, 5)])
    o.add("Trim", G.box(3, 16.3, -1, 21, 0.6, 21) + G.box(-2, 8.7, 0, 25, 0.4, 19))
    slats = []
    for k in range(10):
        slats += G.box(9 + k * 0.9 - 4, 4.2, -9.3, 0.4, 8, 0.4)
    o.add("Accent", slats)
    return o


@design("house_villa", "house", 26, 24)
def house_villa():
    o, r = Out(), rng_for("house_villa")
    W, D, H = 22, 18, 14
    o.add("Wall", G.ybox(0, 0, W, D, 0, H))
    o.add("Roof", G.hip(0, 0, W, D, H, 5, 1.6))
    wa, sh = [], []
    for side in (-1, 1):
        for k in range(3):
            x = -W / 2 + (k + 0.5) * W / 3
            for y in (4, 10.5):
                z = side * (D / 2 + 0.12)
                wa.append(G.pane(v(x, y, z), (1, 0, 0), (0, 0, side), 2.4, 3.6))
                if side < 0:
                    sh += G.box(x - 2.1, y, z - 0.1, 1.2, 3.8, 0.2) + G.box(x + 2.1, y, z - 0.1, 1.2, 3.8, 0.2)
    o.add("WinA", wa)
    o.add("Accent", sh)
    # arched loggia on the ground floor front
    lo = G.box(0, 6.7, -D / 2 - 3, W - 2, 1, 6)
    for k in range(4):
        lo += G.ybox(-W / 2 + 1 + k * (W - 2) / 3, -D / 2 - 5.6, 1, 1, 0, 6.2)
    o.add("Trim", lo)
    o.add("Trim", G.box(0, 7.2, 0, W + 0.6, 0.6, D + 0.6))
    return o


# ---------------------------------------------------------------------------
# TREES (kind "tree"): Leaf / Trunk (/ Snow)
# ---------------------------------------------------------------------------
@design("tree_oak", "tree", 16, 16)
def tree_oak():
    o, r = Out(), rng_for("tree_oak")
    o.add("Trunk", G.frustum(0, 0, 1.2, 0.7, 0, 10, 6))
    o.add("Trunk", G.rot_axis(G.frustum(0, 0, 0.5, 0.3, 7, 12, 5), (0, 0, 1), -0.6, (0, 7, 0)))
    o.add("Leaf", G.blob(0, 13, 0, 6.5, 1, 0.2, r, 1, 0.85, 1))
    o.add("Leaf", G.blob(3.4, 15, 1.4, 4.6, 1, 0.22, r))
    o.add("Leaf", G.blob(-3, 14.4, -2, 4.3, 1, 0.22, r))
    o.add("Leaf", G.blob(0.6, 17.6, -0.6, 3.6, 1, 0.2, r))
    return o


@design("tree_pine", "tree", 14, 14)
def tree_pine():
    o, r = Out(), rng_for("tree_pine")
    o.add("Trunk", G.frustum(0, 0, 0.9, 0.5, 0, 8, 6))
    tiers = [(6.6, 4, 13), (5.4, 9, 17), (4.2, 13, 21), (2.9, 17, 26)]
    for k, (rad, y0, y1) in enumerate(tiers):
        o.add("Leaf", G.cone(0, 0, rad, y0, y1, 8, a0=k * 0.4))
    return o


@design("tree_snowpine", "tree", 14, 14)
def tree_snowpine():
    """Pine with a band of snow lying on every tier."""
    o, r = Out(), rng_for("tree_snowpine")
    o.add("Trunk", G.frustum(0, 0, 0.9, 0.5, 0, 8, 6))
    tiers = [(6.6, 4, 13), (5.4, 9, 17), (4.2, 13, 21), (2.9, 17, 26)]
    for k, (rad, y0, y1) in enumerate(tiers):
        h = y1 - y0
        a = k * 0.4
        o.add("Leaf", G.frustum(0, 0, rad, rad * 0.8, y0, y0 + 0.2 * h, 8, a0=a, top=False, bottom=True))
        o.add("Snow", G.frustum(0, 0, rad * 0.8 + 0.15, rad * 0.5 + 0.15, y0 + 0.2 * h, y0 + 0.5 * h, 8, a0=a, top=False))
        o.add("Leaf" if k < 3 else "Snow", G.cone(0, 0, rad * 0.5, y0 + 0.5 * h, y1, 8, a0=a, bottom=False))
    return o


@design("tree_palm", "tree", 18, 18)
def tree_palm():
    o, r = Out(), rng_for("tree_palm")
    segs, H = 8, 26
    rings = []
    for k in range(segs + 1):
        t = k / segs
        x = 3.2 * t ** 1.6
        rad = 1.05 - 0.4 * t
        rings.append(G.ring(x, 0, rad, 7, t * H))
    o.add("Trunk", G.loft(rings, top=True))
    top = v(3.2, H, 0)
    o.add("Trunk", G.blob(3.2, H - 0.8, 0, 1.3, 0, 0.1, r))
    fronds = []
    for k in range(9):
        a = 2 * math.pi * k / 9 + r.uniform(-0.15, 0.15)
        d = v(math.cos(a), 0, math.sin(a))
        side = v(-math.sin(a), 0, math.cos(a))
        L = r.uniform(10, 13)
        pts = []
        for s in range(6):
            t = s / 5
            p = top + d * (L * t) + v(0, 2.2 * math.sin(math.pi * t * 0.7) - 5.5 * t * t, 0)
            pts.append((p, 1.6 * math.sin(math.pi * min(1, t * 1.1 + 0.08))))
        for s in range(5):
            (p0, w0), (p1, w1) = pts[s], pts[s + 1]
            drop = v(0, -0.5, 0)
            for sg in (-1, 1):
                q = [p0, p1, p1 + side * sg * w1 + drop, p0 + side * sg * w0 + drop]
                fronds.append(q)
    o.add("Leaf", G.both(fronds))
    return o


@design("tree_cypress", "tree", 8, 8)
def tree_cypress():
    o, r = Out(), rng_for("tree_cypress")
    o.add("Trunk", G.frustum(0, 0, 0.7, 0.5, 0, 4, 6))
    o.add("Leaf", G.blob(0, 13, 0, 1, 2, 0.1, r, 3.4, 11, 3.4))
    return o


@design("tree_birch", "tree", 14, 14)
def tree_birch():
    o, r = Out(), rng_for("tree_birch")
    o.add("Trunk", G.frustum(0, 0, 0.8, 0.45, 0, 16, 6))
    o.add("Leaf", G.blob(0, 14, 0, 5.2, 1, 0.22, r, 1, 1.3, 1))
    o.add("Leaf", G.blob(2.2, 19, 0.8, 3.8, 1, 0.2, r, 1, 1.2, 1))
    o.add("Leaf", G.blob(-2, 11.5, -1.2, 3.4, 1, 0.2, r))
    return o


@design("tree_cherry", "tree", 20, 20)
def tree_cherry():
    o, r = Out(), rng_for("tree_cherry")
    o.add("Trunk", G.frustum(0, 0, 1.1, 0.8, 0, 5, 6))
    o.add("Trunk", G.rot_axis(G.frustum(0, 0, 0.7, 0.4, 4.5, 11, 5), (0, 0, 1), 0.55, (0, 4.5, 0)))
    o.add("Trunk", G.rot_axis(G.frustum(0, 0, 0.7, 0.4, 4.5, 11, 5), (0, 0, 1), -0.5, (0, 4.5, 0)))
    for (x, y, z, rad) in [(0, 11.5, 0, 5.4), (-4.6, 10.2, 1.5, 4.2), (4.8, 10.4, -1.2, 4.3), (1.5, 12, 4.2, 3.8), (-1, 11.6, -4.4, 3.8)]:
        o.add("Leaf", G.blob(x, y, z, rad, 1, 0.2, r, 1, 0.7, 1))
    return o


@design("tree_jungle", "tree", 24, 24)
def tree_jungle():
    o, r = Out(), rng_for("tree_jungle")
    o.add("Trunk", G.frustum(0, 0, 1.4, 0.8, 0, 24, 7))
    for k in range(4):
        a = k * math.pi / 2 + 0.3
        fin = [v(0, 0, 0), v(math.cos(a) * 4, 0, math.sin(a) * 4), v(0, 6, 0)]
        fin2 = [p + v(-math.sin(a), 0, math.cos(a)) * 0.35 for p in fin]
        fins_ = [fin, fin2[::-1], [fin[0], fin[1], fin2[1], fin2[0]], [fin[1], fin[2], fin2[2], fin2[1]]]
        o.add("Trunk", G.outward(fins_, v(math.cos(a) * 1.3, 2, math.sin(a) * 1.3) + v(-math.sin(a), 0, math.cos(a)) * 0.175))
    o.add("Leaf", G.blob(0, 25, 0, 9, 1, 0.2, r, 1, 0.42, 1))
    o.add("Leaf", G.blob(5, 21, -3, 5.6, 1, 0.2, r, 1, 0.5, 1))
    o.add("Leaf", G.blob(-4.6, 22.5, 3.4, 5.2, 1, 0.2, r, 1, 0.5, 1))
    return o


@design("tree_acacia", "tree", 22, 22)
def tree_acacia():
    o, r = Out(), rng_for("tree_acacia")
    o.add("Trunk", G.frustum(0, 0, 1.0, 0.7, 0, 7, 6))
    o.add("Trunk", G.rot_axis(G.frustum(0, 0, 0.6, 0.35, 6, 14, 5), (0, 0, 1), 0.5, (0, 6, 0)))
    o.add("Trunk", G.rot_axis(G.frustum(0, 0, 0.6, 0.35, 6, 14, 5), (0, 0, 1), -0.45, (0, 6, 0)))
    o.add("Leaf", G.blob(-3.5, 14.2, 0, 7, 1, 0.18, r, 1, 0.28, 0.9))
    o.add("Leaf", G.blob(4.2, 13.2, 1, 5.4, 1, 0.18, r, 1, 0.3, 1))
    return o


@design("bush", "tree", 9, 8)
def bush():
    o, r = Out(), rng_for("bush")
    o.add("Leaf", G.blob(0, 1.8, 0, 3.4, 1, 0.22, r, 1.1, 0.75, 1, flat_bottom=-0.5))
    o.add("Leaf", G.blob(2.8, 1.5, 1.2, 2.6, 1, 0.22, r, 1, 0.8, 1, flat_bottom=-0.4))
    o.add("Leaf", G.blob(-2.4, 1.3, -0.8, 2.2, 1, 0.22, r, 1, 0.8, 1, flat_bottom=-0.4))
    return o


# ---------------------------------------------------------------------------
# ROCKS AND MOUNTAINS
# ---------------------------------------------------------------------------
@design("rock_a", "rock", 14, 11)
def rock_a():
    o, r = Out(), rng_for("rock_a")
    o.add("Rock", G.blob(0, 2.2, 0, 5.4, 1, 0.3, r, 1.3, 0.75, 1, flat_bottom=-2.2))
    return o


@design("rock_b", "rock", 16, 14)
def rock_b():
    o, r = Out(), rng_for("rock_b")
    o.add("Rock", G.blob(0, 2.6, 0, 5, 1, 0.32, r, 1.1, 0.9, 1, flat_bottom=-2.6))
    o.add("Rock", G.blob(4.6, 1.5, 2.4, 3.2, 1, 0.3, r, 1, 0.8, 1, flat_bottom=-1.5))
    o.add("Rock", G.blob(-4, 1.2, -2.6, 2.6, 1, 0.3, r, 1, 0.8, 1, flat_bottom=-1.2))
    return o


@design("rock_spire", "rock", 16, 16)
def rock_spire():
    """Canyon hoodoo: a tall striped pillar with a cap."""
    o, r = Out(), rng_for("rock_spire")
    rings = []
    for k in range(8):
        y = k * 6
        rad = 6.5 - k * 0.45 + (0.8 if k % 2 else 0)
        rings.append([p + v(r.uniform(-0.4, 0.4), 0, r.uniform(-0.4, 0.4)) for p in G.ring(0, 0, rad, 7, y, 0.2 * k)])
    faces = G.loft(rings, top=False)
    for f in faces:
        c = G.centroid(f)
        o.add("Band" if int(c[1] // 6) % 2 else "Rock", [f])
    o.add("Rock", G.blob(0, 44, 0, 5.2, 1, 0.25, r, 1.2, 0.5, 1.2))
    return o


def _noise(rng, n=5):
    waves = [(rng.uniform(0.5, 3) * (k + 1), rng.uniform(0, 2 * math.pi), rng.uniform(0, 2 * math.pi), 1 / (k + 1)) for k in range(n)]

    def f(x, z):
        s = 0.0
        for fr, px, pz, amp in waves:
            s += amp * math.sin(x * fr + px) * math.cos(z * fr * 0.9 + pz)
        return s

    return f


def mountain(name, R, H, peaks, rng, snow=0.62, base=0.1, n=18, rough=0.18, mesa=False):
    o = Out()
    nz = _noise(rng)

    def fn(x, z):
        h = 0.0
        for (px, pz, pr, ph) in peaks:
            d = math.hypot(x - px * R, z - pz * R) / (pr * R)
            if d < 1:
                k = (1 - d) ** (1.25 if not mesa else 0.35)
                h = max(h, ph * k)
        edge = max(0.0, 1 - max(abs(x), abs(z)) / R)
        h *= min(1.0, edge * 6)
        if h <= 0:
            return 0.0
        if mesa:
            h = min(h, 0.82)
        return H * h * (1 + rough * nz(x / R * 3, z / R * 3))

    faces = G.heightfield(R, H, n, fn, rng)
    for f in faces:
        c = G.centroid(f)
        sl = G.slope_of(f)
        hk = c[1] / H
        if mesa:
            slot = "Base" if sl < 0.12 and hk > 0.6 else ("Band" if int(c[1] // (H * 0.09)) % 2 else "Rock")
        elif hk > snow and sl < 0.75:
            slot = "Snow"
        elif hk < base or (sl < 0.3 and hk < snow * 0.7):
            slot = "Base"
        else:
            slot = "Rock"
        o.add(slot, [f])
    return o


@design("mtn_peak", "mountain", 1200, 1200, smooth=True)
def mtn_peak():
    r = rng_for("mtn_peak")
    return mountain("mtn_peak", 600, 560, [(0, 0, 1.0, 1.0), (0.3, -0.2, 0.55, 0.62), (-0.35, 0.25, 0.5, 0.5)], r)


@design("mtn_ridge", "mountain", 1400, 900, smooth=True)
def mtn_ridge():
    r = rng_for("mtn_ridge")
    return mountain("mtn_ridge", 700, 480, [(-0.4, 0, 0.6, 0.9), (0.05, 0.05, 0.55, 1.0), (0.45, -0.05, 0.5, 0.8), (0, 0.3, 0.5, 0.5)], r, n=20)


@design("mtn_mesa", "mountain", 1000, 1000, smooth=False)
def mtn_mesa():
    r = rng_for("mtn_mesa")
    return mountain("mtn_mesa", 500, 260, [(0, 0, 0.95, 1.4), (0.35, 0.3, 0.45, 1.2)], r, n=16, rough=0.08, mesa=True)


@design("hill", "mountain", 900, 900, smooth=True)
def hill():
    r = rng_for("hill")
    return mountain("hill", 450, 150, [(0, 0, 1.0, 1.0), (0.3, 0.2, 0.6, 0.8)], r, snow=9, base=0.5, n=14, rough=0.1)


# ---------------------------------------------------------------------------
# ROAD VEHICLES (kind "vehicle"): nose at -z, wheels on the ground
# ---------------------------------------------------------------------------
def _side_profile(pts, width, slot, o):
    """Extrude a side profile [(z, y), ...] across x."""
    poly = [(z, y) for z, y in pts]
    faces = G.prism(poly, -width / 2, width / 2, top=True, bottom=True)
    # prism builds along y; remap (x=z_profile, y=width axis, z=y_profile) -> (x=width, y=profile y, z=profile z)
    faces = [[v(p[1], p[2], p[0]) for p in f] for f in faces]
    o.add(slot, faces)


def _wheels(o, x, zs, r=1.35, w=1.0):
    for z in zs:
        for sx in (-1, 1):
            o.add("Dark", G.tube_x(sx * x, r, z, r, w, 10))


@design("car_sedan", "vehicle", 7, 15)
def car_sedan():
    o = Out()
    _side_profile([(-7.4, 1.0), (-7.4, 2.9), (-6.6, 3.5), (-2.6, 3.8), (4.8, 3.8), (7.2, 3.5), (7.4, 2.8), (7.4, 1.0)], 6.2, "Body", o)
    _side_profile([(-2.4, 3.7), (-0.8, 5.5), (3.4, 5.5), (5.0, 3.7)], 5.6, "Glass", o)
    o.add("Body", G.box(0, 5.62, 1.3, 5.0, 0.25, 4.0))
    _wheels(o, 2.75, (-4.6, 4.6))
    o.add("Light", G.box(-2.2, 3.0, -7.45, 1.4, 0.6, 0.15) + G.box(2.2, 3.0, -7.45, 1.4, 0.6, 0.15))
    o.add("TailLight", G.box(-2.3, 3.1, 7.45, 1.4, 0.6, 0.15) + G.box(2.3, 3.1, 7.45, 1.4, 0.6, 0.15))
    return o


@design("car_suv", "vehicle", 7, 16)
def car_suv():
    o = Out()
    _side_profile([(-7.8, 1.2), (-7.8, 3.6), (-6.8, 4.4), (-3.6, 4.6), (7.8, 4.6), (7.8, 1.2)], 6.6, "Body", o)
    _side_profile([(-3.4, 4.5), (-1.8, 6.9), (7.2, 6.9), (7.6, 4.5)], 6.0, "Glass", o)
    o.add("Body", G.box(0, 7.05, 2.7, 6.2, 0.3, 9.6))
    _wheels(o, 3.0, (-5.0, 5.0), r=1.55, w=1.1)
    o.add("Light", G.box(-2.4, 3.7, -7.85, 1.5, 0.6, 0.15) + G.box(2.4, 3.7, -7.85, 1.5, 0.6, 0.15))
    o.add("TailLight", G.box(-2.6, 4.0, 7.85, 1.2, 1.2, 0.15) + G.box(2.6, 4.0, 7.85, 1.2, 1.2, 0.15))
    return o


@design("bus", "vehicle", 9, 36)
def bus():
    o = Out()
    o.add("Body", G.box(0, 5.6, 0, 8, 8.6, 34))
    o.add("Glass", G.box(0, 7.2, 1, 8.2, 3.2, 28) + G.box(0, 6.2, -17.05, 7, 5.4, 0.2))
    o.add("Accent", G.box(0, 3.6, 0, 8.15, 1.0, 33))
    _wheels(o, 3.6, (-11, 11), r=1.7, w=1.2)
    o.add("Light", G.box(-2.8, 2.6, -17.05, 1.4, 0.8, 0.15) + G.box(2.8, 2.6, -17.05, 1.4, 0.8, 0.15))
    o.add("TailLight", G.box(-3.2, 3, 17.05, 1, 1.6, 0.15) + G.box(3.2, 3, 17.05, 1, 1.6, 0.15))
    return o
