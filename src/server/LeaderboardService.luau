--!strict
-- The three global leaderboards in the lobby's leaderboard corner:
--   TopDistance (lifetime metres), MostGems (lifetime gems earned), MostWins, BestRun (single run).
-- Each is an OrderedDataStore. Online players' totals are pushed and the top 10 are read every
-- REFRESH seconds. When DataStores are unavailable (Studio without API access) the boards rank the
-- players in this server instead, so they still show something.
-- The fourth board (YourStats) is per player and drawn by the client (client/LobbyBoards).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Palette)
local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

-- Every REFRESH seconds each server reads the four boards (4 GetSorted requests) and writes
-- only the totals that changed since its last write. Roblox's per-server budget is 5 + 2 x players
-- sorted reads a minute, so a read is skipped (board keeps its last rows) whenever the budget is
-- low; the cost per server never grows with the total player count, so thousands of players
-- across many servers never overload it.
local REFRESH = 30
local ROWS = 10

type Board = { id: string, title: string, icon: Rect?, unit: string, field: string, store: OrderedDataStore? }
local boards: { Board } = {
	{
		id = "TopDistance",
		title = "TOP DISTANCE",
		icon = Rect.new(520, 144, 760, 384),
		unit = " m",
		field = "totalDist",
	},
	{ id = "MostGems", title = "MOST GEMS", icon = Rect.new(16, 168, 248, 368), unit = "", field = "gemsEarned" },
	{ id = "MostWins", title = "MOST WINS", icon = Rect.new(272, 160, 496, 368), unit = "", field = "wins" },
	{ id = "BestRun", title = "BEST RUN", icon = Rect.new(784, 144, 1000, 376), unit = " m", field = "best" },
}
for _, b in boards do
	pcall(function()
		b.store = DataStoreService:GetOrderedDataStore("JJ_LB_" .. b.id)
	end)
end

local names: { [number]: string } = {}
local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = ok and n or ("Player " .. userId)
	return names[userId]
end

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Builds the rows on the board's Screen part once; returns the row labels to fill.
type Row = { rank: TextLabel, name: TextLabel, value: TextLabel }
local rowsFor: { [string]: { Row } } = {}

local function build(b: Board, screen: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.4
	gui.Parent = screen

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Palette.UiPaper
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 26)
	pad.PaddingLeft = UDim.new(0, 30)
	pad.PaddingRight = UDim.new(0, 30)
	pad.Parent = bg

	-- Title band: dark jungle green with gold lettering, so these three out-shout the plain stats board.
	local title = Instance.new("TextLabel")
	title.BackgroundColor3 = Palette.UiPanel
	title.BorderSizePixel = 0
	title.Size = UDim2.new(1, 60, 0, 96)
	title.Position = UDim2.fromOffset(-30, -26)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = b.title
	title.TextColor3 = Palette.UiGold
	title.Parent = bg
	local tPad = Instance.new("UIPadding")
	tPad.PaddingTop = UDim.new(0, 12)
	tPad.PaddingBottom = UDim.new(0, 10)
	tPad.Parent = title
	-- the board's icon (sheet rbxassetid 89148085552985) at the left end of the band
	if b.icon then
		tPad.PaddingLeft = UDim.new(0, 104)
		tPad.PaddingRight = UDim.new(0, 24)
		for _, side in { 0 } do
			local ic = Instance.new("ImageLabel")
			ic.BackgroundTransparency = 1
			ic.Image = "rbxassetid://89148085552985"
			ic.ImageRectOffset = b.icon.Min
			ic.ImageRectSize = b.icon.Max - b.icon.Min
			ic.ScaleType = Enum.ScaleType.Fit
			ic.Size = UDim2.fromOffset(92, 92)
			ic.AnchorPoint = Vector2.new(side, 0.5)
			-- in the board frame, not the title (its padding would push them inward)
			ic.Position = UDim2.new(side, side == 0 and -22 or 22, 0, 22)
			ic.ZIndex = 3
			ic.Parent = bg
		end
	end
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Palette.UiRim
	tStroke.Thickness = 3
	tStroke.Parent = title
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = Palette.UiGold
	edge.Thickness = 10
	edge.Parent = bg
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = Palette.UiGold
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(1, 0, 0, 6)
	rule.Position = UDim2.fromOffset(0, 100)
	rule.Parent = bg

	local rows = {}
	local rowH = 52
	for i = 1, ROWS do
		local y = 124 + (i - 1) * (rowH + 4)
		local strip = Instance.new("Frame")
		strip.BorderSizePixel = 0
		strip.BackgroundColor3 = i % 2 == 1 and Palette.UiPaperDim or Palette.UiPaper
		strip.Size = UDim2.new(1, 0, 0, rowH)
		strip.Position = UDim2.fromOffset(0, y)
		strip.Parent = bg
		local function label(
			x: number,
			w: number,
			align: Enum.TextXAlignment,
			colour: Color3,
			font: Enum.Font
		): TextLabel
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Position = UDim2.new(x, 8, 0, 6)
			l.Size = UDim2.new(w, -16, 1, -12)
			l.TextScaled = true
			l.Font = font
			l.TextXAlignment = align
			l.TextColor3 = colour
			l.Text = ""
			l.Parent = strip
			return l
		end
		local medal = Palette.UiInk -- gold/silver/bronze numbers were hard to read on the boards
		table.insert(rows, {
			rank = label(0, 0.14, Enum.TextXAlignment.Left, medal, Enum.Font.FredokaOne),
			name = label(0.14, 0.56, Enum.TextXAlignment.Left, Palette.UiInk, Enum.Font.GothamBold),
			value = label(0.68, 0.32, Enum.TextXAlignment.Right, Palette.UiRim, Enum.Font.FredokaOne),
		})
	end
	rowsFor[b.id] = rows
end

-- The #1 of each board stands as a statue on a plinth in the bay beside it (the wall side away
-- from the board's right): their own avatar, idling, with their name on the plinth. Rebuilt
-- only when the #1 changes.
local CHEER = "rbxassetid://507770677" -- Roblox's stock R15 cheer (the winners' celebration)
local screens: { [string]: BasePart } = {}
local champs: { [string]: { id: number, model: Instance } } = {}
local avatars: { [number]: Model } = {}
local function champion(b: Board, userId: number?)
	local screen = screens[b.id]
	local cur = champs[b.id]
	if not screen or (cur and cur.id == userId) then
		return
	end
	if cur then
		cur.model:Destroy()
		champs[b.id] = nil
	end
	if not userId or userId <= 0 then
		return
	end
	champs[b.id] = { id = userId, model = Instance.new("Folder") } -- claimed while loading
	task.spawn(function()
		local av = avatars[userId]
		if not av then
			local ok, m = pcall(Players.CreateHumanoidModelFromUserId, Players, userId)
			if not ok or not m then
				return
			end
			av = m
			avatars[userId] = m
		end
		if not champs[b.id] or champs[b.id].id ~= userId then
			return -- the #1 changed while loading
		end
		local holder = Instance.new("Model")
		holder.Name = "Champion_" .. b.id
		-- The stand is built off the board's own plinth: the same limestone, height, depth and
		-- sandstone trim, lined up with it, joined to it by a lower stone step, out on the side
		-- away from the board's right (the free wall).
		local bp = screen.Parent and screen.Parent:FindFirstChild("Plinth") :: BasePart?
		local trimRef = screen.Parent and screen.Parent:FindFirstChild("PlinthTrim") :: BasePart?
		if not bp then
			return
		end
		local away = screen.CFrame * CFrame.new(-(screen.Size.X / 2 + 9.3), 0, 0)
		local side = bp.CFrame:PointToObjectSpace(away.Position).X >= 0 and 1 or -1
		local W, GAP = 6, 4
		local half = bp.Size.X / 2
		local standCf = bp.CFrame * CFrame.new(side * (half + GAP + W / 2), 0, 0)
		local function block(size: Vector3, at: CFrame, color: Color3, mat: Enum.Material): Part
			local q = Instance.new("Part")
			q.Anchored = true
			q.Size = size
			q.CFrame = at
			q.Color = color
			q.Material = mat
			q.TopSurface = Enum.SurfaceType.Smooth
			q.Parent = holder
			return q
		end
		local plinth = block(Vector3.new(W, bp.Size.Y, bp.Size.Z), standCf, bp.Color, bp.Material)
		local topY = bp.Size.Y / 2
		if trimRef then
			-- the trim sits where the board's does relative to its plinth
			local rel = bp.CFrame:ToObjectSpace(trimRef.CFrame)
			block(
				Vector3.new(W + (trimRef.Size.X - bp.Size.X), trimRef.Size.Y, trimRef.Size.Z),
				standCf * CFrame.new(0, rel.Y, rel.Z),
				Palette.StoneTrim,
				trimRef.Material
			)
			topY = rel.Y + trimRef.Size.Y / 2
		end
		-- the step between them: half height, a little shallower, ends tucked into both
		block(
			Vector3.new(GAP + 1, bp.Size.Y * 0.5, bp.Size.Z - 1),
			bp.CFrame * CFrame.new(side * (half + GAP / 2), -bp.Size.Y * 0.25, 0),
			bp.Color,
			bp.Material
		)
		local base = standCf * CFrame.new(0, topY, 0)
		local sign = Instance.new("SurfaceGui")
		sign.Face = Enum.NormalId.Front
		sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sign.PixelsPerStud = 50
		sign.LightInfluence = 0.3
		sign.Parent = plinth
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextColor3 = Palette.UiGold
		t.Text = nameOf(userId) -- just the name: the board already shows the rank
		local st = Instance.new("UIStroke")
		st.Color = Palette.UiInk
		st.Thickness = 3
		st.Parent = t
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.06, 0)
		pad.PaddingRight = UDim.new(0.06, 0)
		pad.PaddingTop = UDim.new(0.15, 0)
		pad.PaddingBottom = UDim.new(0.15, 0)
		pad.Parent = t
		t.Parent = sign
		local m = av:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = d.Name == "HumanoidRootPart"
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		m.Name = "Statue"
		m.Parent = holder
		-- a little larger than life, feet on the plinth (placed by its box, so any rig fits)
		m:ScaleTo(1.35)
		m:PivotTo(base * CFrame.new(0, 12, 0))
		local bcf, bsize = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + Vector3.new(0, base.Y - (bcf.Y - bsize.Y / 2), 0))
		if not (champs[b.id] and champs[b.id].id == userId) then
			holder:Destroy()
			return
		end
		champs[b.id].model:Destroy()
		champs[b.id].model = holder
		-- in the world first: an Animator outside the DataModel won't play its tracks
		holder.Parent = workspace
		local animator = hum and (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum))
		if animator then
			local a = Instance.new("Animation")
			a.AnimationId = CHEER
			local ok, tr = pcall(animator.LoadAnimation, animator, a)
			if ok and tr then
				tr.Looped = true
				tr:Play()
			end
		end
	end)
end

local function fill(b: Board, entries: { { name: string, value: number, id: number? } })
	champion(b, entries[1] and entries[1].id)
	local rows = rowsFor[b.id]
	if not rows then
		return
	end
	for i, r in rows do
		local e = entries[i]
		r.rank.Text = e and ("#" .. i) or ""
		r.name.Text = e and e.name or (i == 1 and "Be the first!" or "")
		r.value.Text = e and (fmt(e.value) .. b.unit) or ""
	end
end

local function localEntries(b: Board): { { name: string, value: number, id: number? } }
	local t = {}
	for player, p in DataService.all() do
		if player.Parent and ((p :: any)[b.field] or 0) > 0 then
			table.insert(t, { name = player.DisplayName, value = (p :: any)[b.field] or 0, id = player.UserId })
		end
	end
	table.sort(t, function(a, c)
		return a.value > c.value
	end)
	return t
end

local pushed: { [string]: number } = {} -- board..userId -> last value written
local function push(player: Player)
	local p = DataService.get(player)
	if not p then
		return
	end
	for _, b in boards do
		local s = b.store
		local v = math.floor((p :: any)[b.field] or 0)
		local key = b.id .. player.UserId
		if s and v > 0 and pushed[key] ~= v then
			if
				DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementSortedAsync) < 1
			then
				return -- try again next cycle
			end
			local ok = pcall(function()
				s:SetAsync(tostring(player.UserId), v)
			end)
			if ok then
				pushed[key] = v
			end
		end
	end
end

local usingLocal: { [string]: boolean } = {}
-- last top-ROWS read from each global store (userId, value), so a finished run can be shown at
-- once by laying the online players' fresh totals over it, without another read
local cached: { [string]: { { id: number, value: number } } } = {}

-- the cached global rows with everyone online updated to their current total, re-sorted
local function merged(b: Board): { { name: string, value: number, id: number? } }
	local byId: { [number]: number } = {}
	for _, e in cached[b.id] or {} do
		byId[e.id] = e.value
	end
	for player, p in DataService.all() do
		local v = math.floor((p :: any)[b.field] or 0)
		if player.Parent and v > (byId[player.UserId] or 0) then
			byId[player.UserId] = v
		end
	end
	local t = {}
	for id, v in byId do
		if v > 0 then
			table.insert(t, { id = id, value = v })
		end
	end
	table.sort(t, function(a, c)
		return a.value > c.value
	end)
	local out = {}
	for i = 1, math.min(ROWS, #t) do
		table.insert(out, { name = nameOf(t[i].id), value = t[i].value, id = t[i].id })
	end
	return out
end

local function refresh()
	for _, player in Players:GetPlayers() do
		push(player)
	end
	for _, b in boards do
		local entries: { { name: string, value: number, id: number? } }? = nil
		local s = b.store
		local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync)
		if s and budget < 1 and cached[b.id] then
			fill(b, merged(b)) -- out of reads this minute: keep the last rows, refresh the online totals
			continue
		end
		if s then
			local ok, page = pcall(function()
				return s:GetSortedAsync(false, ROWS):GetCurrentPage()
			end)
			if ok then
				local rows = {}
				for _, row in page do
					table.insert(rows, { id = tonumber(row.key) or 0, value = row.value })
				end
				cached[b.id] = rows
				entries = merged(b)
			end
		end
		usingLocal[b.id] = entries == nil
		fill(b, entries or localEntries(b))
	end
end

function LeaderboardService.init()
	local building = workspace:FindFirstChild("LobbyBuilding")
	local folder = building and building:FindFirstChild("Leaderboards")
	if not folder then
		return
	end
	for _, b in boards do
		local m = folder:FindFirstChild(b.id)
		local screen = m and m:FindFirstChild("Screen")
		if screen and screen:IsA("BasePart") then
			build(b, screen)
			screens[b.id] = screen
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		push(player)
		for _, b in boards do
			pushed[b.id .. player.UserId] = nil
		end
	end)
	task.spawn(function()
		task.wait(3)
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
end

-- Redraw now (after a round ends) without waiting for the next cycle: the last global read with
-- the online players' new totals laid over it. The stores themselves are written and re-read on
-- their own timer to stay inside DataStore budgets.
function LeaderboardService.bump()
	for _, b in boards do
		fill(b, if usingLocal[b.id] ~= false then localEntries(b) else merged(b))
	end
end

return LeaderboardService
