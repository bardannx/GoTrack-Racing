--!nonstrict
-- Fills the land around a circuit out to the horizon, so no map has empty grass (called
-- by CircuitBuilder.Build after the landmarks, districts and fields):
--  * city   - a grid of blocks and streets out to the horizon: one or two downtowns of
--             skyscrapers fading into midrises, apartments, lofts, malls and parks, with
--             traffic on the far streets
--  * town   - suburbs (streets lined with houses, gardens and trees), a town centre with
--             midrises and shops, parks
--  * rural  - villages (houses round a church and a green) and forests between the fields
--  * sparse - rock fields, canyon spires, palm groves, snowy forests and hamlets (by theme)
-- With the Blender world meshes imported (WorldMeshes) every building, tree and car is a
-- mesh design (a few MeshParts); without them it uses cheap 2-4 part stand-ins. A part
-- budget per Graphics Quality keeps phones smooth; the nearest land fills first.

local Arch = require(script.Parent.Architecture)

local City = {}

-- extra parts this may add, by quality 1..4
local BUDGET = { 500, 1800, 5000, 9000 }
City.Budget = BUDGET

-- Shorthand for the colour tables.
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Random entry from a list, using the circuit's seeded random.
local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

local M = Enum.Material
local ROAD = rgb(58, 60, 66)
local PAVE = rgb(176, 174, 168)
local WARM = rgb(255, 222, 160)
local GLASS =
	{ rgb(80, 120, 160), rgb(110, 150, 180), rgb(70, 95, 120), rgb(120, 160, 175), rgb(90, 110, 150), rgb(60, 80, 100) }

-- skyscraper styles per circuit (default: all of them)
local TOWERS_ALL = {
	"tower_glass",
	"tower_deco",
	"tower_twist",
	"tower_round",
	"tower_blade",
	"tower_twin",
	"tower_stack",
	"tower_resi",
}
local TOWER_STYLE = {
	dragon = { "tower_twist", "tower_blade", "tower_glass", "tower_round", "tower_twin", "tower_stack" },
	neon = { "tower_glass", "tower_round", "tower_stack", "tower_blade", "tower_twist", "tower_twin" },
	vegas = { "tower_glass", "tower_round", "tower_stack", "tower_blade", "tower_resi" },
	corniche = { "tower_blade", "tower_twin", "tower_twist", "tower_round", "tower_glass" },
	capital = { "tower_deco", "tower_glass", "tower_resi", "tower_stack", "tower_deco" },
	harbor = { "tower_resi", "tower_resi", "tower_round", "tower_glass" },
	castle = { "tower_twist", "tower_glass", "tower_resi", "tower_blade" },
	bay = { "tower_glass", "tower_twin", "tower_round", "tower_blade", "tower_stack" },
}
local MIDS = { "mid_office", "mid_apart", "mid_euro", "mid_loft", "mid_apart" }
local WARM_MIDS = { "mid_euro", "mid_apart", "mid_euro" }
local HOUSES = { "house_gable", "house_hip", "house_modern", "house_gable", "house_hip" }
local WARM_HOUSES = { "house_villa", "house_villa", "house_hip" }
local WARM_THEMES =
	{ harbor = true, mediterranean = true, castle = true, temple = true, valley = true, marina = true, aztec = true }

-- fast approximate distance from (x, z) to the track centre line
local function trackDistance(t)
	local step = math.max(1, t.N // 300)
	local xs, zs = {}, {}
	for i = 1, t.N, step do
		table.insert(xs, t.X[i])
		table.insert(zs, t.Z[i])
	end
	return function(x: number, z: number): number
		local best = math.huge
		for k = 1, #xs do
			local dx, dz = xs[k] - x, zs[k] - z
			local d = dx * dx + dz * dz
			if d < best then
				best = d
			end
		end
		return math.sqrt(best)
	end
end

---------------------------------------------------------------------------
-- Stand-ins (parts) for when the world meshes aren't imported
---------------------------------------------------------------------------
local function cheapTower(ctx, f, cf, w, d, h, rng)
	local P, th = ctx.P, ctx.Th
	local glass = pick(rng, GLASS)
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), glass, M.Glass).Reflectance = 0.15
	P(
		f,
		Vector3.new(w + 0.8, 3, d + 0.8),
		cf * CFrame.new(0, h * 0.62, 0),
		glass:Lerp(rgb(235, 238, 244), 0.6),
		M.Metal
	)
	P(f, Vector3.new(w * 0.7, 10, d * 0.7), cf * CFrame.new(0, h + 5, 0), rgb(220, 224, 230), M.Metal)
	if th.Night then
		P(f, Vector3.new(w + 0.4, h * 0.3, d + 0.4), cf * CFrame.new(0, h * 0.3, 0), WARM:Lerp(glass, 0.35), M.Neon)
	end
end

-- A 3-4 part midrise for when the meshes aren't imported (walls, window band, roof).
local function cheapMid(ctx, f, cf, w, d, h, rng)
	local P, th = ctx.P, ctx.Th
	local wall = Arch.WallColor(rng, th)
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), wall, M.Concrete)
	local lit = th.Night and rng:NextNumber() < 0.7
	P(
		f,
		Vector3.new(w + 0.3, h * 0.55, d + 0.3),
		cf * CFrame.new(0, h * 0.52, 0),
		if lit then WARM else rgb(70, 90, 115),
		if lit then M.Neon else M.Glass
	)
	P(f, Vector3.new(w + 0.8, 1, d + 0.8), cf * CFrame.new(0, h + 0.5, 0), wall:Lerp(rgb(0, 0, 0), 0.2), M.Concrete)
end

-- A 3-4 part house for when the meshes aren't imported.
local function cheapHouse(ctx, f, cf, rng, warm)
	local P, th = ctx.P, ctx.Th
	local w, d, h = rng:NextNumber(14, 18), rng:NextNumber(11, 14), rng:NextNumber(7, 10)
	local wall = Arch.WallColor(rng, th)
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), wall, M.Plaster)
	local roof = if warm
		then rgb(196, 96, 60)
		else pick(rng, { rgb(78, 82, 92), rgb(150, 60, 46), rgb(116, 80, 60), rgb(70, 96, 84) })
	P(
		f,
		Vector3.new(w + 1, 3.6, d / 2 + 0.6),
		cf * CFrame.new(0, h + 1.8, -d / 4 - 0.15),
		roof,
		M.Slate,
		nil,
		false,
		nil,
		"WedgePart"
	)
	P(
		f,
		Vector3.new(w + 1, 3.6, d / 2 + 0.6),
		cf * CFrame.new(0, h + 1.8, d / 4 + 0.15) * CFrame.Angles(0, math.pi, 0),
		roof,
		M.Slate,
		nil,
		false,
		nil,
		"WedgePart"
	)
	if th.Night and rng:NextNumber() < 0.6 then
		P(f, Vector3.new(3, 2.4, 0.3), cf * CFrame.new(-w / 4, h * 0.6, -d / 2 - 0.1), WARM, M.Neon)
	end
end

---------------------------------------------------------------------------
-- Placement helpers
---------------------------------------------------------------------------
-- a mesh design with the country's colours; false when the meshes aren't imported
local function meshBuilding(ctx, design, cf, rng, k, hMul)
	if not ctx.Meshes then
		return false
	end
	local tower = string.sub(design, 1, 5) == "tower"
	local ky = k * (hMul or 1)
	local lit = if ctx.Night then rng:NextInteger(if tower then 1 else 0, 2) else 0
	return ctx.Mesh(design, ctx.Scenery, cf, {
		Scale = Vector3.new(k, ky, k),
		Paint = Arch.MeshPaint(design, rng, ctx.Th),
		Night = ctx.Night,
		Lit = lit,
		Shadow = tower and ctx.Q >= 3,
	}) ~= nil
end

-- A skyscraper: a mesh design from `style`, or a cheap stand-in.
local function tower(ctx, cf, rng, hMul, style)
	local design = pick(rng, style)
	if not meshBuilding(ctx, design, cf, rng, rng:NextNumber(0.85, 1.1), hMul) then
		cheapTower(ctx, ctx.Scenery, cf, rng:NextNumber(26, 36), rng:NextNumber(26, 36), 250 * hMul, rng)
	end
end

-- The circuit's own architecture (pagodas, wind towers, chalets, colourful houses...)
-- mixed into the fill so every map looks like its country. Generic types are left out.
local GENERIC = {
	office_tower = true,
	glass_midrise = true,
	apartment = true,
	hotel_block = true,
	suburban_house = true,
	warehouse = true,
	shop_row = true,
	parking_garage = true,
	gas_station = true,
	twisted_tower = true,
	spire_tower = true,
	beach_condo = true,
	oil_pump = true,
	wind_turbine = true,
	water_tower = true,
	hangar = true,
	geothermal = true,
	lighthouse = true,
	casino_hotel = true,
	pyramid_hotel = true,
	skydeck_hotel = true,
	flame_tower = true,
	torii = true,
}

-- One of the theme's own buildings (a pagoda, a castle house...) if one fits in `maxW`.
local function localBuilding(ctx, cf, rng, maxW: number): boolean
	local list = ctx.LocalArch
	if not list or #list == 0 then
		return false
	end
	for _ = 1, 4 do
		local name = list[rng:NextInteger(1, #list)]
		local w = Arch.Footprint(name)
		if w <= maxW then
			Arch.Build(name, ctx.Scenery, cf, rng, ctx.Th, ctx.P)
			return true
		end
	end
	return false
end

-- a few of the circuit's own props (lanterns, tulips, cacti, sunflowers, its trees...)
local function themeProps(ctx, cf: CFrame, rng, n: number, spread: number)
	local list = ctx.ThemeProps
	if not list or #list == 0 then
		return
	end
	for _ = 1, n do
		local name = list[rng:NextInteger(1, #list)]
		ctx.Prop(
			name,
			ctx.Scenery,
			cf * CFrame.new(rng:NextNumber(-spread, spread), 0, rng:NextNumber(-spread, spread)),
			rng:NextNumber(0.8, 1.3),
			ctx.Th
		)
	end
end

-- A midrise block, sometimes swapped for a local building.
local function midrise(ctx, cf, rng, warm)
	if rng:NextNumber() < (ctx.LocalShare or 0) * 0.6 and localBuilding(ctx, cf, rng, 58) then
		return
	end
	local design = pick(rng, if warm then WARM_MIDS else MIDS)
	if not meshBuilding(ctx, design, cf, rng, rng:NextNumber(0.9, 1.15), rng:NextNumber(0.8, 1.35)) then
		cheapMid(ctx, ctx.Scenery, cf, rng:NextNumber(26, 36), rng:NextNumber(20, 28), rng:NextNumber(26, 60), rng)
	end
end

-- A house, sometimes swapped for a local building.
local function house(ctx, cf, rng, warm)
	if rng:NextNumber() < (ctx.LocalShare or 0) and localBuilding(ctx, cf, rng, 36) then
		return
	end
	local design = pick(rng, if warm then WARM_HOUSES else HOUSES)
	if not meshBuilding(ctx, design, cf, rng, rng:NextNumber(0.85, 1.05), rng:NextNumber(0.9, 1.1)) then
		cheapHouse(ctx, ctx.Scenery, cf, rng, warm)
	end
end

-- One of the theme's trees.
local function tree(ctx, cf, rng, s)
	if ctx.Tree then
		ctx.Tree(ctx.Scenery, cf, s or rng:NextNumber(0.8, 1.2))
	end
end

-- a road strip between two points (flat on the ground)
local function road(ctx, a: Vector3, b: Vector3, width: number, y: number)
	local len = (b - a).Magnitude
	if len < 1 then
		return
	end
	ctx.P(
		ctx.Scenery,
		Vector3.new(width, 0.3, len),
		CFrame.lookAt((a + b) / 2 + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0)),
		ROAD,
		M.Asphalt
	)
end

-- Whether a point is inside the area the cityscape fills.
local function inside(ctx, x: number, z: number): boolean
	local dx, dz = x - ctx.Cx, z - ctx.Cz
	return dx * dx + dz * dz < ctx.FillR * ctx.FillR
end

-- Grid of candidate cells around the circuit, `minD` to `maxD` studs from the track,
-- nearest the track first so the view from the road fills before the far land.
local function cells(ctx, pitch: number, minD: number, maxD: number, dist)
	local b, rng = ctx.Bounds, ctx.Rng
	local reach = maxD
	local ox, oz = rng:NextNumber(0, pitch), rng:NextNumber(0, pitch)
	local out = {}
	for gx = math.floor((b[1] - reach - ox) / pitch), math.ceil((b[2] + reach - ox) / pitch) do
		for gz = math.floor((b[3] - reach - oz) / pitch), math.ceil((b[4] + reach - oz) / pitch) do
			local x, z = ox + gx * pitch, oz + gz * pitch
			local d = if inside(ctx, x, z) then dist(x, z) else math.huge
			if d > minD and d < maxD then
				table.insert(out, { gx, gz, x, z, d + rng:NextNumber(0, pitch * 1.5) })
			end
		end
	end
	table.sort(out, function(a, c)
		return a[5] < c[5]
	end)
	return out
end

---------------------------------------------------------------------------
-- Construction site: a half-built tower and a tower crane slowly swinging its jib
---------------------------------------------------------------------------
local function construction(ctx, cf: CFrame, rng)
	local P, f = ctx.P, ctx.Scenery
	local conc = rgb(176, 176, 172)
	local h = rng:NextInteger(5, 11) * 10
	P(f, Vector3.new(12, h, 12), cf * CFrame.new(0, h / 2, 0), conc, M.Concrete)
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			P(f, Vector3.new(1.6, h, 1.6), cf * CFrame.new(x * 15, h / 2, z * 15), conc, M.Concrete)
		end
	end
	for y = 10, h, 20 do
		P(f, Vector3.new(32, 1, 32), cf * CFrame.new(0, y, 0), conc:Lerp(rgb(255, 255, 255), 0.15), M.Concrete)
	end
	P(f, Vector3.new(34, 6, 0.4), cf * CFrame.new(0, 3, -17.5), rgb(40, 110, 200), M.Fabric)
	-- the crane: lattice mast, then cab + jib + counter-jib that rotate together
	local yellow = rgb(245, 190, 30)
	local mastH = h + 50
	local base = cf * CFrame.new(20, 0, 20)
	P(f, Vector3.new(3, mastH, 3), base * CFrame.new(0, mastH / 2, 0), yellow, M.DiamondPlate)
	local top = base * CFrame.new(0, mastH, 0)
	local parts = {
		P(f, Vector3.new(4, 4, 4), top * CFrame.new(0, 2, 0), yellow, M.Metal),
		P(f, Vector3.new(2.4, 2.4, 70), top * CFrame.new(0, 5, -33), yellow, M.DiamondPlate),
		P(f, Vector3.new(2.4, 2.4, 22), top * CFrame.new(0, 5, 13), yellow, M.DiamondPlate),
		P(f, Vector3.new(5, 4, 6), top * CFrame.new(0, 3, 21), rgb(120, 120, 124), M.Concrete),
		P(f, Vector3.new(0.3, 26, 0.3), top * CFrame.new(0, -8, -52), rgb(40, 40, 44), M.Metal),
		P(f, Vector3.new(3, 2, 3), top * CFrame.new(0, -22, -52), rgb(200, 60, 40), M.Metal),
	}
	if ctx.Night then
		table.insert(parts, P(f, Vector3.new(1, 1, 1), top * CFrame.new(0, 7, -67), rgb(255, 40, 40), M.Neon))
	end
	local speed = rng:NextNumber(0.05, 0.12) * (if rng:NextNumber() < 0.5 then 1 else -1)
	local phase = rng:NextNumber(0, math.pi * 2)
	ctx.Mover(parts, top, function(now)
		return top * CFrame.Angles(0, phase + math.sin(now * speed) * 1.6, 0)
	end)
end

-- Sports ground: a pitch with lines, goals and a few players running about
local function sportsGround(ctx, cf: CFrame, rng)
	local P, f = ctx.P, ctx.Scenery
	local white = rgb(245, 245, 245)
	P(f, Vector3.new(90, 0.4, 60), cf * CFrame.new(0, 0.2, 0), rgb(76, 158, 64), M.Grass)
	for _, s in { { 88, 0.5 }, { 0.5, 58 } } do
		P(
			f,
			Vector3.new(s[1], 0.06, s[2]),
			cf * CFrame.new(0, 0.43, if s[1] > 1 then 29 else 0),
			white,
			M.SmoothPlastic
		)
		if s[1] > 1 then
			P(f, Vector3.new(s[1], 0.06, s[2]), cf * CFrame.new(0, 0.43, -29), white, M.SmoothPlastic)
		end
	end
	for side = -1, 1, 2 do
		P(f, Vector3.new(0.5, 0.06, 58), cf * CFrame.new(side * 44, 0.43, 0), white, M.SmoothPlastic)
		P(f, Vector3.new(0.6, 5, 12), cf * CFrame.new(side * 45, 2.5, 0), white, M.Metal).Transparency = 0.3
	end
	local kits = { rgb(220, 40, 40), rgb(40, 90, 200) }
	for k = 1, if ctx.Q >= 3 then 8 else 4 do
		local team = kits[k % 2 + 1]
		local base = CFrame.new(0, -300, 0)
		local parts = {
			P(f, Vector3.new(1.1, 2.1, 0.6), base * CFrame.new(0, 1.05, 0), rgb(245, 245, 245), M.Fabric),
			P(f, Vector3.new(1.35, 1.8, 0.75), base * CFrame.new(0, 3, 0), team, M.Fabric),
			P(
				f,
				Vector3.new(0.9, 0.9, 0.9),
				base * CFrame.new(0, 4.35, 0),
				rgb(224, 172, 105),
				M.SmoothPlastic,
				nil,
				false,
				Enum.PartType.Ball
			),
		}
		local cx, cz = rng:NextNumber(-30, 30), rng:NextNumber(-18, 18)
		local rx, rz = rng:NextNumber(6, 14), rng:NextNumber(4, 10)
		local w = rng:NextNumber(0.3, 0.7)
		local phase = rng:NextNumber(0, 6.28)
		ctx.Mover(parts, base, function(now)
			local a = phase + now * w
			local p = cf
				* Vector3.new(
					cx + math.cos(a) * rx,
					0.45 + math.abs(math.sin(now * 7 + phase)) * 0.2,
					cz + math.sin(a * 1.3) * rz
				)
			local d = cf:VectorToWorldSpace(Vector3.new(-math.sin(a) * rx, 0, math.cos(a * 1.3) * rz * 1.3))
			return CFrame.lookAt(p, p + (if d.Magnitude > 0.01 then d else Vector3.new(0, 0, -1)))
		end)
	end
end

---------------------------------------------------------------------------
-- City: blocks out to the horizon, with downtowns
---------------------------------------------------------------------------
local function city(ctx, over, dist, maxD)
	local rng, P, f, th = ctx.Rng, ctx.P, ctx.Scenery, ctx.Th
	local pitch = 150
	local slab = 124
	local style = TOWER_STYLE[th.Key] or TOWERS_ALL
	local warm = WARM_THEMES[th.Key]
	-- one or two downtowns somewhere in the fill ring
	local cbd = {}
	for _ = 1, 40 do
		if #cbd >= 2 then
			break
		end
		local c = ctx.OpenSpot(60)
		if c and dist(c.X, c.Z) > 260 then
			table.insert(cbd, c)
		end
	end
	local function downtown(x, z): number
		local best = 0
		for _, c in cbd do
			local d = (Vector3.new(x, 0, z) - c).Magnitude
			best = math.max(best, math.exp(-(d / 420) ^ 2))
		end
		return best
	end
	local placed, streets = {}, {}
	local count = 0
	local cranes = ({ 0, 2, 5, 8 })[ctx.Q]
	for _, c in cells(ctx, pitch, 120, maxD, dist) do
		if over() then
			break
		end
		local gx, gz, x, z = c[1], c[2], c[3], c[4]
		local r = slab * 0.72
		if ctx.Clear(x, z, r + ctx.Barrier + 6) and ctx.Occ.free(x, z, r) then
			ctx.Occ.add(x, z, r)
			placed[gx .. ":" .. gz] = true
			count += 1
			local centre = CFrame.new(x, 0, z)
			P(f, Vector3.new(slab, 0.5, slab), centre * CFrame.new(0, 0.25, 0), PAVE, M.Pavement)
			table.insert(streets, { gx, gz, x, z })
			local dt = downtown(x, z)
			local roll = rng:NextNumber()
			if roll < 0.025 and ctx.Q >= 2 then
				sportsGround(
					ctx,
					centre * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, rng:NextInteger(0, 1) * math.pi / 2, 0),
					rng
				)
			elseif roll < 0.07 then
				-- park
				P(
					f,
					Vector3.new(slab - 8, 0.3, slab - 8),
					centre * CFrame.new(0, 0.6, 0),
					th.Ground:Lerp(rgb(90, 160, 70), 0.5),
					M.Grass
				)
				for _ = 1, rng:NextInteger(5, 9) do
					tree(ctx, centre * CFrame.new(rng:NextNumber(-50, 50), 0.7, rng:NextNumber(-50, 50)), rng)
				end
				themeProps(ctx, centre * CFrame.new(0, 0.7, 0), rng, rng:NextInteger(2, 5), 48)
			elseif roll < 0.11 and dt < 0.3 then
				if
					not meshBuilding(
						ctx,
						"mall",
						centre * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, rng:NextInteger(0, 3) * math.pi / 2, 0),
						rng,
						1.3,
						1
					)
				then
					cheapMid(ctx, f, centre * CFrame.new(0, 0.5, 0), 90, 70, 18, rng)
				end
			else
				-- four lots, towers where the downtown is
				for lx = -1, 1, 2 do
					for lz = -1, 1, 2 do
						if rng:NextNumber() < 0.92 then
							local lcf = centre
								* CFrame.new(lx * slab / 4, 0.5, lz * slab / 4)
								* CFrame.Angles(0, (if lz < 0 then 0 else math.pi) + rng:NextInteger(-1, 1) * 0.02, 0)
							if cranes > 0 and dt > 0.15 and rng:NextNumber() < 0.06 then
								cranes -= 1
								construction(ctx, lcf, rng)
							elseif rng:NextNumber() < 0.12 + dt * 0.8 then
								tower(ctx, lcf, rng, rng:NextNumber(0.45, 0.75) + dt * rng:NextNumber(0.3, 0.9), style)
							else
								midrise(ctx, lcf, rng, warm)
							end
						end
					end
				end
			end
		end
	end
	-- streets on the -X / -Z side of every block (+X / +Z where no neighbour)
	for _, s in streets do
		local gx, gz, x, z = s[1], s[2], s[3], s[4]
		local h = pitch / 2
		road(ctx, Vector3.new(x - h, 0, z - h), Vector3.new(x + h, 0, z - h), 24, 0.12)
		road(ctx, Vector3.new(x - h, 0, z - h), Vector3.new(x - h, 0, z + h), 24, 0.18)
		if not placed[(gx + 1) .. ":" .. gz] then
			road(ctx, Vector3.new(x + h, 0, z - h), Vector3.new(x + h, 0, z + h), 24, 0.18)
		end
		if not placed[gx .. ":" .. (gz + 1)] then
			road(ctx, Vector3.new(x - h, 0, z + h), Vector3.new(x + h, 0, z + h), 24, 0.12)
		end
	end
	return count, streets, pitch
end

---------------------------------------------------------------------------
-- Town: suburbs round a small centre
---------------------------------------------------------------------------
local function town(ctx, over, dist, maxD)
	local rng, th = ctx.Rng, ctx.Th
	local pitch = 118
	local warm = WARM_THEMES[th.Key]
	local centreSpot = ctx.OpenSpot(60)
	local placed, streets = {}, {}
	local count = 0
	for _, c in cells(ctx, pitch, 110, maxD, dist) do
		if over() then
			break
		end
		local gx, gz, x, z = c[1], c[2], c[3], c[4]
		local r = pitch * 0.5
		if ctx.Clear(x, z, r + ctx.Barrier + 6) and ctx.Occ.free(x, z, r) then
			ctx.Occ.add(x, z, r)
			placed[gx .. ":" .. gz] = true
			count += 1
			table.insert(streets, { gx, gz, x, z })
			local centre = CFrame.new(x, 0, z)
			local core = if centreSpot then math.exp(-((Vector3.new(x, 0, z) - centreSpot).Magnitude / 260) ^ 2) else 0
			local roll = rng:NextNumber()
			if roll < 0.04 and ctx.Q >= 2 then
				sportsGround(ctx, centre * CFrame.Angles(0, rng:NextInteger(0, 1) * math.pi / 2, 0), rng)
			elseif roll < 0.09 then
				-- park with trees
				for _ = 1, rng:NextInteger(5, 8) do
					tree(ctx, centre * CFrame.new(rng:NextNumber(-44, 44), 0, rng:NextNumber(-44, 44)), rng)
				end
				themeProps(ctx, centre, rng, rng:NextInteger(3, 6), 42)
			elseif roll < 0.09 + core * 0.7 then
				-- town centre: midrises facing the street
				for lx = -1, 1, 2 do
					midrise(ctx, centre * CFrame.new(lx * 28, 0, -22), rng, warm)
					if rng:NextNumber() < 0.6 then
						midrise(ctx, centre * CFrame.new(lx * 28, 0, 26) * CFrame.Angles(0, math.pi, 0), rng, warm)
					end
				end
			else
				-- two rows of houses with gardens, facing the streets
				for row = -1, 1, 2 do
					for k = -1, 1 do
						if rng:NextNumber() < 0.9 then
							local hcf = centre
								* CFrame.new(k * 36 + rng:NextNumber(-2, 2), 0, row * 27)
								* CFrame.Angles(0, if row < 0 then 0 else math.pi, 0)
							house(ctx, hcf, rng, warm)
							if rng:NextNumber() < 0.55 then
								tree(ctx, hcf * CFrame.new(rng:NextNumber(-14, 14), 0, 17), rng, rng:NextNumber(0.7, 1))
							end
						end
					end
				end
			end
		end
	end
	for _, s in streets do
		local gx, gz, x, z = s[1], s[2], s[3], s[4]
		local h = pitch / 2
		road(ctx, Vector3.new(x - h, 0, z - h), Vector3.new(x + h, 0, z - h), 16, 0.12)
		road(ctx, Vector3.new(x - h, 0, z - h), Vector3.new(x - h, 0, z + h), 16, 0.18)
		if not placed[(gx + 1) .. ":" .. gz] then
			road(ctx, Vector3.new(x + h, 0, z - h), Vector3.new(x + h, 0, z + h), 16, 0.18)
		end
		if not placed[gx .. ":" .. (gz + 1)] then
			road(ctx, Vector3.new(x - h, 0, z + h), Vector3.new(x + h, 0, z + h), 16, 0.12)
		end
	end
	return count, streets, pitch
end

---------------------------------------------------------------------------
-- Villages, forests, rock fields
---------------------------------------------------------------------------
local function village(ctx, at: Vector3, rng)
	local P, f, th = ctx.P, ctx.Scenery, ctx.Th
	local warm = WARM_THEMES[th.Key]
	-- crossroads through the green
	for k = 0, 1 do
		local dir = if k == 0 then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
		road(ctx, at - dir * 110, at + dir * 110, 12, 0.12 + k * 0.05)
	end
	P(
		f,
		Vector3.new(34, 0.3, 34),
		CFrame.new(at + Vector3.new(0, 0.2, 0)),
		th.Ground:Lerp(rgb(110, 180, 80), 0.4),
		M.Grass
	)
	if th.Arch.church or rng:NextNumber() < 0.6 then
		Arch.Build("church", f, CFrame.new(at + Vector3.new(0, 0, 36)) * CFrame.Angles(0, math.pi, 0), rng, th, ctx.P)
	end
	local n = rng:NextInteger(8, 14)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local d = rng:NextNumber(40, 95)
		local p = at + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		if ctx.Clear(p.X, p.Z, ctx.Barrier + 16) and ctx.Occ.free(p.X, p.Z, 9) then
			local hcf = CFrame.lookAt(p, at)
			if ctx.Meshes then
				house(ctx, hcf, rng, warm)
			else
				local name = nil
				for arch in th.Arch do
					if
						(
							arch == "cottage"
							or arch == "chalet"
							or arch == "villa"
							or arch == "japanese_house"
							or arch == "colorful_house"
							or arch == "ranch_house"
							or arch == "wind_tower_house"
						) and rng:NextNumber() < 0.6
					then
						name = arch
					end
				end
				if name then
					Arch.Build(name, f, hcf, rng, th, ctx.P)
				else
					cheapHouse(ctx, f, hcf, rng, warm)
				end
			end
			if rng:NextNumber() < 0.5 then
				tree(
					ctx,
					CFrame.new(p + (p - at).Unit * 16 + Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))),
					rng
				)
			end
		end
	end
	themeProps(ctx, CFrame.new(at), rng, rng:NextInteger(4, 8), 90)
	ctx.Occ.add(at.X, at.Z, 100)
end

-- `n` trees scattered in a circle, thicker in the middle.
local function forest(ctx, at: Vector3, radius: number, n: number, rng, propName: string?)
	for _ = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = radius * math.sqrt(rng:NextNumber())
		local x, z = at.X + math.cos(a) * d, at.Z + math.sin(a) * d
		if ctx.Clear(x, z, ctx.Barrier + 14) and ctx.Occ.free(x, z, 5) then
			local cf = CFrame.new(x, 0, z)
			if propName then
				ctx.Prop(propName, ctx.Scenery, cf, rng:NextNumber(0.8, 1.5), ctx.Th)
			else
				tree(ctx, cf, rng, rng:NextNumber(0.85, 1.45))
			end
		end
	end
	ctx.Occ.add(at.X, at.Z, radius * 0.8)
end

-- spot in the fill ring (between inner and outer distance from the track)
local function ringSpot(ctx, dist, inner, outer, r): Vector3?
	local b, rng = ctx.Bounds, ctx.Rng
	for _ = 1, 80 do
		local x = rng:NextNumber(b[1] - outer, b[2] + outer)
		local z = rng:NextNumber(b[3] - outer, b[4] + outer)
		local d = if inside(ctx, x, z) then dist(x, z) else math.huge
		if d > inner and d < outer and ctx.Clear(x, z, r + ctx.Barrier) and ctx.Occ.free(x, z, r) then
			return Vector3.new(x, 0, z)
		end
	end
	return nil
end

-- a rolling hill (the Blender mesh, or a squashed ball of turf)
local function hillAt(ctx, at: Vector3, k: number, rng)
	local th = ctx.Th
	local col = th.Ground:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0.02, 0.1))
	if ctx.Meshes then
		local placed =
			ctx.Mesh("hill", ctx.Scenery, CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), {
				Scale = Vector3.new(
					k * rng:NextNumber(0.8, 1.3),
					k * rng:NextNumber(0.7, 1.2),
					k * rng:NextNumber(0.8, 1.3)
				),
				Paint = { Base = { col, M.Grass }, Rock = { col:Lerp(rgb(120, 118, 112), 0.6), M.Rock } },
			})
		if placed then
			return
		end
	end
	local w = 900 * k
	local p = ctx.P(
		ctx.Scenery,
		Vector3.new(w, 150 * k * 2, w * 0.8),
		CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		col,
		M.Grass,
		nil,
		false,
		Enum.PartType.Ball
	)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
end

-- a pond with a reedy shore and a few trees
local function pond(ctx, at: Vector3, r: number, rng)
	local P, f, th = ctx.P, ctx.Scenery, ctx.Th
	P(
		f,
		Vector3.new(0.6, r * 2 + 10, r * 2 + 8),
		CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		th.Ground:Lerp(rgb(120, 110, 80), 0.35),
		M.Ground,
		nil,
		false,
		Enum.PartType.Cylinder
	)
	local w = P(
		f,
		Vector3.new(0.6, r * 2, r * 2 - 2),
		CFrame.new(at + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		th.Water,
		M.Glass,
		nil,
		false,
		Enum.PartType.Cylinder
	)
	w.Reflectance = 0.2
	for _ = 1, rng:NextInteger(4, 8) do
		local a = rng:NextNumber(0, math.pi * 2)
		local p = at + Vector3.new(math.cos(a), 0, math.sin(a)) * (r + rng:NextNumber(8, 20))
		if ctx.Clear(p.X, p.Z, ctx.Barrier + 12) then
			tree(ctx, CFrame.new(p), rng)
		end
	end
	ctx.Occ.add(at.X, at.Z, r + 10)
end

-- Rural land: villages, ponds, forests between the fields and rolling hills further out.
local function countryside(ctx, over, dist, maxD)
	local rng, q = ctx.Rng, ctx.Q
	local made = 0
	-- villages
	for _ = 1, ({ 1, 3, 6, 8 })[q] do
		if over() then
			break
		end
		local at = ringSpot(ctx, dist, 320, maxD * 0.8, 110)
		if at then
			village(ctx, at, rng)
			made += 1
		end
	end
	-- ponds
	for _ = 1, ({ 0, 2, 3, 4 })[q] do
		local r = rng:NextNumber(35, 80)
		local at = ringSpot(ctx, dist, 200, maxD * 0.7, r + 12)
		if at then
			pond(ctx, at, r, rng)
			made += 1
		end
	end
	-- forests: thick woods of the circuit's trees
	for _ = 1, ({ 4, 10, 22, 32 })[q] do
		if over() then
			break
		end
		local r = rng:NextNumber(60, 140)
		local at = ringSpot(ctx, dist, 160, maxD, r * 0.6)
		if at then
			forest(ctx, at, r, math.floor(r * r / 170 * math.min(1.3, ctx.Dens + 0.3)), rng)
			made += 1
		end
	end
	-- rolling hills further out
	for _ = 1, ({ 2, 4, 7, 10 })[q] do
		local k = rng:NextNumber(0.3, 0.7)
		local at = ringSpot(ctx, dist, 420, maxD + 200, 900 * k * 0.33)
		if at then
			hillAt(ctx, at, k, rng)
			ctx.Occ.add(at.X, at.Z, 900 * k * 0.33)
			made += 1
		end
	end
	return made
end

-- rock fields / groves for deserts, snow, volcanoes, canyons
local SPARSE = {
	canyon = { { "rock_spire", 2 }, { "rock", 3 }, { "cactus", 1 } },
	desertnight = { { "rock", 2 }, { "palm", 1 }, { "dune", 2 } },
	pearl = { { "rock", 1 }, { "palm", 2 }, { "dune", 2 } },
	oasis = { { "palm", 3 }, { "rock", 1 }, { "dune", 2 } },
	snow = { { "snowpine", 4 }, { "iceblock", 1 } },
	volcano = { { "lavarock", 3 }, { "palm", 2 } },
}

-- giant formations close to the track: { design, min scale, max scale }
local MONUMENTS = {
	canyon = { { "rock_spire", 2.6, 6 }, { "rock_spire", 2, 4 }, { "mtn_mesa", 0.1, 0.24 } },
	desertnight = { { "mtn_mesa", 0.08, 0.18 }, { "rock_spire", 1.6, 3 } },
	pearl = { { "mtn_mesa", 0.08, 0.16 } },
	oasis = { { "rock_spire", 1.8, 3.5 }, { "mtn_mesa", 0.08, 0.2 } },
	snow = { { "mtn_peak", 0.1, 0.2 }, { "mtn_ridge", 0.1, 0.18 } },
	volcano = { { "mtn_peak", 0.1, 0.18 } },
}

-- A giant formation near the track (rock spire, mesa or peak), coloured for the theme.
local function monument(ctx, e, at: Vector3, rng)
	local th = ctx.Th
	local design, k = e[1], rng:NextNumber(e[2], e[3])
	local sand = th.HorizonColor or rgb(205, 128, 82):Lerp(rgb(232, 175, 118), rng:NextNumber())
	local paint
	if th.Key == "snow" then
		paint = {
			Rock = { rgb(118, 126, 142), M.Rock },
			Snow = { rgb(245, 248, 255), M.Snow },
			Base = { rgb(230, 236, 245), M.Snow },
		}
	elseif th.Key == "volcano" then
		paint = {
			Rock = { rgb(58, 50, 48), M.Basalt },
			Snow = { rgb(88, 76, 72), M.Basalt },
			Base = { th.Ground, M.Ground },
		}
	else
		paint = {
			Rock = { sand, M.Sandstone },
			Band = { sand:Lerp(rgb(245, 205, 150), 0.4), M.Sandstone },
			Base = { sand:Lerp(rgb(230, 200, 150), 0.5), M.Sand },
		}
	end
	local cf = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	if
		ctx.Meshes
		and ctx.Mesh(design, ctx.Scenery, cf, {
			Scale = Vector3.new(
				k * rng:NextNumber(0.8, 1.3),
				k * rng:NextNumber(0.8, 1.4),
				k * rng:NextNumber(0.8, 1.3)
			),
			Paint = paint,
		})
	then
		return
	end
	-- stand-in: a stack of weathered blocks
	local W = (ctx.MeshSize(design) or 16) * k * 0.7
	local H = if design == "rock_spire" then 48 * k else W * 0.35
	for s = 0, 2 do
		local w = W * (1 - s * 0.22)
		ctx.P(
			ctx.Scenery,
			Vector3.new(w, H / 3 + 0.5, w * 0.85),
			cf * CFrame.new(0, H / 6 + s * H / 3, 0) * CFrame.Angles(0, s * 0.4, 0),
			paint.Rock[1]:Lerp(Color3.new(1, 1, 1), s * 0.06),
			paint.Rock[2]
		)
	end
end

local NOT_HAMLET = {
	oil_pump = true,
	wind_turbine = true,
	geothermal = true,
	water_tower = true,
	spire_tower = true,
	lighthouse = true,
}

-- Sparse land: rock fields, groves and hamlets, mixed per theme (SPARSE).
local function wilds(ctx, over, dist, maxD)
	local rng, th, q = ctx.Rng, ctx.Th, ctx.Q
	local mix = SPARSE[th.Key] or { { "rock", 2 }, { "bush", 1 } }
	local total = 0
	for _, e in mix do
		total += e[2]
	end
	local made = 0
	for _ = 1, ({ 6, 14, 28, 40 })[q] do
		if over() then
			break
		end
		local roll, name = rng:NextNumber(0, total), mix[1][1]
		for _, e in mix do
			roll -= e[2]
			if roll <= 0 then
				name = e[1]
				break
			end
		end
		local r = rng:NextNumber(50, 120)
		local at = ringSpot(ctx, dist, 140, maxD, r * 0.6)
		if at then
			forest(ctx, at, r, math.floor(r * r / (if name == "dune" then 1400 else 240)), rng, name)
			made += 1
		end
	end
	-- giant rock formations, buttes and crags
	local mons = MONUMENTS[th.Key]
	if mons then
		for _ = 1, ({ 4, 9, 16, 24 })[q] do
			if over() then
				break
			end
			local e = pick(rng, mons)
			local W = (ctx.MeshSize(e[1]) or 16) * e[3]
			local at = ringSpot(ctx, dist, 120 + W * 0.3, maxD, W * 0.35)
			if at then
				monument(ctx, e, at, rng)
				ctx.Occ.add(at.X, at.Z, W * 0.35)
				made += 1
			end
		end
	end
	-- a couple of hamlets of the local architecture
	for _ = 1, ({ 1, 2, 5, 7 })[q] do
		if over() then
			break
		end
		local at = ringSpot(ctx, dist, 260, maxD * 0.8, 70)
		if at then
			local names = {}
			for n in th.Arch do
				if Arch.Types[n] and not NOT_HAMLET[n] then
					table.insert(names, n)
				end
			end
			if #names > 0 then
				for k = 1, rng:NextInteger(4, 7) do
					local a = k / 7 * math.pi * 2
					local p = at + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(20, 55)
					if ctx.Clear(p.X, p.Z, ctx.Barrier + 20) and ctx.Occ.free(p.X, p.Z, 12) then
						Arch.Build(pick(rng, names), ctx.Scenery, CFrame.lookAt(p, at), rng, th, ctx.P)
					end
				end
				ctx.Occ.add(at.X, at.Z, 60)
				made += 1
			end
		end
	end
	return made
end

---------------------------------------------------------------------------
-- Far traffic: cars driving up and down the fill streets
---------------------------------------------------------------------------
local function traffic(ctx, streets, pitch)
	local rng, q = ctx.Rng, ctx.Q
	local want = ({ 0, 6, 14, 22 })[q]
	if want == 0 or #streets == 0 then
		return
	end
	for _ = 1, want do
		local s = streets[rng:NextInteger(1, #streets)]
		local x, z = s[3], s[4]
		local h = pitch / 2
		local alongX = rng:NextNumber() < 0.5
		local lane = if rng:NextNumber() < 0.5 then -5 else 5
		local a = if alongX then Vector3.new(x - h, 0.35, z - h + lane) else Vector3.new(x - h + lane, 0.35, z - h)
		local len = pitch * rng:NextInteger(2, 4)
		local dirV = if alongX then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
		local base = CFrame.new(0, -300, 0)
		local parts = Arch.Car(ctx.Scenery, base, Arch.CarColor(rng, ctx.Th.Layout == "city"), ctx.Night, ctx.P)
		local speed = rng:NextNumber(26, 42)
		local phase = rng:NextNumber(0, 100)
		ctx.Mover(parts, base, function(now)
			local u = ((phase + now * speed) % (len * 2))
			local fwd = u < len
			local d = if fwd then u else len * 2 - u
			local p = a + dirV * (d - len / 2)
			return CFrame.lookAt(p, p + (if fwd then dirV else -dirV))
		end)
	end
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------
-- Returns how many blocks / villages / groves were added.
function City.Fill(ctx): number
	local start = ctx.Parts()
	local budget = BUDGET[ctx.Q]
	local function over(): boolean
		return ctx.Parts() - start > budget
	end
	local dist = trackDistance(ctx.T)
	-- fill out to just inside the horizon ring
	ctx.FillR = ctx.Span / 2 + 780
	local maxD = ({ 650, 850, 1150, 1350 })[ctx.Q]
	local layout = ctx.Th.Layout
	local made = 0
	-- the country's own buildings and props, mixed into everything below
	ctx.LocalArch, ctx.ThemeProps = {}, {}
	for name, w in ctx.Th.Arch do
		if Arch.Types[name] and not GENERIC[name] then
			for _ = 1, math.max(1, math.floor(w + 0.5)) do
				table.insert(ctx.LocalArch, name)
			end
		end
	end
	for name, w in ctx.Th.Props do
		for _ = 1, math.max(1, math.floor(w + 0.5)) do
			table.insert(ctx.ThemeProps, name)
		end
	end
	ctx.LocalShare = if layout == "city" then 0.22 else 0.42
	if layout == "city" then
		local n, streets, pitch = city(ctx, over, dist, maxD)
		made += n
		traffic(ctx, streets, pitch)
	elseif layout == "town" then
		local n, streets, pitch = town(ctx, over, dist, maxD * 0.85)
		made += n
		made += countryside(ctx, over, dist, maxD)
		traffic(ctx, streets, pitch)
	elseif layout == "rural" then
		made += countryside(ctx, over, dist, maxD)
	else
		made += wilds(ctx, over, dist, maxD)
	end
	return made
end

return City
