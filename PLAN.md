# ATC Raycrash recreation: plan

Private recreation of ATC Raycrash (CodiNET, 2005) in Godot 4.7, using the original rules,
data and art from the 2016 RageZone release. Not for publishing: the art, data and the rules
read from the source are CodiNET's.

How to run, controls and every number in use: `godot/README.md`.
What the archive contains: `docs/archive-inventory.md`.

## What the original is (from its source)

- Top-down. Mechs move on a flat plane and the camera looks straight down at it. Each mech is
  rolled as it turns so it always shows an upright side profile, which is why players said it
  "looked 3D but played 2D".
- Online, client and server. Each client moves its own mech and reports moves to the server.
  For most weapons the player who gets hit decides the damage.
- Four (later five) bodies: Zeid, Red Kite, Gigas, Deff, Alicia. Five weapon slots each, beam
  swords with key combos, guns, missiles, grapples, drones (bits).

## Decisions

- Godot rewrite, not a source port. The source does not build cleanly and a port would stay on
  Windows. The source is the specification.
- Rules and numbers come from the original database backup and the client's Lua tables,
  converted exactly as the server and client did. Every constant names its source.
- Art comes straight from the client: `.x` models to glTF through Assimp.
- Private play only. A clean-room process would be needed before anything is published.

## Milestones

| # | Step | Status |
|---|---|---|
| 1 | Zeid walking, boosting and firing the SR-3 on the original numbers | Done |
| 2 | Two players over the network | Done |
| 3 | Damage, knockouts and rounds | Done |
| 4 | A real battle map: scenery and collision grid | Done |
| 5 | Sound and the original HUD art | Done |
| 6 | The Zeid's other weapons: sword combos, missiles (SR-3 mode 2 is unreachable in the original) | Done |
| 7 | The other four bodies | Done |
| 8 | Shields and the slot-4 specials (EMP, Confusing Beam, X-Mine) | Done |
| 9 | Sword command combos | Done |
| 10 | Up to 12 players, free-for-all or red and blue teams | Done |
| 11 | Android: touch controls and an APK build | Done |
| 12 | Loadouts: four weapon slots by category, the original defaults, 33 weapons | Done |
| 13 | The original front end: its controls, login (player name), character select, main menu, options | Done |
| 14 | The original room list and game room, with LAN discovery | Done |
| 15 | The original shop page as the garage | Done |
| 16 | Internet play: send rate by player count, a host override, the Tailscale guide | Done |
| 17 | The last 15 weapons: split and linked shots, burns, drains, the leech bomb, teleport, freeze, blind, the plasma wire | Done |
| 18 | The grab (clutch) and each body's special attack | Done |
| 19 | The jump (X) and the shove (Shift) | Done |
| 20 | Mech bumping | Done |

## Step 16 plan: internet play (agreed with Wes)

- **State send rate by player count**, picked by every machine from the host's roster, so it
  is the same for everyone and changes mid-match when someone joins or leaves:
  2 to 4 players 60 a second (as now), 5 to 8 players 30, 9 to 12 players 20. Send every Nth
  physics tick. Receivers need no change: `MechSim.step_remote` already carries a remote mech
  on along its last direction and speed between states.
- **A host override** forcing 60 a second, for big LAN games that do not need the lower rate:
  `/rate full` in the room chat, or `fullrate` on the command line.
- **README: playing over the internet with Tailscale**, including `tailscale ping` and
  `tailscale status` to tell a direct connection from a relayed (DERP) one, and that the host
  should be the player with the best upload, ideally on a computer.
- The optional room password is already in (step 14).

Why: the host relays every player's state to every other player, so its upload grows with
roughly the square of the player count, about (N-1)^2 streams. Measured in step 16: about 210
bytes an update, so 12 players at 20 a second is about 0.48 MB/s (4 Mbit/s), against about
1.45 MB/s (12 Mbit/s) at 60. The lower rate affects only remote mechs' position, facing and status: shots,
swings, hits, guard and round events are separate reliable messages and are not delayed.

Kept in reserve, not planned:
- Smaller updates: positions as short integers, and leaving out fields that did not change
  (weapon slot, shield, round number).
- The original's change-based move sending: a state on start, stop, direction change or boost,
  plus a 10 to 20 a second drift correction, with smoothing of remote position and facing.

## History

- A 3D arena prototype and then a side-view 2D browser prototype came first, built from
  screenshots before the archive arrived. Both assumed the wrong view. The browser prototype
  is in the first commit's history. Clips of both are in `clips/` (git-ignored).
