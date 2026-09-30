"""Rounded-polygon -> control points string. verts: list of (x, z, y, d). First vertex is the
start/finish point (d ignored). Corners get two points at distance d before/after the vertex,
long edges get intermediate points so the spline stays straight."""
import math
def pts(verts, maxgap=6.0):
    n = len(verts); out = []
    def lerp(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
    for i in range(n):
        x, z, y, d = verts[i]
        P = (x, z, y)
        if i == 0:
            out.append(P)
        else:
            A = verts[i - 1][:3]; B = verts[(i + 1) % n][:3]
            la = math.dist(A[:2], P[:2]); lb = math.dist(P[:2], B[:2])
            da = min(d, la * 0.45); db = min(d, lb * 0.45)
            out.append(lerp(P, A, da / la))
            out.append(lerp(P, B, db / lb))
        # fill the straight to the next vertex
        B = verts[(i + 1) % n]
        a = out[-1]; b = (B[0], B[1], B[2])
        L = math.dist(a[:2], b[:2]) - B[3]
        k = int(L // maxgap)
        for j in range(1, k + 1):
            out.append(lerp(a, b, j * maxgap / math.dist(a[:2], b[:2])))
    return "; ".join("%g,%g,%g" % (round(p[0], 2), round(p[1], 2), round(p[2], 1)) for p in out)
