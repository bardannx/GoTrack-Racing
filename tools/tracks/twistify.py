"""Turn every circuit into a twistier version: simplify the centre line to a polygon,
round its corners tightly, and drop chicanes into long straights."""

import json, math, sys

sys.path.insert(0, ".")
from poly import pts as poly_pts


def dp(points, tol):
    """Simplifies an open polyline of (x, z, y) points (Douglas-Peucker, tolerance `tol`)."""
    if len(points) < 3:
        return points
    a, b = points[0], points[-1]
    ax, az = a[0], a[1]
    bx, bz = b[0], b[1]
    L = math.hypot(bx - ax, bz - az) or 1e-9
    best, bi = -1, 0
    for i in range(1, len(points) - 1):
        px, pz = points[i][0], points[i][1]
        d = abs((bx - ax) * (az - pz) - (ax - px) * (bz - az)) / L
        if d > best:
            best, bi = d, i
    if best > tol:
        return dp(points[: bi + 1], tol)[:-1] + dp(points[bi:], tol)
    return [a, b]


def turn(a, b, c):
    """Signed turn angle at b going from a to c."""
    v1 = (b[0] - a[0], b[1] - a[1])
    v2 = (c[0] - b[0], c[1] - b[1])
    ang = math.atan2(v1[0] * v2[1] - v1[1] * v2[0], v1[0] * v2[0] + v1[1] * v2[1])
    return abs(math.degrees(ang))


def twist(t, tol=0.9, chicane_len=15, sharp=1.0, seed=0):
    """A twistier version of one circuit: simplified centre line, tight corners, and a
    chicane on long straights.
    """
    P = [(x / 50, z / 50, y) for x, z, y in zip(t["x"], t["z"], t["y"])]
    # split the loop at the start (index 0) and half way so DP works on open lines
    n = len(P)
    h = n // 2
    A = dp(P[: h + 1], tol)
    B = dp(P[h:] + [P[0]], tol)
    V = A[:-1] + B[:-1]
    m = len(V)
    out = []
    side = 1 if seed % 2 == 0 else -1
    for i in range(m):
        a, b, c = V[i - 1], V[i], V[(i + 1) % m]
        if i == 0:
            out.append((b[0], b[1], b[2], 0))
        else:
            ang = turn(a, b, c)
            d = sharp if ang > 70 else (sharp * 1.35 if ang > 40 else (sharp * 1.9 if ang > 20 else 3.0))
            out.append((b[0], b[1], b[2], d))
        # chicane on long straights, never on the edges touching the start line
        L = math.hypot(c[0] - b[0], c[1] - b[1])
        if L > chicane_len and i != 0 and (i + 1) % m != 0:
            ux, uz = (c[0] - b[0]) / L, (c[1] - b[1]) / L
            nx, nz = -uz, ux
            mid = L * 0.5
            for s, off in ((mid - 2.2, 0), (mid - 0.7, 1.3 * side), (mid + 0.8, 1.3 * side), (mid + 2.3, 0)):
                px, pz = b[0] + ux * s + nx * off, b[1] + uz * s + nz * off
                py = b[2] + (c[2] - b[2]) * s / L
                out.append((px, pz, py, 0.8))
            side = -side
    return poly_pts(out)


if __name__ == "__main__":
    d = json.load(open("dense.json"))
    cfg = json.load(open(sys.argv[1])) if len(sys.argv) > 1 else {}
    res = {}
    for k, t in d.items():
        c = cfg.get(k, {})
        if c.get("skip"):
            continue
        res[k] = twist(
            t, tol=c.get("tol", 0.9), chicane_len=c.get("chicane", 15), sharp=c.get("sharp", 1.0), seed=len(k)
        )
    json.dump(res, open("twist_ov.json", "w"), indent=0)
    print(len(res), "circuits")
