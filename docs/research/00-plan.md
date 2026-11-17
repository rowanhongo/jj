# Jungle Juice: the plan from the four research reports

Sources: 01-mastery-competition.md, 02-build-out-depth.md (+ 02_economy_sim.py),
03-retention-one-more-run.md, 04-spending-social.md. Each claim below is backed in those
files with links and an evidence grade. Anything marked (weak) rests on fan guides or a
secondary summary.

## The diagnosis (all four agree, from the code)

1. **Nothing measures how well you ran.** Everyone who reaches a 1,000-1,300 m goal "wins";
   a perfect run and a scrappy one score about the same. Self-determination theory says the
   feeling of competence needs feedback on *how well*, not just the outcome
   (Przybylski, Rigby & Ryan 2010).
2. **Beating bots means nothing.** Bots decide each obstacle with one dice roll
   (`BotService.fails`) and wear your avatar.
3. **The urge to go again is spent waiting.** Death to next GO is about 36 s solo, and up to
   about 110 s while other humans are still running (RoundService L1447, L1516-1520, L1071-1072).
   Children discount delayed rewards hardest (Green, Fry & Myerson 1994).
4. **Nothing you own grows.** Duplicates do nothing; one 1,000-gem roll is about 50 runs.
5. **Money code is not safe to switch on.** There is no ProcessReceipt handler, bought gems
   would count on the MOST GEMS board, the gem roll is a paid random item under Roblox
   policy with no odds shown and no PolicyService check.

## The plan, in order

### Phase 0 - must do first (about 2 days)
- Results wait 5 s -> 3 s, intermission 25 s -> 10 s (solo death-to-GO ~36 s -> ~19 s).
- Show the roll odds before spending; check `ArePaidRandomItemsRestricted` in a pcall
  (failure = restricted) and give restricted players a fixed-price "Pick a gadget" shop.
- ProcessReceipt handler; bought gems kept out of `gemsEarned` (the MOST GEMS board).

### Phase 1 - make a run feel like skill (about 2 weeks)
- **Clean / Close / Hit** on every obstacle: "CLOSE!" when you clear it with <= 2 studs
  spare, a combo that resets on a stumble (10/25/50 = +1/+2/+3 m per obstacle). Near-misses
  raise the urge to play on only when the player caused them (Clark et al. 2009, read in full).
- **Honest death card:** "137 m SHORT", your best, the leader, what got you and a tip.
  Only true numbers: faked near-misses lower the urge (same study).
- **A designed peak in the last 20%:** "200 m TO GO", music change, FOV kick, finish arch,
  winners' podium (goal-gradient, Kivetz et al. 2006; peak-end rule).
- **Ability counterplay:** a 0.4 s tell you can dodge by lane change or jump, "DODGED!",
  and a "what hit you" card.
- **Movement tech, no new buttons:** slide/jump cancels, a perfect-landing boost
  (+8% for 1 s, stacks x3), risky shortcut routes on the existing forks.

### Phase 2 - abilities you build (about 3-4 weeks)
- **Levels 1-10** paid with Juice Drops (earned only, never sold) plus Shards (1 per use of
  that gadget in a run; a duplicate = 25 Shards). Levels only boost effects on yourself;
  hits on others keep their 0.9 s / 2 s caps.
- **Brew Vat mutations:** 60 Drops, 4 real hours, 2 slots, pity Golden every 25 brews.
  Juicy 40 / Bouncy 25 / Shiny 18 / Frosty 10 / Golden 5 / Rainbow 1.8 / Cosmic 0.2 %.
  Mutations add side effects, never more power against others. A 5-minute "weather" every
  45 minutes triples one mutation's odds (the come-back-later hook).
- **Merging:** 3 of the same mutation -> a starred copy (up to 3 stars).
- **Evolutions:** two Lv10 gadgets that make a recipe turn your 5th box into a fusion
  (e.g. Wild Dash + Rocket Boots = Comet Run); recipes hidden until found.
- Simulated (400 players per type, 120 days): a regular player (15 runs/day) gets Lv5 and
  a first mutation on day 2, a Golden on day 7, a first Lv10 on day 54; a grinder finishes
  in ~2 weeks (so ship 2 new recipes a month); a casual never sees an evolution (so a
  weekend "Evolution Taster" lets recipes fire from Lv7).
- Nothing a player builds is ever destroyed (the IKEA effect vanishes when the thing is
  lost; Norton, Mochon & Ariely 2012).

### Phase 3 - competition (about 3-4 weeks)
- Make the course fully seeded (one non-deterministic line, PathService L246), then
  **ghosts** of real runs (about 14 KB per run) including your personal-best ghost, and a
  **Daily Course** everyone runs on the same seed. Racing your own ghost raised motivation
  over 4 weeks (Michael & Lutteroth, CHI 2020).
- Bots that react to the course and are tagged as bots.
- **Ranked** after 25 runs: hidden Glicko-2 rating, visible tiers, fixed 1,500 m goal,
  everyone's gadgets set to Lv5 so builds never decide rank. Only humans and ghosts are rated.

### Phase 4 - daily return, social, money (about 2-3 weeks)
- 7-day streak calendar, day 1 ticked on arrival, a missed day pauses it instead of
  resetting it.
- Statues wear the champion's cosmetics; "you beat <friend> by N m"; party join;
  friends-only board.
- Robux buys status and convenience, never power: VIP Runner pass 299 R$, Jungle Pass
  ~499 R$ per 6-8 week season (50 tiers, premium track refunds 70-100% in gems),
  statue looks 99-199 R$ for current top-10 holders only, gem packs 49-1,499 R$.
  No Robux rolls, luck boosts, gadgets or revives (loot-box spend links to problem
  gambling far more than other purchases: Zendle & Cairns 2018). No trading.

## Where the reports pulled against each other, and the call
- **Builds vs fair competition:** levels give an edge, ranked wants none. Call: levels only
  touch self-effects, and ranked sets everyone to Lv5.
- **Robux to speed up the Brew Vat:** one report allowed it. Call: not at launch; it is
  pay-to-progress and the vat is a random roll.

## What is still not proven
- The near-miss window, combo values, economy and pass prices are proposals; they need
  playtests and the simulation's guesses (5 boxes a run, finish rates) replaced with real data.
- Grow a Garden mutation odds and Rivals' ranked rules come from fan guides and press (weak).
- No designer talk on Subway Surfers / Temple Run / Fall Guys or interview with the Rivals
  developers was found.
- Nunes & Drèze's exact 34% vs 19% is only in a secondary source.
