-- Lobby music: HAPPY, cheerful Christmas music, never sad (user 2026-11-22: the calm Christmas list was "too calm and
-- sad"; before that calm classical, and Tchaikovsky's Trepak etc. had loud bursts): jolly sleigh-bell / jingle tracks
-- (free APM / DistroKid tracks from the Creator Store, usable in any experience; all checked to load) plays everywhere,
-- one after another. It fades out only during the chase home (Client/Sfx has the chase music) and the hatch
-- cutscene, and fades back in,
-- carrying on where it was. Volume follows the Settings
-- panel's music slider (player attribute MusicVolume).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local LobbyMusic = {}

local TRACKS = {
	"rbxassetid://1839945406", -- Jingle Bells (APM: lively, toe-tapping jazz piano, 1:57)
	"rbxassetid://9041838912", -- Snow Ball Fun (APM: bouncing sleigh bells, carefree, 1:32)
	"rbxassetid://1838667168", -- We Wish You A Merry Christmas (APM instrumental, 2:13)
	"rbxassetid://109810915196826", -- Tiptoe Marimba Elves Xmas (playful marimba, 1:09)
	"rbxassetid://1841238714", -- Happy Christmas (a) (APM, 2:33)
	"rbxassetid://1838667719", -- Christmas Father's Sled (APM, 1:08)
	"rbxassetid://1838667061", -- Jingle Bells (APM instrumental, 2:31)
	"rbxassetid://1838667740", -- Christmas Presents (APM, 1:03)
}
local VOLUME = 0.35

function LobbyMusic.init()
	local index = 1
	local sound = Instance.new("Sound")
	sound.Name = "SAFD_LobbyMusic"
	sound.Volume = 0
	sound.SoundId = TRACKS[index]
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		index = index % #TRACKS + 1
		sound.SoundId = TRACKS[index]
		sound.TimePosition = 0
		sound:Play()
	end)
	local level = 0 -- 0..1, faded
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		local step = acc
		acc = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- plays everywhere (spawn, bases and the biomes, user 2026-11-21); only the chase home stops it (Client/Sfx
		-- has the chase music): an egg carried or the run's LocalDisaster
		local chasing = Workspace:FindFirstChild("LocalDisaster") ~= nil or (player:GetAttribute("Carrying") or 0) > 0
		-- (and none during the hatch cutscene: user 2026-11-22)
		local hatching = player:GetAttribute("SAFD_Cutscene") == true
		local want = if root ~= nil and not chasing and not hatching then 1 else 0
		level = math.clamp(level + (if want > level then step / 1.5 else -step / 0.8), 0, 1)
		local volume = VOLUME * level * (player:GetAttribute("MusicVolume") or 0.5) * 2
		sound.Volume = volume
		if level > 0 and not sound.IsPlaying then
			if sound.TimePosition > 0 then
				sound:Resume()
			else
				sound:Play()
			end
		elseif level <= 0 and sound.IsPlaying then
			sound:Pause()
		end
	end)
end

return LobbyMusic
