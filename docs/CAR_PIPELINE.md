# 3D car pipeline (`tools/cargen/`)

Every car mesh in the game comes from Python code run through Blender's `bpy` module. Nothing is hand-modelled. That's why all 13 chassis share one hitbox and one set of anchors while looking completely different.

```
designs.py / wheels.py  ──►  build.py export  ──►  .fbx + manifest.json
                                                      │            │
               Bardan: Studio File → Import 3D ◄──────┘            │
                              │                                    ▼
        MeshParts → ReplicatedStorage.CarMeshes           gen_luau.py → src/shared/CarData.luau
                              │
         Save to File → extract_meshes.py → assets/CarMeshes.rbxmx (Rojo)
                              │
                 CarBuilder.luau assembles cars in-game
```

## Files

| File | What it does |
|---|---|
| `geo.py` | Geometry core: lofts, superellipse sections, offsets, clipping, welding |
| `parts.py` | Reusable parts: wing elements, endplates, arcs, suspension |
| `details.py` | Signature F1 details: wheel deflectors, louvres, nose cams, pitot, T-wing, X-wings, horns, chimneys, flip-ups, in-wash boards, airbox ears, DRS pod, mirror pylons, overbite lip, light bars |
| `designs.py` | **The 13 car designs.** One function per design, plus shared helpers (`open_wheeler`, `std_anchors`, `auto_liv`, …) and the `SIGNATURE` table at the bottom (each car's era-defining details) |
| `wheels.py` | Shared meshes: tyres, rims (7 styles), helmet (`helmet2`), headrest, steering wheels (`steering_modern`, `steering_round`) |
| `build.py` | CLI: `render` / `sheet` previews and `export` FBX + manifest. `DESIGNS` maps design code → builder |
| `gen_luau.py` | `manifest.json` → `src/shared/CarData.luau`. Also holds **PRESETS** (chassis id → design + first-generation fallback) and **ROUND_WHEEL** |
| `merge_manifest.py` | Merges a partial export's manifest into `assets/cars/manifest.json` |
| `extract_meshes.py` | Pulls `ReplicatedStorage.CarMeshes` out of a saved `.rbxlx` into `assets/CarMeshes.rbxmx` |
| `export_helmet.py` | Exports only the helmet meshes (small FBX for quick re-import) |
| `promo.py` / `overlay.py` | Store art: Cycles renders of cars at a venue, then titles with PIL (see below) |

## Designs and chassis

Every chassis is built around one real F1 idea (shapes only, no team names or logos), so the 13 silhouettes can't be mixed up:

| Chassis id = design code | Builder | Real-F1 signature | First-gen code |
|---|---|---|---|
| gt1 | `modern` | 2026 spec: tight downwash sidepods with a deep undercut and overbite inlet, cooling gills, in-wash boards, no beam wing, rwA | mod |
| aeros | `aeros` | 2022 zero-pod: slot sidepods, mirrors on tall vanes, wheel deflectors | aer |
| stealth | `stealth` | stealth jet: faceted body, chined canards, dorsal spine, flat flap | stl |
| nova | `nova` | hypercar concept: cycle fenders, headlight blades, fender tail lights | nov |
| neonracer | `neonracer` | 2004 walrus-nose tribute: twin tusks with glowing fangs, neon | neo |
| arrow | `hybrid` | 2017: giant shark fin into the rear wing, twin T-wing, boomerang wing, nose cape, rwA | hyb |
| falcon | `falcon` | 2014 finger nose, narrow tall rear wing, airbox ears, no halo | fal |
| viper | `viper` | 2012 step nose, huge shark fin, F-duct snorkel, double-deck diffuser | vip |
| vortex | `r88` | 1988 turbo: long flat pods with NACA ducts and vents, wastegate pipe, round wheel | r88 |
| apex | `v10` | 2006-08 winglet mania: horns, X-wing towers, chimneys, flip-ups, "twin tower" nose wing, grooved tyres, rwA | v10 |
| aurora | `aurora` | closed-canopy concept with a framed canopy and light bar | aur |
| retro70 | `r70` | 1976 "teapot" airbox, open V8 with intake trumpets, round wheel | r70 |
| retro90 | `r92` | 1990 high nose with a gull-wing front wing slung underneath | r92 |

The default colours for each chassis live in `Cosmetics.BodyLivery`. The shop item is in `Cosmetics.luau` (`add({ Id = "gt1", … Category = "Body", Era = "…" })`; `Era` is shown in the Garage).

**Two generations of meshes.** The current meshes are named after the chassis (`gt1.Body.Primary`). The first-generation meshes (`mod.Body.Primary`, …) stay in `assets/cars/manifest.json` and `CarData` as `Presets[id].Old`. `CarBuilder.Build` uses the newest set that is imported in `ReplicatedStorage.CarMeshes`, so the game keeps working before and after the Studio import. Once the new FBX is imported and extracted, the first-generation objects can be deleted from the manifest and `CarMeshes`.

**Active-aero flap.** `rw_elements` puts the top rear-wing element (slot `Secondary`) in its own `Flap` group and records its trailing-edge hinge in the anchors (`CarData.Designs[..].Flap`). In game the flap hangs off a hinge part: `CarBuilder.SetFlap(parts.Flap, 0..1)` opens it (straight mode, `Config.Car.ActiveAero`). Designs without a `Secondary` rear element (aurora, retro70) simply have no moving flap.

## Conventions

- Designs are written in **car metres**: x right, y up, z towards the rear, nose at −z. `designs.to_studs` converts with SX 2.9, SY 2.75, SZ 2.65, YG −1.95 and ZC 1.72. Keep the wheelbase and track inside the shared hitbox (5.7 × 1.2 × 14.6 studs).
- Mesh object names:
  - `<design>.<Group>.<Slot>`, for example `aer.Body.Primary`;
  - variants: `<design>.v.<key>.<Group>.<Slot>`;
  - livery overlays: `<design>.p.<pattern>.<Group>`;
  - shared: `w.*` wheels, `h2.*` helmet, `sw.*` modern wheel, `swr.*` round wheel.
- **Slots** decide the colour in game: `Primary`, `Secondary`, `Accent`, `Carbon`, `Halo`, `Dark`, `Glass`, `Canopy`, `Metal`, `TailLight`, `Light` (white glow), `TCam`, `Suit`.
- **Groups**: `Body`, `FrontWing`, `RearWing`, `LeftPod`, `RightPod` (the last four break off in crashes) and `Flap` (moving rear flap, breaks off with the rear wing).
- Blender → Roblox axes: export uses `axis_forward=-Z, axis_up=Y`. Roblox then rotates imports 180° about Y, which is why every placement uses `MESH_FIX` in `CarBuilder`.
- Watertight, outward-facing geometry. Roblox rejects flat degenerate caps: recess them (`recess()` in designs.py).

## Preview a design (no Studio needed)

```bash
cd tools/cargen
python3 build.py sheet aeros /tmp/aeros.png                      # 4 views in its in-game colours (~30 s)
python3 build.py render aeros none /tmp/aeros.png front34        # one view: fast, no livery overlays
python3 build.py render aeros stripe /tmp/aeros_stripe.png side  # with a livery pattern
```

- Views: `front34`, `rear34`, `side`, `top`, `front`, `close`, `rclose`.
- Patterns: `stripe`, `side`, `split`, `chevron`, `checker`, `flames`, `retro`, `circuit`, `carbon`, or `none`.
- **Look at the render before exporting.**

## Add a new chassis (checklist)

1. Write `def mycar():` in `designs.py`. Copy the closest existing design and change its sections, wings and sidepods. It must call `std_anchors(...)` so it gets wheels, head, cams and number plates.
2. Register it in `build.py`: `DESIGNS["myc"] = designs.mycar`.
3. Preview it from several views. Make sure it's visibly different from all 13 others.
4. Export **only the new design**, without the shared parts:
   `python3 build.py export ../../assets/cars/GoTrackCars_myc.fbx ../../assets/cars/manifest_myc.json myc False`
5. Merge it and regenerate:
   `python3 merge_manifest.py ../../assets/cars/manifest.json ../../assets/cars/manifest_myc.json`
   `python3 gen_luau.py ../../assets/cars/manifest.json ../../src/shared/CarData.luau`
6. Add the chassis in `gen_luau.py` `PRESETS` (and `ROUND_WHEEL` if it has a classic round wheel), then re-run step 5's `gen_luau.py`.
7. In `Cosmetics.luau`, add the Body item (price or pass) and a `BodyLivery` entry.
8. **Bardan imports the FBX in Studio.** An agent can't drive the file picker.
   1. Studio → File → Import 3D → pick the FBX → Import.
   2. Move all the new MeshParts into `ReplicatedStorage.CarMeshes`. Names must match the manifest. Paste this into the command bar (change the model name to the imported one):
      `local src = workspace:FindFirstChild("GoTrackCars") local dst = game.ReplicatedStorage.CarMeshes local n = 0 for _, p in src:GetDescendants() do if p:IsA("MeshPart") then local old = dst:FindFirstChild(p.Name) if old then old:Destroy() end p.Anchored = true p.Parent = dst n += 1 end end src:Destroy() print("moved", n)`
   3. File → Save to File.
9. Refresh the Rojo asset: `python3 tools/cargen/extract_meshes.py GoTrackRacing.rbxlx assets/CarMeshes.rbxmx`.
10. Run `bash tools/check.sh`, build, and look at the car in the Garage and in cockpit view.

Changing an existing design works the same way. Export just that design (step 4), and replace its old MeshParts in `CarMeshes` when Bardan imports.

**Imported (2026-09-30):** `assets/cars/GoTrackCars.fbx` holds all 13 current designs (633 meshes, ~350k triangles). They are in `ReplicatedStorage.CarMeshes` / `assets/CarMeshes.rbxmx`. The first-generation meshes are still there as a fallback. `lune run tools/sim/cars.luau` checks both cases.

## Store art

`promo.py` renders with Cycles (Nishita sky, AgX): the cars at a small venue with barriers, grandstands and trees.

```bash
cd tools/cargen
python3 promo.py cache                  # build all car geometry once → promo_cache.pkl (~34 MB, git-ignored)
python3 promo.py icon   /tmp/art/f_icon.png
python3 promo.py hero   /tmp/art/f_hero.png
python3 promo.py lineup /tmp/art/f_lineup.png
python3 promo.py battle /tmp/art/f_battle.png
python3 overlay.py /tmp/art ../../assets/launch   # adds titles → icon 512 + 3 thumbnails 1920×1080
```

- `PROMO_TEST=1` renders quick low-res tests.
- A full render takes about 10 minutes on 2 CPU cores.
- Fonts are Poppins. Poppins has no arrow or emoji glyphs, so use `›` or `•`.
