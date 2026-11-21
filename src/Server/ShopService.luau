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

-- The equipped trail on your character, as in "[NEW] Feed and Rob Animals" (TrailService): a soft glow band with a
-- bright core inside it, both facing the camera, the core tapering off toward the tail, the colour running from your
-- back to the tail (Config.Trails Look). The better ones leave sparkles (stars, clouds) while you run, and the further
-- down the list, the taller, longer and brighter.
local SPARK_SPEED = 6 -- studs/s: sparkles only while you're moving this fast
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local PUFF = "rbxasset://textures/particles/smoke_main.dds"

local function colours(list: { Color3 }): ColorSequence
	if #list == 1 then
		return ColorSequence.new(list[1])
	end
	local keys = {}
	for i, c in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), c))
	end
	return ColorSequence.new(keys)
end

-- hard bands of the colours one after another down the trail (the Zebra Trail's stripes)
local function bands(list: { Color3 }, count: number): ColorSequence
	local n = math.clamp(math.floor(count), 1, 10)
	local keys = {}
	for i = 0, n - 1 do
		local c = list[i % #list + 1]
		table.insert(keys, ColorSequenceKeypoint.new(if i == 0 then 0 else i / n + 0.002, c))
		table.insert(keys, ColorSequenceKeypoint.new((i + 1) / n, c))
	end
	return ColorSequence.new(keys)
end

local function ribbon(
	parent: Instance,
	a0: Attachment,
	a1: Attachment,
	color: ColorSequence,
	life: number,
	emission: number,
	bright: number,
	alpha: number,
	taper: number
)
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Color = color
	tr.Lifetime = life
	tr.MinLength = 0.05
	tr.FaceCamera = true
	tr.LightEmission = emission
	tr.LightInfluence = 0
	tr.Brightness = bright
	tr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, alpha),
		NumberSequenceKeypoint.new(0.35, alpha + (1 - alpha) * 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	tr.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, taper),
	})
	tr.Parent = parent
	return tr
end

-- a particle emitter left off: the loop in init runs it at its "Rate" attribute while you move
local function emitter(parent: Instance, color: Color3, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparks"
	e.Color = ColorSequence.new(color)
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	e.Rate = 0
	e:SetAttribute("Rate", rate)
	e.Parent = parent
	return e
end

local function buildTrail(info, hrp: BasePart, holder: Instance): { Instance }
	local look = info.Look
	local rank = (info.Index - 1) / math.max(1, #Config.Trails - 1) -- 0 .. 1 down the list
	local span = 2.4 + 1.6 * rank -- studs tall
	local bottom = -span / 2 -- (centred on the middle of the body, not the legs; user 2026-11-20)
	local made: { Instance } = {}
	local function att(name: string, y: number): Attachment
		local at = Instance.new("Attachment")
		at.Name = name
		at.Position = Vector3.new(0, y, 0.35)
		at.Parent = hrp
		table.insert(made, at)
		return at
	end
	local life = 0.55 + 0.5 * rank
	local seq = if look.Stripes then bands(look.Colors, look.Stripes) else colours(look.Colors)
	ribbon(
		holder,
		att("ShopTrailGlow0", bottom + span),
		att("ShopTrailGlow1", bottom),
		if look.Glow then ColorSequence.new(look.Glow) else seq,
		life,
		look.GlowEmission or 1,
		look.GlowBright or 1 + rank,
		look.GlowAlpha or 0.6,
		0.55
	)
	ribbon(
		holder,
		att("ShopTrailCore0", bottom + span * 0.8),
		att("ShopTrailCore1", bottom + span * 0.2),
		seq,
		life * 0.85,
		look.Core or 0.6,
		look.Bright or 1 + 2 * rank,
		0,
		0.2
	)
	local spot: Attachment? = nil
	local function fxSpot(): Attachment
		spot = spot or att("ShopTrailSparks", bottom + span * 0.45)
		return spot :: Attachment
	end
	if look.Sparks then
		for _, c in look.Sparks do
			local e = emitter(fxSpot(), c, (10 + 36 * rank) / #look.Sparks)
			-- (a dark sparkle drawn as light would vanish: solid instead)
			local dark = c.R * 0.3 + c.G * 0.59 + c.B * 0.11 < 0.25
			e.Texture = SPARKLE
			e.LightEmission = if dark then 0 else 1
			e.Brightness = if dark then 1 else 1 + rank
			e.Lifetime = NumberRange.new(0.45, 0.9)
			e.Speed = NumberRange.new(0.5, 2)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Drag = 3
			e.Acceleration = Vector3.new(0, 3, 0)
			local size = 0.3 + 0.25 * rank
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, size),
				NumberSequenceKeypoint.new(0.5, size * 0.8),
				NumberSequenceKeypoint.new(1, 0),
			})
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.7, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.RotSpeed = NumberRange.new(-180, 180)
		end
	end
	-- a galaxy's stars: tiny points that hang in the air behind you and twinkle as they fade
	if look.Stars then
		for _, c in look.Stars do
			local e = emitter(fxSpot(), c, (14 + 24 * rank) / #look.Stars)
			e.Texture = SPARKLE
			e.LightEmission = 1
			e.Brightness = 2
			e.Lifetime = NumberRange.new(0.8, 1.6)
			e.Speed = NumberRange.new(1.5, 5)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Drag = 5
			local sz = 0.22
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.1, sz),
				NumberSequenceKeypoint.new(0.25, sz * 0.35),
				NumberSequenceKeypoint.new(0.4, sz),
				NumberSequenceKeypoint.new(0.55, sz * 0.35),
				NumberSequenceKeypoint.new(0.7, sz * 0.9),
				NumberSequenceKeypoint.new(1, 0),
			})
			e.RotSpeed = NumberRange.new(-40, 40)
		end
	end
	-- heavenly clouds: soft bright puffs left behind you, slowly rising and swelling as they fade
	if look.Clouds then
		local e = emitter(fxSpot(), look.Clouds, 7)
		e.Texture = PUFF
		e.LightEmission = 0.35
		e.Brightness = 1.2
		e.Lifetime = NumberRange.new(1, 1.6)
		e.Speed = NumberRange.new(0.4, 1.2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 1.2, 0)
		e.Drag = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.RotSpeed = NumberRange.new(-20, 20)
	end
	-- a glow of light around you
	if look.Light then
		local light = Instance.new("PointLight")
		light.Name = "ShopTrailLight"
		light.Color = look.Light
		light.Range = 12
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = att("ShopTrailAura", 0)
	end
	return made
end

local function applyTrail(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not root then
		return
	end
	local old = root:FindFirstChild("ShopTrail")
	if old then
		old:Destroy()
	end
	local info = Config.Trails[data.EquippedTrail]
	if not info or not data.Trails[tostring(data.EquippedTrail)] then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "ShopTrail"
	local made = buildTrail(info, root, holder)
	holder.Destroying:Connect(function()
		for _, m in made do
			m:Destroy()
		end
	end)
	holder.Parent = root
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
	-- trail sparkles only while you run (the trail itself fades on its own when you stop)
	task.spawn(function()
		while true do
			task.wait(0.15)
			for _, p in Players:GetPlayers() do
				local char = p.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local spot = hrp and hrp:FindFirstChild("ShopTrailSparks")
				if hrp and spot then
					local v = hrp.AssemblyLinearVelocity
					local moving = Vector2.new(v.X, v.Z).Magnitude > SPARK_SPEED
					for _, e in spot:GetChildren() do
						if e:IsA("ParticleEmitter") then
							local want = if moving then (e:GetAttribute("Rate") :: number?) or 0 else 0
							if e.Rate ~= want then
								e.Rate = want
							end
						end
					end
				end
			end
		end
	end)
	Net.event("BuyTrail").OnServerEvent:Connect(function(player, index)
		local data = DataService.get(player)
		local info = type(index) == "number" and Config.Trails[index]
		if not data or not info then
			return
		end
		local key = tostring(index)
		if data.Trails[key] then
			data.EquippedTrail = index
			notify(
				player,
				`Equipped {info.Name}! Training speed x{Util.formatNumber(info.Multiplier)}`,
				Color3.fromRGB(120, 255, 140)
			)
		elseif data.Money >= info.Price then
			data.Money -= info.Price
			data.Trails[key] = true
			data.EquippedTrail = index
			notify(
				player,
				`Bought {info.Name}! Training speed x{Util.formatNumber(info.Multiplier)}`,
				Color3.fromRGB(120, 255, 140)
			)
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
		local info = Config.Trails[index]
		if info then
			notify(
				player,
				`Equipped {info.Name}! Training speed x{Util.formatNumber(info.Multiplier)}`,
				Color3.fromRGB(120, 255, 140)
			)
		end
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
