-- The opening cutscene, on your first visit (Server/Main sets PlayIntro; /intro in the admin panel replays it):
--   1. peace: the camera drifts over Grassy Meadows, where eggs from every biome lie in the grass, wobbling now and then
--   2. disaster: the ground rumbles, a wall of lava erupts at the far end of the meadow with a roar
--   3. fear: every egg breaks into a huge cartoon sweat drop (on its upper side, dripping and bouncing), trembles and
--      hops in panic; quick close-ups of three of them, "!!", little panicked squeaks
--   4. panic: a wide shot of all the eggs hopping in place as the lava rolls towards them
--   5. the hero: a masked hero (you, with a mask and a cape) drops in from the sky and sprints through the chaos,
--      weaving from egg to egg: every egg pops up onto the head stack (like in the game) until all 8 are saved, while
--      sliding under a lava ball, double jumping a rolling boulder, swerving round a lava geyser, hurdling a falling
--      tree and leaping a lava crack. A counter on screen counts them: "EGGS SAVED 8/8"
--   6. title: slow motion, the hero runs at the camera with the tall egg stack, "SAVE EGGS FROM DISASTERS!"
-- Everything is local (only you see it) and cleaned up afterwards; Skip ends it at any time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local EggFactory = require(Shared.EggFactory)
local MapStyle = require(Shared.MapStyle)
local Net = require(Shared.Net)

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
local T_SWEAT = T_ERUPT + 0.9 -- the sweat breaks out
local T_FEAR = 5.4 -- three close-ups, FEAR_SHOT each
local FEAR_SHOT = 0.75
local T_PANIC = T_FEAR + FEAR_SHOT * 3
local T_DROP = T_PANIC + 1.4
local T_RUN = T_DROP + 0.8
local T_SLOW = T_RUN + 8.1
local END_T = T_SLOW + 3.6
local HERO_START_Z = -640
local HERO_SPEED = 32
-- event times, all on the run
local E_SLIDE = T_RUN + 0.7 -- under a lava ball
local E_DJ = T_RUN + 2.4 -- over the boulder
local E_GEYSER = T_RUN + 3.0 -- a geyser in the path: swerve round it
local E_TREE = T_RUN + 3.7 -- a tree topples across the path: hurdle it
local E_CRACK = T_RUN + 5.1 -- the ground splits: leap it

-- the eggs, each picked up this long after the run starts (between the stunts), biome egg design (Shared/EggFactory)
local CAST = {
	{ at = 0.25, biome = 1 },
	{ at = 1.6, biome = 2 },
	{ at = 2.1, biome = 1 },
	{ at = 3.6, biome = 3 },
	{ at = 4.75, biome = 4 },
	{ at = 6.3, biome = 5 },
	{ at = 6.9, biome = 2 },
	{ at = 7.6, biome = 6 },
}
local GROUND_HEIGHT = { 3.6, 4, 4.4, 4.8, 5.2, 5.8 } -- an egg's height in the grass, by biome (cutscene sized)
local FEAR_STARS = { 1, 4, 8 } -- the close-ups (CAST indices)
-- the hero's weave across the meadow (seconds into the run, x offset): still at each egg, at X0 for the boulder
local WEAVE = {
	{ 0, 0 },
	{ 0.25, -5 },
	{ 0.9, 0 },
	{ 1.6, 6 },
	{ 2.1, 0 },
	{ 3.3, 0 },
	{ 4.75, -6 },
	{ 5.5, 0 },
	{ 6.3, 5 },
	{ 6.9, -4 },
	{ 7.6, 3 },
}

local SWEAT_DIR = Vector3.new(0.94, 0, -0.34).Unit -- the side of the egg it runs down (the side the camera sees)
local SWEAT_CYCLE = 1.15

local function smooth(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

local function backOut(k: number): number
	k = math.clamp(k, 0, 1)
	local c1 = 1.70158
	return 1 + (c1 + 1) * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
end

-- the hero's line: running from T_RUN, slow motion from T_SLOW
local function heroZ(t: number): number
	if t < T_RUN then
		return HERO_START_Z
	end
	local fast = math.min(t, T_SLOW) - T_RUN
	local slow = math.max(0, t - T_SLOW) * 0.35
	return HERO_START_Z - HERO_SPEED * (fast + slow)
end

local function heroX(t: number): number
	local r = t - T_RUN
	local x = WEAVE[#WEAVE][2]
	if r <= WEAVE[1][1] then
		x = WEAVE[1][2]
	else
		for i = 1, #WEAVE - 1 do
			local a, b = WEAVE[i], WEAVE[i + 1]
			if r < b[1] then
				x = a[2] + (b[2] - a[2]) * smooth((r - a[1]) / (b[1] - a[1]))
				break
			end
		end
	end
	-- the swerve round the geyser
	if t >= E_GEYSER - 0.1 and t < E_GEYSER + 0.9 then
		x += math.sin(math.pi * (t - (E_GEYSER - 0.1)) / 1.0) * 9
	end
	return X0 + x
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

local function punch(gui: GuiObject, from: number)
	local sc = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	sc.Scale = from
	sc.Parent = gui
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- "!" (or "!!") over an egg
local function exclaim(model: Model, text: string)
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	local h = model:GetAttribute("Height") or 4
	local bb = Instance.new("BillboardGui")
	bb.Name = "Exclaim"
	bb.Size = UDim2.fromOffset(60, 60)
	bb.StudsOffsetWorldSpace = Vector3.new(0, h * 0.5 + 1.6, 0)
	bb.AlwaysOnTop = false
	local l = label(bb, {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Text = text,
		TextColor3 = Color3.fromRGB(255, 60, 40),
	})
	bb.Parent = root
	punch(l, 0.2)
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

-- an egg model and its spinning parts (the Mythic egg's halo, the radioactive egg's barrels: Shared/EggFactory)
type Spinner = { model: Model, rel: CFrame, speed: number }
local function makeEgg(biome: number, height: number, design: number?): (Model?, { Spinner })
	local ok, model = pcall(EggFactory.create, biome, height, design)
	if not ok or not model then
		return nil, {}
	end
	local spinners: { Spinner } = {}
	local pivot = model:GetPivot()
	for attr, speed in { Halo = 0.8, Orbit = 0.6 } do
		local name = model:GetAttribute(attr)
		local child = name and model:FindFirstChild(name)
		if child and child:IsA("Model") then
			table.insert(spinners, { model = child, rel = pivot:Inverse() * child:GetPivot(), speed = speed })
		end
	end
	return model, spinners
end

local function placeEgg(model: Model, spinners: { Spinner }, cf: CFrame, t: number)
	model:PivotTo(cf)
	for _, s in spinners do
		s.model:PivotTo(cf * CFrame.Angles(0, t * s.speed, 0) * s.rel)
	end
end

-- the sweat drop: the plain sweat emoji 💧 (user 2026-11-21: the glassy ball drop "looks weird", like 😅's drop
-- instead), on a billboard so it always faces the camera; it pops in, bounces and drips down the shell
type SweatPart = { p: BasePart, gui: BillboardGui, size: number }
local function makeSweat(folder: Instance, d: number): { SweatPart }
	local model = Instance.new("Model")
	model.Name = "SweatDrop"
	local p = part(model, {
		Name = "Drop",
		Size = Vector3.one * 0.2,
		Transparency = 1,
		CastShadow = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Adornee = p
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(d, d * 1.2)
	gui.Enabled = false
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = "💧"
	l.TextScaled = true
	l.Rotation = -12
	l.Parent = gui
	gui.Parent = p
	model.Parent = folder
	return { { p = p, gui = gui, size = d } }
end

local function placeSweat(sweat: { SweatPart }, at: CFrame, scale: number)
	for _, s in sweat do
		s.gui.Enabled = scale >= 0.04
		if scale >= 0.04 then
			s.p.CFrame = at
			s.gui.Size = UDim2.fromScale(s.size * scale, s.size * 1.2 * scale)
		end
	end
end

type Egg = {
	model: Model?,
	spinners: { Spinner },
	carry: Model?,
	carrySpinners: { Spinner },
	carryH: number,
	biome: number,
	h: number,
	bodyY: number,
	home: Vector3,
	yaw: number,
	phase: number,
	pickAt: number,
	sweatAt: number,
	sweat: { SweatPart }?,
	spray: ParticleEmitter?,
	taken: boolean,
	takenAt: number,
	from: Vector3,
}

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

	-- screen: fade, subtitles, egg counter, title, skip
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
	local counter = label(gui, {
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromScale(0.42, 0.065),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 240, 170),
		Visible = false,
		ZIndex = 5,
	})
	local title = label(gui, {
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.9, 0.16),
		Text = string.upper(Config.GameName) .. "!",
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
		Text = "Rescue every egg before the disaster catches you!",
		Visible = false,
		ZIndex = 6,
	})
	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.fromScale(0.985, 0.97)
	skip.Size = UDim2.fromScale(0.18, 0.06)
	skip.SizeConstraint = Enum.SizeConstraint.RelativeYY
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

	-- the eggs, lying along the hero's route (each where the hero will be when it picks it up), plus the smaller
	-- copy that rides on the head stack (built now, so nothing is built mid-run)
	local eggs: { Egg } = {}
	for i, c in CAST do
		local h = GROUND_HEIGHT[c.biome]
		local pickAt = T_RUN + c.at
		local home = Vector3.new(heroX(pickAt), GROUND, heroZ(pickAt))
		-- (the eggs show both designs, mixed: user 2026-11-22)
		local design = (i % EggFactory.DesignCount) + 1
		local model, spinners = makeEgg(c.biome, h, design)
		if not model then
			continue
		end
		local carryH = Config.CarryEggHeight[c.biome] or 2.6
		local carry, carrySpinners = makeEgg(c.biome, carryH, design)
		local root = model.PrimaryPart :: BasePart
		local e: Egg = {
			model = model,
			spinners = spinners,
			carry = carry,
			carrySpinners = carrySpinners,
			carryH = carryH,
			biome = c.biome,
			h = h,
			bodyY = root.Position.Y - h / 2 - model:GetPivot().Position.Y,
			home = home,
			yaw = math.pi + rng:NextNumber(-0.5, 0.5),
			phase = rng:NextNumber(0, 10),
			pickAt = pickAt,
			sweatAt = T_SWEAT + (i - 1) * 0.09,
			sweat = nil,
			spray = nil,
			taken = false,
			takenAt = 0,
			from = home,
		}
		placeEgg(model, spinners, CFrame.new(home) * CFrame.Angles(0, e.yaw, 0), 0)
		model.Parent = folder
		table.insert(eggs, e)
	end
	local fearStars: { Egg } = {}
	for _, i in FEAR_STARS do
		local e = eggs[i]
		if e then
			table.insert(fearStars, e)
		end
	end
	local total = #eggs

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

	local carriedList: { Egg } = {}
	local events: { [string]: boolean } = {}
	local function once(name: string): boolean
		if events[name] then
			return false
		end
		events[name] = true
		return true
	end
	local nextRain = T_RUN + 0.3
	local nextSqueak = T_SWEAT
	local t0 = os.clock()
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
		for _, e in eggs do
			-- (the head-stack copies of the eggs not picked up yet were never parented to the folder)
			if e.carry then
				e.carry:Destroy()
			end
			if e.model then
				e.model:Destroy()
			end
		end
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
		counter.Visible = false
		subtitle.Text = ""
		skip.Visible = false
		TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.delay(0.7, function()
			gui:Destroy()
		end)
		playing = false
	end

	TweenService:Create(fade, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	say("Far away, the eggs lay safe and sound in the meadows...")

	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if skipped or t >= END_T then
			task.spawn(finish)
			return
		end
		local shotIndex = if t >= T_FEAR and t < T_PANIC
			then math.clamp(math.floor((t - T_FEAR) / FEAR_SHOT) + 1, 1, 3)
			else 0
		local star = fearStars[shotIndex]

		-- the eggs in the grass: a lazy wobble, then panic (trembling, hopping, sweating) until the hero gets them
		for i, e in eggs do
			local model = e.model
			if e.taken or not model then
				continue
			end
			local h = e.h
			local cf
			if t < T_ERUPT then
				local c = (t + e.phase) % 3.2
				local w = if c < 0.8 then math.sin(c * 25) * 0.07 * (1 - c / 0.8) else 0
				cf = CFrame.new(e.home) * CFrame.Angles(w, e.yaw, w * 0.6)
			else
				local panic = t >= e.sweatAt
				local frantic = if t >= T_PANIC then 1.5 else 1
				local shake = (if panic then 0.06 else 0.035) * h
				local j = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * shake
				local hop = 0
				if panic then
					local k = (t * 2.1 * frantic + e.phase) % 1
					hop = if k < 0.45 then math.sin(math.pi * k / 0.45) * 0.22 * h else 0
				end
				local tilt = math.sin(t * 38 + e.phase) * (if panic then 0.08 else 0.04)
				cf = CFrame.new(e.home + j + Vector3.new(0, hop, 0)) * CFrame.Angles(tilt, e.yaw, -tilt * 0.7)
			end
			placeEgg(model, e.spinners, cf, t)

			-- the sweat drop: pops out on the upper side, bounces, drips down the shell, pops out again
			if t >= e.sweatAt then
				local root = model.PrimaryPart
				if not e.sweat then
					e.sweat = makeSweat(folder, h * 0.34)
					if root then
						e.spray = emitter(root, {
							Name = "SweatSpray",
							Texture = SPARK,
							Color = ColorSequence.new(Color3.fromRGB(150, 215, 255)),
							Size = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.12 * h),
								NumberSequenceKeypoint.new(1, 0),
							}),
							Lifetime = NumberRange.new(0.35, 0.6),
							Speed = NumberRange.new(1.6 * h, 2.4 * h),
							Acceleration = Vector3.new(0, -9 * h, 0),
							EmissionDirection = Enum.NormalId.Top,
							SpreadAngle = Vector2.new(55, 55),
							Rate = 7,
						})
					end
					if i == 1 then
						ChaseFx.play("Pop", 0.8, 1.9)
					end
				end
				local sweat = e.sweat :: { SweatPart }
				local age = t - e.sweatAt
				local u = (age % SWEAT_CYCLE) / SWEAT_CYCLE
				local scale = if u < 0.18 then backOut(u / 0.18) elseif u > 0.86 then 1 - (u - 0.86) / 0.14 else 1
				scale *= 1 + 0.12 * math.sin(t * 17)
				if star == e then
					scale *= 1.3 -- (a bigger one in the close-up)
				end
				local yFrac = 0.8 - 0.3 * smooth((u - 0.25) / 0.6)
				local r = EggFactory.radiusAt(yFrac * 10) * h / 10
				local surface = (cf * CFrame.new(0, e.bodyY + yFrac * h, 0)).Position
				local d = h * 0.34
				local at = CFrame.new(surface + SWEAT_DIR * (r + d * 0.25)) * CFrame.Angles(0, 0, 0.3)
				placeSweat(sweat, at, scale)
			end
		end
		-- little panicked squeaks
		if t >= nextSqueak and t < T_SLOW and #carriedList < total then
			nextSqueak = t + rng:NextNumber(0.3, 0.6)
			ChaseFx.play("Pop", rng:NextNumber(0.35, 0.6), rng:NextNumber(1.7, 2.3))
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
			local z = LAVA_Z - math.max(0, t - T_PANIC) * 19
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
		if t >= T_SWEAT and once("sweat") then
			say("The eggs broke into a cold sweat!")
		end

		-- 3. fear close-ups: a big sweat drop, "!!", a squeak, one egg after another
		if star and once("fear" .. shotIndex) then
			if shotIndex == 1 then
				say("They were terrified!")
			end
			if star.model then
				exclaim(star.model, "!!")
			end
			ChaseFx.play("Pop", 0.9, 2 + shotIndex * 0.1)
			ChaseFx.kick(4)
		end
		-- 4. panic: everyone else gets a "!" too
		if t >= T_PANIC and once("panic") then
			say("Who could save them now?")
			ChaseFx.play("Whoosh", 1, 0.8)
			for _, e in eggs do
				if e.model and not table.find(fearStars, e) then
					exclaim(e.model, "!")
				end
			end
		end

		-- 5. the hero
		if heroRoot then
			local z = heroZ(t)
			local x = heroX(t)
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
				counter.Text = `EGGS SAVED: 0/{total}`
				counter.Visible = true
				punch(counter, 0.3)
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
			-- c) the geyser: it bursts up right ahead, the hero swerves round it (heroX)
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
			-- scoop up each egg as the hero reaches it: it pops up onto the head stack, its sweat gone
			for _, e in eggs do
				if not e.taken and t >= e.pickAt - 0.05 then
					e.taken = true
					e.takenAt = t
					local model = e.model
					if model then
						e.from = model:GetPivot().Position
						burst(folder, e.from + Vector3.new(0, e.h * 0.5, 0), Color3.fromRGB(255, 240, 120), 30, SPARK)
						model:Destroy()
						e.model = nil
					end
					if e.sweat then
						local drop = e.sweat[1] and e.sweat[1].p.Parent
						if drop then
							drop:Destroy()
						end
						e.sweat = nil
					end
					if e.carry then
						e.carry.Parent = folder
					end
					table.insert(carriedList, e)
					local n = #carriedList
					ChaseFx.play("Pop", 1, 1.1 + n * 0.08)
					ChaseFx.play("Good", 1, 0.95 + n * 0.06)
					ChaseFx.kick(6)
					counter.Text = if n >= total then `ALL {total} EGGS SAVED!` else `EGGS SAVED: {n}/{total}`
					if n >= total then
						counter.TextColor3 = Color3.fromRGB(255, 215, 60)
						ChaseFx.play("Confetti", 0.8, 1.1)
					end
					punch(counter, 1.5)
					if n == 1 then
						say("The hero scooped them up, one by one...")
					elseif n == total then
						say("...and saved every single egg!")
					end
				end
			end
			if t >= T_DROP then
				local ahead = Vector3.new(heroX(t + 0.1) - x, 0, heroZ(t + 0.1) - z)
				if ahead.Magnitude < 0.01 then
					ahead = Vector3.new(0, 0, -1)
				end
				local p = Vector3.new(x, heroY, z)
				heroRoot.CFrame = CFrame.lookAt(p, p + ahead)
			end
			-- the saved eggs ride stacked on the hero's head (each flies up there first), swaying on the run
			local head = hero and hero:FindFirstChild("Head") :: BasePart?
			local top = if head
				then head.Position + Vector3.new(0, head.Size.Y / 2 + 0.1, 0)
				else heroRoot.Position + Vector3.new(0, 3, 0)
			local facing = heroRoot.CFrame.Rotation
			for i, e in carriedList do
				local carry = e.carry
				if not carry then
					continue
				end
				local slot = top + facing.RightVector * math.sin(t * 7) * 0.07 * (i - 1)
				local k = smooth((t - e.takenAt) / 0.32)
				local pos = e.from:Lerp(slot, k) + Vector3.new(0, math.sin(math.pi * k) * 5, 0)
				local spin = (1 - k) * math.pi * 2
				placeEgg(carry, e.carrySpinners, CFrame.new(pos) * facing * CFrame.Angles(0, math.pi + spin, 0), t)
				top += Vector3.new(0, e.carryH * 0.95, 0)
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
			punch(title, 3)
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
		local stackH = 0
		for _, e in carriedList do
			stackH += e.carryH * 0.95
		end
		local camCF
		if t < T_ERUPT then
			-- a slow drift down over the eggs in the grass
			local k = smooth(t / T_ERUPT)
			local a = CFrame.lookAt(Vector3.new(X0 + 110, 50, -880), Vector3.new(X0, 4, -770))
			local b = CFrame.lookAt(Vector3.new(X0 + 30, 14, -735), Vector3.new(X0, 4, -680))
			camCF = a:Lerp(b, k)
		elseif t < T_FEAR then
			-- look up at the eruption, the first eggs in the foreground
			local from = CFrame.lookAt(Vector3.new(X0 + 30, 14, -735), Vector3.new(X0, 4, -680))
			local to = CFrame.lookAt(Vector3.new(X0 + 10, 6, -705), Vector3.new(X0, 34, LAVA_Z))
			camCF = from:Lerp(to, smooth((t - T_ERUPT) / 0.6))
		elseif t < T_PANIC then
			-- close-ups on the sweaty side, the lava behind, slowly pushing in
			if star then
				local h = star.h
				local p = star.home
				local k = ((t - T_FEAR) % FEAR_SHOT) / FEAR_SHOT
				local dist = h * (2.3 - 0.5 * k)
				local eye = p + Vector3.new(h * 0.9, h * 0.85, -dist)
				camCF = CFrame.lookAt(eye, p + Vector3.new(0, h * 0.62, 0))
			else
				camCF = cam.CFrame
			end
		elseif t < T_DROP then
			-- wide and low: all the eggs hopping in panic, the lava rolling in
			local k = t - T_PANIC
			camCF = CFrame.lookAt(Vector3.new(X0 + 18, 6, -775 + k * 6), Vector3.new(X0, 5, -690))
		elseif t < T_SLOW then
			local z = heroZ(t)
			local y = if heroRoot then heroRoot.Position.Y else GROUND + 3
			if t < T_DROP + 0.6 then
				camCF =
					CFrame.lookAt(Vector3.new(X0 + 18, GROUND + 4, HERO_START_Z - 14), Vector3.new(X0, y, HERO_START_Z))
			else
				-- tracking from the side, slightly ahead (the next egg in view), pulling back as the stack grows;
				-- swinging round for the tree
				local x = heroX(t)
				local side = if t >= E_TREE - 0.4 and t < E_TREE + 1 then -1 else 1
				local dist = 20 + stackH * 0.45
				local from = Vector3.new(
					X0 + (x - X0) * 0.5 + dist * side,
					GROUND + 6 + (y - GROUND - 3) * 0.4 + stackH * 0.3,
					z - 7
				)
				camCF = CFrame.lookAt(from, Vector3.new(x, y + stackH * 0.4, z - 5))
			end
		else
			-- low, ahead of the hero, slow motion, backing away; the whole stack in view
			local zc = heroZ(T_SLOW) - 36 - (t - T_SLOW) * 7
			camCF = CFrame.lookAt(
				Vector3.new(X0 - 4, GROUND + 5, zc),
				Vector3.new(heroX(t), GROUND + 6 + stackH * 0.4, heroZ(t) + 4)
			)
		end
		cam.CFrame = camCF * jitter
	end)
end

function IntroCutscene.init()
	local function start()
		task.spawn(function()
			-- (after the loading screen: the whole map is there by then, ReplicatedFirst/Loading)
			local t0 = os.clock()
			while not player:GetAttribute("WorldReady") and os.clock() - t0 < 120 do
				task.wait(0.2)
			end
			pcall(function()
				player:RequestStreamAroundAsync(Vector3.new(X0, GROUND, -700), 4)
			end)
			task.wait(0.3)
			local ok, err = pcall(IntroCutscene.play)
			if not ok then
				warn("[IntroCutscene]", err)
				playing = false
			end
		end)
	end
	-- your first visit (Server/Main), and every /intro from the admin panel
	player:GetAttributeChangedSignal("PlayIntro"):Connect(function()
		if player:GetAttribute("PlayIntro") == true then
			start()
		end
	end)
	Net.event("PlayIntro").OnClientEvent:Connect(start)
	if player:GetAttribute("PlayIntro") == true then
		start()
	end
end

return IntroCutscene
