--!nocheck
-- Server simulation: a fake player joins, races the weekly featured circuit against 9 computer
-- drivers (sending car states and checkpoints like a real client), and finishes. Checks
-- results, coins (incl. the featured bonus), stats and challenge progress, then claims.
--   lune run tools/sim/server.luau
local process = require("@lune/process")
local Env = require("./env")
local roblox = Env.Roblox

-- Prints the failure and exits with an error code.
local function fail(msg)
	print("FAIL: " .. msg)
	process.exit(1)
end

-- a fake Player
local attrs = {}
local player = {
	UserId = 4242,
	Name = "SimRacer",
	DisplayName = "SimRacer",
	Parent = Env.Game,
	ClassName = "Player",
}
function player:GetAttribute(k)
	return attrs[k]
end
function player:SetAttribute(k, v)
	attrs[k] = v
end
function player:Kick(msg)
	fail("kicked: " .. tostring(msg))
end
function player:IsA(c)
	return c == "Player"
end
function player:IsFriendsWithAsync()
	return true
end
local Players = Env.Services.Players
Players.GetPlayers = function()
	return { player }
end

local Net = Env.Require("src/shared/Net")
local Track = Env.Require("src/shared/Track")
local Config = Env.Require("src/shared/Config")
local Challenges = Env.Require("src/shared/Challenges")
local DataService = Env.Require("src/server/DataService")
local ChallengeService = Env.Require("src/server/ChallengeService")
local RM = Env.Require("src/server/RaceManager")

-- any error ends the run (the server's forever-loops would otherwise keep Lune alive)
local okInit, errInit = pcall(DataService.Init)
if not okInit then
	fail("DataService.Init: " .. tostring(errInit))
end
Players.PlayerAdded:Fire(player)
local d = DataService.WaitFor(player, 5)
if not d then
	fail("profile did not load")
end
local coins0 = d.coins

-- capture what the server sends
local results
-- A fake RemoteEvent that records everything sent with FireClient.
local function ev()
	local e = { Sent = {} }
	function e:FireClient(_p, payload)
		table.insert(e.Sent, payload)
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
RM._test.setEvents(events)

local featured = ChallengeService.Featured()
local T = RM._test
local clock = 5000
Env.SetServerTime(clock)
local lobby = T.createLobby("quick", featured, player)
T.addToLobby(player, lobby)
T.startSession(lobby)
local start = events.Start.Sent[1]
if not start then
	fail("no RaceStart sent")
end
print(
	string.format("race on %s (featured: %s), %d laps, %d racers", start.TrackId, featured, start.Laps, #start.Racers)
)
local s = nil
for _, ss in T.sessions do
	s = ss
end
local t = Track.Get(start.TrackId)

-- drive: 200 studs/s along the centre line, from the grid
local me = s.ByPlayer[player]
local gs = Track.GridSlot(t, me.Slot)
local dist = gs - t.Length
local nextGate = 1
local dt = 1 / 20
clock = start.LightsStart - 1
local laps = start.Laps
local b = buffer.create(Net.StateSize)
for step = 1, 20000 do
	clock += dt
	Env.SetServerTime(clock)
	local raceTime = clock - start.GoTime
	if raceTime > 0 then
		dist += 200 * dt
	end
	local x, y, z, tx, ty, tz = Track.PointAt(t, dist % t.Length, 0)
	Net.WriteState(b, 0, raceTime, x, y + 2.6, z, math.atan2(-tx, -tz), 0, 0, tx * 200, 0, tz * 200, 0)
	T.onState(player, b)
	-- checkpoints: gate k sits at k/24 of the lap (gate 1 = the line)
	if raceTime > 0 then
		local gateS = t.S[t.Gates[nextGate]]
		local lapStart = math.floor(dist / t.Length) * t.Length
		if dist >= lapStart + gateS and dist - 200 * dt < lapStart + gateS + 1 then
			T.onGate(player, nextGate, raceTime)
			nextGate = (nextGate % Track.GateCount) + 1
		end
	end
	T.stepAI(s, dt)
	T.tickSession(s)
	if #events.Results.Sent > 0 then
		results = events.Results.Sent[1]
		break
	end
end
if not results then
	fail("race never ended")
end
local you = results.You
print(
	string.format(
		"finished P%s (finished=%s), +%s coins, +%s XP, featured bonus=%s",
		tostring(you.Pos),
		tostring(you.Finished),
		tostring(you.Coins),
		tostring(you.XP),
		tostring(you.Featured)
	)
)
if not you.Finished then
	fail("player did not finish")
end
if d.coins ~= coins0 + you.Coins then
	fail("coins not paid")
end
local base = Config.Economy.PositionCoins[you.Pos] + (if you.Fastest then Config.Economy.FastestLapCoins else 0)
local expect = math.floor(base * Config.Economy.FeaturedCoinMultiplier + 0.5)
if you.Coins ~= expect then
	fail(string.format("featured bonus wrong: got %d expected %d", you.Coins, expect))
end
print("stats:", d.stats.races, "races,", d.stats.laps, "laps,", d.stats.podiums, "podiums,", d.stats.wins, "wins")
local snap = ChallengeService.Snapshot(d)
for _, c in snap.list do
	print(string.format("  weekly #%d  %-45s %d/%d  %d coins", c.i, c.text, c.progress, c.goal, c.coins))
end
for _, c in snap.starter do
	print(string.format("  starter %-10s %-45s %d/%d", c.id, c.text, c.progress, c.goal))
end
if d.weekly.counts.races ~= 1 or d.weekly.counts.featured ~= 1 or d.weekly.counts.laps ~= laps then
	fail("weekly counts wrong")
end
-- claiming
local r1 = ChallengeService.Claim(player, "starter", "s_race")
if not r1.ok then
	fail("starter claim failed: " .. tostring(r1.err))
end
local r2 = ChallengeService.Claim(player, "starter", "s_race")
if r2.ok then
	fail("double claim allowed")
end
local r3 = ChallengeService.Claim(player, "starter", "s_ranked")
if r3.ok then
	fail("claimed an unfinished challenge")
end
print("claims ok (+" .. r1.coins .. " coins); double and unfinished claims refused")
print("SERVER SIM OK")
process.exit(0)
