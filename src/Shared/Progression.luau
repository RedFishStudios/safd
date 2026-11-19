-- Progression copied from "[NEW] Feed and Rob Animals" (Config/Progression, Config/TreadmillTiers, Config/Upgrades,
-- Shared/Speed, Shared/TreadmillSpeed). Speed is a points stat (the HUD number); walking speed comes from it on a
-- log curve through each biome's RecommendedSpeed, and prices climb Growth x per area from the third area on.

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)

local Progression = {}

Progression.Growth = 3
Progression.From = 3

function Progression.mult(stage: number): number
	return Progression.Growth ^ math.max(0, stage - Progression.From)
end

-- base price on the curve, rounded to two figures; unchanged before From
function Progression.price(base: number, stage: number): number
	local k = Progression.mult(stage)
	if k == 1 or base <= 0 then
		return base
	end
	local p = base * k
	local step = 10 ^ (math.floor(math.log10(p)) - 1)
	return math.floor(p / step + 0.5) * step
end

local function tier(model: string, name: string, price: number, gain: number)
	return { Model = model, DisplayName = name, Price = price, Gain = gain }
end

-- Gain = speed points per training step (a step every 0.25 s, down to 0.1 s)
local TREADMILL_STAGES = { 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5 }
Progression.Treadmill = {
	tier("BasicTreadmill", "Basic", 0, 1),
	tier("MilitaryTreadmill", "Military", 500, 2),
	tier("CandyTreadmill", "Candy", 2500, 3),
	tier("PirateTreadmill", "Pirate", 12000, 5),
	tier("FrostTreadmill", "Frost", 40000, 15),
	tier("SteampunkTreadmill", "Steampunk", 300000, 32),
	tier("MagmaTreadmill", "Magma", 1000000, 63),
	tier("JungleTreadmill", "Jungle", 2500000, 160),
	tier("CrystalTreadmill", "Crystal", 4500000, 436),
	tier("DesertTreadmill", "Desert", 25000000, 678),
	tier("NeonArcadeTreadmill", "Neon Arcade", 85000000, 1115),
	tier("UnderwaterTreadmill", "Underwater", 300000000, 1600),
	tier("SpaceTreadmill", "Space", 650000000, 2280),
	tier("RoyalTreadmill", "Royal", 3000000000, 3400),
	tier("VolcanicAshTreadmill", "Volcanic Ash", 10000000000, 4850),
	tier("VolcanicAshTreadmill_Gold", "Gold Volcanic Ash", 50000000000, 7750),
}
for i, t in Progression.Treadmill do
	t.Price = Progression.price(t.Price, TREADMILL_STAGES[i] or TREADMILL_STAGES[#TREADMILL_STAGES])
end

-- Base (pen) tiers: more room for animals that earn money. Each level uses the next BaseLvl model.
local BASE_STAGES = { 1, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5 }
Progression.Base = {
	{ Price = 0, PetSlots = 3 },
	{ Price = 250, PetSlots = 4 },
	{ Price = 6000, PetSlots = 5 },
	{ Price = 100000, PetSlots = 6 },
	{ Price = 2000000, PetSlots = 8 },
	{ Price = 30000000, PetSlots = 10 },
	{ Price = 500000000, PetSlots = 12 },
	{ Price = 8000000000, PetSlots = 15 },
}
for i, level in Progression.Base do
	level.Price = Progression.price(level.Price, BASE_STAGES[i] or BASE_STAGES[#BASE_STAGES])
	level.Model = `BaseLvl{i}`
end

-- Walking speed from speed points: each biome's RecommendedSpeed makes you Lead studs/s faster than its wall,
-- climbing smoothly (log scale) in between; past the last biome PerDecade per x10, capped at MaxWalkSpeed.
Progression.Training = { BaseWalkSpeed = 16, Lead = 4, PerDecade = 6, MaxWalkSpeed = 110 }

function Progression.walkSpeed(points: number): number
	local T = Progression.Training
	local x = math.log10(1 + math.max(points, 0))
	local prevX, prevW = 0, T.BaseWalkSpeed
	for _, b in Config.Biomes do
		local bx, bw = math.log10(1 + b.RecommendedSpeed), b.WallSpeed + T.Lead
		if x <= bx then
			return prevW + (bw - prevW) * (x - prevX) / (bx - prevX)
		end
		prevX, prevW = bx, bw
	end
	return math.min(prevW + (x - prevX) * T.PerDecade, T.MaxWalkSpeed)
end

-- Treadmill payout interval: 0.25 s, shrinking to 0.1 s as your speed grows on that treadmill
-- (1,000x its gain -> 0.25 s, 1,000,000x -> 0.1 s)
Progression.STEP_SECONDS = 0.25
Progression.FAST_SECONDS = 0.1
function Progression.interval(points: number, gain: number): number
	local base = math.max(gain, 1)
	local s = math.max(points, 1)
	local x = math.clamp((math.log10(s / base) - 3) / 3, 0, 1)
	return Progression.STEP_SECONDS - x * (Progression.STEP_SECONDS - Progression.FAST_SECONDS)
end

-- 950, 1.5K, 14K, 25M ... (Shared/Util.formatNumber, the reference game's Format.short)
function Progression.short(n: number): string
	return Util.formatNumber(n)
end

return Progression
