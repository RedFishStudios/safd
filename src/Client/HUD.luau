-- Toast notifications, "+1" popups and a hint line. Money / speed live on the UI pack's Hud
-- (driven by UIBridge).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local player = Players.LocalPlayer

local HUD = {}

local gui: ScreenGui
local toastList: Frame
local hintLabel: TextLabel

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	for k, v in props do
		(l :: any)[k] = v
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(15, 15, 25)
	stroke.Parent = l
	l.Parent = parent
	return l
end

function HUD.gui(): ScreenGui
	return gui
end

-- Big action call in the middle of the screen ("SLIDE!", "DOUBLE JUMP!"): pops in, pulses, and stays until the
-- returned function is called (or `duration` runs out).
local promptToken = 0
function HUD.prompt(text: string, sub: string?, color: Color3, duration: number): () -> ()
	promptToken += 1
	local token = promptToken
	local old = gui:FindFirstChild("ActionPrompt")
	if old then
		old:Destroy()
	end
	local frame = Instance.new("Frame")
	frame.Name = "ActionPrompt"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.4)
	frame.Size = UDim2.fromScale(0.5, 0.16)
	frame.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = frame
	local main = label(frame, { Size = UDim2.fromScale(1, 0.72), Text = text, TextColor3 = color })
	local stroke = main:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 5
	if sub then
		label(frame, {
			Position = UDim2.fromScale(0, 0.72),
			Size = UDim2.fromScale(1, 0.28),
			Text = sub,
		})
	end
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(0.25, function()
		if frame.Parent then
			TweenService:Create(
				scale,
				TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.12 }
			):Play()
		end
	end)
	local function hide()
		if token ~= promptToken or not frame.Parent then
			return
		end
		for _, d in frame:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			end
		end
		task.delay(0.22, function()
			frame:Destroy()
		end)
	end
	task.delay(duration, hide)
	return hide
end

function HUD.toast(text: string, color: Color3?, duration: number?)
	local item = label(toastList, {
		Size = UDim2.fromScale(1, 0.16),
		Text = text,
		TextColor3 = color or Color3.new(1, 1, 1),
		TextTransparency = 1,
	})
	local stroke = item:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Transparency = 1
	TweenService:Create(item, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0 }):Play()
	task.delay(duration or 4, function()
		TweenService:Create(item, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		task.wait(0.45)
		item:Destroy()
	end)
end

function HUD.plusOne(text: string?)
	local rng = Random.new()
	local pop = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + rng:NextNumber(-0.06, 0.06), 0.55 + rng:NextNumber(-0.03, 0.03)),
		Size = UDim2.fromScale(0.28, 0.07),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Text = text or "+1 Speed",
		TextColor3 = Color3.fromRGB(110, 255, 120),
		Rotation = rng:NextNumber(-8, 8),
	})
	local stroke = pop:FindFirstChildOfClass("UIStroke") :: UIStroke
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(pop, info, {
		Position = pop.Position - UDim2.fromScale(0, 0.12),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	task.delay(1, function()
		pop:Destroy()
	end)
end

function HUD.setHint(text: string?)
	hintLabel.Text = text or ""
	hintLabel.Visible = text ~= nil
end

function HUD.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_HUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 70 -- (above the shops: "you need $..." used to show behind them)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	toastList = Instance.new("Frame")
	toastList.Name = "Toasts"
	toastList.AnchorPoint = Vector2.new(0.5, 0)
	toastList.Position = UDim2.fromScale(0.5, 0.24)
	toastList.Size = UDim2.fromScale(0.6, 0.3)
	toastList.BackgroundTransparency = 1
	toastList.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = toastList

	hintLabel = label(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.6, 0.035),
		Visible = false,
	})

	Net.event("Notify").OnClientEvent:Connect(function(text: string, color: Color3?)
		HUD.toast(text, color)
	end)
end

return HUD
