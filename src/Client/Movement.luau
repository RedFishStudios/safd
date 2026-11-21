-- Owns the local character's WalkSpeed: walk speed from your speed points (Shared/Progression.walkSpeed, the
-- reference game's curve) x temporary boosts / slows, capped by the HUD "Slow Mode" switch. Trails and "double
-- speed" multiply the points the treadmill gives instead (Server/TrainingService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))

local player = Players.LocalPlayer

local Movement = {}
Movement.locked = false -- true while something else (the treadmill) controls the character

local slowUntil = 0
local boostUntil = 0
local boostMultiplier = 1
local boostTime = 1

function Movement.slow(duration: number)
	slowUntil = math.max(slowUntil, os.clock() + duration)
end

function Movement.isSlowed(): boolean
	return os.clock() < slowUntil
end

function Movement.boost(multiplier: number, duration: number)
	boostMultiplier = multiplier
	boostTime = math.max(duration, 0.01)
	boostUntil = os.clock() + duration
end

function Movement.baseSpeed(): number
	local speed = Progression.walkSpeed(player:GetAttribute("Speed") or 0)
	if player:GetAttribute("SlowMode") then
		speed = math.min(speed, Config.SlowModeWalkSpeed)
	end
	return speed
end

function Movement.init()
	RunService.Heartbeat:Connect(function()
		if Movement.locked then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local now = os.clock()
		local speed = Movement.baseSpeed()
		if now < boostUntil then
			-- eases back to normal speed over the burst (a sudden drop from 1.5x felt like a hitch)
			local left = (boostUntil - now) / boostTime
			speed *= 1 + (boostMultiplier - 1) * math.min(left * 1.5, 1)
		end
		if now < slowUntil then
			speed *= Config.SlowMultiplier
		end
		humanoid.WalkSpeed = speed
	end)
end

return Movement
