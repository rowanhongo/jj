--!strict
-- All tuning numbers in one place.

return table.freeze({
	-- Path
	PathWidth = 32, -- studs, floor width of a normal segment (3 lanes of PathWidth/3; room for 12 runners)
	WallHeight = 5,
	GenerateAhead = 520, -- keep this many studs of path past the leader
	DeleteBehind = 160, -- delete segments this far behind the Guardian
	StudsPerMetre = 3.5, -- HUD distance = studs / this

	-- Running
	RunSpeedStart = 35,
	MaxSpeedFactor = 2.2, -- server cap on distance gained per second, as a multiple of run speed (anti-cheat)
	-- run speed grows slowly: x1.15 at 5 min, x1.25 at 10 min, x1.35 at 15 min (then stays)
	RunSpeedSteps = { { 0, 1 }, { 30, 1.1 }, { 75, 1.2 }, { 130, 1.3 } }, -- goals are ~2-4 min now
	SteerFactor = 0.75, -- sideways share of movement at full stick
	SlideSeconds = 0.8,
	StumbleSeconds = 0.75,
	StumbleSpeedMul = 0.35,
	WallBumpCooldown = 1.2,

	-- Pace line / Guardian
	PaceStartBehind = 45, -- studs behind the start line
	PaceSpeedRatio = 0.93,
	PaceMaxGap = 90, -- studs: the Guardian catches up so the runner a third from the back of the pack is never further ahead than this -- pace speed = run speed * this (runners slowly pull ahead unless they stumble)
	PaceGrace = 3, -- seconds after GO before the pace line moves
	FallDepth = 36, -- below the floor = fell

	-- Juice
	JuiceMax = 100,
	JuiceStart = 100,
	JuiceDrainPerSecond = 5.5,
	BottleJuice = 12,
	GemPickup = 1, -- gems per diamond on the path
	BottlePickupRadius = 6,
	EmptyStumbleEvery = 2.5,

	-- Darts
	DartCooldown = 3.5,
	DartRange = 90,
	DartJuiceDrain = 18,
	DartSlowSeconds = 1.2,
	DartSlowMul = 0.7,

	-- Round
	IntermissionSeconds = 25, -- a run starts every 25 s
	CountdownSeconds = 3,
	GoalRevealSeconds = 3.2, -- the "SURVIVE x m" card, before the countdown
	MinPlayers = 1,
	-- Goal race: each run rolls a goal distance (metres, rounded to 50). A run with any player
	-- on fewer than GoalNewRuns runs uses the shorter New range. Everyone who reaches it wins
	-- and celebrates for CelebrateSeconds.
	-- { chance, low, high }: most runs are short (1,000-1,300 m), some mid, a long one now and then
	GoalBuckets = { { 0.55, 1000, 1300 }, { 0.33, 1300, 1700 }, { 0.12, 1700, 2200 } },
	GoalNewShift = 150, -- newer players' goals are this much shorter
	GoalNewRuns = 30,
	CelebrateSeconds = 5,
	FieldSize = 12, -- bots top every run up to this many runners, wearing the game owner's avatar

	-- Rewards
	GemsPerMetre = 1 / 250,
	LastStandingGems = 3,
	FinishGems = 5, -- everyone who reaches the goal
	CampEveryMetres = 500,
	CampGems = 2,
	WeeklyGems = 15, -- every 7th lifetime check-in
	ClassTokenEvery = 14, -- every 14th lifetime check-in grants one class of your choice
})
