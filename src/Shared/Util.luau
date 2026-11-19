-- Small helpers shared by server and client.

local Util = {}

-- Big numbers like the reference game shows them everywhere: 950, 1.5K, 14K, 25M, 3.2B, 1T, 9.9Qa ... one
-- decimal with ".0" dropped, and a number that rounds up to the next unit shows in it (999.95K is 1M).
local UNITS = {
	{ 1e33, "Dc" },
	{ 1e30, "No" },
	{ 1e27, "Oc" },
	{ 1e24, "Sp" },
	{ 1e21, "Sx" },
	{ 1e18, "Qi" },
	{ 1e15, "Qa" },
	{ 1e12, "T" },
	{ 1e9, "B" },
	{ 1e6, "M" },
	{ 1e3, "K" },
}
function Util.formatNumber(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	local abs = math.abs(n)
	for _, u in UNITS do
		local unit = u[1]
		if abs >= (if unit == 1e3 then 999.5 else unit * 0.99995) then
			return sign .. (string.format("%.1f", abs / unit):gsub("%.0$", "")) .. u[2]
		end
	end
	return sign .. tostring(math.floor(abs + 0.5))
end

-- The other way: "2.5M", "1b", "3Qa", "14,000", "500" -> a number (nil if it isn't one).
function Util.parseNumber(text: string): number?
	local t = string.gsub(string.gsub(text, ",", ""), "^%$", "")
	local num, unit = string.match(t, "^([%d%.]+)(%a*)$")
	local n = num and tonumber(num)
	if not n then
		return nil
	end
	if unit == "" then
		return n
	end
	for _, u in UNITS do
		if string.lower(u[2]) == string.lower(unit) then
			return n * u[1]
		end
	end
	return nil
end

function Util.parts(root: Instance): { BasePart }
	local list = {}
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

local CORNERS = {}
for _, x in { -1, 1 } do
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(CORNERS, Vector3.new(x, y, z))
		end
	end
end

-- Axis-aligned bounds of every part under `root`, measured in the space of `frame`.
function Util.boundsIn(root: Instance, frame: CFrame): (Vector3, Vector3)
	local minV = Vector3.one * math.huge
	local maxV = -minV
	for _, part in Util.parts(root) do
		local half = part.Size / 2
		for _, corner in CORNERS do
			local p = frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(half * corner))
			minV = minV:Min(p)
			maxV = maxV:Max(p)
		end
	end
	return minV, maxV
end

function Util.aabb(root: Instance): (Vector3, Vector3)
	return Util.boundsIn(root, CFrame.identity)
end

function Util.setModelPhysics(model: Instance, anchored: boolean)
	for _, part in Util.parts(model) do
		part.Anchored = anchored
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = true
	end
end

function Util.weightedPick(rng: Random, weights: { number }): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 then
			return i
		end
	end
	return #weights
end

return Util
