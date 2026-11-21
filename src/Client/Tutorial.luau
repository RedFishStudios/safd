-- The new-player tutorial (2026-11-20; restyled 2026-11-21 as a copy of Throw Food for Animals' tutorial): plays once
-- after the opening cutscene (data.SeenTutorial, Server/Main) and again from the Help window (Client/Help) or /tutorial.
-- One short line of white text with a black outline near the top of the screen says what to do; no box, no buttons.
-- Where to go: a yellow ▼ bobbing over the target and a yellow ring on the ground under it ("step on the circle");
-- for buttons on the screen, a yellow ▼ bobbing just above the button. Each step waits for the player to do it;
-- steps that only tell you something move on by themselves after a few seconds.
--   welcome -> your base -> run on the treadmill -> past the white line -> jump / double jump / slide -> grab an egg ->
--   run home (caught: try again) -> it hatched -> Animals -> EQUIP -> money -> trail shop -> treadmill upgrade -> plot
--   upgrade -> the ? Help button (tutorial again + controls) -> "You're all set! Now go save some eggs!"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapInfo = require(Shared.MapInfo)
local Net = require(Shared.Net)

local AnimalsPanel = require(script.Parent.AnimalsPanel)
local Bases = require(script.Parent.Bases)
local ChaseFx = require(script.Parent.ChaseFx)
local Help = require(script.Parent.Help)
local Moves = require(script.Parent.Moves)

local player = Players.LocalPlayer

local Tutorial = {}

local YELLOW = Color3.fromRGB(255, 215, 40)
local DARK = Color3.fromRGB(12, 12, 16)
local running = false
local stopFlag = false

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- the line of text and the screen arrow ---------------------------------------------------------------------------

type Screen = { gui: ScreenGui, line: TextLabel, pop: UIScale, pointer: TextLabel }

local function buildScreen(): Screen
	local gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_Tutorial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 55
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.BackgroundTransparency = 1
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.fromScale(0.5, 0.33) -- (under the run prompts, which sit at y 0.23-0.31, and the biome banner)
	line.Size = UDim2.fromScale(0.7, 0.07)
	line.Font = Enum.Font.FredokaOne
	line.TextScaled = true
	line.TextColor3 = Color3.new(1, 1, 1)
	line.Text = ""
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = DARK
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.Parent = line
	local pop = Instance.new("UIScale")
	pop.Parent = line
	line.Parent = gui
	local pointer = Instance.new("TextLabel")
	pointer.Name = "Pointer"
	pointer.BackgroundTransparency = 1
	pointer.AnchorPoint = Vector2.new(0.5, 1)
	pointer.Size = UDim2.fromScale(0.05, 0.05)
	pointer.SizeConstraint = Enum.SizeConstraint.RelativeYY
	pointer.Font = Enum.Font.GothamBlack
	pointer.TextScaled = true
	pointer.Text = "▼"
	pointer.TextColor3 = YELLOW
	pointer.Visible = false
	pointer.ZIndex = 10
	local ps = Instance.new("UIStroke")
	ps.Thickness = 3
	ps.Color = DARK
	ps.Parent = pointer
	pointer.Parent = gui
	-- a small Skip button under the line (user 2026-11-21: "allow for option to skip the tutorial")
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AutoButtonColor = true
	skip.AnchorPoint = Vector2.new(0.5, 0)
	skip.Position = UDim2.fromScale(0.5, 0.41)
	skip.Size = UDim2.fromScale(0.2, 0.045)
	skip.SizeConstraint = Enum.SizeConstraint.RelativeYY
	skip.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	skip.BackgroundTransparency = 0.35
	skip.Font = Enum.Font.FredokaOne
	skip.TextScaled = true
	skip.TextColor3 = Color3.fromRGB(230, 230, 240)
	skip.Text = "Skip tutorial"
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.5, 0)
	sc.Parent = skip
	local sp = Instance.new("UIPadding")
	sp.PaddingTop = UDim.new(0.18, 0)
	sp.PaddingBottom = UDim.new(0.18, 0)
	sp.Parent = skip
	skip.Activated:Connect(function()
		stopFlag = true
	end)
	skip.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, line = line, pop = pop, pointer = pointer }
end

-- the world marker: a yellow ▼ over the target and a ring on the ground ------------------------------------------

type Guide = { folder: Folder, marker: BasePart, ring: BasePart, ground: Vector3?, height: number }

local function buildGuide(): Guide
	local folder = Instance.new("Folder")
	folder.Name = "SAFD_TutorialGuide"
	folder.Parent = Workspace
	local marker = Instance.new("Part")
	marker.Name = "Marker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.one
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(5, 30, 5, 30) -- (studs plus a little: it stays readable far away)
	bb.AlwaysOnTop = false -- (on top, billboards never drew in this place)
	bb.LightInfluence = 0
	bb.MaxDistance = 3000
	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextScaled = true
	arrow.Text = "▼"
	arrow.TextColor3 = YELLOW
	local st = Instance.new("UIStroke")
	st.Thickness = 4
	st.Color = DARK
	st.Parent = arrow
	arrow.Parent = bb
	bb.Parent = marker
	-- the ring on the ground: two thin neon arcs would cost more; a flat yellow band round a see-through middle
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 1
	ring.Size = Vector3.new(9, 0.2, 9)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.CanvasSize = Vector2.new(200, 200)
	local circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromScale(0.9, 0.9)
	circle.BackgroundTransparency = 1
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(1, 0)
	cc.Parent = circle
	local cs = Instance.new("UIStroke")
	cs.Thickness = 14
	cs.Color = YELLOW
	cs.Parent = circle
	circle.Parent = gui
	gui.Parent = ring
	return { folder = folder, marker = marker, ring = ring, ground = nil, height = 4 }
end

-- point at a spot on the ground (`height`: how tall the thing standing there is; the ▼ floats over it)
local function guideTo(g: Guide, ground: Vector3?, height: number?)
	g.ground = ground
	g.height = height or 4
	if ground then
		g.marker.Parent = g.folder
		g.ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.15, 0))
		g.ring.Parent = g.folder
	else
		g.marker.Parent = nil
		g.ring.Parent = nil
	end
end

local function updateGuide(g: Guide, t: number)
	local ground = g.ground
	if not ground then
		return
	end
	g.marker.CFrame = CFrame.new(ground + Vector3.new(0, g.height + 4 + math.sin(t * 5) * 0.8, 0))
end

-- the ground spot under a thing in the world, and its height
local function spotOf(inst: Instance?): (Vector3?, number)
	if not inst then
		return nil, 4
	end
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position - Vector3.new(0, size.Y / 2, 0), size.Y
	elseif inst:IsA("BasePart") then
		return inst.Position - Vector3.new(0, inst.Size.Y / 2, 0), inst.Size.Y
	end
	return nil, 4
end

local function nearestEgg(): Model?
	local folder = Workspace:FindFirstChild("WildEggs")
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not folder or not hrp then
		return nil
	end
	local best, bd = nil, math.huge
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m.Name:find("Meadow") then
			local d = (m:GetPivot().Position - hrp.Position).Magnitude
			if d < bd then
				best, bd = m, d
			end
		end
	end
	return best
end

-- standing at (or right by) your own base?
local function atBase(): boolean
	local base = Bases.mine()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not base or not root then
		return false
	end
	local pen = base:FindFirstChild("Pen")
	local box = pen or base
	if not box:IsA("Model") then
		return false
	end
	local cf, size = box:GetBoundingBox()
	local rel = cf:PointToObjectSpace(root.Position)
	return math.abs(rel.X) < size.X / 2 + 30 and math.abs(rel.Z) < size.Z / 2 + 30
end

-- the steps -------------------------------------------------------------------------------------------------------

local function play()
	if running then
		return
	end
	running = true
	stopFlag = false
	local screen = buildScreen()
	local guide = buildGuide()
	local t = 0
	local pointAt: GuiObject? = nil
	local conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		updateGuide(guide, t)
		local target = pointAt
		if target and target.Parent and target.AbsoluteSize.X > 0 and target.Visible then
			-- (both ScreenGuis keep the top-bar inset, so their positions line up)
			local p = target.AbsolutePosition
			screen.pointer.Visible = true
			screen.pointer.Position = UDim2.fromOffset(p.X + target.AbsoluteSize.X / 2, p.Y - 4 + math.sin(t * 6) * 6)
		else
			screen.pointer.Visible = false
		end
	end)

	local function say(text: string)
		screen.line.Text = text
		screen.pop.Scale = 0.6
		TweenService:Create(screen.pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		ChaseFx.play("Pop", 0.7, 1.2)
	end
	local function hold(seconds: number)
		local t0 = os.clock()
		while not stopFlag and os.clock() - t0 < seconds do
			task.wait(0.1)
		end
	end
	local function waitFor(check: () -> boolean, timeout: number?): boolean
		local t0 = os.clock()
		while not stopFlag and not check() do
			if timeout and os.clock() - t0 > timeout then
				return false
			end
			task.wait(0.1)
		end
		if not stopFlag then
			ChaseFx.play("Good", 0.8, 1.3)
		end
		return true
	end

	local ok, err = pcall(function()
		local touch = isTouch()
		-- it starts at your base (user 2026-11-21): anywhere else, it first takes you there
		if not atBase() then
			local base = Bases.mine()
			local home = base and (base:FindFirstChild("Pen") or base)
			local spot = spotOf(home)
			guideTo(guide, spot, 3)
			say("Go to your base to start the tutorial")
			waitFor(atBase)
			guideTo(guide, nil)
			if stopFlag then
				return
			end
		end
		say("Welcome! Let's save some eggs!")
		hold(3)
		-- your base
		local base = Bases.mine()
		local pen = base and base:FindFirstChild("Pen")
		local penSpot = spotOf(pen or base)
		guideTo(guide, penSpot, 3)
		say("This is your base")
		hold(3)
		if stopFlag then
			return
		end
		-- the treadmill
		local tread, treadH = spotOf(base and base:FindFirstChild("Treadmill"))
		guideTo(guide, tread, treadH)
		say("Run on your treadmill")
		local trained = 0
		waitFor(function()
			if player:GetAttribute("Training") then
				trained += 0.1
			end
			return trained >= 3
		end)
		if stopFlag then
			return
		end
		guideTo(guide, nil)
		say(
			if touch
				then "You are getting faster! Jump to get off"
				else "You are getting faster! Press SPACE to get off"
		)
		waitFor(function()
			return not player:GetAttribute("Training")
		end, 8)
		if stopFlag then
			return
		end

		-- out past the white line
		local line = MapInfo.dangerLine()
		local toBase = MapInfo.toBase()
		local function pastLine(): boolean
			local c = player.Character
			local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			return r ~= nil and (r.Position - line):Dot(toBase) < -8
		end
		local practised = false
		local function practise()
			guideTo(guide, nil)
			local jumps, jumpedTwice = 0, false
			local c = player.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			local jumpsInAir = 0
			local jumpConn = h
				and h.StateChanged:Connect(function(_, new)
					if new == Enum.HumanoidStateType.Jumping then
						jumps += 1
						jumpsInAir += 1
						if jumpsInAir >= 2 then
							jumpedTwice = true
						end
					elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
						jumpsInAir = 0
					end
				end)
			say(if touch then "Tap the jump button to jump" else "Press SPACE to jump")
			waitFor(function()
				return jumps > 0
			end)
			if not stopFlag then
				say(if touch then "Tap jump again in the air to double jump" else "Press SPACE twice to double jump")
				waitFor(function()
					return jumpedTwice
				end)
			end
			if not stopFlag then
				say(if touch then "Hold the slide button to slide" else "Hold SHIFT to slide")
				waitFor(function()
					return Moves.isBusy()
				end)
			end
			if jumpConn then
				jumpConn:Disconnect()
			end
			practised = true
		end
		local function eggStep()
			local lineSpot = Vector3.new(-8, line.Y, line.Z) - toBase * 10
			guideTo(guide, lineSpot, 0.5)
			say("Go past the white line")
			waitFor(pastLine)
			if stopFlag then
				return
			end
			if not practised then
				practise()
				if stopFlag then
					return
				end
			end
			say(if touch then "Grab an egg: hold the button next to it" else "Grab an egg: hold E next to it")
			waitFor(function()
				local egg = nearestEgg()
				if egg then
					local spot, height = spotOf(egg)
					guideTo(guide, spot, height)
				end
				return (player:GetAttribute("Carrying") or 0) > 0
			end)
		end
		eggStep()
		if stopFlag then
			return
		end
		-- the run home (caught: try again)
		local hatched = false
		while not hatched and not stopFlag do
			guideTo(guide, Vector3.new(-8, line.Y, line.Z) + toBase * 6, 0.5)
			say("Run home before the disaster gets you!")
			local died = false
			waitFor(function()
				local c = player.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				if not h or h.Health <= 0 then
					died = true
					return true
				end
				return (player:GetAttribute("Carrying") or 0) == 0
			end)
			if stopFlag then
				return
			end
			if died then
				task.wait(4)
			end
			local hatchGui = player.PlayerGui:FindFirstChild("SAFD_Hatch")
			local sawHatch = waitFor(function()
				return hatchGui ~= nil and hatchGui:FindFirstChild("Hatch") ~= nil
			end, 3)
			if sawHatch and not died then
				hatched = true
			else
				guideTo(guide, nil)
				say("Oh no! Try again")
				hold(2)
				eggStep()
			end
		end
		if stopFlag then
			return
		end
		guideTo(guide, nil)
		screen.line.Visible = false
		local hatchGui = player.PlayerGui:FindFirstChild("SAFD_Hatch")
		waitFor(function()
			return not (hatchGui and hatchGui:FindFirstChild("Hatch"))
		end)
		screen.line.Visible = true
		-- the animal onto your plot
		pointAt = AnimalsPanel.button()
		say(if touch then "Tap the 🐾 Animals button" else "Click the 🐾 Animals button")
		waitFor(function()
			return AnimalsPanel.isOpen()
		end, 40)
		pointAt = nil
		if stopFlag then
			return
		end
		local placedBefore = player:GetAttribute("PlacedCount") or 0
		say(
			if touch then "Tap EQUIP to put your animal on your plot" else "Click EQUIP to put your animal on your plot"
		)
		waitFor(function()
			return (player:GetAttribute("PlacedCount") or 0) > placedBefore
		end, 60)
		AnimalsPanel.close()
		if stopFlag then
			return
		end
		guideTo(guide, penSpot, 3)
		say("Your animals make money every second")
		hold(3.5)
		-- spending
		local elements = Workspace:FindFirstChild("Spawn_elements")
		local shop, shopH = spotOf(elements and elements:FindFirstChild("Weight_stand"))
		guideTo(guide, shop, shopH)
		say("Buy trails here to train faster")
		hold(3.5)
		local tUp, tUpH = spotOf(base and base:FindFirstChild("TreadmillUpgrade"))
		guideTo(guide, tUp, tUpH)
		say("Upgrade your treadmill here")
		hold(3.5)
		local pUp, pUpH = spotOf(base and base:FindFirstChild("PlotUpgrade"))
		guideTo(guide, pUp, pUpH)
		say("Upgrade your plot here for more animals")
		hold(3.5)
		guideTo(guide, nil)
		if stopFlag then
			return
		end
		-- the Help button
		pointAt = Help.button()
		say(if touch then "Tap ? for help" else "Click ? for help")
		waitFor(function()
			return Help.isOpen()
		end, 40)
		pointAt = nil
		if stopFlag then
			return
		end
		say("Watch the tutorial again and see the controls here")
		hold(4)
		Help.close()
		say("You're all set! Now go save some eggs!")
		ChaseFx.play("Confetti", 1, 1.1)
		hold(3.5)
	end)
	if not ok then
		warn("[Tutorial]", err)
	end
	conn:Disconnect()
	screen.gui:Destroy()
	guide.folder:Destroy()
	Net.event("TutorialDone"):FireServer()
	running = false
end

function Tutorial.isRunning(): boolean
	return running
end

function Tutorial.start()
	task.spawn(function()
		-- after the loading screen and the opening cutscene
		local t0 = os.clock()
		while not player:GetAttribute("WorldReady") and os.clock() - t0 < 120 do
			task.wait(0.3)
		end
		task.wait(1.5)
		while player.PlayerGui:FindFirstChild("SAFD_Intro") do
			task.wait(0.3)
		end
		-- (your save is in, and not in the middle of a run or the hatch)
		while not player:GetAttribute("Loaded") or (player:GetAttribute("Carrying") or 0) > 0 do
			task.wait(0.3)
		end
		task.wait(0.5)
		play()
	end)
end

-- (the Help window's "watch the tutorial again": stops one that's running, then starts over)
function Tutorial.replay()
	if running then
		stopFlag = true
		while running do
			task.wait(0.1)
		end
	end
	task.spawn(play)
end

function Tutorial.init()
	if player:GetAttribute("PlayTutorial") == true then
		Tutorial.start()
	end
	player:GetAttributeChangedSignal("PlayTutorial"):Connect(function()
		if player:GetAttribute("PlayTutorial") == true then
			Tutorial.start()
		end
	end)
	Net.event("PlayTutorial").OnClientEvent:Connect(Tutorial.start)
	Help.onReplay = Tutorial.replay
end

return Tutorial
