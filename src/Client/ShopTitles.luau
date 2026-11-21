-- Floating names over the spawn stands, as in "[NEW] Feed and Rob Animals" (LobbySignsController, "the trail shop
-- should constantly show and be bright colours"): a big name over each stand in a bright gradient with an outline,
-- unlit, never hidden by distance, bobbing gently. The outline keeps its share of the letters at any distance.
-- (user, 2026-11-20: 'for the yellow tent, there should be a hovering "Trail Shop" on top of the tent')
-- Drawn on this client only: no collisions, no queries.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShopTitles = {}

local FONT = Enum.Font.FredokaOne

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- stand model in Workspace.Spawn_elements, text, gradient top / bottom, outline, studs wide, studs over its top
local NAMES = {
	{
		Model = "Weight_stand",
		Text = "Trail Shop",
		Top = rgb(225, 255, 120),
		Bottom = rgb(60, 215, 60),
		Outline = rgb(12, 80, 22),
		Width = 22,
		Above = 4,
	},
	{
		Model = "Speed_stand",
		Text = "Sell Shop",
		Top = rgb(255, 245, 140),
		Bottom = rgb(255, 165, 20),
		Outline = rgb(105, 55, 0),
		Width = 22,
		Above = 4,
	},
}

type Name = { gui: BillboardGui, stroke: UIStroke, anchor: BasePart, letters: number, phase: number }
local names: { Name } = {}

local function floatingName(folder: Folder, def)
	local elements = Workspace:WaitForChild("Spawn_elements", 60)
	local model = elements and elements:WaitForChild(def.Model, 60)
	if not model or not model:IsA("Model") then
		return
	end
	local cf, size = model:GetBoundingBox()
	local h = def.Width * 0.24
	local at = cf.Position + Vector3.new(0, size.Y / 2 + def.Above + h / 2, 0)
	local anchor = Instance.new("Part")
	anchor.Name = def.Model .. "Name"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "Name"
	gui.Size = UDim2.fromScale(def.Width, h) -- (studs)
	gui.LightInfluence = 0
	gui.MaxDistance = math.huge
	gui.Adornee = anchor
	gui.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Font = FONT
	text.Text = def.Text
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Size = UDim2.fromScale(1, 1)
	text.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(def.Top, def.Bottom)
	g.Parent = text
	local stroke = Instance.new("UIStroke")
	stroke.Color = def.Outline
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = text
	table.insert(names, { gui = gui, stroke = stroke, anchor = anchor, letters = h * 0.5, phase = #names * 1.9 })
end

-- each frame: the names bob, and their outline stays about a twelfth of the letters' height on screen
local function step()
	local cam = Workspace.CurrentCamera
	if not cam or #names == 0 then
		return
	end
	local k = cam.ViewportSize.Y / (2 * math.tan(math.rad(cam.FieldOfView) / 2))
	local eye = cam.CFrame.Position
	local t = os.clock()
	for _, n in names do
		n.gui.StudsOffset = Vector3.new(0, math.sin(t * 1.6 + n.phase) * 0.3, 0)
		local px = n.letters * k / math.max((n.anchor.Position - eye).Magnitude, 1)
		local th = math.clamp(px * 0.085, 1, 4.5)
		if math.abs(th - n.stroke.Thickness) > 0.15 then
			n.stroke.Thickness = th
		end
	end
end

function ShopTitles.init()
	local folder = Instance.new("Folder")
	folder.Name = "SAFD_ShopTitles"
	folder.Parent = Workspace
	for _, def in NAMES do
		task.spawn(floatingName, folder, def)
	end
	RunService.RenderStepped:Connect(step)
end

return ShopTitles
