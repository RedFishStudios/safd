-- The admin panel, like the reference game's ("[NEW] Feed and Rob Animals", AdminController): admins (the IsAdmin
-- attribute, Server/AdminService) get a crown button in the top bar beside the backpack; it opens a window with
--   * a command line: type a command (the slash is optional) and press Run or Enter
--   * every command: how to type it and what it does (click one and it's put on the command line)
--   * a "Give Animal" tab above the window: pick an animal and "/give <animal> 1 " is put on the command line
--   * an "Admins" tab (the owner only): make someone an admin by name, or take it away (/admin, /unadmin). Admins
--     are saved (Server/AdminService), and someone made admin gets the panel straight away.
-- The server checks and runs everything (Net.AdminAction) and answers with the usual toasts.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local player = Players.LocalPlayer

local AdminPanel = {}

local FACE = Font.new("rbxassetid://12187365364", Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
local GOLD = Color3.fromRGB(255, 205, 60)
local DARK = Color3.fromRGB(28, 30, 40)
local FIELD = Color3.fromRGB(16, 17, 24)
local SOFT = Color3.fromRGB(190, 196, 214)

type Command = { Alias: string, Usage: string, About: string }

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.new(0, 0, 0)
	s.ApplyStrokeMode = if parent:IsA("TextLabel") or parent:IsA("TextButton")
		then Enum.ApplyStrokeMode.Contextual
		else Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function escape(t: string): string
	return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function label(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.FontFace = FACE
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.Parent = parent
	return l
end

-- a chunky game button: a colour with a lighter top half, a dark outline and white outlined text
local function button(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.FontFace = FACE
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	corner(b, 0.3)
	local edge = stroke(b, 2.5, Color3.fromRGB(20, 20, 20))
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke(b, 2, Color3.fromRGB(20, 20, 20))
	local g = Instance.new("UIGradient")
	local h, s, v = color:ToHSV()
	local light = Color3.fromHSV(h, s * 0.8, math.min(1, v * 1.12))
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, light),
		ColorSequenceKeypoint.new(0.5, light),
		ColorSequenceKeypoint.new(0.501, color),
		ColorSequenceKeypoint.new(1, color),
	})
	g.Rotation = 90
	g.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.Parent = b
	b.Parent = parent
	return b
end

local function field(parent: Instance, name: string, placeholder: string, size: UDim2, pos: UDim2): TextBox
	local b = Instance.new("TextBox")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = FIELD
	b.FontFace = FACE
	b.TextColor3 = Color3.new(1, 1, 1)
	b.PlaceholderText = placeholder
	b.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
	b.ClearTextOnFocus = false
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Text = ""
	corner(b, 0.25)
	stroke(b, 1.5, Color3.fromRGB(70, 74, 92))
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = b
	b.Parent = parent
	return b
end

local function scroller(parent: Instance, name: string, size: UDim2, pos: UDim2): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = name
	s.Size = size
	s.Position = pos
	s.BackgroundColor3 = FIELD
	s.BackgroundTransparency = 0.35
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = GOLD
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	corner(s, 0.03)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = s
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = s
	s.Parent = parent
	return s
end

local function build(): ScreenGui
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "SAFD_Admin"
	screen.IgnoreGuiInset = true -- (positions in screen pixels: the crown sits in Roblox's top bar)
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 40
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	-- the crown, in the top bar just left of the HUD's backpack button, as big as it
	local toggle = Instance.new("TextButton")
	toggle.Name = "AdminButton"
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.BackgroundColor3 = Color3.new(0, 0, 0)
	toggle.BackgroundTransparency = 0.3
	toggle.Text = "👑"
	toggle.TextScaled = true
	toggle.Size = UDim2.fromOffset(44, 44)
	toggle:SetAttribute("PixelOK", true) -- (sized like the HUD button beside it, every frame)
	toggle.Position = UDim2.new(1, -230, 0, 28)
	corner(toggle, 1)
	toggle.Parent = screen
	task.spawn(function()
		local hud = playerGui:WaitForChild("Hud", 30)
		local anchor = hud and hud:FindFirstChild("BackpackButton", true)
		if not (anchor and anchor:IsA("GuiObject")) then
			return
		end
		local function place()
			-- (AbsolutePosition is measured from below the top bar, whatever the screen: add the inset back)
			local pos, size = anchor.AbsolutePosition + GuiService:GetGuiInset(), anchor.AbsoluteSize
			toggle.Size = UDim2.fromOffset(size.X, size.Y)
			toggle.Position = UDim2.fromOffset(pos.X - size.X * 1.2, pos.Y + size.Y / 2)
			toggle.Visible = anchor.Visible
		end
		anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
		anchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		anchor:GetPropertyChangedSignal("Visible"):Connect(place)
		place()
	end)

	-- the window
	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.55)
	window.Size = UDim2.fromScale(0.62, 0.76)
	window.BackgroundColor3 = DARK
	window.Visible = false
	window.Active = true
	corner(window, 0.03)
	stroke(window, 3, GOLD)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(1000, 760)
	limit.Parent = window
	window.Parent = screen

	-- the "Give Animal" tab, on top of the window's top edge
	local giveTab = button(
		window,
		"🎁 Give Animal",
		UDim2.fromScale(0.28, 0.075),
		UDim2.fromScale(0.03, -0.082),
		Color3.fromRGB(255, 200, 50)
	)
	giveTab.Name = "GiveAnimalTab"
	giveTab.ZIndex = 0
	giveTab.TextColor3 = Color3.fromRGB(40, 30, 10)
	for _, c in giveTab:GetChildren() do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			c:Destroy()
		end
	end

	-- the "Admins" tab beside it (shown to the owner only, once the server says so)
	local adminsTab = button(
		window,
		"👑 Admins",
		UDim2.fromScale(0.22, 0.075),
		UDim2.fromScale(0.33, -0.082),
		Color3.fromRGB(120, 200, 255)
	)
	adminsTab.Name = "AdminsTab"
	adminsTab.ZIndex = 0
	adminsTab.TextColor3 = Color3.fromRGB(10, 30, 50)
	adminsTab.Visible = false
	for _, c in adminsTab:GetChildren() do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			c:Destroy()
		end
	end

	local title =
		label(window, "Title", "👑 Admin Panel", UDim2.fromScale(0.7, 0.09), UDim2.fromScale(0.03, 0.025), GOLD)
	stroke(title, 2)
	local close =
		button(window, "X", UDim2.fromScale(0.07, 0.085), UDim2.fromScale(0.985, 0.025), Color3.fromRGB(225, 50, 50))
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.Parent = close

	-- the command line
	local commandBox = field(
		window,
		"CommandLine",
		"Type a command, like /give Chicken 3",
		UDim2.fromScale(0.76, 0.085),
		UDim2.fromScale(0.03, 0.135)
	)
	local runButton =
		button(window, "Run", UDim2.fromScale(0.18, 0.085), UDim2.fromScale(0.79, 0.135), Color3.fromRGB(60, 200, 60))
	runButton.Name = "Run"

	-- the list: the commands, or the animals (Give Animal)
	local listTitle = label(
		window,
		"ListTitle",
		"Commands (click one to use it)",
		UDim2.fromScale(0.8, 0.05),
		UDim2.fromScale(0.03, 0.24),
		SOFT
	)
	local commands = scroller(window, "Commands", UDim2.fromScale(0.94, 0.67), UDim2.fromScale(0.03, 0.3))
	local animals = scroller(window, "Animals", UDim2.fromScale(0.94, 0.67), UDim2.fromScale(0.03, 0.3))
	animals.Visible = false
	local grid = animals:FindFirstChildOfClass("UIListLayout")
	if grid then
		grid:Destroy()
	end
	local cells = Instance.new("UIGridLayout")
	cells.CellPadding = UDim2.fromOffset(6, 6)
	cells.CellSize = UDim2.new(0.32, -4, 0, 44)
	cells.SortOrder = Enum.SortOrder.LayoutOrder
	cells.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cells.Parent = animals

	local function put(text: string)
		commandBox.Text = text
		commandBox:CaptureFocus()
		commandBox.CursorPosition = #commandBox.Text + 1
	end

	local order = 0
	for _, biome in Config.Biomes do
		for _, id in biome.Animals do
			local info = Config.Animals[id]
			local rarity = Config.Rarities[info.Rarity]
			order += 1
			local cell = Instance.new("TextButton")
			cell.Name = id
			cell.LayoutOrder = order
			cell.BackgroundColor3 = if order % 2 == 0 then Color3.fromRGB(46, 49, 64) else Color3.fromRGB(39, 42, 56)
			cell.Text = ""
			corner(cell, 0.2)
			stroke(cell, 1.5, rarity.Color)
			local l = label(cell, "Name", info.Name, UDim2.fromScale(0.92, 0.55), UDim2.fromScale(0.05, 0.06))
			l.TextScaled = true
			local r = label(
				cell,
				"Rarity",
				rarity.Name,
				UDim2.fromScale(0.92, 0.32),
				UDim2.fromScale(0.05, 0.62),
				rarity.Color
			)
			r.TextScaled = true
			cell.Activated:Connect(function()
				put(`/give {id} 1 `)
			end)
			cell.Parent = animals
		end
	end

	-- the Admins page: a name box with "Make admin", then everyone the owner has made admin, each with "Remove"
	local admins = scroller(window, "Admins", UDim2.fromScale(0.94, 0.67), UDim2.fromScale(0.03, 0.3))
	admins.Visible = false
	local addRow = Instance.new("Frame")
	addRow.Name = "AddRow"
	addRow.LayoutOrder = 0
	addRow.BackgroundTransparency = 1
	addRow.Size = UDim2.new(1, -12, 0, 48)
	addRow.Parent = admins
	local nameBox = field(
		addRow,
		"NameBox",
		"Player name (in this server, or any username)",
		UDim2.fromScale(0.66, 0.9),
		UDim2.fromScale(0, 0.05)
	)
	local addButton = button(
		addRow,
		"Make admin",
		UDim2.fromScale(0.32, 0.9),
		UDim2.fromScale(0.68, 0.05),
		Color3.fromRGB(60, 200, 60)
	)
	addButton.Name = "MakeAdmin"
	local adminRows: { Frame } = {}

	local function showPage(page: string)
		animals.Visible = page == "Animals"
		admins.Visible = page == "Admins"
		commands.Visible = page == "Commands"
		listTitle.Text = if page == "Animals"
			then "Give Animal (click one, then Run: count and player are optional)"
			elseif page == "Admins" then "Admins (saved: they stay admins in every server)"
			else "Commands (click one to use it)"
	end
	giveTab.Activated:Connect(function()
		showPage(if animals.Visible then "Commands" else "Animals")
	end)
	adminsTab.Activated:Connect(function()
		showPage(if admins.Visible then "Commands" else "Admins")
	end)

	-- text sizes and row heights follow the window's size (TextScaled would wrap the longer lines)
	local rows: { TextButton } = {}
	local function fit()
		local h = window.AbsoluteSize.Y
		local rowH = math.max(40, math.floor(h * 0.085))
		title.TextSize = math.floor(h * 0.065)
		commandBox.TextSize = math.max(12, math.floor(h * 0.034))
		listTitle.TextSize = math.max(11, math.floor(h * 0.032))
		cells.CellSize = UDim2.new(0.32, -4, 0, math.floor(rowH * 0.9))
		for _, row in rows do
			row.Size = UDim2.new(1, -12, 0, rowH)
			for _, c in row:GetChildren() do
				if c:IsA("TextLabel") then
					c.TextSize = math.max(11, math.floor(rowH * (if c.Name == "Top" then 0.36 else 0.27)))
				end
			end
		end
	end
	window:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	-- phones: nearly the whole screen
	local function shape()
		local cam = Workspace.CurrentCamera
		local vs = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		window.Size = if math.min(vs.X, vs.Y) < 500 then UDim2.fromScale(0.95, 0.84) else UDim2.fromScale(0.62, 0.76)
	end
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(shape)
	end
	shape()

	local function ask(action: string, arg: string?): (boolean, any)
		local ok, a, b = pcall(function()
			return Net.func("AdminAction"):InvokeServer(action, arg)
		end)
		if not ok then
			return false, nil
		end
		return a == true, b
	end

	local loaded = false
	local load: () -> ()
	local function runLine(line: string): boolean
		local ok = ask("run", line)
		if ok and (string.find(line, "^/?admin") or string.find(line, "^/?unadmin")) then
			task.spawn(load)
		end
		return ok
	end
	local function fillAdmins(list: { { UserId: number, Name: string } })
		for _, r in adminRows do
			r:Destroy()
		end
		table.clear(adminRows)
		if #list == 0 then
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.LayoutOrder = 1
			row.Size = UDim2.new(1, -12, 0, 40)
			label(row, "None", "No admins yet besides you.", UDim2.fromScale(1, 1), UDim2.fromScale(0.02, 0), SOFT)
			row.Parent = admins
			table.insert(adminRows, row)
		end
		for i, a in list do
			local row = Instance.new("Frame")
			row.Name = a.Name
			row.LayoutOrder = i
			row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(46, 49, 64) else Color3.fromRGB(39, 42, 56)
			row.Size = UDim2.new(1, -12, 0, 46)
			corner(row, 0.15)
			local l = label(row, "Name", "👑 " .. a.Name, UDim2.fromScale(0.62, 0.8), UDim2.fromScale(0.03, 0.1))
			l.TextScaled = true
			local remove = button(
				row,
				"Remove",
				UDim2.fromScale(0.28, 0.78),
				UDim2.fromScale(0.7, 0.11),
				Color3.fromRGB(225, 60, 60)
			)
			remove.Activated:Connect(function()
				task.spawn(runLine, "/unadmin " .. a.Name)
			end)
			row.Parent = admins
			table.insert(adminRows, row)
		end
	end
	addButton.Activated:Connect(function()
		local name = nameBox.Text:gsub("%s", "")
		if name ~= "" then
			task.spawn(function()
				if runLine("/admin " .. name) then
					nameBox.Text = ""
				end
			end)
		end
	end)

	function load()
		local ok, info = ask("info")
		if not (ok and type(info) == "table") then
			return
		end
		loaded = true
		adminsTab.Visible = info.Owner == true
		if type(info.Admins) == "table" then
			fillAdmins(info.Admins)
		end
		for _, r in rows do
			r:Destroy()
		end
		table.clear(rows)
		for i, c: Command in info.Commands do
			local row = Instance.new("TextButton")
			row.Name = c.Alias
			row.LayoutOrder = i
			row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(46, 49, 64) else Color3.fromRGB(39, 42, 56)
			row.Text = ""
			corner(row, 0.15)
			local top = label(row, "Top", "", UDim2.fromScale(0.95, 0.5), UDim2.fromScale(0.03, 0.06))
			top.RichText = true
			top.Text = ('<b>%s</b>  <font color="#9fd0ff">%s</font>'):format(c.Alias, escape(c.Usage))
			label(row, "About", c.About, UDim2.fromScale(0.95, 0.4), UDim2.fromScale(0.03, 0.56), SOFT)
			row.Activated:Connect(function()
				put(c.Alias .. " ")
			end)
			row.Parent = commands
			table.insert(rows, row)
		end
		fit()
	end

	local function open(on: boolean)
		window.Visible = on
		if on and not loaded then
			task.spawn(load)
		end
	end
	toggle.Activated:Connect(function()
		open(not window.Visible)
	end)
	close.Activated:Connect(function()
		open(false)
	end)

	local function run()
		local line = commandBox.Text
		if line:gsub("%s", "") == "" then
			return
		end
		task.spawn(function()
			if runLine(line) then
				commandBox.Text = ""
			end
		end)
	end
	runButton.Activated:Connect(run)
	commandBox.FocusLost:Connect(function(enter: boolean)
		if enter then
			run()
		end
	end)
	fit()
	return screen
end

function AdminPanel.init()
	-- built when you're an admin (also when the owner makes you one while you play), gone if it's taken away
	local screen: ScreenGui? = nil
	local function check()
		local isAdmin = player:GetAttribute("IsAdmin") == true
		if isAdmin and not screen then
			screen = build()
		elseif not isAdmin and screen then
			screen:Destroy()
			screen = nil
		end
	end
	player:GetAttributeChangedSignal("IsAdmin"):Connect(check)
	check()
end

return AdminPanel
