--!strict
-- Endless path. It joins pieces end to end from a seed, keeps Config.GenerateAhead studs
-- built past the leader, and deletes pieces behind the Guardian.
--
-- Turns are limited so the heading stays within ±90° of the start heading (-Z). The path then
-- always makes progress along -Z and can never cross itself. Each new piece first clears older
-- decor out of its corridor, and decor is never placed over floors or walls.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Segments = require(script.Parent.Segments)

local W = Config.PathWidth

export type Segment = {
	index: number,
	kind: string,
	entry: CFrame,
	exit: CFrame,
	length: number,
	startDist: number,
	turn: number,
	model: Model,
	solid: Folder,
	decor: Folder,
}

local PathService = {}

local root: Folder
local segments: { Segment } = {}
local rng = Random.new()
local quarter = 0 -- -1, 0, +1 : heading relative to -Z
local sinceTurn = 0
local elevation = 0
local bottleId = 0
local builtDist = 0

local function solidFolders(): { Instance }
	local t = {}
	for _, s in segments do
		table.insert(t, s.solid)
	end
	return t
end

local function decorFolders(): { Instance }
	local t = {}
	for _, s in segments do
		table.insert(t, s.decor)
	end
	return t
end

local function overlap(include: { Instance }): OverlapParams
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = include
	return p
end

local function pickKind(): string
	local n = #segments
	if n < 3 then
		return "straight"
	end
	local d = math.clamp(builtDist / 4000, 0, 1)
	local weights: { [string]: number } = {
		straight = 3.5 - 2 * d,
		hurdle = 1.4 + 1.0 * d,
		duck = 1.4 + 1.0 * d,
		gap = 0.9 + 1.3 * d,
		bridge = 0.7,
		halfWall = 1.1 + 0.8 * d,
		tar = 0.8 + 0.6 * d,
		zipline = (elevation < 24 and n > 4) and 0.6 or 0,
		stairsUp = elevation < 24 and 0.7 or 0,
		stairsDown = elevation > -8 and 0.7 or 0,
	}
	if sinceTurn >= 2 then
		local tw = 1.5
		if quarter > -1 then
			weights.turnLeft = tw
		end
		if quarter < 1 then
			weights.turnRight = tw
		end
	end
	-- Never two hard obstacles in a row early on
	local last = segments[n].kind
	if d < 0.4 and (last == "gap" or last == "hurdle" or last == "duck" or last == "halfWall" or last == "tar" or last == "zipline") then
		weights.gap, weights.hurdle, weights.duck, weights.halfWall, weights.tar, weights.zipline = 0, 0, 0, 0, 0, 0
	end
	local total = 0
	for _, w in weights do
		total += w
	end
	local r = rng:NextNumber() * total
	for k, w in weights do
		r -= w
		if r <= 0 then
			return k
		end
	end
	return "straight"
end

local function build(kind: string, entry: CFrame)
	local model = Instance.new("Model")
	model.Name = string.format("%03d_%s", #segments + 1, kind)
	local solid = Instance.new("Folder")
	solid.Name = "Solid"
	solid.Parent = model
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = model

	-- Clear older decor out of this piece's corridor.
	-- Box is kept just inside the floor + walls (banks start at W/2 + 2) and short of the
	-- entry, so neighbouring banks that merely touch the corridor survive.
	local len = Segments.footprint(kind)
	local corridorCF = entry * CFrame.new(0, 10, -len / 2 - 1)
	local hits = workspace:GetPartBoundsInBox(corridorCF, Vector3.new(W + 2, 60, len - 4), overlap(decorFolders()))
	for _, part in hits do
		part:Destroy()
	end

	local solids = solidFolders()
	table.insert(solids, solid)
	local params = overlap(solids)

	local ctx: Segments.Ctx = {
		rng = rng,
		entry = entry,
		model = model,
		solid = solid,
		decor = decor,
		difficulty = math.clamp(builtDist / 4000, 0, 1),
		nextBottleId = function()
			bottleId += 1
			return bottleId
		end,
		isFree = function(cf: CFrame, size: Vector3): boolean
			return #workspace:GetPartBoundsInBox(cf, size, params) == 0
		end,
	}
	local builder = (Segments :: any)[kind]
	local res: Segments.Result = builder(ctx)
	model.Parent = root

	local seg: Segment = {
		index = #segments + 1,
		kind = kind,
		entry = entry,
		exit = res.exit,
		length = res.length,
		startDist = builtDist,
		turn = res.turn,
		model = model,
		solid = solid,
		decor = decor,
	}
	model:SetAttribute("StartDist", builtDist)
	table.insert(segments, seg)
	builtDist += res.length
	if res.turn ~= 0 then
		quarter += res.turn
		sinceTurn = 0
	else
		sinceTurn += 1
	end
	if kind == "stairsUp" then
		elevation += 8
	elseif kind == "stairsDown" then
		elevation -= 8
	elseif kind == "zipline" then
		elevation += 16
	end
end

function PathService.reset(seed: number)
	if root then
		root:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "Path"
	root.Parent = workspace
	segments = {}
	rng = Random.new(seed)
	quarter, sinceTurn, elevation, bottleId, builtDist = 0, 0, 0, 0, 0
	build("start", CFrame.new(0, 0, 0))
	-- The start piece's gate is at z = 50; distance 0 is at the gate.
	builtDist -= 50
	segments[1].startDist = -50
end

function PathService.ensureAhead(leaderDist: number)
	while builtDist < leaderDist + Config.GenerateAhead do
		local last = segments[#segments]
		build(pickKind(), last.exit)
	end
end

function PathService.trimBehind(dist: number)
	while #segments > 2 and segments[1].startDist + segments[1].length < dist - Config.DeleteBehind do
		local s = table.remove(segments, 1) :: Segment
		s.model:Destroy()
	end
end

local function segmentAt(dist: number): Segment
	for i = #segments, 1, -1 do
		if segments[i].startDist <= dist then
			return segments[i]
		end
	end
	return segments[1]
end

-- CFrame on the path centreline at a distance, facing the run heading there.
function PathService.pointAt(dist: number): CFrame
	local s = segmentAt(dist)
	local t = math.clamp(dist - s.startDist, 0, s.length)
	if s.turn == 0 then
		local a = t / s.length
		local pos = s.entry.Position:Lerp(s.exit.Position, a)
		return CFrame.lookAt(pos, pos + s.entry.LookVector)
	end
	local half = s.length / 2
	if t <= half then
		return s.entry * CFrame.new(0, 0, -t)
	end
	local centre = s.entry * CFrame.new(0, 0, -half)
	local exitRot = s.exit.Rotation
	return CFrame.new(centre.Position) * exitRot * CFrame.new(0, 0, -(t - half))
end

-- Progress along the path for a world position. hint = last known segment index.
-- Returns distance, the segment, and whether the position is over that segment.
function PathService.progress(pos: Vector3, hintDist: number): (number, Segment?)
	local startIdx = 1
	for i, s in segments do
		if s.startDist <= hintDist then
			startIdx = i
		end
	end
	for i = startIdx, math.min(startIdx + 4, #segments) do
		local s = segments[i]
		local lp = s.entry:PointToObjectSpace(pos)
		local f = -lp.Z
		if s.turn == 0 then
			if f >= -1 and f <= s.length + 1 and math.abs(lp.X) < W / 2 + 10 then
				return s.startDist + math.clamp(f, 0, s.length), s
			end
		else
			if f >= -1 and f <= s.length + 2 and math.abs(lp.X) < W / 2 + 10 then
				local half = s.length / 2
				local along = math.clamp(f, 0, half) + math.clamp(lp.X * s.turn, 0, half)
				return s.startDist + along, s
			end
		end
	end
	return hintDist, nil
end

function PathService.floorY(seg: Segment): number
	return math.min(seg.entry.Y, seg.exit.Y)
end

PathService.segmentAt = segmentAt

-- Every built piece's Solid folder (floors, walls, blocks).
function PathService.solids(): { Instance }
	local t = {}
	for _, s in segments do
		table.insert(t, s.solid)
	end
	return t
end

function PathService.builtDist(): number
	return builtDist
end

function PathService.startCFrame(): CFrame
	return segments[1].entry * CFrame.new(0, 3, -40)
end

function PathService.bottle(id: number): BasePart?
	if not root then
		return nil
	end
	for _, s in segments do
		for _, c in s.model:GetChildren() do
			if c:IsA("BasePart") and c:GetAttribute("BottleId") == id then
				return c
			end
		end
	end
	return nil
end

return PathService
