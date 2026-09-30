--!nonstrict
-- Menu pages: Quick Race (circuit selector + open races), Ranked hub (rank emblem,
-- divisions, season rewards, match history, map-vote matchmaking), Time Trial
-- (circuit selector + medals + lap records + ghosts) and Leaderboards (podium + list).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Circuits = require(Shared.Circuits)
local Track = require(Shared.Track)
local Themes = require(Shared.Themes)
local CircuitInfo = require(Shared.CircuitInfo)
local Medals = require(Shared.Medals)
local Cosmetics = require(Shared.Cosmetics)

local Kit = require(script.Parent.Kit)
local Hud = require(script.Parent.Hud)
local State = require(script.Parent.Parent.State)
local Util = require(script.Parent.Parent.Util)

local C = Kit.Colors
local player = Players.LocalPlayer
local Pages = {}

-- A circuit's theme (colours, flag, sky).
local function themeOf(c)
	return Themes[c.Theme] or Themes.park
end

-- Every `every`-th minimap point, enough for a small map.
local function smallMini(t, every)
	local mini = {}
	for i = 1, #t.Minimap, every do
		table.insert(mini, t.Minimap[i])
	end
	return mini
end

-- Rough race length for a circuit card, e.g. "~4:30".
local function raceTimeText(t)
	local secs = math.floor(t.IdealLap * t.Laps * 1.12)
	return string.format("~%d:%02d", secs // 60, secs % 60)
end

---------------------------------------------------------------------------
-- Circuit grid (shared by Quick Race and Time Trial)
---------------------------------------------------------------------------
local function circuitGrid(parent, onPick, includeRandom)
	local scroll = Kit.ScrollGrid(parent, UDim2.new(0.25, -10, 0, 156), 10)
	local cards = {}
	local function setSelected(id)
		for cid, card in cards do
			local on = cid == id
			local stroke = card:FindFirstChild("Sel")
			if stroke then
				stroke.Transparency = if on then 0 else 0.85
				stroke.Thickness = if on then 3 else 1.2
				stroke.Color = if on then C.Accent else C.White
			end
			local tick = card:FindFirstChild("Tick")
			if tick then
				tick.Visible = on
			end
		end
	end
	local function card(order: number, id: string)
		local b = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.Panel2,
			LayoutOrder = order,
			ClipsDescendants = true,
			Parent = scroll,
		})
		Kit.Corner(b, 14)
		local st = Kit.Stroke(b, C.White, 1.2, 0.85)
		st.Name = "Sel"
		local tick = Kit.new("Frame", {
			Name = "Tick",
			BackgroundColor3 = C.Accent,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(22, 22),
			Visible = false,
			ZIndex = 3,
			Parent = b,
		})
		Kit.Round(tick)
		Kit.Label(tick, "✓", 14, {
			Font = Kit.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(30, 20, 4),
			ZIndex = 4,
		})
		Kit.Clickable(b, function()
			setSelected(id)
			onPick(id)
		end)
		cards[id] = b
		return b
	end
	if includeRandom then
		local b = card(0, "random")
		Kit.Gradient(b, Color3.fromRGB(150, 80, 255), Color3.fromRGB(40, 24, 100), 45)
		Kit.Label(b, "🎲", 50, {
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 70),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Kit.Label(b, "RANDOM", 18, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(0, 94),
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Kit.Label(b, "Join any open race", 12, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(0, 118),
			Size = UDim2.new(1, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(215, 200, 255),
		})
	end
	for _, c in Circuits.List do
		local t = Track.Get(c.Id)
		local th = themeOf(c)
		local b = card(c.Round, c.Id)
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		Kit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, th.Accent:Lerp(Color3.fromRGB(20, 22, 34), 0.35)),
				ColorSequenceKeypoint.new(0.55, th.Accent:Lerp(Color3.fromRGB(20, 22, 34), 0.78)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 20, 31)),
			}),
			Rotation = 90,
			Parent = b,
		})
		local mapHolder = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(88, 88),
			Parent = b,
		})
		Hud.DrawTrack(mapHolder, smallMini(t, 3), 88, 2.5, Color3.fromRGB(250, 250, 252))
		local r = Kit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(10, 12, 20),
			BackgroundTransparency = 0.3,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = b,
		})
		Kit.Round(r)
		Kit.Padding(r, 6, 0)
		Kit.Label(r, "R" .. c.Round, 10, {
			Font = Kit.Fonts.Title,
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			TextColor3 = C.SubText,
		})
		Kit.Label(b, c.Flag, 18, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 5),
			Size = UDim2.fromOffset(28, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		Kit.Label(b, c.Name, 14, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(10, 104),
			Size = UDim2.new(1, -20, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local info = CircuitInfo.Get(c.Id)
		local cond = if th.Weather == "rain"
			then "  🌧️"
			elseif th.Weather == "snow" then "  🌨️"
			elseif th.Night then "  🌙"
			else ""
		Kit.Label(b, string.format("%s  •  %.1f km%s", c.Region, info.LengthKm, cond), 11, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(10, 122),
			Size = UDim2.new(1, -20, 0, 14),
			TextColor3 = C.SubText,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Kit.Label(b, CircuitInfo.Stars(info.Difficulty), 11, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(10, 137),
			Size = UDim2.new(1, -20, 0, 14),
			TextColor3 = C.Gold,
		})
		local medal = State.Profile and State.Profile.medals and State.Profile.medals[c.Id]
		if medal and medal > 0 then
			Kit.Label(b, Util.MedalIcon(medal), 16, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 28),
				Size = UDim2.fromOffset(24, 20),
				TextXAlignment = Enum.TextXAlignment.Right,
			})
		end
	end
	return scroll, setSelected
end

-- A small fact tag in the circuit details (length, corners, laps...).
local function factChip(parent, glyph, text, order)
	local f = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		BackgroundTransparency = 0.3,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Round(f)
	Kit.Padding(f, 10, 0)
	Kit.Label(
		f,
		glyph .. "  " .. text,
		12,
		{ Font = Kit.Fonts.Bold, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X }
	)
end

-- Big circuit header used by Quick Race & Time Trial detail panels
local function circuitDetails(parent, id)
	Util.Clear(parent, true)
	if id == "random" then
		Kit.IconTile(parent, "🎲", 90, C.Purple)
		Kit.Label(
			parent,
			"Random circuit",
			24,
			{ Font = Kit.Fonts.Title, Position = UDim2.fromOffset(106, 4), Size = UDim2.new(1, -106, 0, 30) }
		)
		Kit.Label(
			parent,
			"Jump into any open quick race, or start a new one on a random circuit from all "
				.. #Circuits.List
				.. " tracks.",
			13,
			{
				Position = UDim2.fromOffset(106, 38),
				Size = UDim2.new(1, -106, 0, 60),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextColor3 = C.SubText,
			}
		)
		return
	end
	local c = Circuits.ById[id]
	local t = Track.Get(id)
	local th = themeOf(c)
	local map = Kit.new(
		"Frame",
		{ BackgroundColor3 = Color3.fromRGB(10, 12, 20), Size = UDim2.fromOffset(150, 150), Parent = parent }
	)
	Kit.Corner(map, 14)
	Kit.Gradient(map, th.Accent:Lerp(Color3.fromRGB(10, 12, 20), 0.7), Color3.fromRGB(10, 12, 20), 90)
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(134, 134),
		Parent = map,
	})
	Hud.DrawTrack(holder, t.Minimap, 134, 4, th.Accent:Lerp(C.White, 0.3))
	Kit.Label(parent, "ROUND " .. c.Round .. "  •  " .. string.upper(c.Region), 11, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromOffset(164, 0),
		Size = UDim2.new(1, -164, 0, 16),
		TextColor3 = th.Accent:Lerp(C.White, 0.3),
	})
	Kit.Label(parent, c.Flag .. "  " .. c.Name, 22, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromOffset(164, 16),
		Size = UDim2.new(1, -164, 0, 28),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Kit.Label(parent, c.Blurb, 13, {
		Position = UDim2.fromOffset(164, 46),
		Size = UDim2.new(1, -164, 0, 46),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.SubText,
	})
	local facts = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(164, 94),
		Size = UDim2.new(1, -164, 0, 56),
		Parent = parent,
	})
	local grid = Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 26),
		CellPadding = UDim2.fromOffset(6, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = facts,
	})
	grid.FillDirectionMaxCells = 2
	local info = CircuitInfo.Get(id)
	factChip(facts, "📏", string.format("%.2f km  •  %d corners", info.LengthKm, info.Corners), 1)
	factChip(facts, "🛑", string.format("%d braking zones", info.BrakingZones), 2)
	factChip(facts, if th.Night then "🌙" else "☀️", string.format("%s  •  %d°C", th.TimeOfDay, th.Temp), 3)
	factChip(facts, "⭐", CircuitInfo.Stars(info.Difficulty) .. "  " .. raceTimeText(t), 4)
end

---------------------------------------------------------------------------
-- Quick Race
---------------------------------------------------------------------------
local Quick = {}
Pages.Quick = Quick
local quickSelected = "random"
local lobbyList, quickDetails
local lobbyRefreshToken = 0

-- Reloads the list of open races.
local function refreshLobbies()
	lobbyRefreshToken += 1
	local my = lobbyRefreshToken
	task.spawn(function()
		local res = Util.Invoke("GetLobbies")
		if my ~= lobbyRefreshToken or not lobbyList then
			return
		end
		Util.Clear(lobbyList, true)
		local list = (res and res.lobbies) or {}
		if #list == 0 then
			Kit.Label(
				lobbyList,
				"No open races right now - start one and others can join!",
				13,
				{ TextColor3 = C.SubText, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y }
			)
		end
		for i, l in list do
			local c = l.TrackId and Circuits.ById[l.TrackId]
			local row = Kit.Card(lobbyList, { Size = UDim2.new(1, 0, 0, 52), LayoutOrder = i })
			local modeColor = if l.Mode == "ranked" then C.Purple elseif l.Private then C.Accent2 else C.Accent
			local bar = Kit.new("Frame", {
				BackgroundColor3 = modeColor,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 10),
				Size = UDim2.fromOffset(4, 32),
				Parent = row,
			})
			Kit.Corner(bar, 2)
			local title = if c then (c.Flag .. "  " .. c.Name) else "🏆  Ranked - map vote"
			Kit.Label(row, title, 14, {
				Font = Kit.Fonts.Bold,
				Position = UDim2.fromOffset(14, 5),
				Size = UDim2.new(1, -110, 0, 22),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local left = math.max(0, math.ceil(l.EndsAt - workspace:GetServerTimeNow()))
			Kit.Label(
				row,
				string.format("%d/%d racers  •  host %s  •  %ds", l.Count, l.Max, l.HostName, left),
				11,
				{
					Font = Kit.Fonts.Bold,
					Position = UDim2.fromOffset(14, 27),
					Size = UDim2.new(1, -110, 0, 16),
					TextColor3 = C.SubText,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}
			)
			if res.mine ~= l.Id then
				Kit.Button(row, "JOIN", "success", function()
					task.spawn(function()
						local r = Util.Invoke("JoinLobby", l.Id) -- join THIS lobby (ranked included)
						if r and not r.ok then
							Kit.Toast(r.err or "Couldn't join", "error")
						end
						refreshLobbies()
					end)
				end, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.fromOffset(80, 34),
					TextSize = 14,
				})
			else
				Kit.Chip(
					row,
					"YOU'RE IN",
					C.Success,
					{ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0) }
				)
			end
		end
	end)
end

-- Builds the Quick Race page: circuit grid, details and open races.
function Quick.Build(parent, menu)
	local f, body = menu.PageFrame(parent, "Quick Race", "Pick a circuit and race a full 10-car grid")
	Quick.Frame = f
	local left = Kit.Panel(body, { Size = UDim2.new(0.6, -8, 1, 0) })
	Kit.Padding(left, 14, 14)
	Kit.Section(left, "Choose a circuit", 0)
	local gridHolder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		Parent = left,
	})
	local _, setSel = circuitGrid(gridHolder, function(id)
		quickSelected = id
		circuitDetails(quickDetails, id)
	end, true)
	Quick.SetSelected = setSel
	local right = Kit.Panel(
		body,
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, -8, 1, 0) }
	)
	Kit.Padding(right, 16, 14)
	quickDetails = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 152), Parent = right })
	Kit.Button(right, "🏁  RACE NOW", "primary", function()
		task.spawn(function()
			local res = Util.Invoke("QuickRace", quickSelected, false)
			if res and res.ok then
				Kit.Toast("Joined a race - waiting for racers...", "success")
				refreshLobbies()
			else
				Kit.Toast((res and res.err) or "Couldn't create a race", "error")
			end
		end)
	end, { Position = UDim2.fromOffset(0, 164), Size = UDim2.new(1, 0, 0, 54), TextSize = 22 })
	Kit.Button(right, "🔒  Private race with friends", "secondary", function()
		if not State.HasPass("PrivateRaces") then
			Kit.Modal("🔒 Private Races", "Host friends-only races on any circuit and choose the number of laps.", {
				{ "Not now", "secondary" },
				{
					"Get Private Races",
					"primary",
					function()
						State.PromptPass("PrivateRaces")
					end,
				},
			})
			return
		end
		Kit.Prompt(
			"🔒 Private race - laps",
			"Number of laps (1-10)",
			tostring(if quickSelected ~= "random" then Track.Get(quickSelected).Laps else Track.RaceLaps),
			function(text)
				task.spawn(function()
					local res = Util.Invoke("QuickRace", quickSelected, true, tonumber(text) or 3)
					if res and res.ok then
						Kit.Toast("Private race created - your friends can join from Quick Race!", "success")
					else
						Kit.Toast((res and res.err) or "Couldn't create a race", "error")
					end
				end)
			end,
			2
		)
	end, { Position = UDim2.fromOffset(0, 226), Size = UDim2.new(1, 0, 0, 42), TextSize = 15 })
	local sec = Kit.Section(right, "Open races", 0, C.Success)
	sec.Position = UDim2.fromOffset(0, 282)
	lobbyList = Kit.ScrollList(right, { Position = UDim2.fromOffset(0, 312), Size = UDim2.new(1, 0, 1, -312) }, 6)
end

local refreshLoop = 0
-- Page opened: show the selected circuit and refresh the open races every few seconds.
function Quick.OnShow()
	circuitDetails(quickDetails, quickSelected)
	Quick.SetSelected(quickSelected)
	refreshLoop += 1
	local my = refreshLoop
	task.spawn(function()
		while Quick.Frame.Visible and refreshLoop == my do
			refreshLobbies()
			task.wait(3)
		end
	end)
end

-- Page closed: stop refreshing.
function Quick.OnHide()
	refreshLoop += 1
end

---------------------------------------------------------------------------
-- Leaderboard helpers
---------------------------------------------------------------------------
local FORMATS = {
	ranked = function(v)
		return Kit.Comma(v) .. " RP"
	end,
	wins = function(v)
		return Kit.Comma(v) .. (if v == 1 then " win" else " wins")
	end,
	level = function(v)
		local lvl = math.floor(v / 1000000)
		return "Level " .. lvl
	end,
	tt = function(v)
		return Medals.FormatTime(v)
	end,
}
Pages.Formats = FORMATS

-- Gold, silver and bronze for the top three, grey for the rest.
local function rankColor(i)
	return if i == 1 then C.Gold elseif i == 2 then C.Silver elseif i == 3 then C.Bronze else C.SubText
end

-- second line under a driver's name on each board
local function boardSubline(e, kind: string): string
	if kind == "ranked" then
		return (if e.champion then "👑 " else "") .. Config.RankName(e.value, e.champion)
	elseif kind == "level" then
		return "Level " .. tostring(math.floor(e.value / 1000000))
	elseif kind == "wins" then
		return if e.value == 1 then "1 victory" else (Kit.Comma(e.value) .. " victories")
	end
	return "Verified lap"
end

-- A leaderboard row: rank, avatar, name + subline, (rank badge), value
local function boardRow(parent, i: number, e, kind: string, order: number, highlight: boolean?, note: string?)
	local me = e.userId == player.UserId
	local top3 = i >= 1 and i <= 3
	local bg = if me or highlight
		then Color3.fromRGB(72, 58, 22)
		elseif i % 2 == 0 then C.Panel2
		else C.Panel2:Lerp(C.Panel, 0.45)
	local row = Kit.Card(parent, { Size = UDim2.new(1, 0, 0, 52), LayoutOrder = order }, bg)
	if e.champion then
		Kit.Stroke(row, Config.Ranked.Tiers[#Config.Ranked.Tiers].Color, 1.2, 0.35)
	elseif me or highlight then
		Kit.Stroke(row, C.Accent, 1.4, 0.2)
	end
	-- rank: a medal disc for the top 3, a number otherwise
	if top3 then
		local disc = Kit.new("Frame", {
			BackgroundColor3 = rankColor(i),
			Position = UDim2.fromOffset(14, 11),
			Size = UDim2.fromOffset(30, 30),
			Parent = row,
		})
		Kit.Round(disc)
		Kit.Gradient(disc, rankColor(i):Lerp(C.White, 0.3), rankColor(i):Lerp(Color3.new(0, 0, 0), 0.2), 90)
		local n = Kit.Label(disc, tostring(i), 15, {
			Font = Kit.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = rankColor(i):Lerp(Color3.new(0, 0, 0), 0.7),
		})
		n.RichText = false
	else
		local rk = Kit.Label(row, if i > 0 then ("#" .. i) else "—", 15, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.fromOffset(46, 52),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.SubText,
		})
		rk.RichText = false
	end
	Kit.Avatar(row, e.userId, 36, e.name, if top3 then rankColor(i) else nil, { Position = UDim2.fromOffset(58, 8) })
	Kit.Label(row, e.name .. (if me then "  <font color='#FFC83C'>YOU</font>" else ""), 15, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(104, 7),
		Size = UDim2.new(1, -270, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Kit.Label(row, note or boardSubline(e, kind), 12, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(104, 27),
		Size = UDim2.new(1, -270, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = if note then C.Accent else C.SubText,
	})
	if kind == "ranked" then
		local tier, div = Config.DivisionFor(e.value, e.champion)
		Kit.TierBadge(row, tier, 34, div, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -128, 0.5, 0) })
	end
	local vl = Kit.Label(row, FORMATS[kind](e.value), 16, {
		Font = if kind == "tt" then Kit.Fonts.Mono else Kit.Fonts.Title,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromOffset(112, 52),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if top3 then rankColor(i) else C.Text,
	})
	vl.RichText = false
	return row
end

-- Top-3 podium: three cards, the winner's tallest with a bobbing crown
local function podium(parent, entries, kind: string)
	local f = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 240), LayoutOrder = 1, Parent = parent }
	)
	local order = { 2, 1, 3 }
	local tops = { [1] = 0, [2] = 28, [3] = 44 }
	for col, place in order do
		local e = entries[place]
		local color = rankColor(place)
		local card = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Position = UDim2.new((col - 1) / 3, 6, 0, tops[place]),
			Size = UDim2.new(1 / 3, -12, 1, -tops[place]),
			Parent = f,
		})
		Kit.Corner(card, 16)
		Kit.new("UIGradient", {
			Color = ColorSequence.new(color:Lerp(C.Panel2, if e then 0.5 else 0.85), C.Panel2),
			Rotation = 90,
			Parent = card,
		})
		Kit.Stroke(card, color, if place == 1 then 2 else 1.2, if e then (if place == 1 then 0 else 0.3) else 0.7)
		local disc = Kit.new("Frame", {
			BackgroundColor3 = color,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(30, 30),
			ZIndex = 3,
			Parent = card,
		})
		Kit.Round(disc)
		local dn = Kit.Label(disc, tostring(place), 16, {
			Font = Kit.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = color:Lerp(Color3.new(0, 0, 0), 0.65),
			ZIndex = 3,
		})
		dn.RichText = false
		local av = if place == 1 then 84 else 66
		local avY = if place == 1 then 36 else 20
		if e then
			if place == 1 then
				local glow = Kit.new("Frame", {
					BackgroundColor3 = color,
					BackgroundTransparency = 0.8,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0, avY + av / 2),
					Size = UDim2.fromOffset(av + 22, av + 22),
					Parent = card,
				})
				Kit.Round(glow)
			end
			Kit.Avatar(
				card,
				e.userId,
				av,
				e.name,
				color,
				{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, avY) }
			)
			if place == 1 then
				local crown = Kit.Label(card, "👑", 34, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 0, avY + 10),
					Size = UDim2.fromOffset(56, 42),
					TextXAlignment = Enum.TextXAlignment.Center,
					Rotation = -14,
					ZIndex = 4,
				})
				Kit.Loop(crown, 0.55, { Position = UDim2.new(0.5, 0, 0, avY + 5) })
				Kit.Loop(crown, 0.9, { Rotation = -4 })
			end
			local y = avY + av + 8
			Kit.Label(card, e.name, if place == 1 then 17 else 15, {
				Font = Kit.Fonts.Title,
				Position = UDim2.fromOffset(8, y),
				Size = UDim2.new(1, -16, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local v = Kit.Label(card, FORMATS[kind](e.value), if place == 1 then 16 else 14, {
				Font = if kind == "tt" then Kit.Fonts.Mono else Kit.Fonts.Title,
				Position = UDim2.fromOffset(8, y + 22),
				Size = UDim2.new(1, -16, 0, 20),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = color,
			})
			v.RichText = false
			Kit.Label(card, boardSubline(e, kind), 12, {
				Font = Kit.Fonts.Bold,
				Position = UDim2.fromOffset(8, y + 42),
				Size = UDim2.new(1, -16, 0, 16),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = C.SubText,
			})
		else
			-- empty spot: an invitation instead of a blank
			local ph = Kit.new("Frame", {
				BackgroundColor3 = C.Panel3,
				BackgroundTransparency = 0.3,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, avY),
				Size = UDim2.fromOffset(av, av),
				Parent = card,
			})
			Kit.Round(ph)
			Kit.Stroke(ph, color, 1.5, 0.5)
			Kit.Label(ph, "?", av * 0.45, {
				Font = Kit.Fonts.Title,
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = color:Lerp(C.White, 0.3),
			})
			Kit.Label(card, "Claim this spot", 14, {
				Font = Kit.Fonts.Title,
				Position = UDim2.fromOffset(8, avY + av + 10),
				Size = UDim2.new(1, -16, 0, 20),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = C.SubText,
			})
		end
	end
	return f
end

-- Fills `list` (a ScrollList) with a podium + rows, and `pinned` with your row
local boardToken = 0
-- Loads a leaderboard from the server and fills `list` with a podium and rows, and
-- `pinned` with the player's own row. `withGhosts` (lap records) lists every row with a
-- ghost button to pick whose laps to race against.
local function loadBoard(list, pinned, kind: string, id: string?, emptyText: string, withGhosts, onGhosts)
	boardToken += 1
	local my = boardToken
	Util.Clear(list, true)
	if pinned then
		Util.Clear(pinned, true)
	end
	Kit.Label(list, "Loading...", 14, { TextColor3 = C.SubText })
	task.spawn(function()
		local res = Util.Invoke("GetLeaderboard", kind, id)
		if my ~= boardToken then
			return
		end
		Util.Clear(list, true)
		local entries = (res and res.entries) or {}
		if #entries == 0 then
			local e = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 180), Parent = list })
			Kit.IconTile(
				e,
				"🏆",
				80,
				C.Accent,
				{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16) }
			)
			Kit.Label(e, emptyText, 15, {
				Font = Kit.Fonts.Bold,
				Position = UDim2.fromOffset(0, 112),
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = true,
				TextColor3 = C.SubText,
			})
		elseif not withGhosts then
			podium(list, entries, kind)
		end
		local maxGhosts = if State.HasPass("ProRacer") then 5 else 1
		local selected = {}
		for i, e in entries do
			if withGhosts or i > 3 then
				local row = boardRow(list, i, e, kind, 10 + i)
				if withGhosts and e.userId ~= player.UserId then
					local gb
					gb = Kit.Button(row, "👻", "secondary", function()
						local idx = table.find(selected, e.userId)
						if idx then
							table.remove(selected, idx)
							Kit.SetButtonStyle(gb, "secondary")
						else
							if #selected >= maxGhosts then
								if maxGhosts < 5 then
									Kit.Modal(
										"👻 More ghosts",
										"Free racers can chase 1 ghost at a time. The Pro Racer Pack lets you race up to 5 ghosts at once!",
										{
											{ "Not now", "secondary" },
											{
												"Get Pro Racer",
												"primary",
												function()
													State.PromptPass("ProRacer")
												end,
											},
										}
									)
								end
								return
							end
							table.insert(selected, e.userId)
							Kit.SetButtonStyle(gb, "blue")
						end
						if onGhosts then
							onGhosts(selected)
						end
					end, {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -130, 0.5, 0),
						Size = UDim2.fromOffset(40, 32),
						TextSize = 15,
					})
					if #selected == 0 then
						table.insert(selected, e.userId)
						Kit.SetButtonStyle(gb, "blue")
					end
				end
			end
		end
		if onGhosts then
			onGhosts(selected)
		end
		-- your position
		if pinned then
			local myRank, myEntry = 0, nil
			for i, e in entries do
				if e.userId == player.UserId then
					myRank, myEntry = i, e
				end
			end
			if not myEntry and res and res.mine ~= nil then
				myEntry =
					{ userId = player.UserId, name = player.DisplayName, value = res.mine, champion = res.champion }
			end
			if myEntry then
				-- how far to the next place up
				local note = nil
				local above = if myRank > 1 then entries[myRank - 1] elseif myRank == 0 then entries[#entries] else nil
				if myRank == 1 then
					note = "👑 You're #1 - defend it!"
				elseif above and kind ~= "tt" and above.value > myEntry.value then
					local gap = above.value - myEntry.value
					if kind == "level" then
						note = string.format("Level up to chase #%d", if myRank > 1 then myRank - 1 else #entries)
					else
						note = string.format(
							"%s more to pass #%d",
							Kit.Comma(gap) .. (if kind == "ranked" then " RP" else ""),
							if myRank > 1 then myRank - 1 else #entries
						)
					end
				elseif above and kind == "tt" and myEntry.value > above.value then
					note = string.format(
						"%.3f s to beat #%d",
						math.max(0.001, (myEntry.value - above.value) / 1000),
						if myRank > 1 then myRank - 1 else #entries
					)
				end
				boardRow(pinned, myRank, myEntry, kind, 1, true, note)
			else
				Kit.Label(pinned, "You're not on this board yet - get racing!", 13, {
					Font = Kit.Fonts.Bold,
					Size = UDim2.new(1, 0, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = C.SubText,
				})
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Ranked hub
---------------------------------------------------------------------------
local Ranked = {}
Pages.Ranked = Ranked
local rankLeft, historyList, rankBoard, rankPinned, rankTab = nil, nil, nil, nil, "history"

-- The player's rank card: tier emblem, division, RP bar and what's next.
local function renderRank()
	Util.Clear(rankLeft, true)
	local p = State.Profile
	local rp = p.rp or 0
	local champ = p.champion == true
	local ci = p.championInfo or {}
	local tier, div, frac, need, nextLabel = Config.DivisionFor(rp, champ)
	local resetIn = math.max(0, (ci.resetsAt or 0) - os.time())
	local resetText = string.format("%dh %dm", resetIn // 3600, (resetIn % 3600) // 60)
	local card = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), LayoutOrder = 1, Parent = rankLeft }
	)
	local glow = Kit.new(
		"Frame",
		{ BackgroundColor3 = tier.Color, BackgroundTransparency = 0.85, Size = UDim2.fromScale(1, 1), Parent = card }
	)
	Kit.Corner(glow, 14)
	Kit.Gradient(glow, tier.Color, Color3.fromRGB(20, 22, 34), 0)
	Kit.TierBadge(card, tier, 140, div, { Position = UDim2.fromOffset(12, 15) })
	Kit.Label(card, string.upper(Config.Ranked.Season.Name) .. " RANK", 11, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromOffset(166, 20),
		Size = UDim2.new(1, -176, 0, 14),
		TextColor3 = C.SubText,
	})
	Kit.Label(card, (if champ then "👑 " else "") .. string.upper(Config.RankName(rp, champ)), 28, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromOffset(166, 36),
		Size = UDim2.new(1, -176, 0, 34),
		TextColor3 = tier.Color:Lerp(C.White, 0.2),
	})
	Kit.Label(
		card,
		Kit.Comma(rp) .. " RP",
		17,
		{ Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(166, 70), Size = UDim2.new(1, -176, 0, 22) }
	)
	Kit.Bar(card, frac, tier.Color, { Position = UDim2.fromOffset(166, 102), Size = UDim2.new(1, -186, 0, 10) })
	local status
	if champ then
		status = string.format("Top %d driver today  •  list re-picked in %s", Config.Ranked.ChampionSlots, resetText)
	elseif need > 0 then
		status = string.format("%d RP to <b>%s</b>", need, nextLabel)
	else
		status =
			string.format("Champion qualifier! Be top %d at 00:00 UTC (in %s)", Config.Ranked.ChampionSlots, resetText)
	end
	Kit.Label(card, status, 12, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(166, 118),
		Size = UDim2.new(1, -176, 0, 18),
		TextColor3 = if need > 0 then C.SubText else C.Gold,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local peak = p.peakRp or rp
	local peakIdx = p.peakTier or Config.TierIndex(peak)
	local peakName = if peakIdx >= #Config.Ranked.Tiers then "Champion" else Config.RankName(peak)
	Kit.Label(card, "Season peak: " .. peakName, 12, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(166, 138),
		Size = UDim2.new(1, -176, 0, 18),
		TextColor3 = C.Muted,
	})

	-- season rewards track
	local season = Kit.Card(rankLeft, { Size = UDim2.new(1, 0, 0, 132), LayoutOrder = 2 })
	Kit.Padding(season, 12, 10)
	local left = Config.Ranked.Season.EndsAt - os.time()
	Kit.Label(
		season,
		string.format(
			"🏆  SEASON REWARDS  •  ends in %dd %dh",
			math.max(0, left) // 86400,
			(math.max(0, left) % 86400) // 3600
		),
		12,
		{ Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.Accent }
	)
	local track = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 1, -24),
		Parent = season,
	})
	Kit.List(track, Enum.FillDirection.Horizontal, 6)
	for i, tt in Config.Ranked.Tiers do
		local unlocked = peakIdx >= i
		local cell = Kit.new("Frame", {
			BackgroundColor3 = if unlocked then tt.Color:Lerp(C.Panel2, 0.7) else Color3.fromRGB(14, 16, 26),
			Size = UDim2.new(1 / 6, -5, 1, 0),
			LayoutOrder = i,
			Parent = track,
		})
		Kit.Corner(cell, 10)
		Kit.Stroke(cell, tt.Color, 1.2, if unlocked then 0.2 else 0.75)
		Kit.TierBadge(cell, tt, 42, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4) })
		Kit.Label(cell, tt.Name, 11, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(0, 48),
			Size = UDim2.new(1, 0, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if unlocked then C.White else C.Muted,
		})
		local reward = Cosmetics.RankedRewards and Cosmetics.RankedRewards[i]
		if i == #Config.Ranked.Tiers and not unlocked then
			reward = string.format("Top %d only", Config.Ranked.ChampionSlots)
		end
		Kit.Label(cell, if unlocked and i > 1 then "✓ " .. (reward or "") elseif reward then reward else "Start", 9, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(2, 64),
			Size = UDim2.new(1, -4, 0, 24),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = if unlocked then C.Success else C.SubText,
		})
	end

	local findBtn = Kit.Button(rankLeft, "🏆  FIND RANKED MATCH", "purple", function()
		task.spawn(function()
			local res = Util.Invoke("RankedQueue")
			if res and res.ok then
				local l = res.lobby or {}
				if l.Searching or l.Waiting then
					Kit.Toast("Searching for rivals - real players only", "info")
				else
					Kit.Toast("Match found - vote for the circuit!", "success")
				end
			else
				Kit.Toast((res and res.err) or "Couldn't join ranked", "error")
			end
		end)
	end, { Size = UDim2.new(1, 0, 0, 58), TextSize = 21, LayoutOrder = 3 })
	findBtn.TextColor3 = C.White
	local st = p.stats or {}
	local rules = Kit.Card(rankLeft, { Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 4 })
	Kit.Padding(rules, 12, 10)
	Kit.Label(
		rules,
		string.format(
			"RP PER FINISH  •  %d ranked races played  •  leaving costs %d RP",
			st.rankedRaces or 0,
			Config.Ranked.LeaveRP
		),
		11,
		{ Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 14), TextColor3 = C.SubText }
	)
	local rrow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 48),
		Parent = rules,
	})
	Kit.List(rrow, Enum.FillDirection.Horizontal, 4)
	for pos, delta in Config.Ranked.PositionRP do
		local cell = Kit.new("Frame", {
			BackgroundColor3 = if delta >= 0 then Color3.fromRGB(20, 60, 36) else Color3.fromRGB(70, 22, 28),
			Size = UDim2.new(0.1, -4, 1, 0),
			LayoutOrder = pos,
			Parent = rrow,
		})
		Kit.Corner(cell, 8)
		Kit.Label(cell, "P" .. pos, 11, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(0, 5),
			Size = UDim2.new(1, 0, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.SubText,
		})
		Kit.Label(cell, (if delta >= 0 then "+" else "") .. delta, 14, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if delta >= 0 then C.Success else C.Danger,
		})
	end
end

-- The player's last 10 races with positions and RP changes.
local function renderHistory()
	Util.Clear(historyList, true)
	local hist = State.Profile.history or {}
	if #hist == 0 then
		local e = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 220), Parent = historyList })
		Kit.IconTile(
			e,
			"🏁",
			84,
			C.Purple,
			{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30) }
		)
		Kit.Label(e, "No ranked races yet", 18, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(0, 128),
			Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Kit.Label(e, "Your last 10 results and RP changes will show up here.", 13, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(0, 154),
			Size = UDim2.new(1, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.SubText,
		})
		return
	end
	for i = #hist, 1, -1 do
		local h = hist[i]
		local c = Circuits.ById[h.t] or Circuits.List[1]
		local row = Kit.Card(historyList, { Size = UDim2.new(1, 0, 0, 50), LayoutOrder = #hist - i + 1 })
		local posColor = if h.p == 1
			then C.Gold
			elseif h.p == 2 then C.Silver
			elseif h.p == 3 then C.Bronze
			elseif h.p and h.p <= 5 then C.Success
			else C.Panel3
		local chip = Kit.new("Frame", {
			BackgroundColor3 = posColor,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(46, 34),
			Parent = row,
		})
		Kit.Corner(chip, 8)
		Kit.Label(chip, if h.p then ("P" .. h.p) else "DNF", 15, {
			Font = Kit.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if h.p and h.p <= 3 then Color3.fromRGB(30, 22, 6) else C.White,
		})
		Kit.Label(row, c.Flag .. "  " .. c.Name, 14, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(64, 6),
			Size = UDim2.new(1, -150, 0, 20),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Kit.Label(
			row,
			(if h.at then Util.TimeAgo(h.at) else "") .. (if h.n then ("  •  " .. h.n .. " cars") else ""),
			11,
			{
				Font = Kit.Fonts.Bold,
				Position = UDim2.fromOffset(64, 26),
				Size = UDim2.new(1, -150, 0, 16),
				TextColor3 = C.SubText,
			}
		)
		local d = h.d or 0
		Kit.Label(row, (if d >= 0 then "+" else "") .. d .. " RP", 15, {
			Font = Kit.Fonts.Title,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromOffset(80, 50),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = if d >= 0 then C.Success else C.Danger,
		})
	end
end

-- Builds the Ranked page.
function Ranked.Build(parent, menu)
	local f, body = menu.PageFrame(parent, "Ranked", "Race real players, vote the map, climb from Bronze to Champion")
	Ranked.Frame = f
	local leftPanel = Kit.Panel(body, { Size = UDim2.new(0.5, -8, 1, 0) })
	Kit.Padding(leftPanel, 16, 14)
	rankLeft = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = leftPanel })
	Kit.List(rankLeft, Enum.FillDirection.Vertical, 10)
	local right = Kit.Panel(
		body,
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, -8, 1, 0) }
	)
	Kit.Padding(right, 16, 14)
	local tabsHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = right })
	historyList = Kit.ScrollList(right, { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -56) }, 6)
	rankBoard = Kit.ScrollList(
		right,
		{ Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -118), Visible = false },
		6
	)
	rankPinned = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 52),
		Visible = false,
		Parent = right,
	})
	Kit.List(rankPinned, Enum.FillDirection.Vertical, 0)
	local _, sel = Kit.Tabs(tabsHolder, {
		{ key = "history", text = "📜 Match history" },
		{ key = "top", text = "🌍 Top drivers" },
	}, function(key)
		rankTab = key
		historyList.Visible = key == "history"
		rankBoard.Visible = key == "top"
		rankPinned.Visible = key == "top"
		if key == "history" then
			renderHistory()
		else
			loadBoard(rankBoard, rankPinned, "ranked", nil, "No ranked drivers yet - be the first!")
		end
	end)
	Ranked.Select = sel
	State.Changed:Connect(function()
		if f.Visible then
			renderRank()
			if rankTab == "history" then
				renderHistory()
			end
		end
	end)
end

-- Page opened: refresh the rank card and the selected tab.
function Ranked.OnShow()
	renderRank()
	Ranked.Select(rankTab)
end

---------------------------------------------------------------------------
-- Time Trial
---------------------------------------------------------------------------
local TimeTrial = {}
Pages.TimeTrial = TimeTrial
local ttSelected = Circuits.List[1].Id
local ttDetails, ttMedals, ttBoard, ttGhosts = nil, nil, nil, {}

-- Time Trial details for the selected circuit: medal targets, your best and your medal.
local function renderTT()
	circuitDetails(ttDetails, ttSelected)
	local t = Track.Get(ttSelected)
	local th = Medals.FromIdeal(t.IdealLap)
	local best = State.Profile.bests[ttSelected]
	Util.Clear(ttMedals, true)
	for lvl = 4, 1, -1 do
		local got = best ~= nil and best <= th[lvl]
		local col = Config.Medals.Colors[lvl]
		local chip = Kit.new("Frame", {
			BackgroundColor3 = if got then col:Lerp(C.Panel2, 0.55) else Color3.fromRGB(14, 16, 26),
			Size = UDim2.new(0.25, -5, 1, 0),
			LayoutOrder = 5 - lvl,
			Parent = ttMedals,
		})
		Kit.Corner(chip, 10)
		Kit.Stroke(chip, col, 1.2, if got then 0.1 else 0.7)
		Kit.Label(chip, (if got then "✓ " else "") .. string.upper(Config.Medals.Names[lvl]), 10, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = col,
		})
		local l = Kit.Label(chip, Medals.FormatTime(th[lvl]), 13, {
			Font = Kit.Fonts.Mono,
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		l.RichText = false
	end
	TimeTrial.PB.Text = "Your best:  " .. Medals.FormatTime(best)
	ttGhosts = {}
	loadBoard(ttBoard, nil, "tt", ttSelected, "No lap records yet - set the first one!", true, function(sel)
		ttGhosts = table.clone(sel)
	end)
end

-- Builds the Time Trial page: circuit grid, medals, lap records and ghosts.
function TimeTrial.Build(parent, menu)
	local f, body = menu.PageFrame(parent, "Time Trial", "Hot laps, medals and ghosts - chase the lap record")
	TimeTrial.Frame = f
	local left = Kit.Panel(body, { Size = UDim2.new(0.56, -8, 1, 0) })
	Kit.Padding(left, 14, 14)
	Kit.Section(left, "Choose a circuit", 0, C.Accent2)
	local gridHolder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		Parent = left,
	})
	local _, setSel = circuitGrid(gridHolder, function(id)
		ttSelected = id
		renderTT()
	end, false)
	TimeTrial.SetSelected = setSel
	local right = Kit.Panel(
		body,
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.44, -8, 1, 0) }
	)
	Kit.Padding(right, 16, 14)
	ttDetails = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 152), Parent = right })
	ttMedals = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 160),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = right,
	})
	Kit.List(ttMedals, Enum.FillDirection.Horizontal, 6)
	TimeTrial.PB = Kit.Label(right, "", 14, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(0, 206),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = C.Accent2,
	})
	local sec = Kit.Section(right, "Lap records  •  👻 = race their ghost", 0, C.Accent2)
	sec.Position = UDim2.fromOffset(0, 232)
	ttBoard = Kit.ScrollList(right, { Position = UDim2.fromOffset(0, 262), Size = UDim2.new(1, 0, 1, -330) }, 6)
	Kit.Button(right, "⏱️  START TIME TRIAL", "blue", function()
		menu.StartTimeTrial({ trackId = ttSelected, ghostIds = table.clone(ttGhosts) })
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 56),
		TextSize = 21,
	})
end

-- Page opened: show the selected circuit.
function TimeTrial.OnShow()
	TimeTrial.SetSelected(ttSelected)
	renderTT()
end

---------------------------------------------------------------------------
-- Leaderboards
---------------------------------------------------------------------------
local Boards = {}
Pages.Boards = Boards
local boardList, boardPinned, boardTitle, boardSub, circuitBar, boardKind, boardCircuit =
	nil, nil, nil, nil, nil, "ranked", Circuits.List[1].Id
local catButtons = {}

local CATS = {
	{ "ranked", "🏆", "Ranked", "Highest ranked drivers this season" },
	{ "wins", "🥇", "Race wins", "Most race victories of all time" },
	{ "level", "⭐", "Level", "The most experienced racers" },
	{ "tt", "⏱️", "Lap records", "Fastest verified laps per circuit" },
}

-- Highlights the chosen category and loads its board.
local function showBoard()
	for k, b in catButtons do
		local on = k == boardKind
		b.BackgroundColor3 = if on then C.Accent else C.Panel2
		for _, d in b:GetChildren() do
			if d:IsA("TextLabel") then
				d.TextColor3 = if on then Color3.fromRGB(30, 20, 4) else C.Text
			end
		end
	end
	local cat
	for _, c in CATS do
		if c[1] == boardKind then
			cat = c
		end
	end
	boardTitle.Text = cat[2] .. "  " .. cat[3]
	boardSub.Text = cat[4]
	if boardKind == "ranked" then
		local ci = (State.Profile and State.Profile.championInfo) or {}
		local left = math.max(0, (ci.resetsAt or 0) - os.time())
		boardSub.Text = string.format(
			"%s  •  👑 the top %d are Champions",
			Config.Ranked.Season.Name,
			Config.Ranked.ChampionSlots
		) .. (if ci.resetsAt then string.format(" (next pick in %dh %dm)", left // 3600, (left % 3600) // 60) else "")
	end
	circuitBar.Visible = boardKind == "tt"
	local top = if boardKind == "tt" then 104 else 62
	boardList.Position = UDim2.fromOffset(0, top)
	boardList.Size = UDim2.new(1, 0, 1, -top - 62)
	if boardKind == "tt" then
		local c = Circuits.ById[boardCircuit]
		boardSub.Text = c.Flag .. "  " .. c.Name .. "  -  fastest verified laps"
		for id, b in circuitBar:GetChildren() do
			if b:IsA("TextButton") then
				local on = b.Name == boardCircuit
				b.BackgroundColor3 = if on then C.Accent2 else C.Panel2
			end
		end
	end
	loadBoard(
		boardList,
		boardPinned,
		boardKind,
		if boardKind == "tt" then boardCircuit else nil,
		"Nobody here yet - race to claim #1!"
	)
end

-- Builds the Leaderboards page.
function Boards.Build(parent, menu)
	local f, body = menu.PageFrame(parent, "Leaderboards", "Global rankings - updated live")
	Boards.Frame = f
	local nav = Kit.Panel(body, { Size = UDim2.new(0, 230, 1, 0) })
	Kit.Padding(nav, 12, 12)
	Kit.List(nav, Enum.FillDirection.Vertical, 8)
	for i, c in CATS do
		local b = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.Panel2,
			Size = UDim2.new(1, 0, 0, 52),
			LayoutOrder = i,
			Parent = nav,
		})
		Kit.Corner(b, 12)
		Kit.Label(b, c[2], 20, {
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.fromOffset(28, 52),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Kit.Label(
			b,
			c[3],
			16,
			{ Font = Kit.Fonts.Title, Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -56, 1, 0) }
		)
		Kit.Clickable(b, function()
			boardKind = c[1]
			showBoard()
		end)
		catButtons[c[1]] = b
	end
	local main = Kit.Panel(body, { Position = UDim2.fromOffset(246, 0), Size = UDim2.new(1, -246, 1, 0) })
	-- your stats under the categories
	local stats = Kit.Card(nav, { Size = UDim2.new(1, 0, 0, 150), LayoutOrder = 20 })
	Kit.Padding(stats, 12, 10)
	Kit.List(stats, Enum.FillDirection.Vertical, 4)
	Kit.Label(
		stats,
		"YOUR CAREER",
		11,
		{ Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.Accent, LayoutOrder = 0 }
	)
	Boards.StatLines = {}
	for i, key in { "races", "wins", "podiums", "fastestLaps" } do
		local l = Kit.Label(stats, "", 13, { Font = Kit.Fonts.Bold, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i })
		Boards.StatLines[key] = l
	end
	Kit.Padding(main, 18, 14)
	boardTitle = Kit.Label(main, "", 22, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 28) })
	boardSub = Kit.Label(main, "", 13, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = C.SubText,
	})
	circuitBar = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 40),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		Visible = false,
		Parent = main,
	})
	Kit.List(circuitBar, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for _, c in Circuits.List do
		local b = Kit.new("TextButton", {
			Name = c.Id,
			Text = c.Flag .. " " .. c.Name,
			Font = Kit.Fonts.Bold,
			TextSize = 12,
			TextColor3 = C.Text,
			AutoButtonColor = false,
			BackgroundColor3 = C.Panel2,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = c.Round,
			Parent = circuitBar,
		})
		Kit.Round(b)
		Kit.Padding(b, 12, 0)
		Kit.Clickable(b, function()
			boardCircuit = c.Id
			showBoard()
		end)
	end
	boardList = Kit.ScrollList(main, { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 1, -124) }, 6)
	local pinWrap = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -12, 0, 52),
		Parent = main,
	})
	boardPinned = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = pinWrap })
	Kit.List(boardPinned, Enum.FillDirection.Vertical, 0)
end

-- Page opened (optionally on a category): fill in the player's own stats and load the board.
function Boards.OnShow(arg)
	local st = State.Profile.stats or {}
	local names =
		{ races = "🏁  Races", wins = "🏆  Wins", podiums = "🥇  Podiums", fastestLaps = "⚡  Fastest laps" }
	for key, l in Boards.StatLines do
		l.Text = string.format("%s  <font color='#FFB81C'>%s</font>", names[key], Kit.Comma(st[key] or 0))
	end
	if arg and (arg == "ranked" or arg == "wins" or arg == "level" or arg == "tt") then
		boardKind = arg
	end
	showBoard()
end

Pages.LoadBoard = loadBoard
return Pages
