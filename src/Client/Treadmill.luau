-- Treadmill training. Walking onto your own treadmill locks you onto the belt facing the biomes and plays the run
-- animation (legs faster on better treadmills, like the reference game). The server pays speed points every 0.25 s
-- while you stand on it (Server/TrainingService) and each payout pops "+N". Space (or the on-screen button) exits.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)

local Bases = require(script.Parent.Bases)
local HUD = require(script.Parent.HUD)
local Movement = require(script.Parent.Movement)

local player = Players.LocalPlayer

local Treadmill = {}

local ACTION = "SAFD_ExitTreadmill"
local FALLBACK_RUN = {
	[Enum.HumanoidRigType.R15] = "rbxassetid://913376220",
	[Enum.HumanoidRigType.R6] = "rbxassetid://180426354",
}

type Session = {
	root: Model,
	humanoid: Humanoid,
	hrp: BasePart,
	runnerCF: CFrame,
	track: AnimationTrack?,
	connections: { RBXScriptConnection },
	jumpPower: number,
	jumpHeight: number,
}

local session: Session? = nil

-- The UI pack swaps the HUD buttons for Speed Shop / 2x Speed while on the treadmill.
local function setSpeedMat(active: boolean)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local shop = gui and gui:FindFirstChild("Speed Shop")
	if shop then
		shop:SetAttribute("SpeedMatActive", active)
	end
end
local mustLeaveZone = false

local function treadmillRoot(): Model?
	local base = Bases.mine()
	local treadmill = base and base:FindFirstChild("Treadmill")
	return if treadmill and treadmill:IsA("Model") and treadmill.PrimaryPart then treadmill else nil
end

local function inZone(model: Model, position: Vector3): boolean
	local cf, size = model:GetBoundingBox()
	local l = cf:PointToObjectSpace(position)
	return math.abs(l.X) <= size.X / 2 and math.abs(l.Z) <= size.Z / 2 and l.Y >= -size.Y / 2 and l.Y <= size.Y / 2 + 6
end

-- Belt surface: the model's measured BeltHeight (studs above its bottom at BeltScale) scaled to its size, under
-- the middle of its belt beam attachments; the runner faces the console end (the pivot's LookVector, the biomes).
local function runnerCFrame(model: Model, humanoid: Humanoid, hrp: BasePart): CFrame
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	local scale = model:GetScale() / (model:GetAttribute("BeltScale") or 1)
	local beltTop = bottom + (model:GetAttribute("BeltHeight") or 1.4) * scale
	local body = model.PrimaryPart
	local a0 = body and body:FindFirstChild("Attachment0")
	local a1 = body and body:FindFirstChild("Attachment1")
	local centre = if a0
			and a1
			and a0:IsA("Attachment")
			and a1:IsA("Attachment")
		then (a0.WorldPosition + a1.WorldPosition) / 2
		else cf.Position
	local piv = model:GetPivot()
	local facing = Vector3.new(piv.LookVector.X, 0, piv.LookVector.Z).Unit
	local height = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + hrp.Size.Y / 2
	local pos = Vector3.new(centre.X, beltTop + height, centre.Z)
	return CFrame.lookAt(pos, pos + facing)
end

-- legs move faster on every treadmill upgrade: x1 at the first, up to x4 at the top (reference RunAnim, Curve 0.5)
local function legSpeed(model: Model): number
	local tier = model:GetAttribute("Tier") or 1
	local t = (tier - 1) / math.max(#Progression.Treadmill - 1, 1)
	return Config.TreadmillRunAnimSpeed * (1 + 3 * t ^ 0.5)
end

local function runAnimation(character: Model, humanoid: Humanoid): Animation
	local animate = character:FindFirstChild("Animate")
	local run = animate and animate:FindFirstChild("run")
	local existing = run and run:FindFirstChildOfClass("Animation")
	if existing then
		return existing
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = FALLBACK_RUN[humanoid.RigType] or FALLBACK_RUN[Enum.HumanoidRigType.R15]
	return animation
end

function Treadmill.stop()
	local s = session
	if not s then
		return
	end
	session = nil
	ContextActionService:UnbindAction(ACTION)
	for _, connection in s.connections do
		connection:Disconnect()
	end
	if s.track then
		s.track:Stop(0.2)
	end
	s.humanoid.AutoRotate = true
	s.humanoid.JumpPower = s.jumpPower
	s.humanoid.JumpHeight = s.jumpHeight
	if s.humanoid.Health > 0 then
		-- Step off to the side of the belt.
		s.hrp.CFrame = s.runnerCF * CFrame.new(3.5, 0, 0)
	end
	Movement.locked = false
	mustLeaveZone = true
	HUD.setHint(nil)
	setSpeedMat(false)
end

local function start(root: Model, character: Model, humanoid: Humanoid, hrp: BasePart)
	local s: Session = {
		root = root,
		humanoid = humanoid,
		hrp = hrp,
		runnerCF = runnerCFrame(root, humanoid, hrp),
		track = nil,
		connections = {},
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
	}
	session = s
	Movement.locked = true
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	hrp.CFrame = s.runnerCF

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local ok, track = pcall(function()
			return animator:LoadAnimation(runAnimation(character, humanoid))
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			track:Play(0.15)
			track:AdjustSpeed(legSpeed(root))
			s.track = track
		end
	end

	table.insert(
		s.connections,
		humanoid.Died:Connect(function()
			Treadmill.stop()
		end)
	)

	ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Treadmill.stop()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:SetTitle(ACTION, "Stop")
	HUD.setHint("Training! Press SPACE to stop")
	setSpeedMat(true)
end

function Treadmill.isTraining(): boolean
	return session ~= nil
end

function Treadmill.init()
	-- (the "+N" popup, sound and sparkles for each payout: Client/SpeedFx)
	RunService.Heartbeat:Connect(function()
		local s = session
		if s then
			if not s.root.Parent then
				-- the treadmill was upgraded: hop onto the new one
				local newRoot = treadmillRoot()
				if newRoot then
					s.root = newRoot
					s.runnerCF = runnerCFrame(newRoot, s.humanoid, s.hrp)
					if s.track then
						s.track:AdjustSpeed(legSpeed(newRoot))
					end
				end
			end
			-- Hold the runner on the belt (client owns its character, so this replicates).
			s.hrp.CFrame = s.runnerCF
			s.hrp.AssemblyLinearVelocity = Vector3.zero
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local root = treadmillRoot()
		if not humanoid or not hrp or not root or humanoid.Health <= 0 then
			return
		end
		if not inZone(root, hrp.Position) then
			mustLeaveZone = false
			return
		end
		if not mustLeaveZone and (player:GetAttribute("Carrying") or 0) == 0 then
			start(root, character :: Model, humanoid, hrp)
		end
	end)
end

return Treadmill
