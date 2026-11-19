-- Animals: wild spawns in each biome, "hold E" rescue, the head stack, depositing at the safe line,
-- inventory/placement in bases, and money per second (including offline earnings).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalFactory = require(Shared.AnimalFactory)
local Config = require(Shared.Config)
local MapInfo = require(Shared.MapInfo)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)

local AnimalService = {}

local rng = Random.new()
local wildFolder: Folder
local baseFolder: Folder
local wild: { [number]: { Model } } = {}
local carried: { [Player]: { id: { string }, models: { Model } } } = {}
-- the run home in progress: the multiplier rings collected so far (Client/RunCourse, Net.RunRing)
local runs: { [Player]: { product: number, rings: { number }, started: number } } = {}
local placedModels: { [Player]: { [string]: Model } } = {}

local DisasterStart = Net.event("DisasterStart")
local DisasterEnd = Net.event("DisasterEnd")
local RunReward = Net.event("RunReward")
local InventoryChanged = Net.event("InventoryChanged")
local Notify = Net.event("Notify")
local PlaceAnimal = Net.event("PlaceAnimal")
local GetState = Net.func("GetState")
local StateChanged = Net.event("StateChanged")

local function notify(player: Player, text: string, color: Color3?)
	Notify:FireClient(player, text, color)
end

local function rarityOf(id: string)
	return Config.Rarities[Config.Animals[id].Rarity]
end

local function addTag(model: Model, id: string, extra: string?)
	local info = Config.Animals[id]
	local rarity = rarityOf(id)
	local root = model.PrimaryPart :: BasePart
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(180, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 3) + 1.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 110
	gui.Adornee = root
	gui.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	local lines = {
		{ info.Name, Color3.new(1, 1, 1), 22, Enum.Font.GothamBlack },
		{ rarity.Name, rarity.Color, 16, Enum.Font.GothamBold },
		{ extra or `${Util.formatNumber(info.Income)}/s`, Color3.fromRGB(120, 255, 120), 15, Enum.Font.GothamBold },
	}
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, line[3])
		label.Text = line[1]
		label.TextColor3 = line[2]
		label.TextSize = line[3]
		label.Font = line[4]
		label.TextStrokeTransparency = 0.3
		label.Parent = gui
	end
end

-- Inventory / income --------------------------------------------------------------------------------------------

local function incomeOf(data): number
	local total = 0
	for _, entry in data.Placed do
		local info = Config.Animals[entry.Id]
		if info then
			total += info.Income
		end
	end
	return total
end

local function refreshStats(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	player:SetAttribute("Money", data.Money)
	player:SetAttribute("Income", incomeOf(data))
	player:SetAttribute("PlacedCount", #data.Placed)
	player:SetAttribute("Speed", data.Speed)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		(stats :: any).Money.Value = math.floor(data.Money);
		(stats :: any).Speed.Value = data.Speed
	end
	BaseService.updateSign(player)
	BaseService.updateUpgradeSigns(player, data)
end
AnimalService.refreshStats = refreshStats

-- Everything the client UI shows that isn't an attribute.
function AnimalService.state(player: Player)
	local data = DataService.get(player)
	if not data then
		return nil
	end
	return {
		Inventory = data.Inventory,
		Discovered = data.Discovered,
		IndexClaimed = data.IndexClaimed,
		Trails = data.Trails,
		EquippedTrail = data.EquippedTrail,
		PendingOffline = data.PendingOffline,
		FreeItemClaimed = data.FreeItemClaimed,
	}
end

function AnimalService.pushState(player: Player)
	local state = AnimalService.state(player)
	if state then
		StateChanged:FireClient(player, state)
	end
end

-- Saved (unplaced) animals live in the Backpack as one Tool per species, so the UI pack's real
-- 1-9 hotbar can show them. Equipping one starts placement on the client.
local function syncTools(player: Player)
	local data = DataService.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	local counts = {}
	for _, id in data.Inventory do
		counts[id] = (counts[id] or 0) + 1
	end
	local existing = {}
	local character = player.Character
	for _, container in { backpack, character } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("AnimalId") then
					existing[tool:GetAttribute("AnimalId")] = tool
				end
			end
		end
	end
	for id, tool in existing do
		if not counts[id] then
			tool:Destroy()
		end
	end
	for id, count in counts do
		local info = Config.Animals[id]
		local tool = existing[id]
		if not tool then
			tool = Instance.new("Tool")
			tool.RequiresHandle = false
			tool.CanBeDropped = false
			tool.ManualActivationOnly = true
			tool:SetAttribute("AnimalId", id)
			tool:SetAttribute("HotbarOrder", info.Biome * 10 + info.Rarity)
			tool.Parent = backpack
		end
		tool.Name = if count > 1 then `{info.Name} x{count}` else info.Name
		tool.ToolTip = `{Config.Rarities[info.Rarity].Name} · ${Util.formatNumber(info.Income)}/s`
		tool:SetAttribute("Count", count)
	end
end
AnimalService.syncTools = syncTools

local function pushInventory(player: Player)
	local data = DataService.get(player)
	if data then
		InventoryChanged:FireClient(player, data.Inventory)
		syncTools(player)
		AnimalService.pushState(player)
	end
end

-- Wild animals --------------------------------------------------------------------------------------------------

local spawnWild: (biome: number) -> ()

local function onRescue(player: Player, model: Model, biome: number)
	if model:GetAttribute("Taken") or not model.Parent then
		return
	end
	local data = DataService.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local stack = carried[player]
	if not stack then
		stack = { id = {}, models = {} }
		carried[player] = stack
	end
	if #stack.id >= Config.MaxCarry then
		notify(player, "Your stack is full! Get back to your base.", Color3.fromRGB(255, 120, 80))
		return
	end
	local animalInfo = Config.Animals[model:GetAttribute("AnimalId") or ""]
	local reach = 40 + (if animalInfo then animalInfo.Height else 0) -- (the big ones are huge)
	if (root.Position - model:GetPivot().Position).Magnitude > reach then -- animals wander client-side
		return
	end

	local id = model:GetAttribute("AnimalId") :: string
	model:SetAttribute("Taken", true)
	model:Destroy()
	task.delay(rng:NextNumber(Config.WildRespawnTime[1], Config.WildRespawnTime[2]), spawnWild, biome)

	-- Stack it on the player's head.
	local head = character:FindFirstChild("Head") :: BasePart?
	local attachTo = head or root
	local carry = AnimalFactory.create(id, Config.CarryHeight, 3.6)
	local stackHeight = 0
	for _, m in stack.models do
		stackHeight += (m:GetAttribute("Height") or Config.CarryHeight) + 0.1
	end
	local yaw = attachTo.CFrame - attachTo.Position
	local base = attachTo.CFrame * CFrame.new(0, attachTo.Size.Y / 2 + 0.1 + stackHeight, 0)
	carry:PivotTo(CFrame.new(base.Position) * yaw)
	Util.setModelPhysics(carry, false)
	for _, part in Util.parts(carry) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = attachTo
		weld.Part1 = part
		weld.Parent = part
	end
	CollectionService:AddTag(carry, "CarriedAnimal")
	carry.Name = `Carried_{id}`
	carry.Parent = character
	table.insert(stack.id, id)
	table.insert(stack.models, carry)
	player:SetAttribute("Carrying", #stack.id)

	local info = Config.Animals[id]
	notify(player, `Rescued a {rarityOf(id).Name} {info.Name}!`, rarityOf(id).Color)
	-- Every pickup (re)starts the chase: the client ignores it while one is already running, and if a chase ever
	-- ended while you still carried animals, the next pickup brings it straight back (it used to fire only for the
	-- first animal of a stack, 2026-11-19).
	if not runs[player] then
		runs[player] = { product = 1, rings = {}, started = os.clock() }
	end
	if not MapInfo.isSafe(root.Position) then
		DisasterStart:FireClient(player, biome)
	end
end

-- A free spot on the biome's track. farOnly: only in the far 40% of the biome (away from the bases), where the
-- legendaries live.
local function randomSpot(biome: number, farOnly: boolean?): Vector3?
	local minV, maxV = MapInfo.bounds(biome)
	if not minV then
		return nil
	end
	local zMin, zMax = minV.Z + 18, maxV.Z - 12
	if farOnly then
		local toBase = MapInfo.toBase()
		if toBase.Z < 0 then
			zMin = zMin + (zMax - zMin) * 0.6 -- the bases are towards -Z: far = high Z
		else
			zMax = zMax - (zMax - zMin) * 0.6
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- skip particle volumes like the biomes' *_specks parts
	params.FilterDescendantsInstances = { wildFolder }
	for _ = 1, 40 do
		local x = rng:NextNumber(minV.X + 8, maxV.X - 8)
		local z = rng:NextNumber(zMin, zMax)
		local tooClose = false
		for _, other in wild[biome] do
			local p = other:GetPivot().Position
			if (Vector2.new(p.X, p.Z) - Vector2.new(x, z)).Magnitude < Config.WildMinSpacing then
				tooClose = true
				break
			end
		end
		if not tooClose then
			local hit = Workspace:Raycast(Vector3.new(x, maxV.Y + 120, z), Vector3.new(0, -200, 0), params)
			-- Reject hits on tree canopies, rocks etc. — only accept ground level.
			if hit and hit.Position.Y < maxV.Y + 4 then
				return hit.Position
			end
		end
	end
	return nil
end

function spawnWild(biome: number)
	local list = wild[biome]
	-- Drop references to models that were rescued.
	for i = #list, 1, -1 do
		if not list[i].Parent then
			table.remove(list, i)
		end
	end
	if #list >= Config.WildAnimalsPerBiome then
		return
	end
	local animals = Config.Biomes[biome].Animals
	-- only one legendary out in a biome at a time
	local legendaryOut = false
	for _, other in list do
		local otherId = other:GetAttribute("AnimalId")
		if otherId and Config.Animals[otherId] and Config.Animals[otherId].Rarity == #Config.Rarities then
			legendaryOut = true
		end
	end
	local weights = {}
	for i = 1, #animals do
		weights[i] = if i == #Config.Rarities and legendaryOut then 0 else Config.Rarities[i].Weight
	end
	local rarity = Util.weightedPick(rng, weights)
	local id = animals[rarity]
	local spot = randomSpot(biome, rarity == #Config.Rarities)
	if not spot then
		task.delay(5, spawnWild, biome)
		return
	end
	local model = AnimalFactory.create(id, Config.animalHeight(id), Config.animalHeight(id) * 2.2)
	model:PivotTo(CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Biome", biome)
	addTag(model, id)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Save"
	prompt.ObjectText = `{Config.Animals[id].Name} ({rarityOf(id).Name})`
	prompt.HoldDuration = 0.7
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- Wild animals wander on each player's screen only, so the server's copy stays at the spawn spot. Roblox checks a
	-- prompt's distance against the server's copy, so the server allows the wander radius on top; each client shrinks
	-- it back to ClientRange (Client/AnimalVisuals) so the prompt still only shows up close.
	prompt.MaxActivationDistance = 8 + Config.animalHeight(id) * 0.8 + Config.AnimalWanderRadius * 2 + 14
	prompt:SetAttribute("ClientRange", 8 + Config.animalHeight(id) * 0.8)
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		onRescue(player, model, biome)
	end)

	CollectionService:AddTag(model, "WildAnimal")
	model.Parent = wildFolder
	table.insert(list, model)
end

-- Carrying / deposit --------------------------------------------------------------------------------------------

local function clearStack(player: Player): { string }
	runs[player] = nil
	local stack = carried[player]
	carried[player] = nil
	player:SetAttribute("Carrying", 0)
	if not stack then
		return {}
	end
	for _, model in stack.models do
		model:Destroy()
	end
	return stack.id
end

local function deposit(player: Player)
	local data = DataService.get(player)
	local run = runs[player]
	local ids = clearStack(player)
	if not data or #ids == 0 then
		return
	end
	local newlyFound = {}
	for _, id in ids do
		table.insert(data.Inventory, id)
		if not data.Discovered[id] then
			data.Discovered[id] = true
			table.insert(newlyFound, Config.Animals[id].Name)
		end
	end
	-- the run bonus: some seconds of the rescued animals' income, times every ring you flew through on the way
	local income = 0
	for _, id in ids do
		income += Config.Animals[id].Income
	end
	local base = income * Config.RunRewardSeconds
	local product = if run then run.product else 1
	local total = base * product
	data.Money += total
	refreshStats(player)
	RunReward:FireClient(player, {
		Base = base,
		Rings = if run then run.rings else {},
		Total = total,
		Animals = ids,
	})
	pushInventory(player)
	-- hold the animal you just brought home, ready to place in your base
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if humanoid and backpack and humanoid.Health > 0 then
		for _, tool in backpack:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("AnimalId") == ids[#ids] then
				humanoid:EquipTool(tool)
				break
			end
		end
	end
	DisasterEnd:FireClient(player, #ids, false)
	if #newlyFound > 0 then
		notify(
			player,
			`New in your Index: {table.concat(newlyFound, ", ")}! Claim the reward in the Index.`,
			Color3.fromRGB(120, 220, 255)
		)
	end
	notify(
		player,
		`You saved {#ids} animal{if #ids == 1 then "" else "s"}! Place them in your base from the hotbar.`,
		Color3.fromRGB(120, 255, 140)
	)
end

local function loseStack(player: Player)
	local ids = clearStack(player)
	if #ids > 0 then
		DisasterEnd:FireClient(player, 0, true)
		notify(player, "You lost the animals you were carrying...", Color3.fromRGB(255, 90, 90))
	end
end

-- Base animals --------------------------------------------------------------------------------------------------

local function spawnPlaced(player: Player, entry)
	local plot = BaseService.getPlot(player)
	if not plot or not Config.Animals[entry.Id] then
		return
	end
	local model = AnimalFactory.create(entry.Id, Config.animalHeight(entry.Id), Config.animalHeight(entry.Id) * 2.2)
	model:PivotTo(BaseService.toWorld(plot, entry.X, entry.Z, entry.R))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- no shadows from the animals in the bases (the giant ones darkened the whole yard)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = false
		end
	end
	model.Name = `{entry.Id}_{entry.Uid}`
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Uid", entry.Uid)
	model:SetAttribute("Plot", plot.Index)
	addTag(model, entry.Id)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = Config.Animals[entry.Id].Name
	prompt.HoldDuration = 0.6
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8 + Config.animalHeight(entry.Id) * 0.8
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(who)
		if who ~= player then
			return
		end
		local data = DataService.get(player)
		if not data then
			return
		end
		for i, placed in data.Placed do
			if placed.Uid == entry.Uid then
				table.remove(data.Placed, i)
				table.insert(data.Inventory, placed.Id)
				break
			end
		end
		local models = placedModels[player]
		if models then
			models[entry.Uid] = nil
		end
		model:Destroy()
		pushInventory(player)
		refreshStats(player)
	end)

	CollectionService:AddTag(model, "BaseAnimal")
	model.Parent = baseFolder
	placedModels[player] = placedModels[player] or {}
	placedModels[player][entry.Uid] = model
end

local function onPlace(player: Player, id: unknown, x: unknown, z: unknown, rotation: unknown)
	if type(id) ~= "string" or type(x) ~= "number" or type(z) ~= "number" or type(rotation) ~= "number" then
		return
	end
	if x ~= x or z ~= z or rotation ~= rotation or not Config.Animals[id] then
		return -- NaN or unknown animal
	end
	local data = DataService.get(player)
	local plot = BaseService.getPlot(player)
	if not data or not plot then
		return
	end
	if not BaseService.isInside(plot, x, z) then
		notify(player, "Place animals inside your base.", Color3.fromRGB(255, 120, 80))
		return
	end
	if #data.Placed >= BaseService.capacity(data) then
		notify(player, "Your base is full! Upgrade your base for more room.", Color3.fromRGB(255, 120, 80))
		return
	end
	local index = table.find(data.Inventory, id)
	if not index then
		return
	end
	table.remove(data.Inventory, index)
	local entry = {
		Uid = HttpService:GenerateGUID(false),
		Id = id,
		X = math.round(x * 100) / 100,
		Z = math.round(z * 100) / 100,
		R = math.round((rotation % (math.pi * 2)) * 1000) / 1000,
	}
	table.insert(data.Placed, entry)
	spawnPlaced(player, entry)
	pushInventory(player)
	refreshStats(player)
end

-- Player lifecycle ----------------------------------------------------------------------------------------------

function AnimalService.playerLoaded(player: Player, data)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local money = Instance.new("NumberValue")
	money.Name = "Money"
	money.Parent = stats
	local speed = Instance.new("IntValue")
	speed.Name = "Speed"
	speed.Parent = stats
	stats.Parent = player

	-- Drop unknown ids (e.g. after renaming an animal in Config).
	for i = #data.Inventory, 1, -1 do
		if not Config.Animals[data.Inventory[i]] then
			table.remove(data.Inventory, i)
		end
	end
	for i = #data.Placed, 1, -1 do
		if not Config.Animals[data.Placed[i].Id] then
			table.remove(data.Placed, i)
		end
	end

	-- Offline earnings: animals kept earning while the player was away.
	local income = incomeOf(data)
	if data.LastOnline > 0 and income > 0 then
		local away = math.max(0, os.time() - data.LastOnline)
		local earned = away * income
		if earned > 0 then
			-- Held until the player presses "Claim" on the Offline Cash panel.
			data.PendingOffline += earned
		end
	end
	-- Old saves: animals already placed/held count as discovered.
	for _, id in data.Inventory do
		data.Discovered[id] = true
	end
	for _, entry in data.Placed do
		data.Discovered[entry.Id] = true
	end

	for _, entry in data.Placed do
		spawnPlaced(player, entry)
	end
	refreshStats(player)
	pushInventory(player)
	if not DataService.canSave(player) then
		task.delay(4, function()
			if player.Parent then
				notify(
					player,
					"Data is not saving (Studio: enable 'Studio Access to API Services').",
					Color3.fromRGB(255, 90, 90)
				)
			end
		end)
	end

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			loseStack(player)
		end)
		-- The Backpack is rebuilt on every respawn.
		player:WaitForChild("Backpack", 10)
		syncTools(player)
	end)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			loseStack(player)
		end)
	end
end

function AnimalService.playerRemoving(player: Player)
	clearStack(player)
	local models = placedModels[player]
	placedModels[player] = nil
	if models then
		for _, model in models do
			model:Destroy()
		end
	end
end

function AnimalService.init()
	wildFolder = Instance.new("Folder")
	wildFolder.Name = "WildAnimals"
	wildFolder.Parent = Workspace
	baseFolder = Instance.new("Folder")
	baseFolder.Name = "BaseAnimals"
	baseFolder.Parent = Workspace

	-- In live servers the KeyframeSequences are only useful for editing; keep them off the client download.
	if not RunService:IsStudio() then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets then
			local holder = Instance.new("Folder")
			holder.Name = "AnimalAnimSaves"
			holder.Parent = ServerStorage
			for _, descendant in assets:GetDescendants() do
				if descendant.Name == "Animations" and descendant.Parent and descendant.Parent:IsA("Model") then
					descendant.Name = descendant.Parent.Name
					descendant.Parent = holder
				end
			end
		end
	end

	local missing = {}
	for id in Config.Animals do
		if not AnimalFactory.findTemplate(id) then
			table.insert(missing, id)
		end
	end
	if #missing > 0 then
		warn(
			`[AnimalService] {#missing} animal models missing from ReplicatedStorage.Assets (using placeholders): `
				.. table.concat(missing, ", ")
		)
	end

	for biome = 1, #Config.Biomes do
		wild[biome] = {}
		for _ = 1, Config.WildAnimalsPerBiome do
			spawnWild(biome)
		end
	end

	PlaceAnimal.OnServerEvent:Connect(onPlace)
	GetState.OnServerInvoke = function(player)
		return AnimalService.state(player)
	end

	-- a multiplier ring on the run home: only while carrying animals, only the ring values that exist, a few a
	-- second at most, the product capped
	Net.event("RunRing").OnServerEvent:Connect(function(player, value)
		local run = runs[player]
		if not run or type(value) ~= "number" or not table.find(Config.RunRingValues, value) then
			return
		end
		if #run.rings >= 40 or #run.rings > (os.clock() - run.started) * 3 + 2 then
			return
		end
		table.insert(run.rings, value)
		run.product = math.min(run.product * value, Config.RunMultiplierCap)
	end)

	Net.event("ClaimOffline").OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if not data or data.PendingOffline <= 0 then
			return
		end
		local amount = data.PendingOffline
		data.PendingOffline = 0
		data.Money += amount
		refreshStats(player)
		AnimalService.pushState(player)
		Net.event("Purchased"):FireClient(player) -- the cha-ching (Client/RewardFx)
		notify(player, `Claimed ${Util.formatNumber(amount)} offline cash!`, Color3.fromRGB(255, 220, 90))
	end)

	Net.event("ClaimIndexReward").OnServerEvent:Connect(function(player, id)
		local data = DataService.get(player)
		local info = type(id) == "string" and Config.Animals[id]
		if not data or not info or not data.Discovered[id] or data.IndexClaimed[id] then
			return
		end
		data.IndexClaimed[id] = true
		local money = info.Income * Config.IndexRewardSeconds
		local speed = Config.IndexRewardSpeed[info.Rarity] or 1
		data.Money += money
		data.Speed += speed
		refreshStats(player)
		AnimalService.pushState(player)
		notify(
			player,
			`Index reward: +${Util.formatNumber(money)} and +{speed} speed!`,
			Config.Rarities[info.Rarity].Color
		)
	end)

	Net.event("SellAnimals").OnServerEvent:Connect(function(player, ids)
		local data = DataService.get(player)
		if not data or type(ids) ~= "table" or #ids > 50 then
			return
		end
		local total, count = 0, 0
		for _, id in ids do
			local index = type(id) == "string" and table.find(data.Inventory, id)
			if index then
				table.remove(data.Inventory, index)
				total += Config.Animals[id].Income * Config.SellValueSeconds
				count += 1
			end
		end
		if count == 0 then
			return
		end
		data.Money += total
		refreshStats(player)
		pushInventory(player)
		notify(
			player,
			`Sold {count} animal{if count == 1 then "" else "s"} for ${Util.formatNumber(total)}`,
			Color3.fromRGB(120, 255, 140)
		)
	end)

	-- Safe-line check for players carrying animals.
	task.spawn(function()
		while true do
			task.wait(0.15)
			for player, stack in carried do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and #stack.id > 0 and MapInfo.isSafe(root.Position) then
					deposit(player)
				end
			end
		end
	end)

	-- Money every second.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data and player:GetAttribute("Loaded") then
					local income = incomeOf(data)
					if income > 0 then
						data.Money += income
						player:SetAttribute("Money", data.Money)
						local stats = player:FindFirstChild("leaderstats")
						if stats then
							(stats :: any).Money.Value = math.floor(data.Money)
						end
					end
				end
			end
		end
	end)
end

return AnimalService
