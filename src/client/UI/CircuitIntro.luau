--!nonstrict
-- The circuit intro: a TV-broadcast style presentation of each circuit before a race or
-- time trial.
--  1. Begin(): while the circuit is being built - the circuit's colours, round, flag and
--     name, blurb, a track map that draws itself with a car dot lapping it, 8 stat tiles,
--     conditions (time of day, weather, temperature, type, difficulty), the circuit's
--     landmarks and a real build progress bar.
--  2. Reveal(): the world fades in behind letterbox bars and the camera flies over the
--     circuit (aerial orbit -> a landmark fly-past -> down onto your car on the grid) with
--     lower-third captions, a mini map and a countdown. Skippable (Space / Enter / A / tap).
--  3. The HUD and chase camera take over.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Circuits = require(Shared.Circuits)
local Track = require(Shared.Track)
local Themes = require(Shared.Themes)
local CircuitInfo = require(Shared.CircuitInfo)
local Medals = require(Shared.Medals)

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local Cam = require(script.Parent.Parent.CameraController)
local Landmarks = require(script.Parent.Parent.Landmarks)
local Util = require(script.Parent.Parent.Util)

local Intro = {}

local C = Kit.Colors
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local gui, root = Kit.Screen("GoTrackIntro", 45)
gui.Enabled = false

local active = nil -- the running intro
-- keep the broadcast header clear of the Roblox buttons (top-left)
local insetLeft = 180
local function placeHeader(header: Frame)
	local x = math.max(20, insetLeft + 12)
	header.Position = UDim2.fromOffset(x, 0)
	header.Size = UDim2.new(1, -x - 20, 1, -3)
end
Kit.BindInset(function(_top, left)
	insetLeft = left
	if active and active.Header and active.Header.Parent then
		placeHeader(active.Header)
	end
end)
local SECTOR = { rgb(255, 70, 80), rgb(70, 170, 255), rgb(255, 205, 50) }

local MODE_NAMES = { quick = "QUICK RACE", ranked = "RANKED", private = "PRIVATE RACE", tt = "TIME TRIAL" }

local function dark(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), f)
end

local function text(parent, str: string, size: number, props)
	local l = Kit.Label(parent, str, size, props)
	return l
end

-- a straight line between two points of a map, drawn as a rotated frame
local function line(parent, a: Vector2, b: Vector2, thick: number, color: Color3, z: number?): Frame
	local d = b - a
	local f = Kit.new("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Size = UDim2.fromOffset(d.Magnitude + thick * 0.6, thick),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		ZIndex = z or 3,
		Parent = parent,
	})
	return f
end

local function timeIcon(th): string
	local tod = th.TimeOfDay
	if tod == "Morning" then
		return "🌅"
	elseif tod == "Midday" then
		return "☀️"
	elseif tod == "Afternoon" then
		return "🌤️"
	elseif tod == "Sunset" then
		return "🌇"
	end
	return "🌙"
end

local function weatherIcon(th): string
	if th.Weather == "rain" then
		return "🌧️"
	elseif th.Weather == "snow" then
		return "🌨️"
	elseif th.Weather == "ash" then
		return "🌋"
	elseif th.Sky.Cloud and th.Sky.Cloud > 0.6 then
		return "☁️"
	end
	return if th.Night then "✨" else "🌤️"
end

local function chip(parent, str: string, color: Color3, order: number)
	local f = Kit.new("Frame", { BackgroundColor3 = dark(color, 0.55), BackgroundTransparency = 0.15, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = parent })
	Kit.Round(f)
	Kit.Stroke(f, color, 1.2, 0.4)
	Kit.Padding(f, 12, 0)
	text(f, str, 14, { Font = Kit.Fonts.Bold, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, TextColor3 = C.Text })
	return f
end

-- stat tile: icon, big value (counts up), caption
local function tile(parent, icon: string, value: number, fmt: string, caption: string, accent: Color3, order: number, counters)
	local f = Kit.new("Frame", { BackgroundColor3 = rgb(12, 14, 26), BackgroundTransparency = 0.2, LayoutOrder = order, Parent = parent })
	Kit.Corner(f, 12)
	Kit.Stroke(f, accent, 1, 0.7)
	local bar = Kit.new("Frame", { BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(0, 8), Parent = f })
	Kit.Corner(bar, 2)
	-- icon + caption on top, the number big underneath
	text(f, icon, 14, { Position = UDim2.fromOffset(12, 7), Size = UDim2.fromOffset(18, 18) })
	text(f, caption, 11, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(32, 7), Size = UDim2.new(1, -36, 0, 18), TextColor3 = C.SubText, TextTruncate = Enum.TextTruncate.AtEnd })
	local v = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = string.format(fmt, 0),
		FontFace = Kit.Faces.Sub,
		TextSize = 28,
		TextScaled = true,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -18, 0, 40),
		Parent = f,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 30, Parent = v })
	table.insert(counters, { Label = v, Target = value, Fmt = fmt })
	return f
end

-- builds the track map (hidden segments revealed over time); returns map(x, z) -> Vector2
local function buildMap(holder, t, size: number, thick: number)
	local mini = t.Minimap
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in mini do
		minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
		minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
	end
	local span = math.max(maxX - minX, maxZ - minZ, 1)
	local scale = (size - 24) / span
	local ox = (size - (maxX - minX) * scale) / 2
	local oz = (size - (maxZ - minZ) * scale) / 2
	local function map(x: number, z: number): Vector2
		return Vector2.new(ox + (x - minX) * scale, oz + (z - minZ) * scale)
	end
	local n = #mini
	local segs = {}
	for i = 1, n do
		local a, b = mini[i], mini[(i % n) + 1]
		local sector = math.clamp(math.floor((i - 1) / n * 3) + 1, 1, 3)
		-- a dark casing under the coloured line so it reads on any background
		local under = line(holder, map(a[1], a[2]), map(b[1], b[2]), thick + 4, rgb(8, 10, 18), 2)
		local over = line(holder, map(a[1], a[2]), map(b[1], b[2]), thick, SECTOR[sector], 3)
		under.Visible = false
		over.Visible = false
		table.insert(segs, { under, over })
	end
	local s0 = map(mini[1][1], mini[1][2])
	local flag = Kit.new("TextLabel", { BackgroundTransparency = 1, Text = "🏁", TextSize = 22, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(s0.X, s0.Y - 4), Size = UDim2.fromOffset(26, 26), ZIndex = 6, Visible = false, Parent = holder })
	local dot = Kit.new("Frame", { BackgroundColor3 = C.White, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(thick + 7, thick + 7), ZIndex = 7, Visible = false, Parent = holder })
	Kit.Round(dot)
	Kit.Stroke(dot, rgb(10, 12, 20), 2, 0)
	return map, segs, flag, dot
end

local function lapPoint(t, map, s: number): Vector2
	local x, _, z = Track.PointAt(t, s)
	return map(x, z)
end

-- One line of advice for a circuit, based on its layout and conditions
function Intro.Tip(trackId: string): string
	local c = Circuits.ById[trackId]
	local th = Themes[c.Theme] or Themes.park
	local s = CircuitInfo.Get(trackId)
	if th.Weather == "rain" then
		return "Rain and spray cut the view: learn the braking boards and brake at the same one every lap."
	elseif th.Weather == "snow" or th.Weather == "ash" then
		return "Snow in the air: the orange racing line shows every braking zone - trust it."
	elseif s.BrakingZones >= 15 then
		return string.format("%d big stops a lap: brake early and in a straight line, then get on the power early.", s.BrakingZones)
	elseif s.LongestStraightM >= 600 then
		return string.format("A %d m straight: tuck into the slipstream and pass into the next corner.", math.floor(s.LongestStraightM / 10) * 10)
	elseif s.Type == "Street circuit" then
		return "Walls everywhere: a clean lap beats a risky one. Crashes cost time to repair."
	elseif s.ElevationM >= 12 then
		return "Big hills: the car goes light over the crests. Straighten up before you brake."
	elseif s.Corners >= 32 then
		return string.format("%d corners: keep a smooth rhythm - the esses reward patience.", s.Corners)
	elseif s.FullThrottle >= 0.35 then
		return "A fast, flowing lap: carry speed through the quick bends and don't over-brake."
	end
	return "Use the racing line: green means flat out, red means brake now."
end

---------------------------------------------------------------------------
-- Begin: the loading card
---------------------------------------------------------------------------
-- opts: { Mode = "quick"|"ranked"|"private"|"tt", Laps, Slot, Racers }
function Intro.Begin(trackId: string, opts)
	Intro.Stop()
	opts = opts or {}
	local c = Circuits.ById[trackId]
	local t = Track.Get(trackId)
	if not c or not t then
		return
	end
	local th = Themes[c.Theme] or Themes.park
	local info = CircuitInfo.Get(trackId)
	local accent = th.Accent
	local run = { Track = t, Circuit = c, Theme = th, Opts = opts, Conns = {}, Counters = {}, Start = os.clock() }
	active = run
	Util.Clear(root, true)
	gui.Enabled = true

	-- background: the circuit's colours with moving speed stripes
	local bg = Kit.new("Frame", { Name = "Bg", BackgroundColor3 = C.White, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = root })
	Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, dark(accent, 0.45)),
			ColorSequenceKeypoint.new(0.45, dark(accent, 0.82)),
			ColorSequenceKeypoint.new(1, rgb(8, 9, 16)),
		}),
		Rotation = 25,
		Parent = bg,
	})
	local stripes = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 1, Parent = bg })
	for k = 0, 7 do
		local sfr = Kit.new("Frame", {
			BackgroundColor3 = if k % 2 == 0 then accent else C.White,
			BackgroundTransparency = if k % 2 == 0 then 0.86 else 0.94,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(k * 0.16, 0.5),
			Size = UDim2.new(0, 40 + (k % 3) * 30, 2, 0),
			Rotation = 25,
			ZIndex = 1,
			Parent = stripes,
		})
		sfr:SetAttribute("Base", k * 0.16)
	end
	run.Bg = bg
	run.Stripes = stripes

	-- letterbox bars (always on)
	local topBar = Kit.new("Frame", { Name = "TopBar", BackgroundColor3 = rgb(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 64), ZIndex = 20, Parent = root })
	local botBar = Kit.new("Frame", { Name = "BotBar", BackgroundColor3 = rgb(0, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 70), ZIndex = 20, Parent = root })
	run.TopBar, run.BotBar = topBar, botBar
	local accentLine = Kit.new("Frame", { BackgroundColor3 = accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), ZIndex = 21, Parent = topBar })
	local _ = accentLine
	-- broadcast header: round + mode (left, after the Roblox buttons), LIVE bug (right)
	local header = Kit.new("Frame", { BackgroundTransparency = 1, ZIndex = 21, Parent = topBar })
	placeHeader(header)
	run.Header = header
	local hl = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.7, 1), ZIndex = 21, Parent = header })
	Kit.List(hl, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	chip(hl, string.format("ROUND %d / %d", c.Round, #Circuits.List), accent, 1)
	chip(hl, MODE_NAMES[opts.Mode or "quick"] or "RACE", if opts.Mode == "ranked" then C.Purple elseif opts.Mode == "tt" then C.Accent2 else C.Accent, 2)
	if opts.Laps then
		chip(hl, string.format("%d LAPS", opts.Laps), C.Success, 3)
	end
	local live = Kit.new("Frame", { BackgroundColor3 = rgb(200, 20, 30), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(196, 30), ZIndex = 21, Parent = header })
	Kit.Corner(live, 6)
	local liveDot = Kit.new("Frame", { BackgroundColor3 = C.White, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(10, 10), ZIndex = 22, Parent = live })
	Kit.Round(liveDot)
	text(live, "LIVE  •  GOTRACK TV", 13, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), ZIndex = 22 })
	run.LiveDot = liveDot

	-- LEFT: identity, blurb, conditions, stats --------------------------------------------
	local left = Kit.new("Frame", { Name = "Left", BackgroundTransparency = 1, Position = UDim2.new(0, 56, 0, 86), Size = UDim2.new(0.5, -40, 1, -180), ZIndex = 5, Parent = root })
	run.Left = left
	local flagL = text(left, c.Flag, 58, { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(74, 70), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	local _ = flagL
	local name = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = string.upper(c.Name),
		FontFace = Kit.Faces.Logo,
		TextSize = 48,
		TextScaled = true,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(84, 4),
		Size = UDim2.new(1, -84, 0, 52),
		ZIndex = 5,
		Parent = left,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 48, Parent = name })
	Kit.new("UIStroke", { Color = rgb(0, 0, 0), Thickness = 2, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = name })
	local under = Kit.new("Frame", { BackgroundColor3 = accent, BorderSizePixel = 0, Position = UDim2.fromOffset(86, 58), Size = UDim2.fromOffset(0, 5), ZIndex = 5, Parent = left })
	Kit.Corner(under, 3)
	Kit.Tween(under, 0.8, { Size = UDim2.fromOffset(220, 5) }, Enum.EasingStyle.Quart)
	text(left, string.format("%s  %s  •  %s", th.Icon, string.upper(c.Region), th.Name), 16, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(86, 66), Size = UDim2.new(1, -86, 0, 22), TextColor3 = accent:Lerp(C.White, 0.45), ZIndex = 5 })
	text(left, c.Blurb, 17, { Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 46), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Text, ZIndex = 5 })
	-- conditions
	local cond = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 150), Size = UDim2.new(1, 0, 0, 30), ZIndex = 5, Parent = left })
	Kit.List(cond, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	chip(cond, timeIcon(th) .. "  " .. th.TimeOfDay, rgb(255, 190, 80), 1)
	chip(cond, weatherIcon(th) .. "  " .. th.Conditions .. "  " .. th.Temp .. "°C", rgb(120, 190, 255), 2)
	chip(cond, if info.Type == "Street circuit" then "🏙️  Street" elseif info.Type == "Bonus circuit" then "⭐  Bonus" else "🏁  Permanent", rgb(170, 170, 190), 3)
	chip(cond, CircuitInfo.Stars(info.Difficulty), C.Gold, 4)
	-- stat tiles
	local grid = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 194), Size = UDim2.new(1, 0, 0, 172), ZIndex = 5, Parent = left })
	local gl = Kit.new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, 80), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	local _gl = gl
	local laps = opts.Laps or info.Laps
	local cnt = run.Counters
	tile(grid, "📏", info.LengthKm, "%.2f km", "LAP LENGTH", accent, 1, cnt)
	tile(grid, "🔁", laps, "%d", "LAPS", accent, 2, cnt)
	tile(grid, "↪️", info.Corners, "%d", "CORNERS", accent, 3, cnt)
	tile(grid, "🛑", info.BrakingZones, "%d", "BRAKING ZONES", accent, 4, cnt)
	tile(grid, "🚀", info.LongestStraightM, "%d m", "STRAIGHT", accent, 5, cnt)
	tile(grid, "⚡", info.FullThrottle * 100, "%d%%", "FLAT OUT", accent, 6, cnt)
	tile(grid, "⛰️", info.ElevationM, if info.ElevationM < 1 then "Flat" else "%d m", "ELEVATION", accent, 7, cnt)
	tile(grid, "🏁", info.LengthKm * laps, "%.1f km", "RACE DISTANCE", accent, 8, cnt)
	-- your start / your record
	local you = Kit.new("Frame", { BackgroundColor3 = rgb(12, 14, 26), BackgroundTransparency = 0.2, Position = UDim2.fromOffset(0, 376), Size = UDim2.new(1, -8, 0, 52), ZIndex = 5, Parent = left })
	Kit.Corner(you, 12)
	Kit.Stroke(you, C.Accent, 1.2, 0.5)
	local best = State.Profile and State.Profile.bests and State.Profile.bests[trackId]
	local medal = State.Profile and State.Profile.medals and State.Profile.medals[trackId] or 0
	local th2 = Medals.FromIdeal(t.IdealLap)
	local youText
	if opts.Mode == "tt" then
		youText = if best then string.format("⏱️  YOUR BEST  %s  %s     🎯 GOLD  %s", Medals.FormatTime(best), Util.MedalIcon(medal), Medals.FormatTime(th2[3])) else string.format("⏱️  NO LAP YET     🎯 GOLD MEDAL  %s     💠 AUTHOR  %s", Medals.FormatTime(th2[3]), Medals.FormatTime(th2[4]))
	else
		youText = string.format("🚦  YOU START  P%s / %s", tostring(opts.Slot or "?"), tostring(opts.Racers or 10)) .. (if best then "     ⏱️  YOUR BEST LAP  " .. Medals.FormatTime(best) else "")
	end
	text(you, youText, 17, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -24, 1, 0), ZIndex = 6 })
	-- a racing tip for this circuit, from its numbers
	local tip = Kit.new("Frame", { BackgroundColor3 = dark(accent, 0.6), BackgroundTransparency = 0.25, Position = UDim2.fromOffset(0, 438), Size = UDim2.new(1, -8, 0, 52), ZIndex = 5, Parent = left })
	Kit.Corner(tip, 12)
	text(tip, "💡", 22, { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(30, 52), ZIndex = 6 })
	text(tip, Intro.Tip(trackId), 15, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -60, 1, 0), TextWrapped = true, ZIndex = 6 })

	-- RIGHT: the map, sectors legend and landmarks ---------------------------------------
	local right = Kit.new("Frame", { Name = "Right", BackgroundColor3 = rgb(10, 12, 22), BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 86), Size = UDim2.fromOffset(470, 440), ZIndex = 5, Parent = root })
	Kit.Corner(right, 18)
	Kit.Stroke(right, accent, 1.5, 0.55)
	run.Right = right
	local mapHolder = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(15, 12), Size = UDim2.fromOffset(300, 300), ZIndex = 5, Parent = right })
	local map, segs, flag, dot = buildMap(mapHolder, t, 300, 5)
	run.Map, run.Segs, run.Flag, run.Dot = map, segs, flag, dot
	local legend = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(326, 20), Size = UDim2.fromOffset(130, 100), ZIndex = 5, Parent = right })
	Kit.List(legend, Enum.FillDirection.Vertical, 6)
	for i = 1, 3 do
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(130, 22), LayoutOrder = i, Parent = legend })
		local sw = Kit.new("Frame", { BackgroundColor3 = SECTOR[i], Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(22, 6), ZIndex = 6, Parent = row })
		Kit.Corner(sw, 3)
		text(row, "SECTOR " .. i, 13, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(30, 0), Size = UDim2.fromOffset(100, 22), ZIndex = 6 })
	end
	local startRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(130, 22), LayoutOrder = 4, Parent = legend })
	text(startRow, "🏁  START / FINISH", 12, { Font = Kit.Fonts.Bold, Size = UDim2.fromOffset(130, 22), TextColor3 = C.SubText, ZIndex = 6 })
	-- landmarks to look out for (from the theme; confirmed after the build)
	text(right, "LOOK OUT FOR", 13, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(20, 318), Size = UDim2.fromOffset(300, 18), TextColor3 = accent:Lerp(C.White, 0.3), ZIndex = 6 })
	local sightsBox = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 340), Size = UDim2.new(1, -40, 0, 90), ZIndex = 6, Parent = right })
	local sgl = Kit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 26), CellPadding = UDim2.fromOffset(8, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sightsBox })
	local _sgl = sgl
	local shown = 0
	for _, lm in th.Landmarks do
		local label = Landmarks.Names[lm]
		if label and shown < 6 then
			shown += 1
			local row = Kit.new("Frame", { BackgroundColor3 = dark(accent, 0.7), BackgroundTransparency = 0.3, LayoutOrder = shown, Parent = sightsBox })
			Kit.Corner(row, 8)
			text(row, "📍 " .. label, 13, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -12, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 })
		end
	end

	-- BOTTOM: build progress (in the letterbox) ---------------------------------------------
	local stage = text(botBar, "Loading...", 15, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(56, 8), Size = UDim2.new(0.6, 0, 0, 20), TextColor3 = C.SubText, ZIndex = 21 })
	local pct = text(botBar, "0%", 15, { Font = Kit.Fonts.Title, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 8), Size = UDim2.fromOffset(80, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 21 })
	local barBg = Kit.new("Frame", { BackgroundColor3 = rgb(40, 44, 64), Position = UDim2.fromOffset(56, 36), Size = UDim2.new(1, -112, 0, 8), ZIndex = 21, Parent = botBar })
	Kit.Round(barBg)
	local barFill = Kit.new("Frame", { BackgroundColor3 = accent, Size = UDim2.fromScale(0.02, 1), ZIndex = 22, Parent = barBg })
	Kit.Round(barFill)
	Kit.Gradient(barFill, accent:Lerp(C.White, 0.3), accent, 0)
	run.Stage, run.Pct, run.BarBg, run.BarFill = stage, pct, barBg, barFill

	-- entrance animation: panels slide in, map draws itself, numbers count up
	local lp, rp = left.Position, right.Position
	left.Position = lp - UDim2.fromOffset(60, 0)
	right.Position = rp + UDim2.fromOffset(60, 0)
	Kit.Tween(left, 0.5, { Position = lp }, Enum.EasingStyle.Quart)
	Kit.Tween(right, 0.5, { Position = rp }, Enum.EasingStyle.Quart)

	local lapS = 0
	table.insert(run.Conns, RunService.RenderStepped:Connect(function(dt)
		local el = os.clock() - run.Start
		-- stripes drift, LIVE dot blinks
		for _, sfr in run.Stripes:GetChildren() do
			local base = sfr:GetAttribute("Base") or 0
			sfr.Position = UDim2.new(((base + el * 0.04) % 1.3) - 0.15, 0, 0.5, 0)
		end
		run.LiveDot.BackgroundTransparency = if math.floor(el * 2) % 2 == 0 then 0 else 0.7
		-- the map draws itself over 1.4 s, then a car dot laps it
		local frac = math.clamp(el / 1.4, 0, 1)
		local want = math.floor(frac * #run.Segs)
		for i = 1, want do
			local sg = run.Segs[i]
			if not sg[2].Visible then
				sg[1].Visible = true
				sg[2].Visible = true
			end
		end
		if frac >= 1 then
			run.Flag.Visible = true
			run.Dot.Visible = true
			lapS = (lapS + dt * run.Track.Length / 6) % run.Track.Length
			local p = lapPoint(run.Track, run.Map, lapS)
			run.Dot.Position = UDim2.fromOffset(p.X, p.Y)
		end
		-- counters
		local cf = math.clamp((el - 0.3) / 1.2, 0, 1)
		cf = 1 - (1 - cf) ^ 3
		for _, ct in run.Counters do
			ct.Label.Text = string.format(ct.Fmt, ct.Target * cf)
		end
	end))
end

-- Build progress from CircuitBuilder (stage name, 0..1)
function Intro.Progress(stageName: string, frac: number)
	local run = active
	if not run or not run.BarFill then
		return
	end
	run.Stage.Text = stageName .. "..."
	run.Pct.Text = string.format("%d%%", math.floor(frac * 100))
	Kit.Tween(run.BarFill, 0.25, { Size = UDim2.fromScale(math.max(0.02, frac), 1) })
end

---------------------------------------------------------------------------
-- Reveal: the flyover
---------------------------------------------------------------------------
local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- camera shots: each is { Duration, Caption, Fn(u) -> CFrame }
local function makeShots(run, world, car, total: number)
	local t = run.Track
	local b = t.Bounds
	local cx, cz = (b[1] + b[2]) / 2, (b[3] + b[4]) / 2
	local span = math.max(b[2] - b[1], b[4] - b[3])
	local shots = {}
	-- 1. establishing aerial orbit around the whole circuit, looking towards its busiest
	-- side (the camera sits opposite it) so the shot never opens on empty land
	local a0 = math.random() * math.pi * 2
	if world and world.ViewAngle then
		a0 = world.ViewAngle + math.pi - 0.275 + (math.random() - 0.5) * 0.5
	end
	local R = span * 0.62 + 120
	local H = span * 0.34 + 90
	table.insert(shots, {
		Caption = string.upper(run.Circuit.Name),
		Sub = run.Circuit.Region .. "  •  " .. run.Theme.Name,
		Fn = function(u)
			local a = a0 + u * 0.55
			local pos = Vector3.new(cx + math.cos(a) * R, H - u * H * 0.18, cz + math.sin(a) * R)
			return CFrame.lookAt(pos, Vector3.new(cx, 0, cz)), 55
		end,
	})
	-- 2. fly past a landmark (the biggest one that isn't out on the horizon)
	local pickSpot = nil
	for _, sp in (world and world.SightSpots) or {} do
		if sp.Place ~= "far" and (not pickSpot or sp.R > pickSpot.R) then
			pickSpot = sp
		end
	end
	if pickSpot then
		local r = math.max(pickSpot.R, 30)
		local look = pickSpot.Pos + Vector3.new(0, math.min(r * 0.45, 60), 0)
		local dir = Vector3.new(cx - pickSpot.Pos.X, 0, cz - pickSpot.Pos.Z)
		dir = if dir.Magnitude > 1 then dir.Unit else Vector3.new(0, 0, 1)
		local side = dir:Cross(Vector3.yAxis)
		table.insert(shots, {
			Caption = "📍 " .. string.upper(pickSpot.Name),
			Sub = "Circuit landmark",
			Fn = function(u)
				local pos = pickSpot.Pos + dir * (r * 2.1 + 40) + side * ((u - 0.5) * r * 2.4) + Vector3.new(0, r * 0.5 + 24 - u * 8, 0)
				return CFrame.lookAt(pos, look), 60
			end,
		})
	end
	-- 3. down onto your car on the grid
	local carCF = if car and car.Chassis then car.Chassis.CFrame else CFrame.new(t.X[1], t.Y[1] + 3, t.Z[1])
	local endPos = (carCF * CFrame.new(0, 5.5, 15)).Position
	local endLook = (carCF * CFrame.new(0, 2, -12)).Position
	local startPos = (carCF * CFrame.new(40, 70, -120)).Position
	local startLook = (carCF * CFrame.new(0, 0, -40)).Position
	table.insert(shots, {
		Caption = if run.Opts.Mode == "tt" then "⏱️  TIME TRIAL" else string.format("🚦  YOU START P%s", tostring(run.Opts.Slot or "?")),
		Sub = if run.Opts.Mode == "tt" then "Beat your best lap" else string.format("%d laps  •  %d racers  •  %s", run.Opts.Laps or 2, run.Opts.Racers or 10, MODE_NAMES[run.Opts.Mode or "quick"] or "RACE"),
		Fn = function(u)
			local e = ease(u)
			local mid = startPos:Lerp(endPos, e) + Vector3.new(0, math.sin(e * math.pi) * 10, 0)
			local fov = State.Setting("Fov") or 78
			return CFrame.lookAt(mid, startLook:Lerp(endLook, e)), 64 + (fov - 64) * e
		end,
	})
	-- durations: fit the time available
	if total < 3.2 then
		shots = { shots[#shots] }
		shots[1].Duration = math.max(1.2, total)
	elseif total < 6 or #shots == 2 then
		shots = { shots[1], shots[#shots] }
		shots[1].Duration = total * 0.5
		shots[2].Duration = total * 0.5
	else
		shots[1].Duration = total * 0.36
		shots[2].Duration = total * 0.28
		shots[3].Duration = total * 0.36
	end
	return shots
end

-- world: CircuitBuilder result. opts: { EndsAt = server time (race), Duration = seconds
-- (time trial), Car = car controller, OnDone = fn }
function Intro.Reveal(world, opts)
	local run = active
	if not run then
		if opts.OnDone then
			task.spawn(opts.OnDone)
		end
		return
	end
	run.Revealed = true
	local now = workspace:GetServerTimeNow()
	local total = if opts.EndsAt then opts.EndsAt - now else (opts.Duration or 5)
	run.Stage.Text = "Ready!"
	run.Pct.Text = "100%"
	Kit.Tween(run.BarFill, 0.2, { Size = UDim2.fromScale(1, 1) })

	local function finish()
		if run.Done then
			return
		end
		run.Done = true
		if active == run then
			Intro.Stop()
		end
		if opts.OnDone then
			task.spawn(opts.OnDone)
		end
	end
	-- not enough time for a flyover: straight to the grid
	if total < 1.4 then
		finish()
		return
	end

	-- the world fades in; the info panels make way for broadcast graphics
	Kit.Tween(run.Bg, 0.7, { BackgroundTransparency = 1 })
	for _, d in run.Bg:GetDescendants() do
		if d:IsA("Frame") then
			Kit.Tween(d, 0.6, { BackgroundTransparency = 1 })
		elseif d:IsA("TextLabel") then
			Kit.Tween(d, 0.6, { TextTransparency = 1 })
		end
	end
	Kit.Tween(run.Left, 0.45, { Position = run.Left.Position - UDim2.fromOffset(700, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
	-- the map card shrinks into the top-right corner
	local sc = Kit.new("UIScale", { Scale = 1, Parent = run.Right })
	Kit.Tween(sc, 0.6, { Scale = 0.52 }, Enum.EasingStyle.Quart)
	Kit.Tween(run.Right, 0.6, { Position = UDim2.new(1, -24, 0, 76), AnchorPoint = Vector2.new(1, 0) }, Enum.EasingStyle.Quart)
	run.BarBg.Visible = false
	run.Pct.Visible = false

	-- lower third: caption for the current shot
	local lower = Kit.new("Frame", { BackgroundColor3 = rgb(10, 12, 22), BackgroundTransparency = 0.15, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -560, 1, -92), Size = UDim2.fromOffset(520, 76), ZIndex = 15, Parent = root })
	Kit.Corner(lower, 12)
	local lbar = Kit.new("Frame", { BackgroundColor3 = run.Theme.Accent, BorderSizePixel = 0, Size = UDim2.new(0, 8, 1, 0), ZIndex = 16, Parent = lower })
	Kit.Corner(lbar, 4)
	local capTitle = Kit.new("TextLabel", { BackgroundTransparency = 1, Text = "", FontFace = Kit.Faces.Sub, TextSize = 28, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(22, 8), Size = UDim2.new(1, -30, 0, 34), ZIndex = 16, Parent = lower })
	local capSub = text(lower, "", 15, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(22, 44), Size = UDim2.new(1, -30, 0, 20), TextColor3 = C.SubText, ZIndex = 16 })
	Kit.Tween(lower, 0.5, { Position = UDim2.new(0, 40, 1, -92) }, Enum.EasingStyle.Quart)
	-- countdown + skip hint in the bottom bar
	local isTouch = Kit.Touch()
	run.Stage.Text = if isTouch then "Tap to skip" else "Press SPACE to skip"
	local count = text(run.BotBar, "", 22, { Font = Kit.Fonts.Title, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(500, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21 })
	-- a quick dip to black between shots
	local flash = Kit.new("Frame", { BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 12, Parent = root })

	local shots = makeShots(run, world, opts.Car, total)
	local idx, shotT = 1, 0
	local function setCaption(i)
		capTitle.Text = shots[i].Caption
		capSub.Text = shots[i].Sub or ""
	end
	setCaption(1)
	Cam.Scripted(function(dt)
		if run.Done then
			return nil
		end
		shotT += dt
		local sh = shots[idx]
		if shotT >= sh.Duration then
			if idx >= #shots then
				task.defer(finish)
				return sh.Fn(1)
			end
			idx += 1
			shotT = 0
			sh = shots[idx]
			setCaption(idx)
			flash.BackgroundTransparency = 0
			Kit.Tween(flash, 0.35, { BackgroundTransparency = 1 })
		end
		return sh.Fn(shotT / sh.Duration)
	end)

	local endAt = if opts.EndsAt then opts.EndsAt else workspace:GetServerTimeNow() + total
	table.insert(run.Conns, RunService.Heartbeat:Connect(function()
		local left = math.max(0, endAt - workspace:GetServerTimeNow())
		count.Text = if opts.EndsAt then string.format("LIGHTS IN  %d", math.ceil(left + 0.5)) else string.format("READY IN  %d", math.ceil(left))
	end))
	-- skip
	table.insert(run.Conns, UserInputService.InputBegan:Connect(function(io, processed)
		if processed then
			return
		end
		local k = io.KeyCode
		if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA or io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			finish()
		end
	end))
end

function Intro.IsActive(): boolean
	return active ~= nil
end

-- Removes the intro immediately (race left / finished loading without a flyover)
function Intro.Stop()
	local run = active
	active = nil
	if run then
		run.Done = true
		for _, c in run.Conns do
			c:Disconnect()
		end
	end
	Util.Clear(root, true)
	gui.Enabled = false
end

local _ = Players
return Intro
