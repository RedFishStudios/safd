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

-- PROGRESSION (2026-11-22, user: "study Break and Steal an Egg, Steal an Egg, Throw Food for Animals and apply the
-- same progression"; researched from the community wikis / guides, see Config.AnimalIncome).
-- Treadmills = Steal an Egg's treadmill ladder (games.gg "best treadmills ranked"): Common +2 free, Sci-Fi +5 $15K,
-- Flame +12 $250K, Celebrity +30 $5M, Golden +80 $120M, Freeze +100 $3B, Lucky Block +200 $75B, Hacker +500 $2T,
-- Demonic +1,000 $50T, Angelic +2,000 $1Qd, bought in order. Our 16 treadmill models take those 10 steps in order; the
-- last 6 carry the ladder on (x25 the price, x2 the gain each, its own late-game ratio). Prices are exact: no curve.
-- Gain = speed points per training step (a step every 0.25 s, down to 0.1 s)
Progression.Treadmill = {
	tier("BasicTreadmill", "Basic", 0, 2),
	tier("MilitaryTreadmill", "Military", 15000, 5),
	tier("CandyTreadmill", "Candy", 250000, 12),
	tier("PirateTreadmill", "Pirate", 5000000, 30),
	tier("FrostTreadmill", "Frost", 120000000, 80),
	tier("SteampunkTreadmill", "Steampunk", 3000000000, 100),
	tier("MagmaTreadmill", "Magma", 75000000000, 200),
	tier("JungleTreadmill", "Jungle", 2000000000000, 500),
	tier("CrystalTreadmill", "Crystal", 50000000000000, 1000),
	tier("DesertTreadmill", "Desert", 1000000000000000, 2000),
	tier("NeonArcadeTreadmill", "Neon Arcade", 25000000000000000, 4000),
	tier("UnderwaterTreadmill", "Underwater", 625000000000000000, 8000),
	tier("SpaceTreadmill", "Space", 1.6e19, 16000),
	tier("RoyalTreadmill", "Royal", 4e20, 32000),
	tier("VolcanicAshTreadmill", "Volcanic Ash", 1e22, 64000),
	tier("VolcanicAshTreadmill_Gold", "Gold Volcanic Ash", 2.5e23, 128000),
}

-- Base (pen) tiers = Break and Steal an Egg's pen (allthings.how guides): it starts with 8 slots, Lv2 $10K (+1 slot),
-- Lv3 $1M, Lv4 $45M; past that the guides stop, so the ladder carries on at its own x40 per level. Each level uses the
-- next BaseLvl model.
Progression.Base = {
	{ Price = 0, PetSlots = 8 },
	{ Price = 10000, PetSlots = 9 },
	{ Price = 1000000, PetSlots = 10 },
	{ Price = 45000000, PetSlots = 11 },
	{ Price = 1800000000, PetSlots = 12 },
	{ Price = 72000000000, PetSlots = 13 },
	{ Price = 2900000000000, PetSlots = 14 },
	{ Price = 115000000000000, PetSlots = 15 },
}
for i, level in Progression.Base do
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
			-- (cubed: most of the step comes right at the recommended speed. Under it the wall is faster than you:
			-- user 2026-11-21, 200 speed must not be enough for the Tundra's 1K)
			local f = (x - prevX) / (bx - prevX)
			return prevW + (bw - prevW) * f * f * f
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
