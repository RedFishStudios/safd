-- The two leaderboards at spawn (user 2026-11-21): the one
-- by the Sell tent shows TOP SPEED, the one by the Trail Shop MOST TIME PLAYED (data.TimePlayed, seconds, counted here).
-- Both read an OrderedDataStore (top 10). Built so it never breaks the game and never shows a broken board:
--   * every DataStore call is pcall-wrapped, retried with backoff, and only made when the request budget allows it
--   * writes only when a value changed, at most every WRITE_EVERY s per player, plus on leaving / shutdown
--   * the last good top-10 is kept; if the store can't be read (Studio without API access, an outage), the board
--     shows that, merged with everyone in this server right now (live values always win), so it's always filled in
--   * names are looked up once and cached (UserId -> name), with the UserId as a last resort
-- The boards (2026-11-22) are the Feed and Rob Animals ones, saved in the place as Spawn_elements.Leaderboard_Speed /
-- Leaderboard_Time (attribute Stat); this sets their "Rows" attribute and Client/Leaderboards draws them. Players get
-- the attribute TimePlayed for their own "YOUR POSITION" row.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local ROWS = 10
local READ_EVERY = 60
local WRITE_EVERY = 120

type Board = {
	key: string, -- "Speed" | "Time"
	store: OrderedDataStore?,
	top: { { userId: number, value: number } }, -- the last good read
	model: Model,
}

local boards: { Board } = {}
local live: { [number]: { Speed: number, Time: number } } = {} -- this server's players, every second
local written: { [number]: { Speed: number, Time: number, at: number } } = {}
local names: { [number]: string } = {}

-- a DataStore call that never throws: retried with backoff while the budget allows, nil if it never worked
local function safe(budget: Enum.DataStoreRequestType, fn: () -> any): (boolean, any)
	for attempt = 1, 4 do
		local ok0, left = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(budget)
		end)
		if ok0 and left and left > 0 then
			local ok, result = pcall(fn)
			if ok then
				return true, result
			end
		end
		task.wait(2 ^ attempt)
	end
	return false, nil
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.Name
		return p.Name
	end
	if userId <= 0 then
		return "Player"
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		names[userId] = name
		return name
	end
	return "Player " .. userId
end

-- the top-10 to show: the stored list, with everyone in this server put in at their live value
local function merged(b: Board): { { userId: number, value: number } }
	local byId: { [number]: number } = {}
	for _, e in b.top do
		byId[e.userId] = e.value
	end
	for userId, v in live do
		local value = v[b.key]
		if value and value > 0 then
			byId[userId] = math.max(byId[userId] or 0, value)
		end
	end
	local list = {}
	for userId, value in byId do
		table.insert(list, { userId = userId, value = value })
	end
	table.sort(list, function(x, y)
		return x.value > y.value
	end)
	while #list > ROWS do
		table.remove(list)
	end
	return list
end

-- the top 10 goes on the board model as JSON (attribute "Rows": [{u, n, v}]); Client/Leaderboards draws it in the
-- board's own UI (the Feed and Rob Animals boards, user 2026-11-22)
local function render(b: Board)
	local rows = {}
	for _, e in merged(b) do
		table.insert(rows, { u = e.userId, n = nameOf(e.userId), v = e.value })
	end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(rows)
	end)
	if ok and b.model.Parent then
		b.model:SetAttribute("Rows", json)
	end
end

local function read(b: Board)
	local store = b.store
	if not store then
		return
	end
	local ok, pages = safe(Enum.DataStoreRequestType.GetSortedAsync, function()
		return (store :: OrderedDataStore):GetSortedAsync(false, ROWS)
	end)
	if not ok or not pages then
		return -- (keep showing the last good list)
	end
	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage or type(page) ~= "table" then
		return
	end
	local top = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId and type(entry.value) == "number" then
			table.insert(top, { userId = userId, value = entry.value })
		end
	end
	b.top = top
end

local function write(userId: number, force: boolean?)
	local v = live[userId]
	if not v then
		return
	end
	local w = written[userId] or { Speed = -1, Time = -1, at = 0 }
	written[userId] = w
	if not force and os.clock() - w.at < WRITE_EVERY then
		return
	end
	w.at = os.clock()
	for _, b in boards do
		local value = math.floor(v[b.key] or 0)
		local store = b.store
		if store and value > 0 and value ~= w[b.key] then
			local ok = safe(Enum.DataStoreRequestType.SetIncrementSortedAsync, function()
				return (store :: OrderedDataStore):SetAsync(tostring(userId), value)
			end)
			if ok then
				w[b.key] = value
			end
		end
	end
end

local function renderAll()
	for _, b in boards do
		render(b)
	end
end

function LeaderboardService.init()
	local elements = Workspace:WaitForChild("Spawn_elements", 30)
	if not elements then
		return
	end
	-- the Feed and Rob Animals boards (saved in the place, user 2026-11-22): by the Sell tent TOP SPEED, by the Trail
	-- Shop the playtime board
	local models = {
		elements:FindFirstChild("Leaderboard_Speed"),
		elements:FindFirstChild("Leaderboard_Time"),
	}
	local function store(name: string): OrderedDataStore?
		local ok, s = pcall(function()
			return DataStoreService:GetOrderedDataStore(name)
		end)
		return if ok then s else nil
	end
	local defs = {
		{ key = "Speed", store = store("SAFD_LB_Speed_v1") },
		{ key = "Time", store = store("SAFD_LB_Time_v1") },
	}
	for i, def in defs do
		local model = models[i]
		if model and model:IsA("Model") then
			local b: Board = {
				key = def.key,
				store = def.store,
				top = {},
				model = model,
			}
			table.insert(boards, b)
		end
	end

	-- this server's players: time played counts up every second; values read straight from their data
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in Players:GetPlayers() do
				local data = DataService.get(p)
				if data and p:GetAttribute("Loaded") then
					data.TimePlayed = (tonumber(data.TimePlayed) or 0) + 1
					live[p.UserId] = { Speed = tonumber(data.Speed) or 0, Time = data.TimePlayed }
					p:SetAttribute("TimePlayed", data.TimePlayed)
				end
			end
		end
	end)
	-- writes (staggered) and reads
	task.spawn(function()
		while true do
			for _, p in Players:GetPlayers() do
				task.spawn(write, p.UserId)
				task.wait(0.5)
			end
			task.wait(10)
		end
	end)
	task.spawn(function()
		while true do
			for _, b in boards do
				read(b)
			end
			pcall(renderAll)
			task.wait(READ_EVERY)
		end
	end)
	-- live values show up between reads too (every 10 s)
	task.spawn(function()
		while true do
			task.wait(10)
			pcall(renderAll)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		task.spawn(function()
			write(p.UserId, true)
			live[p.UserId] = nil
			written[p.UserId] = nil
		end)
	end)
	game:BindToClose(function()
		local pending = 0
		for userId in live do
			pending += 1
			task.spawn(function()
				write(userId, true)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 20 do
			task.wait(0.1)
		end
	end)
end

return LeaderboardService
