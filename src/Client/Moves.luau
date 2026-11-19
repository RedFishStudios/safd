-- Double jump (press jump again in the air: a full forward somersault) and slide (hold Ctrl / the mobile button:
-- a low feet-first slide for as long as it's held, with a short speed burst at the start; let go and you're back
-- up running). Animations play on the character's Animator, so other players see them; the effects (air ring,
-- dust, wind) are in Client/MoveFx.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HUD = require(script.Parent.HUD)
local Movement = require(script.Parent.Movement)

local player = Players.LocalPlayer

local Moves = {}

local SLIDE_ACTION = "SAFD_Slide"

type Rig = {
	humanoid: Humanoid,
	root: BasePart,
	doubleJump: AnimationTrack?,
	slide: AnimationTrack?,
	canDouble: boolean,
	usedDouble: boolean,
	sliding: boolean,
	held: boolean,
	airTime: number,
	lastSlide: number,
}

local rig: Rig? = nil

local function load(humanoid: Humanoid, id: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if not animator or id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok then
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

-- true while sliding (hazards that fly at head height pass over you)
function Moves.isBusy(): boolean
	return rig ~= nil and rig.sliding
end

local function stopSlide(r: Rig)
	if not r.sliding then
		return
	end
	r.sliding = false
	r.lastSlide = os.clock()
	if r.slide then
		r.slide:Stop(0.2) -- torso lifts, legs come back under the body, straight back into running
	end
end

local function startSlide(r: Rig)
	if r.sliding or Movement.locked or os.clock() - r.lastSlide < Config.SlideCooldown then
		return
	end
	if r.humanoid.FloorMaterial == Enum.Material.Air or r.humanoid.Health <= 0 then
		return
	end
	r.sliding = true
	r.airTime = 0
	Movement.boost(Config.SlideBoost, Config.SlideBoostTime)
	if r.slide then
		r.slide:Play(0.1) -- hips drop quickly into the slide
	end
end

local function doubleJump(r: Rig)
	if r.usedDouble or not r.canDouble or Movement.locked then
		return
	end
	local state = r.humanoid:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return
	end
	r.usedDouble = true
	local v = r.root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	-- A small forward push on top of the vertical kick makes the flip feel like it carries you.
	local push = if flat.Magnitude > 1 then flat.Unit * 8 else Vector3.zero
	r.root.AssemblyLinearVelocity = Vector3.new(v.X, Config.DoubleJumpPower, v.Z) + push
	r.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	if r.doubleJump then
		r.doubleJump:Play(0.05)
	end
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local r: Rig = {
		humanoid = humanoid,
		root = root,
		doubleJump = load(humanoid, Config.DoubleJumpAnimation, Enum.AnimationPriority.Action2, false),
		slide = load(humanoid, Config.SlideAnimation, Enum.AnimationPriority.Action2, true),
		canDouble = false,
		usedDouble = false,
		sliding = false,
		held = false,
		airTime = 0,
		lastSlide = 0,
	}
	rig = r
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			r.canDouble = false
			r.usedDouble = false
			-- still holding Ctrl when you land: slide straight on
			if r.held then
				startSlide(r)
			end
		elseif new == Enum.HumanoidStateType.Freefall then
			-- Allow the second jump once airborne (also when walking off a ledge).
			task.delay(0.08, function()
				if rig == r then
					r.canDouble = true
				end
			end)
		end
	end)
	humanoid.Died:Connect(function()
		stopSlide(r)
	end)
end

function Moves.init()
	-- fetch the move animations up front, so the first slide / double jump starts the instant you press
	task.spawn(function()
		local list = {}
		for _, id in
			{
				Config.SlideAnimation,
				Config.DoubleJumpAnimation,
				Config.JumpAnimation,
				Config.FallAnimation,
				Config.RunAnimation,
			}
		do
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			table.insert(list, anim)
		end
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	UserInputService.JumpRequest:Connect(function()
		local r = rig
		if r and r.humanoid.Health > 0 then
			if r.sliding then
				stopSlide(r) -- jumping out of a slide
			end
			doubleJump(r)
		end
	end)

	-- End the slide if you leave the ground for more than a moment or get locked (treadmill).
	RunService.Heartbeat:Connect(function(dt)
		local r = rig
		if not r or not r.sliding then
			return
		end
		if r.humanoid.FloorMaterial == Enum.Material.Air then
			r.airTime += dt
		else
			r.airTime = 0
		end
		if r.airTime > 0.3 or Movement.locked or not r.held then
			stopSlide(r)
		end
	end)

	-- Ctrl (or C). In a Studio playtest, Studio itself also reads Ctrl + W/A/S/D as its own shortcuts before the game
	-- sees them: Ctrl+A selects everything in the place (Studio freezes for seconds on a map this size), Ctrl+S saves,
	-- Ctrl+D duplicates the selection (a clone of your character if it's selected). Studio's log shows Select All firing
	-- in the playtests where the slide "hung" (2026-11-19). Nothing in the game can block those, and the published game
	-- has no such shortcuts, so there Ctrl is fine. In Studio a toast says to use C.
	local studio = RunService:IsStudio()
	local lastStudioHint = -math.huge
	local SLIDE_KEYS = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB }
	ContextActionService:BindAction(SLIDE_ACTION, function(_, inputState, input: InputObject)
		if
			studio
			and inputState == Enum.UserInputState.Begin
			and (input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl)
			and os.clock() - lastStudioHint > 30
		then
			lastStudioHint = os.clock()
			HUD.toast(
				"Studio playtest: slide with C. Ctrl + W/A/S/D runs Studio's shortcuts (Select All, Save, Duplicate) and freezes Studio. Ctrl works normally in the published game.",
				Color3.fromRGB(255, 210, 90),
				8
			)
		end
		local r = rig
		if not r then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			r.held = true
			startSlide(r)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			r.held = false
			stopSlide(r)
		end
		return Enum.ContextActionResult.Pass
	end, true, table.unpack(SLIDE_KEYS))
	ContextActionService:SetTitle(SLIDE_ACTION, "Slide")
	ContextActionService:SetPosition(SLIDE_ACTION, UDim2.new(1, -170, 1, -130))
end

return Moves
