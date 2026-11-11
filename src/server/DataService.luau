--!strict
-- Player save: gems, best distance, and the lifetime check-in count.
-- Check-ins never reset. Each new UTC day you join adds one.
--   every 7th check-in  -> Config.WeeklyGems
--   every 14th check-in -> one class token (pick any class); it replaces the gems that day
-- Falls back to a session-only profile when DataStores are unavailable (e.g. Studio without API access).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)

export type Profile = {
	gems: number,
	best: number, -- metres
	checkIns: number,
	lastDay: number,
	classTokens: number,
	classes: { string },
	xp: number,
	level: number,
	items: { [string]: number }, -- gadget id -> copies owned (1 = owned, more = duplicates)
	loadout: { string },
	cosmetics: { [string]: boolean },
	equipped: { [string]: string }, -- Title / Emote / Trail -> cosmetic id
	records: { [string]: number }, -- mode id -> best metres
	pity: { [string]: number }, -- rarity -> rolls since last at least that rarity
	showcase: string, -- mode whose record floats above your head
	rolls: number,
}

local DataService = {}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("JJProfile_v1")
end)

local profiles: { [Player]: Profile } = {}
local notify: (Player, string) -> () = function() end

local function default(): Profile
	local items, cos = {}, {}
	for _, id in Items.DefaultGadgets do
		items[id] = 1
	end
	for _, id in Items.DefaultCosmetics do
		cos[id] = true
	end
	return {
		gems = 0,
		best = 0,
		checkIns = 0,
		lastDay = -1,
		classTokens = 0,
		classes = {},
		xp = 0,
		level = 1,
		items = items,
		loadout = table.clone(Items.DefaultGadgets),
		cosmetics = cos,
		equipped = { Title = "T_Rookie", Emote = "E_Wave" },
		records = {},
		pity = { Rare = 0, Epic = 0, Mythic = 0 },
		showcase = "Stampede",
		rolls = 0,
	}
end

local pusher: (Player, Profile) -> () = function() end
function DataService.setPusher(fn: (Player, Profile) -> ())
	pusher = fn
end

local function syncStats(player: Player, p: Profile)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local best = Instance.new("IntValue")
		best.Name = "Best"
		best.Parent = ls
		local gems = Instance.new("IntValue")
		gems.Name = "Gems"
		gems.Parent = ls
		ls.Parent = player
	end
	(ls :: any).Best.Value = math.floor(p.best);
	(ls :: any).Gems.Value = p.gems
	player:SetAttribute("CheckIns", p.checkIns)
	player:SetAttribute("ClassTokens", p.classTokens)
	player:SetAttribute("Gems", p.gems)
	player:SetAttribute("Level", p.level)
	player:SetAttribute("Xp", p.xp)
	local title = Items.get(p.equipped.Title or "")
	player:SetAttribute("Title", title and title.name or "")
	player:SetAttribute("Showcase", p.showcase)
	player:SetAttribute("ShowcaseBest", p.records[p.showcase] or 0)
	player:SetAttribute("Trail", p.equipped.Trail or "")
	pusher(player, p)
end

function DataService.sync(player: Player)
	local p = profiles[player]
	if p then
		syncStats(player, p)
	end
end

local function checkIn(player: Player, p: Profile)
	local today = math.floor(os.time() / 86400)
	if today <= p.lastDay then
		return
	end
	p.lastDay = today
	p.checkIns += 1
	local n = p.checkIns
	if n % Config.ClassTokenEvery == 0 then
		p.classTokens += 1
		notify(player, string.format("Check-in %d! You earned a FREE CLASS of your choice", n))
	elseif n % 7 == 0 then
		p.gems += Config.WeeklyGems
		notify(player, string.format("Check-in %d! +%d gems", n, Config.WeeklyGems))
	else
		local toNext = 7 - (n % 7)
		notify(player, string.format("Check-in %d. Reward in %d more day%s", n, toNext, toNext == 1 and "" or "s"))
	end
end

function DataService.setNotifier(fn: (Player, string) -> ())
	notify = fn
end

function DataService.load(player: Player)
	local p = default()
	local s = store
	if s then
		local ok, data = pcall(function()
			return s:GetAsync("u" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			for k, v in data do
				local d = (p :: any)[k]
				if type(d) == "table" and type(v) == "table" and #d == 0 then
					for k2, v2 in v do
						d[k2] = v2
					end
				else
					(p :: any)[k] = v
				end
			end
		elseif not ok then
			warn("[JJ.Data] load failed, session-only profile:", data)
		end
	end
	profiles[player] = p
	if game:GetService("RunService"):IsStudio() then
		-- Studio testing: set the DevGems attribute on a player to grant that many gems.
		player:GetAttributeChangedSignal("DevGems"):Connect(function()
			local n = player:GetAttribute("DevGems")
			if type(n) == "number" and n > 0 then
				p.gems += n
				syncStats(player, p)
			end
		end)
	end
	checkIn(player, p)
	syncStats(player, p)
end

function DataService.save(player: Player)
	local p = profiles[player]
	local s = store
	if not p or not s then
		return
	end
	local ok, err = pcall(function()
		s:SetAsync("u" .. player.UserId, p)
	end)
	if not ok then
		warn("[JJ.Data] save failed:", err)
	end
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

function DataService.addGems(player: Player, n: number)
	local p = profiles[player]
	if p and n > 0 then
		p.gems += n
		syncStats(player, p)
	end
end

function DataService.submitDistance(player: Player, metres: number, mode: string?)
	local p = profiles[player]
	if not p then
		return
	end
	local m = mode or "Stampede"
	if metres > (p.records[m] or 0) then
		p.records[m] = metres
	end
	if metres > p.best then
		p.best = metres
	end
	syncStats(player, p)
end

function DataService.addXp(player: Player, n: number)
	local p = profiles[player]
	if not p or n <= 0 then
		return
	end
	p.xp += n
	while p.xp >= Items.xpFor(p.level) do
		p.xp -= Items.xpFor(p.level)
		p.level += 1
		notify(player, string.format("LEVEL UP! You're level %d", p.level))
	end
	syncStats(player, p)
end

function DataService.init()
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		profiles[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			DataService.save(player)
		end
	end)
end

return DataService
