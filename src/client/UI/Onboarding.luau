--!nonstrict
-- First-time player experience.
--  * Welcome tour (once per account): what the game is, how to drive on this device
--    (keyboard / touch / gamepad), how to read the racing line, and how coins and the
--    Garage work - then "Start my first race" on the easiest circuit.
--  * First-race coaching: a few timed tips during the player's first race.
-- The server remembers both with profile flags (SetFlag "onboarded" / "coached").

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Circuits = require(Shared.Circuits)
local CircuitInfo = require(Shared.CircuitInfo)

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local Util = require(script.Parent.Parent.Util)
local Fx = require(script.Parent.Parent.Fx)

local Onboarding = {}
local C = Kit.Colors

local function device(): string
	if Kit.Touch() then
		return "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "gamepad"
	end
	return "keyboard"
end

local function controls(): { { string } }
	local d = device()
	if d == "touch" then
		return {
			{ "⛽", "GAS and BRAKE are on the right" },
			{ "◀▶", "Steer with the arrows on the left - slide your thumb between them" },
			{ "💨", "DRIFT helps you round hairpins" },
			{ "🔧", "Stuck or damaged? Tap the spanner to reset and repair" },
			{ "🎥", "Tap the camera to switch views (cockpit, chase, TV...)" },
		}
	elseif d == "gamepad" then
		return {
			{ "RT", "Accelerate (or A)" },
			{ "LT", "Brake and reverse (or X)" },
			{ "L", "Left stick to steer" },
			{ "B", "Drift (or RB)" },
			{ "Y", "Reset and repair  •  View button: camera  •  Menu: pause" },
		}
	end
	return {
		{ "W", "Accelerate (or ↑)" },
		{ "S", "Brake and reverse (or ↓)" },
		{ "A D", "Steer (or ← →)" },
		{ "␣", "Space to drift round hairpins" },
		{ "R", "Reset and repair  •  C: camera  •  P: pause" },
	}
end

local SLIDES = {
	{
		Icon = "🏁",
		Color = C.Accent,
		Title = "Welcome to GoTrack Racing!",
		Body = "Race 10-car Formula grids on 31 circuits around the world. Every car handles exactly the same - only skill wins.",
		Points = function()
			return {
				{ "🌍", "31 circuits, each with its own landmarks and weather" },
				{ "🏆", "Ranked seasons with a reward for every tier" },
				{ "⏱️", "Time Trials with ghosts, medals and world records" },
			}
		end,
	},
	{
		Icon = "🎮",
		Color = C.Accent2,
		Title = "How to drive",
		Body = "Brake BEFORE the corner, turn in, then back on the power.",
		Points = controls,
	},
	{
		Icon = "🟢",
		Color = C.Success,
		Title = "Follow the racing line",
		Body = "The chevrons on the road show the fastest way round, and they react to your speed.",
		Points = function()
			return {
				{ "🟢", "Green: flat out" },
				{ "🟡", "Yellow: lift off the gas" },
				{ "🔴", "Red: brake now!" },
				{ "🪧", "Boards count down 150 - 100 - 50 to each big corner" },
			}
		end,
	},
	{
		Icon = "🪙",
		Color = C.Gold,
		Title = "Earn coins, make it yours",
		Body = "Every race pays coins and XP, and the podium pays the most.",
		Points = function()
			return {
				{ "🎁", "Daily reward - day 7 is the big one" },
				{ "🎯", "Weekly challenges and a getting-started checklist" },
				{ "🎨", "Paints, rims, helmets, liveries and 13 chassis in the Garage" },
			}
		end,
	},
}

-- the friendliest circuit for a first race (fewest difficulty stars, then shortest)
local function easiestCircuit(): string
	local best, bestKey = Circuits.List[1].Id, math.huge
	for _, c in Circuits.List do
		local s = CircuitInfo.Get(c.Id)
		if s and not string.find(c.Region, "Bonus") then
			local key = s.Difficulty * 100 + s.LengthKm
			if key < bestKey then
				best, bestKey = c.Id, key
			end
		end
	end
	return best
end

local open = false

-- onDone(startedRace) runs when the tour closes
function Onboarding.Show(onDone: ((boolean) -> ())?)
	if open then
		return
	end
	open = true
	local box, _, close = Kit.ModalFrame("👋 Let's get you racing", 660)
	local page = 1
	local content = Kit.new("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.new(1, 0, 0, 316), LayoutOrder = 1, ZIndex = 12, Parent = box })
	local dots = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 2, ZIndex = 12, Parent = box })
	Kit.List(dots, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local dotFrames = {}
	for i = 1, #SLIDES do
		local d = Kit.new("Frame", { BackgroundColor3 = C.Panel3, Size = UDim2.fromOffset(10, 10), LayoutOrder = i, ZIndex = 13, Parent = dots })
		Kit.Round(d)
		dotFrames[i] = d
	end
	local btns = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 3, ZIndex = 12, Parent = box })
	Kit.List(btns, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)

	local function finish(race: boolean)
		if not open then
			return
		end
		open = false
		close()
		task.spawn(Util.Invoke, "SetFlag", "onboarded")
		if onDone then
			task.spawn(onDone, race)
		end
		if race then
			task.spawn(function()
				local id = easiestCircuit()
				local res = Util.Invoke("QuickRace", id, false)
				if res and res.ok then
					Kit.Toast("🏁 Joining your first race on " .. Circuits.ById[id].Name .. " - good luck!", "success")
				else
					Kit.Toast((res and res.err) or "Couldn't join - try Quick Race", "error")
				end
			end)
		end
	end

	local render
	local function go(delta: number)
		page = math.clamp(page + delta, 1, #SLIDES)
		Fx.Play("Click", 0.3, 1.1)
		render(delta)
	end

	render = function(dir: number)
		Util.Clear(content)
		local sl = SLIDES[page]
		local holder = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(dir * 60, 0), Size = UDim2.fromScale(1, 1), ZIndex = 12, Parent = content })
		Kit.Tween(holder, 0.3, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quart)
		Kit.IconTile(holder, sl.Icon, 76, sl.Color, { Position = UDim2.fromOffset(0, 0), ZIndex = 13 })
		Kit.Label(holder, sl.Title, 24, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(92, 2), Size = UDim2.new(1, -92, 0, 30), ZIndex = 13 })
		Kit.Label(holder, sl.Body, 15, { Position = UDim2.fromOffset(92, 36), Size = UDim2.new(1, -92, 0, 60), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.SubText, ZIndex = 13 })
		local list = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 1, -102), ZIndex = 12, Parent = holder })
		Kit.List(list, Enum.FillDirection.Vertical, 6)
		for i, pt in sl.Points() do
			local r = Kit.Card(list, { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, ZIndex = 12 }, C.Panel2)
			local key = Kit.new("Frame", { BackgroundColor3 = sl.Color:Lerp(C.Panel3, 0.55), Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(52, 26), ZIndex = 13, Parent = r })
			Kit.Corner(key, 7)
			Kit.Label(key, pt[1], 14, { Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 })
			local l = Kit.Label(r, pt[2], 14, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(68, 0), Size = UDim2.new(1, -76, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13 })
			l.TextTransparency = 1
			task.delay(0.05 * i, function()
				if l.Parent then
					Kit.Tween(l, 0.25, { TextTransparency = 0 })
				end
			end)
		end
		for i, d in dotFrames do
			Kit.Tween(d, 0.2, { BackgroundColor3 = if i == page then sl.Color else C.Panel3, Size = if i == page then UDim2.fromOffset(26, 10) else UDim2.fromOffset(10, 10) })
		end
		Util.Clear(btns, true)
		if page == 1 then
			Kit.Button(btns, "Skip tour", "secondary", function()
				finish(false)
			end, { LayoutOrder = 1, Size = UDim2.fromOffset(140, 46), ZIndex = 13 })
		else
			Kit.Button(btns, "‹ Back", "secondary", function()
				go(-1)
			end, { LayoutOrder = 1, Size = UDim2.fromOffset(120, 46), ZIndex = 13 })
		end
		if page < #SLIDES then
			Kit.Button(btns, "Next ›", "primary", function()
				go(1)
			end, { LayoutOrder = 2, Size = UDim2.fromOffset(150, 46), ZIndex = 13 })
		else
			Kit.Button(btns, "Explore first", "secondary", function()
				finish(false)
			end, { LayoutOrder = 2, Size = UDim2.fromOffset(150, 46), ZIndex = 13 })
			Kit.Button(btns, "🏁  START MY FIRST RACE", "success", function()
				finish(true)
			end, { LayoutOrder = 3, Size = UDim2.fromOffset(250, 46), ZIndex = 13 })
		end
	end
	render(0)
end

-- Should this account see the welcome tour? (never seen it and hasn't raced yet)
function Onboarding.Needed(): boolean
	local p = State.Profile
	if not p or (p.flags and p.flags.onboarded) then
		return false
	end
	if p.stats and (p.stats.races or 0) > 0 then
		-- a player from before the tour existed: don't show it, just remember
		task.spawn(Util.Invoke, "SetFlag", "onboarded")
		return false
	end
	return true
end

-- First-race coaching tips (message function = Hud.Message). Only the very first race.
function Onboarding.CoachFirstRace(message: (string, Color3?, number?) -> (), isActive: () -> boolean)
	local p = State.Profile
	if not p or (p.flags and p.flags.coached) or (p.stats and (p.stats.races or 0) > 0) then
		return
	end
	local touch = Kit.Touch()
	local tips = {
		{ 2.5, if touch then "Hold GAS to go - steer with ◀ ▶" else "Hold W to go - steer with A / D" },
		{ 9, "Brake when the racing line turns RED" },
		{ 17, "Watch the 150 - 100 - 50 boards before big corners" },
		{ 26, if touch then "Stuck or damaged? Tap 🔧 to reset" else "Stuck or damaged? Press R to reset" },
		{ 36, if touch then "Tap 🎥 to try another camera" else "Press C to try another camera" },
		{ 46, "Flat out on a straight? Your rear wing opens: ⚡ STRAIGHT MODE" },
	}
	task.spawn(function()
		local t0 = os.clock()
		for _, tip in tips do
			local wait = tip[1] - (os.clock() - t0)
			if wait > 0 then
				task.wait(wait)
			end
			if not isActive() then
				return
			end
			message("💡 " .. tip[2], C.Accent2, 3.2)
		end
		task.spawn(Util.Invoke, "SetFlag", "coached")
	end)
end

return Onboarding
