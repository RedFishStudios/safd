-- The opening cutscene, on your first visit (Server/Main sets PlayIntro; /intro in the admin panel replays it):
--   1. peace: the camera drifts over Grassy Meadows, chickens peck and wander, a cow grazes, a bunny hops ...
--   2. disaster: the ground rumbles, a wall of lava erupts at the far end of the meadow with a roar
--   3. fear: quick close-ups of the animals, trembling, a drop of sweat running down the side of the head, "!",
--      scared high calls (cluck! moo!)
--   4. stampede: they flee towards the camera, calling out, the lava rolling after them
--   5. the hero: a masked hero (you, with a mask and a cape) drops in from the sky and sprints through the chaos:
--      slides under a lava ball, double jumps a rolling boulder, dodges a lava geyser, hurdles a falling tree, leaps a
--      lava crack, and scoops up three stranded animals on the way (stacked on the head, like in the game)
--   6. title: slow motion, the hero runs at the camera, "SAVE THE ANIMALS!"
-- Everything is local (only you see it) and cleaned up afterwards; Skip ends it at any time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalFactory = require(Shared.AnimalFactory)
local Config = require(Shared.Config)
local MapStyle = require(Shared.MapStyle)

local AnimalSounds = require(script.Parent.AnimalSounds)
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
-- the timeline (seconds)
local T_ERUPT = 3.6
local T_FEAR = 5.4 -- three close-ups, FEAR_SHOT each
local FEAR_SHOT = 0.75
local T_FLEE = T_FEAR + FEAR_SHOT * 3
local T_DROP = T_FLEE + 1.4
local T_RUN = T_DROP + 0.8
local T_SLOW = T_RUN + 7.2
local END_T = T_SLOW + 3.4
local HERO_START_Z = -640
local HERO_SPEED = 32

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
	MapStyle.apply(p)
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

-- "!" (or "!!") over an animal
local function exclaim(model: Model, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Exclaim"
	bb.Size = UDim2.fromOffset(60, 60)
	bb.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 4) + 1.5, 0)
	bb.AlwaysOnTop = true
	label(bb, {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Text = text,
		TextColor3 = Color3.fromRGB(255, 60, 40),
	})
	bb.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local sc = Instance.new("UIScale")
	sc.Scale = 0.2
	sc.Parent = bb:FindFirstChildOfClass("TextLabel")
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- a drop of sweat running down the side of an animal's head
local function sweat(model: Model)
	local h = model:GetAttribute("Height") or 4
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Sweat"
	bb.Size = UDim2.fromOffset(34, 44)
	bb.AlwaysOnTop = true
	local start = Vector3.new(h * 0.32, h * 0.95, 0)
	bb.StudsOffsetWorldSpace = start
	local drop = Instance.new("Frame")
	drop.AnchorPoint = Vector2.new(0.5, 0.5)
	drop.Position = UDim2.fromScale(0.5, 0.5)
	drop.Size = UDim2.fromScale(0.55, 0.75)
	drop.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	drop.Rotation = 20
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = drop
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.fromRGB(30, 80, 150)
	st.Parent = drop
	local shine = Instance.new("Frame")
	shine.Position = UDim2.fromScale(0.25, 0.2)
	shine.Size = UDim2.fromScale(0.25, 0.3)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BorderSizePixel = 0
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.5, 0)
	c2.Parent = shine
	shine.Parent = drop
	drop.Parent = bb
	bb.Parent = root
	TweenService:Create(bb, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		StudsOffsetWorldSpace = start - Vector3.new(0, h * 0.35, 0),
	}):Play()
	task.delay(0.9, function()
		bb:Destroy()
	end)
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
		local mask = part(hero, {
			Name = "HeroMask",
			Size = Vector3.new(head.Size.X * 0.62, head.Size.Y * 0.32, head.Size.Z * 1.08),
			Color = Color3.fromRGB(20, 20, 28),
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
		local tail = part(hero, {
			Name = "HeroMaskTail",
			Size = Vector3.new(0.25, 0.18, 1.6),
			Color = Color3.fromRGB(200, 30, 40),
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

local function animal(folder: Instance, id: string, at: Vector3, yaw: number): Model?
	local ok, model = pcall(AnimalFactory.create, id, Config.animalHeight(id), Config.animalHeight(id) * 2.2)
	if not ok or not model then
		return nil
	end
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, yaw, 0))
	model.Parent = folder
	return model
end

type Herd = { model: Model, id: string, home: Vector3, phase: number, speed: number, fled: boolean }
type Stranded = { model: Model, id: string, z: number, taken: boolean, called: boolean }

local playing = false

function IntroCutscene.play()
	if playing then
		return
	end
	playing = true
	-- (a living, fully built character: the hero is a copy of it. Right after joining the server is still dressing
	-- your avatar and swaps the character for a new one, so keep looking at the current one until it's complete.)
	local character: Model? = nil
	local humanoid: Humanoid? = nil
	local waitStart = os.clock()
	while os.clock() - waitStart < 12 do
		local c = player.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if
			c
			and h
			and h.Health > 0
			and c:FindFirstChild("HumanoidRootPart")
			and c:FindFirstChild("Head")
			and (c:FindFirstChild("Torso") or c:FindFirstChild("UpperTorso"))
			and #c:GetChildren() >= 10
		then
			character, humanoid = c, h
			break
		end
		task.wait(0.2)
	end
	task.wait(0.3)
	character = player.Character
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
	local restoreUi = ChaseFx.hideUi({ "SAFD_Intro" })

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

	-- the herd
	local herd: { Herd } = {}
	local cast = { "Chicken", "Cow", "Bunny", "Horse", "Goat", "Chicken", "Corgi", "Chicken", "Bunny" }
	for i, id in cast do
		local home = Vector3.new(X0 + rng:NextNumber(-34, 34), GROUND, -660 - rng:NextNumber(-25, 30))
		-- (the close-up stars stand nearer the camera, apart from each other)
		if i == 1 then
			home = Vector3.new(X0 - 14, GROUND, -680)
		elseif i == 2 then
			home = Vector3.new(X0 + 12, GROUND, -672)
		elseif i == 3 then
			home = Vector3.new(X0 - 2, GROUND, -690)
		end
		local model = animal(folder, id, home, rng:NextNumber(0, math.pi * 2))
		if model then
			AnimalVisuals.play(model, if i % 2 == 0 then "Walk" else "Idle")
			table.insert(herd, {
				model = model,
				id = id,
				home = home,
				phase = rng:NextNumber(0, math.pi * 2),
				speed = rng:NextNumber(22, 28),
				fled = false,
			})
		end
	end
	-- the stranded ones, frozen with fear right on the hero's path
	local heroZ: (number) -> number
	local stranded: { Stranded } = {}
	for _, s in { { "Chicken", T_RUN + 1.6 }, { "Bunny", T_RUN + 4.2 }, { "Corgi", T_RUN + 6.2 } } do
		local z = HERO_START_Z - HERO_SPEED * (s[2] - T_RUN)
		local model = animal(folder, s[1], Vector3.new(X0, GROUND, z), math.pi)
		if model then
			AnimalVisuals.play(model, "Idle")
			table.insert(stranded, { model = model, id = s[1], z = z, taken = false, called = false })
		end
	end

	-- the lava wall (under the ground until it erupts)
	local lava = Instance.new("Model")
	lava.Name = "LavaWall"
	local core = part(lava, {
		Name = "Core",
		Size = Vector3.new(260, 80, 14),
		Color = Color3.fromRGB(255, 90, 20),
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
		heroRoot.CFrame = CFrame.new(X0, 200, HERO_START_Z)
	end

	-- the hazards the hero gets past
	local ball = part(folder, {
		Name = "LavaBall",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		Color = Color3.fromRGB(255, 110, 30),
		Material = Enum.Material.Neon,
		Transparency = 1,
	})
	local ballFire = emitter(ball, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 60, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(1, 4),
		LightEmission = 1,
		Rate = 80,
	})
	ballFire.Enabled = false
	local boulder = part(folder, {
		Name = "Boulder",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6, 6, 6),
		Color = Color3.fromRGB(90, 80, 75),
		Transparency = 1,
	})
	local geyser = part(folder, {
		Name = "Geyser",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 6, 6),
		Color = Color3.fromRGB(255, 120, 30),
		Material = Enum.Material.Neon,
		Transparency = 1,
	})
	local tree = Instance.new("Model")
	tree.Name = "FallingTree"
	local trunk = part(tree, { Name = "Trunk", Size = Vector3.new(2.4, 18, 2.4), Color = Color3.fromRGB(110, 70, 45) })
	local crown = part(tree, { Name = "Crown", Size = Vector3.new(8, 7, 8), Color = Color3.fromRGB(80, 170, 60) })
	trunk.CFrame = CFrame.new(0, 9, 0)
	crown.CFrame = CFrame.new(0, 19, 0)
	tree.PrimaryPart = trunk
	tree.WorldPivot = CFrame.new(0, 0, 0)
	tree.Parent = folder
	local crack = part(folder, {
		Name = "LavaCrack",
		Size = Vector3.new(140, 0.4, 0.1),
		Color = Color3.fromRGB(255, 120, 30),
		Material = Enum.Material.Neon,
		Transparency = 1,
	})

	-- the hero's line: running from T_RUN, slow motion from T_SLOW
	heroZ = function(t: number): number
		if t < T_RUN then
			return HERO_START_Z
		end
		local fast = math.min(t, T_SLOW) - T_RUN
		local slow = math.max(0, t - T_SLOW) * 0.35
		return HERO_START_Z - HERO_SPEED * (fast + slow)
	end
	-- event times, all on the run
	local E_SLIDE = T_RUN + 0.7 -- under a lava ball
	local E_DJ = T_RUN + 2.4 -- over the boulder
	local E_GEYSER = T_RUN + 3.0 -- a geyser in the path: sidestep
	local E_TREE = T_RUN + 3.7 -- a tree topples across the path: hurdle it
	local E_CRACK = T_RUN + 5.1 -- the ground splits: leap it
	local carriedList: { Model } = {}

	local events: { [string]: boolean } = {}
	local function once(name: string): boolean
		if events[name] then
			return false
		end
		events[name] = true
		return true
	end
	local nextRain = T_RUN + 0.3
	local nextPanic = T_FLEE
	local t0 = os.clock()
	local lastT = 0
	local heroY = 200

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
		restoreUi()
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

	local fearStars = { herd[1], herd[2], herd[3] }

	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local dt = math.clamp(t - lastT, 0, 0.1)
		lastT = t
		if skipped or t >= END_T then
			task.spawn(finish)
			return
		end

		-- the herd: grazing, then trembling, then the stampede
		for i, a in herd do
			if t < T_FEAR then
				local w = t * 0.45 + a.phase
				local r = if i % 2 == 0 then 4 else 1.2
				local p = a.home + Vector3.new(math.cos(w) * r, 0, math.sin(w) * r)
				local ahead = a.home + Vector3.new(math.cos(w + 0.2) * r, 0, math.sin(w + 0.2) * r)
				a.model:PivotTo(CFrame.lookAt(p, ahead))
			elseif t < T_FLEE then
				-- frozen in fear, facing the eruption, trembling
				local j = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 0.12
				a.model:PivotTo(CFrame.lookAt(a.home + j, a.home + Vector3.new(0, 0, 1)))
			else
				if not a.fled then
					a.fled = true
					AnimalVisuals.play(a.model, "Walk")
					exclaim(a.model, "!")
				end
				local cf = a.model:GetPivot()
				local p = cf.Position + Vector3.new(0, 0, -a.speed * dt)
				a.model:PivotTo(CFrame.lookAt(p, p + Vector3.new(0, 0, -1)))
			end
		end
		-- panicked calls all through the stampede
		if t >= nextPanic and t < T_SLOW and #herd > 0 then
			nextPanic = t + rng:NextNumber(0.35, 0.7)
			local a = herd[rng:NextInteger(1, #herd)]
			AnimalSounds.call(a.model, a.id, rng:NextNumber(1.25, 1.45), 1.6)
		end

		-- the stranded ones tremble and sweat, and call out as the hero comes
		for _, s in stranded do
			if not s.taken and t >= T_FEAR then
				local base = Vector3.new(X0, GROUND, s.z)
				local j = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 0.1
				s.model:PivotTo(CFrame.lookAt(base + j, base + j + Vector3.new(0, 0, 1)))
				if once("strandMark" .. s.z) then
					exclaim(s.model, "!!")
				end
				if t >= T_RUN and not s.called and heroZ(t) - s.z < 45 then
					s.called = true
					sweat(s.model)
					AnimalSounds.call(s.model, s.id, 1.4, 1.8)
				end
			end
		end

		-- 2. the eruption
		if t >= T_ERUPT then
			if once("erupt") then
				say("...until one day, disaster struck!")
				ChaseFx.play("Rumble", 1.2, 0.7)
				ChaseFx.play("Roar", 1.3, 0.4)
				Sfx.startChase()
			end
			local rise = smooth((t - T_ERUPT) / 1.4)
			local z = LAVA_Z - math.max(0, t - T_FLEE) * 19
			lavaAt(z, rise)
			if t < T_FEAR and rng:NextNumber() < 0.3 then
				burst(
					folder,
					Vector3.new(X0 + rng:NextNumber(-100, 100), GROUND + 2, LAVA_Z - 10),
					Color3.fromRGB(255, 120, 40),
					8,
					FIRE
				)
			end
			if t > T_ERUPT + 0.7 and once("eruptBoom") then
				ChaseFx.play("Impact", 1.2, 0.6)
			end
		end

		-- 3. fear close-ups: sweat, "!", a scared call, one animal after another
		if t >= T_FEAR and t < T_FLEE then
			local shot = math.floor((t - T_FEAR) / FEAR_SHOT) + 1
			local a = fearStars[shot]
			if a and once("fear" .. shot) then
				if shot == 1 then
					say("The animals were terrified!")
				end
				sweat(a.model)
				exclaim(a.model, "!")
				AnimalSounds.call(a.model, a.id, 1.45, 2)
				ChaseFx.play("Pop", 0.5, 1.6)
			end
		end
		if t >= T_FLEE and once("flee") then
			ChaseFx.play("Whoosh", 1, 0.8)
		end

		-- 5. the hero
		if heroRoot then
			local z = heroZ(t)
			local x = X0
			if t >= T_DROP and t < T_DROP + 0.6 then
				if once("drop") then
					say("But one masked hero wasn't scared...")
					if fall then
						fall:Play(0.1)
					end
					ChaseFx.play("Whoosh", 1.2, 0.7)
				end
				heroY = GROUND + 3 + 60 * (1 - smooth((t - T_DROP) / 0.6)) ^ 2
			elseif t >= T_DROP + 0.6 then
				if once("land") then
					if fall then
						fall:Stop(0.1)
					end
					burst(folder, Vector3.new(X0, GROUND + 1, z), Color3.fromRGB(230, 220, 200), 30)
					ChaseFx.play("Thud", 1.3, 0.8)
					ChaseFx.play("Impact", 0.8, 1)
					ChaseFx.kick(8)
				end
				heroY = GROUND + 3
			end
			if t >= T_RUN and once("go") then
				if run then
					run:Play(0.15)
					run:AdjustSpeed(1.4)
				end
				ChaseFx.play("Boost", 1, 0.9)
			end
			-- a) slide under the lava ball
			if t >= E_SLIDE - 0.2 and once("slide") then
				if slide then
					slide:Play(0.1)
				end
				ChaseFx.play("Whoosh", 1, 1.1)
			end
			if t >= E_SLIDE + 0.7 and once("slideEnd") and slide then
				slide:Stop(0.2)
			end
			if t >= E_SLIDE - 0.4 and t < E_SLIDE + 0.8 then
				ball.Transparency = 0
				ballFire.Enabled = true
				local k = (t - (E_SLIDE - 0.4)) / 1.2
				ball.Position = Vector3.new(X0 + 45 - 90 * k, GROUND + 5.2, heroZ(E_SLIDE + 0.2))
			elseif t >= E_SLIDE + 0.8 and once("ballGone") then
				burst(folder, ball.Position, Color3.fromRGB(255, 120, 40), 25, FIRE)
				ball.Transparency = 1
				ballFire.Enabled = false
			end
			-- b) double jump the rolling boulder
			if t >= E_DJ - 1 and t < E_DJ + 1 then
				boulder.Transparency = 0
				local meetZ = heroZ(E_DJ + 0.45)
				local bz = meetZ + (E_DJ + 0.45 - t) * -30
				boulder.CFrame = CFrame.new(X0, GROUND + 3, bz) * CFrame.Angles(t * 8, 0, 0)
			elseif t >= E_DJ + 1 then
				boulder.Transparency = 1
			end
			if t >= E_DJ and once("dj") then
				if dj then
					dj:Play(0.05)
				end
				ChaseFx.play("Whoosh", 1, 0.9)
				ChaseFx.play("Good", 0.6, 1.3)
			end
			if t >= E_DJ and t < E_DJ + 0.9 then
				heroY = GROUND + 3 + math.sin(math.pi * (t - E_DJ) / 0.9) * 10
			end
			-- c) the geyser: it bursts up right ahead, the hero swerves round it
			local gz = heroZ(E_GEYSER + 0.4)
			if t >= E_GEYSER and t < E_GEYSER + 1.4 then
				if once("geyser") then
					ChaseFx.play("Impact", 1, 0.8)
					burst(folder, Vector3.new(X0, GROUND + 1, gz), Color3.fromRGB(255, 120, 30), 30, FIRE)
				end
				local k = math.clamp((t - E_GEYSER) / 0.25, 0, 1)
				local h = 26 * k * (1 - math.max(0, t - E_GEYSER - 1) / 0.4)
				geyser.Transparency = 0.1
				geyser.Size = Vector3.new(math.max(0.1, h), 6, 6)
				geyser.CFrame = CFrame.new(X0, GROUND + h / 2, gz) * CFrame.Angles(0, 0, math.pi / 2)
			elseif t >= E_GEYSER + 1.4 then
				geyser.Transparency = 1
			end
			if t >= E_GEYSER - 0.1 and t < E_GEYSER + 0.9 then
				x = X0 + math.sin(math.pi * (t - (E_GEYSER - 0.1)) / 1.0) * 9
			end
			-- d) the tree: it topples across the path, the hero hurdles the trunk
			local tz = heroZ(E_TREE + 0.5)
			if t >= E_TREE - 0.6 then
				local k = smooth((t - (E_TREE - 0.6)) / 0.7)
				tree:PivotTo(CFrame.new(X0 - 22, GROUND, tz) * CFrame.Angles(0, 0, -math.pi / 2 * k))
				if k >= 1 and once("treeDown") then
					ChaseFx.play("Thud", 1.2, 0.7)
					burst(folder, Vector3.new(X0, GROUND + 1, tz), Color3.fromRGB(200, 190, 170), 20)
				end
			else
				tree:PivotTo(CFrame.new(X0 - 22, GROUND, tz))
			end
			if t >= E_TREE + 0.25 and t < E_TREE + 0.8 then
				if once("hurdle") then
					ChaseFx.play("Whoosh", 0.8, 1.2)
				end
				heroY = GROUND + 3 + math.sin(math.pi * (t - (E_TREE + 0.25)) / 0.55) * 5
			end
			-- e) the crack: the ground splits open in front, the hero leaps it
			local cz = heroZ(E_CRACK + 0.45)
			if t >= E_CRACK - 0.5 then
				if once("crack") then
					ChaseFx.play("Rumble", 1, 1.3)
					ChaseFx.play("Impact", 1, 0.5)
				end
				local k = smooth((t - (E_CRACK - 0.5)) / 0.4)
				crack.Transparency = 0
				crack.Size = Vector3.new(140, 0.4, 0.1 + 7 * k)
				crack.CFrame = CFrame.new(X0, GROUND + 0.25, cz)
				if rng:NextNumber() < 0.4 then
					burst(
						folder,
						Vector3.new(X0 + rng:NextNumber(-40, 40), GROUND + 1, cz),
						Color3.fromRGB(255, 120, 30),
						6,
						FIRE
					)
				end
			end
			if t >= E_CRACK and once("leap") then
				if dj then
					dj:Play(0.05)
				end
				ChaseFx.play("Boost", 1, 1.1)
				ChaseFx.kick(10)
			end
			if t >= E_CRACK and t < E_CRACK + 0.9 then
				heroY = GROUND + 3 + math.sin(math.pi * (t - E_CRACK) / 0.9) * 11
			end
			-- scoop up the stranded animals as the hero reaches them
			for _, s in stranded do
				if not s.taken and z <= s.z + 1 then
					s.taken = true
					local ex = s.model:FindFirstChild("Exclaim", true)
					if ex then
						ex:Destroy()
					end
					table.insert(carriedList, s.model)
					AnimalVisuals.play(s.model, "Idle")
					ChaseFx.play("Pop", 1, 1.1 + #carriedList * 0.1)
					ChaseFx.play("Good", 1, 0.95 + #carriedList * 0.08)
					ChaseFx.kick(6)
					burst(
						folder,
						s.model:GetPivot().Position + Vector3.new(0, 2, 0),
						Color3.fromRGB(255, 240, 120),
						30,
						SPARK
					)
					if #carriedList == 1 then
						say("He saved them, one by one!")
					end
				end
			end
			if t >= T_DROP then
				heroRoot.CFrame = CFrame.lookAt(Vector3.new(x, heroY, z), Vector3.new(x, heroY, z - 1))
			end
			-- the carried animals ride stacked on the hero's head
			local head = hero and hero:FindFirstChild("Head") :: BasePart?
			local top = if head
				then head.Position + Vector3.new(0, head.Size.Y / 2 + 0.1, 0)
				else heroRoot.Position + Vector3.new(0, 3, 0)
			for _, m in carriedList do
				m:PivotTo(CFrame.lookAt(top, top + Vector3.new(0, 0, -1)))
				top += Vector3.new(0, (m:GetAttribute("Height") or 3) * 0.9, 0)
			end
			-- lava rains down around the hero
			if t >= nextRain and t < T_SLOW then
				nextRain = t + rng:NextNumber(0.25, 0.5)
				local p = Vector3.new(X0 + rng:NextNumber(-30, 30), GROUND + 1, z - rng:NextNumber(10, 40))
				burst(folder, p, Color3.fromRGB(255, 110, 30), 14, FIRE)
				burst(folder, p, Color3.fromRGB(70, 60, 55), 10)
				if rng:NextNumber() < 0.5 then
					ChaseFx.play("Impact", 0.5, rng:NextNumber(0.8, 1.2))
				end
			end
		end

		-- 6. title
		if t >= T_SLOW + 0.3 and once("title") then
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
		if t >= T_SLOW + 0.9 and once("tag") then
			tag.Visible = true
			tag.TextTransparency = 1
			TweenService:Create(tag, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
		end

		-- the camera
		local shake = if t >= T_ERUPT and t < T_FEAR then 0.45 else 0.05
		local jitter = CFrame.new(rng:NextNumber(-1, 1) * shake, rng:NextNumber(-1, 1) * shake, 0)
		local camCF
		if t < T_ERUPT then
			local k = smooth(t / T_ERUPT)
			local a = CFrame.lookAt(Vector3.new(X0 - 70, 42, -775), Vector3.new(X0, 4, -660))
			local b = CFrame.lookAt(Vector3.new(X0 - 28, 14, -715), Vector3.new(X0, 4, -660))
			camCF = a:Lerp(b, k)
		elseif t < T_FEAR then
			-- look up at the eruption
			local from = CFrame.lookAt(Vector3.new(X0 - 28, 14, -715), Vector3.new(X0, 4, -660))
			local to = CFrame.lookAt(Vector3.new(X0 + 10, 6, -705), Vector3.new(X0, 34, LAVA_Z))
			camCF = from:Lerp(to, smooth((t - T_ERUPT) / 0.6))
		elseif t < T_FLEE then
			-- close-ups, face on, slowly pushing in
			local shot = math.clamp(math.floor((t - T_FEAR) / FEAR_SHOT) + 1, 1, 3)
			local a = fearStars[shot]
			if a then
				local h = a.model:GetAttribute("Height") or 4
				local p = a.home
				local k = ((t - T_FEAR) % FEAR_SHOT) / FEAR_SHOT
				local dist = h * (2.4 - 0.5 * k)
				local eye = p + Vector3.new(h * 0.6, h * 0.85, dist)
				camCF = CFrame.lookAt(eye, p + Vector3.new(0, h * 0.75, 0))
			else
				camCF = cam.CFrame
			end
		elseif t < T_DROP then
			-- in front of the stampede, backing away as it comes
			local lead = -670 - (t - T_FLEE) * 24
			camCF = CFrame.lookAt(Vector3.new(X0 + 6, 4.5, lead - 22), Vector3.new(X0, 5, lead + 10))
		elseif t < T_SLOW then
			local z = heroZ(t)
			local y = if heroRoot then heroRoot.Position.Y else GROUND + 3
			if t < T_DROP + 0.6 then
				camCF =
					CFrame.lookAt(Vector3.new(X0 + 18, GROUND + 4, HERO_START_Z - 14), Vector3.new(X0, y, HERO_START_Z))
			else
				-- tracking from the side, swinging round now and then for the big moments
				local side = if t >= E_TREE - 0.4 and t < E_TREE + 1 then -1 else 1
				local from = Vector3.new(X0 + 20 * side, GROUND + 6 + (y - GROUND - 3) * 0.4, z - 6)
				camCF = CFrame.lookAt(from, Vector3.new(X0, y, z - 4))
			end
		else
			-- low, ahead of the hero, slow motion
			local zc = heroZ(T_SLOW) - 26
			camCF = CFrame.lookAt(Vector3.new(X0 - 4, GROUND + 2, zc), Vector3.new(X0, GROUND + 6, heroZ(t) + 6))
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
