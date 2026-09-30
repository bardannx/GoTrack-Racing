"""Geometry toolkit for the GoTrack car generator.

Everything is authored as polygon soups (lists of Nx3 numpy arrays) in "car metres":
x = lateral (right +), y = up (ground 0), z = longitudinal (rear +, front axle 0).
Objects are collected in an Out() and later converted to studs + exported by Blender.
"""

import math
import numpy as np
import mapbox_earcut as earcut

TAU = math.pi * 2


# ---------------------------------------------------------------------------
# interpolation of keyframed parameters
# ---------------------------------------------------------------------------
class Track:
    """Keyframed parameter set: Track({'cy': [(z,v),...], ...}, linear={'dip'})"""

    def __init__(self, keys, linear=()):
        from scipy.interpolate import PchipInterpolator

        self.f = {}
        for name, ks in keys.items():
            zs = np.array([k[0] for k in ks], float)
            vs = np.array([k[1] for k in ks], float)
            if name in linear or len(ks) < 3:
                self.f[name] = (lambda zs, vs: lambda z: float(np.interp(z, zs, vs)))(zs, vs)
            else:
                p = PchipInterpolator(zs, vs, extrapolate=False)
                lo, hi = vs[0], vs[-1]
                z0, z1 = zs[0], zs[-1]
                self.f[name] = (lambda p, lo, hi, z0, z1: lambda z: float(lo if z <= z0 else hi if z >= z1 else p(z)))(
                    p, lo, hi, z0, z1
                )

    def __call__(self, z):
        return {k: f(z) for k, f in self.f.items()}


def smoothstep(e0, e1, x):
    """Smooth 0 -> 1 ramp between e0 and e1 (eases in and out)."""
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0))) if e1 != e0 else (1.0 if x >= e1 else 0.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------
# cross sections
# ---------------------------------------------------------------------------
def superellipse_section(z, p, N=56):
    """Closed ring, first point = top centre, going towards +x.
    p: cx, cy, wt (top half width), wb (bottom half width), ht, hb (heights above/below cy),
       n (exponent), optional dip (depth), dipw (half width of the dip), tilt."""
    cx, cy = p.get("cx", 0.0), p["cy"]
    wt, wb, ht, hb = p["wt"], p["wb"], p["ht"], p["hb"]
    n = p.get("n", 2.5)
    nb = p.get("nb", n)
    dip, dipw = p.get("dip", 0.0), p.get("dipw", 0.0)
    pts = []
    for i in range(N):
        t = TAU * i / N
        s, c = math.sin(t), math.cos(t)
        blend = 0.5 + 0.5 * c
        w = wb + (wt - wb) * blend
        nn = nb + (n - nb) * blend
        h = ht if c >= 0 else hb
        x = w * math.copysign(abs(s) ** (2 / nn), s)
        y = h * math.copysign(abs(c) ** (2 / nn), c)
        if dip > 0 and c > 0 and dipw > 0 and abs(x) < dipw:
            k = 1 - (abs(x) / dipw) ** 4
            y -= dip * k
        pts.append((cx + x, cy + y, z))
    return np.array(pts)


def airfoil(chord, thick=0.1, camber=0.04, N=16):
    """Returns list of (u, v) around the aerofoil, u along chord 0..1 (LE->TE), v up."""
    pts = []
    half = N // 2
    for i in range(half + 1):  # upper surface TE->LE
        b = math.pi * i / half
        u = 0.5 + 0.5 * math.cos(b)
        pts.append(u)
    upper = []
    lower = []
    for u in pts:
        yt = 5 * thick * (0.2969 * math.sqrt(max(u, 0)) - 0.126 * u - 0.3516 * u**2 + 0.2843 * u**3 - 0.1036 * u**4)
        yc = camber * 4 * u * (1 - u)
        upper.append((u, yc + yt))
        lower.append((u, yc - yt))
    ring = upper + lower[::-1][1:-1]
    return ring


# ---------------------------------------------------------------------------
# polygon soups
# ---------------------------------------------------------------------------
def signed_volume(polys):
    v = 0.0
    for p in polys:
        p0 = p[0]
        for k in range(1, len(p) - 1):
            v += np.dot(p0, np.cross(p[k], p[k + 1]))
    return v / 6.0


def orient_closed(polys):
    """Flips a closed shape's faces if they point inwards."""
    if signed_volume(polys) < 0:
        return [p[::-1] for p in polys]
    return polys


def loft(rings, cap0=True, cap1=True, cap0_zone=None, cap1_zone=None):
    """rings: list of (N,3). Returns (side polys, {zone: cap polys}). Always outward facing."""
    R = [np.asarray(r, float) for r in rings]
    M = len(R)
    N = len(R[0])
    sides = []
    for i in range(M - 1):
        a, b = R[i], R[i + 1]
        for j in range(N):
            j2 = (j + 1) % N
            sides.append(np.array([a[j], b[j], b[j2], a[j2]]))
    c0 = R[0].mean(axis=0)
    c1 = R[-1].mean(axis=0)
    capA = [np.array([c0, R[0][j], R[0][(j + 1) % N]]) for j in range(N)]
    capB = [np.array([c1, R[-1][(j + 1) % N], R[-1][j]]) for j in range(N)]
    if signed_volume(sides + capA + capB) < 0:
        sides = [p[::-1] for p in sides]
        capA = [p[::-1] for p in capA]
        capB = [p[::-1] for p in capB]
    caps = {}
    if cap0:
        caps.setdefault(cap0_zone, []).extend(capA)
    if cap1:
        caps.setdefault(cap1_zone, []).extend(capB)
    return sides, caps


def grid_normals(rings):
    """Per-vertex normals of a grid of rings (a lofted surface)."""
    R = np.array(rings, float)  # M,N,3
    M, N, _ = R.shape
    nrm = np.zeros_like(R)
    for i in range(M):
        i0, i1 = max(0, i - 1), min(M - 1, i + 1)
        for j in range(N):
            ta = R[i, (j + 1) % N] - R[i, (j - 1) % N]
            tb = R[i1, j] - R[i0, j]
            n = np.cross(tb, ta)
            L = np.linalg.norm(n)
            nrm[i, j] = n / L if L > 1e-9 else (0, 1, 0)
    return nrm


def offset_rings(rings, d):
    """Rings pushed out along their normals by d (a shell just above a surface)."""
    n = grid_normals(rings)
    R = np.array(rings, float)
    cent = R.mean(axis=1, keepdims=True)
    if np.sum(n * (R - cent)) < 0:
        n = -n
    return [np.asarray(r) + n[i] * d for i, r in enumerate(rings)]


def tube(path, radius, N=10, cap=True, flat=1.0):
    """Tube along a polyline. radius may be a float or callable(t 0..1). flat squashes one axis."""
    P = [np.asarray(p, float) for p in path]
    rings = []
    # parallel transport frame
    t0 = P[1] - P[0]
    t0 /= np.linalg.norm(t0)
    up = np.array([0, 1.0, 0]) if abs(t0[1]) < 0.9 else np.array([1.0, 0, 0])
    nrm = np.cross(t0, up)
    nrm /= np.linalg.norm(nrm)
    for k, p in enumerate(P):
        if k == 0:
            t = P[1] - P[0]
        elif k == len(P) - 1:
            t = P[-1] - P[-2]
        else:
            t = P[k + 1] - P[k - 1]
        t /= np.linalg.norm(t)
        nrm = nrm - t * np.dot(nrm, t)
        nrm /= np.linalg.norm(nrm)
        bi = np.cross(t, nrm)
        r = radius(k / (len(P) - 1)) if callable(radius) else radius
        ring = [p + (nrm * math.cos(TAU * j / N) * flat + bi * math.sin(TAU * j / N)) * r for j in range(N)]
        rings.append(np.array(ring))
    polys, caps = loft(rings, cap, cap)
    out = list(polys)
    for v in caps.values():
        out.extend(v)
    return out


def bezier(pts, n=16):
    """n+1 points along a Bezier curve through the control points."""
    P = [np.asarray(p, float) for p in pts]
    out = []
    for i in range(n + 1):
        t = i / n
        Q = list(P)
        while len(Q) > 1:
            Q = [Q[k] * (1 - t) + Q[k + 1] * t for k in range(len(Q) - 1)]
        out.append(Q[0])
    return out


def plate(poly2d, plane, offset, thick, round_steps=0):
    """Extrude a 2D polygon. plane 'zy' -> polygon coords (z, y), extruded along x from offset-thick/2..+thick/2.
    plane 'xz' -> (x, z) extruded along y; plane 'xy' -> (x, y) extruded along z."""
    P = np.asarray(poly2d, float)
    # ensure CCW
    area = 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])
    if area < 0:
        P = P[::-1]
    tri = earcut.triangulate_float64(P.reshape(-1, 2), np.array([len(P)], dtype=np.uint32)).reshape(-1, 3)

    def to3(a, b, w):
        if plane == "zy":
            return np.array([w, b, a])
        if plane == "xz":
            return np.array([a, w, b])
        return np.array([a, b, w])  # xy

    lo, hi = offset - thick / 2, offset + thick / 2
    polys = []
    for t in tri:
        polys.append(np.array([to3(*P[t[0]], hi), to3(*P[t[1]], hi), to3(*P[t[2]], hi)]))
        polys.append(np.array([to3(*P[t[2]], lo), to3(*P[t[1]], lo), to3(*P[t[0]], lo)]))
    n = len(P)
    for i in range(n):
        a, b = P[i], P[(i + 1) % n]
        polys.append(np.array([to3(*a, lo), to3(*b, lo), to3(*b, hi), to3(*a, hi)]))
    # fix winding for planes where the extrusion axis flips handedness
    return orient_closed(polys)


def rounded_rect(x0, y0, x1, y1, r, steps=4):
    """Outline of a rectangle with rounded corners of radius r."""
    pts = []
    corners = [(x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180), (x1 - r, y0 + r, 270)]
    for cx, cy, a0 in corners:
        for k in range(steps + 1):
            a = math.radians(a0 + 90 * k / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def revolve(profile, N=48, axis="x", center=(0, 0, 0), a0=0.0, a1=TAU, closed=True, orient=True, flip=False):
    """profile: list of (axial, radius). Revolves around the given axis. Returns polys."""
    cx, cy, cz = center
    for k in range(len(profile)):
        pass
    # build grid: one ring per profile point (around the axis)
    grid = []
    for ax, r in profile:
        ring = []
        for j in range(N):
            a = a0 + (a1 - a0) * j / (N if closed else N - 1)
            if axis == "x":
                ring.append((cx + ax, cy + r * math.cos(a), cz + r * math.sin(a)))
            elif axis == "y":
                ring.append((cx + r * math.cos(a), cy + ax, cz + r * math.sin(a)))
            else:
                ring.append((cx + r * math.cos(a), cy + r * math.sin(a), cz + ax))
        grid.append(np.array(ring))
    polys = []
    for i in range(len(grid) - 1):
        a, b = grid[i], grid[i + 1]
        rng = range(N) if closed else range(N - 1)
        for j in rng:
            j2 = (j + 1) % N
            polys.append(np.array([a[j], b[j], b[j2], a[j2]]))
    if orient:
        polys = orient_closed(polys)
    elif flip:
        polys = [p[::-1] for p in polys]
    return polys


def ellipsoid(center, radii, N=24, M=14):
    """A closed ellipsoid mesh."""
    cx, cy, cz = center
    rx, ry, rz = radii
    rings = []
    for i in range(1, M):
        phi = math.pi * i / M
        ring = []
        for j in range(N):
            th = TAU * j / N
            ring.append(
                (
                    cx + rx * math.sin(phi) * math.cos(th),
                    cy + ry * math.cos(phi),
                    cz + rz * math.sin(phi) * math.sin(th),
                )
            )
        rings.append(np.array(ring))
    polys, caps = loft(rings, False, False)
    top = np.array([cx, cy + ry, cz])
    bot = np.array([cx, cy - ry, cz])
    R0, R1 = rings[0], rings[-1]
    for j in range(N):
        j2 = (j + 1) % N
        polys.append(np.array([top, R0[j2], R0[j]]))
        polys.append(np.array([bot, R1[j], R1[j2]]))
    return orient_closed(polys)


def box(c, s):
    """A closed box: centre c, size s."""
    cx, cy, cz = c
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    v = [np.array([cx + dx * hx, cy + dy * hy, cz + dz * hz]) for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)]

    def V(dx, dy, dz):
        return v[((dx + 1) // 2) * 4 + ((dy + 1) // 2) * 2 + (dz + 1) // 2]

    faces = [
        [V(1, -1, -1), V(1, 1, -1), V(1, 1, 1), V(1, -1, 1)],
        [V(-1, -1, 1), V(-1, 1, 1), V(-1, 1, -1), V(-1, -1, -1)],
        [V(-1, 1, -1), V(-1, 1, 1), V(1, 1, 1), V(1, 1, -1)],
        [V(-1, -1, 1), V(-1, -1, -1), V(1, -1, -1), V(1, -1, 1)],
        [V(-1, -1, 1), V(1, -1, 1), V(1, 1, 1), V(-1, 1, 1)],
        [V(1, -1, -1), V(-1, -1, -1), V(-1, 1, -1), V(1, 1, -1)],
    ]
    return orient_closed([np.array(f) for f in faces])


def mirror_x(polys):
    """Mirrors polygons across x = 0 (right side -> left side), keeping them facing out."""
    out = []
    for p in polys:
        q = np.array(p, float).copy()
        q[:, 0] *= -1
        out.append(q[::-1])
    return out


def transform(polys, fn):
    """Applies fn to every vertex."""
    return [np.array([fn(v) for v in p]) for p in polys]


# ---------------------------------------------------------------------------
# exact region clipping (for colour zones and livery overlays)
# A region = list of convex pieces; a piece = list of half-spaces (a(3), b): a.p + b >= 0
# ---------------------------------------------------------------------------
def H(a, b):
    return (np.asarray(a, float), float(b))


def hs_x_ge(v):
    """Half-space x >= v."""
    return H((1, 0, 0), -v)


def hs_x_le(v):
    """Half-space x <= v."""
    return H((-1, 0, 0), v)


def hs_y_ge(v):
    """Half-space y >= v."""
    return H((0, 1, 0), -v)


def hs_y_le(v):
    """Half-space y <= v."""
    return H((0, -1, 0), v)


def hs_z_ge(v):
    """Half-space z >= v."""
    return H((0, 0, 1), -v)


def hs_z_le(v):
    """Half-space z <= v."""
    return H((0, 0, -1), v)


def hs_line2d(axes, p0, p1):
    """Half-plane to the LEFT of p0->p1 in the given 2D axes ('zy', 'xz', 'zx', ...)."""
    ia = "xyz".index(axes[0])
    ib = "xyz".index(axes[1])
    d = (p1[0] - p0[0], p1[1] - p0[1])
    n2 = (-d[1], d[0])  # left normal
    a = [0.0, 0.0, 0.0]
    a[ia] = n2[0]
    a[ib] = n2[1]
    b = -(n2[0] * p0[0] + n2[1] * p0[1])
    return H(a, b)


def poly_region(axes, poly, extra=()):
    """Triangulate a simple 2D polygon into convex pieces (+ extra half-spaces for each piece)."""
    P = np.asarray(poly, float)
    area = 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])
    if area < 0:
        P = P[::-1]
    tri = earcut.triangulate_float64(P.reshape(-1, 2), np.array([len(P)], dtype=np.uint32)).reshape(-1, 3)
    pieces = []
    for t in tri:
        a, b, c = P[t[0]], P[t[1]], P[t[2]]
        # ensure CCW
        cr = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if cr < 0:
            b, c = c, b
        pieces.append([hs_line2d(axes, a, b), hs_line2d(axes, b, c), hs_line2d(axes, c, a)] + list(extra))
    return pieces


def _clip(poly, h):
    """Clips one convex polygon to a half-space."""
    a, b = h
    P = poly
    d = P @ a + b
    if np.all(d >= -1e-12):
        return P, None
    if np.all(d <= 1e-12):
        return None, P
    inside, outside = [], []
    n = len(P)
    for i in range(n):
        p, q = P[i], P[(i + 1) % n]
        dp, dq = d[i], d[(i + 1) % n]
        if dp >= 0:
            inside.append(p)
        if dp <= 0:
            outside.append(p)
        if (dp > 0 and dq < 0) or (dp < 0 and dq > 0):
            # canonical order so shared edges split identically
            if tuple(p) < tuple(q):
                t = dp / (dp - dq)
                x = p + (q - p) * t
            else:
                t = dq / (dq - dp)
                x = q + (p - q) * t
            inside.append(x)
            outside.append(x)
    ins = np.array(inside) if len(inside) >= 3 else None
    outs = np.array(outside) if len(outside) >= 3 else None
    return ins, outs


def split(polys, region):
    """Returns (inside, outside) polygon lists."""
    inside = []
    rest = list(polys)
    for piece in region:
        new_rest = []
        for p in rest:
            cur = p
            for h in piece:
                cin, cout = _clip(cur, h)
                if cout is not None:
                    new_rest.append(cout)
                cur = cin
                if cur is None:
                    break
            if cur is not None:
                inside.append(cur)
        rest = new_rest
    return inside, rest


def keep(polys, region):
    """The parts of polys inside the region."""
    return split(polys, region)[0]


# ---------------------------------------------------------------------------
# output collection
# ---------------------------------------------------------------------------
class Out:
    def __init__(self):
        self.objs = {}  # name -> list of polys
        self.meta = {}  # name -> dict (units etc.)

    def add(self, name, polys, studs=False):
        if not polys:
            return
        self.objs.setdefault(name, []).extend([np.asarray(p, float) for p in polys])
        self.meta.setdefault(name, {"studs": studs})

    def names(self, prefix):
        return [n for n in self.objs if n.startswith(prefix)]


def facet_section(z, p, N=None):
    """Chiselled 10-point section (stealth look). Uses cx, cy, wt, wb, ht, hb (+ optional wm = mid width)."""
    cx, cy = p.get("cx", 0.0), p["cy"]
    wt, wb, ht, hb = p["wt"], p["wb"], p["ht"], p["hb"]
    wm = p.get("wm", max(wt, wb) * 1.12)
    pts = [(0.0, ht), (wt, ht), (wm, ht * 0.25), (wm, -hb * 0.35), (wb, -hb), (0.0, -hb * 1.02)]
    ring = pts + [(-x, y) for x, y in reversed(pts[1:-1])]
    return np.array([(cx + x, cy + y, z) for x, y in ring])
