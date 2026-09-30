"""Car designs. Each returns a Design with base objects, livery overlays and anchors (car metres)."""

import math
import numpy as np
import geo
import parts as P
import details as X
from geo import Track, superellipse_section

# stud conversion (shared by all designs so every chassis has the same hitbox)
SX, SY, SZ = 2.9, 2.75, 2.65
YG = -1.95  # ground height in chassis space
ZC = 1.72  # car-metre z that maps to the chassis centre
FAST = False  # skip livery overlays (quick previews)
PREVIEW_PATTERNS = None  # or a set of pattern keys to build


def to_studs(v):
    """Car metres -> Roblox studs, lined up with the shared chassis hitbox."""
    return np.array([v[0] * SX, v[1] * SY + YG, (v[2] - ZC) * SZ])


class Design:
    """One car as it's being built: meshes by (group, slot), livery overlays, variants
    (optional parts like a second rear wing) and anchors (wheels, head, cameras...).
    """

    def __init__(self, name):
        self.name = name
        self.objs = {}  # (group, slot) -> polys
        self.pats = {}  # pattern key -> {group: polys}
        self.anchors = {}
        self.variants = {}  # variant key -> {(group, slot): polys}
        self.flaps = {}  # variant key ("" = always) -> rear-wing flap hinge (0, y, z)

    def add(self, group, slot, polys):
        if polys:
            self.objs.setdefault((group, slot), []).extend(polys)

    def pat(self, key, group, polys):
        if polys:
            self.pats.setdefault(key, {}).setdefault(group, []).extend(polys)

    def var(self, key, group, slot, polys):
        if polys:
            self.variants.setdefault(key, {}).setdefault((group, slot), []).extend(polys)


# ---------------------------------------------------------------------------
# shared livery overlays on body + pods
# ---------------------------------------------------------------------------
def body_liveries(
    d, body_rings, cy_curve, top_curve, cockpit_ex, stripe_w, nose_z, cover_z, pod_rings_r, pod_info, cover_side
):
    """cy_curve / top_curve: [(z, y)] along the centreline. pod_info: dict z0,z1,cy(z)->, outer side threshold."""
    above = P.above_curve_region(cy_curve)
    z_front, z_rear = cy_curve[0][0], cy_curve[-1][0]

    def body_ov(region):
        return P.overlay_from_rings(body_rings, region, cockpit_ex)

    def pod_ov(region, side):
        rings = pod_rings_r if side > 0 else [np.array([[-v[0], v[1], v[2]] for v in r]) for r in pod_rings_r]
        if side < 0:
            region = mirror_region(region)
        polys = P.overlay_from_rings(rings, region)
        return polys

    # centre stripe
    d.pat("stripe", "Body", body_ov(P.with_extra(above, [geo.hs_x_ge(-stripe_w), geo.hs_x_le(stripe_w)])))
    # retro twin stripes (A wide off-centre, B thin)
    d.pat("retroA", "Body", body_ov(P.with_extra(above, [geo.hs_x_ge(-stripe_w * 2.3), geo.hs_x_le(-stripe_w * 0.35)])))
    d.pat("retroB", "Body", body_ov(P.with_extra(above, [geo.hs_x_ge(stripe_w * 0.2), geo.hs_x_le(stripe_w * 1.0)])))
    # two tone: everything above a line
    split_line = [(z_front, pod_info["split_front"]), (nose_z[1], pod_info["split_y"]), (z_rear, pod_info["split_y"])]
    split_reg = P.above_curve_region(split_line)
    d.pat("split", "Body", body_ov(split_reg))
    for s, g in ((1, "RightPod"), (-1, "LeftPod")):
        d.pat("split", g, pod_ov(split_reg, s))
    # chevron on the nose (V pointing forward)
    zc0, k, t = pod_info["chev_z"], pod_info["chev_k"], pod_info["chev_t"]
    chev = []
    for s in (1, -1):
        # z >= zc0 + k*|x|  and z <= zc0 + t + k*|x|   (x on side s)
        chev.append(
            [geo.H((-s * k, 0, 1), -zc0), geo.H((s * k, 0, -1), zc0 + t), geo.hs_x_ge(0) if s > 0 else geo.hs_x_le(0)]
        )
    d.pat("chevron", "Body", geo.keep(body_ov(chev), above))
    # pod-top chevrons
    pz, pk, pt = pod_info["pchev_z"], pod_info["pchev_k"], pod_info["pchev_t"]
    for s, g in ((1, "RightPod"), (-1, "LeftPod")):
        xc = pod_info["pod_cx"]
        reg = [
            [
                geo.H((-pk, 0, 1), -(pz - pk * xc)),
                geo.H((pk, 0, -1), (pz - pk * xc) + pt),
                geo.hs_x_ge(xc),
                geo.hs_y_ge(pod_info["pod_top_y"]),
            ],
            [
                geo.H((pk, 0, 1), -(pz + pk * xc)),
                geo.H((-pk, 0, -1), (pz + pk * xc) + pt),
                geo.hs_x_le(xc),
                geo.hs_y_ge(pod_info["pod_top_y"]),
            ],
        ]
        d.pat("chevron", g, pod_ov(reg, s))
    # checker on the engine cover top
    cz0, cz1 = cover_z
    cell = pod_info["check_cell"]
    wmax = pod_info["check_w"]
    ncol = int(round(2 * wmax / cell))
    nrow = int(round((cz1 - cz0) / cell))
    A, B = [], []
    for r in range(nrow):
        for c in range(ncol):
            x0 = -wmax + c * cell
            z0 = cz0 + r * cell
            piece = [
                geo.hs_x_ge(x0),
                geo.hs_x_le(x0 + cell),
                geo.hs_z_ge(z0),
                geo.hs_z_le(z0 + cell),
                geo.hs_y_ge(pod_info["check_ymin"]),
            ]
            (A if (r + c) % 2 == 0 else B).append(piece)
    d.pat("checkA", "Body", body_ov(A))
    d.pat("checkB", "Body", body_ov(B))
    # side flash along the pod flank (+ an accent on the cover side)
    fl = pod_info["flash"]  # polygon in zy
    for s, g in ((1, "RightPod"), (-1, "LeftPod")):
        reg = geo.poly_region("zy", fl, [geo.hs_x_ge(pod_info["outer_x"])])
        d.pat("side", g, pod_ov(reg, s))
    cs = cover_side
    reg = geo.poly_region("zy", cs, [geo.hs_x_ge(0.02)]) + geo.poly_region("zy", cs, [geo.hs_x_le(-0.02)])
    d.pat("side", "Body", body_ov(reg))
    # circuit lines (thin bands)
    for s, g in ((1, "RightPod"), (-1, "LeftPod")):
        reg = geo.poly_region("zy", pod_info["circuit"], [geo.hs_x_ge(pod_info["outer_x"])])
        d.pat("circuit", g, pod_ov(reg, s))
    reg = []
    for s in (1, -1):
        xa, xb = sorted((s * stripe_w * 1.6, s * stripe_w * 2.1))
        reg += P.with_extra(above, [geo.hs_x_ge(xa), geo.hs_x_le(xb)])
    d.pat("circuit", "Body", body_ov(reg))
    # flames: three stacked layers on the pod flanks
    for li, poly in enumerate(pod_info["flames"]):
        for s, g in ((1, "RightPod"), (-1, "LeftPod")):
            reg = geo.poly_region("zy", poly, [geo.hs_x_ge(pod_info["outer_x"])])
            rings = pod_rings_r if s > 0 else [np.array([[-v[0], v[1], v[2]] for v in r]) for r in pod_rings_r]
            rr = reg if s > 0 else mirror_region(reg)
            d.pat("flame%d" % (li + 1), g, P.overlay_from_rings(rings, rr, d=P.DELTA * (1 + li * 0.8)))


def mirror_region(region):
    """A colour-zone region mirrored to the other side of the car."""
    out = []
    for piece in region:
        np_ = []
        for a, b in piece:
            a2 = np.array(a, float).copy()
            a2[0] *= -1
            np_.append((a2, b))
        out.append(np_)
    return out


def flame_poly(z0, z1, y_mid, h, tongues=5, seed=1.0):
    """Flame silhouette in the zy plane: flat base at z0, fat tongues licking back to ~z1."""
    L = z1 - z0
    n = tongues
    dh = h / n
    ybot = y_mid - h / 2
    lens = [L * (0.55 + 0.45 * abs(math.sin((i + 1) * 1.7 * seed))) for i in range(n)]
    pts = [(z0, ybot), (z0 + lens[0] * 0.55, ybot + dh * 0.12)]
    for i in range(n):
        yM = ybot + dh * (i + 0.5)
        pts.append((z0 + lens[i], yM + dh * 0.1))
        if i < n - 1:
            pts.append((z0 + 0.5 * min(lens[i], lens[i + 1]), ybot + dh * (i + 1)))
    pts.append((z0 + lens[-1] * 0.5, ybot + h - dh * 0.1))
    pts.append((z0, ybot + h))
    return pts


# ---------------------------------------------------------------------------
# generic open-wheeler builder
# ---------------------------------------------------------------------------
def _mirrored(polys, s):
    return polys if s > 0 else geo.mirror_x(polys)


def recess(cap_polys, depth):
    """Push the centre vertex of a fan cap inward (+z) so intakes look recessed and have depth."""
    from collections import Counter

    cnt = Counter(tuple(np.round(v, 7)) for p in cap_polys for v in p)
    centre = np.array(cnt.most_common(1)[0][0])
    out = []
    for p in cap_polys:
        q = np.array(p, float).copy()
        for v in q:
            if np.linalg.norm(v - centre) < 1e-5:
                v[2] += depth
        out.append(q)
    return out


def add_pods(d, S):
    """Lofts the sidepods from the design's pod keyframes (smooth or faceted sections)."""
    pod = Track(S["pod"])
    z0, z1 = S["pod_z"]
    facet = S.get("section") == "facet"
    pzs = P.zsamples(z0, z1, 0.05 if not facet else 0.3, dense=[] if facet else [(z0, z0 + 0.15, 0.015)])
    secfn = geo.facet_section if facet else superellipse_section
    prings = [secfn(z, pod(z), 40) for z in pzs]
    psides, pcaps = P.loft_obj(prings, True, True, "Dark", "")
    pcaps["Dark"] = recess(pcaps["Dark"], 0.05)
    for s, g in ((1, "RightPod"), (-1, "LeftPod")):
        d.add(g, "Primary", _mirrored(psides + pcaps[""], s))
        d.add(g, "Dark", _mirrored(pcaps["Dark"], s))
        if S.get("pod_lip", True):
            e = 0.012
            lipr = [
                secfn(
                    z,
                    dict(pod(z), wt=pod(z)["wt"] + e, wb=pod(z)["wb"] + e, ht=pod(z)["ht"] + e, hb=pod(z)["hb"] + e),
                    40,
                )
                for z in (z0 - 0.01, z0 + 0.04)
            ]
            ls, _ = geo.loft(lipr, False, False)
            d.add(g, "Secondary", _mirrored(ls, s))
        if S.get("mirror"):
            pos, stalk = S["mirror"]
            shell, glass, st = P.mirror(s, pos, (s * stalk[0], stalk[1], stalk[2]))
            d.add(g, "Primary", shell)
            d.add(g, "Glass", glass)
            d.add(g, "Carbon", st)
    return prings


def add_floor(d, S):
    """The flat floor under the car, with its edge details."""
    f = S.get("floor")
    if not f:
        return
    outline = f["half"] + [(-x, z) for x, z in reversed(f["half"])]
    d.add("Body", "Carbon", geo.plate(outline, "xz", f.get("y", 0.065), 0.03))
    if f.get("edge"):
        z0, z1, x = f["edge"]
        for s in (1, -1):
            d.add(
                "Body",
                "Carbon",
                P.endplate([(z0, 0.08), (z1, 0.08), (z1 - 0.04, 0.15), (z0 + 0.17, 0.17)], s * x, 0.012),
            )
    if f.get("diffuser"):
        z0, z1, w, y1 = f["diffuser"]
        d.add("Body", "Carbon", geo.plate([(z0, 0.06), (z1, y1), (z1, y1 + 0.03), (z0, 0.09)], "zy", 0, w * 2))
        for x in f.get("strakes", (-w + 0.01, -w / 2, 0.0, w / 2, w - 0.01)):
            d.add("Body", "Carbon", P.endplate([(z0, 0.06), (z1, 0.06), (z1, y1 + 0.02), (z0 + 0.05, 0.09)], x, 0.012))


def add_susp(d, S):
    """Suspension wishbones and push-rods on both sides."""
    su = S["susp"]
    polys = []
    for s in (1, -1):

        def m(v):
            return (s * v[0], v[1], v[2])

        for a, b, c in su["wishbones"]:
            polys += P.wishbone(m(a), m(b), m(c))
        for a, b, r in su.get("rods", []):
            polys += P.rod(m(a), m(b), r, flat=1 if r > 0.015 else 0.45)
    d.add("Body", "Carbon", polys)
    for cz, x0, x1, r in su["drums"]:
        dr = P.drum((0, S["wheel_y"], cz), r, x0, x1)
        d.add("Body", "Carbon", dr + geo.mirror_x(dr))


def open_wheeler(name, S):
    """Builds an open-wheel car from a spec S: body and cockpit, sidepods, floor, intake,
    fin, exhausts, halo, suspension and wings, then the chassis' signature details
    (SIGNATURE) and the livery overlays.
    """
    d = Design(name)
    pre, post = SIGNATURE.get(name, (None, None))
    if pre:
        pre(S)
    N = S.get("N", 48)
    body = Track(S["body"], linear={"dip", "dipw"})
    z0, z1 = S["body_z"]
    zs = S["zs"] if S.get("zs") else P.zsamples(z0, z1, 0.05, dense=S.get("dense", []))
    secfn = geo.facet_section if S.get("section") == "facet" else superellipse_section
    rings = [secfn(z, body(z), N) for z in zs]
    sides, caps = P.loft_obj(rings)
    polys = sides + caps[""]
    dark = []
    if S.get("cockpit"):
        cx, cz0, cz1, cy0 = S["cockpit"]
        dark, polys = geo.split(polys, P.box_region(x0=-cx, x1=cx, z0=cz0, z1=cz1, y0=cy0))
    tip = []
    if S.get("tip_z") is not None:
        tip, polys = geo.split(polys, P.box_region(z1=S["tip_z"]))
    d.add("Body", "Primary", polys)
    d.add("Body", "Secondary", tip)
    d.add("Body", "Dark", dark)

    prings = add_pods(d, S) if S.get("pod") else None
    add_floor(d, S)
    if S.get("intake"):
        hx, y0, y1, z = S["intake"]
        d.add(
            "Body", "Dark", geo.plate(geo.rounded_rect(-hx, y0, hx, y1, min(hx, (y1 - y0) / 2) * 0.6, 3), "xy", z, 0.03)
        )
    if S.get("tcam"):
        d.add("Body", "TCam", geo.box(S["tcam"], (0.11, 0.035, 0.07)))
    if S.get("fin"):
        if S.get("fin_always"):
            d.add("Body", "Secondary", P.endplate(S["fin"], 0, 0.01))
        else:
            d.var("fin", "Body", "Secondary", P.endplate(S["fin"], 0, 0.01))
    if S.get("tail"):
        d.add("Body", "TailLight", geo.box(S["tail"], (0.09, 0.05, 0.03)))
    for ex, ey, ez, r, ln in S.get("exhausts", []):
        d.add(
            "Body",
            "Metal",
            geo.revolve(
                [
                    (ez - ln, 0.0),
                    (ez - ln, r),
                    (ez, r),
                    (ez, r * 0.8),
                    (ez - ln + 0.01, r * 0.8),
                    (ez - ln + 0.01, 0.0),
                ],
                16,
                "z",
                center=(ex, ey, 0),
            ),
        )
    if S.get("halo"):
        d.add("Body", "Halo", P.halo(*S["halo"]))
    if S.get("suit"):
        d.add("Body", "Suit", geo.ellipsoid(S["suit"], (0.19, 0.08, 0.14), 16, 10))
    add_susp(d, S)
    S["wings"](d)
    if S.get("extras"):
        S["extras"](d, body)
    if post:
        post(d, body, S)

    if not FAST:
        L = S["liv"]
        cy_curve = [(z, body(z)["cy"]) for z in np.linspace(z0, z1, 40)]
        top_curve = [(z, body(z)["cy"] + body(z)["ht"]) for z in np.linspace(z0, z1, 40)]
        body_liveries(
            d,
            rings,
            cy_curve,
            top_curve,
            L["cockpit_ex"],
            L["stripe_w"],
            (z0, L["nose_end"]),
            L["cover_z"],
            prings,
            L,
            L["cover_side"],
        )
    d.anchors = S["anchors"](body)
    if d.flaps:
        d.anchors["flap"] = dict(d.flaps)
    return d


def fw_elements(d, elements, span, inner, endplate, ep_slot="Primary", sweep_rise=(0.40, 0.93)):
    """elements: list of (y0, zle, chord, aoa, rise, sweep, chord_out, slot, full_span)."""

    def el(y0, zle, c, a, rise, sweep, ch_out):
        def fn(x):
            t = geo.smoothstep(sweep_rise[0] * span / 0.935, sweep_rise[1] * span / 0.935, abs(x))
            return {"y": y0 + rise * t**1.4, "z": zle + sweep * t, "c": c * (1 - (1 - ch_out) * t), "a": a + 10 * t}

        return fn

    for y0, zle, c, a, rise, sweep, cho, slot, full in elements:
        if full:
            d.add(
                "FrontWing",
                slot,
                P.wing_element(-span, span, el(y0, zle, c, a, rise, sweep, cho), thick=0.06, camber=-0.04),
            )
        else:
            for s in (1, -1):
                x0, x1 = (inner, span) if s > 0 else (-span, -inner)
                d.add(
                    "FrontWing",
                    slot,
                    P.wing_element(x0, x1, el(y0, zle, c, a, rise, sweep, cho), stations=20, thick=0.06, camber=-0.05),
                )
    for s in (1, -1):
        d.add("FrontWing", ep_slot, P.endplate(endplate, s * (span + 0.01), 0.014))


def rw_elements(d, elements, span, endplate, droop=0.05, ep_slot="Primary", var=None, flap=True):
    """Rear wing. With flap=True the top element (slot "Secondary") is its own "Flap" group so
    the game can open it on straights (active aero); its hinge is recorded in d.flaps."""

    def mk(y0, zle, c, a):
        def fn(x):
            t = abs(x) / span
            return {"y": y0 - droop * t**4 + 0.02 * t * t, "z": zle, "c": c, "a": a}

        return fn

    add = (lambda g, sl, p: d.var(var, g, sl, p)) if var else d.add
    for y0, zle, c, a, slot in elements:
        grp = "RearWing"
        if flap and slot == "Secondary":
            grp = "Flap"
            # hinge at the trailing edge: opening lifts the leading edge (like DRS / 2026 aero)
            d.flaps[var or ""] = (0.0, y0 + c * math.sin(math.radians(a)), zle + c * math.cos(math.radians(a)))
        add(grp, slot, P.wing_element(-span, span, mk(y0, zle, c, a), camber=-0.06, thick=0.08))
    for s in (1, -1):
        add("RearWing", ep_slot, P.endplate(endplate, s * (span + 0.007), 0.014))


def swan_necks(d, var, x, z0, y0, z1, y1):
    """Swan-neck pylons hanging the rear wing from above, on variant `var` (or on every
    build of the car when var is None)."""
    for s in (1, -1):
        path = geo.bezier(
            [
                (s * x, y0, z0),
                (s * x, (y0 + y1) / 2, z0 + 0.02),
                (s * x, y1 + 0.06, z1 - 0.05),
                (s * x, y1 + 0.02, z1 + 0.05),
            ],
            10,
        )
        tube = geo.tube(path, 0.018, N=8, flat=0.5)
        if var:
            d.var(var, "RearWing", "Carbon", tube)
        else:
            d.add("RearWing", "Carbon", tube)


def std_anchors(body, wheels, head, nose_z, side, exhaust, engine, trail, glow):
    """The anchor points every car needs: wheels, driver's head, number plates, exhaust,
    engine, trail and underglow.
    """
    b = body(nose_z)
    return {
        "wheels": wheels,
        "head": (head[0], head[1] - 0.05, head[2]),  # driver sits down in the seat
        "numberNose": {"pos": (0, b["cy"] + b["ht"] + 0.004, nose_z), "size": (0.16, 0.16), "pitch": 9},
        "numberSide": {"pos": side, "size": (0.20, 0.16)},
        "exhaust": exhaust,
        "engine": engine,
        "trail": trail,
        "underglow": glow,
    }


def default_liv(**kw):
    """Default livery-overlay placement, with any value overridden by keyword."""
    L = {
        "split_front": 0.27,
        "split_y": 0.53,
        "chev_z": -0.62,
        "chev_k": 1.3,
        "chev_t": 0.16,
        "pchev_z": 1.55,
        "pchev_k": 0.9,
        "pchev_t": 0.12,
        "pod_cx": 0.55,
        "pod_top_y": 0.5,
        "check_cell": 0.075,
        "check_w": 0.30,
        "check_ymin": 0.62,
        "outer_x": 0.45,
        "flash": [(1.30, 0.37), (1.30, 0.47), (2.2, 0.42), (3.2, 0.33), (3.2, 0.30), (2.2, 0.37)],
        "circuit": [(1.32, 0.445), (2.3, 0.40), (3.1, 0.33), (3.1, 0.315), (2.3, 0.385), (1.32, 0.43)],
        "flames": [
            flame_poly(1.30, 2.9, 0.43, 0.22, 5, 1.0),
            flame_poly(1.30, 2.5, 0.43, 0.16, 4, 1.4),
            flame_poly(1.30, 2.05, 0.43, 0.10, 3, 1.9),
        ],
        "cockpit_ex": P.box_region(x0=-0.215, x1=0.215, z0=1.04, z1=1.9, y0=0.47),
        "stripe_w": 0.055,
        "nose_end": 0.5,
        "cover_z": (2.05, 3.55),
        "cover_side": [(2.1, 0.62), (2.1, 0.72), (3.6, 0.53), (3.6, 0.47)],
    }
    L.update(kw)
    return L


# ---------------------------------------------------------------------------
# GT-1: 2026-spec (this season's real cars) - tight downwash sidepods with a deep undercut
# and an overbite inlet, in-wash boards on the floor, no beam wing, active-aero rear flap
# ---------------------------------------------------------------------------
def modern():
    def wings(d):
        fw_elements(
            d,
            [
                (0.075, -1.06, 0.32, 3, 0.02, 0.06, 1.0, "Accent", True),
                (0.105, -0.80, 0.20, 12, 0.05, 0.04, 1.0, "Accent", False),
                (0.14, -0.66, 0.16, 22, 0.08, 0.03, 1.0, "Accent", False),
                (0.185, -0.55, 0.13, 34, 0.10, 0.02, 0.8, "Secondary", False),
            ],
            0.935,
            0.15,
            [(-1.08, 0.025), (-0.46, 0.025), (-0.44, 0.13), (-0.50, 0.25), (-0.60, 0.29), (-0.86, 0.24), (-1.08, 0.11)],
        )
        rw_elements(
            d,
            [(0.80, 3.98, 0.33, 8, "Accent"), (0.91, 4.25, 0.21, 32, "Secondary")],
            0.515,
            [(3.92, 0.60), (4.46, 0.56)] + P.arc_pts(4.37, 0.88, 0.11, -30, 90, 6)[1:] + [(4.02, 0.99), (3.93, 0.86)],
            var="rwA",
        )
        d.var(
            "rwA", "RearWing", "Carbon", P.endplate([(3.92, 0.36), (4.12, 0.36), (4.22, 0.82), (4.04, 0.82)], 0, 0.02)
        )
        rw_elements(
            d,
            [(0.79, 3.96, 0.36, 11, "Accent"), (0.93, 4.25, 0.25, 38, "Secondary")],
            0.515,
            [(3.88, 0.50), (4.52, 0.50), (4.52, 1.03), (3.93, 1.03)],
            droop=0.0,
            var="rwB",
        )
        swan_necks(d, "rwB", 0.09, 3.98, 0.40, 4.12, 0.80)
        X.drs_pod(d, 0.985, 4.33, var="rwA")
        # 2026: the beam wing is gone - just the crash structure with its rain light

    def extras(d, body):
        # downwash sidepods: overbite lip over a wide letterbox inlet, gills on the ramp
        X.overbite(d, 0.555, 0.255, 0.585, 1.33, depth=0.11)
        pod = Track(S["pod"])
        X.louvres(d, 0.52, 2.05, 2.75, lambda z: pod(z)["cy"] + pod(z)["ht"], n=6, w=0.16)
        # in-wash boards at the floor's front corners (new for 2026)
        for x, z0, z1, h in ((0.62, 0.62, 1.12, 0.26), (0.74, 0.78, 1.18, 0.2)):
            X.inwash_board(d, x, z0, z1, h)
        # nose camera pods, pitot probe, airbox ears, cockpit padding
        X.nose_cams(d, 0.105, 0.33, -0.36)
        X.pitot(d, 0.21, -0.99, 0.12)
        X.airbox_ears(d, 0.16, 0.86, 1.98)
        X.cockpit_rim(d, 0.2, 1.06, 1.88, 0.62)

    S = {
        "body": {
            "cy": [
                (-0.99, 0.20),
                (-0.93, 0.215),
                (-0.70, 0.26),
                (-0.30, 0.33),
                (0.10, 0.40),
                (0.50, 0.44),
                (0.95, 0.45),
                (1.25, 0.45),
                (1.75, 0.45),
                (1.97, 0.50),
                (2.25, 0.50),
                (2.80, 0.47),
                (3.40, 0.42),
                (3.90, 0.36),
                (4.15, 0.34),
            ],
            "wt": [
                (-0.99, 0.06),
                (-0.93, 0.11),
                (-0.70, 0.13),
                (-0.30, 0.14),
                (0.10, 0.15),
                (0.50, 0.19),
                (0.95, 0.24),
                (1.25, 0.29),
                (1.75, 0.30),
                (1.97, 0.11),
                (2.25, 0.10),
                (2.80, 0.10),
                (3.40, 0.08),
                (3.90, 0.06),
                (4.15, 0.045),
            ],
            "wb": [
                (-0.99, 0.08),
                (-0.93, 0.13),
                (-0.70, 0.15),
                (-0.30, 0.165),
                (0.10, 0.19),
                (0.50, 0.24),
                (0.95, 0.30),
                (1.25, 0.33),
                (1.75, 0.34),
                (1.97, 0.34),
                (2.25, 0.33),
                (2.80, 0.27),
                (3.40, 0.18),
                (3.90, 0.09),
                (4.15, 0.055),
            ],
            "ht": [
                (-0.99, 0.03),
                (-0.93, 0.06),
                (-0.70, 0.085),
                (-0.30, 0.10),
                (0.10, 0.115),
                (0.50, 0.14),
                (0.95, 0.21),
                (1.25, 0.27),
                (1.75, 0.27),
                (1.97, 0.47),
                (2.25, 0.42),
                (2.80, 0.30),
                (3.40, 0.19),
                (3.90, 0.10),
                (4.15, 0.06),
            ],
            "hb": [
                (-0.99, 0.04),
                (-0.93, 0.06),
                (-0.70, 0.08),
                (-0.30, 0.10),
                (0.10, 0.13),
                (0.50, 0.19),
                (0.95, 0.30),
                (1.25, 0.33),
                (1.75, 0.33),
                (1.97, 0.38),
                (2.25, 0.38),
                (2.80, 0.35),
                (3.40, 0.30),
                (3.90, 0.18),
                (4.15, 0.07),
            ],
            "n": [(-0.99, 2.2), (-0.5, 2.6), (0.95, 2.8), (1.75, 3.0), (1.97, 2.2), (2.8, 2.4), (4.15, 2.4)],
            "dip": [(-1, 0), (1.02, 0), (1.12, 0.22), (1.80, 0.22), (1.90, 0), (5, 0)],
            "dipw": [(-1, 0.2), (5, 0.2)],
        },
        "body_z": (-0.99, 4.15),
        "dense": [(-0.99, -0.85, 0.02), (0.95, 1.2, 0.02), (1.75, 2.05, 0.02), (4.0, 4.15, 0.025)],
        "cockpit": (0.19, 1.06, 1.88, 0.49),
        "tip_z": -0.80,
        "pod": {
            "cx": [(1.30, 0.555), (1.40, 0.565), (1.80, 0.55), (2.40, 0.46), (2.95, 0.35), (3.40, 0.25), (3.60, 0.20)],
            "cy": [(1.30, 0.45), (1.40, 0.45), (1.80, 0.42), (2.40, 0.31), (2.95, 0.22), (3.40, 0.17), (3.60, 0.15)],
            "wt": [(1.30, 0.235), (1.40, 0.25), (1.80, 0.255), (2.40, 0.22), (2.95, 0.16), (3.40, 0.09), (3.60, 0.05)],
            "wb": [(1.30, 0.09), (1.40, 0.10), (1.80, 0.11), (2.40, 0.13), (2.95, 0.13), (3.40, 0.09), (3.60, 0.05)],
            "ht": [(1.30, 0.12), (1.40, 0.135), (1.80, 0.14), (2.40, 0.115), (2.95, 0.08), (3.40, 0.05), (3.60, 0.035)],
            "hb": [(1.30, 0.19), (1.40, 0.21), (1.80, 0.23), (2.40, 0.19), (2.95, 0.13), (3.40, 0.09), (3.60, 0.07)],
            "n": [(1.30, 5.0), (1.8, 3.6), (3.6, 2.4)],
        },
        "pod_z": (1.30, 3.60),
        "mirror": ((0.47, 0.74, 1.22), (0.30, 0.64, 1.28)),
        "floor": {
            "half": [
                (0.0, 0.33),
                (0.30, 0.40),
                (0.56, 0.78),
                (0.79, 1.08),
                (0.81, 2.90),
                (0.72, 3.14),
                (0.57, 3.28),
                (0.55, 3.95),
                (0.50, 4.10),
            ],
            "edge": (1.08, 2.88, 0.80),
            "diffuser": (3.45, 4.22, 0.5, 0.32),
        },
        "intake": (0.07, 0.80, 0.935, 1.93),
        "tcam": (0, 0.985, 2.06),
        "fin": [(2.25, 0.86), (2.55, 0.955), (3.95, 0.64), (3.95, 0.52), (2.35, 0.80)],
        "tail": (0, 0.335, 4.165),
        "exhausts": [(0, 0.47, 4.16, 0.042, 0.14)],
        "halo": (0.98, 0.64, 0.92, 1.9, 0.27, 0.70),
        "steer": (0, 0.64, 1.16),
        "suit": (0, 0.56, 1.52),
        "wheel_y": 0.36,
        "susp": {
            "wishbones": [
                ((0.17, 0.43, -0.12), (0.17, 0.45, 0.25), (0.66, 0.49, 0.0)),
                ((0.15, 0.22, -0.16), (0.15, 0.21, 0.34), (0.68, 0.21, 0.02)),
                ((0.20, 0.46, 3.28), (0.18, 0.46, 3.72), (0.62, 0.52, 3.60)),
                ((0.21, 0.17, 3.22), (0.21, 0.19, 3.76), (0.64, 0.19, 3.60)),
            ],
            "rods": [((0.63, 0.22, 0.03), (0.19, 0.50, 0.12), 0.012), ((0.20, 0.30, 3.60), (0.60, 0.34, 3.60), 0.02)],
            "drums": [(0.0, 0.52, 0.655, 0.17), (3.6, 0.48, 0.58, 0.18)],
        },
        "wings": wings,
        "extras": lambda d, body: extras(d, body),
        "liv": default_liv(),
        "anchors": lambda body: std_anchors(
            body,
            [
                {"pos": (-0.80, 0.36, 0.0), "r": 0.36, "w": 0.305, "tyre": "t18"},
                {"pos": (0.80, 0.36, 0.0), "r": 0.36, "w": 0.305, "tyre": "t18"},
                {"pos": (-0.775, 0.365, 3.6), "r": 0.365, "w": 0.405, "tyre": "t18"},
                {"pos": (0.775, 0.365, 3.6), "r": 0.365, "w": 0.405, "tyre": "t18"},
            ],
            (0, 0.82, 1.47),
            -0.30,
            (0.115, 0.70, 2.55),
            (0, 0.47, 4.17),
            (0, 0.7, 3.0),
            [(-0.53, 0.99, 4.45), (0.53, 0.99, 4.45)],
            {"pos": (0, 0.05, 1.9), "size": (1.5, 3.4)},
        ),
    }
    return open_wheeler("mod", S)


def _wheels(fx, fr, fw, rx, rr, rw, rz, tyre):
    """Four wheel anchors from front/rear track, radius, width and wheelbase."""
    return [
        {"pos": (-fx, fr, 0.0), "r": fr, "w": fw, "tyre": tyre},
        {"pos": (fx, fr, 0.0), "r": fr, "w": fw, "tyre": tyre},
        {"pos": (-rx, rr, rz), "r": rr, "w": rw, "tyre": tyre},
        {"pos": (rx, rr, rz), "r": rr, "w": rw, "tyre": tyre},
    ]


def _plates(d, group, slot, specs):
    """Wing endplates on both sides (or one centred plate when x is 0)."""
    for poly, x in specs:
        for s in (1, -1) if x != 0 else (1,):
            d.add(group, slot, P.endplate(poly, s * x, 0.012))


# ---------------------------------------------------------------------------
# HYBRID (2017-21: shark fin, bargeboards, high narrow nose) -> arrow, falcon, vortex, viper
# ---------------------------------------------------------------------------
def hybrid():
    def wings(d):
        fw_elements(
            d,
            [
                (0.07, -1.07, 0.30, 2, 0.03, 0.08, 1.0, "Accent", True),
                (0.10, -0.83, 0.17, 14, 0.12, 0.10, 0.9, "Accent", False),
                (0.14, -0.70, 0.13, 26, 0.16, 0.10, 0.8, "Accent", False),
                (0.19, -0.60, 0.11, 38, 0.17, 0.10, 0.7, "Secondary", False),
            ],
            0.93,
            0.12,
            [(-1.10, 0.02), (-0.42, 0.02), (-0.40, 0.20), (-0.45, 0.34), (-0.62, 0.36), (-0.98, 0.30), (-1.10, 0.14)],
            sweep_rise=(0.35, 0.90),
        )
        # cascade winglets + nose pylons
        for s in (1, -1):
            x0, x1 = (0.70, 0.90) if s > 0 else (-0.90, -0.70)
            d.add(
                "FrontWing",
                "Accent",
                P.wing_element(x0, x1, lambda x: {"y": 0.29, "z": -0.86, "c": 0.09, "a": 12}, stations=6, thick=0.08),
            )
        _plates(d, "FrontWing", "Carbon", [([(-0.97, 0.09), (-0.62, 0.09), (-0.58, 0.27), (-0.86, 0.22)], 0.065)])
        rw_elements(
            d,
            [(0.82, 3.98, 0.34, 7, "Accent"), (0.93, 4.26, 0.20, 30, "Secondary")],
            0.475,
            [(3.90, 0.36), (4.48, 0.36), (4.48, 1.01), (3.95, 1.01)],
            droop=0.0,
            var="rwA",
        )
        d.var(
            "rwA", "RearWing", "Carbon", P.endplate([(3.95, 0.40), (4.12, 0.40), (4.20, 0.83), (4.03, 0.83)], 0, 0.02)
        )
        rw_elements(
            d,
            [(0.84, 3.99, 0.30, 5, "Accent"), (0.94, 4.24, 0.17, 22, "Secondary")],
            0.475,
            [(3.92, 0.42), (4.46, 0.42)] + P.arc_pts(4.36, 0.90, 0.10, -30, 90, 6)[1:] + [(4.0, 1.0), (3.92, 0.9)],
            droop=0.07,
            var="rwB",
        )
        swan_necks(d, "rwB", 0.08, 3.98, 0.40, 4.12, 0.84)
        d.add(
            "RearWing",
            "Carbon",
            P.wing_element(-0.40, 0.40, lambda x: {"y": 0.45, "z": 4.00, "c": 0.18, "a": 8}, stations=10),
        )
        d.add(
            "RearWing",
            "Carbon",
            P.wing_element(-0.16, 0.16, lambda x: {"y": 0.52, "z": 4.12, "c": 0.08, "a": 20}, stations=6),
        )

    def extras(d, body):
        # bargeboards + turning vanes
        _plates(
            d,
            "Body",
            "Carbon",
            [
                ([(0.55, 0.07), (1.22, 0.07), (1.28, 0.32), (1.05, 0.37), (0.72, 0.22)], 0.42),
                ([(0.78, 0.07), (1.30, 0.07), (1.28, 0.27), (0.98, 0.25)], 0.56),
                ([(0.95, 0.07), (1.32, 0.07), (1.31, 0.22), (1.08, 0.2)], 0.66),
                ([(-0.25, 0.16), (0.45, 0.13), (0.42, 0.30), (-0.18, 0.33)], 0.11),
            ],
        )
        # T-wing
        d.add(
            "RearWing",
            "Carbon",
            P.wing_element(-0.2, 0.2, lambda x: {"y": 0.74, "z": 3.86, "c": 0.07, "a": 10}, stations=6),
        )

    S = {
        "body": {
            "cy": [
                (-0.98, 0.17),
                (-0.90, 0.19),
                (-0.65, 0.25),
                (-0.25, 0.35),
                (0.15, 0.44),
                (0.55, 0.47),
                (0.95, 0.46),
                (1.25, 0.46),
                (1.75, 0.46),
                (1.97, 0.52),
                (2.30, 0.52),
                (2.90, 0.46),
                (3.45, 0.40),
                (3.95, 0.36),
                (4.15, 0.35),
            ],
            "wt": [
                (-0.98, 0.045),
                (-0.90, 0.075),
                (-0.65, 0.095),
                (-0.25, 0.12),
                (0.15, 0.15),
                (0.55, 0.20),
                (0.95, 0.25),
                (1.25, 0.29),
                (1.75, 0.30),
                (1.97, 0.09),
                (2.30, 0.085),
                (2.90, 0.08),
                (3.45, 0.07),
                (3.95, 0.05),
                (4.15, 0.04),
            ],
            "wb": [
                (-0.98, 0.05),
                (-0.90, 0.075),
                (-0.65, 0.09),
                (-0.25, 0.11),
                (0.15, 0.15),
                (0.55, 0.22),
                (0.95, 0.29),
                (1.25, 0.32),
                (1.75, 0.33),
                (1.97, 0.33),
                (2.30, 0.31),
                (2.90, 0.23),
                (3.45, 0.15),
                (3.95, 0.08),
                (4.15, 0.05),
            ],
            "ht": [
                (-0.98, 0.035),
                (-0.90, 0.05),
                (-0.65, 0.07),
                (-0.25, 0.09),
                (0.15, 0.11),
                (0.55, 0.15),
                (0.95, 0.22),
                (1.25, 0.27),
                (1.75, 0.27),
                (1.97, 0.47),
                (2.30, 0.40),
                (2.90, 0.28),
                (3.45, 0.18),
                (3.95, 0.09),
                (4.15, 0.05),
            ],
            "hb": [
                (-0.98, 0.035),
                (-0.90, 0.05),
                (-0.65, 0.06),
                (-0.25, 0.07),
                (0.15, 0.10),
                (0.55, 0.20),
                (0.95, 0.31),
                (1.25, 0.34),
                (1.75, 0.34),
                (1.97, 0.40),
                (2.30, 0.40),
                (2.90, 0.34),
                (3.45, 0.28),
                (3.95, 0.20),
                (4.15, 0.08),
            ],
            "n": [(-0.98, 2.2), (-0.5, 2.5), (0.95, 2.8), (1.75, 3.0), (1.97, 2.1), (2.9, 2.3), (4.15, 2.4)],
            "dip": [(-1, 0), (1.02, 0), (1.12, 0.22), (1.80, 0.22), (1.90, 0), (5, 0)],
            "dipw": [(-1, 0.2), (5, 0.2)],
        },
        "body_z": (-0.98, 4.15),
        "dense": [(-0.98, -0.85, 0.02), (0.95, 1.2, 0.02), (1.75, 2.05, 0.02), (4.0, 4.15, 0.025)],
        "cockpit": (0.19, 1.06, 1.88, 0.50),
        "tip_z": -0.78,
        "pod": {
            "cx": [(1.35, 0.52), (1.45, 0.53), (1.80, 0.50), (2.40, 0.40), (2.90, 0.30), (3.30, 0.22)],
            "cy": [(1.35, 0.48), (1.45, 0.48), (1.80, 0.45), (2.40, 0.38), (2.90, 0.30), (3.30, 0.24)],
            "wt": [(1.35, 0.18), (1.45, 0.20), (1.80, 0.20), (2.40, 0.15), (2.90, 0.10), (3.30, 0.06)],
            "wb": [(1.35, 0.08), (1.45, 0.09), (1.80, 0.09), (2.40, 0.08), (2.90, 0.07), (3.30, 0.05)],
            "ht": [(1.35, 0.12), (1.45, 0.14), (1.80, 0.15), (2.40, 0.12), (2.90, 0.08), (3.30, 0.05)],
            "hb": [(1.35, 0.22), (1.45, 0.25), (1.80, 0.28), (2.40, 0.26), (2.90, 0.20), (3.30, 0.15)],
            "n": [(1.35, 3.2), (1.8, 2.9), (3.3, 2.4)],
        },
        "pod_z": (1.35, 3.30),
        "mirror": ((0.46, 0.74, 1.15), (0.28, 0.63, 1.22)),
        "floor": {
            "half": [
                (0.0, 0.45),
                (0.45, 0.50),
                (0.62, 0.90),
                (0.80, 1.20),
                (0.82, 3.00),
                (0.62, 3.25),
                (0.55, 3.95),
                (0.50, 4.10),
            ],
            "diffuser": (3.45, 4.15, 0.5, 0.36),
        },
        "intake": (0.075, 0.82, 0.97, 1.93),
        "tcam": (0, 1.0, 2.05),
        "fin": [(2.15, 0.93), (2.40, 1.0), (4.05, 0.93), (4.05, 0.55), (2.25, 0.85)],
        "fin_always": True,
        "tail": (0, 0.345, 4.165),
        "exhausts": [(0, 0.45, 4.16, 0.045, 0.12)],
        "halo": (0.98, 0.66, 0.93, 1.9, 0.27, 0.72),
        "steer": (0, 0.65, 1.16),
        "suit": (0, 0.57, 1.52),
        "wheel_y": 0.33,
        "susp": {
            "wishbones": [
                ((0.12, 0.47, -0.10), (0.12, 0.49, 0.25), (0.62, 0.50, 0.0)),
                ((0.12, 0.30, -0.15), (0.14, 0.28, 0.30), (0.66, 0.20, 0.02)),
                ((0.20, 0.46, 3.28), (0.18, 0.46, 3.72), (0.62, 0.50, 3.60)),
                ((0.21, 0.17, 3.22), (0.21, 0.19, 3.76), (0.64, 0.17, 3.60)),
            ],
            "rods": [((0.62, 0.21, 0.02), (0.15, 0.53, 0.15), 0.012), ((0.20, 0.30, 3.60), (0.60, 0.32, 3.60), 0.02)],
            "drums": [(0.0, 0.52, 0.655, 0.15), (3.6, 0.48, 0.58, 0.16)],
        },
        "wings": wings,
        "extras": extras,
        "liv": default_liv(
            flash=[(1.35, 0.42), (1.35, 0.52), (2.2, 0.45), (3.1, 0.32), (3.1, 0.29), (2.2, 0.40)],
            circuit=[(1.37, 0.49), (2.3, 0.42), (3.0, 0.33), (3.0, 0.315), (2.3, 0.405), (1.37, 0.475)],
            flames=[
                flame_poly(1.35, 2.8, 0.46, 0.18, 5, 1.0),
                flame_poly(1.35, 2.4, 0.46, 0.13, 4, 1.4),
                flame_poly(1.35, 2.0, 0.46, 0.08, 3, 1.9),
            ],
            pod_cx=0.52,
            pod_top_y=0.55,
            pchev_z=1.6,
            check_ymin=0.64,
            split_y=0.55,
            chev_z=-0.55,
            chev_k=1.5,
            cover_side=[(2.1, 0.64), (2.1, 0.74), (3.6, 0.52), (3.6, 0.46)],
        ),
        "anchors": lambda body: std_anchors(
            body,
            _wheels(0.80, 0.33, 0.305, 0.78, 0.33, 0.405, 3.6, "t13"),
            (0, 0.83, 1.47),
            -0.2,
            (0.105, 0.70, 2.6),
            (0, 0.45, 4.17),
            (0, 0.7, 3.0),
            [(-0.49, 1.01, 4.45), (0.49, 1.01, 4.45)],
            {"pos": (0, 0.05, 1.9), "size": (1.5, 3.4)},
        ),
    }
    return open_wheeler("hyb", S)


# ---------------------------------------------------------------------------
# V10 (2000s: high nose, grooved tyres, tall rear wing) -> apex, aurora
# ---------------------------------------------------------------------------
def v10():
    def wings(d):
        fw_elements(
            d,
            [
                (0.07, -1.02, 0.30, 4, 0.05, 0.03, 1.0, "Accent", True),
                (0.12, -0.78, 0.18, 22, 0.08, 0.03, 0.9, "Secondary", False),
            ],
            0.84,
            0.16,
            [(-1.05, 0.02), (-0.55, 0.02), (-0.55, 0.26), (-1.0, 0.26)],
            sweep_rise=(0.5, 0.95),
        )
        _plates(d, "FrontWing", "Carbon", [([(-0.98, 0.09), (-0.70, 0.09), (-0.66, 0.31), (-0.90, 0.31)], 0.07)])
        rw_elements(
            d,
            [(0.76, 3.70, 0.30, 10, "Accent"), (0.88, 3.73, 0.26, 12, "Accent"), (0.99, 3.96, 0.17, 30, "Secondary")],
            0.50,
            [(3.62, 0.38), (4.16, 0.38), (4.16, 1.08), (3.65, 1.08)],
            droop=0.0,
            var="rwA",
        )
        rw_elements(
            d,
            [(0.80, 3.70, 0.32, 7, "Accent"), (0.90, 3.98, 0.17, 24, "Secondary")],
            0.50,
            [(3.62, 0.38), (4.18, 0.38), (4.18, 0.99), (3.65, 0.99)],
            droop=0.0,
            var="rwB",
        )
        d.add(
            "RearWing",
            "Carbon",
            P.wing_element(-0.42, 0.42, lambda x: {"y": 0.45, "z": 3.72, "c": 0.2, "a": 8}, stations=10),
        )
        _plates(d, "RearWing", "Carbon", [([(3.70, 0.40), (3.90, 0.40), (3.95, 0.78), (3.75, 0.78)], 0.06)])

    def extras(d, body):
        _plates(d, "Body", "Carbon", [([(0.62, 0.07), (1.22, 0.07), (1.20, 0.40), (1.02, 0.42), (0.80, 0.22)], 0.44)])
        for s, g in ((1, "RightPod"), (-1, "LeftPod")):
            d.add(g, "Carbon", P.endplate([(2.82, 0.28), (3.08, 0.28), (3.08, 0.47), (2.92, 0.44)], s * 0.56, 0.012))
            wx = (0.14, 0.30) if s > 0 else (-0.30, -0.14)
            d.add(
                "Body",
                "Carbon",
                P.wing_element(wx[0], wx[1], lambda x: {"y": 0.84, "z": 2.28, "c": 0.08, "a": 12}, stations=6),
            )
            ex = geo.tube(
                geo.bezier([(s * 0.38, 0.40, 2.80), (s * 0.40, 0.46, 2.92), (s * 0.40, 0.47, 3.02)], 6), 0.04, N=12
            )
            d.add(g, "Metal", ex)

    S = {
        "body": {
            "cy": [
                (-0.92, 0.30),
                (-0.85, 0.31),
                (-0.55, 0.36),
                (-0.15, 0.44),
                (0.30, 0.49),
                (0.80, 0.48),
                (1.10, 0.48),
                (1.75, 0.48),
                (1.95, 0.52),
                (2.25, 0.50),
                (2.80, 0.45),
                (3.30, 0.40),
                (3.75, 0.36),
                (3.95, 0.35),
            ],
            "wt": [
                (-0.92, 0.05),
                (-0.85, 0.085),
                (-0.55, 0.11),
                (-0.15, 0.14),
                (0.30, 0.18),
                (0.80, 0.24),
                (1.10, 0.28),
                (1.75, 0.29),
                (1.95, 0.13),
                (2.25, 0.12),
                (2.80, 0.10),
                (3.30, 0.08),
                (3.75, 0.05),
                (3.95, 0.04),
            ],
            "wb": [
                (-0.92, 0.06),
                (-0.85, 0.09),
                (-0.55, 0.11),
                (-0.15, 0.13),
                (0.30, 0.19),
                (0.80, 0.28),
                (1.10, 0.31),
                (1.75, 0.32),
                (1.95, 0.32),
                (2.25, 0.30),
                (2.80, 0.22),
                (3.30, 0.14),
                (3.75, 0.08),
                (3.95, 0.05),
            ],
            "ht": [
                (-0.92, 0.04),
                (-0.85, 0.06),
                (-0.55, 0.08),
                (-0.15, 0.10),
                (0.30, 0.13),
                (0.80, 0.22),
                (1.10, 0.26),
                (1.75, 0.26),
                (1.95, 0.46),
                (2.25, 0.38),
                (2.80, 0.25),
                (3.30, 0.16),
                (3.75, 0.08),
                (3.95, 0.05),
            ],
            "hb": [
                (-0.92, 0.04),
                (-0.85, 0.06),
                (-0.55, 0.07),
                (-0.15, 0.09),
                (0.30, 0.16),
                (0.80, 0.32),
                (1.10, 0.34),
                (1.75, 0.34),
                (1.95, 0.38),
                (2.25, 0.36),
                (2.80, 0.31),
                (3.30, 0.27),
                (3.75, 0.20),
                (3.95, 0.08),
            ],
            "n": [(-0.92, 2.3), (0.8, 2.8), (1.75, 3.0), (1.95, 2.2), (3.95, 2.4)],
            "dip": [(-1, 0), (1.02, 0), (1.12, 0.24), (1.78, 0.24), (1.88, 0), (5, 0)],
            "dipw": [(-1, 0.2), (5, 0.2)],
        },
        "body_z": (-0.92, 3.95),
        "dense": [(-0.92, -0.8, 0.02), (0.95, 1.2, 0.02), (1.72, 2.02, 0.02), (3.8, 3.95, 0.025)],
        "cockpit": (0.19, 1.06, 1.86, 0.48),
        "tip_z": -0.72,
        "pod": {
            "cx": [(1.20, 0.50), (1.30, 0.52), (1.80, 0.52), (2.40, 0.45), (2.90, 0.33), (3.25, 0.22)],
            "cy": [(1.20, 0.38), (1.30, 0.38), (1.80, 0.37), (2.40, 0.33), (2.90, 0.27), (3.25, 0.22)],
            "wt": [(1.20, 0.20), (1.30, 0.22), (1.80, 0.22), (2.40, 0.19), (2.90, 0.13), (3.25, 0.07)],
            "wb": [(1.20, 0.16), (1.30, 0.18), (1.80, 0.17), (2.40, 0.15), (2.90, 0.11), (3.25, 0.06)],
            "ht": [(1.20, 0.15), (1.30, 0.17), (1.80, 0.17), (2.40, 0.13), (2.90, 0.09), (3.25, 0.05)],
            "hb": [(1.20, 0.20), (1.30, 0.22), (1.80, 0.22), (2.40, 0.20), (2.90, 0.15), (3.25, 0.12)],
            "n": [(1.20, 3.2), (1.8, 2.9), (3.25, 2.4)],
        },
        "pod_z": (1.20, 3.25),
        "mirror": ((0.42, 0.66, 1.10), (0.30, 0.58, 1.15)),
        "floor": {
            "half": [
                (0.0, 0.50),
                (0.30, 0.55),
                (0.58, 0.80),
                (0.72, 1.00),
                (0.72, 2.90),
                (0.55, 3.10),
                (0.50, 3.80),
                (0.45, 3.90),
            ],
            "diffuser": (3.25, 3.95, 0.45, 0.30),
        },
        "intake": (0.085, 0.84, 1.0, 1.92),
        "tcam": (0, 1.0, 2.05),
        "tail": (0, 0.345, 3.965),
        "halo": None,
        "steer": (0, 0.64, 1.14),
        "suit": (0, 0.58, 1.5),
        "wheel_y": 0.33,
        "susp": {
            "wishbones": [
                ((0.10, 0.46, -0.10), (0.10, 0.48, 0.25), (0.60, 0.48, 0.0)),
                ((0.10, 0.33, -0.15), (0.10, 0.31, 0.30), (0.62, 0.20, 0.02)),
                ((0.18, 0.45, 3.15), (0.16, 0.45, 3.60), (0.58, 0.50, 3.45)),
                ((0.20, 0.18, 3.10), (0.20, 0.20, 3.60), (0.60, 0.18, 3.45)),
            ],
            "rods": [((0.58, 0.20, 0.02), (0.12, 0.50, 0.15), 0.012), ((0.20, 0.30, 3.45), (0.56, 0.32, 3.45), 0.02)],
            "drums": [(0.0, 0.46, 0.57, 0.15), (3.45, 0.44, 0.52, 0.15)],
        },
        "wings": wings,
        "extras": extras,
        "liv": default_liv(
            flash=[(1.22, 0.34), (1.22, 0.45), (2.2, 0.40), (3.1, 0.30), (3.1, 0.27), (2.2, 0.35)],
            circuit=[(1.24, 0.41), (2.3, 0.37), (3.0, 0.30), (3.0, 0.285), (2.3, 0.355), (1.24, 0.395)],
            flames=[
                flame_poly(1.22, 2.7, 0.38, 0.22, 5, 1.0),
                flame_poly(1.22, 2.3, 0.38, 0.16, 4, 1.4),
                flame_poly(1.22, 1.9, 0.38, 0.10, 3, 1.9),
            ],
            pod_cx=0.52,
            pod_top_y=0.46,
            pchev_z=1.45,
            check_ymin=0.62,
            split_y=0.52,
            split_front=0.36,
            chev_z=-0.5,
            chev_k=1.3,
            cover_z=(2.05, 3.4),
            cover_side=[(2.1, 0.62), (2.1, 0.72), (3.4, 0.5), (3.4, 0.45)],
            cockpit_ex=P.box_region(x0=-0.215, x1=0.215, z0=1.04, z1=1.88, y0=0.46),
        ),
        "anchors": lambda body: std_anchors(
            body,
            _wheels(0.72, 0.33, 0.30, 0.70, 0.33, 0.38, 3.45, "t13g"),
            (0, 0.85, 1.43),
            -0.3,
            (0.11, 0.66, 2.55),
            (0, 0.40, 3.97),
            (0, 0.7, 2.9),
            [(-0.51, 1.08, 4.1), (0.51, 1.08, 4.1)],
            {"pos": (0, 0.05, 1.8), "size": (1.35, 3.1)},
        ),
    }
    return open_wheeler("v10", S)


# ---------------------------------------------------------------------------
# RETRO 70s (tall periscope airbox, wide nose wing, fat rear tyres) -> retro70
# ---------------------------------------------------------------------------
def r70():
    def wings(d):
        fw_elements(
            d,
            [
                (0.10, -1.00, 0.32, 6, 0.0, 0.0, 1.0, "Accent", True),
                (0.155, -0.74, 0.12, 20, 0.0, 0.0, 1.0, "Secondary", False),
            ],
            0.78,
            0.30,
            [(-1.02, 0.05), (-0.62, 0.05), (-0.62, 0.23), (-0.95, 0.21)],
        )
        rw_elements(
            d,
            [(1.00, 3.72, 0.42, 10, "Accent")],
            0.50,
            [(3.66, 0.86), (4.22, 0.86), (4.22, 1.13), (3.70, 1.13)],
            droop=0.0,
        )
        d.add("RearWing", "Carbon", P.endplate([(3.55, 0.36), (3.80, 0.36), (3.95, 0.99), (3.74, 0.99)], 0, 0.03))

    def extras(d, body):
        ab = Track(
            {
                # the huge mid-70s "teapot" airbox towering over the driver
                "cy": [(1.76, 0.86), (1.95, 0.90), (2.45, 0.72), (2.95, 0.50)],
                "wt": [(1.76, 0.19), (1.95, 0.22), (2.45, 0.15), (2.95, 0.06)],
                "wb": [(1.76, 0.15), (1.95, 0.18), (2.45, 0.20), (2.95, 0.15)],
                "ht": [(1.76, 0.30), (1.95, 0.34), (2.45, 0.20), (2.95, 0.06)],
                "hb": [(1.76, 0.30), (1.95, 0.36), (2.45, 0.28), (2.95, 0.14)],
                "n": [(1.76, 3.4), (2.95, 2.4)],
            }
        )
        rings = [superellipse_section(z, ab(z), 36) for z in P.zsamples(1.76, 2.95, 0.05, dense=[(1.76, 1.86, 0.02)])]
        sd, cp = P.loft_obj(rings, True, True, "Dark", "")
        cp["Dark"] = recess(cp["Dark"], 0.06)
        d.add("Body", "Primary", sd + cp[""])
        d.add("Body", "Dark", cp["Dark"])
        d.add("Body", "Glass", geo.plate(geo.rounded_rect(-0.21, 0.50, 0.21, 0.66, 0.05, 3), "xy", 0.98, 0.01))
        # exposed engine + exhausts + gearbox
        d.add("Body", "Metal", geo.box((0, 0.30, 3.05), (0.36, 0.22, 0.55)))
        d.add("Body", "Dark", geo.box((0, 0.26, 3.62), (0.26, 0.2, 0.42)))
        for s in (1, -1):
            d.add(
                "Body",
                "Metal",
                geo.tube(
                    geo.bezier([(s * 0.14, 0.30, 2.85), (s * 0.24, 0.30, 3.25), (s * 0.22, 0.40, 3.78)], 8), 0.035, N=10
                ),
            )

    S = {
        "body": {
            "cy": [
                (-0.95, 0.18),
                (-0.80, 0.20),
                (-0.50, 0.25),
                (-0.10, 0.31),
                (0.40, 0.35),
                (0.90, 0.36),
                (1.15, 0.36),
                (1.80, 0.36),
                (2.00, 0.38),
                (2.50, 0.36),
                (3.00, 0.33),
                (3.50, 0.30),
                (3.80, 0.30),
            ],
            "wt": [
                (-0.95, 0.30),
                (-0.80, 0.28),
                (-0.50, 0.20),
                (-0.10, 0.16),
                (0.40, 0.19),
                (0.90, 0.24),
                (1.15, 0.27),
                (1.80, 0.27),
                (2.00, 0.25),
                (2.50, 0.20),
                (3.00, 0.14),
                (3.50, 0.10),
                (3.80, 0.06),
            ],
            "wb": [
                (-0.95, 0.32),
                (-0.80, 0.30),
                (-0.50, 0.22),
                (-0.10, 0.18),
                (0.40, 0.22),
                (0.90, 0.28),
                (1.15, 0.30),
                (1.80, 0.30),
                (2.00, 0.30),
                (2.50, 0.26),
                (3.00, 0.20),
                (3.50, 0.12),
                (3.80, 0.07),
            ],
            "ht": [
                (-0.95, 0.03),
                (-0.80, 0.06),
                (-0.50, 0.09),
                (-0.10, 0.11),
                (0.40, 0.14),
                (0.90, 0.20),
                (1.15, 0.22),
                (1.80, 0.22),
                (2.00, 0.20),
                (2.50, 0.16),
                (3.00, 0.12),
                (3.50, 0.08),
                (3.80, 0.05),
            ],
            "hb": [
                (-0.95, 0.04),
                (-0.80, 0.06),
                (-0.50, 0.09),
                (-0.10, 0.12),
                (0.40, 0.20),
                (0.90, 0.24),
                (1.15, 0.24),
                (1.80, 0.24),
                (2.00, 0.26),
                (2.50, 0.24),
                (3.00, 0.21),
                (3.50, 0.18),
                (3.80, 0.07),
            ],
            "n": [(-0.95, 3.5), (-0.5, 2.8), (0.9, 2.8), (3.8, 2.6)],
            "dip": [(-1, 0), (1.05, 0), (1.14, 0.15), (1.78, 0.15), (1.86, 0), (5, 0)],
            "dipw": [(-1, 0.19), (5, 0.19)],
        },
        "body_z": (-0.95, 3.80),
        "dense": [(-0.95, -0.8, 0.02), (1.0, 1.2, 0.02), (1.72, 1.95, 0.02)],
        "cockpit": (0.18, 1.08, 1.84, 0.40),
        "tip_z": -0.82,
        "pod": {
            "cx": [(1.20, 0.50), (1.30, 0.52), (2.30, 0.52), (2.70, 0.44)],
            "cy": [(1.20, 0.28), (1.30, 0.28), (2.30, 0.28), (2.70, 0.26)],
            "wt": [(1.20, 0.20), (1.30, 0.22), (2.30, 0.22), (2.70, 0.16)],
            "wb": [(1.20, 0.20), (1.30, 0.22), (2.30, 0.22), (2.70, 0.16)],
            "ht": [(1.20, 0.12), (1.30, 0.14), (2.30, 0.14), (2.70, 0.10)],
            "hb": [(1.20, 0.14), (1.30, 0.15), (2.30, 0.15), (2.70, 0.12)],
            "n": [(1.20, 5.0), (2.70, 4.0)],
        },
        "pod_z": (1.20, 2.70),
        "mirror": ((0.34, 0.60, 0.95), (0.22, 0.55, 1.0)),
        "floor": {"half": [(0.0, 0.55), (0.70, 1.10), (0.72, 2.70), (0.30, 2.80)]},
        "tail": (0, 0.30, 3.815),
        "halo": None,
        "steer": (0, 0.55, 1.15),
        "suit": (0, 0.47, 1.5),
        "wheel_y": 0.30,
        "susp": {
            "wishbones": [
                ((0.14, 0.38, -0.08), (0.14, 0.40, 0.22), (0.60, 0.40, 0.0)),
                ((0.14, 0.20, -0.12), (0.14, 0.19, 0.28), (0.62, 0.18, 0.02)),
                ((0.18, 0.42, 3.05), (0.16, 0.42, 3.50), (0.48, 0.46, 3.30)),
                ((0.20, 0.16, 3.00), (0.20, 0.18, 3.50), (0.50, 0.16, 3.30)),
            ],
            "rods": [((0.20, 0.30, 3.30), (0.46, 0.34, 3.30), 0.025)],
            "drums": [(0.0, 0.46, 0.59, 0.14), (3.3, 0.34, 0.44, 0.19)],
        },
        "wings": wings,
        "extras": extras,
        "liv": default_liv(
            flash=[(1.20, 0.22), (1.20, 0.34), (2.70, 0.30), (2.70, 0.24)],
            circuit=[(1.22, 0.31), (2.65, 0.30), (2.65, 0.285), (1.22, 0.295)],
            flames=[
                flame_poly(1.20, 2.5, 0.28, 0.2, 5, 1.0),
                flame_poly(1.20, 2.1, 0.28, 0.14, 4, 1.4),
                flame_poly(1.20, 1.8, 0.28, 0.08, 3, 1.9),
            ],
            outer_x=0.55,
            pod_cx=0.52,
            pod_top_y=0.36,
            pchev_z=1.35,
            pchev_k=0.8,
            check_ymin=0.48,
            check_w=0.2,
            cover_z=(2.9, 3.4),
            cover_side=[(2.0, 0.45), (2.0, 0.53), (3.4, 0.40), (3.4, 0.35)],
            split_y=0.42,
            split_front=0.2,
            chev_z=-0.5,
            chev_k=1.0,
            stripe_w=0.06,
            nose_end=0.4,
            cockpit_ex=P.box_region(x0=-0.2, x1=0.2, z0=1.05, z1=1.86, y0=0.38),
        ),
        "anchors": lambda body: std_anchors(
            body,
            _wheels(0.72, 0.29, 0.26, 0.72, 0.36, 0.55, 3.3, "t13"),
            (0, 0.72, 1.5),
            -0.1,
            (0.105, 0.47, 2.5),
            (0, 0.40, 3.80),
            (0, 0.5, 3.0),
            [(-0.51, 1.13, 4.2), (0.51, 1.13, 4.2)],
            {"pos": (0, 0.05, 1.7), "size": (1.4, 3.0)},
        ),
    }
    return open_wheeler("r70", S)


# ---------------------------------------------------------------------------
# RETRO TURBO (late 80s: low wedge, long flat pods, big square endplates) -> retro90
# ---------------------------------------------------------------------------
def r88():
    def wings(d):
        fw_elements(
            d,
            [
                (0.08, -1.05, 0.30, 4, 0.0, 0.0, 1.0, "Accent", True),
                (0.13, -0.80, 0.16, 20, 0.02, 0.0, 1.0, "Secondary", False),
            ],
            0.86,
            0.15,
            [(-1.10, 0.03), (-0.62, 0.03), (-0.62, 0.24), (-1.05, 0.24)],
        )
        rw_elements(
            d,
            [(0.82, 3.85, 0.32, 8, "Accent"), (0.93, 4.10, 0.18, 28, "Secondary")],
            0.46,
            [(3.72, 0.30), (4.35, 0.30), (4.35, 1.00), (3.78, 1.00)],
            droop=0.0,
        )
        d.add(
            "RearWing",
            "Carbon",
            P.wing_element(-0.4, 0.4, lambda x: {"y": 0.42, "z": 3.95, "c": 0.18, "a": 8}, stations=10),
        )

    def extras(d, body):
        d.add("Body", "Glass", geo.plate(geo.rounded_rect(-0.24, 0.52, 0.24, 0.70, 0.06, 3), "xy", 0.96, 0.01))
        d.add(
            "Body",
            "Carbon",
            geo.tube(geo.bezier([(-0.16, 0.60, 1.88), (0, 0.92, 1.9), (0.16, 0.60, 1.88)], 10), 0.03, N=10),
        )

    S = {
        "body": {
            "cy": [
                (-0.98, 0.17),
                (-0.90, 0.18),
                (-0.50, 0.25),
                (0.00, 0.32),
                (0.50, 0.37),
                (0.95, 0.38),
                (1.20, 0.38),
                (1.75, 0.38),
                (1.95, 0.40),
                (2.50, 0.38),
                (3.10, 0.35),
                (3.60, 0.32),
                (4.00, 0.31),
            ],
            "wt": [
                (-0.98, 0.07),
                (-0.90, 0.12),
                (-0.50, 0.15),
                (0.00, 0.17),
                (0.50, 0.21),
                (0.95, 0.27),
                (1.20, 0.30),
                (1.75, 0.30),
                (1.95, 0.24),
                (2.50, 0.20),
                (3.10, 0.14),
                (3.60, 0.09),
                (4.00, 0.05),
            ],
            "wb": [
                (-0.98, 0.08),
                (-0.90, 0.13),
                (-0.50, 0.17),
                (0.00, 0.20),
                (0.50, 0.25),
                (0.95, 0.31),
                (1.20, 0.33),
                (1.75, 0.33),
                (1.95, 0.33),
                (2.50, 0.30),
                (3.10, 0.22),
                (3.60, 0.13),
                (4.00, 0.06),
            ],
            "ht": [
                (-0.98, 0.03),
                (-0.90, 0.05),
                (-0.50, 0.08),
                (0.00, 0.11),
                (0.50, 0.15),
                (0.95, 0.22),
                (1.20, 0.25),
                (1.75, 0.25),
                (1.95, 0.26),
                (2.50, 0.20),
                (3.10, 0.13),
                (3.60, 0.08),
                (4.00, 0.05),
            ],
            "hb": [
                (-0.98, 0.04),
                (-0.90, 0.05),
                (-0.50, 0.09),
                (0.00, 0.13),
                (0.50, 0.20),
                (0.95, 0.26),
                (1.20, 0.27),
                (1.75, 0.27),
                (1.95, 0.29),
                (2.50, 0.27),
                (3.10, 0.24),
                (3.60, 0.20),
                (4.00, 0.07),
            ],
            "n": [(-0.98, 2.4), (0.95, 2.8), (1.95, 3.0), (4.0, 2.6)],
            "dip": [(-1, 0), (1.02, 0), (1.12, 0.20), (1.78, 0.20), (1.88, 0), (5, 0)],
            "dipw": [(-1, 0.2), (5, 0.2)],
        },
        "body_z": (-0.98, 4.00),
        "dense": [(-0.98, -0.85, 0.02), (0.95, 1.2, 0.02), (1.72, 2.0, 0.02)],
        "cockpit": (0.19, 1.06, 1.86, 0.42),
        "tip_z": -0.80,
        "pod": {
            "cx": [(1.00, 0.50), (1.10, 0.54), (2.20, 0.56), (3.00, 0.45), (3.40, 0.30)],
            "cy": [(1.00, 0.30), (1.10, 0.30), (2.20, 0.30), (3.00, 0.27), (3.40, 0.22)],
            "wt": [(1.00, 0.20), (1.10, 0.24), (2.20, 0.25), (3.00, 0.18), (3.40, 0.10)],
            "wb": [(1.00, 0.20), (1.10, 0.24), (2.20, 0.25), (3.00, 0.18), (3.40, 0.10)],
            "ht": [(1.00, 0.10), (1.10, 0.12), (2.20, 0.12), (3.00, 0.09), (3.40, 0.06)],
            "hb": [(1.00, 0.14), (1.10, 0.16), (2.20, 0.17), (3.00, 0.15), (3.40, 0.12)],
            "n": [(1.00, 3.2), (3.40, 2.6)],
        },
        "pod_z": (1.00, 3.40),
        "mirror": ((0.36, 0.60, 0.95), (0.26, 0.55, 1.0)),
        "floor": {
            "half": [(0.0, 0.50), (0.70, 0.95), (0.80, 3.00), (0.50, 3.40), (0.45, 3.95)],
            "diffuser": (3.40, 4.00, 0.45, 0.28),
        },
        "tail": (0, 0.31, 4.015),
        "exhausts": [(0.22, 0.30, 4.0, 0.05, 0.14)],
        "halo": None,
        "steer": (0, 0.56, 1.15),
        "suit": (0, 0.49, 1.5),
        "wheel_y": 0.31,
        "susp": {
            "wishbones": [
                ((0.14, 0.38, -0.08), (0.14, 0.40, 0.22), (0.62, 0.42, 0.0)),
                ((0.14, 0.20, -0.12), (0.14, 0.19, 0.28), (0.64, 0.19, 0.02)),
                ((0.18, 0.44, 3.25), (0.16, 0.44, 3.70), (0.52, 0.48, 3.50)),
                ((0.20, 0.16, 3.20), (0.20, 0.18, 3.70), (0.54, 0.16, 3.50)),
            ],
            "rods": [((0.20, 0.30, 3.50), (0.50, 0.33, 3.50), 0.022)],
            "drums": [(0.0, 0.48, 0.60, 0.14), (3.5, 0.40, 0.49, 0.17)],
        },
        "wings": wings,
        "extras": extras,
        "liv": default_liv(
            flash=[(1.05, 0.26), (1.05, 0.36), (3.3, 0.30), (3.3, 0.25)],
            circuit=[(1.05, 0.325), (3.3, 0.29), (3.3, 0.275), (1.05, 0.31)],
            flames=[
                flame_poly(1.05, 2.6, 0.30, 0.2, 5, 1.0),
                flame_poly(1.05, 2.2, 0.30, 0.14, 4, 1.4),
                flame_poly(1.05, 1.8, 0.30, 0.08, 3, 1.9),
            ],
            outer_x=0.55,
            pod_cx=0.55,
            pod_top_y=0.38,
            pchev_z=1.3,
            pchev_k=0.8,
            check_ymin=0.55,
            check_w=0.22,
            cover_z=(2.0, 3.4),
            cover_side=[(2.0, 0.52), (2.0, 0.60), (3.5, 0.42), (3.5, 0.37)],
            split_y=0.44,
            split_front=0.2,
            chev_z=-0.55,
            chev_k=1.2,
            stripe_w=0.06,
            cockpit_ex=P.box_region(x0=-0.215, x1=0.215, z0=1.04, z1=1.88, y0=0.40),
        ),
        "anchors": lambda body: std_anchors(
            body,
            _wheels(0.75, 0.31, 0.30, 0.72, 0.34, 0.45, 3.5, "t13"),
            (0, 0.78, 1.47),
            -0.3,
            (0.105, 0.56, 2.6),
            (0.22, 0.30, 4.02),
            (0, 0.55, 3.0),
            [(-0.47, 1.0, 4.35), (0.47, 1.0, 4.35)],
            {"pos": (0, 0.05, 1.9), "size": (1.5, 3.3)},
        ),
    }
    return open_wheeler("r88", S)


def auto_liv(body_keys, pod_keys, pod_z, cover_z=(2.05, 3.5), cockpit=(1.04, 1.9), **kw):
    """Derive livery zones (side flash, circuit lines, flames, two-tone line, checker) from the shapes."""
    body = Track(body_keys, linear={"dip", "dipw"})
    pod = Track(pod_keys)
    z0, z1 = pod_z
    zs = list(np.linspace(z0, z0 + (z1 - z0) * 0.9, 8))
    mid = [(z, pod(z)["cy"] + pod(z)["ht"] * 0.05) for z in zs]
    flash = [(z, y - 0.045) for z, y in mid] + [(z, y + 0.045) for z, y in reversed(mid)]
    flash[len(mid) - 1] = (flash[len(mid) - 1][0], flash[len(mid) - 1][1] + 0.02)
    circ = [(z, y + 0.035) for z, y in mid] + [(z, y + 0.05) for z, y in reversed(mid)]
    p0 = pod(z0)
    fh = (p0["ht"] + p0["hb"]) * 0.8
    L = z1 - z0
    flames = [
        flame_poly(z0, z0 + L * 0.75, p0["cy"], fh, 5, 1.0),
        flame_poly(z0, z0 + L * 0.55, p0["cy"], fh * 0.72, 4, 1.4),
        flame_poly(z0, z0 + L * 0.35, p0["cy"], fh * 0.45, 3, 1.9),
    ]
    cz0, cz1 = cover_z
    b0, b1 = body(cz0 + 0.05), body(cz1)
    cs = [
        (cz0 + 0.05, b0["cy"] + b0["ht"] * 0.45),
        (cz0 + 0.05, b0["cy"] + b0["ht"] * 0.7),
        (cz1, b1["cy"] + b1["ht"] * 0.75),
        (cz1, b1["cy"] + b1["ht"] * 0.4),
    ]
    bm = body((cz0 + cz1) / 2)
    bc = body(cockpit[0] - 0.1)
    L2 = dict(
        flash=flash,
        circuit=circ,
        flames=flames,
        outer_x=p0.get("cx", 0.5) - 0.02,
        pod_cx=p0.get("cx", 0.5),
        pod_top_y=p0["cy"] + p0["ht"] * 0.55,
        pchev_z=z0 + 0.25,
        check_ymin=bm["cy"] + bm["ht"] * 0.72,
        check_w=min(0.3, max(bm["wt"], 0.12) * 1.6),
        split_y=bc["cy"] + bc["ht"] * 0.55,
        split_front=body(body_keys["cy"][0][0])["cy"],
        cover_z=cover_z,
        cover_side=cs,
        cockpit_ex=P.box_region(x0=-0.215, x1=0.215, z0=cockpit[0], z1=cockpit[1], y0=bc["cy"] + bc["ht"] * 0.4),
        chev_z=body_keys["cy"][0][0] + 0.35,
        chev_k=1.3,
    )
    L2.update(kw)
    return default_liv(**L2)


def _dip(z0=1.02, z1=1.9, depth=0.22):
    """Keyframes for the dip in the body behind the cockpit."""
    return {
        "dip": [(-2, 0), (z0, 0), (z0 + 0.1, depth), (z1 - 0.1, depth), (z1, 0), (6, 0)],
        "dipw": [(-2, 0.2), (6, 0.2)],
    }


def _susp(fz=0.0, rz=3.6, fx=0.66, rx=0.62, wy=0.36, hi_nose=0.45):
    """Suspension geometry for add_susp."""
    return {
        "wishbones": [
            ((0.16, hi_nose, fz - 0.12), (0.16, hi_nose + 0.02, fz + 0.25), (fx, wy + 0.13, fz)),
            ((0.15, 0.22, fz - 0.16), (0.15, 0.21, fz + 0.34), (fx + 0.02, wy - 0.15, fz + 0.02)),
            ((0.20, 0.46, rz - 0.32), (0.18, 0.46, rz + 0.12), (rx, wy + 0.16, rz)),
            ((0.21, 0.17, rz - 0.38), (0.21, 0.19, rz + 0.16), (rx + 0.02, wy - 0.17, rz)),
        ],
        "rods": [
            ((fx - 0.03, wy - 0.14, fz + 0.03), (0.18, hi_nose + 0.05, fz + 0.12), 0.012),
            ((0.20, 0.30, rz), (rx - 0.02, wy - 0.02, rz), 0.02),
        ],
        "drums": [(fz, fx - 0.14, fx - 0.005, 0.16), (rz, rx - 0.14, rx - 0.04, 0.17)],
    }


def _anch(wheels, head, nose_z, side, exhaust, engine, trail, glow=None):
    """An anchors function for a design, filled in once its body shape is known."""
    return lambda body: std_anchors(
        body, wheels, head, nose_z, side, exhaust, engine, trail, glow or {"pos": (0, 0.05, 1.9), "size": (1.5, 3.4)}
    )


MOD_FLOOR = {
    "half": [
        (0.0, 0.33),
        (0.30, 0.40),
        (0.56, 0.78),
        (0.79, 1.08),
        (0.81, 2.90),
        (0.72, 3.14),
        (0.57, 3.28),
        (0.55, 3.95),
        (0.50, 4.10),
    ],
    "edge": (1.08, 2.88, 0.80),
    "diffuser": (3.45, 4.22, 0.5, 0.32),
}
W18 = _wheels(0.80, 0.36, 0.305, 0.775, 0.365, 0.405, 3.6, "t18")


# ---------------------------------------------------------------------------
# AERO S: 2022 "zero-pod" - tiny slot sidepods, short blunt nose, side shelves, louvres
# ---------------------------------------------------------------------------
def aeros():
    body = {
        "cy": [
            (-0.80, 0.24),
            (-0.72, 0.26),
            (-0.40, 0.32),
            (0.10, 0.40),
            (0.50, 0.44),
            (0.95, 0.45),
            (1.25, 0.45),
            (1.75, 0.45),
            (1.97, 0.50),
            (2.30, 0.50),
            (2.90, 0.46),
            (3.50, 0.41),
            (3.95, 0.36),
            (4.15, 0.34),
        ],
        "wt": [
            (-0.80, 0.11),
            (-0.72, 0.14),
            (-0.40, 0.15),
            (0.10, 0.16),
            (0.50, 0.20),
            (0.95, 0.25),
            (1.25, 0.29),
            (1.75, 0.30),
            (1.97, 0.16),
            (2.30, 0.17),
            (2.90, 0.16),
            (3.50, 0.11),
            (3.95, 0.07),
            (4.15, 0.045),
        ],
        "wb": [
            (-0.80, 0.12),
            (-0.72, 0.15),
            (-0.40, 0.17),
            (0.10, 0.20),
            (0.50, 0.25),
            (0.95, 0.30),
            (1.25, 0.33),
            (1.75, 0.36),
            (1.97, 0.40),
            (2.30, 0.40),
            (2.90, 0.33),
            (3.50, 0.20),
            (3.95, 0.10),
            (4.15, 0.055),
        ],
        "ht": [
            (-0.80, 0.05),
            (-0.72, 0.075),
            (-0.40, 0.095),
            (0.10, 0.115),
            (0.50, 0.14),
            (0.95, 0.21),
            (1.25, 0.27),
            (1.75, 0.27),
            (1.97, 0.46),
            (2.30, 0.41),
            (2.90, 0.30),
            (3.50, 0.19),
            (3.95, 0.10),
            (4.15, 0.06),
        ],
        "hb": [
            (-0.80, 0.06),
            (-0.72, 0.07),
            (-0.40, 0.09),
            (0.10, 0.13),
            (0.50, 0.19),
            (0.95, 0.30),
            (1.25, 0.33),
            (1.75, 0.33),
            (1.97, 0.38),
            (2.30, 0.38),
            (2.90, 0.35),
            (3.50, 0.30),
            (3.95, 0.18),
            (4.15, 0.07),
        ],
        "n": [(-0.8, 3.2), (0.95, 2.8), (1.75, 3.0), (1.97, 2.5), (4.15, 2.4)],
        **_dip(),
    }
    pod = {
        "cx": [(1.35, 0.40), (1.45, 0.41), (1.90, 0.40), (2.40, 0.34), (2.80, 0.26)],
        "cy": [(1.35, 0.46), (1.45, 0.46), (1.90, 0.44), (2.40, 0.40), (2.80, 0.36)],
        "wt": [(1.35, 0.09), (1.45, 0.10), (1.90, 0.10), (2.40, 0.08), (2.80, 0.05)],
        "wb": [(1.35, 0.07), (1.45, 0.08), (1.90, 0.08), (2.40, 0.07), (2.80, 0.05)],
        "ht": [(1.35, 0.14), (1.45, 0.16), (1.90, 0.16), (2.40, 0.12), (2.80, 0.08)],
        "hb": [(1.35, 0.16), (1.45, 0.18), (1.90, 0.18), (2.40, 0.16), (2.80, 0.12)],
        "n": [(1.35, 3.4), (2.8, 2.6)],
    }

    def wings(d):
        fw_elements(
            d,
            [
                (0.08, -1.06, 0.36, 3, 0.03, 0.05, 1.0, "Accent", True),
                (0.11, -0.78, 0.20, 13, 0.06, 0.04, 1.0, "Accent", False),
                (0.15, -0.64, 0.15, 24, 0.09, 0.03, 0.9, "Secondary", False),
            ],
            0.935,
            0.14,
            [(-1.10, 0.025), (-0.52, 0.025), (-0.50, 0.12)]
            + P.arc_pts(-0.72, 0.12, 0.2, 0, 150, 6)[1:]
            + [(-1.10, 0.10)],
        )
        rw_elements(
            d,
            [(0.78, 3.97, 0.34, 6, "Accent"), (0.88, 4.24, 0.20, 26, "Secondary")],
            0.52,
            [(3.92, 0.62), (4.46, 0.58)] + P.arc_pts(4.35, 0.84, 0.13, -40, 110, 7)[1:] + [(3.94, 0.9)],
            droop=0.10,
        )
        d.add("RearWing", "Carbon", P.endplate([(3.92, 0.36), (4.12, 0.36), (4.22, 0.80), (4.04, 0.80)], 0, 0.02))
        d.add(
            "RearWing",
            "Carbon",
            P.wing_element(-0.43, 0.43, lambda x: {"y": 0.44, "z": 4.03, "c": 0.17, "a": 6}, stations=10),
        )

    def extras(d, b):
        for s, g in ((1, "RightPod"), (-1, "LeftPod")):
            # side-impact "shelf" wing jutting out from the tiny pod
            shelf = P.wing_element(
                0.40, 0.74, lambda x: {"y": 0.34, "z": 1.35, "c": 0.34, "a": -4}, stations=8, thick=0.12
            )
            d.add(g, "Primary", _mirrored(shelf, s))
            for k in range(5):
                d.add(g, "Dark", _mirrored(geo.box((0.25, 0.70 - k * 0.018, 2.15 + k * 0.1), (0.1, 0.012, 0.05)), s))

    S = {
        "body": body,
        "body_z": (-0.80, 4.15),
        "dense": [(-0.80, -0.68, 0.02), (0.95, 1.2, 0.02), (1.75, 2.05, 0.02)],
        "cockpit": (0.19, 1.06, 1.88, 0.49),
        "tip_z": -0.66,
        "pod": pod,
        "pod_z": (1.35, 2.80),
        "mirror": ((0.36, 0.86, 1.26), (0.27, 0.88, 1.32)),
        "floor": MOD_FLOOR,
        "intake": (0.09, 0.80, 0.94, 1.93),
        "tcam": (0, 0.985, 2.06),
        "tail": (0, 0.335, 4.165),
        "exhausts": [(0, 0.47, 4.16, 0.042, 0.14)],
        "halo": (0.98, 0.64, 0.92, 1.9, 0.27, 0.70),
        "suit": (0, 0.56, 1.52),
        "wheel_y": 0.36,
        "susp": _susp(),
        "wings": wings,
        "extras": extras,
        "liv": auto_liv(body, pod, (1.35, 2.80)),
        "anchors": _anch(
            W18,
            (0, 0.82, 1.47),
            -0.3,
            (0.17, 0.70, 2.55),
            (0, 0.47, 4.17),
            (0, 0.7, 3.0),
            [(-0.53, 0.99, 4.45), (0.53, 0.99, 4.45)],
        ),
    }
    return open_wheeler("aer", S)


# ---------------------------------------------------------------------------
# FALCON: 2014 "finger nose", size-zero pods, narrow tall rear wing, no halo
# ---------------------------------------------------------------------------
def falcon():
    body = {
        "cy": [
            (-0.98, 0.17),
            (-0.92, 0.18),
            (-0.78, 0.20),
            (-0.62, 0.30),
            (-0.45, 0.40),
            (-0.10, 0.47),
            (0.40, 0.50),
            (0.95, 0.49),
            (1.25, 0.49),
            (1.75, 0.49),
            (1.97, 0.55),
            (2.30, 0.54),
            (2.90, 0.47),
            (3.50, 0.40),
            (3.95, 0.36),
            (4.15, 0.35),
        ],
        "wt": [
            (-0.98, 0.03),
            (-0.92, 0.04),
            (-0.78, 0.045),
            (-0.62, 0.10),
            (-0.45, 0.14),
            (-0.10, 0.16),
            (0.40, 0.20),
            (0.95, 0.25),
            (1.25, 0.28),
            (1.75, 0.29),
            (1.97, 0.10),
            (2.30, 0.10),
            (2.90, 0.09),
            (3.50, 0.07),
            (3.95, 0.05),
            (4.15, 0.04),
        ],
        "wb": [
            (-0.98, 0.03),
            (-0.92, 0.04),
            (-0.78, 0.045),
            (-0.62, 0.07),
            (-0.45, 0.12),
            (-0.10, 0.15),
            (0.40, 0.20),
            (0.95, 0.28),
            (1.25, 0.31),
            (1.75, 0.32),
            (1.97, 0.32),
            (2.30, 0.30),
            (2.90, 0.22),
            (3.50, 0.14),
            (3.95, 0.08),
            (4.15, 0.05),
        ],
        "ht": [
            (-0.98, 0.025),
            (-0.92, 0.03),
            (-0.78, 0.035),
            (-0.62, 0.09),
            (-0.45, 0.10),
            (-0.10, 0.11),
            (0.40, 0.14),
            (0.95, 0.20),
            (1.25, 0.25),
            (1.75, 0.25),
            (1.97, 0.46),
            (2.30, 0.40),
            (2.90, 0.27),
            (3.50, 0.17),
            (3.95, 0.09),
            (4.15, 0.05),
        ],
        "hb": [
            (-0.98, 0.025),
            (-0.92, 0.03),
            (-0.78, 0.035),
            (-0.62, 0.07),
            (-0.45, 0.08),
            (-0.10, 0.10),
            (0.40, 0.16),
            (0.95, 0.32),
            (1.25, 0.35),
            (1.75, 0.35),
            (1.97, 0.42),
            (2.30, 0.42),
            (2.90, 0.35),
            (3.50, 0.28),
            (3.95, 0.20),
            (4.15, 0.08),
        ],
        "n": [(-0.98, 2.0), (-0.6, 2.4), (0.95, 2.8), (1.75, 3.0), (1.97, 2.1), (4.15, 2.4)],
        **_dip(1.02, 1.9, 0.22),
    }
    pod = {
        "cx": [(1.40, 0.50), (1.50, 0.51), (1.90, 0.48), (2.50, 0.38), (3.20, 0.22)],
        "cy": [(1.40, 0.49), (1.50, 0.49), (1.90, 0.46), (2.50, 0.38), (3.20, 0.25)],
        "wt": [(1.40, 0.15), (1.50, 0.17), (1.90, 0.17), (2.50, 0.13), (3.20, 0.05)],
        "wb": [(1.40, 0.06), (1.50, 0.07), (1.90, 0.07), (2.50, 0.06), (3.20, 0.04)],
        "ht": [(1.40, 0.11), (1.50, 0.13), (1.90, 0.14), (2.50, 0.11), (3.20, 0.05)],
        "hb": [(1.40, 0.24), (1.50, 0.27), (1.90, 0.30), (2.50, 0.26), (3.20, 0.15)],
        "n": [(1.40, 3.2), (3.2, 2.4)],
    }

    def wings(d):
        fw_elements(
            d,
            [
                (0.07, -1.06, 0.30, 2, 0.04, 0.08, 1.0, "Accent", True),
                (0.10, -0.83, 0.17, 16, 0.14, 0.10, 0.9, "Accent", False),
                (0.15, -0.70, 0.13, 30, 0.17, 0.10, 0.8, "Secondary", False),
            ],
            0.825,
            0.10,
            [(-1.10, 0.02), (-0.46, 0.02), (-0.44, 0.24), (-0.60, 0.36), (-1.0, 0.34), (-1.10, 0.18)],
            sweep_rise=(0.3, 0.88),
        )
        _plates(d, "FrontWing", "Carbon", [([(-0.99, 0.09), (-0.80, 0.09), (-0.78, 0.20), (-0.94, 0.18)], 0.035)])
        rw_elements(
            d,
            [(0.88, 4.02, 0.30, 7, "Accent"), (0.98, 4.28, 0.18, 30, "Secondary")],
            0.375,
            [(3.93, 0.40), (4.47, 0.40), (4.47, 1.04), (3.97, 1.04)],
            droop=0.0,
        )
        d.add("RearWing", "Carbon", P.endplate([(3.96, 0.40), (4.12, 0.40), (4.22, 0.89), (4.06, 0.89)], 0, 0.02))
        d.add(
            "RearWing",
            "Carbon",
            P.wing_element(-0.2, 0.2, lambda x: {"y": 0.53, "z": 4.10, "c": 0.10, "a": 16}, stations=6),
        )

    def extras(d, b):
        _plates(
            d,
            "Body",
            "Carbon",
            [
                ([(0.50, 0.07), (1.30, 0.07), (1.33, 0.36), (1.10, 0.40), (0.70, 0.24)], 0.40),
                ([(0.85, 0.07), (1.36, 0.07), (1.34, 0.28), (1.02, 0.26)], 0.56),
            ],
        )
        d.add("Body", "Glass", geo.plate(geo.rounded_rect(-0.16, 0.66, 0.16, 0.74, 0.03, 3), "xy", 1.04, 0.01))

    S = {
        "body": body,
        "body_z": (-0.98, 4.15),
        "dense": [(-0.98, -0.55, 0.02), (0.95, 1.2, 0.02), (1.75, 2.05, 0.02)],
        "cockpit": (0.19, 1.06, 1.88, 0.51),
        "tip_z": -0.80,
        "pod": pod,
        "pod_z": (1.40, 3.20),
        "mirror": ((0.44, 0.72, 1.12), (0.28, 0.63, 1.18)),
        "floor": {
            "half": [
                (0.0, 0.42),
                (0.45, 0.48),
                (0.62, 0.90),
                (0.78, 1.20),
                (0.80, 3.00),
                (0.60, 3.25),
                (0.52, 3.95),
                (0.48, 4.10),
            ],
            "diffuser": (3.45, 4.15, 0.48, 0.34),
        },
        "intake": (0.08, 0.84, 0.99, 1.93),
        "tcam": (0, 1.02, 2.05),
        "tail": (0, 0.345, 4.165),
        "exhausts": [(0, 0.46, 4.17, 0.05, 0.12)],
        "halo": None,
        "suit": (0, 0.58, 1.52),
        "wheel_y": 0.33,
        "susp": _susp(wy=0.33, fx=0.64, rx=0.62, hi_nose=0.48),
        "wings": wings,
        "extras": extras,
        "liv": auto_liv(body, pod, (1.40, 3.20)),
        "anchors": _anch(
            _wheels(0.76, 0.33, 0.27, 0.74, 0.33, 0.38, 3.6, "t13"),
            (0, 0.85, 1.47),
            -0.2,
            (0.105, 0.72, 2.6),
            (0, 0.46, 4.18),
            (0, 0.72, 3.0),
            [(-0.39, 1.04, 4.45), (0.39, 1.04, 4.45)],
        ),
    }
    return open_wheeler("fal", S)


# ---------------------------------------------------------------------------
# VIPER: 2010-12 "step nose", big shark fin, tall narrow rear wing, wide low front wing
# ---------------------------------------------------------------------------
def viper():
    body = {
        "cy": [
            (-0.98, 0.22),
            (-0.90, 0.23),
            (-0.60, 0.27),
            (-0.20, 0.31),
            (0.00, 0.34),
            (0.15, 0.46),
            (0.50, 0.50),
            (0.95, 0.49),
            (1.25, 0.49),
            (1.75, 0.49),
            (1.97, 0.54),
            (2.30, 0.53),
            (2.90, 0.47),
            (3.50, 0.40),
            (3.95, 0.36),
            (4.15, 0.35),
        ],
        "wt": [
            (-0.98, 0.05),
            (-0.90, 0.09),
            (-0.60, 0.11),
            (-0.20, 0.12),
            (0.00, 0.13),
            (0.15, 0.17),
            (0.50, 0.20),
            (0.95, 0.25),
            (1.25, 0.28),
            (1.75, 0.29),
            (1.97, 0.10),
            (2.30, 0.09),
            (2.90, 0.08),
            (3.50, 0.07),
            (3.95, 0.05),
            (4.15, 0.04),
        ],
        "wb": [
            (-0.98, 0.06),
            (-0.90, 0.10),
            (-0.60, 0.12),
            (-0.20, 0.13),
            (0.00, 0.14),
            (0.15, 0.18),
            (0.50, 0.22),
            (0.95, 0.28),
            (1.25, 0.31),
            (1.75, 0.32),
            (1.97, 0.32),
            (2.30, 0.30),
            (2.90, 0.22),
            (3.50, 0.14),
            (3.95, 0.08),
            (4.15, 0.05),
        ],
        "ht": [
            (-0.98, 0.04),
            (-0.90, 0.06),
            (-0.60, 0.08),
            (-0.20, 0.09),
            (0.00, 0.10),
            (0.15, 0.13),
            (0.50, 0.15),
            (0.95, 0.21),
            (1.25, 0.26),
            (1.75, 0.26),
            (1.97, 0.46),
            (2.30, 0.40),
            (2.90, 0.28),
            (3.50, 0.18),
            (3.95, 0.09),
            (4.15, 0.05),
        ],
        "hb": [
            (-0.98, 0.04),
            (-0.90, 0.06),
            (-0.60, 0.07),
            (-0.20, 0.08),
            (0.00, 0.09),
            (0.15, 0.15),
            (0.50, 0.20),
            (0.95, 0.32),
            (1.25, 0.35),
            (1.75, 0.35),
            (1.97, 0.40),
            (2.30, 0.40),
            (2.90, 0.34),
            (3.50, 0.28),
            (3.95, 0.20),
            (4.15, 0.08),
        ],
        "n": [(-0.98, 2.3), (0.0, 2.5), (0.15, 3.2), (0.95, 2.8), (1.75, 3.0), (1.97, 2.1), (4.15, 2.4)],
        **_dip(1.02, 1.9, 0.22),
    }
    pod = {
        "cx": [(1.30, 0.52), (1.40, 0.54), (1.90, 0.53), (2.50, 0.45), (3.20, 0.26)],
        "cy": [(1.30, 0.40), (1.40, 0.40), (1.90, 0.39), (2.50, 0.34), (3.20, 0.24)],
        "wt": [(1.30, 0.19), (1.40, 0.21), (1.90, 0.21), (2.50, 0.17), (3.20, 0.06)],
        "wb": [(1.30, 0.14), (1.40, 0.16), (1.90, 0.15), (2.50, 0.13), (3.20, 0.05)],
        "ht": [(1.30, 0.15), (1.40, 0.17), (1.90, 0.17), (2.50, 0.13), (3.20, 0.06)],
        "hb": [(1.30, 0.20), (1.40, 0.22), (1.90, 0.22), (2.50, 0.20), (3.20, 0.13)],
        "n": [(1.30, 3.4), (3.2, 2.4)],
    }

    def wings(d):
        fw_elements(
            d,
            [
                (0.07, -1.05, 0.32, 3, 0.02, 0.05, 1.0, "Accent", True),
                (0.11, -0.80, 0.19, 18, 0.07, 0.06, 0.9, "Secondary", False),
            ],
            0.90,
            0.15,
            [(-1.10, 0.02), (-0.50, 0.02), (-0.50, 0.30), (-0.75, 0.33), (-1.10, 0.20)],
            sweep_rise=(0.55, 0.95),
        )
        rw_elements(
            d,
            [(0.93, 4.00, 0.32, 8, "Accent"), (1.03, 4.26, 0.19, 28, "Secondary")],
            0.375,
            [(3.92, 0.45), (4.46, 0.45), (4.46, 1.08), (3.95, 1.08)],
            droop=0.0,
        )
        d.add(
            "RearWing",
            "Carbon",
            P.wing_element(-0.33, 0.33, lambda x: {"y": 0.48, "z": 4.02, "c": 0.17, "a": 8}, stations=10),
        )
        _plates(d, "RearWing", "Carbon", [([(3.98, 0.42), (4.14, 0.42), (4.18, 0.92), (4.04, 0.92)], 0.05)])

    def extras(d, b):
        for s, g in ((1, "RightPod"), (-1, "LeftPod")):
            ex = geo.tube(
                geo.bezier([(s * 0.36, 0.30, 3.05), (s * 0.38, 0.33, 3.2), (s * 0.40, 0.34, 3.3)], 6), 0.04, N=12
            )
            d.add(g, "Metal", ex)
        _plates(d, "Body", "Carbon", [([(0.62, 0.07), (1.22, 0.07), (1.24, 0.38), (0.95, 0.40), (0.78, 0.22)], 0.44)])

    S = {
        "body": body,
        "body_z": (-0.98, 4.15),
        "dense": [(-0.98, -0.85, 0.02), (-0.05, 0.25, 0.02), (0.95, 1.2, 0.02), (1.75, 2.05, 0.02)],
        "cockpit": (0.19, 1.06, 1.88, 0.51),
        "tip_z": -0.80,
        "pod": pod,
        "pod_z": (1.30, 3.20),
        "mirror": ((0.46, 0.68, 1.10), (0.30, 0.60, 1.16)),
        "floor": {
            "half": [
                (0.0, 0.45),
                (0.40, 0.50),
                (0.62, 0.90),
                (0.78, 1.15),
                (0.80, 3.00),
                (0.60, 3.25),
                (0.52, 3.95),
                (0.48, 4.10),
            ],
            "diffuser": (3.45, 4.15, 0.48, 0.36),
        },
        "intake": (0.08, 0.83, 0.98, 1.93),
        "tcam": (0, 1.01, 2.05),
        "fin": [(2.10, 0.93), (2.35, 0.99), (4.00, 0.99), (4.00, 0.55), (2.25, 0.85)],
        "fin_always": True,
        "tail": (0, 0.345, 4.165),
        "halo": None,
        "suit": (0, 0.58, 1.52),
        "wheel_y": 0.33,
        "susp": _susp(wy=0.33, fx=0.66, rx=0.62, hi_nose=0.46),
        "wings": wings,
        "extras": extras,
        "liv": auto_liv(body, pod, (1.30, 3.20)),
        "anchors": _anch(
            _wheels(0.78, 0.33, 0.27, 0.76, 0.33, 0.37, 3.6, "t13"),
            (0, 0.85, 1.47),
            -0.4,
            (0.105, 0.72, 2.6),
            (0, 0.34, 3.3),
            (0, 0.72, 3.0),
            [(-0.39, 1.08, 4.45), (0.39, 1.08, 4.45)],
        ),
    }
    return open_wheeler("vip", S)


def _rot_z_polys(polys, center, ang):
    """Polygons rotated about the z axis around `center`."""
    c, s = math.cos(ang), math.sin(ang)
    cx, cy, cz = center
    return [
        np.array([[cx + (v[0] - cx) * c - (v[1] - cy) * s, cy + (v[0] - cx) * s + (v[1] - cy) * c, v[2]] for v in p])
        for p in polys
    ]


# ---------------------------------------------------------------------------
# AURORA: concept car - closed glass canopy, teardrop body, tall tail fin, delta wings
# ---------------------------------------------------------------------------
def aurora():
    body = {
        "cy": [
            (-1.00, 0.20),
            (-0.90, 0.22),
            (-0.50, 0.30),
            (0.00, 0.38),
            (0.50, 0.43),
            (1.00, 0.45),
            (1.50, 0.46),
            (2.00, 0.46),
            (2.60, 0.44),
            (3.20, 0.40),
            (3.80, 0.36),
            (4.20, 0.33),
        ],
        "wt": [
            (-1.00, 0.08),
            (-0.90, 0.14),
            (-0.50, 0.16),
            (0.00, 0.19),
            (0.50, 0.24),
            (1.00, 0.28),
            (1.50, 0.30),
            (2.00, 0.28),
            (2.60, 0.22),
            (3.20, 0.14),
            (3.80, 0.08),
            (4.20, 0.04),
        ],
        "wb": [
            (-1.00, 0.10),
            (-0.90, 0.16),
            (-0.50, 0.19),
            (0.00, 0.22),
            (0.50, 0.28),
            (1.00, 0.32),
            (1.50, 0.34),
            (2.00, 0.33),
            (2.60, 0.28),
            (3.20, 0.19),
            (3.80, 0.10),
            (4.20, 0.05),
        ],
        "ht": [
            (-1.00, 0.04),
            (-0.90, 0.07),
            (-0.50, 0.10),
            (0.00, 0.13),
            (0.50, 0.17),
            (1.00, 0.20),
            (1.50, 0.21),
            (2.00, 0.20),
            (2.60, 0.17),
            (3.20, 0.12),
            (3.80, 0.08),
            (4.20, 0.05),
        ],
        "hb": [
            (-1.00, 0.05),
            (-0.90, 0.07),
            (-0.50, 0.10),
            (0.00, 0.14),
            (0.50, 0.20),
            (1.00, 0.30),
            (1.50, 0.33),
            (2.00, 0.33),
            (2.60, 0.30),
            (3.20, 0.26),
            (3.80, 0.18),
            (4.20, 0.07),
        ],
        "n": [(-1.0, 2.4), (4.2, 2.4)],
        "dip": [(-2, 0), (6, 0)],
        "dipw": [(-2, 0.2), (6, 0.2)],
    }
    pod = {
        "cx": [(1.10, 0.48), (1.25, 0.52), (2.00, 0.52), (2.80, 0.42), (3.40, 0.26)],
        "cy": [(1.10, 0.38), (1.25, 0.38), (2.00, 0.37), (2.80, 0.32), (3.40, 0.24)],
        "wt": [(1.10, 0.16), (1.25, 0.20), (2.00, 0.21), (2.80, 0.15), (3.40, 0.06)],
        "wb": [(1.10, 0.13), (1.25, 0.17), (2.00, 0.18), (2.80, 0.13), (3.40, 0.05)],
        "ht": [(1.10, 0.10), (1.25, 0.14), (2.00, 0.15), (2.80, 0.11), (3.40, 0.05)],
        "hb": [(1.10, 0.14), (1.25, 0.18), (2.00, 0.19), (2.80, 0.16), (3.40, 0.11)],
        "n": [(1.1, 2.4), (3.4, 2.3)],
    }

    def wings(d):
        # delta front wing: one swept element with small fins
        def fn(x):
            t = abs(x) / 0.9
            return {"y": 0.09 + 0.05 * t * t, "z": -1.02 + 0.30 * t, "c": 0.42 - 0.22 * t, "a": 5 + 8 * t}

        d.add("FrontWing", "Accent", P.wing_element(-0.9, 0.9, fn, stations=24, thick=0.07, camber=-0.04))
        for s in (1, -1):
            d.add(
                "FrontWing",
                "Secondary",
                P.endplate([(-0.78, 0.08), (-0.52, 0.08), (-0.56, 0.22), (-0.70, 0.20)], s * 0.905, 0.012),
            )

        # tail wing sitting on top of the fin
        def rfn(x):
            t = abs(x) / 0.52
            return {"y": 1.02 - 0.06 * t * t, "z": 3.98 + 0.16 * t, "c": 0.34 - 0.08 * t, "a": 7}

        d.add("RearWing", "Accent", P.wing_element(-0.52, 0.52, rfn, stations=20, thick=0.08, camber=-0.05))
        for s in (1, -1):
            d.add(
                "RearWing",
                "Secondary",
                P.endplate([(4.10, 0.74), (4.42, 0.74), (4.46, 1.02), (4.12, 0.98)], s * 0.53, 0.014),
            )

    def extras(d, b):
        can = Track(
            {
                "cy": [(0.75, 0.62), (1.00, 0.65), (1.45, 0.66), (1.95, 0.64), (2.40, 0.60)],
                "wt": [(0.75, 0.10), (1.00, 0.20), (1.45, 0.23), (1.95, 0.20), (2.40, 0.08)],
                "wb": [(0.75, 0.12), (1.00, 0.23), (1.45, 0.26), (1.95, 0.23), (2.40, 0.10)],
                "ht": [(0.75, 0.02), (1.00, 0.22), (1.45, 0.34), (1.95, 0.27), (2.40, 0.04)],
                "hb": [(0.80, 0.02), (1.00, 0.04), (1.45, 0.05), (1.95, 0.04), (2.35, 0.02)],
                "n": [(0.75, 2.2), (2.40, 2.2)],
            }
        )
        rings = [superellipse_section(z, can(z), 40) for z in P.zsamples(0.75, 2.40, 0.05)]
        sd, cp = P.loft_obj(rings)
        d.add("Body", "Canopy", sd + cp[""])
        d.add(
            "Body",
            "Secondary",
            P.endplate([(2.35, 0.62), (2.7, 0.80), (4.05, 1.00), (4.12, 0.60), (2.6, 0.58)], 0, 0.02),
        )

    S = {
        "body": body,
        "body_z": (-1.00, 4.20),
        "dense": [(-1.0, -0.85, 0.02)],
        "cockpit": None,
        "tip_z": -0.86,
        "pod": pod,
        "pod_z": (1.10, 3.40),
        "mirror": None,
        "floor": MOD_FLOOR,
        "tail": (0, 0.30, 4.215),
        "exhausts": [(0, 0.40, 4.2, 0.045, 0.12)],
        "halo": None,
        "suit": (0, 0.56, 1.52),
        "wheel_y": 0.36,
        "susp": _susp(hi_nose=0.44),
        "wings": wings,
        "extras": extras,
        "liv": auto_liv(body, pod, (1.10, 3.40), cockpit=(0.8, 2.4)),
        "anchors": _anch(
            W18,
            (0, 0.80, 1.47),
            -0.3,
            (0.13, 0.55, 2.7),
            (0, 0.40, 4.21),
            (0, 0.6, 3.0),
            [(-0.54, 1.0, 4.35), (0.54, 1.0, 4.35)],
        ),
    }
    return open_wheeler("aur", S)


# ---------------------------------------------------------------------------
# NOVA: hyper concept - shark nose, cycle fenders over every wheel, twin tail fins
# ---------------------------------------------------------------------------
def nova():
    body = {
        "cy": [
            (-1.02, 0.17),
            (-0.94, 0.19),
            (-0.60, 0.26),
            (-0.20, 0.34),
            (0.20, 0.41),
            (0.60, 0.44),
            (0.95, 0.45),
            (1.25, 0.45),
            (1.75, 0.45),
            (1.97, 0.49),
            (2.30, 0.49),
            (2.90, 0.45),
            (3.50, 0.40),
            (3.95, 0.36),
            (4.15, 0.34),
        ],
        "wt": [
            (-1.02, 0.02),
            (-0.94, 0.06),
            (-0.60, 0.11),
            (-0.20, 0.14),
            (0.20, 0.17),
            (0.60, 0.21),
            (0.95, 0.25),
            (1.25, 0.29),
            (1.75, 0.30),
            (1.97, 0.12),
            (2.30, 0.11),
            (2.90, 0.10),
            (3.50, 0.08),
            (3.95, 0.06),
            (4.15, 0.045),
        ],
        "wb": [
            (-1.02, 0.03),
            (-0.94, 0.08),
            (-0.60, 0.13),
            (-0.20, 0.16),
            (0.20, 0.20),
            (0.60, 0.25),
            (0.95, 0.30),
            (1.25, 0.33),
            (1.75, 0.34),
            (1.97, 0.34),
            (2.30, 0.32),
            (2.90, 0.26),
            (3.50, 0.17),
            (3.95, 0.09),
            (4.15, 0.055),
        ],
        "ht": [
            (-1.02, 0.02),
            (-0.94, 0.04),
            (-0.60, 0.07),
            (-0.20, 0.10),
            (0.20, 0.12),
            (0.60, 0.15),
            (0.95, 0.21),
            (1.25, 0.27),
            (1.75, 0.27),
            (1.97, 0.44),
            (2.30, 0.39),
            (2.90, 0.29),
            (3.50, 0.19),
            (3.95, 0.10),
            (4.15, 0.06),
        ],
        "hb": [
            (-1.02, 0.02),
            (-0.94, 0.04),
            (-0.60, 0.07),
            (-0.20, 0.10),
            (0.20, 0.14),
            (0.60, 0.20),
            (0.95, 0.30),
            (1.25, 0.33),
            (1.75, 0.33),
            (1.97, 0.37),
            (2.30, 0.37),
            (2.90, 0.34),
            (3.50, 0.30),
            (3.95, 0.18),
            (4.15, 0.07),
        ],
        "n": [(-1.02, 2.0), (0.95, 2.8), (1.75, 3.0), (1.97, 2.2), (4.15, 2.4)],
        **_dip(),
    }
    pod = {
        "cx": [(1.25, 0.53), (1.35, 0.55), (1.90, 0.55), (2.60, 0.46), (3.40, 0.26)],
        "cy": [(1.25, 0.40), (1.35, 0.40), (1.90, 0.39), (2.60, 0.33), (3.40, 0.22)],
        "wt": [(1.25, 0.20), (1.35, 0.23), (1.90, 0.24), (2.60, 0.18), (3.40, 0.06)],
        "wb": [(1.25, 0.12), (1.35, 0.14), (1.90, 0.14), (2.60, 0.13), (3.40, 0.05)],
        "ht": [(1.25, 0.12), (1.35, 0.15), (1.90, 0.16), (2.60, 0.12), (3.40, 0.05)],
        "hb": [(1.25, 0.19), (1.35, 0.22), (1.90, 0.23), (2.60, 0.21), (3.40, 0.12)],
        "n": [(1.25, 2.6), (3.4, 2.3)],
    }

    def wings(d):
        fw_elements(
            d,
            [
                (0.07, -1.02, 0.30, 4, 0.03, 0.04, 1.0, "Accent", True),
                (0.12, -0.76, 0.17, 20, 0.06, 0.03, 0.9, "Secondary", False),
            ],
            0.92,
            0.10,
            [(-1.08, 0.025), (-0.56, 0.025), (-0.60, 0.16), (-1.0, 0.18)],
        )
        rw_elements(
            d,
            [(0.86, 3.98, 0.32, 9, "Accent"), (0.93, 4.24, 0.14, 24, "Secondary")],
            0.50,
            [(3.94, 0.62), (4.34, 0.62), (4.42, 1.00), (3.98, 0.96)],
            droop=0.03,
        )

    def fender(center, r, w, a0, a1, xoff):
        cz, cy = center
        steps = 12
        rings = []
        for k in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * k / steps)
            zz, yy = cz - math.cos(a) * r, cy + math.sin(a) * r
            nz, ny = -math.cos(a), math.sin(a)
            t = 0.02
            ring = [
                (xoff - w / 2, yy, zz),
                (xoff + w / 2, yy, zz),
                (xoff + w / 2, yy + ny * t, zz + nz * t),
                (xoff - w / 2, yy + ny * t, zz + nz * t),
            ]
            rings.append(np.array(ring))
        sd, cp = geo.loft(rings, True, True)
        return list(sd) + sum(cp.values(), [])

    def extras(d, b):
        for s in (1, -1):
            d.add("Body", "Primary", _mirrored(fender((0.0, 0.36), 0.42, 0.36, 25, 150, 0.80), s))
            d.add("Body", "Primary", _mirrored(fender((3.6, 0.365), 0.43, 0.44, 60, 165, 0.775), s))
            # fender struts
            d.add("Body", "Carbon", _mirrored(P.rod((0.62, 0.55, 0.0), (0.72, 0.74, -0.05), 0.014), s))
            d.add("Body", "Carbon", _mirrored(P.rod((0.60, 0.55, 3.55), (0.70, 0.76, 3.55), 0.014), s))
            fin = P.endplate([(2.9, 0.62), (3.3, 0.72), (4.05, 0.98), (4.05, 0.62)], 0.0, 0.014)
            d.add(
                "RearWing",
                "Secondary",
                _rot_z_polys(
                    [np.array([[v[0] + s * 0.26, v[1], v[2]] for v in p]) for p in fin], (s * 0.26, 0.62, 0), -s * 0.18
                ),
            )

    S = {
        "body": body,
        "body_z": (-1.02, 4.15),
        "dense": [(-1.02, -0.85, 0.02), (0.95, 1.2, 0.02), (1.75, 2.05, 0.02)],
        "cockpit": (0.19, 1.06, 1.88, 0.49),
        "tip_z": -0.82,
        "pod": pod,
        "pod_z": (1.25, 3.40),
        "mirror": ((0.48, 0.74, 1.22), (0.30, 0.64, 1.28)),
        "floor": MOD_FLOOR,
        "intake": (0.07, 0.80, 0.93, 1.93),
        "tcam": (0, 0.975, 2.06),
        "tail": (0, 0.335, 4.165),
        "exhausts": [(0, 0.47, 4.16, 0.042, 0.14)],
        "halo": (0.98, 0.64, 0.92, 1.9, 0.27, 0.70),
        "suit": (0, 0.56, 1.52),
        "wheel_y": 0.36,
        "susp": _susp(),
        "wings": wings,
        "extras": extras,
        "liv": auto_liv(body, pod, (1.25, 3.40)),
        "anchors": _anch(
            W18,
            (0, 0.82, 1.47),
            -0.3,
            (0.12, 0.69, 2.55),
            (0, 0.47, 4.17),
            (0, 0.7, 3.0),
            [(-0.51, 0.94, 4.3), (0.51, 0.94, 4.3)],
        ),
    }
    return open_wheeler("nov", S)


# ---------------------------------------------------------------------------
# STEALTH: chiselled, faceted "stealth jet" body - flat panels, chisel nose, canted twin fins
# ---------------------------------------------------------------------------
def stealth():
    body = {
        "cy": [
            (-1.00, 0.19),
            (-0.60, 0.27),
            (0.00, 0.37),
            (0.60, 0.44),
            (1.05, 0.45),
            (1.80, 0.45),
            (2.00, 0.50),
            (2.80, 0.46),
            (3.60, 0.39),
            (4.15, 0.34),
        ],
        "wt": [
            (-1.00, 0.10),
            (-0.60, 0.10),
            (0.00, 0.11),
            (0.60, 0.15),
            (1.05, 0.20),
            (1.80, 0.21),
            (2.00, 0.08),
            (2.80, 0.07),
            (3.60, 0.05),
            (4.15, 0.03),
        ],
        "wb": [
            (-1.00, 0.08),
            (-0.60, 0.13),
            (0.00, 0.17),
            (0.60, 0.24),
            (1.05, 0.30),
            (1.80, 0.33),
            (2.00, 0.33),
            (2.80, 0.26),
            (3.60, 0.14),
            (4.15, 0.05),
        ],
        "wm": [
            (-1.00, 0.12),
            (-0.60, 0.15),
            (0.00, 0.19),
            (0.60, 0.26),
            (1.05, 0.31),
            (1.80, 0.34),
            (2.00, 0.34),
            (2.80, 0.27),
            (3.60, 0.15),
            (4.15, 0.05),
        ],
        "ht": [
            (-1.00, 0.02),
            (-0.60, 0.07),
            (0.00, 0.11),
            (0.60, 0.15),
            (1.05, 0.23),
            (1.80, 0.25),
            (2.00, 0.45),
            (2.80, 0.30),
            (3.60, 0.17),
            (4.15, 0.06),
        ],
        "hb": [
            (-1.00, 0.04),
            (-0.60, 0.08),
            (0.00, 0.12),
            (0.60, 0.20),
            (1.05, 0.31),
            (1.80, 0.33),
            (2.00, 0.38),
            (2.80, 0.35),
            (3.60, 0.28),
            (4.15, 0.07),
        ],
        "dip": [(-2, 0), (6, 0)],
        "dipw": [(-2, 0.2), (6, 0.2)],
    }
    pod = {
        "cx": [(1.25, 0.53), (1.90, 0.55), (2.60, 0.46), (3.35, 0.26)],
        "cy": [(1.25, 0.40), (1.90, 0.39), (2.60, 0.33), (3.35, 0.23)],
        "wt": [(1.25, 0.14), (1.90, 0.16), (2.60, 0.12), (3.35, 0.04)],
        "wb": [(1.25, 0.12), (1.90, 0.13), (2.60, 0.11), (3.35, 0.04)],
        "wm": [(1.25, 0.22), (1.90, 0.24), (2.60, 0.18), (3.35, 0.06)],
        "ht": [(1.25, 0.15), (1.90, 0.17), (2.60, 0.12), (3.35, 0.05)],
        "hb": [(1.25, 0.20), (1.90, 0.22), (2.60, 0.19), (3.35, 0.12)],
    }

    def wings(d):
        # flat-plate front wing with angular endplates
        d.add(
            "FrontWing",
            "Accent",
            geo.plate([(-0.93, -1.06), (0.93, -1.06), (0.93, -0.72), (-0.93, -0.72)], "xz", 0.09, 0.03),
        )
        for s in (1, -1):
            d.add(
                "FrontWing",
                "Accent",
                _mirrored(
                    geo.transform(
                        geo.plate([(0.16, -0.78), (0.93, -0.78), (0.93, -0.58), (0.16, -0.62)], "xz", 0.0, 0.025),
                        lambda v: np.array([v[0], 0.16 + (v[2] + 0.78) * 0.45, v[2]]),
                    ),
                    s,
                ),
            )
            d.add(
                "FrontWing",
                "Secondary",
                P.endplate([(-1.10, 0.03), (-0.55, 0.03), (-0.62, 0.30), (-0.95, 0.22)], s * 0.945, 0.016),
            )
        # flat main plane + a flat active-aero flap (hinged at its trailing edge)
        d.add(
            "RearWing",
            "Accent",
            geo.plate([(-0.52, 3.96), (0.52, 3.96), (0.52, 4.22), (-0.52, 4.22)], "xz", 0.90, 0.035),
        )
        d.add(
            "Flap",
            "Secondary",
            geo.transform(
                geo.plate([(-0.52, 4.25), (0.52, 4.25), (0.52, 4.45), (-0.52, 4.45)], "xz", 0.0, 0.03),
                lambda v: np.array([v[0], 0.975 + (v[2] - 4.45) * 0.35 + v[1], v[2]]),
            ),
        )
        d.flaps[""] = (0.0, 0.975, 4.45)
        for s in (1, -1):
            ep = P.endplate([(3.90, 0.50), (4.48, 0.50), (4.42, 1.02), (3.98, 1.02)], s * 0.53, 0.016)
            d.add("RearWing", "Secondary", _rot_z_polys(ep, (s * 0.53, 0.5, 0), s * 0.12))
            fin = P.endplate([(2.4, 0.66), (2.9, 0.80), (3.95, 0.90), (3.95, 0.60)], s * 0.14, 0.014)
            d.add("RearWing", "Secondary", _rot_z_polys(fin, (s * 0.14, 0.6, 0), -s * 0.30))
        d.add("RearWing", "Carbon", P.endplate([(3.92, 0.36), (4.12, 0.36), (4.20, 0.89), (4.04, 0.89)], 0, 0.02))

    def extras(d, b):
        d.add(
            "Body",
            "Glass",
            geo.transform(
                geo.plate([(-0.20, 0.0), (0.20, 0.0), (0.12, 0.12), (-0.12, 0.12)], "xy", 0, 0.01),
                lambda v: np.array([v[0], 0.66 + v[1] * 0.8, 1.02 + v[1] * 0.6]),
            ),
        )

    zs = [-1.0, -0.8, -0.6, -0.3, 0.0, 0.3, 0.6, 0.85, 1.05, 1.4, 1.8, 1.9, 2.0, 2.4, 2.8, 3.2, 3.6, 3.9, 4.15]
    S = {
        "body": body,
        "body_z": (-1.00, 4.15),
        "zs": zs,
        "section": "facet",
        "cockpit": (0.19, 1.06, 1.88, 0.62),
        "tip_z": -0.62,
        "pod": pod,
        "pod_z": (1.25, 3.35),
        "mirror": ((0.46, 0.74, 1.22), (0.30, 0.64, 1.28)),
        "floor": MOD_FLOOR,
        "intake": (0.07, 0.80, 0.93, 1.99),
        "tcam": (0, 0.975, 2.08),
        "tail": (0, 0.33, 4.165),
        "exhausts": [(0, 0.46, 4.16, 0.042, 0.14)],
        "halo": (0.98, 0.68, 0.94, 1.9, 0.27, 0.72),
        "suit": (0, 0.56, 1.52),
        "wheel_y": 0.36,
        "susp": _susp(),
        "wings": wings,
        "extras": extras,
        "liv": auto_liv(body, pod, (1.25, 3.35)),
        "anchors": _anch(
            W18,
            (0, 0.84, 1.47),
            -0.3,
            (0.11, 0.70, 2.55),
            (0, 0.46, 4.17),
            (0, 0.7, 3.0),
            [(-0.56, 1.02, 4.45), (0.56, 1.02, 4.45)],
        ),
    }
    return open_wheeler("stl", S)


# ---------------------------------------------------------------------------
# NEON RACER: sci-fi - twin-prong nose, wide flat body, side blades, tall blade rear wing
# ---------------------------------------------------------------------------
def neonracer():
    body = {
        "cy": [
            (-0.25, 0.34),
            (-0.15, 0.36),
            (0.20, 0.40),
            (0.60, 0.42),
            (0.95, 0.43),
            (1.25, 0.43),
            (1.75, 0.43),
            (1.97, 0.46),
            (2.40, 0.45),
            (3.00, 0.42),
            (3.60, 0.37),
            (4.15, 0.33),
        ],
        "wt": [
            (-0.25, 0.10),
            (-0.15, 0.17),
            (0.20, 0.22),
            (0.60, 0.26),
            (0.95, 0.29),
            (1.25, 0.31),
            (1.75, 0.31),
            (1.97, 0.16),
            (2.40, 0.15),
            (3.00, 0.12),
            (3.60, 0.08),
            (4.15, 0.04),
        ],
        "wb": [
            (-0.25, 0.12),
            (-0.15, 0.20),
            (0.20, 0.26),
            (0.60, 0.31),
            (0.95, 0.34),
            (1.25, 0.36),
            (1.75, 0.36),
            (1.97, 0.36),
            (2.40, 0.33),
            (3.00, 0.25),
            (3.60, 0.14),
            (4.15, 0.05),
        ],
        "ht": [
            (-0.25, 0.04),
            (-0.15, 0.08),
            (0.20, 0.12),
            (0.60, 0.15),
            (0.95, 0.20),
            (1.25, 0.24),
            (1.75, 0.24),
            (1.97, 0.36),
            (2.40, 0.32),
            (3.00, 0.24),
            (3.60, 0.15),
            (4.15, 0.06),
        ],
        "hb": [
            (-0.25, 0.06),
            (-0.15, 0.10),
            (0.20, 0.16),
            (0.60, 0.22),
            (0.95, 0.30),
            (1.25, 0.32),
            (1.75, 0.32),
            (1.97, 0.35),
            (2.40, 0.34),
            (3.00, 0.32),
            (3.60, 0.27),
            (4.15, 0.07),
        ],
        "n": [(-0.25, 3.0), (1.75, 3.2), (1.97, 2.4), (4.15, 2.4)],
        **_dip(1.02, 1.9, 0.20),
    }
    pod = {
        "cx": [(1.10, 0.56), (1.25, 0.60), (2.20, 0.60), (3.00, 0.48), (3.40, 0.32)],
        "cy": [(1.10, 0.32), (1.25, 0.32), (2.20, 0.31), (3.00, 0.28), (3.40, 0.22)],
        "wt": [(1.10, 0.20), (1.25, 0.24), (2.20, 0.25), (3.00, 0.18), (3.40, 0.08)],
        "wb": [(1.10, 0.20), (1.25, 0.24), (2.20, 0.25), (3.00, 0.18), (3.40, 0.08)],
        "ht": [(1.10, 0.07), (1.25, 0.09), (2.20, 0.09), (3.00, 0.07), (3.40, 0.04)],
        "hb": [(1.10, 0.12), (1.25, 0.14), (2.20, 0.15), (3.00, 0.13), (3.40, 0.10)],
        "n": [(1.1, 3.6), (3.4, 2.8)],
    }

    def wings(d):
        def fn(x):
            t = abs(x) / 0.92
            return {"y": 0.10 + 0.08 * t**3, "z": -1.00 + 0.10 * t, "c": 0.30, "a": 6 + 6 * t}

        d.add("FrontWing", "Accent", P.wing_element(-0.92, 0.92, fn, stations=24, thick=0.07, camber=-0.05))
        d.add(
            "FrontWing",
            "Secondary",
            P.wing_element(
                -0.92,
                0.92,
                lambda x: {"y": 0.16 + 0.1 * (abs(x) / 0.92) ** 3, "z": -0.76, "c": 0.14, "a": 24},
                stations=24,
                thick=0.06,
                camber=-0.05,
            ),
        )
        for s in (1, -1):
            d.add(
                "FrontWing",
                "Primary",
                P.endplate(
                    [(-1.08, 0.03), (-0.58, 0.03), (-0.54, 0.36), (-0.70, 0.40), (-1.04, 0.20)], s * 0.93, 0.016
                ),
            )
        rw_elements(
            d,
            [(0.95, 3.98, 0.36, 9, "Accent"), (1.04, 4.27, 0.15, 26, "Secondary")],
            0.54,
            [(3.84, 0.40), (4.46, 0.52), (4.46, 1.14), (4.00, 1.14), (3.84, 0.70)],
            droop=0.0,
        )
        swan_necks(d, None, 0.10, 3.98, 0.40, 4.14, 0.93)

    def extras(d, b):
        # twin prongs (tusks) that carry the front wing
        tusk = Track(
            {
                "cy": [(-1.00, 0.19), (-0.60, 0.26), (-0.20, 0.34), (0.30, 0.40)],
                "wt": [(-1.00, 0.03), (-0.60, 0.05), (-0.20, 0.06), (0.30, 0.07)],
                "wb": [(-1.00, 0.03), (-0.60, 0.05), (-0.20, 0.06), (0.30, 0.07)],
                "ht": [(-1.00, 0.03), (-0.60, 0.05), (-0.20, 0.06), (0.30, 0.07)],
                "hb": [(-1.00, 0.04), (-0.60, 0.07), (-0.20, 0.08), (0.30, 0.09)],
                "n": [(-1.0, 2.4), (0.3, 2.4)],
            }
        )
        for s in (1, -1):
            rings = [
                superellipse_section(z, dict(tusk(z), cx=s * (0.20 - 0.02 * (z + 1.0))), 24)
                for z in P.zsamples(-1.00, 0.30, 0.05)
            ]
            sd, cp = P.loft_obj(rings)
            d.add("Body", "Primary", sd + cp[""])
            # side blade on the pod
            d.add(
                "RightPod" if s > 0 else "LeftPod",
                "Secondary",
                _mirrored(P.endplate([(1.30, 0.40), (2.60, 0.40), (3.10, 0.52), (1.60, 0.52)], 0.72, 0.014), s),
            )

    S = {
        "body": body,
        "body_z": (-0.25, 4.15),
        "dense": [(-0.25, -0.1, 0.02), (0.95, 1.2, 0.02), (1.75, 2.05, 0.02)],
        "cockpit": (0.19, 1.06, 1.88, 0.46),
        "tip_z": None,
        "pod": pod,
        "pod_z": (1.10, 3.40),
        "mirror": ((0.52, 0.66, 1.18), (0.32, 0.60, 1.24)),
        "floor": MOD_FLOOR,
        "intake": (0.09, 0.72, 0.84, 1.93),
        "tcam": (0, 0.84, 2.06),
        "tail": (0, 0.32, 4.165),
        "exhausts": [(-0.1, 0.42, 4.16, 0.035, 0.12), (0.1, 0.42, 4.16, 0.035, 0.12)],
        "halo": (0.98, 0.62, 0.90, 1.9, 0.28, 0.66),
        "suit": (0, 0.54, 1.52),
        "wheel_y": 0.36,
        "susp": _susp(hi_nose=0.42),
        "wings": wings,
        "extras": extras,
        "liv": auto_liv(body, pod, (1.10, 3.40), chev_z=0.0),
        "anchors": _anch(
            W18,
            (0, 0.79, 1.47),
            0.3,
            (0.17, 0.62, 2.6),
            (0, 0.42, 4.17),
            (0, 0.6, 3.0),
            [(-0.55, 1.1, 4.45), (0.55, 1.1, 4.45)],
        ),
    }
    return open_wheeler("neo", S)


# ---------------------------------------------------------------------------
# RETRO 90s: early-90s raised nose, droop (anhedral) front wing, big airbox, rounded pods
# ---------------------------------------------------------------------------
def r92():
    body = {
        # high "raised" nose with the gull-wing front wing slung underneath (1990-92)
        "cy": [
            (-0.90, 0.41),
            (-0.82, 0.42),
            (-0.50, 0.45),
            (-0.10, 0.48),
            (0.35, 0.49),
            (0.85, 0.48),
            (1.10, 0.48),
            (1.75, 0.48),
            (1.95, 0.53),
            (2.30, 0.51),
            (2.90, 0.45),
            (3.40, 0.39),
            (3.85, 0.35),
            (4.00, 0.34),
        ],
        "wt": [
            (-0.90, 0.07),
            (-0.82, 0.10),
            (-0.50, 0.13),
            (-0.10, 0.16),
            (0.35, 0.20),
            (0.85, 0.25),
            (1.10, 0.28),
            (1.75, 0.29),
            (1.95, 0.17),
            (2.30, 0.16),
            (2.90, 0.12),
            (3.40, 0.09),
            (3.85, 0.05),
            (4.00, 0.04),
        ],
        "wb": [
            (-0.90, 0.07),
            (-0.82, 0.10),
            (-0.50, 0.12),
            (-0.10, 0.15),
            (0.35, 0.21),
            (0.85, 0.29),
            (1.10, 0.31),
            (1.75, 0.32),
            (1.95, 0.33),
            (2.30, 0.31),
            (2.90, 0.24),
            (3.40, 0.15),
            (3.85, 0.08),
            (4.00, 0.05),
        ],
        "ht": [
            (-0.90, 0.05),
            (-0.82, 0.07),
            (-0.50, 0.09),
            (-0.10, 0.11),
            (0.35, 0.14),
            (0.85, 0.23),
            (1.10, 0.28),
            (1.75, 0.28),
            (1.95, 0.47),
            (2.30, 0.40),
            (2.90, 0.26),
            (3.40, 0.16),
            (3.85, 0.08),
            (4.00, 0.05),
        ],
        "hb": [
            (-0.90, 0.05),
            (-0.82, 0.07),
            (-0.50, 0.08),
            (-0.10, 0.10),
            (0.35, 0.18),
            (0.85, 0.33),
            (1.10, 0.35),
            (1.75, 0.35),
            (1.95, 0.40),
            (2.30, 0.38),
            (2.90, 0.32),
            (3.40, 0.27),
            (3.85, 0.20),
            (4.00, 0.08),
        ],
        "n": [(-0.9, 2.2), (0.85, 2.6), (1.75, 2.8), (1.95, 2.3), (4.0, 2.3)],
        **_dip(1.02, 1.88, 0.26),
    }
    pod = {
        "cx": [(1.10, 0.52), (1.20, 0.55), (2.20, 0.56), (2.90, 0.46), (3.30, 0.30)],
        "cy": [(1.10, 0.34), (1.20, 0.34), (2.20, 0.34), (2.90, 0.30), (3.30, 0.24)],
        "wt": [(1.10, 0.18), (1.20, 0.22), (2.20, 0.23), (2.90, 0.17), (3.30, 0.08)],
        "wb": [(1.10, 0.18), (1.20, 0.22), (2.20, 0.23), (2.90, 0.17), (3.30, 0.08)],
        "ht": [(1.10, 0.12), (1.20, 0.15), (2.20, 0.15), (2.90, 0.11), (3.30, 0.06)],
        "hb": [(1.10, 0.15), (1.20, 0.17), (2.20, 0.18), (2.90, 0.16), (3.30, 0.12)],
        "n": [(1.1, 2.3), (3.3, 2.3)],
    }

    def wings(d):
        def fn(x):
            t = abs(x) / 0.85
            return {"y": 0.31 - 0.24 * geo.smoothstep(0.12, 0.92, t), "z": -1.02, "c": 0.30, "a": 5}

        d.add("FrontWing", "Accent", P.wing_element(-0.85, 0.85, fn, stations=24, thick=0.07, camber=-0.04))

        def fn2(x):
            t = abs(x) / 0.85
            return {"y": 0.36 - 0.23 * geo.smoothstep(0.12, 0.92, t), "z": -0.80, "c": 0.16, "a": 22}

        for s in (1, -1):
            x0, x1 = (0.12, 0.85) if s > 0 else (-0.85, -0.12)
            d.add("FrontWing", "Secondary", P.wing_element(x0, x1, fn2, stations=16, thick=0.06, camber=-0.05))
            d.add(
                "FrontWing",
                "Primary",
                P.endplate([(-1.06, 0.03), (-0.62, 0.03), (-0.62, 0.22), (-1.02, 0.22)], s * 0.86, 0.016),
            )
        _plates(d, "FrontWing", "Carbon", [([(-1.0, 0.30), (-0.72, 0.33), (-0.70, 0.42), (-0.92, 0.40)], 0.07)])
        rw_elements(
            d,
            [(0.80, 3.62, 0.30, 12, "Accent"), (0.93, 3.66, 0.24, 16, "Accent"), (1.02, 3.88, 0.14, 30, "Secondary")],
            0.49,
            [(3.55, 0.12), (4.10, 0.12), (4.10, 1.08), (3.58, 1.08)],
            droop=0.0,
        )

    def extras(d, b):
        d.add("Body", "Glass", geo.plate(geo.rounded_rect(-0.20, 0.70, 0.20, 0.80, 0.04, 3), "xy", 1.00, 0.01))

    S = {
        "body": body,
        "body_z": (-0.90, 4.00),
        "dense": [(-0.90, -0.78, 0.02), (0.95, 1.2, 0.02), (1.72, 2.02, 0.02)],
        "cockpit": (0.19, 1.06, 1.84, 0.46),
        "tip_z": -0.72,
        "pod": pod,
        "pod_z": (1.10, 3.30),
        "mirror": ((0.44, 0.64, 1.02), (0.30, 0.57, 1.08)),
        "floor": {
            "half": [(0.0, 0.55), (0.65, 0.95), (0.78, 1.20), (0.80, 2.95), (0.55, 3.20), (0.48, 3.85)],
            "diffuser": (3.30, 3.95, 0.45, 0.30),
        },
        "intake": (0.11, 0.84, 1.02, 1.92),
        "tcam": None,
        "tail": (0, 0.34, 4.015),
        "exhausts": [(0.18, 0.28, 3.95, 0.05, 0.12), (-0.18, 0.28, 3.95, 0.05, 0.12)],
        "halo": None,
        "suit": (0, 0.58, 1.48),
        "wheel_y": 0.33,
        "susp": _susp(wy=0.33, fx=0.64, rx=0.60, hi_nose=0.46),
        "wings": wings,
        "extras": extras,
        "liv": auto_liv(body, pod, (1.10, 3.30), cover_z=(2.05, 3.4), cockpit=(1.04, 1.86)),
        "anchors": _anch(
            _wheels(0.77, 0.33, 0.28, 0.75, 0.33, 0.38, 3.45, "t13"),
            (0, 0.86, 1.45),
            -0.3,
            (0.11, 0.68, 2.5),
            (0.18, 0.28, 3.96),
            (0, 0.7, 2.9),
            [(-0.5, 1.08, 4.1), (0.5, 1.08, 4.1)],
        ),
    }
    return open_wheeler("r92", S)


# ---------------------------------------------------------------------------
# SIGNATURES: the one-look details that make every chassis unmistakable, each taken from
# a real F1 era (shapes only). pre(S) tweaks the spec before building; post(d, body, S)
# bolts parts on afterwards. Keyed by the name each design passes to open_wheeler.
# ---------------------------------------------------------------------------
def _set(keys, z, v):
    """Replace the value at z in a [(z, v), ...] key list."""
    for i, (kz, _) in enumerate(keys):
        if abs(kz - z) < 1e-6:
            keys[i] = (kz, v)
            return
    raise KeyError(z)


def _pod_top(S):
    """Height of the sidepod top along the car."""
    pod = Track(S["pod"])
    return lambda z: pod(z)["cy"] + pod(z)["ht"]


def _front_wheels(S, body):
    """The two front wheel anchors."""
    return S["anchors"](body)["wheels"][:2]


def _sig_aeros_post(d, body, S):
    """2022 "zero-pod": the mirrors sit on tall vanes growing out of the tiny sidepods."""
    for s in (1, -1):
        d.add(
            "RightPod" if s > 0 else "LeftPod",
            "Primary",
            _mirrored(P.endplate([(1.36, 0.60), (1.56, 0.60), (1.31, 0.85), (1.22, 0.85)], 0.36, 0.014), s),
        )
    for w in _front_wheels(S, body):
        if w["pos"][0] > 0:
            X.wheel_deflector(d, w)
    X.nose_cams(d, 0.16, 0.33, -0.35)
    X.pitot(d, 0.24, -0.80, 0.12)
    X.airbox_ears(d, 0.15, 0.84, 1.98)
    X.drs_pod(d, 0.935, 4.32)
    X.cockpit_rim(d, 0.2, 1.06, 1.88, 0.62)


def _sig_stealth_post(d, body, S):
    """Stealth jet: chined canards on the nose, a dorsal spine blade, angular pod strakes."""
    X.both(
        d,
        "Body",
        "Secondary",
        geo.plate([(0.13, -0.58), (0.34, -0.30), (0.34, -0.22), (0.13, -0.24)], "xz", 0.31, 0.02),
    )
    d.add("Body", "Accent", P.endplate([(2.0, 0.93), (2.25, 1.0), (3.9, 0.58), (3.9, 0.47), (2.1, 0.90)], 0, 0.014))
    X.both(
        d,
        "Body",
        "Secondary",
        P.endplate([(1.30, 0.37), (2.70, 0.30), (2.70, 0.335), (1.30, 0.41)], 0.79, 0.03),
        split_groups=True,
    )
    for w in _front_wheels(S, body):
        if w["pos"][0] > 0:
            X.wheel_deflector(d, w, slot="Accent")
    X.rear_light_bar(d, 0.30, 4.17, 0.30)


def _sig_nova_post(d, body, S):
    """Hypercar lighting: tail-light strips on the rear fenders, headlight blades up front."""
    X.both(d, "Body", "TailLight", geo.box((0.775, 0.49, 4.02), (0.34, 0.03, 0.03)))
    X.both(d, "Body", "Light", geo.box((0.80, 0.545, -0.385), (0.30, 0.022, 0.03)))
    X.rear_light_bar(d, 0.34, 4.17, 0.30)
    X.drs_pod(d, 0.975, 4.30)


def _sig_neon_post(d, body, S):
    """Walrus tusks with glowing fangs, a light bar, wheel deflectors."""
    X.both(d, "Body", "Light", geo.ellipsoid((0.20, 0.20, -1.0), (0.035, 0.03, 0.045), 12, 8))
    X.rear_light_bar(d, 0.32, 4.17, 0.30)
    for w in _front_wheels(S, body):
        if w["pos"][0] > 0:
            X.wheel_deflector(d, w, slot="Secondary")
    X.drs_pod(d, 1.09, 4.34)


def _sig_arrow_pre(S):
    """2017-18: a giant shark fin running into the rear wing."""
    S["fin"] = [(2.05, 0.93), (2.35, 1.03), (4.10, 1.01), (4.10, 0.55), (2.20, 0.85)]


def _sig_arrow_post(d, body, S):
    """Twin T-wing, "boomerang" wing over the pod, the nose "cape", gills."""
    top = _pod_top(S)
    X.t_wing(d, 0.80, 3.76, span=0.22, twin=True)
    for s in (1, -1):
        g = "RightPod" if s > 0 else "LeftPod"
        wing = P.wing_element(
            0.36, 0.72, lambda x: {"y": 0.80 + 0.03 * (x - 0.36), "z": 1.50, "c": 0.08, "a": 10}, stations=8
        )
        strut = P.endplate([(1.50, top(1.55) - 0.01), (1.62, top(1.60) - 0.01), (1.60, 0.82), (1.50, 0.82)], 0.72, 0.01)
        d.add(g, "Carbon", _mirrored(wing + strut, s))
    d.add("Body", "Carbon", geo.plate([(-0.12, -0.62), (0.12, -0.62), (0.12, 0.10), (-0.12, 0.10)], "xz", 0.15, 0.02))
    X.both(d, "Body", "Carbon", P.endplate([(-0.60, 0.15), (0.08, 0.15), (0.08, 0.32), (-0.60, 0.25)], 0.10, 0.01))
    X.louvres(d, 0.50, 2.20, 2.80, top, n=5, w=0.13)
    X.nose_cams(d, 0.13, 0.36, -0.30)
    X.pitot(d, 0.17, -0.98, 0.12)
    X.drs_pod(d, 0.98, 4.33, var="rwA")


def _sig_falcon_post(d, body, S):
    """2014 "finger" nose poking out past the front wing."""
    finger = geo.tube(
        geo.bezier([(0, 0.17, -0.96), (0, 0.16, -1.05), (0, 0.15, -1.13)], 6), lambda t: 0.032 - 0.012 * t, N=12
    )
    d.add("Body", "Secondary", finger)
    X.airbox_ears(d, 0.15, 0.88, 1.98)
    X.nose_cams(d, 0.15, 0.41, -0.40)
    X.drs_pod(d, 1.03, 4.36)


def _sig_viper_pre(S):
    """2012 "step" nose: a sheer step between the tall chassis and the low nose."""
    b = S["body"]
    _set(b["cy"], 0.00, 0.30)
    _set(b["cy"], 0.15, 0.50)
    _set(b["ht"], 0.15, 0.12)
    # a shark fin big enough to join the rear wing
    S["fin"] = [(2.00, 0.95), (2.30, 1.07), (4.02, 1.07), (4.02, 0.55), (2.15, 0.86)]


def _sig_viper_post(d, body, S):
    """F-duct snorkel on the nose, double-deck diffuser."""
    b = body(0.62)
    y = b["cy"] + b["ht"]
    d.add("Body", "Primary", geo.ellipsoid((0, y + 0.015, 0.62), (0.05, 0.035, 0.13), 14, 8))
    d.add("Body", "Dark", geo.plate(geo.rounded_rect(-0.035, y - 0.005, 0.035, y + 0.035, 0.015, 3), "xy", 0.50, 0.01))
    d.add("Body", "Carbon", geo.plate([(3.70, 0.30), (4.20, 0.44), (4.20, 0.47), (3.70, 0.33)], "zy", 0, 0.60))
    X.nose_cams(d, 0.13, 0.30, -0.40)
    X.drs_pod(d, 1.08, 4.34)


def _sig_vortex_post(d, body, S):
    """1988 turbo: NACA ducts on the long flat pods, a wastegate pipe, pod-top vents."""
    X.both(
        d,
        "Body",
        "Dark",
        geo.plate([(0.47, 1.62), (0.63, 1.62), (0.565, 1.30), (0.535, 1.30)], "xz", 0.425, 0.012),
        split_groups=True,
    )
    d.add(
        "Body",
        "Metal",
        geo.tube(geo.bezier([(0.12, 0.34, 3.50), (0.12, 0.46, 3.66), (0.12, 0.52, 3.80)], 6), 0.028, N=10),
    )
    X.louvres(d, 0.56, 2.30, 2.95, _pod_top(S), n=5, w=0.18)


def _sig_apex_post(d, body, S):
    """2006-08 winglet mania: horns, X-wing towers, chimneys, flip-ups, "twin tower" nose wing."""
    top = _pod_top(S)
    X.horn(d, 0.20, 0.40, 0.73, 0.80)
    X.x_wing(d, 0.52, 1.55, top(1.55) - 0.01, 0.88, span=0.10)
    X.chimney(d, 0.46, top(2.55) - 0.01, 2.55)
    X.flip_up(d, 0.56, 2.95, 0.40)
    b = body(0.40)
    y = b["cy"] + b["ht"]
    for s in (1, -1):
        d.add(
            "Body",
            "Carbon",
            P.endplate([(0.32, y - 0.02), (0.46, y - 0.02), (0.44, y + 0.13), (0.34, y + 0.13)], s * 0.09, 0.012),
        )
    d.add(
        "Body",
        "Carbon",
        P.wing_element(-0.24, 0.24, lambda x: {"y": y + 0.13, "z": 0.33, "c": 0.09, "a": 12}, stations=8),
    )
    X.drs_pod(d, 1.04, 4.02, var="rwA")


def _sig_aurora_post(d, body, S):
    """Jet canopy frame, delta canards, full-width light bar."""
    can = Track(
        {
            "cy": [(0.75, 0.62), (1.00, 0.65), (1.45, 0.66), (1.95, 0.64), (2.40, 0.60)],
            "ht": [(0.75, 0.02), (1.00, 0.22), (1.45, 0.34), (1.95, 0.27), (2.40, 0.04)],
            "wt": [(0.75, 0.10), (1.00, 0.20), (1.45, 0.23), (1.95, 0.20), (2.40, 0.08)],
            "wb": [(0.75, 0.12), (1.00, 0.23), (1.45, 0.26), (1.95, 0.23), (2.40, 0.10)],
            "hb": [(0.80, 0.02), (1.00, 0.04), (1.45, 0.05), (1.95, 0.04), (2.35, 0.02)],
            "n": [(0.75, 2.2), (2.40, 2.2)],
        }
    )
    spine = [(0, can(z)["cy"] + can(z)["ht"] + 0.008, z) for z in np.linspace(0.85, 2.30, 12)]
    d.add("Body", "Carbon", geo.tube(spine, 0.012, N=8))
    for z in (1.20, 1.75):
        c = can(z)
        arc = [
            (c["wt"] * math.sin(a) * 1.02, c["cy"] + c["ht"] * math.cos(a) * 1.02 + 0.004, z)
            for a in np.linspace(-1.35, 1.35, 11)
        ]
        d.add("Body", "Carbon", geo.tube(arc, 0.011, N=8))
    X.both(
        d,
        "Body",
        "Secondary",
        geo.plate([(0.15, -0.70), (0.36, -0.42), (0.36, -0.36), (0.15, -0.40)], "xz", 0.27, 0.018),
    )
    X.rear_light_bar(d, 0.30, 4.215, 0.36)


def _sig_retro70_post(d, body, S):
    """Open engine bay: eight intake trumpets on the V8, oil cooler over the gearbox."""
    for x in (-0.10, -0.035, 0.035, 0.10):
        for z in (2.95, 3.12):
            d.add(
                "Body",
                "Metal",
                geo.revolve(
                    [(0.0, 0.0), (0.0, 0.022), (0.06, 0.022), (0.075, 0.032), (0.075, 0.0)],
                    12,
                    "y",
                    center=(x, 0.41, z),
                ),
            )
    d.add("Body", "Dark", geo.box((0, 0.40, 3.66), (0.30, 0.04, 0.20)))


def _sig_retro90_post(d, body, S):
    """1990 high nose: TV camera pods on the nose flanks."""
    X.nose_cams(d, 0.12, 0.44, -0.30)


SIGNATURE = {
    "mod": (None, None),  # GT-1: 2026 spec, details are in modern() itself
    "aer": (None, _sig_aeros_post),
    "stl": (None, _sig_stealth_post),
    "nov": (None, _sig_nova_post),
    "neo": (None, _sig_neon_post),
    "hyb": (_sig_arrow_pre, _sig_arrow_post),
    "fal": (None, _sig_falcon_post),
    "vip": (_sig_viper_pre, _sig_viper_post),
    "r88": (None, _sig_vortex_post),
    "v10": (None, _sig_apex_post),
    "aur": (None, _sig_aurora_post),
    "r70": (None, _sig_retro70_post),
    "r92": (None, _sig_retro90_post),
}
