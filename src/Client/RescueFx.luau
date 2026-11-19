-- The rescue's two big moments:
--   * picking an animal up: a stacked pop + chime (+ a fanfare for rare and better), a sparkle burst on your head, a
--     camera punch and "+1 Chicken!" in the rarity's colour
--   * getting home (Net.RunReward from Server/AnimalService): a short cutscene. The camera swings round in front of
--     you, the bonus counts up from $0, then every multiplier ring you flew through stamps in ("x2!", "x3!") and the
--     number jumps up with it, ending on the total with a cash register and confetti.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local ChaseFx = require(script.Parent.ChaseFx)
local Movement = require(script.Parent.Movement)

local player = Players.LocalPlayer

local RescueFx = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local RING_COLORS = {
	[2] = Color3.fromRGB(80, 255, 120),
	[3] = Color3.fromRGB(80, 180, 255),
	[5] = Color3.fromRGB(255, 200, 40),
}

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

local function onPickup(character: Model, id: string)
	local info = Config.Animals[id]
	if not info then
		return
	end
	local rarity = Config.Rarities[info.Rarity]
	local head = character:FindFirstChild("Head") :: BasePart?
	ChaseFx.play("Pop", 1, 1.25)
	task.delay(0.06, function()
		ChaseFx.play("Good", 1, 0.95 + info.Rarity * 0.06)
	end)
	if info.Rarity >= 3 then
		task.delay(0.12, function()
			ChaseFx.play("Confetti", 0.8 + info.Rarity * 0.1, 1)
		end)
	end
	if head then
		burst(head, rarity.Color, 25 + info.Rarity * 12)
	end
	ChaseFx.kick(6 + info.Rarity)
	ChaseFx.pop(`+1 {info.Name}!`, rarity.Color, info.Rarity >= 4)
end

local function watch(character: Model)
	character.ChildAdded:Connect(function(child)
		local id = string.match(child.Name, "^Carried_(.+)$")
		if id and child:IsA("Model") then
			onPickup(character, id)
		end
	end)
end

-- the money cutscene ---------------------------------------------------------------------------------------------

local busy = false

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(l :: any)[k] = v
	end
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.new(0, 0, 0)
	st.Parent = l
	l.Parent = parent
	return l
end

local function countTo(l: TextLabel, from: number, to: number, time: number, tick: boolean)
	local t0 = os.clock()
	local nextTick = 0
	local steps = 0
	while true do
		local k = math.min((os.clock() - t0) / time, 1)
		local e = 1 - (1 - k) ^ 3
		l.Text = "$" .. Util.formatNumber(from + (to - from) * e)
		if tick and os.clock() >= nextTick and k < 1 then
			nextTick = os.clock() + 0.07
			steps += 1
			ChaseFx.play("Pop", 0.35, 1 + steps * 0.05)
		end
		if k >= 1 then
			break
		end
		task.wait()
	end
end

local function reward(info: any)
	if busy or type(info) ~= "table" then
		return
	end
	busy = true
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local base = tonumber(info.Base) or 0
	local rings = if type(info.Rings) == "table" then info.Rings else {}
	local total = tonumber(info.Total) or base

	local gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_RunReward"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 36
	gui.Parent = player:WaitForChild("PlayerGui")

	-- the camera swings round in front of you
	if root and humanoid and humanoid.Health > 0 then
		Movement.locked = true
		humanoid.WalkSpeed = 0
		ChaseFx.letterbox(true)
		local look = root.CFrame.LookVector
		local front =
			CFrame.lookAt(root.Position + look * 12 + Vector3.new(0, 2.5, 0), root.Position + Vector3.new(0, 1, 0))
		task.spawn(ChaseFx.cameraTo, front, 0.55, Enum.EasingStyle.Quad)
	end

	local names = {}
	for _, id in if type(info.Animals) == "table" then info.Animals else {} do
		local a = Config.Animals[id]
		if a then
			local c = Config.Rarities[a.Rarity].Color
			table.insert(names, string.format('<font color="#%s">%s</font>', c:ToHex(), a.Name))
		end
	end
	local title = label(gui, {
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromScale(0.6, 0.08),
		Text = "RESCUED!",
		TextColor3 = Color3.fromRGB(120, 255, 140),
	})
	label(gui, {
		Position = UDim2.fromScale(0.5, 0.275),
		Size = UDim2.fromScale(0.6, 0.045),
		RichText = true,
		Text = table.concat(names, "  "),
	})
	local amount = label(gui, {
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(0.5, 0.11),
		Text = "$0",
		TextColor3 = Color3.fromRGB(120, 255, 90),
	})
	local sc = Instance.new("UIScale")
	sc.Parent = amount
	local tsc = Instance.new("UIScale")
	tsc.Scale = 0.3
	tsc.Parent = title
	TweenService:Create(tsc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	ChaseFx.play("Good", 1, 1)
	task.wait(0.45)

	countTo(amount, 0, base, 0.7, true)
	local value = base
	for i, v in rings do
		local color = RING_COLORS[v] or RING_COLORS[2]
		local stamp = label(gui, {
			Position = UDim2.fromScale(0.5 + ((i % 2) * 2 - 1) * 0.2, 0.6),
			Size = UDim2.fromScale(0.16, 0.09),
			Text = "x" .. v,
			TextColor3 = color,
			Rotation = ((i % 2) * 2 - 1) * 12,
		})
		local ssc = Instance.new("UIScale")
		ssc.Scale = 2.5
		ssc.Parent = stamp
		TweenService:Create(ssc, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		ChaseFx.play("Good", 0.9, 1 + i * 0.07)
		ChaseFx.kick(4)
		local nextValue = math.min(value * v, base * Config.RunMultiplierCap)
		sc.Scale = 1.25
		TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		countTo(amount, value, nextValue, 0.3, false)
		value = nextValue
		task.delay(0.6, function()
			TweenService:Create(stamp, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			local st = stamp:FindFirstChildOfClass("UIStroke")
			if st then
				TweenService:Create(st, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end)
		if i >= 12 then
			break -- (a very long chain: jump to the end)
		end
	end
	amount.Text = "+$" .. Util.formatNumber(total)
	ChaseFx.play("Cash", 1, 1)
	ChaseFx.play("Confetti", 1, 1)
	ChaseFx.kick(8)
	sc.Scale = 1.5
	TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 })
		:Play()
	if #rings > 0 then
		local product = math.floor(total / math.max(base, 1e-9) + 0.5)
		label(gui, {
			Position = UDim2.fromScale(0.5, 0.81),
			Size = UDim2.fromScale(0.4, 0.045),
			Text = `RUN BONUS x{product}`,
			TextColor3 = Color3.fromRGB(255, 230, 120),
		})
	end
	task.wait(1.1)

	ChaseFx.letterbox(false)
	ChaseFx.releaseCamera()
	Movement.locked = false
	for _, d in gui:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
	end
	task.delay(0.35, function()
		gui:Destroy()
	end)
	busy = false
end

function RescueFx.init()
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
	Net.event("RunReward").OnClientEvent:Connect(function(info)
		task.spawn(reward, info)
	end)
end

return RescueFx
