--!nocheck
-- Builds the real menu pages outside Studio with a fake profile and dumps each screen
-- for tools/sim/uirender.py.
--   lune run tools/sim/menu.luau [page ...]     pages: home quick ranked timetrial leaderboards garage shop settings
local process = require("@lune/process")
local task = require("@lune/task")
local fs = require("@lune/fs")
local Env = require("./env")
local Dump = require("./dumpui")

local Cosmetics = Env.Require("src/shared/Cosmetics")
local Config = Env.Require("src/shared/Config")
local profile = {
	coins = 1250, xp = 340, level = 7, xpNeeded = 900, owned = {}, car = table.clone(Cosmetics.DefaultCar),
	bests = { lakeside = 61234, harbor = 70500 }, medals = { lakeside = 3, harbor = 1 },
	stats = { races = 14, wins = 3, podiums = 6, fastestLaps = 2, rankedRaces = 4, laps = 40 },
	rp = 1180, peakRp = 1240, peakTier = 2, history = {}, daily = { streak = 3, available = true },
	settings = {}, passes = {}, boostUntil = 0, serverTime = os.time(), offline = false, userId = 1,
}
-- challenge snapshot like ChallengeService.Snapshot builds it
do
	local Challenges = Env.Require("src/shared/Challenges")
	local w = Challenges.WeekAt(os.time())
	local list = {}
	for i, c in Challenges.ForWeek(w) do
		table.insert(list, { i = c.Index, text = c.Text, goal = c.Goal, progress = if i == 1 then c.Goal else math.floor(c.Goal / 2), coins = c.Coins, claimed = false })
	end
	local starter = {}
	for i, c in Challenges.Starter do
		table.insert(starter, { id = c.Id, text = c.Text, icon = c.Icon, goal = c.Goal, progress = if i <= 2 then 1 else 0, coins = c.Coins, claimed = i == 1 })
	end
	profile.challenges = { week = w, featured = Challenges.Featured(w), endsAt = Challenges.WeekEnds(w), list = list, starter = starter }
	profile.flags = { onboarded = false, coached = false }
	profile.daily = { streak = 3, available = false }
end
Env.Server.GetProfile = function()
	return profile
end
Env.Server.GetLobbies = function()
	return { lobbies = {} }
end
-- sample boards: a few players (the first ones Champions on the ranked board)
local SAMPLE_NAMES = { "Max Velocity", "Lina Slide", "Carlos Kerb", "Yuki Boost", "Pit Stopz", "Grid Walker", "Tura Boost", "Alex Turbo", "Nico Chicane", "Oscar Pace", "Zhou Sector", "Esteban Line" }
Env.Server.GetLeaderboard = function(kind)
	local entries = {}
	for i, n in SAMPLE_NAMES do
		local v = if kind == "ranked" then 3100 - i * 170 elseif kind == "tt" then 60000 + i * 850 elseif kind == "level" then (40 - i) * 1000000 else 120 - i * 9
		table.insert(entries, { userId = 1000 + i, name = n, value = v, rank = i, champion = kind == "ranked" and v >= 2400 })
	end
	return { ok = true, entries = entries, mine = if kind == "ranked" then profile.rp else nil }
end
Env.Server.SaveSettings = function()
	return { ok = true }
end

local State = Env.Require("src/client/State")
State.Profile = profile
local Kit = Env.Require("src/client/UI/Kit")
local Menu = Env.Require("src/client/UI/MainMenu")
local Pages = Env.Require("src/client/UI/RacePages")
local Garage = Env.Require("src/client/UI/Garage")
local Shop = Env.Require("src/client/UI/Shop")
local SettingsPage = Env.Require("src/client/UI/SettingsPage")
local ChallengesPanel = Env.Require("src/client/UI/ChallengesPanel")
local Onboarding = Env.Require("src/client/UI/Onboarding")
Menu.RegisterPage("quick", Pages.Quick)
Menu.RegisterPage("ranked", Pages.Ranked)
Menu.RegisterPage("timetrial", Pages.TimeTrial)
Menu.RegisterPage("leaderboards", Pages.Boards)
Menu.RegisterPage("garage", Garage)
Menu.RegisterPage("shop", Shop)
Menu.RegisterPage("settings", SettingsPage)

local pages = {}
for _, a in process.args do
	table.insert(pages, a)
end
if #pages == 0 then
	pages = { "home", "quick", "ranked", "timetrial", "leaderboards", "garage", "shop", "settings" }
end
fs.writeDir("tools/sim/out")
Menu.Show()
task.wait(0.2)
for _, pg in pages do
	local ok, err = pcall(function()
		if pg == "results" then
			-- a sample ranked result: you finished 4th
			local Results = Env.Require("src/client/UI/Results")
			local list = {}
			for i = 1, 10 do
				table.insert(list, { Rid = i, P = i, Name = if i == 4 then "Bardan" else SAMPLE_NAMES[i], IsAI = i ~= 4, UserId = if i == 4 then 1 else 0, Time = 98.5 + i * 0.7, Best = 47 + i * 0.3, Car = { Primary = "paint_red" } })
			end
			Results.Show({ Results = list, You = { Pos = 4, Coins = 180, XP = 72, RpDelta = 12, Rp = 1192, OldRp = 1180, Finished = true }, Mode = "ranked", TrackId = "dragon", Fastest = { Rid = 1 } }, 4, {
				{ "🏁 Race Again", "primary", function() end },
				{ "🏠 Menu", "secondary", function() end },
			})
		elseif pg == "searching" or pg == "found" or pg == "waiting" or pg == "vote" then
			-- the ranked lobby panel: cross-server search, match found, waiting for a rival, map vote
			Menu.Open("ranked")
			local t0 = 1000
			Env.SetServerTime(t0)
			local cands = { "capital", "alpine", "canyon" }
			local info = if pg == "searching"
				then { Id = "Q", Mode = "ranked", Searching = true, Since = t0 - 37, Queue = 6, Count = 1, Max = 10, EndsAt = t0 }
				elseif pg == "found" then { Id = "Q", Mode = "ranked", Found = true, Count = 4, Max = 10, EndsAt = t0 }
				elseif pg == "waiting" then { Id = "L1", Mode = "ranked", Candidates = cands, Votes = {}, Count = 1, Max = 10, EndsAt = t0 + 8, Waiting = true, Created = t0 - 42, Names = { "Bardan" } }
				else { Id = "L1", Mode = "ranked", Candidates = cands, Votes = { capital = 2, canyon = 1 }, MyVote = "capital", Count = 3, Max = 10, EndsAt = t0 + 12, Names = { "Bardan" } }
			Menu.SetLobby(info)
		elseif pg == "challenges" then
			ChallengesPanel.Open()
		elseif pg == "onboarding" or pg == "onboarding2" then
			Onboarding.Show()
		elseif pg ~= "home" then
			Menu.Open(pg)
		else
			Menu.Show()
		end
		task.wait(0.6)
		for _ = 1, 10 do
			Env.RunService.RenderStepped:Fire(1 / 30)
			Env.RunService.Heartbeat:Fire(1 / 30)
		end
		-- dump every enabled ScreenGui, merged: menu first, then the others on top
		local merged = { k = "ScreenGui", name = "merged", kids = {} }
		local guis = {}
		for _, g in Env.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled then
				table.insert(guis, g)
			end
		end
		table.sort(guis, function(a, b)
			return a.DisplayOrder < b.DisplayOrder
		end)
		for i, g in guis do
			Dump.Save(g, "tools/sim/out/ui_tmp.json")
			local j = require("@lune/serde").decode("json", fs.readFile("tools/sim/out/ui_tmp.json"))
			for _, kid in j.kids do
				kid.z = (kid.z or 1) + i * 100
				table.insert(merged.kids, kid)
			end
		end
		fs.writeFile("tools/sim/out/page_" .. pg .. ".json", require("@lune/serde").encode("json", merged))
		if pg == "results" then
			Env.Require("src/client/UI/Results").Hide()
		elseif pg == "searching" or pg == "found" or pg == "waiting" or pg == "vote" then
			Menu.SetLobby(nil)
			Menu.Back()
		elseif pg == "challenges" or pg == "onboarding" or pg == "onboarding2" then
			-- close the modal: it is the last child of the overlay root
			for _, c in Kit.OverlayRoot:GetChildren() do
				if c:IsA("TextButton") and c.ZIndex == 10 then
					c:Destroy()
				end
			end
		elseif pg ~= "home" then
			Menu.Back()
		end
	end)
	print(pg, if ok then "ok" else ("FAILED: " .. tostring(err)))
end
