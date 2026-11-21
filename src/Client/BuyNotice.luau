-- "NEW EQUIPMENT! YOU CAN NOW BUY ..." (user 2026-11-21: a copy of Throw Food for Animals' popup, at the top of the
-- screen): the moment you can afford the next trail, treadmill or base, a card drops in at the top: a blue striped
-- title band "NEW EQUIPMENT!" with a red X, the picture on a light blue tile, "YOU CAN NOW BUY", the name, the price
-- in green and what it gives in blue, a green UPGRADE button, and an orange bar along the bottom that runs down (it
-- closes itself after 9 s). Never during a run, the hatch or the intro, never over another window or the tutorial.
-- Each thing pops up once a session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local Util = require(Shared.Util)

local ChaseFx = require(script.Parent.ChaseFx)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local BuyNotice = {}

local state = { Trails = {}, BaseTier = 1, TreadmillLevel = 1, loaded = false }
local shown: { [string]: boolean } = {}
local current: Frame? = nil
local gui: ScreenGui

local DARK = Color3.fromRGB(12, 12, 16)

type Offer = { key: string, name: string, price: number, gives: string, buy: () -> (), picture: (Frame) -> () }

-- a little fence pen, for the base upgrade's picture
local function penModel(): Model
	local m = Instance.new("Model")
	local function part(size: Vector3, cf: CFrame, color: Color3)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Parent = m
	end
	part(Vector3.new(10, 0.6, 10), CFrame.new(0, -0.3, 0), Color3.fromRGB(110, 200, 60))
	for _, side in { -1, 1 } do
		for k = -2, 2 do
			part(Vector3.new(0.6, 2.2, 0.6), CFrame.new(side * 4.6, 1.1, k * 2.2), Color3.fromRGB(90, 65, 50))
			part(Vector3.new(0.6, 2.2, 0.6), CFrame.new(k * 2.2, 1.1, side * 4.6), Color3.fromRGB(90, 65, 50))
		end
		part(Vector3.new(0.3, 0.4, 9.6), CFrame.new(side * 4.6, 1.5, 0), Color3.fromRGB(165, 85, 10))
		part(Vector3.new(9.6, 0.4, 0.3), CFrame.new(0, 1.5, side * 4.6), Color3.fromRGB(165, 85, 10))
	end
	return m
end

-- what you could buy next, each kind's cheapest
local function offers(): { Offer }
	local list = {}
	-- the cheapest trail you don't have
	local best: any = nil
	for i, t in Config.Trails do
		if not state.Trails[tostring(i)] and (not best or t.Price < best.Price) then
			best = t
		end
	end
	if best then
		local i = table.find(Config.Trails, best) :: number
		table.insert(list, {
			key = "Trail" .. i,
			name = string.upper(best.Name),
			price = best.Price,
			gives = "x" .. Util.formatNumber(best.Multiplier) .. " Speed",
			buy = function()
				Net.event("BuyTrail"):FireServer(i)
			end,
			picture = function(slot: Frame)
				local img = Instance.new("ImageLabel")
				img.BackgroundTransparency = 1
				img.AnchorPoint = Vector2.new(0.5, 0.5)
				img.Position = UDim2.fromScale(0.5, 0.5)
				img.Size = UDim2.fromScale(0.9, 0.9)
				img.ScaleType = Enum.ScaleType.Fit
				img.Image = if best.Art and best.Art > 0 then "rbxassetid://" .. best.Art else ""
				img.ZIndex = slot.ZIndex + 2
				img.Parent = slot
			end,
		})
	end
	local tread = Progression.Treadmill[state.TreadmillLevel + 1]
	if tread then
		table.insert(list, {
			key = "Treadmill" .. (state.TreadmillLevel + 1),
			name = string.upper(tread.DisplayName .. " Treadmill"),
			price = tread.Price,
			gives = "+" .. Progression.short(tread.Gain) .. " Speed / step",
			buy = function()
				Net.event("BuyUpgrade"):FireServer("Treadmill")
			end,
			picture = function(slot: Frame)
				local assets = ReplicatedStorage:FindFirstChild("Assets")
				local tiers = assets and assets:FindFirstChild("TreadmillTiers")
				local m = tiers and tiers:FindFirstChild(tread.Model)
				if m and m:IsA("Model") then
					local vp = Ui.viewport(slot, m:Clone())
					vp.ZIndex = slot.ZIndex + 2
				end
			end,
		})
	end
	local base = Progression.Base[state.BaseTier + 1]
	if base then
		table.insert(list, {
			key = "Base" .. (state.BaseTier + 1),
			name = "BIGGER BASE",
			price = base.Price,
			gives = base.PetSlots .. " animal slots",
			buy = function()
				Net.event("BuyUpgrade"):FireServer("Base")
			end,
			picture = function(slot: Frame)
				local vp = Ui.viewport(slot, penModel(), Vector3.new(0.6, 0.8, -1))
				vp.ZIndex = slot.ZIndex + 2
			end,
		})
	end
	return list
end

local function close(card: Frame)
	if current == card then
		current = nil
	end
	TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.5, -0.3),
	}):Play()
	task.delay(0.27, function()
		card:Destroy()
	end)
end

local function label(parent: Instance, props: { [string]: any }, stroke: number?): TextLabel
	local l = Ui.text(parent, props, nil)
	if stroke then
		local st = Ui.stroke(l, stroke, DARK)
		st.LineJoinMode = Enum.LineJoinMode.Round
	end
	return l
end

local function show(o: Offer)
	-- the card: dark, rounded, a thick black edge; at the top of the screen
	local card = Ui.frame(gui, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, -0.3),
		Size = UDim2.fromScale(0.36, 0.25),
		BackgroundColor3 = Color3.fromRGB(16, 16, 20),
		ZIndex = 2,
	})
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 2.45
	ar.Parent = card
	Ui.corner(card, 0.09)
	Ui.stroke(card, 4, DARK, true)

	-- the blue title band with light diagonal stripes
	local band = Ui.frame(card, {
		Size = UDim2.fromScale(1, 0.25),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		ZIndex = 3,
	})
	Ui.corner(band, 0.35)
	Ui.gradient(band, Color3.fromRGB(70, 175, 255), Color3.fromRGB(35, 120, 235))
	for k = 0, 5 do
		local stripe = Ui.frame(band, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.45 + k * 0.1, 0.5),
			Size = UDim2.fromScale(0.035, 2.2),
			Rotation = 25,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.85,
			ZIndex = 3,
		})
		local _ = stripe
	end
	label(band, {
		Position = UDim2.fromScale(0.035, 0.12),
		Size = UDim2.fromScale(0.75, 0.78),
		Text = "NEW EQUIPMENT!",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	}, 3)
	-- the red X
	local x = Instance.new("TextButton")
	x.AutoButtonColor = false
	x.Text = ""
	x.AnchorPoint = Vector2.new(1, 0.5)
	x.Position = UDim2.fromScale(0.975, 0.5)
	x.Size = UDim2.fromScale(0.105, 0.82)
	x.BackgroundColor3 = Color3.new(1, 1, 1)
	x.ZIndex = 4
	Ui.corner(x, 0.22)
	Ui.gradient(x, Color3.fromRGB(240, 45, 45), Color3.fromRGB(190, 15, 20))
	Ui.stroke(x, 3, DARK, true)
	label(x, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.72),
		Text = "X",
		ZIndex = 5,
	}, 3)
	x.Parent = band

	-- the picture: a light blue tile with a pale circle behind the thing
	local pic = Ui.frame(card, {
		Position = UDim2.fromScale(0.035, 0.3),
		Size = UDim2.fromScale(0.27, 0.62),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
	})
	Ui.corner(pic, 0.13)
	Ui.gradient(pic, Color3.fromRGB(150, 215, 255), Color3.fromRGB(70, 165, 245), 135)
	Ui.stroke(pic, 3, DARK, true)
	local disc = Ui.frame(pic, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.85, 0.85),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		ZIndex = 3,
	})
	Ui.corner(disc, 1)
	local dar = Instance.new("UIAspectRatioConstraint")
	dar.Parent = disc
	pcall(o.picture, pic)

	-- the words
	label(card, {
		Position = UDim2.fromScale(0.34, 0.31),
		Size = UDim2.fromScale(0.62, 0.13),
		Text = "YOU CAN NOW BUY",
		TextColor3 = Color3.fromRGB(210, 205, 235),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, 2)
	local nameLabel = label(card, {
		Position = UDim2.fromScale(0.34, 0.44),
		Size = UDim2.fromScale(0.62, 0.21),
		Text = o.name,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, 3)
	Ui.gradient(nameLabel, Color3.new(1, 1, 1), Color3.fromRGB(170, 225, 255))
	label(card, {
		RichText = true,
		Position = UDim2.fromScale(0.34, 0.69),
		Size = UDim2.fromScale(0.33, 0.15),
		Text = `<font color="#8CF050">${Util.formatNumber(o.price)}</font>  <font color="#78C8FF">{o.gives}</font>`,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, 2)
	-- the green UPGRADE button
	local buy = Instance.new("TextButton")
	buy.AutoButtonColor = false
	buy.Text = ""
	buy.Name = "Upgrade"
	buy.AnchorPoint = Vector2.new(1, 0)
	buy.Position = UDim2.fromScale(0.965, 0.63)
	buy.Size = UDim2.fromScale(0.28, 0.25)
	buy.BackgroundColor3 = Color3.new(1, 1, 1)
	buy.ZIndex = 3
	Ui.corner(buy, 0.25)
	Ui.gradient(buy, Color3.fromRGB(120, 230, 40), Color3.fromRGB(60, 175, 20))
	Ui.stroke(buy, 3, DARK, true)
	local buyText = label(buy, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.7),
		Text = "UPGRADE",
		ZIndex = 4,
	}, 3)
	buy.Parent = card

	-- the time left: an orange bar along the bottom
	local barBack = Ui.frame(card, {
		Position = UDim2.fromScale(0.035, 0.945),
		Size = UDim2.fromScale(0.93, 0.025),
		BackgroundColor3 = Color3.fromRGB(40, 40, 46),
		ZIndex = 3,
	})
	Ui.corner(barBack, 1)
	local bar = Ui.frame(barBack, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 160, 20),
		ZIndex = 4,
	})
	Ui.corner(bar, 1)
	TweenService:Create(bar, TweenInfo.new(9, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	current = card
	TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.008),
	}):Play()
	ChaseFx.play("Good", 0.6, 1.15)
	x.Activated:Connect(function()
		close(card)
	end)
	buy.Activated:Connect(function()
		if (player:GetAttribute("Money") or 0) < o.price then
			Ui.recolor(buy, Ui.RED)
			buyText.Text = "NEED MORE $"
			return
		end
		o.buy()
		close(card)
	end)
	task.delay(9, function()
		if card.Parent then
			close(card)
		end
	end)
end

local function check()
	if not state.loaded or current or Ui.busy() or Ui.windowOpen() then
		return
	end
	local pg = player:FindFirstChild("PlayerGui")
	if pg and pg:FindFirstChild("SAFD_Tutorial") then
		return -- (the tutorial shows you these itself)
	end
	local cash = player:GetAttribute("Money") or 0
	for _, o in offers() do
		if not shown[o.key] and cash >= o.price then
			shown[o.key] = true
			show(o)
			return
		end
	end
end

function BuyNotice.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_BuyNotice"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.IgnoreGuiInset = true -- (right at the top of the screen, level with Roblox's own buttons: user 2026-11-21)
	gui.Parent = player:WaitForChild("PlayerGui")
	-- (the treadmill pictures are meshes: load them now, so the picture is there when the card pops up)
	task.spawn(function()
		local assets = ReplicatedStorage:WaitForChild("Assets", 30)
		local tiers = assets and assets:WaitForChild("TreadmillTiers", 30)
		if tiers then
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(tiers:GetChildren())
			end)
		end
	end)
	Net.event("StateChanged").OnClientEvent:Connect(function(s)
		if type(s) ~= "table" then
			return
		end
		state.Trails = s.Trails or state.Trails
		state.BaseTier = s.BaseTier or state.BaseTier
		state.TreadmillLevel = s.TreadmillLevel or state.TreadmillLevel
		state.loaded = true
	end)
	-- (things already affordable when you join pop up once too, a few seconds in)
	task.spawn(function()
		local ok, s = pcall(function()
			return Net.func("GetState"):InvokeServer()
		end)
		if ok and type(s) == "table" then
			state.Trails = s.Trails or {}
			state.BaseTier = s.BaseTier or 1
			state.TreadmillLevel = s.TreadmillLevel or 1
		end
		task.wait(6)
		state.loaded = true
		while true do
			check()
			task.wait(1)
		end
	end)
end

-- (tests / the tutorial can show one)
function BuyNotice.preview()
	local list = offers()
	if list[1] then
		show(list[1])
	end
end

return BuyNotice
