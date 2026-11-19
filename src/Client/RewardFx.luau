-- Money feedback:
--   * every purchase (an upgrade, a trail, a Robux product: Net.Purchased) plays the reference game's cash-register
--     "cha-ching" with a burst of golden sparkles on you and a swell of the money counter
--   * your income every second: a "+$62/s" appears beside your money, floats up and fades (like the reference)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer

local RewardFx = {}

local CASH = "rbxassetid://111773238101465" -- the reference's "Cash" (a cash register)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local function scaleOf(gui: GuiObject): UIScale
	local s = gui:FindFirstChild("SAFD_Pop")
	if s and s:IsA("UIScale") then
		return s
	end
	local made = Instance.new("UIScale")
	made.Name = "SAFD_Pop"
	made.Parent = gui
	return made
end

local function swell(gui: GuiObject?, by: number)
	if not gui then
		return
	end
	local s = scaleOf(gui)
	s.Scale = by
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function RewardFx.init()
	local cash = Instance.new("Sound")
	cash.Name = "SAFD_Cash"
	cash.SoundId = CASH
	cash.Volume = 1.6
	cash.Parent = SoundService
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ cash })
		end)
	end)

	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("Hud", 30)
	local moneyFrame = hud and hud:FindFirstChild("Money", true)
	local moneyAmount = moneyFrame and moneyFrame:FindFirstChild("Amount", true) :: TextLabel?
	local moneyGain = moneyFrame and moneyFrame:FindFirstChild("Gain", true) :: TextLabel?

	-- golden sparkles around you
	local holder = Instance.new("Part")
	holder.Name = "SAFD_RewardFx"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Parent = Workspace
	local at = Instance.new("Attachment")
	at.Parent = holder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(120, 255, 110))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.5, 0.9)
	sparks.Speed = NumberRange.new(10, 20)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -18, 0)
	sparks.Rate = 0
	sparks.Parent = at

	Net.event("Purchased").OnClientEvent:Connect(function()
		local s = cash:Clone()
		s.Volume = cash.Volume * (player:GetAttribute("SfxVolume") or 0.5) * 2
		s.Parent = SoundService
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			at.WorldPosition = root.Position + Vector3.new(0, 1, 0)
			sparks:Emit(40)
		end
		swell(moneyAmount, 1.35)
	end)

	-- income, every second
	local popGui = Instance.new("ScreenGui")
	popGui.Name = "IncomePopups"
	popGui.IgnoreGuiInset = false -- (AbsolutePosition is measured from below the top bar: this way a copy lands right on the HUD label)
	popGui.ResetOnSpawn = false
	popGui.DisplayOrder = 19
	popGui.Parent = playerGui
	-- Like the reference (the user's video, 2026-11-19): the "+$62/s" beside your money isn't a fixed label; every
	-- second a fresh one appears in its place, floats up about a line and fades away. (The HUD's own Gain label stays
	-- where it is, invisible, as the place to start from and the text to copy.)
	local hidden = false
	local function hideGain(g: TextLabel)
		if hidden then
			return
		end
		hidden = true
		g.TextTransparency = 1
		for _, c in g:GetChildren() do
			if c:IsA("UIStroke") then
				c.Transparency = 1
			end
		end
	end
	local function incomePop(_amount: number)
		local g = moneyGain
		if not (g and g.Visible and g.Text ~= "") then
			return
		end
		hideGain(g)
		local pos, size = g.AbsolutePosition, g.AbsoluteSize
		local t = g:Clone()
		for _, c in t:GetChildren() do
			if not (c:IsA("UIStroke") or c:IsA("UIGradient") or c:IsA("UITextSizeConstraint")) then
				c:Destroy()
			end
		end
		t.Name = "IncomePop"
		t.AnchorPoint = Vector2.zero
		t.Size = UDim2.fromOffset(size.X, size.Y)
		t.Position = UDim2.fromOffset(pos.X, pos.Y)
		t.TextTransparency = 0
		t.LayoutOrder = 0
		local strokes = {}
		for _, c in t:GetChildren() do
			if c:IsA("UIStroke") then
				c.Transparency = 0
				table.insert(strokes, c)
			end
		end
		local sc = Instance.new("UIScale")
		sc.Scale = 0.85
		sc.Parent = t
		t.Parent = popGui
		TweenService:Create(sc, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		TweenService:Create(t, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(pos.X, pos.Y - size.Y * 1.15),
		}):Play()
		local fade = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.3)
		TweenService:Create(t, fade, { TextTransparency = 1 }):Play()
		for _, st in strokes do
			TweenService:Create(st, fade, { Transparency = 1 }):Play()
		end
		task.delay(0.9, function()
			t:Destroy()
		end)
		swell(moneyAmount, 1.06)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			local income = player:GetAttribute("Income") or 0
			if income > 0 and player:GetAttribute("Loaded") then
				incomePop(income)
			end
		end
	end)
end

return RewardFx
