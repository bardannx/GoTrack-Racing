-- Prints every circuit's full centre line (x, z, height, speed) and road width as JSON.
-- Read by twistify.py.
--   luau dump2.luau > dense.json

local Circuits = require("./Circuits")
local Track = require("./Track")
local out = {}
for _, c in Circuits.List do
	local t = Track.Build(c)
	local xs, zs, ys, vs = {}, {}, {}, {}
	for i = 1, t.N do
		table.insert(xs, string.format("%.1f", t.X[i]))
		table.insert(zs, string.format("%.1f", t.Z[i]))
		table.insert(ys, string.format("%.1f", t.Y[i]))
		table.insert(vs, string.format("%.0f", t.V[i]))
	end
	table.insert(
		out,
		string.format(
			'"%s":{"x":[%s],"z":[%s],"y":[%s],"v":[%s],"w":%d}',
			c.Id,
			table.concat(xs, ","),
			table.concat(zs, ","),
			table.concat(ys, ","),
			table.concat(vs, ","),
			t.Width
		)
	)
end
print("{" .. table.concat(out, ",") .. "}")
