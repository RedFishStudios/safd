-- Read-only view of the map layout (biome tracks, safe line) for server and client.
-- The server's MapService measures the map and writes attributes onto ReplicatedStorage.MapInfo,
-- because with StreamingEnabled the client may not have the track parts loaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local MapInfo = {}

local folder: Instance? = nil

local function data(): Instance
	if folder and folder:GetAttribute("Ready") then
		return folder
	end
	local f = ReplicatedStorage:WaitForChild("MapInfo")
	while not f:GetAttribute("Ready") do
		f:GetAttributeChangedSignal("Ready"):Wait()
	end
	folder = f
	return f
end

function MapInfo.biomeCount(): number
	return #Config.Biomes
end

-- World-space AABB of a biome's running track.
function MapInfo.bounds(biome: number): (Vector3, Vector3)
	local f = data()
	return f:GetAttribute(`Biome{biome}Min`), f:GetAttribute(`Biome{biome}Max`)
end

-- Unit vector pointing from the biomes towards the bases.
function MapInfo.toBase(): Vector3
	return data():GetAttribute("ToBase")
end

function MapInfo.dangerLine(): Vector3
	return data():GetAttribute("DangerLine")
end

-- True once the position is on the base side of the white line.
function MapInfo.isSafe(position: Vector3): boolean
	local f = data()
	local line: Vector3 = f:GetAttribute("DangerLine")
	local toBase: Vector3 = f:GetAttribute("ToBase")
	return (position - line):Dot(toBase) > 0
end

function MapInfo.biomeAt(position: Vector3): number?
	for i = 1, #Config.Biomes do
		local minV, maxV = MapInfo.bounds(i)
		if
			minV
			and position.X >= minV.X - 6
			and position.X <= maxV.X + 6
			and position.Z >= minV.Z
			and position.Z <= maxV.Z
		then
			return i
		end
	end
	return nil
end

return MapInfo
