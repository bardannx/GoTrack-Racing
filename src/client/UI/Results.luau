--!nonstrict
-- Race results: podium with avatars, your result + rewards, ranked RP change with a
-- promotion / demotion animation, and the full classification.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Medals = require(Shared.Medals)
local Config = require(Shared.Config)
local Circuits = require(Shared.Circuits)
local Cosmetics = require(Shared.Cosmetics)

local Kit = require(script.Parent.Kit)
local Util = require(script.Parent.Parent.Util)
local Fx = require(script.Parent.Parent.Fx)
local State = require(script.Parent.Parent.State)

local C = Kit.Colors
local Results = {}

local gui, root = Kit.Screen("GoTrackResults", 20)
gui.Enabled = false
-- everything is built inside `content`: clearing `root` itself would destroy the screen's
-- UIScale and blow the whole page up to 1:1 pixels (it ran off phone screens)
local content =
	Kit.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })

local MEDAL = { C.Gold, C.Silver, C.Bronze }

-- A racer's main paint colour, used to tint their row.
local function colorOf(car)
	local prim = car and Cosmetics.ById[car.Primary or ""]
	return if prim and prim.Color then prim.Color else C.Accent
end

-- Time column: the winner's race time, then gaps (+1.234), laps down (+1 LAP) or DNF.
local function timeText(r, winner)
	if r.DNF then
		return "DNF"
	end
	if r.P == 1 then
		return Medals.FormatTime((r.Time or 0) * 1000)
	end
	if r.Lapped and r.Lapped >= 1 then
		return "+" .. r.Lapped .. " LAP" .. (if r.Lapped > 1 then "S" else "")
	end
	if r.Time and winner and winner.Time then
		return string.format("+%.3f", r.Time - winner.Time)
	end
	if r.Gap then
		return string.format("+%.3f", r.Gap)
	end
	return "--"
end

-- big animated banner for a rank change
local function rankChangeBanner(parent, oldRp: number, newRp: number)
	local oldName, newName = Config.RankName(oldRp), Config.RankName(newRp)
	if oldName == newName then
		return
	end
	local up = newRp > oldRp
	local tier, div = Config.DivisionFor(newRp)
	local f = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = parent,
	})
	local badge = Kit.TierBadge(
		f,
		tier,
		if Kit.Compact() then 140 else 200,
		div,
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), ZIndex = 31 }
	)
	for _, d in badge:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 32
		end
	end
	local sc = Kit.new("UIScale", { Scale = 0.2, Parent = badge })
	Kit.Tween(sc, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
	Kit.Label(f, if up then "PROMOTED!" else "DEMOTED", 46, {
		Font = Kit.Fonts.Title,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(800, 56),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if up then C.Success else C.Danger,
		ZIndex = 33,
	})
	Kit.Label(f, string.upper(oldName) .. "   →   " .. string.upper(newName), 22, {
		Font = Kit.Fonts.Title,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromOffset(800, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = tier.Color:Lerp(C.White, 0.3),
		ZIndex = 33,
	})
	if up then
		Fx.Play("Finish", 0.6, 1.1)
	end
	local b = Kit.Button(f, "CONTINUE", "primary", function()
		f:Destroy()
	end, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.fromOffset(220, 50),
		ZIndex = 33,
	})
	b.ZIndex = 33
end

-- payload = { Results, You, Mode, TrackId, Fastest }, buttons = { {text, style, fn} }
function Results.Show(payload, yourRid: number, buttons)
	Util.Clear(content)
	gui.Enabled = true
	local list = payload.Results or {}
	local you = payload.You or {}
	local circuit = Circuits.ById[payload.TrackId]
	local dim =
		Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = content })
	Kit.Gradient(dim, Color3.fromRGB(26, 30, 56), Color3.fromRGB(6, 7, 12), 90)
	local stripe =
		Kit.new("Frame", { BackgroundColor3 = C.Red, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 6), Parent = dim })
	Kit.Gradient(stripe, C.Red, C.Accent, 0)

	-- responsive layout: everything is sized from the real screen (phone, tablet or PC)
	local rs = Kit.RootSize()
	local W, H = rs.X, rs.Y
	local compact = Kit.Compact()
	local top = Kit.Inset()
	local margin = if compact then 20 else 40
	local titleY = top + (if compact then 0 else 4)
	local titleSize = if compact then 32 else 46
	local title = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = "RACE RESULTS",
		FontFace = Kit.Faces.Logo,
		TextSize = titleSize,
		TextColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, titleY),
		Size = UDim2.fromOffset(900, titleSize + 6),
		Parent = dim,
	})
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 226, 90), Color3.fromRGB(255, 120, 40)),
		Rotation = 90,
		Parent = title,
	})
	Kit.new("UIStroke", { Color = Color3.fromRGB(34, 12, 4), Thickness = 2, Parent = title })
	local subY = titleY + titleSize + (if compact then 6 else 10)
	-- circuit pill under the title
	local pill = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(14, 16, 30),
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, subY),
		Size = UDim2.fromOffset(0, if compact then 26 else 30),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = dim,
	})
	Kit.Round(pill)
	Kit.Padding(pill, 16, 0)
	Kit.Stroke(pill, if payload.Mode == "ranked" then C.Purple else C.Accent, 1.2, 0.5)
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = (if circuit then circuit.Flag .. "  " .. circuit.Name else "")
			.. (if payload.Mode == "ranked" then "   •   RANKED" else "   •   QUICK RACE"),
		FontFace = Kit.Faces.Heavy,
		TextSize = if compact then 13 else 15,
		TextColor3 = C.Text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, if compact then 26 else 30),
		Parent = pill,
	})

	local btnH = if compact then 46 else 54
	local btnBottom = if compact then 10 else 24
	local y0 = subY + (if compact then 36 else 48)
	local availH = H - y0 - btnH - btnBottom - 12

	-- left column: podium + your result, scaled down to fit short / narrow screens
	local cardH = 104 + (if you.RpDelta then 52 else 0) + (if you.LeveledUp then 26 else 0)
	local natural = 336 + cardH
	local leftScale = math.clamp(math.min(availH / natural, (W * 0.47 - margin) / 500), 0.45, 1)
	local leftCol = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(margin, y0),
		Size = UDim2.fromOffset(500, natural),
		Parent = dim,
	})
	Kit.new("UIScale", { Scale = leftScale, Parent = leftCol })

	-- podium
	local podium = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(500, 320), Parent = leftCol })
	local order = { 2, 1, 3 }
	local heights = { [1] = 150, [2] = 112, [3] = 86 }
	for col, place in order do
		local r = list[place]
		if r then
			local x = (col - 1) * 166
			local h = heights[place]
			local step = Kit.new("Frame", {
				BackgroundColor3 = MEDAL[place],
				Position = UDim2.new(0, x + 8, 1, -h),
				Size = UDim2.new(0, 150, 0, h),
				Parent = podium,
			})
			Kit.Corner(step, 12)
			Kit.Depth(step, MEDAL[place])
			Kit.Label(step, tostring(place), 58, {
				Font = Kit.Fonts.Title,
				Size = UDim2.new(1, 0, 0, 64),
				Position = UDim2.fromOffset(0, 8),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = MEDAL[place]:Lerp(Color3.new(0, 0, 0), 0.65),
			})
			local av = if place == 1 then 78 else 64
			local halo = nil
			if place == 1 then
				-- winner: pulsing golden halo behind the avatar
				halo = Kit.new("Frame", {
					BackgroundColor3 = C.Gold,
					BackgroundTransparency = 0.75,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, x + 83, 1, -h - 58 - av / 2),
					Size = UDim2.fromOffset(av + 26, av + 26),
					Parent = podium,
				})
				Kit.Round(halo)
			end
			Kit.Avatar(
				podium,
				if r.IsAI then 0 else r.UserId,
				av,
				r.Name,
				MEDAL[place],
				{ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, x + 83, 1, -h - 58) }
			)
			if place == 1 then
				-- the winner's crown, gently bobbing on top of the avatar
				local crownY = -h - 58 - av + 16
				local crown = Kit.Label(podium, "👑", 46, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0, x + 83, 1, crownY),
					Size = UDim2.fromOffset(72, 54),
					TextXAlignment = Enum.TextXAlignment.Center,
					Rotation = -15,
					ZIndex = 4,
				})
				Kit.Loop(crown, 0.55, { Position = UDim2.new(0, x + 83, 1, crownY - 6) })
				Kit.Loop(crown, 0.9, { Rotation = -5 })
				if halo then
					Kit.Loop(halo, 1.1, { Size = UDim2.fromOffset(av + 40, av + 40), BackgroundTransparency = 0.9 })
				end
			end
			local bar = Kit.new("Frame", {
				BackgroundColor3 = colorOf(r.Car),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0, x + 83, 1, -h - 52),
				Size = UDim2.fromOffset(40, 4),
				Parent = podium,
			})
			Kit.Round(bar)
			Kit.Label(podium, r.Name, 15, {
				Font = Kit.Fonts.Title,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, x, 1, -h - 26),
				Size = UDim2.fromOffset(166, 20),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local tl = Kit.Label(podium, timeText(r, list[1]), 13, {
				Font = Kit.Fonts.Mono,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, x, 1, -h - 6),
				Size = UDim2.fromOffset(166, 18),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = C.SubText,
			})
			tl.RichText = false
		end
	end

	-- your result card: big position badge + rewards
	local finished = you.Finished ~= false
	local myPos = you.Pos or 0
	local podiumFinish = finished and myPos >= 1 and myPos <= 3
	local badgeColor = if podiumFinish then MEDAL[myPos] elseif finished then Color3.fromRGB(70, 90, 160) else C.Danger
	local yourCard = Kit.Panel(leftCol, { Position = UDim2.fromOffset(0, 336), Size = UDim2.fromOffset(500, cardH) })
	local badge = Kit.new("Frame", {
		BackgroundColor3 = badgeColor,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(0, 96, 1, -28),
		Parent = yourCard,
	})
	Kit.Corner(badge, 14)
	Kit.Gradient(badge, badgeColor:Lerp(Color3.new(1, 1, 1), 0.2), badgeColor:Lerp(Color3.new(0, 0, 0), 0.25), 90)
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = if finished then ("P" .. tostring(myPos)) else "DNF",
		FontFace = Kit.Faces.Logo,
		TextSize = if finished and myPos < 10 then 44 else 36,
		TextColor3 = if podiumFinish then badgeColor:Lerp(Color3.new(0, 0, 0), 0.75) else C.White,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
	})
	local info = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(126, 12),
		Size = UDim2.new(1, -140, 1, -24),
		Parent = yourCard,
	})
	Kit.List(info, Enum.FillDirection.Vertical, 8)
	local function ordinal(n)
		local k = n % 100
		if k >= 11 and k <= 13 then
			return n .. "TH"
		end
		return n .. (({ "ST", "ND", "RD" })[n % 10] or "TH")
	end
	local headline = if not finished
		then "DID NOT FINISH"
		elseif myPos == 1 then "🏆 YOU WON!"
		elseif podiumFinish then "PODIUM - " .. ordinal(myPos) .. "!"
		else "YOU FINISHED " .. ordinal(myPos)
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = headline,
		FontFace = Kit.Faces.Sub,
		TextSize = 26,
		TextColor3 = if podiumFinish then MEDAL[myPos] else C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Parent = info,
	})
	local rewards =
		Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 2, Parent = info })
	Kit.List(rewards, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	if you.Coins then
		local c = Kit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(10, 12, 20),
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
			Parent = rewards,
		})
		Kit.Round(c)
		Kit.Padding(c, 10, 0)
		Kit.Stroke(c, C.Gold, 1, 0.6)
		Kit.List(c, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		Kit.Coin(c, 22, { LayoutOrder = 1 })
		Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = "+" .. Kit.Comma(you.Coins),
			FontFace = Kit.Faces.Heavy,
			TextSize = 18,
			TextColor3 = C.Gold,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24),
			LayoutOrder = 2,
			Parent = c,
		})
	end
	if you.XP then
		Kit.Chip(rewards, "+" .. you.XP .. " XP", C.Accent2, { LayoutOrder = 2 })
	end
	if you.Featured then
		Kit.Chip(rewards, "⭐ FEATURED ×" .. Config.Economy.FeaturedCoinMultiplier, C.Gold, { LayoutOrder = 3 })
	end
	if you.Fastest then
		Kit.Chip(rewards, "⚡ FASTEST LAP", Color3.fromRGB(190, 90, 255), { LayoutOrder = 3 })
	end
	if you.RpDelta then
		local champ = State.Profile and State.Profile.champion
		local tier, div = Config.DivisionFor(you.Rp or 0, champ)
		local row = Kit.new(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, Parent = info }
		)
		Kit.TierBadge(row, tier, 42, div)
		local sign = if you.RpDelta >= 0 then "+" else ""
		Kit.Label(row, string.format("%s%d RP", sign, you.RpDelta), 20, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(52, 0),
			Size = UDim2.new(1, -52, 0, 24),
			TextColor3 = if you.RpDelta >= 0 then C.Success else C.Danger,
		})
		Kit.Label(row, string.format("%s  •  %d RP", Config.RankName(you.Rp or 0, champ), you.Rp or 0), 13, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(52, 24),
			Size = UDim2.new(1, -52, 0, 18),
			TextColor3 = C.SubText,
		})
	end
	if you.LeveledUp then
		Kit.Label(
			info,
			"🎉 LEVEL UP!  You're now level " .. tostring(you.Level),
			16,
			{ Font = Kit.Fonts.Title, LayoutOrder = 4, TextColor3 = C.Accent2 }
		)
	end

	-- classification table: fills the rest of the width, rows scroll if they don't fit
	local gap = if compact then 16 else 32
	local tableW = math.min(720, W - margin * 2 - 500 * leftScale - gap)
	local showBest = tableW >= 470
	-- centre both columns as one block (no big empty gap on wide screens)
	local blockW = 500 * leftScale + gap + tableW
	local x0 = math.max(margin, (W - blockW) / 2)
	leftCol.Position = UDim2.fromOffset(x0, y0)
	local rowsArea = availH - (if compact then 16 else 24) - 30
	local rowH = math.clamp(math.floor(rowsArea / math.max(1, #list)) - 4, if compact then 32 else 34, 44)
	local tableBox = Kit.Panel(
		dim,
		{ Position = UDim2.fromOffset(x0 + 500 * leftScale + gap, y0), Size = UDim2.fromOffset(tableW, availH) }
	)
	Kit.Padding(tableBox, if compact then 12 else 16, if compact then 8 else 12)
	local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), Parent = tableBox })
	local timeRight = if showBest then -120 else -12
	Kit.Label(header, "POS", 11, { Font = Kit.Fonts.Title, Size = UDim2.fromOffset(40, 22), TextColor3 = C.SubText })
	Kit.Label(header, "DRIVER", 11, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromOffset(92, 0),
		Size = UDim2.fromOffset(200, 22),
		TextColor3 = C.SubText,
	})
	Kit.Label(header, "TIME / GAP", 11, {
		Font = Kit.Fonts.Title,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, timeRight, 0, 0),
		Size = UDim2.fromOffset(110, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.SubText,
	})
	if showBest then
		Kit.Label(header, "BEST LAP", 11, {
			Font = Kit.Fonts.Title,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.fromOffset(100, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.SubText,
		})
	end
	local rowsHolder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 1, -26),
		Parent = tableBox,
	})
	local rows = Kit.ScrollList(rowsHolder, nil, 4)
	local myIndex = nil
	for i, r in list do
		if r.Rid == yourRid then
			myIndex = i
		end
		local me = r.Rid == yourRid
		local row = Kit.Card(
			rows,
			{ Size = UDim2.new(1, -8, 0, rowH), LayoutOrder = i },
			if me then Color3.fromRGB(72, 58, 22) else C.Panel2
		)
		local pad = (rowH - 28) / 2
		local pbox = Kit.new("Frame", {
			BackgroundColor3 = if r.P <= 3 then MEDAL[r.P] else Color3.fromRGB(240, 240, 245),
			Position = UDim2.fromOffset(8, pad),
			Size = UDim2.fromOffset(30, 28),
			Parent = row,
		})
		Kit.Corner(pbox, 6)
		Kit.Label(pbox, tostring(r.P), 15, {
			Font = Kit.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(20, 20, 26),
		})
		Kit.Avatar(
			row,
			if r.IsAI then 0 else r.UserId,
			30,
			r.Name,
			colorOf(r.Car),
			{ Position = UDim2.fromOffset(48, (rowH - 30) / 2) }
		)
		Kit.Label(row, (if r.P == 1 and not r.DNF then "👑 " else "") .. r.Name, 15, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(92, 0),
			Size = UDim2.new(1, (if showBest then -330 else -220), 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local tt = Kit.Label(row, timeText(r, list[1]), 14, {
			Font = Kit.Fonts.Mono,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, timeRight, 0, 0),
			Size = UDim2.fromOffset(110, rowH),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		tt.RichText = false
		if showBest then
			local fastest = payload.Fastest and payload.Fastest.Rid == r.Rid
			local bl = Kit.Label(row, if r.Best then string.format("%.3f", r.Best) else "--", 14, {
				Font = Kit.Fonts.Mono,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.fromOffset(100, rowH),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = if fastest then Color3.fromRGB(190, 90, 255) else C.SubText,
			})
			bl.RichText = false
		end
	end

	-- if your row is below the fold, scroll so you can see yourself
	if myIndex then
		task.defer(function()
			local rowTop = (myIndex - 1) * (rowH + 4)
			local view = rows.AbsoluteWindowSize.Y / math.max(0.01, Kit.Scale())
			if rowTop + rowH > view then
				rows.CanvasPosition = Vector2.new(0, rowTop + rowH - view + 8)
			end
		end)
	end

	-- buttons: always on screen, pinned to the bottom
	local n = math.max(1, #buttons)
	local btnW = math.min(if compact then 200 else 230, (W - margin * 2 - (n - 1) * 14) / n)
	local btnRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -btnBottom),
		Size = UDim2.new(1, -margin * 2, 0, btnH),
		ZIndex = 5,
		Parent = dim,
	})
	Kit.List(btnRow, Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center)
	for i, b in buttons do
		Kit.Button(btnRow, b[1], b[2], function()
			Results.Hide()
			b[3]()
		end, { Size = UDim2.fromOffset(btnW, btnH), TextSize = if compact then 16 else 19, LayoutOrder = i })
	end
	if (you.Pos or 99) <= 3 and finished then
		Fx.Play("Finish", 0.5)
	end
	if you.RpDelta and you.OldRp then
		task.delay(0.8, function()
			if gui.Enabled then
				rankChangeBanner(dim, you.OldRp, you.Rp or 0)
			end
		end)
	end
end

-- Closes the results screen.
function Results.Hide()
	gui.Enabled = false
	Util.Clear(content)
end

return Results
