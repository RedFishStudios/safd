-- Client-side animal life: idle/walk animations for every animal, and base animals wandering
-- around inside their owner's base. Runs locally on every client, so it's smooth and costs
-- the server nothing.
--
-- Animation source: Config.AnimationIds (uploaded ids, required for live servers). In Studio,
-- falls back to registering the pack's KeyframeSequences on the fly.

local CollectionService = game:GetService("CollectionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalFactory = require(Shared.AnimalFactory)
local Config = require(Shared.Config)

local MapInfo = require(Shared.MapInfo)

local Bases = require(script.Parent.Bases)

local AnimalVisuals = {}

local KINDS = { "Idle", "Walk" }
local PATTERNS = { Idle = { "idle" }, Walk = { "walk", "swim", "fly" } }

local idCache: { [string]: string | false } = {}
local tracks: { [Model]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
local warned = false
local rng = Random.new()

local function findKeyframes(animalId: string, kind: string): KeyframeSequence?
	local template = AnimalFactory.findTemplate(animalId)
	local saves = template and template:FindFirstChild("Animations")
	if not saves then
		return nil
	end
	for _, pattern in PATTERNS[kind] do
		for _, child in saves:GetChildren() do
			if child:IsA("KeyframeSequence") and string.find(string.lower(child.Name), pattern, 1, true) then
				return child
			end
		end
	end
	return nil
end

function AnimalVisuals.animationId(animalId: string, kind: string): string?
	local key = animalId .. "/" .. kind
	local cached = idCache[key]
	if cached ~= nil then
		return cached or nil
	end
	local configured = Config.AnimationIds[animalId]
	local id = configured and configured[kind]
	if not id or id == "" then
		id = nil
		if RunService:IsStudio() then
			local keyframes = findKeyframes(animalId, kind)
			if keyframes then
				local ok, result = pcall(function()
					return KeyframeSequenceProvider:RegisterKeyframeSequence(keyframes)
				end)
				if ok then
					id = result
				end
			end
		elseif not warned then
			warned = true
			warn(
				"[AnimalVisuals] no uploaded animation ids in Config.AnimationIds; animals won't animate in live servers"
			)
		end
	end
	idCache[key] = id or false
	return id
end

function AnimalVisuals.play(model: Model, kind: string)
	local entry = tracks[model]
	if not entry then
		entry = {}
		tracks[model] = entry
	end
	if entry.current == kind then
		return
	end
	entry.current = kind
	local animalId = model:GetAttribute("AnimalId")
	if not animalId then
		return
	end
	local track = entry[kind]
	if track == nil then
		track = false
		local controller = model:FindFirstChildOfClass("AnimationController") or model:FindFirstChildOfClass("Humanoid")
		local animationId = AnimalVisuals.animationId(animalId, kind)
		if controller and animationId then
			local animator = controller:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = controller
			end
			local animation = Instance.new("Animation")
			animation.AnimationId = animationId
			local ok, loaded = pcall(function()
				return (animator :: Animator):LoadAnimation(animation)
			end)
			if ok and loaded then
				loaded.Looped = true
				track = loaded
			end
		end
		entry[kind] = track
	end
	for _, other in KINDS do
		local t = entry[other]
		if other ~= kind and t then
			t:Stop(0.25)
		end
	end
	if track then
		track:Play(0.25)
	end
end

-- Wandering -----------------------------------------------------------------------------------------------------

type Wanderer = {
	bounds: { number }, -- minX, maxX, minZ, maxZ in anchor space
	radius: number,
	anchor: CFrame,
	home: Vector2,
	pos: Vector2,
	y: number,
	yaw: number,
	target: Vector2?,
	wait: number,
	speed: number,
}

local wanderers: { [Model]: Wanderer } = {}

local function yawOf(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

local function lerpAngle(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + diff * t
end

local function addBaseAnimal(model: Instance)
	if not model:IsA("Model") then
		return
	end
	AnimalVisuals.play(model, "Idle")
	-- Only the owner sees the "Pick up" prompt.
	if model:GetAttribute("Owner") ~= Players.LocalPlayer.UserId then
		local prompt = model:FindFirstChild("PickupPrompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
	end
	local base = Bases.byIndex(model:GetAttribute("Plot") or -1)
	local anchor = base and base:GetAttribute("Anchor")
	if not base or not anchor then
		return
	end
	local pivot = model:GetPivot()
	local localPos = anchor:PointToObjectSpace(pivot.Position)
	local home = Vector2.new(localPos.X, localPos.Z)
	wanderers[model] = {
		bounds = {
			base:GetAttribute("MinX"),
			base:GetAttribute("MaxX"),
			base:GetAttribute("MinZ"),
			base:GetAttribute("MaxZ"),
		},
		radius = Config.AnimalWanderRadius,
		anchor = anchor,
		home = home,
		pos = home,
		y = pivot.Position.Y,
		yaw = yawOf(pivot.LookVector),
		target = nil,
		wait = rng:NextNumber(0.5, 4),
		speed = Config.AnimalWanderSpeed * rng:NextNumber(0.8, 1.2),
	}
end

-- Only solid things are in the way (trees, rocks, cacti, the run's blockades): grass, pebbles and the paths have
-- their collisions off, so the cast goes straight through them.
local pathParams = RaycastParams.new()
pathParams.FilterType = Enum.RaycastFilterType.Exclude
pathParams.RespectCanCollide = true
local lastFilter = 0
local function pathClear(w: Wanderer, model: Model, to: Vector2): boolean
	local now = os.clock()
	if now - lastFilter > 2 then
		lastFilter = now
		local ex: { Instance } = {}
		for _, name in { "WildAnimals", "BaseAnimals", "PlayerBases" } do
			local f = workspace:FindFirstChild(name)
			if f then
				table.insert(ex, f)
			end
		end
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ex, p.Character)
			end
		end
		pathParams.FilterDescendantsInstances = ex
	end
	local h = model:GetAttribute("Height") or 4
	local r = math.clamp(h * 0.3, 0.8, 4)
	local from = w.anchor:PointToWorldSpace(Vector3.new(w.pos.X, 0, w.pos.Y))
	local goal = w.anchor:PointToWorldSpace(Vector3.new(to.X, 0, to.Y))
	local y = w.y + r + 0.6 -- (above the floor, so the ground itself doesn't count)
	local a, b = Vector3.new(from.X, y, from.Z), Vector3.new(goal.X, y, goal.Z)
	local dir = b - a
	if dir.Magnitude < 0.1 then
		return true
	end
	return workspace:Spherecast(a, r, dir + dir.Unit * r, pathParams) == nil
end

local function pickTarget(w: Wanderer, model: Model): Vector2?
	for _ = 1, 6 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(2, w.radius)
		local p = w.home + Vector2.new(math.cos(angle), math.sin(angle)) * radius
		local b = w.bounds
		local t = Vector2.new(math.clamp(p.X, b[1], b[2]), math.clamp(p.Y, b[3], b[4]))
		if pathClear(w, model, t) then
			return t
		end
	end
	return nil
end

-- Far from the camera an animal sleeps: no animation and no wandering, so dozens of (big) animals out of sight cost
-- nothing. It wakes when you come back within WAKE studs.
local SLEEP, WAKE = 280, 240
local function setAsleep(model: Model, w: any, asleep: boolean)
	w.asleep = asleep
	local entry = tracks[model]
	if asleep then
		if entry then
			for _, kind in KINDS do
				local t = entry[kind]
				if t then
					t:Stop(0)
				end
			end
			entry.current = nil
		end
	else
		AnimalVisuals.play(model, if w.target then "Walk" else "Idle")
	end
end

local function step(dt: number)
	local cam = workspace.CurrentCamera
	local eye = if cam then cam.CFrame.Position else Vector3.zero
	for model, w in wanderers do
		if not model.Parent then
			wanderers[model] = nil
			continue
		end
		local far = (model:GetPivot().Position - eye).Magnitude
		if w.asleep then
			if far < WAKE then
				setAsleep(model, w, false)
			else
				continue
			end
		elseif far > SLEEP then
			setAsleep(model, w, true)
			continue
		end
		-- frozen while you hold E on it, so the hold never slips
		if model:GetAttribute("Held") then
			continue
		end
		-- Wild animals hold still while the local player is close, so "hold E" is not a chase.
		if w.radius > Config.AnimalWanderRadius then
			local root = Players.LocalPlayer.Character
				and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if
				root
				and (root.Position - model:GetPivot().Position).Magnitude < 14 + (model:GetAttribute("Height") or 0)
			then
				if w.target then
					w.target = nil
					AnimalVisuals.play(model, "Idle")
				end
				w.wait = 1
				continue
			end
		end
		local target = w.target
		if target then
			local delta = target - w.pos
			local distance = delta.Magnitude
			if distance < 0.2 then
				w.target = nil
				w.wait = rng:NextNumber(2, 5)
				AnimalVisuals.play(model, "Idle")
			else
				w.pos += delta.Unit * math.min(distance, w.speed * dt)
				local dir = w.anchor:VectorToWorldSpace(Vector3.new(delta.X, 0, delta.Y)).Unit
				local wanted = yawOf(dir) + (if Config.AnimalFacingFlip then math.pi else 0)
				w.yaw = lerpAngle(w.yaw, wanted, math.min(1, dt * 6))
				local world = w.anchor:PointToWorldSpace(Vector3.new(w.pos.X, 0, w.pos.Y))
				model:PivotTo(CFrame.new(world.X, w.y, world.Z) * CFrame.Angles(0, w.yaw, 0))
			end
		else
			w.wait -= dt
			if w.wait <= 0 then
				w.target = pickTarget(w, model)
				if w.target then
					AnimalVisuals.play(model, "Walk")
				else
					w.wait = rng:NextNumber(1, 3) -- (boxed in: look around a bit, try again)
				end
			end
		end
	end
end

local function watchTag(tag: string, onAdded: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		if instance:IsA("Model") then
			wanderers[instance] = nil
			tracks[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdded, instance)
	end
end

-- Wild animals roam around where they spawned, inside their biome track. Runs on each client; the
-- rescue prompt moves with the model, and the server only checks a generous distance.
local function addWildAnimal(model: Instance)
	if not model:IsA("Model") then
		return
	end
	AnimalVisuals.play(model, "Idle")
	-- the prompt shows at its real range here (the server allows more, for the wandering: Server/AnimalService)
	task.spawn(function()
		local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
		for _ = 1, 20 do
			if prompt then
				break
			end
			task.wait(0.25)
			prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
		end
		if prompt and prompt:IsA("ProximityPrompt") then
			local range = prompt:GetAttribute("ClientRange")
			if type(range) == "number" then
				prompt.MaxActivationDistance = range
			end
		end
	end)
	local biome = model:GetAttribute("Biome")
	local minV, maxV = MapInfo.bounds(biome or 1)
	if not minV then
		return
	end
	local pivot = model:GetPivot()
	local home = Vector2.new(pivot.Position.X, pivot.Position.Z)
	wanderers[model] = {
		bounds = { minV.X + 6, maxV.X - 6, minV.Z + 6, maxV.Z - 6 },
		radius = 16,
		anchor = CFrame.identity,
		home = home,
		pos = home,
		y = pivot.Position.Y,
		yaw = yawOf(pivot.LookVector),
		target = nil,
		wait = rng:NextNumber(0.2, 3),
		speed = Config.AnimalWanderSpeed * rng:NextNumber(0.9, 1.4),
	}
end

local function playIdle(instance: Instance)
	if instance:IsA("Model") then
		AnimalVisuals.play(instance, "Idle")
	end
end

function AnimalVisuals.init()
	watchTag("WildAnimal", addWildAnimal)
	watchTag("CarriedAnimal", playIdle)
	watchTag("BaseAnimal", addBaseAnimal)
	RunService.Heartbeat:Connect(step)
	local PromptService = game:GetService("ProximityPromptService")
	PromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local model = prompt:FindFirstAncestorWhichIsA("Model")
		if model and wanderers[model] then
			model:SetAttribute("Held", true)
			if wanderers[model].target then
				wanderers[model].target = nil
				AnimalVisuals.play(model, "Idle")
			end
		end
	end)
	PromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local model = prompt:FindFirstAncestorWhichIsA("Model")
		if model then
			task.delay(1, function()
				if model.Parent then
					model:SetAttribute("Held", nil)
				end
			end)
		end
	end)
end

return AnimalVisuals
