-- Player data persistence (DataStoreService) with a simple session lock so two servers
-- never write the same player at once. Data shape:
--   { Money, Speed, Inventory = {animalId}, Placed = {{Uid, Id, X, Z, R}}, LastOnline, Version }

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local DataService = {}

local LOCK_TIMEOUT = 150 -- seconds before another server's lock is treated as stale
local DEFAULT = {
	Money = 0,
	Speed = 0,
	Inventory = {},
	Placed = {},
	LastOnline = 0,
	Version = 1,
	Discovered = {}, -- [animalId] = true once saved at least once (Index)
	IndexClaimed = {}, -- [animalId] = true once its Index reward was claimed
	Trails = {}, -- [trailIndex as string] = true when owned
	EquippedTrail = 0,
	FreeItemClaimed = false,
	PendingOffline = 0, -- offline earnings waiting for the "Claim" button
	TreadmillLevel = 1, -- treadmill tier (Shared/Progression.Treadmill)
	BaseTier = 1, -- base tier (Shared/Progression.Base)
	SpeedMultiplier = 1, -- Robux "double your speed"
}

type Profile = { Data: any, Key: string, CanSave: boolean, Saving: boolean }

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function reconcile(data: any): any
	for key, value in DEFAULT do
		if data[key] == nil then
			data[key] = deepCopy(value)
		end
	end
	return data
end

-- One UpdateAsync that claims the session lock. Returns (ok, data | nil, lockedElsewhere, err).
local function claim(key: string, steal: boolean): (boolean, any, boolean, any)
	local result, locked = nil, false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key, function(old)
			result, locked = nil, false
			local lock = old and old.Lock
			if not steal and lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < LOCK_TIMEOUT then
				locked = true
				return nil -- abort, leave the record untouched
			end
			local record = {
				Data = (old and old.Data) or deepCopy(DEFAULT),
				Lock = { JobId = game.JobId, Time = os.time() },
			}
			result = record.Data
			return record
		end)
	end)
	return ok, result, locked, err
end

function DataService.load(player: Player): any
	local key = `u_{player.UserId}`
	if not store then
		local data = deepCopy(DEFAULT)
		profiles[player] = { Data = data, Key = key, CanSave = false, Saving = false }
		return data
	end

	local data, failures = nil, 0
	for attempt = 1, 10 do
		local ok, result, locked, err = claim(key, attempt >= 7)
		if ok and result then
			data = result
			break
		elseif not ok then
			failures += 1
			warn(`[DataService] load failed for {player.Name} (attempt {attempt}): {err}`)
			-- 403 = Studio without "Enable Studio Access to API Services"; retrying won't help.
			if failures >= 3 or string.find(tostring(err), "403") then
				break
			end
		elseif locked then
			warn(`[DataService] {player.Name}'s data is still locked by another server, retrying...`)
		end
		task.wait(if attempt < 3 then 2 else 5)
		if not player.Parent then
			return nil
		end
	end

	if not data then
		-- DataStore unreachable (e.g. Studio without API access). Play on, but never overwrite real data.
		warn(`[DataService] using temporary data for {player.Name}; progress will NOT be saved`)
		data = deepCopy(DEFAULT)
		profiles[player] = { Data = data, Key = key, CanSave = false, Saving = false }
		return data
	end

	reconcile(data)
	profiles[player] = { Data = data, Key = key, CanSave = true, Saving = false }
	return data
end

function DataService.get(player: Player): any
	local profile = profiles[player]
	return profile and profile.Data
end

-- Wipes a player back to a brand-new save (admin ResetData); they rejoin to start over.
function DataService.reset(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	table.clear(profile.Data)
	for key, value in DEFAULT do
		profile.Data[key] = deepCopy(value)
	end
end

function DataService.canSave(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.CanSave
end

local function save(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return
	end
	while profile.Saving do
		task.wait(0.1)
	end
	profile.Saving = true
	profile.Data.LastOnline = os.time()
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(profile.Key, function(old)
			local lock = old and old.Lock
			if lock and lock.JobId ~= game.JobId then
				return nil -- another server took over this session; don't clobber it
			end
			return {
				Data = profile.Data,
				Lock = if release then nil else { JobId = game.JobId, Time = os.time() },
			}
		end)
	end)
	if not ok then
		warn(`[DataService] save failed for {player.Name}: {err}`)
	end
	profile.Saving = false
end

function DataService.release(player: Player)
	save(player, true)
	profiles[player] = nil
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn(`[DataService] DataStore unavailable: {result}`)
	end

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Main releases explicitly after other services clean up; this is a fallback.
		task.delay(5, function()
			if profiles[player] then
				DataService.release(player)
			end
		end)
	end)
end

return DataService
