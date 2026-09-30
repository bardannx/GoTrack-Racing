--!nonstrict
-- GoTrack UI kit v3: one consistent, responsive, animated design system.
-- Everything scales from a 1280x720 reference and respects the Roblox top bar.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Fx = require(script.Parent.Parent.Fx)

local Kit = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Kit.Colors = {
	Bg = rgb(10, 12, 21),
	Panel = rgb(19, 22, 35),
	Panel2 = rgb(29, 33, 51),
	Panel3 = rgb(43, 48, 71),
	Stroke = rgb(70, 79, 116),
	Text = rgb(246, 247, 251),
	SubText = rgb(160, 168, 194),
	Muted = rgb(110, 118, 145),
	Accent = rgb(255, 184, 28),
	Accent2 = rgb(48, 182, 255),
	Red = rgb(236, 38, 58),
	Success = rgb(58, 216, 124),
	Danger = rgb(255, 72, 84),
	Warn = rgb(255, 196, 54),
	Purple = rgb(152, 92, 255),
	Gold = rgb(255, 204, 64),
	Silver = rgb(205, 212, 224),
	Bronze = rgb(214, 132, 62),
	White = rgb(255, 255, 255),
}
local C = Kit.Colors

Kit.Fonts = {
	Logo = Enum.Font.Michroma,
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
	Mono = Enum.Font.RobotoMono,
	Number = Enum.Font.TitilliumWeb,
}

-- Brand fonts (FontFace): heavy italic Montserrat reads fast and "racing", and stays crisp
-- at every size (the old Michroma logo got thin and muddy on busy backgrounds).
Kit.Faces = {
	Logo = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
	Sub = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Italic),
	Heavy = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold),
	Semi = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold),
}

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function apply(inst: Instance, props: { [string]: any }?)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	return inst
end
Kit.Apply = apply

function Kit.Corner(parent: Instance, radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

function Kit.Round(parent: Instance): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function Kit.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or C.Stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.45,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.Padding(parent: Instance, px: number, py: number?): UIPadding
	local y = py or px
	return Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, y),
		PaddingBottom = UDim.new(0, y),
		Parent = parent,
	})
end

function Kit.List(parent: Instance, dir: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Kit.Grid(parent: Instance, cell: UDim2, padding: number?): UIGridLayout
	return Kit.new("UIGridLayout", {
		CellSize = cell,
		CellPadding = UDim2.fromOffset(padding or 10, padding or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- NOTE: a UIGradient multiplies the object's colour, so the parent is set to white and the
-- gradient alone defines the colours.
function Kit.Gradient(parent: Instance, c0: Color3, c1: Color3, rotation: number?): UIGradient
	if parent:IsA("GuiObject") and not parent:IsA("TextLabel") then
		(parent :: any).BackgroundColor3 = Color3.new(1, 1, 1)
	end
	return Kit.new("UIGradient", {
		Color = ColorSequence.new(c0, c1),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

-- Vertical "depth" shading: slightly lighter top, base middle, darker bottom.
-- (Gradients multiply, so the parent gets a lightened base and the gradient only shades.)
function Kit.Depth(parent: Instance, base: Color3, strength: number?): UIGradient
	local s = strength or 1
	if parent:IsA("GuiObject") then
		(parent :: any).BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.1 * s)
	end
	local mid = 1 - 0.07 * s
	local low = 1 - 0.2 * s
	return Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, Color3.new(mid, mid, mid)),
			ColorSequenceKeypoint.new(1, Color3.new(low, low, low)),
		}),
		Rotation = 90,
		Parent = parent,
	})
end

function Kit.Tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Endless back-and-forth tween (bobbing crowns, pulsing halos). No script loop: it stops by
-- itself when the instance is destroyed.
function Kit.Loop(inst: Instance, period: number, props: { [string]: any }): Tween
	local t = TweenService:Create(inst, TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), props)
	t:Play()
	return t
end

---------------------------------------------------------------------------
-- Screens (auto-scaled) + Roblox top-bar safe area
---------------------------------------------------------------------------
local roots: { Frame } = {}
local insetCallbacks = {}

-- Design space is 1280x720. Phones (short screens) use a 960x540 reference instead, so
-- text and buttons come out ~35% bigger and stay readable/tappable; screens then get a
-- shorter root (540 units tall) and lay themselves out in "compact" mode.
local PHONE_HEIGHT = 600 -- viewport points below this = phone layout

-- Studio-only: set LocalPlayer attribute "TestViewport" (Vector2, e.g. 844x390 for a phone,
-- 1180x820 for an iPad) to lay every screen out for that device, drawn in the top-left
-- corner. Lets play-tests check phone / tablet layouts without the device simulator.
-- "TestZoom" (number) shrinks the drawing so big tablet screens fit inside the Studio view.
local IS_STUDIO = game:GetService("RunService"):IsStudio()
local function testViewport(): Vector2?
	if not IS_STUDIO then
		return nil
	end
	local lp = game:GetService("Players").LocalPlayer
	local v = lp and lp:GetAttribute("TestViewport")
	return if typeof(v) == "Vector2" and v.X > 100 and v.Y > 100 then v else nil
end

local function viewport(): Vector2
	local t = testViewport()
	if t then
		return t
	end
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

local function isCompact(): boolean
	return viewport().Y < PHONE_HEIGHT
end

local function currentScale(): number
	local vp = viewport()
	local refW, refH = 1280, 720
	if vp.Y < PHONE_HEIGHT then
		refW, refH = 960, 540
	end
	local s = math.min(vp.X / refW, vp.Y / refH)
	return math.clamp(s, 0.45, 1.5)
end
Kit.Scale = currentScale
Kit.Compact = isCompact

-- Root size in design units (what a full-screen frame measures inside a Kit.Screen)
function Kit.RootSize(): Vector2
	return viewport() / currentScale()
end

local function applyScale(root: Frame)
	local s = currentScale()
	local sc = root:FindFirstChildOfClass("UIScale")
	local t = testViewport()
	local zoom = 1
	if t then
		local lp = game:GetService("Players").LocalPlayer
		local z = lp and lp:GetAttribute("TestZoom")
		zoom = if typeof(z) == "number" and z > 0.1 then z else 1
	end
	if sc then
		sc.Scale = s * zoom
	end
	if t then
		root.Size = UDim2.fromOffset(t.X / s, t.Y / s)
		root.ClipsDescendants = true
	else
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		root.ClipsDescendants = false
	end
end

-- Safe area in root (scaled) units: top = height of the Roblox top bar,
-- left = where the Roblox buttons end, right = space reserved on the right.
function Kit.Inset(): (number, number, number)
	local s = currentScale()
	local ok, rect = pcall(function()
		return GuiService.TopbarInset
	end)
	local vpX = viewport().X
	if ok and rect and rect.Height > 0 then
		return rect.Max.Y / s, rect.Min.X / s, math.max(0, vpX - rect.Max.X) / s
	end
	return 58 / s, 170 / s, 0
end

function Kit.BindInset(fn: (number, number, number) -> ())
	table.insert(insetCallbacks, fn)
	fn(Kit.Inset())
end

local fitters = {}

local function refreshAll()
	for _, r in roots do
		applyScale(r)
	end
	local top, left, right = Kit.Inset()
	for _, fn in insetCallbacks do
		task.spawn(fn, top, left, right)
	end
	for _, fn in fitters do
		task.spawn(fn)
	end
end

-- Shrinks `frame` (via UIScale) so content that is `natural` units tall fits the screen
-- height minus `reserve()` units. Used by fixed-height columns on short phone screens.
function Kit.FitHeight(frame: GuiObject, natural: number, reserve: () -> number, minScale: number?)
	local sc = frame:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = frame })
	local function update()
		local avail = Kit.RootSize().Y - reserve()
		sc.Scale = math.clamp(avail / natural, minScale or 0.6, 1)
	end
	table.insert(fitters, update)
	update()
end

function Kit.Screen(name: string, order: number?): (ScreenGui, Frame)
	local gui = Kit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order or 1,
		Parent = playerGui,
	})
	local root = Kit.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	Kit.new("UIScale", { Parent = root })
	applyScale(root)
	table.insert(roots, root)
	return gui, root
end

task.spawn(function()
	local cam = workspace.CurrentCamera
	while not cam do
		task.wait()
		cam = workspace.CurrentCamera
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(refreshAll)
	if IS_STUDIO then
		local lp = game:GetService("Players").LocalPlayer
		if lp then
			lp:GetAttributeChangedSignal("TestViewport"):Connect(refreshAll)
			lp:GetAttributeChangedSignal("TestZoom"):Connect(refreshAll)
		end
	end
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refreshAll)
	end)
	refreshAll()
end)

-- Touch-screen device (Studio play-tests can fake it with LocalPlayer attribute "TestTouch")
function Kit.Touch(): boolean
	if IS_STUDIO then
		local lp = game:GetService("Players").LocalPlayer
		if lp and lp:GetAttribute("TestTouch") ~= nil then
			return lp:GetAttribute("TestTouch") == true
		end
	end
	return UserInputService.TouchEnabled
end

function Kit.IsMobile(): boolean
	if IS_STUDIO then
		local lp = game:GetService("Players").LocalPlayer
		if lp and lp:GetAttribute("TestTouch") ~= nil then
			return lp:GetAttribute("TestTouch") == true
		end
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

---------------------------------------------------------------------------
-- Basic widgets
---------------------------------------------------------------------------
-- Glass panel: soft vertical gradient, hairline stroke
function Kit.Panel(parent: Instance, props: { [string]: any }?): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.04, BorderSizePixel = 0, Parent = parent })
	apply(f, props)
	Kit.Corner(f, 16)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(rgb(255, 255, 255), rgb(200, 205, 225)),
		Rotation = 90,
		Parent = f,
	})
	Kit.Stroke(f, rgb(90, 100, 145), 1.2, 0.55)
	return f
end

-- Flat card used inside panels
function Kit.Card(parent: Instance, props: { [string]: any }?, color: Color3?): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = color or C.Panel2, BorderSizePixel = 0, Parent = parent })
	apply(f, props)
	Kit.Corner(f, 12)
	Kit.Stroke(f, rgb(255, 255, 255), 1, 0.92)
	return f
end

function Kit.Label(parent: Instance, text: string, size: number?, props: { [string]: any }?): TextLabel
	local l = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size or 18,
		Font = Kit.Fonts.Medium,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, (size or 18) + 6),
		RichText = true,
		Parent = parent,
	})
	apply(l, props)
	return l
end

-- GOTRACK / RACING logo lockup. size = height of "GOTRACK" in design units.
-- opts: { Align = "left" | "center", Parent-relative props via Kit.Apply }
function Kit.Logo(parent: Instance, size: number, opts: { [string]: any }?): Frame
	local o = opts or {}
	local center = o.Align == "center"
	local w = math.floor(size * 5.5)
	local h = math.floor(size * 1.72)
	local f = Kit.new("Frame", { Name = "Logo", BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h), Parent = parent })
	local align = if center then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	local z = o.ZIndex or 1
	-- soft drop shadow for contrast on bright 3D scenes
	local shadow = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = "GOTRACK",
		FontFace = Kit.Faces.Logo,
		TextSize = size,
		TextColor3 = Color3.new(0, 0, 0),
		TextTransparency = 0.45,
		TextXAlignment = align,
		Position = UDim2.fromOffset(math.max(2, size * 0.04), math.max(3, size * 0.07)),
		Size = UDim2.new(1, 0, 0, size * 1.05),
		ZIndex = z,
		Parent = f,
	})
	local _ = shadow
	local main = Kit.new("TextLabel", {
		Name = "Word",
		BackgroundTransparency = 1,
		Text = "GOTRACK",
		FontFace = Kit.Faces.Logo,
		TextSize = size,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = align,
		Size = UDim2.new(1, 0, 0, size * 1.05),
		ZIndex = z + 1,
		Parent = f,
	})
	Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 90)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 176, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 104, 36)),
		}),
		Rotation = 90,
		Parent = main,
	})
	Kit.new("UIStroke", { Color = Color3.fromRGB(34, 12, 4), Thickness = math.max(1.5, size / 30), Transparency = 0.05, Parent = main })
	-- RACING with speed bars
	local sub = size * 0.34
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, size * 1.08), Size = UDim2.new(1, 0, 0, sub * 1.3), ZIndex = z + 1, Parent = f })
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = if center then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, math.floor(sub * 0.45)),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local function bar(order: number, width: number, color: Color3)
		local b = Kit.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromOffset(width, math.max(3, sub * 0.2)), LayoutOrder = order, ZIndex = z + 1, Parent = row })
		Kit.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = b })
		return b
	end
	bar(1, size * (if center then 0.9 else 0.35), Color3.fromRGB(236, 38, 58))
	local racing = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = "RACING",
		FontFace = Kit.Faces.Sub,
		TextSize = sub,
		TextColor3 = Color3.fromRGB(248, 249, 255),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, sub * 1.3),
		LayoutOrder = 2,
		ZIndex = z + 1,
		Parent = row,
	})
	Kit.new("UIStroke", { Color = Color3.fromRGB(10, 12, 20), Thickness = math.max(1, sub / 14), Transparency = 0.25, Parent = racing })
	bar(3, size * (if center then 0.9 else 1.6), Color3.fromRGB(255, 184, 28))
	Kit.Apply(f, o.Props)
	return f
end

-- Small uppercase section heading with an accent tick
function Kit.Section(parent: Instance, text: string, order: number?, color: Color3?): Frame
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order or 0, Parent = parent })
	local tick = Kit.new("Frame", { BackgroundColor3 = color or C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 5), Size = UDim2.fromOffset(4, 14), Parent = f })
	Kit.Corner(tick, 2)
	Kit.Label(f, string.upper(text), 13, { Font = Kit.Fonts.Title, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -12, 1, 0), TextColor3 = C.SubText })
	return f
end

local STYLES = {
	primary = { bg = C.Accent, text = rgb(28, 18, 4), stroke = rgb(255, 230, 150) },
	red = { bg = C.Red, text = C.White, stroke = rgb(255, 150, 160) },
	secondary = { bg = C.Panel3, text = C.Text, stroke = rgb(120, 130, 175) },
	success = { bg = C.Success, text = rgb(6, 34, 16), stroke = rgb(170, 255, 200) },
	danger = { bg = C.Danger, text = C.White, stroke = rgb(255, 170, 170) },
	blue = { bg = C.Accent2, text = rgb(4, 24, 40), stroke = rgb(170, 235, 255) },
	purple = { bg = C.Purple, text = C.White, stroke = rgb(210, 180, 255) },
	ghost = { bg = C.Panel2, text = C.SubText, stroke = rgb(90, 100, 140) },
	dark = { bg = rgb(16, 18, 28), text = C.Text, stroke = rgb(80, 90, 130) },
}
Kit.Styles = STYLES

local function styleButton(b: GuiObject, st)
	if b:IsA("TextButton") then
		b.TextColor3 = st.text
	end
	local g = b:FindFirstChild("Depth")
	if g then
		g:Destroy()
	end
	local grad = Kit.Depth(b, st.bg, 1)
	grad.Name = "Depth"
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = st.stroke
	end
end

-- Hover / press animation for any clickable GuiButton
function Kit.Clickable(b: GuiButton, onClick: (() -> ())?, sound: boolean?)
	local scale = b:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = b })
	local stroke = b:FindFirstChildOfClass("UIStroke")
	local baseT = if stroke then stroke.Transparency else 0
	local hovered = false
	b.MouseEnter:Connect(function()
		hovered = true
		Kit.Tween(scale, 0.12, { Scale = 1.035 })
		if stroke then
			Kit.Tween(stroke, 0.12, { Transparency = math.max(0, baseT - 0.4) })
		end
	end)
	b.MouseLeave:Connect(function()
		hovered = false
		Kit.Tween(scale, 0.15, { Scale = 1 })
		if stroke then
			Kit.Tween(stroke, 0.15, { Transparency = baseT })
		end
	end)
	b.MouseButton1Down:Connect(function()
		Kit.Tween(scale, 0.06, { Scale = 0.965 })
	end)
	b.MouseButton1Up:Connect(function()
		Kit.Tween(scale, 0.1, { Scale = if hovered then 1.035 else 1 })
	end)
	-- touch has no hover (MouseLeave never comes): always spring back when the finger
	-- lifts, even if it slid off the button first
	b.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then
			hovered = false
			Kit.Tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
			if stroke then
				Kit.Tween(stroke, 0.12, { Transparency = baseT })
			end
		end
	end)
	if onClick then
		b.Activated:Connect(function()
			if sound ~= false then
				Fx.Play("Click", 0.35)
			end
			onClick()
		end)
	end
end

function Kit.Button(parent: Instance, text: string, style: string?, onClick: (() -> ())?, props: { [string]: any }?): TextButton
	local st = STYLES[style or "secondary"] or STYLES.secondary
	local b = Kit.new("TextButton", {
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = text,
		Font = Kit.Fonts.Bold,
		TextSize = 18,
		Size = UDim2.fromOffset(160, 44),
		RichText = true,
		Parent = parent,
	})
	Kit.Corner(b, 12)
	Kit.Stroke(b, st.stroke, 1.4, 0.55)
	styleButton(b, st)
	apply(b, props)
	Kit.Clickable(b, onClick)
	return b
end

function Kit.SetButtonStyle(b: GuiObject, style: string)
	styleButton(b, STYLES[style] or STYLES.secondary)
end

function Kit.ScrollList(parent: Instance, props: { [string]: any }?, padding: number?): ScrollingFrame
	local s = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Stroke,
		ScrollBarImageTransparency = 0.2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	apply(s, props)
	Kit.List(s, Enum.FillDirection.Vertical, padding or 8)
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 2), Parent = s })
	return s
end

function Kit.ScrollGrid(parent: Instance, cell: UDim2, padding: number?, props: { [string]: any }?): ScrollingFrame
	local s = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	apply(s, props)
	Kit.Grid(s, cell, padding)
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = s })
	return s
end

-- Pill tabs. Returns (bar, select(key))
function Kit.Tabs(parent: Instance, tabs: { { key: string, text: string } }, onSelect: (string) -> (), props: { [string]: any }?): (Frame, (string) -> ())
	local bar = Kit.new("Frame", { BackgroundColor3 = rgb(12, 14, 24), BackgroundTransparency = 0.2, Size = UDim2.new(0, 0, 0, 44), AutomaticSize = Enum.AutomaticSize.X, Parent = parent })
	Kit.Round(bar)
	Kit.Padding(bar, 4, 4)
	apply(bar, props)
	Kit.List(bar, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local buttons = {}
	local function select(key: string)
		for k, b in buttons do
			local on = k == key
			Kit.Tween(b, 0.15, { BackgroundTransparency = if on then 0 else 1, TextColor3 = if on then rgb(28, 18, 4) else C.SubText })
		end
		onSelect(key)
	end
	for i, t in tabs do
		local b = Kit.new("TextButton", {
			AutoButtonColor = false,
			Text = t.text,
			Font = Kit.Fonts.Bold,
			TextSize = 15,
			TextColor3 = C.SubText,
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
			Parent = bar,
		})
		Kit.Round(b)
		Kit.Padding(b, 16, 0)
		Kit.Clickable(b, function()
			select(t.key)
		end)
		buttons[t.key] = b
	end
	return bar, select
end

-- Segmented control: options = { {key, text} }. Returns (frame, set(key))
function Kit.Segmented(parent: Instance, options: { { any } }, current: any, onChange: (any) -> (), props: { [string]: any }?): (Frame, (any) -> ())
	local f = Kit.new("Frame", { BackgroundColor3 = rgb(12, 14, 24), BackgroundTransparency = 0.1, Size = UDim2.fromOffset(300, 38), Parent = parent })
	Kit.Round(f)
	Kit.Padding(f, 3, 3)
	apply(f, props)
	Kit.List(f, Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local btns = {}
	local n = #options
	local function set(key)
		for k, b in btns do
			local on = k == key
			b.BackgroundTransparency = if on then 0 else 1
			b.TextColor3 = if on then rgb(28, 18, 4) else C.SubText
		end
	end
	for i, o in options do
		local b = Kit.new("TextButton", {
			AutoButtonColor = false,
			Text = o[2],
			Font = Kit.Fonts.Bold,
			TextSize = 13,
			TextColor3 = C.SubText,
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = 1,
			Size = UDim2.new(1 / n, -3 * (n - 1) / n, 1, 0),
			LayoutOrder = i,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = f,
		})
		Kit.Round(b)
		Kit.Clickable(b, function()
			set(o[1])
			onChange(o[1])
		end)
		btns[o[1]] = b
	end
	set(current)
	return f, set
end

-- iOS-style switch. Returns (button, set(bool))
function Kit.Toggle(parent: Instance, value: boolean, onChange: (boolean) -> (), props: { [string]: any }?): (TextButton, (boolean) -> ())
	local b = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.Panel3, Size = UDim2.fromOffset(54, 30), Parent = parent })
	Kit.Round(b)
	apply(b, props)
	local knob = Kit.new("Frame", { BackgroundColor3 = C.White, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(22, 22), Parent = b })
	Kit.Round(knob)
	local state = value
	local function set(v: boolean, instant: boolean?)
		state = v
		local t = if instant then 0 else 0.15
		Kit.Tween(b, t, { BackgroundColor3 = if v then C.Success else C.Panel3 })
		Kit.Tween(knob, t, { Position = if v then UDim2.new(1, -26, 0.5, 0) else UDim2.new(0, 4, 0.5, 0) })
	end
	set(value, true)
	b.Activated:Connect(function()
		Fx.Play("Click", 0.3)
		set(not state)
		onChange(state)
	end)
	return b, function(v)
		set(v, true)
	end
end

-- Slider. onChange fires while dragging, onCommit on release. Returns (frame, set(value))
function Kit.Slider(parent: Instance, min: number, max: number, step: number, value: number, onChange: (number) -> (), onCommit: ((number) -> ())?, props: { [string]: any }?): (Frame, (number) -> ())
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 30), Parent = parent })
	apply(f, props)
	local track = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.Panel3, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, -56, 0, 8), Parent = f })
	Kit.Round(track)
	local fill = Kit.new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
	Kit.Round(fill)
	Kit.Gradient(fill, rgb(255, 214, 90), C.Accent, 0)
	local knob = Kit.new("Frame", { BackgroundColor3 = C.White, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(20, 20), ZIndex = 2, Parent = track })
	Kit.Round(knob)
	Kit.Stroke(knob, C.Accent, 3, 0)
	local valueLabel = Kit.Label(f, "", 15, { Font = Kit.Fonts.Bold, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(48, 24), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Accent })
	local cur = value
	local function set(v: number)
		v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
		cur = v
		local a = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		valueLabel.Text = tostring(v)
	end
	set(value)
	local dragging = false
	local function fromX(x: number)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local before = cur
		set(min + a * (max - min))
		if cur ~= before then
			onChange(cur)
		end
	end
	track.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(io.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			fromX(io.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if onCommit then
				onCommit(cur)
			end
		end
	end)
	return f, set
end

function Kit.Chip(parent: Instance, text: string, color: Color3, props: { [string]: any }?): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.8, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Parent = parent })
	Kit.Round(f)
	Kit.Stroke(f, color, 1, 0.4)
	Kit.Padding(f, 9, 0)
	Kit.Label(f, text, 11, { Font = Kit.Fonts.Title, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, TextColor3 = color:Lerp(C.White, 0.35) })
	apply(f, props)
	return f
end

-- Corner ribbon like "BEST VALUE"
function Kit.Ribbon(parent: Instance, text: string, color: Color3, textColor: Color3?): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = color, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, -10), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5, Parent = parent })
	Kit.Round(f)
	Kit.Depth(f, color, 1)
	Kit.Padding(f, 10, 0)
	Kit.Label(f, text, 11, { Font = Kit.Fonts.Title, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, TextColor3 = textColor or C.White, ZIndex = 6 })
	return f
end

function Kit.Bar(parent: Instance, frac: number, color: Color3, props: { [string]: any }?): (Frame, Frame)
	local bg = Kit.new("Frame", { BackgroundColor3 = rgb(10, 12, 20), BackgroundTransparency = 0.1, Size = UDim2.new(1, 0, 0, 8), Parent = parent })
	Kit.Round(bg)
	apply(bg, props)
	local fill = Kit.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1), Parent = bg })
	Kit.Round(fill)
	Kit.Gradient(fill, color:Lerp(C.White, 0.3), color, 0)
	return bg, fill
end

---------------------------------------------------------------------------
-- Drawn icons (no image assets needed)
---------------------------------------------------------------------------
function Kit.Coin(parent: Instance, size: number, props: { [string]: any }?): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = rgb(255, 205, 60), Size = UDim2.fromOffset(size, size), Parent = parent })
	Kit.Round(f)
	Kit.Gradient(f, rgb(255, 232, 120), rgb(230, 140, 20), 45)
	Kit.Stroke(f, rgb(170, 98, 8), math.max(1, size * 0.08), 0)
	local inner = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.66), Parent = f })
	Kit.Round(inner)
	Kit.Stroke(inner, rgb(255, 245, 190), math.max(1, size * 0.05), 0.2)
	Kit.Label(f, "G", size * 0.5, { Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = rgb(150, 84, 4) })
	apply(f, props)
	return f
end

function Kit.Robux(parent: Instance, size: number, color: Color3?, props: { [string]: any }?): Frame
	local col = color or C.White
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent })
	local outer = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.84, 0.84), Rotation = 0, Parent = f })
	Kit.Corner(outer, math.floor(size * 0.24))
	Kit.Stroke(outer, col, math.max(1.5, size * 0.12), 0)
	local inner = Kit.new("Frame", { BackgroundColor3 = col, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.3, 0.3), Parent = f })
	Kit.Corner(inner, 2)
	apply(f, props)
	return f
end

-- Price row: [Robux icon] 1,234
function Kit.RobuxPrice(parent: Instance, amount: number, textSize: number, color: Color3?, props: { [string]: any }?): (Frame, TextLabel)
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, textSize + 6), AutomaticSize = Enum.AutomaticSize.X, Parent = parent })
	Kit.List(f, Enum.FillDirection.Horizontal, math.floor(textSize * 0.3), Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	Kit.Robux(f, textSize * 0.95, color, { LayoutOrder = 1 })
	local s = tostring(math.floor(amount))
	local formatted, k = s, 0
	repeat
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	local l = Kit.Label(f, formatted, textSize, { Font = Kit.Fonts.Title, Size = UDim2.fromOffset(0, textSize + 6), AutomaticSize = Enum.AutomaticSize.X, TextColor3 = color or C.White, LayoutOrder = 2 })
	apply(f, props)
	return f, l
end

-- Ranked emblem: diamond with the division numeral (or a star for champion)
function Kit.TierBadge(parent: Instance, tier, size: number, division: string?, props: { [string]: any }?): Frame
	local col = tier.Color
	-- just the diamond (no round glow behind it)
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent })
	local outer = Kit.new("Frame", { BackgroundColor3 = col, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7), Rotation = 45, Parent = f })
	Kit.Corner(outer, math.floor(size * 0.1))
	Kit.Gradient(outer, col:Lerp(C.White, 0.45), col:Lerp(Color3.new(0, 0, 0), 0.35), 0)
	Kit.Stroke(outer, col:Lerp(C.White, 0.6), math.max(1, size * 0.035), 0)
	local inner = Kit.new("Frame", { BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.55), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.46, 0.46), Rotation = 45, Parent = f })
	Kit.Corner(inner, math.floor(size * 0.06))
	Kit.Stroke(inner, col:Lerp(C.White, 0.25), math.max(1, size * 0.02), 0.2)
	local txt = if tier.Name == "Champion" then "★" else (division or "")
	Kit.Label(f, txt, size * (if #txt > 2 then 0.17 else 0.22), { Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = col:Lerp(C.White, 0.7) })
	apply(f, props)
	return f
end

-- Player headshot (AI / unknown players get initials)
function Kit.Avatar(parent: Instance, userId: number?, size: number, fallbackName: string?, ring: Color3?, props: { [string]: any }?): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = C.Panel3, Size = UDim2.fromOffset(size, size), Parent = parent })
	Kit.Round(f)
	Kit.Stroke(f, ring or rgb(255, 255, 255), math.max(1.5, size * 0.05), if ring then 0 else 0.8)
	if userId and userId > 0 then
		local img = Kit.new("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId),
			Parent = f,
		})
		Kit.Round(img)
	else
		local name = fallbackName or "?"
		local initials = ""
		for word in string.gmatch(name, "%a+") do
			initials ..= string.upper(string.sub(word, 1, 1))
			if #initials >= 2 then
				break
			end
		end
		Kit.Gradient(f, rgb(70, 80, 120), rgb(35, 40, 62), 45)
		Kit.Label(f, if initials == "" then "?" else initials, size * 0.36, { Font = Kit.Fonts.Title, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	end
	apply(f, props)
	return f
end

-- Rounded icon tile with an emoji / glyph
function Kit.IconTile(parent: Instance, glyph: string, size: number, color: Color3, props: { [string]: any }?): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(size, size), Parent = parent })
	Kit.Corner(f, math.floor(size * 0.28))
	Kit.Gradient(f, color:Lerp(C.White, 0.3), color:Lerp(Color3.new(0, 0, 0), 0.25), 45)
	Kit.Stroke(f, color:Lerp(C.White, 0.5), 1, 0.5)
	Kit.Label(f, glyph, size * 0.52, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	apply(f, props)
	return f
end

---------------------------------------------------------------------------
-- Overlays: toasts, modals, loading
---------------------------------------------------------------------------
local overlayGui, overlayRoot = Kit.Screen("GoTrackOverlay", 50)
local toastHolder = Kit.new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(560, 400),
	Parent = overlayRoot,
})
Kit.List(toastHolder, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
Kit.OverlayRoot = overlayRoot
Kit.OverlayGui = overlayGui
Kit.BindInset(function(top)
	toastHolder.Position = UDim2.new(0.5, 0, 0, top + 12)
end)

function Kit.Toast(msg: string, kind: string?)
	local color = if kind == "success" then C.Success elseif kind == "error" then C.Danger elseif kind == "warn" then C.Warn else C.Accent2
	local f = Kit.new("Frame", { BackgroundColor3 = rgb(16, 18, 30), BackgroundTransparency = 0.04, Size = UDim2.fromOffset(0, 48), AutomaticSize = Enum.AutomaticSize.X, Parent = toastHolder })
	Kit.Corner(f, 14)
	local stroke = Kit.Stroke(f, color, 1.5, 0.3)
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 18), Parent = f })
	local bar = Kit.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Position = UDim2.new(0, -14, 0.5, -11), Size = UDim2.fromOffset(4, 22), Parent = f })
	Kit.Corner(bar, 2)
	local l = Kit.Label(f, msg, 16, { Size = UDim2.fromOffset(0, 48), AutomaticSize = Enum.AutomaticSize.X, Font = Kit.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Center })
	local sc = Kit.new("UIScale", { Scale = 0.7, Parent = f })
	Kit.Tween(sc, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3.4, function()
		Kit.Tween(f, 0.3, { BackgroundTransparency = 1 })
		Kit.Tween(l, 0.3, { TextTransparency = 1 })
		Kit.Tween(stroke, 0.3, { Transparency = 1 })
		Kit.Tween(bar, 0.3, { BackgroundTransparency = 1 })
		task.wait(0.35)
		f:Destroy()
	end)
end

local function modalFrame(title: string, width: number?, height: number?): (Frame, Frame, () -> ())
	local dim = Kit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = rgb(4, 5, 10),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = overlayRoot,
	})
	Kit.Tween(dim, 0.2, { BackgroundTransparency = 0.4 })
	local box = Kit.Panel(dim, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width or 480, height or 0),
		AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		ZIndex = 11,
	})
	Kit.Padding(box, 24, 22)
	Kit.List(box, Enum.FillDirection.Vertical, 14)
	local accent = Kit.new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromOffset(44, 4), LayoutOrder = -1, ZIndex = 12, Parent = box })
	Kit.Round(accent)
	Kit.Label(box, title, 24, { Font = Kit.Fonts.Title, LayoutOrder = 0, ZIndex = 12, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
	local sc = Kit.new("UIScale", { Scale = 0.88, Parent = box })
	Kit.Tween(sc, 0.24, { Scale = 1 }, Enum.EasingStyle.Back)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		dim:Destroy()
	end
	return box, dim, close
end
Kit.ModalFrame = modalFrame

-- Buttons: { {text, style, fn} }. fn may return true to keep the modal open.
function Kit.Modal(title: string, body: string, buttons: { { any } }, width: number?)
	local box, _, close = modalFrame(title, width)
	local l = Kit.Label(box, body, 16, { TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = C.SubText, LayoutOrder = 1, ZIndex = 12, Font = Kit.Fonts.Medium, TextYAlignment = Enum.TextYAlignment.Top })
	l.Size = UDim2.new(1, 0, 0, 20)
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 2, ZIndex = 12, Parent = box })
	Kit.List(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	for i, b in buttons do
		Kit.Button(row, b[1], b[2], function()
			local keep = if b[3] then b[3]() else false
			if not keep then
				close()
			end
		end, { LayoutOrder = i, ZIndex = 13, Size = UDim2.fromOffset(math.max(120, #b[1] * 10 + 36), 46) })
	end
	return close
end

-- Text input modal
function Kit.Prompt(title: string, placeholder: string, default: string?, onSubmit: (string) -> (), maxLen: number?)
	local box, _, close = modalFrame(title, 460)
	local tb = Kit.new("TextBox", {
		BackgroundColor3 = rgb(12, 14, 24),
		Text = default or "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = C.Muted,
		TextColor3 = C.Text,
		Font = Kit.Fonts.Bold,
		TextSize = 20,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, 50),
		LayoutOrder = 1,
		ZIndex = 12,
		Parent = box,
	})
	Kit.Corner(tb, 12)
	Kit.Stroke(tb, C.Accent, 1.5, 0.4)
	Kit.Padding(tb, 14, 0)
	if maxLen then
		tb:GetPropertyChangedSignal("Text"):Connect(function()
			if #tb.Text > maxLen then
				tb.Text = string.sub(tb.Text, 1, maxLen)
			end
		end)
	end
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 2, ZIndex = 12, Parent = box })
	Kit.List(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)
	Kit.Button(row, "Cancel", "secondary", close, { LayoutOrder = 1, ZIndex = 13, Size = UDim2.fromOffset(120, 46) })
	Kit.Button(row, "OK", "primary", function()
		local text = tb.Text
		close()
		onSubmit(text)
	end, { LayoutOrder = 2, ZIndex = 13, Size = UDim2.fromOffset(120, 46) })
	task.defer(function()
		tb:CaptureFocus()
	end)
end

-- Full-screen loading curtain with animated stripes and tips
local TIPS = {
	"Brake in a straight line, then turn in - smooth is fast.",
	"Follow the racing line: green = flat out, red = brake!",
	"Hitting walls breaks your wings. Press R to repair (costs time).",
	"Stay right behind a rival to catch the slipstream.",
	"Flat out on a straight, your rear wing opens (straight mode) for extra top speed.",
	"Press C to switch between cockpit, chase and TV cameras.",
	"Ranked races use a map vote - pick your favourite circuit!",
	"Time Trial ghosts show you exactly where you lose time.",
	"Grass and gravel slow you down a lot - keep it on the tarmac.",
}
local curtain: Frame? = nil
local curtainConn = nil
-- text = big line (e.g. "🇨🇳  Dragon City Circuit"), detail = small line under it,
-- heading = small caps label above it (default "LOADING")
function Kit.Loading(show: boolean, text: string?, detail: string?, heading: string?)
	if show then
		if not curtain then
			local f = Kit.new("Frame", { BackgroundColor3 = C.Bg, Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = overlayRoot })
			Kit.Gradient(f, rgb(24, 28, 52), rgb(8, 9, 16), 90)
			local stripes = Kit.new("Frame", { Name = "Stripes", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 40, Parent = f })
			for k = 0, 5 do
				local s = Kit.new("Frame", {
					BackgroundColor3 = if k % 2 == 0 then C.Accent else C.Red,
					BackgroundTransparency = 0.88,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.1 + k * 0.18, 0, 0.5, 0),
					Size = UDim2.new(0, 60, 2, 0),
					Rotation = 25,
					ZIndex = 40,
					Parent = stripes,
				})
				s:SetAttribute("Base", 0.1 + k * 0.18)
			end
			Kit.Logo(f, 92, { Align = "center", Props = { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.33), ZIndex = 41 } })
			-- what is loading: small caps heading, big name, detail line
			local card = Kit.new("Frame", { Name = "Card", BackgroundColor3 = rgb(12, 14, 26), BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(620, 150), ZIndex = 41, Parent = f })
			Kit.Corner(card, 20)
			Kit.new("UIStroke", { Color = C.Accent, Thickness = 1.5, Transparency = 0.6, Parent = card })
			Kit.new("TextLabel", { Name = "Head", BackgroundTransparency = 1, Text = "LOADING", FontFace = Kit.Faces.Heavy, TextSize = 15, TextColor3 = C.Accent, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 18), ZIndex = 42, Parent = card })
			Kit.new("TextLabel", { Name = "Status", BackgroundTransparency = 1, Text = "", FontFace = Kit.Faces.Sub, TextSize = 32, TextColor3 = C.Text, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(20, 40), Size = UDim2.new(1, -40, 0, 40), ZIndex = 42, Parent = card })
			Kit.new("TextLabel", { Name = "Detail", BackgroundTransparency = 1, Text = "", FontFace = Kit.Faces.Semi, TextSize = 16, TextColor3 = C.SubText, Position = UDim2.fromOffset(20, 82), Size = UDim2.new(1, -40, 0, 20), ZIndex = 42, Parent = card })
			local barBg = Kit.new("Frame", { Name = "BarBg", BackgroundColor3 = rgb(40, 45, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118), Size = UDim2.new(1, -80, 0, 8), ClipsDescendants = true, ZIndex = 42, Parent = card })
			Kit.Round(barBg)
			local bar = Kit.new("Frame", { Name = "Bar", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.35, 1), ZIndex = 43, Parent = barBg })
			Kit.Round(bar)
			Kit.Gradient(bar, C.Accent, C.Red, 0)
			-- tip pill
			local tip = Kit.new("Frame", { Name = "TipPill", BackgroundColor3 = rgb(12, 14, 26), BackgroundTransparency = 0.3, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 41, Parent = f })
			Kit.Round(tip)
			Kit.Padding(tip, 20, 0)
			Kit.new("TextLabel", { Name = "Tip", BackgroundTransparency = 1, Text = "", FontFace = Kit.Faces.Semi, TextSize = 17, TextColor3 = rgb(215, 220, 240), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), RichText = true, ZIndex = 42, Parent = tip })
			curtain = f
			local t0 = os.clock()
			if curtainConn then
				curtainConn:Disconnect()
			end
			curtainConn =game:GetService("RunService").RenderStepped:Connect(function()
				local t = os.clock() - t0
				bar.Position = UDim2.fromScale(((t * 0.7) % 1.3) - 0.3, 0)
				for _, s in stripes:GetChildren() do
					local base = s:GetAttribute("Base") or 0
					s.Position = UDim2.new(((base + t * 0.05) % 1.2) - 0.1, 0, 0.5, 0)
				end
			end)
		end
		local cf = curtain :: Frame
		local card = cf:FindFirstChild("Card") :: Frame
		;(card:FindFirstChild("Status") :: TextLabel).Text = text or "Loading..."
		;(card:FindFirstChild("Detail") :: TextLabel).Text = detail or ""
		;(card:FindFirstChild("Head") :: TextLabel).Text = heading or "LOADING"
		;(cf:FindFirstChild("TipPill"):FindFirstChild("Tip") :: TextLabel).Text = "<font color='#FFB81C'><b>TIP</b></font>   " .. TIPS[math.random(1, #TIPS)]
		cf.Visible = true
		cf.BackgroundTransparency = 0
	elseif curtain then
		local f = curtain
		curtain = nil
		for _, d in f:GetDescendants() do
			if d:IsA("TextLabel") then
				Kit.Tween(d, 0.35, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				Kit.Tween(d, 0.35, { Transparency = 1 })
			elseif d:IsA("Frame") then
				Kit.Tween(d, 0.35, { BackgroundTransparency = 1 })
			end
		end
		Kit.Tween(f, 0.35, { BackgroundTransparency = 1 })
		task.delay(0.4, function()
			if curtainConn and not curtain then
				curtainConn:Disconnect()
				curtainConn = nil
			end
			f:Destroy()
		end)
	end
end

-- Formats 12345 -> "12,345"
function Kit.Comma(n: number): string
	local s = tostring(math.floor(n))
	local formatted, k = s, 0
	repeat
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

return Kit
