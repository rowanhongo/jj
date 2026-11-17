# Live-ops notes

## Fill servers before opening new ones

Roblox's matchmaker, not game code, decides which server a joining player lands in. Ours sets
no rules yet. These are the settings to change before inviting testers:

1. **Creator Hub > the experience > Places > the start place > Server Fill**: choose
   **"Maximum"**. Roblox then fills every server to its max before starting a new one.
   - The default, "Roblox optimized", keeps slots free for friends to join.
   - With "Customize", you can set how many slots to keep free; use 1 if you want to keep a few.
2. **Creator Hub > Matchmaking** (custom matchmaking configuration): raise the weight of the
   **Occupancy** signal, which favours fuller servers.
   - Keep **Latency** in, so players in the same region still group together.
   - Regions always matter: a player far away still gets a nearer, emptier server.
3. **Max players per server**: keep it close to `Config.FieldSize` (8), with a little headroom,
   e.g. 10–12. Small servers fill fast and every run has real players; bots top up the rest.
4. Optional, later: a "Join a busy server" button in the lobby. It would use `MessagingService`
   to find the server with the most players and `TeleportService:TeleportAsync` to move the
   player there. Only worth it once player counts are real.

## Analytics: onboarding funnel (done, `src/server/Funnel.luau`)

Logged with `AnalyticsService:LogOnboardingFunnelStepEvent`, once per player per server:

| Step | Name | When |
|---|---|---|
| 1 | Joined | player joins |
| 2 | Pressed Play | first time they queue (button or pad) |
| 3 | First run started | their first RUN! |
| 4 | Reached 100 m | first time past 100 m |
| 5 | First run ended | first time caught or fall |
| 6 | Second run started | they came back for another run |
| 7 | Reached 500 m | first time past 500 m |

- **Where to see it:** Creator Hub > Analytics > Funnels. It starts filling once the published game is
  played; Studio sessions don't count.
- **Changing steps:** never renumber or reorder them. Add new ones at the end.
- **Still to do:**
  - An **economy** funnel: `LogEconomyEvent` for gems earned and spent.
  - **Custom events** with `LogCustomEvent`, e.g. which gadget was used and how each run ended.

## To do: tutorial

Needs a pass before testers. It must show at least:
- steering and turning at corners
- jump, and slide under logs and saws
- zipline: jump to the next cable before the glowing red cut end
- juice: grab cans or you slow down
- the position bonus for places 1 to 3

A new player's first run is already easier (no ziplines or planks, half the hard obstacles) and
at night (`RoundService.prebuild`, `PathService.pickKind`, workspace attribute `EasyRun`).
