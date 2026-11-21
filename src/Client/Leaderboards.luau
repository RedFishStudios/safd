-- Draws the TOP SPEED / playtime boards at spawn (user 2026-11-22: "the same leaderboard UI as Feed and Rob Animals"):
-- the boards are the reference game's own models (Spawn_elements.Leaderboard_Speed / Leaderboard_Time, attribute
-- Stat). The top 10 come from the board's "Rows" attribute (Server/LeaderboardService: JSON [{u, n, v}]); the
-- "YOUR POSITION" row shows your own live value. A copy of the reference game's LeaderboardController.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local Leaderboards = {}

local player = Players.LocalPlayer
local TOP = 10
local ATTRIBUTE = { Speed = "Speed", Playtime = "TimePlayed" }
local MEDALS = { Color3.fromRGB(255, 214, 60), Color3.fromRGB(220, 232, 245), Color3.fromRGB(235, 150, 85) }
local SPEED_ICON = "rbxassetid://140333781098529" -- (the HUD's speed icon)
local CLOCK = "⏰" -- (the playtime board is a copy of the speed board: its icons become clocks)

type Entry = { u: number, n: string, v: number }

local function playtime(seconds: number): string
	local s = math.floor(seconds)
	local d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
	if d > 0 then
		return ("%dd %dh"):format(d, h)
	elseif h > 0 then
		return ("%dh %dm"):format(h, m)
	elseif m > 0 then
		return ("%dm"):format(m)
	end
	return ("%ds"):format(s)
end

local function format(stat: string, v: number): string
	if stat == "Speed" then
		return Util.formatNumber(v)
	end
	return playtime(v)
end

local function clockIcon(image: ImageLabel)
	image.ImageTransparency = 1
	local t = Instance.new("TextLabel")
	t.Name = "Emoji"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = CLOCK
	t.TextScaled = true
	t.Parent = image
end

local function text(row: Instance, name: string): TextLabel?
	local l = row:FindFirstChild(name)
	return if l and l:IsA("TextLabel") then l else nil
end

local function fill(row: Frame, rank: string, medal: Color3?, userId: number, name: string, value: string)
	local r, n, v = text(row, "Rank"), text(row, "PlayerName"), text(row, "Value")
	if r then
		r.Text = rank
		r.TextColor3 = medal or Color3.new(1, 1, 1)
	end
	if n then
		n.Text = name
	end
	if v then
		v.Text = value
	end
	local avatar = row:FindFirstChild("Avatar")
	if avatar and avatar:IsA("ImageLabel") then
		avatar.Image = if userId > 0 then ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId) else ""
	end
end

local function setup(board: Instance)
	local stat = board:GetAttribute("Stat")
	if typeof(stat) ~= "string" or not ATTRIBUTE[stat] then
		return
	end
	local display = board:WaitForChild("DisplayPart", 30)
	local gui = display and display:FindFirstChildWhichIsA("SurfaceGui")
	local scroller = gui and gui:FindFirstChild("ScrollingFrame")
	local you = gui and gui:FindFirstChild("YourRank")
	local youRow = you and you:FindFirstChild("Row")
	if not (gui and scroller and scroller:IsA("GuiObject") and youRow and youRow:IsA("Frame")) then
		return
	end
	-- (the speed board shows our own speed icon, the HUD's, instead of the reference game's shoes: user 2026-11-22)
	if stat == "Speed" then
		for _, d in board:GetDescendants() do
			if
				d:IsA("ImageLabel")
				and d.Name ~= "Studs"
				and d.Name ~= "Avatar"
				and d.Parent
				and d.Parent.Name ~= "Bg"
			then
				d.Image = SPEED_ICON
				d.ImageColor3 = Color3.new(1, 1, 1)
				d.ScaleType = Enum.ScaleType.Fit
			end
		end
	end
	if stat == "Playtime" then
		for _, d in board:GetDescendants() do
			if d:IsA("ImageLabel") and d.Name ~= "Studs" and d.Name ~= "Avatar" and not d:FindFirstChild("Emoji") then
				clockIcon(d)
			end
		end
	end

	-- the top 10: copies of the "your position" row, in a plain frame where the template's list was
	scroller.Visible = false
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Size = scroller.Size
	list.Position = scroller.Position
	list.AnchorPoint = scroller.AnchorPoint
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0.008, 0)
	layout.Parent = list
	local rows: { Frame } = {}
	for i = 1, TOP do
		local r = youRow:Clone()
		r.Name = "Row" .. i
		r.LayoutOrder = i
		r.AnchorPoint = Vector2.zero
		r.Position = UDim2.new()
		r.Size = UDim2.new(0.95, 0, 1 / TOP, -4)
		r.Visible = false
		r.Parent = list
		rows[i] = r
	end
	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Size = UDim2.fromScale(0.9, 0.1)
	empty.LayoutOrder = 0
	empty.Text = "Loading..."
	empty.TextColor3 = Color3.new(1, 1, 1)
	empty.TextScaled = true
	empty.Font = Enum.Font.FredokaOne
	empty.Parent = list

	local myRank: number? = nil
	local function renderYou()
		fill(
			youRow :: Frame,
			if myRank then "#" .. myRank else TOP .. "+",
			if myRank then MEDALS[myRank] else nil,
			player.UserId,
			player.DisplayName,
			format(stat, tonumber(player:GetAttribute(ATTRIBUTE[stat])) or 0)
		)
	end
	local function render()
		local raw = board:GetAttribute("Rows")
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(if typeof(raw) == "string" then raw else "[]")
		end)
		local entries: { Entry } = if ok and type(decoded) == "table" then decoded else {}
		myRank = nil
		for i = 1, TOP do
			local e = entries[i]
			rows[i].Visible = e ~= nil
			if e then
				fill(rows[i], "#" .. i, MEDALS[i], tonumber(e.u) or 0, tostring(e.n), format(stat, tonumber(e.v) or 0))
				if e.u == player.UserId then
					myRank = i
				end
			end
		end
		empty.Visible = #entries == 0
		renderYou()
	end
	board:GetAttributeChangedSignal("Rows"):Connect(render)
	player:GetAttributeChangedSignal(ATTRIBUTE[stat]):Connect(renderYou)
	render()
end

function Leaderboards.init()
	task.spawn(function()
		local elements = Workspace:WaitForChild("Spawn_elements", 60)
		if not elements then
			return
		end
		for _, name in { "Leaderboard_Speed", "Leaderboard_Time" } do
			local b = elements:WaitForChild(name, 30)
			if b then
				task.spawn(setup, b)
			end
		end
	end)
end

return Leaderboards
