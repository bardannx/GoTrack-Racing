--!nonstrict
-- Garage: categories on the left, item grid on the right, the car in the middle on the
-- turntable (drag to rotate, scroll to zoom). Clicking a locked item previews it on the
-- car and shows how to unlock it; owned items equip instantly.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local Monetization = require(Shared.Monetization)
local Config = require(Shared.Config)
local CarBuilder = require(Shared.CarBuilder)

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local Util = require(script.Parent.Parent.Util)
local Fx = require(script.Parent.Parent.Fx)

local C = Kit.Colors
local Garage = {}
Garage.Camera = "garage"

local menu: any = nil
local itemsScroll, titleLabel, countLabel, actionBar, actionName, actionInfo, actionBtn
local catButtons = {}
local currentSlot = "Body"
local selected = nil -- item being previewed

local GROUPS = {
	{ "CAR", { "Body", "Pattern", "Primary", "Secondary", "Accent" } },
	{ "WHEELS", { "Rims", "RimColor", "Tyre" } },
	{ "DRIVER", { "Helmet", "Visor", "Title", "Number" } },
	{ "EFFECTS", { "TyreSmoke", "Underglow", "Trail", "Flames", "Celebration" } },
}

local ICONS = {
	Body = "🏎️", Pattern = "🎨", Primary = "🖌️", Secondary = "🖌️", Accent = "🖌️",
	Rims = "⚙️", RimColor = "🖌️", Tyre = "🛞", Helmet = "⛑️", Visor = "🥽", Title = "🏷️", Number = "🔢",
	TyreSmoke = "💨", Underglow = "💡", Trail = "🌈", Flames = "🔥", Celebration = "🎆",
}

-- item filter above the grid
local FILTERS = { { "all", "All" }, { "owned", "Owned" }, { "free", "Free" }, { "coins", "Coins" }, { "pass", "Passes" } }
local filterMode = "all"
local filterButtons = {}
local catCounts = {}

local function passesFilter(item, usable: boolean): boolean
	if filterMode == "owned" then
		return usable
	elseif filterMode == "free" then
		return item.Price <= 0 and not item.Pass and not item.RankTier
	elseif filterMode == "coins" then
		return item.Price > 0
	elseif filterMode == "pass" then
		return item.Pass ~= nil or item.RankTier ~= nil
	end
	return true
end

local function passFor(item)
	return if item.Pass then Monetization.PassByKey[item.Pass] else nil
end

local function rarityColor(item): Color3
	if item.RankTier then
		return Config.Ranked.Tiers[item.RankTier].Color
	elseif item.Pass then
		return C.Purple
	elseif item.Price > 0 then
		return C.Accent
	end
	return C.Muted
end

local function previewAppearance(slot: string, item)
	local car = table.clone(State.Profile.car)
	car[slot] = item.Id
	if slot == "Body" and Cosmetics.BodyLivery[item.Id] then
		-- chassis previews/thumbnails show the car in its factory colours
		for k, v in Cosmetics.BodyLivery[item.Id] do
			car[k] = v
		end
	end
	return car
end

local function equip(slot: string, item)
	task.spawn(function()
		local res = Util.Invoke("Equip", slot, item.Id)
		if res and res.ok then
			Fx.Play("Click", 0.4, 1.2)
		elseif res and res.err then
			Kit.Toast(res.err, "error")
		end
	end)
end

local refreshItems

local function setAction(item)
	selected = item
	if not item then
		actionBar.Visible = false
		menu.Scene.ClearPreview()
		return
	end
	actionBar.Visible = true
	actionName.Text = item.Name
	local usable = State.CanUse(item)
	local equipped = State.Profile.car[currentSlot] == item.Id
	for _, c in actionBtn:GetChildren() do
		if c:IsA("Frame") and c.Name == "Price" then
			c:Destroy()
		end
	end
	actionBtn.Text = ""
	if equipped then
		actionInfo.Text = "Equipped on your car"
		actionBtn.Text = "✓ EQUIPPED"
		Kit.SetButtonStyle(actionBtn, "ghost")
	elseif usable then
		actionInfo.Text = "You own this"
		actionBtn.Text = "EQUIP"
		Kit.SetButtonStyle(actionBtn, "success")
	elseif item.RankTier then
		local tier = Config.Ranked.Tiers[item.RankTier]
		actionInfo.Text = "Ranked reward - reach " .. tier.Name .. " this season"
		actionBtn.Text = "🏆 PLAY RANKED"
		Kit.SetButtonStyle(actionBtn, "purple")
	elseif item.Pass then
		local pass = passFor(item)
		actionInfo.Text = "Included in " .. (if pass then pass.Name else "a game pass")
		Kit.SetButtonStyle(actionBtn, "purple")
		local price = Kit.RobuxPrice(actionBtn, State.PassPrice(item.Pass), 18, C.White, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		price.Name = "Price"
	else
		actionInfo.Text = string.format("Costs %s coins  •  you have %s", Kit.Comma(item.Price), Kit.Comma(State.Profile.coins))
		actionBtn.Text = "BUY  " .. Kit.Comma(item.Price)
		Kit.SetButtonStyle(actionBtn, "primary")
	end
	-- chassis: which real F1 era the design comes from
	if item.Era then
		actionInfo.Text = item.Era .. "  •  " .. actionInfo.Text
	end
end

local function onAction()
	local item = selected
	if not item then
		return
	end
	local slot = currentSlot
	if State.Profile.car[slot] == item.Id then
		return
	end
	if State.CanUse(item) then
		equip(slot, item)
		return
	end
	if item.RankTier then
		menu.Open("ranked")
		return
	end
	if item.Pass then
		State.PromptPass(item.Pass)
		return
	end
	if State.Profile.coins < item.Price then
		Kit.Modal("Not enough coins", string.format("%s costs %s coins and you have %s.\nWin races to earn more, or grab a coin pack!", item.Name, Kit.Comma(item.Price), Kit.Comma(State.Profile.coins)), {
			{ "OK", "secondary" },
			{ "Get coins", "primary", function()
				menu.Open("shop", "coins")
			end },
		})
		return
	end
	task.spawn(function()
		local res = Util.Invoke("BuyItem", item.Id)
		if res and res.ok then
			Fx.Play("Purchase", 0.5)
			Kit.Toast("✨ Unlocked " .. item.Name .. "!", "success")
			equip(slot, item)
		else
			Kit.Toast((res and res.err) or "Purchase failed", "error")
		end
	end)
end

-- live 3D thumbnail of the car wearing this item
local function carThumb(area, slot: string, item)
	local vp = Kit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.5, -1, -0.3),
		Parent = area,
	})
	local ok = pcall(function()
		local parts = CarBuilder.Build(previewAppearance(slot, item), { Preview = true, UserId = State.Profile.userId })
		parts.Model:PivotTo(CFrame.new(0, 0, 0))
		parts.Model.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		if slot == "Rims" then
			cam.CFrame = CFrame.lookAt(Vector3.new(10, 0.6, -10.5), Vector3.new(2.3, -0.95, -4.6))
		else
			cam.CFrame = CFrame.lookAt(Vector3.new(18, 8, -21), Vector3.new(0, -0.6, 0.4))
		end
		cam.Parent = vp
		vp.CurrentCamera = cam
	end)
	if not ok then
		vp:Destroy()
	end
end

local function swatch(card, item, category)
	local area = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 62), Parent = card })
	if category == "Body" or category == "Pattern" or category == "Rims" then
		carThumb(area, currentSlot, item)
		return
	end
	if item.Color and (category == "Paint" or category == "Helmet" or category == "Visor" or category == "Tyre" or category == "Underglow" or category == "Trail" or category == "TyreSmoke") then
		local sw = Kit.new("Frame", { BackgroundColor3 = item.Color, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(52, 52), Parent = area })
		Kit.Round(sw)
		Kit.Stroke(sw, Color3.new(1, 1, 1), 2, 0.55)
		if item.Rainbow then
			local g = Kit.new("UIGradient", { Parent = sw })
			local kps = {}
			for k = 0, 6 do
				table.insert(kps, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6, 0.85, 1)))
			end
			g.Color = ColorSequence.new(kps)
			sw.BackgroundColor3 = Color3.new(1, 1, 1)
		elseif item.Material == Enum.Material.Neon or category == "Underglow" then
			Kit.Stroke(sw, item.Color, 4, 0.1)
		elseif (item.Reflectance or 0) > 0.15 or item.Material == Enum.Material.Metal then
			Kit.Gradient(sw, item.Color:Lerp(Color3.new(1, 1, 1), 0.5), item.Color:Lerp(Color3.new(0, 0, 0), 0.3), 45)
		end
		if category == "Helmet" and item.Stripe then
			local stripe = Kit.new("Frame", { BackgroundColor3 = item.Stripe, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 8), Parent = sw })
			stripe.ZIndex = 2
		end
	else
		local glyph = ICONS[currentSlot] or "✨"
		if string.find(item.Id, "none") or item.Id == "flames_none" then
			glyph = "🚫"
		elseif category == "Body" then
			glyph = "🏎️"
		end
		Kit.Label(area, glyph, 34, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	end
end

refreshItems = function()
	if not itemsScroll then
		return
	end
	Util.Clear(itemsScroll, true)
	local profile = State.Profile
	for slot, b in catButtons do
		local on = slot == currentSlot
		b.BackgroundColor3 = if on then C.Accent else Color3.fromRGB(0, 0, 0)
		b.BackgroundTransparency = if on then 0 else 1
		for _, d in b:GetChildren() do
			if d:IsA("TextLabel") then
				d.TextColor3 = if on then Color3.fromRGB(30, 20, 4) else C.Text
			end
		end
	end
	if currentSlot == "Number" then
		titleLabel.Text = "Race number"
		countLabel.Text = ""
		local n = Cosmetics.NumberFor(profile.car, profile.userId)
		local card = Kit.Card(itemsScroll, { Size = UDim2.fromOffset(280, 150), LayoutOrder = 1 })
		Kit.Label(card, "#" .. n, 56, { Font = Kit.Fonts.Logo, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 66), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Accent })
		Kit.Button(card, if State.HasPass("ProRacer") then "CHANGE NUMBER" else "🔒 CUSTOM NUMBER", if State.HasPass("ProRacer") then "primary" else "purple", function()
			if not State.HasPass("ProRacer") then
				State.PromptPass("ProRacer")
				return
			end
			Kit.Prompt("🔢 Race number", "1 - 99", tostring(n), function(text)
				task.spawn(function()
					local res = Util.Invoke("SetNumber", tonumber(text))
					if res and res.ok then
						Kit.Toast("Race number set to #" .. res.number, "success")
					else
						Kit.Toast((res and res.err) or "Couldn't set number", "error")
					end
				end)
			end, 2)
		end, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -28, 0, 42), TextSize = 15 })
		setAction(nil)
		return
	end
	local category = Cosmetics.Slots[currentSlot]
	titleLabel.Text = Cosmetics.SlotLabels[currentSlot]
	local equipped = profile.car[currentSlot]
	-- owner-only items (the Owner title) are only listed for the owner
	local items = {}
	for _, it in Cosmetics.ByCategory[category] or {} do
		if not it.OwnerOnly or State.CanUse(it) then
			table.insert(items, it)
		end
	end
	local owned = 0
	for _, it in items do
		if State.CanUse(it) then
			owned += 1
		end
	end
	countLabel.Text = string.format("%d / %d unlocked", owned, #items)
	-- unlocked counts next to every category + filter chip states
	for slot, lbl in catCounts do
		local cat = Cosmetics.Slots[slot]
		local list = cat and Cosmetics.ByCategory[cat]
		if list then
			local n = 0
			for _, it in list do
				if State.CanUse(it) then
					n += 1
				end
			end
			lbl.Text = n .. "/" .. #list
		end
	end
	for key, b in filterButtons do
		local on = key == filterMode
		b.BackgroundColor3 = if on then C.Accent2 else C.Panel2
		b.TextColor3 = if on then Color3.fromRGB(10, 20, 30) else C.Text
	end
	local shown = 0
	for i, item in items do
		local usable = State.CanUse(item)
		if not passesFilter(item, usable) and equipped ~= item.Id then
			continue
		end
		shown += 1
		local isEquipped = equipped == item.Id
		local isSel = selected and selected.Id == item.Id
		local card = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if isEquipped then Color3.fromRGB(64, 52, 20) else C.Panel2, LayoutOrder = i, Parent = itemsScroll })
		Kit.Corner(card, 12)
		Kit.Stroke(card, if isEquipped then C.Accent elseif isSel then C.Accent2 else C.White, if isEquipped or isSel then 2.5 else 1, if isEquipped or isSel then 0 else 0.9)
		local strip = Kit.new("Frame", { BackgroundColor3 = rarityColor(item), BorderSizePixel = 0, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 0, 3), Parent = card })
		Kit.Corner(strip, 2)
		swatch(card, item, category)
		Kit.Label(card, item.Name, 13, { Font = Kit.Fonts.Bold, Position = UDim2.new(0, 4, 0, 74), Size = UDim2.new(1, -8, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
		local status, statusColor
		if isEquipped then
			status, statusColor = "EQUIPPED", C.Accent
		elseif usable then
			local free = item.Price <= 0 and not item.Pass and not item.RankTier
			status, statusColor = if free then "FREE" else "OWNED", if free then C.SubText else C.Success
		elseif item.RankTier then
			status, statusColor = "🏆 " .. Config.Ranked.Tiers[item.RankTier].Name, Config.Ranked.Tiers[item.RankTier].Color
		elseif item.Pass then
			local pass = passFor(item)
			status, statusColor = (if pass then pass.Icon .. " " .. pass.Name else "🔒 Pass"), if pass then pass.Color:Lerp(C.White, 0.35) else Color3.fromRGB(190, 150, 255)
		else
			status, statusColor = "🪙 " .. Kit.Comma(item.Price), C.Warn
		end
		Kit.Label(card, status, 11, { Font = Kit.Fonts.Title, Position = UDim2.new(0, 4, 1, -24), Size = UDim2.new(1, -8, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = statusColor, TextTruncate = Enum.TextTruncate.AtEnd })
		if isEquipped then
			local tick = Kit.new("Frame", { BackgroundColor3 = C.Accent, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 8), Size = UDim2.fromOffset(20, 20), Parent = card })
			Kit.Round(tick)
			Kit.Label(tick, "✓", 12, { Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(30, 20, 4) })
		elseif not usable then
			Kit.Label(card, "🔒", 14, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(20, 20), TextXAlignment = Enum.TextXAlignment.Center })
		end
		Kit.Clickable(card, function()
			if usable and not isEquipped then
				selected = item
				menu.Scene.ClearPreview()
				equip(currentSlot, item)
				setAction(item)
			else
				selected = item
				if not usable then
					menu.Scene.RefreshCar(previewAppearance(currentSlot, item))
				else
					menu.Scene.ClearPreview()
				end
				setAction(item)
				refreshItems()
			end
		end)
	end
	if shown == 0 then
		Kit.Label(itemsScroll, "Nothing here with this filter - try All.", 13, { Font = Kit.Fonts.Bold, TextColor3 = C.SubText, TextWrapped = true })
	end
	if selected and Cosmetics.Slots[currentSlot] == selected.Category then
		setAction(selected)
	else
		setAction(nil)
	end
end

-- 🎲 a random combination of things you own (paints, livery, helmet, visor, rims, tyres)
function Garage.RandomLook()
	local p = State.Profile
	if not p then
		return
	end
	task.spawn(function()
		local used = {}
		for _, slot in { "Primary", "Secondary", "Accent", "Pattern", "Helmet", "Visor", "Rims", "RimColor", "Tyre" } do
			local pool = {}
			for _, it in Cosmetics.ByCategory[Cosmetics.Slots[slot]] or {} do
				if State.CanUse(it) and not (slot ~= "Primary" and used[it.Id] and Cosmetics.Slots[slot] == "Paint") then
					table.insert(pool, it)
				end
			end
			if #pool > 0 then
				local pick = pool[math.random(1, #pool)]
				used[pick.Id] = true
				if p.car[slot] ~= pick.Id then
					Util.Invoke("Equip", slot, pick.Id)
				end
			end
		end
		Fx.Play("Purchase", 0.35, 1.3)
		Kit.Toast("🎲 New look! Keep it or roll again.", "success")
	end)
end

-- ↺ back to the current chassis' factory colours
function Garage.FactoryLook()
	local p = State.Profile
	if not p then
		return
	end
	task.spawn(function()
		local res = Util.Invoke("Equip", "Body", p.car.Body)
		if res and res.ok then
			Fx.Play("Click", 0.4, 1.1)
			Kit.Toast("↺ Factory colours restored", "success")
		end
	end)
end

function Garage.Build(parent: Instance, m)
	menu = m
	local f, body = m.PageFrame(parent, "Garage", "Every car has identical performance - this is all about style")
	Garage.Frame = f
	-- categories (left)
	local left = Kit.Panel(body, { Size = UDim2.new(0, 236, 1, 0) })
	Kit.Padding(left, 10, 10)
	local catScroll = Kit.ScrollList(left, nil, 2)
	local order = 0
	for _, group in GROUPS do
		order += 1
		local h = Kit.Label(catScroll, group[1], 11, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.Muted, LayoutOrder = order })
		h.TextYAlignment = Enum.TextYAlignment.Bottom
		Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = h })
		for _, slot in group[2] do
			order += 1
			local b = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BackgroundColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = order, Parent = catScroll })
			Kit.Corner(b, 10)
			Kit.Label(b, ICONS[slot] or "✨", 17, { Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(24, 38), TextXAlignment = Enum.TextXAlignment.Center })
			Kit.Label(b, if slot == "Number" then "Race number" else Cosmetics.SlotLabels[slot], 14, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -96, 1, 0) })
			if slot ~= "Number" then
				local cnt = Kit.Label(b, "", 11, { Font = Kit.Fonts.Bold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(46, 38), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Muted })
				cnt.RichText = false
				catCounts[slot] = cnt
			end
			Kit.Clickable(b, function()
				currentSlot = slot
				selected = nil
				menu.Scene.ClearPreview()
				refreshItems()
			end)
			catButtons[slot] = b
		end
	end
	-- items (right)
	local right = Kit.Panel(body, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 470, 1, 0) })
	Kit.Padding(right, 16, 14)
	titleLabel = Kit.Label(right, "Chassis", 22, { Font = Kit.Fonts.Title, Size = UDim2.new(1, -200, 0, 28) })
	countLabel = Kit.Label(right, "", 12, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, -200, 0, 16), TextColor3 = C.SubText })
	-- quick looks: random owned combo, back to the chassis' factory colours
	local quick = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(196, 36), Parent = right })
	Kit.List(quick, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
	Kit.Button(quick, "🎲 Random", "secondary", function()
		Garage.RandomLook()
	end, { Size = UDim2.fromOffset(96, 34), TextSize = 13, LayoutOrder = 1 })
	Kit.Button(quick, "↺ Factory", "secondary", function()
		Garage.FactoryLook()
	end, { Size = UDim2.fromOffset(94, 34), TextSize = 13, LayoutOrder = 2 })
	-- filter chips
	local filters = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 28), Parent = right })
	Kit.List(filters, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for i, fl in FILTERS do
		local fb = Kit.new("TextButton", { Text = fl[2], Font = Kit.Fonts.Bold, TextSize = 12, TextColor3 = C.Text, AutoButtonColor = false, BackgroundColor3 = C.Panel2, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = filters })
		Kit.Round(fb)
		Kit.Padding(fb, 12, 0)
		Kit.Clickable(fb, function()
			filterMode = fl[1]
			refreshItems()
		end)
		filterButtons[fl[1]] = fb
	end
	itemsScroll = Kit.ScrollGrid(right, UDim2.fromOffset(130, 132), 10, { Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 1, -86 - 84) })
	-- action bar
	actionBar = Kit.Card(right, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 74), Visible = false }, Color3.fromRGB(14, 16, 27))
	actionName = Kit.Label(actionBar, "", 17, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -200, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
	actionInfo = Kit.Label(actionBar, "", 12, { Font = Kit.Fonts.Bold, Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -200, 0, 18), TextColor3 = C.SubText, TextTruncate = Enum.TextTruncate.AtEnd })
	actionBtn = Kit.Button(actionBar, "EQUIP", "success", onAction, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(170, 48), TextSize = 17 })
	-- hint under the car
	local hint = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(12, 14, 24), BackgroundTransparency = 0.2, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, -117, 1, 0), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Parent = body })
	Kit.Round(hint)
	Kit.Padding(hint, 14, 0)
	Kit.Label(hint, if Kit.IsMobile() then "👆  Drag to rotate  •  Pinch to zoom" else "🖱️  Drag to rotate  •  Scroll to zoom", 12, { Font = Kit.Fonts.Bold, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, TextColor3 = C.SubText })
	State.Changed:Connect(function()
		if f.Visible then
			refreshItems()
			if not menu.Scene.IsPreviewing() then
				menu.Scene.RefreshCar()
			end
		end
	end)
end

function Garage.OnShow()
	selected = nil
	refreshItems()
end

function Garage.OnHide()
	selected = nil
	menu.Scene.ClearPreview()
end

return Garage
