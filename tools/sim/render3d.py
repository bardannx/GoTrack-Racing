#!/usr/bin/env python3
"""Real 3D picture of a circuit, rendered with Blender (bpy + Cycles) from the part dump
written by tools/sim/maps.luau --dump. Every Part / WedgePart / ball / cylinder of the
circuit becomes geometry with its own colour and a material look (glass, metal, neon...),
under a sky and sun that follow the circuit's time of day.

    lune run tools/sim/maps.luau 3 lakeside --dump
    python3 tools/sim/render3d.py lakeside [--views aerial,start,side] [--size 1280x720] [--samples 32]

Writes tools/sim/out/<id>_3d_<view>.png. Needs `pip install bpy numpy`.
"""

import json
import math
import sys
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parent / "out"

# Roblox material -> look class
ROUGH = {
    "Concrete",
    "Grass",
    "LeafyGrass",
    "Sand",
    "Slate",
    "Wood",
    "WoodPlanks",
    "Brick",
    "Asphalt",
    "Ground",
    "Rock",
    "Basalt",
    "Cobblestone",
    "Pebble",
    "Granite",
    "Limestone",
    "Mud",
    "Salt",
    "Sandstone",
    "Snow",
    "CrackedLava",
    "Pavement",
    "Fabric",
    "Marble",
    "Ice",
    "Glacier",
}
METAL = {"Metal", "DiamondPlate", "CorrodedMetal", "Foil"}


def look_of(p):
    """Which Blender material a part gets from its Roblox material and transparency."""
    m = p.get("m", "Plastic")
    t = p.get("t", 0) or 0
    if m == "Neon":
        return "neon"
    if m == "Glass" or (0.25 < t < 0.98):
        return "glass"
    if m in METAL:
        return "metal"
    if m in ROUGH:
        return "rough"
    return "smooth"


# unit primitives in Roblox axes (size 1), as (verts, faces)
def box():
    v = np.array([[x, y, z] for x in (-0.5, 0.5) for y in (-0.5, 0.5) for z in (-0.5, 0.5)])
    f = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
    return v, f


def wedge():
    """A unit Roblox WedgePart: full height at +Z, sloping down to the bottom front edge (-Z)."""
    v = np.array(
        [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5]]
    )
    f = [[0, 2, 3, 1], [2, 4, 5, 3], [0, 1, 5, 4], [0, 4, 2], [1, 3, 5]]
    return v, f


def cylinder(n=14):
    """A unit cylinder along X."""
    v = []
    for x in (-0.5, 0.5):
        for k in range(n):
            a = 2 * math.pi * k / n
            v.append([x, 0.5 * math.cos(a), 0.5 * math.sin(a)])
    v = np.array(v)
    f = [list(range(n))[::-1], list(range(n, 2 * n))]
    for k in range(n):
        f.append([k, (k + 1) % n, n + (k + 1) % n, n + k])
    return v, f


def sphere(nu=14, nv=8):
    """A unit UV sphere."""
    v = [[0, 0.5, 0]]
    for j in range(1, nv):
        ph = math.pi * j / nv
        for k in range(nu):
            th = 2 * math.pi * k / nu
            v.append([0.5 * math.sin(ph) * math.cos(th), 0.5 * math.cos(ph), 0.5 * math.sin(ph) * math.sin(th)])
    v.append([0, -0.5, 0])
    v = np.array(v)
    f = []
    for k in range(nu):
        f.append([0, 1 + (k + 1) % nu, 1 + k])
    for j in range(nv - 2):
        a0 = 1 + j * nu
        a1 = a0 + nu
        for k in range(nu):
            f.append([a0 + k, a0 + (k + 1) % nu, a1 + (k + 1) % nu, a1 + k])
    last = len(v) - 1
    a0 = 1 + (nv - 2) * nu
    for k in range(nu):
        f.append([last, a0 + k, a0 + (k + 1) % nu])
    return v, f


PRIMS = {"Block": box(), "Wedge": wedge(), "Cylinder": cylinder(), "Ball": sphere()}

# World meshes (tools/worldgen): MeshParts named <design>.<Slot>. Their geometry comes
# straight from the generator, centred on the manifest centre and unit-sized, so the
# part's Size scales it exactly like Roblox does.
_MESHES = {}


_WORLDGEN = []


def worldgen():
    """tools/worldgen/build, loaded on its own: tools/cargen has modules with the same names
    (build, designs), so a script that uses both (cargen/showcase.py) must not mix them."""
    if _WORLDGEN:
        return _WORLDGEN[0]
    names = ("build", "designs", "geom")
    saved = {k: sys.modules.pop(k) for k in names if k in sys.modules}
    wdir = str(Path(__file__).resolve().parents[1] / "worldgen")
    sys.path.insert(0, wdir)
    try:
        import build as wbuild  # noqa: E402
    finally:
        sys.path.remove(wdir)
        for k in names:
            sys.modules.pop(k, None)
        sys.modules.update(saved)
    _WORLDGEN.append(wbuild)
    return wbuild


def mesh_prim(name):
    """Real geometry for a Blender world mesh (rebuilt from tools/worldgen, cached)."""
    if name in _MESHES:
        return _MESHES[name]
    wbuild = worldgen()
    design, slot = name.split(".", 1)
    faces = wbuild.build(design).get(slot)
    if not faces:
        _MESHES[name] = None
        return None
    c, size = wbuild.bbox(faces)
    verts, fidx = wbuild.weld(faces)
    # Cycles shows both sides anyway: drop mirrored copies of double-sided faces
    seen, uniq = set(), []
    for f in fidx:
        key = tuple(sorted(f))
        if key not in seen:
            seen.add(key)
            uniq.append(f)
    fidx = uniq
    V = (np.array(verts) - c) / size
    # the FBX import turns meshes 180 degrees about Y (CarBuilder's MESH_FIX undoes it)
    V[:, 0] *= -1
    V[:, 2] *= -1
    _MESHES[name] = (V, fidx)
    return _MESHES[name]


def kind_of(p):
    """Which primitive a part is drawn with (block, wedge, cylinder, ball or a world mesh)."""
    if p.get("mesh"):
        return "Mesh:" + p["mesh"]
    if p.get("k") == "WedgePart":
        return "Wedge"
    s = p.get("s", "Block")
    if p.get("e"):
        return "Ball"  # SpecialMesh sphere: an ellipsoid scaled by the size
    return s if s in PRIMS else "Block"


def srgb_to_lin(c):
    """0-255 sRGB to linear colour."""
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


JITTER = 0.0  # studs of height between overlapping parts (showcase.py sets it)


def build_scene(data):
    """Turns every part of the dump into Blender geometry, one mesh per material look."""
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    groups = {}
    for p in data["parts"]:
        if (p.get("t", 0) or 0) >= 0.98:
            continue
        look = look_of(p)
        kind = kind_of(p)
        groups.setdefault(look, []).append((kind, p))

    def material(look):
        m = bpy.data.materials.new(look)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        attr = nt.nodes.new("ShaderNodeAttribute")
        attr.attribute_name = "col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        rough = {"rough": 0.85, "smooth": 0.45, "metal": 0.3, "glass": 0.05, "neon": 0.5}[look]
        bsdf.inputs["Roughness"].default_value = rough
        if look == "metal":
            bsdf.inputs["Metallic"].default_value = 0.8
        if look == "glass":
            bsdf.inputs["Alpha"].default_value = 0.45
            try:
                bsdf.inputs["Coat Weight"].default_value = 0.6
            except Exception:
                pass
        if look == "neon":
            nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 4.0
        if look == "smooth":
            try:
                bsdf.inputs["Coat Weight"].default_value = 0.2
            except Exception:
                pass
        return m

    for look, items in groups.items():
        verts_all, faces_all, cols = [], [], []
        base = 0
        for kind, p in items:
            if kind.startswith("Mesh:"):
                prim = mesh_prim(kind[5:])
                if not prim:
                    continue
                pv, pf = prim
            else:
                pv, pf = PRIMS[kind]
            size = np.array(p["z"], float)
            c = p["c"]
            pos = np.array(c[0:3], float)
            R = np.array(c[3:12], float).reshape(3, 3)
            w = (pv * size) @ R.T + pos  # Roblox world
            if JITTER:
                # parts that overlap exactly (road pieces, decals) share coplanar faces; Cycles
                # then shadows each with the other and they render black. A hair of height
                # per part separates them.
                w[:, 1] += JITTER * ((len(verts_all) * 7) % 11)
            wb = np.stack([w[:, 0], -w[:, 2], w[:, 1]], axis=1)  # Blender: x, -z, y
            verts_all.append(wb)
            faces_all.extend([[base + i for i in f] for f in pf])
            col = srgb_to_lin(np.array(p["col"], float))
            cols.extend([col] * len(pf))
            base += len(pv)
        if not verts_all:
            continue
        V = np.concatenate(verts_all)
        me = bpy.data.meshes.new(look)
        me.from_pydata(V.tolist(), [], faces_all)
        me.update()
        attr = me.attributes.new(name="col", type="FLOAT_COLOR", domain="FACE")
        flat = np.concatenate([np.append(c, 1.0) for c in cols]) if cols else np.zeros(0)
        attr.data.foreach_set("color", flat.astype(np.float32))
        ob = bpy.data.objects.new(look, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(material(look))
    return groups


def setup_world(data):
    """Sky, sun and exposure from the circuit's time of day."""
    import bpy
    import mathutils

    sc = bpy.context.scene
    sky = data.get("sky", {})
    clock = float(sky.get("clock", 14))
    night = bool(sky.get("night"))
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    # sun: elevation from the time of day
    elev = max(4.0, 62.0 * math.sin(math.pi * (clock - 6.0) / 12.0)) if not night else 20.0
    azim = 200.0 + (clock - 12.0) * 12.0
    if not night:
        try:
            tex = nt.nodes.new("ShaderNodeTexSky")
            try:
                tex.sky_type = "NISHITA"
            except Exception:
                pass
            tex.sun_elevation = math.radians(elev)
            tex.sun_rotation = math.radians(azim)
            nt.links.new(tex.outputs["Color"], bg.inputs["Color"])
            bg.inputs["Strength"].default_value = 0.12
        except Exception:
            bg.inputs["Color"].default_value = (0.5, 0.65, 0.85, 1)
    else:
        # the game's night races are floodlit dusk-blue (bright ambient), not pitch black
        amb = sky.get("ambient") or [0.55, 0.57, 0.72]
        bg.inputs["Color"].default_value = (amb[0] * 0.35, amb[1] * 0.35, amb[2] * 0.5, 1)
        bg.inputs["Strength"].default_value = 0.9
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.6 if not night else 0.9
    sun.angle = math.radians(1.5)
    if night:
        sun.color = (0.6, 0.7, 1.0)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = mathutils.Euler((math.radians(90 - elev), 0, math.radians(azim)), "XYZ")
    sc.collection.objects.link(so)
    sc.view_settings.view_transform = (
        "AgX" if hasattr(sc.view_settings, "view_transform") else sc.view_settings.view_transform
    )
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Punchy"
    except Exception:
        pass


def cameras(data):
    """The camera positions for each view (aerial, start, side, lap, panorama...)."""
    tr = np.array(data["track"], float)  # Roblox coords
    tb = np.stack([tr[:, 0], -tr[:, 2], tr[:, 1]], axis=1)
    lo, hi = tb.min(axis=0), tb.max(axis=0)
    centre = (lo + hi) / 2
    span = float(max(hi[0] - lo[0], hi[1] - lo[1]))
    views = {}
    # aerial 3/4 view of the whole circuit, looking towards its busiest side (like the intro)
    d = span * 0.95
    views["aerial"] = (centre + np.array([-d * 0.6, -d * 0.75, d * 0.62]), centre + np.array([0, 0, 0]), 30)
    if data.get("view") is not None:
        a = float(data["view"]) + math.pi  # camera opposite the busy side (Roblox x, z)
        off = np.array([math.cos(a) * d * 0.96, -math.sin(a) * d * 0.96, d * 0.62])  # Blender: (x, -z, up)
        views["aerial"] = (centre + off, centre + np.array([0, 0, 0]), 30)
    # low view from behind the grid, looking down the start straight
    p0 = tb[0]
    k = min(len(tb) - 1, 6)
    fwd = tb[k] - tb[0]
    fwd[2] = 0
    fwd /= max(np.linalg.norm(fwd), 1e-6)
    views["start"] = (p0 - fwd * 60 + np.array([0, 0, 14]), p0 + fwd * 160 + np.array([0, 0, 4]), 30)
    # side view from a quarter of the way round, looking across the infield
    q = tb[len(tb) // 4]
    to_c = centre - q
    to_c[2] = 0
    to_c /= max(np.linalg.norm(to_c), 1e-6)
    views["side"] = (q - to_c * 90 + np.array([0, 0, 40]), q + to_c * 200 + np.array([0, 0, 5]), 28)
    # the driver's view a third of the way round the lap (chase-cam height)
    j = len(tb) // 3
    ahead = tb[min(len(tb) - 1, j + 12)] - tb[j]
    ahead[2] = 0
    ahead /= max(np.linalg.norm(ahead), 1e-6)
    views["lap"] = (tb[j] - ahead * 24 + np.array([0, 0, 9]), tb[j] + ahead * 140 + np.array([0, 0, 6]), 24)
    # a high view from outside the circuit looking over it to the horizon
    views["panorama"] = (
        centre + np.array([-span * 0.9, -span * 0.35, span * 0.16]),
        centre + np.array([span * 0.4, span * 0.2, 0]),
        26,
    )
    return views


def render(data, views, size, samples):
    """Renders each view to tools/sim/out/<id>_3d_<view>.png."""
    import bpy
    import mathutils

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.device = "CPU"
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = size
    cam = bpy.data.cameras.new("cam")
    cam.clip_end = 30000
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    all_views = cameras(data)
    outs = []
    for name in views:
        if name not in all_views:
            continue
        pos, tgt, lens = all_views[name]
        cam.lens = lens
        co.location = tuple(pos)
        dv = mathutils.Vector(tuple(tgt)) - mathutils.Vector(tuple(pos))
        co.rotation_euler = dv.to_track_quat("-Z", "Y").to_euler()
        out = OUT / f"{data['id']}_3d_{name}.png"
        sc.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)
        outs.append(out)
    return outs


def main():
    """Command line: render3d.py <id ...> [--views a,b] [--size WxH] [--samples n]."""
    args = sys.argv[1:]
    ids, views, size, samples = [], ["aerial", "start", "side"], (1280, 720), 32
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--views":
            views = args[i + 1].split(",")
            i += 1
        elif a == "--size":
            w, h = args[i + 1].split("x")
            size = (int(w), int(h))
            i += 1
        elif a == "--samples":
            samples = int(args[i + 1])
            i += 1
        else:
            ids.append(a)
        i += 1
    for cid in ids:
        data = json.loads((OUT / f"{cid}.json").read_text())
        groups = build_scene(data)
        setup_world(data)
        n = sum(len(v) for v in groups.values())
        for out in render(data, views, size, samples):
            print(out, f"({n} parts)")


if __name__ == "__main__":
    main()
