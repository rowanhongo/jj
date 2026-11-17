--!strict
-- Route map: a small heading-up map of the course ahead, so a crossroads is a choice you can
-- read, not a coin flip (docs/research/05-routes-strip-guardian.md). Drawn from the real built
-- floors (the whole built course is on the client: streaming is off), about AHEAD studs ahead and
-- BEHIND studs behind you:
--   floors   tinted by height against yours: lighter = above you, darker = below you
--   gems / juice   coloured dots (the side routes are lined with them)
--   obstacles   red marks (blocks, logs, spikes)
--   runners   small pale dots (players and bots); you: a gold arrow; the Guardian: a red block
-- Shown only while you are running. Redrawn 20 times a second from a pool of frames.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))

local RouteMap = {}

local AHEAD = 420 -- studs shown ahead of you
local BEHIND = 50 -- studs shown behind you
local HZ = 20
local PHONE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local player = Players.LocalPlayer

type Pool = { frames: { Frame }, used: number, make: () -> Frame }

local function pool(make: () -> Frame): Pool
	return { frames = {}, used = 0, make = make }
end

local function take(p: Pool): Frame
	p.used += 1
	local f = p.frames[p.used]
	if not f then
		f = p.make()
		p.frames[p.used] = f
	end
	f.Visible = true
	return f
end

local function finish(p: Pool)
	for i = p.used + 1, #p.frames do
		p.frames[i].Visible = false
	end
	p.used = 0
end

-- every tagged part of the course under workspace.Path, kept up to date as pieces come and go
local function tracked(tag: string): { [BasePart]: boolean }
	local set: { [BasePart]: boolean } = {}
	local function add(i: Instance)
		if i:IsA("BasePart") then
			task.defer(function()
				local path = workspace:FindFirstChild("Path")
				if path and i:IsDescendantOf(path) then
					set[i] = true
				end
			end)
		end
	end
	for _, i in CollectionService:GetTagged(tag) do
		add(i)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(i)
		set[i :: BasePart] = nil
	end)
	return set
end

function RouteMap.init(gui: ScreenGui, pos: UDim2)
	local w = PHONE and 116 or 160
	local h = PHONE and 150 or 210
	local panel = Instance.new("Frame")
	panel.Name = "RouteMap"
	panel.Position = pos
	panel.Size = UDim2.fromOffset(w, h)
	panel.BackgroundColor3 = Palette.UiInk
	panel.BackgroundTransparency = 0.3
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Visible = false
	panel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.UiRim
	stroke.Thickness = 2.5
	stroke.Parent = panel

	local scale = h / (AHEAD + BEHIND) -- px per stud
	local cx, cy = w / 2, h * AHEAD / (AHEAD + BEHIND)
	local halfW = w / 2 / scale + 30 -- studs either side worth looking at

	local function layer(z: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.ZIndex = z
		f.Visible = false
		f.Parent = panel
		return f
	end
	local floors = pool(function()
		return layer(2)
	end)
	local obstacles = pool(function()
		local f = layer(3)
		f.BackgroundColor3 = Palette.UiDanger
		return f
	end)
	local dots = pool(function()
		local f = layer(4)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		return f
	end)
	local runners = pool(function()
		local f = layer(5)
		f.Size = UDim2.fromOffset(6, 6)
		f.BackgroundColor3 = Palette.MapRunner
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Color = Palette.UiInk
		s.Thickness = 1
		s.Parent = f
		return f
	end)
	local guardian = layer(6)
	guardian.Size = UDim2.fromOffset(12, 8)
	guardian.BackgroundColor3 = Palette.UiDanger
	local gs = Instance.new("UIStroke")
	gs.Color = Palette.UiInk
	gs.Thickness = 1.5
	gs.Parent = guardian
	local me = Instance.new("TextLabel")
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.fromOffset(cx, cy)
	me.Size = UDim2.fromOffset(16, 16)
	me.BackgroundTransparency = 1
	me.Font = Enum.Font.FredokaOne
	me.Text = "▲"
	me.TextSize = 16
	me.TextColor3 = Palette.UiGold
	me.ZIndex = 7
	me.Parent = panel
	local ms = Instance.new("UIStroke")
	ms.Color = Palette.UiInk
	ms.Thickness = 1.5
	ms.Parent = me

	local floorSet = tracked("Floor")
	local bottleSet = tracked("Bottle")
	local obstacleSets = { tracked("Block"), tracked("Duck"), tracked("Spike") }

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local running = player:GetAttribute("State") == "Running"
		panel.Visible = running
		if not running then
			return
		end
		acc += dt
		if acc < 1 / HZ then
			return
		end
		acc = 0
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local origin = root.Position
		local look = root.CFrame.LookVector
		local fwd = Vector3.new(look.X, 0, look.Z)
		if fwd.Magnitude < 0.1 then
			return
		end
		fwd = fwd.Unit
		local right = fwd:Cross(Vector3.yAxis)
		local myY = origin.Y - 3

		-- world point -> map pixel; nil when off the map
		local function toMap(p: Vector3, margin: number): (number?, number?)
			local rel = p - origin
			local f = rel:Dot(fwd)
			local r = rel:Dot(right)
			if f < -BEHIND - margin or f > AHEAD + margin or math.abs(r) > halfW + margin then
				return nil, nil
			end
			return cx + r * scale, cy - f * scale
		end
		-- a part as a rotated rectangle seen from above
		local function rect(f: Frame, part: BasePart, x: number, y: number, minPx: number)
			local lk = part.CFrame.LookVector
			local flat = Vector3.new(lk.X, 0, lk.Z)
			local ang = 0
			local sx, sz = part.Size.X, part.Size.Z
			if flat.Magnitude > 0.05 then
				ang = math.deg(math.atan2(flat:Dot(right), flat:Dot(fwd)))
				sz *= flat.Magnitude -- a ramp's floor is shorter seen from above
			else
				-- standing on end (e.g. a log turned on its side): its Y axis lies flat
				sz = part.Size.Y
			end
			f.Position = UDim2.fromOffset(x, y)
			f.Size = UDim2.fromOffset(math.max(sx * scale, minPx), math.max(sz * scale, minPx))
			f.Rotation = ang
		end

		for part in floorSet do
			if not part.Parent then
				floorSet[part] = nil
				continue
			end
			local x, y = toMap(part.Position, math.max(part.Size.X, part.Size.Z) / 2)
			if x and y then
				local f = take(floors)
				rect(f, part, x, y, 1)
				local dy = part.Position.Y + part.Size.Y / 2 - myY
				f.BackgroundColor3 = dy > 4 and Palette.MapHigh or (dy < -4 and Palette.MapLow or Palette.MapFloor)
			end
		end
		finish(floors)

		for _, set in obstacleSets do
			for part in set do
				if not part.Parent then
					set[part] = nil
					continue
				end
				local x, y = toMap(part.Position, 0)
				if x and y then
					rect(take(obstacles), part, x, y, 2)
				end
			end
		end
		finish(obstacles)

		for part in bottleSet do
			if not part.Parent then
				bottleSet[part] = nil
				continue
			end
			if part.LocalTransparencyModifier >= 1 then
				continue -- picked up (hidden on this client until the server removes it)
			end
			local x, y = toMap(part.Position, 0)
			if x and y then
				local kind = part:GetAttribute("Kind")
				local f = take(dots)
				f.Position = UDim2.fromOffset(x, y)
				local s = kind == "Box" and 5 or 4
				f.Size = UDim2.fromOffset(s, s)
				f.BackgroundColor3 = kind == "Gem" and Palette.Gem
					or (kind == "Box" and Palette.UiGold or Palette.Juice)
			end
		end
		finish(dots)

		local function runnerDot(p: BasePart?)
			if p then
				local x, y = toMap(p.Position, 0)
				if x and y then
					take(runners).Position = UDim2.fromOffset(x, y)
				end
			end
		end
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute("State") == "Running" then
				runnerDot(other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?)
			end
		end
		local bots = workspace:FindFirstChild("Bots")
		if bots then
			for _, m in bots:GetChildren() do
				if m:IsA("Model") then
					runnerDot(m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") :: BasePart?)
				end
			end
		end
		finish(runners)

		-- the Guardian: where it is, or pinned to the bottom edge while it is close behind
		local g = workspace:FindFirstChild("Guardian") :: Model?
		local gx, gy
		if g then
			local gp = g:GetPivot().Position
			gx, gy = toMap(gp, 0)
			local rel = gp - origin
			if not gx and rel:Dot(fwd) < 0 and rel:Dot(fwd) > -200 then
				gx = math.clamp(cx + rel:Dot(right) * scale, 8, w - 8)
				gy = h - 6
			end
		end
		guardian.Visible = gx ~= nil
		if gx and gy then
			guardian.Position = UDim2.fromOffset(gx, gy)
		end
	end)
end

return RouteMap
