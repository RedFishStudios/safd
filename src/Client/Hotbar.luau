-- Free placement of saved animals inside your base (no grid).
-- The UI pack's 1-9 hotbar (All items) shows saved animals as Backpack tools; equipping one starts
-- placement here: a ghost follows the mouse, click / tap to place, R rotates, Q / Backspace cancels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalFactory = require(Shared.AnimalFactory)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local Bases = require(script.Parent.Bases)
local HUD = require(script.Parent.HUD)

local player = Players.LocalPlayer
local PlaceAnimal = Net.event("PlaceAnimal")

local Hotbar = {}

type Placing = {
	id: string,
	key: string, -- id, or id*mult (Config.parseKey)
	tool: Tool,
	ghost: Model,
	highlight: Highlight,
	rotation: number,
	valid: boolean,
	x: number,
	z: number,
	started: number,
}
local placing: Placing? = nil

local function stopPlacing()
	if placing then
		placing.ghost:Destroy()
		placing = nil
		HUD.setHint(nil)
	end
end

local function startPlacing(tool: Tool)
	stopPlacing()
	local id = tool:GetAttribute("AnimalId")
	local info = id and Config.Animals[id]
	if not info then
		return
	end
	if not Bases.mine() then
		HUD.toast("You don't have a base yet.", Color3.fromRGB(255, 120, 80))
		return
	end
	local ghost = AnimalFactory.create(id, info.BaseHeight, math.min(info.BaseHeight * 2.2, Config.MaxBaseAnimalWidth))
	for _, part in Util.parts(ghost) do
		part.CanQuery = false
	end
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = ghost
	ghost.Parent = Workspace
	placing = {
		id = id,
		key = tool:GetAttribute("AnimalKey") or id,
		tool = tool,
		ghost = ghost,
		highlight = highlight,
		rotation = 0,
		valid = false,
		x = 0,
		z = 0,
		started = os.clock(),
	}
	HUD.setHint(`Place your {info.Name}: click inside your base  ·  R rotate  ·  Q cancel`)
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	if placing then
		table.insert(ignore, placing.ghost)
	end
	for _, name in { "WildEggs", "BaseAnimals", "LocalDisaster" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	params.FilterDescendantsInstances = ignore
	return params
end

local function updateGhost(screenPoint: Vector2, viewport: boolean)
	local p = placing
	local base = Bases.mine()
	if not p or not base then
		return
	end
	local camera = Workspace.CurrentCamera
	local ray = if viewport
		then camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
		else camera:ScreenPointToRay(screenPoint.X, screenPoint.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, rayParams())
	local anchor: CFrame = base:GetAttribute("Anchor")
	local floorY: number = base:GetAttribute("FloorY")
	if not hit or not anchor then
		p.valid = false
		p.ghost:PivotTo(CFrame.new(0, -500, 0))
		return
	end
	local localPos = anchor:PointToObjectSpace(hit.Position)
	p.x, p.z = localPos.X, localPos.Z
	p.valid = Bases.isInside(base, p.x, p.z)
	local world = anchor:PointToWorldSpace(Vector3.new(p.x, 0, p.z))
	p.ghost:PivotTo(CFrame.new(world.X, floorY, world.Z) * (anchor - anchor.Position) * CFrame.Angles(0, p.rotation, 0))
	local color = if p.valid then Color3.fromRGB(80, 255, 120) else Color3.fromRGB(255, 70, 70)
	p.highlight.FillColor = color
	p.highlight.OutlineColor = color
end

local function confirm()
	local p = placing
	if not p then
		return
	end
	if not p.valid then
		HUD.toast("Place animals inside your base.", Color3.fromRGB(255, 120, 80), 2)
		return
	end
	if os.clock() - p.started < 0.4 then
		return -- (the click that equipped it)
	end
	PlaceAnimal:FireServer(p.key, p.x, p.z, p.rotation)
	-- one click places one animal, then the tool goes back in the hotbar: a stray click can never drop a whole stack
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("AnimalId") then
			startPlacing(child)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if placing and child == placing.tool then
			stopPlacing()
		end
	end)
end

function Hotbar.isPlacing(): boolean
	return placing ~= nil
end

function Hotbar.init()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterRemoving:Connect(stopPlacing)

	RunService.RenderStepped:Connect(function()
		if placing and not UserInputService.TouchEnabled then
			updateGhost(UserInputService:GetMouseLocation(), true)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not placing then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			confirm()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			updateGhost(Vector2.new(input.Position.X, input.Position.Y), false)
			confirm()
		elseif input.KeyCode == Enum.KeyCode.R then
			placing.rotation += math.pi / 4
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Backspace then
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:UnequipTools()
			end
		end
	end)
end

return Hotbar
