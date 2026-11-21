-- The run home (user, 2026-11-20). No set path: you run home across the open biome however you like, and obstacles
-- rise out of the ground in front of you, right across the play area (no going round them). Obby style, and every
-- biome builds them from its own things (THEMES below: logs/fences/mud in the Meadow, ice in the Tundra, sandstone in
-- the Dunes, obsidian/lava in the Hellscape, pipes/barrels/acid in the Toxic Wasteland, candy in Candyland). The
-- shape says what to do, and the prompt at the top of the screen says it too:
--   * JUMP: a low piece (2.6 tall, bright top edge), a kill strip (mud, icy water, quicksand, lava, acid, chocolate:
--     touch it and you're slowed and put back), knee-high sweeper arms spinning round posts, stepping platforms over a
--     long kill strip.
--   * SLIDE (the prompt blinks): two big pieces stacked from 3.4 up to ~22, far over even a double jump, with the
--     opening underneath; or a big piece swinging on ropes at head height.
--   * DOUBLE JUMP (some runs more, some none): a very high wall (9.5).
--   * GO THROUGH THE GAP: two walls sliding side to side with a gap between them.
--   * DODGE: projectiles (Client/Hazards).
-- They come in short sets of 2-3, about a second apart, with a breather between sets.
-- The map's own trees topple as you pass them, and props on the hill steps tumble down into the valley (shake, creak
-- and dust over a red strip first); a tree that falls across your way is a log to jump. Every brick goes back exactly
-- where it was after the run.
-- LUCK badges (+1x green, +2x blue, +3x purple, +5x gold) add up (x1 + every one) and raise the odds of hatching a
-- rarer animal (Server/AnimalService). Some sit where it's risky: high over a barrier (double jump for it), off to one
-- side, or where a tree is about to land.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapInfo = require(Shared.MapInfo)
local MapStyle = require(Shared.MapStyle)
local Net = require(Shared.Net)

local ChaseFx = require(script.Parent.ChaseFx)
local Hazards = require(script.Parent.Hazards)
local Movement = require(script.Parent.Movement)
local Moves = require(script.Parent.Moves)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local rng = Random.new()

local RunCourse = {}
-- the LUCK counter on screen (Client/Disaster): a picked-up badge flies up into it
RunCourse.luckTarget = nil :: GuiObject?

local sceneryBetween: (zMin: number, zMax: number) -> { any }

local RING_COLORS = Config.RunRingColors
local LANE_W = 46 -- the width kept clear of big map rocks where you're heading (obstacles reach right across)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Each biome's look for the same few clear shapes (obstacles are unique to the biome, the action stays readable):
--   Round   pieces are cylinders (logs, pipes, candy canes) or blocks (ice, sandstone, obsidian)
--   Main / Accent / Lip   the piece, its bands / cracks / stripes, and the bright edge that marks a top or an opening
--   Liquid  the kill strip (touch it and you're sent back): mud, icy water, quicksand, lava, acid, chocolate
--   Wall    the very high wall (a double jump), Step the stepping platforms over a long kill strip
local THEMES = {
	{ -- Grassy Meadows: logs, fences, hay, mud
		Round = true,
		Main = rgb(125, 85, 50),
		Accent = rgb(80, 52, 30),
		Lip = rgb(255, 225, 40),
		Liquid = { Color = rgb(95, 68, 42) },
		Wall = { Style = "Planks", Color = rgb(160, 110, 65), Trim = rgb(245, 240, 230) },
		Step = { Round = true, Color = rgb(115, 78, 46), Top = rgb(210, 170, 115) },
		Hay = rgb(235, 200, 90),
	},
	{ -- Snowy Tundra: ice blocks, icy water, ice walls, ice floes
		Round = false,
		Glass = true,
		Main = rgb(140, 200, 245),
		Accent = rgb(255, 255, 255),
		Lip = rgb(255, 120, 30),
		Liquid = { Color = rgb(55, 135, 220), Glass = true },
		Wall = { Style = "Ice", Color = rgb(165, 215, 250), Trim = rgb(255, 255, 255) },
		Step = { Round = false, Color = rgb(225, 242, 255), Top = rgb(255, 255, 255) },
	},
	{ -- Sandy Dunes: sandstone slabs, quicksand, temple walls
		Round = false,
		Main = rgb(215, 180, 120),
		Accent = rgb(150, 112, 65),
		Lip = rgb(30, 150, 200),
		Liquid = { Color = rgb(200, 160, 95), Swirl = rgb(160, 120, 65) },
		Wall = { Style = "Temple", Color = rgb(200, 160, 100), Trim = rgb(255, 210, 60) },
		Step = { Round = false, Color = rgb(190, 150, 95), Top = rgb(230, 200, 140) },
	},
	{ -- Fiery Hellscape: obsidian beams with glowing seams, lava
		Round = false,
		Main = rgb(40, 28, 45),
		Accent = rgb(255, 100, 20),
		AccentNeon = true,
		Lip = rgb(255, 210, 70),
		Liquid = { Color = rgb(255, 100, 20), Neon = true },
		-- (the floor here is bright red already: danger is a deep dark red so it still stands out)
		Danger = rgb(105, 0, 12),
		DangerDark = rgb(40, 0, 6),
		Wall = { Style = "Lava", Color = rgb(50, 38, 45), Trim = rgb(255, 110, 20) },
		Step = { Round = false, Color = rgb(55, 40, 55), Top = rgb(255, 120, 30) },
	},
	{ -- Toxic Wasteland: pipes, barrels, acid
		Round = true,
		Main = rgb(115, 115, 110),
		Accent = rgb(120, 255, 70),
		AccentNeon = true,
		Lip = rgb(255, 220, 40),
		Liquid = { Color = rgb(110, 225, 55), Neon = true },
		Wall = { Style = "Barrels", Color = rgb(230, 200, 40), Trim = rgb(120, 255, 70) },
		Step = { Round = true, Color = rgb(230, 200, 40), Top = rgb(120, 255, 70) },
	},
	{ -- Candyland: candy canes, chocolate, cookies, frosting
		Round = true,
		Candy = true,
		Main = rgb(255, 255, 255),
		Accent = rgb(235, 40, 60),
		Lip = rgb(90, 230, 255),
		Liquid = { Color = rgb(105, 58, 32) },
		Wall = { Style = "Choco", Color = rgb(105, 58, 32), Trim = rgb(255, 130, 200) },
		Step = { Round = true, Color = rgb(205, 150, 80), Top = rgb(255, 240, 225) },
	},
}

type Ring = {
	pos: Vector3,
	value: number,
	model: Model,
	taken: boolean,
	anchor: BasePart,
	base: CFrame,
	bb: BillboardGui,
	scale: UIScale,
	rays: Frame?,
	phase: number,
}
-- an area that does something while you're in it: "Gate" (under a slide stack: "NICE!" when you slide through),
-- "Pad" (a bounce pad), "Pit" (over a strip: standing ON the strip slows you; a bridge after 2 misses)
type Zone = {
	kind: string,
	cf: CFrame,
	size: Vector3,
	next: number,
	done: boolean?,
	off: boolean?,
	fails: number?,
	back: Vector3?, -- (Pit: the near edge)
	bridge: ((x: number) -> ())?,
	strip: BasePart?, -- (Pit: the strip itself)
	strips: { [BasePart]: boolean }?, -- (Pit: a zigzag's legs)
}
-- something that moves each frame (falling trees...): returns true when it's done
type Ticker = (now: number, dt: number, progress: number) -> boolean
-- parts moved together: offsets from the first
type Group = { parts: { BasePart }, offs: { CFrame } }
-- what to do next, shown at the top of the screen as you get close (d: studs along the run)
type Cue = { d: number, text: string, color: Color3, blink: boolean? }
-- one of the map's trees (a cluster of touching bricks on the valley floor)
type Tree = {
	parts: { BasePart },
	x: number,
	z: number,
	bottom: number,
	height: number,
	radius: number, -- (of its trunk)
	trunk: number, -- (how tall the trunk is: the bit that's a log to jump once it's down)
	center: Vector3,
	size: Vector3,
}

export type Course = {
	root: Folder, -- everything of this run
	folder: Folder, -- (where the obstacle being built goes)
	rings: { Ring },
	zones: { Zone },
	hits: { BasePart }, -- solid obstacles: running into one slows you (landing on top doesn't)
	tickers: { Ticker },
	built: { { folder: Folder, dEnd: number } },
	spans: { { z0: number, z1: number } }, -- (where obstacles stand: projectiles keep off them)
	cues: { Cue },
	prompt: { gui: ScreenGui, label: TextLabel, scale: UIScale, text: string },
	moved: { [BasePart]: { cf: CFrame, collide: boolean } }, -- the map's trees we knocked over (put back after)
	usedTrees: { [Tree]: boolean },
	nextTree: number,
	nextTreeCheck: number,
	overlap: OverlapParams,
	nextBump: number,
	toBase: Vector3,
	origin: Vector3,
	g0: number,
	laneX: number, -- where you're heading at the obstacle being built (its ring)
	x0: number, -- the play area's sides: obstacles reach right across
	x1: number,
	speed: number,
	onRing: (value: number) -> (),
	hidden: { [BasePart]: boolean }, -- map scenery where obstacles stand: hidden for this run (its CanCollide before)
	nextD: number, -- (studs from the start towards the base) where the next obstacle goes
	stopD: number,
	setLeft: number, -- obstacles left in the current set
	lastAction: string?,
	finished: boolean,
	spacing: number,
	forceDouble: number, -- this run's share of double jumps (0: none this run)
	hrp: BasePart?, -- (you, for the moving walls)
	fell: number, -- (how many of the map's trees / props went over this run: the Studio log)
	testIndex: number?,
	slideBlocks: { BasePart },
	slideOpen: boolean,
	afterRing: number?, -- (a badge tier to put in the open space after the obstacle just built, well clear of it)
}

-- building blocks ------------------------------------------------------------------------------------------------

local function part(c: Course, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = c.folder
	return p
end

-- RED = SLOWS YOU (user, 2026-11-20). The only thing that slows you is landing in a strip (mud, water, lava...), so the
-- strips are red; obstacles are solid (they stop you, never slow you) and keep their biome colours.
local DANGER = Color3.fromRGB(235, 35, 35)
local DANGER_DARK = Color3.fromRGB(150, 15, 22)

-- the first couple of times something red slows you, it says so
local redTips = 0
local function slowedByRed(amount: number)
	Movement.slow(amount)
	if redTips < 2 then
		redTips += 1
		ChaseFx.pop("THE RED SLOWS YOU DOWN!", DANGER)
	end
end

-- a solid obstacle part: you can't go through it (jump it, slide under it, double jump it), but touching it never
-- slows you (user, 2026-11-20: "you should not be able to phase through them and touching them DOES NOT make you
-- slower")
local function solid(c: Course, props: { [string]: any }): Part
	local p = part(c, props)
	p.CanCollide = true
	p.CanQuery = true
	table.insert(c.hits, p)
	return p
end

local function deco(c: Course, props: { [string]: any }): Part
	local p = part(c, props)
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- a piece you get under by sliding: solid, except while you slide (RunCourse.update switches it)
local function slideBlock(c: Course, p: BasePart)
	p.CanCollide = true
	table.insert(c.slideBlocks, p)
end

local function zone(c: Course, kind: string, cf: CFrame, size: Vector3): Zone
	local z: Zone = { kind = kind, cf = cf, size = size, next = 0 }
	table.insert(c.zones, z)
	return z
end

-- a badge's value: it MULTIPLIES your luck (user 2026-11-21: "x3 then x3 is x9"). Tier 1 mostly x2, tier 2 x3 / x4,
-- tier 3 (risky ones) x4 or the golden x5
local function luck(tier: number): number
	local r = rng:NextNumber()
	if tier <= 1 then
		return if r < 0.75 then 2 elseif r < 0.95 then 3 else 4
	elseif tier == 2 then
		return if r < 0.5 then 3 elseif r < 0.9 then 4 else 5
	end
	return if r < 0.55 then 4 else 5
end

-- x positions every `step` studs within `reach` of where you're heading (details only near you: cheap)
local function nearLane(c: Course, step: number, reach: number): { number }
	local out = {}
	local x = math.max(c.x0 + 1, c.laneX - reach)
	local x1 = math.min(c.x1 - 1, c.laneX + reach)
	while x <= x1 do
		table.insert(out, x)
		x += step
	end
	return out
end

local function group(parts: { BasePart }): Group
	local base = parts[1].CFrame
	local offs = table.create(#parts)
	for i, p in parts do
		offs[i] = base:ToObjectSpace(p.CFrame)
	end
	return { parts = parts, offs = offs }
end

-- (queue a group's move at cf: all of a frame's moves go in one BulkMoveTo)
local function queue(P: { BasePart }, C: { CFrame }, gr: Group, cf: CFrame)
	for i, p in gr.parts do
		table.insert(P, p)
		table.insert(C, cf * gr.offs[i])
	end
end

local function flush(P: { BasePart }, C: { CFrame })
	if #P > 0 then
		Workspace:BulkMoveTo(P, C, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- a blinking red strip on the ground: something is about to land here
local function warnStrip(c: Course, cf: CFrame, size: Vector3): Part
	local p = deco(c, {
		Name = "Warning",
		Size = size,
		CFrame = cf,
		Material = Enum.Material.Neon,
		Color = rgb(255, 40, 40),
		Transparency = 0.3,
	})
	TweenService:Create(
		p,
		TweenInfo.new(0.22, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.8 }
	):Play()
	return p
end

-- a puff of dust (a landing, a crash)
local function puff(c: Course, pos: Vector3, color: Color3, amount: number)
	local a = deco(c, { Name = "Dust", Transparency = 1, Size = Vector3.new(10, 1, 4), CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.7, 1.2)
	e.Speed = NumberRange.new(6, 14)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Rate = 0
	e.Parent = a
	e:Emit(amount)
	task.delay(1.5, function()
		a:Destroy()
	end)
end

local function refreshHits(c: Course)
	c.overlap.FilterDescendantsInstances = c.hits
end

-- LUCK badges ----------------------------------------------------------------------------------------------------
-- A chunky round badge (a BillboardGui only: nothing glowing in the world over it): a bright gradient circle, a thick
-- dark outline and a thin white inner ring, the number huge in the middle. Bigger values: a bigger badge with a soft
-- halo (and for x4 / x5 slowly turning rays) BEHIND the circle, never over the number. It bobs gently; picked up, it
-- pops (scale up + fade) with a chime.
local BADGE = {
	[2] = { px = 104, top = rgb(140, 255, 120), bottom = rgb(30, 175, 60), rays = 0 },
	[3] = { px = 116, top = rgb(130, 215, 255), bottom = rgb(25, 105, 230), rays = 0 },
	[4] = { px = 130, top = rgb(225, 160, 255), bottom = rgb(130, 50, 220), rays = 4 },
	[5] = { px = 148, top = rgb(255, 245, 140), bottom = rgb(255, 160, 10), rays = 6 },
}
local OUTLINE = rgb(35, 25, 45)
local PICKUP_RADIUS = 4.6 -- (studs from your middle: a ring over a barrier needs the jump)

local function circle(parent: Instance, size: number, color: Color3, transparency: number, z: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(size, size)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	f.Parent = parent
	return f
end

-- the biggest badge each biome can have (progression: Meadow only x2, the far biomes the big ones; user 2026-11-20)
local BADGE_CAP = { 2, 3, 4, 4, 5, 5 }
-- badges only over the open valley floor, never in a build or on the hills (user 2026-11-22: some were inside the
-- Hellscape lava islands, some up on the side hills)
local BADGE_X = { -69, 53 } -- (the valley floor is x -75.5 .. 59.5 in every biome)
local badgeParams = OverlapParams.new()
badgeParams.FilterType = Enum.RaycastFilterType.Include
local function badgeBlocked(pos: Vector3): boolean
	if #badgeParams.FilterDescendantsInstances == 0 then
		local roots = {}
		for _, name in { "Levels", "Non_functional_spawn_assets", "SAFD_Boundaries" } do
			local r = Workspace:FindFirstChild(name)
			if r then
				table.insert(roots, r)
			end
		end
		badgeParams.FilterDescendantsInstances = roots
	end
	for _, p in Workspace:GetPartBoundsInRadius(pos, 4, badgeParams) do
		-- (the floor under it doesn't count, only something standing there)
		if p.CanCollide and p.Transparency < 1 and p.Position.Y + p.Size.Y / 2 > pos.Y - 2.5 then
			return true
		end
	end
	return false
end
local function ring(c: Course, pos: Vector3, value: number)
	-- (no badges past the white line: the safe side; user 2026-11-20)
	if (pos - MapInfo.dangerLine()):Dot(c.toBase) > -10 then
		return
	end
	pos = Vector3.new(math.clamp(pos.X, BADGE_X[1], BADGE_X[2]), pos.Y, pos.Z)
	if badgeBlocked(pos) then
		-- slide it towards the middle of the valley until it's in the open, or skip it
		local found = false
		for k = 1, 6 do
			local x = pos.X + (if pos.X > -8 then -1 else 1) * k * 7
			local p2 = Vector3.new(math.clamp(x, BADGE_X[1], BADGE_X[2]), pos.Y, pos.Z)
			if not badgeBlocked(p2) then
				pos = p2
				found = true
				break
			end
		end
		if not found then
			return
		end
	end
	local cap = BADGE_CAP[MapInfo.biomeAt(Vector3.new(-8, 1, pos.Z)) or 6] or 5
	value = math.clamp(value, 2, cap)
	local st = BADGE[value] or BADGE[2]
	local color = RING_COLORS[value] or st.bottom
	local m = Instance.new("Model")
	m.Name = "LuckBadge_x" .. value
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = m
	local bb = Instance.new("BillboardGui")
	-- (room round the circle for the halo; AlwaysOnTop stays off: on top, billboards never drew in this place)
	bb.Size = UDim2.fromOffset(st.px * 1.5, st.px * 1.5)
	bb.MaxDistance = 220
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = bb
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	-- behind: the halo and the rays
	if value >= 3 then
		circle(holder, 0.98, color, 0.72, 1)
	end
	local rays
	if st.rays > 0 then
		rays = Instance.new("Frame")
		rays.BackgroundTransparency = 1
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromScale(1, 1)
		rays.ZIndex = 1
		for i = 0, st.rays / 2 - 1 do
			local ray = Instance.new("Frame")
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.fromScale(0.98, 0.12)
			ray.Rotation = i * 180 / (st.rays / 2)
			ray.BackgroundColor3 = st.top
			ray.BackgroundTransparency = 0.45
			ray.BorderSizePixel = 0
			ray.ZIndex = 1
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(1, 0)
			rc.Parent = ray
			ray.Parent = rays
		end
		rays.Parent = holder
	end
	-- the badge
	local disc = circle(holder, 0.66, Color3.new(1, 1, 1), 0, 2)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(st.top, st.bottom)
	grad.Rotation = 90
	grad.Parent = disc
	local outline = Instance.new("UIStroke")
	outline.Thickness = 7
	outline.Color = OUTLINE
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = disc
	local inner = circle(disc, 0.86, Color3.new(1, 1, 1), 1, 3)
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Thickness = 2.5
	innerStroke.Color = Color3.new(1, 1, 1)
	innerStroke.Transparency = 0.15
	innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerStroke.Parent = inner
	-- a toy-like shine, top left (well clear of the number)
	local shine = circle(disc, 0.22, Color3.new(1, 1, 1), 0.45, 3)
	shine.Position = UDim2.fromScale(0.3, 0.24)
	shine.Size = UDim2.fromScale(0.2, 0.12)
	local num = Instance.new("TextLabel")
	num.AnchorPoint = Vector2.new(0.5, 0.5)
	num.Position = UDim2.fromScale(0.5, 0.52)
	num.Size = UDim2.fromScale(0.82, 0.62)
	num.BackgroundTransparency = 1
	num.Font = Enum.Font.FredokaOne
	num.TextScaled = true
	num.Text = "x" .. value
	num.TextColor3 = Color3.new(1, 1, 1)
	num.ZIndex = 4
	local ns = Instance.new("UIStroke")
	ns.Thickness = 4
	ns.Color = OUTLINE
	ns.Parent = num
	num.Parent = disc
	bb.Parent = anchor
	m.Parent = c.folder
	table.insert(c.rings, {
		pos = pos,
		value = value,
		model = m,
		taken = false,
		anchor = anchor,
		base = anchor.CFrame,
		bb = bb,
		scale = scale,
		rays = rays,
		phase = rng:NextNumber(0, 6),
	})
end

-- a picked-up badge, drawn on the screen where it was, rises and flies up into the LUCK counter (user, 2026-11-20:
-- "you can visibly see you got the multiplier as it rises up to the top of your screen"); when it lands the counter
-- bumps, sparkles burst out of it and a rising three-note chime plays
local flyToCounter: (c: Course, r: Ring) -> ()

local function screenBadge(parent: Instance, value: number, px: number): (Frame, UIScale)
	local st = BADGE[value] or BADGE[2]
	local f = Instance.new("Frame")
	f.Name = "FlyingLuck"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(px, px)
	f.BackgroundTransparency = 1
	f.ZIndex = 20
	local sc = Instance.new("UIScale")
	sc.Parent = f
	local disc = circle(f, 1, Color3.new(1, 1, 1), 0, 21)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(st.top, st.bottom)
	grad.Rotation = 90
	grad.Parent = disc
	local outline = Instance.new("UIStroke")
	outline.Thickness = 5
	outline.Color = OUTLINE
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = disc
	local num = Instance.new("TextLabel")
	num.AnchorPoint = Vector2.new(0.5, 0.5)
	num.Position = UDim2.fromScale(0.5, 0.52)
	num.Size = UDim2.fromScale(0.82, 0.62)
	num.BackgroundTransparency = 1
	num.Font = Enum.Font.FredokaOne
	num.TextScaled = true
	num.Text = "x" .. value
	num.TextColor3 = Color3.new(1, 1, 1)
	num.ZIndex = 22
	local ns = Instance.new("UIStroke")
	ns.Thickness = 3
	ns.Color = OUTLINE
	ns.Parent = num
	num.Parent = disc
	f.Parent = parent
	return f, sc
end

local function sparkle(parent: Instance, at: Vector2, color: Color3, n: number, dist: number)
	for i = 1, n do
		local d = circle(parent, 0, color, 0, 19)
		d.Position = UDim2.fromOffset(at.X, at.Y)
		d.Size = UDim2.fromOffset(12, 12)
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local to = at + Vector2.new(math.cos(a), math.sin(a)) * dist * rng:NextNumber(0.7, 1.2)
		local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(
			d,
			info,
			{ Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(3, 3), BackgroundTransparency = 1 }
		):Play()
		task.delay(0.5, function()
			d:Destroy()
		end)
	end
end

-- the chimes (user 2026-11-21: "x2 will be 2 fast chimes, x5 fast 5 chimes"): a glockenspiel note climbing a happy
-- scale, one per point of luck, then a sparkly bling (the hatch's own sounds, Client/Hatch, checked to load)
local CHIME = "rbxassetid://72644163309528"
local BLING = "rbxassetid://4612374036"
local CHIME_SCALE = { 0, 4, 7, 12, 16, 19, 24 }
local soundBank: { [string]: Sound } = {}
local function playSound(id: string, volume: number, pitch: number)
	local base = soundBank[id]
	if not base then
		base = Instance.new("Sound")
		base.SoundId = id
		base.Parent = game:GetService("SoundService")
		soundBank[id] = base
	end
	local snd = base:Clone()
	snd.Volume = volume * 2 * (Players.LocalPlayer:GetAttribute("SfxVolume") or 0.5)
	snd.PlaybackSpeed = pitch
	snd.Parent = base.Parent
	snd:Play()
	snd.Ended:Once(function()
		snd:Destroy()
	end)
end
function RunCourse.preloadSounds()
	for _, id in { CHIME, BLING } do
		playSound(id, 0, 1)
	end
end

local function bump(target: GuiObject, to: number)
	local sc = target:FindFirstChildOfClass("UIScale")
	if not sc then
		local made = Instance.new("UIScale")
		made.Parent = target
		sc = made
	end
	(sc :: UIScale).Scale = to
	TweenService:Create(sc :: UIScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- the badge you picked up bounces in just under the LUCK counter (top right: never over the way ahead), chimes once
-- per point, then hops into the counter
flyToCounter = function(c: Course, r: Ring)
	local value = r.value
	local st = BADGE[value] or BADGE[2]
	local gui = c.prompt.gui
	local cam = Workspace.CurrentCamera
	local target = RunCourse.luckTarget
	local chimes = math.clamp(value, 1, 7)
	if not gui.Parent or not cam or not target or not target.Parent then
		c.onRing(value)
		for i = 1, chimes do
			task.delay((i - 1) * 0.075, playSound, CHIME, 0.5, 2 ^ (CHIME_SCALE[i] / 12) * 0.5)
		end
		return
	end
	local view = cam.ViewportSize
	local tg = target:FindFirstAncestorOfClass("ScreenGui")
	local inset = if tg and not tg.IgnoreGuiInset then GuiService:GetGuiInset() else Vector2.zero
	local to = target.AbsolutePosition + target.AbsoluteSize / 2 + inset
	local px = math.floor(view.Y * 0.085)
	local home = Vector2.new(
		math.clamp(to.X, px, view.X - px),
		math.min(to.Y + target.AbsoluteSize.Y * 0.5 + px * 0.8, view.Y * 0.4)
	)
	local f, sc = screenBadge(gui, value, px)
	f.Position = UDim2.fromOffset(home.X, home.Y - px * 0.9)
	sc.Scale = 0.2
	-- drops in with a bounce
	TweenService:Create(f, TweenInfo.new(0.32, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(home.X, home.Y),
	}):Play()
	TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 })
		:Play()
	-- one fast chime per point of luck: the badge and the counter bump on each
	for i = 1, chimes do
		task.delay(0.08 + (i - 1) * 0.075, function()
			playSound(CHIME, 0.45 + i * 0.04, 2 ^ (CHIME_SCALE[i] / 12) * 0.5)
			if f.Parent then
				sc.Scale = 1.3
				TweenService:Create(sc, TweenInfo.new(0.07), { Scale = 1.05 }):Play()
				f.Rotation = if i % 2 == 0 then 8 else -8
				sparkle(gui, home, st.top, 3, px * 0.7)
			end
			bump(target, 1.12)
		end)
	end
	local done = 0.08 + chimes * 0.075 + 0.12
	task.delay(done, function()
		if f.Parent then
			f.Rotation = 0
			TweenService:Create(f, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(to.X, to.Y),
			}):Play()
			TweenService
				:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.3 })
				:Play()
		end
		task.delay(0.18, function()
			if f.Parent then
				f:Destroy()
			end
			sparkle(gui, to, st.top, 8 + value * 2, px * 0.8)
			sparkle(gui, to, Color3.new(1, 1, 1), 5, px * 0.5)
			c.onRing(value)
			playSound(BLING, 0.55 + value * 0.05, 1 + value * 0.03)
			if value >= 5 then
				ChaseFx.play("Confetti", 0.8, 1.1)
			end
		end)
	end)
end

local function collect(c: Course, r: Ring)
	r.taken = true
	-- pop: a quick swell and fade
	local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(r.scale, info, { Scale = 1.7 }):Play()
	for _, d in r.bb:GetDescendants() do
		if d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	-- a small burst of sparkles
	local st = BADGE[r.value] or BADGE[2]
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(st.top, st.bottom)
	e.LightEmission = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.3, 0.6)
	e.Speed = NumberRange.new(8, 16)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = r.anchor
	e:Emit(10 + r.value * 3)
	task.delay(0.7, function()
		r.model:Destroy()
	end)
	ChaseFx.play("Pop", 1, 0.95 + r.value * 0.1)
	ChaseFx.play("Boost", 0.35, 1.3)
	ChaseFx.kick(2 + r.value * 0.5)
	Net.event("RunRing"):FireServer(r.value)
	flyToCounter(c, r)
end

-- the screen prompt ----------------------------------------------------------------------------------------------

local PROMPT_COLORS = {
	JUMP = Color3.fromRGB(255, 230, 90),
	SLIDE = Color3.fromRGB(120, 220, 255),
	DOUBLE = Color3.fromRGB(255, 130, 230),
	EITHER = Color3.fromRGB(170, 255, 120),
	BOOST = Color3.fromRGB(80, 230, 255),
}

-- d along the run of a world z
local function dOf(c: Course, z: number): number
	return (z - c.origin.Z) * c.toBase.Z
end

local function cue(c: Course, z: number, text: string, color: Color3, blink: boolean?)
	local d = dOf(c, z)
	local i = #c.cues
	while i > 0 and c.cues[i].d > d do
		i -= 1
	end
	table.insert(c.cues, i + 1, { d = d, text = text, color = color, blink = blink })
end

local function biomeAt(z: number): number
	return MapInfo.biomeAt(Vector3.new(-8, 1, z)) or 1
end

local function look(z: number)
	return THEMES[biomeAt(z)] or THEMES[1]
end

local function zAt(c: Course, origin: Vector3, d: number): number
	return origin.Z + c.toBase.Z * d
end

local function span(c: Course): (number, number)
	return (c.x0 + c.x1) / 2, c.x1 - c.x0
end

-- obstacles ------------------------------------------------------------------------------------------------------
-- Each takes the z it starts at and the ground height there, and returns how long it is (studs towards the base). They
-- reach right across the play area (c.x0 .. c.x1); details are only drawn near where you're heading. Heights against
-- Client/Moves: one jump lifts your feet ~6.4 (JumpPower 50), a double jump pressed near the top ~14; a slide keeps
-- you under 3.4.

-- a moving obstacle part (the sliding walls): solid
local function mover(c: Course, props: { [string]: any }): Part
	local p = part(c, props)
	p.CanCollide = true
	table.insert(c.hits, p)
	return p
end

-- x positions every `step` studs right across (offset by phase 0..1 of a step)
local function across(c: Course, step: number, phase: number?): { number }
	local out = {}
	local x = c.x0 + step * (phase or 0.5)
	while x < c.x1 do
		table.insert(out, x)
		x += step
	end
	return out
end

local function mat(p: BasePart, glass: boolean?, neon: boolean?)
	if neon then
		p.Material = Enum.Material.Neon
	elseif glass then
		p.Material = Enum.Material.Glass
		p.Transparency = 0.12
	end
end

-- a long piece right across at height y (its centre), h tall: a cylinder (diameter h) or a block (h x depth), with
-- bands / cracks / candy stripes near you
local function beam(c: Course, o, y: number, z: number, h: number, depth: number, name: string, hit: boolean): BasePart
	local cx, w = span(c)
	local p = (if hit then solid else deco)(c, {
		Name = name,
		Shape = if o.Round then Enum.PartType.Cylinder else Enum.PartType.Block,
		Size = if o.Round then Vector3.new(w, h, h) else Vector3.new(w, h, depth),
		CFrame = CFrame.new(cx, y, z),
		Color = o.Main,
	})
	mat(p, o.Glass)
	if o.Round then
		local step = if o.Candy then 3.4 else 8
		for _, x in nearLane(c, step, 80) do
			local band = deco(c, {
				Name = "Band",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(if o.Candy then 1.7 else 0.8, h + 0.15, h + 0.15),
				CFrame = CFrame.new(x, y, z),
				Color = o.Accent,
			})
			mat(band, false, o.AccentNeon)
		end
	else
		for _, x in nearLane(c, 7, 80) do
			local line = deco(c, {
				Name = "Seam",
				Size = Vector3.new(0.5, h - 0.4, depth + 0.12),
				CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(12)),
				Color = o.Accent,
			})
			mat(line, false, o.AccentNeon)
		end
	end
	return p
end

-- the kill strip: liquid right across (touch it and you're slowed and put back on the near edge; a bridge after two
-- misses). zoneTop: how high above the floor your middle counts as in it (lower over stepping platforms).
local function strip(c: Course, o, z: number, g: number, len: number, zoneTop: number): number
	local cx, w = span(c)
	local mid = z + c.toBase.Z * len / 2
	local liq = o.Liquid
	local stripPart = deco(c, {
		Name = "KillStrip",
		Size = Vector3.new(w, 0.4, len),
		CFrame = CFrame.new(cx, g + 0.12, mid),
		Color = o.Danger or DANGER,
	})
	local _ = liq
	for _, x in nearLane(c, 9, 60) do
		deco(c, {
			Name = "Swirl",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 3, 3),
			CFrame = CFrame.new(x, g + 0.34, mid + rng:NextNumber(-len / 3, len / 3))
				* CFrame.Angles(0, 0, math.pi / 2),
			Color = o.DangerDark or DANGER_DARK,
		})
	end
	for _, e in { -0.6, len + 0.6 } do
		deco(c, {
			Name = "Lip",
			Size = Vector3.new(w, 0.45, 1.2),
			CFrame = CFrame.new(cx, g + 0.2, z + c.toBase.Z * e),
			Color = o.Lip,
		})
	end
	local folder = c.folder
	-- (the zone only says you're over the strip; what counts is what's right under your feet: RunCourse.update)
	stripPart.CanQuery = true
	local _ = zoneTop
	local zn = zone(c, "Pit", CFrame.new(cx, g + 6, mid), Vector3.new(w, 12, len))
	zn.strip = stripPart
	zn.fails = 0
	zn.back = Vector3.new(0, g + 3.3, z - c.toBase.Z * 4)
	zn.bridge = function(x: number)
		local plank = Instance.new("Part")
		plank.Name = "Bridge"
		plank.Anchored = true
		plank.CanCollide = false
		plank.CanQuery = false
		plank.CanTouch = false
		plank.Size = Vector3.new(14, 0.6, len + 2)
		plank.CFrame = CFrame.new(x, g + 0.5, mid)
		plank.Color = rgb(150, 100, 60)
		MapStyle.apply(plank)
		plank.Parent = folder
	end
	return len + 1.2
end

-- a badge where you only get it with the move (or a risky one)
local function moveRing(c: Course, g: number, z: number, high: number, risky: number)
	local dice = rng:NextNumber()
	if dice < 0.4 then
		ring(c, Vector3.new(c.laneX, g + high, z), luck(1))
	elseif dice < 0.55 then
		ring(c, Vector3.new(c.laneX + rng:NextNumber(-6, 6), g + risky, z), luck(3))
	end
end

-- JUMP: a low piece right across (a log, an ice block, a sandstone slab, an obsidian beam, a pipe, a candy cane:
-- 2.6 tall, a bright top edge) or a kill strip about 0.3 s of running wide
local function jump(c: Course, z: number, g: number): number
	local o = look(z)
	cue(c, z, "JUMP!", PROMPT_COLORS.JUMP)
	local used
	if rng:NextNumber() < 0.55 then
		local cx, w = span(c)
		local h, depth = 2.6, 2.4
		beam(c, o, g + h / 2, z + c.toBase.Z * depth / 2, h, depth, "Bar", true)
		deco(c, {
			Name = "TopEdge",
			Size = Vector3.new(w, 0.3, 0.9),
			CFrame = CFrame.new(cx, g + h + 0.1, z + c.toBase.Z * depth / 2),
			Color = o.Lip,
		})
		used = depth
	else
		used = strip(c, o, z, g, math.clamp(c.speed * 0.3, 6, 14), 4.6)
	end
	moveRing(c, g, z + c.toBase.Z * used / 2, 8.6, 16.5) -- (above it: you get it with the jump)
	return used
end

-- FORCED SLIDE: two big pieces stacked (9 each: two giant logs, ice blocks, sandstone slabs, obsidian beams, pipes,
-- candy canes) from 3.4 up to ~22: far over even a double jump (~14), with the empty opening under them and a bright
-- edge along its top. The zone: sliding you're through, anything else pushes you back. The prompt blinks "SLIDE!".
local function slide(c: Course, z: number, g: number): number
	local o = look(z)
	cue(c, z, "SLIDE!", PROMPT_COLORS.SLIDE, true)
	local cx, w = span(c)
	local bottom, size = g + 3.4, 9
	local depth = if o.Round then size else 4
	local mid = z + c.toBase.Z * depth / 2
	slideBlock(c, beam(c, o, bottom + size / 2, mid, size, depth, "Stack", false))
	slideBlock(c, beam(c, o, bottom + size * 1.5, mid, size, depth, "Stack", false))
	deco(c, {
		Name = "OpeningEdge",
		Size = Vector3.new(w, 0.45, 1),
		CFrame = CFrame.new(cx, bottom - 0.05, z - c.toBase.Z * 0.2),
		Color = o.Lip,
	})
	-- (posts at the far ends only: the opening stays clear)
	for _, px in { c.x0 + 1, c.x1 - 1 } do
		deco(c, {
			Name = "Post",
			Size = Vector3.new(1.4, bottom + size * 2 - g, 1.4),
			CFrame = CFrame.new(px, (g + bottom + size * 2) / 2, mid),
			Color = o.Accent,
		})
	end
	zone(c, "Gate", CFrame.new(cx, g + 13, mid), Vector3.new(w, 26, depth + 1.5))
	local dice = rng:NextNumber()
	if dice < 0.6 then
		c.afterRing = if dice < 0.45 then 1 else 2
	end
	return depth
end

-- SLIDE TUNNEL (slide only, user 2026-11-22: "more obstacles you can only get through by sliding"): a run of slide
-- stacks one after another, 3.4 up to ~22 like SLIDE!, about half a second of sliding under them
local function tunnel(c: Course, z: number, g: number): number
	local o = look(z)
	cue(c, z, "SLIDE!", PROMPT_COLORS.SLIDE, true)
	local cx, w = span(c)
	local bottom, size = g + 3.4, 9
	local piece = if o.Round then size else 4
	local count = math.clamp(math.floor(c.speed * 0.45 / piece), 2, 5)
	local depth = piece * count
	for i = 0, count - 1 do
		local mid = z + c.toBase.Z * (piece * i + piece / 2)
		slideBlock(c, beam(c, o, bottom + size / 2, mid, size, piece, "Stack", false))
		slideBlock(c, beam(c, o, bottom + size * 1.5, mid, size, piece, "Stack", false))
	end
	deco(c, {
		Name = "OpeningEdge",
		Size = Vector3.new(w, 0.45, 1),
		CFrame = CFrame.new(cx, bottom - 0.05, z - c.toBase.Z * 0.2),
		Color = o.Lip,
	})
	zone(c, "Gate", CFrame.new(cx, g + 13, z + c.toBase.Z * depth / 2), Vector3.new(w, 26, depth + 1.5))
	c.afterRing = 1
	return depth
end

-- FORCED DOUBLE JUMP: a very high wall (9.5: over one jump's ~6.4, under a double jump's ~14), the biome's own: a
-- wooden fence, an ice wall, a temple wall, a basalt wall with lava seams, a wall of toxic barrels, a chocolate bar
local function double(c: Course, z: number, g: number): number
	local o = look(z)
	local wl = o.Wall
	cue(c, z, "DOUBLE JUMP!", PROMPT_COLORS.DOUBLE)
	local cx, w = span(c)
	local h, depth = 9.5, 2.6
	-- (user 2026-11-20: "high log walls, things appropriate for the biome, like for candy, candies stacked together")
	if rng:NextNumber() < 0.7 then
		local piece = h / 2
		local d = if o.Round then piece else 3
		local mid = z + c.toBase.Z * d / 2
		beam(c, o, g + piece / 2, mid, piece, d, "Stack", true)
		beam(c, o, g + piece * 1.5, mid, piece, d, "Stack", true)
		deco(c, {
			Name = "TopEdge",
			Size = Vector3.new(w, 0.5, d * 0.7),
			CFrame = CFrame.new(cx, g + h + 0.1, mid),
			Color = o.Lip,
		})
		if rng:NextNumber() < 0.6 then
			ring(c, Vector3.new(c.laneX, g + 15, mid), luck(3))
		end
		return d
	end
	local mid = z + c.toBase.Z * depth / 2
	local face = z - c.toBase.Z * 0.1
	local wall = solid(c, {
		Name = "Block",
		Size = Vector3.new(w, h, depth),
		CFrame = CFrame.new(cx, g + h / 2, mid),
		Color = wl.Color,
	})
	if wl.Style == "Ice" then
		mat(wall, true)
	end
	local style = wl.Style
	if style == "Planks" then
		for _, x in nearLane(c, 3, 70) do
			deco(c, {
				Name = "Plank",
				Size = Vector3.new(0.35, h, 0.2),
				CFrame = CFrame.new(x, g + h / 2, face),
				Color = wl.Color:Lerp(Color3.new(0, 0, 0), 0.35),
			})
		end
		deco(c, {
			Name = "Rail",
			Size = Vector3.new(w, 0.8, 0.5),
			CFrame = CFrame.new(cx, g + h * 0.5, face),
			Color = wl.Trim,
		})
	elseif style == "Temple" then
		for i = 1, 3 do
			deco(c, {
				Name = "Band",
				Size = Vector3.new(w, 0.7, depth + 0.2),
				CFrame = CFrame.new(cx, g + i * 2.6, mid),
				Color = wl.Color:Lerp(Color3.new(0, 0, 0), 0.25),
			})
		end
		for _, x in nearLane(c, 16, 64) do
			deco(c, {
				Name = "Eye",
				Size = Vector3.new(3, 1.3, 0.3),
				CFrame = CFrame.new(x, g + h - 2, face),
				Color = o.Lip,
			})
		end
	elseif style == "Lava" then
		for _, x in nearLane(c, 8, 80) do
			deco(c, {
				Name = "LavaSeam",
				Size = Vector3.new(0.6, h - 1, 0.25),
				CFrame = CFrame.new(x, g + h / 2, face) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-20, 20))),
				Color = wl.Trim,
				Material = Enum.Material.Neon,
			})
		end
	elseif style == "Barrels" then
		for i, x in nearLane(c, 4.2, 64) do
			for row = 0, 1 do
				deco(c, {
					Name = "Barrel",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(h / 2 - 0.1, 4, 4),
					CFrame = CFrame.new(x, g + h / 4 + row * h / 2, face - c.toBase.Z * 1.5)
						* CFrame.Angles(0, 0, math.pi / 2),
					Color = if (i + row) % 3 == 0 then rgb(60, 60, 65) else wl.Color,
				})
			end
		end
	elseif style == "Choco" then
		for _, x in nearLane(c, 6, 60) do
			for row = 0, 1 do
				deco(c, {
					Name = "Square",
					Size = Vector3.new(5.2, 4, 0.5),
					CFrame = CFrame.new(x, g + 2.4 + row * 4.4, face),
					Color = wl.Color:Lerp(Color3.new(0, 0, 0), 0.2),
				})
			end
		end
	end
	-- the top: snow, gold trim, glowing lava, toxic slime, pink frosting...
	local top = deco(c, {
		Name = "TopEdge",
		Size = Vector3.new(w, 0.8, depth + 0.4),
		CFrame = CFrame.new(cx, g + h + 0.2, mid),
		Color = wl.Trim,
	})
	if style == "Lava" or style == "Barrels" then
		top.Material = Enum.Material.Neon
	end
	if rng:NextNumber() < 0.6 then
		ring(c, Vector3.new(c.laneX, g + 15, mid), luck(3))
	end
	return depth
end

-- SWEEPERS (obby): arms spinning round posts at knee height, right across (the biome's log, pipe, candy stick...):
-- jump them as they come
local function sweeper(c: Course, z: number, g: number): number
	local o = look(z)
	cue(c, z, "JUMP!", PROMPT_COLORS.JUMP)
	local step = 30
	local turn = math.rad(rng:NextNumber(95, 135))
	local arms = {}
	local x = c.x0 + step / 2
	local i = 0
	while x < c.x1 do
		solid(c, {
			Name = "Post",
			Size = Vector3.new(2.4, 4.5, 2.4),
			CFrame = CFrame.new(x, g + 2.25, z),
			Color = o.Accent,
		})
		local arm = part(c, {
			Name = "Arm",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(step - 1, 1.8, 1.8),
			CFrame = CFrame.new(x, g + 1.3, z),
			Color = o.Main,
			CanCollide = false,
		})
		mat(arm, o.Glass)
		table.insert(c.hits, arm)
		-- neighbours turn opposite ways, a quarter turn apart, so they never clash
		table.insert(arms, {
			arm = arm,
			pivot = Vector3.new(x, g + 1.3, z),
			a = (i % 2) * math.pi / 2,
			w = (if i % 2 == 0 then -1 else 1) * turn,
		})
		x += step
		i += 1
	end
	table.insert(c.tickers, function(_, dt)
		if not arms[1].arm.Parent then
			return true
		end
		local P, C = {}, {}
		for _, s in arms do
			s.a += s.w * dt
			table.insert(P, s.arm)
			table.insert(C, CFrame.new(s.pivot) * CFrame.Angles(0, s.a, 0))
		end
		flush(P, C)
		return false
	end)
	moveRing(c, g, z, 8.2, 16.5)
	return 3
end

-- SWINGING (obby): a big piece of the biome hanging right across on ropes, swinging back and forth at head height:
-- slide under it (standing or jumping, it knocks you back)
local function swing(c: Course, z: number, g: number): number
	local o = look(z)
	cue(c, z, "SLIDE!", PROMPT_COLORS.SLIDE, true)
	local cx, w = span(c)
	local pivotY, L = g + 17, 12.2 -- (lowest point: its middle at ~4.8, head height)
	local d = 3.2
	local log = part(c, {
		Name = "HeadBar",
		Shape = if o.Round then Enum.PartType.Cylinder else Enum.PartType.Block,
		Size = if o.Round then Vector3.new(w, d, d) else Vector3.new(w, d, d),
		CFrame = CFrame.new(cx, pivotY - L, z),
		Color = o.Main,
		CanCollide = false,
	})
	mat(log, o.Glass)
	table.insert(c.hits, log)
	local parts = { log }
	for _, x in nearLane(c, 30, 60) do
		table.insert(
			parts,
			deco(c, {
				Name = "Rope",
				Size = Vector3.new(0.3, L, 0.3),
				CFrame = CFrame.new(x, pivotY - L / 2, z),
				Color = rgb(60, 45, 35),
			})
		)
	end
	-- the frame it hangs from (high above: out of the way)
	deco(c, {
		Name = "Frame",
		Size = Vector3.new(w, 1, 1),
		CFrame = CFrame.new(cx, pivotY + 0.5, z),
		Color = o.Accent,
	})
	local gr = group(parts)
	local pivot = CFrame.new(cx, pivotY, z)
	local rel = pivot:ToObjectSpace(log.CFrame)
	local speed = rng:NextNumber(2.2, 3)
	local phase = rng:NextNumber(0, 6)
	table.insert(c.tickers, function(now)
		if not log.Parent then
			return true
		end
		local P, C = {}, {}
		queue(P, C, gr, pivot * CFrame.Angles(math.sin(now * speed + phase) * 0.55, 0, 0) * rel)
		flush(P, C)
		return false
	end)
	c.afterRing = 1
	return 8
end

-- STEPPING PLATFORMS (obby): a long kill strip with rows of the biome's platforms (stumps, ice floes, sandstone
-- blocks, obsidian rocks, upright barrels, cookies): hop from one to the next
local function steps(c: Course, z: number, g: number): number
	local o = look(z)
	local st = o.Step
	local n = rng:NextInteger(2, 4)
	local gap = math.clamp(c.speed * 0.45, 10, 17)
	local len = gap * (n + 1)
	strip(c, o, z, g, len, 3.9)
	for i = 1, n do
		local pz = z + c.toBase.Z * gap * i
		cue(c, pz - c.toBase.Z * gap * 0.6, "JUMP!", PROMPT_COLORS.JUMP)
		for _, px in across(c, 18, if i % 2 == 0 then 0 else 0.5) do
			local pad = part(c, {
				Name = "Step",
				Shape = if st.Round then Enum.PartType.Cylinder else Enum.PartType.Block,
				Size = if st.Round then Vector3.new(1.6, 10, 10) else Vector3.new(10, 1.6, 10),
				CFrame = if st.Round
					then CFrame.new(px, g + 0.8, pz) * CFrame.Angles(0, 0, math.pi / 2)
					else CFrame.new(px, g + 0.8, pz),
				Color = st.Color,
				CanCollide = true,
			})
			mat(pad, o.Glass)
			deco(c, {
				Name = "StepTop",
				Shape = pad.Shape,
				Size = if st.Round then Vector3.new(0.2, 9.4, 9.4) else Vector3.new(9.4, 0.2, 9.4),
				CFrame = pad.CFrame * (if st.Round then CFrame.new(0.8, 0, 0) else CFrame.new(0, 0.8, 0)),
				Color = st.Top,
				Material = if o.AccentNeon then Enum.Material.Neon else Enum.Material.Plastic,
			})
		end
		if i == 2 then
			ring(c, Vector3.new(c.laneX, g + 7, pz), luck(2))
		end
	end
	return len + 1.2
end

-- MOVING WALLS (obby): two walls right across (7 tall: over one jump) sliding side to side with a gap between them:
-- run through the gap. Anywhere else pushes you back.
local function movers(c: Course, z: number, g: number): number
	local o = look(z)
	local wl = o.Wall
	cue(c, z, "GO THROUGH THE GAP!", Color3.fromRGB(140, 255, 140))
	local _, w = span(c)
	local h, depth, gapW = 7, 2.4, 16
	local mid = z + c.toBase.Z * depth / 2
	local walls = {}
	for _, s in { -1, 1 } do
		local wall = mover(c, {
			Name = "Mover",
			Size = Vector3.new(w, h, depth),
			CFrame = CFrame.new(c.laneX + s * (gapW + w) / 2, g + h / 2, mid),
			Color = wl.Color,
		})
		if wl.Style == "Ice" then
			mat(wall, true)
		end
		local top = deco(c, {
			Name = "TopEdge",
			Size = Vector3.new(w, 0.6, depth + 0.3),
			CFrame = wall.CFrame * CFrame.new(0, h / 2 + 0.2, 0),
			Color = wl.Trim,
		})
		-- the gap's edge glows
		local edge = deco(c, {
			Name = "GapEdge",
			Size = Vector3.new(0.8, h, depth + 0.3),
			CFrame = wall.CFrame * CFrame.new(-s * w / 2, 0, 0),
			Color = o.Lip,
			Material = Enum.Material.Neon,
		})
		table.insert(walls, { gr = group({ wall, top, edge }), s = s })
	end
	local amp = rng:NextNumber(20, 34)
	local speed = rng:NextNumber(0.9, 1.4)
	local phase = rng:NextNumber(0, 6)
	local base = c.laneX
	local lo, hi = c.x0 + gapW, c.x1 - gapW
	local nextPush = 0
	table.insert(c.tickers, function(now)
		local first = walls[1].gr.parts[1]
		if not first.Parent then
			return true
		end
		local gx = math.clamp(base + math.sin(now * speed + phase) * amp, lo, hi)
		local P, C = {}, {}
		for _, wv in walls do
			queue(P, C, wv.gr, CFrame.new(gx + wv.s * (gapW + w) / 2, g + h / 2, mid))
		end
		flush(P, C)
		-- not in the gap: pushed back (a wall is no way through)
		local hrp = c.hrp
		if hrp then
			local p = hrp.Position
			local along = (p.Z - mid) * c.toBase.Z
			if
				now >= nextPush
				and math.abs(along) < depth / 2 + 1.2
				and math.abs(p.X - gx) > gapW / 2 - 1
				and p.Y < g + h + 3
			then
				nextPush = now + 0.4
				local _ = along
			end
		end
		return false
	end)
	c.afterRing = 2
	return depth
end

-- HURDLES: a row of 2-4 low pieces in quick succession: jump, jump, jump (a rhythm)
local function hurdles(c: Course, z: number, g: number): number
	local o = look(z)
	local cx, w = span(c)
	local n = rng:NextInteger(2, 4)
	local gap = math.clamp(c.speed * 0.5, 14, 26)
	local h, depth = 2.2, 2
	for i = 0, n - 1 do
		local hz = z + c.toBase.Z * gap * i
		cue(c, hz, "JUMP!", PROMPT_COLORS.JUMP)
		beam(c, o, g + h / 2, hz + c.toBase.Z * depth / 2, h, depth, "Bar", true)
		deco(c, {
			Name = "TopEdge",
			Size = Vector3.new(w, 0.3, 0.9),
			CFrame = CFrame.new(cx, g + h + 0.1, hz + c.toBase.Z * depth / 2),
			Color = o.Lip,
		})
		if i == 1 then
			ring(c, Vector3.new(c.laneX, g + 8.6, hz + c.toBase.Z * depth / 2), luck(1))
		end
	end
	return gap * (n - 1) + depth
end

-- WEAVE (obby): two staggered rows of tall pillars (the biome's own: logs on end, ice pillars, sandstone columns,
-- obsidian spires, pipes, candy sticks): steer through the gaps
local function weave(c: Course, z: number, g: number): number
	local o = look(z)
	cue(c, z, "WEAVE THROUGH!", Color3.fromRGB(140, 255, 140))
	local h, size, step = 11, 7, 19
	local rowGap = math.clamp(c.speed * 0.3, 12, 20)
	for row = 0, 1 do
		local rz = z + c.toBase.Z * (size / 2 + rowGap * row)
		for _, x in across(c, step, if row == 0 then 0.25 else 0.75) do
			if math.abs(x - c.laneX) > 120 then
				continue -- (far off to the side: nobody runs there, and fewer parts to build)
			end
			local pillar = solid(c, {
				Name = "Pillar",
				Shape = if o.Round then Enum.PartType.Cylinder else Enum.PartType.Block,
				Size = if o.Round then Vector3.new(h, size, size) else Vector3.new(size, h, size),
				CFrame = if o.Round
					then CFrame.new(x, g + h / 2, rz) * CFrame.Angles(0, 0, math.pi / 2)
					else CFrame.new(x, g + h / 2, rz),
				Color = o.Main,
			})
			mat(pillar, o.Glass)
			if math.abs(x - c.laneX) < 70 then
				local band = deco(c, {
					Name = "Band",
					Shape = pillar.Shape,
					Size = if o.Round
						then Vector3.new(1.2, size + 0.2, size + 0.2)
						else Vector3.new(size + 0.2, 1.2, size + 0.2),
					CFrame = if o.Round
						then CFrame.new(x, g + h * 0.6, rz) * CFrame.Angles(0, 0, math.pi / 2)
						else CFrame.new(x, g + h * 0.6, rz),
					Color = o.Accent,
				})
				mat(band, false, o.AccentNeon)
				deco(c, {
					Name = "Cap",
					Shape = pillar.Shape,
					Size = if o.Round
						then Vector3.new(0.6, size + 0.3, size + 0.3)
						else Vector3.new(size + 0.3, 0.6, size + 0.3),
					CFrame = if o.Round
						then CFrame.new(x, g + h, rz) * CFrame.Angles(0, 0, math.pi / 2)
						else CFrame.new(x, g + h, rz),
					Color = o.Lip,
				})
			end
		end
	end
	c.afterRing = 1
	return size + rowGap
end

-- SMASHERS (obby): big blocks right across in sections, each rising and slamming down in turn (neighbours out of
-- step): go under one while it's up, or steer to one that is. Caught under one as it comes down: pushed back.
local function pounders(c: Course, z: number, g: number): number
	local o = look(z)
	local wl = o.Wall
	cue(c, z, "WATCH THE SMASHERS!", Color3.fromRGB(255, 160, 80))
	local secW, h, depth = 16, 6, 5
	local mid = z + c.toBase.Z * depth / 2
	local list = {}
	local i = 0
	for _, x in across(c, secW, 0.5) do
		if math.abs(x - c.laneX) > 130 then
			continue -- (far off to the side: nobody runs there)
		end
		local block = mover(c, {
			Name = "Smasher",
			Size = Vector3.new(secW - 1.5, h, depth),
			CFrame = CFrame.new(x, g + h / 2, mid),
			Color = wl.Color,
		})
		if wl.Style == "Ice" then
			mat(block, true)
		end
		local trim = deco(c, {
			Name = "Trim",
			Size = Vector3.new(secW - 1.3, 0.6, depth + 0.2),
			CFrame = block.CFrame * CFrame.new(0, -h / 2 + 0.3, 0),
			Color = o.Lip,
			Material = Enum.Material.Neon,
		})
		-- a dark shadow on the ground under it
		deco(c, {
			Name = "Shadow",
			Size = Vector3.new(secW - 1.5, 0.15, depth),
			CFrame = CFrame.new(x, g + 0.1, mid),
			Color = rgb(30, 25, 30),
			Transparency = 0.4,
		})
		table.insert(list, { gr = group({ block, trim }), x = x, phase = (i % 2) * 0.5 + rng:NextNumber(-0.08, 0.08) })
		i += 1
	end
	local period = rng:NextNumber(1.3, 1.7)
	local nextPush = 0
	local top = 15
	table.insert(c.tickers, function(now)
		if #list == 0 or not list[1].gr.parts[1].Parent then
			return true
		end
		local P, C = {}, {}
		local hrp = c.hrp
		local hp = hrp and hrp.Position
		for _, s in list do
			local t = ((now / period) + s.phase) % 1
			-- up for most of the cycle, a quick slam, a moment down, then it lifts again
			local y
			if t < 0.55 then
				y = top
			elseif t < 0.62 then
				local k = (t - 0.55) / 0.07
				y = top * (1 - k * k)
			elseif t < 0.8 then
				y = 0
			else
				y = top * ((t - 0.8) / 0.2)
			end
			queue(P, C, s.gr, CFrame.new(s.x, g + h / 2 + y, mid))
			if
				hp
				and y < 3
				and now >= nextPush
				and math.abs(hp.X - s.x) < secW / 2
				and math.abs((hp.Z - mid) * c.toBase.Z) < depth / 2 + 1
			then
				nextPush = now + 0.5
				local along = (hp.Z - mid) * c.toBase.Z
				local _ = along
				slowedByRed(Config.SlowDuration * 0.4)
				ChaseFx.play("Thud", 1, 0.9)
				ChaseFx.kick(-6)
			end
		end
		flush(P, C)
		return false
	end)
	c.afterRing = 2
	return depth
end

-- NARROW BRIDGES (obby): a long kill strip with three narrow planks running along it: stay on one
local function bridge(c: Course, z: number, g: number): number
	local o = look(z)
	local st = o.Step
	cue(c, z, "STAY ON THE BRIDGE!", Color3.fromRGB(255, 230, 120))
	local len = math.clamp(c.speed * 0.9, 30, 70)
	strip(c, o, z, g, len, 3.9)
	local mid = z + c.toBase.Z * len / 2
	local bw = 9 -- (wide: easy to stay on; user 2026-11-20)
	local offs = { -26, 0, 26 }
	local wiggle = rng:NextNumber() < 0.5
	for k, off in offs do
		local x = math.clamp(c.laneX + off, c.x0 + 4, c.x1 - 4)
		if wiggle then
			-- two halves, the far one shifted sideways: hop across in the middle
			local shift = (if k % 2 == 0 then -1 else 1) * 7
			for half = 0, 1 do
				local hz = z + c.toBase.Z * (len * (0.25 + half * 0.5))
				part(c, {
					Name = "Plank",
					Size = Vector3.new(bw, 1.2, len / 2 + 0.5),
					CFrame = CFrame.new(x + half * shift, g + 0.6, hz),
					Color = st.Color,
					CanCollide = true,
				})
			end
		else
			part(c, {
				Name = "Plank",
				Size = Vector3.new(bw, 1.2, len + 1),
				CFrame = CFrame.new(x, g + 0.6, mid),
				Color = st.Color,
				CanCollide = true,
			})
		end
	end
	ring(c, Vector3.new(math.clamp(c.laneX, c.x0 + 4, c.x1 - 4), g + 4, mid), luck(2))
	return len + 1.2
end

-- COMBO: a low piece to jump, then right after it a bar at head height to slide under
local function combo(c: Course, z: number, g: number): number
	local o = look(z)
	local cx, w = span(c)
	cue(c, z, "JUMP!", PROMPT_COLORS.JUMP)
	local h, depth = 2.4, 2
	beam(c, o, g + h / 2, z + c.toBase.Z * depth / 2, h, depth, "Bar", true)
	deco(c, {
		Name = "TopEdge",
		Size = Vector3.new(w, 0.3, 0.9),
		CFrame = CFrame.new(cx, g + h + 0.1, z + c.toBase.Z * depth / 2),
		Color = o.Lip,
	})
	local gap = math.clamp(c.speed * 0.55, 16, 30)
	local bz = z + c.toBase.Z * (depth + gap)
	cue(c, bz, "SLIDE!", PROMPT_COLORS.SLIDE, true)
	-- (slide ONLY, user 2026-11-22: the bar was 3.2 tall and you could jump over it; now it reaches up to 22, far over
	-- a double jump)
	slideBlock(c, beam(c, o, g + 3.4 + 1.6, bz, 3.2, 3.2, "HeadBar", false))
	slideBlock(c, beam(c, o, g + 6.6 + 7.7, bz, 15.4, 3.2, "HeadBar", false))
	zone(c, "Gate", CFrame.new(cx, g + 13, bz), Vector3.new(w, 26, 4.7))
	deco(c, {
		Name = "UnderEdge",
		Size = Vector3.new(w, 0.3, 0.9),
		CFrame = CFrame.new(cx, g + 3.3, bz),
		Color = o.Lip,
	})
	for _, px in { c.x0 + 1, c.x1 - 1 } do
		deco(c, {
			Name = "Post",
			Size = Vector3.new(1.2, 7, 1.2),
			CFrame = CFrame.new(px, g + 3.5, bz),
			Color = o.Accent,
		})
	end
	c.afterRing = 1
	return depth + gap + 2
end

-- EITHER WAY (user 2026-11-22: "things where players can either double jump or slide, especially when it's a bit hard
-- like tight areas, or in between a lot of double jumping and sliding only obstacles"): a bar from 3.4 up to 9.4: too
-- high for one jump (~6.4) but under a double jump (~14), and open underneath for a slide. Sometimes two of them close
-- together (a tight bit). The prompt says "SLIDE or DOUBLE JUMP!".
local function either(c: Course, z: number, g: number): number
	local o = look(z)
	local cx, w = span(c)
	local bottom, h = g + 3.4, 6
	local depth = if o.Round then h else 3
	local count = if rng:NextNumber() < 0.35 then 2 else 1
	local gap = math.clamp(c.speed * 0.45, 14, 26)
	local used = 0
	for i = 1, count do
		local zi = z + c.toBase.Z * (i - 1) * (depth + gap)
		cue(c, zi, "SLIDE or DOUBLE JUMP!", PROMPT_COLORS.EITHER)
		local mid = zi + c.toBase.Z * depth / 2
		slideBlock(c, beam(c, o, bottom + h / 2, mid, h, depth, "EitherBar", false))
		deco(c, {
			Name = "TopEdge",
			Size = Vector3.new(w, 0.4, depth * 0.7),
			CFrame = CFrame.new(cx, bottom + h + 0.1, mid),
			Color = o.Lip,
		})
		deco(c, {
			Name = "UnderEdge",
			Size = Vector3.new(w, 0.3, 0.9),
			CFrame = CFrame.new(cx, bottom - 0.05, zi - c.toBase.Z * 0.2),
			Color = o.Lip,
		})
		zone(c, "Gate", CFrame.new(cx, g + 3, mid), Vector3.new(w, 6, depth + 1.5))
		used = (i - 1) * (depth + gap) + depth
	end
	c.afterRing = 1
	return used
end

-- SPEED BOOST PAD (user 2026-11-22: "include some speed boost parts"): a bright strip of arrows right across; run over
-- it and you go faster for a couple of seconds (Movement.boost)
local function boostPad(c: Course, z: number, g: number): number
	local cx, w = span(c)
	cue(c, z, "SPEED BOOST!", PROMPT_COLORS.BOOST)
	local depth = 8
	local mid = z + c.toBase.Z * depth / 2
	deco(c, {
		Name = "BoostPad",
		Size = Vector3.new(w, 0.3, depth),
		CFrame = CFrame.new(cx, g + 0.15, mid),
		Color = Color3.fromRGB(40, 200, 255),
	})
	-- arrows (chevrons) pointing home, near where you're heading
	for _, x in nearLane(c, 7, 63) do
		for k = 0, 1 do
			local az = z + c.toBase.Z * (2 + k * 3.5)
			for _, side in { -1, 1 } do
				deco(c, {
					Name = "Arrow",
					Size = Vector3.new(2.4, 0.35, 0.7),
					CFrame = CFrame.new(x + side * 0.85, g + 0.35, az)
						* CFrame.Angles(0, math.rad(side * 40) * c.toBase.Z, 0),
					Color = Color3.fromRGB(255, 255, 255),
				})
			end
		end
	end
	zone(c, "Boost", CFrame.new(cx, g + 3, mid), Vector3.new(w, 6, depth))
	return depth
end

-- TWIN WALLS (double jump only, user 2026-11-22): two of the DOUBLE JUMP! walls in a row with a short run-up between
local function twinWall(c: Course, z: number, g: number): number
	local d1 = double(c, z, g)
	local gap = math.clamp(c.speed * 0.6, 18, 34)
	local d2 = double(c, z + c.toBase.Z * (d1 + gap), g)
	return d1 + gap + d2
end

-- BOUNCE PAD (obby): a glowing pad right across, then a wall far too high to jump (16): the pad throws you over it.
-- Missed the pad (jumped over it)? The wall puts you back before the pad to try again.
local function bounce(c: Course, z: number, g: number): number
	local o = look(z)
	local wl = o.Wall
	local cx, w = span(c)
	cue(c, z, "BOUNCE!", Color3.fromRGB(255, 120, 230))
	local padDepth = 7
	local padMid = z + c.toBase.Z * padDepth / 2
	deco(c, {
		Name = "Pad",
		Size = Vector3.new(w, 0.5, padDepth),
		CFrame = CFrame.new(cx, g + 0.25, padMid),
		Color = rgb(255, 90, 220),
		Material = Enum.Material.Neon,
	})
	for _, x in nearLane(c, 9, 70) do
		deco(c, {
			Name = "Arrow",
			Size = Vector3.new(2.4, 0.2, 2.4),
			CFrame = CFrame.new(x, g + 0.55, padMid) * CFrame.Angles(0, math.rad(45), 0),
			Color = Color3.new(1, 1, 1),
		})
	end
	local pad = zone(c, "Pad", CFrame.new(cx, g + 3, padMid), Vector3.new(w, 6, padDepth))
	pad.back = nil
	local gap = math.clamp(c.speed * 0.25, 10, 20)
	local wh, wd = 16, 3
	local wallMid = z + c.toBase.Z * (padDepth + gap + wd / 2)
	local wall = solid(c, {
		Name = "BigWall",
		Size = Vector3.new(w, wh, wd),
		CFrame = CFrame.new(cx, g + wh / 2, wallMid),
		Color = wl.Color,
	})
	if wl.Style == "Ice" then
		mat(wall, true)
	end
	deco(c, {
		Name = "TopEdge",
		Size = Vector3.new(w, 0.8, wd + 0.4),
		CFrame = CFrame.new(cx, g + wh + 0.2, wallMid),
		Color = wl.Trim,
	})
	ring(c, Vector3.new(c.laneX, g + wh + 5, wallMid), luck(2)) -- (high over the wall: you fly through it)
	return padDepth + gap + wd
end

-- ZIGZAG STRIPS: one or two red strips zigzagging right across (user 2026-11-20: "instead, you can have zig zag
-- strips"): jump each where it crosses your way
local function zigzag(c: Course, z: number, g: number): number
	local o = look(z)
	local n = rng:NextInteger(1, 2)
	local seg = rng:NextNumber(30, 44) -- (studs across per leg)
	local amp = rng:NextNumber(10, 18) -- (how far the zigzag swings towards the base and back)
	local depth = math.clamp(c.speed * 0.12, 5, 9)
	local gapZ = math.clamp(c.speed * 0.7, 30, 60)
	local cx, w = span(c)
	local strips: { [BasePart]: boolean } = {}
	local color = o.Danger or DANGER
	local function zOff(x: number): number
		-- a triangle wave across x: 0 .. amp .. 0 ..
		local t = ((x - c.x0) / seg) % 2
		return (if t < 1 then t else 2 - t) * amp
	end
	local total = 0
	for k = 0, n - 1 do
		local base = z + c.toBase.Z * (depth / 2 + k * (amp + gapZ))
		local x = c.x0
		while x < c.x1 do
			local x2 = math.min(x + seg, c.x1)
			local a = Vector3.new(x, g + 0.12, base + c.toBase.Z * zOff(x))
			local b = Vector3.new(x2, g + 0.12, base + c.toBase.Z * zOff(x2 - 0.001))
			local mid = (a + b) / 2
			local len = (b - a).Magnitude
			local leg = deco(c, {
				Name = "KillStrip",
				Size = Vector3.new(len + depth * 0.5, 0.4, depth),
				CFrame = CFrame.lookAt(mid, mid + (b - a).Unit) * CFrame.Angles(0, math.pi / 2, 0),
				Color = color,
			})
			leg.CanQuery = true
			strips[leg] = true
			x = x2
		end
		-- the jump cue where it crosses your way
		cue(c, base + c.toBase.Z * (zOff(c.laneX) - depth), "JUMP!", PROMPT_COLORS.JUMP)
		total = k * (amp + gapZ) + amp + depth
	end
	local pit = zone(c, "Pit", CFrame.new(cx, g + 6, z + c.toBase.Z * total / 2), Vector3.new(w, 12, total))
	pit.strips = strips
	c.afterRing = 1
	return total + 1
end

local BUILDERS = {
	Zigzag = zigzag,
	Hurdles = hurdles,
	Weave = weave,
	Pounders = pounders,
	Bridge = bridge,
	Combo = combo,
	Bounce = bounce,
	Jump = jump,
	Slide = slide,
	Double = double,
	Tunnel = tunnel,
	TwinWall = twinWall,
	Either = either,
	Boost = boostPad,
	Sweeper = sweeper,
	Swing = swing,
	Steps = steps,
	Movers = movers,
}

-- the map's scenery, indexed by Z (32-stud rows) the first time a lane is built (spatial queries can't see the
-- walk-through decor: CanQuery is off on it)
type Scenery = { part: BasePart, center: Vector3, rx: number, top: number, bottom: number }
local sceneryRows: { [number]: { Scenery } }? = nil
local sceneryBuilding = false
local ROW = 32
-- (built in the background by RunCourse.prepare, a slice per frame: on the first run it used to freeze the game
-- for ~0.7 s; yields only when `yield` is set)
local function indexScenery(yield: boolean?): { [number]: { Scenery } }
	local rows = {}
	local roots = {}
	local levels = Workspace:FindFirstChild("Levels")
	if levels then
		table.insert(roots, levels)
	end
	local spawnDecor = Workspace:FindFirstChild("Non_functional_spawn_assets")
	if spawnDecor then
		table.insert(roots, spawnDecor)
	end
	for _, root in roots do
		for n, p in root:GetDescendants() do
			if yield and n % 4000 == 0 then
				task.wait()
			end
			if p:IsA("BasePart") and p.Transparency < 1 then
				local size = p.Size
				if size.X > 60 or size.Z > 60 then
					continue -- (ground and big backdrops)
				end
				local half = p.CFrame:VectorToWorldSpace(size / 2)
				local hy = math.max(math.abs(half.Y), size.Y / 2)
				local entry = {
					part = p,
					center = p.Position,
					rx = math.min(math.max(size.X, size.Z) / 2, 30),
					top = p.Position.Y + hy,
					bottom = p.Position.Y - hy,
				}
				local row = math.floor(p.Position.Z / ROW)
				rows[row] = rows[row] or {}
				table.insert(rows[row], entry)
			end
		end
	end
	return rows
end
function sceneryBetween(zMin: number, zMax: number): { Scenery }
	if not sceneryRows then
		if sceneryBuilding then
			return {} -- (still being indexed in the background: never stall a run for it)
		end
		sceneryRows = indexScenery()
	end
	local out = {}
	for row = math.floor(zMin / ROW) - 1, math.floor(zMax / ROW) + 1 do
		local list = (sceneryRows :: any)[row]
		if list then
			table.move(list, 1, #list, #out + 1, out)
		end
	end
	return out
end

-- the run -------------------------------------------------------------------------------------------------------

-- the floor of the biome at z (obstacles stand on it)
local function groundAt(c: Course, z: number): number
	local b = MapInfo.biomeAt(Vector3.new(-8, 1, z))
	if b then
		local _, maxV = MapInfo.bounds(b)
		if maxV then
			return maxV.Y
		end
	end
	return c.g0
end

-- map scenery standing where an obstacle goes is hidden (only for you, only for this run), so it never blocks a gap
local function hideScenery(c: Course, z: number, len: number, g: number)
	-- OFF (user 2026-11-22): it hid single bricks of whatever an obstacle overlapped, so the lava islands and other
	-- builds looked half-loaded during runs. The map always stays whole now.
	if true then
		return
	end
	local z2 = z + c.toBase.Z * len
	-- (and the 30 studs leading up to it: a rock just in front used to hide the obstacle until you ran into it)
	local zA = z - c.toBase.Z * 30
	local zMin, zMax = math.min(zA, z2) - 3, math.max(zA, z2) + 3
	local minV, maxV = MapInfo.bounds(biomeAt(z))
	local xMin = if minV then minV.X - 10 else c.x0
	local xMax = if maxV then maxV.X + 10 else c.x1
	for _, entry in sceneryBetween(zMin, zMax) do
		local p = entry.part
		if c.hidden[p] ~= nil or not p.Parent then
			continue
		end
		local e = entry.center
		if
			e.X + entry.rx > xMin
			and e.X - entry.rx < xMax
			and e.Z + entry.rx > zMin
			and e.Z - entry.rx < zMax
			and entry.top > g + 0.6
			and entry.bottom < g + 30
		then
			c.hidden[p] = p.CanCollide
			p.CanCollide = false
			p.LocalTransparencyModifier = 1
		end
	end
end

-- how many big solid pieces of the map (rocks, hills, buildings) stand where an obstacle would go at x, z
local mapParams = OverlapParams.new()
mapParams.FilterType = Enum.RaycastFilterType.Include
local function bigSceneryAt(c: Course, x: number, z: number, g: number): number
	if #mapParams.FilterDescendantsInstances == 0 then
		local roots = {}
		for _, name in { "Levels", "Non_functional_spawn_assets" } do
			local r = Workspace:FindFirstChild(name)
			if r then
				table.insert(roots, r)
			end
		end
		mapParams.FilterDescendantsInstances = roots
	end
	local n = 0
	local box = CFrame.new(x, g + 5, z + c.toBase.Z * 12)
	for _, p in Workspace:GetPartBoundsInBox(box, Vector3.new(LANE_W, 8, 26), mapParams) do
		if
			p.CanCollide
			and p.Position.Y - p.Size.Y / 2 < g + 6
			and p.Position.Y + p.Size.Y / 2 > g + 2.5
			and math.max(p.Size.X, p.Size.Z) > 8
		then
			n += 1
		end
	end
	return n
end

-- the next obstacle, centred where you're heading. They come in sets of 2-3 about a second apart, then a long
-- breather before the next set.
-- (user, 2026-11-20: "include more variations of obbies and obstacles ... now it is the same variations")
-- (user 2026-11-20: no hopping on rocks / platforms over the strips and no bridges (too fast for that), no three logs in
-- a row: slides and high stacked walls to double jump instead; zigzag strips)
-- (user 2026-11-22: more obstacles that only ONE move gets you through, but not everything: "either way" bars (slide
-- OR double jump) come up a lot, most of all right after a slide-only or double-jump-only one, plus speed boost pads)
local ACTIONS = {
	{ "Jump", 1 },
	{ "Slide", 1.6 },
	{ "Tunnel", 1 },
	{ "Zigzag", 0.8 },
	{ "Double", 1.5 },
	{ "TwinWall", 0.8 },
	{ "Either", 2 },
	{ "Boost", 0.8 },
	-- (Sweeper, Swing and Pounders are off: solid moving pieces would shove you around; user 2026-11-20)
	{ "Sweeper", 0 },
	{ "Swing", 0 },
	{ "Steps", 0 },
	{ "Movers", 0.5 },
	{ "Hurdles", 0 },
	{ "Weave", 0.5 },
	{ "Pounders", 0 },
	{ "Bridge", 0 },
	{ "Combo", 0.7 },
	{ "Bounce", 0 }, -- (off: a pad you MUST use or you can't get past; user 2026-11-20)
}
local function nextAction(c: Course): string
	-- (Studio test hook: player attribute TestObstacle = "Bounce" etc. forces that kind, or a comma list in turn)
	local forced = RunService:IsStudio() and player:GetAttribute("TestObstacle")
	if type(forced) == "string" and forced ~= "" then
		local list = string.split(forced, ",")
		c.testIndex = (c.testIndex or 0) % #list + 1
		local pick = list[c.testIndex]
		if BUILDERS[pick] then
			c.lastAction = pick
			return pick
		end
	end
	local list = table.clone(ACTIONS)
	local _ = c.forceDouble -- (double jumps are in ACTIONS now, every run)
	for k = #list, 1, -1 do
		if list[k][2] <= 0 then
			table.remove(list, k)
		end
	end
	-- after a slide-only / double-jump-only obstacle, an "either way" one is much likelier next
	local strict = { Slide = true, Tunnel = true, Double = true, TwinWall = true, Combo = true }
	if strict[c.lastAction or ""] then
		for k, a in list do
			if a[1] == "Either" then
				list[k] = { a[1], a[2] * 2.5 }
			end
		end
	end
	local total = 0
	for _, a in list do
		if a[1] ~= c.lastAction or a[1] == "Jump" then
			total += a[2]
		end
	end
	local r = rng:NextNumber() * total
	local pick = "Jump"
	for _, a in list do
		if a[1] ~= c.lastAction or a[1] == "Jump" then
			r -= a[2]
			if r <= 0 then
				pick = a[1]
				break
			end
		end
	end
	c.lastAction = pick
	return pick
end

local function spawnNext(c: Course, hrp: BasePart, progress: number)
	local d = c.nextD
	if d > c.stopD then
		c.finished = true
		return
	end
	-- where you'll be: your sideways drift until you get there (half of it: you'll steer anyway)
	local v = hrp.AssemblyLinearVelocity
	local t = math.max(d - progress, 0) / math.max(c.speed, 16)
	local area = Config.PlayAreaX
	local x = math.clamp(
		hrp.Position.X + math.clamp(v.X, -40, 40) * t * 0.5,
		area[1] + LANE_W / 2 + 2,
		area[2] - LANE_W / 2 - 2
	)
	local z = zAt(c, c.origin, d)
	local g = groundAt(c, z)
	-- not squeezed against a big rock or hill of the map's: slide it sideways, towards the middle first
	local lo, hi = area[1] + LANE_W / 2 + 2, area[2] - LANE_W / 2 - 2
	local toMid = if x > (area[1] + area[2]) / 2 then -1 else 1
	local bestX, bestN = x, math.huge
	for _, off in { 0, 14, 28, -14, 42, -28 } do
		local cx = math.clamp(x + toMid * off, lo, hi)
		local n = bigSceneryAt(c, cx, z, g)
		if n < bestN then
			bestX, bestN = cx, n
		end
		if n == 0 then
			break
		end
	end
	c.laneX = bestX
	local sub = Instance.new("Folder")
	sub.Name = "Obstacle"
	sub.Parent = c.root
	c.folder = sub
	local action = nextAction(c)
	local firstHit = #c.hits + 1
	local ringsBefore = #c.rings
	local used = BUILDERS[action](c, z, g)
	-- every obstacle offers one badge (over it, or in the open after it): the luck on offer grows with the run
	-- (user 2026-11-20: longer runs from further out should collect more)
	if #c.rings == ringsBefore and not c.afterRing then
		c.afterRing = 1
	end
	local _ = firstHit
	hideScenery(c, z, used, g)
	-- (the map's Lego look: Plastic + "2022 Stud", not the realistic materials)
	MapStyle.applyAll(sub)
	refreshHits(c)
	table.insert(c.built, { folder = sub, dEnd = d + used })
	local z1 = zAt(c, c.origin, d + used)
	table.insert(c.spans, { z0 = math.min(z, z1), z1 = math.max(z, z1) })
	-- the gap to the next one: about a second within a set (a bit more after a double jump), a breather between sets
	local gap
	c.setLeft -= 1
	if c.setLeft > 0 then
		gap = math.clamp(c.speed * rng:NextNumber(0.7, 0.85), 20, 55) -- (busier: user 2026-11-20)
		if action == "Double" or action == "TwinWall" then
			gap += c.speed * 0.3
		end
	else
		c.setLeft = rng:NextInteger(3, 4)
		gap = c.spacing * rng:NextNumber(0.9, 1.2)
		-- (no trails of badges any more: "you can collect 3 multipliers in a row, should not have this"; user 2026-11-20)
		if false then
			local n = rng:NextInteger(3, 4)
			local tx = c.laneX + rng:NextNumber(-10, 10)
			local wob = rng:NextNumber(-1, 1) * 6
			c.afterRing = nil -- (the trail is this gap's badges)
			for k = 0, n - 1 do
				local dz = d + used + gap * 0.3 + k * 9
				ring(
					c,
					Vector3.new(tx + math.sin(k * 0.9) * wob, g + 3, zAt(c, c.origin, dz)),
					if k == n - 1 then luck(2) else 1
				)
			end
		end
	end
	-- the badge for getting through the obstacle: halfway along the open space after it (never right at it)
	if c.afterRing then
		local tier = c.afterRing :: number
		c.afterRing = nil
		if gap >= 16 then
			local dz = d + used + math.min(gap * 0.5, 22)
			local rx = c.laneX
			if tier >= 2 and rng:NextNumber() < 0.4 then
				rx = math.clamp(
					rx + (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(14, 24),
					c.x0 + 4,
					c.x1 - 4
				)
			end
			ring(c, Vector3.new(rx, g + 3, zAt(c, c.origin, dz)), luck(tier))
		end
	end
	c.nextD = d + used + gap
end

-- THE MAP'S TREES AND HILL PROPS -------------------------------------------------------------------------------------
-- The map's bricks are merged into Chunks.All models, so a tree is found by shape: touching bricks (union-find)
-- standing on the valley floor, 12-32 tall, at most 30 across, tree-shaped (a narrow trunk under a wider top) and not
-- see-through. Hill props: small clusters of touching bricks on the hill steps beside the valley (rocks, bones,
-- crystals, fences, small trees). Found once per biome in the background (RunCourse.prepare) and kept.
-- During a run EVERYTHING near you goes, progressively as you pass (a small stagger, never all on one frame): a tree
-- within 70 studs to your side shakes, creaks and puffs dust over a red strip, then topples; most land beside your way,
-- some right across it (a log to jump: "JUMP!"). Hill props shake and tumble down the slope into the valley's edge.
-- Only on your screen; RunCourse.destroy puts every brick back exactly.
local VALLEY_X = { -110, 100 }
local treeCache: { [number]: { Tree } } = {}
local hillCache: { [number]: { Tree } } = {}
local treesStarted = false

type Box = { p: BasePart, lo: Vector3, hi: Vector3 }
type Cluster = { boxes: { Box }, lo: Vector3, hi: Vector3, low: Box }

-- touching boxes join up (union-find; a grid over x, z finds the neighbours)
local function clusterBoxes(boxes: { Box }): { Cluster }
	local up = table.create(#boxes)
	for i = 1, #boxes do
		up[i] = i
	end
	local function find(i: number): number
		while up[i] ~= i do
			up[i] = up[up[i]]
			i = up[i]
		end
		return i
	end
	local CELL, T = 6, 0.12
	local grid: { [number]: { number } } = {}
	for i, b in boxes do
		if i % 2000 == 0 then
			task.wait()
		end
		for gx = math.floor((b.lo.X - T) / CELL), math.floor((b.hi.X + T) / CELL) do
			for gz = math.floor((b.lo.Z - T) / CELL), math.floor((b.hi.Z + T) / CELL) do
				local key = gx * 4096 + gz
				local cell = grid[key]
				if cell then
					for _, j in cell do
						local a = boxes[j]
						if
							a.lo.X <= b.hi.X + T
							and b.lo.X <= a.hi.X + T
							and a.lo.Y <= b.hi.Y + T
							and b.lo.Y <= a.hi.Y + T
							and a.lo.Z <= b.hi.Z + T
							and b.lo.Z <= a.hi.Z + T
						then
							local ra, rb = find(i), find(j)
							if ra ~= rb then
								up[ra] = rb
							end
						end
					end
					table.insert(cell, i)
				else
					grid[key] = { i }
				end
			end
		end
	end
	local byRoot: { [number]: Cluster } = {}
	local out = {}
	for i, b in boxes do
		local r = find(i)
		local cl = byRoot[r]
		if not cl then
			cl = { boxes = { b }, lo = b.lo, hi = b.hi, low = b }
			byRoot[r] = cl
			table.insert(out, cl)
		else
			table.insert(cl.boxes, b)
			cl.lo = cl.lo:Min(b.lo)
			cl.hi = cl.hi:Max(b.hi)
			if b.lo.Y < cl.low.lo.Y then
				cl.low = b
			end
		end
	end
	return out
end

local function clear(p: BasePart): boolean
	return p.Transparency > 0.05 or p.Material == Enum.Material.Glass
end

-- a real tree: a narrow trunk under a wider top (the bottom quarter is at most half as wide as the whole), not
-- see-through (ice spires and crystals are tall and narrow too, and toppling them blocked the whole view)
local function isTreeShape(cl: Cluster, size: Vector3): boolean
	local w = math.max(size.X, size.Z)
	local lo, hi
	local nClear, total = 0, 0
	for _, b in cl.boxes do
		total += 1
		if clear(b.p) then
			nClear += 1
		end
		if b.lo.Y < cl.lo.Y + size.Y * 0.25 then
			lo = if lo then lo:Min(b.lo) else b.lo
			hi = if hi then hi:Max(b.hi) else b.hi
		end
	end
	if nClear > total * 0.2 or not lo then
		return false
	end
	-- (or slim all the way up: pines and cones are as wide at the bottom as anywhere)
	return math.max(hi.X - lo.X, hi.Z - lo.Z) <= w * 0.5 or size.Y >= w * 1.5
end

local function toTree(cl: Cluster, size: Vector3): Tree
	-- the trunk: the lowest brick and the thin ones stacked over it
	local low = cl.low
	local bx, bz = (low.lo.X + low.hi.X) / 2, (low.lo.Z + low.hi.Z) / 2
	local radius = math.min(math.max(low.hi.X - low.lo.X, low.hi.Z - low.lo.Z) / 2, 3)
	local trunkTop = low.hi.Y
	local parts = { low.p }
	for _, b in cl.boxes do
		if b ~= low then
			table.insert(parts, b.p)
			local mx, mz = (b.lo.X + b.hi.X) / 2, (b.lo.Z + b.hi.Z) / 2
			if
				b.hi.X - b.lo.X <= 6
				and b.hi.Z - b.lo.Z <= 6
				and math.abs(mx - bx) < 3.5
				and math.abs(mz - bz) < 3.5
			then
				trunkTop = math.max(trunkTop, b.hi.Y)
			end
		end
	end
	return {
		parts = parts,
		x = bx,
		z = bz,
		bottom = cl.lo.Y,
		height = size.Y,
		radius = math.max(radius, 1),
		trunk = math.clamp(trunkTop - cl.lo.Y, math.min(4, size.Y), size.Y),
		center = (cl.lo + cl.hi) / 2,
		size = size,
	}
end

local function findScenery(level: Instance): ({ Tree }, { Tree })
	local chunks = level:FindFirstChild("Chunks")
	local root = chunks and chunks:FindFirstChild("All") or level
	local valley: { Box } = {}
	local hill: { Box } = {}
	for n, p in root:GetDescendants() do
		if n % 3000 == 0 then
			task.wait()
		end
		if not p:IsA("BasePart") or p.Transparency >= 1 then
			continue
		end
		local pos = p.Position
		local e = p.ExtentsSize / 2
		-- (the whole play area: many trees stand on small mounds or on the hill steps, not on the valley floor)
		if pos.X > Config.PlayAreaX[1] and pos.X < Config.PlayAreaX[2] then
			-- (not the floor itself, nor big slabs)
			if e.X < 20 and e.Z < 20 and pos.Y + e.Y > 1.6 then
				table.insert(valley, { p = p, lo = pos - e, hi = pos + e })
			end
		end
		-- the hill steps beside the valley: only small bricks (a hill's own big blocks would join everything up)
		if
			(pos.X < VALLEY_X[1] and pos.X > VALLEY_X[1] - 110 or pos.X > VALLEY_X[2] and pos.X < VALLEY_X[2] + 110)
			and e.X < 4
			and e.Z < 4
			and e.Y < 6
			and pos.Y - e.Y > 2
			and not clear(p)
		then
			table.insert(hill, { p = p, lo = pos - e, hi = pos + e })
		end
	end
	-- trees on the valley floor (or a low mound on it) topple; the ones up on the hill steps tumble down to the
	-- valley edge like the hill props (user, 2026-11-20: "the trees in meadow ... need to be falling over")
	local trees, props = {}, {}
	local claimed: { [BasePart]: boolean } = {}
	for _, cl in clusterBoxes(valley) do
		local size = cl.hi - cl.lo
		local cx = (cl.lo.X + cl.hi.X) / 2
		if
			size.Y >= 10
			and size.Y <= 45
			and math.max(size.X, size.Z) <= 30
			and #cl.boxes <= 400
			and isTreeShape(cl, size)
		then
			local t = toTree(cl, size)
			for _, bp in t.parts do
				claimed[bp] = true
			end
			if cl.lo.Y <= 12 and cx > VALLEY_X[1] - 15 and cx < VALLEY_X[2] + 15 then
				table.insert(trees, t)
			else
				table.insert(props, t)
			end
		end
	end
	for _, cl in clusterBoxes(hill) do
		local size = cl.hi - cl.lo
		if size.Y >= 2.5 and size.Y <= 20 and math.max(size.X, size.Z) <= 16 and #cl.boxes <= 150 then
			local mine = true
			for _, b in cl.boxes do
				if claimed[b.p] then
					mine = false
					break
				end
			end
			if mine then
				table.insert(props, toTree(cl, size))
			end
		end
	end
	return trees, props
end

-- find every biome's trees and hill props (once, in the background)
function RunCourse.prepare()
	if treesStarted then
		return
	end
	treesStarted = true
	RunCourse.preloadSounds()
	task.spawn(function()
		local levels = Workspace:WaitForChild("Levels", 60)
		if not levels then
			return
		end
		if not sceneryRows then
			sceneryBuilding = true
			sceneryRows = indexScenery(true)
			sceneryBuilding = false
		end
		for b, biome in Config.Biomes do
			local level = levels:FindFirstChild(biome.Level)
			if level then
				treeCache[b], hillCache[b] = findScenery(level)
			else
				treeCache[b], hillCache[b] = {}, {}
			end
			if RunService:IsStudio() then
				print(`[RunCourse] {biome.Level}: {#treeCache[b]} trees, {#hillCache[b]} hill props to knock over`)
			end
			task.wait()
		end
	end)
end

type Faller = { gr: Group, base: CFrame, rel: CFrame }

-- shake (and creak) for `warn` seconds, then topple sideways (towards +X when side = 1) and lie on the ground
local function toppler(list: { Faller }, side: number, warn: number, onLand: () -> ()): (dt: number) -> boolean
	local t = 0
	return function(dt: number): boolean
		t += dt
		local P, C = {}, {}
		local done = false
		for _, f in list do
			local a
			if t < warn then
				a = math.sin(t * 38 + f.base.X) * math.rad(1.5 + 5 * t / warn)
			else
				local k = math.min((t - warn) / 0.55, 1)
				done = k >= 1
				a = -side * math.pi / 2 * k * k
			end
			queue(P, C, f.gr, f.base * CFrame.Angles(0, 0, a) * f.rel)
		end
		flush(P, C)
		if done then
			onLand()
		end
		return done
	end
end

local function keepOriginal(c: Course, parts: { BasePart })
	for _, p in parts do
		if not c.moved[p] then
			c.moved[p] = { cf = p.CFrame, collide = p.CanCollide }
		end
		p.CanCollide = false -- (never squashes or traps you)
	end
end

local function topple(c: Course, hrp: BasePart, t: Tree, ahead: number)
	local px = hrp.Position.X
	local dx = px - t.x
	local H = t.height
	-- most land beside your way; some right crosses it (only when there's time to see it coming: a log to jump)
	local side
	if math.abs(dx) >= H + 3 then
		side = math.sign(dx) -- (towards you, but it can't reach you)
	elseif rng:NextNumber() < 0.3 and ahead >= c.speed * 1.4 then
		side = if math.abs(dx) < 3 then (if rng:NextNumber() < 0.5 then -1 else 1) else math.sign(dx)
	else
		side = if dx > 0 then -1 else 1 -- (away from you)
	end
	local g = groundAt(c, t.z)
	local folder = Instance.new("Folder")
	folder.Name = "FallingTree"
	folder.Parent = c.root
	local keep = c.folder
	c.folder = folder
	local mark = warnStrip(c, CFrame.new(t.x + side * H / 2, g + 0.12, t.z), Vector3.new(H, 0.2, t.radius * 2 + 3))
	local crosses = px > math.min(t.x, t.x + side * H) - 3 and px < math.max(t.x, t.x + side * H) + 3
	if crosses then
		cue(c, t.z, "JUMP!", PROMPT_COLORS.JUMP)
		-- a risky badge right where it will land: grab it before it comes down
		if rng:NextNumber() < 0.4 then
			ring(c, Vector3.new(px, g + 8, t.z), luck(2)) -- (over the log: jump it to get it)
		end
	end
	puff(c, Vector3.new(t.x, g + 1, t.z), rgb(150, 130, 110), 14)
	c.folder = keep
	table.insert(c.built, { folder = folder, dEnd = dOf(c, t.z) + 4 })
	keepOriginal(c, t.parts)
	c.fell += 1
	Sfx.at("WoodCrack", Vector3.new(t.x, t.bottom + H / 2, t.z), 1.5, rng:NextNumber(0.75, 0.95))
	local base = CFrame.new(t.x, t.bottom + t.radius, t.z)
	local f: Faller = { gr = group(t.parts), base = base, rel = base:ToObjectSpace(t.parts[1].CFrame) }
	local tick = toppler({ f }, side, 0.7, function()
		if mark.Parent then
			mark:Destroy()
		end
		local landed = Vector3.new(t.x + side * H * 0.5, g + 1, t.z)
		Sfx.at("HeavyThud", landed, 1.3)
		if folder.Parent then
			local was = c.folder
			c.folder = folder
			puff(c, landed, rgb(150, 130, 110), 22)
			if crosses then
				-- what you jump: the trunk lying on the ground
				local trunk = part(c, {
					Name = "Trunk",
					Transparency = 1,
					CanCollide = false,
					Size = Vector3.new(t.trunk, 3, t.radius * 2 + 1),
					CFrame = CFrame.new(t.x + side * t.trunk / 2, g + 1.5, t.z),
				})
				table.insert(c.hits, trunk)
				refreshHits(c)
			end
			c.folder = was
		end
		if (hrp.Position - landed).Magnitude < 60 then
			ChaseFx.kick(2)
		end
	end)
	table.insert(c.tickers, function(_, dt)
		return tick(dt)
	end)
end

-- a hill prop shakes, then tumbles down the slope (rolling over) to the valley's edge, beside your way
local function tumble(c: Course, t: Tree)
	keepOriginal(c, t.parts)
	c.fell += 1
	local toValley = if t.x < 0 then 1 else -1
	local g = groundAt(c, t.z)
	local landX = if toValley > 0 then VALLEY_X[1] + rng:NextNumber(2, 14) else VALLEY_X[2] - rng:NextNumber(2, 14)
	local start = t.center
	local finish = Vector3.new(landX, g + t.size.Y / 2, t.z + rng:NextNumber(-4, 4))
	local base = CFrame.new(start)
	local gr = group(t.parts)
	local rel = base:ToObjectSpace(t.parts[1].CFrame)
	local turns = rng:NextNumber(1, 2.2) * math.pi
	local fly = math.clamp(math.abs(landX - start.X) / 30, 0.8, 1.6)
	Sfx.at("Rubble", start, 1.2, rng:NextNumber(0.85, 1.1))
	local keep = c.folder
	local folder = Instance.new("Folder")
	folder.Name = "Tumbling"
	folder.Parent = c.root
	c.folder = folder
	puff(c, start, rgb(150, 130, 110), 10)
	c.folder = keep
	table.insert(c.built, { folder = folder, dEnd = dOf(c, t.z) + 4 })
	local time = 0
	table.insert(c.tickers, function(_, dt)
		time += dt
		local P, C = {}, {}
		if time < 0.45 then
			queue(P, C, gr, base * CFrame.Angles(0, 0, math.sin(time * 45) * math.rad(4)) * rel)
			flush(P, C)
			return false
		end
		local k = math.min((time - 0.45) / fly, 1)
		local pos = start:Lerp(finish, k) + Vector3.new(0, math.sin(k * math.pi) * 6, 0)
		queue(P, C, gr, CFrame.new(pos) * CFrame.Angles(0, 0, -toValley * turns * k) * rel)
		flush(P, C)
		if k >= 1 then
			Sfx.at("RockHit", finish, 1.1)
			if folder.Parent then
				local was = c.folder
				c.folder = folder
				puff(c, finish, rgb(150, 130, 110), 16)
				c.folder = was
			end
			return true
		end
		return false
	end)
end

-- everything near you goes, as you pass: trees within 70 studs to the side when they're ~25-60 studs ahead (sooner at
-- speed), hill props within reach a bit closer; a small stagger so no two start on the same frame
local function toppleTrees(c: Course, hrp: BasePart, now: number)
	if now < c.nextTree then
		return
	end
	local pos = hrp.Position
	local b = biomeAt(pos.Z)
	local reach = math.clamp(c.speed * 1.8, 30, 75)
	local best, bestAhead, isHill = nil, math.huge, false
	for _, bi in { b, b - 1 } do
		for which, list in { treeCache[bi], hillCache[bi] } do
			if not list then
				continue
			end
			local side = if which == 1 then 70 else 150
			local far = if which == 1 then reach else reach * 0.8
			for _, t in list do
				if c.usedTrees[t] then
					continue
				end
				local ahead = (t.z - pos.Z) * c.toBase.Z
				if
					ahead > 6
					and ahead < far
					and ahead < bestAhead
					and math.abs(t.x - pos.X) < side
					and c.hidden[t.parts[1]] == nil
					and t.parts[1].Parent
					and (Vector3.new(t.x, 0, t.z) - MapInfo.dangerLine() * Vector3.new(1, 0, 1)):Dot(c.toBase) < -15
				then
					best, bestAhead, isHill = t, ahead, which == 2
				end
			end
		end
	end
	if best and dOf(c, best.z) < c.stopD then
		c.usedTrees[best] = true
		c.nextTree = now + rng:NextNumber(0.12, 0.3)
		if isHill then
			tumble(c, best)
		else
			topple(c, hrp, best, bestAhead)
		end
	end
end

-- the instruction at the top of the screen
local function buildPrompt(): { gui: ScreenGui, label: TextLabel, scale: UIScale, text: string }
	local gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_RunPrompt"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
	local label = Instance.new("TextLabel")
	-- the top part of the screen, near the middle (user 2026-11-22; it was at the very top edge, then low under your
	-- character): centred, a bit above your character's head, over the sky / far scenery, not the path right ahead
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.27)
	label.Size = UDim2.fromScale(0.42, 0.085)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ""
	label.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, label = label, scale = scale, text = "" }
end

-- origin: where you start (your position when the chase starts). Obstacles appear ahead of you as you go (update).
function RunCourse.build(parent: Instance, origin: Vector3, onRing: (number) -> ()): Course
	RunCourse.prepare()
	local toBase = MapInfo.toBase()
	local root = Instance.new("Folder")
	root.Name = "RunCourse"
	root.Parent = parent
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	local biome = biomeAt(origin.Z)
	local _, maxV = MapInfo.bounds(biome)
	-- this run's share of double jumps: some runs none, some a few, some more
	local r2 = rng:NextNumber()
	local c: Course = {
		root = root,
		folder = root,
		rings = {},
		zones = {},
		hits = {},
		tickers = {},
		built = {},
		spans = {},
		cues = {},
		prompt = buildPrompt(),
		moved = {},
		usedTrees = {},
		nextTree = os.clock() + 1.5,
		nextTreeCheck = 0,
		overlap = overlap,
		nextBump = 0,
		toBase = toBase,
		origin = origin,
		g0 = if maxV then maxV.Y else origin.Y - 3,
		laneX = origin.X,
		x0 = Config.PlayAreaX[1],
		x1 = Config.PlayAreaX[2],
		speed = Movement.baseSpeed(),
		onRing = onRing,
		hidden = {},
		nextD = 0,
		stopD = 0,
		setLeft = rng:NextInteger(2, 3),
		lastAction = nil,
		finished = false,
		spacing = 0,
		forceDouble = if r2 < 0.3 then 0 elseif r2 < 0.75 then 0.5 else 1,
		hrp = nil,
		fell = 0,
		afterRing = nil,
		slideBlocks = {},
		slideOpen = false,
	}
	local total = (MapInfo.dangerLine() - origin):Dot(toBase)
	-- between sets: a breather of ~2.2-3 s of running (user, 2026-11-20: "SPACE THINGS OUT")
	-- (more to do: user 2026-11-20 "you barely have to do anything"): sets of 3-4, ~1.4-1.8 s breathers
	c.spacing = math.clamp(c.speed * rng:NextNumber(1.1, 1.4), 38, 95)
	c.nextD = math.clamp(c.speed * 0.8, 24, 45) -- (the first one straight away)
	c.stopD = total - 70 -- (every obstacle ends well before the white line: nothing on the safe side)
	return c
end

-- is an obstacle standing near this z? (projectiles keep off them: Client/Disaster)
function RunCourse.busyAt(c: Course?, z: number, margin: number): boolean
	if not c then
		return false
	end
	for _, s in c.spans do
		if z > s.z0 - margin and z < s.z1 + margin then
			return true
		end
	end
	return false
end

local function inside(cf: CFrame, size: Vector3, pos: Vector3): boolean
	local l = cf:PointToObjectSpace(pos)
	return math.abs(l.X) < size.X / 2 and math.abs(l.Y) < size.Y / 2 and math.abs(l.Z) < size.Z / 2
end

-- the big instruction at the top centre: DODGE! while a projectile is coming down near you, else what to do at the
-- next thing ahead, shown ~2 s before you reach it (at your speed now)
local DODGE_COLOR = Color3.fromRGB(255, 80, 80)
local function updatePrompt(c: Course, hrp: BasePart, humanoid: Humanoid, progress: number)
	local text, color = "", DODGE_COLOR
	local pos = hrp.Position
	for t in Hazards.targets do
		local dx, dz = t.pos.X - pos.X, t.pos.Z - pos.Z
		local r = t.radius + 7
		if dx * dx + dz * dz < r * r then
			text = "DODGE!"
			break
		end
	end
	local lead = math.max(humanoid.WalkSpeed * 2, 34)
	local best = nil
	local passed = 0
	for _, q in c.cues do
		if q.d < progress - 1.5 then
			passed += 1
		elseif q.d - progress <= lead then
			best = q
			break -- (sorted: the first one ahead)
		else
			break
		end
	end
	if passed > 0 then
		c.cues = table.move(c.cues, passed + 1, #c.cues, 1, {})
	end
	local blink = false
	if text == "" and best then
		text, color = best.text, best.color
		blink = best.blink == true
	end
	local p = c.prompt
	-- (a forced slide blinks: on and off, white and blue)
	if blink then
		local on = (os.clock() * 5) % 1 < 0.6
		p.label.TextTransparency = if on then 0 else 0.75
		p.label.TextColor3 = if on then color else Color3.new(1, 1, 1)
	elseif p.label.TextTransparency ~= 0 then
		p.label.TextTransparency = 0
		p.label.TextColor3 = color
	end
	if text ~= p.text then
		p.text = text
		p.label.Visible = text ~= ""
		if text ~= "" then
			p.label.Text = text
			p.label.TextColor3 = color
			p.scale.Scale = 1.4
			TweenService:Create(p.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end
end

-- true while the top-centre instruction shows (Disaster hides its "RUN!" under it)
function RunCourse.prompting(c: Course?): boolean
	return c ~= nil and c.prompt.text ~= ""
end

-- what's right under your feet (a short ray down from your middle, against this run's pieces only)
local stripRay = RaycastParams.new()
stripRay.FilterType = Enum.RaycastFilterType.Include
local function onStrip(c: Course, hrp: BasePart, stripPart: BasePart?, legs: { [BasePart]: boolean }?): boolean
	if not stripPart and not legs then
		return false
	end
	stripRay.FilterDescendantsInstances = { c.root }
	local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), stripRay)
	return hit ~= nil and (hit.Instance == stripPart or (legs ~= nil and legs[hit.Instance :: BasePart] == true))
end

function RunCourse.update(c: Course, hrp: BasePart, humanoid: Humanoid, dt: number)
	local now = os.clock()
	c.hrp = hrp
	local pos = hrp.Position
	-- obstacles appear ahead of you (about 2 s away, so there's time to see what to do), and old ones behind you go
	local progress = (pos - c.origin):Dot(c.toBase)
	local ahead = math.max(55, humanoid.WalkSpeed * 2.2)
	local made = 0
	while not c.finished and progress + ahead >= c.nextD and made < 4 do
		made += 1
		spawnNext(c, hrp, progress)
	end
	if #c.built > 0 and progress - c.built[1].dEnd > 60 then
		table.remove(c.built, 1).folder:Destroy()
		local keep = {}
		for _, h in c.hits do
			if h.Parent then
				table.insert(keep, h)
			end
		end
		c.hits = keep
		c.overlap.FilterDescendantsInstances = keep
		local rings = {}
		for _, rg in c.rings do
			if rg.model.Parent then
				table.insert(rings, rg)
			end
		end
		c.rings = rings
	end
	toppleTrees(c, hrp, now)
	-- falling trees...
	local i = 1
	while i <= #c.tickers do
		if c.tickers[i](now, dt, progress) then
			c.tickers[i] = c.tickers[#c.tickers]
			c.tickers[#c.tickers] = nil
		else
			i += 1
		end
	end
	-- the luck badges bob and pulse gently (only the ones near you)
	for _, r in c.rings do
		if r.taken or not r.model.Parent then
			continue
		end
		local dist = (pos - r.pos).Magnitude
		if dist < PICKUP_RADIUS then
			collect(c, r)
		elseif dist < 220 then
			local t = now * 2.4 + r.phase
			r.anchor.CFrame = r.base + Vector3.new(0, math.sin(t) * 0.5, 0)
			r.scale.Scale = 1 + math.sin(t * 1.3) * 0.04
			if r.rays then
				r.rays.Rotation = (now * 25) % 360
			end
		end
	end
	updatePrompt(c, hrp, humanoid, progress)
	-- zones
	for _, z in c.zones do
		if z.off then
			continue
		end
		if not inside(z.cf, z.size, pos) then
			z.done = false
			continue
		end
		if z.kind == "Gate" then
			-- under the stack: sliding gets you through (the stack is solid otherwise)
			if Moves.isBusy() and not z.done then
				z.done = true
				ChaseFx.pop("NICE!", Color3.fromRGB(110, 255, 140))
				ChaseFx.play("Good", 0.8, 1.25)
			end
		elseif z.kind == "Boost" then
			-- the speed boost pad: once per visit, faster for a couple of seconds
			if not z.done then
				z.done = true
				Movement.boost(1.6, 2.5)
				ChaseFx.play("Boost", 1, 1.05)
				ChaseFx.pop("SPEED BOOST!", Color3.fromRGB(80, 230, 255))
				ChaseFx.kick(6)
			end
		elseif z.kind == "Pad" then
			-- the bounce pad: once per visit, a big throw up and forwards
			if not z.done then
				z.done = true
				local v = hrp.AssemblyLinearVelocity
				local fwd = math.max((v * Vector3.new(1, 0, 1)):Dot(c.toBase), humanoid.WalkSpeed * 0.8)
				hrp.AssemblyLinearVelocity = Vector3.new(v.X, 92, 0) + c.toBase * fwd
				ChaseFx.play("Boost", 1, 1.15)
				ChaseFx.pop("BOING!", Color3.fromRGB(255, 120, 230))
			end
		elseif z.kind == "Pit" then
			-- in the strip: only when you're standing (not in the air) and the thing right under your feet is the strip
			-- itself, not a platform or a plank over it (user 2026-11-20: "I'm on the strip the whole time and it
			-- registers as I'm touching the mud")
			if humanoid.FloorMaterial ~= Enum.Material.Air and now >= z.next and onStrip(c, hrp, z.strip, z.strips) then
				z.next = now + 0.5
				z.fails = (z.fails or 0) + 1
				slowedByRed(Config.SlowDuration * 0.5)
				z.next = now + 1.2 -- (in the mud / water / lava: slowed, never put back)
				ChaseFx.play("Thud", 1, 0.8)
				ChaseFx.kick(-6)
				if (z.fails :: number) >= 2 and z.bridge then
					z.off = true
					z.bridge(pos.X)
					ChaseFx.pop("BRIDGE!", Color3.fromRGB(255, 230, 120))
				end
			end
		end
	end
	-- (touching an obstacle never slows you: they're solid, that's all)
	-- the slide blocks: open while you slide; closed again only once you're out from under them (closing on top of
	-- you would shove you out)
	local sliding = Moves.isBusy()
	if sliding ~= c.slideOpen then
		local canClose = true
		if not sliding then
			for _, b in c.slideBlocks do
				if b.Parent then
					local l = b.CFrame:PointToObjectSpace(pos)
					local half = b.Size / 2
					-- (a cylinder lies along X: its depth is Size.Y / Z either way)
					if math.abs((pos.Z - b.Position.Z)) < math.max(half.Y, half.Z) + 2.5 and math.abs(l.X) < half.X then
						canClose = false
						break
					end
				end
			end
		end
		if sliding or canClose then
			c.slideOpen = sliding
			for _, b in c.slideBlocks do
				if b.Parent then
					b.CanCollide = not sliding
				end
			end
		end
	end
end

function RunCourse.destroy(c: Course?)
	if not c then
		return
	end
	if RunService:IsStudio() then
		local b = biomeAt(c.origin.Z)
		local found = #(treeCache[b] or {}) + #(hillCache[b] or {})
		print(`[RunCourse] run from biome {b}: {found} trees + hill props cached there, {c.fell} knocked over this run`)
	end
	c.root:Destroy()
	c.prompt.gui:Destroy()
	for p, collide in c.hidden do
		if p.Parent then
			p.CanCollide = collide
			p.LocalTransparencyModifier = 0
		end
	end
	table.clear(c.hidden)
	-- the map's trees we knocked over: exactly back where they were
	for p, was in c.moved do
		if p.Parent then
			p.CFrame = was.cf
			p.CanCollide = was.collide
		end
	end
	table.clear(c.moved)
	table.clear(c.tickers)
end

return RunCourse
