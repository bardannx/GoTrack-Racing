-- Prints per circuit: length, laps, ideal lap time, corners, tightest radius, slowest
-- speed, longest straight and same-level road crossings (must be 0).
--   luau stats.luau

local Circuits = require("./Circuits")
local Track = require("./Track")
for _, c in Circuits.List do
	local t = Track.Build(c)
	-- corners: runs where |K| > 1/400
	local corners, inC, tight, slowV = 0, false, math.huge, math.huge
	local straightMax, run = 0, 0
	for i = 1, t.N do
		local k = math.abs(t.K[i])
		if k > 1 / 400 then
			if not inC then
				corners += 1
			end
			inC = true
			run = 0
		else
			inC = false
			run += Track.DS
			straightMax = math.max(straightMax, run)
		end
		if k > 1e-6 then
			tight = math.min(tight, 1 / k)
		end
		slowV = math.min(slowV, t.V[i])
	end
	-- same-level crossings (road touches other road without overpass)
	local cross = 0
	for i = 1, t.N, 2 do
		for j = i + 40, t.N, 2 do
			local di = math.min(j - i, t.N - (j - i))
			if di > 40 then
				local dx, dz = t.X[i] - t.X[j], t.Z[i] - t.Z[j]
				if dx * dx + dz * dz < (t.Width + 10) ^ 2 and math.abs(t.Y[i] - t.Y[j]) < 8 then
					cross += 1
				end
			end
		end
	end
	print(
		string.format(
			"%-12s len=%5d laps=%d lap=%5.1fs corners=%2d tightR=%4d minV=%3d longStraight=%4d cross=%d",
			c.Id,
			t.Length,
			t.Laps,
			t.IdealLap,
			corners,
			tight,
			slowV,
			straightMax,
			cross
		)
	)
end
