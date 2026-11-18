--@script:server
-- Server entry point. Synced to ServerScriptService.Server.Main by Lync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

print(`[SAFD] Server started ({Config.GameName})`)
