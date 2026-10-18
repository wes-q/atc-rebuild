class_name Original
## Numbers and conventions taken from the original ATC Raycrash client and scripts.
## Every value names its source. "Lua" means data/script/parameter in the client,
## "C++" means the SG/PH client source in the RageZone archive.
##
## World: the original plays on the X/Z plane (y = 0), seen from a camera that sits on
## the plane's normal. Godot coordinates are the original's mapped by G = (x, -y, -z),
## so the camera sits above on +Y and screen up is -Z.

# --- Scale (C++ rcManager.cpp, net/gamept.h) -------------------------------------------
const CHARACTER_SCALE := 0.12 ## HAHA_CHARACTER_SCALE_VAL, applied to mech models
const SCALE := 0.3 ## HAHA_SCALE_VAL, applied to collision sizes
const VEL_SCALE := 0.3 * 1.1 ## HAHA_VEL_SCALE_VAL * 1.1, applied to robot and bullet speeds

# --- Movement (C++ rcPlayer.cpp update, rcArmor.cpp, rcManager.cpp) ---------------------
const BOOSTER_INIT_EXTRA := 70.0 ## booster_init_speed = booster_speed + 70
const BOOSTER_INIT_HOLD := 0.04 ## booster_init_time threshold in rcPlayer::update
const TURN_SNAP_DOT := 0.98 ## facing stops turning once within acos(0.98) of the mouse
## World::process_crash: a guard stops a hit whose bullet is in front, past this dot.
const GUARD_DOT := 0.2

# --- Camera (C++ View_Manager.cpp, world.cpp) -------------------------------------------
const CAMERA_DEPTH_MIN := 550.0 ## alive: min_depth
const CAMERA_DEPTH_MAX := 1000.0 ## alive: max_depth
const CAMERA_AUTO_MIN := 235.0 ## battle auto camera lower clamp (world.cpp)
const CAMERA_AUTO_MAX := 500.0 ## AUTO_CAMERA, option.ini camera_value default (main.cpp)
const CAMERA_ZOOM_RATE := 1000.0 ## depth change per second on + and -
const CAMERA_FOLLOW := 2.0 ## from += gap * time_elapsed * 2.0
const CAMERA_FOV := 45.0 ## world.cpp: radFov = pi / 4, 4:3 frustum

# --- Mech and weapon stats ---------------------------------------------------------------
# Come from the original game database through GameData (scripts/game_data.gd).

## Fire animation length (zeid_weapon02 clip 2). The client pauses weapon recharge while the
## mech is in BEHAVE_ATTACK, which lasts until this clip ends (rcPlayer::attack, on_end_animation).
const ATTACK_TIME := 0.5

## Weapon slot a mech starts with (rcPlayer::init: weapon_index = WEAPON_2).
const START_WEAPON := 1
## Sword swings start at attack clip 2 of the weapon file; each queued swing plays the next clip,
## timed by that clip's length.
const SWORD_FIRST_SWING := 2

# Map collision (rc_map::update, crashed_with_object, crashed_with_wall; rcPlayer::update).
const OBJECT_PUSH := 1.0 + 50.0 * 0.2 ## dash to pos + normal + normal * (50 * 0.2)
const WALL_BOUNCE_DISTANCE := 1.7 * 130.0 * 0.3 ## reflected, x HAHA_SCALE_VAL
const DASH_END_DISTANCE := 40.0 ## end_dash once lastRealPos is this close
const DASH_EASE := 0.1 ## pos += (lastRealPos - pos) * 0.1 each frame

# --- Animation indices (C++ rcPlayer.cpp Zeid::move, rcPlayer::attack, rcPlayer.h) ---------
const ANIM_STAND := 1 ## weapon file, clip 1
const ANIM_ATTACK := 2 ## weapon file, clip 2
const MOVE_FORWARD := 0 ## move file clips, indexed by PLAYER_MOVE_STATE
const MOVE_BOOSTER_FORWARD := 1
const MOVE_BACK := 2
const MOVE_BACKREACTION := 3
const MOVE_BOOSTER_BACK := 4

## Original plane coordinates (x, z) to a Godot position on the plane.
static func to_godot(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, -p.y)

## Godot position to original plane coordinates.
static func to_plane(v: Vector3) -> Vector2:
	return Vector2(v.x, -v.z)

## math::deg_from_vec2: integer degrees, 0 along +x, increasing toward +z.
static func deg_from_vec2(x: float, y: float) -> int:
	if absf(x) < 0.001:
		return 270 if y < 0.0 else 90
	var d := rad_to_deg(atan2(y, x))
	return (int(d) + 360) % 360

static func vec2_from_deg(deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg)))
