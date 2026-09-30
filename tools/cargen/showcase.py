"""Store thumbnails and ad pictures: the game's real cars on the game's real circuits.

The circuit comes from a tools/sim dump (every part and Blender world mesh, built by the
game's own CircuitBuilder); the cars are the same Blender models as the in-game meshes
(promo.py cache). Cars sit on the road surface at a point of the lap, the camera tracks
the lead car and Cycles motion blur streaks the background, like a TV shot.

    lune run tools/sim/maps.luau 3 capital --dump --meshes   # the circuit
    python3 tools/cargen/promo.py cache                        # the cars (once, ~5 min)
    python3 tools/cargen/showcase.py preview capital           # contact sheet of candidate shots
    python3 tools/cargen/showcase.py shot capital              # final render from SHOTS
    python3 tools/cargen/showcase.py card capital              # add the logo + caption

Raw renders go to tools/sim/out/showcase_<id>.png, finished pictures to
assets/launch/thumbnails/. Needs bpy, numpy and Pillow.
"""

import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools" / "sim"))
import promo  # noqa: E402
import render3d  # noqa: E402

OUT = ROOT / "tools" / "sim" / "out"
CARDS = ROOT / "assets" / "launch" / "thumbnails"
SPEED = 95.0  # studs/s: the motion-blur speed of every car
FPS = 24
NIGHT_EV = 0.7  # night circuits are floodlit in game: lift the exposure a little
FILL = 0.26  # sky light strength by day (render3d uses 0.12, which leaves shadows too dark)

# camera rigs in the lead car's frame: (right, forward, up) offsets in studs
RIGS = {
    "front": dict(eye=(8.0, 19.0, 2.6), look=(0.0, 1.5, 0.8), lens=35, fstop=5.0),
    "frontl": dict(eye=(-8.0, 19.0, 2.6), look=(0.0, 1.5, 0.8), lens=35, fstop=5.0),
    "chase": dict(eye=(2.5, -24.0, 7.5), look=(0.0, 30.0, 1.0), lens=30, fstop=9.0),
    "side": dict(eye=(19.0, 4.0, 2.4), look=(0.0, 1.0, 0.6), lens=38, fstop=4.5),
    "sidel": dict(eye=(-19.0, 4.0, 2.4), look=(0.0, 1.0, 0.6), lens=38, fstop=4.5),
    "low": dict(eye=(4.0, 12.0, 0.7), look=(-0.5, 0.0, 1.0), lens=24, fstop=6.0),
    "lowl": dict(eye=(-4.0, 12.0, 0.7), look=(0.5, 0.0, 1.0), lens=24, fstop=6.0),
    "high": dict(eye=(18.0, 26.0, 18.0), look=(0.0, -6.0, 0.0), lens=32, fstop=11.0),
    "highl": dict(eye=(-18.0, 26.0, 18.0), look=(0.0, -6.0, 0.0), lens=32, fstop=11.0),
    "wide": dict(eye=(12.0, 34.0, 5.0), look=(0.0, 0.0, 1.5), lens=28, fstop=8.0),
    "widel": dict(eye=(-12.0, 34.0, 5.0), look=(0.0, 0.0, 1.5), lens=28, fstop=8.0),
}
SHIFT_X = -0.14  # frame the cars right of centre: the logo and caption sit on the left

# final shots: where on the lap (0-1), which rig, which cars, and the caption
SHOTS = {
    "capital": dict(
        frac=0.50,
        rig="front",
        cars=["gt1", "falcon", "aeros"],
        title="CAPITAL CIRCUIT",
        sub="Madrid  ·  street circuit",
    ),
    "bay": dict(
        frac=0.26, rig="front", cars=["neonracer", "nova", "gt1"], title="NEON BAY STREETS", sub="Tokyo  ·  night race"
    ),
    "harbor": dict(
        frac=0.74,
        rig="front",
        cars=["aurora", "gt1", "stealth"],
        title="AZURE HARBOR",
        sub="Monaco  ·  harbour streets",
    ),
    "alpine": dict(
        frac=0.62, rig="front", cars=["viper", "gt1", "falcon"], title="ALPINE RING", sub="Austria  ·  mountain circuit"
    ),
    "canyon": dict(
        frac=0.50,
        rig="front",
        cars=["falcon", "retro90", "gt1"],
        title="RED ROCK CANYON",
        sub="Arizona  ·  desert sunset",
    ),
    "sakura": dict(
        frac=0.38, rig="front", cars=["aeros", "nova", "gt1"], title="SAKURA HILLS", sub="Japan  ·  cherry blossom"
    ),
    "frostpeak": dict(
        frac=0.74,
        rig="front",
        cars=["stealth", "aurora", "gt1"],
        title="FROSTPEAK GLACIER",
        sub="Arctic  ·  snow and ice",
    ),
    "volcano": dict(
        frac=0.74,
        rig="front",
        cars=["gt1", "arrow", "viper"],
        title="VOLCANO ISLAND",
        sub="Pacific  ·  erupting volcano",
    ),
}

LIVERY_OF = promo.LIV


def lap_points(data):
    """The circuit's centre line, converted from Roblox to Blender axes."""
    tr = np.array(data["track"], float)
    return np.stack([tr[:, 0], -tr[:, 2], tr[:, 1]], axis=1)  # Roblox -> Blender (x, -z, y)


def lap_length(tb):
    """Length of the closed centre line."""
    return float(np.sum(np.linalg.norm(np.roll(tb, -1, axis=0) - tb, axis=1)))


def point_at(tb, frac):
    """Position and direction at `frac` of the way around the lap."""
    n = len(tb)
    x = (frac % 1.0) * n
    i = int(x)
    t = x - i
    a, b = tb[i % n], tb[(i + 1) % n]
    p = a + (b - a) * t
    f = tb[(i + 2) % n] - tb[(i - 1) % n]
    f = f / max(np.linalg.norm(f), 1e-6)
    return p, f


def ground(bpy, p, fwd):
    """Road surface under p (ray cast down) and its normal, averaged across the car's width."""
    from mathutils import Vector

    sc = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    right = np.cross(fwd, [0, 0, 1])
    right /= max(np.linalg.norm(right), 1e-6)
    hits, nrms = [], []
    for k in (-2.5, 0.0, 2.5):
        for j in (-5.0, 5.0):
            o = p + right * k + fwd * j + np.array([0, 0, 7.0])
            ok, loc, nrm, *_ = sc.ray_cast(dg, Vector(tuple(o)), Vector((0, 0, -1)), distance=30)
            if ok:
                hits.append(np.array(loc) - right * k - fwd * j)
                n = np.array(nrm)
                nrms.append(n if n[2] > 0 else -n)
    if not hits:
        return p.copy(), np.array([0.0, 0.0, 1.0])
    z = np.median([h[2] for h in hits])
    up = np.mean(nrms, axis=0)
    up /= max(np.linalg.norm(up), 1e-6)
    if up[2] < 0.8:
        up = np.array([0.0, 0.0, 1.0])
    return np.array([p[0], p[1], z]), up


def frame_of(fwd, up):
    """Right, forward and up vectors for a car facing `fwd` on a surface with normal `up`."""
    up = up / np.linalg.norm(up)
    f = fwd - up * np.dot(fwd, up)
    f /= max(np.linalg.norm(f), 1e-6)
    r = np.cross(f, up)
    return r, f, up


def key_linear(ob):
    """Makes an object's keyframes linear, so it moves at constant speed."""
    ad = ob.animation_data
    if ad and ad.action:
        try:
            curves = ad.action.fcurves
        except AttributeError:  # Blender 5 layered actions
            curves = [
                fc
                for layer in ad.action.layers
                for strip in layer.strips
                for bag in strip.channelbags
                for fc in bag.fcurves
            ]
        for fc in curves:
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"


def place_car(bpy, objs, anchors, design, livery, pos, r, f, up, rim="turbine"):
    """Places one car at `pos`, oriented by the (right, forward, up) frame."""
    from mathutils import Matrix

    root = promo.add_car(
        objs,
        anchors,
        design,
        livery,
        promo.VARS.get(design, ()),
        promo.PATS.get(design, "stripe"),
        design in ("nova", "neonracer"),
        (0, 0, 0),
        0.0,
        rim,
    )
    M = Matrix(((r[0], f[0], up[0]), (r[1], f[1], up[1]), (r[2], f[2], up[2])))
    root.rotation_mode = "QUATERNION"
    root.rotation_quaternion = M.to_quaternion()
    base = pos + up * 1.95
    dt = 1.0 / FPS
    for fr in (0, 1, 2):
        root.location = tuple(base + f * SPEED * dt * (fr - 1))
        root.keyframe_insert("location", frame=fr)
    key_linear(root)
    # spin the wheels so the rims blur like the road
    wheels = anchors[design]["wheels"]
    for ch in root.children:
        if not ch.name.startswith("w."):
            continue
        tag = ch.name.split("#", 1)[1].split(".")[0]
        try:
            i = int(tag[len(design) :])
        except ValueError:
            continue
        rad = max(wheels[i]["r"], 0.5)
        for fr in (0, 1, 2):
            ch.rotation_euler[0] = -SPEED * dt * (fr - 1) / rad
            ch.keyframe_insert("rotation_euler", index=0, frame=fr)
        key_linear(ch)
    return root


def set_camera(bpy, co, cam, lead, rig):
    """Puts the camera where the shot's rig says, relative to the lead car, and keys it
    to move with the car so motion blur streaks the background, not the car.
    """
    from mathutils import Vector

    pos, r, f, up = lead
    R = RIGS[rig]

    def at(o):
        return pos + up * 1.95 + r * o[0] + f * o[1] + up * o[2]

    eye, look = at(R["eye"]), at(R["look"])
    cam.lens = R["lens"]
    cam.shift_x = R.get("shift", SHIFT_X)
    cam.dof.use_dof = True
    cam.dof.focus_distance = float(np.linalg.norm(eye - (pos + up * 1.95)))
    cam.dof.aperture_fstop = R["fstop"]
    dt = 1.0 / FPS
    co.animation_data_clear()
    co.rotation_euler = (Vector(tuple(look)) - Vector(tuple(eye))).to_track_quat("-Z", "Y").to_euler()
    for fr in (0, 1, 2):
        co.location = tuple(eye + f * SPEED * dt * (fr - 1))
        co.keyframe_insert("location", frame=fr)
    key_linear(co)


def place_cars(bpy, data, cars, frac):
    """The lead car on the racing line at `frac` of the lap, the others a few lengths
    behind on alternating sides. Returns (roots, lead pose)."""
    objs, anchors = promo.load()
    tb = lap_points(data)
    L = lap_length(tb)
    slots = [(0.0, -3.5), (-19.0, 4.0), (-38.0, -2.0), (-57.0, 3.0)]
    roots, lead = [], None
    for k, design in enumerate(cars):
        back, lat = slots[k % len(slots)]
        p, fwd = point_at(tb, frac + back / L)
        right = np.cross(fwd, [0, 0, 1])
        right /= max(np.linalg.norm(right), 1e-6)
        g, up = ground(bpy, p + right * lat, fwd)
        r, f, u = frame_of(fwd, up)
        roots.append(place_car(bpy, objs, anchors, design, LIVERY_OF[design], g, r, f, u))
        if lead is None:
            lead = (g, r, f, u)
    return roots, lead


def remove_cars(bpy, roots):
    """Deletes the cars from the scene (between shots)."""
    for root in roots:
        for ch in list(root.children_recursive):
            bpy.data.objects.remove(ch, do_unlink=True)
        bpy.data.objects.remove(root, do_unlink=True)


def build(cid, cars, frac, rig="front"):
    """Circuit + cars + camera. Returns (bpy, scene, camera object, camera data, cars, lead pose, data)."""
    data = json.loads((OUT / f"{cid}.json").read_text())
    render3d.JITTER = 0.004
    render3d.build_scene(data)
    render3d.setup_world(data)
    import bpy

    # Roblox lights shadows with ambient light: brighten the sky's fill so shadows under
    # buildings read as shade, not black holes
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    if not (data.get("sky") or {}).get("night"):
        bg.inputs["Strength"].default_value = FILL
    else:
        bpy.context.scene.view_settings.exposure = NIGHT_EV

    promo.bpy = bpy
    roots, lead = place_cars(bpy, data, cars, frac)
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    cam.clip_end = 30000
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    set_camera(bpy, co, cam, lead, rig)
    return bpy, sc, co, cam, roots, lead, data


def render_settings(sc, size, samples):
    """Cycles settings for a shot: size, samples, motion blur."""
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    try:
        sc.cycles.use_denoising = True
        sc.cycles.use_adaptive_sampling = True
        sc.cycles.max_bounces = 6
    except Exception:
        pass
    sc.render.use_persistent_data = True
    sc.render.use_motion_blur = True
    sc.render.motion_blur_shutter = 0.6
    sc.render.fps = FPS
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.frame_set(1)


def preview(cid, cars=("gt1", "falcon"), fracs=None, rigs=None):
    """A contact sheet of quick low-quality renders: rows = points of the lap, columns = rigs."""
    from PIL import Image, ImageDraw

    rigs = rigs or ["front", "frontl", "chase", "side", "low", "high"]
    fracs = fracs or [0.02, 0.12, 0.24, 0.36, 0.48, 0.6, 0.72, 0.84]
    bpy, sc, co, cam, roots, lead, data = build(cid, list(cars), fracs[0], rigs[0])
    render_settings(sc, (384, 216), 6)
    sc.render.use_motion_blur = False
    tiles = []
    for i, fr in enumerate(fracs):
        if i > 0:
            remove_cars(bpy, roots)
            roots, lead = place_cars(bpy, data, list(cars), fr)
        for rig in rigs:
            set_camera(bpy, co, cam, lead, rig)
            sc.frame_set(1)
            path = OUT / f"pv_{cid}_{fr:.2f}_{rig}.png"
            sc.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            tiles.append((path, f"{fr:.2f} {rig}"))
    cols = len(rigs)
    sheet = Image.new("RGB", (384 * cols, 216 * len(fracs)), (0, 0, 0))
    d = ImageDraw.Draw(sheet)
    for i, (path, label) in enumerate(tiles):
        x, y = (i % cols) * 384, (i // cols) * 216
        sheet.paste(Image.open(path).convert("RGB"), (x, y))
        d.rectangle([x, y, x + 110, y + 14], fill=(0, 0, 0))
        d.text((x + 4, y + 1), label, fill=(255, 255, 0))
        Path(path).unlink()
    out = OUT / f"preview_{cid}.jpg"
    sheet.save(out, quality=85)
    print(out)


def clip(cid, cars, frac, rig, seconds, out_dir, size=(960, 540), samples=12, speed=SPEED, fps=FPS):
    """An animated shot for the trailer: the cars drive along the lap at `speed`, the camera
    rig tracks the lead car, wheels spin, Cycles motion blur. Writes out_dir/f_0001.png..."""
    data = json.loads((OUT / f"{cid}.json").read_text())
    render3d.JITTER = 0.004
    render3d.build_scene(data)
    render3d.setup_world(data)
    import bpy
    from mathutils import Matrix

    promo.bpy = bpy
    sc = bpy.context.scene
    if not (data.get("sky") or {}).get("night"):
        sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = FILL
    else:
        sc.view_settings.exposure = NIGHT_EV
    objs, anchors = promo.load()
    tb = lap_points(data)
    L = lap_length(tb)
    n = int(round(seconds * fps))
    slots = [(0.0, -3.5), (-19.0, 4.0), (-38.0, -2.0), (-57.0, 3.0)]
    # poses first (ray casts must not hit the cars), frames 0..n+1
    poses = []
    for k, design in enumerate(cars):
        back, lat = slots[k % len(slots)]
        v = speed * (1.0 - 0.015 * k)  # the chasers are a hair slower: the gap opens a little
        row = []
        for fr in range(n + 2):
            dist = frac * L + back + v * (fr - 1) / fps
            p, fwd = point_at(tb, dist / L)
            right = np.cross(fwd, [0, 0, 1])
            right /= max(np.linalg.norm(right), 1e-6)
            g, up = ground(bpy, p + right * lat, fwd)
            row.append((g, up, fwd, v))
        poses.append(row)

    # smooth normals and headings over time (the road is built from flat pieces)
    def smooth(row, k=4):
        out = []
        for i in range(len(row)):
            js = range(max(0, i - k), min(len(row), i + k + 1))
            up = np.mean([row[j][1] for j in js], axis=0)
            fw = np.mean([row[j][2] for j in js], axis=0)
            z = np.mean([row[j][0][2] for j in js])
            g = row[i][0].copy()
            g[2] = z
            out.append((g,) + frame_of(fw / np.linalg.norm(fw), up / np.linalg.norm(up)))
        return out

    frames = [smooth(row) for row in poses]
    lead_frames = frames[0]
    for k, design in enumerate(cars):
        root = promo.add_car(
            objs,
            anchors,
            design,
            LIVERY_OF[design],
            promo.VARS.get(design, ()),
            promo.PATS.get(design, "stripe"),
            design in ("nova", "neonracer"),
            (0, 0, 0),
            0.0,
            "turbine",
        )
        root.rotation_mode = "QUATERNION"
        wheels = anchors[design]["wheels"]
        spin = [c for c in root.children if c.name.startswith("w.")]
        for fr, (g, r, f, u) in enumerate(frames[k]):
            root.location = tuple(g + u * 1.95)
            root.rotation_quaternion = Matrix(
                ((r[0], f[0], u[0]), (r[1], f[1], u[1]), (r[2], f[2], u[2]))
            ).to_quaternion()
            root.keyframe_insert("location", frame=fr)
            root.keyframe_insert("rotation_quaternion", frame=fr)
            travelled = poses[k][0][3] * fr / fps
            for ch in spin:
                tag = ch.name.split("#", 1)[1].split(".")[0]
                try:
                    i = int(tag[len(design) :])
                except ValueError:
                    continue
                ch.rotation_euler[0] = -travelled / max(wheels[i]["r"], 0.5)
                ch.keyframe_insert("rotation_euler", index=0, frame=fr)
        key_linear(root)
        for ch in spin:
            key_linear(ch)
    cam = bpy.data.cameras.new("cam")
    cam.clip_end = 30000
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    R = RIGS[rig]
    cam.lens = R["lens"]
    cam.shift_x = R.get("shift", 0.0)
    cam.dof.use_dof = True
    cam.dof.aperture_fstop = R["fstop"]
    from mathutils import Vector

    for fr, (g, r, f, u) in enumerate(lead_frames):
        base = g + u * 1.95
        eye = base + r * R["eye"][0] + f * R["eye"][1] + u * R["eye"][2]
        look = base + r * R["look"][0] + f * R["look"][1] + u * R["look"][2]
        co.location = tuple(eye)
        co.rotation_euler = (Vector(tuple(look)) - Vector(tuple(eye))).to_track_quat("-Z", "Y").to_euler()
        cam.dof.focus_distance = float(np.linalg.norm(eye - base))
        co.keyframe_insert("location", frame=fr)
        co.keyframe_insert("rotation_euler", frame=fr)
        cam.keyframe_insert("dof.focus_distance", frame=fr)
    key_linear(co)
    render_settings(sc, size, samples)
    sc.frame_start, sc.frame_end = 1, n
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(Path(out_dir) / "f_")
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(animation=True)
    print("clip", cid, n, "frames ->", out_dir)


def shot(cid, size=(1920, 1080), samples=96):
    """Renders one store thumbnail."""
    s = SHOTS[cid]
    bpy, sc, co, cam, roots, lead, data = build(cid, s["cars"], s["frac"], s["rig"])
    render_settings(sc, size, samples)
    out = OUT / f"showcase_{cid}.png"
    sc.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    print(out)


def card(cid):
    """Logo top-left and the circuit's name under it (nothing at the bottom, where Roblox
    draws the player count)."""
    from PIL import Image
    import overlay as ov

    s = SHOTS[cid]
    img = Image.open(OUT / f"showcase_{cid}.png").convert("RGBA")
    ov.left_fade(img, 1000, s.get("fade", 190))
    yb = ov.logo(img, 70, 52, 118)
    ov.shadow_text(img, (76, yb + 26), s["title"], ov.font(ov.BI, 64), (255, 255, 255, 255), blur=6, off=(3, 5))
    ov.shadow_text(img, (80, yb + 104), s["sub"], ov.font(ov.B, 38), (255, 214, 40, 255), blur=5, off=(3, 4))
    CARDS.mkdir(parents=True, exist_ok=True)
    out = CARDS / f"GoTrack_{cid}.png"
    rgb = img.convert("RGB")
    rgb.save(out, optimize=True)
    if out.stat().st_size > 2_900_000:  # Roblox takes thumbnails under 3 MB
        out.unlink()
        out = out.with_suffix(".jpg")
        rgb.save(out, quality=93)
    print(out, out.stat().st_size)


if __name__ == "__main__":
    cmd, cid = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None
    if cmd == "preview":
        fracs = [float(v) for v in sys.argv[3].split(",")] if len(sys.argv) > 3 else None
        rigs = sys.argv[4].split(",") if len(sys.argv) > 4 else None
        preview(cid, fracs=fracs, rigs=rigs)
    elif cmd == "shot":
        size = tuple(int(v) for v in (sys.argv[3] if len(sys.argv) > 3 else "1920x1080").split("x"))
        samples = int(sys.argv[4]) if len(sys.argv) > 4 else 96
        shot(cid, size, samples)
    elif cmd == "card":
        card(cid)
    elif cmd == "clip":
        # showcase.py clip <id> <frac> <rig> <seconds> <out_dir> [WxH] [samples] [car,car,...]
        size = tuple(int(v) for v in (sys.argv[7] if len(sys.argv) > 7 else "960x540").split("x"))
        samples = int(sys.argv[8]) if len(sys.argv) > 8 else 12
        cars = sys.argv[9].split(",") if len(sys.argv) > 9 else ["gt1", "falcon", "aeros"]
        clip(cid, cars, float(sys.argv[3]), sys.argv[4], float(sys.argv[5]), sys.argv[6], size, samples)
