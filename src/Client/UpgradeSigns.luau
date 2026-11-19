-- Your base's upgrade signs (Upgrade Base / Upgrade Treadmill, the reference game's sign models): the server writes
-- the levels and prices onto each sign's SurfaceGui (BaseService.updateUpgradeSigns) but keeps it disabled. Here
-- the owner gets a working copy in PlayerGui (in-world SurfaceGuis can't be clicked), its cash button green once
-- they can pay and red until then, with the "!" over the sign when an upgrade is affordable. Other players' signs
-- (and unclaimed bases' signs) don't show on this screen at all, like the reference.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Bases = require(script.Parent.Bases)

local player = Players.LocalPlayer

local UpgradeSigns = {}

local SIGN_MODELS = { "PlotUpgrade", "TreadmillUpgrade" }
local GREEN = ColorSequence.new(Color3.new(0, 1, 0), Color3.fromRGB(112, 255, 112))
local RED = ColorSequence.new(Color3.fromRGB(255, 45, 45), Color3.fromRGB(255, 140, 140))

type Copy = { sign: BasePart, gui: SurfaceGui, bang: BillboardGui? }
local copies: { [string]: Copy } = {}
local lastBuy = 0

local function setVisible(model: Instance, visible: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

local function mirror(src: Instance, dst: Instance)
	for _, name in { "Info", "Level" } do
		local a, b = src:FindFirstChild(name), dst:FindFirstChild(name)
		if a and b and a:IsA("TextLabel") and b:IsA("TextLabel") and b.Text ~= a.Text then
			b.Text = a.Text
		end
	end
	local fa, fb = src:FindFirstChild("Frame"), dst:FindFirstChild("Frame")
	if not (fa and fb) then
		return
	end
	for _, name in { "Upgrade", "RobuxUpgrade" } do
		local a, b = fa:FindFirstChild(name), fb:FindFirstChild(name)
		if a and b and a:IsA("GuiObject") and b:IsA("GuiObject") then
			b.Visible = a.Visible
			b.LayoutOrder = a.LayoutOrder
			local ca, cb = a:FindFirstChild("Cost"), b:FindFirstChild("Cost")
			if ca and cb and ca:IsA("TextLabel") and cb:IsA("TextLabel") and cb.Text ~= ca.Text then
				cb.Text = ca.Text
			end
		end
	end
end

local function makeCopy(sign: BasePart, kind: string): Copy?
	local src = sign:FindFirstChild("SurfaceGui")
	if not (src and src:IsA("SurfaceGui")) then
		return nil
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = src:Clone()
	gui.Name = `SAFD_Sign_{kind}`
	gui.Adornee = sign
	gui.Enabled = true
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	local up = gui:FindFirstChild("Upgrade", true)
	if up and up:IsA("GuiButton") then
		up.Activated:Connect(function()
			if os.clock() - lastBuy > 0.4 then
				lastBuy = os.clock()
				Net.event("BuyUpgrade"):FireServer(kind)
			end
		end)
	end
	local bang: BillboardGui? = nil
	local srcBang = sign:FindFirstChild("CanUpgrade")
	if srcBang and srcBang:IsA("BillboardGui") then
		local b = srcBang:Clone()
		b.Name = `SAFD_SignBang_{kind}`
		b.Adornee = sign
		b.ResetOnSpawn = false
		b.Enabled = false
		b.Parent = playerGui
		bang = b
	end
	return { sign = sign, gui = gui, bang = bang }
end

local function drop(kind: string)
	local c = copies[kind]
	if c then
		c.gui:Destroy()
		if c.bang then
			c.bang:Destroy()
		end
		copies[kind] = nil
	end
end

local function update()
	local folder = Bases.folder()
	if not folder then
		return
	end
	local mine = Bases.mine()
	local money = player:GetAttribute("Money") or 0
	for _, base in folder:GetChildren() do
		for _, name in SIGN_MODELS do
			local model = base:FindFirstChild(name)
			if model and model:IsA("Model") then
				setVisible(model, base == mine)
			end
		end
	end
	for _, name in SIGN_MODELS do
		local kind = if name == "PlotUpgrade" then "Base" else "Treadmill"
		local model = mine and mine:FindFirstChild(name)
		local sign = model and model:FindFirstChild("Sign")
		if not (model and model:IsA("Model") and sign and sign:IsA("BasePart")) then
			drop(kind)
			continue
		end
		local c = copies[kind]
		if c and (c.sign ~= sign or not c.gui.Parent) then
			drop(kind)
			c = nil
		end
		if not c then
			c = makeCopy(sign, kind)
			copies[kind] = c
		end
		if c then
			local src = sign:FindFirstChild("SurfaceGui")
			if src then
				mirror(src, c.gui)
			end
			local price = model:GetAttribute("Price") or -1
			local ok = price >= 0 and money >= price
			local up = c.gui:FindFirstChild("Upgrade", true)
			local g = up and up:FindFirstChildOfClass("UIGradient")
			if g then
				g.Color = if ok then GREEN else RED
			end
			if c.bang then
				c.bang.Enabled = ok
			end
		end
	end
end

function UpgradeSigns.init()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			update()
		end
	end)
end

return UpgradeSigns
