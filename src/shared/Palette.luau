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

	-- Lobby floor (warm worn temple stone; the bright Stone* colours read lime under sun)
	FloorStone = hex("7E7454"),
	FloorStoneMoss = hex("6A6648"),
	FloorStoneDark = hex("4E4838"),
	FloorPath = hex("8E7A5A"),
	FloorPathEdge = hex("766046"),
	FloorSoil = hex("3E3024"),
	FloorGap = hex("4A6E2A"),
	FloorMoss = hex("557030"),

	-- Lobby cave ceiling (same olive temple stone as the walls; moss caps on stalactites)
	CaveStone = hex("7E7858"),
	CaveStoneLight = hex("8F8A62"),
	CaveStoneDark = hex("6E6450"),
	StoneTrim = hex("B3A47E"), -- sandstone trim on the leaderboard plinths
	MossCap = hex("5E7A34"),

	-- Path
	PathSand = hex("E3C79A"),
	PathTan = hex("C9A36B"),
	WoodPlank = hex("B5773D"),
	Rope = hex("8A6A3E"),

	-- Water / sky
	Water = hex("1FA393"),
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
	Tar = hex("2B2118"), -- tar pit surface
	TarBubble = hex("4A3A2A"),
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
	UiInk = hex("1E2A1C"),
	FinishDark = hex("1A1A1A"), -- finish line chequers
	FinishLight = hex("F2F2F2"), -- text on paper, tab bar
	UiBuy = hex("3FD08A"), -- buy / play buttons

	-- Route map (client/RouteMap): floors by height against yours
	MapFloor = hex("E3C79A"), -- level with you (the path sand)
	MapHigh = hex("FFF1CC"), -- above you
	MapLow = hex("9C7A4E"), -- below you
	MapRunner = hex("FFF6DC"), -- other runners

	-- Run buttons (gem arrows): blue steer arrows, gold jump/slide; dark rim, base, light facet
	BtnBlueRim = hex("17306E"),
	BtnBlue = hex("1E8BEA"),
	BtnBlueLight = hex("6FE3FF"),
	BtnGoldRim = hex("6E2410"),
	BtnGold = hex("F28A12"),
	BtnGoldLight = hex("FFE45A"),

	-- Rarity
	Common = hex("B9C2A3"),
	Uncommon = hex("8CC63F"),
	Rare = hex("5CB8FF"),
	Epic = hex("B07CFF"),
	Mythic = hex("FF5C7A"),
})
