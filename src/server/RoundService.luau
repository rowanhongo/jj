--!strict
-- Stampede round: lobby -> countdown -> run -> results.
-- The server owns juice, the pace line, who is caught, darts and rewards.
-- The client owns its own movement (steering, jumping, sliding, turning, stumbling).
--
-- Player attributes (replicated):
--   State      "Lobby" | "Countdown" | "Running" | "Caught"
--   Juice      0..JuiceMax
--   RunSpeed   current base run speed (studs/s)
--   SlowUntil  server time (workspace:GetServerTimeNow()) until a dart slow ends
--   Distance   metres this run
--   DartReadyAt server time the next dart is allowed
-- Workspace attributes: Status (text), PaceDist (studs), Alive (count), RunStart (server time)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local PathService = require(script.Parent.PathService)
local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)
local Guard = require(script.Parent.Guard)
local FriendBoost = require(script.Parent.FriendBoost)
local Badges = require(script.Parent.Badges)
local BotService = require(script.Parent.BotService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local Items = require(Shared.Items)
local Funnel = require(script.Parent.Funnel)
local F = Funnel.Steps
local runsThisSession: { [Player]: number } = {}

local RoundService = {}

local LOBBY_CF = CFrame.new(0, 0, 220)

local remotes: Folder
local useGadgetEffect: (Player, any, string) -> ()
local notifyRemote: RemoteEvent
local dartFx: RemoteEvent
local abilityFx: RemoteEvent -- (kind, from root, to root or part): clients draw throws
local diedRemote: RemoteEvent
local sfxRemote: RemoteEvent -- (kind, position): a sound every client plays
local tigerRemote: RemoteEvent -- (warn zone, start time): a tiger charge every client draws
local resetPlayer: (Player) -> ()

type Run = {
	dist: number, -- studs (race distance: progress toward the finish, see PathService)
	route: number?, -- the route you are on in a crossroads block (0 / nil = the main course)
	routeMul: number?, -- run-speed multiplier of that route (PathService.speedMul)
	juice: number,
	emptySince: number,
	collected: { [number]: boolean },
	camps: number,
	caughtAt: number?,
	slots: { string? },
	honeyUntil: number,
	bonus: number?, -- position-bonus metres earned so far
	lastDist: number?,
	pickGems: number?, -- gems from pickups and camps this run
	campGems: number?, -- the camps' share of pickGems (analytics)
	cans: number?,
	place: number?, -- final place (set when going out, or at the end for those still in)
	tigers: { [number]: boolean }?, -- tiger pieces whose charge this runner has had
	finishPlace: number?, -- order across the finish line (everyone who crosses wins)
}
local runs: { [Player]: Run } = {}
local paceDist = 0
local guardian: Model
local water: Part

local function now(): number
	return workspace:GetServerTimeNow()
end

local function notify(player: Player, text: string)
	notifyRemote:FireClient(player, text)
end

local function status(text: string)
	workspace:SetAttribute("Status", text)
end

local function metres(studs: number): number
	return math.max(0, math.floor(studs / Config.StudsPerMetre))
end

local function rootOf(player: Player): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function buildLobby()
	-- The cave-temple lobby is built in the place (Workspace.LobbyBuilding, 600 studs up so the
	-- run path never meets it). Without it, fall back to the old placeholder platform.
	local building = workspace:FindFirstChild("LobbyBuilding")
	local spawnPoint = building and building:FindFirstChild("LobbySpawn") :: BasePart?
	if spawnPoint then
		LOBBY_CF = CFrame.new(spawnPoint.Position)
		local base = workspace:FindFirstChild("Baseplate")
		if base then
			base:Destroy()
		end
	end
	for _, name in { "Baseplate", "SpawnLocation" } do
		local x = workspace:FindFirstChild(name)
		if x and not x:GetAttribute("JJ") then
			x:Destroy()
		end
	end
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	if spawnPoint then
		lobby = nil :: any
	end
	local function p(cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.CFrame = cf
		part.Size = size
		part.Color = color
		part.Material = mat
		part.TopSurface = Enum.SurfaceType.Smooth
		part.Parent = lobby
		return part
	end
	if lobby then
		p(LOBBY_CF * CFrame.new(0, -2, 0), Vector3.new(90, 4, 70), Palette.StoneLight, Enum.Material.Slate)
		p(LOBBY_CF * CFrame.new(0, -20, 0), Vector3.new(86, 32, 66), Palette.StoneShadow, Enum.Material.Slate)
		for _, x in { -40, 40 } do
			for _, z in { -30, 30 } do
				p(LOBBY_CF * CFrame.new(x, 7, z), Vector3.new(5, 14, 5), Palette.StoneMoss, Enum.Material.Slate)
			end
		end
		local spawn = Instance.new("SpawnLocation")
		spawn.Anchored = true
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.CFrame = LOBBY_CF * CFrame.new(0, 0.5, 0)
		spawn.Color = Palette.UiGold
		spawn.Material = Enum.Material.Slate
		spawn.Duration = 0
		spawn:SetAttribute("JJ", true)
		spawn.Parent = lobby
		lobby.Parent = workspace
	end

	-- Water plane follows the Guardian so there is always sea under the jungle.
	water = Instance.new("Part")
	water.Name = "Water"
	water.Anchored = true
	water.CanCollide = false
	water.CanQuery = false
	water.Size = Vector3.new(2048, 1, 2048)
	water.Color = Palette.Water
	water.Material = Enum.Material.SmoothPlastic
	water.Reflectance = 0.3
	water.Transparency = 0.05
	water.CFrame = CFrame.new(0, -34.5, 0)
	water.Parent = workspace
end

local function buildGuardian()
	-- The forest monster (ReplicatedStorage.Assets.ForestMonster, pivot at its feet, facing -Z).
	-- Clients run its legs from how fast it moves (client/GuardianGait); the stone figure below
	-- is only the fallback if the template is missing.
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local monster = assets and assets:FindFirstChild("ForestMonster")
	if monster then
		local g = monster:Clone() :: Model
		g.Name = "Guardian"
		g:PivotTo(CFrame.new(0, -100, 0))
		g.Parent = workspace
		guardian = g
		return
	end
	local m = Instance.new("Model")
	m.Name = "Guardian"
	local function p(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Size = size
		part.CFrame = offset
		part.Color = color
		part.Material = mat
		part.Parent = m
		return part
	end
	local body = p("Body", Vector3.new(16, 16, 10), CFrame.new(0, 10, 0), Palette.Guardian, Enum.Material.Slate)
	m.PrimaryPart = body
	p("Head", Vector3.new(11, 9, 9), CFrame.new(0, 22, -1), Palette.StoneMoss, Enum.Material.Slate)
	p("EyeL", Vector3.new(2.2, 1.4, 0.6), CFrame.new(-2.5, 23, -5.6), Palette.GuardianEyes, Enum.Material.Neon)
	p("EyeR", Vector3.new(2.2, 1.4, 0.6), CFrame.new(2.5, 23, -5.6), Palette.GuardianEyes, Enum.Material.Neon)
	local maskT = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	maskT = maskT and maskT:FindFirstChild("GuardianMask")
	if maskT then
		local mask = maskT:Clone() :: BasePart
		local mesh = mask:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			mesh.Scale = Vector3.new(11, 11, 11)
		end
		mask.Name = "Mask"
		mask.Size = Vector3.new(10, 10, 4)
		mask.CFrame = CFrame.new(0, 22.5, -5.2) -- facing forward (-Z), over the stone head
		mask.Anchored = true
		mask.CanCollide = false
		mask.CanQuery = false
		mask.Parent = m
		for _, n in { "EyeL", "EyeR" } do
			(m:FindFirstChild(n) :: BasePart).Transparency = 1
		end
	end
	p("ArmL", Vector3.new(5, 16, 5), CFrame.new(-11, 9, -2), Palette.StoneShadow, Enum.Material.Slate)
	p("ArmR", Vector3.new(5, 16, 5), CFrame.new(11, 9, -2), Palette.StoneShadow, Enum.Material.Slate)
	for i = 1, 5 do
		local vine = p(
			"Vine" .. i,
			Vector3.new(1, 14, 1),
			CFrame.new(-8 + i * 3, 12, -5.4) * CFrame.Angles(0, 0, (i - 3) * 0.12),
			Palette.CanopyMid,
			Enum.Material.Grass
		)
		vine.Shape = Enum.PartType.Block
	end
	m:PivotTo(CFrame.new(0, -100, 0))
	m.Parent = workspace
	guardian = m
end

-- Position bonus: holding one of the bonus places pays extra metres on everything you run
-- while you hold it. Bonus places shrink as the field does (5+ left: 1-3, 4 left: 1-2,
-- 3 or fewer: only 1st).
local PLACE_MULT = { 1.11, 1.07, 1.04 } -- e.g. 500 m in 1st adds ~55 m
local function bonusPlaces(alive: number): number
	return if alive >= 5 then 3 elseif alive == 4 then 2 else 1
end

-- score metres = real metres + position bonus
local function scoreMetres(run: any): number
	return metres(run.dist) + math.floor(run.bonus or 0)
end

local function setRunAttrs(player: Player, run: Run)
	player:SetAttribute("Juice", math.floor(run.juice * 10) / 10)
	player:SetAttribute("Distance", metres(run.dist))
end

local function runners(): { Player }
	local t = {}
	for player, _ in runs do
		if player.Parent and player:GetAttribute("State") == "Running" then
			table.insert(t, player)
		end
	end
	return t
end

-- Run speed multiplier after `elapsed` seconds (Config.RunSpeedSteps, linear between steps).
local function speedMul(elapsed: number): number
	local steps = Config.RunSpeedSteps
	for i = 2, #steps do
		local a, b = steps[i - 1], steps[i]
		if elapsed < b[1] then
			return a[2] + (b[2] - a[2]) * (elapsed - a[1]) / (b[1] - a[1])
		end
	end
	return steps[#steps][2]
end

-- Places (battle-royale rule): the order runners go out decides them. Whoever goes out is
-- placed at the number of runners still in at that moment (themselves included), so the last
-- one standing is 1st whatever the distances. Counted fresh at each elimination, so two going
-- out in the same frame get different places and a player leaving mid-run can't skew it.
local botPlace: { [string]: number } = {}
local runField = 0 -- runners at the start of this run
-- RunField entries by runner, so the race strip can be fed each runner's metres (attribute M)
local playerEntry: { [Player]: Configuration } = {}
local botEntry: { [number]: Configuration } = {}

local function markOut(name: string)
	local f = workspace:FindFirstChild("RunField")
	if f then
		for _, e in f:GetChildren() do
			if e:GetAttribute("Runner") == name and not e:GetAttribute("Out") then
				e:SetAttribute("Out", true)
				return
			end
		end
	end
end

-- A caught runner stays where they went out (behind their death screen / while spectating) but
-- nobody sees the body; toLobby brings it back.
local function setInvisible(player: Player, hidden: boolean)
	local c = player.Character
	if not c then
		return
	end
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if hidden then
				if d:GetAttribute("JJShownT") == nil then
					d:SetAttribute("JJShownT", d.Transparency)
				end
				d.Transparency = 1
			elseif d:GetAttribute("JJShownT") ~= nil then
				d.Transparency = d:GetAttribute("JJShownT")
				d:SetAttribute("JJShownT", nil)
			end
		end
	end
	c:SetAttribute("Hidden", hidden)
end

local function statsFor(player: Player, run: Run, reason: string, place: number, win: boolean?)
	local score = scoreMetres(run)
	return {
		reason = reason,
		win = win,
		metres = metres(run.dist),
		bonus = math.floor(run.bonus or 0),
		place = place,
		field = runField,
		gems = (run.pickGems or 0) + math.floor(score * Config.GemsPerMetre),
		cans = run.cans or 0,
		time = math.floor(now() - (workspace:GetAttribute("RunStart") or now())),
	}
end

local function catch(player: Player, reason: string)
	local run = runs[player]
	if not run or player:GetAttribute("State") ~= "Running" then
		return
	end
	run.place = #runners() + BotService.aliveCount() -- still Running here, so counted
	markOut(player.DisplayName)
	run.caughtAt = os.clock()
	Funnel.step(player, F.RunEnded)
	player:SetAttribute("State", "Caught")
	player:SetAttribute("Queued", false) -- not pulled into the next round while on the death screen
	local m = metres(run.dist)
	DataService.submitDistance(player, scoreMetres(run))
	-- the "you died" screen: this run's stats, then spectate or leave
	diedRemote:FireClient(player, statsFor(player, run, reason, run.place))
	print(string.format("[JJ.Round] %s caught (%s) at %d m", player.Name, reason, m))
	local at = rootOf(player)
	if at then
		sfxRemote:FireAllClients(reason == "Caught by the Guardian" and "GuardianCatch" or "Takedown", at.Position)
	end
	-- stay on the run map (frozen where you died) behind the death screen; LEAVE or the round
	-- ending sends you to the lobby
	local root = rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
	end
	task.delay(0.6, function()
		if player:GetAttribute("State") == "Caught" then
			setInvisible(player, true)
		end
	end)
end

local function toLobby(player: Player)
	setInvisible(player, false)
	local c = player.Character
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	if c then
		c:PivotTo(LOBBY_CF * CFrame.new(math.random(-20, 20), 4, math.random(-15, 15)))
	end
end

local botHooks: BotService.Hooks = {
	gone = function(name, reason, m, pos)
		botPlace[name] = #runners() + BotService.aliveCount() + 1 -- this bot is already marked out
		markOut(name)
		sfxRemote:FireAllClients(reason == "Caught by the Guardian" and "GuardianCatch" or "Takedown", pos)
		for other, _ in runs do
			if other.Parent then
				notify(other, string.format("%s: %s at %d m", name, reason == "Fell" and "fell" or "caught", m))
			end
		end
	end,
}

-- Abilities that hit other runners -------------------------------------------------------
-- They hold someone in place under a second, or hex them for 2 s at 10% slower; never out.
-- A Shell Shield takes the hit instead. Players get attributes (HeldUntil/HeldKind,
-- HexUntil/HexKind) their client applies; bots go through BotService.hit. Clients draw it all
-- (client/AbilityFx) from those attributes.
type Target = { player: Player?, idx: number?, name: string, root: BasePart, dist: number }

local function targetAhead(player: Player, run: Run): Target?
	local best: Target? = nil
	local function consider(t: Target)
		if t.dist > run.dist and t.dist - run.dist < 260 and (not best or t.dist < (best :: Target).dist) then
			best = t
		end
	end
	for other, oRun in runs do
		local r = rootOf(other)
		if other ~= player and r and other:GetAttribute("State") == "Running" then
			consider({ player = other, name = other.DisplayName, root = r, dist = oRun.dist })
		end
	end
	for _, b in BotService.targets() do
		consider({ idx = b.idx, name = b.name, root = b.root, dist = b.dist })
	end
	return best
end

local VERB = { spear = "speared", ice = "froze", bubble = "bubbled", hex = "hexed" }
local function landHit(from: Player, tgt: Target, kind: string, look: string, secs: number)
	local verb = VERB[kind == "hex" and "hex" or look]
	local t = now()
	if tgt.player then
		local victim = tgt.player :: Player
		if not victim.Parent or victim:GetAttribute("State") ~= "Running" then
			return
		end
		if victim:GetAttribute("Shield") then
			victim:SetAttribute("Shield", nil)
			abilityFx:FireAllClients("shieldpop", tgt.root)
			notify(victim, string.format("Your shield blocked %s!", from.DisplayName))
			notify(from, string.format("%s's shield blocked it!", tgt.name))
			return
		end
		if kind == "held" then
			victim:SetAttribute("HeldKind", look)
			victim:SetAttribute("HeldUntil", t + secs)
		else
			victim:SetAttribute("HexKind", look)
			victim:SetAttribute("HexUntil", t + secs)
		end
		notify(victim, string.format("%s %s you!", from.DisplayName, verb))
	elseif tgt.idx then
		BotService.hit(tgt.idx :: number, kind, look, secs)
	end
	notify(from, string.format("You %s %s!", verb, tgt.name))
end

-- a throw at the runner ahead: the effect lands when the throw arrives
local function throwAt(player: Player, run: Run, fx: string, travel: number, kind: string, look: string, secs: number)
	local tgt = targetAhead(player, run)
	local me = rootOf(player)
	if not tgt or not me then
		notify(player, "Nobody ahead to hit!")
		return
	end
	abilityFx:FireAllClients(fx, me, tgt.root)
	task.delay(travel, landHit, player, tgt, kind, look, secs)
end

-- Bubble traps on the course: anyone but the one who dropped it, touching one, floats 0.9 s
type Trap = { part: BasePart, owner: Player, expires: number }
local traps: { Trap } = {}
local function clearTraps()
	for _, tr in traps do
		tr.part:Destroy()
	end
	table.clear(traps)
end

local function dropTrap(player: Player, run: Run)
	local tgt = targetAhead(player, run)
	local me = rootOf(player)
	if not me then
		return
	end
	-- in front of the runner ahead (or of you, if nobody is), on their line across the path
	local refDist = tgt and tgt.dist or run.dist
	local refPos = tgt and tgt.root.Position or me.Position
	-- on the route they are on (a side route of a crossroads block, or the main course)
	local _, refSeg = PathService.progress(refPos, refDist)
	local route = refSeg and refSeg.route or 0
	local here = PathService.pointAt(refDist, route)
	local lat = (refPos - here.Position):Dot(here.RightVector)
	local at = PathService.pointAt(refDist + 30, route)
	local pos = (at * CFrame.new(lat, 0, 0)).Position
	local ball = Instance.new("Part")
	ball.Name = "BubbleTrap"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(5, 5, 5)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Glass
	ball.Color = Palette.Gem
	ball.Transparency = 0.45
	ball.Position = Vector3.new(pos.X, refPos.Y, pos.Z)
	ball.Parent = workspace
	table.insert(traps, { part = ball, owner = player, expires = now() + 25 })
	abilityFx:FireAllClients("trapdrop", me, ball)
	notify(player, if tgt then string.format("Bubble dropped in front of %s!", tgt.name) else "Bubble dropped ahead!")
end

local function stepTraps()
	local t = now()
	for i = #traps, 1, -1 do
		local tr = traps[i]
		local hitT: Target? = nil
		local p = tr.part.Position
		for other, oRun in runs do
			local r = rootOf(other)
			if
				other ~= tr.owner
				and r
				and other:GetAttribute("State") == "Running"
				and (r.Position - p).Magnitude < 4.5
			then
				hitT = { player = other, name = other.DisplayName, root = r, dist = oRun.dist }
				break
			end
		end
		if not hitT then
			for _, b in BotService.targets() do
				if (b.root.Position - p).Magnitude < 4.5 then
					hitT = { idx = b.idx, name = b.name, root = b.root, dist = b.dist }
					break
				end
			end
		end
		if hitT then
			abilityFx:FireAllClients("trappop", hitT.root, tr.part)
			if tr.owner.Parent then
				landHit(tr.owner, hitT, "held", "bubble", 0.9)
			end
		end
		if hitT or t > tr.expires then
			tr.part:Destroy()
			table.remove(traps, i)
		end
	end
end

local HEX_LOOKS = { "chicken", "skeleton", "frog" }

useGadgetEffect = function(player: Player, run: Run, id: string)
	local t = now()
	if id == "JuiceFlask" then
		run.juice = math.min(Config.JuiceMax, run.juice + 35)
	elseif id == "SprintLeaf" then
		player:SetAttribute("SpeedUntil", t + 4)
	elseif id == "HoneyJar" then
		run.honeyUntil = t + 8
		run.juice = math.min(Config.JuiceMax, run.juice + 10)
	elseif id == "BaitFruit" then
		paceDist -= 35
	elseif id == "GoldenIdol" then
		paceDist -= 80
		DataService.addGems(player, 3, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "GoldenIdol")
	elseif id == "GrappleVine" then
		player:SetAttribute("FlyUntil", t + 1.6)
		player:SetAttribute("LeapAt", t)
	elseif id == "SpiritWings" then
		player:SetAttribute("FlyUntil", t + 5)
	elseif id == "RocketBoots" then
		player:SetAttribute("RocketAt", t)
	elseif id == "ShellShield" then
		player:SetAttribute("Shield", true)
	elseif id == "GemMagnet" then
		player:SetAttribute("MagnetUntil", t + 6)
	elseif id == "SpearThrow" then
		throwAt(player, run, "spear", 0.3, "held", "spear", 0.9)
	elseif id == "FrostBreath" then
		throwAt(player, run, "frost", 0.25, "held", "ice", 0.9)
	elseif id == "WildHex" then
		throwAt(player, run, "hex", 0.3, "hex", HEX_LOOKS[math.random(1, #HEX_LOOKS)], 2)
	elseif id == "BubbleTrap" then
		dropTrap(player, run)
	end
	print(string.format("[JJ.Round] %s used %s", player.Name, id))
end

local function setupRemotes()
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	notifyRemote = Instance.new("RemoteEvent")
	notifyRemote.Name = "Notify"
	notifyRemote.Parent = remotes
	diedRemote = Instance.new("RemoteEvent")
	diedRemote.Name = "Died"
	diedRemote.Parent = remotes
	sfxRemote = Instance.new("RemoteEvent")
	sfxRemote.Name = "Sfx"
	sfxRemote.Parent = remotes
	tigerRemote = Instance.new("RemoteEvent")
	tigerRemote.Name = "Tiger"
	tigerRemote.Parent = remotes
	local tigerHit = Instance.new("RemoteEvent")
	tigerHit.Name = "TigerHit"
	tigerHit.Parent = remotes
	tigerHit.OnServerEvent:Connect(function(player)
		if not Guard.allow(player, "TigerHit") then
			return
		end
		catch(player, "Taken out by the tiger")
	end)
	local leave = Instance.new("RemoteEvent")
	leave.Name = "LeaveMatch"
	leave.Parent = remotes
	leave.OnServerEvent:Connect(function(player)
		if not Guard.allow(player, "LeaveMatch") then
			return
		end
		if player:GetAttribute("State") == "Caught" then
			toLobby(player)
			resetPlayer(player)
		end
	end)
	-- Testing only (Studio or the game owner): Q gives a short sprint so you can pull ahead.
	local testBoost = Instance.new("RemoteEvent")
	testBoost.Name = "TestBoost"
	testBoost.Parent = remotes
	testBoost.OnServerEvent:Connect(function(player)
		if not Guard.allow(player, "TestBoost") then
			return
		end
		if not (RunService:IsStudio() or player.UserId == game.CreatorId) then
			Guard.flag(player, "testboost") -- the button only exists for the owner
			return
		end
		if player:GetAttribute("State") == "Running" then
			player:SetAttribute("SpeedUntil", now() + 6)
		end
	end)
	abilityFx = Instance.new("RemoteEvent")
	abilityFx.Name = "AbilityFx"
	abilityFx.Parent = remotes
	-- a Shell Shield soaks up an obstacle bump too: the client says when it did
	local shieldPop = Instance.new("RemoteEvent")
	shieldPop.Name = "ShieldPop"
	shieldPop.Parent = remotes
	shieldPop.OnServerEvent:Connect(function(player)
		if player:GetAttribute("Shield") then
			player:SetAttribute("Shield", nil)
			local r = rootOf(player)
			if r then
				abilityFx:FireAllClients("shieldpop", r)
			end
		end
	end)
	dartFx = Instance.new("RemoteEvent")
	dartFx.Name = "DartFx"
	dartFx.Parent = remotes
	local collect = Instance.new("RemoteEvent")
	collect.Name = "Collect"
	collect.Parent = remotes
	local dart = Instance.new("RemoteEvent")
	dart.Name = "Dart"
	dart.Parent = remotes
	local queue = Instance.new("RemoteEvent")
	queue.Name = "Queue"
	queue.Parent = remotes
	local useGadget = Instance.new("RemoteEvent")
	useGadget.Name = "UseGadget"
	useGadget.Parent = remotes
	ShopService.init(remotes)
	-- remotes the server only ever fires: a client firing one is tampering. Plus one decoy that
	-- looks like a dev cheat and is never used by the game.
	for _, r in { notifyRemote, diedRemote, sfxRemote, tigerRemote, dartFx } do
		Guard.trap(r)
	end
	local decoy = Instance.new("RemoteEvent")
	decoy.Name = "AdminGiveGems"
	decoy.Parent = remotes
	Guard.trap(decoy)
	remotes.Parent = ReplicatedStorage

	queue.OnServerEvent:Connect(function(player, on)
		if not Guard.allow(player, "Queue") then
			return
		end
		if player:GetAttribute("State") == "Lobby" then
			player:SetAttribute("Queued", on == true)
			if on == true then
				Funnel.step(player, F.Queued)
			end
			-- PLAY button: stand the player on the play pad so they can see they're in
			local pad = workspace:FindFirstChild("LobbyBuilding") and workspace.LobbyBuilding:FindFirstChild("PlayPad")
			local char = player.Character
			if on == true and pad and char then
				local c: Vector3? = pad:GetAttribute("Centre")
				local hx, hz = pad:GetAttribute("HalfX") or 4, pad:GetAttribute("HalfZ") or 4
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if c and root then
					local d = root.Position - c
					if math.abs(d.X) > hx or math.abs(d.Z) > hz then
						local r = Random.new()
						local at = c + Vector3.new(r:NextNumber(-hx + 2, hx - 2), 3, r:NextNumber(-hz + 2, hz - 2))
						char:PivotTo(CFrame.lookAt(at, Vector3.new(0, at.Y, 10)))
					end
				end
			end
		end
	end)

	useGadget.OnServerEvent:Connect(function(player, slot)
		if not Guard.allow(player, "UseGadget") then
			return
		end
		local run = runs[player]
		if type(slot) ~= "number" or not run or player:GetAttribute("State") ~= "Running" then
			return
		end
		local id = run.slots[slot]
		if not id then
			return
		end
		run.slots[slot] = nil
		player:SetAttribute("Gadget" .. slot, nil)
		useGadgetEffect(player, run, id)
	end)

	collect.OnServerEvent:Connect(function(player, id)
		if not Guard.allow(player, "Collect") then
			return
		end
		local run = runs[player]
		if type(id) ~= "number" or not run or run.collected[id] or player:GetAttribute("State") ~= "Running" then
			return
		end
		local bottle = PathService.bottle(id)
		local root = rootOf(player)
		if
			not bottle
			or not root
			or (bottle.Position - root.Position).Magnitude
				> Config.BottlePickupRadius + 8 + (if now() < (player:GetAttribute("MagnetUntil") or 0) then 34 else 0)
		then
			return
		end
		run.collected[id] = true
		local kind = bottle:GetAttribute("Kind")
		if kind == "Box" then
			local p = DataService.get(player)
			local pool = p and p.loadout or Items.DefaultGadgets
			for i = 1, Items.SlotCount do
				if not run.slots[i] then
					local g = pool[math.random(1, #pool)]
					run.slots[i] = g
					player:SetAttribute("Gadget" .. i, g)
					break
				end
			end
		elseif kind == "Gem" then
			DataService.addGems(player, Config.GemPickup)
			run.pickGems = (run.pickGems or 0) + Config.GemPickup
		else
			run.cans = (run.cans or 0) + 1
			run.juice = math.min(Config.JuiceMax, run.juice + Config.BottleJuice)
		end
	end)

	dart.OnServerEvent:Connect(function(player, target)
		if not Guard.allow(player, "Dart") then
			return
		end
		if typeof(target) ~= "Instance" or not target:IsA("Player") or target == player then
			return
		end
		local tRun = runs[target]
		if player:GetAttribute("State") ~= "Running" or target:GetAttribute("State") ~= "Running" or not tRun then
			return
		end
		local t = now()
		if t < (player:GetAttribute("DartReadyAt") or 0) - 0.15 then
			return
		end
		local a, b = rootOf(player), rootOf(target)
		if not a or not b or (a.Position - b.Position).Magnitude > Config.DartRange + 12 then
			return
		end
		player:SetAttribute("DartReadyAt", t + Config.DartCooldown)
		tRun.juice = math.max(0, tRun.juice - Config.DartJuiceDrain)
		target:SetAttribute("SlowUntil", t + Config.DartSlowSeconds)
		dartFx:FireAllClients(player, target)
		notify(target, player.DisplayName .. " darted you!")
	end)
end

resetPlayer = function(player: Player)
	player:SetAttribute("State", "Lobby")
	player:SetAttribute("Juice", Config.JuiceStart)
	player:SetAttribute("Distance", 0)
	player:SetAttribute("SlowUntil", 0)
	player:SetAttribute("DartReadyAt", 0)
	player:SetAttribute("Queued", false)
	for i = 1, Items.SlotCount do
		player:SetAttribute("Gadget" .. i, nil)
	end
	player:SetAttribute("SpeedUntil", 0)
	player:SetAttribute("FlyUntil", 0)
	for _, a in { "HeldUntil", "HeldKind", "HexUntil", "HexKind", "Shield", "MagnetUntil", "RocketAt" } do
		player:SetAttribute(a, nil)
	end
	player:SetAttribute("Place", nil)
	player:SetAttribute("PlaceMult", nil)
	player:SetAttribute("BonusM", nil)
end

local function waitWithStatus(seconds: number, fmt: string)
	for i = seconds, 1, -1 do
		status(string.format(fmt, i))
		task.wait(1)
	end
end

-- The path for the next run is built a few seconds before it starts, while everyone is still in
-- the lobby, so it has replicated by the time runners are moved onto it.
local prebuilt = false
local function prebuild()
	local seed = math.random(1, 2 ^ 30)
	-- 35% of runs are at night (clients switch their lighting while running)
	-- a brand-new player's very first run is at night (it looks best) and easier; after that
	-- night is a 35% roll and the course is the normal one
	local firstEver = false
	for _, pl in Players:GetPlayers() do
		if pl:GetAttribute("Queued") and (pl:GetAttribute("Runs") or 0) == 0 and not runsThisSession[pl] then
			firstEver = true
		end
	end
	workspace:SetAttribute("EasyRun", firstEver)
	PathService.reset(seed)
	PathService.ensureAhead(0)
	prebuilt = true
	print(string.format("[JJ.Round] path prebuilt seed=%d", seed))
end

-- Goal race: every run rolls a goal distance, rounded to 50 m: the New range if anyone in the
-- run has fewer than GoalNewRuns runs, else the Normal one. Everyone who reaches it wins; if
-- nobody does, the last one out (the furthest) wins as before. The finish is a black-and-white
-- chequered line with an arch.
local function rollGoalMetres(list: { Player }): number
	local shift = 0
	for _, p in list do
		if (p:GetAttribute("Runs") or 0) < Config.GoalNewRuns then
			shift = Config.GoalNewShift
		end
	end
	local r = math.random()
	local pick = Config.GoalBuckets[1]
	for _, bucket in Config.GoalBuckets do
		pick = bucket
		r -= bucket[1]
		if r <= 0 then
			break
		end
	end
	local m = pick[2] + math.random() * (pick[3] - pick[2]) - shift
	return math.max(800, math.floor(m / 50 + 0.5) * 50)
end

local function buildFinish(goal: number)
	local seg = PathService.segmentAt(goal)
	local cf = PathService.pointAt(goal)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = PathService.solids()
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	local y = hit and hit.Position.Y or cf.Position.Y
	local base = CFrame.new(cf.Position.X, y, cf.Position.Z) * cf.Rotation
	local W = Config.PathWidth
	-- clear any obstacle standing on the line (spikes, blocks, logs): everything above the floor
	-- between the walls, a few studs either side of the tiles
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = { workspace:FindFirstChild("Path") or seg.model }
	for _, q in workspace:GetPartBoundsInBox(base * CFrame.new(0, 8, 0), Vector3.new(W - 2, 14, 30), op) do
		if q.Position.Y - q.Size.Y / 2 > y - 0.6 and q.Position.Y + q.Size.Y / 2 > y + 0.5 then
			q:Destroy()
		end
	end
	local f = Instance.new("Model")
	f.Name = "FinishLine"
	local function part(size: Vector3, at: CFrame, color: Color3, solid: boolean?): Part
		local q = Instance.new("Part")
		q.Anchored = true
		q.CanCollide = solid == true
		q.CanQuery = false
		q.CanTouch = false
		q.CastShadow = false
		q.Material = Enum.Material.SmoothPlastic
		q.Size = size
		q.CFrame = at
		q.Color = color
		q.Parent = f
		return q
	end
	local N = 8
	local tile = W / N
	for i = 0, N - 1 do
		for j = 0, 1 do
			-- 0.15 above the floor so the tiles never z-fight it
			part(
				Vector3.new(tile, 0.2, tile),
				base * CFrame.new(-W / 2 + tile * (i + 0.5), 0.15, tile * (j - 0.5)),
				(i + j) % 2 == 0 and Palette.FinishDark or Palette.FinishLight
			)
		end
	end
	-- arch: two posts and a chequered banner across the top
	for _, sx in { -1, 1 } do
		part(Vector3.new(1.6, 19, 1.6), base * CFrame.new(sx * (W / 2 + 1.5), 9.5, 0), Palette.FinishDark)
	end
	local M = 16
	local bw = (W + 4.6) / M
	for i = 0, M - 1 do
		for j = 0, 1 do
			part(
				Vector3.new(bw, 1.2, 0.6),
				base * CFrame.new(-(W + 4.6) / 2 + bw * (i + 0.5), 17.6 + j * 1.2, 0),
				(i + j) % 2 == 0 and Palette.FinishDark or Palette.FinishLight
			)
		end
	end
	-- an invisible wall a little past the line keeps winners on the finish while they celebrate
	local stop = part(Vector3.new(W + 24, 40, 2), base * CFrame.new(0, 15, -50), Palette.FinishDark, true)
	stop.Transparency = 1
	f.Parent = seg.model
end

local function playRound()
	-- Gather everyone who is spawned in
	runs = {}
	local list = {}
	for _, player in Players:GetPlayers() do
		if rootOf(player) and player:GetAttribute("Queued") then
			table.insert(list, player)
		end
	end
	if #list == 0 then
		return
	end

	if not prebuilt then
		prebuild()
	end
	prebuilt = false
	local nBots = math.max(0, Config.FieldSize - #list)
	print(string.format("[JJ.Round] start runners=%d bots=%d", #list, nBots))

	local startCF = PathService.startCFrame()
	workspace:SetAttribute("StartLine", startCF.Position)
	local total = #list + nBots
	runField = total
	botPlace = {}
	-- Two staggered rows kept well inside the walls, so the outside runners have room to start
	-- without clipping the side pillars. Returns the slot's offset from the start line.
	local function lateralOf(i: number): CFrame
		local perRow = math.ceil(total / 2)
		local row = if i > perRow then 1 else 0
		local k = if row == 1 then i - perRow else i
		local n = if row == 1 then total - perRow else perRow
		local edge = Config.PathWidth / 2 - 6
		local x = if n <= 1 then 0 else -edge + 2 * edge * (k - 1) / (n - 1)
		return CFrame.new(x + row * edge / math.max(n - 1, 1), 0, row * 5)
	end
	-- Players are spread through the line-up, bots fill the gaps.
	local slots = {}
	for i = 1, total do
		table.insert(slots, i)
	end
	local botCFs = {}
	for _ = 1, nBots do
		local i = table.remove(slots, math.random(1, #slots)) :: number
		table.insert(botCFs, startCF * lateralOf(i))
	end
	BotService.spawn(list[1], botCFs)
	-- the field, for the portrait row at the top of the screen (client/Hud): one entry per runner
	-- in line-up order; Out is set when they go out
	local fieldF = workspace:FindFirstChild("RunField") or Instance.new("Folder")
	fieldF.Name = "RunField"
	fieldF:ClearAllChildren()
	playerEntry, botEntry = {}, {}
	local function addEntry(name: string, userId: number, lookId: number?): Configuration
		local e = Instance.new("Configuration")
		e:SetAttribute("LookId", lookId)
		e.Name = string.format("%02d", #fieldF:GetChildren() + 1)
		e:SetAttribute("Runner", name)
		e:SetAttribute("UserId", userId)
		e:SetAttribute("Out", false)
		e:SetAttribute("M", 0)
		e.Parent = fieldF
		return e
	end
	for _, player in list do
		playerEntry[player] = addEntry(player.DisplayName, player.UserId)
	end
	local botLook = BotService.lookUserId(list[1])
	for _, r in BotService.results() do
		botEntry[r.idx] = addEntry(r.name, 0, botLook)
	end
	fieldF.Parent = workspace
	for i, player in list do
		local lateral = lateralOf(slots[i])
		runs[player] = {
			dist = -10,
			juice = Config.JuiceStart,
			emptySince = 0,
			collected = {},
			camps = 0,
			slots = {},
			honeyUntil = 0,
		}
		player:SetAttribute("State", "Countdown")
		player:SetAttribute("RunSpeed", Config.RunSpeedStart)
		player:SetAttribute("Juice", Config.JuiceStart)
		player:SetAttribute("Distance", 0)
		player:SetAttribute("SlowUntil", 0)
		player:SetAttribute("DartReadyAt", 0)
		local c = player.Character
		if c then
			c:PivotTo(startCF * lateral)
		end
		-- nobody moves before RUN!
		local root = rootOf(player)
		if root then
			root.Anchored = true
		end
	end
	paceDist = -Config.PaceStartBehind
	workspace:SetAttribute("PaceDist", paceDist)
	local goalM = rollGoalMetres(list)
	local goalStuds = goalM * Config.StudsPerMetre
	workspace:SetAttribute("GoalM", goalM)
	-- clients play the big "SURVIVE x m" reveal on this (a counter, so equal goals still fire)
	workspace:SetAttribute("GoalRoll", (workspace:GetAttribute("GoalRoll") or 0) + 1)
	print(string.format("[JJ.Round] goal %d m", goalM))
	-- no crossroads block may run across the finish line
	PathService.setBranchLimit(goalStuds - 60)
	local finishBuilt = false
	local finishCount = 0
	local peakAlive = 0
	local botFinish: { [number]: number } = {} -- bot idx -> finish place (names can repeat)
	local function markDone(name: string)
		local f = workspace:FindFirstChild("RunField")
		if f then
			for _, e in f:GetChildren() do
				if e:GetAttribute("Runner") == name and not e:GetAttribute("Finished") then
					e:SetAttribute("Finished", true)
					return
				end
			end
		end
	end
	local function announce(name: string, place: number)
		for other, _ in runs do
			if other.Parent then
				notify(other, string.format("%s made it! (#%d)", name, place))
			end
		end
	end
	local function finishRun(player: Player, run: Run)
		finishCount += 1
		run.finishPlace = finishCount
		run.dist = goalStuds
		setRunAttrs(player, run)
		player:SetAttribute("State", "Finished")
		player:SetAttribute("Place", finishCount)
		markDone(player.DisplayName)
		DataService.submitDistance(player, scoreMetres(run))
		announce(player.DisplayName, finishCount)
		print(string.format("[JJ.Round] %s finished #%d", player.Name, finishCount))
	end
	BotService.setGoal(goalStuds + 5, function(name: string, idx: number)
		finishCount += 1
		botFinish[idx] = finishCount
		markDone(name)
		announce(name, finishCount)
	end)
	guardian:PivotTo(PathService.pointAt(paceDist))

	task.wait(Config.GoalRevealSeconds) -- the goal reveal plays before the drum countdown
	waitWithStatus(Config.CountdownSeconds, "%d")
	status("RUN!")
	local runStart = now()
	workspace:SetAttribute("RunStart", runStart)
	for player, _ in runs do
		if player.Parent then
			local root = rootOf(player)
			if root then
				root.Anchored = false
			end
			player:SetAttribute("State", "Running")
			runsThisSession[player] = (runsThisSession[player] or 0) + 1
			Funnel.step(player, runsThisSession[player] == 1 and F.RunStarted or F.SecondRun)
		end
	end
	task.delay(1, function()
		if workspace:GetAttribute("Status") == "RUN!" then
			status("")
		end
	end)

	local attrClock = 0
	local lastAliveCount = -1
	while true do
		local dt = RunService.Heartbeat:Wait()
		local elapsed = now() - runStart
		local runSpeed = Config.RunSpeedStart * speedMul(elapsed)
		if elapsed > Config.PaceGrace then
			paceDist += runSpeed * Config.PaceSpeedRatio * dt
			-- Catch-up keyed to the PACK, never one runner: everyone still in (players AND bots)
			-- sorted back to front, and the Guardian is kept within PaceMaxGap of the runner a
			-- third of the way up from the back. A leader running away doesn't drag it forward onto
			-- the field, and the very last runner isn't the one setting its pace.
			local field: { number } = {}
			for player, run in runs do
				if player:GetAttribute("State") == "Running" then
					table.insert(field, run.dist)
				end
			end
			for _, d in BotService.aliveDists() do
				table.insert(field, d)
			end
			if #field > 0 then
				table.sort(field)
				local anchor = field[math.max(1, math.ceil(#field / 3))]
				paceDist = math.max(paceDist, anchor - Config.PaceMaxGap)
			end
			-- it stops short of the finish, so winners celebrate in peace
			paceDist = math.min(paceDist, goalStuds - 40)
		end

		local alive = runners()
		local leader = paceDist
		for _, player in alive do
			local run = runs[player]
			local root = rootOf(player)
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not root or not hum or hum.Health <= 0 then
				catch(player, "Lost")
				continue
			end
			local d, seg = PathService.progress(root.Position, run.dist)
			if seg then
				run.route = seg.route
				run.routeMul = PathService.speedMul(seg)
			end
			-- Anti-cheat: the character is client-owned, so a speed hack or teleport would move it
			-- anywhere. Distance can only grow as fast as the quickest legit move (gadgets included).
			local leaping = now() - (player:GetAttribute("LeapAt") or -99) < 2 -- Grapple Vine launches at ~95 studs/s
				or now() - (player:GetAttribute("RocketAt") or -99) < 3
			local maxGain = runSpeed * (leaping and Config.MaxSpeedFactor * 1.7 or Config.MaxSpeedFactor) * dt
			run.dist = math.max(run.dist, math.min(d, run.dist + maxGain))
			local flying = now() < (player:GetAttribute("FlyUntil") or 0) + 1
				or now() - (player:GetAttribute("RocketAt") or -99) < 3
			if seg and not flying and root.Position.Y < PathService.floorY(seg) - Config.FallDepth then
				catch(player, "Fell")
				continue
			end
			-- The server sees a client-owned character about half a ping late, and the Guardian
			-- on that client is drawn late too: allow for it, so you're only caught when it has
			-- really reached you on your own screen.
			local lag = math.clamp(player:GetNetworkPing() * runSpeed + 3, 3, 18)
			if run.dist < paceDist - lag then
				catch(player, "Caught by the Guardian")
				continue
			end
			if run.dist >= goalStuds + 5 then
				finishRun(player, run)
				continue
			end
			-- Juice
			if now() >= run.honeyUntil then
				run.juice = math.max(0, run.juice - Config.JuiceDrainPerSecond * dt)
			end
			local mNow = metres(run.dist)
			if mNow >= 100 then
				Funnel.step(player, F.Reached100)
			end
			if mNow >= 500 then
				Funnel.step(player, F.Reached500)
			end
			-- Camps
			local camp = math.floor(metres(run.dist) / Config.CampEveryMetres)
			if camp > run.camps then
				run.camps = camp
				run.juice = math.min(Config.JuiceMax, run.juice + 30)
				DataService.addGems(player, Config.CampGems, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Camp")
				run.pickGems = (run.pickGems or 0) + Config.CampGems
				run.campGems = (run.campGems or 0) + Config.CampGems -- logged already: kept out of PathGems
				notify(player, string.format("CAMP %d reached! +%d gems, +juice", camp, Config.CampGems))
			end
			leader = math.max(leader, run.dist)
		end

		attrClock += dt
		if attrClock >= 0.1 then
			attrClock = 0
			-- live places (players and bots), and the bonus each player is earning
			local field = {}
			for _, player in alive do
				if runs[player] then
					table.insert(field, { player = player, dist = runs[player].dist })
				end
			end
			for _, d in BotService.aliveDists() do
				table.insert(field, { dist = d })
			end
			table.sort(field, function(a, b)
				return a.dist > b.dist
			end)
			local paid = bonusPlaces(#field)
			for place, e in field do
				local run = e.player and runs[e.player]
				-- a finisher keeps the place they crossed the line in (bots that finish later run on
				-- past the line, so their distance would push the finisher down the list)
				if run and not run.finishPlace then
					local mult = place <= paid and PLACE_MULT[place] or 1
					run.bonus = (run.bonus or 0)
						+ math.max(0, run.dist - (run.lastDist or run.dist)) / Config.StudsPerMetre * (mult - 1)
					run.lastDist = run.dist
					e.player:SetAttribute("Place", place)
					e.player:SetAttribute("PlaceMult", mult)
					e.player:SetAttribute("BonusM", math.floor(run.bonus))
				end
			end
			-- Catch-up (rubber band) for players too: well behind the front runner you run up to
			-- 10% faster; out alone in front by a long way, up to 5% slower. Distance is progress
			-- along the path, so forks and side routes count the same.
			local front = field[1] and field[1].dist or 0
			local second = field[2] and field[2].dist or front
			for _, player in alive do
				local run = runs[player]
				if run then
					setRunAttrs(player, run)
					local mul = 1
					local behind = front - run.dist
					if behind > 30 then
						mul = 1 + math.clamp((behind - 30) / 200, 0, 0.1)
					elseif run.dist >= front and run.dist - second > 40 then
						mul = 1 - math.clamp((run.dist - second - 40) / 300, 0, 0.05)
					end
					mul *= run.routeMul or 1 -- a side route's speed-up (PathService.speedMul)
					player:SetAttribute("RunSpeed", math.floor(runSpeed * mul * 10) / 10)
				end
			end
			workspace:SetAttribute("PaceDist", paceDist)
			-- the race strip: every runner's metres on their RunField entry (only on a change)
			for player, run in runs do
				local e = playerEntry[player]
				if e and e.Parent then
					local m = math.max(0, math.floor(metres(run.dist)))
					if e:GetAttribute("M") ~= m then
						e:SetAttribute("M", m)
					end
				end
			end
			for _, r in BotService.results() do
				local e = botEntry[r.idx]
				if e and e.Parent then
					local m = math.max(0, math.floor(metres(r.dist)))
					if e:GetAttribute("M") ~= m then
						e:SetAttribute("M", m)
					end
				end
			end
		end
		local hFront, hBack
		for _, player in runners() do
			local d = runs[player].dist
			hFront = math.max(hFront or d, d)
			hBack = math.min(hBack or d, d)
		end
		BotService.step(dt, runSpeed, paceDist, botHooks, hFront, hBack)
		leader = math.max(leader, BotService.maxDist())
		-- Tiger: each runner gets their own charge, started when they reach the piece (bots
		-- the same, in BotService), so a runner far ahead can't set it off before you arrive.
		for _, player in runners() do
			local run = runs[player]
			local seg = run and PathService.segmentAt(run.dist, run.route)
			if seg and seg.kind == "tiger" and run.dist >= seg.startDist + 4 then
				run.tigers = run.tigers or {}
				if not run.tigers[seg.index] then
					run.tigers[seg.index] = true
					local zone = seg.model:FindFirstChild("TigerZone")
					if zone then
						tigerRemote:FireClient(player, zone, now())
					end
				end
			end
		end
		-- counted fresh (runners caught earlier this frame are already out) and never going back
		-- up during a run, so "N running" only ever counts down
		local aliveN = #runners() + BotService.aliveCount()
		if lastAliveCount >= 0 then
			aliveN = math.min(aliveN, lastAliveCount)
		end
		if aliveN ~= lastAliveCount then
			lastAliveCount = aliveN
			workspace:SetAttribute("Alive", aliveN)
		end

		stepTraps()
		PathService.ensureAhead(math.min(leader, goalStuds + 80))
		if not finishBuilt and PathService.builtDist() > goalStuds + 60 then
			finishBuilt = true
			buildFinish(goalStuds)
		end
		PathService.trimBehind(paceDist)
		guardian:PivotTo(PathService.pointAt(paceDist) * CFrame.new(0, 0, 4))
		local g = guardian:GetPivot().Position
		water.CFrame = CFrame.new(math.floor(g.X / 64) * 64, -34.5, math.floor(g.Z / 64) * 64)

		if #runners() == 0 then
			break
		end
		-- last one standing: once everyone else is out (and nobody has finished), the one left
		-- wins on the spot; the run doesn't drag on with a single runner
		if lastAliveCount >= 0 then
			peakAlive = math.max(peakAlive, aliveN)
		end
		if finishCount == 0 and peakAlive > 1 and aliveN <= 1 then
			for _, player in runners() do
				notify(player, "LAST ONE STANDING!")
			end
			break
		end
	end
	BotService.setGoal(nil, nil)
	clearTraps()

	-- Everyone who made it celebrates on the finish (emotes) before the results come up.
	if finishCount > 0 then
		for player, _ in runs do
			if player.Parent and player:GetAttribute("State") == "Finished" then
				notify(player, "You made it! Celebrate!")
			end
		end
		waitWithStatus(Config.CelebrateSeconds, "Winners celebrate! Results in %d")
		status("")
	end

	-- Results: everyone over the line first (in the order they crossed), then anyone still
	-- running (by distance), then the rest by the place they went out at (catch/botHooks.gone).
	local order = {}
	for player, run in runs do
		if player.Parent then
			table.insert(order, {
				player = player,
				name = player.DisplayName,
				dist = run.dist,
				fin = run.finishPlace,
				alive = player:GetAttribute("State") == "Running",
				out = run.place,
			})
		end
	end
	for _, r in BotService.results() do
		table.insert(order, {
			player = nil,
			name = r.name,
			dist = r.dist,
			fin = botFinish[r.idx],
			alive = r.alive and not botFinish[r.idx],
			out = botPlace[r.name],
		})
	end
	local function rank(e): number
		return if e.fin then 0 elseif e.alive then 1 else 2
	end
	table.sort(order, function(x, y)
		local rx, ry = rank(x), rank(y)
		if rx ~= ry then
			return rx < ry
		end
		if rx == 0 then
			return x.fin < y.fin
		end
		local ox, oy = x.out or math.huge, y.out or math.huge
		if rx == 2 and ox ~= oy then
			return ox < oy
		end
		return x.dist > y.dist
	end)
	for i, e in order do
		e.place = i
	end
	for _, e in order do
		local i = e.place or #order
		if not e.player then
			continue
		end
		e.run = runs[e.player]
		local m = scoreMetres(e.run)
		local gems = math.floor(m * Config.GemsPerMetre)
		if e.fin then
			gems += Config.FinishGems
		end
		if i == 1 and #order > 1 then
			gems += Config.LastStandingGems
		end
		local boosted = FriendBoost.apply(e.player, gems)
		if boosted > gems then
			notify(e.player, string.format("Friend boost: +%d gems", boosted - gems))
		end
		gems = boosted
		local xp = 20 + math.floor(m / 2)
		DataService.addGems(
			e.player,
			gems,
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			i == 1 and #order > 1 and "RunRewardWin" or "RunReward"
		)
		DataService.logGems(
			e.player,
			false,
			(e.run.pickGems or 0) - (e.run.campGems or 0),
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			"PathGems"
		)
		DataService.addXp(e.player, xp)
		DataService.submitDistance(e.player, m, "Stampede")
		DataService.recordRun(e.player, m, i, #order)
		Badges.afterRun(e.player, m, i, #order)
		notify(
			e.player,
			string.format(
				"#%d of %d  %d m%s  +%d gems  +%d XP",
				i,
				#order,
				m,
				(e.run.bonus or 0) >= 1 and string.format(" (incl. +%d bonus)", math.floor(e.run.bonus)) or "",
				gems,
				xp
			)
		)
		local won = e.fin ~= nil or (finishCount == 0 and i == 1 and #order > 1)
		if won then
			notify(e.player, e.fin and "WINNER! You reached the goal!" or "WINNER! You outran the whole jungle!")
		elseif #order > 1 and i <= 3 then
			notify(e.player, string.format("Congratulations, you came %s!", i == 2 and "2nd" or "3rd"))
		end
		task.spawn(DataService.save, e.player)
		-- runners still in at the end get the results screen too (1st: the winner screen)
		local st = e.player:GetAttribute("State")
		if st == "Running" or st == "Finished" then
			e.run.place = i
			Funnel.step(e.player, F.RunEnded)
			e.player:SetAttribute("State", "Caught")
			e.player:SetAttribute("Queued", false)
			local root = rootOf(e.player)
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.Anchored = true
			end
			diedRemote:FireClient(
				e.player,
				statsFor(
					e.player,
					e.run,
					e.fin and string.format("Reached %d m!", goalM)
						or (
							won and (e.alive and "Last one standing!" or "Furthest runner!")
							or "Still running at the end"
						),
					i,
					won
				)
			)
		end
	end
	LeaderboardService.bump()
	local top = order[1]
	if top then
		status(
			finishCount > 0 and string.format("%d made it to %d m!", finishCount, goalM)
				or string.format("%s ran furthest: %d m", top.name, metres(top.dist))
		)
	end
	workspace:SetAttribute("Alive", 0)
	task.wait(5)
	for player, _ in runs do
		-- anyone still on the death screen stays there until they press LEAVE (LeaveMatch)
		if player.Parent and player:GetAttribute("State") ~= "Caught" then
			resetPlayer(player)
		end
	end
	runs = {}
	BotService.clear()
	guardian:PivotTo(CFrame.new(0, -100, 0))
end

-- Runners (players and bots) pass through each other: only gadgets interact between runners.
local PhysicsService = game:GetService("PhysicsService")
local RUNNERS = "Runners"
local function ghost(model: Instance)
	local function set(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = RUNNERS
		end
	end
	for _, d in model:GetDescendants() do
		set(d)
	end
	model.DescendantAdded:Connect(set)
end

function RoundService.init()
	PhysicsService:RegisterCollisionGroup(RUNNERS)
	PhysicsService:CollisionGroupSetCollidable(RUNNERS, RUNNERS, false)
	workspace.ChildAdded:Connect(function(c)
		if c.Name == "Bots" then
			ghost(c)
		end
	end)
	setupRemotes()
	buildLobby()
	LeaderboardService.init()
	buildGuardian()
	DataService.setNotifier(notify)
	DataService.init()
	FriendBoost.init()

	local function onPlayer(player: Player)
		Funnel.step(player, F.Joined)
		resetPlayer(player)
		task.spawn(DataService.load, player)
		if player.Character then
			ghost(player.Character)
		end
		player.CharacterAdded:Connect(function(char)
			ghost(char)
			if player:GetAttribute("State") == "Running" then
				catch(player, "Lost")
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
		runsThisSession[player] = nil
	end)

	task.spawn(function()
		while true do
			workspace:SetAttribute("Mode", "Stampede")
			local startAt = now() + Config.IntermissionSeconds
			workspace:SetAttribute("NextRunAt", startAt)
			status("")
			while now() < startAt do
				task.wait(0.25)
				if not prebuilt and startAt - now() <= 6 then
					for _, pl in Players:GetPlayers() do
						if pl:GetAttribute("Queued") then
							prebuild()
							break
						end
					end
				end
			end
			local anyQueued = false
			for _, pl in Players:GetPlayers() do
				if pl:GetAttribute("Queued") then
					anyQueued = true
				end
			end
			if not anyQueued then
				continue
			end
			workspace:SetAttribute("NextRunAt", 0)
			local ok, err = pcall(playRound)
			if not ok then
				warn("[JJ.Round] round crashed:", err)
				for _, player in Players:GetPlayers() do
					resetPlayer(player)
				end
			end
		end
	end)
end

return RoundService
