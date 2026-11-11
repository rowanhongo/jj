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
	{ id = "JuiceFlask", name = "Juice Flask", rarity = "Common", icon = "🧃", desc = "Gulp down a big splash of juice." },
	{ id = "VineShield", name = "Vine Shield", rarity = "Common", icon = "🛡️", desc = "Your next stumble is ignored." },
	{ id = "SprintLeaf", name = "Sprint Leaf", rarity = "Common", icon = "🍃", desc = "Run 35% faster for 4 seconds." },
	{ id = "BananaPeel", name = "Banana Peel", rarity = "Uncommon", icon = "🍌", desc = "Drop a peel behind you. Runners who step on it trip." },
	{ id = "HoneyJar", name = "Honey Jar", rarity = "Uncommon", icon = "🍯", desc = "Juice stops draining for 8 seconds." },
	{ id = "BaitFruit", name = "Bait Fruit", rarity = "Rare", icon = "🍍", desc = "Toss bait back. The Guardian stops to eat it." },
	{ id = "ThornTrap", name = "Thorn Trap", rarity = "Rare", icon = "🌵", desc = "A thorn line across the path behind you. Jump it or trip." },
	{ id = "GrappleVine", name = "Grapple Vine", rarity = "Epic", icon = "🐒", desc = "Swing forward over anything in your way." },
	{ id = "WarDrum", name = "War Drum", rarity = "Epic", icon = "🥁", desc = "Every other runner slows down for 2 seconds." },
	{ id = "SpiritWings", name = "Spirit Wings", rarity = "Mythic", icon = "🕊️", desc = "Glide for 5 seconds. Gaps can't drop you." },
	{ id = "GoldenIdol", name = "Golden Idol", rarity = "Mythic", icon = "🗿", desc = "The Guardian chases the idol back. Plus 25 gems." },
} :: { Gadget }

Items.DefaultGadgets = { "JuiceFlask", "VineShield", "SprintLeaf" }
Items.LoadoutSize = 3
Items.SlotCount = 2

-- Roll prices in gems. Pity: guaranteed rarity at least every N rolls.
Items.RollPrice = 100
Items.Roll10Price = 800 -- 10 rolls for the price of 8
Items.Pity = { Rare = 10, Epic = 25, Mythic = 80 }

-- Titles are never sold: each one unlocks from an achievement (unlock.kind = level | best | rolls).
export type Cosmetic = { id: string, name: string, kind: "Title" | "Emote" | "Trail", rarity: Rarity, price: number, emote: string?, colour: string?, unlock: { kind: string, n: number, text: string }? }

Items.Cosmetics = {
	{ id = "T_Rookie", name = "Rookie", kind = "Title", rarity = "Common", price = 0 },
	{ id = "T_Vine", name = "Vine Swinger", kind = "Title", rarity = "Common", price = 0, unlock = { kind = "best", n = 250, text = "Run 250 m" } },
	{ id = "T_Junkie", name = "Juice Junkie", kind = "Title", rarity = "Uncommon", price = 0, unlock = { kind = "level", n = 5, text = "Reach level 5" } },
	{ id = "T_Gambler", name = "High Roller", kind = "Title", rarity = "Rare", price = 0, unlock = { kind = "rolls", n = 50, text = "Roll 50 times" } },
	{ id = "T_Bait", name = "Guardian Bait", kind = "Title", rarity = "Rare", price = 0, unlock = { kind = "best", n = 1000, text = "Run 1,000 m" } },
	{ id = "T_Raider", name = "Temple Raider", kind = "Title", rarity = "Epic", price = 0, unlock = { kind = "level", n = 20, text = "Reach level 20" } },
	{ id = "T_Untouch", name = "Untouchable", kind = "Title", rarity = "Mythic", price = 0, unlock = { kind = "best", n = 3000, text = "Run 3,000 m" } },
	{ id = "E_Wave", name = "Wave", kind = "Emote", rarity = "Common", price = 0, emote = "wave" },
	{ id = "E_Cheer", name = "Cheer", kind = "Emote", rarity = "Common", price = 150, emote = "cheer" },
	{ id = "E_Point", name = "Point", kind = "Emote", rarity = "Common", price = 150, emote = "point" },
	{ id = "E_Laugh", name = "Laugh", kind = "Emote", rarity = "Uncommon", price = 250, emote = "laugh" },
	{ id = "E_Dance", name = "Jungle Jig", kind = "Emote", rarity = "Rare", price = 400, emote = "dance" },
	{ id = "E_Dance2", name = "Temple Shuffle", kind = "Emote", rarity = "Epic", price = 700, emote = "dance2" },
	{ id = "E_Dance3", name = "Idol Boogie", kind = "Emote", rarity = "Epic", price = 700, emote = "dance3" },
	{ id = "R_Juice", name = "Juice Splash", kind = "Trail", rarity = "Uncommon", price = 300, colour = "Juice" },
	{ id = "R_Leaf", name = "Leaf Rush", kind = "Trail", rarity = "Rare", price = 450, colour = "CanopyBright" },
	{ id = "R_Gem", name = "Diamond Dust", kind = "Trail", rarity = "Epic", price = 800, colour = "Gem" },
} :: { Cosmetic }

Items.DefaultCosmetics = { "T_Rookie", "E_Wave" }
Items.DailySlots = 4

-- Game modes. Only Stampede is playable today; the rest show as coming soon.
export type Mode = { id: string, name: string, icon: string, blurb: string, live: boolean }
Items.Modes = {
	{ id = "Stampede", name = "Stampede", icon = "🏃", blurb = "Everyone runs. The Guardian eats the slowest.", live = true },
	{ id = "Hunted", name = "Hunted", icon = "🎯", blurb = "One runner is marked. Everyone darts them.", live = false },
	{ id = "Chained", name = "Chained", icon = "⛓️", blurb = "Run in pairs, tied by a vine.", live = false },
	{ id = "HotPotato", name = "Hot Coconut", icon = "🥥", blurb = "Pass the coconut before it blows.", live = false },
} :: { Mode }

-- Robux gem packs (product ids are filled in once the products exist on the site).
Items.GemPacks = {
	{ gems = 500, robux = 49, productId = 0 },
	{ gems = 1200, robux = 99, productId = 0, tag = "+20%" },
	{ gems = 3500, robux = 249, productId = 0, tag = "Best value" },
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

return Items
