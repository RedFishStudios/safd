-- Biome title at the top of the screen, copied from "[NEW] Feed and Rob Animals" (AlertsController AreaTitle):
-- walking into a biome shows its name in its difficulty colour with the difficulty emoji on a see-through black
-- band that fades out at both ends, and under it "Recommended:" + the speed icon + the speed points that outrun its
-- wall. It springs in, stays 3 seconds and fades out. The frame itself is the reference's (Assets.RefUI.AreaTitle).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapInfo = require(Shared:WaitForChild("MapInfo"))
local Progression = require(Shared:WaitForChild("Progression"))

local player = Players.LocalPlayer

local AreaBanner = {}

local function tone(l: TextLabel, color: Color3)
	l.TextColor3 = Color3.new(1, 1, 1)
	local g = l:FindFirstChild("Tone") :: UIGradient?
	if not g then
		local made = Instance.new("UIGradient")
		made.Name = "Tone"
		made.Rotation = 90
		made.Parent = l
		g = made
	end
	(g :: UIGradient).Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4), color)
end

function AreaBanner.init()
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local template = assets:WaitForChild("RefUI"):WaitForChild("AreaTitle") :: Frame
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "AreaBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = playerGui

	local areaTitle = template:Clone()
	areaTitle.Visible = false
	areaTitle.Parent = gui
	local band = areaTitle:WaitForChild("Band") :: Frame
	local bandEdge = band:FindFirstChildOfClass("UIStroke")
	local nameLine = band:WaitForChild("NameLine") :: Frame
	local areaName = nameLine:WaitForChild("AreaName") :: TextLabel
	local areaEmoji = nameLine:WaitForChild("Emoji") :: TextLabel
	local recLine = areaTitle:WaitForChild("RecLine") :: Frame
	local recLabel = recLine:WaitForChild("RecLabel") :: TextLabel
	local speedIcon = recLine:WaitForChild("SpeedIcon") :: ImageLabel
	local speedText = recLine:WaitForChild("SpeedText") :: TextLabel
	local pop = areaTitle:WaitForChild("Pop") :: UIScale
	local labels = { areaName, areaEmoji, recLabel, speedText }

	-- (the reference's layout: near the top, the band about 42% of the width)
	areaTitle.AnchorPoint = Vector2.new(0.5, 0)
	areaTitle.Position = UDim2.fromScale(0.5, 0.004)
	areaTitle.Size = UDim2.fromScale(1, 0.19)
	band.AnchorPoint = Vector2.new(0.5, 0)
	band.Position = UDim2.fromScale(0.5, 0.33)
	band.Size = UDim2.fromScale(0.42, 0.36)
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BackgroundTransparency = 0.45
	if bandEdge then
		bandEdge.Enabled = false
	end
	nameLine.Position = UDim2.fromScale(0, 0)
	nameLine.Size = UDim2.fromScale(1, 1)
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, 0),
		NumberSequenceKeypoint.new(0.78, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = band
	recLine.Position = UDim2.fromScale(0.5, 0.72)
	recLine.Size = UDim2.fromScale(1, 0.24)
	tone(speedText, Color3.fromRGB(45, 125, 255))

	local function fitBand()
		local cam = Workspace.CurrentCamera
		local w = if cam then cam.ViewportSize.X else 1000
		local scale = math.max(pop.Scale, 0.05)
		local content = (areaName.AbsoluteSize.X + areaEmoji.AbsoluteSize.X) / scale + 14
		band.Size = UDim2.new(0, math.max(0.42 * w, content + 0.18 * w), 0.36, 0)
	end
	areaName:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBand)
	local BAND_ALPHA = band.BackgroundTransparency

	-- the same speed icon as the HUD's speed counter
	task.spawn(function()
		local hud = playerGui:WaitForChild("Hud", 30)
		local speed = hud and hud:FindFirstChild("Speed", true)
		local icon = speed and speed:FindFirstChild("Icon", true)
		if icon and icon:IsA("ImageLabel") and icon.Image ~= "" then
			speedIcon.Image = icon.Image
		end
	end)

	local function sizeText()
		areaName.TextSize = math.max(12, math.floor(nameLine.AbsoluteSize.Y * 0.64))
		areaEmoji.TextSize = math.max(12, math.floor(nameLine.AbsoluteSize.Y * 0.64))
		recLabel.TextSize = math.max(10, math.floor(recLine.AbsoluteSize.Y * 0.82))
		speedText.TextSize = recLabel.TextSize
	end
	nameLine:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeText)
	recLine:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeText)
	task.defer(sizeText)

	local function setAlpha(a: number, tween: TweenInfo?)
		local function set(inst: Instance, props: { [string]: any })
			if tween then
				TweenService:Create(inst, tween, props):Play()
			else
				for k, v in props do
					(inst :: any)[k] = v
				end
			end
		end
		for _, l in labels do
			set(l, { TextTransparency = a })
			local st = l:FindFirstChildOfClass("UIStroke")
			if st then
				set(st, { Transparency = a })
			end
		end
		set(speedIcon, { ImageTransparency = a })
		set(band, { BackgroundTransparency = a + (1 - a) * BAND_ALPHA })
	end

	local showToken = 0
	local function showArea(b: any)
		showToken += 1
		local token = showToken
		areaName.Text = b.Name
		tone(areaName, b.Difficulty.Color)
		task.defer(fitBand)
		areaEmoji.Text = b.Difficulty.Emoji
		speedText.Text = Progression.short(b.RecommendedSpeed) .. " Speed"
		setAlpha(0)
		areaTitle.Visible = true
		pop.Scale = 0.5
		TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		task.delay(3, function()
			if token ~= showToken then
				return
			end
			setAlpha(1, TweenInfo.new(0.6))
			task.wait(0.65)
			if token == showToken then
				areaTitle.Visible = false
			end
		end)
	end

	local current: number? = nil
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local biome = MapInfo.biomeAt(hrp.Position)
		if biome ~= current then
			current = biome
			if biome then
				showArea(Config.Biomes[biome])
			end
		end
	end)
end

return AreaBanner
