--!strict
-- Lobby UI (only while State == "Lobby"): level + gems top right, next-run countdown top centre,
-- PLAY to join the next run, and a bottom bar: Shop [Z], Inventory [X], Modes [C].
-- Shop: Daily Shop, Item Rolls (with the reel), Passes. Inventory: Gadgets (loadout),
-- Achievements (titles earned + gem rewards, and which mode's best floats above your head),
-- Emotes, Trails.
-- During a run the screen stays clear except the two gadget slots [Q] [E].
-- Colours only from Palette.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)
local Items = require(Shared.Items)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShopCall = remotes:WaitForChild("ShopCall") :: RemoteFunction

local Sfx = require(script.Parent.Sfx)
local ActionButton = require(script.Parent.ActionButton)
local Settings = require(script.Parent.Settings)
local SettingsDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SettingsDefs"))
local Lobby = {}
local BoxLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BoxLook"))
-- set in init: the ? box pop on pickup (flies to the slot it fills)
Lobby.boxPop = function() end

local profile: any = nil
local gui: ScreenGui
local root: Frame -- scaled canvas for lobby widgets
local panelHolder: Frame
local PANEL_TOP, PANEL_BOTTOM = 136, 104 -- design units (the lobby gui is UI-scaled)
local openPanel: string? = nil
local itemTip: (GuiObject, any) -> ()
local renderPanel: () -> () = function() end
local toastFn: (string) -> () = function() end

-- Builder Sans (Roblox's own UI face): even spacing at every size, unlike Fredoka One
local TITLE = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local rarityWells = false -- only Item Rolls paints the item wells in rarity colours

-- ---------- tiny builders ----------
local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		if k == "Font" and typeof(v) == "Font" then
			(i :: any).FontFace = v
		else
			(i :: any)[k] = v
		end
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function corner(parent: Instance, r: number?)
	new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, parent)
end

local function stroke(parent: Instance, color: Color3, thick: number?)
	return new(
		"UIStroke",
		{ Color = color, Thickness = thick or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		parent
	)
end

local function text(
	parent: Instance,
	t: string,
	size: number,
	color: Color3,
	font: any,
	props: { [string]: any }?
): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = t,
		TextSize = size,
		TextColor3 = color,
		Font = font or BODY,
		Size = UDim2.fromScale(1, 1),
	}, parent)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

-- Icon sheet (rbxassetid 89148085552985, 1024x512), left to right: gems, wins, distance, best run.
local ICONS = "rbxassetid://89148085552985"
local ICON = {
	Gems = Rect.new(16, 168, 248, 368),
	Wins = Rect.new(272, 160, 496, 368),
	Distance = Rect.new(520, 144, 760, 384),
	BestRun = Rect.new(784, 144, 1000, 376),
}
-- Menu icons: the user's sheet (1024x298, black): cart | bag | gamepad. Rects measured from
-- the pixels (dark columns 11-350, 383-644, 675-1011; rows 11-286). No gift icon on it.
local MENU_ICONS = "rbxassetid://90222099515375"
local MENU = {
	Shop = Rect.new(11, 11, 351, 287),
	Inventory = Rect.new(383, 11, 645, 287),
	Modes = Rect.new(675, 11, 1012, 287),
}
local function menuIcon(parent: Instance, name: string, size: number, color: Color3): ImageLabel?
	local r = MENU[name]
	if not r then
		return nil
	end
	return new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = MENU_ICONS,
		ImageRectOffset = r.Min,
		ImageRectSize = r.Max - r.Min,
		ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = color,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 4,
	}, parent)
end
-- Jungle UI casings sheet (rbxassetid 126274240973137, 1023x682); rects in sheet pixels.
local CASINGS = "rbxassetid://126274240973137"
local CASE = {
	woodTop = { Rect.new(717, 81, 1019, 173) }, -- level counter
	woodBot = { Rect.new(735, 176, 1002, 263) }, -- gem counter
	button = { Rect.new(486, 529, 678, 647) }, -- stone button in a wood frame
	parchment = { Rect.new(7, 208, 269, 533) }, -- parchment sheet in a lashed wood frame (menus)
}
local function casing(parent: Instance, name: string, props: { [string]: any }): ImageLabel
	local r = CASE[name][1]
	local img = new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = CASINGS,
		ImageRectOffset = r.Min,
		ImageRectSize = r.Max - r.Min,
		ZIndex = 0,
	}, parent)
	for k, v in props do
		(img :: any)[k] = v
	end
	return img
end

local function button(
	parent: Instance,
	t: string,
	bg: Color3,
	fg: Color3,
	size: UDim2,
	pos: UDim2,
	onClick: () -> ()
): TextButton
	local b = new("TextButton", {
		Size = size,
		Position = pos,
		BackgroundColor3 = bg,
		Text = t,
		TextColor3 = fg,
		Font = TITLE,
		TextSize = 22,
		AutoButtonColor = true,
	}, parent)
	corner(b, 8)
	-- jungle skin: leaf green / deep green / red / paper, brown rim, light-to-shade gradient
	local fg = fg
	if bg == Palette.UiBuy then
		b.BackgroundColor3, fg = Palette.CanopyMid, Palette.UiText
	elseif bg == Palette.UiInk then
		b.BackgroundColor3, fg = Palette.CanopyDeep, Palette.UiText
	elseif bg == Palette.UiDanger then
		fg = Palette.UiText
	elseif bg == Palette.UiPaperDim or bg == Palette.UiPaper then
		fg = Palette.CanopyDeep
	end
	b.TextColor3 = fg
	stroke(b, Palette.UiRim, 2.5)
	new(
		"UIGradient",
		{ Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)), Rotation = 90 },
		b
	)
	local light = fg == Palette.UiText
	if light then
		new(
			"UIStroke",
			{ Color = Palette.UiRim, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual },
			b
		)
	end
	-- "💎 7000" -> the game's gem icon (not the emoji) beside the number, sized to the button
	local s, e = string.find(t, "💎", 1, true)
	if s then
		b.Text = ""
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, b)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		local function part(str: string, order: number)
			local l = text(row, str, 22, fg, TITLE, {
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = order,
			})
			if light then
				new("UIStroke", { Color = Palette.UiRim, Thickness = 1.5 }, l)
			end
		end
		local before = (t:sub(1, s - 1):gsub("%s+$", ""))
		local after = (t:sub(e + 1):gsub("^%s+", ""))
		if before ~= "" then
			part(before, 1)
		end
		local gh = size.Y.Offset > 0 and math.floor(size.Y.Offset * 0.62) or 26
		new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = ICONS,
			ImageRectOffset = ICON.Gems.Min,
			ImageRectSize = ICON.Gems.Max - ICON.Gems.Min,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(math.floor(gh * 1.16), gh),
			LayoutOrder = 2,
		}, row)
		if after ~= "" then
			part(after, 3)
		end
	end
	b.Activated:Connect(onClick)
	return b
end

local function call(action: string, ...: any): (boolean, any)
	local ok, a, b = pcall(ShopCall.InvokeServer, ShopCall, action, ...)
	if not ok then
		return false, nil
	end
	return a, b
end

local function rarityColour(r: string): Color3
	return (Palette :: any)[r] or Palette.Common
end

local function fmtTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = sec // 3600
	local m = (sec % 3600) // 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm %ds", m, sec % 60)
end

-- An item card: coloured well with a big icon, name, sub line, optional badge.
-- What an ability does, in the menus: hover a card on PC, or press and hold one on a touch
-- screen (a normal tap still equips/buys). One tooltip shared by every card.
local tipGui: Frame? = nil
local tipFor: Instance? = nil
local function hideItemTip(owner: Instance?)
	if tipGui and (owner == nil or tipFor == owner) then
		tipGui.Visible = false
		tipFor = nil
	end
end
local function showItemTip(owner: GuiObject, g: any)
	local sg = owner:FindFirstAncestorWhichIsA("ScreenGui")
	if not sg then
		return
	end
	if not tipGui or tipGui.Parent ~= sg then
		if tipGui then
			tipGui:Destroy()
		end
		local t = new("Frame", {
			Name = "ItemTip",
			BackgroundColor3 = Palette.UiInk,
			BackgroundTransparency = 0.08,
			Size = UDim2.fromOffset(260, 74),
			ZIndex = 50,
		}, sg)
		corner(t, 10)
		new("UIStroke", { Color = Palette.UiGold, Thickness = 2 }, t)
		text(t, "", 19, Palette.UiGold, TITLE, {
			Name = "N",
			Size = UDim2.new(1, -20, 0, 22),
			Position = UDim2.fromOffset(10, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 51,
		})
		text(t, "", 15, Palette.UiText, BODY, {
			Name = "D",
			Size = UDim2.new(1, -20, 0, 40),
			Position = UDim2.fromOffset(10, 29),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			ZIndex = 51,
		})
		tipGui = t
	end
	local t = tipGui :: Frame
	local nameL = t:FindFirstChild("N") :: TextLabel
	local descL = t:FindFirstChild("D") :: TextLabel
	nameL.Text = g.name
	descL.Text = g.desc
	-- above the card, kept on screen
	-- the lobby GUI has a UIScale: work in its unscaled units
	local us = sg:FindFirstChildOfClass("UIScale")
	local k = us and us.Scale or 1
	local ap = (owner.AbsolutePosition - sg.AbsolutePosition) / k
	local as = owner.AbsoluteSize / k
	local vp = sg.AbsoluteSize / k
	local x = math.clamp(ap.X + as.X / 2 - 130, 8, vp.X - 268)
	local y = ap.Y - 80
	if y < 8 then
		y = ap.Y + as.Y + 6
	end
	t.Position = UDim2.fromOffset(x, y)
	t.Visible = true
	tipFor = owner
end
itemTip = function(f: GuiObject, g: any)
	f.MouseEnter:Connect(function()
		if not UserInputService.TouchEnabled then
			showItemTip(f, g)
		end
	end)
	f.MouseLeave:Connect(function()
		hideItemTip(f)
	end)
	f.InputBegan:Connect(function(io)
		if io.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local held = true
		local c = io.Changed:Connect(function()
			if io.UserInputState == Enum.UserInputState.End then
				held = false
			end
		end)
		task.delay(0.4, function()
			if held then
				showItemTip(f, g)
			end
		end)
		io:GetPropertyChangedSignal("UserInputState"):Wait()
		c:Disconnect()
		task.delay(1.6, hideItemTip, f)
	end)
end

local function card(
	parent: Instance,
	icon: string,
	name: string,
	sub: string,
	rarity: string,
	badge: string?,
	dim: boolean?
): Frame
	-- each item sits in its own tinted grey box
	local f = new(
		"Frame",
		{ BackgroundColor3 = Palette.UiInk, BackgroundTransparency = 0.9, Size = UDim2.fromOffset(150, 170) },
		parent
	)
	corner(f, 6)
	local well = new("Frame", {
		Name = "Well",
		BackgroundColor3 = rarityWells and rarityColour(rarity) or Palette.UiPaperDim,
		BackgroundTransparency = rarityWells and (dim and 0.7 or 0.45) or (dim and 0.55 or 0.15),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(104, 104),
	}, f)
	corner(well, 6)
	-- abilities show their art from the icon sheet; gem packs show the game's gem icon
	local art = Items.byName(name)
	if art then
		Items.iconInto(well, art.id, 0.86)
		itemTip(f, art)
	elseif string.find(icon, "💎", 1, true) then
		new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = ICONS,
			ImageRectOffset = ICON.Gems.Min,
			ImageRectSize = ICON.Gems.Max - ICON.Gems.Min,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.62, 0.62),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		}, well)
	end
	local nameL = text(f, name, 18, Palette.UiInk, TITLE, {
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.fromOffset(8, 110),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local subL = text(f, sub, 14, Palette.CanopyDeep, BODY, {
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(8, 132),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	-- Lay out to the card's size: the square well fills the room left above the two text lines
	-- and anything a caller adds at the bottom (a buy button, extra lines).
	local mine = { [well] = true, [nameL] = true, [subL] = true }
	local function fit()
		local w, h = f.Size.X.Offset, f.Size.Y.Offset
		if f.AbsoluteSize.X > 0 and w == 0 then
			w, h = f.AbsoluteSize.X, f.AbsoluteSize.Y
		end
		local foot = h
		for _, c in f:GetChildren() do
			if c:IsA("GuiObject") and not mine[c] and c.Position.Y.Offset > 40 then
				foot = math.min(foot, c.Position.Y.Offset + c.Position.Y.Scale * h)
			end
		end
		local textTop = foot - 44
		local side = math.max(20, math.min(w - 12, textTop - 10))
		well.Size = UDim2.fromOffset(side, side)
		nameL.Position = UDim2.fromOffset(8, 6 + side + 4)
		subL.Position = UDim2.fromOffset(8, 6 + side + 26)
	end
	task.defer(fit)
	f:GetPropertyChangedSignal("Size"):Connect(fit)
	f:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	f.ChildAdded:Connect(function()
		task.defer(fit)
	end)
	if badge then
		local b = new("TextLabel", {
			BackgroundColor3 = Palette.CanopyDeep,
			TextColor3 = Palette.UiText,
			Font = BODY,
			TextSize = 13,
			ZIndex = 3,
			Text = " " .. badge .. " ",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			Position = UDim2.fromOffset(6, 6),
		}, f)
		corner(b, 3)
	end
	return f
end

local function blurb(k: Frame, t: string, fromBottom: number)
	text(k, t, 14, Palette.UiInk, BODY, {
		TextTransparency = 0.2,
		Size = UDim2.new(1, -16, 0, 44),
		Position = UDim2.new(0, 8, 1, fromBottom),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
end

local function grid(parent: Instance, cell: Vector2): ScrollingFrame
	local s = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Palette.StoneShadow,
		BorderSizePixel = 0,
	}, parent)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, s)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, s)
	return s
end

-- ---------- panel frame with tabs ----------
local panel: Frame
local tabBar: Frame
local body: Frame
local currentTab: { [string]: string } = {}

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIBase") then
			c:Destroy()
		end
	end
end

local function sectionHead(parent: Instance, title: string, sub: string, pos: UDim2, w: number)
	local h = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, 48), Position = pos }, parent)
	new("Frame", { BackgroundColor3 = Palette.CanopyMid, BorderSizePixel = 0, Size = UDim2.fromOffset(5, 44) }, h)
	text(h, title, 24, Palette.CanopyDeep, TITLE, {
		Size = UDim2.new(1, -14, 0, 26),
		Position = UDim2.fromOffset(14, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	text(h, sub, 15, Palette.UiInk, BODY, {
		TextTransparency = 0.25,
		Size = UDim2.new(1, -14, 0, 18),
		Position = UDim2.fromOffset(14, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return h
end

local function gemChip(parent: Instance, pos: UDim2)
	local chip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(130, 40), Position = pos }, parent)
	text(chip, tostring(profile and profile.gems or 0), 26, Palette.UiText, TITLE, {
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -40, 1, 0),
	})
	new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ICONS,
		ImageRectOffset = ICON.Gems.Min,
		ImageRectSize = ICON.Gems.Max - ICON.Gems.Min,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(34, 30),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
	}, chip)
end

-- A gift box drawn from frames: red box and lid, gold ribbon both ways, a two-loop bow.
local function presentIcon(parent: Instance)
	local holder = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		ZIndex = 3,
	}, parent)
	local function rect(color: Color3, size: UDim2, pos: UDim2, rot: number?, round: number?)
		local f = new("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = size,
			Position = pos,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = rot or 0,
			ZIndex = 3,
		}, holder)
		corner(f, round or 2)
		stroke(f, Palette.UiRim, 1.5)
		return f
	end
	rect(Palette.UiGold, UDim2.fromOffset(9, 9), UDim2.fromOffset(10, 4), 35, 4) -- bow loops
	rect(Palette.UiGold, UDim2.fromOffset(9, 9), UDim2.fromOffset(20, 4), -35, 4)
	rect(Palette.UiDanger, UDim2.fromOffset(22, 15), UDim2.fromOffset(15, 21)) -- box
	rect(Palette.UiDanger, UDim2.fromOffset(26, 7), UDim2.fromOffset(15, 11)) -- lid
	local v = rect(Palette.UiGold, UDim2.fromOffset(5, 22), UDim2.fromOffset(15, 18), 0, 1) -- ribbon
	v:FindFirstChildOfClass("UIStroke"):Destroy()
end

local drawGift: (string, Frame) -> ()
-- the menu Gift was opened from, so its Back tab returns there instead of trapping you
local giftReturn: { name: string, tabs: { string }, draw: (string, Frame) -> () }? = nil
local lastOpen: { name: string, tabs: { string }, draw: (string, Frame) -> () }? = nil
local function openTabs(name: string, tabs: { string }, draw: (string, Frame) -> ())
	if name == "Gift" and lastOpen and lastOpen.name ~= "Gift" then
		giftReturn = lastOpen
	elseif name ~= "Gift" then
		lastOpen = { name = name, tabs = tabs, draw = draw }
	end
	openPanel = name
	panelHolder.Visible = true
	clear(tabBar)
	clear(body)
	local tab = currentTab[name] or tabs[1]
	currentTab[name] = tab
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -300, 1, 0) }, tabBar)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local back = name == "Gift" and giftReturn
	if back then
		local b = new("TextButton", {
			Size = UDim2.fromOffset(0, 44),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Palette.CanopyMid,
			Text = "< Back",
			TextColor3 = Palette.UiText,
			Font = TITLE,
			TextSize = 22,
			LayoutOrder = 0,
			Name = "Tab_Back",
		}, row)
		corner(b, 6)
		stroke(b, Palette.UiRim, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, b)
		b.Activated:Connect(function()
			Sfx.menu()
			openTabs(back.name, back.tabs, back.draw)
		end)
	end
	for i, t in tabs do
		local active = t == tab
		local b = new("TextButton", {
			Size = UDim2.fromOffset(0, 44),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = active and Palette.UiPaper or Palette.CanopyMid,
			Text = t,
			TextColor3 = active and Palette.CanopyDeep or Palette.UiText,
			Font = TITLE,
			TextSize = 22,
			LayoutOrder = i,
			Name = "Tab_" .. t:gsub(" ", ""),
		}, row)
		corner(b, 6)
		stroke(b, Palette.UiRim, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, b)
		b.Activated:Connect(function()
			currentTab[name] = t
			openTabs(name, tabs, draw)
		end)
	end
	-- long tab names on a narrow phone: shrink the tab text until the row fits
	task.defer(function()
		local layout = row:FindFirstChildOfClass("UIListLayout") :: UIListLayout
		local ts = 22
		for _ = 1, 12 do
			task.wait()
			if not row.Parent or layout.AbsoluteContentSize.X <= row.AbsoluteSize.X or ts <= 14 then
				break
			end
			ts -= 1
			for _, b in row:GetChildren() do
				if b:IsA("TextButton") then
					b.TextSize = ts
				end
			end
		end
	end)
	gemChip(tabBar, UDim2.new(1, -250, 0.5, -20))
	local gift = button(
		tabBar,
		"",
		Palette.UiBuy,
		Palette.UiInk,
		UDim2.fromOffset(44, 44),
		UDim2.new(1, -102, 0.5, -22),
		function()
			Sfx.menu()
			openTabs("Gift", { "Gift Gems" }, drawGift)
		end
	)
	if not menuIcon(gift, "Gift", 30, Palette.UiText) then
		presentIcon(gift)
	end
	local close = button(
		tabBar,
		"",
		Palette.UiDanger,
		Palette.UiText,
		UDim2.fromOffset(44, 44),
		UDim2.new(1, -50, 0.5, -22),
		function()
			Lobby.close()
		end
	)
	close.LayoutOrder = 99
	-- a drawn cross (two cream bars with a brown edge), not a letter X
	for _, r in { 45, -45 } do
		local bar = new("Frame", {
			BackgroundColor3 = Palette.UiText,
			BorderSizePixel = 0,
			Size = UDim2.new(0.56, 0, 0, 6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = r,
			ZIndex = 3,
		}, close)
		corner(bar, 3)
		stroke(bar, Palette.UiRim, 1.2)
	end
	task.spawn(function()
		local ok, err = xpcall(draw, debug.traceback, tab, body)
		if not ok then
			warn("[JJ.Lobby] draw failed:", err)
		end
	end)
	renderPanel = function()
		openTabs(name, tabs, draw)
	end
end

function Lobby.close()
	if openPanel then
		Sfx.menu()
	end
	openPanel = nil
	panelHolder.Visible = false
	renderPanel = function() end
end

-- A scrolling page that fills a tab; sections stack down it.
local function scrollPage(parent: Instance): ScrollingFrame
	local s = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Palette.StoneShadow,
		BorderSizePixel = 0,
	}, parent)
	new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, s)
	return s
end

-- A section as a table: a light grey box with a heading and a wrapping grid of cells.
-- Returns the grid to put cells in.
local function tableBox(page: Instance, order: number, title: string, sub: string, cell: Vector2): Frame
	local box = new("Frame", {
		BackgroundColor3 = Palette.UiInk,
		BackgroundTransparency = 0.95,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
	}, page)
	corner(box, 8)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
	}, box)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, box)
	local head = sectionHead(box, title, sub, UDim2.new(), 600)
	head.LayoutOrder = 1
	local g = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	}, box)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, g)
	return g
end

-- A gem pack as an item card (square well with the gem count); `forUser` gifts it.
local function packCard(parent: Instance, pk: any, forUser: any)
	local k = card(parent, "💎", string.format("%d gems", pk.gems), pk.tag or "Gem pack", "Rare", pk.tag)
	button(
		k,
		string.format("R$ %d", pk.robux),
		Palette.UiBuy,
		Palette.UiInk,
		UDim2.new(1, -16, 0, 40),
		UDim2.new(0, 8, 1, -48),
		function()
			if forUser then
				call("GiftTarget", forUser.userId)
			end
			if pk.productId == 0 then
				toastFn(forUser and "Gifting opens soon!" or "Gem packs open soon!")
			else
				game:GetService("MarketplaceService"):PromptProductPurchase(player, pk.productId)
			end
		end
	)
end

-- ---------- roll reel ----------
local reel: Frame

local function showResult(ids: { string })
	clear(reel)
	reel.Visible = true
	local last = ids[#ids]
	local g = Items.get(last)
	local shade = new(
		"Frame",
		{ BackgroundColor3 = Palette.UiInk, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1) },
		reel
	)
	shade.Active = true
	local c = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(820, 420),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	}, reel)
	rarityWells = true
	local left =
		card(c, g.icon, g.name, string.format("%s • %.1f%%", g.rarity, Items.rarityChance(last)), g.rarity, "Owned")
	rarityWells = false
	left.Size = UDim2.fromOffset(240, 300)
	left:FindFirstChildOfClass("Frame").Size = UDim2.new(1, 0, 0, 200)
	for _, l in left:GetChildren() do
		if l:IsA("TextLabel") and l.Position.Y.Offset == 110 then
			l.Position = UDim2.fromOffset(8, 214)
			l.TextSize = 24
		elseif l:IsA("TextLabel") and l.Position.Y.Offset == 132 then
			l.Position = UDim2.fromOffset(8, 244)
			l.TextSize = 15
		end
	end
	local right = new(
		"Frame",
		{ BackgroundColor3 = Palette.UiPaper, Size = UDim2.fromOffset(560, 300), Position = UDim2.fromOffset(260, 0) },
		c
	)
	corner(right, 6)
	new(
		"UIPadding",
		{ PaddingLeft = UDim.new(0, 18), PaddingTop = UDim.new(0, 14), PaddingRight = UDim.new(0, 18) },
		right
	)
	text(
		right,
		"Description",
		18,
		Palette.UiInk,
		TITLE,
		{ Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left }
	)
	text(right, g.desc, 15, Palette.StoneShadow, BODY, {
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 24),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local copies = profile and profile.items[last] or 1
	text(
		right,
		"Mastery",
		18,
		Palette.UiInk,
		TITLE,
		{ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 70), TextXAlignment = Enum.TextXAlignment.Left }
	)
	text(
		right,
		string.format("%d duplicate%s", copies - 1, copies - 1 == 1 and "" or "s"),
		15,
		Palette.StoneShadow,
		BODY,
		{ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 94), TextXAlignment = Enum.TextXAlignment.Left }
	)
	if #ids > 1 then
		local list = {}
		for _, id in ids do
			table.insert(list, Items.get(id).name)
		end
		text(right, "You got: " .. table.concat(list, ", "), 20, Palette.UiInk, BODY, {
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 124),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	local function again(n: number)
		reel.Visible = false
		Lobby.roll(n)
	end
	button(
		right,
		string.format("1 more roll  💎%d", Items.RollPrice),
		Palette.UiBuy,
		Palette.UiInk,
		UDim2.fromOffset(250, 56),
		UDim2.fromOffset(0, 210),
		function()
			again(1)
		end
	)
	button(
		right,
		string.format("10 more rolls  💎%d", Items.Roll10Price),
		Palette.UiBuy,
		Palette.UiInk,
		UDim2.fromOffset(250, 56),
		UDim2.fromOffset(268, 210),
		function()
			again(10)
		end
	)
	local done = button(
		c,
		"Done",
		Palette.UiInk,
		Palette.UiText,
		UDim2.fromOffset(200, 56),
		UDim2.new(0.5, -100, 0, 330),
		function()
			reel.Visible = false
			renderPanel()
		end
	)
	done.Name = "Done"
end

function Lobby.roll(n: number)
	local price = n == 10 and Items.Roll10Price or Items.RollPrice
	if not profile or profile.gems < price then
		toastFn("Not enough gems. Run further or grab a gem pack!")
		return
	end
	local ok, ids = call("Roll", n)
	if not ok or not ids then
		toastFn("Roll failed")
		return
	end
	-- Reel: a long strip of random gadget cards that eases to a stop on the last result.
	clear(reel)
	reel.Visible = true
	local shade = new(
		"Frame",
		{ BackgroundColor3 = Palette.UiInk, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1) },
		reel
	)
	shade.Active = true
	local W, GAP, COUNT, LAND = 220, 18, 46, 40
	local strip = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COUNT * (W + GAP), 330),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, -W / 2, 0.5, 0),
	}, reel)
	local target = ids[#ids]
	for i = 1, COUNT do
		local id = i == LAND and target or Items.Gadgets[math.random(1, #Items.Gadgets)].id
		local g = Items.get(id)
		local owned = profile.items[id] and profile.items[id] > 0
		local c = card(
			strip,
			g.icon,
			g.name,
			string.format("%s • %.1f%%", g.rarity, Items.rarityChance(id)),
			g.rarity,
			owned and "Owned" or "Not owned"
		)
		c.Size = UDim2.fromOffset(W, 300)
		c.Position = UDim2.fromOffset((i - 1) * (W + GAP), 15)
		c:FindFirstChildOfClass("Frame").Size = UDim2.new(1, 0, 0, 210)
		for _, l in c:GetChildren() do
			if l:IsA("TextLabel") and l.Position.Y.Offset == 110 then
				l.Position = UDim2.fromOffset(8, 222)
				l.TextSize = 24
			elseif l:IsA("TextLabel") and l.Position.Y.Offset == 132 then
				l.Position = UDim2.fromOffset(8, 252)
				l.TextSize = 15
			end
		end
	end
	local marker = new("Frame", {
		BackgroundColor3 = Palette.UiGold,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(4, 380),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 5,
	}, reel)
	stroke(marker, Palette.UiRim, 1)
	local jitter = math.random(-W * 0.35, W * 0.35)
	local endX = -((LAND - 1) * (W + GAP)) - W / 2 + jitter
	local tw = TweenService:Create(
		strip,
		TweenInfo.new(4.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, endX, 0.5, 0) }
	)
	tw:Play()
	tw.Completed:Wait()
	task.wait(0.5)
	showResult(ids)
end

-- ---------- Shop ----------
local function drawShop(tab: string, f: Frame)
	if tab == "Daily Shop" then
		local page = scrollPage(f)
		local ok, d = call("Daily")
		local today = tableBox(
			page,
			1,
			"Today",
			ok and ("Leaves in " .. fmtTime(d.endsAt - os.time())) or "",
			Vector2.new(170, 226)
		)
		if ok then
			for _, id in d.ids do
				local c = Items.get(id)
				local owned = profile and profile.cosmetics[id]
				local k = card(today, "", c.name, c.kind .. " • " .. c.rarity, c.rarity, owned and "Owned" or nil)
				button(
					k,
					owned and "Owned" or ("💎 " .. c.price),
					owned and Palette.UiPaperDim or Palette.UiBuy,
					Palette.UiInk,
					UDim2.new(1, -16, 0, 40),
					UDim2.new(0, 8, 1, -48),
					function()
						if owned then
							return
						end
						local bought = call("BuyDaily", id)
						toastFn(bought and ("Bought " .. c.name .. "!") or "Not enough gems")
					end
				)
			end
		end
		local gems = tableBox(page, 2, "Get Gems", "Gem packs (Robux)", Vector2.new(170, 226))
		for _, pk in Items.GemPacks do
			packCard(gems, pk, nil)
		end
	elseif tab == "Item Rolls" then
		rarityWells = true
		local list = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -330, 1, 0),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = Palette.StoneShadow,
			BorderSizePixel = 0,
		}, f)
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		for i = #Items.Rarities, 1, -1 do
			local r = Items.Rarities[i]
			local ownedN, total = 0, 0
			for _, g in Items.Gadgets do
				if g.rarity == r then
					total += 1
					if profile and (profile.items[g.id] or 0) > 0 then
						ownedN += 1
					end
				end
			end
			local sec = new(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 236), LayoutOrder = 6 - i },
				list
			)
			local pityTxt = ""
			if Items.Pity[r] and profile then
				pityTxt = string.format("   •   Guaranteed in %d rolls", Items.Pity[r] - (profile.pity[r] or 0))
			end
			sectionHead(
				sec,
				r,
				string.format("%d%% of rolls • %d/%d owned%s", Items.RarityWeight[r], ownedN, total, pityTxt),
				UDim2.new(),
				560
			)
			local row = new(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 176), Position = UDim2.fromOffset(0, 56) },
				sec
			)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }, row)
			for _, g in Items.Gadgets do
				if g.rarity == r then
					local own = profile and (profile.items[g.id] or 0) > 0
					card(
						row,
						g.icon,
						g.name,
						string.format("%s • %.1f%%", r, Items.rarityChance(g.id)),
						r,
						own and "Owned" or "Not owned",
						not own
					)
				end
			end
		end
		rarityWells = false
		local side = new("Frame", {
			BackgroundColor3 = Palette.UiPaper,
			Size = UDim2.new(0, 310, 0, 300),
			Position = UDim2.new(1, -310, 0, 0),
		}, f)
		corner(side, 6)
		stroke(side, Palette.UiInk, 2)
		new(
			"UIPadding",
			{ PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12) },
			side
		)
		text(
			side,
			"10 Rolls",
			26,
			Palette.UiInk,
			TITLE,
			{ Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left }
		)
		text(
			side,
			string.format("10 for the price of %d", Items.Roll10Price // Items.RollPrice),
			15,
			Palette.StoneShadow,
			BODY,
			{ Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Right }
		)
		local y = 40
		for _, r in { "Rare", "Epic", "Mythic" } do
			local left = Items.Pity[r] - (profile and profile.pity[r] or 0)
			text(side, string.format("Guaranteed %s in %d", r, left), 14, Palette.StoneShadow, BODY, {
				Size = UDim2.new(1, 0, 0, 18),
				Position = UDim2.fromOffset(0, y),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			local back = new("Frame", {
				BackgroundColor3 = Palette.UiPaperDim,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 8),
				Position = UDim2.fromOffset(0, y + 20),
			}, side)
			corner(back, 4)
			local fill = new("Frame", {
				BackgroundColor3 = rarityColour(r),
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1 - left / Items.Pity[r], 1),
			}, back)
			corner(fill, 4)
			y += 38
		end
		local r10 = button(
			side,
			"10 Rolls   💎 " .. Items.Roll10Price,
			Palette.UiBuy,
			Palette.UiInk,
			UDim2.new(1, 0, 0, 52),
			UDim2.fromOffset(0, y + 4),
			function()
				Lobby.roll(10)
			end
		)
		r10.Name = "Roll10"
		button(
			side,
			"1 Roll   💎 " .. Items.RollPrice,
			Palette.UiInk,
			Palette.UiText,
			UDim2.new(1, 0, 0, 46),
			UDim2.fromOffset(0, y + 66),
			function()
				Lobby.roll(1)
			end
		)
	elseif tab == "Passes" then
		local page = scrollPage(f)
		local box = tableBox(page, 1, "Passes", "Yours forever. Coming soon.", Vector2.new(190, 260))
		for _, ps in
			{
				{ "VIP", "VIP title, gold trail and one more loadout slot" },
				{ "2x Gems", "Double the gems from every run" },
				{ "Lucky Rolls", "Mythic guaranteed in 50 rolls, not 80" },
			}
		do
			local k = card(box, "", ps[1], "Game pass", "Common")
			blurb(k, ps[2], -100)
			button(
				k,
				"Soon",
				Palette.UiPaperDim,
				Palette.UiInk,
				UDim2.new(1, -16, 0, 40),
				UDim2.new(0, 8, 1, -48),
				function() end
			)
		end
	end
end

-- ---------- Gift: buy a gem pack for anyone (someone here, or any username) ----------
local giftFor: { userId: number, name: string }? = nil
drawGift = function(_: string, f: Frame)
	local page = scrollPage(f)
	local who =
		tableBox(page, 1, "Who gets it?", "Pick someone here, or search any Roblox username", Vector2.new(170, 48))
	local box = new("TextBox", {
		BackgroundColor3 = Palette.UiPaper,
		TextColor3 = Palette.UiInk,
		PlaceholderColor3 = Palette.StoneShadow,
		PlaceholderText = "Username",
		Text = "",
		ClearTextOnFocus = false,
		Font = BODY,
		TextSize = 18,
		LayoutOrder = -2,
	}, who)
	corner(box, 8)
	stroke(box, Palette.UiRim, 2)
	local function search()
		local name = (box.Text:gsub("%s", ""))
		if name == "" then
			return
		end
		task.spawn(function()
			local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
			if not ok or not id then
				toastFn("No player called " .. name)
				return
			end
			if id == player.UserId then
				toastFn("You can't gift yourself")
				return
			end
			local ok2, real = pcall(Players.GetNameFromUserIdAsync, Players, id)
			giftFor = { userId = id, name = ok2 and real or name }
			renderPanel()
		end)
	end
	box.FocusLost:Connect(function(enter)
		if enter then
			search()
		end
	end)
	button(who, "Search", Palette.UiBuy, Palette.UiInk, UDim2.new(), UDim2.new(), search).LayoutOrder = -1
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local picked = giftFor and giftFor.userId == other.UserId
			button(
				who,
				other.DisplayName,
				picked and Palette.UiGold or Palette.UiPaperDim,
				Palette.UiInk,
				UDim2.new(),
				UDim2.new(),
				function()
					giftFor = { userId = other.UserId, name = other.DisplayName }
					renderPanel()
				end
			)
		end
	end
	if giftFor then
		local packs = tableBox(page, 2, "Gift to " .. giftFor.name, "Gem packs (Robux)", Vector2.new(170, 226))
		for _, pk in Items.GemPacks do
			packCard(packs, pk, giftFor)
		end
	end
end

-- ---------- Inventory ----------
local function tapCard(k: Frame, fn: () -> ())
	local b = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5 }, k)
	b.Activated:Connect(fn)
end
local function wellText(k: Frame, t: string, size: number)
	local w = k:FindFirstChild("Well")
	if w then
		text(w, t, size, Palette.CanopyDeep, TITLE)
	end
end
local function wellIcon(k: Frame, r: Rect)
	local w = k:FindFirstChild("Well")
	if w then
		new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = ICONS,
			ImageRectOffset = r.Min,
			ImageRectSize = r.Max - r.Min,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.62, 0.62),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		}, w)
	end
end

local function cosmeticTab(kind: string, f: Frame)
	local page = scrollPage(f)
	local equipped = profile and profile.equipped[kind]
	local eq = equipped and Items.get(equipped)
	local hint = kind == "Emote" and "Press G in the lobby to play it" or "What everyone sees on you"
	local top = tableBox(page, 1, "Equipped", hint, Vector2.new(150, 180))
	local ek = card(top, "", eq and eq.name or "Nothing yet", eq and eq.rarity or "Pick one below", "Common")
	wellText(ek, eq and "" or "+", 40)
	local ownedN, total = 0, 0
	for _, c in Items.Cosmetics do
		if c.kind == kind then
			total += 1
			if profile and profile.cosmetics[c.id] then
				ownedN += 1
			end
		end
	end
	local g = tableBox(
		page,
		2,
		"Your " .. kind .. "s",
		string.format("%d of %d owned. Tap one to wear it.", ownedN, total),
		Vector2.new(150, 180)
	)
	if kind == "Trail" then
		local none = card(g, "", "No trail", "Free", "Common", not equipped and "Equipped" or nil)
		tapCard(none, function()
			call("Equip", "Trail", "")
		end)
	end
	for _, c in Items.Cosmetics do
		if c.kind == kind then
			local own = profile and profile.cosmetics[c.id]
			local badge = equipped == c.id and "Equipped" or (not own and "Locked" or nil)
			local sub = own and c.rarity or (c.unlock and c.unlock.text or "In the Daily Shop")
			local k = card(g, "", c.name, sub, c.rarity, badge, not own)
			if own then
				tapCard(k, function()
					call("Equip", kind, c.id)
				end)
			end
		end
	end
end

local function drawInventory(tab: string, f: Frame)
	if tab == "Gadgets" then
		local page = scrollPage(f)
		local loadout = profile and profile.loadout or {}
		local lb = tableBox(
			page,
			1,
			"Loadout",
			string.format("%d of %d slots. Mystery boxes in a run hand you one of these.", #loadout, Items.LoadoutSize),
			Vector2.new(150, 180)
		)
		for i = 1, Items.LoadoutSize do
			local id = loadout[i]
			if id then
				local g = Items.get(id)
				local k = card(lb, g.icon, g.name, "Tap to unequip", g.rarity, "Slot " .. i)
				tapCard(k, function()
					local nl = table.clone(loadout)
					table.remove(nl, i)
					if #nl == 0 then
						toastFn("Keep at least one gadget")
						return
					end
					call("Loadout", nl)
				end)
			else
				local k = card(lb, "", "Empty slot", "Choose a gadget below", "Common", nil, true)
				wellText(k, "+", 44)
			end
		end
		local any = false
		for _, gd in Items.Gadgets do
			if (profile and profile.items[gd.id] or 0) > 0 then
				any = true
			end
		end
		local g = tableBox(
			page,
			2,
			"Your gadgets",
			any and "Tap one to add it to your loadout" or "Roll in the Shop to get your first gadget",
			Vector2.new(150, 180)
		)
		for _, gd in Items.Gadgets do
			local n = profile and profile.items[gd.id] or 0
			if n > 0 then
				local inL = table.find(loadout, gd.id) ~= nil
				local k = card(
					g,
					gd.icon,
					gd.name,
					n > 1 and string.format("%s  x%d", gd.rarity, n) or gd.rarity,
					gd.rarity,
					inL and "Equipped" or nil
				)
				tapCard(k, function()
					if inL then
						return
					end
					local nl = table.clone(loadout)
					if #nl >= Items.LoadoutSize then
						table.remove(nl, 1)
					end
					table.insert(nl, gd.id)
					call("Loadout", nl)
				end)
			end
		end
	elseif tab == "Achievements" then
		local page = scrollPage(f)
		local wearing = profile and profile.equipped.Title
		local done, total = 0, 0
		for _, c in Items.Cosmetics do
			if c.kind == "Title" and c.unlock then
				total += 1
				if profile and profile.cosmetics[c.id] then
					done += 1
				end
			end
		end
		local ab = tableBox(
			page,
			1,
			"Achievements",
			string.format("%d of %d earned. Each pays gems and a title; tap an earned one to wear it.", done, total),
			Vector2.new(170, 236)
		)
		for _, c in Items.Cosmetics do
			if c.kind ~= "Title" then
				continue
			end
			local own = profile and profile.cosmetics[c.id]
			local u = c.unlock
			local sub, badge
			if not u then
				sub = "Starter title"
			elseif own then
				sub = u.text .. "  - done"
			else
				local have = profile
						and (u.kind == "level" and profile.level or u.kind == "rolls" and profile.rolls or profile.best)
					or 0
				sub = string.format("%s  (%d/%d)", u.text, math.min(have, u.n), u.n)
			end
			if wearing == c.id then
				badge = "Wearing"
			elseif u then
				badge = string.format("+%d gems", Items.AchievementGems[c.rarity] or 0)
			end
			local k = card(ab, "", c.name, sub, c.rarity, badge, not own)
			wellText(k, own and "★" or "?", 40)
			if own then
				tapCard(k, function()
					call("Equip", "Title", c.id)
				end)
			end
		end
		local rb = tableBox(page, 2, "Best runs", "Choose which best run floats above your head", Vector2.new(170, 236))
		for _, m in Items.Modes do
			local best = profile and profile.records[m.id] or 0
			local shown = profile and profile.showcase == m.id
			local sub = best > 0 and "Your best run" or (m.live and "Finish a run to set one" or "Opens soon")
			local k = card(rb, "", m.name, sub, "Common", shown and "Showing" or nil, not m.live)
			wellText(k, best > 0 and string.format("%d m", best) or "-", best > 0 and 30 or 40)
			if m.live then
				button(
					k,
					shown and "Showing" or "Show",
					shown and Palette.UiPaperDim or Palette.UiBuy,
					Palette.UiInk,
					UDim2.new(1, -16, 0, 40),
					UDim2.new(0, 8, 1, -48),
					function()
						call("Showcase", m.id)
					end
				)
			end
		end
		tableBox(
			page,
			3,
			string.format("Level %d", profile and profile.level or 1),
			string.format(
				"%d daily check-ins  |  %d rolls",
				profile and profile.checkIns or 0,
				profile and profile.rolls or 0
			),
			Vector2.new(0, 0)
		)
	else
		cosmeticTab(tab:sub(1, -2), f)
	end
end

-- ---------- Modes ----------
local function drawModes(_: string, f: Frame)
	local page = scrollPage(f)
	local box = tableBox(
		page,
		1,
		"Choose your expedition",
		"Standard is open now. More modes are on the way.",
		Vector2.new(200, 280)
	)
	for _, m in Items.Modes do
		local k = card(
			box,
			"",
			m.name,
			m.live and "Open now" or "Coming soon",
			"Common",
			m.live and "Selected" or nil,
			not m.live
		)
		if m.live then
			wellIcon(k, ICON.Distance)
		else
			wellText(k, "?", 44)
		end
		blurb(k, m.blurb, m.live and -96 or -52)
		if m.live then
			button(
				k,
				"PLAY",
				Palette.UiBuy,
				Palette.UiInk,
				UDim2.new(1, -16, 0, 40),
				UDim2.new(0, 8, 1, -48),
				function()
					remotes.Queue:FireServer(true)
					Lobby.close()
				end
			)
		end
	end
end

-- ---------- Settings ----------
local function drawSettings(_: string, f: Frame)
	local page = scrollPage(f)
	local function row(order: number, d: any): Frame
		local r = new("Frame", {
			BackgroundColor3 = Palette.UiPaper,
			Size = UDim2.new(1, 0, 0, 74),
			LayoutOrder = order,
		}, page)
		corner(r, 8)
		stroke(r, Palette.UiRim, 2)
		text(r, d.name, 24, Palette.UiInk, TITLE, {
			Size = UDim2.new(1, -300, 0, 30),
			Position = UDim2.fromOffset(16, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		text(r, d.hint, 17, Palette.CanopyDeep, BODY, {
			Size = UDim2.new(1, -300, 0, 24),
			Position = UDim2.fromOffset(16, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		return r
	end
	local order = 0
	for _, d in SettingsDefs.list do
		if d.touchOnly and not UserInputService.TouchEnabled then
			continue
		end
		order += 1
		local r = row(order, d)
		if d.slider then
			-- drag anywhere on the bar (mouse or finger); it snaps to 10% steps, so on a phone
			-- each notch is one clear 10% change. Volume follows live; saved on release.
			local STEP = SettingsDefs.STEP
			local track = new("TextButton", {
				Name = "Slider_" .. d.id,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Palette.UiPaperDim,
				Size = UDim2.fromOffset(190, 14),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -96, 0.5, 0),
			}, r)
			corner(track, 7)
			stroke(track, Palette.UiRim, 2)
			-- a bigger invisible grab area round the thin bar, for thumbs
			local grab = new("TextButton", {
				Text = "",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 28, 0, 52),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				ZIndex = 4,
			}, track)
			local fill = new("Frame", {
				BackgroundColor3 = Palette.CanopyMid,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
			}, track)
			corner(fill, 7)
			local knob = new("Frame", {
				BackgroundColor3 = Palette.UiGold,
				Size = UDim2.fromOffset(30, 30),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				ZIndex = 3,
			}, track)
			corner(knob, 15)
			stroke(knob, Palette.UiRim, 2)
			local value = text(r, "", 22, Palette.UiInk, TITLE, {
				Size = UDim2.fromOffset(70, 44),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -16, 0.5, 0),
			})
			local function show()
				local v = Settings.get(d.id)
				fill.Size = UDim2.fromScale(v / 100, 1)
				knob.Position = UDim2.fromScale(v / 100, 0.5)
				value.Text = if v == 0 then "Off" else v .. "%"
			end
			local dragging: InputObject? = nil
			local function at(x: number)
				local u = (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
				Settings.preview(d.id, math.clamp(math.floor(u * 100 / STEP + 0.5) * STEP, 0, 100))
				show()
			end
			grab.InputBegan:Connect(function(io)
				if
					io.UserInputType == Enum.UserInputType.MouseButton1
					or io.UserInputType == Enum.UserInputType.Touch
				then
					dragging = io
					at(io.Position.X)
				end
			end)
			local moved = UserInputService.InputChanged:Connect(function(io)
				if not dragging then
					return
				end
				if
					io == dragging
					or (
						io.UserInputType == Enum.UserInputType.MouseMovement
						and (dragging :: InputObject).UserInputType == Enum.UserInputType.MouseButton1
					)
				then
					at(io.Position.X)
				end
			end)
			local ended = UserInputService.InputEnded:Connect(function(io)
				if io == dragging then
					dragging = nil
					Settings.commit(d.id)
				end
			end)
			-- the panel is redrawn on every open: drop these with it
			track.Destroying:Connect(function()
				moved:Disconnect()
				ended:Disconnect()
			end)
			show()
		elseif d.steps then
			local steps = d.steps :: { string }
			local value = text(r, "", 22, Palette.UiInk, TITLE, {
				Size = UDim2.fromOffset(130, 44),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -66, 0.5, 0),
			})
			local minus, plus
			local function show()
				local v = Settings.get(d.id)
				value.Text = steps[v]
				minus.AutoButtonColor = v > 1
				minus.BackgroundTransparency = v > 1 and 0 or 0.5
				plus.BackgroundTransparency = v < #steps and 0 or 0.5
			end
			local function step(by: number)
				local v = math.clamp(Settings.get(d.id) + by, 1, #steps)
				Settings.set(d.id, v)
				show()
			end
			minus = button(
				r,
				"-",
				Palette.UiInk,
				Palette.UiText,
				UDim2.fromOffset(48, 44),
				UDim2.new(1, -244, 0.5, -22),
				function()
					step(-1)
				end
			)
			plus = button(
				r,
				"+",
				Palette.UiInk,
				Palette.UiText,
				UDim2.fromOffset(48, 44),
				UDim2.new(1, -62, 0.5, -22),
				function()
					step(1)
				end
			)
			minus.TextSize, plus.TextSize = 30, 30
			minus.Name, plus.Name = "Less_" .. d.id, "More_" .. d.id
			show()
		else
			local t: TextButton
			local function show()
				local on = Settings.get(d.id)
				t.Text = on and "ON" or "OFF"
				t.BackgroundColor3 = on and Palette.CanopyMid or Palette.UiPaperDim
				t.TextColor3 = on and Palette.UiText or Palette.UiInk
			end
			t = button(
				r,
				"",
				Palette.UiInk,
				Palette.UiText,
				UDim2.fromOffset(130, 44),
				UDim2.new(1, -144, 0.5, -22),
				function()
					Settings.set(d.id, not Settings.get(d.id))
					show()
				end
			)
			t.Name = "Toggle_" .. d.id
			show()
		end
	end
	local note =
		text(page, "Master volume, graphics quality and camera are in the Roblox menu.", 17, Palette.UiPaper, BODY, {
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = 99,
		})
	new("UIStroke", { Color = Palette.UiRim, Thickness = 1.2 }, note)
end

local function toggle(name: string)
	Sfx.menu()
	if openPanel == name then
		Lobby.close()
	elseif name == "Shop" then
		openTabs("Shop", { "Daily Shop", "Item Rolls", "Passes" }, drawShop)
	elseif name == "Inventory" then
		openTabs("Inventory", { "Gadgets", "Achievements", "Emotes", "Trails" }, drawInventory)
	elseif name == "Modes" then
		openTabs("Modes", { "Expeditions" }, drawModes)
	elseif name == "Settings" then
		openTabs("Settings", { "Settings" }, drawSettings)
	end
end

Lobby.toggle = toggle

-- ---------- emote ----------
local function playEmote()
	local eq = profile and profile.equipped.Emote
	local c = eq and Items.get(eq)
	local char = player.Character
	local animate = char and char:FindFirstChild("Animate")
	local pe = animate and animate:FindFirstChild("PlayEmote")
	if c and c.emote and pe and pe:IsA("BindableFunction") then
		pcall(pe.Invoke, pe, c.emote)
	end
end

-- ---------- build ----------
function Lobby.init(toast: (string) -> ())
	toastFn = toast
	gui = new("ScreenGui", {
		Name = "JJLobby",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 5,
	}, player:WaitForChild("PlayerGui"))

	root = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	local scale = new("UIScale", {}, gui)
	-- Screen size, except on very long phones (wider than 2:1, e.g. the S22/S25 Ultra and A06)
	-- where the notch and rounded corners eat the edges: there use the safe area instead.
	local function area(): Vector2
		local v = workspace.CurrentCamera.ViewportSize
		local s = gui.AbsoluteSize
		if v.Y > 0 and v.X / v.Y > 2 and s.X > 1 then
			return s
		end
		return v
	end
	local function rescale()
		local v = area()
		scale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 760), 0.5, 1.2)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

	-- Top right: level bar + gems
	local lv = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(280, 64),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
	}, root)
	casing(lv, "woodTop", {
		Size = UDim2.new(1, 24, 1, 22),
		Position = UDim2.fromOffset(-12, -10),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(60, 30, 240, 62),
		SliceScale = 0.6,
	})
	local lvText = text(lv, "Level 1", 27, Palette.UiPaper, TITLE, {
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local xpText = text(lv, "", 21, Palette.UiPaper, TITLE, {
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local xpBack = new("Frame", {
		BackgroundColor3 = Palette.UiInk,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 0, 12),
		Position = UDim2.fromOffset(12, 40),
	}, lv)
	local xpFill =
		new("Frame", { BackgroundColor3 = Palette.UiGold, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, xpBack)
	local gemBox = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(150, 46),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 84),
	}, root)
	casing(gemBox, "woodBot", {
		Size = UDim2.new(1, 20, 1, 18),
		Position = UDim2.fromOffset(-10, -8),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(50, 26, 217, 61),
		SliceScale = 0.55,
	})
	new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ICONS,
		ImageRectOffset = ICON.Gems.Min,
		ImageRectSize = ICON.Gems.Max - ICON.Gems.Min,
		Size = UDim2.fromOffset(34, 30),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
	}, gemBox)
	local gemText = text(
		gemBox,
		"0",
		24,
		Palette.UiPaper,
		TITLE,
		{ Size = UDim2.new(1, -54, 1, 0), Position = UDim2.fromOffset(48, 0) }
	)

	-- Settings: a wooden gear button beside the gems
	local gearBox = new("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromOffset(46, 46),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -182, 0, 84),
		Name = "SettingsButton",
	}, root)
	casing(gearBox, "woodBot", {
		Size = UDim2.new(1, 20, 1, 18),
		Position = UDim2.fromOffset(-10, -8),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(50, 26, 217, 61),
		SliceScale = 0.55,
	})
	do -- the gear: four crossed bars for teeth, a disc over them, a dark hole in the middle
		for _, r in { 0, 45, 90, 135 } do
			local tooth = new("Frame", {
				BackgroundColor3 = Palette.UiPaper,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(30, 8),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Rotation = r,
				ZIndex = 2,
			}, gearBox)
			corner(tooth, 2)
		end
		local disc = new("Frame", {
			BackgroundColor3 = Palette.UiPaper,
			Size = UDim2.fromOffset(22, 22),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 3,
		}, gearBox)
		corner(disc, 11)
		local hole = new("Frame", {
			BackgroundColor3 = Palette.UiRim,
			Size = UDim2.fromOffset(9, 9),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 4,
		}, gearBox)
		corner(hole, 5)
	end
	gearBox.Activated:Connect(function()
		toggle("Settings")
	end)

	-- Top centre: mode + countdown
	local cd = new("Frame", {
		BackgroundColor3 = Palette.UiPaper,
		Size = UDim2.fromOffset(250, 84),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
	}, root)
	corner(cd, 6)
	stroke(cd, Palette.UiInk, 2)
	local modeText = text(
		cd,
		"STAMPEDE",
		18,
		Palette.StoneShadow,
		TITLE,
		{ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 6) }
	)
	local cdText = text(
		cd,
		"0:12",
		40,
		Palette.UiInk,
		TITLE,
		{ Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 30) }
	)

	-- Bottom: hint, PLAY, bar
	local hint = new("TextLabel", {
		BackgroundColor3 = Palette.UiPaper,
		TextColor3 = Palette.UiInk,
		Font = TITLE,
		TextSize = 18,
		Text = "Run further, earn more",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -180),
	}, root)
	corner(hint, 4)
	local hintPad = new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 44) }, hint)
	local hintGem = new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ICONS,
		ImageRectOffset = ICON.Gems.Min,
		ImageRectSize = ICON.Gems.Max - ICON.Gems.Min,
		Size = UDim2.fromOffset(26, 23),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0.5, 0),
	}, hint)
	local play = button(
		root,
		"PLAY",
		Palette.UiBuy,
		Palette.UiInk,
		UDim2.fromOffset(240, 72),
		UDim2.new(0.5, -120, 1, -170),
		function() end
	)
	play.TextSize = 40
	for _, c in play:GetChildren() do
		if c:IsA("UIStroke") or c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	play.BackgroundColor3 = Palette.CanopyMid
	play.TextColor3 = Palette.UiText
	stroke(play, Palette.UiPaper, 3)
	new("UIStroke", {
		Color = Palette.UiRim,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, play)
	new(
		"UIGradient",
		{ Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)), Rotation = 90 },
		play
	)
	-- the play triangle, drawn as 1-px rows: each row is as long as the triangle is wide there
	play.Text = "   PLAY"
	local TRI_W, TRI_H = 24, 28
	local tri = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(TRI_W, TRI_H),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, -64, 0.5, 0),
		ZIndex = 3,
	}, play)
	for y = 0, TRI_H - 1 do
		local w = TRI_W * (1 - math.abs((y + 0.5) - TRI_H / 2) / (TRI_H / 2))
		new("Frame", {
			BackgroundColor3 = Palette.UiText,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(math.max(w, 1), 1),
			Position = UDim2.fromOffset(0, y),
			ZIndex = 3,
		}, tri)
	end
	local function playIcon()
		tri.Visible = play.Text ~= "READY"
		play.Text = tri.Visible and "   PLAY" or "READY"
	end
	play.Activated:Connect(function()
		if not player:GetAttribute("Queued") then
			Sfx.start() -- joining only; leaving the queue gets the plain click
		end
		remotes.Queue:FireServer(not player:GetAttribute("Queued"))
	end)

	local bar = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(780, 70),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
	}, root)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 16),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, bar)
	local keyMap = { Shop = Enum.KeyCode.Z, Inventory = Enum.KeyCode.X, Modes = Enum.KeyCode.C }
	for i, spec in
		{
			{ "Shop", "Shop", Palette.Rare },
			{ "Inventory", "Inventory", Palette.UiPaperDim },
			{ "Modes", "Modes", Palette.Epic },
		}
	do
		local b = button(
			bar,
			spec[2],
			Palette.UiPaper,
			Palette.UiInk,
			UDim2.fromOffset(240, 62),
			UDim2.new(),
			function()
				toggle(spec[1])
			end
		)
		b.LayoutOrder = i
		-- wood-and-stone casing; the stone face is painted in the button's own colour
		b.BackgroundTransparency = 1
		b.Text = ""
		local cornerR = b:FindFirstChildOfClass("UICorner")
		if cornerR then
			cornerR:Destroy()
		end
		casing(b, "button", {
			ZIndex = 1,
			Size = UDim2.new(1, 16, 1, 16),
			Position = UDim2.fromOffset(-8, -8),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(40, 32, 152, 86),
			SliceScale = 0.5,
		})
		local face = new("Frame", {
			ZIndex = 2,
			BackgroundColor3 = spec[3],
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -20, 1, -18),
			Position = UDim2.fromOffset(10, 9),
		}, b)
		corner(face, 4)
		new(
			"UIGradient",
			{ Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)), Rotation = 90 },
			face
		)
		for _, st in b:GetChildren() do
			if st:IsA("UIStroke") or st:IsA("UIGradient") then
				st:Destroy() -- the wood casing is the edge
			end
		end
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, b)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		local ic = menuIcon(row, spec[1], 26, Palette.UiInk)
		if ic then
			ic.Size = UDim2.fromOffset(30, 26)
			ic.LayoutOrder = 1
		end
		local label = text(row, spec[2], 28, Palette.UiInk, TITLE, {
			ZIndex = 3,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
		})
		new("UIStroke", { Color = Palette.UiPaper, Thickness = 1.5 }, label)
		if not UserInputService.TouchEnabled then
			local key = new("TextLabel", {
				BackgroundColor3 = Palette.UiPaper,
				TextColor3 = Palette.UiInk,
				Font = TITLE,
				TextSize = 18,
				Text = keyMap[spec[1]].Name,
				Size = UDim2.fromOffset(28, 26),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 0),
				ZIndex = 4,
			}, b)
			corner(key, 3)
		end
	end

	-- Bottom left: Invite Friends (Roblox's invite prompt) with the friend boost above it.
	-- Each friend in the same server adds +10% run gems (server/FriendBoost), up to +30%.
	do
		local inv = new("TextButton", {
			Name = "InviteButton",
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromOffset(196, 62),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 22, 1, -22),
		}, root)
		casing(inv, "button", {
			ZIndex = 1,
			Size = UDim2.new(1, 16, 1, 16),
			Position = UDim2.fromOffset(-8, -8),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(40, 32, 152, 86),
			SliceScale = 0.5,
		})
		local face = new("Frame", {
			ZIndex = 2,
			BackgroundColor3 = Palette.UiGold,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -20, 1, -18),
			Position = UDim2.fromOffset(10, 9),
		}, inv)
		corner(face, 4)
		new(
			"UIGradient",
			{ Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)), Rotation = 90 },
			face
		)
		local label = text(inv, "Invite Friends", 25, Palette.UiInk, TITLE, { ZIndex = 3 })
		new("UIStroke", { Color = Palette.UiPaper, Thickness = 1.5 }, label)
		-- the boost chip, a paper tag pinned above the button
		local chip = new("Frame", {
			BackgroundColor3 = Palette.UiPaper,
			Size = UDim2.fromOffset(196, 30),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 0, -12),
			ZIndex = 3,
		}, inv)
		corner(chip, 6)
		stroke(chip, Palette.UiRim, 2)
		local chipText = text(
			chip,
			"",
			17,
			Palette.CanopyDeep,
			TITLE,
			{ ZIndex = 4, TextScaled = true, Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4) }
		)
		new("UITextSizeConstraint", { MaxTextSize = 17 }, chipText)
		local function showBoost()
			local pct = player:GetAttribute("FriendBoost") or 0
			chipText.Text = if pct > 0
				then string.format("Friend boost +%d%%", pct)
				else "+10% gems per friend, up to 100%"
			chip.BackgroundColor3 = if pct > 0 then Palette.UiGold else Palette.UiPaper
		end
		showBoost()
		player:GetAttributeChangedSignal("FriendBoost"):Connect(showBoost)
		inv.Activated:Connect(function()
			Sfx.menu()
			local SocialService = game:GetService("SocialService")
			local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
			if ok and can then
				pcall(SocialService.PromptGameInvite, SocialService, player)
			elseif toastFn then
				toastFn("Invites aren't available on this account")
			end
		end)
	end

	-- Panels + reel
	panelHolder =
		new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 }, gui)
	-- the PLAY button and its hint sit mid-screen: out of the way while a menu is open
	panelHolder:GetPropertyChangedSignal("Visible"):Connect(function()
		local open = panelHolder.Visible
		play.Visible = not open
		hint.Visible = not open
		-- the menu has its own gem count: the top widgets step aside so it gets the height
	end)
	-- the panel fits between the top UI (level bar + gems box: ~130) and the bottom buttons
	-- (~100), on PC and phone alike, so nothing ever covers it
	panel = new("Frame", {
		BackgroundColor3 = Palette.UiPaper,
		Size = UDim2.new(0, 1080, 1, -(PANEL_TOP + PANEL_BOTTOM)),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, PANEL_TOP),
	}, panelHolder)
	local function fitPanel()
		local v = area()
		local sc = math.max(scale.Scale, 0.01)
		panel.Size = UDim2.new(0, math.min(1080, v.X / sc - 32), 1, -(PANEL_TOP + PANEL_BOTTOM))
	end
	fitPanel()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel)
	scale:GetPropertyChangedSignal("Scale"):Connect(fitPanel)
	panel.BackgroundTransparency = 1
	casing(panel, "parchment", {
		Size = UDim2.new(1, 56, 1, 56),
		Position = UDim2.fromOffset(-28, -28),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(56, 52, 206, 276),
		SliceScale = 0.75,
	})
	tabBar = new("Frame", {
		BackgroundColor3 = Palette.CanopyDeep,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 0, 60),
		Position = UDim2.fromOffset(12, 10),
	}, panel)
	corner(tabBar, 10)
	stroke(tabBar, Palette.UiRim, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, tabBar)
	body = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -44, 1, -98),
		Position = UDim2.fromOffset(22, 82),
		ClipsDescendants = true,
	}, panel)
	reel = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		ClipsDescendants = true,
	}, gui)

	-- Gadget slots during a run (and the countdown): bottom centre on every device, clear of the
	-- phone arrows (bottom-left) and Jump/Slide (bottom-right)
	-- touch: bigger, so a thumb lands on them reliably (tablets bigger still)
	local SLOT = 96
	if UserInputService.TouchEnabled then
		local v = workspace.CurrentCamera.ViewportSize
		SLOT = if math.min(v.X, v.Y) < 500 then 108 else 124
	end
	local slots = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(SLOT * 2 + 20, SLOT + 4),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Visible = false,
	}, gui)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 16),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}, slots)
	local slotButtons = {}
	local slotKeys = { "Q", "E" }
	local function useSlot(i: number)
		if player:GetAttribute("Gadget" .. i) then
			Sfx.play("Gadget")
			remotes.UseGadget:FireServer(i)
		end
	end
	for i = 1, Items.SlotCount do
		-- same look as the run buttons (client/ActionButton); the gadget's icon is the button text
		local b, setPressed = ActionButton.make(slots, SLOT, "")
		b.TextScaled = true
		b.ZIndex = 5
		b.TextColor3 = Palette.UiText
		b.FontFace = TITLE
		b.Activated:Connect(function()
			useSlot(i)
		end)
		b.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				setPressed(true)
			end
		end)
		b.InputEnded:Connect(function()
			setPressed(false)
		end)
		local k = text(
			b,
			slotKeys[i],
			14,
			Palette.UiGold,
			TITLE,
			{ Size = UDim2.fromOffset(20, 18), Position = UDim2.fromOffset(4, 2) }
		)
		k.Visible = not UserInputService.TouchEnabled
		slotButtons[i] = b
	end

	-- What an ability does: a short card above the slots. On PC it shows while you hover a slot;
	-- on every device it shows for a few seconds when an ability lands in a slot, so phone players
	-- learn it without a long-press slowing down the tap that fires it.
	local tip = new("Frame", {
		BackgroundColor3 = Palette.UiInk,
		BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.fromOffset(340, 58),
		Visible = false,
		ZIndex = 8,
	}, slots)
	corner(tip, 10)
	new("UIStroke", { Color = Palette.UiGold, Thickness = 2 }, tip)
	local tipName = text(tip, "", 20, Palette.UiGold, TITLE, {
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	})
	local tipDesc = text(tip, "", 15, Palette.UiText, BODY, {
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 27),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = 9,
	})
	local tipToken = 0
	local hovered: number? = nil
	local function showTip(i: number?, secs: number?)
		tipToken += 1
		local id = i and player:GetAttribute("Gadget" .. i)
		local g = id and Items.get(id)
		if not g then
			tip.Visible = false
			return
		end
		tipName.Text = g.name
		tipDesc.Text = g.desc
		tip.Visible = true
		if secs then
			local my = tipToken
			task.delay(secs, function()
				if tipToken == my and hovered == nil then
					tip.Visible = false
				end
			end)
		end
	end
	for i, b in slotButtons do
		b.MouseEnter:Connect(function()
			if UserInputService.TouchEnabled then
				return
			end
			hovered = i
			showTip(i)
		end)
		b.MouseLeave:Connect(function()
			if hovered == i then
				hovered = nil
				showTip(nil)
			end
		end)
	end

	-- Getting a gadget, in the spirit of Mario Kart's item box: the ? box pops up on screen with
	-- the pickup sound, shrinks into the slot it fills, then the slot spins through gadget icons
	-- for a moment, lands on yours, and its ring flashes gold.
	local slotShown: { [number]: string? } = {}
	local rollUntil: { [number]: number } = {}
	-- the slot that got the gadget: a soft rainbow glow the shape of the slot (round), which
	-- fades out, plus a little pop
	local function glow(b: GuiObject)
		local aura = BoxLook.aura(b, 0.5, 1)
		aura.ZIndex = 4
		local info = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, g in aura:GetChildren() do
			if g:IsA("Frame") then
				g.ZIndex = 4
				TweenService:Create(g, info, { BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(1.45, aura.Destroy, aura)
		local sc = b:FindFirstChildOfClass("UIScale")
		if sc then
			sc.Scale = 1.25
			TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
	end
	-- the ? box pops up in the middle of the screen with a soft rainbow aura, then swipes down
	-- into the slot it fills
	Lobby.boxPop = function()
		local target: GuiObject? = nil
		for i, b in slotButtons do
			if not player:GetAttribute("Gadget" .. i) then
				target = b
				break
			end
		end
		local SIZE = 110
		local holder = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(SIZE, SIZE),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			ZIndex = 20,
		}, gui)
		-- two faces side by side, sized like a cube turning about its upright axis: at angle a
		-- the faces show cos(a) and sin(a) of their width (repeats every quarter turn); the face
		-- turning away is shaded a little
		local faces = {}
		for k = 1, 2 do
			local fr = new("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.fromOffset(SIZE, SIZE),
				Position = UDim2.fromScale(0, 0.5),
				ZIndex = 21,
			}, holder)
			BoxLook.face(fr, SIZE, 21)
			local shade = new("Frame", {
				BackgroundColor3 = Palette.UiInk,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 26,
			}, fr)
			new("UICorner", { CornerRadius = UDim.new(0.05, 0) }, shade)
			faces[k] = { fr = fr, shade = shade }
		end
		BoxLook.aura(holder, 0.05, 1).ZIndex = 20
		for _, g in holder.Aura:GetChildren() do
			if g:IsA("Frame") then
				g.ZIndex = 20
			end
		end
		local sc = new("UIScale", { Scale = 0 }, holder)
		TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		-- it keeps turning on the spot like the box in the world: a GUI can't turn in 3D, so the
		-- width follows cos(angle) (a cube seen from the side), with the same little tilt
		holder.Rotation = 12
		local t0 = os.clock()
		task.spawn(function()
			while holder.Parent do
				local a = ((os.clock() - t0) * 5) % (math.pi / 2)
				local w1, w2 = SIZE * math.cos(a), SIZE * math.sin(a)
				local x0 = (SIZE - (w1 + w2)) / 2
				faces[1].fr.Position = UDim2.new(0, x0, 0.5, 0)
				faces[1].fr.Size = UDim2.fromOffset(w1, SIZE)
				faces[2].fr.Position = UDim2.new(0, x0 + w1, 0.5, 0)
				faces[2].fr.Size = UDim2.fromOffset(w2, SIZE)
				faces[1].shade.BackgroundTransparency = 1 - 0.35 * math.sin(a)
				faces[2].shade.BackgroundTransparency = 1 - 0.35 * math.cos(a)
				RunService.RenderStepped:Wait()
			end
		end)
		task.delay(0.5, function()
			local info = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if target and target.Visible and slots.Visible then
				local tc = target.AbsolutePosition + target.AbsoluteSize / 2 - gui.AbsolutePosition
				TweenService:Create(holder, info, { Position = UDim2.fromOffset(tc.X, tc.Y) }):Play()
				TweenService:Create(sc, info, { Scale = target.AbsoluteSize.X / SIZE * 0.7 }):Play()
			else
				TweenService:Create(sc, info, { Scale = 0 }):Play()
			end
			task.wait(0.32)
			holder:Destroy()
		end)
	end

	-- Winners on the finish line: an EMOTE button (G on a keyboard) while they celebrate
	local emoteB = button(
		gui,
		UserInputService.KeyboardEnabled and "EMOTE [G]" or "EMOTE",
		Palette.UiBuy,
		Palette.UiInk,
		UDim2.fromOffset(170, 50),
		UDim2.new(0.5, -85, 1, -150),
		function()
			playEmote()
		end
	)
	emoteB.Visible = false
	local function showEmote()
		emoteB.Visible = player:GetAttribute("State") == "Finished"
	end
	player:GetAttributeChangedSignal("State"):Connect(showEmote)

	UserInputService.InputBegan:Connect(function(io, processed)
		if processed then
			return
		end
		local state = player:GetAttribute("State")
		if state == "Running" then
			if io.KeyCode == Enum.KeyCode.Q then
				-- testing: with slot 1 empty, Q is a 6 s sprint (server allows it in Studio / for the owner)
				if player:GetAttribute("Gadget1") == nil then
					remotes.TestBoost:FireServer()
				end
				useSlot(1)
			elseif io.KeyCode == Enum.KeyCode.E then
				useSlot(2)
			end
		elseif state == "Finished" then
			if io.KeyCode == Enum.KeyCode.G then
				playEmote()
			end
		elseif state == "Lobby" then
			if io.KeyCode == Enum.KeyCode.Z then
				toggle("Shop")
			elseif io.KeyCode == Enum.KeyCode.X then
				toggle("Inventory")
			elseif io.KeyCode == Enum.KeyCode.C then
				toggle("Modes")
			elseif io.KeyCode == Enum.KeyCode.G then
				playEmote()
			end
		end
	end)

	-- Gem shop pad: stepping onto the hologram half circle in front of the stall opens the same
	-- Lobby pads: square floor pads with a glowing field. Standing on one acts like pressing its
	-- button; stepping off undoes what the pad did (closes the shop, leaves the queue).
	--   GemShop.ShopPad      -> opens the shop panel
	--   LobbyBuilding.PlayPad -> queues for the next Standard run
	task.spawn(function()
		local building = workspace:WaitForChild("LobbyBuilding", 20)
		local shop = building and building:WaitForChild("GemShop", 10)
		local shopPad = shop and shop:WaitForChild("ShopPad", 10)
		local playPad = building and building:WaitForChild("PlayPad", 10)
		local function onPad(pad: Instance?): boolean
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not (pad and root) then
				return false
			end
			local d = root.Position - pad:GetAttribute("Centre")
			local hx: number = pad:GetAttribute("HalfX") or pad:GetAttribute("Half")
			local hz: number = pad:GetAttribute("HalfZ") or pad:GetAttribute("Half")
			return math.abs(d:Dot(pad:GetAttribute("Right"))) < hx
				and math.abs(d:Dot(pad:GetAttribute("Look"))) < hz
				and d.Y > -1
				and d.Y < 16 -- tall enough that jumping on the pad still counts
		end
		local sub = playPad and playPad:FindFirstChild("Sub", true) :: TextLabel?
		local inShop, shopOpened = false, false
		local inPlay, padQueued = false, false
		-- leaving the queue (button) while standing on the pad steps you off it, so you are
		-- visibly out of the ready area
		player:GetAttributeChangedSignal("Queued"):Connect(function()
			if player:GetAttribute("Queued") or player:GetAttribute("State") == "Running" or not onPad(playPad) then
				return
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not (root and playPad) then
				return
			end
			local c: Vector3 = playPad:GetAttribute("Centre")
			local look: Vector3 = playPad:GetAttribute("Look")
			local hz: number = playPad:GetAttribute("HalfZ") or playPad:GetAttribute("Half")
			local right: Vector3 = playPad:GetAttribute("Right")
			local hx: number = playPad:GetAttribute("HalfX") or playPad:GetAttribute("Half")
			-- step off on a side that has lobby floor next to it (one side of the pad is open to
			-- the jungle 30 studs below), nearest side first
			local d = root.Position - c
			local sides = { { look, hz }, { -look, hz }, { right, hx }, { -right, hx } }
			table.sort(sides, function(a, b)
				return d:Dot(a[1]) > d:Dot(b[1])
			end)
			local rp = RaycastParams.new()
			rp.FilterDescendantsInstances = { player.Character :: Model }
			for _, sd in sides do
				local out = c + sd[1] * (sd[2] + 5)
				local hit = workspace:Raycast(out + Vector3.new(0, 6, 0), Vector3.new(0, -12, 0), rp)
				if hit and math.abs(hit.Position.Y - c.Y) < 3 then
					local at = hit.Position + Vector3.new(0, d.Y + 0.2, 0)
					root.CFrame = CFrame.lookAt(at, at + sd[1])
					break
				end
			end
			inPlay = false
		end)
		RunService.Heartbeat:Connect(function()
			local lobby = player:GetAttribute("State") ~= "Running"
			local nowShop = lobby and onPad(shopPad)
			if nowShop and not inShop and openPanel ~= "Shop" then
				toggle("Shop")
				shopOpened = true
			elseif inShop and not nowShop then
				if shopOpened and openPanel == "Shop" then
					Lobby.close()
				end
				shopOpened = false
			end
			inShop = nowShop
			local nowPlay = lobby and onPad(playPad)
			if nowPlay and not inPlay then
				Sfx.play("Start") -- walking into the ready area (never on leaving it)
			end
			if nowPlay and not inPlay and not player:GetAttribute("Queued") then
				remotes.Queue:FireServer(true)
				padQueued = true
			elseif inPlay and not nowPlay then
				-- stepping off the pad always leaves the queue (however you joined it)
				if lobby and player:GetAttribute("Queued") then
					remotes.Queue:FireServer(false)
				end
				padQueued = false
			end
			inPlay = nowPlay
			if sub then
				local n = 0
				for _, pl in Players:GetPlayers() do
					if pl:GetAttribute("Queued") then
						n += 1
					end
				end
				local at = workspace:GetAttribute("NextRunAt") or 0
				local left = math.max(0, math.ceil(at - workspace:GetServerTimeNow()))
				sub.Text = string.format(
					"%d queued  ·  %s",
					n,
					at > 0 and string.format("starts in 0:%02d", left) or "run in progress"
				)
			end
		end)
	end)

	remotes:WaitForChild("Profile").OnClientEvent:Connect(function(p)
		profile = p
		if openPanel and not reel.Visible then
			renderPanel()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local state = player:GetAttribute("State")
		local inLobby = state == "Lobby" or state == nil
		root.Visible = inLobby
		if not inLobby then
			if openPanel then
				Lobby.close()
			end
			reel.Visible = false
		end
		slots.Visible = state == "Running" or state == "Countdown"
		local now = os.clock()
		for i, b in slotButtons do
			local id = player:GetAttribute("Gadget" .. i)
			if id ~= slotShown[i] then
				if id and not slotShown[i] then
					rollUntil[i] = now + 1.3 -- the pop swipes in (~0.85 s), then the icons spin
				end
				slotShown[i] = id
			end
			local g = id and Items.get(id)
			local untilT = rollUntil[i]
			if untilT and id then
				if now < untilT - 0.45 then
					b.Text = ""
					Items.iconInto(b, nil)
				elseif now < untilT then
					local all = Items.Gadgets
					local r = all[(math.floor(now * 14) % #all) + 1]
					b.Text = ""
					Items.iconInto(b, r.id, 0.92)
				else
					rollUntil[i] = nil
					b.Text = ""
					Items.iconInto(b, g and g.id, 0.92)
					glow(b)
					showTip(i, 3)
				end
			else
				rollUntil[i] = nil
				b.Text = ""
				Items.iconInto(b, g and g.id, 0.92)
			end
		end
		if not inLobby then
			return
		end
		local lvl = player:GetAttribute("Level") or 1
		local xp = player:GetAttribute("Xp") or 0
		local need = Items.xpFor(lvl)
		lvText.Text = "Level " .. lvl
		xpText.Text = string.format("%d/%d", xp, need)
		xpFill.Size = UDim2.fromScale(math.clamp(xp / need, 0, 1), 1)
		gemText.Text = tostring(player:GetAttribute("Gems") or 0)
		local mode = workspace:GetAttribute("Mode") or "Stampede"
		for _, m in Items.Modes do
			if m.id == mode then
				modeText.Text = string.upper(m.name)
			end
		end
		local at = workspace:GetAttribute("NextRunAt") or 0
		local left = at - workspace:GetServerTimeNow()
		if at > 0 and left > 0 then
			cdText.Text = string.format("%d:%02d", left // 60, math.ceil(left) % 60)
		else
			cdText.Text = "LIVE"
		end
		local queued = player:GetAttribute("Queued")
		play.Text = queued and "READY" or "PLAY"
		playIcon()
		play.BackgroundColor3 = queued and Palette.UiGold or Palette.CanopyMid
		hint.Text = queued and "You're in! Tap again to leave the queue" or "Run further, earn more"
		hintGem.Visible = not queued
		hintPad.PaddingRight = UDim.new(0, queued and 12 or 44)
	end)
end

return Lobby
