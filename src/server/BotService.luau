--!strict
-- Bot runners. They wear a copy of a real player's avatar and run the same path on the
-- server: an anchored root moved along the path centreline plus a lane offset, snapped to
-- the floor by raycast. Each obstacle is a skill roll: pass and they jump, slide, dodge or
-- hop cables like a player; fail and they stumble (or fall, on gaps and cut ziplines).
-- Every so often they grab a gadget and fire it: Sprint Leaf
-- or Grapple Vine. The Guardian catches them like anyone else.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Palette = require(Shared.Palette)
local PathService = require(script.Parent.PathService)

local BotService = {}

export type Hooks = {
	gone: (name: string, reason: string, metres: number, pos: Vector3) -> (),
}

type Bot = {
	name: string,
	model: Model,
	root: BasePart,
	track: AnimationTrack?,
	dist: number,
	lat: number,
	targetLat: number,
	home: number,
	speedMul: number,
	tigers: { [string]: number }?,
	forks: { [string]: number }?,
	route: number?, -- the route it is on in a crossroads block (PathService); nil/0 = main course
	xroutes: { [number]: number }?, -- crossroads piece index -> the route it picked there
	skill: number,
	stumbleUntil: number,
	speedUntil: number,
	nextGadget: number,
	leapUntil: number,
	y: number,
	alive: boolean,
	finished: boolean?, -- reached the goal
	heldUntil: number?, -- an ability holds it in place (spear, ice, bubble)
	hexUntil: number?, -- turned into a chicken/skeleton/frog: 10% slower
	rolled: { [string]: boolean }, -- obstacle key -> decided
	fails: { [string]: boolean }, -- obstacle key -> will fail
	zipLane: number?,
	idx: number,
	cf: CFrame,
	animSpeed: number,
	cheerTrack: AnimationTrack?,
}

-- Replication. The server no longer moves the bots' parts every frame: 11 bots x (a CFrame
-- property + two attributes) at 60 Hz flooded phone connections, so snapshots arrived late and
-- in bunches (bots froze, then jumped). Instead the server sends ONE small packet for all bots
-- SEND_HZ times a second on an UnreliableRemoteEvent (a lost packet is simply skipped; the next
-- one supersedes it), and every client draws the bots itself (client/BotSmooth).
local SEND_HZ = 20
local bots: { Bot } = {}
local snapRemote: UnreliableRemoteEvent? = nil -- made on first send (Remotes is set up later)
local lastSend = 0
-- packet: f64 server time, then per bot: u8 idx, f32 x, y, z, f32 yaw (17 bytes)
local function sendSnap(t: number)
	local alive = {}
	for _, b in bots do
		if b.alive then
			table.insert(alive, b)
		end
	end
	local buf = buffer.create(8 + 17 * #alive)
	buffer.writef64(buf, 0, t)
	for i, b in alive do
		local o = 8 + (i - 1) * 17
		local p = b.cf.Position
		local lv = b.cf.LookVector
		buffer.writeu8(buf, o, b.idx)
		buffer.writef32(buf, o + 1, p.X)
		buffer.writef32(buf, o + 5, p.Y)
		buffer.writef32(buf, o + 9, p.Z)
		buffer.writef32(buf, o + 13, math.atan2(-lv.X, -lv.Z))
	end
	if not snapRemote then
		local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		if not remotes then
			return
		end
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = "BotSnap"
		r.Parent = remotes
		snapRemote = r
	end
	(snapRemote :: UnreliableRemoteEvent):FireAllClients(buf)
end

local NAMES = { "Kiwi", "Mango", "Tiki", "Banjo", "Coco", "Zuzu", "Pip" }
local HIP = 3 -- root height above the floor
local LANE = Config.PathWidth / 3 -- lane spacing
local CHEER = "rbxassetid://507770677" -- Roblox's stock R15 cheer
local TIGER_START, TIGER_SPEED = 135, 72 -- must match client/Tiger
local HALF = Config.PathWidth / 2
local ZIP_LANES = { -12, -4, 4, 12 }

local folder: Folder? = nil
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Bots wear the game owner's avatar (so testers race "the dev"); the first runner's when the
-- owner's can't be loaded (unpublished place in Studio, group-owned game).
local ownerModel: Model? = nil
local ownerTried = false
local function ownerLook(): Model?
	if not ownerTried then
		ownerTried = true
		if game.CreatorType == Enum.CreatorType.User and game.CreatorId > 0 then
			local ok, m = pcall(function()
				return Players:CreateHumanoidModelFromUserId(game.CreatorId)
			end)
			if ok and m then
				ownerModel = m
			end
		end
	end
	return ownerModel
end

-- whose avatar the bots wear (for their portraits: that user's headshot)
function BotService.lookUserId(from: Player): number
	return if ownerLook() then game.CreatorId else from.UserId
end

local function makeModel(from: Player, name: string): (Model?, string?)
	local char = ownerLook() or from.Character
	if not char then
		return nil, nil
	end
	local was = char.Archivable
	char.Archivable = true
	local m = char:Clone()
	char.Archivable = was
	if not m then
		return nil, nil
	end
	local runId: string? = nil
	local jumpId: string? = nil
	local animate = m:FindFirstChild("Animate")
	if animate then
		local run = animate:FindFirstChild("run")
		local anim = run and run:FindFirstChildOfClass("Animation")
		runId = anim and anim.AnimationId
		local jump = animate:FindFirstChild("jump")
		local ja = jump and jump:FindFirstChildOfClass("Animation")
		jumpId = ja and ja.AnimationId
	end
	for _, d in m:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = false
			d.Massless = true
		end
	end
	m.Name = name
	return m, runId, jumpId
end

local function popIcon(b: Bot, icon: string, g: any?)
	local head = b.model:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(60, 60)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = icon
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Palette.UiText
	t.Parent = bb
	if g and Items.iconInto(bb, g.id, 1) then
		t:Destroy() -- the ability's art instead of its emoji
	end
	bb.Parent = head
	task.delay(1.6, function()
		bb:Destroy()
	end)
end

function BotService.clear()
	for _, b in bots do
		b.model:Destroy()
	end
	bots = {}
	if folder then
		folder:Destroy()
		folder = nil
	end
end

-- Spawn `n` bots that look like `from`, standing at `cfs` (one start CFrame each).
function BotService.spawn(from: Player, cfs: { CFrame })
	BotService.clear()
	local f = Instance.new("Folder")
	f.Name = "Bots"
	f.Parent = workspace
	folder = f
	for i, cf in cfs do
		local name = NAMES[(i - 1) % #NAMES + 1]
		local m, runId, jumpId = makeModel(from, name)
		if not m then
			continue
		end
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = m:FindFirstChildOfClass("Humanoid")
		if not root or not hum then
			m:Destroy()
			continue
		end
		root.Anchored = true
		hum.DisplayName = name
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance = 80
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.EvaluateStateMachine = false
		m:PivotTo(cf)
		m:SetAttribute("Idx", i)
		m.Parent = f
		local track: AnimationTrack? = nil
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local a = Instance.new("Animation")
		a.AnimationId = (runId and runId ~= "") and runId or "rbxassetid://913376220"
		local ok, tr = pcall(function()
			return (animator :: Animator):LoadAnimation(a)
		end)
		if ok and tr then
			track = tr
			tr.Looped = true
			tr:Play(0.1)
		end
		-- in the air the legs hold the jump pose (the run cycle kept "walking" on nothing)
		local jumpTrack: AnimationTrack? = nil
		local ja = Instance.new("Animation")
		ja.AnimationId = (jumpId and jumpId ~= "") and jumpId or "rbxassetid://507765000"
		local okJ, jt = pcall(function()
			return (animator :: Animator):LoadAnimation(ja)
		end)
		if okJ and jt then
			jumpTrack = jt
			jt.Looped = true
			jt.Priority = Enum.AnimationPriority.Action
		end
		-- the finish-line cheer, loaded up front so it is ready the moment they cross
		local cheerTrack: AnimationTrack? = nil
		local ca = Instance.new("Animation")
		ca.AnimationId = CHEER
		local okC, ct = pcall(function()
			return (animator :: Animator):LoadAnimation(ca)
		end)
		if okC and ct then
			cheerTrack = ct
			ct.Looped = true
			ct.Priority = Enum.AnimationPriority.Action4
		end
		local lat = PathService.segmentAt(-10).entry:PointToObjectSpace(cf.Position).X
		table.insert(bots, {
			name = name,
			model = m,
			root = root,
			track = track,
			jumpTrack = jumpTrack,
			cheerTrack = cheerTrack,
			dist = -10,
			lat = lat,
			targetLat = math.clamp(lat, -(HALF - 3), HALF - 3),
			home = math.clamp(lat, -(HALF - 3), HALF - 3),
			speedMul = rng:NextNumber(0.96, 1.05),
			skill = rng:NextNumber(0.8, 0.96),
			stumbleUntil = 0,
			speedUntil = 0,
			nextGadget = 0,
			leapUntil = 0,
			y = cf.Y,
			alive = true,
			rolled = {},
			fails = {},
			zipLane = nil,
			idx = i,
			cf = cf,
			animSpeed = 1,
		})
	end
end

-- Decide once per obstacle whether this bot clears it.
local function fails(b: Bot, key: string, extra: number?): boolean
	if not b.rolled[key] then
		b.rolled[key] = true
		b.fails[key] = rng:NextNumber() > b.skill * (extra or 1)
	end
	return b.fails[key]
end

local function stumble(b: Bot)
	if now() > b.stumbleUntil then
		b.stumbleUntil = now() + Config.StumbleSeconds
	end
end

local function eliminate(b: Bot, reason: string, hooks: Hooks)
	if not b.alive then
		return
	end
	b.alive = false
	print(
		string.format(
			"[JJ.Bot] %s out (%s) at %d m%s",
			b.name,
			reason,
			math.floor(b.dist / Config.StudsPerMetre),
			(b.route or 0) == 0 and "" or (b.route == -1 and " on the left route" or " on the right route")
		)
	)
	if b.track then
		b.track:Stop()
	end
	hooks.gone(b.name, reason, math.max(0, math.floor(b.dist / Config.StudsPerMetre)), b.cf.Position)
	local m = b.model
	m:SetAttribute("Out", true) -- clients stop drawing it and let it drop
	m:PivotTo(b.cf)
	if reason == "Fell" then
		m:PivotTo(m:GetPivot() * CFrame.new(0, -6, 0))
	end
	task.delay(reason == "Fell" and 0.6 or 0.1, function()
		m:Destroy()
	end)
end

local function useGadget(b: Bot, hooks: Hooks)
	local pick = ({ "SprintLeaf", "SprintLeaf", "GrappleVine" })[rng:NextInteger(1, 3)]
	local g = Items.get(pick)
	popIcon(b, g and g.icon or "?", g)
	local t = now()
	if pick == "SprintLeaf" then
		b.speedUntil = t + 4
	elseif pick == "GrappleVine" then
		b.leapUntil = t + 1.2
	end
end

-- Goal race: a bot reaching `dist` stops on the finish and `onFinish(name, idx)` is called once.
-- It then counts as neither alive nor out.
local goalDist: number? = nil
local onFinish: ((string, number) -> ())? = nil
-- Runners an ability can target: every bot still running (not out, not over the line).
function BotService.targets(): { { idx: number, name: string, dist: number, root: BasePart, model: Model } }
	local out = {}
	for _, b in bots do
		if b.alive and not b.finished then
			table.insert(out, { idx = b.idx, name = b.name, dist = b.dist, root = b.root, model = b.model })
		end
	end
	return out
end

-- An ability lands on bot idx: kind "held" (with look spear | ice | bubble) or "hex" (look
-- chicken | skeleton | frog). The look goes on the model as attributes; clients draw it.
function BotService.hit(idx: number, kind: string, look: string, secs: number)
	for _, b in bots do
		if b.idx == idx and b.alive then
			local untilT = now() + secs
			if kind == "held" then
				b.heldUntil = untilT
				b.model:SetAttribute("HeldUntil", untilT)
				b.model:SetAttribute("HeldKind", look)
			else
				b.hexUntil = untilT
				b.model:SetAttribute("HexUntil", untilT)
				b.model:SetAttribute("HexKind", look)
			end
		end
	end
end

function BotService.setGoal(dist: number?, cb: ((string, number) -> ())?)
	goalDist, onFinish = dist, cb
end

function BotService.maxDist(): number
	local m = -math.huge
	for _, b in bots do
		if b.alive and not b.finished then
			m = math.max(m, b.dist)
		end
	end
	return m
end

function BotService.aliveDists(): { number }
	local t = {}
	for _, b in bots do
		if b.alive and not b.finished then
			table.insert(t, b.dist)
		end
	end
	return t
end

function BotService.aliveCount(): number
	local n = 0
	for _, b in bots do
		if b.alive and not b.finished then
			n += 1
		end
	end
	return n
end

function BotService.results(): { { name: string, idx: number, dist: number, alive: boolean } }
	local t = {}
	for _, b in bots do
		table.insert(t, { name = b.name, idx = b.idx, dist = b.dist, alive = b.alive })
	end
	return t
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- One server frame while the run is on.
function BotService.step(
	dt: number,
	runSpeed: number,
	paceDist: number,
	hooks: Hooks,
	humanFront: number?,
	humanBack: number?
)
	rayParams.FilterDescendantsInstances = PathService.solids()
	local t = now()
	for _, b in bots do
		if not b.alive or b.finished then
			continue
		end
		if goalDist and b.dist >= goalDist then
			b.finished = true
			-- celebrate: stop running (and any jump pose), play the cheer on top of everything
			if b.track then
				b.track:AdjustSpeed(1)
				b.track:Stop(0.2)
			end
			if b.jumpTrack then
				b.jumpTrack:Stop(0.1)
			end
			if b.cheerTrack then
				b.cheerTrack:Play(0.2)
			end
			if onFinish then
				onFinish(b.name, b.idx)
			end
			continue
		end
		if b.dist < paceDist then
			eliminate(b, "Caught by the Guardian", hooks)
			continue
		end
		-- Speed
		local speed = runSpeed * b.speedMul
		-- rubber band: a bot well ahead of the furthest human eases off, one far behind the last
		-- human pushes a little, so the field stays together around the players
		if humanFront then
			local ahead = b.dist - humanFront
			if ahead > 25 then
				speed *= math.clamp(1 - (ahead - 25) / 150, 0.82, 1)
			elseif humanBack and b.dist < humanBack - 60 then
				speed *= 1.06
			end
		end
		if t < b.stumbleUntil then
			speed *= Config.StumbleSpeedMul
		end
		if t < b.speedUntil then
			speed *= 1.35
		end
		if t < (b.hexUntil or 0) then
			speed *= 0.9
		end
		if t < (b.heldUntil or 0) then
			speed = 0
		end
		local leaping = t < b.leapUntil
		if leaping then
			speed *= 2.2
		end
		-- Obstacles on the current piece
		local seg = PathService.segmentAt(b.dist, b.route)
		local lt = PathService.along(seg, b.dist)
		-- Crossroads: pick a route on the way in, drift to that side, and take it at the middle
		-- of the square. When the side route ends it is back on the main course, coming in
		-- through the side of the merge square.
		local route = b.route or 0
		if route ~= 0 and seg.route == 0 then
			b.route = nil
			b.lat = route * (HALF - 4)
			route = 0
		end
		if seg.kind == "crossroads" and route == 0 then
			local picks = b.xroutes or {}
			b.xroutes = picks
			local pickR = picks[seg.index]
			if pickR == nil then
				-- a skilled bot takes the fast centre more often; the rest split between the sides
				local pc = 0.3 + 0.3 * b.skill
				local r = rng:NextNumber()
				pickR = r < pc and 0 or (r < pc + (1 - pc) / 2 and -1 or 1)
				picks[seg.index] = pickR
			end
			if pickR ~= 0 then
				b.targetLat = pickR * (HALF - 4)
				local side = lt >= HALF and PathService.segmentAt(b.dist, pickR)
				if side and side.route == pickR then
					b.route = pickR
					b.lat = 0
					seg = side
					lt = PathService.along(seg, b.dist)
				end
			end
		end
		local key = tostring(seg.index)
		local lift = 0
		local airborne = leaping
		local zipping = false
		b.targetLat = b.home -- obstacles below steer away from it
		if seg.kind == "duck" and lt > 25 and lt < 34 then
			if fails(b, key) then
				if lt > 29 then
					stumble(b)
				end
			else
				lift = -1.6
			end
		elseif seg.kind == "fork" then
			-- pick a route by where you are (or at random from the middle) and run it
			local z0, z1 = seg.model:GetAttribute("ForkZ0") or 22, seg.model:GetAttribute("ForkZ1") or 168
			b.forks = b.forks or {}
			if not b.forks[key] then
				b.forks[key] = math.abs(b.lat) > 2 and math.sign(b.lat) or (rng:NextNumber() < 0.5 and -1 or 1)
			end
			local side = b.forks[key]
			if lt > z0 - 14 and lt < z1 + 2 then
				b.targetLat = side * (2 + (HALF - 2.5) / 2)
				if lt > z0 - 2 then
					b.lat = side * math.max(side * b.lat, 3.5) -- never through the ridge
				end
			end
			local slideSide = seg.model:GetAttribute("SlideSide") or 1
			for i = 1, 2 do
				local z = seg.model:GetAttribute("ObsZ" .. i) or 0
				if side == slideSide and lt > z - 5 and lt < z + 4 then
					if fails(b, key .. "o" .. i) then
						if math.abs(lt - z) < 1 then
							stumble(b)
						end
					else
						lift = -1.6
					end
				elseif side ~= slideSide and lt > z - 6 and lt < z + 6 then
					if fails(b, key .. "o" .. i) then
						if math.abs(lt - z) < 1 then
							stumble(b)
						end
					else
						lift = 5 * math.sin(math.pi * (lt - (z - 6)) / 12)
						airborne = true
					end
				end
			end
		elseif seg.kind == "gap" or seg.kind == "plankGap" then
			local ga, gb = seg.model:GetAttribute("GapA") or 26, seg.model:GetAttribute("GapB") or 36
			if lt > ga - 4 and lt < gb + 4 and not leaping then
				if fails(b, key, 1.06) and lt > ga + 1 then
					eliminate(b, "Fell", hooks)
					continue
				end
				lift = 6 * math.sin(math.pi * (lt - (ga - 4)) / (gb - ga + 8))
				airborne = true
			end
		elseif seg.kind == "halfWall" then
			for i = 1, 2 do
				local z = seg.model:GetAttribute("Wall" .. i .. "Z")
				local side = seg.model:GetAttribute("Wall" .. i .. "Side")
				if z and lt > z - 16 and lt < z + 2 then
					if fails(b, key .. "w" .. i) then
						if math.abs(lt - z) < 1.5 then
							stumble(b)
						end
					else
						b.targetLat = -side * 6
					end
				end
			end
		elseif seg.kind == "tar" then
			local side = seg.model:GetAttribute("TarSide") or 1
			if lt > 6 and lt < 40 and not fails(b, key) then
				b.targetLat = -side * 9
			end
			local inPit = lt > 18 and lt < 40 and (b.lat * side) > -(Config.PathWidth / 2 - 7) + 0.5
			if inPit and not airborne then
				speed *= 0.45
			end
		elseif seg.kind == "plank" then
			-- single file along the zigzag planks; a miss on the narrow part is a fall
			local side = seg.model:GetAttribute("PlankSide") or 1
			b.targetLat = (lt > 38 and lt < 76) and 9 * side or 0
			if lt > 18 and lt < 28 and fails(b, key, 1.04) then
				eliminate(b, "Fell", hooks)
				continue
			end
		elseif seg.kind == "slide" then
			-- the mud is fast; steer to a lane with no hole in the rows just ahead
			speed *= 1.25
			local ahead: { [number]: boolean } = {}
			local inHole = false
			for z0s, lanes in string.gmatch(seg.model:GetAttribute("Holes") or "", "(%d+):(%d)") do
				local z0, lane = tonumber(z0s) :: number, tonumber(lanes) :: number
				if lt > z0 - 14 and lt < z0 + 16 then
					ahead[lane] = true
				end
				if lt > z0 + 2 and lt < z0 + 14 and math.abs(b.lat - (lane - 2) * LANE) < 3 then
					inHole = true
				end
			end
			local cur = math.clamp(math.floor((b.lat + 12) / 8) + 1, 1, 3)
			if ahead[cur] and not fails(b, key .. "s" .. math.floor(lt / 16), 1.03) then
				local best, bd = cur, math.huge
				for lane = 1, 3 do
					if not ahead[lane] and math.abs(lane - cur) < bd then
						best, bd = lane, math.abs(lane - cur)
					end
				end
				b.targetLat = (best - 2) * LANE
			else
				b.targetLat = (cur - 2) * LANE
			end
			if inHole and not airborne then
				eliminate(b, "Fell", hooks)
				continue
			end
		elseif seg.kind == "boulders" then
			-- hop boulder to boulder: arcs over the water gaps, a miss is a fall
			local zs, xs = {}, {}
			for v in string.gmatch(seg.model:GetAttribute("BZ") or "", "[^,]+") do
				table.insert(zs, tonumber(v))
			end
			for v in string.gmatch(seg.model:GetAttribute("BX") or "", "[^,]+") do
				table.insert(xs, tonumber(v))
			end
			local R = 7
			local stops = { { z = (seg.model:GetAttribute("BBank") or 14) - 2, x = 0 } }
			for i, z in zs do
				table.insert(stops, { z = z, x = xs[i] })
			end
			table.insert(stops, { z = (seg.model:GetAttribute("BLand") or 80) + 2, x = 0 })
			for i = 1, #stops - 1 do
				local a, c = stops[i], stops[i + 1]
				local za, zc = a.z + (i == 1 and 0 or R - 2), c.z - (i == #stops - 1 and 0 or R - 2)
				if lt > a.z and lt < c.z + 1 then
					b.targetLat = c.x
				end
				if lt > za and lt < zc and not leaping then
					if fails(b, key .. "b" .. i, 1.05) and lt > (za + zc) / 2 then
						eliminate(b, "Fell", hooks)
						break
					end
					lift = 5 * math.sin(math.pi * (lt - za) / (zc - za))
					airborne = true
				end
			end
			if not b.alive then
				continue
			end
		elseif seg.kind == "vines" then
			-- ride the vines like a player: the same swing curve (Segments.vines / client Runner)
			local z0 = seg.model:GetAttribute("VineZ0") or 22
			local gap, len, n, py = 20, 20, 4, 25
			local sv = lt - z0
			if sv > -gap / 2 and sv < (n - 1) * gap + gap / 2 then
				local k = math.clamp(math.floor((sv + gap / 2) / gap) + 1, 1, n)
				local dz = sv - (k - 1) * gap
				zipping = true
				b.targetLat = 0
				local swingY = seg.entry.Y + py - math.sqrt(math.max(len * len - dz * dz, 0)) - 4.6
				b.y += math.clamp(swingY - b.y, -40 * dt, 40 * dt) -- reach for the vine, no jump cut
			elseif sv > -gap / 2 - 30 and sv <= -gap / 2 then
				b.targetLat = 0 -- line up with the vines on the way in
			end
		elseif seg.kind == "tiger" then
			-- step out of the tiger's lane once it is charging, or be taken out
			local lane = (seg.model:GetAttribute("TigerLane") or 0) * LANE
			-- each bot's own charge, from when it reached the piece (as for players)
			b.tigers = b.tigers or {}
			if lt >= 4 and not b.tigers[key] then
				b.tigers[key] = t
			end
			local t0 = b.tigers[key] :: number?
			if t0 and math.abs(b.lat - lane) < 5 + LANE / 2 then
				if not fails(b, key, 0.97) then
					b.targetLat = -math.sign(lane) * LANE * 0.5
				end
				local along = TIGER_START - TIGER_SPEED * (t - t0)
				if math.abs(lt - along) < 3 and math.abs(b.lat - lane) < 2.2 and not airborne then
					eliminate(b, "Taken out by the tiger", hooks)
					continue
				end
			end
		elseif seg.kind == "spikes" then
			-- spike beds fill all lanes but one; steer to the open lane, or run into them
			for i = 1, 2 do
				local z = seg.model:GetAttribute("Row" .. i .. "Z") :: number?
				local open = seg.model:GetAttribute("Row" .. i .. "Open") :: number?
				if z and open and lt > z - 34 and lt < z + 3 then
					if not fails(b, key .. "k" .. i) then
						b.targetLat = (open - 2) * LANE
					elseif math.abs(lt - z) < 2 and math.abs(b.lat - (open - 2) * LANE) > LANE / 2 then
						stumble(b)
					end
				end
			end
		elseif seg.kind == "wind" then
			-- gusts push toward the open edge; a weak bot gets blown off
			local side = seg.model:GetAttribute("WindSide") or 1
			local z0, z1 = seg.model:GetAttribute("WindZ0") or 30, seg.model:GetAttribute("WindZ1") or 86
			if lt > z0 and lt < z1 then
				if fails(b, key, 1.05) then
					b.targetLat = side * 14
					if lt > (z0 + z1) / 2 then
						eliminate(b, "Fell", hooks)
						continue
					end
				else
					b.targetLat = -side * 4
				end
			end
		elseif seg.kind == "split" then
			-- about half take the upper deck (gems), the rest stay low (juice)
			local side = seg.model:GetAttribute("SplitSide") or 1
			if lt > 2 and lt < 124 then
				b.targetLat = fails(b, key .. "up", 0.55) and 6.5 * side or -5 * side
			end
		elseif seg.kind == "zipline" and lt > 12 and lt < 96 then
			local zips = seg.model:FindFirstChild("Zips")
			if zips then
				zipping = true
				if not b.zipLane then
					local best, bd = 1, math.huge
					for lane, x in ZIP_LANES do
						if math.abs(x - b.lat) < bd then
							best, bd = lane, math.abs(x - b.lat)
						end
					end
					b.zipLane = best
				end
				local cable = zips:FindFirstChild("Zip" .. b.zipLane) :: BasePart?
				if cable then
					local a, bb = cable:GetAttribute("A") :: Vector3, cable:GetAttribute("B") :: Vector3
					local u = (lt - 12) / 84
					local cut = cable:GetAttribute("Cut") :: number
					if cut < 1 and u > cut - 0.15 then
						-- Hop to the nearest whole cable (or miss the hop and ride into the cut).
						if not fails(b, key .. "z" .. b.zipLane, 1.05) then
							local best, bd = nil, math.huge
							for lane = 1, 4 do
								local c = zips:FindFirstChild("Zip" .. lane) :: BasePart?
								if c and (c:GetAttribute("Cut") :: number) >= 1 and math.abs(lane - b.zipLane) < bd then
									best, bd = lane, math.abs(lane - b.zipLane)
								end
							end
							b.zipLane = best or b.zipLane
						elseif u >= cut then
							eliminate(b, "Fell", hooks)
							continue
						end
					end
					b.targetLat = ZIP_LANES[b.zipLane :: number]
					local p = a:Lerp(bb, math.clamp(u, 0, 1))
					b.y = p.Y - 4.6
				end
			end
		end
		if not zipping then
			b.zipLane = nil
		end
		-- Gadgets
		if b.nextGadget == 0 then
			b.nextGadget = t + rng:NextNumber(6, 14)
		elseif t >= b.nextGadget then
			b.nextGadget = t + rng:NextNumber(10, 20)
			useGadget(b, hooks)
		end
		-- Move
		-- a side route's studs count for less race distance, and it runs faster there to make up
		-- for most of it (PathService.speedMul)
		b.dist += speed * PathService.speedMul(seg) * dt * seg.rate
		if seg.kind == "plankGap" and lt > -20 and lt < 64 then
			-- the bridge is 12 wide: line up with it on the way in (steered, not snapped)
			b.targetLat = math.clamp(b.targetLat, -3.5, 3.5)
		end
		local latStep = 22 * dt
		b.lat += math.clamp(b.targetLat - b.lat, -latStep, latStep)
		b.lat = math.clamp(b.lat, -(HALF - 3), HALF - 3)
		local centre = PathService.pointAt(b.dist, b.route)
		local pos = (centre * CFrame.new(b.lat, 0, 0)).Position
		if not zipping then
			local hit = workspace:Raycast(Vector3.new(pos.X, b.y + 14, pos.Z), Vector3.new(0, -24, 0), rayParams)
			-- floor only, never the top of a side wall or half wall; a raised platform is climbed
			-- with a quick hop up rather than a snap
			local floorHit = hit
				and hit.Instance.Name ~= "HalfWall"
				and not CollectionService:HasTag(hit.Instance, "Wall")
			if floorHit and hit and hit.Position.Y + HIP > b.y + 2.5 then
				b.y = math.min(hit.Position.Y + HIP, b.y + 45 * dt)
			elseif floorHit and hit then
				b.y = hit.Position.Y + HIP
			end
		end
		local y = b.y + lift + (leaping and 5 or 0)
		local cf = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(pos.X, y, pos.Z) + centre.LookVector)
		b.cf = cf
		local inAir = airborne or zipping or lift > 0.5
		-- the run cycle's speed only changes on a real change (every AdjustSpeed replicates)
		local want = inAir and 0 or math.floor(speed / 24 * 10 + 0.5) / 10
		if b.track and want ~= b.animSpeed then
			b.animSpeed = want
			b.track:AdjustSpeed(want)
		end
		local jt = b.jumpTrack
		if jt then
			if inAir and not jt.IsPlaying then
				jt:Play(0.08)
			elseif not inAir and jt.IsPlaying then
				jt:Stop(0.12)
			end
		end
		if b.y < -40 then
			eliminate(b, "Fell", hooks)
		end
	end
	if t - lastSend >= 1 / SEND_HZ then
		lastSend = t
		sendSnap(t)
	end
end

return BotService
