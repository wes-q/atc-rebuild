# ATC Raycrash in Godot

Private recreation of ATC Raycrash (CodiNET, 2005) using its own rules and art. Godot 4.7.

## Run it

```
brew install --cask godot        # 4.7.2
brew install assimp              # 6.0.5, only for converting art
python3 -I godot/tools/convert_original.py "RaycrashArchive/extracted/source/ATC BIN/bin/data" godot/assets/original
python3 -I godot/tools/extract_db.py RaycrashArchive/extracted/database/raycrash1 godot/assets/original/data
godot --path godot               # play
godot --path godot -e            # open in the editor
godot --headless --path godot -s tests/test_mech_sim.gd   # logic tests
```

The converted art and data in `assets/original/` are CodiNET's and are git-ignored. Rebuild them
with the two tools whenever they are missing. The database extractor exports only game-data
tables (robots, weapons, parts, shop catalogue) and never player, clan, log or billing tables.

Record a scripted demo: `godot --path godot --write-movie out.avi --fixed-fps 30 --quit-after 300 -- autopilot`

## Two players

Start the game on two computers on the same network. One chooses **Host a match**, the
other types the host's address into the box and chooses **Join**. The host's screen shows
its address. You can skip the menu from the command line:

```
godot --path godot -- host                  # player 1, listens on port 7777
godot --path godot -- join 192.168.1.20     # player 2, the host's address
godot --path godot -- practice              # alone, against a target dummy
```

- macOS may ask whether Godot can accept incoming connections the first time you host.
  Allow it, or player 2 cannot connect.
- Two windows on one computer also connect, but only the window in front gets the keyboard
  and mouse, so two people cannot play at once that way. It is useful for testing.
- Player 1 is the Zeid's default blue and white. Player 2 uses its second original colour
  scheme, dark grey and violet.
- Esc leaves the match and returns to the menu.

How it works, following the original client: each player runs their own mech and sends its
state 60 times a second. Shots go out as events, so both screens show every bullet. The
player who is hit decides the damage (the SR-3's database setting), then reports it to
everyone. Remote mechs glide toward their reported position the way the original eased toward
`lastRealPos`.

## Match rules (from the original server and client)

- Free-for-all, last mech standing (`GameRoom::is_game_end`, mode 0). No respawns.
- HP is the body's armour points (700 for the Zeid). Each hit plays one of the two hit
  reactions unless the mech is mid-attack.
- At 0 HP the mech stops and takes no input, and 0.1 s later it explodes into the original
  debris model and is no longer drawn (`rcPlayer::update_dead`).
- Under 10% HP, small explosions spark off the mech, more often as HP drops.
- The match ends the moment one mech is left. The clock counts up from zero; there is no
  time limit.
- Results show kills, damage dealt and points (damage / 10 x 0.825, the server's formula at
  equal grades), plus rounds won this session.
- The next round starts automatically 6 seconds after the results. This part is the
  recreation's own: the original sent players back to a room lobby.

## Arenas (from `test_map.lua`, `rcmap.cpp` and the server)

Pick the arena in the menu, or add `map=<id>` after `--`. The host's choice goes to player 2.

| Map | id | Bounds (x, y) | Walls on the play plane |
|---|---|---|---|
| Space | `space` | -1215..1225, -1303..1242 | asteroids, containers, wreckage |
| City | `city` | -1088..1145, -170..853 | the few rooftops and signs that reach the plane |
| Sky | `sky` | -1220..1230, -1300..1240 | none |
| G-Session | `gsession` | -730..650, -630..685 | none |
| Deep Escape | `escape` | -1215..1225, -1303..1242 | hull edges |

- Each map's model is scaled by 0.3 (`HAHA_SCALE_VAL`), with its own sky and the light values
  its Lua table sets. An `o:name` frame places `name.x` from the same folder.
- Frame name prefixes set how a part draws: `(f)` alpha blend, `(a)` additive, `(c0)` no
  culling, `(z0)` / `(z1)` / `(z2)` depth write and test off, `(b0)` billboard.
- Walls are built the way `rc_map` built its collision model: every frame except `o:` and
  `(` frames whose bounding sphere reaches the play plane, keeping only faces steeper than
  `|n.y| < 0.8`. The map's animation pose at time 0 is used, because the engine kept the
  animation controller running and its keys override the frames' own scale.
- Touching a wall pushes the mech 11 units straight out. Leaving the rectangle puts it back
  on the edge and bounces it 66.3 units along the reflection, with the original `wall_crash`
  effect. Either way it glides there 10% per frame and ignores movement keys until within 40
  units, then walks on if a key is held (`start_dash`, `end_dash`).
- As in the original, only your own mech is collision-checked on your machine. The other
  player's position comes from their machine.
- Bullets stop at the first wall they cross.
- Start points are the server's: twelve around a circle (radius 1000, 600 for G-Session)
  or the City table, picked at random without repeats each round (`position_set`).

Test options, added after `--`: `netlog` prints positions once a second, `hp=60` starts every
mech with 60 HP for quick knockouts, `capture=<dir>` saves 30 JPEG frames a second.

## Controls (as in the original)

| Input | Action |
|---|---|
| WASD or arrows | Move along the screen axes |
| Mouse | Aim. The mech turns toward the cursor at its turn rate |
| Left click | Fire the SR-3: 3-round burst, then the reload |
| Right click (hold) | Boost, draining the gauge |
| + / - | Camera depth. Otherwise it follows the nearest enemy automatically |
| Esc | Leave the match |

## How the original plays (read from its source)

- Top-down, not side view. Mechs move on the X/Z plane, and the camera sits on the plane's
  normal looking straight at it (`View_Manager.cpp`).
- Each mech is rotated about the camera axis to face the mouse and also rolled by up to
  180 degrees as it turns, so it always shows an upright side profile, mirrored when facing
  left (`rcManager.cpp`, rotation table). This is why it "looked 3D but played 2D".
- Battle camera depth is 3x the distance to the nearest enemy, clamped to 235..500
  (`world.cpp`, `option.ini` camera_value), field of view 45 degrees.
- Releasing all keys stops dead. Holding right click starts a boost at boost speed + 70.
  An empty gauge drops back to walking. At or below the low line (330 for the Zeid) a boost cannot start and the
  gauge recovers at half rate.

## Numbers in use (Zeid with SR-3)

From the original database (`RobotInfo` id 1, `WeaponInfo` id 3), converted the way the
server packed them and the client unpacked them. `scripts/game_data.gd` does the conversion.

| | Database | In game |
|---|---|---|
| Walk speed | 330 | 108 units/s |
| Boost speed | 570 | 188 units/s, starts at 258 |
| Boost acceleration | 150 | 2.475 per 0.1 s tick, growing each tick |
| Boost cap | 1150 | 363 units/s |
| Gauge | 1900, drain 140, recovery 110, low line 330 | same, per second |
| Turn rate | 320 | 320 deg/s |
| Armour points | 700 | 700 |
| SR-3 | 3 shots, 100 ms apart, speed 1600, life 700, reload 1200, damage 12 | 3 shots 0.1 s apart, 528 units/s, 0.7 s, 1.2 s reload after the 0.5 s fire animation, 12 damage |

Armour and MCS rows are not applied: the original server never sent them, only purchased
parts added to the base stats.

## Known gaps

- One `WeaponInfo` column could not be named from the backup's metadata. The server's own query
  identifies it as `continuous_time`, the gap between shots.
- The fire animation length (0.5 s) comes from the converted clip; the original playback rate
  of `.x` animations is assumed to match.
- Booster flames are placeholder particles. The original uses particle scripts in
  `data/script/particle`.
- SR-3 mode 2 (7-shot spray) is defined but not wired. How the original switches modes is not
  traced yet.
- The rifle's own animation, sounds and the original HUD art are not in yet.
- City's sky uses `mount01.png`, which is not in the archive, so that part draws untextured.
- Starting facing is toward the arena centre. The original's start direction is not in the
  source we have (inferred).
- The original's bullet wall test cast its ray backward from the previous position, so it
  noticed a wall a frame late. Here the bullet stops on the frame it crosses.
- When a mech touches several wall faces at once, the push uses the nearest one. The
  original used whichever its collision library reported first.
- Light strengths are matched by eye; Direct3D's fixed-function lighting has no exact
  Godot equivalent.
- The hit effect's scale and growth are inferred.
- Team mode, more than two players, NPCs, money and grades are not in yet.
- The character explosion's particles are a stand-in; the original defines them in script.
- No lag compensation. Fine on a home network, untested over the internet.

## Layout

```
project.godot
scenes/main.tscn
scripts/original.gd      constants and coordinate mapping, with sources
scripts/game_data.gd     loads the database export and applies the original conversions
scripts/mech_sim.gd      movement, boost gauge, facing, rifle: pure logic, tested
scripts/mech_view.gd     model, retargeted animations, rifle, the original rotation table
scripts/bullet.gd        SR-3 rounds
scripts/game.gd          modes, networking, rounds, hits, camera, target dummy, autopilot
scripts/battle_world.gd  scenery and effects: arena, sky, lights, booster flames, hits, wall crash, explosion
scripts/battle_map.gd    an arena's bounds, start points, lights and the edge bounce
scripts/map_collision.gd wall triangles on a plane grid: sphere and segment tests
scripts/start_menu.gd    practice, host and join menu
scripts/hud.gd           placeholder readouts
tools/convert_original.py   .x to glTF converter (reads the archive, writes assets/original)
tools/extract_db.py         reads game tables straight out of the SQL Server 2000 backup
tools/inspect_import.gd     prints an imported model's tree and clips
tools/render_poses.gd       renders the mech at several facings
tools/render_map.gd         renders an arena from above with its walls, bounds and start points
tests/test_mech_sim.gd      67 checks against the original database values and rules
```
