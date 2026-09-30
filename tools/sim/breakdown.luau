--!nocheck
-- Where do a circuit's parts go? Counts by build stage.
--   lune run tools/sim/breakdown.luau <id> [quality]
local process = require("@lune/process")
local Env = require("./env")
local CB = Env.Require("src/client/CircuitBuilder")
local id = process.args[1] or "harbor"
local q = tonumber(process.args[2]) or 2
local stages, last, lastN = {}, "start", 0
local counter = 0
local world = CB.Build(id, q, function(stage)
	-- part count so far = descendants of the circuit folder
	local f = Env.Workspace:FindFirstChild("GoTrackCircuit")
	local n = 0
	if f then
		for _, d in f:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
	end
	table.insert(stages, { last, n - lastN })
	last, lastN = stage, n
end)
local total = 0
for _, d in world.Folder:GetDescendants() do
	if d:IsA("BasePart") then
		total += 1
	end
end
table.insert(stages, { last, total - lastN })
for _, s in stages do
	print(string.format("%-40s %6d", s[1], s[2]))
end
print("total", total, "blocks", world.Stats.Blocks, "buildings", world.Stats.Buildings, "movers", world.Stats.Movers)
