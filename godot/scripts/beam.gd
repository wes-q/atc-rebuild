class_name Beam
extends Node3D
## A shot from an immediate weapon (collision_type 4): the Plasma Cannon, HV Head Beam and
## Heavy Machinegun. rc_bullet::fire lays a line collision_line_distance long from the muzzle
## along the fire direction; every frame while the shot lives, any mech the line passes
## through can be hit (rc_bullet::is_crash, segment against the mech's sphere, no width).
## An invisible point also moves along it at the bullet speed; a wall stops the shot when that
## point reaches it, unless the mode sets crash_with_map = 0.
##
## Pierce weapons (weapon_type 3) hit every mech on the line: max_crash_count 1 hits each once;
## -1 hits again every crash_interval_time of contact. A normal one (the Heavy Machinegun)
## hits the first mech in slot order and ends. With use_beam_effect a textured strip grows from
## the muzzle at the bullet speed (up to beam_distance when set), beam_width x 0.33 wide, and
## after the shot it narrows by vel_to_destroy_beam x 0.33 a second.

var weapon: GameData.Weapon
var shooter_id := 0
var start := Vector2.ZERO
var dir := Vector2.RIGHT
var life := 0.0
var travelled := 0.0
var alive := true
## follow_player_weapon: the line follows the muzzle and facing as the mech turns.
var follow := false
## is_skip_crash: this round cannot do damage.
var skip := false
var hits := {} ## mech id -> [count, contact time]
var _width := 0.0
var _shrink := 0.0
var _beam_distance := 0.0
var _mesh: ImmediateMesh
var _mat: StandardMaterial3D
var _mesh_node: MeshInstance3D

func setup(origin: Vector2, deg: int, w: GameData.Weapon, shooter: int, skip_round := false) -> void:
	weapon = w
	shooter_id = shooter
	start = origin
	dir = Original.vec2_from_deg(deg)
	life = w.life
	skip = skip_round
	follow = int(w.mode_num("follow_player_weapon")) == 1
	if int(w.mode_num("use_beam_effect")) == 1:
		_width = w.mode_num("beam_width") * Original.VEL_SCALE
		_shrink = w.mode_num("vel_to_destroy_beam") * Original.VEL_SCALE
		_beam_distance = w.mode_num("beam_distance")
		var tex_path := Bodies.ROOT + Bodies.x_name(str(w.mode.get("beam_texture", ""))) + ".png"
		_mesh = ImmediateMesh.new()
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_mat.albedo_texture = load(tex_path) if ResourceLoader.exists(tex_path) else null
		_mesh_node = MeshInstance3D.new()
		_mesh_node.mesh = _mesh
		_mesh_node.top_level = true
		_mesh_node.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
		add_child(_mesh_node)

func pierce() -> bool:
	return weapon.is_pierce()

func max_hits() -> int:
	return int(weapon.mode_num("max_crash_count", 1))

func hit_interval() -> float:
	return weapon.mode_num("crash_interval_time", 0.1)

func stops_at_walls() -> bool:
	return int(weapon.mode_num("crash_with_map", 1)) == 1

## The collision line.
func line_end() -> Vector2:
	return start + dir * weapon.line_distance

## The moving point, for walls.
func point() -> Vector2:
	return start + dir * travelled

## Advances the shot. Returns false once it is over and its strip has faded.
func advance(dt: float, muzzle: Vector2, facing_deg: int) -> bool:
	if alive:
		if follow:
			start = muzzle
			dir = Original.vec2_from_deg(facing_deg)
		travelled += weapon.bullet_speed * dt
		life -= dt
		if life <= 0.0:
			alive = false
	elif _width > 0.0:
		_width = maxf(0.0, _width - _shrink * dt)
	_draw()
	return alive or _width > 0.0

## rc_bullet::crash for a pierce shot: whether this contact counts as a new hit on that mech.
func register_contact(id: int, dt: float) -> bool:
	if not hits.has(id):
		hits[id] = [1, 0.0]
		return true
	var h: Array = hits[id]
	if max_hits() >= 0:
		if h[0] >= max_hits():
			return false
		h[0] += 1
		return true
	h[1] += dt
	if h[1] >= hit_interval():
		h[1] -= hit_interval()
		h[0] += 1
		return true
	return false

func _draw() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	var length := travelled if _beam_distance <= 0.0 else minf(travelled, _beam_distance)
	length = minf(length, weapon.line_distance if weapon.line_distance > 0.0 else length)
	if _width <= 0.0 or length <= 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var a := Original.to_godot(start)
	var b := Original.to_godot(start + dir * length)
	var side := (b - a).cross(-camera.global_transform.basis.z).normalized() * _width * 0.5
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	var quad := [[a - side, Vector2(0, 0)], [a + side, Vector2(0, 1)], [b - side, Vector2(1, 0)], [b + side, Vector2(1, 1)]]
	for k in [0, 1, 2, 1, 3, 2]:
		_mesh.surface_set_uv(quad[k][1])
		_mesh.surface_add_vertex(quad[k][0])
	_mesh.surface_end()
