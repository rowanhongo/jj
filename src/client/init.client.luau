--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local Hud = require(script.Hud)
local Runner = require(script.Runner)
local Darts = require(script.Darts)
local Lobby = require(script.Lobby)
local Nametags = require(script.Nametags)
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local Sfx = require(script.Sfx)
local Haptics = require(script.Haptics)

local player = Players.LocalPlayer

-- Download the run map's meshes and textures while in the lobby, so the path doesn't pop in.
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("Assets", 20)
	if assets then
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ assets })
		end)
	end
end)

-- One typeface for the whole game: Builder Sans. Text made with Fredoka One / Gotham is
-- switched as it appears (in the screen GUIs and on the lobby boards).
do
	local heavy = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
	local bold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	local function swap(o: Instance)
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
			local f = (o :: TextLabel).Font
			if f == Enum.Font.FredokaOne then
				(o :: TextLabel).FontFace = heavy
			elseif f == Enum.Font.GothamBold or f == Enum.Font.GothamBlack then
				(o :: TextLabel).FontFace = bold
			end
		end
	end
	for _, root in { player:WaitForChild("PlayerGui"), workspace } do
		for _, o in root:GetDescendants() do
			swap(o)
		end
		root.DescendantAdded:Connect(function(o)
			swap(o)
			task.defer(swap, o)
		end)
	end
end

require(script.Settings).init()
Hud.init()
require(script.GoalReveal).init()
require(script.AbilityFx).init()
Runner.init()
require(script.BotSmooth).init()
Darts.init()
Lobby.init(function(t)
	Hud.toast(t)
end)
Nametags.init()
task.spawn(require(script.LobbyBoards).init)
task.spawn(require(script.LobbyBugs).init)
task.spawn(require(script.LobbyAmbience).init)

Runner.onStumble.Event:Connect(function(reason: string)
	Hud.flash(string.upper(reason) .. "!", Palette.UiDanger)
end)
Runner.onWarn.Event:Connect(function(text: string)
	Hud.flash(text, Palette.UiDanger)
end)
task.spawn(require(script.Tiger).init)
require(script.Tiger).onWarn.Event:Connect(function()
	Hud.flash("TIGER COMING!", Palette.UiDanger)
end)
task.spawn(require(script.GuardianGait).init)
task.spawn(require(script.WindFx).init)
task.spawn(Sfx.init)
Runner.onPickup.Event:Connect(function(kind: string)
	Sfx.play(kind == "Gem" and "Gem" or kind == "Box" and "Box" or "Drink")
	if kind == "Gem" then
		Hud.flash("+" .. Config.GemPickup .. (Config.GemPickup == 1 and " GEM" or " GEMS"), Palette.Gem)
	elseif kind == "Box" then
		Lobby.boxPop()
		Haptics.big()
	end
end)
-- every button gives a light tick on phones
task.spawn(Haptics.hookButtons, player:WaitForChild("PlayerGui"))
-- over the finish line: a cheer and a buzz (the server's "You made it" toast says the rest)
player:GetAttributeChangedSignal("State"):Connect(function()
	if player:GetAttribute("State") == "Finished" then
		Sfx.play("Win")
		Haptics.big()
		Hud.flash("YOU MADE IT!", Palette.JuiceGlow)
	end
end)
local BoxLook = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("BoxLook"))
-- ? boxes turn slowly and bob, drawn here only (the server's part stays put; pickups use
-- distance, so the small bob does not matter)
do
	local CollectionService = game:GetService("CollectionService")
	local boxes: { [BasePart]: CFrame } = {}
	local function add(p: Instance)
		if p:IsA("BasePart") and p:GetAttribute("Kind") == "Box" then
			boxes[p] = p.CFrame
		end
	end
	for _, p in CollectionService:GetTagged("Bottle") do
		add(p)
	end
	CollectionService:GetInstanceAddedSignal("Bottle"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Bottle"):Connect(function(p)
		boxes[p :: BasePart] = nil
	end)
	game:GetService("RunService").RenderStepped:Connect(function()
		local t = os.clock()
		for p, base in boxes do
			if not p.Parent then
				boxes[p] = nil
				continue
			end
			local ph = base.Position.X * 0.37 + base.Position.Z * 0.21 -- each box a little out of step
			p.CFrame = CFrame.new(base.Position + Vector3.new(0, 0.3 * math.sin(t * 2.2 + ph), 0))
				* CFrame.Angles(0, t * 1.6 + ph, 0)
				* CFrame.Angles(math.rad(12), 0, math.rad(12))
			-- faint rainbow glow: the light and the face edges drift through the colours
			local c = BoxLook.hue(t * 0.25 + ph * 0.1)
			for _, d in p:GetChildren() do
				if d:IsA("PointLight") then
					d.Color = c
				elseif d:IsA("SurfaceGui") then
					local face = d:FindFirstChild("BoxFace")
					local st = face and face:FindFirstChildOfClass("UIStroke")
					if st then
						st.Color = Palette.GemGlint:Lerp(c, 0.55)
					end
				end
			end
		end
	end)
end

-- Messages that arrive while you're on the death / results screen are dropped: the results
-- screen already shows the run, and replaying them all on return to the lobby buried the screen.
remotes.Notify.OnClientEvent:Connect(function(text: string)
	-- "<name>: fell / caught at N m" goes straight to the side feed; the toast queue would hold it back
	if
		string.find(text, ": fell at")
		or string.find(text, ": caught at")
		or string.find(text, " made it! (#", 1, true)
	then
		Hud.feed(text)
		return
	end
	if player:GetAttribute("State") == "Caught" then
		return
	end
	Hud.toast(text)
end)

local function rightOfLook(look: Vector3): Vector3
	return Vector3.new(-look.Z, 0, look.X).Unit
end

-- At the start line: a wide shot from in front of you looking back down the course, so you see
-- the Guardian waiting behind the pack, then it flies in to sit right behind you looking down the
-- course by RUN! (the player's own zoom, so the camera module carries on with no snap).
player:GetAttributeChangedSignal("State"):Connect(function()
	if player:GetAttribute("State") ~= "Countdown" then
		return
	end
	local t0 = os.clock()
	local HOLD, FLY = 1.5, 1.3 -- seconds on the wide shot, then the fly-in (countdown is 3 s)
	local cam0 = workspace.CurrentCamera
	local zoom = cam0 and math.clamp((cam0.CFrame.Position - cam0.Focus.Position).Magnitude, 10, 22) or 14
	local conn
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local cam = workspace.CurrentCamera
		local t = os.clock() - t0
		if t > HOLD + FLY or not root or not cam or player:GetAttribute("State") ~= "Countdown" then
			conn:Disconnect()
			return
		end
		local look = root.CFrame.LookVector
		local at = root.Position + Vector3.new(0, 2, 0)
		local back = (-look * math.cos(math.rad(25)) + Vector3.new(0, math.sin(math.rad(25)), 0)) * zoom
		local near = CFrame.lookAt(at + back, at)
		local g = workspace:FindFirstChild("Guardian")
		local gp = if g and g:IsA("Model") then g:GetPivot().Position else root.Position - look * 45
		-- wide: ahead of you and up, framing you in front and the Guardian's face behind
		local mid = (root.Position + gp) / 2 + Vector3.new(0, 8, 0)
		-- centred on the path and under the gate beam, so no wall pillar sits in the shot
		local line = workspace:GetAttribute("StartLine") -- path centre at the start (server)
		local centre = if typeof(line) == "Vector3"
			then rightOfLook(look) * -(root.Position - line):Dot(rightOfLook(look))
			else Vector3.zero
		local wide = CFrame.lookAt(root.Position + centre + look * 24 + Vector3.new(0, 11, 0), mid)
		local k = math.clamp((t - HOLD) / FLY, 0, 1)
		k = k * k * (3 - 2 * k)
		cam.CFrame = wide:Lerp(near, k)
		cam.Focus = CFrame.new(at)
	end)
end)

-- Caught: the death screen (stats, spectate, leave). Otherwise the camera follows you.
require(script.DeathScreen).init()
task.spawn(function()
	while true do
		task.wait(0.5)
		local cam = workspace.CurrentCamera
		local mine = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if player:GetAttribute("State") ~= "Caught" and mine and cam.CameraSubject ~= mine then
			cam.CameraSubject = mine
		end
	end
end)

-- the Guardian right behind you: a warning sound once each time it closes in
task.spawn(function()
	local close = false
	while true do
		task.wait(0.2)
		local myStuds = (player:GetAttribute("Distance") or 0) * 3.5
		local gap = myStuds - (workspace:GetAttribute("PaceDist") or 0)
		local now = player:GetAttribute("State") == "Running" and gap < 18
		if now and not close then
			Sfx.play("GuardianBehind")
		end
		close = now or (close and gap < 30)
	end
end)

print("[JJ] client ready")

-- The Guardian is always out there: a screech every 2-4 minutes of a run, even when it's far off.
task.spawn(function()
	while true do
		task.wait(math.random(120, 240))
		if player:GetAttribute("State") == "Running" then
			Sfx.play("GuardianBehind")
		end
	end
end)
