# 02: Build-out depth. Ability levels, mutations, merges, evolutions

Angle: long-term investment and ownership. Every number below is a proposal tuned against the real code (`src/shared/Items.luau`, `src/shared/Config.luau`, `src/server/DataService.luau`, `src/server/RoundService.luau`).

Evidence strength: **[A]** peer-reviewed or official Roblox documentation, **[B]** developer's own channel or a consistent, multi-source description of a shipped mechanic, **[C]** a single fan guide (numbers change between patches).

**Verification pass (revision 2).** Every citation was re-checked online on 2026-11-16. Publisher pages (OUP, SAGE, Elsevier, JSTOR) and the Fandom wikis refused automated fetches (redirect or HTTP 402). So papers were verified through author or university copies and index records (Columbia, MIT, RePEc, Harvard DASH, Duke), and each is linked below. Where a figure could not be confirmed from a primary source, the text says so. The economy numbers are now checked by a Monte Carlo script, [`02_economy_sim.py`](02_economy_sim.py) (section 11). The simulation **changed the design**: leveling costs "shards" earned by using a gadget, because duplicates from 1,000-gem rolls are far too rare (section 2). It also changed the time-to-Lv10 figures.

## 0. What the code says today

- 14 gadgets in `Items.Gadgets`, each one fixed. A ? box gives one of your 3 loadout gadgets into one of 2 slots (`RoundService.luau` ~L737).
- `profile.items[id]` already counts **copies owned**. Duplicates are recorded but give nothing. That is the hook for this design.
- Roll: 1,000 gems, or 10 for 8,000. Rarity weights 55/26/13/5/1. Pity: Rare 10, Epic 25, Mythic 80.
- Income: `GemsPerMetre = 1/250`, `FinishGems 5`, `CampGems 2` every 500 m, and 1 gem per path diamond. A 1,200 m win earns about 5 + 5 + 4 + pickups, so **roughly 20-40 gems a run**. **One roll costs about 30-50 runs.** That gap is the real "nothing to do tomorrow" problem. The build-out layer needs a cheap material that every run produces, not more 1,000-gem rolls.
- The server has no `MarketplaceService` (only `client/Lobby.luau` references it). Rolls are not paid random items today. They become paid random items once gems can be bought with Robux, even indirectly (section 7).

## 1. The design in one picture

```
 RUN --drops--> Juice Drops (common material, every run)
                    |
         Level up a gadget (Lv1-10: Drops + duplicates)
                    |
         Brew Vat (real-time timer) --> Mutation on a gadget copy (rarity-rolled trait)
                    |
         Merge 3 same-mutation copies --> star tier of that mutation
 IN RUN: two Lv10 gadgets that form a recipe --> the 5th box is an EVOLUTION (fusion gadget)
```

There are four layers. A 10-year-old only sees layer 1 ("my Dash is Level 4, it lasts longer") and the coloured glow of layer 2. The 25-year-old chases layers 3 and 4.

## 2. Layer 1: Gadget levels (the IKEA and ownership layer)

Each gadget has a level from 1 to 10. Leveling costs **Juice Drops** (a new currency) plus **Shards of that gadget**. You earn 1 Shard each time you *use* the gadget in a run, so you level what you play. That is the IKEA mechanism: your own work on that item.

*Revision 2:* the first draft charged duplicates (5 at Lv10, 21 in total per gadget). The simulation shows a player gets about one roll per 50-60 runs (~18-22 gems a run against 1,000 gems a roll), spread over 14 gadgets. That makes 21 duplicates of one gadget take thousands of runs. Duplicates now convert to **25 Shards each** instead, which keeps `items[id]` useful.

| Level | Drops | Shards | Effect |
|---|---|---|---|
| 2 | 20 | 3 | +5% potency |
| 3 | 40 | 6 | +10% |
| 4 | 80 | 10 | +15%, bronze icon ring |
| 5 | 150 | 15 | +20%, **unlocks a mutation socket** |
| 6 / 7 / 8 / 9 | 250 / 400 / 600 / 900 | 25 / 35 / 50 / 70 | +25 / 30 / 35 / 40% |
| 10 | 1,400 | 100 | +45%, gold ring, **eligible for Evolution** |

"Potency" is one number per gadget: duration (Wild Dash 4 s to 5.8 s, Bar Freeze 8 s to 11.6 s), refill size (Juice Box) or radius (Gem Magnet). **Effects that hit other runners do not scale.** Bubble Trap, Spear and Frost stay at 0.9 s and Wild Hex at 2 s, matching the cap already written in `Items.luau`. This is the fairness firewall (section 8).

**Drops income:** 1 Drop per 50 m, +5 for finishing, and +0-4 from cans. That is about **20-35 Drops a run**. Simulated medians (section 11): the **first Lv5** comes after about 22-28 runs (day 1 for a grinder, day 2 for a regular, about day 10 for a casual player). **One gadget to Lv10** takes about 420-690 runs (day 11 for a grinder, day 54 for a regular). A casual player does not reach Lv10 within 120 days. **All 14 gadgets** to Lv10 is about 5,000+ runs, the long tail for spenders and grinders.

**Evidence (verified):**
- **IKEA effect** **[A]**. Norton, Mochon & Ariely, "The IKEA effect: When labor leads to love", *Journal of Consumer Psychology* 22(3), 453-460 (2012). [Duke Scholars record](https://scholars.duke.edu/publication/861385), [Harvard DASH full text](https://dash.harvard.edu/handle/1/12136084). The finding: people value things they assembled more than identical ready-made ones, but **only when the work ends in completion**. The effect disappeared when participants built and then destroyed their creation, or did not finish it. Design rule: **never let a level or mutation be lost**, and no failed upgrade may break an item, unlike Diablo or MapleStory enhancement.
- **Competence signal** **[A]**. Mochon, Norton & Ariely, "Bolstering and restoring feelings of competence via the IKEA effect", *IJRM* 29(4), 363-369 (2012). [RePEc](https://econpapers.repec.org/RePEc:eee:ijrema:v:29:y:2012:i:4:p:363-369), [Harvard DASH PDF](https://dash.harvard.edu/bitstream/1/11320608/1/mochon,norton,ariely_bolstering.pdf).
- **Endowment effect** **[A]**. Kahneman, Knetsch & Thaler, "Experimental Tests of the Endowment Effect and the Coase Theorem", *JPE* 98(6), 1325-1348 (1990). [RePEc](https://econpapers.repec.org/RePEc:ucp:jpolec:v:98:y:1990:i:6:p:1325-48), [MIT course copy](https://web.mit.edu/curhan/www/docs/Articles/15341_Readings/Behavioral_Decision_Theory/Kahneman_et_al_1990_Experimental_tests.pdf). Mug markets traded far fewer mugs than the half that theory predicts. The authors' 1991 *JEP* summary puts median selling prices at "about twice" median buying prices. Caveat: Plott & Zeiler's replications got the gap only under some procedures, so treat the size of the effect as moderate.
- **Goal-gradient** **[A]**. Kivetz, Urminsky & Zheng, "The Goal-Gradient Hypothesis Resurrected: Purchase Acceleration, Illusionary Goal Progress, and Customer Retention", *JMR* 43 (Feb 2006), 39-58. [Columbia PDF](https://business.columbia.edu/sites/default/files-efs/pubfiles/1200/goalgradient.pdf). Customers bought faster as they neared a coffee-card reward, illusory progress also sped them up, and stronger acceleration predicted retention. Design rule: show the bar to the next level on every results screen.
- **Endowed progress** **[A, figure partly verified]**. Nunes & Drèze, "The Endowed Progress Effect: How Artificial Advancement Increases Effort", *JCR* 32(4), 504-512 (2006). The design is confirmed in secondary write-ups ([Coglode](https://www.coglode.com/nuggets/endowed-progress-effect)): car-wash cards needing 8 stamps, against 10-stamp cards with 2 pre-stamped. The widely quoted completion rates, **34% vs 19%**, came from my memory and match the "nearly twice" summary, but I could not open the abstract (the OUP page refused the fetch). Quote the ratio, not the exact percentages, until checked. Design rule: each gadget's first level bar starts partly filled.

## 3. Layer 2: Mutations (the Grow a Garden layer)

A mutation is one trait on one gadget copy, shown as a glow colour and one word ("**Frosty** Wild Dash"). Mutations add a **side effect**. They never add raw power against other players.

| Mutation | Weight | Look | Effect (works on any gadget) |
|---|---|---|---|
| Juicy | 40% | orange drip | Using it also gives +6 juice |
| Bouncy | 25% | green | Using it gives a free small hop |
| Shiny | 18% | sparkle | +2 gems on use |
| Frosty | 10% | blue | Guardian slowed 10% for 3 s |
| Golden | 5% | gold | +1 Drop and +1 gem every 100 m while it is equipped |
| Rainbow | 1.8% | cycling hue | Each use rolls a random other mutation's effect |
| Cosmic | 0.2% | starfield | Comes back once per run after use |

Golden, Rainbow and Cosmic copy Grow a Garden's rare base traits. **Primary-source status:** I found no official update log, Trello board or datamine repository that publishes Grow a Garden's odds. The lead developer (Jandel) announces features on the official Discord, for example Pet Mutations on 8 July 2025 ([esports.gg](https://cache.esports.gg/news/roblox/grow-a-garden-everything-about-the-pet-mutations-update)), but those posts do not give odds. Several guides that agree with each other list **Gold ~1% (x20)** and **Rainbow ~0.1% (x50)** as random growth variants **[C]**: [Deltia Plasma guide](https://deltiasgaming.com/?p=241855), [Pocket Tactics](https://www.pockettactics.com/grow-a-garden-mutations), [DroidGamers](https://www.droidgamers.com/guides/grow-a-garden-mutation-multiplier-guide/). Other guides give x10 / x30, or x25 / x40 in Grow a Garden 2, so treat these as approximate. Our rare tiers are more common because a Jungle Juice player owns 14 gadgets, not hundreds of crops.

### Getting one: the Brew Vat (the daily return)

- In the lobby, put a Lv5+ gadget in the **Brew Vat**, pay **60 Drops** and wait **4 real hours**, online or offline. It comes out with one mutation from the table.
- **2 vat slots** free, and a 3rd at player level 15. A 4-hour timer fits one check-in after school and another at night. A brew that finishes while you are away gives a concrete reason to come back. Open loops pull people back (Zeigarnik 1927) **[A, weak: replication is mixed]** *(memory)*.
- **Weather events, live in every server:** every 45 minutes a 5-minute "Jungle Storm" or "Golden Hour" runs. A vat that finishes during one gets 3x odds for that tier (Frosty in a Storm, Golden in Golden Hour). This copies Grow a Garden's 5-minute weather windows that boost one mutation **[C]**: [allthings.how](https://allthings.how/grow-a-garden-2-weather-events-and-what-each-one-does/). Announce each event in every server.
- **Pity:** a guaranteed Golden or better every 25 brews, stored like `profile.pity`.
- **Expected timing (simulated medians, section 11):** first mutation on day 1 for a grinder, day 2 for a regular and about day 11 for a casual player. First Golden on day 3, day 7 and about day 24. First Cosmic by day 120: 89% of grinders, 58% of regulars and 27% of casual players. Cosmic stays a rare showpiece, which is the intent.
- Re-brewing a copy asks "Keep Frosty or take Juicy?", and the player chooses. Nothing is lost without the player choosing it (the IKEA caveat).

## 4. Layer 3: Merging (the pet-sim layer)

**Merge 3 copies of the same gadget with the same mutation into one copy with a star.** Stars go from 1 to 3. 2 stars gives 1.5x the side effect, and 3 stars gives 2x plus a stronger look. The merge fee is 100 Drops for 2 stars and 300 for 3.

This follows the pet-game ladder. **Adopt Me** **[B]**: 4 Full Grown pets of the same kind make 1 Newborn Neon at the Neon Cave, and the 4 pets are consumed. 4 Full Grown Neons (16 original pets) make a Mega Neon, added in April 2020 ([Neon Cave wiki mirror](https://breezewiki.discard.no/adoptme/wiki/Neon_Cave), [Pro Game Guides](https://progameguides.com/roblox/how-to-make-a-neon-pet-in-adopt-me)). Neons must be aged up again, so each tier repeats the grind. **Pet Simulator 99** **[B/C]**: the Golden Machine (Area 10) and Rainbow Machine (Area 31) each take up to 10 copies of one pet. Success is chance-based, rises with the number of copies, and failed inputs are lost. Mastery removes one required pet at levels 60 and 90 ([Pro Game Guides](https://progameguides.com/roblox/where-is-the-rainbow-machine-in-pet-simulator-99-roblox/), [HoldToReset mastery list](https://holdtoreset.com/pet-simulator-99-mastery-list/), official patch notes at [biggames.io](https://biggames.io/post/pet-simulator-99-update-7)). I found no published odds table for the machines. **Our merge is deterministic (3 in, 1 out, never fails)**, on purpose: per the IKEA finding, destroyed work erases the attachment it built, and a kid-facing game should not hide a loss chance.

Merging is the main **economy sink** for duplicates and Drops. It needs `items` to store copies that carry traits, not only a count (section 9).

## 5. Layer 4: Evolutions (the Vampire Survivors and Hades layer, depth inside a run)

- **Vampire Survivors** **[B]**: the base weapon must be at max level (usually 8) and you must hold its paired passive (any level for most base pairings, maxed for some). The evolution then comes from a chest opened **after the 10-minute mark**, typically a boss chest. Some evolutions combine two maxed weapons instead (Peachone + Ebony Wings make Vandalier). Sources: [PC Invasion](https://www.pcinvasion.com/?p=352431), [Prima Games](https://primagames.com/gaming/vampire-survivors-weapon-evolution-guide), [Steam discussion](https://steamcommunity.com/app/1794680/discussions/0/3830916907609154098). Our "5th box of the run" plays the role of VS's post-10-minute chest, and two-gadget recipes copy Vandalier.
- **Hades** **[B, not re-fetched]**: Duo Boons need boons from two specific gods in the same run. The Fandom wiki refused automated fetches, so this rests on general knowledge of the shipped game.
- **Balatro** **[unverified, removed as evidence]**: kept only as a loose analogy.

**Rule:** if your loadout holds two **Lv10** gadgets that form a recipe, the **5th ? box of each run** gives their Evolution instead. The box glows gold mid-run so everyone sees it.

| Recipe | Evolution | Effect |
|---|---|---|
| Wild Dash + Rocket Boots | Comet Run | 3 s dash that flies over one obstacle |
| Grapple Hook + Glider | Canopy Swing | Grapple, then glide for 3 s |
| Juice Box + Bar Freeze | Bottomless Cup | Full refill and no drain for 6 s |
| Decoy Snack + Mighty Roar | Feast Call | Guardian stops for 4 s, which also saves the runners behind you |
| Shell Shield + Bubble Trap | Bubble Fort | A shield that bubbles whoever hit you (0.9 s) |
| Gem Magnet + any Golden copy | Treasure Sense | 10 s magnet, gems x2 |
| Frost Breath + Spear Throw | Glacier Lance | Still the 0.9 s cap, but hits 2 runners ahead |

Recipes stay **hidden until found**. They show as "???" with a hint ("something that flies + something fast"), and the inventory shows "Evolutions found 2/7". A partly filled set pulls toward completion (endowed progress above).

**How a run changes:** today a run is "grab a box, press the button". With this system, early boxes hand you your levelled gadgets (longer and stronger), and every use triggers a mutation side effect (juice drip, hop, gems). Then the 5th box turns gold and gives a fusion that changes the next 30 seconds. That gives a 2-4 minute round the Hades feeling of a build coming together.

## 6. Readable for a 10-year-old, deep for a 25-year-old

- **Kid view:** a level number, a ring colour, one glow colour and one word. Each tooltip is one plain line ("Juicy: also gives juice").
- **Spender view:** a "Lab" tab in Inventory with each copy's stars, vat timers, the weather forecast, the recipe book and the odds tables (which are required anyway).
- **Caps:** one mutation per gadget and at most one evolution per run. Do not add stacked affix lists like Path of Exile's six affixes. That depth is the cautionary end of the scale for this audience.

## 7. Roblox policy (checked 2026-11-16)

- Any random item bought with Robux, **or with in-game currency that can be bought with Robux**, must list every outcome and its odds. Odds boosters must be explained before purchase, and boosted odds must be shown live while a booster is active **[A]**: [Creator Docs, Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items).
- If `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` is true, that player must not be able to use paid random generators. Hide or block them **[A]**: [same page](https://create.roblox.com/docs/production/monetization/paid-random-items), [PolicyService](https://create.roblox.com/docs/reference/engine/classes/PolicyService). Roblox does not do this for you **[C]**: [DevForum thread](https://devforum.roblox.com/t/about-policy-service-arepaidrandomitemsrestricted/2088093).
- **Recommendation:** never sell Juice Drops, so the vat is not a paid random item. If a Robux product is added, have it change time only ("finish brew now", a 3rd vat slot), never odds. A "Lucky Brew" that raises odds is a paid odds booster. It would need a live odds display and the PolicyService check. If the policy call fails, treat the player as restricted. Show the odds tables on the vat and roll screens anyway. The gem roll should show its 55/26/13/5/1 table now, and it becomes mandatory the moment gems are sold.

## 8. Risks

1. **Power creep in a 12-runner race.** Levels and mutations scale only effects on yourself and side rewards. Effects that hit other players keep fixed caps (0.9 s and 2 s). Target: a full Lv10 loadout adds at most **+6% expected finish distance**. Measure it with the bots: 200 simulated rounds of a maxed loadout against a fresh one. As a fairness valve, add an optional "Classic" mode that sets every gadget to Lv5.
2. **A wall for new players.** Bots (`FieldSize 12`) already fill races. Give bots average levels, not max levels, so new players still win sometimes. `GoalNewShift` already helps.
3. **Sunk cost turning sour** **[A]**. Arkes & Blumer, "The Psychology of Sunk Cost", *OBHDP* 35, 124-140 (1985) ([PDF copy, Univ. Klagenfurt](https://cognition.aau.at/bg/BA/Arkes%20%26%20Blumer%201985.pdf)): people show "a greater tendency to continue an endeavor once an investment in money, effort, or time has been made", and those who had paid a sunk cost rated the project's success as more likely. Players will stay because of what they built. The same investment breeds resentment if a patch nerfs it, so never wipe or nerf levels, and rebalance by buffing.
4. **Variable-ratio rewards and children.** Vat odds are a variable-ratio schedule (Ferster & Skinner 1957, *Schedules of Reinforcement*; textbook result, not re-fetched). Keep the vat unpaid, publish its odds and keep pity.
6. **Grinder runs out of content.** The simulation has a 3 h/day player finishing their 3-gadget loadout at Lv10 by about **day 15**. The other 11 gadgets keep them busy for months, but the *evolution chase* for their main build ends in two weeks. Mitigation: add evolutions in content drops (2 new recipes a month), and give each finished evolution a cosmetic "mastery" track.
7. **Casual player never sees an evolution.** At 5 runs a day, Lv10 is not reached in 120 days. Mitigation: a weekend **"Evolution Taster"** event that lets recipes fire from Lv7, so kids see the payoff and know what they are working toward (goal-gradient).
5. **Save size.** Storing each copy grows the profile. Cap the inventory at 200 copies and suggest merges automatically.

## 9. Fit with the existing data (DataService)

Add these optional fields to `Profile`. Each is safe when missing, so old saves still load, the same way `questStamps` is optional today:

```lua
drops: number?,                                   -- Juice Drops
glevels: { [string]: number }?,                   -- gadget id -> level (missing = 1)
copies: { { id: string, mut: string?, star: number? } }?, -- mutated copies; plain dupes stay counted in items[id]
vats: { { copy: number, done: number, mut: string? } }?,  -- done = os.time() when the brew finishes
brewPity: number?,
evolutions: { [string]: boolean }?,               -- recipes discovered
equippedCopy: { [string]: number }?,              -- gadget id -> which mutated copy the loadout uses
```

- The `items[id]` count keeps working as the duplicate pool. Leveling spends from `items[id] - 1`.
- `Items.luau` gains `Items.Mutations`, `Items.LevelCurve`, `Items.Evolutions` and `Items.BrewOdds`, next to the existing `RarityWeight` and `Pity`.
- `RoundService.luau`: on each box pickup (~L737), count boxes per run, and on the 5th check the recipes. `useGadgetEffect` (~L540) reads level and mutation from player attributes set at round start. Award Drops in the same places that call `addGems` (camps, finish, distance).
- Analytics: log Drops through the same `txType`/`sku` path that `addGems` uses, so Drop sources and sinks show up in the Economy dashboard.

## 10. Numbers at a glance

| Item | Value |
|---|---|
| Drops per run | ~20-35 |
| Gems per run (simulated, current Config) | ~18-22, so 1 roll per ~50 runs |
| Runs to the first Lv5 | ~22-28 |
| First mutation | Day 1 (grinder) / 2 (regular) / ~11 (casual) |
| First Golden | Day 3 / 7 / ~24 |
| Brew Vat | 60 Drops, 4 h, 2 slots (3 at level 15), Golden-or-better pity every 25 brews |
| Weather events | Every 45 min, last 5 min, 3x odds for one tier |
| Merge | 3 copies with the same mutation make 1 starred copy; fee 100 / 300 Drops; never fails |
| One gadget to Lv10 | ~420-690 runs (day 11 grinder, day 54 regular, casual not within 120 days) |
| Whole loadout at Lv10 | Day 15 grinder, day 73 regular |
| Evolution | Two Lv10 gadgets that form a recipe; the 5th box of the run |
| Maximum advantage from your own upgrades | +6% finish distance at most |

## 11. Simulation (`02_economy_sim.py`)

Run it with `python -I 02_economy_sim.py`. It runs 400 simulated players per type over 120 days, using the real `GoalBuckets`, gem constants and the level, vat and mutation tables above.

**Assumptions to replace with telemetry:**
- 5 boxes per full run.
- Finish rates: 35%, 55% and 75% by player type.
- Gems from path diamonds: 4-14 a run.
- Drops are spent first on leveling the lowest gadget, keeping a reserve for the vats.

| Player type | Runs/day | Lv5 | 1st mutation | 1st Golden | 1st gem roll | 1st Lv10 | Loadout Lv10 | Cosmic by day 120 |
|---|---|---|---|---|---|---|---|---|
| Casual (20 min) | 5, 4 days/wk | day 10 | day 11 | day 24 | day 20 | not reached | not reached | 27% |
| Regular (1 h) | 15, 6 days/wk | day 2 | day 2 | day 7 | day 4 | day 54 | day 73 | 58% |
| Grinder (3 h) | 40, daily | day 1 | day 1 | day 3 | day 2 | day 11 | day 15 | 89% |

**Readings:**
- The daily hooks land early for everyone: a mutation within 2 days for regulars and within ~2 weeks for casual players. The Golden chase fits the 1-4 week range that keeps a player returning.
- The gem-roll economy is slow (one roll per ~50 runs) but now secondary, because Shards and Drops carry daily progress.
- The two weak points are listed as risks 6 and 7 in section 8. Tune `LEVELS` shard costs first if telemetry differs.
