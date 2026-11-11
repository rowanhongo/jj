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

local function bar(parent: Instance, pos: UDim2, fillColor: Color3, title: string): (Frame, TextLabel)
	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(240, 22)
	back.Position = pos
	back.BackgroundColor3 = Palette.UiPanel
	back.BackgroundTransparency = 0.15
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 11)
	local st = Instance.new("UIStroke")
	st.Color = Palette.UiRim
	st.Thickness = 2
	st.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 11)
	fill.Parent = back
	local t = label(back, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 16)
	t.Text = title
	t.ZIndex = 3
	back.Parent = parent
	return fill, t
end

function Hud.toast(text: string, color: Color3?)
	local l = label(toastHolder, UDim2.new(1, 0, 0, 30), UDim2.new(), 24, color or Palette.UiGold)
	l.Text = text
	l.TextTransparency = 1
	TweenService:Create(l, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	task.delay(3, function()
		local tw = TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		l:Destroy()
	end)
end

function Hud.flash(text: string, color: Color3)
	local l = label(gui, UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 0.32, 0), 46, color)
	l.Text = text
	TweenService:Create(l, TweenInfo.new(0.9), { TextTransparency = 1, Position = UDim2.new(0, 0, 0.28, 0) }):Play()
	task.delay(1, function()
		l:Destroy()
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

	local dist = label(gui, UDim2.new(1, 0, 0, 56), UDim2.fromOffset(0, top), 52, Palette.UiGold)
	local statusL = label(gui, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, top + 58), 32)
	local alive = label(gui, UDim2.fromOffset(200, 30), UDim2.new(1, -212, 0, top), 22)
	alive.TextXAlignment = Enum.TextXAlignment.Right

	local juiceFill, juiceText = bar(gui, UDim2.fromOffset(16, top + 4), Palette.Juice, "JUICE")
	local gapFill, gapText = bar(gui, UDim2.fromOffset(16, top + 34), Palette.UiDanger, "GUARDIAN")
	local shields = label(gui, UDim2.fromOffset(240, 24), UDim2.fromOffset(16, top + 62), 18, Palette.Shield)
	shields.TextXAlignment = Enum.TextXAlignment.Left

	toastHolder = Instance.new("Frame")
	toastHolder.BackgroundTransparency = 1
	toastHolder.Size = UDim2.new(1, 0, 0, 200)
	toastHolder.Position = UDim2.new(0, 0, 0.6, 0)
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = toastHolder
	toastHolder.Parent = gui

	RunService.RenderStepped:Connect(function()
		local state = player:GetAttribute("State")
		local isRun = state == "Running" or state == "Countdown"
		statusL.Text = workspace:GetAttribute("Status") or ""
		juiceFill.Parent.Visible = isRun
		gapFill.Parent.Visible = state == "Running"
		dist.Visible = isRun or state == "Caught"
		dist.Text = string.format("%d m", player:GetAttribute("Distance") or 0)
		local a = workspace:GetAttribute("Alive") or 0
		alive.Text = (state == "Running" or state == "Caught") and string.format("%d running", a) or ""

		local juice = player:GetAttribute("Juice") or 0
		juiceFill.Size = UDim2.fromScale(math.clamp(juice / Config.JuiceMax, 0, 1), 1)
		juiceText.Text = juice <= 0 and "OUT OF JUICE!" or "JUICE"
		juiceText.TextColor3 = juice <= 0 and Palette.UiDanger or Palette.UiText

		-- Guardian gap: full = safe (60+ studs), empty = about to be caught
		local myStuds = (player:GetAttribute("Distance") or 0) * Config.StudsPerMetre
		local gap = myStuds - (workspace:GetAttribute("PaceDist") or 0)
		local g = math.clamp(gap / 60, 0, 1)
		gapFill.Size = UDim2.fromScale(1 - g, 1)
		gapText.Text = gap < 20 and "GUARDIAN CLOSE!" or "GUARDIAN"

		local s = player:GetAttribute("Shields") or 0
		shields.Text = s > 0 and string.format("Shields: %d", s) or ""
	end)
end

return Hud
