--!strict
-- The goal reveal before each run: "SURVIVE" stamps in, the distance rolls up like a slot
-- machine with ticks and lands with a punch and a shine, a tag says how long the run is, then
-- the card shrinks up into the distance counter at the top. Fired by workspace.GoalRoll (the
-- server waits Config.GoalRevealSeconds for it before the drum countdown). Palette colours only.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local GoalReveal = {}

local function tween(
	o: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	local tw =
		TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function text(parent: Instance, t: string, h: number, y: number, color: Color3, stroke: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, y)
	l.Size = UDim2.new(1, 0, h, 0)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = t
	l.TextColor3 = color
	local s = Instance.new("UIStroke")
	s.Color = Palette.UiRim
	s.Thickness = stroke
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	l.Parent = parent
	return l
end

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local busy = 0
local function play(goal: number)
	busy += 1
	local my = busy
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("GoalReveal")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GoalReveal"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 20
	gui.ResetOnSpawn = false
	gui.Parent = pg

	-- dim the world a little so the card owns the screen
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Palette.UiInk
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = gui
	tween(dim, 0.3, { BackgroundTransparency = 0.75 })

	local vp = workspace.CurrentCamera.ViewportSize
	local w = math.min(560, vp.X * 0.8)
	local card = Instance.new("Frame")
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.42)
	card.Size = UDim2.fromOffset(w, w * 0.5)
	card.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = card
	card.Rotation = -3 -- a slight tilt: a stamped banner, not a centred dialog

	-- a hard-edged ink banner across the whole screen, gold rails top and bottom, slides in
	local band = Instance.new("Frame")
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.new(0, vp.X * 1.6, 1.12, 0)
	band.BackgroundColor3 = Palette.UiInk
	band.BorderSizePixel = 0
	band.ZIndex = 0
	band.Parent = card
	for _, y in { 0, 1 } do
		local rail = Instance.new("Frame")
		rail.AnchorPoint = Vector2.new(0, y)
		rail.Position = UDim2.fromScale(0, y)
		rail.Size = UDim2.new(1, 0, 0, 6)
		rail.BackgroundColor3 = Palette.UiGold
		rail.BorderSizePixel = 0
		rail.Parent = band
	end
	local bandScale = Instance.new("UIScale")
	bandScale.Scale = 0
	bandScale.Parent = band
	tween(bandScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)

	-- a soft gold burst behind the number
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.52)
	glow.Size = UDim2.fromScale(0.2, 0.2)
	glow.BackgroundColor3 = Palette.JuiceGlow
	glow.BackgroundTransparency = 1
	glow.Visible = false
	glow.BorderSizePixel = 0
	glow.Parent = card
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(1, 0)
	gc.Parent = glow
	local gg = Instance.new("UIGradient")
	gg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.6, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	gg.Parent = glow

	local survive = text(card, "SURVIVE", 0.22, 0.12, Palette.UiText, 4)
	survive.TextTransparency = 1
	local sScale = Instance.new("UIScale")
	sScale.Scale = 2.2
	sScale.Parent = survive

	local shadow = text(card, "0", 0.5, 0.52, Palette.UiInk, 6)
	shadow.Position = UDim2.new(0.5, 5, 0.52, 7)
	shadow.TextTransparency = 1
	local num = text(card, "0", 0.5, 0.52, Palette.UiGold, 6)
	num.TextTransparency = 1
	local nScale = Instance.new("UIScale")
	nScale.Parent = num

	local unit = text(card, "METRES", 0.16, 0.86, Palette.UiText, 3)
	unit.TextTransparency = 1

	local tagText, tagColor
	if goal >= 1700 then
		tagText, tagColor = "MARATHON!", Palette.Mythic
	elseif goal >= 1300 then
		tagText, tagColor = "LONG RUN", Palette.Epic
	else
		tagText, tagColor = "SPRINT", Palette.Uncommon
	end
	local tag = Instance.new("Frame")
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Position = UDim2.fromScale(0.5, 1.08)
	tag.Size = UDim2.fromScale(0.36, 0.14)
	tag.BackgroundColor3 = tagColor
	tag.BackgroundTransparency = 1
	tag.BorderSizePixel = 0
	tag.Parent = card
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = tag
	local ts = Instance.new("UIStroke")
	ts.Color = Palette.UiRim
	ts.Thickness = 3
	ts.Transparency = 1
	ts.Parent = tag
	local tl = text(tag, tagText, 0.72, 0.5, Palette.UiText, 2)
	tl.Size = UDim2.fromScale(0.86, 0.72)
	tl.TextTransparency = 1
	local tScale = Instance.new("UIScale")
	tScale.Scale = 0
	tScale.Parent = tag

	-- 1. SURVIVE stamps down
	Sfx.play("Menu")
	tween(survive, 0.18, { TextTransparency = 0 })
	tween(sScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	task.wait(0.3)

	-- 2. the number rolls up, fast then slowing, ticking as it goes
	num.TextTransparency = 0
	shadow.TextTransparency = 0
	unit.TextTransparency = 0
	local rollT = 1.25
	local t0 = os.clock()
	local lastTick = -1
	while os.clock() - t0 < rollT and busy == my do
		local k = (os.clock() - t0) / rollT
		local eased = 1 - (1 - k) ^ 3
		local v = math.floor(goal * eased / 10) * 10
		num.Text = fmt(v)
		shadow.Text = num.Text
		local tick = math.floor(v / 100)
		if tick ~= lastTick then
			lastTick = tick
			if k < 0.9 then
				Sfx.play("Click")
			end
			nScale.Scale = 1.06
			tween(nScale, 0.06, { Scale = 1 })
		end
		RunService.RenderStepped:Wait()
	end
	if busy ~= my then
		return
	end
	num.Text = fmt(goal)
	shadow.Text = num.Text

	-- 3. lands: punch, burst, shine, tag pops
	Sfx.play("Box")
	nScale.Scale = 1.45
	tween(nScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	glow.BackgroundTransparency = 0
	glow.Size = UDim2.fromScale(0.3, 0.6)
	tween(glow, 0.6, { Size = UDim2.fromScale(1.5, 2.2), BackgroundTransparency = 1 })
	-- a screen shake on the landing instead of a glossy sweep
	local base = card.Position
	task.spawn(function()
		for k = 1, 6 do
			local m = (7 - k) * 2
			card.Position = base + UDim2.fromOffset(math.random(-m, m), math.random(-m, m))
			task.wait(0.025)
		end
		card.Position = base
	end)
	task.wait(0.12)
	tween(tScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(tag, 0.15, { BackgroundTransparency = 0 })
	tween(ts, 0.15, { Transparency = 0 })
	tween(tl, 0.15, { TextTransparency = 0 })

	-- 4. hold, then fly up into the distance counter
	task.wait(1.05)
	if busy ~= my then
		return
	end
	tween(dim, 0.35, { BackgroundTransparency = 1 })
	local top = 22 / vp.Y
	tween(card, 0.42, { Position = UDim2.fromScale(0.5, top) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(scale, 0.42, { Scale = 0.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.42)
	gui:Destroy()
end

function GoalReveal.init()
	workspace:GetAttributeChangedSignal("GoalRoll"):Connect(function()
		local goal = workspace:GetAttribute("GoalM")
		local st = player:GetAttribute("State")
		-- only for runners waiting on the line (not lobby players or spectators)
		if goal and (st == "Countdown" or st == "Running") then
			task.spawn(play, goal)
		end
	end)
end

return GoalReveal
