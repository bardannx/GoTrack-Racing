--!nonstrict
-- The challenges window: this week's featured circuit (bonus coins), the 3 weekly
-- challenges with progress bars and CLAIM buttons, and the new-player checklist until it
-- is finished. Data comes from the profile snapshot (server-side ChallengeService).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Circuits = require(Shared.Circuits)
local Config = require(Shared.Config)
local Challenges = require(Shared.Challenges)

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local Util = require(script.Parent.Parent.Util)
local Fx = require(script.Parent.Parent.Fx)

local Panel = {}
local C = Kit.Colors

-- how many rewards are ready to claim (for the top-bar badge)
function Panel.Claimable(): number
	local p = State.Profile
	local ch = p and p.challenges
	if not ch then
		return 0
	end
	local n = 0
	for _, c in ch.list or {} do
		if not c.claimed and c.progress >= c.goal then
			n += 1
		end
	end
	for _, c in ch.starter or {} do
		if not c.claimed and c.progress >= c.goal then
			n += 1
		end
	end
	return n
end

-- Whether the new-player checklist is finished (then it's no longer shown).
function Panel.StarterDone(): boolean
	local ch = State.Profile and State.Profile.challenges
	if not ch then
		return true
	end
	for _, c in ch.starter or {} do
		if not c.claimed then
			return false
		end
	end
	return true
end

-- Countdown text to the weekly reset: "3d 4h" or "5h 12m".
local function timeLeft(endsAt: number): string
	local left = math.max(0, endsAt - os.time())
	if left >= 86400 then
		return string.format("%dd %dh", left // 86400, (left % 86400) // 3600)
	end
	return string.format("%dh %dm", left // 3600, (left % 3600) // 60)
end

-- One challenge: icon, text, progress bar, and a CLAIM button once it's complete.
local function row(
	parent,
	order: number,
	icon: string,
	text: string,
	progress: number,
	goal: number,
	coins: number,
	claimed: boolean,
	onClaim
)
	local done = progress >= goal
	local r = Kit.Card(
		parent,
		{ Size = UDim2.new(1, 0, 0, 60), LayoutOrder = order, ZIndex = 12 },
		if claimed then Color3.fromRGB(22, 34, 30) elseif done then Color3.fromRGB(46, 40, 18) else C.Panel2
	)
	Kit.IconTile(
		r,
		icon,
		38,
		if claimed then C.Success elseif done then C.Accent else C.Panel3,
		{ Position = UDim2.fromOffset(11, 11), ZIndex = 13 }
	)
	Kit.Label(r, text, 15, {
		Font = Kit.Fonts.Bold,
		Position = UDim2.fromOffset(64, 8),
		Size = UDim2.new(1, -220, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 13,
	})
	local _, fill = Kit.Bar(
		r,
		math.clamp(progress / goal, 0, 1),
		if done then C.Success else C.Accent2,
		{ Position = UDim2.fromOffset(64, 36), Size = UDim2.new(1, -280, 0, 10), ZIndex = 13 }
	)
	fill.ZIndex = 14
	Kit.Label(r, string.format("%d / %d", progress, goal), 13, {
		Font = Kit.Fonts.Title,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -150, 0, 31),
		Size = UDim2.fromOffset(60, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 13,
	})
	local reward = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(128, 40),
		ZIndex = 13,
		Parent = r,
	})
	if claimed then
		Kit.Label(reward, "✓ CLAIMED", 14, {
			Font = Kit.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Success,
			ZIndex = 14,
		})
	elseif done then
		Kit.Button(
			reward,
			"CLAIM  " .. Kit.Comma(coins),
			"success",
			onClaim,
			{ Size = UDim2.fromScale(1, 1), TextSize = 14, ZIndex = 14 }
		)
	else
		local coin = Kit.Coin(
			reward,
			22,
			{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), ZIndex = 14 }
		)
		coin.ZIndex = 14
		for _, d in coin:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 15
			end
		end
		Kit.Label(reward, Kit.Comma(coins), 16, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(44, 0),
			Size = UDim2.new(1, -44, 1, 0),
			TextColor3 = C.Gold,
			ZIndex = 14,
		})
	end
	return r
end

local current = nil

-- Opens the window (closing it first if it's already open, to rebuild it).
function Panel.Open()
	if current then
		current()
	end
	local p = State.Profile
	local ch = p and p.challenges
	local box, _, close = Kit.ModalFrame("🎯 Challenges", 720)
	current = close
	if not ch then
		Kit.Label(
			box,
			"Challenges load with your profile - try again in a moment.",
			15,
			{ LayoutOrder = 1, TextColor3 = C.SubText, ZIndex = 12 }
		)
		Kit.Button(box, "Close", "secondary", close, { LayoutOrder = 2, Size = UDim2.fromOffset(140, 44), ZIndex = 13 })
		return
	end
	local function claim(kind: string, id)
		return function()
			task.spawn(function()
				local res = Util.Invoke("ClaimChallenge", kind, id)
				if res and res.ok then
					Fx.Play("Purchase", 0.5)
					Kit.Toast(string.format("🎯 Challenge complete!  +%s coins", Kit.Comma(res.coins)), "success")
					task.wait(0.3)
					Panel.Open()
				else
					Kit.Toast((res and res.err) or "Couldn't claim", "warn")
				end
			end)
		end
	end

	-- featured circuit banner
	local fc = Circuits.ById[ch.featured]
	if fc then
		local banner =
			Kit.Card(box, { Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 1, ZIndex = 12 }, Color3.fromRGB(58, 44, 12))
		Kit.Stroke(banner, C.Accent, 1.5, 0.3)
		Kit.Label(
			banner,
			"⭐",
			26,
			{ Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(34, 58), ZIndex = 13 }
		)
		Kit.Label(banner, string.format("FEATURED THIS WEEK:  %s  %s", fc.Flag, string.upper(fc.Name)), 15, {
			Font = Kit.Fonts.Title,
			Position = UDim2.fromOffset(56, 8),
			Size = UDim2.new(1, -200, 0, 20),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 13,
		})
		Kit.Label(banner, string.format("Races here pay ×%.1f coins", Config.Economy.FeaturedCoinMultiplier), 13, {
			Font = Kit.Fonts.Bold,
			Position = UDim2.fromOffset(56, 30),
			Size = UDim2.new(1, -200, 0, 18),
			TextColor3 = C.Gold,
			ZIndex = 13,
		})
		Kit.Button(banner, "🏁 RACE", "primary", function()
			close()
			task.spawn(function()
				local res = Util.Invoke("QuickRace", fc.Id, false)
				if res and res.ok then
					Kit.Toast("Joined a race on " .. fc.Name .. "!", "success")
				else
					Kit.Toast((res and res.err) or "Couldn't join", "error")
				end
			end)
		end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(120, 40),
			TextSize = 15,
			ZIndex = 14,
		})
	end

	-- everything else scrolls, so the window always fits the screen
	local scroll = Kit.ScrollList(
		box,
		{ Size = UDim2.new(1, 0, 0, if Kit.Compact() then 230 else 380), LayoutOrder = 2, ZIndex = 12 },
		8
	)
	-- weekly
	local head = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2, ZIndex = 12, Parent = scroll }
	)
	Kit.Label(
		head,
		"THIS WEEK",
		13,
		{ Font = Kit.Fonts.Title, Size = UDim2.new(0.5, 0, 1, 0), TextColor3 = C.Accent2, ZIndex = 12 }
	)
	Kit.Label(head, "New challenges in " .. timeLeft(ch.endsAt or Challenges.WeekEnds(ch.week or 0)), 12, {
		Font = Kit.Fonts.Bold,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.SubText,
		ZIndex = 12,
	})
	local icons = { "🏁", "🏆", "⚡" }
	for i, c in ch.list or {} do
		row(scroll, 2 + i, icons[i] or "🎯", c.text, c.progress, c.goal, c.coins, c.claimed, claim("weekly", c.i))
	end

	-- getting started
	if not Panel.StarterDone() then
		Kit.Label(scroll, "GETTING STARTED", 13, {
			Font = Kit.Fonts.Title,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = 10,
			TextColor3 = C.Success,
			ZIndex = 12,
		})
		local order = 10
		for _, c in ch.starter or {} do
			if not c.claimed then
				order += 1
				row(scroll, order, c.icon or "✅", c.text, c.progress, c.goal, c.coins, false, claim("starter", c.id))
			end
		end
	end
	local btns = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 50, ZIndex = 12, Parent = box }
	)
	Kit.List(btns, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)
	Kit.Button(btns, "Close", "secondary", function()
		close()
		current = nil
	end, { Size = UDim2.fromOffset(140, 44), ZIndex = 13 })
end

return Panel
