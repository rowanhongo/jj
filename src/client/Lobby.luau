--!strict
-- Lobby UI (only while State == "Lobby"): level + gems top right, next-run countdown top centre,
-- PLAY to join the next run, and a bottom bar: Shop [Z], Inventory [X], Modes [C].
-- Shop: Daily Shop, Item Rolls (with the reel), Passes. Inventory: Gadgets (loadout), Titles,
-- Emotes, Trails, Records (which mode's best floats above your head).
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

local Lobby = {}

local profile: any = nil
local gui: ScreenGui
local root: Frame -- scaled canvas for lobby widgets
local panelHolder: Frame
local openPanel: string? = nil
local renderPanel: () -> () = function() end
local toastFn: (string) -> () = function() end

local TITLE = Enum.Font.FredokaOne
local BODY = Enum.Font.GothamBold

-- ---------- tiny builders ----------
local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
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
	return new("UIStroke", { Color = color, Thickness = thick or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function text(parent: Instance, t: string, size: number, color: Color3, font: Enum.Font?, props: { [string]: any }?): TextLabel
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

local function button(parent: Instance, t: string, bg: Color3, fg: Color3, size: UDim2, pos: UDim2, onClick: () -> ()): TextButton
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
	corner(b, 6)
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
local function card(parent: Instance, icon: string, name: string, sub: string, rarity: string, badge: string?, dim: boolean?): Frame
	local f = new("Frame", { BackgroundColor3 = Palette.UiPaper, Size = UDim2.fromOffset(150, 170) }, parent)
	corner(f, 6)
	local well = new("Frame", { BackgroundColor3 = rarityColour(rarity), BackgroundTransparency = dim and 0.7 or 0.45, Size = UDim2.new(1, 0, 0, 104) }, f)
	corner(well, 6)
	text(well, icon, 54, Palette.UiInk, TITLE, { TextTransparency = dim and 0.5 or 0 })
	text(f, name, 17, Palette.UiInk, TITLE, { Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(8, 110), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	text(f, sub, 12, Palette.StoneShadow, BODY, { Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(8, 132), TextXAlignment = Enum.TextXAlignment.Left })
	if badge then
		local b = new("TextLabel", { BackgroundColor3 = Palette.UiInk, TextColor3 = Palette.UiText, Font = BODY, TextSize = 12, Text = " " .. badge .. " ", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), Position = UDim2.fromOffset(6, 6) }, f)
		corner(b, 3)
	end
	return f
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
	new("UIGridLayout", { CellSize = UDim2.fromOffset(cell.X, cell.Y), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, s)
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
	new("Frame", { BackgroundColor3 = Palette.UiInk, BorderSizePixel = 0, Size = UDim2.fromOffset(5, 44) }, h)
	text(h, title, 24, Palette.UiInk, TITLE, { Size = UDim2.new(1, -14, 0, 26), Position = UDim2.fromOffset(14, 0), TextXAlignment = Enum.TextXAlignment.Left })
	text(h, sub, 14, Palette.StoneShadow, BODY, { Size = UDim2.new(1, -14, 0, 18), Position = UDim2.fromOffset(14, 26), TextXAlignment = Enum.TextXAlignment.Left })
	return h
end

local function gemChip(parent: Instance, pos: UDim2)
	local chip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(130, 40), Position = pos }, parent)
	text(chip, "💎 " .. tostring(profile and profile.gems or 0), 26, Palette.UiText, TITLE, { TextXAlignment = Enum.TextXAlignment.Right })
end

local function openTabs(name: string, tabs: { string }, draw: (string, Frame) -> ())
	openPanel = name
	panelHolder.Visible = true
	clear(tabBar)
	clear(body)
	local tab = currentTab[name] or tabs[1]
	currentTab[name] = tab
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -260, 1, 0) }, tabBar)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i, t in tabs do
		local active = t == tab
		local b = new("TextButton", {
			Size = UDim2.fromOffset(math.max(110, #t * 13 + 34), 44),
			Position = UDim2.fromOffset(10, 8),
			BackgroundColor3 = active and Palette.UiPaper or Palette.UiInk,
			Text = t,
			TextColor3 = active and Palette.UiInk or Palette.UiText,
			Font = TITLE,
			TextSize = 22,
			LayoutOrder = i,
			Name = "Tab_" .. t:gsub(" ", ""),
		}, row)
		corner(b, 4)
		stroke(b, active and Palette.UiInk or Palette.StoneShadow, 2)
		b.Activated:Connect(function()
			currentTab[name] = t
			openTabs(name, tabs, draw)
		end)
	end
	gemChip(tabBar, UDim2.new(1, -200, 0, 0))
	local close = button(tabBar, "X", Palette.UiPaper, Palette.UiInk, UDim2.fromOffset(46, 44), UDim2.new(1, -46, 0, -2), function()
		Lobby.close()
	end)
	close.LayoutOrder = 99
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
	openPanel = nil
	panelHolder.Visible = false
	renderPanel = function() end
end

-- ---------- roll reel ----------
local reel: Frame

local function showResult(ids: { string })
	clear(reel)
	reel.Visible = true
	local last = ids[#ids]
	local g = Items.get(last)
	local shade = new("Frame", { BackgroundColor3 = Palette.UiInk, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1) }, reel)
	shade.Active = true
	local c = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(820, 420), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, reel)
	local left = card(c, g.icon, g.name, string.format("%s • %.1f%%", g.rarity, Items.rarityChance(last)), g.rarity, "Owned")
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
	local right = new("Frame", { BackgroundColor3 = Palette.UiPaper, Size = UDim2.fromOffset(560, 300), Position = UDim2.fromOffset(260, 0) }, c)
	corner(right, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingTop = UDim.new(0, 14), PaddingRight = UDim.new(0, 18) }, right)
	text(right, "Description", 18, Palette.UiInk, TITLE, { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left })
	text(right, g.desc, 15, Palette.StoneShadow, BODY, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 24), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local copies = profile and profile.items[last] or 1
	text(right, "Mastery", 18, Palette.UiInk, TITLE, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 70), TextXAlignment = Enum.TextXAlignment.Left })
	text(right, string.format("%d duplicate%s", copies - 1, copies - 1 == 1 and "" or "s"), 15, Palette.StoneShadow, BODY, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 94), TextXAlignment = Enum.TextXAlignment.Left })
	if #ids > 1 then
		local list = {}
		for _, id in ids do
			table.insert(list, Items.get(id).icon)
		end
		text(right, "You got: " .. table.concat(list, " "), 20, Palette.UiInk, BODY, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 124), TextXAlignment = Enum.TextXAlignment.Left })
	end
	local function again(n: number)
		reel.Visible = false
		Lobby.roll(n)
	end
	button(right, string.format("1 more roll  💎%d", Items.RollPrice), Palette.UiBuy, Palette.UiInk, UDim2.fromOffset(250, 56), UDim2.fromOffset(0, 210), function()
		again(1)
	end)
	button(right, string.format("10 more rolls  💎%d", Items.Roll10Price), Palette.UiBuy, Palette.UiInk, UDim2.fromOffset(250, 56), UDim2.fromOffset(268, 210), function()
		again(10)
	end)
	local done = button(c, "Done", Palette.UiInk, Palette.UiText, UDim2.fromOffset(200, 56), UDim2.new(0.5, -100, 0, 330), function()
		reel.Visible = false
		renderPanel()
	end)
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
	local shade = new("Frame", { BackgroundColor3 = Palette.UiInk, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1) }, reel)
	shade.Active = true
	local W, GAP, COUNT, LAND = 220, 18, 46, 40
	local strip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(COUNT * (W + GAP), 330), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, -W / 2, 0.5, 0) }, reel)
	local target = ids[#ids]
	for i = 1, COUNT do
		local id = i == LAND and target or Items.Gadgets[math.random(1, #Items.Gadgets)].id
		local g = Items.get(id)
		local owned = profile.items[id] and profile.items[id] > 0
		local c = card(strip, g.icon, g.name, string.format("%s • %.1f%%", g.rarity, Items.rarityChance(id)), g.rarity, owned and "Owned" or "Not owned")
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
	local marker = new("Frame", { BackgroundColor3 = Palette.UiGold, BorderSizePixel = 0, Size = UDim2.fromOffset(4, 380), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5 }, reel)
	stroke(marker, Palette.UiRim, 1)
	local jitter = math.random(-W * 0.35, W * 0.35)
	local endX = -((LAND - 1) * (W + GAP)) - W / 2 + jitter
	local tw = TweenService:Create(strip, TweenInfo.new(4.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, endX, 0.5, 0) })
	tw:Play()
	tw.Completed:Wait()
	task.wait(0.5)
	showResult(ids)
end

-- ---------- Shop ----------
local function drawShop(tab: string, f: Frame)
	if tab == "Daily Shop" then
		local ok, d = call("Daily")
		sectionHead(f, "Today", ok and ("Leaves in " .. fmtTime(d.endsAt - os.time())) or "", UDim2.fromOffset(0, 0), 600)
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 230), Position = UDim2.fromOffset(0, 56) }, f)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }, row)
		if ok then
			for _, id in d.ids do
				local c = Items.get(id)
				local owned = profile and profile.cosmetics[id]
				local icon = c.kind == "Title" and "🏷️" or c.kind == "Emote" and "💃" or "✨"
				local k = card(row, icon, c.name, c.kind .. " • " .. c.rarity, c.rarity, owned and "Owned" or nil)
				k.Size = UDim2.fromOffset(170, 220)
				button(k, owned and "Owned" or ("💎 " .. c.price), owned and Palette.UiPaperDim or Palette.UiBuy, Palette.UiInk, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 172), function()
					if owned then
						return
					end
					local bought = call("BuyDaily", id)
					toastFn(bought and ("Bought " .. c.name .. "!") or "Not enough gems")
				end)
			end
		end
		sectionHead(f, "Get Gems", "Gem packs (Robux)", UDim2.fromOffset(0, 300), 600)
		local packs = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 356) }, f)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }, packs)
		for _, pk in Items.GemPacks do
			local b = button(packs, string.format("💎 %d   R$ %d", pk.gems, pk.robux), Palette.UiBuy, Palette.UiInk, UDim2.fromOffset(250, 64), UDim2.new(), function()
				if pk.productId == 0 then
					toastFn("Gem packs open soon!")
				else
					game:GetService("MarketplaceService"):PromptProductPurchase(player, pk.productId)
				end
			end)
			if pk.tag then
				local t = new("TextLabel", { BackgroundColor3 = Palette.UiInk, TextColor3 = Palette.UiGold, Font = BODY, TextSize = 12, Text = " " .. pk.tag .. " ", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), Position = UDim2.fromOffset(6, -9) }, b)
				corner(t, 3)
			end
		end
	elseif tab == "Item Rolls" then
		local list = new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, -330, 1, 0), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = Palette.StoneShadow, BorderSizePixel = 0 }, f)
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
			local sec = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 236), LayoutOrder = 6 - i }, list)
			local pityTxt = ""
			if Items.Pity[r] and profile then
				pityTxt = string.format("   •   Guaranteed in %d rolls", Items.Pity[r] - (profile.pity[r] or 0))
			end
			sectionHead(sec, r, string.format("%d%% of rolls • %d/%d owned%s", Items.RarityWeight[r], ownedN, total, pityTxt), UDim2.new(), 560)
			local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 176), Position = UDim2.fromOffset(0, 56) }, sec)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }, row)
			for _, g in Items.Gadgets do
				if g.rarity == r then
					local own = profile and (profile.items[g.id] or 0) > 0
					card(row, g.icon, g.name, string.format("%s • %.1f%%", r, Items.rarityChance(g.id)), r, own and "Owned" or "Not owned", not own)
				end
			end
		end
		local side = new("Frame", { BackgroundColor3 = Palette.UiPaper, Size = UDim2.new(0, 310, 0, 300), Position = UDim2.new(1, -310, 0, 0) }, f)
		corner(side, 6)
		stroke(side, Palette.UiInk, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12) }, side)
		text(side, "10 Rolls", 26, Palette.UiInk, TITLE, { Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left })
		text(side, string.format("10 for the price of %d", Items.Roll10Price // Items.RollPrice), 15, Palette.StoneShadow, BODY, { Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Right })
		local y = 40
		for _, r in { "Rare", "Epic", "Mythic" } do
			local left = Items.Pity[r] - (profile and profile.pity[r] or 0)
			text(side, string.format("Guaranteed %s in %d", r, left), 14, Palette.StoneShadow, BODY, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, y), TextXAlignment = Enum.TextXAlignment.Left })
			local back = new("Frame", { BackgroundColor3 = Palette.UiPaperDim, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, y + 20) }, side)
			corner(back, 4)
			local fill = new("Frame", { BackgroundColor3 = rarityColour(r), BorderSizePixel = 0, Size = UDim2.fromScale(1 - left / Items.Pity[r], 1) }, back)
			corner(fill, 4)
			y += 38
		end
		local r10 = button(side, "10 Rolls   💎 " .. Items.Roll10Price, Palette.UiBuy, Palette.UiInk, UDim2.new(1, 0, 0, 52), UDim2.fromOffset(0, y + 4), function()
			Lobby.roll(10)
		end)
		r10.Name = "Roll10"
		button(side, "1 Roll   💎 " .. Items.RollPrice, Palette.UiInk, Palette.UiText, UDim2.new(1, 0, 0, 46), UDim2.fromOffset(0, y + 66), function()
			Lobby.roll(1)
		end)
	elseif tab == "Passes" then
		sectionHead(f, "Passes", "Yours forever. Coming soon.", UDim2.new(), 600)
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 230), Position = UDim2.fromOffset(0, 56) }, f)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }, row)
		for _, ps in {
			{ "👑", "VIP", "VIP title, gold trail, +1 loadout slot", "Mythic" },
			{ "💎", "2x Gems", "Double gems from every run", "Epic" },
			{ "🎲", "Lucky Rolls", "Mythic pity drops from 80 to 50", "Rare" },
			{ "🛡️", "Starter Shield", "Start every run with one shield", "Uncommon" },
		} do
			local k = card(row, ps[1], ps[2], ps[3], ps[4])
			k.Size = UDim2.fromOffset(190, 220)
			button(k, "Soon", Palette.UiPaperDim, Palette.UiInk, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 172), function() end)
		end
	end
end

-- ---------- Inventory ----------
local function cosmeticTab(kind: string, f: Frame)
	local equipped = profile and profile.equipped[kind]
	local eq = equipped and Items.get(equipped)
	sectionHead(f, "Equipped", eq and eq.name or "None", UDim2.new(), 300)
	local ownedN = 0
	for _, c in Items.Cosmetics do
		if c.kind == kind and profile and profile.cosmetics[c.id] then
			ownedN += 1
		end
	end
	sectionHead(f, "Your " .. kind .. "s", string.format("%d owned", ownedN), UDim2.fromOffset(0, 0), 600).Position = UDim2.fromOffset(320, 0)
	local preview = new("Frame", { BackgroundColor3 = Palette.UiPaperDim, Size = UDim2.fromOffset(300, 300), Position = UDim2.fromOffset(0, 56) }, f)
	corner(preview, 6)
	if kind == "Title" then
		text(preview, eq and eq.name or "", 30, rarityColour(eq and eq.rarity or "Common"), TITLE)
	elseif kind == "Emote" then
		text(preview, "💃\nPress G to emote", 26, Palette.UiInk, TITLE)
	else
		text(preview, eq and "✨ " .. eq.name or "No trail", 26, Palette.UiInk, TITLE)
	end
	local g = grid(new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -320, 1, -56), Position = UDim2.fromOffset(320, 56) }, f), Vector2.new(150, 170))
	if kind == "Trail" then
		local none = card(g, "⛔", "No trail", "Free", "Common", not equipped and "Equipped" or nil)
		local b = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1) }, none)
		b.Activated:Connect(function()
			call("Equip", "Trail", "")
		end)
	end
	for _, c in Items.Cosmetics do
		if c.kind == kind then
			local own = profile and profile.cosmetics[c.id]
			local icon = kind == "Title" and "🏷️" or kind == "Emote" and "💃" or "✨"
			local badge = equipped == c.id and "Equipped" or (not own and (c.unlock and ("🔒 " .. c.unlock.text) or "🛒 In daily shop") or nil)
			local k = card(g, icon, c.name, c.rarity, c.rarity, badge, not own)
			if own then
				local b = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1) }, k)
				b.Activated:Connect(function()
					call("Equip", kind, c.id)
				end)
			end
		end
	end
end

local function drawInventory(tab: string, f: Frame)
	if tab == "Gadgets" then
		local loadout = profile and profile.loadout or {}
		sectionHead(f, "Loadout", string.format("%d/%d • ? boxes in a run give you one of these", #loadout, Items.LoadoutSize), UDim2.new(), 700)
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 176), Position = UDim2.fromOffset(0, 56) }, f)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }, row)
		for i = 1, Items.LoadoutSize do
			local id = loadout[i]
			if id then
				local g = Items.get(id)
				local k = card(row, g.icon, g.name, "Tap to remove", g.rarity, "Slot " .. i)
				local b = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1) }, k)
				b.Activated:Connect(function()
					local nl = table.clone(loadout)
					table.remove(nl, i)
					if #nl == 0 then
						toastFn("Keep at least one gadget")
						return
					end
					call("Loadout", nl)
				end)
			else
				card(row, "+", "Empty", "Pick below", "Common", nil, true)
			end
		end
		sectionHead(f, "Your Gadgets", "Tap one to add it to your loadout", UDim2.fromOffset(0, 244), 600)
		local g = grid(new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -300), Position = UDim2.fromOffset(0, 300) }, f), Vector2.new(150, 170))
		for _, gd in Items.Gadgets do
			local n = profile and profile.items[gd.id] or 0
			if n > 0 then
				local inL = table.find(loadout, gd.id) ~= nil
				local k = card(g, gd.icon, gd.name, n > 1 and string.format("%s • x%d", gd.rarity, n) or gd.rarity, gd.rarity, inL and "Equipped" or nil)
				local b = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1) }, k)
				b.Activated:Connect(function()
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
	elseif tab == "Records" then
		sectionHead(f, "Records", "Pick the record that floats above your head", UDim2.new(), 700)
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 230), Position = UDim2.fromOffset(0, 56) }, f)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }, row)
		for _, m in Items.Modes do
			local best = profile and profile.records[m.id] or 0
			local shown = profile and profile.showcase == m.id
			local k = card(row, m.icon, m.name, best > 0 and string.format("Best: %d m", best) or "No record yet", shown and "Uncommon" or "Common", shown and "Showing" or nil, not m.live)
			k.Size = UDim2.fromOffset(170, 220)
			button(k, shown and "Showing" or "Show", shown and Palette.UiPaperDim or Palette.UiBuy, Palette.UiInk, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 172), function()
				call("Showcase", m.id)
			end)
		end
		local lvl = profile and profile.level or 1
		text(f, string.format("Level %d  •  %d lifetime check-ins  •  %d rolls", lvl, profile and profile.checkIns or 0, profile and profile.rolls or 0), 18, Palette.UiInk, TITLE, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 300), TextXAlignment = Enum.TextXAlignment.Left })
	else
		cosmeticTab(tab:sub(1, -2), f)
	end
end

-- ---------- Modes ----------
local function drawModes(_: string, f: Frame)
	sectionHead(f, "Pick your expedition", "Only Stampede is open for now", UDim2.new(), 700)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 260), Position = UDim2.fromOffset(0, 56) }, f)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }, row)
	for _, m in Items.Modes do
		local k = card(row, m.icon, m.name, m.live and "Open" or "Coming soon", m.live and "Uncommon" or "Common", m.live and "Selected" or nil, not m.live)
		k.Size = UDim2.fromOffset(200, 250)
		text(k, m.blurb, 13, Palette.StoneShadow, BODY, { Size = UDim2.new(1, -16, 0, 48), Position = UDim2.fromOffset(8, 152), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
		if m.live then
			button(k, "PLAY", Palette.UiBuy, Palette.UiInk, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 202), function()
				remotes.Queue:FireServer(true)
				Lobby.close()
			end)
		end
	end
end

local function toggle(name: string)
	if openPanel == name then
		Lobby.close()
	elseif name == "Shop" then
		openTabs("Shop", { "Daily Shop", "Item Rolls", "Passes" }, drawShop)
	elseif name == "Inventory" then
		openTabs("Inventory", { "Gadgets", "Titles", "Emotes", "Trails", "Records" }, drawInventory)
	elseif name == "Modes" then
		openTabs("Modes", { "Expeditions" }, drawModes)
	end
end

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
	gui = new("ScreenGui", { Name = "JJLobby", ResetOnSpawn = false, IgnoreGuiInset = true, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, DisplayOrder = 5 }, player:WaitForChild("PlayerGui"))
	local inset = GuiService:GetGuiInset()

	root = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	local scale = new("UIScale", {}, gui)
	local function rescale()
		local v = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 760), 0.5, 1.2)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Top right: level bar + gems
	local lv = new("Frame", { BackgroundColor3 = Palette.UiPaper, Size = UDim2.fromOffset(280, 64), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, inset.Y + 10) }, root)
	corner(lv, 6)
	stroke(lv, Palette.UiInk, 2)
	local lvText = text(lv, "Level 1", 22, Palette.UiInk, TITLE, { Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left })
	local xpText = text(lv, "", 16, Palette.StoneShadow, BODY, { Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Right })
	local xpBack = new("Frame", { BackgroundColor3 = Palette.UiInk, BorderSizePixel = 0, Size = UDim2.new(1, -24, 0, 12), Position = UDim2.fromOffset(12, 40) }, lv)
	local xpFill = new("Frame", { BackgroundColor3 = Palette.UiGold, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, xpBack)
	local gemBox = new("Frame", { BackgroundColor3 = Palette.UiPaper, Size = UDim2.fromOffset(130, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, inset.Y + 84) }, root)
	corner(gemBox, 6)
	stroke(gemBox, Palette.UiInk, 2)
	local gemText = text(gemBox, "💎 0", 24, Palette.UiInk, TITLE)

	-- Top centre: mode + countdown
	local cd = new("Frame", { BackgroundColor3 = Palette.UiPaper, Size = UDim2.fromOffset(250, 84), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, inset.Y + 10) }, root)
	corner(cd, 6)
	stroke(cd, Palette.UiInk, 2)
	local modeText = text(cd, "🏃 STAMPEDE", 18, Palette.StoneShadow, TITLE, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 6) })
	local cdText = text(cd, "0:12", 40, Palette.UiInk, TITLE, { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 30) })

	-- Bottom: hint, PLAY, bar
	local hint = new("TextLabel", { BackgroundColor3 = Palette.UiPaper, TextColor3 = Palette.UiInk, Font = TITLE, TextSize = 18, Text = "Run further, earn more 💎", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -196) }, root)
	corner(hint, 4)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, hint)
	local play = button(root, "▶▶ PLAY", Palette.UiBuy, Palette.UiInk, UDim2.fromOffset(280, 86), UDim2.new(0.5, -140, 1, -186), function() end)
	play.TextSize = 46
	stroke(play, Palette.UiPaper, 3)
	play.Activated:Connect(function()
		remotes.Queue:FireServer(not player:GetAttribute("Queued"))
	end)

	local bar = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(780, 70), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14) }, root)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16), HorizontalAlignment = Enum.HorizontalAlignment.Center }, bar)
	local keyMap = { Shop = Enum.KeyCode.Z, Inventory = Enum.KeyCode.X, Modes = Enum.KeyCode.C }
	for i, spec in { { "Shop", "🛒 Shop", Palette.Rare }, { "Inventory", "🎒 Inventory", Palette.UiPaperDim }, { "Modes", "🧭 Modes", Palette.Epic } } do
		local b = button(bar, spec[2], Palette.UiPaper, Palette.UiInk, UDim2.fromOffset(240, 62), UDim2.new(), function()
			toggle(spec[1])
		end)
		b.LayoutOrder = i
		b.TextSize = 28
		new("UIGradient", { Color = ColorSequence.new(Palette.UiPaper, spec[3]), Rotation = 90 }, b)
		stroke(b, Palette.UiPaper, 3)
		if not UserInputService.TouchEnabled then
			local key = new("TextLabel", { BackgroundColor3 = Palette.UiPaper, TextColor3 = Palette.UiInk, Font = TITLE, TextSize = 18, Text = keyMap[spec[1]].Name, Size = UDim2.fromOffset(28, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0) }, b)
			corner(key, 3)
		end
	end

	-- Panels + reel
	panelHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 }, gui)
	panel = new("Frame", { BackgroundColor3 = Palette.UiPaper, Size = UDim2.fromOffset(1080, 560), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -30) }, panelHolder)
	corner(panel, 8)
	stroke(panel, Palette.UiInk, 3)
	new("UIScale", {}, panel).Scale = 1
	tabBar = new("Frame", { BackgroundColor3 = Palette.UiInk, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 60) }, panel)
	corner(tabBar, 8)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, tabBar)
	body = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -36, 1, -84), Position = UDim2.fromOffset(18, 72), ClipsDescendants = true }, panel)
	reel = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, ClipsDescendants = true }, gui)

	-- Gadget slots during a run
	local slots = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 80), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -180) }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Right }, slots)
	local slotButtons = {}
	local slotKeys = { "Q", "E" }
	local function useSlot(i: number)
		if player:GetAttribute("Gadget" .. i) then
			remotes.UseGadget:FireServer(i)
		end
	end
	for i = 1, Items.SlotCount do
		local b = button(slots, "", Palette.UiPanel, Palette.UiText, UDim2.fromOffset(76, 76), UDim2.new(), function()
			useSlot(i)
		end)
		b.TextSize = 40
		b.BackgroundTransparency = 0.2
		stroke(b, Palette.UiGold, 2)
		local k = text(b, slotKeys[i], 14, Palette.UiGold, TITLE, { Size = UDim2.fromOffset(20, 18), Position = UDim2.fromOffset(4, 2) })
		k.Visible = not UserInputService.TouchEnabled
		slotButtons[i] = b
	end

	UserInputService.InputBegan:Connect(function(io, processed)
		if processed then
			return
		end
		local state = player:GetAttribute("State")
		if state == "Running" then
			if io.KeyCode == Enum.KeyCode.Q then
				useSlot(1)
			elseif io.KeyCode == Enum.KeyCode.E then
				useSlot(2)
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
		slots.Visible = state == "Running"
		for i, b in slotButtons do
			local id = player:GetAttribute("Gadget" .. i)
			local g = id and Items.get(id)
			b.Text = g and g.icon or ""
			b.BackgroundTransparency = g and 0.1 or 0.55
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
		gemText.Text = "💎 " .. tostring(player:GetAttribute("Gems") or 0)
		local mode = workspace:GetAttribute("Mode") or "Stampede"
		for _, m in Items.Modes do
			if m.id == mode then
				modeText.Text = m.icon .. " " .. string.upper(m.name)
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
		play.Text = queued and "✔ READY" or "▶▶ PLAY"
		play.BackgroundColor3 = queued and Palette.UiGold or Palette.UiBuy
		hint.Text = queued and "You're in! Tap again to leave the queue" or "Run further, earn more 💎"
	end)
end

return Lobby
