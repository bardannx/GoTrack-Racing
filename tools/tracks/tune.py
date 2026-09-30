"""python3 tune.py overrides.json [ids...] -> stats + plot of the given circuits with overridden points"""
import json, os, re, subprocess, sys
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
ov = json.load(open(sys.argv[1]))
ids = sys.argv[2:] or list(ov)
src = open(os.path.join(os.path.dirname(__file__), '../../src/shared/Circuits.luau')).read()
for k, pts in ov.items():
    src = re.sub(r'(Id = "%s".*?Points = ")[^"]*(")' % k, lambda m: m.group(1) + pts + m.group(2), src, flags=re.S)
open('Circuits.luau', 'w').write(src)
out = subprocess.run([os.environ.get('LUAU', 'luau'), 'dump.luau'], capture_output=True, text=True).stdout
d = json.loads(out)
fig, axs = plt.subplots(1, len(ids), figsize=(6 * len(ids), 6))
if len(ids) == 1: axs = [axs]
for ax, k in zip(axs, ids):
    t = d[k]; v = t['v']; n = len(v)
    def zones(th):
        z = 0; inz = False
        for x in v:
            if x < th and not inz: z += 1; inz = True
            elif x >= th: inz = False
        return z
    full = sum(1 for x in v if x >= 234) / n
    # self proximity check (road closer than 60 studs to a far part of the lap at similar index)
    xs, zs = t['x'], t['z']; close = 0
    for i in range(0, n, 2):
        for j in range(i + 30, n, 2):
            if min(j - i, n - (j - i)) > 30 and (xs[i]-xs[j])**2 + (zs[i]-zs[j])**2 < 75**2: close += 1
    print(f"{k:12s} slow<170:{zones(170)} <140:{zones(140)} minV:{min(v)} flat:{full*100:.0f}% close:{close} len:{n*16}")
    ax.scatter(xs, zs, c=v, cmap='RdYlGn', s=6, vmin=100, vmax=235)
    ax.plot(xs[0], zs[0], 'k^', ms=10)
    p = [list(map(float, c.split(',')[:2])) for c in ov.get(k, t['pts']).split(';')]
    ax.plot([a[0]*50 for a in p], [a[1]*50 for a in p], 'b.', ms=5)
    ax.set_title(k); ax.set_aspect('equal')
plt.tight_layout(); plt.savefig('tune.png', dpi=50)
