--!nonstrict
-- Visual themes for the circuits: lighting (always bright enough to see the road), a
-- per-circuit sky mood, ground, run-off, barriers, local architecture, scenery props,
-- signature landmarks, ambient effects (petals, leaves, sand, fireworks...), moving life
-- (boats, planes, birds, balloons), fan colours, weather and the facts the circuit intro
-- screen shows (icon, time of day, conditions, temperature).

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Every preset keeps the road clearly visible: night races are floodlit dusk-blue,
-- never pitch black.
local Sky = {
	day = { ClockTime = 13.6, Brightness = 3, Ambient = rgb(128, 128, 138), Outdoor = rgb(155, 155, 165), Shift = rgb(255, 246, 228), AtmoColor = rgb(200, 225, 255), AtmoDecay = rgb(110, 150, 200), Density = 0.24, Haze = 1.1, Glare = 0.2, Cloud = 0.45, Tint = rgb(255, 252, 246), Saturation = 0.14, Exposure = 0.05 },
	hot = { ClockTime = 13, Brightness = 3.2, Ambient = rgb(140, 125, 112), Outdoor = rgb(170, 150, 130), Shift = rgb(255, 228, 185), AtmoColor = rgb(245, 228, 195), AtmoDecay = rgb(210, 165, 115), Density = 0.26, Haze = 1.8, Glare = 0.4, Cloud = 0.12, Tint = rgb(255, 246, 232), Saturation = 0.16, Exposure = 0.05 },
	sunset = { ClockTime = 17.1, Brightness = 2.8, Ambient = rgb(150, 122, 116), Outdoor = rgb(172, 138, 128), Shift = rgb(255, 180, 120), AtmoColor = rgb(255, 196, 160), AtmoDecay = rgb(205, 120, 100), Density = 0.26, Haze = 1.6, Glare = 0.7, Cloud = 0.3, Tint = rgb(255, 238, 220), Saturation = 0.2, Exposure = 0.15 },
	twilight = { ClockTime = 17.9, Brightness = 2.4, Ambient = rgb(145, 130, 165), Outdoor = rgb(162, 144, 182), Shift = rgb(255, 160, 130), AtmoColor = rgb(210, 165, 200), AtmoDecay = rgb(130, 90, 160), Density = 0.24, Haze = 1.3, Glare = 0.5, Cloud = 0.28, Tint = rgb(248, 236, 255), Saturation = 0.2, Exposure = 0.3 },
	night = { ClockTime = 19.9, Brightness = 1.8, Ambient = rgb(150, 152, 185), Outdoor = rgb(140, 146, 185), Shift = rgb(180, 196, 255), AtmoColor = rgb(70, 85, 140), AtmoDecay = rgb(40, 45, 95), Density = 0.18, Haze = 0.6, Glare = 0, Cloud = 0.2, Tint = rgb(236, 240, 255), Saturation = 0.22, Exposure = 0.35 },
	overcast = { ClockTime = 12.5, Brightness = 2.3, Ambient = rgb(140, 145, 155), Outdoor = rgb(160, 165, 175), Shift = rgb(215, 220, 230), AtmoColor = rgb(190, 200, 214), AtmoDecay = rgb(135, 145, 165), Density = 0.32, Haze = 2, Glare = 0, Cloud = 0.85, Tint = rgb(242, 246, 252), Saturation = 0, Exposure = 0.15 },
	snow = { ClockTime = 18.9, Brightness = 2, Ambient = rgb(150, 165, 196), Outdoor = rgb(150, 170, 206), Shift = rgb(180, 220, 255), AtmoColor = rgb(120, 150, 200), AtmoDecay = rgb(60, 90, 150), Density = 0.22, Haze = 0.8, Glare = 0, Cloud = 0.35, Tint = rgb(232, 242, 255), Saturation = 0.12, Exposure = 0.4 },
	volcano = { ClockTime = 17.8, Brightness = 2.2, Ambient = rgb(160, 122, 112), Outdoor = rgb(165, 125, 115), Shift = rgb(255, 130, 70), AtmoColor = rgb(170, 110, 90), AtmoDecay = rgb(100, 50, 40), Density = 0.3, Haze = 1.8, Glare = 0.3, Cloud = 0.5, Tint = rgb(255, 232, 216), Saturation = 0.2, Exposure = 0.35 },
}

-- Shirt colours for crowds (a theme can override with its own home-fan palette)
local FANS = { rgb(220, 40, 40), rgb(40, 90, 200), rgb(250, 250, 250), rgb(30, 30, 34), rgb(255, 200, 30), rgb(40, 160, 80), rgb(255, 130, 30), rgb(150, 60, 200), rgb(0, 170, 200), rgb(240, 110, 160) }

local GRASS = rgb(96, 170, 70)
local Themes = {}
Themes.Fans = FANS

local function timeOfDay(clock: number): string
	if clock < 9.5 then
		return "Morning"
	elseif clock < 15 then
		return "Midday"
	elseif clock < 16.9 then
		return "Afternoon"
	elseif clock < 18.5 then
		return "Sunset"
	end
	return "Night"
end

local function theme(key, t)
	t.Key = key
	local preset = Sky[t.Sky or "day"]
	local night = preset == Sky.night or preset == Sky.snow or t.Night == true
	-- each circuit gets its own copy of the preset with its own mood on top
	local sky = table.clone(preset)
	for k, v in t.SkyTweak or {} do
		sky[k] = v
	end
	t.Sky = sky
	t.Night = night
	t.Ground = t.Ground or GRASS
	t.GroundMaterial = t.GroundMaterial or Enum.Material.Grass
	t.Runoff = t.Runoff or t.Ground
	t.RunoffMaterial = t.RunoffMaterial or t.GroundMaterial
	t.RunoffKind = t.RunoffKind or "grass" -- grass | asphalt (painted) | sand
	t.Road = t.Road or (if t.Night then rgb(96, 98, 110) else rgb(62, 64, 72))
	t.KerbA = t.KerbA or rgb(220, 35, 35)
	t.KerbB = t.KerbB or rgb(245, 245, 245)
	t.Barrier = t.Barrier or "classic" -- classic (armco + tyres + tecpro) | street (concrete + fence)
	t.Accent = t.Accent or rgb(255, 180, 40)
	t.Props = t.Props or { tree_round = 1 }
	t.Arch = t.Arch or { cottage = 1 }
	t.Layout = t.Layout or "town" -- city | town | rural | sparse
	t.Density = t.Density or 1
	t.Landmarks = t.Landmarks or {}
	t.Life = t.Life or {} -- boats | planes | birds | balloons | jets | parrots
	t.Horizon = t.Horizon or "hills"
	t.Water = t.Water or rgb(40, 120, 200)
	t.Crowd = t.Crowd or 1
	t.Fans = t.Fans or FANS
	t.Icon = t.Icon or "🏁"
	t.TimeOfDay = t.TimeOfDay or timeOfDay(sky.ClockTime)
	t.Conditions = t.Conditions or (if t.Weather == "rain" then "Light rain" elseif t.Weather == "snow" then "Snowfall" elseif t.Weather == "ash" then "Volcanic ash" elseif night then "Clear, floodlit" else "Clear")
	t.Temp = t.Temp or 24
	Themes[key] = t
end

-- Australia
theme("park", {
	Name = "Parkland", Icon = "🦘", Temp = 22,
	SkyTweak = { ClockTime = 10.4, AtmoColor = rgb(205, 228, 255), Cloud = 0.35, Saturation = 0.18 },
	Props = { tree_round = 4, tree_eucalyptus = 5, rock = 1, bush = 2 },
	Arch = { aussie_house = 3, office_tower = 2, apartment = 1 },
	Layout = "town", Landmarks = { "lake", "ferris", "kangaroos", "bandstand", "skyline" }, Life = { "boats", "birds", "planes" },
	Ambient = "pollen", Horizon = "skyline", Accent = rgb(255, 196, 30),
	Fans = { rgb(255, 200, 30), rgb(0, 120, 60), rgb(250, 250, 250), rgb(30, 70, 160) },
})
-- China
theme("dragon", {
	Name = "Dragon City", Icon = "🐉", Temp = 21,
	SkyTweak = { ClockTime = 15.2, AtmoColor = rgb(235, 225, 205), AtmoDecay = rgb(190, 160, 130), Haze = 2.2, Density = 0.3, Cloud = 0.3 },
	Props = { tree_round = 2, lantern = 3, bush = 1 },
	Arch = { twisted_tower = 2, office_tower = 3, pagoda = 1, neon_block = 2, apartment = 2 },
	Layout = "city", Landmarks = { "pearl_tower", "dragon_gate", "pagoda_big", "skyline" }, Life = { "planes", "boats" },
	Horizon = "skyline", Accent = rgb(230, 40, 40), KerbA = rgb(220, 30, 30), KerbB = rgb(255, 210, 40),
	Fans = { rgb(220, 30, 30), rgb(255, 210, 40), rgb(250, 250, 250) },
})
-- Japan
theme("sakura", {
	Name = "Cherry Blossom Hills", Icon = "🌸", Temp = 18,
	SkyTweak = { ClockTime = 9.3, Tint = rgb(255, 244, 250), AtmoColor = rgb(240, 222, 238), Saturation = 0.2, Cloud = 0.4 },
	Props = { tree_cherry = 7, tree_pine = 1, bush = 1 },
	Arch = { japanese_house = 4, pagoda = 1, torii = 1, neon_block = 1 },
	Layout = "town", Landmarks = { "fuji", "ferris", "torii_path", "zen_garden", "pagoda_big" }, Life = { "birds", "planes" },
	Ambient = "petals", Horizon = "snowmountains", KerbA = rgb(230, 40, 60), Accent = rgb(255, 120, 170),
	Fans = { rgb(250, 250, 250), rgb(230, 30, 50), rgb(30, 40, 90), rgb(255, 150, 190) },
})
-- Bahrain
theme("desertnight", {
	Name = "Desert Night", Icon = "🐪", Temp = 29, Sky = "night",
	SkyTweak = { AtmoColor = rgb(110, 90, 140), AtmoDecay = rgb(70, 50, 110), Tint = rgb(255, 240, 230) },
	Ground = rgb(215, 182, 124), GroundMaterial = Enum.Material.Sand, RunoffKind = "asphalt",
	Props = { dune = 3, palm = 2 },
	Arch = { wind_tower_house = 3, dome_pavilion = 1, spire_tower = 1 },
	Layout = "sparse", Landmarks = { "sail_tower", "tree_of_life", "camels", "tower_floodlit" }, Life = { "planes" },
	Ambient = "sand", Horizon = "mesas", Density = 0.9, Accent = rgb(230, 30, 50),
	Fans = { rgb(230, 30, 50), rgb(250, 250, 250), rgb(30, 30, 34) },
})
-- Saudi Arabia
theme("corniche", {
	Name = "Seafront Night", Icon = "⛲", Temp = 27, Sky = "night",
	SkyTweak = { AtmoColor = rgb(60, 100, 130), AtmoDecay = rgb(30, 60, 90), Tint = rgb(230, 250, 255) },
	Barrier = "street", Ground = rgb(205, 190, 155), GroundMaterial = Enum.Material.Sandstone,
	Props = { palm = 4 },
	Arch = { spire_tower = 2, office_tower = 3, dome_pavilion = 1, apartment = 2 },
	Layout = "city", Landmarks = { "sea", "fountain_jet", "dhows", "flagpole", "skyline" }, Life = { "boats" },
	Fireworks = true, Horizon = "skyline", Accent = rgb(0, 190, 120), Water = rgb(20, 90, 150),
	Fans = { rgb(0, 130, 70), rgb(250, 250, 250), rgb(30, 30, 34) },
})
-- USA Florida
theme("beach", {
	Name = "Ocean Beach", Icon = "🌴", Temp = 31, Sky = "hot",
	SkyTweak = { ClockTime = 12.2, AtmoColor = rgb(215, 238, 255), Cloud = 0.3, Saturation = 0.24 },
	Ground = rgb(232, 212, 162), GroundMaterial = Enum.Material.Sand, RunoffKind = "asphalt",
	Props = { palm = 6, bush = 1 },
	Arch = { beach_condo = 3, art_deco = 3, office_tower = 1, lighthouse = 0.3 },
	Layout = "town", Landmarks = { "sea", "stadium", "yachts", "lifeguards", "deco_row", "lighthouse_cape" }, Life = { "boats", "planes", "birds" },
	Horizon = "skyline", Accent = rgb(0, 200, 200), Water = rgb(20, 160, 200),
	Fans = { rgb(0, 200, 200), rgb(255, 120, 170), rgb(250, 250, 250), rgb(255, 150, 40) },
})
-- Canada
theme("maple", {
	Name = "Maple Forest", Icon = "🍁", Temp = 19,
	SkyTweak = { ClockTime = 16.2, Shift = rgb(255, 214, 160), AtmoColor = rgb(240, 214, 190), Saturation = 0.22 },
	Props = { tree_maple = 7, tree_pine = 2, bush = 1 },
	Arch = { cottage = 2, office_tower = 1, barn = 1 },
	Layout = "rural", Landmarks = { "lake", "biosphere", "inclined_tower", "chateau", "casino" }, Life = { "boats", "birds", "planes" },
	Ambient = "leaves", Horizon = "skyline", KerbA = rgb(200, 30, 30), Accent = rgb(220, 40, 30),
	Fans = { rgb(220, 30, 30), rgb(250, 250, 250) },
})
-- Monaco
theme("harbor", {
	Name = "Principality Harbour", Icon = "🛥️", Temp = 23,
	SkyTweak = { ClockTime = 11.2, AtmoColor = rgb(200, 228, 255), Saturation = 0.2, Cloud = 0.25 },
	Barrier = "street", Ground = rgb(185, 180, 170), GroundMaterial = Enum.Material.Pavement,
	Props = { palm = 2, tree_cypress = 1 },
	Arch = { apartment = 5, villa = 2, hotel_block = 1 },
	Layout = "city", Landmarks = { "sea", "yachts", "casino", "rock_palace", "tunnel" }, Life = { "boats", "planes" },
	Horizon = "mountains", Accent = rgb(220, 30, 50), Water = rgb(20, 110, 180),
	Fans = { rgb(220, 30, 50), rgb(250, 250, 250) },
})
-- Spain (Barcelona)
theme("mediterranean", {
	Name = "Mediterranean Hills", Icon = "☀️", Temp = 28, Sky = "hot",
	SkyTweak = { ClockTime = 14.6, AtmoColor = rgb(250, 232, 205), Haze = 2 },
	Ground = rgb(150, 160, 92), RunoffKind = "asphalt",
	Props = { tree_round = 2, tree_cypress = 2, rock = 1, bush = 1 },
	Arch = { villa = 4, apartment = 1, church = 0.4 },
	Layout = "town", Landmarks = { "spire_cathedral", "bullring", "hill_castle", "white_village" }, Life = { "planes", "birds" },
	Horizon = "hills", Accent = rgb(255, 200, 0), KerbA = rgb(210, 20, 30), KerbB = rgb(255, 200, 0),
	Fans = { rgb(210, 20, 30), rgb(255, 200, 0), rgb(250, 250, 250) },
})
-- Austria
theme("alpine", {
	Name = "Alpine Meadows", Icon = "🏔️", Temp = 17,
	SkyTweak = { ClockTime = 12, Density = 0.16, Haze = 0.5, AtmoColor = rgb(200, 225, 255), Saturation = 0.22, Cloud = 0.3 },
	Props = { tree_pine = 6, rock = 2 },
	Arch = { chalet = 4, church = 0.4, barn = 1 },
	Layout = "rural", Landmarks = { "bull_statue", "cable_car", "cows", "alpine_hut" }, Life = { "birds", "balloons" },
	Horizon = "snowmountains", Accent = rgb(230, 30, 40),
	Fans = { rgb(230, 30, 40), rgb(250, 250, 250), rgb(255, 130, 0) },
})
-- Great Britain
theme("countryside", {
	Name = "Rainy Countryside", Icon = "🌧️", Temp = 15, Sky = "overcast", Weather = "rain",
	Props = { tree_round = 4, hedge = 2 },
	Arch = { cottage = 3, barn = 2, hangar = 1, wind_turbine = 1, church = 0.3 },
	Layout = "rural", Landmarks = { "airfield", "hangars", "manor" }, Life = { "jets", "birds" },
	Horizon = "hills", Ground = rgb(84, 156, 72), Accent = rgb(30, 60, 160),
	Fans = { rgb(30, 60, 160), rgb(220, 30, 40), rgb(250, 250, 250), rgb(255, 150, 30) },
})
-- Belgium
theme("forest", {
	Name = "Deep Forest", Icon = "🌲", Temp = 16, Sky = "overcast",
	SkyTweak = { ClockTime = 11, Density = 0.4, Haze = 2.6, AtmoColor = rgb(200, 212, 205), Cloud = 0.7 },
	Props = { tree_pine = 9, tree_round = 3, rock = 1 },
	Arch = { chalet = 2, cottage = 2, church = 0.3 },
	Layout = "rural", Density = 1.3, Landmarks = { "abbey", "river", "deer", "lodge" }, Life = { "birds" },
	Ambient = "mist", Horizon = "mountains", Ground = rgb(74, 138, 64), Accent = rgb(255, 210, 0),
	Fans = { rgb(30, 30, 34), rgb(255, 210, 0), rgb(230, 30, 40) },
})
-- Hungary
theme("valley", {
	Name = "Sunflower Valley", Icon = "🌻", Temp = 30, Sky = "hot",
	SkyTweak = { ClockTime = 16, Shift = rgb(255, 222, 170), AtmoColor = rgb(250, 230, 190) },
	Ground = rgb(170, 162, 92),
	Props = { sunflowers = 3, tree_round = 2 },
	Arch = { villa = 2, classical = 1, barn = 2, church = 0.4 },
	Layout = "rural", Landmarks = { "parliament", "vineyard", "balloon_field" }, Life = { "balloons", "birds" },
	Horizon = "hills", Accent = rgb(60, 150, 70),
	Fans = { rgb(210, 30, 40), rgb(250, 250, 250), rgb(40, 140, 60) },
})
-- Netherlands
theme("tulip", {
	Name = "Tulip Dunes", Icon = "🌷", Temp = 18,
	SkyTweak = { ClockTime = 11.6, AtmoColor = rgb(210, 230, 255), Cloud = 0.55, Saturation = 0.24 },
	Props = { tulips = 5, dune = 1 },
	Arch = { townhouse = 4, windmill = 1, wind_turbine = 1 },
	Layout = "town", Landmarks = { "windmills", "canal", "bike_park" }, Life = { "birds", "boats" },
	Ambient = "petals_mixed", Horizon = "none", Runoff = rgb(225, 205, 150), RunoffMaterial = Enum.Material.Sand, KerbA = rgb(255, 120, 0), Accent = rgb(255, 120, 0),
	Crowd = 1.3, Fans = { rgb(255, 120, 0), rgb(255, 140, 20), rgb(255, 110, 0), rgb(250, 250, 250) },
})
-- Italy
theme("temple", {
	Name = "Royal Park", Icon = "🏛️", Temp = 26,
	SkyTweak = { ClockTime = 16.4, Shift = rgb(255, 216, 170), AtmoColor = rgb(245, 225, 200), Saturation = 0.2 },
	Props = { tree_round = 4, tree_cypress = 3 },
	Arch = { classical = 2, villa = 3, church = 0.5 },
	Layout = "town", Landmarks = { "temple", "old_banking", "duomo", "village_square" }, Life = { "birds", "planes" },
	Horizon = "hills", KerbA = rgb(0, 150, 70), Accent = rgb(220, 20, 30),
	Crowd = 1.3, Fans = { rgb(220, 20, 30), rgb(230, 25, 35), rgb(210, 15, 25), rgb(255, 220, 0) },
})
-- Spain (Madrid)
theme("capital", {
	Name = "Modern Capital", Icon = "🏙️", Temp = 29,
	SkyTweak = { ClockTime = 13.4, Haze = 1.6, AtmoColor = rgb(230, 225, 215) },
	Ground = rgb(122, 152, 92), RunoffKind = "asphalt",
	Props = { tree_round = 2, bush = 1 },
	Arch = { office_tower = 4, apartment = 3, classical = 1 },
	Layout = "city", Landmarks = { "leaning_towers", "triumph_arch", "stadium", "skyline" }, Life = { "planes" },
	Horizon = "skyline", Accent = rgb(255, 60, 60),
	Fans = { rgb(210, 20, 30), rgb(255, 200, 0), rgb(250, 250, 250) },
})
-- Azerbaijan
theme("castle", {
	Name = "Old City", Icon = "🏰", Temp = 25, Sky = "sunset",
	Barrier = "street", Ground = rgb(190, 170, 130), GroundMaterial = Enum.Material.Sandstone,
	Props = { tree_round = 1, palm = 1 },
	Arch = { apartment = 3, office_tower = 2, castletower = 1 },
	Layout = "city", Landmarks = { "castle", "maiden_tower", "flame_towers", "sea" }, Life = { "boats" },
	Horizon = "skyline", Accent = rgb(0, 170, 220),
	Fans = { rgb(0, 170, 220), rgb(220, 30, 40), rgb(40, 160, 70) },
})
-- Singapore
theme("neon", {
	Name = "Neon Skyline", Icon = "🌃", Temp = 30, Sky = "night",
	SkyTweak = { Tint = rgb(250, 236, 255), AtmoColor = rgb(90, 60, 130), AtmoDecay = rgb(50, 30, 90) },
	Barrier = "street", Ground = rgb(80, 82, 90), GroundMaterial = Enum.Material.Pavement,
	Props = { palm = 2, tree_round = 1 },
	Arch = { office_tower = 4, neon_block = 3, apartment = 2 },
	Layout = "city", Landmarks = { "sands_hotel", "supertrees", "lion_fountain", "ferris", "skyline" }, Life = { "boats" },
	Fireworks = true, Horizon = "skyline", Accent = rgb(255, 40, 200),
	Fans = { rgb(230, 30, 40), rgb(250, 250, 250), rgb(255, 40, 200) },
})
-- USA Texas
theme("texas", {
	Name = "Texas Hill Country", Icon = "🤠", Temp = 33, Sky = "hot",
	SkyTweak = { ClockTime = 15.2, AtmoColor = rgb(215, 232, 255), Haze = 1.2, Cloud = 0.25 },
	Ground = rgb(152, 150, 82), RunoffKind = "asphalt",
	Props = { tree_round = 2, cactus = 1, rock = 2 },
	Arch = { ranch_house = 3, barn = 2, water_tower = 1, oil_pump = 2, wind_turbine = 1 },
	Layout = "rural", Landmarks = { "obs_tower", "longhorns", "rodeo" }, Life = { "planes", "birds" },
	Horizon = "hills", Accent = rgb(255, 120, 20),
	Fans = { rgb(255, 120, 20), rgb(30, 50, 110), rgb(250, 250, 250), rgb(180, 30, 40) },
})
-- Mexico
theme("aztec", {
	Name = "Aztec Highlands", Icon = "🌮", Temp = 21,
	SkyTweak = { ClockTime = 12.6, Density = 0.16, Haze = 0.7, AtmoColor = rgb(190, 215, 255), Saturation = 0.24 },
	Ground = rgb(122, 160, 82),
	Props = { cactus = 2, agave = 2, tree_round = 1 },
	Arch = { colorful_house = 4, church = 0.5, apartment = 1 },
	Layout = "town", Landmarks = { "stadium", "pyramid_big", "sun_stone", "papel_picado", "volcano_far" }, Life = { "planes", "balloons" },
	Ambient = "confetti", Horizon = "mountains", KerbA = rgb(0, 150, 70), Accent = rgb(0, 150, 70),
	Crowd = 1.2, Fans = { rgb(0, 130, 60), rgb(250, 250, 250), rgb(210, 20, 30) },
})
-- Brazil
theme("jungle", {
	Name = "Rainforest Bowl", Icon = "🦜", Temp = 27,
	SkyTweak = { ClockTime = 14.2, Density = 0.3, Haze = 2.1, AtmoColor = rgb(220, 235, 215), Cloud = 0.55 },
	Ground = rgb(64, 142, 62),
	Props = { tree_jungle = 6, palm = 2, bush = 2 },
	Arch = { colorful_house = 4, office_tower = 1, apartment = 1 },
	Layout = "town", Density = 1.2, Landmarks = { "redeemer", "sugarloaf", "favela", "skyline" }, Life = { "parrots", "planes" },
	Ambient = "fireflies", Horizon = "hills", KerbA = rgb(255, 210, 0), KerbB = rgb(0, 150, 60), Accent = rgb(0, 160, 70),
	Crowd = 1.2, Fans = { rgb(255, 210, 0), rgb(0, 150, 60), rgb(30, 60, 160) },
})
-- USA Nevada
theme("vegas", {
	Name = "Glitter Strip", Icon = "🎰", Temp = 26, Sky = "night",
	SkyTweak = { Tint = rgb(255, 244, 228), AtmoColor = rgb(110, 80, 120), AtmoDecay = rgb(60, 40, 90) },
	Barrier = "street", Ground = rgb(84, 84, 92), GroundMaterial = Enum.Material.Pavement,
	Props = { palm = 2 },
	Arch = { casino_hotel = 3, neon_block = 3, pyramid_hotel = 0.4, office_tower = 2 },
	Layout = "city", Landmarks = { "welcome_sign", "fountain_show", "lattice_tower", "orb", "ferris", "skyline" }, Life = { "planes" },
	Fireworks = true, Horizon = "skyline", Accent = rgb(255, 200, 40),
	Fans = { rgb(255, 200, 40), rgb(230, 30, 60), rgb(30, 30, 34), rgb(250, 250, 250) },
})
-- Qatar
theme("pearl", {
	Name = "Pearl Desert", Icon = "🦪", Temp = 30, Sky = "night",
	SkyTweak = { Tint = rgb(236, 246, 255), AtmoColor = rgb(80, 100, 140) },
	Ground = rgb(222, 197, 147), GroundMaterial = Enum.Material.Sand, RunoffKind = "asphalt",
	Props = { dune = 2, palm = 2 },
	Arch = { spire_tower = 1, dome_pavilion = 2, wind_tower_house = 2 },
	Layout = "sparse", Landmarks = { "pearl_monument", "tent_stadium", "tower_floodlit", "skyline" }, Life = { "planes" },
	Ambient = "sand", Horizon = "mesas", Density = 0.9, KerbA = rgb(140, 20, 60), Accent = rgb(140, 20, 60),
	Fans = { rgb(140, 20, 60), rgb(250, 250, 250) },
})
-- Abu Dhabi
theme("marina", {
	Name = "Twilight Marina", Icon = "🌇", Temp = 28, Sky = "twilight", Night = true,
	Ground = rgb(205, 194, 164), GroundMaterial = Enum.Material.Sand, RunoffKind = "asphalt",
	Props = { palm = 5 },
	Arch = { dome_pavilion = 2, spire_tower = 2, office_tower = 2 },
	Layout = "town", Landmarks = { "sea", "yachts", "hotel", "theme_park", "white_palace" }, Life = { "boats", "planes" },
	Fireworks = true, Horizon = "skyline", Accent = rgb(80, 200, 255),
	Fans = { rgb(200, 20, 40), rgb(0, 130, 70), rgb(250, 250, 250), rgb(30, 30, 34) },
})
-- Bonus: Arctic
theme("snow", {
	Name = "Arctic Glacier", Icon = "❄️", Temp = -8, Sky = "snow", Weather = "snow",
	Ground = rgb(236, 243, 252), GroundMaterial = Enum.Material.Snow, Road = rgb(78, 84, 98),
	Props = { snowpine = 6, iceblock = 2 },
	Arch = { research_station = 2, ski_lodge = 2, igloo = 2 },
	Layout = "sparse", Landmarks = { "aurora", "ski_jump", "ski_lift", "ice_castle", "polar_bears" }, Life = {},
	Horizon = "snowmountains", KerbA = rgb(40, 130, 255), Accent = rgb(80, 200, 255),
	Fans = { rgb(40, 130, 255), rgb(250, 250, 250), rgb(220, 30, 40), rgb(255, 200, 30) },
})
-- Bonus: Volcano
theme("volcano", {
	Name = "Volcanic Island", Icon = "🌋", Temp = 38, Sky = "volcano", Weather = "ash", Night = true,
	Ground = rgb(70, 60, 56), GroundMaterial = Enum.Material.Basalt, Road = rgb(92, 90, 98),
	Props = { lavarock = 4, palm = 2 },
	Arch = { tiki_hut = 3, geothermal = 1 },
	Layout = "sparse", Landmarks = { "volcano", "sea", "moai", "lava_river", "tiki_village", "shipwreck" }, Life = { "birds" },
	Ambient = "embers", Horizon = "volcanoes", KerbA = rgb(255, 90, 0), Accent = rgb(255, 110, 20),
	Fans = { rgb(255, 110, 20), rgb(30, 30, 34), rgb(250, 250, 250) },
})

-- Bonus: Arizona canyon
theme("canyon", {
	Name = "Red Rock Canyon", Icon = "🏜️", Temp = 34, Sky = "sunset",
	SkyTweak = { ClockTime = 17.4, Shift = rgb(255, 160, 100), AtmoColor = rgb(255, 190, 150), Haze = 1.4 },
	Ground = rgb(196, 112, 72), GroundMaterial = Enum.Material.Sandstone, RunoffKind = "asphalt",
	Props = { rock = 4, cactus = 3, agave = 1 },
	Arch = { ranch_house = 2, water_tower = 1, oil_pump = 1 },
	Layout = "sparse", Landmarks = { "rock_arches", "western_town", "tower_floodlit" }, Life = { "birds", "planes" },
	Ambient = "sand", Horizon = "mesas", Accent = rgb(255, 120, 50), KerbA = rgb(230, 60, 30),
	Fans = { rgb(255, 120, 50), rgb(40, 90, 170), rgb(250, 250, 250), rgb(120, 60, 40) },
})
-- Bonus: Norway fjord
theme("fjord", {
	Name = "Fjord Ring", Icon = "⛰️", Temp = 12,
	SkyTweak = { ClockTime = 10.6, Density = 0.2, Haze = 0.9, AtmoColor = rgb(200, 222, 245), Cloud = 0.5 },
	Props = { tree_pine = 7, rock = 2 },
	Arch = { chalet = 3, cottage = 2, church = 0.4 },
	Layout = "rural", Landmarks = { "lake", "stave_church", "fishing_village", "waterfall" }, Life = { "boats", "birds" },
	Ambient = "mist", Horizon = "snowmountains", Accent = rgb(60, 170, 255), KerbA = rgb(30, 110, 230), Water = rgb(30, 90, 130),
	Fans = { rgb(200, 20, 40), rgb(250, 250, 250), rgb(20, 40, 120) },
})
-- Bonus: Morocco oasis
theme("oasis", {
	Name = "Sahara Oasis", Icon = "🐪", Temp = 36, Sky = "hot",
	SkyTweak = { ClockTime = 14.8, AtmoColor = rgb(250, 225, 180), Haze = 2.2 },
	Ground = rgb(226, 190, 128), GroundMaterial = Enum.Material.Sand, RunoffKind = "asphalt",
	Props = { dune = 4, palm = 3, cactus = 1 },
	Arch = { wind_tower_house = 2, dome_pavilion = 1 },
	Layout = "sparse", Landmarks = { "pyramid_big", "oasis", "kasbah", "souk" }, Life = { "planes" },
	Ambient = "sand", Horizon = "mesas", HorizonColor = rgb(225, 175, 110), Accent = rgb(255, 170, 40), KerbA = rgb(200, 40, 40),
	Fans = { rgb(200, 30, 40), rgb(0, 120, 60), rgb(250, 250, 250) },
})
-- Bonus: Tokyo bay at night
theme("bay", {
	Name = "Neon Bay", Icon = "🗼", Temp = 22, Sky = "night",
	SkyTweak = { Tint = rgb(245, 238, 255), AtmoColor = rgb(80, 70, 140), AtmoDecay = rgb(40, 30, 100) },
	Barrier = "street", Ground = rgb(80, 82, 92), GroundMaterial = Enum.Material.Pavement,
	Props = { tree_cherry = 2, lantern = 2 },
	Arch = { neon_block = 4, office_tower = 3, apartment = 2 },
	Layout = "city", Landmarks = { "sea", "red_tower", "rainbow_bridge", "neon_alley", "ferris" }, Life = { "boats", "planes" },
	Fireworks = true, Horizon = "skyline", Accent = rgb(255, 60, 200), KerbA = rgb(255, 40, 160), Water = rgb(20, 60, 110),
	Fans = { rgb(250, 250, 250), rgb(220, 30, 50), rgb(255, 60, 200) },
})
-- Bonus: Scottish highlands
theme("loch", {
	Name = "Highland Loch", Icon = "🏰", Temp = 11, Sky = "overcast", Weather = "rain",
	SkyTweak = { Density = 0.38, Haze = 2.4, AtmoColor = rgb(195, 205, 205) },
	Props = { tree_pine = 4, rock = 3, hedge = 1 },
	Arch = { cottage = 3, church = 0.5, barn = 1 },
	Layout = "rural", Landmarks = { "lake", "loch_monster", "highland_castle", "standing_stones", "highland_cows" }, Life = { "birds" },
	Horizon = "mountains", HorizonColor = rgb(110, 120, 95), Accent = rgb(80, 160, 110), Water = rgb(40, 70, 90),
	Fans = { rgb(30, 60, 160), rgb(250, 250, 250), rgb(40, 110, 60) },
})

return Themes
