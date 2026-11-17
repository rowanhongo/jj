--!strict
-- Onboarding funnel (Creator Hub > Analytics > Funnels). Each step is logged once per player per
-- server; Roblox keeps the onboarding funnel for new players. Steps must stay in this order and
-- keep their numbers, or the dashboard's history stops lining up.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Funnel = {}

Funnel.Steps = {
	Joined = { 1, "Joined" },
	Queued = { 2, "Pressed Play" },
	RunStarted = { 3, "First run started" },
	Reached100 = { 4, "Reached 100 m" },
	RunEnded = { 5, "First run ended" },
	SecondRun = { 6, "Second run started" },
	Reached500 = { 7, "Reached 500 m" },
}

local done: { [Player]: { [number]: boolean } } = {}

function Funnel.step(player: Player, which: { any })
	local n, name = which[1] :: number, which[2] :: string
	local d = done[player]
	if not d then
		d = {}
		done[player] = d
	end
	if d[n] then
		return
	end
	d[n] = true
	pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, n, name)
end

Players.PlayerRemoving:Connect(function(player)
	done[player] = nil
end)

return Funnel
