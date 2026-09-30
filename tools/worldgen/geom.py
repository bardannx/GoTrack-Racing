"""Tiny polygon toolkit for the world meshes (buildings, trees, rocks, mountains, road cars).

Coordinates are Roblox studs: x right, y up, z towards the back. A design sits on the
ground at the origin and its facade faces -z (towards the track). A face is a list of
numpy points; every helper returns faces already wound outwards (right-hand rule).
"""
import math

import numpy as np

UP = np.array((0.0, 1.0, 0.0))
DOWN = np.array((0.0, -1.0, 0.0))


def v(x, y, z):
    return np.array((x, y, z), dtype=float)


def normal(face):
    """Newell normal (not normalised)."""
    n = np.zeros(3)
    k = len(face)
    for i in range(k):
        a, b = face[i], face[(i + 1) % k]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return n


def centroid(face):
    return sum(face) / len(face)


def orient(face, want):
    """Wind a face so its normal points along `want`."""
    if float(np.dot(normal(face), want)) < 0:
        return face[::-1]
    return face


def outward(faces, centre):
    return [orient(f, centroid(f) - centre) for f in faces]


def both(faces):
    """Double-sided: every face plus its mirror (leaves, fronds, flags)."""
    return faces + [f[::-1] for f in faces]


# ---------------------------------------------------------------------------
# transforms
# ---------------------------------------------------------------------------
def move(faces, dx=0.0, dy=0.0, dz=0.0):
    d = v(dx, dy, dz)
    return [[p + d for p in f] for f in faces]


def rot_y(faces, ang, cx=0.0, cz=0.0):
    c, s = math.cos(ang), math.sin(ang)
    out = []
    for f in faces:
        nf = []
        for p in f:
            x, z = p[0] - cx, p[2] - cz
            nf.append(v(cx + x * c + z * s, p[1], cz - x * s + z * c))
        out.append(nf)
    return out


def rot_axis(faces, axis, ang, pivot=(0, 0, 0)):
    """Rotate about an arbitrary axis through pivot (Rodrigues)."""
    k = np.array(axis, dtype=float)
    k /= np.linalg.norm(k)
    piv = np.array(pivot, dtype=float)
    c, s = math.cos(ang), math.sin(ang)

    def r(p):
        q = p - piv
        return piv + q * c + np.cross(k, q) * s + k * np.dot(k, q) * (1 - c)

    return [[r(p) for p in f] for f in faces]


def scale(faces, sx, sy, sz, pivot=(0, 0, 0)):
    piv = np.array(pivot, dtype=float)
    s = v(sx, sy, sz)
    return [[piv + (p - piv) * s for p in f] for f in faces]


# ---------------------------------------------------------------------------
# solids
# ---------------------------------------------------------------------------
def box(cx, cy, cz, sx, sy, sz, skip=()):
    """Axis-aligned box. skip: faces to leave out ('px','nx','py','ny','pz','nz')."""
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    c = v(cx, cy, cz)

    def P(a, b, d):
        return c + v(a * hx, b * hy, d * hz)

    table = {
        "px": [P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1)],
        "nx": [P(-1, -1, -1), P(-1, 1, -1), P(-1, 1, 1), P(-1, -1, 1)],
        "py": [P(-1, 1, -1), P(1, 1, -1), P(1, 1, 1), P(-1, 1, 1)],
        "ny": [P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)],
        "pz": [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)],
        "nz": [P(-1, -1, -1), P(1, -1, -1), P(1, 1, -1), P(-1, 1, -1)],
    }
    return outward([f for k, f in table.items() if k not in skip], c)


def ybox(cx, cz, sx, sz, y0, y1, skip=("ny",)):
    """Box standing on y0 (no bottom by default)."""
    return box(cx, (y0 + y1) / 2, cz, sx, y1 - y0, sz, skip)


def _ccw(pts):
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    return pts if area > 0 else pts[::-1]


def prism(poly, y0, y1, top=True, bottom=False):
    """Extrude a 2D polygon [(x, z), ...] (may be concave) from y0 to y1."""
    pts = _ccw([np.array(p, dtype=float) for p in poly])
    n = len(pts)
    faces = []
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        out = v(q[1] - p[1], 0, -(q[0] - p[0]))
        faces.append(orient([v(p[0], y0, p[1]), v(q[0], y0, q[1]), v(q[0], y1, q[1]), v(p[0], y1, p[1])], out))
    if top:
        faces.append(orient([v(p[0], y1, p[1]) for p in pts], UP))
    if bottom:
        faces.append(orient([v(p[0], y0, p[1]) for p in pts], DOWN))
    return faces


def ring(cx, cz, r, n, y, a0=0.0, sx=1.0, sz=1.0):
    return [v(cx + math.cos(a0 + 2 * math.pi * k / n) * r * sx, y, cz + math.sin(a0 + 2 * math.pi * k / n) * r * sz) for k in range(n)]


def loft(rings, top=True, bottom=False, axis=None):
    """Skin a stack of rings (same point count, bottom to top). Sides face away from each
    ring's centre (or from `axis` points)."""
    faces = []
    n = len(rings[0])
    for j in range(len(rings) - 1):
        A, B = rings[j], rings[j + 1]
        ca, cb = centroid(A), centroid(B)
        for k in range(n):
            a0, a1, b1, b0 = A[k], A[(k + 1) % n], B[(k + 1) % n], B[k]
            quad = [a0, a1, b1, b0]
            mid = centroid(quad)
            ax = (ca + cb) / 2
            want = mid - ax
            want[1] = 0 if abs(want[0]) + abs(want[2]) > 1e-6 else want[1]
            if np.linalg.norm(b1 - b0) < 1e-6:
                quad = [a0, a1, b0]
            elif np.linalg.norm(a1 - a0) < 1e-6:
                quad = [a0, b1, b0]
            faces.append(orient(quad, want))
    if top and np.linalg.norm(rings[-1][0] - rings[-1][1]) > 1e-6:
        faces.append(orient(list(rings[-1]), UP))
    if bottom:
        faces.append(orient(list(rings[0]), DOWN))
    return faces


def frustum(cx, cz, r0, r1, y0, y1, n=12, a0=0.0, top=True, bottom=False, sx=1.0, sz=1.0):
    if r1 <= 1e-6:
        return cone(cx, cz, r0, y0, y1, n, a0, bottom, sx, sz)
    return loft([ring(cx, cz, r0, n, y0, a0, sx, sz), ring(cx, cz, r1, n, y1, a0, sx, sz)], top, bottom)


def cone(cx, cz, r, y0, y1, n=12, a0=0.0, bottom=True, sx=1.0, sz=1.0):
    base = ring(cx, cz, r, n, y0, a0, sx, sz)
    apex = v(cx, y1, cz)
    faces = []
    for k in range(n):
        tri = [base[k], base[(k + 1) % n], apex]
        mid = centroid(tri)
        faces.append(orient(tri, v(mid[0] - cx, 0.2, mid[2] - cz)))
    if bottom:
        faces.append(orient(base, DOWN))
    return faces


def tube_x(cx, cy, cz, r, length, n=10):
    """Cylinder along X (wheels, water tanks on their side)."""
    faces = frustum(0, 0, r, r, -length / 2, length / 2, n, top=True, bottom=True)
    faces = [[v(p[1], p[0], p[2]) for p in f] for f in faces]  # y-axis -> x-axis (mirrors winding)
    faces = [f[::-1] for f in faces]
    return move(faces, cx, cy, cz)


def gable(cx, cz, w, d, y0, h, over=0.0, ridge_x=True):
    """Solid triangular roof, ridge along X (or Z). Returns (slopes, ends)."""
    if not ridge_x:
        s, e = gable(0, 0, d, w, y0, h, over, True)
        return move(rot_y(s, math.pi / 2), cx, 0, cz), move(rot_y(e, math.pi / 2), cx, 0, cz)
    hw, hd = w / 2 + over, d / 2 + over
    L0, L1 = v(cx - hw, y0, cz - hd), v(cx + hw, y0, cz - hd)
    R0, R1 = v(cx - hw, y0, cz + hd), v(cx + hw, y0, cz + hd)
    T0, T1 = v(cx - hw, y0 + h, cz), v(cx + hw, y0 + h, cz)
    slopes = [orient([L0, L1, T1, T0], v(0, 1, -1)), orient([R0, R1, T1, T0], v(0, 1, 1)), orient([L0, L1, R1, R0], DOWN)]
    ends = [orient([L0, R0, T0], v(-1, 0, 0)), orient([L1, R1, T1], v(1, 0, 0))]
    return slopes, ends


def hip(cx, cz, w, d, y0, h, over=0.0):
    """Hip roof: ridge along the longer side."""
    hw, hd = w / 2 + over, d / 2 + over
    c = [v(cx - hw, y0, cz - hd), v(cx + hw, y0, cz - hd), v(cx + hw, y0, cz + hd), v(cx - hw, y0, cz + hd)]
    if hw >= hd:
        r = hw - hd
        t0, t1 = v(cx - r, y0 + h, cz), v(cx + r, y0 + h, cz)
        faces = [[c[0], c[1], t1, t0], [c[1], c[2], t1], [c[2], c[3], t0, t1], [c[3], c[0], t0]]
    else:
        r = hd - hw
        t0, t1 = v(cx, y0 + h, cz - r), v(cx, y0 + h, cz + r)
        faces = [[c[0], c[1], t0], [c[1], c[2], t1, t0], [c[2], c[3], t1], [c[3], c[0], t0, t1]]
    centre = v(cx, y0, cz)
    out = []
    for f in faces:
        if len(f) == 4 and np.linalg.norm(f[2] - f[3]) < 1e-6:
            f = f[:3]
        out.append(orient(f, centroid(f) - centre + v(0, 0.01, 0)))
    out.append(orient(c, DOWN))
    return out


# ---------------------------------------------------------------------------
# organic shapes
# ---------------------------------------------------------------------------
_ICO = None


def _icosahedron():
    t = (1 + 5 ** 0.5) / 2
    vs = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    fs = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    return [np.array(p, dtype=float) / np.linalg.norm(p) for p in vs], fs


def sphere_mesh(sub):
    vs, fs = _icosahedron()
    vs = list(vs)
    for _ in range(sub):
        cache = {}

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                m = vs[a] + vs[b]
                vs.append(m / np.linalg.norm(m))
                cache[key] = len(vs) - 1
            return cache[key]

        nf = []
        for a, b, c in fs:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        fs = nf
    return vs, fs


def blob(cx, cy, cz, r, sub=1, jitter=0.18, rng=None, sx=1.0, sy=1.0, sz=1.0, flat_bottom=None):
    """Low-poly lumpy sphere (tree crowns, bushes, rocks)."""
    vs, fs = sphere_mesh(sub)
    rng = rng or np.random.default_rng(1)
    k = 1 + jitter * (rng.random(len(vs)) * 2 - 1)
    pts = []
    for i, p in enumerate(vs):
        q = p * r * k[i] * v(sx, sy, sz)
        if flat_bottom is not None and q[1] < flat_bottom:
            q = v(q[0], flat_bottom, q[2])
        pts.append(q + v(cx, cy, cz))
    c = v(cx, cy, cz)
    faces = []
    for a, b, cc in fs:
        f = [pts[a], pts[b], pts[cc]]
        if np.linalg.norm(normal(f)) < 1e-9:
            continue
        faces.append(orient(f, centroid(f) - c))
    return faces


def heightfield(R, H, n, fn, rng):
    """Square grid of (2n x 2n) cells over [-R, R]^2 with heights fn(x, z) (edge -> 0).
    Returns faces (triangles, upward) with their centroid height and slope."""
    xs = np.linspace(-R, R, 2 * n + 1)
    h = np.zeros((2 * n + 1, 2 * n + 1))
    for i, x in enumerate(xs):
        for j, z in enumerate(xs):
            h[i, j] = max(0.0, fn(x, z))
    faces = []
    for i in range(2 * n):
        for j in range(2 * n):
            p00 = v(xs[i], h[i, j], xs[j])
            p10 = v(xs[i + 1], h[i + 1, j], xs[j])
            p01 = v(xs[i], h[i, j + 1], xs[j + 1])
            p11 = v(xs[i + 1], h[i + 1, j + 1], xs[j + 1])
            if max(p00[1], p10[1], p01[1], p11[1]) <= 0.01:
                continue
            for tri in ([p00, p10, p11], [p00, p11, p01]) if (i + j) % 2 == 0 else ([p00, p10, p01], [p10, p11, p01]):
                faces.append(orient(tri, UP))
    return faces


def slope_of(face):
    n = normal(face)
    ln = np.linalg.norm(n)
    return 0.0 if ln < 1e-9 else 1.0 - abs(n[1]) / ln


# ---------------------------------------------------------------------------
# facade helpers
# ---------------------------------------------------------------------------
def pane(centre, udir, n, w, h):
    """A flat window quad centred on `centre`, facing n."""
    u = np.array(udir, dtype=float) * (w / 2)
    up = v(0, h / 2, 0)
    q = [centre - u - up, centre + u - up, centre + u + up, centre - u + up]
    return orient(q, np.array(n, dtype=float))


def wall_panes(p0, p1, n, y0, y1, floor_h, col_w, pw, ph, off, rng, lit_split=0.5, skip_floors=0, margin=0.0):
    """Window panes on the straight wall from p0 to p1 (x, z) between heights y0..y1.
    Returns (A, B): two random interleaved sets, so at night one set can be lit."""
    p0 = np.array(p0, dtype=float)
    p1 = np.array(p1, dtype=float)
    L = float(np.linalg.norm(p1 - p0))
    if L < 1e-6:
        return [], []
    d2 = (p1 - p0) / L
    udir = v(d2[0], 0, d2[1])
    nn = np.array(n, dtype=float)
    nn = nn / np.linalg.norm(nn)
    cols = max(1, int((L - 2 * margin) // col_w))
    step = (L - 2 * margin) / cols
    floors = int((y1 - y0) // floor_h)
    A, B = [], []
    for f in range(skip_floors, floors):
        y = y0 + (f + 0.5) * floor_h
        for c in range(cols):
            t = margin + (c + 0.5) * step
            base = v(p0[0] + d2[0] * t, y, p0[1] + d2[1] * t) + nn * off
            q = pane(base, udir, nn, min(pw, step * 0.92), ph)
            (A if rng.random() < lit_split else B).append(q)
    return A, B


def box_panes(cx, cz, w, d, y0, y1, floor_h, col_w, pw, ph, off, rng, ang=0.0, skip_floors=0, margin=0.0, sides=(0, 1, 2, 3)):
    """Panes on the four walls of a w x d box (optionally rotated by ang about its centre)."""
    A, B = [], []
    hw, hd = w / 2, d / 2
    walls = [
        ((-hw, -hd), (hw, -hd), (0, 0, -1)),  # front (-z)
        ((hw, -hd), (hw, hd), (1, 0, 0)),
        ((hw, hd), (-hw, hd), (0, 0, 1)),  # back
        ((-hw, hd), (-hw, -hd), (-1, 0, 0)),
    ]
    for k in sides:
        p0, p1, n = walls[k]
        a, b = wall_panes(p0, p1, n, y0, y1, floor_h, col_w, pw, ph, off, rng, skip_floors=skip_floors, margin=margin)
        A += a
        B += b
    if ang:
        A, B = rot_y(A, ang), rot_y(B, ang)
    return move(A, cx, 0, cz), move(B, cx, 0, cz)


def ring_panes(cx, cz, r, n, y0, y1, floor_h, ph, off, rng, a0=0.0, fill=0.8, skip_floors=0):
    """One pane per facet per floor on an n-sided prism of radius r."""
    A, B = [], []
    pts = ring(cx, cz, r, n, 0, a0)
    floors = int((y1 - y0) // floor_h)
    for k in range(n):
        p, q = pts[k], pts[(k + 1) % n]
        mid = (p + q) / 2
        u = q - p
        L = float(np.linalg.norm(u))
        u = u / L
        nn = v(mid[0] - cx, 0, mid[2] - cz)
        nn = nn / np.linalg.norm(nn)
        for f in range(skip_floors, floors):
            c = v(mid[0], y0 + (f + 0.5) * floor_h, mid[2]) + nn * off
            (A if rng.random() < 0.5 else B).append(pane(c, u, nn, L * fill, ph))
    return A, B
