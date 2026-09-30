--!nonstrict
-- Race HUD (broadcast style): timing tower, lap timer + delta, position card, speed /
-- gear / rev lights, car damage diagram, minimap, start lights, messages, camera toast,
-- pause menu and touch controls. Everything sits below the Roblox top bar.

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Medals = require(Shared.Medals)
local Cosmetics = require(Shared.Cosmetics)

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local Util = require(script.Parent.Parent.Util)
local CarController = require(script.Parent.Parent.CarController)

local C = Kit.Colors
local Hud = {}

local gui, root = Kit.Screen("GoTrackHUD", 5)
gui.Enabled = false
local callbacks = {}

local DARK = Color3.fromRGB(12, 13, 20)
local PURPLE = Color3.fromRGB(190, 90, 255)
local RED = Color3.fromRGB(225, 25, 45)

local function box(parent, props)
	local f = Kit.new("Frame", { BackgroundColor3 = DARK, BackgroundTransparency = 0.12, BorderSizePixel = 0, Parent = parent })
	Kit.Apply(f, props)
	Kit.Corner(f, 10)
	return f
end

local topHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
Kit.BindInset(function(top)
	topHolder.Position = UDim2.fromOffset(0, top - 6)
	topHolder.Size = UDim2.new(1, 0, 1, -(top - 6))
end)

---------------------------------------------------------------------------
-- Timing tower (left)
---------------------------------------------------------------------------
local tower = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(250, 330), Parent = topHolder })
local towerHead = box(tower, { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = RED, BackgroundTransparency = 0 })
Kit.Gradient(towerHead, Color3.fromRGB(235, 35, 55), Color3.fromRGB(150, 10, 30), 0)
local lapLabel = Kit.Label(towerHead, "LAP 1/3", 20, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -60, 1, 0) })
local flagLabel = Kit.Label(towerHead, "", 18, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(40, 38), TextXAlignment = Enum.TextXAlignment.Right })
local towerList = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 290), Parent = tower })
Kit.List(towerList, Enum.FillDirection.Vertical, 2)
local towerRows = {}
for i = 1, 10 do
	local row = box(towerList, { Size = UDim2.new(1, 0, 0, 27), LayoutOrder = i })
	local posBox = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(245, 245, 248), Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(24, 21), Parent = row })
	Kit.Corner(posBox, 5)
	local pos = Kit.Label(posBox, tostring(i), 14, { Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = DARK })
	local bar = Kit.new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(33, 5), Size = UDim2.fromOffset(4, 17), Parent = row })
	local name = Kit.Label(row, "---", 14, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(43, 0), Size = UDim2.new(1, -130, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	local gap = Kit.Label(row, "", 13, { Font = Kit.Fonts.Mono, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(86, 27), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.SubText })
	gap.RichText = false
	towerRows[i] = { Frame = row, PosBox = posBox, Pos = pos, Bar = bar, Name = name, Gap = gap }
end

---------------------------------------------------------------------------
-- Top centre: lap timer
---------------------------------------------------------------------------
local timerBox = box(topHolder, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(300, 72) })
Kit.Stroke(timerBox, Color3.fromRGB(255, 255, 255), 1, 0.9)
local lapTimeLabel = Kit.Label(timerBox, "0:00.000", 36, { Font = Kit.Fonts.Mono, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 42), TextXAlignment = Enum.TextXAlignment.Center })
lapTimeLabel.RichText = false
local subTimeLabel = Kit.Label(timerBox, "", 13, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText })
local deltaBox = box(topHolder, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(150, 30), Visible = false })
local deltaLabel = Kit.Label(deltaBox, "", 20, { Font = Kit.Fonts.Mono, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
deltaLabel.RichText = false

---------------------------------------------------------------------------
-- Top right: position + laps
---------------------------------------------------------------------------
local posBox = box(topHolder, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(214, 124) })
local posLabel = Kit.Label(posBox, "P1", 54, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(14, 2), Size = UDim2.fromOffset(120, 60) })
local posOf = Kit.Label(posBox, "/10", 20, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(112, 24), Size = UDim2.fromOffset(80, 30), TextColor3 = C.SubText })
local lastLabel = Kit.Label(posBox, "LAST  --:--.---", 14, { Font = Kit.Fonts.Mono, Position = UDim2.fromOffset(14, 66), Size = UDim2.new(1, -28, 0, 20) })
local bestLabel = Kit.Label(posBox, "BEST  --:--.---", 14, { Font = Kit.Fonts.Mono, Position = UDim2.fromOffset(14, 90), Size = UDim2.new(1, -28, 0, 20), TextColor3 = PURPLE })
lastLabel.RichText = false
bestLabel.RichText = false

local proBox = box(topHolder, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 144), Size = UDim2.fromOffset(214, 96), Visible = false })
Kit.Label(proBox, "📊 PRO TELEMETRY", 11, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 16), TextColor3 = Color3.fromRGB(80, 200, 160) })
local sectorLabels = {}
for i = 1, 3 do
	local l = Kit.Label(proBox, "S" .. i .. "  --.---", 14, { Font = Kit.Fonts.Mono, Position = UDim2.fromOffset(12, 4 + i * 18), Size = UDim2.new(1, -24, 0, 18) })
	l.RichText = false
	sectorLabels[i] = l
end
local gapLabel = Kit.Label(proBox, "", 12, { Font = Kit.Fonts.Mono, Position = UDim2.fromOffset(12, 76), Size = UDim2.new(1, -24, 0, 18), TextColor3 = C.SubText })
gapLabel.RichText = false

local pauseBtn = Kit.Button(topHolder, "⏸", "dark", function()
	Hud.TogglePause()
end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -236, 0, 14), Size = UDim2.fromOffset(46, 46), TextSize = 20 })
local camBtn = Kit.Button(topHolder, "🎥", "dark", function()
	Hud.CameraToast(State.CycleCamera())
end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -236, 0, 66), Size = UDim2.fromOffset(46, 46), TextSize = 20 })

---------------------------------------------------------------------------
-- Bottom right: speed, gear, rev lights + damage diagram
---------------------------------------------------------------------------
local speedBox = box(root, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(300, 118) })
Kit.Stroke(speedBox, Color3.fromRGB(255, 255, 255), 1, 0.9)
local leds = {}
for i = 1, 15 do
	local led = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(40, 44, 60), BorderSizePixel = 0, Position = UDim2.fromOffset(84 + (i - 1) * 13.5, 10), Size = UDim2.fromOffset(10, 10), Parent = speedBox })
	Kit.Round(led)
	leds[i] = led
end
local gearLabel = Kit.Label(speedBox, "N", 58, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(84, 26), Size = UDim2.fromOffset(60, 64), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Accent })
local speedLabel = Kit.Label(speedBox, "0", 46, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(140, 28), Size = UDim2.new(1, -156, 0, 50), TextXAlignment = Enum.TextXAlignment.Right })
local unitLabel = Kit.Label(speedBox, "KM/H", 12, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(140, 78), Size = UDim2.new(1, -156, 0, 14), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.SubText })
local slipLabel = Kit.Label(speedBox, "", 11, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(84, 96), Size = UDim2.new(1, -100, 0, 16), TextColor3 = C.Accent2 })

-- damage diagram (top-down car)
local dmgHolder = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(60, 98), Parent = speedBox })
local dmgParts = {}
local function dmgPiece(key, x, y, w, h)
	local f = Kit.new("Frame", { BackgroundColor3 = C.Success, BorderSizePixel = 0, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Parent = dmgHolder })
	Kit.Corner(f, 3)
	dmgParts[key] = f
end
dmgPiece("FrontWing", 4, 0, 52, 8)
dmgPiece("Nose", 26, 8, 8, 20)
dmgPiece("Left", 8, 34, 14, 32)
dmgPiece("Right", 38, 34, 14, 32)
dmgPiece("Engine", 23, 28, 14, 48)
dmgPiece("Tail", 26, 74, 8, 14) -- gearbox: joins the engine to the rear wing like the nose does at the front
dmgPiece("RearWing", 8, 86, 44, 10)

---------------------------------------------------------------------------
-- Minimap (bottom left)
---------------------------------------------------------------------------
local mapBox = box(root, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18), Size = UDim2.fromOffset(210, 210) })
Kit.Stroke(mapBox, Color3.fromRGB(255, 255, 255), 1, 0.9)
local mapArea = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), Parent = mapBox })
local mapDots = {}
local mapTransform = nil

local function drawLine(parent, a: Vector2, b: Vector2, thick: number, color: Color3, z: number?)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local f = Kit.new("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(mid.X, mid.Y),
		Size = UDim2.fromOffset(len + thick * 0.6, thick),
		Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X)),
		ZIndex = z or 1,
		Parent = parent,
	})
	return f
end
Hud.DrawLine = drawLine

-- Draws a track outline into a frame of `size` px. Returns a function mapping world x,z -> Vector2
function Hud.DrawTrack(parent: Instance, minimap, size: number, thick: number?, color: Color3?)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in minimap do
		minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
		minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
	end
	local span = math.max(maxX - minX, maxZ - minZ, 1)
	local scale = (size - 8) / span
	local ox = (size - (maxX - minX) * scale) / 2
	local oz = (size - (maxZ - minZ) * scale) / 2
	local function map(x: number, z: number): Vector2
		return Vector2.new(ox + (x - minX) * scale, oz + (z - minZ) * scale)
	end
	local n = #minimap
	for i = 1, n do
		local a = minimap[i]
		local b = minimap[(i % n) + 1]
		drawLine(parent, map(a[1], a[2]), map(b[1], b[2]), thick or 4, color or Color3.fromRGB(230, 230, 240))
	end
	local s0 = minimap[1]
	local sp = map(s0[1], s0[2])
	local flag = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sp.X, sp.Y), Size = UDim2.fromOffset(10, 10), ZIndex = 2, Parent = parent })
	Kit.Corner(flag, 2)
	Kit.Stroke(flag, Color3.new(0, 0, 0), 1.5, 0)
	return map
end

---------------------------------------------------------------------------
-- Start lights, messages, warnings, camera toast
---------------------------------------------------------------------------
local lightsBox = box(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 170), Size = UDim2.fromOffset(380, 92), Visible = false })
local lightDots = {}
for k = 1, 5 do
	local pod = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(22, 22, 28), Position = UDim2.fromOffset(16 + (k - 1) * 72, 10), Size = UDim2.fromOffset(60, 72), Parent = lightsBox })
	Kit.Corner(pod, 10)
	local dots = {}
	for r = 0, 1 do
		local dot = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(60, 15, 15), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 20 + r * 32), Size = UDim2.fromOffset(26, 26), Parent = pod })
		Kit.Round(dot)
		table.insert(dots, dot)
	end
	lightDots[k] = dots
end

local bigMessage = Kit.Label(root, "", 44, { Font = Kit.Fonts.Title, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(1000, 60), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, Visible = false })
local bigScale = Kit.new("UIScale", { Parent = bigMessage })
local warnBox = box(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X, Visible = false, BackgroundColor3 = Color3.fromRGB(120, 10, 20) })
Kit.Padding(warnBox, 22, 0)
local warnLabel = Kit.Label(warnBox, "", 24, { Font = Kit.Fonts.Title, Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center })

local camToast = box(root, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Visible = false })
Kit.Padding(camToast, 18, 0)
local camToastLabel = Kit.Label(camToast, "", 16, { Font = Kit.Fonts.Title, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center })

local hint = Kit.Label(root, "", 12, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(760, 16),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = C.SubText,
	TextStrokeTransparency = 0.6,
})

---------------------------------------------------------------------------
-- Pause menu
---------------------------------------------------------------------------
local pausePanel = Kit.Panel(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(360, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 8 })
Kit.Padding(pausePanel, 22, 20)
Kit.List(pausePanel, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center)
Kit.Label(pausePanel, "PAUSED", 30, { Font = Kit.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 0, ZIndex = 9 })
local pauseNote = Kit.Label(pausePanel, "The race keeps going while you're paused!", 13, { TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, ZIndex = 9, TextColor3 = C.SubText })
Kit.Button(pausePanel, "▶  Resume", "primary", function()
	pausePanel.Visible = false
end, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 2, ZIndex = 9 })
Kit.Button(pausePanel, "🔧  Reset & repair car", "secondary", function()
	pausePanel.Visible = false
	if callbacks.Reset then
		callbacks.Reset()
	end
end, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 3, ZIndex = 9 })
local restartBtn = Kit.Button(pausePanel, "⏮  Restart lap", "secondary", function()
	pausePanel.Visible = false
	if callbacks.Restart then
		callbacks.Restart()
	end
end, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 4, ZIndex = 9 })
local camPauseBtn
camPauseBtn = Kit.Button(pausePanel, "🎥  Camera: Chase", "secondary", function()
	local name = State.CycleCamera()
	camPauseBtn.Text = "🎥  Camera: " .. name
end, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 5, ZIndex = 9 })
local lineBtn
lineBtn = Kit.Button(pausePanel, "🟢  Racing line: Full", "secondary", function()
	local order = { "full", "braking", "off" }
	local cur = State.Setting("RacingLine")
	local nextMode = order[((table.find(order, cur) or 1) % 3) + 1]
	State.SetSetting("RacingLine", nextMode)
	lineBtn.Text = "🟢  Racing line: " .. (if nextMode == "full" then "Full" elseif nextMode == "braking" then "Braking zones" else "Off")
end, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 6, ZIndex = 9 })
local exitBtn = Kit.Button(pausePanel, "🏳️  Leave race", "danger", function()
	pausePanel.Visible = false
	if callbacks.Exit then
		callbacks.Exit()
	end
end, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 7, ZIndex = 9 })

---------------------------------------------------------------------------
-- Touch controls
---------------------------------------------------------------------------
local touchFrame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })
local function touchButton(text, pos, size, anchor, flag, color)
	local b = Kit.new("TextButton", {
		Text = text,
		Font = Kit.Fonts.Title,
		TextSize = 24,
		TextColor3 = C.Text,
		AutoButtonColor = false,
		BackgroundColor3 = color or C.Panel2,
		BackgroundTransparency = 0.35,
		AnchorPoint = anchor,
		Position = pos,
		Size = UDim2.fromOffset(size.X, size.Y),
		Parent = touchFrame,
	})
	Kit.Corner(b, 24)
	Kit.Stroke(b, Color3.new(1, 1, 1), 2, 0.6)
	b.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			CarController.Input[flag] = true
			b.BackgroundTransparency = 0.05
		end
	end)
	b.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			CarController.Input[flag] = false
			b.BackgroundTransparency = 0.35
		end
	end)
	return b
end
touchButton("◀", UDim2.new(0, 28, 1, -36), Vector2.new(124, 124), Vector2.new(0, 1), "TouchLeft")
touchButton("▶", UDim2.new(0, 168, 1, -36), Vector2.new(124, 124), Vector2.new(0, 1), "TouchRight")
touchButton("GAS", UDim2.new(1, -28, 1, -150), Vector2.new(140, 140), Vector2.new(1, 1), "TouchThrottle", Color3.fromRGB(40, 160, 80))
touchButton("BRAKE", UDim2.new(1, -186, 1, -36), Vector2.new(120, 100), Vector2.new(1, 1), "TouchBrake", Color3.fromRGB(180, 50, 50))
touchButton("DRIFT", UDim2.new(1, -28, 1, -30), Vector2.new(140, 96), Vector2.new(1, 1), "TouchDrift", Color3.fromRGB(60, 90, 170))

-- Lays the HUD out for the current screen. Phones (Kit.Compact) get smaller boxes and the
-- speedometer moves to the bottom centre, between the touch pads, so nothing overlaps.
local function scaleOf(f: GuiObject): UIScale
	return f:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = f })
end
local lastTouch = false
function Hud.ApplyLayout(touch: boolean?)
	if touch == nil then
		touch = lastTouch
	end
	lastTouch = touch :: boolean
	local compact = Kit.Compact()
	scaleOf(tower).Scale = if compact then 0.72 else 1
	scaleOf(timerBox).Scale = if compact then 0.8 else 1
	scaleOf(posBox).Scale = if compact then 0.75 else 1
	scaleOf(proBox).Scale = if compact then 0.75 else 1
	proBox.Position = UDim2.new(1, -14, 0, if compact then 110 else 144)
	scaleOf(speedBox).Scale = if compact then 0.72 else 1
	scaleOf(mapBox).Scale = 1
	if touch and compact then
		speedBox.AnchorPoint = Vector2.new(0.5, 1)
		speedBox.Position = UDim2.new(0.5, 0, 1, -8)
		-- the right side belongs to the GAS/BRAKE pads: minimap goes top-left, next to the
		-- timing tower, and the pro telemetry box is hidden on phones
		mapBox.AnchorPoint = Vector2.new(0, 0)
		scaleOf(mapBox).Scale = 104 / 210
		local top = Kit.Inset()
		mapBox.Position = UDim2.new(0, 14 + 250 * 0.72 + 10, 0, top + 8)
	elseif touch then
		speedBox.AnchorPoint = Vector2.new(1, 1)
		speedBox.Position = UDim2.new(1, -18, 1, -170)
		mapBox.AnchorPoint = Vector2.new(0, 1)
		mapBox.Position = UDim2.new(0.5, -75, 1, -18)
		scaleOf(mapBox).Scale = 150 / 210
	else
		speedBox.AnchorPoint = Vector2.new(1, 1)
		speedBox.Position = UDim2.new(1, -18, 1, -18)
		mapBox.AnchorPoint = Vector2.new(0, 1)
		mapBox.Position = UDim2.new(0, 18, 1, -18)
		scaleOf(mapBox).Scale = if compact then 160 / 210 else 1
	end
end
Kit.BindInset(function()
	Hud.ApplyLayout()
end)

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local racersById = {}
local myRid = 0

local function abbrev(name: string): string
	local n = string.upper((string.gsub(name, "[^%w ]", "")))
	local parts = string.split(n, " ")
	local last = parts[#parts] or n
	if #last >= 3 then
		return string.sub(last, 1, 3)
	end
	return string.sub(n, 1, 3)
end

-- opts: { mode = "race"|"tt", trackName, flag, laps, racers = {Rid, Name, Car, IsAI}, yourRid, minimap, exitText }
function Hud.Show(opts)
	gui.Enabled = true
	myRid = opts.yourRid or 0
	racersById = {}
	for _, r in opts.racers or {} do
		racersById[r.Rid] = r
	end
	local isRace = opts.mode == "race"
	tower.Visible = isRace
	posLabel.Visible = isRace
	posOf.Visible = isRace
	restartBtn.Visible = not isRace
	pauseNote.Text = if isRace then "The race keeps going while you're paused!" else "Your lap timer keeps running."
	exitBtn.Text = opts.exitText or (if isRace then "🏳️  Leave race" else "🏠  Exit")
	proBox.Visible = State.HasPass("ProRacer") and not (Kit.Compact() and Kit.Touch())
	lapLabel.Text = string.format("LAP 1/%d", opts.laps or 1)
	flagLabel.Text = opts.flag or ""
	lastLabel.Text = "LAST  --:--.---"
	bestLabel.Text = "BEST  --:--.---"
	subTimeLabel.Text = if isRace then opts.trackName else "TIME TRIAL  •  " .. opts.trackName
	deltaBox.Visible = false
	bigMessage.Visible = false
	warnBox.Visible = false
	pausePanel.Visible = false
	lightsBox.Visible = false
	camToast.Visible = false
	for i = 1, 3 do
		sectorLabels[i].Text = "S" .. i .. "  --.---"
		sectorLabels[i].TextColor3 = C.Text
	end
	for _, m in State.CameraModes do
		if m[1] == State.Setting("Camera") then
			camPauseBtn.Text = "🎥  Camera: " .. m[2]
		end
	end
	local rl = State.Setting("RacingLine")
	lineBtn.Text = "🟢  Racing line: " .. (if rl == "full" then "Full" elseif rl == "braking" then "Braking zones" else "Off")
	-- minimap
	Util.Clear(mapArea)
	mapDots = {}
	mapTransform = Hud.DrawTrack(mapArea, opts.minimap, 190, 4)
	local touch = Kit.Touch()
	touchFrame.Visible = touch
	hint.Visible = not touch
	if isRace then
		hint.Text = "WASD / Arrows drive  •  Space drift  •  R repair / reset  •  C camera  •  P pause"
	else
		hint.Text = "WASD / Arrows drive  •  Space drift  •  R restart lap  •  Backspace repair / reset  •  C camera  •  P pause"
	end
	Hud.ApplyLayout(touch)
	camBtn.Visible = true
	Hud.SetDamage(nil)
end

-- Hide / show the race HUD without resetting it (the circuit intro plays over the grid)
function Hud.SetVisible(on: boolean)
	gui.Enabled = on
end

function Hud.Hide()
	gui.Enabled = false
	for k in callbacks do
		callbacks[k] = nil
	end
end

function Hud.SetCallbacks(cbs)
	for k, v in cbs do
		callbacks[k] = v
	end
end

function Hud.TogglePause()
	pausePanel.Visible = not pausePanel.Visible
end

function Hud.SetLap(cur: number, total: number)
	lapLabel.Text = string.format("LAP %d/%d", math.clamp(cur, 1, total), total)
end

function Hud.SetLapTime(ms: number)
	lapTimeLabel.Text = Medals.FormatTime(math.max(ms, 0))
end

function Hud.SetSubText(text: string)
	subTimeLabel.Text = text
end

function Hud.SetPosition(p: number, total: number)
	posLabel.Text = "P" .. p
	posOf.Text = "/" .. total
end

function Hud.SetLast(ms: number?)
	lastLabel.Text = "LAST  " .. Medals.FormatTime(ms)
end

function Hud.SetBest(ms: number?)
	bestLabel.Text = "BEST  " .. Medals.FormatTime(ms)
end

local LED_COLORS = {}
for i = 1, 15 do
	LED_COLORS[i] = if i <= 5 then Color3.fromRGB(50, 230, 90) elseif i <= 10 then Color3.fromRGB(255, 45, 45) else Color3.fromRGB(80, 120, 255)
end
function Hud.SetSpeed(studs: number, gear: number, rpm: number, slip: number?, aero: boolean?)
	local text, unit = State.SpeedText(studs)
	speedLabel.Text = text
	unitLabel.Text = unit
	gearLabel.Text = if gear == 0 then "R" else tostring(gear)
	local lit = math.floor(rpm * 15 + 0.5)
	for i, led in leds do
		led.BackgroundColor3 = if i <= lit then LED_COLORS[i] else Color3.fromRGB(40, 44, 60)
	end
	if slip and slip > 0.2 then
		slipLabel.Text = if aero then "💨 SLIPSTREAM + ⚡ AERO" else "💨 SLIPSTREAM"
	else
		slipLabel.Text = if aero then "⚡ STRAIGHT MODE" else ""
	end
end

local function healthColor(h: number): Color3
	if h > 0.75 then
		return C.Success
	elseif h > 0.45 then
		return C.Warn
	end
	return C.Danger
end

-- damage: { FrontWing, RearWing, Left, Right, Engine } (0..1) or nil for a fresh car
function Hud.SetDamage(damage)
	local d = damage or { FrontWing = 1, RearWing = 1, Left = 1, Right = 1, Engine = 1 }
	dmgParts.FrontWing.BackgroundColor3 = healthColor(d.FrontWing)
	dmgParts.Nose.BackgroundColor3 = healthColor(math.min(1, d.FrontWing + 0.3))
	dmgParts.RearWing.BackgroundColor3 = healthColor(d.RearWing)
	dmgParts.Tail.BackgroundColor3 = healthColor(math.min(1, d.RearWing + 0.3))
	dmgParts.Left.BackgroundColor3 = healthColor(d.Left)
	dmgParts.Right.BackgroundColor3 = healthColor(d.Right)
	dmgParts.Engine.BackgroundColor3 = healthColor(d.Engine)
	dmgParts.FrontWing.BackgroundTransparency = if d.FrontWing < 0.45 then 0.75 else 0
	dmgParts.RearWing.BackgroundTransparency = if d.RearWing < 0.45 then 0.75 else 0
end

function Hud.SetDelta(ms: number?)
	if not ms then
		deltaBox.Visible = false
		return
	end
	deltaBox.Visible = true
	deltaLabel.Text = Medals.FormatDelta(ms)
	deltaLabel.TextColor3 = if ms <= 0 then C.Success else C.Danger
end

function Hud.SetSector(i: number, ms: number?, st: string?)
	local l = sectorLabels[i]
	if not l then
		return
	end
	l.Text = "S" .. i .. "  " .. (if ms then string.format("%.3f", ms / 1000) else "--.---")
	l.TextColor3 = if st == "purple" then PURPLE elseif st == "green" then C.Success elseif st == "yellow" then C.Warn else C.Text
end

function Hud.SetGapText(text: string)
	gapLabel.Text = text
end

-- n = number of red lights (0..5), -1 hides the lights, "go" turns them all green
function Hud.SetLights(n: number | string)
	if n == "go" then
		lightsBox.Visible = true
		for _, dots in lightDots do
			for _, dot in dots do
				dot.BackgroundColor3 = Color3.fromRGB(40, 230, 90)
			end
		end
		return
	end
	local count = n :: number
	if count < 0 then
		lightsBox.Visible = false
		return
	end
	lightsBox.Visible = true
	for k, dots in lightDots do
		for _, dot in dots do
			dot.BackgroundColor3 = if count >= k then Color3.fromRGB(255, 30, 30) else Color3.fromRGB(60, 15, 15)
		end
	end
end

local msgToken = 0
function Hud.Message(text: string, color: Color3?, duration: number?)
	msgToken += 1
	local my = msgToken
	bigMessage.Text = text
	bigMessage.TextColor3 = color or C.Text
	bigMessage.Visible = true
	bigScale.Scale = 1.4
	Kit.Tween(bigScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(duration or 2, function()
		if msgToken == my then
			bigMessage.Visible = false
		end
	end)
end

function Hud.Warning(text: string?)
	warnBox.Visible = text ~= nil
	if text then
		warnLabel.Text = text
	end
end

local camToken = 0
function Hud.CameraToast(name: string)
	camToken += 1
	local my = camToken
	camToastLabel.Text = "🎥  " .. string.upper(name)
	camToast.Visible = true
	task.delay(1.4, function()
		if camToken == my then
			camToast.Visible = false
		end
	end)
	for _, m in State.CameraModes do
		if m[2] == name then
			camPauseBtn.Text = "🎥  Camera: " .. name
		end
	end
end

-- standings: server list
function Hud.UpdateTower(standings)
	local list = standings.List or {}
	local fastest = standings.Fastest
	for i, row in towerRows do
		local s = list[i]
		if s then
			row.Frame.Visible = true
			local r = racersById[s.Rid]
			row.Pos.Text = tostring(s.P)
			local name = if r then r.Name else "?"
			row.Name.Text = (if s.Rid == myRid then name else abbrev(name)) .. (if s.F then " 🏁" else "")
			local prim = r and r.Car and Cosmetics.ById[r.Car.Primary or ""]
			row.Bar.BackgroundColor3 = if prim and prim.Color then prim.Color else C.Accent
			if s.D and not s.F then
				row.Gap.Text = "OUT"
			elseif s.P == 1 then
				row.Gap.Text = if s.F then "WINNER" else "LEADER"
			elseif s.LP and s.LP >= 1 then
				row.Gap.Text = "+" .. s.LP .. " LAP"
			elseif s.G then
				row.Gap.Text = string.format("+%.3f", s.G)
			else
				row.Gap.Text = ""
			end
			row.Gap.TextColor3 = if fastest and fastest.Rid == s.Rid then PURPLE else C.SubText
			local isMe = s.Rid == myRid
			row.Frame.BackgroundColor3 = if isMe then Color3.fromRGB(255, 190, 40) else DARK
			row.Frame.BackgroundTransparency = if isMe then 0.02 else 0.12
			row.Name.TextColor3 = if isMe then Color3.fromRGB(20, 15, 5) else C.Text
			row.Gap.TextColor3 = if isMe then Color3.fromRGB(60, 40, 10) else row.Gap.TextColor3
		else
			row.Frame.Visible = false
		end
	end
end

-- positions: { [rid] = {x, z} }
function Hud.UpdateMinimap(positions)
	if not mapTransform then
		return
	end
	for rid, p in positions do
		local dot = mapDots[rid]
		if not dot then
			local me = rid == myRid
			local r = racersById[rid]
			local prim = r and r.Car and Cosmetics.ById[r.Car.Primary or ""]
			dot = Kit.new("Frame", {
				BackgroundColor3 = if me then Color3.new(1, 1, 1) elseif prim and prim.Color then prim.Color else C.Accent,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(if me then 12 else 8, if me then 12 else 8),
				ZIndex = if me then 5 else 4,
				Parent = mapArea,
			})
			Kit.Round(dot)
			Kit.Stroke(dot, Color3.new(0, 0, 0), if me then 2 else 1, 0)
			mapDots[rid] = dot
		end
		local v = mapTransform(p[1], p[2])
		dot.Position = UDim2.fromOffset(v.X, v.Y)
	end
end

return Hud
