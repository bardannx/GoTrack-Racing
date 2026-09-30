--!nonstrict
-- Everything players pay for, on the server: which game passes they own, delivering
-- developer products (coin packs, Coin Boost) and the coin multipliers from passes.
-- None of it touches car speed or handling. The pass and product list is in
-- shared/Monetization.luau.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Monetization = require(Shared.Monetization)
local Cosmetics = require(Shared.Cosmetics)

local DataService = require(script.Parent.DataService)

local M = {}

local owned: { [Player]: { [string]: boolean } } = {}
local notify: ((Player, string, string?) -> ())? = nil

-- How to show the player a toast (set by init.server so this module needs no remotes).
function M.SetNotifier(fn: (Player, string, string?) -> ())
	notify = fn
end

-- Ultimate counts as owning every pass.
local function expand(set: { [string]: boolean }): { [string]: boolean }
	if set.Ultimate then
		for _, p in Monetization.Passes do
			set[p.Key] = true
		end
	end
	return set
end

-- Set of pass keys the player owns.
function M.GetPasses(player: Player): { [string]: boolean }
	return owned[player] or {}
end

-- Whether the player owns a pass (Ultimate owns them all).
function M.Has(player: Player, key: string): boolean
	local s = owned[player]
	return s ~= nil and (s[key] == true or s.Ultimate == true)
end

-- Sets the player attributes other scripts read (VIP, Ultimate, Owner chat tags) and
-- gives the game owner every cosmetic.
local function applyPerks(player: Player)
	local data = DataService.Get(player)
	local passes = M.GetPasses(player)
	player:SetAttribute("VIP", passes.VIP == true)
	player:SetAttribute("Ultimate", passes.Ultimate == true)
	player:SetAttribute("Owner", passes.Owner == true)
	if data and passes.Owner then
		-- the owner has everything: coin cosmetics and ranked rewards too
		for _, item in Cosmetics.Items do
			if (item.Price > 0 and not item.Pass) or item.RankTier then
				data.owned[item.Id] = true
			end
		end
		if not data.flags.ownerTitle then
			data.flags.ownerTitle = true
			data.car.Title = "title_owner"
		end
	end
	if data then
		-- one-time Starter Pack coins
		if passes.StarterPack and not data.flags.starterGranted then
			data.flags.starterGranted = true
			data.coins += 1500
			if notify then
				(notify :: any)(player, "🎁 Starter Pack: +1,500 coins!", "success")
			end
		end
		-- re-validate equipped cosmetics (a refunded pass removes locked items)
		data.car = Cosmetics.Sanitize(data.car, data.owned, passes, Config.PeakTier(data))
		local title = Cosmetics.ById[data.car.Title]
		player:SetAttribute("Title", if title and title.Text then title.Text else "Racer")
		-- keep a cache so perks survive a temporary MarketplaceService outage
		data.passCache = table.clone(passes)
		DataService.Changed(player)
	end
end

-- Asks Roblox which passes the player owns and applies the perks.
local function refresh(player: Player)
	local set: { [string]: boolean } = {}
	local data = DataService.Get(player)
	local studioAll = RunService:IsStudio() and Config.StudioGrantAllPasses
	local isOwner = Config.IsOwner(player.UserId)
	local pending = 0
	for _, pass in Monetization.Passes do
		if studioAll or isOwner then
			set[pass.Key] = true
		elseif pass.Id ~= 0 then
			pending += 1
			task.spawn(function()
				local ok, has = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
				end)
				if ok then
					set[pass.Key] = has == true
				elseif data and data.passCache and data.passCache[pass.Key] then
					set[pass.Key] = true
				end
				pending -= 1
			end)
		end
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 15 do
		task.wait(0.05)
	end
	owned[player] = expand(set)
	if isOwner then
		owned[player].Owner = true
	end
	applyPerks(player)
end

-- Coin multiplier for race rewards: 2x Coins pass, VIP bonus and an active Coin Boost.
function M.CoinMultiplier(player: Player): number
	local mult = 1
	if M.Has(player, "DoubleCoins") then
		mult *= 2
	end
	if M.Has(player, "VIP") then
		mult *= Config.Economy.VIPCoinMultiplier
	end
	local data = DataService.Get(player)
	if data and (data.boostUntil or 0) > os.time() then
		mult *= 2
	end
	return mult
end

-- (no XP pass any more: XP is the same for everyone)
function M.XPMultiplier(_player: Player): number
	return 1
end

-- Delivers a developer product. Each receipt is remembered so a retry can never pay twice,
-- and Roblox is only told "granted" once the save has gone through.
local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.WaitFor(player, 10)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipts: { string } = data.receipts
	if table.find(receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Monetization.ProductById[info.ProductId]
	if not product then
		warn("[GoTrack] Unknown developer product id", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local oldCoins, oldBoost = data.coins, data.boostUntil
	if product.Coins then
		data.coins += product.Coins
	end
	if product.BoostMinutes then
		local now = os.time()
		data.boostUntil = math.max(data.boostUntil or 0, now) + product.BoostMinutes * 60
	end
	table.insert(receipts, info.PurchaseId)
	while #receipts > 100 do
		table.remove(receipts, 1)
	end
	-- Only tell Roblox the purchase is delivered once it is actually saved. If the save
	-- fails, undo it; Roblox retries the receipt later (e.g. when the player rejoins).
	if not DataService.SaveNow(player) and not DataService.Offline() then
		data.coins, data.boostUntil = oldCoins, oldBoost
		local i = table.find(receipts, info.PurchaseId)
		if i then
			table.remove(receipts, i)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.Changed(player)
	if notify then
		if product.Coins then
			(notify :: any)(player, string.format("💰 +%d coins! Thanks for your support!", product.Coins), "success")
		end
		if product.BoostMinutes then
			(notify :: any)(
				player,
				string.format("⚡ 2x Coin Boost active for %d minutes!", product.BoostMinutes),
				"success"
			)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Loads passes when a save loads and listens for purchases made during the session.
function M.Init()
	DataService.Loaded:Connect(function(player: Player)
		refresh(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			local pass = Monetization.PassById[passId]
			if not pass then
				return
			end
			local set = owned[player] or {}
			set[pass.Key] = true
			owned[player] = expand(set)
			applyPerks(player)
			if notify then
				(notify :: any)(player, pass.Icon .. " " .. pass.Name .. " unlocked! Enjoy!", "success")
			end
		end
	)
	MarketplaceService.ProcessReceipt = processReceipt
end

return M
