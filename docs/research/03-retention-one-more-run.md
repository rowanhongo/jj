# 03: Retention and the "one more run" compulsion

Scope: why losing a round of Jungle Juice produces no "spin up again" urge, and what to change. This is based on the code as of 2026-11-16 (`src/shared/Config.luau`, `src/server/RoundService.luau`, `src/client/DeathScreen.luau`, `src/server/DataService.luau`, `src/shared/Items.luau`). Evidence strength: **[A]** peer-reviewed or replicated, **[B]** a single study, official platform docs or practitioner data, **[C]** practitioner opinion or my own inference.

## 0. The diagnosis in one line

A loss should make a player want to go again straight away. Rivals offers an immediate rematch vote (see section 6). Tower of Hell sends you back to the bottom of the tower at once while its round timer keeps running. In Jungle Juice, a player caught in a round with other humans **waits until every human is out or finished, then 5 s of results, then the full 25 s intermission, then the 3.2 s goal reveal and the 3 s countdown**. The death card also never says how close they came. The urge to replay has nothing to feed on and nowhere to go.

### Verified wait from death to the next GO (read from `src/server/RoundService.luau`)
| Step | Wait | Where |
|---|---|---|
| The round keeps running while any *human* is still running (`runners()` counts players only, never bots) | 0 s if you were the last human; otherwise until the other humans are out, finish, or one is last standing | `runners()` L251-258; `if #runners() == 0 then break` L1280-1281; last-standing break L1288-1292 |
| Winners celebrate (only if someone finished) | 5 s (`CelebrateSeconds`) | L1305 |
| Results on screen | 5 s | `task.wait(5)` L1447 |
| Intermission, counted from the end of the round | 25 s (`IntermissionSeconds`) | L1516-1520 |
| Goal reveal | 3.2 s | L1071 |
| Countdown | 3 s | L1072 |

- **Solo player (rest of the field is bots):** about **36 s** from death to GO (5 + 25 + 3.2 + 3), or 41 s if a bot finished. The round ends the moment the only human is caught.
- **Several humans:** add the time the other humans keep running. The speed curve (`RunSpeedStart` 35 studs/s, x1.1 at 30 s, x1.2 at 75 s, `speedMul` L262) puts a 1,150 m goal (4,025 studs) at about **100 s** of running. So someone caught at 30 s while a friend reaches the goal waits about **70 + 5 + 5 + 25 + 6.2 ≈ 110 s**. That is under 2 minutes, not the 3.5 minutes in my first draft, which wrongly assumed bots keep the round alive.
- **"Play again" adds nothing on top:** `againB` leaves and re-queues (DeathScreen L337-346), but the next run still waits for the intermission loop.

Even the best case, 36 s, is far longer than a Tower of Hell respawn. Bad cases come close to 2 minutes.

## 1. Round audit, moment by moment (as built)

| # | Moment | What the code does | Emotion now | What it should be |
|---|---|---|---|---|
| 1 | Lobby wait | A fixed loop: `IntermissionSeconds = 25` starts **after** the previous round ends (`RoundService.init`). Nobody can join a round that is already running. | Dead air for anyone just back from a run. | Anticipation that is short, with something to look at (quest preview, a best to beat). |
| 2 | Goal reveal | `GoalRevealSeconds = 3.2`, "SURVIVE x m", taken from `GoalBuckets` (55% of goals are 1,000-1,300 m). | Mild curiosity. The number means nothing personal. | "SURVIVE 1,150 m. Your best: 980 m" turns it into a personal challenge (goal-gradient: Hull 1932; Kivetz et al. 2006). |
| 3 | Countdown | 3 s drum. | Fine. | No change. |
| 4 | Early run (0-30 s) | Speed x1.0, `PaceGrace = 3`. | Low stakes. | No change (a gentle start helps flow). |
| 5 | Mid run | Juice drains at 5.5/s, bottles give +12, darts, Guardian. `CampEveryMetres = 500` gives +2 gems. | Moderate. The only progress shown is a number. | A progress bar to the goal that gets more vivid near the end. |
| 6 | Last 20% | Nothing changes as the goal gets close. | **The biggest missed peak.** Goal-gradient says effort and arousal should spike here. | Music change, "200 m TO GO", a faster Guardian, a camera FOV kick. |
| 7 | Death | `catch()` sends stats with a reason ("Caught by the Guardian" / "Fell" / "Lost"). A top-3 player sees their placement instead of the cause. The distance short of the goal is never shown. | A flat "YOU DIED". | The cause plus **"137 m short of 1,150 m"**. A true near miss raises the wish to replay (Clark et al. 2009). |
| 8 | Death card | Rows: metres, place, bonus, gems, cans, time. Buttons: Spectate, Lobby, Play again. | Reads like an accounting screen. No best, no goal distance, no progress toward anything. | One headline number (how close you came, or a new best), one progress bar (quest or level), one big button. |
| 9 | "Play again" | `againB` leaves, waits for the Lobby state, then sends `Queue`. **The player still waits for the current round to end and for the intermission**: 36 s solo, about 110 s with other humans. | **The urge dies here.** Clicking produces nothing right away. | The next action under 10 s away. |
| 10 | Results | `task.wait(5)`, then reset. Status line: "N made it to x m!". | Brief. | Fine, but add a podium moment for winners (peak-end rule, Kahneman et al. 1993). |
| 11 | Back to lobby | Another 25 s. | Where players drop off. | (Fixed by item 1.) |

**Downtime** (worked out in section 0): from death to the next GO takes 36 s solo and about 110 s in a typical multi-human round. The players who die first are the ones a near miss would push hardest to try again, and they get the longest wait. The timings come from the code; the run lengths come from the speed curve, so confirm both with `Funnel` (section 5).

## 2. Changes for this game, ranked by impact for the cost

### R1. Cut the downtime with a quick re-run (highest priority)
- **What:** On death, a big primary "RUN AGAIN" button (also gamepad A and Enter) starts a **practice heat** within **5 s or less**. A heat is a separate path (`PathService` can already build paths) with bots filling the field to 12 (`FieldSize`; `BotService` exists). A simpler option is two staggered round loops, with a new heat every 60-90 s and `IntermissionSeconds` cut from 25 to **10**. Then the longest wait after a death is about one heat.
- **Why:** A delayed reward is worth less to people than the same reward now, and children discount delay the most, then young adults, then older adults (Green, Fry & Myerson 1994, *Psychological Science* 5:33; [APS abstract](https://www.psychologicalscience.org/journals/psychological-science/j.1467-9280.1994.tb00610.x/)) **[A for the age pattern, which later work replicated; I only read the abstract-level summary, and the study used hypothetical money, not games]**. The motivation a near miss creates (Clark et al. 2009) is a short-lived state **[B]**.
- **Cheapest first step (one line each, no new systems):** cut `IntermissionSeconds` from 25 to 10 and the results wait at L1447 from 5 s to 3 s. Solo death to GO drops from 36 s to about 19 s.
- **Numbers:** aim for 15 s or less from death to the next GO (5 s card + 3.2 s reveal + 3 s countdown + load). Cut the main loop's intermission from 25 s to 10 s.
- **Cost:** medium to high (two paths at once, server load with 2×12 runners; bots are cheap). **Risk:** splitting players across heats. Keep a single heat when 6 or more humans are online.

### R2. Show the near miss on the death card
- **What:** The headline reads `"137 m SHORT"`, over a bar from 0 to the goal that marks you, the furthest runner and your personal best. If you beat your best, it reads `"NEW BEST: 1,013 m"` in gold. The second line gives the cause: "Caught by the Guardian", "Fell", "Out of juice" or "Hit by <name>'s dart". Store `bestM` per player in DataService (one field).
- **Why:** Clark et al. 2009 (*Neuron* 61:481; [PMC2658737](https://pmc.ncbi.nlm.nih.gov/articles/PMC2658737), full text read) ran a behavioural experiment (n = 40) and an fMRI experiment (n = 15). Near misses were rated *less* pleasant than full misses (t39 = −2.75, p = .009). Yet when the player had chosen the gamble, near misses *raised* "continue to play" ratings compared with full misses (t39 = 2.66, p = .011). When the computer chose, near misses **lowered** the desire to play. In the brain, near misses activated the ventral striatum and anterior insula, which also respond to wins **[B: one lab study, small samples]**. So the effect depends on the player feeling in control. Running is fully skill-controlled, so this is the honest use of the effect: a real near miss, not a rigged one. Reid (1986, *J. Gambling Behavior* 2:32) describes near misses as reinforcement **[B]**. Personal bests use the goal-gradient effect: effort speeds up as a goal gets closer (Kivetz, Urminsky & Zheng 2006, *J. Marketing Research* 43:39) **[A]**.
- **Ethics:** never fake a near miss (for example, by moving the goal so you "almost" made it). Show true numbers only.
- **Cost:** low (stats are already sent; add `goal`, `best` and `cause`). **Risk:** none.

### R3. Make the last 20% of a run the peak
- **What:** At 80% of the goal: a "200 m TO GO" banner, an added music layer or faster tempo, FOV +6°, a Guardian roar. At 95%: a finish arch comes into view on the path, plus a crowd cheer. Show a goal progress bar on the HUD from GO onward.
- **Why:** Goal-gradient effect (Hull 1934). Kivetz, Urminsky & Zheng 2006 found that café reward-card holders bought coffee more often the closer they got to the free one, and song raters rated more as they neared their reward. A 12-stamp card with 2 bonus stamps was finished faster than a plain 10-stamp card: median 10 vs 15 days ([Columbia summary](https://business.columbia.edu/insights/chazen-global-insights/goal-gradient-hypothesis-resurrected-purchase-acceleration); [paper PDF](https://business.columbia.edu/sites/default/files-efs/pubfiles/1200/goalgradient.pdf)) **[A]**. Peak-end rule: people remember an experience mostly by its peak and its end (Kahneman, Fredrickson, Schreiber & Redelmeier 1993, *Psychological Science* 4:401) **[A]**. Right now the end of a run has no designed peak.
- **Cost:** low to medium (Hud, Sfx, client camera). **Risk:** mobile performance. Keep the effects light on the Low setting.

### R4. Make the win land
- **What:** On finishing: 0.5 s of slow motion, confetti, and a **podium** where the top 3 avatars play their emotes during the 5 s `CelebrateSeconds`, while everyone else spectates. The winner's trail glows for the next round, so others can see who won.
- **Why:** Peak-end rule **[A]**. Self-determination theory: games that meet players' needs for competence and relatedness are enjoyed more and played longer (Ryan, Rigby & Przybylski 2006, *Motivation and Emotion* 30:347) **[A]**.
- **Cost:** medium. **Risk:** low.

### R5. Turn check-ins into a visible streak that pauses instead of resetting
- **Now:** `checkIn` counts **lifetime** check-ins and pays on every 7th (15 gems) and every 14th (a class token). There is no streak, so missing a day costs nothing and there is no reason to come back *tomorrow* in particular.
- **What:** A 7-day calendar. Day 1 = 10 gems, day 2 = 15, day 3 = a mystery box, day 4 = 20, day 5 = 25, day 6 = a trail shard, **day 7 = 60 gems and a rare cosmetic roll**. On first join, day 1 is shown **already ticked** (endowed progress). A missed day **pauses** the streak instead of resetting it, or the player gets one free "streak freeze" a week. Keep the class token every 14 lifetime check-ins as the long-term reward.
- **Why:**
  - **Endowed progress.** Nunes & Drèze 2006 (*J. Consumer Research* 32:504) gave car-wash customers either an 8-stamp card or a 10-stamp card with 2 stamps pre-filled; both needed 8 more washes. Completion was reported as 34% vs 19%. I could only confirm those figures in a secondary source, not the paper **[A for the effect; the exact numbers are B]**. Kivetz et al.'s 10 vs 15 days result above independently replicates the effect.
  - **Loss aversion** makes a streak feel like something you already own (Kahneman & Tversky 1979) **[A]**.
  - **Duolingo:** its own blog says streak freezes keep learners going when they skip a day, but publishes **no figure** ([Duolingo blog](https://blog.duolingo.com/how-duolingo-streak-builds-habit)). The "−21% churn" figure that circulates comes from an unsourced case study, so I dropped it **[C]**.
  - **Roblox's own package:** the [Engagement Rewards feature package](https://create.roblox.com/docs/resources/feature-packages/engagement-rewards) (page read) has Daily rewards keyed to `requiredDaysVisitedStreak`. Its example progression is small early rewards, then bigger consumables, then a lasting item after 7 straight days, which matches the calendar above. The page **doesn't say what happens to a streak on a missed day**, so the pause-not-reset rule is our own design choice **[B]**.
- **Ethics:** a hard reset that punishes a child for missing one day is the stressful part. Pausing keeps the habit without the punishment.
- **Cost:** low (DataService plus one Lobby panel). **Risk:** gem inflation. A 1,200 m finish pays about 14 gems (4.8 from distance + 5 for finishing + 4 from two camps), so a week of streak rewards is worth about 10 runs. That seems reasonable.

### R6. Quests that end on a cliffhanger (Zeigarnik effect)
- **Now:** Quick quests reset every **600 s** (`period = 600`) and daily quests every 86,400 s (the UTC day boundary). They only appear on the lobby boards.
- **What:**
  - (a) On the death card, show the quest closest to done: "Top 3 finishes: 2/3. One more!"
  - (b) Lengthen the Quick quest period from 10 to 15 min, so one more run usually completes it.
  - (c) Finishing all three daily quests unlocks a fourth bonus quest, so a new open goal appears just when the player would stop.
  - (d) On leaving, preview tomorrow's first quest.
- **Why:** Unfinished tasks stay on the mind and pull at attention (Zeigarnik 1927) **[B: replications are mixed; the Ovsiankina resumption effect, the urge to go back and finish an interrupted task, is stronger]**. Goal-gradient effect near completion **[A]**.
- **Cost:** low. **Risk:** a quest grind for children. Cap the gems daily quests can pay.

### R7. Surprise rewards inside runs, never paid
- **What:** Mystery boxes on the path already give abilities. Add a rare "golden bottle" (about 1 run in 20) worth +50 gems, announced to the whole server. Keep these **free and earned**. Anything bought with Robux, or with gems that can be bought with Robux, must show its odds (Roblox's [Paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items)) and be gated by `PolicyService.ArePaidRandomItemsRestricted`.
- **Why:** Rewards on a variable-ratio schedule (unpredictable, after a varying number of tries) produce the most persistent behaviour (Ferster & Skinner 1957) **[A]**. Overusing this on children is the ethical risk, so limit it to free cosmetics and soft currency.
- **Cost:** low. **Risk:** a policy breach if it is ever tied to Robux. Don't tie it.

### R8. A personal rival: beat your friend
- **What:** A lobby panel and the reveal card show "Beat <friend>: 1,240 m" (friends via `Players:GetFriendsAsync`, best distance stored per player). The death card adds "You passed 3 runners this run".
- **Why:** Self-determination theory's needs for relatedness and competence **[A]**. Comparing yourself with others drives effort in games (Rigby & Ryan 2011, *Glued to Games*) **[B]**. `FriendBoost` already exists, so build on it.
- **Cost:** medium. **Risk:** privacy. Show friends' display names only.

## 3. Return structure: day 1, day 7, day 30

**Roblox's own guidance** ([Retention docs](https://create.roblox.com/docs/production/analytics/retention), page read) **[B]**:
- **D1:** make the core loop clear, rewarding and balanced, and get new players to the fun "in 5 minutes or less".
- **D7:** a progression with short-term and long-term goals.
- **D30:** small updates every 2-4 weeks, bigger features every 2-3 months, and social features (leaderboards, tournaments).

The page gives **no benchmark numbers**. Roblox's similar-experience scorecards appear in your own dashboard once the game has 100+ daily active users ([DevForum](https://devforum.roblox.com/t/analytics-similar-experience-benchmarks-broader-access/2210285)).

**Outside reference only, not Roblox:** GameAnalytics' Q1 2024 mobile medians were D1 22.9%, D7 4.2% and D28 0.85% ([summary](https://gamedevreports.substack.com/p/gameanalytics-benchmarks-in-mobile)). Summaries of its 2025 report put the top quartile's D1 at roughly 26-30% **[B]**.

I found no Roblox-staff RDC talk with retention numbers. One third-party site claims a D1 of 45-60% for top-100 Roblox games, but cites no sources, so I left it out **[C]**.

| When | Hook | Mechanism |
|---|---|---|
| **First session / D1** | Shorter goals for new players already exist (`GoalNewShift` 150; the first run is at night). Make the **first run winnable** for about 70% of new players, award a "first finish" badge, show streak day 1 already ticked, and end the session with "Tomorrow: day 2 reward + mystery box". | Competence (self-determination theory), endowed progress, a reason to come back at a set time |
| **D2-D7** | The 7-day streak calendar (R5), daily quests (R6), and your best and your friend's best on the reveal card (R2, R8). | Loss aversion (with pause, not reset), goal-gradient |
| **D7** | A rare cosmetic roll on day 7, with the first class token (day 14) now in sight. | Endowed progress toward the class token |
| **D8-D30** | A weekly **season ladder**: 30 free tiers earned with XP (levels already exist), with a trail at tiers 10, 20 and 30. Plus a weekly "featured run" leaderboard on a fixed path that is the same for everyone that week, so players can master it. Mastery feeds flow (Csikszentmihalyi 1990) **[A]**. | Competence, mastery, a weekly reset to return for |
| **D30** | Lifetime check-in 28 brings the second class token. A season-end trail that can't be earned later (cosmetic only). | Completing a collection |

## 4. Ethics and Roblox policy for under-13s
- **Paid random items:** any box or roll bought with Robux, or with gems that Robux can buy (`Items.GemPacks` exists), must list all outcomes and their odds before purchase and be gated by `PolicyService` ([policy](https://create.roblox.com/docs/production/monetization/paid-random-items)). The Item Rolls tab in `Lobby.luau` falls under this. The free mystery boxes on the path do not.
- **Near misses:** real ones only. Faking them is the slot-machine technique Clark and Reid describe, and the kind of design that draws gambling scrutiny.
- **Streaks:** pause them, don't punish. No pressure messages such as "your streak dies in 2 h!".
- **Experience Guidelines and content maturity:** keep the maturity questionnaire filled in so the game is not Unrated. Since the [December 2024 update](https://devforum.roblox.com/t/updating-experience-guideline-policies-to-keep-our-younger-users-safe/3249079), unrated experiences can't be played by under-13s.
- **Spending:** nothing that only Robux can buy should give a gameplay advantage. Spending goes on cosmetics, trails, emotes, and class tokens that can also be earned free (the 14-day check-in already does this).

## 5. How to measure it
Add three `Funnel` steps: `DeathCardShown`, `RunAgainClicked` and `NextRunStarted`, recording the seconds between them. Targets: **RunAgainClicked / DeathCardShown of 60% or more**, a median of 15 s or less from death to the next GO, and 50% more runs per session. Watch Roblox's D1 and D7 scorecards for 2 weeks before and 2 weeks after shipping R1 and R2.

## 6. How top Roblox round-based games handle the wait after death

Fandom wikis refused automated fetches (HTTP 402 and a bot wall), so the rows below come from secondary guides **[B/C]**. Check them in-game before relying on them.

| Game | After death or failure | Lesson for Jungle Juice |
|---|---|---|
| **Tower of Hell** | No checkpoints. A fall sends you back to the bottom at once and you keep climbing while the round timer (about 8 min; older versions used 6) runs. Each player who reaches the top doubles the timer's speed for everyone else ([obbywiki](https://obbywiki.com/wiki/Tower_of_Hell); [bloxodes guide](https://bloxodes.com/articles/tower-of-hell-beginner-guide)). | Failing restarts the *attempt*, not the *session*. This is the closest model for R1's practice heats. A finisher speeding up the clock gives a mid-round spike. |
| **Rivals** | Duels are first to 5 round wins, so a single death is never the end. Update 6 added a rematch vote straight after a match, usable up to twice ([Sportskeeda patch notes](https://www.sportskeeda.com/roblox-news/rivals-update-6-patch-notes); [allthings.how](https://allthings.how/roblox-rivals-ranked-mode-and-ranks-explained/)). | Losses come in small pieces, and the next fight is one button away against the same opponent. This is the "spin up again" the owner describes. |
| **DOORS** | The death screen shows Guiding Light messages that name the entity that killed you and how to survive it next time. A Revive is offered on the same screen (once per run; sold at 120 Robux for 5, also free through codes) ([gameleap](https://www.gameleap.com/articles/roblox-doors-how-to-get-use-revives)). | Explain the cause and give a tip on the death card (R2). We should **not** copy paid revives: a Robux-bought second chance in a competitive race is pay-to-win. |
| **Flee the Facility** | Captured survivors are frozen in pods that teammates can free, so a "dead" player still has a stake in the round ([Sportskeeda](https://www.sportskeeda.com/esports/how-use-freeze-pod-roblox-flee-facility)). | An eliminated player should still have something to do: spectate *with a job*, e.g. pick a runner to back for a small gem bonus if they finish (free, no Robux). |
| **Murder Mystery 2** | I found no reliable source for its death and intermission flow. | — |

**Takeaway:** none of these games makes a beaten player sit idle through an intermission timer that only starts after the whole round ends. Each one either restarts the attempt at once (Tower of Hell), keeps the session going (Rivals' rounds and rematch vote), explains the death and offers a way back (DOORS), or keeps the eliminated player involved (Flee the Facility).

## Sources
- Clark, L. et al. (2009). Gambling near-misses enhance motivation to gamble and recruit win-related brain circuitry. *Neuron* 61(3):481-490. https://pmc.ncbi.nlm.nih.gov/articles/PMC2658737
- Reid, R. L. (1986). The psychology of the near miss. *Journal of Gambling Behavior* 2:32-39.
- Kivetz, R., Urminsky, O., Zheng, Y. (2006). The goal-gradient hypothesis resurrected. *J. Marketing Research* 43(1):39-58.
- Nunes, J. C., Drèze, X. (2006). The endowed progress effect. *J. Consumer Research* 32(4):504-512.
- Kahneman, D. et al. (1993). When more pain is preferred to less: adding a better end. *Psychological Science* 4(6):401-405.
- Ryan, R. M., Rigby, C. S., Przybylski, A. (2006). The motivational pull of video games: a self-determination theory approach. *Motivation and Emotion* 30:347-363.
- Green, L., Fry, A. F., Myerson, J. (1994). Discounting of delayed rewards: a life-span comparison. *Psychological Science* 5(1):33-36.
- Ferster, C. B., Skinner, B. F. (1957). *Schedules of Reinforcement*.
- Csikszentmihalyi, M. (1990). *Flow*.
- Roblox Creator Docs, Retention: https://create.roblox.com/docs/production/analytics/retention
- Roblox Creator Docs, Engagement rewards feature package: https://create.roblox.com/docs/resources/feature-packages/engagement-rewards
- Roblox Creator Docs, Paid random items policy: https://create.roblox.com/docs/production/monetization/paid-random-items
- Roblox DevForum, Updating experience guideline policies to keep younger users safe: https://devforum.roblox.com/t/updating-experience-guideline-policies-to-keep-our-younger-users-safe/3249079
- Roblox DevForum, Similar experience benchmarks: https://devforum.roblox.com/t/analytics-similar-experience-benchmarks-broader-access/2210285
