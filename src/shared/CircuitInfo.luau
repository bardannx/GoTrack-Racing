--!nonstrict
-- Facts about a circuit for the menus and the circuit intro: real-world style length,
-- corner and braking-zone counts, top speed, elevation change, longest straight,
-- difficulty stars and the circuit type. Pure maths on Track data, cached per circuit.

local Track = require(script.Parent.Track)
local Config = require(script.Parent.Config)
local Themes = require(script.Parent.Themes)
local Circuits = require(script.Parent.Circuits)

local CircuitInfo = {}

-- studs -> metres, from the speed display (Config.SpeedDisplayFactor km/h per stud/s)
local M_PER_STUD = Config.SpeedDisplayFactor / 3.6
CircuitInfo.MetresPerStud = M_PER_STUD

local cache = {}
local ranked = false

export type Stats = {
	LengthKm: number,
	Corners: number,
	BrakingZones: number,
	TopKmh: number,
	ElevationM: number,
	LongestStraightM: number,
	FullThrottle: number,
	Difficulty: number,
	Score: number,
	Type: string,
	Laps: number,
	RaceKm: number,
	IdealLap: number,
}

local function compute(id: string): Stats?
	if cache[id] then
		return cache[id]
	end
	local t = Track.Get(id)
	if not t then
		return nil
	end
	local n = t.N
	-- corners: runs of samples tighter than a 260-stud radius (merged when close)
	local corners, inside, lastEnd, lastSign = 0, false, -100, 0
	for i = 1, n do
		local k = t.K[i]
		local tight = math.abs(k) > 1 / 260
		if tight and not inside then
			local sgn = if k > 0 then 1 else -1
			if not (i - lastEnd < 6 and sgn == lastSign) then
				corners += 1
			end
			lastSign = sgn
			inside = true
		elseif not tight and inside then
			inside = false
			lastEnd = i
		end
	end
	-- braking zones: the ideal speed drops hard over the next ~100 studs
	local zones, braking = 0, false
	for i = 1, n do
		local drop = t.V[i] - t.V[Track.Wrap(t, i + 12)] > 25
		if drop and not braking then
			zones += 1
		end
		braking = drop
	end
	local top, flat = 0, 0
	local minY, maxY = math.huge, -math.huge
	for i = 1, n do
		top = math.max(top, t.V[i])
		if t.V[i] > Track.Profile.TopSpeed * 0.97 then
			flat += 1
		end
		minY = math.min(minY, t.Y[i])
		maxY = math.max(maxY, t.Y[i])
	end
	local longest, run = 0, 0
	for i = 1, n * 2 do
		if math.abs(t.K[((i - 1) % n) + 1]) < 1 / 900 then
			run += 1
			longest = math.max(longest, run)
		else
			run = 0
		end
	end
	longest = math.min(longest, n)
	local th = Themes[t.Def.Theme]
	local street = th and th.Barrier == "street"
	local lengthKm = t.Length * M_PER_STUD / 1000
	-- raw difficulty: corner and braking density, little flat-out time, hills, tight streets
	local km = math.max(lengthKm, 0.5)
	local score = corners / km * 0.5 + zones / km * 1.2 + (1 - flat / n) * 4 + (maxY - minY) / 25 + (if street then 1.2 else 0) + (40 - t.Width) / 5
	local s = {
		LengthKm = lengthKm,
		Corners = corners,
		BrakingZones = zones,
		TopKmh = top * Config.SpeedDisplayFactor,
		ElevationM = (maxY - minY) * M_PER_STUD,
		LongestStraightM = longest * Track.DS * M_PER_STUD,
		FullThrottle = flat / n,
		Difficulty = 3,
		Score = score,
		Type = if string.find(t.Def.Region, "Bonus") then "Bonus circuit" elseif street then "Street circuit" else "Permanent circuit",
		Laps = t.Laps,
		RaceKm = lengthKm * t.Laps,
		IdealLap = t.IdealLap,
	}
	cache[id] = s
	return s
end

-- Difficulty stars 1..5 are relative: circuits are ranked against each other so the
-- whole calendar spreads across the scale.
function CircuitInfo.Get(id: string): Stats?
	if not ranked then
		ranked = true
		local list = {}
		for _, c in Circuits.List do
			local st = compute(c.Id)
			if st then
				table.insert(list, st)
			end
		end
		table.sort(list, function(a, b)
			return a.Score < b.Score
		end)
		for i, st in list do
			st.Difficulty = math.clamp(1 + math.floor((i - 1) / #list * 5), 1, 5)
		end
	end
	return compute(id)
end

function CircuitInfo.Stars(n: number): string
	return string.rep("★", n) .. string.rep("☆", 5 - n)
end

return CircuitInfo
