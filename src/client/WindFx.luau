--!strict
-- What a wind gust looks like (Segments.wind; the push itself is in Runner). While you are near a
-- windy stretch, pale streaks and a few leaves sweep across the path toward the open edge, in
-- gusts that swell and ease like the push does. Drawn locally, so only near you.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Settings = require(script.Parent.Settings)

local WindFx = {}

local STREAK = Color3.fromRGB(245, 250, 255)
local LEAF = { Color3.fromRGB(96, 168, 70), Color3.fromRGB(150, 190, 70), Color3.fromRGB(196, 170, 70) }
local NEAR = 140 -- studs: draw only while the zone is this close
local SPEED = 70 -- studs/s across the path

type Flyer = { part: BasePart, from: Vector3, vel: Vector3, born: number, life: number, leaf: boolean }
local flyers: { Flyer } = {}
local folder: Folder

local function spawnFlyer(zone: BasePart, leaf: boolean)
	local side = zone:GetAttribute("Side") :: number
	local right = zone:GetAttribute("Right") :: Vector3
	if not side or not right then
		return
	end
	local across = right * side -- toward the open edge
	local along = Vector3.yAxis:Cross(right) -- path direction (either way is fine)
	local half = zone.Size.X / 2
	local len = zone.Size.Z
	local start = zone.Position
		- across * (half + 4)
		+ along * (math.random() - 0.5) * len
		+ Vector3.new(0, math.random() * 7 - 3.5, 0)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if leaf then
		p.Size = Vector3.new(0.5, 0.08, 0.35)
		p.Color = LEAF[math.random(1, #LEAF)]
		p.Material = Enum.Material.SmoothPlastic
	else
		p.Size = Vector3.new(0.2, 0.2, 5 + math.random() * 5)
		p.Color = STREAK
		p.Material = Enum.Material.Neon
		p.Transparency = 1
	end
	p.Parent = folder
	local speed = SPEED * (leaf and 0.6 or 1) * (0.85 + math.random() * 0.3)
	table.insert(flyers, {
		part = p,
		from = start,
		vel = across * speed,
		born = os.clock(),
		life = (zone.Size.X + 16) / speed,
		leaf = leaf,
	})
end

function WindFx.init()
	folder = Instance.new("Folder")
	folder.Name = "WindFx"
	folder.Parent = workspace
	local player = Players.LocalPlayer
	local acc = 0
	-- the gust sound: looped, swelling in while you are in a windy stretch
	local gustS = Instance.new("Sound")
	gustS.SoundId = "rbxassetid://224339308"
	gustS.Looped = true
	gustS.Volume = 0
	Settings.asSfx(gustS)
	gustS.Parent = game:GetService("SoundService")
	local gustV = 0
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		-- move and fade what is in the air
		for i = #flyers, 1, -1 do
			local f = flyers[i]
			local u = (t - f.born) / f.life
			if u >= 1 or not f.part.Parent then
				f.part:Destroy()
				table.remove(flyers, i)
				continue
			end
			local pos = f.from + f.vel * (t - f.born)
			if f.leaf then
				pos += Vector3.new(0, math.sin(u * 9 + f.born) * 0.8, 0)
				f.part.CFrame = CFrame.new(pos) * CFrame.Angles(t * 7 + f.born, t * 5, 0)
			else
				f.part.CFrame = CFrame.lookAt(pos, pos + f.vel)
				f.part.Transparency = 0.35 + 0.65 * math.abs(u * 2 - 1) ^ 2
			end
		end
		-- spawn near windy stretches; the gust strength matches the push in Runner
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local gust = 0.75 + 0.3 * math.sin(t * 2.6)
		local inWind = false
		for _, zone in CollectionService:GetTagged("Wind") do
			if zone:IsA("BasePart") then
				local d = zone.CFrame:PointToObjectSpace(root.Position)
				if math.abs(d.Z) < zone.Size.Z / 2 + 6 and math.abs(d.X) < zone.Size.X / 2 + 6 then
					inWind = true
				end
			end
		end
		gustV += ((inWind and 1.6 * gust or 0) - gustV) * math.min(1, dt * 4)
		gustS.Volume = gustV
		if gustV > 0.02 and not gustS.IsPlaying then
			gustS:Play()
		elseif gustV <= 0.02 and gustS.IsPlaying then
			gustS:Stop()
		end
		acc += dt * gust
		local n = math.floor(acc / 0.012)
		if n <= 0 then
			return
		end
		acc -= n * 0.012
		for _, zone in CollectionService:GetTagged("Wind") do
			if zone:IsA("BasePart") and (zone.Position - root.Position).Magnitude < NEAR + zone.Size.Z / 2 then
				-- low effects: a third of the streaks and no leaves (the streaks still show the push)
				local low = Settings.get("LowFx")
				for _ = 1, low and math.ceil(n / 3) or n do
					spawnFlyer(zone, not low and math.random() < 0.15)
				end
			end
		end
	end)
end

return WindFx
