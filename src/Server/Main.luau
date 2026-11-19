--@script:server
-- Server entry point. Synced to ServerScriptService.Server.Main by Lync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
require(Shared.Net) -- creates the remotes before anything else needs them

local Server = script.Parent
local MapService = require(Server.MapService)
local DataService = require(Server.DataService)
local BaseService = require(Server.BaseService)
local AnimalService = require(Server.AnimalService)
local TrainingService = require(Server.TrainingService)
local ShopService = require(Server.ShopService)
local AdminService = require(Server.AdminService)
local AvatarService = require(Server.AvatarService)

MapService.init()
DataService.init()
BaseService.init()
AnimalService.init()
TrainingService.init(AnimalService.refreshStats)
ShopService.init()
AdminService.init()
AvatarService.init()

local function onPlayerAdded(player: Player)
	local data = DataService.load(player)
	if not player.Parent then
		DataService.release(player) -- left while loading; free the session lock
		return
	end
	if not data then
		return
	end
	BaseService.assign(player)
	BaseService.applyTiers(player, data)
	AnimalService.playerLoaded(player, data)
	TrainingService.playerLoaded(player)
	ShopService.playerLoaded(player)
	player:SetAttribute("Loaded", true)
	if not data.SeenIntro then
		data.SeenIntro = true
		player:SetAttribute("PlayIntro", true)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	AnimalService.playerRemoving(player)
	TrainingService.playerRemoving(player)
	DataService.release(player)
	BaseService.release(player)
end)

print(`[SAFD] Server started ({Config.GameName})`)
