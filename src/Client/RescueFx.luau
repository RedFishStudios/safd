-- The rescue's two big moments:
--   * picking an animal up: a card slides in with a close-up picture of the animal, its name and rarity (a second of
--     the same kind stacks on the same card: x2, x3 ...), with a stacked pop + chime (+ a fanfare for epic and up),
--     a sparkle burst on your head and a camera punch
--   * getting home (Net.RunReward from Server/AnimalService): the animals you saved come up on screen, turning in a
--     glow of their rarity colour, and their bonus starts at its base value and grows: every multiplier ring you flew
--     through stamps in ("x2!", "x3!") and the number jumps up, ending on the total with a cash register and confetti.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local AnimalIcon = require(script.Parent.AnimalIcon)
local ChaseFx = require(script.Parent.ChaseFx)

local player = Players.LocalPlayer

local RescueFx = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local RING_COLORS = {
	[2] = Color3.fromRGB(80, 255, 120),
	[3] = Color3.fromRGB(80, 180, 255),
	[5] = Color3.fromRGB(255, 200, 40),
}

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

local function card(id: string)
	local info = Config.Animals[id]
	local rarity = Config.Rarities[info.Rarity]
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
	local vp = AnimalIcon.viewport(pic, id, true)
	AnimalIcon.spin(vp, 1.4)
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

local function onPickup(character: Model, id: string)
	local info = Config.Animals[id]
	if not info then
		return
	end
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
	card(id)
end

local function watch(character: Model)
	character.ChildAdded:Connect(function(child)
		local id = string.match(child.Name, "^Carried_(.+)$")
		if id and child:IsA("Model") then
			onPickup(character, id)
		end
	end)
end

-- the reward -----------------------------------------------------------------------------------------------------

local busy = false

local function countTo(l: TextLabel, from: number, to: number, time: number)
	local t0 = os.clock()
	local nextTick = 0
	local steps = 0
	while true do
		local k = math.min((os.clock() - t0) / time, 1)
		local e = 1 - (1 - k) ^ 3
		l.Text = "$" .. Util.formatNumber(from + (to - from) * e)
		if os.clock() >= nextTick and k < 1 then
			nextTick = os.clock() + 0.06
			steps += 1
			ChaseFx.play("Pop", 0.3, 1 + steps * 0.045)
		end
		if k >= 1 then
			break
		end
		task.wait()
	end
end

local function animalSlot(row: Frame, id: string, i: number, shown: number)
	local a = Config.Animals[id]
	local color = Config.Rarities[a and a.Rarity or 1].Color
	local slot = Instance.new("Frame")
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromScale(math.min(0.42, 0.95 / shown), 1)
	slot.LayoutOrder = i
	slot.Parent = row
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = slot
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.1, 1.1)
	glow.BackgroundColor3 = color
	glow.BorderSizePixel = 0
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(1, 0)
	gc.Parent = glow
	local gg = Instance.new("UIGradient")
	gg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	gg.Parent = glow
	glow.Parent = slot
	task.spawn(function()
		while glow.Parent do
			gg.Rotation = (gg.Rotation + 2) % 360
			task.wait()
		end
	end)
	local vp = AnimalIcon.viewport(slot, id, true)
	AnimalIcon.spin(vp, 1)
	local sc = Instance.new("UIScale")
	sc.Scale = 0
	sc.Parent = slot
	task.delay((i - 1) * 0.12, function()
		TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		ChaseFx.play("Pop", 0.8, 1 + i * 0.1)
	end)
	if a then
		label(slot, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.98),
			Size = UDim2.fromScale(1.2, 0.16),
			Text = a.Name,
			TextColor3 = color,
		})
	end
end

local function reward(info: any)
	if busy or type(info) ~= "table" then
		return
	end
	busy = true
	local base = tonumber(info.Base) or 0
	local rings = if type(info.Rings) == "table" then info.Rings else {}
	local total = tonumber(info.Total) or base
	local ids = if type(info.Animals) == "table" then info.Animals else {}

	local screen = Instance.new("Frame")
	screen.Name = "Reward"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.new(0, 0, 0)
	screen.BackgroundTransparency = 1
	screen.Parent = gui
	TweenService:Create(screen, TweenInfo.new(0.3), { BackgroundTransparency = 0.25 }):Play()

	-- the animals, in a row, each in a turning glow of its rarity colour
	local best = 1
	for _, id in ids do
		local a = Config.Animals[id]
		if a then
			best = math.max(best, a.Rarity)
		end
	end
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.36)
	row.Size = UDim2.fromScale(0.7, 0.36)
	row.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = row
	local shown = math.min(#ids, 4)
	for i = 1, shown do
		animalSlot(row, ids[i], i, shown)
	end
	if #ids > shown then
		label(screen, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.2),
			Size = UDim2.fromScale(0.3, 0.05),
			Text = `+{#ids - shown} more`,
		})
	end
	local title = label(screen, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.13),
		Size = UDim2.fromScale(0.5, 0.08),
		Text = if #ids > 1 then `{#ids} ANIMALS SAVED!` else "ANIMAL SAVED!",
		TextColor3 = Color3.fromRGB(120, 255, 140),
	})
	local tsc = Instance.new("UIScale")
	tsc.Scale = 0.3
	tsc.Parent = title
	TweenService:Create(tsc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	ChaseFx.play("Good", 1, 1)
	if best >= 5 then
		ChaseFx.play("Confetti", 0.8, 1)
	end

	-- the number: from the animals' base up
	local amount = label(screen, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.665),
		Size = UDim2.fromScale(0.5, 0.11),
		Text = "$" .. Util.formatNumber(base),
		TextColor3 = Color3.fromRGB(120, 255, 90),
	})
	local sc = Instance.new("UIScale")
	sc.Parent = amount
	task.wait(0.9)
	local value = base
	for i, v in rings do
		local color = RING_COLORS[v] or RING_COLORS[2]
		local side = (i % 2) * 2 - 1
		local stamp = label(screen, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + side * 0.3, 0.6),
			Size = UDim2.fromScale(0.14, 0.09),
			Text = "x" .. v,
			TextColor3 = color,
			Rotation = side * 12,
		})
		local ssc = Instance.new("UIScale")
		ssc.Scale = 2.4
		ssc.Parent = stamp
		TweenService:Create(ssc, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		TweenService:Create(stamp, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, 0.665),
		}):Play()
		ChaseFx.play("Good", 0.9, 1 + i * 0.07)
		ChaseFx.kick(3)
		task.wait(0.3)
		stamp:Destroy()
		local nextValue = math.min(value * v, base * Config.RunMultiplierCap)
		sc.Scale = 1.3
		TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		countTo(amount, value, nextValue, 0.35)
		value = nextValue
		if i >= 12 then
			break -- (a very long chain: jump to the end)
		end
	end
	amount.Text = "+$" .. Util.formatNumber(total)
	ChaseFx.play("Cash", 1, 1)
	ChaseFx.play("Confetti", 1, 1)
	ChaseFx.kick(7)
	sc.Scale = 1.6
	TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 })
		:Play()
	if #rings > 0 then
		local product = math.floor(total / math.max(base, 1e-9) + 0.5)
		label(screen, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.735),
			Size = UDim2.fromScale(0.35, 0.045),
			Text = `RUN BONUS x{product}`,
			TextColor3 = Color3.fromRGB(255, 230, 120),
		})
	end
	task.wait(1.3)

	TweenService:Create(screen, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	for _, d in screen:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		elseif d:IsA("ViewportFrame") then
			TweenService:Create(d, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			TweenService:Create(d, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		end
	end
	task.delay(0.4, function()
		screen:Destroy()
	end)
	busy = false
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
	Net.event("RunReward").OnClientEvent:Connect(function(info)
		task.spawn(reward, info)
	end)
end

return RescueFx
