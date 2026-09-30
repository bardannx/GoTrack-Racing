local Circuits = require("./Circuits")
local Track = require("./Track")
local out = {}
for _, c in Circuits.List do
	local t = Track.Build(c)
	local xs, zs, vs = {}, {}, {}
	for i = 1, t.N, 2 do table.insert(xs, string.format("%.0f", t.X[i])); table.insert(zs, string.format("%.0f", t.Z[i])); table.insert(vs, string.format("%.0f", t.V[i])) end
	table.insert(out, string.format('"%s":{"x":[%s],"z":[%s],"v":[%s],"pts":"%s"}', c.Id, table.concat(xs, ","), table.concat(zs, ","), table.concat(vs, ","), c.Points))
end
print("{" .. table.concat(out, ",") .. "}")
