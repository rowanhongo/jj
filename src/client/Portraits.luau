--!strict
-- Race strip: every runner in this run as a tiny portrait on a track under the metres (top of the
-- screen), placed by distance between the back and the front of the field, so you see how close
-- the fight is, not just the order. Player's headshot (a bot: the headshot of the avatar it
-- wears) in the stone-and-gold square frame from the casings sheet. You: gold ring, a little
-- bigger, always drawn on top. Runners within NEAR_M of you show their name and the gap.
-- When a runner goes out their tile darkens, a red X cracks across it, and it stays where they
-- went out (the span is set by the runners still in, so knock-outs don't squash it).
-- Data: workspace.RunField (server/RoundService), one Configuration per runner; attribute M =
-- metres, updated 10 times a second.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))

local Portraits = {}

local CASINGS = "rbxassetid://126274240973137"
local FRAME = Rect.new(768, 253, 966, 450) -- the square stone/gold frame (sheet pixels, 1023x682)
local NEAR_M = 20 -- names show for runners this close to you
local MIN_SPAN = 40 -- metres: the strip never zooms in closer than this, so small gaps don't jitter

local player = Players.LocalPlayer
local row: Frame -- the strip, centred under the metres
local track: Frame -- tiles are placed along this
local tiles: { [Instance]: Frame } = {}
local shown: { [Instance]: number } = {} -- each tile's drawn x (0..1), eased toward its target
local thumbs: { [number]: string } = {}

local function size(): number
	local cam = workspace.CurrentCamera
	local w = cam and cam.ViewportSize.X or 1000
	return math.clamp(math.floor((w - 480) / 12) - 4, 22, 34)
end

local function stripWidth(): number
	local cam = workspace.CurrentCamera
	local w = cam and cam.ViewportSize.X or 1000
	return math.clamp(math.floor(w * 0.46), 240, 600)
end

local function crack(tile: Frame)
	local shade = tile:FindFirstChild("Shade") :: Frame
	shade.Visible = true
	for i, rot in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.Name = "X" .. i
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(0, 0, 0.14, 0)
		bar.Rotation = rot
		bar.BackgroundColor3 = Palette.UiDanger
		bar.BorderSizePixel = 0
		bar.ZIndex = 6
		local s = Instance.new("UIStroke")
		s.Color = Palette.UiRim
		s.Thickness = 1
		s.Parent = bar
		bar.Parent = tile
		TweenService:Create(bar, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = UDim2.new(1.15, 0, 0.14, 0) })
			:Play()
	end
	-- a little knock as it cracks (a wobble: the strip owns the tile's position)
	tile.Rotation = -12
	TweenService:Create(tile, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), { Rotation = 0 }):Play()
end

local function build(e: Instance, s: number)
	local tile = Instance.new("Frame")
	tile.Name = e.Name
	tile.BackgroundTransparency = 1
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.new(0, 0, 0.5, 0)
	tile.Size = UDim2.fromOffset(s, s)
	local uid = e:GetAttribute("UserId") :: number
	local name = e:GetAttribute("Runner") :: string
	-- players: their headshot; bots: the headshot of the avatar they wear (LookId)
	local look = (uid and uid > 0) and uid or (e:GetAttribute("LookId") :: number?)
	local img = Instance.new("ImageLabel")
	img.Name = "Face"
	img.BackgroundColor3 = Palette.UiPanel
	img.Size = UDim2.fromScale(0.72, 0.72)
	img.Position = UDim2.fromScale(0.14, 0.14)
	img.ZIndex = 2
	img.Parent = tile
	if look and look > 0 then
		task.spawn(function()
			if not thumbs[look] then
				local ok, url = pcall(function()
					return Players:GetUserThumbnailAsync(
						look,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size48x48
					)
				end)
				thumbs[look] = ok and url or ""
			end
			img.Image = thumbs[look]
		end)
	end
	local frame = Instance.new("ImageLabel")
	frame.BackgroundTransparency = 1
	frame.Image = CASINGS
	frame.ImageRectOffset = FRAME.Min
	frame.ImageRectSize = FRAME.Max - FRAME.Min
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 3
	frame.Parent = tile
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BackgroundColor3 = Palette.UiRim
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(0.72, 0.72)
	shade.Position = UDim2.fromScale(0.14, 0.14)
	shade.ZIndex = 4
	shade.Visible = false
	shade.Parent = tile
	-- you: a gold ring and a slightly bigger tile
	local mine = uid == player.UserId
	if mine then
		local st = Instance.new("UIStroke")
		st.Color = Palette.UiGold
		st.Thickness = 2
		st.Parent = img
		local big = math.floor(s * 1.25)
		tile.Size = UDim2.fromOffset(big, big)
	end
	tile:SetAttribute("Mine", mine)
	-- name (and gap) under the face, only for runners near you
	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	tag.BackgroundTransparency = 1
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 1, 0)
	tag.Size = UDim2.fromOffset(110, 14)
	tag.Font = Enum.Font.FredokaOne
	tag.TextSize = 13
	tag.TextColor3 = mine and Palette.UiGold or Palette.UiText
	tag.Text = mine and "YOU" or (name or "")
	tag.Visible = mine
	tag.ZIndex = 5
	local ts = Instance.new("UIStroke")
	ts.Color = Palette.UiRim
	ts.Thickness = 1.5
	ts.Parent = tag
	tag.Parent = tile
	tile.Parent = track
	tiles[e] = tile
	if e:GetAttribute("Out") then
		crack(tile)
	end
	e:GetAttributeChangedSignal("Out"):Connect(function()
		if e:GetAttribute("Out") and tiles[e] and not tiles[e]:FindFirstChild("X1") then
			crack(tiles[e])
		end
	end)
end

-- Place every tile along the track by its runner's metres.
local function place(dt: number)
	local lo, hi = math.huge, -math.huge
	local myM: number? = nil
	for e, tile in tiles do
		local m = e:GetAttribute("M") or 0
		if not e:GetAttribute("Out") then
			lo = math.min(lo, m)
			hi = math.max(hi, m)
		end
		if tile:GetAttribute("Mine") then
			myM = m
		end
	end
	if lo == math.huge then
		return
	end
	if hi - lo < MIN_SPAN then
		local mid = (hi + lo) / 2
		lo, hi = mid - MIN_SPAN / 2, mid + MIN_SPAN / 2
	end
	local k = 1 - math.exp(-8 * dt)
	for e, tile in tiles do
		local m = e:GetAttribute("M") or 0
		local x = math.clamp((m - lo) / (hi - lo), 0, 1)
		local cur = shown[e] or x
		cur += (x - cur) * k
		shown[e] = cur
		tile.Position = UDim2.new(cur, 0, 0.5, 0)
		local out = e:GetAttribute("Out") == true
		local mine = tile:GetAttribute("Mine") == true
		-- draw order: you on top, then runners in front over those behind; out runners lowest
		tile.ZIndex = mine and 1000 or (out and 1 or 10 + math.floor(x * 500))
		local tag = tile:FindFirstChild("Tag") :: TextLabel?
		if tag and not mine then
			local near = not out and myM ~= nil and math.abs(m - myM) <= NEAR_M
			tag.Visible = near
			if near then
				tag.Text = string.format("%s %+dm", e:GetAttribute("Runner") or "", m - (myM :: number))
			end
		end
	end
end

local function rebuild()
	for _, t in tiles do
		t:Destroy()
	end
	tiles = {}
	shown = {}
	local f = workspace:FindFirstChild("RunField")
	if not f then
		return
	end
	local s = size()
	row.Size = UDim2.fromOffset(stripWidth(), s + 16)
	for _, e in f:GetChildren() do
		build(e, s)
	end
end

function Portraits.init(gui: ScreenGui, y: number)
	local s = size()
	row = Instance.new("Frame")
	row.Name = "Portraits"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, y)
	row.Size = UDim2.fromOffset(stripWidth(), s + 16)
	row.Parent = gui
	-- the track: a dark groove with gold end caps; the back of the field left, the front right
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, 0, 0, s / 2 + 2)
	line.Size = UDim2.new(1, 0, 0, 6)
	line.BackgroundColor3 = Palette.UiInk
	line.BackgroundTransparency = 0.25
	line.BorderSizePixel = 0
	line.Parent = row
	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(1, 0)
	lc.Parent = line
	local ls = Instance.new("UIStroke")
	ls.Color = Palette.UiRim
	ls.Thickness = 1.5
	ls.Parent = line
	for _, side in { 0, 1 } do
		local cap = Instance.new("Frame")
		cap.AnchorPoint = Vector2.new(0.5, 0.5)
		cap.Position = UDim2.new(side, 0, 0.5, 0)
		cap.Size = UDim2.fromOffset(4, 14)
		cap.BackgroundColor3 = Palette.UiGold
		cap.BorderSizePixel = 0
		cap.Parent = line
	end
	track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.Position = UDim2.new(0, 0, 0, 2)
	track.Size = UDim2.new(1, 0, 0, s)
	track.Parent = row
	local watched: Instance? = nil
	local function watch()
		local f = workspace:FindFirstChild("RunField")
		if f == watched then
			return
		end
		watched = f
		if f then
			f.ChildAdded:Connect(function()
				task.defer(rebuild)
			end)
			f.ChildRemoved:Connect(function()
				task.defer(rebuild)
			end)
		end
		rebuild()
	end
	workspace.ChildAdded:Connect(function(c)
		if c.Name == "RunField" then
			watch()
		end
	end)
	watch()
	-- only shown while you are in a run (running, or on the death / winner screen)
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		local st = player:GetAttribute("State")
		row.Visible = st == "Running" or st == "Countdown" or st == "Caught" or st == "Finished"
		if row.Visible then
			place(dt)
		end
	end)
end

return Portraits
