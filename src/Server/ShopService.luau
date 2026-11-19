-- Shops from the UI pack: trails (in-game money), the free item, and Robux developer products.
-- Product ids live in Config.Products; any left at 0 just answer "Coming soon".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local Progression = require(Shared.Progression)

local AnimalService = require(script.Parent.AnimalService)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)

local ShopService = {}

local Notify = Net.event("Notify")
local Purchased = Net.event("Purchased")

local function notify(player: Player, text: string, color: Color3?)
	Notify:FireClient(player, text, color)
end

-- Training multiplier (speed points per treadmill step) = equipped trail x purchased "double speed".
local function refreshMultiplier(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local trail = Config.Trails[data.EquippedTrail]
	local multiplier = (trail and trail.Multiplier or 1) * (data.SpeedMultiplier or 1)
	player:SetAttribute("SpeedMultiplier", math.round(multiplier * 100) / 100)
end
ShopService.refreshMultiplier = refreshMultiplier

local function rainbow(): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.85, 1)))
	end
	return ColorSequence.new(keys)
end

local function applyTrail(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not data or not root then
		return
	end
	local old = root:FindFirstChild("SAFDTrail")
	if old then
		old:Destroy()
	end
	for _, name in { "SAFDTrailTop", "SAFDTrailBottom" } do
		local a = root:FindFirstChild(name)
		if a then
			a:Destroy()
		end
	end
	local info = Config.Trails[data.EquippedTrail]
	if not info then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "SAFDTrailTop"
	top.Position = Vector3.new(0, 0.9, 0.4)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "SAFDTrailBottom"
	bottom.Position = Vector3.new(0, -1.6, 0.4)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SAFDTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Color = if info.Rainbow then rainbow() else ColorSequence.new(info.Color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail:SetAttribute("Owner", player.UserId)
	trail.Parent = root
end

local function grant(player: Player, key: string): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	if key == "Card_BestValue" then
		data.Money += 1e9
	elseif key:match("^Card_Small") then
		data.Money += 150000
	elseif key == "Card_Upgrade" then
		data.TreadmillLevel = math.min((data.TreadmillLevel or 1) + 1, #Progression.Treadmill)
		BaseService.applyTiers(player, data)
		notify(player, `Treadmill upgraded to Lv. {data.TreadmillLevel}!`, Color3.fromRGB(120, 255, 140))
	elseif key == "Card_Double" or key == "2xSpeed" then
		data.SpeedMultiplier = math.min((data.SpeedMultiplier or 1) * 2, 64)
		refreshMultiplier(player)
	elseif key == "OfflineX2" then
		local amount = data.PendingOffline * 2
		data.PendingOffline = 0
		data.Money += amount
	else
		return false
	end
	AnimalService.refreshStats(player)
	AnimalService.pushState(player)
	Purchased:FireClient(player, key)
	return true
end

function ShopService.playerLoaded(player: Player)
	refreshMultiplier(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		applyTrail(player)
	end)
	applyTrail(player)
end

function ShopService.init()
	Net.event("BuyTrail").OnServerEvent:Connect(function(player, index)
		local data = DataService.get(player)
		local info = type(index) == "number" and Config.Trails[index]
		if not data or not info then
			return
		end
		local key = tostring(index)
		if data.Trails[key] then
			data.EquippedTrail = index
		elseif data.Money >= info.Price then
			data.Money -= info.Price
			data.Trails[key] = true
			data.EquippedTrail = index
			notify(player, `Bought {info.Name}! Speed x{info.Multiplier}`, Color3.fromRGB(120, 255, 140))
			Purchased:FireClient(player, "Trail")
		else
			notify(player, `You need ${Util.formatNumber(info.Price)} for {info.Name}.`, Color3.fromRGB(255, 120, 80))
			return
		end
		refreshMultiplier(player)
		applyTrail(player)
		AnimalService.refreshStats(player)
		AnimalService.pushState(player)
	end)

	Net.event("EquipTrail").OnServerEvent:Connect(function(player, index)
		local data = DataService.get(player)
		if not data or type(index) ~= "number" then
			return
		end
		if index ~= 0 and not data.Trails[tostring(index)] then
			return
		end
		data.EquippedTrail = index
		refreshMultiplier(player)
		applyTrail(player)
		AnimalService.pushState(player)
	end)

	-- Upgrade signs beside the base and the treadmill (Client/UpgradeSigns): pay the next level in cash.
	Net.event("BuyUpgrade").OnServerEvent:Connect(function(player, kind)
		local data = DataService.get(player)
		if not data or (kind ~= "Base" and kind ~= "Treadmill") then
			return
		end
		local field = if kind == "Base" then "BaseTier" else "TreadmillLevel"
		local list = if kind == "Base" then Progression.Base else Progression.Treadmill
		local level = data[field] or 1
		local nextRow = list[level + 1]
		if not nextRow then
			notify(player, `Your {string.lower(kind)} is already max level!`, Color3.fromRGB(255, 220, 90))
			return
		end
		if data.Money < nextRow.Price then
			notify(player, `You need ${Progression.short(nextRow.Price)}!`, Color3.fromRGB(255, 120, 80))
			return
		end
		data.Money -= nextRow.Price
		Purchased:FireClient(player, kind)
		data[field] = level + 1
		BaseService.applyTiers(player, data)
		AnimalService.refreshStats(player)
		AnimalService.pushState(player)
		if kind == "Base" then
			notify(
				player,
				`Base upgraded to Lv. {level + 1}! Room for {nextRow.PetSlots} animals.`,
				Color3.fromRGB(120, 255, 140)
			)
		else
			notify(
				player,
				`{nextRow.DisplayName} Treadmill unlocked! +{Progression.short(nextRow.Gain)} speed per step.`,
				Color3.fromRGB(120, 255, 140)
			)
		end
	end)

	Net.event("ClaimFreeItem").OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if not data or data.FreeItemClaimed then
			return
		end
		if Config.GroupId > 0 then
			local ok, inGroup = pcall(player.IsInGroup, player, Config.GroupId)
			if not ok or not inGroup then
				notify(player, "Join the group first, then claim!", Color3.fromRGB(255, 120, 80))
				return
			end
		end
		data.FreeItemClaimed = true
		data.Speed += Config.FreeItemSpeed
		AnimalService.refreshStats(player)
		AnimalService.pushState(player)
		notify(player, `Free reward: +{Config.FreeItemSpeed} speed!`, Color3.fromRGB(120, 255, 140))
	end)

	Net.event("ProductRequest").OnServerEvent:Connect(function(player, key)
		local id = type(key) == "string" and Config.Products[key]
		if id and id > 0 then
			MarketplaceService:PromptProductPurchase(player, id)
		else
			notify(player, "Coming soon!", Color3.fromRGB(255, 220, 90))
		end
	end)

	local keyById = {}
	for key, id in Config.Products do
		if id > 0 then
			keyById[id] = key
		end
	end
	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local data = player and DataService.get(player)
		local key = keyById[receipt.ProductId]
		if not player or not data or not key then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		data.Receipts = data.Receipts or {}
		if table.find(data.Receipts, receipt.PurchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if not grant(player, key) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(data.Receipts, receipt.PurchaseId)
		while #data.Receipts > 50 do
			table.remove(data.Receipts, 1)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return ShopService
