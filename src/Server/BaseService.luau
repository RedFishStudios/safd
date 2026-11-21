-- Base plots: builds a starter base on every plot in Workspace.Bases.BaseLayout, assigns a random
-- free plot to each player, adds their treadmill and the billboard sign, and spawns them there.
--
-- Plot "anchor" convention: CFrame at the front-centre edge of the base at floor level, LookVector
-- pointing OUT of the base. In anchor space the inside of the base is +Z, the outside is -Z.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Progression = require(Shared.Progression)
local MapInfo = require(Shared.MapInfo)
local Net = require(Shared.Net)

local BaseService = {}

export type Plot = {
	Index: number,
	Anchor: CFrame,
	Model: Model,
	Owner: Player?,
	Bounds: { MinX: number, MaxX: number, MinZ: number, MaxZ: number },
	FloorY: number,
	Treadmill: Model?,
	TreadmillSpot: Vector3?,
	TreadmillTier: number?,
	Tier: number,
	Prefer: Vector3?, -- (a point on the side its treadmill should go)
	Facing: Vector3?, -- (the row's end pens' treadmills stand at 45 degrees)
	Sign: { Gui: BillboardGui, Avatar: ImageLabel, Name: TextLabel }?,
	WorldMin: Vector3,
	WorldMax: Vector3,
}

local plots: { Plot } = {}
local plotOf: { [Player]: Plot } = {}
local basesFolder: Folder
local rng = Random.new()

-- Bases are the reference game's wooden fence pens ("[NEW] Feed and Rob Animals", Plots.BaseN.ToUpdate.StarterPen):
-- 44 studs wide, a gate gap in the middle of the front, standing straight on the ground. Each base upgrade makes
-- the pen deeper (its back fence moves back), like the reference's pen upgrades.
local PEN_WIDTH = 44.16
local RAIL_COLOR = Color3.fromRGB(162, 81, 0)
local POST_COLOR = Color3.fromRGB(86, 66, 54)
local MAX_TIER = #Progression.Base

local function penDepth(tier: number): number
	return 49 + (math.clamp(tier, 1, MAX_TIER) - 1) * 2
end

-- Front-centre of a layout marker's pen at ground level, facing out of the pen. The row of plots faces the white
-- line; the two plots off the row (the corners) stand just past the ends of the row and face in towards the middle,
-- like the reference's side plots, so they never sit in front of another base's gate.
local function plotAnchor(
	minV: Vector3,
	maxV: Vector3,
	rowZ: number,
	line: Vector3,
	rowMinX: number,
	rowMaxX: number
): CFrame
	local center = (minV + maxV) / 2
	if math.abs(center.Z - rowZ) < 30 then
		local front = if math.abs(maxV.Z - line.Z) < math.abs(minV.Z - line.Z) then maxV.Z else minV.Z
		local outward = if front == maxV.Z then 1 else -1
		local pos = Vector3.new(center.X, minV.Y, front)
		return CFrame.lookAt(pos, pos + Vector3.new(0, 0, outward))
	end
	local left = center.X < (rowMinX + rowMaxX) / 2
	local outward = if left then 1 else -1
	-- (a little past the row's ends, so the end pens' treadmills fit beside their gates on the outer side)
	local front = if left then rowMinX - PEN_WIDTH / 2 - 10 else rowMaxX + PEN_WIDTH / 2 + 6
	local pos = Vector3.new(front, minV.Y, center.Z)
	return CFrame.lookAt(pos, pos + Vector3.new(outward, 0, 0))
end

local function groundY(position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- skip particle volumes like the biomes' *_specks parts
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position.Y else position.Y
end

local function boxHit(position: Vector3, radius: number, minV: Vector3, maxV: Vector3): boolean
	return position.X > minV.X - radius
		and position.X < maxV.X + radius
		and position.Z > minV.Z - radius
		and position.Z < maxV.Z + radius
end

local blockers: { { Vector3 } } = {} -- spawn stands etc. that treadmills must not overlap

-- Treadmills stand outside every pen (at its biggest), away from other treadmills and the spawn stands, and only
-- in front of their own base: never inside a base or behind one.
local function spotIsFree(position: Vector3, self: Plot): boolean
	local rel = self.Anchor:PointToObjectSpace(position)
	if rel.Z > -8 then
		return false -- (not in front of its own gate)
	end
	for _, other in plots do
		if boxHit(position, 8, other.WorldMin, other.WorldMax) then
			return false
		end
		if other ~= self then
			-- keep clear of the space in front of every other base's gate
			local gate = (other.Anchor * CFrame.new(0, 0, -10)).Position
			if (Vector2.new(gate.X, gate.Z) - Vector2.new(position.X, position.Z)).Magnitude < 14 then
				return false
			end
		end
		if other.TreadmillSpot and other ~= self then
			local p = other.TreadmillSpot
			if (Vector2.new(p.X, p.Z) - Vector2.new(position.X, position.Z)).Magnitude < 18 then
				return false
			end
		end
	end
	for _, box in blockers do
		if boxHit(position, 7, box[1], box[2]) then
			return false
		end
	end
	return true
end

-- The reference game's base layout ("[NEW] Feed and Rob Animals", Plots.Base1): its pen's gate line, centred,
-- facing out of the pen. Our pens are the same width, so its treadmill pad and upgrade signs map across 1:1.
local REF_ANCHOR = CFrame.lookAt(Vector3.new(-3.52, -0.42, 82.4), Vector3.new(-3.52, -0.42, 81.4))
local REF_TREADMILL_PAD = Vector3.new(-22.79, -0.37, 66.07)

local function fromRef(plot: Plot, worldCF: CFrame): CFrame
	local rel = REF_ANCHOR:ToObjectSpace(worldCF)
	return plot.Anchor * CFrame.new(rel.X, rel.Y, rel.Z) * rel.Rotation
end

-- Where the treadmill goes: the reference's pad spot (in front of the pen, to the left of the gate), else the same
-- spot to the right, else a little further out in front. The runner always faces out, towards the biomes.
local function treadmillSpot(plot: Plot): Vector3
	local ref = plot.Anchor:PointToObjectSpace(fromRef(plot, CFrame.new(REF_TREADMILL_PAD)).Position)
	-- pens with a preferred side put theirs there first: the row's end pens on the outer side of the gate (towards
	-- their side pen), the side pens on the side away from the row
	local sides = { 1, -1 }
	if plot.Prefer then
		local a = (plot.Anchor * CFrame.new(ref.X, 0, ref.Z)).Position
		local b = (plot.Anchor * CFrame.new(-ref.X, 0, ref.Z)).Position
		if (b - plot.Prefer).Magnitude < (a - plot.Prefer).Magnitude then
			sides = { -1, 1 }
		end
	end
	local out = 0
	for _, dz in { out, out - 6, out - 12, out - 18 } do
		for _, side in sides do
			local p = (plot.Anchor * CFrame.new(ref.X * side, 0, ref.Z + dz)).Position
			if spotIsFree(p, plot) then
				return p
			end
		end
	end
	return (plot.Anchor * CFrame.new(ref.X, 0, ref.Z - 24)).Position
end

local function treadmillTemplate(tier: number): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("TreadmillTiers")
	local row = Progression.Treadmill[tier] or Progression.Treadmill[1]
	local found = folder and (folder:FindFirstChild(row.Model) or folder:FindFirstChild("BasicTreadmill"))
	return found or (assets and assets:FindFirstChild("BasicTreadmill", true))
end

-- lowest point of the visible parts (effect parts can hang below a model)
local function visibleBottom(m: Model): number
	local lo = math.huge
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf, s = p.CFrame, p.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						lo = math.min(lo, cf:PointToWorldSpace(Vector3.new(x * s.X, y * s.Y, z * s.Z)).Y)
					end
				end
			end
		end
	end
	return lo
end

local function placeTreadmill(plot: Plot, tier: number)
	local old = plot.Treadmill or plot.Model:FindFirstChild("Treadmill")
	local src = treadmillTemplate(tier)
	local model: Model
	if src and src:IsA("Model") then
		model = src:Clone()
	else
		model = Instance.new("Model")
		local part = if src and src:IsA("BasePart") then src:Clone() else Instance.new("Part")
		part.Name = "Body"
		part.Parent = model
		model.PrimaryPart = part
	end
	model.Name = "Treadmill"
	local body = (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)) :: BasePart
	model.PrimaryPart = body
	for _, part in Util.parts(model) do
		part.Anchored = true
		part.CanCollide = false -- the client holds the runner on the belt; a solid hull would block walking in
		part.CanTouch = false
	end
	-- Sized like the reference: the body as long as its treadmill pad (13.42 studs), at most 16 studs across.
	local _, size = model:GetBoundingBox()
	local long = math.max(body.Size.X, body.Size.Z)
	local s = Config.TreadmillPadLength / long
	if math.max(size.X, size.Z) * s > 16 then
		s = 16 / math.max(size.X, size.Z)
	end
	model:ScaleTo(model:GetScale() * s)

	local spot = plot.TreadmillSpot or treadmillSpot(plot)
	plot.TreadmillSpot = spot
	local insideBase = boxHit(spot, 0, plot.WorldMin, plot.WorldMax)
	local y = if insideBase then plot.FloorY else groundY(spot, { basesFolder })
	local facing = plot.Facing or Vector3.new(plot.Anchor.LookVector.X, 0, plot.Anchor.LookVector.Z).Unit -- towards the biomes
	local target = CFrame.lookAt(spot, spot + facing)
	model:PivotTo(target)
	local cf = model:GetBoundingBox()
	local bottom = visibleBottom(model)
	model:PivotTo(target + Vector3.new(spot.X - cf.Position.X, y - bottom, spot.Z - cf.Position.Z))
	model:SetAttribute("Owner", if plot.Owner then plot.Owner.UserId else 0)
	model:SetAttribute("Tier", tier)
	-- only a claimed base has a treadmill (user 2026-11-22): an empty one keeps it out of the world
	model.Parent = if plot.Owner then plot.Model else nil
	plot.Treadmill = model
	plot.TreadmillTier = tier
	if old then
		old:Destroy()
	end
end

-- Upgrade signs (the reference's PlotUpgrade / TreadmillUpgrade models, on taller posts and a bit bigger like
-- its raiseSigns). Their SurfaceGui stays disabled here: the owner's client shows its own copy and handles clicks.
local SIGN_MODELS = { "PlotUpgrade", "TreadmillUpgrade" }
local SIGN_BOTTOM, SIGN_SCALE = 5, 1.3

local function placeSigns(plot: Plot)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("RefUI")
	if not folder then
		warn("[BaseService] ReplicatedStorage.Assets.RefUI (upgrade signs) not found")
		return
	end
	for _, name in SIGN_MODELS do
		local src = folder:FindFirstChild(name)
		if not src then
			continue
		end
		local m = src:Clone() :: Model
		m:PivotTo(fromRef(plot, m:GetPivot()))
		if name == "TreadmillUpgrade" and plot.TreadmillSpot then
			-- keep the reference's offset from the treadmill wherever it ended up (mirrored when it's on the right)
			-- (worked out in the treadmill's own frame, so the board turns with a treadmill that stands at an angle, and
			-- its face always looks back at you, the way you walk up to the treadmill)
			local refPad = plot.Anchor:PointToObjectSpace(fromRef(plot, CFrame.new(REF_TREADMILL_PAD)).Position)
			local spot = plot.Anchor:PointToObjectSpace(plot.TreadmillSpot)
			local rel = CFrame.new(refPad):ToObjectSpace(plot.Anchor:ToObjectSpace(m:GetPivot()))
			local off, right = rel.Position, rel.RightVector
			if (spot.X > 0) ~= (refPad.X > 0) then
				-- a true mirror image: mirror the board's sideways axis (its face is its Left side). Mirroring the look
				-- vector instead turned the face round to the back (the left-hand pens' signs, 2026-11-19).
				off = Vector3.new(-off.X, off.Y, off.Z)
				right = Vector3.new(-right.X, right.Y, right.Z)
			end
			local facing = plot.Facing or plot.Anchor.LookVector
			local f = plot.Anchor:VectorToObjectSpace(Vector3.new(facing.X, 0, facing.Z)).Unit
			local tread = CFrame.lookAt(spot, spot + f)
			m:PivotTo(plot.Anchor * tread * CFrame.fromMatrix(off, right, Vector3.yAxis))
		end
		local sign = m:FindFirstChild("Sign") :: BasePart
		local post = m:FindFirstChild("Support") :: BasePart?
		local probe = if post then post.Position else sign.Position
		local inside = boxHit(probe, 0, plot.WorldMin, plot.WorldMax)
		local gy = if inside then plot.FloorY else groundY(probe, { basesFolder, m })
		local oldBottom = if post then post.Position.Y - post.Size.Y / 2 else sign.Position.Y - sign.Size.Y / 2 - 0.6
		m:PivotTo(m:GetPivot() + Vector3.new(0, gy - oldBottom, 0))
		local boardSize = Vector3.new(sign.Size.X, sign.Size.Y * SIGN_SCALE, sign.Size.Z * SIGN_SCALE)
		sign.Size = boardSize
		sign.CFrame = sign.CFrame + Vector3.new(0, gy + SIGN_BOTTOM + boardSize.Y / 2 - sign.Position.Y, 0)
		if post then
			local h = SIGN_BOTTOM + 0.5
			post.Size = Vector3.new(post.Size.X, h, post.Size.Z)
			post.CFrame = post.CFrame + Vector3.new(0, gy + h / 2 - post.Position.Y, 0)
		end
		for _, part in Util.parts(m) do
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
		end
		m:SetAttribute("Kind", if name == "PlotUpgrade" then "Base" else "Treadmill")
		m.Parent = plot.Model
	end
end

local function fillSign(model: Instance?, info: string, level: string, price: number?)
	local sign = model and model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SurfaceGui")
	if not (model and gui) then
		return
	end
	local function text(n: string, t: string)
		local l = gui:FindFirstChild(n)
		if l and l:IsA("TextLabel") and l.Text ~= t then
			l.Text = t
		end
	end
	text("Info", info)
	text("Level", level)
	local frame = gui:FindFirstChild("Frame")
	local up = frame and frame:FindFirstChild("Upgrade")
	if up and up:IsA("GuiObject") then
		up.Visible = price ~= nil
		up.LayoutOrder = 1
		local c = up:FindFirstChild("Cost")
		if c and c:IsA("TextLabel") and price then
			c.Text = "$" .. Progression.short(price)
		end
	end
	local rb = frame and frame:FindFirstChild("RobuxUpgrade")
	if rb and rb:IsA("GuiObject") then
		rb.Visible = false -- no Robux skip products set up yet
	end
	model:SetAttribute("Price", price or -1)
end

-- Writes the owner's levels and next prices on their base's upgrade signs.
function BaseService.updateUpgradeSigns(player: Player, data: any)
	local plot = plotOf[player]
	if not plot or not data then
		return
	end
	local baseTier = data.BaseTier or 1
	local slots = Progression.Base[baseTier].PetSlots
	local count = #data.Placed
	local nextBase = Progression.Base[baseTier + 1]
	if nextBase then
		fillSign(
			plot.Model:FindFirstChild("PlotUpgrade"),
			`Upgrade Base ({count}/{slots})`,
			`Lv. {baseTier} > Lv. {baseTier + 1}`,
			nextBase.Price
		)
	else
		fillSign(plot.Model:FindFirstChild("PlotUpgrade"), `Base ({count}/{slots})`, `Lv. {baseTier} (MAX)`, nil)
	end
	local tier = data.TreadmillLevel or 1
	local nextMill = Progression.Treadmill[tier + 1]
	if nextMill then
		fillSign(
			plot.Model:FindFirstChild("TreadmillUpgrade"),
			"Upgrade Treadmill",
			`Lv. {tier} > Lv. {tier + 1}`,
			nextMill.Price
		)
	else
		fillSign(plot.Model:FindFirstChild("TreadmillUpgrade"), "Treadmill", `Lv. {tier} (MAX)`, nil)
	end
end

local function fencePart(parent: Instance, size: Vector3, cf: CFrame, color: Color3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Plastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
end

-- One straight run of fence between two pen-space points (x across, z into the pen): posts at both ends of every
-- segment and three rails per segment, like the reference's fence models. `gap` leaves that segment open (the gate).
local RAIL_HEIGHTS = { 0.71, 2.06, 3.46 }
local function fenceRun(parent: Instance, plot: Plot, a: Vector2, b: Vector2, segment: number, gap: number?)
	local span = b - a
	local count = math.max(1, math.round(span.Magnitude / segment))
	local step = span.Magnitude / count
	local unit = span.Unit
	local function world(p: Vector2, height: number): Vector3
		local w = (plot.Anchor * CFrame.new(p.X, 0, p.Y)).Position
		return Vector3.new(w.X, plot.FloorY + height, w.Z)
	end
	local along = (plot.Anchor:VectorToWorldSpace(Vector3.new(unit.X, 0, unit.Y))).Unit
	for i = 0, count do
		local at = world(a + unit * step * i, 1.86)
		fencePart(parent, Vector3.new(1, 4, 1), CFrame.lookAt(at, at + along), POST_COLOR)
	end
	for i = 1, count do
		if i ~= gap then
			for _, h in RAIL_HEIGHTS do
				local mid = world(a + unit * step * (i - 0.5), h)
				fencePart(parent, Vector3.new(0.5, 0.6, step - 0.8), CFrame.lookAt(mid, mid + along), RAIL_COLOR)
			end
		end
	end
end

local function setBounds(plot: Plot, depth: number)
	plot.Bounds = { MinX = -PEN_WIDTH / 2 + 3, MaxX = PEN_WIDTH / 2 - 3, MinZ = 3, MaxZ = depth - 3 }
	local model = plot.Model
	model:SetAttribute("MinX", plot.Bounds.MinX)
	model:SetAttribute("MaxX", plot.Bounds.MaxX)
	model:SetAttribute("MinZ", plot.Bounds.MinZ)
	model:SetAttribute("MaxZ", plot.Bounds.MaxZ)
	local c = (plot.Anchor * CFrame.new(0, 0, depth / 2)).Position
	model:SetAttribute("Center", Vector3.new(c.X, plot.FloorY, c.Z)) -- (the base marker floats over this)
end

-- (Re)builds the plot's pen for a base tier: deeper with every level.
local function setBaseModel(plot: Plot, tier: number)
	if plot.Tier == tier and plot.Model:FindFirstChild("Pen") then
		return
	end
	local old = plot.Model:FindFirstChild("Pen")
	if old then
		old:Destroy()
	end
	local depth = penDepth(tier)
	local w = PEN_WIDTH / 2
	local pen = Instance.new("Model")
	pen.Name = "Pen"
	fenceRun(pen, plot, Vector2.new(-w, 0), Vector2.new(w, 0), 8.83, 3) -- front, the gate in the middle
	fenceRun(pen, plot, Vector2.new(-w, depth), Vector2.new(w, depth), 8.83)
	fenceRun(pen, plot, Vector2.new(-w, 0), Vector2.new(-w, depth), 10.5)
	fenceRun(pen, plot, Vector2.new(w, 0), Vector2.new(w, depth), 10.5)
	pen.Parent = plot.Model
	plot.Tier = tier
	plot.Model:SetAttribute("Tier", tier)
	setBounds(plot, depth)
end

-- Puts the player's base and treadmill tiers on their plot (on join and after an upgrade).
function BaseService.applyTiers(player: Player, data: any)
	local plot = plotOf[player]
	if not plot or not data then
		return
	end
	setBaseModel(plot, data.BaseTier or 1)
	if plot.TreadmillTier ~= (data.TreadmillLevel or 1) then
		placeTreadmill(plot, data.TreadmillLevel or 1)
	end
	if plot.Treadmill then
		plot.Treadmill:SetAttribute("Owner", player.UserId)
		plot.Treadmill.Parent = plot.Model
	end
	BaseService.updateUpgradeSigns(player, data)
end

function BaseService.capacity(data: any): number
	local row = Progression.Base[data.BaseTier or 1] or Progression.Base[1]
	return row.PetSlots
end

-- Base sign: the owner sees a blue house and "Your Base"; everyone else sees the owner's avatar bust and
-- "@username". The client picks which half to show. Unclaimed bases show nothing.
local function outlinedText(parent: Instance, name: string, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(15, 15, 25)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

local function buildSign(plot: Plot)
	local anchorPart = Instance.new("Part")
	anchorPart.Name = "SignAnchor"
	anchorPart.Size = Vector3.new(1, 1, 1)
	anchorPart.Transparency = 1
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	-- Bottom of the name ~4 studs up, top of the icon ~13: big and readable without looking up.
	local front = plot.Anchor * CFrame.new(0, 0, -3)
	anchorPart.CFrame = CFrame.new(front.Position.X, plot.Anchor.Position.Y + 8.5, front.Position.Z)
	anchorPart.Parent = plot.Model

	local gui = Instance.new("BillboardGui")
	gui.Name = "BaseSign"
	gui.Size = UDim2.fromScale(13, 9.5)
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = anchorPart
	gui.Enabled = false
	gui:SetAttribute("OwnerId", 0)
	gui.Parent = anchorPart

	local mine = Instance.new("Frame")
	mine.Name = "Mine"
	mine.BackgroundTransparency = 1
	mine.Size = UDim2.fromScale(1, 1)
	mine.Visible = false
	mine.Parent = gui
	local outline = Instance.new("ImageLabel")
	outline.Name = "HouseOutline"
	outline.BackgroundTransparency = 1
	outline.AnchorPoint = Vector2.new(0.5, 0)
	outline.Position = UDim2.fromScale(0.5, -0.02)
	outline.Size = UDim2.fromScale(0.62, 0.72)
	outline.Image = Config.HouseIcon
	outline.ImageColor3 = Color3.fromRGB(15, 15, 25)
	outline.ScaleType = Enum.ScaleType.Fit
	outline.Parent = mine
	local house = Instance.new("ImageLabel")
	house.Name = "House"
	house.BackgroundTransparency = 1
	house.AnchorPoint = Vector2.new(0.5, 0)
	house.Position = UDim2.fromScale(0.5, 0.04)
	house.Size = UDim2.fromScale(0.5, 0.6)
	house.Image = Config.HouseIcon
	house.ImageColor3 = Color3.fromRGB(40, 150, 255)
	house.ScaleType = Enum.ScaleType.Fit
	house.Parent = mine
	outlinedText(mine, "Label", UDim2.fromScale(0.5, 0.72), UDim2.fromScale(1, 0.26)).Text = "Your Base"

	local other = Instance.new("Frame")
	other.Name = "Other"
	other.BackgroundTransparency = 1
	other.Size = UDim2.fromScale(1, 1)
	other.Visible = false
	other.Parent = gui
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundTransparency = 1
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.fromScale(0.5, 0)
	avatar.Size = UDim2.fromScale(0.7, 0.72)
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.Parent = other
	local name = outlinedText(other, "Label", UDim2.fromScale(0.5, 0.72), UDim2.fromScale(1.3, 0.24))

	plot.Sign = { Gui = gui, Avatar = avatar, Name = name }
end

function BaseService.updateSign(player: Player?, plot: Plot?)
	plot = plot or (player and plotOf[player])
	if not plot or not plot.Sign then
		return
	end
	local sign = plot.Sign
	local owner = plot.Owner
	sign.Gui.Enabled = owner ~= nil
	sign.Gui:SetAttribute("OwnerId", if owner then owner.UserId else 0)
	if owner then
		sign.Name.Text = `@{owner.Name}`
	else
		sign.Name.Text = ""
		sign.Avatar.Image = ""
	end
end

local function buildPlot(index: number, anchor: CFrame): Plot
	local model = Instance.new("Model")
	model.Name = `Base{index}`
	local floorY = groundY(anchor.Position, { basesFolder })
	anchor = CFrame.new(anchor.Position.X, floorY, anchor.Position.Z) * anchor.Rotation
	-- the footprint of the pen at its biggest, for keeping treadmills and signs out of it
	local w = PEN_WIDTH / 2
	local corners = {
		(anchor * CFrame.new(-w, 0, 0)).Position,
		(anchor * CFrame.new(w, 0, 0)).Position,
		(anchor * CFrame.new(-w, 0, penDepth(MAX_TIER))).Position,
		(anchor * CFrame.new(w, 0, penDepth(MAX_TIER))).Position,
	}
	local worldMin, worldMax = corners[1], corners[1]
	for _, c in corners do
		worldMin, worldMax = worldMin:Min(c), worldMax:Max(c)
	end
	local plot: Plot = {
		Index = index,
		Anchor = anchor,
		Model = model,
		Owner = nil,
		Bounds = { MinX = 0, MaxX = 0, MinZ = 0, MaxZ = 0 },
		FloorY = floorY,
		Treadmill = nil,
		Tier = 0,
		Sign = nil,
		WorldMin = worldMin - Vector3.new(0, 1, 0),
		WorldMax = worldMax + Vector3.new(0, 10, 0),
	}
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("Owner", 0)
	model:SetAttribute("Anchor", anchor)
	model:SetAttribute("FloorY", floorY)
	model.Parent = basesFolder
	setBaseModel(plot, 1)
	return plot
end

function BaseService.init()
	local bases = Workspace:WaitForChild("Bases")
	local layout = bases:WaitForChild("BaseLayout")

	-- The old BaseLvl models go to ServerStorage; the layout models only mark where the 7 pens go.
	local templates = Instance.new("Folder")
	templates.Name = "BaseTemplates"
	templates.Parent = ServerStorage
	for _, child in bases:GetChildren() do
		if child ~= layout and child:IsA("Model") then
			child.Parent = templates
		end
	end

	basesFolder = Instance.new("Folder")
	basesFolder.Name = "PlayerBases"
	basesFolder.Parent = Workspace

	local line = Workspace:WaitForChild("Spawn_elements"):WaitForChild("Danger_line") :: BasePart
	for _, element in Workspace:WaitForChild("Spawn_elements"):GetChildren() do
		if element:IsA("Model") or element:IsA("BasePart") then
			local minV, maxV = Util.aabb(element)
			table.insert(blockers, { minV, maxV })
		end
	end
	local layoutPlots = {}
	for _, child in layout:GetChildren() do
		if child:IsA("Model") then
			table.insert(layoutPlots, child)
		end
	end
	-- Stable order: left to right, then back to front.
	table.sort(layoutPlots, function(a, b)
		local pa, pb = a:GetPivot().Position, b:GetPivot().Position
		if math.abs(pa.X - pb.X) > 1 then
			return pa.X < pb.X
		end
		return pa.Z < pb.Z
	end)
	-- the row: the Z most of the markers share
	local zs = {}
	for _, m in layoutPlots do
		table.insert(zs, m:GetPivot().Position.Z)
	end
	table.sort(zs)
	local rowZ = zs[math.ceil(#zs / 2)] or 0
	local rowMinX, rowMaxX = math.huge, -math.huge
	for _, m in layoutPlots do
		local p = m:GetPivot().Position
		if math.abs(p.Z - rowZ) < 30 then
			rowMinX, rowMaxX = math.min(rowMinX, p.X), math.max(rowMaxX, p.X)
		end
	end
	local anchors = {}
	for _, layoutPlot in layoutPlots do
		local minV, maxV = Util.aabb(layoutPlot)
		table.insert(anchors, plotAnchor(minV, maxV, rowZ, line.Position, rowMinX, rowMaxX))
	end
	layout.Parent = templates -- the layout models were only markers

	for index, anchor in anchors do
		local plot = buildPlot(index, anchor)
		local x = anchor.Position.X
		if math.abs(anchor.LookVector.Z) > 0.5 and (math.abs(x - rowMinX) < 1 or math.abs(x - rowMaxX) < 1) then
			-- the row's two end pens: treadmill on the outer side of the gate, at 45 degrees, facing the biomes and the
			-- open middle (it sits in the corner between the end pen and its side pen)
			local outward = if math.abs(x - rowMinX) < 1 then -1 else 1
			plot.Prefer = anchor.Position + Vector3.new(outward * 100, 0, 0)
			plot.Facing = (anchor.LookVector + Vector3.new(-outward, 0, 0)).Unit
		elseif math.abs(anchor.LookVector.X) > 0.5 then
			-- the side pens: straight (facing out of the gate), on the side away from the row
			plot.Prefer = anchor.Position + Vector3.new(0, 0, 100 * math.sign(anchor.Position.Z - rowZ))
		end
		table.insert(plots, plot)
	end
	-- Treadmills need every plot's footprint, so place them in a second pass.
	for _, plot in plots do
		placeTreadmill(plot, 1)
		placeSigns(plot)
		buildSign(plot)
		BaseService.updateSign(nil, plot)
	end
	print(`[BaseService] {#plots} base plots ready`)

	-- the Base button (Client/HomeButton, user 2026-11-22): back to your base from a biome, never during a run
	local lastHome: { [Player]: number } = {}
	Net.event("GoHome").OnServerEvent:Connect(function(player)
		if (player:GetAttribute("Carrying") or 0) > 0 or os.clock() - (lastHome[player] or 0) < 2 then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or MapInfo.isSafe(root.Position) then
			return
		end
		lastHome[player] = os.clock()
		BaseService.teleportHome(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastHome[player] = nil
	end)
end

-- (re)spawning: just in front of your base's gate, outside the pen, facing out towards the biomes
function BaseService.spawnCFrame(plot: Plot): CFrame
	local pos = (plot.Anchor * CFrame.new(0, 0, -9)).Position
	pos = Vector3.new(pos.X, plot.FloorY + 3.5, pos.Z)
	return CFrame.lookAt(pos, pos + plot.Anchor.LookVector)
end

local function teleportHome(player: Player)
	local plot = plotOf[player]
	local character = player.Character
	if plot and character then
		character:PivotTo(BaseService.spawnCFrame(plot))
	end
end
BaseService.teleportHome = teleportHome

function BaseService.assign(player: Player): Plot?
	local free = {}
	for _, plot in plots do
		if not plot.Owner then
			table.insert(free, plot)
		end
	end
	if #free == 0 then
		warn("[BaseService] no free plots; set the experience's Max Players to the plot count")
		return nil
	end
	local plot = free[rng:NextInteger(1, #free)]
	plot.Owner = player
	plotOf[player] = plot
	plot.Model:SetAttribute("Owner", player.UserId)
	player:SetAttribute("Plot", plot.Index)

	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.AvatarBust,
				Enum.ThumbnailSize.Size420x420
			)
		end)
		if ok and plot.Owner == player and plot.Sign then
			plot.Sign.Avatar.Image = image
		end
	end)
	BaseService.updateSign(player)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait() -- let the default spawn finish before moving
		if plotOf[player] == plot then
			teleportHome(player)
		end
	end)
	if player.Character then
		teleportHome(player)
	end
	return plot
end

function BaseService.release(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	plot.Owner = nil
	plot.Model:SetAttribute("Owner", 0)
	-- an empty base goes back to the starter base and treadmill
	setBaseModel(plot, 1)
	if plot.TreadmillTier ~= 1 then
		placeTreadmill(plot, 1)
	end
	if plot.Treadmill then
		plot.Treadmill:SetAttribute("Owner", 0)
		plot.Treadmill.Parent = nil -- (no treadmill on an empty base)
	end
	BaseService.updateSign(nil, plot)
end

function BaseService.getPlot(player: Player): Plot?
	return plotOf[player]
end

function BaseService.isInside(plot: Plot, x: number, z: number): boolean
	local b = plot.Bounds
	return x >= b.MinX and x <= b.MaxX and z >= b.MinZ and z <= b.MaxZ
end

-- World CFrame (pivot at floor level) for a local base position + yaw.
function BaseService.toWorld(plot: Plot, x: number, z: number, rotation: number): CFrame
	local local_ = plot.Anchor * CFrame.new(x, 0, z)
	return CFrame.new(local_.Position.X, plot.FloorY, local_.Position.Z)
		* (plot.Anchor - plot.Anchor.Position)
		* CFrame.Angles(0, rotation, 0)
end

return BaseService
