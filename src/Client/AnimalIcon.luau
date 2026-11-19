-- A picture of an animal for the UI: its model in a ViewportFrame, framed from the front and a little to the side.
--   AnimalIcon.viewport(parent, id, closeUp?) -> ViewportFrame   (closeUp: a tighter portrait of the animal)
--   AnimalIcon.spin(frame, speed)                                 (turns the model slowly, until the frame is gone)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimalFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimalFactory"))

local AnimalIcon = {}

function AnimalIcon.viewport(parent: GuiObject, id: string, closeUp: boolean?): ViewportFrame
	local frame = Instance.new("ViewportFrame")
	frame.Name = "AnimalViewport"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Ambient = Color3.fromRGB(180, 180, 180)
	frame.LightColor = Color3.fromRGB(255, 250, 240)
	frame.LightDirection = Vector3.new(-0.5, -1, 0.6)
	frame.ZIndex = parent.ZIndex + 1
	local model = AnimalFactory.create(id, 4, 4)
	model:PivotTo(CFrame.identity) -- (unturned, an animal faces -Z)
	model.Parent = frame
	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = if closeUp then 32 else 40
	local distance = math.max(size.X, size.Y, size.Z) * (if closeUp then 1.45 else 1.7) + 1
	local aim = cf.Position + Vector3.new(0, if closeUp then size.Y * 0.1 else 0, 0)
	camera.CFrame = CFrame.lookAt(aim + Vector3.new(0.55, 0.3, -1).Unit * distance, aim)
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent
	return frame
end

function AnimalIcon.spin(frame: ViewportFrame, speed: number)
	local model = frame:FindFirstChildOfClass("Model")
	if not model then
		return
	end
	local base = model:GetPivot()
	local a = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not frame.Parent then
			connection:Disconnect()
			return
		end
		a += dt * speed
		model:PivotTo(base * CFrame.Angles(0, math.sin(a) * 0.6, 0))
	end)
end

return AnimalIcon
