--!strict
-- Tiger charge (Segments.tiger). When the first runner reaches a tiger piece the server starts
-- one charge (Remotes.Tiger) and every client draws the same tiger: it appears at the far end of
-- the piece in a side lane and bounds back down the path through the whole field. Change lane to
-- let it past; if it reaches you, you are taken out (Remotes.TigerHit). Bots are checked by the
-- server with the same numbers (BotService: TIGER_START, TIGER_SPEED).
--
-- The model is ReplicatedStorage.Assets.TigerRig: an R6-style rig (Torso, Head, Left/Right Arm =
-- front legs, Left/Right Leg = back legs, joined by Motor6Ds) with its scripts stripped. The
-- gallop is driven here in code: front and back pairs swing opposite each other, the body rises
-- and rocks each stride, the head dips and the root bobs.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local LANE = Config.PathWidth / 3
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local Tiger = {}
Tiger.onWarn = Instance.new("BindableEvent") -- fired once per charge, only while it is still ahead of you

local SCALE = 1.25
local CHARGE_SPEED = 72 -- studs/s toward the runners (BotService.TIGER_SPEED)
local START = 135 -- studs along the piece where it appears (BotService.TIGER_START)
local STRIDES_PER_SEC = 2.3 -- gallop cycles per second
local ROOT_UP = 3.45 -- rig root height above the ground at scale 1
local ROAR = "rbxassetid://2184044761"

-- Rotary gallop, as big cats run: footfalls go left hind, right hind, right fore, left fore,
-- then a moment with all four in the air. Each leg spends STANCE of the cycle on the ground,
-- sweeping back from forward-reach to push-off; the rest it is lifted (raised, not just turned)
-- and carried forward to reach again. OFFSET = where in the cycle each leg lands.
local STANCE = 0.38
local REACH = 0.55 -- radians forward/back of vertical at landing/push-off
local LEGS = {
	["Left Leg"] = { offset = 0.0, lift = 0.9 }, -- hind
	["Right Leg"] = { offset = 0.1, lift = 0.9 },
	["Right Arm"] = { offset = 0.42, lift = 1.3 }, -- fore: tucked higher
	["Left Arm"] = { offset = 0.52, lift = 1.3 },
}
local JOINT_OF = {
	["Left Hip"] = "Left Leg",
	["Right Hip"] = "Right Leg",
	["Left Shoulder"] = "Left Arm",
	["Right Shoulder"] = "Right Arm",
}

-- Each leg turns about the tiger's sideways axis through the top of its visible meshes (the
-- rig's own joints sit away from the leg meshes, so a plain joint rotation flings the leg off),
-- and lifts along the tiger's up axis.
type Leg = { joint: Motor6D, pivot: Vector3, axis: Vector3, up: Vector3, offset: number, lift: number }
type Rig = { model: Model, root: BasePart, legs: { Leg } }

local function spawnRig(parent: Instance): Rig?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local t = assets and assets:FindFirstChild("TigerRig") :: Model?
	if not t then
		return nil
	end
	local m = t:Clone()
	m:ScaleTo(SCALE)
	m.Parent = parent
	local root = m.PrimaryPart :: BasePart
	local legs: { Leg } = {}
	for _, j in m:GetDescendants() do
		local spec = j:IsA("Motor6D") and j.Part0 and j.Part1 and LEGS[JOINT_OF[j.Name] or ""]
		if spec then
			local sum, n, top = Vector3.zero, 0, -math.huge
			for _, p in j.Part1:GetDescendants() do
				if p:IsA("BasePart") then
					sum += p.Position
					n += 1
					top = math.max(top, p.Position.Y + p.Size.Y / 2)
				end
			end
			if n > 0 then
				local c = sum / n
				local frame = j.Part0.CFrame * j.C0
				table.insert(legs, {
					joint = j,
					pivot = frame:PointToObjectSpace(Vector3.new(c.X, top - 0.4 * SCALE, c.Z)),
					axis = frame:VectorToObjectSpace(root.CFrame.RightVector),
					up = frame:VectorToObjectSpace(root.CFrame.UpVector),
					offset = spec.offset,
					lift = spec.lift * SCALE,
				})
			end
		end
	end
	local roar = Instance.new("Sound")
	roar.SoundId = ROAR
	roar.Volume = 3
	roar.RollOffMinDistance = 40
	roar.RollOffMaxDistance = 500
	require(script.Parent.Settings).asSfx(roar)
	roar.Parent = root
	roar:Play()
	return { model = m, root = root, legs = legs }
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

-- Pose the rig at ground point `at` facing `dir`, `cycle` = gallop cycles so far.
local function gallop(r: Rig, at: Vector3, dir: Vector3, cycle: number)
	for _, l in r.legs do
		local u = (cycle + l.offset) % 1
		local angle, lift
		if u < STANCE then
			-- on the ground: sweep from reach (forward) to push-off (back)
			angle = REACH * (1 - 2 * u / STANCE)
			lift = 0
		else
			-- in the air: raise the leg and carry it forward
			local v = (u - STANCE) / (1 - STANCE)
			angle = -REACH + 2 * REACH * smooth(v)
			lift = l.lift * math.sin(math.pi * v)
		end
		l.joint.Transform = CFrame.new(l.up * lift)
			* CFrame.new(l.pivot)
			* CFrame.fromAxisAngle(l.axis, angle)
			* CFrame.new(-l.pivot)
	end
	-- body: rises in the flight after the fore legs push off, nose dips as the fores land
	local c = cycle % 1
	local bob = 0.35 + 0.35 * math.cos(2 * math.pi * (c - 0.85))
	local pitch = 0.07 * math.sin(2 * math.pi * (c - 0.3))
	local pos = at + Vector3.new(0, ROOT_UP * SCALE + bob, 0)
	r.root.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(pitch, 0, 0)
end

local function charge(zone: BasePart, t0: number)
	local player = Players.LocalPlayer
	local dir = zone:GetAttribute("Dir") :: Vector3
	local right = zone:GetAttribute("Right") :: Vector3
	local origin = zone:GetAttribute("Origin") :: Vector3
	local lane = zone:GetAttribute("Lane") :: number
	local model = zone.Parent
	if not (dir and right and origin and lane and model) then
		return
	end
	local r = spawnRig(model)
	if not r then
		return
	end
	local x = lane * LANE
	local hit = false
	local warned = false
	local conn: RBXScriptConnection
	-- Stepped runs before the animation step, so the Motor6D Transforms we set are drawn
	conn = RunService.Stepped:Connect(function()
		local el = workspace:GetServerTimeNow() - t0
		local along = START - CHARGE_SPEED * el
		local cycle = STRIDES_PER_SEC * el
		local at = origin + dir * along + right * x
		gallop(r, at, -dir, cycle)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not warned then
			warned = true
			-- only warn if it is still coming: tiger further along the piece than you, with room
			if (at - root.Position):Dot(dir) > 25 and player:GetAttribute("State") == "Running" then
				Tiger.onWarn:Fire()
			end
		end
		if root and not hit then
			local d = root.Position - at
			local mine = player:GetAttribute("State") == "Running"
			if mine and math.abs(d:Dot(dir)) < 3 and math.abs(d:Dot(right)) < 2.2 and math.abs(d.Y) < 7 then
				hit = true
				remotes.TigerHit:FireServer()
			end
		end
		-- gone once it has run back past the start of its piece (or the piece was cleared away)
		if along < -30 or not r.model.Parent or not model.Parent then
			conn:Disconnect()
			r.model:Destroy()
		end
	end)
end

function Tiger.init()
	remotes:WaitForChild("Tiger").OnClientEvent:Connect(function(zone: BasePart, t0: number)
		if zone and zone.Parent then
			charge(zone, t0)
		end
	end)
end

return Tiger
