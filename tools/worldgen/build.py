"""World meshes CLI (Blender `bpy` as a Python module, like tools/cargen).

  python3 tools/worldgen/build.py stats                         # triangles per design / slot
  python3 tools/worldgen/build.py sheet /tmp/world.png [names]  # preview picture of the designs
  python3 tools/worldgen/build.py export assets/world/GoTrackWorld.fbx assets/world/manifest.json
  python3 tools/worldgen/build.py luau assets/world/manifest.json src/shared/WorldData.luau

Mesh object names are <design>.<Slot> (e.g. tower_glass.Glass). The FBX is imported in
Studio by hand and the MeshParts go into ReplicatedStorage.WorldMeshes (see
docs/WORLD_PIPELINE.md).
"""

import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import designs  # noqa: E402
import geom as G  # noqa: E402

MAX_TRIS = 9000  # Roblox allows 20k per MeshPart; stay well under

# preview colours for the sheet and the circuit renders (RGB 0..1, roughness)
PREVIEW = {
    "Glass": ((0.32, 0.45, 0.6), 0.08),
    "Frame": ((0.82, 0.84, 0.88), 0.3),
    "Wall": ((0.86, 0.82, 0.74), 0.8),
    "Trim": ((0.93, 0.91, 0.86), 0.7),
    "WinA": ((0.2, 0.28, 0.38), 0.1),
    "WinB": ((0.24, 0.32, 0.42), 0.1),
    "Roof": ((0.45, 0.43, 0.42), 0.8),
    "Accent": ((0.85, 0.25, 0.2), 0.5),
    "Beacon": ((0.9, 0.1, 0.1), 0.4),
    "Leaf": ((0.24, 0.52, 0.2), 0.9),
    "Trunk": ((0.4, 0.28, 0.18), 0.9),
    "Snow": ((0.95, 0.96, 1.0), 0.6),
    "Rock": ((0.5, 0.48, 0.46), 0.95),
    "Base": ((0.36, 0.6, 0.26), 0.95),
    "Band": ((0.72, 0.45, 0.3), 0.95),
    "Body": ((0.7, 0.1, 0.1), 0.3),
    "Dark": ((0.05, 0.05, 0.06), 0.8),
    "Light": ((0.95, 0.95, 0.9), 0.3),
    "TailLight": ((0.8, 0.05, 0.05), 0.3),
}

_CACHE = {}


def build(name):
    """{slot: faces} for one design (cached)."""
    if name not in _CACHE:
        out = designs.DESIGNS[name]["fn"]()
        _CACHE[name] = {k: f for k, f in out.slots.items() if f}
    return _CACHE[name]


def tris(faces):
    """Triangle count of a list of faces."""
    return sum(len(f) - 2 for f in faces)


def weld(faces, eps=1e-3):
    """Merges shared vertices into (verts, faces) for Blender."""
    idx, verts, out = {}, [], []
    for f in faces:
        ids = []
        for p in f:
            key = (round(p[0] / eps), round(p[1] / eps), round(p[2] / eps))
            if key not in idx:
                idx[key] = len(verts)
                verts.append((float(p[0]), float(p[1]), float(p[2])))
            i = idx[key]
            if not ids or ids[-1] != i:
                ids.append(i)
        if len(ids) > 1 and ids[0] == ids[-1]:
            ids.pop()
        if len(set(ids)) >= 3:
            out.append(ids)
    return verts, out


def bbox(faces):
    """Centre and size of a set of faces (at least 0.05 studs in every direction)."""
    pts = np.array([p for f in faces for p in f])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    return (lo + hi) / 2, np.maximum(hi - lo, 0.05)


def bl():
    """Imports bpy only when needed, so `stats` runs without Blender."""
    import bpy

    return bpy


def make_object(name, faces, collection, smooth=False, centre=True):
    """Blender object from Roblox-space faces (centred on its bounding box)."""
    bpy = bl()
    c, size = bbox(faces)
    verts, fidx = weld(faces)
    if centre:
        verts = [(x - c[0], y - c[1], z - c[2]) for x, y, z in verts]
    # Roblox (X, Y, Z) -> Blender (X, -Z, Y)
    bverts = [(x, -z, y) for x, y, z in verts]
    me = bpy.data.meshes.new(name)
    me.from_pydata(bverts, [], fidx)
    me.validate()
    me.update()
    # box-projected UVs (1 unit = 8 studs) so Roblox materials tile sensibly
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                uv.data[li].uv = (co[1] / 8, co[2] / 8)
            elif ax == 1:
                uv.data[li].uv = (co[0] / 8, co[2] / 8)
            else:
                uv.data[li].uv = (co[0] / 8, co[1] / 8)
    for p in me.polygons:
        p.use_smooth = smooth
    if smooth:
        try:
            me.set_sharp_from_angle(angle=math.radians(50))
        except Exception:
            pass
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    if centre:
        ob.location = (c[0], -c[2], c[1])
    return ob, c, size, len(fidx)


def objects(only=None):
    """{object name: (faces, design, slot)} for every design (or the listed ones)."""
    out = {}
    for name, meta in designs.DESIGNS.items():
        if only and name not in only:
            continue
        for slot, faces in build(name).items():
            out[f"{name}.{slot}"] = (faces, name, slot)
    return out


def stats():
    """Prints triangles per design and slot, and flags any mesh over MAX_TRIS."""
    total = 0
    for name, meta in designs.DESIGNS.items():
        parts = build(name)
        t = {k: tris(f) for k, f in parts.items()}
        s = sum(t.values())
        total += s
        worst = max(t.values())
        flag = "  <-- too many" if worst > MAX_TRIS else ""
        print(f"{name:14s} {meta['kind']:9s} {s:6d} tris  {len(parts)} slots  max {worst}{flag}")
    print("total", total, "triangles in", len(designs.DESIGNS), "designs")


def export(out_fbx, out_manifest):
    """Exports every design to one FBX and writes the manifest (each MeshPart's centre and
    size, and each design's kind, footprint and height).
    """
    bpy = bl()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    col = bpy.context.scene.collection
    man = {"designs": {}, "objects": {}}
    total = 0
    for obj, (faces, name, slot) in objects().items():
        meta = designs.DESIGNS[name]
        ob, c, size, nf = make_object(obj, faces, col, smooth=meta["smooth"])
        man["objects"][obj] = {
            "c": [round(float(x), 3) for x in c],
            "s": [round(float(x), 3) for x in size],
            "tris": tris(faces),
        }
        d = man["designs"].setdefault(name, {"kind": meta["kind"], "w": meta["w"], "d": meta["d"], "slots": []})
        d["slots"].append(slot)
        total += tris(faces)
    for name, d in man["designs"].items():
        pts = np.array([p for slot in d["slots"] for f in build(name)[slot] for p in f])
        d["h"] = round(float(pts[:, 1].max()), 2)
    print(f"{len(man['objects'])} objects, {total} triangles", file=sys.stderr)
    os.makedirs(os.path.dirname(os.path.abspath(out_fbx)), exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=out_fbx,
        use_selection=False,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        use_triangles=True,
        add_leaf_bones=False,
        bake_anim=False,
    )
    json.dump(man, open(out_manifest, "w"), indent=1)


def luau(manifest, out):
    """Writes src/shared/WorldData.luau from the manifest."""
    man = json.load(open(manifest))
    L = []
    L.append("--!nonstrict")
    L.append("-- GENERATED by tools/worldgen/build.py luau - do not edit by hand.")
    L.append("-- World meshes (buildings, trees, rocks, mountains, road cars) made in Blender. The")
    L.append("-- MeshParts live in ReplicatedStorage.WorldMeshes as <design>.<Slot>; WorldMeshes.luau")
    L.append("-- places them. C = object centre and S = size in studs, relative to the design's origin")
    L.append("-- (on the ground, facade towards -Z).")
    L.append("")
    L.append("local V = Vector3.new")
    L.append("return {")
    L.append("\tDesigns = {")
    for name, d in sorted(man["designs"].items()):
        L.append(f'\t\t["{name}"] = {{')
        L.append(f'\t\t\tKind = "{d["kind"]}", W = {d["w"]}, D = {d["d"]}, H = {d["h"]},')
        L.append("\t\t\tParts = {")
        for slot in d["slots"]:
            o = man["objects"][f"{name}.{slot}"]
            c, s = o["c"], o["s"]
            L.append(f'\t\t\t\t{{ "{name}.{slot}", "{slot}", V({c[0]}, {c[1]}, {c[2]}), V({s[0]}, {s[1]}, {s[2]}) }},')
        L.append("\t\t\t},")
        L.append("\t\t},")
    L.append("\t},")
    L.append("}")
    open(out, "w").write("\n".join(L) + "\n")
    print("wrote", out, len(man["designs"]), "designs")


def material(bpy, key, rgb, rough, emit=0.0, alpha=1.0):
    """A preview material for the sheet renders (cached by key)."""
    m = bpy.data.materials.get(key)
    if m:
        return m
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


def sheet(out, only=None):
    """All designs on a grid (buildings, nature, vehicles in rows), rendered with Cycles."""
    bpy = bl()
    import mathutils

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    col = sc.collection
    names = [n for n in designs.DESIGNS if not only or n in only]
    groups = {"tower": [], "mid": [], "house": [], "tree": [], "rock": [], "vehicle": [], "mountain": []}
    for n in names:
        groups[designs.DESIGNS[n]["kind"]].append(n)
    rows = [groups["tower"], groups["mid"] + groups["house"], groups["tree"] + groups["rock"] + groups["vehicle"]]
    z = 0.0
    maxx = 0.0
    for row in rows:
        if not row:
            continue
        x = 0.0
        depth = max(designs.DESIGNS[n]["d"] for n in row)
        for n in row:
            w = designs.DESIGNS[n]["w"]
            k = 3.0 if designs.DESIGNS[n]["kind"] in ("tree", "rock", "vehicle") else 1.0
            for slot, faces in build(n).items():
                faces = G.scale(faces, k, k, k)
                ob, *_ = make_object(
                    f"{n}.{slot}",
                    G.move(faces, x + w * k / 2, 0, z),
                    col,
                    smooth=designs.DESIGNS[n]["smooth"],
                    centre=False,
                )
                rgb, rough = PREVIEW.get(slot, ((0.7, 0.7, 0.7), 0.5))
                ob.data.materials.append(material(bpy, slot, rgb, rough))
            x += w * k + 14
        maxx = max(maxx, x)
        z += depth * 1.2 + 40
    # ground, sky, sun
    bpy.ops.mesh.primitive_plane_add(size=6000, location=(maxx / 2, -z / 2, 0))
    g = bpy.context.object
    g.data.materials.append(material(bpy, "ground", (0.34, 0.5, 0.28), 0.95))
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.72, 0.9, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.2
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), math.radians(12), math.radians(-35))
    col.objects.link(so)
    cam = bpy.data.cameras.new("cam")
    cam.lens = 30
    cam.clip_end = 50000
    co = bpy.data.objects.new("cam", cam)
    col.objects.link(co)
    sc.camera = co
    tgt = mathutils.Vector((maxx / 2, -z / 2 + 30, 90))
    co.location = (maxx / 2, -z / 2 - max(maxx, z) * 0.95, 360)
    co.rotation_euler = (tgt - co.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 16
    sc.cycles.device = "CPU"
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.view_settings.view_transform = "AgX"
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "stats":
        stats()
    elif cmd == "sheet":
        sheet(sys.argv[2], sys.argv[3].split(",") if len(sys.argv) > 3 else None)
    elif cmd == "export":
        export(sys.argv[2], sys.argv[3])
    elif cmd == "luau":
        luau(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
