-- Picking an egg up: a card slides in with a picture of the egg, its name and rarity (a second of the same kind
-- stacks on the same card: x2, x3 ...), with a stacked pop + chime (+ a fanfare for epic and up), a sparkle burst on
-- your head and a camera punch. (Getting home: the hatch screen, Client/Hatch.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local EggFactory = require(Shared.EggFactory)

local ChaseFx = require(script.Parent.ChaseFx)

local player = Players.LocalPlayer

local RescueFx = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local gui: ScreenGui
local cards: Frame

local function stroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.new(0, 0, 0)
	s.Parent = parent
	return s
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(l :: any)[k] = v
	end
	stroke(l, 2.5)
	l.Parent = parent
	return l
end

local function burst(head: BasePart, color: Color3, amount: number)
	local at = Instance.new("Attachment")
	at.Parent = head
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(12, 24)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -20, 0)
	e.Rate = 0
	e.Parent = at
	e:Emit(amount)
	task.delay(1.2, function()
		at:Destroy()
	end)
end

-- pickup cards ---------------------------------------------------------------------------------------------------

local live: { [string]: { frame: Frame, count: number, countLabel: TextLabel, expires: number } } = {}

-- the egg, turning slowly in a ViewportFrame
local function eggPicture(parent: GuiObject, biome: number, design: number?)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(200, 200, 200)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.7)
	vp.ZIndex = parent.ZIndex + 1
	local model = EggFactory.create(biome, 10, design)
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, 0, -math.max(size.X, size.Y) * 2.1), cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Parent = parent
	local base = model:GetPivot()
	task.spawn(function()
		while vp.Parent do
			model:PivotTo(base * CFrame.Angles(0, os.clock() * 1.2, math.sin(os.clock() * 5) * 0.08))
			task.wait()
		end
	end)
end

local function card(biome: number, design: number?)
	local id = tostring(biome)
	local egg = Config.Eggs[biome]
	local info = { Name = Config.eggName(biome, design) }
	local rarity = Config.Rarities[egg.Rarity]
	local existing = live[id]
	if existing and existing.frame.Parent then
		-- the same kind again: stack on its card
		existing.count += 1
		existing.countLabel.Text = "x" .. existing.count
		existing.countLabel.Visible = true
		existing.expires = os.clock() + 3
		local sc = existing.frame:FindFirstChildOfClass("UIScale") :: UIScale
		sc.Scale = 1.15
		TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		return
	end
	local f = Instance.new("Frame")
	f.Name = id
	f.Size = UDim2.fromScale(1, 0.3)
	f.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	f.BackgroundTransparency = 0.15
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = f
	stroke(f, 3, rarity.Color)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(rarity.Color:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(25, 25, 35))
	g.Parent = f
	local sc = Instance.new("UIScale")
	sc.Scale = 0.2
	sc.Parent = f
	local pic = Instance.new("Frame")
	pic.Name = "Picture"
	pic.BackgroundTransparency = 1
	pic.Size = UDim2.fromScale(0.36, 1)
	pic.Parent = f
	eggPicture(pic, biome, design)
	label(f, {
		Position = UDim2.fromScale(0.38, 0.1),
		Size = UDim2.fromScale(0.58, 0.45),
		Text = info.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label(f, {
		Position = UDim2.fromScale(0.38, 0.55),
		Size = UDim2.fromScale(0.4, 0.3),
		Text = rarity.Name,
		TextColor3 = rarity.Color,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local countLabel = label(f, {
		Position = UDim2.fromScale(0.78, 0.5),
		Size = UDim2.fromScale(0.2, 0.42),
		Text = "x1",
		TextColor3 = Color3.fromRGB(255, 230, 120),
		Visible = false,
	})
	f.Parent = cards
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local entry = { frame = f, count = 1, countLabel = countLabel, expires = os.clock() + 3 }
	live[id] = entry
	task.spawn(function()
		while os.clock() < entry.expires do
			task.wait(0.2)
		end
		TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
			:Play()
		task.wait(0.26)
		f:Destroy()
		if live[id] == entry then
			live[id] = nil
		end
	end)
end

local function onPickup(character: Model, biome: number, design: number?)
	local egg = Config.Eggs[biome]
	if not egg then
		return
	end
	local info = { Rarity = egg.Rarity }
	local rarity = Config.Rarities[info.Rarity]
	local head = character:FindFirstChild("Head") :: BasePart?
	ChaseFx.play("Pop", 1, 1.25)
	task.delay(0.06, function()
		ChaseFx.play("Good", 1, 0.9 + info.Rarity * 0.04)
	end)
	if info.Rarity >= 4 then
		task.delay(0.12, function()
			ChaseFx.play("Confetti", 0.7 + info.Rarity * 0.06, 1)
		end)
	end
	if head then
		burst(head, rarity.Color, 25 + info.Rarity * 8)
	end
	ChaseFx.kick(5 + info.Rarity * 0.6)
	card(biome, design) -- (the card shows the egg's own design)
end

local function watch(character: Model)
	character.ChildAdded:Connect(function(child)
		local biome = tonumber(string.match(child.Name, "^CarriedEgg_(%d+)$"))
		if biome and child:IsA("Model") then
			onPickup(character, biome, child:GetAttribute("Design") :: number?)
		end
	end)
end

function RescueFx.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_Rescue"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 36
	gui.Parent = player:WaitForChild("PlayerGui")
	-- pickup cards stack on the right
	cards = Instance.new("Frame")
	cards.Name = "Cards"
	cards.BackgroundTransparency = 1
	cards.AnchorPoint = Vector2.new(1, 0)
	cards.Position = UDim2.new(1, -16, 0.2, 0)
	cards.Size = UDim2.fromScale(0.2, 0.42)
	cards.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(340, 300)
	limit.Parent = cards
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0.03, 0)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Parent = cards

	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

return RescueFx
