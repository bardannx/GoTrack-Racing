--!nonstrict
-- Leaderboards (OrderedDataStores): time-trial lap records per circuit, ranked points,
-- race wins. Also stores time-trial ghosts.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local L = {}

local ghostStore = nil
pcall(function()
	ghostStore = DataStoreService:GetDataStore(Config.DataStores.Ghosts)
end)

local ordered = {}
local function store(name: string)
	if ordered[name] then
		return ordered[name]
	end
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		ordered[name] = s
		return s
	end
	return nil
end

local names = {}
local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local pl = Players:GetPlayerByUserId(userId)
	if pl then
		names[userId] = pl.DisplayName
		return pl.DisplayName
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local nm = if ok and n then n else ("Player" .. userId)
	names[userId] = nm
	return nm
end

local cache = {}
local fetching = {}

-- Returns { {userId, name, value, rank} }
function L.GetTop(storeName: string, ascending: boolean)
	local c = cache[storeName]
	if c and os.clock() - c.t < Config.Leaderboard.CacheSeconds then
		return c.entries
	end
	if fetching[storeName] then
		local t0 = os.clock()
		while fetching[storeName] and os.clock() - t0 < 8 do
			task.wait(0.1)
		end
		local c2 = cache[storeName]
		return if c2 then c2.entries else {}
	end
	fetching[storeName] = true
	local entries = {}
	local s = store(storeName)
	if s then
		local ok, pages = pcall(function()
			return s:GetSortedAsync(ascending, Config.Leaderboard.TopCount)
		end)
		if ok and pages then
			for i, item in pages:GetCurrentPage() do
				local uid = tonumber(item.key)
				if uid then
					table.insert(entries, { userId = uid, name = nameOf(uid), value = item.value, rank = i })
				end
			end
		end
	end
	cache[storeName] = { t = os.clock(), entries = entries }
	fetching[storeName] = nil
	return entries
end

local function patchCache(storeName: string, userId: number, value: number, ascending: boolean)
	local c = cache[storeName]
	if not c then
		return
	end
	local found = false
	for _, e in c.entries do
		if e.userId == userId then
			e.value = value
			found = true
		end
	end
	if not found then
		table.insert(c.entries, { userId = userId, name = nameOf(userId), value = value, rank = 0 })
	end
	table.sort(c.entries, function(a, b)
		if ascending then
			return a.value < b.value
		end
		return a.value > b.value
	end)
	while #c.entries > Config.Leaderboard.TopCount do
		table.remove(c.entries)
	end
	for i, e in c.entries do
		e.rank = i
	end
end

-- Keeps the better value (lower if ascending)
function L.SubmitBest(storeName: string, userId: number, value: number, ascending: boolean)
	value = math.floor(value)
	local s = store(storeName)
	if s then
		task.spawn(function()
			local ok, err = pcall(function()
				s:UpdateAsync(tostring(userId), function(old)
					if old then
						if ascending and old <= value then
							return nil
						end
						if not ascending and old >= value then
							return nil
						end
					end
					return value
				end)
			end)
			if not ok then
				warn("[GoTrack] Leaderboard submit failed", err)
			end
		end)
	end
	patchCache(storeName, userId, value, ascending)
end

-- Always overwrites (ranked points can go down)
function L.SetValue(storeName: string, userId: number, value: number, ascending: boolean)
	value = math.max(0, math.floor(value))
	local s = store(storeName)
	if s then
		task.spawn(function()
			pcall(function()
				s:SetAsync(tostring(userId), value)
			end)
		end)
	end
	patchCache(storeName, userId, value, ascending)
end

-- Ghosts ---------------------------------------------------------------------
local ghostCache = {}

function L.SaveGhost(trackId: string, userId: number, ghost)
	local key = trackId .. "_" .. userId
	ghostCache[key] = { t = os.clock(), g = ghost }
	local gs = ghostStore
	if not gs then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			gs:UpdateAsync(key, function(old)
				if typeof(old) == "table" and typeof(old.ms) == "number" and old.ms <= ghost.ms then
					return nil
				end
				return ghost
			end)
		end)
		if not ok then
			warn("[GoTrack] Ghost save failed", err)
		end
	end)
end

function L.GetGhost(trackId: string, userId: number)
	local key = trackId .. "_" .. userId
	local c = ghostCache[key]
	if c and os.clock() - c.t < 300 then
		return c.g
	end
	local gs = ghostStore
	if not gs then
		return if c then c.g else nil
	end
	local ok, g = pcall(function()
		return gs:GetAsync(key)
	end)
	if ok then
		ghostCache[key] = { t = os.clock(), g = g }
		return g
	end
	return if c then c.g else nil
end

return L
