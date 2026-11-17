--!strict
-- The run's on-screen action buttons. Arrows (steer left/right: blue; Jump/Slide: gold) are
-- faceted gem arrows: a dark rim, a colour body shading light to deep, and a lighter inner facet
-- that lights up when pressed. The gadget slots (glyph "") are a see-through dark disc with a
-- thin light ring. Colours from Palette only.
--
--   ActionButton.make(parent, size, glyph) -> (button, setPressed)
--   glyph: "left" | "right" | "up" | "down" (gem arrow), "" (slot) or any text

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))

local ActionButton = {}

local REST_BG = 0.5 -- disc transparency at rest
local function inst(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- A gem arrow (pointing right; the holder is turned for other directions), drawn in layers:
-- a dark rim, the coloured body, and a lighter inner facet, each the same pentagon shape (a
-- box for the back + a square turned 45 degrees for the point) shrunk by `inset`.
local SQ2 = math.sqrt(2)
local function arrowLayer(
	holder: Frame,
	s: number,
	inset: number,
	color: Color3,
	light: Color3?,
	z: number,
	transp: number
): { GuiObject }
	-- All placed in Scale of the holder, never Offset: UDim offsets are whole numbers, which cut
	-- the turned square's side (h / sqrt 2) short, so its tip fell under the body's top edge.
	local top, bottom = math.round(0.12 * s + inset), math.round(0.88 * s - inset)
	local h = bottom - top
	local tipX = math.round(0.93 * s - inset * SQ2)
	local cx = tipX - h / 2
	-- the point's square reaches back to cx - h/2; on the thin inner facet that is behind the
	-- back edge, so the back moves to cover it (else its corner pokes out)
	local back = math.min(math.round(0.1 * s + inset), math.floor(cx - h / 2))
	local r = math.max(2, math.round(s * 0.05))
	local pieces = {}
	local function frame(x: number, w: number): Frame
		return inst("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = transp,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(x / s, top / s),
			Size = UDim2.fromScale(w / s, h / s),
			ZIndex = z,
		}, holder)
	end
	-- the back: rounded corners on the left only (a square-cornered strip covers its right
	-- corners, which used to leave a notch where the point starts)
	local body = frame(back, cx - back)
	inst("UICorner", { CornerRadius = UDim.new(0, r) }, body)
	local join = frame(cx - 2 * r, 2 * r + 1)
	-- the point: a square turned 45 degrees, sharp corners so its top and bottom meet the back
	local side = h / SQ2
	local tip = inst("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = transp,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(cx / s, (top + h / 2) / s),
		Size = UDim2.fromScale(side / s, side / s),
		Rotation = 45,
		ZIndex = z,
	}, holder)
	for _, f in { body, join, tip } do
		if light then
			-- light at the top, the colour at the bottom; the point's square is turned 45, so its
			-- gradient is turned back to stay vertical on screen
			inst("UIGradient", {
				Color = ColorSequence.new(light, color),
				Rotation = f == tip and 45 or 90,
			}, f)
			f.BackgroundColor3 = Color3.new(1, 1, 1)
		end
		table.insert(pieces, f)
	end
	return pieces
end

function ActionButton.make(parent: Instance, size: number, glyph: string): (TextButton, (boolean) -> ())
	local b = inst("TextButton", {
		Name = "Action_" .. glyph,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Palette.UiInk,
		BackgroundTransparency = REST_BG,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 2,
	}, parent)
	inst("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	local ring = inst("UIStroke", {
		Thickness = math.max(2, math.round(size * 0.035)),
		Color = Palette.UiText,
		Transparency = 0.3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, b)
	local scale = inst("UIScale", {}, b)

	local marks: { GuiObject } = {}
	local facets: { GuiObject } = {}
	local light = Palette.UiText
	local arrow = glyph == "left" or glyph == "right" or glyph == "up" or glyph == "down"
	if arrow then
		-- the gem arrow replaces the disc: steer arrows blue, jump/slide gold
		b.BackgroundTransparency = 1
		ring.Enabled = false
		local blue = glyph == "left" or glyph == "right"
		local rim = blue and Palette.BtnBlueRim or Palette.BtnGoldRim
		local base = blue and Palette.BtnBlue or Palette.BtnGold
		light = blue and Palette.BtnBlueLight or Palette.BtnGoldLight
		local holder = inst("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = ({ left = 180, right = 0, up = -90, down = 90 })[glyph] or 0,
			ZIndex = 3,
		}, b)
		arrowLayer(holder, size, 0, rim, nil, 3, 0)
		arrowLayer(holder, size, size * 0.065, base, light, 4, 0)
		for _, f in arrowLayer(holder, size, size * 0.2, light, nil, 5, 0) do
			table.insert(facets, f)
		end
		-- keep the arrow the same size if the layout resizes the button
		b:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local k = b.AbsoluteSize.X / size
			if k > 0 then
				local sc = holder:FindFirstChildOfClass("UIScale") or inst("UIScale", {}, holder)
				sc.Scale = k
			end
		end)
	elseif glyph ~= "" then
		local l = inst("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.7, 0.7),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Text = glyph,
			TextScaled = true,
			Font = Enum.Font.FredokaOne,
			TextColor3 = Palette.UiText,
			ZIndex = 4,
		}, b)
		table.insert(marks, l)
	end

	local info = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function setPressed(on: boolean)
		TweenService:Create(scale, info, { Scale = on and 0.88 or 1 }):Play()
		if arrow then
			-- pressed: the facet lights up and the gem squashes
			for _, f in facets do
				TweenService:Create(f, info, { BackgroundColor3 = on and Palette.UiText or light }):Play()
			end
			return
		end
		TweenService:Create(b, info, {
			BackgroundColor3 = on and Palette.UiText or Palette.UiInk,
			BackgroundTransparency = on and 0.1 or REST_BG,
		}):Play()
		ring.Transparency = on and 0 or 0.3
		if glyph == "" then -- the gadget slots draw their icon as the button's own text
			b.TextColor3 = on and Palette.UiInk or Palette.UiText
		end
		for _, m in marks do
			if m:IsA("TextLabel") then
				m.TextColor3 = on and Palette.UiInk or Palette.UiText
			else
				m.BackgroundColor3 = on and Palette.UiInk or Palette.UiText
			end
		end
	end
	return b, setPressed
end

return ActionButton
