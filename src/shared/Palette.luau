--!strict
-- Colour bible (docs/COLOUR_BIBLE.md). Every world part and GUI colour comes from here.
-- Sampled from the bright jungle-temple reference: saturated leaf greens, pale mossy stone,
-- warm sand paths, turquoise water, golden sunlight.

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

return table.freeze({
	-- Foliage
	CanopyBright = hex("8CC63F"),
	CanopyMid = hex("4E9A2E"),
	CanopyDeep = hex("2E5E26"),
	Trunk = hex("6B4A2B"),

	-- Stone (temple ruins)
	StoneLight = hex("C8D3A0"),
	StoneMoss = hex("9DB27A"),
	StoneShadow = hex("6E8558"),

	-- Path
	PathSand = hex("E3C79A"),
	PathTan = hex("C9A36B"),
	WoodPlank = hex("B5773D"),
	Rope = hex("8A6A3E"),

	-- Water / sky
	Water = hex("3CC2C8"),
	WaterDeep = hex("1F8E9E"),
	Cliff = hex("7E9A5E"),
	CliffFar = hex("A7C08A"),
	Sun = hex("FFF1B8"),

	-- Gameplay
	Juice = hex("FF9F1C"),
	JuiceGlow = hex("FFD23F"),
	Guardian = hex("5C6B4A"),
	GuardianEyes = hex("7CFF6B"),
	Dart = hex("D94F2B"),
	Shield = hex("5CD6FF"),
	Gem = hex("8FF3FF"),
	GemGlint = hex("E8FDFF"),

	-- GUI
	UiGold = hex("F5B83D"),
	UiRim = hex("6B3A12"),
	UiPanel = hex("1E3A24"),
	UiText = hex("FFF6DC"),
	UiDanger = hex("E2483D"),
	UiGood = hex("8CC63F"),
	UiPaper = hex("F6EFD9"), -- shop/inventory card face
	UiPaperDim = hex("E6DDC2"), -- card wells, locked items
	UiInk = hex("1E2A1C"), -- text on paper, tab bar
	UiBuy = hex("3FD08A"), -- buy / play buttons

	-- Rarity
	Common = hex("B9C2A3"),
	Uncommon = hex("8CC63F"),
	Rare = hex("5CB8FF"),
	Epic = hex("B07CFF"),
	Mythic = hex("FF5C7A"),
})
