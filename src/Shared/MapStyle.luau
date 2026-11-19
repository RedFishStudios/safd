-- The map's look, for everything the game builds at runtime (the run's set-pieces, the disaster wall, hazards, the
-- intro). The map's bricks are Plastic with the place's "2022 Stud" MaterialVariant (MaterialService), the Lego studs
-- look; Roblox's realistic materials (Rock, Slate, Ice, Mud ...) stand out against it, so they're swapped for it.
-- Glowing, glass and force-field effects keep their own material.

local MapStyle = {}

MapStyle.Variant = "2022 Stud"

local KEEP = {
	[Enum.Material.Neon] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.ForceField] = true,
}

function MapStyle.apply(part: BasePart): BasePart
	if not KEEP[part.Material] then
		part.Material = Enum.Material.Plastic
		part.MaterialVariant = MapStyle.Variant
	end
	return part
end

-- every part under root
function MapStyle.applyAll(root: Instance)
	if root:IsA("BasePart") then
		MapStyle.apply(root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			MapStyle.apply(d)
		end
	end
end

return MapStyle
