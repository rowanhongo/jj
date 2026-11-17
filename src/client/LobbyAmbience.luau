--!strict
-- Lobby ambience: a soft jungle bed with drums layered a little louder, in the lobby only.
-- During a run the drums crossfade to the run track; the jungle bed keeps playing.
-- Also turns the default footsteps up (the Running sound Roblox puts on each character).

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local Settings = require(script.Parent.Settings)

local LobbyAmbience = {}

local LAYERS: { { id: string, volume: number, run: boolean?, always: boolean? } } = {
	{ id = "rbxassetid://158760787", volume = 0.2, always = true }, -- jungle bed, in the lobby and on runs
	{ id = "rbxassetid://1839999913", volume = 0.22 }, -- drums over it
	{ id = "rbxassetid://1839261127", volume = 0.22, run = true }, -- run music, same level as the drums
}

function LobbyAmbience.init()
	local player = Players.LocalPlayer
	local sounds: { Sound } = {}
	for i, l in LAYERS do
		local s = Instance.new("Sound")
		s.Name = "LobbyAmbience" .. i
		s.SoundId = l.id
		s.Looped = true
		s.Volume = 0
		Settings.asMusic(s)
		s.Parent = SoundService
		s:Play()
		table.insert(sounds, s)
	end
	local FOOTSTEP_VOLUME = 1.1 -- Roblox default is 0.65
	local function louderSteps(char: Model)
		local root = char:WaitForChild("HumanoidRootPart", 10)
		local snd = root and root:WaitForChild("Running", 10)
		if snd and snd:IsA("Sound") then
			snd.Volume = FOOTSTEP_VOLUME
			Settings.asSfx(snd)
		end
	end
	local function watch(p: Player)
		p.CharacterAdded:Connect(louderSteps)
		if p.Character then
			task.spawn(louderSteps, p.Character)
		end
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	local level = 0
	RunService.Heartbeat:Connect(function(dt)
		local want = player:GetAttribute("State") == "Running" and 0 or 1
		level += math.clamp(want - level, -dt / 1.5, dt / 1.5)
		for i, s in sounds do
			local l = LAYERS[i]
			s.Volume = l.volume * (l.always and 1 or l.run and 1 - level or level)
		end
	end)
end

return LobbyAmbience
