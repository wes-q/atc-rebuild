# ATC Raycrash recreation: plan

Status: Godot rewrite, milestone 1 done. The Zeid walks, boosts and fires the SR-3 with the
original numbers, model, animations and sky. See `godot/README.md` for how to run it.

The earlier browser prototype (`src/`, `tools/bot.ts`) assumed a side view. The original source
shows the game is top-down, so that prototype is superseded and kept only for reference.

## How to run the old browser prototype

```
npm install
npm run dev          # http://localhost:5173, open it in two tabs
npm run bot          # optional: a bot takes the free player slot
npm run clip -- 15 clips/fight.mp4   # record a clip (needs Chrome and ffmpeg)
npm test             # simulation tests
npm run typecheck
```

A third tab spectates player 1. `?name=Wes` sets your name. `HOST=0.0.0.0 npm run dev`
opens the server to the LAN for a second machine.

## What the original was

ATC Raycrash (Assault Tactical Combat, later M.W.Battle), CodiNET, 2005 to 2006. Online
mech fighter that played on a 2D plane: side view, free flight with boost and hover,
lock-on, machine guns and beam blades, night city and space stages. Reference screenshots
are in `reference/`.

## Direction change

The first build was a full 3D arena. Wes rejected it in favour of 2D like the original.
A clip of the 3D build is in `clips/3d-prototype.mp4`. Its code is gone from the repo.

## Architecture

- `src/sim`: pure TypeScript simulation, side view, x right and y up, metres. Fixed 60 Hz.
  No DOM. Unit tested with Node's built-in test runner.
- `src/server`: one Node process. Runs the sim, serves the client through Vite, and talks
  WebSocket on `/ws`. Authoritative. Broadcasts every tick.
- `src/client`: Canvas 2D renderer and an HTML HUD recreated from the screenshots. Sends
  input every frame and draws one tick behind, blending the last two snapshots.
- `tools/bot.ts`: headless player over the real socket. `tools/clip.ts`: MP4 recorder.

No client prediction yet. On one machine the latency is around one frame, so it is not
needed. It becomes necessary for play over the internet.

Dependencies: ws (runtime), vite and typescript (dev), type packages. All MIT or Apache 2.0,
pinned, zero audit findings. Three.js was removed with the 3D build.

## Milestone 1 scope (done)

- One night city stage: buildings to stand on, one-way decks, cyan grid boundary walls.
- Walk, jump, hold to hover, eight-way boost dash, gauge with overheat, drop through decks.
- Lock-on that faces and aims at the opponent. Tab turns it off and the mouse aims.
- Heavy machine gun with ammo, beam blade slash with lunge and knockback.
- Rounds: countdown, 3 minute clock, knockout or time out, win counter, auto restart.
- HUD after the original: score, timer, boost gauge, lock ring, weapon slots, ammo, HP,
  side-on minimap, DAMAGE! pops.

## Next candidates

- Original art (below). The mech is drawn from polygons, so a sprite swap is contained in
  `src/client/mech.ts`.
- Sound.
- Space stage, as in reference screenshots 01 and 06.
- Weapon loadouts in the four slots, and the F1 to F3 quick slots.
- Tuning pass with two people. Constants are all in `src/sim/constants.ts`.

## Getting closer to the original

Hand-drawn 2D will not converge on the original, which drew 3D models from a side camera on
a locked plane. Every option below except a footage-only rebuild needs the RageZone archive.

| Option | Difficulty | Efficiency | Time |
|---|---|---|---|
| Extract the original art | Medium with source, hard without | Very high | Days |
| Port using source and data | Medium to hard | High | Weeks |
| Rebuild from footage only | Low to medium, slow | Low, lookalike only | Weeks |
| Disassemble the binaries | Very hard | Very low | Months |

Art extraction and the port run as two parallel tracks after a shared archive inventory. They
meet at a 3D side-view renderer. Stage files and animation timing feed both tracks.

### Platform for the port

- Source port: compile the original C++ with modern tools and replace DirectX, for example
  with SDL. Truest duplicate, but only if the source is complete and builds. Needs Windows and
  Visual Studio, possibly an older version.
- Browser, the current TypeScript stack moved to Three.js: easy sharing, full rewrite.
- Godot 4: free, strong 3D with a side camera, exports to desktop and web. Full rewrite.
- Unity is workable but heavy. Unreal is overkill.

Decision rule: run the original first as the reference. Source port if the source builds,
otherwise rewrite in Godot or the browser with the extracted art and data. The archive
inventory decides.

### Running the original

Needs the compiled server and client, the two databases, the two config files and the
launcher. The source download is optional for this.

- On the Mac: a Windows virtual machine. VMware Fusion is free, Parallels is paid with the
  best 3D, UTM has weak 3D. Windows runs unactivated with a watermark.
- Database: likely SQL Server (inferred), Express or Developer are free. It is not officially
  supported on Windows for ARM, so it may need to run in a container on the Mac. A 2005-era
  backup may need an intermediate SQL Server version to restore (inferred).
- On a Windows PC: still isolate the leaked programs in Hyper-V, VMware Workstation,
  VirtualBox or a spare PC. Intel and AMD machines run it natively.
- Heroic Games Launcher (Wine) suits the client only. The server's Windows services and SQL
  Server do not run reliably under Wine, and Wine gives little isolation from Mac files.
  Possible mix: server in a VM or on a spare PC, client through Heroic on the Mac.
- No subscription to pay. The leaked server includes its own billing service, so your server
  decides who plays (inferred until the files are seen).

## Original art

A 2016 RageZone release has the client, server, databases and source. Links are behind a
forum login. The original models are 3D, rendered side-on, so using them in 2D means either
rendering them to sprite sheets or drawing new sprites over them.

1. Wes downloads the archives into a folder outside this repo. Nothing from them is run.
2. Inventory formats, read the source for the model loader, write a converter.
3. Render each mech's animations to sprite sheets from a side camera.

The art is CodiNET's copyright. Fine for private local play, not for publishing. TODO:
decide before this goes anywhere public.
