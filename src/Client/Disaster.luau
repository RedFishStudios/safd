-- The escape sequence, entirely client-side (only the player who triggered it sees it):
--   * a short cutscene first: the camera flies to the far end of the biome, where the disaster rises out of the
--     ground with a roar, then swoops back behind you: RUN!
--   * the wall made of the biome then comes after you (fast while it's far behind, Config.WallCatchUpGap)
--   * a different course every run (Client/RunCourse): blockades, split paths, ziplines, launch pads, x2/x3/x5 rings
--   * every action answers with a sound and a camera punch (Client/ChaseFx)
--   * nearby scenery topples over one piece at a time, rocks drop from the sky, the floor cracks
--   * touching any of that slows the player for Config.SlowDuration seconds
--   * red "RUN!" banner, pulsing red screen edges, camera shake, tint, music
-- Everything is undone when the player crosses the white line (or dies).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapInfo = require(Shared.MapInfo)
local MapStyle = require(Shared.MapStyle)
local Net = require(Shared.Net)

local ChaseFx = require(script.Parent.ChaseFx)
local HUD = require(script.Parent.HUD)
local Hazards = require(script.Parent.Hazards)
local RunCourse = require(script.Parent.RunCourse)
local Movement = require(script.Parent.Movement)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local rng = Random.new()

local Disaster = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local WALL_THICKNESS = 16

type State = {
	biome: number,
	speed: number,
	toBase: Vector3,
	trackMinX: number,
	trackMaxX: number,
	folder: Folder,
	wall: Model,
	wallCF: CFrame,
	gui: ScreenGui,
	runLabel: TextLabel,
	runScale: UIScale,
	distanceLabel: TextLabel,
	slowLabel: TextLabel,
	edges: { Frame },
	tint: ColorCorrectionEffect,
	fov: number,
	fallen: { [Instance]: CFrame },
	uncollided: { BasePart },
	groundY: number,
	candidates: { Instance },
	lastScan: number,
	obstacles: { Instance },
	overlap: OverlapParams,
	nextTopple: number,
	shaking: { [Instance]: { bottom: Vector3, axis: Vector3, t0: number, original: CFrame } },
	nextTrailTopple: number,
	nextSpectacle: number,
	nextGeyser: number,
	nextCollapse: number,
	lastSide: number,
	nextProjectile: number,
	nextRoller: number,
	crossings: number,
	nextBarrage: number,
	shake: number,
	connections: { RBXScriptConnection },
	intro: boolean,
	course: RunCourse.Course?,
	bonus: number,
	bonusLabel: TextLabel?,
	nextTick: number,
	locked: { walk: boolean, jumpPower: number, jumpHeight: number }?,
	guide: { label: TextLabel, chevrons: { BasePart } }?,
	nextGhost: number,
	restoreUi: (() -> ())?,
	holdFor: number, -- seconds the wall waits after the cutscene (you were close to the biome's end)
	holdUntil: number,
}

local state: State? = nil

-- During your chase other players are hidden and you run straight through them (only on your screen: they still see
-- each other). Re-applied every half second, so players who join or respawn mid-chase are hidden too.
local ghosted: { [BasePart]: boolean } = {} -- part -> its CanCollide before
local ghostedHumanoids: { [Humanoid]: Enum.HumanoidDisplayDistanceType } = {}
local function ghostOthers()
	for _, p in Players:GetPlayers() do
		local c = p ~= player and p.Character
		if not c then
			continue
		end
		for _, d in c:GetDescendants() do
			if d:IsA("BasePart") then
				if ghosted[d] == nil then
					ghosted[d] = d.CanCollide
				end
				d.LocalTransparencyModifier = 1
				d.CanCollide = false
			elseif d:IsA("Humanoid") and ghostedHumanoids[d] == nil then
				ghostedHumanoids[d] = d.DisplayDistanceType
				d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Trail") then
				if d:GetAttribute("SAFD_GhostWas") == nil then
					d:SetAttribute("SAFD_GhostWas", d.Enabled)
				end
				d.Enabled = false
			end
		end
	end
end
local function unghostOthers()
	for part, collide in ghosted do
		if part.Parent then
			part.LocalTransparencyModifier = 0
			part.CanCollide = collide
		end
	end
	table.clear(ghosted)
	for h, kind in ghostedHumanoids do
		if h.Parent then
			h.DisplayDistanceType = kind
		end
	end
	table.clear(ghostedHumanoids)
	for _, p in Players:GetPlayers() do
		local c = p ~= player and p.Character
		if c then
			for _, d in c:GetDescendants() do
				local was = d:GetAttribute("SAFD_GhostWas")
				if was ~= nil then
					(d :: any).Enabled = was
					d:SetAttribute("SAFD_GhostWas", nil)
				end
			end
		end
	end
end
local flash: (text: string, color: Color3) -> ()

local function character(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return char, humanoid, hrp
end

local function refreshOverlap(s: State)
	s.overlap.FilterDescendantsInstances = s.obstacles
end

local function addObstacle(s: State, instance: Instance)
	table.insert(s.obstacles, instance)
	-- Keep the list bounded: drop the oldest spawned obstacle (not toppled scenery).
	if #s.obstacles > 70 then
		for i, old in s.obstacles do
			if old:IsDescendantOf(s.folder) then
				table.remove(s.obstacles, i)
				old:Destroy()
				break
			end
		end
	end
	refreshOverlap(s)
end

local function groundAt(s: State, position: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- skip particle volumes like the biomes' *_specks parts
	local ignore: { Instance } = { s.folder }
	local char = player.Character
	if char then
		table.insert(ignore, char)
	end
	for _, name in { "WildAnimals", "BaseAnimals" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -140, 0), params)
	return hit and hit.Position
end

-- (pooled: one emitter per colour on the disaster folder, moved to each puff and fired)
local dustPool: { [string]: { at: Attachment, emitter: ParticleEmitter } } = {}
local dustHolderOf: { [Instance]: Part } = setmetatable({}, { __mode = "k" }) :: any
local function dust(s: State, position: Vector3, color: Color3, amount: number)
	local holder = dustHolderOf[s.folder]
	if not holder then
		holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.Parent = s.folder
		dustHolderOf[s.folder] = holder
		table.clear(dustPool)
	end
	local key = color:ToHex()
	local entry = dustPool[key]
	if not entry or not entry.at.Parent then
		local at = Instance.new("Attachment")
		at.Parent = holder
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = SMOKE
		emitter.Color = ColorSequence.new(color)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) })
		emitter.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(1, 1.8)
		emitter.Speed = NumberRange.new(6, 16)
		emitter.SpreadAngle = Vector2.new(180, 40)
		emitter.Rate = 0
		emitter.Parent = at
		entry = { at = at, emitter = emitter }
		dustPool[key] = entry
	end
	entry.at.WorldPosition = position
	entry.emitter:Emit(math.min(math.ceil(amount * 0.45), 12))
end

-- Wall ----------------------------------------------------------------------------------------------------------

local function buildWall(s: State, biome, start: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "DisasterWall"
	local width = (s.trackMaxX - s.trackMinX) + 80
	local main = Instance.new("Part")
	main.Name = "Main"
	main.Size = Vector3.new(width, 90, WALL_THICKNESS)
	main.Material = biome.WallMaterial
	main.Color = biome.WallColor
	main.Anchored = true
	main.CanCollide = false
	main.CanQuery = false
	main.CanTouch = false
	main.CFrame = start
	main.Parent = model
	model.PrimaryPart = main

	-- Jagged chunks on the front face so it reads as a churning mass, not a flat slab.
	for _ = 1, 45 do
		local chunk = Instance.new("Part")
		local size = rng:NextNumber(6, 16)
		chunk.Size = Vector3.new(size, size * rng:NextNumber(0.6, 1.2), size)
		chunk.Material = biome.WallMaterial
		local h, sat, v = biome.WallColor:ToHSV()
		chunk.Color = Color3.fromHSV(h, sat, math.clamp(v * rng:NextNumber(0.75, 1.1), 0, 1))
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CFrame = start
			* CFrame.new(
				rng:NextNumber(-width / 2, width / 2),
				rng:NextNumber(-45, 50),
				-WALL_THICKNESS / 2 - rng:NextNumber(0, 5)
			)
			* CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3))
		chunk.Parent = model
	end

	local front = Instance.new("Part")
	front.Name = "Debris"
	front.Size = Vector3.new(width, 80, 1)
	front.Transparency = 1
	front.Anchored = true
	front.CanCollide = false
	front.CanQuery = false
	front.CanTouch = false
	front.CFrame = start * CFrame.new(0, 0, -WALL_THICKNESS / 2 - 3)
	front.Parent = model
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Color = ColorSequence.new(biome.WallColor)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 14) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(1.2, 2.2)
	emitter.Speed = NumberRange.new(10, 30)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Rate = 30
	emitter.Parent = front
	return model
end

-- Toppling scenery ----------------------------------------------------------------------------------------------

local function scanCandidates(s: State)
	local levels = Workspace:FindFirstChild("Levels")
	if not levels then
		return
	end
	local list = {}
	for b = 1, s.biome do
		local level = levels:FindFirstChild(Config.Biomes[b].Level)
		if level then
			for _, group in level:GetChildren() do
				if group:IsA("Model") then
					for _, item in group:GetChildren() do
						if (item:IsA("Model") or item:IsA("BasePart")) and not s.fallen[item] then
							table.insert(list, item)
						end
					end
				end
			end
		end
	end
	s.candidates = list
end

local function bounds(item: Instance): (CFrame?, Vector3?)
	if item:IsA("Model") then
		if not item:FindFirstChildWhichIsA("BasePart", true) then
			return nil, nil
		end
		return item:GetBoundingBox()
	elseif item:IsA("BasePart") then
		return item.CFrame, item.Size
	end
	return nil, nil
end

local function pivotOf(item: Instance): CFrame
	return (item :: any):GetPivot()
end

local function setPivot(item: Instance, cf: CFrame)
	(item :: any):PivotTo(cf)
end

local function topple(s: State, item: Instance, cf: CFrame, size: Vector3)
	local original = s.fallen[item] or pivotOf(item)
	s.fallen[item] = original
	s.shaking[item] = nil
	Sfx.at("WoodCrack", cf.Position, 1.3, rng:NextNumber(0.85, 1.15))
	-- Non-solid while knocked over, so it can never squash the player through the floor.
	for _, p in (if item:IsA("BasePart") then { item } else item:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide then
			p.CanCollide = false
			table.insert(s.uncollided, p)
		end
	end
	local bottom = cf.Position - Vector3.new(0, size.Y / 2, 0)
	local centerX = (s.trackMinX + s.trackMaxX) / 2
	local side = if math.abs(centerX - bottom.X) < 8
		then (if rng:NextNumber() < 0.5 then -1 else 1)
		else math.sign(centerX - bottom.X)
	-- Fall across the path; random lean towards/away from the base for variety.
	local dir = (Vector3.new(side, 0, 0) + s.toBase * rng:NextNumber(-0.4, 0.4)).Unit
	local axis = Vector3.new(0, 1, 0):Cross(dir).Unit
	local angle = math.rad(rng:NextNumber(72, 88))
	local pivotPoint = CFrame.new(bottom)
	local function apply(a: number)
		setPivot(item, pivotPoint * CFrame.fromAxisAngle(axis, a) * pivotPoint:Inverse() * original)
	end

	task.spawn(function()
		-- Wobble, then accelerate over like it's actually falling, then a small bounce.
		local t = 0
		while t < 0.2 do
			if state ~= s then
				return
			end
			apply(math.sin(t * 60) * math.rad(4))
			t += RunService.Heartbeat:Wait()
		end
		local duration = math.clamp(size.Y / 25, 0.5, 1.1)
		t = 0
		while t < duration do
			if state ~= s then
				return
			end
			local k = t / duration
			apply(angle * k * k)
			t += RunService.Heartbeat:Wait()
		end
		apply(angle)
		if state ~= s then
			return
		end
		s.shake = math.max(s.shake, math.clamp(size.Y / 20, 0.4, 1.2))
		dust(s, bottom + dir * size.Y * 0.6, Color3.fromRGB(150, 130, 110), 30)
		Sfx.at("HeavyThud", bottom + dir * size.Y * 0.6, 1.2)
		-- Only things that land on the path itself slow you; hillside scenery is pure spectacle.
		local landed = bottom + dir * size.Y * 0.6
		if landed.X > s.trackMinX and landed.X < s.trackMaxX then
			addObstacle(s, item)
		end
		t = 0
		while t < 0.25 do
			if state ~= s then
				return
			end
			apply(angle - math.sin(t / 0.25 * math.pi) * math.rad(6))
			t += RunService.Heartbeat:Wait()
		end
		apply(angle)
	end)
end

local function isEdgeScenery(s: State, center: Vector3): boolean
	return center.X < s.trackMinX + 18 or center.X > s.trackMaxX - 18
end

-- Scenery far ahead starts shaking; as you get close it leans and falls, one piece at a time, alternating
-- between the two hillsides. Things in the middle of the trail only rarely go (see trail topple).
local function advanceScenery(s: State, hrp: BasePart, now: number)
	local here = hrp.Position
	local shakingCount = 0
	for _ in s.shaking do
		shakingCount += 1
	end
	local best, bestScore, bestCF, bestSize = nil, math.huge, nil, nil
	local trailBest, trailScore, trailCF, trailSize = nil, math.huge, nil, nil
	for _, item in s.candidates do
		if (s.fallen[item] and not s.shaking[item]) or not item.Parent then
			continue
		end
		local cf, size = bounds(item)
		if not cf or not size or size.Y < 3 or math.max(size.X, size.Y, size.Z) > 70 then
			continue
		end
		local center = cf.Position
		if center.X < s.trackMinX - 60 or center.X > s.trackMaxX + 60 then
			continue
		end
		local offset = Vector3.new(center.X - here.X, 0, center.Z - here.Z)
		local ahead = offset:Dot(s.toBase)
		local edge = isEdgeScenery(s, center)
		if edge and ahead > 60 and ahead < 170 and not s.shaking[item] and shakingCount < 5 then
			-- Starts trembling well before you reach it.
			s.fallen[item] = s.fallen[item] or pivotOf(item)
			s.shaking[item] = {
				bottom = center - Vector3.new(0, size.Y / 2, 0),
				axis = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit,
				t0 = now,
				original = s.fallen[item],
			}
			shakingCount += 1
		end
		-- (only things well ahead of you fall, so you see them coming and have time to react)
		if ahead > 35 and ahead < 95 then
			local side = if center.X < (s.trackMinX + s.trackMaxX) / 2 then -1 else 1
			-- Alternate hillsides: prefer the side that didn't go last.
			local score = offset.Magnitude + (if side == s.lastSide then 25 else 0)
			if edge and score < bestScore then
				best, bestScore, bestCF, bestSize = item, score, cf, size
			elseif not edge and ahead > 45 and score < trailScore then
				trailBest, trailScore, trailCF, trailSize = item, score, cf, size
			end
		end
	end
	if now >= s.nextTopple and best and bestCF and bestSize then
		s.nextTopple = now + Config.ToppleInterval * rng:NextNumber(0.6, 1.4)
		s.lastSide = if bestCF.Position.X < (s.trackMinX + s.trackMaxX) / 2 then -1 else 1
		topple(s, best, bestCF, bestSize)
	end
	if now >= s.nextTrailTopple and trailBest and trailCF and trailSize then
		s.nextTrailTopple = now + Config.TrailToppleInterval * rng:NextNumber(0.8, 1.3)
		topple(s, trailBest, trailCF, trailSize)
	end
end

-- Trembling scenery: a growing wobble around its base.
local shakeFrame = false
local function shakeStep(s: State, now: number)
	-- (30 times a second is plenty for a tremble, and halves the cost of moving the shaking models)
	shakeFrame = not shakeFrame
	if not shakeFrame then
		return
	end
	for item, info in s.shaking do
		if not item.Parent then
			s.shaking[item] = nil
			continue
		end
		local age = now - info.t0
		local strength = math.rad(math.min(1 + age * 1.5, 5))
		local pivotPoint = CFrame.new(info.bottom)
		local angle = math.sin(age * 22) * strength
		setPivot(item, pivotPoint * CFrame.fromAxisAngle(info.axis, angle) * pivotPoint:Inverse() * info.original)
	end
end

-- Helpers --------------------------------------------------------------------------------------------------------

local function aheadPoint(s: State, hrp: BasePart, near: number, far: number): Vector3
	local p = hrp.Position + s.toBase * rng:NextNumber(near, far) + Vector3.new(rng:NextNumber(-24, 24), 0, 0)
	return Vector3.new(math.clamp(p.X, s.trackMinX + 3, s.trackMaxX - 3), p.Y, p.Z)
end

-- Side projectiles and rollers (see Hazards) -------------------------------------------------------------------

local function hazardContext(s: State): Hazards.Context
	return {
		folder = s.folder,
		trackMinX = s.trackMinX,
		trackMaxX = s.trackMaxX,
		toBase = s.toBase,
		alive = function()
			return state == s
		end,
		groundAt = function(p: Vector3)
			local g = groundAt(s, p)
			if g and MapInfo.isSafe(g) then
				return nil
			end
			return g
		end,
		addObstacle = function(instance: Instance)
			addObstacle(s, instance)
		end,
		shake = function(amount: number)
			s.shake = math.max(s.shake, amount)
		end,
		hit = function(_, push: Vector3)
			local _, humanoid, hrp = character()
			if not humanoid or not hrp or RunCourse.isRiding(s.course) then
				return
			end
			ChaseFx.play("Thud", 1, rng:NextNumber(0.9, 1.1))
			ChaseFx.kick(-8)
			Movement.slow(Config.HazardHitSlow)
			hrp.AssemblyLinearVelocity = push * 45 + Vector3.new(0, 38, 0)
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			s.shake = math.max(s.shake, 1.3)
			flash("OUCH!", Color3.fromRGB(255, 70, 70))
		end,
		dodged = function(mode: string)
			ChaseFx.pop(if mode == "Slide" then "NICE SLIDE!" else "NICE JUMP!", Color3.fromRGB(110, 255, 140))
			ChaseFx.play("Good", 0.8, 1.25)
			ChaseFx.kick(4)
		end,
	}
end

local function currentTheme(s: State, hrp: BasePart)
	return Hazards.themeFor(MapInfo.biomeAt(hrp.Position) or s.biome)
end

local function launchProjectile(s: State, hrp: BasePart, aimed: boolean)
	local theme = currentTheme(s, hrp)
	local target
	if aimed then
		-- Aim where the player will be when it lands.
		local v = hrp.AssemblyLinearVelocity
		target = hrp.Position + Vector3.new(v.X, 0, v.Z) * Config.TelegraphTime
	else
		target = aheadPoint(s, hrp, 25, 75)
	end
	target = Vector3.new(math.clamp(target.X, s.trackMinX + 4, s.trackMaxX - 4), target.Y, target.Z)
	Hazards.projectile(hazardContext(s), Hazards.pick(theme.Projectiles), target)
end

-- Background spectacle: debris tumbling down both hillsides, eruptions along the edges, and bigger collapses
-- behind you as the disaster consumes the route you just ran.
local function spectacle(s: State, hrp: BasePart, now: number)
	local theme = currentTheme(s, hrp)
	local biome = MapInfo.biomeAt(hrp.Position) or s.biome
	if now >= s.nextSpectacle then
		local range = Config.SpectacleInterval
		s.nextSpectacle = now + rng:NextNumber(range[1], range[2])
		-- Staggered sides: mostly alternate, sometimes the same side twice.
		local side = if rng:NextNumber() < 0.7 then -s.lastSide else s.lastSide
		local kinds = table.clone(theme.Projectiles)
		for _, k in theme.Rollers do
			table.insert(kinds, k)
		end
		local z = hrp.Position.Z + s.toBase.Z * rng:NextNumber(-20, 140)
		Hazards.tumble(hazardContext(s), Hazards.pick(kinds), side, z, s.groundY)
	end
	if now >= s.nextGeyser then
		s.nextGeyser = now + rng:NextNumber(1.1, 2.2)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = if side < 0 then s.trackMinX - rng:NextNumber(4, 25) else s.trackMaxX + rng:NextNumber(4, 25)
		local z = hrp.Position.Z + s.toBase.Z * rng:NextNumber(20, 110)
		local ground = groundAt(s, Vector3.new(x, s.groundY, z))
		Hazards.geyser(hazardContext(s), biome, ground or Vector3.new(x, s.groundY, z))
	end
	if now >= s.nextCollapse then
		s.nextCollapse = now + rng:NextNumber(0.5, 0.9)
		-- Behind the player: big dust clouds and debris where the route is being swallowed.
		local behindZ = hrp.Position.Z - s.toBase.Z * rng:NextNumber(15, 60)
		local ctx = hazardContext(s)
		for _, x in { s.trackMinX - 4, s.trackMaxX + 4, rng:NextNumber(s.trackMinX, s.trackMaxX) } do
			Hazards.dust(ctx, Vector3.new(x, s.groundY + 1, behindZ + rng:NextNumber(-8, 8)), 18)
		end
		if rng:NextNumber() < 0.4 then
			Hazards.tumble(
				ctx,
				Hazards.pick(theme.Projectiles),
				if rng:NextNumber() < 0.5 then -1 else 1,
				behindZ,
				s.groundY
			)
		end
	end
end

-- A wall across the whole path coming straight at you: slide under it / double jump over it (Hazards.barrier).
local function launchBarrier(s: State, hrp: BasePart, mode: string): boolean
	local theme = currentTheme(s, hrp)
	local biome = MapInfo.biomeAt(hrp.Position) or s.biome
	local ahead = hrp.Position + s.toBase * 95
	local ground = groundAt(s, ahead)
	local here = groundAt(s, hrp.Position + s.toBase * 15)
	if not ground or not here or MapInfo.isSafe(ground) or MapInfo.isSafe(here) then
		return false
	end
	Hazards.barrier(hazardContext(s), mode, biome, theme.Flyers or theme.Projectiles, ahead, here.Y)
	return true
end

local function launchRoller(s: State, hrp: BasePart)
	local theme = currentTheme(s, hrp)
	local ahead = hrp.Position + s.toBase * rng:NextNumber(10, 30)
	local ground = groundAt(s, ahead)
	if not ground or MapInfo.isSafe(ground) then
		return
	end
	Hazards.roller(hazardContext(s), Hazards.pick(theme.Rollers), ahead.Z, ground.Y)
end

-- UI ------------------------------------------------------------------------------------------------------------

local function textLabel(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.AnchorPoint = Vector2.new(0.5, 0)
	for k, v in props do
		(l :: any)[k] = v
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(30, 0, 0)
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function buildGui(): (ScreenGui, TextLabel, UIScale, TextLabel, TextLabel, { Frame })
	local gui = Instance.new("ScreenGui")
	gui.Name = "DisasterGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5

	-- Red edges: four gradient frames fading towards the centre.
	local edges = {}
	local specs = {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.2, 1), 0 }, -- left
		{ UDim2.fromScale(0.8, 0), UDim2.fromScale(0.2, 1), 180 }, -- right
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.2), 90 }, -- top
		{ UDim2.fromScale(0, 0.8), UDim2.fromScale(1, 0.2), 270 }, -- bottom
	}
	for _, spec in specs do
		local frame = Instance.new("Frame")
		frame.Position = spec[1]
		frame.Size = spec[2]
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		frame.BackgroundTransparency = 0.5
		frame.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[3]
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame
		table.insert(edges, frame)
	end

	local runLabel = textLabel(gui, {
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.42, 0.13),
		Text = "RUN!",
		TextColor3 = Color3.fromRGB(255, 35, 35),
	})
	local scale = Instance.new("UIScale")
	scale.Parent = runLabel
	local distanceLabel = textLabel(gui, {
		Position = UDim2.fromScale(0.5, 0.18),
		Size = UDim2.fromScale(0.35, 0.035),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 220, 220),
		Font = Enum.Font.GothamBold,
	})
	local slowLabel = textLabel(gui, {
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.25, 0.06),
		Text = "SLOWED!",
		TextColor3 = Color3.fromRGB(120, 180, 255),
		Visible = false,
	})
	return gui, runLabel, scale, distanceLabel, slowLabel, edges
end

function flash(text: string, color: Color3)
	local gui = HUD.gui()
	local l = textLabel(gui, {
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.4, 0.12),
		Text = text,
		TextColor3 = color,
	})
	local stroke = l:FindFirstChildOfClass("UIStroke") :: UIStroke
	task.delay(1.2, function()
		TweenService:Create(l, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		task.wait(0.55)
		l:Destroy()
	end)
end

-- Main loop -----------------------------------------------------------------------------------------------------

local function update(s: State, dt: number)
	local _, humanoid, hrp = character()
	if not humanoid or not hrp then
		return
	end
	local now = os.clock()

	-- Past the white line: the wall holds still. The chase ends only when the server takes your animals in
	-- (DisasterEnd). Ending it here on our own let a quick step over the line and back end the chase while you
	-- still carried them, so the next pickup started no disaster.
	if now >= s.nextGhost then
		s.nextGhost = now + 0.5
		ghostOthers()
	end
	if MapInfo.isSafe(hrp.Position) then
		return
	end
	if s.guide then
		local line = MapInfo.dangerLine()
		local left = (line - hrp.Position):Dot(s.toBase)
		s.guide.label.Text = `SAFE ZONE  {math.max(0, math.floor(left))}`
		local wave = (os.clock() * 1.5) % 1
		for i, c in s.guide.chevrons do
			local d = 14 + (i - 1 + wave) * 9
			local p = hrp.Position + s.toBase * d
			-- (the arrow's top face shows "^" pointing along its -Z: aim -Z towards the base)
			c.CFrame = CFrame.lookAt(
				Vector3.new(p.X, s.groundY + 0.15, p.Z),
				Vector3.new(p.X, s.groundY + 0.15, p.Z) + s.toBase
			)
		end
	end
	if s.intro then
		return -- (the cutscene is playing)
	end
	if s.course then
		RunCourse.update(s.course, hrp, humanoid, dt)
	end

	-- Safety net: never lose your animals to a fall through the map.
	if hrp.Position.Y < s.groundY - 12 then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = CFrame.new(hrp.Position.X, s.groundY + 5, hrp.Position.Z)
	end

	-- Wall advances and shoves.
	-- (formed far back at the end of the biome, it surges in until it's close, then keeps the biome's pace)
	local behind = (hrp.Position - s.wallCF.Position):Dot(s.toBase)
	local speed = s.speed + math.max(0, behind - Config.WallCatchUpGap) * Config.WallCatchUpRate
	if now < s.holdUntil then
		speed = 0
	end
	s.wallCF += s.toBase * speed * dt
	s.wall:PivotTo(s.wallCF)
	local frontPlane = s.wallCF.Position + s.toBase * (WALL_THICKNESS / 2 + 4)
	local gap = (hrp.Position - frontPlane):Dot(s.toBase)
	if gap < 1 and humanoid.Health > 0 then
		-- The wall caught you: you die on the spot (the server drops your carried animals when you die).
		s.shake = math.max(s.shake, 1.5)
		humanoid.Health = 0
		return
	end
	local intensity = math.clamp(1 - gap / 90, 0, 1)
	-- a heartbeat thump that quickens as it closes in
	if gap < 32 and now >= s.nextTick then
		s.nextTick = now + math.clamp(gap / 45, 0.2, 0.65)
		ChaseFx.play("Thud", 0.3, 1.7)
	end

	-- Hazards.
	if now - s.lastScan > 2 then
		s.lastScan = now
		scanCandidates(s)
	end
	advanceScenery(s, hrp, now)
	shakeStep(s, now)
	spectacle(s, hrp, now)
	-- Gameplay hazards: readable, spaced out, never more than a few warnings at once.
	if now >= s.nextProjectile and Hazards.activeTelegraphs < Config.MaxTelegraphs then
		local range = Config.ProjectileInterval
		s.nextProjectile = now + rng:NextNumber(range[1], range[2])
		launchProjectile(s, hrp, rng:NextNumber() < 0.2)
	end
	-- Things crossing the path take turns, one at a time: a wall to slide under, a roller from the side, a wall to
	-- double jump over, a roller...
	if now >= s.nextRoller and Hazards.activeRollers == 0 and Hazards.activeTelegraphs <= 3 then
		s.crossings += 1
		local step = s.crossings % 4
		if step == 1 or step == 3 then
			local range = Config.FlyerInterval
			s.nextRoller = now + rng:NextNumber(range[1], range[2])
			if not launchBarrier(s, hrp, if step == 1 then "Slide" else "Jump") then
				launchRoller(s, hrp)
			end
		else
			local range = Config.RollerInterval
			s.nextRoller = now + rng:NextNumber(range[1], range[2])
			launchRoller(s, hrp)
		end
	end
	if now >= s.nextBarrage and Hazards.activeTelegraphs <= 2 and Hazards.activeRollers == 0 then
		-- A volley across the path that always leaves one third of it open.
		s.nextBarrage = now + rng:NextNumber(5, 8)
		local width = s.trackMaxX - s.trackMinX
		local open = rng:NextInteger(1, 3)
		local z = hrp.Position.Z + s.toBase.Z * rng:NextNumber(22, 38)
		for lane = 1, 3 do
			if lane ~= open then
				local x = s.trackMinX + width * (lane - 0.5) / 3 + rng:NextNumber(-6, 6)
				task.delay(lane * 0.15, function()
					if state == s then
						Hazards.projectile(
							hazardContext(s),
							Hazards.pick(currentTheme(s, hrp).Projectiles),
							Vector3.new(x, s.groundY, z)
						)
					end
				end)
			end
		end
	end

	-- Obstructions slow the player.
	if #s.obstacles > 0 and not RunCourse.isRiding(s.course) then
		local touching = Workspace:GetPartBoundsInBox(hrp.CFrame, Vector3.new(3.5, 6.5, 3.5), s.overlap)
		if #touching > 0 then
			if not Movement.isSlowed() then
				s.shake = math.max(s.shake, 0.4)
			end
			Movement.slow(Config.SlowDuration)
		end
	end
	s.slowLabel.Visible = Movement.isSlowed()

	-- Juice: pulsing banner + edges, distance readout, camera shake.
	local pulse = (math.sin(now * (3 + intensity * 6) * math.pi) + 1) / 2
	s.runScale.Scale = 1 + pulse * 0.08 + intensity * 0.12
	for _, edge in s.edges do
		edge.BackgroundTransparency = math.clamp(0.7 - intensity * 0.45 - pulse * 0.2, 0.05, 1)
	end
	s.distanceLabel.Text = if gap < 12
		then "THE WALL IS RIGHT BEHIND YOU!"
		else `Wall: {math.floor(gap)} studs behind you`
	s.shake = math.max(0, s.shake - dt * 1.5)
	-- (gentler: "the shake is a bit too much", 2026-11-19)
	local amplitude = 0.02 + intensity * 0.12 + s.shake * 0.35
	humanoid.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * amplitude
end

function Disaster.start(biomeIndex: number)
	if state then
		return
	end
	local biome = Config.Biomes[biomeIndex]
	local _, humanoid, hrp = character()
	if not biome or not humanoid or not hrp then
		return
	end
	local toBase = MapInfo.toBase()
	local minV, maxV = MapInfo.bounds(biomeIndex)
	local folder = Instance.new("Folder")
	folder.Name = "LocalDisaster"
	folder.Parent = Workspace

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = {}

	local gui, runLabel, runScale, distanceLabel, slowLabel, edges = buildGui()
	gui.Enabled = false -- (hidden during the cutscene: "RUN!" only once it is over)
	gui.Parent = player:WaitForChild("PlayerGui")

	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "DisasterTint"
	tint.TintColor = Color3.fromRGB(255, 225, 220)
	tint.Contrast = 0.12
	tint.Saturation = 0.15
	tint.Parent = Lighting

	local camera = Workspace.CurrentCamera
	local s: State = {
		biome = biomeIndex,
		speed = biome.WallSpeed,
		toBase = toBase,
		trackMinX = minV and minV.X or hrp.Position.X - 60,
		trackMaxX = maxV and maxV.X or hrp.Position.X + 60,
		folder = folder,
		wall = nil :: any,
		wallCF = CFrame.identity,
		gui = gui,
		runLabel = runLabel,
		runScale = runScale,
		distanceLabel = distanceLabel,
		slowLabel = slowLabel,
		edges = edges,
		tint = tint,
		fov = camera.FieldOfView,
		fallen = {},
		uncollided = {},
		groundY = 0,
		candidates = {},
		lastScan = 0,
		obstacles = {},
		overlap = overlap,
		nextTopple = os.clock() + 0.5,
		shaking = {},
		nextTrailTopple = os.clock() + 4,
		nextSpectacle = os.clock(),
		nextGeyser = os.clock() + 1,
		nextCollapse = os.clock() + 0.5,
		lastSide = 1,
		nextProjectile = os.clock() + 0.6,
		nextRoller = os.clock() + 1.8,
		crossings = 0, -- the first crossing is a wall to slide under
		nextBarrage = os.clock() + 5,
		shake = 1,
		connections = {},
		intro = true,
		course = nil,
		bonus = 1,
		bonusLabel = nil,
		nextTick = 0,
		locked = nil,
		guide = nil,
		nextGhost = 0,
		-- the run home: only the chase's own screen (no money, speed, shop, index, hotbar ...)
		holdFor = 0,
		holdUntil = 0,
		restoreUi = ChaseFx.hideUi({ "DisasterGui", "SAFD_Rescue", "SAFD_Intro" }),
	}
	local groundY = (minV and maxV) and maxV.Y or hrp.Position.Y - 3
	s.groundY = groundY
	local centerX = (s.trackMinX + s.trackMaxX) / 2
	-- The disaster forms at the far end of the biome (user, 2026-11-19), but never closer behind you than
	-- Config.WallStartDistance (the legendaries live out there).
	local back = -toBase
	local farZ = if minV and maxV then (if back.Z > 0 then maxV.Z else minV.Z) else hrp.Position.Z
	-- (always this biome's own far end, even when you're close to it: it used to start further back, inside the next
	-- biome, which looked like the disaster was happening there. Close to the end, it waits a moment instead.)
	local wallZ = farZ
	local head = (hrp.Position.Z - farZ) * toBase.Z - WALL_THICKNESS / 2
	s.holdFor = math.max(0, Config.WallStartDistance - head) / s.speed
	local wallPos = Vector3.new(centerX, groundY + 40, wallZ)
	s.wallCF = CFrame.lookAt(wallPos, wallPos + toBase)
	s.wall = buildWall(s, biome, s.wallCF)
	MapStyle.applyAll(s.wall)
	s.wall:PivotTo(s.wallCF - Vector3.new(0, 100, 0)) -- still under the ground: the cutscene raises it
	s.wall.Parent = folder
	state = s

	-- the run bonus readout
	local bonusLabel = textLabel(gui, {
		Position = UDim2.fromScale(0.5, 0.225),
		Size = UDim2.fromScale(0.3, 0.05),
		Text = "RUN BONUS x1",
		TextColor3 = Color3.fromRGB(255, 230, 120),
	})
	s.bonusLabel = bonusLabel
	-- this run's course
	s.course = RunCourse.build(folder, hrp.Position, function(value: number)
		s.bonus = math.min(s.bonus * value, Config.RunMultiplierCap)
		bonusLabel.Text = "RUN BONUS x" .. s.bonus
		local sc = bonusLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		sc.Parent = bonusLabel
		sc.Scale = 1.5
		TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end)

	-- Where to go: a pillar of green light over the white line with the distance, and arrows on the ground ahead
	do
		local line = MapInfo.dangerLine()
		local mid = Vector3.new(centerX, groundY, line.Z)
		local pillar = Instance.new("Part")
		pillar.Name = "SafeBeacon"
		pillar.Anchored = true
		pillar.CanCollide = false
		pillar.CanQuery = false
		pillar.CanTouch = false
		pillar.CastShadow = false
		pillar.Material = Enum.Material.Neon
		pillar.Color = Color3.fromRGB(90, 255, 140)
		pillar.Transparency = 0.55
		pillar.Size = Vector3.new(8, 260, 8)
		pillar.CFrame = CFrame.new(mid + Vector3.new(0, 130, 0))
		pillar.Parent = folder
		local band = pillar:Clone()
		band.Name = "SafeLine"
		band.Size = Vector3.new(s.trackMaxX - s.trackMinX + 40, 0.3, 5)
		band.CFrame = CFrame.new(mid + Vector3.new(0, 0.3, 0))
		band.Transparency = 0.35
		band.Parent = folder
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(260, 70)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.StudsOffsetWorldSpace = Vector3.new(0, -100, 0)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(120, 255, 150)
		l.Text = "SAFE ZONE"
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Parent = l
		l.Parent = bb
		bb.Parent = pillar
		local chevrons = {}
		for i = 1, 3 do
			local c = Instance.new("Part")
			c.Name = "Arrow"
			c.Anchored = true
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			c.CastShadow = false
			c.Transparency = 1
			c.Size = Vector3.new(6, 0.2, 6)
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Top
			sg.LightInfluence = 0
			sg.AlwaysOnTop = false
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Font = Enum.Font.GothamBlack
			t.TextScaled = true
			t.Text = "^"
			t.TextColor3 = Color3.fromRGB(120, 255, 150)
			t.TextTransparency = 0.15 + i * 0.15
			t.Parent = sg
			sg.Parent = c
			c.Parent = folder
			table.insert(chevrons, c)
		end
		s.guide = { label = l, chevrons = chevrons }
	end

	Sfx.startChase()

	table.insert(
		s.connections,
		RunService.Heartbeat:Connect(function(dt)
			if state == s then
				update(s, dt)
			end
		end)
	)
	table.insert(
		s.connections,
		humanoid.Died:Connect(function()
			Disaster.stop(true)
		end)
	)
	-- a camera punch for your moves while you run
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		table.insert(
			s.connections,
			animator.AnimationPlayed:Connect(function(track)
				local id = track.Animation and track.Animation.AnimationId or ""
				if id == Config.DoubleJumpAnimation then
					ChaseFx.kick(7)
				elseif id == Config.SlideAnimation then
					ChaseFx.kick(5)
				end
			end)
		)
	end

	-- The cutscene: what you're running from.
	task.spawn(function()
		local cam = Workspace.CurrentCamera
		s.locked = { walk = true, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight }
		Movement.locked = true
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		ChaseFx.letterbox(true)
		ChaseFx.play("Rumble", 1, 0.8)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local wallTop = wallPos + Vector3.new(0, 10, 0)
		local shot =
			CFrame.lookAt(wallPos + toBase * 95 + Vector3.new(side * 30, -10, 0), wallTop - Vector3.new(0, 18, 0))
		ChaseFx.cameraTo(shot, 0.85, Enum.EasingStyle.Quad)
		if state ~= s then
			return
		end
		ChaseFx.play("Roar", 1.2, 0.45)
		ChaseFx.play("Impact", 1, 0.7)
		ChaseFx.pop(`THE {string.upper(biome.Name)} IS COLLAPSING!`, Color3.fromRGB(255, 80, 50), true)
		local t0 = os.clock()
		local RISE = 1.35
		while os.clock() - t0 < RISE and state == s do
			local k = (os.clock() - t0) / RISE
			local e = TweenService:GetValue(k, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			s.wall:PivotTo(s.wallCF - Vector3.new(0, 100 * (1 - e), 0))
			cam.CFrame = shot * CFrame.new(rng:NextNumber(-1, 1) * 0.3, rng:NextNumber(-1, 1) * 0.3, 0)
			if rng:NextNumber() < 0.25 then
				dust(
					s,
					Vector3.new(wallPos.X + rng:NextNumber(-60, 60), groundY + 2, wallZ + toBase.Z * 10),
					biome.WallColor,
					8
				)
			end
			task.wait()
		end
		if state ~= s then
			return
		end
		s.wall:PivotTo(s.wallCF)
		ChaseFx.play("Impact", 0.9, 0.55)
		-- swoop back behind you
		local _, _, root = character()
		if root then
			local behindYou =
				CFrame.lookAt(root.Position - toBase * 14 + Vector3.new(0, 6, 0), root.Position + toBase * 25)
			ChaseFx.play("Whoosh", 1, 0.7)
			ChaseFx.cameraTo(behindYou, 0.7, Enum.EasingStyle.Quad)
		end
		if state ~= s then
			return
		end
		ChaseFx.releaseCamera()
		ChaseFx.letterbox(false)
		Movement.locked = false
		humanoid.JumpPower = s.locked.jumpPower
		humanoid.JumpHeight = s.locked.jumpHeight
		s.locked = nil
		s.intro = false
		s.gui.Enabled = true
		s.holdUntil = os.clock() + s.holdFor
		local now = os.clock()
		s.nextProjectile = now + 1.2
		s.nextRoller = now + 2.6
		s.nextBarrage = now + 6
		ChaseFx.play("Boost", 1, 0.9)
		ChaseFx.kick(14)
	end)
end

function Disaster.stop(lost: boolean)
	local s = state
	if not s then
		return
	end
	state = nil
	for _, connection in s.connections do
		connection:Disconnect()
	end
	-- (stopped in the middle of the cutscene: give the camera and the controls back)
	if s.intro then
		ChaseFx.releaseCamera()
		ChaseFx.letterbox(false)
		local _, h = character()
		if s.locked and h then
			h.JumpPower = s.locked.jumpPower
			h.JumpHeight = s.locked.jumpHeight
		end
		Movement.locked = false
	end
	RunCourse.destroy(s.course)
	unghostOthers()
	if s.restoreUi then
		s.restoreUi()
	end
	-- Put the world back the way it was.
	for item, original in s.fallen do
		if item.Parent then
			setPivot(item, original)
		end
	end
	for _, p in s.uncollided do
		p.CanCollide = true
	end
	s.folder:Destroy()
	s.gui:Destroy()
	s.tint:Destroy()
	local _, humanoid = character()
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end
	Sfx.stopChase()
	if lost then
		flash("YOU WERE CAUGHT...", Color3.fromRGB(255, 80, 80))
	else
		flash("SAFE!", Color3.fromRGB(90, 255, 120))
	end
end

function Disaster.init()
	Net.event("DisasterStart").OnClientEvent:Connect(function(biomeIndex: number)
		Disaster.start(biomeIndex)
	end)
	Net.event("DisasterEnd").OnClientEvent:Connect(function(_, lost: boolean)
		Disaster.stop(lost)
	end)
	player.CharacterRemoving:Connect(function()
		Disaster.stop(true)
	end)
end

return Disaster
