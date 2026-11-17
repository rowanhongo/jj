--!strict
-- Blowdart: F or the touch "Dart" button. It auto-targets the running player nearest to
-- where the camera looks (within range). The server validates and applies drain + slow;
-- every client draws the dart.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local Darts = {}

local function rootOf(p: Player): BasePart?
	local c = p.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function pickTarget(): Player?
	local me = rootOf(player)
	local cam = workspace.CurrentCamera
	if not me or not cam then
		return nil
	end
	local best, bestScore = nil, -math.huge
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("State") == "Running" then
			local r = rootOf(p)
			if r then
				local off = r.Position - me.Position
				local d = off.Magnitude
				if d <= Config.DartRange then
					local facing = cam.CFrame.LookVector:Dot(off.Unit)
					local score = facing * 2 - d / Config.DartRange
					if score > bestScore then
						best, bestScore = p, score
					end
				end
			end
		end
	end
	return best
end

local function fire()
	if player:GetAttribute("State") ~= "Running" then
		return
	end
	if workspace:GetServerTimeNow() < (player:GetAttribute("DartReadyAt") or 0) then
		return
	end
	local target = pickTarget()
	if target then
		remotes.Dart:FireServer(target)
	end
end

local function drawDart(from: Player, to: Player)
	local a, b = rootOf(from), rootOf(to)
	if not a or not b then
		return
	end
	local dart = Instance.new("Part")
	dart.Anchored = true
	dart.CanCollide = false
	dart.CanQuery = false
	dart.CanTouch = false
	dart.Size = Vector3.new(0.3, 0.3, 2.2)
	dart.Color = Palette.Dart
	dart.Material = Enum.Material.Neon
	dart.CFrame = CFrame.lookAt(a.Position + Vector3.new(0, 1.5, 0), b.Position)
	dart.Parent = workspace
	local tw = TweenService:Create(
		dart,
		TweenInfo.new(0.18, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(b.Position, b.Position + (b.Position - a.Position)) }
	)
	tw:Play()
	tw.Completed:Connect(function()
		dart:Destroy()
	end)
end

function Darts.init()
	ContextActionService:BindAction("JJDart", function(_, state)
		if state == Enum.UserInputState.Begin then
			fire()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	remotes.DartFx.OnClientEvent:Connect(drawDart)
end

return Darts
