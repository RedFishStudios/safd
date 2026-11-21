-- My Animals (user 2026-11-21: a copy of Throw Food for Animals'): the "Animals" tile on the right of the screen,
-- half way down (dark rounded tile, orange paw, "Animals" under it), opens the list right beside it:
--   ON YOUR PLOT 3/5   each with PICK UP (back to the backpack) and SELL
--   BACKPACK 4         each with EQUIP (put it on your plot, at a free spot) and SELL
--   EQUIP BEST         fills your plot with your best earners (Net.AnimalAction "EquipBest", Server/AnimalService)
-- SELL asks "SURE?" first (a second tap), so nobody sells their legendary by accident. Hidden during runs.
-- Everything is sized from the screen (scale, no pixel sizes), so it looks the same on a phone as on a computer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local AnimalIcon = require(script.Parent.AnimalIcon)
local ChaseFx = require(script.Parent.ChaseFx)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local AnimalsPanel = {}

local DARK = Color3.fromRGB(12, 12, 16)

local state = { Inventory = {}, Placed = {}, Capacity = 3 }
local gui: ScreenGui
local window: Frame
local list: ScrollingFrame
local countLabel: TextLabel
local sideButton: TextButton
local dirty = true

local function income(id: string): number
	local info = Config.Animals[id]
	return if info then info.Income else 0
end

local function money(n: number): string
	return "$" .. Util.formatNumber(n)
end

local function rowHeight(): number
	return math.max(40, window.AbsoluteSize.Y * 0.165)
end

local function label(parent: Instance, props: { [string]: any }, stroke: number?): TextLabel
	local l = Ui.text(parent, props, nil)
	if stroke then
		Ui.stroke(l, stroke, DARK).LineJoinMode = Enum.LineJoinMode.Round
	end
	return l
end

local function header(order: number, text: string, extra: string, extraColor: Color3)
	local row = Ui.frame(list, {
		Size = UDim2.new(1, -8, 0, rowHeight() * 0.42),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	})
	label(row, {
		RichText = true,
		Size = UDim2.fromScale(0.96, 0.9),
		Position = UDim2.fromScale(0.03, 0.05),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = `{text}  <font color="#{extraColor:ToHex()}">{extra}</font>`,
	}, 2)
end

-- a chunky button like the reference's: a colour gradient, a black edge, white words with a black outline
local function button(parent: Instance, text: string, top: Color3, bottom: Color3, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(b :: any)[k] = v
	end
	Ui.corner(b, 0.28)
	Ui.gradient(b, top, bottom)
	Ui.stroke(b, 2.5, DARK, true)
	label(b, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.66),
		Text = text,
		ZIndex = b.ZIndex + 1,
	}, 2)
	b.Parent = parent
	return b
end

-- one animal row: picture, name / rarity / $/s, two buttons
local function row(
	order: number,
	id: string,
	count: number,
	first: string,
	firstTop: Color3,
	firstBottom: Color3,
	onFirst: () -> (),
	onSell: () -> (),
	framed: boolean
)
	local info = Config.Animals[id]
	if not info then
		return
	end
	local rarity = Config.Rarities[info.Rarity]
	local r = Ui.frame(list, {
		Size = UDim2.new(1, -8, 0, rowHeight()),
		BackgroundColor3 = Color3.fromRGB(26, 26, 32),
		LayoutOrder = order,
	})
	Ui.corner(r, 0.2)
	Ui.stroke(r, if framed then 3 else 2, if framed then Color3.new(1, 1, 1) else Color3.fromRGB(45, 45, 55), true)
	local pic = Ui.frame(r, {
		Position = UDim2.fromScale(0.03, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		BackgroundColor3 = Color3.new(1, 1, 1),
	})
	local par = Instance.new("UIAspectRatioConstraint")
	par.Parent = pic
	Ui.corner(pic, 0.18)
	Ui.gradient(pic, Color3.fromRGB(130, 235, 110), Color3.fromRGB(60, 175, 60))
	task.defer(function()
		if pic.Parent then
			AnimalIcon.viewport(pic, id, true)
		end
	end)
	local x0 = 0.31
	label(r, {
		Position = UDim2.fromScale(x0, 0.1),
		Size = UDim2.fromScale(0.38, 0.32),
		Text = info.Name .. (if count > 1 then " x" .. count else ""),
		TextColor3 = Color3.fromRGB(150, 255, 110),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 2)
	label(r, {
		Position = UDim2.fromScale(x0, 0.42),
		Size = UDim2.fromScale(0.38, 0.2),
		Text = string.upper(rarity.Name),
		TextColor3 = rarity.Color,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 2)
	label(r, {
		Position = UDim2.fromScale(x0, 0.63),
		Size = UDim2.fromScale(0.38, 0.27),
		Text = money(info.Income) .. "/s",
		TextColor3 = Color3.fromRGB(150, 255, 110),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 2)
	local a = button(r, first, firstTop, firstBottom, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.08),
		Size = UDim2.fromScale(0.28, 0.4),
	})
	local sell = button(r, "SELL", Color3.fromRGB(240, 50, 50), Color3.fromRGB(190, 20, 25), {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.97, 0.92),
		Size = UDim2.fromScale(0.28, 0.4),
	})
	a.Activated:Connect(function()
		ChaseFx.play("Good", 0.4, 1.2)
		onFirst()
	end)
	local armed = false
	sell.Activated:Connect(function()
		local l = sell:FindFirstChild("Label") :: TextLabel
		if not armed then
			armed = true
			l.Text = "SURE? " .. money(income(id) * Config.SellValueSeconds)
			task.delay(2.5, function()
				armed = false
				if l.Parent then
					l.Text = "SELL"
				end
			end)
			return
		end
		armed = false
		onSell()
	end)
end

local function rebuild()
	dirty = false
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local placed = table.clone(state.Placed)
	table.sort(placed, function(x, y)
		return income(x.Id) > income(y.Id)
	end)
	local cap = state.Capacity
	countLabel.Text = `{#placed}/{cap}`
	header(1, "ON YOUR PLOT", `{#placed}/{cap}`, Color3.fromRGB(140, 255, 90))
	local order = 2
	for _, e in placed do
		row(order, e.Id, 1, "PICK UP", Color3.fromRGB(70, 175, 255), Color3.fromRGB(30, 110, 235), function()
			Net.event("AnimalAction"):FireServer("PickUp", e.Uid)
		end, function()
			Net.event("AnimalAction"):FireServer("SellPlaced", e.Uid)
		end, true)
		order += 1
	end
	-- the backpack, grouped by animal
	local counts, ids = {}, {}
	for _, key in state.Inventory do
		local info = Config.parseKey(key)
		if info then
			if not counts[info.Id] then
				table.insert(ids, info.Id)
			end
			counts[info.Id] = (counts[info.Id] or 0) + 1
		end
	end
	table.sort(ids, function(x, y)
		return income(x) > income(y)
	end)
	header(500, "BACKPACK", tostring(#state.Inventory), Color3.fromRGB(255, 215, 60))
	order = 501
	for _, id in ids do
		row(order, id, counts[id], "EQUIP", Color3.fromRGB(120, 230, 40), Color3.fromRGB(60, 175, 20), function()
			Net.event("AnimalAction"):FireServer("Place", id)
		end, function()
			Net.event("AnimalAction"):FireServer("Sell", id)
		end, false)
		order += 1
	end
end

-- the window sits right beside (to the left of) the Animals tile
local function placeWindow()
	local left = sideButton.AbsolutePosition.X
	local gap = sideButton.AbsoluteSize.X * 0.25
	window.Position = UDim2.new(0, left - gap, 0.5, 0)
end

local function setOpen(open: boolean)
	if open and Ui.busy() then
		return
	end
	window.Visible = open
	if open then
		placeWindow()
		Ui.pop(window, 0.5)
		ChaseFx.play("Good", 0.35, 1.3)
		if dirty then
			rebuild()
		end
	end
end

function AnimalsPanel.open()
	setOpen(true)
end

function AnimalsPanel.close()
	if window then
		window.Visible = false
	end
end

function AnimalsPanel.isOpen(): boolean
	return window ~= nil and window.Visible
end

-- the side button (for the tutorial to point at)
function AnimalsPanel.button(): GuiObject?
	return sideButton
end

function AnimalsPanel.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_Animals"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.Parent = player:WaitForChild("PlayerGui")

	-- the Animals tile: right side, half way down
	sideButton = Instance.new("TextButton")
	sideButton.Name = "AnimalsButton"
	sideButton.AutoButtonColor = false
	sideButton.Text = ""
	sideButton.AnchorPoint = Vector2.new(1, 0.5)
	sideButton.Position = UDim2.fromScale(0.985, 0.5)
	sideButton.Size = UDim2.fromScale(0.095, 0.095)
	sideButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
	sideButton.BackgroundColor3 = Color3.fromRGB(38, 42, 42)
	sideButton.BackgroundTransparency = 0.1
	Ui.corner(sideButton, 0.22)
	Ui.stroke(sideButton, 3, DARK, true)
	-- the light inner rim
	local rim = Ui.frame(sideButton, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		BackgroundTransparency = 1,
	})
	Ui.corner(rim, 0.18)
	local rimStroke = Ui.stroke(rim, 2, Color3.fromRGB(150, 155, 155))
	rimStroke.Transparency = 0.3
	local pawHolder = Ui.frame(sideButton, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(0.66, 0.66),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	task.defer(Ui.paw, pawHolder, 3)
	label(sideButton, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(1.3, 0.38),
		Text = "Animals",
		TextColor3 = Color3.fromRGB(255, 205, 150),
		ZIndex = 4,
	}, 3)
	sideButton.Parent = gui

	-- the window
	window = Ui.frame(gui, {
		Name = "Window",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.88, 0.5),
		Size = UDim2.fromScale(0.5, 0.82),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = Color3.fromRGB(16, 16, 20),
		Visible = false,
	})
	local war = Instance.new("UIAspectRatioConstraint")
	war.AspectRatio = 0.64
	war.Parent = window
	Ui.corner(window, 0.06)
	Ui.stroke(window, 4, DARK, true)
	local band = Ui.frame(window, { Size = UDim2.fromScale(1, 0.1), BackgroundColor3 = Color3.new(1, 1, 1) })
	Ui.corner(band, 0.4)
	Ui.gradient(band, Color3.fromRGB(255, 80, 230), Color3.fromRGB(190, 40, 220))
	label(band, {
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.5, 0.8),
		Text = "My Animals",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 3)
	-- the green count pill with a paw
	local pill = Ui.frame(band, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.83, 0.5),
		Size = UDim2.fromScale(0.27, 0.74),
		BackgroundColor3 = Color3.new(1, 1, 1),
	})
	Ui.corner(pill, 0.4)
	Ui.gradient(pill, Color3.fromRGB(120, 230, 40), Color3.fromRGB(60, 175, 20))
	Ui.stroke(pill, 3, DARK, true)
	local pillPaw = Ui.frame(pill, {
		Position = UDim2.fromScale(0.06, 0.12),
		Size = UDim2.fromScale(0.76, 0.76),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	task.defer(Ui.paw, pillPaw, 3)
	countLabel = label(pill, {
		Position = UDim2.fromScale(0.36, 0.1),
		Size = UDim2.fromScale(0.58, 0.8),
		Text = "0/3",
	}, 2)
	local x = button(band, "X", Color3.fromRGB(240, 50, 50), Color3.fromRGB(190, 20, 25), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.975, 0.5),
		Size = UDim2.fromScale(0.12, 0.78),
	})
	list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromScale(0.04, 0.12)
	list.Size = UDim2.fromScale(0.94, 0.72)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.Parent = list
	-- the scroll area is exactly as tall as the list (AutomaticCanvasSize stopped half way down: user 2026-11-21)
	local function fit()
		list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 16)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()
	list.Parent = window
	local best = button(window, "EQUIP BEST", Color3.fromRGB(255, 200, 60), Color3.fromRGB(250, 140, 20), {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.86, 0.1),
	})
	best.Activated:Connect(function()
		ChaseFx.play("Good", 0.5, 1)
		Net.event("AnimalAction"):FireServer("EquipBest")
	end)

	sideButton.Activated:Connect(function()
		setOpen(not window.Visible)
	end)
	x.Activated:Connect(function()
		setOpen(false)
	end)
	-- (a phone turned round, a resized window: rows and the window's place follow the screen)
	window:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		dirty = true
		if window.Visible then
			placeWindow()
			rebuild()
		end
	end)

	local function apply(s)
		if type(s) ~= "table" then
			return
		end
		state.Inventory = s.Inventory or state.Inventory
		state.Placed = s.Placed or state.Placed
		state.Capacity = s.Capacity or state.Capacity
		dirty = true
		if window.Visible then
			rebuild()
		end
	end
	Net.event("StateChanged").OnClientEvent:Connect(apply)
	task.spawn(function()
		local ok, s = pcall(function()
			return Net.func("GetState"):InvokeServer()
		end)
		if ok then
			apply(s)
		end
	end)
	-- hidden during runs and the hatch (checked a few times a second, not every frame)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local busy = Ui.busy()
		sideButton.Visible = not busy
		if busy and window.Visible then
			window.Visible = false
		end
	end)
end

return AnimalsPanel
