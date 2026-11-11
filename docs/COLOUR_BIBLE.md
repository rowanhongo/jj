# Jungle Juice colour bible

Sampled from the reference: a bright jungle temple at midday. It is saturated and sunny, never gloomy.
Code source of truth: `src/shared/Palette.luau`. Use only these colours for world parts and GUI.

| Token | Hex | Use |
|---|---|---|
| CanopyBright | `#8CC63F` | sunlit leaves, tree tops, good/OK GUI |
| CanopyMid | `#4E9A2E` | bushes, mid foliage |
| CanopyDeep | `#2E5E26` | shaded leaves, under-canopy |
| Trunk | `#6B4A2B` | tree trunks, logs |
| StoneLight | `#C8D3A0` | temple stone, walls, path edging |
| StoneMoss | `#9DB27A` | mossy stone faces |
| StoneShadow | `#6E8558` | stone in shade, pillars |
| PathSand | `#E3C79A` | main path floor |
| PathTan | `#C9A36B` | path borders, stairs |
| WoodPlank | `#B5773D` | rope bridges |
| Rope | `#8A6A3E` | bridge rails |
| Water | `#3CC2C8` | rivers, pools |
| WaterDeep | `#1F8E9E` | deep water under gaps |
| Cliff | `#7E9A5E` | near cliff walls |
| CliffFar | `#A7C08A` | far cliff walls (fog carries them) |
| Sun | `#FFF1B8` | sunlight tint |
| Juice | `#FF9F1C` | juice bottles, juice bar |
| JuiceGlow | `#FFD23F` | juice highlight |
| Guardian | `#5C6B4A` | Guardian body |
| GuardianEyes | `#7CFF6B` | Guardian eyes (neon) |
| Dart | `#D94F2B` | blowdart |
| Shield | `#5CD6FF` | shield bubble |
| Gem | `#8FF3FF` | diamond gems (glass) |
| GemGlint | `#E8FDFF` | diamond inner glint (neon) |
| UiGold | `#F5B83D` | titles, highlights |
| UiRim | `#6B3A12` | title outline, stroke |
| UiPanel | `#1E3A24` | GUI panels |
| UiText | `#FFF6DC` | GUI text |
| UiDanger | `#E2483D` | Guardian warnings |
| UiGood | `#8CC63F` | positive feedback |
| UiPaper | `#F6EFD9` | shop / inventory card face |
| UiPaperDim | `#E6DDC2` | card wells, locked items |
| UiInk | `#1E2A1C` | text on paper, tab bar |
| UiBuy | `#3FD08A` | buy and PLAY buttons |
| Common | `#B9C2A3` | rarity |
| Uncommon | `#8CC63F` | rarity |
| Rare | `#5CB8FF` | rarity |
| Epic | `#B07CFF` | rarity |
| Mythic | `#FF5C7A` | rarity |

## Lighting (default.project.json)
- Midday sun: ClockTime 13.6, Brightness 3, warm `ColorShift_Top`.
- Green-tinted ambient light, so shadows read as jungle green, not grey.
- Atmosphere: haze 1.7 and density 0.34, coloured pale mint. Far cliffs fade into green mist.
- Colour correction: saturation +0.25. Bloom stays low. A light touch of sun rays.

| Tar | 2B2118 | tar pit surface (slows runners) |
| TarBubble | 4A3A2A | bubbles on the tar |
