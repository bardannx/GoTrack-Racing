"""Shared wheel, rim and helmet meshes (unit sized; scaled per car in Roblox via MeshPart.Size).
Tyre/rim: axial along x in -0.5..0.5 (outboard = +x), radius 1 (tyre outer / rim outer)."""

import math
import numpy as np
import geo


def _arc(cx, cy, r, a0, a1, n):
    """n+1 points on a circular arc (angles in degrees)."""
    return [
        (
            cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
            cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / n)),
        )
        for k in range(n + 1)
    ]


def tyre(inner, shoulder=0.07):
    """Closed tyre cross-section revolved. inner = bead radius (0.64 for 18in, 0.47 for 13in)."""
    s = shoulder
    prof = []
    prof += [(-0.47, inner)]
    prof += [(-0.5, inner + 0.05)]
    prof += _arc(-0.5 + s, 1.0 - s, s, 180, 90, 5)  # inboard shoulder
    prof += _arc(0.5 - s, 1.0 - s, s, 90, 0, 5)  # outboard shoulder
    prof += [(0.5, inner + 0.05), (0.47, inner), (0.30, inner - 0.015), (-0.30, inner - 0.015)]
    # de-dup consecutive
    clean = []
    for p in prof:
        if not clean or (abs(clean[-1][0] - p[0]) > 1e-6 or abs(clean[-1][1] - p[1]) > 1e-6):
            clean.append(p)
    clean.append(clean[0])
    polys = geo.revolve(clean, 48, "x")
    # inboard closing disc so you never see through the wheel
    polys += geo.revolve([(-0.30, 0.0), (-0.30, inner - 0.01), (-0.33, inner - 0.01), (-0.33, 0.0)], 32, "x")
    return polys


def compound_ring(r0, r1):
    """The coloured tyre-compound band on the sidewall, between radii r0 and r1."""
    return geo.revolve([(0.5, r0), (0.508, r0), (0.508, r1), (0.5, r1), (0.5, r0)], 48, "x")


def tread_grooves(n=4):
    """Grooved-tyre bands (2000s) as thin dark rings slightly proud of the tread."""
    polys = []
    for k in range(n):
        x = -0.3 + 0.6 * k / (n - 1)
        polys += geo.revolve(
            [(x - 0.025, 1.003), (x + 0.025, 1.003), (x + 0.025, 0.995), (x - 0.025, 0.995), (x - 0.025, 1.003)],
            48,
            "x",
        )
    return polys


# ---------------------------------------------------------------------------
# rims (radius 1 = tyre bead). Face plane ~ x 0.30..0.36
# ---------------------------------------------------------------------------
FACE0, FACE1 = 0.30, 0.355


def rim_barrel():
    """The outer lip of the rim."""
    return geo.revolve(
        [(-0.45, 0.965), (0.36, 0.965), (0.40, 1.0), (0.44, 1.0), (0.44, 0.92), (-0.45, 0.92), (-0.45, 0.965)], 40, "x"
    )


def rim_back():
    """The solid disc behind the spokes."""
    return geo.revolve([(-0.15, 0.0), (-0.15, 0.93), (-0.18, 0.93), (-0.18, 0.0)], 32, "x")


def rim_hub():
    """The centre hub."""
    return geo.revolve([(0.28, 0.0), (0.28, 0.17), (0.40, 0.15), (0.43, 0.10), (0.44, 0.0)], 20, "x")


def _spoke(poly_polar, angle):
    """poly in (r, t) where t is tangential offset; rotated to angle; returns plate in the disc plane."""
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for r, t in poly_polar:
        # disc plane coords (z, y)
        y = r * ca - t * sa
        z = r * sa + t * ca
        pts.append((z, y))
    return geo.plate(pts, "zy", (FACE0 + FACE1) / 2, FACE1 - FACE0)


def spokes(count, w_in, w_out, r0=0.15, r1=0.94, twist=0.0, pair=0.0, steps=6):
    """`count` spokes from r0 to r1, optionally twisted or in pairs."""
    polys = []
    for k in range(count):
        base = 2 * math.pi * k / count
        for off in (-pair, pair) if pair else (0.0,):
            pts_l, pts_r = [], []
            for i in range(steps + 1):
                f = i / steps
                r = r0 + (r1 - r0) * f
                w = w_in + (w_out - w_in) * f
                t = twist * f * f
                pts_r.append((r, t * r - w / 2))
                pts_l.append((r, t * r + w / 2))
            polys += _spoke(pts_r + pts_l[::-1], base + off)
    return polys


def rim_style(style):
    """The spoke pattern for a rim style (classic, spoke, star, dish, turbine, blade, mesh)."""
    if style == "classic":
        return spokes(5, 0.07, 0.05, pair=0.13)
    if style == "spoke":
        return spokes(5, 0.16, 0.08)
    if style == "star":
        return spokes(6, 0.26, 0.05)
    if style == "turbine":
        return spokes(12, 0.07, 0.10, twist=0.9)
    if style == "blade":
        return spokes(4, 0.30, 0.22, twist=0.6)
    if style == "mesh":
        return spokes(10, 0.035, 0.03, twist=0.55) + spokes(10, 0.035, 0.03, twist=-0.55)
    if style == "dish":
        return geo.revolve(
            [(FACE0, 0.0), (FACE0, 0.94), (FACE1 - 0.01, 0.94), (FACE1 + 0.04, 0.5), (FACE1 + 0.05, 0.0)], 40, "x"
        )
    raise ValueError(style)


def neon_ring():
    """The glowing ring on neon rims."""
    return geo.revolve(
        [(FACE1, 0.80), (FACE1 + 0.02, 0.80), (FACE1 + 0.02, 0.87), (FACE1, 0.87), (FACE1, 0.80)], 40, "x"
    )


# ---------------------------------------------------------------------------
# helmet (studs, centred on the head, front = -z)
# ---------------------------------------------------------------------------
def helmet():
    rx, ry, rz = 0.40, 0.42, 0.47
    rings = []
    N = 32
    for i in range(1, 16):
        phi = math.pi * i / 16 * 0.9  # leave the neck open
        ring = []
        for j in range(N):
            th = 2 * math.pi * j / N
            x = rx * math.sin(phi) * math.cos(th)
            z = rz * math.sin(phi) * math.sin(th)
            y = ry * math.cos(phi)
            # chin bar forward, flatter back
            if z < 0:
                z *= 1.0 + 0.08 * max(0, -y / ry)
            ring.append((x, y, z))
        rings.append(np.array(ring))
    sides, caps = geo.loft(rings, False, True)
    top = np.array([0, ry, 0])
    polys = list(sides) + caps[None]
    R0 = rings[0]
    cap = [np.array([top, R0[(j + 1) % N], R0[j]]) for j in range(N)]
    if geo.signed_volume(sides + cap + caps[None]) < 0:
        cap = [c[::-1] for c in cap]
    polys += cap
    visor_reg = [[geo.hs_z_le(-0.18), geo.hs_y_ge(-0.07), geo.hs_y_le(0.15), geo.hs_x_ge(-0.30), geo.hs_x_le(0.30)]]
    visor, rest = geo.split(polys, visor_reg)
    stripe_reg = [
        [geo.hs_x_ge(-0.085), geo.hs_x_le(0.085), geo.hs_y_ge(0.16)],
        [geo.hs_y_ge(-0.14), geo.hs_y_le(-0.07), geo.hs_z_le(0.1)],
    ]
    stripe, shell = geo.split(rest, stripe_reg)
    return shell, stripe, visor


def helmet2():
    """Proper F1 helmet (studs, centred on the head, front = -z): long chin, wrap-around visor,
    brow + crown stripes, rear spoiler, carbon HANS collar."""
    from geo import Track, superellipse_section

    T = Track(
        {
            "cy": [
                (-0.50, -0.20),
                (-0.46, -0.14),
                (-0.38, -0.05),
                (-0.24, 0.02),
                (-0.05, 0.04),
                (0.12, 0.03),
                (0.28, 0.01),
                (0.40, 0.01),
                (0.47, 0.03),
            ],
            "wt": [
                (-0.50, 0.10),
                (-0.46, 0.22),
                (-0.38, 0.32),
                (-0.24, 0.38),
                (-0.05, 0.40),
                (0.12, 0.40),
                (0.28, 0.36),
                (0.40, 0.27),
                (0.47, 0.12),
            ],
            "wb": [
                (-0.50, 0.10),
                (-0.46, 0.20),
                (-0.38, 0.29),
                (-0.24, 0.34),
                (-0.05, 0.36),
                (0.12, 0.35),
                (0.28, 0.32),
                (0.40, 0.24),
                (0.47, 0.10),
            ],
            "ht": [
                (-0.50, 0.06),
                (-0.46, 0.16),
                (-0.38, 0.28),
                (-0.24, 0.36),
                (-0.05, 0.40),
                (0.12, 0.40),
                (0.28, 0.36),
                (0.40, 0.27),
                (0.47, 0.12),
            ],
            "hb": [
                (-0.50, 0.05),
                (-0.46, 0.10),
                (-0.38, 0.20),
                (-0.24, 0.30),
                (-0.05, 0.34),
                (0.12, 0.34),
                (0.28, 0.30),
                (0.40, 0.22),
                (0.47, 0.10),
            ],
            "n": [(-0.5, 2.3), (0.47, 2.2)],
        }
    )
    zs = [-0.50 + 0.97 * (0.5 - 0.5 * math.cos(math.pi * i / 30)) for i in range(31)]
    rings = [superellipse_section(z, T(z), 40) for z in zs]
    sides, caps = geo.loft(rings, True, True)
    polys = list(sides) + caps[None]
    visor_reg = [
        [geo.hs_z_le(-0.10), geo.hs_y_ge(-0.07), geo.hs_y_le(0.15)],
        [geo.hs_z_le(-0.42), geo.hs_y_ge(-0.24), geo.hs_y_le(-0.13), geo.hs_x_ge(-0.12), geo.hs_x_le(0.12)],
    ]
    visor, rest = geo.split(polys, visor_reg)
    stripe_reg = [
        [geo.hs_z_le(0.02), geo.hs_y_ge(0.15), geo.hs_y_le(0.21)],  # brow band over the visor
        [geo.hs_x_ge(-0.06), geo.hs_x_le(0.06), geo.hs_y_ge(0.21)],  # crown stripe
        [geo.hs_y_ge(-0.33), geo.hs_y_le(-0.26), geo.hs_z_ge(-0.30)],  # lower band
    ]
    stripe, shell = geo.split(rest, stripe_reg)
    # rear spoiler on the crown + two little fins
    spoiler = geo.transform(
        geo.box((0, 0, 0), (0.44, 0.035, 0.13)),
        lambda v: np.array(
            [
                v[0],
                v[1] * math.cos(0.25) - v[2] * math.sin(0.25) + 0.36,
                v[1] * math.sin(0.25) + v[2] * math.cos(0.25) + 0.30,
            ]
        ),
    )
    for s in (-1, 1):
        spoiler += geo.box((s * 0.2, 0.33, 0.29), (0.02, 0.09, 0.12))
    stripe = list(stripe) + spoiler
    collar = geo.ellipsoid((0, -0.42, 0.12), (0.34, 0.08, 0.30), 20, 10)
    return shell, stripe, visor, collar


# ---------------------------------------------------------------------------
# steering wheels (studs, centred on the wheel, face toward the driver = +z)
# ---------------------------------------------------------------------------
def steering_modern():
    """Modern F1 wheel: carbon body, rubber grips, screen, LED strip, coloured rotaries/buttons."""
    body_outline = [
        (-0.30, 0.20),
        (-0.12, 0.23),
        (0.12, 0.23),
        (0.30, 0.20),
        (0.34, 0.05),
        (0.30, -0.12),
        (0.16, -0.20),
        (0.08, -0.12),
        (-0.08, -0.12),
        (-0.16, -0.20),
        (-0.30, -0.12),
        (-0.34, 0.05),
    ]
    body = geo.plate(body_outline, "xy", 0.0, 0.07)
    body += geo.revolve([(0.0, 0.0), (0.0, 0.06), (-0.22, 0.05), (-0.22, 0.0)], 12, "z")  # column
    grips = []
    for s in (-1, 1):
        grips += geo.tube(
            geo.bezier([(s * 0.35, -0.16, 0.0), (s * 0.43, 0.0, 0.01), (s * 0.35, 0.19, 0.0)], 10),
            0.055,
            N=12,
            flat=0.8,
        )
    screen = geo.plate(geo.rounded_rect(-0.13, -0.02, 0.13, 0.13, 0.02, 3), "xy", 0.04, 0.015)
    leds = []
    for k in range(12):
        x = -0.165 + k * 0.03
        leds += geo.box((x, 0.19, 0.04), (0.018, 0.018, 0.012))
    buttons = []
    for x, y in ((-0.22, 0.10), (0.22, 0.10), (-0.22, -0.04), (0.22, -0.04)):
        buttons += geo.revolve([(0.035, 0.0), (0.035, 0.028), (0.07, 0.024), (0.07, 0.0)], 12, "z", center=(x, y, 0))
    for x, y in ((-0.17, 0.02), (0.17, 0.02), (-0.06, -0.08), (0.06, -0.08), (-0.26, 0.17), (0.26, 0.17)):
        buttons += geo.box((x, y, 0.045), (0.035, 0.035, 0.02))
    return body, grips, screen, leds, buttons


def steering_round():
    """Classic three-spoke round wheel (70s/80s)."""
    R = 0.30
    ring = geo.revolve([(0.0, R - 0.03), (0.03, R), (0.0, R + 0.03), (-0.03, R), (0.0, R - 0.03)], 40, "z")
    spokes = []
    for ang in (90, 210, 330):
        a = math.radians(ang)
        spokes += geo.tube([(0, 0, 0), (math.cos(a) * (R - 0.02), math.sin(a) * (R - 0.02), 0)], 0.022, N=8, flat=0.5)
    hub = geo.revolve([(0.0, 0.0), (0.0, 0.07), (-0.2, 0.05), (-0.2, 0.0)], 14, "z")
    hub += geo.revolve([(0.01, 0.0), (0.01, 0.06), (0.04, 0.05), (0.04, 0.0)], 14, "z")
    return ring, spokes, hub


def headrest():
    """U-shaped padded headrest that wraps the back and sides of the helmet (studs, head-centred)."""
    rings = []
    R = 0.47
    for k in range(17):
        a = math.radians(-115 + 230 * k / 16)  # 0 = straight behind the head (+z)
        cx, cz = math.sin(a) * R, math.cos(a) * R
        nx, nz = math.sin(a), math.cos(a)
        w, h = 0.13, 0.26
        y0 = -0.42
        ring = [
            (cx - nx * w / 2, y0, cz - nz * w / 2),
            (cx + nx * w / 2, y0, cz + nz * w / 2),
            (cx + nx * w / 2 * 0.8, y0 + h, cz + nz * w / 2 * 0.8),
            (cx - nx * w / 2, y0 + h * 0.9, cz - nz * w / 2),
        ]
        rings.append(np.array(ring))
    sd, cp = geo.loft(rings, True, True)
    return list(sd) + sum(cp.values(), [])
