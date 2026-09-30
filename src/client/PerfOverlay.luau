--!nonstrict
-- FPS / ping counter (Settings > Show FPS & ping) and automatic graphics lowering when a
-- device struggles during a race.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Kit = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)

local Perf = {}

local gui, root = Kit.Screen("GoTrackPerf", 60)
local label = Kit.Label(root, "", 12, {
	Font = Kit.Fonts.Mono,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -28),
	Size = UDim2.fromOffset(200, 18),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = Color3.fromRGB(120, 255, 160),
	TextStrokeTransparency = 0.4,
})
label.RichText = false

local frames, acc = 0, 0
local fps = 60
local avg = 60 -- slow moving average used for auto quality

RunService.RenderStepped:Connect(function(dt)
	frames += 1
	acc += dt
	avg += ((1 / math.max(dt, 1e-3)) - avg) * math.min(1, dt * 0.5)
	if acc >= 0.5 then
		fps = frames / acc
		frames, acc = 0, 0
		local show = State.Profile ~= nil and State.Setting("ShowFPS") == true
		gui.Enabled = show
		if show then
			local ping = 0
			pcall(function()
				ping = Players.LocalPlayer:GetNetworkPing() * 1000
			end)
			label.Text = string.format("%d FPS  •  %d ms", math.floor(fps + 0.5), math.floor(ping + 0.5))
			label.TextColor3 = if fps >= 50 then Color3.fromRGB(120, 255, 160) elseif fps >= 30 then Color3.fromRGB(255, 210, 80) else Color3.fromRGB(255, 90, 90)
		end
	end
end)

function Perf.Fps(): number
	return fps
end

function Perf.AvgFps(): number
	return avg
end

-- Call once a race has been running for a while: lowers effects right away and the
-- scenery quality for the next race if the device can't keep up.
local lowered = false
function Perf.CheckAutoLower()
	if lowered or avg >= 27 then
		return false
	end
	local q = State.Setting("Quality") or 3
	if q <= 1 then
		return false
	end
	lowered = true
	Lighting.GlobalShadows = false
	for _, name in { "GoTrackBloom", "GoTrackRays", "GoTrackDOF" } do
		local e = Lighting:FindFirstChild(name)
		if e then
			e.Enabled = false
		end
	end
	State.SetSetting("Quality", q - 1)
	Kit.Toast("Graphics lowered to keep the race smooth (change it in Settings).", "warn")
	return true
end

return Perf
