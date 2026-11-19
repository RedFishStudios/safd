-- Measures the map once at startup and publishes it to ReplicatedStorage.MapInfo (see Shared/MapInfo).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local MapService = {}

function MapService.init()
	local folder = Instance.new("Folder")
	folder.Name = "MapInfo"

	local levels = Workspace:WaitForChild("Levels")
	local firstCenter: Vector3? = nil
	for i, biome in Config.Biomes do
		local level = levels:WaitForChild(biome.Level, 30)
		local track = level and level:FindFirstChild(biome.Track, true)
		if not track then
			warn(`[MapService] missing track {biome.Track} in {biome.Level}`)
			continue
		end
		local minV, maxV = Util.aabb(track)
		folder:SetAttribute(`Biome{i}Min`, minV)
		folder:SetAttribute(`Biome{i}Max`, maxV)
		if i == 1 then
			firstCenter = (minV + maxV) / 2
		end
	end

	local spawnElements = Workspace:WaitForChild("Spawn_elements")
	local line = spawnElements:WaitForChild("Danger_line") :: BasePart
	local linePos = line.Position
	-- Bases are on the far side of the line from the first biome.
	local away = linePos - (firstCenter or (linePos + Vector3.new(0, 0, 1)))
	local toBase = Vector3.new(0, 0, if away.Z >= 0 then 1 else -1)
	folder:SetAttribute("DangerLine", linePos)
	folder:SetAttribute("ToBase", toBase)
	folder:SetAttribute("Ready", true)
	folder.Parent = ReplicatedStorage
end

return MapService
