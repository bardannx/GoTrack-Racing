--!nonstrict
-- Runs every multiplayer race on the server, from the lobby to the results.
--
-- Lobbies: Quick Race (pick a circuit), Ranked (vote on a circuit) and friends-only
-- private races. A Quick Race fills its empty grid slots with computer drivers; ranked
-- never does. On a live server ranked players are matched across servers and raced on
-- their own match server (RankedMatchmaker); in Studio they wait for a second player on
-- the same server.
--
-- Races: each client drives its own car and streams its position here. The server keeps
-- the order, checks that every lap passed the timing gates in order, relays everyone's
-- position to everyone else, drives the computer cars and hands out coins, XP and RP.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Track = require(Shared.Track)
local Circuits = require(Shared.Circuits)
local Cosmetics = require(Shared.Cosmetics)

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local ChallengeService = require(script.Parent.ChallengeService)
local Matchmaker = require(script.Parent.RankedMatchmaker)

local RM = {}

local RC = Config.Race
local QUEUE = Config.Ranked.Queue
local AERO = Config.Car.ActiveAero or { Enabled = false, TopSpeedBonus = 0 }
local lobbies = {}
local sessions = {}
local playerLobby = {}
local playerSession = {}
local idCounter = 0

local LobbyEvent, StartEvent, GateEvent, StandingsEvent, ResultsEvent, LeaveEvent
local StateIn, StatesOut
local notify = function(_p, _m, _k) end

-- Shared clock: the same on the server and every client, so start lights and lap times agree.
local function now(): number
	return workspace:GetServerTimeNow()
end

-- Short unique id for a lobby ("L3") or a race session ("S7").
local function newId(prefix: string): string
	idCounter += 1
	return prefix .. idCounter
end

-- Any circuit, for when nobody picked one.
local function randomTrack(): string
	return Circuits.List[math.random(1, #Circuits.List)].Id
end

---------------------------------------------------------------------------
-- Lobbies
---------------------------------------------------------------------------
local function voteCounts(l)
	local counts = {}
	for _, id in l.Candidates or {} do
		counts[id] = 0
	end
	for p, id in l.Votes or {} do
		if p.Parent and counts[id] then
			counts[id] += 1
		end
	end
	return counts
end

-- What a client needs to draw a lobby: players, circuit, countdown, map vote.
local function lobbyInfo(l, forPlayer: Player?)
	local names = {}
	for _, p in l.Players do
		table.insert(names, p.DisplayName)
	end
	return {
		Id = l.Id,
		Mode = l.Mode,
		TrackId = if l.Candidates then nil else l.TrackId,
		Candidates = l.Candidates,
		Votes = if l.Candidates then voteCounts(l) else nil,
		MyVote = if l.Candidates and forPlayer and l.Votes then l.Votes[forPlayer] else nil,
		AvgRp = l.AvgRp,
		Count = #l.Players,
		Max = RC.MaxRacers,
		EndsAt = l.EndsAt,
		HostName = if l.Host then l.Host.DisplayName else "",
		HostId = if l.Host then l.Host.UserId else 0,
		Private = l.Private == true,
		Laps = l.Laps or Track.Get(l.TrackId).Laps,
		Names = names,
		Waiting = l.Waiting == true,
		Expected = l.Expected,
		Created = l.Created,
	}
end

-- A player's ranked points (new players start at Config.Ranked.StartRP).
local function rpOf(p: Player): number
	local d = DataService.Get(p)
	return if d then (d.rp or Config.Ranked.StartRP) else Config.Ranked.StartRP
end

-- Sends the latest lobby state to everyone in it.
local function pushLobby(l)
	if l.Mode == "ranked" then
		local sum = 0
		for _, p in l.Players do
			sum += rpOf(p)
		end
		l.AvgRp = if #l.Players > 0 then math.floor(sum / #l.Players) else 0
	end
	for _, p in l.Players do
		LobbyEvent:FireClient(p, lobbyInfo(l, p))
	end
end

-- Takes a player out of their lobby; an empty lobby is closed.
local function removeFromLobby(p: Player, silent: boolean?)
	local l = playerLobby[p]
	if not l then
		return
	end
	playerLobby[p] = nil
	local i = table.find(l.Players, p)
	if i then
		table.remove(l.Players, i)
	end
	if l.Votes then
		l.Votes[p] = nil
	end
	if not silent then
		LobbyEvent:FireClient(p, nil)
	end
	if #l.Players == 0 then
		lobbies[l.Id] = nil
	else
		if l.Host == p then
			l.Host = l.Players[1]
		end
		pushLobby(l)
	end
end

-- Puts a player in a lobby. A full grid starts in 3 seconds.
local function addToLobby(p: Player, l)
	removeFromLobby(p, true)
	table.insert(l.Players, p)
	playerLobby[p] = l
	if #l.Players >= RC.MaxRacers then
		l.EndsAt = math.min(l.EndsAt, now() + 3)
	end
	if l.Waiting and #l.Players >= QUEUE.MinRacers then
		-- a rival arrived: time to vote for the circuit
		l.Waiting = false
		l.EndsAt = now() + QUEUE.VoteSeconds
	end
	pushLobby(l)
end

-- Opens a new lobby with `host` in it.
local function createLobby(mode: string, trackId: string, host: Player, private: boolean?, laps: number?)
	local l = {
		Id = newId("L"),
		Mode = mode,
		TrackId = trackId,
		Host = host,
		Players = {},
		Created = now(),
		EndsAt = now() + (if mode == "ranked" then RC.RankedCountdown else RC.QuickCountdown),
		Private = private,
		Laps = laps,
	}
	if mode == "ranked" then
		-- three random circuits to vote on
		local pool = {}
		for _, c in Circuits.List do
			table.insert(pool, c.Id)
		end
		l.Candidates = {}
		for _ = 1, 3 do
			table.insert(l.Candidates, table.remove(pool, math.random(1, #pool)))
		end
		l.Votes = {}
		l.TrackId = l.Candidates[1]
	end
	lobbies[l.Id] = l
	return l
end

local friendCache = {}
-- Friend check for private lobbies (cached, it's a web call).
local function isFriend(p: Player, userId: number): boolean
	if p.UserId == userId then
		return true
	end
	local key = p.UserId .. ":" .. userId
	if friendCache[key] ~= nil then
		return friendCache[key]
	end
	local ok, res = pcall(function()
		return (p :: any):IsFriendsWithAsync(userId)
	end)
	if not ok then
		ok, res = pcall(function()
			return (p :: any):IsFriendsWith(userId)
		end)
	end
	friendCache[key] = ok and res == true
	return friendCache[key]
end

-- Open lobbies this player can see (private ones only if they're the host's friend).
function RM.GetLobbies(p: Player)
	local out = {}
	for _, l in lobbies do
		if not l.Private or (l.Host and isFriend(p, l.Host.UserId)) then
			table.insert(out, lobbyInfo(l, p))
		end
	end
	table.sort(out, function(a, b)
		return a.EndsAt < b.EndsAt
	end)
	return { ok = true, lobbies = out, mine = if playerLobby[p] then playerLobby[p].Id else nil }
end

-- Joins an open Quick Race lobby on that circuit, or opens a new one.
function RM.QuickRace(p: Player, trackId: any, private: any, laps: any)
	if playerSession[p] then
		return { ok = false, err = "You're already in a race" }
	end
	if Matchmaker.IsMatchServer() then
		return { ok = false, err = "This server is for your ranked match" }
	end
	Matchmaker.Leave(p)
	if trackId ~= "random" and not Circuits.ById[trackId] then
		return { ok = false, err = "Unknown circuit" }
	end
	if private then
		if not MonetizationService.Has(p, "PrivateRaces") then
			return { ok = false, err = "Private races need the Private Races pass" }
		end
		local tid = if trackId == "random" then randomTrack() else trackId
		local l =
			createLobby("quick", tid, p, true, math.clamp(math.floor(tonumber(laps) or Track.Get(tid).Laps), 1, 10))
		addToLobby(p, l)
		return { ok = true, lobby = lobbyInfo(l, p) }
	end
	-- join an open lobby for the same circuit (or any circuit for "random")
	local best = nil
	for _, l in lobbies do
		if
			l.Mode == "quick"
			and not l.Private
			and #l.Players < RC.MaxRacers
			and l.EndsAt - now() > 3
			and (trackId == "random" or l.TrackId == trackId)
		then
			if not best or l.EndsAt < best.EndsAt then
				best = l
			end
		end
	end
	if not best then
		best = createLobby("quick", if trackId == "random" then randomTrack() else trackId, p)
	end
	addToLobby(p, best)
	return { ok = true, lobby = lobbyInfo(best, p) }
end

-- Ranked: on a live server this joins the cross-server queue; in Studio it joins
-- the local ranked lobby; on a match server it just confirms the player's match.
function RM.RankedQueue(p: Player)
	if playerSession[p] then
		return { ok = false, err = "You're already in a race" }
	end
	if Matchmaker.IsMatchServer() then
		local l = playerLobby[p]
		if l then
			return { ok = true, lobby = lobbyInfo(l, p) }
		end
		task.spawn(Matchmaker.ReturnToLobby, { p })
		return { ok = false, err = "Your ranked race is over - heading back to the lobby" }
	end
	if Matchmaker.Enabled() then
		-- live game: the queue shared by every server (real players only)
		removeFromLobby(p, true)
		return Matchmaker.Join(p)
	end
	-- Studio: a ranked lobby on this server that waits for real players
	-- matchmaking: join the ranked lobby closest to your RP (the window widens as lobbies wait)
	local myRp = rpOf(p)
	local best, bestDiff = nil, math.huge
	for _, l in lobbies do
		if
			l.Mode == "ranked"
			and not l.Match
			and #l.Players < RC.MaxRacers
			and (l.Waiting or l.EndsAt - now() > 3)
			and not table.find(l.Players, p)
		then
			local diff = math.abs((l.AvgRp or myRp) - myRp)
			local allowed = Config.Ranked.MatchmakingSpread + (now() - l.Created) * 25
			if diff <= allowed and diff < bestDiff then
				best, bestDiff = l, diff
			end
		end
	end
	if not best then
		best = createLobby("ranked", randomTrack(), p)
	end
	addToLobby(p, best)
	return { ok = true, lobby = lobbyInfo(best, p) }
end

-- A vote for one of the ranked lobby's candidate circuits.
function RM.VoteMap(p: Player, trackId: any)
	local l = playerLobby[p]
	if not l or not l.Candidates or not table.find(l.Candidates, trackId) then
		return { ok = false, err = "Nothing to vote on" }
	end
	l.Votes[p] = trackId
	pushLobby(l)
	return { ok = true }
end

-- Joins a specific lobby from the list.
function RM.JoinLobby(p: Player, id: any)
	if playerSession[p] then
		return { ok = false, err = "You're already in a race" }
	end
	if Matchmaker.IsMatchServer() then
		return { ok = false, err = "This server is for your ranked match" }
	end
	local l = lobbies[id]
	if not l then
		return { ok = false, err = "That race already started" }
	end
	if #l.Players >= RC.MaxRacers then
		return { ok = false, err = "That race is full" }
	end
	if l.Private and not (l.Host and isFriend(p, l.Host.UserId)) then
		return { ok = false, err = "That race is friends-only" }
	end
	if l.Mode == "ranked" then
		-- same skill window as matchmaking, so a Champion can't farm a Bronze lobby
		local diff = math.abs((l.AvgRp or rpOf(p)) - rpOf(p))
		if diff > Config.Ranked.MatchmakingSpread + (now() - l.Created) * 25 then
			return { ok = false, err = "That ranked race is for a different rank" }
		end
	end
	addToLobby(p, l)
	return { ok = true, lobby = lobbyInfo(l, p) }
end

-- Leaves the lobby or the ranked queue.
function RM.LeaveLobby(p: Player)
	Matchmaker.Leave(p)
	local l = playerLobby[p]
	removeFromLobby(p)
	if l and l.Match then
		-- leaving a ranked match before the start: back to a public server
		task.spawn(Matchmaker.ReturnToLobby, { p })
	end
	return { ok = true }
end

-- Match server: a player of this server's ranked match has arrived
local matchLobby = nil
local matchStarted = false
function RM.MatchPlayer(p: Player, match)
	if matchStarted then
		Matchmaker.ReturnToLobby({ p }, "Your ranked race already started without you - back to the lobby.")
		return
	end
	if not matchLobby or not lobbies[matchLobby.Id] then
		matchLobby = createLobby("ranked", randomTrack(), p)
		local cands = {}
		for _, id in (typeof(match.cands) == "table" and match.cands) or {} do
			if Circuits.ById[id] then
				table.insert(cands, id)
			end
		end
		if #cands > 0 then
			matchLobby.Candidates = cands
			matchLobby.TrackId = cands[1]
		end
		matchLobby.Match = true
		matchLobby.Expected = math.max(1, #(match.users or {}))
		matchLobby.EndsAt = now() + QUEUE.MatchWait
	end
	addToLobby(p, matchLobby)
	if #matchLobby.Players >= matchLobby.Expected then
		matchLobby.EndsAt = math.min(matchLobby.EndsAt, now() + QUEUE.VoteSeconds)
		pushLobby(matchLobby)
	end
end

-- The host of a Quick Race skips the rest of the countdown.
function RM.StartNow(p: Player)
	local l = playerLobby[p]
	if not l or l.Host ~= p or l.Mode == "ranked" then
		return { ok = false, err = "Only the host can start early" }
	end
	l.EndsAt = math.min(l.EndsAt, now() + 3)
	pushLobby(l)
	return { ok = true }
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
local FREE_BODIES = { "gt1", "gt1", "aeros", "arrow", "falcon", "stealth", "vortex", "apex", "nova", "viper" }
local AI_PATTERNS =
	{ "pattern_stripe", "pattern_side", "pattern_split", "pattern_chevron", "pattern_none", "pattern_checker" }
local AI_HELMETS = { "helmet_white", "helmet_black", "helmet_red", "helmet_yellow", "helmet_blue", "helmet_green" }

-- A random paint for a computer driver (no rainbow or neon, those are earned).
local function randomPaint(): string
	local list = Cosmetics.ByCategory.Paint
	while true do
		local it = list[math.random(1, #list)]
		if not it.Rainbow and it.Material ~= Enum.Material.Neon then
			return it.Id
		end
	end
end

-- A computer driver's car: a free chassis in random colours.
local function aiCar(number: number)
	return {
		Body = FREE_BODIES[math.random(1, #FREE_BODIES)],
		Primary = randomPaint(),
		Secondary = randomPaint(),
		Accent = randomPaint(),
		RimColor = "paint_black",
		Helmet = AI_HELMETS[math.random(1, #AI_HELMETS)],
		Rims = "rims_classic",
		Pattern = AI_PATTERNS[math.random(1, #AI_PATTERNS)],
		Number = number,
	}
end

-- The player's equipped title, if it's not the default.
local function titleOf(p: Player): string?
	local t = p:GetAttribute("Title")
	return if typeof(t) == "string" and t ~= "Racer" then t else nil
end

-- Puts a racer on their grid slot, facing down the track.
local function gridState(s, r)
	local t = s.Track
	local gs, lat = Track.GridSlot(t, r.Slot)
	local x, y, z, tx, ty, tz = Track.PointAt(t, gs, lat)
	r.X, r.Y, r.Z = x, y + 2.55, z
	r.Yaw = math.atan2(-tx, -tz)
	r.Pitch = math.asin(math.clamp(ty, -1, 1))
	r.Roll = 0
	r.Speed = 0
	r.VX, r.VY, r.VZ = 0, 0, 0
	r.T = -RC.LoadTime
	r.Flags = 0
	r.LatVel = 0
	r.Dist = gs - t.Length
	r.Idx = Track.Wrap(t, math.floor(gs / Track.DS) + 1)
	r.Lateral = lat
	r.GhostUntil = 0
	r.LastReset = -100
end

-- Picks the circuit with the most votes (ties broken at random).
local function resolveVote(l)
	if not l.Candidates then
		return
	end
	local counts = voteCounts(l)
	local best, bestN = {}, -1
	for _, id in l.Candidates do
		local n = counts[id] or 0
		if n > bestN then
			best, bestN = { id }, n
		elseif n == bestN then
			table.insert(best, id)
		end
	end
	l.TrackId = best[math.random(1, #best)]
end

-- Turns a lobby into a race: fills the grid, sends everyone the start, and counts down.
local function startSession(l)
	lobbies[l.Id] = nil
	resolveVote(l)
	local t = Track.Get(l.TrackId)
	local s = {
		Id = newId("S"),
		Mode = l.Mode,
		Private = l.Private,
		TrackId = l.TrackId,
		Track = t,
		Laps = l.Laps or t.Laps,
		Racers = {},
		ByPlayer = {},
		LightsStart = now() + RC.LoadTime,
		State = "countdown",
		Fastest = nil,
	}
	s.GoTime = s.LightsStart + RC.CountdownSeconds -- 3, 2, 1 ... GO! (everyone released together)
	-- real players in random order
	local players = table.clone(l.Players)
	for i = #players, 2, -1 do
		local j = math.random(1, i)
		players[i], players[j] = players[j], players[i]
	end
	local usedNumbers = {}
	for _, p in players do
		if p.Parent then
			playerLobby[p] = nil
			local d = DataService.Get(p)
			local car = if d then d.car else Cosmetics.DefaultCar
			local num = Cosmetics.NumberFor(car, p.UserId)
			usedNumbers[num] = true
			local r = {
				Rid = #s.Racers + 1,
				Name = p.DisplayName,
				IsAI = false,
				Player = p,
				UserId = p.UserId,
				Car = car,
				Number = num,
				Title = titleOf(p),
				Rp = if d then d.rp else 0,
			}
			table.insert(s.Racers, r)
			s.ByPlayer[p] = r
			playerSession[p] = s
		end
	end
	if #s.Racers == 0 then
		return
	end
	if Matchmaker.IsMatchServer() then
		matchStarted = true
	end
	-- computer drivers fill the grid in Quick Race; Ranked is real players only
	if Config.AI.Enabled and s.Mode ~= "ranked" then
		local names = table.clone(Config.AI.Names)
		local skill = Config.AI.QuickSkill
		while #s.Racers < RC.MaxRacers do
			local ni = math.random(1, #names)
			local name = table.remove(names, ni)
			local num
			repeat
				num = math.random(2, 99)
			until not usedNumbers[num]
			usedNumbers[num] = true
			table.insert(s.Racers, {
				Rid = #s.Racers + 1,
				Name = name,
				IsAI = true,
				UserId = 0,
				Car = aiCar(num),
				Number = num,
				Skill = skill[1] + math.random() * (skill[2] - skill[1]),
				LatTimer = 0,
				LateralTarget = 0,
			})
		end
	end
	for i, r in s.Racers do
		r.Slot = i
		r.LapsDone = -1
		r.NextGate = 1
		r.GateCount = 0
		r.GateTimes = {}
		r.LastGateTime = -10
		r.Finished = false
		r.DNF = false
		gridState(s, r)
	end
	sessions[s.Id] = s
	-- tell the players
	local list = {}
	for _, r in s.Racers do
		table.insert(list, {
			Rid = r.Rid,
			Name = r.Name,
			IsAI = r.IsAI,
			UserId = r.UserId,
			Car = r.Car,
			Number = r.Number,
			Slot = r.Slot,
			Title = r.Title,
		})
	end
	for p, r in s.ByPlayer do
		LobbyEvent:FireClient(p, nil)
		StartEvent:FireClient(p, {
			SessionId = s.Id,
			Mode = s.Mode,
			TrackId = s.TrackId,
			Laps = s.Laps,
			Racers = list,
			YourRid = r.Rid,
			LightsStart = s.LightsStart,
			GoTime = s.GoTime,
		})
	end
end

-- A racer took the chequered flag.
local function finishRacer(s, r, raceTime: number)
	if r.Finished then
		return
	end
	r.Finished = true
	r.FinishTime = raceTime
	if not r.IsAI and not s.FirstRealFinish then
		s.FirstRealFinish = now()
	end
	if not s.FirstFinish then
		s.FirstFinish = now()
	end
end

-- Updates the racer's best lap and the race's fastest lap.
local function recordLap(s, r, lapTime: number)
	if not r.BestLap or lapTime < r.BestLap then
		r.BestLap = lapTime
	end
	if not s.Fastest or lapTime < s.Fastest.Time then
		s.Fastest = { Rid = r.Rid, Time = lapTime, Name = r.Name }
	end
end

-- a racer crossed global gate k (k = 0 is the first time across the start line)
local function crossGate(s, r, k: number, raceTime: number)
	r.GateTimes[k] = raceTime
	r.GateCount = k + 1
	local g = (k % Track.GateCount) + 1
	if g == 1 then
		if r.LapsDone >= 0 and r.LapStartTime then
			recordLap(s, r, raceTime - r.LapStartTime)
		end
		r.LapsDone += 1
		r.LapStartTime = raceTime
		if r.LapsDone >= s.Laps then
			finishRacer(s, r, raceTime)
		end
	end
	r.NextGate = (g % Track.GateCount) + 1
end

-- nearest racer ahead of `r` on track within `range` studs; returns (other, gap)
local function carAhead(s, r, range: number)
	local best, bestGap = nil, range
	local L = s.Track.Length
	for _, o in s.Racers do
		if o ~= r and not o.DNF and o.X and not o.Finished then
			local gap = ((o.Dist % L) - (r.Dist % L)) % L
			if gap > 0 and gap < bestGap and math.abs((o.Lateral or 0) - r.Lateral) < 7.5 then
				best, bestGap = o, gap
			end
		end
	end
	return best, bestGap
end

-- Computer driver's position from its distance along the track and sideways offset.
local function placeAI(s, r)
	local t = s.Track
	local x, y, z, tx, ty, tz = Track.PointAt(t, r.Dist % t.Length, r.Lateral)
	r.X, r.Y, r.Z = x, y + 2.55, z
	r.Yaw = math.atan2(-tx, -tz)
	r.Pitch = math.asin(math.clamp(ty, -1, 1))
	r.Roll = 0
	r.VX, r.VY, r.VZ =
		tx * r.Speed + t.RX[r.Idx or 1] * (r.LatVel or 0),
		ty * r.Speed,
		tz * r.Speed + t.RZ[r.Idx or 1] * (r.LatVel or 0)
end

-- Drives the computer cars: they follow the track's speed profile at their own skill
-- level, get the same active-aero boost as players, and pass or follow the car ahead
-- instead of driving into it.
local function stepAI(s, dt: number)
	local t = s.Track
	local L = t.Length
	local gateLen = L / Track.GateCount
	local tNow = now()
	if tNow < s.GoTime then
		return
	end
	local raceTime = tNow - s.GoTime
	local P = Track.Profile
	local maxLat = t.Width / 2 - 4
	for _, r in s.Racers do
		if r.IsAI and not r.Finished then
			local sm = r.Dist % L
			local look = math.max(8, r.Speed * 0.35)
			local base = math.min(Track.SpeedAt(t, sm + 8), Track.SpeedAt(t, sm + look))
			-- active aero on the straights, the same bonus players get (and the flap shows it)
			local aero = AERO.Enabled and base >= P.TopSpeed * 0.99 and r.Speed > P.TopSpeed * 0.8
			if aero then
				base *= 1 + AERO.TopSpeedBonus
			end
			r.Flags = if aero then Net.Flags.Aero else 0
			local target = base * r.Skill
			target *= 1 + 0.025 * math.sin(tNow * 0.35 + r.Rid * 1.7)
			-- racecraft: don't drive into the car ahead - pass it or follow it
			local ahead, gap = carAhead(s, r, 34)
			if ahead and gap < 34 then
				if r.Speed > (ahead.Speed or 0) - 2 then
					local side = if (ahead.Lateral or 0) > 0 then -1 else 1
					local room = maxLat - math.abs(ahead.Lateral or 0)
					if room > 9 then
						r.LateralTarget = math.clamp((ahead.Lateral or 0) + side * 9.5, -maxLat, maxLat)
						r.LatTimer = 2.5
					end
					if gap < 16 then
						target = math.min(target, (ahead.Speed or 0) - 1)
					end
				end
			end
			if r.Speed < target then
				local ratio = r.Speed / P.TopSpeed
				r.Speed = math.min(target, r.Speed + P.Accel * (1 - ratio * ratio * 0.8) * dt)
			else
				r.Speed = math.max(target, r.Speed - P.Brake * 1.1 * dt)
			end
			r.Speed = math.max(r.Speed, 0)
			local prev = r.Dist
			r.Dist += r.Speed * dt
			r.LatTimer -= dt
			if r.LatTimer <= 0 then
				r.LatTimer = 3 + math.random() * 4
				r.LateralTarget = (math.random() * 2 - 1) * t.Width * 0.26
			end
			-- bumps from players push the AI sideways, then it steers back
			r.LatVel = (r.LatVel or 0) * math.exp(-3 * dt)
			r.Lateral += (r.LateralTarget - r.Lateral) * math.min(1, 0.6 * dt) + r.LatVel * dt
			r.Lateral = math.clamp(r.Lateral, -maxLat, maxLat)
			-- gates
			local k0 = math.floor(prev / gateLen) + 1
			local k1 = math.floor(r.Dist / gateLen)
			for k = math.max(k0, 0), k1 do
				local frac = (k * gateLen - prev) / math.max(r.Dist - prev, 1e-3)
				crossGate(s, r, k, raceTime - dt * (1 - frac))
				if r.Finished then
					break
				end
			end
			r.Idx = Track.Wrap(t, math.floor(sm / Track.DS) + 1)
			placeAI(s, r)
			r.T = raceTime
		elseif r.IsAI and r.Finished then
			-- cool-down lap at a gentle pace
			r.Speed = math.max(60, r.Speed - 40 * dt)
			r.Dist += r.Speed * dt
			r.Idx = Track.Wrap(t, math.floor((r.Dist % L) / Track.DS) + 1)
			placeAI(s, r)
			r.T = raceTime
		end
	end
end

-- server-authoritative "no contact" windows
local function isGhost(s, r, tNow: number): boolean
	if tNow < s.GoTime + Config.Contact.GhostStartSeconds then
		return true
	end
	if r.Finished or r.DNF then
		return true
	end
	if tNow < (r.GhostUntil or 0) then
		return true
	end
	return (r.WrongWayTime or 0) > 0.8
end

-- Race order: finishers by time, then everyone still racing by distance, DNFs last.
local function standingsOrder(s)
	local list = {}
	for _, r in s.Racers do
		table.insert(list, r)
	end
	table.sort(list, function(a, b)
		if a.Finished ~= b.Finished then
			return a.Finished
		end
		if a.Finished and b.Finished then
			return a.FinishTime < b.FinishTime
		end
		if a.DNF ~= b.DNF then
			return not a.DNF
		end
		return a.Dist > b.Dist
	end)
	return list
end

-- Gap to the leader: (seconds, 0) when both passed the same gate, or (nil, laps down).
local function gapInfo(leader, r)
	if r == leader then
		return nil, 0
	end
	if r.Finished and leader.Finished then
		return r.FinishTime - leader.FinishTime, 0
	end
	local lapped = math.floor((leader.GateCount - r.GateCount) / Track.GateCount)
	if lapped >= 1 then
		return nil, lapped
	end
	local k = r.GateCount - 1
	if k >= 0 and leader.GateTimes[k] and r.GateTimes[k] then
		return r.GateTimes[k] - leader.GateTimes[k], 0
	end
	return nil, 0
end

-- Sends the live order, gaps and fastest lap to every racer.
local function sendStandings(s)
	local order = standingsOrder(s)
	local leader = order[1]
	local list = {}
	for pos, r in order do
		r.Pos = pos
		local gap, lapped = gapInfo(leader, r)
		table.insert(list, {
			Rid = r.Rid,
			P = pos,
			L = math.max(r.LapsDone, 0),
			F = r.Finished,
			D = r.DNF,
			G = gap,
			LP = lapped,
			B = r.BestLap,
			NG = r.NextGate,
			FT = r.FinishTime,
		})
	end
	local payload = { T = now() - s.GoTime, List = list, Fastest = s.Fastest }
	for p, r in s.ByPlayer do
		if not r.LeftEarly then
			StandingsEvent:FireClient(p, payload)
		end
	end
end

-- Final results: pays coins and XP, updates stats, challenges, ranked RP and
-- leaderboards, then shows everyone the results screen.
local function endSession(s)
	if s.State == "ended" then
		return
	end
	s.State = "ended"
	local order = standingsOrder(s)
	local results = {}
	local leader = order[1]
	for pos, r in order do
		local gap, lapped = gapInfo(leader, r)
		table.insert(results, {
			Rid = r.Rid,
			Name = r.Name,
			IsAI = r.IsAI,
			P = pos,
			Finished = r.Finished,
			DNF = r.DNF or not r.Finished,
			Time = r.FinishTime,
			Gap = gap,
			Lapped = lapped,
			Best = r.BestLap,
			Number = r.Number,
			Car = r.Car,
			UserId = r.UserId,
		})
	end
	local econ = Config.Economy
	for p, r in s.ByPlayer do
		local d = DataService.Get(p)
		local you = { Pos = r.Pos or #order }
		if d and p.Parent then
			local pos = r.Pos or #order
			local finished = r.Finished
			local coins = if finished then (econ.PositionCoins[pos] or econ.DNFCoins) else econ.DNFCoins
			local xp = if finished then (econ.PositionXP[pos] or 20) else 10
			local fastest = s.Fastest and s.Fastest.Rid == r.Rid
			if fastest then
				coins += econ.FastestLapCoins
				d.stats.fastestLaps += 1
			end
			-- this week's featured circuit pays bonus coins
			local featured = s.TrackId == ChallengeService.Featured()
			if featured then
				coins = math.floor(coins * Config.Economy.FeaturedCoinMultiplier + 0.5)
			end
			coins = math.floor(coins * MonetizationService.CoinMultiplier(p) + 0.5)
			xp = math.floor(xp * MonetizationService.XPMultiplier(p) + 0.5)
			d.coins += coins
			d.xp += xp
			local leveled = false
			while d.xp >= Config.XPForLevel(d.level) do
				d.xp -= Config.XPForLevel(d.level)
				d.level += 1
				leveled = true
			end
			d.stats.races += 1
			local lapsDone = math.clamp(r.LapsDone or 0, 0, s.Laps)
			d.stats.laps += lapsDone
			ChallengeService.RaceResult(d, {
				finished = finished,
				pos = pos,
				laps = lapsDone,
				ranked = s.Mode == "ranked",
				trackId = s.TrackId,
				fastest = fastest,
			})
			if finished and pos == 1 then
				d.stats.wins += 1
				LeaderboardService.SubmitBest(Config.DataStores.Wins, p.UserId, d.stats.wins, false)
			end
			if finished and pos <= 3 then
				d.stats.podiums += 1
			end
			local rpDelta = nil
			local oldRp = nil
			if s.Mode == "ranked" then
				-- a smaller field spreads the same table: last place is always the last slot
				local n = #order
				local slot = if n <= 1
					then 1
					else math.floor(1 + (pos - 1) * (#Config.Ranked.PositionRP - 1) / (n - 1) + 0.5)
				local worst = Config.Ranked.PositionRP[#Config.Ranked.PositionRP]
				rpDelta = if finished then (Config.Ranked.PositionRP[slot] or worst) else worst
				oldRp = d.rp or Config.Ranked.StartRP
				d.rp = math.max(0, oldRp + rpDelta)
				-- peak RP unlocks rank-tier cosmetics and decides the season reward
				d.peakRp = math.max(d.peakRp or 0, d.rp)
				d.stats.rankedRaces += 1
				RM.AddHistory(d, s, if finished then pos else nil, d.rp - oldRp)
				LeaderboardService.SetValue(Config.RankedBoard(), p.UserId, d.rp, false)
			end
			if leveled then
				LeaderboardService.SetValue(Config.DataStores.Level, p.UserId, d.level * 1000000 + d.xp, false)
			end
			DataService.Changed(p)
			you = {
				Pos = pos,
				Coins = coins,
				XP = xp,
				LeveledUp = leveled,
				Level = d.level,
				RpDelta = rpDelta,
				Rp = d.rp,
				OldRp = oldRp,
				Fastest = fastest,
				Finished = finished,
				Featured = featured,
			}
		end
		ResultsEvent:FireClient(p, {
			SessionId = s.Id,
			Mode = s.Mode,
			TrackId = s.TrackId,
			Results = results,
			You = you,
			Fastest = s.Fastest,
			LeftEarly = r.LeftEarly,
		})
		if playerSession[p] == s then
			playerSession[p] = nil
		end
	end
	sessions[s.Id] = nil
	if s.Mode == "ranked" and Matchmaker.IsMatchServer() then
		-- the match is over: everyone back to a public server after the results screen
		task.delay(RC.ResultsSeconds + 2, function()
			Matchmaker.ReturnToLobby(Players:GetPlayers())
		end)
	end
end

-- Moves a race along: lights out, then the end once every player is home, the grace
-- time after the first finisher runs out, or the race runs far too long.
local function tickSession(s)
	if s.State == "ended" then
		return
	end
	local tNow = now()
	if s.State == "countdown" and tNow >= s.GoTime then
		s.State = "racing"
	end
	-- remove players who left the server
	local anyPlayer = false
	local allDone = true
	for p, r in s.ByPlayer do
		if not p.Parent then
			r.DNF = not r.Finished
			s.ByPlayer[p] = nil
			if playerSession[p] == s then
				playerSession[p] = nil
			end
		else
			anyPlayer = true
			if not r.Finished and not r.DNF then
				allDone = false
			end
		end
	end
	if not anyPlayer then
		sessions[s.Id] = nil
		s.State = "ended"
		return
	end
	if s.State ~= "racing" then
		return
	end
	if allDone then
		s.EndAt = s.EndAt or (tNow + 4)
	end
	if s.FirstRealFinish and tNow - s.FirstRealFinish > RC.FinishGrace then
		s.EndAt = s.EndAt or tNow
	end
	if s.FirstFinish and tNow - s.FirstFinish > RC.FinishGrace + 30 then
		s.EndAt = s.EndAt or tNow
	end
	-- hard cap, stretched for long (private) races so 10-lap races aren't cut off mid-race
	if tNow - s.GoTime > math.max(RC.MaxRaceSeconds, s.Track.IdealLap * s.Laps * 2.5 + 60) then
		s.EndAt = s.EndAt or tNow
	end
	if s.EndAt and tNow >= s.EndAt then
		sendStandings(s)
		endSession(s)
	end
end

---------------------------------------------------------------------------
-- Network handlers
---------------------------------------------------------------------------
local function onGate(p: Player, gate: any, clientTime: any)
	local s = playerSession[p]
	if not s or s.State ~= "racing" then
		return
	end
	local r = s.ByPlayer[p]
	if not r or r.Finished or r.DNF then
		return
	end
	if typeof(gate) ~= "number" or gate ~= r.NextGate then
		return
	end
	local t = s.Track
	local gi = t.Gates[gate]
	if math.abs(Track.IndexDelta(t, gi, r.Idx)) > 70 then
		return
	end
	local raceNow = now() - s.GoTime
	local ct = if typeof(clientTime) == "number" and clientTime == clientTime then clientTime else raceNow
	ct = math.clamp(ct, raceNow - 2.5, raceNow + 0.3)
	local minGap = (t.Length / Track.GateCount) / (Config.Car.TopSpeed * 1.45)
	if r.GateCount > 0 and ct - r.LastGateTime < minGap then
		return
	end
	r.LastGateTime = ct
	crossGate(s, r, r.GateCount, ct)
end

-- A player's car state (position, rotation, speed). Positions that are impossible
-- (too fast, not a number) are thrown away.
local function onState(p: Player, b: any)
	local s = playerSession[p]
	if not s or typeof(b) ~= "buffer" or buffer.len(b) ~= Net.StateSize then
		return
	end
	local r = s.ByPlayer[p]
	if not r or r.DNF then
		return
	end
	local ct, x, y, z, yaw, pitch, roll, vx, vy, vz, flags = Net.ReadState(b, 0)
	if x ~= x or y ~= y or z ~= z or vx ~= vx or ct ~= ct then
		return
	end
	local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
	if speed > 700 then
		return
	end
	local raceNow = now() - s.GoTime
	r.T = math.clamp(ct, raceNow - 1, raceNow + 0.2)
	r.X, r.Y, r.Z, r.Yaw, r.Pitch, r.Roll = x, y, z, yaw, pitch, roll
	r.VX, r.VY, r.VZ, r.Speed = vx, vy, vz, speed
	-- only damage bits come from the client; the ghost bit is decided here
	r.Flags = bit32.band(
		flags,
		bit32.bor(Net.Flags.FrontWing, Net.Flags.RearWing, Net.Flags.Smoke, Net.Flags.Brake, Net.Flags.Aero)
	)
	local t = s.Track
	local idx, lateral = Track.Project(t, x, y, z, r.Idx)
	r.Idx = idx
	r.Lateral = lateral
	-- wrong-way detection (for the no-contact rule)
	local tx, tz = t.TX[idx], t.TZ[idx]
	local tNow = os.clock()
	local dtw = math.min(tNow - (r.LastStateClock or tNow), 0.5)
	r.LastStateClock = tNow
	if speed > 15 and (vx * tx + vz * tz) / speed < -0.4 then
		r.WrongWayTime = (r.WrongWayTime or 0) + dtw
	else
		r.WrongWayTime = 0
	end
	local L = t.Length
	local sIdx = t.S[idx]
	local nextS = if r.NextGate == 1 then L else t.S[t.Gates[r.NextGate]]
	local prog = math.min(sIdx, nextS + 150)
	if r.NextGate == 2 and sIdx > L * 0.75 then
		prog = 0
	end
	r.Dist = r.LapsDone * L + prog
end

-- A player reset their car to the track.
local function onReset(p: Player)
	local s = playerSession[p]
	local r = s and s.ByPlayer[p]
	if not r then
		return
	end
	local tNow = now()
	if tNow - (r.LastReset or -100) < 2 then
		return -- rate limit
	end
	r.LastReset = tNow
	r.GhostUntil = tNow + Config.Damage.ResetRepairSeconds + Config.Contact.GhostResetSeconds
end

-- a player hit an AI car: push the AI (validated by distance)
local function onBump(p: Player, b: any)
	local s = playerSession[p]
	if not s or typeof(b) ~= "buffer" or buffer.len(b) ~= 5 then
		return
	end
	local me = s.ByPlayer[p]
	local ai = s.Racers[buffer.readu8(b, 0)]
	if not me or not ai or not ai.IsAI or ai.Finished or not me.X or not ai.X then
		return
	end
	local dx, dz = me.X - ai.X, me.Z - ai.Z
	if dx * dx + dz * dz > 20 * 20 then
		return
	end
	local ix = math.clamp(buffer.readi16(b, 1) / 10, -120, 120)
	local iz = math.clamp(buffer.readi16(b, 3) / 10, -120, 120)
	local t = s.Track
	local i = ai.Idx or 1
	local lat = ix * t.RX[i] + iz * t.RZ[i]
	local along = ix * t.TX[i] + iz * t.TZ[i]
	ai.LatVel = math.clamp((ai.LatVel or 0) + lat * 0.8, -40, 40)
	ai.Speed = math.max(0, ai.Speed + math.clamp(along, -60, 25))
end

-- Sends every racer's position to every other racer, RC.SendRate times a second,
-- plus the standings 4 times a second.
local function relayLoop()
	local interval = 1 / RC.SendRate
	local standingsTimer = 0
	local last = os.clock()
	local REC = 1 + Net.StateSize
	while true do
		task.wait(interval)
		local dtReal = os.clock() - last
		last = os.clock()
		standingsTimer += dtReal
		local sendStand = standingsTimer >= 0.25
		if sendStand then
			standingsTimer = 0
		end
		local tNow = now()
		for _, s in sessions do
			if s.State ~= "ended" then
				local n = #s.Racers
				local b = buffer.create(2 + n * REC)
				local count = 0
				for _, r in s.Racers do
					if r.X and not (r.DNF and not r.IsAI) then
						local off = 2 + count * REC
						local flags = r.Flags or 0
						if isGhost(s, r, tNow) then
							flags = bit32.bor(flags, Net.Flags.Ghost)
						end
						buffer.writeu8(b, off, r.Rid)
						Net.WriteState(
							b,
							off + 1,
							r.T or 0,
							r.X,
							r.Y,
							r.Z,
							r.Yaw or 0,
							r.Pitch or 0,
							r.Roll or 0,
							r.VX or 0,
							r.VY or 0,
							r.VZ or 0,
							flags
						)
						count += 1
					end
				end
				buffer.writeu16(b, 0, count)
				for p, r in s.ByPlayer do
					if not r.LeftEarly then
						StatesOut:FireClient(p, b)
					end
				end
				if sendStand and s.State == "racing" then
					sendStandings(s)
				end
			end
		end
	end
end

-- lobby timers: start races, keep ranked lobbies waiting for real rivals
local function lobbyTick(tNow: number)
	for _, l in lobbies do
		for i = #l.Players, 1, -1 do
			if not l.Players[i].Parent then
				table.remove(l.Players, i)
			end
		end
		if l.Match and tNow - (l.Pushed or 0) > 3 then
			-- players who just arrived may still be loading: keep their lobby panel fresh
			l.Pushed = tNow
			pushLobby(l)
		end
		if #l.Players == 0 then
			lobbies[l.Id] = nil
		elseif tNow >= l.EndsAt and l.Mode == "ranked" and #l.Players < QUEUE.MinRacers then
			-- ranked is real players only: never start a race without a rival
			if l.Match then
				lobbies[l.Id] = nil
				local back = table.clone(l.Players)
				for _, p in back do
					playerLobby[p] = nil
				end
				task.spawn(
					Matchmaker.ReturnToLobby,
					back,
					"Not enough racers made it to this match - no points lost. Back to the lobby!"
				)
			else
				l.Waiting = true
				l.EndsAt = tNow + 10
				pushLobby(l)
			end
		elseif tNow >= l.EndsAt then
			local ok, err = pcall(startSession, l)
			if not ok then
				warn("[GoTrack] Failed to start race:", err)
				lobbies[l.Id] = nil
				for _, p in l.Players do
					playerLobby[p] = nil
					-- a half-built session must not leave them stuck "already in a race"
					local half = playerSession[p]
					if half then
						playerSession[p] = nil
						sessions[half.Id] = nil
					end
					LobbyEvent:FireClient(p, nil)
					notify(p, "Couldn't start the race - please try again.", "error")
				end
			end
		end
	end
end

-- A player quit mid-race. Finishers keep their result; anyone else is out (DNF), and in
-- ranked it costs them Config.Ranked.LeaveRP.
function RM.PlayerLeftRace(p: Player)
	local s = playerSession[p]
	if not s then
		return
	end
	local r = s.ByPlayer[p]
	playerSession[p] = nil
	if r and r.Finished and p.Parent then
		-- finished racers keep their result & rewards; they just stop receiving updates
		r.LeftEarly = true
		return
	end
	if r then
		r.DNF = true
		if s.Mode == "ranked" and s.State ~= "ended" and not r.Penalized then
			r.Penalized = true
			local d = DataService.Get(p)
			if d then
				local old = d.rp or Config.Ranked.StartRP
				d.rp = math.max(0, old + Config.Ranked.LeaveRP)
				d.stats.rankedRaces += 1
				RM.AddHistory(d, s, nil, d.rp - old)
				LeaderboardService.SetValue(Config.RankedBoard(), p.UserId, d.rp, false)
				DataService.Changed(p)
			end
		end
	end
	s.ByPlayer[p] = nil
end

-- Adds a race to the player's recent-results list (the last 10 are kept).
function RM.AddHistory(d, s, pos: number?, delta: number)
	d.history = d.history or {}
	table.insert(d.history, { t = s.TrackId, p = pos, d = delta, at = os.time(), n = #s.Racers })
	while #d.history > 10 do
		table.remove(d.history, 1)
	end
end

-- Whether the player is in a race right now.
function RM.InRace(p: Player): boolean
	return playerSession[p] ~= nil
end

-- How to show a player a toast (set by init.server).
function RM.SetNotifier(fn)
	notify = fn
end

-- Creates the race remotes and starts the lobby, race and relay loops.
function RM.Init()
	LobbyEvent = Net.Event("LobbyUpdate")
	StartEvent = Net.Event("RaceStart")
	GateEvent = Net.Event("RaceGate")
	StandingsEvent = Net.Event("RaceStandings")
	ResultsEvent = Net.Event("RaceResults")
	LeaveEvent = Net.Event("RaceLeave")
	StateIn = Net.UEvent("CarState")
	StatesOut = Net.UEvent("CarStates")

	GateEvent.OnServerEvent:Connect(onGate)
	StateIn.OnServerEvent:Connect(onState)
	Net.Event("RaceReset").OnServerEvent:Connect(onReset)
	Net.UEvent("Bump").OnServerEvent:Connect(onBump)
	LeaveEvent.OnServerEvent:Connect(function(p)
		local s = playerSession[p]
		local r = s and s.ByPlayer[p]
		RM.PlayerLeftRace(p)
		if Matchmaker.IsMatchServer() and not (r and r.Finished) then
			-- quit a ranked match: back to a public server (finishers go with everyone after the results)
			task.spawn(Matchmaker.ReturnToLobby, { p })
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		removeFromLobby(p, true)
		RM.PlayerLeftRace(p)
	end)

	-- lobby timers
	task.spawn(function()
		while true do
			task.wait(0.25)
			lobbyTick(now())
		end
	end)
	-- AI + session ticks
	RunService.Heartbeat:Connect(function(dt)
		for id, s in sessions do
			local ok, err = pcall(function()
				stepAI(s, math.min(dt, 0.1))
				tickSession(s)
			end)
			if not ok then
				-- a broken session must never trap its players: after a few failures, end
				-- it (results if possible) and free everyone
				s.Errors = (s.Errors or 0) + 1
				if s.Errors <= 3 then
					warn("[GoTrack] Session error:", err)
				end
				if s.Errors >= 30 then
					warn("[GoTrack] Ending broken session", id)
					local okEnd = pcall(endSession, s)
					sessions[id] = nil
					for p in s.ByPlayer do
						if playerSession[p] == s then
							playerSession[p] = nil
						end
						if not okEnd then
							LeaveEvent:FireClient(p)
							notify(p, "Something went wrong with that race - sorry! Please start a new one.", "error")
						end
					end
				end
			end
		end
	end)
	task.spawn(relayLoop)
	Matchmaker.Start({
		notify = function(p, msg, kind)
			notify(p, msg, kind)
		end,
		lobby = function(p, info)
			LobbyEvent:FireClient(p, info)
		end,
		onMatchPlayer = RM.MatchPlayer,
		rpOf = rpOf,
	})
end

-- exposed for automated tests
RM._test = {
	createLobby = createLobby,
	addToLobby = addToLobby,
	startSession = startSession,
	stepAI = stepAI,
	tickSession = tickSession,
	onGate = onGate,
	onState = onState,
	sendStandings = sendStandings,
	sessions = sessions,
	lobbies = lobbies,
	endSession = endSession,
	lobbyInfo = lobbyInfo,
	lobbyTick = lobbyTick,
	setEvents = function(ev)
		LobbyEvent, StartEvent, GateEvent, StandingsEvent, ResultsEvent, LeaveEvent, StateIn, StatesOut =
			ev.Lobby, ev.Start, ev.Gate, ev.Standings, ev.Results, ev.Leave, ev.StateIn, ev.StatesOut
	end,
}

return RM
