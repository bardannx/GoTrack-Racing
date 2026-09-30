--!nonstrict
-- Main-menu 3D scene: a bright, sunny team paddock with the player's car on a spinning
-- turntable in front of the team garage. Also used by the Garage for live previews.

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CarBuilder = require(Shared.CarBuilder)

local State = require(script.Parent.Parent.State)
local Fx = require(script.Parent.Parent.Fx)
local Cam = require(script.Parent.Parent.CameraController)

local Showroom = {}

local BASE = Vector3.new(0, 5000, 0)
local CAR_POS = BASE + Vector3.new(0, 3.35, 0)
Showroom.CarPos = CAR_POS

local folder = nil
local spinner = nil -- disc stripes that rotate with the car
local carModel = nil
local conn = nil
local spinAngle = 0
local spinning = true
local previewCar = nil

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function P(parent, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(BASE + Vector3.new(x, y, z))
end

local function vertCyl(parent, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?)
	return P(parent, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
end

local function sign(part: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, sub: string?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0
	sg.Brightness = 1.2
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = bg or rgb(20, 22, 30)
	f.BackgroundTransparency = if bg then 0 else 1
	f.Parent = sg
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, if sub then 0.62 else 1)
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.Michroma
	t.TextColor3 = color
	t.Parent = f
	if sub then
		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromScale(0.1, 0.62)
		s.Size = UDim2.fromScale(0.8, 0.3)
		s.Text = sub
		s.TextScaled = true
		s.Font = Enum.Font.GothamBold
		s.TextColor3 = rgb(210, 214, 225)
		s.Parent = f
	end
	sg.Parent = part
	return sg
end

local function tyreStack(parent, cf: CFrame, n: number, band: Color3)
	for k = 0, n - 1 do
		local c = cf * CFrame.new(0, 0.55 + k * 1.1, 0)
		vertCyl(parent, 1.05, 2.7, c, rgb(24, 24, 27))
		vertCyl(parent, 1.07, 1.6, c, band)
		vertCyl(parent, 1.09, 1.2, c, rgb(40, 40, 44), Enum.Material.Metal)
	end
end

local function garage(parent, cf: CFrame, width: number, team: Color3, name: string, bays: number)
	local depth = 26
	local h = 30
	-- main block
	P(parent, Vector3.new(width, h, depth), cf * CFrame.new(0, h / 2, depth / 2), rgb(240, 242, 246))
	-- team colour band + roof
	P(parent, Vector3.new(width + 0.4, 5, depth + 0.4), cf * CFrame.new(0, h - 2.5, depth / 2), team)
	P(parent, Vector3.new(width + 6, 1, depth + 8), cf * CFrame.new(0, h + 0.5, depth / 2 - 3), rgb(210, 213, 220), Enum.Material.Metal)
	-- upper glass floor
	local glass = P(parent, Vector3.new(width - 6, 7, 0.4), cf * CFrame.new(0, 19, -0.1), rgb(90, 140, 185), Enum.Material.Glass)
	glass.Reflectance = 0.25
	for k = 1, math.floor(width / 12) do
		P(parent, Vector3.new(0.5, 7, 0.6), cf * CFrame.new(-width / 2 + 3 + k * 12, 19, -0.2), rgb(225, 228, 235), Enum.Material.Metal)
	end
	-- sign
	local signPart = P(parent, Vector3.new(math.min(width * 0.55, 90), 4.6, 0.5), cf * CFrame.new(0, h - 2.5, -0.35), rgb(20, 22, 30))
	sign(signPart, Enum.NormalId.Front, name, rgb(255, 255, 255))
	-- garage bays (dark openings with a lit interior)
	local bayW = (width - 8) / bays
	for b = 0, bays - 1 do
		local x = -width / 2 + 4 + bayW * (b + 0.5)
		P(parent, Vector3.new(bayW - 3, 12.5, 0.4), cf * CFrame.new(x, 6.25, -0.1), rgb(46, 49, 58))
		P(parent, Vector3.new(bayW - 5, 0.4, 0.5), cf * CFrame.new(x, 12, -0.25), rgb(255, 250, 235), Enum.Material.Neon)
		P(parent, Vector3.new(bayW - 3, 1.4, 0.5), cf * CFrame.new(x, 1.2, -0.25), team:Lerp(Color3.new(0, 0, 0), 0.25))
		-- tool chest & tyres in front of each bay
		P(parent, Vector3.new(4, 3.4, 2), cf * CFrame.new(x - bayW * 0.3, 1.7, -3), team, Enum.Material.SmoothPlastic)
		P(parent, Vector3.new(4.1, 0.3, 2.1), cf * CFrame.new(x - bayW * 0.3, 3.5, -3), rgb(50, 52, 58), Enum.Material.Metal)
		tyreStack(parent, cf * CFrame.new(x + bayW * 0.32, 0, -3), 4, if b % 2 == 0 then rgb(230, 40, 40) else rgb(255, 210, 40))
	end
end

local function tree(parent, cf: CFrame, s: number)
	P(parent, Vector3.new(1.6, 8, 1.6) * s, cf * CFrame.new(0, 4 * s, 0), rgb(110, 78, 50), Enum.Material.Wood)
	P(parent, Vector3.new(10, 10, 10) * s, cf * CFrame.new(0, 11 * s, 0), rgb(76, 150, 62), Enum.Material.Grass, Enum.PartType.Ball)
	P(parent, Vector3.new(7, 7, 7) * s, cf * CFrame.new(2.5 * s, 14 * s, 1 * s), rgb(90, 165, 70), Enum.Material.Grass, Enum.PartType.Ball)
end

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

function Showroom.ApplyLighting()
	Lighting.ClockTime = 14.3
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 3
	Lighting.Ambient = rgb(125, 125, 135)
	Lighting.OutdoorAmbient = rgb(150, 150, 160)
	Lighting.ColorShift_Top = rgb(255, 248, 235)
	Lighting.ExposureCompensation = 0.05
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.GlobalShadows = true
	local atmo = getOrMake("Atmosphere", "GoTrackAtmosphere", Lighting)
	atmo.Density = 0.28
	atmo.Offset = 0.1
	atmo.Haze = 1.1
	atmo.Glare = 0.2
	atmo.Color = rgb(205, 225, 255)
	atmo.Decay = rgb(120, 160, 210)
	local bloom = getOrMake("BloomEffect", "GoTrackBloom", Lighting)
	bloom.Intensity = 0.25
	bloom.Size = 24
	bloom.Threshold = 2
	local cc = getOrMake("ColorCorrectionEffect", "GoTrackColor", Lighting)
	cc.Saturation = 0.12
	cc.Contrast = 0.08
	cc.Brightness = 0.02
	cc.TintColor = rgb(255, 252, 246)
	local rays = getOrMake("SunRaysEffect", "GoTrackRays", Lighting)
	rays.Intensity = 0.04
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = getOrMake("Clouds", "GoTrackClouds", terrain)
		clouds.Cover = 0.45
		clouds.Density = 0.6
		clouds.Color = Color3.new(1, 1, 1)
	end
	Showroom.ApplyQuality()
end

-- Graphics quality (Settings) takes effect at once: shadows from Medium, bloom / sun rays
-- from High, depth of field and clouds on Ultra / High. The circuit's scenery detail follows
-- on the next race.
local lastQuality = nil
function Showroom.ApplyQuality()
	local q = State.Setting("Quality") or 3
	lastQuality = q
	Lighting.GlobalShadows = q >= 2
	for name, minQ in { GoTrackBloom = 3, GoTrackRays = 3, GoTrackDOF = 4 } do
		local e = Lighting:FindFirstChild(name)
		if e then
			e.Enabled = q >= minQ
		end
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChild("GoTrackClouds")
	if clouds then
		clouds.Enabled = q >= 2
	end
end
State.Changed:Connect(function()
	local q = State.Setting("Quality") or 3
	if q ~= lastQuality and folder ~= nil then
		Showroom.ApplyQuality()
	end
end)

local function build()
	local f = Instance.new("Folder")
	f.Name = "GoTrackShowroom"
	-- ground: concrete plaza, pit-lane asphalt and painted lines
	P(f, Vector3.new(900, 2, 900), at(0, -1, 0), rgb(168, 172, 180), Enum.Material.Concrete)
	for k = -12, 12 do
		local l1 = P(f, Vector3.new(300, 0.06, 0.25), at(0, 0.03, k * 12 - 60), rgb(150, 154, 162))
		l1.CastShadow = false
		local l2 = P(f, Vector3.new(0.25, 0.06, 300), at(k * 12, 0.03, -60), rgb(150, 154, 162))
		l2.CastShadow = false
	end
	P(f, Vector3.new(900, 0.2, 30), at(0, 0.05, 34), rgb(74, 77, 84), Enum.Material.Asphalt)
	for _, z in { 19.2, 48.8 } do
		P(f, Vector3.new(900, 0.1, 0.8), at(0, 0.2, z), rgb(255, 255, 255))
	end
	for k = -20, 20 do
		P(f, Vector3.new(4, 0.1, 0.5), at(k * 12, 0.2, 34), rgb(255, 210, 40))
	end
	-- grass beyond the paddock
	P(f, Vector3.new(900, 1, 500), at(0, -0.2, 330), rgb(92, 168, 70), Enum.Material.Grass)
	P(f, Vector3.new(900, 1, 300), at(0, -0.2, -300), rgb(92, 168, 70), Enum.Material.Grass)

	-- turntable
	vertCyl(f, 1.2, 32, at(0, 0.6, 0), rgb(34, 36, 44), Enum.Material.Metal)
	local ring = vertCyl(f, 0.3, 29.9, at(0, 1.22, 0), rgb(255, 170, 30), Enum.Material.Neon)
	ring.Transparency = 0.45
	ring.CastShadow = false
	local disc = vertCyl(f, 0.3, 29.3, at(0, 1.26, 0), rgb(46, 50, 60), Enum.Material.SmoothPlastic)
	disc.Reflectance = 0.18
	local sp = Instance.new("Model")
	sp.Name = "Spinner"
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		local stripe = P(sp, Vector3.new(0.5, 0.06, 13), at(0, 1.43, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 7.2), rgb(74, 80, 94))
		stripe.CastShadow = false
	end
	local hub = vertCyl(sp, 0.08, 6, at(0, 1.44, 0), rgb(255, 170, 30))
	hub.CastShadow = false
	sp.WorldPivot = CFrame.new(BASE + Vector3.new(0, 1.44, 0))
	sp.Parent = f
	spinner = sp

	-- team garages
	garage(f, at(0, 0, 50), 190, rgb(225, 32, 48), "GOTRACK RACING", 5)
	garage(f, at(-185, 0, 62) * CFrame.Angles(0, math.rad(12), 0), 150, rgb(40, 110, 230), "APEX GP", 4)
	garage(f, at(185, 0, 62) * CFrame.Angles(0, math.rad(-12), 0), 150, rgb(30, 175, 110), "STUDLINK F1", 4)

	-- big screen and TV tower peeking over the roof
	P(f, Vector3.new(3, 46, 3), at(-60, 23, 110), rgb(90, 94, 104), Enum.Material.Metal)
	P(f, Vector3.new(3, 46, 3), at(-20, 23, 110), rgb(90, 94, 104), Enum.Material.Metal)
	local screen = P(f, Vector3.new(50, 24, 1.5), at(-40, 52, 110), rgb(12, 14, 20))
	sign(screen, Enum.NormalId.Front, "LIVE", rgb(255, 184, 28), rgb(16, 18, 30), "GOTRACK GRAND PRIX")
	P(f, Vector3.new(8, 70, 8), at(70, 35, 125), rgb(235, 236, 240), Enum.Material.Concrete)
	P(f, Vector3.new(20, 10, 20), at(70, 74, 125), rgb(40, 44, 54), Enum.Material.Glass).Reflectance = 0.2
	P(f, Vector3.new(21, 2, 21), at(70, 80, 125), rgb(225, 32, 48))

	-- grandstand in the distance
	for row = 0, 8 do
		P(f, Vector3.new(260, 3 + row * 3.2, 6), at(0, (3 + row * 3.2) / 2, 170 + row * 6), rgb(215, 218, 226), Enum.Material.Concrete)
		local seats = P(f, Vector3.new(258, 1.2, 3), at(0, 3.6 + row * 3.2, 170 + row * 6 - 1), if row % 3 == 0 then rgb(225, 32, 48) elseif row % 3 == 1 then rgb(245, 245, 245) else rgb(40, 110, 230))
		seats.CastShadow = false
	end
	P(f, Vector3.new(270, 1.5, 60), at(0, 34, 190), rgb(235, 237, 242), Enum.Material.Metal)

	-- trees and light poles around the plaza
	local rng = Random.new(42)
	for k = 0, 34 do
		local x = -420 + k * 24 + rng:NextNumber(-6, 6)
		tree(f, at(x, 0, 250 + rng:NextNumber(-20, 30)), rng:NextNumber(1.1, 1.8))
		tree(f, at(x, 0, -150 - rng:NextNumber(0, 60)), rng:NextNumber(1.1, 1.8))
	end
	for _, x in { -110, -55, 55, 110 } do
		P(f, Vector3.new(1.2, 26, 1.2), at(x, 13, 20), rgb(80, 84, 92), Enum.Material.Metal)
		P(f, Vector3.new(6, 1, 2.5), at(x, 26, 19), rgb(245, 245, 240), Enum.Material.Neon).CastShadow = false
	end

	-- foreground props: tyre rack, spare wing, monitor stand, flags, barrier
	for c = 0, 3 do
		tyreStack(f, at(-22 + c * 3, 0, 9), 3, if c % 2 == 0 then rgb(230, 40, 40) else rgb(250, 250, 250))
	end
	P(f, Vector3.new(7, 0.3, 1.6), at(21, 4.2, 12) * CFrame.Angles(math.rad(-10), math.rad(-25), 0), rgb(25, 25, 30))
	P(f, Vector3.new(0.3, 1.8, 1.8), at(24.2, 4.6, 13.4) * CFrame.Angles(0, math.rad(-25), 0), rgb(225, 32, 48))
	P(f, Vector3.new(0.3, 1.8, 1.8), at(17.8, 4.6, 10.6) * CFrame.Angles(0, math.rad(-25), 0), rgb(225, 32, 48))
	P(f, Vector3.new(0.4, 4, 0.4), at(21, 2, 12), rgb(70, 74, 82), Enum.Material.Metal)
	P(f, Vector3.new(0.5, 7, 0.5), at(27, 3.5, 3), rgb(70, 74, 82), Enum.Material.Metal)
	local mon = P(f, Vector3.new(5, 3.2, 0.3), at(27, 7.5, 3) * CFrame.Angles(0, math.rad(-120), 0), rgb(15, 16, 22))
	sign(mon, Enum.NormalId.Front, "P1", rgb(80, 220, 140), rgb(14, 16, 26), "SECTOR 1  23.418")
	for k, x in { -46, -34, 34, 46 } do
		local col = if k % 2 == 1 then rgb(225, 32, 48) else rgb(255, 255, 255)
		P(f, Vector3.new(0.3, 16, 0.3), at(x, 8, 17), rgb(60, 64, 72), Enum.Material.Metal)
		local banner = P(f, Vector3.new(0.15, 12, 3.4), at(x, 9.5, 18.8), col)
		banner.CastShadow = false
		local band = P(f, Vector3.new(0.2, 1.4, 3.4), at(x, 13.6, 18.8), rgb(20, 22, 30))
		band.CastShadow = false
	end
	-- soft key light on the car
	local lamp = P(f, Vector3.new(2, 0.5, 2), at(0, 30, -6), rgb(255, 255, 255))
	lamp.Transparency = 1
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Range = 40
	spot.Angle = 50
	spot.Brightness = 1.2
	spot.Shadows = false
	spot.Parent = lamp
	return f
end

function Showroom.Show()
	Showroom.ApplyLighting()
	if folder then
		return
	end
	folder = build()
	folder.Parent = workspace
	Showroom.RefreshCar()
	conn = RunService.RenderStepped:Connect(function(dt)
		if spinning then
			spinAngle += dt * 0.22
		end
		local cf = CFrame.new(CAR_POS) * CFrame.Angles(0, spinAngle, 0)
		if carModel then
			carModel:PivotTo(cf)
		end
		if spinner then
			spinner:PivotTo(CFrame.new(BASE + Vector3.new(0, 1.44, 0)) * CFrame.Angles(0, spinAngle, 0))
		end
	end)
end

function Showroom.Hide()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
		carModel = nil
		spinner = nil
	end
end

function Showroom.IsShown(): boolean
	return folder ~= nil
end

-- appearance: optional override (garage previews)
function Showroom.RefreshCar(appearance)
	if appearance ~= nil then
		previewCar = appearance
	end
	if not folder then
		return
	end
	if carModel then
		carModel:Destroy()
		carModel = nil
	end
	local car = previewCar or State.Profile.car
	local parts = CarBuilder.Build(car, { Preview = true, UserId = State.Profile.userId })
	parts.Model:PivotTo(CFrame.new(CAR_POS) * CFrame.Angles(0, spinAngle, 0))
	parts.Model.Parent = folder
	carModel = parts.Model
	Fx.RegisterRainbow(parts.Model)
end

function Showroom.ClearPreview()
	if previewCar then
		previewCar = nil
		Showroom.RefreshCar()
	end
end

function Showroom.IsPreviewing(): boolean
	return previewCar ~= nil
end

function Showroom.SetSpin(on: boolean)
	spinning = on
end

-- Camera presets -------------------------------------------------------------
-- home: car framed on the right third (menu buttons live on the left)
function Showroom.CamHome()
	Cam.SetInteractive(false)
	Showroom.SetSpin(true)
	Cam.Showroom(CAR_POS + Vector3.new(0, 3, 0), 38, 6.5, 3.8, 48, -math.pi / 2, 0.18)
end

-- page: car pushed further right / smaller so panels have room
function Showroom.CamPage()
	Cam.SetInteractive(false)
	Showroom.SetSpin(true)
	Cam.Showroom(CAR_POS, 44, 12, -4.5, 46, -math.pi / 2 - 0.35, 0.1)
end

-- garage: car centred between the two side panels, drag to rotate
function Showroom.CamGarage()
	Showroom.SetSpin(false)
	Cam.SetInteractive(true)
	Cam.Showroom(CAR_POS + Vector3.new(0, -0.5, 0), 35, 7.5, -2.9, 46, -math.pi / 2 - 0.6, 0)
end

Showroom.FocusCar = Showroom.CamGarage
Showroom.Orbit = Showroom.CamPage

return Showroom
