--!nonstrict
-- Draws the other racers (players and computer cars) from the server's position stream.
-- Uses dead reckoning: every packet carries a timestamp and velocity, so cars are
-- predicted to *now* (not shown in the past) and any correction is smoothed out.
-- That keeps car-to-car contact fair: the car you hit is where it really is.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local CarBuilder = require(Shared.CarBuilder)
local Cosmetics = require(Shared.Cosmetics)

local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local WheelFx = require(script.Parent.WheelFx)
local EngineAudio = require(script.Parent.EngineAudio)

local STALE_SECONDS = 1.5 -- hide a remote car after this long without a position update

local RemoteCars = {}
RemoteCars.__index = RemoteCars

local MAX_EXTRAP = 0.35 -- seconds we are willing to predict ahead
local SMOOTH = 0.12 -- error correction time constant
local SNAP = 30 -- corrections larger than this teleport instead of sliding
local F = Net.Flags
local REC = 1 + Net.StateSize

-- Name tag above a car (name, title and race position).
local function tag(model: Model, chassis: BasePart, name: string, title: string?, color: Color3)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 46)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 350
	bb.LightInfluence = 0
	bb.Adornee = chassis
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.fromScale(0.5, 0)
	frame.Size = UDim2.fromOffset(0, 26)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.BackgroundColor3 = Color3.fromRGB(15, 16, 24)
	frame.BackgroundTransparency = 0.2
	frame.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromOffset(4, 18)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.LayoutOrder = 0
	bar.Parent = frame
	local pos = Instance.new("TextLabel")
	pos.Name = "Pos"
	pos.Size = UDim2.fromOffset(28, 22)
	pos.BackgroundTransparency = 1
	pos.Font = Enum.Font.GothamBlack
	pos.TextSize = 16
	pos.TextColor3 = Color3.fromRGB(255, 200, 60)
	pos.Text = ""
	pos.LayoutOrder = 1
	pos.Parent = frame
	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.fromOffset(0, 22)
	nm.AutomaticSize = Enum.AutomaticSize.X
	nm.BackgroundTransparency = 1
	nm.Font = Enum.Font.GothamBold
	nm.TextSize = 15
	nm.TextColor3 = Color3.new(1, 1, 1)
	nm.Text = name
	nm.LayoutOrder = 2
	nm.Parent = frame
	if title then
		local tl = Instance.new("TextLabel")
		tl.AnchorPoint = Vector2.new(0.5, 0)
		tl.Position = UDim2.new(0.5, 0, 0, 27)
		tl.Size = UDim2.fromOffset(200, 16)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold
		tl.TextSize = 13
		tl.TextColor3 = Color3.fromRGB(255, 205, 80)
		tl.TextStrokeTransparency = 0.5
		tl.Text = title
		tl.Parent = bb
	end
	bb.Parent = model
	return bb, pos
end

-- goTime: server time of lights out (packets are stamped relative to it)
function RemoteCars.new(racers, yourRid: number, goTime: number)
	local self = setmetatable({ Cars = {}, YourRid = yourRid, GoTime = goTime }, RemoteCars)
	local folder = Instance.new("Folder")
	folder.Name = "GoTrackRacers"
	folder.Parent = workspace
	self.Folder = folder
	for _, r in racers do
		if r.Rid ~= yourRid then
			local parts = CarBuilder.Build(r.Car, { Remote = true, UserId = r.UserId })
			parts.Model.Name = "Racer" .. r.Rid
			Fx.RegisterRainbow(parts.Model)
			local prim = Cosmetics.ById[(r.Car or {}).Primary or ""]
			local bb, posLabel = tag(
				parts.Model,
				parts.Chassis,
				r.Name,
				r.Title,
				if prim and prim.Color then prim.Color else Color3.new(1, 1, 1)
			)
			local transparencies = {}
			for _, d in parts.Model:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "SpinBlur" and d.Name ~= "SidewallMark" then
					transparencies[d] = d.Transparency
				end
			end
			self.Cars[r.Rid] = {
				Info = r,
				IsAI = r.IsAI == true,
				Parts = parts,
				Model = parts.Model,
				Chassis = parts.Chassis,
				Tag = bb,
				PosLabel = posLabel,
				Sample = nil, -- latest { t, pos, rot, vel, yawRate }
				ErrPos = Vector3.zero,
				ErrRot = CFrame.identity,
				Spin = 0,
				Ghost = true,
				GhostShown = false,
				Flags = 0,
				ShownFlags = 0,
				FlapT = 0,
				Transparencies = transparencies,
				CF = nil,
				Vel = Vector3.zero,
				Speed = 0,
				Audio = EngineAudio.new(parts.Chassis, false),
			}
		end
	end
	return self
end

-- Track conditions (rain spray, blinking rain lights) for everyone else's cars
function RemoteCars:SetConditions(wet: boolean, night: boolean)
	self.Wet = wet
	self.Night = night
end

-- Race time on the shared clock, the same timeline the packets use.
function RemoteCars:Now(): number
	return workspace:GetServerTimeNow() - self.GoTime
end

-- Where a car is `now`, from its last packet: position + velocity x age, turning at its
-- yaw rate. Capped at MAX_EXTRAP so a lost packet doesn't send it flying.
local function predict(sample, now: number): (CFrame, number)
	local dt = math.clamp(now - sample.t, 0, MAX_EXTRAP)
	local pos = sample.pos + sample.vel * dt
	local rot = sample.rot * CFrame.Angles(0, sample.yawRate * dt, 0)
	return rot + pos, dt
end

-- Reads one position packet from the server (every other racer's state).
function RemoteCars:Push(b: buffer)
	if typeof(b) ~= "buffer" or buffer.len(b) < 2 then
		return
	end
	local count = buffer.readu16(b, 0)
	if buffer.len(b) < 2 + count * REC then
		return
	end
	local now = self:Now()
	for i = 0, count - 1 do
		local off = 2 + i * REC
		local rid = buffer.readu8(b, off)
		local car = self.Cars[rid]
		if car then
			local t, x, y, z, yaw, pitch, roll, vx, vy, vz, flags = Net.ReadState(b, off + 1)
			car.LastRecv = os.clock() -- still being relayed (even if parked on the grid)
			if not car.Model.Parent and car.Sample then
				car.Model.Parent = self.Folder
			end
			local old = car.Sample
			if old and t <= old.t then
				continue -- out of order
			end
			local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)
			local yawRate = 0
			if old and t - old.t > 1e-3 then
				local dyaw = ((yaw - old.yaw + math.pi) % (2 * math.pi)) - math.pi
				yawRate = math.clamp(dyaw / (t - old.t), -4, 4)
			end
			local sample = {
				t = t,
				pos = Vector3.new(x, y, z),
				rot = rot,
				vel = Vector3.new(vx, vy, vz),
				yaw = yaw,
				yawRate = yawRate,
			}
			local newCF = predict(sample, now)
			if car.CF then
				local err = car.CF.Position - newCF.Position
				if err.Magnitude > SNAP then
					car.ErrPos = Vector3.zero
					car.ErrRot = CFrame.identity
				else
					car.ErrPos = err
					car.ErrRot = newCF.Rotation:Inverse() * car.CF.Rotation
				end
			end
			car.Sample = sample
			car.Flags = flags
			car.Ghost = bit32.band(flags, F.Ghost) ~= 0
			if not car.Model.Parent then
				car.Model.Parent = self.Folder
			end
		end
	end
end

-- Updates the P1, P2... on the name tags.
function RemoteCars:SetPositions(posByRid)
	for rid, car in self.Cars do
		local p = posByRid[rid]
		car.PosLabel.Text = if p then ("P" .. p) else ""
	end
end

-- Hides or shows a damage group (a knocked-off wing) on another racer's car.
local function setGroupHidden(car, group: string, hidden: boolean)
	for _, part in car.Parts.Groups[group] or {} do
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end
end

-- Every frame: moves each car to its predicted position, easing out any correction,
-- and updates wheels, flap, lights and sounds.
function RemoteCars:Update(dt: number)
	local now = self:Now()
	local showTags = State.Setting("NameTags") ~= false
	local decay = math.exp(-dt / SMOOTH)
	local clock = os.clock()
	for _, car in self.Cars do
		local s = car.Sample
		-- no packets for a while (the racer left or the server stopped relaying them):
		-- remove the car instead of leaving a frozen, solid obstacle on the track
		if s and car.LastRecv and clock - car.LastRecv > STALE_SECONDS then
			if car.CF then
				car.CF = nil
				car.Model.Parent = nil
			end
			continue
		end
		if s then
			local cf = predict(s, now)
			car.ErrPos *= decay
			car.ErrRot = CFrame.identity:Lerp(car.ErrRot, decay)
			cf = (cf.Rotation * car.ErrRot) + (cf.Position + car.ErrPos)
			car.CF = cf
			car.Vel = s.vel
			car.Speed = s.vel.Magnitude
			car.Model:PivotTo(cf)
			car.Spin = WheelFx.Step(car.Spin, car.Speed, dt, car.Parts.Wheels)
			if car.Audio then
				car.Audio:Update(car.Speed, 1, 0, dt)
			end
			for _, w in car.Parts.Wheels do
				w.Weld.C0 = CFrame.new(w.Offset) * CFrame.Angles(car.Spin, 0, 0)
			end
			-- rain light (brake flag from the owner), rain spray and floor sparks
			if car.Parts.RainLight then
				CarBuilder.SetRainLight(
					car.Parts.RainLight,
					bit32.band(car.Flags or 0, F.Brake) ~= 0,
					self.Wet == true or self.Night == true
				)
			end
			local spraying = self.Wet == true and car.Speed > 50
			for _, pe in car.Parts.Spray or {} do
				pe.Enabled = spraying
			end
			if car.Parts.Plank and car.Speed > 170 and math.random() < dt * 2.5 then
				car.Parts.Plank:Emit(math.random(3, 8))
			end
			-- active-aero flap (flag from the car's player, or the server for computer cars)
			if car.Parts.Flap then
				local goal = if bit32.band(car.Flags or 0, F.Aero) ~= 0 then 1 else 0
				local cur = car.FlapT or 0
				cur += (goal - cur) * math.min(1, 10 * dt)
				if math.abs(cur - (car.FlapT or 0)) > 1e-3 then
					CarBuilder.SetFlap(car.Parts.Flap, cur)
				end
				car.FlapT = cur
			end
			car.Tag.Enabled = showTags
			-- ghosted cars (just reset / wrong way / race start) are see-through
			if car.Ghost ~= car.GhostShown then
				car.GhostShown = car.Ghost
				for part, tr in car.Transparencies do
					if part.Parent then
						part.Transparency = if car.Ghost then math.max(tr, 0.55) else tr
					end
				end
			end
			-- damage replicated from the owner
			if car.Flags ~= car.ShownFlags then
				local f = car.Flags
				car.ShownFlags = f
				setGroupHidden(car, "FrontWing", bit32.band(f, F.FrontWing) ~= 0)
				setGroupHidden(car, "RearWing", bit32.band(f, F.RearWing) ~= 0)
				if car.Parts.DamageSmoke then
					car.Parts.DamageSmoke.Enabled = bit32.band(f, F.Smoke) ~= 0
				end
			end
		end
	end
end

-- Cars that can be hit right now: { {Rid, CF, Vel, IsAI} }
function RemoteCars:Solid(): { any }
	local out = {}
	for rid, car in self.Cars do
		if car.CF and not car.Ghost then
			table.insert(out, { Rid = rid, CF = car.CF, Vel = car.Vel, IsAI = car.IsAI })
		end
	end
	return out
end

-- Returns the racer ahead within `range` studs (used for slipstream)
function RemoteCars:SlipstreamFactor(cf: CFrame): number
	local best = 0
	for _, car in self.Cars do
		if car.CF then
			local rel = cf:PointToObjectSpace(car.CF.Position)
			if rel.Z < -8 and rel.Z > -60 and math.abs(rel.X) < 7 and math.abs(rel.Y) < 8 then
				local f = 1 - (-rel.Z - 8) / 52
				best = math.max(best, f)
			end
		end
	end
	return best
end

-- The drawn car for a racer id.
function RemoteCars:Get(rid: number)
	return self.Cars[rid]
end

-- Removes every car.
function RemoteCars:Destroy()
	for _, car in self.Cars do
		if car.Audio then
			car.Audio:Destroy()
		end
		if car.Model then
			car.Model:Destroy()
		end
	end
	self.Folder:Destroy()
	self.Cars = {}
end

return RemoteCars
