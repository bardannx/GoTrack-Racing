--!nonstrict
-- Server entry point. Starts every service and handles the client's requests: equipping
-- and buying cosmetics, daily rewards, challenges, joining races and time trials, and
-- leaderboards. Every handler checks its arguments itself, never trusting the client.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Cosmetics = require(Shared.Cosmetics)
local Circuits = require(Shared.Circuits)

local DataService = require(script.DataService)
local MonetizationService = require(script.MonetizationService)
local LeaderboardService = require(script.LeaderboardService)
local RaceManager = require(script.RaceManager)
local TimeTrial = require(script.TimeTrial)
local ChallengeService = require(script.ChallengeService)
local ChampionService = require(script.ChampionService)

Net.GetFolder()
local NotifyEvent = Net.Event("Notify")
local ProfileEvent = Net.Event("ProfileUpdated")

-- Shows the player a toast message (kind: info, success, warn, error).
local function notify(player: Player, msg: string, kind: string?)
	NotifyEvent:FireClient(player, msg, kind or "info")
end
MonetizationService.SetNotifier(notify)
RaceManager.SetNotifier(notify)

---------------------------------------------------------------------------
-- Profile snapshot
---------------------------------------------------------------------------
local function canClaimDaily(data): boolean
	return os.time() - (data.daily.last or 0) >= 20 * 3600
end

-- streak the next claim builds on (0 once a day was missed, so the popup shows day 1)
local function liveStreak(data): number
	if os.time() - (data.daily.last or 0) < 48 * 3600 then
		return data.daily.streak or 0
	end
	return 0
end

-- The part of a save the client is allowed to see, sent whenever it changes.
local function snapshot(player: Player)
	local d = DataService.Get(player)
	if not d then
		return nil
	end
	return {
		coins = d.coins,
		xp = d.xp,
		level = d.level,
		xpNeeded = Config.XPForLevel(d.level),
		owned = d.owned,
		car = d.car,
		bests = d.bests,
		medals = d.medals,
		stats = d.stats,
		rp = d.rp,
		peakRp = d.peakRp,
		peakTier = Config.PeakTier(d),
		champion = ChampionService.IsChampion(player.UserId, d.rp),
		championInfo = ChampionService.Info(),
		history = d.history,
		daily = { streak = liveStreak(d), available = canClaimDaily(d) },
		settings = d.settings,
		passes = MonetizationService.GetPasses(player),
		boostUntil = d.boostUntil,
		serverTime = os.time(),
		offline = DataService.Offline(),
		userId = player.UserId,
		challenges = ChallengeService.Snapshot(d),
		flags = { onboarded = d.flags.onboarded == true, coached = d.flags.coached == true },
	}
end

-- Wins, rank and level on the Roblox player list.
local function updateLeaderstats(player: Player)
	local d = DataService.Get(player)
	if not d then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		for _, n in { "Wins", "Rank", "Level" } do
			local v = if n == "Rank" then Instance.new("StringValue") else Instance.new("IntValue")
			v.Name = n
			v.Parent = ls
		end
		ls.Parent = player
	end
	ls.Wins.Value = d.stats.wins
	ls.Level.Value = d.level
	ls.Rank.Value = Config.RankName(d.rp or 0, ChampionService.IsChampion(player.UserId, d.rp))
	player:SetAttribute("RP", d.rp)
end

local pushQueued = {}
DataService.OnChanged(function(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		if player.Parent then
			local snap = snapshot(player)
			if snap then
				ProfileEvent:FireClient(player, snap)
			end
			updateLeaderstats(player)
		end
	end)
end)

---------------------------------------------------------------------------
-- Rate limiting and remote handlers
---------------------------------------------------------------------------
local buckets = {}
local HEAVY = { GetLeaderboard = true, GetGhost = true, GetLobbies = true }

-- Token bucket per player and remote: a burst of 15 calls (10 for the heavy ones),
-- refilled at 5 per second (2). Stops a client from spamming the server.
local function allow(player: Player, name: string): boolean
	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end
	local cap = if HEAVY[name] then 10 else 15
	local refill = if HEAVY[name] then 2 else 5
	local b = pb[name]
	local t = os.clock()
	if not b then
		b = { tokens = cap, t = t }
		pb[name] = b
	end
	b.tokens = math.min(cap, b.tokens + (t - b.t) * refill)
	b.t = t
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- Registers a remote handler with rate limiting and error catching, so a bad call
-- returns an error to that client instead of breaking the server.
local function bind(name: string, fn)
	Net.Function(name).OnServerInvoke = function(player: Player, ...)
		if not allow(player, name) then
			return { ok = false, err = "Slow down a little!" }
		end
		local args = table.pack(...)
		local ok, result = pcall(function()
			return fn(player, table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn("[GoTrack] Remote", name, "error:", result)
			return { ok = false, err = "Something went wrong" }
		end
		return result
	end
end

---------------------------------------------------------------------------
-- Profile, garage & shop
---------------------------------------------------------------------------
bind("GetProfile", function(player)
	DataService.WaitFor(player, 20)
	return snapshot(player)
end)

bind("BuyItem", function(player, itemId)
	local d = DataService.Get(player)
	local item = if typeof(itemId) == "string" then Cosmetics.ById[itemId] else nil
	if not d or not item then
		return { ok = false, err = "Item not found" }
	end
	if item.Pass then
		return { ok = false, err = "This item comes with a game pass" }
	end
	if item.Price <= 0 or d.owned[item.Id] then
		return { ok = false, err = "You already own this" }
	end
	if d.coins < item.Price then
		return { ok = false, err = "Not enough coins" }
	end
	d.coins -= item.Price
	d.owned[item.Id] = true
	DataService.Changed(player)
	return { ok = true }
end)

bind("Equip", function(player, slot, itemId)
	local d = DataService.Get(player)
	if not d or typeof(slot) ~= "string" or typeof(itemId) ~= "string" then
		return { ok = false, err = "Bad request" }
	end
	local category = Cosmetics.Slots[slot]
	local item = Cosmetics.ById[itemId]
	if not category or not item or item.Category ~= category then
		return { ok = false, err = "Can't equip that there" }
	end
	if not Cosmetics.CanUse(item, d.owned, MonetizationService.GetPasses(player), Config.PeakTier(d)) then
		return { ok = false, err = "Locked" }
	end
	d.car[slot] = itemId
	if slot == "Body" and d.car[slot] ~= nil then
		-- factory colours for this chassis (free to use from now on)
		local livery = Cosmetics.BodyLivery[itemId]
		if livery then
			for liverySlot, liveryId in livery do
				if Cosmetics.ById[liveryId] then
					d.car[liverySlot] = liveryId
					d.owned[liveryId] = true
				end
			end
		end
	end
	if slot == "Title" then
		player:SetAttribute("Title", item.Text or "Racer")
	end
	d.stats.equips = (d.stats.equips or 0) + 1
	DataService.Changed(player)
	return { ok = true }
end)

bind("SetNumber", function(player, number)
	local d = DataService.Get(player)
	local n = tonumber(number)
	if not d or not n or n ~= math.floor(n) or n < 1 or n > 99 then
		return { ok = false, err = "Pick a number from 1 to 99" }
	end
	if not MonetizationService.Has(player, "ProRacer") then
		return { ok = false, err = "Requires the Pro Racer Pack" }
	end
	d.car.Number = n
	DataService.Changed(player)
	return { ok = true, number = n }
end)

bind("ClaimDaily", function(player)
	local d = DataService.Get(player)
	if not d then
		return { ok = false }
	end
	if not canClaimDaily(d) then
		return { ok = false, err = "Come back later!" }
	end
	d.daily.streak = liveStreak(d) + 1
	d.daily.last = os.time()
	local rewards = Config.Economy.DailyRewards
	local amount = rewards[((d.daily.streak - 1) % #rewards) + 1]
	if MonetizationService.Has(player, "VIP") then
		amount *= 2
	end
	d.coins += amount
	DataService.Changed(player)
	return { ok = true, coins = amount, streak = d.daily.streak }
end)

local SETTINGS_KEYS = {
	Fov = "number",
	Shake = "boolean",
	Units = "string",
	ShowGhosts = "boolean",
	Quality = "number",
	ShowPBGhost = "boolean",
	Camera = "string",
	NameTags = "boolean",
	RacingLine = "string",
	ShowFPS = "boolean",
	Sfx = "number",
	Engine = "number",
	SpeedFov = "boolean",
}
-- weekly challenges and the getting-started checklist
bind("ClaimChallenge", function(player, kind, id)
	return ChallengeService.Claim(player, kind, id)
end)

-- one-off tutorial flags (welcome tour seen, first-race coaching done)
local FLAGS = { onboarded = true, coached = true }
bind("SetFlag", function(player, flag)
	local d = DataService.Get(player)
	if not d or typeof(flag) ~= "string" or not FLAGS[flag] then
		return { ok = false }
	end
	if not d.flags[flag] then
		d.flags[flag] = true
		DataService.Changed(player)
	end
	return { ok = true }
end)

bind("SaveSettings", function(player, settings)
	local d = DataService.Get(player)
	if not d or typeof(settings) ~= "table" then
		return { ok = false }
	end
	for k, ty in SETTINGS_KEYS do
		local v = settings[k]
		if typeof(v) == ty and v == v then -- (v == v rejects NaN, which can't be saved)
			if ty == "string" then
				v = string.sub(v, 1, 12)
			elseif ty == "number" then
				v = math.clamp(v, 0, 200)
			end
			d.settings[k] = v
		end
	end
	return { ok = true }
end)

---------------------------------------------------------------------------
-- Races
---------------------------------------------------------------------------
bind("GetLobbies", function(player)
	return RaceManager.GetLobbies(player)
end)
bind("QuickRace", function(player, trackId, private, laps)
	return RaceManager.QuickRace(player, trackId, private, laps)
end)
bind("RankedQueue", function(player)
	return RaceManager.RankedQueue(player)
end)
bind("JoinLobby", function(player, id)
	return RaceManager.JoinLobby(player, id)
end)
bind("LeaveLobby", function(player)
	return RaceManager.LeaveLobby(player)
end)
bind("StartNow", function(player)
	return RaceManager.StartNow(player)
end)
bind("VoteMap", function(player, trackId)
	return RaceManager.VoteMap(player, trackId)
end)

---------------------------------------------------------------------------
-- Time trial & leaderboards
---------------------------------------------------------------------------
bind("TTStart", function(player, trackId)
	if RaceManager.InRace(player) then
		return { ok = false, err = "Finish your race first" }
	end
	return TimeTrial.Start(player, trackId)
end)
bind("TTSubmitLap", function(player, token, lapMs, frames, rate)
	return TimeTrial.SubmitLap(player, token, lapMs, frames, rate)
end)

-- value of a board for one player's data (nil = not on this board)
local function boardValue(d, kind, id)
	if kind == "tt" then
		return d.bests[id]
	elseif kind == "ranked" then
		return d.rp
	elseif kind == "wins" then
		return if d.stats.wins > 0 then d.stats.wins else nil
	elseif kind == "level" then
		return d.level * 1000000 + d.xp
	end
	return nil
end

local STORES = {
	ranked = function()
		return Config.RankedBoard(), false -- this season's board
	end,
	wins = function()
		return Config.DataStores.Wins, false
	end,
	level = function()
		return Config.DataStores.Level, false
	end,
}

bind("GetLeaderboard", function(player, kind, id)
	local d = DataService.Get(player)
	local storeName, ascending
	if kind == "tt" then
		if not Circuits.ById[id] then
			return { ok = false }
		end
		storeName, ascending = Config.DataStores.LeaderboardPrefix .. id, true
	elseif STORES[kind] then
		storeName, ascending = STORES[kind]()
	else
		return { ok = false }
	end
	local entries = table.clone(LeaderboardService.GetTop(storeName, ascending))
	-- merge everyone in this server with their live value (boards are never empty in-game)
	for _, pl in Players:GetPlayers() do
		local pd = DataService.Get(pl)
		local v = pd and boardValue(pd, kind, id)
		if v then
			local found = false
			for i, e in entries do
				if e.userId == pl.UserId then
					found = true
					entries[i] = { userId = e.userId, name = pl.DisplayName, value = v, rank = e.rank }
				end
			end
			if not found then
				table.insert(entries, { userId = pl.UserId, name = pl.DisplayName, value = v, rank = 0 })
			end
		end
	end
	table.sort(entries, function(a, b)
		if ascending then
			return a.value < b.value
		end
		return a.value > b.value
	end)
	while #entries > Config.Leaderboard.TopCount do
		table.remove(entries)
	end
	for i, e in entries do
		local out = table.clone(e)
		out.rank = i
		if kind == "ranked" then
			out.champion = ChampionService.IsChampion(e.userId, e.value)
		end
		entries[i] = out
	end
	return {
		ok = true,
		entries = entries,
		mine = if d then boardValue(d, kind, id) else nil,
		champion = if kind == "ranked" and d then ChampionService.IsChampion(player.UserId, d.rp) else nil,
	}
end)

bind("GetGhost", function(_player, trackId, userId)
	if not Circuits.ById[trackId] or typeof(userId) ~= "number" then
		return nil
	end
	return LeaderboardService.GetGhost(trackId, userId)
end)

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------
MonetizationService.Init()
RaceManager.Init()
ChampionService.Start()

DataService.Loaded:Connect(function(player: Player)
	updateLeaderstats(player)
	local d = DataService.Get(player)
	if d then
		LeaderboardService.SetValue(Config.DataStores.Level, player.UserId, d.level * 1000000 + d.xp, false)
	end
	if DataService.Offline() then
		notify(player, "⚠️ Saving is offline in this session (enable Studio API access to test saving).", "warn")
	end
end)
DataService.Init()

Players.PlayerRemoving:Connect(function(player)
	TimeTrial.Cleanup(player)
	buckets[player] = nil
	pushQueued[player] = nil
end)

print(string.format("[GoTrack Racing] Server v%s ready - %d circuits.", Config.Version, #Circuits.List))
