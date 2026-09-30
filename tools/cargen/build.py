"""Build car meshes: preview renders and FBX export for Roblox.

  python3 build.py render <design> <pattern|none> <out.png> [view] [variants]
  python3 build.py sheet <design> <out.png> [pattern|none]   (4 views, in-game colours)
  python3 build.py export <out.fbx> <manifest.json> [designs|all] [True|False|new]
      designs: comma list of design codes (e.g. "myc,aer") or "all"
      last arg: include shared wheel/helmet parts (True), skip them (False),
                or only the newer shared parts (new: steering wheels + headrest)
"""
import json
import math
import sys
import time

import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import geo
import designs
import wheels

RIM_STYLES = ["classic", "spoke", "star", "turbine", "blade", "mesh", "dish"]
# design code (= chassis id in the game) -> builder. Mesh names start with the code.
# (The first generation used short codes - mod, aer, hyb... - and those meshes stay in
# assets/cars/manifest.json as a fallback until the new ones are imported in Studio.)
DESIGNS = {
    "gt1": designs.modern, "aeros": designs.aeros, "stealth": designs.stealth, "nova": designs.nova,
    "neonracer": designs.neonracer, "arrow": designs.hybrid, "falcon": designs.falcon, "viper": designs.viper,
    "vortex": designs.r88, "apex": designs.v10, "aurora": designs.aurora, "retro70": designs.r70, "retro90": designs.r92,
}


def _build_design(dn):
    return DESIGNS[dn]()


def collect(names=None, shared=True):
    """Returns (objects {name: polys in studs}, anchors {design: {...}})."""
    objs = {}
    anchors = {}
    todo = [dn for dn in DESIGNS if not names or dn in names]
    built = {}
    if len(todo) > 1:
        from concurrent.futures import ProcessPoolExecutor

        with ProcessPoolExecutor(2) as ex:
            for dn, d in zip(todo, ex.map(_build_design, todo)):
                built[dn] = d
    for dn in todo:
        t = time.time()
        d = built.get(dn) or DESIGNS[dn]()
        conv = lambda polys: [np.array([designs.to_studs(v) for v in p]) for p in polys]
        for (g, s), polys in d.objs.items():
            objs[f"{dn}.{g}.{s}"] = conv(polys)
        for key, parts in d.variants.items():
            for (g, s), polys in parts.items():
                objs[f"{dn}.v.{key}.{g}.{s}"] = conv(polys)
        for key, groups in d.pats.items():
            for g, polys in groups.items():
                objs[f"{dn}.p.{key}.{g}"] = conv(polys)
        a = d.anchors
        A = {}
        A["wheels"] = []
        for w in a["wheels"]:
            p = designs.to_studs(w["pos"])
            A["wheels"].append({"pos": list(map(float, p)), "r": w["r"] * designs.SY, "w": w["w"] * designs.SX, "tyre": w["tyre"]})
        for k in ("head", "exhaust", "engine"):
            A[k] = list(map(float, designs.to_studs(a[k])))
        A["trail"] = [list(map(float, designs.to_studs(p))) for p in a["trail"]]
        A["numberNose"] = {"pos": list(map(float, designs.to_studs(a["numberNose"]["pos"]))), "size": [a["numberNose"]["size"][0] * designs.SX, a["numberNose"]["size"][1] * designs.SZ], "pitch": a["numberNose"]["pitch"]}
        A["numberSide"] = {"pos": list(map(float, designs.to_studs(a["numberSide"]["pos"]))), "size": [a["numberSide"]["size"][0] * designs.SZ, a["numberSide"]["size"][1] * designs.SY]}
        if a.get("flap"):
            A["flap"] = {k: list(map(float, designs.to_studs(v))) for k, v in a["flap"].items()}
        ug = a["underglow"]
        A["underglow"] = {"pos": list(map(float, designs.to_studs(ug["pos"]))), "size": [ug["size"][0] * designs.SX, ug["size"][1] * designs.SZ]}
        anchors[dn] = A
        print(f"design {dn}: {time.time() - t:.1f}s", file=sys.stderr)
    if shared == "new":
        body, grips, screen, leds, buttons = wheels.steering_modern()
        objs["sw.body"], objs["sw.grip"], objs["sw.screen"], objs["sw.led"], objs["sw.button"] = body, grips, screen, leds, buttons
        ring, spokes, hub = wheels.steering_round()
        objs["swr.ring"], objs["swr.spokes"], objs["swr.hub"] = ring, spokes, hub
        objs["h2.headrest"] = wheels.headrest()
        return objs, anchors
    if not shared:
        return objs, anchors
    # shared wheel parts (already unit sized)
    objs["w.tyre18"] = wheels.tyre(0.64)
    objs["w.tyre13"] = wheels.tyre(0.47, 0.09)
    objs["w.comp18"] = wheels.compound_ring(0.73, 0.79)
    objs["w.comp13"] = wheels.compound_ring(0.66, 0.74)
    objs["w.grooves"] = wheels.tread_grooves()
    objs["w.barrel"] = wheels.rim_barrel()
    objs["w.back"] = wheels.rim_back()
    objs["w.hub"] = wheels.rim_hub()
    for st in RIM_STYLES:
        objs["w.rim." + st] = wheels.rim_style(st)
    objs["w.neonring"] = wheels.neon_ring()
    sh, st, vi = wheels.helmet()
    objs["h.shell"], objs["h.stripe"], objs["h.visor"] = sh, st, vi
    return objs, anchors


def weld(polys, tol=1e-4):
    idx = {}
    verts = []
    faces = []
    for p in polys:
        f = []
        for v in p:
            k = (round(v[0] / tol), round(v[1] / tol), round(v[2] / tol))
            if k not in idx:
                idx[k] = len(verts)
                verts.append((float(v[0]), float(v[1]), float(v[2])))
            i = idx[k]
            if not f or f[-1] != i:
                f.append(i)
        if len(f) > 1 and f[0] == f[-1]:
            f.pop()
        if len(set(f)) >= 3 and len(set(f)) == len(f):
            faces.append(f)
    return verts, faces


def bbox(polys):
    allv = np.concatenate([np.asarray(p) for p in polys])
    lo, hi = allv.min(axis=0), allv.max(axis=0)
    return (lo + hi) / 2, hi - lo


# ---------------------------------------------------------------------------
# Blender side
# ---------------------------------------------------------------------------
def bl():
    import bpy

    return bpy


def make_object(name, polys, collection, center=True):
    bpy = bl()
    c, size = bbox(polys)
    verts, faces = weld(polys)
    if center:
        verts = [(v[0] - c[0], v[1] - c[1], v[2] - c[2]) for v in verts]
    # Roblox (X, Y, Z) -> Blender (X, -Z, Y)
    bverts = [(v[0], -v[2], v[1]) for v in verts]
    me = bpy.data.meshes.new(name)
    me.from_pydata(bverts, [], faces)
    me.validate()
    me.update()
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(34))
    except Exception:
        pass
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    if center:
        ob.location = (c[0], -c[2], c[1])
    return ob, c, size, len(me.polygons)


def slot_of(name):
    parts = name.split(".")
    if parts[0] in ("w", "h"):
        return parts[-1] if parts[0] == "h" else {"tyre18": "Tyre", "tyre13": "Tyre", "comp18": "Comp", "comp13": "Comp", "grooves": "Dark", "back": "Dark", "hub": "Hub", "neonring": "Neon"}.get(parts[1], "Rim")
    if parts[1] == "p":
        key = parts[2]
        return {"checkA": "White", "checkB": "Black", "flame1": "Flame1", "flame2": "Flame2", "flame3": "Flame3", "retroB": "Accent", "circuit": "Neon", "chevron": "Secondary"}.get(key, "Secondary")
    return parts[-1]


PREVIEW = {
    "Primary": (0.75, 0.04, 0.06, 0.25),
    "Secondary": (0.92, 0.92, 0.92, 0.3),
    "Accent": (0.03, 0.03, 0.035, 0.35),
    "Carbon": (0.018, 0.018, 0.02, 0.45),
    "Halo": (0.018, 0.018, 0.02, 0.45),
    "Dark": (0.004, 0.004, 0.005, 0.6),
    "Glass": (0.02, 0.03, 0.05, 0.05),
    "Metal": (0.5, 0.5, 0.52, 0.25),
    "TailLight": (1.0, 0.05, 0.05, 0.3),
    "Light": (0.92, 0.96, 1.0, 0.2),
    "TCam": (1.0, 0.8, 0.0, 0.3),
    "Suit": (0.6, 0.03, 0.05, 0.7),
    "Canopy": (0.05, 0.08, 0.14, 0.03),
    "Tyre": (0.02, 0.02, 0.022, 0.8),
    "Comp": (0.9, 0.05, 0.05, 0.6),
    "Rim": (0.03, 0.03, 0.035, 0.3),
    "Hub": (0.8, 0.1, 0.1, 0.3),
    "Neon": (0.0, 1.0, 0.9, 0.3),
    "White": (0.95, 0.95, 0.95, 0.3),
    "Black": (0.01, 0.01, 0.01, 0.3),
    "Flame1": (1.0, 0.8, 0.05, 0.3),
    "Flame2": (1.0, 0.35, 0.02, 0.3),
    "Flame3": (0.85, 0.05, 0.02, 0.3),
    "shell": (0.95, 0.95, 0.95, 0.2),
    "stripe": (0.1, 0.3, 0.9, 0.2),
    "visor": (0.02, 0.02, 0.03, 0.05),
}


def material(slot, cache={}):
    bpy = bl()
    if slot in cache:
        return cache[slot]
    m = bpy.data.materials.new(slot)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    r, g, bb, rough = PREVIEW.get(slot, (0.5, 0.5, 0.5, 0.5))
    b.inputs["Base Color"].default_value = (r, g, bb, 1)
    b.inputs["Roughness"].default_value = rough
    if slot == "Metal":
        b.inputs["Metallic"].default_value = 1.0
    if slot in ("TailLight", "Neon", "Light"):
        b.inputs["Emission Color"].default_value = (r, g, bb, 1)
        b.inputs["Emission Strength"].default_value = 4.0
    try:
        b.inputs["Coat Weight"].default_value = 0.6 if slot in ("Primary", "Secondary", "Accent", "White") else 0.0
    except Exception:
        pass
    cache[slot] = m
    return m


# in-game default colours per design (Cosmetics.BodyLivery), for previews
LIVERY = {
    "gt1": ((215, 25, 35), (240, 240, 240)), "aeros": ((0, 160, 150), (240, 240, 240)), "stealth": ((22, 22, 26), (240, 240, 240)),
    "nova": ((120, 50, 200), (240, 240, 240)), "neonracer": ((15, 20, 55), (240, 240, 240)), "arrow": ((170, 175, 185), (0, 160, 150)),
    "falcon": ((255, 120, 20), (240, 240, 240)), "viper": ((20, 150, 80), (240, 240, 240)), "vortex": ((240, 240, 240), (215, 25, 35)),
    "apex": ((215, 25, 35), (240, 240, 240)), "aurora": ((120, 190, 255), (240, 240, 240)), "retro70": ((215, 25, 35), (240, 240, 240)),
    "retro90": ((15, 25, 80), (240, 240, 240)),
}


def _srgb(c):
    return tuple(((v / 255) ** 2.2) for v in c)


def render(design, pattern, out, view="front34", variants=("fin", "rwA"), res=(1100, 620)):
    return render_views(design, pattern, [(view, out)], variants, res)


def render_views(design, pattern, views_out, variants=("fin", "rwA"), res=(1100, 620), livery=False):
    bpy = bl()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    material.__defaults__[0].clear()
    if livery and design in LIVERY:
        pc, sc2 = LIVERY[design]
        PREVIEW["Primary"] = _srgb(pc) + (0.25,)
        PREVIEW["Suit"] = _srgb(pc) + (0.7,)
        PREVIEW["Secondary"] = _srgb(sc2) + (0.3,)
    objs, anchors = collect([design])
    col = bpy.context.scene.collection
    pats = {"stripe": ["stripe"], "retro": ["retroA", "retroB"], "split": ["split"], "chevron": ["chevron"], "checker": ["checkA", "checkB"], "flames": ["flame1", "flame2", "flame3"], "side": ["side"], "circuit": ["circuit"], "carbon": ["split"]}.get(pattern, [])
    for name, polys in objs.items():
        parts = name.split(".")
        if parts[0] != design:
            continue
        if parts[1] == "p" and parts[2] not in pats:
            continue
        if parts[1] == "v" and parts[2] not in variants:
            continue
        ob, *_ = make_object(name, polys, col)
        slot = slot_of(name)
        if pattern == "carbon" and parts[1] == "p":
            slot = "Carbon"
        ob.data.materials.append(material(slot))
    A = anchors[design]
    # wheels
    for i, w in enumerate(A["wheels"]):
        side = 1 if w["pos"][0] > 0 else -1
        t = w["tyre"]
        inner = 0.64 if t == "t18" else 0.47
        tn = "18" if t == "t18" else "13"
        extra = (("w.grooves", 1.0),) if t == "t13g" else ()
        for nm, sc in ((f"w.tyre{tn}", 1.0), (f"w.comp{tn}", 1.0)) + extra + (("w.barrel", inner), ("w.back", inner), ("w.hub", inner), ("w.rim.classic", inner)):
            ob, *_ = make_object(f"{nm}#{i}", objs[nm], col, center=False)
            ob.data.materials.append(material(slot_of(nm)))
            ob.scale = (w["w"] * side, 2 * w["r"] * sc / 2, 2 * w["r"] * sc / 2)
            ob.location = (w["pos"][0], -w["pos"][2], w["pos"][1])
    for nm in ("h.shell", "h.stripe", "h.visor"):
        ob, *_ = make_object(nm + "#", objs[nm], col, center=False)
        ob.data.materials.append(material(nm.split(".")[1]))
        hp = A["head"]
        ob.location = (hp[0], -hp[2], hp[1])
    # ground + lights + camera
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -1.95))
    g = bpy.context.object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.36, 0.38, 1)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
    g.data.materials.append(gm)
    world = bpy.data.worlds.new("w")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.65, 0.8, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.5
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(40), math.radians(10), math.radians(-30))
    col.objects.link(so)
    cam = bpy.data.cameras.new("cam")
    cam.lens = 50
    co = bpy.data.objects.new("cam", cam)
    col.objects.link(co)
    views = {
        "front34": ((-13, 16, 4.5), (0, 0.5, -1.0)),
        "rear34": ((12, -15, 5), (0, 0.0, -1.0)),
        "side": ((-24, 0, 0.2), (0, 0, -1.0)),
        "top": ((0, 0.01, 26), (0, 0, -1)),
        "front": ((0, 22, 0.5), (0, 0, -1.0)),
        "close": ((-6, 8, 2.5), (0, 1.5, -0.8)),
        "rclose": ((5, -8, 2.5), (0, -2, -0.8)),
    }
    import mathutils

    sc = bpy.context.scene
    sc.camera = co
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.cycles.device = "CPU"
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = res
    for view, out in views_out:
        loc, tgt = views[view]
        co.location = loc
        dvec = mathutils.Vector(tgt) - mathutils.Vector(loc)
        co.rotation_euler = dvec.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = out
        bpy.ops.render.render(write_still=True)


def sheet(design, out, pattern="none", views=("front34", "rear34", "side", "top")):
    """One picture of a design from several views, in its in-game default colours."""
    import os
    import tempfile
    from PIL import Image, ImageDraw

    tmp = tempfile.mkdtemp()
    outs = [(v, os.path.join(tmp, v + ".png")) for v in views]
    render_views(design, pattern, outs, res=(880, 496), livery=True)
    ims = [Image.open(o) for _, o in outs]
    cols = 2
    w, h = ims[0].size
    img = Image.new("RGB", (w * cols, h * ((len(ims) + cols - 1) // cols)), (30, 30, 30))
    dr = ImageDraw.Draw(img)
    for i, im in enumerate(ims):
        img.paste(im, ((i % cols) * w, (i // cols) * h))
    dr.text((12, 10), design, fill=(255, 230, 0))
    img.save(out)


def export(out_fbx, out_manifest, only=None, shared=True):
    bpy = bl()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs, anchors = collect(only, shared)
    col = bpy.context.scene.collection
    man = {"objects": {}, "anchors": anchors, "scale": [designs.SX, designs.SY, designs.SZ], "yg": designs.YG}
    total = 0
    for name, polys in objs.items():
        if not polys:
            continue
        ob, c, size, nf = make_object(name, polys, col)
        man["objects"][name] = {"c": [float(x) for x in c], "s": [float(x) for x in size], "faces": nf}
        total += nf
    print(f"{len(man['objects'])} objects, {total} faces", file=sys.stderr)
    bpy.ops.export_scene.fbx(filepath=out_fbx, use_selection=False, object_types={"MESH"}, apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y", use_mesh_modifiers=True, mesh_smooth_type="FACE", use_triangles=True, add_leaf_bones=False, bake_anim=False)
    json.dump(man, open(out_manifest, "w"), indent=1)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "render":
        if sys.argv[3] == "none":
            designs.FAST = True
        render(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "front34", tuple(sys.argv[6].split(",")) if len(sys.argv) > 6 else ("fin", "rwA"))
    elif cmd == "sheet":
        if len(sys.argv) <= 4 or sys.argv[4] == "none":
            designs.FAST = True
        sheet(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "none")
    elif cmd == "export":
        sh = sys.argv[5] if len(sys.argv) > 5 else "True"
        sh = {"true": True, "false": False, "new": "new"}.get(sh.lower(), True)
        export(sys.argv[2], sys.argv[3], sys.argv[4].split(",") if len(sys.argv) > 4 and sys.argv[4] != "all" else None, sh)
