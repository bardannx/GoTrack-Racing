--!nonstrict
-- Sound playback and volume, the rainbow paint animation, and finish celebrations.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Fx = {}

-- Sounds ----------------------------------------------------------------------------------
local soundCache: { [string]: Sound } = {}
local masterVolume = 0.8

-- Master volume from Settings (0-1).
function Fx.SetVolume(v: number)
	masterVolume = math.clamp(v, 0, 1)
end

-- Current master volume.
function Fx.GetVolume(): number
	return masterVolume
end

-- engine sounds have their own slider on top of the master volume (Settings)
local engineVolume = 1
-- Engine volume from Settings (0-1).
function Fx.SetEngineVolume(v: number)
	engineVolume = math.clamp(v, 0, 1)
end

-- Engine volume after the master volume is applied.
function Fx.GetEngineVolume(): number
	return masterVolume * engineVolume
end

-- Plays a one-shot sound from Config.Sounds by name. Missing ids are skipped.
function Fx.Play(name: string, volume: number?, pitch: number?)
	local id = Config.Sounds[name]
	if not id or id == "" then
		return
	end
	local s = soundCache[name]
	if not s then
		s = Instance.new("Sound")
		s.SoundId = id
		s.Parent = SoundService
		soundCache[name] = s
	end
	local clone = s:Clone()
	clone.Volume = (volume or 0.5) * masterVolume
	clone.PlaybackSpeed = pitch or 1
	clone.Parent = SoundService
	clone:Play()
	Debris:AddItem(clone, 6)
end

-- A looping engine sound on `parent` (nil if no engine sound is set).
function Fx.EngineSound(parent: Instance): Sound?
	local id = Config.Sounds.EngineLoop
	if not id or id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = 0.35 * masterVolume
	s.Parent = parent
	s:Play()
	return s
end

-- Rainbow paint ---------------------------------------------------------------------------
local rainbowParts: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Starts the colour cycle on every part under `root` tagged Rainbow.
function Fx.RegisterRainbow(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Rainbow") then
			rainbowParts[d] = true
		end
	end
end

RunService.RenderStepped:Connect(function()
	local hue = (os.clock() * 0.18) % 1
	for part in rainbowParts do
		if part.Parent == nil then
			rainbowParts[part] = nil
		else
			part.Color = Color3.fromHSV(hue, 0.85, 1)
		end
	end
end)

-- Celebrations ----------------------------------------------------------------------------
local function emitterAt(parent: Instance, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Enabled = false
	for k, v in props do
		(pe :: any)[k] = v
	end
	pe.Parent = parent
	return pe
end

-- An invisible anchored part to hold an effect in the air.
local function anchorPart(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	Debris:AddItem(p, 8)
	return p
end

-- Plays the equipped finish celebration (fireworks, confetti...) at `pos`.
function Fx.Celebrate(kind: string, pos: Vector3)
	if kind == "celebrate_fireworks" then
		for i = 0, 5 do
			task.delay(i * 0.35, function()
				local offset = Vector3.new(math.random(-30, 30), math.random(25, 45), math.random(-30, 30))
				local p = anchorPart(pos + offset)
				local hue = math.random()
				local pe = emitterAt(p, {
					Color = ColorSequence.new(Color3.fromHSV(hue, 0.8, 1), Color3.fromHSV((hue + 0.1) % 1, 0.6, 1)),
					LightEmission = 1,
					Size = NumberSequence.new(1.2, 0),
					Lifetime = NumberRange.new(1, 1.6),
					Speed = NumberRange.new(30, 45),
					SpreadAngle = Vector2.new(180, 180),
					Drag = 2,
					Acceleration = Vector3.new(0, -20, 0),
				})
				pe:Emit(120)
				Fx.Play("Boost", 0.4, 0.7 + math.random() * 0.4)
			end)
		end
	elseif kind == "celebrate_confetti" then
		local p = anchorPart(pos + Vector3.new(0, 30, 0))
		for i = 0, 5 do
			local pe = emitterAt(p, {
				Color = ColorSequence.new(Color3.fromHSV(i / 6, 0.85, 1)),
				Size = NumberSequence.new(0.6),
				Lifetime = NumberRange.new(3, 4),
				Speed = NumberRange.new(10, 25),
				SpreadAngle = Vector2.new(70, 70),
				Acceleration = Vector3.new(0, -12, 0),
				Drag = 1,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-200, 200),
				Shape = Enum.ParticleEmitterShape.Box,
			})
			pe:Emit(40)
		end
	elseif kind == "celebrate_lightning" then
		for i = 1, 4 do
			task.delay(i * 0.25, function()
				local top = pos + Vector3.new(math.random(-20, 20), 70, math.random(-20, 20))
				local cur = top
				local segs = 7
				for s = 1, segs do
					local nextPos = top:Lerp(pos, s / segs) + Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
					local part = Instance.new("Part")
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.Material = Enum.Material.Neon
					part.Color = Color3.fromRGB(170, 220, 255)
					local len = (nextPos - cur).Magnitude
					part.Size = Vector3.new(0.6, 0.6, len)
					part.CFrame = CFrame.lookAt((cur + nextPos) / 2, nextPos)
					part.Parent = workspace
					Debris:AddItem(part, 0.25)
					cur = nextPos
				end
				local lp = anchorPart(pos + Vector3.new(0, 10, 0))
				local light = Instance.new("PointLight")
				light.Range = 60
				light.Brightness = 8
				light.Color = Color3.fromRGB(170, 220, 255)
				light.Parent = lp
				Debris:AddItem(lp, 0.2)
			end)
		end
	elseif kind == "celebrate_goldrain" then
		local p = anchorPart(pos + Vector3.new(0, 35, 0))
		p.Size = Vector3.new(40, 1, 40)
		local pe = emitterAt(p, {
			Color = ColorSequence.new(Color3.fromRGB(255, 225, 90), Color3.fromRGB(255, 170, 20)),
			LightEmission = 0.8,
			Size = NumberSequence.new(0.8),
			Lifetime = NumberRange.new(2.5, 3.5),
			Speed = NumberRange.new(2, 6),
			EmissionDirection = Enum.NormalId.Bottom,
			Acceleration = Vector3.new(0, -18, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-120, 120),
			Shape = Enum.ParticleEmitterShape.Box,
		})
		pe:Emit(250)
	else
		local p = anchorPart(pos + Vector3.new(0, 4, 0))
		local pe = emitterAt(p, {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 200)),
			LightEmission = 1,
			Size = NumberSequence.new(0.8, 0),
			Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(15, 25),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, -10, 0),
		})
		pe:Emit(60)
	end
end

return Fx
