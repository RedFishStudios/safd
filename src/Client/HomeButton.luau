-- The "Base" button (user 2026-11-22: "allow players to teleport to their base while they are in the zones ... not during
-- the run ... on top of the Shop button"): a copy of the HUD's Shop button, orange with a house, right above Shop. It
-- only shows while you're out in a biome and not running home / hatching; clicking it asks the server
-- (Net.GoHome -> BaseService) to put you back at your base.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapInfo = require(Shared.MapInfo)
local Net = require(Shared.Net)

local HomeButton = {}

local player = Players.LocalPlayer
-- (plain like Shop and Index: the same faint pattern, only the gradient is orange; user 2026-11-22)
local ORANGE = ColorSequence.new(Color3.fromRGB(255, 200, 40), Color3.fromRGB(255, 120, 10))
local ORANGE_EDGE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 80, 10)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 225, 140)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 225, 140)),
})

local function build(): GuiButton?
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("Hud", 30)
	local shop = hud and hud:FindFirstChild("ShopButton", true)
	if not (shop and shop:IsA("GuiButton")) then
		return nil
	end
	local old = shop.Parent:FindFirstChild("HomeButton")
	if old then
		old:Destroy()
	end
	local b = shop:Clone()
	b.Name = "HomeButton"
	-- (right above Shop: the same gap as between Shop and Index)
	local index = shop.Parent:FindFirstChild("IndexButton")
	local step = if index and index:IsA("GuiObject") then index.Position.Y.Scale - shop.Position.Y.Scale else 0.37
	b.Position = UDim2.fromScale(shop.Position.X.Scale, shop.Position.Y.Scale - step)
	local visual = b:FindFirstChild("Visual")
	local label = visual and visual:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = "Base"
	end
	local icon = visual and visual:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.ImageTransparency = 1
		local house = Instance.new("TextLabel")
		house.Name = "House"
		house.BackgroundTransparency = 1
		house.Size = UDim2.fromScale(1, 1)
		house.Text = "🏠"
		house.TextScaled = true
		house.ZIndex = icon.ZIndex + 1
		house.Parent = icon
	end
	-- (the Shop button's green comes from its "Border" picture, a green frame with checker holes; hidden here so the
	-- orange gradient shows plain, with the same faint pattern as Shop: user 2026-11-22 "should not be checkered")
	local border = visual and visual:FindFirstChild("Border")
	if border and border:IsA("GuiObject") then
		border.Visible = false
	end
	local bg = visual and visual:FindFirstChild("Background")
	if bg then
		local edge = bg:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Thickness = math.max(edge.Thickness, 3)
		end
		local g = bg:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ORANGE
			-- (the UI pack can repaint its buttons: keep ours orange)
			g:GetPropertyChangedSignal("Color"):Connect(function()
				if g.Color ~= ORANGE then
					g.Color = ORANGE
				end
			end)
		end
		local st = bg:FindFirstChildOfClass("UIStroke")
		local sg = st and st:FindFirstChildOfClass("UIGradient")
		if sg then
			sg.Color = ORANGE_EDGE
		end
	end
	b.Visible = false
	b.Parent = shop.Parent
	b.Activated:Connect(function()
		Net.event("GoHome"):FireServer()
	end)
	return b
end

function HomeButton.init()
	task.spawn(function()
		local button = build()
		if not button then
			return
		end
		local acc = 0
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 0.2 then
				return
			end
			acc = 0
			if not button.Parent then
				button = build() or button
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local chasing = Workspace:FindFirstChild("LocalDisaster") ~= nil
				or (player:GetAttribute("Carrying") or 0) > 0
			local show = root ~= nil
				and not chasing
				and not player:GetAttribute("SAFD_Cutscene")
				and MapInfo.biomeAt(root.Position) ~= nil
			button.Visible = show
		end)
	end)
end

return HomeButton
