-- Everyone plays as R6: StarterPlayer.StarterCharacter is a blank R6 rig (saved in the place), and each
-- player's own avatar (clothes, colours, accessories, face) is applied onto it when they spawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local AvatarService = {}

local descriptions: { [number]: HumanoidDescription } = {}

local function descriptionFor(player: Player): HumanoidDescription?
	local cached = descriptions[player.UserId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(math.max(player.UserId, 1))
	end)
	if ok and result then
		descriptions[player.UserId] = result
		return result
	end
	return nil
end

-- Our own R6 run / jump / fall animations in the Animate script (it re-reads them when they change).
local ANIMATE = {
	walk = { "WalkAnim", "RunAnimation" },
	run = { "RunAnim", "RunAnimation" },
	jump = { "JumpAnim", "JumpAnimation" },
	fall = { "FallAnim", "FallAnimation" },
}
local function setAnimations(character: Model)
	local animate = character:WaitForChild("Animate", 10)
	if not animate then
		return
	end
	for folder, spec in ANIMATE do
		local value = animate:FindFirstChild(folder)
		local anim = value and value:FindFirstChild(spec[1])
		if anim and anim:IsA("Animation") and anim.AnimationId ~= Config[spec[2]] then
			anim.AnimationId = Config[spec[2]]
		end
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	setAnimations(character)
	local description = descriptionFor(player)
	if not description then
		return
	end
	-- Body scale values don't apply to R6; clear them so ApplyDescription doesn't complain.
	local copy = description:Clone()
	-- (no animation packages: everyone uses the game's own animations)
	for _, prop in
		{ "RunAnimation", "WalkAnimation", "JumpAnimation", "FallAnimation", "IdleAnimation", "ClimbAnimation" }
	do
		pcall(function()
			(copy :: any)[prop] = 0
		end)
	end
	local ok, err = pcall(function()
		humanoid:ApplyDescription(copy)
	end)
	if not ok then
		warn(`[AvatarService] could not apply {player.Name}'s avatar: {err}`)
	end
	setAnimations(character)
end

function AvatarService.init()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		descriptions[player.UserId] = nil
	end)
end

return AvatarService
