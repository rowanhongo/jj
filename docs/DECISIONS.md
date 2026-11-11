# Jungle Juice decisions

## D1: Core loop (2026-11-11)
Endless forward runner for up to 8 players. The character runs forward on its own, with no lanes:
- **Steering:** the stick or A/D steers freely within the path.
- **Jump:** Space, W or Up.
- **Slide:** S, Down or C (on mobile, the Slide button).
- **Turns:** steer toward a corner inside it to turn 90°. Missing the corner forces the turn and stumbles you.
- **Stumbles:** clipping a hurdle or a log, or steering into a wall. Each stumble slows you briefly.
- **Gaps:** falling into one means you're out.
- **Pace line:** the Guardian rides it. Falling behind it catches you.
- **Jungle Juice:** drains constantly and bottles refill it. When it's empty you stumble every 2.5 s.
- **Blowdart (F or the Dart button):** auto-targets the runner nearest your camera's aim. A hit drains their juice and slows them.
- **Shields:** a player attribute that absorbs a stumble. This is the hook for future purchases.
- **Camera:** the default Roblox camera, untouched.

## D2: Endless path
- **Generation:** a server-side, seeded chain of pieces (`src/server/Segments.luau`, `PathService.luau`). The server keeps 520 studs built past the leader and deletes pieces 160 studs behind the Guardian.
- **Turns:** limited to ±90° of the start heading, so the path can never cross itself.
- **Decor:** a new piece clears older decor out of its corridor, and decor is never placed over floors or walls.
- **Hiding flatness** (DevForum research): grass banks below path level, clumped near cliffs with ragged heights, far cliffs faded by the atmosphere, and a sea plane that follows the Guardian. Stairs pieces change the elevation.
- **Greybox pieces:** start, straight, hurdle, duck (log), gap, rope bridge, stairs up, stairs down, turn left, turn right.

## D3: Look
- Colour bible: `docs/COLOUR_BIBLE.md`, taken from the bright jungle-temple reference.
- Lighting: midday sun with mint atmosphere haze, set in `default.project.json`.

## D4: Monetization and retention
- **Classes:** buy with gems or earn them. Gems come from runs (distance, camps, finishing last standing) and from Robux packs. Each class screen shows both "unlock with gems" and "get gems".
- **Lifetime check-ins:** never reset; each new UTC day you join counts once.
  - Every 7th check-in: 150 gems.
  - Every 14th check-in: one class of your choice, which replaces the gems that day.
- **Planned consumables:** revive, bait (stalls the Guardian), shields, juice rush.
- Cosmetics come last.

## D5: Lobby, shop, gadgets (modelled on the user's reference screenshots)
- **Lobby UI:** level/XP and gems top right; mode and next-run countdown top centre; PLAY joins the next run (press again to leave); bottom bar Shop [Z], Inventory [X], Modes [C]. During a run the screen is clear apart from the run HUD and two gadget slots [Q] [E].
- **Gadgets:** 11 in `src/shared/Items.luau`, Common to Mythic. 3 are owned by default; the rest come from Item Rolls (100 gems, or 10 for 650). Pity: Rare every 10, Epic 25, Mythic 80. Duplicates count toward mastery.
- **In a run:** gold ? boxes on about 16% of pieces give a random gadget from your loadout (up to 3) into one of 2 slots.
- **Daily Shop:** 4 cosmetics (titles, emotes, trails) for gems, the same for everyone, changing each UTC day. Gem packs are listed with Robux prices; product ids are 0 until created. Passes are shown as "Soon".
- **Overhead tag:** your title plus the chosen mode's icon and best metres (Inventory > Records picks the mode).
- **XP:** 20 + metres/2 per run. Level L needs 150 + 150L XP.
