-- Procedural idle / walk animation for the animals from the reference game's animal pack ("[NEW] Feed and Rob
-- Animals", AnimalPack.Shared.CreatureAnimator, copied as is). Client/AnimalVisuals drives it from Shared/CreatureProfiles.
--[[ CreatureAnimator
	Procedural idle / walk animation for AnimalPack creatures. Drives each bone's Motor6D.Transform from the
	creature's profile (Animation/Profile ModuleScript). Every loop is periodic (idle loop = profile.IdleLoop seconds,
	walk loop = 1 / StepRate), so the same poses can be baked into KeyframeSequences (CreatureAnimator.Bake).

	local anim = CreatureAnimator.new(model, profile)
	anim:SetState("Idle" | "Walk")
	anim:Step(dt)                -- call every frame (client)
	anim:Destroy()               -- resets the joints

	Profile fields (all optional; angles in degrees, distances as a fraction of the creature's height):
	  StepRate, WalkSpeed (studs/s), IdleLoop (s)
	  Body  = { bone, breathe, breathePitch, bob, pitch, roll, sway, lean }
	  Legs  = { { bone, phase, swing, lift, knee = bone, bend, splay } ... }
	  Arms  = { { bone, phase, swing, idle } ... }
	  Head  = { bone, look, nod, tilt, walkNod }     Neck = { bones = {...}, look, nod, walkNod, sway }
	  Tail  = { bones = {...}, idle, walk, lag, lift, axis = "Y" | "X", rate }
	  Ears  = { bones = {...}, twitch, flop, axis }
	  Jaw   = { bone, open, rate }
	  Wings = { { bone, tip, side = 1 | -1, idle, walk, rate, fold } ... }
	  Extra = { { bone, axis, idle, walk, rate, phase, offset } ... }   -- free oscillators (manes, tail fans, heads)
]]
local A = {}
A.__index = A

local TAU = math.pi * 2
local rad, sin, cos, max = math.rad, math.sin, math.cos, math.max

local function ang(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end
local function axisAngle(axis, deg)
	if axis == "X" then
		return ang(deg, 0, 0)
	elseif axis == "Z" then
		return ang(0, 0, deg)
	end
	return ang(0, deg, 0)
end
local function sideOf(name)
	local last = name:sub(-1)
	if last == "L" then
		return -1
	end
	return 1
end

function A.collect(model)
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	return motors
end

function A.new(model, profile)
	local self = setmetatable({}, A)
	self.model = model
	self.p = profile
	self.motors = A.collect(model)
	self.height = model:GetAttribute("Height") or 4
	self.t = math.random() * (profile.IdleLoop or 4)
	self.cycle = math.random()
	self.w = 0
	self.target = 0
	return self
end

function A:SetState(state)
	self.target = (state == "Walk") and 1 or 0
	self.state = state
end

-- pose for idle time t (seconds), walk cycle position c (0..1) and walk weight w -> { bone = CFrame }
function A.Pose(p, H, t, c, w)
	local out = {}
	local function add(bone, cf)
		if bone then
			out[bone] = (out[bone] or CFrame.identity) * cf
		end
	end
	local L = p.IdleLoop or 4
	local function osc(k, ph)
		return sin(TAU * (t * k / L + (ph or 0)))
	end -- k whole cycles per idle loop
	local function wv(k, ph)
		return sin(TAU * (c * k + (ph or 0)))
	end -- k cycles per stride
	local i = 1 - w

	local B = p.Body
	if B then
		local breath = osc(B.breathRate or 1)
		-- walk: the body dips each time a foot plants (two dips per stride), rolls and shifts its weight
		-- over the planted side, and leans into the walk
		local dip = 0.5 - 0.5 * cos(TAU * c * 2)
		local y = i * (B.breathe or 0.012) * H * breath - w * (B.bob or 0.025) * H * dip
		local pitch = i * (B.breathePitch or 0.8) * breath + w * ((B.pitch or 1.5) * wv(2, 0.25) + (B.lean or 0))
		local roll = w * (B.roll or 1.5) * wv(1) + i * (B.sway or 0) * osc(1, 0.1)
		local yaw = w * (B.yaw or 0) * wv(1, 0.25)
		local shift = w * (B.shift or 0) * H * wv(1)
		add(B.bone, CFrame.new(shift, y, 0) * ang(pitch, yaw, roll))
	end
	local SF = p.SwingFrac or 0.4
	for _, leg in p.Legs or {} do
		-- stride: swing forward quickly with the foot lifted (eased), then plant and push back at a steady speed
		local ph = (c + (leg.phase or 0)) % 1
		local sf = leg.swingFrac or SF
		local amp = leg.swing or 25
		local a, swingT, stanceT
		if ph < sf then
			local u = ph / sf
			local e = u * u * (3 - 2 * u)
			a = -amp + 2 * amp * e
			swingT = sin(math.pi * u)
			stanceT = 0
		else
			local u = (ph - sf) / (1 - sf)
			a = amp - 2 * amp * u
			swingT = 0
			stanceT = sin(math.pi * u)
		end
		a = w * a + i * (leg.idle or 0) * osc(1, leg.phase or 0)
		local lift = w * (leg.lift or 0.035) * H * swingT
		add(leg.bone, CFrame.new(0, lift, 0) * ang(a, 0, (leg.splay or 0)))
		if leg.knee then
			-- knee / wrist / hock folds through the swing and gives a little as the foot takes the weight;
			-- kneeDir -1 folds the lower leg back (front legs, bird and dino legs), +1 forward (hind hocks)
			local bend = (leg.bend or 35) * (swingT + 0.2 * stanceT)
			add(leg.knee, ang(w * bend * (leg.kneeDir or -1) + i * (leg.kneeIdle or 0) * osc(1, leg.phase or 0), 0, 0))
		end
	end
	for _, arm in p.Arms or {} do
		local ph = (c + (arm.phase or 0)) % 1
		add(arm.bone, ang(w * (arm.swing or 15) * cos(TAU * ph) + i * (arm.idle or 4) * osc(1, arm.phase or 0), 0, 0))
	end
	local N = p.Neck
	if N then
		local n = #N.bones
		for k, bone in N.bones do
			local f = 1 / n
			local yaw = i * (N.look or 8) * f * (osc(1, 0.1) * 0.7 + osc(2, 0.37) * 0.3)
			local pitch = i * (N.nod or 3) * f * osc(1, 0.6 + k * 0.08)
				+ w * (N.walkNod or 3) * f * wv(2, 0.5 + k * 0.05)
			local roll = (N.sway or 0) * f * (i * osc(1, 0.3 + k * 0.1) + w * wv(1, k * 0.1))
			add(bone, ang(pitch, yaw, roll))
		end
	end
	local Hd = p.Head
	if Hd then
		local yaw = i * (Hd.look or 10) * (osc(1, 0.1) * 0.7 + osc(2, 0.37) * 0.3)
		local pitch = i * (Hd.nod or 3) * osc(2, 0.6) + w * (Hd.walkNod or 3) * wv(2, 0.5)
		local roll = i * (Hd.tilt or 0) * osc(1, 0.8)
		add(Hd.bone, ang(pitch, yaw, roll))
	end
	local T = p.Tail
	if T then
		local axis = T.axis or "Y"
		for k, bone in T.bones do
			local lag = (T.lag or 0.12) * (k - 1)
			local a = i * (T.idle or 12) * osc(T.rate or 2, -lag) + w * (T.walk or 10) * wv(1, -lag)
			add(bone, axisAngle(axis, a) * ang(T.lift and (T.lift / #T.bones) or 0, 0, 0))
		end
	end
	local E = p.Ears
	if E then
		for k, bone in E.bones do
			local s = sideOf(bone)
			local tw = i * (E.twitch or 10) * max(0, osc(1, 0.2 + k * 0.33)) ^ 12
			local fl = w * (E.flop or 6) * wv(2, 0.3)
			add(bone, axisAngle(E.axis or "Z", s * (tw + fl)))
		end
	end
	local J = p.Jaw
	if J then
		local o = i * (J.open or 6) * max(0, osc(J.rate or 1, 0.4)) ^ 3 + w * (J.walkOpen or 2) * max(0, wv(2))
		add(J.bone, ang(-o, 0, 0)) -- (negative X rotation drops a jaw that points along -z)
	end
	for _, wing in p.Wings or {} do
		local s = wing.side or sideOf(wing.bone)
		local idleFlap = (wing.idle or 6) * osc(wing.idleRate or 1, 0)
		local walkFlap = (wing.walk or 10) * wv(wing.rate or 1, 0)
		local a = (wing.fold or 0) + i * idleFlap + w * walkFlap
		add(wing.bone, ang(0, 0, s * a))
		if wing.tip then
			local ta = i * (wing.idle or 6) * 0.6 * osc(wing.idleRate or 1, -0.12)
				+ w * (wing.walk or 10) * 0.6 * wv(wing.rate or 1, -0.12)
			add(wing.tip, ang(0, 0, s * ta))
		end
	end
	for _, x in p.Extra or {} do
		local s = x.mirror and sideOf(x.bone) or 1
		local a = (x.offset or 0)
			+ i * (x.idle or 0) * osc(x.rate or 1, x.phase or 0)
			+ w * (x.walk or 0) * wv(x.walkRate or 1, x.phase or 0)
		add(x.bone, axisAngle(x.axis or "Y", s * a))
	end
	return out
end

function A:Step(dt)
	local p = self.p
	self.w += (self.target - self.w) * math.min(dt * 4, 1)
	self.t = (self.t + dt) % (p.IdleLoop or 4)
	self.cycle = (self.cycle + dt * (p.StepRate or 1.6)) % 1
	local pose = A.Pose(p, self.height, self.t, self.cycle, self.w)
	-- mutation effect hubs (rays, orbiting crystals) spin continuously
	self.spin = (self.spin or 0) + dt
	pose.RayHub = CFrame.Angles(0, math.rad(self.spin * 16), 0)
	pose.OrbitHub = CFrame.Angles(0, math.rad(-self.spin * 40), 0)
	for name, m in self.motors do
		m.Transform = pose[name] or CFrame.identity
	end
end

function A:Destroy()
	for _, m in self.motors do
		m.Transform = CFrame.identity
	end
end

-- Bake a looping KeyframeSequence ("Idle" or "Walk") from the profile. Poses follow the Motor6D tree (RootPart first).
function A.Bake(model, profile, state, fps)
	fps = fps or 30
	local H = model:GetAttribute("Height") or 4
	local length = state == "Walk" and 1 / (profile.StepRate or 1.6) or (profile.IdleLoop or 4)
	local frames = math.max(2, math.floor(length * fps + 0.5))
	local motors = A.collect(model)
	local children = {}
	for _, m in motors do
		local parentName = m.Part0.Name
		children[parentName] = children[parentName] or {}
		table.insert(children[parentName], m)
	end
	local ks = Instance.new("KeyframeSequence")
	ks.Name = state
	ks.Loop = true
	ks.Priority = state == "Walk" and Enum.AnimationPriority.Movement or Enum.AnimationPriority.Idle
	for f = 0, frames do
		local time = f / frames * length
		local pose = state == "Walk" and A.Pose(profile, H, 0, f / frames, 1) or A.Pose(profile, H, time, 0, 0)
		local kf = Instance.new("Keyframe")
		kf.Time = time
		local function build(parentPose, partName)
			for _, m in children[partName] or {} do
				local ps = Instance.new("Pose")
				ps.Name = m.Part1.Name
				ps.CFrame = pose[m.Name] or CFrame.identity
				ps.Weight = 1
				ps.Parent = parentPose
				build(ps, m.Part1.Name)
			end
		end
		local rootPose = Instance.new("Pose")
		rootPose.Name = "RootPart"
		rootPose.Weight = 0
		rootPose.Parent = kf
		build(rootPose, "RootPart")
		kf.Parent = ks
	end
	return ks
end

return A
