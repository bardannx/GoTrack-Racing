--!nonstrict
-- Player data with session locking, autosave and safe shutdown.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)

local DataService = {}

local LOCK_TIMEOUT = 1800
local AUTOSAVE = 90

local store: DataStore? = nil
local offline = false
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStores.Player)
	end)
	if ok then
		store = result
	else
		offline = true
		warn("[GoTrack] DataStores unavailable - progress will not save:", result)
	end
end

local function deepCopy(t: any): any
	if typeof(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

local function defaultData(): { [string]: any }
	return {
		coins = Config.Economy.StartingCoins,
		xp = 0,
		level = 1,
		owned = {},
		car = deepCopy(Cosmetics.DefaultCar),
		bests = {}, -- time trial best lap per circuit (ms)
		medals = {}, -- time trial medal per circuit
		stats = { races = 0, wins = 0, podiums = 0, fastestLaps = 0, rankedRaces = 0, laps = 0, ttLaps = 0, equips = 0 },
		rp = Config.Ranked.StartRP,
		peakRp = Config.Ranked.StartRP,
		rankedSeason = Config.Ranked.Season.Number,
		history = {}, -- last 10 ranked races
		seasonLog = {}, -- rewards granted at the end of each season
		daily = { last = 0, streak = 0 },
		receipts = {},
		flags = {},
		weekly = {}, -- this week's challenge progress (ChallengeService)
		starter = {}, -- getting-started checklist rewards claimed
		settings = {},
		passCache = {},
		boostUntil = 0,
		created = os.time(),
	}
end

local function reconcile(data: { [string]: any }, template: { [string]: any })
	for k, v in template do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif typeof(v) == "table" and typeof(data[k]) == "table" and (k == "car" or k == "stats") then
			reconcile(data[k], v)
		end
	end
end

type Profile = { data: { [string]: any }, key: string, loaded: boolean, released: boolean }
local profiles: { [Player]: Profile } = {}
local loadedSignal = Instance.new("BindableEvent")
local changedCallbacks: { (Player) -> () } = {}

DataService.Offline = function(): boolean
	return offline
end

local function keyFor(userId: number): string
	return "u_" .. userId
end

local function loadData(player: Player): { [string]: any }?
	if offline or not store then
		return defaultData()
	end
	local key = keyFor(player.UserId)
	local ds = store :: DataStore
	for attempt = 1, 6 do
		if not player.Parent then
			return nil
		end
		local force = attempt >= 6
		local ok, result = pcall(function()
			return ds:UpdateAsync(key, function(old: any)
				local d = if typeof(old) == "table" then old else defaultData()
				local lock = d._lock
				if not force and typeof(lock) == "table" and lock.job ~= game.JobId and os.time() - (lock.time or 0) < LOCK_TIMEOUT then
					return nil
				end
				d._lock = { job = game.JobId, time = os.time() }
				return d
			end)
		end)
		if ok and typeof(result) == "table" and typeof(result._lock) == "table" and result._lock.job == game.JobId then
			return result
		end
		if not ok then
			warn("[GoTrack] Load failed for", player.Name, result)
			-- Only Studio (no API access / unpublished place) falls back to a throwaway
			-- profile. In live servers a transient error (e.g. "502: API Services rejected
			-- request") must NOT switch saving off for everyone - keep retrying instead.
			if RunService:IsStudio() then
				offline = true
				return defaultData()
			end
		end
		task.wait(math.min(attempt * 2, 8))
	end
	return nil
end

local function saveProfile(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or not profile.loaded or offline or not store then
		return false
	end
	local ds = store :: DataStore
	local data = profile.data
	local ok, err = pcall(function()
		ds:UpdateAsync(profile.key, function(old: any)
			if typeof(old) == "table" and typeof(old._lock) == "table" and old._lock.job ~= game.JobId then
				-- another server owns this session now; never overwrite it
				return nil
			end
			data._lock = if release then nil else { job = game.JobId, time = os.time() }
			return data
		end)
	end)
	if not ok then
		warn("[GoTrack] Save failed for", player.Name, err)
	end
	return ok
end

function DataService.Get(player: Player): { [string]: any }?
	local p = profiles[player]
	if p and p.loaded then
		return p.data
	end
	return nil
end

function DataService.WaitFor(player: Player, timeout: number?): { [string]: any }?
	local t0 = os.clock()
	while player.Parent and os.clock() - t0 < (timeout or 30) do
		local d = DataService.Get(player)
		if d then
			return d
		end
		task.wait(0.1)
	end
	return DataService.Get(player)
end

function DataService.SaveNow(player: Player): boolean
	local p = profiles[player]
	if p and p.released then
		return false -- handed over to another server (teleport); it saves from now on
	end
	return saveProfile(player, false)
end

-- Save and give up the session lock before a teleport, so the server the player lands on
-- loads their profile at once. Returns false if the save failed (don't teleport then).
function DataService.ReleaseForTeleport(player: Player): boolean
	local p = profiles[player]
	if not p or not p.loaded or p.released or offline or not store then
		return true
	end
	if saveProfile(player, true) then
		p.released = true
		return true
	end
	return false
end

-- The teleport failed: take the session lock back so this server keeps saving.
function DataService.Reclaim(player: Player): boolean
	local p = profiles[player]
	if not p or not p.released or offline or not store then
		return true
	end
	local ok, got = pcall(function()
		return (store :: DataStore):UpdateAsync(p.key, function(old: any)
			if typeof(old) == "table" and typeof(old._lock) == "table" and old._lock.job ~= game.JobId then
				return nil -- another server already has the player
			end
			p.data._lock = { job = game.JobId, time = os.time() }
			return p.data
		end)
	end)
	if ok and typeof(got) == "table" and typeof(got._lock) == "table" and got._lock.job == game.JobId then
		p.released = false
		return true
	end
	return false
end

function DataService.OnChanged(cb: (Player) -> ())
	table.insert(changedCallbacks, cb)
end

-- Call after mutating data so the client gets a fresh snapshot.
function DataService.Changed(player: Player)
	for _, cb in changedCallbacks do
		task.spawn(cb, player)
	end
end

DataService.Loaded = loadedSignal.Event

-- New ranked season: keep the rewards earned last season forever, soften RP.
function DataService.SeasonRollover(data)
	local season = Config.Ranked.Season.Number
	if data.rankedSeason == season then
		return false
	end
	-- last season's peak (Champion counts if they made the daily top 500 in that season)
	local peakTier = if data.championSeason and data.championSeason == data.rankedSeason then #Config.Ranked.Tiers else Config.TierIndex(data.peakRp or data.rp or 0)
	for _, item in Cosmetics.Items do
		if item.RankTier and item.RankTier <= peakTier then
			data.owned[item.Id] = true
		end
	end
	table.insert(data.seasonLog, { season = data.rankedSeason, peak = data.peakRp, tier = peakTier })
	local start = Config.Ranked.StartRP
	data.rp = math.floor(start + math.max(0, (data.rp or start) - start) * Config.Ranked.SeasonReset)
	data.peakRp = data.rp
	data.history = {}
	data.rankedSeason = season
	return true
end

local function onPlayerAdded(player: Player)
	local data = loadData(player)
	if not player.Parent then
		-- player left while loading: release the session lock we may hold
		if data and not offline then
			profiles[player] = { data = data, key = keyFor(player.UserId), loaded = true, released = true }
			saveProfile(player, true)
			profiles[player] = nil
		end
		return
	end
	if not data then
		player:Kick("GoTrack could not load your data. Please rejoin in a minute.")
		return
	end
	reconcile(data, defaultData())
	DataService.SeasonRollover(data)
	data.car = Cosmetics.Sanitize(data.car)
	profiles[player] = { data = data, key = keyFor(player.UserId), loaded = true, released = false }
	loadedSignal:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local p = profiles[player]
	if not p or p.released then
		profiles[player] = nil
		return
	end
	-- let the other PlayerRemoving handlers finish first (e.g. the ranked leave penalty)
	task.wait()
	if p.released then
		return
	end
	p.released = true
	-- the last save of a session must not be lost to a transient DataStore error
	for attempt = 1, 4 do
		if saveProfile(player, true) then
			break
		end
		task.wait(attempt * 2)
	end
	profiles[player] = nil
end

function DataService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, pl in Players:GetPlayers() do
		task.spawn(onPlayerAdded, pl)
	end
	-- a new ranked season can start while a server is running
	task.spawn(function()
		while true do
			task.wait(60)
			for pl, prof in profiles do
				if prof.loaded and not prof.released and DataService.SeasonRollover(prof.data) then
					DataService.Changed(pl)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for pl, prof in profiles do
				if prof.loaded and not prof.released then
					task.spawn(saveProfile, pl, false)
				end
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and offline then
			return
		end
		local pending = 0
		for pl, prof in profiles do
			if not prof.released then
				prof.released = true
				pending += 1
				task.spawn(function()
					saveProfile(pl, true)
					pending -= 1
				end)
			end
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
