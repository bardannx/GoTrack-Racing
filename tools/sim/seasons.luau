--!nocheck
-- Prints the automatic ranked season calendar (Config.SeasonAt).
local Env = require("./env")
local Config = Env.Require("src/shared/Config")
for _, t in { os.time(), 1798761539, 1798761540, 1798761540 + 70 * 86400 - 1, 1798761540 + 70 * 86400, 1830000000 } do
	local s = Config.SeasonAt(t)
	print(os.date("!%Y-%m-%d %H:%M", t), "->", s.Name, "ends", os.date("!%Y-%m-%d %H:%M", s.EndsAt))
end
print("now:", Config.Ranked.Season.Name, os.date("!%Y-%m-%d", Config.Ranked.Season.EndsAt))
