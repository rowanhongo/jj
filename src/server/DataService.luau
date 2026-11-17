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
	totalDist: number, -- lifetime metres run (leaderboard)
	gemsEarned: number, -- lifetime gems earned, spending never lowers it (leaderboard)
	wins: number, -- runs finished first with at least one other runner (leaderboard)
	runs: number,
	questDay: number, -- retired (single 12 h board); kept so old saves load
	questStamps: { [string]: number }?, -- quest set id -> period number its progress belongs to
	quests: { [string]: number }, -- quest id -> progress this period (-1 = claimed)
	settings: { [string]: any }, -- setting id -> value (shared/SettingsDefs); missing = default
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
		totalDist = 0,
		gemsEarned = 0,
		wins = 0,
		runs = 0,
		questDay = -1,
		settings = {},
		quests = {},
	}
end

-- Clears each quest set's progress when its period rolls over.
local function freshQuests(p: Profile): boolean
	local changed = false
	p.questStamps = p.questStamps or {}
	local stamps = p.questStamps :: { [string]: number }
	for _, set in Items.QuestSets do
		local now = math.floor(os.time() / set.period)
		if stamps[set.id] ~= now then
			stamps[set.id] = now
			changed = true
			for _, q in Items.Quests do
				if q.set == set.id then
					p.quests[q.id] = nil
				end
			end
		end
	end
	return changed
end

local pusher: (Player, Profile) -> () = function() end
function DataService.setPusher(fn: (Player, Profile) -> ())
	pusher = fn
end

-- Titles are earned, never bought: grant any whose achievement is met.
local function grantTitles(player: Player, p: Profile)
	for _, c in Items.Cosmetics do
		local u = c.unlock
		if u and not p.cosmetics[c.id] then
			local have = u.kind == "level" and p.level or u.kind == "rolls" and p.rolls or p.best
			if have >= u.n then
				p.cosmetics[c.id] = true
				local reward = Items.AchievementGems[c.rarity] or 0
				p.gems += reward
				p.gemsEarned += reward
				notify(player, string.format("Achievement: %s!  +%d gems", c.name, reward))
			end
		end
	end
end

local function syncStats(player: Player, p: Profile)
	grantTitles(player, p)
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
	player:SetAttribute("Best", math.floor(p.best))
	player:SetAttribute("TotalDist", math.floor(p.totalDist))
	player:SetAttribute("GemsEarned", p.gemsEarned)
	player:SetAttribute("Wins", p.wins)
	player:SetAttribute("Runs", p.runs)
	freshQuests(p)
	for _, q in Items.Quests do
		player:SetAttribute(q.id, p.quests[q.id] or 0)
	end
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
		DataService.logGems(
			player,
			false,
			Config.WeeklyGems,
			Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
			"WeeklyCheckIn"
		)
		notify(player, string.format("Check-in %d! +%d gems", n, Config.WeeklyGems))
	else
		local toNext = 7 - (n % 7)
		notify(player, string.format("Check-in %d. Reward in %d more day%s", n, toNext, toNext == 1 and "" or "s"))
	end
end

function DataService.setNotifier(fn: (Player, string) -> ())
	notify = fn
end

-- ---------- saving ----------
-- Each save key holds the profile plus a session lock: { job = JobId, t = os.time() }.
-- Everything goes through UpdateAsync, so a server only writes while it holds the lock:
--   * a player who hops servers fast waits for the old server to let go (no lost progress, no dupes)
--   * a failed load never becomes a blank profile that overwrites the real save: the player is
--     asked to rejoin instead (session-only play is for Studio without API access only)
--   * autosave every AUTOSAVE s, failed writes retried, every save flushed on shutdown
local AUTOSAVE = 60
local LOCK_STALE = 4 * AUTOSAVE -- a lock not refreshed for this long belongs to a dead server
local LOAD_TRIES = 6
local RunService = game:GetService("RunService")
local JOB = if RunService:IsStudio() then "studio-" .. game.JobId .. tostring(os.clock()) else game.JobId
local KICK = "Your Jungle Juice save couldn't be loaded safely. Please rejoin in a minute."

local saveable: { [Player]: boolean } = {} -- false: session-only, never written
local saving: { [Player]: boolean } = {}

local function key(player: Player): string
	return "u" .. player.UserId
end

-- one UpdateAsync with retries; transform returns the value to write or nil to leave it alone
local function update(k: string, transform: (any) -> any): (boolean, any)
	local s = store
	if not s then
		return false, "no store"
	end
	local err
	for i = 1, 4 do
		local ok, res = pcall(function()
			return s:UpdateAsync(k, transform)
		end)
		if ok then
			return true, res
		end
		err = res
		if RunService:IsStudio() then
			break -- Studio without API access fails every time: don't stall the load retrying
		end
		task.wait(i * 1.5)
	end
	return false, err
end

local function merge(p: Profile, data: any)
	for k, v in data do
		if k == "_lock" then
			continue
		end
		local d = (p :: any)[k]
		if type(d) == "table" and type(v) == "table" and #d == 0 then
			for k2, v2 in v do
				d[k2] = v2
			end
		else
			(p :: any)[k] = v
		end
	end
end

-- claim the save for this server: nil while someone else holds a fresh lock
local function claim(player: Player): (boolean, any)
	local got, held = nil, false
	local ok, err = update(key(player), function(old)
		local lock = type(old) == "table" and old._lock
		if type(lock) == "table" and lock.job ~= JOB and os.time() - (lock.t or 0) < LOCK_STALE then
			held = true
			return nil
		end
		held = false
		local v = if type(old) == "table" then old else {}
		v._lock = { job = JOB, t = os.time() }
		got = v
		return v
	end)
	if not ok then
		return false, err
	end
	return not held, got
end

function DataService.load(player: Player)
	local p = default()
	local live = store ~= nil
	if live then
		local data, failed = nil, nil
		for i = 1, LOAD_TRIES do
			local ok, res = claim(player)
			if ok then
				data = res
				break
			end
			failed = res
			if RunService:IsStudio() or not player.Parent then
				break
			end
			task.wait(2 + i) -- the old server is still saving them out: give it a moment
		end
		if data then
			merge(p, data)
		elseif not player.Parent then
			return
		elseif RunService:IsStudio() then
			warn("[JJ.Data] no DataStore access in Studio, session-only profile:", failed)
			live = false
		else
			warn("[JJ.Data] load failed for", player.UserId, failed)
			player:Kick(KICK)
			return
		end
	end
	if not player.Parent then
		-- left while loading: let the lock go so the next server doesn't wait for it
		if live then
			update(key(player), function(old)
				if type(old) == "table" and type(old._lock) == "table" and old._lock.job == JOB then
					old._lock = nil
					return old
				end
				return nil
			end)
		end
		return
	end
	saveable[player] = live
	-- drop gadgets that were removed from the game (Banana Peel, Thorn Trap, War Drum)
	for id in p.items do
		if not Items.get(id) then
			p.items[id] = nil
		end
	end
	for i = #p.loadout, 1, -1 do
		if not Items.get(p.loadout[i]) then
			table.remove(p.loadout, i)
		end
	end
	if #p.loadout == 0 then
		p.loadout = table.clone(Items.DefaultGadgets)
	end
	profiles[player] = p
	if RunService:IsStudio() then
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

-- write the profile if this server still holds the lock; release = let go of it (player left)
function DataService.save(player: Player, release: boolean?): boolean
	local p = profiles[player]
	if not p or not saveable[player] then
		return false
	end
	while saving[player] do
		task.wait(0.1)
	end
	saving[player] = true
	local lost = false
	local ok, err = update(key(player), function(old)
		lost = false
		local lock = type(old) == "table" and old._lock
		if type(lock) == "table" and lock.job ~= JOB then
			lost = true -- another server took over: never write over it
			return nil
		end
		local v = table.clone(p) :: any
		v._lock = if release then nil else { job = JOB, t = os.time() }
		return v
	end)
	saving[player] = nil
	if not ok then
		warn("[JJ.Data] save failed for", player.UserId, err)
	elseif lost then
		warn("[JJ.Data] save skipped, another server holds", player.UserId)
		saveable[player] = false
	end
	return ok and not lost
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Economy analytics (Creator Hub > Analytics > Economy): every gem gained is a Source, every gem
-- spent a Sink, logged after the change with the balance it left. Amounts are always positive.
-- txType is a Roblox default (Gameplay, TimedReward, Shop, ...); sku says what exactly.
-- Gems picked up on the path are added one by one but logged once per run (sku PathGems), to stay
-- well inside the analytics rate limit.
local AnalyticsService = game:GetService("AnalyticsService")
function DataService.logGems(player: Player, sink: boolean, n: number, txType: string, sku: string?)
	local p = profiles[player]
	if not p or n <= 0 then
		return
	end
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if sink then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source,
			"Gems",
			n,
			p.gems,
			txType,
			sku
		)
	end)
end

-- txType nil: added now, logged later by the caller (path pickups, summed per run)
function DataService.addGems(player: Player, n: number, txType: string?, sku: string?)
	local p = profiles[player]
	if p and n > 0 then
		p.gems += n
		p.gemsEarned += n
		syncStats(player, p)
		if txType then
			DataService.logGems(player, false, n, txType, sku)
		end
	end
end

-- One finished run: lifetime totals, wins and daily quest progress. rank is 1-based among all
-- runners (bots included); count is how many ran.
function DataService.recordRun(player: Player, metres: number, rank: number, count: number)
	local p = profiles[player]
	if not p then
		return
	end
	freshQuests(p)
	p.totalDist += metres
	p.runs += 1
	if rank == 1 and count > 1 then
		p.wins += 1
	end
	local gain = { dist = metres, runs = 1, top3 = (rank <= 3 and count > 1) and 1 or 0 }
	for _, q in Items.Quests do
		local cur = p.quests[q.id] or 0
		if cur >= 0 then
			cur = math.min(q.n, cur + gain[q.kind])
			if cur >= q.n then
				cur = -1
				p.gems += q.gems
				p.gemsEarned += q.gems
				DataService.logGems(player, false, q.gems, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, q.id)
				notify(
					player,
					string.format(
						"%s done: %s  +%d gems",
						q.set == "H" and "Quick quest" or "Daily quest",
						q.text,
						q.gems
					)
				)
			end
			p.quests[q.id] = cur
		end
	end
	syncStats(player, p)
end

-- Every loaded profile (for the in-server leaderboard fallback).
function DataService.all(): { [Player]: Profile }
	return profiles
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

function DataService.checkTitles(player: Player)
	local p = profiles[player]
	if p then
		grantTitles(player, p)
	end
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
	-- Studio only: a dev hook to grant gems to a tester (command-bar scripts get their own copy
	-- of this module, so they can't reach the live profiles directly)
	if RunService:IsStudio() then
		local f = Instance.new("BindableFunction")
		f.Name = "DevGrantGems"
		f.OnInvoke = function(player: Player, n: number)
			DataService.addGems(player, n)
			return DataService.save(player)
		end
		f.Parent = game:GetService("ServerStorage")
	end
	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			DataService.save(player, true)
		end
		profiles[player] = nil
		saveable[player] = nil
	end)
	game:BindToClose(function()
		-- every save at once: shutdown gives about 30 s in total
		local left = 0
		for player in profiles do
			left += 1
			task.spawn(function()
				DataService.save(player, true)
				left -= 1
			end)
		end
		local t = os.clock()
		while left > 0 and os.clock() - t < 25 do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player in profiles do
				task.spawn(DataService.save, player)
			end
		end
	end)
	-- roll quest boards over on the hour (and at midnight) for players sitting in the lobby
	task.spawn(function()
		while true do
			task.wait(20)
			for player, p in profiles do
				if freshQuests(p) then
					syncStats(player, p)
				end
			end
		end
	end)
end

return DataService
