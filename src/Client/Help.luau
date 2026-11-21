-- Help (user 2026-11-21: "the controls are too annoying ... a place where you can find help, a question mark button,
-- blue"): a blue "?" tile on the right of the screen, just above the Animals tile. It opens a small window beside it
-- with WATCH TUTORIAL AGAIN and the controls (keyboard or phone wording). Replaces the controls card that was always
-- on screen. The tutorial points at it near its end (Help.button / Help.isOpen / Help.close).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ChaseFx = require(script.Parent.ChaseFx)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Help = {}

-- set by Client/Tutorial (it requires this module, not the other way round)
Help.onReplay = nil :: (() -> ())?

local DARK = Color3.fromRGB(12, 12, 16)
local gui: ScreenGui
local tile: TextButton
local window: Frame

local function label(parent: Instance, props: { [string]: any }, stroke: number?): TextLabel
	local l = Ui.text(parent, props, nil)
	if stroke then
		Ui.stroke(l, stroke, DARK).LineJoinMode = Enum.LineJoinMode.Round
	end
	return l
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function setOpen(open: boolean)
	if open and Ui.busy() then
		return
	end
	window.Visible = open
	if open then
		window.Position = UDim2.new(0, tile.AbsolutePosition.X - tile.AbsoluteSize.X * 0.25, 0.5, 0)
		Ui.pop(window, 0.5)
		ChaseFx.play("Good", 0.35, 1.3)
	end
end

function Help.button(): GuiObject?
	return tile
end

function Help.isOpen(): boolean
	return window ~= nil and window.Visible
end

function Help.close()
	if window then
		window.Visible = false
	end
end

local function controlRow(parent: Instance, order: number, key: string, what: string)
	local r = Ui.frame(parent, { Size = UDim2.fromScale(1, 0.15), BackgroundTransparency = 1, LayoutOrder = order })
	local badge = Ui.frame(r, {
		Position = UDim2.fromScale(0, 0.08),
		Size = UDim2.fromScale(0.46, 0.84),
		BackgroundColor3 = Color3.fromRGB(245, 240, 255),
	})
	Ui.corner(badge, 0.25)
	Ui.stroke(badge, 2, DARK, true)
	label(badge, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.7),
		Text = key,
		TextColor3 = Color3.fromRGB(40, 30, 70),
	})
	label(r, {
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromScale(0.5, 0.76),
		Text = what,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 2)
end

function Help.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_Help"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.Parent = player:WaitForChild("PlayerGui")

	-- the blue "?" tile, above the Animals tile
	tile = Instance.new("TextButton")
	tile.Name = "HelpButton"
	tile.AutoButtonColor = false
	tile.Text = ""
	tile.AnchorPoint = Vector2.new(1, 0.5)
	tile.Position = UDim2.fromScale(0.985, 0.355)
	tile.Size = UDim2.fromScale(0.095, 0.095)
	tile.SizeConstraint = Enum.SizeConstraint.RelativeYY
	tile.BackgroundColor3 = Color3.new(1, 1, 1)
	Ui.corner(tile, 0.22)
	Ui.gradient(tile, Color3.fromRGB(80, 180, 255), Color3.fromRGB(25, 105, 230))
	Ui.stroke(tile, 3, DARK, true)
	label(tile, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(0.7, 0.7),
		Text = "?",
		ZIndex = 2,
	}, 3)
	label(tile, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(1.2, 0.38),
		Text = "Help",
		TextColor3 = Color3.fromRGB(170, 225, 255),
		ZIndex = 3,
	}, 3)
	tile.Parent = gui

	-- the window, beside the tile
	window = Ui.frame(gui, {
		Name = "Window",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.88, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = Color3.fromRGB(16, 16, 20),
		Visible = false,
	})
	local war = Instance.new("UIAspectRatioConstraint")
	war.AspectRatio = 0.85
	war.Parent = window
	Ui.corner(window, 0.07)
	Ui.stroke(window, 4, DARK, true)
	local band = Ui.frame(window, { Size = UDim2.fromScale(1, 0.13), BackgroundColor3 = Color3.new(1, 1, 1) })
	Ui.corner(band, 0.4)
	Ui.gradient(band, Color3.fromRGB(80, 180, 255), Color3.fromRGB(25, 105, 230))
	label(band, {
		Position = UDim2.fromScale(0.05, 0.12),
		Size = UDim2.fromScale(0.6, 0.76),
		Text = "Help",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 3)
	local x = Ui.button(band, "X", Ui.RED, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.15, 0.78),
	})
	local replay = Ui.button(window, "WATCH TUTORIAL AGAIN", Ui.GREEN, {
		Name = "Replay",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromScale(0.88, 0.13),
	})
	label(window, {
		Position = UDim2.fromScale(0.06, 0.34),
		Size = UDim2.fromScale(0.88, 0.08),
		Text = "CONTROLS",
		TextColor3 = Color3.fromRGB(255, 215, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 2)
	local rows = Ui.frame(window, {
		Position = UDim2.fromScale(0.06, 0.44),
		Size = UDim2.fromScale(0.88, 0.52),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.04, 0)
	layout.Parent = rows
	if isTouch() then
		controlRow(rows, 1, "Tap jump", "Jump")
		controlRow(rows, 2, "Tap jump twice", "Double jump")
		controlRow(rows, 3, "Hold SLIDE", "Slide")
		controlRow(rows, 4, "Hold the button", "Pick up an egg")
		controlRow(rows, 5, "🐾 Animals", "Open your animals") -- (the button itself, user 2026-11-22)
	else
		controlRow(rows, 1, "SPACE", "Jump")
		controlRow(rows, 2, "SPACE twice", "Double jump")
		controlRow(rows, 3, "Hold SHIFT", "Slide")
		controlRow(rows, 4, "Hold E", "Pick up an egg")
		controlRow(rows, 5, "🐾 Animals", "Open your animals")
	end

	tile.Activated:Connect(function()
		setOpen(not window.Visible)
	end)
	x.Activated:Connect(function()
		setOpen(false)
	end)
	replay.Activated:Connect(function()
		setOpen(false)
		if Help.onReplay then
			task.spawn(Help.onReplay)
		end
	end)
	-- hidden during runs and the hatch
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local busy = Ui.busy()
		tile.Visible = not busy
		if busy and window.Visible then
			window.Visible = false
		end
	end)
end

return Help
