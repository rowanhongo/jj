--!strict
-- Endless path. It joins pieces end to end from a seed, keeps Config.GenerateAhead studs
-- built past the leader, and deletes pieces behind the Guardian.
--
-- Turns are limited so the heading stays within ±90° of the start heading (-Z). The path then
-- always makes progress along -Z and can never cross itself. Each new piece first clears older
-- decor out of its corridor, and decor is never placed over floors or walls.
--
-- Routes (docs/research/05-routes-strip-guardian.md): now and then a crossroads block is built
-- in one go: a crossroads, three routes side by side (centre = the spine, left and right = side
-- routes with their own pieces), and a merge where they meet again. Every segment has a `route`
-- (0 spine, -1 left, 1 right). Distances are RACE distance (progress toward the finish): a side
-- route is physically longer than the centre, so each stud run on it counts `rate` (< 1) studs
-- of race distance. `length` and `startDist` are race distance; physical length = length / rate.

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
	route: number, -- 0 = the spine, -1 / 1 = the left / right side route of a crossroads block
	rate: number, -- race studs per physical stud (1 on the spine)
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
local spineLast: Segment -- the last piece on the spine (the next piece joins its exit)
local spineCount = 0
local sinceBranch = 0 -- spine pieces since the last merge
local branchLimit = math.huge -- no crossroads block may reach past this race distance (the finish)

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

-- Scenery that reaches into a runner's corridor (cf, size):
--  * a tree goes as a whole (never a trunk with no top, or a canopy with no trunk);
--  * a big land or cliff block is cut back at the face nearest the corridor, so the land stays
--    and only the part poking into the path goes (gone only if most of it is in the way);
--  * anything else in the way goes.
local function touches(part: BasePart, cf: CFrame, size: Vector3): boolean
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { part }
	return #workspace:GetPartBoundsInBox(cf, size, p) > 0
end

local function trim(part: BasePart, cf: CFrame, size: Vector3)
	local cf0, s0 = part.CFrame, part.Size
	local best: { cf: CFrame, size: Vector3, cut: number }? = nil
	for _, axis in { Vector3.xAxis, Vector3.zAxis } do
		local full = (s0 * axis).Magnitude
		for _, dir in { -1, 1 } do
			for step = 1, 8 do
				local cut = full * step * 0.1
				if best and cut >= best.cut then
					break
				end
				-- cut `cut` studs off the face on side `dir`: the centre moves the other way by half
				part.Size = s0 - axis * cut
				part.CFrame = cf0 * CFrame.new(-axis * dir * cut / 2)
				if not touches(part, cf, size) then
					best = { cf = part.CFrame, size = part.Size, cut = cut }
					break
				end
			end
		end
	end
	if best then
		part.Size = best.size
		part.CFrame = best.cf
	else
		part:Destroy()
	end
end

local function clearBox(cf: CFrame, size: Vector3, params: OverlapParams)
	for _, part in workspace:GetPartBoundsInBox(cf, size, params) do
		if not part.Parent then
			continue
		end
		local treeId = part:GetAttribute("Tree")
		if treeId then
			for _, other in (part.Parent :: Instance):GetChildren() do
				if other ~= part and other:GetAttribute("Tree") == treeId then
					other:Destroy()
				end
			end
			part:Destroy()
		elseif part:IsA("Part") and part.Shape == Enum.PartType.Block and math.max(part.Size.X, part.Size.Z) > 16 then
			trim(part, cf, size)
		else
			part:Destroy()
		end
	end
end

local function overlap(include: { Instance }): OverlapParams
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = include
	return p
end

-- every run opens with these three obstacles, in a random order (set in reset)
local OPENERS = { "tiger", "spikes", "wind" }
local openers: { string } = {}
-- juice comes 3-4 cans at a time for the first 5 minutes of a run
local RICH_JUICE_SECONDS = 300
local richUntil = 0
local corridors: { { cf: CFrame, size: Vector3 } } = {} -- the last few pieces' corridors

-- A crossroads block is about this long on the spine; one is never started if it could reach
-- the finish.
local BRANCH_SPAN = 480

local function pickKind(): string
	local n = spineCount
	if n < 3 then
		return "straight"
	end
	-- Studio test hook: workspace attribute DevEarlyCross puts a crossroads right after the start
	if n == 3 and workspace:GetAttribute("DevEarlyCross") and game:GetService("RunService"):IsStudio() then
		return "branch"
	end
	if openers[n - 2] then
		return openers[n - 2]
	end
	-- Crossroads: only while heading straight down the course (the side routes go out sideways
	-- and must never point back), two pieces after a turn, a few pieces after the last block.
	if
		quarter == 0
		and sinceTurn >= 2
		and n > 6
		and sinceBranch >= 4
		and builtDist + BRANCH_SPAN < branchLimit
		and not workspace:GetAttribute("EasyRun")
	then
		if sinceBranch >= 7 or rng:NextNumber() < 0.45 then
			return "branch"
		end
	end
	local d = math.clamp(builtDist / 4000, 0, 1)
	local weights: { [string]: number } = {
		straight = 3.5 - 2 * d,
		duck = 1.4 + 1.0 * d,
		gap = 0.9 + 1.3 * d,
		bridge = 0.7,
		halfWall = 1.1 + 0.8 * d,
		tar = 0, -- retired; something else replaces it later
		zipline = (elevation < 24 and n > 4) and 0.6 or 0,
		stairsUp = elevation < 24 and 0.7 or 0,
		stairsDown = elevation > -8 and 0.7 or 0,
		plank = n > 4 and 0.7 + 0.4 * d or 0,
		plankGap = n > 3 and 0.7 or 0,
		fork = n > 4 and 0.6 or 0,
		split = n > 3 and 0.6 or 0,
		slide = (elevation > -4 and n > 3) and 0.8 or 0,
		boulders = n > 4 and 0.6 + 0.5 * d or 0,
		vines = n > 4 and 0.6 or 0,
		tiger = n > 5 and 0.5 + 0.4 * d or 0,
		wind = n > 5 and 0.5 + 0.3 * d or 0,
		spikes = n > 3 and 0.9 + 0.6 * d or 0,
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
	local last = spineLast.kind
	if
		d < 0.4
		and (
			last == "gap"
			or last == "duck"
			or last == "halfWall"
			or last == "tar"
			or last == "zipline"
			or last == "plank"
			or last == "plankGap"
			or last == "fork"
			or last == "slide"
			or last == "boulders"
			or last == "vines"
			or last == "tiger"
			or last == "wind"
			or last == "spikes"
		)
	then
		weights.gap, weights.duck, weights.halfWall, weights.tar, weights.zipline, weights.plank = 0, 0, 0, 0, 0, 0
		weights.slide, weights.boulders, weights.vines, weights.tiger, weights.wind = 0, 0, 0, 0, 0
		weights.spikes, weights.plankGap, weights.fork = 0, 0, 0
	end
	-- a new player's first run: no ziplines or planks, hard obstacles half as common
	if workspace:GetAttribute("EasyRun") then
		weights.zipline, weights.plank, weights.tar = 0, 0, 0
		for _, k in { "gap", "duck", "halfWall", "slide", "boulders", "vines", "tiger", "wind", "spikes" } do
			weights[k] *= 0.5
		end
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

type Opts = { route: number?, len: number?, theme: string?, auto: boolean?, signs: { [number]: string }? }

local function build(kind: string, entry: CFrame, opts: Opts?): Segment
	local o: Opts = opts or {}
	local route = o.route or 0
	local model = Instance.new("Model")
	model.Name = string.format("%03d_%s%s", #segments + 1, kind, route == 0 and "" or (route < 0 and "_L" or "_R"))
	local solid = Instance.new("Folder")
	solid.Name = "Solid"
	solid.Parent = model
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = model

	-- Clear older decor out of this piece's corridor.
	-- Box is kept just inside the floor + walls (banks start at W/2 + 2) and short of the
	-- entry, so neighbouring banks that merely touch the corridor survive.
	local len, extra = Segments.footprint(kind, o.len)
	local corridorCF = entry * CFrame.new(0, 30, -len / 2 - 1)
	local corridorSize = Vector3.new(W + 2 + extra, 70, math.max(len - 4, 1))
	clearBox(corridorCF, corridorSize, overlap(decorFolders()))

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
		richJuice = os.clock() < richUntil,
		nextBottleId = function()
			bottleId += 1
			return bottleId
		end,
		isFree = function(cf: CFrame, size: Vector3): boolean
			return #workspace:GetPartBoundsInBox(cf, size, params) == 0
		end,
		len = o.len,
		theme = o.theme,
		auto = o.auto,
		signs = o.signs,
	}
	local builder = (Segments :: any)[kind]
	local res: Segments.Result = builder(ctx)
	model.Parent = root
	-- ...and this piece's own scenery out of the older pieces' corridors (after a turn the new
	-- piece's land can reach back across the path already built)
	local mine = overlap({ decor })
	for _, cor in corridors do
		clearBox(cor.cf, cor.size, mine)
	end
	table.insert(corridors, { cf = corridorCF, size = corridorSize })
	if #corridors > 30 then
		table.remove(corridors, 1)
	end

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
		route = route,
		rate = 1,
	}
	model:SetAttribute("Route", route)
	table.insert(segments, seg)
	if route ~= 0 then
		-- a side route piece: its race distance is set once the whole route is built (buildBranch)
		return seg
	end
	model:SetAttribute("StartDist", builtDist)
	spineLast = seg
	spineCount += 1
	sinceBranch += 1
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
	elseif kind == "slide" then
		elevation -= 20
	end
	return seg
end

-- What goes on each route of a block. Centre: the short way, hard obstacles. High: climbs onto a
-- ridge, a gem line, one medium obstacle. Low: drops into a gully, a juice line, one easy
-- obstacle. The side routes are longer to run, so the centre is the fast, risky way.
local CENTRE_HARD = { "spikes", "boulders", "gap", "halfWall", "duck", "wind" }
local HIGH_MID = { "plank", "plankGap", "bridge", "gap" }
local LOW_EASY = { "duck", "bridge", "boulders", "straight" }
-- studs of connector between a square and a side route's corner: the gap between the routes.
-- 12 read as one wide road from above; 20 leaves water and trees between them.
local SIDE_OUT = 20

local function pick(list: { string }, avoid: { [string]: boolean }?): string
	for _ = 1, 8 do
		local k = list[rng:NextInteger(1, #list)]
		if not (avoid and avoid[k]) then
			return k
		end
	end
	return list[1]
end

local function planLength(plan: { string }): number
	local n = 0
	for _, k in plan do
		n += (Segments.footprint(k))
	end
	return n
end

-- Build `plan` from `entry` on `route`, then filler so the whole run is exactly `len` long.
local function buildRun(
	plan: { string },
	entry: CFrame,
	len: number,
	route: number,
	theme: string?
): (CFrame, { Segment })
	local out = {}
	local e = entry
	local done = 0
	for _, k in plan do
		local seg = build(k, e, { route = route })
		table.insert(out, seg)
		e = seg.exit
		done += seg.length
	end
	-- the rest as filler pieces of at most 60 studs (the side routes carry their prize on them)
	local rest = len - done
	if rest < 1 then
		warn(string.format("[JJ.Path] route %d overran its stretch by %.1f studs", route, -rest))
		return e, out
	end
	local n = math.max(1, math.ceil(rest / 60))
	for _ = 1, n do
		local seg = build("filler", e, { route = route, len = rest / n, theme = theme })
		table.insert(out, seg)
		e = seg.exit
	end
	return e, out
end

-- A whole crossroads block: crossroads, three routes, merge (see the top of this file).
local function buildBranch()
	local highSide = rng:NextNumber() < 0.5 and -1 or 1
	local centre = { pick(CENTRE_HARD) }
	table.insert(centre, pick(CENTRE_HARD, { [centre[1]] = true }))
	if math.clamp(builtDist / 4000, 0, 1) > 0.5 then
		table.insert(centre, pick(CENTRE_HARD, { [centre[1]] = true, [centre[2]] = true }))
	end
	local high = { "stairsUp", "stairsUp", pick(HIGH_MID), "stairsDown", "stairsDown" }
	local low = { "stairsDown", pick(LOW_EASY), "stairsUp" }
	-- the forward stretch every route covers (filler pads each to exactly this)
	local stretch = math.max(planLength(centre), planLength(high), planLength(low)) + 24
	local signs = { [0] = "FAST", [highSide] = "GEMS", [-highSide] = "JUICE" }
	local cross = build("crossroads", spineLast.exit, { signs = signs })
	cross.model:SetAttribute("HighSide", highSide)
	-- the centre route is the spine
	local centreEnd = buildRun(centre, cross.exit, stretch, 0, nil)
	-- side routes: out through the square's side, a corner onto the forward stretch, a corner back
	-- in, and in through the merge square's side
	local half = W / 2
	local sideSegs: { [number]: { Segment } } = {}
	for _, s in { -1, 1 } do
		local segs: { Segment } = {}
		local e = cross.entry
			* CFrame.new(0, 0, -half)
			* CFrame.Angles(0, s == 1 and -math.pi / 2 or math.pi / 2, 0)
			* CFrame.new(0, 0, -half)
		local g = build("filler", e, { route = s, len = SIDE_OUT })
		table.insert(segs, g)
		-- heading out sideways, the turn back to the course direction is toward the centre
		local back = s == 1 and "turnLeft" or "turnRight"
		g = build(back, g.exit, { route = s, auto = true })
		table.insert(segs, g)
		local runEnd, run =
			buildRun(s == highSide and high or low, g.exit, stretch, s, s == highSide and "Gem" or "Juice")
		for _, r in run do
			table.insert(segs, r)
		end
		g = build(back, runEnd, { route = s, auto = true })
		table.insert(segs, g)
		g = build("filler", g.exit, { route = s, len = SIDE_OUT })
		table.insert(segs, g)
		sideSegs[s] = segs
	end
	local merge = build("merge", centreEnd)
	-- race distance on the side routes: they cover the same span as the centre (from the middle of
	-- the crossroads to the middle of the merge), spread over their own physical length
	local span = merge.startDist - cross.startDist
	for _, segs in sideSegs do
		local phys = 0
		for _, g in segs do
			phys += g.length
		end
		local rate = span / phys
		local at = cross.startDist + half
		for _, g in segs do
			g.rate = rate
			g.startDist = at
			g.length *= rate
			g.model:SetAttribute("StartDist", at)
			g.model:SetAttribute("Rate", rate)
			at += g.length
		end
	end
	sinceBranch = 0
	sinceTurn = 0
	print(
		string.format(
			"[JJ.Path] crossroads at %d m: centre %s | high (%s) %s | low %s",
			math.floor(cross.startDist / Config.StudsPerMetre),
			table.concat(centre, "+"),
			highSide < 0 and "left" or "right",
			high[3],
			low[2]
		)
	)
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
	corridors = {}
	openers = table.clone(OPENERS)
	for i = #openers, 2, -1 do
		local k = rng:NextInteger(1, i)
		openers[i], openers[k] = openers[k], openers[i]
	end
	richUntil = os.clock() + RICH_JUICE_SECONDS + 15 -- + lobby countdown
	quarter, sinceTurn, elevation, bottleId, builtDist = 0, 0, 0, 0, 0
	spineCount, sinceBranch, branchLimit = 0, 0, math.huge
	build("start", CFrame.new(0, 0, 0))
	-- The start piece's gate is at z = 50; distance 0 is at the gate.
	builtDist -= 50
	segments[1].startDist = -50
	segments[1].model:SetAttribute("StartDist", -50)
end

function PathService.all(): { Segment }
	return segments
end

-- No crossroads block may reach past this race distance (set once the run's goal is rolled).
function PathService.setBranchLimit(dist: number)
	branchLimit = dist
end

function PathService.ensureAhead(leaderDist: number)
	while builtDist < leaderDist + Config.GenerateAhead do
		local kind = pickKind()
		if kind == "branch" then
			buildBranch()
		else
			build(kind, spineLast.exit)
		end
	end
end

function PathService.trimBehind(dist: number)
	local i = 1
	while i <= #segments do
		local s = segments[i]
		if #segments > 2 and s ~= spineLast and s.startDist + s.length < dist - Config.DeleteBehind then
			table.remove(segments, i)
			s.model:Destroy()
		else
			i += 1
		end
	end
end

-- The piece at race distance `dist` on `route` (the spine where that route has no piece).
local function segmentAt(dist: number, route: number?): Segment
	local r = route or 0
	if r ~= 0 then
		for i = #segments, 1, -1 do
			local s = segments[i]
			if s.route == r and s.startDist <= dist and dist < s.startDist + s.length then
				return s
			end
		end
	end
	for i = #segments, 1, -1 do
		local s = segments[i]
		if s.route == 0 and s.startDist <= dist then
			return s
		end
	end
	return segments[1]
end

-- Run-speed multiplier on piece `s`. A side route is longer than the centre, so without help its
-- runners fall behind the Guardian's pace line (it paces on race distance). On a side route you
-- run faster, enough that the route costs SIDE_RACE_SPEED of the centre's race speed: the centre
-- stays the quickest way (about 5%), a side route never gets you caught just for taking it.
local SIDE_RACE_SPEED = 0.95
function PathService.speedMul(s: Segment?): number
	if not s or s.route == 0 then
		return 1
	end
	return math.clamp(SIDE_RACE_SPEED / s.rate, 1, 1.35)
end

-- Physical studs into piece `s` at race distance `dist`.
function PathService.along(s: Segment, dist: number): number
	return (dist - s.startDist) / s.rate
end

-- CFrame on the path centreline at a race distance (on `route`), facing the run heading there.
function PathService.pointAt(dist: number, route: number?): CFrame
	local s = segmentAt(dist, route)
	local phys = s.length / s.rate
	local t = math.clamp((dist - s.startDist) / s.rate, 0, phys)
	if s.turn == 0 then
		local a = t / phys
		local pos = s.entry.Position:Lerp(s.exit.Position, a)
		return CFrame.lookAt(pos, pos + s.entry.LookVector)
	end
	local half = phys / 2
	if t <= half then
		return s.entry * CFrame.new(0, 0, -t)
	end
	local centre = s.entry * CFrame.new(0, 0, -half)
	local exitRot = s.exit.Rotation
	return CFrame.new(centre.Position) * exitRot * CFrame.new(0, 0, -(t - half))
end

-- Race distance for a world position, and the piece it is on (its .route says which route).
-- hintDist = the last known distance. Pieces near it on every route are tried: one you are
-- squarely over beats a loose match, then the one whose distance is nearest the hint.
function PathService.progress(pos: Vector3, hintDist: number): (number, Segment?)
	local best: Segment? = nil
	local bestD, bestScore = hintDist, math.huge
	for _, s in segments do
		if s.startDist > hintDist + 300 or s.startDist + s.length < hintDist - 60 then
			continue
		end
		local lp = s.entry:PointToObjectSpace(pos)
		-- (below: deep enough that a runner falling off still has a piece for the Fell check)
		if lp.Y < -90 or lp.Y > 45 then
			continue
		end
		local phys = s.length / s.rate
		local f = -lp.Z
		local along: number? = nil
		local square = false
		if s.turn == 0 then
			if f >= -1 and f <= phys + 1 and math.abs(lp.X) < W / 2 + 10 then
				along = math.clamp(f, 0, phys)
				square = math.abs(lp.X) <= W / 2 + 1
			end
		elseif f >= -1 and f <= phys + 2 and math.abs(lp.X) < W / 2 + 10 then
			local half = phys / 2
			along = math.clamp(f, 0, half) + math.clamp(lp.X * s.turn, 0, half)
			square = math.abs(lp.X) <= W / 2 + 1 and f <= phys + 1
		end
		if along then
			local d = s.startDist + along * s.rate
			local score = (square and 0 or 1000) + math.abs(d - hintDist)
			if score < bestScore then
				best, bestD, bestScore = s, d, score
			end
		end
	end
	return bestD, best
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
