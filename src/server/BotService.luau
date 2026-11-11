--!strict
-- Bot runners. They wear a copy of a real player's avatar and run the same path on the
-- server: an anchored root moved along the path centreline plus a lane offset, snapped to
-- the floor by raycast. Each obstacle is a skill roll: pass and they jump, slide, dodge or
-- hop cables like a player; fail and they stumble (or fall, on gaps and cut ziplines).
-- Every so often they grab a gadget and fire it: Sprint Leaf, War Drum, Banana Peel,
-- Thorn Trap or Grapple Vine. The Guardian catches them like anyone else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Palette = require(Shared.Palette)
local PathService = require(script.Parent.PathService)

local BotService = {}

export type Hooks = {
	warDrum: (name: string) -> (), -- slow every real runner
	trap: (at: CFrame, width: number, height: number, color: Color3) -> (),
	gone: (name: string, reason: string, metres: number) -> (),
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
	skill: number,
	stumbleUntil: number,
	slowUntil: number,
	speedUntil: number,
	nextGadget: number,
	leapUntil: number,
	y: number,
	alive: boolean,
	rolled: { [string]: boolean }, -- obstacle key -> decided
	fails: { [string]: boolean }, -- obstacle key -> will fail
	zipLane: number?,
}

local NAMES = { "Kiwi", "Mango", "Tiki", "Banjo", "Coco", "Zuzu", "Pip" }
local HIP = 3 -- root height above the floor
local ZIP_LANES = { -9, -3, 3, 9 }

local bots: { Bot } = {}
local folder: Folder? = nil
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function makeModel(from: Player, name: string): (Model?, string?)
	local char = from.Character
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
	local animate = m:FindFirstChild("Animate")
	if animate then
		local run = animate:FindFirstChild("run")
		local anim = run and run:FindFirstChildOfClass("Animation")
		runId = anim and anim.AnimationId
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
	return m, runId
end

local function popIcon(b: Bot, icon: string)
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
		local m, runId = makeModel(from, name)
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
		local lat = PathService.segmentAt(-10).entry:PointToObjectSpace(cf.Position).X
		table.insert(bots, {
			name = name,
			model = m,
			root = root,
			track = track,
			dist = -10,
			lat = lat,
			targetLat = math.clamp(lat, -9, 9),
			home = math.clamp(lat, -9, 9),
			speedMul = rng:NextNumber(0.96, 1.05),
			skill = rng:NextNumber(0.8, 0.96),
			stumbleUntil = 0,
			slowUntil = 0,
			speedUntil = 0,
			nextGadget = 0,
			leapUntil = 0,
			y = cf.Y,
			alive = true,
			rolled = {},
			fails = {},
			zipLane = nil,
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
	if b.track then
		b.track:Stop()
	end
	hooks.gone(b.name, reason, math.max(0, math.floor(b.dist / Config.StudsPerMetre)))
	local m = b.model
	if reason == "Fell" then
		m:PivotTo(m:GetPivot() * CFrame.new(0, -6, 0))
	end
	task.delay(reason == "Fell" and 0.6 or 0.1, function()
		m:Destroy()
	end)
end

local function useGadget(b: Bot, hooks: Hooks)
	local pick = ({ "SprintLeaf", "SprintLeaf", "WarDrum", "BananaPeel", "ThornTrap", "GrappleVine" })[rng:NextInteger(1, 6)]
	local g = Items.get(pick)
	popIcon(b, g and g.icon or "?")
	local t = now()
	if pick == "SprintLeaf" then
		b.speedUntil = t + 4
	elseif pick == "WarDrum" then
		hooks.warDrum(b.name)
		for _, o in bots do
			if o ~= b and o.alive then
				o.slowUntil = t + 2
			end
		end
	elseif pick == "BananaPeel" then
		hooks.trap(b.root.CFrame, 3, 0.6, Palette.JuiceGlow)
	elseif pick == "ThornTrap" then
		hooks.trap(b.root.CFrame, Config.PathWidth - 2, 1.4, Palette.CanopyDeep)
	elseif pick == "GrappleVine" then
		b.leapUntil = t + 1.2
	end
end

function BotService.maxDist(): number
	local m = -math.huge
	for _, b in bots do
		if b.alive then
			m = math.max(m, b.dist)
		end
	end
	return m
end

function BotService.aliveCount(): number
	local n = 0
	for _, b in bots do
		if b.alive then
			n += 1
		end
	end
	return n
end

function BotService.results(): { { name: string, dist: number } }
	local t = {}
	for _, b in bots do
		table.insert(t, { name = b.name, dist = b.dist })
	end
	return t
end

function BotService.slowAll(untilT: number)
	for _, b in bots do
		b.slowUntil = untilT
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- One server frame while the run is on.
function BotService.step(dt: number, runSpeed: number, paceDist: number, hooks: Hooks)
	rayParams.FilterDescendantsInstances = PathService.solids()
	local t = now()
	for _, b in bots do
		if not b.alive then
			continue
		end
		if b.dist < paceDist then
			eliminate(b, "Caught by the Guardian", hooks)
			continue
		end
		-- Speed
		local speed = runSpeed * b.speedMul
		if t < b.stumbleUntil then
			speed *= Config.StumbleSpeedMul
		end
		if t < b.slowUntil then
			speed *= Config.DartSlowMul
		end
		if t < b.speedUntil then
			speed *= 1.35
		end
		local leaping = t < b.leapUntil
		if leaping then
			speed *= 2.2
		end
		-- Obstacles on the current piece
		local seg = PathService.segmentAt(b.dist)
		local lt = b.dist - seg.startDist
		local key = tostring(seg.index)
		local lift = 0
		local airborne = leaping
		local zipping = false
		b.targetLat = b.home -- obstacles below steer away from it
		if seg.kind == "hurdle" and lt > 23 and lt < 35 and not leaping then
			if fails(b, key) then
				if lt > 29 then
					stumble(b)
				end
			else
				lift = 4.5 * math.sin(math.pi * (lt - 23) / 12)
				airborne = true
			end
		elseif seg.kind == "duck" and lt > 25 and lt < 34 then
			if fails(b, key) then
				if lt > 29 then
					stumble(b)
				end
			else
				lift = -1.6
			end
		elseif seg.kind == "gap" then
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
		b.dist += speed * dt
		local latStep = 22 * dt
		b.lat += math.clamp(b.targetLat - b.lat, -latStep, latStep)
		local centre = PathService.pointAt(b.dist)
		local pos = (centre * CFrame.new(b.lat, 0, 0)).Position
		if not zipping then
			local hit = workspace:Raycast(Vector3.new(pos.X, b.y + 6, pos.Z), Vector3.new(0, -16, 0), rayParams)
			if hit and hit.Instance.Name ~= "HalfWall" then
				b.y = hit.Position.Y + HIP
			end
		end
		local y = b.y + lift + (leaping and 5 or 0)
		b.root.CFrame = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(pos.X, y, pos.Z) + centre.LookVector)
		if b.track then
			b.track:AdjustSpeed((airborne or zipping) and 0.2 or speed / 24)
		end
		if b.y < -40 then
			eliminate(b, "Fell", hooks)
		end
	end
end

return BotService
