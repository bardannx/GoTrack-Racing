--!nonstrict
-- Replays recorded runs as translucent ghost cars.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CarBuilder = require(Shared.CarBuilder)

local Fx = require(script.Parent.Fx)

local GhostPlayer = {}
GhostPlayer.__index = GhostPlayer

export type GhostData = { ms: number, rate: number, f: { number }, car: any, name: string?, title: string? }

local function frameCF(f: { number }, i: number): CFrame
	local b = i * 6
	return CFrame.new(f[b + 1], f[b + 2], f[b + 3]) * CFrame.fromEulerAnglesXYZ(f[b + 4], f[b + 5], f[b + 6])
end

function GhostPlayer.new(data: GhostData, label: string, color: Color3?)
	local parts = CarBuilder.Build(data.car, { Ghost = true })
	local model = parts.Model
	model.Name = "Ghost"
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(200, 44)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 400
	bb.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0.6, 0)
	name.BackgroundTransparency = 1
	name.Text = label
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = color or Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Parent = bb
	if data.title then
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0.4, 0)
		t.Position = UDim2.fromScale(0, 0.6)
		t.BackgroundTransparency = 1
		t.Text = data.title
		t.Font = Enum.Font.GothamMedium
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(255, 205, 80)
		t.TextStrokeTransparency = 0.5
		t.Parent = bb
	end
	bb.Adornee = parts.Chassis
	bb.Parent = model
	model.Parent = workspace
	Fx.RegisterRainbow(model)
	local self = setmetatable({
		Data = data,
		Model = model,
		Chassis = parts.Chassis,
		Count = #data.f // 6,
		Wheels = parts.Wheels,
		Spin = 0,
	}, GhostPlayer)
	self:Update(0)
	return self
end

-- Time in seconds this ghost first entered a region (for split comparisons).
function GhostPlayer.TimeAtRegion(data: GhostData, inRegion: (Vector3) -> boolean): number?
	local n = #data.f // 6
	for i = 0, n - 1 do
		local b = i * 6
		if inRegion(Vector3.new(data.f[b + 1], data.f[b + 2], data.f[b + 3])) then
			return i / data.rate
		end
	end
	return nil
end

function GhostPlayer:Update(t: number)
	local n = self.Count
	if n < 1 then
		return
	end
	local fi = t * self.Data.rate
	local i = math.floor(fi)
	local cf
	if i >= n - 1 then
		cf = frameCF(self.Data.f, n - 1)
	elseif i < 0 then
		cf = frameCF(self.Data.f, 0)
	else
		local a = frameCF(self.Data.f, i)
		local b = frameCF(self.Data.f, i + 1)
		local alpha = fi - i
		-- respawn teleports: don't interpolate across them
		if (a.Position - b.Position).Magnitude > 60 then
			cf = if alpha < 0.5 then a else b
		else
			cf = a:Lerp(b, alpha)
		end
	end
	self.Model:PivotTo(cf)
	self.Spin = (self.Spin - 0.35) % (math.pi * 2)
	for _, w in self.Wheels do
		w.Weld.C0 = CFrame.new(w.Offset) * CFrame.Angles(self.Spin, 0, 0)
	end
end

function GhostPlayer:SetVisible(v: boolean)
	self.Model.Parent = if v then workspace else nil
end

function GhostPlayer:Destroy()
	self.Model:Destroy()
end

return GhostPlayer
