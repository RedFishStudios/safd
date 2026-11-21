-- Animals call out, like the reference game ("[NEW] Feed and Rob Animals", Config/Sounds Calls + AnimalCall): every
-- animal near you (wild ones in the biomes and the ones in the bases) makes its species' sound now and then from
-- where it stands: chickens cluck, horses neigh, yaks moo, dragons roar... Bigger (rarer) animals sound deeper. How
-- loud: the Settings panel's Animal Sounds slider (AnimalVolume).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

local AnimalSounds = {}

-- the reference's calls (Creator Store sound effects)
local CALLS = {
	Cluck = { 77584650945481, 0.6 },
	Oink = { 9117344600, 0.6 },
	Moo = { 138223429, 0.55 },
	Neigh = { 3165902128, 0.55 },
	Squeak = { 111105644516217, 0.5 },
	Bark = { 99723552215501, 0.55 },
	Howl = { 9120790529, 0.45 },
	Roar = { 9116303194, 0.5 },
	Bellow = { 9113626093, 0.5 },
	Growl = { 102112785810676, 0.5, 3 },
	Chirp = { 105990653889537, 0.45, 2.5 },
	Gull = { 9118858259, 0.5 },
	Screech = { 133423182233493, 0.4 },
	Hiss = { 95722591785076, 0.5 },
	Croak = { 9113859538, 0.55 },
	Dragon = { 122225901664901, 0.5 },
	Buzz = { 130509545329522, 0.4 },
}

local CALL_OF = {
	-- Grassy Meadows
	Chicken = "Cluck",
	Bunny = "Squeak",
	Horse = "Neigh",
	Griffin = "Screech",
	Pegasus = "Neigh",
	-- Snowy Tundra
	Puffin = "Gull",
	Yak = "Moo",
	PolarBear = "Growl",
	Mammoth = "Bellow",
	Fenrir = "Howl",
	-- Sandy Dunes
	Meerkat = "Squeak",
	FennecFox = "Bark",
	Cobra = "Hiss",
	Manticore = "Roar",
	Sphinx = "Roar",
	-- Fiery Hellscape
	Salamander = "Hiss",
	Hellhound = "Growl",
	Cerberus = "Bark",
	Dragon = "Dragon",
	Phoenix = "Screech",
	-- Toxic Wasteland
	Toad = "Croak",
	Beetle = "Buzz",
	GiantSpider = "Hiss",
	Chupacabra = "Growl",
	Hydra = "Dragon",
	-- Candyland
	Hamster = "Squeak",
	Axolotl = "Croak",
	Flamingo = "Chirp",
	Unicorn = "Neigh",
	Qilin = "Roar",
	Corgi = "Bark",
	Goat = "Bellow",
	Cow = "Moo",
	Akita = "Bark",
	Wolf = "Howl",
	Tiger = "Roar",
	Armadillo = "Squeak",
	Lizard = "Hiss",
	Caracal = "Growl",
	Komodo = "Hiss",
	ShadowWolf = "Howl",
	Cockatrice = "Screech",
	Newt = "Croak",
	Hyena = "Bark",
	Crocodile = "Growl",
	Toucan = "Chirp",
	RedPanda = "Squeak",
	Kitsune = "Bark",
	Caladrius = "Screech",
	Simurgh = "Chirp",
	Dimetrodon = "Hiss",
	BichonFrise = "Bark",
	Ankylosaurus = "Bellow",
	Triceratops = "Bellow",
	Gecko = "Hiss",
	Jackal = "Howl",
}

-- (heard more: the biomes' animals are few and spread out, so with calls every 8-20 s within 90 studs you rarely heard
-- one, 2026-11-19)
-- (fewer again: "too many animal sounds", 2026-11-19)
-- (quieter and rarer again: "plays too much too often", 2026-11-19)
local WILD_EVERY = { 30, 60 } -- seconds between one wild animal's calls
local BASE_EVERY = { 90, 180 } -- base animals hardly ever
local GAP = 8 -- at least this long between any two calls
local RANGE = 170 -- animals further than this from the camera stay quiet
local LOUDNESS = 1.4 -- x the call's own volume x the Animal Sounds slider (0.5 by default)

local nextCall: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastAny = 0
local rng = Random.new()

local function call(model: Model, id: string, pitch: number?, volume: number?)
	local kind = CALL_OF[id]
	local def = kind and CALLS[kind]
	local part = model.PrimaryPart
	if not def or not part then
		return
	end
	local info = Config.Animals[id]
	local rarity = if info then info.Rarity else 1
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. def[1]
	s.Volume = def[2] * LOUDNESS * (volume or 1) * (player:GetAttribute("AnimalVolume") or 0.5)
	s.PlaybackSpeed = math.clamp(1.12 - (rarity - 1) * 0.05, 0.7, 1.2) * rng:NextNumber(0.94, 1.06) * (pitch or 1)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 25 + rarity * 8
	s.RollOffMaxDistance = RANGE + 40
	s.Parent = part
	s:Play()
	local maxLen = def[3]
	if maxLen then
		task.delay(maxLen, function()
			if s.Parent then
				s:Stop()
				s:Destroy()
			end
		end)
	end
	s.Ended:Once(function()
		s:Destroy()
	end)
end

-- one call from this animal, now (the intro: scared, high-pitched calls). pitch / volume multiply the usual ones.
function AnimalSounds.call(model: Model, id: string, pitch: number?, volume: number?)
	call(model, id, pitch, volume)
end

function AnimalSounds.init()
	task.spawn(function()
		while true do
			task.wait(0.25)
			if (player:GetAttribute("AnimalVolume") or 0.5) <= 0.001 then
				continue
			end
			local cam = Workspace.CurrentCamera
			if not cam then
				continue
			end
			local from = cam.CFrame.Position
			local now = os.clock()
			for _, folderName in { "WildAnimals", "BaseAnimals" } do
				local folder = Workspace:FindFirstChild(folderName)
				if not folder then
					continue
				end
				local every = if folderName == "WildAnimals" then WILD_EVERY else BASE_EVERY
				for _, model in folder:GetChildren() do
					if not model:IsA("Model") or model:GetAttribute("LocalHidden") then
						continue
					end
					local due = nextCall[model]
					if not due then
						nextCall[model] = now + rng:NextNumber(every[1] * 0.3, every[2])
						continue
					end
					if now < due or now - lastAny < GAP then
						continue
					end
					nextCall[model] = now + rng:NextNumber(every[1], every[2])
					if (model:GetPivot().Position - from).Magnitude <= RANGE then
						local id = model:GetAttribute("AnimalId")
						if type(id) == "string" then
							lastAny = now
							call(model, id)
						end
					end
				end
			end
		end
	end)
end

return AnimalSounds
