-- Eggs and animals: wild eggs in each biome (Shared/EggFactory), "hold E" to save one, the head stack of eggs,
-- hatching them at the safe line (the run's luck rings raise the odds of rarer animals: Config.hatchWeights), the
-- animals' inventory/placement in bases, and money per second (including offline earnings).

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
local EggFactory = require(Shared.EggFactory)
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
-- the eggs on a player's head: their biomes, and the models
local carried: { [Player]: { eggs: { number }, models: { Model }, designs: { number } } } = {}
-- the run home in progress: the luck rings collected so far (Client/RunCourse, Net.RunRing). They add up:
-- luck = 1 + the rings, and it raises the odds of hatching the rarer animals (Config.hatchWeights)
local runs: { [Player]: { mult: number, rings: { number }, started: number } } = {}
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

local function addTag(model: Model, id: string)
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
		{ `${Util.formatNumber(info.Income)}/s`, Color3.fromRGB(120, 255, 120), 17, Enum.Font.GothamBlack },
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
		BiomeClaimed = data.BiomeClaimed,
		Trails = data.Trails,
		EquippedTrail = data.EquippedTrail,
		PendingOffline = data.PendingOffline,
		FreeItemClaimed = data.FreeItemClaimed,
		-- (the My Animals panel and the "you can buy" popups: Client/AnimalsPanel, Client/BuyNotice)
		Placed = data.Placed,
		Capacity = BaseService.capacity(data),
		BaseTier = data.BaseTier or 1,
		TreadmillLevel = data.TreadmillLevel or 1,
	}
end

function AnimalService.pushState(player: Player)
	local state = AnimalService.state(player)
	if state then
		StateChanged:FireClient(player, state)
	end
end

-- Saved (unplaced) animals live in the Backpack as one Tool per species, so the UI pack's real 1-9 hotbar
-- (Client/UIBridge) can show them. Equipping one starts placement on
-- the client.
local function syncTools(player: Player)
	local data = DataService.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	local counts = {}
	for _, key in data.Inventory do
		counts[key] = (counts[key] or 0) + 1
	end
	local existing = {}
	local character = player.Character
	for _, container in { backpack, character } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("AnimalId") then
					local key = tool:GetAttribute("AnimalKey") or tool:GetAttribute("AnimalId")
					if existing[key] then
						tool:Destroy() -- (a duplicate)
					else
						existing[key] = tool
					end
				end
			end
		end
	end
	for key, tool in existing do
		if not counts[key] then
			tool:Destroy()
		end
	end
	for key, count in counts do
		local info = Config.parseKey(key)
		if not info then
			continue
		end
		local tool = existing[key]
		if not tool then
			tool = Instance.new("Tool")
			tool.RequiresHandle = false
			tool.CanBeDropped = false
			tool.ManualActivationOnly = true
			tool:SetAttribute("AnimalId", info.Id)
			tool:SetAttribute("AnimalKey", key)
			-- (the best first: biome, then rarity)
			tool:SetAttribute("HotbarOrder", -(info.Biome * 1000 + info.Rarity * 40))
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

-- Wild eggs -----------------------------------------------------------------------------------------------------

local spawnEgg: (biome: number) -> ()

local function eggTag(model: Model, biome: number)
	local egg = Config.Eggs[biome]
	local rarity = Config.Rarities[egg.Rarity]
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, egg.Height * 0.62 + 2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 140 + egg.Height * 4
	gui.Adornee = model.PrimaryPart
	gui.Parent = model.PrimaryPart
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	local name = Config.eggName(biome, model:GetAttribute("Design") :: number?)
	for _, line in { { name, Color3.new(1, 1, 1), 26 }, { rarity.Name, rarity.Color, 22 } } do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, line[3])
		label.Text = line[1]
		label.TextColor3 = line[2]
		label.TextSize = line[3]
		label.Font = Enum.Font.FredokaOne
		label.TextStrokeTransparency = 0
		label.Parent = gui
	end
end

local function onEggPickup(player: Player, model: Model, biome: number)
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
		stack = { eggs = {}, models = {}, designs = {} }
		carried[player] = stack
	end
	if #stack.eggs >= Config.MaxCarry then
		notify(player, "Your stack is full! Get back to your base.", Color3.fromRGB(255, 120, 80))
		return
	end
	local egg = Config.Eggs[biome]
	if (root.Position - model:GetPivot().Position).Magnitude > (model:GetAttribute("Footprint") or egg.Height) + 25 then
		return
	end

	local design = model:GetAttribute("Design") or 1
	model:SetAttribute("Taken", true)
	model:Destroy()
	task.delay(rng:NextNumber(Config.EggRespawnTime[1], Config.EggRespawnTime[2]), spawnEgg, biome)

	-- Stack it on the player's head.
	local head = character:FindFirstChild("Head") :: BasePart?
	local attachTo = head or root
	local carry = EggFactory.create(biome, Config.CarryEggHeight[biome], design) -- (the design you picked up)
	local stackHeight = 0
	for _, m in stack.models do
		stackHeight += (m:GetAttribute("Height") or Config.CarryHeight) + 0.1
	end
	local yaw = attachTo.CFrame - attachTo.Position
	local base = attachTo.CFrame * CFrame.new(0, attachTo.Size.Y / 2 + 0.1 + stackHeight, 0)
	carry:PivotTo(CFrame.new(base.Position) * yaw)
	-- (no light or smoke on your head: only the egg)
	for _, d in carry:GetDescendants() do
		if d:IsA("PointLight") or (d:IsA("ParticleEmitter") and string.find(d.Texture, "smoke") ~= nil) then
			d:Destroy()
		end
	end
	Util.setModelPhysics(carry, false)
	for _, part in Util.parts(carry) do
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = attachTo
		weld.Part1 = part
		weld.Parent = part
	end
	CollectionService:AddTag(carry, "CarriedEgg")
	carry.Name = `CarriedEgg_{biome}`
	carry.Parent = character
	table.insert(stack.eggs, biome)
	table.insert(stack.models, carry)
	table.insert(stack.designs, design)
	player:SetAttribute("Carrying", #stack.eggs)

	-- (the pickup card: Client/RescueFx). Every pickup (re)starts the chase: the client ignores it while one is
	-- already running.
	if not runs[player] then
		runs[player] = { mult = 1, rings = {}, started = os.clock() }
	end
	if not MapInfo.isSafe(root.Position) then
		DisasterStart:FireClient(player, biome)
	end
end

-- A free spot on the biome's track for an egg of this footprint (radius round its centre, wings and all): never
-- overlapping another egg (their footprints plus a gap; user 2026-11-20: two eggs stood in the same place), and only
-- where the ground under the whole footprint is open floor (no tree, rock or slope in the way).
local EGG_GAP = 9 -- (spread a little: user 2026-11-22)
local MIN_RUN = 190
local function randomSpot(biome: number, radius: number): Vector3?
	local minV, maxV = MapInfo.bounds(biome)
	if not minV then
		return nil
	end
	local zMin, zMax = minV.Z + 18 + radius, maxV.Z - 12 - radius
	-- never right by the safe line: at least MIN_RUN studs of run home, so even Meadow has a few obstacles to get past
	-- (user 2026-11-20: "the biome is too short and you barely have to do anything")
	-- pushed back: eggs only in the far 45% of the biome (like Steal an Egg, the run home is the game; user 2026-11-20)
	local toB = MapInfo.toBase()
	local len = maxV.Z - minV.Z
	if toB.Z < 0 then
		zMin = math.max(zMin, maxV.Z - len * 0.45)
	else
		zMax = math.min(zMax, minV.Z + len * 0.45)
	end
	local line = MapInfo.dangerLine()
	if line then
		local toBase = MapInfo.toBase()
		local far = if toBase.Z < 0 then line.Z + MIN_RUN else line.Z - MIN_RUN
		if toBase.Z < 0 and far < zMax - 10 then
			zMin = math.max(zMin, far)
		elseif toBase.Z > 0 and far > zMin + 10 then
			zMax = math.min(zMax, far)
		end
	end
	local xMin, xMax = minV.X + 4 + radius, maxV.X - 4 - radius
	if zMin >= zMax or xMin >= xMax then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- skip particle volumes like the biomes' *_specks parts
	params.FilterDescendantsInstances = { wildFolder }
	-- eggs hang around TOGETHER in the same few rows (user 2026-11-22: "not too together ... slightly more spread out,
	-- just in the same few rows"): a band across the valley, about three eggs deep, in the middle of the egg area; only if
	-- it's full do they spread over the whole area
	local rowDepth = (radius * 2 + EGG_GAP) * 1.6
	local pcz = (zMin + zMax) / 2
	for attempt = 1, 90 do
		local x, z
		if attempt <= 60 then
			x = rng:NextNumber(xMin, xMax)
			z = math.clamp(pcz + rng:NextNumber(-rowDepth, rowDepth), zMin, zMax)
		else
			x = rng:NextNumber(xMin, xMax)
			z = rng:NextNumber(zMin, zMax)
		end
		local tooClose = false
		for _, other in wild[biome] do
			if other.Parent then
				local p = other:GetPivot().Position
				local need = radius + (other:GetAttribute("Footprint") or radius) + EGG_GAP
				if (Vector2.new(p.X, p.Z) - Vector2.new(x, z)).Magnitude < need then
					tooClose = true
					break
				end
			end
		end
		if tooClose then
			continue
		end
		-- the middle and 8 points round the footprint's edge must all be open ground (not a canopy, rock or hill)
		local ground: Vector3? = nil
		local open = true
		for k = 0, 8 do
			local a = k * math.pi / 4
			local off = if k == 0 then Vector3.zero else Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.85
			local hit = Workspace:Raycast(Vector3.new(x, maxV.Y + 120, z) + off, Vector3.new(0, -200, 0), params)
			if not hit or hit.Position.Y > maxV.Y + 1.5 then
				open = false
				break
			end
			if k == 0 then
				ground = hit.Position
			end
		end
		if open and ground then
			return ground
		end
	end
	return nil
end

function spawnEgg(biome: number)
	local list = wild[biome]
	for i = #list, 1, -1 do
		if not list[i].Parent then
			table.remove(list, i)
		end
	end
	local egg = Config.Eggs[biome]
	if #list >= egg.Count then
		return
	end
	-- (one of the biome's egg designs at random: only the look, user 2026-11-22)
	local model = EggFactory.create(biome, egg.Height, rng:NextInteger(1, EggFactory.DesignCount))
	-- (its footprint: half the diagonal of its box, so any turn fits)
	local _, size = model:GetBoundingBox()
	local radius = math.sqrt(size.X * size.X + size.Z * size.Z) / 2
	model:SetAttribute("Footprint", radius)
	local spot = randomSpot(biome, radius)
	if not spot then
		model:Destroy()
		task.delay(5, spawnEgg, biome)
		return
	end
	local eggName = Config.eggName(biome, model:GetAttribute("Design") :: number?)
	model.Name = eggName
	model:PivotTo(CFrame.new(spot - Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- walk-through: you run past (and through) eggs on the way home (user, 2026-11-20: "I keep running into the eggs")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	eggTag(model, biome)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Save"
	prompt.ObjectText = `{eggName} ({Config.Rarities[egg.Rarity].Name})`
	prompt.HoldDuration = 0.6
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- reachable from anywhere round the egg (its footprint plus a step), measured from a point just above the ground:
	-- on the big eggs the prompt used to sit at the egg's centre, high in the air, and never showed (user 2026-11-20:
	-- "sometimes I can't collect an egg")
	prompt.MaxActivationDistance = radius + 9
	prompt.RequiresLineOfSight = false
	local promptAt = Instance.new("Attachment")
	promptAt.Name = "PromptAt"
	promptAt.Parent = model.PrimaryPart
	promptAt.WorldPosition = model:GetPivot().Position + Vector3.new(0, 3, 0)
	prompt.Parent = promptAt
	prompt.Triggered:Connect(function(player)
		onEggPickup(player, model, biome)
	end)

	CollectionService:AddTag(model, "WildEgg")
	model.Parent = wildFolder
	table.insert(list, model)
end

-- Hatching: one of the biome's animals, the rarer ones likelier with more luck
-- (returns the animal and the % chance it had at that luck: the hatch screen shows it)
local function hatch(biome: number, luck: number): (string, number)
	local ids, chances = Config.hatchChances(biome, luck)
	local i = Util.weightedPick(rng, chances)
	return ids[i], chances[i]
end
AnimalService.hatch = hatch

-- Carrying / deposit --------------------------------------------------------------------------------------------

local function clearStack(player: Player): ({ number }, { number })
	runs[player] = nil
	local stack = carried[player]
	carried[player] = nil
	player:SetAttribute("Carrying", 0)
	if not stack then
		return {}, {}
	end
	for _, model in stack.models do
		model:Destroy()
	end
	return stack.eggs, stack.designs
end

local function deposit(player: Player)
	local data = DataService.get(player)
	local run = runs[player]
	local eggs, designs = clearStack(player)
	if not data or #eggs == 0 then
		return
	end
	-- the luck: every ring on the way home adds to it; it raises the odds of the rarer animals in every egg
	local luck = math.clamp(if run then run.mult else 1, 1, Config.RunMultiplierCap)
	local newlyFound = {}
	local ids = {}
	local chances = {}
	local income = 0
	for _, biome in eggs do
		local id, chance = hatch(biome, luck)
		table.insert(ids, id)
		table.insert(chances, chance)
		table.insert(data.Inventory, id)
		income += Config.Animals[id].Income
		if not data.Discovered[id] then
			data.Discovered[id] = true
			table.insert(newlyFound, id)
		end
	end
	refreshStats(player)
	-- (the hatch screen: Client/Hatch)
	RunReward:FireClient(player, {
		Eggs = eggs,
		Designs = designs, -- (each egg's look, so the hatch shows the egg you carried)
		Rings = if run then run.rings else {},
		Luck = luck,
		Animals = ids,
		Chances = chances, -- (% chance of each, at this luck)
		New = newlyFound,
		Income = income,
	})
	pushInventory(player)
	-- (nothing is put in your hand: holding an animal starts placing it, and clicks after the hatch screen used to
	-- drop the whole stack into the base without meaning to, user 2026-11-20)
	DisasterEnd:FireClient(player, #eggs, false)
end

local function loseStack(player: Player)
	local ids = clearStack(player)
	if #ids > 0 then
		DisasterEnd:FireClient(player, 0, true)
		notify(player, "You lost the eggs you were carrying...", Color3.fromRGB(255, 90, 90))
	end
end

-- Base animals --------------------------------------------------------------------------------------------------

local function spawnPlaced(player: Player, entry)
	local plot = BaseService.getPlot(player)
	if not plot or not Config.Animals[entry.Id] then
		return
	end
	local model = AnimalFactory.create(
		entry.Id,
		Config.baseAnimalHeight(entry.Id),
		math.min(Config.baseAnimalHeight(entry.Id) * 2.2, Config.MaxBaseAnimalWidth)
	)
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
	prompt.MaxActivationDistance = 8 + Config.baseAnimalHeight(entry.Id) * 0.8
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(who)
		if who == player then
			AnimalService.pickUp(player, entry.Uid, false)
		end
	end)

	CollectionService:AddTag(model, "BaseAnimal")
	model.Parent = baseFolder
	placedModels[player] = placedModels[player] or {}
	placedModels[player][entry.Uid] = model
end

-- takes a placed animal off the base: back into the backpack, or sold (My Animals: Client/AnimalsPanel)
function AnimalService.pickUp(player: Player, uid: string, sellIt: boolean, quiet: boolean?): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local paid = 0
	for i, placed in data.Placed do
		if placed.Uid == uid then
			table.remove(data.Placed, i)
			if sellIt then
				local info = Config.Animals[placed.Id]
				paid = if info then info.Income * Config.SellValueSeconds else 0
				data.Money += paid
			else
				table.insert(data.Inventory, placed.Id)
			end
			break
		end
	end
	local models = placedModels[player]
	local model = models and models[uid]
	if models then
		models[uid] = nil
	end
	if model then
		model:Destroy()
	end
	if not quiet then
		pushInventory(player)
		refreshStats(player)
	end
	return paid
end

-- a free spot in the base for an animal placed from the menu: the grid point furthest from the others
local function freeSpot(player: Player, data: any): (number?, number?)
	local plot = BaseService.getPlot(player)
	if not plot then
		return nil, nil
	end
	local b = plot.Bounds
	local bestX, bestZ, bestD = nil, nil, -1
	local x = b.MinX + 3
	while x <= b.MaxX - 3 do
		local z = b.MinZ + 4
		while z <= b.MaxZ - 3 do
			local d = 1e9
			for _, e in data.Placed do
				d = math.min(d, (Vector2.new(e.X, e.Z) - Vector2.new(x, z)).Magnitude)
			end
			-- (a little nearer the front is nicer: you see them from the gate)
			d -= z * 0.02
			if d > bestD then
				bestX, bestZ, bestD = x, z, d
			end
			z += 3
		end
		x += 3
	end
	return bestX, bestZ
end

local function placeFromMenu(player: Player, id: string, quiet: boolean?): boolean
	local data = DataService.get(player)
	if not data or #data.Placed >= BaseService.capacity(data) then
		if not quiet then
			notify(player, "Your base is full! Upgrade your base for more room.", Color3.fromRGB(255, 120, 80))
		end
		return false
	end
	local index = table.find(data.Inventory, id)
	local x, z = freeSpot(player, data)
	if not index or not x then
		return false
	end
	table.remove(data.Inventory, index)
	local entry = { Uid = HttpService:GenerateGUID(false), Id = id, X = x, Z = z :: number, R = 0 }
	table.insert(data.Placed, entry)
	spawnPlaced(player, entry)
	if not quiet then
		pushInventory(player)
		refreshStats(player)
	end
	return true
end

-- the best earners on the base, as many as fit; the rest go in the backpack
local function equipBest(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local cap = BaseService.capacity(data)
	local all = {}
	for _, e in data.Placed do
		table.insert(all, { id = e.Id, uid = e.Uid, income = (Config.Animals[e.Id] or { Income = 0 }).Income })
	end
	for _, id in data.Inventory do
		local info = Config.parseKey(id)
		if info then
			table.insert(all, { id = info.Id, income = info.Income })
		end
	end
	table.sort(all, function(a, b)
		if a.income ~= b.income then
			return a.income > b.income
		end
		return (a.uid ~= nil) and (b.uid == nil) -- (keep the ones already out)
	end)
	local keep = {}
	for i = 1, math.min(cap, #all) do
		keep[all[i]] = true
	end
	local changed = 0
	for _, a in all do
		if a.uid and not keep[a] then
			AnimalService.pickUp(player, a.uid, false, true)
			changed += 1
		end
	end
	for _, a in all do
		if not a.uid and keep[a] then
			if placeFromMenu(player, a.id, true) then
				changed += 1
			end
		end
	end
	pushInventory(player)
	refreshStats(player)
	notify(
		player,
		if changed > 0 then "Your best animals are on your base! ⭐" else "Your best animals are already out! ⭐",
		Color3.fromRGB(255, 220, 90)
	)
end

local function onPlace(player: Player, key: unknown, x: unknown, z: unknown, rotation: unknown)
	if type(key) ~= "string" or type(x) ~= "number" or type(z) ~= "number" or type(rotation) ~= "number" then
		return
	end
	local info = Config.parseKey(key)
	if x ~= x or z ~= z or rotation ~= rotation or not info then
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
	local index = table.find(data.Inventory, key)
	if not index then
		return
	end
	table.remove(data.Inventory, index)
	local entry = {
		Uid = HttpService:GenerateGUID(false),
		Id = info.Id,
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

	-- Drop unknown ids (e.g. after renaming an animal in Config). Old run-bonus keys ("Chicken*8") become plain ids:
	-- luck no longer changes income (2026-11-20).
	for i = #data.Inventory, 1, -1 do
		local info = Config.parseKey(data.Inventory[i])
		if info then
			data.Inventory[i] = info.Id
		else
			table.remove(data.Inventory, i)
		end
	end
	for i = #data.Placed, 1, -1 do
		if not Config.Animals[data.Placed[i].Id] then
			table.remove(data.Placed, i)
		else
			data.Placed[i].M = nil
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
	for _, key in data.Inventory do
		data.Discovered[Config.parseKey(key).Id] = true
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
	wildFolder.Name = "WildEggs"
	wildFolder.Parent = Workspace
	baseFolder = Instance.new("Folder")
	baseFolder.Name = "BaseAnimals"
	baseFolder.Parent = Workspace

	-- The KeyframeSequences are only useful for editing; keep them off the client download (they live in
	-- ServerStorage.AnimalAnimSaves in the place since 2026-11-20; this catches any added back under Assets).
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
		for _ = 1, Config.Eggs[biome].Count do
			spawnEgg(biome)
		end
	end
	-- eggs ALWAYS come back (user 2026-11-22): besides the respawn after each pickup, every 10 s each biome is topped
	-- up to its full count (spawnEgg does nothing when it's full)
	task.spawn(function()
		while true do
			task.wait(10)
			for biome = 1, #Config.Biomes do
				local list = wild[biome]
				local alive = 0
				for _, m in list do
					if m.Parent and not m:GetAttribute("Taken") then
						alive += 1
					end
				end
				for _ = alive + 1, Config.Eggs[biome].Count do
					pcall(spawnEgg, biome)
				end
			end
		end
	end)

	PlaceAnimal.OnServerEvent:Connect(onPlace)
	Net.event("AnimalAction").OnServerEvent:Connect(function(player, action, arg)
		local data = DataService.get(player)
		if not data then
			return
		end
		if action == "EquipBest" then
			equipBest(player)
		elseif action == "PickUp" and type(arg) == "string" then
			AnimalService.pickUp(player, arg, false)
		elseif action == "SellPlaced" and type(arg) == "string" then
			local paid = AnimalService.pickUp(player, arg, true)
			if paid > 0 then
				Net.event("Purchased"):FireClient(player)
				notify(player, `Sold for ${Util.formatNumber(paid)}!`, Color3.fromRGB(120, 255, 140))
			end
		elseif action == "Sell" and type(arg) == "string" then
			local index = table.find(data.Inventory, arg)
			if index then
				table.remove(data.Inventory, index)
				local paid = Config.keyIncome(arg) * Config.SellValueSeconds
				data.Money += paid
				pushInventory(player)
				refreshStats(player)
				Net.event("Purchased"):FireClient(player)
				notify(player, `Sold for ${Util.formatNumber(paid)}!`, Color3.fromRGB(120, 255, 140))
			end
		elseif action == "Place" and type(arg) == "string" then
			placeFromMenu(player, arg)
		end
	end)
	GetState.OnServerInvoke = function(player)
		return AnimalService.state(player)
	end

	-- a luck ring on the run home: only while carrying eggs, only the ring values that exist, a few a
	-- second at most, the total capped
	Net.event("RunRing").OnServerEvent:Connect(function(player, value)
		local run = runs[player]
		if not run or type(value) ~= "number" or not table.find(Config.RunRingValues, value) then
			return
		end
		if #run.rings >= 150 or #run.rings > (os.clock() - run.started) * 4 + 4 then
			return
		end
		table.insert(run.rings, value)
		run.mult = math.min(run.mult * value, Config.RunMultiplierCap) -- (badges multiply)
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

	-- one animal's Index reward (cash = 100x its income, plus speed); nil if it can't be claimed
	local function claimIndex(data: any, id: string): (number?, number?)
		local info = Config.Animals[id]
		if not info or not data.Discovered[id] or data.IndexClaimed[id] then
			return nil, nil
		end
		data.IndexClaimed[id] = true
		local money = info.Income * Config.IndexRewardSeconds
		local speed = Config.IndexRewardSpeed[info.Rarity] or 1
		data.Money += money
		data.Speed += speed
		return money, speed
	end
	Net.event("ClaimIndexReward").OnServerEvent:Connect(function(player, id)
		local data = DataService.get(player)
		if not data or type(id) ~= "string" then
			return
		end
		local money, speed = claimIndex(data, id)
		if not money then
			return
		end
		refreshStats(player)
		AnimalService.pushState(player)
		notify(
			player,
			`Index reward: +${Util.formatNumber(money)} and +{speed} speed!`,
			Config.Rarities[Config.Animals[id].Rarity].Color
		)
	end)
	-- Claim All (user 2026-11-22, like Steal an Egg): every unclaimed reward at once, one message
	Net.event("ClaimIndexAll").OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if not data then
			return
		end
		local totalMoney, totalSpeed, n = 0, 0, 0
		for id in data.Discovered do
			local money, speed = claimIndex(data, id)
			if money then
				totalMoney += money
				totalSpeed += speed :: number
				n += 1
			end
		end
		if n == 0 then
			return
		end
		refreshStats(player)
		AnimalService.pushState(player)
		notify(
			player,
			`Claimed {n} Index rewards: +${Util.formatNumber(totalMoney)} and +{Util.formatNumber(totalSpeed)} speed!`,
			Color3.fromRGB(120, 255, 140)
		)
	end)
	-- a whole biome found: its extra cash reward, once (like Throw Food for Animals)
	Net.event("ClaimBiomeReward").OnServerEvent:Connect(function(player, biome)
		local data = DataService.get(player)
		local b = type(biome) == "number" and Config.Biomes[biome] and biome
		if not data or not b then
			return
		end
		local key = tostring(b)
		data.BiomeClaimed = data.BiomeClaimed or {}
		if data.BiomeClaimed[key] then
			return
		end
		for _, id in Config.Biomes[b].Animals do
			if not data.Discovered[id] then
				return
			end
		end
		data.BiomeClaimed[key] = true
		local money = Config.biomeCompleteReward(b)
		data.Money += money
		refreshStats(player)
		AnimalService.pushState(player)
		notify(player, `{Config.Biomes[b].Name} complete! +${Util.formatNumber(money)}`, Color3.fromRGB(255, 215, 60))
	end)

	Net.event("SellAnimals").OnServerEvent:Connect(function(player, ids)
		local data = DataService.get(player)
		if not data or type(ids) ~= "table" or #ids > 50 then
			return
		end
		local total, count = 0, 0
		for _, key in ids do
			local index = type(key) == "string" and table.find(data.Inventory, key)
			if index then
				table.remove(data.Inventory, index)
				total += Config.keyIncome(key) * Config.SellValueSeconds
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
				if root and #stack.eggs > 0 and MapInfo.isSafe(root.Position) then
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
