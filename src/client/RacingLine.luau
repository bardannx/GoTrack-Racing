--!nonstrict
-- F1-game style dynamic racing line: chevrons painted on the road ahead of your car
-- along the ideal line. Green = you can go flat out, yellow = lift / be ready,
-- red = brake now (you're too fast for the corner ahead). Settings: off / braking / full.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Track = require(Shared.Track)

local State = require(script.Parent.State)

local RacingLine = {}

local COUNT = 30 -- chevrons shown
local SPACING = 3 -- samples between chevrons (3 x 8 = 24 studs)
local ARM = 3.6
local ANGLE = math.rad(38)
local LIFT = 0.66
local BRAKE = Track.Profile.Brake * 0.9

local GREEN = Color3.fromRGB(40, 230, 90)
local YELLOW = Color3.fromRGB(255, 205, 30)
local RED = Color3.fromRGB(255, 45, 45)

local folder, conn = nil, nil
local arms = {} -- { {left, right} }
local hidden = CFrame.new(0, -5000, 0)

-- One arm of a chevron: a thin neon strip laid on the road.
local function makeArm(parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.new(0.7, 0.05, ARM)
	p.Material = Enum.Material.SmoothPlastic
	p.Color = GREEN
	p.Transparency = 0.15
	p.CFrame = hidden
	p.Parent = parent
	return p
end

-- Removes the racing line (end of race, or turned off in Settings).
function RacingLine.Stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	arms = {}
end

-- t: sampled track, car: CarController
function RacingLine.Start(t, car)
	RacingLine.Stop()
	folder = Instance.new("Folder")
	folder.Name = "GoTrackRacingLine"
	folder.Parent = workspace
	for k = 1, COUNT do
		arms[k] = { makeArm(folder), makeArm(folder) }
	end
	local hint = nil
	local colorTimer = 0
	local colors = {}
	local partsList, cfList = {}, {}
	for k = 1, COUNT do
		table.insert(partsList, arms[k][1])
		table.insert(partsList, arms[k][2])
	end
	conn = RunService.RenderStepped:Connect(function(dt)
		local mode = State.Setting("RacingLine")
		local root = car.Chassis
		if mode == "off" or not root.Parent then
			for i, p in partsList do
				cfList[i] = hidden
			end
			workspace:BulkMoveTo(partsList, cfList, Enum.BulkMoveMode.FireCFrameChanged)
			return
		end
		local pos = root.Position
		local idx = Track.Project(t, pos.X, pos.Y, pos.Z, hint)
		hint = idx
		local speed = math.max(car.ForwardSpeed, 0)
		colorTimer -= dt
		local recolor = colorTimer <= 0
		if recolor then
			colorTimer = 0.1
		end
		-- start a little ahead of the car, snapped to the chevron grid so they don't slide
		local base = idx + 2
		base = base - (base % SPACING) + SPACING
		for k = 1, COUNT do
			local i = Track.Wrap(t, base + (k - 1) * SPACING)
			local j = Track.Wrap(t, i + 1)
			local lat = t.RL[i]
			local p0 = Vector3.new(t.X[i] + t.RX[i] * lat, t.Y[i] + LIFT, t.Z[i] + t.RZ[i] * lat)
			local latJ = t.RL[j]
			local p1 = Vector3.new(t.X[j] + t.RX[j] * latJ, t.Y[j] + LIFT, t.Z[j] + t.RZ[j] * latJ)
			local tip = CFrame.lookAt(p0, p1)
			-- colour: can the car, braking from this chevron, make the slowest point ahead?
			if recolor then
				local distToChev = ((k - 1) * SPACING + (base - idx)) * Track.DS
				local vmin, dmin = math.huge, 0
				for o = 0, 18 do
					local q = Track.Wrap(t, i + o)
					local allowed = math.sqrt(t.V[q] * t.V[q] + 2 * BRAKE * o * Track.DS)
					if allowed < vmin then
						vmin, dmin = allowed, o
					end
				end
				-- speed the car would carry to this chevron if it kept going
				local need = vmin
				local carAtChev = speed
				local c
				if carAtChev > need + 6 then
					c = RED
				elseif
					carAtChev > need - 18
					or t.V[Track.Wrap(t, i + dmin)] < Track.Profile.TopSpeed * 0.8
						and distToChev < 60
						and carAtChev > need - 30
				then
					c = YELLOW
				else
					c = GREEN
				end
				colors[k] = c
			end
			local c = colors[k] or GREEN
			local show = mode == "full" or c ~= GREEN
			local a = arms[k]
			if show then
				-- the two arms form a ">" pointing along the track
				local offX = math.sin(ANGLE) * ARM / 2
				local offZ = math.cos(ANGLE) * ARM / 2
				cfList[k * 2 - 1] = tip * CFrame.new(-offX, 0, offZ) * CFrame.Angles(0, -ANGLE, 0)
				cfList[k * 2] = tip * CFrame.new(offX, 0, offZ) * CFrame.Angles(0, ANGLE, 0)
				if recolor and a[1].Color ~= c then
					a[1].Color = c
					a[2].Color = c
				end
			else
				cfList[k * 2 - 1] = hidden
				cfList[k * 2] = hidden
			end
		end
		workspace:BulkMoveTo(partsList, cfList, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return RacingLine
