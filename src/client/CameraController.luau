--!nonstrict
-- Camera modes.
--  Race views (Settings > Camera, C to cycle): chase_near, chase_far, tcam, cockpit, nose, tv
--  Menu views: showroom (car framed right of centre), garage (drag to rotate, wheel to zoom)
--  Cinematics: Cam.Scripted(fn) for the circuit intro flyover

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Track = require(Shared.Track)

local State = require(script.Parent.State)

local Cam = {}

local camera = workspace.CurrentCamera
local mode = "none"
local target: BasePart? = nil
local car: any = nil
local smoothPos: Vector3? = nil
local smoothLook: Vector3? = nil
local smoothUp = Vector3.yAxis
local shake = 0
local lastView = nil
local hiddenParts = {}

-- showroom / garage
local orbitCenter = Vector3.zero
local orbitRadius = 26
local orbitHeight = 7
local orbitAngle = 0.6
local orbitSpeed = 0.05
local orbitShift = 0 -- sideways offset of the look point (frames the car off-centre)
local orbitFov = 50
local targetRadius = 26
local targetShift = 0
local interactive = false
local dragging = false
local previewFov: number? = nil
local swayAmp = 0
local orbitTarget = 0.6

-- TV cameras
local tvTrack = nil
local tvSpots = {}
local tvIndex = 1
local tvHint = nil

local function setScriptable()
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
end

local function setHelmetHidden(hidden: boolean)
	if hidden then
		if car and car.Model then
			for _, d in car.Model:GetDescendants() do
				if d:IsA("BasePart") and (d.Name == "Helmet" or d.Name == "HelmetStripe" or d.Name == "Visor" or d.Name == "Collar") then
					d.LocalTransparencyModifier = 1
					hiddenParts[d] = true
				end
			end
		end
	else
		for d in hiddenParts do
			if d.Parent then
				d.LocalTransparencyModifier = 0
			end
		end
		hiddenParts = {}
	end
end

function Cam.Chase(carController: any)
	setScriptable()
	setHelmetHidden(false)
	mode = "race"
	car = carController
	target = carController.Chassis
	smoothPos = nil
	smoothLook = nil
	smoothUp = Vector3.yAxis
	lastView = nil
end

function Cam.Spectate(part: BasePart)
	setScriptable()
	setHelmetHidden(false)
	mode = "race"
	car = nil
	target = part
	smoothPos = nil
	lastView = nil
end

-- Track used for the TV camera positions
function Cam.SetTrack(t)
	tvTrack = t
	tvSpots = {}
	tvIndex = 1
	if not t then
		return
	end
	local step = 240
	local n = math.floor(t.Length / step)
	for k = 0, n - 1 do
		local s = k * step + step * 0.5
		local i = Track.Wrap(t, math.floor(s / Track.DS) + 1)
		-- sit on the outside of the upcoming bend
		local kSum = 0
		for o = 0, 20 do
			kSum += t.K[Track.Wrap(t, i + o)]
		end
		local side = if kSum >= 0 then -1 else 1
		local lat = side * (t.Width / 2 + 34)
		local x, y, z = Track.PointAt(t, s, lat)
		table.insert(tvSpots, { S = s, Pos = Vector3.new(x, y + 16, z) })
	end
end

-- Menu showroom: slow drift around the car, car framed to the right of the screen centre
-- baseAngle: where the camera sits around the car (radians); sway: gentle drift amplitude
function Cam.Showroom(center: Vector3, radius: number, height: number, shift: number?, fov: number?, baseAngle: number?, sway: number?)
	setScriptable()
	setHelmetHidden(false)
	local wasOrbit = mode == "orbit"
	mode = "orbit"
	orbitCenter = center
	targetRadius = radius
	orbitHeight = height
	targetShift = shift or 0
	orbitSpeed = 0
	orbitFov = fov or 50
	swayAmp = sway or 0
	if baseAngle then
		-- shortest way round to the new angle
		orbitTarget = orbitAngle + (((baseAngle - orbitAngle + math.pi) % (2 * math.pi)) - math.pi)
	end
	if not wasOrbit then
		orbitRadius = radius
		orbitShift = targetShift
		orbitAngle = orbitTarget
	end
end

-- Kept for older callers
function Cam.Orbit(center: Vector3, radius: number, height: number, speed: number?)
	Cam.Showroom(center, radius, height, 0, 55)
	orbitSpeed = speed or 0.08
end

function Cam.SetInteractive(on: boolean)
	interactive = on
	dragging = false
end

function Cam.PreviewFov(fov: number?)
	previewFov = fov
end

function Cam.Stop()
	mode = "none"
	setHelmetHidden(false)
end

-- Cinematic camera: fn(dt) returns the camera CFrame (and optionally a field of view)
-- every frame until another mode takes over (circuit intro flyovers)
local scripted: ((number) -> (CFrame?, number?))? = nil
function Cam.Scripted(fn: (number) -> (CFrame?, number?))
	setScriptable()
	setHelmetHidden(false)
	mode = "script"
	scripted = fn
end

function Cam.Shake(amount: number)
	if State.Setting("Shake") then
		shake = math.max(shake, amount)
	end
end

function Cam.Mode(): string
	return mode
end

-- garage input: drag to rotate, wheel / pinch to zoom
UserInputService.InputBegan:Connect(function(io, processed)
	if not interactive or processed then
		return
	end
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
		dragging = true
	end
end)
UserInputService.InputEnded:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
UserInputService.InputChanged:Connect(function(io, processed)
	if not interactive then
		return
	end
	if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
		orbitAngle -= io.Delta.X * 0.008
		orbitTarget = orbitAngle
	elseif io.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		targetRadius = math.clamp(targetRadius - io.Position.Z * 2.5, 13, 40)
	end
end)
UserInputService.TouchPinch:Connect(function(_, scale, _, st)
	if interactive and st == Enum.UserInputState.Change then
		targetRadius = math.clamp(targetRadius / math.max(scale, 0.5) ^ 0.05, 13, 40)
	end
end)

local occlusionParams = RaycastParams.new()
occlusionParams.FilterType = Enum.RaycastFilterType.Include
occlusionParams.IgnoreWater = true
occlusionParams.RespectCanCollide = false
local occludedDist: number? = nil

local function raceView(dt: number, cf: CFrame, view: string, speed: number)
	local pos = cf.Position
	local look = cf.LookVector
	local grounded = car == nil or car.Grounded
	local up = if grounded then cf.UpVector else Vector3.yAxis:Lerp(cf.UpVector, 0.3)
	smoothUp = smoothUp:Lerp(up, math.min(1, 4 * dt))
	if smoothUp.Magnitude < 0.1 then
		smoothUp = Vector3.yAxis
	end
	smoothUp = smoothUp.Unit
	local flatLook = look - smoothUp * look:Dot(smoothUp)
	flatLook = if flatLook.Magnitude > 0.05 then flatLook.Unit else look
	local speedT = math.clamp(speed / Config.Car.TopSpeed, 0, 1.3)
	local camPos, lookAt, camUp
	local fovBoost = if State.Setting("SpeedFov") ~= false then speedT * 14 else 0

	if view == "cockpit" or view == "tcam" or view == "nose" then
		local attr = if view == "cockpit" then "CockpitCam" elseif view == "tcam" then "TCam" else "NoseCam"
		local custom = target and target:GetAttribute(attr)
		local offset = if typeof(custom) == "Vector3" then custom elseif view == "cockpit" then Vector3.new(0, 1.12, -0.25) elseif view == "tcam" then Vector3.new(0, 2.25, 0.75) else Vector3.new(0, 0.3, -6.9)
		local rigid = cf * CFrame.new(offset)
		-- smooth only the rotation a little so bumps don't make you seasick
		local wantLook = rigid.LookVector
		smoothLook = if smoothLook then (smoothLook :: Vector3):Lerp(wantLook, math.min(1, 14 * dt)) else wantLook
		camPos = rigid.Position
		local pitchDown = if view == "tcam" then 0.1 elseif view == "cockpit" then 0.12 else 0.02
		lookAt = camPos + (smoothLook :: Vector3) * 20 - smoothUp * (20 * pitchDown)
		camUp = smoothUp
		smoothPos = nil
		fovBoost *= 0.6
	elseif view == "tv" and #tvSpots > 0 and tvTrack then
		local idx = Track.Project(tvTrack, pos.X, pos.Y, pos.Z, tvHint)
		tvHint = idx
		local carS = tvTrack.S[idx]
		-- first spot at or ahead of (car - 90 studs)
		local best, bestD = 1, math.huge
		for k, sp in tvSpots do
			local d = (sp.S - (carS - 90)) % tvTrack.Length
			if d < bestD then
				best, bestD = k, d
			end
		end
		tvIndex = best
		local spot = tvSpots[tvIndex].Pos
		camPos = spot
		lookAt = pos + smoothUp * 1.5
		camUp = Vector3.yAxis
		local dist = (spot - pos).Magnitude
		local fov = math.clamp(math.deg(2 * math.atan(26 / math.max(dist, 1))), 9, 70)
		camera.FieldOfView = camera.FieldOfView + (fov - camera.FieldOfView) * math.min(1, 6 * dt)
		smoothPos = nil
		return camPos, lookAt, camUp, nil
	else
		local far = view == "chase_far"
		local dist = (if far then 27 else 18.5) + speedT * 3
		local height = (if far then 8.5 else 5) + speedT * 0.5
		local desired = pos - flatLook * dist + smoothUp * height
		if not smoothPos then
			smoothPos = desired
		end
		smoothPos = (smoothPos :: Vector3):Lerp(desired, 1 - math.exp(-9 * dt))
		camPos = smoothPos :: Vector3
		-- don't let the chase camera sink into walls, grandstands or buildings (that made
		-- the scenery look see-through). Pull it in front of whatever blocks the view.
		local circuit = workspace:FindFirstChild("GoTrackCircuit")
		if circuit then
			if occlusionParams.FilterDescendantsInstances[1] ~= circuit then
				occlusionParams.FilterDescendantsInstances = { circuit }
			end
			local origin = pos + smoothUp * 2.5
			local toCam = camPos - origin
			local hit = workspace:Spherecast(origin, 0.9, toCam, occlusionParams)
			local want = if hit then math.max(4, hit.Distance - 0.4) else toCam.Magnitude
			occludedDist = if occludedDist then math.min(want, occludedDist + dt * 30) else want
			occludedDist = math.min(occludedDist :: number, want)
			if occludedDist < toCam.Magnitude - 0.05 and toCam.Magnitude > 0.01 then
				camPos = origin + toCam.Unit * (occludedDist :: number)
			end
		end
		lookAt = pos + smoothUp * 2.2 + flatLook * 8
		camUp = smoothUp
	end
	local baseFov = previewFov or State.Setting("Fov") or 78
	return camPos, lookAt, camUp, baseFov + fovBoost
end

RunService:BindToRenderStep("GoTrackCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera = workspace.CurrentCamera
	if mode == "race" and target and target.Parent then
		local view = State.Setting("Camera")
		if car == nil and (view == "cockpit" or view == "tcam" or view == "nose") then
			view = "chase_near" -- spectating: first-person views make no sense
		end
		if view ~= lastView then
			lastView = view
			smoothPos = nil
			smoothLook = nil
			setHelmetHidden(view == "cockpit")
		end
		local cf = target.CFrame
		local speed = target.AssemblyLinearVelocity.Magnitude
		local camPos, lookAt, camUp, fov = raceView(dt, cf, view, speed)
		local shakeOffset = Vector3.zero
		if shake > 0 then
			shakeOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * shake
			shake = math.max(0, shake - dt * 3)
		end
		camera.CFrame = CFrame.lookAt(camPos + shakeOffset, lookAt, camUp)
		if fov then
			camera.FieldOfView = camera.FieldOfView + (fov - camera.FieldOfView) * math.min(1, 5 * dt)
		end
	elseif mode == "script" and scripted then
		local cf, fov = scripted(dt)
		if cf then
			camera.CFrame = cf
			if fov then
				camera.FieldOfView = fov
			end
		end
	elseif mode == "orbit" then
		if not dragging then
			orbitTarget += dt * orbitSpeed
			orbitAngle += (orbitTarget - orbitAngle) * math.min(1, 3 * dt)
		end
		orbitRadius += (targetRadius - orbitRadius) * math.min(1, 6 * dt)
		orbitShift += (targetShift - orbitShift) * math.min(1, 4 * dt)
		local a = orbitAngle + swayAmp * math.sin(os.clock() * 0.13)
		local pos = orbitCenter + Vector3.new(math.cos(a) * orbitRadius, orbitHeight, math.sin(a) * orbitRadius)
		local toCenter = (orbitCenter - pos)
		local right = toCenter.Unit:Cross(Vector3.yAxis)
		if right.Magnitude < 0.01 then
			right = Vector3.xAxis
		end
		-- shifting the look point left pushes the car to the right of the screen
		local lookAt = orbitCenter + Vector3.new(0, 1.2, 0) - right.Unit * orbitShift
		camera.CFrame = CFrame.lookAt(pos, lookAt)
		local fov = previewFov or orbitFov
		camera.FieldOfView = camera.FieldOfView + (fov - camera.FieldOfView) * math.min(1, 8 * dt)
	end
end)

return Cam
