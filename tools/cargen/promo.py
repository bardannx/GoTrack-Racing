"""Promo renders (game icon / thumbnails) of the real GoTrack car models.

  python3 promo.py cache                 # build + pickle the car geometry (slow, once)
  python3 promo.py icon  out.png
  python3 promo.py hero  out.png
  python3 promo.py lineup out.png
"""
import math
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build
import designs
import wheels

CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "promo_cache.pkl")
NEEDED = ["gt1", "falcon", "nova", "aeros", "stealth", "neonracer", "viper", "aurora", "retro90", "arrow"]


def rgb(r, g, b):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b))


PAINT = {
    "red": rgb(215, 25, 35), "white": rgb(240, 240, 240), "black": rgb(22, 22, 26), "teal": rgb(0, 160, 150),
    "purple": rgb(120, 50, 200), "midnight": rgb(15, 20, 55), "silver": rgb(170, 175, 185), "orange": rgb(255, 120, 20),
    "green": rgb(20, 150, 80), "sky": rgb(120, 190, 255), "navy": rgb(15, 25, 80), "yellow": rgb(255, 210, 30), "cyan": rgb(40, 200, 255),
}
PATTERN_KEYS = {
    "stripe": [("stripe", "Secondary")],
    "side": [("side", "Secondary")],
    "split": [("split", "Secondary")],
    "chevron": [("chevron", "Secondary")],
}


def cache():
    objs, anchors = build.collect(NEEDED, shared=True)
    sh, st, vi, co = wheels.helmet2()
    objs["h2.shell"], objs["h2.stripe"], objs["h2.visor"], objs["h2.collar"] = sh, st, vi, co
    objs["h2.headrest"] = wheels.headrest()
    pickle.dump((objs, anchors), open(CACHE, "wb"))
    print("cached", len(objs))


def load():
    return pickle.load(open(CACHE, "rb"))


# ---------------------------------------------------------------------------
bpy = None
EXPOSURE = -1.0


def mat(name, color, rough=0.3, metal=0.0, coat=0.0, emit=0.0, alpha=1.0, cache={}):
    key = (name, color, rough, metal, coat, emit, alpha)
    if key in cache:
        return cache[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    try:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.05
    except Exception:
        pass
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        try:
            b.inputs["Transmission Weight"].default_value = 0.6
        except Exception:
            pass
    cache[key] = m
    return m


def slot_material(slot, livery):
    P, S, A = livery["Primary"], livery["Secondary"], livery["Accent"]
    table = {
        "Primary": lambda: mat("paint", PAINT[P], 0.18, 0.0, 1.0),
        "Suit": lambda: mat("suit", PAINT[P], 0.6),
        "Secondary": lambda: mat("paint", PAINT[S], 0.18, 0.0, 1.0),
        "Accent": lambda: mat("paint", PAINT[A], 0.25, 0.0, 0.8),
        "TCam": lambda: mat("paint", PAINT["yellow"], 0.3),
        "Carbon": lambda: mat("carbon", rgb(30, 30, 34), 0.35, 0.0, 0.5),
        "Halo": lambda: mat("carbon", rgb(30, 30, 34), 0.35, 0.0, 0.5),
        "Dark": lambda: mat("dark", rgb(10, 10, 12), 0.5),
        "Glass": lambda: mat("glass", rgb(20, 25, 35), 0.05, 0.3),
        "Canopy": lambda: mat("canopy", rgb(22, 30, 48), 0.03, 0.2, 1.0),
        "Metal": lambda: mat("metal", rgb(165, 165, 175), 0.25, 1.0),
        "TailLight": lambda: mat("tail", rgb(255, 40, 40), 0.3, 0, 0, 6.0),
        "Neon": lambda: mat("neon", PAINT[S], 0.3, 0, 0, 8.0),
    }
    return table.get(slot, lambda: mat("grey", rgb(128, 128, 128)))()


def add_car(objs, anchors, design, livery, variants=("rwA",), pattern="stripe", neon=False, loc=(0, 0, 0), yaw=0.0, rim="classic"):
    col = bpy.context.scene.collection
    root = bpy.data.objects.new(design + "_root", None)
    col.objects.link(root)
    keys = PATTERN_KEYS.get(pattern, [])
    patset = {k: s for k, s in keys}
    if neon:
        patset["circuit"] = "Neon"
    for name, polys in objs.items():
        parts = name.split(".")
        if parts[0] != design:
            continue
        if parts[1] == "v":
            if parts[2] not in variants:
                continue
            slot = parts[4]
        elif parts[1] == "p":
            if parts[2] not in patset:
                continue
            slot = patset[parts[2]]
        else:
            slot = parts[2]
        ob, *_ = build.make_object(name, polys, col)
        ob.data.materials.append(slot_material(slot, livery))
        ob.parent = root
    A = anchors[design]
    for i, w in enumerate(A["wheels"]):
        side = 1 if w["pos"][0] > 0 else -1
        t = w["tyre"]
        inner = 0.64 if t == "t18" else 0.47
        tn = "18" if t == "t18" else "13"
        parts_ = [(f"w.tyre{tn}", 1.0, mat("tyre", rgb(30, 30, 33), 0.75)),
                  (f"w.comp{tn}", 1.0, mat("comp", rgb(230, 40, 40), 0.5)),
                  ("w.barrel", inner, mat("rim", rgb(25, 25, 28), 0.3, 0.6)),
                  ("w.back", inner, mat("dark", rgb(10, 10, 12), 0.5)),
                  ("w.hub", inner, mat("hub", rgb(210, 40, 40), 0.3)),
                  ("w.rim." + rim, inner, mat("rim", rgb(25, 25, 28), 0.3, 0.6))]
        for nm, sc, m in parts_:
            ob, *_ = build.make_object(f"{nm}#{design}{i}", objs[nm], col, center=False)
            ob.data.materials.append(m)
            ob.scale = (w["w"] * side, w["r"] * sc, w["r"] * sc)
            ob.location = (w["pos"][0], -w["pos"][2], w["pos"][1])
            ob.parent = root
    hp = A["head"]
    for nm, m in (("h2.shell", mat("helmet", rgb(245, 245, 245), 0.2, 0, 1.0)), ("h2.stripe", mat("hstripe", PAINT[livery["Primary"]], 0.2, 0, 1.0)),
                  ("h2.visor", mat("visor", rgb(10, 12, 18), 0.05, 0.3)), ("h2.collar", mat("carbon", rgb(30, 30, 34), 0.35)), ("h2.headrest", mat("dark", rgb(10, 10, 12), 0.5))):
        ob, *_ = build.make_object(nm + "#" + design, objs[nm], col, center=False)
        ob.data.materials.append(m)
        ob.location = (hp[0], -hp[2], hp[1])
        ob.parent = root
    root.location = (loc[0], loc[1], loc[2])
    root.rotation_euler = (0, 0, yaw)
    return root


def scene(sun_elev=7.0, sun_rot=200.0, strength=0.55):
    global bpy
    bpy = build.bl()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    try:
        sky = nt.nodes.new("ShaderNodeTexSky")
        try:
            sky.sky_type = "NISHITA"
        except Exception:
            pass
        sky.sun_elevation = math.radians(sun_elev)
        sky.sun_rotation = math.radians(sun_rot)
        try:
            sky.altitude = 200
        except Exception:
            pass
        nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = strength
    except Exception as e:
        print("sky fallback", e)
        bg.inputs["Color"].default_value = (0.9, 0.5, 0.3, 1)
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.2
    sun.color = (1.0, 0.78, 0.6)
    sun.angle = math.radians(1.5)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(90 - sun_elev - 6), 0, math.radians(sun_rot - 180 + 90))
    sc.collection.objects.link(so)
    # asphalt + track markings
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, -1.95))
    g = bpy.context.object
    g.data.materials.append(mat("asphalt", rgb(52, 54, 60), 0.62))
    return sc


def track_lines(y0=-200, y1=200, half=17, kerb_side=1):
    sc = bpy.context.scene
    for x in (-half, half):
        bpy.ops.mesh.primitive_plane_add(size=1, location=(x, (y0 + y1) / 2, -1.94))
        o = bpy.context.object
        o.scale = (0.6, (y1 - y0), 1)
        o.data.materials.append(mat("line", rgb(235, 235, 235), 0.5))
    # red / white kerb
    x = kerb_side * (half + 1.6)
    for k in range(int((y1 - y0) / 4)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y0 + k * 4 + 2, -1.88))
        o = bpy.context.object
        o.scale = (2.6, 4.0, 0.12)
        o.data.materials.append(mat("kerbw" if k % 2 else "kerbr", rgb(240, 240, 240) if k % 2 else rgb(220, 30, 40), 0.45))
    # grass beyond
    for s in (-1, 1):
        bpy.ops.mesh.primitive_plane_add(size=1, location=(s * (half + 60), (y0 + y1) / 2, -1.945))
        o = bpy.context.object
        o.scale = (110, (y1 - y0), 1)
        o.data.materials.append(mat("grass", rgb(60, 120, 50), 0.8))


def venue(half=17, y0=-260, y1=120):
    import random
    rnd = random.Random(7)
    # tyre-wall / barrier with sponsor-coloured panels on both sides
    cols = [rgb(20, 90, 200), rgb(240, 240, 240), rgb(230, 40, 50), rgb(250, 190, 30), rgb(20, 20, 26)]
    for s in (-1, 1):
        x = s * (half + 7)
        y = y0
        k = 0
        while y < y1:
            bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y + 5, -1.2))
            o = bpy.context.object
            o.scale = (0.6, 10.0, 1.5)
            o.data.materials.append(mat("panel%d" % (k % 5), cols[k % 5], 0.4))
            y += 10
            k += 1
        # grandstand blocks with a colourful "crowd" and a roof
        for yy in range(int(y0) + 20, int(y1) - 20, 34):
            base = s * (half + 18)
            for step in range(6):
                bpy.ops.mesh.primitive_cube_add(size=1, location=(base + s * step * 1.6, yy, -1.2 + step * 1.1))
                o = bpy.context.object
                o.scale = (1.6, 28, 1.1 + step * 2.2 * 0)
                o.data.materials.append(mat("stand", rgb(120, 125, 135), 0.7))
                for c in range(14):
                    bpy.ops.mesh.primitive_cube_add(size=1, location=(base + s * step * 1.6, yy - 13 + c * 2 + rnd.uniform(-0.3, 0.3), -0.35 + step * 1.1))
                    o = bpy.context.object
                    o.scale = (0.7, 0.8, 0.9)
                    o.data.materials.append(mat("crowd%d" % (c % 6), [rgb(230, 40, 50), rgb(250, 190, 30), rgb(40, 120, 230), rgb(240, 240, 240), rgb(30, 160, 90), rgb(160, 60, 200)][rnd.randrange(6)], 0.8))
            bpy.ops.mesh.primitive_cube_add(size=1, location=(base + s * 5, yy, 7.2))
            o = bpy.context.object
            o.scale = (11, 30, 0.4)
            o.data.materials.append(mat("roof", rgb(235, 235, 240), 0.5))
    # a few trees on the horizon
    for i in range(40):
        s = -1 if i % 2 else 1
        x = s * rnd.uniform(half + 45, half + 120)
        y = rnd.uniform(y0, y1)
        bpy.ops.mesh.primitive_cone_add(radius1=rnd.uniform(3, 5), depth=rnd.uniform(9, 15), location=(x, y, 3))
        o = bpy.context.object
        o.data.materials.append(mat("tree", rgb(40, 95, 45), 0.8))


def camera(loc, target, lens=50, focus=None, fstop=4.0):
    import mathutils

    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    cam.lens = lens
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.location = loc
    co.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    if focus:
        cam.dof.use_dof = True
        cam.dof.focus_distance = focus
        cam.dof.aperture_fstop = fstop
    sc.camera = co


def render(out, res, samples=64):
    if os.environ.get("PROMO_TEST"):
        res, samples = (res[0] // 3, res[1] // 3), 16
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.view_settings.view_transform = "AgX" if "AgX" in [v.identifier for v in sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    try:
        sc.view_settings.look = "AgX - Punchy"
    except Exception:
        pass
    sc.view_settings.exposure = EXPOSURE
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)


LIV = {
    "gt1": dict(Primary="red", Secondary="white", Accent="black"),
    "falcon": dict(Primary="orange", Secondary="white", Accent="black"),
    "nova": dict(Primary="purple", Secondary="white", Accent="black"),
    "aeros": dict(Primary="teal", Secondary="white", Accent="black"),
    "stealth": dict(Primary="black", Secondary="white", Accent="black"),
    "neonracer": dict(Primary="midnight", Secondary="cyan", Accent="black"),
    "viper": dict(Primary="green", Secondary="white", Accent="black"),
    "aurora": dict(Primary="sky", Secondary="white", Accent="black"),
    "retro90": dict(Primary="navy", Secondary="white", Accent="black"),
    "arrow": dict(Primary="silver", Secondary="teal", Accent="black"),
}
VARS = {"gt1": ("rwA",), "arrow": ("rwA",), "apex": ("rwA",)}
PATS = {"aeros": "side", "arrow": "split"}


def car(objs, anchors, d, loc, yaw, rim="classic"):
    return add_car(objs, anchors, d, LIV[d], VARS.get(d, ()), PATS.get(d, "stripe"), d in ("nova", "neonracer"), loc, yaw, rim)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "cache":
        cache()
        sys.exit()
    objs, anchors = load()
    out = sys.argv[2]
    if cmd == "icon":
        scene(sun_elev=12, sun_rot=150, strength=0.45)
        track_lines(half=17)
        venue()
        car(objs, anchors, "gt1", (0, 0, 0), math.radians(-32), rim="turbine")
        camera((-11.5, 15.0, 1.4), (0.6, 0.4, -0.7), lens=40, focus=18.5, fstop=5.0)
        render(out, (1024, 1024), 96)
    elif cmd == "hero":
        scene(sun_elev=10, sun_rot=150, strength=0.45)
        track_lines(half=17, kerb_side=1)
        venue()
        car(objs, anchors, "gt1", (1.0, 0, 0), math.radians(-2), rim="turbine")
        car(objs, anchors, "falcon", (-6.5, -15, 0), math.radians(3))
        car(objs, anchors, "nova", (6.5, -28, 0), math.radians(-2))
        camera((11, 21, 0.4), (-1.5, -8, -0.6), lens=48, focus=22, fstop=5.0)
        render(out, (1920, 1080), 80)
    elif cmd == "lineup":
        scene(sun_elev=14, sun_rot=210, strength=0.45)
        track_lines(half=40)
        venue(half=40, y0=-120, y1=80)
        order = ["aeros", "stealth", "nova", "neonracer", "gt1", "falcon", "viper", "aurora", "retro90"]
        n = len(order)
        for i, d in enumerate(order):
            k = i - (n - 1) / 2
            x = k * 7.2
            y = -abs(k) * 5.0
            car(objs, anchors, d, (x, y, 0), math.radians(-k * 4.0))
        camera((0, 34, 6.5), (0, -6, -1.2), lens=40, focus=36, fstop=11)
        render(out, (1920, 1080), 80)
    elif cmd == "battle":
        scene(sun_elev=9, sun_rot=140, strength=0.45)
        track_lines(half=17, kerb_side=-1)
        venue()
        car(objs, anchors, "viper", (3.2, 0, 0), math.radians(-1), rim="star")
        car(objs, anchors, "aeros", (-3.4, -4.5, 0), math.radians(1.5), rim="turbine")
        car(objs, anchors, "stealth", (1.5, -24, 0), math.radians(0))
        camera((-4, 19, 0.5), (4.5, -3, -0.5), lens=46, focus=18, fstop=5.0)
        render(out, (1920, 1080), 80)
