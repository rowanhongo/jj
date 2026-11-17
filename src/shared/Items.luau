--!strict
-- Catalog: gadgets (rolled), cosmetics (daily shop), game modes, roll prices.
-- Gadgets are what a ? box hands you mid-run. You pick up to 3 in your loadout; a box
-- gives one of them at random into one of your 2 gadget slots.

local Items = {}

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Mythic"

Items.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Mythic" } :: { Rarity }
-- Percent chance a roll lands on each rarity (sums to 100).
Items.RarityWeight = { Common = 55, Uncommon = 26, Rare = 13, Epic = 5, Mythic = 1 }

export type Gadget = { id: string, name: string, rarity: Rarity, icon: string, desc: string }

Items.Gadgets = {
	-- Wild-themed (not tied to one map). Ids are kept from the first set so saved loadouts stay
	-- valid. Anything that hits another runner lasts under a second (Wild Hex: 2 s) and never
	-- knocks anyone out.
	{
		id = "JuiceFlask",
		name = "Juice Box",
		rarity = "Common",
		icon = "🧃",
		desc = "Refills a big splash of juice.",
	},
	{ id = "SprintLeaf", name = "Wild Dash", rarity = "Common", icon = "💨", desc = "Run 35% faster for 4 seconds." },
	{
		id = "BubbleTrap",
		name = "Bubble Trap",
		rarity = "Common",
		icon = "🫧",
		desc = "Drops a bubble in front of the runner ahead. Whoever hits it floats for 0.9 s.",
	},
	{
		id = "HoneyJar",
		name = "Bar Freeze",
		rarity = "Uncommon",
		icon = "⏸️",
		desc = "Your juice bar stops draining for 8 seconds.",
	},
	{
		id = "ShellShield",
		name = "Shell Shield",
		rarity = "Uncommon",
		icon = "🛡️",
		desc = "Blocks the next ability or bump that hits you.",
	},
	{
		id = "WildHex",
		name = "Wild Hex",
		rarity = "Uncommon",
		icon = "🐔",
		desc = "Turns the runner ahead into a chicken, skeleton or frog for 2 s (10% slower).",
	},
	{
		id = "GemMagnet",
		name = "Gem Magnet",
		rarity = "Uncommon",
		icon = "🧲",
		desc = "Pulls in every gem nearby for 6 seconds.",
	},
	{
		id = "BaitFruit",
		name = "Decoy Snack",
		rarity = "Rare",
		icon = "🍖",
		desc = "Toss a snack back. The Guardian stops to eat it.",
	},
	{
		id = "SpearThrow",
		name = "Spear Throw",
		rarity = "Rare",
		icon = "🔱",
		desc = "Pins the runner ahead in place for 0.9 s.",
	},
	{
		id = "FrostBreath",
		name = "Frost Breath",
		rarity = "Rare",
		icon = "❄️",
		desc = "Freezes the runner ahead in ice for 0.9 s.",
	},
	{
		id = "GrappleVine",
		name = "Grapple Hook",
		rarity = "Epic",
		icon = "🪝",
		desc = "Swing forward over anything in your way.",
	},
	{
		id = "RocketBoots",
		name = "Rocket Boots",
		rarity = "Epic",
		icon = "🚀",
		desc = "A huge rocket jump, high over anything ahead.",
	},
	{
		id = "SpiritWings",
		name = "Glider",
		rarity = "Mythic",
		icon = "🪂",
		desc = "Glide for 5 s. Use it while falling and it carries you back up.",
	},
	{
		id = "GoldenIdol",
		name = "Mighty Roar",
		rarity = "Mythic",
		icon = "🦁",
		desc = "Roar the Guardian far back down the track. Plus 3 gems.",
	},
} :: { Gadget }

Items.DefaultGadgets = { "JuiceFlask", "SprintLeaf" }
Items.LoadoutSize = 3
Items.SlotCount = 2

-- Roll prices in gems. Pity: guaranteed rarity at least every N rolls.
Items.RollPrice = 1000
Items.Roll10Price = 8000 -- 10 rolls for the price of 8
Items.Pity = { Rare = 10, Epic = 25, Mythic = 80 }

-- Titles are never sold: each one unlocks from an achievement (unlock.kind = level | best | rolls).
export type Cosmetic = {
	id: string,
	name: string,
	kind: "Title" | "Emote" | "Trail",
	rarity: Rarity,
	price: number,
	emote: string?,
	colour: string?,
	unlock: { kind: string, n: number, text: string }?,
}

-- Achievements (Inventory > Achievements): every title is earned by one, and earning it pays a
-- small gem reward by rarity (a roll is 1000, so these are a nudge, not an income).
Items.AchievementGems = { Common = 25, Uncommon = 50, Rare = 100, Epic = 200, Mythic = 400 }

Items.Cosmetics = {
	{ id = "T_Rookie", name = "Rookie", kind = "Title", rarity = "Common", price = 0 },
	{
		id = "T_Vine",
		name = "Vine Swinger",
		kind = "Title",
		rarity = "Common",
		price = 0,
		unlock = { kind = "best", n = 250, text = "Run 250 m" },
	},
	{
		id = "T_Junkie",
		name = "Juice Junkie",
		kind = "Title",
		rarity = "Uncommon",
		price = 0,
		unlock = { kind = "level", n = 5, text = "Reach level 5" },
	},
	{
		id = "T_Gambler",
		name = "High Roller",
		kind = "Title",
		rarity = "Rare",
		price = 0,
		unlock = { kind = "rolls", n = 50, text = "Roll 50 times" },
	},
	{
		id = "T_Bait",
		name = "Guardian Bait",
		kind = "Title",
		rarity = "Rare",
		price = 0,
		unlock = { kind = "best", n = 1000, text = "Run 1,000 m" },
	},
	{
		id = "T_Raider",
		name = "Temple Raider",
		kind = "Title",
		rarity = "Epic",
		price = 0,
		unlock = { kind = "level", n = 20, text = "Reach level 20" },
	},
	{
		id = "T_Untouch",
		name = "Untouchable",
		kind = "Title",
		rarity = "Mythic",
		price = 0,
		unlock = { kind = "best", n = 3000, text = "Run 3,000 m" },
	},
	{ id = "E_Wave", name = "Wave", kind = "Emote", rarity = "Common", price = 0, emote = "wave" },
	{ id = "E_Cheer", name = "Cheer", kind = "Emote", rarity = "Common", price = 1500, emote = "cheer" },
	{ id = "E_Point", name = "Point", kind = "Emote", rarity = "Common", price = 1500, emote = "point" },
	{ id = "E_Laugh", name = "Laugh", kind = "Emote", rarity = "Uncommon", price = 2500, emote = "laugh" },
	{ id = "E_Dance", name = "Jungle Jig", kind = "Emote", rarity = "Rare", price = 4000, emote = "dance" },
	{ id = "E_Dance2", name = "Temple Shuffle", kind = "Emote", rarity = "Epic", price = 7000, emote = "dance2" },
	{ id = "E_Dance3", name = "Idol Boogie", kind = "Emote", rarity = "Epic", price = 7000, emote = "dance3" },
	{ id = "R_Juice", name = "Juice Splash", kind = "Trail", rarity = "Uncommon", price = 3000, colour = "Juice" },
	{ id = "R_Leaf", name = "Leaf Rush", kind = "Trail", rarity = "Rare", price = 4500, colour = "CanopyBright" },
	{ id = "R_Gem", name = "Diamond Dust", kind = "Trail", rarity = "Epic", price = 8000, colour = "Gem" },
} :: { Cosmetic }

Items.DefaultCosmetics = { "T_Rookie", "E_Wave" }
Items.DailySlots = 4

-- Game modes. Only Stampede is playable today; the rest show as coming soon.
export type Mode = { id: string, name: string, icon: string, blurb: string, live: boolean }
Items.Modes = {
	{
		id = "Stampede",
		name = "Standard",
		icon = "🏃",
		blurb = "Reach the goal distance before the Guardian gets you. Everyone who makes it wins!",
		live = true,
	},
	{
		id = "Endless",
		name = "Endless",
		icon = "♾️",
		blurb = "On your own, no finish line. Run until you're caught and beat your best.",
		live = false,
	},
	{
		id = "Hunted",
		name = "Hunted",
		icon = "🎯",
		blurb = "One runner is marked. Everyone darts them.",
		live = false,
	},
	{ id = "Chained", name = "Chained", icon = "⛓️", blurb = "Run in pairs, tied by a vine.", live = false },
	{
		id = "HotPotato",
		name = "Hot Coconut",
		icon = "🥥",
		blurb = "Pass the coconut before it blows.",
		live = false,
	},
} :: { Mode }

-- Quests: two boards, the same quests for everyone. Reward is paid the moment one completes.
--   kind: dist (metres run), runs (runs finished), top3 (runs finished in the top 3)
-- Quick (every 10 min): small goals you always finish in one sitting, a fresh set while you play.
-- Daily (00:00 UTC): bigger goals, bigger pay, a reason to come back tomorrow.
-- board = the QuestBoard model in LobbyBuilding that shows the set.
Items.QuestSets = {
	{ id = "H", name = "QUICK QUESTS", period = 600, board = "QuestBoardHourly" },
	{ id = "D", name = "DAILY QUESTS", period = 86400, board = "QuestBoard" },
}

Items.Quests = {
	{ id = "QH_Runs", set = "H", kind = "runs", n = 2, gems = 3, text = "Finish 2 runs" },
	{ id = "QH_Dist", set = "H", kind = "dist", n = 500, gems = 5, text = "Run 500 m in total" },
	{ id = "QH_Top3", set = "H", kind = "top3", n = 1, gems = 8, text = "Finish a run in the top 3" },
	{ id = "QD_Dist", set = "D", kind = "dist", n = 3000, gems = 30, text = "Run 3,000 m in total" },
	{ id = "QD_Runs", set = "D", kind = "runs", n = 8, gems = 25, text = "Finish 8 runs" },
	{ id = "QD_Top3", set = "D", kind = "top3", n = 3, gems = 50, text = "Finish 3 runs in the top 3" },
}

-- Robux gem packs (product ids are filled in once the products exist on the site).
Items.GemPacks = {
	{ gems = 1000, robux = 49, productId = 0 },
	{ gems = 2400, robux = 99, productId = 0, tag = "+20%" },
	{ gems = 7000, robux = 249, productId = 0, tag = "Best value" },
}

local byId: { [string]: any } = {}
for _, g in Items.Gadgets do
	byId[g.id] = g
end
for _, c in Items.Cosmetics do
	byId[c.id] = c
end
function Items.get(id: string): any
	return byId[id]
end

function Items.rarityChance(id: string): number
	local g = byId[id]
	local n = 0
	for _, o in Items.Gadgets do
		if o.rarity == g.rarity then
			n += 1
		end
	end
	return Items.RarityWeight[g.rarity] / n
end

-- XP needed to go from level L to L+1.
function Items.xpFor(level: number): number
	return 150 + 150 * level
end

-- Ability art: one 1024x1024 sheet (rbxassetid 105037341301724), a 4x4 grid of 256 px cells,
-- read left to right, top to bottom.
Items.IconSheet = "rbxassetid://105037341301724"
local CELL = {
	JuiceFlask = 0,
	SprintLeaf = 1,
	HoneyJar = 2,
	BaitFruit = 3,
	GrappleVine = 4,
	GoldenIdol = 5,
	SpiritWings = 6,
	RocketBoots = 7,
	ShellShield = 8,
	GemMagnet = 9,
	SpearThrow = 10,
	FrostBreath = 11,
	WildHex = 12,
	BubbleTrap = 13,
}
function Items.iconRect(id: string): Vector2?
	local c = CELL[id]
	return c and Vector2.new((c % 4) * 256, math.floor(c / 4) * 256)
end
-- puts (or updates) the ability's art in `parent`; clears it when id has no art
function Items.iconInto(parent: Instance, id: string?, scale: number?): ImageLabel?
	local img = parent:FindFirstChild("ItemArt") :: ImageLabel?
	local off = id and Items.iconRect(id)
	if not off then
		if img then
			img:Destroy()
		end
		return nil
	end
	if not img then
		local n = Instance.new("ImageLabel")
		n.Name = "ItemArt"
		n.BackgroundTransparency = 1
		n.Image = Items.IconSheet
		n.ImageRectSize = Vector2.new(256, 256)
		n.ScaleType = Enum.ScaleType.Fit
		n.AnchorPoint = Vector2.new(0.5, 0.5)
		n.Position = UDim2.fromScale(0.5, 0.5)
		n.ZIndex = 3
		n.Parent = parent
		img = n
	end
	local im = img :: ImageLabel
	-- always drawn above whatever it sits in (a button's dark disc would otherwise cover it)
	if parent:IsA("GuiObject") then
		im.ZIndex = parent.ZIndex + 2
	end
	im.Size = UDim2.fromScale(scale or 0.8, scale or 0.8)
	im.ImageRectOffset = off
	return im
end
function Items.byName(name: string)
	for _, g in Items.Gadgets do
		if g.name == name then
			return g
		end
	end
	return nil
end

return Items
