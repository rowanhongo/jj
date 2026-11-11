--!strict
-- Small tag above every player's head: their title, then the showcased mode's icon and best metres.
-- Reads replicated attributes (Title, Showcase, ShowcaseBest). Hidden while you are running.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)
local Items = require(Shared.Items)

local me = Players.LocalPlayer
local Nametags = {}

local tags: { [Player]: BillboardGui } = {}

local function icon(mode: string): string
	for _, m in Items.Modes do
		if m.id == mode then
			return m.icon
		end
	end
	return "🏃"
end

local function build(p: Player): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "JJTag"
	bb.Size = UDim2.fromOffset(160, 44)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 90
	bb.ResetOnSpawn = false
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Palette.UiGold
	title.Parent = bb
	local best = Instance.new("TextLabel")
	best.Name = "Best"
	best.BackgroundTransparency = 1
	best.Size = UDim2.new(1, 0, 0, 24)
	best.Position = UDim2.fromOffset(0, 16)
	best.Font = Enum.Font.FredokaOne
	best.TextSize = 18
	best.TextColor3 = Palette.UiText
	best.Parent = bb
	for _, l in { title, best } do
		local s = Instance.new("UIStroke")
		s.Color = Palette.UiRim
		s.Thickness = 1.5
		s.Parent = l
	end
	bb.Parent = me:WaitForChild("PlayerGui")
	return bb
end

function Nametags.init()
	Players.PlayerRemoving:Connect(function(p)
		if tags[p] then
			tags[p]:Destroy()
			tags[p] = nil
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local hideAll = me:GetAttribute("State") == "Running"
		for _, p in Players:GetPlayers() do
			local bb = tags[p] or build(p)
			tags[p] = bb
			local head = p.Character and p.Character:FindFirstChild("Head")
			bb.Adornee = head
			bb.Enabled = head ~= nil and not hideAll
			local t = p:GetAttribute("Title") or "";
			(bb :: any).Title.Text = t
			local b = p:GetAttribute("ShowcaseBest") or 0;
			(bb :: any).Best.Text = string.format("%s %s m", icon(p:GetAttribute("Showcase") or "Stampede"), b > 0 and tostring(b) or "—")
		end
	end)
end

return Nametags
