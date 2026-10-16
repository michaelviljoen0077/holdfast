# Holdfast

A diorama real-time tactics game: defend a procedurally generated island
village from waves of raiders arriving by longboat. Built in Godot 4.7
(Forward+). Everything — terrain, props, units, effects and audio — is
generated in code; there are no imported assets yet.

## Running

Double-click `run.bat`, or open the folder in Godot 4.7.2 and press F5.

## How to play

**New Campaign** sails a warband across a sea chart of six islands, ending at
the Drowned Jarl's fleet. Two kinds of island:

- **Defend** a village while raiders land in waves. Every house you save pays
  gold. Burn beached longboats before they row home for a bounty.
- **Assault** a raider camp (flame icon): burn every longhouse, topple the
  bowman-manned watchtowers, and break the captive pens — freed thralls join
  your warband for good.

After each won island, choose one of three **boons** (13 in the pool), so
every run builds a different warband. In the war camp spend gold to teach
abilities, train squads to three stars, recruit, buy timber or veteran
recruits. A squad wiped out in battle is gone for good.

Islands roll **weather** (clear, golden hour, overcast, storm, moonlit night)
and often a **trait** (Timberland, Prosperous, Haunted Shore, Old Ruins,
Veteran Raiders, Fair Winds). Storms shorten bowshots and slow fires; at night
longboats are only spotted when nearly ashore.

| Squad | Strength | Ability (F) |
| --- | --- | --- |
| Shieldwall | Blocks most frontal blows and missiles | **Brace**: an unbreakable front; attackers are thrown back |
| Swordsmen | Heavy two-handed hits, wreck structures | **Charge**: sprint to a point, bowling enemies over |
| Crossbows | Ranged; reach further from high ground | **Volley**: every crossbow fires at a target area |
| Rune-priests | Slowly heal nearby allies; rune bolts at range | **Firestorm**: a rain of fire on a target area that also burns enemy timber |
| Freed Thralls | Quick dual-knife fighters | — |

**Formations (G)**: Block (default), Line (wide front), Wedge (charges hit
twice as hard, a little faster) and Ring (shields face every way, slow).
Fighting downhill hits harder.

**Fortify (B)**: hold the left mouse button and drag to draw a palisade along
the ground; release to build. The ghost shows real stakes, the timber cost and
why any part won't fit. Each wall you draw gets a gate in the middle that your
soldiers walk through; raiders must hack through or go around. Right-click a
wall in build mode to tear it down (full refund before the first wave, half
after). While longboats sail in, red dotted lines show the route each crew
will march, so you can see where a wall matters.

**Militia (M)**: once per battle the village takes up arms — more houses
standing, more militia.

**Refit**: a squad resting at an intact house door replaces its fallen.

**Fire**: Torchbearer raiders hurl torches at houses and palisades. A burning
house slowly burns down unless soldiers stand at its door and beat the flames
out.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a squad (time slows while a squad is selected) |
| Right click | Move the selected squad; drag to set the facing it takes on arrival |
| Right click a structure | Attack an enemy longboat, longhouse, watchtower or pen |
| 1 – 5 | Select squad by number |
| F (or Space) | Squad ability; Charge and Volley then need a ground click |
| G | Cycle the selected squad's formation |
| B | Build mode: drag to draw palisades, right-click a wall to remove it, Esc to leave |
| M | Call the militia |
| T, then left click | Topple the tower in the clicked direction (crushes friend and foe) |
| WASD / middle-drag | Pan |
| Q / E / right-drag (nothing selected) | Orbit |
| Mouse wheel | Zoom |
| Enter | After a campaign battle, return to the sea chart |
| Esc | Cancel the current order, otherwise open the pause menu |
| R / N | Quick battle: replay / new island |
| F12 | Screenshot to `shots/` |

## Layout

- `scripts/world/` — island heightfield, terrain mesh, ramp carving, navigation grid, scatter, procedural props
- `scripts/gameplay/` — battle simulation, squads, units, raid director, player commands, destructible tower
- `scripts/core/` — camera rig, procedural audio, texture helpers, capture tooling
- `shaders/` — terrain, water, grass, props, banner

## Automated captures

`./shoot.sh <name> [--cam=wide|close|top|follow|custom] [--seed=N] [--frames=N] [--speed=N] [--autoplay]`
renders a screenshot to `shots/<name>.png` without stealing keyboard input.

## Credits

- Characters: KayKit Adventurers and KayKit Skeletons by Kay Lousberg (CC0)
- Sound effects and stingers: Kenney Impact Sounds, RPG Audio and Music Jingles (CC0)
- Fonts: Cinzel and Alegreya Sans (SIL Open Font License)
- Music: composed and rendered in code by `tools/compose_music.py`
- Everything else (terrain, props, water, effects, ambience) is generated in code.

## Regenerating the music

`python tools/compose_music.py` re-renders `assets/audio/music/calm.wav` and
`battle.wav` (needs numpy, scipy and soundfile).
