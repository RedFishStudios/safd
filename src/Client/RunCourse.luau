-- A different course on every run home (user, 2026-11-19: "all times you run should be different"). When a chase
-- starts, a random sequence of set-pieces is built on the path between you and the white line. They exist only for
-- you, only for this run, and are gone when it ends:
--   * Blockade: a wall of mud (ice, sandstone, basalt, slime, candy: whatever the biome is made of) right across the
--     path with one gap: find it. A x2 ring sits in the gap.
--   * Split: a tall ridge splits the path. The wide lane is easy (x2); the narrow lane has hurdles to jump (x3).
--   * Zipline: hop up a rock (step, then top) and you grab a cable that carries you far ahead, faster than you run,
--     onto another rock. A x5 ring hangs on the cable.
--   * Launch pads: glowing pads fling you up and forward; a x3 ring floats at the top of the arc.
--   * Slalom: x2 rings weaving across the path.
--   * Chute: walk up a ramp to a high platform and shoot down a long slide, fast, to a x3 ring at the bottom.
--   * Bounce: a mud pit across the path (wading through it slows you right down) with bouncy mushrooms over it:
--     bounce across to keep your speed (x3 rings in the air).
--   * High road: a rock staircase up onto a narrow ridge over the path, x5 at its end; the low road only has a x2.
--   * Speed strips: glowing arrows on the ground that give you a burst of speed.
--   * Gates: a wall with three doors. x2 is open, x3 has a hurdle in it, x5 is behind a block you can only double jump.
-- Signs over every choice show what each way pays, so you can decide whether to risk it; x5 rings have a beam of
-- light over them so you can see them coming from far off.
-- Multiplier rings (only during a run home) multiply the bonus your animals pay when you get them home
-- (Server/AnimalService; the counting-up cutscene: Client/RunReward). Collecting one tells the server (Net.RunRing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapInfo = require(Shared.MapInfo)
local Net = require(Shared.Net)

local ChaseFx = require(script.Parent.ChaseFx)
local Movement = require(script.Parent.Movement)

local player = Players.LocalPlayer
local rng = Random.new()

local RunCourse = {}

local RING_MESH = "rbxassetid://3270017"
local RING_COLORS = {
	[2] = Color3.fromRGB(80, 255, 120),
	[3] = Color3.fromRGB(80, 180, 255),
	[5] = Color3.fromRGB(255, 200, 40),
}

-- what each biome's set-pieces are made of
local THEMES = {
	{ Material = Enum.Material.Mud, Color = Color3.fromRGB(105, 72, 45), Rock = Color3.fromRGB(120, 120, 115) },
	{ Material = Enum.Material.Ice, Color = Color3.fromRGB(190, 225, 245), Rock = Color3.fromRGB(150, 165, 180) },
	{ Material = Enum.Material.Sandstone, Color = Color3.fromRGB(215, 175, 115), Rock = Color3.fromRGB(190, 150, 95) },
	{ Material = Enum.Material.Basalt, Color = Color3.fromRGB(70, 35, 30), Rock = Color3.fromRGB(60, 50, 50) },
	{ Material = Enum.Material.Slate, Color = Color3.fromRGB(85, 120, 50), Rock = Color3.fromRGB(80, 90, 70) },
	{
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 150, 200),
		Rock = Color3.fromRGB(180, 120, 255),
	},
}

type Ring = { pos: Vector3, value: number, model: Model, taken: boolean }
type Zip = { a: Vector3, b: Vector3, cable: BasePart }
type Pad = { cf: CFrame, size: Vector3, next: number }
-- an area that does something while you stand in it: "Chute" (speed), "Mud" (slow), "Strip" (speed burst),
-- "Bounce" (a mushroom: up you go)
type Zone = { kind: string, cf: CFrame, size: Vector3, next: number, dir: Vector3 }

export type Course = {
	folder: Folder,
	rings: { Ring },
	zips: { Zip },
	pads: { Pad },
	zones: { Zone },
	riding: { zip: Zip, t: number, handle: BasePart, whirr: Sound? }?,
	zipCooldown: number,
	toBase: Vector3,
	onRing: (value: number) -> (),
}

local function block(c: Course, size: Vector3, cf: CFrame, theme, rock: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Material = if rock then Enum.Material.Rock else theme.Material
	p.Color = if rock then theme.Rock else theme.Color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = c.folder
	-- rise up out of the ground
	local final = p.CFrame
	p.CFrame = final - Vector3.new(0, size.Y + 1, 0)
	TweenService:Create(p, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = final })
		:Play()
	return p
end

local function ring(c: Course, pos: Vector3, value: number)
	local color = RING_COLORS[value] or RING_COLORS[2]
	local m = Instance.new("Model")
	m.Name = "RunRing_x" .. value
	local hoop = Instance.new("Part")
	hoop.Name = "Hoop"
	hoop.Anchored = true
	hoop.CanCollide = false
	hoop.CanQuery = false
	hoop.CanTouch = false
	hoop.CastShadow = false
	hoop.Material = Enum.Material.Neon
	hoop.Color = color
	hoop.Size = Vector3.one
	hoop.CFrame = CFrame.lookAt(pos, pos + c.toBase)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = RING_MESH
	mesh.Scale = Vector3.new(4, 4, 1.8)
	mesh.Parent = hoop
	hoop.Parent = m
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(110, 56)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 220
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "x" .. value
	t.TextColor3 = Color3.new(1, 1, 1)
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = color:Lerp(Color3.new(0, 0, 0), 0.6)
	st.Parent = t
	t.Parent = bb
	bb.Parent = hoop
	if value >= 5 then
		-- a beam of light, so you can see it (and decide to go for it) from far off
		local beam = Instance.new("Part")
		beam.Name = "Beam"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.6
		beam.Size = Vector3.new(1.2, 80, 1.2)
		beam.CFrame = CFrame.new(pos + Vector3.new(0, 44, 0))
		beam.Parent = m
	end
	m.Parent = c.folder
	-- a slow spin and bob
	local spin = TweenService:Create(
		hoop,
		TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = hoop.CFrame * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(25)) }
	)
	spin:Play()
	table.insert(c.rings, { pos = pos, value = value, model = m, taken = false })
end

-- a floating sign over a choice ("x5 RISKY!")
local function sign(c: Course, pos: Vector3, text: string, color: Color3)
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.one
	a.CFrame = CFrame.new(pos)
	a.Parent = c.folder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(200, 60)
	bb.MaxDistance = 260
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Parent = t
	t.Parent = bb
	bb.Parent = a
end

local function zone(c: Course, kind: string, cf: CFrame, size: Vector3, dir: Vector3?)
	table.insert(c.zones, { kind = kind, cf = cf, size = size, next = 0, dir = dir or c.toBase })
end

local function plainPart(c: Course, props: { [string]: any }): Part
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

local function collect(c: Course, r: Ring)
	r.taken = true
	local hoop = r.model:FindFirstChild("Hoop") :: BasePart?
	if hoop then
		local mesh = hoop:FindFirstChildOfClass("SpecialMesh")
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if mesh then
			TweenService:Create(mesh, info, { Scale = mesh.Scale * 2.2 }):Play()
		end
		TweenService:Create(hoop, info, { Transparency = 1 }):Play()
		local bb = hoop:FindFirstChildOfClass("BillboardGui")
		if bb then
			bb:Destroy()
		end
	end
	task.delay(0.35, function()
		r.model:Destroy()
	end)
	local color = RING_COLORS[r.value] or RING_COLORS[2]
	ChaseFx.play("Good", 1, 0.9 + r.value * 0.08)
	ChaseFx.play("Pop", 0.8, 1.3)
	ChaseFx.kick(5 + r.value)
	ChaseFx.pop("x" .. r.value .. "!", color, r.value >= 5)
	Net.event("RunRing"):FireServer(r.value)
	c.onRing(r.value)
end

-- along the route: d studs from the start towards the base, at x
local function at(c: Course, origin: Vector3, d: number, x: number, y: number): Vector3
	local p = origin + c.toBase * d
	return Vector3.new(x, y, p.Z)
end

local function themeAt(pos: Vector3)
	return THEMES[MapInfo.biomeAt(pos) or 1] or THEMES[1]
end

-- set-pieces ----------------------------------------------------------------------------------------------------

local function blockade(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local theme = themeAt(at(c, origin, d, (minX + maxX) / 2, g))
	local area = Config.PlayAreaX
	local gapW = 18
	local gapX = rng:NextNumber(minX + gapW, maxX - gapW)
	local h, depth = 18, 8
	local z = at(c, origin, d, 0, 0).Z
	local leftEnd, rightStart = gapX - gapW / 2, gapX + gapW / 2
	block(c, Vector3.new(leftEnd - area[1], h, depth), CFrame.new((area[1] + leftEnd) / 2, g + h / 2, z), theme)
	block(c, Vector3.new(area[2] - rightStart, h, depth), CFrame.new((rightStart + area[2]) / 2, g + h / 2, z), theme)
	ring(c, Vector3.new(gapX, g + 4, z), 2)
	return depth + 6
end

local function split(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local len = 90
	local mid = (minX + maxX) / 2
	local ridgeX = mid + rng:NextNumber(-1, 1) * (maxX - minX) * 0.2
	local mid3 = at(c, origin, d + len / 2, ridgeX, g)
	local theme = themeAt(mid3)
	block(c, Vector3.new(6, 14, len), CFrame.new(ridgeX, g + 7, mid3.Z), theme)
	-- the narrow lane (towards the nearer track edge) is the hard one
	local hardLeft = ridgeX - minX < maxX - ridgeX
	local hardX = if hardLeft then (minX + ridgeX) / 2 else (ridgeX + maxX) / 2
	local easyX = if hardLeft then (ridgeX + maxX) / 2 else (minX + ridgeX) / 2
	local hardW = if hardLeft then ridgeX - minX else maxX - ridgeX
	for i = 1, 3 do
		local p = at(c, origin, d + len * i / 4, hardX, g)
		block(c, Vector3.new(hardW - 3, 3.2, 3), CFrame.new(hardX, g + 1.6, p.Z), theme, true)
	end
	ring(c, at(c, origin, d + len * 0.5, easyX, g + 4), 2)
	ring(c, at(c, origin, d + len * 0.92, hardX, g + 4), 3)
	return len
end

local function zipline(
	c: Course,
	origin: Vector3,
	d: number,
	minX: number,
	maxX: number,
	g: number,
	room: number
): number
	local L = math.min(rng:NextNumber(100, 140), room - 30)
	if L < 70 then
		return 0
	end
	local x = if rng:NextNumber() < 0.5 then minX + 14 else maxX - 14
	local startP = at(c, origin, d, x, g)
	local endP = at(c, origin, d + L, x, g)
	local theme = themeAt(startP)
	-- start rock: a step (4) then the top (9)
	block(c, Vector3.new(8, 4, 6), CFrame.new(x, g + 2, startP.Z - c.toBase.Z * 9), theme, true)
	block(c, Vector3.new(12, 9, 12), CFrame.new(x, g + 4.5, startP.Z), theme, true)
	block(c, Vector3.new(1, 12, 1), CFrame.new(x, g + 15, startP.Z + c.toBase.Z * 4), theme, true)
	-- landing rock
	block(c, Vector3.new(14, 6, 14), CFrame.new(x, g + 3, endP.Z), themeAt(endP), true)
	block(c, Vector3.new(1, 12, 1), CFrame.new(x, g + 12, endP.Z - c.toBase.Z * 4), themeAt(endP), true)
	local a = Vector3.new(x, g + 20, startP.Z + c.toBase.Z * 4)
	local b = Vector3.new(x, g + 17, endP.Z - c.toBase.Z * 4)
	local cable = Instance.new("Part")
	cable.Anchored = true
	cable.CanCollide = false
	cable.CanQuery = false
	cable.CanTouch = false
	cable.Material = Enum.Material.Metal
	cable.Color = Color3.fromRGB(40, 40, 45)
	cable.Size = Vector3.new(0.3, 0.3, (b - a).Magnitude)
	cable.CFrame = CFrame.lookAt((a + b) / 2, b)
	cable.Parent = c.folder
	table.insert(c.zips, { a = a, b = b, cable = cable })
	-- a sign on the start rock
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 40)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.MaxDistance = 200
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "ZIPLINE ⬆"
	t.TextColor3 = Color3.fromRGB(255, 230, 120)
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Parent = t
	t.Parent = bb
	bb.Parent = cable
	bb.Adornee = nil
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = Vector3.new(x, g + 10, startP.Z)
	anchor.Parent = cable
	bb.Adornee = anchor
	ring(c, a:Lerp(b, 0.55) - Vector3.new(0, 3.5, 0), 5)
	return L + 10
end

local function pads(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local theme = themeAt(at(c, origin, d, (minX + maxX) / 2, g))
	local n = 3
	for i = 1, n do
		local x = minX + (maxX - minX) * (i - 0.5) / n
		local p = at(c, origin, d, x, g)
		local pad = Instance.new("Part")
		pad.Anchored = true
		pad.CanCollide = false
		pad.CanQuery = false
		pad.CanTouch = false
		pad.Material = Enum.Material.Neon
		pad.Color = Color3.fromRGB(90, 230, 255)
		pad.Size = Vector3.new(9, 0.4, 9)
		pad.CFrame = CFrame.new(x, g + 0.25, p.Z)
		pad.Parent = c.folder
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Top
		sg.LightInfluence = 0
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = "⏫"
		l.Rotation = if c.toBase.Z < 0 then 0 else 180
		l.Parent = sg
		sg.Parent = pad
		table.insert(c.pads, { cf = pad.CFrame, size = pad.Size, next = 0 })
		if i == 2 then
			ring(c, at(c, origin, d + 20, x, g + 13), 3)
		end
	end
	local _ = theme
	return 40
end

local function slalom(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local mid = (minX + maxX) / 2
	local swing = (maxX - minX) * 0.3
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	for i = 0, 3 do
		ring(c, at(c, origin, d + i * 20, mid + side * swing, g + 4), 2)
		side = -side
	end
	return 70
end

local function chute(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local x = if rng:NextNumber() < 0.5 then minX + 16 else maxX - 16
	local theme = themeAt(at(c, origin, d, x, g))
	local H, rampL, topL, slideL = 14, 30, 10, 85
	local z0 = at(c, origin, d, x, g).Z
	local dirZ = c.toBase.Z
	-- the ramp up (a wedge rising towards the base)
	local rampMid = Vector3.new(x, g + H / 2, z0 + dirZ * rampL / 2)
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.CanTouch = false
	wedge.Size = Vector3.new(10, H, rampL)
	wedge.CFrame = CFrame.lookAt(rampMid, rampMid - c.toBase)
	wedge.Material = Enum.Material.Rock
	wedge.Color = theme.Rock
	wedge.Parent = c.folder
	-- the platform
	local topZ = z0 + dirZ * (rampL + topL / 2)
	block(c, Vector3.new(10, H, topL), CFrame.new(x, g + H / 2, topZ), theme, true)
	-- the slide down
	local a = Vector3.new(x, g + H, z0 + dirZ * (rampL + topL))
	local b = Vector3.new(x, g + 0.5, z0 + dirZ * (rampL + topL + slideL))
	local mid = (a + b) / 2
	local slide = plainPart(c, {
		Name = "Chute",
		Size = Vector3.new(8, 1, (b - a).Magnitude),
		CFrame = CFrame.lookAt(mid, b) * CFrame.new(0, -0.5, 0),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(80, 200, 255),
		Transparency = 0.2,
	})
	for _, side in { -1, 1 } do
		plainPart(c, {
			Name = "Rail",
			Size = Vector3.new(0.6, 2.4, (b - a).Magnitude),
			CFrame = CFrame.lookAt(mid, b) * CFrame.new(side * 4.3, 0.7, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(255, 255, 255),
		})
	end
	zone(c, "Chute", slide.CFrame * CFrame.new(0, 2.5, 0), slide.Size + Vector3.new(0, 5, 0), (b - a).Unit)
	ring(c, b + c.toBase * 6 + Vector3.new(0, 4, 0), 3)
	sign(c, Vector3.new(x, g + 22, z0), "SLIDE x3", Color3.fromRGB(80, 200, 255))
	return rampL + topL + slideL + 8
end

local function bounce(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local theme = themeAt(at(c, origin, d, (minX + maxX) / 2, g))
	local area = Config.PlayAreaX
	local len = 60
	local midZ = at(c, origin, d + len / 2, 0, 0).Z
	-- the mud pit, wall to wall
	local pit = plainPart(c, {
		Name = "Mud",
		Size = Vector3.new(area[2] - area[1], 0.4, len),
		CFrame = CFrame.new((area[1] + area[2]) / 2, g + 0.15, midZ),
		Material = Enum.Material.Mud,
		Color = theme.Color:Lerp(Color3.fromRGB(70, 45, 25), 0.6),
		CanCollide = false,
	})
	zone(c, "Mud", pit.CFrame * CFrame.new(0, 3, 0), pit.Size + Vector3.new(0, 6, 0))
	-- mushrooms in two lanes
	for lane = 1, 2 do
		local x = minX + (maxX - minX) * (if lane == 1 then 0.3 else 0.7)
		for i = 1, 3 do
			local p = at(c, origin, d + len * (i - 0.5) / 3, x, g)
			plainPart(c, {
				Name = "MushroomStem",
				Size = Vector3.new(1.5, 2, 1.5),
				CFrame = CFrame.new(p.X, g + 1, p.Z),
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(245, 235, 220),
				CanCollide = false,
			})
			local cap = plainPart(c, {
				Name = "Mushroom",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.2, 7, 7),
				CFrame = CFrame.new(p.X, g + 2.4, p.Z) * CFrame.Angles(0, 0, math.pi / 2),
				Material = Enum.Material.SmoothPlastic,
				Color = if lane == 1 then Color3.fromRGB(255, 80, 120) else Color3.fromRGB(120, 255, 120),
				CanCollide = false,
			})
			zone(c, "Bounce", CFrame.new(cap.Position + Vector3.new(0, 2.5, 0)), Vector3.new(7, 5, 7))
			if i == 2 then
				ring(c, Vector3.new(p.X, g + 15, p.Z), 3)
			end
		end
	end
	sign(c, at(c, origin, d - 6, (minX + maxX) / 2, g + 14), "BOUNCE! (mud is slow)", Color3.fromRGB(255, 120, 160))
	return len + 6
end

local function highRoad(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local x = if rng:NextNumber() < 0.5 then minX + 10 else maxX - 10
	local theme = themeAt(at(c, origin, d, x, g))
	local len = 80
	for i = 1, 3 do
		local p = at(c, origin, d + (i - 1) * 6, x, g)
		block(c, Vector3.new(8, 4 * i, 6), CFrame.new(x, g + 2 * i, p.Z), theme, true)
	end
	local ridgeStart = d + 18
	local mid = at(c, origin, ridgeStart + len / 2, x, g)
	block(c, Vector3.new(4, 12, len), CFrame.new(x, g + 6, mid.Z), theme, true)
	ring(c, at(c, origin, ridgeStart + len * 0.45, x, g + 16), 2)
	ring(c, at(c, origin, ridgeStart + len - 4, x, g + 16), 5)
	local lowX = (minX + maxX) / 2 + (if x < (minX + maxX) / 2 then 25 else -25)
	ring(c, at(c, origin, ridgeStart + len / 2, lowX, g + 4), 2)
	sign(c, at(c, origin, d - 4, x, g + 16), "HIGH ROAD x5 - RISKY!", Color3.fromRGB(255, 200, 40))
	sign(c, at(c, origin, d - 4, lowX, g + 10), "SAFE x2", Color3.fromRGB(80, 255, 120))
	return ridgeStart - d + len + 4
end

local function strips(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local mid = (minX + maxX) / 2
	for i = 0, 2 do
		local x = mid + (i - 1) * 22
		local p = at(c, origin, d + i * 18, x, g)
		local strip = plainPart(c, {
			Name = "SpeedStrip",
			Size = Vector3.new(10, 0.3, 12),
			CFrame = CFrame.lookAt(Vector3.new(x, g + 0.2, p.Z), Vector3.new(x, g + 0.2, p.Z) + c.toBase),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 220, 60),
			CanCollide = false,
		})
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Top
		sg.LightInfluence = 0
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.Text = "^^"
		l.TextColor3 = Color3.fromRGB(255, 255, 255)
		l.Parent = sg
		sg.Parent = strip
		zone(c, "Strip", strip.CFrame * CFrame.new(0, 3, 0), Vector3.new(10, 6, 12))
	end
	ring(c, at(c, origin, d + 60, mid, g + 4), 2)
	return 64
end

local function gates(c: Course, origin: Vector3, d: number, minX: number, maxX: number, g: number): number
	local theme = themeAt(at(c, origin, d, (minX + maxX) / 2, g))
	local area = Config.PlayAreaX
	local z = at(c, origin, d, 0, 0).Z
	local h, depth, doorW = 18, 8, 14
	local values = { 2, 3, 5 }
	-- shuffle which door is which
	for i = #values, 2, -1 do
		local j = rng:NextInteger(1, i)
		values[i], values[j] = values[j], values[i]
	end
	local doors = {}
	for i = 1, 3 do
		doors[i] = minX + (maxX - minX) * (i - 0.5) / 3
	end
	local edges = { area[1] }
	for i = 1, 3 do
		table.insert(edges, doors[i] - doorW / 2)
		table.insert(edges, doors[i] + doorW / 2)
	end
	table.insert(edges, area[2])
	for k = 1, #edges, 2 do
		local a, b = edges[k], edges[k + 1]
		if b - a > 0.5 then
			block(c, Vector3.new(b - a, h, depth), CFrame.new((a + b) / 2, g + h / 2, z), theme)
		end
	end
	for i = 1, 3 do
		local v = values[i]
		local x = doors[i]
		if v == 3 then
			block(c, Vector3.new(doorW, 3.2, 3), CFrame.new(x, g + 1.6, z), theme, true) -- a hurdle: jump it
		elseif v == 5 then
			block(c, Vector3.new(doorW, 9, 3), CFrame.new(x, g + 4.5, z), theme, true) -- only a double jump clears it
		end
		local text = if v == 5 then "x5 (double jump!)" elseif v == 3 then "x3 (jump)" else "x2"
		sign(c, Vector3.new(x, g + h + 4, z), text, RING_COLORS[v])
		ring(c, at(c, origin, d + 12, x, g + 4), v)
	end
	return depth + 14
end

-- the run -------------------------------------------------------------------------------------------------------

-- origin: where you start (your position when the chase starts). Builds pieces from a little ahead of you to just
-- before the white line.
function RunCourse.build(parent: Instance, origin: Vector3, onRing: (number) -> ()): Course
	local toBase = MapInfo.toBase()
	local folder = Instance.new("Folder")
	folder.Name = "RunCourse"
	folder.Parent = parent
	local c: Course = {
		folder = folder,
		rings = {},
		zips = {},
		pads = {},
		zones = {},
		riding = nil,
		zipCooldown = 0,
		toBase = toBase,
		onRing = onRing,
	}
	local line = MapInfo.dangerLine()
	local total = (line - origin):Dot(toBase)
	local kinds = { "Blockade", "Split", "Zipline", "Pads", "Slalom", "Chute", "Bounce", "HighRoad", "Strips", "Gates" }
	local last = ""
	local d = 55
	while d < total - 45 do
		local p = origin + toBase * d
		local biome = MapInfo.biomeAt(Vector3.new(-8, 1, p.Z)) or 1
		local minV, maxV = MapInfo.bounds(biome)
		if not minV then
			break
		end
		local minX, maxX = minV.X + 6, maxV.X - 6
		local g = maxV.Y
		local kind
		repeat
			kind = kinds[rng:NextInteger(1, #kinds)]
		until kind ~= last
		last = kind
		local used = 0
		if kind == "Blockade" then
			used = blockade(c, origin, d, minX, maxX, g)
		elseif kind == "Split" and total - d > 130 then
			used = split(c, origin, d, minX, maxX, g)
		elseif kind == "Zipline" then
			used = zipline(c, origin, d, minX, maxX, g, total - d)
		elseif kind == "Pads" then
			used = pads(c, origin, d, minX, maxX, g)
		elseif kind == "Slalom" then
			used = slalom(c, origin, d, minX, maxX, g)
		elseif kind == "Chute" and total - d > 150 then
			used = chute(c, origin, d, minX, maxX, g)
		elseif kind == "Bounce" then
			used = bounce(c, origin, d, minX, maxX, g)
		elseif kind == "HighRoad" and total - d > 120 then
			used = highRoad(c, origin, d, minX, maxX, g)
		elseif kind == "Strips" then
			used = strips(c, origin, d, minX, maxX, g)
		elseif kind == "Gates" then
			used = gates(c, origin, d, minX, maxX, g)
		end
		if used == 0 then
			used = slalom(c, origin, d, minX, maxX, g)
		end
		d += used + rng:NextNumber(28, 48)
	end
	return c
end

function RunCourse.isRiding(c: Course?): boolean
	return c ~= nil and c.riding ~= nil
end

local function release(c: Course, hrp: BasePart, humanoid: Humanoid)
	local r = c.riding
	if not r then
		return
	end
	c.riding = nil
	c.zipCooldown = os.clock() + 1
	r.handle:Destroy()
	if r.whirr then
		r.whirr:Stop()
		r.whirr:Destroy()
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local dir = (r.zip.b - r.zip.a).Unit
	hrp.AssemblyLinearVelocity = Vector3.new(dir.X, 0, dir.Z) * 30 + Vector3.new(0, 12, 0)
	ChaseFx.play("Whoosh", 1, 0.9)
	ChaseFx.kick(-4)
end

function RunCourse.update(c: Course, hrp: BasePart, humanoid: Humanoid, dt: number)
	local now = os.clock()
	local pos = hrp.Position
	-- rings
	for _, r in c.rings do
		if not r.taken and (pos - r.pos).Magnitude < 7 then
			collect(c, r)
		end
	end
	-- riding a zipline
	local r = c.riding
	if r then
		local len = (r.zip.b - r.zip.a).Magnitude
		local speed = math.max(70, humanoid.WalkSpeed * 1.7)
		r.t += speed * dt / len
		if r.t >= 1 or humanoid.Health <= 0 then
			release(c, hrp, humanoid)
			return
		end
		local p = r.zip.a:Lerp(r.zip.b, r.t) - Vector3.new(0, math.sin(math.pi * r.t) * 3, 0)
		local dir = (r.zip.b - r.zip.a).Unit
		r.handle.CFrame = CFrame.lookAt(p, p + dir)
		hrp.CFrame =
			CFrame.lookAt(p - Vector3.new(0, 3.4, 0), p - Vector3.new(0, 3.4, 0) + Vector3.new(dir.X, 0, dir.Z))
		hrp.AssemblyLinearVelocity = Vector3.zero
		return
	end
	-- grabbing one: stand on the start rock under the cable's end
	if now >= c.zipCooldown then
		for _, z in c.zips do
			local flat = Vector3.new(pos.X - z.a.X, 0, pos.Z - z.a.Z)
			if flat.Magnitude < 7 and pos.Y > z.a.Y - 13 and pos.Y < z.a.Y + 2 then
				local handle = Instance.new("Part")
				handle.Anchored = true
				handle.CanCollide = false
				handle.CanQuery = false
				handle.CanTouch = false
				handle.Material = Enum.Material.Metal
				handle.Color = Color3.fromRGB(230, 60, 60)
				handle.Size = Vector3.new(2.6, 0.35, 0.35)
				handle.CFrame = CFrame.new(z.a)
				handle.Parent = c.folder
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
				c.riding = { zip = z, t = 0, handle = handle, whirr = ChaseFx.play("Zip", 1.2, 1.4) }
				ChaseFx.play("Boost", 0.9, 1.1)
				ChaseFx.kick(10)
				ChaseFx.pop("ZIPLINE!", Color3.fromRGB(255, 230, 120))
				return
			end
		end
	end
	-- zones
	for _, z in c.zones do
		local l = z.cf:PointToObjectSpace(pos)
		if math.abs(l.X) < z.size.X / 2 and math.abs(l.Y) < z.size.Y / 2 and math.abs(l.Z) < z.size.Z / 2 then
			if z.kind == "Mud" then
				Movement.slow(0.25)
			elseif z.kind == "Chute" then
				Movement.boost(2, 0.4)
				if now >= z.next then
					z.next = now + 3
					ChaseFx.play("Whoosh", 1, 0.8)
					ChaseFx.play("Zip", 0.8, 1.8)
					ChaseFx.kick(10)
					ChaseFx.pop("WHEEE!", Color3.fromRGB(80, 200, 255))
				end
				local v = hrp.AssemblyLinearVelocity
				local along = Vector3.new(z.dir.X, 0, z.dir.Z).Unit
				if Vector3.new(v.X, 0, v.Z):Dot(along) < 55 then
					hrp.AssemblyLinearVelocity = Vector3.new(along.X * 55, v.Y, along.Z * 55)
				end
			elseif z.kind == "Strip" and now >= z.next then
				z.next = now + 0.8
				Movement.boost(1.6, 1.2)
				ChaseFx.play("Boost", 0.8, 1.2)
				ChaseFx.kick(8)
			elseif z.kind == "Bounce" and now >= z.next and hrp.AssemblyLinearVelocity.Y < 5 then
				z.next = now + 0.5
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				hrp.AssemblyLinearVelocity = c.toBase * 32 + Vector3.new(0, 62, 0)
				ChaseFx.play("Pop", 1, 0.7)
				ChaseFx.play("Boost", 0.6, 1.4)
				ChaseFx.kick(6)
			end
		end
	end
	-- launch pads
	for _, pad in c.pads do
		if now >= pad.next then
			local l = pad.cf:PointToObjectSpace(pos)
			if math.abs(l.X) < pad.size.X / 2 and math.abs(l.Z) < pad.size.Z / 2 and l.Y > -1 and l.Y < 6 then
				pad.next = now + 0.8
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				hrp.AssemblyLinearVelocity = c.toBase * 60 + Vector3.new(0, 72, 0)
				ChaseFx.play("Boost", 1, 1)
				ChaseFx.kick(12)
				ChaseFx.pop("LAUNCH!", Color3.fromRGB(90, 230, 255))
			end
		end
	end
end

function RunCourse.destroy(c: Course?)
	if not c then
		return
	end
	local _, humanoid = nil, nil
	local character = player.Character
	humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if c.riding and humanoid and hrp then
		release(c, hrp, humanoid)
	end
	c.folder:Destroy()
end

return RunCourse
