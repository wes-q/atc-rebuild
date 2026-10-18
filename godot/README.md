# ATC Raycrash in Godot

Private recreation of ATC Raycrash (CodiNET, 2005) using its own rules and art. Godot 4.7.

## Run it

```
brew install --cask godot        # 4.7.2
brew install assimp              # 6.0.5, only for converting art
brew install ffmpeg              # optional: cleans the original sound files' tags
python3 -I godot/tools/convert_original.py "RaycrashArchive/extracted/source/ATC BIN/bin/data" godot/assets/original
python3 -I godot/tools/extract_db.py RaycrashArchive/extracted/database/raycrash1 godot/assets/original/data
python3 -I godot/tools/extract_ui.py "RaycrashArchive/extracted/source/ATC BIN/bin/data" godot/assets/original
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

## HUD (from `page_game_fight.lua`, the `res/game_fight_*.lua` window tables and `radar.cpp`)

The battle HUD is the original's art and layout. `tools/extract_ui.py` reads the Lua window
tables as data (it never runs them) and `scripts/original_ui.gd` rebuilds the engine's
windows from them: a position, a size and a switchable texture list, drawn the way
`Window::draw_self` drew them. The original's screen was 800x600; the HUD is laid out on
that and scaled to the window.

- Top left: robot face, name, level and HP as four big digits (`ON_self_user_state_wnd`).
- Left edge: the boost gauge, a 391-pixel bar with the low line marked and the readout
  riding the gauge's top; below the low line the readout hides and the marker flickers
  (`OnBoosterUpdate`).
- Top centre: the clock (`OnTimeUpdate`), including the script's quirk where the tens of
  hundredths wrap at 6.
- Bottom left: the weapon panel with the SR-3 art, the recharge ring stepping through 16
  images as it reloads, the four weapon slots, and `0000 / 0000` ammo, since the SR-3 has
  no ammo limit.
- Right: for 2 seconds after each hit you land, the target's face, name and energy bar
  (`ON_user_state_wnd`).
- Radar (top right): dots at 0.08 scale within 1000 x 750 units. Every free-for-all player
  is team 0, so every dot uses the same "ours" image, as in the original.
- Off-screen players: a marker on a 180-pixel ring round the screen centre, the nearest
  one with the brighter image. Names float over mechs on screen, in team 0 green.
- Under 10% HP, the SPAttack warning pulses under your mech.
- HIT! when your shot lands and DAMAGE! when you are hit, the original particle scripts'
  textures, 100 units up the screen from your own mech (`World::process_damage`).

## Sound (from `NubAudiere.cpp`, `BGM.cpp` and the weapon scripts)

- Each shot plays `gunfire1`, a hit plays `gun_Hit` at the mech hit, a boost start plays
  `sp_booster`, bouncing off the arena edge plays `special_fire`, a knockout plays
  `bomb-complete`.
- Volume and pan are set once when a sound starts. The listener is over the camera but 300
  units off the plane, so a sound right below plays at 0.625 and fades out linearly by about
  740 units away. Pan is the sideways offset x 0.005 with a 50-unit dead zone.
- Each round starts a random track from the first 19 of the original play list; the winner
  hears `victory`, everyone else `defeat`. Two list entries point at a folder that does not
  exist, so about one round in ten is silent, as it was.
- Add `mute` after `--` to start silent.

Test options, added after `--`: `netlog` prints positions once a second, `hp=60` starts every
mech with 60 HP for quick knockouts, `capture=<dir>` saves 30 JPEG frames a second (run the
window with `--max-fps 60`, or it runs unthrottled). `--write-movie` records sound as well.

## Controls (as in the original)

| Input | Action |
|---|---|
| WASD or arrows | Move along the screen axes |
| Mouse | Aim. The mech turns toward the cursor at its turn rate |
| Left click | Fire the SR-3: 3-round burst, then the reload |
| Right click (hold) | Boost, draining the gauge |
| + / - | Camera depth. Otherwise it follows the nearest enemy automatically |
| M | Sound and music on or off (this recreation's own) |
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
- Booster flames and the knockout burst are placeholder particles. Only the single-quad case
  of the original particle engine (`psys.cpp`) is ported, for HIT! and DAMAGE!.
- SR-3 mode 2 (7-shot spray) is defined but not wired. How the original switches modes is not
  traced yet.
- The rifle's own animation is not in yet.
- Within one draw order the original drew sibling windows in Lua's hash order, which is
  not recoverable. Text windows are drawn last so names stay readable (inferred).
- The results screen is this recreation's own panel, not the original's result page.
- The original drew HUD text with its own bitmap font; Godot's default font stands in.
- The weapon change sound (`gun_start`) is copied but unused, since weapons do not switch yet.
- City's sky uses `mount01.png`, which is not in the archive, so that part draws untextured.
- Starting facing is toward the arena centre. The original's start direction is not in the
  source we have (inferred).
- The original's bullet wall test cast its ray backward from the previous position, so it
  noticed a wall a frame late. Here the bullet stops on the frame it crosses.
- When a mech touches several wall faces at once, the push uses the nearest one. The
  original used whichever its collision library reported first.
- Light strengths are matched by eye; Direct3D's fixed-function lighting has no exact
  Godot equivalent.
- The bullet impact flash's scale and growth are inferred.
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
scripts/hud.gd           the original battle HUD: dialogs, radar, markers, name tags
scripts/original_ui.gd   the engine's UI windows, built from the exported Lua tables
scripts/game_sound.gd    positioned sound effects and the BGM play list
scripts/particle_quad.gd one layer of an original particle script (single-quad case)
tools/convert_original.py   .x to glTF converter (reads the archive, writes assets/original)
tools/extract_db.py         reads game tables straight out of the SQL Server 2000 backup
tools/inspect_import.gd     prints an imported model's tree and clips
tools/render_poses.gd       renders the mech at several facings
tools/render_map.gd         renders an arena from above with its walls, bounds and start points
tools/extract_ui.py         reads the HUD window tables and particle scripts, copies their art
tests/test_mech_sim.gd      76 checks against the original database values and rules
```
