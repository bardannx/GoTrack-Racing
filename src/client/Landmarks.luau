--!nonstrict
-- Signature landmarks and moving life for every circuit (called by CircuitBuilder.Build).
-- Each landmark has a footprint radius, a placement rule and a builder:
--   near    - an open spot close to the track (the default)
--   infield - an open spot inside the lap
--   far     - out on the horizon, big enough to see from anywhere (mountains, statues)
--   sea     - out on the water (needs the "sea" landmark)
--   shore   - along the beach line (needs the "sea" landmark)
--   global  - positioned by the builder itself (sky effects)
--   track   - the builder picks a stretch of track itself (tunnels, banners)
-- Builders get a CFrame on the ground whose LookVector faces the track, and use the
-- helpers below. Moving parts (ferris wheels, boats, animals, cable cars) register a
-- mover; WorldLife animates every mover with one BulkMoveTo per frame.
-- Themes list landmarks by name (Themes.luau); `life` entries add sky / water traffic.

local Arch = require(script.Parent.Architecture)

local Landmarks = {}

-- Shorthand for the colour tables.
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local PI = math.pi
local M = Enum.Material

-- the build context of the landmark being built (set by Landmarks.Build)
local X = nil

-- A part in the landmark being built (through the circuit builder's part maker).
local function P(
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	shape: Enum.PartType?,
	class: string?
): BasePart
	return X.P(X.F, size, cf, color, mat or M.SmoothPlastic, nil, false, shape, class)
end

-- A block.
local function box(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	return P(size, cf, color, mat)
end

-- a true sphere (Roblox balls are always round)
local function ball(d: number, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	return P(Vector3.new(d, d, d), cf, color, mat, Enum.PartType.Ball)
end

-- a stretched sphere: block part with a sphere mesh
local function ellipsoid(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	local p = P(size, cf, color, mat)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- vertical cylinder standing on its centre `cf`
local function vcyl(h: number, d: number, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	return P(Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, PI / 2), color, mat, Enum.PartType.Cylinder)
end

-- cylinder along the local X axis of `cf`
local function hcyl(len: number, d: number, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	return P(Vector3.new(len, d, d), cf, color, mat, Enum.PartType.Cylinder)
end

-- A wedge.
local function wedge(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	return P(size, cf, color, mat, nil, "WedgePart")
end

-- a beam between two world points
local function beam(a: Vector3, b: Vector3, thick: number, color: Color3, mat: Enum.Material?): BasePart?
	local len = (b - a).Magnitude
	if len < 0.05 then
		return nil
	end
	return box(Vector3.new(thick, thick, len), CFrame.lookAt((a + b) / 2, b), color, mat)
end

-- stepped cone (stacked cylinders), bottom diameter d0 -> top d1
local function cone(
	h: number,
	d0: number,
	d1: number,
	steps: number,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	topColor: Color3?
)
	local sh = h / steps
	for k = 0, steps - 1 do
		local d = d0 + (d1 - d0) * (k + 0.5) / steps
		local c = if topColor and k >= steps * 0.72 then topColor else color
		vcyl(
			sh + 0.2,
			d,
			cf * CFrame.new(0, sh * (k + 0.5), 0),
			c,
			if topColor and k >= steps * 0.72 then M.Snow else mat
		)
	end
end

-- A point light on `part`, while the circuit's light budget lasts (lights are costly).
local function light(part: BasePart, color: Color3, range: number, brightness: number?)
	if X.Lights <= 0 then
		return
	end
	X.Lights -= 1
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 2
	l.Shadows = false
	l.Parent = part
end

-- A smoke plume from `part` (volcanoes, waterfall mist, chimneys).
local function smoke(part: BasePart, color: Color3, size0: number, size1: number, rate: number, speed: number)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(color)
	pe.Size = NumberSequence.new(size0, size1)
	pe.Transparency = NumberSequence.new(0.35, 1)
	pe.Lifetime = NumberRange.new(4, 7)
	pe.Rate = rate
	pe.Speed = NumberRange.new(speed * 0.7, speed)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = part
	return pe
end

-- Bright particles from `part` (lava sparks, embers, waterfall spray, fountain jets).
local function sparkle(part: BasePart, color: Color3, rate: number, speed: number, size: number, life: number?)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 0.8
	pe.Size = NumberSequence.new(size, 0)
	pe.Lifetime = NumberRange.new(life or 1.2, (life or 1.2) * 1.6)
	pe.Rate = rate
	pe.Speed = NumberRange.new(speed * 0.7, speed)
	pe.SpreadAngle = Vector2.new(12, 12)
	pe.Acceleration = Vector3.new(0, -speed * 0.5, 0)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = part
	return pe
end

-- Text on one face of a part.
local function sign(part: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	X.Text(part, face, text, color, bg)
end

-- Random entry from a list, using the circuit's seeded random.
local function pick(list)
	return list[X.Rng:NextInteger(1, #list)]
end

-- Random number between a and b, using the circuit's seeded random.
local function rnd(a: number, b: number): number
	return X.Rng:NextNumber(a, b)
end

-- moving parts: build them at `baseCF`, `update(now)` returns where baseCF goes
local function mover(parts: { BasePart }, baseCF: CFrame, update: (number) -> CFrame)
	X.Mover(parts, baseCF, update)
end

local SHIRTS = {
	rgb(220, 40, 40),
	rgb(40, 90, 200),
	rgb(250, 250, 250),
	rgb(30, 30, 34),
	rgb(255, 200, 30),
	rgb(40, 160, 80),
	rgb(255, 130, 30),
	rgb(150, 60, 200),
}
local SKIN = { rgb(255, 219, 172), rgb(241, 194, 125), rgb(224, 172, 105), rgb(198, 134, 66), rgb(141, 85, 36) }

-- A simple standing figure (legs, shirt, head) in the home fans' colours.
local function person(cf: CFrame, shirt: Color3?): { BasePart }
	return {
		box(Vector3.new(1.1, 2.1, 0.6), cf * CFrame.new(0, 1.05, 0), rgb(50, 55, 80), M.Fabric),
		box(Vector3.new(1.35, 1.8, 0.75), cf * CFrame.new(0, 3, 0), shirt or pick(X.Th.Fans or SHIRTS), M.Fabric),
		ball(0.9, cf * CFrame.new(0, 4.35, 0), pick(SKIN)),
	}
end

-- a four-legged animal (nose = -Z). Returns its parts.
local function animal(cf: CFrame, s: number, body: Color3, opts): { BasePart }
	opts = opts or {}
	local parts = {}
	local function add(p)
		table.insert(parts, p)
	end
	local legH = (opts.legs or 2.4) * s
	local len = (opts.len or 5) * s
	local bw = (opts.width or 2.2) * s
	local bh = (opts.height or 2.2) * s
	add(box(Vector3.new(bw, bh, len), cf * CFrame.new(0, legH + bh / 2, 0), body))
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		add(
			box(
				Vector3.new(0.55 * s, legH + 0.2, 0.55 * s),
				cf * CFrame.new(o[1] * (bw / 2 - 0.35 * s), legH / 2, o[2] * (len / 2 - 0.5 * s)),
				opts.legColor or body:Lerp(Color3.new(0, 0, 0), 0.25)
			)
		)
	end
	local neckY = legH + bh * (opts.neckUp or 0.9)
	local headZ = -len / 2 - (opts.neck or 0.8) * s
	if opts.neck and opts.neck > 1.5 then
		add(
			beam(
				(cf * CFrame.new(0, legH + bh * 0.8, -len / 2 + 0.4 * s)).Position,
				(cf * CFrame.new(0, neckY + opts.neck * s * 0.7, headZ + 0.4 * s)).Position,
				0.8 * s,
				body
			)
		)
		neckY += opts.neck * s * 0.7
	end
	add(box(Vector3.new(bw * 0.6, bh * 0.6, 1.8 * s), cf * CFrame.new(0, neckY, headZ), opts.head or body))
	if opts.horns then
		add(
			box(
				Vector3.new(bw * (opts.hornSpan or 1.6), 0.3 * s, 0.3 * s),
				cf * CFrame.new(0, neckY + bh * 0.35, headZ + 0.3 * s),
				opts.horns
			)
		)
	end
	if opts.hump then
		add(ball(bh * 0.9, cf * CFrame.new(0, legH + bh, 0), body))
	end
	return parts
end

-- parts orbiting in a circle (radius r around `centre`), facing along the path
local function circler(
	parts: { BasePart },
	baseCF: CFrame,
	centre: Vector3,
	r: number,
	speed: number,
	phase: number,
	bob: number?
)
	mover(parts, baseCF, function(now)
		local a = phase + now * speed / r
		local p = centre
			+ Vector3.new(math.cos(a) * r, (bob or 0) * math.abs(math.sin(now * 5 + phase)), math.sin(a) * r)
		local ahead = centre
			+ Vector3.new(
				math.cos(a + 0.05 * math.sign(speed)) * r,
				p.Y - centre.Y,
				math.sin(a + 0.05 * math.sign(speed)) * r
			)
		return CFrame.lookAt(p, ahead)
	end)
end

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
local Defs = {}
Landmarks.Defs = Defs

-- Registers a landmark: its name, footprint radius, placement rule and builder.
local function def(name: string, radius: number, place: string, build)
	Defs[name] = { R = radius, Place = place, Build = build }
end

-- nice names for the circuit intro screen
Landmarks.Names = {}
-- The name shown for a landmark on the circuit intro.
local function named(name: string, label: string)
	Landmarks.Names[name] = label
end

---------------------------------------------------------------------------
-- Moving life in the sky and on the water
---------------------------------------------------------------------------
local Life = {}
Landmarks.Life = Life

-- sailing boats and motor yachts cruising on the sea (or the lake)
function Life.boats(ctx)
	local n = ({ 2, 4, 6, 8 })[X.Q]
	for k = 1, n do
		local centre
		if ctx.SeaZ then
			centre = Vector3.new(ctx.Cx + rnd(-900, 900), 0.8, ctx.SeaZ + rnd(160, 700))
		elseif ctx.Lake then
			centre = ctx.Lake.Pos + Vector3.new(0, 0.8, 0)
		else
			return
		end
		local r = if ctx.SeaZ then rnd(120, 260) else ctx.Lake.R * rnd(0.35, 0.6)
		local base = CFrame.new(0, -500 - k * 40, 0)
		local parts
		if k % 2 == 0 then
			local hull = if X.Rng:NextNumber() < 0.5 then rgb(250, 250, 250) else rgb(30, 60, 120)
			parts = {
				box(Vector3.new(4, 2, 14), base * CFrame.new(0, 1, 0), hull),
				wedge(Vector3.new(4, 2, 3), base * CFrame.new(0, 1, -8.5) * CFrame.Angles(0, PI, 0), hull),
				box(Vector3.new(0.4, 18, 0.4), base * CFrame.new(0, 11, -1), rgb(220, 220, 225), M.Metal),
				wedge(
					Vector3.new(0.2, 15, 8),
					base * CFrame.new(0, 11, 3) * CFrame.Angles(0, PI, 0),
					rgb(255, 255, 255),
					M.Fabric
				),
			}
		else
			parts = {
				box(Vector3.new(7, 3, 22), base * CFrame.new(0, 1.5, 0), rgb(248, 248, 250)),
				box(Vector3.new(6, 3, 10), base * CFrame.new(0, 4.5, 2), rgb(236, 236, 240)),
				box(Vector3.new(6.2, 1.2, 10.2), base * CFrame.new(0, 5, 2), rgb(40, 60, 90), M.Glass),
				wedge(
					Vector3.new(7, 3, 5),
					base * CFrame.new(0, 1.5, -13.5) * CFrame.Angles(0, PI, 0),
					rgb(248, 248, 250)
				),
			}
		end
		circler(parts, base, centre, r, rnd(8, 16) * (if k % 2 == 0 then 1 else -1), rnd(0, 6))
	end
end

-- an airliner crossing high above, round and round a huge circle
function Life.planes(ctx)
	local base = CFrame.new(0, -700, 0)
	local white, tail = rgb(245, 246, 250), X.Th.Accent
	local parts = {
		box(Vector3.new(5, 5, 44), base, white),
		box(Vector3.new(46, 0.8, 9), base * CFrame.new(0, -1, 2), white),
		box(Vector3.new(14, 0.6, 5), base * CFrame.new(0, 1, 20), white),
		box(Vector3.new(0.6, 9, 7), base * CFrame.new(0, 5, 19), tail),
		hcyl(5, 3, base * CFrame.new(-10, -2.5, 0) * CFrame.Angles(0, PI / 2, 0), rgb(200, 200, 205), M.Metal),
		hcyl(5, 3, base * CFrame.new(10, -2.5, 0) * CFrame.Angles(0, PI / 2, 0), rgb(200, 200, 205), M.Metal),
	}
	if X.Th.Night then
		table.insert(parts, box(Vector3.new(0.8, 0.8, 0.8), base * CFrame.new(-23, -1, 2), rgb(255, 40, 40), M.Neon))
		table.insert(parts, box(Vector3.new(0.8, 0.8, 0.8), base * CFrame.new(23, -1, 2), rgb(40, 255, 80), M.Neon))
	end
	circler(parts, base, Vector3.new(ctx.Cx, 520, ctx.Cz), ctx.Span * 0.9 + 900, 110, rnd(0, 6))
end

-- `count` flocks of birds circling over the circuit at about `height` studs.
local function flock(ctx, colors: { Color3 }, count: number, height: number)
	for g = 1, count do
		local centre = Vector3.new(
			ctx.Cx + rnd(-ctx.Span * 0.6, ctx.Span * 0.6),
			height + rnd(0, 40),
			ctx.Cz + rnd(-ctx.Span * 0.6, ctx.Span * 0.6)
		)
		local base = CFrame.new(0, -600 - g * 10, 0)
		local parts = {}
		for b = 0, 6 do
			local off = CFrame.new((b % 3 - 1) * 5 + rnd(-1, 1), rnd(-2, 2), (b // 3) * 5 + rnd(-1, 1))
			local c = colors[(b % #colors) + 1]
			table.insert(parts, box(Vector3.new(3.2, 0.25, 0.9), base * off * CFrame.Angles(0, 0, 0.35), c))
			table.insert(parts, box(Vector3.new(0.5, 0.5, 1.4), base * off, c))
		end
		circler(parts, base, centre, rnd(80, 220), rnd(24, 40) * (if g % 2 == 0 then 1 else -1), rnd(0, 6))
	end
end

-- Plain birds.
function Life.birds(ctx)
	flock(ctx, { rgb(40, 40, 46), rgb(60, 58, 60) }, ({ 1, 2, 3, 4 })[X.Q], 90)
end

-- Brightly coloured birds for the tropical circuits.
function Life.parrots(ctx)
	flock(ctx, { rgb(230, 40, 40), rgb(40, 180, 70), rgb(255, 200, 30), rgb(40, 120, 230) }, ({ 1, 2, 3, 4 })[X.Q], 70)
end

-- hot air balloons drifting slowly over the circuit
function Life.balloons(ctx)
	local n = ({ 2, 3, 5, 7 })[X.Q]
	for k = 1, n do
		local base = CFrame.new(0, -800 - k * 60, 0)
		local c1, c2 = Color3.fromHSV(rnd(0, 1), 0.75, 1), Color3.fromHSV(rnd(0, 1), 0.7, 1)
		local parts = {
			ellipsoid(Vector3.new(26, 30, 26), base * CFrame.new(0, 26, 0), c1, M.Fabric),
			ellipsoid(Vector3.new(26.4, 12, 26.4), base * CFrame.new(0, 28, 0), c2, M.Fabric),
			vcyl(6, 10, base * CFrame.new(0, 11, 0), c1, M.Fabric),
			box(Vector3.new(4, 3.5, 4), base * CFrame.new(0, 1.75, 0), rgb(150, 105, 60), M.WoodPlanks),
		}
		local centre = Vector3.new(
			ctx.Cx + rnd(-ctx.Span * 0.7, ctx.Span * 0.7),
			rnd(120, 260),
			ctx.Cz + rnd(-ctx.Span * 0.7, ctx.Span * 0.7)
		)
		local phase, r = rnd(0, 6), rnd(60, 180)
		mover(parts, base, function(now)
			local a = phase + now * 0.02
			return CFrame.new(centre + Vector3.new(math.cos(a) * r, math.sin(now * 0.3 + phase) * 8, math.sin(a) * r))
		end)
	end
end

-- aerobatic jets in formation with coloured smoke trails
function Life.jets(ctx)
	local base = CFrame.new(0, -900, 0)
	local parts = {}
	local cols = { rgb(220, 30, 40), rgb(250, 250, 250), rgb(30, 60, 170), rgb(220, 30, 40), rgb(250, 250, 250) }
	local slots = { { 0, 0 }, { -9, 8 }, { 9, 8 }, { -18, 16 }, { 18, 16 } }
	local trails = X.Q >= 2
	for k, s in slots do
		local o = base * CFrame.new(s[1], 0, s[2])
		table.insert(parts, box(Vector3.new(1.6, 1.4, 9), o, rgb(210, 20, 30)))
		table.insert(parts, box(Vector3.new(8, 0.3, 3), o * CFrame.new(0, 0, 1.5), rgb(210, 20, 30)))
		table.insert(parts, box(Vector3.new(0.3, 2.2, 2), o * CFrame.new(0, 1.2, 4), rgb(250, 250, 250)))
		if trails then
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.4, 4.5)
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.4, 4.5)
			local tail = parts[#parts - 2]
			a0.Parent = tail
			a1.Parent = tail
			local tr = Instance.new("Trail")
			tr.Attachment0 = a0
			tr.Attachment1 = a1
			tr.Color = ColorSequence.new(cols[k])
			tr.Transparency = NumberSequence.new(0.2, 1)
			tr.Lifetime = 2.5
			tr.WidthScale = NumberSequence.new(4, 9)
			tr.FaceCamera = true
			tr.LightEmission = 0.2
			tr.Parent = tail
		end
	end
	local centre = Vector3.new(ctx.Cx, 220, ctx.Cz)
	local r = ctx.Span * 0.45 + 200
	mover(parts, base, function(now)
		local a = now * 90 / r
		local p = centre + Vector3.new(math.cos(a) * r, math.sin(a * 2) * 40, math.sin(a) * r)
		local ahead = centre
			+ Vector3.new(math.cos(a + 0.03) * r, math.sin((a + 0.03) * 2) * 40, math.sin(a + 0.03) * r)
		return CFrame.lookAt(p, ahead) * CFrame.Angles(0, 0, math.rad(-35))
	end)
end

---------------------------------------------------------------------------
-- Classics (upgraded from the first map pass)
---------------------------------------------------------------------------
named("lake", "Sparkling lake")
def("lake", 175, "infield", function(cf, ctx)
	local r = 160
	local pos = cf.Position
	hcyl(1, r * 2, CFrame.new(pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, PI / 2), X.Th.Water, M.Glass).Reflectance =
		0.3
	hcyl(
		0.6,
		r * 2 + 16,
		CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, PI / 2),
		rgb(220, 200, 150),
		M.Sand
	)
	-- jetty with a boathouse
	local j = CFrame.new(pos) * CFrame.Angles(0, rnd(0, 6), 0) * CFrame.new(0, 0, -r + 20)
	box(Vector3.new(8, 1, 50), j * CFrame.new(0, 1.2, 10), rgb(140, 100, 60), M.WoodPlanks)
	box(Vector3.new(20, 10, 16), j * CFrame.new(0, 5, -12), rgb(200, 70, 50), M.WoodPlanks)
	wedge(Vector3.new(21, 5, 8.5), j * CFrame.new(0, 12.5, -16.2), rgb(80, 80, 90))
	wedge(Vector3.new(21, 5, 8.5), j * CFrame.new(0, 12.5, -7.8) * CFrame.Angles(0, PI, 0), rgb(80, 80, 90))
	ctx.Lake = { Pos = pos, R = r }
end)

named("ferris", "Giant ferris wheel")
def("ferris", 80, "near", function(cf)
	local r = 60
	local pos = cf.Position
	-- the axle (hub X axis) points at the track so the wheel faces the drivers
	local hub = cf * CFrame.new(0, r + 10, 0) * CFrame.Angles(0, PI / 2, 0)
	for side = -1, 1, 2 do
		for leg = -1, 1, 2 do
			box(
				Vector3.new(3, r + 16, 3),
				hub * CFrame.new(side * 5, 0, 0) * CFrame.Angles(leg * 0.32, 0, 0) * CFrame.new(0, -(r + 12) / 2, 0),
				rgb(230, 230, 235),
				M.Metal
			)
		end
	end
	box(Vector3.new(24, 3, 30), CFrame.new(pos + Vector3.new(0, 1.5, 0)), rgb(60, 62, 70), M.Concrete)
	local rim = {}
	local n = 24
	local rimColor = if X.Th.Night then X.Th.Accent else rgb(240, 240, 245)
	for k = 0, n - 1 do
		local a = k / n * PI * 2
		local chord = 2 * r * math.sin(PI / n) + 0.5
		table.insert(
			rim,
			box(
				Vector3.new(1.5, 1.5, chord),
				hub * CFrame.Angles(a, 0, 0) * CFrame.new(0, r, 0),
				rimColor,
				if X.Th.Night then M.Neon else M.Metal
			)
		)
		if k % 3 == 0 then
			table.insert(
				rim,
				box(
					Vector3.new(0.6, r, 0.6),
					hub * CFrame.Angles(a, 0, 0) * CFrame.new(0, r / 2, 0),
					rgb(200, 200, 210),
					M.Metal
				)
			)
		end
	end
	table.insert(rim, hcyl(6, 8, hub, rgb(90, 92, 100), M.Metal))
	mover(rim, hub, function(now)
		return hub * CFrame.Angles(now * 0.08, 0, 0)
	end)
	-- cabins hang from the rim and stay upright
	for k = 0, n - 1, 3 do
		local a0 = k / n * PI * 2
		local cab = box(
			Vector3.new(6, 5, 5),
			CFrame.new((hub * CFrame.Angles(a0, 0, 0) * CFrame.new(0, r, 0)).Position - Vector3.new(0, 3, 0)),
			Color3.fromHSV(k / n, 0.7, 1)
		)
		local cabBase = cab.CFrame
		mover({ cab }, cabBase, function(now)
			local p = (hub * CFrame.Angles(a0 + now * 0.08, 0, 0) * CFrame.new(0, r, 0)).Position
			return CFrame.new(p - Vector3.new(0, 3, 0))
		end)
	end
end)

named("pagoda_big", "Five-storey pagoda")
def("pagoda_big", 45, "near", function(cf)
	local red, roof = rgb(190, 40, 35), rgb(40, 60, 70)
	box(Vector3.new(60, 4, 60), cf * CFrame.new(0, 2, 0), rgb(200, 195, 185), M.Slate)
	local y = 4
	for k = 0, 4 do
		local w = 38 - k * 5.5
		local h = 13 - k * 1.2
		box(Vector3.new(w, h, w), cf * CFrame.new(0, y + h / 2, 0), red, M.WoodPlanks)
		box(
			Vector3.new(w + 0.3, h * 0.35, w + 0.3),
			cf * CFrame.new(0, y + h * 0.55, 0),
			rgb(245, 225, 170),
			M.WoodPlanks
		)
		y += h
		-- flared roof: a slab with upturned wedge eaves on all four sides
		box(Vector3.new(w + 14, 1.4, w + 14), cf * CFrame.new(0, y + 0.7, 0), roof, M.Slate)
		for q = 0, 3 do
			wedge(
				Vector3.new(w + 14, 2, 3),
				cf
					* CFrame.Angles(0, q * PI / 2, 0)
					* CFrame.new(0, y + 2.2, -(w + 14) / 2 + 1.5)
					* CFrame.Angles(0, PI, 0),
				roof,
				M.Slate
			)
		end
		y += 1.4
		if X.Th.Night or k == 0 then
			for q = 0, 3 do
				local l = ball(
					1.8,
					cf * CFrame.Angles(0, q * PI / 2 + PI / 4, 0) * CFrame.new(0, y - 3, -(w + 12) * 0.7),
					rgb(255, 70, 40),
					M.Neon
				)
				if q == 0 then
					light(l, rgb(255, 120, 60), 30, 1)
				end
			end
		end
	end
	vcyl(16, 1.2, cf * CFrame.new(0, y + 8, 0), rgb(220, 180, 60), M.Metal)
	for k = 0, 5 do
		vcyl(0.6, 3.6 - k * 0.4, cf * CFrame.new(0, y + 2 + k * 2, 0), rgb(220, 180, 60), M.Metal)
	end
end)

named("temple", "Marble temple")
def("temple", 90, "near", function(cf)
	local c = rgb(240, 235, 220)
	box(Vector3.new(120, 6, 60), cf * CFrame.new(0, 3, 0), c, M.Marble)
	for k = 0, 9 do
		for side = -1, 1, 2 do
			vcyl(30, 4, cf * CFrame.new(-54 + k * 12, 21, side * 24), c, M.Marble)
		end
	end
	box(Vector3.new(124, 5, 64), cf * CFrame.new(0, 38, 0), c, M.Marble)
	wedge(Vector3.new(124, 12, 32), cf * CFrame.new(0, 46.5, -16), c, M.Marble)
	wedge(Vector3.new(124, 12, 32), cf * CFrame.new(0, 46.5, 16) * CFrame.Angles(0, PI, 0), c, M.Marble)
	for k = 0, 3 do
		box(
			Vector3.new(128 - k * 4, 1.4, 68 - k * 4),
			cf * CFrame.new(0, 0.7 - k * 0.2, 0),
			c:Lerp(rgb(200, 190, 170), k * 0.2),
			M.Marble
		)
	end
end)

named("casino", "Grand casino")
def("casino", 70, "near", function(cf)
	box(Vector3.new(90, 30, 50), cf * CFrame.new(0, 15, 0), rgb(240, 225, 190), M.Marble)
	ball(34, cf * CFrame.new(0, 34, 0), rgb(80, 140, 110), M.Metal)
	for side = -1, 1, 2 do
		box(Vector3.new(14, 44, 14), cf * CFrame.new(side * 38, 22, -4), rgb(236, 220, 186), M.Marble)
		ball(12, cf * CFrame.new(side * 38, 48, -4), rgb(80, 140, 110), M.Metal)
	end
	for k = -3, 3 do
		vcyl(18, 2.4, cf * CFrame.new(k * 6, 9, -27), rgb(250, 245, 230), M.Marble)
	end
	local s = box(Vector3.new(50, 8, 1), cf * CFrame.new(0, 24, -25.6), rgb(30, 20, 20))
	sign(s, Enum.NormalId.Front, "GRAND CASINO", rgb(255, 210, 90))
	-- fountain roundabout in front
	vcyl(1.5, 30, cf * CFrame.new(0, 0.75, -50), rgb(225, 220, 210), M.Marble)
	vcyl(0.6, 26, cf * CFrame.new(0, 1.3, -50), rgb(60, 150, 210), M.Glass)
	local jet = vcyl(10, 1.4, cf * CFrame.new(0, 6, -50), rgb(210, 235, 255), M.Glass)
	jet.Transparency = 0.4
	for k = 0, 5 do
		Arch.Car(
			X.F,
			cf * CFrame.new(-30 + k * 12, 0, -72) * CFrame.Angles(0, PI / 2, 0),
			pick({ rgb(200, 20, 30), rgb(250, 250, 250), rgb(20, 20, 24), rgb(255, 200, 0) }),
			X.Th.Night,
			X.P
		)
	end
end)

named("stadium", "Stadium section")
def("stadium", 165, "near", function(cf)
	local r = 110
	local pos = cf.Position
	local nseg = if X.Q >= 3 then 32 else 20
	for k = 0, nseg - 1 do
		local a = k / nseg * PI * 2
		for row = 0, 4 do
			local rr = r + row * 8
			local scf = CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 3 + row * 5, -rr)
			box(
				Vector3.new(2 * rr * math.sin(PI / nseg) + 1, 5, 8),
				scf,
				if row % 2 == 0 then rgb(200, 200, 210) else Color3.fromHSV((k * 7 % nseg) / nseg, 0.5, 0.9),
				M.Concrete
			)
		end
		if k % 4 == 0 then
			local mcf = CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(r + 44))
			box(Vector3.new(2, 50, 2), mcf * CFrame.new(0, 25, 0), rgb(70, 72, 80), M.Metal)
			local head = box(Vector3.new(10, 4, 2), mcf * CFrame.new(0, 50, 2), rgb(255, 250, 230), M.Neon)
			if X.Th.Night then
				light(head, rgb(255, 248, 230), 60, 1.5)
			end
		end
	end
	-- pitch in the middle
	hcyl(
		0.5,
		r * 1.6,
		CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, PI / 2),
		rgb(70, 160, 70),
		M.Grass
	)
end)

named("hotel", "Glowing marina hotel")
def("hotel", 100, "near", function(cf)
	for side = -1, 1, 2 do
		box(Vector3.new(40, 60, 120), cf * CFrame.new(side * 50, 30, 0), rgb(235, 235, 240), M.Glass)
	end
	for k = 0, 11 do
		local strip = box(
			Vector3.new(142, 1.5, 3),
			cf * CFrame.new(0, 64, -55 + k * 10) * CFrame.Angles(math.rad(12), 0, 0),
			Color3.fromHSV((k / 12 + 0.55) % 1, 0.7, 1),
			M.Neon
		)
		if k % 4 == 0 then
			light(strip, strip.Color, 50, 1.5)
		end
	end
end)

named("castle", "Old city walls")
def("castle", 110, "near", function(cf)
	local c = rgb(200, 175, 130)
	for k = 0, 3 do
		local a = k * PI / 2
		local wcf = cf * CFrame.Angles(0, a, 0)
		box(Vector3.new(120, 22, 8), wcf * CFrame.new(0, 11, -60), c, M.Sandstone)
		for m = -5, 5 do
			box(Vector3.new(5, 4, 8.4), wcf * CFrame.new(m * 11, 24, -60), c, M.Sandstone)
		end
		Arch.Build("castletower", X.F, wcf * CFrame.new(60, 0, -60), X.Rng, X.Th, X.P)
	end
	Arch.Build("castletower", X.F, cf, X.Rng, X.Th, X.P)
	-- market stalls inside the walls
	for k = 0, 5 do
		local s = cf * CFrame.new(-30 + (k % 3) * 30, 0, -20 + (k // 3) * 40)
		box(Vector3.new(10, 5, 8), s * CFrame.new(0, 2.5, 0), rgb(150, 110, 70), M.WoodPlanks)
		wedge(
			Vector3.new(11, 2.5, 9),
			s * CFrame.new(0, 6.2, 0),
			pick({ rgb(200, 40, 40), rgb(40, 110, 180), rgb(230, 170, 40) }),
			M.Fabric
		)
	end
end)

named("pyramid_big", "Sun pyramid")
def("pyramid_big", 80, "near", function(cf)
	for k = 0, 5 do
		local w = (30 - k * 5) * 4
		box(
			Vector3.new(w, 14, w),
			cf * CFrame.new(0, 7 + k * 14, 0),
			rgb(190, 170, 130):Lerp(rgb(160, 140, 105), k / 6),
			M.Limestone
		)
	end
	-- central staircase
	for k = 0, 20 do
		box(Vector3.new(14, 2, 4), cf * CFrame.new(0, 1 + k * 4, -60 + k * 2.9), rgb(175, 155, 120), M.Limestone)
	end
	box(Vector3.new(14, 12, 14), cf * CFrame.new(0, 90, 0), rgb(170, 90, 60), M.Limestone)
end)

named("windmills", "Old windmills")
def("windmills", 95, "near", function(cf)
	for k = 0, 2 do
		local wcf = cf * CFrame.new(k * 50 - 50, 0, (k % 2) * 30)
		Arch.Build("windmill", X.F, wcf, X.Rng, X.Th, X.P)
	end
end)

named("hangars", "Wartime hangars")
def("hangars", 110, "near", function(cf)
	for k = 0, 2 do
		Arch.Build("hangar", X.F, cf * CFrame.new(k * 56 - 56, 0, 0), X.Rng, X.Th, X.P)
	end
end)

named("tower_floodlit", "Floodlit tower")
def("tower_floodlit", 40, "near", function(cf)
	box(Vector3.new(8, 90, 8), cf * CFrame.new(0, 45, 0), rgb(220, 220, 225), M.Concrete)
	local top = box(Vector3.new(26, 10, 26), cf * CFrame.new(0, 92, 0), X.Th.Accent, M.Neon)
	light(top, X.Th.Accent, 60, 2)
end)

named("orb", "Giant LED sphere")
def("orb", 70, "near", function(cf)
	local o = ball(110, cf * CFrame.new(0, 58, 0), rgb(80, 140, 255), M.Neon)
	o.Transparency = 0.1
	local ring = hcyl(2, 118, cf * CFrame.new(0, 58, 0) * CFrame.Angles(0, 0, math.rad(80)), rgb(255, 200, 60), M.Neon)
	ring.Transparency = 0.2
	box(Vector3.new(60, 6, 60), cf * CFrame.new(0, 3, 0), rgb(40, 42, 50), M.Concrete)
	light(o, rgb(80, 140, 255), 60, 2)
	-- the "screen" slowly changes colour: a second shell spins with a coloured band
	local band = hcyl(24, 111, cf * CFrame.new(0, 58, 0), rgb(255, 60, 200), M.Neon)
	band.Transparency = 0.35
	local base = band.CFrame
	mover({ band }, base, function(now)
		return base * CFrame.Angles(0, now * 0.4, 0) * CFrame.Angles(0, 0, math.sin(now * 0.3) * 0.6)
	end)
end)

named("volcano", "Erupting volcano")
def("volcano", 240, "near", function(cf)
	local pos = cf.Position
	for k = 0, 6 do
		local w = 420 - k * 55
		hcyl(
			40,
			w,
			CFrame.new(pos + Vector3.new(0, 20 + k * 38, 0)) * CFrame.Angles(0, 0, PI / 2),
			rgb(60 + k * 4, 50, 46),
			M.Basalt
		)
	end
	local lava =
		hcyl(6, 70, CFrame.new(pos + Vector3.new(0, 268, 0)) * CFrame.Angles(0, 0, PI / 2), rgb(255, 90, 20), M.Neon)
	light(lava, rgb(255, 120, 40), 60, 5)
	local s = smoke(lava, rgb(80, 70, 70), 30, 80, 4, 25)
	s.EmissionDirection = Enum.NormalId.Right
	local sp = sparkle(lava, rgb(255, 150, 40), 20, 70, 3, 2.5)
	sp.EmissionDirection = Enum.NormalId.Right
	sp.SpreadAngle = Vector2.new(30, 30)
	for k = 0, 3 do
		local a = k * PI / 2 + 0.4
		box(
			Vector3.new(12, 1, 180),
			CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 60, -170) * CFrame.Angles(math.rad(-38), 0, 0),
			rgb(255, 100, 20),
			M.Neon
		)
	end
end)

named("aurora", "Northern lights")
def("aurora", 0, "global", function(cf, ctx)
	local pos = Vector3.new(ctx.Cx, 0, ctx.Cz)
	local sheets = {}
	for k = 0, 4 do
		local p = box(
			Vector3.new(900, 60, 2),
			CFrame.new(pos + Vector3.new(0, 420 + k * 30, 600 + k * 40))
				* CFrame.Angles(math.rad(-20), math.rad(k * 8 - 16), 0),
			Color3.fromHSV(0.35 + k * 0.08, 0.8, 1),
			M.Neon
		)
		p.Transparency = 0.6
		local base = p.CFrame
		mover({ p }, base, function(now)
			return base
				* CFrame.new(math.sin(now * 0.07 + k) * 60, math.sin(now * 0.11 + k * 2) * 12, 0)
				* CFrame.Angles(0, math.sin(now * 0.05 + k) * 0.08, 0)
		end)
		table.insert(sheets, p)
	end
end)

---------------------------------------------------------------------------
-- Shared bits
---------------------------------------------------------------------------
-- lattice towers (Vegas replica, Tokyo red tower); assigned further down
local latticeTower: (CFrame, number, Color3, Color3?) -> ()

local GLASS = {
	rgb(80, 120, 160),
	rgb(110, 150, 180),
	rgb(70, 95, 120),
	rgb(120, 160, 175),
	rgb(90, 110, 150),
	rgb(60, 130, 140),
}

-- A palm tree for landmark scenes (beaches, islands, oases).
local function palm(cf: CFrame, s: number)
	local h = 18 * s
	for k = 0, 3 do
		box(
			Vector3.new(1.6 * s, h / 4 + 0.4, 1.6 * s),
			cf * CFrame.new(k * 0.6 * s, h / 8 + k * h / 4, 0) * CFrame.Angles(0, 0, math.rad(-6)),
			rgb(150, 110, 70),
			M.Wood
		)
	end
	for k = 0, 5 do
		local a = k / 6 * PI * 2
		box(
			Vector3.new(1.4 * s, 0.4 * s, 9 * s),
			cf
				* CFrame.new(2.4 * s, h + 0.5, 0)
				* CFrame.Angles(0, a, 0)
				* CFrame.new(0, -1 * s, -4 * s)
				* CFrame.Angles(math.rad(-20), 0, 0),
			rgb(60, 160, 60),
			M.LeafyGrass
		)
	end
end

-- A leafy tree for landmark scenes.
local function tree(cf: CFrame, s: number, leaf: Color3)
	box(Vector3.new(1.8, 8, 1.8) * s, cf * CFrame.new(0, 4 * s, 0), rgb(100, 70, 45), M.Wood)
	ellipsoid(Vector3.new(13, 9, 13) * s, cf * CFrame.new(0, 11 * s, 0), leaf, M.LeafyGrass)
	ellipsoid(
		Vector3.new(8, 7, 8) * s,
		cf * CFrame.new(3 * s, 14 * s, -2 * s),
		leaf:Lerp(Color3.new(1, 1, 1), 0.12),
		M.LeafyGrass
	)
end

-- a tower block with floor bands and a crown (used by skylines)
local function tower(tcf: CFrame, w: number, d: number, h: number, glass: Color3)
	box(Vector3.new(w, h, d), tcf * CFrame.new(0, h / 2, 0), glass, M.Glass)
	local every = if X.Q >= 3 then 1 else 2
	local n = math.floor(h / 16)
	for f = 1, n, every do
		local lit = X.Th.Night and X.Rng:NextNumber() < 0.6
		box(
			Vector3.new(w + 0.4, 1.3, d + 0.4),
			tcf * CFrame.new(0, f * 16, 0),
			if lit then rgb(255, 226, 170) else glass:Lerp(Color3.new(1, 1, 1), 0.4),
			if lit then M.Neon else M.Metal
		)
	end
	local style = X.Rng:NextInteger(1, 4)
	if style == 1 then
		box(
			Vector3.new(w * 0.6, 14, d * 0.6),
			tcf * CFrame.new(0, h + 7, 0),
			glass:Lerp(Color3.new(1, 1, 1), 0.2),
			M.Glass
		)
		vcyl(34, 1.2, tcf * CFrame.new(0, h + 31, 0), rgb(220, 220, 225), M.Metal)
		if X.Th.Night then
			box(Vector3.new(1.4, 1.4, 1.4), tcf * CFrame.new(0, h + 48, 0), rgb(255, 40, 40), M.Neon)
		end
	elseif style == 2 then
		wedge(Vector3.new(w, 20, d), tcf * CFrame.new(0, h + 10, 0), glass, M.Glass)
	elseif style == 3 then
		box(Vector3.new(w + 1, 5, d + 1), tcf * CFrame.new(0, h - 2.5, 0), X.Th.Accent, M.Neon)
	else
		box(Vector3.new(w * 0.7, h * 0.25, d * 0.7), tcf * CFrame.new(0, h + h * 0.125, 0), glass, M.Glass)
	end
end

---------------------------------------------------------------------------
-- Generic
---------------------------------------------------------------------------
named("skyline", "Downtown skyline")
def("skyline", 170, "near", function(cf)
	local n = ({ 5, 7, 10, 13 })[X.Q]
	local placed = {}
	for _ = 1, n * 3 do
		if #placed >= n then
			break
		end
		local a, dist = rnd(0, PI * 2), rnd(0, 135)
		local ox, oz = math.cos(a) * dist, math.sin(a) * dist
		local ok = true
		for _, q in placed do
			if (q[1] - ox) ^ 2 + (q[2] - oz) ^ 2 < 44 * 44 then
				ok = false
			end
		end
		if ok then
			table.insert(placed, { ox, oz })
			local w, d = rnd(24, 40), rnd(24, 40)
			local h = rnd(110, 320) * (1.1 - dist / 260)
			tower(cf * CFrame.new(ox, 0, oz) * CFrame.Angles(0, rnd(-0.25, 0.25), 0), w, d, h, pick(GLASS))
		end
	end
	box(Vector3.new(300, 0.6, 300), cf * CFrame.new(0, 0.3, 0), rgb(150, 150, 152), M.Pavement)
end)

---------------------------------------------------------------------------
-- Australia
---------------------------------------------------------------------------
named("kangaroos", "Kangaroo paddock")
def("kangaroos", 60, "near", function(cf)
	for k = 0, 11 do
		local a = k / 12 * PI * 2
		box(Vector3.new(0.6, 4, 0.6), cf * CFrame.new(math.cos(a) * 48, 2, math.sin(a) * 48), rgb(140, 100, 60), M.Wood)
	end
	local fur = rgb(170, 110, 70)
	for k = 1, 7 do
		local base = CFrame.new(0, -400 - k * 12, 0)
		local parts = {
			ellipsoid(Vector3.new(3, 4.5, 5), base * CFrame.new(0, 4, 0) * CFrame.Angles(math.rad(-30), 0, 0), fur),
			ellipsoid(Vector3.new(1.8, 2, 2.6), base * CFrame.new(0, 7, -2.2), fur),
			box(Vector3.new(0.4, 1.4, 0.6), base * CFrame.new(-0.6, 8.4, -1.8), fur),
			box(Vector3.new(0.4, 1.4, 0.6), base * CFrame.new(0.6, 8.4, -1.8), fur),
			box(Vector3.new(0.9, 0.9, 6), base * CFrame.new(0, 1.8, 3.6) * CFrame.Angles(math.rad(18), 0, 0), fur),
			box(Vector3.new(2.6, 1, 4), base * CFrame.new(0, 0.5, 0.4), fur:Lerp(Color3.new(0, 0, 0), 0.2)),
		}
		local centre = (cf * CFrame.new(rnd(-12, 12), 0, rnd(-12, 12))).Position
		local r, speed, phase = rnd(10, 32), rnd(6, 10) * (if k % 2 == 0 then 1 else -1), rnd(0, 6)
		mover(parts, base, function(now)
			local a = phase + now * speed / r
			local hop = math.abs(math.sin(now * 3.2 + phase)) * 3
			local p = centre + Vector3.new(math.cos(a) * r, hop, math.sin(a) * r)
			local ahead = centre
				+ Vector3.new(math.cos(a + 0.05 * math.sign(speed)) * r, hop, math.sin(a + 0.05 * math.sign(speed)) * r)
			return CFrame.lookAt(p, ahead)
		end)
	end
	for k = 0, 4 do
		local tcf = cf * CFrame.Angles(0, k * 1.3, 0) * CFrame.new(0, 0, -rnd(20, 44))
		box(Vector3.new(1.4, 14, 1.4), tcf * CFrame.new(0, 7, 0), rgb(215, 205, 190), M.Wood)
		ellipsoid(Vector3.new(11, 6, 11), tcf * CFrame.new(0, 15, 0), rgb(120, 150, 110), M.LeafyGrass)
	end
end)

named("bandstand", "Park bandstand")
def("bandstand", 45, "near", function(cf)
	vcyl(2, 30, cf * CFrame.new(0, 1, 0), rgb(235, 232, 225), M.Marble)
	for k = 0, 7 do
		local a = k / 8 * PI * 2
		vcyl(12, 1, cf * CFrame.new(math.cos(a) * 12, 8, math.sin(a) * 12), rgb(250, 250, 250))
	end
	ellipsoid(Vector3.new(32, 12, 32), cf * CFrame.new(0, 16, 0), rgb(60, 120, 90), M.Metal)
	vcyl(6, 0.8, cf * CFrame.new(0, 24, 0), rgb(220, 190, 80), M.Metal)
	-- a band on stage and a picnic crowd on blankets
	for k = 0, 4 do
		local a = k / 5 * PI * 2
		person(cf * CFrame.new(math.cos(a) * 6, 2, math.sin(a) * 6) * CFrame.Angles(0, -a, 0))
	end
	for k = 0, 7 do
		local pcf = cf * CFrame.Angles(0, k * 0.8, 0) * CFrame.new(0, 0, -rnd(22, 38))
		box(
			Vector3.new(7, 0.2, 5),
			pcf * CFrame.new(0, 0.1, 0),
			pick({ rgb(220, 60, 60), rgb(60, 120, 220), rgb(250, 220, 80), rgb(250, 250, 250) }),
			M.Fabric
		)
		person(pcf * CFrame.new(-1.5, 0, 0) * CFrame.Angles(0, PI, 0))
	end
end)

---------------------------------------------------------------------------
-- China
---------------------------------------------------------------------------
named("pearl_tower", "Pearl TV tower")
def("pearl_tower", 50, "near", function(cf)
	local pink = rgb(235, 90, 150)
	local mat = if X.Th.Night then M.Neon else M.SmoothPlastic
	box(Vector3.new(80, 8, 80), cf * CFrame.new(0, 4, 0), rgb(200, 200, 205), M.Concrete)
	for k = 0, 2 do
		local a = k * PI * 2 / 3
		beam(
			(cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 6, -34)).Position,
			(cf * CFrame.new(0, 96, 0)).Position,
			6,
			rgb(225, 225, 230),
			M.Concrete
		)
		vcyl(210, 4, cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 105, -8), rgb(215, 215, 222), M.Concrete)
	end
	vcyl(270, 10, cf * CFrame.new(0, 135, 0), rgb(225, 225, 230), M.Concrete)
	local s1 = ball(48, cf * CFrame.new(0, 96, 0), pink, mat)
	ball(32, cf * CFrame.new(0, 208, 0), pink, mat)
	for k = 0, 4 do
		ball(9, cf * CFrame.new(0, 128 + k * 14, 0) * CFrame.Angles(0, k * 1.3, 0) * CFrame.new(0, 0, -7), pink, mat)
	end
	ball(14, cf * CFrame.new(0, 252, 0), pink, mat)
	vcyl(56, 2.4, cf * CFrame.new(0, 290, 0), rgb(230, 230, 235), M.Metal)
	light(s1, pink, 80, 2)
end)

named("dragon_gate", "Dragon gate")
def("dragon_gate", 55, "near", function(cf)
	local red, gold, tile = rgb(200, 30, 30), rgb(235, 185, 50), rgb(40, 110, 90)
	for _, x in { -24, -8, 8, 24 } do
		local h = if math.abs(x) < 10 then 30 else 24
		vcyl(h, 3.4, cf * CFrame.new(x, h / 2, 0), red, M.WoodPlanks)
		vcyl(1.5, 5, cf * CFrame.new(x, 0.75, 0), rgb(200, 195, 185), M.Marble)
	end
	for _, r in { { 0, 31, 22 }, { -16, 25, 17 }, { 16, 25, 17 } } do
		box(Vector3.new(r[3], 3, 4), cf * CFrame.new(r[1], r[2], 0), gold, M.WoodPlanks)
		box(Vector3.new(r[3] + 6, 1.2, 9), cf * CFrame.new(r[1], r[2] + 2.2, 0), tile, M.Slate)
		wedge(Vector3.new(r[3] + 6, 2.4, 4.5), cf * CFrame.new(r[1], r[2] + 4, -2.25), tile, M.Slate)
		wedge(
			Vector3.new(r[3] + 6, 2.4, 4.5),
			cf * CFrame.new(r[1], r[2] + 4, 2.25) * CFrame.Angles(0, PI, 0),
			tile,
			M.Slate
		)
	end
	local plaque = box(Vector3.new(10, 5, 0.6), cf * CFrame.new(0, 27, -2.4), rgb(30, 30, 34))
	sign(plaque, Enum.NormalId.Front, "龍", gold)
	-- a dancing dragon weaving in front of the gate
	for k = 0, 13 do
		local seg = ball(
			if k == 0 then 5 else 4 - k * 0.12,
			cf * CFrame.new(-26 + k * 4, 6, -16),
			if k % 2 == 0 then red else gold,
			M.Fabric
		)
		local parts = { seg }
		if k == 0 then
			table.insert(parts, box(Vector3.new(3.4, 3, 5), cf * CFrame.new(-26, 6.5, -18.5), red))
			table.insert(parts, box(Vector3.new(4.6, 0.5, 0.5), cf * CFrame.new(-26, 9, -16), gold))
		end
		local base = seg.CFrame
		mover(parts, base, function(now)
			return base * CFrame.new(0, math.sin(now * 3 - k * 0.55) * 2.6, math.cos(now * 1.5 - k * 0.4) * 3)
		end)
		if k % 3 == 1 then
			local pole = box(Vector3.new(0.3, 6, 0.3), cf * CFrame.new(-26 + k * 4, 3, -16), rgb(90, 60, 40), M.Wood)
			local pb = pole.CFrame
			mover({ pole }, pb, function(now)
				return pb * CFrame.new(0, math.sin(now * 3 - k * 0.55) * 1.3, math.cos(now * 1.5 - k * 0.4) * 3)
			end)
		end
	end
	for side = -1, 1, 2 do
		box(Vector3.new(4, 4, 7), cf * CFrame.new(side * 34, 2, -4), rgb(200, 195, 185), M.Marble)
		box(Vector3.new(3, 5, 5), cf * CFrame.new(side * 34, 6.5, -4), rgb(150, 150, 140), M.Rock)
	end
end)

---------------------------------------------------------------------------
-- Japan
---------------------------------------------------------------------------
named("fuji", "Snow-capped Mt. Fuji")
def("fuji", 470, "far", function(cf)
	cone(470, 940, 70, 12, cf, rgb(90, 100, 120), M.Rock, rgb(248, 250, 255))
	cone(160, 1100, 800, 3, cf, rgb(70, 110, 70), M.Grass)
end)

named("torii_path", "Torii gate path")
def("torii_path", 110, "near", function(cf)
	local ver = rgb(230, 80, 30)
	box(Vector3.new(10, 0.4, 200), cf * CFrame.new(0, 0.2, 0), rgb(200, 190, 170), M.Pebble)
	local n = if X.Q >= 3 then 16 else 9
	for k = 0, n - 1 do
		local g = cf * CFrame.new(0, 0, -95 + k * 190 / (n - 1))
		for side = -1, 1, 2 do
			vcyl(16, 1.6, g * CFrame.new(side * 6, 8, 0), ver, M.WoodPlanks)
			vcyl(1.4, 2.2, g * CFrame.new(side * 6, 0.7, 0), rgb(30, 30, 34), M.Wood)
		end
		box(Vector3.new(17, 1.6, 2.2), g * CFrame.new(0, 16.3, 0), rgb(30, 30, 34), M.WoodPlanks)
		box(Vector3.new(14, 1.2, 1.6), g * CFrame.new(0, 13.5, 0), ver, M.WoodPlanks)
		if k % 3 == 0 then
			for side = -1, 1, 2 do
				local l = g * CFrame.new(side * 11, 0, 0)
				box(Vector3.new(1.2, 3, 1.2), l * CFrame.new(0, 1.5, 0), rgb(160, 160, 155), M.Slate)
				local lamp = box(
					Vector3.new(2.4, 2, 2.4),
					l * CFrame.new(0, 4, 0),
					if X.Th.Night then rgb(255, 210, 140) else rgb(170, 170, 165),
					if X.Th.Night then M.Neon else M.Slate
				)
				box(Vector3.new(3.4, 0.8, 3.4), l * CFrame.new(0, 5.4, 0), rgb(150, 150, 145), M.Slate)
				local _ = lamp
			end
		end
	end
	Arch.Build("japanese_house", X.F, cf * CFrame.new(0, 0, 108) * CFrame.Angles(0, PI, 0), X.Rng, X.Th, X.P)
end)

named("zen_garden", "Zen garden & koi pond")
def("zen_garden", 60, "near", function(cf)
	box(Vector3.new(90, 0.4, 70), cf * CFrame.new(0, 0.2, 0), rgb(225, 222, 212), M.Pebble)
	for k = -6, 6 do
		box(Vector3.new(0.5, 0.1, 64), cf * CFrame.new(k * 3.4 - 20, 0.45, 0), rgb(200, 196, 186), M.Pebble)
	end
	for _, r in { { -30, -12, 7 }, { -18, 16, 5 }, { -8, -20, 4 } } do
		ellipsoid(
			Vector3.new(r[3] * 1.5, r[3], r[3] * 1.2),
			cf * CFrame.new(r[1], r[3] * 0.35, r[2]),
			rgb(110, 110, 105),
			M.Rock
		)
		vcyl(0.4, r[3] * 3, cf * CFrame.new(r[1], 0.4, r[2]), rgb(90, 140, 70), M.Grass)
	end
	vcyl(0.8, 44, cf * CFrame.new(22, 0.3, 0), rgb(60, 130, 150), M.Glass)
	for k = 0, 5 do
		local a = k / 6 * PI * 2
		ellipsoid(
			Vector3.new(4, 1.6, 3),
			cf * CFrame.new(22 + math.cos(a) * 22, 0.8, math.sin(a) * 22),
			rgb(120, 120, 115),
			M.Rock
		)
	end
	-- red arched bridge
	for k = -2, 2 do
		box(
			Vector3.new(6, 0.8, 5),
			cf * CFrame.new(22, 3.6 - math.abs(k) * 1.2, k * 4.6) * CFrame.Angles(math.rad(k * 14), 0, 0),
			rgb(200, 40, 40),
			M.WoodPlanks
		)
	end
	-- koi
	for k = 1, 6 do
		local base = CFrame.new(0, -450 - k * 5, 0)
		local fish = {
			ellipsoid(
				Vector3.new(1, 0.6, 2.8),
				base,
				pick({ rgb(255, 120, 30), rgb(250, 250, 250), rgb(255, 80, 40) }),
				M.SmoothPlastic
			),
		}
		circler(
			fish,
			base,
			(cf * CFrame.new(22, 0.6, 0)).Position,
			rnd(6, 16),
			rnd(3, 6) * (if k % 2 == 0 then 1 else -1),
			rnd(0, 6)
		)
	end
	tree(cf * CFrame.new(38, 0, -24), 1.1, rgb(255, 175, 205))
	tree(cf * CFrame.new(-40, 0, 26), 1, rgb(210, 70, 40))
	Arch.Build("japanese_house", X.F, cf * CFrame.new(-6, 0, 28) * CFrame.Angles(0, PI, 0), X.Rng, X.Th, X.P)
end)

---------------------------------------------------------------------------
-- Bahrain
---------------------------------------------------------------------------
named("sail_tower", "Sail-roof VIP tower")
def("sail_tower", 60, "near", function(cf)
	box(Vector3.new(90, 16, 40), cf * CFrame.new(0, 8, 0), rgb(236, 230, 218), M.Concrete)
	box(Vector3.new(90.4, 5, 40.4), cf * CFrame.new(0, 9, 0), rgb(60, 80, 100), M.Glass)
	box(Vector3.new(26, 120, 26), cf * CFrame.new(0, 60, 0), rgb(236, 230, 218), M.Concrete)
	for f = 1, 11 do
		local lit = X.Th.Night and f % 2 == 0
		box(
			Vector3.new(26.6, 3, 26.6),
			cf * CFrame.new(0, f * 10, 0),
			if lit then rgb(255, 226, 170) else rgb(70, 100, 130),
			if lit then M.Neon else M.Glass
		)
	end
	for k = 0, 9 do
		local a = (k - 4.5) * 0.16
		box(
			Vector3.new(4, 1, 70),
			cf * CFrame.new(0, 124, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(10), 0, 0),
			rgb(248, 248, 250),
			M.Fabric
		)
	end
	local top = box(Vector3.new(30, 2, 30), cf * CFrame.new(0, 121, 0), X.Th.Accent, M.Neon)
	light(top, rgb(255, 240, 220), 70, 2)
end)

named("oasis", "Palm oasis")
def("oasis", 60, "near", function(cf)
	vcyl(0.8, 50, cf * CFrame.new(0, 0.3, 0), rgb(40, 150, 170), M.Glass)
	vcyl(0.5, 60, cf * CFrame.new(0, 0.15, 0), rgb(120, 160, 80), M.Grass)
	for k = 0, 9 do
		local a = k / 10 * PI * 2 + rnd(-0.2, 0.2)
		palm(
			cf * CFrame.new(math.cos(a) * rnd(28, 36), 0, math.sin(a) * rnd(28, 36)) * CFrame.Angles(0, rnd(0, 6), 0),
			rnd(0.9, 1.3)
		)
	end
	for k = 0, 2 do
		local t = cf * CFrame.Angles(0, k * 2.1 + 0.5, 0) * CFrame.new(0, 0, -48)
		wedge(Vector3.new(14, 6, 6), t * CFrame.new(0, 3, -3), rgb(60, 45, 40), M.Fabric)
		wedge(Vector3.new(14, 6, 6), t * CFrame.new(0, 3, 3) * CFrame.Angles(0, PI, 0), rgb(60, 45, 40), M.Fabric)
		box(Vector3.new(8, 0.2, 6), t * CFrame.new(0, 0.1, -8), rgb(170, 40, 40), M.Fabric)
		if X.Th.Night then
			local fire = box(Vector3.new(1.2, 1.2, 1.2), t * CFrame.new(6, 0.6, -8), rgb(255, 140, 40), M.Neon)
			sparkle(fire, rgb(255, 150, 50), 6, 6, 0.6, 1)
		end
	end
end)

named("camels", "Camel caravan")
def("camels", 60, "near", function(cf)
	local centre = cf.Position
	for k = 1, 5 do
		local base = CFrame.new(0, -420 - k * 20, 0)
		local parts = animal(
			base,
			1.25,
			rgb(200, 160, 105),
			{ hump = true, neck = 2.6, legs = 4.6, len = 6, height = 2.6, width = 2.4 }
		)
		table.insert(
			parts,
			box(
				Vector3.new(2.8, 0.6, 3),
				base * CFrame.new(0, 10.8, 1.2),
				pick({ rgb(200, 40, 40), rgb(40, 90, 180), rgb(230, 170, 40) }),
				M.Fabric
			)
		)
		mover(parts, base, function(now)
			local a = now * 0.12 + k * 0.32
			local p = centre + Vector3.new(math.cos(a) * 40, 0, math.sin(a) * 40)
			local ahead = centre + Vector3.new(math.cos(a + 0.05) * 40, 0, math.sin(a + 0.05) * 40)
			return CFrame.lookAt(p, ahead) * CFrame.new(0, math.abs(math.sin(now * 2.2 + k)) * 0.3, 0)
		end)
	end
	person(cf * CFrame.new(0, 0, -44), rgb(250, 250, 250))
end)

---------------------------------------------------------------------------
-- Saudi Arabia
---------------------------------------------------------------------------
named("fountain_jet", "Giant sea fountain")
def("fountain_jet", 40, "sea", function(cf)
	vcyl(3, 26, cf * CFrame.new(0, 1, 0), rgb(220, 220, 225), M.Concrete)
	local top
	for k = 0, 9 do
		local d = 3 + k * 0.9
		local seg =
			vcyl(30, d, cf * CFrame.new(0, 15 + k * 30, 0), rgb(235, 245, 255), if X.Th.Night then M.Neon else M.Glass)
		seg.Transparency = 0.25 + k * 0.05
		top = seg
	end
	local mist = smoke(top, rgb(240, 248, 255), 20, 60, 6, 10)
	mist.EmissionDirection = Enum.NormalId.Right
	local spray = sparkle(top, rgb(230, 245, 255), 60, 40, 2.4, 3)
	spray.EmissionDirection = Enum.NormalId.Right
	spray.SpreadAngle = Vector2.new(40, 40)
	light(top, rgb(200, 230, 255), 80, 2)
end)

named("dhows", "Wooden dhows")
def("dhows", 60, "sea", function(cf)
	for k = 1, 4 do
		local base = CFrame.new(0, -470 - k * 20, 0)
		local wood = rgb(130, 85, 50)
		local parts = {
			box(Vector3.new(6, 3, 20), base * CFrame.new(0, 1.5, 0), wood, M.WoodPlanks),
			wedge(Vector3.new(6, 4, 6), base * CFrame.new(0, 2, -13) * CFrame.Angles(0, PI, 0), wood, M.WoodPlanks),
			wedge(Vector3.new(6, 3, 3), base * CFrame.new(0, 3.5, 11.5), wood, M.WoodPlanks),
			box(Vector3.new(0.5, 20, 0.5), base * CFrame.new(0, 13, -2), rgb(90, 60, 35), M.Wood),
			wedge(
				Vector3.new(0.2, 16, 14),
				base * CFrame.new(0, 13, 3) * CFrame.Angles(0, PI, 0),
				rgb(245, 238, 220),
				M.Fabric
			),
		}
		circler(
			parts,
			base,
			cf.Position + Vector3.new(rnd(-120, 120), 0.6, rnd(-60, 120)),
			rnd(60, 130),
			rnd(5, 9) * (if k % 2 == 0 then 1 else -1),
			rnd(0, 6)
		)
	end
end)

named("flagpole", "Giant flagpole")
def("flagpole", 50, "near", function(cf)
	vcyl(2, 40, cf * CFrame.new(0, 1, 0), rgb(220, 215, 205), M.Marble)
	vcyl(200, 3, cf * CFrame.new(0, 100, 0), rgb(225, 225, 230), M.Metal)
	local flag =
		box(Vector3.new(0.4, 40, 64), cf * CFrame.new(0, 178, 32), X.Th.Accent:Lerp(rgb(0, 110, 60), 0.6), M.Fabric)
	local band = box(Vector3.new(0.5, 4, 40), cf * CFrame.new(0, 172, 34), rgb(250, 250, 250), M.Fabric)
	local pivot = cf * CFrame.new(0, 178, 0)
	local fb, bb = pivot:ToObjectSpace(flag.CFrame), pivot:ToObjectSpace(band.CFrame)
	mover({ flag, band }, pivot, function(now)
		return pivot * CFrame.Angles(0, math.sin(now * 0.8) * 0.35, 0)
	end)
	local _ = fb and bb
	if X.Th.Night then
		for k = 0, 3 do
			local l = box(
				Vector3.new(2, 2, 2),
				cf * CFrame.Angles(0, k * PI / 2, 0) * CFrame.new(0, 2.5, -18),
				rgb(255, 250, 230),
				M.Neon
			)
			if k == 0 then
				light(l, rgb(255, 250, 230), 60, 2)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Florida
---------------------------------------------------------------------------
named("lifeguards", "Lifeguard towers & beach")
def("lifeguards", 220, "shore", function(cf)
	local pastel = {
		rgb(255, 140, 170),
		rgb(90, 210, 220),
		rgb(255, 220, 90),
		rgb(160, 230, 140),
		rgb(200, 150, 255),
		rgb(255, 170, 90),
	}
	for k = -3, 3 do
		local h = cf * CFrame.new(k * 60, 0, 10) * CFrame.Angles(0, PI, 0)
		for _, o in { { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } } do
			box(Vector3.new(0.6, 8, 0.6), h * CFrame.new(o[1], 4, o[2]), rgb(240, 240, 240))
		end
		local col = pastel[(k + 3) % #pastel + 1]
		box(Vector3.new(9, 6, 8), h * CFrame.new(0, 11, 0), col)
		box(Vector3.new(9.2, 2, 8.2), h * CFrame.new(0, 11, 0), rgb(250, 250, 250))
		wedge(Vector3.new(10, 2.5, 9), h * CFrame.new(0, 15.3, 0), col:Lerp(Color3.new(0, 0, 0), 0.2))
		box(
			Vector3.new(3, 0.4, 10),
			h * CFrame.new(0, 4, -8) * CFrame.Angles(math.rad(30), 0, 0),
			rgb(240, 240, 240),
			M.WoodPlanks
		)
		for _ = 1, 3 do
			local u = h * CFrame.new(rnd(-25, 25), 0, rnd(-18, 18))
			box(Vector3.new(0.3, 7, 0.3), u * CFrame.new(0, 3.5, 0), rgb(230, 230, 230))
			hcyl(1.2, 9, u * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, PI / 2), pick(pastel), M.Fabric)
			box(Vector3.new(3, 0.15, 6), u * CFrame.new(2, 0.1, 2), pick(pastel), M.Fabric)
			if X.Q >= 3 then
				person(u * CFrame.new(-2, 0, 2) * CFrame.Angles(0, rnd(0, 6), 0))
			end
		end
	end
	for k = -5, 5 do
		palm(cf * CFrame.new(k * 42 + rnd(-8, 8), 0, -26), rnd(1, 1.4))
	end
end)

named("deco_row", "Art-deco hotel row")
def("deco_row", 160, "near", function(cf)
	local pastel = {
		rgb(255, 180, 190),
		rgb(150, 225, 225),
		rgb(255, 235, 160),
		rgb(210, 180, 255),
		rgb(255, 205, 160),
		rgb(250, 250, 245),
	}
	for k = -2, 3 do
		local h = cf * CFrame.new(k * 48 - 24, 0, 0)
		local c = pastel[(k + 2) % #pastel + 1]
		local ht = rnd(30, 52)
		box(Vector3.new(38, ht, 26), h * CFrame.new(0, ht / 2, 0), c, M.Plaster)
		for f = 1, math.floor(ht / 8) - 1 do
			box(Vector3.new(30, 2.2, 26.4), h * CFrame.new(-2, f * 8 + 1, 0), rgb(80, 120, 150), M.Glass)
			box(Vector3.new(34, 0.6, 28), h * CFrame.new(0, f * 8 - 1.5, 0), rgb(250, 250, 250))
		end
		vcyl(ht, 10, h * CFrame.new(19, ht / 2, -8), c:Lerp(Color3.new(1, 1, 1), 0.3), M.Plaster)
		local fin = box(Vector3.new(3, 16, 1.4), h * CFrame.new(0, ht + 8, -12), c, M.Plaster)
		local neon = box(
			Vector3.new(3.4, ht * 0.8, 1),
			h * CFrame.new(12, ht * 0.5, -13.2),
			Color3.fromHSV(rnd(0, 1), 0.7, 1),
			if X.Th.Night then M.Neon else M.SmoothPlastic
		)
		box(Vector3.new(24, 6, 1), h * CFrame.new(0, ht + 3, -12.6), c:Lerp(Color3.new(1, 1, 1), 0.5), M.Plaster)
		local _ = fin and neon
		box(Vector3.new(36, 0.8, 10), h * CFrame.new(0, 4.4, -18), c:Lerp(Color3.new(0, 0, 0), 0.1), M.Fabric)
	end
end)

---------------------------------------------------------------------------
-- Canada
---------------------------------------------------------------------------
named("biosphere", "Geodesic biosphere")
def("biosphere", 60, "near", function(cf)
	local r = 46
	local c = cf * CFrame.new(0, r * 0.75, 0)
	local inner = ball(r * 2 - 2, c, rgb(170, 210, 230), M.Glass)
	inner.Transparency = 0.55
	local segs = if X.Q >= 3 then 16 else 10
	local lons = if X.Q >= 3 then 8 else 5
	for m = 0, lons - 1 do
		local rot = c * CFrame.Angles(0, m * PI / lons, 0)
		for k = 0, segs - 1 do
			local a0, a1 = k / segs * PI * 2, (k + 1) / segs * PI * 2
			local p0 = (rot * CFrame.new(math.cos(a0) * r, math.sin(a0) * r, 0)).Position
			local p1 = (rot * CFrame.new(math.cos(a1) * r, math.sin(a1) * r, 0)).Position
			if p0.Y > 0.5 or p1.Y > 0.5 then
				beam(p0, p1, 0.9, rgb(225, 228, 235), M.Metal)
			end
		end
	end
	for lat = -1, 3 do
		local y = lat * r / 4
		local rr = math.sqrt(math.max(0, r * r - y * y))
		for k = 0, segs - 1 do
			local a0, a1 = k / segs * PI * 2, (k + 1) / segs * PI * 2
			beam(
				(c * CFrame.new(math.cos(a0) * rr, y, math.sin(a0) * rr)).Position,
				(c * CFrame.new(math.cos(a1) * rr, y, math.sin(a1) * rr)).Position,
				0.9,
				rgb(225, 228, 235),
				M.Metal
			)
		end
	end
end)

named("inclined_tower", "Inclined stadium tower")
def("inclined_tower", 110, "near", function(cf)
	local n = if X.Q >= 3 then 24 else 16
	for k = 0, n - 1 do
		local a = k / n * PI * 2
		local rx, rz = 70, 52
		local p = cf * CFrame.new(math.cos(a) * rx, 0, math.sin(a) * rz)
		local nxt = cf * CFrame.new(math.cos(a + 2 * PI / n) * rx, 0, math.sin(a + 2 * PI / n) * rz)
		local seg = (nxt.Position - p.Position).Magnitude
		local look = CFrame.lookAt(p.Position, nxt.Position)
		box(Vector3.new(14, 18, seg + 1), look * CFrame.new(0, 9, -seg / 2), rgb(225, 225, 228), M.Concrete)
		wedge(
			Vector3.new(10, 8, seg + 1),
			look * CFrame.new(0, 22, -seg / 2) * CFrame.Angles(0, PI / 2, 0),
			rgb(235, 235, 238),
			M.Concrete
		)
	end
	local foot = cf * CFrame.new(70, 0, 0)
	local t = foot * CFrame.Angles(0, 0, math.rad(45)) * CFrame.new(0, 90, 0)
	box(Vector3.new(16, 190, 20), t, rgb(230, 230, 232), M.Concrete)
	box(Vector3.new(26, 20, 26), t * CFrame.new(0, 100, 0), rgb(70, 100, 130), M.Glass)
	for k = 1, 4 do
		beam(
			(t * CFrame.new(0, -95 + k * 40, 0)).Position,
			(cf * CFrame.new(-10 + k * 6, 22, 0)).Position,
			0.4,
			rgb(60, 60, 64),
			M.Metal
		)
	end
end)

---------------------------------------------------------------------------
-- Monaco
---------------------------------------------------------------------------
named("rock_palace", "Palace on the rock")
def("rock_palace", 110, "near", function(cf)
	local rock = rgb(150, 138, 118)
	for k = 0, 6 do
		ellipsoid(
			Vector3.new(rnd(90, 150), rnd(40, 70), rnd(70, 120)),
			cf * CFrame.new(rnd(-40, 40), rnd(5, 20), rnd(-30, 30)) * CFrame.Angles(0, rnd(0, 3), 0),
			rock:Lerp(rgb(110, 100, 90), rnd(0, 0.5)),
			M.Rock
		)
	end
	box(Vector3.new(160, 50, 110), cf * CFrame.new(0, 25, 0), rock, M.Rock)
	local top = cf * CFrame.new(0, 50, 0)
	local cream = rgb(240, 225, 195)
	box(Vector3.new(80, 20, 34), top * CFrame.new(0, 10, 0), cream, M.Plaster)
	for m = -7, 7 do
		box(Vector3.new(3, 3, 34.4), top * CFrame.new(m * 5.4, 21.5, 0), cream, M.Plaster)
	end
	for side = -1, 1, 2 do
		box(Vector3.new(14, 32, 14), top * CFrame.new(side * 44, 16, 0), cream, M.Plaster)
		box(Vector3.new(16, 2, 16), top * CFrame.new(side * 44, 33, 0), rgb(200, 90, 70), M.Slate)
		box(Vector3.new(0.4, 10, 0.4), top * CFrame.new(side * 44, 39, 0), rgb(220, 220, 220), M.Metal)
		box(
			Vector3.new(0.2, 3, 5),
			top * CFrame.new(side * 44, 42.5, 2.6),
			if side < 0 then rgb(220, 30, 40) else rgb(250, 250, 250),
			M.Fabric
		)
	end
	for k = -3, 3 do
		box(Vector3.new(3, 5, 0.4), top * CFrame.new(k * 9, 11, -17.2), rgb(80, 110, 140), M.Glass)
	end
	for k = -3, 3 do
		Arch.Build("villa", X.F, cf * CFrame.new(k * 26, 0, -70), X.Rng, X.Th, X.P)
	end
end)

named("tunnel", "Harbour tunnel")
def("tunnel", 0, "track", function(_, ctx)
	local t = ctx.T
	local W = t.Width
	-- the straightest flat run away from the start line
	local len = 30
	local best, bestScore = nil, math.huge
	for i = math.floor(t.N * 0.2), math.floor(t.N * 0.8) - len do
		local score, ok = 0, true
		for o = 0, len do
			local j = i + o
			if t.Over[j] or math.abs(t.K[j]) > 1 / 200 then
				ok = false
				break
			end
			score += math.abs(t.K[j]) * 1000 + math.abs(t.Y[j] - t.Y[i]) * 0.1
		end
		if ok and score < bestScore then
			best, bestScore = i, score
		end
	end
	if not best then
		return
	end
	local half = W / 2 + 10
	local H = 26
	local wall, roofC = rgb(200, 196, 188), rgb(170, 166, 160)
	for o = 0, len - 3, 3 do
		local a, b = best + o, best + o + 3
		local pa, pb = ctx.Pos(a, 0, 0), ctx.Pos(b, 0, 0)
		local mid = (pa + pb) / 2
		local seg = (pb - pa).Magnitude + 0.6
		local fcf = CFrame.lookAt(mid, pb)
		for side = -1, 1, 2 do
			box(Vector3.new(3, H + 2, seg), fcf * CFrame.new(side * half, H / 2, 0), wall, M.Concrete)
		end
		box(Vector3.new(half * 2 + 3, 3, seg), fcf * CFrame.new(0, H + 1.5, 0), roofC, M.Concrete)
		local strip = box(Vector3.new(1.2, 0.3, seg - 1), fcf * CFrame.new(0, H - 0.2, 0), rgb(255, 240, 210), M.Neon)
		if o % 9 == 0 then
			light(strip, rgb(255, 238, 205), 40, 1.6)
		end
		for side = -1, 1, 2 do
			box(
				Vector3.new(0.3, 0.8, seg - 0.4),
				fcf * CFrame.new(side * (half - 1.6), 6, 0),
				rgb(255, 200, 40),
				M.Neon
			)
		end
		ctx.Occ.add(mid.X, mid.Z, half + 6)
	end
	for _, e in { best, best + len - 3 } do
		local p = ctx.Pos(e, 0, 0)
		local q = ctx.Pos(e + (if e == best then 1 else -1), 0, 0)
		local pcf = CFrame.lookAt(p, q)
		box(Vector3.new(half * 2 + 12, 10, 4), pcf * CFrame.new(0, H + 5, 0), rgb(230, 225, 215), M.Concrete)
		local s = box(Vector3.new(half * 1.2, 5, 0.4), pcf * CFrame.new(0, H + 5, -2.2), rgb(25, 30, 40))
		sign(s, Enum.NormalId.Front, "HARBOUR TUNNEL", rgb(255, 210, 90))
		-- a block of the old town sits on top of each portal
		box(Vector3.new(half * 2 + 30, 14, 30), pcf * CFrame.new(0, H + 10, -15), rgb(236, 214, 180), M.Plaster)
		box(Vector3.new(half * 2 + 31, 1.5, 31), pcf * CFrame.new(0, H + 17.5, -15), rgb(190, 90, 70), M.Slate)
	end
end)

---------------------------------------------------------------------------
-- Spain (Barcelona)
---------------------------------------------------------------------------
named("spire_cathedral", "Spired basilica")
def("spire_cathedral", 70, "near", function(cf)
	local stone = rgb(205, 180, 140)
	box(Vector3.new(90, 44, 40), cf * CFrame.new(0, 22, 0), stone, M.Sandstone)
	wedge(Vector3.new(90, 16, 20), cf * CFrame.new(0, 52, -10), stone:Lerp(rgb(150, 130, 100), 0.3), M.Sandstone)
	wedge(
		Vector3.new(90, 16, 20),
		cf * CFrame.new(0, 52, 10) * CFrame.Angles(0, PI, 0),
		stone:Lerp(rgb(150, 130, 100), 0.3),
		M.Sandstone
	)
	local tips = { rgb(230, 60, 50), rgb(250, 200, 40), rgb(60, 160, 90), rgb(60, 120, 220) }
	for k = 0, 3 do
		local x = -30 + k * 20
		local h = if k == 1 or k == 2 then 130 else 110
		cone(h, 12, 4, 7, cf * CFrame.new(x, 0, -22), stone, M.Sandstone)
		ball(6, cf * CFrame.new(x, h + 3, -22), tips[k + 1], M.Neon)
		cone(h * 0.8, 10, 4, 6, cf * CFrame.new(x, 0, 22), stone, M.Sandstone)
	end
	cone(185, 22, 6, 9, cf * CFrame.new(0, 0, 0), stone:Lerp(Color3.new(1, 1, 1), 0.15), M.Sandstone)
	local star = ball(10, cf * CFrame.new(0, 190, 0), rgb(255, 250, 230), M.Neon)
	light(star, rgb(255, 245, 220), 50, 1.5)
	for k = -3, 3 do
		box(Vector3.new(4, 20, 0.5), cf * CFrame.new(k * 11, 20, -20.2), rgb(90, 130, 170), M.Glass)
	end
	for _ = 1, 3 do
		local c = box(Vector3.new(3, 60, 3), cf * CFrame.new(rnd(-40, 40), 30, rnd(28, 40)), rgb(240, 190, 30), M.Metal)
		local _ = c
	end
end)

named("bullring", "Old bullring")
def("bullring", 70, "near", function(cf)
	local n = if X.Q >= 3 then 28 else 18
	local r = 50
	for k = 0, n - 1 do
		local a = k / n * PI * 2
		local seg = 2 * (r + 6) * math.sin(PI / n) + 1
		local w = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r)
		box(Vector3.new(seg, 20, 3), w * CFrame.new(0, 10, -6), rgb(240, 225, 195), M.Plaster)
		box(Vector3.new(4, 9, 3.2), w * CFrame.new(0, 7, -6), rgb(180, 60, 40), M.Brick)
		for row = 0, 3 do
			box(
				Vector3.new(seg - 1, 2, 4),
				w * CFrame.new(0, 3 + row * 3.6, -1 + row * 1.2) * CFrame.new(0, 0, 0),
				if row % 2 == 0 then rgb(200, 40, 40) else rgb(250, 200, 50),
				M.Concrete
			)
		end
	end
	vcyl(0.4, r * 1.8, cf * CFrame.new(0, 0.2, 0), rgb(225, 190, 120), M.Sand)
	vcyl(2.4, r * 1.85, cf * CFrame.new(0, 1.2, 0), rgb(160, 40, 30), M.WoodPlanks)
	vcyl(2.6, r * 1.8, cf * CFrame.new(0, 1.2, 0), rgb(225, 190, 120), M.Sand)
end)

named("hill_castle", "Hilltop fortress")
def("hill_castle", 120, "near", function(cf)
	ellipsoid(Vector3.new(220, 80, 200), cf * CFrame.new(0, 0, 0), X.Th.Ground:Lerp(rgb(80, 120, 60), 0.4), M.Grass)
	for k = 0, 8 do
		tree(cf * CFrame.Angles(0, k * 0.7, 0) * CFrame.new(0, 12, -rnd(60, 90)), rnd(0.9, 1.3), rgb(70, 120, 60))
	end
	local top = cf * CFrame.new(0, 36, 0)
	local c = rgb(200, 180, 140)
	for k = 0, 3 do
		local w = top * CFrame.Angles(0, k * PI / 2, 0)
		box(Vector3.new(70, 16, 5), w * CFrame.new(0, 8, -35), c, M.Sandstone)
		for m = -6, 6 do
			box(Vector3.new(3, 3, 5.2), w * CFrame.new(m * 5.5, 17.5, -35), c, M.Sandstone)
		end
		vcyl(26, 14, w * CFrame.new(35, 13, -35), c, M.Sandstone)
	end
	box(Vector3.new(24, 30, 24), top * CFrame.new(0, 15, 0), c, M.Sandstone)
	box(Vector3.new(0.4, 14, 0.4), top * CFrame.new(0, 37, 0), rgb(220, 220, 220), M.Metal)
	box(Vector3.new(0.2, 4, 7), top * CFrame.new(0, 42, 3.6), rgb(250, 200, 0), M.Fabric)
end)

---------------------------------------------------------------------------
-- Austria
---------------------------------------------------------------------------
named("bull_statue", "Giant bull sculpture")
def("bull_statue", 45, "near", function(cf)
	local s = 1.8
	local bronze = rgb(90, 70, 50)
	box(Vector3.new(40, 6, 24), cf * CFrame.new(0, 3, 0), rgb(120, 120, 125), M.Slate)
	local b = cf * CFrame.new(0, 6, 0) * CFrame.Angles(0, PI / 2, 0)
	ellipsoid(Vector3.new(10, 11, 22) * s, b * CFrame.new(0, 14 * s, 0), bronze, M.Metal)
	ellipsoid(Vector3.new(11, 12, 10) * s, b * CFrame.new(0, 16 * s, -6 * s), bronze, M.Metal)
	box(
		Vector3.new(6, 6, 8) * s,
		b * CFrame.new(0, 12 * s, -15 * s) * CFrame.Angles(math.rad(30), 0, 0),
		bronze,
		M.Metal
	)
	for side = -1, 1, 2 do
		box(
			Vector3.new(7, 1.2, 1.2) * s,
			b * CFrame.new(side * 5 * s, 16 * s, -14 * s) * CFrame.Angles(0, 0, side * math.rad(25)),
			rgb(230, 220, 200),
			M.Marble
		)
		box(
			Vector3.new(2.4, 10, 2.4) * s,
			b * CFrame.new(side * 3 * s, 5 * s, -7 * s) * CFrame.Angles(math.rad(-20), 0, 0),
			bronze,
			M.Metal
		)
		box(
			Vector3.new(2.4, 10, 2.4) * s,
			b * CFrame.new(side * 3 * s, 5 * s, 7 * s) * CFrame.Angles(math.rad(25), 0, 0),
			bronze,
			M.Metal
		)
	end
	box(
		Vector3.new(0.8, 0.8, 9) * s,
		b * CFrame.new(0, 17 * s, 13 * s) * CFrame.Angles(math.rad(40), 0, 0),
		bronze,
		M.Metal
	)
end)

named("cable_car", "Mountain cable car")
def("cable_car", 170, "near", function(cf)
	local low = cf * CFrame.new(-140, 0, 0)
	local high = cf * CFrame.new(140, 0, 0)
	ellipsoid(Vector3.new(160, 220, 160), high * CFrame.new(0, 0, 0), rgb(110, 130, 100), M.Grass)
	ellipsoid(Vector3.new(110, 150, 110), high * CFrame.new(0, 20, 0), rgb(130, 128, 125), M.Rock)
	ellipsoid(Vector3.new(50, 40, 50), high * CFrame.new(0, 90, 0), rgb(245, 248, 255), M.Snow)
	local topY = 104
	box(Vector3.new(24, 14, 18), low * CFrame.new(0, 7, 0), rgb(200, 60, 50), M.WoodPlanks)
	box(Vector3.new(24, 14, 18), high * CFrame.new(0, topY + 7, 0), rgb(200, 60, 50), M.WoodPlanks)
	local a = (low * CFrame.new(0, 12, 0)).Position
	local b = (high * CFrame.new(0, topY + 12, 0)).Position
	for side = -1, 1, 2 do
		local off = Vector3.new(0, 0, side * 4)
		beam(a + (cf.Rotation * off), b + (cf.Rotation * off), 0.3, rgb(40, 40, 44), M.Metal)
	end
	for k = 1, 3 do
		local p = a:Lerp(b, k / 4)
		box(Vector3.new(3, p.Y, 3), CFrame.new(p.X, p.Y / 2, p.Z), rgb(120, 125, 130), M.Metal)
		box(
			Vector3.new(3, 1.2, 12),
			CFrame.lookAt(p, p + cf.LookVector) * CFrame.new(0, 1, 0),
			rgb(120, 125, 130),
			M.Metal
		)
	end
	for k = 1, 4 do
		local base = CFrame.new(0, -520 - k * 20, 0)
		local col = if k % 2 == 0 then rgb(230, 40, 40) else rgb(250, 250, 250)
		local parts = {
			box(Vector3.new(6, 6, 6), base * CFrame.new(0, -6, 0), col),
			box(Vector3.new(6.2, 2.2, 6.2), base * CFrame.new(0, -5, 0), rgb(60, 80, 100), M.Glass),
			box(Vector3.new(0.4, 5, 0.4), base * CFrame.new(0, -1.5, 0), rgb(40, 40, 44), M.Metal),
		}
		local side = if k % 2 == 0 then 4 else -4
		local phase = k * 0.5
		mover(parts, base, function(now)
			local u = (now * 0.03 + phase) % 2
			local f = if u < 1 then u else 2 - u
			local p = a:Lerp(b, f) + cf.Rotation * Vector3.new(0, 0, side)
			return CFrame.new(p) * cf.Rotation
		end)
	end
end)

named("cows", "Alpine cows")
def("cows", 55, "near", function(cf)
	for k = 0, 15 do
		local a = k / 16 * PI * 2
		local p = cf * CFrame.new(math.cos(a) * 44, 0, math.sin(a) * 34)
		box(Vector3.new(0.5, 4, 0.5), p * CFrame.new(0, 2, 0), rgb(120, 85, 55), M.Wood)
		local q = cf * CFrame.new(math.cos(a + PI / 8) * 44, 0, math.sin(a + PI / 8) * 34)
		beam(p.Position + Vector3.new(0, 3, 0), q.Position + Vector3.new(0, 3, 0), 0.3, rgb(120, 85, 55), M.Wood)
	end
	for k = 1, 8 do
		local ccf = cf * CFrame.new(rnd(-30, 30), 0, rnd(-22, 22)) * CFrame.Angles(0, rnd(0, 6.28), 0)
		local body = pick({ rgb(250, 248, 240), rgb(130, 85, 55), rgb(90, 60, 40) })
		animal(ccf, 1.1, body, { head = body, horns = rgb(235, 230, 215), hornSpan = 1.2, legs = 2.2, len = 5 })
		box(Vector3.new(1.4, 1.4, 1.4), ccf * CFrame.new(0.6, 3.6, -1.2), rgb(40, 34, 30))
		box(Vector3.new(0.8, 0.9, 0.8), ccf * CFrame.new(0, 2.4, -3.2), rgb(210, 180, 60), M.Metal)
		local _ = k
	end
end)

named("alpine_hut", "Mountain hut")
def("alpine_hut", 40, "near", function(cf)
	Arch.Build("chalet", X.F, cf, X.Rng, X.Th, X.P)
	for k = 0, 4 do
		vcyl(3, 3.4, cf * CFrame.new(-16 + k * 4, 1.5, -18) * CFrame.Angles(PI / 2, 0, 0), rgb(220, 190, 110), M.Grass)
	end
	vcyl(26, 0.6, cf * CFrame.new(18, 13, -14), rgb(230, 230, 230), M.Metal)
	box(Vector3.new(0.2, 5, 8), cf * CFrame.new(18, 23.5, -10), rgb(220, 30, 40), M.Fabric)
	box(Vector3.new(0.25, 1.6, 8.1), cf * CFrame.new(18, 23.5, -10), rgb(250, 250, 250), M.Fabric)
	for k = 0, 1 do
		box(Vector3.new(8, 1, 2), cf * CFrame.new(-6 + k * 12, 1.4, -24), rgb(130, 90, 55), M.WoodPlanks)
		person(cf * CFrame.new(-6 + k * 12, 0, -26))
	end
end)

---------------------------------------------------------------------------
-- Great Britain
---------------------------------------------------------------------------
local function propPlane(cf: CFrame, col: Color3)
	box(Vector3.new(3, 3, 18), cf * CFrame.new(0, 3.5, 0), col)
	box(Vector3.new(26, 0.5, 4), cf * CFrame.new(0, 3.2, -1), col)
	box(Vector3.new(9, 0.4, 2.5), cf * CFrame.new(0, 4.2, 8), col)
	box(Vector3.new(0.4, 4, 2.4), cf * CFrame.new(0, 6, 8), col)
	box(Vector3.new(2.2, 1.4, 3), cf * CFrame.new(0, 5.4, -2), rgb(60, 80, 100), M.Glass)
	box(Vector3.new(7, 0.4, 0.5), cf * CFrame.new(0, 3.5, -9.4), rgb(40, 40, 44), M.Metal)
	for side = -1, 1, 2 do
		box(Vector3.new(0.4, 2.5, 0.4), cf * CFrame.new(side * 3, 1.25, -2), rgb(40, 40, 44), M.Metal)
	end
end

named("airfield", "Old airfield")
def("airfield", 220, "near", function(cf)
	box(Vector3.new(420, 0.5, 42), cf * CFrame.new(0, 0.25, 0), rgb(88, 90, 96), M.Asphalt)
	for k = -9, 9 do
		box(Vector3.new(12, 0.1, 1), cf * CFrame.new(k * 22, 0.55, 0), rgb(240, 240, 240))
	end
	for side = -1, 1, 2 do
		for m = -3, 3 do
			box(Vector3.new(14, 0.1, 2), cf * CFrame.new(side * 196, 0.55, m * 5), rgb(240, 240, 240))
		end
	end
	box(Vector3.new(200, 0.4, 16), cf * CFrame.new(0, 0.2, -50), rgb(95, 96, 100), M.Asphalt)
	-- control tower
	local tw = cf * CFrame.new(-120, 0, -80)
	box(Vector3.new(14, 26, 14), tw * CFrame.new(0, 13, 0), rgb(236, 236, 230), M.Concrete)
	box(Vector3.new(18, 7, 18), tw * CFrame.new(0, 29.5, 0), rgb(60, 90, 120), M.Glass)
	box(Vector3.new(20, 1, 20), tw * CFrame.new(0, 33.5, 0), rgb(236, 236, 230), M.Concrete)
	vcyl(8, 0.4, tw * CFrame.new(5, 38, 5), rgb(200, 200, 200), M.Metal)
	-- windsock
	local ws = cf * CFrame.new(150, 0, -40)
	vcyl(12, 0.4, ws * CFrame.new(0, 6, 0), rgb(220, 220, 220), M.Metal)
	box(Vector3.new(1.6, 1.6, 6), ws * CFrame.new(0, 11, 3), rgb(255, 120, 20), M.Fabric)
	for k = 0, 3 do
		propPlane(
			cf * CFrame.new(-60 + k * 40, 0, -62) * CFrame.Angles(0, PI, 0),
			pick({ rgb(200, 200, 205), rgb(220, 40, 40), rgb(40, 80, 150), rgb(240, 200, 40) })
		)
	end
end)

named("manor", "Stately manor")
def("manor", 110, "near", function(cf)
	local brick, stone, slate = rgb(150, 75, 55), rgb(225, 215, 195), rgb(70, 75, 85)
	box(Vector3.new(90, 30, 28), cf * CFrame.new(0, 15, 0), brick, M.Brick)
	for side = -1, 1, 2 do
		box(Vector3.new(26, 24, 40), cf * CFrame.new(side * 52, 12, 6), brick, M.Brick)
		wedge(Vector3.new(26, 8, 20), cf * CFrame.new(side * 52, 28, -4), slate, M.Slate)
		wedge(Vector3.new(26, 8, 20), cf * CFrame.new(side * 52, 28, 16) * CFrame.Angles(0, PI, 0), slate, M.Slate)
		for m = 0, 1 do
			box(Vector3.new(3, 10, 3), cf * CFrame.new(side * (20 + m * 14), 34, 4), brick, M.Brick)
		end
	end
	wedge(Vector3.new(90, 10, 14), cf * CFrame.new(0, 35, -7), slate, M.Slate)
	wedge(Vector3.new(90, 10, 14), cf * CFrame.new(0, 35, 7) * CFrame.Angles(0, PI, 0), slate, M.Slate)
	for f = 0, 2 do
		for k = -5, 5 do
			if k ~= 0 or f > 0 then
				box(Vector3.new(3, 5, 0.4), cf * CFrame.new(k * 7.6, 5 + f * 9, -14.1), rgb(70, 90, 120), M.Glass)
				box(Vector3.new(3.8, 0.6, 0.6), cf * CFrame.new(k * 7.6, 2.3 + f * 9, -14.2), stone)
			end
		end
	end
	for k = -2, 2 do
		vcyl(22, 2.2, cf * CFrame.new(k * 5, 11, -20), stone, M.Marble)
	end
	box(Vector3.new(26, 2, 10), cf * CFrame.new(0, 23, -19), stone, M.Marble)
	wedge(Vector3.new(26, 6, 10), cf * CFrame.new(0, 27, -19), stone, M.Marble)
	-- formal garden
	box(Vector3.new(80, 0.4, 70), cf * CFrame.new(0, 0.2, -62), rgb(214, 200, 170), M.Pebble)
	for _, o in { { -22, -46 }, { 22, -46 }, { -22, -78 }, { 22, -78 } } do
		box(Vector3.new(26, 3, 22), cf * CFrame.new(o[1], 1.5, o[2]), rgb(50, 110, 50), M.LeafyGrass)
		box(Vector3.new(22, 3.2, 18), cf * CFrame.new(o[1], 1.6, o[2]), rgb(214, 200, 170), M.Pebble)
		box(Vector3.new(14, 2, 10), cf * CFrame.new(o[1], 1.2, o[2]), rgb(200, 60, 90), M.LeafyGrass)
	end
	vcyl(1.6, 16, cf * CFrame.new(0, 0.8, -62), stone, M.Marble)
	vcyl(0.4, 13, cf * CFrame.new(0, 1.5, -62), rgb(70, 140, 200), M.Glass)
	vcyl(8, 1.2, cf * CFrame.new(0, 4, -62), stone, M.Marble)
end)

---------------------------------------------------------------------------
-- Belgium
---------------------------------------------------------------------------
named("abbey", "Ruined abbey")
def("abbey", 70, "near", function(cf)
	local s = rgb(150, 145, 130)
	for side = -1, 1, 2 do
		for k = -4, 4 do
			local h = if (k + side) % 3 == 0 then rnd(6, 14) else rnd(18, 26)
			box(Vector3.new(4, h, 10), cf * CFrame.new(side * 18, h / 2, k * 11), s, M.Cobblestone)
			if h > 16 then
				box(Vector3.new(4.2, 6, 3), cf * CFrame.new(side * 18, h - 8, k * 11), rgb(60, 70, 60), M.Slate)
			end
		end
	end
	box(Vector3.new(40, 30, 4), cf * CFrame.new(0, 15, -50), s, M.Cobblestone)
	box(Vector3.new(10, 16, 4.4), cf * CFrame.new(0, 14, -50), rgb(60, 70, 60), M.Slate)
	wedge(Vector3.new(40, 12, 4), cf * CFrame.new(0, 36, -50), s, M.Cobblestone)
	box(Vector3.new(16, 42, 16), cf * CFrame.new(-28, 21, 44), s, M.Cobblestone)
	for _ = 1, 10 do
		box(
			Vector3.new(rnd(2, 5), rnd(1, 3), rnd(2, 5)),
			cf * CFrame.new(rnd(-30, 30), 0.8, rnd(-50, 50)) * CFrame.Angles(rnd(0, 1), rnd(0, 3), rnd(0, 1)),
			s,
			M.Cobblestone
		)
	end
	box(Vector3.new(34, 0.3, 100), cf * CFrame.new(0, 0.15, 0), rgb(90, 150, 70), M.Grass)
end)

named("river", "River valley bridge")
def("river", 200, "near", function(cf)
	local pts = {}
	for k = 0, 24 do
		local x = -190 + k * 16
		table.insert(pts, (cf * CFrame.new(x, 0.35, math.sin(k * 0.45) * 40)).Position)
	end
	for k = 1, #pts - 1 do
		local a, b = pts[k], pts[k + 1]
		local len = (b - a).Magnitude + 3
		local c = CFrame.lookAt((a + b) / 2, b)
		box(Vector3.new(30, 0.5, len), c, rgb(60, 120, 150), M.Glass).Reflectance = 0.15
		box(Vector3.new(40, 0.3, len), c * CFrame.new(0, -0.15, 0), rgb(150, 140, 110), M.Pebble)
	end
	-- stone bridge over the middle
	local mid = CFrame.lookAt(pts[12], pts[13])
	for k = -3, 3 do
		box(
			Vector3.new(44, 1.6, 8),
			mid
				* CFrame.Angles(0, PI / 2, 0)
				* CFrame.new(k * 6.2, 4 - math.abs(k) * 1, 0)
				* CFrame.Angles(0, 0, math.rad(k * 5)),
			rgb(150, 140, 125),
			M.Cobblestone
		)
	end
	-- watermill
	local mill = CFrame.new(pts[6]) * CFrame.new(24, 0, 0)
	Arch.Build("cottage", X.F, mill, X.Rng, X.Th, X.P)
	local wheel = hcyl(2, 14, mill * CFrame.new(-12, 6, 0), rgb(110, 75, 45), M.WoodPlanks)
	local wb = wheel.CFrame
	mover({ wheel }, wb, function(now)
		return wb * CFrame.Angles(now * 0.6, 0, 0)
	end)
end)

named("deer", "Grazing deer")
def("deer", 45, "near", function(cf)
	for k = 1, 6 do
		local dcf = cf * CFrame.new(rnd(-30, 30), 0, rnd(-30, 30)) * CFrame.Angles(0, rnd(0, 6.28), 0)
		local parts = animal(dcf, 0.9, rgb(150, 100, 60), {
			legs = 3.6,
			len = 4.4,
			height = 2,
			width = 1.6,
			neck = 2,
			horns = if k % 2 == 0 then rgb(200, 180, 150) else nil,
			hornSpan = 2,
		})
		local _ = parts
	end
end)

named("lodge", "Forest lodge")
def("lodge", 40, "near", function(cf)
	local log = rgb(120, 80, 50)
	for k = 0, 7 do
		hcyl(36, 2.6, cf * CFrame.new(0, 1.3 + k * 2.4, -10), log, M.Wood)
		hcyl(36, 2.6, cf * CFrame.new(0, 1.3 + k * 2.4, 10), log, M.Wood)
		hcyl(22, 2.6, cf * CFrame.new(-17, 1.3 + k * 2.4, 0) * CFrame.Angles(0, PI / 2, 0), log, M.Wood)
		hcyl(22, 2.6, cf * CFrame.new(17, 1.3 + k * 2.4, 0) * CFrame.Angles(0, PI / 2, 0), log, M.Wood)
	end
	wedge(Vector3.new(40, 10, 13), cf * CFrame.new(0, 24, -6.5), rgb(60, 70, 60), M.Slate)
	wedge(Vector3.new(40, 10, 13), cf * CFrame.new(0, 24, 6.5) * CFrame.Angles(0, PI, 0), rgb(60, 70, 60), M.Slate)
	local chim = box(Vector3.new(4, 12, 4), cf * CFrame.new(12, 26, 4), rgb(120, 115, 110), M.Cobblestone)
	smoke(chim, rgb(200, 200, 205), 3, 12, 2, 5)
	for k = 0, 5 do
		hcyl(
			8,
			1.8,
			cf * CFrame.new(-24, 0.9 + (k % 3) * 1.7, -8 + (k // 3) * 2) * CFrame.Angles(0, PI / 2, 0),
			log,
			M.Wood
		)
	end
end)

---------------------------------------------------------------------------
-- Hungary
---------------------------------------------------------------------------
named("parliament", "Gothic parliament")
def("parliament", 110, "near", function(cf)
	local cream, roof = rgb(238, 226, 200), rgb(170, 60, 50)
	box(Vector3.new(170, 30, 40), cf * CFrame.new(0, 15, 0), cream, M.Limestone)
	wedge(Vector3.new(170, 10, 20), cf * CFrame.new(0, 35, -10), roof, M.Slate)
	wedge(Vector3.new(170, 10, 20), cf * CFrame.new(0, 35, 10) * CFrame.Angles(0, PI, 0), roof, M.Slate)
	vcyl(26, 36, cf * CFrame.new(0, 43, 0), cream, M.Limestone)
	ellipsoid(Vector3.new(38, 40, 38), cf * CFrame.new(0, 56, 0), roof, M.Slate)
	cone(34, 5, 1, 5, cf * CFrame.new(0, 72, 0), cream, M.Limestone)
	for k = -8, 8 do
		if k ~= 0 then
			cone(if k % 4 == 0 then 30 else 16, 3, 0.6, 3, cf * CFrame.new(k * 10, 30, -20), cream, M.Limestone)
		end
	end
	for f = 0, 1 do
		for k = -12, 12 do
			box(Vector3.new(2.4, 6, 0.4), cf * CFrame.new(k * 6.6, 7 + f * 12, -20.2), rgb(80, 100, 130), M.Glass)
		end
	end
	for side = -1, 1, 2 do
		box(Vector3.new(18, 44, 18), cf * CFrame.new(side * 70, 22, -6), cream, M.Limestone)
		cone(20, 12, 2, 4, cf * CFrame.new(side * 70, 44, -6), roof, M.Slate)
	end
end)

named("vineyard", "Hillside vineyard")
def("vineyard", 90, "near", function(cf)
	box(Vector3.new(150, 0.3, 110), cf * CFrame.new(0, 0.15, 0), rgb(140, 110, 70), M.Ground)
	local rows = if X.Q >= 3 then 14 else 8
	for k = 0, rows - 1 do
		local z = -48 + k * 96 / (rows - 1)
		box(Vector3.new(130, 3, 2), cf * CFrame.new(0, 1.5, z), rgb(70, 130, 50), M.LeafyGrass)
		if X.Q >= 3 then
			for m = -6, 6, 3 do
				box(Vector3.new(0.4, 4, 0.4), cf * CFrame.new(m * 10, 2, z), rgb(110, 80, 50), M.Wood)
			end
		end
	end
	Arch.Build("villa", X.F, cf * CFrame.new(0, 0, 70), X.Rng, X.Th, X.P)
	for k = 0, 5 do
		vcyl(4, 3.2, cf * CFrame.new(-20 + k * 4, 1, 58) * CFrame.Angles(PI / 2, 0, 0), rgb(120, 80, 50), M.WoodPlanks)
	end
end)

named("balloon_field", "Balloon launch field")
def("balloon_field", 70, "near", function(cf)
	for k = 0, 2 do
		local b = cf * CFrame.new(-36 + k * 36, 0, 10)
		local c = Color3.fromHSV(rnd(0, 1), 0.75, 1)
		ellipsoid(Vector3.new(40, 16, 22), b * CFrame.new(0, 7, 0), c, M.Fabric)
		box(Vector3.new(4, 3.5, 4), b * CFrame.new(-22, 1.75, 0), rgb(150, 105, 60), M.WoodPlanks)
		person(b * CFrame.new(-26, 0, 4))
		person(b * CFrame.new(-18, 0, -6))
	end
	-- one balloon going up and down on a tether
	local base = cf * CFrame.new(0, 0, -34)
	local c1 = Color3.fromHSV(rnd(0, 1), 0.8, 1)
	local parts = {
		ellipsoid(Vector3.new(26, 30, 26), base * CFrame.new(0, 26, 0), c1, M.Fabric),
		vcyl(6, 10, base * CFrame.new(0, 11, 0), c1, M.Fabric),
		box(Vector3.new(4, 3.5, 4), base * CFrame.new(0, 1.75, 0), rgb(150, 105, 60), M.WoodPlanks),
	}
	mover(parts, base, function(now)
		return base * CFrame.new(0, (1 - math.cos(now * 0.15)) * 40, 0)
	end)
end)

---------------------------------------------------------------------------
-- Netherlands
---------------------------------------------------------------------------
named("canal", "Canal quarter")
def("canal", 160, "near", function(cf)
	box(Vector3.new(300, 0.6, 26), cf * CFrame.new(0, 0.3, 0), rgb(60, 100, 120), M.Glass).Reflectance = 0.15
	for side = -1, 1, 2 do
		box(Vector3.new(300, 1.6, 8), cf * CFrame.new(0, 0.8, side * 17), rgb(150, 80, 60), M.Brick)
		box(Vector3.new(300, 0.8, 10), cf * CFrame.new(0, 0.4, side * 26), rgb(160, 160, 160), M.Cobblestone)
		for k = -6, 6 do
			local hcf = cf * CFrame.new(k * 24, 0, side * 40) * CFrame.Angles(0, if side > 0 then PI else 0, 0)
			local c = pick({ rgb(150, 70, 50), rgb(90, 50, 40), rgb(200, 190, 170), rgb(60, 70, 80), rgb(130, 60, 40) })
			local h = rnd(22, 32)
			box(Vector3.new(20, h, 14), hcf * CFrame.new(0, h / 2, 0), c, M.Brick)
			wedge(Vector3.new(10, 8, 1), hcf * CFrame.new(0, h + 4, -6.5), c, M.Brick)
			for f = 0, math.floor(h / 8) - 1 do
				for w = -1, 1 do
					box(Vector3.new(3, 4, 0.4), hcf * CFrame.new(w * 6, 5 + f * 8, -7.1), rgb(250, 250, 250))
					box(Vector3.new(2.4, 3.4, 0.5), hcf * CFrame.new(w * 6, 5 + f * 8, -7.1), rgb(60, 80, 100), M.Glass)
				end
			end
			if X.Th.Night then
				box(Vector3.new(2, 2, 0.5), hcf * CFrame.new(0, 3, -7.2), rgb(255, 220, 160), M.Neon)
			end
		end
	end
	for k = -2, 2 do
		local hb = cf * CFrame.new(k * 55 + 20, 0, if k % 2 == 0 then -7 else 7)
		box(
			Vector3.new(34, 3, 8),
			hb * CFrame.new(0, 1.5, 0),
			pick({ rgb(40, 90, 60), rgb(40, 60, 110), rgb(120, 40, 40) }),
			M.WoodPlanks
		)
		box(Vector3.new(24, 5, 7), hb * CFrame.new(-3, 5, 0), rgb(240, 236, 226), M.WoodPlanks)
		box(Vector3.new(2, 2, 2), hb * CFrame.new(10, 4, 0), rgb(220, 60, 90), M.LeafyGrass)
	end
	for _, x in { -100, 100 } do
		for k = -2, 2 do
			box(
				Vector3.new(8, 1.2, 8),
				cf * CFrame.new(x, 3.2 - math.abs(k) * 0.9, k * 7.8) * CFrame.Angles(math.rad(-k * 8), 0, 0),
				rgb(150, 80, 60),
				M.Brick
			)
		end
	end
end)

named("bike_park", "Bike racks & flower market")
def("bike_park", 40, "near", function(cf)
	for k = 0, 17 do
		local b = cf * CFrame.new(-26 + k * 3, 0, -8)
		local col = Color3.fromHSV(rnd(0, 1), 0.6, 0.9)
		for _, z in { -1.8, 1.8 } do
			hcyl(0.2, 3, b * CFrame.new(0, 1.5, z), rgb(30, 30, 34))
		end
		box(Vector3.new(0.25, 0.25, 3.8), b * CFrame.new(0, 2.4, 0), col, M.Metal)
		box(Vector3.new(0.25, 1.6, 0.25), b * CFrame.new(0, 2.6, 1.2), col, M.Metal)
		box(Vector3.new(1.4, 0.2, 0.2), b * CFrame.new(0, 3.4, -1.6), rgb(30, 30, 34), M.Metal)
	end
	for k = 0, 3 do
		local s = cf * CFrame.new(-24 + k * 16, 0, 12)
		box(Vector3.new(12, 3, 6), s * CFrame.new(0, 1.5, 0), rgb(120, 80, 50), M.WoodPlanks)
		for m = -2, 2 do
			box(
				Vector3.new(2, 1.4, 5),
				s * CFrame.new(m * 2.3, 3.6, 0),
				Color3.fromHSV(rnd(0, 1), 0.8, 1),
				M.LeafyGrass
			)
		end
		wedge(
			Vector3.new(13, 3, 7),
			s * CFrame.new(0, 8, 0),
			pick({ rgb(255, 120, 0), rgb(250, 250, 250), rgb(40, 90, 180) }),
			M.Fabric
		)
		for side = -1, 1, 2 do
			box(Vector3.new(0.3, 6.5, 0.3), s * CFrame.new(side * 6, 3.25, -3), rgb(80, 80, 80), M.Metal)
		end
		if X.Q >= 3 then
			person(s * CFrame.new(0, 0, -6) * CFrame.Angles(0, PI, 0))
		end
	end
end)

---------------------------------------------------------------------------
-- Italy
---------------------------------------------------------------------------
named("old_banking", "Historic banked oval")
def("old_banking", 150, "near", function(cf)
	local n = if X.Q >= 3 then 18 else 12
	local r = 120
	for k = 0, n - 1 do
		local a = -PI / 2 + k / (n - 1) * PI
		local nxt = -PI / 2 + (k + 1) / (n - 1) * PI
		local seg = 2 * r * math.sin((nxt - a) / 2) + 2
		local b = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r)
		box(
			Vector3.new(seg, 1.6, 26),
			b * CFrame.new(0, 9, 0) * CFrame.Angles(math.rad(38), 0, 0),
			rgb(175, 172, 165),
			M.Concrete
		)
		box(Vector3.new(seg, 16, 3), b * CFrame.new(0, 8, -12), rgb(160, 156, 150), M.Concrete)
		box(Vector3.new(seg, 1.4, 0.6), b * CFrame.new(0, 17.5, -11), rgb(205, 210, 215), M.Metal)
		if k % 3 == 0 then
			tree(b * CFrame.new(rnd(-6, 6), 16, -20), rnd(0.8, 1.1), rgb(70, 120, 60))
		end
	end
	local s = box(Vector3.new(40, 8, 1), cf * CFrame.new(0, 12, -r - 16), rgb(30, 30, 34))
	sign(s, Enum.NormalId.Front, "SOPRAELEVATA", rgb(250, 250, 250))
end)

named("duomo", "Cathedral dome")
def("duomo", 80, "near", function(cf)
	local white, green, red = rgb(240, 236, 226), rgb(70, 120, 90), rgb(190, 90, 60)
	box(Vector3.new(80, 32, 36), cf * CFrame.new(0, 16, 0), white, M.Marble)
	for k = 0, 3 do
		box(Vector3.new(80.4, 1.4, 36.4), cf * CFrame.new(0, 6 + k * 7, 0), green, M.Marble)
	end
	vcyl(22, 40, cf * CFrame.new(28, 43, 0), white, M.Marble)
	ellipsoid(Vector3.new(42, 50, 42), cf * CFrame.new(28, 54, 0), red, M.Brick)
	for k = 0, 7 do
		local a = k / 8 * PI * 2
		box(
			Vector3.new(1.2, 22, 1.2),
			cf
				* CFrame.new(28 + math.cos(a) * 17, 64, math.sin(a) * 17)
				* CFrame.Angles(0, -a, 0)
				* CFrame.Angles(0, 0, 0),
			white,
			M.Marble
		)
	end
	vcyl(10, 8, cf * CFrame.new(28, 84, 0), white, M.Marble)
	ball(4, cf * CFrame.new(28, 91, 0), rgb(230, 190, 70), M.Metal)
	box(Vector3.new(14, 90, 14), cf * CFrame.new(-44, 45, 16), white, M.Marble)
	for k = 0, 5 do
		box(
			Vector3.new(14.4, 3, 14.4),
			cf * CFrame.new(-44, 10 + k * 14, 16),
			if k % 2 == 0 then green else red,
			M.Marble
		)
	end
	box(Vector3.new(16, 3, 16), cf * CFrame.new(-44, 91.5, 16), white, M.Marble)
	vcyl(0.3, 1, cf, white)
	for k = 0, 2 do
		box(Vector3.new(6, 10, 0.4), cf * CFrame.new(-20 + k * 20, 16, -18.2), rgb(120, 60, 50), M.WoodPlanks)
	end
end)

---------------------------------------------------------------------------
-- Madrid
---------------------------------------------------------------------------
named("leaning_towers", "Leaning twin towers")
def("leaning_towers", 100, "near", function(cf)
	for side = -1, 1, 2 do
		local foot = cf * CFrame.new(side * 40, 0, 0)
		local t = foot * CFrame.Angles(0, 0, side * math.rad(15)) * CFrame.new(0, 80, 0)
		box(Vector3.new(34, 160, 34), t, rgb(70, 110, 140), M.Glass)
		for k = -7, 7 do
			box(Vector3.new(34.6, 1.4, 34.6), t * CFrame.new(0, k * 10, 0), rgb(200, 205, 210), M.Metal)
		end
		box(
			Vector3.new(36, 6, 36),
			t * CFrame.new(0, 83, 0),
			rgb(230, 40, 40),
			if X.Th.Night then M.Neon else M.SmoothPlastic
		)
	end
	box(Vector3.new(160, 1, 60), cf * CFrame.new(0, 0.5, 0), rgb(180, 180, 182), M.Pavement)
	vcyl(40, 10, cf * CFrame.new(0, 20, 0), rgb(230, 190, 60), M.Metal)
end)

named("triumph_arch", "Triumphal gate")
def("triumph_arch", 45, "near", function(cf)
	local g = rgb(215, 205, 185)
	for _, x in { -22, -8, 8, 22 } do
		box(Vector3.new(6, 30, 12), cf * CFrame.new(x, 15, 0), g, M.Granite)
	end
	box(Vector3.new(52, 10, 13), cf * CFrame.new(0, 35, 0), g, M.Granite)
	box(Vector3.new(54, 2, 14), cf * CFrame.new(0, 41, 0), g:Lerp(Color3.new(0, 0, 0), 0.1), M.Granite)
	box(Vector3.new(16, 8, 10), cf * CFrame.new(0, 46, 0), g, M.Granite)
	for side = -1, 1, 2 do
		box(Vector3.new(4, 6, 4), cf * CFrame.new(side * 22, 45, 0), rgb(120, 110, 90), M.Metal)
	end
	vcyl(1, 90, cf * CFrame.new(0, 0.5, 0), rgb(90, 150, 70), M.Grass)
	for k = 0, 11 do
		local a = k / 12 * PI * 2
		box(
			Vector3.new(2, 1.2, 2),
			cf * CFrame.new(math.cos(a) * 40, 1.2, math.sin(a) * 40),
			Color3.fromHSV(k / 12, 0.7, 1),
			M.LeafyGrass
		)
	end
end)

---------------------------------------------------------------------------
-- Azerbaijan
---------------------------------------------------------------------------
named("maiden_tower", "Maiden's tower")
def("maiden_tower", 35, "near", function(cf)
	local s = rgb(190, 170, 130)
	vcyl(64, 34, cf * CFrame.new(0, 32, 0), s, M.Sandstone)
	box(Vector3.new(14, 60, 22), cf * CFrame.new(0, 30, -18), s, M.Sandstone)
	for k = 0, 11 do
		local a = k / 12 * PI * 2
		box(Vector3.new(3, 3, 3), cf * CFrame.new(math.cos(a) * 16, 65.5, math.sin(a) * 16), s, M.Sandstone)
	end
	for k = 0, 4 do
		box(Vector3.new(2, 4, 0.6), cf * CFrame.new(0, 12 + k * 11, -29.2), rgb(40, 34, 30))
	end
	box(Vector3.new(0.4, 10, 0.4), cf * CFrame.new(0, 69, 0), rgb(220, 220, 220), M.Metal)
	box(Vector3.new(0.2, 3, 5), cf * CFrame.new(0, 72.5, 2.6), rgb(0, 170, 220), M.Fabric)
end)

named("flame_towers", "Flame towers")
def("flame_towers", 110, "near", function(cf)
	for k = 0, 2 do
		local tcf = cf * CFrame.Angles(0, k * 2 * PI / 3, 0) * CFrame.new(0, 0, -38)
		local h = if k == 0 then 190 else 160
		for f = 0, 7 do
			local w = 44 - f * 4.5
			local seg = h / 8
			box(
				Vector3.new(w, seg + 0.2, w * 0.8),
				tcf * CFrame.new(0, seg * (f + 0.5), f * 1.5),
				rgb(70, 110, 150),
				M.Glass
			)
		end
		local flame = wedge(
			Vector3.new(14, 40, 20),
			tcf * CFrame.new(0, h + 16, 12),
			rgb(255, 120, 30),
			if X.Th.Night then M.Neon else M.Glass
		)
		if X.Th.Night then
			light(flame, rgb(255, 140, 50), 60, 2)
		end
		if X.Th.Night then
			for f = 0, 5 do
				box(
					Vector3.new(38 - f * 4, 1.2, 1),
					tcf * CFrame.new(0, 20 + f * 26, -16 + f * 1.4),
					Color3.fromHSV(0.05 + f * 0.02, 0.9, 1),
					M.Neon
				)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Singapore
---------------------------------------------------------------------------
named("sands_hotel", "Sky-park hotel")
def("sands_hotel", 130, "near", function(cf)
	for k = -1, 1 do
		local t = cf * CFrame.new(k * 56, 0, 0)
		box(Vector3.new(34, 180, 22), t * CFrame.new(0, 90, -6), rgb(200, 215, 225), M.Glass)
		box(
			Vector3.new(34, 180, 16),
			t * CFrame.new(0, 90, 14) * CFrame.Angles(math.rad(-4), 0, 0),
			rgb(180, 200, 215),
			M.Glass
		)
		for f = 1, 17 do
			local lit = X.Th.Night and (f + k) % 2 == 0
			box(
				Vector3.new(34.6, 1.2, 38),
				t * CFrame.new(0, f * 10, 4),
				if lit then rgb(255, 226, 170) else rgb(230, 235, 240),
				if lit then M.Neon else M.Metal
			)
		end
	end
	local deck = box(Vector3.new(230, 7, 34), cf * CFrame.new(20, 184, 2), rgb(235, 238, 242), M.SmoothPlastic)
	wedge(Vector3.new(34, 7, 40), cf * CFrame.new(150, 184, 2) * CFrame.Angles(0, -PI / 2, 0), rgb(235, 238, 242))
	box(Vector3.new(120, 1, 8), cf * CFrame.new(-10, 188, -8), rgb(40, 170, 220), M.Glass)
	for k = 0, 8 do
		tree(cf * CFrame.new(-80 + k * 22, 187.5, 10), 0.6, rgb(60, 150, 70))
	end
	if X.Th.Night then
		local strip = box(Vector3.new(230, 1, 1), cf * CFrame.new(20, 181, -15.2), rgb(120, 200, 255), M.Neon)
		light(strip, rgb(120, 200, 255), 60, 1.5)
	end
	local _ = deck
end)

named("supertrees", "Glowing supertrees")
def("supertrees", 110, "near", function(cf)
	local spots = {
		{ 0, 0, 90 },
		{ 40, 20, 70 },
		{ -40, 16, 76 },
		{ 20, -40, 60 },
		{ -28, -36, 56 },
		{ 60, -14, 50 },
		{ -64, -8, 52 },
		{ 6, 52, 58 },
	}
	local tops = {}
	for k, s in spots do
		local h = s[3]
		local t = cf * CFrame.new(s[1], 0, s[2])
		local steps = 8
		for f = 0, steps - 1 do
			local d = 6 + (f / steps) ^ 2 * 14
			vcyl(
				h / steps + 0.2,
				d,
				t * CFrame.new(0, h / steps * (f + 0.5), 0),
				rgb(120, 70, 110):Lerp(rgb(60, 110, 70), (f % 2) * 0.4),
				M.Metal
			)
		end
		local canopy = vcyl(
			4,
			34,
			t * CFrame.new(0, h + 2, 0),
			if X.Th.Night then Color3.fromHSV((k * 0.13) % 1, 0.7, 1) else rgb(130, 90, 140),
			if X.Th.Night then M.Neon else M.Metal
		)
		for m = 0, 7 do
			local a = m / 8 * PI * 2
			box(
				Vector3.new(1, 12, 1),
				t
					* CFrame.new(math.cos(a) * 14, h - 5, math.sin(a) * 14)
					* CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5),
				rgb(60, 130, 70),
				M.LeafyGrass
			)
		end
		tops[k] = (t * CFrame.new(0, h * 0.6, 0)).Position
		if k <= 2 then
			light(canopy, canopy.Color, 50, 1.5)
		end
	end
	beam(tops[2], tops[3], 3, rgb(220, 222, 228), M.Metal)
	beam(tops[1] - Vector3.new(0, 10, 0), tops[4], 3, rgb(220, 222, 228), M.Metal)
end)

named("lion_fountain", "Lion fountain")
def("lion_fountain", 35, "near", function(cf)
	vcyl(2, 40, cf * CFrame.new(0, 1, 0), rgb(220, 220, 225), M.Marble)
	vcyl(0.6, 36, cf * CFrame.new(0, 2.1, 0), rgb(60, 140, 200), M.Glass)
	local w = rgb(245, 245, 248)
	box(Vector3.new(8, 14, 8), cf * CFrame.new(0, 9, 8), w, M.Marble)
	ellipsoid(Vector3.new(10, 12, 12), cf * CFrame.new(0, 21, 6), w, M.Marble)
	ball(8, cf * CFrame.new(0, 24, 3), w, M.Marble)
	box(Vector3.new(4, 3, 3), cf * CFrame.new(0, 22, -0.5), w, M.Marble)
	ellipsoid(Vector3.new(6, 6, 14), cf * CFrame.new(0, 10, 16) * CFrame.Angles(math.rad(-40), 0, 0), w, M.Marble)
	local mouth = box(Vector3.new(1, 1, 1), cf * CFrame.new(0, 21.5, -2), w)
	mouth.Transparency = 1
	local jet = sparkle(mouth, rgb(200, 230, 255), 60, 22, 1.2, 1.4)
	jet.EmissionDirection = Enum.NormalId.Front
	jet.Acceleration = Vector3.new(0, -30, 0)
	jet.SpreadAngle = Vector2.new(4, 4)
	jet.LightEmission = 0.3
	light(mouth, rgb(200, 230, 255), 30, 1)
end)

---------------------------------------------------------------------------
-- Texas
---------------------------------------------------------------------------
named("obs_tower", "Red-sail observation tower")
def("obs_tower", 45, "near", function(cf)
	vcyl(230, 7, cf * CFrame.new(0, 115, 0), rgb(235, 235, 238), M.Concrete)
	vcyl(8, 24, cf * CFrame.new(0, 200, 0), rgb(80, 110, 140), M.Glass)
	vcyl(2, 28, cf * CFrame.new(0, 205, 0), rgb(235, 235, 238), M.Concrete)
	local n = if X.Q >= 3 then 18 else 12
	for k = 0, n - 1 do
		local a = k / n * PI * 2
		beam(
			(cf * CFrame.new(0, 222, 0)).Position,
			(cf * CFrame.new(math.cos(a) * 44, 120, math.sin(a) * 44)).Position,
			1.2,
			rgb(220, 30, 40),
			if X.Th.Night then M.Neon else M.SmoothPlastic
		)
	end
	box(Vector3.new(60, 6, 60), cf * CFrame.new(0, 3, 0), rgb(200, 200, 205), M.Concrete)
end)

named("longhorns", "Longhorn ranch")
def("longhorns", 80, "near", function(cf)
	for k = 0, 19 do
		local a = k / 20 * PI * 2
		local p = cf * CFrame.new(math.cos(a) * 62, 0, math.sin(a) * 44)
		box(Vector3.new(0.7, 5, 0.7), p * CFrame.new(0, 2.5, 0), rgb(120, 85, 55), M.Wood)
		local q = cf * CFrame.new(math.cos(a + PI / 10) * 62, 0, math.sin(a + PI / 10) * 44)
		beam(p.Position + Vector3.new(0, 4, 0), q.Position + Vector3.new(0, 4, 0), 0.35, rgb(140, 100, 65), M.Wood)
		beam(p.Position + Vector3.new(0, 2, 0), q.Position + Vector3.new(0, 2, 0), 0.35, rgb(140, 100, 65), M.Wood)
	end
	for _ = 1, 9 do
		local ccf = cf * CFrame.new(rnd(-45, 45), 0, rnd(-30, 30)) * CFrame.Angles(0, rnd(0, 6.28), 0)
		local col = pick({ rgb(170, 90, 40), rgb(200, 130, 70), rgb(120, 70, 40), rgb(240, 230, 210) })
		animal(ccf, 1.2, col, { horns = rgb(235, 225, 200), hornSpan = 3.4, legs = 2.4, len = 5.4 })
	end
	vcyl(2, 8, cf * CFrame.new(0, 1, 0), rgb(120, 130, 140), M.Metal)
	-- windpump
	local wp = cf * CFrame.new(-48, 0, -30)
	for _, o in { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } } do
		beam(
			(wp * CFrame.new(o[1] * 2, 0, o[2] * 2)).Position,
			(wp * CFrame.new(o[1] * 0.3, 30, o[2] * 0.3)).Position,
			0.4,
			rgb(150, 150, 155),
			M.Metal
		)
	end
	local fan = hcyl(1, 10, wp * CFrame.new(0, 31, -1) * CFrame.Angles(0, PI / 2, 0), rgb(200, 200, 205), M.Metal)
	local fb = fan.CFrame
	mover({ fan }, fb, function(now)
		return fb * CFrame.Angles(now * 2, 0, 0)
	end)
end)

named("rodeo", "Rodeo arena")
def("rodeo", 70, "near", function(cf)
	vcyl(0.3, 90, cf * CFrame.new(0, 0.15, 0), rgb(190, 150, 100), M.Ground)
	for k = 0, 23 do
		local a = k / 24 * PI * 2
		local p = cf * CFrame.new(math.cos(a) * 44, 0, math.sin(a) * 44)
		box(Vector3.new(0.8, 6, 0.8), p * CFrame.new(0, 3, 0), rgb(250, 250, 250), M.WoodPlanks)
		local q = cf * CFrame.new(math.cos(a + PI / 12) * 44, 0, math.sin(a + PI / 12) * 44)
		for _, y in { 2, 4, 5.6 } do
			beam(
				p.Position + Vector3.new(0, y, 0),
				q.Position + Vector3.new(0, y, 0),
				0.4,
				rgb(250, 250, 250),
				M.WoodPlanks
			)
		end
	end
	for row = 0, 4 do
		box(Vector3.new(70, 1.5, 4), cf * CFrame.new(0, 1 + row * 2.4, 52 + row * 4), rgb(200, 160, 110), M.WoodPlanks)
	end
	for k = 0, 2 do
		local a = k * 2 * PI / 3
		vcyl(
			4,
			3,
			cf * CFrame.new(math.cos(a) * 20, 2, math.sin(a) * 20),
			pick({ rgb(40, 90, 180), rgb(200, 40, 40), rgb(250, 250, 250) }),
			M.Metal
		)
	end
	local horse =
		animal(cf * CFrame.new(-10, 0, 0), 1.2, rgb(110, 70, 40), { neck = 2.2, legs = 3.8, len = 5.6, width = 2 })
	local base = cf * CFrame.new(-10, 0, 0)
	table.insert(horse, box(Vector3.new(1.4, 2, 0.8), base * CFrame.new(0, 8.2, 0.4), rgb(40, 90, 170)))
	table.insert(horse, box(Vector3.new(2.6, 0.5, 2.6), base * CFrame.new(0, 10.4, 0.4), rgb(160, 110, 60)))
	mover(horse, base, function(now)
		local a = now * 0.5
		local p = cf.Position + Vector3.new(math.cos(a) * 26, math.abs(math.sin(now * 5)) * 0.8, math.sin(a) * 26)
		return CFrame.lookAt(
			p,
			cf.Position + Vector3.new(math.cos(a + 0.05) * 26, p.Y - cf.Position.Y, math.sin(a + 0.05) * 26)
		)
	end)
end)

---------------------------------------------------------------------------
-- Mexico
---------------------------------------------------------------------------
named("sun_stone", "Sun stone monument")
def("sun_stone", 35, "near", function(cf)
	box(Vector3.new(40, 6, 16), cf * CFrame.new(0, 3, 0), rgb(150, 140, 125), M.Slate)
	local disc = cf * CFrame.new(0, 30, 0) * CFrame.Angles(0, PI / 2, 0)
	hcyl(6, 48, disc, rgb(160, 150, 130), M.Basalt)
	for k, d in { 40, 30, 20 } do
		hcyl(6.4, d, disc, rgb(160, 150, 130):Lerp(rgb(110, 100, 90), k * 0.2), M.Basalt)
	end
	for k = 0, 15 do
		local a = k / 16 * PI * 2
		box(
			Vector3.new(6.8, 3, 1.6),
			disc * CFrame.new(0, math.cos(a) * 22, math.sin(a) * 22) * CFrame.Angles(a, 0, 0),
			rgb(120, 110, 95),
			M.Basalt
		)
	end
	box(Vector3.new(7, 8, 7), disc, rgb(200, 170, 90), M.Basalt)
end)

named("papel_picado", "Papel picado plaza")
def("papel_picado", 60, "near", function(cf)
	box(Vector3.new(100, 0.4, 70), cf * CFrame.new(0, 0.2, 0), rgb(200, 150, 110), M.Cobblestone)
	local poles = {}
	for k = 0, 5 do
		local p = cf * CFrame.new(-45 + (k % 3) * 45, 0, if k < 3 then -30 else 30)
		box(Vector3.new(0.8, 16, 0.8), p * CFrame.new(0, 8, 0), rgb(120, 90, 60), M.Wood)
		poles[k + 1] = (p * CFrame.new(0, 15, 0)).Position
	end
	local links = { { 1, 2 }, { 2, 3 }, { 4, 5 }, { 5, 6 }, { 1, 5 }, { 2, 6 }, { 3, 5 }, { 2, 4 } }
	for _, l in links do
		local a, b = poles[l[1]], poles[l[2]]
		local n = if X.Q >= 3 then 14 else 8
		for m = 1, n - 1 do
			local f = m / n
			local p = a:Lerp(b, f) - Vector3.new(0, math.sin(f * PI) * 3, 0)
			box(
				Vector3.new(0.1, 2.4, 2),
				CFrame.lookAt(p, p + (b - a)) * CFrame.Angles(0, PI / 2, 0) * CFrame.new(0, -1.2, 0),
				Color3.fromHSV((m * 0.17) % 1, 0.85, 1),
				M.Fabric
			)
		end
	end
	for k = 0, 3 do
		local s = cf * CFrame.new(-30 + k * 20, 0, 0)
		box(Vector3.new(10, 3, 5), s * CFrame.new(0, 1.5, 0), rgb(200, 60, 80), M.WoodPlanks)
		wedge(Vector3.new(11, 2, 6), s * CFrame.new(0, 6.5, 0), Color3.fromHSV(k * 0.22, 0.7, 1), M.Fabric)
		for side = -1, 1, 2 do
			box(Vector3.new(0.3, 5.5, 0.3), s * CFrame.new(side * 5, 2.75, -2.5), rgb(80, 80, 80), M.Metal)
		end
		if X.Q >= 3 then
			person(s * CFrame.new(0, 0, -6) * CFrame.Angles(0, PI, 0))
			person(s * CFrame.new(3, 0, -8))
		end
	end
end)

---------------------------------------------------------------------------
-- Brazil
---------------------------------------------------------------------------
named("redeemer", "Statue on the mountain")
def("redeemer", 400, "far", function(cf)
	cone(360, 700, 60, 10, cf, rgb(70, 120, 70), M.Grass)
	cone(120, 240, 50, 4, cf * CFrame.new(0, 250, 0), rgb(110, 110, 105), M.Rock)
	local top = cf * CFrame.new(0, 370, 0)
	local w = rgb(235, 232, 225)
	box(Vector3.new(16, 14, 16), top * CFrame.new(0, 7, 0), w, M.Concrete)
	box(Vector3.new(12, 60, 8), top * CFrame.new(0, 44, 0), w, M.Concrete)
	box(Vector3.new(76, 7, 6), top * CFrame.new(0, 66, 0), w, M.Concrete)
	ball(9, top * CFrame.new(0, 76, 0), w, M.Concrete)
	box(Vector3.new(16, 30, 9), top * CFrame.new(0, 28, 0), w, M.Concrete)
	local glow = box(Vector3.new(2, 2, 2), top * CFrame.new(0, 40, -8), w, M.Neon)
	light(glow, rgb(255, 250, 235), 60, 1)
end)

named("sugarloaf", "Sugarloaf mountain")
def("sugarloaf", 320, "far", function(cf)
	ellipsoid(Vector3.new(260, 460, 240), cf * CFrame.new(0, 100, 0), rgb(110, 115, 105), M.Rock)
	ellipsoid(Vector3.new(300, 140, 280), cf * CFrame.new(0, 10, 0), rgb(60, 120, 60), M.Grass)
	local hill = cf * CFrame.new(-240, 0, 60)
	ellipsoid(Vector3.new(200, 220, 190), hill * CFrame.new(0, 30, 0), rgb(70, 125, 65), M.Grass)
	local a = (hill * CFrame.new(0, 138, 0)).Position
	local b = (cf * CFrame.new(0, 328, 0)).Position
	beam(a, b, 0.6, rgb(40, 40, 44), M.Metal)
	box(Vector3.new(14, 8, 12), CFrame.new(a), rgb(220, 220, 225), M.Concrete)
	box(Vector3.new(14, 8, 12), CFrame.new(b), rgb(220, 220, 225), M.Concrete)
	local base = CFrame.new(0, -600, 0)
	local car = {
		box(Vector3.new(7, 6, 10), base * CFrame.new(0, -5, 0), rgb(240, 240, 245)),
		box(Vector3.new(7.2, 2, 10.2), base * CFrame.new(0, -4, 0), rgb(60, 80, 100), M.Glass),
	}
	mover(car, base, function(now)
		local u = (now * 0.02) % 2
		local f = if u < 1 then u else 2 - u
		return CFrame.lookAt(a:Lerp(b, f), b)
	end)
end)

named("favela", "Colourful hillside town")
def("favela", 140, "near", function(cf)
	wedge(Vector3.new(240, 80, 150), cf * CFrame.new(0, 40, 20), X.Th.Ground:Lerp(rgb(120, 100, 70), 0.4), M.Ground)
	local colors = {
		rgb(240, 90, 80),
		rgb(255, 200, 60),
		rgb(80, 180, 220),
		rgb(120, 200, 110),
		rgb(250, 250, 240),
		rgb(240, 140, 60),
		rgb(200, 120, 220),
		rgb(255, 160, 180),
	}
	local rows = if X.Q >= 3 then 9 else 6
	for row = 0, rows - 1 do
		local f = (row + 0.5) / rows
		local z = -75 + f * 150 + 20
		local y = f * 80
		for u = -112, 112, rnd(10, 14) do
			if X.Rng:NextNumber() < 0.85 then
				local w, d, h = rnd(8, 12), rnd(8, 10), rnd(6, 11)
				local hcf = cf * CFrame.new(u + rnd(-2, 2), y + h / 2 - 1, z)
				local c = pick(colors)
				box(Vector3.new(w, h, d), hcf, c, M.Plaster)
				box(
					Vector3.new(2, 2.4, 0.3),
					hcf * CFrame.new(rnd(-2, 2), 0.5, -d / 2 - 0.1),
					if X.Th.Night then rgb(255, 220, 150) else rgb(60, 70, 80),
					if X.Th.Night then M.Neon else M.Glass
				)
				if X.Rng:NextNumber() < 0.3 then
					vcyl(2.4, 2.6, hcf * CFrame.new(rnd(-2, 2), h / 2 + 1.2, 0), rgb(50, 110, 180), M.Plastic)
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Las Vegas
---------------------------------------------------------------------------
named("welcome_sign", "Famous welcome sign")
def("welcome_sign", 30, "near", function(cf)
	for side = -1, 1, 2 do
		box(Vector3.new(1.4, 22, 1.4), cf * CFrame.new(side * 9, 11, 0), rgb(230, 230, 235), M.Metal)
	end
	local board =
		box(Vector3.new(26, 26, 1), cf * CFrame.new(0, 28, 0) * CFrame.Angles(0, 0, PI / 4), rgb(250, 250, 250))
	local s = box(Vector3.new(24, 12, 1.2), cf * CFrame.new(0, 28, 0), rgb(250, 250, 250))
	sign(s, Enum.NormalId.Front, "WELCOME TO\nNEON STRIP", rgb(220, 30, 50))
	sign(s, Enum.NormalId.Back, "DRIVE\nFAST", rgb(40, 90, 200))
	for k = 0, 15 do
		local a = k / 16 * PI * 2
		local bulb = ball(
			1.2,
			board.CFrame * CFrame.new(math.cos(a) * 12.5 * 1, math.sin(a) * 12.5, -0.8),
			rgb(255, 230, 140),
			M.Neon
		)
		local _ = bulb
	end
	local star =
		box(Vector3.new(6, 6, 0.8), cf * CFrame.new(0, 44, 0) * CFrame.Angles(0, 0, PI / 4), rgb(220, 30, 50), M.Neon)
	light(star, rgb(255, 80, 80), 30, 1.5)
end)

named("fountain_show", "Dancing fountains")
def("fountain_show", 130, "near", function(cf)
	box(Vector3.new(230, 1, 80), cf * CFrame.new(0, 0.5, 0), rgb(40, 110, 170), M.Glass).Reflectance = 0.2
	box(Vector3.new(236, 2.4, 86), cf * CFrame.new(0, 0.4, 0), rgb(220, 215, 205), M.Marble)
	local cols = if X.Q >= 3 then 18 else 10
	for k = 0, cols - 1 do
		for row = -1, 1 do
			if X.Q >= 3 or row == 0 then
				local x = -105 + k * 210 / (cols - 1)
				local jet = vcyl(
					40,
					2.2,
					cf * CFrame.new(x, 20, row * 24),
					rgb(230, 245, 255),
					if X.Th.Night then M.Neon else M.Glass
				)
				jet.Transparency = 0.35
				local base = jet.CFrame
				mover({ jet }, base, function(now)
					local h = (math.sin(now * 1.4 - k * 0.45 + row) * 0.5 + 0.5) * 36
					return base * CFrame.new(-(36 - h) * 0.5, 0, 0) * CFrame.new(-(36 - h) * 0.5, 0, 0)
				end)
			end
		end
	end
	for k = 0, 7 do
		Arch.Build(
			"casino_hotel",
			X.F,
			cf * CFrame.new(-105 + k * 30, 0, 90) * CFrame.Angles(0, PI, 0),
			X.Rng,
			X.Th,
			X.P
		)
		if k >= 1 then
			break
		end
	end
end)

named("lattice_tower", "Lattice tower replica")
def("lattice_tower", 55, "near", function(cf)
	latticeTower(cf, 180, rgb(120, 90, 70))
	if X.Th.Night then
		local top = ball(3, cf * CFrame.new(0, 187, 0), rgb(255, 220, 140), M.Neon)
		light(top, rgb(255, 220, 140), 40, 1.5)
		for _, y in { 40, 90 } do
			local w = if y == 40 then 40 else 20
			box(Vector3.new(w + 0.6, 0.6, w + 0.6), cf * CFrame.new(0, y + 1.8, 0), rgb(255, 210, 120), M.Neon)
		end
	end
end)

---------------------------------------------------------------------------
-- Qatar
---------------------------------------------------------------------------
named("pearl_monument", "Pearl monument")
def("pearl_monument", 35, "near", function(cf)
	vcyl(2, 36, cf * CFrame.new(0, 1, 0), rgb(220, 215, 205), M.Marble)
	vcyl(0.6, 32, cf * CFrame.new(0, 2.2, 0), rgb(50, 150, 200), M.Glass)
	box(Vector3.new(8, 8, 8), cf * CFrame.new(0, 6, 0), rgb(230, 225, 215), M.Marble)
	ellipsoid(Vector3.new(26, 6, 22), cf * CFrame.new(0, 11, 0), rgb(200, 190, 175), M.Marble)
	ellipsoid(
		Vector3.new(26, 6, 22),
		cf * CFrame.new(0, 20, 7) * CFrame.Angles(math.rad(-55), 0, 0),
		rgb(210, 200, 185),
		M.Marble
	)
	local pearl =
		ball(10, cf * CFrame.new(0, 17, -1), rgb(250, 248, 255), if X.Th.Night then M.Neon else M.SmoothPlastic)
	pearl.Reflectance = 0.3
	light(pearl, rgb(240, 240, 255), 40, 1.5)
end)

named("tent_stadium", "Tent stadium")
def("tent_stadium", 130, "near", function(cf)
	local n = 16
	for k = 0, n - 1 do
		local a = k / n * PI * 2
		box(
			Vector3.new(2 * 100 * math.sin(PI / n) + 2, 24, 10),
			cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 12, -100),
			rgb(230, 225, 215),
			M.Concrete
		)
	end
	for side = -1, 1, 2 do
		for s = 0, 5 do
			local col = if s % 2 == 0 then rgb(30, 30, 34) else rgb(245, 245, 245)
			if s == 5 then
				col = rgb(160, 30, 40)
			end
			wedge(
				Vector3.new(34, 60, 110),
				cf * CFrame.new(-85 + s * 34, 50, side * 55) * CFrame.Angles(0, if side > 0 then PI else 0, 0),
				col,
				M.Fabric
			)
		end
	end
	if X.Th.Night then
		local l = box(Vector3.new(200, 1, 1), cf * CFrame.new(0, 81, 0), rgb(255, 240, 210), M.Neon)
		light(l, rgb(255, 240, 210), 70, 1.5)
	end
end)

---------------------------------------------------------------------------
-- Abu Dhabi
---------------------------------------------------------------------------
named("theme_park", "Red-roof theme park")
def("theme_park", 150, "near", function(cf)
	vcyl(20, 170, cf * CFrame.new(0, 10, 0), rgb(235, 235, 238), M.Concrete)
	ellipsoid(Vector3.new(200, 40, 200), cf * CFrame.new(0, 20, 0), rgb(210, 20, 30), M.Metal)
	local s = box(Vector3.new(60, 10, 1), cf * CFrame.new(0, 12, -86), rgb(250, 250, 250))
	sign(s, Enum.NormalId.Front, "SPEED WORLD", rgb(210, 20, 30))
	-- roller coaster loop around the building
	local R = 125
	local pts = {}
	local n = if X.Q >= 3 then 40 else 24
	for k = 0, n do
		local a = k / n * PI * 2
		pts[k] = (cf * CFrame.new(math.cos(a) * R, 26 + math.sin(a * 3) * 18, math.sin(a) * R)).Position
	end
	for k = 0, n - 1 do
		beam(pts[k], pts[k + 1], 1.4, rgb(250, 200, 30), M.Metal)
		if k % 3 == 0 then
			box(
				Vector3.new(1.2, pts[k].Y, 1.2),
				CFrame.new(pts[k].X, pts[k].Y / 2, pts[k].Z),
				rgb(200, 200, 205),
				M.Metal
			)
		end
	end
	local base = CFrame.new(0, -700, 0)
	local train = {}
	for c = 0, 3 do
		table.insert(train, box(Vector3.new(4, 3, 6), base * CFrame.new(0, 2, c * 6.5), rgb(210, 20, 30)))
	end
	mover(train, base, function(now)
		local a = (now * 0.35) % (PI * 2)
		local p = cf * CFrame.new(math.cos(a) * R, 26 + math.sin(a * 3) * 18 + 2, math.sin(a) * R)
		local q = cf
			* CFrame.new(math.cos(a - 0.05) * R, 26 + math.sin((a - 0.05) * 3) * 18 + 2, math.sin(a - 0.05) * R)
		return CFrame.lookAt(p.Position, q.Position)
	end)
end)

named("white_palace", "White palace domes")
def("white_palace", 100, "near", function(cf)
	local w, gold = rgb(248, 248, 250), rgb(230, 190, 80)
	box(Vector3.new(120, 20, 70), cf * CFrame.new(0, 10, 0), w, M.Marble)
	vcyl(14, 40, cf * CFrame.new(0, 27, 0), w, M.Marble)
	ellipsoid(Vector3.new(44, 46, 44), cf * CFrame.new(0, 40, 0), w, M.Marble)
	vcyl(8, 2, cf * CFrame.new(0, 66, 0), gold, M.Metal)
	for _, o in { { -40, -20 }, { 40, -20 }, { -40, 20 }, { 40, 20 }, { -20, -26 }, { 20, -26 } } do
		ellipsoid(Vector3.new(14, 16, 14), cf * CFrame.new(o[1], 23, o[2]), w, M.Marble)
		vcyl(4, 1, cf * CFrame.new(o[1], 33, o[2]), gold, M.Metal)
	end
	for _, o in { { -60, -35 }, { 60, -35 }, { -60, 35 }, { 60, 35 } } do
		vcyl(80, 5, cf * CFrame.new(o[1], 40, o[2]), w, M.Marble)
		vcyl(4, 7, cf * CFrame.new(o[1], 70, o[2]), gold, M.Metal)
		cone(10, 4, 1, 3, cf * CFrame.new(o[1], 80, o[2]), gold, M.Metal)
	end
	box(Vector3.new(90, 0.6, 50), cf * CFrame.new(0, 0.3, -60), rgb(60, 150, 200), M.Glass)
	if X.Th.Night then
		local l = box(Vector3.new(120.4, 1, 70.4), cf * CFrame.new(0, 2, 0), rgb(150, 200, 255), M.Neon)
		light(l, rgb(170, 210, 255), 60, 1.5)
	end
end)

---------------------------------------------------------------------------
-- Arctic
---------------------------------------------------------------------------
named("ski_jump", "Ski jump")
def("ski_jump", 70, "near", function(cf)
	local n = 10
	for k = 0, n - 1 do
		local f = k / n
		local y = 90 - f * 80 - math.sin(f * PI) * 6
		local z = -60 + f * 110
		local seg = cf * CFrame.new(0, y, z) * CFrame.Angles(math.rad(-38 + f * 30), 0, 0)
		box(Vector3.new(10, 1.4, 14), seg, rgb(240, 245, 255), M.Snow)
		box(Vector3.new(1, y, 1), cf * CFrame.new(-4, y / 2, z), rgb(150, 155, 165), M.Metal)
		box(Vector3.new(1, y, 1), cf * CFrame.new(4, y / 2, z), rgb(150, 155, 165), M.Metal)
	end
	box(Vector3.new(14, 16, 14), cf * CFrame.new(0, 98, -64), rgb(200, 40, 40), M.Metal)
	wedge(Vector3.new(60, 40, 90), cf * CFrame.new(0, 20, 110) * CFrame.Angles(0, PI, 0), rgb(240, 245, 255), M.Snow)
	box(Vector3.new(10, 24, 10), cf * CFrame.new(40, 12, 40), rgb(220, 225, 235), M.Concrete)
	box(Vector3.new(12, 6, 12), cf * CFrame.new(40, 27, 40), rgb(70, 110, 150), M.Glass)
end)

named("ski_lift", "Ski lift")
def("ski_lift", 150, "near", function(cf)
	wedge(Vector3.new(120, 70, 260), cf * CFrame.new(0, 35, 0), rgb(238, 244, 252), M.Snow)
	local a = (cf * CFrame.new(-20, 10, -126)).Position
	local b = (cf * CFrame.new(-20, 80, 126)).Position
	for k = 0, 5 do
		local p = a:Lerp(b, k / 5)
		local ground = 70 * ((p - a).Magnitude / (b - a).Magnitude)
		box(
			Vector3.new(1.6, p.Y - ground + 4, 1.6),
			CFrame.new(p.X, (p.Y + ground) / 2, p.Z),
			rgb(140, 145, 150),
			M.Metal
		)
		box(Vector3.new(10, 1, 1), CFrame.new(p) * cf.Rotation * CFrame.new(0, 2, 0), rgb(140, 145, 150), M.Metal)
	end
	for side = -1, 1, 2 do
		beam(
			a + cf.RightVector * side * 4 + Vector3.new(0, 2, 0),
			b + cf.RightVector * side * 4 + Vector3.new(0, 2, 0),
			0.25,
			rgb(40, 40, 44),
			M.Metal
		)
	end
	local chairs = if X.Q >= 3 then 10 else 6
	for k = 0, chairs - 1 do
		local base = CFrame.new(0, -740 - k * 10, 0)
		local parts = {
			box(Vector3.new(4, 0.6, 2), base * CFrame.new(0, -5, 0), rgb(60, 70, 80), M.Metal),
			box(Vector3.new(4, 2, 0.4), base * CFrame.new(0, -4, 1), rgb(60, 70, 80), M.Metal),
			box(Vector3.new(0.3, 5, 0.3), base * CFrame.new(0, -2.5, 0), rgb(40, 40, 44), M.Metal),
			box(
				Vector3.new(1.4, 2, 1),
				base * CFrame.new(-1, -3.8, 0),
				pick({ rgb(220, 40, 40), rgb(40, 110, 220), rgb(250, 200, 30) }),
				M.Fabric
			),
		}
		local up = k % 2 == 0
		local phase = k / chairs
		mover(parts, base, function(now)
			local f = (now * 0.02 + phase) % 1
			if not up then
				f = 1 - f
			end
			local p = a:Lerp(b, f) + cf.RightVector * (if up then 4 else -4) + Vector3.new(0, 2, 0)
			return CFrame.new(p) * cf.Rotation
		end)
	end
end)

named("ice_castle", "Ice castle")
def("ice_castle", 60, "near", function(cf)
	local ice = rgb(190, 230, 255)
	for k = 0, 3 do
		local w = cf * CFrame.Angles(0, k * PI / 2, 0)
		local wall = box(Vector3.new(60, 18, 5), w * CFrame.new(0, 9, -30), ice, M.Ice)
		wall.Transparency = 0.2
		for m = -5, 5 do
			box(Vector3.new(3, 3, 5.2), w * CFrame.new(m * 5.5, 19.5, -30), ice, M.Ice).Transparency = 0.2
		end
		local tw = vcyl(34, 14, w * CFrame.new(30, 17, -30), ice, M.Ice)
		tw.Transparency = 0.15
		cone(14, 16, 2, 4, w * CFrame.new(30, 34, -30), rgb(220, 240, 255), M.Glacier)
	end
	local keep = box(Vector3.new(22, 40, 22), cf * CFrame.new(0, 20, 0), ice, M.Glacier)
	keep.Transparency = 0.1
	local glow = box(Vector3.new(10, 10, 10), cf * CFrame.new(0, 16, 0), rgb(120, 200, 255), M.Neon)
	light(glow, rgb(140, 210, 255), 70, 2.5)
end)

named("polar_bears", "Polar bears")
def("polar_bears", 55, "near", function(cf)
	vcyl(2, 90, cf * CFrame.new(0, 0.6, 0), rgb(235, 245, 255), M.Glacier)
	for k = 1, 4 do
		local base = CFrame.new(0, -760 - k * 10, 0)
		local s = if k == 4 then 0.8 else 1.3
		local parts = animal(
			base,
			s,
			rgb(245, 244, 238),
			{ legs = 2.2, len = 6, width = 3, height = 3, head = rgb(240, 238, 232) }
		)
		circler(
			parts,
			base,
			cf.Position + Vector3.new(0, 1.6, 0),
			rnd(14, 34),
			rnd(2, 4) * (if k % 2 == 0 then 1 else -1),
			rnd(0, 6)
		)
	end
end)

---------------------------------------------------------------------------
-- Volcano island
---------------------------------------------------------------------------
named("moai", "Stone head statues")
def("moai", 60, "near", function(cf)
	box(Vector3.new(90, 5, 16), cf * CFrame.new(0, 2.5, 0), rgb(110, 100, 90), M.Basalt)
	for k = -3, 3 do
		local m = cf * CFrame.new(k * 12, 5, 0) * CFrame.Angles(0, rnd(-0.1, 0.1), 0)
		local stone = rgb(115, 105, 95):Lerp(rgb(90, 85, 80), rnd(0, 1))
		box(Vector3.new(8, 14, 6), m * CFrame.new(0, 7, 0), stone, M.Basalt)
		box(Vector3.new(7, 12, 7), m * CFrame.new(0, 20, 0), stone, M.Basalt)
		box(Vector3.new(7.4, 2, 3), m * CFrame.new(0, 23, -2.6), stone:Lerp(Color3.new(0, 0, 0), 0.15), M.Basalt)
		box(Vector3.new(2, 7, 2.4), m * CFrame.new(0, 18.5, -4.2), stone, M.Basalt)
		box(Vector3.new(1.6, 6, 1.6), m * CFrame.new(-4, 20, 0), stone, M.Basalt)
		box(Vector3.new(1.6, 6, 1.6), m * CFrame.new(4, 20, 0), stone, M.Basalt)
		if k % 2 == 0 then
			vcyl(4, 7, m * CFrame.new(0, 28, 0), rgb(150, 60, 40), M.Basalt)
		end
	end
end)

named("lava_river", "River of lava")
def("lava_river", 190, "near", function(cf)
	local pts = {}
	for k = 0, 22 do
		table.insert(pts, (cf * CFrame.new(-176 + k * 16, 0.4, math.sin(k * 0.5) * 50)).Position)
	end
	for k = 1, #pts - 1 do
		local a, b = pts[k], pts[k + 1]
		local c = CFrame.lookAt((a + b) / 2, b)
		local len = (b - a).Magnitude + 3
		local lava = box(Vector3.new(16, 0.8, len), c, rgb(255, 100, 20), M.Neon)
		box(Vector3.new(30, 0.6, len), c * CFrame.new(0, -0.3, 0), rgb(40, 34, 32), M.Basalt)
		for side = -1, 1, 2 do
			ellipsoid(
				Vector3.new(rnd(6, 10), rnd(3, 6), rnd(6, 12)),
				c * CFrame.new(side * rnd(10, 14), 1, rnd(-4, 4)),
				rgb(50, 44, 42),
				M.Basalt
			)
		end
		if k % 4 == 0 then
			light(lava, rgb(255, 120, 40), 40, 2)
			if X.Q >= 3 then
				smoke(lava, rgb(90, 80, 80), 6, 20, 1.5, 6)
			end
		end
	end
end)

named("tiki_village", "Tiki village")
def("tiki_village", 70, "near", function(cf)
	for k = 0, 4 do
		Arch.Build("tiki_hut", X.F, cf * CFrame.Angles(0, k * 1.25, 0) * CFrame.new(0, 0, -40), X.Rng, X.Th, X.P)
	end
	for k = 0, 5 do
		local t = cf * CFrame.Angles(0, k * 1.05 + 0.5, 0) * CFrame.new(0, 0, -24)
		box(Vector3.new(0.8, 8, 0.8), t * CFrame.new(0, 4, 0), rgb(110, 75, 45), M.Wood)
		local fire = box(Vector3.new(1.4, 1.8, 1.4), t * CFrame.new(0, 8.8, 0), rgb(255, 150, 40), M.Neon)
		sparkle(fire, rgb(255, 150, 40), 8, 5, 0.8, 0.8)
	end
	for k = 0, 2 do
		local t = cf * CFrame.new(-12 + k * 12, 0, 12)
		for m = 0, 3 do
			box(
				Vector3.new(4, 4, 4),
				t * CFrame.new(0, 2 + m * 4, 0),
				Color3.fromHSV((k * 0.2 + m * 0.1) % 1, 0.6, 0.7),
				M.WoodPlanks
			)
			box(Vector3.new(3, 0.8, 0.4), t * CFrame.new(0, 3 + m * 4, -2.1), rgb(20, 20, 20))
		end
	end
	local pit = vcyl(1, 8, cf * CFrame.new(0, 0.5, 0), rgb(60, 50, 45), M.Basalt)
	local fire = box(Vector3.new(3, 2, 3), cf * CFrame.new(0, 1.8, 0), rgb(255, 120, 30), M.Neon)
	sparkle(fire, rgb(255, 140, 40), 20, 10, 1.4, 1)
	light(fire, rgb(255, 140, 60), 40, 2)
	local _ = pit
end)

named("shipwreck", "Shipwreck")
def("shipwreck", 50, "shore", function(cf)
	local wood = rgb(100, 70, 45)
	local s = cf * CFrame.new(rnd(-100, 100), 0, 20) * CFrame.Angles(0, rnd(0, 6), math.rad(18))
	box(Vector3.new(12, 8, 30), s * CFrame.new(0, 3, 0), wood, M.WoodPlanks)
	wedge(Vector3.new(12, 8, 10), s * CFrame.new(0, 3, -20) * CFrame.Angles(0, PI, 0), wood, M.WoodPlanks)
	box(Vector3.new(12, 6, 14), s * CFrame.new(0, 2, 28) * CFrame.Angles(math.rad(10), 0.3, 0), wood, M.WoodPlanks)
	box(Vector3.new(1, 22, 1), s * CFrame.new(0, 17, -4) * CFrame.Angles(0.2, 0, 0), wood, M.Wood)
	box(Vector3.new(1, 10, 1), s * CFrame.new(0, 11, 10) * CFrame.Angles(-0.3, 0, 0.4), wood, M.Wood)
	box(Vector3.new(0.2, 8, 8), s * CFrame.new(0, 20, -1), rgb(210, 200, 180), M.Fabric).Transparency = 0.2
end)

---------------------------------------------------------------------------
-- Extra sights shared by several circuits
---------------------------------------------------------------------------
named("lighthouse_cape", "Cape lighthouse")
def("lighthouse_cape", 50, "shore", function(cf)
	local c = cf * CFrame.new(rnd(-200, 200), 0, 0)
	box(Vector3.new(50, 30, 50), c * CFrame.new(0, 15, 0), rgb(200, 140, 80), M.Sandstone)
	vcyl(56, 10, c * CFrame.new(0, 58, 0), rgb(250, 250, 250), M.Plaster)
	for k = 0, 2 do
		vcyl(5, 10.4, c * CFrame.new(0, 40 + k * 16, 0), rgb(210, 40, 40), M.Plaster)
	end
	local lamp = vcyl(6, 8, c * CFrame.new(0, 89, 0), rgb(255, 245, 200), M.Neon)
	light(lamp, rgb(255, 245, 210), 80, 2)
	local beamPart = box(Vector3.new(3, 3, 120), c * CFrame.new(0, 89, -60), rgb(255, 250, 220), M.Neon)
	beamPart.Transparency = 0.8
	local pivot = c * CFrame.new(0, 89, 0)
	mover({ beamPart }, pivot, function(now)
		return pivot * CFrame.Angles(0, now * 0.8, 0)
	end)
	box(Vector3.new(24, 10, 16), c * CFrame.new(0, 35, 14), rgb(250, 250, 250), M.Plaster)
end)

named("white_village", "Whitewashed village")
def("white_village", 110, "near", function(cf)
	local n = if X.Q >= 3 then 34 else 20
	for _ = 1, n do
		local h = rnd(8, 16)
		local w, d = rnd(10, 18), rnd(10, 16)
		local hc = cf
			* CFrame.new(rnd(-90, 90), 0, rnd(-80, 80))
			* CFrame.Angles(0, X.Rng:NextInteger(0, 3) * PI / 2, 0)
		box(Vector3.new(w, h, d), hc * CFrame.new(0, h / 2, 0), rgb(250, 250, 246), M.Plaster)
		box(
			Vector3.new(w + 0.2, 1, d + 0.2),
			hc * CFrame.new(0, 0.5, 0),
			pick({ rgb(40, 90, 170), rgb(230, 180, 40) }),
			M.Plaster
		)
		if X.Rng:NextNumber() < 0.6 then
			wedge(Vector3.new(w, 3, d / 2), hc * CFrame.new(0, h + 1.5, -d / 4), rgb(200, 100, 60), M.Slate)
			wedge(
				Vector3.new(w, 3, d / 2),
				hc * CFrame.new(0, h + 1.5, d / 4) * CFrame.Angles(0, PI, 0),
				rgb(200, 100, 60),
				M.Slate
			)
		end
		box(Vector3.new(2, 4, 2), hc * CFrame.new(w / 2 - 2, h + 2, 0), rgb(250, 250, 246), M.Plaster)
		box(Vector3.new(3, 1, 3), hc * CFrame.new(w / 2 - 2, h + 4.5, 0), rgb(250, 250, 246), M.Plaster)
		box(
			Vector3.new(2.4, 4, 0.3),
			hc * CFrame.new(0, 2, -d / 2 - 0.1),
			pick({ rgb(40, 90, 170), rgb(40, 130, 80), rgb(150, 60, 40) }),
			M.WoodPlanks
		)
		box(Vector3.new(2, 2, 0.3), hc * CFrame.new(-w / 4, h - 4, -d / 2 - 0.1), rgb(40, 90, 170), M.WoodPlanks)
	end
	Arch.Build("church", X.F, cf * CFrame.new(0, 0, 0), X.Rng, X.Th, X.P)
end)

named("chateau", "Château")
def("chateau", 90, "near", function(cf)
	local stone, roof = rgb(235, 225, 200), rgb(60, 70, 95)
	box(Vector3.new(90, 28, 30), cf * CFrame.new(0, 14, 0), stone, M.Limestone)
	box(Vector3.new(92, 12, 16), cf * CFrame.new(0, 34, -7), roof, M.Slate)
	wedge(Vector3.new(92, 10, 8), cf * CFrame.new(0, 45, -11), roof, M.Slate)
	box(Vector3.new(92, 12, 16), cf * CFrame.new(0, 34, 7), roof, M.Slate)
	for side = -1, 1, 2 do
		vcyl(40, 18, cf * CFrame.new(side * 48, 20, -12), stone, M.Limestone)
		cone(26, 20, 1, 6, cf * CFrame.new(side * 48, 40, -12), roof, M.Slate)
		box(Vector3.new(0.2, 3, 5), cf * CFrame.new(side * 48, 68, -9.4), rgb(40, 60, 160), M.Fabric)
	end
	for f = 0, 1 do
		for k = -5, 5 do
			box(Vector3.new(3, 7, 0.4), cf * CFrame.new(k * 7.6, 7 + f * 12, -15.2), rgb(70, 90, 120), M.Glass)
		end
	end
	box(Vector3.new(24, 0.4, 90), cf * CFrame.new(0, 0.2, -60), rgb(220, 205, 170), M.Pebble)
	for k = -4, 4 do
		for side = -1, 1, 2 do
			ellipsoid(
				Vector3.new(4, 16, 4),
				cf * CFrame.new(side * 14, 8, -24 - k * 8 - 40),
				rgb(40, 90, 50),
				M.LeafyGrass
			)
		end
	end
	vcyl(1.6, 18, cf * CFrame.new(0, 0.8, -60), stone, M.Marble)
	vcyl(8, 1.2, cf * CFrame.new(0, 4, -60), stone, M.Marble)
end)

named("village_square", "Village café square")
def("village_square", 70, "near", function(cf)
	box(Vector3.new(90, 0.4, 70), cf * CFrame.new(0, 0.2, 0), rgb(200, 180, 150), M.Cobblestone)
	for k = 0, 5 do
		local hcf = cf * CFrame.Angles(0, k * PI / 3, 0) * CFrame.new(0, 0, -44) * CFrame.Angles(0, PI, 0)
		local c = pick({ rgb(240, 215, 170), rgb(230, 190, 140), rgb(245, 230, 200), rgb(220, 170, 130) })
		box(Vector3.new(22, 18, 12), hcf * CFrame.new(0, 9, 0), c, M.Plaster)
		box(Vector3.new(23, 1.4, 13), hcf * CFrame.new(0, 18.7, 0), rgb(200, 100, 60), M.Slate)
		for w = -1, 1 do
			box(
				Vector3.new(3, 4, 0.3),
				hcf * CFrame.new(w * 7, 11, 6.1),
				pick({ rgb(60, 110, 150), rgb(80, 130, 90), rgb(160, 140, 120) }),
				M.WoodPlanks
			)
		end
		box(
			Vector3.new(20, 0.5, 4),
			hcf * CFrame.new(0, 5, 8) * CFrame.Angles(math.rad(-12), 0, 0),
			pick({ rgb(200, 40, 40), rgb(40, 90, 170), rgb(40, 130, 80) }),
			M.Fabric
		)
	end
	for k = 0, 5 do
		local tcf = cf * CFrame.new(-18 + (k % 3) * 18, 0, -8 + (k // 3) * 16)
		vcyl(3, 1, tcf * CFrame.new(0, 1.5, 0), rgb(60, 60, 64), M.Metal)
		vcyl(0.3, 5, tcf * CFrame.new(0, 3.1, 0), rgb(250, 250, 250))
		box(Vector3.new(0.3, 7, 0.3), tcf * CFrame.new(0, 3.5, 0), rgb(220, 220, 220), M.Metal)
		hcyl(
			1,
			9,
			tcf * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, PI / 2),
			pick({ rgb(200, 40, 40), rgb(250, 250, 250), rgb(40, 90, 170) }),
			M.Fabric
		)
		if X.Q >= 3 then
			person(tcf * CFrame.new(-2.4, 0, 0) * CFrame.Angles(0, PI / 2, 0))
		end
	end
	vcyl(10, 3, cf * CFrame.new(0, 5, 0), rgb(230, 225, 215), M.Marble)
	vcyl(1, 12, cf * CFrame.new(0, 0.9, 0), rgb(230, 225, 215), M.Marble)
end)

-- a smoking volcano on the horizon (Mexico)
named("volcano_far", "Smoking volcano")
def("volcano_far", 450, "far", function(cf)
	cone(420, 900, 110, 10, cf, rgb(80, 90, 80), M.Rock)
	cone(120, 1000, 800, 3, cf, rgb(70, 120, 60), M.Grass)
	local top = box(Vector3.new(60, 4, 60), cf * CFrame.new(0, 420, 0), rgb(90, 80, 75), M.Basalt)
	smoke(top, rgb(200, 200, 205), 50, 140, 2, 16)
end)

---------------------------------------------------------------------------
-- Bahrain: the lone tree in the desert
---------------------------------------------------------------------------
named("tree_of_life", "Lone desert tree")
def("tree_of_life", 45, "near", function(cf)
	ellipsoid(Vector3.new(60, 10, 60), cf * CFrame.new(0, 0, 0), X.Th.Ground:Lerp(rgb(255, 255, 255), 0.08), M.Sand)
	local bark = rgb(110, 85, 60)
	box(Vector3.new(4, 16, 4), cf * CFrame.new(0, 10, 0) * CFrame.Angles(0, 0, 0.08), bark, M.Wood)
	for k = 0, 5 do
		local a = k / 6 * PI * 2
		box(
			Vector3.new(1.6, 14, 1.6),
			cf * CFrame.new(0, 18, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(50), 0, 0) * CFrame.new(0, 6, 0),
			bark,
			M.Wood
		)
		ellipsoid(
			Vector3.new(16, 7, 16),
			cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 26, -10),
			rgb(90, 130, 60),
			M.LeafyGrass
		)
	end
	ellipsoid(Vector3.new(22, 10, 22), cf * CFrame.new(0, 30, 0), rgb(100, 140, 65), M.LeafyGrass)
	for k = 0, 7 do
		local a = k / 8 * PI * 2
		box(
			Vector3.new(0.4, 1.2, 0.4),
			cf * CFrame.new(math.cos(a) * 24, 3.8, math.sin(a) * 24),
			rgb(90, 80, 70),
			M.Metal
		)
		if X.Th.Night and k % 2 == 0 then
			local l = box(
				Vector3.new(1, 1, 1),
				cf * CFrame.new(math.cos(a) * 24, 4.6, math.sin(a) * 24),
				rgb(255, 230, 170),
				M.Neon
			)
			if k == 0 then
				light(l, rgb(255, 225, 170), 40, 1.5)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Arizona canyon
---------------------------------------------------------------------------
named("rock_arches", "Natural stone arches")
def("rock_arches", 90, "near", function(cf)
	local reds = { rgb(200, 100, 60), rgb(185, 85, 50), rgb(215, 125, 75), rgb(170, 80, 50) }
	for k = 0, 1 do
		local a = cf * CFrame.new(-40 + k * 70, 0, rnd(-20, 20)) * CFrame.Angles(0, rnd(-0.4, 0.4), 0)
		local h = rnd(40, 60)
		local span = rnd(30, 44)
		for side = -1, 1, 2 do
			box(
				Vector3.new(12, h, 14),
				a * CFrame.new(side * span / 2, h / 2, 0) * CFrame.Angles(0, 0, side * 0.08),
				pick(reds),
				M.Sandstone
			)
		end
		for m = -3, 3 do
			local y = h + 4 - math.abs(m) ^ 1.6 * 1.1
			box(Vector3.new(span / 6 + 4, 9, 13), a * CFrame.new(m * span / 7, y, 0), pick(reds), M.Sandstone)
		end
	end
	-- balanced rock and hoodoos
	local b = cf * CFrame.new(0, 0, 50)
	box(Vector3.new(8, 26, 8), b * CFrame.new(0, 13, 0), pick(reds), M.Sandstone)
	ellipsoid(Vector3.new(22, 16, 18), b * CFrame.new(0, 33, 0), pick(reds), M.Sandstone)
	for _ = 1, 6 do
		cone(
			rnd(14, 30),
			rnd(7, 11),
			rnd(2, 4),
			4,
			cf * CFrame.new(rnd(-80, 80), 0, rnd(-60, 70)),
			pick(reds),
			M.Sandstone
		)
	end
end)

named("western_town", "Wild-west town")
def("western_town", 90, "near", function(cf)
	box(Vector3.new(150, 0.3, 26), cf * CFrame.new(0, 0.15, 0), rgb(180, 130, 90), M.Ground)
	local names = { "SALOON", "GENERAL STORE", "SHERIFF", "BANK", "HOTEL", "BLACKSMITH", "BARBER" }
	local woods = { rgb(150, 100, 60), rgb(120, 80, 50), rgb(170, 120, 75), rgb(140, 70, 50), rgb(180, 160, 120) }
	local n = 0
	for side = -1, 1, 2 do
		for k = -3, 2 do
			n += 1
			local b = cf * CFrame.new(k * 24 + 12, 0, side * 26) * CFrame.Angles(0, if side > 0 then PI else 0, 0)
			local col = pick(woods)
			local h = rnd(12, 17)
			box(Vector3.new(20, h, 16), b * CFrame.new(0, h / 2, 0), col, M.WoodPlanks)
			local front = box(Vector3.new(20, 5, 1), b * CFrame.new(0, h + 2.5, -8), col, M.WoodPlanks)
			local _ = front
			local s = box(Vector3.new(16, 3, 0.4), b * CFrame.new(0, h + 2.5, -8.7), rgb(240, 225, 190), M.WoodPlanks)
			sign(s, Enum.NormalId.Front, names[(n - 1) % #names + 1], rgb(90, 40, 20))
			box(Vector3.new(20, 0.6, 6), b * CFrame.new(0, 0.9, -11), rgb(110, 75, 45), M.WoodPlanks)
			box(Vector3.new(20, 0.5, 6), b * CFrame.new(0, 8, -11), rgb(110, 75, 45), M.WoodPlanks)
			for _, x in { -9, 9 } do
				box(Vector3.new(0.6, 7.4, 0.6), b * CFrame.new(x, 4.4, -13.6), rgb(100, 70, 40), M.Wood)
			end
			box(Vector3.new(4, 6, 0.4), b * CFrame.new(0, 3.6, -8.2), rgb(70, 45, 30), M.WoodPlanks)
			if X.Th.Night or X.Th.Sky.ClockTime > 16.5 then
				box(Vector3.new(3, 2, 0.3), b * CFrame.new(-6, 5, -8.2), rgb(255, 210, 140), M.Neon)
			end
		end
	end
	Arch.Build("water_tower", X.F, cf * CFrame.new(70, 0, 0), X.Rng, X.Th, X.P)
	local horse = animal(
		cf * CFrame.new(-30, 0, -2) * CFrame.Angles(0, PI / 2, 0),
		1.1,
		rgb(120, 80, 50),
		{ neck = 2.2, legs = 3.8, len = 5.6, width = 2 }
	)
	local _ = horse
	for k = 0, 3 do
		ellipsoid(Vector3.new(3, 3, 3), cf * CFrame.new(-60 + k * 38, 1.5, rnd(-4, 4)), rgb(170, 140, 80), M.Grass)
	end
end)

---------------------------------------------------------------------------
-- Norway fjord
---------------------------------------------------------------------------
named("stave_church", "Stave church")
def("stave_church", 40, "near", function(cf)
	local tar, wood = rgb(50, 36, 28), rgb(90, 60, 38)
	box(Vector3.new(26, 12, 34), cf * CFrame.new(0, 6, 0), wood, M.WoodPlanks)
	local y = 12
	for k = 0, 3 do
		local w = 30 - k * 7
		local d = 38 - k * 8
		wedge(Vector3.new(w, 6, d / 2), cf * CFrame.new(0, y + 3, -d / 4), tar, M.WoodPlanks)
		wedge(Vector3.new(w, 6, d / 2), cf * CFrame.new(0, y + 3, d / 4) * CFrame.Angles(0, PI, 0), tar, M.WoodPlanks)
		y += 6
		if k < 3 then
			box(Vector3.new(w - 8, 5, d - 10), cf * CFrame.new(0, y + 2.5, 0), wood, M.WoodPlanks)
			y += 5
		end
	end
	cone(16, 4, 0.6, 4, cf * CFrame.new(0, y, 0), tar, M.WoodPlanks)
	for side = -1, 1, 2 do
		box(
			Vector3.new(1, 3, 3),
			cf * CFrame.new(side * 13, 20, -19) * CFrame.Angles(math.rad(-30), 0, 0),
			rgb(140, 100, 60),
			M.WoodPlanks
		)
	end
	for k = 0, 5 do
		box(Vector3.new(1, 3, 2.4), cf * CFrame.new(-18 + k * 7, 1.5, -30), rgb(130, 130, 125), M.Slate)
	end
end)

named("fishing_village", "Red fishing cabins")
def("fishing_village", 90, "near", function(cf)
	vcyl(0.6, 150, cf * CFrame.new(0, 0.3, 30), rgb(40, 90, 120), M.Glass).Reflectance = 0.2
	for k = -4, 4 do
		local b = cf * CFrame.new(k * 15, 0, rnd(-12, -2))
		local col = pick({ rgb(170, 40, 35), rgb(160, 35, 30), rgb(230, 190, 60), rgb(240, 238, 230) })
		for _, o in { { -4, -4 }, { 4, -4 }, { -4, 4 }, { 4, 4 } } do
			box(Vector3.new(0.8, 4, 0.8), b * CFrame.new(o[1], 2, o[2] + 10), rgb(90, 70, 50), M.Wood)
		end
		box(Vector3.new(11, 8, 10), b * CFrame.new(0, 8, 10), col, M.WoodPlanks)
		wedge(Vector3.new(12, 4, 5.5), b * CFrame.new(0, 14, 7.25), rgb(40, 40, 44), M.Slate)
		wedge(Vector3.new(12, 4, 5.5), b * CFrame.new(0, 14, 12.75) * CFrame.Angles(0, PI, 0), rgb(40, 40, 44), M.Slate)
		box(Vector3.new(2, 2.6, 0.3), b * CFrame.new(-3, 9, 4.9), rgb(250, 250, 250))
		box(Vector3.new(2, 2.6, 0.3), b * CFrame.new(3, 9, 4.9), rgb(250, 250, 250))
		if X.Th.Night then
			box(Vector3.new(1.6, 2.2, 0.35), b * CFrame.new(3, 9, 4.9), rgb(255, 220, 150), M.Neon)
		end
	end
	for k = 0, 2 do
		local r = box(Vector3.new(8, 2, 1), cf * CFrame.new(-30 + k * 30, 5, 40), rgb(200, 200, 200))
		local _ = r
		for m = -3, 3 do
			box(Vector3.new(0.3, 3, 0.3), cf * CFrame.new(-30 + k * 30 + m, 3.5, 40), rgb(120, 110, 90), M.Wood)
		end
	end
end)

named("waterfall", "Cliff waterfall")
def("waterfall", 90, "near", function(cf)
	local rock = rgb(95, 100, 105)
	box(Vector3.new(160, 120, 50), cf * CFrame.new(0, 60, 30), rock, M.Rock)
	for _ = 1, 6 do
		ellipsoid(
			Vector3.new(rnd(40, 70), rnd(40, 80), rnd(30, 50)),
			cf * CFrame.new(rnd(-70, 70), rnd(30, 110), rnd(10, 40)),
			rock:Lerp(rgb(70, 90, 70), rnd(0, 0.5)),
			M.Rock
		)
	end
	box(Vector3.new(170, 6, 60), cf * CFrame.new(0, 122, 30), rgb(80, 120, 70), M.Grass)
	for k = 0, 5 do
		tree(cf * CFrame.new(-70 + k * 28, 125, 36), rnd(0.9, 1.2), rgb(40, 100, 55))
	end
	local fall = box(Vector3.new(16, 118, 3), cf * CFrame.new(0, 60, 4), rgb(225, 240, 250), M.Glass)
	fall.Transparency = 0.25
	local sheen = box(Vector3.new(12, 118, 3.4), cf * CFrame.new(0, 60, 4), rgb(250, 255, 255), M.Neon)
	sheen.Transparency = 0.8
	vcyl(1, 60, cf * CFrame.new(0, 0.5, -20), rgb(60, 130, 160), M.Glass)
	local mist = box(Vector3.new(20, 2, 20), cf * CFrame.new(0, 3, -6), rgb(255, 255, 255))
	mist.Transparency = 1
	smoke(mist, rgb(240, 248, 255), 10, 30, 5, 8)
	local splash = sparkle(mist, rgb(230, 245, 255), 30, 18, 1.4, 1.2)
	splash.SpreadAngle = Vector2.new(50, 50)
end)

---------------------------------------------------------------------------
-- Morocco / Sahara
---------------------------------------------------------------------------
named("kasbah", "Mud-brick kasbah")
def("kasbah", 80, "near", function(cf)
	local mud = rgb(190, 120, 80)
	for k = 0, 3 do
		local w = cf * CFrame.Angles(0, k * PI / 2, 0)
		box(Vector3.new(80, 18, 5), w * CFrame.new(0, 9, -40), mud, M.Sandstone)
		for m = -7, 7 do
			box(Vector3.new(2.6, 3, 5.2), w * CFrame.new(m * 5.4, 19.5, -40), mud, M.Sandstone)
		end
		local t = w * CFrame.new(40, 0, -40)
		box(Vector3.new(14, 34, 14), t * CFrame.new(0, 17, 0), mud:Lerp(rgb(170, 100, 65), 0.3), M.Sandstone)
		for m = -1, 1 do
			box(Vector3.new(3, 4, 14.4), t * CFrame.new(m * 4.5, 36, 0), mud, M.Sandstone)
			box(Vector3.new(1.4, 3, 0.4), t * CFrame.new(m * 4, 26, -7.2), rgb(50, 35, 25))
		end
	end
	box(Vector3.new(30, 26, 26), cf * CFrame.new(0, 13, 0), mud, M.Sandstone)
	box(Vector3.new(10, 14, 0.4), cf * CFrame.new(0, 7, -40.3), rgb(80, 50, 30), M.WoodPlanks)
	wedge(Vector3.new(12, 4, 2), cf * CFrame.new(0, 16, -41), mud, M.Sandstone)
	for k = 0, 3 do
		palm(cf * CFrame.Angles(0, k * PI / 2 + PI / 4, 0) * CFrame.new(0, 0, -26), rnd(0.9, 1.2))
	end
end)

named("souk", "Spice souk")
def("souk", 60, "near", function(cf)
	box(Vector3.new(90, 0.3, 40), cf * CFrame.new(0, 0.15, 0), rgb(200, 160, 110), M.Cobblestone)
	local awn = { rgb(200, 40, 40), rgb(30, 110, 170), rgb(240, 180, 30), rgb(40, 140, 80), rgb(180, 60, 150) }
	local goods = {
		rgb(220, 120, 30),
		rgb(200, 40, 30),
		rgb(240, 200, 40),
		rgb(120, 70, 40),
		rgb(60, 140, 60),
		rgb(250, 240, 220),
	}
	for side = -1, 1, 2 do
		for k = -3, 3 do
			local s = cf * CFrame.new(k * 12, 0, side * 12) * CFrame.Angles(0, if side > 0 then PI else 0, 0)
			box(Vector3.new(10, 3, 5), s * CFrame.new(0, 1.5, 0), rgb(140, 90, 55), M.WoodPlanks)
			for m = -1, 1 do
				ellipsoid(Vector3.new(2.6, 2, 2.6), s * CFrame.new(m * 3.2, 3.6, -0.6), pick(goods), M.Sand)
			end
			for _, x in { -5, 5 } do
				box(Vector3.new(0.4, 8, 0.4), s * CFrame.new(x, 4, -3), rgb(110, 75, 45), M.Wood)
			end
			box(
				Vector3.new(11, 0.3, 8),
				s * CFrame.new(0, 8.2, -1) * CFrame.Angles(math.rad(-10), 0, 0),
				pick(awn),
				M.Fabric
			)
			if X.Q >= 3 then
				person(s * CFrame.new(0, 0, 3) * CFrame.Angles(0, PI, 0))
			end
		end
	end
	for k = 0, 2 do
		local l = box(
			Vector3.new(1.6, 2.2, 1.6),
			cf * CFrame.new(-24 + k * 24, 12, 0),
			rgb(240, 170, 60),
			if X.Th.Night then M.Neon else M.Metal
		)
		beam(
			(cf * CFrame.new(-24 + k * 24, 13, 0)).Position,
			(cf * CFrame.new(-24 + k * 24, 16, 0)).Position,
			0.1,
			rgb(40, 40, 40),
			M.Metal
		)
		local _ = l
	end
end)

---------------------------------------------------------------------------
-- Tokyo bay
---------------------------------------------------------------------------
latticeTower = function(cf: CFrame, h: number, c: Color3, c2: Color3?)
	local legs = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
	local s = h / 180
	for _, l in legs do
		local pts = {
			(cf * CFrame.new(l[1] * 30 * s, 0, l[2] * 30 * s)).Position,
			(cf * CFrame.new(l[1] * 18 * s, 40 * s, l[2] * 18 * s)).Position,
			(cf * CFrame.new(l[1] * 9 * s, 90 * s, l[2] * 9 * s)).Position,
			(cf * CFrame.new(l[1] * 3 * s, 160 * s, l[2] * 3 * s)).Position,
		}
		for k = 1, 3 do
			local seg = beam(pts[k], pts[k + 1], (3.4 - k * 0.6) * s, c, M.Metal)
			if seg and c2 and k % 2 == 0 then
				seg.Color = c2
			end
		end
	end
	for i, y in { 40, 90, 130 } do
		local w = ({ 40, 20, 12 })[i] * s
		box(Vector3.new(w, 3 * s, w), cf * CFrame.new(0, y * s, 0), if c2 and i % 2 == 0 then c2 else c, M.Metal)
	end
	vcyl(26 * s, 1.6 * s, cf * CFrame.new(0, 173 * s, 0), c, M.Metal)
end

named("red_tower", "Red lattice TV tower")
def("red_tower", 50, "near", function(cf)
	latticeTower(cf, 230, rgb(230, 70, 40), rgb(250, 250, 250))
	box(Vector3.new(24, 7, 24), cf * CFrame.new(0, 128, 0), rgb(60, 90, 120), M.Glass)
	if X.Th.Night then
		local top = ball(3, cf * CFrame.new(0, 240, 0), rgb(255, 120, 60), M.Neon)
		light(top, rgb(255, 120, 60), 40, 1.5)
		for _, y in { 51, 115 } do
			box(Vector3.new(26, 0.6, 26), cf * CFrame.new(0, y + 2, 0), rgb(255, 160, 80), M.Neon)
		end
	end
	box(Vector3.new(60, 14, 60), cf * CFrame.new(0, 7, 0), rgb(230, 230, 232), M.Concrete)
end)

named("rainbow_bridge", "Harbour suspension bridge")
def("rainbow_bridge", 60, "sea", function(cf)
	local len = 700
	local deckY = 40
	local b = cf * CFrame.new(0, 0, 100) * CFrame.Angles(0, PI / 2, 0)
	box(Vector3.new(24, 4, len), b * CFrame.new(0, deckY, 0), rgb(230, 232, 236), M.Concrete)
	for _, z in { -170, 170 } do
		for side = -1, 1, 2 do
			box(Vector3.new(4, 120, 6), b * CFrame.new(side * 10, 60, z), rgb(245, 245, 248), M.Concrete)
		end
		box(Vector3.new(24, 6, 6), b * CFrame.new(0, 116, z), rgb(245, 245, 248), M.Concrete)
		box(Vector3.new(24, 4, 6), b * CFrame.new(0, 70, z), rgb(245, 245, 248), M.Concrete)
	end
	local night = X.Th.Night
	for side = -1, 1, 2 do
		local pts = {}
		for k = 0, 16 do
			local z = -350 + k * 700 / 16
			local sag
			if math.abs(z) <= 170 then
				sag = 116 - (1 - (z / 170) ^ 2) * 70
			else
				sag = 116 - (math.abs(z) - 170) / 180 * 72
			end
			pts[k] = (b * CFrame.new(side * 10, sag, z)).Position
		end
		for k = 0, 15 do
			local cable = beam(
				pts[k],
				pts[k + 1],
				1.2,
				if night then Color3.fromHSV(k / 16, 0.6, 1) else rgb(230, 232, 236),
				if night then M.Neon else M.Metal
			)
			local _ = cable
			if k % 2 == 0 then
				local p = pts[k]
				box(
					Vector3.new(0.3, p.Y - deckY, 0.3),
					CFrame.new(p.X, (p.Y + deckY) / 2, p.Z),
					rgb(200, 200, 205),
					M.Metal
				)
			end
		end
	end
	for k = -3, 3 do
		if k ~= 0 then
			box(Vector3.new(20, deckY, 16), b * CFrame.new(0, deckY / 2, k * 100), rgb(210, 210, 214), M.Concrete)
		end
	end
end)

named("neon_alley", "Neon alley")
def("neon_alley", 60, "near", function(cf)
	box(Vector3.new(14, 0.3, 110), cf * CFrame.new(0, 0.15, 0), rgb(60, 62, 70), M.Asphalt)
	local words = { "RAMEN", "ARCADE", "SUSHI", "KARAOKE", "HOTEL", "GAMES", "CAFE", "IZAKAYA", "MANGA", "BAR" }
	for side = -1, 1, 2 do
		for k = -4, 4 do
			local b = cf * CFrame.new(side * 16, 0, k * 12) * CFrame.Angles(0, side * PI / 2, 0)
			local h = rnd(24, 44)
			box(
				Vector3.new(11.5, h, 14),
				b * CFrame.new(0, h / 2, 0),
				pick({ rgb(70, 72, 82), rgb(90, 86, 84), rgb(110, 100, 96), rgb(60, 64, 74) }),
				M.Concrete
			)
			for m = 0, 2 do
				local col = Color3.fromHSV(rnd(0, 1), 0.8, 1)
				local sgn =
					box(Vector3.new(0.6, rnd(6, 12), 2.4), b * CFrame.new(-6, 8 + m * 10, rnd(-4, 4)), col, M.Neon)
				if m == 0 then
					sign(
						sgn,
						Enum.NormalId.Left,
						words[X.Rng:NextInteger(1, #words)],
						rgb(255, 255, 255),
						col:Lerp(Color3.new(0, 0, 0), 0.5)
					)
				end
			end
			box(Vector3.new(0.6, 3, 11), b * CFrame.new(-6.4, 3.5, 0), rgb(255, 230, 190), M.Neon)
		end
	end
	for k = 0, 6 do
		box(Vector3.new(1.4, 1.6, 1.4), cf * CFrame.new(rnd(-4, 4), 11, -40 + k * 13), rgb(255, 60, 50), M.Neon)
	end
	local glow = box(Vector3.new(2, 2, 2), cf * CFrame.new(0, 14, 0), rgb(255, 80, 200), M.Neon)
	light(glow, rgb(255, 90, 210), 50, 2)
	if X.Q >= 3 then
		for _ = 1, 8 do
			person(cf * CFrame.new(rnd(-5, 5), 0.3, rnd(-50, 50)) * CFrame.Angles(0, rnd(0, 6), 0))
		end
	end
end)

---------------------------------------------------------------------------
-- Scotland
---------------------------------------------------------------------------
named("highland_castle", "Castle on the crag")
def("highland_castle", 90, "near", function(cf)
	local rock, stone = rgb(95, 98, 100), rgb(150, 145, 135)
	ellipsoid(Vector3.new(150, 70, 130), cf * CFrame.new(0, 0, 0), rock, M.Rock)
	box(Vector3.new(90, 30, 70), cf * CFrame.new(0, 15, 0), rock, M.Rock)
	local top = cf * CFrame.new(0, 30, 0)
	box(Vector3.new(34, 46, 26), top * CFrame.new(-8, 23, 0), stone, M.Cobblestone)
	wedge(Vector3.new(34, 12, 13), top * CFrame.new(-8, 52, -6.5), rgb(70, 72, 80), M.Slate)
	wedge(Vector3.new(34, 12, 13), top * CFrame.new(-8, 52, 6.5) * CFrame.Angles(0, PI, 0), rgb(70, 72, 80), M.Slate)
	for _, o in { { -25, -13 }, { 9, -13 }, { -25, 13 }, { 9, 13 } } do
		vcyl(8, 6, top * CFrame.new(o[1], 48, o[2]), stone, M.Cobblestone)
		cone(6, 7, 1, 3, top * CFrame.new(o[1], 52, o[2]), rgb(70, 72, 80), M.Slate)
	end
	box(Vector3.new(70, 12, 4), top * CFrame.new(10, 6, -30), stone, M.Cobblestone)
	box(Vector3.new(4, 12, 60), top * CFrame.new(44, 6, 0), stone, M.Cobblestone)
	vcyl(26, 14, top * CFrame.new(44, 13, -30), stone, M.Cobblestone)
	for k = 0, 5 do
		box(
			Vector3.new(1.4, 3, 0.4),
			top * CFrame.new(-20 + k * 5, 30, -13.2),
			if X.Th.Night then rgb(255, 210, 140) else rgb(40, 40, 44),
			if X.Th.Night then M.Neon else M.SmoothPlastic
		)
	end
	box(Vector3.new(0.4, 12, 0.4), top * CFrame.new(-8, 64, 0), rgb(200, 200, 200), M.Metal)
	box(Vector3.new(0.2, 4, 7), top * CFrame.new(-8, 68, 3.6), rgb(30, 60, 160), M.Fabric)
end)

named("loch_monster", "Something in the loch...")
def("loch_monster", 0, "global", function(_, ctx)
	local lake = ctx.Lake
	if not lake then
		return
	end
	local green = rgb(50, 80, 60)
	local base = CFrame.new(0, -1100, 0)
	local parts = {
		box(Vector3.new(2.4, 16, 2.4), base * CFrame.new(0, 7, -12) * CFrame.Angles(math.rad(-15), 0, 0), green),
		box(Vector3.new(3.4, 3, 6), base * CFrame.new(0, 15.5, -15), green),
		ellipsoid(Vector3.new(6, 6, 12), base * CFrame.new(0, 0.5, 0), green),
		ellipsoid(Vector3.new(5, 5, 9), base * CFrame.new(0, 0.2, 12), green),
		box(Vector3.new(1.4, 1.4, 8), base * CFrame.new(0, -0.5, 20), green),
	}
	local centre = lake.Pos + Vector3.new(0, -1.2, 0)
	local r = lake.R * 0.45
	mover(parts, base, function(now)
		local a = now * 0.05
		local dive = math.clamp(math.sin(now * 0.12) * 3, -1, 1)
		local p = centre + Vector3.new(math.cos(a) * r, (dive - 1) * 8, math.sin(a) * r)
		return CFrame.lookAt(p, centre + Vector3.new(math.cos(a + 0.05) * r, p.Y - centre.Y, math.sin(a + 0.05) * r))
	end)
end)

named("standing_stones", "Standing stones")
def("standing_stones", 40, "near", function(cf)
	for k = 0, 11 do
		local a = k / 12 * PI * 2
		local h = rnd(8, 14)
		box(
			Vector3.new(3.4, h, 2.2),
			cf
				* CFrame.Angles(0, a, 0)
				* CFrame.new(0, h / 2 - 0.5, -24)
				* CFrame.Angles(rnd(-0.08, 0.08), 0, rnd(-0.08, 0.08)),
			rgb(120, 118, 112):Lerp(rgb(90, 100, 90), rnd(0, 0.5)),
			M.Slate
		)
	end
	box(Vector3.new(6, 2, 3), cf * CFrame.new(0, 1, 0), rgb(110, 108, 104), M.Slate)
end)

named("highland_cows", "Highland cattle")
def("highland_cows", 55, "near", function(cf)
	for k = 0, 13 do
		local a = k / 14 * PI * 2
		local p = cf * CFrame.new(math.cos(a) * 40, 0, math.sin(a) * 32)
		box(Vector3.new(3, 3, 3), p * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, a, 0), rgb(110, 108, 100), M.Slate)
	end
	for _ = 1, 7 do
		local ccf = cf * CFrame.new(rnd(-28, 28), 0, rnd(-20, 20)) * CFrame.Angles(0, rnd(0, 6.28), 0)
		local shag = pick({ rgb(190, 100, 45), rgb(170, 85, 40), rgb(210, 130, 60), rgb(80, 60, 50) })
		animal(
			ccf,
			1.15,
			shag,
			{ horns = rgb(235, 225, 200), hornSpan = 2.6, legs = 1.8, len = 5, width = 2.8, height = 2.8 }
		)
		box(Vector3.new(2.2, 1.2, 1), ccf * CFrame.new(0, 4.4, -3.6), shag:Lerp(Color3.new(1, 1, 1), 0.1), M.Fabric)
	end
end)

---------------------------------------------------------------------------
-- Building a circuit's landmarks
---------------------------------------------------------------------------
-- ctx: { P, F, Th, Rng, Q, Text, Mover, Lights, T, Pos, Occ, Clear, Barrier, Cx, Cz,
--        Span, SeaZ, Bounds, OpenSpot(r, infield) -> Vector3?, FarSpot(r) -> Vector3?,
--        ShoreSpot(r) -> Vector3?, SeaSpot(r) -> Vector3?, Face(pos) -> CFrame, Reserve(pos, r) }
-- Returns the display names of the landmarks that were built, and where they stand
-- ({ Name, Pos, R, Place }) so the circuit intro can fly past them.
function Landmarks.Build(ctx, list: { string }): ({ string }, { any })
	X = ctx
	local built = {}
	local spots = {}
	for _, name in list do
		local d = Defs[name]
		if d then
			local pos = nil
			if d.Place == "far" then
				pos = ctx.FarSpot(d.R)
			elseif d.Place == "sea" then
				pos = ctx.SeaSpot(d.R)
			elseif d.Place == "shore" then
				pos = ctx.ShoreSpot(d.R)
			elseif d.Place == "global" or d.Place == "track" then
				pos = Vector3.new(ctx.Cx, 0, ctx.Cz)
			else
				pos = ctx.OpenSpot(d.R, d.Place == "infield")
			end
			if pos then
				local cf
				if d.Place == "shore" or d.Place == "sea" then
					cf = CFrame.lookAt(pos, pos - Vector3.new(0, 0, 1))
				else
					cf = ctx.Face(pos)
				end
				local ok, err = pcall(d.Build, cf, ctx)
				if not ok then
					warn("GoTrack landmark " .. name .. " failed: " .. tostring(err))
				else
					if d.Place ~= "global" and d.Place ~= "track" and d.R > 0 then
						ctx.Reserve(pos, d.R)
					end
					table.insert(built, Landmarks.Names[name] or name)
					if d.Place ~= "global" and d.Place ~= "track" then
						table.insert(
							spots,
							{ Name = Landmarks.Names[name] or name, Pos = pos, R = d.R, Place = d.Place }
						)
					end
				end
			end
		end
	end
	return built, spots
end

-- Sky and water traffic for a circuit
function Landmarks.BuildLife(ctx, list: { string })
	X = ctx
	for _, name in list do
		local fn = Life[name]
		if fn then
			local ok, err = pcall(fn, ctx)
			if not ok then
				warn("GoTrack life " .. name .. " failed: " .. tostring(err))
			end
		end
	end
end

return Landmarks
