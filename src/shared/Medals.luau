--!nonstrict
-- Medal thresholds. Medal levels: 0 none, 1 bronze, 2 silver, 3 gold, 4 author.

local Config = require(script.Parent.Config)

local Medals = {}

export type Thresholds = { [number]: number } -- [1]=bronze ms ... [4]=author ms

local function round100(ms: number): number
	return math.floor(ms / 100 + 0.5) * 100
end

-- Time Trial thresholds from a circuit's ideal lap (seconds)
function Medals.FromIdeal(idealSeconds: number): Thresholds
	local m = Config.Medals
	local ms = idealSeconds * 1000
	return {
		[1] = round100(ms * m.BronzeFactor),
		[2] = round100(ms * m.SilverFactor),
		[3] = round100(ms * m.GoldFactor),
		[4] = round100(ms * m.AuthorFactor),
	}
end

function Medals.Earned(ms: number, thresholds: Thresholds?): number
	if not thresholds then
		return 0
	end
	for level = 4, 1, -1 do
		local t = thresholds[level]
		if t and ms <= t then
			return level
		end
	end
	return 0
end

function Medals.FormatTime(ms: number?): string
	if not ms or ms <= 0 or ms ~= ms then
		return "--:--.---"
	end
	local total = math.floor(ms + 0.5)
	local minutes = total // 60000
	local seconds = (total % 60000) // 1000
	local millis = total % 1000
	return string.format("%d:%02d.%03d", minutes, seconds, millis)
end

function Medals.FormatDelta(deltaMs: number): string
	local sign = if deltaMs < 0 then "-" else "+"
	local a = math.abs(deltaMs)
	return string.format("%s%d.%03d", sign, a // 1000, math.floor(a % 1000))
end

return Medals
