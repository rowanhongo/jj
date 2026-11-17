--!strict
-- HUD: distance, juice bar, Guardian gap, alive count, round status, toasts.
-- Colours come only from Palette (docs/COLOUR_BIBLE.md).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)
local Config = require(Shared.Config)

local player = Players.LocalPlayer
local Hud = {}

local gui: ScreenGui
local toastHolder: Frame
local flashY = 200 -- set in init: just under the toast line

local function label(parent: Instance, size: UDim2, pos: UDim2, textSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.FredokaOne
	l.TextSize = textSize
	l.TextColor3 = color or Palette.UiText
	l.Text = ""
	local s = Instance.new("UIStroke")
	s.Color = Palette.UiRim
	s.Thickness = 2.5
	s.Parent = l
	l.Parent = parent
	return l
end

-- phones get smaller bars (they cover a big share of a small screen); PC is 80% of the old 240x22
local UIS = game:GetService("UserInputService")
local PHONE = UIS.TouchEnabled and not UIS.KeyboardEnabled
local BAR_K = PHONE and 0.65 or 0.8

local function bar(parent: Instance, pos: UDim2, fillColor: Color3, title: string): (Frame, TextLabel)
	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(math.round(240 * BAR_K), math.round(22 * BAR_K))
	back.Position = pos
	back.BackgroundColor3 = Palette.UiPanel
	back.BackgroundTransparency = 0.15
	Instance.new("UICorner", back).CornerRadius = UDim.new(0.5, 0)
	local st = Instance.new("UIStroke")
	st.Color = Palette.UiRim
	st.Thickness = 2
	st.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	fill.Parent = back
	local t = label(back, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), math.round(16 * BAR_K))
	t.Text = title
	t.ZIndex = 3
	back.Parent = parent
	return fill, t
end

-- The juice bar is the user's art (rbxassetid 125527088370600, 1020x209, "JUICE" and the jar
-- baked in): a dimmed copy is the empty bar, and a bright copy inside a clipping frame shows how
-- full it is. Returns the clipping frame (size its X scale) and an "OUT OF JUICE!" overlay.
local JUICE_ART = "rbxassetid://125527088370600"
local function juiceBar(parent: Instance, pos: UDim2): (Frame, TextLabel, number)
	local w = math.round(250 * BAR_K)
	local h = math.round(w * 209 / 1020)
	local back = Instance.new("ImageLabel")
	back.BackgroundTransparency = 1
	back.Image = JUICE_ART
	back.ImageColor3 = Palette.UiInk
	back.ImageTransparency = 0.25
	back.Size = UDim2.fromOffset(w, h)
	back.Position = pos
	local clip = Instance.new("Frame")
	clip.Name = "Fill"
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Size = UDim2.fromScale(1, 1)
	clip.Parent = back
	local full = Instance.new("ImageLabel")
	full.BackgroundTransparency = 1
	full.Image = JUICE_ART
	full.Size = UDim2.fromOffset(w, h)
	full.Parent = clip
	local t = label(back, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), math.round(18 * BAR_K))
	t.Text = "OUT OF JUICE!"
	t.TextColor3 = Palette.UiDanger
	t.ZIndex = 3
	t.Visible = false
	back.Parent = parent
	return clip, t, h
end

-- Toasts show one at a time at the top of the screen; each stays ~1.5 s (longer lines a little
-- more) and is then replaced by the next one in the queue.
local toastQueue: { { text: string, color: Color3? } } = {}
local toastBusy = false
local function showToasts()
	toastBusy = true
	while #toastQueue > 0 do
		local item = table.remove(toastQueue, 1) :: any
		local small = string.find(item.text, "^Congratulations") ~= nil or string.find(item.text, "^WINNER") ~= nil
		local l = label(
			toastHolder,
			UDim2.fromScale(1, 1),
			UDim2.fromOffset(0, -8),
			small and 20 or 26,
			item.color or Palette.UiGold
		)
		l.Text = item.text
		l.TextWrapped = true
		l.TextTransparency = 1
		TweenService:Create(l, TweenInfo.new(0.15), { TextTransparency = 0, Position = UDim2.new() }):Play()
		task.wait(math.clamp(1.2 + #item.text / 45, 1.5, 2.6) - (#toastQueue > 3 and 0.5 or 0))
		local tw = TweenService:Create(l, TweenInfo.new(0.15), { TextTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		l:Destroy()
	end
	toastBusy = false
end

-- Who went out: shown the moment it happens, stacked on the right (newest at the bottom)
local feed: Frame? = nil
function Hud.feed(text: string)
	if not feed then
		return
	end
	local l = label(feed, UDim2.new(1, 0, 0, 22), UDim2.new(), 18)
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.Text = text
	l.LayoutOrder = os.clock() * 1000
	local lines = feed:GetChildren()
	local n = 0
	for _, c in lines do
		if c:IsA("TextLabel") then
			n += 1
		end
	end
	if n > 4 then
		local oldest: TextLabel? = nil
		for _, c in lines do
			if c:IsA("TextLabel") and (not oldest or c.LayoutOrder < oldest.LayoutOrder) then
				oldest = c
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(3.5, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.wait(0.3)
			l:Destroy()
		end
	end)
end

function Hud.toast(text: string, color: Color3?)
	table.insert(toastQueue, { text = text, color = color })
	if not toastBusy then
		task.spawn(showToasts)
	end
end

-- Alerts during a run: the same look as the end-of-run lines (toasts), shown at once just
-- under them; a new alert replaces the one on screen.
local flashL: TextLabel? = nil
local flashN = 0
function Hud.flash(text: string, color: Color3)
	if flashL then
		flashL:Destroy()
	end
	flashN += 1
	local n = flashN
	local l = label(gui, UDim2.new(0.8, 0, 0, 40), UDim2.new(0.1, 0, 0, flashY + 8), 30, color)
	l.Text = text
	l.TextWrapped = true
	l.TextTransparency = 1
	flashL = l
	TweenService:Create(l, TweenInfo.new(0.15), { TextTransparency = 0, Position = UDim2.new(0.1, 0, 0, flashY) })
		:Play()
	task.delay(math.clamp(1.1 + #text / 45, 1.3, 2.2), function()
		if flashN ~= n then
			return
		end
		local tw = TweenService:Create(l, TweenInfo.new(0.2), { TextTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		l:Destroy()
		if flashL == l then
			flashL = nil
		end
	end)
end

function Hud.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "JJHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")

	local inset = GuiService:GetGuiInset()
	local top = inset.Y + 8

	-- metres up in the top band, level with Roblox's own buttons (like a match timer)
	local band = Instance.new("ScreenGui")
	band.Name = "JJTopBand"
	band.ResetOnSpawn = false
	band.IgnoreGuiInset = true
	band.ScreenInsets = Enum.ScreenInsets.None
	band.DisplayOrder = 2
	band.Parent = gui.Parent
	local dist = label(band, UDim2.new(0, 220, 0, 40), UDim2.new(0.5, -110, 0, 2), 36, Palette.UiGold)
	local portraits = require(script.Parent.Portraits)
	portraits.init(band, 42)
	local statusL = label(gui, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, top + 58), 32)
	-- right column (running count, place, bonus, feed): higher on phones, where it sat low
	local rTop = PHONE and top - 22 or top
	local alive = label(gui, UDim2.fromOffset(200, 30), UDim2.new(1, -212, 0, rTop), 22)
	alive.TextXAlignment = Enum.TextXAlignment.Right

	local bTop = PHONE and top - 6 or top + 4
	local juiceFill, juiceText, juiceH = juiceBar(gui, UDim2.fromOffset(16, bTop))
	local gapFill, gapText = bar(gui, UDim2.fromOffset(16, bTop + juiceH + 6), Palette.UiDanger, "GUARDIAN")
	-- the route map, under the bars on the left
	require(script.Parent.RouteMap).init(gui, UDim2.fromOffset(16, bTop + juiceH + 6 + math.round(22 * BAR_K) + 12))
	-- live place, right side under "N running"; gold with its bonus while in a paid place
	local place = label(gui, UDim2.fromOffset(200, 50), UDim2.new(1, -212, 0, rTop + 30), 44)
	place.TextXAlignment = Enum.TextXAlignment.Right
	local bonus = label(gui, UDim2.fromOffset(260, 24), UDim2.new(1, -272, 0, rTop + 80), 18, Palette.UiGold)
	bonus.TextXAlignment = Enum.TextXAlignment.Right
	local lastPlace = 0
	local lastAlive = 0
	local lastFlash = 0 -- places can swap back and forth; pop up at most every 1.5 s

	toastHolder = Instance.new("Frame")
	toastHolder.BackgroundTransparency = 1
	toastHolder.Size = UDim2.new(0.8, 0, 0, 64)
	toastHolder.Position = UDim2.new(0.1, 0, 0, top + 56)
	flashY = top + 124
	toastHolder.Parent = gui
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(300, 120)
	f.Position = UDim2.new(1, -312, 0, rTop + 104)
	local fl = Instance.new("UIListLayout")
	fl.SortOrder = Enum.SortOrder.LayoutOrder
	fl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	fl.Parent = f
	f.Parent = gui
	feed = f

	RunService.RenderStepped:Connect(function()
		local state = player:GetAttribute("State")
		local isRun = state == "Running" or state == "Countdown"
		statusL.Text = workspace:GetAttribute("Status") or ""
		juiceFill.Parent.Visible = isRun
		gapFill.Parent.Visible = state == "Running"
		dist.Visible = isRun or state == "Caught" or state == "Finished"
		local goal = workspace:GetAttribute("GoalM")
		dist.Text = goal and string.format("%d / %d m", player:GetAttribute("Distance") or 0, goal)
			or string.format("%d m", player:GetAttribute("Distance") or 0)
		local a = workspace:GetAttribute("Alive") or 0
		alive.Text = (state == "Running" or state == "Caught" or state == "Finished") and string.format("%d running", a)
			or ""
		-- someone dropped out: say how many are left (never your own place)
		if state == "Running" and a < lastAlive and a > 1 then
			Hud.flash(string.format("%d LEFT", a), Palette.UiText)
		end
		lastAlive = a

		local juice = player:GetAttribute("Juice") or 0
		juiceFill.Size = UDim2.fromScale(math.clamp(juice / Config.JuiceMax, 0, 1), 1)
		juiceText.Visible = juice <= 0

		-- Guardian gap: full = safe (60+ studs), empty = about to be caught
		local myStuds = (player:GetAttribute("Distance") or 0) * Config.StudsPerMetre
		local gap = myStuds - (workspace:GetAttribute("PaceDist") or 0)
		local g = math.clamp(gap / 60, 0, 1)
		gapFill.Size = UDim2.fromScale(1 - g, 1)
		gapText.Text = gap < 20 and "GUARDIAN CLOSE!" or "GUARDIAN"

		local pl = player:GetAttribute("Place")
		local mult = player:GetAttribute("PlaceMult") or 1
		if state == "Running" and pl then
			place.Text = "#" .. pl
			place.TextColor3 = mult > 1 and Palette.UiGold or Palette.UiText
			bonus.Text = mult > 1
					and string.format(
						"x%s GEMS + DISTANCE  (+%d m)",
						tostring(mult),
						player:GetAttribute("BonusM") or 0
					)
				or ""
			if pl ~= lastPlace and lastPlace ~= 0 and os.clock() - lastFlash > 1.5 then
				lastFlash = os.clock()
				if mult > 1 and pl < lastPlace then
					Hud.flash(string.format("#%d  x%s BONUS!", pl, tostring(mult)), Palette.UiGold)
				end
			end
			lastPlace = pl
		else
			place.Text = ""
			bonus.Text = ""
			lastPlace = 0
		end
	end)
end

return Hud
