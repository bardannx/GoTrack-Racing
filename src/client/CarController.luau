--!nonstrict
-- Arcade raycast-suspension race car, fully client-simulated for instant response.
--  * Car-to-car contact: other cars are solid boxes (players and AI). Each client
--    resolves its own car, so bumps feel fair even with lag.
--  * Crash damage: big impacts (walls or cars) break the front / rear wing, damage the
--    sidepods and engine, and change how the car drives. A reset repairs everything.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local CarBuilder = require(Shared.CarBuilder)
local Net = require(Shared.Net)

local Fx = require(script.Parent.Fx)
local WheelFx = require(script.Parent.WheelFx)
local EngineAudio = require(script.Parent.EngineAudio)
local State = require(script.Parent.State)

local CarController = {}
CarController.__index = CarController

local cfg = Config.Car
local contact = Config.Contact
local dmgCfg = Config.Damage
local SPRING = cfg.Gravity / (cfg.SuspensionLength - cfg.SuspensionRest)

-- surface part names -> behaviour
local SURFACE = {
	Grass = "grass",
	Pavement = "grass",
	Gravel = "gravel",
	Runoff = "runoff", -- painted asphalt run-off: full grip but counts as track limits
}

-- Shared input state (keyboard, gamepad and touch buttons all write here)
local Input = {
	Throttle = 0,
	Brake = 0,
	Steer = 0,
	Handbrake = false,
	TouchThrottle = false,
	TouchBrake = false,
	TouchLeft = false,
	TouchRight = false,
	TouchDrift = false,
	TouchSteer = 0,
	PadThrottle = 0,
	PadBrake = 0,
	PadSteer = 0,
}
CarController.Input = Input

UserInputService.InputChanged:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.Gamepad1 then
		if io.KeyCode == Enum.KeyCode.ButtonR2 then
			Input.PadThrottle = io.Position.Z
		elseif io.KeyCode == Enum.KeyCode.ButtonL2 then
			Input.PadBrake = io.Position.Z
		elseif io.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x = io.Position.X
			Input.PadSteer = if math.abs(x) > 0.12 then x else 0
		end
	end
end)

local function readInput()
	local kb = UserInputService:GetFocusedTextBox() == nil
	local W = kb and (UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up))
	local S = kb and (UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down))
	local A = kb and (UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left))
	local D = kb and (UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right))
	local space = kb and UserInputService:IsKeyDown(Enum.KeyCode.Space)
	local padDrift = UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR1)
	local padA = UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
	local padX = UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonX)

	Input.Throttle = math.max(if W or Input.TouchThrottle or padA then 1 else 0, Input.PadThrottle)
	Input.Brake = math.max(if S or Input.TouchBrake or padX then 1 else 0, Input.PadBrake)
	local steer = 0
	if A or Input.TouchLeft then
		steer -= 1
	end
	if D or Input.TouchRight then
		steer += 1
	end
	if steer == 0 then
		steer = if Input.PadSteer ~= 0 then Input.PadSteer else Input.TouchSteer
	end
	Input.Steer = math.clamp(steer, -1, 1)
	Input.Handbrake = space or Input.TouchDrift or padDrift
end

local function newDamage()
	return { FrontWing = 1, RearWing = 1, Left = 1, Right = 1, Engine = 1 }
end

function CarController.new(appearance, spawnCF: CFrame, surfaceFolder: Instance, userId: number?)
	local parts = CarBuilder.Build(appearance, { UserId = userId })
	local model = parts.Model
	local chassis = parts.Chassis
	model:PivotTo(spawnCF)
	model.Parent = workspace

	local att = Instance.new("Attachment")
	att.Name = "AntiGravityAtt"
	att.Parent = chassis
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Parent = chassis

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { surfaceFolder }
	params.IgnoreWater = true

	local self = setmetatable({
		Model = model,
		Chassis = chassis,
		Parts = parts,
		AntiGravity = vf,
		Params = params,
		Enabled = false,
		Frozen = true,
		Speed = 0,
		ForwardSpeed = 0,
		SideSpeed = 0,
		Grounded = false,
		OffTrack = 0,
		Gravel = 0,
		OnRunoff = false,
		Slipstream = 0,
		AeroOpen = false, -- active-aero flap open (straight mode)
		AeroHold = 0,
		FlapT = 0,
		AirTime = 0,
		StuckTime = 0,
		WheelState = {},
		SpinAngle = 0,
		OnStuck = nil,
		OnLand = nil,
		OnImpact = nil, -- fn(strength 0..1, kind)
		OnBumpAI = nil, -- fn(rid, impulse Vector3)
		GetOthers = nil, -- fn() -> { {Rid, CF, Vel, IsAI} }
		Ghost = false,
		Damage = newDamage(),
		Detached = {},
		Wrecked = false,
		PostVel = nil,
		ImpactCooldown = 0,
		Braking = false,
		Connections = {},
		Audio = nil,
		Debris = {},
	}, CarController)

	for i = 1, 4 do
		self.WheelState[i] = { y = parts.Wheels[i].Offset.Y, target = parts.Wheels[i].Offset.Y }
	end
	-- remember every part's place so a reset can repair the car
	self.Home = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= chassis then
			self.Home[d] = chassis.CFrame:ToObjectSpace(d.CFrame)
		end
	end

	Fx.RegisterRainbow(model)
	self.Audio = EngineAudio.new(chassis, true)
	self:Freeze(true)

	table.insert(self.Connections, RunService.PreSimulation:Connect(function(dt)
		self:PhysicsStep(dt)
	end))
	table.insert(self.Connections, RunService.RenderStepped:Connect(function(dt)
		self:VisualStep(dt)
	end))
	return self
end

-- Track conditions for the car's effects: wet = rain spray + blinking rain light,
-- night = blinking rain light (set by the race / time trial after the circuit loads)
function CarController:SetConditions(wet: boolean, night: boolean)
	self.Wet = wet
	self.Night = night
end

function CarController:Freeze(frozen: boolean)
	self.Frozen = frozen
	self.Chassis.Anchored = frozen
	self.Chassis.AssemblyLinearVelocity = Vector3.zero
	self.Chassis.AssemblyAngularVelocity = Vector3.zero
	self.PostVel = nil
end

function CarController:Teleport(cf: CFrame)
	local wasFrozen = self.Frozen
	self.Chassis.Anchored = true
	self.Model:PivotTo(cf)
	self.Chassis.AssemblyLinearVelocity = Vector3.zero
	self.Chassis.AssemblyAngularVelocity = Vector3.zero
	self.AirTime = 0
	self.StuckTime = 0
	self.PostVel = nil
	if not wasFrozen then
		task.defer(function()
			if not self.Frozen and self.Chassis.Parent then
				self.Chassis.Anchored = false
				self.Chassis.AssemblyLinearVelocity = Vector3.zero
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
function CarController:Health(): number
	local d = self.Damage
	return (d.FrontWing + d.RearWing + d.Left + d.Right + d.Engine) / 5
end

function CarController:Flags(): number
	local f = 0
	local F = Net.Flags
	if self.Detached.FrontWing then
		f += F.FrontWing
	end
	if self.Detached.RearWing then
		f += F.RearWing
	end
	if self.Damage.Engine < 0.5 then
		f += F.Smoke
	end
	if self.Ghost then
		f += F.Ghost
	end
	if self.Braking then
		f += F.Brake
	end
	if self.AeroOpen then
		f += F.Aero
	end
	return f
end

-- Knock a group of parts off: they tumble away (simple ballistic flight, no physics)
function CarController:Detach(group: string)
	if self.Detached[group] then
		return
	end
	self.Detached[group] = true
	local root = self.Chassis
	local vel = root.AssemblyLinearVelocity
	for _, part in self.Parts.Groups[group] or {} do
		if part.Parent then
			part.LocalTransparencyModifier = 1
			local debris = part:Clone()
			for _, c in debris:GetChildren() do
				c:Destroy()
			end
			debris.Anchored = true
			debris.CanCollide = false
			debris.LocalTransparencyModifier = 0
			debris.Parent = workspace
			table.insert(self.Debris, {
				Part = debris,
				Vel = vel * 0.55 + Vector3.new(math.random(-12, 12), math.random(10, 22), math.random(-12, 12)),
				Spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14,
				Life = 2.2,
			})
		end
	end
end

function CarController:Impact(strength: number, localDir: Vector3)
	if not dmgCfg.Enabled or self.ImpactCooldown > 0 then
		return
	end
	local e = math.clamp((strength - dmgCfg.MinImpact) / (dmgCfg.FullImpact - dmgCfg.MinImpact), 0, 1)
	if e <= 0 then
		return
	end
	self.ImpactCooldown = 0.15
	local d = self.Damage
	local kind
	if math.abs(localDir.Z) >= math.abs(localDir.X) then
		if localDir.Z > 0 then
			-- pushed backwards = hit something in front
			kind = "front"
			d.FrontWing = math.max(0, d.FrontWing - e * 1.3)
			d.Engine = math.max(0, d.Engine - e * 0.25)
		else
			kind = "rear"
			d.RearWing = math.max(0, d.RearWing - e * 1.3)
			d.Engine = math.max(0, d.Engine - e * 0.2)
		end
	else
		if localDir.X > 0 then
			kind = "left" -- pushed to the right = hit on the left
			d.Left = math.max(0, d.Left - e * 1.1)
		else
			kind = "right"
			d.Right = math.max(0, d.Right - e * 1.1)
		end
		d.Engine = math.max(0, d.Engine - e * 0.1)
	end
	if d.FrontWing < dmgCfg.WingBreak then
		self:Detach("FrontWing")
	end
	if d.RearWing < dmgCfg.WingBreak then
		self:Detach("RearWing")
	end
	if self.Parts.DamageSmoke then
		self.Parts.DamageSmoke.Enabled = d.Engine < 0.5
	end
	if self.Parts.Sparks then
		self.Parts.Sparks:Emit(math.floor(10 + e * 40))
	end
	Fx.Play("Crash", 0.25 + e * 0.5, 0.8 + math.random() * 0.3)
	if self:Health() < 0.22 and not self.Wrecked then
		self.Wrecked = true
	end
	if self.OnImpact then
		self.OnImpact(e, kind)
	end
end

function CarController:Repair()
	self.Damage = newDamage()
	self.Detached = {}
	self.Wrecked = false
	local root = self.Chassis
	for part, rel in self.Home do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	if self.Parts.DamageSmoke then
		self.Parts.DamageSmoke.Enabled = false
	end
	local _ = root
end

-- handling modifiers from damage
function CarController:Mods(): (number, number, number, number)
	local d = self.Damage
	local grip = 1 - (1 - d.FrontWing) * 0.16 - (1 - d.RearWing) * 0.22 - (2 - d.Left - d.Right) * 0.06
	local steer = 1 - (1 - d.FrontWing) * 0.28
	local top = 0.84 + 0.16 * d.Engine
	local bias = (d.Right - d.Left) * 0.07
	return grip, steer, top, bias
end

---------------------------------------------------------------------------
-- Car-to-car contact (2D oriented boxes in the ground plane)
---------------------------------------------------------------------------
local HW, HL = contact.HalfWidth, contact.HalfLength

local function project(axis: Vector3, fwd: Vector3, right: Vector3): number
	return HL * math.abs(fwd:Dot(axis)) + HW * math.abs(right:Dot(axis))
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-4 then f.Unit else Vector3.zAxis
end

function CarController:Contacts(dt: number)
	if not contact.Enabled or self.Ghost or not self.GetOthers then
		return false
	end
	local changed = false
	local root = self.Chassis
	local cf = root.CFrame
	local myPos = cf.Position
	local myF = flat(cf.LookVector)
	local myR = Vector3.new(-myF.Z, 0, myF.X)
	for _, o in self.GetOthers() do
		local op = o.CF.Position
		local d = Vector3.new(myPos.X - op.X, 0, myPos.Z - op.Z)
		if d.Magnitude < 16 and math.abs(myPos.Y - op.Y) < 5 then
			local oF = flat(o.CF.LookVector)
			local oR = Vector3.new(-oF.Z, 0, oF.X)
			local best, bestAxis = math.huge, nil
			for _, axis in { myF, myR, oF, oR } do
				local overlap = project(axis, myF, myR) + project(axis, oF, oR) - math.abs(d:Dot(axis))
				if overlap <= 0 then
					best = -1
					break
				end
				if overlap < best then
					best, bestAxis = overlap, axis
				end
			end
			if best > 0 and bestAxis then
				local n = if d:Dot(bestAxis) >= 0 then bestAxis else -bestAxis
				-- push apart (each client moves its own car, so take ~60%)
				local push = math.min(best * 0.6 + 0.02, 2)
				root.CFrame = root.CFrame + n * push
				changed = true
				-- velocity exchange (equal masses, each side applies half)
				local vel = root.AssemblyLinearVelocity
				local ov = o.Vel or Vector3.zero
				local rel = Vector3.new(vel.X - ov.X, 0, vel.Z - ov.Z)
				local vn = rel:Dot(n)
				if vn < 0 then
					local j = -(1 + contact.Restitution) * vn * 0.5
					local tangent = rel - n * vn
					local newVel = vel + n * j - tangent * contact.Friction * 0.5
					root.AssemblyLinearVelocity = Vector3.new(newVel.X, vel.Y, newVel.Z)
					-- a little spin from off-centre hits
					local contactPoint = (myPos + op) / 2
					local r = contactPoint - myPos
					local yaw = (r:Cross(n * j)).Y * 0.01
					local ang = root.AssemblyAngularVelocity
					root.AssemblyAngularVelocity = ang + Vector3.new(0, math.clamp(yaw, -1.2, 1.2), 0)
					local localDir = cf:VectorToObjectSpace(n)
					self:Impact(-vn * 1.1, localDir)
					if o.IsAI and self.OnBumpAI and -vn > 6 then
						self.OnBumpAI(o.Rid, -n * j)
					end
				end
			end
		end
	end
	return changed
end

---------------------------------------------------------------------------
-- Physics
---------------------------------------------------------------------------
function CarController:PhysicsStep(dt: number)
	local root = self.Chassis
	if self.Frozen or root.Anchored or not root.Parent then
		self.Speed = 0
		self.ForwardSpeed = 0
		return
	end
	dt = math.min(dt, 1 / 20)
	self.ImpactCooldown = math.max(0, self.ImpactCooldown - dt)
	if self.Enabled and not self.Wrecked then
		readInput()
	else
		Input.Throttle, Input.Brake, Input.Steer, Input.Handbrake = 0, if self.Wrecked then 0.6 else 0.35, 0, false
	end

	local mass = root.AssemblyMass
	self.AntiGravity.Force = Vector3.new(0, mass * workspace.Gravity, 0)

	local cf = root.CFrame
	local up = cf.UpVector
	local look = cf.LookVector
	local right = cf.RightVector
	local vel = root.AssemblyLinearVelocity
	-- track the velocity change we cause ourselves, so walls can be detected
	local expect = vel
	local function imp(i: Vector3)
		root:ApplyImpulse(i)
		expect += i / mass
	end

	-- wall impacts: a sudden velocity change we didn't cause ourselves
	if self.PostVel then
		local dv = vel - self.PostVel
		local dvH = dv - up * dv:Dot(up)
		local mag = dvH.Magnitude
		if mag > dmgCfg.MinImpact then
			self:Impact(mag, cf:VectorToObjectSpace(dvH.Unit))
			if self.OnImpactShake then
				self.OnImpactShake(mag)
			end
		end
	end

	-- suspension
	local hits, offHits, gravelHits = 0, 0, 0
	local runoff = false
	local normalSum = Vector3.zero
	for i, w in self.Parts.Wheels do
		local off = w.Offset
		local origin = cf:PointToWorldSpace(Vector3.new(off.X, 0, off.Z))
		local result = workspace:Raycast(origin, -up * cfg.SuspensionLength, self.Params)
		local st = self.WheelState[i]
		if result then
			hits += 1
			normalSum += result.Normal
			local kind = SURFACE[result.Instance.Name]
			if kind == "grass" then
				offHits += 1
			elseif kind == "gravel" then
				offHits += 1
				gravelHits += 1
			elseif kind == "runoff" then
				runoff = true
			end
			local compression = cfg.SuspensionLength - result.Distance
			local relVel = root:GetVelocityAtPosition(origin):Dot(up)
			local accel = math.clamp(SPRING * compression - cfg.SuspensionDamping * relVel, 0, 1800)
			local si = up * accel * (mass / 4) * dt
			root:ApplyImpulseAtPosition(si, origin)
			expect += si / mass
			st.target = -(result.Distance - w.Radius)
		else
			st.target = -(cfg.SuspensionLength - w.Radius)
		end
	end

	local wasGrounded = self.Grounded
	local grounded = hits >= 2
	self.Grounded = grounded
	local normal = if hits > 0 then normalSum.Unit else Vector3.yAxis
	local groundFactor = hits / 4
	local offFrac = if hits > 0 then offHits / hits else 0
	local gravelFrac = if hits > 0 then gravelHits / hits else 0
	self.OffTrack = offFrac
	self.Gravel = gravelFrac
	self.OnRunoff = runoff
	local speed = vel.Magnitude
	self.Speed = speed

	if grounded and not wasGrounded and self.AirTime > 0.4 then
		Fx.Play("Land", 0.35, 1)
		-- the floor scrapes on landing: a shower of sparks from under the car
		if self.Parts.Plank and speed > 60 then
			self.Parts.Plank:Emit(math.floor(12 + math.min(self.AirTime, 1.5) * 20))
		end
		if self.OnLand then
			self.OnLand(self.AirTime)
		end
	end
	self.AirTime = if grounded then 0 else self.AirTime + dt

	-- gravity + downforce
	local gDir = if grounded and speed > 35 then -normal else Vector3.new(0, -1, 0)
	imp(gDir * cfg.Gravity * mass * dt)
	if grounded then
		imp(-normal * math.min(speed * cfg.Downforce, 110) * mass * dt)
	end

	local fwd = look - normal * look:Dot(normal)
	fwd = if fwd.Magnitude > 1e-3 then fwd.Unit else look
	local side = right - normal * right:Dot(normal)
	side = if side.Magnitude > 1e-3 then side.Unit else right
	local vF = vel:Dot(fwd)
	local vS = vel:Dot(side)
	self.ForwardSpeed = vF
	self.SideSpeed = vS

	-- active aero ("straight mode", like the 2026 cars): flat out and pointing straight, the
	-- rear flap opens for less drag; braking, turning or leaving the track closes it at once
	local aero = cfg.ActiveAero
	if aero and aero.Enabled then
		local want = grounded
			and self.Enabled
			and not self.Wrecked
			and Input.Throttle > 0.85
			and Input.Brake < 0.05
			and not Input.Handbrake
			and math.abs(Input.Steer) < 0.25
			and vF > cfg.TopSpeed * aero.MinSpeed
			and offFrac == 0
			and not self.Detached.RearWing
		self.AeroHold = if want then (self.AeroHold or 0) + dt else 0
		local open = self.AeroHold > aero.Delay
		if open ~= (self.AeroOpen == true) then
			self.AeroOpen = open
			if open then
				Fx.Play("Boost", 0.18, 1.35)
			end
		end
	end

	local gripMul, steerMul, topMul, steerBias = self:Mods()
	local top = cfg.TopSpeed * topMul * (1 + cfg.SlipstreamBonus * self.Slipstream + (if self.AeroOpen then aero.TopSpeedBonus else 0))
	top = top + (cfg.OffTrackTopSpeed - top) * (offFrac - gravelFrac)
	top = top + (cfg.GravelTopSpeed - top) * gravelFrac

	if grounded then
		local accel = 0
		local throttle, brake = Input.Throttle, Input.Brake
		self.Braking = brake > 0.1 and vF > 5
		if throttle > 0 and vF < -2 then
			accel = cfg.BrakeDecel * throttle
		elseif throttle > 0 then
			if vF < top then
				local ratio = math.max(vF, 0) / top
				accel = cfg.EngineAccel * throttle * (1 - ratio * ratio * 0.8) * (1 + 0.15 * self.Slipstream) * (0.85 + 0.15 * self.Damage.Engine)
			end
		elseif brake > 0 then
			if vF > 2 then
				accel = -cfg.BrakeDecel * brake
			elseif vF > -cfg.ReverseTopSpeed then
				accel = -cfg.ReverseAccel * brake
			end
		end
		local sgn = if vF >= 0 then 1 else -1
		local resist = -sgn * (cfg.RollingResistance + cfg.AirDrag * vF * vF)
		if vF > top + 2 then
			resist -= (vF - top) * (1.2 + offFrac * 2 + gravelFrac * 3)
		end
		if throttle == 0 and brake == 0 and math.abs(vF) < 3 then
			resist = -vF * 4
		end
		accel += resist
		imp(fwd * accel * mass * dt * groundFactor)

		local grip = if Input.Handbrake then cfg.DriftGrip else cfg.Grip
		grip *= 1 + (cfg.OffTrackGrip - 1) * (offFrac - gravelFrac) + (cfg.GravelGrip - 1) * gravelFrac
		grip *= gripMul
		local dv = -vS * math.min(1, grip * dt)
		imp(side * dv * mass * groundFactor)
		if Input.Handbrake and math.abs(vF) > 5 then
			imp(-fwd * sgn * 14 * mass * dt)
		end

		local angVel = root.AssemblyAngularVelocity
		local sp = math.abs(vF)
		local rate = cfg.SteerRate * math.clamp(sp / 16, 0, 1) * (1 - cfg.HighSpeedSteerFactor * math.clamp(sp / cfg.TopSpeed, 0, 1)) * steerMul
		if Input.Handbrake then
			rate *= 1.35
		end
		local dir = if vF >= -1 then 1 else -1
		local steerIn = math.clamp(Input.Steer + (if sp > 20 then steerBias else 0), -1, 1)
		local desired = -steerIn * rate * dir
		local cur = angVel:Dot(up)
		local newYaw = cur + (desired - cur) * math.min(1, 12 * dt)
		angVel += up * (newYaw - cur)
		local roll = angVel:Dot(look)
		angVel -= look * roll * math.min(1, 5 * dt)
		root.AssemblyAngularVelocity = angVel
	else
		self.Braking = false
		local angVel = root.AssemblyAngularVelocity
		angVel *= (1 - math.min(1, 4 * dt))
		local axis = up:Cross(Vector3.yAxis)
		angVel += axis * 18 * dt
		local cur = angVel:Dot(Vector3.yAxis)
		angVel += Vector3.yAxis * ((-Input.Steer * 1.4) - cur) * math.min(1, 2.5 * dt)
		root.AssemblyAngularVelocity = angVel
		imp(-vel * 0.04 * mass * dt)
	end

	-- other cars
	if self:Contacts(dt) then
		expect = root.AssemblyLinearVelocity
	end

	-- stuck / flipped
	if (not grounded and speed < 12) or (up.Y < 0.1 and speed < 10) then
		self.StuckTime += dt
	else
		self.StuckTime = 0
	end
	if self.StuckTime > 2.2 then
		self.StuckTime = 0
		if self.OnStuck then
			self.OnStuck()
		end
	end
	self.PostVel = expect
end

function CarController:VisualStep(dt: number)
	local parts = self.Parts
	if not self.Chassis.Parent then
		return
	end
	local vF = self.ForwardSpeed
	self.SpinAngle = WheelFx.Step(self.SpinAngle, vF, dt, parts.Wheels)
	local steerAngle = -Input.Steer * 0.4 * (if self.Enabled then 1 else 0)
	for i, w in parts.Wheels do
		local st = self.WheelState[i]
		st.y += (st.target - st.y) * math.min(1, 18 * dt)
		local off = w.Offset
		local c0 = CFrame.new(off.X, st.y, off.Z)
		if i <= 2 then
			c0 *= CFrame.Angles(0, steerAngle, 0)
		end
		-- a damaged side makes that wheel wobble
		local dmg = if off.X < 0 then self.Damage.Left else self.Damage.Right
		if dmg < 0.6 then
			c0 *= CFrame.Angles(0, 0, math.sin(self.SpinAngle * 2) * (0.6 - dmg) * 0.25)
		end
		w.Weld.C0 = c0 * CFrame.Angles(self.SpinAngle, 0, 0)
	end
	-- steering wheel + dashboard screen
	local sw = parts.Steering
	if sw then
		self.WheelTurn = (self.WheelTurn or 0) + ((steerAngle * 3.2) - (self.WheelTurn or 0)) * math.min(1, 14 * dt)
		sw.Weld.C0 = sw.Base * CFrame.Angles(0, 0, self.WheelTurn)
		self.ScreenTimer = (self.ScreenTimer or 0) - dt
		if sw.Gear and self.ScreenTimer <= 0 then
			self.ScreenTimer = 0.08
			local gear, rpm = self:Gear()
			sw.Gear.Text = if gear == 0 then "R" elseif math.abs(vF) < 1 then "N" else tostring(gear)
			sw.Speed.Text = State.SpeedText(vF)
			if sw.Rev then
				sw.Rev.Size = UDim2.fromScale(math.clamp(rpm, 0.02, 1), 1)
				sw.Rev.BackgroundColor3 = if rpm > 0.9 then Color3.fromRGB(80, 140, 255) elseif rpm > 0.7 then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(60, 255, 120)
			end
		end
	end
	local fast = math.abs(vF) > cfg.TopSpeed * 0.75
	for _, pe in parts.Flames do
		pe.Enabled = fast and self.Enabled
	end
	local sliding = self.Grounded and (math.abs(self.SideSpeed) > 22 or (Input.Handbrake and math.abs(vF) > 20) or (Input.Brake > 0 and vF > 120))
	for _, pe in parts.Smoke do
		pe.Enabled = sliding and self.Enabled
	end
	if parts.Trail then
		parts.Trail.Enabled = math.abs(vF) > 40
	end
	-- rear rain light: bright under braking, blinking in the wet and at night
	if parts.RainLight then
		CarBuilder.SetRainLight(parts.RainLight, self.Enabled and Input.Brake > 0.1 and vF > 5, self.Wet == true or self.Night == true)
	end
	-- active-aero flap: swings open fast, snaps shut even faster
	if parts.Flap then
		local goal = if self.AeroOpen then 1 else 0
		local cur = self.FlapT or 0
		cur += (goal - cur) * math.min(1, (if goal > cur then 9 else 16) * dt)
		if math.abs(cur - (self.FlapT or 0)) > 1e-3 then
			CarBuilder.SetFlap(parts.Flap, cur)
		end
		self.FlapT = cur
	end
	-- spray off the rear tyres in the rain
	local spraying = self.Wet == true and self.Grounded and math.abs(vF) > 50
	for _, pe in parts.Spray or {} do
		pe.Enabled = spraying
		if spraying then
			pe.Rate = 18 + math.abs(vF) * 0.3
		end
	end
	-- the floor's skid blocks spark at top speed (like F1 titanium skids)
	if parts.Plank and self.Grounded and self.Enabled and vF > cfg.TopSpeed * 0.72 then
		self.PlankTimer = (self.PlankTimer or 0) - dt
		if self.PlankTimer <= 0 then
			self.PlankTimer = 0.12 + math.random() * 0.7
			parts.Plank:Emit(math.random(3, 9))
		end
	end
	if self.Audio then
		if self.Enabled or self.Frozen then
			local slide = 0
			if sliding then
				slide = math.clamp((math.abs(self.SideSpeed) - 14) / 30, 0.35, 1)
			end
			self.Audio:Update(vF, if self.Enabled then Input.Throttle else 0.25, slide, dt)
		else
			self.Audio:Mute()
		end
	end
	-- flying debris
	for i = #self.Debris, 1, -1 do
		local d = self.Debris[i]
		d.Life -= dt
		if d.Life <= 0 or not d.Part.Parent then
			d.Part:Destroy()
			table.remove(self.Debris, i)
		else
			d.Vel += Vector3.new(0, -140 * dt, 0)
			local p = d.Part.CFrame.Position + d.Vel * dt
			d.Part.CFrame = CFrame.new(p) * d.Part.CFrame.Rotation * CFrame.Angles(d.Spin.X * dt, d.Spin.Y * dt, d.Spin.Z * dt)
			if d.Life < 0.5 then
				d.Part.Transparency = 1 - d.Life * 2
			end
		end
	end
end

-- Gear (1-8) and rpm fraction for the dashboard
function CarController:Gear(): (number, number)
	local v = math.abs(self.ForwardSpeed)
	local top = cfg.TopSpeed
	local gear = math.clamp(math.floor(v / top * 8) + 1, 1, 8)
	local low = (gear - 1) / 8 * top
	local rpm = math.clamp((v - low) / (top / 8), 0, 1)
	if self.ForwardSpeed < -1 then
		return 0, 0.3
	end
	return gear, rpm
end

function CarController:Destroy()
	for _, c in self.Connections do
		c:Disconnect()
	end
	self.Connections = {}
	for _, d in self.Debris do
		d.Part:Destroy()
	end
	self.Debris = {}
	if self.Audio then
		self.Audio:Destroy()
		self.Audio = nil
	end
	if self.Model then
		self.Model:Destroy()
	end
	Input.TouchThrottle, Input.TouchBrake, Input.TouchLeft, Input.TouchRight, Input.TouchDrift = false, false, false, false, false
end

return CarController
