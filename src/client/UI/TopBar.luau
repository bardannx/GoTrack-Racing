--!nonstrict
-- Status bar that lives inside the Roblox top bar (right side): challenges (with a badge
-- when a reward is ready), daily reward, coin boost, ranked badge, level + XP and coins.
-- Every pill is clickable.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local ChallengesPanel = require(script.Parent.ChallengesPanel)

local C = Kit.Colors
local TopBar = {}

local bar = nil
local refs: { [string]: any } = {}
local shownCoins = nil
local coinValue = Instance.new("NumberValue")

-- A clickable rounded box in the bar.
local function pill(parent, order: number, accent: Color3, onClick): TextButton
	local b = Kit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(14, 16, 27),
		BackgroundTransparency = 0.12,
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Round(b)
	local st = Kit.Stroke(b, accent, 1.5, 0.35)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), accent:Lerp(Color3.new(1, 1, 1), 0.3)),
		Rotation = 0,
		Parent = st,
	})
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 14), Parent = b })
	Kit.List(b, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	Kit.Clickable(b, onClick)
	return b
end

-- Two lines of text, small on top and bold below ("LEVEL" over "12").
local function stacked(
	parent,
	order: number,
	top: string,
	bottom: string,
	topColor: Color3?
): (Frame, TextLabel, TextLabel)
	local f = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.List(f, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local t = Kit.Label(f, top, 15, {
		Font = Kit.Fonts.Title,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		TextColor3 = topColor or C.Text,
		LayoutOrder = 1,
	})
	local b = Kit.Label(f, bottom, 11, {
		Font = Kit.Fonts.Bold,
		Size = UDim2.fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		TextColor3 = C.SubText,
		LayoutOrder = 2,
	})
	return f, t, b
end

-- menu: the MainMenu module (for navigation)
function TopBar.Build(root: Frame, menu)
	bar = Kit.new("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(900, 44),
		Parent = root,
	})
	Kit.List(bar, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	Kit.BindInset(function(top, _left, right)
		bar.Position = UDim2.new(1, -(right + 14), 0, math.max(top, 50) / 2 + 2)
	end)

	-- challenges
	local ch = pill(bar, 0, C.Accent2, function()
		ChallengesPanel.Open()
	end)
	Kit.IconTile(ch, "🎯", 34, C.Accent2, { LayoutOrder = 1 })
	refs.chLabel = Kit.Label(ch, "CHALLENGES", 14, {
		Font = Kit.Fonts.Title,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		TextColor3 = C.Accent2,
		LayoutOrder = 2,
	})
	local badge = Kit.new(
		"Frame",
		{ BackgroundColor3 = C.Red, Size = UDim2.fromOffset(22, 22), LayoutOrder = 3, Visible = false, Parent = ch }
	)
	Kit.Round(badge)
	refs.chCount = Kit.Label(
		badge,
		"1",
		13,
		{ Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }
	)
	refs.chBadge = badge
	refs.ch = ch

	-- daily reward
	local daily = pill(bar, 1, C.Success, function()
		menu.ShowDaily()
	end)
	Kit.IconTile(daily, "🎁", 34, C.Success, { LayoutOrder = 1 })
	Kit.Label(daily, "DAILY", 14, {
		Font = Kit.Fonts.Title,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		TextColor3 = C.Success,
		LayoutOrder = 2,
	})
	refs.daily = daily

	-- coin boost
	local boost = pill(bar, 2, C.Warn, function()
		menu.Open("shop", "coins")
	end)
	Kit.IconTile(boost, "⚡", 34, C.Warn, { LayoutOrder = 1 })
	local _, boostTop, boostBottom = stacked(boost, 2, "2X COINS", "", C.Warn)
	refs.boost, refs.boostTop, refs.boostBottom = boost, boostTop, boostBottom

	-- ranked
	local rank = pill(bar, 3, C.Purple, function()
		menu.Open("ranked")
	end)
	local badgeHolder = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromOffset(36, 36), LayoutOrder = 1, Parent = rank }
	)
	local _, rankTop, rankBottom = stacked(rank, 2, "BRONZE III", "100 RP")
	refs.rank, refs.badgeHolder, refs.rankTop, refs.rankBottom = rank, badgeHolder, rankTop, rankBottom

	-- level
	local level = pill(bar, 4, C.Accent2, function()
		menu.Open("leaderboards", "level")
	end)
	local lvlCircle = Kit.new(
		"Frame",
		{ BackgroundColor3 = C.Accent2, Size = UDim2.fromOffset(34, 34), LayoutOrder = 1, Parent = level }
	)
	Kit.Round(lvlCircle)
	Kit.Gradient(lvlCircle, Color3.fromRGB(120, 220, 255), Color3.fromRGB(20, 110, 220), 45)
	Kit.Stroke(lvlCircle, Color3.fromRGB(190, 240, 255), 1.5, 0.2)
	local lvlNum = Kit.Label(
		lvlCircle,
		"1",
		16,
		{ Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }
	)
	local lvlInfo = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromOffset(104, 36), LayoutOrder = 2, Parent = level }
	)
	Kit.Label(lvlInfo, "LEVEL", 11, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 14), TextColor3 = C.SubText })
	local xpText = Kit.Label(lvlInfo, "0 / 150", 11, {
		Font = Kit.Fonts.Bold,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.SubText,
	})
	local _, xpFill =
		Kit.Bar(lvlInfo, 0, C.Accent2, { Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, 0, 0, 8) })
	refs.lvlNum, refs.xpText, refs.xpFill = lvlNum, xpText, xpFill

	-- coins
	local coins = pill(bar, 5, C.Accent, function()
		menu.Open("shop", "coins")
	end)
	Kit.Coin(coins, 32, { LayoutOrder = 1 })
	local coinLabel = Kit.Label(coins, "0", 18, {
		Font = Kit.Fonts.Title,
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
	})
	local plus = Kit.new(
		"Frame",
		{ BackgroundColor3 = C.Success, Size = UDim2.fromOffset(26, 26), LayoutOrder = 3, Parent = coins }
	)
	Kit.Round(plus)
	Kit.Depth(plus, C.Success)
	Kit.Label(plus, "+", 20, {
		Font = Kit.Fonts.Title,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(8, 40, 18),
	})
	refs.coins, refs.coinLabel = coins, coinLabel

	coinValue:GetPropertyChangedSignal("Value"):Connect(function()
		coinLabel.Text = Kit.Comma(coinValue.Value)
	end)
	State.Changed:Connect(TopBar.Refresh)
	TopBar.Refresh()
end

local lastBadge = nil
-- Updates every pill from the profile (the coin count animates to its new value).
function TopBar.Refresh()
	local p = State.Profile
	if not p or not bar then
		return
	end
	-- coins (animated count)
	if shownCoins == nil then
		shownCoins = p.coins
		coinValue.Value = p.coins
		refs.coinLabel.Text = Kit.Comma(p.coins)
	elseif p.coins ~= shownCoins then
		local up = p.coins > shownCoins
		shownCoins = p.coins
		Kit.Tween(coinValue, 0.8, { Value = p.coins }, Enum.EasingStyle.Quart)
		local sc = refs.coins:FindFirstChildOfClass("UIScale")
		if sc and up then
			sc.Scale = 1.12
			Kit.Tween(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	-- level
	refs.lvlNum.Text = tostring(p.level)
	local need = math.max(p.xpNeeded or 1, 1)
	refs.xpText.Text = string.format("%s / %s", Kit.Comma(p.xp), Kit.Comma(need))
	Kit.Tween(refs.xpFill, 0.5, { Size = UDim2.fromScale(math.clamp(p.xp / need, 0, 1), 1) })
	-- rank
	local rp = p.rp or 0
	local tier, div = Config.DivisionFor(rp, p.champion)
	local key = tier.Name .. div
	if key ~= lastBadge then
		lastBadge = key
		for _, c in refs.badgeHolder:GetChildren() do
			c:Destroy()
		end
		Kit.TierBadge(refs.badgeHolder, tier, 36, div)
	end
	refs.rankTop.Text = string.upper(tier.Name .. (if div ~= "" then " " .. div else ""))
	refs.rankTop.TextColor3 = tier.Color:Lerp(C.White, 0.25)
	refs.rankBottom.Text = Kit.Comma(rp) .. " RP"
	-- challenges: badge with the number of rewards ready; the label hides on small screens
	local ready = ChallengesPanel.Claimable()
	refs.chBadge.Visible = ready > 0
	refs.chCount.Text = tostring(ready)
	refs.chLabel.Visible = not Kit.Compact()
	refs.ch.Visible = p.challenges ~= nil
	-- daily + boost
	refs.daily.Visible = p.daily ~= nil and p.daily.available == true
	local boostLeft = (p.boostUntil or 0) - (p.serverTime or os.time())
	refs.boost.Visible = boostLeft > 0
	if boostLeft > 0 then
		refs.boostBottom.Text = string.format("%d min left", math.ceil(boostLeft / 60))
	end
end

-- Shows or hides the bar.
function TopBar.SetVisible(on: boolean)
	if bar then
		bar.Visible = on
	end
end

return TopBar
