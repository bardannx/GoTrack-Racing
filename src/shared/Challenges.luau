--!nonstrict
-- Weekly content that rotates by itself (no updates needed):
--  * a featured circuit every week (bonus coins for racing there)
--  * 3 weekly challenges picked from a pool, with coin rewards
--  * a one-time "getting started" checklist for new players
-- Everything is derived from the UTC week number, so every server agrees. Progress is
-- counted and paid on the server (ChallengeService); this module is only the rules.

local Circuits = require(script.Parent.Circuits)

local Challenges = {}

local WEEK = 7 * 86400
-- weeks start on Monday 00:00 UTC (5 Jan 2026 was a Monday)
local EPOCH = 1767571200

-- stat keys counted per week (see ChallengeService.Bump):
--   races, podiums, wins, top5, laps, featured, ranked, ttLaps, ttMedals, fastest
local function plural(n: number, one: string, many: string): string
	return if n == 1 then one else string.format(many, n)
end

Challenges.Pool = {
	{
		Id = "races",
		Stat = "races",
		Goals = { 4, 6, 8 },
		Coins = 60,
		Text = function(n)
			return string.format("Finish %d races", n)
		end,
	},
	{
		Id = "podiums",
		Stat = "podiums",
		Goals = { 2, 3, 4 },
		Coins = 110,
		Text = function(n)
			return string.format("Finish on the podium %d times", n)
		end,
	},
	{
		Id = "wins",
		Stat = "wins",
		Goals = { 1, 2, 3 },
		Coins = 220,
		Text = function(n)
			return plural(n, "Win a race", "Win %d races")
		end,
	},
	{
		Id = "top5",
		Stat = "top5",
		Goals = { 3, 4, 6 },
		Coins = 80,
		Text = function(n)
			return string.format("Finish in the top five %d times", n)
		end,
	},
	{
		Id = "laps",
		Stat = "laps",
		Goals = { 12, 20, 30 },
		Coins = 8,
		Text = function(n)
			return string.format("Complete %d laps (races or Time Trial)", n)
		end,
	},
	{
		Id = "featured",
		Stat = "featured",
		Goals = { 2, 3, 4 },
		Coins = 110,
		Text = function(n)
			return string.format("Race %d times on the featured circuit", n)
		end,
	},
	{
		Id = "ranked",
		Stat = "ranked",
		Goals = { 2, 3, 5 },
		Coins = 120,
		Text = function(n)
			return string.format("Finish %d Ranked races", n)
		end,
	},
	{
		Id = "ttLaps",
		Stat = "ttLaps",
		Goals = { 5, 8, 12 },
		Coins = 25,
		Text = function(n)
			return string.format("Set %d valid Time Trial laps", n)
		end,
	},
	{
		Id = "ttMedals",
		Stat = "ttMedals",
		Goals = { 1, 2, 3 },
		Coins = 150,
		Text = function(n)
			return plural(
				n,
				"Set a Silver-medal (or better) Time Trial lap",
				"Set %d Silver-medal (or better) Time Trial laps"
			)
		end,
	},
	{
		Id = "fastest",
		Stat = "fastest",
		Goals = { 1, 2 },
		Coins = 180,
		Text = function(n)
			return plural(n, "Set the fastest lap in a race", "Set the fastest lap in %d races")
		end,
	},
}

-- one-time checklist for new players; lifetime stats (d.stats) decide progress
Challenges.Starter = {
	{ Id = "s_race", Stat = "races", Text = "Finish your first race", Goal = 1, Coins = 200, Icon = "🏁" },
	{ Id = "s_tt", Stat = "ttLaps", Text = "Set a Time Trial lap", Goal = 1, Coins = 150, Icon = "⏱️" },
	{
		Id = "s_garage",
		Stat = "equips",
		Text = "Change something on your car in the Garage",
		Goal = 1,
		Coins = 100,
		Icon = "🎨",
	},
	{ Id = "s_podium", Stat = "podiums", Text = "Finish on the podium", Goal = 1, Coins = 250, Icon = "🏆" },
	{ Id = "s_ranked", Stat = "rankedRaces", Text = "Finish a Ranked race", Goal = 1, Coins = 250, Icon = "💎" },
}

-- Week number for a unix time (week 0 starts at EPOCH).
function Challenges.WeekAt(t: number): number
	return math.floor((t - EPOCH) / WEEK)
end

-- Unix time when the given week ends, for the "resets in 3d 4h" countdown.
function Challenges.WeekEnds(week: number): number
	return EPOCH + (week + 1) * WEEK
end

-- small deterministic RNG (same answer on every server for a given week)
local function rng(seed: number)
	local s = (seed * 2654435761) % 4294967296
	return function(n: number): number
		s = (s * 1103515245 + 12345) % 2147483648
		return (s % n) + 1
	end
end

-- featured circuit: walks the calendar in a shuffled order, never the same two weeks running
function Challenges.Featured(week: number): string
	local n = #Circuits.List
	local stride = 11 -- coprime with the calendar size, so every circuit comes round
	while n % stride == 0 do
		stride += 1
	end
	return Circuits.List[((week * stride) % n) + 1].Id
end

-- the week's 3 challenges: { Index, Id, Stat, Text, Goal, Coins }
function Challenges.ForWeek(week: number)
	local roll = rng(week + 7)
	local pool = table.clone(Challenges.Pool)
	local out = {}
	for i = 1, 3 do
		local c = table.remove(pool, roll(#pool))
		local tier = roll(#c.Goals)
		local goal = c.Goals[tier]
		local circuit = Circuits.ById[Challenges.Featured(week)]
		local text = c.Text(goal)
		if c.Id == "featured" and circuit then
			text = string.format("Race %d times at %s %s", goal, circuit.Flag, circuit.Name)
		end
		table.insert(out, {
			Index = i,
			Id = c.Id,
			Stat = c.Stat,
			Text = text,
			Goal = goal,
			-- rewards scale with the goal; per-lap / per-TT-lap challenges pay per unit
			Coins = math.floor((c.Coins * (if c.Coins < 40 then goal else (1 + (tier - 1) * 0.5))) / 10 + 0.5) * 10,
		})
	end
	return out
end

return Challenges
