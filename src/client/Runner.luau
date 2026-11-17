--!strict
-- Local runner control. While State == "Running" the character always runs forward along
-- `heading`. The stick or A/D steers sideways, Space/W/Up jumps, and S/Down/C slides.
-- Steering into a corner's turn direction inside its Junction turns you 90°.
-- Running into a corner's dead end forces the turn and stumbles you. Clipping
-- a log or a side wall stumbles you. An empty juice meter stumbles you every few seconds.
-- The camera: during a run JJRunCam keeps it looking down the path (only corners turn it).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Sfx = require(script.Parent.Sfx)
local Settings = require(script.Parent.Settings)
local ActionButton = require(script.Parent.ActionButton)

-- Why running looked fast but felt slow: Roblox's Animate script plays the run cycle at
-- WalkSpeed / 16, so at our run speed (35+) the legs cycle 2.2x+ too fast and look like a
-- sprint while the ground goes by at the same rate. During a run the run/walk tracks are held
-- to RUN_ANIM_MAX, and the camera widens with speed so the speed reads on screen.
local RUN_ANIM_MAX = 1.3
local FOV_BASE, FOV_RUN = 70, 84

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local Runner = {}
Runner.onStumble = Instance.new("BindableEvent")
Runner.onPickup = Instance.new("BindableEvent")
Runner.onWarn = Instance.new("BindableEvent") -- (text, zone part): a hazard warning volume was entered

local controls: any = nil
task.spawn(function()
	local ok, mod = pcall(function()
		-- Newer Studio builds keep PlayerModule under StarterPlayer instead of PlayerScripts.
		local ps = player:WaitForChild("PlayerScripts")
		local mod = ps:FindFirstChild("PlayerModule")
			or game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
			or ps:WaitForChild("PlayerModule")
		return (require(mod :: ModuleScript) :: any):GetControls()
	end)
	if ok then
		controls = mod
	end
end)

-- Touch steering (phones): the default thumbstick has a dead zone and a fixed spot, and its
-- move vector lags, so during a run we read the finger ourselves. Put a thumb down anywhere
-- on the left 60% of the screen (not on a button) and drag: the sideways offset from where it
-- landed is the steer, full at TOUCH_FULL px. A quick flick left/right is a turn press (like
-- tapping A/D at a corner), a flick up jumps and a flick down slides.
local TOUCH_FULL = 55
local STEER_REACH = { 1.6, 1.3, 1, 0.8, 0.6 }
local touchId: InputObject? = nil
local touchStart = Vector2.zero
local touchAnchor = Vector2.zero
local touchStartTime = 0
local touchSteer = 0
local flickSign, flickTime = 0, 0
local arrowSteer: (number) -> number

local heading = Vector3.new(0, 0, -1)
local slideUntil = 0
local SLIDE_ANIM = "rbxassetid://131203084107880"
-- The slide clip is loaded ONCE per Animator and kept. (Loading it again every frame piled up
-- tracks until the Animator hit its limit and every animation froze: the "standing stiff,
-- floating" bug.) It never loops, and it is stopped whenever a run ends.
local slideTrack: AnimationTrack? = nil
local slideAnimator: Animator? = nil
local function slideTrackFor(hum: Humanoid): AnimationTrack?
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	if slideAnimator ~= animator then
		if slideTrack then
			slideTrack:Stop(0)
			slideTrack:Destroy()
		end
		local a = Instance.new("Animation")
		a.AnimationId = SLIDE_ANIM
		slideTrack = animator:LoadAnimation(a)
		slideAnimator = animator
		local tr = slideTrack :: AnimationTrack
		tr.Priority = Enum.AnimationPriority.Action4
		tr.Looped = false
	end
	return slideTrack
end
-- The clip is downloaded and loaded as soon as each character spawns, so the very first slide
-- plays it straight away (it used to sink into the greybox pose while it downloaded).
task.spawn(function()
	local a = Instance.new("Animation")
	a.AnimationId = SLIDE_ANIM
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ a })
	end)
end)
local function warmSlide(char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum:WaitForChild("Animator", 10)
		local tr = slideTrackFor(hum)
		if tr then
			-- play it once at zero weight so the clip is fully decoded before it is needed
			tr:Play(0, 0.001, 1)
			task.delay(0.1, function()
				tr:Stop(0)
			end)
		end
	end
end
if player.Character then
	task.spawn(warmSlide, player.Character)
end
player.CharacterAdded:Connect(warmSlide)
local function stopSlideAnim()
	if slideTrack and slideTrack.IsPlaying then
		slideTrack:Stop(0.1)
	end
end
local stumbleUntil = 0
local lastWallBump = 0
local lastEmptyStumble = 0
local emptyPulses = 0 -- out-of-juice stumbles in a row; after 4 you start slowing down
local usedJunctions: { [Instance]: boolean } = {}
local hitObstacles: { [Instance]: boolean } = {}
local collected: { [number]: boolean } = {}
local lastSteerSign = 0
local lastSteerTime = 0
local headingMismatchSince = 0
local baseHip: number? = nil
local wasRunning = false
local lastLeap = 0
local lastRocket = 0
local flyY: number? = nil
local lastGroundY: number? = nil -- where you last stood: Glider lifts you back up to it
local tarUntil = 0
local mudUntil = 0 -- on the mud slide: faster
local windUntil, windSide, windRight = 0, 0, Vector3.zero -- in a wind gust stretch
local lastClock = os.clock()
local wasFov = false

-- Zipline ride (see Segments.zipline). Cables are parallel; lane 1 is leftmost.
local ZIP_HANG = 4.6
local ZIP_SWITCH = 0.28
type Zip = { cables: { BasePart }, lane: number, s: number, from: number?, swStart: number, held: boolean }
local zip: Zip? = nil

-- Vine swing (see Segments.vines). s runs along the swing direction from the first pivot; on
-- vine k the hand sits on a circle of radius len round its pivot. Hand-over at the midpoint.
local VINE_HANG = 4.6
type Vine = { parts: { BasePart }, dir: Vector3, gap: number, len: number, s: number, endS: number }
local vine: Vine? = nil
local vineK = 0 -- the vine in hand (a swing sound on each catch)

local function cableAB(c: BasePart): (Vector3, Vector3)
	return c:GetAttribute("A") :: Vector3, c:GetAttribute("B") :: Vector3
end

local function zipPos(c: BasePart, s: number): Vector3
	local a, b = cableAB(c)
	return a + (b - a).Unit * s
end

-- Hanging pose for ziplines and vines: the character's own jump clip (arms up), held still on
-- its arms-up frame for the whole ride. Loaded once per Animator, like the slide clip.
local hangTrack: AnimationTrack? = nil
local hangAnimator: Animator? = nil
local function startHang(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	if hangAnimator ~= animator then
		if hangTrack then
			hangTrack:Destroy()
		end
		local animate = hum.Parent and hum.Parent:FindFirstChild("Animate")
		local src = animate and animate:FindFirstChild("jump")
		local clip = src and src:FindFirstChildOfClass("Animation")
		if not clip then
			return
		end
		hangTrack = animator:LoadAnimation(clip)
		hangAnimator = animator
		local tr = hangTrack :: AnimationTrack
		tr.Priority = Enum.AnimationPriority.Action4
		tr.Looped = true
	end
	local tr = hangTrack :: AnimationTrack
	if not tr.IsPlaying then
		tr:Play(0.15)
	end
	-- hold the arms-up frame (most of the way through the clip)
	task.defer(function()
		if tr.IsPlaying then
			tr.TimePosition = tr.Length * 0.6
			tr:AdjustSpeed(0)
		end
	end)
end
local function stopHang()
	if hangTrack and hangTrack.IsPlaying then
		hangTrack:Stop(0.2)
	end
end

local function endVine(hum: Humanoid?)
	local v = vine
	vine = nil
	if v then
		for _, p in v.parts do
			p.CFrame = p:GetAttribute("Rest") :: CFrame
		end
	end
	if hum and not zip then
		hum.PlatformStand = false
	end
	if not zip then
		stopHang()
	end
end

local zipSound: Sound? = nil
local function endZip(hum: Humanoid?)
	zip = nil
	if not vine then
		stopHang()
	end
	if zipSound then
		zipSound:Destroy()
		zipSound = nil
	end
	if hum then
		hum.PlatformStand = false
	end
end

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

-- Corner turns are a short curve, not a snap. The runner follows a quadratic arc:
-- from where they are, through the corner point on their current line, to the new
-- corridor's centreline. Duration = arc length / speed (clamped), so fast runs don't
-- overshoot. The camera swings 90° a bit faster than the runner and leans ~8° into the
-- turn, so the new path is in view straight away. Steering input is locked meanwhile.
type Turn = { p0: Vector3, c: Vector3, pe: Vector3, h0: Vector3, h1: Vector3, dir: number, dur: number, start: number }
local turning: Turn? = nil
local TURN_ROLL = math.rad(8)
local turnRoll = 0
local turnCamLook = Vector3.new(0, 0, -1)

local function easeOutCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

local function turnAt(dir: number, junction: BasePart)
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local h0 = heading
	local h1 = snapQuarter(dir == 1 and rightOf(h0) or -rightOf(h0))
	heading = h1
	if not root then
		return
	end
	local p0 = root.Position
	local centre = Vector3.new(junction.Position.X, p0.Y, junction.Position.Z)
	-- depth < 0 means we are already past the centre (e.g. hit the dead end): the corner is
	-- then where we stand, and the lead-out is long enough to keep the curve under 45°.
	local depth = (centre - p0):Dot(h0)
	local cornerDepth = math.max(depth, 0)
	local corner = p0 + h0 * cornerDepth
	local lead = math.max(cornerDepth, math.abs(depth), 4)
	local pe = centre + h1 * ((corner - centre):Dot(h1) + lead)
	local len = (corner - p0).Magnitude + (pe - corner).Magnitude
	local speed = math.max(player:GetAttribute("RunSpeed") or Config.RunSpeedStart, 10)
	turning = {
		p0 = p0,
		c = corner,
		pe = pe,
		h1 = h1,
		dir = dir,
		dur = math.clamp(len / speed, 0.18, 0.35),
		start = os.clock(),
		h0 = h0,
	}
end

-- One frame of an active turn. Returns true while the turn is still running.
local function turnFrame(root: BasePart, hum: Humanoid, speed: number): boolean
	local tr = turning :: Turn
	local el = os.clock() - tr.start
	local u = math.min(el / tr.dur, 1)
	local e = easeOutCubic(u)
	local a, b = tr.p0:Lerp(tr.c, e), tr.c:Lerp(tr.pe, e)
	local pos = a:Lerp(b, e)
	local tangent = (b - a)
	tangent = tangent.Magnitude > 1e-3 and tangent.Unit or tr.h1
	local p = Vector3.new(pos.X, root.Position.Y, pos.Z)
	root.CFrame = CFrame.lookAt(p, p + tangent)
	root.AssemblyLinearVelocity = tangent * speed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
	hum.WalkSpeed = speed
	hum:Move(tangent, false)

	-- the camera's direction follows the same curve in the same time (drawn in JJRunCam)
	turnCamLook = CFrame.Angles(0, -tr.dir * e * math.pi / 2, 0):VectorToWorldSpace(tr.h0)
	turnRoll = if u < 1 then -TURN_ROLL * math.sin(math.pi * u) * tr.dir else 0
	if u >= 1 then
		turning = nil
		return false
	end
	return true
end

local shieldUsedAt = -99
function Runner.stumble(reason: string)
	local t = os.clock()
	if t < stumbleUntil then
		return
	end
	-- a Shell Shield takes the bump (the server clears it and every client pops it)
	if player:GetAttribute("Shield") and t - shieldUsedAt > 1 then
		shieldUsedAt = t
		stumbleUntil = t + 0.4 -- a short grace so the same obstacle doesn't hit twice
		remotes:WaitForChild("ShieldPop"):FireServer()
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
		if os.clock() > slideUntil then
			Sfx.play("Slide")
		end
		slideUntil = os.clock() + Config.SlideSeconds
	end
end

-- Jump buffer + coyote time: a press counts for 0.2 s (so pressing just before landing still
-- jumps), and you can still jump 0.12 s after running off an edge or over a seam between tiles.
-- The jump is started with ChangeState, which acts this frame (Humanoid.Jump waits for the
-- humanoid's own state update).
local jumpWanted = -1
local lastGrounded = -1
-- Just after a jump the feet still read the floor for a few frames (FloorMaterial lags), which
-- let a quick second tap jump again in mid-air. The floor doesn't count until this long after.
local lastJumpAt = -1
local JUMP_LOCK = 0.35
local function jump()
	if not running() then
		return
	end
	jumpWanted = os.clock()
end

local function resetRun()
	heading = Vector3.new(0, 0, -1)
	slideUntil, stumbleUntil = 0, 0
	stopSlideAnim()
	usedJunctions, hitObstacles, collected = {}, {}, {}
	headingMismatchSince = 0
	turning = nil
	tarUntil, mudUntil, windUntil = 0, 0, 0
	local c = player.Character
	endZip(c and c:FindFirstChildOfClass("Humanoid"))
	endVine(c and c:FindFirstChildOfClass("Humanoid"))
end

local function grabZip(trigger: Instance, root: BasePart, hum: Humanoid)
	local folder = trigger.Parent and trigger.Parent:FindFirstChild("Zips")
	if not folder then
		return
	end
	local cables: { BasePart } = {}
	for _, c in folder:GetChildren() do
		if c:IsA("BasePart") and c:GetAttribute("Lane") then
			cables[c:GetAttribute("Lane") :: number] = c
		end
	end
	if #cables == 0 then
		return
	end
	local right = rightOf(heading)
	local best, bestD = 1, math.huge
	for lane, c in cables do
		local a = cableAB(c)
		local d = math.abs((root.Position - a):Dot(right))
		if d < bestD then
			best, bestD = lane, d
		end
	end
	local a, b = cableAB(cables[best])
	local s = math.max(0, (root.Position - a):Dot((b - a).Unit))
	zip = { cables = cables, lane = best, s = s, from = nil, swStart = 0, held = true }
	hum.PlatformStand = true
	startHang(hum)
	if zipSound then
		zipSound:Destroy()
	end
	zipSound = Sfx.play("Zip")
end

local function grabVine(trigger: Instance, root: BasePart, hum: Humanoid)
	local folder = trigger.Parent and trigger.Parent:FindFirstChild("Vines")
	if not folder then
		return
	end
	local parts: { BasePart } = {}
	for i = 1, trigger:GetAttribute("N") :: number do
		local p = folder:FindFirstChild("V" .. i) :: BasePart?
		if not p then
			return
		end
		parts[i] = p
	end
	local gap = trigger:GetAttribute("Gap") :: number
	local dir = trigger:GetAttribute("Dir") :: Vector3
	local p1 = parts[1]:GetAttribute("Pivot") :: Vector3
	-- start where you are along the swing (never before the first catch point)
	local s = math.clamp((root.Position - p1):Dot(dir), -gap / 2, 0)
	vine = {
		parts = parts,
		dir = dir,
		gap = gap,
		len = trigger:GetAttribute("Len") :: number,
		s = s,
		endS = (#parts - 1) * gap + gap / 2,
	}
	hum.PlatformStand = true
	vineK = 0
	startHang(hum)
end

-- One frame on the vines: faster at the bottom of each swing, slower near the top.
local function vineFrame(root: BasePart, hum: Humanoid, speed: number, dt: number)
	local v = vine :: Vine
	local k = math.clamp(math.floor((v.s + v.gap / 2) / v.gap) + 1, 1, #v.parts)
	local pivot = v.parts[k]:GetAttribute("Pivot") :: Vector3
	if k ~= vineK then
		vineK = k
		Sfx.play("Vine")
	end
	local dz = v.s - (k - 1) * v.gap
	local drop = math.sqrt(math.max(v.len * v.len - dz * dz, 0))
	-- pendulum feel: 0.75x at the catch height, ~1.25x at the bottom
	local lowest = v.len - math.sqrt(v.len * v.len - (v.gap / 2) ^ 2)
	local depth = (drop - (v.len - lowest)) / lowest
	v.s += speed * (0.75 + 0.5 * depth) * dt
	local hand = pivot + v.dir * dz - Vector3.new(0, drop, 0)
	-- the vine you hold points at your hand; the others hang still
	for i, p in v.parts do
		if i == k then
			p.CFrame = CFrame.lookAt((pivot + hand) / 2, hand) * CFrame.Angles(math.pi / 2, 0, 0)
		else
			p.CFrame = p:GetAttribute("Rest") :: CFrame
		end
	end
	if v.s >= v.endS then
		-- thrown off the last vine onto the far ledge
		endVine(hum)
		root.CFrame = CFrame.lookAt(hand - Vector3.new(0, VINE_HANG, 0), hand - Vector3.new(0, VINE_HANG, 0) + heading)
		root.AssemblyLinearVelocity = heading * speed + Vector3.new(0, 16, 0)
		return
	end
	local at = hand - Vector3.new(0, VINE_HANG, 0)
	-- lean into the swing
	local tilt = math.atan2(dz, drop)
	root.CFrame = CFrame.lookAt(at, at + heading) * CFrame.Angles(-tilt * 0.5, 0, 0)
	root.AssemblyLinearVelocity = v.dir * speed
end

-- One frame on the zipline: slide up the cable, hop lanes on a left/right press, drop at a cut.
local function zipFrame(root: BasePart, hum: Humanoid, speed: number, steer: number, dt: number)
	local z = zip :: Zip
	local t = os.clock()
	local pressed = math.abs(steer) > 0.5
	if pressed and not z.held and not z.from then
		local target = z.lane + math.sign(steer)
		if z.cables[target] then
			z.from = z.lane
			z.lane = target
			z.swStart = t
		end
	end
	z.held = pressed
	local cable = z.cables[z.lane]
	local a, b = cableAB(cable)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	z.s += speed * dt
	local p = zipPos(cable, z.s)
	if z.from then
		local u = math.min((t - z.swStart) / ZIP_SWITCH, 1)
		local e = easeOutCubic(u)
		p = zipPos(z.cables[z.from], z.s):Lerp(p, e) + Vector3.new(0, 2.2 * math.sin(math.pi * u), 0)
		if u >= 1 then
			z.from = nil
		end
	end
	local cut = cable:GetAttribute("Cut") :: number
	if not z.from and cut < 1 and z.s >= len * cut then
		-- The line snapped: let go and fall.
		endZip(hum)
		root.AssemblyLinearVelocity = dir * speed * 0.5 + Vector3.new(0, -4, 0)
		Runner.onStumble:Fire("The line snapped!")
		return
	end
	if z.s >= len then
		endZip(hum)
		root.CFrame = CFrame.lookAt(p, p + heading) * CFrame.new(0, -ZIP_HANG + 3, -2)
		root.AssemblyLinearVelocity = heading * speed + Vector3.new(0, 10, 0)
		return
	end
	local at = p - Vector3.new(0, ZIP_HANG, 0)
	root.CFrame = CFrame.lookAt(at, at + heading)
	root.AssemblyLinearVelocity = dir * speed
end

-- Juice, gems and boxes near you. Called every frame, also while swinging on a vine or riding a
-- zipline (those return early from step), with a tall box so cans over a jump still count.
local function collectNear(root: BasePart)
	local path = workspace:FindFirstChild("Path")
	if not path then
		return
	end
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { path }
	local r = Config.BottlePickupRadius + 2
	local magnet = workspace:GetServerTimeNow() < (player:GetAttribute("MagnetUntil") or 0)
	local box = if magnet then Vector3.new(60, 24, 60) else Vector3.new(r, 14, r)
	for _, part in workspace:GetPartBoundsInBox(root.CFrame, box, p) do
		local far = (part.Position - root.Position).Magnitude > r
		if far and part:GetAttribute("Kind") ~= "Gem" then
			continue -- the magnet only pulls gems
		end
		if far and CollectionService:HasTag(part, "Bottle") then
			-- the gem flies to you (drawn here only), then counts as picked up
			local id = part:GetAttribute("BottleId") :: number
			if id and not collected[id] then
				local from = part.CFrame
				local t0 = os.clock()
				task.spawn(function()
					while os.clock() - t0 < 0.22 and root.Parent do
						local k = (os.clock() - t0) / 0.22
						part.CFrame = from:Lerp(root.CFrame, k * k)
						RunService.RenderStepped:Wait()
					end
				end)
			end
		end
		if CollectionService:HasTag(part, "Bottle") then
			local id = part:GetAttribute("BottleId") :: number
			if id and not collected[id] then
				collected[id] = true
				part.LocalTransparencyModifier = 1
				for _, d in part:GetDescendants() do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = 1
					elseif d:IsA("SurfaceGui") or d:IsA("Light") then
						d.Enabled = false -- the ? box is drawn with these
					end
				end
				Runner.onPickup:Fire(part:GetAttribute("Kind") or "Juice")
				remotes.Collect:FireServer(id)
			end
		end
	end
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
	local cam = workspace.CurrentCamera
	if not isRunning or not hum or not root then
		if cam and wasFov then
			wasFov = false
			cam.FieldOfView = FOV_BASE
		end
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, tr in animator:GetPlayingAnimationTracks() do
			local n = tr.Animation and tr.Animation.Name
			if (n == "RunAnim" or n == "WalkAnim") and tr.Speed > RUN_ANIM_MAX then
				tr:AdjustSpeed(RUN_ANIM_MAX)
			end
		end
	end
	if cam then
		wasFov = true
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z).Magnitude
		local kick = Settings.get("SpeedZoom") and (FOV_RUN - FOV_BASE) or 0
		local want = FOV_BASE + kick * math.clamp((flat - 16) / 30, 0, 1.3)
		cam.FieldOfView += (want - cam.FieldOfView) * 0.08
	end
	local t = os.clock()
	local dt = math.min(t - lastClock, 0.1)
	lastClock = t

	local hs = hum:GetState()
	if
		hum.FloorMaterial ~= Enum.Material.Air
		and hs ~= Enum.HumanoidStateType.Jumping
		and hs ~= Enum.HumanoidStateType.Freefall
		and t - lastJumpAt > JUMP_LOCK
	then
		lastGrounded = t
	end
	if t - jumpWanted < 0.2 and t - lastGrounded < 0.12 and hs ~= Enum.HumanoidStateType.Jumping then
		jumpWanted = -1
		lastGrounded = -1
		lastJumpAt = t
		slideUntil = 0
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		Sfx.play("Jump")
	end

	if turning then
		local speed = player:GetAttribute("RunSpeed") or Config.RunSpeedStart
		if t < stumbleUntil then
			speed *= Config.StumbleSpeedMul
		end
		turnFrame(root, hum, speed)
		return
	end

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
	if steer == 0 then
		steer = arrowSteer(t)
	end
	if steer == 0 and controls and not UserInputService.TouchEnabled then
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
	-- a flick that already ended still counts as a turn press for a moment
	if flickSign ~= 0 and t - flickTime < 0.35 and t - lastSteerTime > 0.02 then
		lastSteerSign = flickSign
		lastSteerTime = flickTime
	end

	-- Speed
	local speed = player:GetAttribute("RunSpeed") or Config.RunSpeedStart
	if t < stumbleUntil then
		speed *= Config.StumbleSpeedMul
	end
	if workspace:GetServerTimeNow() < (player:GetAttribute("SlowUntil") or 0) then
		speed *= Config.DartSlowMul
	end
	local st = workspace:GetServerTimeNow()
	if st < (player:GetAttribute("SpeedUntil") or 0) then
		speed *= 1.35
	end
	-- hit by someone's ability: hexed runs 10% slower; speared / frozen / bubbled stops dead
	if st < (player:GetAttribute("HexUntil") or 0) then
		speed *= 0.9
	end
	local held = st < (player:GetAttribute("HeldUntil") or 0)
	if held then
		speed = 0
		if player:GetAttribute("HeldKind") == "bubble" then
			-- the bubble floats you up a little
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, math.max(v.Y, 6), 0)
		end
	end
	if t < tarUntil then
		speed *= 0.45
	end
	if t < mudUntil then
		speed *= 1.25
	end
	-- out of juice: the first 4 pulses only stumble, then every pulse costs 8% speed (down to 50%)
	if (player:GetAttribute("Juice") or 100) > 0 then
		emptyPulses = 0
	elseif emptyPulses > 4 then
		speed *= math.max(0.5, 1 - 0.08 * (emptyPulses - 4))
	end
	collectNear(root)
	if zip then
		zipFrame(root, hum, speed * 1.05, steer, dt)
		return
	end
	if vine then
		vineFrame(root, hum, speed, dt)
		return
	end

	-- Gadgets: Grapple Vine launches you forward; while flying you never drop below where you took off.
	local leapAt = player:GetAttribute("LeapAt") or 0
	if leapAt ~= lastLeap then
		lastLeap = leapAt
		if st - leapAt < 1 then
			flyY = root.Position.Y + 6
			root.AssemblyLinearVelocity = heading * 95 + Vector3.new(0, 45, 0)
		end
	end
	-- Rocket Boots: a huge jump straight up and on
	local rocketAt = player:GetAttribute("RocketAt") or 0
	if rocketAt ~= lastRocket then
		lastRocket = rocketAt
		if st - rocketAt < 1 then
			root.AssemblyLinearVelocity = heading * 50 + Vector3.new(0, 105, 0)
			Sfx.play("Jump")
		end
	end
	if hum.FloorMaterial ~= Enum.Material.Air then
		lastGroundY = root.Position.Y
	end
	if st < (player:GetAttribute("FlyUntil") or 0) then
		if not flyY then
			-- Glider used while falling (below where you last stood): it lifts you back up to
			-- just above that height, then you glide on
			local y = root.Position.Y
			flyY = if lastGroundY and y < lastGroundY - 2 then lastGroundY + 3 else y
		end
		local fy = flyY :: number
		if root.Position.Y < fy then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity =
				Vector3.new(v.X, math.max(v.Y, math.min(70, (fy - root.Position.Y) * 10)), v.Z)
		end
	else
		flyY = nil
	end

	-- Slide pose (greybox: drop the hip so the body ducks under logs)
	local sliding = t < slideUntil
	local track = slideTrackFor(hum)
	if track then
		if sliding and not track.IsPlaying then
			track:Play(0.08)
		elseif not sliding and track.IsPlaying then
			track:Stop(0.12) -- cut when the slide ends (or a jump cancels it)
		end
	end
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
				local dir = part:GetAttribute("Turn") :: number?
				local out = part:GetAttribute("Out") :: Vector3?
				if usedJunctions[part] or turning then
					-- already taken (or mid-turn)
				elseif part:GetAttribute("Fork") then
					-- crossroads: flick left or right to take that route; no flick = straight on
					if lastSteerSign ~= 0 and t - lastSteerTime < 0.35 then
						usedJunctions[part] = true
						turnAt(lastSteerSign, part :: BasePart)
					end
				elseif out then
					-- merge: a side route coming in from the side is turned onto the way ahead
					usedJunctions[part] = true
					local side = rightOf(heading):Dot(out)
					if math.abs(side) > 0.5 then
						turnAt(side > 0 and 1 or -1, part :: BasePart)
					end
				elseif part:GetAttribute("Auto") and dir then
					-- a side route's corner: only one way to go, so it turns you
					usedJunctions[part] = true
					turnAt(dir, part :: BasePart)
				elseif dir and lastSteerSign == dir and t - lastSteerTime < 0.35 then
					usedJunctions[part] = true
					turnAt(dir, part :: BasePart)
				end
			elseif CollectionService:HasTag(part, "TurnWall") then
				-- TurnWall lives in the piece's Solid folder; the Junction is on the piece model.
				local model = part:FindFirstAncestorOfClass("Model")
				local j = model and model:FindFirstChild("Junction") :: BasePart?
				if j and not usedJunctions[j] then
					-- Missed the corner: forced turn, stumble.
					usedJunctions[j] = true
					turnAt(part:GetAttribute("Turn") :: number, j)
					Runner.stumble("Missed the turn")
				end
			elseif CollectionService:HasTag(part, "Block") then
				if not hitObstacles[part] then
					hitObstacles[part] = true
					Sfx.play("WallHit")
					Runner.stumble("Hit a wall")
				end
			elseif CollectionService:HasTag(part, "Spike") then
				if not hitObstacles[part] then
					hitObstacles[part] = true
					Sfx.play("WallHit")
					Runner.stumble("Spiked")
				end
			elseif CollectionService:HasTag(part, "Tar") then
				tarUntil = t + 0.15
			elseif CollectionService:HasTag(part, "Mud") then
				mudUntil = t + 0.15
			elseif CollectionService:HasTag(part, "Wind") then
				windUntil = t + 0.15
				windSide = part:GetAttribute("Side") :: number
				windRight = part:GetAttribute("Right") :: Vector3
			elseif CollectionService:HasTag(part, "Warn") then
				if not usedJunctions[part] then
					usedJunctions[part] = true
					Runner.onWarn:Fire(part:GetAttribute("Text"), part)
				end
			elseif CollectionService:HasTag(part, "VineStart") then
				if not vine and not zip and not usedJunctions[part] then
					usedJunctions[part] = true
					grabVine(part, root, hum)
				end
			elseif CollectionService:HasTag(part, "ZipStart") then
				if not zip and not usedJunctions[part] then
					usedJunctions[part] = true
					grabZip(part, root, hum)
				end
			elseif CollectionService:HasTag(part, "Duck") then
				if not hitObstacles[part] then
					hitObstacles[part] = true
					Sfx.play("WallHit")
					Runner.stumble("Bonk")
				end
			elseif CollectionService:HasTag(part, "Wall") then
				local side = part:GetAttribute("Side") :: number
				local toward = math.sign(steer) == side and math.abs(steer) > 0.2
				if toward and t - lastWallBump > Config.WallBumpCooldown then
					lastWallBump = t
					Sfx.play("WallHit")
					Runner.stumble("Bumped a wall")
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
		if onCorner then
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
		emptyPulses += 1
		Runner.stumble(emptyPulses > 4 and "Out of juice - slowing!" or "Out of juice")
	end

	-- Drive: forward along heading plus sideways steer, forward speed kept constant.
	local dir = heading + rightOf(heading) * steer * Config.SteerFactor
	if t < windUntil then
		-- gusts: a steady push toward the open edge that swells and eases; full steer beats it
		local gust = 0.75 + 0.3 * math.sin(t * 2.6)
		dir += windRight * windSide * gust * Config.SteerFactor * 0.95
	end
	hum.WalkSpeed = speed * dir.Magnitude
	hum:Move(dir.Unit, false)
end

-- Phone arrows: two buttons bottom-left instead of a joystick. Holding one steers that way at
-- full lock; a tap is a short nudge (length from the Steering setting) and also counts as a turn
-- press at a corner, registered the moment the finger goes DOWN (a swipe only registered when the
-- finger lifted, which made corners late on phones).
local NUDGE = { 0.1, 0.14, 0.18, 0.24, 0.3 }
local arrowHeld: { [number]: InputObject? } = { [-1] = nil, [1] = nil }
local arrowPress: { [number]: number } = { [-1] = 0, [1] = 0 }
local arrowGui: ScreenGui? = nil

arrowSteer = function(t: number): number
	local best, bestT = 0, -1
	for side, at in arrowPress do
		local active = arrowHeld[side] ~= nil or t - at < (NUDGE[Settings.get("Steer")] or 0.18)
		if active and at > bestT then
			best, bestT = side, at -- the most recent press wins, so switching is instant
		end
	end
	return best
end

local function pressArrow(side: number, io: InputObject)
	arrowHeld[side] = io
	arrowPress[side] = os.clock()
	lastSteerSign, lastSteerTime = side, os.clock()
	flickSign, flickTime = side, os.clock()
end

-- Phone layout during a run (all from ActionButton): arrows bottom-left, Jump and Slide
-- bottom-right (Slide left of Jump, both under the right thumb), gadget slots bottom-centre
-- (client/Lobby). Roblox's own jump button is hidden while running so there is only one.
local function layoutSize(): number
	local v = workspace.CurrentCamera.ViewportSize
	local short = math.min(v.X, v.Y)
	-- phones (short side < 500 px), tablets such as Samsung Tabs (larger): thumb-sized either way
	-- tablets get noticeably bigger buttons: the thumbs reach less far across a big screen
	return if short < 500 then 86 elseif short < 800 then 124 else 140
end

local function makeArrows()
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "RunButtons"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false
	gui.Parent = pg
	arrowGui = gui
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local buttons: { [string]: GuiObject } = {}

	local function hookPress(
		b: GuiButton,
		setPressed: (boolean) -> (),
		onDown: (InputObject) -> (),
		onUp: (InputObject) -> ()?
	)
		local held: InputObject? = nil
		b.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				held = io
				setPressed(true)
				onDown(io)
			end
		end)
		-- released anywhere on screen (a GuiButton drops the touch once the finger slides off it)
		UserInputService.InputEnded:Connect(function(io)
			if held == io then
				held = nil
				setPressed(false)
				if onUp then
					onUp(io)
				end
			end
		end)
	end

	for _, side in { -1, 1 } do
		local b, setPressed = ActionButton.make(holder, layoutSize(), side < 0 and "left" or "right")
		buttons[side < 0 and "Left" or "Right"] = b
		hookPress(b, setPressed, function(io)
			pressArrow(side, io)
		end, function(io)
			if arrowHeld[side] == io then
				arrowHeld[side] = nil
			end
		end)
	end
	local jb, jumpPressed = ActionButton.make(holder, layoutSize(), "up")
	buttons.Jump = jb
	hookPress(jb, jumpPressed, function()
		jump()
	end)
	local sb, slidePressed = ActionButton.make(holder, layoutSize(), "down")
	buttons.Slide = sb
	hookPress(sb, slidePressed, function()
		slide()
	end)

	local function place()
		local s = layoutSize()
		local m, gap = 24, 18
		for _, b in buttons do
			b.Size = UDim2.fromOffset(s, s)
			b.AnchorPoint = Vector2.new(0, 1)
		end
		buttons.Left.Position = UDim2.new(0, m, 1, -m)
		buttons.Right.Position = UDim2.new(0, m + s + gap, 1, -m)
		buttons.Jump.AnchorPoint = Vector2.new(1, 1)
		buttons.Slide.AnchorPoint = Vector2.new(1, 1)
		-- Jump in the corner and a little higher (the thumb's resting spot), Slide beside it
		buttons.Jump.Position = UDim2.new(1, -m, 1, -m - s * 0.35)
		buttons.Slide.Position = UDim2.new(1, -m - s - gap, 1, -m)
	end
	place()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)

	-- Off the run (lobby, celebrating on the finish) the same gold jump arrow replaces Roblox's
	-- jump button, which stays hidden all the time.
	local lobbyGui = Instance.new("ScreenGui")
	lobbyGui.Name = "LobbyJump"
	lobbyGui.ResetOnSpawn = false
	lobbyGui.IgnoreGuiInset = true
	lobbyGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	lobbyGui.Parent = pg
	local lj, ljPressed = ActionButton.make(lobbyGui, layoutSize(), "up")
	lj.AnchorPoint = Vector2.new(1, 1)
	hookPress(lj, ljPressed, function()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local st = hum and hum:GetState()
		if
			hum
			and hum.FloorMaterial ~= Enum.Material.Air
			and st ~= Enum.HumanoidStateType.Jumping
			and st ~= Enum.HumanoidStateType.Freefall
			and os.clock() - lastJumpAt > JUMP_LOCK
		then
			lastJumpAt = os.clock()
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
	local function placeLobby()
		local s = layoutSize()
		lj.Size = UDim2.fromOffset(s, s)
		lj.Position = UDim2.new(1, -24, 1, -24 - s * 0.35)
	end
	placeLobby()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeLobby)
	-- Roblox shows the move stick's resting "hint" ring at spawn, then fades it: hide it until
	-- the first touch, so the lobby doesn't flash a joystick that then disappears.
	local touchedOnce = false
	UserInputService.TouchStarted:Connect(function()
		touchedOnce = true
	end)
	task.spawn(function()
		while gui.Parent do
			if not touchedOnce then
				local tgui = pg:FindFirstChild("TouchGui")
				local dyn = tgui and tgui:FindFirstChild("DynamicThumbstickFrame", true)
				if dyn then
					for _, n in { "ThumbstickStart", "ThumbstickEnd" } do
						local im = dyn:FindFirstChild(n) :: ImageLabel?
						if im then
							im.ImageTransparency = 1
						end
					end
				end
			end
			local st = player:GetAttribute("State")
			lobbyGui.Enabled = not gui.Enabled and (st == nil or st == "Lobby" or st == "Finished")
			local tg = pg:FindFirstChild("TouchGui")
			local rj = tg and tg:FindFirstChild("JumpButton", true) :: GuiObject?
			if rj then
				rj.Visible = false
			end
			task.wait(if touchedOnce then 0.2 else 0)
		end
	end)
end

local function initTouch()
	UserInputService.TouchStarted:Connect(function(io, processed)
		if processed or touchId or not running() then
			return
		end
		local cam = workspace.CurrentCamera
		if cam and io.Position.X > cam.ViewportSize.X * 0.6 then
			return
		end
		touchId = io
		touchStart = Vector2.new(io.Position.X, io.Position.Y)
		touchAnchor = touchStart
		touchStartTime = os.clock()
		touchSteer = 0
	end)
	UserInputService.TouchMoved:Connect(function(io)
		if io ~= touchId then
			return
		end
		local p = Vector2.new(io.Position.X, io.Position.Y)
		local dx = p.X - touchAnchor.X
		-- the anchor follows the finger past full lock, so reversing responds at once
		if math.abs(dx) > TOUCH_FULL then
			touchAnchor = Vector2.new(p.X - math.sign(dx) * TOUCH_FULL, touchAnchor.Y)
			dx = p.X - touchAnchor.X
		end
		-- Steering setting: how far a drag goes for full steer (Normal = TOUCH_FULL)
		touchSteer = dx / (TOUCH_FULL * STEER_REACH[Settings.get("Steer")])
	end)
	UserInputService.TouchEnded:Connect(function(io)
		if io ~= touchId then
			return
		end
		touchId = nil
		touchSteer = 0
		local d = Vector2.new(io.Position.X, io.Position.Y) - touchStart
		if os.clock() - touchStartTime < 0.3 and d.Magnitude > 40 then
			if math.abs(d.X) > math.abs(d.Y) then
				flickSign, flickTime = math.sign(d.X), os.clock()
			elseif d.Y < 0 then
				jump()
			end -- swiping down does nothing: sliding is the Slide button only
		end
	end)
	-- the default thumbstick fights our steer during a run; hide it then, bring it back after
	player:GetAttributeChangedSignal("State"):Connect(function()
		if controls and UserInputService.TouchEnabled then
			if running() then
				controls:Disable()
			else
				controls:Enable()
			end
		end
		touchId, touchSteer = nil, 0
		arrowHeld[-1], arrowHeld[1] = nil, nil
		if arrowGui then
			arrowGui.Enabled = running() or player:GetAttribute("State") == "Countdown"
		end
	end)
	if UserInputService.TouchEnabled then
		task.spawn(makeArrows)
	end
end

function Runner.init()
	initTouch()
	-- After the PlayerModule's control step (Input priority) so our Move wins each frame, and
	-- BEFORE the camera (it was after it): the camera is then placed from where you are this
	-- frame, not last frame. On a phone at 30 fps that one frame was a visible lag on every turn.
	RunService:BindToRenderStep("JJRunner", Enum.RenderPriority.Camera.Value - 2, step)
	-- Run camera, after the camera module: during a run the camera always looks down the path
	-- (your heading), so steering sideways never swings it and you never come out of a corner
	-- angled. Only corners turn it (on the runner's own curve). The player's zoom and up/down tilt
	-- from the camera module are kept; only the direction is fixed.
	RunService:BindToRenderStep("JJRunCam", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = workspace.CurrentCamera
		if not cam or not running() then
			turnRoll = 0
			return
		end
		local focus = cam.Focus.Position
		local cf = cam.CFrame
		local dist = (cf.Position - focus).Magnitude
		if dist < 0.5 then
			return -- first person: leave it
		end
		local ly = math.clamp(cf.LookVector.Y, -0.95, 0.6)
		local flat = if turning then turnCamLook else heading
		local look = flat * math.sqrt(1 - ly * ly) + Vector3.new(0, ly, 0)
		cam.CFrame = CFrame.lookAt(focus - look * dist, focus) * CFrame.Angles(0, 0, turnRoll)
		if not turning then
			turnRoll = 0
		end
	end)

	-- keys and gamepad only: phones get the Slide button from makeArrows
	ContextActionService:BindAction("JJSlide", function(_, state)
		if state == Enum.UserInputState.Begin then
			slide()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.S, Enum.KeyCode.Down, Enum.KeyCode.C, Enum.KeyCode.ButtonB)

	-- Space, a gamepad A and the default touch jump button all raise JumpRequest
	UserInputService.JumpRequest:Connect(jump)
	ContextActionService:BindAction("JJJump", function(_, state)
		if state == Enum.UserInputState.Begin then
			jump()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.W, Enum.KeyCode.Up) -- phones use Roblox's own jump button
end

return Runner
