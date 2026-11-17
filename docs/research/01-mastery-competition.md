# 01 — Mastery, skill expression and competition (revision 2)

Angle: the "I'm better than them, run it back" feeling. This is revision 2 (2026-11-16). Where a source is marked *read*, I fetched and read the primary text, and the quotes and numbers come from it. Sources marked *snippet* were found but not read in full.

Evidence labels:
- **[strong]**: replicated, meta-analytic, or an established method.
- **[moderate]**: a single peer-reviewed study, or an official first-party statement.
- **[anecdotal]**: a developer interview, press coverage, a fan guide or an opinion.

---

## 1. What the code shows (why there is "no space to get better")

| Finding | Code | Consequence |
|---|---|---|
| Most goals are short and everyone who reaches one wins | `Config.GoalBuckets`: 55% of goals are 1,000–1,300 m. `FinishGems = 5` goes to every finisher. | A competent player wins nearly every run the same way, so a win tells them nothing about how well they played. |
| Score ≈ distance + placement | `RoundService.scoreMetres` = metres + `run.bonus`. `bonusPlaces` pays the top 1–3. | The goal caps distance, so scores bunch together at the top. |
| Saved stats don't measure skill | `DataService.Profile`: `best`, `records`, `xp`, `level` | Level measures time played. `best` mostly reflects which goal the run rolled. |
| Every error costs the same | `StumbleSeconds 0.75` at `StumbleSpeedMul 0.35` | A comfortable clear and a clear by a hair look identical. Nothing grades how well you did. |
| Bots roll dice instead of reacting | `BotService.fails()`: `rng:NextNumber() > b.skill * extra`, decided once per obstacle | Bots miss easy and hard obstacles at the same rate, so beating them proves nothing. They also wear the owner's avatar (`FieldSize = 12`). |
| Abilities have no counterplay | `landHit` / `throwAt` / `dropTrap` target `targetAhead` | The 2 s Wild Hex can't be answered. |
| Speed ramp is flat | `RunSpeedSteps` tops out at x1.3 at 130 s | The challenge stops rising just when experts reach flow. |
| **The course is already seeded** | `RoundService.prebuild()` → `PathService.reset(seed)` with `seed = math.random(1, 2^30)`. Every piece and pickup draws from that one `Random` (`ctx.rng`). | Ghosts and a daily course are cheap to build (section 4.4). |
| The client owns movement | RoundService header: "The client owns its own movement (steering, jumping, sliding, turning, stumbling)." | Timing finer than about 100 ms has to be measured on the client. The server can only sanity-check it. |

---

## 2. Research findings (primary sources read)

### 2.1 Competence feedback (Self-Determination Theory) **[strong]**
- **Source:** Przybylski, Rigby & Ryan (2010), *A Motivational Model of Video Game Engagement*, Rev. Gen. Psych. 14(2):154–166 ([doi:10.1037/a0019440](https://doi.org/10.1037/a0019440)). *Abstract and secondary reviews read.*
- **Empirical base:** Ryan, Rigby & Przybylski (2006), *Motivation and Emotion* ([PDF](https://www.rochester.edu/warner/lida/wp-content/uploads/2022/11/02bfe513dd59366750000000.pdf)).
- **Finding:** satisfying competence, autonomy and relatedness predicts enjoyment, preference and short-term well-being, across multiple studies.
- **Mechanism:** competence comes from informational feedback, meaning knowing *how well* you did, not just the outcome.

### 2.2 Near-misses work only under personal control **[moderate]** *(read: full text)*
- **Source:** Clark, Lawrence, Astley-Jones & Gray (2009), *Neuron* 61:481–490 ([PMC2658737](https://pmc.ncbi.nlm.nih.gov/articles/PMC2658737)).
- **Design:**
  - Experiment I: n = 40, a two-reel slot task with wins on 1/6 of trials and near-misses on 2/6.
  - Experiment II: n = 15, fMRI.
- **Results:**
  - Near-misses the participant had arranged felt less pleasant than full misses (t39 = −2.75, p = .009) but raised the desire to play (t39 = 2.66, p = .011).
  - Near-misses arranged by the computer reduced the desire to play.
  - Chosen versus computer-chosen near-misses differed in motivation at t39 = 4.69, p < .001.
- **The often-quoted 30%:** the paper cites Kassinove & Schare (2001), who tested near-miss frequencies of 15%, 30% and 45%. Persistence followed an inverted U that peaked around 30%.
- **For this game:** a close call has to come from a margin the player earned, never from the game staging one. A rough frequency target for close calls is on the order of 1 in 4. That figure is gambling-derived, so tune it in play tests rather than adopting it.

### 2.3 Racing your own ghosts raises motivation and flow **[moderate]** *(read: publisher abstract page)*
- **Source:** Michael & Lutteroth (2020), *Race Yourselves: A Longitudinal Exploration of Self-Competition Between Past, Present, and Future Performances in a VR Exergame*, CHI '20 ([doi:10.1145/3313831.3376256](https://doi.org/10.1145/3313831.3376256)).
- **Design:** all of a player's past sessions are replayed as ghosts, plus a projected "future" ghost. There was a 4-week longitudinal study and a cross-sectional study.
- **Result:** compared with a non-competitive version, ghosts improved performance, intrinsic motivation and flow.
- **Caveat:** the abstract page gives no sample sizes.

### 2.4 Losing streaks drive churn, and so does pure winning **[moderate]** *(read: full PDF text)*
**Source:** Chen, Xue, Kolen, Aghdaie, Zaman, Sun & Seif El-Nasr (2017), *EOMM: An Engagement Optimized Matchmaking Framework*, WWW 2017 ([arXiv:1702.06820](https://arxiv.org/abs/1702.06820)). The data comes from an EA PvP game.

**Table 1 — 7-day churn by last three outcomes:**

| Last 3 outcomes | 7-day churn |
|---|---|
| DLW / LLW / LDW / DDD | 2.6–2.7% |
| WWW | 3.7% |
| DLL / LWL / LDL | 4.6–4.7% |
| WWL | 4.9% |
| **LLL** | **5.1%** |

- **Claimed gain:** 0.3–5.5% engagement over Elo- and TrueSkill-based matchmaking, via the [Emergent Mind summary](https://www.emergentmind.com/papers/1702.06820).
- **For this game:** steer *unrated* bot difficulty toward mixed outcomes. Never adjust ratings.

### 2.5 Glicko-2 **[strong as a method]** *(read: full PDF text)*
- **Source:** Glickman, *Example of the Glicko-2 system* ([PDF](http://www.glicko.net/glicko/glicko2.pdf)).
- **Starting values:** an unrated player starts at 1500, RD 350, volatility 0.06.
- **τ:** "between 0.3 and 1.2".
- **Rating periods:** the system "works best when … an average of at least 10–15 games per player in a rating period."
- **Confidence:** the 95% interval is rating ± 2·RD.

### 2.6 Valorant: hidden MMR with a visible rank that converges **[moderate, official]** *(read: Riot support page)*
- **Source:** [Riot Support, *How Rank Rating is calculated*](https://support.riotgames.com/valorant/gameplay/how-rank-rating-rr-is-calculated).
- **Inputs:**
  - Match outcome is the main input.
  - The round differential matters: a 13–2 result moves RR more than 13–9.
  - Individual performance "slightly" adjusts RR, and matters less at high ranks.
- **Convergence:** if MMR is above rank, wins pay more and losses cost less. The reverse also applies.
- **Losses:** you never gain RR from a loss.
- **Resets:** rank resets each Act, followed by placements.
- **Not published:** the base RR values.

### 2.7 Roblox Rivals **[anecdotal; no first-party design interview found]** *(read: RoWatcher)*
**Source:** [RoWatcher](https://rowatcher.com/news/rivals-how-roblox-s-top-shooter-built-a-nearly-million-player-empire).

- **Scale and updates:** launched 2024-06-28, peaked at 967,342 concurrent users, passed 13B visits by March 2026, and shipped 19 major updates in 21 months.
- **Ranked design:**
  - Tiers run from Bronze to Archnemesis.
  - Hidden MMR sits behind a visible Rank Rating.
  - Curated maps with bans.
  - Maximum of 2 weapon swaps per duel.
  - **Input-based matchmaking** separates mobile players from mouse-and-keyboard players.
- **Monetisation:** cosmetics only; "no purchase offers a competitive edge."
- **Ranked gate has tightened over time:**
  - Earlier fan guides ([allthings.how](https://allthings.how/roblox-rivals-ranked-mode-and-ranks-explained/)) list level 30, 10 duels and a 14-day-old account.
  - In 2026 it became **level 50 plus real-world verification** (Updates 17–18).
- **The pattern:** casual play feeds a stricter, less random ranked ruleset.

### 2.8 Designers of runners and racers on skill versus chaos
- **Fall Guys** **[anecdotal, interview read]** ([GamesBeat](https://gamesbeat.com/fall-guys-ultimate-knockout-how-mediatonic-crafted-a-cute-battle-royale/)):
  - Lead designer Joe Walsh: "about 80 percent skill and a 20 percent sprinkling of chaos." They don't want speedrunners winning every time.
  - They capped lobbies at 60 rather than 100 because it "played better."
  - Snippet: Walsh says the right difficulty is when "you always feel like it was your fault."
- **Mario Kart, Kosuke Yabuki** **[anecdotal, snippet]**:
  - Balance came from "thousands of tests."
  - He offers a no-items option to players who want pure racing ([GameSpot](https://www.gamespot.com/articles/mario-kart-8-it-s-not-all-about-luck-two-rainbow-roads-confirmed/1100-6418730/), [Twinfinite](https://twinfinite.net/2017/07/mario-karts-director-explains-why-the-dreaded-blue-shell-isnt-going-away/)).
  - **Lesson:** keep separate rulesets for chaos and for skill.
- **Trackmania** **[moderate, official]** ([Ubisoft](https://news.ubisoft.com/en-us/article/2TT6868Gzx9cZpbqOVXCJn/trackmania-nations-remake-revealed), [docs](https://doc.trackmania.com/play/watch-replays)):
  - You race your best ghost.
  - You can download the world's best replays.
  - Every opponent is intangible.
- **Celeste** **[anecdotal, article read]** ([*Celeste & Forgiveness*](https://maddymakesgames.com/articles/celeste_and_forgiveness/index.html)):
  - Coyote time and jump buffering.
  - A 2 px (quarter-tile) wall-jump window "fudged … in the player's favor."
  - **Lesson:** wide windows and a graded outcome can coexist.
- **Subway Surfers** **[anecdotal]** ([Deconstructor of Fun](https://www.deconstructoroffun.com/blog//2013/02/monetizing-infinite-runner.html)): depth comes from verticality (train roofs), not from more lanes.

**Not found despite searching:** a GDC transcript on skill in Subway Surfers, Temple Run or Fall Guys, and any Nosniy design interview.

---

## 3. Principle
Keep the controls (3 lanes, jump, slide) and the chaos (boxes and abilities). Add four things:
1. **Grade** every obstacle (2.1, 2.2).
2. **Rate** runs on time and cleanliness, which the goal cap can't flatten (2.5, 2.6).
3. **Race people or honest ghosts**, never dice (2.3, 2.4, Trackmania).
4. **Cap chaos at about 20% in ranked** (Fall Guys, Mario Kart, Rivals).

---

## 4. Mechanics with concrete numbers
Run speed is 35 → 45.5 studs/s, so **1 stud ≈ 22–29 ms of travel**.

### 4.1 Clean / Close / Hit grading + combo
**Grades:**

| Grade | Rule | ≈ time |
|---|---|---|
| **Hit** | A stumble (existing `Runner.onStumble`) | — |
| **Close** | Cleared, with the closest gap between the root hitbox and the hazard part **≤ 2.0 studs**. For a jump, that means landing or taking off within 2 studs of the hazard. For a lane switch, it means finishing within 2 studs. | 44–57 ms |
| **Clean** | Cleared with a bigger margin than that | — |
| **Perfect landing** (see 4.3) | Slide pressed within **±100 ms** of touchdown | — |

**Tuning target:** a mid-skill player gets Close on about **15–30% of obstacles**. Adjust the 2-stud figure until play tests hit that.

**Combo:**
- +1 for each Clean or Close.
- A Hit resets it.
- At 10, 25 and 50, each obstacle adds +1, +2 or +3 m to `run.bonus`.
- Each Close adds +1 m and shows a "CLOSE!" pop with a whoosh.

**Death or finish screen:** show "Clean 41/47 · Close 9 · best combo 22". Add one comparison line only when the gap is real and small, such as "0.6 s behind 2nd" or "34 m short".

**Fit with the code:**
- `Runner.luau` grades on the client and sends `(obstacleId, grade)` to the server.
- The server rejects a claim unless all three hold:
  1. The runner's server-side `run.dist` has passed that segment.
  2. There was no stumble.
  3. There are at most 1 Close per obstacle and at most 60% Closes per run.
- Server positions lag about 100 ms (≈ 4.5 studs). The server can therefore confirm Hit or not-Hit, but it can't verify a 2-stud margin.
- Tag hazards in `Segments` with `ObstacleId = segIndex*100 + k`.

**Cost:** M, about 3 days.
**Risk:** a forged Close is worth at most +1 m. Tune on a real phone.

### 4.2 Run Rating → Glicko-2 → visible ranked tiers
**Ordering a run:**
- Finishers are ordered by **time to goal**.
- Everyone else is ordered by metres reached.
- In Last-Standing, the survivor is ranked first.

**MMR (Glicko-2):**
- Each run is turned into pairwise results, so a full field gives about 11 "games." That meets Glickman's 10–15 games per rating period, with one run as one period.
- Initial values: 1500 / 350 / 0.06, with **τ = 0.5** because runs are noisy.
- **Only humans and recorded ghosts are rated.**

**Visible rank:**
- Six tiers (Sprout, Vine, Canopy, Thunder, Apex, Jungle King), each with 3 divisions of 100 points.
- **Base points:** +25 for 1st, falling linearly to −20 for last.
- **Convergence:** base points × clamp(1 + (MMR − rankMMR)/400, 0.5, 1.5), where rankMMR = 1000 + 50·division.
- A bottom-half finish never gains points.
- The rank is shown once RD ≤ 150, which takes about 5–6 runs.

**Unlock: 25 runs, about 1.5 h.** This is lighter than Rivals' level 30–50 because runs here are short.

**Ranked ruleset:**
- Fixed 1,500 m goal.
- Speed ramp continues to x1.6 at 180 s.
- A **fixed shared pool** of 6 Common and Uncommon abilities, so the gacha gives no advantage.
- Rate touch and keyboard players separately, as Rivals does. The `Device` module already exists.

**Seasons:** every 6 weeks, pull MMR 50% of the way toward 1500 and set RD to 200.

**Fit with the code:**
- `Profile` gains `mmr`, `rd`, `vol`, `rankPts` and `rankedRuns`.
- An OrderedDataStore in `LeaderboardService`.
- A ranked pad in `Lobby.luau`.
- Ranked runs inside normal servers by rating only the humans queued for ranked, so no separate matchmaking is needed.

**Cost:** L, about 1.5–2 weeks.
**Depends on:** 4.4, so that ghosts can fill low-population fields.

### 4.3 Movement tech (no new buttons)

| Tech | Rule | Value |
|---|---|---|
| Jump-cancel slide | Slide in the air fast-falls; jump mid-slide ends the slide | Fast-fall gravity ×2 |
| Perfect landing | Slide within ±100 ms of touchdown | +8% speed for 1.0 s, stacks ×3 within 3 s |
| Risk routes | 1 in 4 fork segments get one route about 6% shorter, or with 2× gems, that ends in a gap or log row | Reuses the existing two-route segments (`Segments.luau` ~1340) |

- **Server cap:** three stacked boosts give 1.08³ ≈ 1.26×, which is within `MaxSpeedFactor 2.2`.
- **Cost:** M.
- **Risk:** precision on mobile. Keep the window at ±100 ms.

### 4.4 Ghosts, a Daily Course, and honest bots
**1. Make the course fully deterministic:**
- `PathService` line 246, `richJuice = os.clock() < richUntil`, depends on wall-clock time. Change it to depend on segment index.
- Store `seed`, `EasyRun` and the goal for each run.
- `difficulty = builtDist/4000` and decor clearing are already deterministic.
- **Check:** build the same seed twice and diff segment names and CFrames.
- **Cost:** S, about 1 day.

**2. Record each human:**
- Sample `run.dist` plus the lateral and height offset from `PathService.pointAt(dist)` at **10 Hz**.
- Pack each sample as u16 dist delta, i16 lateral and i16 height: **6 B**.
- A 240 s run is about **14 KB**, against a 4 MB limit per DataStore key.

**3. Play back:**
- A ghost is a bot whose position comes from the recording instead of the dice.
- It reuses `BotService.sendSnap` (buffer snapshots) and `BotSmooth.luau` interpolation.
- Ghosts are intangible, and `targetAhead` skips them.

**4. Daily Course:**
- One seed per day.
- DataStore `Ghosts_<yyyymmdd>` keeps the top 50 by time, each player's personal best, and 20 per tier to fill rated fields.

**5. Live bots that react:**
- Each bot's reaction time is drawn from N(260 ms, 40 ms) and scaled by skill.
- Lane errors run 5–15% and rise with obstacle density.
- A visible "BOT" tag, and bots stop wearing the owner's avatar.
- **Steering:** after two bottom-half finishes, live-bot skill drops 10%, and it resets after a top-half finish. This applies EOMM's LLL finding to *unrated* bots only.

**Cost:** about 2 weeks in total (S + M + M + M).

### 4.5 Counterplay and a "what got me" card
**Counterplay:**
- Each hostile ability shows a **400 ms telegraph**: an edge icon and a lane flash.
- A lane switch or jump during the telegraph dodges it. A dodge shows "DODGED!", gives +5 juice and adds +1 to the combo.
- `throwAt` already has a `travel` parameter: set its minimum to 0.4 s and send a warning remote.

**"What got me" card:**
- Format: "Spear from Mia (Canopy II): switch lanes on the red flash."

**Ranked chaos cap:** hostile uptime on any one runner stays at or below 20% of any 10 s window (the Fall Guys 80/20 split).

**Cost:** M.

---

## 5. Order: about 5–6 weeks for one developer
1. 4.1 grading.
2. 4.4 step 1, the 1-day determinism fix.
3. Ghosts and the Daily Course.
4. 4.2 ranked.
5. 4.3 movement tech.
6. 4.5 counterplay.

## 6. Don'ts
- No rubber-banding of rated results.
- No position-weighted items in ranked.
- No staged near-misses: Clark found that near-misses the computer arranged *lowered* the urge to keep playing.
- No rank and no `best` from runs against dice-bots.
- Nothing sold that affects ranked.
