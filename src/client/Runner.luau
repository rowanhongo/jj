--!strict
-- Local runner control. While State == "Running" the character always runs forward along
-- `heading`. The stick or A/D steers sideways, Space/W/Up jumps, and S/Down/C slides.
-- Steering into a corner's turn direction inside its Junction turns you 90°.
-- Running into a corner's dead end forces the turn and stumbles you. Clipping a hurdle,
-- a log or a side wall stumbles you. An empty juice meter stumbles you every few seconds.
-- The camera is the default Roblox camera; this script never touches it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local Runner = {}
Runner.onStumble = Instance.new("BindableEvent")
Runner.onShield = Instance.new("BindableEvent")
Runner.onPickup = Instance.new("BindableEvent")

local controls: any = nil
task.spawn(function()
	local ok, mod = pcall(function()
		-- Newer Studio builds keep PlayerModule under StarterPlayer instead of PlayerScripts.
		local ps = player:WaitForChild("PlayerScripts")
		local mod = ps:FindFirstChild("PlayerModule") or game:GetService("StarterPlayer"):FindFirstChild("PlayerModule") or ps:WaitForChild("PlayerModule")
		return (require(mod :: ModuleScript) :: any):GetControls()
	end)
	if ok then
		controls = mod
	end
end)

local heading = Vector3.new(0, 0, -1)
local slideUntil = 0
local stumbleUntil = 0
local lastWallBump = 0
local lastEmptyStumble = 0
local usedJunctions: { [Instance]: boolean } = {}
local hitObstacles: { [Instance]: boolean } = {}
local collected: { [number]: boolean } = {}
local lastSteerSign = 0
local lastSteerTime = 0
local headingMismatchSince = 0
local baseHip: number? = nil
local wasRunning = false

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local function snapQuarter(v: Vector3): Vector3
	if math.abs(v.X) > math.abs(v.Z) then
		return Vector3.new(math.sign(v.X), 0, 0)
	end
	return Vector3.new(0, 0, math.sign(v.Z))
end

local function rightOf(h: Vector3): Vector3
	return h:Cross(Vector3.yAxis)
end

local pendingTurn: { junction: BasePart, dir: number }? = nil
local assistCentre: Vector3? = nil
local assistUntil = 0

-- dir +1 = right, -1 = left. After turning, steer toward the new corridor's centreline
-- for a moment (Temple Run style) so the runner never scrapes the exit's walls.
local function turnAt(dir: number, junction: BasePart)
	heading = snapQuarter(dir == 1 and rightOf(heading) or -rightOf(heading))
	assistCentre = junction.Position
	assistUntil = os.clock() + 0.6
end

function Runner.stumble(reason: string)
	local t = os.clock()
	if t < stumbleUntil then
		return
	end
	if (player:GetAttribute("Shields") or 0) > 0 then
		remotes.UseShield:FireServer()
		stumbleUntil = t + 0.4 -- brief grace so one obstacle eats one shield
		Runner.onShield:Fire()
		return
	end
	stumbleUntil = t + Config.StumbleSeconds
	Runner.onStumble:Fire(reason)
end

function Runner.isSliding(): boolean
	return os.clock() < slideUntil
end

local function running(): boolean
	return player:GetAttribute("State") == "Running"
end

local function slide()
	if not running() then
		return
	end
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum and hum.FloorMaterial ~= Enum.Material.Air then
		slideUntil = os.clock() + Config.SlideSeconds
	end
end

local function jump()
	if not running() then
		return
	end
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum then
		slideUntil = 0
		hum.Jump = true
	end
end

local function resetRun()
	heading = Vector3.new(0, 0, -1)
	slideUntil, stumbleUntil = 0, 0
	usedJunctions, hitObstacles, collected = {}, {}, {}
	headingMismatchSince = 0
	pendingTurn, assistCentre, assistUntil = nil, nil, 0
end

local function step()
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local isRunning = running()
	if isRunning ~= wasRunning then
		wasRunning = isRunning
		resetRun()
		if hum then
			if isRunning then
				baseHip = hum.HipHeight
				hum.AutoRotate = true
			elseif baseHip then
				hum.HipHeight = baseHip
				hum.WalkSpeed = 16
			end
		end
	end
	if not isRunning or not hum or not root then
		return
	end
	local t = os.clock()

	-- Input
	-- Keyboard and gamepad are read directly (the control module's move vector stayed zero
	-- in testing); touch falls back to the control module's thumbstick.
	local steer = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		steer -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		steer += 1
	end
	if steer == 0 then
		for _, io in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if io.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(io.Position.X) > 0.15 then
				steer = io.Position.X
			end
		end
	end
	if steer == 0 and controls then
		local mv = controls:GetMoveVector()
		steer = mv.X
	end
	steer = math.clamp(steer, -1, 1)
	if math.abs(steer) > 0.45 then
		local s = math.sign(steer)
		if s ~= lastSteerSign or t - lastSteerTime > 0.05 then
			lastSteerSign = s
		end
		lastSteerTime = t
	end

	-- Speed
	local speed = player:GetAttribute("RunSpeed") or Config.RunSpeedStart
	if t < stumbleUntil then
		speed *= Config.StumbleSpeedMul
	end
	if workspace:GetServerTimeNow() < (player:GetAttribute("SlowUntil") or 0) then
		speed *= Config.DartSlowMul
	end

	-- Slide pose (greybox: drop the hip so the body ducks under logs)
	local sliding = t < slideUntil
	if baseHip and baseHip > 1 then
		hum.HipHeight = sliding and math.max(0.4, baseHip - 1.6) or baseHip
	end

	-- Sensors: one box around the body (shorter while sliding) and one wider box for bottles.
	local path = workspace:FindFirstChild("Path")
	if path then
		params.FilterDescendantsInstances = { path }
		local feetY = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
		local bodyTop = sliding and 2.3 or 4.8
		local centre = Vector3.new(root.Position.X, feetY + 0.3 + (bodyTop - 0.3) / 2, root.Position.Z)
		local parts = workspace:GetPartBoundsInBox(CFrame.new(centre), Vector3.new(3, bodyTop - 0.3, 3), params)
		for _, part in parts do
			if CollectionService:HasTag(part, "Junction") then
				local dir = part:GetAttribute("Turn") :: number
				if not usedJunctions[part] and lastSteerSign == dir and t - lastSteerTime < 0.35 then
					-- Queue it: the turn happens once we reach the corner's centre, so we
					-- never cut the corner into the wall ends.
					usedJunctions[part] = true
					pendingTurn = { junction = part :: BasePart, dir = dir }
				end
			elseif CollectionService:HasTag(part, "TurnWall") then
				local j = part.Parent and part.Parent:FindFirstChild("Junction") :: BasePart?
				if j and pendingTurn and pendingTurn.junction == j then
					-- Turn was queued, just execute it now.
					turnAt(pendingTurn.dir, j)
					pendingTurn = nil
				elseif j and not usedJunctions[j] then
					-- Missed the corner: forced turn, stumble.
					usedJunctions[j] = true
					turnAt(part:GetAttribute("Turn") :: number, j)
					Runner.stumble("Missed the turn")
				end
			elseif CollectionService:HasTag(part, "Hurdle") then
				if not hitObstacles[part] then
					hitObstacles[part] = true
					Runner.stumble("Tripped")
				end
			elseif CollectionService:HasTag(part, "Duck") then
				if not hitObstacles[part] then
					hitObstacles[part] = true
					Runner.stumble("Bonk")
				end
			elseif CollectionService:HasTag(part, "Wall") then
				local side = part:GetAttribute("Side") :: number
				local toward = math.sign(steer) == side and math.abs(steer) > 0.2
				if toward and t - lastWallBump > Config.WallBumpCooldown then
					lastWallBump = t
					Runner.stumble("Bumped a wall")
				end
			end
		end
		local near = workspace:GetPartBoundsInBox(root.CFrame, Vector3.new(Config.BottlePickupRadius, 8, Config.BottlePickupRadius), params)
		for _, part in near do
			if CollectionService:HasTag(part, "Bottle") then
				local id = part:GetAttribute("BottleId") :: number
				if id and not collected[id] then
					collected[id] = true
					part.LocalTransparencyModifier = 1
					Runner.onPickup:Fire(part:GetAttribute("Kind") or "Juice")
					remotes.Collect:FireServer(id)
				end
			end
		end

		-- Safety: if the floor under us has a heading we don't match for a while
		-- (outside corners), snap to it.
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { path }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), rp)
		local floorHeading = hit and hit.Instance:GetAttribute("Heading") :: Vector3?
		local onCorner = hit and hit.Instance:GetAttribute("Corner")
		if onCorner or pendingTurn or t < assistUntil then
			headingMismatchSince = 0
		elseif floorHeading then
			local fh = snapQuarter(floorHeading)
			if fh:Dot(heading) < 0.9 then
				if headingMismatchSince == 0 then
					headingMismatchSince = t
				elseif t - headingMismatchSince > 0.6 then
					heading = fh
					headingMismatchSince = 0
				end
			else
				headingMismatchSince = 0
			end
		end
	end

	-- Juice empty: stumble every few seconds
	if (player:GetAttribute("Juice") or 100) <= 0 and t - lastEmptyStumble > Config.EmptyStumbleEvery then
		lastEmptyStumble = t
		Runner.stumble("Out of juice")
	end

	-- Queued turn executes at the corner's centre line.
	local pt = pendingTurn
	if pt then
		if not pt.junction.Parent then
			pendingTurn = nil
		elseif (root.Position - pt.junction.Position):Dot(heading) >= -2 then
			turnAt(pt.dir, pt.junction)
			pendingTurn = nil
		end
	end
	-- Hold the middle while a turn is queued; after turning, pull to the new centreline.
	if pendingTurn then
		local off = (root.Position - pendingTurn.junction.Position):Dot(rightOf(heading))
		steer = math.clamp(-off / 4, -1, 1)
	elseif assistCentre and t < assistUntil then
		local off = (root.Position - assistCentre):Dot(rightOf(heading))
		steer = math.abs(off) > 0.5 and math.clamp(-off / 4, -1, 1) or 0
	end

	-- Drive: forward along heading plus sideways steer, forward speed kept constant.
	local dir = heading + rightOf(heading) * steer * Config.SteerFactor
	hum.WalkSpeed = speed * dir.Magnitude
	hum:Move(dir.Unit, false)
end

function Runner.init()
	-- After the PlayerModule's control step (Input priority) so our Move wins each frame.
	RunService:BindToRenderStep("JJRunner", Enum.RenderPriority.Character.Value + 1, step)

	ContextActionService:BindAction("JJSlide", function(_, state)
		if state == Enum.UserInputState.Begin then
			slide()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.S, Enum.KeyCode.Down, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("JJSlide", "Slide")
	ContextActionService:SetPosition("JJSlide", UDim2.new(1, -170, 1, -90))

	ContextActionService:BindAction("JJJump", function(_, state)
		if state == Enum.UserInputState.Begin then
			jump()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.W, Enum.KeyCode.Up)
end

return Runner
