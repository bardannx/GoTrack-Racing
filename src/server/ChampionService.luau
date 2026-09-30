--!nonstrict
-- Champion rank: only the season's top 500 ranked drivers (who also have the Champion RP,
-- Config.Ranked.Tiers[#].Min) hold it, and the list is re-picked once a day at 00:00 UTC.
-- The first server of the day reads the season's ranked leaderboard, saves the list, and
-- every other server loads that same list, so all servers agree on who is Champion today.
-- Without DataStore access (Studio before publishing) anyone with the Champion RP counts, so
-- the rank can still be tested.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local DataService = require(script.Parent.DataService)

local CS = {}

local STORE = "GTR_Champions_v1" -- one key per season: today's list
local snap = nil -- { day, season, ids = { [userId string] = place }, count, cutoff, offline }
local retryAt = 0

-- Days since 1970 in UTC; the list is re-picked when this changes.
local function today(): number
	return os.time() // 86400
end

-- RP needed for the top tier (a driver needs this as well as a top-500 place).
local function minRp(): number
	local tiers = Config.Ranked.Tiers
	return tiers[#tiers].Min
end

-- seconds (UTC) when the list is next re-picked
function CS.ResetsAt(): number
	return (today() + 1) * 86400
end

-- read the season's ranked board: top ChampionSlots drivers with at least the Champion RP
local function compute(season: number)
	local board = DataStoreService:GetOrderedDataStore(Config.RankedBoard(season))
	local slots = Config.Ranked.ChampionSlots
	local pages = board:GetSortedAsync(false, 100, minRp())
	local ids, n, cutoff = {}, 0, nil
	while true do
		for _, item in pages:GetCurrentPage() do
			local uid = tonumber(item.key)
			if uid and n < slots then
				n += 1
				ids[tostring(uid)] = n
				cutoff = item.value
			end
		end
		if n >= slots or pages.IsFinished then
			break
		end
		pages:AdvanceToNextPageAsync()
	end
	return { day = today(), season = season, ids = ids, count = n, cutoff = cutoff or minRp() }
end

-- true if today's list was (re)loaded
function CS.Refresh(): boolean
	local d, season = today(), Config.Ranked.Season.Number
	if snap and snap.day == d and snap.season == season then
		return false
	end
	if os.clock() < retryAt then
		return false
	end
	local ok, res = pcall(function()
		local store = DataStoreService:GetDataStore(STORE)
		local key = "S" .. season
		local saved = store:GetAsync(key)
		if typeof(saved) == "table" and saved.day == d then
			return saved
		end
		local fresh = compute(season)
		local final = fresh
		store:UpdateAsync(key, function(old)
			if typeof(old) == "table" and old.day == d then
				final = old -- another server was first: use its list
				return nil
			end
			return fresh
		end)
		return final
	end)
	if ok and res then
		snap = res
	else
		-- no DataStore access: points alone decide (keeps it testable); try again later
		snap = { day = d, season = season, ids = {}, count = 0, cutoff = minRp(), offline = true }
		if not ok and not DataService.Offline() then
			warn("[GoTrack] Champion list unavailable:", res)
			retryAt = os.clock() + 300
			snap.day = -1 -- not today's real list: retry after retryAt
		end
	end
	return true
end

-- Whether this player holds the Champion rank today.
function CS.IsChampion(userId: number, rp: number?): boolean
	if not snap then
		CS.Refresh()
	end
	if not snap then
		return false
	end
	if snap.offline then
		return (rp or 0) >= minRp()
	end
	return snap.ids[tostring(userId)] ~= nil
end

-- for the client: how many Champions today, the RP of the last one, when the list resets
function CS.Info()
	return {
		count = if snap then snap.count else 0,
		cutoff = if snap then snap.cutoff else minRp(),
		slots = Config.Ranked.ChampionSlots,
		minRp = minRp(),
		resetsAt = CS.ResetsAt(),
	}
end

-- mark the season's Champions (unlocks the Champion rewards) and push fresh profiles
local function applyTo(player: Player)
	local d = DataService.Get(player)
	if not d then
		return
	end
	local champ = CS.IsChampion(player.UserId, d.rp)
	if champ and d.championSeason ~= Config.Ranked.Season.Number then
		d.championSeason = Config.Ranked.Season.Number
		d.championDays = (d.championDays or 0) + 1
	end
	DataService.Changed(player)
end

-- Loads today's list and checks once a minute for the daily re-pick.
function CS.Start()
	task.spawn(function()
		while true do
			if CS.Refresh() then
				for _, p in Players:GetPlayers() do
					applyTo(p)
				end
			end
			task.wait(60)
		end
	end)
	DataService.Loaded:Connect(function(player)
		applyTo(player)
	end)
end

return CS
