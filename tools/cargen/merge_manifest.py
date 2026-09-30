"""Merge a partial export manifest into the master manifest (objects + anchors), then regenerate CarData.

python3 tools/cargen/merge_manifest.py assets/cars/manifest.json assets/cars/manifest_new.json
python3 tools/cargen/gen_luau.py assets/cars/manifest.json src/shared/CarData.luau
"""

import json
import sys

master_path, part_path = sys.argv[1], sys.argv[2]
master = json.load(open(master_path))
part = json.load(open(part_path))
master["objects"].update(part.get("objects", {}))
master["anchors"].update(part.get("anchors", {}))
json.dump(master, open(master_path, "w"), indent=1)
print(f"{master_path}: {len(master['objects'])} objects, {len(master['anchors'])} designs")
