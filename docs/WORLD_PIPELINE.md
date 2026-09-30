# World meshes (`tools/worldgen/`)

The buildings, trees, rocks, mountains and road cars around every circuit can come from Blender, like the cars. The same Python code (`bpy` as a module) makes the meshes, exports one FBX and writes the Luau data file the game reads.

```
designs.py ──► build.py export ──► assets/world/GoTrackWorld.fbx + manifest.json
                                          │                 │
            by hand: Studio File → Import 3D                 │
                          │                                  ▼
     MeshParts → ReplicatedStorage.WorldMeshes     build.py luau → src/shared/WorldData.luau
                          │
     Save to File → extract_meshes.py → assets/WorldMeshes.rbxmx (Rojo)
                          │
     WorldMeshes.luau places them (Cityscape, Architecture, props, horizon, traffic)
```

**The game never depends on the meshes.** If `ReplicatedStorage.WorldMeshes` is empty, `WorldMeshes.Available()` is false and every system uses its part-built version (cheap 2-4 part buildings, part trees, block mountains). Everything is tested both ways: `lune run tools/sim/maps.luau 3 --meshes` pretends the meshes are imported.

## Files

| File | What it does |
|---|---|
| `tools/worldgen/geom.py` | Polygon toolkit in Roblox studs: boxes, prisms, lofts, frustums, cones, gable/hip roofs, lumpy low-poly spheres, heightfields, window panes |
| `tools/worldgen/designs.py` | **The 37 designs** (below). One function per design, returning `{slot: faces}` |
| `tools/worldgen/build.py` | CLI: `stats`, `sheet` (preview picture), `export` (FBX + manifest), `luau` (WorldData.luau) |
| `src/shared/WorldData.luau` | Generated. Per design: kind, footprint, height, and each MeshPart's centre and size |
| `src/client/WorldMeshes.luau` | Clones and places a design: scale, colours per slot, night windows, neon lights |
| `src/client/Cityscape.luau` | Fills the land out to the horizon: city grids with downtowns, suburbs, villages, forests, ponds, hills, rock formations, cranes, sports grounds, far traffic |
| `tools/sim/render3d.py` | Cycles render of a whole circuit from a `maps.luau --dump` (loads the real mesh geometry for MeshParts) |

## Designs

| Kind | Designs |
|---|---|
| Skyscrapers | `tower_glass` (setback glass tower), `tower_deco` (art-deco stone with spire), `tower_twist` (twisting), `tower_round` (cylinder with ring balconies), `tower_blade` (tapering shard), `tower_twin` (twin towers with skybridge), `tower_stack` (stacked offset boxes), `tower_resi` (residential slab with balconies) |
| Midrises | `mid_office`, `mid_apart`, `mid_euro` (mansard roof, dormers, shopfront), `mid_loft` (brick with water tower), `mall` |
| Houses | `house_gable`, `house_hip`, `house_modern`, `house_villa` |
| Trees | `tree_oak`, `tree_pine`, `tree_snowpine`, `tree_palm`, `tree_cypress`, `tree_birch`, `tree_cherry`, `tree_jungle`, `tree_acacia`, `bush` |
| Rocks / land | `rock_a`, `rock_b`, `rock_spire` (canyon hoodoo), `mtn_peak`, `mtn_ridge`, `mtn_mesa`, `hill` |
| Vehicles | `car_sedan`, `car_suv`, `bus` |

**Slots** decide colour and material in game (defaults in `WorldMeshes.Default`, building colours per country in `Architecture.MeshPaint`): `Glass`, `Frame`, `Wall`, `Trim`, `WinA` / `WinB` (two random halves of the windows, so at night one or both glow), `Roof`, `Accent`, `Beacon`, `Leaf`, `Trunk`, `Snow`, `Rock`, `Base` (ground colour), `Band`, `Body`, `Dark`, `Light`, `TailLight`.

Conventions: units are studs (a floor is ~9-10 studs, a person ~5). A design stands on the ground at its origin and its facade faces **-Z** (towards the track). Object names are `<design>.<Slot>`. Export axes and the 180° import turn are the same as the cars (`MESH_FIX` in `WorldMeshes.luau`). Keep every mesh under 9,000 triangles (`build.py stats` flags it); the whole set is ~27k.

## Change or add a design

```bash
python3 tools/worldgen/build.py stats
python3 tools/worldgen/build.py sheet /tmp/world.png tower_glass,tree_oak   # look at it
python3 tools/worldgen/build.py export assets/world/GoTrackWorld.fbx assets/world/manifest.json
python3 tools/worldgen/build.py luau assets/world/manifest.json src/shared/WorldData.luau
```

Then use it: buildings go in `Architecture` (`MESH_SUB`: which part archetype it replaces) or `Cityscape` (`TOWER_STYLE`, `MIDS`, `HOUSES`), props in `CircuitBuilder` (`PROP_MESH`). A new or changed design needs a new Studio import.

## Both imports at once (cars + world, about 5 minutes)

1. Studio → File → Import 3D → `assets/cars/GoTrackCars.fbx` → Import. Then File → Import 3D → `assets/world/GoTrackWorld.fbx` → Import.
2. Paste this into the command bar and press Enter. It should print `cars 633 world 146`:
   `local function move(model, folder) local src = workspace:FindFirstChild(model) if not src then warn("not imported: " .. model) return 0 end local dst = game.ReplicatedStorage:FindFirstChild(folder) or Instance.new("Folder", game.ReplicatedStorage) dst.Name = folder local n = 0 for _, p in src:GetDescendants() do if p:IsA("MeshPart") then local old = dst:FindFirstChild(p.Name) if old then old:Destroy() end p.Anchored = true p.CanCollide = false p.CollisionFidelity = Enum.CollisionFidelity.Box p.Parent = dst n += 1 end end src:Destroy() return n end print("cars", move("GoTrackCars", "CarMeshes"), "world", move("GoTrackWorld", "WorldMeshes"))`
3. File → Save to File (over `GoTrackRacing.rbxlx`).
4. In the VS Code terminal:
   `python3 tools/cargen/extract_meshes.py GoTrackRacing.rbxlx assets/CarMeshes.rbxmx && python3 tools/cargen/extract_meshes.py GoTrackRacing.rbxlx assets/WorldMeshes.rbxmx WorldMeshes`
   then commit and sync.

## Import only the world meshes (about 5 minutes)

1. Studio → File → Import 3D → pick `assets/world/GoTrackWorld.fbx` → Import.
2. Paste this into the command bar and press Enter. It moves the 146 meshes into `ReplicatedStorage.WorldMeshes`:
   `local src = workspace:FindFirstChild("GoTrackWorld") local dst = game.ReplicatedStorage:FindFirstChild("WorldMeshes") or Instance.new("Folder", game.ReplicatedStorage) dst.Name = "WorldMeshes" local n = 0 for _, p in src:GetDescendants() do if p:IsA("MeshPart") then local old = dst:FindFirstChild(p.Name) if old then old:Destroy() end p.Anchored = true p.CanCollide = false p.CastShadow = false p.CollisionFidelity = Enum.CollisionFidelity.Box p.Parent = dst n += 1 end end src:Destroy() print("moved", n)`
   It should print `moved 146`.
3. File → Save to File (over `GoTrackRacing.rbxlx`).
4. In the VS Code terminal: `python3 tools/cargen/extract_meshes.py GoTrackRacing.rbxlx assets/WorldMeshes.rbxmx WorldMeshes`, then commit and sync.

After that, every circuit uses the meshes automatically (check with Play: skyscrapers with window grids, round low-poly trees, snowy mountain ranges).

## Checking maps without Studio

```bash
lune run tools/sim/maps.luau 3                     # all circuits, part-built fallback
lune run tools/sim/maps.luau 3 --meshes            # as if the world meshes were imported
lune run tools/sim/maps.luau 3 capital --meshes --dump
python3 tools/sim/render3d.py capital --views aerial,start,lap,panorama --size 1280x720 --samples 24
```
