--!nonstrict
-- Car audio: engine (rpm + gear shifts + throttle), tyre squeal, wind at speed.
-- Your own car is heard "in the cockpit" (loud, no distance fall-off). Other cars are
-- 3D sounds on their chassis, so you hear rivals come past and fade away.
-- Sound ids live in Config.Sounds (EngineLoop, EngineHigh, TyreSqueal, Wind). Any id
-- left empty is simply skipped, so the game never errors on missing audio.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Fx = require(script.Parent.Fx)

local EngineAudio = {}
EngineAudio.__index = EngineAudio

local GEARS = 8

local function loop(parent: Instance, name: string, id: string?, isLocal: boolean): Sound?
	if not id or id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	if isLocal then
		-- no distance fall-off for the player's own car
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10000
		s.RollOffMaxDistance = 10001
	else
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 18
		s.RollOffMaxDistance = 260
	end
	s.Parent = parent
	s:Play()
	return s
end

-- Gear and rpm (0..1) from speed, matching the dashboard in CarController.
function EngineAudio.GearFor(speed: number): (number, number)
	local top = Config.Car.TopSpeed
	local v = math.abs(speed)
	local gear = math.clamp(math.floor(v / top * GEARS) + 1, 1, GEARS)
	local low = (gear - 1) / GEARS * top
	local rpm = math.clamp((v - low) / (top / GEARS), 0, 1)
	return gear, rpm
end

function EngineAudio.new(parent: BasePart, isLocal: boolean)
	local S = Config.Sounds
	local self = setmetatable({
		Local = isLocal,
		Engine = loop(parent, "EngineLow", S.EngineLoop, isLocal),
		High = loop(parent, "EngineHigh", S.EngineHigh, isLocal),
		Squeal = if isLocal then loop(parent, "TyreSqueal", S.TyreSqueal, true) else nil,
		Wind = if isLocal then loop(parent, "Wind", S.Wind, true) else nil,
		Gear = 1,
		ShiftDip = 0,
		Throttle = 0,
		Pitch = 0.8,
	}, EngineAudio)
	return self
end

-- speed: forward studs/s, throttle 0..1, slide 0..1 (tyre squeal), dt seconds
function EngineAudio:Update(speed: number, throttle: number, slide: number, dt: number)
	local vol = Fx.GetEngineVolume()
	local gear, rpm = EngineAudio.GearFor(speed)
	if gear ~= self.Gear then
		-- the revs drop on an upshift, flare on a downshift
		self.ShiftDip = if gear > self.Gear then 0.18 else -0.08
		self.Gear = gear
		if self.Local and gear > 1 then
			Fx.Play("Shift", 0.25, 1 + gear * 0.03)
		end
	end
	self.ShiftDip += (0 - self.ShiftDip) * math.min(1, 7 * dt)
	self.Throttle += (throttle - self.Throttle) * math.min(1, 8 * dt)
	local idle = math.abs(speed) < 2
	local r = if idle then 0.12 + self.Throttle * 0.5 else 0.3 + rpm * 0.7
	r = math.clamp(r - self.ShiftDip, 0.05, 1.1)
	local pitch = 0.62 + r * 0.95 + (gear - 1) * 0.015
	self.Pitch += (pitch - self.Pitch) * math.min(1, 14 * dt)
	local load = 0.55 + 0.45 * self.Throttle
	local base = if self.Local then 0.42 else 0.9
	if self.Engine then
		self.Engine.PlaybackSpeed = self.Pitch
		local lowMix = if self.High then math.clamp(1.3 - r, 0.25, 1) else 1
		self.Engine.Volume = base * load * lowMix * vol
	end
	if self.High then
		self.High.PlaybackSpeed = self.Pitch * 0.9
		self.High.Volume = base * load * math.clamp((r - 0.35) * 1.6, 0, 1) * vol
	end
	if self.Squeal then
		local target = math.clamp(slide, 0, 1) * 0.45 * vol
		self.Squeal.Volume += (target - self.Squeal.Volume) * math.min(1, 10 * dt)
		self.Squeal.PlaybackSpeed = 0.9 + math.clamp(math.abs(speed) / 200, 0, 0.3)
	end
	if self.Wind then
		local t = math.clamp(math.abs(speed) / Config.Car.TopSpeed, 0, 1.2)
		self.Wind.Volume = t * t * 0.3 * vol
		self.Wind.PlaybackSpeed = 0.8 + t * 0.5
	end
end

-- Silence everything (paused / finished) without destroying.
function EngineAudio:Mute()
	for _, s in { self.Engine, self.High, self.Squeal, self.Wind } do
		if s then
			s.Volume = 0
		end
	end
end

function EngineAudio:Destroy()
	for _, s in { self.Engine, self.High, self.Squeal, self.Wind } do
		if s then
			s:Destroy()
		end
	end
end

return EngineAudio
