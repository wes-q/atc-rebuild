class_name BattleWorld
extends RefCounted
## Scenery and effects for the battle scene: lights, camera, the arena model and its sky,
## booster flames, hit flashes, wall crashes and the knockout explosion.

const HIT_FLASH := "res://assets/original/zeid/bullet_sr3_boom.gltf"
const EXPLOSION := "res://assets/original/fx/explo2_result.gltf"
const WALL_CRASH := "res://assets/original/fx/wall_crash.gltf"
const SKY_SCALE := 100.0
## Map model space to Godot: undo Assimp's z mirror, HAHA_SCALE_VAL, then the plane mapping.
const MAP_BASIS := Basis(Vector3(0.3, 0, 0), Vector3(0, -0.3, 0), Vector3(0, 0, 0.3))

static var _effect_scenes := {}
const CHARACTER_EXPLO := "res://assets/original/fx/character_explo.gltf"
const PART_EXPLOSION := "res://assets/original/fx/part_explosion.gltf"
const SWORD_HIT := "res://assets/original/fx/sword_hit.gltf"
const FONT_HIT := "res://assets/original/fx/font_hit.gltf"
const FONT_DAMAGE := "res://assets/original/fx/font_damage.gltf"
const FONT_TIME := 1.2 ## the particles' 1 s life (energy), plus their 0.2 s emission

## Environment, light and camera. The arena comes from build_map.
static func build(root: Node3D, depth: float) -> Dictionary:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.0, 0.0, 0.02)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, 25, 0)
	sun.light_energy = 1.1
	root.add_child(sun)

	var camera := Camera3D.new()
	camera.fov = Original.CAMERA_FOV
	camera.near = 3.3
	camera.far = 5000.0 * 3.3
	root.add_child(camera)
	camera.position = Vector3(0, depth, 0)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	return {"camera": camera, "env": env, "sun": sun}

## rc_map::load: the map model scaled by HAHA_SCALE_VAL, an "o:name" frame placing name.x,
## the map's sky, and the light values its Lua table sets in init.
static func build_map(root: Node3D, map: BattleMap, env: WorldEnvironment, sun: DirectionalLight3D) -> Dictionary:
	var node := Node3D.new()
	node.name = "Map"
	root.add_child(node)
	var model := (load(map.folder + "rac.gltf") as PackedScene).instantiate() as Node3D
	node.add_child(model)
	model.transform = Transform3D(MAP_BASIS, Vector3.ZERO)
	for o in map.objects:
		var obj := (load(map.folder + str(o["file"])) as PackedScene).instantiate() as Node3D
		model.add_child(obj)
		var m: Array = o["matrix"]
		obj.transform = Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))
		apply_frame_flags(obj, false)
		MechView.play_effect(obj, true)
	apply_frame_flags(model, false)
	MechView.play_effect(model, true)

	# skybox::render: the sky model is re-centred on the camera every frame. Scaled out beyond
	# the arena so it never covers the mechs; from the centre it looks the same.
	var sky := (load(map.folder + "skymap.gltf") as PackedScene).instantiate() as Node3D
	sky.name = "Sky"
	node.add_child(sky)
	apply_frame_flags(sky, true)
	MechView.play_effect(sky, true)

	# client_global light values, D3D direction mapped to Godot like any other vector.
	var d := map.light_direction
	var dir := Vector3(d.x, -d.y, -d.z).normalized()
	sun.look_at_from_position(Vector3.ZERO, dir, Vector3(0, 0, -1) if absf(dir.y) < 0.99 else Vector3(1, 0, 0))
	var diffuse := map.light_diffuse
	var peak := maxf(diffuse.x, maxf(diffuse.y, diffuse.z))
	sun.light_color = Color(diffuse.x / peak, diffuse.y / peak, diffuse.z / peak)
	sun.light_energy = peak * LIGHT_SCALE
	var a := map.light_ambient
	env.environment.ambient_light_color = Color(a.x, a.y, a.z)
	env.environment.ambient_light_energy = AMBIENT_SCALE
	return {"node": node, "sky": sky}

## D3D fixed-function light values to Godot light energy, matched by eye against the
## original's screenshots.
const LIGHT_SCALE := 0.6
const AMBIENT_SCALE := 1.6

## Model::frame properties from a frame name prefix like "(az0)": f alpha blend, a additive,
## c0 no culling, z0 no depth write, z1 no depth test, z2 both, b0 billboard.
static func apply_frame_flags(scene: Node, unshaded: bool) -> void:
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var flags := frame_flags(str(mi.name))
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			var mat := src.duplicate() as StandardMaterial3D if src else StandardMaterial3D.new()
			if unshaded:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			if flags.has("f"):
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if flags.has("a"):
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			if flags.has("c0"):
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			if flags.has("z0") or flags.has("z2"):
				mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			if flags.has("z1") or flags.has("z2"):
				mat.no_depth_test = true
			if flags.has("b0"):
				mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mi.set_surface_override_material(i, mat)

static func frame_flags(frame_name: String) -> Array[String]:
	var out: Array[String] = []
	if not frame_name.begins_with("("):
		return out
	var i := 1
	while i < frame_name.length() and frame_name[i] != ")":
		var ch := frame_name[i]
		if ch in ["c", "z", "b"] and i + 1 < frame_name.length() and frame_name[i + 1].is_valid_int():
			out.append(ch + frame_name[i + 1])
			i += 1
		elif ch in ["f", "a"]:
			out.append(ch)
		i += 1
	return out

static func place_sky(sky: Node3D, camera: Camera3D) -> void:
	sky.global_transform = Transform3D(MechView.G * Basis.from_scale(Vector3(1, 1, -1) * SKY_SCALE), camera.position)

## Damage::put_image_only: weapon/font_hit.x (your shot landed) or font_damage.x (you were
## hit), placed with an identity matrix, so no scale and no rotation beyond the axis mapping.
static func font_marker(root: Node3D, at: Vector2, hit: bool) -> void:
	spawn_effect(root, FONT_HIT if hit else FONT_DAMAGE, MechView.G * Basis.from_scale(Vector3(1, 1, -1)), at, FONT_TIME)

## rc_map::crashed_with_wall: weapon/wall_crash.x launched from the edge point, facing out
## along the wall normal with up toward the camera.
static func wall_crash(root: Node3D, at: Vector2, normal: Vector2) -> void:
	var z := Vector3(normal.x, 0, normal.y).normalized()
	var y := Vector3(0, -1, 0)
	var x := y.cross(z).normalized()
	var b := MechView.G * Basis(x, y, z) * Basis.from_scale(Vector3(1, 1, -1)) * Basis.from_scale(Vector3.ONE * Original.SCALE)
	spawn_effect(root, WALL_CRASH, b, at, 1.5)

## An effect model (the_projectile_manager.add): its animation plays once and its particle
## frames run their scripts. Freed after life seconds, when the scripts have run out.
static func spawn_effect(root: Node3D, path: String, basis: Basis, at: Vector2, life := 2.0) -> Node3D:
	if not _effect_scenes.has(path):
		_effect_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _effect_scenes[path]
	if scene == null:
		return null
	var fx := scene.instantiate() as Node3D
	root.add_child(fx)
	fx.transform = Transform3D(basis, Original.to_godot(at))
	MechView.play_effect(fx, false)
	ParticleFX.attach_all(fx, true)
	var timer := fx.get_tree().create_timer(life)
	timer.timeout.connect(fx.queue_free)
	return fx

## Default placement for effect files: the axis mapping and HAHA_SCALE_VAL.
static func effect_basis(scale := Original.SCALE) -> Basis:
	return MechView.G * Basis.from_scale(Vector3(1, 1, -1) * scale)

## An effect turned to a mech's facing: projectile_manager.add(name, pos, dir, up (0, -1, 0)),
## a look-at frame along the facing, with HAHA_SCALE_VAL like the other effects (inferred).
static func facing_effect_basis(facing_deg: int) -> Basis:
	var d := Original.vec2_from_deg(facing_deg)
	var z := Vector3(d.x, 0, d.y)
	var up := Vector3(0, -1, 0)
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return MechView.G * Basis(x, y, z) * Basis.from_scale(Vector3(1, 1, -1) * Original.SCALE)

## A bullet's bullet_dead_xfile where it hit or ran out.
static func hit_flash(root: Node3D, at: Vector2, path := HIT_FLASH) -> void:
	spawn_effect(root, path, effect_basis(), at)

## rcPlayer::update under 10% life: particle01/part_explosion.x at a random offset.
static func low_health_spark(root: Node3D, at: Vector2) -> void:
	spawn_effect(root, PART_EXPLOSION, effect_basis(1.0), at)

## Zeid::damage(DAMAGE_EXPLOSION2_RESULT): anim/explo2_result.x placed with
## matrixDefaultRotation (RotZ 90, no scale) and weapon/character_explo.x, whose particles
## make the burst.
static func knockout_explosion(root: Node3D, at: Vector2) -> void:
	var b := MechView.G * Basis(Vector3(0, 0, 1), deg_to_rad(90)) * Basis.from_scale(Vector3(1, 1, -1))
	spawn_effect(root, EXPLOSION, b, at, 2.5)
	spawn_effect(root, CHARACTER_EXPLO, effect_basis(1.0), at, 2.5)

## SwordEffectState::update: weapon/sword_hit.x at a mech the swing reached.
static func sword_hit(root: Node3D, at: Vector2) -> void:
	spawn_effect(root, SWORD_HIT, effect_basis(1.0), at)
