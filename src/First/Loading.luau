--@localscript
-- No loading screen any more (user 2026-11-21: "the map loads fast enough now"). Roblox's own short default screen
-- covers the moment the place arrives (Workspace.StreamingEnabled is off, so the whole map is here when game.Loaded
-- fires); then player:GetAttribute("WorldReady") turns true (Client/IntroCutscene and Client/Tutorial wait for it).
-- Meshes and pictures keep downloading quietly in the background, so nothing waits on them.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

if not game:IsLoaded() then
	game.Loaded:Wait()
end
player:SetAttribute("WorldReady", true)

-- meshes and pictures, in the background (batches, so nothing hitches)
task.spawn(function()
	local list: { Instance } = {}
	local function collect(root: Instance?)
		if not root then
			return
		end
		for _, d in root:GetDescendants() do
			if d:IsA("MeshPart") or d:IsA("Decal") or d:IsA("SpecialMesh") or d:IsA("ImageLabel") then
				table.insert(list, d)
			end
		end
	end
	collect(ReplicatedStorage:FindFirstChild("Assets"))
	collect(game:GetService("StarterGui"))
	collect(workspace)
	for i = 1, #list, 60 do
		pcall(function()
			ContentProvider:PreloadAsync(table.move(list, i, math.min(i + 59, #list), 1, {}))
		end)
		task.wait()
	end
end)
