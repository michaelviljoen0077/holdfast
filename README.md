# TGN (working title)

A diorama real-time tactics game: defend a procedurally generated island
village from waves of raiders arriving by longboat. Built in Godot 4.7
(Forward+). Everything — terrain, props, units, effects and audio — is
generated in code; there are no imported assets yet.

## Running

Double-click `run.bat`, or open the folder in Godot 4.7.2 and press F5.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a squad (time slows while a squad is selected) |
| Right click | Move the selected squad (path preview follows the cursor) |
| 1 – 3 | Select squad by number |
| T, then left click | Topple the tower in the clicked direction (crushes anyone underneath, friend or foe) |
| WASD / middle-drag | Pan |
| Q / E / right-drag | Orbit |
| Mouse wheel | Zoom |
| R / N | Replay this island / generate a new island |
| F12 | Screenshot to `shots/` |

## Layout

- `scripts/world/` — island heightfield, terrain mesh, ramp carving, navigation grid, scatter, procedural props
- `scripts/gameplay/` — battle simulation, squads, units, raid director, player commands, destructible tower
- `scripts/core/` — camera rig, procedural audio, texture helpers, capture tooling
- `shaders/` — terrain, water, grass, props, banner

## Automated captures

`./shoot.sh <name> [--cam=wide|close|top|follow|custom] [--seed=N] [--frames=N] [--speed=N] [--autoplay]`
renders a screenshot to `shots/<name>.png` without stealing keyboard input.
