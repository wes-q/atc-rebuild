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
| 3 | Damage, knockouts and rounds | Next |
| 4 | A real battle map: scenery and collision grid | |
| 5 | Sound and the original HUD art | |
| 6 | The Zeid's other weapons: sword combos, missiles, SR-3 mode 2 | |
| 7 | The other four bodies | |

## History

- A 3D arena prototype and then a side-view 2D browser prototype came first, built from
  screenshots before the archive arrived. Both assumed the wrong view. The browser prototype
  is in the first commit's history. Clips of both are in `clips/` (git-ignored).
