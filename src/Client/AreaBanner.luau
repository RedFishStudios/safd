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

local ChaseFx = require(script.Parent.ChaseFx)
local DisasterLooks = require(script.Parent.DisasterLooks)
local Movement = require(script.Parent.Movement)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

-- "Are you brave enough?" when you walk into a biome you aren't fast enough for yet (user 2026-11-21). Once per biome
-- until you're back over the white line. Never during the run home or the tutorial.
local warnGui: ScreenGui? = nil
local function dangerWarning(b: number, onDone: () -> ())
	local biome = Config.Biomes[b]
	if warnGui then
		warnGui:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "SAFD_DangerWarn"
	g.ResetOnSpawn = false
	g.DisplayOrder = 40
	g.Parent = player:WaitForChild("PlayerGui")
	warnGui = g
	local box = Ui.frame(g, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6), -- (under the biome banner)
		Size = UDim2.fromScale(0.65, 0.42),
		SizeConstraint = Enum.SizeConstraint.RelativeYY, -- (a share of the screen's height: same look on a phone)
		BackgroundColor3 = Color3.fromRGB(22, 14, 18),
	})
	Ui.corner(box, 0.08)
	local edge = Ui.stroke(box, 5, Color3.fromRGB(255, 60, 40), true)
	local band = Ui.frame(box, { Size = UDim2.fromScale(1, 0.2), BackgroundColor3 = Color3.new(1, 1, 1) })
	Ui.corner(band, 0.35)
	Ui.gradient(band, Color3.fromRGB(255, 90, 60), Color3.fromRGB(200, 20, 30))
	Ui.text(band, {
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.92, 0.8),
		Text = "⚠️ DANGER ZONE! ⚠️",
	}, 3)
	Ui.text(box, {
		Position = UDim2.fromScale(0.05, 0.23),
		Size = UDim2.fromScale(0.9, 0.13),
		Text = "The " .. string.lower(DisasterLooks.title(b)) .. " here is SUPER fast!",
	}, 2)
	local speed = player:GetAttribute("Speed") or 0
	Ui.text(box, {
		RichText = true,
		Position = UDim2.fromScale(0.05, 0.38),
		Size = UDim2.fromScale(0.9, 0.15),
		Text = 'Your speed: <font color="#FF5A4A">⚡'
			.. Progression.short(math.floor(speed))
			.. '</font>   Needed: <font color="#7CFF5A">⚡'
			.. Progression.short(biome.RecommendedSpeed)
			.. "</font>",
	}, 2)
	Ui.text(box, {
		Position = UDim2.fromScale(0.05, 0.55),
		Size = UDim2.fromScale(0.9, 0.12),
		Text = "Are you brave enough to save these eggs? 🥚",
		TextColor3 = Color3.fromRGB(255, 225, 120),
	}, 2)
	local brave = Ui.button(box, "I'M BRAVE! 💪", Ui.ORANGE, {
		Name = "Brave",
		Position = UDim2.fromScale(0.05, 0.73),
		Size = UDim2.fromScale(0.43, 0.2),
	})
	local train = Ui.button(box, "TRAIN FIRST 🏃", Ui.GREEN, {
		Name = "Train",
		Position = UDim2.fromScale(0.52, 0.73),
		Size = UDim2.fromScale(0.43, 0.2),
	})
	Ui.pop(box, 0.3)
	ChaseFx.play("Thud", 0.6, 0.8)
	-- the red edge pulses
	task.spawn(function()
		while g.Parent do
			edge.Transparency = 0.4 + 0.4 * math.sin(os.clock() * 8)
			task.wait()
		end
	end)
	-- (you stop while it's up)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local wasLocked = Movement.locked
	Movement.locked = true
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	local function finish()
		Movement.locked = wasLocked
		g:Destroy()
		if warnGui == g then
			warnGui = nil
		end
		onDone()
	end
	brave.Activated:Connect(function()
		ChaseFx.play("Boost", 0.7, 1.1)
		finish()
	end)
	train.Activated:Connect(function()
		-- back to your treadmill
		local Bases = require(script.Parent.Bases)
		local base = Bases.mine()
		local tread = base and base:FindFirstChild("Treadmill")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos = if tread and tread:IsA("Model")
			then tread:GetPivot().Position
			elseif tread and tread:IsA("BasePart") then tread.Position
			else nil
		if pos and root then
			root.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0))
		end
		ChaseFx.play("Whoosh", 0.7, 1)
		finish()
	end)
end

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
	areaTitle.Position = UDim2.fromScale(0.5, -0.06) -- (higher: user 2026-11-21)
	areaTitle.Size = UDim2.fromScale(1, 0.25) -- (bigger: user 2026-11-21, "make the recommended speed clearer")
	band.AnchorPoint = Vector2.new(0.5, 0)
	band.Position = UDim2.fromScale(0.5, 0.33)
	band.Size = UDim2.fromScale(0.5, 0.36)
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
	recLine.Position = UDim2.fromScale(0.5, 0.71)
	recLine.Size = UDim2.fromScale(1, 0.27)
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
		task.delay(4, function()
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
	local readyAt = math.huge
	task.spawn(function()
		while not player:GetAttribute("Loaded") do
			task.wait(0.2)
		end
		readyAt = os.clock() + 2
	end)
	local acc = 0
	local warned: { [number]: boolean } = {}
	local warning = false
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
		-- (not until your save is in and you stand at your base: right after joining you briefly spawn in the middle of
		-- the map, inside the Dunes, with speed 0, which popped a wrong DANGER ZONE)
		if not player:GetAttribute("Loaded") or player:GetAttribute("Speed") == nil or os.clock() < readyAt then
			return
		end
		local biome = MapInfo.biomeAt(hrp.Position)
		if MapInfo.isSafe(hrp.Position) then
			table.clear(warned)
		end
		if biome ~= current then
			current = biome
			if biome then
				showArea(Config.Biomes[biome])
			end
		end
		-- too slow for it? (never during a run home: then you're running back through it)
		local b = biome and Config.Biomes[biome]
		if
			b
			and not warning
			and not warned[biome :: number]
			and not Ui.busy()
			and (player:GetAttribute("Speed") or 0) < b.RecommendedSpeed
			and not playerGui:FindFirstChild("SAFD_Tutorial")
		then
			warned[biome :: number] = true
			warning = true
			dangerWarning(biome :: number, function()
				warning = false
			end)
		end
	end)
end

return AreaBanner
