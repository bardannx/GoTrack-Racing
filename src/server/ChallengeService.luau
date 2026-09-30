--!nonstrict
-- Weekly challenges, the featured-circuit bonus and the new-player checklist.
-- Progress is counted here from race results, Time Trial laps and Garage changes, and
-- rewards are paid here - clients only ask to claim. Rules live in shared/Challenges.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Challenges = require(Shared.Challenges)

local DataService = require(script.Parent.DataService)

local ChallengeService = {}

-- this week's progress table for a profile (reset when the week changes)
local function weekState(d)
	local w = Challenges.WeekAt(os.time())
	local wk = d.weekly
	if typeof(wk) ~= "table" or wk.week ~= w then
		wk = { week = w, counts = {}, claimed = {} }
		d.weekly = wk
	end
	return wk, w
end

function ChallengeService.Bump(d, stat: string, n: number?)
	local wk = weekState(d)
	wk.counts[stat] = (wk.counts[stat] or 0) + (n or 1)
end

-- the featured circuit this week (races there pay bonus coins)
function ChallengeService.Featured(): string
	return Challenges.Featured(Challenges.WeekAt(os.time()))
end

-- r: { finished, pos, laps, ranked, trackId, fastest }
function ChallengeService.RaceResult(d, r)
	if r.laps and r.laps > 0 then
		ChallengeService.Bump(d, "laps", r.laps)
	end
	if not r.finished then
		return
	end
	ChallengeService.Bump(d, "races")
	if r.pos <= 5 then
		ChallengeService.Bump(d, "top5")
	end
	if r.pos <= 3 then
		ChallengeService.Bump(d, "podiums")
	end
	if r.pos == 1 then
		ChallengeService.Bump(d, "wins")
	end
	if r.ranked then
		ChallengeService.Bump(d, "ranked")
	end
	if r.trackId == ChallengeService.Featured() then
		ChallengeService.Bump(d, "featured")
	end
	if r.fastest then
		ChallengeService.Bump(d, "fastest")
	end
end

-- what the client shows
function ChallengeService.Snapshot(d)
	local wk, w = weekState(d)
	local list = {}
	for _, c in Challenges.ForWeek(w) do
		table.insert(list, {
			i = c.Index,
			text = c.Text,
			goal = c.Goal,
			progress = math.min(wk.counts[c.Stat] or 0, c.Goal),
			coins = c.Coins,
			claimed = wk.claimed[tostring(c.Index)] == true,
		})
	end
	local starter = {}
	d.starter = d.starter or {}
	for _, c in Challenges.Starter do
		table.insert(starter, {
			id = c.Id,
			text = c.Text,
			icon = c.Icon,
			goal = c.Goal,
			progress = math.min(d.stats[c.Stat] or 0, c.Goal),
			coins = c.Coins,
			claimed = d.starter[c.Id] == true,
		})
	end
	return { week = w, featured = Challenges.Featured(w), endsAt = Challenges.WeekEnds(w), list = list, starter = starter }
end

-- kind: "weekly" (id = 1..3) or "starter" (id = checklist id)
function ChallengeService.Claim(player: Player, kind: any, id: any)
	local d = DataService.Get(player)
	if not d then
		return { ok = false, err = "Data not loaded" }
	end
	if kind == "weekly" then
		local wk, w = weekState(d)
		for _, c in Challenges.ForWeek(w) do
			if c.Index == id then
				if wk.claimed[tostring(c.Index)] then
					return { ok = false, err = "Already claimed" }
				end
				if (wk.counts[c.Stat] or 0) < c.Goal then
					return { ok = false, err = "Not finished yet" }
				end
				wk.claimed[tostring(c.Index)] = true
				d.coins += c.Coins
				DataService.Changed(player)
				return { ok = true, coins = c.Coins }
			end
		end
	elseif kind == "starter" then
		d.starter = d.starter or {}
		for _, c in Challenges.Starter do
			if c.Id == id then
				if d.starter[c.Id] then
					return { ok = false, err = "Already claimed" }
				end
				if (d.stats[c.Stat] or 0) < c.Goal then
					return { ok = false, err = "Not finished yet" }
				end
				d.starter[c.Id] = true
				d.coins += c.Coins
				DataService.Changed(player)
				return { ok = true, coins = c.Coins }
			end
		end
	end
	return { ok = false, err = "Unknown challenge" }
end

return ChallengeService
