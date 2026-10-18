class_name Bullet
extends Node3D
## SR-3 round. Flies straight on the plane at the original speed for the original life.
## Orientation follows rc_bullet::init: model +Z along the direction, scaled by HAHA_SCALE_VAL.

const MODEL := "res://assets/original/zeid/bullet_sr3.gltf"
static var _scene: PackedScene

var plane_pos := Vector2.ZERO
var dir := Vector2.RIGHT
var speed := 0.0
var life := 0.0
var radius := 0.0
var power := 0
var owner_sim: MechSim

func setup(origin: Vector2, deg: int, shooter: MechSim) -> void:
	var w := shooter.weapon
	plane_pos = origin
	dir = Original.vec2_from_deg(deg)
	speed = w.bullet_speed
	life = w.life
	radius = w.crash_radius
	power = w.damage
	owner_sim = shooter
	if _scene == null:
		_scene = load(MODEL)
	var model := _scene.instantiate() as Node3D
	add_child(model)
	# rc_Weapon::update_bullet: z along the direction, up = direction turned 90 degrees in the plane.
	var z := Vector3(dir.x, 0, dir.y)
	var up := Vector3(-dir.y, 0, dir.x)
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	var b := MechView.G * Basis(x, y, z) * Basis.from_scale(Vector3(1, 1, -1)) * Basis.from_scale(Vector3.ONE * Original.SCALE)
	model.transform = Transform3D(b, Vector3.ZERO)
	position = Original.to_godot(plane_pos)

## Returns false when the bullet has expired.
func advance(dt: float) -> bool:
	life -= dt
	plane_pos += dir * speed * dt
	position = Original.to_godot(plane_pos)
	return life > 0.0
