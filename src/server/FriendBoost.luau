--!strict
-- Friend boost: +PER% run gems for each Roblox friend in the same server, up to MAX%.
-- Kept on the player as the attribute FriendBoost (a percent) so the lobby can show it.
-- IsFriendsWithAsync is a web call: each pair is asked once and remembered.

local Players = game:GetService("Players")

local FriendBoost = {}

FriendBoost.PER = 10
FriendBoost.MAX = 100 -- 10 friends

local known: { [string]: boolean } = {}

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

local function friends(a: Player, b: Player): boolean
	local k = pairKey(a.UserId, b.UserId)
	if known[k] == nil then
		local ok, res = pcall(a.IsFriendsWithAsync, a, b.UserId)
		if not ok then
			return false -- try again next refresh
		end
		known[k] = res
	end
	return known[k]
end

local function refresh()
	local list = Players:GetPlayers()
	for _, p in list do
		local n = 0
		for _, q in list do
			if q ~= p and friends(p, q) then
				n += 1
			end
		end
		p:SetAttribute("FriendBoost", math.min(FriendBoost.MAX, n * FriendBoost.PER))
	end
end

-- gems after the boost (whole gems, rounded down)
function FriendBoost.apply(player: Player, gems: number): number
	local pct = player:GetAttribute("FriendBoost") or 0
	return math.floor(gems * (1 + pct / 100))
end

function FriendBoost.init()
	Players.PlayerAdded:Connect(function()
		task.defer(refresh)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
	task.defer(refresh)
end

return FriendBoost
