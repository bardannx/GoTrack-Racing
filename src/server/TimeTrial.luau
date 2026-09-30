--!nonstrict
-- Time Trial: solo hot laps against the clock and your ghost. The client drives and
-- records its path; the server replays that path through validate() before a time can
-- reach the leaderboard, so a hacked client can't post an impossible lap.

local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Track = require(Shared.Track)
local Medals = require(Shared.Medals)
local Cosmetics = require(Shared.Cosmetics)

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local ChallengeService = require(script.Parent.ChallengeService)

local TT = {}

local sessions = {}

-- Opens a session on a circuit. Laps are only accepted with this session's token.
function TT.Start(p: Player, trackId: any)
	local t = Track.Get(trackId)
	if not t then
		return { ok = false, err = "Unknown circuit" }
	end
	local token = HttpService:GenerateGUID(false)
	sessions[p] = { token = token, trackId = trackId, lastEnd = os.clock() }
	return { ok = true, token = token }
end

-- Fastest a car can really go: top speed +7% slipstream +5% active aero (x1.12). The
-- checks leave a wide margin so crashes and bumps never reject a real lap.
local MAX_SPEED = Config.Car.TopSpeed * 1.3 + 10
-- IdealLap is the physics limit on the centre line (the Author medal is 1.02x it); a
-- lap much faster than that can't have been driven
local MIN_LAP_FACTOR = 0.8

-- Checks a submitted lap against its recorded path (6 numbers per frame: position and
-- rotation). Returns false and a short reason for the first check that fails:
--   clock / too fast   the lap can't be quicker than the time since the session started
--                      or than the circuit's physical limit
--   rate / framecount  the path was sampled at the agreed rate for the whole lap
--   nan / speed        every frame is a real position no further than top speed allows
--   gates / finish     it passed every timing gate in order and ended on the line
local function validate(t, lapMs: number, frames, rate: number, elapsed: number): (boolean, string?)
	if elapsed + 1.5 < lapMs / 1000 then
		return false, "clock"
	end
	if lapMs < t.IdealLap * 1000 * MIN_LAP_FACTOR then
		return false, "too fast"
	end
	if rate ~= Config.GhostSampleRate then
		return false, "rate"
	end
	local n = #frames // 6
	if #frames % 6 ~= 0 or n < 5 then
		return false, "frames"
	end
	local expected = lapMs / 1000 * rate
	if n < expected * 0.85 - 2 or n > expected * 1.15 + 3 then
		return false, "framecount"
	end
	local maxStep = MAX_SPEED / rate + 4
	local nextGate = 2
	local hint = 1
	local prevX, prevZ, prevY = nil, nil, nil
	for i = 0, n - 1 do
		local x, y, z = frames[i * 6 + 1], frames[i * 6 + 2], frames[i * 6 + 3]
		if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" or x ~= x or y ~= y or z ~= z then
			return false, "nan"
		end
		if prevX then
			local dx, dy, dz = x - prevX, y - prevY, z - prevZ
			local step = math.sqrt(dx * dx + dy * dy + dz * dz)
			if step > maxStep then
				return false, "speed"
			end
		end
		local idx, lateral = Track.Project(t, x, y, z, hint)
		hint = idx
		if nextGate <= Track.GateCount then
			local gi = t.Gates[nextGate]
			local d = Track.IndexDelta(t, gi, idx)
			if d >= 0 and d < 60 and math.abs(lateral) < t.Width / 2 + 70 then
				nextGate += 1
			end
		end
		prevX, prevY, prevZ = x, y, z
	end
	if nextGate <= Track.GateCount then
		return false, "gates"
	end
	-- last frame must be at the start/finish line
	local lx, ly, lz = frames[(n - 1) * 6 + 1], frames[(n - 1) * 6 + 2], frames[(n - 1) * 6 + 3]
	local idx = Track.Project(t, lx, ly, lz, hint)
	if math.abs(Track.IndexDelta(t, 1, idx)) > 25 then
		return false, "finish"
	end
	return true, nil
end

-- A finished lap from the client. If it passes validate(), it updates the player's best,
-- medal, leaderboard entry and ghost, and pays the Time Trial coins.
function TT.SubmitLap(p: Player, token: any, lapMs: any, frames: any, rate: any)
	local s = sessions[p]
	if not s or s.token ~= token then
		return { ok = false, err = "Session expired" }
	end
	if typeof(lapMs) ~= "number" or lapMs ~= lapMs or lapMs < 5000 or lapMs > Config.MaxLapSeconds * 1000 then
		return { ok = false, err = "Invalid lap" }
	end
	if typeof(frames) ~= "table" or #frames > Config.MaxLapSeconds * Config.GhostSampleRate * 6 + 60 then
		return { ok = false, err = "Invalid lap" }
	end
	local clean = table.create(#frames)
	for i, v in frames do
		if typeof(v) ~= "number" then
			return { ok = false, err = "Invalid lap" }
		end
		clean[i] = math.floor(v * 100 + 0.5) / 100
	end
	lapMs = math.floor(lapMs)
	local t = Track.Get(s.trackId)
	local elapsed = os.clock() - s.lastEnd
	s.lastEnd = os.clock()
	local ok, reason = validate(t, lapMs, clean, tonumber(rate) or 0, elapsed)
	if not ok then
		warn("[GoTrack] Rejected lap from", p.Name, reason)
		return { ok = false, err = "Lap could not be verified", reason = reason }
	end
	local d = DataService.Get(p)
	if not d then
		return { ok = false, err = "Data not loaded" }
	end
	local trackId = s.trackId
	local prev = d.bests[trackId]
	local isPB = prev == nil or lapMs < prev
	local thresholds = Medals.FromIdeal(t.IdealLap)
	local medal = Medals.Earned(lapMs, thresholds)
	local oldMedal = d.medals[trackId] or 0
	local econ = Config.Economy
	local coins = econ.TimeTrialLapCoins
	local lastReward = p:GetAttribute("LastTTReward")
	if typeof(lastReward) == "number" and os.clock() - lastReward < econ.MinSecondsBetweenTTRewards then
		coins = 0
	end
	p:SetAttribute("LastTTReward", os.clock())
	if medal > 0 then
		coins += econ.MedalCoins[medal]
	end
	if medal > oldMedal then
		coins += econ.NewMedalBonus * (medal - oldMedal)
		d.medals[trackId] = medal
	end
	if isPB and prev then
		coins += econ.TimeTrialPBCoins
	end
	coins = math.floor(coins * MonetizationService.CoinMultiplier(p) + 0.5)
	d.coins += coins
	d.stats.laps += 1
	d.stats.ttLaps = (d.stats.ttLaps or 0) + 1
	ChallengeService.Bump(d, "ttLaps")
	ChallengeService.Bump(d, "laps")
	if medal >= 2 then
		ChallengeService.Bump(d, "ttMedals")
	end
	if isPB then
		d.bests[trackId] = lapMs
		LeaderboardService.SubmitBest(Config.DataStores.LeaderboardPrefix .. trackId, p.UserId, lapMs, true)
		local title = Cosmetics.ById[d.car.Title]
		LeaderboardService.SaveGhost(trackId, p.UserId, {
			v = 2,
			ms = lapMs,
			rate = Config.GhostSampleRate,
			f = clean,
			car = d.car,
			name = p.DisplayName,
			userId = p.UserId,
			title = if title then title.Text else nil,
		})
	end
	DataService.Changed(p)
	return {
		ok = true,
		lapMs = lapMs,
		pb = isPB,
		prevBest = prev,
		medal = medal,
		newMedal = medal > oldMedal,
		coins = coins,
	}
end

-- Forgets the player's session when they leave the mode.
function TT.Cleanup(p: Player)
	sessions[p] = nil
end

return TT
