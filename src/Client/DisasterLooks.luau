-- What chases you home, one disaster per biome, in the style of the user's reference picture (2026-11-21, a blocky
-- landslide): a broken-off cliff of big tilted earth slabs, each with a thick capped top dripping over its front
-- edge, chunks and capped clods tumbling out of it, big lavender boulders and snapped logs rolling at its foot, a solid
-- bank of dust puffs along the ground and little cubes flying over the top. The same build, in each biome's stuff:
--   Meadow    LANDSLIDE        orange earth, grass tops, lavender rocks, snapped logs, tan dust
--   Tundra    AVALANCHE        packed snow and ice, white tops, ice boulders, snowy pine logs, white powder
--   Dunes     SANDSTORM        sandstone, sand tops, red rocks, broken stone pillars, sand clouds (+ a tall sand wall)
--   Hellscape LAVA FLOOD       black basalt, glowing lava tops, obsidian, burning logs, smoke, embers
--   Toxic     TOXIC SLUDGE     murky rock, slime tops, mossy rocks, leaking barrels, green gas
--   Candyland CHOCOLATE FLOOD  chocolate, pink frosting, gumballs, candy canes, sugar puffs
-- All plain parts with the map's stud look (Disaster applies MapStyle), plus particles; DisasterLooks.move puts every
-- piece in place each frame with one BulkMoveTo: slabs rock, chunks and boulders tumble, dust puffs churn, cubes arc
-- over. Phones and low graphics get a lighter build (fewer pieces, fewer particles).
-- Local space: -Z points at you (the way it moves), the ground is at y = GROUND, the deadly front face at z = FRONT.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DisasterLooks = {}

local GROUND = -40
local FRONT = -8

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

type Anim = {
	kind: string, -- "heave" | "tumble" | "puff" | "arc"
	phase: number,
	speed: number,
	amount: number,
	axis: Vector3?,
	center: Vector3?,
}

export type Look = {
	model: Model,
	parts: { BasePart },
	offsets: { CFrame },
	anims: { [number]: Anim },
	cache: { CFrame },
	title: string,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local THEMES = {
	{
		title = "LANDSLIDE",
		body = { rgb(205, 110, 45), rgb(185, 95, 38), rgb(220, 125, 55) },
		cap = { rgb(120, 205, 40), rgb(100, 185, 30) },
		rock = { rgb(150, 140, 230), rgb(135, 125, 215) },
		log = "Log",
		dust = rgb(200, 152, 98),
		fly = { rgb(205, 110, 45), rgb(185, 95, 38) },
	},
	{
		title = "AVALANCHE",
		body = { rgb(110, 160, 225), rgb(90, 140, 210), rgb(130, 175, 232) },
		cap = { rgb(250, 252, 255), rgb(235, 242, 255) },
		rock = { rgb(85, 115, 170), rgb(70, 100, 155) },
		log = "Pine",
		dust = rgb(245, 248, 255),
		fly = { rgb(250, 252, 255), rgb(200, 225, 250) },
	},
	{
		title = "SANDSTORM",
		body = { rgb(225, 160, 90), rgb(205, 140, 75), rgb(235, 175, 105) },
		cap = { rgb(245, 215, 140), rgb(235, 200, 120) },
		rock = { rgb(185, 105, 65), rgb(165, 90, 55) },
		log = "Pillar",
		dust = rgb(230, 195, 130),
		fly = { rgb(245, 215, 140), rgb(225, 160, 90) },
		wall = rgb(212, 150, 80), -- (a towering wall of blowing sand behind it all)
	},
	{
		title = "LAVA FLOOD",
		body = { rgb(70, 42, 46), rgb(55, 32, 36), rgb(85, 50, 52) },
		cap = { rgb(255, 105, 20), rgb(255, 70, 10) },
		capNeon = true,
		rock = { rgb(75, 45, 115), rgb(60, 35, 95) },
		log = "Burning",
		dust = rgb(95, 85, 88),
		fly = { rgb(255, 120, 30), rgb(255, 80, 20) },
		flyNeon = true,
		fire = true,
	},
	{
		title = "TOXIC SLUDGE",
		body = { rgb(90, 100, 60), rgb(75, 85, 50), rgb(105, 115, 70) },
		cap = { rgb(120, 225, 40), rgb(100, 205, 30) },
		rock = { rgb(115, 135, 105), rgb(95, 115, 90) },
		log = "Barrel",
		dust = rgb(150, 215, 95),
		fly = { rgb(120, 225, 40), rgb(90, 100, 60) },
		bubbles = true,
	},
	{
		title = "CHOCOLATE FLOOD",
		body = { rgb(125, 68, 36), rgb(105, 56, 30), rgb(140, 80, 44) },
		cap = { rgb(255, 150, 210), rgb(255, 125, 195) },
		rock = "Gumball",
		log = "Cane",
		dust = rgb(255, 220, 238),
		fly = { rgb(255, 80, 160), rgb(90, 200, 255), rgb(255, 230, 60), rgb(150, 255, 120) },
		sprinkles = true,
	},
}

function DisasterLooks.title(biome: number): string
	return (THEMES[biome] or THEMES[1]).title
end

-- phones and low graphics: a lighter build
local function isLite(): boolean
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return true
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return ok and level > 0 and level <= 4
end

local function newPart(
	look: Look,
	shape: Enum.PartType?,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	neon: boolean?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.Plastic
	if shape then
		p.Shape = shape
	end
	p.Parent = look.model
	table.insert(look.parts, p)
	table.insert(look.offsets, offset)
	return p
end

local function animate(look: Look, anim: Anim)
	look.anims[#look.parts] = anim
end

-- a group of parts that moves as one about `center` (a slab with its cap, a boulder, a log)
type Group = { look: Look, base: CFrame, anim: Anim }
local function group(look: Look, center: Vector3, rotation: CFrame, anim: Anim): Group
	anim.center = center
	return { look = look, base = CFrame.new(center) * rotation, anim = anim }
end
local function add(g: Group, shape: Enum.PartType?, size: Vector3, local_: CFrame, color: Color3, neon: boolean?): Part
	local p = newPart(g.look, shape, size, g.base * local_, color, neon)
	animate(g.look, g.anim)
	return p
end

local function pick(rng: Random, list: { any }): any
	return list[rng:NextInteger(1, #list)]
end

-- a broken-off slab of ground: earth with a thick top cap and drips hanging over its front edge
local function slab(look: Look, rng: Random, theme: any, x: number, z: number, w: number, h: number, depth: number)
	local lean = -math.rad(rng:NextNumber(10, 32)) -- (top leaning towards you)
	local roll = math.rad(rng:NextNumber(-14, 14))
	local center = Vector3.new(x, GROUND + h * 0.42, z)
	local g = group(look, center, CFrame.Angles(lean, rng:NextNumber(-0.35, 0.35), roll), {
		kind = "heave",
		phase = rng:NextNumber(0, 6.3),
		speed = rng:NextNumber(1.2, 2),
		amount = rng:NextNumber(0.03, 0.06),
	})
	local body = pick(rng, theme.body)
	add(g, nil, Vector3.new(w, h, depth), CFrame.identity, body)
	-- broken, stepped face: a couple of blocks sticking out of the front
	for _ = 1, 2 do
		local bw, bh = w * rng:NextNumber(0.3, 0.55), h * rng:NextNumber(0.15, 0.35)
		add(
			g,
			nil,
			Vector3.new(bw, bh, 3),
			CFrame.new(
				rng:NextNumber(-w / 2 + bw / 2, w / 2 - bw / 2),
				rng:NextNumber(-h * 0.45, h * 0.2),
				-depth / 2 - 1
			),
			pick(rng, theme.body)
		)
	end
	local capH = math.clamp(h * 0.09, 2, 4)
	local capColor = pick(rng, theme.cap)
	add(g, nil, Vector3.new(w + 1, capH, depth + 1), CFrame.new(0, h / 2 + capH / 2 - 0.4, 0), capColor, theme.capNeon)
	-- drips over the front edge
	local drips = rng:NextInteger(2, 3)
	for k = 1, drips do
		local dw = rng:NextNumber(2.5, 4.5)
		local dh = rng:NextNumber(2, 5)
		local dx = (k - (drips + 1) / 2) * (w / (drips + 0.5)) + rng:NextNumber(-1, 1)
		add(
			g,
			nil,
			Vector3.new(dw, dh, 1.2),
			CFrame.new(dx, h / 2 - dh / 2 + capH * 0.5, -depth / 2 - 0.4),
			capColor,
			theme.capNeon
		)
	end
end

-- a boulder: a big block with smaller ones stuck to it (or a gumball)
local function boulder(look: Look, rng: Random, theme: any, at: Vector3, s: number)
	local g = group(look, at, CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), 0), {
		kind = "tumble",
		phase = rng:NextNumber(0, 6.3),
		speed = rng:NextNumber(0.8, 1.6),
		amount = rng:NextNumber(0.6, 1.4),
		axis = Vector3.new(1, rng:NextNumber(-0.3, 0.3), 0).Unit,
	})
	if theme.rock == "Gumball" then
		local colors =
			{ rgb(255, 70, 90), rgb(90, 200, 255), rgb(255, 230, 60), rgb(150, 255, 120), rgb(200, 120, 255) }
		add(g, Enum.PartType.Ball, Vector3.one * s, CFrame.identity, pick(rng, colors))
		return
	end
	local c = pick(rng, theme.rock)
	add(g, nil, Vector3.new(s, s * 0.8, s * 0.9), CFrame.identity, c)
	add(g, nil, Vector3.one * (s * 0.55), CFrame.new(s * 0.4, s * 0.3, -s * 0.2), pick(rng, theme.rock))
	add(g, nil, Vector3.one * (s * 0.45), CFrame.new(-s * 0.35, -s * 0.15, s * 0.3), c)
end

-- a snapped log (or the biome's version of one)
local function logPiece(look: Look, rng: Random, theme: any, at: Vector3)
	local g =
		group(look, at, CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.3), rng:NextNumber(0.3, 0.9)), {
			kind = "tumble",
			phase = rng:NextNumber(0, 6.3),
			speed = rng:NextNumber(1, 2),
			amount = rng:NextNumber(1, 2),
			axis = Vector3.new(0, 0, 1),
		})
	local len = rng:NextNumber(14, 19)
	local cyl = Enum.PartType.Cylinder
	if theme.log == "Barrel" then
		add(g, cyl, Vector3.new(5, 4, 4), CFrame.identity, rgb(235, 190, 30))
		add(g, cyl, Vector3.new(0.3, 3.4, 3.4), CFrame.new(2.55, 0, 0), rgb(130, 255, 40), true)
		add(g, cyl, Vector3.new(0.4, 4.2, 4.2), CFrame.new(1.2, 0, 0), rgb(60, 60, 60))
		return
	elseif theme.log == "Cane" then
		for k = 0, 4 do
			add(
				g,
				cyl,
				Vector3.new(len / 5, 2, 2),
				CFrame.new(-len / 2 + (k + 0.5) * len / 5, 0, 0),
				if k % 2 == 0 then rgb(230, 30, 50) else rgb(255, 255, 255)
			)
		end
		add(
			g,
			cyl,
			Vector3.new(4, 2, 2),
			CFrame.new(len / 2 + 0.6, 1.4, 0) * CFrame.Angles(0, 0, math.rad(70)),
			rgb(230, 30, 50)
		)
		return
	end
	local wood, inner = rgb(125, 78, 45), rgb(235, 200, 140)
	if theme.log == "Pine" then
		wood, inner = rgb(105, 70, 48), rgb(230, 205, 160)
	elseif theme.log == "Pillar" then
		wood, inner = rgb(235, 215, 170), rgb(205, 180, 135)
	elseif theme.log == "Burning" then
		wood, inner = rgb(40, 30, 30), rgb(255, 110, 20)
	end
	add(g, cyl, Vector3.new(len, 3.6, 3.6), CFrame.identity, wood)
	-- the snapped end: pale splinters (glowing embers on a burning one)
	for k = 1, 4 do
		local a = k / 4 * math.pi * 2
		add(
			g,
			nil,
			Vector3.new(1.6, 0.7, 0.7),
			CFrame.new(len / 2 + 0.5, math.cos(a) * 0.8, math.sin(a) * 0.8)
				* CFrame.Angles(a, 0, rng:NextNumber(-0.4, 0.4)),
			inner,
			theme.log == "Burning"
		)
	end
	if theme.log == "Pine" then
		add(g, nil, Vector3.new(len * 0.6, 0.6, 2.9), CFrame.new(-len * 0.1, 1.4, 0), rgb(250, 252, 255))
	end
end

-- a capped clod tumbling out of the front
local function clod(look: Look, rng: Random, theme: any, at: Vector3, s: number)
	local g = group(look, at, CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3)), {
		kind = "tumble",
		phase = rng:NextNumber(0, 6.3),
		speed = rng:NextNumber(1.5, 3),
		amount = rng:NextNumber(1, 2.5),
		axis = Vector3.new(1, rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.3, 0.3)).Unit,
	})
	add(g, nil, Vector3.new(s, s * 0.8, s), CFrame.identity, pick(rng, theme.body))
	if rng:NextNumber() < 0.5 then
		add(
			g,
			nil,
			Vector3.new(s + 0.4, s * 0.25, s + 0.4),
			CFrame.new(0, s * 0.5, 0),
			pick(rng, theme.cap),
			theme.capNeon
		)
	end
end

local function emitter(holder: BasePart, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Shape = Enum.ParticleEmitterShape.Box
	e.LightInfluence = 0.6
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = holder
	return e
end

local function holder(look: Look, size: Vector3, offset: CFrame): Part
	local p = newPart(look, nil, size, offset, Color3.new())
	p.Transparency = 1
	return p
end

function DisasterLooks.build(biome: number, width: number): Look
	local theme = THEMES[biome] or THEMES[1]
	local rng = Random.new(biome * 31 + 7)
	local lite = isLite()
	local model = Instance.new("Model")
	model.Name = "DisasterWall"
	local look: Look = { model = model, parts = {}, offsets = {}, anims = {}, cache = {}, title = theme.title }
	local colW = 16
	local columns = math.ceil(width / colW)
	local x0 = -width / 2

	for c = 0, columns - 1 do
		local x = x0 + (c + 0.5) * colW
		local wave = (math.sin(c * 0.5) + math.sin(c * 1.3 + 1.7) * 0.5 + 1.5) / 3
		-- the front rank of slabs, uneven heights
		local h = 26 + wave * 18 + rng:NextNumber(0, 8)
		slab(
			look,
			rng,
			theme,
			x + rng:NextNumber(-2, 2),
			FRONT + 13 + rng:NextNumber(-4, 6),
			colW + rng:NextNumber(-1, 3),
			h,
			12
		)
		-- a taller rank behind (every other column; none on light builds)
		if not lite and c % 2 == 0 then
			local h2 = 40 + wave * 20 + rng:NextNumber(0, 10)
			slab(look, rng, theme, x + colW / 2, FRONT + 28, colW * 2 + 2, h2, 14)
		end
		-- a clod tumbling out of the face
		if not lite or c % 2 == 0 then
			local y = GROUND + rng:NextNumber(10, h * 0.85)
			clod(
				look,
				rng,
				theme,
				Vector3.new(x + rng:NextNumber(-5, 5), y, FRONT + 2 - (y - GROUND) * 0.05),
				rng:NextNumber(4, 7)
			)
		end
		-- heaps of rubble: loose blocks of earth piled in front of the slabs
		for _ = 1, if lite then 1 else 3 do
			local s = rng:NextNumber(3.5, 7)
			local at = Vector3.new(
				x + rng:NextNumber(-7, 7),
				GROUND + rng:NextNumber(s * 0.4, 14),
				FRONT + rng:NextNumber(1, 7)
			)
			local g =
				group(look, at, CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3)), {
					kind = "tumble",
					phase = rng:NextNumber(0, 6.3),
					speed = rng:NextNumber(0.6, 1.4),
					amount = rng:NextNumber(0.3, 0.9),
					axis = Vector3.new(1, rng:NextNumber(-0.4, 0.4), 0).Unit,
				})
			add(g, nil, Vector3.one * s, CFrame.identity, pick(rng, theme.body))
		end
		-- boulders at the foot
		if c % 2 == 1 or (not lite and rng:NextNumber() < 0.5) then
			local s = rng:NextNumber(10, 17)
			boulder(
				look,
				rng,
				theme,
				Vector3.new(x + rng:NextNumber(-4, 4), GROUND + s * 0.45, FRONT + rng:NextNumber(0, 4)),
				s
			)
		end
		-- snapped logs
		if c % 4 == 2 then
			logPiece(
				look,
				rng,
				theme,
				Vector3.new(x + rng:NextNumber(-3, 3), GROUND + rng:NextNumber(10, 24), FRONT + rng:NextNumber(1, 6))
			)
		end
		-- the dust bank along the ground in front: chunky puffs
		local puffs = if lite then 1 else 2
		for k = 1, puffs do
			local s = rng:NextNumber(5, 10)
			local p = newPart(
				look,
				nil,
				Vector3.new(s * 1.3, s, s),
				CFrame.new(x + (k - 1.5) * 7 + rng:NextNumber(-2, 2), GROUND + s * 0.4, FRONT - rng:NextNumber(1, 5))
					* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
				theme.dust
			)
			p.Transparency = 0.12
			animate(
				look,
				{ kind = "puff", phase = rng:NextNumber(0, 6.3), speed = rng:NextNumber(2, 3.5), amount = s * 0.25 }
			)
		end
	end
	-- little cubes flying over the top
	local flyers = if lite then 10 else 24
	for i = 1, flyers do
		local s = rng:NextNumber(1.6, 3.2)
		newPart(
			look,
			nil,
			Vector3.one * s,
			CFrame.new(x0 + (i - 0.5) * (width / flyers), GROUND + 46, FRONT + 8),
			pick(rng, theme.fly),
			theme.flyNeon
		)
		animate(look, {
			kind = "arc",
			phase = rng:NextNumber(0, 1),
			speed = rng:NextNumber(0.5, 0.8),
			amount = rng:NextNumber(10, 22),
		})
	end
	-- the sandstorm's own wall of blowing sand, towering behind
	if theme.wall then
		for c = 0, math.ceil(width / 40) - 1 do
			local d = rng:NextNumber(38, 55)
			local p = newPart(
				look,
				Enum.PartType.Ball,
				Vector3.one * d,
				CFrame.new(x0 + (c + 0.5) * 40, GROUND + 55 + rng:NextNumber(-8, 12), FRONT + 40),
				theme.wall
			)
			p.Transparency = 0.18
			animate(
				look,
				{ kind = "tumble", phase = rng:NextNumber(0, 6.3), speed = 0.4, amount = 4, axis = Vector3.xAxis }
			)
		end
	end

	-- particles: dust rolling off the front, a cloud over the top
	local rate = if lite then 0.4 else 1
	local front = holder(look, Vector3.new(width, 6, 4), CFrame.new(0, GROUND + 3, FRONT - 5))
	emitter(front, {
		Color = ColorSequence.new(theme.dust),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 7), NumberSequenceKeypoint.new(1, 16) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(8, 18),
		EmissionDirection = Enum.NormalId.Front,
		SpreadAngle = Vector2.new(30, 25),
		Acceleration = Vector3.new(0, 6, 0),
		Rate = 45 * rate,
	})
	local top = holder(look, Vector3.new(width, 10, 14), CFrame.new(0, GROUND + 50, FRONT + 18))
	emitter(top, {
		Color = ColorSequence.new(theme.dust),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12), NumberSequenceKeypoint.new(1, 30) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(1.8, 3),
		Speed = NumberRange.new(6, 14),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(25, 40),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		Rate = 25 * rate,
	})
	if theme.fire then
		local f = holder(look, Vector3.new(width, 4, 14), CFrame.new(0, GROUND + 40, FRONT + 10))
		emitter(f, {
			Texture = FIRE,
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new(rgb(255, 200, 60), rgb(255, 60, 10)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(10, 20),
			EmissionDirection = Enum.NormalId.Top,
			Rate = 50 * rate,
		})
	end
	if theme.bubbles then
		local b = holder(look, Vector3.new(width, 4, 14), CFrame.new(0, GROUND + 36, FRONT + 10))
		emitter(b, {
			Texture = SPARK,
			LightEmission = 0.8,
			Color = ColorSequence.new(rgb(170, 255, 80)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 4) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(8, 16),
			EmissionDirection = Enum.NormalId.Top,
			Rate = 40 * rate,
		})
	end
	if theme.sprinkles then
		local sp = holder(look, Vector3.new(width, 4, 14), CFrame.new(0, GROUND + 36, FRONT + 10))
		emitter(sp, {
			Texture = SPARK,
			LightEmission = 0.6,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(255, 80, 160)),
				ColorSequenceKeypoint.new(0.33, rgb(90, 200, 255)),
				ColorSequenceKeypoint.new(0.66, rgb(255, 230, 60)),
				ColorSequenceKeypoint.new(1, rgb(150, 255, 120)),
			}),
			Size = NumberSequence.new(1.6),
			Lifetime = NumberRange.new(1, 1.8),
			Speed = NumberRange.new(14, 26),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(50, 50),
			Acceleration = Vector3.new(0, -30, 0),
			Rate = 40 * rate,
		})
	end
	if theme.capNeon and not lite then
		for k = -1, 1 do
			local l = Instance.new("PointLight")
			l.Color = theme.cap[1]
			l.Range = 60
			l.Brightness = 3
			l.Parent = holder(look, Vector3.one, CFrame.new(k * width / 3, GROUND + 20, FRONT - 4))
		end
	end
	for i = 1, #look.parts do
		look.cache[i] = CFrame.identity
	end
	return look
end

-- every piece at its place for the disaster's CFrame `cf` at time t
function DisasterLooks.move(look: Look, cf: CFrame, t: number)
	local cache = look.cache
	for i, offset in look.offsets do
		local a = look.anims[i]
		if not a then
			cache[i] = cf * offset
		elseif a.kind == "heave" then
			-- a slab rocking on its base
			local c = a.center :: Vector3
			local rel = CFrame.new(c):ToObjectSpace(offset)
			local rock = math.sin(t * a.speed + a.phase) * a.amount
			cache[i] = cf * CFrame.new(c) * CFrame.Angles(rock, 0, rock * 0.4) * rel
		elseif a.kind == "tumble" then
			local spin = t * a.speed + a.phase
			local bob = Vector3.new(0, math.sin(spin * 0.7) * a.amount, -math.abs(math.sin(spin * 0.35)) * a.amount)
			local c = a.center
			if c then
				local rel = CFrame.new(c):ToObjectSpace(offset)
				cache[i] = cf * CFrame.new(c + bob) * CFrame.fromAxisAngle(a.axis :: Vector3, spin) * rel
			else
				cache[i] = cf * CFrame.new(bob) * offset * CFrame.fromAxisAngle(a.axis :: Vector3, spin)
			end
		elseif a.kind == "puff" then
			-- dust puffs churning: up, down and a little forward
			local s = t * a.speed + a.phase
			cache[i] = cf * CFrame.new(0, math.abs(math.sin(s)) * a.amount, -math.sin(s * 0.5) * a.amount) * offset
		else -- "arc": little cubes thrown up and over the front
			local u = (t * a.speed + a.phase) % 1
			local up = 4 * u * (1 - u) * a.amount
			cache[i] = cf * CFrame.new(0, up - a.amount * 0.5, -u * 26) * offset * CFrame.Angles(u * 9, u * 6, 0)
		end
	end
	Workspace:BulkMoveTo(look.parts, cache, Enum.BulkMoveMode.FireCFrameChanged)
end

return DisasterLooks
