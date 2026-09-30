--!nocheck
-- Time Trial anti-cheat check: on every circuit, a lap driven along the physics speed
-- profile must be accepted, and faked laps (too fast / teleporting) must be rejected.
--   lune run tools/sim/ttcheck.luau
local process = require("@lune/process")
local Env = require("./env")

local attrs = {}
local player = { UserId = 4343, Name = "TTSim", DisplayName = "TTSim", Parent = Env.Game, ClassName = "Player" }
function player:GetAttribute(k)
	return attrs[k]
end
function player:SetAttribute(k, v)
	attrs[k] = v
end
function player:IsA(c)
	return c == "Player"
end
function player:Kick() end
local Players = Env.Services.Players
Players.GetPlayers = function()
	return { player }
end

-- the server modules get their own os.clock, so a lap can "take" its full time instantly
local clockFn = os.clock
Env.Overrides.os = setmetatable({
	clock = function()
		return clockFn()
	end,
}, { __index = os })

local Circuits = Env.Require("src/shared/Circuits")
local Track = Env.Require("src/shared/Track")
local Config = Env.Require("src/shared/Config")
local DataService = Env.Require("src/server/DataService")
local TT = Env.Require("src/server/TimeTrial")
pcall(DataService.Init)
Players.PlayerAdded:Fire(player)
DataService.WaitFor(player, 5)

-- frames of a lap along the centre line; slow = lap time / ideal lap time
local function lapFrames(t, slow: number, teleport: boolean?)
	local rate = Config.GhostSampleRate
	local frames = {}
	local time, nextSample = 0, 0
	local function push(x, y, z)
		for _, v in { x, y + 2, z, 0, 0, 0 } do
			table.insert(frames, v)
		end
	end
	for i = 1, t.N do
		local j = i % t.N + 1
		local ds = (if j == 1 then t.Length else t.S[j]) - t.S[i]
		local dt = ds / (t.V[i] / slow)
		while nextSample <= time + dt do
			local u = (nextSample - time) / dt
			local x = t.X[i] + (t.X[j] - t.X[i]) * u
			local y = t.Y[i] + (t.Y[j] - t.Y[i]) * u
			local z = t.Z[i] + (t.Z[j] - t.Z[i]) * u
			if teleport and #frames == 6 * 20 then
				x += 400 -- one big jump
			end
			push(x, y, z)
			nextSample += 1 / rate
		end
		time += dt
	end
	push(t.X[1], t.Y[1], t.Z[1])
	return frames, math.floor(time * 1000)
end

local realClock = os.clock
local fails = 0
-- Starts a Time Trial session and submits a lap, faking the clock so the lap time is
-- consistent with the time since the session started. Returns the server's answer.
local function submit(t, frames, lapMs)
	local start = TT.Start(player, t.Id)
	-- only the elapsed check's two clock reads see the future; everything after
	-- (saving, rewards) gets the real clock
	local fakeNow = realClock() + lapMs / 1000 + 2
	local reads = 0
	clockFn = function()
		reads += 1
		if reads > 2 then
			return realClock()
		end
		return fakeNow
	end
	local res = TT.SubmitLap(player, start.token, lapMs, frames, Config.GhostSampleRate)
	clockFn = realClock
	return res
end

for _, c in Circuits.List do
	local t = Track.Get(c.Id)
	-- a clean, very fast lap: 3% off the physics ideal (faster than the Author medal)
	local frames, ms = lapFrames(t, 1.03)
	local legit = submit(t, frames, ms)
	-- the same path claimed in 70% of the time
	local fast = submit(t, frames, math.floor(ms * 0.7))
	-- a lap driven at 1.6x the physics profile (speed hack)
	local hf, hms = lapFrames(t, 1 / 1.6)
	local hack = submit(t, hf, hms)
	-- a lap with a 400-stud teleport
	local tf, tms = lapFrames(t, 1.05, true)
	local tele = submit(t, tf, tms)
	local good = legit.ok and not fast.ok and not hack.ok and not tele.ok
	if not good then
		fails += 1
	end
	print(
		string.format(
			"%-12s ideal %6.1fs  legit %-5s  70%%-time %-10s  1.6x %-10s  teleport %-10s %s",
			c.Id,
			t.IdealLap,
			tostring(legit.ok),
			tostring(fast.reason or fast.ok),
			tostring(hack.reason or hack.ok),
			tostring(tele.reason or tele.ok),
			if good then "ok" else ("WRONG " .. tostring(legit.err) .. " " .. tostring(legit.reason))
		)
	)
end
if fails > 0 then
	print(fails .. " circuit(s) wrong")
	process.exit(1)
end
print("TT CHECK OK")
process.exit(0)
