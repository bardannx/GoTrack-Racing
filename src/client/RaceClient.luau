--!nonstrict
-- Multiplayer race runtime: builds the circuit, puts you on the grid, runs the F1 start
-- lights, times your laps, reports timing gates to the server, draws the other racers,
-- and shows the results.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Track = require(Shared.Track)
local Circuits = require(Shared.Circuits)
local Medals = require(Shared.Medals)

local State = require(script.Parent.State)
local Fx = require(script.Parent.Fx)
local CircuitBuilder = require(script.Parent.CircuitBuilder)
local CarController = require(script.Parent.CarController)
local RemoteCars = require(script.Parent.RemoteCars)
local Cam = require(script.Parent.CameraController)
local Kit = require(script.Parent.UI.Kit)
local Hud = require(script.Parent.UI.Hud)
local RacingLine = require(script.Parent.RacingLine)
local Perf = require(script.Parent.PerfOverlay)
local Intro = require(script.Parent.UI.CircuitIntro)
local Onboarding = require(script.Parent.UI.Onboarding)

local RaceClient = {}

local player = Players.LocalPlayer
local active = nil

local GateEvent = Net.Event("RaceGate")
local StandingsEvent = Net.Event("RaceStandings")
local ResultsEvent = Net.Event("RaceResults")
local LeaveEvent = Net.Event("RaceLeave")
local StateOut = Net.UEvent("CarState")
local StatesIn = Net.UEvent("CarStates")
local BumpOut = Net.UEvent("Bump")
local ResetEvent = Net.Event("RaceReset")

local SECTOR_END = { [9] = 1, [17] = 2, [1] = 3 } -- gate crossed -> sector finished

function RaceClient.IsActive(): boolean
	return active ~= nil
end

local function spawnCF(t, s: number, lateral: number): CFrame
	local x, y, z, tx, ty, tz = Track.PointAt(t, s, lateral)
	local p = Vector3.new(x, y + 0.6 + 2.1, z)
	return CFrame.lookAt(p, p + Vector3.new(tx, ty, tz))
end

local function cleanup(race)
	for _, c in race.Connections do
		c:Disconnect()
	end
	if race.Car then
		race.Car:Destroy()
	end
	if race.Remote then
		race.Remote:Destroy()
	end
	RacingLine.Stop()
	Intro.Stop()
	CircuitBuilder.Clear()
	Hud.Hide()
	Cam.Stop()
	Cam.SetTrack(nil)
end

-- info: RaceStart payload. handlers: { OnResults(payload, yourRid), OnQuit() }
function RaceClient.Start(info, handlers)
	if active then
		cleanup(active)
		active = nil
	end
	local t = Track.Get(info.TrackId)
	local circuit = Circuits.ById[info.TrackId]
	local race = {
		Info = info,
		Track = t,
		Connections = {},
		NextGate = 1,
		LapsDone = -1,
		LapStart = nil,
		LastLap = nil,
		BestLap = nil,
		Finished = false,
		Started = false,
		LastIdx = nil,
		LightsShown = -1,
		OffTime = 0,
		WrongTime = 0,
		SectorStart = 0,
		BestSectors = {},
		GateTimes = {},
		BestGateTimes = nil,
		Standings = nil,
		MyPos = info.YourRid,
		LeftEarly = false,
		MismatchSince = false,
		GhostUntil = 0,
		WreckedTime = 0,
		Repairing = false,
		IntroDone = false,
		EndIntro = function() end,
	}
	active = race
	local me = nil
	for _, r in info.Racers do
		if r.Rid == info.YourRid then
			me = r
		end
	end
	-- the circuit intro covers the build, then flies over the circuit until the lights
	Intro.Begin(info.TrackId, { Mode = info.Mode, Laps = info.Laps, Slot = me.Slot, Racers = #info.Racers })
	local okBuild, world = pcall(CircuitBuilder.Build, info.TrackId, State.Setting("Quality"), Intro.Progress)
	if not okBuild then
		-- never leave the player stuck on the intro: back to the menu
		warn("[GoTrack] Circuit failed to build:", world)
		Kit.Toast("Couldn't load that circuit - sorry! Try another race.", "error")
		RaceClient.Quit(handlers)
		return
	end
	race.World = world
	local gs, lat = Track.GridSlot(t, me.Slot)
	race.GridCF = spawnCF(t, gs, lat)
	local car = CarController.new(State.Profile.car, race.GridCF, world.Surface, player.UserId)
	race.Car = car
	race.LastIdx = Track.Wrap(t, math.floor(gs / Track.DS) + 1)
	car.OnStuck = function()
		RaceClient.Reset()
	end
	car.OnLand = function(air)
		if air > 0.8 then
			Cam.Shake(0.6)
		end
	end
	car.OnImpact = function(e, _kind)
		Cam.Shake(0.4 + e * 1.4)
		Hud.SetDamage(car.Damage)
		if car.Wrecked then
			Hud.Message("💥 CAR WRECKED - press R to repair", Kit.Colors.Danger, 2.5)
		elseif e > 0.35 then
			Hud.Message("💥 DAMAGE!", Kit.Colors.Warn, 1.2)
		end
	end
	race.Remote = RemoteCars.new(info.Racers, info.YourRid, info.GoTime)
	-- wet / night effects on every car (rain spray, rain lights)
	local wet = world.Theme and world.Theme.Weather == "rain"
	local night = world.Theme and world.Theme.Night == true
	car:SetConditions(wet, night)
	race.Remote:SetConditions(wet, night)
	car.GetOthers = function()
		return race.Remote:Solid()
	end
	car.OnBumpAI = function(rid, impulse)
		local b = buffer.create(5)
		buffer.writeu8(b, 0, rid)
		buffer.writei16(b, 1, math.clamp(math.floor(impulse.X * 10), -32000, 32000))
		buffer.writei16(b, 3, math.clamp(math.floor(impulse.Z * 10), -32000, 32000))
		BumpOut:FireServer(b)
	end
	Cam.SetTrack(t)

	Hud.Show({
		mode = "race",
		trackName = circuit.Flag .. "  " .. circuit.Name,
		laps = info.Laps,
		racers = info.Racers,
		yourRid = info.YourRid,
		minimap = t.Minimap,
	})
	Hud.SetVisible(false)
	Hud.SetPosition(me.Slot, #info.Racers)
	Hud.SetCallbacks({
		Reset = function()
			RaceClient.Reset()
		end,
		Exit = function()
			if race.Finished then
				RaceClient.Quit(handlers)
				return
			end
			Kit.Modal("Leave the race?", "You'll be marked DNF and won't earn position rewards.", {
				{ "Keep racing", "secondary" },
				{ "Leave", "danger", function()
					RaceClient.Quit(handlers)
				end },
			})
		end,
	})
	Cam.Chase(car)
	RacingLine.Start(t, car)
	Hud.SetDamage(car.Damage)

	table.insert(race.Connections, StatesIn.OnClientEvent:Connect(function(b)
		if active == race then
			race.Remote:Push(b)
		end
	end))
	table.insert(race.Connections, StandingsEvent.OnClientEvent:Connect(function(s)
		if active ~= race then
			return
		end
		race.Standings = s
		Hud.UpdateTower(s)
		local posMap = {}
		for _, e in s.List do
			posMap[e.Rid] = e.P
			if e.Rid == info.YourRid then
				race.MyPos = e.P
				Hud.SetPosition(e.P, #s.List)
				-- the server is authoritative for the next gate (adopt only a persistent mismatch)
				if e.NG and e.NG ~= race.NextGate and not race.Finished then
					race.MismatchSince = race.MismatchSince or os.clock()
					if os.clock() - race.MismatchSince > 1.2 then
						race.NextGate = e.NG
						race.MismatchSince = false
					end
				else
					race.MismatchSince = false
				end
			end
		end
		race.Remote:SetPositions(posMap)
		if State.HasPass("ProRacer") then
			local ahead, behind = nil, nil
			for i, e in s.List do
				if e.Rid == info.YourRid then
					ahead = s.List[i - 1]
					behind = s.List[i + 1]
				end
			end
			local mine = nil
			for _, e in s.List do
				if e.Rid == info.YourRid then
					mine = e
				end
			end
			local txt = ""
			if ahead and mine and mine.G and (ahead.G or ahead.P == 1) then
				txt ..= string.format("AHEAD -%.2f  ", mine.G - (ahead.G or 0))
			end
			if behind and behind.G and mine then
				txt ..= string.format("BEHIND +%.2f", behind.G - (mine.G or 0))
			end
			Hud.SetGapText(txt)
		end
	end))
	-- the server ended this race without results (it broke): back to the menu
	table.insert(race.Connections, LeaveEvent.OnClientEvent:Connect(function()
		if active == race then
			RaceClient.Quit(handlers)
		end
	end))
	table.insert(race.Connections, ResultsEvent.OnClientEvent:Connect(function(payload)
		if active == race and payload.SessionId == info.SessionId then
			active = nil
			cleanup(race)
			if handlers.OnResults then
				handlers.OnResults(payload, info.YourRid)
			end
		end
	end))
	table.insert(race.Connections, UserInputService.InputBegan:Connect(function(io, processed)
		if processed or active ~= race then
			return
		end
		local k = io.KeyCode
		if k == Enum.KeyCode.R or k == Enum.KeyCode.ButtonY or k == Enum.KeyCode.Backspace then
			RaceClient.Reset()
		elseif k == Enum.KeyCode.P or k == Enum.KeyCode.ButtonStart or k == Enum.KeyCode.Tab then
			Hud.TogglePause()
		elseif k == Enum.KeyCode.C or k == Enum.KeyCode.ButtonSelect then
			Hud.CameraToast(State.CycleCamera())
		end
	end))

	local sendTimer = 0
	local mapTimer = 0
	table.insert(race.Connections, RunService.Heartbeat:Connect(function(dt)
		if active ~= race then
			return
		end
		local now = workspace:GetServerTimeNow()
		local chassis = car.Chassis
		if not chassis.Parent then
			return
		end
		-- start lights (the intro always hands over before the first light)
		if not race.IntroDone and now >= info.LightsStart - 0.3 then
			race.EndIntro()
		end
		if not race.Started then
			-- countdown: 3 (2 red lights), 2 (4 red), 1 (all 5 red) ... then green GO
			if now >= info.LightsStart and now < info.GoTime then
				local num = math.clamp(math.ceil(info.GoTime - now - 1e-3), 1, 3)
				if num ~= race.LightsShown then
					race.LightsShown = num
					local red = ({ [3] = 2, [2] = 4, [1] = 5 })[num]
					Hud.SetLights(red)
					CircuitBuilder.SetStartLights(red)
					Hud.Message(tostring(num), Color3.fromRGB(255, 60, 60), 0.9)
					Fx.Play("Countdown", 0.5, 0.9)
				end
			end
			if now >= info.GoTime then
				race.Started = true
				Hud.SetLights("go")
				CircuitBuilder.SetStartLights(-1)
				car:Freeze(false)
				car.Enabled = true
				Fx.Play("Go", 0.7, 1.4)
				Hud.Message("GO!", Kit.Colors.Success, 1.4)
				-- a few tips during the player's very first race
				Onboarding.CoachFirstRace(Hud.Message, function()
					return active == race and not race.Finished
				end)
				task.delay(1.5, function()
					if active == race then
						Hud.SetLights(-1)
						CircuitBuilder.SetStartLights(0)
					end
				end)
			end
		end
		local raceTime = now - info.GoTime
		-- position on track
		local p = chassis.Position
		local idx, lateral, vertical = Track.Project(t, p.X, p.Y, p.Z, race.LastIdx)
		local prev = race.LastIdx or idx
		race.LastIdx = idx
		if race.Started and not race.Finished then
			local gi = t.Gates[race.NextGate]
			local step = Track.IndexDelta(t, prev, idx)
			if math.abs(step) < 150 and Track.IndexDelta(t, prev, gi) > 0 and Track.IndexDelta(t, gi, idx) >= 0 and math.abs(lateral) < t.Width / 2 + 70 then
				RaceClient._gate(race, race.NextGate, raceTime)
			end
			-- lap timer
			if race.LapStart then
				Hud.SetLapTime((raceTime - race.LapStart) * 1000)
			else
				Hud.SetLapTime(0)
			end
			Hud.SetSubText(string.format("%s  •  RACE %s", circuit.Name, Medals.FormatTime(math.max(raceTime, 0) * 1000)))
			-- track limits / off track far / wrong way
			local farOff = math.abs(lateral) > t.Width / 2 + 90 or vertical < -14
			race.OffTime = if farOff then race.OffTime + dt else 0
			if race.OffTime > 2.5 then
				RaceClient.Reset()
			end
			local tangent = Vector3.new(t.TX[idx], t.TY[idx], t.TZ[idx])
			local vel = chassis.AssemblyLinearVelocity
			local wrong = vel.Magnitude > 15 and vel.Unit:Dot(tangent) < -0.4
			race.WrongTime = if wrong then race.WrongTime + dt else 0
			local missed = Track.IndexDelta(t, gi, idx)
			if race.WrongTime > 1.2 then
				Hud.Warning("⚠ WRONG WAY")
			elseif race.LapStart and missed > 40 and missed < t.N / 3 then
				Hud.Warning("⚠ MISSED CHECKPOINT - GO BACK")
			elseif (car.OffTrack > 0.5 or car.OnRunoff) and car.Speed > 20 then
				Hud.Warning(if car.Gravel > 0.3 then "IN THE GRAVEL" else "TRACK LIMITS")
			else
				Hud.Warning(nil)
			end
		end
		-- no-contact windows: race start, after a reset, driving the wrong way, finished
		car.Ghost = now < info.GoTime + Config.Contact.GhostStartSeconds or now < race.GhostUntil or race.WrongTime > 0.8 or race.Finished
		-- wrecked cars get reset automatically after a moment
		if car.Wrecked and race.Started and not race.Finished then
			race.WreckedTime += dt
			if race.WreckedTime > 3 then
				RaceClient.Reset()
			end
		else
			race.WreckedTime = 0
		end
		-- struggling device? lower the graphics once, 12s into the race
		if race.Started and not race.PerfChecked and raceTime > 12 then
			race.PerfChecked = true
			Perf.CheckAutoLower()
		end
		-- slipstream
		car.Slipstream = if race.Started then race.Remote:SlipstreamFactor(chassis.CFrame) else 0
		local gear, rpm = car:Gear()
		Hud.SetSpeed(car.Speed, gear, rpm, car.Slipstream, car.AeroOpen)
		-- send our state
		sendTimer += dt
		if sendTimer >= 1 / Config.Race.SendRate then
			sendTimer = 0
			local pitch, yaw, roll = chassis.CFrame:ToEulerAnglesYXZ()
			local v = chassis.AssemblyLinearVelocity
			local b = buffer.create(Net.StateSize)
			Net.WriteState(b, 0, now - info.GoTime, p.X, p.Y, p.Z, yaw, pitch, roll, v.X, v.Y, v.Z, car:Flags())
			StateOut:FireServer(b)
		end
		-- minimap
		mapTimer += dt
		if mapTimer > 0.1 then
			mapTimer = 0
			local positions = { [info.YourRid] = { p.X, p.Z } }
			for rid, rc in race.Remote.Cars do
				if rc.CF then
					positions[rid] = { rc.CF.Position.X, rc.CF.Position.Z }
				end
			end
			Hud.UpdateMinimap(positions)
		end
	end))
	table.insert(race.Connections, RunService.RenderStepped:Connect(function(dt)
		if active == race then
			race.Remote:Update(dt)
		end
	end))

	-- intro flyover until just before the lights, then the HUD and chase camera
	race.EndIntro = function()
		if race.IntroDone or active ~= race then
			return
		end
		race.IntroDone = true
		Intro.Stop()
		Cam.Chase(car)
		Hud.SetVisible(true)
		if workspace:GetServerTimeNow() < info.LightsStart then
			Hud.Message(string.format("%s  •  %d LAPS", circuit.Name:upper(), info.Laps), Kit.Colors.Accent, 2)
		end
	end
	Kit.Loading(false)
	Intro.Reveal(world, { EndsAt = info.LightsStart - 0.6, Car = car, OnDone = race.EndIntro })
end

function RaceClient._gate(race, gate: number, raceTime: number)
	GateEvent:FireServer(gate, raceTime)
	local t = race.Track
	local pro = State.HasPass("ProRacer")
	-- sector timing
	local sector = SECTOR_END[gate]
	if sector and race.LapStart then
		local sms = (raceTime - race.SectorStart) * 1000
		local best = race.BestSectors[sector]
		local st = if best == nil or sms < best then "green" else "yellow"
		if best == nil or sms < best then
			race.BestSectors[sector] = sms
		end
		if pro then
			Hud.SetSector(sector, sms, st)
		end
	end
	if sector then
		race.SectorStart = raceTime
	end
	-- live delta vs best lap
	if race.LapStart then
		local lapT = raceTime - race.LapStart
		race.GateTimes[gate] = lapT
		if pro and race.BestGateTimes and race.BestGateTimes[gate] and gate ~= 1 then
			Hud.SetDelta((lapT - race.BestGateTimes[gate]) * 1000)
		end
	end
	if gate == 1 then
		if race.LapsDone >= 0 and race.LapStart then
			local lap = raceTime - race.LapStart
			race.LastLap = lap
			Hud.SetLast(lap * 1000)
			if not race.BestLap or lap < race.BestLap then
				race.BestLap = lap
				race.BestGateTimes = table.clone(race.GateTimes)
				race.BestGateTimes[1] = nil
				Hud.SetBest(lap * 1000)
			end
			if pro and race.BestLap then
				Hud.SetDelta((lap - race.BestLap) * 1000)
			end
		end
		race.GateTimes = {}
		race.LapsDone += 1
		race.LapStart = raceTime
		local laps = race.Info.Laps
		if race.LapsDone >= laps then
			race.Finished = true
			race.Car.Enabled = false
			Hud.SetLap(laps, laps)
			Hud.Warning(nil)
			Fx.Play("Finish", 0.6)
			Fx.Celebrate(State.Profile.car.Celebration, race.Car.Chassis.Position)
			Hud.Message("🏁 FINISHED  P" .. tostring(race.MyPos or "?"), Kit.Colors.Accent, 4)
			Hud.SetSubText("Waiting for the other racers...")
		else
			Hud.SetLap(race.LapsDone + 1, laps)
			if race.LapsDone == laps - 1 then
				Hud.Message("FINAL LAP!", Kit.Colors.Warn, 2)
			elseif race.LapsDone > 0 then
				Fx.Play("Checkpoint", 0.4, 1.2)
			end
		end
	end
	race.NextGate = (gate % Track.GateCount) + 1
end

-- Reset to the track: the crew repairs the car (costs a moment) and you're ghosted briefly
function RaceClient.Reset()
	local race = active
	if not race or not race.Started or race.Finished or race.Repairing then
		return
	end
	race.Repairing = true
	local t = race.Track
	local idx = race.LastIdx or 1
	local back = Track.Wrap(t, idx - 3)
	local car = race.Car
	local damaged = car:Health() < 0.999
	car:Teleport(spawnCF(t, t.S[back], 0))
	car:Repair()
	Hud.SetDamage(car.Damage)
	race.OffTime = 0
	race.WrongTime = 0
	race.WreckedTime = 0
	race.GhostUntil = workspace:GetServerTimeNow() + Config.Damage.ResetRepairSeconds + Config.Contact.GhostResetSeconds
	ResetEvent:FireServer()
	car:Freeze(true)
	car.Enabled = false
	Hud.Message(if damaged then "🔧 Repairing..." else "Reset to track", Kit.Colors.Accent2, Config.Damage.ResetRepairSeconds)
	task.delay(Config.Damage.ResetRepairSeconds, function()
		if active == race and car.Chassis.Parent then
			car:Freeze(false)
			car.Enabled = not race.Finished
		end
		race.Repairing = false
	end)
end

function RaceClient.Quit(handlers)
	local race = active
	if not race then
		return
	end
	active = nil
	LeaveEvent:FireServer()
	cleanup(race)
	if handlers and handlers.OnQuit then
		handlers.OnQuit(race.Finished)
	end
end

return RaceClient
