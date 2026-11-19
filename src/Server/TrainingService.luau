-- Treadmill training, ported from "[NEW] Feed and Rob Animals" (TrainingService): standing on your own treadmill
-- pays its tier's Gain in speed points once per payout interval (0.25 s, shrinking to 0.1 s as your speed grows on
-- that treadmill: Shared/Progression.interval), times your trail and "double speed" multiplier. Walking speed comes
-- from the points (Shared/Progression.walkSpeed), so +1 point is nowhere near +1 stud/s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)

local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)

local TrainingService = {}

local POPUP_EVERY = 0.25

type State = { nextStep: number?, popupSum: number, popupSteps: number }
local state: { [Player]: State } = {}
local SpeedGain = Net.event("SpeedGain")

local function tierOf(data: any)
	return Progression.Treadmill[data.TreadmillLevel or 1] or Progression.Treadmill[1]
end

local function applySpeed(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if data and humanoid then
		humanoid.WalkSpeed = Progression.walkSpeed(data.Speed)
	end
end

local function onTreadmill(player: Player): boolean
	local plot = BaseService.getPlot(player)
	local model = plot and plot.Treadmill
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (model and hrp and humanoid) or humanoid.Health <= 0 then
		return false
	end
	local cf, size = model:GetBoundingBox()
	local l = cf:PointToObjectSpace(hrp.Position)
	return math.abs(l.X) <= size.X / 2 + 0.5
		and math.abs(l.Z) <= size.Z / 2 + 0.5
		and l.Y >= -size.Y / 2 - 1
		and l.Y <= size.Y / 2 + 6
end

local function tick(onChanged: (Player) -> ())
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		local s = state[player]
		if not s then
			s = { nextStep = nil, popupSum = 0, popupSteps = 0 }
			state[player] = s
		end
		local st = s :: State
		local training = data ~= nil and onTreadmill(player)
		if training then
			local gain = tierOf(data).Gain
			local interval = Progression.interval(data.Speed, gain)
			if not st.nextStep then
				st.nextStep = now + interval
			end
			local steps = 0
			while now >= (st.nextStep :: number) and steps < 10 do
				steps += 1
				st.nextStep = (st.nextStep :: number) + interval
			end
			if now - (st.nextStep :: number) > 1 then
				st.nextStep = now
			end
			if steps > 0 then
				local per = gain * (player:GetAttribute("SpeedMultiplier") or 1)
				local n = per * steps
				data.Speed += n
				st.popupSum += n
				st.popupSteps += steps
				onChanged(player)
			end
			if st.popupSum > 0 and st.popupSteps >= math.ceil(POPUP_EVERY / interval - 1e-6) then
				SpeedGain:FireClient(player, st.popupSum)
				st.popupSum, st.popupSteps = 0, 0
			end
		elseif st.nextStep then
			st.nextStep = nil
			st.popupSum, st.popupSteps = 0, 0
		end
		if player:GetAttribute("Training") ~= training then
			player:SetAttribute("Training", training)
		end
	end
end

function TrainingService.playerLoaded(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		applySpeed(player)
	end)
	applySpeed(player)
end

function TrainingService.playerRemoving(player: Player)
	state[player] = nil
end

function TrainingService.init(onChanged: (Player) -> ())
	RunService.Heartbeat:Connect(function()
		tick(onChanged)
	end)
end

return TrainingService
