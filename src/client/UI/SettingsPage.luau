--!nonstrict
-- Settings: a centred panel with Camera / Gameplay / Graphics & Audio sections, a
-- controls reference and Help (replay the welcome tour, weekly challenges). Every change
-- saves automatically; camera changes preview live.

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local Fx = require(script.Parent.Parent.Fx)
local Cam = require(script.Parent.Parent.CameraController)
local Onboarding = require(script.Parent.Onboarding)
local ChallengesPanel = require(script.Parent.ChallengesPanel)

local C = Kit.Colors
local Settings = {}
Settings.Camera = "home"

local setters = {}

-- One settings row: title and description on the left, the control on the right.
local function row(parent, order: number, title: string, desc: string?, height: number?): Frame
	local h = height or (if desc then 62 else 52)
	local r = Kit.Card(parent, { Size = UDim2.new(1, 0, 0, h), LayoutOrder = order })
	Kit.Label(r, title, 16, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(16, if desc then 10 else 0),
		Size = UDim2.new(0.45, -16, 0, if desc then 22 else h),
	})
	if desc then
		Kit.Label(r, desc, 12, {
			Position = UDim2.fromOffset(16, 32),
			Size = UDim2.new(0.45, -16, 0, 20),
			TextColor3 = C.SubText,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	return r
end

-- The right-hand slot of a row where the toggle or selector goes.
local function control(r: Frame, width: number, height: number?): Frame
	return Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(width, height or 38),
		Parent = r,
	})
end

-- An on/off setting.
local function toggleRow(list, order, title, desc, key)
	local r = row(list, order, title, desc)
	local holder = control(r, 54, 30)
	local _, set = Kit.Toggle(holder, State.Setting(key) == true, function(v)
		State.SetSetting(key, v)
	end)
	setters[key] = function()
		set(State.Setting(key) == true)
	end
end

-- A setting with a few choices (camera, units, graphics...).
local function segRow(list, order, title, desc, key, options, width)
	local r = row(list, order, title, desc)
	local holder = control(r, width or 300)
	local _, set = Kit.Segmented(holder, options, State.Setting(key), function(v)
		State.SetSetting(key, v)
		if Settings.OnSegment then
			Settings.OnSegment(key, v)
		end
	end, { Size = UDim2.fromScale(1, 1) })
	setters[key] = function()
		set(State.Setting(key))
	end
end

-- Builds the Settings page.
function Settings.Build(parent, menu)
	local f, body = menu.PageFrame(parent, "Settings", "Changes save automatically")
	Settings.Frame = f
	local panel = Kit.Panel(
		body,
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 780, 1, 0) }
	)
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(780, 640), Parent = panel })
	Kit.Padding(panel, 18, 16)
	local list = Kit.ScrollList(panel, nil, 8)

	-- CAMERA ------------------------------------------------------------------------------
	Kit.Section(list, "Camera", 1, C.Accent2)
	local camOptions = {}
	for _, m in State.CameraModes do
		table.insert(camOptions, { m[1], m[2] })
	end
	segRow(list, 2, "Race camera", "Press C (or Select) in a race to cycle", "Camera", camOptions, 430)
	do
		local r = row(list, 3, "Field of view", "Drag to preview it live")
		local holder = control(r, 300, 30)
		local _, set = Kit.Slider(holder, 60, 110, 1, State.Setting("Fov"), function(v)
			Cam.PreviewFov(v)
		end, function(v)
			State.SetSetting("Fov", v)
			task.delay(1.2, function()
				if Settings.Frame.Visible then
					Cam.PreviewFov(nil)
				end
			end)
		end, { Size = UDim2.fromScale(1, 1) })
		setters.Fov = function()
			set(State.Setting("Fov"))
		end
	end
	toggleRow(list, 4, "Speed zoom", "Field of view widens at high speed", "SpeedFov")
	toggleRow(list, 5, "Camera shake", "Shake on big landings and crashes", "Shake")

	-- GAMEPLAY ----------------------------------------------------------------------------
	Kit.Section(list, "Gameplay", 10, C.Accent)
	segRow(
		list,
		11,
		"Racing line",
		"Green = flat out, yellow = lift, red = brake",
		"RacingLine",
		{ { "off", "Off" }, { "braking", "Braking zones" }, { "full", "Full line" } },
		330
	)
	segRow(list, 12, "Speed units", nil, "Units", { { "kmh", "KM/H" }, { "mph", "MPH" } }, 200)
	toggleRow(list, 13, "Name tags", "Show names above other cars", "NameTags")
	toggleRow(list, 14, "Time Trial ghosts", "Race against leaderboard ghosts", "ShowGhosts")
	toggleRow(list, 15, "Race my PB ghost", "Show your best lap as a ghost", "ShowPBGhost")

	-- GRAPHICS & AUDIO --------------------------------------------------------------------
	Kit.Section(list, "Graphics & audio", 20, C.Purple)
	segRow(
		list,
		21,
		"Graphics quality",
		"Lower it if your device struggles",
		"Quality",
		{ { 1, "Low" }, { 2, "Medium" }, { 3, "High" }, { 4, "Ultra" } },
		330
	)
	toggleRow(list, 22, "Show FPS & ping", "Small performance counter", "ShowFPS")
	do
		local r = row(list, 23, "Master volume", "Every sound in the game")
		local holder = control(r, 300, 30)
		local _, set = Kit.Slider(holder, 0, 100, 5, State.Setting("Sfx"), function(v)
			Fx.SetVolume(v / 100)
		end, function(v)
			State.SetSetting("Sfx", v)
			Fx.Play("Click", 0.6)
		end, { Size = UDim2.fromScale(1, 1) })
		setters.Sfx = function()
			set(State.Setting("Sfx"))
		end
	end
	do
		local r = row(list, 24, "Engine sound", "Your car and the cars around you")
		local holder = control(r, 300, 30)
		local _, set = Kit.Slider(holder, 0, 100, 5, State.Setting("Engine"), function(v)
			Fx.SetEngineVolume(v / 100)
		end, function(v)
			State.SetSetting("Engine", v)
		end, { Size = UDim2.fromScale(1, 1) })
		setters.Engine = function()
			set(State.Setting("Engine"))
		end
	end

	-- CONTROLS ----------------------------------------------------------------------------
	Kit.Section(list, "Controls", 30, C.Success)
	local controls = {
		{ "Drive / brake / steer", "W A S D  or  arrows", "RT / LT / left stick" },
		{ "Drift (handbrake)", "Space", "B  or  RB" },
		{ "Reset & repair car", "R", "Y" },
		{ "Switch camera", "C", "Select" },
		{ "Pause", "P  or  Tab", "Start" },
	}
	local r = Kit.Card(list, { Size = UDim2.new(1, 0, 0, 28 + #controls * 26), LayoutOrder = 31 })
	Kit.Padding(r, 16, 10)
	Kit.Label(r, "ACTION", 11, { Font = Kit.Fonts.Title, Size = UDim2.new(0.4, 0, 0, 16), TextColor3 = C.SubText })
	Kit.Label(r, "KEYBOARD", 11, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromScale(0.4, 0),
		Size = UDim2.new(0.3, 0, 0, 16),
		TextColor3 = C.SubText,
	})
	Kit.Label(r, "GAMEPAD", 11, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromScale(0.7, 0),
		Size = UDim2.new(0.3, 0, 0, 16),
		TextColor3 = C.SubText,
	})
	for i, c in controls do
		local y = 4 + i * 26
		Kit.Label(
			r,
			c[1],
			14,
			{ Font = Kit.Fonts.Bold, Position = UDim2.new(0, 0, 0, y), Size = UDim2.new(0.4, 0, 0, 22) }
		)
		Kit.Label(
			r,
			c[2],
			13,
			{ Position = UDim2.new(0.4, 0, 0, y), Size = UDim2.new(0.3, 0, 0, 22), TextColor3 = C.Accent }
		)
		Kit.Label(
			r,
			c[3],
			13,
			{ Position = UDim2.new(0.7, 0, 0, y), Size = UDim2.new(0.3, 0, 0, 22), TextColor3 = C.Accent2 }
		)
	end
	Kit.Label(
		list,
		"On phones and tablets: steer with ◀ ▶ bottom-left, GAS / BRAKE / DRIFT bottom-right. Pause ⏸, camera 🎥 and repair 🔧 sit at the top right.",
		12,
		{ LayoutOrder = 40, TextColor3 = C.SubText, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y }
	)

	-- help
	Kit.Section(list, "Help", 50, C.Gold)
	local tour = row(list, 51, "Welcome tour", "How to drive, the racing line, coins and the Garage")
	Kit.Button(control(tour, 170), "🎓  Replay tour", "secondary", function()
		Onboarding.Show()
	end, { Size = UDim2.fromScale(1, 1), TextSize = 14 })
	local ch = row(list, 52, "Weekly challenges", "New challenges and a featured circuit every Monday")
	Kit.Button(control(ch, 170), "🎯  Open", "secondary", function()
		ChallengesPanel.Open()
	end, { Size = UDim2.fromScale(1, 1), TextSize = 14 })
end

-- Page opened: sync every control with the current settings.
function Settings.OnShow()
	for _, fn in setters do
		fn()
	end
end

-- Page closed: end the camera preview.
function Settings.OnHide()
	Cam.PreviewFov(nil)
end

return Settings
