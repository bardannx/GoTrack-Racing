local Circuits = require("./Circuits")
local Track = require("./Track")
for _, c in Circuits.List do
	local t = Track.Build(c)
	local worstBack, worstFwd = 0, 0
	for i = 1, t.N do
		local s = t.S[i]
		local k = math.abs(t.K[i])
		if s > t.Length - 230 then worstBack = math.max(worstBack, k) end
		if s < 160 then worstFwd = math.max(worstFwd, k) end
	end
	local rb = if worstBack > 0 then 1 / worstBack else 1e9
	local rf = if worstFwd > 0 then 1 / worstFwd else 1e9
	if rb < 350 or rf < 350 then
		print(string.format("%-12s gridR=%d startR=%d", c.Id, rb, rf))
	end
end
print("checked")
