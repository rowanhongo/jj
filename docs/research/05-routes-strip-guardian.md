# Routes, race strip, route map, Guardian ambush: design

Written before the build. Each choice says what it borrows, from where, and the check it passed:
does it make sense, has a shipped game done it, does it fit this game's thinking (simple core,
real skill, a readable race).

## 1. Race strip

The portrait row (client/Portraits, data workspace.RunField) becomes a track: a bar across the
top, each runner's face placed by distance between the back and the front of the field, your face
ringed in gold and drawn on top. Runners within 20 m of you get their name.

- Seen in: the position tower / progress bar of racing games (Mario Kart's position list,
  F1 timing towers, Fall Guys' qualification count). Ours shows distance, not just order, so
  "I'm 6 m behind Mia" is visible.
- Why: relatedness and competence need a visible other to measure against (Przybylski, Rigby &
  Ryan 2010). Order alone hides how close the fight is.
- Data: each RunField entry gets attribute `M` (metres) every 0.1 s from the existing live-place
  loop (no new network message).

## 2. Branching routes

A **crossroads** (a T plus straight: open left, right and ahead) splits the course into three
routes that run side by side and rejoin at a **merge**. You choose at the crossroads with the
same flick you already use for corners: flick left, flick right, or do nothing and carry on
straight. This is Temple Run 2's T-junction control, which our corners already copy.

    left route            centre route           right route
    (corner, auto)  <-- [crossroads] -->  (corner, auto)
         |                   |                   |
       stairs up        hard obstacles       stairs down
       GEM line          (shortest)          JUICE line
       stairs down                           stairs up
         |                   |                   |
    (corner, auto)  --> [  merge  ] <--  (corner, auto)

- **Every route has a visible price and a visible prize** (Mario Kart's shortcuts are risky and
  short; routes that only differ in scenery feel like no choice, see report 01/the "illusion of
  choice" sources):
  - centre FAST: shortest, two or three hard obstacles, ordinary pickups.
  - high GEM route: climbs onto a ridge, a line of gems, one medium obstacle, about 2.5 s longer.
  - low JUICE route: drops into a gully, a line of juice, one easy obstacle, about 2.5 s longer.
  Which side is high/low is random per crossroads, so you read it rather than memorise it.
- **Routes rejoin** (divergence for agency, reconvergence for cost and for keeping the pack in
  sight). They are separated by height (high +16, low -8) and a gap, so each feels like its own
  path (the Cyberpunk 2077 "perception of exclusivity" note).
- **Distance stays honest.** Race distance is progress toward the finish. On a side route each
  stud you run counts for (centre span / side length), so a longer route really is slower in
  the standings and the Guardian line; the strip and places stay true.
- **Only the crossroads asks a question.** The corners inside a side route and the merge turn
  you automatically (no stumble), because they have only one way to go.
- **Loop or not:** no laps. The course is generated, so a longer goal is more course, and every
  crossroads is new and must be read, not memorised.
- **Where:** only when the run is heading straight, at least two pieces after a turn, at least
  four pieces after the last merge, and never across the finish. About one crossroads every
  250-300 m, so 3-6 per run.

## 3. Route map

A heading-up map on the right side, drawn from the real built floors (the client has the whole
built course; streaming is off): about 130 m ahead and 15 m behind. Floors are tinted by height
(higher lighter, lower darker), juice and gems are dots, obstacles are red marks, other runners
are small dots, you are a gold arrow, the Guardian is a red marker. At a crossroads you see the
three routes and what lies on each before you choose.

- Seen in: racing-game minimaps; Temple Run has none, which is why its forks are coin flips.
- Why: a choice is only agency when the consequences are visible before you commit.

### Built (2026-11-16) and what testing changed

- Routes are 20 studs apart (12 read as one wide road from above).
- Bot data showed side-route runners being caught near the merge: a longer route counts for less
  race distance per second, and the Guardian paces on race distance. Fix: on a side route you
  run faster (PathService.speedMul), so it costs about 5% of the centre's pace instead of ~20%.
  The centre is still the quickest way; a side route no longer gets you caught for taking it.
- Studio test switch: workspace attribute `DevEarlyCross` puts a crossroads right after the start.
- Verified in play: the race strip, the map, the block geometry (side routes meet both squares
  exactly), bots choosing all three routes, a human flick taking the left route and its corner
  turning you on its own. Not yet seen with a human: the merge turning you back onto the course.

## 4. Guardian ambush (designed here, built after the routes are confirmed in play)

The question to answer first: if the Guardian is behind you, why would it be in front?

- **Fiction:** the Guardian is the temple's stone keeper. Carved **guardian shrines** stand at the
  start of routes after a crossroads. It can sink into the stone behind you and rise from a
  shrine ahead. Players see it sink (the back of the pack gets a breather) and see the shrine wake.
- **Seen in:** Alien: Isolation's alien leaves into the vents and drops out of a vent ahead of
  you, with vent noise as the warning; Resident Evil 3's Nemesis shows up at set places. Our
  version uses fixed, visible doors (shrines), so it is learnable, not random.
- **What it does to the race:** it wakes on the route the most front runners are heading down
  (decided when the first runner passes the crossroads). That turns every crossroads into a
  read: follow the crowd (safe in numbers? no: the crowd draws it) or split off. This is a
  minority game: the best choice depends on what others do, so it never solves itself.
- **Fairness:** 2 s of warning (shrine eyes glow, rumble, map marker). It charges back down
  that route like the tiger: change lane or jump to dodge. Getting hit costs a heavy stumble,
  not elimination; elimination stays "it caught you from behind".
- **Pacing:** while it is ahead, nobody behind can be caught (the valley for the back, the peak
  for the front, as Left 4 Dead's Director alternates them). It then sinks again and rises
  behind the pack at the pace line.
- **Not yet decided:** how often (every crossroads, or every other), and whether it can wake
  on a route nobody chose. Both need play-testing once routes exist.
