# RageZone archive inventory

Read 2026-10-18. Location: `RaycrashArchive/` (git-ignored, not served by the dev server).
Extracted copies: `RaycrashArchive/extracted/source` and `RaycrashArchive/extracted/database`.
Nothing from the archive has been executed.

## What came down

| Archive | Size | Contents |
|---|---|---|
| RayCrash Source.zip | 2.2 GB | Superset. Client build and data (`ATC BIN`), client and engine source (`ATC Engine`), server source (`CodiNET Server Source 1`), and `Andrew/` |
| Raycrash Client Server.rar | 633 MB | Same client, engine and server folders as the source zip, under other names |
| RayCrash Database.rar | 0.9 MB | Two SQL Server 2000 backups, `raycrash1` and `raycrash2` |

`Andrew/` holds `RayCrash/Source Codes.zip` and `EK/`, which appears to be a different
CodiNET game (inferred). `RayCrash Source2.zip` (the forum's page 3 link) is a byte-identical
duplicate of `RayCrash Source.zip` (same SHA-256), so it adds nothing.

### Two versions of the client source

`Andrew/RayCrash/Source Codes.zip` is extracted to `extracted/source-sgph`. Its readme calls
it the source "used for SG/PH service", the Singapore and Philippines release.

| | Main copy (`ATC Engine`) | SG/PH copy (`source-sgph/engine`) |
|---|---|---|
| Latest edits | Some files edited in 2008 | Files dated up to April 2006 |
| Gameplay code | Identical | Identical |
| Differences | Login check skipped with a `goto`, forced 800x600 display: looks like later private-server edits (inferred) | WASD added as movement keys, login security fix, network changes |

947 of 959 code files are identical, including every gameplay system: player, movement,
weapons, combos, damage. The 12 that differ cover input, networking, login, audio headers,
startup and one Lua library file. For the rewrite the rules are the same either way. Use the
SG/PH copy for controls, since that is the version players in the region knew.

Extraction note: 42 files have Korean names in an old encoding. They extract correctly with
`bsdtar --options hdrcharset=CP949`.

## Game data: plain text, ready to use

`ATC BIN/bin/data/script/parameter/*.lua`, Korean comments in CP949.

- `player_parameter.lua`: per mech body (zeid, redkite, gigas, deff). Life, walk speed,
  boost speed, boost gauge size, drain and recovery, short boost, collision radius, turn
  speed, shove, and the four weapons each body carries.
- `weapon_parameter.lua` (1,600 lines): every weapon, its model, attach point, ammo,
  animations, combo use and firing modes.
- `weapon_mode_parameter.lua`, `combo_parameter.lua`, `clutch_combo_parameter.lua`:
  firing modes, melee combos with exact key sequences, damage and time limits, and grapples.
- Armour, colour, shop, NPC and preload tables.
- `new_parameter.lua` shows how the engine loads all of the above.
- `script/particle` (186 Lua files): effect definitions. `script/page` and `script/res`: UI.

Units look like engine units, roughly centimetres (speed 300, collision radius 40, inferred).

## Art

- Models and animations: DirectX `.x`, binary (370 sampled) and MSZIP-compressed binary (30).
  Assimp reads both and exports glTF for Godot.
- Mechs: `data/middle_character/<body>/`, one model plus separate animation files per action
  (weapons 1 to 4 standing and moving, guard, damage, grapple, interface poses).
- Armour parts and colour textures: `data/item01`, `item02`. Weapons: `data/weapon`, `weapon01`.
- Maps: `data/map/map01` to `map05` (field) and `b_map01` to `b_map05` (battle), each with
  sky models, textures and an `object` folder. Collision source: `MapCollisionGrid.cpp`.
- Textures: PNG (2,169), DDS (66), TGA, BMP. UI: `data/ui`, `ui2`, `ui3`.
- Audio: Ogg Vorbis (116) and WAV. Music in `bin/BGM`.
- Packs: `.vp` files are a `VPVP` header plus raw files, with names and offsets in a matching
  `.hdr`. Simple to unpack, and most content also exists loose.
- 3ds Max source files: 4.

## Reference video

`ATC BIN/bin/RAYCRASH-2005.avi`: official 2005 trailer, 2 min 17 s, 640x480, much real
gameplay. `ray.wmv` is the same video. `ace_trim.wmv` is an unrelated anime trailer.

## Source code

- Client game logic, `ATC Engine/main`: player, movement (`rcPlayerMove`), player state, lock-on,
  weapons, ammo, combos, grapple (`rcClutch`), damage, shield, bits, energy, AI, NPCs, map
  collision grid, world, effects, radar, UI, networking protocol.
- Engine, `ATC Engine/engine`: DirectX 9 sample framework (`d3dfile` loads `.x`), Lua 5 with
  tolua, math. Libraries: Audiere (sound), ColDet (collision), FLAC.
- `ATC Engine/fileArchiver`: the `.vp` packer.
- Server, `CodiNET Server Source 1/RAYCRASH_SERVER/source`: RayCrash server, network module,
  billing. Plus auto-patcher and billing tools.
- Debug symbol files (`.pdb`) are present, useful if any logic is missing from the source.
- Build: Visual Studio 2002/2003 era projects (`.vcproj`, `.dsp`). The forum reports it does
  not build cleanly, which does not matter for the Godot rewrite.

## Databases: mostly player data, treat as sensitive

- `raycrash1`: game accounts. Characters, battle records, clans, owned items, shop list and
  logs. Only `shop_list` has possible game value, and prices may also be in the Lua shop table.
- `raycrash2`: billing. User info, billing info, payment logs, IP table. Likely real people's
  personal data. Do not restore or open.
- Neither is needed for the Godot rewrite. Balance data lives in the Lua scripts.

## Verdict for the Godot rewrite

Best case on both tracks. Data: plain Lua tables plus readable C++ for the rules. Art: a
standard model format with a ready converter, standard image and audio formats, and an
official gameplay video to check against.
