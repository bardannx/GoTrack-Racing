--!nonstrict
-- Procedural buildings for each country theme. Every archetype declares its footprint
-- (W x D studs) so the circuit builder can place it without overlapping the track,
-- then builds a handful of parts facing the track (the -Z / Front face is the facade).
-- When the Blender world meshes are imported, the generic archetypes (towers, midrises,
-- houses, road cars) are built from them instead (see MESH_SUB / Arch.MeshHook).

local WM = require(script.Parent.WorldMeshes)

local Arch = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local WARM = rgb(255, 222, 160)
local GLASS_TINTS = { rgb(80, 120, 160), rgb(110, 150, 180), rgb(70, 95, 120), rgb(120, 160, 175), rgb(90, 110, 150) }

-- P(parent, size, cf, color, material, name, collide, shape, className)
local P

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

local function wedge(f, size, cf, color, material)
	return P(f, size, cf, color, material, nil, false, nil, "WedgePart")
end

-- gable roof, ridge along local X
local function gable(f, w, d, h, cf, color, material)
	wedge(f, Vector3.new(w, h, d / 2), cf * CFrame.new(0, h / 2, -d / 4), color, material)
	wedge(f, Vector3.new(w, h, d / 2), cf * CFrame.new(0, h / 2, d / 4) * CFrame.Angles(0, math.pi, 0), color, material)
end

-- window bands wrapping the body, one per floor (lit at night)
local function floors(f, cf, w, d, h, floorH, color, th, rng, startY)
	local n = math.floor((h - (startY or 2)) / floorH)
	for k = 1, n do
		local y = (startY or 2) + (k - 0.5) * floorH
		local lit = th.Night and rng:NextNumber() < 0.7
		P(f, Vector3.new(w + 0.3, floorH * 0.42, d + 0.3), cf * CFrame.new(0, y, 0), if lit then WARM else color, if lit then Enum.Material.Neon else Enum.Material.Glass)
	end
end

local function signText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 8
	sg.LightInfluence = 0
	sg.MaxDistance = 1200
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = if bg then 0 else 1
	tl.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	tl.Text = text
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = color
	tl.Parent = sg
	sg.Parent = part
end
Arch.SignText = signText

-- DETAIL HELPERS ------------------------------------------------------------------
-- Vertical fins across the whole body. Each part pokes out of two opposite faces, so
-- a handful of parts turns flat window bands into a real window grid.
local function mullions(f, cf, w, d, h, y0, spacing, color)
	local hh = h - y0
	if hh <= 1 then
		return
	end
	local nx = math.max(1, math.floor(w / spacing))
	local nz = math.max(1, math.floor(d / spacing))
	for k = 1, nx - 1 do
		P(f, Vector3.new(0.5, hh, d + 0.5), cf * CFrame.new(-w / 2 + k * w / nx, y0 + hh / 2, 0), color, Enum.Material.Metal)
	end
	for k = 1, nz - 1 do
		P(f, Vector3.new(w + 0.5, hh, 0.5), cf * CFrame.new(0, y0 + hh / 2, -d / 2 + k * d / nz), color, Enum.Material.Metal)
	end
end

-- Roof clutter: parapet, air-con units, a water tank, an aircraft warning light
local function rooftop(f, cf, w, d, h, rng, th)
	P(f, Vector3.new(w + 0.4, 1.2, d + 0.4), cf * CFrame.new(0, h + 0.6, 0), rgb(150, 152, 158), Enum.Material.Concrete)
	local mx, mz = math.max(0.5, w / 2 - 3), math.max(0.5, d / 2 - 3)
	for _ = 1, rng:NextInteger(1, 3) do
		P(f, Vector3.new(3.2, 2, 2.4), cf * CFrame.new(rng:NextNumber(-mx, mx), h + 2.2, rng:NextNumber(-mz, mz)), rgb(190, 192, 196), Enum.Material.Metal)
	end
	if rng:NextNumber() < 0.3 then
		P(f, Vector3.new(5, 5, 5), cf * CFrame.new(rng:NextNumber(-mx, mx), h + 3.7, rng:NextNumber(-mz, mz)) * CFrame.Angles(0, 0, math.pi / 2), rgb(120, 95, 70), Enum.Material.WoodPlanks, nil, false, Enum.PartType.Cylinder)
	end
	if th.Night and h > 50 then
		P(f, Vector3.new(1, 1, 1), cf * CFrame.new(0, h + 2, 0), rgb(255, 40, 40), Enum.Material.Neon)
	end
end

local AWNINGS = { rgb(196, 40, 40), rgb(30, 120, 70), rgb(30, 70, 150), rgb(230, 160, 30), rgb(120, 60, 140), rgb(240, 240, 235), rgb(20, 20, 24) }
local SHOPS = { "CAFE", "PIZZA", "BAKERY", "PHARMACY", "MARKET", "BOUTIQUE", "DINER", "BOOKS", "GELATO", "FLOWERS", "SUSHI", "TYRES", "BARBER", "BISTRO", "NOODLES", "SPORTS" }

-- Ground-floor shop: glass front, sloping awning and (sometimes) a name board
local function shopfront(f, cf, w, d, rng, th, withSign)
	local lit = th.Night
	P(f, Vector3.new(w - 1, 3.4, 0.4), cf * CFrame.new(0, 1.9, -d / 2 - 0.15), if lit then WARM else rgb(70, 90, 110), if lit then Enum.Material.Neon else Enum.Material.Glass)
	P(f, Vector3.new(w - 0.5, 0.35, 3), cf * CFrame.new(0, 4.1, -d / 2 - 1.5) * CFrame.Angles(math.rad(-14), 0, 0), pick(rng, AWNINGS), Enum.Material.Fabric)
	if withSign then
		local s = P(f, Vector3.new(math.min(w - 2, 12), 1.4, 0.3), cf * CFrame.new(0, 5.2, -d / 2 - 0.2), rgb(25, 25, 30))
		signText(s, Enum.NormalId.Front, pick(rng, SHOPS), rgb(255, 240, 210))
	end
end

-- A road car (nose = -Z). Wheels are two axle cylinders that show on both sides.
-- Returns the parts so movers can animate them.
local CAR_COLORS = { rgb(240, 240, 242), rgb(22, 24, 28), rgb(170, 174, 180), rgb(95, 100, 108), rgb(30, 50, 95), rgb(160, 25, 30), rgb(232, 232, 226), rgb(60, 72, 60), rgb(120, 20, 30), rgb(205, 196, 176), rgb(40, 90, 150) }
function Arch.CarColor(rng: Random, taxi: boolean?): Color3
	if taxi and rng:NextNumber() < 0.25 then
		return rgb(250, 200, 30)
	end
	return pick(rng, CAR_COLORS)
end

function Arch.Car(f, cf: CFrame, color: Color3, night: boolean?, maker): { BasePart }
	P = maker or P
	if Arch.MeshHook then
		local meshParts = Arch.MeshHook(if math.random() < 0.72 then "car_sedan" else "car_suv", f, cf, { Paint = { Body = { color, Enum.Material.SmoothPlastic }, Glass = { color:Lerp(rgb(30, 38, 50), 0.75), Enum.Material.Glass } }, Night = night })
		if meshParts then
			return meshParts
		end
	end
	local parts = {}
	local function add(p)
		table.insert(parts, p)
	end
	add(P(f, Vector3.new(6.4, 2.2, 15), cf * CFrame.new(0, 2.2, 0), color, Enum.Material.SmoothPlastic))
	add(P(f, Vector3.new(5.8, 2.1, 7.6), cf * CFrame.new(0, 4.3, 0.9), color:Lerp(rgb(30, 38, 50), 0.75), Enum.Material.Glass))
	for _, z in { -4.8, 4.8 } do
		add(P(f, Vector3.new(6.7, 2.6, 2.6), cf * CFrame.new(0, 1.3, z), rgb(24, 24, 27), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Cylinder))
	end
	if night then
		add(P(f, Vector3.new(5.2, 0.6, 0.2), cf * CFrame.new(0, 2.7, -7.55), rgb(255, 250, 225), Enum.Material.Neon))
		add(P(f, Vector3.new(5.2, 0.6, 0.2), cf * CFrame.new(0, 2.7, 7.55), rgb(220, 20, 20), Enum.Material.Neon))
	end
	return parts
end

local B = {}

-- MODERN CITY ------------------------------------------------------------------
B.office_tower = { W = 34, D = 34, Build = function(f, cf, rng, th)
	local w = rng:NextNumber(24, 32)
	local h = rng:NextNumber(70, 170)
	local glass = pick(rng, GLASS_TINTS)
	P(f, Vector3.new(w, h, w), cf * CFrame.new(0, h / 2, 0), glass, Enum.Material.Glass).Reflectance = 0.15
	for k = -1, 1, 2 do
		P(f, Vector3.new(1.2, h, 1.2), cf * CFrame.new(k * w / 2, h / 2, -w / 2), rgb(210, 214, 222), Enum.Material.Metal)
		P(f, Vector3.new(1.2, h, 1.2), cf * CFrame.new(k * w / 2, h / 2, w / 2), rgb(210, 214, 222), Enum.Material.Metal)
	end
	if th.Night then
		floors(f, cf, w, w, h, 10, glass, th, rng, 4)
	else
		for k = 1, math.floor(h / 14) do
			P(f, Vector3.new(w + 0.2, 0.8, w + 0.2), cf * CFrame.new(0, k * 14, 0), rgb(225, 228, 235), Enum.Material.Metal)
		end
	end
	mullions(f, cf, w, w, h, 6, 4.5, rgb(200, 205, 214))
	-- double-height lobby
	P(f, Vector3.new(w + 0.6, 6, w + 0.6), cf * CFrame.new(0, 3, 0), if th.Night then WARM else rgb(40, 52, 66), if th.Night then Enum.Material.Neon else Enum.Material.Glass)
	P(f, Vector3.new(w * 0.6, 0.6, 5), cf * CFrame.new(0, 6.3, -w / 2 - 2.5), rgb(215, 218, 225), Enum.Material.Metal)
	P(f, Vector3.new(w * 0.7, 6, w * 0.7), cf * CFrame.new(0, h + 3, 0), rgb(230, 232, 238), Enum.Material.Metal)
	rooftop(f, cf, w * 0.7, w * 0.7, h + 6, rng, th)
	P(f, Vector3.new(0.6, 18, 0.6), cf * CFrame.new(0, h + 15, 0), rgb(200, 200, 205), Enum.Material.Metal)
	if th.Night then
		P(f, Vector3.new(1.2, 1.2, 1.2), cf * CFrame.new(0, h + 24, 0), rgb(255, 40, 40), Enum.Material.Neon)
	end
end }

B.twisted_tower = { W = 36, D = 36, Build = function(f, cf, rng, th)
	local w = rng:NextNumber(24, 30)
	local n = rng:NextInteger(9, 14)
	local glass = pick(rng, GLASS_TINTS)
	for k = 0, n - 1 do
		local lit = th.Night and rng:NextNumber() < 0.6
		P(f, Vector3.new(w, 11, w), cf * CFrame.new(0, 5.5 + k * 11, 0) * CFrame.Angles(0, math.rad(k * 7), 0), if lit then glass:Lerp(WARM, 0.5) else glass, Enum.Material.Glass)
		P(f, Vector3.new(w + 0.4, 0.8, w + 0.4), cf * CFrame.new(0, 11 + k * 11, 0) * CFrame.Angles(0, math.rad(k * 7), 0), rgb(220, 224, 232), Enum.Material.Metal)
	end
	P(f, Vector3.new(0.8, 24, 0.8), cf * CFrame.new(0, n * 11 + 12, 0), rgb(220, 220, 225), Enum.Material.Metal)
end }

B.spire_tower = { W = 40, D = 40, Build = function(f, cf, rng, th)
	local base = rng:NextNumber(30, 38)
	local y = 0
	local glass = pick(rng, GLASS_TINTS)
	for k = 0, 4 do
		local w = base * (1 - k * 0.17)
		local h = rng:NextNumber(26, 40) * (1 - k * 0.1)
		P(f, Vector3.new(w, h, w), cf * CFrame.new(0, y + h / 2, 0) * CFrame.Angles(0, math.rad(k * 45), 0), glass:Lerp(rgb(200, 210, 220), k * 0.08), Enum.Material.Glass).Reflectance = 0.2
		if th.Night then
			P(f, Vector3.new(w + 0.3, 1, w + 0.3), cf * CFrame.new(0, y + h, 0) * CFrame.Angles(0, math.rad(k * 45), 0), WARM, Enum.Material.Neon)
		end
		y += h
	end
	P(f, Vector3.new(40, 1.2, 1.2), cf * CFrame.new(0, y + 20, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(225, 228, 235), Enum.Material.Metal, nil, false, Enum.PartType.Cylinder)
end }

B.apartment = { W = 32, D = 24, Build = function(f, cf, rng, th)
	local w, d = rng:NextNumber(24, 32), rng:NextNumber(16, 22)
	local nfl = rng:NextInteger(4, 9)
	local fh = 3.8
	local h = nfl * fh + 2
	local palette = if th.Key == "harbor" or th.Key == "mediterranean" or th.Key == "castle" then { rgb(240, 214, 180), rgb(236, 190, 160), rgb(245, 232, 205), rgb(230, 200, 200), rgb(250, 240, 220) } else { rgb(210, 210, 214), rgb(190, 186, 180), rgb(225, 220, 210), rgb(170, 175, 185) }
	local wall = pick(rng, palette)
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), wall, Enum.Material.Plaster)
	for k = 1, nfl do
		local y = 1 + (k - 0.5) * fh
		local lit = th.Night and rng:NextNumber() < 0.6
		P(f, Vector3.new(w + 0.2, 1.6, d + 0.2), cf * CFrame.new(0, y + 0.3, 0), if lit then WARM else rgb(60, 72, 90), if lit then Enum.Material.Neon else Enum.Material.Glass)
		if k > 1 then
			P(f, Vector3.new(w - 3, 0.4, 2), cf * CFrame.new(0, y - fh / 2 + 0.6, -d / 2 - 1), wall:Lerp(rgb(255, 255, 255), 0.4), Enum.Material.Concrete)
		end
	end
	P(f, Vector3.new(w + 0.6, 1, d + 0.6), cf * CFrame.new(0, h + 0.5, 0), wall:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Concrete)
	-- pilasters split the window bands into separate windows
	mullions(f, cf, w, d, h, 4.8, 5.5, wall)
	if rng:NextNumber() < 0.55 then
		shopfront(f, cf, w, d, rng, th, rng:NextNumber() < 0.4)
	else
		P(f, Vector3.new(3, 4, 0.4), cf * CFrame.new(0, 2, -d / 2 - 0.1), rgb(60, 45, 35), Enum.Material.Wood)
	end
	if th.Key == "harbor" or th.Key == "mediterranean" then
		P(f, Vector3.new(w + 1, 0.8, d + 1), cf * CFrame.new(0, h + 1.3, 0), rgb(190, 90, 60), Enum.Material.Slate)
	else
		rooftop(f, cf, w, d, h + 1, rng, th)
	end
end }

B.hotel_block = { W = 44, D = 24, Build = function(f, cf, rng, th)
	local w, d = 40, 20
	local nfl = rng:NextInteger(9, 13)
	local fh = 3.8
	local h = nfl * fh + 2
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), rgb(246, 244, 238), Enum.Material.Plaster)
	for k = 1, nfl do
		local y = 1 + (k - 0.5) * fh
		P(f, Vector3.new(w - 2, 0.35, 2.6), cf * CFrame.new(0, y - 1.2, -d / 2 - 1.3), rgb(250, 250, 250), Enum.Material.Concrete)
		P(f, Vector3.new(w + 0.2, 1.8, d + 0.2), cf * CFrame.new(0, y + 0.2, 0), if th.Night and rng:NextNumber() < 0.6 then WARM else rgb(60, 110, 150), if th.Night then Enum.Material.Neon else Enum.Material.Glass)
	end
	mullions(f, cf, w, d, h, 3, 5, rgb(246, 244, 238))
	shopfront(f, cf, w, d, rng, th, false)
	rooftop(f, cf, w, d, h, rng, th)
	local s = P(f, Vector3.new(24, 4, 0.5), cf * CFrame.new(0, h + 3, -d / 2 + 1), rgb(20, 20, 26))
	signText(s, Enum.NormalId.Front, pick(rng, { "HOTEL AZUR", "GRAND PALACE", "RIVIERA", "HOTEL LUMIERE" }), rgb(255, 215, 120))
end }

B.neon_block = { W = 28, D = 24, Build = function(f, cf, rng, th)
	local w, d = rng:NextNumber(20, 26), rng:NextNumber(16, 22)
	local h = rng:NextNumber(26, 60)
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), rgb(56, 58, 68), Enum.Material.Concrete)
	floors(f, cf, w, d, h, 6, rgb(40, 50, 70), th, rng, 3)
	local colors = { rgb(255, 40, 200), rgb(0, 230, 255), rgb(255, 200, 40), rgb(120, 255, 60), rgb(255, 70, 70) }
	for k = -1, 1, 2 do
		local c = pick(rng, colors)
		P(f, Vector3.new(3, h * 0.7, 0.6), cf * CFrame.new(k * (w / 2 - 3), h * 0.55, -d / 2 - 0.4), c, Enum.Material.Neon)
	end
	shopfront(f, cf, w, d, rng, th, true)
	local board = P(f, Vector3.new(w * 0.8, 8, 0.6), cf * CFrame.new(0, h + 5, -d / 2 + 2), rgb(18, 18, 24))
	signText(board, Enum.NormalId.Front, pick(rng, { "NITRO COLA", "PIXEL MOTORS", "STUDLINK", "APEX ENERGY", "TURBO RAMEN", "ORBIT AIR" }), pick(rng, colors))
	P(f, Vector3.new(w * 0.8 + 0.6, 0.5, 0.8), cf * CFrame.new(0, h + 9.2, -d / 2 + 2), pick(rng, colors), Enum.Material.Neon)
end }

B.casino_hotel = { W = 60, D = 50, Build = function(f, cf, rng, th)
	local h = rng:NextNumber(80, 130)
	local gold = rgb(230, 190, 110)
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		local wingCF = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 10)
		P(f, Vector3.new(14, h - k * 8, 28), wingCF * CFrame.new(0, (h - k * 8) / 2, 0), gold, Enum.Material.Glass).Reflectance = 0.25
		if th.Night then
			for fl = 1, math.floor((h - k * 8) / 9) do
				if rng:NextNumber() < 0.7 then
					P(f, Vector3.new(14.3, 1.2, 28.3), wingCF * CFrame.new(0, fl * 9, 0), WARM, Enum.Material.Neon)
				end
			end
		end
	end
	P(f, Vector3.new(16, 8, 16), cf * CFrame.new(0, h + 4, 0), rgb(255, 210, 90), Enum.Material.Neon)
	local s = P(f, Vector3.new(40, 10, 1), cf * CFrame.new(0, 16, -22), rgb(40, 10, 20))
	signText(s, Enum.NormalId.Front, pick(rng, { "LUCKY STAR", "GOLDEN SANDS", "THE MIRAGE ROYALE", "NEON PALACE", "HIGH ROLLER" }), rgb(255, 220, 90))
	P(f, Vector3.new(42, 0.8, 1.4), cf * CFrame.new(0, 21.4, -22), rgb(255, 40, 160), Enum.Material.Neon)
end }

B.pyramid_hotel = { W = 70, D = 70, Build = function(f, cf, rng, th)
	for k = 0, 9 do
		local w = 64 - k * 6.2
		P(f, Vector3.new(w, 5.5, w), cf * CFrame.new(0, 2.75 + k * 5.5, 0), rgb(24, 24, 30), Enum.Material.Glass).Reflectance = 0.3
	end
	P(f, Vector3.new(1.5, 400, 1.5), cf * CFrame.new(0, 255, 0), rgb(255, 250, 230), Enum.Material.Neon).Transparency = 0.4
end }

B.skydeck_hotel = { W = 90, D = 36, Build = function(f, cf, rng, th)
	local h = 110
	for k = -1, 1 do
		P(f, Vector3.new(18, h, 28), cf * CFrame.new(k * 30, h / 2, 0), rgb(200, 205, 212), Enum.Material.Glass).Reflectance = 0.2
		if th.Night then
			floors(f, cf * CFrame.new(k * 30, 0, 0), 18, 28, h, 8, rgb(150, 170, 190), th, rng, 4)
		end
	end
	P(f, Vector3.new(110, 5, 32), cf * CFrame.new(8, h + 2.5, 0), rgb(235, 238, 242), Enum.Material.Metal)
	P(f, Vector3.new(100, 2, 26), cf * CFrame.new(8, h + 6, 0), rgb(70, 150, 70), Enum.Material.Grass)
end }

B.flame_tower = { W = 60, D = 60, Build = function(f, cf, rng, th)
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		local base = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 16)
		local h = 90 - k * 12
		for s = 0, 5 do
			local w = 18 - s * 2.2
			local lean = s * 1.6
			local lit = th.Night
			P(f, Vector3.new(w, h / 6, w), base * CFrame.new(0, s * h / 6 + h / 12, -lean), if lit then rgb(255, 120, 40) else rgb(90, 130, 175), if lit then Enum.Material.Neon else Enum.Material.Glass)
		end
	end
end }

-- HOUSES & TOWNS ---------------------------------------------------------------
B.villa = { W = 24, D = 22, Build = function(f, cf, rng, th)
	local w, d, h = rng:NextNumber(16, 20), rng:NextNumber(12, 16), rng:NextNumber(7, 10)
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), rgb(248, 244, 236), Enum.Material.Plaster)
	gable(f, w + 1.5, d + 1.5, 3.5, cf * CFrame.new(0, h, 0), rgb(196, 96, 60), Enum.Material.Slate)
	P(f, Vector3.new(w * 0.7, 2.2, 0.3), cf * CFrame.new(0, h * 0.55, -d / 2 - 0.1), rgb(70, 90, 110), Enum.Material.Glass)
	P(f, Vector3.new(8, 0.3, 4), cf * CFrame.new(0, 0.2, -d / 2 - 3.5), rgb(80, 190, 230), Enum.Material.Glass)
end }

B.aussie_house = { W = 22, D = 20, Build = function(f, cf, rng, th)
	local w, d, h = 16, 13, 6
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), pick(rng, { rgb(236, 226, 206), rgb(210, 190, 170), rgb(240, 240, 240) }), Enum.Material.Plaster)
	gable(f, w + 2, d + 4, 3, cf * CFrame.new(0, h, 0), rgb(150, 156, 164), Enum.Material.CorrodedMetal)
	for k = -1, 1, 2 do
		P(f, Vector3.new(0.4, h, 0.4), cf * CFrame.new(k * (w / 2 - 0.5), h / 2, -d / 2 - 1.8), rgb(240, 240, 240))
	end
end }

B.cottage = { W = 20, D = 18, Build = function(f, cf, rng, th)
	local w, d, h = rng:NextNumber(12, 16), rng:NextNumber(9, 12), rng:NextNumber(6, 8)
	local wall = pick(rng, { rgb(170, 90, 70), rgb(236, 226, 206), rgb(200, 160, 120), rgb(245, 240, 230) })
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), wall, if wall.R > 0.8 then Enum.Material.Plaster else Enum.Material.Brick)
	gable(f, w + 1, d + 1.2, 4, cf * CFrame.new(0, h, 0), rgb(70, 72, 80), Enum.Material.Slate)
	P(f, Vector3.new(1.6, 4, 1.6), cf * CFrame.new(w / 2 - 2, h + 3, 0), rgb(150, 80, 60), Enum.Material.Brick)
	P(f, Vector3.new(2, 3.4, 0.3), cf * CFrame.new(0, 1.7, -d / 2 - 0.1), rgb(60, 40, 30), Enum.Material.Wood)
end }

B.townhouse = { W = 36, D = 14, Build = function(f, cf, rng, th)
	local x = -13.5
	for _ = 1, 4 do
		local w = rng:NextNumber(7, 9)
		local h = rng:NextNumber(12, 17)
		local brick = pick(rng, { rgb(150, 70, 50), rgb(120, 60, 45), rgb(90, 50, 40), rgb(200, 190, 170) })
		local c = cf * CFrame.new(x + w / 2, 0, 0)
		P(f, Vector3.new(w, h, 11), c * CFrame.new(0, h / 2, 0), brick, Enum.Material.Brick)
		for s = 1, 3 do
			P(f, Vector3.new(w - s * 2, 1.4, 11), c * CFrame.new(0, h + (s - 0.5) * 1.4, 0), brick, Enum.Material.Brick)
		end
		for fl = 1, math.floor(h / 4) do
			local lit = th.Night and rng:NextNumber() < 0.6
			P(f, Vector3.new(w - 2.4, 1.8, 0.3), c * CFrame.new(0, fl * 4 - 1.4, -5.6), if lit then WARM else rgb(240, 240, 240), if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		end
		x += w
	end
end }

B.chalet = { W = 24, D = 22, Build = function(f, cf, rng, th)
	local w, d = rng:NextNumber(16, 20), rng:NextNumber(12, 15)
	P(f, Vector3.new(w, 5, d), cf * CFrame.new(0, 2.5, 0), rgb(245, 243, 236), Enum.Material.Plaster)
	P(f, Vector3.new(w, 4, d), cf * CFrame.new(0, 7, 0), rgb(140, 92, 56), Enum.Material.Wood)
	gable(f, w + 4, d + 4, 5, cf * CFrame.new(0, 9, 0), rgb(90, 60, 45), Enum.Material.Wood)
	P(f, Vector3.new(w + 1, 0.5, 2), cf * CFrame.new(0, 6.2, -d / 2 - 1), rgb(120, 80, 50), Enum.Material.Wood)
	P(f, Vector3.new(w * 0.6, 2, 0.3), cf * CFrame.new(0, 2.8, -d / 2 - 0.1), rgb(60, 80, 100), Enum.Material.Glass)
end }

B.barn = { W = 30, D = 22, Build = function(f, cf, rng, th)
	local red = pick(rng, { rgb(170, 40, 35), rgb(150, 50, 40), rgb(120, 110, 100) })
	P(f, Vector3.new(18, 10, 14), cf * CFrame.new(-3, 5, 0), red, Enum.Material.WoodPlanks)
	gable(f, 19, 15, 5, cf * CFrame.new(-3, 10, 0), rgb(70, 50, 45), Enum.Material.Slate)
	P(f, Vector3.new(6, 8, 0.3), cf * CFrame.new(-3, 4, -7.1), rgb(245, 240, 235), Enum.Material.Wood)
	P(f, Vector3.new(16, 6, 6), cf * CFrame.new(10, 8, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(200, 205, 210), Enum.Material.Metal, nil, false, Enum.PartType.Cylinder)
	P(f, Vector3.new(6, 6, 6), cf * CFrame.new(10, 16, 0), rgb(200, 205, 210), Enum.Material.Metal, nil, false, Enum.PartType.Ball)
end }

B.hangar = { W = 50, D = 70, Build = function(f, cf, rng, th)
	P(f, Vector3.new(44, 14, 62), cf * CFrame.new(0, 7, 0), rgb(160, 165, 170), Enum.Material.CorrodedMetal)
	P(f, Vector3.new(62, 44, 44), cf * CFrame.new(0, 14, 0) * CFrame.Angles(0, math.pi / 2, 0), rgb(150, 155, 160), Enum.Material.CorrodedMetal, nil, false, Enum.PartType.Cylinder)
	P(f, Vector3.new(34, 12, 0.5), cf * CFrame.new(0, 6, -31.3), rgb(80, 84, 90), Enum.Material.DiamondPlate)
end }

B.church = { W = 22, D = 36, Build = function(f, cf, rng, th)
	local stone = pick(rng, { rgb(210, 200, 180), rgb(190, 180, 165), rgb(235, 230, 220) })
	P(f, Vector3.new(12, 10, 26), cf * CFrame.new(0, 5, 4), stone, Enum.Material.Limestone)
	gable(f, 13, 27, 6, cf * CFrame.new(0, 10, 4) * CFrame.Angles(0, math.pi / 2, 0), rgb(80, 80, 90), Enum.Material.Slate)
	P(f, Vector3.new(8, 24, 8), cf * CFrame.new(0, 12, -12), stone, Enum.Material.Limestone)
	for s = 0, 3 do
		local w = 7 - s * 1.7
		P(f, Vector3.new(w, 4, w), cf * CFrame.new(0, 26 + s * 4, -12), rgb(70, 110, 100), Enum.Material.Metal)
	end
	P(f, Vector3.new(0.4, 4, 0.4), cf * CFrame.new(0, 43, -12), rgb(220, 190, 90), Enum.Material.Metal)
end }

B.classical = { W = 46, D = 30, Build = function(f, cf, rng, th)
	local c = rgb(238, 230, 212)
	P(f, Vector3.new(40, 14, 22), cf * CFrame.new(0, 7, 2), c, Enum.Material.Marble)
	P(f, Vector3.new(42, 1.5, 6), cf * CFrame.new(0, 0.75, -11), c, Enum.Material.Marble)
	for k = 0, 7 do
		P(f, Vector3.new(14, 1.6, 1.6), cf * CFrame.new(-17.5 + k * 5, 7.5, -12) * CFrame.Angles(0, 0, math.pi / 2), c, Enum.Material.Marble, nil, false, Enum.PartType.Cylinder)
	end
	P(f, Vector3.new(42, 1.6, 6), cf * CFrame.new(0, 15, -11), c, Enum.Material.Marble)
	gable(f, 42, 6, 4, cf * CFrame.new(0, 15.8, -11) * CFrame.Angles(0, 0, 0), c, Enum.Material.Marble)
	if rng:NextNumber() < 0.5 then
		P(f, Vector3.new(14, 14, 14), cf * CFrame.new(0, 16, 4), rgb(90, 140, 120), Enum.Material.Metal, nil, false, Enum.PartType.Ball)
	end
end }

B.colorful_house = { W = 18, D = 16, Build = function(f, cf, rng, th)
	local colors = { rgb(255, 120, 150), rgb(255, 200, 60), rgb(80, 190, 255), rgb(120, 220, 120), rgb(255, 150, 60), rgb(190, 120, 255), rgb(250, 250, 245) }
	local y = 0
	for k = 0, rng:NextInteger(0, 2) do
		local w, d, h = rng:NextNumber(8, 12), rng:NextNumber(8, 11), rng:NextNumber(4.5, 6)
		P(f, Vector3.new(w, h, d), cf * CFrame.new(rng:NextNumber(-2, 2), y + h / 2, rng:NextNumber(-1.5, 1.5)), pick(rng, colors), Enum.Material.Plaster)
		P(f, Vector3.new(2, 2, 0.3), cf * CFrame.new(0, y + h * 0.55, -d / 2 - 1.6), if th.Night then WARM else rgb(60, 70, 90), if th.Night then Enum.Material.Neon else Enum.Material.Glass)
		y += h
		local _ = k
	end
end }

B.beach_condo = { W = 40, D = 20, Build = function(f, cf, rng, th)
	local h = rng:NextNumber(40, 75)
	P(f, Vector3.new(34, h, 16), cf * CFrame.new(0, h / 2, 0), rgb(250, 250, 248), Enum.Material.Plaster)
	for k = 1, math.floor(h / 4) do
		P(f, Vector3.new(32, 0.4, 2.4), cf * CFrame.new(0, k * 4 - 1, -9), rgb(245, 245, 245), Enum.Material.Concrete)
		P(f, Vector3.new(34.2, 1.8, 16.2), cf * CFrame.new(0, k * 4, 0), if th.Night and rng:NextNumber() < 0.6 then WARM else rgb(70, 170, 210), if th.Night then Enum.Material.Neon else Enum.Material.Glass)
	end
	mullions(f, cf, 34, 16, h, 2, 5.5, rgb(250, 250, 248))
	rooftop(f, cf, 34, 16, h, rng, th)
end }

-- STREET FILLERS (used by city blocks) -------------------------------------------------
B.glass_midrise = { W = 34, D = 28, Build = function(f, cf, rng, th)
	local w, d = rng:NextNumber(24, 32), rng:NextNumber(20, 26)
	local h = rng:NextNumber(30, 62)
	local glass = pick(rng, GLASS_TINTS)
	P(f, Vector3.new(w + 2, 6, d + 2), cf * CFrame.new(0, 3, 0), rgb(200, 200, 204), Enum.Material.Concrete)
	shopfront(f, cf, w + 2, d + 2, rng, th, rng:NextNumber() < 0.5)
	P(f, Vector3.new(w, h - 6, d), cf * CFrame.new(0, 6 + (h - 6) / 2, 0), glass, Enum.Material.Glass).Reflectance = 0.12
	if th.Night then
		floors(f, cf, w, d, h, 4.5, glass, th, rng, 6)
	end
	for k = 1, math.floor((h - 6) / 4.5) do
		P(f, Vector3.new(w + 0.3, 0.5, d + 0.3), cf * CFrame.new(0, 6 + k * 4.5, 0), rgb(220, 223, 230), Enum.Material.Concrete)
	end
	mullions(f, cf, w, d, h, 6, 4, rgb(215, 218, 225))
	rooftop(f, cf, w, d, h, rng, th)
end }

B.shop_row = { W = 40, D = 16, Build = function(f, cf, rng, th)
	local walls = { rgb(236, 222, 200), rgb(200, 120, 90), rgb(170, 190, 200), rgb(240, 236, 226), rgb(150, 80, 60), rgb(215, 200, 150), rgb(120, 140, 120) }
	local x = -19
	while x < 16 do
		local w = math.min(rng:NextNumber(8, 11), 19 - x)
		if w < 4 then
			break
		end
		local h = rng:NextNumber(8, 14)
		local wall = pick(rng, walls)
		local c = cf * CFrame.new(x + w / 2, 0, 0)
		P(f, Vector3.new(w - 0.2, h, 12), c * CFrame.new(0, h / 2, 0), wall, if rng:NextNumber() < 0.3 then Enum.Material.Brick else Enum.Material.Plaster)
		shopfront(f, c, w - 0.2, 12, rng, th, rng:NextNumber() < 0.45)
		local lit = th.Night and rng:NextNumber() < 0.6
		P(f, Vector3.new(w - 3, 2.2, 0.3), c * CFrame.new(0, h - 3, -6.1), if lit then WARM else rgb(60, 70, 90), if lit then Enum.Material.Neon else Enum.Material.Glass)
		P(f, Vector3.new(w, 0.8, 12.6), c * CFrame.new(0, h + 0.4, 0), wall:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Concrete)
		x += w
	end
end }

B.parking_garage = { W = 44, D = 36, Build = function(f, cf, rng, th)
	local w, d = 40, 32
	local levels = rng:NextInteger(3, 5)
	local conc = rgb(178, 179, 183)
	for k = 0, levels do
		P(f, Vector3.new(w, 0.8, d), cf * CFrame.new(0, k * 4.5 + 0.4, 0), conc, Enum.Material.Concrete)
		if k > 0 then
			for s = -1, 1, 2 do
				P(f, Vector3.new(w, 1.3, 0.5), cf * CFrame.new(0, k * 4.5 + 1.45, s * (d / 2 - 0.25)), conc:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Concrete)
			end
		end
	end
	for _, o in { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 1 }, { 0, 1 }, { 1, 1 } } do
		P(f, Vector3.new(1.4, levels * 4.5, 1.4), cf * CFrame.new(o[1] * (w / 2 - 1), levels * 2.25, o[2] * (d / 2 - 1)), conc, Enum.Material.Concrete)
	end
	for _ = 1, rng:NextInteger(2, 5) do
		local ccf = cf * CFrame.new(rng:NextNumber(-14, 14), levels * 4.5 + 0.8, rng:NextNumber(-5, 5)) * CFrame.Angles(0, if rng:NextNumber() < 0.5 then 0 else math.pi, 0)
		Arch.Car(f, ccf, Arch.CarColor(rng), false)
	end
	local s = P(f, Vector3.new(5, 5, 0.4), cf * CFrame.new(w / 2 - 4, 7, -d / 2 - 0.4), rgb(20, 70, 170))
	signText(s, Enum.NormalId.Front, "P", Color3.new(1, 1, 1), rgb(20, 70, 170))
end }

B.warehouse = { W = 50, D = 34, Build = function(f, cf, rng, th)
	local w, d, h = rng:NextNumber(38, 46), rng:NextNumber(24, 30), rng:NextNumber(10, 14)
	local wall = pick(rng, { rgb(190, 192, 196), rgb(150, 165, 180), rgb(200, 190, 170), rgb(120, 130, 140) })
	P(f, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), wall, Enum.Material.Metal)
	mullions(f, cf, w, d, h - 0.5, 0, 3, wall:Lerp(Color3.new(0, 0, 0), 0.12))
	for k = -1, 1 do
		P(f, Vector3.new(7, 8, 0.4), cf * CFrame.new(k * 12, 4, -d / 2 - 0.3), rgb(120, 125, 130), Enum.Material.DiamondPlate)
	end
	gable(f, w + 1, d + 1, 2.5, cf * CFrame.new(0, h, 0), rgb(140, 145, 150), Enum.Material.Metal)
	P(f, Vector3.new(w, 0.3, 14), cf * CFrame.new(0, 0.15, -d / 2 - 7), rgb(150, 150, 155), Enum.Material.Concrete)
	if rng:NextNumber() < 0.6 then
		local tcf = cf * CFrame.new(rng:NextNumber(-12, 12), 0, -d / 2 - 9)
		P(f, Vector3.new(7, 9, 18), tcf * CFrame.new(0, 5.5, 2), rgb(240, 240, 240), Enum.Material.SmoothPlastic)
		P(f, Vector3.new(7, 6, 6), tcf * CFrame.new(0, 4, -9.5), pick(rng, CAR_COLORS), Enum.Material.SmoothPlastic)
		P(f, Vector3.new(7.3, 2.4, 2.4), tcf * CFrame.new(0, 1.2, -9), rgb(24, 24, 27), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Cylinder)
		P(f, Vector3.new(7.3, 2.4, 2.4), tcf * CFrame.new(0, 1.2, 7), rgb(24, 24, 27), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Cylinder)
	end
end }

B.suburban_house = { W = 32, D = 30, Build = function(f, cf, rng, th)
	local w, d, h = rng:NextNumber(15, 19), rng:NextNumber(11, 14), rng:NextNumber(7, 9)
	local wall = pick(rng, { rgb(240, 236, 226), rgb(214, 196, 170), rgb(190, 200, 210), rgb(236, 220, 200), rgb(170, 120, 100), rgb(210, 220, 200) })
	local body = cf * CFrame.new(-4, 0, 4)
	P(f, Vector3.new(w, h, d), body * CFrame.new(0, h / 2, 0), wall, if wall.R < 0.72 then Enum.Material.Brick else Enum.Material.Plaster)
	gable(f, w + 1.5, d + 1.5, 4, body * CFrame.new(0, h, 0), pick(rng, { rgb(70, 72, 80), rgb(150, 70, 50), rgb(90, 60, 50), rgb(60, 70, 90) }), Enum.Material.Slate)
	for k = -1, 1, 2 do
		local lit = th.Night and rng:NextNumber() < 0.7
		P(f, Vector3.new(3.2, 2.6, 0.3), body * CFrame.new(k * w / 4, h * 0.62, -d / 2 - 0.1), if lit then WARM else rgb(70, 90, 110), if lit then Enum.Material.Neon else Enum.Material.Glass)
	end
	P(f, Vector3.new(2.2, 4, 0.3), body * CFrame.new(0, 2, -d / 2 - 0.1), pick(rng, { rgb(150, 30, 30), rgb(30, 50, 90), rgb(40, 90, 60), rgb(110, 75, 45) }), Enum.Material.Wood)
	-- garage, driveway, lawn and picket fence
	P(f, Vector3.new(8, 6, 10), body * CFrame.new(w / 2 + 4, 3, 1), wall, Enum.Material.Plaster)
	P(f, Vector3.new(7, 5, 0.3), body * CFrame.new(w / 2 + 4, 2.5, -4.1), rgb(235, 235, 235), Enum.Material.SmoothPlastic)
	P(f, Vector3.new(7, 0.25, 12), body * CFrame.new(w / 2 + 4, 0.12, -10), rgb(170, 170, 172), Enum.Material.Concrete)
	P(f, Vector3.new(w, 0.2, 8), body * CFrame.new(0, 0.1, -d / 2 - 4), rgb(96, 170, 70), Enum.Material.Grass)
	P(f, Vector3.new(w, 1.8, 0.3), body * CFrame.new(0, 0.9, -d / 2 - 8), rgb(245, 245, 245), Enum.Material.Wood)
	if rng:NextNumber() < 0.55 then
		Arch.Car(f, body * CFrame.new(w / 2 + 4, 0.2, -11.5) * CFrame.Angles(0, if rng:NextNumber() < 0.5 then 0 else math.pi, 0), Arch.CarColor(rng), th.Night)
	end
	if rng:NextNumber() < 0.6 then
		P(f, Vector3.new(1.2, 6, 1.2), body * CFrame.new(-w / 2 - 2, 3, -d / 2 - 3), rgb(100, 70, 45), Enum.Material.Wood)
		P(f, Vector3.new(8, 8, 8), body * CFrame.new(-w / 2 - 2, 8, -d / 2 - 3), rgb(70, 140, 60), Enum.Material.LeafyGrass, nil, false, Enum.PartType.Ball)
	end
end }

B.gas_station = { W = 44, D = 38, Build = function(f, cf, rng, th)
	local brand = pick(rng, { { "BLOX OIL", rgb(40, 200, 120) }, { "TURBOFUEL", rgb(255, 70, 40) }, { "VELOCITY", rgb(255, 210, 0) }, { "APEX", rgb(60, 200, 255) } })
	P(f, Vector3.new(40, 0.3, 32), cf * CFrame.new(0, 0.15, -2), rgb(150, 150, 155), Enum.Material.Concrete)
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			P(f, Vector3.new(1, 9, 1), cf * CFrame.new(x * 10, 4.5, -7 + z * 6), rgb(230, 230, 235), Enum.Material.Metal)
		end
	end
	P(f, Vector3.new(28, 1.6, 18), cf * CFrame.new(0, 9.8, -7), rgb(245, 245, 248), Enum.Material.SmoothPlastic)
	P(f, Vector3.new(28.2, 0.8, 18.2), cf * CFrame.new(0, 9.2, -7), brand[2], if th.Night then Enum.Material.Neon else Enum.Material.SmoothPlastic)
	for k = -1, 1, 2 do
		P(f, Vector3.new(1.5, 3.4, 2.5), cf * CFrame.new(k * 5, 1.7, -7), rgb(40, 42, 50), Enum.Material.SmoothPlastic)
	end
	P(f, Vector3.new(26, 8, 10), cf * CFrame.new(0, 4, 12), rgb(235, 235, 235), Enum.Material.Plaster)
	shopfront(f, cf * CFrame.new(0, 0, 12), 26, 10, rng, th, false)
	local pylon = P(f, Vector3.new(6, 14, 1), cf * CFrame.new(-17, 7, -16), rgb(30, 30, 36))
	signText(pylon, Enum.NormalId.Front, brand[1], brand[2])
	if rng:NextNumber() < 0.7 then
		Arch.Car(f, cf * CFrame.new(0, 0.3, -7), Arch.CarColor(rng), th.Night)
	end
end }

B.ranch_house = { W = 32, D = 20, Build = function(f, cf, rng, th)
	P(f, Vector3.new(26, 6, 12), cf * CFrame.new(0, 3, 0), pick(rng, { rgb(230, 215, 190), rgb(200, 170, 140), rgb(240, 238, 230) }), Enum.Material.WoodPlanks)
	gable(f, 28, 15, 2.5, cf * CFrame.new(0, 6, -1), rgb(110, 80, 60), Enum.Material.Slate)
	for k = -2, 2 do
		P(f, Vector3.new(0.4, 5, 0.4), cf * CFrame.new(k * 5.5, 2.5, -8), rgb(120, 90, 60), Enum.Material.Wood)
	end
end }

B.japanese_house = { W = 22, D = 18, Build = function(f, cf, rng, th)
	P(f, Vector3.new(16, 6, 12), cf * CFrame.new(0, 3, 0), rgb(245, 238, 222), Enum.Material.Plaster)
	for k = -2, 2 do
		P(f, Vector3.new(0.5, 6, 0.5), cf * CFrame.new(k * 3.8, 3, -6.2), rgb(70, 45, 35), Enum.Material.Wood)
	end
	gable(f, 20, 16, 3.5, cf * CFrame.new(0, 6, 0), rgb(50, 54, 62), Enum.Material.Slate)
	P(f, Vector3.new(21, 0.6, 1), cf * CFrame.new(0, 9.6, 0), rgb(40, 42, 48), Enum.Material.Slate)
end }

B.torii = { W = 20, D = 6, Build = function(f, cf, rng, th)
	local red = rgb(220, 50, 40)
	for k = -1, 1, 2 do
		P(f, Vector3.new(1.4, 14, 1.4), cf * CFrame.new(k * 6, 7, 0), red, Enum.Material.Wood)
	end
	P(f, Vector3.new(18, 1.2, 1.6), cf * CFrame.new(0, 11, 0), red, Enum.Material.Wood)
	P(f, Vector3.new(20, 1.4, 2), cf * CFrame.new(0, 14, 0), rgb(30, 30, 34), Enum.Material.Wood)
end }

B.pagoda = { W = 26, D = 26, Build = function(f, cf, rng, th)
	for k = 0, 4 do
		local w = (20 - k * 3.4)
		P(f, Vector3.new(w * 0.7, 5, w * 0.7), cf * CFrame.new(0, 2.5 + k * 6, 0), rgb(190, 45, 40), Enum.Material.Wood)
		P(f, Vector3.new(w, 1.2, w), cf * CFrame.new(0, 5.6 + k * 6, 0), rgb(40, 42, 48), Enum.Material.Slate)
		if th.Night then
			P(f, Vector3.new(w * 0.72, 0.6, w * 0.72), cf * CFrame.new(0, 4.2 + k * 6, 0), WARM, Enum.Material.Neon)
		end
	end
	P(f, Vector3.new(0.6, 6, 0.6), cf * CFrame.new(0, 33, 0), rgb(220, 180, 60), Enum.Material.Metal)
end }

-- MIDDLE EAST --------------------------------------------------------------------
B.dome_pavilion = { W = 36, D = 36, Build = function(f, cf, rng, th)
	local sand = pick(rng, { rgb(230, 212, 178), rgb(240, 228, 205), rgb(220, 200, 165) })
	P(f, Vector3.new(30, 12, 30), cf * CFrame.new(0, 6, 0), sand, Enum.Material.Sandstone)
	for k = -1, 1 do
		P(f, Vector3.new(5, 7, 0.4), cf * CFrame.new(k * 9, 4.5, -15.1), rgb(60, 50, 40), Enum.Material.SmoothPlastic)
	end
	P(f, Vector3.new(18, 18, 18), cf * CFrame.new(0, 13, 0), pick(rng, { rgb(240, 240, 240), rgb(60, 140, 170), rgb(220, 180, 90) }), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Ball)
	for k = -1, 1, 2 do
		P(f, Vector3.new(4, 18, 4), cf * CFrame.new(k * 13, 9, -13), sand, Enum.Material.Sandstone)
	end
	if th.Night then
		P(f, Vector3.new(30.4, 0.8, 30.4), cf * CFrame.new(0, 12, 0), WARM, Enum.Material.Neon)
	end
end }

B.wind_tower_house = { W = 22, D = 20, Build = function(f, cf, rng, th)
	local sand = pick(rng, { rgb(226, 206, 170), rgb(214, 190, 150), rgb(236, 222, 196) })
	P(f, Vector3.new(16, 8, 14), cf * CFrame.new(0, 4, 0), sand, Enum.Material.Sandstone)
	P(f, Vector3.new(4.5, 9, 4.5), cf * CFrame.new(5, 12, 3), sand, Enum.Material.Sandstone)
	for k = -1, 1 do
		P(f, Vector3.new(0.6, 5, 4.6), cf * CFrame.new(5 + k * 1.3, 13, 3), rgb(80, 60, 45))
	end
	P(f, Vector3.new(3, 3, 0.3), cf * CFrame.new(-3, 4, -7.1), if th.Night then WARM else rgb(70, 60, 50), if th.Night then Enum.Material.Neon else Enum.Material.SmoothPlastic)
end }

-- RURAL / INDUSTRIAL ----------------------------------------------------------------
B.water_tower = { W = 16, D = 16, Build = function(f, cf, rng, th)
	for _, o in { { -4, -4 }, { 4, -4 }, { -4, 4 }, { 4, 4 } } do
		P(f, Vector3.new(0.8, 26, 0.8), cf * CFrame.new(o[1], 13, o[2]), rgb(150, 155, 160), Enum.Material.Metal)
	end
	P(f, Vector3.new(10, 14, 14), cf * CFrame.new(0, 31, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(225, 228, 232), Enum.Material.Metal, nil, false, Enum.PartType.Cylinder)
	local band = P(f, Vector3.new(3, 14.2, 14.2), cf * CFrame.new(0, 31, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(200, 60, 50), Enum.Material.Metal, nil, false, Enum.PartType.Cylinder)
	band.Transparency = 0
end }

B.oil_pump = { W = 16, D = 10, Build = function(f, cf, rng, th)
	P(f, Vector3.new(10, 1, 4), cf * CFrame.new(0, 0.5, 0), rgb(90, 90, 95), Enum.Material.Concrete)
	P(f, Vector3.new(1, 7, 1), cf * CFrame.new(0, 4, 0), rgb(60, 60, 64), Enum.Material.Metal)
	P(f, Vector3.new(11, 1, 1), cf * CFrame.new(0, 7.6, 0) * CFrame.Angles(0, 0, math.rad(12)), rgb(230, 170, 30), Enum.Material.Metal)
	P(f, Vector3.new(1.6, 3, 1.4), cf * CFrame.new(-5.6, 6.2, 0), rgb(230, 170, 30), Enum.Material.Metal)
end }

B.wind_turbine = { W = 30, D = 30, Build = function(f, cf, rng, th)
	P(f, Vector3.new(74, 2.4, 2.4), cf * CFrame.new(0, 37, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(240, 242, 245), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Cylinder)
	P(f, Vector3.new(3, 3, 6), cf * CFrame.new(0, 75, 1), rgb(240, 242, 245))
	local hub = cf * CFrame.new(0, 75, -2.2)
	local rot = rng:NextNumber(0, math.pi)
	for k = 0, 2 do
		P(f, Vector3.new(1.4, 26, 0.4), hub * CFrame.Angles(0, 0, rot + k * math.pi * 2 / 3) * CFrame.new(0, 13, 0), rgb(245, 246, 248))
	end
end }

B.windmill = { W = 26, D = 22, Build = function(f, cf, rng, th)
	P(f, Vector3.new(9, 26, 9), cf * CFrame.new(0, 13, 0), rgb(120, 90, 70), Enum.Material.Brick)
	P(f, Vector3.new(10, 5, 10), cf * CFrame.new(0, 28, 0), rgb(60, 60, 62), Enum.Material.Slate)
	local hub = cf * CFrame.new(0, 26, -5.5)
	for k = 0, 3 do
		P(f, Vector3.new(2.5, 22, 0.4), hub * CFrame.Angles(0, 0, k * math.pi / 2 + 0.3) * CFrame.new(0, 11, 0), rgb(240, 240, 235), Enum.Material.Fabric)
	end
end }

B.lighthouse = { W = 14, D = 14, Build = function(f, cf, rng, th)
	for k = 0, 5 do
		P(f, Vector3.new(6, 8 - k * 0.4, 8 - k * 0.4), cf * CFrame.new(0, 3 + k * 6, 0) * CFrame.Angles(0, 0, math.pi / 2), if k % 2 == 0 then rgb(235, 40, 40) else rgb(250, 250, 250), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Cylinder)
	end
	P(f, Vector3.new(4, 5, 5), cf * CFrame.new(0, 39, 0), rgb(255, 245, 200), Enum.Material.Neon)
end }

B.castletower = { W = 22, D = 22, Build = function(f, cf, rng, th)
	P(f, Vector3.new(14, 36, 14), cf * CFrame.new(0, 18, 0), rgb(200, 175, 130), Enum.Material.Sandstone)
	for k = 0, 3 do
		local a = k * math.pi / 2
		P(f, Vector3.new(4, 4, 4), cf * CFrame.new(0, 38, 0) * CFrame.Angles(0, a, 0) * CFrame.new(5, 0, 5), rgb(200, 175, 130), Enum.Material.Sandstone)
	end
end }

-- ARCTIC / ISLAND ---------------------------------------------------------------------
B.research_station = { W = 30, D = 24, Build = function(f, cf, rng, th)
	for k = 0, 1 do
		local c = cf * CFrame.new(k * 12 - 6, 0, 0)
		for _, o in { { -4, -3 }, { 4, -3 }, { -4, 3 }, { 4, 3 } } do
			P(f, Vector3.new(0.6, 3, 0.6), c * CFrame.new(o[1], 1.5, o[2]), rgb(80, 80, 86), Enum.Material.Metal)
		end
		P(f, Vector3.new(10, 5, 8), c * CFrame.new(0, 5.5, 0), if k == 0 then rgb(230, 80, 40) else rgb(240, 200, 40), Enum.Material.SmoothPlastic)
		P(f, Vector3.new(8, 1.2, 0.3), c * CFrame.new(0, 6, -4.1), WARM, Enum.Material.Neon)
	end
	P(f, Vector3.new(8, 8, 8), cf * CFrame.new(0, 12, 8), rgb(245, 245, 250), Enum.Material.SmoothPlastic, nil, false, Enum.PartType.Ball)
	P(f, Vector3.new(0.4, 16, 0.4), cf * CFrame.new(10, 13, 6), rgb(200, 200, 205), Enum.Material.Metal)
end }

B.ski_lodge = { W = 24, D = 22, Build = function(f, cf, rng, th)
	gable(f, 16, 18, 14, cf, rgb(120, 80, 50), Enum.Material.WoodPlanks)
	P(f, Vector3.new(6, 8, 0.4), cf * CFrame.new(0, 4, -9.2), if th.Night then WARM else rgb(70, 90, 110), if th.Night then Enum.Material.Neon else Enum.Material.Glass)
	gable(f, 17, 19, 1.4, cf * CFrame.new(0, 13.6, 0), rgb(245, 250, 255), Enum.Material.Snow)
end }

B.igloo = { W = 14, D = 14, Build = function(f, cf, rng, th)
	P(f, Vector3.new(12, 12, 12), cf * CFrame.new(0, 0, 0), rgb(245, 250, 255), Enum.Material.Ice, nil, false, Enum.PartType.Ball)
	P(f, Vector3.new(3, 3, 4), cf * CFrame.new(0, 1.5, -6), rgb(240, 246, 255), Enum.Material.Ice)
end }

B.tiki_hut = { W = 16, D = 16, Build = function(f, cf, rng, th)
	for _, o in { { -4, -4 }, { 4, -4 }, { -4, 4 }, { 4, 4 } } do
		P(f, Vector3.new(0.8, 6, 0.8), cf * CFrame.new(o[1], 3, o[2]), rgb(110, 75, 45), Enum.Material.Wood)
	end
	gable(f, 12, 12, 5, cf * CFrame.new(0, 6, 0), rgb(200, 170, 90), Enum.Material.Grass)
	if th.Night then
		P(f, Vector3.new(1, 1.6, 1), cf * CFrame.new(0, 4, -4), rgb(255, 160, 60), Enum.Material.Neon)
	end
end }

B.geothermal = { W = 40, D = 40, Build = function(f, cf, rng, th)
	for k = 0, 5 do
		local d = 26 - math.abs(k - 3) * 2.5
		P(f, Vector3.new(7, d, d), cf * CFrame.new(0, 3.5 + k * 6.5, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(200, 200, 204), Enum.Material.Concrete, nil, false, Enum.PartType.Cylinder)
	end
	local top = P(f, Vector3.new(1, 1, 1), cf * CFrame.new(0, 42, 0), Color3.new(1, 1, 1))
	top.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(240, 240, 245))
	pe.Size = NumberSequence.new(10, 30)
	pe.Transparency = NumberSequence.new(0.4, 1)
	pe.Lifetime = NumberRange.new(5, 8)
	pe.Rate = 3
	pe.Speed = NumberRange.new(8, 14)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = top
end }

Arch.Types = B

-- WORLD MESHES --------------------------------------------------------------------------
-- Once the Blender world meshes are imported (WorldMeshes.luau), the generic archetypes
-- below are built from them instead: a skyscraper becomes ~6 MeshParts (real window grids,
-- setbacks, crowns, masts) instead of 40-80 parts. CircuitBuilder sets Arch.MeshHook to
-- function(design, parent, cf, opts) -> parts? (it counts the parts); nil = parts only.
Arch.MeshHook = nil

local MESH_SUB = {
	office_tower = { "tower_glass", "tower_stack", "tower_round", "tower_deco", "tower_resi", "tower_glass" },
	twisted_tower = { "tower_twist" },
	spire_tower = { "tower_twin", "tower_blade" },
	glass_midrise = { "mid_office", "mid_office", "tower_stack" },
	apartment = { "mid_apart", "mid_euro", "mid_apart" },
	hotel_block = { "tower_resi" },
	beach_condo = { "tower_resi" },
	suburban_house = { "house_gable", "house_hip", "house_modern" },
	villa = { "house_villa" },
	aussie_house = { "house_hip" },
	cottage = { "house_gable" },
	warehouse = { "mid_loft" },
}
Arch.MeshSub = MESH_SUB

local NEUTRAL = { rgb(222, 216, 202), rgb(200, 196, 190), rgb(236, 230, 214), rgb(186, 176, 164), rgb(214, 200, 180), rgb(172, 174, 180) }
local WARM_WALLS = { rgb(240, 214, 180), rgb(236, 190, 160), rgb(245, 232, 205), rgb(230, 200, 196), rgb(250, 240, 220), rgb(226, 180, 130) }
local BRIGHT = { rgb(255, 160, 170), rgb(255, 210, 110), rgb(130, 200, 255), rgb(150, 220, 150), rgb(255, 170, 90), rgb(250, 250, 245), rgb(190, 150, 255) }
local SAND = { rgb(226, 206, 170), rgb(214, 190, 150), rgb(236, 222, 196), rgb(220, 200, 165) }
local BRICK = { rgb(150, 76, 58), rgb(130, 66, 50), rgb(170, 96, 70), rgb(112, 62, 50) }
local HOUSE_ROOFS = { rgb(190, 96, 62), rgb(78, 82, 92), rgb(116, 80, 60), rgb(150, 56, 44), rgb(70, 96, 84) }
local WARM_THEMES = { harbor = true, mediterranean = true, castle = true, temple = true, valley = true, marina = true }
local BRIGHT_THEMES = { aztec = true, jungle = true, beach = true }
local SAND_THEMES = { desertnight = true, pearl = true, oasis = true, corniche = true, canyon = true }

function Arch.WallColor(rng: Random, th, design: string?): Color3
	if design == "mid_loft" then
		return pick(rng, BRICK)
	elseif WARM_THEMES[th.Key] then
		return pick(rng, WARM_WALLS)
	elseif BRIGHT_THEMES[th.Key] and (design == nil or string.sub(design, 1, 5) ~= "tower") then
		return pick(rng, BRIGHT)
	elseif SAND_THEMES[th.Key] then
		return pick(rng, SAND)
	end
	return pick(rng, NEUTRAL)
end

-- colours for one mesh building, matching the host country
function Arch.MeshPaint(design: string, rng: Random, th): { [string]: any }
	local M = Enum.Material
	local glass = pick(rng, GLASS_TINTS)
	local wall = Arch.WallColor(rng, th, design)
	local house = string.sub(design, 1, 5) == "house"
	local roof = if house then pick(rng, HOUSE_ROOFS) else rgb(150, 152, 158)
	if design == "house_villa" or (house and WARM_THEMES[th.Key]) then
		roof = rgb(196, 96, 60)
	end
	return {
		Glass = { glass, M.Glass },
		WinA = { glass:Lerp(rgb(20, 30, 45), 0.35), M.Glass },
		WinB = { glass:Lerp(rgb(20, 30, 45), 0.2), M.Glass },
		Wall = { wall, if design == "mid_loft" then M.Brick elseif house then M.Plaster else M.Concrete },
		Trim = { wall:Lerp(rgb(255, 255, 255), 0.55), M.SmoothPlastic },
		Roof = { roof, if house then M.Slate else M.Concrete },
		Frame = { if design == "tower_deco" then rgb(200, 190, 160) else rgb(214, 218, 226), M.Metal },
		Accent = { pick(rng, AWNINGS), M.Fabric },
	}
end

-- Build a mesh stand-in inside a footprint of fw x fd studs. hMul scales the height.
function Arch.MeshBuilding(design: string, parent: Instance, cf: CFrame, rng: Random, th, fw: number?, fd: number?, hMul: number?): boolean
	local hook = Arch.MeshHook
	if not hook then
		return false
	end
	local W, D = WM.Size(design)
	if not W or not D then
		return false
	end
	local k = 1
	if fw and fd then
		k = math.clamp(math.min(fw / W, fd / D), 0.6, 1.3)
	end
	local tower = string.sub(design, 1, 5) == "tower"
	local ky = k * (hMul or (if tower then rng:NextNumber(0.5, 1) else rng:NextNumber(0.85, 1.15)))
	local lit = if th.Night then rng:NextInteger(if tower then 1 else 0, 2) else 0
	local parts = hook(design, parent, cf, { Scale = Vector3.new(k, ky, k), Paint = Arch.MeshPaint(design, rng, th), Night = th.Night, Lit = lit, Shadow = tower })
	return parts ~= nil
end

-- Builds archetype `name`; returns false if unknown
function Arch.Build(name: string, parent: Instance, cf: CFrame, rng: Random, th, maker): boolean
	local t = B[name]
	if not t then
		return false
	end
	P = maker
	local sub = Arch.MeshHook and MESH_SUB[name]
	if sub and Arch.MeshBuilding(pick(rng, sub), parent, cf, rng, th, t.W, t.D) then
		return true
	end
	t.Build(parent, cf, rng, th)
	return true
end

function Arch.Footprint(name: string): (number, number)
	local t = B[name]
	if not t then
		return 20, 20
	end
	return t.W, t.D
end

return Arch
