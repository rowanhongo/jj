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

local player = Players.LocalPlayer

Hud.init()
Runner.init()
Darts.init()
Lobby.init(function(t) Hud.toast(t) end)
Nametags.init()

Runner.onStumble.Event:Connect(function(reason: string)
	Hud.flash(string.upper(reason) .. "!", Palette.UiDanger)
end)
Runner.onShield.Event:Connect(function()
	Hud.flash("SHIELD!", Palette.Shield)
end)
Runner.onPickup.Event:Connect(function(kind: string)
	if kind == "Gem" then
		Hud.flash("+3 GEMS", Palette.Gem)
	elseif kind == "Box" then
		Hud.flash("GADGET!", Palette.UiGold)
	end
end)
remotes.Notify.OnClientEvent:Connect(function(text: string)
	Hud.toast(text)
end)

-- Ghost spectating: once caught, the default camera follows the furthest runner.
task.spawn(function()
	while true do
		task.wait(0.5)
		local cam = workspace.CurrentCamera
		local mine = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if player:GetAttribute("State") == "Caught" then
			local best, bestD = nil, -1
			for _, p in Players:GetPlayers() do
				if p ~= player and p:GetAttribute("State") == "Running" then
					local d = p:GetAttribute("Distance") or 0
					local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
					if h and d > bestD then
						best, bestD = h, d
					end
				end
			end
			if best and cam.CameraSubject ~= best then
				cam.CameraSubject = best
			end
		elseif mine and cam.CameraSubject ~= mine then
			cam.CameraSubject = mine
		end
	end
end)

print("[JJ] client ready")
