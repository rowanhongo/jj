# 04 — Spending, social status and the Roblox market (Jungle Juice)

Revision 2 (2026-11-16). Policy claims are quoted from Roblox pages fetched on that date. Evidence key:
**[A]** official Roblox docs, newsroom or staff talk; **[B]** peer-reviewed research; **[C]** press or third-party trackers, with no audited figures.

## 0. What the code does today (read, not guessed)
| Fact | Where |
|---|---|
| 14 gadgets (gameplay items) with rarity weights 55/26/13/5/1 | `shared/Items.luau` `RarityWeight` |
| A random gadget roll costs 1,000 gems; ten rolls cost 8,000 | `Items.RollPrice`, `Roll10Price`; `server/ShopService.luau` `handlers.Roll` |
| Robux gem packs: 1000 gems for 49 R$, 2400 for 99 R$, 7000 for 249 R$, all `productId = 0` | `Items.GemPacks` |
| The client already prompts the purchase and has a "Gift to <player>" flow | `client/Lobby.luau:676-688, 1160`; `ShopService.GiftTarget` |
| **There is no `ProcessReceipt` handler anywhere in `src/server`**, so live products would charge players and credit nothing | grep |
| `DataService.addGems` adds to `gemsEarned`, which feeds the global **MOST GEMS** board | `DataService.luau:419-428`, `LeaderboardService.luau:35` |
| No `PolicyService` call exists | grep |
| Friend boost gives +10% run gems per friend in the server, capped at 100% | `server/FriendBoost.luau` |
| Earned-only titles exist (`T_Untouch` for 3,000 m); emotes and trails are sold in a 4-slot daily gem shop | `Items.Cosmetics` |

Two blockers before any product id is filled in:
1. A receipt handler must exist.
2. It must credit gems **without** `addGems`. Otherwise purchased or gifted gems raise `gemsEarned`, and anyone can buy a place on the MOST GEMS board.

## 1. Policy (quoted from fetched pages)

### 1.1 The gem roll is a paid random item
https://create.roblox.com/docs/production/monetization/paid-random-items covers random items bought "directly or indirectly with Robux" and says "This includes random items purchased with paid in-game currency." The gems here are a single pool, so **every roll is covered**, including rolls by players who never bought gems.

Requirements, quoted:
- You "must indicate all possible outcomes and the actual numerical odds"; percentages "sum to exactly 100%".
- With currency, you "must disclose the odds … before they spend the in-game currency."
- Odds boosters "must be numerically explained" before purchase and "dynamically updated when these items are active."
- When `ArePaidRandomItemsRestricted` is true, "the user cannot interact with paid random item generators." The accepted treatments include "Offering an unpaid, earnable path to acquiring the random item", removing the item, or blocking with an error.
- Random rewards from an action that involves no Robux or paid currency need no odds disclosure. The page's example is an earned key opening a chest. **Jungle Juice's in-run `?` boxes are therefore fine.**

### 1.2 PolicyService (https://create.roblox.com/docs/reference/engine/classes/PolicyService.md)
Fields:
- `ArePaidRandomItemsRestricted`: "the player can **not** interact with paid random item generators".
- `IsPaidItemTradingAllowed`: "the player can trade virtual items that they purchased with in-experience currency or Robux".
- `IsEligibleToPurchaseSubscription`.
- `IsEligibleToPurchaseCommerceProduct`.
- `AreAdsAllowed`.

The docs samples wrap the call in `pcall`. It errors if called "more than 100 … times before an HTTP response comes back", so call it once per player on join and cache the result. **If the call fails, treat the player as restricted.**

### 1.3 Questionnaire and age access (https://create.roblox.com/docs/production/promotion/experience-guidelines)
- "If your game sells randomized rewards that meet Roblox's Randomized Virtual Items Policy, answer yes."
- "Games with a Minimal or Mild rating are eligible for Roblox Kids (ages 5–8) and Roblox Select (ages 9–15)."
- "If a game does not have content ratings, Roblox restricts the playability".
- "Unplayable gambling content" sets a minimum age of 13, and "This category does not apply to paid random items."

**Consequence:** keep casino imagery (slot reels, chips, "jackpot") out of the roll UI so the game stays Minimal or Mild.

### 1.4 Subscriptions (https://create.roblox.com/docs/production/monetization/subscriptions)
- Prices: any Robux amount "equal to or greater than 49 Robux"; local-currency tiers "$2.99, $4.99, $7.99, $9.99, or $14.99".
- Payout: 70% for Robux subscriptions; local currency pays "70% in the first month, then 100% in subsequent months."
- Rules: "Mutually exclusive subscriptions are not supported"; Robux prices change once every 60 days; there are no Robux refunds; benefits cannot be gated once paid for.

### 1.5 Price optimization (https://create.roblox.com/docs/production/monetization/price-optimization)
- It needs "at least 60,000 transactions over the previous 30 days", so it is unavailable at launch.
- It "can't collect data from and make changes to prices you have hard-coded". Read prices with `GetProductInfo` now.
- The page publishes **no** uplift percentages, so any "X% uplift" figure seen elsewhere is not Roblox's.

### 1.6 Pages I could not verify
- The Roblox advertising standards page returned 403 and the DevEx docs URL returned 404. The DevEx rate below comes from the newsroom and press.
- I found no global under-13 ban on paid random items. Restriction is per player through `ArePaidRandomItemsRestricted`.

## 2. Market numbers, reconciled
| Claim | Source | Strength | Reconciliation |
|---|---|---|---|
| Creators earned "over $1 billion" through DevEx in the year to mid-2025; DevEx rate +8.5% | https://about.roblox.com/newsroom/2025/09/roblox-rdc-2025 | A | Press gives $0.0038 per Robux (from $0.0035), which matches the +8.5% |
| Average yearly earnings: top 10 developers $38.5M, top 100 $7M, top 1,000 $980k; **median DevEx creator $1,440** | Nick Tornow at RDC 2025, reported by https://gameworldobserver.com/2025/09/08/how-much-top-developers-earn-in-roblox-official-data | A (second-hand) | A top-1,000 game makes about 680x the median creator. Budget for the median and design for the tail. |
| A further +42% DevEx rate on spend from age-checked US players 18+, R15 games only, from June 8 | https://about.roblox.com/newsroom/2026/04/roblox-fuels-high-fidelity-games-over-18-players-increases-qualifying-devex-rate-42 | A | Small effect for a mostly-child audience. Confirm Jungle Juice's player rig is R15 before counting on it. |
| FY2025: revenue about $4.9bn, bookings $6.8bn, DAU 126.5m average, Q4 monthly unique payers 36.7m | https://www.pocketgamer.biz/roblox-revenue-up-36-yy-as-grow-a-garden-and-steal-a-brainrot-drive-multiple-milestones/ | A via press | **Derived:** about $54 of bookings per DAU per year, roughly $0.15 per DAU per day, as the platform average |
| Grow a Garden made "$12 million" in May 2025 (seeds, upgrades, rare animals) | https://www.calcalistech.com/ctechnews/article/dj4lxef8r | C (no named source) | RoWatcher's modelled $1.75M a month is about 7x lower. Both are modelled. |
| Rivals was #1 on the PC top-earning chart and #2 on mobile behind Steal a Brainrot (Jan 2026) | https://www.pcgamesn.com/roblox/highest-revenue-jan-2026 citing https://www.roblox.com/charts/top-earning | Rank: A. Dollars: none. | Tracker dollar figures for Rivals ($1.74M to "$8–15M+" a month) disagree by about 8x on undisclosed models, so they are not cited as fact |

**Verdict:** only the rank and Roblox's aggregate figures are reliable. Rank shows that both a cosmetic-first shooter (Rivals) and progression or collection games (Grow a Garden, Steal a Brainrot) reach the top on Roblox.

## 3. Mechanisms and peer-reviewed sources
| Mechanism | Evidence | Use here |
|---|---|---|
| Purchase motivations | Hamari et al. 2017, *Computers in Human Behavior* 68:538-546, N=519, doi:10.1016/j.chb.2016.11.045. "Unobstructed play, social interaction, and economical rationale" were positively associated with spend | Social features and good-value bundles |
| Functional, hedonic and social value ("prestige of owning a rare item") | Lehdonvirta 2009, *Electronic Commerce Research* 9(1):97-113 | Sell hedonic and social value; keep functional value (gadgets) earned |
| Paid randomness carries harm risk | Zendle & Cairns 2018, *PLOS ONE*, N=7,422: loot box spend is linked to problem-gambling severity, η²=0.054 vs 0.004 for other microtransactions (correlational) | Never sell rolls or luck for Robux |
| Paying can lower status | Evers, van de Ven & Weeda 2024, *Int. J. Internet Science* 10(1) (abstract only): microtransaction users are seen as lower in skill and status | Top status markers stay earned-only; bought cosmetics decorate earned status |
| Decoy / attraction effect | Huber, Payne & Puto 1982, *JCR* 9(1):90-98. Weak in later replications (Frederick, Lee & Baskin 2014; Yang & Lynn 2014, *JMR*) | A big top pack is a cheap anchor; expect little from it |
| Gifting goes with spend | Secondary summary only; primary paper not found, so weak | Gifting is already built; give it a public moment, but do not count on it for revenue |

## 4. The design

### 4.1 Compliance (about 2.5 days, blocks every product)
1. **Receipt handler:** idempotent (store receipt ids in the profile), credits gems without touching `gemsEarned`, and pays the gift target from `ShopService.giftTargetOf`.
2. **Policy gate:** check on join inside `pcall` and treat a failure as restricted. Restricted players see **"Pick a gadget"** instead of Roll: a fixed-price direct buy near expected-value parity (for example Common 600, Uncommon 1,200, Rare 2,500, Epic 5,000, Mythic 12,000 gems).
3. **Odds on the roll screen:** show each gadget's `Items.rarityChance` as a percentage, rounded so the column sums to 100%.
4. **Questionnaire:** answer *yes* to randomized rewards; keep casino imagery out.

### 4.2 What to sell (nothing changes power in a race)
| Item | Type | Price | Basis | Risk |
|---|---|---|---|---|
| Gem packs: existing three plus 499 R$ for 15,000 and 1,499 R$ for 50,000 | Dev product | 49–1,499 R$ | Spending tail (RDC distribution); weak anchor | Medium (gems reach rolls), mitigated by §4.1 |
| **VIP Runner**: gold nametag, VIP lobby stand, +1 daily-shop slot | Pass | 299 R$ | Social value (Lehdonvirta) | Low |
| **Jungle Pass**: 6–8 week season, 50 tiers; premium track refunds about 70–100% in gems; season-only trails and titles | Pass per season | about 499 R$ | Economic rationale (Hamari) | Low (no random items) |
| Tier skip | Dev product | 49 R$ | Convenience | Low |
| **Champion statue look** (material and pose), sold only to current top-10 holders | Dev product | 99–199 R$ | Earned status, then decorated (Evers) | Low |
| **Jungle Club** monthly: daily gems plus one exclusive cosmetic a month | Robux subscription | for example 449 R$ a month | Gate on `IsEligibleToPurchaseSubscription`; 70% payout | Low. Add after D30 retention is proven. |

Never sold: rolls, luck, gadgets, revives, mid-run boosts.

### 4.3 Status signals
- **Run:** trail, title on the nametag, a finish emote everyone sees, top-3 podium shot.
- **Lobby:** statues wear the champion's equipped trail, title and pose, plus a Season N plaque.
- **Boards:** fix `gemsEarned` so every board measures play.

### 4.4 Friends and rivalry
- Show the friend boost in the HUD.
- Add party join through reserved servers.
- After a run, show "beat <friend> by N m".
- Add a friends-only board.
- Allow gifting a Jungle Pass (reuse `GiftTarget`).

### 4.5 Trading: no
Trading needs `IsPaidItemTradingAllowed` gating per player, invites scams, and Roblox "don't support or facilitate cash convertible rewards". Gifting covers the social benefit.

## 5. Do NOT
- Turn on products before §4.1 is done.
- Sell rolls or luck for Robux, use slot-machine visuals, or put countdowns on rolls.
- Hard-code Robux prices.
- Let purchases appear on any leaderboard.

## 6. Order of work
1. §4.1.
2. VIP pass + statue looks (2–3 days).
3. Jungle Pass Season 1 (1–2 weeks).
4. Party, rival callouts and friends board (3–5 days).
5. Subscription, once retention is known.
6. Price testing, at 60k transactions a month.

## Sources
- [A] https://create.roblox.com/docs/production/monetization/paid-random-items
- [A] https://create.roblox.com/docs/reference/engine/classes/PolicyService.md
- [A] https://create.roblox.com/docs/production/monetization/subscriptions
- [A] https://create.roblox.com/docs/production/monetization/price-optimization
- [A] https://create.roblox.com/docs/production/promotion/experience-guidelines
- [A] https://about.roblox.com/newsroom/2025/09/roblox-rdc-2025 ; https://gameworldobserver.com/2025/09/08/how-much-top-developers-earn-in-roblox-official-data
- [A] https://about.roblox.com/newsroom/2026/04/roblox-fuels-high-fidelity-games-over-18-players-increases-qualifying-devex-rate-42
- [A via press] https://www.pocketgamer.biz/roblox-revenue-up-36-yy-as-grow-a-garden-and-steal-a-brainrot-drive-multiple-milestones/
- [C] https://www.pcgamesn.com/roblox/highest-revenue-jan-2026 ; https://www.calcalistech.com/ctechnews/article/dj4lxef8r
- [B] Hamari et al. 2017 doi:10.1016/j.chb.2016.11.045 ; Lehdonvirta 2009 ECR 9(1) ; Zendle & Cairns 2018 doi:10.1371/journal.pone.0206767 ; Huber, Payne & Puto 1982 JCR 9(1) ; Frederick, Lee & Baskin 2014 JMR ; Evers, van de Ven & Weeda 2024 IJIS 10(1)
