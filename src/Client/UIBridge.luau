-- Connects the imported UI pack (StarterGui: Hud, Index, All items, Offline Cash, Sell Pets, Speed Shop,
-- TrailsShop, FREE ITEM, Settings, ...) to real game data. The pack's own controllers keep owning their
-- animations; this module only writes text / attributes and answers their request events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalFactory = require(Shared.AnimalFactory)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UIBridge = {}

local state = {
	Inventory = {},
	Discovered = {},
	IndexClaimed = {},
	Trails = {},
	EquippedTrail = 0,
	PendingOffline = 0,
	FreeItemClaimed = false,
}

local function gui(name: string): ScreenGui?
	return playerGui:WaitForChild(name, 15) :: ScreenGui?
end

local function find(root: Instance?, path: string): Instance?
	local node = root
	for part in string.gmatch(path, "[^%.]+") do
		if not node then
			return nil
		end
		node = node:FindFirstChild(part)
	end
	return node
end

local function setText(root: Instance?, path: string, text: string)
	local label = find(root, path)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.Text = text
	end
end

local function money(n: number): string
	return "$" .. Util.formatNumber(n)
end

-- A spinning-free 3D thumbnail of an animal, laid over an ImageLabel slot.
local function viewport(parent: GuiObject, id: string): ViewportFrame
	local old = parent:FindFirstChild("AnimalViewport")
	if old then
		old:Destroy()
	end
	if parent:IsA("ImageLabel") then
		parent.ImageTransparency = 1
	end
	local frame = Instance.new("ViewportFrame")
	frame.Name = "AnimalViewport"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Ambient = Color3.fromRGB(170, 170, 170)
	frame.LightDirection = Vector3.new(-0.5, -1, 0.6)
	frame.ZIndex = parent.ZIndex
	local model = AnimalFactory.create(id, 4, 4)
	-- unturned, an animal faces -Z (as it walks in the world); the camera sits in front of it, a little to its side
	model:PivotTo(CFrame.identity)
	model.Parent = frame
	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = math.max(size.X, size.Y, size.Z) * 1.7 + 1
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0.6, 0.3, -1).Unit * distance, cf.Position)
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent
	return frame
end

local function animalsInOrder(): { string }
	local list = {}
	for _, biome in Config.Biomes do
		for _, id in biome.Animals do
			table.insert(list, id)
		end
	end
	return list
end

-- Hud ------------------------------------------------------------------------------------------------------------

local hud: ScreenGui?
local function refreshHud()
	if not hud then
		return
	end
	setText(hud, "Container.Stats.Money.Amount", money(player:GetAttribute("Money") or 0) .. " ")
	setText(hud, "Container.Stats.Money.Gain", "+" .. money(player:GetAttribute("Income") or 0) .. "/s")
	-- speed points, the number the biome banner's "Recommended: N Speed" is compared with (like the reference)
	setText(hud, "Container.Stats.Speed.Amount", Util.formatNumber(math.floor(player:GetAttribute("Speed") or 0)))
	local multiplier = player:GetAttribute("SpeedMultiplier") or 1
	local multLabel = find(hud, "Container.Stats.Speed.Multiplier")
	if multLabel and multLabel:IsA("TextLabel") then
		multLabel.Text = `(x{multiplier})`
		multLabel.Visible = multiplier ~= 1
	end
end

local function setupHud()
	hud = gui("Hud")
	if not hud then
		return
	end
	-- No eggs / equipped-pets systems in this game.
	local right = find(hud, "Container.RightNavigation")
	if right and right:IsA("GuiObject") then
		-- The pack's side-panel controller shows it again; keep it hidden.
		right.Visible = false
		right:GetPropertyChangedSignal("Visible"):Connect(function()
			if right.Visible then
				right.Visible = false
			end
		end)
	end
	local add = find(hud, "Container.Stats.Speed.AddButton")
	if add and add:IsA("GuiButton") then
		add.Activated:Connect(function()
			local trails = playerGui:FindFirstChild("TrailsShop")
			if trails then
				trails:SetAttribute("TrailShopOpen", true)
			end
		end)
	end
	for _, attr in { "Money", "Income", "Speed", "SpeedMultiplier", "SlowMode" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshHud)
	end
	refreshHud()
end

-- Offline Cash ---------------------------------------------------------------------------------------------------

local offline: ScreenGui?
local function refreshOffline(openIfPending: boolean)
	if not offline then
		return
	end
	setText(offline, "Container.Content.Body.Amount", money(state.PendingOffline))
	local double = find(offline, "Container.Content.Actions.DoubleClaimButton")
	if double and double:IsA("GuiObject") then
		double.Visible = (Config.Products.OfflineX2 or 0) > 0
	end
	if openIfPending and state.PendingOffline > 0 then
		offline:SetAttribute("OfflineCashOpen", true)
	end
end

local function setupOffline()
	offline = gui("Offline Cash")
	if not offline then
		return
	end
	if state.PendingOffline <= 0 then
		offline:SetAttribute("OfflineCashOpen", false)
	end
	local claim = offline:WaitForChild("ClaimRequested", 5) :: BindableEvent?
	if claim then
		claim.Event:Connect(function(multiplier)
			if multiplier == 2 then
				Net.event("ProductRequest"):FireServer("OfflineX2")
			else
				Net.event("ClaimOffline"):FireServer()
			end
			offline:SetAttribute("OfflineCashOpen", false)
		end)
	end
	refreshOffline(true)
end

-- Index ----------------------------------------------------------------------------------------------------------

local index: ScreenGui?
local indexEntries: { [string]: GuiButton } = {}

local function refreshIndex()
	for id, button in indexEntries do
		local info = Config.Animals[id]
		button:SetAttribute("Unlocked", state.Discovered[id] == true)
		button:SetAttribute("RewardClaimed", state.IndexClaimed[id] == true)
		button:SetAttribute("MoneyReward", Util.formatNumber(info.Income * Config.IndexRewardSeconds))
		local vp = find(button, "Visual.Icon.AnimalViewport")
		if vp and vp:IsA("ViewportFrame") then
			vp.ImageColor3 = if state.Discovered[id] then Color3.new(1, 1, 1) else Color3.fromRGB(20, 20, 24)
		end
	end
end

local function setupIndex()
	index = gui("Index")
	if not index then
		return
	end
	local scroll = find(index, "Container.Body.CollectionScroll")
	if not scroll then
		return
	end
	index:SetAttribute("TotalCollectionCount", #animalsInOrder())
	for b = 1, 7 do
		local collection = scroll:FindFirstChild(string.format("Collection%02d", b))
		if collection then
			local biome = Config.Biomes[b]
			if not biome then
				collection.Visible = false
				continue
			end
			collection:SetAttribute("WorldName", biome.Name)
			local entries = collection:FindFirstChild("Entries")
			local buttons = {}
			if entries then
				for _, child in entries:GetChildren() do
					if child:IsA("GuiButton") then
						table.insert(buttons, child)
					end
				end
			end
			table.sort(buttons, function(x, y)
				return x.LayoutOrder < y.LayoutOrder
			end)
			for i, button in buttons do
				local id = biome.Animals[i]
				if not id then
					button.Visible = false
					continue
				end
				local info = Config.Animals[id]
				button.Name = id
				button:SetAttribute("ItemId", id)
				button:SetAttribute("DisplayName", info.Name)
				button:SetAttribute("Rarity", Config.Rarities[info.Rarity].Name)
				button:SetAttribute("IncomeText", money(info.Income) .. "/s")
				button:SetAttribute("IncomePerSecond", nil)
				button:SetAttribute("SpeedReward", Config.IndexRewardSpeed[info.Rarity])
				button:SetAttribute("IconImage", "")
				local icon = find(button, "Visual.Icon")
				if icon and icon:IsA("GuiObject") then
					viewport(icon, id)
				end
				indexEntries[id] = button
			end
		end
	end
	-- Detail preview follows the selected entry.
	local preview = find(index, "Container.Body.SelectionPanel.Preview.Icon")
	local selection = index:WaitForChild("SelectionChanged", 5) :: BindableEvent?
	local function showSelected(id: string?)
		if preview and preview:IsA("GuiObject") and id and Config.Animals[id] then
			local vp = viewport(preview, id)
			vp.ImageColor3 = if state.Discovered[id] then Color3.new(1, 1, 1) else Color3.fromRGB(20, 20, 24)
		end
	end
	if selection then
		selection.Event:Connect(function(id)
			showSelected(id)
		end)
	end
	index:GetAttributeChangedSignal("IndexOpen"):Connect(function()
		if index and index:GetAttribute("IndexOpen") then
			showSelected(index:GetAttribute("SelectedEntry") or animalsInOrder()[1])
		end
	end)
	local reward = index:WaitForChild("RewardRequested", 5) :: BindableEvent?
	if reward then
		reward.Event:Connect(function(id)
			Net.event("ClaimIndexReward"):FireServer(id)
		end)
	end
	refreshIndex()
end

-- All items (backpack panel + 1-9 hotbar of animal tools) --------------------------------------------------------

local allItems: ScreenGui?
local allItemsList: { { id: string } } = {}

local function refreshAllItems()
	if not allItems then
		return
	end
	local setItems = allItems:FindFirstChild("SetItems") :: BindableEvent?
	if not setItems then
		return
	end
	local counts, order = {}, {}
	for _, id in state.Inventory do
		if not counts[id] then
			table.insert(order, id)
		end
		counts[id] = (counts[id] or 0) + 1
	end
	table.sort(order, function(a, b)
		local ia, ib = Config.Animals[a], Config.Animals[b]
		if ia.Rarity ~= ib.Rarity then
			return ia.Rarity > ib.Rarity
		end
		return ia.Biome > ib.Biome
	end)
	allItemsList = {}
	local list = {}
	for _, id in order do
		local info = Config.Animals[id]
		table.insert(allItemsList, { id = id })
		table.insert(list, {
			id = id,
			name = info.Name,
			kg = "",
			label = `{info.Name} x{counts[id]} ({money(info.Income)}/s)`,
			image = "",
			rarity = Config.Rarities[info.Rarity].Name,
		})
	end
	setItems:Fire("Pets", list)
	setItems:Fire("Eggs", {})
end

local function setupAllItems()
	allItems = gui("All items")
	if not allItems then
		return
	end
	local grid = find(allItems, "Container.Panel.Grid")
	if grid then
		-- Cards are rebuilt by the pack controller; give each one a 3D thumbnail.
		grid.ChildAdded:Connect(function(card)
			local n = tonumber(string.match(card.Name, "^Item_(%d+)$"))
			local entry = n and allItemsList[n]
			local icon = find(card, "IconHolder.Icon")
			if entry and icon and icon:IsA("GuiObject") then
				task.defer(viewport, icon, entry.id)
			end
		end)
	end
	local selected = allItems:WaitForChild("ItemSelected", 5) :: BindableEvent?
	if selected then
		selected.Event:Connect(function(_, item)
			-- Clicking an animal card equips its tool, which starts placement.
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local backpack = player:FindFirstChildOfClass("Backpack")
			if not humanoid or not backpack or type(item) ~= "table" then
				return
			end
			for _, tool in backpack:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("AnimalId") == item.id then
					humanoid:EquipTool(tool)
					allItems:SetAttribute("AllItemsOpen", false)
					return
				end
			end
		end)
	end
	refreshAllItems()
end

-- Sell Pets ------------------------------------------------------------------------------------------------------

local sell: ScreenGui?
local function fillSellCards(category: string?)
	if not sell then
		return
	end
	local root = sell:FindFirstChild("Container")
	if not root then
		return
	end
	local cards = {}
	for _, child in root:GetChildren() do
		if child:GetAttribute("PetCard") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	-- Best (highest income) first.
	local units = table.clone(state.Inventory)
	table.sort(units, function(a, b)
		return Config.Animals[a].Income > Config.Animals[b].Income
	end)
	for i, card in cards do
		local id = if category == "Eggs" then nil else units[i]
		if id then
			local info = Config.Animals[id]
			local value = info.Income * Config.SellValueSeconds
			card:SetAttribute("ItemId", id)
			card:SetAttribute("Value", value)
			card:SetAttribute("Weight", info.Rarity)
			card:SetAttribute("Sold", false)
			card.Visible = true
			setText(card, "Visual.ValueLabel", money(value))
			setText(card, "Visual.WeightLabel", `({info.Name})`)
			setText(card, "Visual.RateLabel", money(info.Income) .. "/s")
			local pet = find(card, "Visual.Pet")
			if pet and pet:IsA("GuiObject") then
				viewport(pet, id)
			end
		else
			card:SetAttribute("Sold", true)
			card:SetAttribute("Selected", false)
			card.Visible = false
		end
	end
	local total = find(root, "TotalValueLabel")
	if total and total:IsA("TextLabel") then
		total.Text = "$0"
	end
end

local function setupSell()
	sell = gui("Sell Pets")
	if not sell then
		return
	end
	sell:GetAttributeChangedSignal("SellPetsOpen"):Connect(function()
		if sell and sell:GetAttribute("SellPetsOpen") then
			-- The pack restocks its demo cards on open; overwrite them right after.
			task.defer(fillSellCards, "Pets")
		end
	end)
	local changed = sell:WaitForChild("CategoryChanged", 5) :: BindableEvent?
	if changed then
		changed.Event:Connect(function(name)
			task.defer(fillSellCards, name)
		end)
	end
	local request = sell:WaitForChild("SellRequested", 5) :: BindableEvent?
	if request then
		request.Event:Connect(function(_, ids)
			Net.event("SellAnimals"):FireServer(ids)
		end)
	end
end

-- Speed Shop / Shop / Gift (Robux) --------------------------------------------------------------------------------

local function setupProducts()
	local speedShop = gui("Speed Shop")
	local purchase = speedShop and speedShop:WaitForChild("PurchaseRequested", 5) :: BindableEvent?
	if purchase then
		purchase.Event:Connect(function(key)
			Net.event("ProductRequest"):FireServer(key)
		end)
	end
	local giftGui = gui("Gift Player")
	local gift = giftGui and giftGui:WaitForChild("GiftRequested", 5) :: BindableEvent?
	if gift then
		gift.Event:Connect(function()
			Net.event("ProductRequest"):FireServer("Gift")
		end)
	end
end

-- Trails ---------------------------------------------------------------------------------------------------------

local trails: ScreenGui?
local function refreshTrails()
	if not trails then
		return
	end
	local scroll = find(trails, "Container.Content.TrailScroll")
	if not scroll then
		return
	end
	for _, card in scroll:GetChildren() do
		local i = card:GetAttribute("TrailIndex")
		local info = i and Config.Trails[i]
		if i and not info then
			card.Visible = false
		elseif info then
			setText(card, "Visual.Title", info.Name)
			setText(card, "Visual.Stats.TextGroup.Multiplier", `x{info.Multiplier}`)
			local owned = state.Trails[tostring(i)] == true
			local label = if state.EquippedTrail == i then "Equipped" elseif owned then "Equip" else money(info.Price)
			setText(card, "Visual.Purchase.MoneyButton.Visual.PriceContent.Price", label)
			local robux = find(card, "Visual.Purchase.RobuxButton")
			if robux and robux:IsA("GuiObject") then
				robux.Visible = (Config.Products["Trail" .. i] or 0) > 0
			end
		end
	end
end

local function setupTrails()
	trails = gui("TrailsShop")
	if not trails then
		return
	end
	local purchase = trails:WaitForChild("PurchaseRequested", 5) :: BindableEvent?
	if purchase then
		purchase.Event:Connect(function(i, currency)
			if currency == "Robux" then
				Net.event("ProductRequest"):FireServer("Trail" .. tostring(i))
			elseif state.EquippedTrail == i then
				Net.event("EquipTrail"):FireServer(0)
			else
				Net.event("BuyTrail"):FireServer(i)
			end
		end)
	end
	refreshTrails()
end

-- Free item ------------------------------------------------------------------------------------------------------

local freeItem: ScreenGui?
local function refreshFreeItem()
	if not freeItem then
		return
	end
	setText(freeItem, "Container.Content.Body.RewardAmount", `+{Config.FreeItemSpeed} SPEED`)
	setText(
		freeItem,
		"Container.Content.ClaimButton.Visual.Label",
		if state.FreeItemClaimed then "Claimed" else "Claim"
	)
end

local function setupFreeItem()
	freeItem = gui("FREE ITEM")
	if not freeItem then
		return
	end
	local claim = freeItem:WaitForChild("ClaimRequested", 5) :: BindableEvent?
	if claim then
		claim.Event:Connect(function()
			if not state.FreeItemClaimed then
				Net.event("ClaimFreeItem"):FireServer()
			end
		end)
	end
	refreshFreeItem()
end

-- Settings (the reference game's panel): music / sfx / animal-sound volume, showing others' and your own base
-- animals, and how big base animals look on your screen (Tiny / Small / Normal) ----------------------------------

local SIZE_FACTOR = { Tiny = 0.35, Small = 0.6, Normal = 1 }

local function applyBaseAnimals()
	local settings = playerGui:FindFirstChild("Settings")
	local showOthers = not settings or settings:GetAttribute("ViewOthersAnimals") ~= false
	local showMine = not settings or settings:GetAttribute("ViewOwnAnimals") ~= false
	local factor = SIZE_FACTOR[settings and settings:GetAttribute("BaseAnimalSize") or "Normal"] or 1
	local folder = Workspace:FindFirstChild("BaseAnimals")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local mine = model:GetAttribute("Owner") == player.UserId
		local visible = if mine then showMine else showOthers
		if model:GetAttribute("LocalHidden") ~= not visible then
			model:SetAttribute("LocalHidden", not visible)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = if visible then 0 else 1
				elseif d:IsA("BillboardGui") then
					d.Enabled = visible
				end
			end
		end
		local base = model:GetAttribute("LocalBaseScale")
		if not base then
			base = model:GetScale()
			model:SetAttribute("LocalBaseScale", base)
		end
		local wanted = base * factor
		if math.abs(model:GetScale() - wanted) > 0.001 then
			pcall(function()
				model:ScaleTo(wanted)
			end)
		end
	end
end

local function setupSettings()
	local settings = gui("Settings")
	if not settings then
		return
	end
	local function apply()
		player:SetAttribute("MusicVolume", settings:GetAttribute("MusicVolume") or 0.5)
		player:SetAttribute("SfxVolume", settings:GetAttribute("SfxVolume") or 0.5)
		player:SetAttribute("AnimalVolume", settings:GetAttribute("AnimalVolume") or 0.5)
		applyBaseAnimals()
	end
	settings.AttributeChanged:Connect(apply)
	apply()
	-- animals are placed and stream in all the time
	task.spawn(function()
		while true do
			task.wait(1)
			applyBaseAnimals()
		end
	end)
end

-- Base signs: "Your Base" on your own base, the owner's avatar + @name on everyone else's -------------------------

-- (base signs: Client/BaseMarkers)

-- Walk-up zones on the spawn stands --------------------------------------------------------------------------------

local ZONES = {
	{ Model = "Speed_stand", Gui = "Speed Shop", Attribute = "SpeedShopOpen" },
	{ Model = "Weight_stand", Gui = "Sell Pets", Attribute = "SellPetsOpen" },
	{ Model = "Free_item_section", Gui = "FREE ITEM", Attribute = "FreeItemOpen" },
}

local function setupZones()
	local inside = {}
	local boxes = {}
	task.spawn(function()
		while true do
			task.wait(0.2)
			local elements = Workspace:FindFirstChild("Spawn_elements")
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not elements or not root then
				continue
			end
			for _, zone in ZONES do
				local box = boxes[zone.Model]
				if not box then
					local model = elements:FindFirstChild(zone.Model)
					if model and model:IsA("Model") then
						local cf, size = model:GetBoundingBox()
						box = { cf = cf, half = size / 2 + Vector3.new(4, 6, 4) }
						boxes[zone.Model] = box
					end
				end
				if box then
					local p = box.cf:PointToObjectSpace(root.Position)
					local now = math.abs(p.X) < box.half.X and math.abs(p.Y) < box.half.Y and math.abs(p.Z) < box.half.Z
					if now ~= (inside[zone.Model] == true) then
						inside[zone.Model] = now
						local target = playerGui:FindFirstChild(zone.Gui)
						if target then
							target:SetAttribute(zone.Attribute, now)
						end
					end
				end
			end
		end
	end)
end

-- State --------------------------------------------------------------------------------------------------------

local function applyState(newState)
	if type(newState) ~= "table" then
		return
	end
	local hadOffline = state.PendingOffline
	for k, v in newState do
		state[k] = v
	end
	refreshHud()
	refreshOffline(hadOffline <= 0 and state.PendingOffline > 0)
	refreshIndex()
	refreshAllItems()
	refreshTrails()
	refreshFreeItem()
	if sell and sell:GetAttribute("SellPetsOpen") then
		fillSellCards("Pets")
	end
end

function UIBridge.init()
	Net.event("StateChanged").OnClientEvent:Connect(applyState)
	task.spawn(function()
		setupHud()
		setupIndex()
		setupAllItems()
		setupSell()
		setupProducts()
		setupTrails()
		setupFreeItem()
		setupSettings()
		setupZones()
		local getState = Net.func("GetState")
		for _ = 1, 60 do
			local ok, result = pcall(getState.InvokeServer, getState)
			if ok and result then
				applyState(result)
				break
			end
			task.wait(1)
		end
		setupOffline()
	end)
end

return UIBridge
