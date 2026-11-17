--!strict
-- Lobby critters, drawn on each client only (no server cost, no replication).
-- Crawlers (ladybugs, stick bugs) walk slowly over the floor, walls, boards and the shop,
-- climbing from one surface onto the next and pausing now and then. The mantis hops across the floor.
-- Templates live in LobbyBuilding.Critters; each carries attributes set when they were imported:
--   Fwd, Up  - the bug's forward and up directions in its pivot space
--   Foot     - the point under its feet in pivot space (sits on the surface)

local RunService = game:GetService("RunService")

local Settings = require(script.Parent.Settings)

local LobbyBugs = {}
local clones: { Model } = {}
-- kind -> hidden template
LobbyBugs.templates = {} :: { [string]: Model }

-- Lobby floor bounds (world) for the mantis hops.
local MIN = Vector3.new(-59, 628, -37)
local MAX = Vector3.new(57, 650, 56)

-- Each crawler starts where a ray from origin along dir lands, and keeps to its home box
-- (centre, half size): when it strays out it turns back toward the centre.
type Spawn = { kind: string, origin: Vector3, dir: Vector3, home: Vector3, half: Vector3 }
local CRAWLERS: { Spawn } = {
	{
		kind = "Ladybug",
		origin = Vector3.new(30, 642, 40),
		dir = Vector3.zAxis,
		home = Vector3.new(16, 640, 46),
		half = Vector3.new(26, 9, 6),
	},
	{
		kind = "Ladybug",
		origin = Vector3.new(45, 638, 25),
		dir = Vector3.xAxis,
		home = Vector3.new(50, 638, 22),
		half = Vector3.new(8, 9, 14),
	},
	{
		kind = "Ladybug",
		origin = Vector3.new(8, 640, 4),
		dir = -Vector3.yAxis,
		home = Vector3.new(0, 630, 10),
		half = Vector3.new(20, 3, 20),
	},
	{
		kind = "Ladybug",
		origin = Vector3.new(-30, 634, 50),
		dir = Vector3.zAxis,
		home = Vector3.new(-30, 635, 55),
		half = Vector3.new(12, 5, 4),
	},
	{
		kind = "Ladybug",
		origin = Vector3.new(-20, 640, -10),
		dir = -Vector3.yAxis,
		home = Vector3.new(-20, 630, -10),
		half = Vector3.new(14, 3, 14),
	},
	{
		kind = "StickBug",
		origin = Vector3.new(-44, 645, -22),
		dir = -Vector3.yAxis,
		home = Vector3.new(-47, 634, -25),
		half = Vector3.new(10, 8, 10),
	},
	{
		kind = "StickBug",
		origin = Vector3.new(50, 634, -10),
		dir = Vector3.xAxis,
		home = Vector3.new(57, 635, -10),
		half = Vector3.new(4, 6, 12),
	},
}
local SPEED = { Ladybug = 1.3, StickBug = 0.7 }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local function rotate(v: Vector3, axis: Vector3, a: number): Vector3
	return (CFrame.fromAxisAngle(axis, a) * v)
end

local function flatten(v: Vector3, n: Vector3): Vector3
	local p = v - n * v:Dot(n)
	if p.Magnitude < 1e-3 then
		p = n:Cross(Vector3.xAxis)
		if p.Magnitude < 1e-3 then
			p = n:Cross(Vector3.zAxis)
		end
	end
	return p.Unit
end

type Bug = { model: Model, align: CFrame, foot: Vector3 }

local function prepare(template: Model): Bug
	local m = template:Clone()
	local fwd: Vector3 = template:GetAttribute("Fwd")
	local up: Vector3 = template:GetAttribute("Up")
	m.Parent = workspace
	table.insert(clones, m)
	return { model = m, align = CFrame.lookAt(Vector3.zero, fwd, up):Inverse(), foot = template:GetAttribute("Foot") }
end

local function place(b: Bug, pos: Vector3, fwd: Vector3, up: Vector3)
	b.model:PivotTo(CFrame.lookAt(pos, pos + fwd, up) * b.align * CFrame.new(-b.foot))
end

local function crawler(b: Bug, s: Spawn, speed: number): (number) -> ()
	local rng = Random.new()
	local hit = workspace:Raycast(s.origin - s.dir * 2, s.dir * 40, params)
	local pos = hit and hit.Position or Vector3.new(0, 628.9, 0)
	local n = hit and hit.Normal or Vector3.yAxis
	local h = flatten(Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)), n)
	local turn = 0
	local pause = 0
	local walk = rng:NextNumber(3, 8)
	local shownN, shownH = n, h

	return function(dt: number)
		if pause > 0 then
			pause -= dt
		else
			walk -= dt
			if walk <= 0 then
				pause = rng:NextNumber(1, 4)
				walk = rng:NextNumber(3, 9)
				turn = rng:NextNumber(-1.2, 1.2)
			end
			-- slow meander
			turn = math.clamp(turn + rng:NextNumber(-1, 1) * dt * 2, -0.9, 0.9)
			h = flatten(rotate(h, n, turn * dt), n)
			-- stay in the home box (and off the ceiling): steer back toward its centre
			local off = pos - s.home
			local out = math.abs(off.X) > s.half.X or math.abs(off.Y) > s.half.Y or math.abs(off.Z) > s.half.Z
			if out or n.Y < -0.2 then
				local back = s.home - pos
				if n.Y < -0.2 then
					back += Vector3.new(0, -10, 0)
				end
				local want = flatten(back, n)
				h = flatten(h:Lerp(want, math.min(1, dt * 3)), n)
			end
			local nextPos = pos + h * speed * dt
			local step = speed * dt
			-- 1) a surface right ahead (inside corner): climb onto it
			local wall = workspace:Raycast(pos + n * 0.15, h * (step + 0.35), params)
			if wall and wall.Normal:Dot(n) < 0.7 then
				h = flatten(n, wall.Normal)
				n = wall.Normal
				pos = wall.Position
			else
				-- 2) stick to the surface under the next spot
				local under = workspace:Raycast(nextPos + n * 0.4, -n * 0.9, params)
				if under then
					pos = under.Position
					n = under.Normal
					h = flatten(h, n)
				else
					-- 3) outside edge: wrap over it onto the face below
					local wrap = workspace:Raycast(nextPos - n * 0.25, -h * 0.8, params)
					if wrap and wrap.Normal:Dot(n) < 0.7 then
						h = flatten(-n, wrap.Normal)
						n = wrap.Normal
						pos = wrap.Position
					else
						-- nothing to stand on ahead: turn aside rather than flip in place
						h = flatten(rotate(h, n, math.pi * 0.6), n)
					end
				end
			end
		end
		-- ease the drawn orientation so surface changes turn instead of snapping
		local a = math.min(1, dt * 8)
		shownN = (shownN:Lerp(n, a)).Unit
		shownH = flatten(shownH:Lerp(h, a), shownN)
		place(b, pos, shownH, shownN)
	end
end

local function hopper(b: Bug): (number) -> ()
	local rng = Random.new()
	local function ground(x: number, z: number): Vector3?
		local r = workspace:Raycast(Vector3.new(x, 646, z), Vector3.new(0, -30, 0), params)
		return r and r.Normal.Y > 0.7 and r.Position or nil
	end
	local pos = ground(14, -6) or Vector3.new(14, 628.9, -6)
	local face = Vector3.new(0, 0, 1)
	local from, to = pos, pos
	local t, dur, wait = 1, 0.55, 2
	return function(dt: number)
		if t < 1 then
			t = math.min(1, t + dt / dur)
			local p = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * (2 + (to - from).Magnitude * 0.15), 0)
			place(b, p, face, Vector3.yAxis)
			if t >= 1 then
				pos = to
				wait = rng:NextNumber(2.5, 7)
			end
			return
		end
		wait -= dt
		-- idle: a slight sway of the body
		local sway = math.sin(os.clock() * 1.7) * 0.06
		place(b, pos, rotate(face, Vector3.yAxis, sway), Vector3.yAxis)
		if wait <= 0 then
			for _ = 1, 6 do
				local a = rng:NextNumber(0, math.pi * 2)
				local d = rng:NextNumber(5, 11)
				local x = math.clamp(pos.X + math.cos(a) * d, MIN.X + 6, MAX.X - 6)
				local z = math.clamp(pos.Z + math.sin(a) * d, MIN.Z + 6, MAX.Z - 6)
				local g = ground(x, z)
				if g and math.abs(g.Y - pos.Y) < 4 then
					from, to = pos, g
					local flat = Vector3.new(g.X - pos.X, 0, g.Z - pos.Z)
					if flat.Magnitude > 0.1 then
						face = flat.Unit
					end
					t = 0
					return
				end
			end
			wait = 1
		end
	end
end

function LobbyBugs.init()
	local building = workspace:WaitForChild("LobbyBuilding", 20)
	local folder = building and building:WaitForChild("Critters", 10)
	if not (building and folder) then
		return
	end
	local surfaces = {}
	for _, n in { "lobby_floor", "lobby_walls", "Leaderboards", "GemShop", "QuestBoard" } do
		local c = building:FindFirstChild(n)
		if c then
			table.insert(surfaces, c)
		end
	end
	params.FilterDescendantsInstances = surfaces
	-- the templates stay hidden on this client; clones do the moving
	local templates = LobbyBugs.templates
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			templates[m.Name] = m
			m.Parent = nil
		end
	end
	local steps: { (number) -> () } = {}
	for _, s in CRAWLERS do
		local t = templates[s.kind]
		if t then
			table.insert(steps, crawler(prepare(t), s, (SPEED :: any)[s.kind]))
		end
	end
	if templates.Mantis then
		table.insert(steps, hopper(prepare(templates.Mantis)))
	end
	-- parrots (LobbyBuilding.Birds, attribute Watch) turn on their perch to face this player;
	-- attribute Beak = the beak direction in the model's pivot space (measured per model)
	local birds = building:FindFirstChild("Birds")
	if birds then
		for _, m in birds:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Watch") then
				local home = m:GetPivot()
				local beak: Vector3 = m:GetAttribute("Beak") or -Vector3.zAxis
				local align = CFrame.lookAt(Vector3.zero, beak):Inverse()
				local fwd = home:VectorToWorldSpace(beak)
				local yaw = math.atan2(-fwd.X, -fwd.Z)
				local player = game:GetService("Players").LocalPlayer
				table.insert(steps, function(dt: number)
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not root then
						return
					end
					local d = root.Position - home.Position
					if d.X * d.X + d.Z * d.Z < 1 then
						return
					end
					local want = math.atan2(-d.X, -d.Z)
					local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
					yaw += diff * math.min(1, dt * 3)
					m:PivotTo(CFrame.new(home.Position) * CFrame.Angles(0, yaw, 0) * align)
				end)
			end
		end
	end
	-- butterflies: single ones, built here (a body and four round wings, each wing over a dark rim),
	-- spread around the hall at mixed heights, each wandering on its own and flapping
	do
		local rng = Random.new()
		local COLOURS = {
			Color3.fromRGB(255, 140, 30), -- monarch
			Color3.fromRGB(255, 140, 30),
			Color3.fromRGB(50, 150, 255), -- morpho blue
			Color3.fromRGB(255, 215, 60), -- yellow
			Color3.fromRGB(245, 240, 225), -- white
		}
		local RIM = Color3.fromRGB(30, 22, 18)
		-- each butterfly keeps to its own patch of the hall (a 4 x 4 grid), so they stay spread out
		local CELLS = 4
		local cw = (MAX.X - MIN.X - 12) / CELLS
		local cd = (MAX.Z - MIN.Z - 12) / CELLS
		local function spotIn(cell: number): Vector3
			local cx, cz = (cell - 1) % CELLS, (cell - 1) // CELLS
			local x0, z0 = MIN.X + 6 + cx * cw, MIN.Z + 6 + cz * cd
			return Vector3.new(rng:NextNumber(x0, x0 + cw), rng:NextNumber(630, 654), rng:NextNumber(z0, z0 + cd))
		end
		local cells = {}
		for i = 1, CELLS * CELLS do
			table.insert(cells, i)
		end
		local function disc(d: number, colour: Color3): Part
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(0.04, d, d)
			p.Color = colour
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = workspace
			return p
		end
		local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- disc axis X -> Y: lies flat
		for _ = 1, 14 do
			local cell = table.remove(cells, rng:NextInteger(1, #cells)) :: number
			local function spot(): Vector3
				return spotIn(cell)
			end
			local k = rng:NextNumber(0.6, 1.1) * 0.42
			local colour = COLOURS[rng:NextInteger(1, #COLOURS)]
			local body = Instance.new("Part")
			body.Size = Vector3.new(0.14, 0.14, 0.75) * k
			body.Color = RIM
			body.Anchored = true
			body.CanCollide = false
			body.CanQuery = false
			body.CanTouch = false
			body.CastShadow = false
			body.Parent = workspace
			-- per side: { part, offset in hinge space }
			local wings = {}
			for _, side in { -1, 1 } do
				for _, w in { { 1.0, 0.55, -0.15 }, { 0.7, 0.42, 0.32 } } do
					local d, x, z = w[1] * k, w[2] * k, w[3] * k
					table.insert(
						wings,
						{ side = side, part = disc(d + 0.12 * k, RIM), off = CFrame.new(side * x, -0.01, z) }
					)
					table.insert(wings, { side = side, part = disc(d, colour), off = CFrame.new(side * x, 0.01, z) })
				end
			end
			local pos, vel, target = spot(), Vector3.zero, spot()
			local phase = rng:NextNumber(0, 10)
			local beat = rng:NextNumber(9, 13)
			local rest = 0
			table.insert(steps, function(dt: number)
				phase += dt
				if rest > 0 then
					rest -= dt
				else
					if (target - pos).Magnitude < 3 then
						target = spot()
						if rng:NextNumber() < 0.3 then
							rest = rng:NextNumber(0.6, 2) -- glide for a moment
						end
					end
					local want = (target - pos).Unit * rng:NextNumber(3, 6)
					vel = vel:Lerp(want, math.min(1, dt * 1.2))
				end
				pos += vel * dt
				local p = pos + Vector3.new(0, math.sin(phase * 4.3) * 0.35, 0)
				local flat = Vector3.new(vel.X, 0, vel.Z)
				local cf = flat.Magnitude > 0.05 and CFrame.lookAt(p, p + flat) or CFrame.new(p)
				body.CFrame = cf
				local flap = rest > 0 and 0.15 or 0.25 + math.sin(phase * beat) * 0.85
				for _, w in wings do
					w.part.CFrame = cf * CFrame.Angles(0, 0, w.side * flap) * w.off * FLAT
				end
			end)
		end
	end
	-- low effects: the bugs are taken out of the world (they come back where they were)
	local low = false
	Settings.watch("LowFx", function(v)
		low = v
		for _, m in clones do
			m.Parent = if v then nil else workspace
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if low then
			return
		end
		-- only animate while the lobby is near the camera
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - Vector3.new(0, 640, 10)).Magnitude > 200 then
			return
		end
		for _, step in steps do
			step(dt)
		end
	end)
end

return LobbyBugs
