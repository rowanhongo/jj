--!strict
-- All tuning numbers in one place.

return table.freeze({
	-- Path
	PathWidth = 24, -- studs, floor width of a normal segment
	WallHeight = 5,
	GenerateAhead = 520, -- keep this many studs of path past the leader
	DeleteBehind = 160, -- delete segments this far behind the Guardian
	StudsPerMetre = 3.5, -- HUD distance = studs / this

	-- Running
	RunSpeedStart = 30,
	RunSpeedMax = 46,
	RunSpeedRampSeconds = 240, -- seconds to reach max speed
	SteerFactor = 0.75, -- sideways share of movement at full stick
	SlideSeconds = 0.8,
	StumbleSeconds = 0.75,
	StumbleSpeedMul = 0.35,
	WallBumpCooldown = 1.2,

	-- Pace line / Guardian
	PaceStartBehind = 70, -- studs behind the start line
	PaceSpeedRatio = 0.9, -- pace speed = run speed * this (runners slowly pull ahead unless they stumble)
	PaceGrace = 3, -- seconds after GO before the pace line moves
	FallDepth = 22, -- below the floor = fell

	-- Juice
	JuiceMax = 100,
	JuiceStart = 100,
	JuiceDrainPerSecond = 5.5,
	BottleJuice = 6,
	BottlePickupRadius = 6,
	EmptyStumbleEvery = 2.5,

	-- Darts
	DartCooldown = 3.5,
	DartRange = 90,
	DartJuiceDrain = 18,
	DartSlowSeconds = 1.2,
	DartSlowMul = 0.7,

	-- Round
	IntermissionSeconds = 12,
	CountdownSeconds = 3,
	MinPlayers = 1,

	-- Rewards
	GemsPerMetre = 1 / 25,
	LastStandingGems = 25,
	CampEveryMetres = 500,
	CampGems = 10,
	WeeklyGems = 150, -- every 7th lifetime check-in
	ClassTokenEvery = 14, -- every 14th lifetime check-in grants one class of your choice
})
