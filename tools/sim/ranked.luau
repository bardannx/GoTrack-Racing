--!nocheck
-- Ranked check: real players only, never computer drivers.
--  1. Cross-server grouping (RankedMatchmaker.FormMatches): full grids at once, smaller
--     grids only after a long wait, RP window widening, nobody matched twice.
--  2. Studio / local ranked lobby: one player waits (no race, no computer drivers), a second player
--     joins, the race starts with exactly those two, and RP uses the whole table.
--  3. A reserved match server: the match lobby, map candidates, early start once
--     everyone arrived, a match nobody joined is cancelled, latecomers are sent back.
--   lune run tools/sim/ranked.luau
local process = require("@lune/process")
local Env = require("./env")

-- Prints the failure and exits with an error code.
local function fail(msg)
	print("FAIL: " .. msg)
	process.exit(1)
end
-- Fails with `msg` unless `cond` holds.
local function check(cond, msg)
	if not cond then
		fail(msg)
	end
end

-- fake players
local all = {}
local kicked = {}
-- A fake Player with attributes, enough for the race server.
local function newPlayer(id, name)
	local attrs = {}
	local p = { UserId = id, Name = name, DisplayName = name, Parent = Env.Game, ClassName = "Player" }
	function p:GetAttribute(k)
		return attrs[k]
	end
	function p:SetAttribute(k, v)
		attrs[k] = v
	end
	function p:Kick(msg)
		kicked[p] = msg
	end
	function p:IsA(c)
		return c == "Player"
	end
	function p:IsFriendsWithAsync()
		return false
	end
	function p:GetJoinData()
		return {}
	end
	table.insert(all, p)
	return p
end
local Players = Env.Services.Players
Players.GetPlayers = function()
	return all
end

local Config = Env.Require("src/shared/Config")
local Circuits = Env.Require("src/shared/Circuits")
local DataService = Env.Require("src/server/DataService")
local MM = Env.Require("src/server/RankedMatchmaker")
local RM = Env.Require("src/server/RaceManager")
local Q = Config.Ranked.Queue

---------------------------------------------------------------------------
-- 1. grouping
---------------------------------------------------------------------------
local function entries(n, rp, t, from)
	local out = {}
	for i = 1, n do
		table.insert(out, { u = (from or 0) + i, rp = rp, t = t })
	end
	return out
end
-- The size of each match group, for printing.
local function sizes(groups)
	local s = {}
	for _, g in groups do
		table.insert(s, #g)
	end
	return table.concat(s, ",")
end

check(MM.Needed(0) == Config.Race.MaxRacers, "a fresh queue should wait for a full grid")
check(MM.Needed(1e6) == Q.MinRacers, "a long wait should allow the smallest grid")

local g = MM.FormMatches(entries(10, 1000, 100), 101)
check(#g == 1 and #g[1] == 10, "10 players at once should make one full grid, got " .. sizes(g))

g = MM.FormMatches(entries(3, 1000, 100), 105)
check(#g == 0, "3 players after 5 s should keep searching")
local waitFor3 = nil
for w = 0, 120 do
	if #MM.FormMatches(entries(3, 1000, 100), 100 + w) > 0 then
		waitFor3 = w
		break
	end
end
check(waitFor3 ~= nil, "3 players never got a match")
print(string.format("3 players in the queue: matched after %d s", waitFor3))

g = MM.FormMatches(entries(1, 1000, 100), 100 + 600)
check(#g == 0, "a lone player must never get a match")

-- far-apart ratings only meet once the window has widened enough
local far = { { u = 1, rp = 1000, t = 100 }, { u = 2, rp = 3000, t = 100 } }
local joinAt = nil
for w = 0, 300 do
	if #MM.FormMatches(far, 100 + w) > 0 then
		joinAt = w
		break
	end
end
check(joinAt ~= nil and joinAt > 60, "1000 RP and 3000 RP matched too early: " .. tostring(joinAt))
print(string.format("1000 RP vs 3000 RP: matched after %d s (window widens %d RP/s)", joinAt, Q.SpreadPerSecond))

-- 23 players at once: two full grids, the other 3 keep searching; nobody twice
g = MM.FormMatches(entries(23, 1000, 100), 101)
check(sizes(g) == "10,10", "23 players should make 10,10 now, got " .. sizes(g))
local seen = {}
for _, grp in g do
	for _, e in grp do
		check(not seen[e.u], "player matched twice")
		seen[e.u] = true
	end
end

-- the longest waiter anchors the match and gets the closest ratings
local mixed = { { u = 1, rp = 1500, t = 50 } }
for i = 1, 12 do
	table.insert(mixed, { u = 100 + i, rp = 1500 + i * 20, t = 90 })
end
g = MM.FormMatches(mixed, 91)
check(#g == 1 and g[1][1].u == 1 and #g[1] == 10, "anchor / closest ratings wrong")
check(g[1][10].rp == 1500 + 9 * 20, "should take the 9 closest ratings")
check(MM.FormMatches({ { u = 1 }, "junk", { u = 2, rp = 5, t = 1 } }, 10) ~= nil, "bad entries should be skipped")
print("grouping ok")

-- seasons roll over on their own, forever: no update needed
local R = Config.Ranked
local s1 = Config.SeasonAt(R.FirstSeasonEnds - 1)
check(s1.Number == 1 and s1.EndsAt == R.FirstSeasonEnds, "season 1 should end at FirstSeasonEnds")
local s2 = Config.SeasonAt(R.FirstSeasonEnds)
check(
	s2.Number == 2 and s2.EndsAt == R.FirstSeasonEnds + R.SeasonDays * 86400,
	"season 2 should start when season 1 ends"
)
local prev = s2
for day = 1, 5 * 365 do
	local sx = Config.SeasonAt(R.FirstSeasonEnds + day * 86400)
	check(
		sx.Number == prev.Number or (sx.Number == prev.Number + 1 and sx.StartsAt == prev.EndsAt),
		"seasons must follow each other with no gap"
	)
	check(sx.EndsAt > R.FirstSeasonEnds + day * 86400, "the current season must not have ended")
	prev = sx
end
print(
	string.format(
		"seasons: 5 years after season 1 it is %s (a new one every %d days, automatically)",
		prev.Name,
		R.SeasonDays
	)
)

---------------------------------------------------------------------------
-- 2. local ranked lobby (Studio): waits for a real rival, never adds computer drivers
---------------------------------------------------------------------------
check(not MM.Enabled(), "the shared queue must be off outside a live server")
check(not MM.IsMatchServer(), "not a match server")

local okInit, errInit = pcall(DataService.Init)
check(okInit, "DataService.Init: " .. tostring(errInit))
local A = newPlayer(9001, "Alice")
local B = newPlayer(9002, "Bruno")
local C = newPlayer(9003, "Chen")
local D = newPlayer(9004, "Dana")
for _, p in { A, B, C, D } do
	Players.PlayerAdded:Fire(p)
	check(DataService.WaitFor(p, 5), "profile did not load for " .. p.Name)
end

-- A fake RemoteEvent that records everything sent with FireClient.
local function ev()
	local e = { Sent = {} }
	function e:FireClient(p, payload)
		table.insert(e.Sent, { p = p, v = payload })
	end
	e.OnServerEvent = Env.Signal()
	return e
end
local events = {
	Lobby = ev(),
	Start = ev(),
	Gate = ev(),
	Standings = ev(),
	Results = ev(),
	Leave = ev(),
	StateIn = ev(),
	StatesOut = ev(),
}
local T = RM._test
T.setEvents(events)
-- The last lobby update the server sent to `p`.
local function lastLobbyFor(p)
	for i = #events.Lobby.Sent, 1, -1 do
		if events.Lobby.Sent[i].p == p then
			return events.Lobby.Sent[i].v
		end
	end
	return nil
end
-- How many races are running.
local function countSessions()
	local n = 0
	for _ in T.sessions do
		n += 1
	end
	return n
end

local clock = 10000
Env.SetServerTime(clock)
local res = RM.RankedQueue(A)
check(res.ok and res.lobby and res.lobby.Mode == "ranked", "RankedQueue failed: " .. tostring(res.err))
check(res.lobby.Candidates and #res.lobby.Candidates == 3, "ranked lobby should offer 3 circuits")

-- the countdown runs out with nobody else: keep waiting, never start alone
clock += Config.Race.RankedCountdown + 1
Env.SetServerTime(clock)
T.lobbyTick(clock)
check(countSessions() == 0, "a ranked race started with one player")
local info = lastLobbyFor(A)
check(info and info.Waiting == true, "the lone player should see 'waiting for a rival'")
for _ = 1, 20 do
	clock += 5
	Env.SetServerTime(clock)
	T.lobbyTick(clock)
end
check(countSessions() == 0, "a ranked race started with one player after a long wait")
print("one player: still waiting after " .. (clock - 10000) .. " s, no race, no computer drivers")

-- a second real player arrives: vote, then race with exactly those two
res = RM.RankedQueue(B)
check(res.ok, "second player could not queue: " .. tostring(res.err))
info = lastLobbyFor(A)
check(info and info.Count == 2 and not info.Waiting, "the waiting lobby should pick up the second player")
check(
	info.EndsAt - clock <= Q.VoteSeconds + 0.01 and info.EndsAt - clock >= Q.VoteSeconds - 0.01,
	"the vote should last VoteSeconds"
)
check(RM.VoteMap(B, info.Candidates[2]).ok, "vote failed")
clock = info.EndsAt + 0.1
Env.SetServerTime(clock)
T.lobbyTick(clock)
check(countSessions() == 1, "the ranked race did not start with two players")
local s = nil
for _, ss in T.sessions do
	s = ss
end
check(s.Mode == "ranked" and #s.Racers == 2, "ranked grid should be exactly the 2 players, got " .. #s.Racers)
for _, r in s.Racers do
	check(not r.IsAI, "a computer driver joined a ranked race")
end
check(s.TrackId == info.Candidates[2], "the voted circuit should win")
print(string.format("two players: race on %s with %d racers, 0 computer drivers", s.TrackId, #s.Racers))

-- results: P1 gets the winner's RP, P2 of 2 gets the last-place RP (the table spreads)
local rA, rB = s.ByPlayer[A], s.ByPlayer[B]
rA.Finished, rA.FinishTime, rA.Pos = true, 100, 1
rB.Finished, rB.FinishTime, rB.Pos = true, 101, 2
DataService.Get(B).rp = 1000
local rpA0, rpB0 = DataService.Get(A).rp, DataService.Get(B).rp
T.endSession(s)
local PR = Config.Ranked.PositionRP
local dA, dB = DataService.Get(A).rp - rpA0, DataService.Get(B).rp - rpB0
check(dA == PR[1], string.format("P1 of 2 should get %d RP, got %d", PR[1], dA))
check(dB == PR[#PR], string.format("P2 of 2 should get %d RP, got %d", PR[#PR], dB))
print(string.format("results: P1 %+d RP, P2 %+d RP", dA, dB))

-- a quick race still fills the grid with computer drivers
Env.SetServerTime(clock)
local ql = T.createLobby("quick", Circuits.List[1].Id, C)
T.addToLobby(C, ql)
T.startSession(ql)
local qs = nil
for _, ss in T.sessions do
	if ss.Mode == "quick" then
		qs = ss
	end
end
check(qs and #qs.Racers == Config.Race.MaxRacers, "quick race should still fill a full grid")
T.sessions[qs.Id] = nil
print("quick race: full grid of " .. #qs.Racers)

---------------------------------------------------------------------------
-- 3. a reserved match server
---------------------------------------------------------------------------
Env.GameProps.PrivateServerId = "reserved-1"
Env.GameProps.PrivateServerOwnerId = 0
check(MM.IsMatchServer(), "should be a match server now")
local E = newPlayer(9005, "Eve")
local F = newPlayer(9006, "Femi")
local G = newPlayer(9007, "Gus")
for _, p in { E, F, G } do
	Players.PlayerAdded:Fire(p)
	check(DataService.WaitFor(p, 5), "profile did not load for " .. p.Name)
end
check(not RM.QuickRace(E, "random", false).ok, "quick race must be refused on a match server")

-- nobody else made it: the match is cancelled, no race, no RP lost
local c1, c2 = Circuits.List[3].Id, Circuits.List[4].Id
RM.MatchPlayer(E, { users = { E.UserId, F.UserId }, cands = { c1, "not-a-circuit", c2 } })
local ml = nil
for _, l in T.lobbies do
	if l.Match then
		ml = l
	end
end
check(ml and ml.Expected == 2, "match lobby not created")
check(
	#ml.Candidates == 2 and ml.Candidates[1] == c1 and ml.Candidates[2] == c2,
	"bad circuits must be dropped from the vote"
)
local rpE0 = DataService.Get(E).rp
clock += Q.MatchWait + 1
Env.SetServerTime(clock)
T.lobbyTick(clock)
check(T.lobbies[ml.Id] == nil and countSessions() == 0, "a match with one arrival should be cancelled")
check(DataService.Get(E).rp == rpE0, "a cancelled match must not cost RP")
print("match server: a match nobody else joined is cancelled (no race, no RP lost)")

-- everyone arrives: the vote is shortened, the race starts with exactly them
local cands = { c1, c2, Circuits.List[5].Id }
RM.MatchPlayer(E, { users = { E.UserId, F.UserId, G.UserId }, cands = cands })
RM.MatchPlayer(F, { users = { E.UserId, F.UserId, G.UserId }, cands = cands })
for _, l in T.lobbies do
	if l.Match then
		ml = l
	end
end
check(#ml.Players == 2 and ml.EndsAt - clock > Q.VoteSeconds, "should still wait for the third player")
local q = RM.RankedQueue(F)
check(q.ok and q.lobby.Id == ml.Id, "RankedQueue on a match server should return the match lobby")
RM.MatchPlayer(G, { users = { E.UserId, F.UserId, G.UserId }, cands = cands })
check(#ml.Players == 3 and ml.EndsAt - clock <= Q.VoteSeconds + 0.01, "everyone arrived: the vote should start")
clock = ml.EndsAt + 0.1
Env.SetServerTime(clock)
T.lobbyTick(clock)
local ms = nil
for _, ss in T.sessions do
	if ss.Mode == "ranked" then
		ms = ss
	end
end
check(ms and #ms.Racers == 3, "the match race should start with the 3 players")
for _, r in ms.Racers do
	check(not r.IsAI, "a computer driver joined a match race")
end
print(string.format("match server: race on %s with %d racers, 0 computer drivers", ms.TrackId, #ms.Racers))

-- someone arriving after the start is sent back, not added to the race
local H = newPlayer(9008, "Hana")
Players.PlayerAdded:Fire(H)
DataService.WaitFor(H, 5)
RM.MatchPlayer(H, { users = { H.UserId }, cands = cands })
for _, l in T.lobbies do
	check(not table.find(l.Players, H), "a latecomer joined a lobby after the match started")
end
check(ms.ByPlayer[H] == nil, "a latecomer joined the running race")
print("match server: a latecomer is sent back to the lobby")

print("RANKED SIM OK")
process.exit(0)
