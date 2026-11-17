"""Monte Carlo check of the 02-build-out-depth.md economy.

Run: python -I 02_economy_sim.py
Inputs mirror src/shared/Config.luau (GoalBuckets, GemsPerMetre, FinishGems, CampGems)
and src/shared/Items.luau (RollPrice, RarityWeight). Player behaviour numbers are assumptions.
"""
import random
import statistics as st

random.seed(7)

GOAL_BUCKETS = [(0.55, 1000, 1300), (0.33, 1300, 1700), (0.12, 1700, 2200)]
# Player types: runs per day, chance to reach the goal, vat check-ins per day, days played per week
TYPES = {
    "casual (kid, 20 min/day)": dict(runs=5, finish=0.35, checkins=1, days=4),
    "regular (1 h/day)": dict(runs=15, finish=0.55, checkins=2, days=6),
    "grinder (3 h/day)": dict(runs=40, finish=0.75, checkins=4, days=7),
}
BOXES_PER_RUN = 5  # ? boxes picked up per full run (assumption, check in RoundService telemetry)
LOADOUT = 3

# Level costs: (drops, shards). Shards = earned by USING that gadget in a run (1 per use),
# replacing the original "duplicates" cost (see the report, section 2).
LEVELS = {2: (20, 3), 3: (40, 6), 4: (80, 10), 5: (150, 15), 6: (250, 25),
          7: (400, 35), 8: (600, 50), 9: (900, 70), 10: (1400, 100)}
VAT_COST, VAT_HOURS, VAT_SLOTS = 60, 4, 2
MUTS = [("Juicy", 40), ("Bouncy", 25), ("Shiny", 18), ("Frosty", 10), ("Golden", 5),
        ("Rainbow", 1.8), ("Cosmic", 0.2)]
PITY_GOLDEN = 25


def goal():
    r, acc = random.random(), 0
    for p, lo, hi in GOAL_BUCKETS:
        acc += p
        if r <= acc:
            return random.randrange(lo, hi + 1, 50)
    return 1200


def one_run(finish_p):
    g = goal()
    fin = random.random() < finish_p
    dist = g if fin else int(g * random.uniform(0.25, 0.95))
    gems = dist / 250 + (5 if fin else 0) + 2 * (dist // 500) + random.randint(4, 14)
    drops = dist // 50 + (5 if fin else 0) + random.randint(0, 4)
    boxes = max(1, round(BOXES_PER_RUN * dist / g))
    return dist, gems, drops, boxes


def roll_mut(pity):
    if pity + 1 >= PITY_GOLDEN:
        pool = [m for m in MUTS if m[0] in ("Golden", "Rainbow", "Cosmic")]
    else:
        pool = MUTS
    tot = sum(w for _, w in pool)
    r = random.uniform(0, tot)
    for name, w in pool:
        r -= w
        if r <= 0:
            return name
    return pool[-1][0]


def simulate(t, days=120):
    drops = gems = 0
    lvl = [1] * LOADOUT
    shards = [0] * LOADOUT
    pity = 0
    brews = 0
    first = {}
    day_runs_total = 0
    for day in range(1, days + 1):
        if random.random() > t["days"] / 7:
            continue
        for _ in range(t["runs"]):
            _, g, d, b = one_run(t["finish"])
            gems += g
            drops += d
            day_runs_total += 1
            for _ in range(b):
                shards[random.randrange(LOADOUT)] += 1
            # spend: level the lowest gadget first
            while True:
                i = min(range(LOADOUT), key=lambda k: lvl[k])
                if lvl[i] >= 10:
                    break
                cd, cs = LEVELS[lvl[i] + 1]
                # keep a vat reserve once a Lv5 exists
                reserve = VAT_COST * VAT_SLOTS if max(lvl) >= 5 else 0
                if drops - reserve >= cd and shards[i] >= cs:
                    drops -= cd
                    shards[i] -= cs
                    lvl[i] += 1
                    for L in (5, 10):
                        if lvl[i] == L and f"Lv{L}" not in first:
                            first[f"Lv{L}"] = (day, day_runs_total)
                else:
                    break
            if min(lvl) >= 10 and "AllLoadoutLv10" not in first:
                first["AllLoadoutLv10"] = (day, day_runs_total)
        if gems >= 1000 and "firstRoll" not in first:
            first["firstRoll"] = (day, day_runs_total)
        # vat: each check-in collects/starts brews; a brew needs >= 4 h so at most
        # min(checkins, 24/4) cycles per slot per day, one per check-in.
        if max(lvl) >= 5:
            for _ in range(min(t["checkins"], 24 // VAT_HOURS)):
                for _ in range(VAT_SLOTS):
                    if drops < VAT_COST:
                        break
                    drops -= VAT_COST
                    brews += 1
                    m = roll_mut(pity)
                    pity = 0 if m in ("Golden", "Rainbow", "Cosmic") else pity + 1
                    if "firstMutation" not in first:
                        first["firstMutation"] = (day, day_runs_total)
                    if m == "Golden" and "firstGolden" not in first:
                        first["firstGolden"] = (day, day_runs_total)
                    if m == "Cosmic" and "firstCosmic" not in first:
                        first["firstCosmic"] = (day, day_runs_total)
    return first, gems, day_runs_total


def main():
    keys = ["Lv5", "firstMutation", "firstGolden", "firstRoll", "Lv10", "AllLoadoutLv10", "firstCosmic"]
    for name, t in TYPES.items():
        res = [simulate(t) for _ in range(400)]
        print(f"\n== {name}: {t['runs']} runs/day, finish {t['finish']:.0%}, {t['checkins']} vat check-ins/day")
        print(f"   gems/run ~ {st.mean(r[1] / max(1, r[2]) for r in res):.1f}")
        for k in keys:
            days = [r[0][k][0] for r in res if k in r[0]]
            runs = [r[0][k][1] for r in res if k in r[0]]
            if days:
                print(f"   {k:15s} median day {st.median(days):6.0f}  (runs {st.median(runs):6.0f})  "
                      f"reached in 120 d: {len(days) / len(res):.0%}")
            else:
                print(f"   {k:15s} not reached in 120 days")


if __name__ == "__main__":
    main()
