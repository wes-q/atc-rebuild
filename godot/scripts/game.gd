extends Node3D
## Milestone 1: the Zeid walking, boosting and firing the SR-3 with the original numbers,
## seen through the original's top-down battle camera, with a stationary target to shoot.

const SKY := "res://assets/original/map/b_map01_skymap.gltf"
const BOOM := "res://assets/original/zeid/bullet_sr3_boom.gltf"
const TARGET_START := Vector2(260, 140)
const RESPAWN_TIME := 2.0

var camera: Camera3D
var sky: Node3D
const SKY_SCALE := 100.0
var hud: Hud
var player_sim := MechSim.new()
var player_view: MechView
var target_sim := MechSim.new()
var target_view: MechView
var bullets: Array[Bullet] = []
var booster_fx: Array[CPUParticles3D] = []
var depth := 500.0
var cam_from := Vector3.ZERO ## camera position in original space
var target_respawn := 0.0
var _boom_scene: PackedScene
var _autopilot := OS.get_cmdline_user_args().has("autopilot")
var _clock := 0.0

func _ready() -> void:
	_build_world()
	player_view = MechView.new()
	add_child(player_view)
	target_view = MechView.new()
	add_child(target_view)
	target_sim.pos = TARGET_START
	target_sim.facing = 180
	player_sim.fired.connect(_on_player_fired)
	for p in player_view.booster_points:
		booster_fx.append(_make_booster_fx(p))
	hud = Hud.new()
	add_child(hud)
	_boom_scene = load(BOOM)
	depth = _auto_depth_target()
	cam_from = Vector3(player_sim.pos.x, -depth, player_sim.pos.y)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.0, 0.0, 0.02)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, 25, 0)
	sun.light_energy = 1.1
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = Original.CAMERA_FOV
	camera.near = 3.3
	camera.far = 5000.0 * 3.3
	add_child(camera)

	# skybox::render: the original sky model is re-centred on the camera every frame.
	# Scaled out beyond the arena so it never covers the mechs; from the centre it looks the same.
	if ResourceLoader.exists(SKY):
		sky = (load(SKY) as PackedScene).instantiate() as Node3D
		sky.name = "Sky"
		add_child(sky)
		for m in sky.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
				var mat := src.duplicate() as StandardMaterial3D if src else StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				if str(mi.name).begins_with("(z)") or str(mi.name).begins_with("(a)"):
					mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				mi.set_surface_override_material(i, mat)

	# Faint reference grid on the plane so movement reads against something.
	var grid := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	grid.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/grid.gdshader")
	grid.material_override = mat
	grid.position = Vector3(0, -20, 0)
	add_child(grid)

func _make_booster_fx(point: Node3D) -> CPUParticles3D:
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
	var quad := QuadMesh.new()
	quad.size = Vector2(7.0, 7.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.45, 0.8, 1.0, 0.9)
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
	fx.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(0.2, 0.5, 1.0, 0))
	fx.color_ramp = ramp
	point.add_child(fx)
	return fx

func _physics_process(dt: float) -> void:
	var intent := _read_intent()
	player_sim.step(intent, dt)
	_step_target(dt)
	_step_bullets(dt)

func _process(dt: float) -> void:
	_update_camera(dt)
	_draw_mech(player_view, player_sim)
	_draw_mech(target_view, target_sim)
	for fx in booster_fx:
		fx.emitting = player_sim.acc_flag
		if fx.emitting:
			var back := -player_sim.move_dir
			fx.direction = fx.global_transform.basis.inverse() * Original.to_godot(back).normalized()
	hud.refresh(player_sim, target_sim, depth, dt)

func _read_intent() -> MechSim.Intent:
	if _autopilot:
		return _autopilot_intent()
	var it := MechSim.Intent.new()
	it.left = Input.is_action_pressed("move_left")
	it.right = Input.is_action_pressed("move_right")
	it.up = Input.is_action_pressed("move_up")
	it.down = Input.is_action_pressed("move_down")
	it.boost = Input.is_action_pressed("boost")
	it.fire = Input.is_action_pressed("fire")
	it.aim = _mouse_on_plane()
	return it

## rcPlayerManager::updaterotation: ray from the camera through the cursor onto the plane.
func _mouse_on_plane() -> Vector2:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return player_sim.pos
	var t := -from.y / dir.y
	return Original.to_plane(from + dir * t)

## World::update: battle depth eases toward 3x the nearest enemy's distance, clamped to
## 235..AUTO_CAMERA (500 by default in option.ini), at most 1000 units/s capped per frame.
func _auto_depth_target() -> float:
	var len := player_sim.pos.distance_to(target_sim.pos)
	return clampf(len * 3.0, Original.CAMERA_AUTO_MIN, Original.CAMERA_AUTO_MAX)

func _update_camera(dt: float) -> void:
	if Input.is_action_pressed("zoom_in"):
		depth = maxf(Original.CAMERA_AUTO_MIN, depth - Original.CAMERA_ZOOM_RATE * dt)
	elif Input.is_action_pressed("zoom_out"):
		depth = minf(Original.CAMERA_DEPTH_MAX, depth + Original.CAMERA_ZOOM_RATE * dt)
	else:
		var want := _auto_depth_target()
		var step := minf(dt, 0.004) * 1000.0
		if absf(want - depth) > 5.0:
			depth = move_toward(depth, want, step)
	# View_Manager::update_camera_frame: from moves toward (x, -depth, z) at 2x per second.
	var to := Vector3(player_sim.pos.x, 0, player_sim.pos.y)
	var from2 := Vector3(to.x, -depth, to.z)
	var gap := from2 - cam_from
	cam_from = cam_from + gap * minf(1.0, dt * Original.CAMERA_FOLLOW) if gap.length_squared() > 2.0 else from2
	# Original (x, y, z) -> Godot (x, -y, -z).
	camera.position = Vector3(cam_from.x, -cam_from.y, -cam_from.z)
	camera.look_at(Vector3(to.x, 0, -to.z), Vector3(0, 0, -1))
	if sky:
		sky.transform = Transform3D(MechView.G * Basis.from_scale(Vector3(1, 1, -1) * SKY_SCALE), camera.position)

func _draw_mech(view: MechView, sim: MechSim) -> void:
	view.place(sim.pos, sim.facing)
	view.visible = sim.life > 0 or fmod(target_respawn, 0.2) < 0.1
	if view.is_attack_playing():
		return
	var clip := sim.move_clip()
	if clip < 0:
		view.play_stand()
	else:
		view.play_move(clip)

func _on_player_fired(_origin: Vector2, deg: int) -> void:
	if not player_view.is_attack_playing():
		player_view.play_attack()
	var b := Bullet.new()
	add_child(b)
	b.setup(player_view.muzzle_plane_pos(), deg, player_sim)
	bullets.append(b)

func _step_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		var alive := b.advance(dt)
		if alive and target_sim.life > 0 and b.plane_pos.distance_to(target_sim.pos) < b.radius + target_sim.crash_radius:
			target_sim.life = maxi(0, target_sim.life - b.power)
			_boom(b.plane_pos)
			hud.show_hit(camera.unproject_position(Original.to_godot(target_sim.pos)))
			if target_sim.life == 0:
				target_respawn = RESPAWN_TIME
			alive = false
		if not alive:
			b.queue_free()
			bullets.remove_at(i)

func _step_target(dt: float) -> void:
	# Stands still and turns to face the player.
	var it := MechSim.Intent.new()
	it.aim = player_sim.pos
	target_sim.step(it, dt)
	if target_respawn > 0.0:
		target_respawn -= dt
		if target_respawn <= 0.0:
			target_sim.life = target_sim.life_max

func _boom(at: Vector2) -> void:
	var fx := _boom_scene.instantiate() as Node3D
	add_child(fx)
	fx.position = Original.to_godot(at)
	fx.scale = Vector3.ONE * Original.SCALE
	var tw := create_tween()
	tw.tween_property(fx, "scale", Vector3.ONE * Original.SCALE * 2.0, 0.25)
	tw.tween_callback(fx.queue_free)

## Scripted demo for recording and checks: walk, boost in several directions, fire.
func _autopilot_intent() -> MechSim.Intent:
	_clock += get_physics_process_delta_time()
	var t := _clock
	var it := MechSim.Intent.new()
	it.aim = target_sim.pos
	if t < 1.0:
		pass
	elif t < 3.0:
		it.right = true
		it.fire = t > 1.5
	elif t < 4.5:
		it.up = true
		it.right = true
		it.boost = true
	elif t < 6.0:
		it.left = true
		it.boost = true
		it.fire = true
	elif t < 7.5:
		it.down = true
		it.fire = true
	elif t < 8.5:
		it.aim = player_sim.pos + Vector2(-200, 50)
	else:
		it.right = true
		it.boost = true
		it.fire = true
	return it
