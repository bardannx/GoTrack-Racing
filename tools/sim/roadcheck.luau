--!nocheck
-- Is anything standing on the road? Builds every circuit the way the live game does
-- (world meshes imported, top graphics) and probes the space a car and the chase camera
-- use: the whole road width, from just above the tarmac up to CircuitBuilder.RoadClear
-- studs (roads under a bridge crossing excepted). Every visible or solid part found there
-- is reported with the game code that made it. It also prints how many parts the
-- builder's own safety sweep had to remove ("swept"): the builders should keep that at 0.
--   lune run tools/sim/roadcheck.luau [quality] [id ...] [--parts]
-- Exits with an error when anything is in the way. --parts lists examples of each.
local process = require("@lune/process")
local Env = require("./env")
local Vector3 = require("@lune/roblox").Vector3

local quality, ids, listParts = 4, {}, false
for _, a in process.args do
	if a == "--parts" then
		listParts = true
	elseif tonumber(a) then
		quality = tonumber(a)
	else
		table.insert(ids, a)
	end
end
Env.FakeWorldMeshes()
Env.TrackOrigins = true
local Circuits = Env.Require("src/shared/Circuits")
local CircuitBuilder = Env.Require("src/client/CircuitBuilder")
local CLEAR = CircuitBuilder.RoadClear -- studs above the road kept free
local EDGE = CircuitBuilder.RoadEdge -- kept back from each road edge (kerbs, barriers)
if #ids == 0 then
	for _, c in Circuits.List do
		table.insert(ids, c.Id)
	end
end

-- the first lines of src/ code in a creation traceback, skipping the part-making helpers
local function origin(part)
	local tb = part:GetAttribute("SimOrigin")
	if not tb then
		return "(cloned) " .. part.Name
	end
	local out = {}
	for file, line, fn in string.gmatch(tb, 'src/client/([%w_/]+)%.luau"%]:(%d+) function ([%w_]+)') do
		-- skip the generic part makers, the caller is the interesting bit
		if fn ~= "P" and fn ~= "MESH" and fn ~= "E" and fn ~= "box" and fn ~= "wedge" then
			table.insert(out, file .. ":" .. line .. " " .. fn)
			if #out >= 3 then
				break
			end
		end
	end
	return if #out > 0 then table.concat(out, " < ") else "?"
end

local CELL = 40
local total, totalSwept = 0, 0
for _, id in ids do
	local res = CircuitBuilder.Build(id, quality)
	local t = res.Track
	-- bucket every visible part by the grid cells its bounding box covers
	local grid = {}
	for _, d in res.Folder:GetDescendants() do
		if
			d:IsA("BasePart")
			and (d.Transparency < 0.95 or d.CanCollide)
			and d.Parent
			and d.Parent.Name ~= "Surface"
			and not d:GetAttribute("BridgeRail")
		then
			local cf, s = d.CFrame, d.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local hx = math.abs(r.X) * s.X / 2 + math.abs(u.X) * s.Y / 2 + math.abs(l.X) * s.Z / 2
			local hz = math.abs(r.Z) * s.X / 2 + math.abs(u.Z) * s.Y / 2 + math.abs(l.Z) * s.Z / 2
			local p = cf.Position
			for gx = math.floor((p.X - hx) / CELL), math.floor((p.X + hx) / CELL) do
				for gz = math.floor((p.Z - hz) / CELL), math.floor((p.Z + hz) / CELL) do
					local key = gx .. ":" .. gz
					grid[key] = grid[key] or {}
					table.insert(grid[key], d)
				end
			end
		end
	end
	local found = {} -- part -> { first sample, count }
	local half = t.Width / 2 - EDGE
	local under = CircuitBuilder.UnderBridge(t)
	for i = 1, t.N do
		for lat = -half, half, 3 do
			for _, h in if under[i] then {} else { 1.2, 4, 8, CLEAR - 0.2 } do
				local x = t.X[i] + t.RX[i] * lat
				local z = t.Z[i] + t.RZ[i] * lat
				local y = t.Y[i] + 0.6 + h
				local list = grid[math.floor(x / CELL) .. ":" .. math.floor(z / CELL)]
				if list then
					local pt = Vector3.new(x, y, z)
					for _, d in list do
						local lp = d.CFrame:PointToObjectSpace(pt)
						local s = d.Size
						if math.abs(lp.X) <= s.X / 2 and math.abs(lp.Y) <= s.Y / 2 and math.abs(lp.Z) <= s.Z / 2 then
							local f = found[d]
							if f then
								f.n += 1
							else
								found[d] = { i = i, n = 1 }
							end
						end
					end
				end
			end
		end
	end
	-- group by the code that made the part
	local groups, n = {}, 0
	for d, f in found do
		n += 1
		local key = origin(d)
		local g = groups[key]
		if not g then
			g = { count = 0, examples = {} }
			groups[key] = g
		end
		g.count += 1
		if #g.examples < 3 then
			table.insert(
				g.examples,
				string.format(
					"%s %s %.0fx%.0fx%.0f at sample %d",
					d.ClassName,
					d.Name,
					d.Size.X,
					d.Size.Y,
					d.Size.Z,
					f.i
				)
			)
		end
	end
	total += n
	local swept = res.Stats and res.Stats.RoadCleared or 0
	totalSwept += swept
	print(string.format("%-12s %4d part(s) on the road   (swept %d)", id, n, swept))
	for key, g in groups do
		print(string.format("    %3d  %s", g.count, key))
		if listParts then
			for _, e in g.examples do
				print("           " .. e)
			end
		end
	end
	CircuitBuilder.Clear()
end
print(string.format("safety sweep removed %d part(s) in total", totalSwept))
print(total == 0 and "ROAD CHECK OK" or ("ROAD CHECK: " .. total .. " part(s) on the road"))
if total > 0 then
	process.exit(1)
end
