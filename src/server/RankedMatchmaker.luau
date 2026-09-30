--!nonstrict
-- Ranked matchmaking across servers. Real players only, never computer drivers.
--  * Lobby servers put ranked players in one queue shared by every server (a MemoryStore
--    sorted map keyed by user id, sorted by RP). One server at a time (a short lock)
--    groups the queue into matches: a full grid at once, or fewer players the longer the
--    oldest has waited (Config.Ranked.Queue.Steps), with an RP window that widens with
--    the wait. Each match gets a reserved server; every lobby server teleports its own
--    matched players there.
--  * A reserved server is a match server: its players arrive with the match in their
--    teleport data; RaceManager runs one ranked race with exactly them (map vote, race,
--    results) and then everyone is sent back to a public server.
--  * In Studio (no teleports, no shared queue) ranked stays on the local server and waits
--    for real players there (Test > Clients and Servers).
-- Profiles are saved and released before each teleport (DataService.ReleaseForTeleport),
-- so the next server loads them at once and nothing is lost.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Circuits = require(Shared.Circuits)

local DataService = require(script.Parent.DataService)

local MM = {}

local Q = Config.Ranked.Queue
local ENTRY_TTL = 60 -- a queue entry its server stops refreshing disappears after this
local MATCH_TTL = 120

local queueMap, matchMap, lockMap
local queued: { [Player]: { since: number, t: number, rp: number, refreshed: number } } = {}
local teleporting: { [Player]: boolean } = {}
local deps = {
	notify = function(_p, _m, _k) end,
	lobby = function(_p, _info) end,
	onMatchPlayer = function(_p, _match) end,
	rpOf = function(_p)
		return 0
	end,
}
local queueSize = 0
local sizeCheckedAt = 0

-- a reserved (matchmaking) server: private, but not a player-owned VIP server
function MM.IsMatchServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- the shared cross-server queue is available (live game, not Studio)
function MM.Enabled(): boolean
	return not RunService:IsStudio() and game.PlaceId ~= 0 and queueMap ~= nil
end

-- Whether the player is searching for a ranked match.
function MM.IsQueued(p: Player): boolean
	return queued[p] ~= nil
end

---------------------------------------------------------------------------
-- Grouping (pure: tested in tools/sim/ranked.luau)
---------------------------------------------------------------------------
-- racers needed to start once the longest-waiting player has queued `wait` seconds
function MM.Needed(wait: number): number
	local need = Q.Steps[1][2]
	for _, step in Q.Steps do
		if wait >= step[1] then
			need = step[2]
		end
	end
	return math.max(Q.MinRacers, need)
end

-- entries: { { u = userId, rp = number, t = queuedAt } }. Returns groups of entries,
-- oldest-waiting players first; everyone in a group is within the RP window of the
-- group's anchor (the longest waiter), which widens the longer they wait.
function MM.FormMatches(entries, now: number)
	local open = {}
	for _, e in entries do
		if typeof(e) == "table" and e.u and e.rp and e.t then
			table.insert(open, e)
		end
	end
	table.sort(open, function(a, b)
		return a.t < b.t
	end)
	local used, groups = {}, {}
	for _, anchor in open do
		if not used[anchor.u] then
			local wait = now - anchor.t
			local window = Config.Ranked.MatchmakingSpread + wait * Q.SpreadPerSecond
			local near = {}
			for _, e in open do
				if not used[e.u] and math.abs(e.rp - anchor.rp) <= window then
					table.insert(near, e)
				end
			end
			if #near >= MM.Needed(wait) then
				-- the anchor plus the closest ratings, up to a full grid
				table.sort(near, function(a, b)
					if a == anchor then
						return true
					elseif b == anchor then
						return false
					end
					return math.abs(a.rp - anchor.rp) < math.abs(b.rp - anchor.rp)
				end)
				local group = {}
				for i = 1, math.min(#near, Config.Race.MaxRacers) do
					table.insert(group, near[i])
					used[near[i].u] = true
				end
				table.insert(groups, group)
			end
		end
	end
	return groups
end

-- three random circuits to vote on
local function candidates(): { string }
	local pool = {}
	for _, c in Circuits.List do
		table.insert(pool, c.Id)
	end
	local out = {}
	for _ = 1, 3 do
		local i = math.random(1, #pool)
		table.insert(out, pool[i])
		table.remove(pool, i)
	end
	return out
end

---------------------------------------------------------------------------
-- Queue (lobby servers)
---------------------------------------------------------------------------
local function searchingInfo(p: Player)
	local q = queued[p]
	return {
		Id = "Q",
		Mode = "ranked",
		Searching = true,
		Since = if q then q.since else workspace:GetServerTimeNow(),
		Queue = math.max(queueSize, 1),
		Count = 1,
		Max = Config.Race.MaxRacers,
		EndsAt = workspace:GetServerTimeNow(),
	}
end

-- Puts (or refreshes) the player's entry in the shared queue. Entries expire after
-- ENTRY_TTL, so a crashed server's players drop out on their own.
local function writeEntry(p: Player, q)
	queueMap:SetAsync(tostring(p.UserId), { u = p.UserId, rp = q.rp, t = q.t, job = game.JobId }, ENTRY_TTL, q.rp)
	q.refreshed = os.clock()
end

-- Starts searching for a ranked match.
function MM.Join(p: Player)
	if queued[p] then
		return { ok = true, lobby = searchingInfo(p) }
	end
	local q = { since = workspace:GetServerTimeNow(), t = os.time(), rp = deps.rpOf(p), refreshed = 0 }
	local ok, err = pcall(writeEntry, p, q)
	if not ok then
		warn("[GoTrack] Ranked queue join failed:", err)
		return { ok = false, err = "Ranked matchmaking is busy - try again in a moment" }
	end
	queued[p] = q
	queueSize += 1
	return { ok = true, lobby = searchingInfo(p) }
end

-- Stops searching.
function MM.Leave(p: Player)
	if not queued[p] then
		return
	end
	queued[p] = nil
	task.spawn(pcall, function()
		queueMap:RemoveAsync(tostring(p.UserId))
	end)
end

-- the lock holder groups the queue and reserves a server per match
local function matchTick()
	local got = lockMap:UpdateAsync("lock", function(old)
		if typeof(old) == "table" and old.job ~= game.JobId then
			return nil
		end
		return { job = game.JobId }
	end, 8)
	if not (typeof(got) == "table" and got.job == game.JobId) then
		return
	end
	local rows = queueMap:GetRangeAsync(Enum.SortDirection.Ascending, 200)
	local entries = {}
	for _, row in rows do
		table.insert(entries, row.value)
	end
	queueSize = #entries
	for _, group in MM.FormMatches(entries, os.time()) do
		local code = TeleportService:ReserveServer(game.PlaceId)
		local users = {}
		for _, e in group do
			table.insert(users, e.u)
		end
		local match =
			{ id = HttpService:GenerateGUID(false), code = code, users = users, cands = candidates(), t = os.time() }
		for _, e in group do
			local rec = table.clone(match)
			rec.qt = e.t -- which queue entry this answers (see lobbyTick)
			matchMap:SetAsync(tostring(e.u), rec, MATCH_TTL)
			queueMap:RemoveAsync(tostring(e.u))
		end
	end
end

-- teleport this server's matched players; refresh everyone still waiting
local function lobbyTick()
	local byMatch = {}
	for p, q in queued do
		if not p.Parent then
			queued[p] = nil
		else
			local ok, match = pcall(function()
				return matchMap:GetAsync(tostring(p.UserId))
			end)
			-- only the match made for this queue entry (not one left over from an earlier queue)
			if ok and typeof(match) == "table" and match.code and match.qt == q.t then
				byMatch[match.id] = byMatch[match.id] or { match = match, players = {} }
				table.insert(byMatch[match.id].players, p)
			elseif os.clock() - q.refreshed > 15 then
				pcall(writeEntry, p, q)
			end
		end
	end
	for _, m in byMatch do
		local go = {}
		for _, p in m.players do
			queued[p] = nil
			deps.lobby(p, {
				Id = "Q",
				Mode = "ranked",
				Found = true,
				Count = #m.match.users,
				Max = Config.Race.MaxRacers,
				EndsAt = workspace:GetServerTimeNow(),
			})
			pcall(function()
				matchMap:RemoveAsync(tostring(p.UserId))
			end)
			if DataService.ReleaseForTeleport(p) then
				teleporting[p] = true
				table.insert(go, p)
			else
				deps.lobby(p, nil)
				deps.notify(p, "Couldn't save your progress - match skipped. Please queue again.", "error")
			end
		end
		if #go > 0 then
			local opts = Instance.new("TeleportOptions")
			opts.ReservedServerAccessCode = m.match.code
			opts:SetTeleportData({ ranked = { id = m.match.id, users = m.match.users, cands = m.match.cands } })
			local ok, err = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, go, opts)
			end)
			if not ok then
				warn("[GoTrack] Ranked teleport failed:", err)
				for _, p in go do
					MM.TeleportFailed(p)
				end
			end
		end
	end
	if next(queued) and os.clock() - sizeCheckedAt > 6 then
		-- how many are searching across every server (shown on the searching panel)
		sizeCheckedAt = os.clock()
		local okSize, rows = pcall(function()
			return queueMap:GetRangeAsync(Enum.SortDirection.Ascending, 200)
		end)
		if okSize then
			queueSize = #rows
		end
	end
	for p in queued do
		deps.lobby(p, searchingInfo(p))
	end
end

-- The teleport to the match server failed: take the save back and put the player
-- back in the menu (or ask them to rejoin if even that fails).
function MM.TeleportFailed(p: Player)
	if not teleporting[p] then
		return
	end
	teleporting[p] = nil
	if not DataService.Reclaim(p) then
		p:Kick("Your ranked match couldn't start. Please rejoin GoTrack Racing.")
		return
	end
	deps.lobby(p, nil)
	deps.notify(p, "Couldn't join the ranked match - please queue again.", "error")
end

---------------------------------------------------------------------------
-- Match servers
---------------------------------------------------------------------------
local currentMatch = nil

-- On a match server, the match the players were sent here for (nil elsewhere).
function MM.Match()
	return currentMatch
end

-- send players back to a normal public server (after the race, or if the match fails)
function MM.ReturnToLobby(players: { Player }, message: string?)
	local go = {}
	for _, p in players do
		if p.Parent and not teleporting[p] then
			if message then
				deps.notify(p, message, "info")
			end
			if DataService.ReleaseForTeleport(p) then
				teleporting[p] = true
				table.insert(go, p)
			end
		end
	end
	if #go == 0 then
		return
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, go)
		end)
		if ok then
			return
		end
		warn("[GoTrack] Return teleport failed:", err)
		task.wait(attempt * 2)
	end
	for _, p in go do
		if p.Parent then
			p:Kick("Your ranked race is over. Rejoin GoTrack Racing to keep racing!")
		end
	end
end

-- Match server: reads the match from the arriving player's teleport data.
local function onMatchPlayerAdded(p: Player)
	local ok, join = pcall(function()
		return p:GetJoinData()
	end)
	local data = ok and join and join.TeleportData
	local match = typeof(data) == "table" and data.ranked or nil
	if typeof(match) == "table" and not currentMatch then
		currentMatch = match
	end
	local expected = currentMatch and table.find(currentMatch.users or {}, p.UserId)
	if not expected then
		-- not part of this match (e.g. followed a friend): back to a public server
		task.delay(3, MM.ReturnToLobby, { p }, "This server is running a ranked match - taking you back to the lobby.")
		return
	end
	if not DataService.WaitFor(p, 30) then
		return
	end
	deps.onMatchPlayer(p, currentMatch)
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
function MM.Start(d)
	for k, v in d do
		deps[k] = v
	end
	TeleportService.TeleportInitFailed:Connect(function(p)
		if MM.IsMatchServer() then
			teleporting[p] = nil
			DataService.Reclaim(p)
			deps.notify(p, "Couldn't take you back to the lobby - please rejoin the game.", "error")
		else
			MM.TeleportFailed(p)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		MM.Leave(p)
		teleporting[p] = nil
	end)
	if MM.IsMatchServer() then
		Players.PlayerAdded:Connect(onMatchPlayerAdded)
		for _, p in Players:GetPlayers() do
			task.spawn(onMatchPlayerAdded, p)
		end
		return
	end
	if RunService:IsStudio() or game.PlaceId == 0 then
		return -- Studio: ranked stays on this server (RaceManager's local lobby)
	end
	local ok, err = pcall(function()
		queueMap = MemoryStoreService:GetSortedMap("GTR_RankedQueue")
		matchMap = MemoryStoreService:GetSortedMap("GTR_RankedMatch")
		lockMap = MemoryStoreService:GetSortedMap("GTR_RankedLock")
	end)
	if not ok then
		warn("[GoTrack] MemoryStore unavailable, ranked stays on this server:", err)
		queueMap = nil
		return
	end
	task.spawn(function()
		while true do
			task.wait(2 + math.random())
			if next(queued) then
				local okL, errL = pcall(lobbyTick)
				if not okL then
					warn("[GoTrack] Ranked lobby tick:", errL)
				end
			end
			local okM, errM = pcall(matchTick)
			if not okM then
				warn("[GoTrack] Ranked match tick:", errM)
			end
		end
	end)
end

return MM
