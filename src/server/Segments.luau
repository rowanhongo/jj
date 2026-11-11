--!strict
-- Greybox path pieces. Each builder gets an entry CFrame. The position is the centre of the
-- floor top at the entrance, and LookVector is the run heading. The builder returns the
-- piece's length along the path and its exit CFrame.
--
-- Local frame: x = right, y = up, z = distance forward (built with entry * CFrame.new(x, y, -z)).
--
-- Tags the client reads (CollectionService):
--   Floor     walkable floor, attribute Heading (Vector3)
--   Wall      side wall, attribute Side (+1 right / -1 left); bumping into it stumbles you
--   TurnWall  dead end at a corner, attribute Turn; running into it forces the turn and stumbles you
--   Junction  invisible corner volume, attribute Turn (+1 right / -1 left)
--   Hurdle    low bar to jump; Duck: log to slide under (both CanCollide false)
--   Bottle    juice bottle, attribute BottleId

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Palette)
local Config = require(Shared.Config)

local W = Config.PathWidth
local HALF = W / 2
local WATER_Y = -34

export type Ctx = {
	rng: Random,
	entry: CFrame,
	model: Model,
	solid: Folder, -- floors and walls (kept clear of decor)
	decor: Folder, -- banks, trees, cliffs (removable when later path needs the space)
	difficulty: number, -- 0..1
	nextBottleId: () -> number,
	isFree: (cf: CFrame, size: Vector3) -> boolean, -- false if the box touches any path solid
}

export type Result = { length: number, exit: CFrame, turn: number }

local Segments = {}

local function L(ctx: Ctx, x: number, y: number, z: number): CFrame
	return ctx.entry * CFrame.new(x, y, -z)
end

local function newPart(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local function decorPart(ctx: Ctx, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part?
	-- Decor never overlaps the path: skip anything that would intrude on a floor or wall.
	if not ctx.isFree(cf, size + Vector3.new(2, 0, 2)) then
		return nil
	end
	local p = newPart(ctx.decor, cf, size, color, material)
	if shape then
		p.Shape = shape
	end
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Floor top at local height `y` from z0 to z1, with a stone foundation down to the water.
local function floor(ctx: Ctx, z0: number, z1: number, y: number?)
	local h = y or 0
	local len = z1 - z0
	local f = newPart(ctx.solid, L(ctx, 0, h - 1.5, (z0 + z1) / 2), Vector3.new(W, 3, len), Palette.PathSand, Enum.Material.Cobblestone)
	f:SetAttribute("Heading", ctx.entry.LookVector)
	CollectionService:AddTag(f, "Floor")
	-- Tan kerb strips sit 0.3 above the floor top so no faces are coplanar.
	for _, side in { -1, 1 } do
		newPart(ctx.solid, L(ctx, side * (HALF - 0.75), h + 0.15 - 0.15, (z0 + z1) / 2), Vector3.new(1.5, 0.6, len), Palette.PathTan, Enum.Material.Slate)
	end
	-- Foundation
	local top = ctx.entry.Y + h - 3
	local depth = top - WATER_Y
	if depth > 1 then
		local cf = L(ctx, 0, 0, (z0 + z1) / 2)
		local found = newPart(ctx.decor, CFrame.new(cf.X, WATER_Y + depth / 2, cf.Z) * cf.Rotation, Vector3.new(W - 0.2, depth, len - 0.2), Palette.StoneShadow, Enum.Material.Slate)
		found.CanQuery = false
	end
end

local function wall(ctx: Ctx, side: number, z0: number, z1: number, y: number?)
	local h = y or 0
	local len = z1 - z0
	local wallH = Config.WallHeight + 3
	local p = newPart(ctx.solid, L(ctx, side * (HALF + 1), h + Config.WallHeight - wallH / 2, (z0 + z1) / 2), Vector3.new(2, wallH, len), Palette.StoneLight, Enum.Material.Slate)
	p:SetAttribute("Side", side)
	CollectionService:AddTag(p, "Wall")
	-- Moss cap, raised so its faces are not coplanar with the wall's.
	local cap = newPart(ctx.solid, L(ctx, side * (HALF + 1), h + Config.WallHeight + 0.35, (z0 + z1) / 2), Vector3.new(2.6, 0.8, len + 0.3), Palette.StoneMoss, Enum.Material.Grass)
	cap.CanQuery = false
	-- Pillars every ~20 studs
	local n = math.floor(len / 20)
	for i = 0, n do
		local z = z0 + (len / math.max(n, 1)) * i
		if z >= z0 + 1 and z <= z1 - 1 then
			local pil = newPart(ctx.solid, L(ctx, side * (HALF + 1.2), h + 4.5, z), Vector3.new(3, 9, 3), Palette.StoneMoss, Enum.Material.Slate)
			pil.CanQuery = false
			local top = newPart(ctx.solid, L(ctx, side * (HALF + 1.2), h + 9.4, z), Vector3.new(3.8, 0.8, 3.8), Palette.StoneLight, Enum.Material.Slate)
			top.CanQuery = false
		end
	end
end

local function tree(ctx: Ctx, cf: CFrame)
	local rng = ctx.rng
	local h = rng:NextNumber(14, 28)
	local trunk = decorPart(ctx, cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(h, 2.4, 2.4), Palette.Trunk, Enum.Material.Wood, Enum.PartType.Cylinder)
	if not trunk then
		return
	end
	local colors = { Palette.CanopyBright, Palette.CanopyMid, Palette.CanopyDeep }
	for i = 1, rng:NextInteger(2, 4) do
		local r = rng:NextNumber(8, 14)
		local off = Vector3.new(rng:NextNumber(-4, 4), h + rng:NextNumber(-2, 3), rng:NextNumber(-4, 4))
		decorPart(ctx, cf * CFrame.new(off), Vector3.new(r, r * 0.8, r), colors[(i % 3) + 1], Enum.Material.Grass, Enum.PartType.Ball)
	end
end

-- Banks, trees, bushes, near cliffs and far cliffs on both sides of z0..z1.
local function sides(ctx: Ctx, z0: number, z1: number, y: number?, skipBanks: boolean?)
	local rng = ctx.rng
	local h = y or 0
	local len = z1 - z0
	local baseY = ctx.entry.Y + h
	for _, side in { -1, 1 } do
		if not skipBanks then
			-- Jungle bank: a grass shelf just below floor level, falling to the water.
			local bankW = 34
			local x = side * (HALF + 2 + bankW / 2)
			local top = baseY - 1.2
			local c = L(ctx, x, 0, (z0 + z1) / 2)
			decorPart(ctx, CFrame.new(c.X, (top + WATER_Y) / 2, c.Z) * c.Rotation, Vector3.new(bankW, top - WATER_Y, len), Palette.CanopyMid, Enum.Material.Grass)
			-- Bushes along the wall foot
			for z = z0 + 4, z1 - 4, 9 do
				local r = rng:NextNumber(5, 8)
				decorPart(ctx, L(ctx, side * (HALF + 5 + rng:NextNumber(0, 3)), h - 1, z), Vector3.new(r, r * 0.7, r), rng:NextNumber() < 0.5 and Palette.CanopyBright or Palette.CanopyMid, Enum.Material.Grass, Enum.PartType.Ball)
			end
			-- Trees
			for z = z0 + rng:NextNumber(4, 10), z1 - 4, rng:NextNumber(14, 22) do
				local tx = side * (HALF + rng:NextNumber(9, 30))
				local t = L(ctx, tx, h - 1.2, z)
				tree(ctx, CFrame.new(t.Position))
			end
		end
		-- Near cliff clump (hides the flat horizon), heights vary for a ragged skyline.
		for z = z0, z1, rng:NextNumber(18, 30) do
			local cw = rng:NextNumber(24, 44)
			local ch = rng:NextNumber(8, 40)
			local cx = side * (HALF + 62 + rng:NextNumber(0, 40))
			local c = L(ctx, cx, 0, z)
			local topY = baseY + ch
			local cliff = decorPart(ctx, CFrame.new(c.X, (topY + WATER_Y) / 2, c.Z) * c.Rotation * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Vector3.new(cw, topY - WATER_Y, rng:NextNumber(22, 34)), Palette.Cliff, Enum.Material.Rock)
			if cliff then
				decorPart(ctx, CFrame.new(c.X, topY + 1, c.Z), Vector3.new(cw * 0.9, 6, cw * 0.8), Palette.CanopyDeep, Enum.Material.Grass, Enum.PartType.Ball)
			end
		end
		-- Far cliffs (fog fades them to mint)
		if rng:NextNumber() < 0.7 then
			local c = L(ctx, side * (HALF + 130 + rng:NextNumber(0, 60)), 0, (z0 + z1) / 2)
			local ch = rng:NextNumber(70, 140)
			decorPart(ctx, CFrame.new(c.X, (baseY + ch + WATER_Y) / 2, c.Z) * c.Rotation, Vector3.new(rng:NextNumber(50, 90), baseY + ch - WATER_Y, len + 10), Palette.CliffFar, Enum.Material.Rock)
		end
	end
end

local function bottles(ctx: Ctx, z0: number, z1: number, y: number?, lift: number?)
	local rng = ctx.rng
	local lanes = { -7, 0, 7 }
	local lane = lanes[rng:NextInteger(1, 3)]
	local z = z0
	while z <= z1 do
		local id = ctx.nextBottleId()
		local b = newPart(ctx.model, L(ctx, lane, (y or 0) + 1.8 + (lift or 0), z), Vector3.new(1.4, 2, 1.4), Palette.Juice, Enum.Material.Neon)
		b.Shape = Enum.PartType.Cylinder
		b.CFrame = b.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		b.Size = Vector3.new(2, 1.4, 1.4)
		b.CanCollide = false
		b.CanTouch = false
		b.Name = "Bottle"
		b:SetAttribute("BottleId", id)
		CollectionService:AddTag(b, "Bottle")
		z += 5
	end
end

local function straightBase(ctx: Ctx, len: number)
	floor(ctx, 0, len)
	wall(ctx, -1, 0, len)
	wall(ctx, 1, 0, len)
	sides(ctx, 0, len)
end

local function exitAt(ctx: Ctx, len: number, rise: number?): CFrame
	return ctx.entry * CFrame.new(0, rise or 0, -len)
end

function Segments.start(ctx: Ctx): Result
	local len = 60
	straightBase(ctx, len)
	-- Temple gate at the start line
	for _, side in { -1, 1 } do
		newPart(ctx.solid, L(ctx, side * (HALF - 2), 9, 50), Vector3.new(4, 18, 4), Palette.StoneMoss, Enum.Material.Slate).CanQuery = false
	end
	newPart(ctx.solid, L(ctx, 0, 19.5, 50), Vector3.new(W + 2, 3, 5), Palette.StoneLight, Enum.Material.Slate).CanQuery = false
	local line = newPart(ctx.model, L(ctx, 0, 0.05, 50), Vector3.new(W - 3, 0.1, 1.2), Palette.UiGold, Enum.Material.Neon)
	line.CanCollide = false
	line.CanQuery = false
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

function Segments.straight(ctx: Ctx): Result
	local len = 60
	straightBase(ctx, len)
	bottles(ctx, 12, 48)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

function Segments.hurdle(ctx: Ctx): Result
	local len = 60
	straightBase(ctx, len)
	local z = 30
	local bar = newPart(ctx.model, L(ctx, 0, 1.3, z), Vector3.new(W, 2.6, 1.6), Palette.StoneMoss, Enum.Material.Slate)
	bar.CanCollide = false
	CollectionService:AddTag(bar, "Hurdle")
	-- Bottles arc over the hurdle: they reward the jump.
	bottles(ctx, z - 5, z + 5, 0, 3)
	bottles(ctx, 44, 54)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

function Segments.duck(ctx: Ctx): Result
	local len = 60
	straightBase(ctx, len)
	local z = 30
	local log = newPart(ctx.model, L(ctx, 0, 4.7, z) * CFrame.Angles(0, 0, 0), Vector3.new(W + 4, 2.8, 2.8), Palette.Trunk, Enum.Material.Wood)
	log.Shape = Enum.PartType.Cylinder
	log.CanCollide = false
	CollectionService:AddTag(log, "Duck")
	-- Hanging vines from the log so it reads from far away
	for x = -HALF + 2, HALF - 2, 4 do
		local v = newPart(ctx.model, L(ctx, x, 5.5, z + 0.4), Vector3.new(0.4, 2.2, 0.4), Palette.CanopyBright, Enum.Material.Grass)
		v.CanCollide = false
		v.CanQuery = false
	end
	bottles(ctx, 8, 22)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

function Segments.gap(ctx: Ctx): Result
	local len = 60
	local g = math.floor(9 + 4 * ctx.difficulty)
	local a = 26
	floor(ctx, 0, a)
	floor(ctx, a + g, len)
	wall(ctx, -1, 0, len)
	wall(ctx, 1, 0, len)
	sides(ctx, 0, len)
	-- Broken edge stones
	for _, z in { a - 0.6, a + g + 0.6 } do
		local e = newPart(ctx.solid, L(ctx, 0, -1.2, z), Vector3.new(W - 0.4, 3.2, 1.2), Palette.StoneShadow, Enum.Material.Slate)
		e.CanQuery = false
	end
	bottles(ctx, a - 2, a + g + 2, 0, 4)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

function Segments.bridge(ctx: Ctx): Result
	local len = 56
	-- Planks over an open chasm; rope rails act as walls.
	local z = 0
	while z < len do
		local p = newPart(ctx.solid, L(ctx, 0, -0.5, z + 1.2), Vector3.new(W, 1, 2.3), Palette.WoodPlank, Enum.Material.WoodPlanks)
		p:SetAttribute("Heading", ctx.entry.LookVector)
		CollectionService:AddTag(p, "Floor")
		z += 2.5
	end
	for _, side in { -1, 1 } do
		local rail = newPart(ctx.solid, L(ctx, side * (HALF + 0.4), 3.2, len / 2), Vector3.new(0.6, 0.6, len), Palette.Rope, Enum.Material.Fabric)
		rail:SetAttribute("Side", side)
		CollectionService:AddTag(rail, "Wall")
		-- invisible upper collision so nobody steers off the bridge
		local guard = newPart(ctx.solid, L(ctx, side * (HALF + 0.9), 3, len / 2), Vector3.new(1, 6, len), Palette.Rope, Enum.Material.Fabric)
		guard.Transparency = 1
		guard:SetAttribute("Side", side)
		CollectionService:AddTag(guard, "Wall")
		for pz = 0, len, 14 do
			newPart(ctx.solid, L(ctx, side * (HALF + 0.4), 1.5, pz), Vector3.new(1, 5, 1), Palette.Trunk, Enum.Material.Wood).CanQuery = false
		end
	end
	sides(ctx, 0, len, 0, true)
	bottles(ctx, 10, 46)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

local function stairs(ctx: Ctx, rise: number): Result
	local flatA, run, flatB = 8, 32, 8
	local len = flatA + run + flatB
	floor(ctx, 0, flatA)
	floor(ctx, flatA + run, len, rise)
	-- Invisible ramp is the collision; visible steps are cosmetic blocks.
	local hyp = math.sqrt(run * run + rise * rise)
	local angle = math.atan2(rise, run)
	local ramp = newPart(ctx.solid, L(ctx, 0, rise / 2, flatA + run / 2) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -0.5, 0), Vector3.new(W, 1, hyp), Palette.PathTan, Enum.Material.Slate)
	ramp.Transparency = 1
	ramp:SetAttribute("Heading", ctx.entry.LookVector)
	CollectionService:AddTag(ramp, "Floor")
	local steps = 10
	for i = 0, steps - 1 do
		local z = flatA + (i + 0.5) * run / steps
		local stepTop = rise * (i + (rise > 0 and 1 or 0)) / steps
		local bottom = math.min(0, rise) - 3
		local s = newPart(ctx.solid, L(ctx, 0, (stepTop + bottom) / 2 - 0.05, z), Vector3.new(W - 0.2, stepTop - bottom, run / steps), i % 2 == 0 and Palette.StoneLight or Palette.PathTan, Enum.Material.Slate)
		s.CanCollide = false
		s.CanQuery = false
	end
	for _, side in { -1, 1 } do
		wall(ctx, side, 0, flatA)
		wall(ctx, side, flatA + run, len, rise)
		local w = newPart(ctx.solid, L(ctx, side * (HALF + 1), rise / 2 + 2, flatA + run / 2) * CFrame.Angles(angle, 0, 0), Vector3.new(2, Config.WallHeight + 5, hyp), Palette.StoneLight, Enum.Material.Slate)
		w:SetAttribute("Side", side)
		CollectionService:AddTag(w, "Wall")
	end
	sides(ctx, 0, len / 2)
	sides(ctx, len / 2, len, rise)
	bottles(ctx, flatA + run + 1, len - 1, rise)
	return { length = len, exit = exitAt(ctx, len, rise), turn = 0 }
end

function Segments.stairsUp(ctx: Ctx): Result
	return stairs(ctx, 8)
end

function Segments.stairsDown(ctx: Ctx): Result
	return stairs(ctx, -8)
end

local function corner(ctx: Ctx, turn: number): Result
	-- Square junction W x W. Entry from z = 0; the exit leaves through the `turn` side.
	floor(ctx, 0, W)
	local back = newPart(ctx.solid, L(ctx, 0, Config.WallHeight / 2 + 1, W + 1), Vector3.new(W + 4, Config.WallHeight + 6, 2), Palette.StoneLight, Enum.Material.Slate)
	back:SetAttribute("Turn", turn)
	CollectionService:AddTag(back, "TurnWall")
	-- Carved idol face on the dead end so the corner reads early
	local face = newPart(ctx.solid, L(ctx, 0, 6, W - 0.3), Vector3.new(8, 8, 0.6), Palette.StoneMoss, Enum.Material.Slate)
	face.CanQuery = false
	wall(ctx, -turn, 0, W + 2)
	local j = newPart(ctx.model, L(ctx, 0, 6, W / 2), Vector3.new(W, 14, W), Palette.UiGold, Enum.Material.SmoothPlastic)
	j.Transparency = 1
	j.CanCollide = false
	j.Name = "Junction"
	j:SetAttribute("Turn", turn)
	CollectionService:AddTag(j, "Junction")
	-- Outer side and back decor (the inside corner is covered by the neighbouring pieces)
	local rng = ctx.rng
	for i = 1, 3 do
		local t = L(ctx, -turn * (HALF + rng:NextNumber(9, 26)), -1.2, rng:NextNumber(0, W))
		tree(ctx, CFrame.new(t.Position))
	end
	local c = L(ctx, 0, 0, W + 30)
	local topY = ctx.entry.Y + rng:NextNumber(25, 55)
	decorPart(ctx, CFrame.new(c.X, (topY + WATER_Y) / 2, c.Z) * c.Rotation, Vector3.new(W + 60, topY - WATER_Y, 40), Palette.Cliff, Enum.Material.Rock)
	local exit = ctx.entry * CFrame.new(0, 0, -HALF) * CFrame.Angles(0, turn == 1 and -math.pi / 2 or math.pi / 2, 0) * CFrame.new(0, 0, -HALF)
	return { length = W, exit = exit, turn = turn }
end

function Segments.turnLeft(ctx: Ctx): Result
	return corner(ctx, -1)
end

function Segments.turnRight(ctx: Ctx): Result
	return corner(ctx, 1)
end

-- Corridor (in local space) a piece will occupy, used to clear older decor out of its way.
function Segments.footprint(kind: string): (number, number)
	-- returns length, extra width
	if kind == "turnLeft" or kind == "turnRight" then
		return W + 2, 8
	elseif kind == "stairsUp" or kind == "stairsDown" then
		return 48, 8
	elseif kind == "bridge" then
		return 56, 8
	end
	return 60, 8
end

return Segments
