"""Signature F1 details the designs bolt on (car metres: x right, y up, z towards the rear,
nose at -z). Each helper adds right + mirrored left parts straight into a Design.

Real-car references (shapes only):
  wheel_deflector   2022-25 wheel-wake winglet arching over the front tyre
  louvres           cooling gills on pods / engine cover (2022+)
  nose_cams         TV camera pods on the nose flanks
  pitot             sensor probe sticking out of the nose tip
  t_wing            2017-18 T-wing over the rear tyres' line
  monkey_seat       winglet over the exhaust (2014-16)
  x_wing            2006 pod-mounted "X-wing" towers
  horn              2006-08 chassis horn winglets
  chimney           2000s pod-top hot-air chimneys
  flip_up           winglets ahead of the rear wheels (2000s)
  inwash_board      2026 in-washing boards at the floor's front corners
  airbox_ears       auxiliary intakes beside the roll hoop
  drs_pod           actuator fairing on the rear-wing flap
  mirror_pylon      vertical vane holding the mirror (2022 zero-pod)
  overbite          upper sidepod lip that juts out over the inlet (2023 downwash)
"""
import math
import numpy as np
import geo
import parts as P


def _mir(polys, s):
    return polys if s > 0 else geo.mirror_x(polys)


def both(d, group, slot, polys, split_groups=False):
    """Add polys (built for the right side) and their mirror. split_groups: RightPod / LeftPod."""
    if split_groups:
        d.add("RightPod", slot, polys)
        d.add("LeftPod", slot, geo.mirror_x(polys))
    else:
        d.add(group, slot, polys + geo.mirror_x(polys))


def obox(center, size, pitch=0.0, yaw=0.0, roll=0.0):
    """Box rotated about its centre (degrees): pitch about x, yaw about y, roll about z."""
    polys = geo.box((0, 0, 0), size)
    p, y, r = math.radians(pitch), math.radians(yaw), math.radians(roll)
    cp, sp, cy, sy, cr, sr = math.cos(p), math.sin(p), math.cos(y), math.sin(y), math.cos(r), math.sin(r)
    Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]])
    R = Rz @ Ry @ Rx
    c = np.asarray(center, float)
    return [np.array([R @ v + c for v in poly]) for poly in polys]


def arc_band(cz, cy, r0, r1, a0, a1, n=10):
    """Annular sector in the zy plane (angles in degrees, 0 = +z/rear, 90 = up, 180 = front)."""
    outer = [(cz + r1 * math.cos(math.radians(a0 + (a1 - a0) * k / n)), cy + r1 * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]
    inner = [(cz + r0 * math.cos(math.radians(a0 + (a1 - a0) * k / n)), cy + r0 * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]
    return outer + inner[::-1]


# ---------------------------------------------------------------------------
# modern details
# ---------------------------------------------------------------------------
def wheel_deflector(d, wheel, a0=95, a1=150, gap=0.035, slot="Carbon"):
    """Curved winglet over the top-front of a front tyre (car-metre wheel anchor dict)."""
    x, y, z = wheel["pos"]
    r, w = wheel["r"], wheel["w"]
    x = abs(x)
    band = arc_band(z, y, r + gap, r + gap + 0.018, a0, a1, 8)
    blade = geo.plate(band, "zy", x - w * 0.12, w * 0.62)
    # little strut down to the (hidden) brake duct
    strut = P.endplate([(z - 0.02, y + r * 0.35), (z + 0.05, y + r * 0.35), (z + 0.05 - (r + gap) * 0.1, y + r + gap), (z - 0.05, y + r + gap)], x - w * 0.42, 0.012)
    both(d, "Body", slot, blade + strut)


def louvres(d, x, z0, z1, y_of_z, n=5, w=0.14, slot="Dark", split_groups=True, pitch=-12):
    """Row of cooling slats along z on a surface whose height is y_of_z(z)."""
    polys = []
    for k in range(n):
        z = z0 + (z1 - z0) * (k + 0.5) / n
        polys += obox((x, y_of_z(z) + 0.004, z), (w, 0.014, (z1 - z0) / n * 0.55), pitch=pitch)
    both(d, "Body", slot, polys, split_groups)


def nose_cams(d, x, y, z, slot="Dark"):
    both(d, "Body", slot, geo.ellipsoid((x, y, z), (0.022, 0.02, 0.06), 12, 8))


def pitot(d, y, z, length=0.14):
    d.add("Body", "Metal", geo.tube([(0, y, z), (0, y, z - length)], 0.006, N=6))


def t_wing(d, y, z, span=0.2, chord=0.07, twin=False, slot="Carbon"):
    for k in range(2 if twin else 1):
        d.add("RearWing", slot, P.wing_element(-span, span, lambda x, k=k: {"y": y + 0.06 * k, "z": z + 0.03 * k, "c": chord, "a": 10}, stations=6))
    d.add("RearWing", slot, P.endplate([(z - 0.01, y - 0.06), (z + chord + 0.02, y - 0.06), (z + chord + 0.02, y + (0.09 if twin else 0.03)), (z - 0.01, y + (0.09 if twin else 0.03))], 0, 0.01))


def monkey_seat(d, y, z, span=0.16, slot="Carbon"):
    d.add("RearWing", slot, P.wing_element(-span, span, lambda x: {"y": y, "z": z, "c": 0.09, "a": 18}, stations=6))
    d.add("RearWing", slot, P.wing_element(-span, span, lambda x: {"y": y + 0.045, "z": z + 0.05, "c": 0.06, "a": 30}, stations=6))


def x_wing(d, x, z, y0, y1, span=0.12, slot="Carbon"):
    """Pod-mounted tower with a small wing on top (per side, in the pod damage groups)."""
    tower = P.endplate([(z - 0.03, y0), (z + 0.05, y0), (z + 0.07, y1 + 0.02), (z, y1 + 0.02)], x, 0.014)
    wing = P.wing_element(x - span, x + span, lambda xx: {"y": y1, "z": z - 0.02, "c": 0.09, "a": 12}, stations=6)
    plates = [P.endplate([(z - 0.04, y1 - 0.03), (z + 0.08, y1 - 0.03), (z + 0.08, y1 + 0.05), (z - 0.04, y1 + 0.05)], x + sx, 0.008) for sx in (-span, span)]
    polys = tower + wing + plates[0] + plates[1]
    both(d, "Body", slot, polys, split_groups=True)


def horn(d, x0, x1, y, z, slot="Carbon"):
    """Chassis-mounted horn winglet with an outer endplate."""
    wing = P.wing_element(x0, x1, lambda x: {"y": y + 0.03 * (x - x0) / (x1 - x0), "z": z, "c": 0.09, "a": 14}, stations=6)
    ep = P.endplate([(z - 0.02, y - 0.05), (z + 0.1, y - 0.05), (z + 0.1, y + 0.06), (z - 0.02, y + 0.04)], x1, 0.008)
    both(d, "Body", slot, wing + ep)


def chimney(d, x, y, z, r=0.045, h=0.08, slot="Carbon"):
    outer = geo.revolve([(0.0, r * 0.2), (0.0, r), (h, r * 0.9), (h, r * 0.7), (h - 0.01, r * 0.62)], 14, "y", center=(x, y, z))
    cap = geo.revolve([(h - 0.012, 0.0), (h - 0.012, r * 0.64)], 14, "y", center=(x, y, z))
    both(d, "Body", slot, outer, split_groups=True)
    both(d, "Body", "Dark", cap, split_groups=True)


def flip_up(d, x, z, y, slot="Carbon"):
    ep = P.endplate([(z - 0.12, y - 0.1), (z + 0.08, y - 0.1), (z + 0.1, y + 0.08), (z - 0.06, y + 0.06)], x, 0.01)
    w = P.wing_element(x - 0.1, x, lambda xx: {"y": y + 0.02, "z": z - 0.08, "c": 0.12, "a": 16}, stations=6)
    both(d, "Body", slot, ep + w, split_groups=True)


def inwash_board(d, x, z0, z1, h=0.2, slot="Carbon"):
    both(d, "Body", slot, P.endplate([(z0, 0.07), (z1, 0.07), (z1 - 0.05, 0.07 + h), (z0 + 0.1, 0.07 + h * 0.75)], x, 0.012))


def airbox_ears(d, x, y, z, slot="Primary"):
    shell = geo.ellipsoid((x, y, z + 0.08), (0.05, 0.045, 0.13), 14, 8)
    mouth = geo.plate(geo.rounded_rect(x - 0.035, y - 0.03, x + 0.035, y + 0.03, 0.02, 3), "xy", z - 0.03, 0.01)
    both(d, "Body", slot, shell)
    both(d, "Body", "Dark", mouth)


def drs_pod(d, y, z, var=None, slot="Carbon"):
    polys = geo.ellipsoid((0, y, z), (0.03, 0.045, 0.1), 12, 8)
    if var:
        d.var(var, "RearWing", slot, polys)
    else:
        d.add("RearWing", slot, polys)


def mirror_pylon(d, x, z, y0, y1, slot="Primary"):
    both(d, "Body", slot, P.endplate([(z - 0.06, y0), (z + 0.14, y0), (z + 0.08, y1), (z - 0.03, y1)], x, 0.014), split_groups=True)


def overbite(d, cx, wt, y, z, depth=0.12, slot="Primary"):
    """Thin lip plate jutting forward over a sidepod inlet (right side, mirrored)."""
    lip = geo.plate(geo.rounded_rect(cx - wt, z - depth, cx + wt, z + 0.06, 0.03, 3), "xz", y, 0.025)
    both(d, "Body", slot, lip, split_groups=True)


def cockpit_rim(d, cx, z0, z1, y, slot="Dark"):
    """Padded cockpit surround."""
    path = [(cx, y, z0 + 0.1), (cx * 1.02, y, (z0 + z1) / 2), (cx * 0.95, y + 0.01, z1 - 0.08)]
    both(d, "Body", slot, geo.tube(geo.bezier(path, 8), 0.022, N=8))


def rear_light_bar(d, y, z, w=0.22, slot="TailLight"):
    """Wide LED strip (concepts)."""
    d.add("Body", slot, geo.box((0, y, z), (w, 0.03, 0.02)))
