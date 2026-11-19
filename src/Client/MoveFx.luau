-- Movement effects on every character this client sees (so you see other players' too):
--   * running: thin white wind trails off the hands and feet, small dust puffs at each footstep
--   * double jump: a white air ring expanding under the feet at the second boost, with short upward streaks
--   * slide: curling white dust and wind streaks behind the character while the slide animation plays
--   * your own character leans sideways into turns while running
-- The slide / double jump are spotted by their animation playing (animations replicate, attributes don't).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

local MoveFx = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local RING_MESH = "rbxassetid://3270017" -- the classic torus ring mesh
-- Sounds: loaded once at start, and each character keeps its own copies that are simply replayed, so they play the
-- instant the move starts (a freshly made Sound has to load first, ~0.4 s late).
local WOOSH = "rbxassetid://90261693738952" -- "Thick Cloth - Swoosh - Weak (Short)": a soft whoosh as you flip
local SKID = "rbxassetid://9118771226" -- "Sand Slide, Long Skids" (Pro Sound Effects), pitched up: a light grass swish
local preloaded = false
local function preload()
	if preloaded then
		return
	end
	preloaded = true
	task.spawn(function()
		local list = {}
		for _, id in { WOOSH, SKID } do
			local snd = Instance.new("Sound")
			snd.SoundId = id
			table.insert(list, snd)
		end
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end)
end

local function makeSound(root: BasePart, id: string, pitch: number): Sound
	local snd = Instance.new("Sound")
	snd.Name = "SAFD_MoveSound"
	snd.SoundId = id
	snd.PlaybackSpeed = pitch
	snd.RollOffMinDistance = 10
	snd.RollOffMaxDistance = 110
	snd.Parent = root
	return snd
end

local function sfxVolume(): number
	return 2 * (player:GetAttribute("SfxVolume") or 0.5)
end

local holder: Part
local dustAt: Attachment
local dust: ParticleEmitter
local streakAt: Attachment
local streaks: ParticleEmitter

type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	trails: { Trail },
	nextStep: number,
	stepSide: number,
	sliding: AnimationTrack?,
	nextSlideFx: number,
}
local rigs: { [Model]: Rig } = {}

local function emitAt(attachment: Attachment, emitter: ParticleEmitter, position: Vector3, count: number)
	attachment.WorldPosition = position
	emitter:Emit(count)
end

local function trail(part: BasePart, a: Vector3, b: Vector3): Trail
	local a0 = Instance.new("Attachment")
	a0.Name = "SAFD_FxA0"
	a0.Position = a
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "SAFD_FxA1"
	a1.Position = b
	a1.Parent = part
	local t = Instance.new("Trail")
	t.Name = "SAFD_Wind"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(Color3.new(1, 1, 1))
	t.LightEmission = 0.6
	t.Lifetime = 0.16
	t.MinLength = 0.05
	t.FaceCamera = true
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	t.Enabled = false
	t.Parent = part
	return t
end

local function airRing(position: Vector3)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Size = Vector3.one
	ring.Transparency = 0.2
	ring.Color = Color3.new(1, 1, 1)
	ring.Material = Enum.Material.Neon
	ring.CFrame = CFrame.new(position) * CFrame.Angles(math.pi / 2, 0, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = RING_MESH
	mesh.Scale = Vector3.new(0.8, 0.8, 0.4)
	mesh.Parent = ring
	ring.Parent = Workspace
	local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(mesh, info, { Scale = Vector3.new(4.5, 4.5, 0.2) }):Play()
	TweenService:Create(ring, info, { Transparency = 1 }):Play()
	task.delay(0.45, function()
		ring:Destroy()
	end)
	-- short upward trails
	streaks.Speed = NumberRange.new(28, 40)
	streaks.EmissionDirection = Enum.NormalId.Top
	streaks.SpreadAngle = Vector2.new(25, 25)
	emitAt(streakAt, streaks, position, 10)
	emitAt(dustAt, dust, position, 6)
end

local function addRig(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	local r: Rig = {
		character = character,
		humanoid = humanoid,
		root = root,
		trails = {},
		nextStep = 0,
		stepSide = 1,
		sliding = nil,
		nextSlideFx = 0,
	}
	for _, name in { "Left Arm", "Right Arm" } do
		local p = character:WaitForChild(name, 5)
		if p and p:IsA("BasePart") then
			table.insert(r.trails, trail(p, Vector3.new(0, -0.75, 0), Vector3.new(0, -1, 0)))
		end
	end
	for _, name in { "Left Leg", "Right Leg" } do
		local p = character:WaitForChild(name, 5)
		if p and p:IsA("BasePart") then
			table.insert(r.trails, trail(p, Vector3.new(0, -0.75, 0), Vector3.new(0, -1, 0)))
		end
	end
	-- this character's own move sounds (replayed, never re-made)
	local woosh = makeSound(root, WOOSH, 1.05)
	local swish = makeSound(root, SKID, 1.35)
	local animator = humanoid:WaitForChild("Animator", 10) :: Animator?
	if animator then
		animator.AnimationPlayed:Connect(function(track)
			local id = track.Animation and track.Animation.AnimationId or ""
			if id == Config.DoubleJumpAnimation then
				airRing(root.Position - Vector3.new(0, 3, 0))
				-- a soft whoosh, as subtle as the slide's swish
				woosh.Volume = 0.45 * sfxVolume()
				woosh.TimePosition = 0
				woosh:Play()
			elseif id == Config.SlideAnimation then
				r.sliding = track
				-- a light swish across the grass while you slide, fading as you get up
				swish.Volume = 0.35 * sfxVolume()
				swish.TimePosition = 0
				swish:Play()
				track.Stopped:Once(function()
					TweenService:Create(swish, TweenInfo.new(0.15), { Volume = 0 }):Play()
					task.delay(0.16, function()
						swish:Stop()
					end)
				end)
			end
		end)
	end
	rigs[character] = r
	character.Destroying:Connect(function()
		rigs[character] = nil
	end)
	humanoid.Died:Connect(function()
		rigs[character] = nil
	end)
end

local function hook(p: Player)
	p.CharacterAdded:Connect(function(c)
		task.spawn(addRig, c)
	end)
	if p.Character then
		task.spawn(addRig, p.Character)
	end
end

-- own character: lean into turns (RootJoint roll; joint-space Y is the character's back axis)
local leanJoint: Motor6D? = nil
local leanBase: CFrame? = nil
local lean = 0

local function update(dt: number)
	local now = os.clock()
	for character, r in rigs do
		if not character.Parent then
			rigs[character] = nil
			continue
		end
		local v = r.root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local grounded = r.humanoid.FloorMaterial ~= Enum.Material.Air
		local slidingNow = r.sliding ~= nil and r.sliding.IsPlaying
		local fast = speed > 18
		for _, t in r.trails do
			t.Enabled = fast
		end
		local feet = r.root.Position - Vector3.new(0, 3, 0)
		if slidingNow then
			if now >= r.nextSlideFx and speed > 2 then
				r.nextSlideFx = now + 0.05
				local back = if speed > 0.1 then -Vector3.new(v.X, 0, v.Z).Unit else -r.root.CFrame.LookVector
				emitAt(dustAt, dust, feet + back * 1.5 + Vector3.new(0, 0.4, 0), 2)
				streaks.Speed = NumberRange.new(10, 18)
				streaks.EmissionDirection = Enum.NormalId.Top
				streaks.SpreadAngle = Vector2.new(60, 60)
				emitAt(streakAt, streaks, feet + back * 2 + Vector3.new(0, 1, 0), 1)
			end
		elseif grounded and speed > 8 and now >= r.nextStep then
			-- a footstep every stride: quicker the faster you run
			r.nextStep = now + math.clamp(5.5 / speed, 0.12, 0.35)
			r.stepSide = -r.stepSide
			local side = r.root.CFrame.RightVector * 0.5 * r.stepSide
			emitAt(dustAt, dust, feet + side + Vector3.new(0, 0.2, 0), 2)
		end
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local joint = root and root:FindFirstChild("RootJoint")
	if joint and joint:IsA("Motor6D") then
		if leanJoint ~= joint then
			leanJoint = joint
			leanBase = joint.C0
			lean = 0
		end
		local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
		local v = (root :: BasePart).AssemblyLinearVelocity
		local running = humanoid
			and humanoid.FloorMaterial ~= Enum.Material.Air
			and Vector3.new(v.X, 0, v.Z).Magnitude > 8
		local turn = (root :: BasePart).AssemblyAngularVelocity.Y
		local target = if running then math.clamp(turn * 0.025, -0.1, 0.1) else 0 -- (a very slight lean)
		lean += (target - lean) * math.min(dt * 10, 1)
		joint.C0 = (leanBase :: CFrame) * CFrame.Angles(0, lean, 0)
	end
end

function MoveFx.init()
	preload()
	holder = Instance.new("Part")
	holder.Name = "SAFD_MoveFx"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.identity
	holder.Parent = Workspace

	dustAt = Instance.new("Attachment")
	dustAt.Parent = holder
	dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE
	dust.Color = ColorSequence.new(Color3.fromRGB(245, 245, 245))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.35, 0.7)
	dust.Speed = NumberRange.new(1.5, 4)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.RotSpeed = NumberRange.new(-120, 120) -- curling
	dust.Rotation = NumberRange.new(0, 360)
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.Rate = 0
	dust.Parent = dustAt

	streakAt = Instance.new("Attachment")
	streakAt.Parent = holder
	streaks = Instance.new("ParticleEmitter")
	streaks.Texture = SPARK
	streaks.Color = ColorSequence.new(Color3.new(1, 1, 1))
	streaks.LightEmission = 0.7
	streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
	streaks.Squash = NumberSequence.new(-2.5) -- long thin streaks
	streaks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	streaks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	streaks.Lifetime = NumberRange.new(0.2, 0.35)
	streaks.Speed = NumberRange.new(10, 18)
	streaks.Rate = 0
	streaks.Parent = streakAt

	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	RunService.Heartbeat:Connect(update)
end

return MoveFx
