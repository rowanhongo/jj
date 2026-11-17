--!strict
-- Anti-cheat front door for every remote the client can fire (Roblox: validate + rate-limit
-- first, detection second).
--   Guard.allow(player, name)  token bucket per player per remote: spam past the limit is dropped
--   Guard.trap(remote)         a remote no real client ever fires; firing it is a sure sign of a
--                              tampered client, so the player is kicked
-- Everything flagged is logged to Analytics (custom event "CheatFlag") so it shows on the dashboard.
-- Kicks are only for certainties (a trap, or thousands of dropped calls); everything else is just
-- ignored, so a laggy player who bursts a few calls is never punished.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Guard = {}

-- calls per second (refill) and burst size per remote
local LIMITS: { [string]: { rate: number, burst: number } } = {
	Collect = { rate = 25, burst = 40 }, -- gems and bottles come in clusters
	Dart = { rate = 3, burst = 4 },
	UseGadget = { rate = 4, burst = 6 },
	Queue = { rate = 3, burst = 6 },
	LeaveMatch = { rate = 2, burst = 4 },
	TigerHit = { rate = 2, burst = 4 },
	TestBoost = { rate = 1, burst = 2 },
	ShopCall = { rate = 8, burst = 15 },
}
local SPAM_KICK = 2000 -- dropped calls within one minute

type Bucket = { tokens: number, at: number }
local buckets: { [Player]: { [string]: Bucket } } = {}
local dropped: { [Player]: { n: number, since: number } } = {}
local flagged: { [Player]: { [string]: boolean } } = {}

local KICK = "Something went wrong with your connection to Jungle Juice. Please rejoin."

local function flag(player: Player, reason: string)
	flagged[player] = flagged[player] or {}
	if flagged[player][reason] then
		return
	end
	flagged[player][reason] = true
	warn("[JJ.Guard]", player.UserId, reason)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "CheatFlag", 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = reason,
		})
	end)
end
Guard.flag = flag

function Guard.allow(player: Player, name: string): boolean
	local lim = LIMITS[name]
	if not lim then
		return true
	end
	local now = os.clock()
	local mine = buckets[player]
	if not mine then
		mine = {}
		buckets[player] = mine
	end
	local b = mine[name]
	if not b then
		b = { tokens = lim.burst, at = now }
		mine[name] = b
	end
	b.tokens = math.min(lim.burst, b.tokens + (now - b.at) * lim.rate)
	b.at = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	local d = dropped[player]
	if not d or now - d.since > 60 then
		d = { n = 0, since = now }
		dropped[player] = d
	end
	d.n += 1
	if d.n == 50 then
		flag(player, "spam:" .. name)
	elseif d.n >= SPAM_KICK and not RunService:IsStudio() then
		flag(player, "spamkick:" .. name)
		player:Kick(KICK)
	end
	return false
end

-- a server-to-client remote (or a decoy): any call from a client is tampering
function Guard.trap(remote: RemoteEvent)
	remote.OnServerEvent:Connect(function(player)
		flag(player, "trap:" .. remote.Name)
		if not RunService:IsStudio() then
			player:Kick(KICK)
		end
	end)
end

Players.PlayerRemoving:Connect(function(p)
	buckets[p], dropped[p], flagged[p] = nil, nil, nil
end)

return Guard
