--!strict
-- Sound effects. Everything the game plays outside the music beds goes through here, so the ids
-- and levels live in one table. play() is for sounds on your own screen; at() places a sound in
-- the world (other runners being taken down). UI clicks are hooked once for every button.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Settings = require(script.Parent.Settings)

local Sfx = {}

type Def = { id: string, volume: number, start: number?, length: number? }
local DEFS: { [string]: Def } = {
	Gem = { id = "rbxassetid://116120982042508", volume = 1.4 },
	Box = { id = "rbxassetid://110626067438129", volume = 2 }, -- power-up pickup
	Drink = { id = "rbxassetid://133347729618467", volume = 1.1 },
	Start = { id = "rbxassetid://116907230256274", volume = 1, start = 0.1 },
	Menu = { id = "rbxassetid://6874964659", volume = 0.9, start = 0.1 },
	Click = { id = "rbxassetid://116090250127536", volume = 0.9, start = 0.1 },
	Death = { id = "rbxassetid://140695149439373", volume = 3 },
	GuardianCatch = { id = "rbxassetid://107499797127175", volume = 1.3, start = 0, length = 1.5 },
	GuardianBehind = { id = "rbxassetid://74185022698539", volume = 1.2 },
	Zip = { id = "rbxassetid://107348141479601", volume = 1.2, start = 0.3 }, -- stopped when you let go
	Vine = { id = "rbxassetid://132176641904643", volume = 6 }, -- a soft recording: turned well up
	WallHit = { id = "rbxassetid://9113518407", volume = 2.6 },
	Countdown = { id = "rbxassetid://80041193116570", volume = 1.2 }, -- drum beats at 0, 1, 2, 3 s
	Go = { id = "rbxassetid://127613720380706", volume = 1.2 },
	Win = { id = "rbxassetid://128418686371809", volume = 1.2 },
	Jump = { id = "rbxassetid://110701912642979", volume = 2 },
	Slide = { id = "rbxassetid://134781979035978", volume = 2.2 },
	Gadget = { id = "rbxassetid://127488139302452", volume = 1.5 }, -- using an ability slot
}

-- A runner going down: one of these screams at random, played on your own speakers (not left at
-- the spot, which you run away from) and to its full length.
-- start skips each recording's silent lead-in
local SCREAMS: { { id: string, start: number } } = {
	{ id = "rbxassetid://127504800716656", start = 0 },
	{ id = "rbxassetid://103086623976469", start = 0.5 },
	{ id = "rbxassetid://6999993863", start = 0.5 },
	{ id = "rbxassetid://5303371139", start = 0.5 },
	{ id = "rbxassetid://18852484906", start = 0.5 },
}
local lastScream = 0
local screams: { Sound } = {}
local hushUntil = 0

-- The win sound plays alone: stop every scream and hold new ones off for a few seconds.
function Sfx.hushScreams(seconds: number?)
	hushUntil = os.clock() + (seconds or 6)
	for _, s in screams do
		if s.Parent then
			s:Stop()
			s:Destroy()
		end
	end
	table.clear(screams)
end

local function make(def: Def, parent: Instance): Sound
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = def.volume
	Settings.asSfx(s)
	s.TimePosition = def.start or 0
	s.Parent = parent
	return s
end

local function finish(s: Sound, def: Def)
	s:Play()
	if def.start then
		s.TimePosition = def.start -- skip the silent lead-in
	end
	if def.length then
		task.delay(def.length, function()
			s:Stop()
			s:Destroy()
		end)
	else
		s.Ended:Once(function()
			s:Destroy()
		end)
		Debris:AddItem(s, 30)
	end
end

function Sfx.play(name: string): Sound?
	local def = DEFS[name]
	if not def then
		return nil
	end
	local s = make(def, SoundService)
	finish(s, def)
	return s
end

function Sfx.playDef(def: Def): Sound
	local s = make(def, SoundService)
	finish(s, def)
	return s
end

-- A sound in the world at `pos` (heard louder close by).
function Sfx.at(name: string, pos: Vector3)
	local def = DEFS[name]
	if not def then
		return
	end
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.one
	a.Position = pos
	a.Parent = workspace
	local s = make(def, a)
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 400
	finish(s, def)
	Debris:AddItem(a, (def.length or 6) + 1)
end

-- Button sounds: opening/closing a menu and the PLAY button call Sfx.menu()/Sfx.start() from
-- their own handlers; every other button press gets the plain click.
local lastSpecial = 0
function Sfx.menu()
	lastSpecial = os.clock()
	Sfx.play("Menu")
end
function Sfx.start()
	lastSpecial = os.clock()
	Sfx.play("Start")
end

local function hook(b: Instance)
	if b:IsA("GuiButton") then
		b.Activated:Connect(function()
			task.defer(function()
				if os.clock() - lastSpecial > 0.05 then
					Sfx.play("Click")
				end
			end)
		end)
	end
end

function Sfx.init()
	local player = Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")
	for _, d in pg:GetDescendants() do
		hook(d)
	end
	pg.DescendantAdded:Connect(hook)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ev = remotes:WaitForChild("Sfx") :: RemoteEvent
	ev.OnClientEvent:Connect(function(name: string, pos: Vector3)
		if name ~= "Takedown" then
			Sfx.at(name, pos)
		end
		if os.clock() < hushUntil then
			return
		end
		local pick = math.random(#SCREAMS - 1)
		if pick >= lastScream then
			pick += 1 -- never the same scream twice in a row
		end
		lastScream = pick
		local snd = Sfx.playDef({ id = SCREAMS[pick].id, start = SCREAMS[pick].start, volume = 1.3 })
		for i = #screams, 1, -1 do
			if not screams[i].Parent then
				table.remove(screams, i)
			end
		end
		table.insert(screams, snd)
	end)
	-- countdown drums from the first beat (0 s) so they land on 3, 2, 1 and GO; then the GO sting
	player:GetAttributeChangedSignal("State"):Connect(function()
		local st = player:GetAttribute("State")
		if st == "Countdown" then
			Sfx.play("Countdown")
		elseif st == "Running" then
			Sfx.play("Go")
		end
	end)
end

return Sfx
