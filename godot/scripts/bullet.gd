class_name Bullet
extends Node3D
## A round from a projectile weapon: plain bullets, guided missiles and shock waves, splash
## shells and the bow's arrows. Its model and impact come from the weapon's mode table
## (bullet_xfile, bullet_dead_xfile; the bow's charge levels pick bullet_xfile2/3 and
## bullet_dead_xfile3/4). Orientation follows rc_bullet::init: model +Z along the direction,
## scaled by HAHA_SCALE_VAL. The models' particle frames run their scripts.

## rc_bullet::update: a guided bullet re-aims every 0.05 s (0.01 s only past guided_flag 100).
const HOMING_STEP := 0.05
static var _scenes := {}

var plane_pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var dir := Vector2.RIGHT
var speed := 0.0
var life := 0.0
var radius := 0.0
var power := 0
var weapon: GameData.Weapon
var weapon_id := 0
var guided := 0
var charge := 0
var owner_sim: MechSim
## The mech a guided bullet chases, or null to fly straight.
var target: MechSim
var _homing_time := 0.0
var _model: Node3D

# X-Mine (is_stop): flies for stop_time, stops, and each frame looks for the nearest enemy
# within detecting_area. Once it has one it turns toward it, waits delay_after_stop, then
# chases it like a guided bullet for chase_time (its life is reset to that).
var mine := false
var _stop_left := 0.0
var _delay_left := 0.0
var _chasing := false
## Finds a mine's target: (mine position, range) -> MechSim or null. Set by the game.
var find_target: Callable

func setup(origin: Vector2, deg: int, shooter: MechSim, w: GameData.Weapon, chase: MechSim = null, charge_level := 0) -> void:
	plane_pos = origin
	prev_pos = origin
	dir = Original.vec2_from_deg(deg)
	weapon = w
	speed = w.bullet_speed
	life = w.life
	radius = w.crash_radius
	weapon_id = w.id
	guided = w.guided_flag if w.is_guided() else 0
	charge = maxi(0, charge_level)
	# charge_add_damage: each charge level adds this share of the damage.
	power = int(w.damage * (1.0 + w.param_num("charge_add_damage") * charge))
	if charge == 1 and w.mode.has("charged_crash_radius"):
		radius = w.mode_num("charged_crash_radius")
	elif charge >= 2 and w.mode.has("charged_crash_radius2"):
		radius = w.mode_num("charged_crash_radius2")
	owner_sim = shooter
	target = chase if guided > 0 else null
	mine = w.is_mine()
	if mine:
		_stop_left = w.mode_num("stop_time")
	var key := "bullet_xfile" if charge == 0 else "bullet_xfile%d" % (charge + 1)
	var path := Bodies.scene_path(str(w.mode.get(key, w.mode.get("bullet_xfile", ""))))
	if path != "" and not _scenes.has(path):
		_scenes[path] = load(path)
	if path != "" and _scenes[path] != null:
		_model = (_scenes[path] as PackedScene).instantiate() as Node3D
		add_child(_model)
		ParticleFX.attach_all(_model)
	_orient()

## Returns false when the bullet has expired.
func advance(dt: float) -> bool:
	prev_pos = plane_pos
	life -= dt
	if mine:
		_advance_mine(dt)
		_orient()
		return life > 0.0
	if target:
		_homing_time -= dt
		if _homing_time <= 0.0:
			_homing_time = HOMING_STEP
			_steer()
	plane_pos += dir * speed * dt
	_orient()
	return life > 0.0

## rc_bullet::update for is_stop. The 20 s life keeps running while the mine waits.
func _advance_mine(dt: float) -> void:
	if _stop_left > 0.0:
		_stop_left -= dt
		plane_pos += dir * speed * dt
		return
	if target == null:
		if find_target.is_valid():
			target = find_target.call(plane_pos, weapon.mode_num("detecting_area"))
		if target:
			# bullet_vec = target - pos: it faces the target while it waits.
			var to := target.pos - plane_pos
			if to.length_squared() > 0.0001:
				dir = to.normalized()
			_delay_left = weapon.mode_num("delay_after_stop")
		return
	if not _chasing:
		_delay_left -= dt
		if _delay_left > 0.0:
			return
		_chasing = true
		life = weapon.mode_num("chase_time")
		guided = weapon.guided_flag
	_homing_time -= dt
	if _homing_time <= 0.0:
		_homing_time = HOMING_STEP
		_steer()
	plane_pos += dir * speed * dt

## A stopped mine with no target yet (other players' screens do not draw it).
func is_lying() -> bool:
	return mine and _stop_left <= 0.0 and target == null

## The original turns a guided bullet by slerping between 180-degree rotations about the old
## and new headings, which amounts to slerping the headings themselves. The step is the dot
## of the two times guided_flag / 255, at least 0.05. It never loses its target.
func _steer() -> void:
	var to := target.pos - plane_pos
	if to.length_squared() < 0.0001:
		return
	var want := to.normalized()
	var t := maxf(0.05, dir.dot(want) * float(guided) / 255.0)
	dir = dir.slerp(want, minf(t, 1.0)).normalized()

## rc_bullet::is_crash, NORMAL type: distance from the mech to this frame's path.
func hits(at: Vector2, mech_radius: float) -> bool:
	var closest := Geometry2D.get_closest_point_to_segment(at, prev_pos, plane_pos)
	return closest.distance_to(at) <= mech_radius + radius

func _orient() -> void:
	position = Original.to_godot(plane_pos)
	if _model == null:
		return
	# rc_Weapon::update_bullet: z along the direction, up = direction turned 90 degrees in the plane.
	var z := Vector3(dir.x, 0, dir.y)
	var up := Vector3(-dir.y, 0, dir.x)
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	var b := MechView.G * Basis(x, y, z) * Basis.from_scale(Vector3(1, 1, -1)) * Basis.from_scale(Vector3.ONE * Original.SCALE)
	_model.transform = Transform3D(b, Vector3.ZERO)

## bullet_dead_xfile for this weapon and charge level.
func boom_scene() -> String:
	var key := "bullet_dead_xfile" if charge == 0 else "bullet_dead_xfile%d" % (charge + 2)
	return Bodies.scene_path(str(weapon.mode.get(key, weapon.mode.get("bullet_dead_xfile", ""))))

## button_up_explosion: the owner can set it off by letting go of the button.
func detonates_on_release() -> bool:
	return int(weapon.mode_num("button_up_explosion")) == 1
