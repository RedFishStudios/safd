-- The opening cutscene, on your first visit (Server/Main sets PlayIntro; /intro in the admin panel replays it):
--   1. peace: the camera drifts over Grassy Meadows, chickens peck and wander, a cow grazes, a bunny hops ...
--   2. disaster: the ground rumbles, a wall of lava erupts at the far end of the meadow with a roar
--   3. panic: "!" over every animal, they flee towards the camera with the lava rolling after them
--   4. the hero: a masked hero (you, with a mask and a cape) drops in from the sky and sprints home through the chaos:
--      slides under a lava ball at head height, double jumps a rolling boulder, scoops up a frozen chicken
--   5. title: slow motion, the hero runs at the camera, "SAVE THE ANIMALS!"
-- Everything is local (only you see it) and cleaned up afterwards; Skip ends it at any time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalFactory = require(Shared.AnimalFactory)
local Config = require(Shared.Config)

local AnimalVisuals = require(script.Parent.AnimalVisuals)
local ChaseFx = require(script.Parent.ChaseFx)
local Movement = require(script.Parent.Movement)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local rng = Random.new()

local IntroCutscene = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- the stage: Grassy Meadows. The base is towards -Z.
local X0 = -8
local GROUND = 1
local LAVA_Z = -585
local HERO_LAND_Z = -680
local HERO_SPEED = 32
local END_T = 15.6

local function smooth(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

local function part(folder: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = folder
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function burst(folder: Instance, pos: Vector3, color: Color3, amount: number, texture: string?)
	local holder = part(folder, { Size = Vector3.one, Transparency = 1, Position = pos })
	local e = emitter(holder, {
		Texture = texture or SMOKE,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(10, 26),
		SpreadAngle = Vector2.new(180, 60),
		Rate = 0,
		LightEmission = if texture == FIRE then 0.8 else 0,
	})
	e:Emit(amount)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

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
	st.Parent = l
	l.Parent = parent
	return l
end

-- the hero: a copy of your own avatar, with a mask and a cape
local function makeHero(folder: Instance): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local was = character.Archivable
	character.Archivable = true
	local hero = character:Clone()
	character.Archivable = was
	if not hero then
		return nil, nil, nil
	end
	for _, d in hero:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or (d:IsA("Model") and string.find(d.Name, "^Carried_")) then
			d:Destroy()
		end
	end
	for _, d in hero:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		end
	end
	local humanoid = hero:FindFirstChildOfClass("Humanoid")
	local root = hero:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = hero:FindFirstChild("Head") :: BasePart?
	local torso = (hero:FindFirstChild("Torso") or hero:FindFirstChild("UpperTorso")) :: BasePart?
	if not humanoid or not root then
		hero:Destroy()
		return nil, nil, nil
	end
	root.Anchored = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local function weld(p: BasePart, to: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = to
		w.Part1 = p
		w.Parent = p
		p.Anchored = false
		p.Parent = hero
	end
	if head then
		-- an eye mask with two bright eyes
		local mask = part(hero, {
			Name = "HeroMask",
			Size = Vector3.new(head.Size.X * 0.62, head.Size.Y * 0.32, head.Size.Z * 1.08),
			Color = Color3.fromRGB(20, 20, 28),
			Material = Enum.Material.SmoothPlastic,
		})
		mask.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.08, 0)
		weld(mask, head)
		for _, side in { -1, 1 } do
			local eye = part(hero, {
				Name = "HeroEye",
				Size = Vector3.new(0.22, 0.12, 0.05),
				Color = Color3.fromRGB(255, 255, 255),
				Material = Enum.Material.Neon,
			})
			eye.CFrame = head.CFrame * CFrame.new(side * head.Size.X * 0.15, head.Size.Y * 0.08, -head.Size.Z * 0.56)
			weld(eye, head)
		end
		-- the mask's tails, flapping behind the head
		local tail = part(hero, {
			Name = "HeroMaskTail",
			Size = Vector3.new(0.25, 0.18, 1.6),
			Color = Color3.fromRGB(200, 30, 40),
			Material = Enum.Material.Fabric,
		})
		tail.CFrame = head.CFrame
			* CFrame.new(0, head.Size.Y * 0.08, head.Size.Z * 0.55 + 0.75)
			* CFrame.Angles(0.25, 0, 0)
		weld(tail, head)
	end
	if torso then
		local cape = part(hero, {
			Name = "HeroCape",
			Size = Vector3.new(torso.Size.X * 0.95, torso.Size.Y * 1.25, 0.12),
			Color = Color3.fromRGB(210, 30, 40),
			Material = Enum.Material.Fabric,
		})
		cape.CFrame = torso.CFrame
			* CFrame.new(0, torso.Size.Y * 0.5, torso.Size.Z / 2 + 0.1)
			* CFrame.Angles(0.35, 0, 0)
			* CFrame.new(0, -cape.Size.Y / 2, 0)
		weld(cape, torso)
	end
	hero.Name = "MaskedHero"
	hero.Parent = folder
	return hero, humanoid, root
end

local function loadTrack(
	humanoid: Humanoid,
	id: string,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, t = pcall(function()
		return (animator :: Animator):LoadAnimation(a)
	end)
	if not ok then
		return nil
	end
	t.Priority = priority
	t.Looped = looped
	return t
end

type Animal = {
	model: Model,
	home: Vector3,
	z0: number,
	phase: number,
	speed: number,
	flee: boolean,
	mark: BillboardGui?,
}

local playing = false

function IntroCutscene.play()
	if playing then
		return
	end
	playing = true
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local folder = Instance.new("Folder")
	folder.Name = "SAFD_Intro"
	folder.Parent = Workspace
	local cam = Workspace.CurrentCamera

	-- screen: fade, subtitles, title, skip
	local gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_Intro"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Parent = player:WaitForChild("PlayerGui")
	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.ZIndex = 20
	fade.Parent = gui
	local subtitle = label(gui, {
		Position = UDim2.fromScale(0.5, 0.84),
		Size = UDim2.fromScale(0.7, 0.06),
		Text = "",
		ZIndex = 5,
	})
	local title = label(gui, {
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.8, 0.16),
		Text = "SAVE THE ANIMALS!",
		TextColor3 = Color3.fromRGB(255, 210, 60),
		Visible = false,
		ZIndex = 6,
	})
	local titleGrad = Instance.new("UIGradient")
	titleGrad.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 120, 40))
	titleGrad.Rotation = 90
	titleGrad.Parent = title
	local tag = label(gui, {
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.6, 0.06),
		Text = "Rescue them before the disaster catches you!",
		Visible = false,
		ZIndex = 6,
	})
	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -20, 1, -20)
	skip.Size = UDim2.fromOffset(130, 44)
	skip.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	skip.BackgroundTransparency = 0.25
	skip.Font = Enum.Font.FredokaOne
	skip.TextScaled = true
	skip.TextColor3 = Color3.new(1, 1, 1)
	skip.Text = "SKIP >"
	skip.ZIndex = 21
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.3, 0)
	sc.Parent = skip
	skip.Parent = gui
	local skipped = false
	skip.Activated:Connect(function()
		skipped = true
	end)
	local function say(text: string)
		subtitle.Text = text
		subtitle.TextTransparency = 1
		TweenService:Create(subtitle, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	end

	-- nothing else on screen while it plays (the HUD, windows, Roblox's own menus); all back afterwards
	local hiddenGuis: { ScreenGui } = {}
	local function hideGuis()
		for _, g in player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name ~= "SAFD_ChaseFx" then
				g.Enabled = false
				table.insert(hiddenGuis, g)
			end
		end
	end
	hideGuis()
	local guiWatch = player.PlayerGui.ChildAdded:Connect(function(g)
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name ~= "SAFD_ChaseFx" then
			g.Enabled = false
			table.insert(hiddenGuis, g)
		end
	end)
	local StarterGui = game:GetService("StarterGui")
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)

	-- freeze and hide yourself for the length of it
	local hidden = {}
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				hidden[d] = d.LocalTransparencyModifier
				d.LocalTransparencyModifier = 1
			end
		end
	end
	Movement.locked = true
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	ChaseFx.letterbox(true)
	cam.CameraType = Enum.CameraType.Scriptable

	-- the animals
	local animals: { Animal } = {}
	local cast = { "Chicken", "Chicken", "Cow", "Bunny", "Horse", "Goat", "Corgi", "Chicken" }
	for i, id in cast do
		local ok, model = pcall(AnimalFactory.create, id, Config.animalHeight(id), Config.animalHeight(id) * 2.2)
		if ok and model then
			local home = Vector3.new(X0 + rng:NextNumber(-34, 34), GROUND, -655 - rng:NextNumber(-25, 30))
			model:PivotTo(CFrame.new(home) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			model.Parent = folder
			AnimalVisuals.play(model, if i % 2 == 0 then "Walk" else "Idle")
			table.insert(animals, {
				model = model,
				home = home,
				z0 = home.Z,
				phase = rng:NextNumber(0, math.pi * 2),
				speed = rng:NextNumber(22, 28),
				flee = false,
				mark = nil,
			})
		end
	end
	-- the one frozen with fear, right on the hero's path
	local frozen: Model? = nil
	do
		local ok, model = pcall(AnimalFactory.create, "Chicken", Config.animalHeight("Chicken"), 10)
		if ok and model then
			model:PivotTo(CFrame.new(X0, GROUND, -790) * CFrame.Angles(0, math.pi, 0))
			model.Parent = folder
			AnimalVisuals.play(model, "Idle")
			frozen = model
		end
	end

	-- the lava wall (under the ground until it erupts)
	local lava = Instance.new("Model")
	lava.Name = "LavaWall"
	local core = part(lava, {
		Name = "Core",
		Size = Vector3.new(260, 80, 14),
		Color = Color3.fromRGB(255, 90, 20),
		Material = Enum.Material.CrackedLava,
	})
	local glow = part(lava, {
		Name = "Glow",
		Size = Vector3.new(262, 82, 2),
		Color = Color3.fromRGB(255, 150, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	})
	for _ = 1, 26 do
		local s = rng:NextNumber(8, 18)
		part(lava, {
			Name = "Chunk",
			Size = Vector3.new(s, s * 0.8, s),
			Color = Color3.fromRGB(60, 25, 20),
			Material = Enum.Material.Basalt,
		}).CFrame = CFrame.new(
			rng:NextNumber(-120, 120),
			rng:NextNumber(-35, 40),
			-8
		) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
	end
	lava.PrimaryPart = core
	core.CFrame = CFrame.new()
	glow.CFrame = CFrame.new(0, 0, -8)
	emitter(glow, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 60, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 2) }),
		Lifetime = NumberRange.new(0.8, 1.5),
		Speed = NumberRange.new(8, 20),
		EmissionDirection = Enum.NormalId.Front,
		LightEmission = 0.9,
		Rate = 60,
		Shape = Enum.ParticleEmitterShape.Box,
	})
	lava.Parent = folder
	local function lavaAt(z: number, rise: number)
		lava:PivotTo(CFrame.new(X0, GROUND + 40 - 100 * (1 - rise), z) * CFrame.Angles(0, math.pi, 0))
	end
	lavaAt(LAVA_Z, 0)

	-- the hero
	local hero, heroHum, heroRoot = makeHero(folder)
	local run, slide, dj, fall
	if heroHum then
		run = loadTrack(heroHum, Config.RunAnimation, Enum.AnimationPriority.Movement, true)
		slide = loadTrack(heroHum, Config.SlideAnimation, Enum.AnimationPriority.Action2, true)
		dj = loadTrack(heroHum, Config.DoubleJumpAnimation, Enum.AnimationPriority.Action2, false)
		fall = loadTrack(heroHum, Config.FallAnimation, Enum.AnimationPriority.Action, true)
	end
	if heroRoot then
		heroRoot.CFrame = CFrame.new(X0, 200, HERO_LAND_Z)
	end

	-- the hazards the hero dodges
	local ball = part(folder, {
		Name = "LavaBall",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		Color = Color3.fromRGB(255, 110, 30),
		Material = Enum.Material.CrackedLava,
		Transparency = 1,
	})
	emitter(ball, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 60, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(1, 4),
		LightEmission = 1,
		Rate = 80,
	}).Enabled =
		false
	local boulder = part(folder, {
		Name = "Boulder",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6, 6, 6),
		Color = Color3.fromRGB(90, 80, 75),
		Material = Enum.Material.Slate,
		Transparency = 1,
	})

	-- the timeline
	local heroZ = function(t: number): number
		if t < 7.8 then
			return HERO_LAND_Z
		end
		-- slow motion at the very end
		local fast = math.min(t, 12.6) - 7.8
		local slow = math.max(0, t - 12.6) * 0.35
		return HERO_LAND_Z - HERO_SPEED * (fast + slow)
	end
	local events: { [string]: boolean } = {}
	local function once(name: string): boolean
		if events[name] then
			return false
		end
		events[name] = true
		return true
	end
	local nextRain = 8
	local t0 = os.clock()
	local lastT = 0
	local heroY = 200
	local carried = false

	local connection
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		if connection then
			connection:Disconnect()
		end
		Sfx.stopChase()
		fade.BackgroundTransparency = 1
		TweenService:Create(fade, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
		task.wait(0.4)
		folder:Destroy()
		for d, v in hidden do
			if d.Parent then
				d.LocalTransparencyModifier = v
			end
		end
		ChaseFx.releaseCamera()
		ChaseFx.letterbox(false)
		Movement.locked = false
		guiWatch:Disconnect()
		for _, g in hiddenGuis do
			if g.Parent then
				g.Enabled = true
			end
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
		title.Visible = false
		tag.Visible = false
		subtitle.Text = ""
		skip.Visible = false
		TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.delay(0.7, function()
			gui:Destroy()
		end)
		playing = false
	end

	TweenService:Create(fade, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	say("Far away, the animals lived happily in the meadows...")

	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local dt = math.clamp(t - lastT, 0, 0.1)
		lastT = t
		if skipped or t >= END_T then
			task.spawn(finish)
			return
		end

		-- 1. peace / 2. eruption / 3. panic: the animals
		for i, a in animals do
			local cf = a.model:GetPivot()
			if t < 5.2 then
				-- wander: slow little loops around home, some just pecking
				local w = t * 0.45 + a.phase
				local r = if i % 2 == 0 then 4 else 1.2
				local p = a.home + Vector3.new(math.cos(w) * r, 0, math.sin(w) * r)
				local ahead = a.home + Vector3.new(math.cos(w + 0.2) * r, 0, math.sin(w + 0.2) * r)
				a.model:PivotTo(CFrame.lookAt(p, ahead))
			else
				if not a.flee then
					a.flee = true
					AnimalVisuals.play(a.model, "Walk")
					local bb = Instance.new("BillboardGui")
					bb.Size = UDim2.fromOffset(60, 60)
					bb.StudsOffsetWorldSpace = Vector3.new(0, (a.model:GetAttribute("Height") or 4) + 2, 0)
					bb.AlwaysOnTop = true
					local l = label(bb, {
						Size = UDim2.fromScale(1, 1),
						Position = UDim2.fromScale(0.5, 0.5),
						Text = "!",
						TextColor3 = Color3.fromRGB(255, 60, 40),
					})
					local _ = l
					bb.Parent = a.model.PrimaryPart or a.model:FindFirstChildWhichIsA("BasePart")
					a.mark = bb
					ChaseFx.play("Pop", 0.5, 1.3 + i * 0.05)
				end
				local p = cf.Position + Vector3.new(0, 0, -a.speed * dt)
				a.model:PivotTo(CFrame.lookAt(p, p + Vector3.new(0, 0, -1)))
			end
		end
		if frozen and not carried and t > 5.2 and once("frozenMark") then
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(60, 60)
			bb.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
			bb.AlwaysOnTop = true
			label(bb, {
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				Text = "!!",
				TextColor3 = Color3.fromRGB(255, 60, 40),
			})
			bb.Parent = frozen.PrimaryPart or frozen:FindFirstChildWhichIsA("BasePart")
		end

		-- the lava: erupts at 3.6, rolls forward from 5.2
		if t >= 3.6 then
			if once("erupt") then
				say("...until one day, disaster struck!")
				ChaseFx.play("Rumble", 1.2, 0.7)
				ChaseFx.play("Roar", 1.3, 0.4)
				Sfx.startChase()
			end
			local rise = smooth((t - 3.6) / 1.4)
			local z = LAVA_Z - math.max(0, t - 5.2) * 19
			lavaAt(z, rise)
			if t < 5.2 and rng:NextNumber() < 0.3 then
				burst(
					folder,
					Vector3.new(X0 + rng:NextNumber(-100, 100), GROUND + 2, LAVA_Z - 10),
					Color3.fromRGB(255, 120, 40),
					8,
					FIRE
				)
			end
			if t > 4.3 and once("eruptBoom") then
				ChaseFx.play("Impact", 1.2, 0.6)
			end
		end

		-- 4. the hero
		if heroRoot then
			local z = heroZ(t)
			if t >= 7.0 and t < 7.6 then
				if once("drop") then
					say("But one masked hero wasn't scared...")
					if fall then
						fall:Play(0.1)
					end
					ChaseFx.play("Whoosh", 1.2, 0.7)
				end
				heroY = GROUND + 3 + 60 * (1 - smooth((t - 7.0) / 0.6)) ^ 2
			elseif t >= 7.6 then
				if once("land") then
					if fall then
						fall:Stop(0.1)
					end
					burst(folder, Vector3.new(X0, GROUND + 1, z), Color3.fromRGB(230, 220, 200), 30)
					ChaseFx.play("Thud", 1.3, 0.8)
					ChaseFx.play("Impact", 0.8, 1)
				end
				heroY = GROUND + 3
			end
			if t >= 7.8 and once("go") then
				if run then
					run:Play(0.15)
					run:AdjustSpeed(1.4)
				end
				ChaseFx.play("Boost", 1, 0.9)
			end
			-- slide under the lava ball (8.6 - 9.5)
			if t >= 8.6 and once("slide") then
				if slide then
					slide:Play(0.1)
				end
				ChaseFx.play("Whoosh", 1, 1.1)
			end
			if t >= 9.5 and once("slideEnd") and slide then
				slide:Stop(0.2)
			end
			if t >= 8.4 and t < 9.6 then
				ball.Transparency = 0
				ball:FindFirstChildOfClass("ParticleEmitter").Enabled = true
				local k = (t - 8.4) / 1.2
				ball.Position = Vector3.new(X0 + 45 - 90 * k, GROUND + 5.2, heroZ(9.0))
			elseif t >= 9.6 and once("ballGone") then
				burst(folder, ball.Position, Color3.fromRGB(255, 120, 40), 25, FIRE)
				ball.Transparency = 1
				ball:FindFirstChildOfClass("ParticleEmitter").Enabled = false
			end
			-- double jump the boulder (10.0 - 10.9)
			if t >= 9.4 and t < 11.2 then
				boulder.Transparency = 0
				local meetZ = heroZ(10.45)
				local bz = meetZ + (10.45 - t) * -30 -- rolling towards the hero (towards +Z)
				boulder.CFrame = CFrame.new(X0, GROUND + 3, bz) * CFrame.Angles(t * 8, 0, 0)
			elseif t >= 11.2 then
				boulder.Transparency = 1
			end
			if t >= 10.0 and once("dj") then
				if dj then
					dj:Play(0.05)
				end
				ChaseFx.play("Whoosh", 1, 0.9)
				ChaseFx.play("Good", 0.6, 1.3)
			end
			if t >= 10.0 and t < 10.9 then
				heroY = GROUND + 3 + math.sin(math.pi * (t - 10.0) / 0.9) * 10
			end
			-- scoop up the frozen chicken (11.3)
			if frozen and not carried and z <= -788 then
				carried = true
				ChaseFx.play("Pop", 1, 1.2)
				ChaseFx.play("Good", 1, 1)
				burst(
					folder,
					frozen:GetPivot().Position + Vector3.new(0, 2, 0),
					Color3.fromRGB(255, 240, 120),
					30,
					SPARK
				)
				AnimalVisuals.play(frozen, "Idle")
			end
			if t >= 7.0 then
				heroRoot.CFrame = CFrame.lookAt(Vector3.new(X0, heroY, z), Vector3.new(X0, heroY, z - 1))
			end
			if frozen and carried then
				local head = hero and hero:FindFirstChild("Head") :: BasePart?
				local top = if head
					then head.Position + Vector3.new(0, head.Size.Y / 2 + 0.1, 0)
					else heroRoot.Position + Vector3.new(0, 3, 0)
				frozen:PivotTo(CFrame.lookAt(top, top + Vector3.new(0, 0, -1)))
			end
			-- lava rains down around the hero
			if t >= nextRain and t < 12.4 then
				nextRain = t + rng:NextNumber(0.25, 0.5)
				local p = Vector3.new(X0 + rng:NextNumber(-30, 30), GROUND + 1, z - rng:NextNumber(5, 40))
				burst(folder, p, Color3.fromRGB(255, 110, 30), 14, FIRE)
				burst(folder, p, Color3.fromRGB(70, 60, 55), 10)
				if rng:NextNumber() < 0.5 then
					ChaseFx.play("Impact", 0.5, rng:NextNumber(0.8, 1.2))
				end
			end
		end

		-- 5. title
		if t >= 12.9 and once("title") then
			subtitle.Text = ""
			title.Visible = true
			local ts = Instance.new("UIScale")
			ts.Scale = 3
			ts.Parent = title
			TweenService:Create(ts, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
			ChaseFx.play("Impact", 1.2, 0.7)
			ChaseFx.play("Confetti", 1, 1)
			ChaseFx.kick(12)
		end
		if t >= 13.5 and once("tag") then
			tag.Visible = true
			tag.TextTransparency = 1
			TweenService:Create(tag, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
		end

		-- the camera
		local shake = if t >= 3.6 and t < 7.2 then 0.5 * (1 - smooth((t - 3.6) / 3.6)) + 0.08 else 0.04
		local jitter = CFrame.new(rng:NextNumber(-1, 1) * shake, rng:NextNumber(-1, 1) * shake, 0)
		local camCF
		if t < 3.6 then
			local k = smooth(t / 3.6)
			local a = CFrame.lookAt(Vector3.new(X0 - 70, 42, -775), Vector3.new(X0, 4, -655))
			local b = CFrame.lookAt(Vector3.new(X0 - 28, 14, -712), Vector3.new(X0, 4, -650))
			camCF = a:Lerp(b, k)
		elseif t < 5.4 then
			-- look up at the eruption
			local from = CFrame.lookAt(Vector3.new(X0 - 28, 14, -712), Vector3.new(X0, 4, -650))
			local to = CFrame.lookAt(Vector3.new(X0 + 10, 6, -705), Vector3.new(X0, 34, LAVA_Z))
			camCF = from:Lerp(to, smooth((t - 3.6) / 0.6))
		elseif t < 7.0 then
			-- in front of the stampede, backing away as it comes at us
			local lead = -660 - (t - 5.2) * 24
			camCF = CFrame.lookAt(Vector3.new(X0 + 6, 4.5, lead - 22), Vector3.new(X0, 5, lead + 10))
		elseif t < 12.6 then
			-- tracking the hero from the side
			local z = heroZ(t)
			local y = if heroRoot then heroRoot.Position.Y else GROUND + 3
			local from = Vector3.new(X0 + 20, GROUND + 6 + (y - GROUND - 3) * 0.4, z - 6)
			camCF = CFrame.lookAt(from, Vector3.new(X0, y, z - 4))
			if t < 7.6 then
				-- (the drop: look up at it coming down)
				camCF =
					CFrame.lookAt(Vector3.new(X0 + 18, GROUND + 4, HERO_LAND_Z - 14), Vector3.new(X0, y, HERO_LAND_Z))
			end
		else
			-- low, ahead of the hero, slow motion
			local zc = heroZ(12.6) - 26
			camCF = CFrame.lookAt(Vector3.new(X0 - 4, GROUND + 2, zc), Vector3.new(X0, GROUND + 5, heroZ(t) + 6))
		end
		cam.CFrame = camCF * jitter
	end)
end

function IntroCutscene.init()
	local function check()
		if player:GetAttribute("PlayIntro") == true then
			task.spawn(function()
				-- (wait for the world around Grassy Meadows to be there)
				pcall(function()
					player:RequestStreamAroundAsync(Vector3.new(X0, GROUND, -700), 4)
				end)
				task.wait(0.5)
				IntroCutscene.play()
			end)
		end
	end
	player:GetAttributeChangedSignal("PlayIntro"):Connect(check)
	check()
end

return IntroCutscene
