-- Finds base models built by the server (Workspace.PlayerBases.BaseN).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Bases = {}

function Bases.folder(): Instance?
	return Workspace:FindFirstChild("PlayerBases")
end

function Bases.mine(): Model?
	local folder = Bases.folder()
	if not folder then
		return nil
	end
	local userId = Players.LocalPlayer.UserId
	for _, base in folder:GetChildren() do
		if base:GetAttribute("Owner") == userId then
			return base :: Model
		end
	end
	return nil
end

function Bases.byIndex(index: number): Model?
	local folder = Bases.folder()
	if not folder then
		return nil
	end
	for _, base in folder:GetChildren() do
		if base:GetAttribute("PlotIndex") == index then
			return base :: Model
		end
	end
	return nil
end

function Bases.isInside(base: Instance, x: number, z: number): boolean
	return x >= base:GetAttribute("MinX")
		and x <= base:GetAttribute("MaxX")
		and z >= base:GetAttribute("MinZ")
		and z <= base:GetAttribute("MaxZ")
end

return Bases
