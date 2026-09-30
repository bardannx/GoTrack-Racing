--!nonstrict
-- The loading screen. Runs first (ReplicatedFirst), replaces Roblox's default screen,
-- and fades out once the game has loaded and the main menu exists.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Tiny Instance helper. This runs from ReplicatedFirst before the UI Kit exists.
local function new(className, props, parent)
	local i = Instance.new(className)
	for k, v in props do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local gui =
	new("ScreenGui", { Name = "GoTrackLoading", IgnoreGuiInset = true, DisplayOrder = 100, ResetOnSpawn = false }, nil)
local bg =
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, gui)
new(
	"UIGradient",
	{ Color = ColorSequence.new(Color3.fromRGB(26, 30, 56), Color3.fromRGB(8, 9, 16)), Rotation = 90 },
	bg
)

-- animated racing stripes
local stripes = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true }, bg)
local stripeParts = {}
for k = 0, 5 do
	local s = new("Frame", {
		BackgroundColor3 = if k % 2 == 0 then Color3.fromRGB(255, 184, 28) else Color3.fromRGB(236, 38, 58),
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.1 + k * 0.18, 0.5),
		Size = UDim2.new(0, 70, 2, 0),
		Rotation = 25,
	}, stripes)
	table.insert(stripeParts, { s, 0.1 + k * 0.18 })
end

-- logo lockup (same look as the in-game logo: heavy italic, gold gradient, dark outline)
local LOGO = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local SUB = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Italic)
local SEMI = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 4, 0.4, 6),
	Size = UDim2.fromScale(0.62, 0.14),
	BackgroundTransparency = 1,
	Text = "GOTRACK",
	FontFace = LOGO,
	TextScaled = true,
	TextColor3 = Color3.new(0, 0, 0),
	TextTransparency = 0.45,
}, bg)
local logo = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromScale(0.62, 0.14),
	BackgroundTransparency = 1,
	Text = "GOTRACK",
	FontFace = LOGO,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
}, bg)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 90)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 176, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 104, 36)),
	}),
	Rotation = 90,
}, logo)
new("UIStroke", { Color = Color3.fromRGB(34, 12, 4), Thickness = 3 }, logo)
local subRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.51),
	Size = UDim2.fromScale(0.5, 0.05),
	BackgroundTransparency = 1,
}, bg)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0.02, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, subRow)
-- One of the slanted colour bars under the logo.
local function speedBar(order, color)
	local b = new(
		"Frame",
		{ Size = UDim2.fromScale(0.16, 0.14), BackgroundColor3 = color, BorderSizePixel = 0, LayoutOrder = order },
		subRow
	)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
end
speedBar(1, Color3.fromRGB(236, 38, 58))
new("TextLabel", {
	Size = UDim2.fromScale(0.34, 1),
	BackgroundTransparency = 1,
	Text = "RACING",
	FontFace = SUB,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(248, 249, 255),
	LayoutOrder = 2,
}, subRow)
speedBar(3, Color3.fromRGB(255, 184, 28))
new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.585),
	Size = UDim2.fromScale(0.6, 0.032),
	BackgroundTransparency = 1,
	Text = "31 circuits  •  10-car grids  •  one champion",
	FontFace = SEMI,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(190, 198, 222),
}, bg)

local barBg = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.66),
	Size = UDim2.fromScale(0.3, 0.01),
	BackgroundColor3 = Color3.fromRGB(43, 48, 71),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, bg)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, barBg)
local bar = new(
	"Frame",
	{ Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = Color3.fromRGB(255, 184, 28), BorderSizePixel = 0 },
	barBg
)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)

gui.Parent = playerGui

local t0 = os.clock()
local conn = RunService.RenderStepped:Connect(function()
	local t = os.clock() - t0
	bar.Position = UDim2.fromScale(((t * 0.7) % 1.3) - 0.3, 0)
	for _, sp in stripeParts do
		sp[1].Position = UDim2.fromScale(((sp[2] + t * 0.05) % 1.2) - 0.1, 0.5)
	end
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
-- wait for the main UI to exist (or give up after 20s)
local waited = 0
while not playerGui:FindFirstChild("GoTrackMenu") and waited < 20 do
	task.wait(0.1)
	waited += 0.1
end
task.wait(0.4)
conn:Disconnect()
local info = TweenInfo.new(0.5)
TweenService:Create(bg, info, { BackgroundTransparency = 1 }):Play()
for _, d in bg:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, info, { TextTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, info, { Transparency = 1 }):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.55)
gui:Destroy()
