-- The wild eggs come alive on your screen: they wobble now and then like something inside wants out, the Mythic
-- egg's halo turns and the radioactive egg's barrels orbit it (Shared/EggFactory names them in the Halo / Orbit
-- attributes). Only eggs near you are animated.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local EggVisuals = {}

type Entry = {
	model: Model,
	base: CFrame,
	spinners: { { model: Model, base: CFrame, speed: number } },
	phase: number,
	lastW: number,
}
local eggs: { [Model]: Entry } = {}

local function add(model: Instance)
	if not model:IsA("Model") or eggs[model] then
		return
	end
	local entry: Entry =
		{ model = model, base = model:GetPivot(), spinners = {}, phase = math.random() * 10, lastW = 0 }
	for attr, speed in { Halo = 0.8, Orbit = 0.6 } do
		local name = model:GetAttribute(attr)
		local child = name and model:FindFirstChild(name)
		if child and child:IsA("Model") then
			table.insert(entry.spinners, { model = child, base = child:GetPivot(), speed = speed })
		end
	end
	eggs[model] = entry
end

function EggVisuals.init()
	for _, m in CollectionService:GetTagged("WildEgg") do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal("WildEgg"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("WildEgg"):Connect(function(m)
		eggs[m :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local t = os.clock()
		-- during the run home, only the labels of eggs right by you show: the rest covered the luck badges and the way
		-- ahead (user 2026-11-20: no clutter)
		local chasing = workspace:FindFirstChild("LocalDisaster") ~= nil
		for model, e in eggs do
			local root2 = model.PrimaryPart
			local tag = root2 and root2:FindFirstChild("Tag")
			if tag and tag:IsA("BillboardGui") then
				tag.Enabled = not chasing or (e.base.Position - root.Position).Magnitude < 45
			end
			if not model.Parent then
				eggs[model] = nil
				continue
			end
			if (e.base.Position - root.Position).Magnitude > 260 then
				continue
			end
			-- a wobble every few seconds
			local c = (t + e.phase) % 4
			local w = if c < 0.8 then math.sin(c * 25) * 0.07 * (1 - c / 0.8) else 0
			local wobble = e.base * CFrame.Angles(w, 0, w * 0.6)
			if w ~= 0 or e.lastW ~= 0 then
				model:PivotTo(wobble)
			end
			e.lastW = w
			for _, s in e.spinners do
				local centre = wobble * e.base:Inverse() * s.base
				s.model:PivotTo(
					CFrame.new(wobble.Position)
						* CFrame.Angles(0, t * s.speed, 0)
						* (CFrame.new(wobble.Position):Inverse() * centre)
				)
			end
		end
	end)
end

return EggVisuals
