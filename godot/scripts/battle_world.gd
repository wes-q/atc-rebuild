class_name BattleWorld
extends RefCounted
## Scenery and effects for the battle scene: lights, camera, the original sky, the reference
## grid, booster flames, hit flashes and the knockout explosion.

const SKY := "res://assets/original/map/b_map01_skymap.gltf"
const HIT_FLASH := "res://assets/original/zeid/bullet_sr3_boom.gltf"
const EXPLOSION := "res://assets/original/fx/explo2_result.gltf"
const SKY_SCALE := 100.0

static var _hit_scene: PackedScene
static var _explosion_scene: PackedScene

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

	# skybox::render: the original sky model is re-centred on the camera every frame.
	# Scaled out beyond the arena so it never covers the mechs; from the centre it looks the same.
	var sky: Node3D = null
	if ResourceLoader.exists(SKY):
		sky = (load(SKY) as PackedScene).instantiate() as Node3D
		sky.name = "Sky"
		root.add_child(sky)
		for n in sky.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
				var mat := src.duplicate() as StandardMaterial3D if src else StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				if str(mi.name).begins_with("(z)") or str(mi.name).begins_with("(a)"):
					mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				mi.set_surface_override_material(i, mat)
		MechView.play_effect(sky, true)
		place_sky(sky, camera)

	# Faint reference grid on the plane so movement reads against something. Not original art.
	var grid := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	grid.mesh = plane
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://scripts/grid.gdshader")
	grid.material_override = gmat
	grid.position = Vector3(0, -20, 0)
	root.add_child(grid)
	return {"camera": camera, "sky": sky}

static func place_sky(sky: Node3D, camera: Camera3D) -> void:
	sky.transform = Transform3D(MechView.G * Basis.from_scale(Vector3(1, 1, -1) * SKY_SCALE), camera.position)

## Bullet impact, also used for the low-health sparks (rcPlayer::update part_explosion).
static func hit_flash(root: Node3D, at: Vector2, size := 1.0) -> void:
	if _hit_scene == null:
		_hit_scene = load(HIT_FLASH)
	var fx := _hit_scene.instantiate() as Node3D
	root.add_child(fx)
	fx.position = Original.to_godot(at)
	fx.scale = Vector3.ONE * Original.SCALE * size
	var tw := fx.create_tween()
	tw.tween_property(fx, "scale", Vector3.ONE * Original.SCALE * size * 2.0, 0.25)
	tw.tween_callback(fx.queue_free)

## Zeid::damage(DAMAGE_EXPLOSION2_RESULT): explo2_result.x placed with matrixDefaultRotation
## (RotZ 90, no scale), plus a particle burst standing in for character_explo.x, whose
## particles are defined by script.
static func knockout_explosion(root: Node3D, at: Vector2) -> void:
	if _explosion_scene == null:
		_explosion_scene = load(EXPLOSION)
	var fx := _explosion_scene.instantiate() as Node3D
	root.add_child(fx)
	var b := MechView.G * Basis(Vector3(0, 0, 1), deg_to_rad(90)) * Basis.from_scale(Vector3(1, 1, -1))
	fx.transform = Transform3D(b, Original.to_godot(at))
	MechView.play_effect(fx, false)
	var timer := fx.get_tree().create_timer(1.2)
	timer.timeout.connect(fx.queue_free)

	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.amount = 70
	burst.lifetime = 0.7
	burst.explosiveness = 0.9
	burst.direction = Vector3(0, 1, 0)
	burst.spread = 180.0
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 140.0
	burst.gravity = Vector3.ZERO
	burst.damping_min = 40.0
	burst.damping_max = 80.0
	burst.mesh = _glow_quad(Color(1.0, 0.7, 0.35, 1.0), 14.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 0.9, 1))
	ramp.set_color(1, Color(1, 0.3, 0.1, 0))
	burst.color_ramp = ramp
	root.add_child(burst)
	burst.position = Original.to_godot(at)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

## Placeholder booster flame. The original's particle scripts come in a later milestone.
static func booster_flame(point: Node3D) -> CPUParticles3D:
	var fx := CPUParticles3D.new()
	fx.emitting = false
	fx.amount = 60
	fx.lifetime = 0.22
	fx.local_coords = false
	fx.direction = Vector3(0, 0, 1)
	fx.spread = 12.0
	fx.initial_velocity_min = 90.0
	fx.initial_velocity_max = 160.0
	fx.gravity = Vector3.ZERO
	fx.scale_amount_min = 1.0
	fx.scale_amount_max = 1.8
	fx.mesh = _glow_quad(Color(0.45, 0.8, 1.0, 0.9), 7.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(0.2, 0.5, 1.0, 0))
	fx.color_ramp = ramp
	point.add_child(fx)
	return fx

static func _glow_quad(color: Color, size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	glow.gradient = g
	m.albedo_texture = glow
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = m
	return quad
