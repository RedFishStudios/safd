-- The six biome eggs (Config.Eggs), built from stud bricks like the map (Shared/MapStyle). One design per biome; each
-- egg is a stack of brick layers (an octagon of three plates per layer) with the biome's colours and decorations.
-- Later biomes get more layers (smoother), more decorations and particles, and are much bigger. NO Neon parts on any
-- egg (user 2026-11-22): bright solid colours, so shapes and details stay clear.
--   EggFactory.create(biome, height) -> Model   (PrimaryPart "Root": an invisible box around the egg; pivot = its
--                                                bottom centre; everything anchored, no collisions)
-- Parts the client animates: Model attributes Halo / Orbit name child models to spin (Client/EggVisuals).

local MapStyle = require(script.Parent.MapStyle)

local EggFactory = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- every egg is designed 10 units tall, then built at height / 10
local UNIT = 10
local CENTRE = 4.2 -- the widest point
local RADIUS = 3.8

-- the egg's radius at height y (a rounder bottom, a narrower top)
local function radiusAt(y: number): number
	if y <= CENTRE then
		local u = (CENTRE - y) / (CENTRE * 1.12)
		return RADIUS * math.sqrt(math.max(0, 1 - u * u))
	end
	local u = (y - CENTRE) / (UNIT - CENTRE)
	return RADIUS * math.max(0, 1 - u * u) ^ 0.55
end
EggFactory.radiusAt = radiusAt

type Builder = {
	model: Model,
	s: number,
	part: (props: { [string]: any }) -> BasePart,
	ring: (y0: number, h: number, extra: number, color: Color3, props: { [string]: any }?) -> (),
	surface: (y: number, angle: number, out: number?) -> CFrame,
	emitter: (at: Vector3, props: { [string]: any }) -> ParticleEmitter,
}

local function builder(model: Model, s: number): Builder
	local b = {} :: Builder
	b.model = model
	b.s = s
	-- props.Size / props.CFrame are in egg units (10 tall); scaled here
	function b.part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in props do
			if k == "Size" then
				p.Size = v * s
			elseif k == "CFrame" then
				p.CFrame = v.Rotation + v.Position * s
			else
				(p :: any)[k] = v
			end
		end
		MapStyle.apply(p)
		p.Parent = model
		return p
	end
	-- an octagon ring of plates from y0 to y0 + h, sticking out `extra` past the egg's surface there
	function b.ring(y0, h, extra, color, props)
		local r = radiusAt(y0 + h / 2) + extra
		for i, size in
			{ Vector3.new(2 * r, h, 1.2 * r), Vector3.new(1.2 * r, h, 2 * r), Vector3.new(1.55 * r, h, 1.55 * r) }
		do
			local t = { Name = "Ring", Size = size, CFrame = CFrame.new(0, y0 + h / 2, 0), Color = color }
			if props then
				for k, v in props do
					(t :: any)[k] = v
				end
			end
			if i == 3 then
				t.CFrame = t.CFrame * CFrame.Angles(0, math.rad(45), 0)
			end
			b.part(t)
		end
	end
	-- a frame on the egg's surface at height y, facing out at angle (radians)
	function b.surface(y, angle, out)
		local r = radiusAt(y) * 0.97 + (out or 0)
		return CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r) * CFrame.Angles(0, -angle + math.pi / 2, 0)
	end
	function b.emitter(at, props)
		local holder = model:FindFirstChild("Root") :: BasePart
		local a = Instance.new("Attachment")
		a.Position = (at - Vector3.new(0, UNIT / 2, 0)) * s
		a.Parent = holder
		local e = Instance.new("ParticleEmitter")
		e.LightEmission = 0.6
		for k, v in props do
			if k == "Size" then
				local keys = {}
				for _, kp in (v :: NumberSequence).Keypoints do
					table.insert(keys, NumberSequenceKeypoint.new(kp.Time, kp.Value * s, kp.Envelope * s))
				end
				e.Size = NumberSequence.new(keys)
			elseif k == "Speed" then
				e.Speed = NumberRange.new(v.Min * s, v.Max * s)
			elseif k == "Acceleration" then
				e.Acceleration = v * s
			else
				(e :: any)[k] = v
			end
		end
		e.Parent = a
		return e
	end
	return b
end

-- the body: n brick layers, coloured by colorAt(i, n, y); twist turns each layer a little (the candy swirl)
local function body(b: Builder, n: number, colorAt: (number, number, number) -> Color3, twist: number?)
	local h = UNIT / n
	for i = 1, n do
		local y = (i - 0.5) * h
		local r = radiusAt(y)
		local color = colorAt(i, n, y)
		local turn = CFrame.Angles(0, (twist or 0) * i, 0)
		local at = CFrame.new(0, y, 0) * turn
		b.part({ Name = "Shell", Size = Vector3.new(2 * r, h, 1.2 * r), CFrame = at, Color = color })
		b.part({ Name = "Shell", Size = Vector3.new(1.2 * r, h, 2 * r), CFrame = at, Color = color })
		b.part({
			Name = "Shell",
			Size = Vector3.new(1.55 * r, h, 1.55 * r),
			CFrame = at * CFrame.Angles(0, math.rad(45), 0),
			Color = color,
		})
	end
end

local function spots(b: Builder, seed: number, count: number, colors: { Color3 }, size: number, y0: number, y1: number)
	local rng = Random.new(seed)
	for i = 1, count do
		local y = rng:NextNumber(y0, y1)
		local a = rng:NextNumber(0, math.pi * 2)
		local sz = size * rng:NextNumber(0.75, 1.25)
		b.part({
			Name = "Spot",
			Size = Vector3.new(sz, sz * 0.8, sz * 0.5),
			CFrame = b.surface(y, a, sz * 0.15),
			Color = colors[(i - 1) % #colors + 1],
		})
	end
end

local function light(b: Builder, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = math.min(60, range * b.s)
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = b.model:FindFirstChild("Root")
end

-- 1 Grassy Meadows: a plain speckled egg in a tuft of grass ---------------------------------------------------------
local function meadow(b: Builder)
	body(b, 8, function(i)
		return if i % 2 == 0 then rgb(242, 228, 186) else rgb(234, 218, 172)
	end)
	b.ring(0, 1.1, 0.35, rgb(95, 180, 60))
	for k = 0, 5 do
		local a = k * math.pi / 3 + 0.3
		b.part({
			Name = "Grass",
			Size = Vector3.new(0.6, 1.6, 0.4),
			CFrame = b.surface(1.2, a, 0.25) * CFrame.Angles(math.rad(-15), 0, 0),
			Color = rgb(110, 200, 70),
		})
	end
	spots(b, 11, 6, { rgb(160, 115, 70), rgb(135, 95, 55) }, 1.1, 2.2, 8)
end

-- 2 Snowy Tundra: an icy egg with a snow cap and ice crystals --------------------------------------------------------
local function tundra(b: Builder)
	body(b, 10, function(i, n)
		if i >= n - 2 then
			return rgb(250, 252, 255)
		end
		return if i % 2 == 0 then rgb(170, 218, 252) else rgb(198, 234, 255)
	end)
	-- the snow cap's drips
	for k = 0, 6 do
		local a = k * math.pi * 2 / 7
		local len = 0.8 + (k % 3) * 0.5
		b.part({
			Name = "Snow",
			Size = Vector3.new(0.9, len, 0.4),
			CFrame = b.surface(7.4 - len / 2, a, 0.1),
			Color = rgb(250, 252, 255),
		})
	end
	b.ring(0, 0.7, 0.6, rgb(240, 248, 255))
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		b.part({
			Name = "Crystal",
			Size = Vector3.new(0.7, 2.6, 0.7),
			CFrame = b.surface(3.2, a, 0.6) * CFrame.Angles(math.rad(-35), 0, math.rad(20)),
			Color = rgb(150, 225, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.15,
		})
	end
end

-- 3 Sandy Dunes: a pharaoh's egg, gold and lapis stripes, a gold band and a turquoise gem -------------------------------
local function dunes(b: Builder)
	body(b, 12, function(i, n)
		if i > n * 0.5 then
			return if i % 2 == 0 then rgb(250, 200, 60) else rgb(40, 75, 195)
		end
		return if i % 2 == 0 then rgb(232, 194, 118) else rgb(222, 182, 104)
	end)
	b.ring(4.6, 0.7, 0.18, rgb(255, 205, 50))
	b.ring(0, 0.6, 0.9, rgb(225, 190, 120))
	b.ring(0.6, 0.4, 0.35, rgb(235, 200, 130))
	-- the gem on the front, in a gold frame
	b.part({
		Name = "GemFrame",
		Size = Vector3.new(1.7, 1.7, 0.4),
		CFrame = b.surface(3.4, math.pi / 2, 0.1),
		Color = rgb(255, 205, 50),
	})
	b.part({
		Name = "Gem",
		Size = Vector3.new(1.1, 1.1, 0.5),
		CFrame = b.surface(3.4, math.pi / 2, 0.25) * CFrame.Angles(0, 0, math.rad(45)),
		Color = rgb(40, 230, 210),
	})
	-- a gold cap on the top
	b.part({ Name = "Cap", Size = Vector3.new(1, 0.7, 1), CFrame = CFrame.new(0, 10.1, 0), Color = rgb(255, 205, 50) })
	b.emitter(Vector3.new(0, 5, 0), {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(255, 225, 120)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 6,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
	}).Shape =
		Enum.ParticleEmitterShape.Sphere
end

-- 4 Fiery Hellscape (Inferno Egg): black basalt with a molten top dripping lava down the shell, orange lava cracks,
-- two horns, a lava pool ringed with rocks, a small flame on top. All plain stud bricks, NO Neon (user 2026-11-22):
-- the lava is bright orange / yellow plastic so the egg's shape and details stay clear.
local LAVA = rgb(255, 120, 30)
local LAVA_HOT = rgb(255, 196, 60)
local BASALT = rgb(48, 38, 38)
local BASALT2 = rgb(68, 46, 42)
local function hellscape(b: Builder)
	body(b, 14, function(i, n)
		if i == n then
			return LAVA_HOT
		elseif i >= n - 2 then
			return LAVA
		end
		return if i % 2 == 0 then BASALT else BASALT2
	end)
	-- lava running down from the molten top
	for k = 0, 9 do
		local a = k * math.pi * 2 / 10 + 0.15
		local len = 1 + ((k * 7) % 4) * 0.55
		b.part({
			Name = "LavaDrip",
			Size = Vector3.new(0.8, len, 0.45),
			CFrame = b.surface(7.9 - len / 2, a, 0.08),
			Color = LAVA,
		})
		b.part({
			Name = "LavaDrop",
			Size = Vector3.new(0.95, 0.6, 0.55),
			CFrame = b.surface(7.9 - len, a, 0.1),
			Color = LAVA_HOT,
		})
	end
	-- lava cracks: chunky zigzags down the lower shell
	for k = 0, 4 do
		local a0 = k * math.pi * 2 / 5 + 0.45
		for y = 0.9, 5.4, 0.9 do
			b.part({
				Name = "Crack",
				Size = Vector3.new(0.55, 1, 0.35),
				CFrame = b.surface(y, a0 + math.sin(y * 1.7 + k) * 0.2, 0.05),
				Color = if y > 3.5 then LAVA_HOT else LAVA,
			})
		end
	end
	-- two horns, dark with orange tips
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			local w = 1.1 - k * 0.3
			b.part({
				Name = "Horn",
				Size = Vector3.new(w, 1.2, w),
				CFrame = CFrame.new(side * (1.5 + k * 0.55), 8.6 + k * 0.9, 0)
					* CFrame.Angles(0, 0, side * math.rad(-25 - k * 15)),
				Color = if k == 2 then LAVA else rgb(30, 18, 18),
			})
		end
	end
	-- the lava pool it sits in, a dark rim and rocks round it
	b.ring(0, 0.35, 2.1, rgb(40, 30, 30))
	b.ring(0.05, 0.35, 1.5, LAVA)
	for k = 0, 6 do
		local a = k * math.pi * 2 / 7 + 0.4
		b.part({
			Name = "Rock",
			Size = Vector3.new(1.3, 1 + (k % 3) * 0.35, 1.1),
			CFrame = b.surface(0.55, a, 2) * CFrame.Angles(0, k, 0),
			Color = if k % 2 == 0 then rgb(40, 30, 30) else rgb(58, 42, 38),
		})
	end
	b.emitter(Vector3.new(0, 10.2, 0), {
		Texture = FIRE,
		Color = ColorSequence.new(rgb(255, 210, 80), rgb(255, 90, 20)),
		LightEmission = 0.5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.7),
		Rate = 12,
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(15, 15),
	})
	b.emitter(Vector3.new(0, 4, 0), {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(255, 160, 40)),
		LightEmission = 0.4,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1, 2),
		Rate = 6,
		Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, 2, 0),
		SpreadAngle = Vector2.new(60, 60),
	}).Shape =
		Enum.ParticleEmitterShape.Sphere
	light(b, rgb(255, 130, 50), 12, 0.8)
end

-- 5 Toxic Wasteland (Radioactive Egg): a bright green shell under a darker bubbling slime top, slime dripping down,
-- a yellow-and-black hazard band, the radiation sign, toxic barrels orbiting it, a slime puddle with tipped barrels.
-- All plain stud bricks, NO Neon (user 2026-11-22): bright solid greens instead of glow, so every detail reads.
local SLIME = rgb(110, 230, 60)
local SLIME_DARK = rgb(60, 150, 40)
local function toxic(b: Builder)
	body(b, 16, function(i, n)
		if i > n - 4 then
			return SLIME_DARK
		end
		return if i % 2 == 0 then rgb(140, 225, 80) else rgb(165, 240, 100)
	end)
	-- bubbling slime on top
	for k = 0, 6 do
		local a = k * math.pi * 2 / 7
		local r = 0.6 + (k % 3) * 0.25
		b.part({
			Name = "Bubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r, r, r) * 2,
			CFrame = CFrame.new(math.cos(a) * 1.1, 9.4 + (k % 2) * 0.4, math.sin(a) * 1.1),
			Color = if k % 2 == 0 then SLIME else rgb(150, 245, 90),
		})
	end
	-- the hazard band: yellow and black blocks round the middle
	local segs = 16
	for k = 0, segs - 1 do
		local a = k * math.pi * 2 / segs
		local r = radiusAt(4.1)
		b.part({
			Name = "Hazard",
			Size = Vector3.new(2 * math.pi * r / segs + 0.12, 1.2, 0.4),
			CFrame = b.surface(4.1, a, 0.12),
			Color = if k % 2 == 0 then rgb(255, 215, 0) else rgb(25, 25, 25),
		})
	end
	-- slime drips from the top
	for k = 0, 10 do
		local a = k * math.pi * 2 / 11 + 0.2
		local len = 1 + ((k * 7) % 4) * 0.6
		-- (none over the radiation sign on the front)
		local off = math.abs((a - math.pi / 2 + math.pi) % (math.pi * 2) - math.pi)
		if off < 0.5 then
			continue
		end
		b.part({
			Name = "Drip",
			Size = Vector3.new(0.75, len, 0.45),
			CFrame = b.surface(7.6 - len / 2, a, 0.1),
			Color = SLIME_DARK,
		})
		b.part({
			Name = "Drop",
			Size = Vector3.new(0.95, 0.7, 0.55),
			CFrame = b.surface(7.6 - len, a, 0.12),
			Color = SLIME,
		})
	end
	-- the radiation sign on the front
	local front = b.surface(6, math.pi / 2, 0.15)
	b.part({ Name = "Sign", Size = Vector3.new(2.6, 2.6, 0.3), CFrame = front, Color = rgb(255, 215, 0) })
	b.part({ Name = "SignDot", Size = Vector3.new(0.6, 0.6, 0.45), CFrame = front, Color = rgb(25, 25, 25) })
	for k = 0, 2 do
		local spin = CFrame.Angles(0, 0, math.rad(90 + k * 120))
		b.part({
			Name = "SignBlade",
			Size = Vector3.new(0.8, 0.9, 0.45),
			CFrame = front * spin * CFrame.new(0.85, 0, 0),
			Color = rgb(25, 25, 25),
		})
	end
	-- three barrels orbiting (spun by Client/EggVisuals)
	local orbit = Instance.new("Model")
	orbit.Name = "Orbit"
	orbit.Parent = b.model
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		local barrel = b.part({
			Name = "Barrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 1, 1),
			CFrame = CFrame.new(math.cos(a) * (RADIUS + 1.8), 5, math.sin(a) * (RADIUS + 1.8))
				* CFrame.Angles(0, 0, math.pi / 2),
			Color = rgb(255, 200, 0),
		})
		barrel.Parent = orbit
		local stripe = b.part({
			Name = "BarrelBand",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 1.08, 1.08),
			CFrame = barrel.CFrame.Rotation + barrel.Position / b.s,
			Color = rgb(30, 30, 30),
		})
		stripe.Parent = orbit
	end
	b.model:SetAttribute("Orbit", "Orbit")
	-- the slime puddle, with two barrels tipped over in it
	b.ring(0, 0.3, 2.2, SLIME_DARK)
	b.ring(0.05, 0.3, 1.6, SLIME)
	for k, a in { 0.9, 3.6 } do
		b.part({
			Name = "TippedBarrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.3, 0.95, 0.95),
			CFrame = b.surface(0.6, a, 2.1) * CFrame.Angles(0, math.rad(20 + k * 40), 0),
			Color = rgb(255, 200, 0),
		})
	end
	b.emitter(Vector3.new(0, 1, 0), {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(140, 255, 90)),
		LightEmission = 0.3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 8,
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(25, 25),
	})
	light(b, rgb(140, 255, 100), 14, 0.8)
end

-- 6 Candyland: an enormous rainbow swirl egg, white frosting dripping from the top, sprinkles, a crown of lollipops
-- with a cherry, candy wings, a golden halo and a frosted cake to stand on -------------------------------------------
local RAINBOW = {
	rgb(240, 95, 165),
	rgb(250, 150, 60),
	rgb(240, 200, 55),
	rgb(75, 200, 120),
	rgb(70, 155, 235),
	rgb(150, 95, 225),
}
local function candyland(b: Builder)
	body(b, 18, function(i, n)
		if i > n - 4 then
			return rgb(248, 236, 242)
		end
		return RAINBOW[(i - 1) % #RAINBOW + 1]
	end, math.rad(9))
	-- frosting drips
	for k = 0, 11 do
		local a = k * math.pi * 2 / 12
		local len = 0.8 + ((k * 5) % 4) * 0.45
		b.part({
			Name = "Frosting",
			Size = Vector3.new(0.8, len, 0.45),
			CFrame = b.surface(7.8 - len / 2, a, 0.08),
			Color = rgb(248, 236, 242),
		})
	end
	spots(b, 66, 34, RAINBOW, 0.45, 1, 7.4)
	-- the cake it stands on
	b.ring(-1.6, 1, 2.6, rgb(255, 150, 200))
	b.ring(-0.6, 0.6, 2.4, rgb(248, 236, 242))
	for k = 0, 9 do
		local a = k * math.pi * 2 / 10
		b.part({
			Name = "Candy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 0.9),
			CFrame = CFrame.new(math.cos(a) * (radiusAt(0) + 2.9), -1.1, math.sin(a) * (radiusAt(0) + 2.9)),
			Color = RAINBOW[k % #RAINBOW + 1],
		})
	end
	-- a crown of lollipops round a cherry
	for k = 0, 4 do
		local a = k * math.pi * 2 / 5
		local base = CFrame.new(math.cos(a) * 0.9, 9.6, math.sin(a) * 0.9)
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(0, 0, math.rad(-20))
		b.part({
			Name = "Stick",
			Size = Vector3.new(0.25, 2.2, 0.25),
			CFrame = base * CFrame.new(0, 1.1, 0),
			Color = rgb(255, 255, 255),
		})
		b.part({
			Name = "Lolly",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, 1.5, 1.5),
			CFrame = base * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Color = RAINBOW[k + 1],
		})
	end
	b.part({
		Name = "Cherry",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = CFrame.new(0, 10.4, 0),
		Color = rgb(235, 30, 60),
	})
	-- candy wings
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			b.part({
				Name = "Wing",
				Size = Vector3.new(4.2 - k * 0.9, 0.9, 0.35),
				CFrame = CFrame.new(side * (RADIUS + 0.6), 5.8 - k * 0.9, -0.4)
					* CFrame.Angles(0, 0, side * math.rad(28 - k * 6))
					* CFrame.new(side * (2.1 - k * 0.45), 0, 0),
				Color = if k % 2 == 0 then rgb(240, 140, 195) else rgb(248, 236, 242),
			})
		end
	end
	-- the halo (spun by Client/EggVisuals)
	local halo = Instance.new("Model")
	halo.Name = "Halo"
	halo.Parent = b.model
	for k = 0, 13 do
		local a = k * math.pi * 2 / 14
		local p = b.part({
			Name = "HaloBit",
			Size = Vector3.new(0.9, 0.3, 0.4),
			CFrame = CFrame.new(math.cos(a) * 2.2, 12, math.sin(a) * 2.2) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = rgb(255, 215, 80),
			Material = Enum.Material.SmoothPlastic,
		})
		p.Parent = halo
	end
	b.model:SetAttribute("Halo", "Halo")
	b.emitter(Vector3.new(0, 5, 0), {
		Texture = SPARK,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, RAINBOW[1]),
			ColorSequenceKeypoint.new(0.5, RAINBOW[3]),
			ColorSequenceKeypoint.new(1, RAINBOW[5]),
		}),
		LightEmission = 0.3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1, 2),
		Rate = 6,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
	}).Shape =
		Enum.ParticleEmitterShape.Sphere
	light(b, rgb(255, 190, 230), 14, 0.6)
end

-- SECOND designs (user 2026-11-22: "another egg per biome ... mix and match"): only for looks, each wild egg picks one
-- of its biome's two designs at random (it means nothing for the hatch). Same rules: stud bricks, the biome's
-- colours and things, more detail further out, NO Neon.

-- 1b Grassy Meadows: a pale green egg with daisies and a band of grass round the bottom
local function meadow2(b: Builder)
	body(b, 8, function(i)
		return if i % 2 == 0 then rgb(150, 210, 95) else rgb(138, 200, 85)
	end)
	b.ring(0, 1.3, 0.3, rgb(100, 185, 60))
	for k = 0, 7 do
		local a = k * math.pi / 4 + 0.2
		b.part({
			Name = "Grass",
			Size = Vector3.new(0.5, 1.3, 0.35),
			CFrame = b.surface(1.5, a, 0.2) * CFrame.Angles(math.rad(-12), 0, math.rad(if k % 2 == 0 then 10 else -10)),
			Color = rgb(120, 205, 75),
		})
	end
	-- daisies: four white petals round a yellow middle
	local rng = Random.new(21)
	for k = 0, 6 do
		local y = 3 + (k % 3) * 1.5
		local a = k * math.pi * 2 / 7 + rng:NextNumber(-0.3, 0.3)
		local at = b.surface(y, a, 0.5)
		for p = 0, 3 do
			b.part({
				Name = "Petal",
				Size = Vector3.new(0.75, 0.75, 0.25),
				CFrame = at * CFrame.Angles(0, 0, p * math.pi / 2) * CFrame.new(0.62, 0, 0),
				Color = rgb(255, 255, 255),
			})
		end
		b.part({ Name = "Middle", Size = Vector3.new(0.7, 0.7, 0.35), CFrame = at, Color = rgb(255, 210, 50) })
	end
end

-- 2b Snowy Tundra: a snowball egg in a red-and-white knitted scarf, with blue snowflakes
local function tundra2(b: Builder)
	body(b, 10, function(i)
		return if i % 2 == 0 then rgb(246, 250, 255) else rgb(232, 240, 252)
	end)
	-- the scarf: a striped band, its end hanging down the front
	b.ring(5.2, 0.6, 0.25, rgb(220, 40, 50))
	b.ring(5.8, 0.4, 0.22, rgb(255, 255, 255))
	for k = 0, 3 do
		b.part({
			Name = "ScarfEnd",
			Size = Vector3.new(1, 0.55, 0.35),
			CFrame = b.surface(5.1 - k * 0.55, math.pi / 2 + 0.4, 0.35),
			Color = if k % 2 == 0 then rgb(220, 40, 50) else rgb(255, 255, 255),
		})
	end
	-- snowflakes: a little plus of blue bricks
	for k = 0, 3 do
		local a = k * math.pi / 2 + 1.2
		local at = b.surface(if k % 2 == 0 then 2.6 else 7.2, a, 0.12)
		b.part({ Name = "Flake", Size = Vector3.new(1.9, 0.45, 0.25), CFrame = at, Color = rgb(120, 190, 255) })
		b.part({ Name = "Flake", Size = Vector3.new(0.45, 1.9, 0.25), CFrame = at, Color = rgb(120, 190, 255) })
	end
	b.ring(0, 0.6, 0.7, rgb(250, 252, 255))
	-- a pom-pom on top
	b.part({
		Name = "PomPom",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.3, 1.3, 1.3),
		CFrame = CFrame.new(0, 10.2, 0),
		Color = rgb(220, 40, 50),
	})
end

-- 3b Sandy Dunes: desert-sunset sandstone layers, a little gold pyramid on top, two cacti in a sand mound
local function dunes2(b: Builder)
	local bands = { rgb(240, 205, 140), rgb(235, 170, 95), rgb(214, 130, 80), rgb(190, 100, 70) }
	body(b, 12, function(i)
		return bands[math.floor((i - 1) / 3) % #bands + 1]
	end)
	b.ring(0, 0.8, 1.2, rgb(236, 200, 130))
	-- the gold pyramid: three shrinking blocks
	for k = 0, 2 do
		local w = 2 - k * 0.6
		b.part({
			Name = "Pyramid",
			Size = Vector3.new(w, 0.5, w),
			CFrame = CFrame.new(0, 9.9 + k * 0.5, 0),
			Color = rgb(255, 205, 50),
		})
	end
	-- an eye-of-the-sun disc on the front
	b.part({
		Name = "Sun",
		Size = Vector3.new(1.6, 1.6, 0.35),
		CFrame = b.surface(5, math.pi / 2, 0.12),
		Color = rgb(255, 205, 50),
	})
	b.part({
		Name = "SunEye",
		Size = Vector3.new(0.7, 0.7, 0.45),
		CFrame = b.surface(5, math.pi / 2, 0.2),
		Color = rgb(40, 75, 195),
	})
	-- two cacti at the foot
	for _, a in { 0.5, 3.8 } do
		local at = b.surface(0.8, a, 1.35)
		b.part({
			Name = "Cactus",
			Size = Vector3.new(0.7, 2.6, 0.7),
			CFrame = at * CFrame.new(0, 0.9, 0),
			Color = rgb(85, 160, 60),
		})
		b.part({
			Name = "CactusArm",
			Size = Vector3.new(0.9, 0.45, 0.45),
			CFrame = at * CFrame.new(0.6, 1.2, 0),
			Color = rgb(85, 160, 60),
		})
		b.part({
			Name = "CactusArm",
			Size = Vector3.new(0.45, 0.9, 0.45),
			CFrame = at * CFrame.new(0.95, 1.6, 0),
			Color = rgb(85, 160, 60),
		})
	end
	b.emitter(Vector3.new(0, 5, 0), {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(255, 225, 120)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 4,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
	}).Shape =
		Enum.ParticleEmitterShape.Sphere
end

-- 4b Fiery Hellscape: a red dragon egg, rows of scales, spikes up its back, held in three gold claws
local function hellscape2(b: Builder)
	body(b, 14, function(i)
		return if i % 2 == 0 then rgb(170, 35, 35) else rgb(135, 25, 30)
	end)
	-- scales: staggered rows of dark red bricks
	for row = 0, 6 do
		local y = 1.4 + row * 1.1
		for k = 0, 7 do
			local a = k * math.pi / 4 + (row % 2) * math.pi / 8
			b.part({
				Name = "Scale",
				Size = Vector3.new(0.9, 0.6, 0.3),
				CFrame = b.surface(y, a, 0.06),
				Color = if (row + k) % 3 == 0 then rgb(255, 150, 40) else rgb(95, 18, 22),
			})
		end
	end
	-- spikes up the back
	for k = 0, 5 do
		local y = 2.6 + k * 1.15
		local size = 0.9 - math.abs(k - 2.5) * 0.12
		b.part({
			Name = "Spike",
			Size = Vector3.new(size, size * 1.6, size),
			CFrame = b.surface(y, -math.pi / 2, 0.35) * CFrame.Angles(math.rad(-30), 0, math.rad(45)),
			Color = rgb(40, 20, 20),
		})
	end
	-- the gold claws holding it
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + 0.5
		for s = 0, 2 do
			b.part({
				Name = "Claw",
				Size = Vector3.new(0.8, 1.1, 0.6),
				CFrame = b.surface(0.6 + s * 1, a, 0.35 - s * 0.1) * CFrame.Angles(math.rad(-18 - s * 14), 0, 0),
				Color = if s == 2 then rgb(255, 235, 150) else rgb(230, 175, 40),
			})
		end
	end
	b.ring(0, 0.4, 1.8, rgb(40, 30, 30))
	b.emitter(Vector3.new(0, 3, 0), {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(255, 150, 40)),
		LightEmission = 0.4,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1, 2),
		Rate = 6,
		Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, 2, 0),
		SpreadAngle = Vector2.new(60, 60),
	}).Shape =
		Enum.ParticleEmitterShape.Sphere
	light(b, rgb(255, 120, 60), 10, 0.6)
end

-- 5b Toxic Wasteland: a metal canister egg, a band of bubbling green slime behind a window, rivets, a valve and pipes
-- on top, a puddle with barrels
local function toxic2(b: Builder)
	body(b, 16, function(i, n)
		if i >= 6 and i <= 10 then
			return rgb(120, 225, 60) -- (the slime window)
		end
		if i > n - 2 then
			return rgb(110, 115, 125)
		end
		return if i % 2 == 0 then rgb(150, 155, 165) else rgb(130, 135, 145)
	end)
	-- the window's frame bands and bubbles in the slime
	b.ring(3.5, 0.35, 0.2, rgb(70, 72, 80))
	b.ring(6.5, 0.35, 0.2, rgb(70, 72, 80))
	for k = 0, 9 do
		local a = k * math.pi * 2 / 10
		b.part({
			Name = "Bubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (0.5 + (k % 3) * 0.2),
			CFrame = b.surface(4.2 + (k % 4) * 0.6, a, 0.15),
			Color = rgb(190, 255, 140),
		})
	end
	-- rivets
	for _, y in { 2.2, 7.8 } do
		for k = 0, 7 do
			b.part({
				Name = "Rivet",
				Size = Vector3.new(0.35, 0.35, 0.3),
				CFrame = b.surface(y, k * math.pi / 4, 0.08),
				Color = rgb(60, 62, 70),
			})
		end
	end
	-- a hazard plate on the front
	local front = b.surface(2.5, math.pi / 2, 0.15)
	b.part({ Name = "Plate", Size = Vector3.new(1.8, 1.2, 0.3), CFrame = front, Color = rgb(255, 215, 0) })
	for k = -1, 1 do
		b.part({
			Name = "PlateStripe",
			Size = Vector3.new(0.3, 1.3, 0.35),
			CFrame = front * CFrame.new(k * 0.6, 0, 0) * CFrame.Angles(0, 0, math.rad(30)),
			Color = rgb(25, 25, 25),
		})
	end
	-- the valve on top and two pipes
	b.part({
		Name = "ValveStem",
		Size = Vector3.new(0.5, 1.2, 0.5),
		CFrame = CFrame.new(0, 10.3, 0),
		Color = rgb(70, 72, 80),
	})
	b.part({
		Name = "Valve",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 1.8, 1.8),
		CFrame = CFrame.new(0, 10.9, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rgb(220, 40, 40),
	})
	for _, side in { -1, 1 } do
		b.part({
			Name = "Pipe",
			Size = Vector3.new(0.6, 2.4, 0.6),
			CFrame = CFrame.new(side * 1.8, 8.6, 0) * CFrame.Angles(0, 0, side * math.rad(-30)),
			Color = rgb(95, 100, 110),
		})
	end
	-- the puddle and two barrels
	b.ring(0, 0.3, 2.2, rgb(60, 150, 40))
	b.ring(0.05, 0.3, 1.6, rgb(110, 230, 60))
	for k, a in { 1.4, 4.2 } do
		b.part({
			Name = "Barrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 1, 1),
			CFrame = b.surface(0.9, a, 2.1) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(k, 0, 0),
			Color = rgb(255, 200, 0),
		})
	end
	b.emitter(Vector3.new(0, 4.5, 0), {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(160, 255, 110)),
		LightEmission = 0.3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 8,
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(25, 25),
	})
	light(b, rgb(140, 255, 100), 12, 0.6)
end

-- 6b Candyland: an ice-cream egg: strawberry, mint and vanilla scoops in a waffle cone, chocolate sauce, sprinkles,
-- wafer sticks, a cherry, and lollipops circling it
local function candyland2(b: Builder)
	local scoops = { rgb(255, 170, 200), rgb(170, 240, 200), rgb(255, 240, 200) }
	body(b, 18, function(i, n)
		if i <= 5 then
			return if i % 2 == 0 then rgb(215, 160, 85) else rgb(195, 140, 70) -- (the cone)
		end
		return scoops[math.floor((i - 6) / ((n - 5) / 3)) % 3 + 1]
	end)
	-- the waffle grid on the cone
	for k = 0, 7 do
		local a = k * math.pi / 4
		b.part({
			Name = "Waffle",
			Size = Vector3.new(0.25, 2.6, 0.3),
			CFrame = b.surface(1.6, a, 0.05) * CFrame.Angles(0, 0, math.rad(25)),
			Color = rgb(150, 100, 50),
		})
	end
	b.ring(2.75, 0.5, 0.35, rgb(255, 255, 255))
	-- chocolate sauce dripping from the top
	for k = 0, 11 do
		local a = k * math.pi * 2 / 12
		local len = 0.8 + ((k * 5) % 4) * 0.45
		b.part({
			Name = "Sauce",
			Size = Vector3.new(0.8, len, 0.45),
			CFrame = b.surface(8.2 - len / 2, a, 0.08),
			Color = rgb(110, 60, 35),
		})
	end
	spots(b, 77, 30, RAINBOW, 0.4, 3.4, 8)
	-- wafer sticks and the cherry
	for _, side in { -1, 1 } do
		b.part({
			Name = "Wafer",
			Size = Vector3.new(0.6, 2.6, 0.6),
			CFrame = CFrame.new(side * 1.1, 10.3, 0.3) * CFrame.Angles(0, 0, side * math.rad(-20)),
			Color = rgb(240, 200, 120),
		})
	end
	b.part({
		Name = "Cherry",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.5, 1.5, 1.5),
		CFrame = CFrame.new(0, 10.5, -0.2),
		Color = rgb(235, 30, 60),
	})
	b.part({
		Name = "Stalk",
		Size = Vector3.new(0.2, 1, 0.2),
		CFrame = CFrame.new(0.2, 11.5, -0.2),
		Color = rgb(80, 140, 50),
	})
	-- lollipops circling it (spun by Client/EggVisuals)
	local orbit = Instance.new("Model")
	orbit.Name = "Orbit"
	orbit.Parent = b.model
	for k = 0, 3 do
		local a = k * math.pi / 2
		local at = CFrame.new(math.cos(a) * (RADIUS + 2), 6, math.sin(a) * (RADIUS + 2)) * CFrame.Angles(0, -a, 0)
		local stick =
			b.part({ Name = "LollyStick", Size = Vector3.new(0.25, 2, 0.25), CFrame = at, Color = rgb(255, 255, 255) })
		stick.Parent = orbit
		local lolly = b.part({
			Name = "Lolly",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, 1.6, 1.6),
			CFrame = at * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Color = RAINBOW[k * 2 % #RAINBOW + 1],
		})
		lolly.Parent = orbit
	end
	b.model:SetAttribute("Orbit", "Orbit")
	-- the plate it stands on
	b.ring(-0.6, 0.6, 2.6, rgb(255, 150, 200))
	b.emitter(Vector3.new(0, 6, 0), {
		Texture = SPARK,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, RAINBOW[1]),
			ColorSequenceKeypoint.new(0.5, RAINBOW[3]),
			ColorSequenceKeypoint.new(1, RAINBOW[5]),
		}),
		LightEmission = 0.3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1, 2),
		Rate = 6,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
	}).Shape =
		Enum.ParticleEmitterShape.Sphere
	light(b, rgb(255, 200, 230), 14, 0.5)
end

local DESIGNS = {
	{ meadow, meadow2 },
	{ tundra, tundra2 },
	{ dunes, dunes2 },
	{ hellscape, hellscape2 },
	{ toxic, toxic2 },
	{ candyland, candyland2 },
}
EggFactory.DesignCount = 2

-- design: 1 or 2 (only the look; nil = 1)
function EggFactory.create(biome: number, height: number, design: number?): Model
	local s = height / UNIT
	local model = Instance.new("Model")
	model.Name = "Egg"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Transparency = 1
	root.Size = Vector3.new(RADIUS * 2, UNIT, RADIUS * 2) * s
	root.CFrame = CFrame.new(0, UNIT / 2 * s, 0)
	root.Parent = model
	model.PrimaryPart = root
	local b = builder(model, s)
	local set = DESIGNS[math.clamp(biome, 1, #DESIGNS)]
	local d = math.clamp(math.floor(tonumber(design) or 1), 1, #set)
	set[d](b)
	model:SetAttribute("Biome", biome)
	model:SetAttribute("Design", d)
	model:SetAttribute("Height", height)
	-- pivot: the bottom centre of everything (the candy egg stands on its cake)
	local cf, size = model:GetBoundingBox()
	-- (with a PrimaryPart, a model pivots on PrimaryPart.CFrame * PivotOffset)
	root.PivotOffset = root.CFrame:Inverse() * CFrame.new(0, cf.Position.Y - size.Y / 2, 0)
	return model
end

return EggFactory
