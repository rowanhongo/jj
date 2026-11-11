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

export type Profile = {
	gems: number,
	best: number, -- metres
	checkIns: number,
	lastDay: number,
	classTokens: number,
	classes: { string },
}

local DataService = {}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("JJProfile_v1")
end)

local profiles: { [Player]: Profile } = {}
local notify: (Player, string) -> () = function() end

local function default(): Profile
	return { gems = 0, best = 0, checkIns = 0, lastDay = -1, classTokens = 0, classes = {} }
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
				(p :: any)[k] = v
			end
		elseif not ok then
			warn("[JJ.Data] load failed, session-only profile:", data)
		end
	end
	profiles[player] = p
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

function DataService.submitDistance(player: Player, metres: number)
	local p = profiles[player]
	if p and metres > p.best then
		p.best = metres
		syncStats(player, p)
	end
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
