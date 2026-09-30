"""Reusable F1 car parts (car metres; see geo.py for axes)."""

import math
import numpy as np
import geo
from geo import superellipse_section, loft

DELTA = 0.010  # livery overlay offset (m)


def zsamples(z0, z1, step, dense=()):
    """Stations along the car from z0 to z1 every `step`, with denser spacing inside
    each (a, b, step) range in `dense`.
    """
    zs = list(np.arange(z0, z1, step)) + [z1]
    for a, b, st in dense:
        zs += list(np.arange(a, b, st))
    zs = sorted(set(round(z, 4) for z in zs if z0 <= z <= z1))
    return zs


def body_rings(track, zs, N):
    """Cross-section rings along the car from a shape function `track(z)`."""
    return [superellipse_section(z, track(z), N) for z in zs]


def loft_obj(rings, cap0=True, cap1=True, cap0_zone="", cap1_zone=""):
    """Lofts rings into (sides, caps)."""
    sides, caps = loft(rings, cap0, cap1, cap0_zone, cap1_zone)
    return sides, caps


def overlay_from_rings(rings, region, exclude=None, d=DELTA):
    """Livery overlay: the loft surface pushed out by d, clipped to region (minus exclude)."""
    off = geo.offset_rings(rings, d)
    sides, _ = loft(off, False, False)
    polys = geo.keep(sides, region)
    if exclude:
        polys = geo.split(polys, exclude)[1]
    return polys


# ---------------------------------------------------------------------------
# region helpers
# ---------------------------------------------------------------------------
def box_region(x0=None, x1=None, y0=None, y1=None, z0=None, z1=None):
    """A box-shaped region from any of its six bounds (left out = unbounded)."""
    hs = []
    if x0 is not None:
        hs.append(geo.hs_x_ge(x0))
    if x1 is not None:
        hs.append(geo.hs_x_le(x1))
    if y0 is not None:
        hs.append(geo.hs_y_ge(y0))
    if y1 is not None:
        hs.append(geo.hs_y_le(y1))
    if z0 is not None:
        hs.append(geo.hs_z_ge(z0))
    if z1 is not None:
        hs.append(geo.hs_z_le(z1))
    return [hs]


def above_curve_region(curve_zy, ytop=3.0, extra=()):
    """Region above a polyline y(z) given as [(z, y), ...] (in the zy plane)."""
    pts = list(curve_zy) + [(curve_zy[-1][0], ytop), (curve_zy[0][0], ytop)]
    return geo.poly_region("zy", pts, extra)


def with_extra(region, extra):
    """A region with extra half-spaces added to every piece."""
    return [piece + list(extra) for piece in region]


# ---------------------------------------------------------------------------
# aero surfaces
# ---------------------------------------------------------------------------
def wing_element(x0, x1, fn, stations=28, M=18, thick=0.09, camber=0.05, cap=True):
    """Aerofoil lofted along x. fn(x) -> dict(y, z (leading edge), c (chord), a (deg, nose-down +)).
    Station spacing is clustered toward the ends."""
    xs = [x0 + (x1 - x0) * (0.5 - 0.5 * math.cos(math.pi * i / (stations - 1))) for i in range(stations)]
    ring2d = geo.airfoil(1.0, thick, camber, M)
    rings = []
    for x in xs:
        p = fn(x)
        a = math.radians(p["a"])
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for u, v in ring2d:
            # chord along +z (rearward), aoa rotates trailing edge upward (nose-down pitch)
            du, dv = u * p["c"], v * p["c"]
            yy = p["y"] + dv * ca + du * sa
            zz = p["z"] + du * ca - dv * sa
            ring.append((x, yy, zz))
        rings.append(np.array(ring))
    sides, caps = loft(rings, cap, cap)
    out = list(sides)
    for v in caps.values():
        out += v
    return out


def endplate(poly_zy, x, thick=0.012):
    """A flat wing endplate from its side outline, at lateral position x."""
    return geo.plate(poly_zy, "zy", x, thick)


def arc_pts(cz, cy, r, a0, a1, n=8):
    """Points on a circular arc in the side view (angles in degrees)."""
    return [
        (
            cz + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
            cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / n)),
        )
        for k in range(n + 1)
    ]


# ---------------------------------------------------------------------------
# mechanical bits
# ---------------------------------------------------------------------------
def rod(a, b, r=0.014, flat=0.45, N=8):
    return geo.tube([a, b], r, N=N, flat=flat)


def wishbone(inner_a, inner_b, outer, r=0.013):
    """A suspension wishbone: two rods from the chassis meeting at the wheel."""
    return rod(inner_a, outer, r) + rod(inner_b, outer, r)


def drum(center, r, x0, x1, N=20):
    """A short cylinder along x (brake drums, hubs)."""
    cx, cy, cz = center
    prof = [(x0, 0.0), (x0, r), (x1, r), (x1, 0.0)]
    return geo.revolve([(ax, rr) for ax, rr in prof], N=N, axis="x", center=(0, cy, cz))


def halo(front_z, base_y, top_y, rear_z, half_w, rear_y, r=0.03):
    """Halo: centre pillar + hoop, returns polys (symmetrical)."""
    polys = []
    pillar = geo.bezier([(0, base_y, front_z - 0.03), (0, top_y - 0.05, front_z), (0, top_y, front_z + 0.07)], 6)
    polys += geo.tube(pillar, r * 1.1, N=10)
    for s in (-1, 1):
        pts = []
        cz = front_z + 0.07 + (rear_z - front_z - 0.07) * 0.62
        rz = cz - (front_z + 0.07)
        for k in range(0, 13):
            t = math.pi / 2 * k / 12
            pts.append((s * half_w * math.sin(t), top_y - 0.03 * math.sin(t), cz - rz * math.cos(t)))
        # straight run to the rear mount then down
        pts.append((s * half_w, top_y - 0.05, rear_z - 0.06))
        pts.append((s * half_w * 1.02, (top_y + rear_y) / 2, rear_z))
        pts.append((s * half_w * 1.05, rear_y, rear_z + 0.03))
        polys += geo.tube(pts, r, N=10)
    return polys


def mirror(side, pos, stalk_from, housing=(0.075, 0.036, 0.03)):
    """A wing mirror on one side (side = 1 right, -1 left): housing, glass and stalk."""
    x, y, z = pos
    hx, hy, hz = housing
    shell = geo.ellipsoid((side * x, y, z), (hx, hy, hz), N=16, M=10)
    glass = geo.plate(geo.rounded_rect(-hx * 0.85, -hy * 0.7, hx * 0.85, hy * 0.7, 0.012, 3), "xy", 0, 0.004)
    glass = geo.transform(glass, lambda v: np.array([v[0] + side * x, v[1] + y, v[2] + z + hz * 0.95]))
    stalk = rod(stalk_from, (side * (x - hx * 0.6), y - 0.01, z), r=0.012, flat=0.5)
    return shell, glass, stalk
