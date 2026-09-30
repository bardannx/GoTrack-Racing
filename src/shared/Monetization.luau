--!nonstrict
-- Game passes and developer products, as data. The logic that grants them lives in
-- server/MonetizationService.luau.
--
-- To add one: create it in the Creator Dashboard, paste its ID into `Id` (0 means "not
-- created yet": the shop says "not on sale yet"), and set the same `Price` as the
-- dashboard. The shop shows the live dashboard price; `Price` is only a fallback.

local M = {}

-- 11 passes, each worth its price on its own. (Small one-item passes were folded into VIP,
-- the Pro Racer Pack and the FX Pack; basic cosmetics are bought with coins instead.)
-- Nothing here changes car speed or handling.
M.Passes = {
	{
		Key = "Ultimate",
		Id = 2002544633,
		Name = "Ultimate Bundle",
		Price = 3999,
		Icon = "💎",
		Color = Color3.fromRGB(170, 90, 255),
		Description = "EVERY game pass in GoTrack Racing, forever. Best value!",
		Perks = {
			"All 10 other passes, forever",
			"Every car, effect & perk in the game",
			"Ultimate title & 💎 chat tag",
			"Save 790+ R$ vs buying separately",
		},
	},
	{
		Key = "VIP",
		Id = 2002196624,
		Name = "VIP",
		Price = 300,
		Icon = "👑",
		Color = Color3.fromRGB(255, 200, 40),
		Description = "Earn faster and race in style.",
		Perks = {
			"1.5x coins (stacks with 2x Coins)",
			"2x daily rewards",
			"[👑 VIP] chat tag + VIP title",
			"Rainbow paint, VIP Gold & Platinum paints",
			"Chrome & Gold helmets, iridium visors, gold tyres",
		},
	},
	{
		Key = "DoubleCoins",
		Id = 2003264417,
		Name = "2x Coins",
		Price = 299,
		Icon = "💰",
		Color = Color3.fromRGB(255, 215, 60),
		Description = "Double every coin you earn, forever.",
		Perks = {
			"2x coins from races & time trials",
			"Stacks with VIP and Coin Boosts",
			"Unlock the Garage twice as fast",
		},
	},
	{
		Key = "StarterPack",
		Id = 2003366409,
		Name = "Starter Pack",
		Price = 99,
		Icon = "🎁",
		Color = Color3.fromRGB(90, 220, 120),
		Description = "The perfect start: coins and an exclusive look.",
		Perks = { "+1,500 coins (once)", "Rookie Green paint & Rookie title", "Rookie helmet" },
	},
	{
		Key = "ProRacer",
		Id = 2001410699,
		Name = "Pro Racer Pack",
		Price = 299,
		Icon = "📊",
		Color = Color3.fromRGB(80, 200, 160),
		Description = "The tools the fastest drivers use.",
		Perks = {
			"Pro telemetry HUD: live delta, sectors, gaps",
			"Chase up to 5 Time Trial ghosts at once",
			"Pick your own race number (1-99)",
			"Pro title",
		},
	},
	{
		Key = "FXPack",
		Id = 2003126442,
		Name = "FX Pack",
		Price = 299,
		Icon = "🌈",
		Color = Color3.fromRGB(255, 90, 200),
		Description = "Every effect: be seen on every straight.",
		Perks = {
			"All underglow colours",
			"Rainbow, Fire, Lightning, Toxic & Galaxy trails",
			"Exhaust flames + gold & rainbow tyre smoke",
			"Fireworks, Lightning & Gold Rain finishes",
			"Neon helmet & neon tyres",
		},
	},
	{
		Key = "PrivateRaces",
		Id = 2003198441,
		Name = "Private Races",
		Price = 299,
		Icon = "🔒",
		Color = Color3.fromRGB(90, 140, 255),
		Description = "Host private races for you and your friends.",
		Perks = {
			"Create friends-only races on any circuit",
			"Choose the lap count",
			"Hidden from the public lobby list",
		},
	},
	{
		Key = "PremiumTeam",
		Id = 1999329787,
		Name = "Premium Team Pack",
		Price = 799,
		Icon = "🏎️",
		Color = Color3.fromRGB(255, 80, 80),
		Description = "Factory-team cars, rims and liveries.",
		Perks = {
			"Stealth, Vortex & Apex chassis",
			"Blade & Mesh rims",
			"Flames & Carbon liveries",
			"Chrome & Carbon paints",
		},
	},
	{
		Key = "LegendaryCars",
		Id = 2003552389,
		Name = "Legendary Car Pack",
		Price = 1499,
		Icon = "🏆",
		Color = Color3.fromRGB(255, 140, 30),
		Description = "The rarest race cars in GoTrack with glowing neon details.",
		Perks = { "Nova, Viper & Aurora chassis", "Glowing neon body lines", "Legend title" },
	},
	{
		Key = "NeonCollection",
		Id = 2002022644,
		Name = "Neon Night Collection",
		Price = 449,
		Icon = "🌃",
		Color = Color3.fromRGB(80, 90, 255),
		Description = "Glow-in-the-dark cosmetics built for night races.",
		Perks = { "Neon Racer chassis", "3 electric neon paints", "Circuit-lines livery", "Neon rims" },
	},
	{
		Key = "HeritageCollection",
		Id = 2002142631,
		Name = "Heritage Collection",
		Price = 449,
		Icon = "🏁",
		Color = Color3.fromRGB(200, 160, 90),
		Description = "Classic cars and liveries from racing's golden eras.",
		Perks = {
			"Retro 70s & Retro 90s chassis",
			"Racing Green, Papaya & Heritage Gold paints",
			"Retro stripes livery",
			"Gold rims",
		},
	},
}

M.Products = {
	{
		Key = "Coins500",
		Id = 3715631892,
		Name = "Pouch of Coins",
		Price = 49,
		Icon = "🪙",
		Coins = 500,
		Description = "500 coins",
	},
	{
		Key = "Coins1500",
		Id = 3715631944,
		Name = "Bag of Coins",
		Price = 129,
		Icon = "💰",
		Coins = 1500,
		Description = "1,500 coins",
	},
	{
		Key = "Coins4000",
		Id = 3715632010,
		Name = "Chest of Coins",
		Price = 299,
		Icon = "🧰",
		Coins = 4000,
		Description = "4,000 coins",
	},
	{
		Key = "Coins10000",
		Id = 3715632083,
		Name = "Vault of Coins",
		Price = 649,
		Icon = "🏦",
		Coins = 10000,
		Description = "10,000 coins",
	},
	{
		Key = "Coins30000",
		Id = 3715632144,
		Name = "Mountain of Coins",
		Price = 1499,
		Icon = "⛰️",
		Coins = 30000,
		Description = "30,000 coins - best value",
	},
	{
		Key = "CoinBoost",
		Id = 3715632244,
		Name = "Coin Boost (30 min)",
		Price = 79,
		Icon = "⚡",
		BoostMinutes = 30,
		Description = "2x coins for 30 minutes",
	},
}

-- Lookups by key (used in code) and by Roblox ID (used when a purchase comes in).
M.PassByKey = {}
M.PassById = {}
for _, p in M.Passes do
	M.PassByKey[p.Key] = p
	if p.Id ~= 0 then
		M.PassById[p.Id] = p
	end
end

M.ProductById = {}
M.ProductByKey = {}
for _, p in M.Products do
	M.ProductByKey[p.Key] = p
	if p.Id ~= 0 then
		M.ProductById[p.Id] = p
	end
end

-- What every pass costs bought one by one (the Ultimate Bundle's "save X R$" line).
function M.TotalPassRobux(): number
	local t = 0
	for _, p in M.Passes do
		t += p.Price
	end
	return t
end

return M
