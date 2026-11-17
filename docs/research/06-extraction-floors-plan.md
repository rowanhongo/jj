# Jungle Juice: extraction floors, the agreed plan (2026-11-17)

Supersedes the timed-race direction. The running core (lanes, jumps, turns, crossroads routes,
juice, Guardian) stays. Everything below is agreed with the user unless marked OPEN.

## The game in one line
Up to 12 runners (solo or teams of up to 4) run a temple floor, fill a physical bag with relics,
and choose when to extract. Find the floor's 3 keys to open the next floor.

## Floors (outer progression)
- Fixed, hand-set layout per floor (built once from a fixed seed with the existing generator).
  Same every run, so it can be learned; the map lets players plan routes.
- About 5 minutes from start to the final gate.
- Launch with 10-12 floors (jungle, flooded, lava, ...). New floor = content update.
- No paying to unlock floors.
- No night/variant modes (cut: confusing).
- Head of floor: best extraction on that floor, name in the floor's start area.

## Keys
- 3 keys per floor, each at a FIXED spot (e.g. key 1 down the left branch at the second turn).
- A key counts once you extract with it, and stays yours. Collect them across as many runs as needed.
- All 3 extracted = next floor opens. After that the floor is replayed for relics.

## Run bag and relics (in-run progression)
- Loot goes into a physical bag on your back that grows as it fills. Bag value floats over your head.
- Chests sit at fixed spots on the fixed layout; contents are random (Tarkov/Arc Raiders model).
  Risky places (crossroads side routes, just before later gates) hold better chests.
- Relics: Common to Mythic. Sold for coins.
- Multiplier rises the longer you stay in the run.
- Juice stays on the course as now.

## Extraction gates
- Glowing gates beside the track at fixed spots (about every 45 s), plus the final gate (big bonus).
- Steer in: short animation, back to the lobby, bag banked.
- Die before extracting: lose the bag (and unextracted keys).

## Death and revive
- Revive keeps the bag and continues the run. First is cheap, each next doubles (this run only).
  Paid with earnable currency or Robux. No straight "pay to keep loot" button.

## Other runners
- Cannot hit or affect you. Competition = visible bag values, race strip, Head of floor.
- Attack modes may come later as a separate mode.

## What coins buy / the flex (OPEN: confirm list)
- Bag upgrades (capacity) and bag skins (the bag is the main visible flex).
- Runner outfits and trails.
- Revive currency.
- Later: boosts (2x coins, luck), battle pass.

## Cut / later
Cards, enemies, gear, stat points, trading, albums, modes, Guardian ambush, passive income.
Abilities: spin system to be revisited (likely removed in favour of the above).

## UI rework
- Route map: top-down RENDERED picture of the floor (bake each fixed floor like Anime Nexus's
  minimap: tools/roblox/minimap_bake.luau -> ReplicatedStorage data -> EditableImage, see
  Anime-Nexus-Online src/client/hud/minimapImage.luau + minimap.luau). Small, clean player icons.
  Square, top right on PC and phone, size scales for tablets (like Anime Nexus HudLayout.minimapSize).
  Shows keys/chests/gates once discovered (OPEN: always visible or discovered only?).
- Race strip (top): redesign, current one is ugly. Show runner + bag value.

## Tracking (AnalyticsService)
Runs, extractions, which gate, bag value, deaths, revives, session length, invites sent,
joins via invite. Ease difficulty slightly after 2 losses in a row (never alters paid items).
Not doing: gyroscope/accelerometer profiling of players (minors), battery, outside-app data.

## Build order
0. Route fixes (T-junction, no forced turns, smooth bends, bigger elevation, clean routes).
1. Bag + chests + extraction gates + multiplier on the current course (feel test).
2. Keys + fixed floors + floor unlock.
3. Baked top-down map (top right) + race strip redesign.
4. Revive, coins shop, Head of floor, analytics.
5. Floors 1-12 content.

## Lobby between raids (agreed)
- The lobby is where you are between raids. Step on a pad -> pick the floor you are headed to
  (like picking a chapter). Each floor shows your keys (e.g. 2/3) and whether it is locked.
- The pad drops the group into that floor. No timed rounds, no last-standing.

## Route fixes (agreed, from play-testing 2026-11-17)
- Bug: the crossroads turned the player onto routes they did not choose. Cause: a lane-change
  swipe held near the fork counts as a turn flick (Runner.luau treats a steer within 0.35 s as a
  flick). Must only take a deliberate turn.
- Replace the 3-way crossroads with a T-junction: left or right, no straight. Your swipe always
  means a route. A 3-way stays possible but very rare.
- No snapped auto-turns inside routes: corners inside a route become smooth bends you run round,
  and the routes rejoin with a smooth curve, so nothing yanks the camera.
- Elevation much bigger: one side climbs high above the main course, the other drops far below.
- Bug: side routes sometimes glitchy and with rocks/boulders blocking them; audit route content.

## Decisions 2026-11-17 (round 2)
- Currency: gems only. Relics sell for gems. Gems pay revives, equipment and skins. No new currency.
- The flex is the equipment (as Fisch's flex is the rod). Equipment = the bag (capacity, chest
  luck) and later more runner kit; tiers, skins, mutations. Exact list OPEN.
- T-junction with no swipe: stumble, then a random 50/50 side.
- Juice: KEPT (Claude's decision). It is the run's clock without a timer: it drains, pickups on the
  course refill it, running dry slows you and the Guardian catches you. With a full bag and low
  juice you extract; with juice to spare you push on. It keeps lane-weaving for pickups meaningful.
  Juice does not go in the bag and is not banked.

## Quality bar (the user's complaints about the last build, must not repeat)
- Map: was bad. Must be a baked top-down picture, small clean icons, verified on PC and phone.
- Race strip: was ugly and inaccurate (positions did not match the race). Must be correct
  to the metre and verified against the server's numbers.
- Dying: the strip/map did not handle runners who died. Every UI must define and test what it
  shows for: a runner who died, revived, extracted, or left the server.
- Every feature: list its states and edge cases BEFORE coding, test each in Play, report what was
  not tested.

## OPEN questions
- Name for the runners (not "Templars"): Relic Runners / Wardbreakers / Jungle Raiders / other.
- Map: keys/chests always shown, or only after you've found them once?
