# Holdfast

A diorama real-time tactics game: defend a procedurally generated island
village from waves of raiders arriving by longboat. Built in Godot 4.7
(Forward+). Everything — terrain, props, units, effects and audio — is
generated in code; there are no imported assets yet.

## Running

Double-click `run.bat`, or open the folder in Godot 4.7.2 and press F5.

## How to play

**New Campaign** sails a warband across a sea chart of six islands, ending at
the Jarl's fleet. On each island, raiders land in waves from longboats and try
to burn the village. Every house you save earns gold. Spend it in the war camp
between islands to teach squads their ability, train them (up to three stars),
or recruit new squads. A squad wiped out in battle is gone for good, and the
campaign ends if the whole warband falls.

**Quick Battle** drops you onto a random island with one of each squad.

| Squad | Strength | Ability (F) |
| --- | --- | --- |
| Shieldwall | Blocks most frontal blows | **Brace**: an unbreakable front for 6 s; attackers are thrown back |
| Swordsmen | Heavy two-handed hits, no block | **Charge**: sprint to a point, bowling enemies over |
| Crossbows | Ranged, fragile up close | **Volley**: every crossbow fires at a target area |

A squad that rests at an intact house door for 3 seconds refits: the fallen
are replaced and the wounded healed (25 s cooldown).

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a squad (time slows while a squad is selected) |
| Right click | Move the selected squad (path preview follows the cursor) |
| 1 � 4 | Select squad by number |
| F (or Space) | Use the selected squad's ability; Charge and Volley then need a ground click |
| T, then left click | Topple the tower in the clicked direction (crushes anyone underneath, friend or foe) |
| WASD / middle-drag | Pan |
| Q / E / right-drag | Orbit |
| Mouse wheel | Zoom |
| Enter | After a campaign battle, return to the sea chart |
| R / N / Esc | Quick battle: replay / new island / title |
| F12 | Screenshot to `shots/` |

## Layout

- `scripts/world/` — island heightfield, terrain mesh, ramp carving, navigation grid, scatter, procedural props
- `scripts/gameplay/` — battle simulation, squads, units, raid director, player commands, destructible tower
- `scripts/core/` — camera rig, procedural audio, texture helpers, capture tooling
- `shaders/` — terrain, water, grass, props, banner

## Automated captures

`./shoot.sh <name> [--cam=wide|close|top|follow|custom] [--seed=N] [--frames=N] [--speed=N] [--autoplay]`
renders a screenshot to `shots/<name>.png` without stealing keyboard input.
