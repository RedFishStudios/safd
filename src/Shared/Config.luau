-- Shared constants, readable from both server and client.
-- Tuning knobs for the whole game live here.

local Config = {}

Config.GameName = "SAFD"

-- Movement / training -------------------------------------------------------------------------------------------
Config.BaseWalkSpeed = 16 -- walk speed with 0 speed points (Shared/Progression maps points to walk speed)
Config.TreadmillRunAnimSpeed = 1.25
Config.TreadmillPadLength = 13.42 -- treadmills are scaled so their body is this long (reference TreadmillBottom pad)
Config.SlowModeWalkSpeed = 16 -- HUD "Slow Mode" switch caps walking at this speed

-- Double jump / slide (R6 animations uploaded to the owner's account) -------------------------------------------
Config.RunAnimation = "rbxassetid://132922296070553" -- replaces the R6 walk/run (Animate run + walk)
Config.JumpAnimation = "rbxassetid://99865393139720" -- first jump: upright, arms raised outwards
Config.FallAnimation = "rbxassetid://94199200189504" -- airborne hold of the jump pose
Config.DoubleJumpAnimation = "rbxassetid://88651942165023" -- second jump: full 360 forward somersault
Config.SlideAnimation = "rbxassetid://112684077516999" -- low feet-first slide, held while Ctrl is down
Config.DoubleJumpPower = 55 -- upward velocity of the second jump
Config.SlideBoost = 1.5 -- speed multiplier at the start of a slide...
Config.SlideBoostTime = 0.6 -- ...for this long; then you keep sliding at your normal speed while you hold Ctrl
Config.SlideCooldown = 0.25

-- Bases ---------------------------------------------------------------------------------------------------------
Config.StartingBase = "BaseLvl1" -- template inside Workspace.Bases (moved to ServerStorage at runtime)

-- Carrying / disaster -------------------------------------------------------------------------------------------
Config.MaxCarry = 10
Config.CarryHeight = 2.4 -- each carried animal is scaled to this height on the head stack
Config.WallStartDistance = 70 -- how far behind the player the wall appears
Config.SlowDuration = 2 -- seconds slowed after touching an obstruction
Config.SlowMultiplier = 0.45
Config.ToppleInterval = 0.7 -- hillside scenery shakes, leans and falls as you approach
Config.TrailToppleInterval = 5 -- occasionally something on the trail itself falls (non-solid)
Config.ToppleRadius = 80
Config.CrackInterval = 1.4
Config.ProjectileInterval = { 0.35, 0.65 } -- seconds between gameplay projectiles falling into the path
Config.RollerInterval = { 2.6, 3.8 } -- seconds between rolling hazards that cross the path (jump them)
Config.FlyerInterval = { 2.6, 3.8 } -- wait after a head-height flyer (slide under it) before the next crossing
Config.MaxTelegraphs = 6 -- never more than this many red target circles at once
Config.SpectacleInterval = { 0.18, 0.35 } -- background debris tumbling down the hills (harmless)
Config.TelegraphTime = 1.1 -- red circle fill time before a projectile lands
Config.HazardHitSlow = 2 -- seconds slowed when hit by a projectile / roller
-- Disaster music (Creator Store, APM Music, free for any experience). "Race to the Artifact (A)": starts
-- straight away with staccato strings, choir and huge percussion. Preloaded at join so it starts instantly.
Config.DisasterMusicId = "rbxassetid://9043371402"
Config.DisasterMusicVolume = 2.4 -- loud (x the Music slider)
Config.DisasterMusicStart = 0 -- seconds into the track to start from
-- Disaster sound effects (Pro Sound Effects, free).
Config.Sounds = {
	Impact = "rbxassetid://9118588165", -- rock drop and break
	RockHit = "rbxassetid://9118608146",
	Rubble = "rbxassetid://9118691819",
	WoodCrack = "rbxassetid://9126240449",
	HeavyThud = "rbxassetid://9113805612",
	Rumble = "rbxassetid://9112887827", -- deep rumbling loop under the whole escape
}
Config.HouseIcon = "rbxassetid://102462759228425" -- white house silhouette, tinted on the base sign

-- Wild animals ---------------------------------------------------------------------------------------------------
Config.WildAnimalsPerBiome = 5 -- (fewer, spread out)
Config.WildMinSpacing = 60 -- (well spread out; the big ones need room)
Config.WildRespawnTime = { 8, 16 }
Config.AnimalWanderSpeed = 4
Config.AnimalWanderRadius = 10
-- Most rigs face -Z. If animals walk backwards in the base, set this to true.
Config.AnimalFacingFlip = false

-- UI pack hooks -------------------------------------------------------------------------------------------------
Config.SellValueSeconds = 20 -- selling an animal pays this many seconds of its income
Config.IndexRewardSeconds = 120 -- Index "Claim!" pays this many seconds of the animal's income...
Config.IndexRewardSpeed = { 1, 2, 4, 7, 12 } -- ...plus speed by rarity
Config.FreeItemSpeed = 100 -- "Like + join the group" free reward (once per player)
Config.GroupId = 0 -- set to your group id to require membership for the free item
-- Trails bought with in-game money (Trails Shop). Multiplier applies to the speed points the treadmill gives.
Config.Trails = {
	{ Name = "White Trail", Price = 500, Multiplier = 1.1, Color = Color3.fromRGB(255, 255, 255) },
	{ Name = "Blue Trail", Price = 2500, Multiplier = 1.15, Color = Color3.fromRGB(60, 150, 255) },
	{ Name = "Green Trail", Price = 10000, Multiplier = 1.2, Color = Color3.fromRGB(80, 230, 90) },
	{ Name = "Purple Trail", Price = 40000, Multiplier = 1.3, Color = Color3.fromRGB(180, 80, 255) },
	{ Name = "Red Trail", Price = 150000, Multiplier = 1.4, Color = Color3.fromRGB(255, 60, 60) },
	{ Name = "Golden Trail", Price = 500000, Multiplier = 1.5, Color = Color3.fromRGB(255, 200, 40) },
	{ Name = "Rainbow Trail", Price = 2000000, Multiplier = 1.65, Rainbow = true },
	{ Name = "Void Trail", Price = 8000000, Multiplier = 1.8, Color = Color3.fromRGB(40, 0, 70) },
	{ Name = "Secret Trail", Price = 30000000, Multiplier = 2, Color = Color3.fromRGB(0, 255, 200) },
	{ Name = "Nova Trail", Price = 100000000, Multiplier = 2.25, Color = Color3.fromRGB(255, 120, 220) },
	{ Name = "Celestial Trail", Price = 400000000, Multiplier = 2.5, Color = Color3.fromRGB(150, 220, 255) },
}
-- Developer product ids for Robux buttons in the pack (0 = not set up yet; the button says "Coming soon").
-- Keys are the card / button names in the GUIs. Grants are defined in ShopService.
Config.Products = {
	Card_Small1 = 0,
	Card_Small2 = 0,
	Card_Small3 = 0,
	Card_Small4 = 0,
	Card_BestValue = 0,
	Card_Upgrade = 0,
	Card_Double = 0,
	["2xSpeed"] = 0,
	OfflineX2 = 0,
}

-- Admins (in-game admin panel, toggle with K). The experience owner is always an admin.
Config.Admins = { 418337702 }

-- Data ----------------------------------------------------------------------------------------------------------
Config.DataStoreName = "SAFD_PlayerData_v1"
Config.AutosaveInterval = 60

-- Rarities (index 1..5, lowest to highest) -----------------------------------------------------------------------
Config.Rarities = {
	{ Name = "Common", Color = Color3.fromRGB(200, 200, 200), Height = 9, Income = 1, Weight = 50 },
	{ Name = "Uncommon", Color = Color3.fromRGB(85, 220, 95), Height = 12, Income = 3, Weight = 25 },
	{ Name = "Rare", Color = Color3.fromRGB(60, 150, 255), Height = 17, Income = 8, Weight = 14 },
	{ Name = "Epic", Color = Color3.fromRGB(180, 80, 255), Height = 32, Income = 20, Weight = 8 },
	{ Name = "Legendary", Color = Color3.fromRGB(255, 190, 40), Height = 58, Income = 50, Weight = 1 },
}

-- Biomes, ordered from nearest to the bases to furthest. Animals are listed Common -> Legendary.
-- Model names must match the animal models inside ReplicatedStorage.Assets.
Config.Biomes = {
	{
		Name = "Grassy Meadows",
		Level = "Level1_Grassy_Meadows",
		Track = "Level1_track",
		WallSpeed = 18, -- studs/s (the reference game's chase speed for this area)
		RecommendedSpeed = 5, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Easy", Emoji = "😀", Color = Color3.fromRGB(190, 255, 60) },
		IncomeMultiplier = 1,
		WallMaterial = Enum.Material.Grass,
		WallColor = Color3.fromRGB(80, 160, 70),
		Animals = { "Chicken", "Bunny", "Horse", "Griffin", "Pegasus" },
	},
	{
		Name = "Snowy Tundra",
		Level = "Level2_Snowy_Tundra",
		Track = "Level2_track",
		WallSpeed = 24, -- studs/s (the reference game's chase speed for this area)
		RecommendedSpeed = 1e3, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Medium", Emoji = "😟", Color = Color3.fromRGB(255, 170, 40) },
		IncomeMultiplier = 2.5,
		WallMaterial = Enum.Material.Snow,
		WallColor = Color3.fromRGB(230, 240, 255),
		Animals = { "Puffin", "Yak", "PolarBear", "Mammoth", "Fenrir" },
	},
	{
		Name = "Sandy Dunes",
		Level = "Level3_Sandy_Dunes",
		Track = "Level3_track",
		WallSpeed = 30, -- studs/s (the reference game's chase speed for this area)
		RecommendedSpeed = 5e4, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Hard", Emoji = "😠", Color = Color3.fromRGB(255, 90, 60) },
		IncomeMultiplier = 6,
		WallMaterial = Enum.Material.Sand,
		WallColor = Color3.fromRGB(225, 195, 135),
		Animals = { "Meerkat", "FennecFox", "Cobra", "Manticore", "Sphinx" },
	},
	{
		Name = "Fiery Hellscape",
		Level = "Level4_Fiery_Hellscape",
		Track = "Level4_track",
		WallSpeed = 37, -- studs/s (the reference game's chase speed for this area)
		RecommendedSpeed = 1e6, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Expert", Emoji = "😤", Color = Color3.fromRGB(230, 40, 60) },
		IncomeMultiplier = 15,
		WallMaterial = Enum.Material.CrackedLava,
		WallColor = Color3.fromRGB(255, 95, 35),
		Animals = { "Salamander", "Hellhound", "Cerberus", "Dragon", "Phoenix" },
	},
	{
		Name = "Toxic Wasteland",
		Level = "Level5_Toxic_Wasteland",
		Track = "Level5_track",
		WallSpeed = 45, -- studs/s (the reference game's chase speed for this area)
		RecommendedSpeed = 1e7, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Insane", Emoji = "🤯", Color = Color3.fromRGB(190, 70, 255) },
		IncomeMultiplier = 35,
		WallMaterial = Enum.Material.Mud,
		WallColor = Color3.fromRGB(120, 200, 40),
		Animals = { "Toad", "Beetle", "GiantSpider", "Chupacabra", "Hydra" },
	},
	{
		Name = "Candyland",
		Level = "Level6_Candyland",
		Track = "Level6_track",
		WallSpeed = 54, -- studs/s (the reference game's chase speed for this area)
		RecommendedSpeed = 1.5e8, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Extreme", Emoji = "😈", Color = Color3.fromRGB(255, 60, 170) },
		IncomeMultiplier = 80,
		WallMaterial = Enum.Material.SmoothPlastic,
		WallColor = Color3.fromRGB(255, 140, 205),
		Animals = { "Hamster", "Axolotl", "Flamingo", "Unicorn", "Qilin" },
	},
}

-- Disaster hazards per biome (index matches Config.Biomes). Projectiles arc in from the sides onto a red
-- target circle; rollers sweep across the whole path. Kinds are built in Client/Hazards.
Config.HazardThemes = {
	-- Grassy Meadows: rocks, falling trees, hay
	{
		Projectiles = { "Boulder", "FallingLog", "HayBale" },
		Rollers = { "Log", "HayBale" },
		Flyers = { "Log", "Boulder" },
	},
	-- Snowy Tundra: no rocks, all snow and ice
	{
		Projectiles = { "Snowball", "IceChunk", "Icicle" },
		Rollers = { "Snowball", "Avalanche" },
		Flyers = { "Snowball", "IceChunk" },
	},
	-- Sandy Dunes: sandstone, cacti, tumbleweeds
	{
		Projectiles = { "Sandstone", "Cactus" },
		Rollers = { "StoneWheel", "Tumbleweed" },
		Flyers = { "Sandstone", "Tumbleweed" },
	},
	-- Fiery Hellscape: meteors and lava
	{
		Projectiles = { "Meteor", "LavaBomb" },
		Rollers = { "LavaRock" },
		Flyers = { "Fireball" },
	},
	-- Toxic Wasteland: acid and toxic barrels
	{
		Projectiles = { "AcidBlob", "ToxicBarrel" },
		Rollers = { "Barrel" },
		Flyers = { "AcidBlob", "ToxicBarrel" },
	},
	-- Candyland: sweets
	{
		Projectiles = { "Gumball", "Cupcake", "Lollipop" },
		Rollers = { "CandyCane", "Donut" },
		Flyers = { "Gumball", "Donut" },
	},
}

local DISPLAY_NAMES = {
	PolarBear = "Polar Bear",
	Mammoth = "Woolly Mammoth",
	FennecFox = "Fennec Fox",
	GiantSpider = "Giant Spider",
	Phoenix = "Fire Phoenix",
}

-- Uploaded animation ids (owned by the experience owner), used in Studio and live servers.
-- Animals sharing a rig share ids. Studio falls back to the KeyframeSequences for any id left empty.
local function anim(idle: number, walk: number)
	return { Idle = `rbxassetid://{idle}`, Walk = `rbxassetid://{walk}` }
end
local FOUR_LEGS = anim(107047039655505, 133468089622097) -- Unicorn rig
local TWO_LEGS = anim(128488789733107, 131220039691914) -- Hamster rig
local QUAD = anim(76910213934059, 96372237104795) -- Meerkat rig (Animal Pack 5.0 quadrupeds)
local LEGS4 = anim(78325691204179, 111773581225310) -- Cerberus rig
local BIRD = anim(116801412086095, 135645695133496) -- Flamingo rig
Config.AnimationIds = {
	-- Grassy Meadows
	Chicken = TWO_LEGS,
	Bunny = FOUR_LEGS,
	Horse = FOUR_LEGS,
	Griffin = anim(110576759629844, 110768971268137),
	Pegasus = anim(133700678986038, 77711137970691),
	-- Snowy Tundra
	Puffin = BIRD,
	Yak = anim(114007678779447, 105125511949192),
	PolarBear = QUAD,
	Mammoth = QUAD,
	Fenrir = anim(137706311104273, 88806756385689),
	-- Sandy Dunes
	Meerkat = QUAD,
	FennecFox = QUAD,
	Cobra = anim(117159496322762, 118960125285350),
	Manticore = anim(81285761183513, 76465555564567),
	Sphinx = LEGS4,
	-- Fiery Hellscape
	Salamander = anim(97269541192167, 128827780676939),
	Hellhound = anim(79130407766429, 137099021957203),
	Cerberus = LEGS4,
	Dragon = anim(126212241364312, 139527452472057),
	Phoenix = anim(91548404679679, 88369132667768),
	-- Toxic Wasteland
	Toad = anim(113750747554980, 78879898975447),
	Beetle = anim(77578666401450, 80116124101527),
	GiantSpider = anim(120837733110630, 74922974739748),
	Chupacabra = anim(126559332319203, 123146221142161),
	Hydra = anim(86190719617424, 88126570883808),
	-- Candyland
	Hamster = TWO_LEGS,
	Axolotl = anim(74824387738129, 78485509879675),
	Flamingo = BIRD,
	Unicorn = FOUR_LEGS,
	Qilin = anim(100656739982577, 110997990188334),
}

-- Derived: Config.Animals[id] = { Id, Name, Biome, Rarity, Income } ---------------------------------------------
Config.Animals = {}
for biomeIndex, biome in Config.Biomes do
	for rarityIndex, id in biome.Animals do
		Config.Animals[id] = {
			Id = id,
			Name = DISPLAY_NAMES[id] or id,
			Biome = biomeIndex,
			Rarity = rarityIndex,
			Income = Config.Rarities[rarityIndex].Income * biome.IncomeMultiplier,
		}
	end
end

return Config
