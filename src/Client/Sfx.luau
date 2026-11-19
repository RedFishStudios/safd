-- Disaster sound effects and music. Everything is preloaded at join so the chase music starts the instant
-- a disaster begins. Volumes follow the Settings panel (SfxVolume / MusicVolume player attributes).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

local Sfx = {}

local music: Sound
local rumble: Sound
local holder: Part

local function sfxVolume(): number
	return player:GetAttribute("SfxVolume") or 1
end

-- One-shot 3D sound at a world position.
function Sfx.at(name: string, position: Vector3, volume: number?, speed: number?)
	local id = Config.Sounds[name]
	if not id or not holder then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = holder
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = (volume or 1) * sfxVolume()
	sound.PlaybackSpeed = (speed or 1) * Random.new():NextNumber(0.9, 1.1)
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = 220
	sound.Parent = attachment
	sound:Play()
	sound.Ended:Once(function()
		attachment:Destroy()
	end)
	task.delay(8, function()
		if attachment.Parent then
			attachment:Destroy()
		end
	end)
end

function Sfx.startChase()
	if Config.DisasterMusicId ~= "" then
		music.TimePosition = Config.DisasterMusicStart
		music.Volume = Config.DisasterMusicVolume * (player:GetAttribute("MusicVolume") or 1)
		music:Play()
	end
	rumble.Volume = 0.55 * sfxVolume()
	rumble:Play()
end

function Sfx.stopChase()
	for _, sound in { music, rumble } do
		local fade = TweenService:Create(sound, TweenInfo.new(0.8), { Volume = 0 })
		fade.Completed:Once(function()
			sound:Stop()
		end)
		fade:Play()
	end
end

function Sfx.init()
	holder = Instance.new("Part")
	holder.Name = "SAFD_SfxHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.identity
	holder.Parent = Workspace

	music = Instance.new("Sound")
	music.Name = "SAFD_ChaseMusic"
	music.SoundId = Config.DisasterMusicId
	music.Looped = true
	music.Volume = 0
	music.Parent = SoundService
	rumble = Instance.new("Sound")
	rumble.Name = "SAFD_Rumble"
	rumble.SoundId = Config.Sounds.Rumble
	rumble.Looped = true
	rumble.Volume = 0
	rumble.Parent = SoundService

	task.spawn(function()
		local list: { Instance } = { music, rumble }
		for _, id in Config.Sounds do
			local probe = Instance.new("Sound")
			probe.SoundId = id
			table.insert(list, probe)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

return Sfx
