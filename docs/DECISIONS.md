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
