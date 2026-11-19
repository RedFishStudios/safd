-- Disaster hazards (client-only, like the rest of the disaster):
--   * Projectiles lob in from the left / right edges of the path. A red circle marks the landing spot and
--     fills from the centre outwards; the projectile lands exactly when the circle is full.
--   * Rollers (huge logs, snowballs, barrels, ...) sweep across the whole path from one side to the other
--     after a flashing red lane warning. Jump (double jump!) over them or get out of the lane.
--   * Flyers are hurled flat across the path at head height after a yellow "SLIDE!" lane warning: slide under.
-- Each biome picks its kinds from Config.HazardThemes (snowballs and ice in the tundra, cacti in the dunes...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HUD = require(script.Parent.HUD)
local Moves = require(script.Parent.Moves)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local rng = Random.new()

local Hazards = {}
Hazards.activeTelegraphs = 0
Hazards.activeRollers = 0

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

export type Context = {
	folder: Folder,
	trackMinX: number,
	trackMaxX: number,
	toBase: Vector3,
	alive: () -> boolean,
	groundAt: (Vector3) -> Vector3?,
	addObstacle: (Instance) -> (),
	shake: (number) -> (),
	hit: (Vector3, Vector3) -> (), -- (hit position, push direction)
}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- Puffs of dust / fire / sparkles. Pooled: one emitter per look, kept on a single holder part, moved to each puff
-- and fired (emitted particles stay where they were born), instead of a new part + emitter for every puff.
local burstHolder: Part? = nil
local burstPool: { [string]: { Attachment } } = {}
local function burstEmitter(color: Color3, texture: string): (Attachment, ParticleEmitter)
	if not burstHolder or not burstHolder.Parent then
		local h = Instance.new("Part")
		h.Name = "SAFD_HazardPuffs"
		h.Anchored = true
		h.CanCollide = false
		h.CanQuery = false
		h.CanTouch = false
		h.Transparency = 1
		h.Size = Vector3.one
		h.Parent = workspace
		burstHolder = h
		burstPool = {}
	end
	-- (colours snapped to a small palette, so the pool stays small)
	color = Color3.new(math.round(color.R * 6) / 6, math.round(color.G * 6) / 6, math.round(color.B * 6) / 6)
	local key = texture .. color:ToHex()
	local entry = burstPool[key]
	if not entry then
		local at = Instance.new("Attachment")
		at.Parent = burstHolder
		emitter(at, {
			Texture = texture,
			Color = ColorSequence.new(color),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 7) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.2),
			Speed = NumberRange.new(10, 28),
			SpreadAngle = Vector2.new(180, 60),
			Rate = 0,
		})
		entry = { at }
		burstPool[key] = entry
	end
	local at = entry[1]
	return at, at:FindFirstChildOfClass("ParticleEmitter") :: ParticleEmitter
end

local function burst(_ctx: Context, position: Vector3, color: Color3, amount: number, texture: string?)
	local at, e = burstEmitter(color, texture or SMOKE)
	at.WorldPosition = position
	e:Emit(math.min(math.ceil(amount * 0.45), 14)) -- (big see-through puffs are what costs most to draw)
end

-- Builders ------------------------------------------------------------------------------------------------------
-- Each returns (model, radius). Models are anchored, non-colliding until they settle.

local function ball(radius: number, color: Color3, material: Enum.Material): Model
	local m = Instance.new("Model")
	local core =
		part({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 2, Color = color, Material = material })
	core.Name = "Core"
	core.Parent = m
	m.PrimaryPart = core
	return m
end

local function lumpy(radius: number, color: Color3, material: Enum.Material): Model
	-- A boulder: a ball plus a few offset chunks so it isn't a perfect sphere.
	local m = ball(radius, color, material)
	for _ = 1, 4 do
		local s = radius * rng:NextNumber(0.6, 0.9)
		local chunk = part({
			Size = Vector3.new(s, s, s) * 1.4,
			Color = color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.25)),
			Material = material,
		})
		chunk.CFrame = CFrame.new(rng:NextUnitVector() * radius * 0.45)
			* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		chunk.Parent = m
	end
	return m
end

local PROJECTILES = {}

PROJECTILES.Boulder = function(): (Model, number)
	local r = rng:NextNumber(3.5, 5.5)
	return lumpy(r, Color3.fromRGB(120, 115, 108), Enum.Material.Slate), r
end

PROJECTILES.Sandstone = function(): (Model, number)
	local r = rng:NextNumber(3.5, 5.5)
	return lumpy(r, Color3.fromRGB(205, 160, 100), Enum.Material.Sandstone), r
end

PROJECTILES.Icicle = function(): (Model, number)
	local m = Instance.new("Model")
	local h = rng:NextNumber(9, 13)
	local spike = part({
		Size = Vector3.new(2.4, h, 2.4),
		Color = Color3.fromRGB(170, 230, 255),
		Material = Enum.Material.Ice,
		Transparency = 0.15,
	})
	spike.Name = "Core"
	spike.Parent = m
	for i = 1, 3 do
		local shard = part({
			Size = Vector3.new(1.2, h * 0.55, 1.2),
			Color = Color3.fromRGB(200, 240, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.25,
		})
		shard.CFrame = CFrame.Angles(0, i * 2.1, 0.35) * CFrame.new(1.2, -h * 0.15, 0)
		shard.Parent = m
	end
	m.PrimaryPart = spike
	return m, 3
end
PROJECTILES.IceSpike = PROJECTILES.Icicle

PROJECTILES.Snowball = function(): (Model, number)
	local r = rng:NextNumber(3.5, 5.5)
	local m = ball(r, Color3.fromRGB(245, 250, 255), Enum.Material.Snow)
	emitter(m.PrimaryPart :: BasePart, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r), NumberSequenceKeypoint.new(1, r * 2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.7),
		Rate = 30,
	})
	return m, r
end

PROJECTILES.IceChunk = function(): (Model, number)
	local s = rng:NextNumber(5, 7.5)
	local m = Instance.new("Model")
	local core = part({
		Size = Vector3.new(s, s * 0.8, s),
		Color = Color3.fromRGB(150, 215, 255),
		Material = Enum.Material.Ice,
		Transparency = 0.1,
	})
	core.Name = "Core"
	core.Parent = m
	for _ = 1, 3 do
		local c = s * rng:NextNumber(0.4, 0.6)
		local chunk = part({
			Size = Vector3.new(c, c, c),
			Color = Color3.fromRGB(190, 235, 255),
			Material = Enum.Material.Glacier,
		})
		chunk.CFrame = CFrame.new(rng:NextUnitVector() * s * 0.4)
			* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		chunk.Parent = m
	end
	m.PrimaryPart = core
	return m, s / 2 + 0.5
end

PROJECTILES.FallingLog = function(): (Model, number)
	local length, radius = rng:NextNumber(9, 12), 1.8
	local m = Instance.new("Model")
	local core = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, radius * 2, radius * 2),
		Color = Color3.fromRGB(105, 70, 40),
		Material = Enum.Material.Wood,
	})
	core.Name = "Core"
	core.Parent = m
	local leaves = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 5,
		Color = Color3.fromRGB(70, 150, 60),
		Material = Enum.Material.Grass,
	})
	leaves.CFrame = CFrame.new(length / 2, 0, 0)
	leaves.Parent = m
	m.PrimaryPart = core
	return m, 4
end

PROJECTILES.HayBale = function(): (Model, number)
	local r = rng:NextNumber(2.6, 3.4)
	local m = Instance.new("Model")
	local core = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(r * 1.6, r * 2, r * 2),
		Color = Color3.fromRGB(225, 190, 95),
		Material = Enum.Material.Fabric,
	})
	core.Name = "Core"
	core.Parent = m
	m.PrimaryPart = core
	return m, r + 0.5
end

PROJECTILES.Cactus = function(): (Model, number)
	local m = Instance.new("Model")
	local green = Color3.fromRGB(70, 150, 65)
	local h = rng:NextNumber(8, 11)
	local core = part({ Size = Vector3.new(2.2, h, 2.2), Color = green, Material = Enum.Material.Grass })
	core.Name = "Core"
	core.Parent = m
	for _, side in { -1, 1 } do
		local arm = part({ Size = Vector3.new(1.6, h * 0.35, 1.6), Color = green, Material = Enum.Material.Grass })
		arm.CFrame = CFrame.new(side * 1.9, h * 0.1, 0)
		arm.Parent = m
		local elbow = part({ Size = Vector3.new(1.9, 1.4, 1.6), Color = green, Material = Enum.Material.Grass })
		elbow.CFrame = CFrame.new(side * 1.2, -h * 0.05, 0)
		elbow.Parent = m
	end
	m.PrimaryPart = core
	return m, 3
end

PROJECTILES.Meteor = function(): (Model, number)
	local r = rng:NextNumber(3.5, 5)
	local m = lumpy(r, Color3.fromRGB(60, 30, 25), Enum.Material.Basalt)
	local glow = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * r * 1.6,
		Color = Color3.fromRGB(255, 110, 20),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
	})
	glow.Parent = m
	emitter(m.PrimaryPart :: BasePart, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 40, 10)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r * 1.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.4, 0.8),
		Rate = 35,
		Speed = NumberRange.new(2, 6),
		LightEmission = 1,
	})
	return m, r + 1
end

PROJECTILES.LavaBomb = function(): (Model, number)
	local r = rng:NextNumber(2.5, 3.5)
	local m = ball(r, Color3.fromRGB(255, 80, 10), Enum.Material.Neon)
	emitter(m.PrimaryPart :: BasePart, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 50, 10)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r * 2), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Rate = 35,
		LightEmission = 1,
	})
	return m, r + 1.5
end
PROJECTILES.Fireball = PROJECTILES.LavaBomb

PROJECTILES.AcidBlob = function(): (Model, number)
	local r = rng:NextNumber(3, 4.5)
	local m = ball(r, Color3.fromRGB(120, 255, 40), Enum.Material.Neon);
	(m.PrimaryPart :: BasePart).Transparency = 0.15
	emitter(m.PrimaryPart :: BasePart, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(150, 255, 60)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 1),
		Rate = 40,
	})
	return m, r + 1.5
end

PROJECTILES.ToxicBarrel = function(): (Model, number)
	local m = Instance.new("Model")
	local core = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 3.6, 3.6),
		Color = Color3.fromRGB(230, 190, 30),
		Material = Enum.Material.DiamondPlate,
	})
	core.Name = "Core"
	core.Parent = m
	for _, x in { -1.6, 1.6 } do
		local band = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 3.8, 3.8),
			Color = Color3.fromRGB(120, 255, 40),
			Material = Enum.Material.Neon,
		})
		band.CFrame = CFrame.new(x, 0, 0)
		band.Parent = m
	end
	m.PrimaryPart = core
	return m, 3.5
end

PROJECTILES.Gumball = function(): (Model, number)
	local r = rng:NextNumber(3.5, 5.5)
	local m = ball(r, Color3.fromHSV(rng:NextNumber(), 0.7, 1), Enum.Material.SmoothPlastic);
	(m.PrimaryPart :: BasePart).Reflectance = 0.15
	return m, r
end

PROJECTILES.Cupcake = function(): (Model, number)
	local m = Instance.new("Model")
	local core = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.5, 5, 5),
		Color = Color3.fromRGB(255, 120, 170),
		Material = Enum.Material.Fabric,
	})
	core.Name = "Core"
	core.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	core.Parent = m
	local frosting = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5.8, 4.5, 5.8),
		Color = Color3.fromRGB(255, 245, 250),
		Material = Enum.Material.SmoothPlastic,
	})
	frosting.CFrame = CFrame.new(0, 2.3, 0)
	frosting.Parent = m
	local cherry = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.4,
		Color = Color3.fromRGB(230, 20, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	cherry.CFrame = CFrame.new(0, 4.6, 0)
	cherry.Parent = m
	m.PrimaryPart = core
	return m, 3.5
end

PROJECTILES.Lollipop = function(): (Model, number)
	local m = Instance.new("Model")
	local core = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 6, 6),
		Color = Color3.fromHSV(rng:NextNumber(), 0.6, 1),
		Material = Enum.Material.SmoothPlastic,
	})
	core.Name = "Core"
	core.Parent = m
	local swirl = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.1, 3.4, 3.4),
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.SmoothPlastic,
	})
	swirl.Parent = m
	local stick = part({ Size = Vector3.new(0.5, 6, 0.5), Color = Color3.fromRGB(250, 250, 240) })
	stick.CFrame = CFrame.new(0, -5.5, 0)
	stick.Parent = m
	m.PrimaryPart = core
	return m, 3.5
end

-- What a projectile does when it lands. Anything not listed shatters into rubble that scatters and fades.
local IMPACT = {
	Meteor = "scorch",
	LavaBomb = "scorch",
	Fireball = "scorch",
	AcidBlob = "puddle",
	ToxicBarrel = "puddle",
	Gumball = "bounce",
	Snowball = "splat",
	HayBale = "splat",
	Cupcake = "splat",
}
local IMPACT_SOUND = {
	Meteor = { "HeavyThud", 1.6, 0.8 },
	LavaBomb = { "HeavyThud", 1.3, 1 },
	Fireball = { "HeavyThud", 1.3, 1 },
	Gumball = { "RockHit", 1.2, 1.4 },
	AcidBlob = { "RockHit", 1.2, 1.4 },
	Snowball = { "HeavyThud", 1.2, 1.3 },
	HayBale = { "HeavyThud", 1, 1.2 },
	Cupcake = { "RockHit", 1, 1.5 },
	Lollipop = { "RockHit", 1.2, 1.2 },
	FallingLog = { "WoodCrack", 1.6, 0.9 },
	Cactus = { "WoodCrack", 1.2, 1.3 },
	ToxicBarrel = { "Impact", 1.4, 1.2 },
	Icicle = { "Impact", 1.5, 1.4 },
	IceSpike = { "Impact", 1.5, 1.4 },
	IceChunk = { "Impact", 1.5, 1.25 },
}

local ROLLERS = {}

-- Cylinder parts have their axis along local X; the roller axis is laid along the path (world Z).
local function log(length: number, radius: number, color: Color3, material: Enum.Material): Model
	local m = Instance.new("Model")
	local core = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, radius * 2, radius * 2),
		Color = color,
		Material = material,
	})
	core.Name = "Core"
	core.Parent = m
	m.PrimaryPart = core
	return m
end

ROLLERS.Log = function(): (Model, number, number)
	local length, radius = rng:NextNumber(26, 36), 2.8
	local m = log(length, radius, Color3.fromRGB(110, 72, 40), Enum.Material.Wood)
	for _, side in { -1, 1 } do
		local cap = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, radius * 1.9, radius * 1.9),
			Color = Color3.fromRGB(200, 160, 100),
			Material = Enum.Material.WoodPlanks,
		})
		cap.CFrame = CFrame.new(side * length / 2, 0, 0)
		cap.Parent = m
	end
	return m, radius, length
end

ROLLERS.Snowball = function(): (Model, number, number)
	local r = rng:NextNumber(5, 7)
	return ball(r, Color3.fromRGB(240, 248, 255), Enum.Material.Snow), r, r * 2
end

ROLLERS.StoneWheel = function(): (Model, number, number)
	local r = rng:NextNumber(5, 6.5)
	local m = log(3.5, r, Color3.fromRGB(190, 150, 95), Enum.Material.Sandstone)
	local hub = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, r * 0.8, r * 0.8),
		Color = Color3.fromRGB(120, 90, 60),
		Material = Enum.Material.Slate,
	})
	hub.Parent = m
	return m, r, 4
end

ROLLERS.LavaRock = function(): (Model, number, number)
	local r = rng:NextNumber(4.5, 6)
	local m = lumpy(r, Color3.fromRGB(40, 20, 18), Enum.Material.CrackedLava)
	emitter(m.PrimaryPart :: BasePart, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 120, 30)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.3, 0.6),
		Rate = 30,
		LightEmission = 1,
	})
	return m, r, r * 2
end

ROLLERS.Barrel = function(): (Model, number, number)
	local m = Instance.new("Model")
	local length, radius = 9, 2.6
	for i = 0, 2 do
		local barrel = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length / 3 - 0.2, radius * 2, radius * 2),
			Color = Color3.fromRGB(60, 120, 30),
			Material = Enum.Material.DiamondPlate,
		})
		barrel.CFrame = CFrame.new((i - 1) * length / 3, 0, 0)
		barrel.Name = if i == 1 then "Core" else "Barrel"
		barrel.Parent = m
		local band = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, radius * 2.1, radius * 2.1),
			Color = Color3.fromRGB(150, 255, 40),
			Material = Enum.Material.Neon,
		})
		band.CFrame = barrel.CFrame
		band.Parent = m
	end
	m.PrimaryPart = m:FindFirstChild("Core") :: BasePart
	return m, radius, length
end

ROLLERS.CandyCane = function(): (Model, number, number)
	local m = Instance.new("Model")
	local length, radius = 30, 2.4
	local stripes = 12
	for i = 0, stripes - 1 do
		local stripe = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length / stripes, radius * 2, radius * 2),
			Color = if i % 2 == 0 then Color3.fromRGB(255, 60, 80) else Color3.fromRGB(255, 250, 250),
			Material = Enum.Material.SmoothPlastic,
		})
		stripe.CFrame = CFrame.new((i - (stripes - 1) / 2) * length / stripes, 0, 0)
		stripe.Name = if i == stripes // 2 then "Core" else "Stripe"
		stripe.Parent = m
	end
	m.PrimaryPart = m:FindFirstChild("Core") :: BasePart
	return m, radius, length
end

ROLLERS.HayBale = function(): (Model, number, number)
	local r = rng:NextNumber(3.5, 4.5)
	local m = log(rng:NextNumber(10, 16), r, Color3.fromRGB(225, 190, 95), Enum.Material.Fabric)
	return m, r, (m.PrimaryPart :: BasePart).Size.X
end

-- A rolling wave of snow: wide along the path, low enough to jump.
ROLLERS.Avalanche = function(): (Model, number, number)
	local m = Instance.new("Model")
	local length, r = rng:NextNumber(30, 40), 3
	local core = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, r * 2, r * 2),
		Color = Color3.fromRGB(245, 250, 255),
		Material = Enum.Material.Snow,
	})
	core.Name = "Core"
	core.Parent = m
	for i = 1, 6 do
		local lump = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(3.5, 5.5),
			Color = Color3.fromRGB(235, 245, 255),
			Material = Enum.Material.Snow,
		})
		lump.CFrame = CFrame.new((i - 3.5) * length / 6, rng:NextNumber(-0.5, 1.2), 0)
		lump.Parent = m
	end
	emitter(core, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 12) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.1),
		Rate = 30,
		Speed = NumberRange.new(4, 10),
	})
	m.PrimaryPart = core
	return m, r, length
end

ROLLERS.Tumbleweed = function(): (Model, number, number)
	local r = rng:NextNumber(3.5, 4.5)
	local m = ball(r, Color3.fromRGB(165, 120, 70), Enum.Material.Fabric);
	(m.PrimaryPart :: BasePart).Transparency = 0.35
	for _ = 1, 6 do
		local twig = part({
			Size = Vector3.new(0.3, 0.3, r * 2.2),
			Color = Color3.fromRGB(120, 85, 45),
			Material = Enum.Material.Wood,
		})
		twig.CFrame = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		twig.Parent = m
	end
	return m, r, r * 2
end

ROLLERS.Donut = function(): (Model, number, number)
	local r = rng:NextNumber(4.5, 5.5)
	local m = log(2.6, r, Color3.fromRGB(205, 140, 80), Enum.Material.SmoothPlastic)
	local icing = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.8, r * 1.8, r * 1.8),
		Color = Color3.fromRGB(255, 120, 190),
		Material = Enum.Material.SmoothPlastic,
	})
	icing.Parent = m
	local hole = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, r * 0.7, r * 0.7),
		Color = Color3.fromRGB(120, 70, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	hole.Parent = m
	return m, r, 3
end

-- Flyers: hurled flat across the path at head height. Jumping into them hurts; slide (Ctrl) under them.
-- Each returns (model, radius); the model's long side (if any) lies along local X, laid along the path.
local FLYERS = {}
FLYERS.Boulder = PROJECTILES.Boulder
FLYERS.Sandstone = PROJECTILES.Sandstone
FLYERS.Snowball = PROJECTILES.Snowball
FLYERS.IceChunk = PROJECTILES.IceChunk
FLYERS.Fireball = PROJECTILES.LavaBomb
FLYERS.AcidBlob = PROJECTILES.AcidBlob
FLYERS.Gumball = PROJECTILES.Gumball
FLYERS.Log = function(): (Model, number)
	local m = log(rng:NextNumber(12, 16), 2, Color3.fromRGB(110, 72, 40), Enum.Material.Wood)
	return m, 2
end
FLYERS.Tumbleweed = function(): (Model, number)
	local m, r = ROLLERS.Tumbleweed()
	return m, r
end
FLYERS.ToxicBarrel = PROJECTILES.ToxicBarrel
FLYERS.Donut = function(): (Model, number)
	local m, r = ROLLERS.Donut()
	return m, r
end

-- Telegraph: outer ring + inner disc that grows to full size over `duration` --------------------------------------

local function telegraph(ctx: Context, ground: Vector3, radius: number, duration: number): () -> ()
	local flat = CFrame.new(ground + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local ring = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		CFrame = flat,
		Color = Color3.fromRGB(255, 40, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.65,
		Parent = ctx.folder,
	})
	local edge = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.17, radius * 2 + 0.6, radius * 2 + 0.6),
		CFrame = flat * CFrame.new(-0.01, 0, 0),
		Color = Color3.fromRGB(255, 0, 0),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
		Parent = ctx.folder,
	})
	local fill = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = flat * CFrame.new(0.02, 0, 0),
		Color = Color3.fromRGB(255, 30, 30),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		Parent = ctx.folder,
	})
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
	}):Play()
	TweenService:Create(edge, TweenInfo.new(0.12, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.7,
	}):Play()
	Hazards.activeTelegraphs += 1
	local cleared = false
	return function()
		if cleared then
			return
		end
		cleared = true
		Hazards.activeTelegraphs -= 1
		ring:Destroy()
		edge:Destroy()
		fill:Destroy()
	end
end

-- Projectile -----------------------------------------------------------------------------------------------------

local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local u = 1 - t
	return a * u * u + b * 2 * u * t + c * t * t
end

function Hazards.projectile(ctx: Context, kind: string, target: Vector3)
	local ground = ctx.groundAt(target)
	if not ground then
		return
	end
	local build = PROJECTILES[kind] or PROJECTILES.Boulder
	local model, radius = build()
	local hitRadius = radius + 1.2 -- the red circle is exactly where the projectile lands
	local duration = Config.TelegraphTime * rng:NextNumber(0.9, 1.15)
	local clear = telegraph(ctx, ground, hitRadius, duration)

	-- Launch from whichever edge of the path is further away, high up, slightly behind/ahead.
	local side = if ground.X - ctx.trackMinX > ctx.trackMaxX - ground.X then -1 else 1
	if rng:NextNumber() < 0.35 then
		side = -side
	end
	local edgeX = if side < 0 then ctx.trackMinX - rng:NextNumber(45, 85) else ctx.trackMaxX + rng:NextNumber(45, 85)
	local start = Vector3.new(edgeX, ground.Y + rng:NextNumber(30, 55), ground.Z + rng:NextNumber(-25, 25))
	-- It visibly breaks loose from the hillside first.
	burst(ctx, start, Color3.fromRGB(140, 120, 100), 18)
	Sfx.at("Rubble", start, 0.9)
	local landing = ground + Vector3.new(0, radius * 0.8, 0)
	local apex = (start + landing) / 2 + Vector3.new(0, rng:NextNumber(35, 55), 0)
	model:PivotTo(CFrame.new(start))
	model.Parent = ctx.folder
	local spinAxis = rng:NextUnitVector()
	local t0 = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not ctx.alive() then
			connection:Disconnect()
			clear()
			return
		end
		local t = math.clamp((os.clock() - t0) / duration, 0, 1)
		local pos = bezier(start, apex, landing, t)
		local spin = CFrame.fromAxisAngle(spinAxis, (os.clock() - t0) * 9)
		model:PivotTo(CFrame.new(pos) * spin)
		if t < 1 then
			return
		end
		connection:Disconnect()
		clear()
		-- Impact.
		ctx.shake(math.clamp(radius / 4, 0.6, 1.4))
		local snd = IMPACT_SOUND[kind] or { "Impact", 1.5, 0.9 }
		Sfx.at(snd[1], ground, snd[2], snd[3])
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local flat = Vector3.new(root.Position.X - ground.X, 0, root.Position.Z - ground.Z)
			-- only the projectile itself hurts: you must be where it lands, not just on the red circle's edge
			if flat.Magnitude < hitRadius and root.Position.Y - ground.Y < radius * 2 + 3 then
				ctx.hit(root.Position, if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0))
			end
		end
		local core = model.PrimaryPart
		local color = if core then core.Color else Color3.fromRGB(120, 115, 108)
		local material = if core then core.Material else Enum.Material.Slate
		local how = IMPACT[kind] or "shatter"
		if how == "scorch" then
			burst(ctx, ground, Color3.fromRGB(255, 120, 30), 45, FIRE)
			burst(ctx, ground, Color3.fromRGB(60, 40, 30), 30)
			local scorch = part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, hitRadius * 2, hitRadius * 2),
				CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Color = Color3.fromRGB(255, 90, 20),
				Material = Enum.Material.Neon,
				Transparency = 0.35,
				CanQuery = true,
				Parent = ctx.folder,
			})
			-- (just a mark: standing on it does nothing)
			model:Destroy()
			TweenService:Create(scorch, TweenInfo.new(4), { Transparency = 1 }):Play()
			task.delay(4, function()
				scorch:Destroy()
			end)
		elseif how == "puddle" then
			burst(ctx, ground, Color3.fromRGB(150, 255, 60), 40)
			model:Destroy()
			local puddle = part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.25, hitRadius * 2.2, hitRadius * 2.2),
				CFrame = CFrame.new(ground + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Color = Color3.fromRGB(120, 255, 40),
				Material = Enum.Material.Neon,
				Transparency = 0.3,
				CanQuery = true,
				Parent = ctx.folder,
			})
			-- (just a mark: standing on it does nothing)
			emitter(puddle, {
				Texture = SMOKE,
				Color = ColorSequence.new(Color3.fromRGB(150, 255, 60)),
				Size = NumberSequence.new(3),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.5),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Lifetime = NumberRange.new(1, 1.5),
				Rate = 12,
				Speed = NumberRange.new(2, 4),
			})
			TweenService:Create(puddle, TweenInfo.new(3.5), { Transparency = 1 }):Play()
			task.delay(3.5, function()
				puddle:Destroy()
			end)
		elseif how == "bounce" then
			burst(ctx, ground, Color3.fromRGB(255, 200, 240), 20, SPARKLE)
			-- Bounce once, then roll off across the path.
			local dir = side * -1
			local bounceStart = os.clock()
			local from = landing
			local bounce
			bounce = RunService.Heartbeat:Connect(function()
				if not ctx.alive() or not model.Parent then
					bounce:Disconnect()
					return
				end
				local u = (os.clock() - bounceStart) / 1.6
				if u >= 1 then
					bounce:Disconnect()
					model:Destroy()
					return
				end
				local p = from + Vector3.new(dir * u * 70, math.abs(math.sin(u * math.pi * 3)) * (1 - u) * 12, 0)
				model:PivotTo(CFrame.new(p) * CFrame.Angles(0, 0, -dir * u * 25))
			end)
		elseif how == "splat" then
			-- Snow, hay and frosting burst into a big puff and a few clumps; nothing stays on the path.
			burst(ctx, ground, color, 55)
			burst(ctx, ground + Vector3.new(0, 2, 0), color:Lerp(Color3.new(1, 1, 1), 0.5), 30)
			model:Destroy()
			for _ = 1, 5 do
				local s = rng:NextNumber(1, 2.2)
				local clump = part({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * s,
					Color = color,
					Material = material,
					Parent = ctx.folder,
				})
				local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
				local from = ground + Vector3.new(0, 1, 0)
				local t1 = os.clock()
				local fly
				fly = RunService.Heartbeat:Connect(function()
					local u = (os.clock() - t1) / 0.8
					if u >= 1 or not clump.Parent then
						fly:Disconnect()
						clump:Destroy()
						return
					end
					clump.Position = from + dir * u * 10 + Vector3.new(0, math.sin(u * math.pi) * 4, 0)
					clump.Transparency = u * u
				end)
			end
		else
			-- Rock, ice, wood and candy shatter into pieces that scatter and fade, so the path never gets
			-- blocked up.
			burst(ctx, ground, color:Lerp(Color3.fromRGB(150, 130, 110), 0.5), 40)
			model:Destroy()
			for _ = 1, 7 do
				local s = rng:NextNumber(0.8, 1.8)
				local chunk =
					part({ Size = Vector3.new(s, s, s), Color = color, Material = material, Parent = ctx.folder })
				local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
				local from = ground + Vector3.new(0, 1, 0)
				local chunkSpin = rng:NextUnitVector()
				local t1 = os.clock()
				local fly
				fly = RunService.Heartbeat:Connect(function()
					local u = (os.clock() - t1) / 0.9
					if u >= 1 or not chunk.Parent then
						fly:Disconnect()
						chunk:Destroy()
						return
					end
					local p = from + dir * u * 12 + Vector3.new(0, math.sin(u * math.pi) * 5, 0)
					chunk.CFrame = CFrame.new(p) * CFrame.fromAxisAngle(chunkSpin, u * 10)
					chunk.Transparency = u * u
				end)
			end
		end
	end)
end

-- Roller ---------------------------------------------------------------------------------------------------------

function Hazards.roller(ctx: Context, kind: string, centerZ: number, groundY: number)
	local build = ROLLERS[kind] or ROLLERS.Log
	local model, radius, length = build()
	Hazards.activeRollers += 1
	local released = false
	local function release()
		if not released then
			released = true
			Hazards.activeRollers -= 1
		end
	end
	local width = ctx.trackMaxX - ctx.trackMinX
	local centerX = (ctx.trackMinX + ctx.trackMaxX) / 2
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local warnTime = 1.0
	-- Flashing red lane across the whole path.
	local lane = part({
		Size = Vector3.new(width + 20, 0.2, length + 2),
		CFrame = CFrame.new(centerX, groundY + 0.15, centerZ),
		Color = Color3.fromRGB(255, 30, 30),
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		Parent = ctx.folder,
	})
	TweenService:Create(lane, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.85,
	}):Play()
	for i = 1, 5 do
		local arrow = part({
			Size = Vector3.new(4, 0.25, 1.2),
			CFrame = CFrame.new(ctx.trackMinX + width * i / 6, groundY + 0.2, centerZ)
				* CFrame.Angles(0, if side < 0 then 0 else math.pi, 0),
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			Parent = lane,
		})
		arrow.Name = "Arrow"
	end
	ctx.shake(0.3)

	local startX = if side < 0 then ctx.trackMinX - 25 else ctx.trackMaxX + 25
	local endX = if side < 0 then ctx.trackMaxX + 25 else ctx.trackMinX - 25
	local speed = rng:NextNumber(55, 75)
	local y = groundY + radius
	-- Cylinder axis (local X) along the path (world Z).
	local axisRotation = CFrame.Angles(0, math.pi / 2, 0)
	task.delay(warnTime, function()
		lane:Destroy()
		if not ctx.alive() then
			model:Destroy()
			release()
			return
		end
		Sfx.at(
			if kind == "Log" or kind == "CandyCane" then "WoodCrack" else "Rubble",
			Vector3.new(startX, groundY, centerZ),
			1.6
		)
		model:PivotTo(CFrame.new(startX, y, centerZ) * axisRotation)
		model.Parent = ctx.folder
		local hitAlready = false
		local t0 = os.clock()
		local duration = math.abs(endX - startX) / speed
		local dustTimer = 0
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			if not ctx.alive() or not model.Parent then
				connection:Disconnect()
				model:Destroy()
				release()
				return
			end
			local u = (os.clock() - t0) / duration
			if u >= 1 then
				connection:Disconnect()
				model:Destroy()
				release()
				return
			end
			local x = startX + (endX - startX) * u
			local travelled = math.abs(x - startX)
			local roll = -(travelled / radius) * (if side < 0 then 1 else -1)
			model:PivotTo(CFrame.new(x, y, centerZ) * axisRotation * CFrame.Angles(roll, 0, 0))
			dustTimer -= dt
			if dustTimer <= 0 then
				dustTimer = 0.12
				burst(ctx, Vector3.new(x, groundY, centerZ), Color3.fromRGB(140, 120, 100), 4)
				if rng:NextNumber() < 0.3 then
					Sfx.at("Rubble", Vector3.new(x, groundY, centerZ), 0.8)
				end
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and not hitAlready then
				local p = root.Position
				local feet = p.Y - 3
				if
					math.abs(p.X - x) < radius + 1.2
					and math.abs(p.Z - centerZ) < length / 2 + 1
					and feet < y + radius - 0.6
				then
					hitAlready = true
					ctx.shake(1.2)
					ctx.hit(p, Vector3.new(if side < 0 then 1 else -1, 0, 0))
				end
			end
		end)
	end)
end

-- Flyer: a yellow "SLIDE!" lane flashes across the path, then something is hurled flat across it from the
-- hillside at head height. Standing or jumping into it knocks you back; sliding (Ctrl) takes you under it.
local SLIDE_CLEARANCE = 3.2 -- studs above the ground where the flyer's underside passes

function Hazards.flyer(ctx: Context, kind: string, centerZ: number, groundY: number)
	local build = FLYERS[kind] or FLYERS.Boulder
	local model, radius = build()
	local _, size = model:GetBoundingBox()
	local depth = math.max(size.X, radius * 2) -- its extent along the path once laid along it
	Hazards.activeRollers += 1
	local released = false
	local function release()
		if not released then
			released = true
			Hazards.activeRollers -= 1
		end
	end
	local width = ctx.trackMaxX - ctx.trackMinX
	local centerX = (ctx.trackMinX + ctx.trackMaxX) / 2
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local warnTime = 1.1
	local lane = part({
		Size = Vector3.new(width + 20, 0.2, depth + 3),
		CFrame = CFrame.new(centerX, groundY + 0.15, centerZ),
		Color = Color3.fromRGB(255, 200, 20),
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		Parent = ctx.folder,
	})
	TweenService:Create(lane, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.85,
	}):Play()
	-- A floating "SLIDE!" sign over the lane.
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(220, 70)
	tag.StudsOffsetWorldSpace = Vector3.new(0, SLIDE_CLEARANCE + radius * 2 + 3, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Adornee = lane
	tag.Parent = lane
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 220, 40)
	text.Text = "SLIDE! (Ctrl / C)"
	text.Parent = tag
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(60, 20, 0)
	stroke.Parent = text
	ctx.shake(0.3)

	local startX = if side < 0 then ctx.trackMinX - 40 else ctx.trackMaxX + 40
	local endX = if side < 0 then ctx.trackMaxX + 40 else ctx.trackMinX - 40
	local speed = rng:NextNumber(65, 85)
	local y = groundY + SLIDE_CLEARANCE + radius
	local layAlong = CFrame.Angles(0, math.pi / 2, 0) -- local X along the path (world Z)
	task.delay(warnTime, function()
		lane:Destroy()
		if not ctx.alive() then
			model:Destroy()
			release()
			return
		end
		local from = Vector3.new(startX, groundY + 20, centerZ)
		burst(ctx, from, Color3.fromRGB(140, 120, 100), 16)
		Sfx.at(if kind == "Log" then "WoodCrack" else "Rubble", from, 1.6)
		model:PivotTo(CFrame.new(startX, y, centerZ) * layAlong)
		model.Parent = ctx.folder
		local hitAlready = false
		local whooshed = false
		local t0 = os.clock()
		local duration = math.abs(endX - startX) / speed
		local connection
		connection = RunService.Heartbeat:Connect(function()
			if not ctx.alive() or not model.Parent then
				connection:Disconnect()
				model:Destroy()
				release()
				return
			end
			local u = (os.clock() - t0) / duration
			if u >= 1 then
				connection:Disconnect()
				model:Destroy()
				release()
				return
			end
			local x = startX + (endX - startX) * u
			model:PivotTo(CFrame.new(x, y, centerZ) * layAlong * CFrame.Angles((os.clock() - t0) * 12, 0, 0))
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return
			end
			local p = root.Position
			if not whooshed and math.abs(p.X - x) < 25 and math.abs(p.Z - centerZ) < 25 then
				whooshed = true
				Sfx.at("RockHit", Vector3.new(x, y, centerZ), 1.2, 0.6)
			end
			if hitAlready then
				return
			end
			local feet, head = p.Y - 3, p.Y + 2
			local bottom, top = y - radius, y + radius
			if
				math.abs(p.X - x) < radius + 1.2
				and math.abs(p.Z - centerZ) < depth / 2 + 1
				and not Moves.isBusy() -- sliding: you pass underneath
				and head > bottom
				and feet < top
			then
				hitAlready = true
				ctx.shake(1.2)
				ctx.hit(p, Vector3.new(if side < 0 then 1 else -1, 0, 0))
			end
		end)
	end)
end

-- Forced moves: something spanning the whole path comes straight down it at you, so the only way past is the move it
-- calls for, with a big prompt in the middle of the screen.
--   "Slide": a swooping wall of the biome's flyers (boulders, snowballs, fireballs...) dives in from the sky to
--            chest-to-head height. Standing or jumping into it hurts; sliding (hold Ctrl) takes you under it.
--   "Jump":  a giant roller (log, snow roll, lava rock...) along the ground, too tall for one jump: double jump.
local BARRIER_LOOK = {
	{ Color3.fromRGB(110, 72, 40), Enum.Material.Wood }, -- meadow: a giant log
	{ Color3.fromRGB(240, 248, 255), Enum.Material.Snow }, -- tundra: a snow roll
	{ Color3.fromRGB(205, 160, 100), Enum.Material.Sandstone }, -- dunes: a sandstone pillar
	{ Color3.fromRGB(45, 22, 18), Enum.Material.CrackedLava }, -- hellscape: a lava rock column
	{ Color3.fromRGB(60, 120, 30), Enum.Material.DiamondPlate }, -- toxic: a toxic pipe
	{ Color3.fromRGB(255, 90, 120), Enum.Material.SmoothPlastic }, -- candy: a candy roll
}
local SLIDE_BOTTOM = 2.6 -- the slide wall's underside, studs above the ground (a sliding body fits under)
local JUMP_RADIUS = 4.2 -- the roller is 8.4 studs tall: one jump reaches ~6.5, a double jump ~13

function Hazards.barrier(ctx: Context, mode: string, biome: number, kinds: { string }, start: Vector3, groundY: number)
	local dir = Vector3.new(-ctx.toBase.X, 0, -ctx.toBase.Z).Unit -- it travels away from the bases, at the player
	local width = ctx.trackMaxX - ctx.trackMinX + 16
	local centerX = (ctx.trackMinX + ctx.trackMaxX) / 2
	local model = Instance.new("Model")
	local thickness, bottom, top, y
	local spin = 0
	if mode == "Slide" then
		local count = math.ceil(width / 8)
		local biggest = 0
		local pieces = {}
		for i = 0, count - 1 do
			local build = FLYERS[kinds[(i % #kinds) + 1]] or FLYERS.Boulder
			local piece, r = build()
			biggest = math.max(biggest, r)
			table.insert(pieces, { piece, r, centerX - width / 2 + (i + 0.5) * width / count })
		end
		y = groundY + SLIDE_BOTTOM + biggest
		for _, p in pieces do
			local piece, r, x = p[1], p[2], p[3]
			piece:PivotTo(CFrame.new(x, y + (biggest - r) * 0.3, 0) * CFrame.Angles(rng:NextNumber(0, 6), 0, 0))
			for _, d in piece:GetDescendants() do
				if d:IsA("BasePart") then
					d.Parent = model
				end
			end
			piece:Destroy()
		end
		thickness = biggest
		bottom = groundY + SLIDE_BOTTOM
		top = y + biggest
	else
		local look = BARRIER_LOOK[biome] or BARRIER_LOOK[1]
		local core = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(width, JUMP_RADIUS * 2, JUMP_RADIUS * 2),
			Color = look[1],
			Material = look[2],
		})
		core.CFrame = CFrame.new(centerX, groundY + JUMP_RADIUS, 0)
		core.Parent = model
		for _, x in { -1, 1 } do
			local cap = part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, JUMP_RADIUS * 1.9, JUMP_RADIUS * 1.9),
				Color = look[1]:Lerp(Color3.new(1, 1, 1), 0.35),
				Material = look[2],
			})
			cap.CFrame = core.CFrame * CFrame.new(x * width / 2, 0, 0)
			cap.Parent = model
		end
		for i = 1, 6 do
			local stripe = part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.2, JUMP_RADIUS * 2.05, JUMP_RADIUS * 2.05),
				Color = look[1]:Lerp(Color3.new(0, 0, 0), 0.3),
				Material = look[2],
			})
			stripe.CFrame = core.CFrame * CFrame.new((i - 3.5) * width / 7, 0, 0)
			stripe.Parent = model
		end
		model.PrimaryPart = core
		y = groundY + JUMP_RADIUS
		thickness = JUMP_RADIUS
		bottom = groundY
		top = groundY + JUMP_RADIUS * 2 - 0.3
		spin = 1
	end
	-- built across the path (along world X) around (centerX, y, 0); move it along the path from there
	model.WorldPivot = CFrame.new(centerX, y, 0)
	local function at(along: Vector3, height: number, roll: number): CFrame
		return CFrame.new(along.X, height, along.Z) * CFrame.Angles(roll, 0, 0)
	end
	local origin = Vector3.new(centerX, y, start.Z)
	local speed = 38
	local swoopTime = if mode == "Slide" then 0.5 else 0
	model:PivotTo(at(origin, y + (if mode == "Slide" then 28 else 0), 0))
	model.Parent = ctx.folder
	Hazards.activeRollers += 1
	local hide = if mode == "Slide"
		then HUD.prompt("SLIDE!", "hold Ctrl or C", Color3.fromRGB(255, 220, 40), 4)
		else HUD.prompt("DOUBLE JUMP!", "press Space twice", Color3.fromRGB(90, 220, 255), 4)
	if mode == "Slide" then
		burst(ctx, origin + Vector3.new(0, 28, 0), Color3.fromRGB(150, 130, 110), 25)
		Sfx.at("Rubble", origin + Vector3.new(0, 20, 0), 1.6)
	else
		Sfx.at("WoodCrack", origin, 1.8, 0.7)
	end
	local t0 = os.clock()
	local hitAlready, passed = false, false
	local dustTimer = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local elapsed = os.clock() - t0
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos = origin + dir * speed * elapsed
		if not ctx.alive() or elapsed > 6 or (passed and root and (root.Position - pos):Dot(dir) < -45) then
			connection:Disconnect()
			model:Destroy()
			Hazards.activeRollers -= 1
			hide()
			return
		end
		local swoop = if swoopTime > 0 then math.clamp(elapsed / swoopTime, 0, 1) else 1
		local height = y + 28 * (1 - swoop) ^ 2
		model:PivotTo(at(pos, height, math.sign(dir.Z) * spin * speed * elapsed / JUMP_RADIUS))
		dustTimer -= dt
		if dustTimer <= 0 then
			dustTimer = 0.1
			burst(
				ctx,
				Vector3.new(centerX + rng:NextNumber(-width / 2, width / 2), groundY, pos.Z),
				Color3.fromRGB(160, 140, 120),
				3
			)
		end
		if not root then
			return
		end
		local p = root.Position
		local along = (p - pos):Dot(dir) -- > 0: it hasn't reached you yet
		if along < -thickness - 1.5 and not passed then
			passed = true
			hide()
		end
		if hitAlready or swoop < 1 or math.abs(along) > thickness + 1.2 then
			return
		end
		local feet, head = p.Y - 3, p.Y + 2
		local blocked = if mode == "Slide" then not Moves.isBusy() and head > bottom and feet < top else feet < top
		if blocked then
			hitAlready = true
			ctx.shake(1.3)
			ctx.hit(p, dir)
		end
	end)
end

-- Background spectacle (harmless, never enters the path) ---------------------------------------------------------

local DEBRIS = {
	Boulder = PROJECTILES.Boulder,
	Sandstone = PROJECTILES.Sandstone,
	IceSpike = PROJECTILES.IceSpike,
	Meteor = PROJECTILES.Meteor,
	AcidBlob = PROJECTILES.AcidBlob,
	Gumball = PROJECTILES.Gumball,
	Snowball = function()
		local r = rng:NextNumber(2.5, 4.5)
		return ball(r, Color3.fromRGB(240, 248, 255), Enum.Material.Snow), r
	end,
	LavaRock = function()
		local r = rng:NextNumber(2.5, 4)
		return lumpy(r, Color3.fromRGB(45, 22, 18), Enum.Material.CrackedLava), r
	end,
	Barrel = function()
		local m = log(3.5, 1.6, Color3.fromRGB(60, 120, 30), Enum.Material.DiamondPlate)
		return m, 1.6
	end,
	Log = function()
		local m = log(rng:NextNumber(8, 12), 1.3, Color3.fromRGB(110, 72, 40), Enum.Material.Wood)
		return m, 1.3
	end,
	Avalanche = function()
		local r = rng:NextNumber(3, 5)
		return ball(r, Color3.fromRGB(245, 250, 255), Enum.Material.Snow), r
	end,
	StoneWheel = PROJECTILES.Sandstone,
	CandyCane = PROJECTILES.Lollipop,
}

-- Something breaks loose high on a hillside and tumbles down, bouncing, stopping at the edge of the path.
function Hazards.tumble(ctx: Context, kind: string, side: number, z: number, groundY: number)
	local build = DEBRIS[kind] or PROJECTILES[kind] or FLYERS[kind] or DEBRIS.Boulder
	local model, radius = build()
	local edge = if side < 0 then ctx.trackMinX else ctx.trackMaxX
	local startX = edge + side * rng:NextNumber(35, 85)
	local stopX = edge + side * rng:NextNumber(1, 9)
	local start = Vector3.new(startX, groundY + rng:NextNumber(25, 55), z)
	local finish = Vector3.new(stopX, groundY + radius * 0.7, z + rng:NextNumber(-10, 10))
	local duration = rng:NextNumber(1.4, 2.3)
	local hops = rng:NextInteger(2, 4)
	model:PivotTo(CFrame.new(start))
	model.Parent = ctx.folder
	burst(ctx, start, Color3.fromRGB(150, 130, 110), 12)
	local spin = rng:NextUnitVector()
	local t0 = os.clock()
	local bounced = 0
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not ctx.alive() or not model.Parent then
			connection:Disconnect()
			model:Destroy()
			return
		end
		local u = math.clamp((os.clock() - t0) / duration, 0, 1)
		-- Slide down the slope with decaying hops.
		local base = start:Lerp(finish, 1 - (1 - u) * (1 - u))
		local hop = math.abs(math.sin(u * math.pi * hops)) * (1 - u) * 10
		model:PivotTo(CFrame.new(base + Vector3.new(0, hop, 0)) * CFrame.fromAxisAngle(spin, u * 14))
		local hopIndex = math.floor(u * hops)
		if hopIndex > bounced then
			bounced = hopIndex
			burst(ctx, base, Color3.fromRGB(150, 130, 110), 6)
			if rng:NextNumber() < 0.5 then
				Sfx.at("RockHit", base, 0.7, rng:NextNumber(0.8, 1.2))
			end
		end
		if u >= 1 then
			connection:Disconnect()
			burst(ctx, finish, Color3.fromRGB(150, 130, 110), 20)
			Sfx.at("Rubble", finish, 0.9)
			for _, p in model:GetDescendants() do
				if p:IsA("BasePart") then
					TweenService:Create(p, TweenInfo.new(1.2), { Transparency = 1 }):Play()
				end
			end
			task.delay(1.3, function()
				model:Destroy()
			end)
		end
	end)
end

-- Biome-flavoured eruption at the edge of the path: lava, acid, snow, sand, sprinkles, dirt.
local GEYSERS = {
	{ Color3.fromRGB(120, 95, 60), SMOKE }, -- meadow: dirt
	{ Color3.fromRGB(245, 250, 255), SMOKE }, -- tundra: snow
	{ Color3.fromRGB(225, 195, 135), SMOKE }, -- dunes: sand
	{ Color3.fromRGB(255, 110, 25), FIRE }, -- hellscape: lava
	{ Color3.fromRGB(130, 255, 50), SMOKE }, -- toxic: acid
	{ Color3.fromRGB(255, 150, 220), SPARKLE }, -- candy: sprinkles
}

function Hazards.geyser(ctx: Context, biome: number, position: Vector3)
	local spec = GEYSERS[biome] or GEYSERS[1]
	local holder = part({ Transparency = 1, Size = Vector3.new(4, 1, 4), Position = position, Parent = ctx.folder })
	local e = emitter(holder, {
		Texture = spec[2],
		Color = ColorSequence.new(spec[1]),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 12) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(30, 55),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = Vector3.new(0, -25, 0),
		Rate = 40,
		LightEmission = if spec[2] == FIRE then 1 else 0,
		EmissionDirection = Enum.NormalId.Top,
	})
	Sfx.at("HeavyThud", position, 0.8, 0.7)
	task.delay(1.3, function()
		e.Enabled = false
	end)
	task.delay(3.5, function()
		holder:Destroy()
	end)
end

function Hazards.dust(ctx: Context, position: Vector3, amount: number)
	burst(ctx, position, Color3.fromRGB(150, 130, 110), amount)
end

function Hazards.themeFor(biome: number)
	return Config.HazardThemes[biome] or Config.HazardThemes[1]
end

function Hazards.pick(list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

return Hazards
