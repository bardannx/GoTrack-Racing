--!nonstrict
-- Shop: Featured (Ultimate hero, new-player deal, popular passes, best coin packs), Passes
-- (perks), Car Packs (with a live 3D preview of each pack's car) and Coins & Boosts.
-- Live Robux prices from the dashboard when IDs are set. Nothing sold here changes speed.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Monetization = require(Shared.Monetization)
local Cosmetics = require(Shared.Cosmetics)
local CarBuilder = require(Shared.CarBuilder)

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local Util = require(script.Parent.Parent.Util)

local C = Kit.Colors
local Shop = {}
Shop.Camera = "page"

local content: Frame
local selectTab: (string) -> ()
local currentTab = "featured"

-- what each tab shows
local PERK_PASSES = { "VIP", "DoubleCoins", "FXPack", "ProRacer", "PrivateRaces", "StarterPack" }
local CAR_PACKS = {
	{ key = "LegendaryCars", cars = { "nova", "viper", "aurora" } },
	{ key = "PremiumTeam", cars = { "stealth", "vortex", "apex" } },
	{ key = "NeonCollection", cars = { "neonracer" } },
	{ key = "HeritageCollection", cars = { "retro70", "retro90" } },
}

local RIBBONS = {
	Ultimate = { "BEST VALUE", C.Success },
	VIP = { "MOST POPULAR", C.Red },
	DoubleCoins = { "POPULAR", C.Red },
	FXPack = { "NEW", C.Accent2 },
	ProRacer = { "NEW", C.Accent2 },
	StarterPack = { "NEW PLAYER DEAL", C.Success },
	LegendaryCars = { "HOT", Color3.fromRGB(255, 120, 30) },
}

local BASE_RATE = 500 / 49 -- coins per Robux of the smallest pack

-- A buy button showing the Robux icon and price.
local function priceButton(parent, robux: number, style: string, onClick, props)
	local b = Kit.Button(parent, "", style, onClick, props)
	local _, label = Kit.RobuxPrice(
		b,
		robux,
		props and props.TextSize or 18,
		if style == "primary" then Color3.fromRGB(30, 20, 4) else C.White,
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }
	)
	return b, label
end

-- The green OWNED tag that replaces the buy button.
local function ownedChip(parent, props)
	local f = Kit.new("Frame", { BackgroundColor3 = C.Success, BackgroundTransparency = 0.75, Parent = parent })
	Kit.Corner(f, 12)
	Kit.Stroke(f, C.Success, 1.5, 0.2)
	Kit.Label(f, "✓  OWNED", 16, {
		Font = Kit.Fonts.Title,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Success,
	})
	Kit.Apply(f, props)
	return f
end

-- Swaps the price on `label` for the live Roblox price once it has loaded.
local function livePassPrice(pass, label)
	if pass.Id ~= 0 then
		task.spawn(function()
			local p = State.PassPrice(pass.Key)
			if label.Parent then
				label.Text = Kit.Comma(p)
			end
		end)
	end
end

-- A vertical scrolling area for a shop tab.
local function scroller(parent)
	local s = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Stroke,
		Parent = parent,
	})
	Kit.List(s, Enum.FillDirection.Vertical, 14)
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 16),
		Parent = s,
	})
	return s
end

-- 3D preview of a chassis in its factory colours (car packs)
local function carPreview(parent, bodyId: string, props)
	local vp = Kit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.5, -1, -0.3),
		Parent = parent,
	})
	Kit.Apply(vp, props)
	local ok = pcall(function()
		local car = table.clone(Cosmetics.DefaultCar)
		car.Body = bodyId
		for k, v in Cosmetics.BodyLivery[bodyId] or {} do
			car[k] = v
		end
		local parts = CarBuilder.Build(car, { Preview = true, UserId = State.Profile and State.Profile.userId })
		parts.Model:PivotTo(CFrame.new(0, 0, 0))
		parts.Model.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 28
		cam.CFrame = CFrame.lookAt(Vector3.new(19, 7, -20), Vector3.new(0, -0.8, 0.6))
		cam.Parent = vp
		vp.CurrentCamera = cam
	end)
	if not ok then
		vp:Destroy()
	end
	return vp
end

-- Hero card for the Ultimate bundle
local function hero(parent, order)
	local pass = Monetization.PassByKey.Ultimate
	local owned = State.HasPass("Ultimate")
	local card = Kit.new(
		"Frame",
		{ BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, 210), LayoutOrder = order, Parent = parent }
	)
	Kit.Corner(card, 18)
	Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 90, 255)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(90, 40, 190)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 20, 90)),
		}),
		Rotation = 20,
		Parent = card,
	})
	Kit.Stroke(card, Color3.fromRGB(220, 190, 255), 2, 0.3)
	local total = Monetization.TotalPassRobux() - pass.Price
	Kit.Ribbon(
		card,
		string.format("BEST VALUE  •  SAVE %s R$", Kit.Comma(math.max(0, total - pass.Price))),
		C.Success,
		Color3.fromRGB(6, 34, 16)
	)
	local icon = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.7,
		Position = UDim2.fromOffset(22, 26),
		Size = UDim2.fromOffset(156, 156),
		Parent = card,
	})
	Kit.Corner(icon, 28)
	Kit.Label(icon, pass.Icon, 90, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Label(
		card,
		"ULTIMATE BUNDLE",
		32,
		{ Font = Kit.Fonts.Title, Position = UDim2.fromOffset(198, 24), Size = UDim2.new(1, -420, 0, 38) }
	)
	Kit.Label(card, pass.Description, 15, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(198, 62),
		Size = UDim2.new(1, -420, 0, 20),
		TextColor3 = Color3.fromRGB(230, 215, 255),
	})
	local perks = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(198, 92),
		Size = UDim2.new(1, -420, 0, 100),
		Parent = card,
	})
	Kit.List(perks, Enum.FillDirection.Vertical, 4)
	for i, perk in pass.Perks do
		Kit.Label(perks, "✓  " .. perk, 14, {
			Font = Kit.Fonts.Bold,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = i,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	if owned then
		ownedChip(
			card,
			{ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -22, 1, -22), Size = UDim2.fromOffset(200, 56) }
		)
	else
		local _, label = priceButton(card, pass.Price, "primary", function()
			State.PromptPass("Ultimate")
		end, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -22, 1, -22),
			Size = UDim2.fromOffset(200, 56),
			TextSize = 24,
		})
		livePassPrice(pass, label)
		local was = Kit.Label(card, "Separately: " .. Kit.Comma(total) .. " R$", 13, {
			Font = Kit.Fonts.Bold,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -22, 1, -84),
			Size = UDim2.fromOffset(200, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(220, 200, 255),
		})
		was.RichText = false
	end
	return card
end

-- slim banner for the 99 R$ Starter Pack (only until it's owned)
local function starterBanner(parent, order)
	local pass = Monetization.PassByKey.StarterPack
	if not pass or State.HasPass("StarterPack") then
		return
	end
	local card = Kit.new(
		"Frame",
		{ BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, 84), LayoutOrder = order, Parent = parent }
	)
	Kit.Corner(card, 16)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(40, 150, 80), Color3.fromRGB(16, 50, 34)),
		Rotation = 0,
		Parent = card,
	})
	Kit.Stroke(card, Color3.fromRGB(120, 255, 170), 1.5, 0.3)
	Kit.IconTile(card, pass.Icon, 56, pass.Color, { Position = UDim2.fromOffset(14, 14) })
	Kit.Label(card, "NEW PLAYER DEAL  •  " .. string.upper(pass.Name), 18, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromOffset(84, 14),
		Size = UDim2.new(1, -300, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Kit.Label(card, table.concat(pass.Perks, "  •  "), 13, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(84, 42),
		Size = UDim2.new(1, -300, 0, 28),
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(200, 255, 220),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local _, label = priceButton(card, pass.Price, "primary", function()
		State.PromptPass("StarterPack")
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(180, 50),
		TextSize = 20,
	})
	livePassPrice(pass, label)
end

-- A game pass card: icon, name, perks and the buy button (or OWNED).
local function passCard(parent, pass, order: number)
	local owned = State.HasPass(pass.Key)
	local card = Kit.Card(parent, { LayoutOrder = order }, Color3.new(1, 1, 1))
	Kit.new(
		"UIGradient",
		{ Color = ColorSequence.new(pass.Color:Lerp(C.Panel2, 0.72), C.Panel2), Rotation = 90, Parent = card }
	)
	local st = card:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = pass.Color
		st.Transparency = if owned then 0.7 else 0.35
		st.Thickness = 1.5
	end
	local rib = RIBBONS[pass.Key]
	if rib and not owned then
		Kit.Ribbon(card, rib[1], rib[2])
	end
	Kit.IconTile(card, pass.Icon, 58, pass.Color, { Position = UDim2.fromOffset(14, 14) })
	Kit.Label(card, pass.Name, 17, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromOffset(84, 16),
		Size = UDim2.new(1, -96, 0, 22),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Kit.Label(card, pass.Description, 12, {
		Position = UDim2.fromOffset(84, 38),
		Size = UDim2.new(1, -96, 0, 34),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.SubText,
	})
	local perks = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 82),
		Size = UDim2.new(1, -32, 0, 100),
		Parent = card,
	})
	Kit.List(perks, Enum.FillDirection.Vertical, 2)
	for i = 1, math.min(5, #pass.Perks) do
		Kit.Label(perks, "<font color='#3AD87C'>✓</font>  " .. pass.Perks[i], 12, {
			Font = Kit.Fonts.Bold,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = i,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	if owned then
		ownedChip(
			card,
			{ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -28, 0, 42) }
		)
	else
		local _, label = priceButton(card, pass.Price, "primary", function()
			State.PromptPass(pass.Key)
		end, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -28, 0, 42),
			TextSize = 17,
		})
		livePassPrice(pass, label)
	end
	return card
end

-- car pack: a 3D preview of the pack's first chassis, the car names, perks, price
local function carPackCard(parent, packDef, order: number)
	local pass = Monetization.PassByKey[packDef.key]
	local owned = State.HasPass(pass.Key)
	local card = Kit.Card(parent, { LayoutOrder = order }, Color3.new(1, 1, 1))
	Kit.new(
		"UIGradient",
		{ Color = ColorSequence.new(pass.Color:Lerp(C.Panel2, 0.6), C.Panel2), Rotation = 90, Parent = card }
	)
	local st = card:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = pass.Color
		st.Transparency = if owned then 0.7 else 0.25
		st.Thickness = 1.5
	end
	local rib = RIBBONS[pass.Key]
	if rib and not owned then
		Kit.Ribbon(card, rib[1], rib[2])
	end
	carPreview(card, packDef.cars[1], { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 150) })
	local names = {}
	for _, id in packDef.cars do
		local it = Cosmetics.ById[id]
		table.insert(names, if it then it.Name else id)
	end
	Kit.Label(card, pass.Icon .. "  " .. pass.Name, 18, {
		Font = Kit.Fonts.Title,
		Position = UDim2.fromOffset(16, 160),
		Size = UDim2.new(1, -32, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Kit.Label(card, "🏎️  " .. table.concat(names, "  •  "), 13, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(16, 186),
		Size = UDim2.new(1, -32, 0, 18),
		TextColor3 = pass.Color:Lerp(C.White, 0.4),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local perks = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 210),
		Size = UDim2.new(1, -32, 0, 60),
		Parent = card,
	})
	Kit.List(perks, Enum.FillDirection.Vertical, 2)
	for i = 2, math.min(4, #pass.Perks) do
		Kit.Label(perks, "<font color='#3AD87C'>✓</font>  " .. pass.Perks[i], 12, {
			Font = Kit.Fonts.Bold,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = i,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	if owned then
		ownedChip(
			card,
			{ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -28, 0, 42) }
		)
	else
		local _, label = priceButton(card, pass.Price, "primary", function()
			State.PromptPass(pass.Key)
		end, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -28, 0, 42),
			TextSize = 17,
		})
		livePassPrice(pass, label)
	end
	return card
end

-- A little stack of `n` coins as the picture on a coin pack.
local function coinPile(parent, n: number, props)
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 70), Parent = parent })
	Kit.Apply(f, props)
	local count = math.clamp(n, 1, 7)
	for k = 1, count do
		local row = (k - 1) // 3
		local col = (k - 1) % 3
		local x = 50 + (col - 1) * 20 + row * 10 - 16
		local y = 38 - row * 16
		Kit.Coin(f, 32, { Position = UDim2.fromOffset(x, y), ZIndex = 2 + row })
	end
	return f
end

-- A coin pack or Coin Boost card.
local function coinCard(parent, prod, order: number, idx: number)
	local isBoost = prod.BoostMinutes ~= nil
	local color = if isBoost then C.Warn else C.Accent
	local card = Kit.Card(parent, { LayoutOrder = order }, Color3.new(1, 1, 1))
	Kit.new(
		"UIGradient",
		{ Color = ColorSequence.new(color:Lerp(C.Panel2, 0.8), C.Panel2), Rotation = 90, Parent = card }
	)
	if prod.Coins then
		local rate = prod.Coins / prod.Price
		local bonus = math.floor((rate / BASE_RATE - 1) * 100 + 0.5)
		if prod.Key == "Coins30000" then
			Kit.Ribbon(card, "BEST VALUE", C.Success, Color3.fromRGB(6, 34, 16))
		elseif prod.Key == "Coins4000" then
			Kit.Ribbon(card, "POPULAR", C.Red)
		end
		coinPile(card, idx + 1, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16) })
		Kit.Label(card, Kit.Comma(prod.Coins), 28, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(0, 92),
			Size = UDim2.new(1, 0, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Gold,
		})
		Kit.Label(card, prod.Name, 13, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(0, 124),
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.SubText,
		})
		if bonus > 0 then
			Kit.Chip(
				card,
				"+" .. bonus .. "% BONUS",
				C.Success,
				{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 146) }
			)
		end
	else
		Kit.IconTile(
			card,
			"⚡",
			70,
			C.Warn,
			{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16) }
		)
		Kit.Label(card, "2X COINS", 26, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(0, 92),
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Warn,
		})
		Kit.Label(card, "for " .. prod.BoostMinutes .. " minutes of racing", 13, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(0, 124),
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.SubText,
		})
	end
	local _, label = priceButton(card, prod.Price, "primary", function()
		State.PromptProduct(prod.Key)
	end, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -28, 0, 44),
		TextSize = 18,
	})
	if prod.Id ~= 0 then
		task.spawn(function()
			local p = State.ProductPrice(prod.Key)
			if label.Parent then
				label.Text = Kit.Comma(p)
			end
		end)
	end
	return card
end

-- A section title with an optional link on the right ("All passes").
local function sectionRow(parent, title, order, linkText, linkFn)
	local f = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, Parent = parent }
	)
	Kit.Section(f, title, 0)
	if linkText then
		local b = Kit.new("TextButton", {
			Text = linkText .. "  ›",
			Font = Kit.Fonts.Bold,
			TextSize = 13,
			TextColor3 = C.Accent2,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(160, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = f,
		})
		Kit.Clickable(b, linkFn)
	end
end

-- a 3-column grid sized for `count` cards (explicit height: no layout surprises)
local function grid(parent, order: number, cellH: number, count: number)
	local rows = math.max(1, math.ceil(count / 3))
	local g = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, rows * (cellH + 14) - 14),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Grid(g, UDim2.new(1 / 3, -10, 0, cellH), 14)
	return g
end

-- Featured tab: the Ultimate Bundle, the starter deal, popular passes and coin packs.
local function showFeatured()
	Util.Clear(content, true)
	local s = scroller(content)
	hero(s, 1)
	starterBanner(s, 2)
	sectionRow(s, "Popular passes", 3, "All passes", function()
		selectTab("passes")
	end)
	local row = grid(s, 4, 248, 3)
	for i, key in { "VIP", "DoubleCoins", "FXPack" } do
		passCard(row, Monetization.PassByKey[key], i)
	end
	sectionRow(s, "Car packs", 5, "All car packs", function()
		selectTab("cars")
	end)
	local cars = grid(s, 6, 330, 3)
	for i = 1, 3 do
		carPackCard(cars, CAR_PACKS[i], i)
	end
	sectionRow(s, "Coin packs", 7, "All coin packs", function()
		selectTab("coins")
	end)
	local crow = grid(s, 8, 236, 3)
	for i, key in { "Coins4000", "Coins10000", "Coins30000" } do
		local idx = table.find({ "Coins500", "Coins1500", "Coins4000", "Coins10000", "Coins30000" }, key) or 1
		coinCard(crow, Monetization.ProductByKey[key], i, idx)
	end
	Kit.Label(
		s,
		"Purchases are handled securely by Roblox. Nothing in the shop changes car speed - races stay fair.",
		12,
		{ LayoutOrder = 9, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }
	)
end

-- Passes tab.
local function showPasses()
	Util.Clear(content, true)
	local s = scroller(content)
	local g = grid(s, 1, 248, #PERK_PASSES)
	for i, key in PERK_PASSES do
		local pass = Monetization.PassByKey[key]
		if pass then
			passCard(g, pass, if State.HasPass(key) then i + 100 else i)
		end
	end
	Kit.Label(
		s,
		"Owned passes move to the end  •  the Ultimate Bundle includes every pass",
		12,
		{ LayoutOrder = 2, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }
	)
end

-- Car Packs tab (packs you own go to the end).
local function showCars()
	Util.Clear(content, true)
	local s = scroller(content)
	local g = grid(s, 1, 330, #CAR_PACKS)
	for i, def in CAR_PACKS do
		carPackCard(g, def, if State.HasPass(def.key) then i + 100 else i)
	end
	Kit.Label(
		s,
		"Every chassis drives exactly the same - it's all about style. More chassis are sold for coins in the Garage.",
		12,
		{ LayoutOrder = 2, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }
	)
end

-- Coins & Boosts tab.
local function showCoins()
	Util.Clear(content, true)
	local s = scroller(content)
	local g = grid(s, 1, 236, #Monetization.Products)
	for i, prod in Monetization.Products do
		coinCard(g, prod, i, i)
	end
	Kit.Label(
		s,
		"Coins buy chassis, paints, helmets, visors, rims, tyres, trails, smoke, underglow and titles in the Garage.",
		12,
		{ LayoutOrder = 2, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }
	)
end

-- Builds the Shop page.
function Shop.Build(parent: Instance, menu)
	local f, body = menu.PageFrame(parent, "Shop", "Passes, car packs, coins and boosts")
	Shop.Frame = f
	local panel = Kit.Panel(
		body,
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1, 0, 1, 0) }
	)
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(1000, math.huge), Parent = panel })
	Kit.Padding(panel, 18, 14)
	local tabs = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = panel })
	local _, sel = Kit.Tabs(tabs, {
		{ key = "featured", text = "⭐ Featured" },
		{ key = "passes", text = "🎟️ Passes" },
		{ key = "cars", text = "🏎️ Car Packs" },
		{ key = "coins", text = "💰 Coins & Boosts" },
	}, function(key)
		currentTab = key
		if key == "featured" then
			showFeatured()
		elseif key == "passes" then
			showPasses()
		elseif key == "cars" then
			showCars()
		else
			showCoins()
		end
	end)
	selectTab = sel
	content = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		Parent = panel,
	})
	local lastPasses = nil
	State.Changed:Connect(function(p)
		local key = ""
		for k, v in (p and p.passes) or {} do
			if v then
				key ..= k
			end
		end
		if f.Visible and key ~= lastPasses and currentTab ~= "coins" then
			selectTab(currentTab)
		end
		lastPasses = key
	end)
end

-- Page opened, on the Featured tab unless another is given.
function Shop.OnShow(tab: string?)
	selectTab(tab or "featured")
end

return Shop
