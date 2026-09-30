--!nonstrict
-- Brings a circuit's surroundings to life (called by CircuitBuilder.Build):
--  * Trackside: spectator banks with fans, flags and umbrellas; campsites at rural
--    circuits; pavements, lamp posts and fans behind the fences of street circuits
--  * Districts: a real street grid of city blocks (pavement + kerb, asphalt streets with
--    lane dashes and zebra crossings, buildings facing the streets, shops, parks with
--    fountains, car parks, street lamps, street trees, parked cars)
--  * Fields: a patchwork of crops, ploughed land and pasture with hedges, hay bales and
--    cows around rural circuits
--  * Movers: traffic and pedestrians circling the blocks, a tractor, and a TV helicopter
--    flying laps above the track (all moved together with one BulkMoveTo per frame)
-- Every system has a part budget per Graphics Quality level (ctx.Q = 1..4).

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Track = require(Shared.Track)

local Arch = require(script.Parent.Architecture)

local Life = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

local BLOCK = 112 -- buildable square of a city block
local WALK = 6 -- pavement around it
local STREET = 30 -- road between two pavements (parking lane + driving lane each way)
local PITCH = BLOCK + WALK * 2 + STREET
local HALF = BLOCK / 2 + WALK -- block centre -> kerb
local CURB = 0.9 -- pavement height

-- extra parts each system may add, by quality 1..4
local BUDGET = {
	Trackside = { 500, 1200, 2200, 3200 },
	Districts = { 1800, 5000, 9500, 15000 },
	Fields = { 400, 1000, 1800, 2600 },
}

local NOT_IN_BLOCKS = { torii = true, oil_pump = true, wind_turbine = true, windmill = true, water_tower = true, igloo = true, lighthouse = true, castletower = true, hangar = true, geothermal = true, research_station = true, tiki_hut = true, barn = true, ranch_house = true, pagoda = true, cottage = true, chalet = true, ski_lodge = true }
local BIG = { skydeck_hotel = true, pyramid_hotel = true, flame_tower = true, casino_hotel = true }
-- generic street buildings mixed in with each country's own architecture
local FILL = {
	city = { glass_midrise = 2.5, shop_row = 1.5, parking_garage = 0.4, apartment = 1 },
	town = { suburban_house = 3, shop_row = 1, gas_station = 0.25 },
}

local SHIRTS = { rgb(220, 40, 40), rgb(40, 90, 200), rgb(250, 250, 250), rgb(30, 30, 34), rgb(255, 200, 30), rgb(40, 160, 80), rgb(255, 130, 30), rgb(150, 60, 200), rgb(0, 170, 200), rgb(240, 110, 160) }
local PANTS = { rgb(40, 55, 90), rgb(30, 30, 34), rgb(120, 110, 90), rgb(70, 70, 76), rgb(200, 190, 160) }
local SKIN = { rgb(255, 219, 172), rgb(241, 194, 125), rgb(224, 172, 105), rgb(198, 134, 66), rgb(141, 85, 36), rgb(92, 56, 30) }
local ROAD = rgb(56, 58, 64)
local PAVE = rgb(178, 176, 170)
local PAINT = rgb(236, 236, 228)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- fast approximate distance from (x, z) to the track centre line
local function trackDistance(t)
	local step = math.max(1, t.N // 360)
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

-- A standing person (legs, shirt, head); cf is on the ground, facing -Z. Returns parts.
local function person(ctx, f, cf: CFrame, rng: Random): { BasePart }
	local P = ctx.P
	return {
		P(f, Vector3.new(1.1, 2.1, 0.6), cf * CFrame.new(0, 1.05, 0), pick(rng, PANTS), Enum.Material.Fabric),
		P(f, Vector3.new(1.35, 1.8, 0.75), cf * CFrame.new(0, 3, 0), pick(rng, SHIRTS), Enum.Material.Fabric),
		P(f, Vector3.new(0.9, 0.9, 0.9), cf * CFrame.new(0, 4.35, 0), pick(rng, SKIN), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Ball),
	}
end

local function addMover(ctx, parts: { BasePart }, baseCF: CFrame, update: (number) -> CFrame)
	local offs = table.create(#parts)
	for i, p in parts do
		offs[i] = baseCF:ToObjectSpace(p.CFrame)
	end
	table.insert(ctx.Movers, { Parts = parts, Offsets = offs, Update = update })
end

-- Point on a rounded square loop (half-size r, corner radius c) around (cx, cz).
-- Returns x, z and the unit heading. dir = -1 runs the loop the other way.
local function loopPoint(cx: number, cz: number, r: number, c: number, s: number, dir: number): (number, number, number, number)
	local L = 2 * (r - c)
	local arc = math.pi * c / 2
	local seg = L + arc
	local perim = 4 * seg
	s = s % perim
	if dir < 0 then
		s = perim - s
	end
	local k = s // seg
	local u = s - k * seg
	local x, z, hx, hz
	if u < L then
		x, z = -(r - c) + u, -r
		hx, hz = 1, 0
	else
		local a = (u - L) / c
		x = (r - c) + math.sin(a) * c
		z = -(r - c) - math.cos(a) * c
		hx, hz = math.cos(a), math.sin(a)
	end
	for _ = 1, k do
		x, z = -z, x
		hx, hz = -hz, hx
	end
	if dir < 0 then
		hx, hz = -hx, -hz
	end
	return cx + x, cz + z, hx, hz
end

---------------------------------------------------------------------------
-- Trackside
---------------------------------------------------------------------------
-- grassy bank sloping up away from the barrier, packed with fans
local function buildBank(ctx, i: number, side: number, len: number)
	local t, rng, P, f, th = ctx.T, ctx.Rng, ctx.P, ctx.Scenery, ctx.Th
	local x, _, z, tx, _, tz = Track.PointAt(t, t.S[i], side * (ctx.Barrier + 6))
	local along = Vector3.new(tx, 0, tz).Unit
	local out = Vector3.new(t.RX[i], 0, t.RZ[i]) * side
	local depth, height = 30, 9
	local foot = Vector3.new(x, 0, z)
	local mid = foot + out * (depth / 2)
	-- wedge: high edge (+Z) away from the track
	P(f, Vector3.new(len, height, depth), CFrame.lookAt(mid + Vector3.new(0, height / 2, 0), mid + Vector3.new(0, height / 2, 0) - out), th.Ground:Lerp(Color3.new(0, 0, 0), 0.08), th.GroundMaterial, nil, false, nil, "WedgePart")
	-- debris fence in front
	local fence = P(f, Vector3.new(len, 7, 0.2), CFrame.lookAt(foot + Vector3.new(0, 3.5, 0) - out * 1.5, foot + Vector3.new(0, 3.5, 0) - out * 1.5 - out), rgb(90, 95, 100), Enum.Material.DiamondPlate)
	fence.Transparency = 0.7
	-- fans on four terraces
	local prob = math.clamp(0.35 + 0.35 * ctx.Dens * th.Crowd, 0.25, 0.85)
	for row = 0, 3 do
		local d = 4 + row * 6.5
		local y = height * (d / depth)
		for u = -len / 2 + 2, len / 2 - 2, 2.6 do
			if rng:NextNumber() < prob then
				local p = foot + out * (d + rng:NextNumber(-0.6, 0.6)) + along * u + Vector3.new(0, y, 0)
				local pcf = CFrame.lookAt(p, p - out)
				P(f, Vector3.new(1.35, 2.6, 0.8), pcf * CFrame.new(0, 1.3, 0), pick(rng, SHIRTS), Enum.Material.Fabric)
				P(f, Vector3.new(0.9, 0.9, 0.9), pcf * CFrame.new(0, 3.05, 0), pick(rng, SKIN), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Ball)
			end
		end
	end
	-- flags and umbrellas
	for k = 1, (if ctx.Q >= 3 then 3 else 1) do
		local d = rng:NextNumber(8, 26)
		local p = foot + out * d + along * rng:NextNumber(-len / 2 + 4, len / 2 - 4) + Vector3.new(0, height * d / depth, 0)
		P(f, Vector3.new(0.25, 9, 0.25), CFrame.new(p + Vector3.new(0, 4.5, 0)), rgb(200, 200, 205), Enum.Material.Metal)
		local flagCol = pick(rng, SHIRTS)
		P(f, Vector3.new(0.1, 2.4, 3.6), CFrame.lookAt(p + Vector3.new(0, 7.6, 0), p + Vector3.new(0, 7.6, 0) + out) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, 0, -1.8), flagCol, Enum.Material.Fabric)
		if ctx.Q >= 3 then
			local q = foot + out * rng:NextNumber(6, 26) + along * rng:NextNumber(-len / 2 + 4, len / 2 - 4)
			local qy = height * ((q - foot):Dot(out)) / depth
			P(f, Vector3.new(0.2, 5, 0.2), CFrame.new(q + Vector3.new(0, qy + 2.5, 0)), rgb(220, 220, 220), Enum.Material.Metal)
			P(f, Vector3.new(0.6, 6, 6), CFrame.new(q + Vector3.new(0, qy + 5, 0)) * CFrame.Angles(0, 0, math.pi / 2), if k % 2 == 0 then rgb(250, 250, 250) else pick(rng, SHIRTS), Enum.Material.Fabric, nil, false, Enum.PartType.Cylinder)
		end
	end
	for u = -len / 2, len / 2, len / 3 do
		local c = foot + out * (depth / 2) + along * u
		ctx.Occ.add(c.X, c.Z, len / 6 + depth / 2)
	end
end

local function banks(ctx, over)
	local t, rng = ctx.T, ctx.Rng
	local want = ({ 1, 3, 5, 7 })[ctx.Q]
	local placed = {}
	for _ = 1, 80 do
		if #placed >= want or over() then
			break
		end
		local i = rng:NextInteger(1, t.N)
		if math.abs(t.K[i]) < 1 / 500 and not t.Over[i] then
			local far = true
			for _, j in placed do
				if math.abs(Track.IndexDelta(t, i, j)) < 60 then
					far = false
				end
			end
			local side = if rng:NextNumber() < 0.5 then 1 else -1
			local len = 64
			local ok = far
			if ok then
				for _, ds in { -len / 2, 0, len / 2 } do
					for _, extra in { 8, 36 } do
						local x, _, z = Track.PointAt(t, t.S[i] + ds, side * (ctx.Barrier + extra))
						if not ctx.Clear(x, z, ctx.Barrier + 3) or not ctx.Occ.free(x, z, 10) then
							ok = false
						end
					end
				end
			end
			if ok then
				table.insert(placed, i)
				buildBank(ctx, i, side, len)
			end
		end
	end
end

-- street circuits: pavement, lamp posts and fans pressed against the fence
local function streetside(ctx, over)
	local t, rng, P, f = ctx.T, ctx.Rng, ctx.P, ctx.Scenery
	local step = 10
	local n = 0
	for i = 1, t.N - step, step do
		if over() then
			break
		end
		n += 1
		for side = -1, 1, 2 do
			local lat = side * (ctx.Barrier + 5)
			local x1, y1, z1 = Track.PointAt(t, t.S[i], lat)
			local x2, y2, z2 = Track.PointAt(t, t.S[i + step], lat)
			if not t.Over[i] and ctx.Clear(x1, z1, ctx.Barrier + 1.5) and ctx.Clear(x2, z2, ctx.Barrier + 1.5) and ctx.Occ.free((x1 + x2) / 2, (z1 + z2) / 2, 3) then
				local p1, p2 = Vector3.new(x1, y1 + 0.2, z1), Vector3.new(x2, y2 + 0.2, z2)
				local len = (p2 - p1).Magnitude
				if len > 0.5 then
					local cf = CFrame.lookAt((p1 + p2) / 2, p2)
					P(f, Vector3.new(7, 0.8, len + 0.6), cf, PAVE, Enum.Material.Pavement)
					local outV = Vector3.new(t.RX[i], 0, t.RZ[i]) * side
					if n % 3 == 0 then
						local base = p1 + outV * 3 + Vector3.new(0, 0.4, 0)
						P(f, Vector3.new(0.5, 16, 0.5), CFrame.new(base + Vector3.new(0, 8, 0)), rgb(60, 64, 70), Enum.Material.Metal)
						P(f, Vector3.new(2.4, 0.5, 1.4), CFrame.lookAt(base + Vector3.new(0, 16, 0) - outV * 2, base + Vector3.new(0, 16, 0) - outV * 3), if ctx.Night then rgb(255, 244, 214) else rgb(220, 222, 226), if ctx.Night then Enum.Material.Neon else Enum.Material.SmoothPlastic)
					end
					if rng:NextNumber() < 0.45 * math.min(1, ctx.Dens) then
						for _ = 1, rng:NextInteger(2, 6) do
							local p = p1:Lerp(p2, rng:NextNumber()) + outV * rng:NextNumber(-2.8, 0.5) + Vector3.new(0, 0.4, 0)
							person(ctx, f, CFrame.lookAt(p, p - outV) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), rng)
						end
					end
				end
			end
		end
	end
end

-- tents, caravans and cars in a field near the track (rural circuits)
local function campsite(ctx, over)
	local t, rng, P, f = ctx.T, ctx.Rng, ctx.P, ctx.Scenery
	for _ = 1, 30 do
		if over() then
			return
		end
		local i = rng:NextInteger(1, t.N)
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local x, _, z = Track.PointAt(t, t.S[i], side * (ctx.Barrier + 70))
		if ctx.Clear(x, z, ctx.Barrier + 45) and ctx.Occ.free(x, z, 45) then
			ctx.Occ.add(x, z, 45)
			local centre = CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			for _ = 1, 10 do
				local cf = centre * CFrame.new(rng:NextNumber(-36, 36), 0, rng:NextNumber(-36, 36)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
				local roll = rng:NextNumber()
				if roll < 0.55 then
					local col = pick(rng, { rgb(40, 110, 200), rgb(220, 60, 40), rgb(60, 150, 70), rgb(240, 180, 30), rgb(230, 230, 230) })
					P(f, Vector3.new(6, 4, 4), cf * CFrame.new(0, 2, -2), col, Enum.Material.Fabric, nil, false, nil, "WedgePart")
					P(f, Vector3.new(6, 4, 4), cf * CFrame.new(0, 2, 2) * CFrame.Angles(0, math.pi, 0), col, Enum.Material.Fabric, nil, false, nil, "WedgePart")
				elseif roll < 0.8 then
					P(f, Vector3.new(7, 7, 18), cf * CFrame.new(0, 4.2, 0), rgb(240, 240, 236), Enum.Material.SmoothPlastic)
					P(f, Vector3.new(7.1, 1, 18.1), cf * CFrame.new(0, 3.5, 0), pick(rng, { rgb(40, 110, 200), rgb(200, 60, 40), rgb(60, 140, 80) }), Enum.Material.SmoothPlastic)
					P(f, Vector3.new(7.3, 2.2, 2.2), cf * CFrame.new(0, 1.1, 0), rgb(24, 24, 27), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Cylinder)
				else
					Arch.Car(f, cf, Arch.CarColor(rng), ctx.Night, P)
				end
			end
			for _ = 1, 8 do
				person(ctx, f, centre * CFrame.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-30, 30)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng)
			end
			return
		end
	end
end

-- TV helicopter flying laps a little to the side of the track
local function helicopter(ctx)
	local t, P, f = ctx.T, ctx.P, ctx.Scenery
	local base = CFrame.new(0, -400, 0)
	local livery = rgb(30, 60, 150)
	local body = {
		P(f, Vector3.new(5, 5, 9), base, livery, Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Ball),
		P(f, Vector3.new(4, 3, 3.6), base * CFrame.new(0, 0.5, -3.2), rgb(40, 60, 80), Enum.Material.Glass),
		P(f, Vector3.new(1, 1, 10), base * CFrame.new(0, 0.8, 8.5), livery, Enum.Material.SmoothPlastic),
		P(f, Vector3.new(0.3, 3.2, 2), base * CFrame.new(0, 2.2, 13), rgb(240, 240, 240), Enum.Material.SmoothPlastic),
		P(f, Vector3.new(0.4, 0.4, 9), base * CFrame.new(-2.1, -3, 0), rgb(40, 40, 44), Enum.Material.Metal),
		P(f, Vector3.new(0.4, 0.4, 9), base * CFrame.new(2.1, -3, 0), rgb(40, 40, 44), Enum.Material.Metal),
		P(f, Vector3.new(0.6, 1.4, 0.6), base * CFrame.new(0, 2.9, 0), rgb(50, 50, 54), Enum.Material.Metal),
	}
	local rotorBase = base * CFrame.new(0, 3.6, 0)
	local rotor = {
		P(f, Vector3.new(0.3, 0.12, 22), rotorBase, rgb(30, 30, 32), Enum.Material.Metal),
		P(f, Vector3.new(22, 0.12, 0.3), rotorBase, rgb(30, 30, 32), Enum.Material.Metal),
	}
	local speed, lat = 62, 28
	local lastT, lastCF = -1, base
	local function heliCF(now: number): CFrame
		if now ~= lastT then
			lastT = now
			local s = now * speed
			local x, y, z = Track.PointAt(t, s, lat)
			local x2, _, z2 = Track.PointAt(t, s + 45, lat)
			local pos = Vector3.new(x, y + 72 + math.sin(now * 0.5) * 4, z)
			lastCF = CFrame.lookAt(pos, Vector3.new(x2, pos.Y, z2)) * CFrame.Angles(math.rad(-7), 0, 0)
		end
		return lastCF
	end
	addMover(ctx, body, base, heliCF)
	addMover(ctx, rotor, rotorBase, function(now)
		return heliCF(now) * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, now * 24, 0)
	end)
end

function Life.Trackside(ctx)
	local start = ctx.Parts()
	local budget = BUDGET.Trackside[ctx.Q]
	local function over()
		return ctx.Parts() - start > budget
	end
	if ctx.Street then
		streetside(ctx, over)
	else
		banks(ctx, over)
	end
	if ctx.Th.Layout == "rural" and ctx.Q >= 2 then
		campsite(ctx, over)
	end
	if ctx.Q >= 2 and ctx.Dens > 0.5 then
		helicopter(ctx)
	end
end

---------------------------------------------------------------------------
-- Districts (city / town street grid)
---------------------------------------------------------------------------
-- one street along a block side. alongX: the street runs along X.
local function street(ctx, cx: number, cz: number, alongX: boolean, len: number)
	local P, f, rng = ctx.P, ctx.Scenery, ctx.Rng
	P(f, if alongX then Vector3.new(len, 0.4, STREET) else Vector3.new(STREET, 0.4, len), CFrame.new(cx, 0.2, cz), ROAD, Enum.Material.Asphalt)
	if ctx.Q >= 2 then
		for off = -HALF + 7, HALF - 7, 14 do
			local p = if alongX then Vector3.new(cx + off, 0.43, cz) else Vector3.new(cx, 0.43, cz + off)
			P(f, if alongX then Vector3.new(6, 0.06, 0.5) else Vector3.new(0.5, 0.06, 6), CFrame.new(p), PAINT, Enum.Material.SmoothPlastic)
		end
	end
	-- zebra crossing next to the intersection at the street's start
	if ctx.Q >= 3 and rng:NextNumber() < 0.5 then
		for k = 0, 8 do
			local across = -STREET / 2 + 2 + k * 3.25
			local p = if alongX then Vector3.new(cx - HALF + 4, 0.43, cz + across) else Vector3.new(cx + across, 0.43, cz - HALF + 4)
			P(f, if alongX then Vector3.new(4, 0.06, 1.6) else Vector3.new(1.6, 0.06, 4), CFrame.new(p), PAINT, Enum.Material.SmoothPlastic)
		end
	end
	for k = -1, 1 do
		local p = if alongX then Vector3.new(cx + k * len / 3, 0, cz) else Vector3.new(cx, 0, cz + k * len / 3)
		ctx.Occ.add(p.X, p.Z, STREET / 2)
	end
end

-- lamps, street trees and parked cars around a block
local function furniture(ctx, centre: CFrame)
	local P, f, rng, night = ctx.P, ctx.Scenery, ctx.Rng, ctx.Night
	for side = 0, 3 do
		local sideCF = centre * CFrame.Angles(0, side * math.pi / 2, 0)
		-- lamp posts at the kerb, arm over the road
		for _, u in { -BLOCK / 4, BLOCK / 4 } do
			local base = sideCF * CFrame.new(u, CURB, -(HALF - 0.6))
			P(f, Vector3.new(0.5, 15, 0.5), base * CFrame.new(0, 7.5, 0), rgb(58, 62, 68), Enum.Material.Metal)
			P(f, Vector3.new(0.35, 0.35, 5), base * CFrame.new(0, 15, -2.3), rgb(58, 62, 68), Enum.Material.Metal)
			P(f, Vector3.new(1.4, 0.5, 2.4), base * CFrame.new(0, 14.8, -4.6), if night then rgb(255, 238, 200) else rgb(220, 222, 226), if night then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		end
		-- a street tree in the middle of each side
		if ctx.Tree and ctx.Q >= 2 then
			ctx.Tree(f, sideCF * CFrame.new(rng:NextNumber(-8, 8), CURB, -(HALF - 1.2)), rng:NextNumber(0.7, 0.85))
		end
		-- parked cars in the kerbside lane
		if ctx.Q >= 2 then
			for _ = 1, rng:NextInteger(0, if ctx.Q >= 3 then 2 else 1) do
				local u = rng:NextNumber(-BLOCK / 2 + 12, BLOCK / 2 - 12)
				local ccf = sideCF * CFrame.new(u, 0.4, -(HALF + 3.8)) * CFrame.Angles(0, if rng:NextNumber() < 0.5 then math.pi / 2 else -math.pi / 2, 0)
				Arch.Car(f, ccf, Arch.CarColor(rng, ctx.Th.Layout == "city"), false, P)
			end
		end
	end
end

-- buildings along the four sides of a block, facades facing the street
local function lots(ctx, centre: CFrame, pickName)
	local f, rng = ctx.Scenery, ctx.Rng
	local rects = {}
	local function free(x, z, hx, hz): boolean
		for _, r in rects do
			if math.abs(x - r[1]) < hx + r[3] + 1 and math.abs(z - r[2]) < hz + r[4] + 1 then
				return false
			end
		end
		return true
	end
	for side = 0, 3 do
		local ang = side * math.pi / 2
		local ca, sa = math.cos(ang), math.sin(ang)
		local sideCF = centre * CFrame.Angles(0, ang, 0)
		local u = -BLOCK / 2
		local guard = 0
		while u < BLOCK / 2 - 8 and guard < 16 do
			guard += 1
			local name = pickName()
			local fw, fd = Arch.Footprint(name)
			local placed = false
			if name and u + fw <= BLOCK / 2 then
				local lx, lz = u + fw / 2, -BLOCK / 2 + fd / 2
				local x, z = lx * ca + lz * sa, -lx * sa + lz * ca
				local hx, hz = if side % 2 == 0 then fw / 2 else fd / 2, if side % 2 == 0 then fd / 2 else fw / 2
				if free(x, z, hx, hz) then
					table.insert(rects, { x, z, hx, hz })
					Arch.Build(name, f, sideCF * CFrame.new(lx, CURB, lz), rng, ctx.Th, ctx.P)
					u += fw + rng:NextNumber(0.5, 3)
					placed = true
				end
			end
			if not placed then
				u += 5
			end
		end
	end
end

local function park(ctx, centre: CFrame)
	local P, f, rng = ctx.P, ctx.Scenery, ctx.Rng
	P(f, Vector3.new(BLOCK, 0.3, BLOCK), centre * CFrame.new(0, CURB + 0.15, 0), ctx.Th.Ground:Lerp(rgb(90, 160, 70), 0.5), Enum.Material.Grass)
	for k = 0, 1 do
		P(f, if k == 0 then Vector3.new(BLOCK, 0.35, 6) else Vector3.new(6, 0.35, BLOCK), centre * CFrame.new(0, CURB + 0.18, 0), rgb(214, 204, 180), Enum.Material.Sandstone)
	end
	-- fountain
	P(f, Vector3.new(1.4, 16, 16), centre * CFrame.new(0, CURB + 0.7, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(220, 216, 206), Enum.Material.Marble, nil, false, Enum.PartType.Cylinder)
	local water = P(f, Vector3.new(0.4, 13.5, 13.5), centre * CFrame.new(0, CURB + 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(70, 150, 210), Enum.Material.Glass, nil, false, Enum.PartType.Cylinder)
	water.Transparency = 0.2
	P(f, Vector3.new(1.4, 6, 1.4), centre * CFrame.new(0, CURB + 3, 0), rgb(220, 216, 206), Enum.Material.Marble)
	for _ = 1, rng:NextInteger(8, 12) do
		local x, z = rng:NextNumber(8, BLOCK / 2 - 6) * (if rng:NextNumber() < 0.5 then 1 else -1), rng:NextNumber(8, BLOCK / 2 - 6) * (if rng:NextNumber() < 0.5 then 1 else -1)
		if ctx.Tree then
			ctx.Tree(f, centre * CFrame.new(x, CURB + 0.3, z), rng:NextNumber(0.8, 1.2))
		end
	end
	for k = 0, 3 do
		local bcf = centre * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(-6, CURB + 0.3, -14)
		P(f, Vector3.new(0.8, 1.6, 5), bcf * CFrame.new(0, 0.8, 0), rgb(110, 75, 45), Enum.Material.WoodPlanks)
	end
	if ctx.Q >= 3 then
		for _ = 1, rng:NextInteger(5, 9) do
			local p = centre * CFrame.new(rng:NextNumber(-2.5, 2.5) + (if rng:NextNumber() < 0.5 then 0 else rng:NextNumber(-40, 40)), CURB + 0.35, rng:NextNumber(-40, 40))
			person(ctx, f, p * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng)
		end
	end
end

local function carpark(ctx, centre: CFrame)
	local P, f, rng = ctx.P, ctx.Scenery, ctx.Rng
	P(f, Vector3.new(BLOCK, 0.3, BLOCK), centre * CFrame.new(0, CURB + 0.15, 0), ROAD:Lerp(rgb(120, 120, 124), 0.25), Enum.Material.Asphalt)
	for _, rowZ in { -30, 30 } do
		for x = -BLOCK / 2 + 6, BLOCK / 2 - 6, 9 do
			P(f, Vector3.new(0.4, 0.06, 16), centre * CFrame.new(x, CURB + 0.33, rowZ), PAINT, Enum.Material.SmoothPlastic)
			if x < BLOCK / 2 - 12 and rng:NextNumber() < 0.6 then
				Arch.Car(f, centre * CFrame.new(x + 4.5, CURB + 0.3, rowZ) * CFrame.Angles(0, if rowZ < 0 then 0 else math.pi, 0), Arch.CarColor(rng), false, P)
			end
		end
	end
	P(f, Vector3.new(6, 7, 6), centre * CFrame.new(BLOCK / 2 - 6, CURB + 3.5, 0), rgb(235, 235, 235), Enum.Material.Plaster)
end

-- pavement square with a kerb
local function pavement(ctx, centre: CFrame)
	ctx.P(ctx.Scenery, Vector3.new(BLOCK + WALK * 2, CURB, BLOCK + WALK * 2), centre * CFrame.new(0, CURB / 2, 0), PAVE, Enum.Material.Pavement)
end

function Life.Districts(ctx)
	local th, q = ctx.Th, ctx.Q
	local fill = FILL[th.Layout]
	if not fill then
		return 0
	end
	local t, rng, f = ctx.T, ctx.Rng, ctx.Scenery
	local reach = if th.Layout == "city" then 1000 else 760
	local dist = trackDistance(t)

	-- what to build: the country's own architecture plus generic street buildings
	local list, total, bigList = {}, 0, {}
	local function addWeight(name, w)
		if not Arch.Types[name] or NOT_IN_BLOCKS[name] or w <= 0 then
			return
		end
		if BIG[name] then
			table.insert(bigList, name)
			return
		end
		local fw, fd = Arch.Footprint(name)
		if fw <= BLOCK * 0.55 and fd <= BLOCK * 0.45 then
			total += w
			table.insert(list, { name, total })
		end
	end
	local themeTotal, fillTotal = 0, 0
	for _, w in th.Arch do
		themeTotal += w
	end
	for _, w in fill do
		fillTotal += w
	end
	for name, w in th.Arch do
		addWeight(name, w)
	end
	for name, w in fill do
		addWeight(name, w / fillTotal * math.max(themeTotal, 1) * 0.7)
	end
	if total <= 0 then
		return 0
	end
	local function pickName(): string?
		local roll = rng:NextNumber(0, total)
		for _, e in list do
			if roll <= e[2] then
				return e[1]
			end
		end
		return list[#list][1]
	end

	-- candidate blocks on a grid, nearest the track first (with some jitter)
	local b = ctx.Bounds
	local ox, oz = rng:NextNumber(0, PITCH), rng:NextNumber(0, PITCH)
	local halfDiag = (HALF + STREET / 2) * 1.4143
	local cands = {}
	for gx = math.floor((b[1] - reach - ox) / PITCH), math.ceil((b[2] + reach - ox) / PITCH) do
		for gz = math.floor((b[3] - reach - oz) / PITCH), math.ceil((b[4] + reach - oz) / PITCH) do
			local cx, cz = ox + gx * PITCH, oz + gz * PITCH
			local d = dist(cx, cz)
			if d > halfDiag + ctx.Barrier + 6 and d < reach then
				table.insert(cands, { gx, gz, cx, cz, d + rng:NextNumber(0, 180) })
			end
		end
	end
	table.sort(cands, function(a, c)
		return a[5] < c[5]
	end)
	-- phones default to Medium: keep the city smaller there
	local maxBlocks = math.min(({ 6, 14, 40, 60 })[q], math.floor(BUDGET.Districts[q] / 190))
	if th.Layout == "town" then
		maxBlocks = math.floor(maxBlocks * 0.75)
	end
	local chosen, order = {}, {}
	for _, c in cands do
		if #order >= maxBlocks then
			break
		end
		if ctx.Clear(c[3], c[4], halfDiag + ctx.Barrier + 4) and ctx.Occ.free(c[3], c[4], HALF * 1.42) then
			chosen[c[1] .. ":" .. c[2]] = true
			table.insert(order, c)
		end
	end
	for _, c in order do
		ctx.Occ.add(c[3], c[4], HALF * 1.42)
	end

	local walkers, drivers = 0, 0
	local maxWalkers = ({ 0, 0, 30, 50 })[q]
	local maxDrivers = ({ 0, 8, 16, 26 })[q]
	for _, c in order do
		local gx, gz, cx, cz = c[1], c[2], c[3], c[4]
		local centre = CFrame.new(cx, 0, cz)
		pavement(ctx, centre)
		-- each block lays the streets on its -X / -Z sides, and the +X / +Z ones when no
		-- neighbour will; vertical streets span the intersections so nothing overlaps
		street(ctx, cx - PITCH / 2, cz, false, PITCH)
		street(ctx, cx, cz - PITCH / 2, true, BLOCK + WALK * 2)
		if not chosen[(gx + 1) .. ":" .. gz] then
			street(ctx, cx + PITCH / 2, cz, false, PITCH)
		end
		if not chosen[gx .. ":" .. (gz + 1)] then
			street(ctx, cx, cz + PITCH / 2, true, BLOCK + WALK * 2)
		end

		local roll = rng:NextNumber()
		if roll < 0.1 and q >= 2 then
			park(ctx, centre)
		elseif roll < 0.17 then
			carpark(ctx, centre)
		elseif roll < 0.27 and #bigList > 0 then
			Arch.Build(pick(rng, bigList), f, centre * CFrame.new(0, CURB, 0) * CFrame.Angles(0, rng:NextInteger(0, 3) * math.pi / 2, 0), rng, th, ctx.P)
		else
			lots(ctx, centre, pickName)
		end
		furniture(ctx, centre)

		-- traffic circling the block in the driving lane
		for _ = 1, rng:NextInteger(0, 2) do
			if drivers < maxDrivers then
				drivers += 1
				local base = CFrame.new(0, -300, 0)
				local parts = Arch.Car(f, base, Arch.CarColor(rng, th.Layout == "city"), ctx.Night, ctx.P)
				local speed = rng:NextNumber(24, 40)
				local phase = rng:NextNumber(0, 1000)
				local r = HALF + 10.5
				addMover(ctx, parts, base, function(now)
					local x, z, hx, hz = loopPoint(cx, cz, r, 14, phase + now * speed, 1)
					local p = Vector3.new(x, 0.4, z)
					return CFrame.lookAt(p, p + Vector3.new(hx, 0, hz))
				end)
			end
		end
		-- pedestrians strolling round the pavement
		for _ = 1, rng:NextInteger(1, 3) do
			if walkers < maxWalkers then
				walkers += 1
				local base = CFrame.new(0, -300, 0)
				local parts = person(ctx, f, base, rng)
				local speed = rng:NextNumber(3.5, 6)
				local phase = rng:NextNumber(0, 1000)
				local dir = if rng:NextNumber() < 0.5 then 1 else -1
				local r = BLOCK / 2 + 3.4
				addMover(ctx, parts, base, function(now)
					local x, z, hx, hz = loopPoint(cx, cz, r, 4, phase + now * speed, dir)
					local p = Vector3.new(x, CURB + math.abs(math.sin((phase + now) * 6)) * 0.15, z)
					return CFrame.lookAt(p, p + Vector3.new(hx, 0, hz))
				end)
			end
		end
	end
	return #order
end

---------------------------------------------------------------------------
-- Fields (rural patchwork)
---------------------------------------------------------------------------
local CROPS = {
	{ "wheat", rgb(214, 186, 104), Enum.Material.Grass, 3 },
	{ "green", rgb(104, 158, 62), Enum.Material.Grass, 3 },
	{ "plough", rgb(118, 88, 60), Enum.Material.Ground, 2 },
	{ "pasture", rgb(122, 172, 78), Enum.Material.Grass, 3 },
	{ "rapeseed", rgb(236, 214, 58), Enum.Material.Grass, 1 },
}

function Life.Fields(ctx)
	if ctx.Th.Layout ~= "rural" then
		return 0
	end
	local t, rng, P, f, q = ctx.T, ctx.Rng, ctx.P, ctx.Scenery, ctx.Q
	local start = ctx.Parts()
	local budget = BUDGET.Fields[q]
	local dist = trackDistance(t)
	local rot = CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0)
	local cw, ch = 140, 105
	local b = ctx.Bounds
	local cx0, cz0 = (b[1] + b[2]) / 2, (b[3] + b[4]) / 2
	local reach = math.max(b[2] - b[1], b[4] - b[3]) / 2 + 900
	local cands = {}
	for gx = -math.ceil(reach / cw), math.ceil(reach / cw) do
		for gz = -math.ceil(reach / ch), math.ceil(reach / ch) do
			local p = (CFrame.new(cx0, 0, cz0) * rot * CFrame.new(gx * cw, 0, gz * ch)).Position
			local d = dist(p.X, p.Z)
			if d > ctx.Barrier + 80 and d < 950 then
				table.insert(cands, { p, d + rng:NextNumber(0, 200) })
			end
		end
	end
	table.sort(cands, function(a, c)
		return a[2] < c[2]
	end)
	local maxFields = ({ 12, 28, 48, 70 })[q]
	local totalW = 0
	for _, c in CROPS do
		totalW += c[4]
	end
	local count = 0
	local tractorDone = q < 3
	for _, c in cands do
		if count >= maxFields or ctx.Parts() - start > budget then
			break
		end
		local p = c[1]
		if ctx.Clear(p.X, p.Z, ctx.Barrier + 76) and ctx.Occ.free(p.X, p.Z, 42) then
			count += 1
			local roll, crop = rng:NextNumber(0, totalW), CROPS[1]
			for _, cr in CROPS do
				roll -= cr[4]
				if roll <= 0 then
					crop = cr
					break
				end
			end
			local w, d = cw - rng:NextNumber(4, 10), ch - rng:NextNumber(4, 10)
			local fcf = CFrame.new(p) * rot
			P(f, Vector3.new(w, 0.3, d), fcf * CFrame.new(0, 0.1, 0), crop[2]:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.08)), crop[3])
			ctx.Occ.add(p.X, p.Z, math.min(w, d) / 2 - 4)
			if q >= 3 and crop[1] ~= "pasture" then
				for k = -2, 2 do
					P(f, Vector3.new(w - 4, 0.06, 1.2), fcf * CFrame.new(0, 0.28, k * d / 6), crop[2]:Lerp(Color3.new(0, 0, 0), 0.18), crop[3])
				end
			end
			if q >= 2 then
				-- hedge with a couple of trees along one edge
				local edge = rng:NextInteger(0, 1)
				local hcf = fcf * CFrame.new(if edge == 0 then 0 else w / 2 + 2, 1.3, if edge == 0 then d / 2 + 2 else 0)
				P(f, if edge == 0 then Vector3.new(w, 2.6, 2.4) else Vector3.new(2.4, 2.6, d), hcf, rgb(62, 112, 48), Enum.Material.LeafyGrass)
				if ctx.Tree then
					for _ = 1, 2 do
						local along = rng:NextNumber(-0.4, 0.4)
						ctx.Tree(f, hcf * CFrame.new(if edge == 0 then along * w else 0, -1.3, if edge == 0 then 0 else along * d), rng:NextNumber(0.9, 1.3))
					end
				end
			end
			if crop[1] == "wheat" then
				for _ = 1, rng:NextInteger(2, 5) do
					P(f, Vector3.new(4, 4, 4), fcf * CFrame.new(rng:NextNumber(-w / 2 + 5, w / 2 - 5), 2.1, rng:NextNumber(-d / 2 + 5, d / 2 - 5)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rgb(222, 196, 120), Enum.Material.Grass, nil, false, Enum.PartType.Cylinder)
				end
			elseif crop[1] == "pasture" then
				for _ = 1, rng:NextInteger(2, 5) do
					local ccf = fcf * CFrame.new(rng:NextNumber(-w / 2 + 6, w / 2 - 6), 0, rng:NextNumber(-d / 2 + 6, d / 2 - 6)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
					local hide = pick(rng, { rgb(245, 245, 240), rgb(120, 80, 50), rgb(40, 36, 34) })
					P(f, Vector3.new(2.2, 2.2, 4.8), ccf * CFrame.new(0, 2.6, 0), hide, Enum.Material.SmoothPlastic)
					P(f, Vector3.new(1.4, 1.4, 1.8), ccf * CFrame.new(0, 3.2, -3), hide, Enum.Material.SmoothPlastic)
					P(f, Vector3.new(1.8, 1.6, 4), ccf * CFrame.new(0, 0.8, 0), rgb(60, 50, 44), Enum.Material.SmoothPlastic)
				end
			elseif not tractorDone and (crop[1] == "plough" or crop[1] == "green") then
				tractorDone = true
				local base = CFrame.new(0, -300, 0)
				local col = pick(rng, { rgb(40, 130, 60), rgb(200, 40, 30), rgb(40, 90, 170) })
				local parts = {
					P(f, Vector3.new(3.4, 3, 7), base * CFrame.new(0, 3, 0), col, Enum.Material.SmoothPlastic),
					P(f, Vector3.new(3.4, 3.6, 3.4), base * CFrame.new(0, 6.1, 1.6), rgb(50, 70, 90), Enum.Material.Glass),
					P(f, Vector3.new(5.6, 4.2, 4.2), base * CFrame.new(0, 2.1, 2), rgb(26, 26, 28), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Cylinder),
					P(f, Vector3.new(4.4, 2.4, 2.4), base * CFrame.new(0, 1.2, -2.6), rgb(26, 26, 28), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Cylinder),
				}
				local span = w / 2 - 10
				local lane = rng:NextNumber(-d / 4, d / 4)
				addMover(ctx, parts, base, function(now)
					local a = now * 6 / span
					local x = math.sin(a) * span
					local heading = if math.cos(a) >= 0 then 1 else -1
					local pos = (fcf * CFrame.new(x, 0.3, lane)).Position
					local dirV = fcf.RightVector * heading
					return CFrame.lookAt(pos, pos + dirV)
				end)
			end
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Movers
---------------------------------------------------------------------------
-- Starts animating everything registered in ctx.Movers. Returns the connection.
function Life.Start(ctx): RBXScriptConnection?
	if #ctx.Movers == 0 then
		return nil
	end
	local parts, cfs = {}, {}
	for _, m in ctx.Movers do
		for _, p in m.Parts do
			table.insert(parts, p)
		end
	end
	local t0 = os.clock()
	local acc = 1
	return RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then
			return
		end
		acc = 0
		local now = os.clock() - t0
		local n = 0
		for _, m in ctx.Movers do
			local cf = m.Update(now)
			for _, off in m.Offsets do
				n += 1
				cfs[n] = cf * off
			end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return Life
