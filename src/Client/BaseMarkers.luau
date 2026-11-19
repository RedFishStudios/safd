-- What floats over the bases, copied from "[NEW] Feed and Rob Animals" (BaseMarkerController): over your own base the
-- blue house with "Your Base" under it (for you only); over every other taken base its owner's avatar bust, cut off
-- across the chest, with @username under it on a dark pill; nothing over a free base.
-- They're drawn on a 2D layer, each frame right after the camera moves, at the spot over the middle of the base and
-- sized as a world board there would be (studs that shrink with distance, plus a few fixed pixels so they stay
-- readable far off), so animals and props in front of a base never hide them. Same sizes and height as the reference.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local BaseMarkers = {}

local MARKER_BOTTOM = 16 -- studs over the base floor: a marker's bottom edge
local HOUSE = "rbxassetid://102871618525956" -- the reference's blue house (outlined), with our own as a fallback
local HOUSE_FALLBACK = "rbxassetid://102462759228425"
local NEAREST = 2
local MAX_DISTANCE = 800
local GROW = 1.75
type Shape = { studs: Vector2, pixels: Vector2 }
local HOUSE_SHAPE: Shape = { studs = Vector2.new(15, 15.75) * GROW, pixels = Vector2.new(21, 21) * GROW }
local PROFILE_SHAPE: Shape = { studs = Vector2.new(16, 9.2) * GROW, pixels = Vector2.new(20, 12) * GROW }

type Marker = { frame: Frame, kind: string, icon: ImageLabel, words: TextLabel, owner: number }

local layer: ScreenGui
local markers: { [Instance]: Marker } = {}

local function outline(label: TextLabel, thickness: number)
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.new(0, 0, 0)
	edge.Thickness = thickness
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	edge.Parent = label
end

local function newMarker(kind: string): Marker
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0)
	icon.Parent = frame
	local words = Instance.new("TextLabel")
	words.Name = "Words"
	words.AnchorPoint = Vector2.new(0.5, 1)
	words.Position = UDim2.fromScale(0.5, 1)
	words.Font = Enum.Font.GothamBlack
	words.TextColor3 = Color3.new(1, 1, 1)
	words.TextScaled = true
	words.Parent = frame
	if kind == "house" then
		icon.Size = UDim2.fromScale(0.85, 8 / 10.5)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = HOUSE
		words.BackgroundTransparency = 1
		words.Size = UDim2.fromScale(1, 2.2 / 10.5)
		words.Text = "Your Base"
		outline(words, 3)
	else
		icon.Size = UDim2.fromScale(11 / 16, 7.2 / 9.2)
		icon.ScaleType = Enum.ScaleType.Crop -- (filling the wide box, cut off across the chest)
		-- the name on a dark rounded pill, as wide as the name
		words.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		words.BackgroundTransparency = 0.35
		words.Size = UDim2.fromScale(0.62, 2 / 9.2)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = words
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.PaddingRight = UDim.new(0.04, 0)
		pad.PaddingTop = UDim.new(0.1, 0)
		pad.PaddingBottom = UDim.new(0.1, 0)
		pad.Parent = words
		outline(words, 1.5)
	end
	frame.Parent = layer
	return { frame = frame, kind = kind, icon = icon, words = words, owner = 0 }
end

-- the spot over the middle of a base's floor
local function spotOf(base: Model): Vector3
	local center = base:GetAttribute("Center") -- (the middle of the pen, set by the server)
	if typeof(center) == "Vector3" then
		return center
	end
	local cf = base:GetBoundingBox()
	local floorY = base:GetAttribute("FloorY") or cf.Position.Y
	return Vector3.new(cf.Position.X, floorY, cf.Position.Z)
end

local spots: { [Instance]: Vector3 } = {}

local function refresh()
	local folder = Workspace:FindFirstChild("PlayerBases")
	if not folder then
		return
	end
	local seen = {}
	for _, base in folder:GetChildren() do
		if not base:IsA("Model") then
			continue
		end
		seen[base] = true
		spots[base] = spotOf(base)
		-- (the server's in-world sign stays off on this screen)
		local anchor = base:FindFirstChild("SignAnchor")
		local board = anchor and anchor:FindFirstChild("BaseSign")
		if board and board:IsA("BillboardGui") and board.Enabled then
			board.Enabled = false
		end
		local owner = base:GetAttribute("Owner") or 0
		local kind = if owner == player.UserId then "house" elseif owner ~= 0 then "profile" else nil
		local m = markers[base]
		if m and (m.kind ~= kind or (kind == "profile" and m.owner ~= owner)) then
			m.frame:Destroy()
			markers[base] = nil
			m = nil
		end
		if kind and not m then
			local made = newMarker(kind)
			made.owner = owner
			if kind == "profile" then
				local who = Players:GetPlayerByUserId(owner)
				made.words.Text = "@" .. (if who then who.Name else tostring(owner))
				made.icon.Image = `rbxthumb://type=AvatarBust&id={owner}&w=420&h=420`
			end
			markers[base] = made
		end
	end
	for base, m in markers do
		if not seen[base] then
			m.frame:Destroy()
			markers[base] = nil
		end
	end
end

local function windowOpen(): boolean
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return false
	end
	for _, g in gui:GetChildren() do
		if g:IsA("ScreenGui") then
			for key, value in g:GetAttributes() do
				-- (the offline-cash flag stays on in the pack, so it doesn't count)
				if value == true and string.sub(key, -4) == "Open" and key ~= "OfflineCashOpen" then
					return true
				end
			end
		end
	end
	return false
end

local openCache, openAt = false, 0
local function place()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local now = os.clock()
	if now - openAt > 0.25 then
		openAt = now
		openCache = windowOpen()
	end
	local from = cam.CFrame.Position
	local perStud = cam.ViewportSize.Y / (2 * math.tan(math.rad(cam.FieldOfView) / 2))
	for base, m in markers do
		local shape = if m.kind == "house" then HOUSE_SHAPE else PROFILE_SHAPE
		local floorSpot = spots[base]
		local visible = false
		if floorSpot and not openCache then
			local spot = floorSpot + Vector3.new(0, MARKER_BOTTOM + shape.studs.Y / 2, 0)
			if (spot - from).Magnitude < MAX_DISTANCE then
				local at = cam:WorldToViewportPoint(spot)
				if at.Z > NEAREST then
					local size = shape.studs * (perStud / at.Z) + shape.pixels
					m.frame.Size = UDim2.fromOffset(math.round(size.X), math.round(size.Y))
					m.frame.Position = UDim2.fromOffset(math.round(at.X), math.round(at.Y))
					visible = true
				end
			end
		end
		if m.frame.Visible ~= visible then
			m.frame.Visible = visible
		end
	end
end

function BaseMarkers.init()
	local made = Instance.new("ScreenGui")
	made.Name = "BaseMarkers"
	made.ResetOnSpawn = false
	made.IgnoreGuiInset = true
	made.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	made.DisplayOrder = -2 -- under every other screen
	made.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	made.Parent = player:WaitForChild("PlayerGui")
	layer = made
	-- if the reference's house image can't load here, use ours
	task.spawn(function()
		local loaded = false
		local probe = Instance.new("ImageLabel")
		probe.Image = HOUSE
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ probe }, function(_, status)
				loaded = status == Enum.AssetFetchStatus.Success
			end)
		end)
		if not loaded then
			HOUSE = HOUSE_FALLBACK
			for _, m in markers do
				if m.kind == "house" then
					m.icon.Image = HOUSE
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			pcall(refresh)
			task.wait(0.5)
		end
	end)
	RunService:BindToRenderStep("SAFD_BaseMarkers", Enum.RenderPriority.Camera.Value + 1, place)
end

return BaseMarkers
