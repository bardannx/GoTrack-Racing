--!nonstrict
-- Client entry point. Loads the profile, builds the menu and connects the pieces: the
-- menu starts races and time trials, and the results screen leads back to the menu.
-- Also registers a Studio-only hook (GoTrackDev) that test scripts use to open pages.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Circuits = require(Shared.Circuits)

local State = require(script.State)
local Util = require(script.Util)
local Kit = require(script.UI.Kit)
local Menu = require(script.UI.MainMenu)
local Pages = require(script.UI.RacePages)
local Garage = require(script.UI.Garage)
local Shop = require(script.UI.Shop)
local Results = require(script.UI.Results)
local SettingsPage = require(script.UI.SettingsPage)
local Fx = require(script.Fx)
require(script.PerfOverlay)
local RaceClient = require(script.RaceClient)
local Onboarding = require(script.UI.Onboarding)
local TimeTrialClient = require(script.TimeTrialClient)

local player = Players.LocalPlayer

Kit.Loading(
	true,
	"Warming up the tyres...",
	#Circuits.List .. " circuits  •  10-car grids  •  one champion",
	"GETTING READY"
)
State.Notify:Connect(function(msg, kind)
	Kit.Toast(msg, kind)
end)

-- chat tags
pcall(function()
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local speaker = Players:GetPlayerByUserId(source.UserId)
			if speaker then
				if speaker:GetAttribute("Owner") then
					props.PrefixText = "<font color='#FF4B5A'>[🛠️ OWNER]</font> " .. message.PrefixText
				elseif speaker:GetAttribute("Ultimate") then
					props.PrefixText = "<font color='#B478FF'>[💎 ULTIMATE]</font> " .. message.PrefixText
				elseif speaker:GetAttribute("VIP") then
					props.PrefixText = "<font color='#FFC828'>[👑 VIP]</font> " .. message.PrefixText
				end
			end
		end
		return props
	end
end)

if not State.Init() then
	Kit.Loading(true, "Couldn't reach the GoTrack servers. Please rejoin.")
	return
end

Menu.RegisterPage("quick", Pages.Quick)
Menu.RegisterPage("ranked", Pages.Ranked)
Menu.RegisterPage("timetrial", Pages.TimeTrial)
Menu.RegisterPage("leaderboards", Pages.Boards)
Menu.RegisterPage("garage", Garage)
Menu.RegisterPage("shop", Shop)
Menu.RegisterPage("settings", SettingsPage)

Fx.SetVolume((State.Setting("Sfx") or 80) / 100)
Fx.SetEngineVolume((State.Setting("Engine") or 100) / 100)
-- keep a listener so position packets that arrive between races are simply dropped
Net.UEvent("CarStates").OnClientEvent:Connect(function() end)

local lastRace = nil -- { Mode, TrackId }

-- Shows the results screen with Race Again / Menu buttons.
local function showResults(payload, yourRid)
	Menu.Hide()
	Results.Show(payload, yourRid, {
		{
			"🏁 Race Again",
			"primary",
			function()
				Menu.Show(if payload.Mode == "ranked" then "ranked" else "quick")
				task.spawn(function()
					local res
					if payload.Mode == "ranked" then
						res = Util.Invoke("RankedQueue")
					else
						res = Util.Invoke("QuickRace", payload.TrackId, false)
					end
					if res and not res.ok then
						Kit.Toast(res.err or "Couldn't join", "error")
					end
				end)
			end,
		},
		{
			"🏠 Menu",
			"secondary",
			function()
				Menu.Show()
			end,
		},
	})
end

-- a race is starting for us
Net.Event("RaceStart").OnClientEvent:Connect(function(info)
	if TimeTrialClient.IsActive() then
		TimeTrialClient.Exit()
	end
	Results.Hide()
	Menu.SetLobby(nil)
	Menu.Hide()
	lastRace = { Mode = info.Mode, TrackId = info.TrackId }
	RaceClient.Start(info, {
		OnResults = function(payload, yourRid)
			showResults(payload, yourRid)
		end,
		OnQuit = function(finished)
			Menu.Show(if lastRace and lastRace.Mode == "ranked" then "ranked" else "quick")
			if finished then
				Kit.Toast("Your result is saved - results arrive when the race ends.", "info")
			end
		end,
	})
end)

-- results for a race we left early (after finishing)
Net.Event("RaceResults").OnClientEvent:Connect(function(payload)
	if not RaceClient.IsActive() and payload.LeftEarly and not TimeTrialClient.IsActive() then
		local you = payload.You or {}
		Kit.Toast(
			string.format(
				"🏁 Race over - you finished P%s  (+%s coins)",
				tostring(you.Pos or "?"),
				tostring(you.Coins or 0)
			),
			"success"
		)
	end
end)

Menu.StartTimeTrial = function(opts)
	if Menu.Lobby then
		Kit.Toast("Leave your race lobby first!", "warn")
		return
	end
	Menu.Hide()
	opts.onExit = function()
		Menu.Show("timetrial")
	end
	TimeTrialClient.Start(opts)
end

-- brand-new players get the welcome tour first (the daily reward waits until it's done)
local needTour = Onboarding.Needed()
Menu.HoldDaily = needTour
Menu.Show()
task.wait(0.5)
Kit.Loading(false)
if needTour then
	task.delay(0.6, function()
		Onboarding.Show(function(startedRace)
			Menu.HoldDaily = false
			if not startedRace then
				Menu.ShowDaily()
			end
		end)
	end)
end

-- Studio-only test hook (lets automated play-tests drive the menus)
if game:GetService("RunService"):IsStudio() then
	local dev = Instance.new("BindableFunction")
	dev.Name = "GoTrackDev"
	dev.OnInvoke = function(cmd, a, b)
		if cmd == "open" then
			Menu.Open(a, b)
		elseif cmd == "back" then
			Menu.Back()
		elseif cmd == "setting" then
			State.SetSetting(a, b)
		elseif cmd == "invoke" then
			return Util.Invoke(a, b)
		elseif cmd == "daily" then
			Menu.ShowDaily()
		elseif cmd == "results" then
			-- sample results screen for layout testing on every device size
			local mine = math.clamp(tonumber(b) or 3, 1, 10)
			local names = {
				"Alex Turbo",
				"Carlos Kerb",
				"Yuki Boost",
				"Charles Apex",
				"Max Velocity",
				"Fernando Gear",
				"Lina Slide",
				"Pit Stopz",
				"Grid Walker",
				"Tura Boost",
			}
			names[mine] = player.DisplayName
			local rows = {}
			for i, n in names do
				local me = i == mine
				table.insert(rows, {
					Rid = i,
					Name = n,
					IsAI = not me,
					UserId = if me then player.UserId else 0,
					P = i,
					Finished = true,
					Time = 209.753 + i * 0.6,
					Best = 51.2 + i * 0.1,
					Car = State.Profile.car,
				})
			end
			showResults({
				Results = rows,
				You = {
					Pos = mine,
					Coins = 120,
					XP = 60,
					Finished = true,
					RpDelta = if a == "ranked" then 18 else nil,
					Rp = 180,
					OldRp = 180,
					Fastest = true,
				},
				Mode = a or "quick",
				TrackId = "capital",
				Fastest = { Rid = mine },
			}, mine)
		end
		return true
	end
	dev.Parent = player
end
