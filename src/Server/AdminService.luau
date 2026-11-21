-- Owner / admin commands for the in-game admin panel (Client/AdminPanel). Every command is checked here;
-- the client panel is only a convenience.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local MapInfo = require(Shared.MapInfo)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local AnimalService = require(script.Parent.AnimalService)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)

local AdminService = {}

local Notify = Net.event("Notify")

-- The owner: Config.Admins and the experience's creator. Only the owner can make (or unmake) other admins.
local function isOwner(userId: number): boolean
	if table.find(Config.Admins, userId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId == userId
	end
	return false
end

-- Admins the owner made in game (/admin <name>): saved in their own DataStore, so they're admins in every server and
-- after rejoining. { [userId as string] = name }
local ADMIN_STORE, ADMIN_KEY = "SAFD_Admins_v1", "granted"
local granted: { [string]: string } = {}
local adminStore: DataStore? = nil

local function isAdmin(player: Player): boolean
	return isOwner(player.UserId) or granted[tostring(player.UserId)] ~= nil
end

local function refreshAdminFlags()
	for _, p in Players:GetPlayers() do
		p:SetAttribute("IsAdmin", isAdmin(p))
		p:SetAttribute("IsOwner", isOwner(p.UserId))
	end
end

local function loadGranted()
	if not adminStore then
		return
	end
	local ok, result = pcall(function()
		return (adminStore :: DataStore):GetAsync(ADMIN_KEY)
	end)
	if ok then
		granted = if type(result) == "table" then result else {}
		refreshAdminFlags()
	end
end

-- add (name given) or remove (name nil) one admin. Returns (saved, error message)
local function setGranted(userId: number, name: string?): (boolean, string?)
	local key = tostring(userId)
	granted[key] = name
	refreshAdminFlags()
	if not adminStore then
		return false, "not saved: the DataStore is unavailable (Studio needs API access)"
	end
	local ok, err = pcall(function()
		(adminStore :: DataStore):UpdateAsync(ADMIN_KEY, function(old)
			local list = if type(old) == "table" then old else {}
			list[key] = name
			granted = list
			return list
		end)
	end)
	refreshAdminFlags()
	if not ok then
		warn("[AdminService] could not save the admin list:", err)
		return false, "not saved (DataStore error), only for this server"
	end
	return true, nil
end

-- a player in this server (part of the name is enough), or anyone on Roblox by exact username
local function resolveUser(word: string?): (number?, string?)
	if not word or word == "" then
		return nil, nil
	end
	local q = string.lower(word)
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name):sub(1, #q) == q or string.lower(p.DisplayName):sub(1, #q) == q then
			return p.UserId, p.Name
		end
	end
	local id = tonumber(word)
	local ok, result = pcall(function()
		return if id then id else Players:GetUserIdFromNameAsync(word)
	end)
	if ok and result then
		local nameOk, name = pcall(function()
			return Players:GetNameFromUserIdAsync(result)
		end)
		return result, if nameOk then name else word
	end
	return nil, nil
end

local function findTarget(admin: Player, name: unknown): Player?
	if type(name) ~= "string" or name == "" then
		return admin
	end
	local query = string.lower(name)
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name):sub(1, #query) == query or string.lower(p.DisplayName):sub(1, #query) == query then
			return p
		end
	end
	return nil
end

local function number(value: unknown): number?
	local n = tonumber(value)
	if n and n == n and math.abs(n) < 1e15 then
		return n
	end
	return nil
end

local COMMANDS: { [string]: (admin: Player, target: Player, data: any, arg: any, arg2: any) -> string? } = {}

COMMANDS.SetSpeed = function(_, target, data, arg)
	local n = number(arg)
	if not n then
		return "Enter a number"
	end
	data.Speed = math.max(0, math.floor(n))
	AnimalService.refreshStats(target)
	return `{target.Name}'s speed stat = {data.Speed} (walk speed {math.floor(Progression.walkSpeed(data.Speed))})`
end

COMMANDS.AddSpeed = function(_, target, data, arg)
	local n = number(arg)
	if not n then
		return "Enter a number"
	end
	data.Speed = math.max(0, math.floor(data.Speed + n))
	AnimalService.refreshStats(target)
	return `{target.Name}'s speed stat = {data.Speed}`
end

COMMANDS.SetMoney = function(_, target, data, arg)
	local n = number(arg)
	if not n then
		return "Enter a number"
	end
	data.Money = math.max(0, n)
	AnimalService.refreshStats(target)
	return `{target.Name}'s money = ${Util.formatNumber(data.Money)}`
end

COMMANDS.AddMoney = function(_, target, data, arg)
	local n = number(arg)
	if not n then
		return "Enter a number"
	end
	data.Money = math.max(0, data.Money + n)
	AnimalService.refreshStats(target)
	return `{target.Name}'s money = ${Util.formatNumber(data.Money)}`
end

COMMANDS.ResetMultiplier = function(_, target, data)
	data.SpeedMultiplier = 1
	data.EquippedTrail = 0
	ShopService.refreshMultiplier(target)
	AnimalService.pushState(target)
	return `{target.Name}: speed multiplier reset to x1 and trail unequipped`
end

COMMANDS.SetBaseTier = function(_, target, data, arg)
	local n = number(arg)
	if not n then
		return "Enter a level"
	end
	data.BaseTier = math.clamp(math.floor(n), 1, #Progression.Base)
	BaseService.applyTiers(target, data)
	AnimalService.refreshStats(target)
	return `{target.Name}'s base = Lv. {data.BaseTier}`
end

COMMANDS.SetTreadmillTier = function(_, target, data, arg)
	local n = number(arg)
	if not n then
		return "Enter a level"
	end
	data.TreadmillLevel = math.clamp(math.floor(n), 1, #Progression.Treadmill)
	BaseService.applyTiers(target, data)
	AnimalService.refreshStats(target)
	return `{target.Name}'s treadmill = Lv. {data.TreadmillLevel} ({Progression.Treadmill[data.TreadmillLevel].DisplayName})`
end

COMMANDS.ResetData = function(_, target)
	DataService.reset(target)
	task.delay(0.5, function()
		target:Kick("Your data was reset. Rejoin to start fresh!")
	end)
	return `Reset {target.Name}`
end

-- arg: an animal id
COMMANDS.GiveAnimal = function(_, target, data, arg, arg2)
	local info = Config.parseKey(arg)
	if not info then
		return "Unknown animal"
	end
	local count = math.clamp(math.floor(number(arg2) or 1), 1, 20)
	for _ = 1, count do
		table.insert(data.Inventory, info.Id)
	end
	data.Discovered[info.Id] = true
	AnimalService.syncTools(target)
	AnimalService.pushState(target)
	return `Gave {target.Name} {count}x {info.Name}`
end

COMMANDS.ClearInventory = function(_, target, data)
	table.clear(data.Inventory)
	AnimalService.syncTools(target)
	AnimalService.pushState(target)
	return `Cleared {target.Name}'s unplaced animals`
end

COMMANDS.Teleport = function(_, target, _, arg)
	local character = target.Character
	if not character then
		return "No character"
	end
	local biome = math.floor(number(arg) or 0)
	if biome == 0 then
		local plot = BaseService.getPlot(target)
		if not plot then
			return "No base"
		end
		character:PivotTo(BaseService.spawnCFrame(plot))
		return `Teleported {target.Name} home`
	end
	local minV, maxV = MapInfo.bounds(biome)
	if not minV then
		return "Unknown biome"
	end
	local center = (minV + maxV) / 2
	character:PivotTo(CFrame.new(center.X, maxV.Y + 5, center.Z))
	return `Teleported {target.Name} to {Config.Biomes[biome].Name}`
end

-- Typed commands (the admin panel's command line, like the reference's): "/setmoney 2.5M", "/give Chicken 3 bob".
-- The slash is optional; the last word can name a player (part of their name is enough, "me" or nothing is you).
type TextCommand = {
	Alias: string,
	Usage: string,
	About: string,
	Args: number, -- how many words come before the [player]
	Run: (admin: Player, target: Player, data: any, args: { string }) -> string?,
}

local function amount(word: string?): number?
	return word and Util.parseNumber(word)
end

local function findAnimal(word: string?): string?
	if not word then
		return nil
	end
	local q = string.lower((string.gsub(word, "[%s_%-]", "")))
	local prefix = nil
	for id, info in Config.Animals do
		local a, b = string.lower(id), string.lower((string.gsub(info.Name, "%s", "")))
		if a == q or b == q then
			return id
		end
		if not prefix and (string.sub(a, 1, #q) == q or string.sub(b, 1, #q) == q) then
			prefix = id
		end
	end
	return prefix
end

local function findBiome(word: string?): number?
	if not word then
		return nil
	end
	local n = tonumber(word)
	if n then
		return if Config.Biomes[n] then n else nil
	end
	local q = string.lower(word)
	if q == "base" or q == "home" then
		return 0
	end
	for i, b in Config.Biomes do
		if string.find(string.lower(b.Name), q, 1, true) then
			return i
		end
	end
	return nil
end

local TEXT: { TextCommand } = {
	{
		Alias = "/setmoney",
		Usage = "<amount> [player]",
		About = "Set their money (2.5M, 1B, 3Qa ...)",
		Args = 1,
		Run = function(a, t, d, args)
			return if amount(args[1]) then COMMANDS.SetMoney(a, t, d, amount(args[1])) else "Type an amount, like 2.5M"
		end,
	},
	{
		Alias = "/addmoney",
		Usage = "<amount> [player]",
		About = "Add to their money",
		Args = 1,
		Run = function(a, t, d, args)
			return if amount(args[1]) then COMMANDS.AddMoney(a, t, d, amount(args[1])) else "Type an amount, like 2.5M"
		end,
	},
	{
		Alias = "/setspeed",
		Usage = "<points> [player]",
		About = "Set their speed points (walk speed follows the biome curve)",
		Args = 1,
		Run = function(a, t, d, args)
			return if amount(args[1]) then COMMANDS.SetSpeed(a, t, d, amount(args[1])) else "Type a number, like 14K"
		end,
	},
	{
		Alias = "/addspeed",
		Usage = "<points> [player]",
		About = "Add to their speed points",
		Args = 1,
		Run = function(a, t, d, args)
			return if amount(args[1]) then COMMANDS.AddSpeed(a, t, d, amount(args[1])) else "Type a number, like 14K"
		end,
	},
	{
		Alias = "/give",
		Usage = "<animal> [count] [player]",
		About = "Give animals to place in their base, e.g. /give Chicken 3",
		Args = 2,
		Run = function(a, t, d, args)
			local id = findAnimal(args[1])
			if not id then
				return `No animal called "{args[1] or ""}"`
			end
			return COMMANDS.GiveAnimal(a, t, d, id, tonumber(args[2] or "1") or 1)
		end,
	},
	{
		Alias = "/clearanimals",
		Usage = "[player]",
		About = "Remove the animals they haven't placed yet",
		Args = 0,
		Run = function(a, t, d)
			return COMMANDS.ClearInventory(a, t, d)
		end,
	},
	{
		Alias = "/setbase",
		Usage = "<level> [player]",
		About = `Set their base level (1-{#Progression.Base})`,
		Args = 1,
		Run = function(a, t, d, args)
			return COMMANDS.SetBaseTier(a, t, d, tonumber(args[1] or ""))
		end,
	},
	{
		Alias = "/settreadmill",
		Usage = "<level> [player]",
		About = `Set their treadmill level (1-{#Progression.Treadmill})`,
		Args = 1,
		Run = function(a, t, d, args)
			return COMMANDS.SetTreadmillTier(a, t, d, tonumber(args[1] or ""))
		end,
	},
	{
		Alias = "/resetboost",
		Usage = "[player]",
		About = "Speed multiplier back to x1, trail taken off",
		Args = 0,
		Run = function(a, t, d)
			return COMMANDS.ResetMultiplier(a, t, d)
		end,
	},
	{
		Alias = "/tp",
		Usage = "<base | biome> [player]",
		About = "Teleport to their base or a biome (1-6 or its name, e.g. /tp tundra)",
		Args = 1,
		Run = function(a, t, d, args)
			local b = findBiome(args[1])
			if not b then
				return `No place called "{args[1] or ""}"`
			end
			return COMMANDS.Teleport(a, t, d, b)
		end,
	},
	{
		Alias = "/intro",
		Usage = "[player]",
		About = "Play the opening cutscene again",
		Args = 0,
		Run = function(_, t)
			-- (an event, not an attribute: flipping PlayIntro off and on in one frame never reached the client)
			Net.event("PlayIntro"):FireClient(t)
			return `Playing the intro for {t.Name}`
		end,
	},
	{
		Alias = "/tutorial",
		Usage = "[player]",
		About = "Play the new-player tutorial again",
		Args = 0,
		Run = function(_, t)
			Net.event("PlayTutorial"):FireClient(t)
			return `Playing the tutorial for {t.Name}`
		end,
	},
	{
		Alias = "/admin",
		Usage = "<player>",
		About = "Owner only: make someone an admin (in this server, or anyone by username)",
		Args = 1,
		Run = function(a, _, _, args)
			if not isOwner(a.UserId) then
				return "Only the owner can make admins"
			end
			local userId, name = resolveUser(args[1])
			if not userId then
				return `No player called "{args[1] or ""}"`
			end
			if isOwner(userId) or granted[tostring(userId)] then
				return `{name} is already an admin`
			end
			local saved, err = setGranted(userId, name)
			local target = Players:GetPlayerByUserId(userId)
			if target then
				Notify:FireClient(
					target,
					"You are now an admin! Open the panel with the 👑",
					Color3.fromRGB(255, 220, 90)
				)
			end
			return `{name} is now an admin` .. (if saved then "" else ` ({err})`)
		end,
	},
	{
		Alias = "/unadmin",
		Usage = "<player>",
		About = "Owner only: take someone's admin away",
		Args = 1,
		Run = function(a, _, _, args)
			if not isOwner(a.UserId) then
				return "Only the owner can remove admins"
			end
			local word = args[1] or ""
			local userId, name = nil, nil
			for key, n in granted do
				if string.lower(n) == string.lower(word) or key == word then
					userId, name = tonumber(key), n
				end
			end
			if not userId then
				userId, name = resolveUser(word)
			end
			if not userId or not granted[tostring(userId)] then
				return if userId and isOwner(userId)
					then "The owner is always an admin"
					else `{name or word} isn't an admin`
			end
			local saved, err = setGranted(userId, nil)
			return `{name} is no longer an admin` .. (if saved then "" else ` ({err})`)
		end,
	},
	{
		Alias = "/admins",
		Usage = "",
		About = "List the admins",
		Args = 0,
		Run = function()
			local names = {}
			for _, n in granted do
				table.insert(names, n)
			end
			table.sort(names)
			return if #names == 0 then "No admins besides the owner" else "Admins: " .. table.concat(names, ", ")
		end,
	},
	{
		Alias = "/resetdata",
		Usage = "[player]",
		About = "Wipe their save and kick them, so they rejoin fresh",
		Args = 0,
		Run = function(a, t, d)
			return COMMANDS.ResetData(a, t, d)
		end,
	},
}

local function runLine(admin: Player, line: string): (boolean, string)
	local words = string.split(line, " ")
	local args = {}
	for _, w in words do
		if w ~= "" then
			table.insert(args, w)
		end
	end
	local name = table.remove(args, 1)
	if not name then
		return false, "Type a command"
	end
	name = string.lower(name)
	if string.sub(name, 1, 1) ~= "/" then
		name = "/" .. name
	end
	local cmd: TextCommand? = nil
	for _, c in TEXT do
		if c.Alias == name then
			cmd = c
		end
	end
	if not cmd then
		return false, `Unknown command {name}`
	end
	-- a word past the command's own ones names the player
	local who = if #args > cmd.Args then table.remove(args) else nil
	if who and string.lower(who) == "me" then
		who = nil
	end
	local target = findTarget(admin, who)
	if not target then
		return false, `No player matching "{who}"`
	end
	local data = DataService.get(target)
	if not data then
		return false, `{target.Name} hasn't loaded yet`
	end
	local ok, message = pcall(cmd.Run, admin, target, data, args)
	if not ok then
		warn("[AdminService]", message)
		return false, "That command failed"
	end
	return true, message or "Done"
end

function AdminService.playerAdded(player: Player)
	player:SetAttribute("IsAdmin", isAdmin(player))
	player:SetAttribute("IsOwner", isOwner(player.UserId))
end

function AdminService.init()
	-- Studio playtests only: automated tests run admin commands for any player (ServerStorage.SAFD_TestHook:Invoke(
	-- playerName, "/addmoney 1M")); "__data" returns their saved data as JSON
	if game:GetService("RunService"):IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "SAFD_TestHook"
		hook.OnInvoke = function(name: string, line: string)
			local p = Players:FindFirstChild(name) :: Player?
			if not p then
				return false, "no player"
			end
			if line == "__data" then
				return true, game:GetService("HttpService"):JSONEncode(DataService.get(p))
			end
			return runLine(p, line)
		end
		hook.Parent = game:GetService("ServerStorage")
	end
	local storeOk, store = pcall(function()
		return DataStoreService:GetDataStore(ADMIN_STORE)
	end)
	adminStore = if storeOk then store else nil
	Players.PlayerAdded:Connect(AdminService.playerAdded)
	for _, p in Players:GetPlayers() do
		AdminService.playerAdded(p)
	end
	task.spawn(function()
		-- (and again now and then, so admins made or removed in another server count here too)
		while true do
			loadGranted()
			task.wait(60)
		end
	end)
	Net.func("AdminAction").OnServerInvoke = function(admin: Player, action: unknown, line: unknown)
		if not isAdmin(admin) then
			return false, "Admins only"
		end
		if action == "info" then
			local list = {}
			for _, c in TEXT do
				table.insert(list, { Alias = c.Alias, Usage = c.Usage, About = c.About })
			end
			local admins = {}
			for key, n in granted do
				table.insert(admins, { UserId = tonumber(key), Name = n })
			end
			table.sort(admins, function(x, y)
				return x.Name < y.Name
			end)
			return true, { Commands = list, Owner = isOwner(admin.UserId), Admins = admins }
		elseif action == "run" and type(line) == "string" and #line < 200 then
			local ok, message = runLine(admin, line)
			Notify:FireClient(
				admin,
				(if ok then "[Admin] " else "") .. message,
				if ok then Color3.fromRGB(255, 220, 90) else Color3.fromRGB(255, 120, 80)
			)
			return ok, message
		end
		return false, ""
	end
	Net.event("AdminCommand").OnServerEvent:Connect(function(admin, command, targetName, arg, arg2)
		if not isAdmin(admin) or type(command) ~= "string" then
			return
		end
		local handler = COMMANDS[command]
		local target = findTarget(admin, targetName)
		if not handler then
			return
		end
		if not target then
			Notify:FireClient(admin, `No player matching "{targetName}"`, Color3.fromRGB(255, 120, 80))
			return
		end
		local data = DataService.get(target)
		if not data then
			Notify:FireClient(admin, `{target.Name} hasn't loaded yet`, Color3.fromRGB(255, 120, 80))
			return
		end
		local message = handler(admin, target, data, arg, arg2)
		if message then
			Notify:FireClient(admin, "[Admin] " .. message, Color3.fromRGB(255, 220, 90))
		end
	end)
end

return AdminService
