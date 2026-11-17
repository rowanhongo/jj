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
--   Duck      log to slide under (CanCollide false)
--   Bottle    juice bottle, attribute BottleId

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Palette)
local Config = require(Shared.Config)
local BoxLook = require(Shared.BoxLook)

local W = Config.PathWidth
local HALF = W / 2
local LANE = W / 3 -- three lanes
local KIT_W = 24 -- the kit meshes were built for a 24-wide path; they are stretched sideways to W
local WATER_Y = -34

export type Ctx = {
	rng: Random,
	entry: CFrame,
	model: Model,
	solid: Folder, -- floors and walls (kept clear of decor)
	decor: Folder, -- banks, trees, cliffs (removable when later path needs the space)
	difficulty: number, -- 0..1
	richJuice: boolean?, -- early in a run: juice comes 3-4 at a time
	nextBottleId: () -> number,
	isFree: (cf: CFrame, size: Vector3) -> boolean, -- false if the box touches any path solid
	-- routes (PathService builds a crossroads block):
	len: number?, -- filler: its exact length
	theme: string?, -- filler on a side route: "Gem" or "Juice", a line of that pickup
	auto: boolean?, -- corner on a side route: it turns you by itself (only one way to go)
	signs: { [number]: string }?, -- crossroads: the label over each way (-1 left, 0 ahead, 1 right)
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

local function decorPart(
	ctx: Ctx,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part?
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
	p.CastShadow = false -- scenery: shadows off to save frame time (a few trees keep theirs)
	return p
end

-- Modelled kit (ServerStorage.MapKit, built in art/map_kit_build.py). Each template's pivot is
-- its path entry; in the template the path runs along +Z with right = -X, which is the local
-- frame here turned 180 degrees. The kit is looks only: the greybox parts keep every collision,
-- tag and attribute and just turn invisible when the kit is present.
local ASSETS = game:GetService("ReplicatedStorage"):FindFirstChild("Assets") -- replicated so clients preload the meshes
local KIT = ASSETS and ASSETS:FindFirstChild("MapKit")
local kitOff = false -- set while a piece whose kit model already has its own floor and walls builds

local function hide(p: BasePart?)
	if KIT and p then
		p.Transparency = 1
	end
end

-- Places kit piece `name` with its entry at local (x, y, z). `back` turns it to face the
-- way the path came from; `scaleZ` stretches it along its length.
local function kit(ctx: Ctx, name: string, x: number, y: number, z: number, back: boolean?, scaleZ: number?): Model?
	local t = KIT and KIT:FindFirstChild(name) :: Model?
	if not t then
		return nil
	end
	local m = t:Clone()
	local sx = (name:find("EdgeWall") or name:find("RiverBank")) and 1 or W / KIT_W
	local sz = (scaleZ or 1) * (name:find("Corner") and sx or 1)
	if math.abs(sz - 1) > 1e-3 or math.abs(sx - 1) > 1e-3 then
		local piv = m:GetPivot()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				local off = piv:PointToObjectSpace(d.Position)
				local rel = piv.Rotation:ToObjectSpace(d.CFrame.Rotation)
				-- scale along the model's X/Z axes, mapped onto the part's own axes
				local ax = rel:VectorToObjectSpace(Vector3.xAxis)
				local az = rel:VectorToObjectSpace(Vector3.zAxis)
				local function f(axis: Vector3, n: number): number
					return 1 + (sx - 1) * math.abs(ax:Dot(axis)) * n + (sz - 1) * math.abs(az:Dot(axis)) * n
				end
				d.Size = Vector3.new(
					d.Size.X * f(Vector3.xAxis, 1),
					d.Size.Y * f(Vector3.yAxis, 1),
					d.Size.Z * f(Vector3.zAxis, 1)
				)
				d.CFrame = piv * CFrame.new(off.X * sx, off.Y, off.Z * sz) * rel
			end
		end
	end
	m:PivotTo(L(ctx, x, y, z) * CFrame.Angles(0, back and 0 or math.pi, 0))
	m.Parent = ctx.model
	return m
end

-- Floor top at local height `y` from z0 to z1, with a stone foundation down to the water.
local function floor(ctx: Ctx, z0: number, z1: number, y: number?)
	local h = y or 0
	local len = z1 - z0
	local f = newPart(
		ctx.solid,
		L(ctx, 0, h - 1.5, (z0 + z1) / 2),
		Vector3.new(W, 3, len),
		Palette.PathSand,
		Enum.Material.Cobblestone
	)
	hide(f)
	f:SetAttribute("Heading", ctx.entry.LookVector)
	CollectionService:AddTag(f, "Floor")
	-- Tan kerb strips sit 0.3 above the floor top so no faces are coplanar.
	for _, side in { -1, 1 } do
		hide(
			newPart(
				ctx.solid,
				L(ctx, side * (HALF - 0.75), h + 0.15 - 0.15, (z0 + z1) / 2),
				Vector3.new(1.5, 0.6, len),
				Palette.PathTan,
				Enum.Material.Slate
			)
		)
	end
	-- Foundation
	local top = ctx.entry.Y + h - 3
	local depth = top - WATER_Y
	if depth > 1 then
		local cf = L(ctx, 0, 0, (z0 + z1) / 2)
		local found = newPart(
			ctx.decor,
			CFrame.new(cf.X, WATER_Y + depth / 2, cf.Z) * cf.Rotation,
			Vector3.new(KIT and W - 3 or W - 0.2, depth, len - 0.2),
			Palette.StoneShadow,
			Enum.Material.Slate
		)
		found.CanQuery = false
	end
end

local function wall(ctx: Ctx, side: number, z0: number, z1: number, y: number?)
	local h = y or 0
	local len = z1 - z0
	local wallH = Config.WallHeight + 3
	local p = newPart(
		ctx.solid,
		L(ctx, side * (HALF + 1), h + Config.WallHeight - wallH / 2, (z0 + z1) / 2),
		Vector3.new(2, wallH, len),
		Palette.StoneLight,
		Enum.Material.Slate
	)
	p:SetAttribute("Side", side)
	CollectionService:AddTag(p, "Wall")
	-- Moss cap, raised so its faces are not coplanar with the wall's.
	local cap = newPart(
		ctx.solid,
		L(ctx, side * (HALF + 1), h + Config.WallHeight + 0.35, (z0 + z1) / 2),
		Vector3.new(2.6, 0.8, len + 0.3),
		Palette.StoneMoss,
		Enum.Material.Grass
	)
	cap.CanQuery = false
	-- invisible barrier above the wall so nobody can jump up and run along its top
	local lid = newPart(
		ctx.solid,
		L(ctx, side * (HALF + 1), h + Config.WallHeight + 20, (z0 + z1) / 2),
		Vector3.new(2, 40, len),
		Palette.StoneLight,
		Enum.Material.SmoothPlastic
	)
	lid.Transparency = 1
	lid.CanQuery = false
	lid.CastShadow = false
	if KIT then
		hide(p)
		hide(cap)
		if not kitOff then
			-- 20-stud wall sections, vines toward the path (the left wall runs backwards)
			local n = math.max(1, math.floor(len / 20 + 0.5))
			local seg = len / n
			for i = 0, n - 1 do
				if side == 1 then
					kit(ctx, "K12_EdgeWall", HALF + 1, h, z0 + i * seg, false, seg / 20)
				else
					kit(ctx, "K12_EdgeWall", -HALF - 1, h, z0 + (i + 1) * seg, true, seg / 20)
				end
			end
		end
		return
	end
	-- Pillars every ~20 studs
	local n = math.floor(len / 20)
	for i = 0, n do
		local z = z0 + (len / math.max(n, 1)) * i
		if z >= z0 + 1 and z <= z1 - 1 then
			local pil = newPart(
				ctx.solid,
				L(ctx, side * (HALF + 1.2), h + 4.5, z),
				Vector3.new(3, 9, 3),
				Palette.StoneMoss,
				Enum.Material.Slate
			)
			pil.CanQuery = false
			local top = newPart(
				ctx.solid,
				L(ctx, side * (HALF + 1.2), h + 9.4, z),
				Vector3.new(3.8, 0.8, 3.8),
				Palette.StoneLight,
				Enum.Material.Slate
			)
			top.CanQuery = false
		end
	end
end

-- Jungle tree: a tall square trunk with buttress roots, a wide stepped canopy (flat tiers getting
-- smaller toward the top, a dark slab underneath) and aerial roots hanging from the canopy.
local buildTree: (Ctx, CFrame) -> ()
local treeCount = 0
local function tree(ctx: Ctx, cf: CFrame)
	local before = #ctx.decor:GetChildren()
	buildTree(ctx, cf)
	-- every part of this tree carries its id, so clearing takes it whole (PathService.clearBox)
	treeCount += 1
	local kids = ctx.decor:GetChildren()
	for i = before + 1, #kids do
		kids[i]:SetAttribute("Tree", treeCount)
	end
end

function buildTree(ctx: Ctx, cf: CFrame)
	local rng = ctx.rng
	local h = rng:NextNumber(16, 30)
	local tw = rng:NextNumber(2.6, 3.6)
	cf = cf * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	-- stand on whatever is under it (bank, cliff), or rise out of the water like a mangrove
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { ctx.model }
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, 6, 0), Vector3.new(0, -80, 0), rp)
	local groundY = hit and hit.Position.Y or WATER_Y
	local sink = math.max(0, cf.Position.Y - groundY) + 0.5
	local trunkLen = h + sink
	local trunk = decorPart(
		ctx,
		cf * CFrame.new(0, h - trunkLen / 2, 0),
		Vector3.new(tw, trunkLen, tw),
		Palette.Trunk,
		Enum.Material.Wood
	)
	if trunk and rng:NextNumber() < 0.35 then
		trunk.CastShadow = true
	end
	if not trunk then
		return
	end
	-- buttress roots flaring out at the foot
	for i = 0, 3 do
		local a = i * math.pi / 2 + rng:NextNumber(-0.3, 0.3)
		local bh = rng:NextNumber(3, 5)
		decorPart(
			ctx,
			cf * CFrame.new(0, -sink + 0.5, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, bh / 2, tw / 2 + 0.5),
			Vector3.new(0.9, bh, 1.8),
			Palette.Trunk,
			Enum.Material.Wood
		)
	end
	-- stepped canopy
	local r = rng:NextNumber(16, 22)
	local y = h
	decorPart(
		ctx,
		cf * CFrame.new(0, y - 1.4, 0),
		Vector3.new(r * 0.8, 1.4, r * 0.8),
		Palette.CanopyDeep,
		Enum.Material.Grass
	)
	local colors = { Palette.CanopyMid, Palette.CanopyMid, Palette.CanopyBright, Palette.CanopyBright }
	local tiers = rng:NextInteger(3, 5)
	for i = 1, tiers do
		local th = rng:NextNumber(1.3, 2)
		local off = Vector3.new(rng:NextNumber(-0.6, 0.6), y + th / 2, rng:NextNumber(-0.6, 0.6))
		decorPart(
			ctx,
			cf * CFrame.new(off),
			Vector3.new(r, th, r * rng:NextNumber(0.85, 1)),
			colors[math.min(i, #colors)],
			Enum.Material.Grass
		)
		y += th
		r -= rng:NextNumber(2.5, 4)
		if r < 4 then
			break
		end
	end
	-- aerial roots: some reach the ground, most stop part way
	local half = rng:NextNumber(16, 22) * 0.38
	for _ = 1, rng:NextInteger(4, 7) do
		local x, z = rng:NextNumber(-half, half), rng:NextNumber(-half, half)
		if math.abs(x) < tw and math.abs(z) < tw then
			x += tw * math.sign(x + 0.01)
		end
		local len = rng:NextNumber() < 0.35 and h - 1.4 + sink - 0.5 or rng:NextNumber(h * 0.3, h * 0.7)
		local root = decorPart(
			ctx,
			cf * CFrame.new(x, h - 1.4 - len / 2, z),
			Vector3.new(0.45, len, 0.45),
			Palette.CanopyDeep,
			Enum.Material.Grass
		)
		if root then
			root.CanCollide = false
		end
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
			local banked = true
			-- Jungle bank: a grass shelf just below floor level, falling to the water.
			local bankW = 34
			local x = side * (HALF + 2 + bankW / 2)
			local top = baseY - 1.2
			local c = L(ctx, x, 0, (z0 + z1) / 2)
			local bankCf = CFrame.new(c.X, (top + WATER_Y) / 2, c.Z) * c.Rotation
			if KIT then
				-- modelled bank in 20-stud pieces, sloping away from the wall foot
				banked = ctx.isFree(bankCf, Vector3.new(bankW + 2, top - WATER_Y, len + 2))
				if banked then
					local n = math.max(1, math.floor(len / 20 + 0.5))
					local seg = len / n
					for i = 0, n - 1 do
						if side == 1 then
							kit(ctx, "K12_RiverBank", HALF + 2, h - 0.2, z0 + i * seg, false, seg / 20)
						else
							kit(ctx, "K12_RiverBank", -HALF - 2, h - 0.2, z0 + (i + 1) * seg, true, seg / 20)
						end
					end
					-- The bank mesh is open on its wall side and its ends (you could see through
					-- the slope). A solid wedge tucked just under it closes them: its tall back face
					-- against the wall foot, sloping down to the water.
					local wTop = top - 0.6
					local depth = bankW - 6
					local mid = L(ctx, side * (HALF + 2 + depth / 2), 0, (z0 + z1) / 2)
					local centre = Vector3.new(mid.X, (wTop + WATER_Y) / 2, mid.Z)
					local out = mid.RightVector * side
					local fill = newPart(
						ctx.decor,
						CFrame.lookAt(centre, centre + out),
						Vector3.new(len - 0.4, wTop - WATER_Y, depth),
						Palette.CanopyDeep,
						Enum.Material.Grass
					)
					fill.Shape = Enum.PartType.Wedge
					fill.CanQuery = false
					fill.CanTouch = false
					fill.CastShadow = false
				end
			else
				banked = decorPart(
					ctx,
					bankCf,
					Vector3.new(bankW, top - WATER_Y, len),
					Palette.CanopyMid,
					Enum.Material.Grass
				) ~= nil
			end
			-- Bushes along the wall foot (only where there is a bank under them: never in the air)
			for z = z0 + 4, banked and z1 - 4 or z0, 9 do
				local r = rng:NextNumber(5, 8)
				decorPart(
					ctx,
					L(ctx, side * (HALF + 5 + rng:NextNumber(0, 3)), h - 1, z),
					Vector3.new(r, r * 0.7, r),
					rng:NextNumber() < 0.5 and Palette.CanopyBright or Palette.CanopyMid,
					Enum.Material.Grass,
					Enum.PartType.Ball
				)
			end
			-- Trees
			for z = z0 + rng:NextNumber(4, 10), z1 - 4, rng:NextNumber(14, 22) do
				local tx = side * (HALF + rng:NextNumber(13, 32))
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
			local cliff = decorPart(
				ctx,
				CFrame.new(c.X, (topY + WATER_Y) / 2, c.Z) * c.Rotation * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
				Vector3.new(cw, topY - WATER_Y, rng:NextNumber(22, 34)),
				Palette.Cliff,
				Enum.Material.Rock
			)
			if cliff then
				decorPart(
					ctx,
					CFrame.new(c.X, topY + 1, c.Z),
					Vector3.new(cw * 0.9, 6, cw * 0.8),
					Palette.CanopyDeep,
					Enum.Material.Grass,
					Enum.PartType.Ball
				)
			end
		end
		-- Far cliffs (fog fades them to mint)
		if rng:NextNumber() < 0.7 then
			local c = L(ctx, side * (HALF + 130 + rng:NextNumber(0, 60)), 0, (z0 + z1) / 2)
			local ch = rng:NextNumber(70, 140)
			decorPart(
				ctx,
				CFrame.new(c.X, (baseY + ch + WATER_Y) / 2, c.Z) * c.Rotation,
				Vector3.new(rng:NextNumber(50, 90), baseY + ch - WATER_Y, len + 10),
				Palette.CliffFar,
				Enum.Material.Rock
			)
		end
	end
end

local pickups = ASSETS and ASSETS:FindFirstChild("Pickups")
local JUICE_CAN = pickups and pickups:FindFirstChild("JuiceCan") :: Model?

local function pickup(ctx: Ctx, cf: CFrame, kind: string): Part
	local id = ctx.nextBottleId()
	local b
	if kind == "Gem" then
		-- Diamond: a cube stood on its corner, with a pale inner glint.
		b = newPart(
			ctx.model,
			cf * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			Vector3.new(1.6, 1.6, 1.6),
			Palette.Gem,
			Enum.Material.Glass
		)
		b.Transparency = 0.15
		b.Reflectance = 0.3
		local core = newPart(b, cf, Vector3.new(0.7, 0.7, 0.7), Palette.GemGlint, Enum.Material.Neon)
		core.CanCollide = false
		core.CanQuery = false
		core.CanTouch = false
		-- modelled brilliant-cut gem (matches the HUD icon); the cube stays as the invisible pickup
		local gemKit = KIT and KIT:FindFirstChild("K16_Gem") :: Model?
		if gemKit then
			local g = gemKit:Clone()
			g:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, ctx.rng:NextNumber(0, math.pi), 0))
			g.Parent = b
			b.Transparency = 1
			core.Transparency = 1
		end
	elseif kind == "Box" then
		-- ? box: a glass rainbow cube with a "?" on every side (shared/BoxLook); clients spin it.
		-- Gives a loadout gadget.
		b = newPart(ctx.model, cf, Vector3.new(2.8, 2.8, 2.8), Palette.Gem, Enum.Material.SmoothPlastic)
		BoxLook.dress(b)
	else
		b = newPart(
			ctx.model,
			cf * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(2.2, 1.6, 1.6),
			Palette.Juice,
			Enum.Material.Neon
		)
		b.Shape = Enum.PartType.Cylinder
		-- the gold juice can (ServerStorage.Pickups.JuiceCan, made from the Bloxy Cola mesh) is
		-- the look; the tagged cylinder stays as the pickup and goes invisible
		local can = JUICE_CAN and JUICE_CAN:Clone()
		if can then
			b.Transparency = 1
			can:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, math.rad(ctx.rng:NextNumber(-30, 30)), 0))
			can.Parent = b
		end
	end
	b.CanCollide = false
	b.CanTouch = false
	b.Name = kind
	b:SetAttribute("BottleId", id)
	b:SetAttribute("Kind", kind)
	CollectionService:AddTag(b, "Bottle")
	return b
end

-- Juice: a short line of 3, only on some pieces (rarer, but each is worth more).
-- Gems: sometimes one diamond, off to one side, so grabbing it is a small detour.
-- `force` always places juice (e.g. arcs over hurdles that reward the jump).
local function bottles(ctx: Ctx, z0: number, z1: number, y: number?, lift: number?, force: boolean?)
	local rng = ctx.rng
	local h = (y or 0) + 1.8 + (lift or 0)
	if force or rng:NextNumber() < 0.5 then
		-- one or two cans
		local lane = ({ -LANE * 0.6, 0, LANE * 0.6 })[rng:NextInteger(1, 3)]
		local mid = (z0 + z1) / 2
		if ctx.richJuice then
			local n = rng:NextInteger(3, 4)
			for k = 1, n do
				pickup(ctx, L(ctx, lane, h, mid + (k - (n + 1) / 2) * 2.5), "Juice")
			end
		elseif rng:NextNumber() < 0.5 then
			pickup(ctx, L(ctx, lane, h, mid), "Juice")
		else
			pickup(ctx, L(ctx, lane, h, mid - 2.5), "Juice")
			pickup(ctx, L(ctx, lane, h, mid + 2.5), "Juice")
		end
	end
	if not force and rng:NextNumber() < 0.07 then
		pickup(ctx, L(ctx, rng:NextNumber(-LANE, LANE), (y or 0) + 2.4, rng:NextNumber(z0, z1)), "Box")
	end
	if rng:NextNumber() < 0.15 then
		local side = rng:NextNumber() < 0.5 and -1 or 1
		pickup(ctx, L(ctx, side * rng:NextNumber(LANE * 0.5, HALF - 3), (y or 0) + 2.2, rng:NextNumber(z0, z1)), "Gem")
	end
end

local STRAIGHTS = { "K01_StraightA", "K01_StraightA", "K01_StraightB", "K01_StraightC" }
local function straightBase(ctx: Ctx, len: number)
	floor(ctx, 0, len)
	kit(ctx, STRAIGHTS[ctx.rng:NextInteger(1, #STRAIGHTS)], 0, 0, 0, false, len / 60)
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
		newPart(
			ctx.solid,
			L(ctx, side * (HALF + 2), 9, 50),
			Vector3.new(4, 18, 4),
			Palette.StoneMoss,
			Enum.Material.Slate
		).CanQuery =
			false
	end
	newPart(ctx.solid, L(ctx, 0, 19.5, 50), Vector3.new(W + 8, 3, 5), Palette.StoneLight, Enum.Material.Slate).CanQuery =
		false
	local line =
		newPart(ctx.model, L(ctx, 0, 0.05, 50), Vector3.new(W - 3, 0.1, 1.2), Palette.UiGold, Enum.Material.Neon)
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

function Segments.duck(ctx: Ctx): Result
	local len = 60
	straightBase(ctx, len)
	local z = 30
	-- raised so the gap reads from a distance (bottom at 4.2: standing hits it, sliding clears it)
	local RAISE = 0.9
	local log = newPart(
		ctx.model,
		L(ctx, 0, 4.7 + RAISE, z) * CFrame.Angles(0, 0, 0),
		Vector3.new(W + 4, 2.8, 2.8),
		Palette.Trunk,
		Enum.Material.Wood
	)
	log.Shape = Enum.PartType.Cylinder
	log.CanCollide = false
	CollectionService:AddTag(log, "Duck")
	local saw = ASSETS and ASSETS:FindFirstChild("ChainsawBlade") :: Model?
	local roll = ctx.rng:NextNumber()
	if roll < 0.35 then
		-- flamethrower: a burning gas pipe across the path at head height, flames rising above
		-- it, nozzles on both walls; it reads as "too high to jump, slide under"
		local pipe = newPart(
			ctx.model,
			L(ctx, 0, 4.9, z),
			Vector3.new(W + 2, 0.7, 0.7),
			Color3.fromRGB(70, 70, 76),
			Enum.Material.Metal
		)
		pipe.CanCollide = false
		pipe.CanQuery = false
		for _, side in { -1, 1 } do
			local tank = newPart(
				ctx.model,
				L(ctx, side * (HALF + 0.4), 4.9, z),
				Vector3.new(1.6, 2.4, 1.6),
				Color3.fromRGB(176, 58, 40),
				Enum.Material.Metal
			)
			tank.CanCollide = false
			tank.CanQuery = false
		end
		for x = -HALF + 1.5, HALF - 1.5, 2.6 do
			local e = newPart(
				ctx.model,
				L(ctx, x, 5.6, z),
				Vector3.new(0.5, 0.5, 0.5),
				Palette.Trunk,
				Enum.Material.SmoothPlastic
			)
			e.Transparency = 1
			e.CanCollide = false
			e.CanQuery = false
			local f = Instance.new("Fire")
			f.Size = 4.5
			f.Heat = 9
			f.Color = Color3.fromRGB(255, 140, 40)
			f.SecondaryColor = Color3.fromRGB(255, 220, 80)
			f.Parent = e
		end
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 150, 60)
		glow.Range = 18
		glow.Brightness = 2
		glow.Parent = pipe
		hide(log)
	elseif saw and roll < 0.6 then
		-- chainsaw blade across the path, flat face to the runner, toothed edge down at your head
		local b = saw:Clone()
		-- lie it flat (broad face up), toothed edge toward the runner
		b:PivotTo(b:GetPivot() * CFrame.Angles(math.pi / 2, 0, 0))
		local k = (W + 2) / b:GetExtentsSize().X
		for _, part in b:GetDescendants() do
			if part:IsA("BasePart") then
				local off = b:GetPivot():PointToObjectSpace(part.Position)
				part.Size = Vector3.new(part.Size.X * k, part.Size.Y * 1.3, part.Size.Z * 2)
				part.Position = b:GetPivot():PointToWorldSpace(Vector3.new(off.X * k, off.Y * 1.3, off.Z * 2))
			end
		end
		-- flat at head height: under it while sliding, into it while standing
		b:PivotTo(L(ctx, 0, 4.7, z) * CFrame.Angles(math.pi / 2, 0, 0))
		b.Parent = ctx.model
		hide(log)
	elseif kit(ctx, "K08_DuckLog", 0, RAISE, z) then
		hide(log)
	else
		-- Hanging vines from the log so it reads from far away
		for x = -HALF + 2, HALF - 2, 4 do
			local v = newPart(
				ctx.model,
				L(ctx, x, 5.5, z + 0.4),
				Vector3.new(0.4, 2.2, 0.4),
				Palette.CanopyBright,
				Enum.Material.Grass
			)
			v.CanCollide = false
			v.CanQuery = false
		end
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
	-- broken ends facing each other across the gap (the far one turned round, squeezed to fit)
	kit(ctx, "K04_GapEnd", 0, 0, 0)
	kit(ctx, "K04_GapEnd", 0, 0, len, true, (len - a - g) / 26)
	wall(ctx, -1, 0, len)
	wall(ctx, 1, 0, len)
	sides(ctx, 0, len)
	-- Broken edge stones
	for _, z in { a - 0.6, a + g + 0.6 } do
		local e = newPart(
			ctx.solid,
			L(ctx, 0, -1.2, z),
			Vector3.new(W - 0.4, 3.2, 1.2),
			Palette.StoneShadow,
			Enum.Material.Slate
		)
		e.CanQuery = false
		hide(e)
	end
	ctx.model:SetAttribute("GapA", a)
	ctx.model:SetAttribute("GapB", a + g)
	bottles(ctx, a - 2, a + g + 2, 0, 4)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

function Segments.bridge(ctx: Ctx): Result
	local len = 56
	-- Planks over an open chasm; rope rails act as walls.
	local z = 0
	while z < len do
		local p = newPart(
			ctx.solid,
			L(ctx, 0, -0.5, z + 1.2),
			Vector3.new(W, 1, 2.3),
			Palette.WoodPlank,
			Enum.Material.WoodPlanks
		)
		hide(p)
		p:SetAttribute("Heading", ctx.entry.LookVector)
		CollectionService:AddTag(p, "Floor")
		z += 2.5
	end
	for _, side in { -1, 1 } do
		local rail = newPart(
			ctx.solid,
			L(ctx, side * (HALF + 0.4), 3.2, len / 2),
			Vector3.new(0.6, 0.6, len),
			Palette.Rope,
			Enum.Material.Fabric
		)
		hide(rail)
		rail:SetAttribute("Side", side)
		CollectionService:AddTag(rail, "Wall")
		-- invisible upper collision so nobody steers off the bridge
		local guard = newPart(
			ctx.solid,
			L(ctx, side * (HALF + 0.9), 3, len / 2),
			Vector3.new(1, 6, len),
			Palette.Rope,
			Enum.Material.Fabric
		)
		guard.Transparency = 1
		guard:SetAttribute("Side", side)
		CollectionService:AddTag(guard, "Wall")
		for pz = 0, len, 14 do
			local post = newPart(
				ctx.solid,
				L(ctx, side * (HALF + 0.4), 1.5, pz),
				Vector3.new(1, 5, 1),
				Palette.Trunk,
				Enum.Material.Wood
			)
			post.CanQuery = false
			hide(post)
		end
	end
	sides(ctx, 0, len, 0, true)
	kit(ctx, "K05_Bridge", 0, 0, 0)
	bottles(ctx, 10, 46)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

local function stairs(ctx: Ctx, rise: number): Result
	local flatA, run, flatB = 8, 32, 8
	local len = flatA + run + flatB
	-- the kit stairs bring their own floors, steps and parapets; down = the same piece turned round
	local hasKit = if rise > 0 then kit(ctx, "K03_StairsUp", 0, 0, 0) else kit(ctx, "K03_StairsUp", 0, rise, len, true)
	kitOff = hasKit ~= nil
	floor(ctx, 0, flatA)
	floor(ctx, flatA + run, len, rise)
	-- Invisible ramp is the collision; visible steps are cosmetic blocks.
	local hyp = math.sqrt(run * run + rise * rise)
	local angle = math.atan2(rise, run)
	local ramp = newPart(
		ctx.solid,
		L(ctx, 0, rise / 2, flatA + run / 2) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -0.5, 0),
		Vector3.new(W, 1, hyp),
		Palette.PathTan,
		Enum.Material.Slate
	)
	ramp.Transparency = 1
	ramp:SetAttribute("Heading", ctx.entry.LookVector)
	CollectionService:AddTag(ramp, "Floor")
	local steps = 10
	for i = 0, steps - 1 do
		local z = flatA + (i + 0.5) * run / steps
		local stepTop = rise * (i + (rise > 0 and 1 or 0)) / steps
		local bottom = math.min(0, rise) - 3
		local s = newPart(
			ctx.solid,
			L(ctx, 0, (stepTop + bottom) / 2 - 0.05, z),
			Vector3.new(W - 0.2, stepTop - bottom, run / steps),
			i % 2 == 0 and Palette.StoneLight or Palette.PathTan,
			Enum.Material.Slate
		)
		s.CanCollide = false
		s.CanQuery = false
		hide(s)
	end
	for _, side in { -1, 1 } do
		wall(ctx, side, 0, flatA)
		wall(ctx, side, flatA + run, len, rise)
		local w = newPart(
			ctx.solid,
			L(ctx, side * (HALF + 1), rise / 2 + 2, flatA + run / 2) * CFrame.Angles(angle, 0, 0),
			Vector3.new(2, Config.WallHeight + 5, hyp),
			Palette.StoneLight,
			Enum.Material.Slate
		)
		hide(w)
		w:SetAttribute("Side", side)
		CollectionService:AddTag(w, "Wall")
	end
	kitOff = false
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

-- Half wall: a stone block across half the path. Running into it stops you and stumbles you.
-- Later on a second block on the other side makes a slalom.
function Segments.halfWall(ctx: Ctx): Result
	local len = 60
	straightBase(ctx, len)
	local rng = ctx.rng
	local side = rng:NextNumber() < 0.5 and -1 or 1
	local zs = { 22 }
	if rng:NextNumber() < 0.35 + 0.5 * ctx.difficulty then
		table.insert(zs, 44)
	end
	for i, z in zs do
		local s = (i == 1) and side or -side
		local b = newPart(
			ctx.solid,
			L(ctx, s * W / 4, 4, z),
			Vector3.new(W / 2, 8, 3),
			Palette.StoneLight,
			Enum.Material.Slate
		)
		b.Name = "HalfWall"
		b:SetAttribute("Side", s)
		CollectionService:AddTag(b, "Block")
		ctx.model:SetAttribute("Wall" .. i .. "Z", z)
		ctx.model:SetAttribute("Wall" .. i .. "Side", s)
		local cap = newPart(
			ctx.solid,
			L(ctx, s * W / 4, 8.4, z),
			Vector3.new(W / 2 + 0.6, 0.8, 3.6),
			Palette.StoneMoss,
			Enum.Material.Grass
		)
		cap.CanQuery = false
		if kit(ctx, rng:NextNumber() < 0.5 and "K09_HalfWallA" or "K09_HalfWallB", s * W / 4, 0, z) then
			hide(b)
			hide(cap)
		end
		bottles(ctx, z + 4, z + 10, 0, 0, true)
	end
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Tar pit: sticky black pool over most of the width. Wading through halves your speed;
-- jump over the narrow end or steer round the dry strip.
function Segments.tar(ctx: Ctx): Result
	local len = 60
	straightBase(ctx, len)
	local rng = ctx.rng
	local side = rng:NextNumber() < 0.5 and -1 or 1
	local pw = W - 7
	local z0, z1 = 18, 40
	local px = side * (W - pw) / 2 -- dry strip on the other side
	local pit = newPart(
		ctx.model,
		L(ctx, px, 0, (z0 + z1) / 2),
		Vector3.new(pw, 1, z1 - z0),
		Palette.Tar,
		Enum.Material.SmoothPlastic
	)
	pit.Reflectance = 0
	-- kit pit: its entry is the pit centre, its banner hangs 8 before the pit
	local tarKit = kit(ctx, "K10_TarPit", px, 0, (z0 + z1) / 2)
	-- Glowing danger rim round the pit so it reads from far down the path.
	local rimH, rimT = 0.7, 0.8
	for _, e in
		{
			{ px, z0, pw + rimT * 2, rimT },
			{ px, z1, pw + rimT * 2, rimT },
			{ px - pw / 2, (z0 + z1) / 2, rimT, z1 - z0 },
			{ px + pw / 2, (z0 + z1) / 2, rimT, z1 - z0 },
		}
	do
		local rim = newPart(
			ctx.model,
			L(ctx, e[1], rimH / 2 - 0.05, e[2]),
			Vector3.new(e[3], rimH, e[4]),
			Palette.UiDanger,
			Enum.Material.Neon
		)
		rim.CanCollide = false
		rim.CanQuery = false
		if tarKit then
			rim:Destroy()
		end
	end
	-- Warning banner hung across the path ahead of the pit.
	-- with the kit the board is the kit's; this part only carries the TAR PIT text in front of it
	local banner = newPart(
		ctx.model,
		L(ctx, tarKit and px or 0, 11, z0 - 8),
		Vector3.new(W - 2, 3, tarKit and 0.7 or 0.4),
		Palette.UiDanger,
		Enum.Material.SmoothPlastic
	)
	if tarKit then
		banner.Transparency = 1
	end
	banner.CanCollide = false
	banner.CanQuery = false
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.PixelsPerStud = 30
		sg.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "TAR PIT"
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Palette.UiText
		local st = Instance.new("UIStroke")
		st.Color = Palette.UiRim
		st.Thickness = 3
		st.Parent = t
		t.Parent = sg
		sg.Parent = banner
	end
	for _, sx in { -1, 1 } do
		local post = newPart(
			ctx.model,
			L(ctx, sx * (HALF - 1), 6, z0 - 8),
			Vector3.new(0.6, 12, 0.6),
			Palette.Trunk,
			Enum.Material.Wood
		)
		post.CanCollide = false
		if tarKit then
			post:Destroy()
		end
	end
	pit.CanCollide = false
	pit.Name = "TarPit"
	if tarKit then
		pit.Transparency = 1
	end
	ctx.model:SetAttribute("TarSide", side)
	CollectionService:AddTag(pit, "Tar")
	for _ = 1, 7 do
		local r = rng:NextNumber(1, 2.4)
		local bub = newPart(
			ctx.model,
			L(ctx, px + rng:NextNumber(-pw / 2 + 2, pw / 2 - 2), 0.45, rng:NextNumber(z0 + 2, z1 - 2)),
			Vector3.new(r, r * 0.6, r),
			Palette.TarBubble,
			Enum.Material.SmoothPlastic
		)
		bub.Shape = Enum.PartType.Ball
		bub.CanCollide = false
		bub.CanQuery = false
		if tarKit then
			bub:Destroy()
		end
	end
	bottles(ctx, 44, 54)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Ziplines: four cables climb from a ledge across a chasm to a higher ledge. You grab the
-- cable in your lane automatically. Two of them are cut part-way: press left/right to hop
-- to the next cable before you reach the cut, or you drop into the water.
-- Each cable is tagged Zipline with world-space A (start), B (end), Cut (0..1 of the way
-- along where it snaps, 1 = whole) and Lane (1..4 left to right).
Segments.ZipLanes = { -12, -4, 4, 12 }
Segments.ZipHang = 4.6 -- root hangs this far under the cable
function Segments.zipline(ctx: Ctx): Result
	local rng = ctx.rng
	local rise, span, ledge = 16, 80, 14
	local len = ledge + span + ledge
	local cableY = 10
	floor(ctx, 0, ledge)
	floor(ctx, ledge + span, len, rise)
	kit(ctx, "K04_GapEnd", 0, 0, 0, false, ledge / 26)
	kit(ctx, "K04_GapEnd", 0, rise, len, true, ledge / 26)
	for _, s in { -1, 1 } do
		wall(ctx, s, 0, ledge)
		wall(ctx, s, ledge + span, len, rise)
	end
	sides(ctx, 0, ledge)
	sides(ctx, ledge, ledge + span, 0, true)
	sides(ctx, ledge + span, len, rise)
	-- Two different cables are cut, at different points.
	local lanes = { 1, 2, 3, 4 }
	local cutA = table.remove(lanes, rng:NextInteger(1, 4)) :: number
	local cutB = table.remove(lanes, rng:NextInteger(1, 3)) :: number
	local cuts = { [cutA] = rng:NextNumber(0.35, 0.5), [cutB] = rng:NextNumber(0.6, 0.78) }
	local zips = Instance.new("Folder")
	zips.Name = "Zips"
	zips.Parent = ctx.model
	local zA, zB = ledge - 2, ledge + span + 2
	for lane, x in Segments.ZipLanes do
		local a = L(ctx, x, cableY, zA).Position
		local b = L(ctx, x, cableY + rise, zB).Position
		local cut = cuts[lane] or 1
		local e = a:Lerp(b, cut)
		local c = newPart(
			zips,
			CFrame.lookAt((a + e) / 2, e) * CFrame.Angles(0, math.pi / 2, 0),
			Vector3.new((e - a).Magnitude, 0.45, 0.45),
			Palette.Rope,
			Enum.Material.Fabric
		)
		c.Shape = Enum.PartType.Cylinder
		c.CanCollide = false
		c.Name = "Zip" .. lane
		c:SetAttribute("A", a)
		c:SetAttribute("B", b)
		c:SetAttribute("Cut", cut)
		c:SetAttribute("Lane", lane)
		CollectionService:AddTag(c, "Zipline")
		if cut < 1 then
			-- Frayed end: a short drooping strand and a red rag so the cut reads from far off.
			local cutKit = KIT and KIT:FindFirstChild("K11_ZipCut") :: Model?
			if cutKit then
				local ck = cutKit:Clone()
				ck:PivotTo(CFrame.lookAt(e, e - (b - a).Unit))
				ck.Parent = zips
			end
			local droop = newPart(
				zips,
				CFrame.new(e) * CFrame.new(0, -1.4, 0),
				Vector3.new(0.3, 2.8, 0.3),
				Palette.Rope,
				Enum.Material.Fabric
			)
			droop.CanCollide = false
			droop.CanQuery = false
			local rag = newPart(
				zips,
				CFrame.new(e) * CFrame.new(0, -0.6, 0),
				Vector3.new(1.4, 1.4, 0.2),
				Palette.UiDanger,
				Enum.Material.Neon
			)
			rag.CanCollide = false
			rag.CanQuery = false
			-- a glowing red warning ball at the cut end, lit, so the break is obvious from far off
			local warn = newPart(zips, CFrame.new(e), Vector3.new(2.4, 2.4, 2.4), Palette.UiDanger, Enum.Material.Neon)
			warn.Shape = Enum.PartType.Ball
			warn.Transparency = 0.25
			warn.CanCollide = false
			warn.CanQuery = false
			local glow = Instance.new("PointLight")
			glow.Color = Palette.UiDanger
			glow.Range = 16
			glow.Brightness = 3
			glow.Parent = warn
			local hl = Instance.new("Highlight")
			hl.FillTransparency = 1
			hl.OutlineColor = Palette.UiDanger
			hl.DepthMode = Enum.HighlightDepthMode.Occluded
			hl.Parent = warn
		end
	end
	-- Posts at both ends
	for _, z in { zA, zB } do
		local y = z == zA and 0 or rise
		local postKit = kit(ctx, "K11_ZipPost", 0, y, z)
		for _, s in { -1, 1 } do
			local post = newPart(
				ctx.solid,
				L(ctx, s * (HALF - 0.5), y + 6, z),
				Vector3.new(2, 12, 2),
				Palette.Trunk,
				Enum.Material.Wood
			)
			post.CanQuery = false
			if postKit then
				hide(post)
			end
		end
		local bar = newPart(
			ctx.solid,
			L(ctx, 0, y + cableY + 0.9, z),
			Vector3.new(W, 1.2, 1.2),
			Palette.Trunk,
			Enum.Material.Wood
		)
		bar.CanQuery = false
		if postKit then
			hide(bar)
		end
	end
	-- Grab trigger at the ledge end.
	local grab =
		newPart(ctx.model, L(ctx, 0, 7, ledge), Vector3.new(W, 16, 12), Palette.UiGold, Enum.Material.SmoothPlastic)
	grab.Transparency = 1
	grab.CanCollide = false
	grab.Name = "ZipStart"
	CollectionService:AddTag(grab, "ZipStart")
	return { length = len, exit = exitAt(ctx, len, rise), turn = 0 }
end

local function corner(ctx: Ctx, turn: number): Result
	-- Square junction W x W. Entry from z = 0; the exit leaves through the `turn` side.
	local cornerKit = kit(ctx, turn == 1 and "K02_CornerRight" or "K02_CornerLeft", 0, 0, 0)
	kitOff = cornerKit ~= nil
	floor(ctx, 0, W)
	for _, f in ctx.solid:GetChildren() do
		if f:GetAttribute("Heading") then
			f:SetAttribute("Corner", true) -- client skips its heading safety check here
		end
	end
	local back = newPart(
		ctx.solid,
		L(ctx, 0, Config.WallHeight / 2 + 1, W + 1),
		Vector3.new(W + 4, Config.WallHeight + 6, 2),
		Palette.StoneLight,
		Enum.Material.Slate
	)
	back:SetAttribute("Turn", turn)
	if not ctx.auto then
		CollectionService:AddTag(back, "TurnWall")
	end
	-- Carved idol face on the dead end so the corner reads early
	local face =
		newPart(ctx.solid, L(ctx, 0, 6, W - 0.3), Vector3.new(8, 8, 0.6), Palette.StoneMoss, Enum.Material.Slate)
	face.CanQuery = false
	if cornerKit then
		hide(back)
		hide(face)
	end
	wall(ctx, -turn, 0, W + 2)
	kitOff = false
	local j =
		newPart(ctx.model, L(ctx, 0, 6, W / 2), Vector3.new(W, 14, W), Palette.UiGold, Enum.Material.SmoothPlastic)
	j.Transparency = 1
	j.CanCollide = false
	j.Name = "Junction"
	j:SetAttribute("Turn", turn)
	j:SetAttribute("Auto", ctx.auto == true)
	CollectionService:AddTag(j, "Junction")
	-- Outer side and back decor (the inside corner is covered by the neighbouring pieces)
	local rng = ctx.rng
	for i = 1, 3 do
		local t = L(ctx, -turn * (HALF + rng:NextNumber(9, 26)), -1.2, rng:NextNumber(0, W))
		tree(ctx, CFrame.new(t.Position))
	end
	local exit = ctx.entry
		* CFrame.new(0, 0, -HALF)
		* CFrame.Angles(0, turn == 1 and -math.pi / 2 or math.pi / 2, 0)
		* CFrame.new(0, 0, -HALF)
	if ctx.auto then
		-- a route corner: no back cliff (it would stand where the routes rejoin)
		return { length = W, exit = exit, turn = turn }
	end
	local c = L(ctx, 0, 0, W + 30)
	local topY = ctx.entry.Y + rng:NextNumber(25, 55)
	decorPart(
		ctx,
		CFrame.new(c.X, (topY + WATER_Y) / 2, c.Z) * c.Rotation,
		Vector3.new(W + 60, topY - WATER_Y, 40),
		Palette.Cliff,
		Enum.Material.Rock
	)
	local exit = ctx.entry
		* CFrame.new(0, 0, -HALF)
		* CFrame.Angles(0, turn == 1 and -math.pi / 2 or math.pi / 2, 0)
		* CFrame.new(0, 0, -HALF)
	return { length = W, exit = exit, turn = turn }
end

function Segments.turnLeft(ctx: Ctx): Result
	return corner(ctx, -1)
end

function Segments.turnRight(ctx: Ctx): Result
	return corner(ctx, 1)
end

-- A visible plank (wood) that runners stand on: solid, tagged Floor like the path.
local function plank(ctx: Ctx, cf: CFrame, size: Vector3): Part
	local p = newPart(ctx.solid, cf, size, Palette.WoodPlank, Enum.Material.WoodPlanks)
	p:SetAttribute("Heading", ctx.entry.LookVector)
	CollectionService:AddTag(p, "Floor")
	return p
end

-- Plank walk: the path thins to single-file planks over the water and zigzags.
--   0..10 path, a 5-wide plank straight on (10..36), a wide 14x14 landing to step sideways
--   onto a second plank 9 studs over (50..74), a landing back (74..88), a last plank (88..100),
--   then path again. Planks are 5 wide (a runner is ~2) so there is leeway; the landings are
--   long enough to make the sideways move at full speed. Side (left/right) is random.
Segments.PLANK = { { 10, 36, 0 }, { 50, 74, 1 }, { 88, 100, 0 } } -- z0, z1, offset (x 0 or 9 * side)
Segments.PLANK_LANDINGS = { { 36, 50 }, { 74, 88 } }
function Segments.plank(ctx: Ctx): Result
	local len = 110
	local s = ctx.rng:NextNumber() < 0.5 and -1 or 1
	ctx.model:SetAttribute("PlankSide", s)
	floor(ctx, 0, 10)
	floor(ctx, 100, len)
	kit(ctx, "K04_GapEnd", 0, 0, 0, false, 10 / 26)
	kit(ctx, "K04_GapEnd", 0, 0, len, true, 10 / 26)
	for _, side in { -1, 1 } do
		wall(ctx, side, 0, 10)
		wall(ctx, side, 100, len)
	end
	sides(ctx, 0, len)
	for _, p in Segments.PLANK do
		local x = p[3] * 9 * s
		plank(ctx, L(ctx, x, -0.5, (p[1] + p[2]) / 2), Vector3.new(5, 1, p[2] - p[1]))
		-- posts at the plank's ends
		for _, z in { p[1] + 0.6, p[2] - 0.6 } do
			for _, dx in { -2.7, 2.7 } do
				local post = newPart(
					ctx.model,
					L(ctx, x + dx, 0.4, z),
					Vector3.new(0.6, 2.2, 0.6),
					Palette.Trunk,
					Enum.Material.Wood
				)
				post.CanCollide = false
				post.CanQuery = false
			end
		end
		-- stilts down to the water
		local c = L(ctx, x, 0, (p[1] + p[2]) / 2)
		local top = c.Y - 1
		local st = newPart(
			ctx.decor,
			CFrame.new(c.X, (top + WATER_Y) / 2, c.Z) * c.Rotation,
			Vector3.new(1.2, top - WATER_Y, 1.2),
			Palette.Trunk,
			Enum.Material.Wood
		)
		st.CanQuery = false
		-- gems along the plank reward the steady line
		for z = p[1] + 4, p[2] - 4, 12 do
			pickup(ctx, L(ctx, x, 2.2, z), "Gem")
		end
	end
	for _, l in Segments.PLANK_LANDINGS do
		plank(ctx, L(ctx, 4.5 * s, -0.5, (l[1] + l[2]) / 2), Vector3.new(14, 1, l[2] - l[1]))
	end
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Plank jump: a straight plank bridge over the water with one easy gap to jump (like the stone
-- gap, on wood). Attributes GapA/GapB as for Segments.gap, so bots and falls work the same.
Segments.PLANKGAP = { a = 30, g = 7, w = 12 }
function Segments.plankGap(ctx: Ctx): Result
	local len = 72
	local P = Segments.PLANKGAP
	local a, b = P.a, P.a + P.g
	floor(ctx, 0, 10)
	floor(ctx, len - 10, len)
	kit(ctx, "K04_GapEnd", 0, 0, 0, false, 10 / 26)
	kit(ctx, "K04_GapEnd", 0, 0, len, true, 10 / 26)
	for _, side in { -1, 1 } do
		wall(ctx, side, 0, 10)
		wall(ctx, side, len - 10, len)
	end
	sides(ctx, 0, len)
	for _, span in { { 10, a }, { b, len - 10 } } do
		local z0, z1 = span[1], span[2]
		plank(ctx, L(ctx, 0, -0.5, (z0 + z1) / 2), Vector3.new(P.w, 1, z1 - z0))
		-- rails posts at the ends, stilts down to the water
		for _, z in { z0 + 0.6, z1 - 0.6 } do
			for _, dx in { -P.w / 2 + 0.3, P.w / 2 - 0.3 } do
				local post = newPart(
					ctx.model,
					L(ctx, dx, 0.4, z),
					Vector3.new(0.6, 2.2, 0.6),
					Palette.Trunk,
					Enum.Material.Wood
				)
				post.CanCollide = false
				post.CanQuery = false
				local c = L(ctx, dx, 0, z)
				local top = c.Y - 1
				local st = newPart(
					ctx.decor,
					CFrame.new(c.X, (top + WATER_Y) / 2, c.Z) * c.Rotation,
					Vector3.new(1, top - WATER_Y, 1),
					Palette.Trunk,
					Enum.Material.Wood
				)
				st.CanQuery = false
			end
		end
	end
	ctx.model:SetAttribute("GapA", a)
	ctx.model:SetAttribute("GapB", b)
	bottles(ctx, a - 2, b + 2, 0, 4)
	for z = 14, a - 4, 12 do
		pickup(ctx, L(ctx, 0, 2.2, z), "Gem")
	end
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Fork: a rock ridge splits the path into a left and a right route for a stretch, then they
-- join again. One route has logs to slide under, the other low hurdles to jump (sides random),
-- each with its own pickups, so the field splits up for a bit and meets again after.
-- Attributes: ForkZ0/ForkZ1 (the ridge), ObsZ1/ObsZ2, SlideSide (-1 left / 1 right).
Segments.FORK = { z0 = 22, z1 = 168, obs = { 62, 118 } }
function Segments.fork(ctx: Ctx): Result
	local len = 190
	straightBase(ctx, len)
	local F = Segments.FORK
	local slideSide = ctx.rng:NextNumber() < 0.5 and -1 or 1
	ctx.model:SetAttribute("ForkZ0", F.z0)
	ctx.model:SetAttribute("ForkZ1", F.z1)
	ctx.model:SetAttribute("ObsZ1", F.obs[1])
	ctx.model:SetAttribute("ObsZ2", F.obs[2])
	ctx.model:SetAttribute("SlideSide", slideSide)
	-- the ridge: tall rock down the middle with tapered ends
	local mid = (F.z0 + F.z1) / 2
	local ridge =
		newPart(ctx.solid, L(ctx, 0, 6, mid), Vector3.new(4, 12, F.z1 - F.z0 - 8), Palette.Cliff, Enum.Material.Rock)
	ridge.Name = "ForkRidge"
	for _, z in { F.z0 + 2, F.z1 - 2 } do
		local tip = newPart(
			ctx.solid,
			L(ctx, 0, 4, z) * CFrame.Angles(0, math.pi / 4, 0),
			Vector3.new(3, 8, 3),
			Palette.Cliff,
			Enum.Material.Rock
		)
		tip.Name = "ForkRidge"
	end
	local cap = newPart(
		ctx.model,
		L(ctx, 0, 12.4, mid),
		Vector3.new(5, 1.2, F.z1 - F.z0 - 6),
		Palette.CanopyDeep,
		Enum.Material.Grass
	)
	cap.CanCollide = false
	cap.CanQuery = false
	local laneW = HALF - 2.5 -- each route's width
	for _, side in { -1, 1 } do
		local x = side * (2 + laneW / 2)
		for _, z in F.obs do
			if side == slideSide then
				local log = newPart(
					ctx.model,
					L(ctx, x, 5.6, z),
					Vector3.new(laneW + 1, 2.8, 2.8),
					Palette.Trunk,
					Enum.Material.Wood
				)
				log.Shape = Enum.PartType.Cylinder
				log.CanCollide = false
				CollectionService:AddTag(log, "Duck")
			else
				local hurdle = newPart(
					ctx.model,
					L(ctx, x, 1.1, z),
					Vector3.new(laneW, 2.2, 1.2),
					Palette.WoodPlank,
					Enum.Material.WoodPlanks
				)
				hurdle.Name = "Hurdle"
				hurdle.CanCollide = false
				CollectionService:AddTag(hurdle, "Block")
			end
		end
		-- each route's own pickups between the obstacles
		for z = F.obs[1] + 12, F.obs[2] - 12, 10 do
			pickup(ctx, L(ctx, x, 2.2, z), (side == slideSide) and "Juice" or "Gem")
		end
	end
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Split route: one side ramps up to an upper deck and back down; the other side runs on below.
-- Upper: gems, narrow, falling off its inner edge just drops you to the lower route.
-- Lower: a juice line. Both rejoin before the end. Side is random.
Segments.SPLIT = { up0 = 14, up1 = 38, deck1 = 96, down1 = 120, h = 12, x = 6.5 }
function Segments.split(ctx: Ctx): Result
	local len = 132
	local S = Segments.SPLIT
	local s = ctx.rng:NextNumber() < 0.5 and -1 or 1
	ctx.model:SetAttribute("SplitSide", s)
	straightBase(ctx, len)
	local x = S.x * s
	local wDeck = 9
	local function ramp(z0: number, z1: number, rising: boolean)
		local run = z1 - z0
		local a = math.atan2(S.h, run)
		local l = math.sqrt(run * run + S.h * S.h)
		local cf = L(ctx, x, S.h / 2, (z0 + z1) / 2) * CFrame.Angles(rising and a or -a, 0, 0) * CFrame.new(0, -0.5, 0)
		plank(ctx, cf, Vector3.new(wDeck, 1, l + 0.6))
	end
	ramp(S.up0, S.up1, true)
	plank(ctx, L(ctx, x, S.h - 0.5, (S.up1 + S.deck1) / 2), Vector3.new(wDeck, 1, S.deck1 - S.up1 + 0.2))
	ramp(S.deck1, S.down1, false)
	-- the space under the way down is filled in, so the lower route can't run into its underside
	local under = newPart(
		ctx.solid,
		L(ctx, x, S.h / 4, (S.deck1 + S.down1) / 2 - 3),
		Vector3.new(wDeck - 0.4, S.h / 2, S.down1 - S.deck1 - 8),
		Palette.StoneShadow,
		Enum.Material.Slate
	)
	CollectionService:AddTag(under, "Block")
	-- stone posts under the deck on the wall side
	for z = S.up1 + 4, S.deck1 - 2, 14 do
		local post = newPart(
			ctx.solid,
			L(ctx, s * (HALF - 1.2), (S.h - 1) / 2, z),
			Vector3.new(1.6, S.h - 1, 1.6),
			Palette.StoneMoss,
			Enum.Material.Slate
		)
		post.CanQuery = false
	end
	-- arrow markers on the floor at the fork
	-- rewards: gems up top, juice below
	for z = S.up1 + 6, S.deck1 - 6, 7 do
		pickup(ctx, L(ctx, x, S.h + 2.2, z), "Gem")
	end
	for z = S.up1 + 10, S.deck1 - 10, 16 do
		pickup(ctx, L(ctx, -s * 5, 2.2, z), "Juice")
	end
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Mud slide: a muddy chute drops 20 studs. Mud speeds you up (tag Mud, read by the client).
-- The chute is 3 lanes of 8-stud tiles; some tiles are missing (holes to the water) with a
-- glowing orange rim and a gem hanging over each, so you either steer round or jump it.
-- No row ever has every lane open to the water. Attribute Holes = "z0:lane,..." for bots.
Segments.SLIDE = { z0 = 10, row = 8, rows = 16, drop = 20 }
function Segments.slide(ctx: Ctx): Result
	local S = Segments.SLIDE
	local z1 = S.z0 + S.row * S.rows
	local len = z1 + 12
	local rng = ctx.rng
	local a = math.atan2(S.drop, z1 - S.z0)
	local tilt = CFrame.Angles(-a, 0, 0)
	local function yAt(z: number): number
		return -S.drop * math.clamp((z - S.z0) / (z1 - S.z0), 0, 1)
	end
	floor(ctx, 0, S.z0)
	floor(ctx, z1, len, -S.drop)
	for _, side in { -1, 1 } do
		wall(ctx, side, 0, S.z0)
		wall(ctx, side, z1, len, -S.drop)
	end
	sides(ctx, 0, S.z0)
	sides(ctx, S.z0, z1, -S.drop / 2, true)
	sides(ctx, z1, len, -S.drop)
	-- holes: 2 rows long (16 studs, long enough to drop into at a run), a new pair every 4 rows
	-- (32 studs apart, time to steer), never the same lane twice running
	local holes: { [number]: { [number]: boolean } } = {}
	local tags = {}
	local last = 0
	for i = 5, S.rows - 2, 4 do -- first hole 40 studs down the slope: time to settle after a turn
		local lane
		repeat
			lane = rng:NextInteger(1, 3)
		until lane ~= last
		last = lane
		local set = { [lane] = true }
		-- harder later: some get a second hole, leaving one lane
		if ctx.difficulty > 0.7 and rng:NextNumber() < 0.3 then
			set[lane == 2 and (rng:NextNumber() < 0.5 and 1 or 3) or 2] = true
		end
		holes[i], holes[i + 1] = set, set
		for l in set do
			table.insert(tags, (S.z0 + (i - 1) * S.row) .. ":" .. l)
		end
	end
	ctx.model:SetAttribute("Holes", table.concat(tags, ","))
	local tileL = S.row / math.cos(a)
	local MUD = Color3.fromRGB(112, 76, 46)
	for i = 1, S.rows do
		local zc = S.z0 + (i - 0.5) * S.row
		for lane = 1, 3 do
			local x = (lane - 2) * LANE
			local cf = L(ctx, x, yAt(zc), zc) * tilt
			if holes[i] and holes[i][lane] then
				-- glowing rim round the 2-row hole (drawn once, from its first row) and a gem over it
				if not (holes[i - 1] and holes[i - 1][lane]) then
					local hc = L(ctx, x, yAt(zc + S.row / 2), zc + S.row / 2) * tilt
					local hl = 2 * S.row / math.cos(a)
					for _, e in
						{
							{ 0, -hl / 2, LANE + 0.6, 0.6 },
							{ 0, hl / 2, LANE + 0.6, 0.6 },
							{ -LANE / 2, 0, 0.6, hl },
							{ LANE / 2, 0, 0.6, hl },
						}
					do
						local rim = newPart(
							ctx.model,
							hc * CFrame.new(e[1], 0.15, e[2]),
							Vector3.new(e[3], 0.5, e[4]),
							Palette.UiDanger,
							Enum.Material.Neon
						)
						rim.CanCollide = false
						rim.CanQuery = false
					end
					pickup(ctx, L(ctx, x, yAt(zc + S.row / 2) + 3.5, zc + S.row / 2), "Gem")
				end
			else
				local t = newPart(
					ctx.solid,
					cf * CFrame.new(0, -0.5, 0),
					Vector3.new(LANE, 1, tileL + 0.05),
					MUD,
					Enum.Material.Mud
				)
				t:SetAttribute("Heading", ctx.entry.LookVector)
				CollectionService:AddTag(t, "Floor")
			end
		end
	end
	-- mud volume (speeds you up) and the chute's sloped side walls
	local mid = L(ctx, 0, yAt((S.z0 + z1) / 2), (S.z0 + z1) / 2) * tilt
	local mud = newPart(
		ctx.model,
		mid * CFrame.new(0, 0.6, 0),
		Vector3.new(W, 1.2, (z1 - S.z0) / math.cos(a)),
		MUD,
		Enum.Material.Mud
	)
	mud.Transparency = 1
	mud.CanCollide = false
	CollectionService:AddTag(mud, "Mud")
	for _, side in { -1, 1 } do
		local wallH = Config.WallHeight + 3
		local w = newPart(
			ctx.solid,
			mid * CFrame.new(side * (HALF + 1), Config.WallHeight - wallH / 2, 0),
			Vector3.new(2, wallH, (z1 - S.z0) / math.cos(a) + 1),
			Color3.fromRGB(92, 64, 40),
			Enum.Material.Ground
		)
		w:SetAttribute("Side", side)
		CollectionService:AddTag(w, "Wall")
		local cap = newPart(
			ctx.solid,
			mid * CFrame.new(side * (HALF + 1), Config.WallHeight + 0.35, 0),
			Vector3.new(2.6, 0.8, (z1 - S.z0) / math.cos(a) + 1.3),
			Color3.fromRGB(70, 48, 30),
			Enum.Material.Mud
		)
		cap.CanQuery = false
		local lid = newPart(
			ctx.solid,
			mid * CFrame.new(side * (HALF + 1), Config.WallHeight + 20, 0),
			Vector3.new(2, 40, (z1 - S.z0) / math.cos(a) + 1),
			MUD,
			Enum.Material.SmoothPlastic
		)
		lid.Transparency = 1
		lid.CanQuery = false
		lid.CastShadow = false
		-- stilts under the chute
		for z = S.z0 + 8, z1 - 4, 16 do
			local c = L(ctx, side * (HALF - 2), 0, z)
			local top = c.Y + yAt(z) - 1
			local st = newPart(
				ctx.decor,
				CFrame.new(c.X, (top + WATER_Y) / 2, c.Z) * c.Rotation,
				Vector3.new(1.6, top - WATER_Y, 1.6),
				Palette.Trunk,
				Enum.Material.Wood
			)
			st.CanQuery = false
		end
	end
	-- wet streaks running down the slope and mud lumps on the lip, so it reads as a mud chute
	for lane = 1, 3 do
		for _, dx in { -2.2, 1.6 } do
			local streak = newPart(
				ctx.model,
				L(ctx, (lane - 2) * LANE + dx, yAt(S.z0 + 14), S.z0 + 14) * tilt * CFrame.new(0, 0.08, 0),
				Vector3.new(0.9, 0.1, 20 / math.cos(a)),
				Color3.fromRGB(70, 46, 26),
				Enum.Material.Mud
			)
			streak.Reflectance = 0.15
			streak.CanCollide = false
			streak.CanQuery = false
		end
	end
	for _, side in { -1, 1 } do
		for i = 0, 3 do
			local r = rng:NextNumber(2.5, 4)
			local lump = newPart(
				ctx.model,
				L(ctx, side * (HALF - 1.5), -0.6, S.z0 - 3 + i * 2),
				Vector3.new(r, r * 0.6, r),
				Color3.fromRGB(96, 64, 38),
				Enum.Material.Mud
			)
			lump.Shape = Enum.PartType.Ball
			lump.CanCollide = false
			lump.CanQuery = false
		end
	end
	pickup(ctx, L(ctx, 0, 1.8, 5), "Juice")
	return { length = len, exit = exitAt(ctx, len, -S.drop), turn = 0 }
end

-- Boulder hop: the path stops at the water. Three big boulders (flat worn tops) zigzag across;
-- jump boulder to boulder and on to the far bank. Miss and you fall in.
-- Attributes BZ / BX = the boulders' centres along / across the path, for bots.
Segments.BOULDER_R = 7
function Segments.boulders(ctx: Ctx): Result
	local rng = ctx.rng
	local R = Segments.BOULDER_R
	local step = math.floor(20 + 3 * ctx.difficulty)
	local bank = 14
	local zs = { bank + 3 + R, bank + 3 + R + step, bank + 3 + R + 2 * step }
	local land = zs[3] + R + 3
	local len = land + 14
	floor(ctx, 0, bank)
	floor(ctx, land, len)
	kit(ctx, "K04_GapEnd", 0, 0, 0, false, bank / 26)
	kit(ctx, "K04_GapEnd", 0, 0, len, true, (len - land) / 26)
	for _, side in { -1, 1 } do
		wall(ctx, side, 0, bank)
		wall(ctx, side, land, len)
	end
	sides(ctx, 0, bank)
	sides(ctx, bank, land, 0, true)
	sides(ctx, land, len)
	local s = rng:NextNumber() < 0.5 and -1 or 1
	local xs = { 4 * s, -4 * s, 3 * s }
	for i, z in zs do
		local x = xs[i]
		local c = L(ctx, x, 0, z)
		-- the stand-on top: a flat round stone
		local top = newPart(
			ctx.solid,
			c * CFrame.new(0, -1.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(3, R * 2, R * 2),
			Palette.StoneLight,
			Enum.Material.Rock
		)
		top.Shape = Enum.PartType.Cylinder
		top:SetAttribute("Heading", ctx.entry.LookVector)
		CollectionService:AddTag(top, "Floor")
		-- the boulder's bulk below, down into the water
		local ball = newPart(
			ctx.decor,
			c * CFrame.new(0, -R - 1.2, 0) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Vector3.new(R * 2.5, R * 2.5, R * 2.5),
			Palette.Cliff,
			Enum.Material.Rock
		)
		ball.Shape = Enum.PartType.Ball
		ball.CanQuery = false
		local depth = c.Y - 3 - WATER_Y
		if depth > 1 then
			local base = newPart(
				ctx.decor,
				CFrame.new(c.X, WATER_Y + depth / 2, c.Z),
				Vector3.new(R * 1.6, depth, R * 1.6),
				Palette.StoneShadow,
				Enum.Material.Rock
			)
			base.CanQuery = false
		end
		-- moss patch on the near side and a gem over the middle
		local moss = newPart(
			ctx.model,
			c * CFrame.new(0, 0.02, R * 0.4) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(0.1, R * 0.9, R * 0.9),
			Palette.CanopyBright,
			Enum.Material.Grass
		)
		moss.Shape = Enum.PartType.Cylinder
		moss.CanCollide = false
		moss.CanQuery = false
		pickup(ctx, L(ctx, x, 2.4, z), "Gem")
	end
	ctx.model:SetAttribute("BZ", table.concat(zs, ","))
	ctx.model:SetAttribute("BX", table.concat(xs, ","))
	ctx.model:SetAttribute("BLand", land)
	ctx.model:SetAttribute("BBank", bank)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- An invisible volume across the path: running into it shows `text` on the runner's screen.
local function warnZone(ctx: Ctx, z: number, y: number, text: string)
	local w =
		newPart(ctx.model, L(ctx, 0, y + 4, z), Vector3.new(W, 8, 3), Palette.UiDanger, Enum.Material.SmoothPlastic)
	w.Transparency = 1
	w.CanCollide = false
	w:SetAttribute("Text", text)
	CollectionService:AddTag(w, "Warn")
	return w
end

-- Vine swing (George of the Jungle): the path stops at a chasm and vines hang from branches
-- over it. Run into the grab zone (or jump into it) and you catch the first vine; the swing is
-- automatic and smooth: each vine carries you down and up, and at the midpoint between two
-- vines you are at the same height on both, so you hand over to the next one without a jerk.
-- After the last vine you are thrown onto the far ledge.
-- Attributes on the model: VineN, VineGap, VineLen, VineY (pivot height), VineZ0 (first pivot).
Segments.VINE = { n = 4, gap = 20, len = 20, y = 25, ledge = 14 }
function Segments.vines(ctx: Ctx): Result
	local V = Segments.VINE
	local z0 = V.ledge + 8
	local zEnd = z0 + (V.n - 1) * V.gap + V.gap / 2
	local far = zEnd - 2
	local len = far + 14
	floor(ctx, 0, V.ledge)
	floor(ctx, far, len)
	kit(ctx, "K04_GapEnd", 0, 0, 0, false, V.ledge / 26)
	kit(ctx, "K04_GapEnd", 0, 0, len, true, (len - far) / 26)
	for _, side in { -1, 1 } do
		wall(ctx, side, 0, V.ledge)
		wall(ctx, side, far, len)
	end
	sides(ctx, 0, V.ledge)
	sides(ctx, V.ledge, far, 0, true)
	sides(ctx, far, len)
	local vines = Instance.new("Folder")
	vines.Name = "Vines"
	vines.Parent = ctx.model
	for i = 1, V.n do
		local z = z0 + (i - 1) * V.gap
		local pivot = L(ctx, 0, V.y, z)
		-- the branch the vine hangs from, across the chasm between two big trunks
		local branch = newPart(
			ctx.model,
			pivot * CFrame.new(0, 1.2, 0),
			Vector3.new(W + 16, 2.6, 2.6),
			Palette.Trunk,
			Enum.Material.Wood
		)
		branch.Shape = Enum.PartType.Cylinder
		branch.CanQuery = false
		for _, side in { -1, 1 } do
			local c = L(ctx, side * (HALF + 8), 0, z)
			local top = c.Y + V.y + 3
			local trunk = newPart(
				ctx.model,
				CFrame.new(c.X, (top + WATER_Y) / 2, c.Z) * c.Rotation,
				Vector3.new(3.4, top - WATER_Y, 3.4),
				Palette.Trunk,
				Enum.Material.Wood
			)
			trunk.CanQuery = false
			local crown = newPart(
				ctx.model,
				CFrame.new(c.X, top + 2, c.Z),
				Vector3.new(12, 7, 12),
				Palette.CanopyMid,
				Enum.Material.Grass
			)
			crown.Shape = Enum.PartType.Ball
			crown.CanQuery = false
		end
		local v = newPart(
			vines,
			pivot * CFrame.new(0, -V.len / 2, 0),
			Vector3.new(0.6, V.len, 0.6),
			Palette.CanopyBright,
			Enum.Material.Grass
		)
		v.CanCollide = false
		v.CanQuery = false
		v.Name = "V" .. i
		v:SetAttribute("Pivot", pivot.Position)
		v:SetAttribute("Rest", v.CFrame)
		-- a leafy knot at the grip
		local knot = newPart(
			v,
			pivot * CFrame.new(0, -V.len + 0.5, 0),
			Vector3.new(1.6, 1.6, 1.6),
			Palette.CanopyMid,
			Enum.Material.Grass
		)
		knot.Shape = Enum.PartType.Ball
		knot.CanCollide = false
		knot.CanQuery = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = v, knot
		weld.Parent = knot
		knot.Anchored = false
		-- a gem at the bottom of each swing
		pickup(ctx, L(ctx, 0, V.y - V.len - 4.6 + 1.5, z), "Gem")
	end
	-- grab zone: from just before the ledge end out over the chasm, tall, so a jump grabs too
	local grab = newPart(
		ctx.model,
		L(ctx, 0, 7, V.ledge + 1),
		Vector3.new(W, 16, 12),
		Palette.UiGold,
		Enum.Material.SmoothPlastic
	)
	grab.Transparency = 1
	grab.CanCollide = false
	grab.Name = "VineStart"
	grab:SetAttribute("Dir", ctx.entry.LookVector)
	grab:SetAttribute("N", V.n)
	grab:SetAttribute("Gap", V.gap)
	grab:SetAttribute("Len", V.len)
	CollectionService:AddTag(grab, "VineStart")
	ctx.model:SetAttribute("VineZ0", z0)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Tiger charge: an on-screen warning, then a tiger comes bounding back down one lane toward you.
-- Step into another lane to let it past; if it hits you, you stumble. Each runner gets their
-- own tiger (drawn on their client, client/Tiger). Attribute TigerLane = -1 or 1.
function Segments.tiger(ctx: Ctx): Result
	local len = 130
	straightBase(ctx, len)
	local lane = ctx.rng:NextNumber() < 0.5 and -1 or 1 -- left or right lane, never the middle
	ctx.model:SetAttribute("TigerLane", lane)
	local z = warnZone(ctx, 10, 0, "TIGER COMING!")
	z.Name = "TigerZone"
	-- the warning comes from client/Tiger when the charge starts, and only while the tiger is
	-- still ahead of you (a plain warn volume could fire after it had already gone past)
	CollectionService:RemoveTag(z, "Warn")
	z:SetAttribute("Tiger", true)
	z:SetAttribute("Lane", lane)
	z:SetAttribute("Dir", ctx.entry.LookVector)
	z:SetAttribute("Right", ctx.entry.RightVector)
	z:SetAttribute("Origin", L(ctx, 0, 0, 0).Position)
	bottles(ctx, 60, 120)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Wind gust: one side wall is missing for a stretch and gusts push you toward the drop.
-- An on-screen warning comes first. Steer into the wind to stay on.
-- Attributes WindSide (+1 right / -1 left), WindZ0, WindZ1.
Segments.WIND = { z0 = 30, z1 = 86 }
function Segments.wind(ctx: Ctx): Result
	local len = 110
	local Wd = Segments.WIND
	local side = ctx.rng:NextNumber() < 0.5 and -1 or 1
	floor(ctx, 0, len)
	kit(ctx, STRAIGHTS[ctx.rng:NextInteger(1, #STRAIGHTS)], 0, 0, 0, false, len / 60)
	wall(ctx, -side, 0, len)
	wall(ctx, side, 0, Wd.z0)
	wall(ctx, side, Wd.z1, len)
	sides(ctx, 0, len)
	ctx.model:SetAttribute("WindSide", side)
	ctx.model:SetAttribute("WindZ0", Wd.z0)
	ctx.model:SetAttribute("WindZ1", Wd.z1)
	warnZone(ctx, 16, 0, side > 0 and "WIND GUST! LEAN LEFT" or "WIND GUST! LEAN RIGHT")
	-- the windy stretch: pushes you sideways while you are in it (client/Runner)
	local zone = newPart(
		ctx.model,
		L(ctx, 0, 5, (Wd.z0 + Wd.z1) / 2),
		Vector3.new(W, 10, Wd.z1 - Wd.z0),
		Palette.UiDanger,
		Enum.Material.SmoothPlastic
	)
	zone.Transparency = 1
	zone.CanCollide = false
	zone:SetAttribute("Side", side)
	zone:SetAttribute("Right", ctx.entry.RightVector)
	CollectionService:AddTag(zone, "Wind")
	-- what the wind looks like is drawn on each client (client/WindFx)
	-- low danger kerb along the open edge so the drop reads
	local kerb = newPart(
		ctx.model,
		L(ctx, side * (HALF - 0.4), 0.35, (Wd.z0 + Wd.z1) / 2),
		Vector3.new(0.8, 0.5, Wd.z1 - Wd.z0),
		Palette.UiDanger,
		Enum.Material.Neon
	)
	kerb.CanCollide = false
	kerb.CanQuery = false
	-- bent palms on the windward side
	for z = Wd.z0 + 4, Wd.z1 - 4, 13 do
		local c = L(ctx, -side * (HALF + 6), 0, z)
		local trunk = newPart(
			ctx.decor,
			CFrame.new(c.Position + Vector3.new(0, 7, 0)) * c.Rotation * CFrame.Angles(0, 0, -side * 0.35),
			Vector3.new(1.4, 14, 1.4),
			Palette.Trunk,
			Enum.Material.Wood
		)
		trunk.CanQuery = false
	end
	bottles(ctx, Wd.z0 + 6, Wd.z1 - 6)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Spike beds: a row of sharp spikes across all lanes but one, like a half wall you can see
-- through. Steer to the open lane; running into the spikes stumbles you.
-- Attributes Row1Z/Row1Open (open lane 1..3), Row2Z/Row2Open on harder runs.
local SPIKE_STEEL = Color3.fromRGB(176, 182, 190)
local SPIKE_TIP = Color3.fromRGB(214, 64, 52)
local function spikeBed(ctx: Ctx, x: number, z: number)
	local mesh = KIT and KIT:FindFirstChild("Spike") :: BasePart?
	if mesh then
		local h = 4.4
		local k = h / mesh.Size.Y
		for i = -1, 1 do
			local s = mesh:Clone()
			s.Size = mesh.Size * k * (i == 0 and 1.1 or 0.95)
			s.CFrame = L(ctx, x + i * (LANE / 3), s.Size.Y / 2, z) * CFrame.Angles(0, i * 0.9, 0)
			s.Parent = ctx.model
			local tip = newPart(
				ctx.model,
				s.CFrame * CFrame.new(0, s.Size.Y / 2 - 0.25, 0),
				Vector3.new(0.18, 0.5, 0.18),
				SPIKE_TIP,
				Enum.Material.Neon
			)
			tip.CanCollide = false
			tip.CanQuery = false
		end
		local hit = newPart(
			ctx.model,
			L(ctx, x, 2.4, z),
			Vector3.new(LANE - 0.4, 4.2, 3),
			SPIKE_TIP,
			Enum.Material.SmoothPlastic
		)
		hit.Name = "Spikes"
		hit.Transparency = 1
		hit.CanCollide = false
		CollectionService:AddTag(hit, "Spike")
		return
	end
	-- dark base slab
	local base = newPart(
		ctx.model,
		L(ctx, x, 0.3, z),
		Vector3.new(LANE - 0.6, 0.6, 3.4),
		Palette.StoneShadow,
		Enum.Material.Slate
	)
	base.CanCollide = false
	base.CanQuery = false
	-- the spikes: thin pointed blades (two wedges back to back) in two staggered rows
	local n = math.floor((LANE - 1) / 1.6)
	for r = 0, 1 do
		for i = 0, n - 1 do
			local sx = x - (LANE - 1) / 2 + (i + 0.5 + r * 0.5) * ((LANE - 1.6) / n)
			local sz = z - 0.8 + r * 1.6
			local h = 3.2 + ((i + r) % 3) * 0.6
			local cf = L(ctx, sx, 0.6 + h / 2, sz) * CFrame.Angles(0, (i % 2 == 0) and 0.6 or -0.6, 0)
			for _, flip in { 0, math.pi } do
				local w = Instance.new("WedgePart")
				w.Anchored = true
				w.CanCollide = false
				w.CanQuery = false
				w.CanTouch = false
				w.Material = Enum.Material.Metal
				w.Color = SPIKE_STEEL
				w.Size = Vector3.new(0.5, h, 0.55)
				w.CFrame = cf * CFrame.Angles(0, flip, 0) * CFrame.new(0, 0, -0.275)
				w.Parent = ctx.model
			end
			local tip = newPart(
				ctx.model,
				cf * CFrame.new(0, h / 2 - 0.35, 0),
				Vector3.new(0.52, 0.7, 0.3),
				SPIKE_TIP,
				Enum.Material.Neon
			)
			tip.CanCollide = false
			tip.CanQuery = false
		end
	end
	-- what you run into
	local hit =
		newPart(ctx.model, L(ctx, x, 2.4, z), Vector3.new(LANE - 0.4, 4.2, 3), SPIKE_TIP, Enum.Material.SmoothPlastic)
	hit.Name = "Spikes"
	hit.Transparency = 1
	hit.CanCollide = false
	CollectionService:AddTag(hit, "Spike")
end

function Segments.spikes(ctx: Ctx): Result
	local len = 84
	straightBase(ctx, len)
	local rng = ctx.rng
	local zs = { 30 }
	if rng:NextNumber() < 0.3 + 0.5 * ctx.difficulty then
		table.insert(zs, 62)
	end
	local lastOpen = 0
	for i, z in zs do
		local open
		repeat
			open = rng:NextInteger(1, 3)
		until open ~= lastOpen
		lastOpen = open
		ctx.model:SetAttribute("Row" .. i .. "Z", z)
		ctx.model:SetAttribute("Row" .. i .. "Open", open)
		for lane = 1, 3 do
			if lane ~= open then
				spikeBed(ctx, (lane - 2) * LANE, z)
			end
		end
		pickup(ctx, L(ctx, (open - 2) * LANE, 2.2, z), "Gem")
	end
	bottles(ctx, 6, 22)
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Plain stretch of any length (ctx.len), cut into kit-sized pieces so nothing is stretched far.
-- On a side route (ctx.theme) it carries that route's prize: a weaving line of gems or juice.
function Segments.filler(ctx: Ctx): Result
	local len = ctx.len or 60
	floor(ctx, 0, len)
	wall(ctx, -1, 0, len)
	wall(ctx, 1, 0, len)
	local n = math.max(1, math.ceil(len / 60 - 0.1))
	local seg = len / n
	for i = 0, n - 1 do
		kit(ctx, STRAIGHTS[ctx.rng:NextInteger(1, #STRAIGHTS)], 0, 0, i * seg, false, seg / 60)
		sides(ctx, i * seg, (i + 1) * seg)
	end
	if ctx.theme and len >= 14 then
		local k = 0
		for z = 7, len - 7, 8 do
			k += 1
			pickup(ctx, L(ctx, math.sin(k * 0.7) * LANE * 0.8, 2.2, z), ctx.theme)
		end
	elseif len >= 24 then
		bottles(ctx, 8, len - 8)
	end
	return { length = len, exit = exitAt(ctx, len), turn = 0 }
end

-- Four carved posts at the corners of a W x W square, for the crossroads and the merge.
local function squarePosts(ctx: Ctx)
	for _, x in { -1, 1 } do
		for _, z in { 0, W } do
			local post = newPart(
				ctx.solid,
				L(ctx, x * (HALF + 1.5), 6, z),
				Vector3.new(3, 12, 3),
				Palette.StoneMoss,
				Enum.Material.Slate
			)
			post.CanQuery = false
			local cap = newPart(
				ctx.solid,
				L(ctx, x * (HALF + 1.5), 12.6, z),
				Vector3.new(4, 1.2, 4),
				Palette.StoneLight,
				Enum.Material.Slate
			)
			cap.CanQuery = false
		end
	end
end

-- Crossroads: the start of a route block (PathService). A square open left, right and ahead.
-- Flick left or right inside it to take that route; do nothing and you carry straight on.
-- A stone board over the far side names each way (ctx.signs). Junction attribute Fork.
function Segments.crossroads(ctx: Ctx): Result
	floor(ctx, 0, W)
	for _, f in ctx.solid:GetChildren() do
		if f:GetAttribute("Heading") then
			f:SetAttribute("Corner", true)
		end
	end
	squarePosts(ctx)
	local j =
		newPart(ctx.model, L(ctx, 0, 6, W / 2), Vector3.new(W, 14, W), Palette.UiGold, Enum.Material.SmoothPlastic)
	j.Transparency = 1
	j.CanCollide = false
	j.Name = "Junction"
	j:SetAttribute("Fork", true)
	CollectionService:AddTag(j, "Junction")
	-- the board: over the way ahead, high enough to run under, facing you as you come in
	local board =
		newPart(ctx.solid, L(ctx, 0, 17, W + 1.5), Vector3.new(W + 6, 7, 1.4), Palette.StoneLight, Enum.Material.Slate)
	board.CanQuery = false
	board.CanCollide = false
	for _, x in { -1, 1 } do
		local leg = newPart(
			ctx.solid,
			L(ctx, x * (HALF + 1.5), 16, W + 1.5),
			Vector3.new(2, 4, 2),
			Palette.StoneMoss,
			Enum.Material.Slate
		)
		leg.CanQuery = false
		leg.CanCollide = false
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = board
	local signs = ctx.signs or {}
	for i, way in { -1, 0, 1 } do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1 / 3, 1)
		t.Position = UDim2.fromScale((i - 1) / 3, 0)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Palette.UiGold
		local arrow = way == -1 and "<  " or (way == 1 and "" or "^ ")
		local after = way == 1 and "  >" or ""
		t.Text = arrow .. (signs[way] or "") .. after
		local s = Instance.new("UIStroke")
		s.Color = Palette.UiRim
		s.Thickness = 4
		s.Parent = t
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.18, 0)
		pad.PaddingBottom = UDim.new(0.18, 0)
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.PaddingRight = UDim.new(0.04, 0)
		pad.Parent = t
		t.Parent = gui
	end
	return { length = W, exit = exitAt(ctx, W), turn = 0 }
end

-- Merge: the end of a route block. Open left, right and behind; the side routes come in from
-- the sides and are turned onto the way ahead by themselves (Junction attribute Out).
function Segments.merge(ctx: Ctx): Result
	floor(ctx, 0, W)
	for _, f in ctx.solid:GetChildren() do
		if f:GetAttribute("Heading") then
			f:SetAttribute("Corner", true)
		end
	end
	squarePosts(ctx)
	local j =
		newPart(ctx.model, L(ctx, 0, 6, W / 2), Vector3.new(W, 14, W), Palette.UiGold, Enum.Material.SmoothPlastic)
	j.Transparency = 1
	j.CanCollide = false
	j.Name = "Junction"
	j:SetAttribute("Auto", true)
	j:SetAttribute("Out", ctx.entry.LookVector)
	CollectionService:AddTag(j, "Junction")
	return { length = W, exit = exitAt(ctx, W), turn = 0 }
end

-- Corridor (in local space) a piece will occupy, used to clear older decor out of its way.
function Segments.footprint(kind: string, len: number?): (number, number)
	-- returns length, extra width
	if kind == "filler" then
		return len or 60, 8
	elseif kind == "crossroads" or kind == "merge" then
		return W + 2, 8
	elseif kind == "turnLeft" or kind == "turnRight" then
		return W + 2, 8
	elseif kind == "stairsUp" or kind == "stairsDown" then
		return 48, 8
	elseif kind == "bridge" then
		return 56, 8
	elseif kind == "zipline" then
		return 108, 8
	elseif kind == "plank" then
		return 110, 8
	elseif kind == "plankGap" then
		return 72, 8
	elseif kind == "fork" then
		return 190, 8
	elseif kind == "split" then
		return 132, 8
	elseif kind == "slide" then
		return 150, 8
	elseif kind == "boulders" then
		return 100, 8
	elseif kind == "vines" then
		return 112, 24
	elseif kind == "tiger" then
		return 130, 8
	elseif kind == "wind" then
		return 110, 8
	elseif kind == "spikes" then
		return 84, 8
	end
	return 60, 8
end

return Segments
