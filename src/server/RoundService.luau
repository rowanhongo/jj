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
--   Shields    stumble shields left (future purchase)
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
local BotService = require(script.Parent.BotService)
local Items = require(Shared.Items)

local RoundService = {}

local LOBBY_CF = CFrame.new(0, 0, 220)

local remotes: Folder
local useGadgetEffect: (Player, any, string) -> ()
local notifyRemote: RemoteEvent
local dartFx: RemoteEvent

type Run = {
	dist: number, -- studs
	juice: number,
	emptySince: number,
	collected: { [number]: boolean },
	camps: number,
	caughtAt: number?,
	slots: { string? },
	honeyUntil: number,
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
	for _, name in { "Baseplate", "SpawnLocation" } do
		local x = workspace:FindFirstChild(name)
		if x and not x:GetAttribute("JJ") then
			x:Destroy()
		end
	end
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
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

	-- Water plane follows the Guardian so there is always sea under the jungle.
	water = Instance.new("Part")
	water.Name = "Water"
	water.Anchored = true
	water.CanCollide = false
	water.CanQuery = false
	water.Size = Vector3.new(2048, 1, 2048)
	water.Color = Palette.Water
	water.Material = Enum.Material.SmoothPlastic
	water.Reflectance = 0.15
	water.Transparency = 0.1
	water.CFrame = CFrame.new(0, -34.5, 0)
	water.Parent = workspace
end

local function buildGuardian()
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
	p("ArmL", Vector3.new(5, 16, 5), CFrame.new(-11, 9, -2), Palette.StoneShadow, Enum.Material.Slate)
	p("ArmR", Vector3.new(5, 16, 5), CFrame.new(11, 9, -2), Palette.StoneShadow, Enum.Material.Slate)
	for i = 1, 5 do
		local vine = p("Vine" .. i, Vector3.new(1, 14, 1), CFrame.new(-8 + i * 3, 12, -5.4) * CFrame.Angles(0, 0, (i - 3) * 0.12), Palette.CanopyMid, Enum.Material.Grass)
		vine.Shape = Enum.PartType.Block
	end
	m:PivotTo(CFrame.new(0, -100, 0))
	m.Parent = workspace
	guardian = m
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

local function catch(player: Player, reason: string)
	local run = runs[player]
	if not run or player:GetAttribute("State") ~= "Running" then
		return
	end
	run.caughtAt = os.clock()
	player:SetAttribute("State", "Caught")
	local m = metres(run.dist)
	DataService.submitDistance(player, m)
	notify(player, string.format("%s at %d m. Watching the others...", reason, m))
	print(string.format("[JJ.Round] %s caught (%s) at %d m", player.Name, reason, m))
	local c = player.Character
	if c then
		c:PivotTo(LOBBY_CF * CFrame.new(math.random(-20, 20), 4, math.random(-15, 15)))
	end
end

local function dropTrapAt(rootCF: CFrame, owner: number, width: number, height: number, color: Color3)
	local path = workspace:FindFirstChild("Path")
	if not path then
		return
	end
	local look = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z).Unit
	local at = rootCF.Position - look * 10
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { path }
	local hit = workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), rp)
	if not hit then
		return
	end
	local trap = Instance.new("Part")
	trap.Name = "Trap"
	trap.Anchored = true
	trap.CanCollide = false
	trap.Size = Vector3.new(width, height, 1.6)
	trap.CFrame = CFrame.lookAt(hit.Position, hit.Position + look) * CFrame.new(0, height / 2, 0)
	trap.Color = color
	trap.Material = Enum.Material.Grass
	trap:SetAttribute("Owner", owner)
	CollectionService:AddTag(trap, "Hurdle")
	trap.Parent = path
end

local function dropTrap(player: Player, width: number, height: number, color: Color3)
	local root = rootOf(player)
	if root then
		dropTrapAt(root.CFrame, player.UserId, width, height, color)
	end
end

local botHooks: BotService.Hooks = {
	warDrum = function(name)
		local t = now()
		for other, _ in runs do
			if other:GetAttribute("State") == "Running" then
				other:SetAttribute("SlowUntil", t + 2)
				notify(other, name .. " beat the War Drum!")
			end
		end
	end,
	trap = function(cf, w, h, color)
		dropTrapAt(cf, 0, w, h, color)
	end,
	gone = function(name, reason, m)
		for other, _ in runs do
			if other.Parent then
				notify(other, string.format("%s: %s at %d m", name, reason == "Fell" and "fell" or "caught", m))
			end
		end
	end,
}

useGadgetEffect = function(player: Player, run: Run, id: string)
	local t = now()
	if id == "JuiceFlask" then
		run.juice = math.min(Config.JuiceMax, run.juice + 35)
	elseif id == "VineShield" then
		player:SetAttribute("Shields", (player:GetAttribute("Shields") or 0) + 1)
	elseif id == "SprintLeaf" then
		player:SetAttribute("SpeedUntil", t + 4)
	elseif id == "HoneyJar" then
		run.honeyUntil = t + 8
		run.juice = math.min(Config.JuiceMax, run.juice + 10)
	elseif id == "BananaPeel" then
		dropTrap(player, 3, 0.6, Palette.JuiceGlow)
	elseif id == "ThornTrap" then
		dropTrap(player, Config.PathWidth - 2, 1.4, Palette.CanopyDeep)
	elseif id == "BaitFruit" then
		paceDist -= 35
	elseif id == "GoldenIdol" then
		paceDist -= 80
		DataService.addGems(player, 25)
	elseif id == "WarDrum" then
		for other, _ in runs do
			if other ~= player and other:GetAttribute("State") == "Running" then
				other:SetAttribute("SlowUntil", t + 2)
				notify(other, player.DisplayName .. " beat the War Drum!")
			end
		end
		BotService.slowAll(t + 2)
	elseif id == "GrappleVine" then
		player:SetAttribute("FlyUntil", t + 1.6)
		player:SetAttribute("LeapAt", t)
	elseif id == "SpiritWings" then
		player:SetAttribute("FlyUntil", t + 5)
	end
	print(string.format("[JJ.Round] %s used %s", player.Name, id))
end

local function setupRemotes()
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	notifyRemote = Instance.new("RemoteEvent")
	notifyRemote.Name = "Notify"
	notifyRemote.Parent = remotes
	dartFx = Instance.new("RemoteEvent")
	dartFx.Name = "DartFx"
	dartFx.Parent = remotes
	local collect = Instance.new("RemoteEvent")
	collect.Name = "Collect"
	collect.Parent = remotes
	local useShield = Instance.new("RemoteEvent")
	useShield.Name = "UseShield"
	useShield.Parent = remotes
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
	remotes.Parent = ReplicatedStorage

	queue.OnServerEvent:Connect(function(player, on)
		if player:GetAttribute("State") == "Lobby" then
			player:SetAttribute("Queued", on == true)
		end
	end)

	useGadget.OnServerEvent:Connect(function(player, slot)
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
		local run = runs[player]
		if type(id) ~= "number" or not run or run.collected[id] or player:GetAttribute("State") ~= "Running" then
			return
		end
		local bottle = PathService.bottle(id)
		local root = rootOf(player)
		if not bottle or not root or (bottle.Position - root.Position).Magnitude > Config.BottlePickupRadius + 8 then
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
		else
			run.juice = math.min(Config.JuiceMax, run.juice + Config.BottleJuice)
		end
	end)

	useShield.OnServerEvent:Connect(function(player)
		local n = player:GetAttribute("Shields") or 0
		if n > 0 then
			player:SetAttribute("Shields", n - 1)
		end
	end)

	dart.OnServerEvent:Connect(function(player, target)
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

local function resetPlayer(player: Player)
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
	if player:GetAttribute("Shields") == nil then
		player:SetAttribute("Shields", 0)
	end
end

local function waitWithStatus(seconds: number, fmt: string)
	for i = seconds, 1, -1 do
		status(string.format(fmt, i))
		task.wait(1)
	end
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

	local seed = math.random(1, 2 ^ 30)
	PathService.reset(seed)
	PathService.ensureAhead(0)
	print(string.format("[JJ.Round] start seed=%d runners=%d", seed, #list))

	local startCF = PathService.startCFrame()
	local total = #list + Config.Bots
	local function lateralOf(i: number): number
		return (total == 1) and 0 or (-10 + 20 * (i - 1) / (total - 1))
	end
	-- Players are spread through the line-up, bots fill the gaps.
	local slots = {}
	for i = 1, total do
		table.insert(slots, i)
	end
	local botCFs = {}
	for _ = 1, Config.Bots do
		local i = table.remove(slots, math.random(1, #slots)) :: number
		table.insert(botCFs, startCF * CFrame.new(lateralOf(i), 0, math.random(0, 3)))
	end
	BotService.spawn(list[1], botCFs)
	for i, player in list do
		local lateral = lateralOf(slots[i])
		runs[player] = { dist = -10, juice = Config.JuiceStart, emptySince = 0, collected = {}, camps = 0, slots = {}, honeyUntil = 0 }
		player:SetAttribute("State", "Countdown")
		player:SetAttribute("RunSpeed", Config.RunSpeedStart)
		player:SetAttribute("Juice", Config.JuiceStart)
		player:SetAttribute("Distance", 0)
		player:SetAttribute("SlowUntil", 0)
		player:SetAttribute("DartReadyAt", 0)
		local c = player.Character
		if c then
			c:PivotTo(startCF * CFrame.new(lateral, 0, 0))
		end
	end
	paceDist = -Config.PaceStartBehind
	workspace:SetAttribute("PaceDist", paceDist)
	guardian:PivotTo(PathService.pointAt(paceDist))

	waitWithStatus(Config.CountdownSeconds, "%d")
	status("RUN!")
	local runStart = now()
	workspace:SetAttribute("RunStart", runStart)
	for player, _ in runs do
		if player.Parent then
			player:SetAttribute("State", "Running")
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
		local runSpeed = Config.RunSpeedStart + (Config.RunSpeedMax - Config.RunSpeedStart) * math.clamp(elapsed / Config.RunSpeedRampSeconds, 0, 1)
		if elapsed > Config.PaceGrace then
			paceDist += runSpeed * Config.PaceSpeedRatio * dt
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
			run.dist = math.max(run.dist, d)
			local flying = now() < (player:GetAttribute("FlyUntil") or 0) + 1
			if seg and not flying and root.Position.Y < PathService.floorY(seg) - Config.FallDepth then
				catch(player, "Fell")
				continue
			end
			if run.dist < paceDist then
				catch(player, "Caught by the Guardian")
				continue
			end
			-- Juice
			if now() >= run.honeyUntil then
				run.juice = math.max(0, run.juice - Config.JuiceDrainPerSecond * dt)
			end
			-- Camps
			local camp = math.floor(metres(run.dist) / Config.CampEveryMetres)
			if camp > run.camps then
				run.camps = camp
				run.juice = math.min(Config.JuiceMax, run.juice + 30)
				DataService.addGems(player, Config.CampGems)
				notify(player, string.format("CAMP %d reached! +%d gems, +juice", camp, Config.CampGems))
			end
			leader = math.max(leader, run.dist)
		end

		attrClock += dt
		if attrClock >= 0.1 then
			attrClock = 0
			for _, player in alive do
				local run = runs[player]
				if run then
					setRunAttrs(player, run)
					player:SetAttribute("RunSpeed", math.floor(runSpeed * 10) / 10)
				end
			end
			workspace:SetAttribute("PaceDist", paceDist)
		end
		BotService.step(dt, runSpeed, paceDist, botHooks)
		leader = math.max(leader, BotService.maxDist())
		local aliveN = #alive + BotService.aliveCount()
		if aliveN ~= lastAliveCount then
			lastAliveCount = aliveN
			workspace:SetAttribute("Alive", aliveN)
		end

		PathService.ensureAhead(leader)
		PathService.trimBehind(paceDist)
		guardian:PivotTo(PathService.pointAt(paceDist) * CFrame.new(0, 0, 4))
		local g = guardian:GetPivot().Position
		water.CFrame = CFrame.new(math.floor(g.X / 64) * 64, -34.5, math.floor(g.Z / 64) * 64)

		if #runners() == 0 then
			break
		end
	end

	-- Results
	local order = {}
	for player, run in runs do
		if player.Parent then
			table.insert(order, { player = player, name = player.DisplayName, dist = run.dist })
		end
	end
	for _, r in BotService.results() do
		table.insert(order, { player = nil, name = r.name, dist = r.dist })
	end
	table.sort(order, function(a, b)
		return a.dist > b.dist
	end)
	for i, e in order do
		if not e.player then
			continue
		end
		e.run = runs[e.player]
		local m = metres(e.run.dist)
		local gems = math.floor(m * Config.GemsPerMetre)
		if i == 1 and #order > 1 then
			gems += Config.LastStandingGems
		end
		local xp = 20 + math.floor(m / 2)
		DataService.addGems(e.player, gems)
		DataService.addXp(e.player, xp)
		DataService.submitDistance(e.player, m, "Stampede")
		notify(e.player, string.format("#%d of %d  %d m  +%d gems  +%d XP", i, #order, m, gems, xp))
		task.spawn(DataService.save, e.player)
	end
	local top = order[1]
	if top then
		status(string.format("%s ran furthest: %d m", top.name, metres(top.dist)))
	end
	workspace:SetAttribute("Alive", 0)
	task.wait(5)
	for player, _ in runs do
		if player.Parent then
			resetPlayer(player)
		end
	end
	runs = {}
	BotService.clear()
	guardian:PivotTo(CFrame.new(0, -100, 0))
end

function RoundService.init()
	setupRemotes()
	buildLobby()
	buildGuardian()
	DataService.setNotifier(notify)
	DataService.init()

	local function onPlayer(player: Player)
		resetPlayer(player)
		task.spawn(DataService.load, player)
		player.CharacterAdded:Connect(function()
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
	end)

	task.spawn(function()
		while true do
			workspace:SetAttribute("Mode", "Stampede")
			local startAt = now() + Config.IntermissionSeconds
			workspace:SetAttribute("NextRunAt", startAt)
			status("")
			while now() < startAt do
				task.wait(0.25)
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
