-- A little floating block island for each biome (the Index's side cards, user 2026-11-21: "like the reference
-- pictures", Throw Food for Animals' Forest / Savanna cards): a chunky checkered top in the biome's ground colours,
-- dripping over a dirt block, with the biome's own things on it (a tree, a pine, a cactus and pyramid, a dead tree and
-- lava, barrels and slime, a lollipop and candy cane) and its egg. Built from plain parts for a ViewportFrame.
--   BiomeDiorama.build(biome) -> Model      BiomeDiorama.card(biome) -> { bg: Color3, name: string }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EggFactory"))

local BiomeDiorama = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- card background, short name, ground (two checker shades), dirt
local LOOKS = {
	{
		bg = rgb(0, 190, 255),
		name = "Grassy Meadows",
		top = { rgb(140, 235, 40), rgb(110, 210, 30) },
		dirt = rgb(150, 95, 55),
	},
	{
		bg = rgb(110, 165, 255),
		name = "Snowy Tundra",
		top = { rgb(245, 250, 255), rgb(215, 230, 250) },
		dirt = rgb(120, 150, 190),
	},
	{
		bg = rgb(255, 95, 0),
		name = "Sandy Dunes",
		top = { rgb(250, 215, 120), rgb(235, 190, 90) },
		dirt = rgb(215, 140, 80),
	},
	{
		bg = rgb(205, 25, 35),
		name = "Fiery Hellscape",
		top = { rgb(70, 45, 45), rgb(50, 32, 32) },
		dirt = rgb(35, 22, 22),
	},
	{
		bg = rgb(80, 185, 20),
		name = "Toxic Wasteland",
		top = { rgb(120, 140, 60), rgb(95, 115, 45) },
		dirt = rgb(70, 60, 45),
	},
	{
		bg = rgb(255, 105, 200),
		name = "Candyland",
		top = { rgb(255, 190, 225), rgb(255, 160, 210) },
		dirt = rgb(140, 80, 50),
	},
}

function BiomeDiorama.card(biome: number): { bg: Color3, name: string }
	return LOOKS[biome] or LOOKS[1]
end

local function block(model: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function ball(model: Model, d: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	local p = block(model, Vector3.one * d, CFrame.new(pos), color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function cyl(model: Model, h: number, d: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = block(model, Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- the island: 8x8 studs, a checkered top 1 thick, drips down the sides, dirt below
local function island(model: Model, look: any)
	local n, s = 4, 2
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local c = look.top[(i + j) % 2 + 1]
			block(model, Vector3.new(s, 1, s), CFrame.new((i - 1.5) * s, 0, (j - 1.5) * s), c)
		end
	end
	block(model, Vector3.new(8, 3.2, 8), CFrame.new(0, -2.1, 0), look.dirt)
	-- drips: the top colour hanging over the edges
	local rng = Random.new(7)
	for side = 0, 3 do
		for k = 0, 3 do
			local h = rng:NextNumber(0.6, 1.8)
			local along = (k - 1.5) * 2
			local x, z = along, 4.05
			if side == 1 then
				x, z = 4.05, along
			elseif side == 2 then
				x, z = along, -4.05
			elseif side == 3 then
				x, z = -4.05, along
			end
			local size = if side % 2 == 0 then Vector3.new(1.9, h, 0.3) else Vector3.new(0.3, h, 1.9)
			block(model, size, CFrame.new(x, -0.5 - h / 2 + 0.5, z), look.top[(k % 2) + 1])
		end
	end
end

local PROPS = {
	-- Meadow: a leafy tree, a grey rock, flowers, a red mushroom
	function(m: Model)
		block(m, Vector3.new(1, 4, 1), CFrame.new(0.8, 2.5, 1), rgb(150, 85, 45))
		block(m, Vector3.new(0.8, 1.6, 0.8), CFrame.new(1.4, 3.6, 1) * CFrame.Angles(0, 0, -0.6), rgb(150, 85, 45))
		block(m, Vector3.new(3, 2.4, 3), CFrame.new(0.8, 5.4, 1), rgb(160, 240, 50))
		block(m, Vector3.new(2.2, 2, 2.2), CFrame.new(-0.6, 4.6, 0.6), rgb(140, 225, 40))
		block(m, Vector3.new(2, 1.8, 2), CFrame.new(2.2, 4.4, 0.4), rgb(140, 225, 40))
		block(m, Vector3.new(1.4, 0.9, 1.1), CFrame.new(-2.6, 0.95, 2.2) * CFrame.Angles(0, 0.4, 0), rgb(200, 200, 205))
		block(m, Vector3.new(0.3, 0.6, 0.3), CFrame.new(2.6, 0.8, -2.4), rgb(240, 240, 240))
		block(m, Vector3.new(1, 0.4, 1), CFrame.new(2.6, 1.2, -2.4), rgb(230, 40, 40))
		for i, c in { rgb(255, 120, 200), rgb(120, 180, 255), rgb(255, 230, 60) } do
			block(m, Vector3.new(0.4, 0.4, 0.4), CFrame.new(-2.8 + i * 0.9, 0.75, -2.6), c)
		end
	end,
	-- Tundra: a snowy pine, ice crystals, a snowman
	function(m: Model)
		block(m, Vector3.new(0.8, 1.6, 0.8), CFrame.new(1, 1.3, 1), rgb(110, 70, 45))
		for i, w in { 3.2, 2.4, 1.6, 0.8 } do
			block(m, Vector3.new(w, 1.1, w), CFrame.new(1, 1.7 + i * 1.05, 1), rgb(40, 120, 70))
			block(m, Vector3.new(w * 0.9, 0.3, w * 0.9), CFrame.new(1, 2.3 + i * 1.05, 1), rgb(250, 252, 255))
		end
		block(
			m,
			Vector3.new(0.7, 2.4, 0.7),
			CFrame.new(-2.4, 1.7, 2.3) * CFrame.Angles(0.2, 0, 0.25),
			rgb(150, 220, 255),
			Enum.Material.Glass
		).Transparency =
			0.2
		block(
			m,
			Vector3.new(0.5, 1.6, 0.5),
			CFrame.new(-2.9, 1.3, 1.6) * CFrame.Angles(-0.2, 0, -0.3),
			rgb(170, 230, 255),
			Enum.Material.Glass
		).Transparency =
			0.2
		ball(m, 1.4, Vector3.new(2.6, 1.2, -2.4), rgb(250, 252, 255))
		ball(m, 1, Vector3.new(2.6, 2.2, -2.4), rgb(250, 252, 255))
		block(m, Vector3.new(0.2, 0.2, 0.5), CFrame.new(2.6, 2.2, -2.85), rgb(255, 140, 30))
	end,
	-- Dunes: a cactus, a little pyramid, a skull-white rock
	function(m: Model)
		block(m, Vector3.new(1, 4, 1), CFrame.new(1.2, 2.5, 1.2), rgb(70, 170, 60))
		block(m, Vector3.new(1.4, 0.7, 0.7), CFrame.new(0.3, 2.4, 1.2), rgb(70, 170, 60))
		block(m, Vector3.new(0.7, 1.4, 0.7), CFrame.new(-0.2, 3.1, 1.2), rgb(70, 170, 60))
		block(m, Vector3.new(1.4, 0.7, 0.7), CFrame.new(2.1, 3, 1.2), rgb(70, 170, 60))
		block(m, Vector3.new(0.7, 1.2, 0.7), CFrame.new(2.6, 3.6, 1.2), rgb(70, 170, 60))
		for i = 0, 2 do
			local w = 3 - i
			block(m, Vector3.new(w, 0.8, w), CFrame.new(-2, 0.9 + i * 0.8, -1.8), rgb(230, 185, 100))
		end
		block(m, Vector3.new(1.2, 0.6, 0.9), CFrame.new(2.6, 0.8, -2.6), rgb(245, 240, 225))
	end,
	-- Hellscape: a dead black tree, a lava pool, obsidian spikes
	function(m: Model)
		block(m, Vector3.new(3.2, 0.2, 2.6), CFrame.new(-1.6, 0.52, -1.8), rgb(255, 110, 20), Enum.Material.Neon)
		block(m, Vector3.new(0.9, 4.4, 0.9), CFrame.new(1.4, 2.7, 1.4) * CFrame.Angles(0, 0, 0.08), rgb(35, 25, 25))
		block(m, Vector3.new(0.5, 2, 0.5), CFrame.new(2.2, 4.3, 1.4) * CFrame.Angles(0, 0, -0.8), rgb(35, 25, 25))
		block(m, Vector3.new(0.5, 1.8, 0.5), CFrame.new(0.6, 4.6, 1.4) * CFrame.Angles(0, 0, 0.8), rgb(35, 25, 25))
		block(
			m,
			Vector3.new(0.9, 2.2, 0.9),
			CFrame.new(-2.6, 1.6, 2.4) * CFrame.Angles(0.2, 0.5, 0.15),
			rgb(55, 30, 70)
		)
		block(m, Vector3.new(0.6, 1.4, 0.6), CFrame.new(2.8, 1.2, -2.6) * CFrame.Angles(-0.2, 0, -0.2), rgb(55, 30, 70))
	end,
	-- Toxic: barrels, a slime puddle, a pipe
	function(m: Model)
		block(m, Vector3.new(3, 0.2, 2.4), CFrame.new(-1.4, 0.52, -1.8), rgb(120, 255, 40), Enum.Material.Neon)
		cyl(m, 1.8, 1.4, CFrame.new(1.6, 1.4, 1.2) * CFrame.Angles(0, 0, 0), rgb(240, 200, 30))
		block(m, Vector3.new(1.2, 0.1, 1.2), CFrame.new(1.6, 2.32, 1.2), rgb(120, 255, 40), Enum.Material.Neon)
		cyl(m, 1.6, 1.2, CFrame.new(-2.4, 1.3, 2) * CFrame.Angles(0, 0, 0.25), rgb(90, 90, 100))
		block(m, Vector3.new(0.8, 3.4, 0.8), CFrame.new(2.8, 2.2, -2.6), rgb(120, 120, 130))
		block(m, Vector3.new(0.8, 0.8, 2), CFrame.new(2.8, 3.5, -1.9), rgb(120, 120, 130))
	end,
	-- Candyland: a lollipop, a candy cane, a cupcake
	function(m: Model)
		block(m, Vector3.new(0.35, 4, 0.35), CFrame.new(1.4, 2.5, 1.4), rgb(255, 255, 255))
		cyl(m, 0.5, 2.8, CFrame.new(1.4, 5.2, 1.4) * CFrame.Angles(0, math.pi / 2, 0), rgb(255, 70, 160))
		cyl(m, 0.55, 1.6, CFrame.new(1.4, 5.2, 1.4) * CFrame.Angles(0, math.pi / 2, 0), rgb(255, 255, 255))
		cyl(m, 0.6, 0.7, CFrame.new(1.4, 5.2, 1.4) * CFrame.Angles(0, math.pi / 2, 0), rgb(120, 220, 255))
		for i = 0, 4 do
			block(
				m,
				Vector3.new(0.5, 0.6, 0.5),
				CFrame.new(-2.6, 0.8 + i * 0.6, 2.2),
				if i % 2 == 0 then rgb(230, 30, 50) else rgb(255, 255, 255)
			)
		end
		block(m, Vector3.new(0.5, 0.5, 1), CFrame.new(-2.6, 3.65, 1.95), rgb(230, 30, 50))
		block(m, Vector3.new(1.6, 1, 1.6), CFrame.new(2.4, 1, -2.3), rgb(250, 210, 140))
		ball(m, 1.7, Vector3.new(2.4, 1.9, -2.3), rgb(255, 170, 220))
		ball(m, 0.5, Vector3.new(2.4, 2.8, -2.3), rgb(230, 30, 50))
	end,
}

function BiomeDiorama.build(biome: number): Model
	local model = Instance.new("Model")
	model.Name = "Diorama"
	local look = LOOKS[biome] or LOOKS[1]
	island(model, look)
	local props = PROPS[biome]
	if props then
		props(model)
	end
	-- the biome's egg in front
	local ok, egg = pcall(EggFactory.create, biome, 2.6)
	if ok and egg then
		egg:PivotTo(CFrame.new(-1.3, 0.5, 0.6) * CFrame.Angles(0, math.pi, 0))
		for _, d in egg:GetDescendants() do
			if d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
		egg.Parent = model
	end
	return model
end

-- a ViewportFrame showing it, slightly from above and the side, like the reference pictures
function BiomeDiorama.viewport(parent: GuiObject, biome: number): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "SAFD_Diorama"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(200, 200, 200)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.4)
	vp.ZIndex = parent.ZIndex + 1
	local model = BiomeDiorama.build(biome)
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local d = math.max(size.X, size.Y, size.Z) * 2.3
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(-0.55, 0.5, -1).Unit * d, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Parent = parent
	return vp
end

return BiomeDiorama
