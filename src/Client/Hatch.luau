-- The hatch CUTSCENE after a run home (user 2026-11-21; Net.RunReward from Server/AnimalService:
-- { Eggs, Rings, Luck, Animals, Chances, New }). In the world, only you (other players are hidden):
--   1. you stop at the white line and the egg drops onto the ground in front of you, the camera beside you both
--   2. "🍀 1x Luck" at the top counts up badge by badge; the egg GROWS with every badge (Model:ScaleTo about its
--      bottom), a swell / settle pulse, a ring of light on the ground, sparkles, a pop and the next note up a scale
--   3. it wobbles and shakes while the odds climb: "1/5, 1/6 ... 1/37" (1/1..1/4 just show) (the longer it climbs, the rarer the animal
--      inside: it stops at the real odds it had), creaking and cracking
--   4. it cracks: one flash, the top of the shell flies off and the animal grows up out of the bottom half
--   5. rare ones glow: sparkles from Rare up, a coloured glow from Epic, light beams and "SUPER LUCKY!" from Legendary
--      ("LUCKY!" ... "INSANE LUCK!!!" by rarity), the card: name, rarity, "1 in 37", $/s, NEW!
-- Several eggs: one after another (later ones skip the luck count, it's the same luck). Tap to skip the wait.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalFactory = require(Shared.AnimalFactory)
local Config = require(Shared.Config)
local EggFactory = require(Shared.EggFactory)
local MapInfo = require(Shared.MapInfo)
local Net = require(Shared.Net)
local MapStyle = require(Shared.MapStyle)
local Util = require(Shared.Util)

local rng = Random.new()

local ChaseFx = require(script.Parent.ChaseFx)
local Movement = require(script.Parent.Movement)

local player = Players.LocalPlayer

local Hatch = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- the hatch's own sounds: free Creator Store audio, preloaded in Hatch.init
local SOUNDS = {
	Pop = "rbxassetid://109359226723492", -- a cartoon bubble pop: every badge
	Note = "rbxassetid://72644163309528", -- a glockenspiel C6: every badge, climbing a happy scale
	Bling1 = "rbxassetid://4612374393", -- a diamond pickup sparkle
	Bling2 = "rbxassetid://4612374495",
	BigBling = "rbxassetid://4612374036", -- the final value lands
	Riser = "rbxassetid://75942496423806", -- the rising tone under the build-up
	Crack = "rbxassetid://9113542386", -- the shell cracks (pitched up: eggshell)
	Prize = "rbxassetid://119620526223720", -- it bursts open
	Win = "rbxassetid://1846251701", -- a great animal (Epic and up)
	LifeUp = "rbxassetid://7381724959", -- any other animal
}
local soundBank: { [string]: Sound } = {}
local function sfx(name: string, volume: number, pitch: number?): Sound?
	local base = soundBank[name]
	if not base then
		return nil
	end
	local snd = base:Clone()
	snd.Volume = volume * 2 * (player:GetAttribute("SfxVolume") or 0.5)
	snd.PlaybackSpeed = pitch or 1
	snd.Parent = game:GetService("SoundService")
	snd:Play()
	snd.Ended:Once(function()
		snd:Destroy()
	end)
	task.delay(8, function()
		if snd.Parent and not snd.Looped then
			snd:Destroy()
		end
	end)
	return snd
end
-- a major-pentatonic climb, in semitones: each badge plays the next note up
local SCALE = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 31, 33, 36 }
local function notePitch(i: number): number
	return 2 ^ (SCALE[math.clamp(i, 1, #SCALE)] / 12) * 0.5
end

-- what the screen shouts for each rarity (nothing for Common / Uncommon)
local LUCKY = {
	[3] = "LUCKY!",
	[4] = "VERY LUCKY!",
	[5] = "SUPER LUCKY!",
	[6] = "MEGA LUCKY!!",
	[7] = "ULTRA LUCKY!!",
	[8] = "INSANE LUCK!!!",
	[9] = "INSANE LUCK!!!",
}

-- the odds counter's colour: it turns "rarer" colours the higher it climbs
local function oddsColor(n: number): Color3
	local steps = { { 4, 1 }, { 15, 2 }, { 60, 3 }, { 250, 4 }, { 1000, 5 }, { 5000, 6 }, { 25000, 7 } }
	for _, s in steps do
		if n < s[1] then
			return Config.Rarities[s[2]].Color
		end
	end
	return Config.Rarities[8].Color:Lerp(Color3.new(1, 1, 1), 0.6)
end

-- the egg's size for this much luck: small steps at first, much bigger with lots of luck, never silly
-- (badges multiply since 2026-11-21, so luck runs into the millions: the size follows how many times it doubled)
local function eggScaleFor(luck: number): number
	return 1 + 1.6 * (1 - math.exp(-math.log(math.max(luck, 1), 2) / 6))
end

-- how much luck, 0..1, for "bigger everything" (x1 .. about x1M)
local function luckHeat(luck: number): number
	return math.clamp(math.log(math.max(luck, 1), 2) / 20, 0, 1)
end

-- "1x", "12x", "2,000x" (in full with commas: user 2026-11-22)
local function luckText(v: number, _final: boolean): string
	return "🍀 " .. Util.commas(v) .. "x Luck"
end

local gui: ScreenGui
local busy = false
local queue = {}

local function tween(
	inst: Instance,
	time: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function label(parent: Instance, props: { [string]: any }, strokeSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(l :: any)[k] = v
	end
	if strokeSize then
		local s = Instance.new("UIStroke")
		s.Thickness = strokeSize
		s.Color = Color3.fromRGB(15, 10, 25)
		s.Parent = l
	end
	l.Parent = parent
	return l
end

local function bounce(l: GuiObject, from: number)
	local sc = l:FindFirstChild("Bounce") :: UIScale?
	if not sc then
		local made = Instance.new("UIScale")
		made.Name = "Bounce"
		made.Parent = l
		sc = made
	end
	(sc :: UIScale).Scale = from
	tween(sc :: UIScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- a ring of light running out over the ground from the egg
local function groundRing(folder: Instance, at: Vector3, color: Color3, size: number)
	local r = Instance.new("Part")
	r.Shape = Enum.PartType.Cylinder
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CastShadow = false
	r.Material = Enum.Material.Neon
	r.Color = color
	r.Transparency = 0.2
	r.Size = Vector3.new(0.2, 2, 2)
	r.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	r.Parent = folder
	tween(r, 0.55, { Size = Vector3.new(0.2, size, size), Transparency = 1 })
	task.delay(0.6, function()
		r:Destroy()
	end)
end

-- the scene's sparkle emitter, moved to where it's wanted and fired
local function burst(emitter: ParticleEmitter, at: Vector3, color: Color3, n: number)
	local a = emitter.Parent :: Attachment
	a.WorldPosition = at
	emitter.Color = ColorSequence.new(color)
	emitter:Emit(n)
end

-- hides everyone else for the cutscene (only on your screen), and every floating label (shop titles, base animal
-- tags, base signs); returns how to put them back
local function hideOthers(near: Vector3): () -> ()
	local changed: { [BasePart]: number } = {}
	-- (and the base animals near the egg: only you and your egg are in the shot)
	local animals = Workspace:FindFirstChild("BaseAnimals")
	if animals then
		for _, m in animals:GetChildren() do
			if m:IsA("Model") and (m:GetPivot().Position - near).Magnitude < 90 then
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						changed[d] = d.LocalTransparencyModifier
						d.LocalTransparencyModifier = 1
					end
				end
			end
		end
	end
	local guis: { [BillboardGui]: boolean } = {}
	for _, root in
		{
			player:FindFirstChild("PlayerGui"),
			Workspace:FindFirstChild("BaseAnimals"),
			Workspace:FindFirstChild("PlayerBases"),
			Workspace:FindFirstChild("Spawn_elements"),
		}
	do
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("BillboardGui") and d.Enabled then
					guis[d] = true
					d.Enabled = false
				end
			end
		end
	end
	-- no other player is ever in the shot (user 2026-11-22): their characters, what they carry and their name tags,
	-- checked again every 0.2 s so someone who joins, respawns or walks in during the cutscene stays hidden too
	local function hidePlayers()
		for _, p in Players:GetPlayers() do
			if p ~= player and p.Character then
				for _, d in p.Character:GetDescendants() do
					if d:IsA("BasePart") or d:IsA("Decal") then
						if changed[d :: any] == nil then
							changed[d :: any] = (d :: any).LocalTransparencyModifier
						end
						(d :: any).LocalTransparencyModifier = 1
					elseif d:IsA("BillboardGui") and d.Enabled then
						guis[d] = true
						d.Enabled = false
					end
				end
			end
		end
	end
	hidePlayers()
	local acc = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			hidePlayers()
		end
	end)
	return function()
		conn:Disconnect()
		for part, v in changed do
			if part.Parent then
				part.LocalTransparencyModifier = v
			end
		end
		for g, v in guis do
			if g.Parent then
				g.Enabled = v
			end
		end
	end
end

local function partsOf(model: Model): { BasePart }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(list, d)
		end
	end
	return list
end

type Scene = {
	folder: Folder,
	screen: Frame,
	root: BasePart,
	forward: Vector3,
	spot: Vector3,
	camWant: CFrame,
	sparks: ParticleEmitter,
	skip: boolean,
	shakeUntil: number,
	shakeAmp: number,
}

-- one egg: grow with the luck, climb the odds, crack, show the animal
local function hatchOne(sc: Scene, k: number, total: number, info: any)
	local biome = (type(info.Eggs) == "table" and info.Eggs[k]) or 1
	local id = info.Animals[k]
	local chance = (type(info.Chances) == "table" and info.Chances[k]) or 100
	local animal = Config.Animals[id]
	if not animal then
		return
	end
	local rarity = animal.Rarity
	local rcolor = Config.Rarities[rarity].Color
	local isNew = type(info.New) == "table" and table.find(info.New, id) ~= nil
	local luck = math.max(1, tonumber(info.Luck) or 1)
	local rings: { number } = if type(info.Rings) == "table" then info.Rings else {}
	local screen = sc.screen
	local spot = sc.spot
	local up = Vector3.yAxis
	local facing = CFrame.lookAt(spot, spot - sc.forward) - spot

	-- 1. the egg drops in
	local startH = 5 + biome * 0.8
	local design = (type(info.Designs) == "table" and info.Designs[k]) or 1 -- (the look of the egg you carried)
	local egg = EggFactory.create(biome, startH, design)
	local eggParts = partsOf(egg)
	for _, d in egg:GetDescendants() do
		if d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	egg.Parent = sc.folder
	-- the nest it sits in (sized for the egg at its biggest): a ring of straw blocks
	local nestR = startH * eggScaleFor(luck) * 0.42
	local nest = Instance.new("Model")
	nest.Name = "Nest"
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = Vector3.new(nestR * 0.55, nestR * 0.28, nestR * 0.3)
		p.Color = if i % 2 == 0 then Color3.fromRGB(196, 150, 80) else Color3.fromRGB(165, 118, 60)
		p.CFrame = CFrame.new(spot + Vector3.new(math.cos(a) * nestR, nestR * 0.12, math.sin(a) * nestR))
			* CFrame.Angles(0, -a, math.rad(if i % 2 == 0 then 12 else -10))
		p.Parent = nest
	end
	local bed = Instance.new("Part")
	bed.Anchored = true
	bed.CanCollide = false
	bed.CanQuery = false
	bed.CanTouch = false
	bed.Shape = Enum.PartType.Cylinder
	bed.Size = Vector3.new(0.3, nestR * 2, nestR * 2)
	bed.CFrame = CFrame.new(spot + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	bed.Color = Color3.fromRGB(140, 100, 52)
	bed.Parent = nest
	require(ReplicatedStorage.Shared.MapStyle).applyAll(nest)
	nest.Parent = sc.folder
	local scale = 1
	local wobble = 0
	local hop = 30
	local function eggH(): number
		return startH * scale
	end
	local function placeEgg(t: number)
		local w = wobble
		egg:PivotTo(CFrame.new(spot + up * hop) * facing * CFrame.Angles(math.sin(t * 23) * w, 0, math.cos(t * 19) * w))
	end
	local counter = screen:FindFirstChild("Counter") :: TextLabel?
	if counter then
		counter.Text = if total > 1 then `Egg {k} of {total}` else ""
	end
	-- the camera behind you, looking past you at the egg and the biomes beyond (user 2026-11-22: "face this way"),
	-- further back and higher as the egg grows
	local function aim()
		local h = eggH()
		local mid = spot + up * (h * 0.5)
		local stand = sc.root.Position
		local right = sc.forward:Cross(up).Unit
		local pos = stand - sc.forward * (9 + h * 0.9) + up * (4.5 + h * 0.45) + right * (4 + h * 0.3)
		sc.camWant = CFrame.lookAt(pos, mid)
	end
	aim()
	local t0 = os.clock()
	local liveConn = RunService.RenderStepped:Connect(function()
		placeEgg(os.clock() - t0)
	end)
	local dropT = os.clock()
	while os.clock() - dropT < 0.45 do
		local a = (os.clock() - dropT) / 0.45
		hop = 30 * (1 - a * a)
		task.wait()
	end
	hop = 0
	ChaseFx.play("Thud", 0.8, 0.9)
	groundRing(sc.folder, spot, Color3.new(1, 1, 1), startH * 3)
	burst(sc.sparks, spot + up, Color3.fromRGB(255, 240, 200), 12)
	egg:ScaleTo(1.15)
	task.wait(0.07)
	egg:ScaleTo(1)
	task.wait(0.35)

	-- 2. the luck
	local luckLabel = screen:FindFirstChild("Luck") :: TextLabel
	luckLabel.Visible = true
	local values = {}
	if k == 1 then
		local acc = 1
		for _, v in rings do
			acc = math.min(acc * math.max(tonumber(v) or 1, 1), luck) -- (badges multiply)
			table.insert(values, acc)
		end
		-- (lots of badges: at most 24 steps)
		if #values > 24 then
			local thinned = {}
			for i = 1, 24 do
				table.insert(thinned, values[math.ceil(i / 24 * #values)])
			end
			values = thinned
		end
	end
	if #values == 0 or values[#values] ~= luck then
		table.insert(values, luck)
	end
	local shown = 1
	luckLabel.Text = luckText(1, false)
	bounce(luckLabel, 1.4)
	local riser = if luck > 1 then sfx("Riser", 0.12, 0.8) else nil
	if riser then
		riser.Looped = true
	end
	-- ONE smooth growth from start to end (user 2026-11-22: it "keeps stopping and stopping"; it used to ease out to
	-- a stop at every badge): the egg never pauses, it grows a little faster as it goes, the luck counts up with it
	-- (multiplying, badge by badge) and each badge's pop / chime / ring fires as its luck is passed, without a stop
	local growTime = math.clamp(#values * 0.42, 1.2, 4.5)
	local g0, g1 = scale, eggScaleFor(luck)
	local tA = os.clock()
	local fired = 0
	while not sc.skip do
		local a = math.clamp((os.clock() - tA) / growTime, 0, 1)
		local p = a ^ 1.25 -- (speeding up)
		-- the luck: through the badges in turn, multiplying smoothly between them
		local f = p * #values
		local i0 = math.min(math.floor(f), #values - 1)
		local lo = if i0 == 0 then 1 else values[i0]
		local hi = values[i0 + 1]
		shown = if a >= 1 then luck else lo * (hi / lo) ^ (f - i0)
		luckLabel.Text = luckText(shown, a >= 1)
		-- the egg: bigger all the time, with a light wobble so it feels alive
		scale = (g0 + (g1 - g0) * p) * (1 + math.sin(os.clock() * 18) * 0.012)
		egg:ScaleTo(scale)
		aim()
		-- the badges passed so far
		local reached = if a >= 1 then #values else math.floor(f)
		while fired < reached do
			fired += 1
			local i = fired
			local h = luckHeat(values[i]) -- (more luck: bigger everything)
			bounce(luckLabel, 1.25 + h * 0.3)
			groundRing(sc.folder, spot, Color3.fromRGB(150, 255, 120), eggH() * 2.6)
			burst(sc.sparks, spot + up * eggH() * 0.6, Color3.fromRGB(255, 225, 90), 6 + math.floor(h * 10))
			sfx("Pop", 0.55 + h * 0.3, 0.95 + h * 0.25)
			sfx("Note", 0.35 + h * 0.25, notePitch(i))
			if riser then
				riser.PlaybackSpeed = 0.8 + (i / #values) * 0.5
				riser.Volume = (0.12 + (i / #values) * 0.3) * 2 * (player:GetAttribute("SfxVolume") or 0.5)
			end
			task.delay(0.06, function()
				sfx(if i % 2 == 0 then "Bling1" else "Bling2", 0.3 + h * 0.3, 1 + h * 0.25)
			end)
		end
		if a >= 1 then
			break
		end
		task.wait()
	end
	scale = eggScaleFor(luck)
	egg:ScaleTo(scale)
	aim()
	luckLabel.Text = luckText(luck, true)
	if luck > 1 then
		bounce(luckLabel, 1.7)
		sfx("BigBling", 0.8, 1)
		groundRing(sc.folder, spot, Color3.fromRGB(255, 230, 120), eggH() * 3.2)
	end
	if riser then
		riser:Destroy()
	end
	-- (no hold here: the growth runs straight into the swell before the explosion, user 2026-11-22 "no stop at all")
	task.wait(if sc.skip then 0.1 else 0)

	-- 3. BOOM: the egg EXPLODES (user 2026-11-21: it used to fly off in big pieces and "looked like it is being
	-- thrown"). First it trembles harder and swells, then it blows apart into lots of little shell bits flying out
	-- in every direction from its middle, with a white blast ball, a shock ring and a camera shake.
	if not sc.skip then
		local s0 = scale
		local tP = os.clock()
		ChaseFx.play("Thud", 0.5, 0.7)
		while os.clock() - tP < 0.6 and not sc.skip do
			local a = (os.clock() - tP) / 0.6
			wobble = 0.03 + a * 0.12
			scale = s0 * (1 + a * a * 0.22)
			egg:ScaleTo(scale)
			task.wait()
		end
	end
	liveConn:Disconnect()
	wobble = 0
	placeEgg(0)
	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 20
	flash.Parent = screen
	tween(flash, 0.5, { BackgroundTransparency = 1 })
	task.delay(0.55, function()
		flash:Destroy()
	end)
	sfx("Crack", 0.9, 1.25)
	ChaseFx.play("Impact", 0.7, 0.95)
	local h = eggH()
	local pivot = egg:GetPivot()
	local middle = pivot * CFrame.new(0, h * 0.5, 0)
	-- the shell's colours (the egg's own bricks), then the egg itself is gone at once
	local colors: { Color3 } = {}
	for _, p in eggParts do
		if p.Transparency < 1 then
			table.insert(colors, p.Color)
		end
	end
	if #colors == 0 then
		colors = { Color3.new(1, 1, 1) }
	end
	egg:Destroy()
	sc.shakeUntil = os.clock() + 0.45
	sc.shakeAmp = 2.2
	-- the blast ball
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 250, 225)
	ball.Size = Vector3.one * h * 0.6
	ball.CFrame = middle
	ball.Parent = sc.folder
	tween(ball, 0.35, { Size = Vector3.one * h * 2.4, Transparency = 1 })
	task.delay(0.4, function()
		ball:Destroy()
	end)
	-- the shell bits: small blocks from all over the egg, flying straight out from its middle
	local bits: { BasePart } = {}
	local bitFrom: { Vector3 } = {}
	local bitVel: { Vector3 } = {}
	local bitSpin: { Vector3 } = {}
	local count = 46
	for i = 1, count do
		local dir = rng:NextUnitVector()
		dir = Vector3.new(dir.X, dir.Y * 0.8 + 0.15, dir.Z).Unit
		local b = Instance.new("Part")
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		local s = h * rng:NextNumber(0.07, 0.15)
		b.Size = Vector3.new(s, s * rng:NextNumber(0.4, 1), s)
		b.Color = colors[(i - 1) % #colors + 1]
		local from = middle.Position + dir * h * 0.35
		b.CFrame = CFrame.new(from)
		b.Parent = sc.folder
		table.insert(bits, b)
		table.insert(bitFrom, from)
		table.insert(bitVel, dir * h * rng:NextNumber(2.2, 3.6))
		table.insert(bitSpin, Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12)))
	end
	for _, p in bits do
		MapStyle.apply(p)
	end
	burst(sc.sparks, middle.Position, Color3.new(1, 1, 1), 40)
	groundRing(sc.folder, spot, Color3.new(1, 1, 1), h * 4.5)
	task.delay(0.08, groundRing, sc.folder, spot, Color3.fromRGB(255, 230, 140), h * 3)
	task.spawn(function()
		local tF = os.clock()
		local life = 0.9
		local cfs = table.create(#bits)
		while os.clock() - tF < life do
			local t = os.clock() - tF
			local a = t / life
			-- (fast out, slowing down, then dropping a little)
			local reach = 1 - (1 - math.min(t / 0.5, 1)) ^ 2
			for i, from in bitFrom do
				local spin = bitSpin[i] * t
				cfs[i] = CFrame.new(from + bitVel[i] * reach * 0.55 - up * h * 0.9 * a * a)
					* CFrame.Angles(spin.X, spin.Y, spin.Z)
			end
			Workspace:BulkMoveTo(bits, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			local fade = math.clamp((a - 0.55) / 0.45, 0, 1)
			for _, p in bits do
				p.LocalTransparencyModifier = fade
			end
			task.wait()
		end
		for _, p in bits do
			p:Destroy()
		end
	end)

	-- the animal, standing above the nest as a bright white silhouette: no colours or details yet, so you can't tell
	-- what it is, just something big to watch (user 2026-11-21)
	local size = h * (0.75 + math.max(0, rarity - 3) * 0.08)
	local model = AnimalFactory.create(id, size, size * 1.8)
	partsOf(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local white = Instance.new("Highlight")
	white.Name = "Silhouette"
	white.FillColor = Color3.new(1, 1, 1)
	white.FillTransparency = 0
	white.OutlineColor = Color3.new(1, 1, 1)
	white.OutlineTransparency = 0
	white.DepthMode = Enum.HighlightDepthMode.Occluded
	white.Parent = model
	local full = model:GetScale()
	model:ScaleTo(full * 0.15)
	local camPos = sc.camWant.Position
	local base = spot + up * (nestR * 0.25)
	-- (facing the camera: unturned, an animal faces -Z, and lookAt points -Z at the target)
	local animalCF = CFrame.lookAt(base, Vector3.new(camPos.X, base.Y, camPos.Z))
	model:PivotTo(animalCF)
	model.Parent = sc.folder
	local tG = os.clock()
	while os.clock() - tG < 0.5 do
		local a = (os.clock() - tG) / 0.5
		local e = TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		model:ScaleTo(full * (0.15 + 0.85 * e))
		model:PivotTo(animalCF * CFrame.new(0, math.sin(a * math.pi) * h * 0.2, 0))
		task.wait()
	end
	model:ScaleTo(full)
	model:PivotTo(animalCF)
	-- the camera moves in a little, still from behind you (the animal faces you and the camera)
	do
		local mid = spot + up * (h * 0.45)
		local stand = sc.root.Position
		local right = sc.forward:Cross(up).Unit
		local pos = stand - sc.forward * (8 + h * 0.75) + up * (4 + h * 0.4) + right * (4 + h * 0.3)
		sc.camWant = CFrame.lookAt(pos, mid)
	end

	-- 4. the odds climb while the silhouette shakes: the longer it climbs, the rarer it is
	local n = math.max(1, math.floor(100 / math.max(chance, 0.0001) + 0.5))
	local odds = screen:FindFirstChild("Odds") :: TextLabel
	-- (user 2026-11-21: no build-up for the common odds 1/1 .. 1/4, they just show; from 1/5 up the count starts at
	-- 1/5 and the wind-up is LONGER, so kids can follow it and look forward to the reveal: ~3 s for 1/6, ~5 s for
	-- 1/60, up to 8 s)
	local START = 5
	local first = math.min(n, START)
	odds.Visible = true
	odds.Text = "1/" .. Util.commas(first)
	odds.TextColor3 = oddsColor(first)
	bounce(odds, 1.5)
	local climb = if n < START then 0.6 else math.clamp(2.6 + 0.6 * math.log(n / 4, 2), 2.6, 8)
	if sc.skip then
		climb = 0.5
	end
	local tC = os.clock()
	local lastShown, lastTick, creak = first, 0, 0
	while true do
		local a = math.clamp((os.clock() - tC) / climb, 0, 1)
		local v = if a >= 1 or n < START then n else math.max(START, math.floor(START * (n / START) ^ (a ^ 1.15)))
		if v ~= lastShown then
			lastShown = v
			odds.Text = "1/" .. Util.commas(v)
			odds.TextColor3 = oddsColor(v)
			if os.clock() - lastTick > 0.07 then
				lastTick = os.clock()
				sfx("Note", 0.22, notePitch(1 + math.floor(a * 14)))
				bounce(odds, 1.12)
			end
		end
		local w = 0.02 + a * 0.08
		local tt = os.clock()
		model:PivotTo(animalCF * CFrame.Angles(math.sin(tt * 23) * w, math.sin(tt * 9) * w, math.cos(tt * 19) * w))
		if os.clock() - creak > 0.5 - a * 0.3 then
			creak = os.clock()
			ChaseFx.play("Thud", 0.25 + a * 0.4, 0.8 + a * 0.6)
			burst(sc.sparks, base + up * h * 0.5, Color3.new(1, 1, 1), 2)
		end
		if a >= 1 then
			break
		end
		task.wait()
	end
	model:PivotTo(animalCF)
	bounce(odds, 1.6)
	task.wait(if sc.skip or n < START then 0.25 else 0.6) -- (a held breath before the reveal)
	-- the reveal: one flash and its colours come in
	local reveal = Instance.new("Frame")
	reveal.BackgroundColor3 = Color3.new(1, 1, 1)
	reveal.Size = UDim2.fromScale(1, 1)
	reveal.ZIndex = 20
	reveal.Parent = screen
	tween(reveal, 0.6, { BackgroundTransparency = 1 })
	task.delay(0.65, function()
		reveal:Destroy()
	end)
	sfx("Prize", 0.8, 1)
	ChaseFx.play("Impact", 0.6, 1.05)
	burst(sc.sparks, base + up * h * 0.5, rcolor:Lerp(Color3.new(1, 1, 1), 0.4), 30)
	groundRing(sc.folder, spot, rcolor, h * 4)
	tween(white, 0.35, { FillTransparency = 1, OutlineTransparency = 1 })
	task.delay(0.4, function()
		white:Destroy()
	end)

	-- 5. how lucky: the glow and the words
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.CanTouch = false
	fx.Transparency = 1
	fx.Size = Vector3.one
	fx.CFrame = CFrame.new(spot + up * (h * 0.5))
	fx.Parent = sc.folder
	if rarity >= 3 then
		local e = Instance.new("ParticleEmitter")
		e.Texture = SPARK
		e.LightEmission = 1
		e.Color = ColorSequence.new(rcolor:Lerp(Color3.new(1, 1, 1), 0.3))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, h * 0.08), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(h * 0.4, h * 0.9)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 10 + rarity * 6
		e.Parent = fx
		local light = Instance.new("PointLight")
		light.Color = rcolor
		light.Range = h * 2
		light.Brightness = 1 + rarity * 0.4
		light.Parent = fx
	end
	if rarity >= 4 then
		local hl = Instance.new("Highlight")
		hl.FillColor = rcolor
		hl.FillTransparency = 0.75
		hl.OutlineColor = rcolor:Lerp(Color3.new(1, 1, 1), 0.5)
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
	end
	local beams: { BasePart } = {}
	if rarity >= 5 then
		-- light beams turning behind it
		for i = 1, 10 do
			local b = Instance.new("Part")
			b.Anchored = true
			b.CanCollide = false
			b.CanQuery = false
			b.CanTouch = false
			b.CastShadow = false
			b.Material = Enum.Material.Neon
			b.Color = rcolor:Lerp(Color3.new(1, 1, 1), 0.35)
			b.Transparency = 0.55
			b.Size = Vector3.new(h * 0.12, h * 3.2, 0.2)
			b:SetAttribute("Angle", i / 10 * math.pi * 2)
			b.Parent = sc.folder
			table.insert(beams, b)
		end
	end
	local beamConn = RunService.RenderStepped:Connect(function()
		if #beams == 0 then
			return
		end
		local back = CFrame.lookAt(spot + up * (h * 0.55), sc.camWant.Position) * CFrame.new(0, 0, h * 0.6)
		local tt = os.clock()
		for _, b in beams do
			local ang = (b:GetAttribute("Angle") :: number) + tt * 0.5
			b.CFrame = back * CFrame.Angles(0, 0, ang) * CFrame.new(0, h * 1.6, 0)
		end
	end)

	-- (the top of the screen is the reveal's now: the luck and the odds make room)
	luckLabel.Visible = false
	odds.Visible = false
	local lucky = LUCKY[rarity]
	local luckyLabel = screen:FindFirstChild("Lucky") :: TextLabel
	if lucky then
		luckyLabel.Text = lucky
		luckyLabel.Visible = true
		local g = luckyLabel:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(Color3.new(1, 1, 1), rcolor)
		end
		bounce(luckyLabel, 0.2)
		task.spawn(function()
			local tL = os.clock()
			while luckyLabel.Visible and luckyLabel.Parent do
				luckyLabel.Rotation = math.sin((os.clock() - tL) * 6) * 4
				task.wait()
			end
		end)
	end
	if rarity >= 4 then
		sfx("Win", 0.7, 1)
		task.delay(0.2, function()
			ChaseFx.play("Confetti", 1, 1.1)
		end)
	else
		sfx("LifeUp", 0.7, 1)
	end
	-- the card
	local card = screen:FindFirstChild("Card") :: Frame
	card.Visible = true
	local nameLabel = card:FindFirstChild("Name") :: TextLabel
	nameLabel.Text = animal.Name .. (if isNew then "  NEW!" else "")
	local rl = card:FindFirstChild("Rarity") :: TextLabel
	rl.Text = string.upper(Config.Rarities[rarity].Name)
	rl.TextColor3 = rcolor
	local chanceLabel = card:FindFirstChild("Chance") :: TextLabel
	chanceLabel.Text = "1 in " .. Util.commas(n)
	local incomeLabel = card:FindFirstChild("Income") :: TextLabel
	incomeLabel.Text = "$" .. Util.commas(animal.Income) .. "/s"
	bounce(card, 0.3)

	-- the hold (tap to go on)
	sc.skip = false
	local hold = 2.4 + math.max(0, rarity - 3) * 0.5
	if RunService:IsStudio() and player:GetAttribute("TestHatchHold") then
		hold = player:GetAttribute("TestHatchHold") -- (Studio test hook: hold the reveal for a screenshot)
	end
	local tH = os.clock()
	while os.clock() - tH < hold and not sc.skip do
		task.wait()
	end
	sc.skip = false
	-- off it goes to your backpack
	luckyLabel.Visible = false
	card.Visible = false
	odds.Visible = false
	beamConn:Disconnect()
	local tS = os.clock()
	while os.clock() - tS < 0.3 do
		local a = (os.clock() - tS) / 0.3
		model:ScaleTo(full * math.max(0.05, 1 - a))
		task.wait()
	end
	burst(sc.sparks, spot + up * (h * 0.4), Color3.fromRGB(255, 240, 160), 14)
	ChaseFx.play("Pop", 0.6, 1.2)
	model:Destroy()
	egg:Destroy()
	fx:Destroy()
	for _, b in beams do
		b:Destroy()
	end
end

local function buildScreen(): Frame
	local screen = Instance.new("Frame")
	screen.Name = "Hatch" -- (Client/Tutorial waits for SAFD_Hatch.Hatch)
	screen.BackgroundTransparency = 1
	screen.Size = UDim2.fromScale(1, 1)
	screen.Parent = gui
	-- letterbox bars
	for _, isTop in { true, false } do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(1, 0.08)
		bar.Position = if isTop then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 0.92)
		bar.Parent = screen
	end
	local luck = label(screen, {
		Name = "Luck",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.5, 0.11),
		Visible = false,
	}, 5)
	local lg = Instance.new("UIGradient")
	lg.Rotation = 90
	lg.Color = ColorSequence.new(Color3.fromRGB(170, 255, 120), Color3.fromRGB(60, 220, 80))
	lg.Parent = luck
	label(screen, {
		Name = "Odds",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.22),
		Size = UDim2.fromScale(0.3, 0.09),
		Visible = false,
	}, 4)
	local lucky = label(screen, {
		Name = "Lucky",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromScale(0.7, 0.13),
		Visible = false,
	}, 6)
	local lk = Instance.new("UIGradient")
	lk.Rotation = 90
	lk.Parent = lucky
	label(screen, {
		Name = "Counter",
		Position = UDim2.fromScale(0.02, 0.1),
		Size = UDim2.fromScale(0.2, 0.05),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, 3)
	label(screen, {
		Name = "Tap",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.91),
		Size = UDim2.fromScale(0.3, 0.035),
		Text = "Tap to skip",
		TextColor3 = Color3.fromRGB(220, 220, 230),
		TextTransparency = 0.3,
	}, 2)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.fromScale(0.5, 0.86)
	card.Size = UDim2.fromScale(0.5, 0.2)
	card.BackgroundTransparency = 1
	card.Visible = false
	card.Parent = screen
	label(card, { Name = "Name", Size = UDim2.fromScale(1, 0.4) }, 5)
	label(card, { Name = "Rarity", Position = UDim2.fromScale(0, 0.4), Size = UDim2.fromScale(1, 0.25) }, 4)
	label(card, {
		Name = "Chance",
		Position = UDim2.fromScale(0, 0.66),
		Size = UDim2.fromScale(0.5, 0.3),
		TextColor3 = Color3.fromRGB(255, 225, 90),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, 4)
	label(card, {
		Name = "Income",
		Position = UDim2.fromScale(0.55, 0.66),
		Size = UDim2.fromScale(0.45, 0.3),
		TextColor3 = Color3.fromRGB(140, 255, 110),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 4)
	return screen
end

local function run(info: any)
	if type(info.Animals) ~= "table" or #info.Animals == 0 then
		return
	end
	-- (the run's own screens and camera are put away first)
	local tW = os.clock()
	while Workspace:FindFirstChild("LocalDisaster") and os.clock() - tW < 3 do
		task.wait()
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	player:SetAttribute("SAFD_Cutscene", true)
	local restoreUi = ChaseFx.hideUi({ "SAFD_Hatch" })
	-- you stop, facing the biomes (user 2026-11-22: the shot looks from the bases out over the valley); the egg lands
	-- in front of you
	local toB = MapInfo.toBase()
	local forward = -Vector3.new(toB.X, 0, toB.Z).Unit
	local wasLocked = Movement.locked
	Movement.locked = true
	humanoid.WalkSpeed = 0
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)
	root.Anchored = true

	local folder = Instance.new("Folder")
	folder.Name = "SAFD_HatchScene"
	folder.Parent = Workspace

	-- The cutscene is staged in the middle, just past the white line (user 2026-11-21), wherever you crossed it: a
	-- stand-in copy of you stands there and your own character (hidden on your screen) stays where it stopped, so you
	-- carry on from there afterwards. Nobody is teleported.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = { character, folder }
	local function groundAt(p: Vector3): Vector3?
		local hit = Workspace:Raycast(p + Vector3.new(0, 25, 0), Vector3.new(0, -70, 0), params)
		return hit and hit.Position
	end
	local hipHeight = root.Position.Y - (groundAt(root.Position) or (root.Position - Vector3.new(0, 3, 0))).Y
	local line = MapInfo.dangerLine()
	-- (on the safe side, 30 studs back from the white line: the egg in front of you is still this side of it)
	local stageFlat = Vector3.new(-8, root.Position.Y, line.Z) - forward * 30
	local stageGround = groundAt(stageFlat) or (stageFlat - Vector3.new(0, hipHeight, 0))
	local standRoot: BasePart = root
	local hiddenParts: { [Instance]: number } = {}
	local wasArchivable = character.Archivable
	character.Archivable = true
	local okClone, double = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if okClone and double then
		for _, d in double:GetDescendants() do
			if d:IsA("BaseScript") or d:IsA("Sound") or (d:IsA("Model") and string.find(d.Name, "^CarriedEgg")) then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		local dh = double:FindFirstChildOfClass("Humanoid")
		if dh then
			dh.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			-- (no animations on the copy)
			local animator = dh:FindFirstChildOfClass("Animator")
			if animator then
				animator:Destroy()
			end
		end
		-- standing straight (user 2026-11-22: the copy kept the running pose it was cloned in): rebuild every limb from
		-- the root out along the joints with no animation offset, the plain rest pose
		local doubleRoot = double:FindFirstChild("HumanoidRootPart") :: BasePart?
		if doubleRoot then
			-- (the root stands upright first)
			local cf0 = doubleRoot.CFrame
			local look = Vector3.new(cf0.LookVector.X, 0, cf0.LookVector.Z)
			if look.Magnitude > 0.01 then
				doubleRoot.CFrame = CFrame.lookAt(cf0.Position, cf0.Position + look)
			end
			-- joints and accessory welds: Part0.CFrame * C0 == Part1.CFrame * C1
			local joints: { any } = {}
			for _, d in double:GetDescendants() do
				if (d:IsA("Motor6D") or d:IsA("Weld")) and (d :: any).Part0 and (d :: any).Part1 then
					table.insert(joints, d)
				end
			end
			local placed: { [BasePart]: boolean } = { [doubleRoot] = true }
			local progress = true
			while progress do
				progress = false
				for _, j in joints do
					local p0, p1 = j.Part0 :: BasePart, j.Part1 :: BasePart
					if placed[p0] and not placed[p1] then
						p1.CFrame = p0.CFrame * j.C0 * j.C1:Inverse()
						placed[p1] = true
						progress = true
					elseif placed[p1] and not placed[p0] then
						p0.CFrame = p1.CFrame * j.C1 * j.C0:Inverse()
						placed[p0] = true
						progress = true
					end
				end
			end
		end
		local stagePos = stageGround + Vector3.new(0, hipHeight, 0)
		double:PivotTo(CFrame.lookAt(stagePos, stagePos + forward))
		double.Parent = folder
		standRoot = (double:FindFirstChild("HumanoidRootPart") :: BasePart?) or root
		-- your real self, hidden on your screen for the cutscene
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				hiddenParts[d] = (d :: any).LocalTransparencyModifier;
				(d :: any).LocalTransparencyModifier = 1
			end
		end
	end
	local showOthers = hideOthers(stageGround)
	local maxH = (5 + 6 * 0.8) * 2.6
	local ahead = 8 + maxH * 0.4
	local probe = standRoot.Position + forward * ahead
	local spot = groundAt(probe) or (probe - Vector3.new(0, 3, 0))

	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(spot)
	holder.Parent = folder
	local at = Instance.new("Attachment")
	at.Parent = holder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.5, 1.1)
	sparks.Speed = NumberRange.new(10, 26)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -18, 0)
	sparks.Rate = 0
	sparks.Parent = at

	local cam = Workspace.CurrentCamera
	local oldFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 50
	local screen = buildScreen()
	local sc: Scene = {
		folder = folder,
		screen = screen,
		root = standRoot,
		forward = forward,
		spot = spot,
		camWant = cam.CFrame,
		sparks = sparks,
		skip = false,
		shakeUntil = 0,
		shakeAmp = 0,
	}
	local smooth = cam.CFrame
	local camConn = RunService.RenderStepped:Connect(function(dt)
		cam.CameraType = Enum.CameraType.Scriptable
		smooth = smooth:Lerp(sc.camWant, math.clamp(dt * 5, 0, 1))
		-- (the egg exploding shakes the camera for a moment)
		local left = sc.shakeUntil - os.clock()
		if left > 0 then
			local amp = math.rad(sc.shakeAmp) * left / 0.45
			local t = os.clock() * 40
			cam.CFrame = smooth
				* CFrame.Angles(math.sin(t) * amp, math.cos(t * 1.3) * amp, math.sin(t * 0.7) * amp * 0.5)
		else
			cam.CFrame = smooth
		end
	end)
	local tapConn = UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.Touch
			or (t == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space)
		then
			sc.skip = true
		end
	end)
	local ok, err = pcall(function()
		for k = 1, #info.Animals do
			hatchOne(sc, k, #info.Animals, info)
		end
	end)
	if not ok then
		warn("[Hatch]", err)
	end
	camConn:Disconnect()
	tapConn:Disconnect()
	folder:Destroy()
	screen:Destroy()
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = oldFov
	cam.CameraSubject = humanoid
	for d, v in hiddenParts do
		if d.Parent then
			(d :: any).LocalTransparencyModifier = v
		end
	end
	root.Anchored = false
	Movement.locked = wasLocked
	showOthers()
	restoreUi()
	player:SetAttribute("SAFD_Cutscene", nil)
	local HUD = require(script.Parent.HUD)
	HUD.toast(
		if #info.Animals == 1
			then "Saved to your backpack! 🎒"
			else `{#info.Animals} animals saved to your backpack! 🎒`,
		Color3.fromRGB(140, 255, 110),
		3
	)
end

local function pump()
	if busy then
		return
	end
	busy = true
	while #queue > 0 do
		local info = table.remove(queue, 1)
		local ok, err = pcall(run, info)
		if not ok then
			warn("[Hatch]", err)
			player:SetAttribute("SAFD_Cutscene", nil)
		end
	end
	busy = false
end

-- (the admin panel / tests can preview it)
function Hatch.show(info: any)
	table.insert(queue, info)
	task.spawn(pump)
end

function Hatch.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_Hatch"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Parent = player:WaitForChild("PlayerGui")
	-- the hatch's sounds, loaded now so they play the instant they're needed
	local holder = Instance.new("Folder")
	holder.Name = "SAFD_HatchSounds"
	holder.Parent = game:GetService("SoundService")
	local list = {}
	for name, id in SOUNDS do
		local snd = Instance.new("Sound")
		snd.Name = name
		snd.SoundId = id
		snd.Parent = holder
		soundBank[name] = snd
		table.insert(list, snd)
	end
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end)
	Net.event("RunReward").OnClientEvent:Connect(function(info)
		if type(info) == "table" then
			Hatch.show(info)
		end
	end)
end

return Hatch
