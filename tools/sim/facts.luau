--!nocheck
-- Prints the circuit facts shown on the intro screen and circuit picker (CircuitInfo).
--   lune run tools/sim/facts.luau
local Env = require("./env")
local Circuits = Env.Require("src/shared/Circuits")
local Info = Env.Require("src/shared/CircuitInfo")
for _, c in Circuits.List do
	local s = Info.Get(c.Id)
	print(
		string.format(
			"R%-2d %-12s %.2f km  %2d corners %2d braking  top %3d km/h  elev %3d m  straight %4d m  flat %2d%%  %s  %s  laps %d  race %.1f km",
			c.Round,
			c.Id,
			s.LengthKm,
			s.Corners,
			s.BrakingZones,
			s.TopKmh,
			s.ElevationM,
			s.LongestStraightM,
			s.FullThrottle * 100,
			Info.Stars(s.Difficulty),
			s.Type,
			s.Laps,
			s.RaceKm
		)
	)
end
