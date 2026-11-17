--!strict
-- Client-drawn lobby boards (each player sees their own):
--   YourStats board in the leaderboard corner, the three daily quest notes, and the static signs
--   (Hall of Legends, Daily Quests header, Gem Shop). The global leaderboards are server-drawn.
-- Reads replicated player attributes (DataService.syncStats) and the pushed Profile for titles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)
local Items = require(Shared.Items)

local player = Players.LocalPlayer
local LobbyBoards = {}

local TITLE = Enum.Font.FredokaOne
local BODY = Enum.Font.GothamBold

local function gui(part: BasePart, ppS: number?): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = ppS or 50
	g.LightInfluence = 0.4
	g.Adornee = part
	g.Parent = player:WaitForChild("PlayerGui")
	return g
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = BODY
	l.TextColor3 = Palette.UiInk
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- the gem from the icon sheet (rbxassetid 89148085552985)
local function gemIcon(parent: Instance, size: UDim2, pos: UDim2, anchor: Vector2?): ImageLabel
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Image = "rbxassetid://89148085552985"
	img.ImageRectOffset = Vector2.new(16, 168)
	img.ImageRectSize = Vector2.new(232, 200)
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = size
	img.Position = pos
	img.AnchorPoint = anchor or Vector2.zero
	img.Parent = parent
	return img
end

local function sign(part: BasePart?, text: string, colour: Color3, bg: Color3?, gem: boolean?)
	if not part then
		return
	end
	local g = gui(part, 60)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = bg or Palette.UiPaper
	f.BackgroundTransparency = bg and 0 or 1
	f.BorderSizePixel = 0
	f.Parent = g
	local l = label(f, {
		Text = text,
		Font = TITLE,
		TextColor3 = colour,
		Size = UDim2.new(1, -16, 1, -10),
		Position = UDim2.fromOffset(8, 5),
	})
	if gem then
		gemIcon(f, UDim2.fromScale(0.2, 0.9), UDim2.fromScale(0.02, 0.05))
		l.Size = UDim2.new(0.78, -8, 1, -10)
		l.Position = UDim2.new(0.22, 0, 0, 5)
	end
	local s = Instance.new("UIStroke")
	s.Color = Palette.UiRim
	s.Thickness = 3
	s.Parent = l
end

-- ---------------- Your stats ----------------
local profile: any = nil
local statRows: { [string]: TextLabel } = {}
local badgeHolder: Frame? = nil
local nameLabel: TextLabel? = nil

local STATS = {
	{ key = "Best", text = "Best run", unit = " m" },
	{ key = "TotalDist", text = "Total distance", unit = " m" },
	{ key = "Wins", text = "Wins", unit = "" },
	{ key = "Runs", text = "Runs", unit = "" },
	{ key = "GemsEarned", text = "Gems earned", unit = " 💎" },
	{ key = "CheckIns", text = "Days played", unit = "" },
}

local function buildStats(screen: BasePart)
	local g = gui(screen)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	-- Deliberately plain (paper and ink) so the three global boards beside it draw the eye.
	bg.BackgroundColor3 = Palette.UiPaperDim
	bg.BorderSizePixel = 0
	bg.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 22)
	pad.PaddingLeft = UDim.new(0, 28)
	pad.PaddingRight = UDim.new(0, 28)
	pad.Parent = bg
	label(bg, { Text = "Your stats", Font = TITLE, TextColor3 = Palette.UiInk, Size = UDim2.new(1, 0, 0, 64) })
	nameLabel = label(bg, {
		Text = "",
		TextColor3 = Palette.UiInk,
		TextTransparency = 0.3,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 84),
	})
	for i, s in STATS do
		local y = 140 + (i - 1) * 50
		local strip = Instance.new("Frame")
		strip.BackgroundColor3 = Palette.UiPaper
		strip.BackgroundTransparency = i % 2 == 1 and 0 or 1
		strip.BorderSizePixel = 0
		strip.Size = UDim2.new(1, 0, 0, 46)
		strip.Position = UDim2.fromOffset(0, y)
		strip.Parent = bg
		label(strip, {
			Text = s.text,
			TextColor3 = Palette.UiInk,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.6, -8, 1, -12),
			Position = UDim2.fromOffset(8, 6),
		})
		statRows[s.key] = label(strip, {
			Text = "0",
			TextColor3 = Palette.UiInk,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.4, -8, 1, -12),
			Position = UDim2.new(0.6, 0, 0, 6),
		})
	end
	local by = 140 + #STATS * 50 + 12
	label(bg, {
		Text = "Badges",
		Font = TITLE,
		TextColor3 = Palette.UiInk,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, by),
	})
	local h = Instance.new("Frame")
	h.BackgroundTransparency = 1
	h.Size = UDim2.new(1, 0, 0, 160)
	h.Position = UDim2.fromOffset(0, by + 46)
	h.Parent = bg
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0, 34)
	grid.CellPadding = UDim2.fromOffset(12, 6)
	grid.Parent = h
	badgeHolder = h
end

local function drawBadges()
	local h = badgeHolder
	if not h then
		return
	end
	for _, c in h:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for _, c in Items.Cosmetics do
		if c.kind == "Title" and c.id ~= "T_Rookie" then
			local own = profile and profile.cosmetics and profile.cosmetics[c.id]
			local l = label(h, {
				Text = c.name,
				TextColor3 = Palette.UiInk,
				TextTransparency = own and 0 or 0.5,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end
end

local function drawStats()
	for _, s in STATS do
		local l = statRows[s.key]
		if l then
			l.Text = fmt(player:GetAttribute(s.key) or 0) .. s.unit
		end
	end
	if nameLabel then
		nameLabel.Text = string.format("%s  ·  Level %d", player.DisplayName, player:GetAttribute("Level") or 1)
	end
end

-- ---------------- Daily quests ----------------
type Note = { q: any, bar: Frame, count: TextLabel, reward: TextLabel, done: TextLabel }
local notes: { Note } = {}
local headers: { { set: any, label: TextLabel } } = {}

local function buildNote(part: BasePart, q: any)
	local g = gui(part, 60)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Palette.UiPaper
	bg.BorderSizePixel = 0
	bg.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 30)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = bg
	-- No icons: the quest text fills the top half of the note, progress and reward the bottom.
	label(bg, {
		Text = q.text,
		Font = TITLE,
		TextColor3 = Palette.UiInk,
		Size = UDim2.new(1, 0, 0, 110),
		Position = UDim2.fromOffset(0, 10),
		TextWrapped = true,
	})
	local well = Instance.new("Frame")
	well.BackgroundColor3 = Palette.UiPaperDim
	well.BorderSizePixel = 0
	well.Size = UDim2.new(1, 0, 0, 18)
	well.Position = UDim2.fromOffset(0, 140)
	well.Parent = bg
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Palette.UiGood
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(0, 1)
	bar.Parent = well
	local count = label(bg, { Text = "", Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 168) })
	local reward = label(bg, {
		Text = string.format("+%d", q.gems),
		Font = TITLE,
		TextColor3 = Palette.UiRim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.5, 6, 0, 36),
		Position = UDim2.fromOffset(0, 200),
	})
	gemIcon(bg, UDim2.fromOffset(40, 34), UDim2.new(0.5, 12, 0, 201))
	local done = label(bg, {
		Text = "DONE",
		Font = TITLE,
		TextColor3 = Palette.UiBuy,
		Rotation = -14,
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(0, 80),
		Visible = false,
	})
	local st = Instance.new("UIStroke")
	st.Color = Palette.UiInk
	st.Thickness = 2
	st.Parent = done
	table.insert(notes, { q = q, bar = bar, count = count, reward = reward, done = done })
end

local function drawQuests()
	for _, n in notes do
		local q = n.q
		do
			local v = player:GetAttribute(q.id) or 0
			local finished = v < 0
			local cur = finished and q.n or v
			n.bar.Size = UDim2.fromScale(math.clamp(cur / q.n, 0, 1), 1)
			n.count.Text = string.format("%s / %s", fmt(cur), fmt(q.n))
			n.done.Visible = finished
			n.reward.TextTransparency = finished and 0.6 or 0
		end
	end
	for _, h in headers do
		local period = h.set.period
		local left = period - (os.time() % period)
		h.label.Text = if left >= 3600
			then string.format("%s  ·  new in %d:%02d:%02d", h.set.name, left // 3600, (left % 3600) // 60, left % 60)
			else string.format("%s  ·  new in %d:%02d", h.set.name, left // 60, left % 60)
	end
end

function LobbyBoards.init()
	local building = workspace:WaitForChild("LobbyBuilding", 20)
	if not building then
		return
	end
	local lb = building:FindFirstChild("Leaderboards")
	local stats = lb and lb:FindFirstChild("YourStats")
	local screen = stats and stats:FindFirstChild("Screen")
	if screen and screen:IsA("BasePart") then
		buildStats(screen)
	end
	local monument = lb and lb:FindFirstChild("Monument")
	sign(
		monument and monument:FindFirstChild("Sign") :: BasePart?,
		"HALL\nOF\nLEGENDS",
		Palette.UiGold,
		Palette.UiPanel
	)

	-- one board per quest set; each board's Note1..3 show that set's quests in order
	for _, set in Items.QuestSets do
		local qb = building:FindFirstChild(set.board)
		if not qb then
			continue
		end
		local i = 0
		for _, q in Items.Quests do
			if q.set == set.id then
				i += 1
				local part = qb:FindFirstChild("Note" .. i)
				if part and part:IsA("BasePart") then
					buildNote(part, q)
				end
			end
		end
		local hdr = qb:FindFirstChild("Header")
		if hdr and hdr:IsA("BasePart") then
			local g = gui(hdr, 60)
			table.insert(headers, {
				set = set,
				label = label(g, {
					Text = "",
					Font = TITLE,
					TextColor3 = Palette.UiRim,
					Size = UDim2.new(1, -10, 1, -8),
					Position = UDim2.fromOffset(5, 4),
				}),
			})
		end
	end
	local shop = building:FindFirstChild("GemShop")
	sign(shop and shop:FindFirstChild("Sign") :: BasePart?, "GEM SHOP", Palette.UiGold, Palette.UiPanel, true)

	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Profile").OnClientEvent:Connect(function(p)
		profile = p
		drawBadges()
	end)
	drawBadges()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		drawStats()
		drawQuests()
	end)
end

return LobbyBoards
