--!strict
-- "You died" screen. When the server catches you it sends this run's stats (Remotes.Died).
-- SPECTATE hides the card and follows the runners still going (< > to switch);
-- LEAVE MATCH puts you back in the lobby straight away. No revives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Sfx = require(script.Parent.Sfx)
local DeathScreen = {}

local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local function stroke(o: Instance, c: Color3, th: number)
	local s = Instance.new("UIStroke")
	s.Color = c
	s.Thickness = th
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
end

local function text(parent: Instance, t: string, size: number, color: Color3, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = color
	l.Text = t
	local s = Instance.new("UIStroke")
	s.Color = Palette.UiRim
	s.Thickness = 2
	s.Parent = l
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, t: string, color: Color3, pos: UDim2, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color
	b.FontFace = FONT
	b.TextSize = 24
	b.TextColor3 = Palette.UiText
	b.Text = t
	b.AutoButtonColor = true
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	stroke(b, Palette.UiRim, 3)
	-- same jungle skin as the lobby buttons: light at the top, shade at the foot
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	g.Rotation = 90
	g.Parent = b
	local ts = Instance.new("UIStroke")
	ts.Color = Palette.UiRim
	ts.Thickness = 2
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.Parent = b
	b.Parent = parent
	return b
end

-- the humanoids still running (players first, then bots), furthest first
local function targets(): { Humanoid }
	local list: { { h: Humanoid, d: number } } = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("State") == "Running" then
			local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if h then
				table.insert(list, { h = h, d = p:GetAttribute("Distance") or 0 })
			end
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, m in bots:GetChildren() do
			local h = m:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 and m.Parent then
				table.insert(list, { h = h, d = -1 })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d > b.d
	end)
	local out = {}
	for _, e in list do
		table.insert(out, e.h)
	end
	return out
end

function DeathScreen.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JJDeath"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.7
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(380, 460)
	card.BackgroundTransparency = 1
	-- parchment in a lashed wood frame (casings sheet), like the lobby menus
	local frameImg = Instance.new("ImageLabel")
	frameImg.BackgroundTransparency = 1
	frameImg.Image = "rbxassetid://126274240973137"
	frameImg.ImageRectOffset = Vector2.new(7, 208)
	frameImg.ImageRectSize = Vector2.new(262, 325)
	frameImg.ScaleType = Enum.ScaleType.Slice
	frameImg.SliceCenter = Rect.new(56, 52, 206, 276)
	frameImg.SliceScale = 0.75
	frameImg.Size = UDim2.new(1, 56, 1, 56)
	frameImg.Position = UDim2.fromOffset(-28, -28)
	frameImg.ZIndex = 0
	frameImg.Parent = card
	-- light paper under the parchment so the card reads bright, like the lobby menus
	local paper = Instance.new("Frame")
	paper.BackgroundColor3 = Palette.UiPaper
	paper.BackgroundTransparency = 0.02
	paper.BorderSizePixel = 0
	paper.Size = UDim2.new(1, -20, 1, -20)
	paper.Position = UDim2.fromOffset(10, 10)
	paper.ZIndex = -1
	paper.Parent = card
	frameImg.ImageTransparency = 0
	-- the title sits on a green banner across the top rail
	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -6)
	banner.Size = UDim2.new(1, -40, 0, 64)
	-- a title, not a box: big lettering on the parchment with a thin leaf-green rule under it
	banner.BackgroundTransparency = 1
	banner.Parent = card
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = Palette.CanopyMid
	rule.BorderSizePixel = 0
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 1, 0)
	rule.Size = UDim2.new(0.7, 0, 0, 3)
	Instance.new("UICorner", rule).CornerRadius = UDim.new(1, 0)
	rule.Parent = banner
	local sc = Instance.new("UISizeConstraint")
	sc.MaxSize = Vector2.new(380, 460)
	sc.Parent = card
	local scale = Instance.new("UIScale")
	scale.Parent = card
	card.Parent = dim

	local titleL = text(
		banner,
		"YOU DIED",
		42,
		Palette.UiDanger,
		{ Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) }
	)
	local reasonL = text(card, "", 20, Palette.CanopyDeep, {
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 64),
	})
	reasonL:FindFirstChildOfClass("UIStroke"):Destroy()

	local rows: { TextLabel } = {}
	local names = { "Distance", "Place", "Position bonus", "Gems earned", "Juice cans", "Time" }
	for i, n in names do
		local y = 96 + (i - 1) * 34
		-- a table: each stat its own row, every other row tinted
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Palette.UiInk
		row.BackgroundTransparency = i % 2 == 1 and 0.9 or 0.96
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -36, 0, 32)
		row.Position = UDim2.fromOffset(18, y)
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
		row.Parent = card
		local nameL = text(row, n, 19, Palette.UiInk, {
			Size = UDim2.new(0.6, -12, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		nameL:FindFirstChildOfClass("UIStroke"):Destroy()
		rows[i] = text(row, "", 21, Palette.CanopyDeep, {
			Size = UDim2.new(0.4, -12, 1, 0),
			Position = UDim2.new(0.6, 0, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		rows[i]:FindFirstChildOfClass("UIStroke"):Destroy()
	end

	-- PLAY AGAIN goes straight into the next run; LOBBY just goes home (never "leave")
	local againB = button(card, "PLAY AGAIN", Palette.CanopyMid, UDim2.new(0, 20, 1, -138), UDim2.new(1, -40, 0, 56))
	againB.TextSize = 28
	do
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.BackgroundColor3 = Palette.UiGold
		glow.BackgroundTransparency = 0.3
		glow.BorderSizePixel = 0
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = againB.Position + UDim2.new(againB.Size.X.Scale / 2, againB.Size.X.Offset / 2, 0, 28)
		glow.Size = againB.Size + UDim2.fromOffset(12, 12)
		againB.ZIndex = 2
		glow.ZIndex = 1
		Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 14)
		glow.Parent = card
		local loop = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(glow, loop, {
			BackgroundTransparency = 0.8,
			Size = againB.Size + UDim2.fromOffset(26, 22),
		}):Play()
		local rim = againB:FindFirstChildOfClass("UIStroke")
		if rim then
			TweenService:Create(rim, loop, { Color = Palette.UiGold }):Play()
		end
		-- shine: a pale band that sweeps over the face every few seconds
		local shine = Instance.new("Frame")
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0
		shine.BorderSizePixel = 0
		shine.Size = UDim2.fromScale(1, 1)
		shine.ZIndex = 2
		Instance.new("UICorner", shine).CornerRadius = UDim.new(0, 10)
		local sg = Instance.new("UIGradient")
		sg.Rotation = 20
		sg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.65),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sg.Offset = Vector2.new(-1, 0)
		sg.Parent = shine
		shine.Parent = againB
		task.spawn(function()
			while againB.Parent do
				sg.Offset = Vector2.new(-1, 0)
				TweenService:Create(sg, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Offset = Vector2.new(1, 0) })
					:Play()
				task.wait(3)
			end
		end)
	end
	local spectateB = button(card, "SPECTATE", Palette.CanopyDeep, UDim2.new(0, 20, 1, -72), UDim2.new(0.5, -28, 0, 50))
	local leaveB = button(card, "LOBBY", Palette.Trunk, UDim2.new(0.5, 8, 1, -72), UDim2.new(0.5, -28, 0, 50))

	-- spectate bar
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -24)
	bar.Size = UDim2.fromOffset(460, 60)
	bar.BackgroundColor3 = Palette.CanopyDeep
	bar.BackgroundTransparency = 0.05
	bar.Visible = false
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 14)
	stroke(bar, Palette.UiRim, 3)
	bar.Parent = gui
	local prevB = button(bar, "<", Palette.UiRim, UDim2.fromOffset(8, 8), UDim2.fromOffset(44, 44))
	local nextB = button(bar, ">", Palette.UiRim, UDim2.fromOffset(60, 8), UDim2.fromOffset(44, 44))
	local watchL = text(
		bar,
		"",
		20,
		Palette.UiText,
		{ Size = UDim2.new(1, -236, 1, 0), Position = UDim2.fromOffset(112, 0), TextTruncate = Enum.TextTruncate.AtEnd }
	)
	local barLeave = button(bar, "LOBBY", Palette.Trunk, UDim2.new(1, -116, 0, 8), UDim2.fromOffset(108, 44))

	local spectating = false
	local index = 1

	local function fitScale()
		local cam = workspace.CurrentCamera
		local v = cam and cam.ViewportSize or Vector2.new(1000, 700)
		scale.Scale = math.min(1, (v.Y - 40) / 460, (v.X - 32) / 380)
		bar.Size = UDim2.fromOffset(math.min(460, v.X - 32), 60)
	end

	local function myHumanoid(): Humanoid?
		return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	end

	local function close()
		spectating = false
		gui.Enabled = false
		bar.Visible = false
		local h = myHumanoid()
		if h then
			workspace.CurrentCamera.CameraSubject = h
		end
	end

	local function leave()
		remotes.LeaveMatch:FireServer()
		close()
	end

	local function watch(step: number)
		local list = targets()
		if #list == 0 then
			watchL.Text = "Nobody left running"
			return
		end
		index = (index - 1 + step) % #list + 1
		local h = list[index]
		workspace.CurrentCamera.CameraSubject = h
		local p = Players:GetPlayerFromCharacter(h.Parent)
		watchL.Text = "Watching " .. (p and p.DisplayName or (h.Parent :: Instance).Name)
	end

	spectateB.Activated:Connect(function()
		dim.Visible = false
		bar.Visible = true
		spectating = true
		index = 1
		watch(0)
	end)
	leaveB.Activated:Connect(leave)
	againB.Activated:Connect(function()
		leave()
		Sfx.start()
		task.spawn(function()
			local t0 = os.clock()
			while player:GetAttribute("State") ~= "Lobby" and os.clock() - t0 < 6 do
				task.wait(0.1)
			end
			remotes.Queue:FireServer(true)
		end)
	end)
	barLeave.Activated:Connect(leave)
	prevB.Activated:Connect(function()
		watch(-1)
	end)
	nextB.Activated:Connect(function()
		watch(1)
	end)

	remotes.Died.OnClientEvent:Connect(function(stats: any)
		if stats.win then
			Sfx.hushScreams()
		end
		Sfx.play(stats.win and "Win" or "Death")
		spectateB.Visible = not stats.win
		-- a win: no one left to watch, so LOBBY takes the whole row
		leaveB.Position = stats.win and UDim2.new(0, 20, 1, -72) or UDim2.new(0.5, 8, 1, -72)
		leaveB.Size = stats.win and UDim2.new(1, -40, 0, 50) or UDim2.new(0.5, -28, 0, 50)
		fitScale()
		-- dying in 1st is a win; 2nd/3rd still a podium, and the line under the title says so
		local pl = stats.place or 0
		local ord = ({ "1st", "2nd", "3rd" })[pl]
		reasonL.Text = ord and ("You came " .. ord .. "!") or string.format("%s", stats.reason or "Caught")
		-- everyone over the finish line won, whatever their place
		local won = stats.win or pl == 1
		titleL.Text = won and (pl == 1 and "WINNER!" or "YOU MADE IT!")
			or (pl == 2 or pl == 3) and "CONGRATULATIONS!"
			or "YOU DIED"
		titleL.TextColor3 = won and Palette.UiGold or (pl == 2 or pl == 3) and Palette.CanopyMid or Palette.UiDanger
		titleL.TextScaled = not won and (pl == 2 or pl == 3)
		rows[1].Text = string.format("%d m", stats.metres or 0)
		rows[2].Text = (stats.place or 0) > 0
				and string.format("#%d of %d", stats.place, math.max(stats.field or 0, stats.place))
			or "-"
		rows[3].Text = string.format("+%d m", stats.bonus or 0)
		rows[4].Text = string.format("~%d", stats.gems or 0)
		rows[5].Text = tostring(stats.cans or 0)
		local t = stats.time or 0
		rows[6].Text = string.format("%d:%02d", t // 60, t % 60)
		dim.Visible = true
		bar.Visible = false
		spectating = false
		gui.Enabled = true
		card.Position = UDim2.fromScale(0.5, 0.56)
		TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.5) })
			:Play()
	end)

	-- the round ended or we left: close; while spectating, move on when the runner we watch is out
	task.spawn(function()
		while true do
			task.wait(0.5)
			local state = player:GetAttribute("State")
			if gui.Enabled and state ~= "Caught" then
				close()
			elseif spectating then
				local cam = workspace.CurrentCamera
				local subj = cam.CameraSubject
				local ok = false
				for _, h in targets() do
					if h == subj then
						ok = true
					end
				end
				if not ok then
					index = 1
					watch(0)
				end
			end
		end
	end)
end

return DeathScreen
