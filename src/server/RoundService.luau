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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local PathService = require(script.Parent.PathService)
local DataService = require(script.Parent.DataService)

local RoundService = {}

local LOBBY_CF = CFrame.new(0, 0, 220)

local remotes: Folder
local notifyRemote: RemoteEvent
local dartFx: RemoteEvent

type Run = {
	dist: number, -- studs
	juice: number,
	emptySince: number,
	collected: { [number]: boolean },
	camps: number,
	caughtAt: number?,
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
	remotes.Parent = ReplicatedStorage

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
		if bottle:GetAttribute("Kind") == "Gem" then
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
		if rootOf(player) then
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
	for i, player in list do
		local lateral = (#list == 1) and 0 or (-9 + 18 * (i - 1) / (#list - 1))
		runs[player] = { dist = -10, juice = Config.JuiceStart, emptySince = 0, collected = {}, camps = 0 }
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
			if seg and root.Position.Y < PathService.floorY(seg) - Config.FallDepth then
				catch(player, "Fell")
				continue
			end
			if run.dist < paceDist then
				catch(player, "Caught by the Guardian")
				continue
			end
			-- Juice
			run.juice = math.max(0, run.juice - Config.JuiceDrainPerSecond * dt)
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
		if #alive ~= lastAliveCount then
			lastAliveCount = #alive
			workspace:SetAttribute("Alive", #alive)
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
			table.insert(order, { player = player, run = run })
		end
	end
	table.sort(order, function(a, b)
		return a.run.dist > b.run.dist
	end)
	for i, e in order do
		local m = metres(e.run.dist)
		local gems = math.floor(m * Config.GemsPerMetre)
		if i == 1 and #order > 1 then
			gems += Config.LastStandingGems
		end
		DataService.addGems(e.player, gems)
		DataService.submitDistance(e.player, m)
		notify(e.player, string.format("#%d  %d m  +%d gems", i, m, gems))
		task.spawn(DataService.save, e.player)
	end
	local top = order[1]
	if top then
		status(string.format("%s ran furthest: %d m", top.player.DisplayName, metres(top.run.dist)))
	end
	workspace:SetAttribute("Alive", 0)
	task.wait(5)
	for player, _ in runs do
		if player.Parent then
			resetPlayer(player)
		end
	end
	runs = {}
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
			while #Players:GetPlayers() < Config.MinPlayers do
				status("Waiting for players...")
				task.wait(1)
			end
			waitWithStatus(Config.IntermissionSeconds, "Next run in %d")
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
