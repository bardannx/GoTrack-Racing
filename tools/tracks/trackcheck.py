#!/usr/bin/env python3
"""Checks every circuit layout in src/shared/Circuits.luau and draws preview images.

It copies the maths in src/shared/Track.luau (Catmull-Rom spline, 8-stud samples,
curvature, ideal speed profile) so the numbers match what the game builds.

    python3 tools/tracks/trackcheck.py              # check all circuits, write previews
    python3 tools/tracks/trackcheck.py sakura alpine # only these
    python3 tools/tracks/trackcheck.py --no-images

Checks (a FAIL means the circuit will look or drive broken in game):
  * tightest corner radius is at least MIN_RADIUS studs (the road folds over itself below that)
  * no two far-apart parts of the lap come closer than MIN_GAP studs unless one is a bridge
    at least BRIDGE_CLEAR studs higher (otherwise roads, kerbs and walls overlap)
  * the start/finish straight is straight enough for the grid, gantry and pit lane
  * slopes stay drivable
Info: corner count, lap length, ideal lap time and race laps.
Previews go to tools/tracks/out/ (git-ignored), plus an overview sheet all.png.
"""

import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CIRCUITS = os.path.join(ROOT, "src", "shared", "Circuits.luau")
OUT = os.path.join(ROOT, "tools", "tracks", "out")

DS = 8
UNIT = 50
PROFILE = dict(TopSpeed=235, LateralAccel=240, Accel=80, Brake=150)
RACE_TARGET = 180

MIN_RADIUS = 42
MIN_GAP_EXTRA = 70  # studs of grass/barrier between the two road edges
BRIDGE_CLEAR = 18
MAX_SLOPE = 0.26
START_WINDOW = (-440, 380)  # pit lane + grid, studs around the line
START_MAX_K = 1 / 700
CORNER_K = 1 / 260  # tighter than this counts as a corner


def parse_circuits(path):
    """Reads every circuit definition out of Circuits.luau."""
    src = open(path, encoding="utf-8").read()
    out = []
    for block in re.finditer(r"\n\t\{\n(.*?)\n\t\},", src, re.S):
        body = block.group(1)
        cid = re.search(r"Id = \"(\w+)\"", body)
        if not cid:
            continue
        width = re.search(r"Width = (\d+)", body)
        name = re.search(r"Name = \"([^\"]+)\"", body)
        corners = re.search(r"Corners = \"([^\"]+)\"", body)
        points = re.search(r"Points = \"([^\"]+)\"", body)
        out.append(
            dict(
                id=cid.group(1),
                name=name.group(1) if name else cid.group(1),
                corners=corners.group(1) if corners else None,
                points=points.group(1) if points else None,
                width=int(width.group(1)) if width else 40,
            )
        )
    return out


DEFAULT_RADIUS = 90


def expand_corners(s):
    """Same as Track.ExpandCorners in Track.luau. Also returns per-corner notes."""
    wps = []
    for chunk in s.split(";"):
        m = re.match(r"^(.*?)@\s*([\d.]+)", chunk.strip())
        body, r = (m.group(1), float(m.group(2))) if m else (chunk, DEFAULT_RADIUS)
        nums = [float(n) for n in re.findall(r"-?[\d.]+", body)]
        if len(nums) >= 2:
            wps.append(dict(x=nums[0] * UNIT, z=nums[1] * UNIT, y=nums[2] if len(nums) > 2 else 0.0, r=r))
    m = len(wps)
    arcs, notes = [], []
    for i in range(m):
        p, a, c = wps[(i - 1) % m], wps[i], wps[(i + 1) % m]
        ax, az = a["x"] - p["x"], a["z"] - p["z"]
        bx, bz = c["x"] - a["x"], c["z"] - a["z"]
        la, lb = math.hypot(ax, az), math.hypot(bx, bz)
        ax, az, bx, bz = ax / la, az / la, bx / lb, bz / lb
        cross = ax * bz - az * bx
        theta = math.acos(max(-1, min(1, ax * bx + az * bz)))
        if theta < 0.01:
            arcs.append([(a["x"], a["z"])])
            continue
        want = a["r"] * math.tan(theta / 2)
        tl = min(want, la * 0.5, lb * 0.5)
        r = tl / math.tan(theta / 2)
        if tl < want - 1:
            notes.append(
                f"corner {i + 1} ({a['x'] / UNIT:g},{a['z'] / UNIT:g}) squeezed: radius {a['r']:.0f} -> {r:.0f} (points too close)"
            )
        s = 1 if cross >= 0 else -1
        sx, sz = a["x"] - ax * tl, a["z"] - az * tl
        cx, cz = sx - az * s * r, sz + ax * s * r
        a0 = math.atan2(sz - cz, sx - cx)
        steps = max(2, math.ceil(theta * r / 30))
        arcs.append(
            [
                (cx + math.cos(a0 + s * theta * k / steps) * r, cz + math.sin(a0 + s * theta * k / steps) * r)
                for k in range(steps + 1)
            ]
        )
    out, mids = [], []
    for i in range(m):
        pts = arcs[i]
        mids.append(len(out) + len(pts) // 2)
        out.extend([[q[0], 0.0, q[1]] for q in pts])
        last, nxt = pts[-1], arcs[(i + 1) % m][0]
        dx, dz = nxt[0] - last[0], nxt[1] - last[1]
        n = int(math.hypot(dx, dz) // 150)
        for k in range(1, n + 1):
            f = k / (n + 1)
            out.append([last[0] + dx * f, 0.0, last[1] + dz * f])
    total = len(out)
    cum = [0.0]
    for i in range(1, total + 1):
        a, b = out[i - 1], out[i % total]
        cum.append(cum[-1] + math.hypot(b[0] - a[0], b[2] - a[2]))
    lap = cum[total]
    for i in range(m):
        j = (i + 1) % m
        s0, s1 = cum[mids[i]], cum[mids[j]]
        if s1 <= s0:
            s1 += lap
        y0, y1 = wps[i]["y"], wps[j]["y"]
        k = mids[i]
        while True:
            s = cum[k]
            if s < s0:
                s += lap
            out[k][1] = y0 + (y1 - y0) * max(0, min(1, (s - s0) / max(s1 - s0, 1e-6)))
            k = (k + 1) % total
            if k == mids[j]:
                break
    return [tuple(p) for p in out], notes


def parse_points(s):
    """Control points from a circuit's Points string."""
    pts = []
    for chunk in s.split(";"):
        nums = [float(n) for n in re.findall(r"-?[\d.]+", chunk)]
        if len(nums) >= 2:
            pts.append((nums[0] * UNIT, nums[2] if len(nums) > 2 else 0.0, nums[1] * UNIT))
    return pts


def catmull(p0, p1, p2, p3, t):
    """A point on a centripetal Catmull-Rom segment (the same spline Track.luau uses)."""

    def d(a, b):
        return max(math.sqrt(math.sqrt(sum((b[k] - a[k]) ** 2 for k in range(3)))), 1e-4)

    t0 = 0
    t1 = t0 + d(p0, p1)
    t2 = t1 + d(p1, p2)
    t3 = t2 + d(p2, p3)
    tt = t1 + (t2 - t1) * t
    out = []
    for k in range(3):
        a1 = (t1 - tt) / (t1 - t0) * p0[k] + (tt - t0) / (t1 - t0) * p1[k]
        a2 = (t2 - tt) / (t2 - t1) * p1[k] + (tt - t1) / (t2 - t1) * p2[k]
        a3 = (t3 - tt) / (t3 - t2) * p2[k] + (tt - t2) / (t3 - t2) * p3[k]
        b1 = (t2 - tt) / (t2 - t0) * a1 + (tt - t0) / (t2 - t0) * a2
        b2 = (t3 - tt) / (t3 - t1) * a2 + (tt - t1) / (t3 - t1) * a3
        out.append((t2 - tt) / (t2 - t1) * b1 + (tt - t1) / (t2 - t1) * b2)
    return out


def smooth(arr, radius, passes):
    """Moving-average smoothing over a loop, `passes` times."""
    n = len(arr)
    for _ in range(passes):
        c = arr[:]
        for i in range(n):
            arr[i] = sum(c[(i + o) % n] for o in range(-radius, radius + 1)) / (2 * radius + 1)


def build(defn):
    """The centre line of a circuit: spline samples, heights, curvature and speed profile."""
    notes = []
    if defn.get("corners"):
        ctrl, notes = expand_corners(defn["corners"])
    else:
        ctrl = parse_points(defn["points"])
    m = len(ctrl)
    dense = []
    for i in range(m):
        p0, p1, p2, p3 = ctrl[(i - 1) % m], ctrl[i], ctrl[(i + 1) % m], ctrl[(i + 2) % m]
        for s in range(40):
            dense.append(catmull(p0, p1, p2, p3, s / 40))
    nd = len(dense)
    cum = [0.0]
    for i in range(1, nd + 1):
        a, b = dense[i - 1], dense[i % nd]
        cum.append(cum[-1] + math.dist(a, b))
    total = cum[-1]
    n = int(total // DS)
    ds = total / n
    X, Y, Z = [0.0] * n, [0.0] * n, [0.0] * n
    j = 0
    for i in range(n):
        target = i * ds
        while cum[j + 1] < target:
            j += 1
        a, b = dense[j], dense[(j + 1) % nd]
        seg = cum[j + 1] - cum[j]
        t = (target - cum[j]) / seg if seg > 0 else 0
        X[i] = a[0] + (b[0] - a[0]) * t
        Y[i] = a[1] + (b[1] - a[1]) * t
        Z[i] = a[2] + (b[2] - a[2]) * t
    smooth(Y, 10, 3)
    TX, TY, TZ = [0.0] * n, [0.0] * n, [0.0] * n
    for i in range(n):
        ip, inx = (i - 1) % n, (i + 1) % n
        dx, dy, dz = X[inx] - X[ip], Y[inx] - Y[ip], Z[inx] - Z[ip]
        ln = math.sqrt(dx * dx + dy * dy + dz * dz)
        TX[i], TY[i], TZ[i] = dx / ln, dy / ln, dz / ln
    K = [0.0] * n
    for i in range(n):
        ip, inx = (i - 2) % n, (i + 2) % n
        ax, az, bx, bz = TX[ip], TZ[ip], TX[inx], TZ[inx]
        la, lb = math.hypot(ax, az), math.hypot(bx, bz)
        ax, az, bx, bz = ax / la, az / la, bx / lb, bz / lb
        cross = ax * bz - az * bx
        dot = max(-1, min(1, ax * bx + az * bz))
        K[i] = (1 if cross >= 0 else -1) * math.acos(dot) / (4 * ds)
    smooth(K, 2, 1)
    P = PROFILE
    V = [min(P["TopSpeed"], math.sqrt(P["LateralAccel"] / abs(k))) if abs(k) > 1e-6 else P["TopSpeed"] for k in K]
    for _ in range(3):
        for i in range(n - 1, -1, -1):
            nx = (i + 1) % n
            V[i] = min(V[i], math.sqrt(V[nx] ** 2 + 2 * P["Brake"] * ds))
        for i in range(n):
            pv = V[(i - 1) % n]
            r = pv / P["TopSpeed"]
            acc = P["Accel"] * (1 - r * r * 0.8)
            V[i] = min(V[i], math.sqrt(pv * pv + 2 * acc * ds))
    lap = sum(ds / v for v in V)
    laps = max(2, min(6, math.floor(RACE_TARGET / (lap * 1.12) + 0.5)))
    return dict(n=n, ds=ds, length=total, X=X, Y=Y, Z=Z, TY=TY, K=K, V=V, lap=lap, laps=laps, ctrl=ctrl, notes=notes)


def analyse(defn, t):
    """Runs the checks on one circuit. Returns the fails and warnings, plus stats: tightest
    radius, corner count, longest straight and the closest gap between two bits of road."""
    n, ds, X, Y, Z, K = t["n"], t["ds"], t["X"], t["Y"], t["Z"], t["K"]
    W = defn["width"]
    fails, warns = [], list(t["notes"])

    kmax = max(abs(k) for k in K)
    rmin = 1 / kmax
    if rmin < MIN_RADIUS:
        i = max(range(n), key=lambda i: abs(K[i]))
        fails.append(f"corner too tight: radius {rmin:.0f} studs at ({X[i] / UNIT:.1f},{Z[i] / UNIT:.1f})")

    # clearance between far-apart parts of the lap
    gap = W + MIN_GAP_EXTRA
    skip = int((gap * 2.6) / ds) + 6  # samples along the lap that count as "the same corner"
    cell = 80
    grid = {}
    for i in range(n):
        grid.setdefault((int(X[i] // cell), int(Z[i] // cell)), []).append(i)
    worst = {}
    for i in range(0, n, 2):
        cx, cz = int(X[i] // cell), int(Z[i] // cell)
        for gx in range(cx - 2, cx + 3):
            for gz in range(cz - 2, cz + 3):
                for o in grid.get((gx, gz), ()):
                    di = abs(o - i)
                    di = min(di, n - di)
                    if di <= skip:
                        continue
                    d = math.hypot(X[o] - X[i], Z[o] - Z[i])
                    if d < gap and abs(Y[o] - Y[i]) < BRIDGE_CLEAR:
                        key = (round(X[i] / 150), round(Z[i] / 150))
                        if key not in worst or d < worst[key][0]:
                            worst[key] = (d, i, o)
    for d, i, o in sorted(worst.values())[:4]:
        fails.append(
            f"roads too close: {d:.0f} studs (need {gap}) between ({X[i] / UNIT:.1f},{Z[i] / UNIT:.1f}) and ({X[o] / UNIT:.1f},{Z[o] / UNIT:.1f}), height diff {abs(Y[o] - Y[i]):.0f}"
        )

    # start straight
    bad = 0
    for s in range(START_WINDOW[0], START_WINDOW[1], DS):
        i = int((s % t["length"]) / ds) % n
        if abs(K[i]) > START_MAX_K:
            bad = max(bad, abs(K[i]))
    if bad:
        fails.append(f"start/finish area not straight (radius {1 / bad:.0f} studs near the line)")

    slope = max(abs(v) for v in t["TY"])
    if slope > MAX_SLOPE:
        warns.append(f"steep: slope {slope * 100:.0f}%")

    # corners: runs of samples tighter than CORNER_K, merged when close
    corners = []
    inside = False
    for i in range(n):
        tight = abs(K[i]) > CORNER_K
        if tight and not inside:
            if corners and i - corners[-1][1] < 6 and (K[i] > 0) == (K[corners[-1][1]] > 0):
                corners[-1][1] = i
            else:
                corners.append([i, i])
            inside = True
        elif tight:
            corners[-1][1] = i
        else:
            inside = False
    if len(corners) > 1 and corners[0][0] == 0 and corners[-1][1] == n - 1:
        corners.pop()
    longest = 0
    run = 0
    for i in range(2 * n):
        if abs(K[i % n]) < 1 / 900:
            run += 1
            longest = max(longest, run)
        else:
            run = 0
    return dict(fails=fails, warns=warns, rmin=rmin, corners=len(corners), longest=min(longest, n) * ds, gap=gap)


def speed_colour(v):
    """Red (slow) through yellow to green (fast), for the preview picture."""
    a = max(0.0, min(1.0, (v - 60) / (235 - 60)))
    if a < 0.5:
        return (230, int(60 + 360 * a), 50)
    return (int(230 - 400 * (a - 0.5)), 220, 60)


def draw(defn, t, res, size=900):
    """Preview picture of a circuit coloured by speed."""
    from PIL import Image, ImageDraw

    X, Z, V = t["X"], t["Z"], t["V"]
    minx, maxx, minz, maxz = min(X), max(X), min(Z), max(Z)
    pad = 120
    span = max(maxx - minx, maxz - minz) + pad * 2
    sc = (size - 40) / span

    def P(x, z):
        return (
            20 + (x - minx + pad + (span - (maxx - minx) - 2 * pad) / 2) * sc,
            60 + (z - minz + pad + (span - (maxz - minz) - 2 * pad) / 2) * sc,
        )

    img = Image.new("RGB", (size, size + 40), (22, 26, 38))
    d = ImageDraw.Draw(img)
    n = t["n"]
    W = defn["width"]
    order = sorted(range(n), key=lambda i: t["Y"][i])
    for i in order:
        j = (i + 1) % n
        d.line([P(X[i], Z[i]), P(X[j], Z[j])], fill=(12, 14, 20), width=max(2, int((W + 30) * sc)))
        d.line([P(X[i], Z[i]), P(X[j], Z[j])], fill=speed_colour(V[i]), width=max(2, int(W * sc)))
    sx, sz = P(X[0], Z[0])
    d.ellipse([sx - 7, sz - 7, sx + 7, sz + 7], fill=(255, 255, 255))
    ax, az = P(X[6], Z[6])
    d.line([(sx, sz), (ax, az)], fill=(255, 255, 255), width=3)
    status = "OK" if not res["fails"] else "FAIL"
    head = f"{defn['name']}  [{status}]  {t['length']:.0f} studs  lap {t['lap']:.1f}s  x{t['laps']}  corners {res['corners']}  min r {res['rmin']:.0f}"
    d.text((12, 10), head, fill=(255, 255, 255))
    y = 26
    for f in res["fails"][:2]:
        d.text((12, y), f, fill=(255, 110, 110))
        y += 14
    return img


def main():
    """Command line: trackcheck.py [ids ...] [--no-images]."""
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    images = "--no-images" not in sys.argv
    defs = parse_circuits(CIRCUITS)
    if args:
        defs = [c for c in defs if c["id"] in args]
    if images:
        os.makedirs(OUT, exist_ok=True)
    thumbs = []
    nfail = 0
    for c in defs:
        t = build(c)
        r = analyse(c, t)
        ok = not r["fails"]
        nfail += 0 if ok else 1
        print(
            f"{'OK  ' if ok else 'FAIL'} {c['id']:12s} len {t['length']:6.0f}  lap {t['lap']:5.1f}s x{t['laps']}  corners {r['corners']:2d}  "
            f"min r {r['rmin']:4.0f}  longest straight {r['longest']:5.0f}"
        )
        for f in r["fails"]:
            print("       - " + f)
        for w in r["warns"]:
            print("       ~ " + w)
        if images:
            img = draw(c, t, r)
            img.save(os.path.join(OUT, c["id"] + ".png"))
            thumbs.append(img.resize((450, 470)))
    if images and thumbs:
        from PIL import Image

        cols = 6
        rows = math.ceil(len(thumbs) / cols)
        sheet = Image.new("RGB", (cols * 450, rows * 470), (10, 12, 18))
        for k, im in enumerate(thumbs):
            sheet.paste(im, ((k % cols) * 450, (k // cols) * 470))
        sheet.save(os.path.join(OUT, "all.png"))
    print(f"\n{len(defs) - nfail}/{len(defs)} circuits pass")
    sys.exit(1 if nfail else 0)


if __name__ == "__main__":
    main()
