--!nocheck
-- Builds circuits outside Studio and reports part counts / errors.
--   lune run tools/sim/maps.luau [quality] [id ...] [--dump]
-- With --dump every part is written to tools/sim/out/<id>.json for tools/sim/render.py.
-- With --meshes the Blender world meshes count as imported (placeholder MeshParts).
-- Run from the repo root.

local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Env = require("./env")

local args = process.args
local quality = 3
local dump = false
local meshes = false
local ids = {}
for _, a in args do
	if a == "--dump" then
		dump = true
	elseif a == "--meshes" then
		meshes = true
	elseif tonumber(a) then
		quality = tonumber(a)
	else
		table.insert(ids, a)
	end
end

if meshes then
	local _, n = Env.FakeWorldMeshes()
	print("world meshes (placeholders):", n)
end
local Circuits = Env.Require("src/shared/Circuits")
local CircuitBuilder = Env.Require("src/client/CircuitBuilder")
if #ids == 0 then
	for _, c in Circuits.List do
		table.insert(ids, c.Id)
	end
end

-- Rounds to 2 decimals for the report.
local function r1(x)
	return math.floor(x * 100 + 0.5) / 100
end

if dump then
	fs.writeDir("tools/sim/out")
end

local failures = 0
for _, id in ids do
	local t0 = os.clock()
	local ok, res = pcall(CircuitBuilder.Build, id, quality)
	if not ok then
		failures += 1
		print(string.format("%-12s BUILD FAILED: %s", id, tostring(res)))
	else
		-- exercise the per-frame systems once (movers, weather follow, ambient)
		local okTick, errTick = pcall(function()
			for _ = 1, 3 do
				Env.RunService.Heartbeat:Fire(0.05)
				Env.RunService.RenderStepped:Fire(0.05)
			end
		end)
		if not okTick then
			failures += 1
			print(string.format("%-12s TICK FAILED: %s", id, tostring(errTick)))
		end
		local counts = {}
		local total, lights, emitters, guis = 0, 0, 0, 0
		local parts = {}
		for _, d in res.Folder:GetDescendants() do
			if d:IsA("BasePart") then
				total += 1
				local top = d.Parent and d.Parent.Name or "?"
				counts[top] = (counts[top] or 0) + 1
				if dump then
					local c = { d.CFrame:GetComponents() }
					for k = 1, 12 do
						c[k] = r1(c[k])
					end
					local col = d.Color
					table.insert(parts, {
						k = d.ClassName,
						s = if d:IsA("Part") then d.Shape.Name else "Block",
						z = { r1(d.Size.X), r1(d.Size.Y), r1(d.Size.Z) },
						c = c,
						col = { math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255) },
						m = d.Material.Name,
						t = r1(d.Transparency),
						e = if d:FindFirstChildOfClass("SpecialMesh") then 1 else nil,
						mesh = if d:IsA("MeshPart") then d.Name else nil,
					})
				end
			elseif d:IsA("Light") then
				lights += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			elseif d:IsA("SurfaceGui") then
				guis += 1
			end
		end
		local stats = res.Stats or {}
		local meshParts = 0
		for _, d in res.Folder:GetDescendants() do
			if d:IsA("MeshPart") then
				meshParts += 1
			end
		end
		print(
			string.format(
				"%-12s parts %6d  meshes %5d  lights %3d  fx %3d  signs %3d  buildings %4s  fill %4s  landmarks %s  %.1fs",
				id,
				total,
				meshParts,
				lights,
				emitters,
				guis,
				tostring(stats.Buildings or "?"),
				tostring(stats.Filled or "?"),
				tostring(stats.Landmarks or "?"),
				os.clock() - t0
			)
		)
		if dump then
			local L = Env.Lighting
			local sky = {
				clock = L.ClockTime,
				ambient = { L.OutdoorAmbient.R, L.OutdoorAmbient.G, L.OutdoorAmbient.B },
				night = res.Theme.Night,
			}
			local atmo = L:FindFirstChild("GoTrackAtmosphere")
			if atmo then
				sky.atmo = { atmo.Color.R, atmo.Color.G, atmo.Color.B }
				sky.density = atmo.Density
			end
			local tr = res.Track
			local centre = {}
			for i = 1, tr.N, 4 do
				table.insert(centre, { r1(tr.X[i]), r1(tr.Y[i]), r1(tr.Z[i]) })
			end
			fs.writeFile(
				"tools/sim/out/" .. id .. ".json",
				serde.encode(
					"json",
					{ id = id, sky = sky, track = centre, width = tr.Width, parts = parts, view = res.ViewAngle }
				)
			)
		end
		CircuitBuilder.Clear()
	end
end
if failures > 0 then
	print(failures .. " circuit(s) failed")
	process.exit(1)
end
