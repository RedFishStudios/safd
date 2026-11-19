-- The feel of getting faster, ported from "[NEW] Feed and Rob Animals" (SpeedPopupController, SfxController):
-- every treadmill payout (Net.SpeedGain) pops "+N" with the speed icon over your head, which rises and then flies into
-- the HUD speed counter, swelling it; a soft pop plays a step higher each time, climbing a major scale while you keep
-- training (a bell at the top of each octave); and golden sparkles and a ring burst at your feet. Reaching a biome's
-- recommended speed plays a fanfare (confetti + boost) with a toast.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local HUD = require(script.Parent.HUD)

local player = Players.LocalPlayer

local SpeedFx = {}

-- the reference's own sounds (they load in this experience)
local SOUNDS = {
	Pop = { "rbxassetid://72264591133889", 0.5 },
	Good = { "rbxassetid://74756140439068", 0.5 },
	Boost = { "rbxassetid://130787814958279", 0.5 },
	Confetti = { "rbxassetid://73743814975286", 0.5 },
}
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local RING_MESH = "rbxassetid://3270017"
local SCALE = { 0, 2, 4, 5, 7, 9, 11, 12 } -- do re mi fa so la ti do
local BOTTOM = 0.85 -- the pop's pitch for "do"

local templates: { [string]: Sound } = {}

local function play(name: string, volume: number, pitch: number)
	local src = templates[name]
	if not src then
		return
	end
	local s = src:Clone()
	s.Volume = src.Volume * volume * (player:GetAttribute("SfxVolume") or 1)
	s.PlaybackSpeed = pitch
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- 3D burst at the feet: golden sparkles shooting up and out, and a thin ring spreading over the ground
local holder: Part
local sparkAt: Attachment
local sparks: ParticleEmitter
local function burst(big: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	sparkAt.WorldPosition = feet
	sparks:Emit(if big then 26 else 9)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Size = Vector3.one
	ring.Material = Enum.Material.Neon
	ring.Color = if big then Color3.fromRGB(255, 225, 90) else Color3.fromRGB(120, 200, 255)
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(feet) * CFrame.Angles(math.pi / 2, 0, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = RING_MESH
	mesh.Scale = Vector3.new(1, 1, 0.3)
	mesh.Parent = ring
	ring.Parent = Workspace
	local size = if big then 6 else 3.6
	local info = TweenInfo.new(if big then 0.5 else 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(mesh, info, { Scale = Vector3.new(size, size, 0.15) }):Play()
	TweenService:Create(ring, info, { Transparency = 1 }):Play()
	task.delay(0.55, function()
		ring:Destroy()
	end)
end

function SpeedFx.init()
	for name, def in SOUNDS do
		local s = Instance.new("Sound")
		s.Name = "SAFD_SpeedFx_" .. name
		s.SoundId = def[1]
		s.Volume = def[2]
		s.Parent = SoundService
		templates[name] = s
	end
	task.spawn(function()
		local list = {}
		for _, s in templates do
			table.insert(list, s)
		end
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end)

	holder = Instance.new("Part")
	holder.Name = "SAFD_SpeedFx"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Parent = Workspace
	sparkAt = Instance.new("Attachment")
	sparkAt.Parent = holder
	sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 245, 150), Color3.fromRGB(255, 160, 30))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.35, 0.7)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(40, 40)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -20, 0)
	sparks.Rate = 0
	sparks.Parent = sparkAt

	local playerGui = player:WaitForChild("PlayerGui")
	local popGui = Instance.new("ScreenGui")
	popGui.Name = "SpeedPopups"
	popGui.IgnoreGuiInset = true
	popGui.ResetOnSpawn = false
	popGui.DisplayOrder = 20
	popGui.Parent = playerGui

	-- the HUD's speed counter (UI pack): its icon and font for the popups, and it swells as they land
	local hud = playerGui:WaitForChild("Hud", 30)
	local speed = hud and hud:FindFirstChild("Speed", true)
	local icon = speed and speed:FindFirstChild("Icon", true) :: ImageLabel?
	local amount = speed and speed:FindFirstChild("Amount", true) :: TextLabel?
	local iconScale: UIScale? = nil
	local speedScale: UIScale? = nil
	if icon then
		iconScale = icon:FindFirstChildOfClass("UIScale") or Instance.new("UIScale");
		(iconScale :: UIScale).Parent = icon
	end
	if amount then
		speedScale = amount:FindFirstChildOfClass("UIScale") or Instance.new("UIScale");
		(speedScale :: UIScale).Parent = amount
	end
	local function swell(scale: UIScale?, by: number)
		if scale then
			scale.Scale = by
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end

	local live = 0
	local function popup(gain: number, big: boolean)
		if live >= 8 then
			return
		end
		live += 1
		local cam = Workspace.CurrentCamera
		local vp = cam.ViewportSize
		local k = math.clamp(vp.Y / 720, 0.6, 1.6) * (if big then 1.35 else 1)
		local start = Vector2.new(vp.X / 2, vp.Y * 0.45)
		local character = player.Character
		local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
		if head and head:IsA("BasePart") then
			local p, on = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 1.5, 0))
			if on then
				start = Vector2.new(p.X, p.Y)
			end
		end
		start += Vector2.new(math.random(-90, 90), math.random(-50, 10)) * k

		local f = Instance.new("Frame")
		f.BackgroundTransparency = 1
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(160 * k, 44 * k)
		f.Position = UDim2.fromOffset(start.X, start.Y)
		local sc = Instance.new("UIScale")
		sc.Scale = 0
		sc.Parent = f
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, 2 * k)
		list.Parent = f
		if icon then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = icon.Image
			img.Size = UDim2.fromOffset(40 * k, 40 * k)
			img.Rotation = math.random(-12, 12)
			img.LayoutOrder = 1
			img.Parent = f
		end
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromOffset(0, 40 * k)
		t.Text = "+" .. Util.formatNumber(gain)
		t.TextSize = 34 * k
		if amount then
			t.FontFace = amount.FontFace
		else
			t.Font = Enum.Font.FredokaOne
		end
		t.TextColor3 = Color3.new(1, 1, 1)
		t.LayoutOrder = 2
		t.Parent = f
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(255, 250, 140), Color3.fromRGB(255, 150, 20))
		g.Parent = t
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(40, 20, 5)
		st.Thickness = 3 * k
		st.Parent = t
		f.Parent = popGui

		task.spawn(function()
			TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
			TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(start.X, start.Y - 34 * k),
			}):Play()
			task.wait(0.5)
			local target = Vector2.new(vp.X * 0.06, vp.Y * 0.88)
			if icon then
				target = icon.AbsolutePosition + icon.AbsoluteSize / 2 + Vector2.new(0, GuiService:GetGuiInset().Y)
			end
			local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(f, info, { Position = UDim2.fromOffset(target.X, target.Y) }):Play()
			TweenService:Create(sc, info, { Scale = 0.35 }):Play()
			TweenService:Create(t, info, { TextTransparency = 0.6 }):Play()
			task.wait(0.35)
			f:Destroy()
			live -= 1
			swell(iconScale, 1.3)
			swell(speedScale, 1.15)
		end)
	end

	-- the pop climbs a major scale while the payouts keep coming; a pause starts it again from the bottom
	local step, lastGain = 0, 0
	Net.event("SpeedGain").OnClientEvent:Connect(function(gain)
		if type(gain) ~= "number" or gain <= 0 then
			return
		end
		local now = os.clock()
		if now - lastGain > 1.2 then
			step = 0
		end
		lastGain = now
		step += 1
		local note = SCALE[(step - 1) % #SCALE + 1]
		local top = (step % #SCALE) == 0
		play("Pop", 0.45, BOTTOM * 2 ^ (note / 12))
		if top then
			play("Good", 0.35, 1.1)
		end
		burst(top)
		popup(gain, top)
	end)

	-- reaching a biome's recommended speed: fanfare
	local function reached(points: number): number
		local n = 0
		for _, b in Config.Biomes do
			if points >= b.RecommendedSpeed then
				n += 1
			end
		end
		return n
	end
	local known = player:GetAttribute("Speed") ~= nil
	local level = reached(player:GetAttribute("Speed") or 0)
	player:GetAttributeChangedSignal("Speed"):Connect(function()
		local n = reached(player:GetAttribute("Speed") or 0)
		if not known then
			known = true
		elseif n > level then
			play("Confetti", 0.6, 1)
			play("Boost", 0.6, 1.25)
			swell(speedScale, 1.45)
			swell(iconScale, 1.6)
			burst(true)
			local biome = Config.Biomes[n]
			if biome then
				HUD.toast(`You're fast enough for {biome.Name}!`, Color3.fromRGB(255, 220, 90), 4)
			end
		end
		level = n
	end)
end

return SpeedFx
