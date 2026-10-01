# tools/sim: run the maps outside Studio

These scripts build every circuit with the real game code (`src/`) using [Lune](https://github.com/lune-org/lune)
(a standalone Luau runtime with Roblox instances and datatypes), so map changes can be checked without opening
Studio.

```bash
lune run tools/sim/maps.luau              # build all circuits at quality 3, print part/light/landmark counts
lune run tools/sim/maps.luau 1            # ... at another Graphics Quality (1-4)
lune run tools/sim/maps.luau 3 harbor loch --dump   # also write tools/sim/out/<id>.json
python3 tools/sim/render.py harbor loch --views aerial,grid,top   # draw pictures (needs numpy + Pillow)
lune run tools/sim/maps.luau 3 --meshes   # pretend the Blender world meshes are imported (placeholders)
lune run tools/sim/roadcheck.luau [quality]   # nothing standing on the road, on every circuit (see below)
lune run tools/sim/ttcheck.luau           # Time Trial anti-cheat: real laps pass, faked laps are rejected
lune run tools/sim/ranked.luau            # ranked: real players only, cross-server grouping, match servers, seasons
python3 tools/sim/render3d.py harbor --views aerial,start,lap,panorama --size 1280x720 --samples 24
```

- `render3d.py` renders a dump in 3D with Blender Cycles (`pip install bpy`): real materials, sky and sun
  from the circuit's time of day, and the real Blender geometry for world-mesh MeshParts (`tools/worldgen`).
  About 10-20 s per view at 960x540.

- `env.luau` mocks the engine-only services (RunService, Players, TweenService, ...) and loads modules from
  `src/` with a `script` that mirrors the Rojo tree, so `require(script.Parent.X)` works unchanged.
- `maps.luau` exits with an error if any circuit fails to build or its per-frame systems (movers, weather,
  ambient effects) throw. Run it after every change to `CircuitBuilder`, `Landmarks`, `WorldLife`,
  `Cityscape`, `WorldMeshes`, `Architecture` or `Themes` - with and without `--meshes`.
- `roadcheck.luau` builds every circuit as the live game does (world meshes, chosen graphics level) and probes
  the space cars and the chase camera use: the full road width up to `CircuitBuilder.RoadClear` studs. Any
  visible or solid part there fails the check, listed with the lines of game code that made it. It also
  prints how many parts `CircuitBuilder`'s own clearance sweep removed ("swept"), which should stay at 0: a
  non-zero count means a builder is placing something on the road and should be fixed at the source.
  Run it at graphics levels 1-4 after any scenery change.
- `env.luau` replaces Lune's `CFrame.lookAt`, which faces a mirrored direction (in Z) in Lune 0.10; without
  the fix every part placed with it came out turned the wrong way.
- `render.py` is a rough painter's-algorithm renderer (flat colours, no textures or particles). Use it to
  judge layout, density and whether circuits look different from each other, not final looks.

Install Lune: download `lune-<version>-linux-x86_64.zip` (or the macOS build) from the Lune GitHub releases
page and put the `lune` binary on your PATH.
