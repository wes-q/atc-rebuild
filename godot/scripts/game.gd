extends Node3D
## Battle scene. Practice against a target dummy, or two players over the network.
##
## Networking follows the original client: each player simulates their own mech and broadcasts
## its state (the move protocol), shots are broadcast as events, and the player who is hit
## decides the damage (weapon_mode_parameter: DAMAGE_DETERMINE_HITTEN_PLAYER for the SR-3).
##
##   godot --path godot                     menu
##   godot --path godot -- practice         target dummy
##   godot --path godot -- host             player 1, waits on port 7777
##   godot --path godot -- join 127.0.0.1   player 2
## Add "autopilot" to any of these for the scripted demo.

const SKY := "res://assets/original/map/b_map01_skymap.gltf"
const BOOM := "res://assets/original/zeid/bullet_sr3_boom.gltf"
const SKY_SCALE := 100.0
const PORT := 7777
const SPAWNS := [Vector2(-150, 0), Vector2(150, 0)]
const SPAWN_FACING := [0, 180]
const DUMMY_ID := -1
const RESPAWN_TIME := 2.0 ## placeholder until the original knockout rules (milestone 3)

class Mech:
	var id: int
	var slot: int
	var sim: MechSim
	var view: MechView
	var fx: Array[CPUParticles3D] = []
	var local := false
	var respawn := 0.0

var camera: Camera3D
var sky: Node3D
var hud: Hud
var menu: StartMenu
var mechs: Dictionary = {} ## id -> Mech
var local_id := 0
var mode := ""
var bullets: Array[Bullet] = []
var depth := Original.CAMERA_AUTO_MAX
var cam_from := Vector3.ZERO ## camera position in original space
var _boom_scene: PackedScene
var _autopilot := OS.get_cmdline_user_args().has("autopilot")
var _clock := 0.0
var _status := ""
var _netlog := OS.get_cmdline_user_args().has("netlog")
var _log_timer := 0.0

func _ready() -> void:
	_build_world()
	hud = Hud.new()
	add_child(hud)
	_boom_scene = load(BOOM)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var args := OS.get_cmdline_user_args()
	if args.has("host"):
		start_host()
	elif args.has("join"):
		var i := args.find("join")
		start_join(args[i + 1] if i + 1 < args.size() else "127.0.0.1")
	elif args.has("practice") or _autopilot:
		start_practice()
	else:
		_show_menu("")

# --- Modes ------------------------------------------------------------------------------

func _show_menu(message: String) -> void:
	_set_mode("")
	if menu == null:
		menu = StartMenu.new()
		add_child(menu)
		menu.practice_chosen.connect(start_practice)
		menu.host_chosen.connect(start_host)
		menu.join_chosen.connect(start_join)
	menu.visible = true
	menu.show_message(message)

func _hide_menu() -> void:
	if menu:
		menu.visible = false

func _set_mode(m: String) -> void:
	mode = m
	var titles := {"": "", "practice": ": practice", "host": ": player 1 (host)", "join": ": player 2"}
	DisplayServer.window_set_title("ATC Raycrash" + titles.get(m, ""))

func start_practice() -> void:
	_reset_world()
	_set_mode("practice")
	_hide_menu()
	local_id = 1
	_spawn(local_id, 0, true)
	_spawn(DUMMY_ID, 1, false)
	_status = "Practice. Esc: menu"

func start_host() -> void:
	_reset_world()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		_show_menu("Could not host on port %d (error %d). Is another copy already hosting?" % [PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	_set_mode("host")
	_hide_menu()
	local_id = multiplayer.get_unique_id()
	_spawn(local_id, 0, true)
	_status = "Hosting on %s port %d. Waiting for player 2." % [", ".join(_lan_addresses()), PORT]

func start_join(address: String) -> void:
	_reset_world()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		_show_menu("Could not start connecting to %s (error %d)." % [address, err])
		return
	multiplayer.multiplayer_peer = peer
	_set_mode("join")
	_hide_menu()
	_status = "Connecting to %s port %d..." % [address, PORT]

func _reset_world() -> void:
	for id in mechs.keys():
		_remove_mech(id)
	for b in bullets:
		b.queue_free()
	bullets.clear()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	local_id = 0
	_clock = 0.0

func _lan_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	return out

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and mode != "":
		_reset_world()
		_show_menu("")

# --- Network events ---------------------------------------------------------------------

func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	_spawn(local_id, 1, true)
	_status = "Connected. You are player 2."

func _on_connection_failed() -> void:
	_reset_world()
	_show_menu("Could not connect. Check the host is running and the address is right.")

func _on_server_disconnected() -> void:
	_reset_world()
	_show_menu("The host left the match.")

func _on_peer_connected(id: int) -> void:
	if not mechs.has(id):
		_spawn(id, 0 if id == 1 else 1, false)
	if mode == "host":
		_status = "Player 2 joined."

func _on_peer_disconnected(id: int) -> void:
	_remove_mech(id)
	if mode == "host":
		_status = "Player 2 left. Waiting for player 2."

## Owner's state, every physics tick. Unreliable: a newer one replaces a lost one.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_state(state: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not mechs.has(id):
		_spawn(id, 0 if id == 1 else 1, false)
	(mechs[id] as Mech).sim.apply_snapshot(state)

## A shot, from the shooter's muzzle. Reliable so both screens show every bullet.
@rpc("any_peer", "call_remote", "reliable")
func _net_fire(origin: Vector2, deg: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mechs.has(id):
		var m: Mech = mechs[id]
		if not m.view.is_attack_playing():
			m.view.play_attack()
		_add_bullet(origin, deg, m)

# --- Mechs ------------------------------------------------------------------------------

func _spawn(id: int, slot: int, local: bool) -> void:
	var m := Mech.new()
	m.id = id
	m.slot = slot
	m.local = local
	m.sim = MechSim.new()
	m.sim.reset_at(SPAWNS[slot], SPAWN_FACING[slot])
	m.view = MechView.new()
	add_child(m.view)
	m.view.set_skin(slot)
	for p in m.view.booster_points:
		m.fx.append(_make_booster_fx(p))
	if local:
		m.sim.fired.connect(func(_o: Vector2, deg: int) -> void: _on_local_fired(m, deg))
		cam_from = Vector3(m.sim.pos.x, -depth, m.sim.pos.y)
	mechs[id] = m

func _remove_mech(id: int) -> void:
	if mechs.has(id):
		(mechs[id] as Mech).view.queue_free()
		mechs.erase(id)

func _local() -> Mech:
	return mechs.get(local_id)

func _nearest_enemy(of: Mech) -> Mech:
	var best: Mech = null
	for m: Mech in mechs.values():
		if m != of and (best == null or m.sim.pos.distance_to(of.sim.pos) < best.sim.pos.distance_to(of.sim.pos)):
			best = m
	return best

# --- Frame ------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	for m: Mech in mechs.values():
		if m.local:
			var intent := _read_intent(m) if m.sim.life > 0 else MechSim.Intent.new()
			m.sim.step(intent, dt)
			_tick_respawn(m, dt)
			if mode == "host" or mode == "join":
				_net_state.rpc(m.sim.snapshot())
		elif m.id == DUMMY_ID:
			var it := MechSim.Intent.new()
			var me := _local()
			it.aim = me.sim.pos if me else Vector2.ZERO
			m.sim.step(it, dt)
			_tick_respawn(m, dt)
		else:
			m.sim.step_remote(dt)
	_step_bullets(dt)
	if _netlog:
		_log_timer += dt
		if _log_timer >= 1.0:
			_log_timer = 0.0
			var parts: Array[String] = []
			for m: Mech in mechs.values():
				parts.append("%s%d pos=(%d,%d) hp=%d" % ["me" if m.local else "peer", m.id, m.sim.pos.x, m.sim.pos.y, m.sim.life])
			print("[%s] " % mode, "  ".join(parts))

func _tick_respawn(m: Mech, dt: float) -> void:
	if m.sim.life > 0:
		return
	if m.respawn <= 0.0:
		m.respawn = RESPAWN_TIME
	m.respawn -= dt
	if m.respawn <= 0.0:
		m.sim.reset_at(SPAWNS[m.slot], SPAWN_FACING[m.slot])

func _process(dt: float) -> void:
	var me := _local()
	if me:
		_update_camera(me, dt)
	for m: Mech in mechs.values():
		_draw_mech(m)
	var enemy := _nearest_enemy(me) if me else null
	hud.refresh(me.sim if me else null, enemy.sim if enemy else null, depth, dt, _status)

func _draw_mech(m: Mech) -> void:
	m.view.place(m.sim.pos, m.sim.facing)
	m.view.visible = m.sim.life > 0 or fmod(Time.get_ticks_msec() / 1000.0, 0.2) < 0.1
	for fx in m.fx:
		fx.emitting = m.sim.acc_flag and m.sim.life > 0
		if fx.emitting:
			fx.direction = fx.global_transform.basis.inverse() * Original.to_godot(-m.sim.move_dir).normalized()
	if m.view.is_attack_playing():
		return
	var clip := m.sim.move_clip()
	if clip < 0:
		m.view.play_stand()
	else:
		m.view.play_move(clip)

func _read_intent(m: Mech) -> MechSim.Intent:
	if _autopilot:
		return _autopilot_intent(m)
	var it := MechSim.Intent.new()
	it.left = Input.is_action_pressed("move_left")
	it.right = Input.is_action_pressed("move_right")
	it.up = Input.is_action_pressed("move_up")
	it.down = Input.is_action_pressed("move_down")
	it.boost = Input.is_action_pressed("boost")
	it.fire = Input.is_action_pressed("fire")
	it.aim = _mouse_on_plane(m)
	return it

## rcPlayerManager::updaterotation: ray from the camera through the cursor onto the plane.
func _mouse_on_plane(m: Mech) -> Vector2:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return m.sim.pos
	return Original.to_plane(from + dir * (-from.y / dir.y))

# --- Shots ------------------------------------------------------------------------------

func _on_local_fired(m: Mech, deg: int) -> void:
	if not m.view.is_attack_playing():
		m.view.play_attack()
	var origin := m.view.muzzle_plane_pos()
	_add_bullet(origin, deg, m)
	if mode == "host" or mode == "join":
		_net_fire.rpc(origin, deg)

func _add_bullet(origin: Vector2, deg: int, shooter: Mech) -> void:
	var b := Bullet.new()
	add_child(b)
	b.setup(origin, deg, shooter.sim)
	b.set_meta("shooter", shooter.id)
	bullets.append(b)

## Every screen flies every bullet. Damage is decided by whoever owns the mech that was hit:
## the local player for their own mech, this machine for the practice dummy.
func _step_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		var alive := b.advance(dt)
		var shooter: int = b.get_meta("shooter")
		for m: Mech in mechs.values():
			if not alive:
				break
			if m.id == shooter or m.sim.life <= 0:
				continue
			if b.plane_pos.distance_to(m.sim.pos) >= b.radius + m.sim.crash_radius:
				continue
			alive = false
			_boom(b.plane_pos)
			hud.show_hit(camera.unproject_position(Original.to_godot(m.sim.pos)))
			if m.local or m.id == DUMMY_ID:
				m.sim.life = maxi(0, m.sim.life - b.power)
		if not alive:
			b.queue_free()
			bullets.remove_at(i)

func _boom(at: Vector2) -> void:
	var fx := _boom_scene.instantiate() as Node3D
	add_child(fx)
	fx.position = Original.to_godot(at)
	fx.scale = Vector3.ONE * Original.SCALE
	var tw := create_tween()
	tw.tween_property(fx, "scale", Vector3.ONE * Original.SCALE * 2.0, 0.25)
	tw.tween_callback(fx.queue_free)

# --- Camera and world -------------------------------------------------------------------

## World::update: battle depth eases toward 3x the nearest enemy's distance, clamped to
## 235..AUTO_CAMERA (500 by default in option.ini), at most 4 units per frame.
func _auto_depth_target(me: Mech) -> float:
	var enemy := _nearest_enemy(me)
	if enemy == null:
		return Original.CAMERA_AUTO_MAX
	return clampf(me.sim.pos.distance_to(enemy.sim.pos) * 3.0, Original.CAMERA_AUTO_MIN, Original.CAMERA_AUTO_MAX)

func _update_camera(me: Mech, dt: float) -> void:
	if Input.is_action_pressed("zoom_in"):
		depth = maxf(Original.CAMERA_AUTO_MIN, depth - Original.CAMERA_ZOOM_RATE * dt)
	elif Input.is_action_pressed("zoom_out"):
		depth = minf(Original.CAMERA_DEPTH_MAX, depth + Original.CAMERA_ZOOM_RATE * dt)
	else:
		var want := _auto_depth_target(me)
		if absf(want - depth) > 5.0:
			depth = move_toward(depth, want, minf(dt, 0.004) * 1000.0)
	# View_Manager::update_camera_frame: from moves toward (x, -depth, z) at 2x per second.
	var to := Vector3(me.sim.pos.x, 0, me.sim.pos.y)
	var from2 := Vector3(to.x, -depth, to.z)
	var gap := from2 - cam_from
	cam_from = cam_from + gap * minf(1.0, dt * Original.CAMERA_FOLLOW) if gap.length_squared() > 2.0 else from2
	# Original (x, y, z) -> Godot (x, -y, -z).
	camera.position = Vector3(cam_from.x, -cam_from.y, -cam_from.z)
	camera.look_at(Vector3(to.x, 0, -to.z), Vector3(0, 0, -1))
	if sky:
		sky.transform = Transform3D(MechView.G * Basis.from_scale(Vector3(1, 1, -1) * SKY_SCALE), camera.position)

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
	camera.position = Vector3(0, depth, 0)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))

	# skybox::render: the original sky model is re-centred on the camera every frame.
	# Scaled out beyond the arena so it never covers the mechs; from the centre it looks the same.
	if ResourceLoader.exists(SKY):
		sky = (load(SKY) as PackedScene).instantiate() as Node3D
		sky.name = "Sky"
		add_child(sky)
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
		sky.transform = Transform3D(MechView.G * Basis.from_scale(Vector3(1, 1, -1) * SKY_SCALE), camera.position)

	# Faint reference grid on the plane so movement reads against something. Not original art.
	var grid := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	grid.mesh = plane
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://scripts/grid.gdshader")
	grid.material_override = gmat
	grid.position = Vector3(0, -20, 0)
	add_child(grid)

## Placeholder booster flame. The original's particle scripts come in a later milestone.
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

# --- Autopilot --------------------------------------------------------------------------

## Scripted duel for recordings and checks. With an enemy: close to firing range, strafe
## around them with boost bursts, fire when in range. Without one: a fixed walk-boost-fire route.
func _autopilot_intent(m: Mech) -> MechSim.Intent:
	_clock += get_physics_process_delta_time()
	var it := MechSim.Intent.new()
	var enemy := _nearest_enemy(m)
	if enemy == null:
		var t := fmod(_clock, 6.0)
		it.aim = m.sim.pos + Vector2(100, 0)
		it.right = t > 1.0 and t < 3.0
		it.up = t >= 3.0 and t < 4.5
		it.boost = t >= 3.0 and t < 4.5
		it.fire = t > 1.5
		return it
	var to := enemy.sim.pos - m.sim.pos
	var dist := to.length()
	it.aim = enemy.sim.pos
	var side := 1.0 if fmod(_clock + m.slot * 2.5, 5.0) < 2.5 else -1.0
	var want := to.normalized() if dist > 260.0 else (-to.normalized() if dist < 120.0 else Vector2(-to.y, to.x).normalized() * side)
	it.right = want.x > 0.35
	it.left = want.x < -0.35
	it.up = want.y > 0.35
	it.down = want.y < -0.35
	it.boost = fmod(_clock + m.slot, 3.0) < 1.2 and m.sim.booster_gage > 600.0
	it.fire = dist < m.sim.weapon.bullet_speed * m.sim.weapon.life
	return it
