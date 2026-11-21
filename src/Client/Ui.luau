-- Small UI helpers for the game's own windows (the "you can buy" popup, My Animals, the danger-zone warning), in the
-- UI pack's chunky style: FredokaOne, thick dark outlines, rounded boxes, green / red / blue buttons.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local Ui = {}

Ui.DARK = Color3.fromRGB(20, 15, 35)
Ui.GREEN = { Color3.fromRGB(150, 255, 60), Color3.fromRGB(60, 200, 30), Color3.fromRGB(30, 100, 15) }
Ui.RED = { Color3.fromRGB(255, 110, 100), Color3.fromRGB(215, 35, 35), Color3.fromRGB(100, 10, 10) }
Ui.BLUE = { Color3.fromRGB(90, 190, 255), Color3.fromRGB(30, 110, 235), Color3.fromRGB(10, 45, 120) }
Ui.ORANGE = { Color3.fromRGB(255, 210, 80), Color3.fromRGB(255, 140, 20), Color3.fromRGB(120, 60, 0) }
Ui.GREY = { Color3.fromRGB(170, 170, 180), Color3.fromRGB(110, 110, 120), Color3.fromRGB(40, 40, 50) }

function Ui.corner(parent: Instance, r: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r or 0.2, 0)
	c.Parent = parent
	return c
end

function Ui.stroke(parent: Instance, thickness: number, color: Color3?, border: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Ui.DARK
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
	return s
end

function Ui.gradient(parent: Instance, a: Color3, b: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = ColorSequence.new(a, b)
	g.Parent = parent
	return g
end

function Ui.text(parent: Instance, props: { [string]: any }, strokeSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(l :: any)[k] = v
	end
	if strokeSize then
		Ui.stroke(l, strokeSize)
	end
	l.Parent = parent
	return l
end

function Ui.frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

-- a chunky button: a colour gradient, a dark outline and a bouncy press
function Ui.button(parent: Instance, text: string, colors: { Color3 }, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.Text = ""
	for k, v in props do
		(b :: any)[k] = v
	end
	Ui.corner(b, 0.25)
	local g = Ui.gradient(b, colors[1], colors[2])
	g.Name = "Fill"
	local st = Ui.stroke(b, 3, colors[3], true)
	st.Name = "Edge"
	local l = Ui.text(b, {
		Name = "Label",
		Position = UDim2.fromScale(0.06, 0.12),
		Size = UDim2.fromScale(0.88, 0.76),
		Text = text,
		ZIndex = b.ZIndex + 1,
	}, 2)
	l.ZIndex = b.ZIndex + 1
	local sc = Instance.new("UIScale")
	sc.Parent = b
	b.MouseButton1Down:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.08), { Scale = 0.92 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end)
	b.MouseLeave:Connect(function()
		sc.Scale = 1
	end)
	b.Parent = parent
	return b
end

function Ui.recolor(b: GuiObject, colors: { Color3 })
	local g = b:FindFirstChild("Fill")
	if g and g:IsA("UIGradient") then
		g.Color = ColorSequence.new(colors[1], colors[2])
	end
	local st = b:FindFirstChild("Edge")
	if st and st:IsA("UIStroke") then
		st.Color = colors[3]
	end
end

-- the orange paw (Throw Food for Animals' Animals icon), drawn from rounded frames inside a square parent
function Ui.paw(parent: GuiObject, z: number?)
	local zi = z or parent.ZIndex + 1
	local function blob(pos: Vector2, size: Vector2, rot: number)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(pos.X, pos.Y)
		f.Size = UDim2.fromScale(size.X, size.Y)
		f.Rotation = rot
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BorderSizePixel = 0
		f.ZIndex = zi
		Ui.corner(f, 1)
		Ui.gradient(f, Color3.fromRGB(255, 190, 110), Color3.fromRGB(255, 120, 40))
		local st = Ui.stroke(f, 2, Color3.fromRGB(225, 45, 20))
		st.Thickness = math.max(2, parent.AbsoluteSize.X / 28)
		f.Parent = parent
	end
	blob(Vector2.new(0.5, 0.66), Vector2.new(0.5, 0.42), 0)
	blob(Vector2.new(0.18, 0.4), Vector2.new(0.19, 0.25), -28)
	blob(Vector2.new(0.37, 0.2), Vector2.new(0.19, 0.25), -10)
	blob(Vector2.new(0.63, 0.2), Vector2.new(0.19, 0.25), 10)
	blob(Vector2.new(0.82, 0.4), Vector2.new(0.19, 0.25), 28)
end

-- pops a window in (springy)
function Ui.pop(gui: GuiObject, from: number?)
	local sc = gui:FindFirstChild("Pop") :: UIScale?
	if not sc then
		local made = Instance.new("UIScale")
		made.Name = "Pop"
		made.Parent = gui
		sc = made
	end
	(sc :: UIScale).Scale = from or 0.4
	TweenService:Create(sc :: UIScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- a 3D model in a picture slot (a treadmill, an animal ...): the camera fits the model's bounding box
function Ui.viewport(parent: Instance, model: Model, angle: Vector3?): ViewportFrame
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	if parent:IsA("GuiObject") then
		frame.ZIndex = parent.ZIndex + 1
	end
	frame.Ambient = Color3.fromRGB(190, 190, 190)
	frame.LightDirection = Vector3.new(-0.5, -1, 0.6)
	model.Parent = frame
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	local d = math.max(size.X, size.Y, size.Z) * 1.6 + 1
	cam.CFrame = CFrame.lookAt(cf.Position + (angle or Vector3.new(0.7, 0.45, -1)).Unit * d, cf.Position)
	cam.Parent = frame
	frame.CurrentCamera = cam
	frame.Parent = parent
	return frame
end

-- true while one of the UI pack's windows is open (they flag it with an "...Open" attribute: Offline Cash, the Trail
-- Shop, the Index, Sell Pets ...) or one of ours (SAFD_Animals' window)
function Ui.windowOpen(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then
		return false
	end
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled then
			for name, value in g:GetAttributes() do
				if value == true and string.sub(name, -4) == "Open" then
					return true
				end
			end
		end
	end
	for _, name in { "SAFD_Animals", "SAFD_Help" } do
		local g = pg:FindFirstChild(name)
		local window = g and g:FindFirstChild("Window")
		if window and window:IsA("GuiObject") and window.Visible then
			return true
		end
	end
	return false
end

-- Studio only: warns about any of our screen UI sized in pixels (offsets or a UISizeConstraint MinSize). Everything
-- has to be sized as a share of the screen (Scale, or SizeConstraint RelativeYY for squares), so a phone shows the
-- same layout as a computer, just smaller (user 2026-11-21: "it should always be scaled", also after future changes).
function Ui.auditScaling()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then
		return
	end
	local problems = {}
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and (string.sub(g.Name, 1, 5) == "SAFD_" or g.Name == "AreaBanner") then
			for _, d in g:GetDescendants() do
				if d:IsA("UISizeConstraint") and (d.MinSize.X > 0 or d.MinSize.Y > 0) then
					table.insert(problems, d:GetFullName() .. " has a MinSize")
				elseif d:IsA("GuiObject") and not d:GetAttribute("PixelOK") then
					local s = d.Size
					if (s.X.Offset > 2 or s.Y.Offset > 2) and d.Parent and d.Parent:IsA("ScreenGui") then
						table.insert(problems, d:GetFullName() .. " is sized in pixels")
					end
				end
			end
		end
	end
	if #problems > 0 then
		warn("[Ui] not scaled with the screen (phones!):\n  " .. table.concat(problems, "\n  "))
	end
end

-- true during the run home, the hatch cutscene and the intro: no popups then
function Ui.busy(): boolean
	if Workspace:FindFirstChild("LocalDisaster") then
		return true
	end
	if (player:GetAttribute("Carrying") or 0) > 0 then
		return true
	end
	if player:GetAttribute("SAFD_Cutscene") then
		return true
	end
	local pg = player:FindFirstChild("PlayerGui")
	local intro = pg and pg:FindFirstChild("SAFD_Intro")
	if intro and intro:IsA("ScreenGui") and intro.Enabled then
		return true
	end
	return false
end

return Ui
