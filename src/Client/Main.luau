--@script:client
-- Client entry point. Synced to StarterPlayer.StarterPlayerScripts.Client.Main by Lync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

print(`[SAFD] Client started ({Config.GameName})`)
