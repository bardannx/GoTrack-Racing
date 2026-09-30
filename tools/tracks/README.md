# Circuit layout tools

Work in a scratch copy: these scripts read/write `Circuits.luau` and `Track.luau` **in this folder**.

```bash
cd tools/tracks
cp ../../src/shared/Circuits.luau .
sed 's#require(script.Parent.Circuits)#require("./Circuits")#' ../../src/shared/Track.luau > Track.luau
luau stats.luau        # length, laps, corners, tightest radius per circuit
luau gridcheck.luau    # warns if a grid / start straight is curved
luau dump2.luau > dense.json && python3 twistify.py   # auto "twistify" every layout -> twist_ov.json
python3 tune.py twist_ov.json lakeside sakura          # score + plot (tune.png) chosen circuits
```

- **Fun score** (what `tune.py` prints): `slow<170` = braking zones per lap, `<140` = hairpins, `flat` = % of the lap at top speed, `close` = road sections running into each other (must be 0; sakura's bridge crossover reads ~17).
- **Targets the circuits were tuned to:** 7–15 braking zones, ≥2 hairpins, flat ≤ 45%, close = 0.
- `poly.py` turns a rounded polygon `(x, z, height, cornerRadius)` into a Points string, which is the easiest way to design a new circuit.
- Needs the `luau` CLI (set `LUAU=/path/to/luau` if it's not on PATH), Python 3 and matplotlib.
