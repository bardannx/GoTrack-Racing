"""Export only the helmet meshes (h2.*) to a small FBX + manifest, for a quick re-import
after changing the helmet without re-exporting every car.

  python3 tools/cargen/export_helmet.py <out.fbx> <manifest.json>
"""

import json
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import build, wheels

out_fbx, out_man = sys.argv[1], sys.argv[2]
bpy = build.bl()
bpy.ops.wm.read_factory_settings(use_empty=True)
col = bpy.context.scene.collection
sh, st, vi, co = wheels.helmet2()
man = {"objects": {}}
for name, polys in (("h2.shell", sh), ("h2.stripe", st), ("h2.visor", vi), ("h2.collar", co)):
    ob, c, size, nf = build.make_object(name, polys, col)
    man["objects"][name] = {"c": [float(x) for x in c], "s": [float(x) for x in size], "faces": nf}
bpy.ops.export_scene.fbx(
    filepath=out_fbx,
    use_selection=False,
    object_types={"MESH"},
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS",
    axis_forward="-Z",
    axis_up="Y",
    mesh_smooth_type="FACE",
    use_triangles=True,
    add_leaf_bones=False,
    bake_anim=False,
)
json.dump(man, open(out_man, "w"), indent=1)
print(json.dumps(man))
