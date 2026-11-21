-- Builds animal models from the templates in ReplicatedStorage.Assets.
-- Falls back to a simple placeholder when a template is missing, so the game stays playable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)

local AnimalFactory = {}

-- Children that are only needed for editing/animating and would bloat every clone.
local STRIP = { Animations = true, AnimSaves = true, InitialPoses = true }

local templateCache: { [string]: Model } = {}

function AnimalFactory.findTemplate(id: string): Model?
	local cached = templateCache[id]
	if cached and cached.Parent then
		return cached
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	for _, descendant in assets:GetDescendants() do
		if descendant.Name == id and descendant:IsA("Model") then
			templateCache[id] = descendant
			return descendant
		end
	end
	return nil
end

local function placeholder(id: string): Model
	local info = Config.Animals[id]
	local rarity = Config.Rarities[info and info.Rarity or 1]
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2, 3)
	body.Color = rarity.Color
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Color = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.3)
	head.Material = Enum.Material.SmoothPlastic
	head.CFrame = CFrame.new(0, 1.4, -1.6)
	head.Parent = model
	model.PrimaryPart = body
	return model
end

-- Moves the model's pivot to the bottom-centre of its bounding box, upright.
local function pivotToBottom(model: Model)
	local cf, size = model:GetBoundingBox()
	local bottom = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0))
	local root = model.PrimaryPart
	if root then
		root.PivotOffset = root.CFrame:ToObjectSpace(bottom)
	else
		model.WorldPivot = bottom
	end
end

-- Creates a fresh animal model scaled to `height` (and at most `maxWidth` wide), anchored,
-- non-colliding, with its pivot at the bottom-centre. Not parented.
function AnimalFactory.create(id: string, height: number, maxWidth: number): Model
	local template = AnimalFactory.findTemplate(id)
	local model: Model
	if template then
		model = template:Clone()
		for _, child in model:GetChildren() do
			if STRIP[child.Name] then
				child:Destroy()
			end
		end
	else
		model = placeholder(id)
	end
	model.Name = id
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if model.PrimaryPart then
		-- Some pack models have a rotated pivot, which would skew the bounding box used for scaling.
		model.PrimaryPart.PivotOffset = CFrame.identity
	end
	Util.setModelPhysics(model, true)
	-- no shadows: the big animals' shadows cost a lot to draw and darkened whole areas
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = false
		end
	end

	local _, size = model:GetBoundingBox()
	local widest = math.max(size.X, size.Z, 0.1)
	local factor = math.min(height / math.max(size.Y, 0.1), maxWidth / widest)
	if math.abs(factor - 1) > 0.01 then
		model:ScaleTo(model:GetScale() * factor)
	end
	pivotToBottom(model)

	local _, finalSize = model:GetBoundingBox()
	-- the Toxic Wasteland's animals are radioactive: tinted green in Assets, and here a green glow and rising
	-- sparks around them
	local root = model.PrimaryPart
	if model:GetAttribute("Radioactive") and root then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(120, 255, 80)
		light.Range = math.clamp(finalSize.Y * 1.2, 8, 60)
		light.Brightness = 1.5
		light.Shadows = false
		light.Parent = root
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Radiation"
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(Color3.fromRGB(140, 255, 90))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(finalSize.Y * 0.06, 0.3, 3)),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparks.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		sparks.Lifetime = NumberRange.new(1, 1.6)
		sparks.Rate = 6
		sparks.Speed = NumberRange.new(1, 3)
		sparks.Acceleration = Vector3.new(0, 2, 0)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Shape = Enum.ParticleEmitterShape.Box
		sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		sparks.Parent = root
	end
	model:SetAttribute("AnimalId", id)
	model:SetAttribute("Height", finalSize.Y)
	return model
end

return AnimalFactory
