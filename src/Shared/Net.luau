-- Remote events/functions. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"DisasterStart", -- server -> client (biomeIndex)
	"DisasterEnd", -- server -> client (savedCount, lost)
	"SpeedGain", -- server -> client (points gained per treadmill payout group)
	"BuyUpgrade", -- client -> server ("Base" | "Treadmill")
	"Purchased", -- server -> client (kind) after anything is bought: the cha-ching
	"PlaceAnimal", -- client -> server (animalId, localX, localZ, rotation)
	"InventoryChanged", -- server -> client ({animalId})
	"Notify", -- server -> client (text, color?)
	"StateChanged", -- server -> client (state table, see AnimalService.state)
	"ClaimOffline", -- client -> server (multiplier ignored unless a product was bought)
	"ClaimIndexReward", -- client -> server (animalId)
	"SellAnimals", -- client -> server ({animalId})
	"BuyTrail", -- client -> server (trailIndex)
	"EquipTrail", -- client -> server (trailIndex | 0)
	"ClaimFreeItem", -- client -> server
	"ProductRequest", -- client -> server (productKey) -> prompts the developer product if configured
	"AdminCommand", -- client -> server (command, args) — admins only
	"RunRing", -- client -> server (value): a multiplier ring collected on the run home
	"RunReward", -- server -> client ({ Base, Rings, Total, Animals }): the bonus for getting animals home
}
local FUNCTIONS = {
	"GetState", -- client -> server, returns { Inventory = {...} } once data is loaded
	"AdminAction", -- client -> server ("info" | "run", line) -> (ok, info | message): the admin panel
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in EVENTS do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		for _, name in FUNCTIONS do
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local Net = {}

function Net.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
