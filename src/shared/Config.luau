--!nonstrict
-- Every tunable number in the game lives here: car handling, race timing, the economy,
-- ranked tiers and seasons, medals and sounds. The module is shared, so the server and
-- every client read the same values. Handling is deliberately identical for every car
-- and every game pass: only driving decides a race.

local Config = {}

Config.GameName = "GoTrack Racing"
Config.Version = "1.0.0"

-- DataStore names. Bump the suffix (e.g. _v2) ONLY if you want to wipe all data.
Config.DataStores = {
	Player = "GTR_Player_v1",
	Ghosts = "GTR_Ghosts_v1",
	LeaderboardPrefix = "GTR_TT_v1_",
	Ranked = "GTR_Ranked_v1",
	Wins = "GTR_Wins_v1",
	Level = "GTR_Level_v1",
}

-- When true, every game pass perk is unlocked while testing in Roblox Studio.
-- Has NO effect in live servers.
Config.StudioGrantAllPasses = true

-- The game's owner: every pass, cosmetic and ranked reward unlocked, plus an OWNER chat
-- tag and title. Roblox user ids (checked on the server); the account that owns the
-- published game always counts too.
Config.Owners = { 10461888408 } -- Bardan (@bardann04)

-- True for the owners listed above and for whoever owns the published game.
function Config.IsOwner(userId: number): boolean
	if table.find(Config.Owners, userId) then
		return true
	end
	return userId > 0 and game.CreatorType == Enum.CreatorType.User and game.CreatorId == userId
end

-- Car handling (studs, seconds). Identical for every chassis so racing is fair.
Config.Car = {
	TopSpeed = 235,
	EngineAccel = 82,
	BrakeDecel = 165,
	ReverseAccel = 40,
	ReverseTopSpeed = 40,
	RollingResistance = 6,
	AirDrag = 0.0006,
	Grip = 12,
	DriftGrip = 3,
	SteerRate = 2.5,
	HighSpeedSteerFactor = 0.45,
	SuspensionLength = 2.6,
	SuspensionRest = 1.95,
	SuspensionDamping = 20,
	Downforce = 0.5,
	Gravity = 196.2,
	OffTrackTopSpeed = 95, -- on grass / sand
	OffTrackGrip = 0.55,
	SlipstreamBonus = 0.07, -- +7% top speed right behind another car
	GravelTopSpeed = 55, -- in gravel traps
	GravelGrip = 0.35,
	-- 2026-style active aero ("straight mode"): flat out on a straight, the rear-wing flap
	-- opens for less drag. Closes the moment you brake or turn. Same for every car.
	ActiveAero = {
		Enabled = true,
		MinSpeed = 0.55, -- fraction of TopSpeed before it can open
		Delay = 0.35, -- seconds of flat-out, straight driving before it opens
		TopSpeedBonus = 0.05, -- +5% top speed while open
	},
}

-- Car-to-car contact and crash damage
Config.Contact = {
	Enabled = true,
	HalfWidth = 2.85, -- collision box (studs) incl. wheels
	HalfLength = 7.3, -- incl. wings
	Restitution = 0.3,
	Friction = 0.25,
	GhostStartSeconds = 3, -- cars pass through each other for the first 3 s after GO
	GhostResetSeconds = 3, -- no contact after a reset
}

Config.Damage = {
	Enabled = true,
	MinImpact = 30, -- studs/s change in one step before anything breaks
	FullImpact = 150, -- impact that fully breaks a part
	WingBreak = 0.45, -- wing falls off below this health
	ResetRepairSeconds = 1.6, -- time frozen while the crew fixes the car after a reset
}

-- Races
Config.Race = {
	MaxRacers = 10,
	QuickCountdown = 20, -- seconds a quick-race lobby waits for players
	RankedCountdown = 25,
	LoadTime = 9, -- seconds between "race starting" and the countdown (circuit loads)
	CountdownSeconds = 3, -- 3, 2, 1 red lights, then green GO
	FinishGrace = 40, -- seconds after the first real player finishes before the race ends
	MaxRaceSeconds = 480,
	SendRate = 20, -- position updates per second
	ResultsSeconds = 14,
}

-- Computer drivers (fill empty grid slots in Quick Race only; Ranked is real players only)
Config.AI = {
	Enabled = true,
	QuickSkill = { 0.8, 0.92 }, -- fraction of the ideal speed profile
	Names = {
		"Max Velocity",
		"Lewis Throttle",
		"Charles Apex",
		"Lando Drift",
		"Oscar Pace",
		"Carlos Kerb",
		"Fernando Gear",
		"George Slip",
		"Yuki Boost",
		"Pierre Brake",
		"Esteban Line",
		"Nico Chicane",
		"Alex Turbo",
		"Valtteri Pit",
		"Kimi Lap",
		"Sergio Draft",
		"Daniel Grin",
		"Zhou Sector",
		"Logan Pole",
		"Ollie Rev",
	},
}

-- Ghost recording (Time Trial)
Config.GhostSampleRate = 10
Config.MaxLapSeconds = 240

-- Economy
Config.Economy = {
	StartingCoins = 500,
	PositionCoins = { 150, 120, 100, 85, 70, 60, 50, 42, 35, 28 },
	PositionXP = { 120, 100, 85, 72, 62, 54, 46, 40, 34, 28 },
	FastestLapCoins = 30,
	DNFCoins = 10,
	TimeTrialLapCoins = 8,
	TimeTrialPBCoins = 25,
	NewMedalBonus = 60,
	MedalCoins = { 5, 10, 20, 40 },
	MinSecondsBetweenTTRewards = 20,
	DailyRewards = { 100, 150, 200, 300, 400, 600, 1000 },
	VIPCoinMultiplier = 1.5,
	FeaturedCoinMultiplier = 1.5, -- races on the weekly featured circuit (Challenges.luau)
}

-- XP needed to go from `level` to the next one (grows linearly).
function Config.XPForLevel(level: number): number
	return 150 + (level - 1) * 80
end

-- Ranked points, tiers and seasons. Every tier from Bronze to Diamond has three divisions,
-- climbed III -> II -> I (new players start at Bronze III). Champion has no divisions and is
-- NOT won by points alone: you need the Champion RP AND a place in the season's top 500,
-- re-picked every day at 00:00 UTC (server/ChampionService.luau).
Config.Ranked = {
	StartRP = 0,
	PositionRP = { 32, 24, 18, 12, 7, 3, -2, -6, -10, -14 },
	LeaveRP = -18,
	-- Season 1 ends at FirstSeasonEnds; after that a new season starts automatically every
	-- SeasonDays, forever (no update needed). Config.Ranked.Season always reads as the
	-- current season: { Number, Name, EndsAt, StartsAt } (see Config.SeasonAt below).
	FirstSeasonEnds = 1798761540, -- 31 Dec 2026 23:59 UTC
	SeasonDays = 70,
	SeasonReset = 0.5, -- RP keeps 50% above the start value at a new season
	MatchmakingSpread = 350, -- RP difference allowed when joining a ranked lobby
	-- Ranked is real players only (never AI). Live servers share one queue (MemoryStore)
	-- and send each match to its own reserved server (server/RankedMatchmaker.luau).
	Queue = {
		MinRacers = 2, -- fewest players a ranked race can start with
		-- { seconds the longest-waiting player has queued, racers needed to start }
		Steps = { { 0, 10 }, { 15, 6 }, { 30, 4 }, { 45, 2 } },
		SpreadPerSecond = 25, -- the RP window widens the longer someone waits
		MatchWait = 30, -- a match server waits this long for everyone to arrive
		VoteSeconds = 15, -- map vote once everyone is in
	},
	Tiers = {
		{ Name = "Bronze", Min = 0, Color = Color3.fromRGB(214, 132, 62), Icon = "🥉" },
		{ Name = "Silver", Min = 200, Color = Color3.fromRGB(190, 200, 220), Icon = "🥈" },
		{ Name = "Gold", Min = 450, Color = Color3.fromRGB(255, 196, 40), Icon = "🥇" },
		{ Name = "Platinum", Min = 800, Color = Color3.fromRGB(70, 225, 200), Icon = "💠" },
		{ Name = "Diamond", Min = 1250, Color = Color3.fromRGB(110, 160, 255), Icon = "💎" },
		-- Min here is only the RP needed to QUALIFY; the rank itself is the daily top 500
		{ Name = "Champion", Min = 2400, Color = Color3.fromRGB(255, 70, 110), Icon = "🏆" },
	},
	ChampionSlots = 500,
}

-- `champion` = this player is in today's top-500 Champion list (profile.champion on the
-- client, ChampionService on the server). Without it the ladder stops at Diamond I.
function Config.TierIndex(rp: number, champion: boolean?): number
	local tiers = Config.Ranked.Tiers
	if champion then
		return #tiers
	end
	local idx = 1
	for i = 1, #tiers - 1 do
		if rp >= tiers[i].Min then
			idx = i
		end
	end
	return idx
end

-- The tier table entry ({ Name, Min, Color, Icon }) for this many ranked points.
function Config.TierFor(rp: number, champion: boolean?)
	return Config.Ranked.Tiers[Config.TierIndex(rp, champion)]
end

local NUMERALS = { "III", "II", "I" }
-- Returns tier, division text ("III"/"II"/"I"/""), progress 0..1 to the next step,
-- RP needed for the next step, and the label of the next step.
function Config.DivisionFor(rp: number, champion: boolean?)
	local tiers = Config.Ranked.Tiers
	local ti = Config.TierIndex(rp, champion)
	local tier = tiers[ti]
	local nextTier = tiers[ti + 1]
	if not nextTier then
		return tier, "", 1, 0, string.format("Top %d driver", Config.Ranked.ChampionSlots)
	end
	if ti == #tiers - 1 and rp >= nextTier.Min then
		-- qualified: waits for the daily top-500 pick
		return tier, "I", 1, 0, string.format("Champion: be top %d at 00:00 UTC", Config.Ranked.ChampionSlots)
	end
	local span = (nextTier.Min - tier.Min) / 3
	local d = math.clamp(math.floor((rp - tier.Min) / span), 0, 2)
	local stepStart = tier.Min + d * span
	local stepEnd = stepStart + span
	local nextLabel = if d < 2
		then (tier.Name .. " " .. NUMERALS[d + 2])
		else (nextTier.Name .. (if tiers[ti + 2] then " III" else " (top " .. Config.Ranked.ChampionSlots .. ")"))
	return tier,
		NUMERALS[d + 1],
		math.clamp((rp - stepStart) / span, 0, 1),
		math.max(0, math.ceil(stepEnd - rp)),
		nextLabel
end

-- Display name such as "Gold II" or "Champion".
function Config.RankName(rp: number, champion: boolean?): string
	local tier, div = Config.DivisionFor(rp, champion)
	return if div ~= "" then tier.Name .. " " .. div else tier.Name
end

-- Highest tier reached this season (unlocks the ranked reward cosmetics). Champion counts
-- once the player has made the daily top 500 this season.
function Config.PeakTier(data): number
	if data.championSeason and data.championSeason == Config.Ranked.Season.Number then
		return #Config.Ranked.Tiers
	end
	return Config.TierIndex(data.peakRp or data.rp or 0)
end

-- Ranked leaderboard (OrderedDataStore) for a season. Season 1 keeps the original name, later
-- seasons get their own board so last season's points never fill this season's top 500.
function Config.RankedBoard(season: number?): string
	local n = season or Config.Ranked.Season.Number
	return if n <= 1 then Config.DataStores.Ranked else Config.DataStores.Ranked .. "_S" .. n
end

-- Time Trial medals relative to the circuit's ideal lap time
Config.Medals = {
	Names = { "Bronze", "Silver", "Gold", "Author" },
	Colors = {
		Color3.fromRGB(205, 127, 50),
		Color3.fromRGB(200, 205, 215),
		Color3.fromRGB(255, 205, 40),
		Color3.fromRGB(70, 230, 160),
	},
	GoldFactor = 1.1,
	AuthorFactor = 1.02,
	SilverFactor = 1.22,
	BronzeFactor = 1.38,
}

Config.Leaderboard = {
	TopCount = 25,
	CacheSeconds = 45,
}

-- Speed shown on HUD = studs/s * SpeedDisplayFactor (235 studs/s ~ 340 km/h)
Config.SpeedDisplayFactor = 1.45

-- rbxasset:// sounds ship with every Roblox client. Put a Creator Store engine loop
-- (rbxassetid://...) into EngineLoop for engine audio.
Config.Sounds = {
	Click = "rbxasset://sounds/button.wav",
	Countdown = "rbxasset://sounds/electronicpingshort.wav",
	Go = "rbxasset://sounds/electronicpingshort.wav",
	Checkpoint = "rbxasset://sounds/electronicpingshort.wav",
	Finish = "rbxasset://sounds/victory.wav",
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	Boost = "rbxasset://sounds/swoosh.wav",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Crash = "rbxasset://sounds/collide.wav",
	-- Car audio (free Creator Store sounds; EngineLoop is by Roblox Resources). Empty = off.
	EngineLoop = "rbxassetid://80317022777602",
	EngineHigh = "rbxassetid://108310914849076",
	TyreSqueal = "rbxassetid://109487442763183",
	Wind = "rbxassetid://5113213873",
	Shift = "",
}

-- The ranked season at unix time `t`. Season 1 ends at FirstSeasonEnds and every season
-- after it lasts SeasonDays, so seasons keep rolling over with no code change.
function Config.SeasonAt(t: number)
	local R = Config.Ranked
	local len = R.SeasonDays * 86400
	local n = 1
	if t >= R.FirstSeasonEnds then
		n = 2 + math.floor((t - R.FirstSeasonEnds) / len)
	end
	local endsAt = R.FirstSeasonEnds + (n - 1) * len
	return { Number = n, Name = "Season " .. n, EndsAt = endsAt, StartsAt = if n == 1 then 0 else endsAt - len }
end
-- Config.Ranked.Season always reads as the current season.
Config.Ranked.Season = setmetatable({}, {
	__index = function(_, key)
		return Config.SeasonAt(os.time())[key]
	end,
})

return Config
