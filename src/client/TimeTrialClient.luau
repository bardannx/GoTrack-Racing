--!nonstrict
-- Time Trial: solo hot laps with ghosts, medals and a verified lap leaderboard.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Track = require(Shared.Track)
local Circuits = require(Shared.Circuits)
local Medals = require(Shared.Medals)

local State = require(script.Parent.State)
local Util = require(script.Parent.Util)
local Fx = require(script.Parent.Fx)
local CircuitBuilder = require(script.Parent.CircuitBuilder)
local Intro = require(script.Parent.UI.CircuitIntro)
local CarController = require(script.Parent.CarController)
local GhostPlayer = require(script.Parent.GhostPlayer)
local Cam = require(script.Parent.CameraController)
local Kit = require(script.Parent.UI.Kit)
local Hud = require(script.Parent.UI.Hud)
local RacingLine = require(script.Parent.RacingLine)

local TT = {}
local player = Players.LocalPlayer
local RATE = Config.GhostSampleRate
local active = nil

local function round2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

local function spawnCF(t, s: number, lateral: number): CFrame
	local x, y, z, tx, ty, tz = Track.PointAt(t, s, lateral)
	local p = Vector3.new(x, y + 0.6 + 2.1, z)
	return CFrame.lookAt(p, p + Vector3.new(tx, ty, tz))
end

function TT.IsActive(): boolean
	return active ~= nil
end

local function cleanup(tt)
	for _, c in tt.Connections do
		c:Disconnect()
	end
	if tt.Car then
		tt.Car:Destroy()
	end
	for _, g in tt.Ghosts do
		g:Destroy()
	end
	RacingLine.Stop()
	Intro.Stop()
	CircuitBuilder.Clear()
	Hud.Hide()
	Cam.Stop()
	Cam.SetTrack(nil)
end

-- alpha < 1: record a frame part-way between the previous recorded pose and now. After a
-- frame hitch several samples are due at once; spreading them along the path keeps every
-- step under the server's speed check instead of one huge jump ("lap could not be verified").
local function record(tt, alpha: number?)
	local cf = tt.Car.Chassis.CFrame
	if alpha and alpha < 1 and tt.LastCF then
		cf = (tt.LastCF :: CFrame):Lerp(cf, alpha)
	end
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	local p = cf.Position
	local f = tt.Frames
	f[#f + 1] = round2(p.X)
	f[#f + 1] = round2(p.Y)
	f[#f + 1] = round2(p.Z)
	f[#f + 1] = round2(rx)
	f[#f + 1] = round2(ry)
	f[#f + 1] = round2(rz)
end

-- opts: { trackId, ghostIds = {userIds}, onExit = fn }
function TT.Start(opts)
	if active then
		return
	end
	local t = Track.Get(opts.trackId)
	local circuit = Circuits.ById[opts.trackId]
	local tt = {
		Track = t,
		Connections = {},
		Ghosts = {},
		Frames = {},
		LapStart = nil,
		NextGate = 1,
		Valid = true,
		LastIdx = nil,
		Token = nil,
		Best = State.Profile.bests[opts.trackId],
		SessionBest = nil,
		GateTimes = {},
		BestGateTimes = nil,
		Started = false,
		Medals = Medals.FromIdeal(t.IdealLap),
		OffTime = 0,
	}
	active = tt
	tt.IntroPlaying = true
	Intro.Begin(opts.trackId, { Mode = "tt", Laps = 1 })
	local okBuild, world = pcall(CircuitBuilder.Build, opts.trackId, State.Setting("Quality"), Intro.Progress)
	if not okBuild then
		warn("[GoTrack] Circuit failed to build:", world)
		Kit.Toast("Couldn't load that circuit - sorry! Try another one.", "error")
		TT.Exit()
		if opts.onExit then
			opts.onExit()
		end
		return
	end
	local gs, lat = Track.GridSlot(t, 1)
	tt.StartCF = spawnCF(t, gs - 60, 0)
	local car = CarController.new(State.Profile.car, tt.StartCF, world.Surface, player.UserId)
	tt.Car = car
	car:SetConditions(world.Theme and world.Theme.Weather == "rain", world.Theme and world.Theme.Night == true)
	car.OnStuck = function()
		TT.ResetToTrack()
	end
	car.OnImpact = function(e)
		Cam.Shake(0.4 + e * 1.4)
		Hud.SetDamage(car.Damage)
		if car.Wrecked then
			Hud.Message("💥 CAR WRECKED - press Backspace to repair", Kit.Colors.Danger, 2.5)
		end
	end

	-- ghosts
	if State.Setting("ShowGhosts") then
		if State.Setting("ShowPBGhost") then
			local g = Util.Invoke("GetGhost", opts.trackId, player.UserId)
			if typeof(g) == "table" and g.f then
				tt.PBGhost = g
				tt.PBGhostPlayer = GhostPlayer.new(g, "Your PB", Color3.fromRGB(120, 255, 170))
				table.insert(tt.Ghosts, tt.PBGhostPlayer)
			end
		end
		for _, uid in opts.ghostIds or {} do
			if uid ~= player.UserId then
				local g = Util.Invoke("GetGhost", opts.trackId, uid)
				if typeof(g) == "table" and g.f then
					table.insert(tt.Ghosts, GhostPlayer.new(g, g.name or "Ghost", Color3.fromRGB(170, 190, 255)))
				end
			end
		end
	end
	if active ~= tt then
		return
	end
	local res = Util.Invoke("TTStart", opts.trackId)
	tt.Token = res and res.token

	Hud.Show({
		mode = "tt",
		trackName = circuit.Flag .. "  " .. circuit.Name,
		laps = 1,
		racers = { { Rid = 1, Name = player.DisplayName, Car = State.Profile.car } },
		yourRid = 1,
		minimap = t.Minimap,
		exitText = "🏠  Exit Time Trial",
	})
	Hud.SetVisible(false)
	Hud.SetBest(tt.Best)
	Hud.SetLapTime(0)
	Hud.SetCallbacks({
		Reset = function()
			TT.ResetToTrack()
		end,
		Restart = function()
			TT.Restart()
		end,
		Exit = function()
			TT.Exit()
			if opts.onExit then
				opts.onExit()
			end
		end,
	})
	Cam.Chase(car)
	Cam.SetTrack(t)
	RacingLine.Start(t, car)
	Hud.SetDamage(car.Damage)

	table.insert(tt.Connections, UserInputService.InputBegan:Connect(function(io, processed)
		if processed or active ~= tt then
			return
		end
		local k = io.KeyCode
		if k == Enum.KeyCode.R or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonY then
			TT.Restart()
		elseif k == Enum.KeyCode.Backspace or k == Enum.KeyCode.ButtonL1 then
			TT.ResetToTrack()
		elseif k == Enum.KeyCode.P or k == Enum.KeyCode.Tab or k == Enum.KeyCode.ButtonStart then
			Hud.TogglePause()
		elseif k == Enum.KeyCode.C or k == Enum.KeyCode.ButtonSelect then
			Hud.CameraToast(State.CycleCamera())
		end
	end))

	local nextSample = 0
	local mapTimer = 0
	table.insert(tt.Connections, RunService.Heartbeat:Connect(function(dt)
		if active ~= tt or not tt.Started then
			return
		end
		local chassis = car.Chassis
		local p = chassis.Position
		local idx, lateral, vertical = Track.Project(t, p.X, p.Y, p.Z, tt.LastIdx)
		local prev = tt.LastIdx or idx
		tt.LastIdx = idx
		local now = os.clock()
		-- gates
		local gi = t.Gates[tt.NextGate]
		local step = Track.IndexDelta(t, prev, idx)
		if math.abs(step) < 150 and Track.IndexDelta(t, prev, gi) > 0 and Track.IndexDelta(t, gi, idx) >= 0 then
			if math.abs(lateral) < t.Width / 2 + 70 then
				TT._gate(tt, tt.NextGate, now)
			end
		else
			-- skipped a gate (cut the track)?
			local nextIdx = t.Gates[tt.NextGate]
			local following = t.Gates[(tt.NextGate % Track.GateCount) + 1]
			if tt.LapStart and Track.IndexDelta(t, following, idx) > 0 and Track.IndexDelta(t, nextIdx, idx) > 0 and Track.IndexDelta(t, nextIdx, idx) < t.N / 3 then
				if tt.Valid then
					tt.Valid = false
					Hud.Message("LAP INVALID - track limits", Kit.Colors.Danger, 2)
				end
				tt.NextGate = (tt.NextGate % Track.GateCount) + 1
			end
		end
		if tt.LapStart then
			local lapT = now - tt.LapStart
			Hud.SetLapTime(lapT * 1000)
			if lapT >= nextSample then
				local due = math.floor((lapT - nextSample) * RATE) + 1
				for k = 1, due do
					record(tt, k / due)
					nextSample += 1 / RATE
				end
				tt.LastCF = car.Chassis.CFrame
			end
			for _, g in tt.Ghosts do
				g:Update(lapT)
			end
		end
		local farOff = math.abs(lateral) > t.Width / 2 + 90 or vertical < -14
		tt.OffTime = if farOff then tt.OffTime + dt else 0
		if tt.OffTime > 2.5 then
			TT.ResetToTrack()
		end
		if (car.OffTrack > 0.5 or car.OnRunoff) and car.Speed > 20 then
			Hud.Warning(if car.Gravel > 0.3 then "IN THE GRAVEL" else "TRACK LIMITS")
		else
			Hud.Warning(nil)
		end
		if car.Wrecked then
			tt.WreckT = (tt.WreckT or 0) + dt
			if tt.WreckT > 3 then
				tt.WreckT = 0
				TT.ResetToTrack()
			end
		else
			tt.WreckT = 0
		end
		local gear, rpm = car:Gear()
		Hud.SetSpeed(car.Speed, gear, rpm, 0, car.AeroOpen)
		mapTimer += dt
		if mapTimer > 0.1 then
			mapTimer = 0
			Hud.UpdateMinimap({ [1] = { p.X, p.Z } })
		end
	end))

	tt.ResetSampling = function()
		nextSample = 0
	end
	-- a short skippable flyover, then the 3-2-1
	Kit.Loading(false)
	Intro.Reveal(world, {
		Duration = 5.5,
		Car = car,
		OnDone = function()
			if active ~= tt or not tt.IntroPlaying then
				return
			end
			tt.IntroPlaying = false
			Cam.Chase(car)
			Hud.SetVisible(true)
			TT.Restart()
		end,
	})
end

function TT._gate(tt, gate: number, now: number)
	local pro = State.HasPass("ProRacer")
	if tt.LapStart then
		local lapT = now - tt.LapStart
		tt.GateTimes[gate] = lapT
		local ref = tt.BestGateTimes
		if pro and ref and ref[gate] and gate ~= 1 then
			Hud.SetDelta((lapT - ref[gate]) * 1000)
		end
	end
	if gate == 1 then
		if tt.LapStart then
			local lapMs = math.floor((now - tt.LapStart) * 1000 + 0.5)
			record(tt)
			local frames = tt.Frames
			Hud.SetLast(lapMs)
			if tt.Valid then
				local prevBest = tt.SessionBest
				if not tt.SessionBest or lapMs < tt.SessionBest then
					tt.SessionBest = lapMs
					tt.BestGateTimes = table.clone(tt.GateTimes)
				end
				if pro and prevBest then
					Hud.SetDelta(lapMs - prevBest)
				end
				local token = tt.Token
				local trackId = tt.Track.Id
				task.spawn(function()
					local res = Util.Invoke("TTSubmitLap", token, lapMs, frames, RATE)
					if active ~= tt then
						return
					end
					if res and res.ok then
						if res.pb then
							tt.Best = lapMs
							Hud.SetBest(lapMs)
							Fx.Play("Finish", 0.4)
							Hud.Message("🏆 NEW PERSONAL BEST  " .. Medals.FormatTime(lapMs), Kit.Colors.Success, 3)
							-- replace the PB ghost with this lap
							local g = { ms = lapMs, rate = RATE, f = frames, car = State.Profile.car, name = "Your PB" }
							tt.PBGhost = g
							if State.Setting("ShowGhosts") and State.Setting("ShowPBGhost") then
								local old = tt.PBGhostPlayer
								if old then
									local i = table.find(tt.Ghosts, old)
									if i then
										table.remove(tt.Ghosts, i)
									end
									old:Destroy()
								end
								tt.PBGhostPlayer = GhostPlayer.new(g, "Your PB", Color3.fromRGB(120, 255, 170))
								table.insert(tt.Ghosts, tt.PBGhostPlayer)
							end
						else
							Hud.Message(Medals.FormatTime(lapMs), Kit.Colors.Text, 2)
						end
						if res.newMedal and res.medal > 0 then
							Kit.Toast(string.format("%s %s medal on %s! +%d coins", Util.MedalIcon(res.medal), Config.Medals.Names[res.medal], Circuits.ById[trackId].Name, res.coins or 0), "success")
						end
					elseif res and res.err then
						Hud.Message(res.err, Kit.Colors.Danger, 2)
					end
				end)
			end
		end
		-- start a new flying lap
		tt.LapStart = now
		tt.Valid = true
		tt.Frames = {}
		tt.GateTimes = {}
		tt.ResetSampling()
		for _, g in tt.Ghosts do
			g:Update(0)
		end
	end
	tt.NextGate = (gate % Track.GateCount) + 1
end

function TT.Restart()
	local tt = active
	if not tt or tt.IntroPlaying then
		return
	end
	tt.Started = false
	tt.LapStart = nil
	tt.NextGate = 1
	tt.Valid = true
	tt.Frames = {}
	tt.LastIdx = nil
	Hud.SetLapTime(0)
	Hud.SetDelta(nil)
	tt.Car.Enabled = false
	tt.Car:Freeze(true)
	tt.Car:Teleport(tt.StartCF)
	tt.Car:Repair()
	Hud.SetDamage(tt.Car.Damage)
	local token = {}
	tt.CountToken = token
	task.spawn(function()
		for num = 3, 1, -1 do
			if active ~= tt or tt.CountToken ~= token then
				return
			end
			Hud.SetLights(({ [3] = 2, [2] = 4, [1] = 5 })[num])
			Hud.Message(tostring(num), Color3.fromRGB(255, 60, 60), 0.6)
			Fx.Play("Countdown", 0.45, 0.9)
			task.wait(0.6)
		end
		if active ~= tt or tt.CountToken ~= token then
			return
		end
		Hud.SetLights("go")
		task.delay(1, function()
			if active == tt and tt.CountToken == token then
				Hud.SetLights(-1)
			end
		end)
		Fx.Play("Go", 0.6, 1.4)
		tt.Car:Freeze(false)
		tt.Car.Enabled = true
		tt.Started = true
		Hud.Message("GO!  Flying lap starts at the line", Kit.Colors.Success, 1.5)
	end)
end

function TT.ResetToTrack()
	local tt = active
	if not tt or not tt.Started then
		return
	end
	local t = tt.Track
	local idx = Track.Wrap(t, (tt.LastIdx or 1) - 3)
	tt.Car:Teleport(spawnCF(t, t.S[idx], 0))
	tt.Car:Repair()
	Hud.SetDamage(tt.Car.Damage)
	if tt.LapStart and tt.Valid then
		tt.Valid = false
		Hud.Message("LAP INVALID - reset", Kit.Colors.Danger, 1.5)
	end
end

function TT.Exit()
	local tt = active
	if not tt then
		return
	end
	active = nil
	cleanup(tt)
end

return TT
