--!nonstrict
-- Places the Blender world meshes from tools/worldgen: skyscrapers, midrises, houses, a
-- mall, trees, rocks, mountains and road cars. The templates are MeshParts in
-- ReplicatedStorage.WorldMeshes (imported from assets/world/GoTrackWorld.fbx, named
-- <design>.<Slot>); centres and sizes come from WorldData. Until they're imported in
-- Studio, Available() is false and the circuit builder keeps its part-built scenery.
--
-- A design is one MeshPart per colour slot, so a whole skyscraper costs ~6 parts instead
-- of 40-80. Colours come from the caller's paint table ({ Slot = { Color3, Material } })
-- over the defaults below. At night WinA / WinB (two random halves of the windows) can
-- glow, and beacons, head lights and tail lights switch to neon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldData = require(Shared.WorldData)

local WM = {}
WM.Data = WorldData
WM.Designs = WorldData.Designs

-- the FBX import turns every mesh 180 degrees around Y; undo it on every placement
local MESH_FIX = CFrame.Angles(0, math.pi, 0)

-- Shorthand for the colour tables below.
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local WARM = rgb(255, 222, 160)
local M = Enum.Material
WM.Default = {
	Glass = { rgb(92, 122, 152), M.Glass },
	Frame = { rgb(214, 218, 226), M.Metal },
	Wall = { rgb(222, 216, 202), M.Concrete },
	Trim = { rgb(238, 234, 226), M.SmoothPlastic },
	WinA = { rgb(58, 78, 102), M.Glass },
	WinB = { rgb(66, 88, 112), M.Glass },
	Roof = { rgb(96, 98, 104), M.Slate },
	Accent = { rgb(200, 60, 40), M.SmoothPlastic },
	Beacon = { rgb(230, 40, 40), M.SmoothPlastic },
	Leaf = { rgb(70, 150, 55), M.LeafyGrass },
	Trunk = { rgb(110, 75, 45), M.Wood },
	Snow = { rgb(245, 248, 255), M.Snow },
	Rock = { rgb(128, 126, 122), M.Rock },
	Base = { rgb(96, 170, 70), M.Grass },
	Band = { rgb(200, 130, 85), M.Sandstone },
	Body = { rgb(200, 40, 40), M.SmoothPlastic },
	Dark = { rgb(26, 26, 28), M.SmoothPlastic },
	Light = { rgb(235, 235, 225), M.SmoothPlastic },
	TailLight = { rgb(170, 20, 20), M.SmoothPlastic },
}
local NIGHT_NEON = { Beacon = rgb(255, 40, 40), Light = rgb(255, 248, 220), TailLight = rgb(230, 20, 20) }

local folder: Folder? = nil
local complete: { [string]: boolean } = {}

-- The imported mesh folder, or nil if it hasn't been imported into this place.
local function templates(): Folder?
	if folder and folder.Parent then
		return folder
	end
	folder = ReplicatedStorage:FindFirstChild("WorldMeshes") :: Folder?
	complete = {}
	return folder
end

-- every mesh of the design is imported
function WM.Has(design: string): boolean
	local f = templates()
	if not f then
		return false
	end
	local cached = complete[design]
	if cached ~= nil then
		return cached
	end
	local d = WorldData.Designs[design]
	local ok = d ~= nil
	if d then
		for _, e in d.Parts do
			if not f:FindFirstChild(e[1]) then
				ok = false
				break
			end
		end
	end
	complete[design] = ok
	return ok
end

-- the world meshes are imported (checked on a few core designs)
function WM.Available(): boolean
	return WM.Has("tower_glass") and WM.Has("tree_oak") and WM.Has("house_gable")
end

-- Footprint (W, D) and height of a design in studs, or nil
function WM.Size(design: string): (number?, number?, number?)
	local d = WorldData.Designs[design]
	if not d then
		return nil
	end
	return d.W, d.D, d.H
end

-- Place a design. cf: its origin on the ground, facade towards -Z. opts:
--   Scale   Vector3 (per axis)          Paint  { Slot = { Color3, Material? } }
--   Night   boolean                     Lit    0..2 window sets glowing at night
--   Shadow  boolean (cast shadows)      Reflect number (glass reflectance)
-- Returns the MeshParts, or nil when the design isn't imported.
function WM.Place(design: string, parent: Instance, cf: CFrame, opts): { MeshPart }?
	if not WM.Has(design) then
		return nil
	end
	opts = opts or {}
	local d = WorldData.Designs[design]
	local f = templates() :: Folder
	local sc = opts.Scale or Vector3.one
	local paint = opts.Paint or {}
	local night = opts.Night == true
	local lit = opts.Lit or 0
	local parts = table.create(#d.Parts)
	for _, e in d.Parts do
		local name, slot, c, s = e[1], e[2], e[3], e[4]
		local t = f:FindFirstChild(name)
		local p = t:Clone() :: MeshPart
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = opts.Shadow == true
		p.Transparency = 0
		p.Size = s * sc
		p.CFrame = cf * CFrame.new(c * sc) * MESH_FIX
		local look = paint[slot] or WM.Default[slot] or WM.Default.Trim
		local color, material = look[1], look[2] or M.SmoothPlastic
		if night and NIGHT_NEON[slot] then
			color, material = NIGHT_NEON[slot], M.Neon
		elseif night and ((slot == "WinA" and lit >= 1) or (slot == "WinB" and lit >= 2)) then
			color, material = if look[3] then look[3] else WARM, M.Neon
		end
		p.Color = color
		p.Material = material
		if material == M.Glass then
			p.Reflectance = opts.Reflect or 0.12
		end
		p.Parent = parent
		table.insert(parts, p)
	end
	return parts
end

return WM
