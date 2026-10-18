# ATC Raycrash in Godot

Private recreation of ATC Raycrash (CodiNET, 2005) using its own rules and art. Godot 4.7.

## Run it

```
brew install --cask godot        # 4.7.2
brew install assimp              # 6.0.5, only for converting art
brew install ffmpeg              # optional: cleans the original sound files' tags
python3 -I godot/tools/extract_db.py RaycrashArchive/extracted/database/raycrash1 godot/assets/original/data
python3 -I godot/tools/extract_ui.py "RaycrashArchive/extracted/source/ATC BIN/bin/data" godot/assets/original
python3 -I godot/tools/convert_original.py "RaycrashArchive/extracted/source/ATC BIN/bin/data" godot/assets/original
godot --headless --path godot --import   # import what the converter wrote
godot --path godot               # play
godot --path godot -e            # open in the editor
godot --headless --path godot -s tests/test_mech_sim.gd   # logic tests
```

The converted art and data in `assets/original/` are CodiNET's and are git-ignored. Rebuild them
with the three tools, in that order (the converter reads the other two's output), whenever
they are missing, then run the import line. Playing does not import new models; the game
skips any it cannot load without an error, so a missed import shows up only as a missing
clip or effect. The database extractor exports only game-data
tables (robots, weapons, parts, shop catalogue) and never player, clan, log or billing tables.

Record a scripted demo: `godot --path godot --write-movie out.avi --fixed-fps 30 --quit-after 300 -- autopilot`

## Front end (Step 13, from `page_login_new.lua`, `page_charactor.lua`, `page_main_menu.lua`,
`page_main_menu_option.lua`, `main.lua` and the engine's `dialog.cpp`)

The game opens on the original's screens, in English, built from its window tables and art:

1. **Login:** the ATC Online backdrop with ID and PASS boxes, ACCESS and EXIT. The ID is
   your player name (kept between runs); the password is ignored. Then the loading screen.
2. **Character select:** your pilot panel (name, PVT, an empty record) and the body's
   pre-rendered turntable. The arrows step through the five bodies in place of a server's
   character list; ENTER goes on, EXIT shows the intro picture for 4 s and closes the game.
3. **Main menu:** MATCH, TUTORIAL, ITEM SHOP, CHANNEL, OPTION and EXIT down the left, the
   chat console in the middle (normal, whisper and clan tabs, the chat line, scrolling), the
   channel's player list and the friend and clan lists on the right.
   - MATCH opens the room list, ITEM SHOP the shop (both below). TUTORIAL starts practice.
   - CHANNEL opens the channel box, pre-filled "raycrash-"; EXIT goes back to character select.
   - The console shows your own lines and the front end's notices; there is no server to chat
     through yet.
4. **Option:** the BGM and EFFECT volume bars, the music test player (play, stop, next, with
   the track name), window mode on or off (full screen) and tooltips on or off, all kept
   between runs.

How it behaves, from the engine:
- **Buttons:** push buttons show their second image under the pointer and the third while
  held, and play `select_button` when let go. Highlight buttons draw the `selectlight` glow
  behind their label: it grows from 100 to 150 x 15 in 0.1 s with `mousein`, flashes out to
  400 x 0 in 0.2 s when pressed, and `button_click` plays when let go. Check buttons are the
  tabs. The pointer must still be on a button when let go for it to count.
- **Tooltips:** the original English texts in a box at the pointer less (50, 80), wrapped and
  top-aligned as `DrawText` did without `DT_SINGLELINE`.
- **Message boxes:** the dimmed screen, the `sys_message` panel and its OK button.
- **Cursor:** the animated pointer, frames 1-6-1 over 0.6 s on every click, hotspot (8, 11).
  The battle keeps the system pointer.
- **Music:** "Good Luck (Ver2)" from login through the menus (BGM 3).
- **Backdrop:** character select, the main menu and the options are drawn over the space
  map's sky alone, seen from 320 units up: the menus' `interface_map` loads map01's skymap
  and no objects (inferred: no screenshot of the menus survives).
- **Fonts:** the original drew text with Windows' Gulim, Verdana, Tahoma and Impact, which are
  not in the archive; the nearest system fonts stand in.
- **Android's back button** steps back through the screens: a popup, then options, the main
  menu and character select, and from login it quits.

Open a screen directly for testing: `godot --path godot -- front=character` (or `main`,
`option`, `shop`); `-- classic` opens the classic menu (practice, host, join and the loadout
in plain Godot controls, kept for testing).

## Item shop as the garage (Step 15, from `page_game_shop.lua`, `res/game_shop_background.lua`
and the item popup in `main.lua`)

ITEM SHOP opens the original shop page for the body chosen at character select, with its own
music (BGM 22):
- **The robot** stands in the middle frame over the shop's starry backdrop (the `item_shop`
  map's `ui_bg01.x` sky and light values), holding whatever weapon you last chose. Click it to
  see the weapon's attack. Hold the bottom right of the frame to turn it and the bottom left
  to zoom: the window table has those spots with no art of their own, so nothing marks them.
- **Equipped slots** along the bottom: SLOT1 to SLOT4 (sword, gun, heavy, special) and the
  shield. The body-part, skill, instant and bit slots stay empty.
- **Item list** (top right): the shop's weapons in its order, six rows at a time with the
  scroll arrows or the wheel. Another body's weapons are marked red, as the original marked
  what you could not equip; so are weapons this recreation does not play yet.
- **Inventory** (bottom right): this body's weapons that are not equipped. Choose one and
  EQUIP puts it in its slot; the weapon it replaces goes back. Choose an equipped slot and
  DISARM puts that slot's default back (a slot is never empty in battle).
- **Item popup:** pointing at a weapon shows the original's popup: its name, ITEM TYPE,
  DAMAGE, RELOAD TIME, AMMO and COST ENERGY from the database, and its description in green.
  It sits beside the pointer for the inventory and at (367, 60) for the list, as `main.lua`
  placed it.
- **Status panel:** the body's armour, energy, speeds, energy regen, overheat line,
  acceleration and top speed before and with the chosen item. No weapon changes them.
- EXIT keeps the loadout with your profile, one loadout per body, and goes back to the
  channel. Practice and every room you create or join use it.

What is left out or mapped (the shop sold for money on CodiNET's server):
- Nothing costs anything: every weapon the body can use is already in the inventory, and
  BUY, SELL, the gift and cubit recharge buttons are hidden. CUBITS and CREDITS show 0. The
  database export has sell prices but no buy prices, so the list's COST column stays blank.
- The ARMOR, FM and ETC tabs list nothing: armour parts, FM upgrades, colours and bits are not
  in yet. UPGRADE (FM) is hidden.
- The item information box in the middle is hidden, as the shipped script left it: it hides
  the box when the page opens and never shows it again.
- The robot's viewing angle and the turn and zoom speeds are this recreation's: the viewer's
  camera code is not in the archive (inferred).

## Room list and game room (Step 14, from `page_custom_game.lua`, `page_game_room.lua` and
the `res/custom_game_*.lua` and `res/game_room_*.lua` window tables)

MATCH opens the original room list; a room is a game someone hosts, and the game room is
where its players gather between battles.

**Room list** (`page_custom_game`):
- The rows list the rooms hosted on the local network: number, name, the lock and beginner
  icons, SINGLE or TEAM, Waiting, Playing, Beginner Room or FULL, and players out of 12.
  Twelve rows a page, with the arrows for more.
- Click a row to choose it, click it again (or ENTER) to go in. A locked room asks for its
  password first.
- The type button cycles all, single and team rooms; the status button all, waiting and
  playing (as `PushtypeEvent` and `PushStatusEvent` did). REFRESH clears both and the list.
- **Quick Go:** a room number, or a room name, and a password. A name that is no listed
  room but reads as an address (`192.168.1.20`, `100.64.0.7`, `mypc.local`) joins that host
  directly, which also works where the list cannot see a room.
- QUICK JOIN enters the first waiting room with space and no password.
- CREATE opens the original box: room name (up to 20 letters, no space at either end),
  password (up to 15), SINGLE or TEAM, and the beginner switch, which starts on for a new
  pilot as it did for grade 5 and below. Creating a room hosts it on port 7777.
- EXIT goes back to the channel (the main menu).

**Game room** (`page_game_room`):
- The information bar (room number as the list showed it, name, SINGLE or TEAM, Waiting or
  Playing, Beginner Room), the arena banner and twelve slots: 1-6 on the left, 7-12 on the
  right, red and blue in team battle with the VS mark and the team marks.
- Each slot shows the player's face for their body, name (yours in yellow), PVT grade, the
  room master's mark and PLAYING while they are in a battle.
- Click an empty slot to move there; in team battle that changes sides (`ChangeTeamSlot`).
  **T** still moves you to the first free slot on the other side.
- The room master has the arena arrows and START. START needs two players, and even sides
  in team battle (the original's messages otherwise), then counts down in the chat: "5
  seconds remaining" to 1, each with the original countdown sound. START again calls it off
  ("Start is cancled", the original's spelling). Enter does the same as START.
- The battle opens with the original READY and GO shrinking away and `ready go.ogg`. After
  the results everyone goes back to the room.
- Room chat goes to everyone in the room: "name : message", yours in yellow, with System
  notices in green when someone comes in or leaves (the original's "is come in" and "is out
  of the room").
- Exit (or Esc, or Android's back button) leaves for the room list.
- Someone who comes in during a battle waits in the room for the next one.

How it maps onto the network (this recreation's own, as the rooms lived on CodiNET's server):
- The room master's machine is the room: creating a room starts the host, and going in joins
  it. If the master leaves, the room closes and everyone goes back to the room list (the
  original passed the master's mark on instead).
- A host announces its room once a second by UDP broadcast on port 7778; the room list
  listens there. A second copy on the same computer cannot listen as well, so it says to
  type the address instead.
- Joining sends your name, body and the password you typed; the host checks the password
  and room space and answers with the room or the reason ("Wrong password.", "The Room is
  full."). The password never leaves the host.
- The master's own addresses appear in the room chat when the room opens, for anyone to
  type into Quick Go.

The command line skips the menus:

```
godot --path godot -- host                  # a room on port 7777, named "<you>'s room"
godot --path godot -- host teams            # the same, as a team battle
godot --path godot -- join 192.168.1.20     # into the room at that address
godot --path godot -- practice              # alone, against a target dummy
```

## Multiplayer: up to 12, free-for-all or teams

- **Room** (`srv_rcroom.cpp`): 12 places, the host included. Players take the first free
  slot in free-for-all. In team battle slots 1-6 are red and 7-12 blue, and a joiner goes
  to the smaller side (red when level).
- **Starting** (`page_game_room.lua`): needs two players, and equal sides in team battle.
- **Start points** (the server's `start_point` table): free-for-all draws from all 12 points,
  red from points 1-6 and blue from 7-12, never two on one point. The blue draw leans to the
  first blue point, as the server's did. Everyone starts facing 0 degrees: the server sent
  no direction.
- **Teammates** cannot hit each other directly: bullets, beams and swords pass through
  them (`rc_bullet::is_crash` team check), lock-on and X-Mines ignore them. Splash still hurts
  teammates and the shooter. Damage to a teammate earns no points; a kill still counts.
- **After your mech is gone** the camera follows the next player still standing, by slot.
- **Tab** shows every player's face, HP and name (`EnableUserViewInfo`), red on the left and
  blue on the right in team battle.
- macOS may ask whether Godot can accept incoming connections the first time you host.
  Allow it, or the others cannot connect.
- Several windows on one computer also connect, but only the window in front gets the
  keyboard and mouse. It is useful for testing.
- Colour schemes go by slot, cycling the body's original three. The original took them
  from each player's paint item, which this recreation does not have.
- Esc leaves the room for the room list.

How it works, following the original client: each player runs their own mech and sends its
state (60 times a second in a small room, fewer in a big one; below), tagged with the round so
a late state from the last round cannot end the new one. The host keeps the slot list and sends it to everyone when it changes.
Shots go out as events, so every screen shows every bullet. The
player who is hit decides the damage (the SR-3's database setting), then reports it to
everyone. Remote mechs glide toward their reported position the way the original eased toward
`lastRealPos`, and carry on along their last direction and speed between states.

**Movement updates by room size** (Step 16, this recreation's own): the host relays every
player's state to every other player, so its upload grows with about the square of the
player count. To keep a full room within a home connection, every machine sends fewer states
as the room fills, going by the host's player list:

| Players | States a second | Host upload, measured |
|---|---|---|
| 2 to 4 | 60 | 4 players: about 112 KB/s (0.9 Mbit/s) |
| 5 to 8 | 30 | 8 players: about 310 KB/s (2.5 Mbit/s) |
| 9 to 12 | 20 | 12 players: about 480 KB/s (3.9 Mbit/s) |

Measured with autopilot players on one computer, from ENet's own count of what the host sent
in battle, shots included; about 210 bytes per state relayed. At 60 a second, 12 players
would need about 1.45 MB/s (12 Mbit/s). Only remote mechs' position, facing and status come
less often: shots, swings, hits, guard and round events are separate messages and are never
held back. The room's System line says when the rate changes. The room master can keep 60 a
second for a big LAN game by typing `/rate full` in the room chat (`/rate auto` goes back;
`/rate` says the current rate), or start the host with `fullrate` on the command line.

## Playing over the internet with Tailscale

The room list only finds rooms on the same network: broadcasts do not cross the internet or
Tailscale. Friends elsewhere join by address, and Tailscale gives everyone a private address
without opening ports on the router.

1. Everyone installs Tailscale (tailscale.com, or the App Store and Play Store) and signs in.
   Then either invite your friends into your tailnet, or share the host's computer with them
   from Tailscale's admin console. They need to reach the host only.
2. The host creates a room. The room chat lists the host's addresses; the Tailscale one starts
   with `100.` (or run `tailscale ip -4` on the host).
3. Everyone else types that address in the room list's Quick Go name box and presses GO (with
   the room's password, if it has one).
4. Check the connection from a joining computer: `tailscale ping 100.x.y.z`. "via" an IP
   address and port means direct; "via DERP(...)" means Tailscale's relay servers are carrying
   the traffic, which adds delay and can limit a full room. `tailscale status` shows the same
   for every device: "direct" or "relay". A relayed connection often turns direct after a few
   pings; if it stays relayed, a different host or network may do better.
5. The host should be the player with the best upload speed, ideally on a computer rather than
   a phone: a 12-player room needs about 4 Mbit/s of upload (table above), more with
   `/rate full`. Everyone else uploads only their own mech's states (about 13 KB/s at 60 a
   second, 4 KB/s at 20) and downloads the others' (about 46 KB/s in a 12-player room).

The first time a Mac hosts, allow Godot to accept incoming connections when macOS asks.
Without Tailscale, the host can forward UDP port 7777 on their router and give out their
public address instead, which opens that port to anyone on the internet.

## Match rules (from the original server and client)

- Free-for-all: last mech standing. Team battle: last side standing (`GameRoom::is_game_end`).
  No respawns. If nobody is left, everyone loses: there is no draw (`get_winners_team`).
  In team battle the whole winning side wins, its fallen included.
- HP is the body's armour points (700 for the Zeid). Each hit plays one of the two hit
  reactions unless the mech is mid-attack.
- At 0 HP the mech stops and takes no input, and 0.1 s later it explodes into the original
  debris model and is no longer drawn (`rcPlayer::update_dead`).
- Under 10% HP, small explosions spark off the mech, more often as HP drops.
- The match ends the moment one mech is left. The clock counts up from zero; there is no
  time limit.
- Results show kills, damage dealt and points (damage / 10 x 0.825, the server's formula at
  equal grades, doubled in a free-for-all that started with three or more), plus rounds won
  this session.
- 6 seconds after the results a networked game goes back to the game room, as the
  original did. Practice starts its next round instead.

## Arenas (from `test_map.lua`, `rcmap.cpp` and the server)

Pick the arena in the menu, or add `map=<id>` after `--`. The host's choice goes to everyone who joins.

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
- Radar (top right): dots at 0.08 scale within 1000 x 750 units. The dot image goes by team,
  not by side: red players use the "enermy" image (the original's spelling), everyone else
  "ours", your own dot included.
- Off-screen players: a marker on a 180-pixel ring round the screen centre: the friend image
  for teammates, the brighter enemy image for the nearest enemy, the dim one for the rest.
  Markers and the names floating over mechs are green in free-for-all, red or blue in teams.
- Under 10% HP, the SPAttack warning pulses under your mech.
- With a shield, the guard gauge rides under your mech (`guard_gage`, moved every frame by
  `updateguard`): HP, shield and bit bars, each easing to its new width over 0.5 s.
- After an EMP hit the radar's enemy dots, the edge markers and the lock-on marks are hidden
  for 12 s (`Radar::hide_time`).
- HIT! when your shot lands and DAMAGE! when you are hit, the original particle scripts'
  textures, 100 units up the screen from your own mech (`World::process_damage`).

## Sound (from `NubAudiere.cpp`, `BGM.cpp` and the weapon scripts)

- Each shot plays `gunfire1`, a hit plays `gun_Hit` at the mech hit, a boost start plays
  `sp_booster`, bouncing off the arena edge plays `special_fire`, a knockout plays
  `bomb-complete`.
- The guard plays `guard` and `guard_cancel`; a block plays `energy_shield_defense` or
  `solid_shield_defense`, plus one of six `bullet_defense` ricochets for some weapons.
- Volume and pan are set once when a sound starts. The listener is over the camera but 300
  units off the plane, so a sound right below plays at 0.625 and fades out linearly by about
  740 units away. Pan is the sideways offset x 0.005 with a 50-unit dead zone.
- Each round starts a random track from the first 19 of the original play list; the winner
  hears `victory`, everyone else `defeat`. Two list entries point at a folder that does not
  exist, so about one round in ten is silent, as it was.
- Add `mute` after `--` to start silent.

Test options, added after `--`: `netlog` prints positions, HP, shield and states once a
second, `hp=60` starts every mech with 60 HP for quick knockouts, `capture=<dir>` saves 30 JPEG
frames a second (run the window with `--max-fps 60 --always-on-top`, or it runs unthrottled or
stalls when covered). `--write-movie` records sound as well. For practice: `dummy_guard` has the
target raise its guard whenever it can, `dummy_near=200` starts it that far in front of you.
For the autopilot: `slot=4` keeps it on one weapon, `autoguard` guards 2 s in every 8, `combos`
enters both command combos with a sword. For hosting: `players=4` starts the countdown once
four are in (and again after each battle), `room=<name>` names the room, `tab` keeps the Tab
panel open. `name=<player>` plays under another name without saving it, and
`profile=<name>` keeps the name, options and loadouts in `user://<name>.cfg` instead of your
own profile (the demo tools use it). `netlog` lines show each mech's weapons and, on the host,
its upload and movement rate; room System notices print too. `fullrate` keeps hosting at 60
states a second.

## Controls (as in the original)

| Input | Action |
|---|---|
| WASD or arrows | Move along the screen axes |
| Mouse | Aim. The mech turns toward the cursor at its turn rate |
| 1 / 2 / 3 / 4 | The body's weapon slots (not while firing, a burst is out, a combo plays or a bow draws). Drops the guard |
| Space | Raise or lower the guard (toggle) |
| Left click | Attack with the selected weapon. One click, one attack, except: hold the Heavy Machinegun or Plasma Shock Wave to keep firing; hold the Plasma Bow to charge and let go to shoot; let go of the Cluster Cannon to burst its shells in the air. With a sword, tap toward your facing then click, or away, toward, click, for a command combo |
| F | Next lock-on target, with the missile launcher |
| Right click (hold) | Boost, draining the gauge |
| + / - | Camera depth. Otherwise it follows the nearest enemy automatically |
| M | Sound and music on or off (this recreation's own) |
| Esc | Leave the match |

## Android (this recreation's own)

The game runs on Android phones and tablets in landscape, with on-screen controls. A
desktop Mac builds the APK; iPhone is not supported.

Build once the toolchain is installed (Homebrew `openjdk@17` and `android-commandlinetools`,
then `sdkmanager` for `platform-tools`, `build-tools;35.0.1` and `platforms;android-35` in
`~/Library/Android/sdk`, and Godot's 4.7.2 export templates):

```
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
godot --headless --path godot --export-debug Android export/atc-raycrash.apk   # the path is inside the project
```

Install it on a phone with USB debugging on: `~/Library/Android/sdk/platform-tools/adb install -r godot/export/atc-raycrash.apk`.
Or copy the file to the phone and open it (allow installs from that app when asked).
The APK carries the converted CodiNET art and sound: it is for your own phones and friends'
private play, never a store, and it is git-ignored like the art.

**Touch controls** (`scripts/touch_controls.gd`):
- **Left stick:** move along the screen axes in eight directions, like WASD. Pushed to the
  rim it also boosts. The stick appears wherever your thumb lands on the left half.
- **Right stick:** aim; the mech turns toward the drag. Pushed past a third of the way it
  fires: held for the Heavy Machinegun, Plasma Shock Wave, Plasma Bow (let go to shoot) and
  Cluster Cannon (let go to burst), about eight clicks a second for everything else.
- **Buttons:** 1 to 4 for the weapon slots, GUARD, LOCK, PLAYERS (the Tab panel) and MENU.
  Between rounds the host gets START and, in team battle, everyone gets TEAM.
- **Command combos:** flick the left stick toward your facing, then fire; or away, toward,
  fire. Each within 0.2 s, as on the keyboard.
- Android's back button leaves a match (for the room list, or the menu from practice), and
  quits from login.
- Phones on the same Wi-Fi host and join each other, and play with desktops, exactly as on
  the desktop. Some phones do not pass broadcasts to apps (inferred), so a room may be
  missing from a phone's room list; Quick Go with the host's address always works.
- The HUD keeps the original 4:3 layout in the middle of the screen; on a wide phone the
  sticks and buttons sit beside it.

Try the controls on a desktop with the mouse as one finger: `godot --path godot -- practice touch`.

## Bodies (from `rcPlayer.cpp`, `rcArmor.cpp`, `weapon_parameter.lua`, `character_mapping_parameter.lua`)

Pick the body in the menu, or add `body=<zeid|redkite|gigas|deff|alicia>` after `--` (and
`dummy=<body>` for the practice target, otherwise a random other body). Each player's body
travels with their state, so two different bodies can meet.

Default loadouts (the client's `default_item_info`; the server's `InitEquipItemByRobot`):

| Body | Armour | Walk | 1 Sword | 2 Gun | 3 Heavy | 4 Special | Shield |
|---|---|---|---|---|---|---|---|
| Zeid | 700 | 108 | EB Type 3 | SR-3 | MML Type 1 | EMP Shock Gun | ES Type 1, energy, 350 |
| Red Kite | 850 | 99 | BB02X-E | Plasma Rifle | Plasma Cannon | Confusing Beam | EBS-0500, energy, 450 |
| Gigas | 1000 | 89 | SB Type 2 | Heavy Machinegun | Cluster Cannon | X-Mine | SS Type 6, solid, 500 |
| Deff | 900 | 95 | BB02X-S | Arms-Gun | HV Head Beam | Plasma Shock Wave | SS-020, solid, 400 |
| Alicia | 750 | 102 | Saber Type 1 | Double Hand Gun | Plasma Bow | Void Pulse | ES Type 2, energy, 300 |

- **Loadouts:** each slot holds one category, chosen in the menu (see Loadouts below). The
  shield is held apart and raised with Space. Every body starts on slot 2. Until step 12 the
  defaults came from `RobotInfo`'s default weapons, which gave four bodies the Dagger; the
  original client never used that table.
- **Models:** from `anim04` (the newer models with every boost nozzle, the Zeid included).
  Each weapon brings its own attack and move clips for that body and its held model:
  - Deff's Arms-Gun sits in both hands and fires from both.
  - Alicia's pistols alternate hands and clips.
  - Alicia's bow is in her left hand with an arrow in the right.
  - Deff's head beam leaves from `head_dum`.
- **Damage clips:** each body has its own; Alicia uses Deff's.
- **Clip order:** the engine plays a file's clips by index through Direct3D's animation
  controller (`Character::anim_play`, `GetAnimationSet(index)`), which holds them last first,
  so the original's clip 0 is a file's last. Every index here follows that: in a weapon's
  file 0 is the draw, 1 the stance held while standing (the clip with no motion in every
  file), 2 and up the attacks; in a move file each move state's clip counts from the end.
  Before this was found, swords stood in a swing, which looped.
- **Colour schemes:** two alternate schemes per body.
- **Clips only turn and scale parts.** The original puts every part's position back to the
  model's own after each clip step (`Character::update_frame_pos`). Alicia's clips were made
  on a skeleton 2.3 times larger and only fit because of this.
- **Attack timing:** comes from the length of each weapon's attack clip for that body.

## Loadouts (Step 12, from `page_game_shop.lua`, `Shop_List`, the server's `Shop_Joint_Item`
and `IsEnableEquip`)

Pick each slot's weapon in the item shop (above), or add `loadout=29,37,4,17` after `--`
(sword, gun, heavy, special). Money is not ported: everything the original sold is
available.

- **Four slots by category:** sword, gun, heavy, special, as Shop_List's subtypes 1 to 4.
  A weapon fits one category only, and a slot is never empty: unequipping in the original
  put the default back.
- **By body:** Shop_List's Robot mask says who may equip what. Every weapon the shop sold
  for a body is listed (disabled rows like the Whip and Crasher are not).
- **The shield is fixed:** no shield was ever sold, so each body keeps its own.
- **Other players see your loadout:** it travels with your state, like your body.
- **Every weapon the shop sold (48):** every default weapon, every sword (Spear, Dagger,
  Claw, Crescent, Rapier, Axe, Twin Blade, H-Blade and the body swords), the H.P Beam Rifle,
  P.Pulse Gun, Impact Pulse-Gun, Viper Smart Gun and CP Cannon, and since step 17 the last 15
  (below).
  - **P.Pulse Gun:** a 6-shot burst, each bullet turned at random within 30 degrees
    (`angle_randomness`).
  - **Impact Pulse-Gun:** each hit adds 10% to the damage the target takes, up to 2.5x, each
    stack lasting 10 s (`AddDamageState`, with `defence_down.x` on the target).
  - **Viper Smart Gun:** a charge weapon; a hit also drains 200 x (1 + 0.2 per charge level)
    from the target's boost gauge.
  - **Void Pulse (Alicia's default special):** no damage. Using it makes her intangible for
    5 s: bullets, beams, swords and splash pass through, and she is drawn see-through
    (`PulseState`, "a pulse that can ignore external damage").

**The last fifteen** (Step 17, from `world.cpp` `state_change` and `process_link_hit`,
`rcPlayerState.cpp`, `rcAmmo.cpp` `create_child`, `rcManager.cpp`, `rcPlayer.cpp`, `radar.cpp`
and `rcEffect.cpp`). The original picks each effect by the weapon's id and hard-codes its
time; the database's `state_limit_time` is never read, so several times below differ from it
(the Blind Beam and R.Control Beam run 10 s, not 8; the D Fielder's field 10 s, not 30).
Numbers are the database's, packed and unpacked as the server and client did.
- **MP7-C3 (Alicia gun):** two guns firing in turn, 2 rounds a click (the first at once,
  the second 0.13 s on), 4 clicks a magazine then a 2.1 s reload. A round that flies its
  0.1 s without hitting breaks into two Sub_Missile rounds at -4 and +4 degrees (7 damage,
  0.7 s). A direct hit does 18 and splits nothing.
- **Fragment Cannon (Gigas gun):** on a hit, on a mech or a wall, a fragment leaves 30 units
  on at a fixed 400 units/s for 13 damage (25 less 12), toward the hit mech's nearest
  teammate within 600, else the mech nearest it; after a wall, the shooter's nearest enemy
  within 600, else anyone nearest; else a random way. Up to 4 links. Fragments ignore
  sides: one that meets a teammate or its own shooter is taken up with no damage and still
  links. This cannon alone can hit its own shooter, once a round is 0.2 s out.
- **PTL Type 1 (Zeid heavy):** a straight 55-damage torpedo whose time is cut to 0.1 s once
  an enemy is within 120 units of it; when its time runs out it bursts into six
  Chield_Missile rounds 60 degrees apart (7 damage, 2 s), each homing hard (guided 101) on
  the shooter's nearest enemy within 600 of the burst. A direct hit bursts nothing.
- **Napalm Thrower (Gigas heavy):** a 50-damage splash round with no radius. The mech it hits
  burns for 5 ticks a second apart, each a quarter of the hit (12, or 4 through a guard: a
  guard cuts the hit to 0.32 but does not stop the burn). Each round that lands adds a burn
  of its own.
- **CP.Pulse Cannon (Deff heavy):** a charge weapon: hold to charge one level every 0.3 s up
  to 9, draining 70 booster a second until full; let go for 1 + level rounds 0.1 s apart,
  each 20 + 2 x level damage and 10% faster per level, 15 booster each.
- **AP Drain Gun (Zeid, Alicia special):** a 10 hit, then for 10 s the target loses 4 a
  second and the shooter gains it, up to full.
- **Power Up Pulse (Alicia special):** the shooter and every living teammate within 600
  (the shooter alone in free-for-all): for 10 s booster recovery x 1.5, booster use, weapon
  energy and energy drained by others x 0.7. Its round still flies, and in the original an
  enemy it hits gets the same boost; that is kept.
- **D Fielder (Zeid special):** the same 600-unit circle: damage taken x 0.7 for 10 s. The
  generator it drops does nothing more and is gone after 4.4 s.
- **Teleport Beam (Zeid special):** its beam leaves 0.5 s after the click; the shooter goes
  to wherever it is when the button is let go, or when it ends, hits a mech (no damage) or
  meets a wall, stopped, fading back in over about 2 s. Hold to go further.
- **R.Control Beam (Red Kite special):** 10 s of swapped movement keys (left and right, up
  and down). Aim and firing are untouched.
- **Freezing Beam Gun (Red Kite special):** 10 s frozen: no movement, no attacks, and no
  damage taken and no new state either. An ice block, not a slow.
- **Leech Bomb (Gigas special):** flies 0.2 s, stops and waits for an enemy within 400,
  then chases for 1.5 s, like the X-Mine. The mech it hits carries a bomb: 30 s on, or the
  moment any damage lands on it, it goes off for 50 within 198 units, falling off by
  tenths, x 1.2 close in, to everyone (victim, allies and shooter). A teammate's shot
  through the carrier defuses it. Each hit adds its own bomb.
- **Over Booster (Gigas special):** for 10 s a boost runs at top speed at once, with no
  build-up; the gauge drains as usual. `busterup.x` shows on the mech.
- **Blind Beam (Deff special):** 10 s of `blind_eff.png` over your own screen, under the HUD
  panels, with the radar's player dots and the name tags gone.
- **Plasma Wire (Deff special):** a 10 hit that chains the two for 15 s: past 100 units
  apart the target is reeled toward the shooter at 1.5 x the distance a second and the
  shooter toward the target at 0.5 x; the target cannot use its third weapon. The chain
  (`texture01/Chain.png`) grows from the shooter at 500 units a second.

Who decides: as for every hit, the hit mech's machine decides its damage and its state and
tells everyone; burns, drains and the leech bomb's timer run on that machine. Split rounds
and fragments fly on every screen from the same shots, with no messages of their own, as
in the original. The teleport and the shooter's buffs are the shooter's machine's call.

Corrections to the weapons from before, found with these: the server's (BYTE) packing wraps
rather than clamps (the Claw Type 1's reload is 15.1 s, not 25.5); every charge weapon's
round is faster by its charge, x (1 + level x charge_add_damage), which speeds up the Plasma
Bow's and Viper's charged shots; the H.P Beam Rifle and Viper fire their first round on the
click (`use_bullet_start_time`); and the Void Pulse's round, which has no collision type,
never hits anything.

## Weapons (from `weapon_parameter.lua`, `weapon_mode_parameter.lua`, `rcAmmo.cpp`, `rcCombo.cpp`)

The Zeid's default loadout: EB Type 3 (id 1), SR-3 (id 3, selected at the start), MML Type 1
(id 4), EMP Shock Gun (id 17), and the ES Type 1 shield held apart. The Dagger Type 1 (id 28)
described next is one of the Zeid's sword choices; every sword works the same way with its
own numbers.

- **Switching:** keys 1 to 4. The new weapon is drawn with its first clip and the owner
  hears the weapon's change sound. Bullets already in flight stay (`clear_active_bullet`
  empties only the queue of shots not yet fired). Every weapon keeps recharging while not
  selected, and all of them pause while the mech is attacking.
- **Energy:** each bullet or swing spends the weapon's `cost_energy` from the boost gauge:
  20 per SR-3 bullet, 18 per dagger swing, nothing for missiles.
- **Dagger:** a click swings at once; clicks during a swing queue the next, up to three
  (clips 2, 3, 4 of `anim03/Dagger.x` in the original's order, below), each starting when
  the last ends. A swing can land
  from 0.3 s until 0.4 s after it starts, on the first mech within 59.4 units and inside a
  45-degree arc ahead, for 42 damage. The attacker's machine decides (`collision_checker`
  1). The 0.7 s cooldown runs after the whole combo. The blade leaves the original trail
  texture, and a hit throws `sword_hit.x`.
- **SR-3:** as before, but one burst per click and 20 energy per bullet.
- **MML Type 1:** 120 missiles, bursts of 3 leaving 0.3 s apart, 528 units/s for 1.7 s, 26
  damage, 3.5 s reload, 1 ammo per missile. With the launcher selected you lock onto the
  nearest enemy within 540 units and 45 degrees either side of your facing (F steps to the
  next). A burst chases the target locked when it was fired, re-aiming every 0.05 s by
  `max(0.05, dot x 100 / 255)`, and never loses it; with no lock it flies straight. A missile
  that runs out explodes harmlessly. The one hit decides the damage, and their camera shakes
  (0.25 s, power 10; the SR-3 shakes 0.1 s, power 4).
- **Lock-on HUD:** LOCK ON on your target, or on the screen ring when it is off-screen; a
  marker on other candidates; LOCKED in the centre while someone has locked onto you.

**The other bodies' weapons** (Step 7):
- **Instant beams** (`collision_type` 4) lay a line from the muzzle and hit anything on it
  while the shot lives, with no width:
  - **Plasma Cannon:** 660 units. Pierces, hitting each mech once. Passes through walls. A
    textured beam grows at the shot's speed and narrows away after.
  - **HV Head Beam:** 495 units. Follows the head as Deff turns and pierces, hitting again
    every 0.1 s of contact.
  - **Heavy Machinegun:** 198 units. Hold to fire 12.5 rounds a second. It hits the first
    mech on the line, only one round in three can do damage (`is_skip_crash`), and it shows
    a short tracer.
- **Cluster Cannon:** a shell that bursts on a hit, a wall, the end of its life, or when you
  let go of the button. It is the only shell whose wall hit splashes (`explosion()` for id
  11); every other bullet that meets a wall just shows its impact.
  - A direct hit does 52 + 60 to the mech hit.
  - Everything within 132 units takes 52, less 10% for each tenth of the radius.
  - Inside a fifth of the radius the damage is ×1.2.
- **Plasma Bow:** hold to draw, gaining a level every 1.5 s up to 2. Each level adds 20%
  damage and a larger arrow. A hit stuns for 1 / 1.5 / 2 s (no moving, turning or firing)
  and shoves the target 200 units along the arrow.
- **Double Hand Gun:** a magazine of 7. Within it the next attack is ready 0.1 s after the
  last, and a full 1.7 s reload follows the seventh.
- **Plasma Shock Wave:** hold to stream 10 rounds a second, each turned up to 30° either
  way at random, homing weakly (40) on the lock-on target within 600 units.
- **Saber Type 1:** Alicia's three-swing combo, landing from the start of each swing.

**Command combos** (Step 9, from `rcCombo.cpp`, `rcManager.cpp` `combo_shoot` and
`register_combo_command`, `combo_parameter.lua`):
- Every body's sword has two: a tap toward your facing then a click, and a tap away, a
  tap toward, then a click. The arrow keys count relative to the mech's facing (facing up,
  W is "toward" and S "away"). Each key must come within 0.2 s of the last
  (`register_combo_command` sets 0.2; the table's own `limit_time` 0.8 is never read), or the
  sequence starts over.
- The click that completes a combo swings with it. On a first swing it adds its damage
  there; during a chain it rides on the queued swing. A plain queued click carries nothing.
- Damage added: dagger +14 and +30 (56 and 72 in all), saber +15 and +32 (56 and 73). The
  three-key combo is a finisher: when it comes from the queue, the chain ends after it
  (a finisher on the first swing does not end it, as the original commented that out).
- When both sequences finish on the same click the three-key one wins: the original kept
  checking after the first match.
- A combo swing throws `combo_start.x` (a ring and "Combo!") at the mech and
  `combo_attack.x` turned to its facing (Alicia: `ali_combo_attack.x`). Other machines get
  the combo with the swing and show the same.
- The combo keys are read whatever weapon is selected, but only a sword's click uses them.

**Shields** (Step 8, from `rcManager.cpp` `updateguard`, `rcPlayer.cpp` `guard`, `world.cpp`
`process_crash` and `receive_guard`):
- **Space toggles the guard** (`bDownGuard`); letting go does nothing. It goes up only with
  durability left; raising it ends a held stream and a bow's draw. A weapon key drops it
  and changes weapon. You can walk and turn at full speed, but not attack: a click only
  sounds `shieldused`.
- **Pose:** each body's guard take-out clip, held while guarding (movement clips are
  skipped), and the defense clip on each block. Energy shields show the `pSHLD` particle
  frame; Gigas and Deff hold their shield models in the left hand.
- **Durability:** the database value x 10. It wears by the damage of each blocked hit and
  recovers 7 a second while the guard is down. At 0 the shield breaks (`shield_crash.x`)
  and the guard drops; every shield's mode has `shield_regeneration` 0, so a broken shield
  stays broken for the rest of the round.
- **What it stops:** hits whose bullet is in front, dot 0.2 or more from the facing (about
  78 degrees either side). Swords and normal bullets are stopped (`character_block.x`,
  the shield's defense sound, and a ricochet for weapons with `bullet_guard_sound`). Pierce
  beams go through and only sound on it. A splash shell's direct hit does
  `splash_damage + damage x splash_ratio` (0 unless the mode sets it), and the splash part is
  not reduced. Confusing Beam hits and bow stuns that are stopped have no effect.
- `durability_reduce`, `life_time` and the EBS-0500's cylinder collision are never read by
  the original.

**Slot-4 specials** (Step 8, from `rcAmmo.cpp`, `world.cpp` `state_change`,
`rcPlayerState.cpp` and `radar.cpp`):
- **EMP Shock Gun (Zeid):** 528 units/s for 0.7 s, 8 s reload, 40 shots, 120 energy each.
  A direct hit does 20 (24 within 13 units) and splashes 0 to everything within 66 units,
  the shooter included. Any EMP hit, even a 0, blanks your radar for 12 s: no enemy dots,
  no edge markers, no lock-on marks (lock-on itself still works). The one hit carries
  `fourth_new_zeid_spark.x` for 12 s, one per mech in the blast, as the original sent it.
- **Confusing Beam (Red Kite):** 528 units/s for 0.7 s, 5 damage. For 8 s the one hit
  moves and turns at 0.7, deals 0.7 damage and waits 0.8 s longer before each queued shot.
  A new hit restarts the 8 s. Every machine applies it, so the one deciding a hit knows.
- **X-Mine (Gigas):** two mines 0.5 and 1 s after the click, at 429 units/s. Each flies
  0.2 s and stops, hidden from other players' screens while it waits. The first time the
  nearest other player is alive and within 400 units, it turns to them, waits 0.3 s, then
  chases (homing 90) for 1.5 s. Its 20 s life runs while it waits. On contact it does 30
  to the one hit and splashes 20 within 66 units; at the end of its chase or life it
  bursts in place, owner included. Mines do not show on the radar.

**SR-3 mode 2 is left out on purpose.** Its data exists (`zeid2_mode2`, a 7-shot spray), but
the shipped client cannot reach it: the F-key handler that would select it is commented out
in `rcManager.cpp`.

## Particle effects (from `psys.cpp`, `billboard.cpp`, `engine.cpp`)

A frame named `p<group>:<script>` in a model runs particle scripts from
`data/script/particle`. `scripts/particle_fx.gd` ports the engine: sprays and trails, emit
counts, gaps, spreads, life, colour, scale and spin keys sampled into 64 steps, sprite
sheets, the three billboard modes, linked and world-space sprays, additive or alpha
blending. That drives the boost nozzles (the idle ones always, the main ones while
boosting, the directional ones in bursts against each new move), bullet glows and impacts,
the missile exhaust and trail, wall crashes, HIT! and DAMAGE!, the knockout burst and the
low-health sparks.

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

## Numbers in use (Zeid)

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
| SR-3 | 3 shots, 100 ms apart, speed 1600, life 700, reload 1200, damage 12, energy 20 | 3 shots 0.1 s apart, 528 units/s, 0.7 s, 1.2 s reload after the burst (the fire animation, 0.17 s, ends inside it), 12 damage, 20 gauge per shot |
| Dagger Type 1 | area 180, arc 45, life 450, reload 700, damage 42, energy 18 | 59.4 units, 45 degrees, lands 0.3 to 0.4 s, 0.7 s after a combo, 42 damage, 18 per swing |
| MML Type 1 | 3 shots, 300 ms apart, speed 1600, life 1750, reload 3500, damage 26, ammo 120, guided 100 | 3 missiles 0.3 s apart, 528 units/s, 1.7 s, 3.5 s reload, 26 damage, 120 ammo, homing |

Armour and MCS rows are not applied: the original server never sent them, only purchased
parts added to the base stats.

## Known gaps

- The fight HUD's weapon icons stop at id 25, so weapons from the shop's later ranges show
  no icon in the weapon panel, as in the original.
- The Napalm Thrower's attack clips (`anim03/g_napalm.x`) crash assimp's glTF exporter, as
  they move two frames the file does not have; the converter writes them itself and drops
  those two tracks.
- Step 17, inferred: the Plasma Wire chain's width (the original's "1" is in units not
  traced); a hit that does no damage (a second Leech Bomb, an EMP) leaves a leech bomb be,
  where the original's release with 0 would defuse it; the AP drain's mark has no particles,
  as its script defines another effect's under the wrong name; the R.Control and Freezing
  beams have no collision_checker, so in the original both machines applied them, which
  here is the hit mech's machine alone.
- One `WeaponInfo` column could not be named from the backup's metadata. The server's own query
  identifies it as `continuous_time`, the gap between shots.
- Clip lengths come from the converted clips; the original playback rate of `.x` animations
  is assumed to match.
- A shield is whole again each round. The original set durability only when the player was
  created, and each of its matches was a new game (inferred).
- The guard break's own clip (`PLAYERANIM_ETC` clip 1) is not identified; the break shows
  only `shield_crash.x`. A pierce hit through a guard keeps the guard pose rather than
  playing a hit reaction (inferred).
- The guard gauge's easing curve is assumed linear.
- Halving damage while an energy-shield bullet is out (`damage_to_mul` 0.5) and the repair
  bit shooting mines down are not ported: nothing in the five default loadouts creates them.
- Every machine runs each X-Mine's search on its own, as the original did, so a mine can pick
  a different moment to chase on each screen (inferred).
- The X-Mine's fire sound (`gigas4fire.ogg`) is not in the archive.
- A Cluster Cannon burst hurts its own shooter too. No owner exclusion was found in the
  source (inferred).
- The bow's charged arrow sizes (`charged_crash_radius` 9 and 12) are used as plain radii
  (inferred).
- The original's Plasma Shock Wave range indicator and the Plasma Cannon's beam
  shrinking timing after a hit are approximations.
- The combo flashes have no clip to time them, so they last 1 s, and the turned one is
  placed as a look-at along the facing with up (0, -1, 0) (inferred from the projectile
  manager's arguments). `dash_distance` is 0 in every combo, so combo dashes are not ported.
- The particle engine's random rotation seeds, wave trails and `billboard = 3` jitter are not
  ported. Interpolation between keys is assumed linear (`fcurve.cpp` is not in the archive).
- Effect models are placed with HAHA_SCALE_VAL and no turn (inferred: the projectile
  manager's placement for impacts is not traced).
- The lock-on sound (`sound/lock`) is not in the archive.
- The held weapons' own small animations are not played.
- Within one draw order the original drew sibling windows in Lua's hash order, which is
  not recoverable. Text windows are drawn last so names stay readable (inferred).
- The results screen is this recreation's own panel, not the original's result page.
- Character select's centre portrait, rotating title text and create/delete pages come from
  files missing from the archive (`charactor_select_my_charactor_show` and others); the
  turntable and pilot panel are shown without them. Alicia's turntable lacks its last frame.
- The option page's backdrop art and key setting page are not in the archive and are left out.
- The original drew HUD text with its own bitmap font; Godot's default font stands in.
- City's sky uses `mount01.png`, which is not in the archive, so that part draws untextured.
- The original's bullet wall test cast its ray backward from the previous position, so it
  noticed a wall a frame late. Here the bullet stops on the frame it crosses.
- When a mech touches several wall faces at once, the push uses the nearest one. The
  original used whichever its collision library reported first.
- Light strengths are matched by eye; Direct3D's fixed-function lighting has no exact
  Godot equivalent.
- The game room has no watch mode (the observer arrows are hidden), no waiting list or
  invitations, no master's room options (renaming, changing the password) and no NPC slots.
  Slots cannot be closed. The ping lights stay dark, and the team averages show 0.
- The results screen keeps this recreation's panel; the original's result page with its
  GAME ROOM and CHANNEL buttons is not built yet.
- NPCs, observers, money, grades and paint items are not in yet. Points leave out the
  grade-based team averages and loser penalties, which need grades.
- No lag compensation. Fine on a home network; over the internet it depends on the
  connection (above), and it has not been tried between distant players yet.

## Layout

```
project.godot
scenes/main.tscn
scripts/original.gd      constants and coordinate mapping, with sources
scripts/game_data.gd     loads the database export and applies the original conversions
scripts/mech_sim.gd      movement, boost gauge, facing, rifle: pure logic, tested
scripts/bodies.gd        the five bodies: models, loadouts, per-weapon clips and held models
scripts/mech_view.gd     a body's model, retargeted clips, held weapons, the rotation table
scripts/bullet.gd        projectile rounds: bullets, missiles, shells, arrows
scripts/beam.gd          instant line weapons and their beams
scripts/combat.gd        splash, stun, line-hit, guard and mine-target rules
scripts/room.gd          room rules: slots, teams, start points, round end, winners
scripts/game.gd          modes, networking, rounds, hits, camera, target dummy, autopilot
scripts/battle_world.gd  scenery and effects: arena, sky, lights, booster flames, hits, wall crash, explosion
scripts/battle_map.gd    an arena's bounds, start points, lights and the edge bounce
scripts/map_collision.gd wall triangles on a plane grid: sphere and segment tests
scripts/start_menu.gd    the classic practice, host, join and loadout menu (-- classic, for testing)
scripts/shop_page.gd     the original item shop page as the garage
scripts/front_end.gd     the original's login, character select, main menu, options, room list and game room
scripts/lan_rooms.gd     rooms announced and heard on the local network
scripts/touch_controls.gd on-screen sticks and buttons for phones
scripts/hud.gd           the original battle HUD: dialogs, radar, markers, name tags
scripts/original_ui.gd   the engine's UI windows, built from the exported Lua tables
scripts/game_sound.gd    positioned sound effects and the BGM play list
scripts/particle_fx.gd   the original particle engine: sprays, trails, billboards, sprite sheets
tools/convert_original.py   .x to glTF converter (reads the archive, writes assets/original)
tools/extract_db.py         reads game tables straight out of the SQL Server 2000 backup
tools/inspect_import.gd     prints an imported model's tree and clips
tools/render_poses.gd       renders the mech at several facings
tools/render_map.gd         renders an arena from above with its walls, bounds and start points
tools/ui_demo.gd            drives the front end with synthetic input, for checking it
tools/room_demo.gd          joins a room another copy hosts, through the room list, with synthetic input
tools/shop_demo.gd          equips a weapon in the item shop with synthetic input
tools/extract_ui.py         reads the HUD window tables and particle scripts, copies their art
tests/test_mech_sim.gd      300 checks against the original database values and rules
```
