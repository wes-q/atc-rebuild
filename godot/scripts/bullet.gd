class_name Bullet
extends Node3D
## A round from a gun weapon: the SR-3's bullets and the MML's guided missiles.
## Orientation follows rc_bullet::init: model +Z along the direction, scaled by HAHA_SCALE_VAL.
## The models' particle frames run their scripts (the SR-3's glow, the missile's exhaust and
## trail).

## weapon_mode_parameter.lua bullet_xfile and bullet_dead_xfile, by weapon id.
const MODELS := {
	3: "res://assets/original/zeid/bullet_sr3.gltf",
	4: "res://assets/original/zeid/missile_mml.gltf",
}
const BOOMS := {
	3: "res://assets/original/zeid/bullet_sr3_boom.gltf",
	4: "res://assets/original/fx/missile_boom.gltf",
}
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
var weapon_id := 0
var guided := 0
var owner_sim: MechSim
## The mech a guided bullet chases, or null to fly straight.
var target: MechSim
var _homing_time := 0.0
var _model: Node3D

func setup(origin: Vector2, deg: int, shooter: MechSim, w: GameData.Weapon, chase: MechSim = null) -> void:
	plane_pos = origin
	prev_pos = origin
	dir = Original.vec2_from_deg(deg)
	speed = w.bullet_speed
	life = w.life
	radius = w.crash_radius
	power = w.damage
	weapon_id = w.id
	guided = w.guided_flag
	owner_sim = shooter
	target = chase if guided > 0 else null
	var path: String = MODELS.get(w.id, MODELS[3])
	if not _scenes.has(path):
		_scenes[path] = load(path)
	_model = (_scenes[path] as PackedScene).instantiate() as Node3D
	add_child(_model)
	ParticleFX.attach_all(_model)
	_orient()

## Returns false when the bullet has expired.
func advance(dt: float) -> bool:
	prev_pos = plane_pos
	life -= dt
	if target:
		_homing_time -= dt
		if _homing_time <= 0.0:
			_homing_time = HOMING_STEP
			_steer()
	plane_pos += dir * speed * dt
	_orient()
	return life > 0.0

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
	# rc_Weapon::update_bullet: z along the direction, up = direction turned 90 degrees in the plane.
	var z := Vector3(dir.x, 0, dir.y)
	var up := Vector3(-dir.y, 0, dir.x)
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	var b := MechView.G * Basis(x, y, z) * Basis.from_scale(Vector3(1, 1, -1)) * Basis.from_scale(Vector3.ONE * Original.SCALE)
	_model.transform = Transform3D(b, Vector3.ZERO)
	position = Original.to_godot(plane_pos)

## bullet_dead_xfile for this weapon, at a plane point.
func boom_scene() -> String:
	return BOOMS.get(weapon_id, BOOMS[3])
