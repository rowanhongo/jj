--!strict
-- Draws the abilities that hit runners, on every client, for players and bots alike:
--   held (HeldUntil/HeldKind): spear pinned beside them | ice block | floating bubble
--   hex (HexUntil/HexKind): the body hides and a chicken, skeleton or frog runs in its place
--   Shield (Shell Shield): a blue shell bubble until it pops
--   RocketAt: flames from the feet; throws (AbilityFx remote): spear / frost / hex flying over
-- The server decides who is hit; this only draws it. Built from parts, Palette colours only.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)
local Sfx = require(script.Parent.Sfx)

local AbilityFx = {}

local function part(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- weld `p` to `to` keeping its current offset
local function weld(p: BasePart, to: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = p
	w.Parent = p
end

local function puff(at: Vector3, color: Color3, n: number, size: number)
	for _ = 1, n do
		local b = part({
			Shape = Enum.PartType.Ball,
			Anchored = true,
			Size = Vector3.one * size * (0.6 + math.random() * 0.6),
			Color = color,
			Transparency = 0.15,
			Position = at,
		}, workspace)
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
		TweenService:Create(b, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {
			Position = at + dir * (2.5 + math.random() * 2),
			Size = Vector3.one * 0.2,
			Transparency = 1,
		}):Play()
		task.delay(0.5, b.Destroy, b)
	end
end

-- The three hex creatures, about runner height, built around a root at (0,0,0) = hip height
-- 3 studs above the ground, facing -Z. Returns the model (unparented) and its flapping parts.
local function creature(kind: string, cf: CFrame): (Model, { BasePart })
	local m = Instance.new("Model")
	m.Name = "Hex"
	local flap: { BasePart } = {}
	local function add(shape: Enum.PartType?, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?): Part
		return part({
			Shape = shape or Enum.PartType.Block,
			Size = size,
			CFrame = cf * off,
			Color = color,
			Material = mat or Enum.Material.SmoothPlastic,
		}, m)
	end
	local Ball, Cyl = Enum.PartType.Ball, Enum.PartType.Cylinder
	if kind == "chicken" then
		add(Ball, Vector3.new(3.2, 3, 3.6), CFrame.new(0, -0.6, 0), Palette.FinishLight) -- body
		add(Ball, Vector3.new(1.9, 1.9, 1.9), CFrame.new(0, 1.4, -1.3), Palette.FinishLight) -- head
		add(nil, Vector3.new(0.35, 0.7, 1), CFrame.new(0, 2.5, -1.3), Palette.UiDanger) -- comb
		add(nil, Vector3.new(0.35, 0.55, 0.6), CFrame.new(0, 2.35, -0.75), Palette.UiDanger)
		add(
			nil,
			Vector3.new(0.6, 0.4, 0.8),
			CFrame.new(0, 1.3, -2.45) * CFrame.Angles(math.rad(-10), 0, 0),
			Palette.JuiceGlow
		) -- beak
		add(Ball, Vector3.new(0.45, 0.7, 0.45), CFrame.new(0, 0.85, -2.1), Palette.UiDanger) -- wattle
		for _, sx in { -1, 1 } do
			add(Ball, Vector3.new(0.38, 0.38, 0.38), CFrame.new(sx * 0.62, 1.7, -2), Palette.UiInk) -- eyes
			add(
				Cyl,
				Vector3.new(1.4, 0.22, 0.22),
				CFrame.new(sx * 0.6, -2.35, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Palette.JuiceGlow
			)
			add(nil, Vector3.new(0.7, 0.15, 0.9), CFrame.new(sx * 0.6, -3, -0.3), Palette.JuiceGlow) -- feet
			local w = add(Ball, Vector3.new(0.6, 2, 2.6), CFrame.new(sx * 1.6, -0.4, 0.2), Palette.FinishLight)
			w:SetAttribute("Side", sx)
			table.insert(flap, w)
		end
		add(
			nil,
			Vector3.new(1.2, 1.4, 0.4),
			CFrame.new(0, 0.3, 1.9) * CFrame.Angles(math.rad(-25), 0, 0),
			Palette.FinishLight
		) -- tail
	elseif kind == "frog" then
		add(Ball, Vector3.new(3.6, 2.4, 3.8), CFrame.new(0, -1.6, 0), Palette.CanopyMid)
		add(Ball, Vector3.new(2.8, 1.6, 2.8), CFrame.new(0, -1.8, -0.6), Palette.CanopyBright) -- belly
		add(Ball, Vector3.new(3, 2, 2.6), CFrame.new(0, -0.3, -1.1), Palette.CanopyMid) -- head
		add(nil, Vector3.new(2, 0.15, 0.2), CFrame.new(0, -0.65, -2.38), Palette.UiInk) -- mouth
		for _, sx in { -1, 1 } do
			add(Ball, Vector3.new(1.1, 1.1, 1.1), CFrame.new(sx * 0.85, 0.75, -1.4), Palette.FinishLight) -- eyes
			add(Ball, Vector3.new(0.5, 0.6, 0.4), CFrame.new(sx * 0.85, 0.8, -1.9), Palette.UiInk)
			add(Ball, Vector3.new(1.2, 1.4, 2.6), CFrame.new(sx * 1.7, -2.3, 0.6), Palette.CanopyMid) -- back legs
			add(nil, Vector3.new(1.1, 0.2, 1.3), CFrame.new(sx * 1.6, -3, -0.9), Palette.CanopyDeep) -- feet
		end
	else -- skeleton
		local bone = Palette.UiText
		add(Ball, Vector3.new(1.9, 2, 1.9), CFrame.new(0, 2.6, 0), bone) -- skull
		add(nil, Vector3.new(1.3, 0.6, 1.2), CFrame.new(0, 1.7, -0.25), bone) -- jaw
		for _, sx in { -1, 1 } do
			add(Ball, Vector3.new(0.55, 0.6, 0.3), CFrame.new(sx * 0.42, 2.6, -0.85), Palette.UiInk) -- sockets
		end
		add(nil, Vector3.new(0.18, 0.25, 0.3), CFrame.new(0, 2.25, -0.9), Palette.UiInk) -- nose
		add(Cyl, Vector3.new(3.2, 0.35, 0.35), CFrame.new(0, 0, 0.2) * CFrame.Angles(0, 0, math.rad(90)), bone) -- spine
		for i = 0, 3 do
			add(nil, Vector3.new(2.2 - i * 0.2, 0.22, 1.2), CFrame.new(0, 1.1 - i * 0.5, -0.2), bone) -- ribs
		end
		add(nil, Vector3.new(2, 0.5, 0.9), CFrame.new(0, -1.5, 0.1), bone) -- hips
		for _, sx in { -1, 1 } do
			add(
				Cyl,
				Vector3.new(2.6, 0.3, 0.3),
				CFrame.new(sx * 1.45, 0.2, 0) * CFrame.Angles(0, 0, math.rad(80 * sx)),
				bone
			) -- arms
			local leg = add(
				Cyl,
				Vector3.new(2.6, 0.32, 0.32),
				CFrame.new(sx * 0.55, -2.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
				bone
			)
			leg:SetAttribute("Side", sx)
			table.insert(flap, leg)
		end
	end
	return m, flap
end

type Look = { parts: { Instance }, hidden: { [BasePart]: number }?, decals: { [Decal]: number }? }
local held: { [Instance]: Look } = {}
local hexed: { [Instance]: Look } = {}
local shields: { [Instance]: Part } = {}

local function clear(map: { [Instance]: Look }, owner: Instance)
	local l = map[owner]
	if not l then
		return
	end
	map[owner] = nil
	for _, p in l.parts do
		p:Destroy()
	end
	if l.hidden then
		for p, v in l.hidden do
			p.LocalTransparencyModifier = v
		end
	end
	if l.decals then
		for d, v in l.decals do
			d.Transparency = v
		end
	end
end

local function rootFor(owner: Instance): BasePart?
	local m = if owner:IsA("Player") then owner.Character else owner
	return m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function showHeld(owner: Instance, kind: string, secs: number)
	clear(held, owner)
	local root = rootFor(owner)
	if not root then
		return
	end
	local parts: { Instance } = {}
	local at = root.CFrame
	if kind == "ice" then
		Sfx.play("WallHit")
		local block = part({
			Size = Vector3.new(4.4, 6.4, 3.4),
			CFrame = at * CFrame.new(0, -0.2, 0),
			Material = Enum.Material.Glass,
			Color = Palette.Gem,
			Transparency = 0.3,
		}, workspace)
		local frost = part({
			Size = Vector3.new(4.6, 6.6, 3.6),
			CFrame = block.CFrame,
			Material = Enum.Material.Ice,
			Color = Palette.GemGlint,
			Transparency = 0.6,
		}, workspace)
		weld(block, root)
		weld(frost, root)
		table.insert(parts, block)
		table.insert(parts, frost)
		puff(at.Position, Palette.GemGlint, 8, 1.2)
	elseif kind == "bubble" then
		local b = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 7,
			CFrame = at,
			Material = Enum.Material.Glass,
			Color = Palette.Gem,
			Transparency = 0.55,
		}, workspace)
		local shine = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2,
			CFrame = at * CFrame.new(-1.6, 1.8, -2.2),
			Material = Enum.Material.Neon,
			Color = Palette.GemGlint,
			Transparency = 0.2,
		}, workspace)
		weld(b, root)
		weld(shine, root)
		table.insert(parts, b)
		table.insert(parts, shine)
	else -- spear: stuck in the ground beside them, still quivering
		local m = Instance.new("Model")
		local base = at * CFrame.new(1.6, -1.5, -0.5) * CFrame.Angles(math.rad(-20), 0, math.rad(15))
		part({
			Shape = Enum.PartType.Cylinder,
			Anchored = true,
			Size = Vector3.new(7, 0.32, 0.32),
			CFrame = base * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Palette.Trunk,
			Material = Enum.Material.Wood,
		}, m)
		part({
			Anchored = true,
			Size = Vector3.new(0.18, 1.3, 0.7),
			CFrame = base * CFrame.new(0, -1.2, 0),
			Color = Palette.GemGlint,
			Material = Enum.Material.Metal,
		}, m)
		for i = 0, 2 do
			part({
				Anchored = true,
				Size = Vector3.new(0.5, 0.25, 0.08),
				CFrame = base * CFrame.new(0, 5 - i * 0.3, 0),
				Color = Palette.UiDanger,
			}, m)
		end
		m.Parent = workspace
		table.insert(parts, m)
		task.spawn(function()
			local t0 = os.clock()
			while m.Parent and os.clock() - t0 < secs do
				local k = os.clock() - t0
				m:PivotTo(m:GetPivot() * CFrame.Angles(math.rad(math.sin(k * 40) * 1.5 * (1 - k)), 0, 0))
				RunService.RenderStepped:Wait()
			end
		end)
		Sfx.play("WallHit")
	end
	held[owner] = { parts = parts }
	task.delay(secs, function()
		if held[owner] and held[owner].parts == parts then
			if kind == "ice" then
				puff(root.Position, Palette.GemGlint, 10, 1)
			elseif kind == "bubble" then
				puff(root.Position, Palette.Gem, 8, 0.8)
			end
			clear(held, owner)
		end
	end)
end

local function showHex(owner: Instance, kind: string, secs: number)
	clear(hexed, owner)
	local root = rootFor(owner)
	local char = root and root.Parent
	if not root or not char then
		return
	end
	local hidden: { [BasePart]: number } = {}
	local decals: { [Decal]: number } = {}
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			hidden[d] = d.LocalTransparencyModifier
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Decal") then
			decals[d] = d.Transparency
			d.Transparency = 1
		end
	end
	local m, flap = creature(kind, root.CFrame)
	for _, p in m:GetChildren() do
		weld(p :: BasePart, root)
	end
	m.Parent = workspace
	puff(root.Position, Palette.Epic, 12, 1.4)
	Sfx.play("Gadget")
	local look: Look = { parts = { m }, hidden = hidden, decals = decals }
	hexed[owner] = look
	-- flap the wings / swing the legs while hexed (the welds hold the rest)
	task.spawn(function()
		local rest: { [BasePart]: CFrame } = {}
		for _, f in flap do
			for _, w in f:GetChildren() do
				if w:IsA("WeldConstraint") then
					w:Destroy()
				end
			end
			rest[f] = root.CFrame:ToObjectSpace(f.CFrame)
			f.Anchored = true
		end
		while hexed[owner] == look and root.Parent do
			local k = os.clock() * 14
			for _, f in flap do
				local sx = f:GetAttribute("Side") or 1
				f.CFrame = root.CFrame * rest[f] * CFrame.Angles(0, 0, math.rad(math.sin(k) * 25 * sx))
			end
			RunService.RenderStepped:Wait()
		end
	end)
	task.delay(secs, function()
		if hexed[owner] == look then
			puff(root.Position, Palette.Epic, 10, 1.2)
			clear(hexed, owner)
		end
	end)
end

local function showShield(owner: Instance, on: boolean)
	local old = shields[owner]
	if old then
		shields[owner] = nil
		TweenService:Create(old, TweenInfo.new(0.25), { Size = old.Size * 1.5, Transparency = 1 }):Play()
		task.delay(0.3, old.Destroy, old)
	end
	local root = rootFor(owner)
	if not on or not root then
		return
	end
	local s = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 7.5,
		CFrame = root.CFrame,
		Material = Enum.Material.ForceField,
		Color = Palette.Rare,
		Transparency = 0.1,
	}, workspace)
	weld(s, root)
	shields[owner] = s
end

local function rocket(owner: Instance)
	local root = rootFor(owner)
	if not root then
		return
	end
	local f = Instance.new("Fire")
	f.Color = Palette.Juice
	f.SecondaryColor = Palette.JuiceGlow
	f.Size = 6
	f.Heat = 18
	f.Parent = root
	puff(root.Position - Vector3.new(0, 3, 0), Palette.JuiceGlow, 10, 1.4)
	task.delay(0.9, f.Destroy, f)
end

-- attributes on a Player (its character) or a bot model
local function watch(owner: Instance)
	local function onHeld()
		local u = owner:GetAttribute("HeldUntil")
		local left = type(u) == "number" and u - workspace:GetServerTimeNow() or 0
		if left > 0.05 then
			showHeld(owner, owner:GetAttribute("HeldKind") or "spear", left)
		end
	end
	local function onHex()
		local u = owner:GetAttribute("HexUntil")
		local left = type(u) == "number" and u - workspace:GetServerTimeNow() or 0
		if left > 0.05 then
			showHex(owner, owner:GetAttribute("HexKind") or "chicken", left)
		else
			clear(hexed, owner)
		end
	end
	owner:GetAttributeChangedSignal("HeldUntil"):Connect(onHeld)
	owner:GetAttributeChangedSignal("HexUntil"):Connect(onHex)
	owner:GetAttributeChangedSignal("Shield"):Connect(function()
		showShield(owner, owner:GetAttribute("Shield") == true)
	end)
	owner:GetAttributeChangedSignal("RocketAt"):Connect(function()
		rocket(owner)
	end)
	if owner:IsA("Player") then
		owner.CharacterAdded:Connect(function()
			clear(held, owner)
			clear(hexed, owner)
			showShield(owner, false)
		end)
	end
end

-- a throw flying from one runner to another
local function throw(kind: string, from: BasePart, to: BasePart)
	if not from or not to then
		return
	end
	local travel = kind == "frost" and 0.25 or 0.3
	local t0 = os.clock()
	local a = from.Position + Vector3.new(0, 1.5, 0)
	if kind == "spear" then
		local s = part({
			Shape = Enum.PartType.Cylinder,
			Anchored = true,
			Size = Vector3.new(6, 0.3, 0.3),
			Color = Palette.Trunk,
			Material = Enum.Material.Wood,
		}, workspace)
		task.spawn(function()
			while os.clock() - t0 < travel and to.Parent do
				local k = (os.clock() - t0) / travel
				local b = to.Position + Vector3.new(0, 1, 0)
				local p = a:Lerp(b, k) + Vector3.new(0, math.sin(k * math.pi) * 5, 0)
				local ahead = a:Lerp(b, math.min(1, k + 0.05))
					+ Vector3.new(0, math.sin(math.min(1, k + 0.05) * math.pi) * 5, 0)
				if (ahead - p).Magnitude > 0.01 then
					s.CFrame = CFrame.lookAt(p, ahead) * CFrame.Angles(0, math.rad(90), 0)
				end
				RunService.RenderStepped:Wait()
			end
			s:Destroy()
		end)
		Sfx.play("Jump")
	else
		local color = kind == "frost" and Palette.GemGlint or Palette.Epic
		task.spawn(function()
			while os.clock() - t0 < travel and to.Parent do
				local k = (os.clock() - t0) / travel
				local p = a:Lerp(to.Position + Vector3.new(0, 1, 0), k)
				puff(p, color, 2, kind == "frost" and 1.4 or 0.9)
				RunService.RenderStepped:Wait()
			end
		end)
	end
end

function AbilityFx.init()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		clear(held, p)
		clear(hexed, p)
		showShield(p, false)
	end)
	local function watchBots(f: Instance)
		for _, m in f:GetChildren() do
			watch(m)
		end
		f.ChildAdded:Connect(watch)
	end
	workspace.ChildAdded:Connect(function(c)
		if c.Name == "Bots" then
			watchBots(c)
		end
	end)
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		watchBots(bots)
	end
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityFx").OnClientEvent:Connect(function(kind, a, b)
		if kind == "spear" or kind == "frost" or kind == "hex" then
			throw(kind, a, b)
		elseif kind == "shieldpop" and typeof(a) == "Instance" then
			puff((a :: BasePart).Position, Palette.Rare, 12, 1.2)
			Sfx.play("WallHit")
		elseif kind == "trappop" and typeof(b) == "Instance" then
			puff((b :: BasePart).Position, Palette.Gem, 12, 1)
		elseif kind == "trapdrop" and typeof(b) == "Instance" then
			local ball = b :: BasePart
			local full = ball.Size
			ball.Size = Vector3.one * 0.5
			TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = full }):Play()
		end
	end)
end

return AbilityFx
