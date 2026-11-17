--!strict
-- Badges. Create each one in Creator Hub (Experience > Engagement > Badges), then paste its id
-- here; a 0 id is skipped, so this is safe to ship before they exist.
-- Awarded on the server only; each award is checked with UserHasBadgeAsync first and remembered
-- for the session, so a badge is never asked for twice.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local Badges = {}

Badges.ids = {
	FirstRun = 0, -- finish your first run
	Podium = 0, -- finish in the top 3 (with at least one other runner)
	Winner = 0, -- win a run
	Run1000 = 0, -- 1,000 m in one run
	Run3000 = 0, -- 3,000 m in one run
	Level10 = 0, -- reach level 10
	WithFriend = 0, -- play a run with a Roblox friend in the server
}

local done: { [Player]: { [string]: boolean } } = {}

function Badges.award(player: Player, key: string)
	local id = (Badges.ids :: any)[key]
	if type(id) ~= "number" or id == 0 then
		return
	end
	local mine = done[player]
	if not mine then
		mine = {}
		done[player] = mine
	end
	if mine[key] then
		return
	end
	mine[key] = true
	task.spawn(function()
		local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
		if ok and not has then
			local okA, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
			if not okA then
				warn("[JJ.Badges] award failed", key, err)
				mine[key] = nil -- try again next time
			end
		elseif not ok then
			mine[key] = nil
		end
	end)
end

-- everything a finished run can earn
function Badges.afterRun(player: Player, metres: number, rank: number, count: number)
	Badges.award(player, "FirstRun")
	if count > 1 and rank <= 3 then
		Badges.award(player, "Podium")
	end
	if count > 1 and rank == 1 then
		Badges.award(player, "Winner")
	end
	if metres >= 1000 then
		Badges.award(player, "Run1000")
	end
	if metres >= 3000 then
		Badges.award(player, "Run3000")
	end
	if (player:GetAttribute("FriendBoost") or 0) > 0 then
		Badges.award(player, "WithFriend")
	end
	if (player:GetAttribute("Level") or 0) >= 10 then
		Badges.award(player, "Level10")
	end
end

Players.PlayerRemoving:Connect(function(p)
	done[p] = nil
end)

return Badges
