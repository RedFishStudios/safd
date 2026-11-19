-- Feedback for the escape and its rewards: every action gets a sound and a camera move.
--   * ChaseFx.play(name, volume?, pitch?)   a 2D sound (preloaded at join, so it plays the instant it's asked for)
--   * ChaseFx.kick(degrees, time?)           a quick field-of-view punch that springs back (speed, impacts, rings)
--   * ChaseFx.pop(text, color, big?)         a word that bursts in near the middle of the screen and floats away
--   * ChaseFx.letterbox(on)                  black cinema bars for the cutscenes
--   * ChaseFx.cameraTo(cf, time, style?)     move the camera along a tween (the cutscenes); waits until it's there
--   * ChaseFx.releaseCamera()                hand the camera back to the player
-- Volumes follow the Settings panel's SFX slider (SfxVolume).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local ChaseFx = {}

-- (all checked to load as sounds in this experience)
local SOUNDS: { [string]: { string | number } } = {
	Pop = { "rbxassetid://72264591133889", 0.6 }, -- the reference game's soft pop
	Good = { "rbxassetid://74756140439068", 0.55 }, -- bright chime
	Boost = { "rbxassetid://130787814958279", 0.6 }, -- whoosh-up
	Confetti = { "rbxassetid://73743814975286", 0.55 },
	Cash = { "rbxassetid://111773238101465", 0.8 }, -- cash register
	Whoosh = { "rbxassetid://90261693738952", 0.6 }, -- soft cloth swoosh
	Thud = { "rbxassetid://9113805612", 0.8 }, -- heavy thud
	Impact = { "rbxassetid://9118588165", 0.7 }, -- rock drop and break
	Rumble = { "rbxassetid://9112887827", 0.9 },
	Roar = { "rbxassetid://9113626093", 0.9 }, -- a bellow, pitched way down: the disaster waking up
	Zip = { "rbxassetid://9118771226", 0.5 }, -- a long skid, pitched up: the zipline's whirr
}

local cache: { [string]: Sound } = {}
local function sfx(): number
	return 2 * (player:GetAttribute("SfxVolume") or 0.5)
end

function ChaseFx.play(name: string, volume: number?, pitch: number?): Sound?
	local def = SOUNDS[name]
	local base = cache[name]
	if not def or not base then
		return nil
	end
	local s = base:Clone()
	s.Volume = (def[2] :: number) * (volume or 1) * sfx()
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(10, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	return s
end

-- field of view: a spring on top of whatever the camera's own FOV is
local fovOffset, fovVelocity = 0, 0
local baseFov: number? = nil
function ChaseFx.kick(degrees: number, _time: number?)
	fovVelocity += degrees * 18
end

local gui: ScreenGui
local bars: { Frame } = {}

function ChaseFx.pop(text: string, color: Color3, big: boolean?)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.08, if big then 0.32 else 0.4)
	l.Size = UDim2.fromScale(0.5, if big then 0.13 else 0.075)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color
	l.Rotation = (math.random() - 0.5) * 8
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.new(0, 0, 0)
	st.Parent = l
	local sc = Instance.new("UIScale")
	sc.Scale = 0.3
	sc.Parent = l
	l.Parent = gui
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.55, function()
		local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(l, info, { TextTransparency = 1, Position = l.Position - UDim2.fromScale(0, 0.05) }):Play()
		TweenService:Create(st, info, { Transparency = 1 }):Play()
		task.wait(0.42)
		l:Destroy()
	end)
end

function ChaseFx.letterbox(on: boolean)
	for i, b in bars do
		local goal = if on then UDim2.fromScale(1, 0.11) else UDim2.fromScale(1, 0)
		TweenService:Create(b, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = goal }):Play()
		b.AnchorPoint = Vector2.new(0, if i == 1 then 0 else 1)
	end
end

local cameraBusy = false
function ChaseFx.cameraTo(cf: CFrame, time: number, style: Enum.EasingStyle?)
	local cam = Workspace.CurrentCamera
	cameraBusy = true
	cam.CameraType = Enum.CameraType.Scriptable
	local t = TweenService:Create(
		cam,
		TweenInfo.new(time, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ CFrame = cf }
	)
	t:Play()
	task.wait(time)
end

function ChaseFx.releaseCamera()
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		cam.CameraSubject = humanoid
	end
	cameraBusy = false
end

function ChaseFx.cameraBusy(): boolean
	return cameraBusy
end

function ChaseFx.init()
	for name, def in SOUNDS do
		local s = Instance.new("Sound")
		s.Name = "SAFD_Fx_" .. name
		s.SoundId = def[1] :: string
		s.Parent = SoundService
		cache[name] = s
	end
	task.spawn(function()
		local list = {}
		for _, s in cache do
			table.insert(list, s)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)

	gui = Instance.new("ScreenGui")
	gui.Name = "SAFD_ChaseFx"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 35
	gui.Parent = player:WaitForChild("PlayerGui")
	for i = 1, 2 do
		local b = Instance.new("Frame")
		b.Name = if i == 1 then "TopBar" else "BottomBar"
		b.BackgroundColor3 = Color3.new(0, 0, 0)
		b.BorderSizePixel = 0
		b.AnchorPoint = Vector2.new(0, if i == 1 then 0 else 1)
		b.Position = UDim2.fromScale(0, if i == 1 then 0 else 1)
		b.Size = UDim2.fromScale(1, 0)
		b.ZIndex = 10
		b.Parent = gui
		bars[i] = b
	end

	RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		-- spring towards 0
		local k, damping = 120, 16
		fovVelocity += (-k * fovOffset - damping * fovVelocity) * dt
		fovOffset += fovVelocity * dt
		if math.abs(fovOffset) < 0.02 and math.abs(fovVelocity) < 0.05 then
			fovOffset, fovVelocity = 0, 0
			if baseFov then
				cam.FieldOfView = baseFov
				baseFov = nil
			end
			return
		end
		if not baseFov then
			baseFov = cam.FieldOfView
		end
		cam.FieldOfView = math.clamp((baseFov :: number) + fovOffset, 40, 110)
	end)
end

return ChaseFx
