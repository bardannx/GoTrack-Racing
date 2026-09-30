--!nonstrict
-- Builds a full circuit world on the client:
--  * road (smooth segments), bright edge lines, rubbered racing line, skid marks
--  * red/white kerbs, sausage kerbs, grass / gravel traps / painted asphalt run-off
--  * barriers on BOTH sides everywhere: armco, tyre walls, TecPro blocks, street walls
--    with catch fencing (solid - you can crash into them)
--  * start gantry + lights, grid boxes, pit lane with garages, braking boards, corner
--    chevron boards, grandstands full of fans, marshal posts, TV towers, billboards,
--    sponsor bridges, floodlights, blimp
--  * the host country's architecture packed around the track, props, horizon
--  * Landmarks: each circuit's signature sights (towers, statues, mountains, animals,
--    fountains, tunnels...) plus boats, planes, birds and balloons moving around
--  * WorldLife: city street grids, farm fields, spectator banks, traffic, pedestrians and
--    a TV helicopter
--  * Cityscape: the rest of the land out to the horizon (city grids with downtowns, suburbs,
--    villages, forests, ponds, hills, rock formations, cranes, far traffic)
--  * Blender world meshes (WorldMeshes) for buildings, trees, rocks, mountains and road cars
--    once they're imported in Studio; part-built versions until then
--  * bright per-circuit lighting, weather, ambient effects (petals, leaves, sand, embers,
--    fireworks) and a GoTrack blimp. Detail scales with the Graphics Quality setting.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Track = require(Shared.Track)
local Themes = require(Shared.Themes)

local Arch = require(script.Parent.Architecture)
local Life = require(script.Parent.WorldLife)
local Landmarks = require(script.Parent.Landmarks)
local WorldMeshes = require(script.Parent.WorldMeshes)
local Cityscape = require(script.Parent.Cityscape)

local CircuitBuilder = {}

local current = nil
local partCounter = 0
local QUALITY_DENSITY = { 0.4, 0.7, 1, 1.3 }

local function yieldMaybe()
	partCounter += 1
	if partCounter % 300 == 0 then
		task.wait()
	end
end

local function P(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, name: string?, collide: boolean?, shape: Enum.PartType?, className: string?): BasePart
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.CanTouch = false
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape and p:IsA("Part") then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if name then
		p.Name = name
	end
	p.Parent = parent
	yieldMaybe()
	return p
end

-- Place a Blender world mesh (WorldMeshes) and count its parts; nil when not imported
local function MESH(design: string, parent: Instance, cf: CFrame, opts): { BasePart }?
	local parts = WorldMeshes.Place(design, parent, cf, opts)
	if parts then
		for _ in parts do
			yieldMaybe()
		end
	end
	return parts
end

local function sign(x: number): number
	return if x >= 0 then 1 else -1
end

-- Roblox balls are always perfectly round; stretched shapes need a sphere mesh
local function E(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = P(parent, size, cf, color, material)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

local function textGui(part: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 10
	sg.LightInfluence = 0.1
	sg.MaxDistance = 700
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = if bg then 0 else 1
	tl.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	tl.Text = text
	tl.TextScaled = true
	tl.Font = font or Enum.Font.GothamBlack
	tl.TextColor3 = color
	tl.Parent = sg
	sg.Parent = part
end

local BRANDS = {
	{ "TURBOFUEL", Color3.fromRGB(255, 70, 40) },
	{ "APEX ENERGY", Color3.fromRGB(60, 200, 255) },
	{ "NITRO COLA", Color3.fromRGB(230, 30, 60) },
	{ "GOTRACK", Color3.fromRGB(255, 180, 40) },
	{ "VELOCITY TYRES", Color3.fromRGB(255, 220, 0) },
	{ "PIXEL MOTORS", Color3.fromRGB(120, 90, 255) },
	{ "BLOX OIL", Color3.fromRGB(40, 200, 120) },
	{ "HYPERION WATCHES", Color3.fromRGB(230, 230, 230) },
	{ "STUDLINK", Color3.fromRGB(0, 170, 255) },
	{ "ORBIT AIR", Color3.fromRGB(255, 120, 200) },
}

---------------------------------------------------------------------------
-- Clearance grid (keeps scenery and barriers off the track)
---------------------------------------------------------------------------
local function buildClearance(t)
	local cell = 40
	local grid = {}
	for i = 1, t.N do
		local key = math.floor(t.X[i] / cell) .. ":" .. math.floor(t.Z[i] / cell)
		local list = grid[key]
		if not list then
			list = {}
			grid[key] = list
		end
		table.insert(list, i)
	end
	-- clear(x, z, radius, ignoreIdx?, ignoreRange?) -> true when no track sample is closer
	return function(x: number, z: number, radius: number, ignoreIdx: number?, ignoreRange: number?): boolean
		local r = math.ceil(radius / cell) + 1
		local cx, cz = math.floor(x / cell), math.floor(z / cell)
		local r2 = radius * radius
		for gx = cx - r, cx + r do
			for gz = cz - r, cz + r do
				local list = grid[gx .. ":" .. gz]
				if list then
					for _, i in list do
						if not ignoreIdx or math.abs(Track.IndexDelta(t, ignoreIdx, i)) > (ignoreRange or 40) then
							local dx, dz = t.X[i] - x, t.Z[i] - z
							if dx * dx + dz * dz < r2 then
								return false
							end
						end
					end
				end
			end
		end
		return true
	end
end

-- circles already used by buildings / stands (2D occupancy)
local function newOccupancy()
	local cell = 60
	local grid = {}
	local occ = {}
	local maxR = 90
	local blockers = {}
	-- areas nothing may be built on (the sea); fn(x, z, r) -> true when blocked
	function occ.block(fn)
		table.insert(blockers, fn)
	end
	function occ.free(x: number, z: number, r: number): boolean
		for _, fn in blockers do
			if fn(x, z, r) then
				return false
			end
		end
		local cx, cz = math.floor(x / cell), math.floor(z / cell)
		local span = math.ceil((r + maxR) / cell)
		for gx = cx - span, cx + span do
			for gz = cz - span, cz + span do
				local list = grid[gx .. ":" .. gz]
				if list then
					for _, c in list do
						local dx, dz = c[1] - x, c[2] - z
						local rr = c[3] + r
						if dx * dx + dz * dz < rr * rr then
							return false
						end
					end
				end
			end
		end
		return true
	end
	function occ.add(x: number, z: number, r: number)
		maxR = math.max(maxR, r)
		local key = math.floor(x / cell) .. ":" .. math.floor(z / cell)
		grid[key] = grid[key] or {}
		table.insert(grid[key], { x, z, r })
	end
	return occ
end

---------------------------------------------------------------------------
-- Scenery props
---------------------------------------------------------------------------
local Props = {}

function Props.tree_round(f, cf, s, th)
	P(f, Vector3.new(2, 8, 2) * s, cf * CFrame.new(0, 4 * s, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	local leaf = Color3.fromRGB(70, 150, 55)
	P(f, Vector3.new(11, 11, 11) * s, cf * CFrame.new(0, 12 * s, 0), leaf, Enum.Material.LeafyGrass, nil, false, Enum.PartType.Ball)
	P(f, Vector3.new(7, 7, 7) * s, cf * CFrame.new(3 * s, 15 * s, 1 * s), leaf:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.LeafyGrass, nil, false, Enum.PartType.Ball)
end

function Props.tree_eucalyptus(f, cf, s, th)
	P(f, Vector3.new(1.6, 16, 1.6) * s, cf * CFrame.new(0, 8 * s, 0), Color3.fromRGB(215, 205, 190), Enum.Material.Wood)
	local leaf = Color3.fromRGB(120, 150, 110)
	E(f, Vector3.new(10, 7, 10) * s, cf * CFrame.new(0, 17 * s, 0), leaf, Enum.Material.LeafyGrass)
	E(f, Vector3.new(7, 5, 7) * s, cf * CFrame.new(-3 * s, 14 * s, 2 * s), leaf, Enum.Material.LeafyGrass)
end

function Props.tree_cypress(f, cf, s, th)
	P(f, Vector3.new(1, 3, 1) * s, cf * CFrame.new(0, 1.5 * s, 0), Color3.fromRGB(100, 70, 45), Enum.Material.Wood)
	E(f, Vector3.new(4, 18, 4) * s, cf * CFrame.new(0, 11 * s, 0), Color3.fromRGB(40, 90, 50), Enum.Material.LeafyGrass)
end

function Props.tree_maple(f, cf, s, th)
	local colors = { Color3.fromRGB(220, 80, 30), Color3.fromRGB(240, 160, 30), Color3.fromRGB(190, 40, 30) }
	P(f, Vector3.new(2, 9, 2) * s, cf * CFrame.new(0, 4.5 * s, 0), Color3.fromRGB(100, 65, 40), Enum.Material.Wood)
	local c = colors[math.random(1, 3)]
	E(f, Vector3.new(12, 10, 12) * s, cf * CFrame.new(0, 13 * s, 0), c, Enum.Material.LeafyGrass)
	P(f, Vector3.new(7, 7, 7) * s, cf * CFrame.new(-3 * s, 17 * s, 2 * s), c:Lerp(Color3.new(1, 1, 0), 0.15), Enum.Material.LeafyGrass, nil, false, Enum.PartType.Ball)
end

function Props.tree_cherry(f, cf, s, th)
	P(f, Vector3.new(1.8, 8, 1.8) * s, cf * CFrame.new(0, 4 * s, 0), Color3.fromRGB(90, 60, 50), Enum.Material.Wood)
	E(f, Vector3.new(13, 9, 13) * s, cf * CFrame.new(0, 12 * s, 0), Color3.fromRGB(255, 170, 205), Enum.Material.LeafyGrass)
	P(f, Vector3.new(8, 7, 8) * s, cf * CFrame.new(3 * s, 15 * s, -2 * s), Color3.fromRGB(255, 200, 225), Enum.Material.LeafyGrass, nil, false, Enum.PartType.Ball)
end

function Props.tree_pine(f, cf, s, th)
	P(f, Vector3.new(2, 6, 2) * s, cf * CFrame.new(0, 3 * s, 0), Color3.fromRGB(95, 65, 45), Enum.Material.Wood)
	for i = 0, 2 do
		local w = (10 - i * 2.8) * s
		P(f, Vector3.new(w, 5 * s, w), cf * CFrame.new(0, (6 + i * 4.2) * s, 0) * CFrame.Angles(0, math.rad(45 * i), 0), Color3.fromRGB(40, 105, 60), Enum.Material.LeafyGrass)
	end
end

function Props.snowpine(f, cf, s, th)
	Props.tree_pine(f, cf, s, th)
	for i = 0, 2 do
		local w = (8 - i * 2.4) * s
		P(f, Vector3.new(w, 1 * s, w), cf * CFrame.new(0, (8.8 + i * 4.2) * s, 0) * CFrame.Angles(0, math.rad(45 * i), 0), Color3.fromRGB(245, 250, 255), Enum.Material.Snow)
	end
end

function Props.palm(f, cf, s, th)
	local h = 18 * s
	for k = 0, 3 do
		P(f, Vector3.new(1.6 * s, h / 4 + 0.4, 1.6 * s), cf * CFrame.new(k * 0.6 * s, h / 8 + k * h / 4, 0) * CFrame.Angles(0, 0, math.rad(-6)), Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
	end
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		P(f, Vector3.new(1.4 * s, 0.4 * s, 9 * s), cf * CFrame.new(2.4 * s, h + 0.5, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, -1 * s, -4 * s) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(60, 160, 60), Enum.Material.LeafyGrass)
	end
end

function Props.tree_jungle(f, cf, s, th)
	P(f, Vector3.new(2.5, 16, 2.5) * s, cf * CFrame.new(0, 8 * s, 0), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
	E(f, Vector3.new(16, 7, 16) * s, cf * CFrame.new(0, 18 * s, 0), Color3.fromRGB(40, 130, 50), Enum.Material.LeafyGrass)
	E(f, Vector3.new(10, 6, 10) * s, cf * CFrame.new(-4 * s, 14 * s, 3 * s), Color3.fromRGB(60, 150, 60), Enum.Material.LeafyGrass)
end

function Props.hedge(f, cf, s, th)
	P(f, Vector3.new(30 * s, 4, 3), cf * CFrame.new(0, 2, 0), Color3.fromRGB(60, 120, 50), Enum.Material.LeafyGrass)
end

function Props.cactus(f, cf, s, th)
	local c = Color3.fromRGB(70, 140, 70)
	P(f, Vector3.new(12 * s, 3 * s, 3 * s), cf * CFrame.new(0, 6 * s, 0) * CFrame.Angles(0, 0, math.pi / 2), c, nil, nil, false, Enum.PartType.Cylinder)
	for side = -1, 1, 2 do
		P(f, Vector3.new(3 * s, 2 * s, 2 * s), cf * CFrame.new(side * 2.2 * s, 5.5 * s, 0), c, nil, nil, false, Enum.PartType.Cylinder)
		P(f, Vector3.new(4 * s, 2 * s, 2 * s), cf * CFrame.new(side * 3.4 * s, 7.5 * s, 0) * CFrame.Angles(0, 0, math.pi / 2), c, nil, nil, false, Enum.PartType.Cylinder)
	end
end

function Props.agave(f, cf, s, th)
	for k = 0, 5 do
		P(f, Vector3.new(0.8 * s, 5 * s, 0.4 * s), cf * CFrame.Angles(0, k * math.pi / 3, 0) * CFrame.new(0, 2 * s, -1 * s) * CFrame.Angles(math.rad(-30), 0, 0), Color3.fromRGB(90, 150, 130), Enum.Material.LeafyGrass)
	end
end

function Props.rock(f, cf, s, th)
	local c = th.Ground:Lerp(Color3.fromRGB(120, 120, 125), 0.7)
	P(f, Vector3.new(9, 6, 8) * s, cf * CFrame.new(0, 2 * s, 0) * CFrame.Angles(0.2, 0.5, 0.1), c, Enum.Material.Rock)
	P(f, Vector3.new(5, 5, 5) * s, cf * CFrame.new(4 * s, 1.5 * s, 3 * s) * CFrame.Angles(0.4, 1.2, 0.3), c:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Rock)
end

function Props.lavarock(f, cf, s, th)
	P(f, Vector3.new(10, 6, 9) * s, cf * CFrame.new(0, 2 * s, 0) * CFrame.Angles(0.2, 0.7, 0.1), Color3.fromRGB(46, 40, 40), Enum.Material.Basalt)
	P(f, Vector3.new(8, 0.4, 6) * s, cf * CFrame.new(6 * s, 0.3, 2 * s) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(255, 90, 20), Enum.Material.Neon)
end

function Props.iceblock(f, cf, s, th)
	P(f, Vector3.new(8, 10, 7) * s, cf * CFrame.new(0, 4 * s, 0) * CFrame.Angles(0.1, 0.6, 0.2), Color3.fromRGB(170, 220, 255), Enum.Material.Glacier)
end

function Props.dune(f, cf, s, th)
	E(f, Vector3.new(40, 12, 30) * s, cf * CFrame.new(0, -1 * s, 0) * CFrame.Angles(0, math.random() * 3, 0), th.Ground:Lerp(Color3.new(1, 1, 1), 0.05), Enum.Material.Sand)
end

function Props.lantern(f, cf, s, th)
	P(f, Vector3.new(0.6, 10, 0.6), cf * CFrame.new(0, 5, 0), Color3.fromRGB(60, 40, 30), Enum.Material.Wood)
	P(f, Vector3.new(3, 3, 3), cf * CFrame.new(0, 10, 0), Color3.fromRGB(255, 60, 40), Enum.Material.Neon, nil, false, Enum.PartType.Ball)
end

function Props.tulips(f, cf, s, th)
	local colors = { Color3.fromRGB(255, 50, 60), Color3.fromRGB(255, 220, 30), Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 140, 0), Color3.fromRGB(170, 60, 220) }
	for k = 0, 3 do
		P(f, Vector3.new(60 * s, 1.2, 6 * s), cf * CFrame.new(0, 0.6, (k - 1.5) * 8 * s), colors[math.random(1, #colors)], Enum.Material.LeafyGrass)
	end
end

function Props.sunflowers(f, cf, s, th)
	for k = 0, 2 do
		P(f, Vector3.new(60 * s, 2.5, 7 * s), cf * CFrame.new(0, 1.2, (k - 1) * 9 * s), Color3.fromRGB(255, 200, 30), Enum.Material.LeafyGrass)
	end
end

function Props.bush(f, cf, s, th)
	local c = th.Ground:Lerp(Color3.fromRGB(50, 110, 45), 0.6)
	E(f, Vector3.new(7, 4, 6) * s, cf * CFrame.new(0, 1.6 * s, 0), c, Enum.Material.LeafyGrass)
	E(f, Vector3.new(5, 3.4, 5) * s, cf * CFrame.new(2.6 * s, 1.4 * s, 1.5 * s), c:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.LeafyGrass)
end

-- Blender stand-ins for the props once the world meshes are imported:
-- prop name -> { design(s), leaf colours?, trunk colour? }
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local PROP_MESH = {
	tree_round = { { "tree_oak", "tree_oak", "tree_birch" }, { rgb(70, 150, 55), rgb(88, 162, 62), rgb(60, 136, 52), rgb(100, 160, 60) } },
	tree_eucalyptus = { { "tree_birch", "tree_oak" }, { rgb(120, 150, 110), rgb(108, 140, 100), rgb(132, 160, 118) }, rgb(215, 205, 190) },
	tree_cypress = { { "tree_cypress" }, { rgb(40, 90, 50), rgb(48, 100, 56) } },
	tree_maple = { { "tree_oak", "tree_birch" }, { rgb(220, 80, 30), rgb(240, 160, 30), rgb(190, 40, 30), rgb(230, 120, 40), rgb(250, 190, 60) }, rgb(100, 65, 40) },
	tree_cherry = { { "tree_cherry" }, { rgb(255, 170, 205), rgb(255, 196, 222), rgb(250, 150, 190), rgb(255, 225, 235) }, rgb(90, 60, 50) },
	tree_pine = { { "tree_pine" }, { rgb(40, 105, 60), rgb(34, 92, 52), rgb(52, 112, 64) } },
	snowpine = { { "tree_snowpine" }, { rgb(40, 95, 60), rgb(34, 84, 54) } },
	palm = { { "tree_palm" }, { rgb(60, 160, 60), rgb(80, 170, 70), rgb(70, 150, 50) }, rgb(150, 110, 70) },
	tree_jungle = { { "tree_jungle", "tree_jungle", "tree_acacia" }, { rgb(40, 130, 50), rgb(55, 145, 60), rgb(30, 115, 45) } },
	tree_acacia = { { "tree_acacia" }, { rgb(110, 140, 60), rgb(96, 128, 52) } },
	bush = { { "bush" } },
	rock = { { "rock_a", "rock_b" } },
	rock_spire = { { "rock_spire" } },
}

-- place prop `name`: the Blender mesh when imported, else the part version
local meshesOn = false
local function prop(name: string, f: Instance, cf: CFrame, s: number, th)
	local m = meshesOn and PROP_MESH[name]
	if m then
		local design = m[1][math.random(1, #m[1])]
		local paint = {}
		if m[2] then
			paint.Leaf = { m[2][math.random(1, #m[2])], Enum.Material.LeafyGrass }
		end
		if m[3] then
			paint.Trunk = { m[3], Enum.Material.Wood }
		end
		if name == "bush" then
			paint.Leaf = { th.Ground:Lerp(rgb(50, 110, 45), 0.6), Enum.Material.LeafyGrass }
		elseif name == "rock" or name == "rock_spire" then
			local rc = th.Ground:Lerp(rgb(120, 120, 125), 0.7)
			paint.Rock = { rc, Enum.Material.Rock }
			paint.Band = { rc:Lerp(rgb(210, 120, 80), 0.45), Enum.Material.Sandstone }
		end
		local k = s * (if name == "rock" then 1.3 else 1)
		if MESH(design, f, cf * CFrame.Angles(0, math.random() * math.pi * 2, 0), { Scale = Vector3.new(k, k * (0.9 + math.random() * 0.25), k), Paint = paint }) then
			return
		end
	end
	local fn = Props[name]
	if fn then
		fn(f, cf, s, th)
	elseif name == "rock_spire" then
		Props.rock(f, cf, s * 1.6, th)
	elseif name == "tree_acacia" then
		Props.tree_jungle(f, cf, s * 0.8, th)
	end
end

---------------------------------------------------------------------------
-- (Landmarks live in Landmarks.luau)
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Horizon
---------------------------------------------------------------------------
-- Horizon from the Blender meshes: skyline towers, mountain ranges, mesas, rolling hills
local SKYLINE = { "tower_glass", "tower_deco", "tower_twist", "tower_round", "tower_blade", "tower_twin", "tower_stack", "tower_resi" }
local function horizonMeshes(f, th, cx, cz, radius, rng, dens, seaZ, occ, q)
	local kind: string = th.Horizon
	local skyline = kind == "skyline"
	local count = math.floor((if skyline then 36 else 20) * math.clamp(dens, 0.6, 1.2))
	for i = 1, count do
		local ang = (i / count) * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
		if skyline then
			local dist = radius + rng:NextNumber(0, 380)
			local pos = Vector3.new(cx + math.cos(ang) * dist, 0, cz + math.sin(ang) * dist)
			if (seaZ and pos.Z > seaZ - 80) or not occ.free(pos.X, pos.Z, 40) then
				continue
			end
			for c = 1, if q <= 2 then 1 else rng:NextInteger(1, 3) do
				local design = SKYLINE[rng:NextInteger(1, #SKYLINE)]
				local k = rng:NextNumber(1.1, 1.8) / c ^ 0.25
				local p = pos + Vector3.new(rng:NextNumber(-80, 80), 0, rng:NextNumber(-80, 80))
				MESH(design, f, CFrame.lookAt(p, Vector3.new(cx, 0, cz)), { Scale = Vector3.new(k, k * rng:NextNumber(0.8, 1.25), k), Paint = Arch.MeshPaint(design, rng, th), Night = th.Night, Lit = if th.Night then rng:NextInteger(1, 2) else 0 })
			end
		else
			local design, k
			if kind == "hills" then
				design, k = "hill", rng:NextNumber(0.7, 1.2)
			elseif kind == "mesas" then
				design, k = "mtn_mesa", rng:NextNumber(0.45, 0.85)
			else
				design, k = if rng:NextNumber() < 0.5 then "mtn_peak" else "mtn_ridge", rng:NextNumber(0.5, 0.95)
			end
			local W = WorldMeshes.Size(design) or 1000
			local dist = radius + W * k * 0.35 + rng:NextNumber(0, 500)
			local pos = Vector3.new(cx + math.cos(ang) * dist, 0, cz + math.sin(ang) * dist)
			if seaZ and pos.Z + W * k * 0.5 > seaZ - 40 then
				continue
			end
			local rock = th.HorizonColor or (if kind == "snowmountains" then Color3.fromRGB(118, 126, 142) else Color3.fromRGB(122, 118, 110))
			local paint = {
				Base = { if kind == "snowmountains" then th.Ground:Lerp(Color3.fromRGB(190, 200, 212), 0.35) else th.Ground:Lerp(Color3.fromRGB(70, 120, 60), 0.25), Enum.Material.Grass },
				Rock = { rock, Enum.Material.Rock },
				Snow = { Color3.fromRGB(245, 248, 255), Enum.Material.Snow },
			}
			if kind == "mesas" then
				local sand = th.HorizonColor or Color3.fromRGB(205, 128, 82):Lerp(Color3.fromRGB(232, 175, 118), rng:NextNumber())
				paint.Rock = { sand, Enum.Material.Sandstone }
				paint.Band = { sand:Lerp(Color3.fromRGB(245, 205, 150), 0.4), Enum.Material.Sandstone }
				paint.Base = { sand:Lerp(Color3.fromRGB(230, 200, 150), 0.5), Enum.Material.Sand }
			end
			MESH(design, f, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), { Scale = Vector3.new(k * rng:NextNumber(0.75, 1.35), k * rng:NextNumber(0.75, 1.45), k * rng:NextNumber(0.75, 1.35)), Paint = paint })
		end
	end
end

local function horizon(f, th, cx, cz, radius, rng, dens, seaZ, occ, q)
	local kind: string = th.Horizon
	if kind == "none" then
		return
	end
	local useMeshes = meshesOn and kind ~= "volcanoes"
	if useMeshes then
		return horizonMeshes(f, th, cx, cz, radius, rng, dens, seaZ, occ, q)
	end
	local count = math.floor((if kind == "skyline" then 40 else 26) * math.clamp(dens, 0.6, 1.2))
	for i = 1, count do
		local ang = (i / count) * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local dist = radius + rng:NextNumber(0, 400)
		local pos = Vector3.new(cx + math.cos(ang) * dist, 0, cz + math.sin(ang) * dist)
		-- nothing standing in the sea, and don't cut through a far landmark
		if (seaZ and pos.Z > seaZ - 80) or (occ and not occ.free(pos.X, pos.Z, 40)) then
			continue
		end
		if kind == "skyline" then
			-- clusters of 1-3 towers with window bands and a crown
			for c = 1, if q <= 2 then 1 else rng:NextInteger(1, 3) do
				local off = Vector3.new(rng:NextNumber(-70, 70), 0, rng:NextNumber(-70, 70))
				local h = rng:NextNumber(120, 380) / c ^ 0.3
				local w = rng:NextNumber(50, 100)
				local glass = Color3.fromRGB(80, 105, 140):Lerp(Color3.fromRGB(170, 190, 210), rng:NextNumber())
				local tcf = CFrame.new(pos + off + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, ang, 0)
				P(f, Vector3.new(w, h, w), tcf, glass, Enum.Material.Glass)
				local bands = math.floor(h / (if q <= 2 then 80 else 40))
				for k = 1, bands do
					local lit = th.Night and rng:NextNumber() < 0.6
					P(f, Vector3.new(w + 0.6, 3, w + 0.6), tcf * CFrame.new(0, -h / 2 + k * 40, 0), if lit then Color3.fromRGB(255, 225, 160) else glass:Lerp(Color3.new(1, 1, 1), 0.35), if lit then Enum.Material.Neon else Enum.Material.Metal)
				end
				if rng:NextNumber() < 0.5 then
					P(f, Vector3.new(w * 0.6, 20, w * 0.6), tcf * CFrame.new(0, h / 2 + 10, 0), glass, Enum.Material.Glass)
				end
			end
		elseif kind == "mesas" then
			local w, h = rng:NextNumber(300, 600), rng:NextNumber(90, 220)
			local c = th.HorizonColor or Color3.fromRGB(205, 128, 82):Lerp(Color3.fromRGB(232, 175, 118), rng:NextNumber())
			P(f, Vector3.new(w, h, w * 0.7), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, ang, 0), c, Enum.Material.Sandstone)
		else
			local w = rng:NextNumber(350, 700)
			local h = rng:NextNumber(180, 480) * (if kind == "hills" then 0.45 else 1)
			local base = th.HorizonColor or (if kind == "snowmountains" then Color3.fromRGB(130, 140, 160) elseif kind == "volcanoes" then Color3.fromRGB(66, 56, 52) else Color3.fromRGB(86, 132, 80))
			P(f, Vector3.new(w, w, w), CFrame.new(pos + Vector3.new(0, h - w * 0.72, 0)) * CFrame.Angles(math.rad(45), ang, math.rad(35)), base, if kind == "hills" then Enum.Material.Grass else Enum.Material.Rock)
			if kind == "snowmountains" or (kind == "mountains" and h > 330) then
				P(f, Vector3.new(w * 0.36, w * 0.36, w * 0.36), CFrame.new(pos + Vector3.new(0, h - w * 0.21, 0)) * CFrame.Angles(math.rad(45), ang, math.rad(35)), Color3.fromRGB(245, 248, 255), Enum.Material.Snow)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Lighting & weather
---------------------------------------------------------------------------
local function getOrMake(className: string, name: string, parent: Instance)
	local e = parent:FindFirstChild(name)
	if e and e.ClassName == className then
		return e
	end
	local n = Instance.new(className)
	n.Name = name
	n.Parent = parent
	return n
end

function CircuitBuilder.ApplyLighting(th, quality: number?)
	local q = quality or 3
	local L = th.Sky
	Lighting.ClockTime = L.ClockTime
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = L.Brightness
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.Outdoor
	Lighting.ColorShift_Top = L.Shift
	Lighting.GlobalShadows = q >= 2
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.ExposureCompensation = L.Exposure or 0
	local atmo = getOrMake("Atmosphere", "GoTrackAtmosphere", Lighting)
	atmo.Color = L.AtmoColor
	atmo.Decay = L.AtmoDecay
	atmo.Density = L.Density
	atmo.Haze = L.Haze
	atmo.Glare = L.Glare
	atmo.Offset = 0.1
	local bloom = getOrMake("BloomEffect", "GoTrackBloom", Lighting)
	bloom.Enabled = q >= 2
	-- night: neon windows glow without washing out the screen
	bloom.Intensity = if th.Night then 0.4 else 0.35
	bloom.Size = if th.Night then 18 else 26
	bloom.Threshold = if th.Night then 2 else 1.8
	local cc = getOrMake("ColorCorrectionEffect", "GoTrackColor", Lighting)
	cc.Saturation = L.Saturation
	cc.Contrast = 0.08
	cc.Brightness = if th.Night then 0.06 else 0.01
	cc.TintColor = L.Tint
	local rays = getOrMake("SunRaysEffect", "GoTrackRays", Lighting)
	rays.Enabled = q >= 3
	rays.Intensity = if th.Night then 0 else 0.05
	rays.Spread = 0.6
	local dof = getOrMake("DepthOfFieldEffect", "GoTrackDOF", Lighting)
	dof.Enabled = q >= 4
	dof.FarIntensity = 0.12
	dof.FocusDistance = 200
	dof.InFocusRadius = 400
	dof.NearIntensity = 0
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = getOrMake("Clouds", "GoTrackClouds", terrain)
		clouds.Enabled = q >= 2
		clouds.Cover = L.Cloud
		clouds.Density = 0.7
		clouds.Color = if th.Night then Color3.fromRGB(100, 105, 135) else Color3.new(1, 1, 1)
	end
end

local function startWeather(th, folder, q)
	if not th.Weather then
		return nil
	end
	local emitterPart = P(folder, Vector3.new(220, 1, 220), CFrame.new(0, 80, 0), Color3.new(1, 1, 1))
	emitterPart.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.EmissionDirection = Enum.NormalId.Bottom
	local rateMul = ({ 0.35, 0.6, 1, 1.2 })[q] or 1
	if th.Weather == "rain" then
		pe.Color = ColorSequence.new(Color3.fromRGB(190, 205, 230))
		pe.Transparency = NumberSequence.new(0.35)
		pe.Size = NumberSequence.new(0.12)
		pe.Squash = NumberSequence.new(-3)
		pe.Rate = 700 * rateMul
		pe.Lifetime = NumberRange.new(0.9, 1.1)
		pe.Speed = NumberRange.new(90, 110)
	elseif th.Weather == "snow" then
		pe.Color = ColorSequence.new(Color3.new(1, 1, 1))
		pe.Size = NumberSequence.new(0.4)
		pe.Rate = 260 * rateMul
		pe.Lifetime = NumberRange.new(5, 7)
		pe.Speed = NumberRange.new(10, 16)
		pe.SpreadAngle = Vector2.new(15, 15)
		pe.Acceleration = Vector3.new(4, 0, 2)
	else
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 140, 60), Color3.fromRGB(120, 110, 110))
		pe.LightEmission = 0.6
		pe.Size = NumberSequence.new(0.35)
		pe.Rate = 120 * rateMul
		pe.Lifetime = NumberRange.new(4, 6)
		pe.Speed = NumberRange.new(6, 12)
		pe.Acceleration = Vector3.new(6, 2, 3)
	end
	pe.Parent = emitterPart
	return RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if cam and emitterPart.Parent then
			emitterPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 50, 0))
		end
	end)
end

-- Ambient particles that follow the camera: petals, leaves, pollen, sand, mist,
-- fireflies, embers, confetti (Themes.Ambient)
local AMBIENT = {
	petals = { Colors = { Color3.fromRGB(255, 180, 210), Color3.fromRGB(255, 215, 230) }, Rate = 40, Size = 0.35, Speed = { 3, 6 }, Life = { 6, 9 }, Acc = Vector3.new(3, -1.5, 1.5), Rot = true },
	petals_mixed = { Colors = { Color3.fromRGB(255, 80, 90), Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 140, 200), Color3.fromRGB(255, 150, 40) }, Rate = 26, Size = 0.3, Speed = { 3, 6 }, Life = { 6, 9 }, Acc = Vector3.new(4, -1.5, 1), Rot = true },
	leaves = { Colors = { Color3.fromRGB(230, 100, 30), Color3.fromRGB(250, 170, 40), Color3.fromRGB(200, 50, 30) }, Rate = 30, Size = 0.5, Speed = { 3, 6 }, Life = { 6, 9 }, Acc = Vector3.new(3, -2, 2), Rot = true },
	pollen = { Colors = { Color3.fromRGB(255, 250, 210), Color3.fromRGB(255, 255, 255) }, Rate = 30, Size = 0.18, Speed = { 1, 2 }, Life = { 6, 10 }, Acc = Vector3.new(1, 0.2, 0.5), Glow = 0.4 },
	sand = { Colors = { Color3.fromRGB(230, 200, 150), Color3.fromRGB(215, 180, 130) }, Rate = 90, Size = 0.22, Speed = { 30, 45 }, Life = { 1.5, 2.5 }, Acc = Vector3.new(0, -2, 0), Dir = Enum.NormalId.Right, Transparency = 0.45 },
	mist = { Colors = { Color3.fromRGB(235, 240, 240) }, Rate = 6, Size = 14, Speed = { 1, 2 }, Life = { 8, 12 }, Acc = Vector3.new(0.6, 0, 0.3), Transparency = 0.85, Low = true, Smoke = true },
	fireflies = { Colors = { Color3.fromRGB(210, 255, 120), Color3.fromRGB(255, 240, 140) }, Rate = 18, Size = 0.25, Speed = { 0.5, 1.5 }, Life = { 3, 5 }, Acc = Vector3.new(0, 0.3, 0), Glow = 1, Low = true },
	embers = { Colors = { Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 90, 20) }, Rate = 40, Size = 0.28, Speed = { 2, 5 }, Life = { 3, 5 }, Acc = Vector3.new(2, 4, 1), Glow = 1, Low = true },
	confetti = { Colors = { Color3.fromRGB(230, 40, 60), Color3.fromRGB(40, 170, 90), Color3.fromRGB(255, 210, 40), Color3.fromRGB(60, 120, 230), Color3.fromRGB(255, 120, 200) }, Rate = 20, Size = 0.3, Speed = { 2, 4 }, Life = { 5, 8 }, Acc = Vector3.new(1, -2.5, 1), Rot = true },
}

local function startAmbient(th, folder, q)
	local a = th.Ambient and AMBIENT[th.Ambient]
	if not a or q < 2 then
		return nil
	end
	local emitterPart = P(folder, Vector3.new(180, 1, 180), CFrame.new(0, 40, 0), Color3.new(1, 1, 1))
	emitterPart.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.EmissionDirection = a.Dir or Enum.NormalId.Bottom
	local keys = {}
	for i, c in a.Colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #a.Colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, a.Colors[1]))
	end
	pe.Color = ColorSequence.new(keys)
	pe.Size = NumberSequence.new(a.Size)
	pe.Transparency = NumberSequence.new(a.Transparency or 0.1)
	pe.Rate = a.Rate * (({ 0.35, 0.6, 1, 1.3 })[q] or 1)
	pe.Lifetime = NumberRange.new(a.Life[1], a.Life[2])
	pe.Speed = NumberRange.new(a.Speed[1], a.Speed[2])
	pe.Acceleration = a.Acc
	pe.SpreadAngle = Vector2.new(30, 30)
	pe.LightEmission = a.Glow or 0
	if a.Rot then
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-120, 120)
		pe.Squash = NumberSequence.new(-0.5)
	end
	if a.Smoke then
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	end
	pe.Parent = emitterPart
	local height = if a.Low then 6 else 40
	return RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if cam and emitterPart.Parent then
			emitterPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, height, 0))
		end
	end)
end

-- Fireworks over the circuit every few seconds (party circuits at night)
local function startFireworks(folder, cx, cz, span, q)
	if q < 2 then
		return
	end
	task.spawn(function()
		local rng = Random.new()
		while folder.Parent do
			task.wait(rng:NextNumber(2.5, 5))
			if not folder.Parent then
				break
			end
			local pos = Vector3.new(cx + rng:NextNumber(-span * 0.4, span * 0.4), rng:NextNumber(130, 220), cz + rng:NextNumber(-span * 0.4, span * 0.4))
			local anchor = P(folder, Vector3.new(1, 1, 1), CFrame.new(pos), Color3.new(1, 1, 1))
			anchor.Transparency = 1
			local hue = rng:NextNumber()
			local pe = Instance.new("ParticleEmitter")
			pe.Enabled = false
			pe.Color = ColorSequence.new(Color3.fromHSV(hue, 0.8, 1), Color3.fromHSV((hue + 0.12) % 1, 0.5, 1))
			pe.LightEmission = 1
			pe.Size = NumberSequence.new(2.4, 0)
			pe.Lifetime = NumberRange.new(1.2, 2)
			pe.Speed = NumberRange.new(50, 80)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Drag = 2
			pe.Acceleration = Vector3.new(0, -18, 0)
			pe.Parent = anchor
			pe:Emit(if q >= 3 then 140 else 70)
			local flash = Instance.new("PointLight")
			flash.Color = Color3.fromHSV(hue, 0.6, 1)
			flash.Range = 60
			flash.Brightness = 4
			flash.Parent = anchor
			task.delay(0.25, function()
				flash:Destroy()
			end)
			task.delay(3, function()
				anchor:Destroy()
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- Road geometry helpers
---------------------------------------------------------------------------
local ROAD_LIFT = 0.6

-- segment break points: split when the heading OR the slope changes enough
local function breakpoints(t): { number }
	local pts = { 1 }
	local i = 1
	while i < t.N do
		local j = i + 1
		local turn = 0
		while j < t.N and j - i < 7 do
			turn += math.abs(t.K[j]) * Track.DS
			local pitchChange = math.abs(t.TY[j] - t.TY[i])
			if (turn > math.rad(3) or pitchChange > 0.025) and j - i >= 2 then
				break
			end
			j += 1
		end
		if t.N - j < 2 then
			j = t.N
		end
		table.insert(pts, j)
		i = j
	end
	return pts
end

local function pos(t, i: number, lateral: number?, lift: number?): Vector3
	i = Track.Wrap(t, i)
	local l = lateral or 0
	return Vector3.new(t.X[i] + t.RX[i] * l, t.Y[i] + (lift or ROAD_LIFT), t.Z[i] + t.RZ[i] * l)
end

-- strip between samples a and b at a lateral offset (latB optional for tapering)
local function strip(parent, t, a, b, lateral, width, thick, topLift, color, material, name, collide, ext, latB)
	local pa = pos(t, a, lateral, topLift)
	local pb = pos(t, b, latB or lateral, topLift)
	local dir = pb - pa
	local len = dir.Magnitude
	if len < 0.1 then
		return nil
	end
	local mid = (pa + pb) / 2
	local cf = CFrame.lookAt(mid, pb) * CFrame.new(0, -thick / 2, 0)
	return P(parent, Vector3.new(width, thick, len + (ext or 0.4)), cf, color, material, name, collide)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
-- onProgress(stage, fraction) is called as each part of the world goes up (intro screen)
function CircuitBuilder.Build(trackId: string, quality: number?, onProgress: ((string, number) -> ())?)
	local function progress(stage: string, frac: number)
		if onProgress then
			pcall(onProgress, stage, frac)
		end
	end
	CircuitBuilder.Clear()
	local t = Track.Get(trackId)
	assert(t, "Unknown circuit " .. tostring(trackId))
	local def = t.Def
	local th = Themes[def.Theme] or Themes.park
	partCounter = 0
	local q = math.clamp(math.floor(tonumber(quality) or 3), 1, 4)
	local dens = QUALITY_DENSITY[q] * th.Density
	-- Blender world meshes (buildings, trees, mountains, cars) once imported in Studio
	meshesOn = WorldMeshes.Available()
	Arch.MeshHook = if meshesOn then MESH else nil

	local folder = Instance.new("Folder")
	folder.Name = "GoTrackCircuit"
	local surface = Instance.new("Folder")
	surface.Name = "Surface"
	surface.Parent = folder
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = folder
	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = folder
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = folder
	folder.Parent = workspace

	CircuitBuilder.ApplyLighting(th, q)
	progress("Laying the tarmac", 0.04)
	local rng = Random.new(#def.Id * 131 + t.N)
	local W = t.Width
	local street = th.Barrier == "street"
	local night = th.Night
	local clear = buildClearance(t)
	local occ = newOccupancy()
	local BARRIER = if street then W / 2 + 7 else W / 2 + 22

	-- which side is the infield? (positive total curvature = clockwise = infield on the right)
	local sumK = 0
	for i = 1, t.N do
		sumK += t.K[i]
	end
	local inSide = sign(sumK)
	local outSide = -inSide

	-- braking zones: sample indexes where the ideal speed is dropping hard
	local braking = {}
	for i = 1, t.N do
		local ahead = t.V[Track.Wrap(t, i + 12)]
		braking[i] = t.V[i] - ahead > 25
	end

	-- ground ----------------------------------------------------------------
	local b = t.Bounds
	local cx, cz = (b[1] + b[2]) / 2, (b[3] + b[4]) / 2
	local halfX = (b[2] - b[1]) / 2 + 2300
	local halfZ = (b[4] - b[3]) / 2 + 2300
	local tile = 2000
	for i = 0, math.ceil(halfX * 2 / tile) - 1 do
		for j = 0, math.ceil(halfZ * 2 / tile) - 1 do
			P(surface, Vector3.new(tile, 4, tile), CFrame.new(cx - halfX + tile * (i + 0.5), -2, cz - halfZ + tile * (j + 0.5)), th.Ground, th.GroundMaterial, "Grass", true)
		end
	end

	local lineColor = Color3.fromRGB(245, 245, 245)
	local lineMat = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local lineCol = if night then Color3.fromRGB(205, 208, 215) else lineColor

	-- road, lines, run-off, barriers (per smooth segment) --------------------
	local bp = breakpoints(t)
	local nSeg = #bp
	local barrierCount = 0
	for s = 1, nSeg do
		local a = bp[s]
		local bIdx = if s == nSeg then t.N + 1 else bp[s + 1]
		local ia = Track.Wrap(t, a)
		local ib = Track.Wrap(t, bIdx)
		local h1 = math.atan2(t.TX[ia], t.TZ[ia])
		local h2 = math.atan2(t.TX[ib], t.TZ[ib])
		local dh = math.abs(((h2 - h1 + math.pi) % (2 * math.pi)) - math.pi)
		local tanH = math.tan(math.min(dh, 0.6) / 2)
		local ext = W * tanH + 0.6
		-- length extension that closes the joint gap on the OUTSIDE of a bend for a strip
		-- centred at `lat` with width `w` (straight boxes on a curve leave wedge-shaped holes)
		local function ex(lat: number, w: number): number
			return 2 * (math.abs(lat) + w / 2) * tanH + 0.6
		end
		local mid = Track.Wrap(t, math.floor((a + bIdx) / 2))
		local k = t.K[mid]
		local over = t.Over[mid]
		local roadTop = t.Y[mid] + ROAD_LIFT
		local cornerSide = -sign(k) -- outside of the bend

		strip(surface, t, a, bIdx, 0, W, if over then 3 else 1.4, ROAD_LIFT, th.Road, Enum.Material.Asphalt, "Road", true, ext)
		-- rubbered-in racing line
		local rlA, rlB = t.RL[ia], t.RL[ib]
		local rub = strip(deco, t, a, bIdx, rlA, 6, 0.05, ROAD_LIFT + 0.02, th.Road:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Asphalt, "Rubber", false, ext * 0.5, rlB)
		if rub then
			rub.Transparency = 0.35
		end
		-- edge lines
		for side = -1, 1, 2 do
			strip(deco, t, a, bIdx, side * (W / 2 - 1.3), 0.9, 0.08, ROAD_LIFT + 0.04, lineCol, lineMat, "Line", false, ex(W / 2 - 1.3, 0.9) - 0.4)
		end

		if over then
			for side = -1, 1, 2 do
				strip(walls, t, a, bIdx, side * (W / 2 + 1.2), 1.6, 5, ROAD_LIFT + 4.4, Color3.fromRGB(205, 205, 210), Enum.Material.Concrete, "Wall", true, ex(W / 2 + 1.2, 1.6))
				strip(deco, t, a, bIdx, side * (W / 2 + 1.2), 1.8, 1, ROAD_LIFT - 2.2, th.Accent, Enum.Material.SmoothPlastic, "Girder", false, ex(W / 2 + 1.2, 1.8))
			end
		elseif street then
			for side = -1, 1, 2 do
				strip(surface, t, a, bIdx, side * (W / 2 + 3.5), 7, 1, ROAD_LIFT + 0.05, Color3.fromRGB(150, 152, 158), Enum.Material.Asphalt, "Runoff", true, ex(W / 2 + 3.5, 7))
			end
			if roadTop > 3 then
				for side = -1, 1, 2 do
					strip(deco, t, a, bIdx, side * (W / 2 + 4), W / 2 + 10, roadTop, ROAD_LIFT - 1.2, Color3.fromRGB(150, 145, 140), Enum.Material.Brick, "Base", false, 0.4)
				end
			end
		else
			for side = -1, 1, 2 do
				local outer = side == cornerSide and math.abs(k) > 1 / 520
				local runW = BARRIER - W / 2
				if th.RunoffKind == "asphalt" then
					strip(surface, t, a, bIdx, side * (W / 2 + runW / 2), runW, 1.2, ROAD_LIFT - 0.05, th.Road:Lerp(Color3.fromRGB(80, 110, 160), 0.18), Enum.Material.Asphalt, "Runoff", true, ex(W / 2 + runW / 2, runW))
				elseif outer then
					strip(surface, t, a, bIdx, side * (W / 2 + 2.5), 5, 1.2, ROAD_LIFT - 0.05, th.Runoff, th.RunoffMaterial, "Grass", true, ex(W / 2 + 2.5, 5))
					strip(surface, t, a, bIdx, side * (W / 2 + 5 + (runW - 5) / 2), runW - 5, 1.2, ROAD_LIFT - 0.1, Color3.fromRGB(214, 198, 160), Enum.Material.Pebble, "Gravel", true, ex(W / 2 + 5 + (runW - 5) / 2, runW - 5))
				else
					strip(surface, t, a, bIdx, side * (W / 2 + runW / 2), runW, 1.2, ROAD_LIFT - 0.05, th.Runoff, th.RunoffMaterial, "Grass", true, ex(W / 2 + runW / 2, runW))
				end
				-- embankment down to the ground for raised sections
				if roadTop > 1.5 then
					local d = roadTop * 1.4
					local e1 = pos(t, ia, side * (BARRIER + 2), ROAD_LIFT - 0.1)
					local e2 = pos(t, ib, side * (BARRIER + 2), ROAD_LIFT - 0.1)
					local em = (e1 + e2) / 2
					local fwd = (e2 - e1)
					local len = fwd.Magnitude
					if len > 0.1 then
						fwd = fwd.Unit
						local rgt = Vector3.new(t.RX[mid], 0, t.RZ[mid]) * side
						local foot = em + rgt * d - Vector3.new(0, em.Y, 0)
						local across = foot - em
						local acrossLen = across.Magnitude
						local ax = across.Unit
						local up = fwd:Cross(ax)
						if up.Y < 0 then
							up = -up
						end
						local center = (em + foot) / 2 - up * 0.6
						local zAxis = ax:Cross(up)
						P(surface, Vector3.new(acrossLen, 1.2, len + 1.5), CFrame.fromMatrix(center, ax, up, zAxis), th.Runoff:Lerp(th.Ground, 0.5), th.GroundMaterial, "Grass", true)
					end
				end
			end
		end

		-- BARRIERS on both sides -------------------------------------------------
		if not over then
			for side = -1, 1, 2 do
				local inner = side ~= cornerSide
				local skip = inner and math.abs(k) * BARRIER > 0.5
				if not skip then
					-- don't let a wall cut across another part of the track
					local pa = pos(t, ia, side * BARRIER, 0)
					local pb = pos(t, ib, side * BARRIER, 0)
					local pm = (pa + pb) / 2
					local minD = W / 2 + 4
					if not (clear(pa.X, pa.Z, minD, ia, 45) and clear(pb.X, pb.Z, minD, ib, 45) and clear(pm.X, pm.Z, minD, mid, 45)) then
						skip = true
					end
				end
				if not skip then
					barrierCount += 1
					local lat = side * BARRIER
					-- invisible solid collider
					local col = strip(walls, t, a, bIdx, lat, 1.6, 7, ROAD_LIFT + 5.5, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, "Wall", true, ex(lat, 1.6))
					if col then
						col.Transparency = 1
						col.CanQuery = false
					end
					local kind
					if street then
						kind = "concrete"
					elseif not inner and braking[mid] and math.abs(k) > 1 / 300 then
						kind = "tecpro"
					elseif not inner and math.abs(k) > 1 / 520 then
						kind = "tyres"
					else
						kind = "armco"
					end
					if kind == "concrete" then
						local wall = strip(deco, t, a, bIdx, lat, 1.6, 4.4, ROAD_LIFT + 3.9, if s % 4 == 0 then th.Accent else Color3.fromRGB(236, 236, 236), Enum.Material.Concrete, "WallV", false, ex(lat, 1.6))
						strip(deco, t, a, bIdx, lat, 1.7, 0.5, ROAD_LIFT + 4.3, if s % 2 == 0 then Color3.fromRGB(220, 30, 40) else Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic, "WallTop", false, ex(lat, 1.7))
						if q >= 2 then
							-- debris catch fence: posts + cables (a translucent slab read as a
							-- see-through wall, so it is drawn as an open frame instead)
							local fl = lat + side * 0.6
							local fenceCol = Color3.fromRGB(70, 74, 80)
							for _, h in { 7.4, 11.2 } do
								strip(deco, t, a, bIdx, fl, 0.12, 0.12, ROAD_LIFT + h, fenceCol, Enum.Material.Metal, "FenceCable", false, ex(fl, 0.12))
							end
							if s % 2 == 0 then
								local pp = pos(t, ia, fl, ROAD_LIFT)
								P(deco, Vector3.new(0.35, 7.4, 0.35), CFrame.new(pp + Vector3.new(0, 7.6, 0)), fenceCol, Enum.Material.Metal, "FencePost")
							end
						end
						if wall and s % 7 == 0 then
							local brand = BRANDS[(s // 7) % #BRANDS + 1]
							textGui(wall, if side > 0 then Enum.NormalId.Left else Enum.NormalId.Right, brand[1], brand[2], Color3.fromRGB(20, 20, 25))
						end
					elseif kind == "armco" then
						strip(deco, t, a, bIdx, lat, 0.35, 0.8, ROAD_LIFT + 2.6, Color3.fromRGB(205, 210, 215), Enum.Material.Metal, "Armco", false, ex(lat, 0.35))
						strip(deco, t, a, bIdx, lat, 0.35, 0.8, ROAD_LIFT + 1.6, Color3.fromRGB(205, 210, 215), Enum.Material.Metal, "Armco", false, ex(lat, 0.35))
						strip(deco, t, a, bIdx, lat + side * 0.4, 0.25, 2.6, ROAD_LIFT + 2.6, Color3.fromRGB(80, 84, 90), Enum.Material.Metal, "ArmcoPost", false, ex(lat + side * 0.4, 0.25))
					elseif kind == "tyres" then
						strip(deco, t, a, bIdx, lat, 2, 2.8, ROAD_LIFT + 2.8, Color3.fromRGB(24, 24, 26), Enum.Material.Fabric, "Tyres", false, ex(lat, 2))
						local beltColors = { Color3.fromRGB(220, 35, 35), Color3.fromRGB(245, 245, 245), Color3.fromRGB(30, 90, 220), Color3.fromRGB(255, 200, 30) }
						strip(deco, t, a, bIdx, lat - side * 0.1, 2.05, 1.1, ROAD_LIFT + 2.3, if s % 2 == 0 then beltColors[1] else beltColors[2], Enum.Material.SmoothPlastic, "Belt", false, ex(lat - side * 0.1, 2.05))
					else -- tecpro blocks
						local pa = pos(t, ia, lat, ROAD_LIFT)
						local pb = pos(t, ib, lat, ROAD_LIFT)
						local len = (pb - pa).Magnitude
						local n = math.max(1, math.floor(len / 5))
						for kk = 0, n - 1 do
							local p0 = pa:Lerp(pb, (kk + 0.5) / n)
							local cfb = CFrame.lookAt(p0, pb) * CFrame.new(0, 1.3, 0)
							P(deco, Vector3.new(2.4, 2.6, len / n - 0.3), cfb, if kk % 2 == 0 then Color3.fromRGB(220, 40, 40) else Color3.fromRGB(40, 90, 210), Enum.Material.SmoothPlastic, "TecPro")
						end
					end
				end
			end
		end
	end

	progress("Painting kerbs and run-off", 0.28)
	-- kerbs: red/white stripes on corners, sausage kerbs at tight apexes -----------
	for i = 1, t.N do
		local k = t.K[i]
		if math.abs(k) > 1 / 420 and not t.Over[i] then
			local j = i + 1
			for side = -1, 1, 2 do
				local kerb = strip(surface, t, i, j, side * (W / 2 + 1.2), 3, 0.5, ROAD_LIFT + 0.12, if i % 2 == 0 then th.KerbA else th.KerbB, Enum.Material.SmoothPlastic, "Kerb", true, 0.05)
				local _ = kerb
			end
			-- sausage kerb on the inside of tight corners
			if math.abs(k) > 1 / 140 and i % 3 == 0 then
				local insideLat = sign(k) * (W / 2 + 3.4)
				strip(deco, t, i, j, insideLat, 1.2, 0.7, ROAD_LIFT + 0.45, Color3.fromRGB(255, 205, 30), Enum.Material.SmoothPlastic, "Sausage", false, -2)
			end
			-- painted run-off stripes on asphalt run-off (outside of the bend)
			if th.RunoffKind == "asphalt" and not street and i % 2 == 0 then
				local outLat = -sign(k) * (W / 2 + 6.5)
				strip(deco, t, i, j, outLat, 7, 0.06, ROAD_LIFT - 0.02, if i % 4 == 0 then Color3.fromRGB(220, 50, 50) else Color3.fromRGB(40, 110, 220), Enum.Material.SmoothPlastic, "Paint", false, 0)
			end
		end
	end

	-- skid marks into the braking zones
	for i = 1, t.N, 2 do
		if braking[i] and not braking[Track.Wrap(t, i - 2)] then
			for kk = 0, 5 do
				local ii = i + kk * 2
				for side = -1, 1, 2 do
					local lat = t.RL[Track.Wrap(t, ii)] + side * 2.2
					local m = strip(deco, t, ii, ii + 2, lat, 0.8, 0.04, ROAD_LIFT + 0.03, Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic, "Skid", false, 0)
					if m then
						m.Transparency = 0.5 + kk * 0.07
					end
				end
			end
		end
	end

	progress("Building the pit lane and grandstands", 0.4)
	-- start / finish -------------------------------------------------------------
	local lights = {}
	do
		local base = CFrame.lookAt(pos(t, 1), pos(t, 2))
		for row = 0, 1 do
			for col = 0, 15 do
				local black = (row + col) % 2 == 0
				local x = -W / 2 + W / 32 + col * W / 16
				P(deco, Vector3.new(W / 16, 0.08, 1.8), base * CFrame.new(x, 0.05, -0.9 + row * 1.8), if black then Color3.fromRGB(15, 15, 15) else Color3.new(1, 1, 1), nil, "Line")
			end
		end
		local gantryH = 22
		for side = -1, 1, 2 do
			P(deco, Vector3.new(3, gantryH, 3), base * CFrame.new(side * (W / 2 + 5), gantryH / 2 - ROAD_LIFT, -8), Color3.fromRGB(40, 42, 50), Enum.Material.Metal)
		end
		local beam = P(deco, Vector3.new(W + 13, 5, 3), base * CFrame.new(0, gantryH, -8), Color3.fromRGB(30, 32, 38), Enum.Material.Metal)
		textGui(beam, Enum.NormalId.Back, "GOTRACK RACING", Color3.fromRGB(255, 180, 40))
		textGui(beam, Enum.NormalId.Front, def.Name:upper(), Color3.new(1, 1, 1))
		for kk = 1, 5 do
			local pod = P(deco, Vector3.new(3.2, 6, 1.4), base * CFrame.new((kk - 3) * 4.4, gantryH - 5.5, -6.6), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
			local lamps = {}
			for r = 0, 1 do
				local lamp = P(deco, Vector3.new(0.4, 2, 2), pod.CFrame * CFrame.new(0, 1.4 - r * 2.8, 0.75) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(60, 10, 10), Enum.Material.SmoothPlastic, "Lamp", false, Enum.PartType.Cylinder)
				table.insert(lamps, lamp)
			end
			lights[kk] = lamps
		end
		-- grid boxes with numbers
		for slot = 1, 10 do
			local s, lat = Track.GridSlot(t, slot)
			local idx = Track.Wrap(t, math.floor(s / Track.DS) + 1)
			local gcf = CFrame.lookAt(pos(t, idx, lat), pos(t, idx + 1, lat))
			P(deco, Vector3.new(9, 0.08, 0.7), gcf * CFrame.new(0, 0.05, -5.5), Color3.new(1, 1, 1), nil, "Line")
			P(deco, Vector3.new(0.6, 0.08, 3), gcf * CFrame.new(-4.2, 0.05, -4.3), Color3.new(1, 1, 1), nil, "Line")
			P(deco, Vector3.new(0.6, 0.08, 3), gcf * CFrame.new(4.2, 0.05, -4.3), Color3.new(1, 1, 1), nil, "Line")
			local num = P(deco, Vector3.new(4, 0.06, 3), gcf * CFrame.new(0, 0.05, -8.6), Color3.new(1, 1, 1), nil, "Line")
			num.Transparency = 1
			textGui(num, Enum.NormalId.Top, tostring(slot), Color3.new(1, 1, 1))
		end
	end

	local reserved = {}
	local function reserve(p: Vector3, radius: number)
		table.insert(reserved, { p, radius })
		occ.add(p.X, p.Z, radius)
	end

	local function alongStraight(fromS: number, toS: number, lateral: number, height: number, depth: number, color: Color3, material: Enum.Material, name: string?, yOff: number?)
		local ia2 = Track.Wrap(t, math.floor(fromS / Track.DS) + 1)
		local ib2 = Track.Wrap(t, math.floor(toS / Track.DS) + 1)
		local pa = pos(t, ia2, lateral, 0)
		local pb = pos(t, ib2, lateral, 0)
		local m = (pa + pb) / 2
		local cf = CFrame.lookAt(m, pb)
		return P(deco, Vector3.new(depth, height, (pb - pa).Magnitude), cf * CFrame.new(0, height / 2 + (yOff or 0), 0), color, material, name), cf
	end

	-- crowd blocks on a stand row
	local function crowd(cf: CFrame, length: number, rowY: number, rowX: number, prob: number)
		local n = math.floor(length / 3.2)
		local run = nil
		for c = 0, n - 1 do
			if rng:NextNumber() < prob then
				local shirt = if rng:NextNumber() < 0.65 then th.Fans[rng:NextInteger(1, #th.Fans)] else Color3.fromHSV(rng:NextNumber(), rng:NextNumber(0.4, 0.8), rng:NextNumber(0.75, 1))
				P(deco, Vector3.new(2, 2.4, 2.4), cf * CFrame.new(rowX, rowY + 1.2, -length / 2 + 1.6 + c * 3.2), shirt, Enum.Material.SmoothPlastic)
			end
			local _ = run
		end
	end

	-- grandstand. cf: centre on the ground, LookVector along the stand; facing = +1 track on +X
	local function stand(cf: CFrame, length: number, facing: number, rows: number)
		for kk = -1, 1 do
			reserve((cf * CFrame.new(-facing * 18, 0, kk * length / 3)).Position, length / 3 + 22)
		end
		for row = 0, rows - 1 do
			P(deco, Vector3.new(6, 2.5 + row * 3, length), cf * CFrame.new(-facing * (row * 5), (2.5 + row * 3) / 2, 0), Color3.fromRGB(205, 206, 212), Enum.Material.Concrete)
			local seat = P(deco, Vector3.new(5, 0.4, length), cf * CFrame.new(-facing * (row * 5), 2.7 + row * 3, 0), if row % 2 == 0 then th.Accent else th.Accent:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.SmoothPlastic)
			local _ = seat
			crowd(cf * CFrame.new(-facing * (row * 5), 0, 0), length, 2.9 + row * 3, 0, 0.35 + 0.5 * math.min(1, dens) * th.Crowd)
		end
		local roofY = 4 + rows * 3 + 4
		P(deco, Vector3.new(rows * 5 + 10, 1.5, length + 4), cf * CFrame.new(-facing * (rows * 2.5), roofY, 0), Color3.fromRGB(240, 242, 246), Enum.Material.Metal)
		P(deco, Vector3.new(rows * 5 + 10.2, 2.4, 1), cf * CFrame.new(-facing * (rows * 2.5), roofY - 0.4, -length / 2 - 2), th.Accent, Enum.Material.SmoothPlastic)
		for c = 0, 3 do
			P(deco, Vector3.new(1, roofY, 1), cf * CFrame.new(-facing * (rows * 5 + 2), roofY / 2, -length / 2 + c * length / 3), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
		end
		local brand = BRANDS[rng:NextInteger(1, #BRANDS)]
		local fascia = P(deco, Vector3.new(0.6, 3, length * 0.7), cf * CFrame.new(facing * 3.4, 1.5, 0), Color3.fromRGB(20, 22, 30))
		textGui(fascia, if facing > 0 then Enum.NormalId.Right else Enum.NormalId.Left, brand[1], brand[2], Color3.fromRGB(20, 22, 30))
	end

	-- pit lane, garages and paddock (outside of the main straight) -------------------
	local straightS = 0
	local pitLat = outSide * (BARRIER + 16)
	local okPit = true
	for s2 = -300, 240, 40 do
		local x, _, z = Track.PointAt(t, s2, outSide * (BARRIER + 40))
		if not clear(x, z, BARRIER + 14) then
			okPit = false
		end
	end
	if okPit then
		for s2 = -300, 240, 50 do
			local x, _, z = Track.PointAt(t, s2, outSide * (BARRIER + 34))
			reserve(Vector3.new(x, 0, z), 40)
		end
		-- pit lane asphalt + lines + boxes
		alongStraight(straightS - 300, straightS + 240, pitLat, 0.4, 20, th.Road, Enum.Material.Asphalt, nil, ROAD_LIFT - 0.5)
		alongStraight(straightS - 300, straightS + 240, pitLat - outSide * 10, 0.1, 0.6, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, nil, ROAD_LIFT - 0.05)
		for g = 0, 9 do
			local sg = straightS - 270 + g * 50
			local x, y, z, tx, _, tz = Track.PointAt(t, sg, pitLat + outSide * 6)
			local gcf = CFrame.lookAt(Vector3.new(x, y + ROAD_LIFT - 0.02, z), Vector3.new(x + tx, y + ROAD_LIFT - 0.02, z + tz))
			P(deco, Vector3.new(8, 0.06, 0.4), gcf * CFrame.new(0, 0, -6), Color3.fromRGB(255, 210, 40))
			P(deco, Vector3.new(8, 0.06, 0.4), gcf * CFrame.new(0, 0, 6), Color3.fromRGB(255, 210, 40))
		end
		-- pit entry / exit lanes angled towards the track
		for _, e in { { straightS - 300, straightS - 420 }, { straightS + 240, straightS + 360 } } do
			local x1, y1, z1 = Track.PointAt(t, e[1], pitLat)
			local x2, y2, z2 = Track.PointAt(t, e[2], outSide * (W / 2 + 12))
			local p1, p2 = Vector3.new(x1, y1 + ROAD_LIFT - 0.3, z1), Vector3.new(x2, y2 + ROAD_LIFT - 0.3, z2)
			P(deco, Vector3.new(14, 0.4, (p2 - p1).Magnitude + 4), CFrame.lookAt((p1 + p2) / 2, p2), th.Road, Enum.Material.Asphalt)
		end
		-- garage building
		local garage = alongStraight(straightS - 300, straightS + 240, outSide * (BARRIER + 42), 18, 28, Color3.fromRGB(238, 239, 244), Enum.Material.Concrete)
		textGui(garage, if outSide > 0 then Enum.NormalId.Left else Enum.NormalId.Right, "PIT LANE  •  " .. def.Name:upper(), th.Accent, Color3.fromRGB(24, 26, 32))
		alongStraight(straightS - 300, straightS + 240, outSide * (BARRIER + 42), 2, 32, th.Accent, Enum.Material.SmoothPlastic, nil, 18)
		for g = 0, 9 do
			local sg = straightS - 270 + g * 50
			local x, y, z, tx, _, tz = Track.PointAt(t, sg, outSide * (BARRIER + 27.8))
			local gcf = CFrame.lookAt(Vector3.new(x, y + 6.5, z), Vector3.new(x + tx, y + 6.5, z + tz))
			local teamCol = Color3.fromHSV(g / 10, 0.75, 0.92)
			P(deco, Vector3.new(0.4, 12, 36), gcf, Color3.fromRGB(40, 44, 54))
			P(deco, Vector3.new(0.5, 2, 36), gcf * CFrame.new(0, 7, 0), teamCol)
		end
		-- hospitality tents behind the garages
		for kk = 0, 3 do
			local x, y, z = Track.PointAt(t, straightS - 200 + kk * 120, outSide * (BARRIER + 86))
			if clear(x, z, BARRIER + 40) then
				local tcf = CFrame.new(x, y, z)
				P(deco, Vector3.new(28, 7, 20), tcf * CFrame.new(0, 3.5, 0), Color3.fromRGB(250, 250, 250), Enum.Material.Fabric)
				P(deco, Vector3.new(29, 3, 21), tcf * CFrame.new(0, 8.5, 0), Color3.fromHSV(kk / 4, 0.5, 0.95), Enum.Material.Fabric)
			end
		end
	end

	-- main grandstand opposite the pits + corner grandstands ----------------------------
	do
		local lat = inSide * (BARRIER + 12)
		local ok = true
		for s2 = -170, 170, 40 do
			local x, _, z = Track.PointAt(t, s2, lat + inSide * 20)
			if not clear(x, z, BARRIER + 8) then
				ok = false
			end
		end
		if ok then
			local x1, _, z1 = Track.PointAt(t, -170, lat)
			local x2, _, z2 = Track.PointAt(t, 170, lat)
			local cf = CFrame.lookAt(Vector3.new((x1 + x2) / 2, 0, (z1 + z2) / 2), Vector3.new(x2, 0, z2))
			stand(cf, 320, -inSide, 8)
			-- big screen
			local sx, _, sz = Track.PointAt(t, 220, lat + inSide * 10)
			if clear(sx, sz, BARRIER + 6) then
				P(deco, Vector3.new(2, 26, 2), CFrame.new(sx, 13, sz), Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
				local _, _, _, tx, _, tz = Track.PointAt(t, 220, 0)
				local scr = P(deco, Vector3.new(30, 16, 1), CFrame.lookAt(Vector3.new(sx, 32, sz), Vector3.new(sx - tx * 10 - inSide * t.RX[1] * 30, 32, sz - tz * 10 - inSide * t.RZ[1] * 30)), Color3.fromRGB(15, 16, 22))
				textGui(scr, Enum.NormalId.Front, "LIVE  •  " .. def.Name:upper(), th.Accent, Color3.fromRGB(14, 16, 26))
			end
		end
	end
	do
		local candidates = {}
		for i = 1, t.N, 6 do
			table.insert(candidates, i)
		end
		table.sort(candidates, function(a2, c)
			return math.abs(t.K[a2]) > math.abs(t.K[c])
		end)
		local placed = {}
		local want = math.floor(3 + 4 * math.min(1, dens))
		for _, i in candidates do
			if #placed >= want then
				break
			end
			local far = true
			for _, j in placed do
				if math.abs(Track.IndexDelta(t, i, j)) < 110 then
					far = false
				end
			end
			if far and math.abs(t.K[i]) > 1 / 320 then
				local side = -sign(t.K[i])
				local lat = side * (BARRIER + 16)
				local x, _, z, tx, _, tz = Track.PointAt(t, t.S[i], lat + side * 18)
				if clear(x, z, BARRIER + 14) and occ.free(x, z, 60) then
					local x0, _, z0 = Track.PointAt(t, t.S[i], lat)
					local cf = CFrame.lookAt(Vector3.new(x0, 0, z0), Vector3.new(x0 + tx, 0, z0 + tz))
					stand(cf, 130, side, 6)
					table.insert(placed, i)
				end
			end
		end
	end

	-- braking boards (150 / 100 / 50) and corner chevron signs ----------------------------
	do
		local lastBoard = -1000
		for i = 1, t.N do
			local prevI = Track.Wrap(t, i - 1)
			if braking[i] and not braking[prevI] and math.abs(Track.IndexDelta(t, lastBoard, i)) > 30 then
				lastBoard = i
				-- the corner this braking zone leads into
				local apex = i
				for o = 1, 30 do
					local j = Track.Wrap(t, i + o)
					if math.abs(t.K[j]) > math.abs(t.K[apex]) then
						apex = j
					end
				end
				local side = -sign(t.K[apex])
				for _, dist in { 150, 100, 50 } do
					local sIdx = Track.Wrap(t, apex - math.floor((dist + 40) / Track.DS))
					local x, y, z, tx, _, tz = Track.PointAt(t, t.S[sIdx], side * (W / 2 + 7))
					if clear(x, z, W / 2 + 5, sIdx, 12) then
						local bcf = CFrame.lookAt(Vector3.new(x, y + ROAD_LIFT, z), Vector3.new(x - tx, y + ROAD_LIFT, z - tz))
						P(deco, Vector3.new(0.3, 3, 0.3), bcf * CFrame.new(0, 1.5, 0.3), Color3.fromRGB(80, 80, 85), Enum.Material.Metal)
						local board = P(deco, Vector3.new(3, 2.4, 0.2), bcf * CFrame.new(0, 3.8, 0), Color3.fromRGB(250, 250, 250))
						textGui(board, Enum.NormalId.Front, tostring(dist), Color3.fromRGB(15, 15, 20), Color3.fromRGB(250, 250, 250))
					end
				end
				-- chevrons on the outside barrier of tight corners
				if math.abs(t.K[apex]) > 1 / 170 then
					local arrow = if t.K[apex] > 0 then ">>>" else "<<<"
					for o = -1, 1 do
						local j = Track.Wrap(t, apex + o * 5)
						local x, y, z = Track.PointAt(t, t.S[j], side * (BARRIER - 1.6))
						local cxT, _, czT = Track.PointAt(t, t.S[j], 0)
						local ccf = CFrame.lookAt(Vector3.new(x, y + ROAD_LIFT + 3.4, z), Vector3.new(cxT, y + ROAD_LIFT + 3.4, czT))
						local plate = P(deco, Vector3.new(6, 2.6, 0.3), ccf, Color3.fromRGB(20, 20, 24))
						textGui(plate, Enum.NormalId.Front, arrow, Color3.fromRGB(255, 210, 30), Color3.fromRGB(20, 20, 24))
					end
				end
			end
		end
	end

	-- marshal posts, TV towers, billboards, floodlights along the lap -----------------------
	do
		local count = 0
		for i = 20, t.N, 20 do
			count += 1
			local side = if count % 2 == 0 then 1 else -1
			local s0 = t.S[i]
			if count % 3 == 0 and not street then
				-- marshal post
				local x, y, z = Track.PointAt(t, s0, side * (BARRIER + 5))
				if clear(x, z, BARRIER + 2, i, 20) and occ.free(x, z, 5) then
					local mcf = CFrame.new(x, y, z)
					P(deco, Vector3.new(4, 4, 4), mcf * CFrame.new(0, 2, 0), Color3.fromRGB(255, 140, 20), Enum.Material.SmoothPlastic)
					P(deco, Vector3.new(4.4, 0.4, 4.4), mcf * CFrame.new(0, 4.2, 0), Color3.fromRGB(240, 240, 240))
					P(deco, Vector3.new(0.15, 5, 0.15), mcf * CFrame.new(1.5, 6.5, 0), Color3.fromRGB(200, 200, 200), Enum.Material.Metal)
					P(deco, Vector3.new(0.1, 1.6, 2.4), mcf * CFrame.new(1.5, 8.2, 1.2), Color3.fromRGB(255, 220, 0), Enum.Material.Fabric)
				end
			elseif count % 5 == 1 and dens > 0.5 then
				-- TV camera tower
				local x, y, z = Track.PointAt(t, s0, side * (BARRIER + 8))
				if clear(x, z, BARRIER + 4, i, 20) and occ.free(x, z, 6) then
					local tcf = CFrame.new(x, y, z)
					for _, o in { { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } } do
						P(deco, Vector3.new(0.3, 14, 0.3), tcf * CFrame.new(o[1], 7, o[2]), Color3.fromRGB(150, 150, 155), Enum.Material.Metal)
					end
					P(deco, Vector3.new(4, 0.4, 4), tcf * CFrame.new(0, 14, 0), Color3.fromRGB(90, 90, 95), Enum.Material.DiamondPlate)
					P(deco, Vector3.new(1.4, 1.4, 2.4), tcf * CFrame.new(0, 15, 0), Color3.fromRGB(25, 25, 30))
				end
			end
		end
		-- billboards along the straights
		count = 0
		for i = 40, t.N, 38 do
			if math.abs(t.K[i]) < 1 / 900 and not t.Over[i] then
				count += 1
				local side = if count % 2 == 0 then 1 else -1
				local lat = side * (BARRIER + 3)
				local x, y, z, tx, _, tz = Track.PointAt(t, t.S[i], lat)
				if clear(x, z, BARRIER, i, 20) and occ.free(x, z, 14) then
					local brand = BRANDS[(count % #BRANDS) + 1]
					local cf = CFrame.lookAt(Vector3.new(x, y + 6, z), Vector3.new(x + tx, y + 6, z + tz))
					local board = P(deco, Vector3.new(0.6, 7, 30), cf * CFrame.new(0, ROAD_LIFT + 1, 0), Color3.fromRGB(25, 25, 30), Enum.Material.SmoothPlastic)
					textGui(board, if side > 0 then Enum.NormalId.Left else Enum.NormalId.Right, brand[1], brand[2], Color3.fromRGB(20, 20, 26))
					for kk = -1, 1, 2 do
						P(deco, Vector3.new(0.5, 6, 0.5), cf * CFrame.new(0, -2.5 + ROAD_LIFT, kk * 13), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
					end
				end
			end
		end
		-- sponsor bridge over the track (1-2 per circuit)
		local bridges = 0
		for i = math.floor(t.N * 0.3), t.N, math.floor(t.N * 0.35) do
			if bridges < 2 and math.abs(t.K[i]) < 1 / 800 and not t.Over[i] and not braking[i] then
				local okB = true
				for side = -1, 1, 2 do
					local x, _, z = Track.PointAt(t, t.S[i], side * (BARRIER + 4))
					if not clear(x, z, BARRIER, i, 20) then
						okB = false
					end
				end
				if okB then
					bridges += 1
					local x, y, z, tx, _, tz = Track.PointAt(t, t.S[i], 0)
					local bcf = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x + tx, y, z + tz))
					for side = -1, 1, 2 do
						P(deco, Vector3.new(3, 22, 3), bcf * CFrame.new(side * (BARRIER + 3), 11, 0), Color3.fromRGB(230, 232, 236), Enum.Material.Concrete)
					end
					local deck = P(deco, Vector3.new(BARRIER * 2 + 10, 6, 5), bcf * CFrame.new(0, 21, 0), Color3.fromRGB(28, 30, 38), Enum.Material.Metal)
					local brand = BRANDS[rng:NextInteger(1, #BRANDS)]
					textGui(deck, Enum.NormalId.Front, brand[1], brand[2], Color3.fromRGB(24, 26, 34))
					textGui(deck, Enum.NormalId.Back, brand[1], brand[2], Color3.fromRGB(24, 26, 34))
				end
			end
		end
	end

	-- floodlights (night races): poles all the way round, real lights on some ---------------
	if night then
		local n = 0
		local lightsPlaced = 0
		local maxLights = ({ 12, 24, 40, 56 })[q]
		for i = 1, t.N, 5 do
			n += 1
			local side = if n % 2 == 0 then 1 else -1
			local lat = side * (BARRIER + 2.5)
			local x, y, z = Track.PointAt(t, t.S[i], lat)
			if clear(x, z, BARRIER, i, 20) then
				P(deco, Vector3.new(1, 24, 1), CFrame.new(x, y + 12, z), Color3.fromRGB(80, 82, 90), Enum.Material.Metal)
				local head = P(deco, Vector3.new(6, 1.2, 2.5), CFrame.new(x - t.RX[i] * side * 2.5, y + 24, z - t.RZ[i] * side * 2.5), Color3.fromRGB(255, 250, 232), Enum.Material.Neon)
				if n % 3 == 0 and lightsPlaced < maxLights then
					lightsPlaced += 1
					local l = Instance.new("SpotLight")
					l.Face = Enum.NormalId.Bottom
					l.Range = 70
					l.Angle = 120
					l.Brightness = 3.5
					l.Shadows = false
					l.Color = Color3.fromRGB(255, 248, 230)
					l.Parent = head
				end
			end
		end
	end

	-- shared context for landmarks, WorldLife and the movers ---------------------------------
	local function openSpot(radius: number, infield: boolean?): Vector3?
		for _ = 1, 200 do
			local x = rng:NextNumber(b[1] - 500, b[2] + 500)
			local z = rng:NextNumber(b[3] - 500, b[4] + 500)
			if infield then
				x = rng:NextNumber(b[1], b[2])
				z = rng:NextNumber(b[3], b[4])
			end
			if clear(x, z, radius + BARRIER + 20) and occ.free(x, z, radius) then
				return Vector3.new(x, 0, z)
			end
		end
		return nil
	end
	local span = math.max(b[2] - b[1], b[4] - b[3])
	local seaZ = if table.find(th.Landmarks, "sea") then b[4] + 380 else nil
	if seaZ then
		P(scenery, Vector3.new(9000, 1, 3400), CFrame.new(cx, 0.3, seaZ + 1700), th.Water, Enum.Material.Glass).Reflectance = 0.25
		P(scenery, Vector3.new(9000, 1, 70), CFrame.new(cx, 0.2, seaZ - 25), Color3.fromRGB(225, 205, 160), Enum.Material.Sand)
		occ.block(function(_, z, r)
			return z + r > seaZ - 30
		end)
	end
	local movers = {}
	local ctx = {
		P = P,
		F = scenery,
		Scenery = scenery,
		Th = th,
		Rng = rng,
		Q = q,
		Dens = dens,
		T = t,
		Night = night,
		Street = street,
		Barrier = BARRIER,
		Bounds = b,
		Cx = cx,
		Cz = cz,
		Span = span,
		SeaZ = seaZ,
		Clear = clear,
		Occ = occ,
		Movers = movers,
		Lights = ({ 4, 10, 18, 28 })[q],
		Text = textGui,
		OpenSpot = openSpot,
		Meshes = meshesOn,
		Mesh = MESH,
		MeshSize = WorldMeshes.Size,
		Prop = prop,
	}
	function ctx.Parts(): number
		return partCounter
	end
	function ctx.Mover(parts, baseCF: CFrame, update)
		local offs = table.create(#parts)
		for i, part in parts do
			offs[i] = baseCF:ToObjectSpace(part.CFrame)
		end
		table.insert(movers, { Parts = parts, Offsets = offs, Update = update })
	end
	function ctx.Pos(i: number, lateral: number?, lift: number?): Vector3
		return pos(t, i, lateral, lift)
	end
	function ctx.Reserve(p: Vector3, r: number)
		reserve(p, r)
	end
	function ctx.Face(p: Vector3): CFrame
		local best, bd = 1, math.huge
		for i = 1, t.N, 4 do
			local dx, dz = t.X[i] - p.X, t.Z[i] - p.Z
			local d = dx * dx + dz * dz
			if d < bd then
				best, bd = i, d
			end
		end
		local tp = Vector3.new(t.X[best], 0, t.Z[best])
		if (tp - p).Magnitude < 1 then
			return CFrame.new(p)
		end
		return CFrame.lookAt(p, tp)
	end
	function ctx.FarSpot(r: number): Vector3?
		for _ = 1, 60 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = span / 2 + r * 0.6 + rng:NextNumber(500, 900)
			local x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
			if clear(x, z, r * 0.8 + BARRIER) and occ.free(x, z, r * 0.6) then
				return Vector3.new(x, 0, z)
			end
		end
		return nil
	end
	local shoreUsed = {}
	function ctx.ShoreSpot(r: number): Vector3?
		if not seaZ then
			return nil
		end
		for _ = 1, 30 do
			local x = cx + rng:NextNumber(-500, 500)
			local ok = true
			for _, u in shoreUsed do
				if math.abs(u[1] - x) < u[2] + r then
					ok = false
				end
			end
			if ok then
				table.insert(shoreUsed, { x, r })
				return Vector3.new(x, 0, seaZ - 30)
			end
		end
		return nil
	end
	function ctx.SeaSpot(r: number): Vector3?
		if not seaZ then
			return nil
		end
		return Vector3.new(cx + rng:NextNumber(-500, 500), 0.5, seaZ + r + rng:NextNumber(120, 320))
	end

	-- landmarks ------------------------------------------------------------------------------
	progress("Raising the landmarks", 0.52)
	local sights, sightSpots = Landmarks.Build(ctx, th.Landmarks)
	if table.find(th.Landmarks, "yachts") and seaZ then
		for kk = 0, 8 do
			local ycf = CFrame.new(cx - 700 + kk * 170 + rng:NextNumber(-40, 40), 1, seaZ + 60 + rng:NextNumber(0, 200)) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)
			P(scenery, Vector3.new(16, 6, 60), ycf * CFrame.new(0, 2, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
			P(scenery, Vector3.new(12, 5, 30), ycf * CFrame.new(0, 7, 4), Color3.fromRGB(230, 230, 235), Enum.Material.SmoothPlastic)
			P(scenery, Vector3.new(12.2, 1.5, 30.2), ycf * CFrame.new(0, 7.5, 4), Color3.fromRGB(40, 60, 90), Enum.Material.Glass)
			if night then
				P(scenery, Vector3.new(16.2, 0.6, 60.2), ycf * CFrame.new(0, 4.6, 0), th.Accent, Enum.Material.Neon)
			end
		end
	end

	-- life around the track: fan banks, city blocks with traffic, farm fields ------------------
	local treeName = nil
	for name in th.Props do
		if string.find(name, "tree") or name == "palm" or name == "snowpine" then
			treeName = name
			break
		end
	end
	if treeName then
		ctx.Tree = function(f, tcf, sc)
			prop(treeName, f, tcf, sc, th)
		end
	end
	progress("Filling the stands with fans", 0.6)
	Life.Trackside(ctx)
	progress("Building the streets and traffic", 0.66)
	local blocks = Life.Districts(ctx)
	local fields = Life.Fields(ctx)
	progress("Local architecture", 0.78)

	-- the host country's architecture -------------------------------------------------------
	local archList, archTotal = {}, 0
	for name, w in th.Arch do
		if Arch.Types[name] then
			archTotal += w
			table.insert(archList, { name, archTotal })
		end
	end
	local function pickArch(): string?
		if archTotal <= 0 then
			return nil
		end
		local roll = rng:NextNumber(0, archTotal)
		for _, e in archList do
			if roll <= e[2] then
				return e[1]
			end
		end
		return archList[#archList][1]
	end
	local layout = th.Layout
	local rings
	if layout == "city" then
		rings = { { 14, 3, 0.95 }, { 70, 5, 0.8 }, { 150, 7, 0.7 }, { 260, 9, 0.55 } }
	elseif layout == "town" then
		rings = { { 30, 6, 0.55 }, { 110, 7, 0.55 }, { 220, 9, 0.45 } }
	elseif layout == "rural" then
		rings = { { 40, 10, 0.35 }, { 150, 12, 0.35 }, { 300, 14, 0.3 } }
	else
		rings = { { 50, 12, 0.3 }, { 200, 14, 0.25 } }
	end
	local archCount = 0
	for ri, ring in rings do
		-- Low: the two nearest rings; Medium (phones): three - the city blocks fill the rest
		if (q == 1 and ri > 2) or (q == 2 and ri > 3) then
			break
		end
		local dist, stepN, prob = ring[1], ring[2], ring[3] * math.min(1.2, dens)
		for i = 1, t.N, stepN do
			for side = -1, 1, 2 do
				if rng:NextNumber() < prob then
					local name = pickArch()
					if name then
						local fw, fd = Arch.Footprint(name)
						local r = math.max(fw, fd) / 2 + 2
						local lat = side * (BARRIER + dist + fd / 2 + rng:NextNumber(0, 10))
						local x, _, z = Track.PointAt(t, t.S[i] + rng:NextNumber(-10, 10), lat)
						if clear(x, z, r + BARRIER - 2) and occ.free(x, z, r) then
							occ.add(x, z, r)
							local tx0, _, tz0 = Track.PointAt(t, t.S[i], 0)
							local bcf = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(tx0, 0, tz0))
							Arch.Build(name, scenery, bcf, rng, th, P)
							archCount += 1
						end
					end
				end
			end
		end
	end

	-- everything else out to the horizon: city grids, suburbs, villages, forests, rocks
	progress("Growing the city to the horizon", 0.84)
	local filled = Cityscape.Fill(ctx)

	progress("Planting trees and scenery", 0.88)
	-- scenery props --------------------------------------------------------------------------
	local weights, totalW = {}, 0
	for name, w in th.Props do
		if Props[name] or PROP_MESH[name] then
			totalW += w
			table.insert(weights, { name, totalW })
		end
	end
	local area = (b[2] - b[1] + 1400) * (b[4] - b[3] + 1400)
	local count = math.floor(math.clamp(area / 8000, 160, 600) * dens)
	for _ = 1, count do
		local x = rng:NextNumber(b[1] - 700, b[2] + 700)
		local z = rng:NextNumber(b[3] - 700, b[4] + 700)
		if clear(x, z, BARRIER + 12) and occ.free(x, z, 8) and totalW > 0 then
			local roll = rng:NextNumber(0, totalW)
			local chosen = weights[#weights][1]
			for _, w in weights do
				if roll <= w[2] then
					chosen = w[1]
					break
				end
			end
			local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			prop(chosen, scenery, cf, rng:NextNumber(0.9, 1.6), th)
		end
	end
	-- a line of trees behind the barriers on classic circuits
	if not street and dens > 0.5 then
		if treeName then
			for i = 1, t.N, 9 do
				for side = -1, 1, 2 do
					if rng:NextNumber() < 0.45 then
						local x, _, z = Track.PointAt(t, t.S[i], side * (BARRIER + 12 + rng:NextNumber(0, 8)))
						if clear(x, z, BARRIER + 8) and occ.free(x, z, 6) then
							prop(treeName, scenery, CFrame.new(x, 0, z), rng:NextNumber(0.9, 1.3), th)
						end
					end
				end
			end
		end
	end

	-- the GoTrack blimp slowly circling the circuit
	if dens > 0.5 then
		local base = CFrame.new(0, -1000, 0)
		local white = Color3.fromRGB(240, 242, 246)
		local blimp = E(scenery, Vector3.new(22, 22, 72), base, white, Enum.Material.SmoothPlastic)
		local parts = {
			blimp,
			P(scenery, Vector3.new(5, 3, 12), base * CFrame.new(0, -12, 2), Color3.fromRGB(40, 42, 50), Enum.Material.SmoothPlastic),
			P(scenery, Vector3.new(0.6, 12, 9), base * CFrame.new(0, 6, 32), th.Accent, Enum.Material.SmoothPlastic),
			P(scenery, Vector3.new(12, 0.6, 9), base * CFrame.new(0, 0, 32), th.Accent, Enum.Material.SmoothPlastic),
		}
		local band = P(scenery, Vector3.new(22.6, 6, 40), base, Color3.fromRGB(24, 26, 34), Enum.Material.SmoothPlastic)
		table.insert(parts, band)
		textGui(band, Enum.NormalId.Left, "GOTRACK", Color3.fromRGB(255, 170, 30))
		textGui(band, Enum.NormalId.Right, "GOTRACK", Color3.fromRGB(255, 170, 30))
		if night then
			table.insert(parts, P(scenery, Vector3.new(22.8, 0.8, 42), base * CFrame.new(0, -3.6, 0), th.Accent, Enum.Material.Neon))
		end
		ctx.Mover(parts, base, function(now)
			local a = now * 0.012
			local r = span * 0.3 + 120
			local p = Vector3.new(cx + math.cos(a) * r, 170 + math.sin(now * 0.2) * 6, cz + math.sin(a) * r)
			return CFrame.lookAt(p, Vector3.new(cx + math.cos(a + 0.05) * r, p.Y, cz + math.sin(a + 0.05) * r))
		end)
	end

	-- boats, planes, birds, balloons, jets
	progress("Sky, weather and traffic", 0.95)
	Landmarks.BuildLife(ctx, th.Life)

	horizon(scenery, th, cx, cz, math.max(b[2] - b[1], b[4] - b[3]) / 2 + 900, rng, dens, seaZ, occ, q)
	local weatherConn = startWeather(th, deco, q)
	local ambientConn = startAmbient(th, deco, q)
	if th.Fireworks and night then
		startFireworks(deco, cx, cz, span, q)
	end
	local moverConn = Life.Start(ctx)
	progress("Ready", 1)

	-- the side of the circuit with the most scenery: the intro flyover looks that way, so
	-- it never opens on an empty side
	local sectors = table.create(12, 0)
	local reach2 = (span * 0.5 + 800) ^ 2
	for i, p in scenery:GetChildren() do
		if i % 2 == 0 and p:IsA("BasePart") then
			local pp = p.CFrame.Position
			local dx, dz = pp.X - cx, pp.Z - cz
			if dx * dx + dz * dz < reach2 and pp.Y > -50 then
				local k = math.floor((math.atan2(dz, dx) + math.pi) / (math.pi * 2) * 12) % 12 + 1
				sectors[k] += math.min(p.Size.Y, 80)
			end
		end
	end
	local bestK, bestW = 1, -1
	for k = 1, 12 do
		local w = sectors[k] + sectors[k % 12 + 1] * 0.8 + sectors[(k + 10) % 12 + 1] * 0.8
		if w > bestW then
			bestK, bestW = k, w
		end
	end
	local viewAngle = (bestK - 0.5) / 12 * math.pi * 2 - math.pi

	current = {
		ViewAngle = viewAngle,
		Folder = folder,
		Surface = surface,
		Lights = lights,
		Track = t,
		Theme = th,
		Connections = { weatherConn, ambientConn, moverConn },
		Sights = sights,
		SightSpots = sightSpots,
		Stats = { Parts = partCounter, Barriers = barrierCount, Buildings = archCount, Blocks = blocks, Fields = fields, Filled = filled, Meshes = meshesOn, Landmarks = #sights, Movers = #movers },
	}
	return current
end

-- n = number of red lights on (0..5); -1 = all green (GO)
function CircuitBuilder.SetStartLights(n: number)
	if not current then
		return
	end
	for k, lamps in current.Lights do
		for _, lamp in lamps do
			if n < 0 then
				lamp.Color = Color3.fromRGB(40, 255, 90)
				lamp.Material = Enum.Material.Neon
			elseif n >= k then
				lamp.Color = Color3.fromRGB(255, 30, 30)
				lamp.Material = Enum.Material.Neon
			else
				lamp.Color = Color3.fromRGB(60, 10, 10)
				lamp.Material = Enum.Material.SmoothPlastic
			end
		end
	end
end

function CircuitBuilder.Current()
	return current
end

function CircuitBuilder.Clear()
	if current then
		for _, c in current.Connections do
			if c then
				c:Disconnect()
			end
		end
		current.Folder:Destroy()
		current = nil
	end
end

CircuitBuilder.Props = Props

return CircuitBuilder
