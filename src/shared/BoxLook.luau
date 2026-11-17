--!strict
-- The gadget ? box look: a glass tile in cool rainbow tints (cyan, blue, violet) with a bright
-- rim, a white sheen streak and a big white "?" with a dark tinted outline. Not tied to any one
-- map's theme. Drawn with GUI only, so the same face is used on every side of the 3D box
-- (SurfaceGuis, server: Segments) and for the pop on screen when you pick one up (client: Lobby).
-- Colours from Palette only.

local Palette = require(script.Parent.Palette)

local BoxLook = {}

-- the rainbow for the box's glow (all Palette colours), looping back to the start
local BOW =
	{ Palette.Mythic, Palette.Juice, Palette.JuiceGlow, Palette.Uncommon, Palette.Gem, Palette.Rare, Palette.Epic }
local keys = {}
for i, c in BOW do
	table.insert(keys, ColorSequenceKeypoint.new((i - 1) / #BOW, c))
end
table.insert(keys, ColorSequenceKeypoint.new(1, BOW[1]))
BoxLook.RAINBOW = ColorSequence.new(keys)

-- a colour on the rainbow, t in 0..1 (wraps)
function BoxLook.hue(t: number): Color3
	t = t % 1
	local n = #BOW
	local f = t * n
	local i = math.floor(f)
	return BOW[i + 1]:Lerp(BOW[(i + 1) % n + 1], f - i)
end

-- A soft rainbow aura behind a GuiObject, the same shape as it (`corner`: its UICorner
-- radius as a fraction of its size; 0.5 = round). Three stacked glows, each a little bigger and
-- fainter, in slowly turning rainbow colours: reads as a glow, not a drawn ring. `strength` 0..1
-- scales how visible it is. Returns the aura frame; the caller fades or destroys it.
function BoxLook.aura(around: GuiObject, corner: number, strength: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Aura"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = math.max(1, around.ZIndex - 1)
	local grads = {}
	for i, k in { 1.1, 1.24, 1.4 } do
		local g = Instance.new("Frame")
		g.Name = "Glow"
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		g.Size = UDim2.fromScale(k, k)
		g.BorderSizePixel = 0
		g.BackgroundColor3 = Color3.new(1, 1, 1)
		g.BackgroundTransparency = 1 - strength * ({ 0.62, 0.4, 0.22 })[i]
		g.ZIndex = holder.ZIndex
		g:SetAttribute("Base", g.BackgroundTransparency)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(corner >= 0.5 and 1 or math.min(0.5, corner + 0.06 * i), 0)
		c.Parent = g
		local gr = Instance.new("UIGradient")
		gr.Color = BoxLook.RAINBOW
		gr.Parent = g
		table.insert(grads, gr)
		g.Parent = holder
	end
	holder.Parent = around
	task.spawn(function()
		while holder.Parent do
			local r = (os.clock() * 70) % 360
			for i, gr in grads do
				gr.Rotation = r + i * 40
			end
			task.wait()
		end
	end)
	return holder
end

local function new(class: string, props: { [string]: any }, parent: Instance): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	i.Parent = parent
	return i
end

-- Fills `parent` (a SurfaceGui or any GuiObject) with the box face. `px` is roughly the face's
-- width in pixels, for line thicknesses. Returns the tile frame.
function BoxLook.face(parent: Instance, px: number, z: number?): Frame
	local zi = z or 1
	local tile = new("Frame", {
		Name = "BoxFace",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = zi,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0.05, 0) }, tile)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Palette.Gem),
			ColorSequenceKeypoint.new(0.3, Palette.Rare),
			ColorSequenceKeypoint.new(0.62, Palette.Epic),
			ColorSequenceKeypoint.new(0.85, Palette.Rare),
			ColorSequenceKeypoint.new(1, Palette.Uncommon),
		}),
		Rotation = 40,
	}, tile)
	new("UIStroke", {
		Color = Palette.GemGlint,
		Thickness = math.max(2, px * 0.045),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, tile)
	-- soft lighter pane in the middle: the "glass" depth
	local pane = new("Frame", {
		Size = UDim2.fromScale(0.74, 0.74),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Palette.GemGlint,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		ZIndex = zi + 1,
	}, tile)
	new("UICorner", { CornerRadius = UDim.new(0.1, 0) }, pane)
	-- sheen streak across the top-left corner
	new("Frame", {
		Size = UDim2.fromScale(1.6, 0.07),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.32, 0.24),
		Rotation = -38,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = zi + 2,
	}, tile)
	local q = new("TextLabel", {
		Size = UDim2.fromScale(0.92, 0.92),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		BackgroundTransparency = 1,
		Text = "?",
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = zi + 3,
	}, tile)
	local qs = new("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = math.max(3, px * 0.075),
	}, q)
	-- the outline shades from dark brown through violet, like a tinted glass edge
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Palette.UiInk),
			ColorSequenceKeypoint.new(0.5, Palette.UiRim),
			ColorSequenceKeypoint.new(1, Palette.Epic),
		}),
		Rotation = 90,
	}, qs)
	return tile
end

-- Dresses an anchored part as the 3D box: the part itself is invisible and every side gets the
-- face. Clients spin and bob it (client/Lobby).
function BoxLook.dress(part: BasePart)
	part.Transparency = 1
	for _, face in Enum.NormalId:GetEnumItems() do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.Brightness = 1.4
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		BoxLook.face(sg, part.Size.X * 40)
		sg.Parent = part
	end
	local light = Instance.new("PointLight")
	light.Color = Palette.Gem
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = part
end

return BoxLook
