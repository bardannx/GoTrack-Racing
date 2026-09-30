--!nonstrict
-- Every car cosmetic in the game, as data. An item belongs to a category (paint, rims,
-- helmet, trail...) and is unlocked one of four ways:
--   Price > 0     bought with coins
--   Pass = key    comes with that game pass (Monetization.luau)
--   RankTier = n  earned by reaching that ranked tier this season
--   Price = 0     free for everyone
-- A car is a table of slot -> item id (C.Slots). The server runs every car through
-- Sanitize before saving or showing it, so a locked or unknown item can never be used.

local C = {}

-- Equip slot -> item category
C.Slots = {
	Body = "Body",
	Primary = "Paint",
	Secondary = "Paint",
	Accent = "Paint",
	RimColor = "Paint",
	Helmet = "Helmet",
	Visor = "Visor",
	Rims = "Rims",
	Tyre = "Tyre",
	Pattern = "Pattern",
	TyreSmoke = "TyreSmoke",
	Underglow = "Underglow",
	Trail = "Trail",
	Flames = "Flames",
	Celebration = "Celebration",
	Title = "Title",
}

C.SlotOrder = {
	"Body",
	"Primary",
	"Secondary",
	"Accent",
	"Pattern",
	"Helmet",
	"Visor",
	"Rims",
	"RimColor",
	"Tyre",
	"TyreSmoke",
	"Underglow",
	"Trail",
	"Flames",
	"Celebration",
	"Title",
}

C.SlotLabels = {
	Body = "Chassis",
	Primary = "Main Color",
	Secondary = "Second Color",
	Accent = "Wing Color",
	RimColor = "Rim Color",
	Helmet = "Helmet",
	Visor = "Visor",
	Rims = "Rims",
	Tyre = "Tyres",
	Pattern = "Livery",
	TyreSmoke = "Tyre Smoke",
	Underglow = "Underglow",
	Trail = "Trail",
	Flames = "Exhaust Flames",
	Celebration = "Celebration",
	Title = "Title",
}

-- Each chassis comes with its own factory colours. Equipping a chassis applies them (and unlocks
-- those paints for free); players can then customise the car however they like.
C.BodyLivery = {
	gt1 = { Primary = "paint_red", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_stripe" },
	aeros = { Primary = "paint_teal", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_side" },
	stealth = { Primary = "paint_black", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_stripe" },
	nova = { Primary = "paint_purple", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_stripe" },
	neonracer = {
		Primary = "paint_midnight",
		Secondary = "paint_white",
		Accent = "paint_black",
		Pattern = "pattern_stripe",
	},
	arrow = { Primary = "paint_silver", Secondary = "paint_teal", Accent = "paint_black", Pattern = "pattern_split" },
	falcon = { Primary = "paint_orange", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_stripe" },
	viper = { Primary = "paint_green", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_stripe" },
	vortex = { Primary = "paint_white", Secondary = "paint_red", Accent = "paint_black", Pattern = "pattern_chevron" },
	apex = { Primary = "paint_red", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_side" },
	aurora = { Primary = "paint_sky", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_stripe" },
	retro70 = { Primary = "paint_red", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_stripe" },
	retro90 = { Primary = "paint_navy", Secondary = "paint_white", Accent = "paint_black", Pattern = "pattern_stripe" },
}

C.DefaultCar = {
	Body = "gt1",
	Primary = "paint_red",
	Secondary = "paint_white",
	Accent = "paint_black",
	RimColor = "paint_black",
	Helmet = "helmet_white",
	Visor = "visor_dark",
	Rims = "rims_classic",
	Tyre = "tyre_auto",
	Pattern = "pattern_stripe",
	TyreSmoke = "smoke_white",
	Underglow = "glow_none",
	Trail = "trail_none",
	Flames = "flames_none",
	Celebration = "celebrate_basic",
	Title = "title_racer",
	Number = 0, -- 0 = automatic number
}

local items = {}
-- Adds an item to the catalogue (ids must be unique).
local function add(item)
	table.insert(items, item)
end
-- Shorthand for the colour tables.
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- CHASSIS ---------------------------------------------------------------------------------
-- Era: the real F1 idea each design is built around (shown in the Garage). Looks only -
-- every chassis drives exactly the same.
add({ Id = "gt1", Name = "GT-1 Standard", Category = "Body", Price = 0, Era = "2026 spec: downwash pods + active aero" })
add({ Id = "aeros", Name = "Aero S", Category = "Body", Price = 1500, Era = "2022 zero-pod" })
add({ Id = "arrow", Name = "Arrow", Category = "Body", Price = 3000, Era = "2017 shark fin + T-wing" })
add({ Id = "falcon", Name = "Falcon", Category = "Body", Price = 5000, Era = "2014 finger nose" })
add({
	Id = "stealth",
	Name = "Stealth",
	Category = "Body",
	Price = 0,
	Pass = "PremiumTeam",
	Era = "Stealth-jet concept",
})
add({ Id = "vortex", Name = "Vortex", Category = "Body", Price = 0, Pass = "PremiumTeam", Era = "1988 turbo era" })
add({ Id = "apex", Name = "Apex", Category = "Body", Price = 0, Pass = "PremiumTeam", Era = "2006-08 winglet era" })
add({ Id = "nova", Name = "Nova", Category = "Body", Price = 0, Pass = "LegendaryCars", Era = "Hypercar concept" })
add({ Id = "viper", Name = "Viper", Category = "Body", Price = 0, Pass = "LegendaryCars", Era = "2012 step nose" })
add({
	Id = "aurora",
	Name = "Aurora",
	Category = "Body",
	Price = 0,
	Pass = "LegendaryCars",
	Era = "Closed-canopy concept",
})
add({
	Id = "neonracer",
	Name = "Neon Racer",
	Category = "Body",
	Price = 0,
	Pass = "NeonCollection",
	Era = "2004 walrus-nose tribute",
})
add({
	Id = "retro70",
	Name = "Retro 70s",
	Category = "Body",
	Price = 0,
	Pass = "HeritageCollection",
	Era = "1976 teapot airbox",
})
add({
	Id = "retro90",
	Name = "Retro 90s",
	Category = "Body",
	Price = 0,
	Pass = "HeritageCollection",
	Era = "1990 high nose, gull wing",
})

-- Unlocks: Price = coins (0 = free), Pass = game pass key (see Monetization.luau).
-- The mix on purpose: plenty free, lots to earn with coins, the flashiest bits in passes.

-- PAINTS ----------------------------------------------------------------------------------
local freePaints = {
	{ "white", "White", rgb(240, 240, 240) },
	{ "black", "Black", rgb(22, 22, 26) },
	{ "silver", "Silver", rgb(170, 175, 185) },
	{ "grey", "Grey", rgb(95, 100, 110) },
	{ "red", "Racing Red", rgb(215, 25, 35) },
	{ "orange", "Orange", rgb(255, 120, 20) },
	{ "yellow", "Yellow", rgb(255, 210, 30) },
	{ "lime", "Lime", rgb(150, 230, 50) },
	{ "green", "Green", rgb(20, 150, 80) },
	{ "teal", "Teal", rgb(0, 160, 150) },
	{ "cyan", "Cyan", rgb(40, 200, 255) },
	{ "blue", "Blue", rgb(30, 80, 220) },
	{ "navy", "Navy", rgb(15, 25, 80) },
	{ "purple", "Purple", rgb(120, 50, 200) },
	{ "pink", "Pink", rgb(255, 100, 170) },
	{ "maroon", "Maroon", rgb(110, 20, 40) },
}
for _, p in freePaints do
	add({
		Id = "paint_" .. p[1],
		Name = p[2],
		Category = "Paint",
		Price = 0,
		Color = p[3],
		Material = Enum.Material.SmoothPlastic,
	})
end
-- coins
add({
	Id = "paint_crimson",
	Name = "Crimson",
	Category = "Paint",
	Price = 300,
	Color = rgb(150, 10, 30),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.1,
})
add({
	Id = "paint_midnight",
	Name = "Midnight",
	Category = "Paint",
	Price = 300,
	Color = rgb(15, 20, 55),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.1,
})
add({
	Id = "paint_mint",
	Name = "Mint",
	Category = "Paint",
	Price = 300,
	Color = rgb(140, 240, 200),
	Material = Enum.Material.SmoothPlastic,
})
add({
	Id = "paint_sky",
	Name = "Sky Blue",
	Category = "Paint",
	Price = 300,
	Color = rgb(120, 190, 255),
	Material = Enum.Material.SmoothPlastic,
})
add({
	Id = "paint_sand",
	Name = "Desert Sand",
	Category = "Paint",
	Price = 400,
	Color = rgb(214, 190, 140),
	Material = Enum.Material.SmoothPlastic,
})
add({
	Id = "paint_sunset",
	Name = "Sunset",
	Category = "Paint",
	Price = 500,
	Color = rgb(255, 90, 60),
	Material = Enum.Material.SmoothPlastic,
})
add({
	Id = "paint_ice",
	Name = "Ice Blue",
	Category = "Paint",
	Price = 600,
	Color = rgb(185, 225, 255),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.15,
})
add({
	Id = "paint_violet",
	Name = "Satin Violet",
	Category = "Paint",
	Price = 700,
	Color = rgb(95, 40, 140),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.08,
})
add({
	Id = "paint_matte",
	Name = "Matte Black",
	Category = "Paint",
	Price = 800,
	Color = rgb(32, 32, 35),
	Material = Enum.Material.Slate,
})
add({
	Id = "paint_gunmetal",
	Name = "Gunmetal",
	Category = "Paint",
	Price = 900,
	Color = rgb(70, 74, 82),
	Material = Enum.Material.Metal,
	Reflectance = 0.2,
})
add({
	Id = "paint_pearl",
	Name = "Pearl",
	Category = "Paint",
	Price = 1000,
	Color = rgb(245, 240, 230),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.25,
})
add({
	Id = "paint_metalblue",
	Name = "Metallic Blue",
	Category = "Paint",
	Price = 1200,
	Color = rgb(40, 90, 200),
	Material = Enum.Material.Metal,
	Reflectance = 0.2,
})
add({
	Id = "paint_metalred",
	Name = "Metallic Red",
	Category = "Paint",
	Price = 1200,
	Color = rgb(190, 20, 30),
	Material = Enum.Material.Metal,
	Reflectance = 0.2,
})
add({
	Id = "paint_candy",
	Name = "Candy Apple",
	Category = "Paint",
	Price = 1500,
	Color = rgb(200, 0, 40),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.35,
})
add({
	Id = "paint_bronze",
	Name = "Bronze",
	Category = "Paint",
	Price = 1500,
	Color = rgb(170, 110, 60),
	Material = Enum.Material.Metal,
	Reflectance = 0.25,
})
add({
	Id = "paint_lava",
	Name = "Lava Orange",
	Category = "Paint",
	Price = 1500,
	Color = rgb(255, 80, 10),
	Material = Enum.Material.Metal,
	Reflectance = 0.2,
})
-- passes
add({
	Id = "paint_vipgold",
	Name = "VIP Gold",
	Category = "Paint",
	Price = 0,
	Pass = "VIP",
	Color = rgb(255, 196, 45),
	Material = Enum.Material.Metal,
	Reflectance = 0.3,
})
add({
	Id = "paint_platinum",
	Name = "VIP Platinum",
	Category = "Paint",
	Price = 0,
	Pass = "VIP",
	Color = rgb(225, 228, 240),
	Material = Enum.Material.Metal,
	Reflectance = 0.4,
})
add({
	Id = "paint_rainbow",
	Name = "Rainbow",
	Category = "Paint",
	Price = 0,
	Pass = "VIP",
	Color = rgb(255, 80, 80),
	Material = Enum.Material.SmoothPlastic,
	Rainbow = true,
})
add({
	Id = "paint_chrome",
	Name = "Chrome",
	Category = "Paint",
	Price = 0,
	Pass = "PremiumTeam",
	Color = rgb(200, 205, 215),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.6,
})
add({
	Id = "paint_carbon",
	Name = "Carbon",
	Category = "Paint",
	Price = 0,
	Pass = "PremiumTeam",
	Color = rgb(30, 30, 35),
	Material = Enum.Material.DiamondPlate,
})
add({
	Id = "paint_neoncyan",
	Name = "Electric Cyan",
	Category = "Paint",
	Price = 0,
	Pass = "NeonCollection",
	Color = rgb(0, 240, 255),
	Material = Enum.Material.Neon,
})
add({
	Id = "paint_neonpink",
	Name = "Hot Magenta",
	Category = "Paint",
	Price = 0,
	Pass = "NeonCollection",
	Color = rgb(255, 40, 200),
	Material = Enum.Material.Neon,
})
add({
	Id = "paint_neonlime",
	Name = "Toxic Lime",
	Category = "Paint",
	Price = 0,
	Pass = "NeonCollection",
	Color = rgb(120, 255, 40),
	Material = Enum.Material.Neon,
})
add({
	Id = "paint_racinggreen",
	Name = "Racing Green",
	Category = "Paint",
	Price = 0,
	Pass = "HeritageCollection",
	Color = rgb(10, 70, 40),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.15,
})
add({
	Id = "paint_papaya",
	Name = "Papaya",
	Category = "Paint",
	Price = 0,
	Pass = "HeritageCollection",
	Color = rgb(255, 135, 0),
	Material = Enum.Material.SmoothPlastic,
})
add({
	Id = "paint_heritagegold",
	Name = "Heritage Gold",
	Category = "Paint",
	Price = 0,
	Pass = "HeritageCollection",
	Color = rgb(210, 170, 70),
	Material = Enum.Material.Metal,
	Reflectance = 0.2,
})
add({
	Id = "paint_rookie",
	Name = "Rookie Green",
	Category = "Paint",
	Price = 0,
	Pass = "StarterPack",
	Color = rgb(80, 220, 120),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.1,
})

-- HELMETS ---------------------------------------------------------------------------------
local helmets = {
	{ "white", "White", rgb(240, 240, 240), rgb(215, 25, 35) },
	{ "black", "Black", rgb(25, 25, 28), rgb(255, 210, 30) },
	{ "red", "Red", rgb(215, 25, 35), rgb(255, 255, 255) },
	{ "yellow", "Yellow", rgb(255, 210, 30), rgb(30, 80, 220) },
	{ "blue", "Blue", rgb(30, 80, 220), rgb(255, 255, 255) },
	{ "green", "Green", rgb(20, 150, 80), rgb(255, 210, 30) },
}
for _, h in helmets do
	add({ Id = "helmet_" .. h[1], Name = h[2], Category = "Helmet", Price = 0, Color = h[3], Stripe = h[4] })
end
add({
	Id = "helmet_flame",
	Name = "Flame",
	Category = "Helmet",
	Price = 1200,
	Color = rgb(255, 110, 20),
	Stripe = rgb(255, 220, 40),
})
add({
	Id = "helmet_star",
	Name = "Stars",
	Category = "Helmet",
	Price = 1500,
	Color = rgb(20, 30, 90),
	Stripe = rgb(255, 255, 255),
})
add({
	Id = "helmet_carbon",
	Name = "Carbon",
	Category = "Helmet",
	Price = 1800,
	Color = rgb(34, 34, 38),
	Stripe = rgb(215, 25, 35),
	Reflectance = 0.15,
})
add({
	Id = "helmet_checker",
	Name = "Checkered",
	Category = "Helmet",
	Price = 2000,
	Color = rgb(245, 245, 245),
	Stripe = rgb(20, 20, 22),
})
add({
	Id = "helmet_bolt",
	Name = "Lightning",
	Category = "Helmet",
	Price = 2500,
	Color = rgb(30, 60, 200),
	Stripe = rgb(255, 225, 40),
})
add({
	Id = "helmet_rookie",
	Name = "Rookie",
	Category = "Helmet",
	Price = 0,
	Pass = "StarterPack",
	Color = rgb(80, 220, 120),
	Stripe = rgb(255, 255, 255),
})
add({
	Id = "helmet_chrome",
	Name = "Chrome",
	Category = "Helmet",
	Price = 0,
	Pass = "VIP",
	Color = rgb(210, 215, 225),
	Stripe = rgb(30, 30, 35),
	Reflectance = 0.6,
})
add({
	Id = "helmet_gold",
	Name = "Gold",
	Category = "Helmet",
	Price = 0,
	Pass = "VIP",
	Color = rgb(255, 196, 45),
	Stripe = rgb(25, 25, 28),
	Reflectance = 0.3,
})
add({
	Id = "helmet_rainbow",
	Name = "Rainbow",
	Category = "Helmet",
	Price = 0,
	Pass = "VIP",
	Color = rgb(255, 80, 80),
	Stripe = rgb(255, 255, 255),
	Rainbow = true,
})
add({
	Id = "helmet_neon",
	Name = "Neon",
	Category = "Helmet",
	Price = 0,
	Pass = "FXPack",
	Color = rgb(20, 20, 30),
	Stripe = rgb(0, 255, 230),
	Neon = true,
})

-- VISORS (tinted helmet visors, like the real iridium ones) -------------------------------
add({ Id = "visor_dark", Name = "Dark", Category = "Visor", Price = 0, Color = rgb(10, 12, 18), Reflectance = 0.22 })
add({ Id = "visor_smoke", Name = "Smoke", Category = "Visor", Price = 0, Color = rgb(60, 64, 72), Reflectance = 0.3 })
add({
	Id = "visor_red",
	Name = "Iridium Red",
	Category = "Visor",
	Price = 1200,
	Color = rgb(230, 50, 40),
	Reflectance = 0.45,
})
add({
	Id = "visor_green",
	Name = "Iridium Green",
	Category = "Visor",
	Price = 1200,
	Color = rgb(40, 210, 110),
	Reflectance = 0.45,
})
add({
	Id = "visor_purple",
	Name = "Iridium Purple",
	Category = "Visor",
	Price = 1200,
	Color = rgb(150, 70, 240),
	Reflectance = 0.45,
})
add({
	Id = "visor_gold",
	Name = "Iridium Gold",
	Category = "Visor",
	Price = 0,
	Pass = "VIP",
	Color = rgb(255, 190, 40),
	Reflectance = 0.55,
})
add({
	Id = "visor_blue",
	Name = "Iridium Blue",
	Category = "Visor",
	Price = 0,
	Pass = "VIP",
	Color = rgb(40, 140, 255),
	Reflectance = 0.55,
})
add({
	Id = "visor_rainbow",
	Name = "Rainbow",
	Category = "Visor",
	Price = 0,
	Pass = "FXPack",
	Color = rgb(255, 80, 80),
	Reflectance = 0.4,
	Rainbow = true,
})

-- RIMS ------------------------------------------------------------------------------------
add({ Id = "rims_classic", Name = "Classic", Category = "Rims", Price = 0 })
add({ Id = "rims_spoke", Name = "Spoke", Category = "Rims", Price = 400 })
add({ Id = "rims_star", Name = "Star", Category = "Rims", Price = 800 })
add({ Id = "rims_dish", Name = "Aero Cover", Category = "Rims", Price = 1200 })
add({ Id = "rims_turbine", Name = "Turbine", Category = "Rims", Price = 2000 })
add({ Id = "rims_blade", Name = "Blade", Category = "Rims", Price = 0, Pass = "PremiumTeam" })
add({ Id = "rims_mesh", Name = "Mesh", Category = "Rims", Price = 0, Pass = "PremiumTeam" })
add({ Id = "rims_neon", Name = "Neon", Category = "Rims", Price = 0, Pass = "NeonCollection" })
add({ Id = "rims_gold", Name = "Gold", Category = "Rims", Price = 0, Pass = "HeritageCollection" })

-- TYRES (the coloured compound band on the sidewall, like F1's soft / medium / hard) ------
add({ Id = "tyre_auto", Name = "Race Mix", Category = "Tyre", Price = 0, Color = rgb(230, 30, 40) }) -- soft/medium/hard by race number
add({ Id = "tyre_soft", Name = "Soft", Category = "Tyre", Price = 0, Color = rgb(230, 30, 40) })
add({ Id = "tyre_medium", Name = "Medium", Category = "Tyre", Price = 0, Color = rgb(255, 205, 30) })
add({ Id = "tyre_hard", Name = "Hard", Category = "Tyre", Price = 0, Color = rgb(240, 240, 240) })
add({ Id = "tyre_inter", Name = "Intermediate", Category = "Tyre", Price = 500, Color = rgb(40, 185, 70) })
add({ Id = "tyre_wet", Name = "Full Wet", Category = "Tyre", Price = 500, Color = rgb(30, 110, 230) })
add({ Id = "tyre_pink", Name = "Hot Pink", Category = "Tyre", Price = 900, Color = rgb(255, 80, 180) })
add({ Id = "tyre_gold", Name = "Gold", Category = "Tyre", Price = 0, Pass = "VIP", Color = rgb(255, 196, 45) })
add({
	Id = "tyre_neon",
	Name = "Neon",
	Category = "Tyre",
	Price = 0,
	Pass = "FXPack",
	Color = rgb(0, 255, 220),
	Neon = true,
})

-- LIVERIES --------------------------------------------------------------------------------
add({ Id = "pattern_none", Name = "Plain", Category = "Pattern", Price = 0 })
add({ Id = "pattern_stripe", Name = "Centre Stripe", Category = "Pattern", Price = 0 })
add({ Id = "pattern_side", Name = "Side Flash", Category = "Pattern", Price = 300 })
add({ Id = "pattern_split", Name = "Two-Tone", Category = "Pattern", Price = 600 })
add({ Id = "pattern_chevron", Name = "Chevron", Category = "Pattern", Price = 900 })
add({ Id = "pattern_checker", Name = "Checkered", Category = "Pattern", Price = 1500 })
add({ Id = "pattern_flames", Name = "Flames", Category = "Pattern", Price = 0, Pass = "PremiumTeam" })
add({ Id = "pattern_carbon", Name = "Carbon Aero", Category = "Pattern", Price = 0, Pass = "PremiumTeam" })
add({ Id = "pattern_circuit", Name = "Circuit Lines", Category = "Pattern", Price = 0, Pass = "NeonCollection" })
add({ Id = "pattern_retro", Name = "Retro Stripes", Category = "Pattern", Price = 0, Pass = "HeritageCollection" })

-- TYRE SMOKE ------------------------------------------------------------------------------
add({ Id = "smoke_white", Name = "White", Category = "TyreSmoke", Price = 0, Color = rgb(235, 235, 235) })
local smokes = {
	{ "red", "Red", rgb(255, 60, 60) },
	{ "blue", "Blue", rgb(60, 130, 255) },
	{ "green", "Green", rgb(60, 230, 110) },
	{ "orange", "Orange", rgb(255, 140, 40) },
	{ "purple", "Purple", rgb(170, 80, 255) },
	{ "pink", "Pink", rgb(255, 110, 200) },
}
for _, s in smokes do
	add({ Id = "smoke_" .. s[1], Name = s[2], Category = "TyreSmoke", Price = 800, Color = s[3] })
end
add({ Id = "smoke_gold", Name = "Gold", Category = "TyreSmoke", Price = 0, Pass = "FXPack", Color = rgb(255, 200, 50) })
add({
	Id = "smoke_rainbow",
	Name = "Rainbow",
	Category = "TyreSmoke",
	Price = 0,
	Pass = "FXPack",
	Color = rgb(255, 100, 100),
	Rainbow = true,
})

-- UNDERGLOW -------------------------------------------------------------------------------
add({ Id = "glow_none", Name = "None", Category = "Underglow", Price = 0 })
local glows = {
	{ "cyan", "Cyan", rgb(0, 255, 230), 1500 },
	{ "red", "Red", rgb(255, 40, 40), 1500 },
	{ "blue", "Blue", rgb(40, 120, 255), 1500 },
	{ "green", "Green", rgb(60, 255, 90), 1500 },
	{ "pink", "Pink", rgb(255, 60, 200), nil },
	{ "purple", "Purple", rgb(170, 60, 255), nil },
	{ "yellow", "Yellow", rgb(255, 220, 40), nil },
	{ "white", "White", rgb(255, 255, 255), nil },
}
for _, g in glows do
	add({
		Id = "glow_" .. g[1],
		Name = g[2],
		Category = "Underglow",
		Price = g[4] or 0,
		Pass = if g[4] then nil else "FXPack",
		Color = g[3],
	})
end

-- TRAILS ----------------------------------------------------------------------------------
add({ Id = "trail_none", Name = "None", Category = "Trail", Price = 0 })
add({ Id = "trail_smoke", Name = "Vapor", Category = "Trail", Price = 2500, Color = rgb(235, 235, 235) })
add({ Id = "trail_speed", Name = "Speed Blue", Category = "Trail", Price = 3000, Color = rgb(80, 170, 255) })
add({ Id = "trail_ember", Name = "Ember", Category = "Trail", Price = 3500, Color = rgb(255, 120, 40) })
add({ Id = "trail_rainbow", Name = "Rainbow", Category = "Trail", Price = 0, Pass = "FXPack", Rainbow = true })
add({ Id = "trail_fire", Name = "Fire", Category = "Trail", Price = 0, Pass = "FXPack", Color = rgb(255, 110, 20) })
add({
	Id = "trail_lightning",
	Name = "Lightning",
	Category = "Trail",
	Price = 0,
	Pass = "FXPack",
	Color = rgb(90, 180, 255),
})
add({ Id = "trail_toxic", Name = "Toxic", Category = "Trail", Price = 0, Pass = "FXPack", Color = rgb(120, 255, 40) })
add({ Id = "trail_galaxy", Name = "Galaxy", Category = "Trail", Price = 0, Pass = "FXPack", Color = rgb(150, 70, 255) })
add({ Id = "trail_gold", Name = "Gold", Category = "Trail", Price = 0, Pass = "VIP", Color = rgb(255, 200, 40) })

-- FLAMES ----------------------------------------------------------------------------------
add({ Id = "flames_none", Name = "Off", Category = "Flames", Price = 0 })
add({ Id = "flames_nitro", Name = "Exhaust Flames", Category = "Flames", Price = 0, Pass = "FXPack" })

-- CELEBRATIONS ----------------------------------------------------------------------------
add({ Id = "celebrate_basic", Name = "Sparkles", Category = "Celebration", Price = 0 })
add({ Id = "celebrate_confetti", Name = "Confetti", Category = "Celebration", Price = 2000 })
add({ Id = "celebrate_fireworks", Name = "Fireworks", Category = "Celebration", Price = 0, Pass = "FXPack" })
add({ Id = "celebrate_lightning", Name = "Lightning", Category = "Celebration", Price = 0, Pass = "FXPack" })
add({ Id = "celebrate_goldrain", Name = "Gold Rain", Category = "Celebration", Price = 0, Pass = "FXPack" })

-- TITLES ----------------------------------------------------------------------------------
add({ Id = "title_racer", Name = "Racer", Category = "Title", Price = 0, Text = "Racer" })
local titles = {
	{ "Late Braker", 1000 },
	{ "Slipstreamer", 1000 },
	{ "Road Warrior", 1200 },
	{ "Night Rider", 1200 },
	{ "Ghost Hunter", 1500 },
	{ "Podium Hunter", 1500 },
	{ "Pole Sitter", 2000 },
	{ "Track Master", 2000 },
	{ "Speed Demon", 2500 },
	{ "Apex Predator", 3000 },
}
for _, t in titles do
	add({
		Id = "title_" .. string.lower((string.gsub(t[1], " ", ""))),
		Name = t[1],
		Category = "Title",
		Price = t[2],
		Text = t[1],
	})
end
add({ Id = "title_rookie", Name = "Rookie", Category = "Title", Price = 0, Pass = "StarterPack", Text = "Rookie" })
add({ Id = "title_pro", Name = "Pro", Category = "Title", Price = 0, Pass = "ProRacer", Text = "Pro" })
add({ Id = "title_vip", Name = "VIP", Category = "Title", Price = 0, Pass = "VIP", Text = "VIP" })
add({ Id = "title_legend", Name = "Legend", Category = "Title", Price = 0, Pass = "LegendaryCars", Text = "Legend" })
add({ Id = "title_ultimate", Name = "Ultimate", Category = "Title", Price = 0, Pass = "Ultimate", Text = "Ultimate" })
add({ Id = "title_owner", Name = "Owner", Category = "Title", Price = 0, OwnerOnly = true, Text = "Owner" })

-- RANKED SEASON REWARDS (unlocked by reaching a tier; kept forever once earned) -----------
add({
	Id = "title_rk_silver",
	Name = "Silver Racer",
	Category = "Title",
	Price = 0,
	RankTier = 2,
	Text = "Silver Racer",
})
add({
	Id = "paint_rk_gold",
	Name = "Ranked Gold",
	Category = "Paint",
	Price = 0,
	RankTier = 3,
	Color = rgb(255, 200, 50),
	Material = Enum.Material.Metal,
	Reflectance = 0.35,
})
add({ Id = "rims_rk_platinum", Name = "Platinum Rims", Category = "Rims", Price = 0, RankTier = 4 })
add({
	Id = "trail_rk_diamond",
	Name = "Diamond Trail",
	Category = "Trail",
	Price = 0,
	RankTier = 5,
	Color = rgb(140, 200, 255),
})
add({ Id = "pattern_rk_champion", Name = "Champion Livery", Category = "Pattern", Price = 0, RankTier = 6 })
add({ Id = "title_rk_champion", Name = "Champion", Category = "Title", Price = 0, RankTier = 6, Text = "Champion" })

C.RankedRewards =
	{ nil, "Silver Racer title", "Ranked Gold paint", "Platinum rims", "Diamond trail", "Champion livery" }

C.Items = items
C.ById = {}
C.ByCategory = {}
for _, it in items do
	C.ById[it.Id] = it
	C.ByCategory[it.Category] = C.ByCategory[it.Category] or {}
	table.insert(C.ByCategory[it.Category], it)
end

-- Whether a player with these owned items, passes and peak ranked tier may equip `item`.
function C.CanUse(item, owned, passes, peakTier: number?): boolean
	if item.OwnerOnly then
		return passes.Owner == true -- set by the server for the game's owner only
	end
	if item.RankTier then
		return owned[item.Id] == true or (peakTier or 0) >= item.RankTier
	end
	if item.Pass then
		return passes[item.Pass] == true or passes.Ultimate == true
	end
	if item.Price <= 0 then
		return true
	end
	return owned[item.Id] == true
end

-- Makes a car appearance safe (unknown/locked items fall back to default).
function C.Sanitize(car, owned, passes, peakTier: number?)
	local out = {}
	local src = car or {}
	for slot, category in C.Slots do
		local id = src[slot]
		local item = if typeof(id) == "string" then C.ById[id] else nil
		if
			item
			and item.Category == category
			and (owned == nil or passes == nil or C.CanUse(item, owned, passes, peakTier))
		then
			out[slot] = id
		else
			out[slot] = C.DefaultCar[slot]
		end
	end
	local num = tonumber(src.Number)
	out.Number = if num and num >= 0 and num <= 99 and num == math.floor(num) then num else 0
	return out
end

-- Race number shown on a car (automatic numbers are 2..99 based on the user id)
function C.NumberFor(car, userId: number?): number
	local n = car and tonumber(car.Number) or 0
	if n and n > 0 then
		return n
	end
	return ((userId or 7) % 98) + 2
end

return C
