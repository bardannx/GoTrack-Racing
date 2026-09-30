--!nonstrict
-- Client-side cache of the player's profile (server is authoritative).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Cosmetics = require(Shared.Cosmetics)
local Monetization = require(Shared.Monetization)
local Config = require(Shared.Config)

local Util = require(script.Parent.Util)

local State = {}
State.Profile = nil :: any
State.Changed = Util.Signal()
State.Notify = Util.Signal()

State.DefaultSettings = {
	Fov = 78,
	Shake = true,
	Units = "kmh",
	ShowGhosts = true,
	ShowPBGhost = true,
	Quality = if game:GetService("UserInputService").TouchEnabled and not game:GetService("UserInputService").KeyboardEnabled then 2 else 3, -- 1 low .. 4 ultra
	Camera = "chase_near",
	NameTags = true,
	RacingLine = "full", -- off | braking | full
	ShowFPS = false,
	Sfx = 80,
	Engine = 100, -- engine sound volume (on top of Sfx)
	SpeedFov = true,
}

-- Camera views in the order the C key cycles through them
State.CameraModes = {
	{ "chase_near", "Chase" },
	{ "chase_far", "Far Chase" },
	{ "tcam", "T-Cam" },
	{ "cockpit", "Cockpit" },
	{ "nose", "Nose" },
	{ "tv", "TV" },
}

function State.CycleCamera(): string
	local cur = State.Setting("Camera")
	local idx = 1
	for i, m in State.CameraModes do
		if m[1] == cur then
			idx = i
		end
	end
	local nextMode = State.CameraModes[(idx % #State.CameraModes) + 1]
	State.SetSetting("Camera", nextMode[1])
	return nextMode[2]
end

-- Settings changed on this device win over the copy in a profile push: the push can be
-- older than our last SaveSettings (it used to flip toggles back right after you changed them).
local localSettings: { [string]: any } = {}
local saveToken = 0

local function withLocalSettings(snap)
	if snap then
		snap.settings = snap.settings or {}
		for k, v in localSettings do
			snap.settings[k] = v
		end
	end
	return snap
end

function State.Init()
	Net.Event("ProfileUpdated").OnClientEvent:Connect(function(snap)
		State.Profile = withLocalSettings(snap)
		State.Changed:Fire(snap)
	end)
	Net.Event("Notify").OnClientEvent:Connect(function(msg, kind)
		State.Notify:Fire(msg, kind)
	end)
	for attempt = 1, 20 do
		local snap = Util.Invoke("GetProfile")
		if snap then
			State.Profile = snap
			State.Changed:Fire(snap)
			return true
		end
		task.wait(math.min(attempt, 5))
	end
	return false
end

function State.HasPass(key: string): boolean
	local p = State.Profile
	if not p or not p.passes then
		return false
	end
	return p.passes[key] == true or p.passes.Ultimate == true
end

function State.Passes(): { [string]: boolean }
	return (State.Profile and State.Profile.passes) or {}
end

function State.CanUse(item): boolean
	local p = State.Profile
	if not p then
		return false
	end
	return Cosmetics.CanUse(item, p.owned or {}, p.passes or {}, p.peakTier)
end

function State.Setting(key: string): any
	local p = State.Profile
	local v = p and p.settings and p.settings[key]
	if key == "Camera" then
		-- migrate v2 values
		if v == "near" then
			v = "chase_near"
		elseif v == "far" then
			v = "chase_far"
		end
	end
	if v == nil then
		return State.DefaultSettings[key]
	end
	return v
end

function State.SetSetting(key: string, value: any)
	local p = State.Profile
	if not p then
		return
	end
	p.settings = p.settings or {}
	p.settings[key] = value
	localSettings[key] = value
	State.Changed:Fire(p)
	-- debounce: a burst of changes saves once (the server rate-limits remotes)
	saveToken += 1
	local my = saveToken
	task.delay(0.4, function()
		if my == saveToken and State.Profile then
			local res = Util.Invoke("SaveSettings", State.Profile.settings)
			if not (res and res.ok) then
				task.wait(2)
				if my == saveToken and State.Profile then
					Util.Invoke("SaveSettings", State.Profile.settings)
				end
			end
		end
	end)
end

-- Opens the Roblox purchase prompt for a game pass (by key).
function State.PromptPass(key: string): boolean
	local pass = Monetization.PassByKey[key]
	if not pass then
		return false
	end
	if pass.Id == 0 then
		State.Notify:Fire(pass.Name .. " isn't on sale yet - check back soon!", "warn")
		return false
	end
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.Id)
	return true
end

function State.PromptProduct(key: string): boolean
	local prod = Monetization.ProductByKey[key]
	if not prod then
		return false
	end
	if prod.Id == 0 then
		State.Notify:Fire(prod.Name .. " isn't on sale yet - check back soon!", "warn")
		return false
	end
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, prod.Id)
	return true
end

-- Live Robux prices from the dashboard (falls back to config values)
local priceCache: { [string]: number } = {}
function State.PassPrice(key: string): number
	local pass = Monetization.PassByKey[key]
	if not pass then
		return 0
	end
	if priceCache[key] then
		return priceCache[key]
	end
	if pass.Id ~= 0 then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(pass.Id, Enum.InfoType.GamePass)
		end)
		if ok and info and info.PriceInRobux then
			priceCache[key] = info.PriceInRobux
			return info.PriceInRobux
		end
	end
	return pass.Price
end

function State.ProductPrice(key: string): number
	local prod = Monetization.ProductByKey[key]
	if not prod then
		return 0
	end
	local ck = "p_" .. key
	if priceCache[ck] then
		return priceCache[ck]
	end
	if prod.Id ~= 0 then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(prod.Id, Enum.InfoType.Product)
		end)
		if ok and info and info.PriceInRobux then
			priceCache[ck] = info.PriceInRobux
			return info.PriceInRobux
		end
	end
	return prod.Price
end

function State.SpeedText(studsPerSecond: number): (string, string)
	local kmh = math.abs(studsPerSecond) * Config.SpeedDisplayFactor
	if State.Setting("Units") == "mph" then
		return tostring(math.floor(kmh * 0.621371)), "MPH"
	end
	return tostring(math.floor(kmh)), "KM/H"
end

return State
