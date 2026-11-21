-- Connects the imported UI pack (StarterGui: Hud, Index, All items, Offline Cash, Sell Pets, Speed Shop,
-- TrailsShop, FREE ITEM, Settings, ...) to real game data. The pack's own controllers keep owning their
-- animations; this module only writes text / attributes and answers their request events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalFactory = require(Shared.AnimalFactory)
local AnimalIcon = require(script.Parent.AnimalIcon)
local BiomeDiorama = require(script.Parent.BiomeDiorama)
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
	BiomeClaimed = {},
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

-- The pack's NativeLayout sizes each label's text once, for the text it had then ("239"), and turns TextScaled off
-- with wrapping still on, so a longer number later ("205.6K", "+$446/s") wrapped and its end vanished onto a second
-- line ("205.", "+$446/"). These labels scale their text to fit, on one line, whatever it says.
local function fitLabel(path: string): TextLabel?
	local label = find(hud, path)
	if not (label and label:IsA("TextLabel")) then
		return nil
	end
	if not label:GetAttribute("NativeRuntimeTextScaled") then
		label:SetAttribute("NativeRuntimeTextScaled", true) -- (NativeLayout leaves TextScaled on for these)
	end
	-- (only TextScaled: turning TextWrapped off turns TextScaled off with it. The numbers have no spaces to wrap at.)
	label.TextScaled = true
	return label
end

local function refreshHud()
	if not hud then
		return
	end
	fitLabel("Container.Stats.Money.Amount")
	fitLabel("Container.Stats.Money.Gain")
	local speedLabel = fitLabel("Container.Stats.Speed.Amount")
	-- (a space after each: the italic font's last letter leans out of the box)
	setText(hud, "Container.Stats.Money.Amount", money(player:GetAttribute("Money") or 0) .. " ")
	setText(hud, "Container.Stats.Money.Gain", "+" .. money(player:GetAttribute("Income") or 0) .. "/s ")
	-- speed points, the number the biome banner's "Recommended: N Speed" is compared with (like the reference)
	setText(
		hud,
		"Container.Stats.Speed.Amount",
		Util.formatNumber(math.floor(player:GetAttribute("Speed") or 0)) .. " "
	)
	local multiplier = player:GetAttribute("SpeedMultiplier") or 1
	local multLabel = find(hud, "Container.Stats.Speed.Multiplier")
	if multLabel and multLabel:IsA("TextLabel") then
		multLabel.Text = `(x{multiplier})`
		multLabel.Visible = multiplier ~= 1
	end
	-- the speed number gets the room up to the multiplier (or the whole row when there is none), left-aligned
	if speedLabel then
		local x0 = speedLabel.Position.X.Scale
		local right = if multLabel
				and multLabel:IsA("GuiObject")
				and multLabel.Visible
			then multLabel.Position.X.Scale - 0.01
			else 0.78
		speedLabel.Size = UDim2.fromScale(right - x0, speedLabel.Size.Y.Scale)
		speedLabel.TextXAlignment = Enum.TextXAlignment.Left
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
		-- (Claim alone in the middle when there's no x2 button: user 2026-11-21)
		local layout = double.Parent and double.Parent:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.HorizontalAlignment = if double.Visible
				then Enum.HorizontalAlignment.Left
				else Enum.HorizontalAlignment.Center
		end
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

local biomePercent: { [number]: TextLabel }
local biomeClaim: { [number]: { set: (string) -> () } } = {}
local claimAllButton: TextButton? = nil
local indexBadge: Frame? = nil
local function refreshIndex()
	local unclaimed = 0
	for b, l in biomePercent do
		local biome = Config.Biomes[b]
		local found = 0
		for _, id in biome.Animals do
			if state.Discovered[id] then
				found += 1
			end
		end
		-- a whole biome found (user 2026-11-22, like Throw Food for Animals): a gold CLAIM button for its extra cash
		-- reward on the card, then "COMPLETE!"
		local complete = found >= #biome.Animals
		local claimed = (state.BiomeClaimed or {})[tostring(b)] == true
		local row = biomeClaim[b]
		if row then
			row.set(if claimed then "Done" elseif complete then "Claim" else "Locked")
		end
		l.Text = if complete then "✅ COMPLETE!" else "(" .. math.floor(found / #biome.Animals * 100 + 0.5) .. "%)"
		if complete and not claimed then
			unclaimed += 1
		end
	end
	local animalRewards = 0
	for id in state.Discovered do
		if Config.Animals[id] and not state.IndexClaimed[id] then
			animalRewards += 1
		end
	end
	unclaimed += animalRewards
	if claimAllButton then
		claimAllButton.Visible = animalRewards > 0
		claimAllButton.Text = "CLAIM ALL (" .. animalRewards .. ")"
	end
	-- the red badge on the Index button: how many rewards are waiting
	if indexBadge then
		indexBadge.Visible = unclaimed > 0
		local n = indexBadge:FindFirstChild("Count")
		if n and n:IsA("TextLabel") then
			n.Text = if unclaimed > 99 then "99+" else tostring(unclaimed)
		end
	end
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

-- Card colours by rarity (user, 2026-11-20): Common grey, Uncommon green, Rare blue, Epic purple, Legendary gold,
-- Mythic pink (then Cosmic cyan, Secret dark, Eternal white). The reference's cards are coloured by their place in
-- the list; this repaints a card's fill, lattice and border gradients from its animal's rarity.
local CARD_COLORS = {
	Color3.fromRGB(170, 170, 170),
	Color3.fromRGB(40, 220, 0),
	Color3.fromRGB(0, 125, 255),
	Color3.fromRGB(165, 0, 250),
	Color3.fromRGB(255, 185, 0),
	Color3.fromRGB(255, 70, 190),
	Color3.fromRGB(0, 215, 225),
	Color3.fromRGB(55, 55, 70),
	Color3.fromRGB(235, 230, 215),
}
local function shade(c: Color3, k: number): Color3
	return if k > 0 then c:Lerp(Color3.new(1, 1, 1), k) else c:Lerp(Color3.new(0, 0, 0), -k)
end
local function paintCard(button: Instance, rarity: number)
	local c = CARD_COLORS[rarity] or CARD_COLORS[1]
	local bg = find(button, "Visual.Background")
	if not bg then
		return
	end
	for _, d in bg:GetDescendants() do
		if d:IsA("UIGradient") then
			local parent = d.Parent
			if parent and parent.Name == "Fill" then
				d.Color = ColorSequence.new(shade(c, 0.4), shade(c, -0.05))
			elseif parent and parent.Name == "Lattice" then
				d.Color = ColorSequence.new(shade(c, 0.25), shade(c, -0.45))
			elseif parent and parent:IsA("UIStroke") then
				d.Color = ColorSequence.new(Color3.new(1, 1, 1), shade(c, -0.3))
			end
		end
	end
end

-- Each biome's side card (user 2026-11-21, like Throw Food for Animals' Forest / Savanna cards): a card in the biome's
-- colour with a white border, its name on top, a little block island of the biome in the middle (Client/BiomeDiorama)
-- and how much of it you've discovered at the bottom, "(38%)".
biomePercent = {}
local function biomeCard(collection: Instance, biome: number)
	local art: Instance? = nil
	for _, c in collection:GetChildren() do
		if c:IsA("Frame") and string.match(c.Name, "Art$") then
			art = c
			break
		end
	end
	if not art or not art:IsA("Frame") then
		return
	end
	local look = BiomeDiorama.card(biome)
	for _, d in art:GetChildren() do
		if d:IsA("ImageLabel") then
			d.Visible = false
		elseif d.Name == "SAFD_Card" then
			d:Destroy()
		end
	end
	art.BackgroundTransparency = 0
	art.BackgroundColor3 = Color3.new(1, 1, 1) -- (the white border)
	local st = art:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = Color3.fromRGB(20, 15, 35)
		st.Thickness = 2
		local g = st:FindFirstChildOfClass("UIGradient")
		if g then
			g.Enabled = false
		end
	end
	local card = Instance.new("Frame")
	card.Name = "SAFD_Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(1, -8, 1, -8)
	card.BackgroundColor3 = look.bg
	card.ZIndex = art.ZIndex + 1
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.08, 0)
	c.Parent = card
	local inner = Instance.new("UIStroke")
	inner.Thickness = 3
	inner.Color = look.bg:Lerp(Color3.new(1, 1, 1), 0.35)
	inner.Parent = card
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(look.bg:Lerp(Color3.new(1, 1, 1), 0.12), look.bg:Lerp(Color3.new(0, 0, 0), 0.08))
	grad.Parent = card
	card.Parent = art
	local function words(text: string, y: number, h: number): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.fromScale(0.92, h)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Text = text
		l.ZIndex = card.ZIndex + 2
		local ts = Instance.new("UIStroke")
		ts.Thickness = 3
		ts.Color = Color3.fromRGB(20, 15, 35)
		ts.Parent = l
		l.Parent = card
		return l
	end
	words(look.name, 0.04, 0.13)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0, 0.17)
	holder.Size = UDim2.fromScale(1, 0.66)
	holder.ZIndex = card.ZIndex + 1
	holder.Parent = card
	BiomeDiorama.viewport(holder, biome)
	biomePercent[biome] = words("(0%)", 0.84, 0.13)
end

-- The biome-complete reward under the animals (user 2026-11-22: "update the UI in index so it matches the reward,
-- follow how Throw Food for Animals does it"): like its collection reward cards: the "n/8" bar on the left, and a
-- reward card beside it: the cash picture with the amount, and a button: Locked (grey) until all 8 are found, CLAIM
-- (gold) then, Done (green, a big tick over the cash) once claimed. The pack's weapon picture (a bat) is hidden.
local CASH_ICON = "rbxassetid://98729063828762" -- (the HUD's money icon)
local function rewardRow(collection: Instance, biome: number)
	local bar = collection:FindFirstChild("CollectionProgress")
	if not bar or not bar:IsA("GuiObject") then
		return
	end
	local bat = bar:FindFirstChild("CategoryIcon")
	if bat and bat:IsA("GuiObject") then
		bat.Visible = false
	end
	local old = collection:FindFirstChild("SAFD_Reward")
	if old then
		old:Destroy()
	end
	local x0, w0 = bar.Position.X.Scale, bar.Size.X.Scale
	bar.Size = UDim2.fromScale(w0 * 0.56, bar.Size.Y.Scale)
	local card = Instance.new("Frame")
	card.Name = "SAFD_Reward"
	card.AnchorPoint = bar.AnchorPoint
	card.Position = UDim2.fromScale(x0 + w0 * 0.59, bar.Position.Y.Scale - bar.Size.Y.Scale * 0.12)
	card.Size = UDim2.fromScale(w0 * 0.41, bar.Size.Y.Scale * 1.24)
	card.BackgroundColor3 = Color3.fromRGB(45, 40, 80)
	card.ZIndex = bar.ZIndex + 2
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0.18, 0)
	cc.Parent = card
	local cs = Instance.new("UIStroke")
	cs.Thickness = 2
	cs.Color = Color3.fromRGB(20, 15, 35)
	cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cs.Parent = card
	local function label(text: string, pos: UDim2, size: UDim2, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = pos
		l.Size = size
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.ZIndex = card.ZIndex + 2
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = Color3.fromRGB(20, 15, 35)
		st.Parent = l
		l.Parent = card
		return l
	end
	label("Biome Reward", UDim2.fromScale(0.04, 0.03), UDim2.fromScale(0.92, 0.27), Color3.new(1, 1, 1))
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = CASH_ICON
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Position = UDim2.fromScale(0.03, 0.3)
	icon.Size = UDim2.fromScale(0.2, 0.5)
	icon.ZIndex = card.ZIndex + 1
	icon.Parent = card
	local tick = label("✅", UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.18, 0.46), Color3.new(1, 1, 1))
	tick.Visible = false
	label(
		money(Config.biomeCompleteReward(biome)),
		UDim2.fromScale(0.02, 0.76),
		UDim2.fromScale(0.26, 0.22),
		Color3.fromRGB(140, 255, 110)
	)
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(0.96, 0.62)
	button.Size = UDim2.fromScale(0.66, 0.6)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.AutoButtonColor = true
	button.ZIndex = card.ZIndex + 2
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.25, 0)
	bc.Parent = button
	local bs = Instance.new("UIStroke")
	bs.Thickness = 2
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Parent = button
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2
	ts.Color = Color3.fromRGB(20, 15, 35)
	ts.Parent = button
	button.Parent = card
	local current = "Locked"
	button.Activated:Connect(function()
		if current == "Claim" then
			Net.event("ClaimBiomeReward"):FireServer(biome)
		end
	end)
	card.Parent = collection
	biomeClaim[biome] = {
		set = function(stateName: string)
			current = stateName
			tick.Visible = stateName == "Done"
			if stateName == "Done" then
				button.Text = "Done"
				button.BackgroundColor3 = Color3.fromRGB(70, 190, 50)
				bs.Color = Color3.fromRGB(30, 90, 15)
			elseif stateName == "Claim" then
				button.Text = "CLAIM!"
				button.BackgroundColor3 = Color3.fromRGB(255, 190, 30)
				bs.Color = Color3.fromRGB(130, 80, 0)
			else
				button.Text = "Locked"
				button.BackgroundColor3 = Color3.fromRGB(120, 120, 130)
				bs.Color = Color3.fromRGB(60, 60, 70)
			end
		end,
	}
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
	-- The reference game's Index (user, 2026-11-20): its worlds' pictures, matched to ours by look (it has none for
	-- Toxic Wasteland or Candyland: those get a picture of their own, biomeArt); the rest hidden.
	local ART = { "Forest", "Ice", "Desert", "Lava", "", "" }
	local byWorld: { [string]: Instance } = {}
	local collections = {}
	for _, c in scroll:GetChildren() do
		if c:IsA("Frame") and string.match(c.Name, "^Collection%d+$") then
			table.insert(collections, c)
		end
	end
	table.sort(collections, function(x, y)
		return x.Name < y.Name
	end)
	for _, c in collections do
		local world = c:GetAttribute("WorldName")
		if type(world) == "string" and not byWorld[world] then
			byWorld[world] = c
		end
	end
	local used = {}
	local slots = {}
	for b = 1, #Config.Biomes do
		local c = byWorld[ART[b] or ""]
		if not c or used[c] then
			for _, other in collections do
				if not used[other] then
					c = other
					break
				end
			end
		end
		if c then
			used[c] = true
			slots[b] = c
		end
	end
	for _, c in collections do
		if not used[c] then
			c.Visible = false
			c:SetAttribute("IndexCategory", nil)
		end
	end
	for b, collection in slots do
		local biome = Config.Biomes[b]
		do
			collection.LayoutOrder = b
			collection:SetAttribute("WorldName", biome.Name)
			biomeCard(collection, b)
			rewardRow(collection, b)
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
				-- (the reference's "?" picture for locked entries: ours show the animal's black silhouette instead)
				button:SetAttribute("GridIconImage", nil)
				button:SetAttribute("RarityColor", CARD_COLORS[info.Rarity] or Config.Rarities[info.Rarity].Color)
				button:SetAttribute("RarityTextColor", Config.Rarities[info.Rarity].Color)
				paintCard(button, info.Rarity)
				-- (only some of the reference's card templates have a dark "locked" overlay: the silhouette says it already)
				local lockedShade = find(button, "Visual.LockedShade")
				if lockedShade then
					lockedShade:Destroy()
				end
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
	-- CLAIM ALL in the header, left of the close button (user 2026-11-22, like Steal an Egg)
	local header = find(index, "Container.Header")
	if header and header:IsA("GuiObject") then
		local b = Instance.new("TextButton")
		b.Name = "SAFD_ClaimAll"
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.fromScale(0.905, 0.5)
		b.Size = UDim2.fromScale(0.22, 0.6)
		b.BackgroundColor3 = Color3.fromRGB(70, 205, 40)
		b.Font = Enum.Font.FredokaOne
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = "CLAIM ALL"
		b.Visible = false
		b.ZIndex = 20
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.3, 0)
		c.Parent = b
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.fromRGB(30, 90, 15)
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = b
		local ts = Instance.new("UIStroke")
		ts.Thickness = 2
		ts.Color = Color3.fromRGB(20, 60, 10)
		ts.Parent = b
		b.Parent = header
		b.Activated:Connect(function()
			Net.event("ClaimIndexAll"):FireServer()
		end)
		claimAllButton = b
	end
	-- the red badge on the HUD Index button
	local hudGui = gui("Hud")
	local indexButton = hudGui and hudGui:FindFirstChild("IndexButton", true)
	if indexButton and indexButton:IsA("GuiObject") then
		local badge = Instance.new("Frame")
		badge.Name = "SAFD_Badge"
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.97, 0.1)
		badge.Size = UDim2.fromScale(0.42, 0.42)
		badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
		badge.BackgroundColor3 = Color3.fromRGB(235, 40, 40)
		badge.ZIndex = 30
		badge.Visible = false
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = badge
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = Color3.new(1, 1, 1)
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = badge
		local t = Instance.new("TextLabel")
		t.Name = "Count"
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.8, 0.8)
		t.Position = UDim2.fromScale(0.1, 0.1)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.ZIndex = 31
		t.Parent = badge
		badge.Parent = indexButton
		indexBadge = badge
	end
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
local allItemsList: { { id: string, key: string } } = {}

local function refreshAllItems()
	if not allItems then
		return
	end
	local setItems = allItems:FindFirstChild("SetItems") :: BindableEvent?
	if not setItems then
		return
	end
	local counts, order = {}, {}
	for _, key in state.Inventory do
		if Config.parseKey(key) then
			if not counts[key] then
				table.insert(order, key)
			end
			counts[key] = (counts[key] or 0) + 1
		end
	end
	table.sort(order, function(a, b)
		return Config.keyIncome(a) > Config.keyIncome(b)
	end)
	allItemsList = {}
	local list = {}
	for _, key in order do
		local info = Config.parseKey(key)
		local name = info.Name
		table.insert(allItemsList, { id = info.Id, key = key })
		table.insert(list, {
			id = key,
			name = name,
			kg = "",
			label = `{name} x{counts[key]} ({money(info.Income)}/s)`,
			image = "",
			rarity = Config.Rarities[info.Rarity].Name,
		})
	end
	setItems:Fire("Pets", list)
	setItems:Fire("Eggs", {})
end

-- The 1-9 hotbar: the pack shows a tool's TextureId, or its name if it has none. Animal tools get a picture of the
-- animal (a 3D close-up, like the pickup card) with the count in the corner instead.
local slotShown: { [number]: string } = {}
local function tag(slot: Instance, name: string, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.ZIndex = z
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Parent = l
	l.Parent = slot
	return l
end
local function refreshHotbarIcons()
	local ai = allItems
	local hotbar = ai and find(ai, "Container.Hotbar")
	if not hotbar then
		return
	end
	local list = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, t in backpack:GetChildren() do
			if t:IsA("Tool") then
				table.insert(list, t)
			end
		end
	end
	local character = player.Character
	local eq = character and character:FindFirstChildOfClass("Tool")
	if eq then
		table.insert(list, eq)
	end
	table.sort(list, function(a, b)
		return (a:GetAttribute("HotbarOrder") or 0) < (b:GetAttribute("HotbarOrder") or 0)
	end)
	for i = 1, 9 do
		local slot = hotbar:FindFirstChild("Slot" .. i)
		if not slot then
			continue
		end
		local tool = list[i]
		local id = tool and tool:GetAttribute("AnimalId")
		local icon = slot:FindFirstChild("ToolIcon")
		local name = slot:FindFirstChild("ToolName")
		if id and icon and icon:IsA("ImageLabel") then
			icon.Visible = true
			icon.Image = ""
			if name and name:IsA("TextLabel") then
				name.Text = ""
			end
			if slotShown[i] ~= id or not icon:FindFirstChild("AnimalViewport") then
				slotShown[i] = id
				local old = icon:FindFirstChild("AnimalViewport")
				if old then
					old:Destroy()
				end
				AnimalIcon.viewport(icon, id, true)
			end
			local count = slot:FindFirstChild("SAFD_Count") :: TextLabel?
			if not count then
				local c = Instance.new("TextLabel")
				c.Name = "SAFD_Count"
				c.BackgroundTransparency = 1
				c.AnchorPoint = Vector2.new(1, 1)
				c.Position = UDim2.fromScale(0.97, 0.97)
				c.Size = UDim2.fromScale(0.34, 0.26)
				c.Font = Enum.Font.FredokaOne
				c.TextScaled = true
				c.TextXAlignment = Enum.TextXAlignment.Right
				c.TextColor3 = Color3.new(1, 1, 1)
				c.ZIndex = icon.ZIndex + 3
				local st = Instance.new("UIStroke")
				st.Thickness = 2
				st.Parent = c
				c.Parent = slot
				count = c
			end
			local n = tool:GetAttribute("Count") or 1
			(count :: TextLabel).Text = if n > 1 then "x" .. n else ""
			-- what it earns, in green at the top right, and its rarity in its colour along the bottom (user, 2026-11-20)
			local info = Config.Animals[id]
			local income = slot:FindFirstChild("SAFD_Income") :: TextLabel?
			if not income then
				income = tag(slot, "SAFD_Income", icon.ZIndex + 3)
				local l = income :: TextLabel
				l.AnchorPoint = Vector2.new(1, 0)
				l.Position = UDim2.fromScale(0.97, 0.04)
				l.Size = UDim2.fromScale(0.7, 0.26)
				l.TextXAlignment = Enum.TextXAlignment.Right
				l.TextColor3 = Color3.fromRGB(120, 255, 110)
			end
			local rarityLabel = slot:FindFirstChild("SAFD_Rarity") :: TextLabel?
			if not rarityLabel then
				rarityLabel = tag(slot, "SAFD_Rarity", icon.ZIndex + 3)
				local l = rarityLabel :: TextLabel
				l.AnchorPoint = Vector2.new(0, 1)
				l.Position = UDim2.fromScale(0.04, 0.97)
				l.Size = UDim2.fromScale(0.66, 0.24)
				l.TextXAlignment = Enum.TextXAlignment.Left
			end
			if info then
				local rarity = Config.Rarities[info.Rarity];
				(income :: TextLabel).Text = money(info.Income) .. "/s"
				(rarityLabel :: TextLabel).Text = rarity.Name;
				(rarityLabel :: TextLabel).TextColor3 = rarity.Color
			end
		else
			slotShown[i] = nil
			if icon then
				local old = icon:FindFirstChild("AnimalViewport")
				if old then
					old:Destroy()
				end
			end
			local count = slot:FindFirstChild("SAFD_Count")
			if count and count:IsA("TextLabel") then
				count.Text = ""
			end
			for _, n in { "SAFD_Income", "SAFD_Rarity", "SAFD_Mult" } do
				local l = slot:FindFirstChild(n)
				if l and l:IsA("TextLabel") then
					l.Text = ""
				end
			end
		end
	end
end

local function setupAllItems()
	allItems = gui("All items")
	if not allItems then
		return
	end
	-- (after the pack's own refresh, which runs on the same changes)
	local function later()
		task.delay(0.05, refreshHotbarIcons)
	end
	local function watch(container: Instance?)
		if container then
			container.ChildAdded:Connect(later)
			container.ChildRemoved:Connect(later)
		end
	end
	watch(player:FindFirstChildOfClass("Backpack"))
	player.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") then
			watch(c)
			later()
		end
	end)
	player.CharacterAdded:Connect(function(c)
		watch(c)
		later()
	end)
	watch(player.Character)
	task.spawn(function()
		while true do
			task.wait(1)
			refreshHotbarIcons() -- (counts change on the tools themselves)
		end
	end)
	later()
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
				if
					tool:IsA("Tool")
					and (tool:GetAttribute("AnimalKey") or tool:GetAttribute("AnimalId")) == item.id
				then
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
	local units = {}
	for _, key in state.Inventory do
		if Config.parseKey(key) then
			table.insert(units, key)
		end
	end
	table.sort(units, function(a, b)
		return Config.keyIncome(a) > Config.keyIncome(b)
	end)
	for i, card in cards do
		local key = if category == "Eggs" then nil else units[i]
		if key then
			local info = Config.parseKey(key)
			local value = Config.keyIncome(key) * Config.SellValueSeconds
			card:SetAttribute("ItemId", key)
			card:SetAttribute("Value", value)
			card:SetAttribute("Weight", info.Rarity)
			card:SetAttribute("Sold", false)
			card.Visible = true
			setText(card, "Visual.ValueLabel", money(value))
			setText(card, "Visual.WeightLabel", `({info.Name})`)
			setText(card, "Visual.RateLabel", money(info.Income) .. "/s")
			local pet = find(card, "Visual.Pet")
			if pet and pet:IsA("GuiObject") then
				viewport(pet, info.Id)
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
-- money buttons: SOLID green when you can buy it (or own it), SOLID red when you can't (user 2026-11-21: "no
-- stripes"): the pack's Gloss stripes and Checker pattern are hidden, the fill is one flat colour.
local GREEN = ColorSequence.new(Color3.fromRGB(70, 205, 40))
local RED = ColorSequence.new(Color3.fromRGB(225, 45, 45))
local function paintButton(button: Instance?, ok: boolean)
	local fill = button and find(button, "Visual.Background.Native.Fill")
	if not fill then
		return
	end
	local g = fill:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = if ok then GREEN else RED
	end
	local st = fill:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = if ok then Color3.fromRGB(40, 110, 20) else Color3.fromRGB(110, 15, 15)
	end
	-- (the pack's inner border is yellow-green and the price text has a dark green outline: on a red button both go red
	-- too, so it's a full red button; user 2026-11-22)
	local inner = button and find(button, "Visual.Background.Native.InnerStroke")
	local innerStroke = inner and inner:FindFirstChildOfClass("UIStroke")
	if innerStroke then
		innerStroke.Color = if ok then Color3.fromRGB(207, 255, 51) else Color3.fromRGB(255, 120, 120)
	end
	local price = button and find(button, "Visual.PriceContent.Price")
	local priceStroke = price and price:FindFirstChildOfClass("UIStroke")
	if priceStroke then
		priceStroke.Color = if ok then Color3.fromRGB(28, 50, 0) else Color3.fromRGB(90, 10, 10)
	end
	for _, name in { "Checker", "Gloss" } do
		local layer = fill:FindFirstChild(name)
		if layer and layer:IsA("GuiObject") then
			layer.Visible = false
		end
	end
end

-- "NOT ENOUGH MONEY!" right on the card you clicked (the toast used to show behind the shop)
local function cantAfford(card: Instance, need: number)
	local visual = card:FindFirstChild("Visual") or card
	if not visual:IsA("GuiObject") then
		return
	end
	local old = visual:FindFirstChild("SAFD_CantAfford")
	if old then
		old:Destroy()
	end
	local l = Instance.new("TextLabel")
	l.Name = "SAFD_CantAfford"
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.62)
	l.Size = UDim2.fromScale(0.95, 0.2)
	l.BackgroundColor3 = Color3.fromRGB(200, 25, 25)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = "NOT ENOUGH MONEY!\nNeed " .. money(need) .. " more"
	l.ZIndex = 50
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.2, 0)
	c.Parent = l
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = Color3.fromRGB(90, 0, 0)
	st.Parent = l
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = l
	local sc = Instance.new("UIScale")
	sc.Scale = 0.3
	sc.Parent = l
	l.Parent = visual
	local TweenService = game:GetService("TweenService")
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- a little shake
	task.spawn(function()
		for i = 1, 6 do
			l.Rotation = if i % 2 == 0 then 4 else -4
			task.wait(0.04)
		end
		l.Rotation = 0
	end)
	pcall(function()
		require(script.Parent.ChaseFx).play("Thud", 0.5, 0.7)
	end)
	task.delay(1.8, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(st, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			task.wait(0.32)
			l:Destroy()
		end
	end)
end

local function refreshTrails()
	if not trails then
		return
	end
	local scroll = find(trails, "Container.Content.TrailScroll")
	if not scroll then
		return
	end
	local cash = player:GetAttribute("Money") or 0
	for _, card in scroll:GetChildren() do
		local i = card:GetAttribute("TrailIndex")
		local info = i and Config.Trails[i]
		if i and not info then
			card.Visible = false
		elseif info then
			-- cheapest first (user 2026-11-21: "$150K came before $10K")
			if card:IsA("GuiObject") then
				card.LayoutOrder = math.floor(math.log10(info.Price + 1) * 1000) * 100 + i
			end
			setText(card, "Visual.Title", info.Name)
			setText(card, "Visual.Stats.TextGroup.Multiplier", "x" .. Util.formatNumber(info.Multiplier))
			-- its rarity and picture, as in "[NEW] Feed and Rob Animals" (Config.Trails)
			local visual = card:FindFirstChild("Visual") or card
			local rarity = visual:FindFirstChild("Rarity", true)
			if rarity and rarity:IsA("TextLabel") then
				rarity.Text = info.Rarity
				rarity.TextColor3 = Config.TrailRarityColors[info.Rarity] or rarity.TextColor3
			end
			local art = visual:FindFirstChild("TrailArt", true)
			if art and art:IsA("ImageLabel") and info.Art and info.Art > 0 then
				art.Image = "rbxassetid://" .. info.Art
			end
			local owned = state.Trails[tostring(i)] == true
			local label = if state.EquippedTrail == i then "Equipped" elseif owned then "Equip" else money(info.Price)
			local price = find(card, "Visual.Purchase.MoneyButton.Visual.PriceContent.Price")
			if price and price:IsA("TextLabel") then
				price.Text = label
				-- (the pack sizes its text once for "$500": keep "Equipped" as big as the rest)
				price.TextScaled = true
				-- the label fills the button (it used half its width: "Equipped" looked tiny, user 2026-11-21)
				price.Size = UDim2.fromScale(1, 1)
			end
			paintButton(find(card, "Visual.Purchase.MoneyButton"), owned or cash >= info.Price)
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
				-- already on: clicking "Equipped" again keeps it on (it used to take the trail off without a word)
				return
			elseif state.Trails[tostring(i)] then
				Net.event("EquipTrail"):FireServer(i)
			else
				local info = Config.Trails[i]
				local cash = player:GetAttribute("Money") or 0
				if info and cash < info.Price then
					local scroll = find(trails, "Container.Content.TrailScroll")
					for _, card in (scroll and scroll:GetChildren() or {}) do
						if card:GetAttribute("TrailIndex") == i then
							cantAfford(card, info.Price - cash)
						end
					end
					return
				end
				Net.event("BuyTrail"):FireServer(i)
			end
		end)
	end
	-- the buttons turn green the moment you can afford them
	local last = 0
	player:GetAttributeChangedSignal("Money"):Connect(function()
		if os.clock() - last > 0.5 then
			last = os.clock()
			refreshTrails()
		end
	end)
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
	-- (the red tent sells your animals; the yellow tent is the Trail Shop: user, 2026-11-20. The Speed Shop is still
	-- on the HUD and on the treadmill)
	{ Model = "Speed_stand", Gui = "Sell Pets", Attribute = "SellPetsOpen" },
	{ Model = "Weight_stand", Gui = "TrailsShop", Attribute = "TrailShopOpen" },
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
					-- (the free gift only pops up while you can still claim it: user 2026-11-22)
					if zone.Model == "Free_item_section" and state.FreeItemClaimed then
						now = false
					end
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
