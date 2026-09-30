--!nonstrict
-- Main menu: bright showroom scene, status bar, home screen (mode cards + profile,
-- circuit of the day and season cards), page routing, race lobby panel (with the
-- ranked map vote) and the daily reward.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Circuits = require(Shared.Circuits)
local Challenges = require(Shared.Challenges)
local Track = require(Shared.Track)
local Net = require(Shared.Net)

local Kit = require(script.Parent.Kit)
local Hud = require(script.Parent.Hud)
local TopBar = require(script.Parent.TopBar)
local Showroom = require(script.Parent.Showroom)
local State = require(script.Parent.Parent.State)
local Util = require(script.Parent.Parent.Util)
local Fx = require(script.Parent.Parent.Fx)

local C = Kit.Colors
local player = Players.LocalPlayer
local Menu = {}
Menu.Pages = {}
Menu.Scene = Showroom

local gui, root = Kit.Screen("GoTrackMenu", 3)
gui.Enabled = false
Menu.Root = root
Menu.HoldDaily = false -- true while the welcome tour is open (the daily popup waits)

local function setCore(kind, on: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(kind, on)
	end)
end

TopBar.Build(root, Menu)

---------------------------------------------------------------------------
-- Home: left column
---------------------------------------------------------------------------
local home = Kit.new("Frame", { Name = "Home", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })

local leftCol = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(52, 80), Size = UDim2.fromOffset(420, 620), Parent = home })
Kit.List(leftCol, Enum.FillDirection.Vertical, 10)

local logoBox = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 132), LayoutOrder = 1, Parent = leftCol })
-- dark glass behind the logo so it stays readable over the bright 3D showroom
local logoBack = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(8, 10, 18), BackgroundTransparency = 0.25, Position = UDim2.fromOffset(-16, -8), Size = UDim2.new(1, 32, 1, 12), ZIndex = 0, Parent = logoBox })
Kit.Corner(logoBack, 18)
Kit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.75, 0.55), NumberSequenceKeypoint.new(1, 1) }), Parent = logoBack })
Kit.Logo(logoBox, 60, { Align = "left", Props = { Position = UDim2.fromOffset(2, 0) } })
local chips = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(2, 106), Size = UDim2.new(1, 0, 0, 24), Parent = logoBox })
Kit.List(chips, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
local function darkChip(text, color, order)
	local f = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(12, 14, 24), BackgroundTransparency = 0.1, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = chips })
	Kit.Round(f)
	Kit.Padding(f, 11, 0)
	Kit.Stroke(f, color, 1, 0.55)
	Kit.new("TextLabel", { BackgroundTransparency = 1, Text = text, FontFace = Kit.Faces.Heavy, TextSize = 12, TextColor3 = color, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Parent = f })
end
darkChip(#Circuits.List .. " CIRCUITS", C.Accent, 1)
darkChip("10-CAR GRIDS", C.Accent2, 2)
darkChip(string.upper(Config.Ranked.Season.Name), C.Purple, 3)

-- big mode cards
local function modeCard(order: number, glyph: string, title: string, sub: string, color: Color3, fn)
	local b = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, 74), LayoutOrder = order, Parent = leftCol })
	Kit.Corner(b, 16)
	Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.12)),
			ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.35)),
		}),
		Rotation = 0,
		Parent = b,
	})
	Kit.Stroke(b, color:Lerp(Color3.new(1, 1, 1), 0.5), 1.5, 0.35)
	local tile = Kit.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.72, Position = UDim2.fromOffset(12, 11), Size = UDim2.fromOffset(52, 52), Parent = b })
	Kit.Corner(tile, 14)
	Kit.Label(tile, glyph, 28, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.85)
	local light = (color.R * 0.299 + color.G * 0.587 + color.B * 0.114) > 0.62
	local tc = if light then dark else C.White
	Kit.Label(b, title, 22, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(78, 12), Size = UDim2.new(1, -120, 0, 28), TextColor3 = tc })
	Kit.Label(b, sub, 13, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(78, 40), Size = UDim2.new(1, -120, 0, 20), TextColor3 = tc, TextTransparency = 0.2 })
	Kit.Label(b, "›", 40, { Font = Kit.Fonts.Title, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, -3), Size = UDim2.fromOffset(24, 44), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = tc })
	Kit.Clickable(b, fn)
	return b
end
modeCard(10, "🏁", "QUICK RACE", "Pick any circuit • race 9 rivals", Color3.fromRGB(255, 176, 32), function()
	Menu.Open("quick")
end)
modeCard(11, "🏆", "RANKED", "Vote the map • climb the ladder", Color3.fromRGB(140, 80, 255), function()
	Menu.Open("ranked")
end)
modeCard(12, "⏱️", "TIME TRIAL", "Hot laps • chase ghosts • medals", Color3.fromRGB(30, 160, 255), function()
	Menu.Open("timetrial")
end)

local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 124), LayoutOrder = 20, Parent = leftCol })
Kit.Grid(grid, UDim2.new(0.5, -5, 0, 57), 10)
local function smallTile(order: number, glyph: string, title: string, fn)
	local b = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.1, LayoutOrder = order, Parent = grid })
	Kit.Corner(b, 14)
	Kit.Stroke(b, Color3.fromRGB(110, 120, 170), 1.2, 0.55)
	Kit.Label(b, glyph, 22, { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(30, 57), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Label(b, title, 16, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -60, 1, 0) })
	Kit.Clickable(b, fn)
	return b
end
smallTile(1, "🏎️", "GARAGE", function()
	Menu.Open("garage")
end)
smallTile(2, "🛒", "SHOP", function()
	Menu.Open("shop", "featured")
end)
smallTile(3, "📊", "LEADERBOARDS", function()
	Menu.Open("leaderboards")
end)
smallTile(4, "⚙️", "SETTINGS", function()
	Menu.Open("settings")
end)

Kit.BindInset(function(top)
	leftCol.Position = UDim2.fromOffset(if Kit.Compact() then 28 else 52, top + (if Kit.Compact() then 12 else 26))
end)
-- short phone screens: shrink the column to fit instead of running off the bottom
Kit.FitHeight(leftCol, 534, function()
	local top = Kit.Inset()
	return top + (if Kit.Compact() then 12 else 26) + 30
end)

---------------------------------------------------------------------------
-- Home: right column
---------------------------------------------------------------------------
local rightCol = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(300, 600), Parent = home })
Kit.List(rightCol, Enum.FillDirection.Vertical, 12)
Kit.BindInset(function(top)
	rightCol.Position = UDim2.new(1, if Kit.Compact() then -20 else -40, 0, top + (if Kit.Compact() then 12 else 26))
end)
Kit.FitHeight(rightCol, 440, function()
	local top = Kit.Inset()
	return top + (if Kit.Compact() then 12 else 26) + 30
end)

-- profile card
local profileCard = Kit.Panel(rightCol, { Size = UDim2.new(1, 0, 0, 118), LayoutOrder = 1 })
Kit.Padding(profileCard, 14, 12)
Kit.Avatar(profileCard, player.UserId, 54, player.DisplayName, C.Accent)
Kit.Label(profileCard, player.DisplayName, 18, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(66, 2), Size = UDim2.new(1, -66, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
local profileRank = Kit.Label(profileCard, "", 13, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(66, 26), Size = UDim2.new(1, -66, 0, 18), TextColor3 = C.SubText })
local statsRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 32), Parent = profileCard })
Kit.List(statsRow, Enum.FillDirection.Horizontal, 6)
local statLabels = {}
for i, key in { "races", "wins", "podiums" } do
	local s = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(10, 12, 20), BackgroundTransparency = 0.3, Size = UDim2.new(1 / 3, -4, 1, 0), LayoutOrder = i, Parent = statsRow })
	Kit.Corner(s, 8)
	local v = Kit.Label(s, "0", 15, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 1), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Label(s, string.upper(key), 9, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 12), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText })
	statLabels[key] = v
end

-- featured circuit of the week (rotates by itself; races there pay bonus coins)
local cotd = Circuits.ById[Challenges.Featured(Challenges.WeekAt(os.time()))] or Circuits.List[1]
local cotdCard = Kit.Panel(rightCol, { Size = UDim2.new(1, 0, 0, 196), LayoutOrder = 2 })
Kit.Padding(cotdCard, 14, 12)
Kit.Label(cotdCard, string.format("⭐ FEATURED THIS WEEK  •  ×%.1f COINS", Config.Economy.FeaturedCoinMultiplier), 11, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 14), TextColor3 = C.Accent })
Kit.Label(cotdCard, cotd.Flag .. "  " .. cotd.Name, 17, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
do
	local t = Track.Get(cotd.Id)
	Kit.Label(cotdCard, string.format("%s  •  %d laps  •  Round %d", cotd.Region, t.Laps, cotd.Round), 12, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.SubText, TextTruncate = Enum.TextTruncate.AtEnd })
	local mapHolder = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 62), Size = UDim2.fromOffset(84, 84), Parent = cotdCard })
	local mini = {}
	for i = 1, #t.Minimap, 2 do
		table.insert(mini, t.Minimap[i])
	end
	Hud.DrawTrack(mapHolder, mini, 84, 3, C.Accent)
	Kit.Label(cotdCard, cotd.Blurb, 12, { Position = UDim2.fromOffset(94, 64), Size = UDim2.new(1, -94, 0, 64), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.SubText })
	Kit.Button(cotdCard, "🏁  RACE HERE", "primary", function()
		task.spawn(function()
			local res = Util.Invoke("QuickRace", cotd.Id, false)
			if res and res.ok then
				Kit.Toast("Joined a race on " .. cotd.Name .. "!", "success")
			else
				Kit.Toast((res and res.err) or "Couldn't join", "error")
			end
		end)
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 36), TextSize = 15 })
end

-- season card
local seasonCard = Kit.Panel(rightCol, { Size = UDim2.new(1, 0, 0, 96), LayoutOrder = 3 })
Kit.Padding(seasonCard, 14, 12)
local seasonGrad = Kit.new("Frame", { BackgroundColor3 = C.Purple, BackgroundTransparency = 0.82, Size = UDim2.new(1, 28, 1, 24), Position = UDim2.fromOffset(-14, -12), ZIndex = 0, Parent = seasonCard })
Kit.Corner(seasonGrad, 16)
Kit.Label(seasonCard, "🏆  " .. string.upper(Config.Ranked.Season.Name), 15, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 20) })
local seasonTime = Kit.Label(seasonCard, "", 12, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.SubText })
local seasonHint = Kit.Label(seasonCard, "", 12, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(210, 190, 255) })

-- car name plate (under the car)
local plate = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(12, 14, 24), BackgroundTransparency = 0.15, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.55, 0, 1, -26), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Parent = home })
Kit.Round(plate)
Kit.Stroke(plate, C.Accent, 1.2, 0.5)
Kit.Padding(plate, 18, 0)
local plateLabel = Kit.Label(plate, "", 15, { Font = Kit.Fonts.Title, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X })

Kit.Label(root, "v" .. Config.Version, 11, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -6), Size = UDim2.fromOffset(200, 14), TextColor3 = C.Muted })

local function refreshHome()
	local p = State.Profile
	if not p then
		return
	end
	local rp = p.rp or 0
	local tier = Config.DivisionFor(rp, p.champion)
	profileRank.Text = string.format("<font color='#%s'>%s</font>  •  Level %d", tier.Color:ToHex(), Config.RankName(rp, p.champion), p.level)
	local st = p.stats or {}
	statLabels.races.Text = Kit.Comma(st.races or 0)
	statLabels.wins.Text = Kit.Comma(st.wins or 0)
	statLabels.podiums.Text = Kit.Comma(st.podiums or 0)
	local body = Cosmetics.ById[p.car.Body]
	plateLabel.Text = string.format("#%d   %s", Cosmetics.NumberFor(p.car, p.userId), string.upper(body and body.Name or "GT-1"))
	local ti = Config.TierIndex(rp, p.champion)
	local nextTier = Config.Ranked.Tiers[ti + 1]
	if not nextTier then
		seasonHint.Text = "👑 You're a Champion - stay in the top 500 at every daily reset!"
	elseif ti + 1 == #Config.Ranked.Tiers then
		seasonHint.Text = string.format("Champion is only for the top %d drivers, picked daily at 00:00 UTC!", Config.Ranked.ChampionSlots)
	else
		seasonHint.Text = string.format("Reach %s to unlock the %s season reward!", nextTier.Name, nextTier.Name)
	end
end
State.Changed:Connect(refreshHome)

RunService.Heartbeat:Connect(function()
	if gui.Enabled and home.Visible then
		local left = Config.Ranked.Season.EndsAt - os.time()
		if left > 0 then
			seasonTime.Text = string.format("Ends in %dd %dh %dm", left // 86400, (left % 86400) // 3600, (left % 3600) // 60)
		else
			seasonTime.Text = "Season ending - new season soon!"
		end
	end
end)

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local pageHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
local current = nil

function Menu.RegisterPage(name, page)
	Menu.Pages[name] = page
	page.Build(pageHolder, Menu)
	page.Frame.Visible = false
end

local function applyCamera(page)
	if page and page.Camera == "garage" then
		Showroom.CamGarage()
	elseif page and page.Camera == "home" then
		Showroom.CamHome()
	else
		Showroom.CamPage()
	end
end

function Menu.Open(name, arg)
	local page = Menu.Pages[name]
	if not page then
		return
	end
	if current and current ~= name then
		local old = Menu.Pages[current]
		old.Frame.Visible = false
		if old.OnHide then
			old.OnHide()
		end
	end
	current = name
	home.Visible = false
	page.Frame.Visible = true
	page.Frame.Position = UDim2.fromOffset(0, 18)
	Kit.Tween(page.Frame, 0.25, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quart)
	setCore(Enum.CoreGuiType.PlayerList, false)
	applyCamera(page)
	if page.OnShow then
		page.OnShow(arg)
	end
end

function Menu.Back()
	if current then
		local old = Menu.Pages[current]
		old.Frame.Visible = false
		if old.OnHide then
			old.OnHide()
		end
	end
	current = nil
	home.Visible = true
	setCore(Enum.CoreGuiType.PlayerList, true)
	Showroom.CamHome()
	refreshHome()
end

-- Standard page: header (back + title) below the Roblox top bar, body underneath
function Menu.PageFrame(parent, title: string, subtitle: string?)
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -100, 0, 52), Parent = f })
	local back = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(14, 16, 27), BackgroundTransparency = 0.1, Size = UDim2.fromOffset(52, 52), Parent = header })
	Kit.Round(back)
	Kit.Stroke(back, Color3.fromRGB(130, 140, 190), 1.5, 0.4)
	Kit.Label(back, "←", 26, { Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Clickable(back, function()
		Menu.Back()
	end)
	local tl = Kit.Label(header, title, 30, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(66, if subtitle then 0 else 8), Size = UDim2.new(1, -70, 0, 34) })
	Kit.new("UIStroke", { Color = Color3.fromRGB(8, 10, 18), Thickness = 2, Transparency = 0.5, Parent = tl })
	if subtitle then
		local sl = Kit.Label(header, subtitle, 14, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(67, 33), Size = UDim2.new(1, -70, 0, 18), TextColor3 = C.SubText })
		Kit.new("UIStroke", { Color = Color3.fromRGB(8, 10, 18), Thickness = 1.5, Transparency = 0.5, Parent = sl })
	end
	local body = Kit.new("Frame", { BackgroundTransparency = 1, Parent = f })
	Kit.BindInset(function(top)
		-- phones: tighter margins so the page body gets as much height as possible
		local compact = Kit.Compact()
		local side = if compact then 18 else 32
		local headTop = if compact then top + 6 else top + 14
		local bodyTop = if compact then top + 66 else top + 80
		local bottom = if compact then 10 else 22
		header.Position = UDim2.fromOffset(side, headTop)
		body.Position = UDim2.fromOffset(side, bodyTop)
		body.Size = UDim2.new(1, -side * 2, 1, -bodyTop - bottom)
	end)
	return f, body
end

function Menu.Current()
	return current
end

---------------------------------------------------------------------------
-- Lobby panel (while waiting for a race) with the ranked map vote
---------------------------------------------------------------------------
local lobbyPanel = Kit.Panel(root, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(700, 168), Visible = false, ZIndex = 5 })
local lobbyMap = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(10, 12, 20), Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(140, 140), ZIndex = 6, Parent = lobbyPanel })
Kit.Corner(lobbyMap, 12)
local lobbyMode = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(168, 14), Size = UDim2.fromOffset(300, 22), ZIndex = 6, Parent = lobbyPanel })
local lobbyTitle = Kit.Label(lobbyPanel, "", 22, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(168, 40), Size = UDim2.new(1, -330, 0, 28), ZIndex = 6, TextTruncate = Enum.TextTruncate.AtEnd })
local lobbyInfo = Kit.Label(lobbyPanel, "", 13, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(168, 68), Size = UDim2.new(1, -330, 0, 18), ZIndex = 6, TextColor3 = C.SubText })
local lobbyNames = Kit.Label(lobbyPanel, "", 13, { Position = UDim2.fromOffset(168, 90), Size = UDim2.new(1, -330, 0, 62), ZIndex = 6, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
local voteRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(168, 88), Size = UDim2.new(1, -330, 0, 68), ZIndex = 6, Visible = false, Parent = lobbyPanel })
Kit.List(voteRow, Enum.FillDirection.Horizontal, 8)
local countBox = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(10, 12, 20), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(140, 64), ZIndex = 6, Parent = lobbyPanel })
Kit.Corner(countBox, 12)
local lobbyCount = Kit.Label(countBox, "20", 34, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7, TextColor3 = C.Accent })
local lobbyCountLabel = Kit.Label(countBox, "STARTS IN", 10, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7, TextColor3 = C.SubText })
local startNowBtn = Kit.Button(lobbyPanel, "▶ Start now", "success", function()
	task.spawn(Util.Invoke, "StartNow")
end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -58), Size = UDim2.fromOffset(140, 38), TextSize = 15, ZIndex = 6 })
Kit.Button(lobbyPanel, "✖ Leave", "danger", function()
	task.spawn(Util.Invoke, "LeaveLobby")
	Menu.SetLobby(nil)
end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(140, 38), TextSize = 15, ZIndex = 6 })

local function setZ(inst, z)
	for _, d in inst:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = z
		end
	end
end

Menu.Lobby = nil
local drawnKey = nil
local function drawLobbyMap(trackId: string?)
	local key = trackId or "?"
	if drawnKey == key then
		return
	end
	drawnKey = key
	Util.Clear(lobbyMap, true)
	if not trackId then
		Kit.Label(lobbyMap, "?", 70, { Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Purple, ZIndex = 7 })
		return
	end
	local t = Track.Get(trackId)
	local mini = {}
	for i = 1, #t.Minimap, 2 do
		table.insert(mini, t.Minimap[i])
	end
	local holder = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(128, 128), ZIndex = 7, Parent = lobbyMap })
	Hud.DrawTrack(holder, mini, 128, 3, C.Accent)
	setZ(holder, 7)
end

function Menu.SetLobby(info)
	Menu.Lobby = info
	lobbyPanel.Visible = info ~= nil and gui.Enabled
	if not info then
		return
	end
	local ranked = info.Mode == "ranked"
	Util.Clear(lobbyMode, true)
	Kit.List(lobbyMode, Enum.FillDirection.Horizontal, 6)
	local chip = if ranked then Kit.Chip(lobbyMode, "RANKED", C.Purple) elseif info.Private then Kit.Chip(lobbyMode, "PRIVATE", C.Accent2) else Kit.Chip(lobbyMode, "QUICK RACE", C.Accent)
	setZ(lobbyMode, 7)
	chip.ZIndex = 7
	lobbyCountLabel.Text = if info.Searching or info.Waiting then "SEARCHING" elseif info.Found then "MATCH FOUND" else "STARTS IN"
	if info.Searching or info.Found then
		-- ranked queue shared by every server: real players only
		drawLobbyMap(nil)
		voteRow.Visible = false
		lobbyNames.Visible = true
		if info.Found then
			lobbyTitle.Text = "✅ Match found!"
			lobbyInfo.Text = string.format("%d racers  •  joining the race server…", info.Count or 0)
			lobbyNames.Text = "Hold tight - you'll vote for the circuit when everyone is in."
		else
			lobbyTitle.Text = "🔍 Searching for rivals…"
			lobbyInfo.Text = string.format("%d in the ranked queue  •  real players only", info.Queue or 1)
			lobbyNames.Text = "We match you with players near your rank. The longer you wait, the wider the search."
		end
	elseif ranked and info.Waiting then
		drawLobbyMap(nil)
		voteRow.Visible = false
		lobbyNames.Visible = true
		lobbyTitle.Text = "🔍 Waiting for a rival…"
		lobbyInfo.Text = string.format("%d/%d racers  •  real players only", info.Count, info.Max)
		lobbyNames.Text = "The vote starts as soon as another player joins ranked."
	elseif ranked and info.Candidates then
		drawLobbyMap(nil)
		lobbyTitle.Text = "Vote for the circuit!"
		lobbyInfo.Text = string.format("%d/%d racers  •  most votes wins", info.Count, info.Max)
		lobbyNames.Visible = false
		voteRow.Visible = true
		Util.Clear(voteRow, true)
		for i, id in info.Candidates do
			local c = Circuits.ById[id]
			local votes = (info.Votes and info.Votes[id]) or 0
			local mine = info.MyVote == id
			local b = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if mine then C.Purple else C.Panel3, Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = i, ZIndex = 7, Parent = voteRow })
			Kit.Corner(b, 10)
			Kit.Stroke(b, if mine then Color3.fromRGB(220, 200, 255) else C.Stroke, 1.5, if mine then 0 else 0.5)
			Kit.Label(b, c.Flag .. " " .. c.Name, 12, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 30), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 8 })
			Kit.Label(b, string.format("%d vote%s", votes, if votes == 1 then "" else "s"), 11, { Font = Kit.Fonts.Bold, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -4), Size = UDim2.new(1, -16, 0, 16), TextColor3 = if mine then C.White else C.SubText, ZIndex = 8 })
			Kit.Clickable(b, function()
				task.spawn(Util.Invoke, "VoteMap", id)
			end)
		end
	else
		drawLobbyMap(info.TrackId)
		local c = Circuits.ById[info.TrackId]
		lobbyTitle.Text = if c then (c.Flag .. "  " .. c.Name) else "Race"
		lobbyInfo.Text = string.format("%d laps  •  %d/%d racers", info.Laps or 0, info.Count, info.Max)
		lobbyNames.Visible = true
		voteRow.Visible = false
		lobbyNames.Text = "👥  " .. table.concat(info.Names or {}, ",  ")
	end
	startNowBtn.Visible = not ranked and info.HostId == State.Profile.userId
end

RunService.Heartbeat:Connect(function()
	local info = Menu.Lobby
	if info and lobbyPanel.Visible then
		if info.Found then
			lobbyCount.Text = "✓"
			lobbyCount.TextColor3 = C.Success
		elseif info.Searching or info.Waiting then
			-- time spent searching, m:ss
			local waited = math.max(0, math.floor(workspace:GetServerTimeNow() - (info.Since or info.Created or info.EndsAt)))
			lobbyCount.Text = string.format("%d:%02d", waited // 60, waited % 60)
			lobbyCount.TextColor3 = C.Purple
		else
			local left = math.max(0, math.ceil(info.EndsAt - workspace:GetServerTimeNow()))
			lobbyCount.Text = tostring(left)
			lobbyCount.TextColor3 = if left <= 5 then C.Danger else C.Accent
		end
	end
end)

Net.Event("LobbyUpdate").OnClientEvent:Connect(function(info)
	Menu.SetLobby(info)
end)

---------------------------------------------------------------------------
-- Daily reward
---------------------------------------------------------------------------
local dailyClose = nil
function Menu.ShowDaily()
	local p = State.Profile
	if not p or not p.daily or not p.daily.available or not gui.Enabled then
		return false
	end
	local rewards = Config.Economy.DailyRewards
	local day = ((p.daily.streak or 0) % #rewards) + 1
	local vip = State.HasPass("VIP")
	local box, _, close = Kit.ModalFrame("🎁 Daily Reward", 620)
	dailyClose = close
	Kit.Label(box, string.format("Day %d of your streak%s. Come back every day - day 7 is the big one!", day, if vip then "  (VIP: 2x coins)" else ""), 15, { LayoutOrder = 1, TextColor3 = C.SubText, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 12 })
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 96), LayoutOrder = 2, ZIndex = 12, Parent = box })
	Kit.List(row, Enum.FillDirection.Horizontal, 8)
	for d = 1, #rewards do
		local isToday = d == day
		local done = d < day
		local cell = Kit.new("Frame", { BackgroundColor3 = if isToday then C.Accent elseif done then C.Panel3 else C.Panel2, Size = UDim2.new(1 / #rewards, -7, 1, 0), LayoutOrder = d, ZIndex = 12, Parent = row })
		Kit.Corner(cell, 12)
		if isToday then
			Kit.Depth(cell, C.Accent)
			Kit.Stroke(cell, Color3.fromRGB(255, 235, 170), 2, 0)
		end
		local tc = if isToday then Color3.fromRGB(30, 20, 4) else C.Text
		Kit.Label(cell, "DAY " .. d, 11, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = tc, ZIndex = 13 })
		local coin = Kit.Coin(cell, if d == #rewards then 34 else 26, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 13 })
		setZ(coin, 14)
		coin.ZIndex = 13
		Kit.Label(cell, if done then "✓" else Kit.Comma(rewards[d] * (if vip then 2 else 1)), 13, { Font = Kit.Fonts.Title, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = tc, ZIndex = 13 })
	end
	local btns = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 3, ZIndex = 12, Parent = box })
	Kit.List(btns, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)
	Kit.Button(btns, "Later", "secondary", close, { LayoutOrder = 1, ZIndex = 13, Size = UDim2.fromOffset(120, 46) })
	Kit.Button(btns, "CLAIM!", "success", function()
		close()
		task.spawn(function()
			local res = Util.Invoke("ClaimDaily")
			if res and res.ok then
				Fx.Play("Purchase", 0.5)
				Kit.Toast(string.format("🎁 +%s coins!  Streak: %d day%s", Kit.Comma(res.coins), res.streak, if res.streak == 1 then "" else "s"), "success")
			elseif res and res.err then
				Kit.Toast(res.err, "warn")
			end
		end)
	end, { LayoutOrder = 2, ZIndex = 13, Size = UDim2.fromOffset(160, 46) })
end

---------------------------------------------------------------------------
-- Show / hide
---------------------------------------------------------------------------
local shownDaily = false
function Menu.Show(page, arg)
	gui.Enabled = true
	Showroom.Show()
	TopBar.Refresh()
	refreshHome()
	if page then
		Menu.Open(page, arg)
	else
		Menu.Back()
	end
	Menu.SetLobby(Menu.Lobby)
	if not shownDaily and not Menu.HoldDaily and State.Profile.daily and State.Profile.daily.available then
		shownDaily = true
		task.delay(1.2, function()
			if Menu.ShowDaily() == false then
				shownDaily = false -- went straight into a race; offer it next time the menu opens
			end
		end)
	end
end

function Menu.Hide()
	if dailyClose then
		pcall(dailyClose) -- never leave the daily popup over a race
		dailyClose = nil
	end
	if current then
		local old = Menu.Pages[current]
		old.Frame.Visible = false
		if old.OnHide then
			old.OnHide()
		end
		current = nil
	end
	gui.Enabled = false
	lobbyPanel.Visible = false
	Showroom.Hide()
	setCore(Enum.CoreGuiType.PlayerList, false)
end

-- set by the bootstrap
Menu.StartTimeTrial = function(_opts) end

return Menu
