-- Shared constants, readable from both server and client.
-- Tuning knobs for the whole game live here.

local Config = {}

Config.GameName = "Save Eggs from Disasters"

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
Config.SlideAnimation = "rbxassetid://112684077516999" -- low feet-first slide, held while Shift is down
Config.DoubleJumpPower = 55 -- upward velocity of the second jump
Config.SlideBoost = 1.5 -- speed multiplier at the start of a slide...
Config.SlideBoostTime = 0.6 -- ...for this long; then you keep sliding at your normal speed while you hold Shift
Config.SlideCooldown = 0.25

-- Bases ---------------------------------------------------------------------------------------------------------
Config.StartingBase = "BaseLvl1" -- template inside Workspace.Bases (moved to ServerStorage at runtime)

-- Carrying / disaster -------------------------------------------------------------------------------------------
Config.MaxCarry = 10
Config.CarryHeight = 2.4 -- each carried animal is scaled to this height on the head stack
-- The wall chases at this share of the biome's WallSpeed (user, 2026-11-20: the run home is open now, with more
-- obstacles: going round a rock or a wall gap costs time, so the wall gives you more slack than the reference's 4 studs/s)
-- (user 2026-11-21: "with 200 speed I can still pass the ice place with ease: it should follow the recommended speed".
-- Shared/Progression's walk-speed curve puts you only a little faster than WallSpeed at the RecommendedSpeed and well
-- under it below that. The obstacles cost about a fifth of your speed (a bot playtest at 1.1K speed in the Tundra
-- averaged 25 studs/s at WalkSpeed 32), so the wall runs at 0.8 of WallSpeed: at the recommended speed you get home,
-- well under it you don't.)
Config.RunWallFactor = 0.8
Config.WallStartDistance = 40 -- right at the far end you get a head start: the wall waits until it's this far back
Config.WallCatchUpGap = 45 -- while it's further behind you than this, the wall surges in faster to close the gap
Config.WallCatchUpRate = 0.6 -- extra studs/s per stud of gap past WallCatchUpGap
-- Starting the chase right at the far end (where the wall forms): it forms at least this far behind you instead (it
-- used to appear on top of you and kill you), and waits this many extra seconds before it moves (only then)
Config.WallSpawnClearance = 30
Config.WallFarEndHeadStart = 2.5
Config.PlayAreaX = { -219.5, 203.5 } -- inside faces of Workspace.SAFD_Boundaries' side walls (the biomes)
-- the run home: LUCK badges (Client/RunCourse) MULTIPLY your luck (user 2026-11-21: "x3 then x3 should be x9"): x2,
-- x3, x4, x5, starting from x1. Luck raises the odds of hatching a rarer animal from the egg you bring home (never
-- income). Net.RunRing sends the badge's factor.
-- (no real cap: user 2026-11-20, "your multiplier is stuck at 15x, even though I get way more"; this one only keeps
-- the number finite)
Config.RunMultiplierCap = 1e15
Config.RunRingValues = { 2, 3, 4, 5 }
Config.RunRingColors = {
	[2] = Color3.fromRGB(80, 255, 120),
	[3] = Color3.fromRGB(80, 180, 255),
	[4] = Color3.fromRGB(200, 110, 255),
	[5] = Color3.fromRGB(255, 200, 40),
}
Config.SlowDuration = 2 -- seconds slowed after touching an obstruction
Config.SlowMultiplier = 0.45
Config.ToppleInterval = 1e9 -- (off: Disaster's hillside topple; Client/RunCourse knocks over the map's trees instead)
Config.TrailToppleInterval = 1e9 -- (off: nothing falls onto the lane by itself any more)
Config.ToppleRadius = 80
Config.CrackInterval = 1.4
-- (2026-11-20: one every 1-1.8 s, at most 3 circles at once, half aimed where you will be, never on top of a barrier or
-- trench; each shows the side it comes from with an arrow on the ground, and DODGE! at the top of the screen)
Config.ProjectileInterval = { 0.6, 1.1 } -- seconds between gameplay projectiles (user 2026-11-20: "a lot more projectiles")
Config.ProjectileVolleyChance = 0.35 -- chance a second projectile (just ahead of you) comes down with one
Config.RollerInterval = { 4.5, 6 } -- seconds between rolling hazards that cross the path (jump them)
Config.FlyerInterval = { 4.5, 6 } -- wait after a head-height flyer (slide under it) before the next crossing
Config.BarrageInterval = { 11, 15 } -- a volley across the path that always leaves a third of it open
Config.MaxTelegraphs = 5 -- never more than this many red target circles at once
Config.SpectacleInterval = { 1e9, 1e9 } -- (off: background debris tumbling down the hills only cluttered the view)
Config.TelegraphTime = 1.4 -- red circle fill time before a projectile lands (time to see it and get out of the way)
Config.HazardHitSlow = 1.2 -- seconds slowed when hit by a projectile (short: there are lots of them now)
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

-- Wild eggs (2026-11-20: the biomes hold eggs, not animals) ------------------------------------------------------
-- One egg per biome (Shared/EggFactory builds it). Rarity: an index into Config.Rarities, for the egg's label and
-- size. Height: how tall it stands in the wild (the Mythic one is enormous). Count: how many lie in the biome at once.
-- Hatching (Server/AnimalService) picks one of the biome's 8 animals by Config.hatchWeights(biome, luck).
Config.Eggs = {
	{ Name = "Meadow Egg", Rarity = 1, Height = 4.5, Count = 9 },
	{ Name = "Frostbite Egg", Rarity = 2, Height = 6.5, Count = 8 },
	{ Name = "Pharaoh Egg", Rarity = 3, Height = 9, Count = 7 },
	{ Name = "Inferno Egg", Rarity = 4, Height = 13, Count = 6 },
	{ Name = "Radioactive Egg", Rarity = 5, Height = 19, Count = 5 },
	{ Name = "Sugar Rush Egg", Rarity = 6, Height = 30, Count = 4 },
}
-- each biome's two egg designs have their own names (Shared/EggFactory design 1 / 2; only the look: same rarity, same
-- hatch odds; user 2026-11-22)
Config.EggNames = {
	{ "Meadow Egg", "Daisy Egg" },
	{ "Frostbite Egg", "Snowball Egg" },
	{ "Pharaoh Egg", "Sunset Dune Egg" },
	{ "Inferno Egg", "Dragon Egg" },
	{ "Radioactive Egg", "Hazmat Egg" },
	{ "Sugar Rush Egg", "Sundae Egg" },
}
function Config.eggName(biome: number, design: number?): string
	local names = Config.EggNames[biome]
	local egg = Config.Eggs[biome]
	return (names and names[design or 1]) or (egg and egg.Name) or "Egg"
end
Config.CarryEggHeight = { 2.4, 2.7, 3, 3.3, 3.6, 4 } -- each carried egg on the head stack, by biome
Config.EggRespawnTime = { 6, 12 }
-- Hatch chances (reworked 2026-11-20, user: "with 10x you are bound to get at least epic / legendary ... like Steal an
-- Egg"; a 16x run that still hatched Candyland's commonest animal "will demotivate kids"). Two parts:
--   * a floor: the more luck, the higher the lowest rarity an egg can hatch (Config.LuckFloors): from x10 every egg
--     hatches an Epic or better, from x15 a Legendary or better
--   * above the floor, each animal's weight is its rarity's Weight (Config.HatchTiers; the second animal of the same
--     rarity in a biome gets 80% of it) x luck ^ (LuckBoost x how many rarities it is above the lowest allowed one):
--     luck tilts the odds further towards the rarer ones
-- Config.hatchChances(biome, luck) gives every animal's % (adding up to 100), shown on the hatch screen.
Config.HatchTiers = {
	[1] = 100, -- Common
	[2] = 40, -- Uncommon
	[3] = 15, -- Rare
	[4] = 5, -- Epic
	[5] = 1.5, -- Legendary
	[6] = 0.4, -- Mythic
	[7] = 0.1, -- Cosmic
	[8] = 0.03, -- Secret
	[9] = 0.01, -- Eternal
}
-- (2026-11-20, user: "why is it so easy to get legendary in meadow ... apply the same progression as Steal an Egg"):
-- luck only tilts the odds a little, like Steal an Egg's x2 / x3 luck (Meadow Legendary ~0.5% at x1, ~1.4% at x6, ~2.8% at
-- x25), and nothing is ever guaranteed (no floors)
Config.LuckBoost = 0.15 -- (unused now: see LuckMaxBoost)
-- the luck a good run collects in each biome (runs from further out are longer: more badges, bigger ones)
-- (2026-11-21: badges multiply now, so a run's luck grows fast; these are about what a kid's good run collects,
-- ~70% of the badges: Meadow ~4 x2 badges, Tundra ~7 (x2/x3), Dunes ~10, Hellscape ~12, Toxic ~14, Candyland ~16
-- (x2..x5). Luck counts on a log scale against them: half way there (in multiplying) is half the boost.)
Config.BiomeLuck = { 10, 1e3, 5e4, 1e6, 1e7, 5e7 }
Config.LuckMaxBoost = 3 -- a full run: the biome's rarest animal x3 as likely (Steal an Egg's luck is x2-x3)
Config.LuckOverBoost = 1.5 -- an exceptional run counts up to 1.5 full runs (x4)
-- { from this much luck, the lowest rarity an egg can hatch } (highest first)
Config.LuckFloors = {} -- (none any more: see LuckBoost)
Config.OldLuckFloors = {
	{ 60, 8 }, -- x60: Secret or better
	{ 40, 7 }, -- x40: Cosmic or better
	{ 25, 6 }, -- x25: Mythic or better
	{ 15, 5 }, -- x15: Legendary or better
	{ 10, 4 }, -- x10: Epic or better
	{ 6, 3 }, -- x6: Rare or better
	{ 3, 2 }, -- x3: Uncommon or better
}
-- the biome's animals and their chances in % (adding up to 100) at this much luck
function Config.hatchChances(biome: number, luck: number): ({ string }, { number })
	local b = Config.Biomes[biome]
	local l = math.clamp(luck, 1, Config.RunMultiplierCap)
	local floor = 1
	for _, f in Config.LuckFloors do
		if l >= f[1] then
			floor = f[2]
			break
		end
	end
	-- (never above the biome's rarest animal)
	local top = 0
	for _, r in b.Rarities do
		top = math.max(top, r)
	end
	floor = math.min(floor, top)
	local lowest = math.huge
	for _, r in b.Rarities do
		if r >= floor then
			lowest = math.min(lowest, r)
		end
	end
	local chances, total = {}, 0
	local seen: { [number]: number } = {}
	for i, r in b.Rarities do
		seen[r] = (seen[r] or 0) + 1
		if r < floor then
			chances[i] = 0
		else
			-- (Steal an Egg's own drop rate for this slot: Config.BaseHatchChances)
			local base = Config.BaseHatchChances[biome]
			local w = if base and base[i] then base[i] else Config.HatchTiers[r] * (if seen[r] == 1 then 1 else 0.8)
			-- luck helps, it isn't everything (user 2026-11-20, "like Steal an Egg"): measured against what a good run in THIS
			-- biome collects (Config.BiomeLuck: a short Meadow run can't reach x10), a full run makes the rarest animal
			-- LuckMaxBoost times likelier and the ones between it and the commonest a bit less; a great run up to
			-- LuckOverBoost of that
			local span = math.max(top - lowest, 1)
			local reach = Config.BiomeLuck[biome] or 10
			local e = math.clamp(math.log(l) / math.log(math.max(reach, 2)), 0, Config.LuckOverBoost)
			local m = 1 + (Config.LuckMaxBoost - 1) * e
			chances[i] = w * m ^ ((r - lowest) / span)
		end
		total += chances[i]
	end
	for i in chances do
		chances[i] = chances[i] / total * 100
	end
	return b.Animals, chances
end
Config.hatchWeights = Config.hatchChances

-- Wild animals (the base animals' wander) ------------------------------------------------------------------------
Config.AnimalWanderSpeed = 4
Config.AnimalWanderRadius = 10
-- Most rigs face -Z. If animals walk backwards in the base, set this to true.
Config.AnimalFacingFlip = false

-- UI pack hooks -------------------------------------------------------------------------------------------------
Config.SellValueSeconds = 20 -- selling an animal pays this many seconds of its income
-- Completing a biome's Index (all 8 animals found) pays one extra cash reward, like Throw Food for Animals' "complete a
-- biome's collection, claim an extra cash reward" (user 2026-11-22): 100 x the biome's 8 animals' income added up
Config.BiomeCompleteSeconds = 100
function Config.biomeCompleteReward(biome: number): number
	local total = 0
	for _, id in Config.Biomes[biome].Animals do
		local info = Config.Animals[id]
		total += if info then info.Income else 0
	end
	return total * Config.BiomeCompleteSeconds
end
Config.IndexRewardSeconds = 100 -- (Break and Steal an Egg: discovery pays 100x income) Index "Claim!" pays this many seconds of the animal's income...
Config.IndexRewardSpeed = { 1, 2, 4, 7, 12, 20, 35, 60, 100 } -- ...plus speed by rarity
Config.FreeItemSpeed = 10000 -- "Like + join the group" free reward (once per player): +10K speed like Steal an Egg / Break and Steal an Egg
Config.GroupId = 0 -- set to your group id to require membership for the free item
-- Trails bought with in-game money (Trails Shop). Multiplier applies to the speed points the treadmill gives.
-- The Trail Shop (the yellow tent at spawn; user, 2026-11-20: "import the trails in the trail shop" from "[NEW] Feed and
-- Rob Animals", Config/Trails: the same trails, names, pictures, looks and multipliers). Index = the TrailsShop card's
-- TrailIndex. Multiplier: every treadmill payout x this while it's equipped (Server/ShopService refreshMultiplier ->
-- the SpeedMultiplier attribute -> Server/TrainingService). Price: in this game's money, about one trail per biome and
-- the last ones goals for after Candyland. Look: how Server/ShopService draws it (a bright core inside a soft glow,
-- colour from Colors[1] at your back to the last at the tail; Sparks / Stars / Clouds behind you while you run; Light
-- around you).
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
-- (prices = "[NEW] Feed and Rob Animals" Config/Trails after its price curve, user 2026-11-21: "should be correct")
Config.Trails = {
	{
		Index = 1,
		Name = "Pearl Trail",
		Art = 75219173050992,
		Rarity = "Common",
		Multiplier = 2,
		Price = 500,
		Look = { Colors = { rgb(255, 255, 255), rgb(205, 215, 235) }, Core = 0.35 },
	},
	{
		Index = 2,
		Name = "Sapphire Trail",
		Art = 102798911361671,
		Rarity = "Rare",
		Multiplier = 8,
		Price = 210000,
		Look = {
			Colors = { rgb(70, 155, 255), rgb(35, 115, 250), rgb(20, 70, 225) },
			Glow = rgb(45, 135, 255),
			Core = 0.25,
			Bright = 1.05,
			GlowBright = 1,
			GlowEmission = 0.25,
			GlowAlpha = 0.5,
		},
	},
	{
		Index = 3,
		Name = "Emerald Trail",
		Art = 109893441076339,
		Rarity = "Uncommon",
		Multiplier = 4,
		Price = 8000,
		Look = {
			Colors = { rgb(60, 245, 125), rgb(25, 220, 95), rgb(0, 165, 70) },
			Glow = rgb(35, 235, 105),
			Core = 0.25,
			Bright = 1.05,
			GlowBright = 1,
			GlowEmission = 0.25,
			GlowAlpha = 0.5,
		},
	},
	{
		Index = 4,
		Name = "Amethyst Trail",
		Art = 83109490181372,
		Rarity = "Epic",
		Multiplier = 16,
		Price = 10000000,
		Look = {
			Colors = { rgb(210, 75, 255), rgb(180, 45, 245), rgb(130, 25, 215) },
			Glow = rgb(195, 65, 255),
			Core = 0.25,
			Bright = 1.05,
			GlowBright = 1,
			GlowEmission = 0.25,
			GlowAlpha = 0.5,
			Sparks = { rgb(230, 160, 255) },
		},
	},
	{
		Index = 5,
		Name = "Ruby Trail",
		Art = 115086386570140,
		Rarity = "Legendary",
		Multiplier = 40,
		Price = 390000000,
		Look = {
			Colors = { rgb(255, 70, 70), rgb(240, 30, 40), rgb(180, 8, 28) },
			Glow = rgb(255, 45, 45),
			Core = 0.25,
			Bright = 1.05,
			GlowBright = 1,
			GlowEmission = 0.25,
			GlowAlpha = 0.5,
			Sparks = { rgb(255, 130, 115), rgb(255, 65, 55) },
		},
	},
	{
		Index = 6,
		Name = "Gilded Trail",
		Art = 102959921396871,
		Rarity = "Legendary",
		Multiplier = 100,
		Price = 19000000000,
		Look = {
			Colors = { rgb(255, 255, 225), rgb(255, 215, 70), rgb(230, 140, 20) },
			Sparks = { rgb(255, 235, 130), rgb(255, 255, 255) },
		},
	},
	{
		Index = 7,
		Name = "Prism Trail",
		Art = 82285262574478,
		Rarity = "Mythic",
		Multiplier = 250,
		Price = 700000000000,
		Look = {
			Colors = {
				rgb(255, 70, 70),
				rgb(255, 170, 40),
				rgb(255, 240, 70),
				rgb(70, 230, 100),
				rgb(60, 160, 255),
				rgb(180, 90, 255),
			},
			Sparks = { rgb(255, 120, 120), rgb(255, 240, 120), rgb(120, 200, 255) },
		},
	},
	{
		Index = 8,
		Name = "Abyss Trail",
		Art = 101009720763199,
		Rarity = "Cosmic",
		Multiplier = 600,
		Price = 25000000000000,
		Look = {
			Colors = { rgb(210, 140, 255), rgb(90, 25, 160), rgb(20, 5, 40) },
			Glow = rgb(150, 60, 255),
			Core = 0,
			Sparks = { rgb(210, 150, 255), rgb(255, 255, 255) },
		},
	},
	{
		Index = 9,
		Name = "Zebra Trail",
		Art = 108025793375909,
		Rarity = "Secret",
		Multiplier = 1500,
		Price = 730000000000000,
		Look = {
			Colors = { rgb(255, 255, 255), rgb(14, 14, 16) },
			Stripes = 10,
			Core = 0,
			Bright = 1,
			Glow = rgb(255, 255, 255),
			GlowBright = 1,
			GlowAlpha = 0.84,
			Sparks = { rgb(255, 255, 255), rgb(20, 20, 22) },
		},
	},
	{
		Index = 10,
		Name = "Nebula Trail",
		Art = 82690147295681,
		Rarity = "Celestial",
		Multiplier = 4000,
		Price = 8700000000000000,
		Look = {
			Colors = { rgb(70, 150, 255), rgb(140, 80, 255), rgb(250, 75, 225), rgb(110, 60, 240) },
			Glow = rgb(255, 85, 230),
			Core = 0.15,
			Bright = 1.15,
			GlowBright = 1.15,
			GlowAlpha = 0.68,
			Sparks = { rgb(255, 255, 255), rgb(255, 150, 240), rgb(140, 205, 255) },
			Stars = { rgb(255, 255, 255), rgb(255, 205, 250), rgb(185, 220, 255) },
		},
	},
	{
		Index = 11,
		Name = "Divine Trail",
		Art = 100324936581578,
		Rarity = "Celestial",
		Multiplier = 10000,
		Price = 110000000000000000,
		Look = {
			Colors = { rgb(255, 220, 70), rgb(255, 195, 35), rgb(255, 155, 20) },
			Glow = rgb(255, 205, 70),
			Core = 0.45,
			Bright = 1.25,
			GlowBright = 1.4,
			GlowEmission = 0.45,
			GlowAlpha = 0.5,
			Sparks = { rgb(255, 255, 255), rgb(255, 236, 140), rgb(255, 200, 60) },
			Clouds = rgb(255, 246, 215),
			Light = rgb(255, 210, 110),
		},
	},
}
-- trail prices = Break and Steal an Egg's (same multipliers x2 .. x10K; bloxodes trails table, 2026-11-22: "apply the
-- same progression")
local TRAIL_PRICE_BY_MULT = {
	[2] = 500,
	[4] = 7500,
	[8] = 100000,
	[16] = 1200000,
	[40] = 17500000,
	[100] = 250000000,
	[250] = 3500000000,
	[600] = 45000000000,
	[1500] = 600000000000,
	[4000] = 8000000000000,
	[10000] = 100000000000000,
}
for _, t in Config.Trails do
	local p = TRAIL_PRICE_BY_MULT[t.Multiplier]
	if p then
		t.Price = p
	end
end
-- (rarity label colours on the cards)
Config.TrailRarityColors = {
	Common = rgb(210, 210, 210),
	Uncommon = rgb(90, 220, 90),
	Rare = rgb(70, 150, 255),
	Epic = rgb(180, 80, 255),
	Legendary = rgb(255, 190, 40),
	Mythic = rgb(255, 90, 200),
	Cosmic = rgb(120, 255, 240),
	Secret = rgb(230, 230, 240),
	Celestial = rgb(255, 225, 120),
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

-- Rarities, from the reference game ("[NEW] Feed and Rob Animals", Config/Pets): names, colours and spawn weights.
-- Each biome's rarities slide up the ladder (Config.Biomes[*].Rarities), and income goes x1, x2, x5, x10, x20, x50 ...
-- from the biome's lowest rarity (RarityIncomeSteps), like the reference.
-- Size: how big the animal is out in the wild (user, 2026-11-20: epic and legendary "about 5x bigger", legendary
-- bigger than epic, and up from there). BaseSize: how big it stands in your base (user 2026-11-21: "legendary should
-- look huge", every rarity bigger than the one before; capped at Config.MaxBaseAnimalHeight so it still fits a pen).
Config.Rarities = {
	{ Name = "Common", Color = Color3.fromRGB(200, 200, 200), Size = 1, BaseSize = 1, Weight = 50 },
	{ Name = "Uncommon", Color = Color3.fromRGB(90, 220, 90), Size = 1.15, BaseSize = 1.25, Weight = 30 },
	{ Name = "Rare", Color = Color3.fromRGB(70, 150, 255), Size = 1.35, BaseSize = 1.6, Weight = 15 },
	{ Name = "Epic", Color = Color3.fromRGB(180, 80, 255), Size = 5, BaseSize = 2.2, Weight = 7 },
	{ Name = "Legendary", Color = Color3.fromRGB(255, 190, 40), Size = 6.5, BaseSize = 4.8, Weight = 3 },
	{ Name = "Mythic", Color = Color3.fromRGB(255, 90, 200), Size = 7.5, BaseSize = 5.8, Weight = 1.2 },
	{ Name = "Cosmic", Color = Color3.fromRGB(120, 255, 240), Size = 8.5, BaseSize = 6.8, Weight = 0.5 },
	{ Name = "Secret", Color = Color3.fromRGB(60, 60, 70), Size = 9.5, BaseSize = 7.8, Weight = 0.15 },
	{ Name = "Eternal", Color = Color3.fromRGB(255, 255, 255), Size = 11, BaseSize = 8.8, Weight = 0.05 },
}
Config.RarityIncomeSteps = { 1, 2, 5, 10, 20, 50, 100, 200, 500 } -- (old curve: only a fallback now)
-- PROGRESSION (2026-11-22, user: "study the progressions for Break and Steal an Egg, Steal an Egg, Throw Food for
-- Animals and apply that same progression"). Researched from the community wikis / guides (eldorado.gg, games.gg,
-- bloxodes, allthings.how, rblxguide). Our six biomes ARE Break and Steal an Egg's first six zones: the same speed gates
-- (5 / 1K / 50K / 750K / 12M / 150M) and the same trails, so each animal earns what the pet of the same rarity earns in
-- that game's matching zone (Forest, Desert, Snowy, Candy, Swamp, Ocean), our rarities mapped onto its ladder (our
-- Cosmic = its Divine, Secret = its Cosmic, Eternal = its Celestial / zone top). "est" = that zone has no pet of
-- that rarity, so it's filled in from the ratios between rarities in its other zones.
-- $/s per biome, by animal slot (Config.Biomes[b].Animals order)
Config.AnimalIncome = {
	{ 1, 2, 10, 13, 35, 145, 1800, 5000 }, -- Forest: C 1/2, U 10/13, R 35, E 145, L 1.8K, Mythic est
	{ 3, 20, 25, 110, 230, 2800, 8000, 60000 }, -- Desert: C 3, U 20/25, R 110, E 230, L 2.8K, Mythic + Divine est
	{ 40, 65, 180, 240, 650, 4500, 12500, 125000 }, -- Snowy: U 40/65, R 180/240, E 650, L 4.5K, M 12.5K, Divine 125K
	{ 84, 224, 336, 840, 8400, 46700, 220000, 1500000 }, -- Candy: U 84, R 224/336, E 840, L 8.4K, M 46.7K, D 220K, Cosmic 1.5M
	{ 400, 600, 1500, 1800, 15000, 83300, 391000, 12000000 }, -- Swamp: R 400/600, E 1.5K (2nd est), L 15K, M 83.3K, D 391K, Secret 12M
	{ 720, 2700, 3500, 27000, 150000, 703000, 16700000, 125000000 }, -- Ocean: R 720, E 2.7K (2nd est), L 27K, M 150K, D 703K, Secret 16.7M, Celestial 125M
}
-- each biome's base hatch chances in %, by animal slot: Steal an Egg's per-pet drop rates in its matching biome (Forest,
-- Lake, Desert, Jungle, Snow, Volcano; rblxguide.com drop-rates guide). Luck badges then tilt them (hatchChances).
Config.BaseHatchChances = {
	{ 34, 24, 17, 10, 7, 4.5, 2.5, 1 },
	{ 29.27, 23.22, 17.16, 12.11, 8.08, 5.55, 4.04, 0.57 },
	{ 26.59, 20.45, 15.34, 12.27, 9.20, 8.18, 6.65, 1.33 },
	{ 26.01, 20.01, 17, 13, 11, 7.85, 5, 0.124 },
	{ 29.44, 21.57, 18.34, 14.02, 11.86, 4.17, 0.37, 0.22 },
	{ 26.85, 22.04, 18.03, 17.03, 15.03, 0.62, 0.22, 0.18 },
}
-- How tall an animal stands: small in the first biome, bigger in every biome after it, and bigger again by rarity
-- (a Grassy Meadows chicken ~5 studs, the player's height; a Candyland Eternal ~45). Config.animalHeight below.
Config.BiomeAnimalHeight = { 5, 6.25, 7.5, 9, 10.5, 12 }
-- (user 2026-11-22: animals stuck out of the base far too much; the pen is ~38 studs across: no animal longer than 30
-- or taller than 40 there, so it can poke out a little but not a lot)
Config.MaxBaseAnimalHeight = 40
Config.MaxBaseAnimalWidth = 30

-- Biomes, ordered from nearest to the bases to furthest. 8 animals each, lowest rarity first; Rarities[i] is the
-- rarity (index into Config.Rarities) of Animals[i].
-- Model names must match the animal models inside ReplicatedStorage.Assets.
Config.Biomes = {
	{
		Name = "Grassy Meadows",
		Level = "Level1_Grassy_Meadows",
		Track = "Level1_track",
		WallSpeed = 18, -- studs/s: you outrun it at the RecommendedSpeed (Progression.walkSpeed)
		RecommendedSpeed = 5, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Easy", Emoji = "😀", Color = Color3.fromRGB(190, 255, 60) },
		IncomeMultiplier = 1,
		WallMaterial = Enum.Material.Grass,
		WallColor = Color3.fromRGB(80, 160, 70),
		Animals = { "Chicken", "Corgi", "Bunny", "Goat", "Cow", "Horse", "Griffin", "Pegasus" },
		Rarities = { 1, 1, 2, 2, 3, 4, 5, 6 },
	},
	{
		Name = "Snowy Tundra",
		Level = "Level2_Snowy_Tundra",
		Track = "Level2_track",
		WallSpeed = 28, -- studs/s: you outrun it at the RecommendedSpeed (Progression.walkSpeed)
		RecommendedSpeed = 1e3, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Medium", Emoji = "😟", Color = Color3.fromRGB(255, 170, 40) },
		IncomeMultiplier = 2.5,
		WallMaterial = Enum.Material.Snow,
		WallColor = Color3.fromRGB(230, 240, 255),
		Animals = { "Puffin", "Akita", "Yak", "Wolf", "PolarBear", "Caladrius", "Mammoth", "Fenrir" },
		Rarities = { 1, 2, 2, 3, 4, 5, 6, 7 },
	},
	{
		Name = "Sandy Dunes",
		Level = "Level3_Sandy_Dunes",
		Track = "Level3_track",
		WallSpeed = 38, -- studs/s: you outrun it at the RecommendedSpeed (Progression.walkSpeed)
		RecommendedSpeed = 5e4, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Hard", Emoji = "😠", Color = Color3.fromRGB(255, 90, 60) },
		IncomeMultiplier = 6,
		WallMaterial = Enum.Material.Sand,
		WallColor = Color3.fromRGB(225, 195, 135),
		Animals = { "Meerkat", "Armadillo", "FennecFox", "Jackal", "Cobra", "Caracal", "Manticore", "Sphinx" },
		Rarities = { 2, 2, 3, 3, 4, 5, 6, 7 },
	},
	{
		Name = "Fiery Hellscape",
		Level = "Level4_Fiery_Hellscape",
		Track = "Level4_track",
		WallSpeed = 48, -- studs/s: you outrun it at the RecommendedSpeed (Progression.walkSpeed)
		RecommendedSpeed = 750e3, -- (Break and Steal an Egg Candy gate) speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Expert", Emoji = "😤", Color = Color3.fromRGB(230, 40, 60) },
		IncomeMultiplier = 15,
		WallMaterial = Enum.Material.CrackedLava,
		WallColor = Color3.fromRGB(255, 95, 35),
		Animals = {
			"Salamander",
			"Hellhound",
			"ShadowWolf",
			"Dimetrodon",
			"Cerberus",
			"Cockatrice",
			"Phoenix",
			"Dragon",
		},
		Rarities = { 2, 3, 3, 4, 5, 6, 7, 8 },
	},
	{
		Name = "Toxic Wasteland",
		Level = "Level5_Toxic_Wasteland",
		Track = "Level5_track",
		WallSpeed = 58, -- studs/s: you outrun it at the RecommendedSpeed (Progression.walkSpeed)
		RecommendedSpeed = 12e6, -- (Break and Steal an Egg Swamp gate) speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Insane", Emoji = "🤯", Color = Color3.fromRGB(190, 70, 255) },
		IncomeMultiplier = 35,
		WallMaterial = Enum.Material.Mud,
		WallColor = Color3.fromRGB(120, 200, 40),
		-- (all radioactive: tinted green in ReplicatedStorage.Assets, attribute Radioactive; they glow in the wild)
		Animals = {
			"Beetle",
			"Gecko",
			"Crocodile",
			"GiantSpider",
			"Chupacabra",
			"Ankylosaurus",
			"Triceratops",
			"Hydra",
		},
		Rarities = { 3, 3, 4, 4, 5, 6, 7, 8 },
	},
	{
		Name = "Candyland",
		Level = "Level6_Candyland",
		Track = "Level6_track",
		WallSpeed = 68, -- studs/s: you outrun it at the RecommendedSpeed (Progression.walkSpeed)
		RecommendedSpeed = 1.5e8, -- speed points that outrun this wall (shown at the top of the screen)
		Difficulty = { Name = "Extreme", Emoji = "😈", Color = Color3.fromRGB(255, 60, 170) },
		IncomeMultiplier = 80,
		WallMaterial = Enum.Material.SmoothPlastic,
		WallColor = Color3.fromRGB(255, 140, 205),
		Animals = { "Hamster", "BichonFrise", "Axolotl", "Toucan", "Flamingo", "Unicorn", "Simurgh", "Qilin" },
		Rarities = { 3, 4, 4, 5, 6, 7, 8, 9 },
	},
}

-- Disaster hazards per biome (index matches Config.Biomes). Projectiles arc in from the sides onto a red
-- target circle; rollers sweep across the whole path. Kinds are built in Client/Hazards.
Config.HazardThemes = {
	-- Grassy Meadows: rocks, falling trees, hay
	{
		Projectiles = { "Boulder", "FallingLog", "HayBale", "Pumpkin", "Beehive" },
		Rollers = { "Log", "HayBale" },
		Flyers = { "Log", "Boulder" },
	},
	-- Snowy Tundra: no rocks, all snow and ice
	{
		Projectiles = { "Snowball", "IceChunk", "Icicle", "Snowman" },
		Rollers = { "Snowball", "Avalanche" },
		Flyers = { "Snowball", "IceChunk" },
	},
	-- Sandy Dunes: sandstone, cacti, tumbleweeds
	{
		Projectiles = { "Sandstone", "Cactus", "Urn", "Skull" },
		Rollers = { "StoneWheel", "Tumbleweed" },
		Flyers = { "Sandstone", "Tumbleweed" },
	},
	-- Fiery Hellscape: meteors and lava
	{
		Projectiles = { "Meteor", "LavaBomb", "Obsidian" },
		Rollers = { "LavaRock" },
		Flyers = { "Fireball" },
	},
	-- Toxic Wasteland: acid and toxic barrels
	{
		Projectiles = { "AcidBlob", "ToxicBarrel", "Tire", "SludgeBucket" },
		Rollers = { "Barrel" },
		Flyers = { "AcidBlob", "ToxicBarrel" },
	},
	-- Candyland: sweets
	{
		Projectiles = { "Gumball", "Cupcake", "Lollipop", "Donut", "Cookie" },
		Rollers = { "CandyCane", "Donut" },
		Flyers = { "Gumball", "Donut" },
	},
}

local DISPLAY_NAMES = {
	Beetle = "Toxic Beetle",
	Gecko = "Glow Gecko",
	Crocodile = "Mutant Croc",
	GiantSpider = "Radioactive Spider",
	Ankylosaurus = "Toxic Ankylosaurus",
	Triceratops = "Mutant Triceratops",
	Hydra = "Radioactive Hydra",
	Dimetrodon = "Lava Dimetrodon",
	BichonFrise = "Cotton Candy Bichon",
	PolarBear = "Polar Bear",
	Mammoth = "Woolly Mammoth",
	FennecFox = "Fennec Fox",
	Phoenix = "Fire Phoenix",
	Komodo = "Komodo Dragon",
	ShadowWolf = "Shadow Wolf",
	RedPanda = "Red Panda",
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
-- (the animals added from the same animal bundle share a skeleton with one already here, so they use its clips)
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
-- the rest of the 8 per biome, from the same animal bundle: same bone names as the animal named, so its clips fit
for id, like in
	{
		Corgi = "Meerkat",
		Goat = "Mammoth",
		Cow = "Meerkat",
		Akita = "Meerkat",
		Wolf = "Mammoth",
		Tiger = "Unicorn",
		Armadillo = "Meerkat",
		Lizard = "Meerkat",
		Caracal = "Mammoth",
		Komodo = "Salamander",
		ShadowWolf = "Hellhound",
		Cockatrice = "Phoenix",
		Newt = "Salamander",
		Hyena = "Meerkat",
		Crocodile = "Mammoth",
		Toucan = "Flamingo",
		RedPanda = "Meerkat",
		Kitsune = "Meerkat",
		-- (2026-11-20)
		Caladrius = "Phoenix",
		Simurgh = "Phoenix",
		Dimetrodon = "Sphinx",
		BichonFrise = "Meerkat",
		Ankylosaurus = "Meerkat",
		Triceratops = "Mammoth",
		Gecko = "Salamander",
		Jackal = "Meerkat",
	}
do
	Config.AnimationIds[id] = Config.AnimationIds[like]
end

-- Derived: Config.Animals[id] = { Id, Name, Biome, Rarity, Income } ---------------------------------------------
Config.Animals = {}
for biomeIndex, biome in Config.Biomes do
	local lowest = math.huge
	for _, r in biome.Rarities do
		lowest = math.min(lowest, r)
	end
	for slot, id in biome.Animals do
		local rarity = biome.Rarities[slot]
		Config.Animals[id] = {
			Id = id,
			Name = DISPLAY_NAMES[id] or id,
			Biome = biomeIndex,
			Slot = slot,
			Rarity = rarity,
			Income = (Config.AnimalIncome[biomeIndex] or {})[slot]
				or biome.IncomeMultiplier * Config.RarityIncomeSteps[rarity - lowest + 1],
			Height = Config.BiomeAnimalHeight[biomeIndex] * Config.Rarities[rarity].Size,
			BaseHeight = math.min(
				Config.BiomeAnimalHeight[biomeIndex] * Config.Rarities[rarity].BaseSize,
				Config.MaxBaseAnimalHeight
			),
		}
	end
end
-- Animals that used to live in a biome (2026-11-20 re-sort): no longer found in the wild, but players who rescued
-- one keep it, earning what it did. Biome and rarity as they were.
Config.Retired = {
	Tiger = { Biome = 2, Rarity = 5, Step = 5 },
	Komodo = { Biome = 4, Rarity = 3, Step = 2 },
	Toad = { Biome = 5, Rarity = 3, Step = 1 },
	Newt = { Biome = 5, Rarity = 3, Step = 1 },
	Hyena = { Biome = 5, Rarity = 4, Step = 2 },
	RedPanda = { Biome = 6, Rarity = 5, Step = 3 },
	Kitsune = { Biome = 6, Rarity = 8, Step = 6 },
	Lizard = { Biome = 3, Rarity = 3, Step = 2 },
}
for id, r in Config.Retired do
	if not Config.Animals[id] then
		Config.Animals[id] = {
			Id = id,
			Name = DISPLAY_NAMES[id] or id,
			Biome = r.Biome,
			Slot = 0,
			Rarity = r.Rarity,
			Retired = true,
			-- (a retired animal earns like the biome's current animal of the same rarity)
			Income = (function(): number
				local b = Config.Biomes[r.Biome]
				for slot, rr in b.Rarities do
					if rr >= r.Rarity then
						return Config.AnimalIncome[r.Biome][slot]
					end
				end
				return Config.AnimalIncome[r.Biome][#b.Rarities]
			end)(),
			Height = Config.BiomeAnimalHeight[r.Biome] * Config.Rarities[r.Rarity].Size,
			BaseHeight = math.min(Config.BiomeAnimalHeight[r.Biome] * Config.Rarities[r.Rarity].BaseSize, 40),
		}
	end
end

-- Saved animals are keys: the animal's id. Older saves have "Chicken*8" (brought home at x8, when the rings raised
-- income): those still parse, as a plain chicken (luck no longer changes income, user 2026-11-20).
function Config.parseKey(key: unknown): (any, number)
	if type(key) ~= "string" then
		return nil, 1
	end
	local id = string.match(key, "^([%w_]+)%*%d+$")
	return Config.Animals[id or key], 1
end

function Config.makeKey(id: string, _mult: number?): string
	return id
end

-- money per second of a saved animal (its key)
function Config.keyIncome(key: string): number
	local info = Config.parseKey(key)
	return if info then info.Income else 0
end

-- how tall it stands in the wild
function Config.animalHeight(id: string): number
	local info = Config.Animals[id]
	return if info then info.Height else 4
end

-- how tall it stands in your base (and the ghost you place)
function Config.baseAnimalHeight(id: string): number
	local info = Config.Animals[id]
	return if info then info.BaseHeight else 4
end

return Config
