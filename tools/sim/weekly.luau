--!nocheck
-- Prints the next weeks of automatic content (featured circuit + weekly challenges).
local Env = require("./env")
local Challenges = Env.Require("src/shared/Challenges")
local Circuits = Env.Require("src/shared/Circuits")
local w0 = Challenges.WeekAt(os.time())
local seen = {}
for w = w0, w0 + 34 do
	local f = Challenges.Featured(w)
	seen[f] = (seen[f] or 0) + 1
	if w < w0 + 6 then
		print(os.date("!%Y-%m-%d", Challenges.WeekEnds(w) - 7 * 86400), "featured:", Circuits.ById[f].Name)
		for _, c in Challenges.ForWeek(w) do
			print("    ", c.Text, "->", c.Coins, "coins")
		end
	end
end
local n = 0
for _ in seen do
	n += 1
end
print("distinct featured circuits over 35 weeks:", n)
