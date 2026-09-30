--!nocheck
-- Serialises a ScreenGui tree (GuiObjects + layout modifiers) to JSON for tools/sim/uirender.py.
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local Dump = {}

local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end
local function col(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function node(inst)
	local n = { k = inst.ClassName, name = inst.Name, kids = {} }
	if inst:IsA("GuiObject") then
		n.pos = udim2(inst.Position)
		n.size = udim2(inst.Size)
		n.anchor = { inst.AnchorPoint.X, inst.AnchorPoint.Y }
		n.bg = col(inst.BackgroundColor3)
		n.bgt = inst.BackgroundTransparency
		n.z = inst.ZIndex
		n.order = inst.LayoutOrder
		n.vis = inst.Visible
		n.auto = inst.AutomaticSize.Name
		n.rot = inst.Rotation
		n.clip = inst.ClipsDescendants
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			n.text = inst.Text
			n.ts = inst.TextSize
			n.tc = col(inst.TextColor3)
			n.tt = inst.TextTransparency
			n.tx = inst.TextXAlignment.Name
			n.ty = inst.TextYAlignment.Name
			n.scaled = inst.TextScaled
			n.wrap = inst.TextWrapped
			local ok, w = pcall(function()
				return inst.FontFace.Weight.Name
			end)
			n.bold = ok and (w == "Bold" or w == "ExtraBold" or w == "Heavy" or w == "Black")
			local okf, f = pcall(function()
				return inst.Font.Name
			end)
			if okf and f and (string.find(f, "Bold") or string.find(f, "Black")) then
				n.bold = true
			end
		end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			n.img = true
		end
	elseif inst:IsA("UICorner") then
		n.r = { inst.CornerRadius.Scale, inst.CornerRadius.Offset }
	elseif inst:IsA("UIStroke") then
		n.c = col(inst.Color)
		n.th = inst.Thickness
		n.t = inst.Transparency
	elseif inst:IsA("UIGradient") then
		local kp = inst.Color.Keypoints
		n.c0 = col(kp[1].Value)
		n.c1 = col(kp[#kp].Value)
		n.rot = inst.Rotation
	elseif inst:IsA("UIListLayout") then
		n.dir = inst.FillDirection.Name
		n.pad = { inst.Padding.Scale, inst.Padding.Offset }
		n.h = inst.HorizontalAlignment.Name
		n.v = inst.VerticalAlignment.Name
	elseif inst:IsA("UIGridLayout") then
		n.cell = udim2(inst.CellSize)
		n.cpad = udim2(inst.CellPadding)
		n.max = inst.FillDirectionMaxCells
	elseif inst:IsA("UIPadding") then
		n.p = { inst.PaddingLeft.Offset, inst.PaddingRight.Offset, inst.PaddingTop.Offset, inst.PaddingBottom.Offset }
	elseif inst:IsA("UIScale") then
		n.scale = inst.Scale
	end
	for _, c in inst:GetChildren() do
		table.insert(n.kids, node(c))
	end
	return n
end

function Dump.Save(inst, path)
	fs.writeFile(path, serde.encode("json", node(inst)))
end

return Dump
