"""Pull ReplicatedStorage.CarMeshes (or another folder) out of a saved .rbxlx into an
.rbxmx for Rojo.

  python3 tools/cargen/extract_meshes.py <place.rbxlx> assets/CarMeshes.rbxmx
  python3 tools/cargen/extract_meshes.py <place.rbxlx> assets/WorldMeshes.rbxmx WorldMeshes
"""
import sys
import xml.etree.ElementTree as ET

src, dst = sys.argv[1], sys.argv[2]
folder = sys.argv[3] if len(sys.argv) > 3 else "CarMeshes"
root = ET.parse(src).getroot()


def name_of(item):
    for c in item.find("Properties"):
        if c.get("name") == "Name":
            return c.text


rs = [i for i in root.findall("Item") if i.get("class") == "ReplicatedStorage"][0]
cm = [i for i in rs.findall("Item") if name_of(i) == folder][0]
print("meshparts", len(cm.findall("Item")))
refs = set(e.text for e in cm.iter("SharedString"))
out = ET.Element("roblox", {"version": "4"})
out.append(cm)
ss = root.find("SharedStrings")
if refs and ss is not None:
    ns = ET.SubElement(out, "SharedStrings")
    for s in ss.findall("SharedString"):
        if s.get("md5") in refs:
            ns.append(s)
    print("shared strings", len(ns))
ET.ElementTree(out).write(dst, encoding="utf-8", xml_declaration=False)
print("wrote", dst)
