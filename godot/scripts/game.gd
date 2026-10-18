extends Node3D
## Battle scene. Practice against a target dummy, or two players over the network.
##
## Networking follows the original client: each player simulates their own mech and broadcasts
## its state (the move protocol), shots are broadcast as events, and the player who is hit
## decides the damage (weapon_mode_parameter: DAMAGE_DETERMINE_HITTEN_PLAYER for the SR-3).
##
## Match rules follow the original free-for-all (GameRoom::is_game_end, mode 0): no respawns,
## the match ends as soon as one mech is left, and the clock counts up. Starting the next round
## automatically after the results is this recreation's own addition; the original returned
## players to the room lobby.
##
##   godot --path godot                     menu
##   godot --path godot -- practice         target dummy
##   godot --path godot -- host             player 1, waits on port 7777
##   godot --path godot -- join 127.0.0.1   player 2
## Add "autopilot" to any of these for the scripted duel, "netlog" for position logs.

const PORT := 7777
const SPAWNS := [Vector2(-150, 0), Vector2(150, 0)]
const SPAWN_FACING := [0, 180]
const DUMMY_ID := -1
const RESULT_DELAY := 1.5 ## after the last knockout, so the explosion plays first
const RESULT_TIME := 6.0 ## results on screen before the next round

class Mech:
	var id: int
	var slot: int
	var sim: MechSim
	var view: MechView
	var fx: Array[CPUParticles3D] = []
	var local := false
	var death_played := false
	var exploded := false
	var spark_time := 0.0

## Per-round tallies, kept the same on every machine from hit and knockout messages.
class Stats:
	var kills := 0
	var damage := 0

	## RayCrashServer::user_damage_to_point at equal grades: damage / 10 * 330 / 400.
	func points() -> int:
		return int(damage / 10.0 * 330.0 / 400.0)

var camera: Camera3D
var sky: Node3D
var hud: Hud
var menu: StartMenu
var mechs: Dictionary = {} ## id -> Mech
var stats: Dictionary = {} ## id -> Stats
var wins: Dictionary = {} ## id -> rounds won this session
var local_id := 0
var mode := ""
var bullets: Array[Bullet] = []
var depth := Original.CAMERA_AUTO_MAX
var cam_from := Vector3.ZERO ## camera position in original space
var round_active := false
var round_number := 0
var round_time := 0.0 ## World game_time: counts up from the start of the round
var _end_timer := -1.0 ## host only: counts down to sending the result
var _next_round_timer := -1.0 ## host only: counts down to the next round
var _autopilot := OS.get_cmdline_user_args().has("autopilot")
var _clock := 0.0
var _status := ""
var _netlog := OS.get_cmdline_user_args().has("netlog")
## Test option "hp=<n>": start every mech with n armour points so knockouts come quickly.
var _test_hp := _arg_int("hp=")
## Test option "capture=<dir>": saves 30 frames per second of real-time play as JPEGs.
var _capture_dir := _arg_str("capture=")
var _capture_time := 0.0
var _capture_index := 0
var _log_timer := 0.0

func _ready() -> void:
	var built := BattleWorld.build(self, depth)
	camera = built.camera
	sky = built.sky
	hud = Hud.new()
	add_child(hud)
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

static func _arg_str(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""

static func _arg_int(prefix: String) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return int(a.trim_prefix(prefix))
	return 0

func _networked() -> bool:
	return mode == "host" or mode == "join"

func _is_authority() -> bool:
	return mode == "host" or mode == "practice"

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
	_begin_round(1)

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
	_clear_bullets()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	local_id = 0
	_clock = 0.0
	round_active = false
	round_number = 0
	wins.clear()
	stats.clear()
	_end_timer = -1.0
	_next_round_timer = -1.0
	hud.hide_result()

func _clear_bullets() -> void:
	for b in bullets:
		b.queue_free()
	bullets.clear()

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

# --- Rounds -----------------------------------------------------------------------------

## Everyone back to their spawn at full health, tallies cleared, clock from zero.
func _begin_round(number: int) -> void:
	round_number = number
	round_active = true
	round_time = 0.0
	_end_timer = -1.0
	_next_round_timer = -1.0
	_clear_bullets()
	stats.clear()
	for m: Mech in mechs.values():
		m.sim.reset_at(SPAWNS[m.slot], SPAWN_FACING[m.slot])
		if _test_hp > 0:
			m.sim.life_max = _test_hp
			m.sim.life = _test_hp
		m.death_played = false
		m.exploded = false
		m.view.visible = true
		m.view.play_stand()
		stats[m.id] = Stats.new()
	hud.hide_result()

@rpc("authority", "call_remote", "reliable")
func _net_round_start(number: int) -> void:
	_begin_round(number)

## Host (or practice): ends the round once one mech or none is left standing.
func _check_round_end() -> void:
	if not round_active or not _is_authority() or _end_timer >= 0.0:
		return
	if mode == "host" and mechs.size() < 2:
		return
	var alive: Array[int] = []
	for m: Mech in mechs.values():
		if m.sim.life > 0:
			alive.append(m.id)
	if alive.size() <= 1:
		_end_timer = RESULT_DELAY
		round_active = false

func _send_result() -> void:
	var winner := -999
	for m: Mech in mechs.values():
		if m.sim.life > 0:
			winner = m.id
	var tally := {}
	for id in stats:
		tally[id] = [(stats[id] as Stats).kills, (stats[id] as Stats).damage]
	_show_result(winner, tally)
	if mode == "host":
		_net_round_result.rpc(winner, tally)
	_next_round_timer = RESULT_TIME

@rpc("authority", "call_remote", "reliable")
func _net_round_result(winner: int, tally: Dictionary) -> void:
	_show_result(winner, tally)

func _show_result(winner: int, tally: Dictionary) -> void:
	round_active = false
	if winner != -999:
		wins[winner] = int(wins.get(winner, 0)) + 1
	var title := "DRAW"
	if winner == local_id:
		title = "YOU WIN"
	elif winner != -999:
		title = "YOU LOSE"
	var lines: Array[String] = []
	for m: Mech in _mechs_in_slot_order():
		var t: Array = tally.get(m.id, [0, 0])
		var s := Stats.new()
		s.damage = int(t[1])
		lines.append("%-10s  kills %d   damage %4d   points %3d   rounds won %d" % [
			_mech_label(m), int(t[0]), s.damage, s.points(), int(wins.get(m.id, 0))])
	hud.show_result(title, lines, "Round %d    time %s    next round in %d s" % [round_number, Hud.clock_text(round_time), int(RESULT_TIME)])

func _mechs_in_slot_order() -> Array:
	var list := mechs.values()
	list.sort_custom(func(a: Mech, b: Mech) -> bool: return a.slot < b.slot)
	return list

func _mech_label(m: Mech) -> String:
	if m.id == DUMMY_ID:
		return "Target"
	return ("You, P%d" if m.id == local_id else "P%d") % (m.slot + 1)

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
		var next := round_number + 1
		_begin_round(next)
		_net_round_start.rpc_id(id, next)

func _on_peer_disconnected(id: int) -> void:
	_remove_mech(id)
	if mode == "host":
		_status = "Player 2 left. Waiting for player 2."
		round_active = false
		hud.hide_result()

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

## The victim's machine reports a hit it decided (World::damage_respond).
@rpc("any_peer", "call_remote", "reliable")
func _net_hit(attacker: int, amount: int, remaining: int) -> void:
	var victim := multiplayer.get_remote_sender_id()
	_record_hit(victim, attacker, amount, remaining)

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
		m.fx.append(BattleWorld.booster_flame(p))
	if local:
		m.sim.fired.connect(func(_o: Vector2, deg: int) -> void: _on_local_fired(m, deg))
		cam_from = Vector3(m.sim.pos.x, -depth, m.sim.pos.y)
	mechs[id] = m
	stats[id] = Stats.new()

func _remove_mech(id: int) -> void:
	if mechs.has(id):
		(mechs[id] as Mech).view.queue_free()
		mechs.erase(id)
		stats.erase(id)

func _local() -> Mech:
	return mechs.get(local_id)

func _nearest_enemy(of: Mech, alive_only := true) -> Mech:
	var best: Mech = null
	for m: Mech in mechs.values():
		if m == of or (alive_only and m.sim.is_dead_complete):
			continue
		if best == null or m.sim.pos.distance_to(of.sim.pos) < best.sim.pos.distance_to(of.sim.pos):
			best = m
	return best

# --- Frame ------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if round_active:
		round_time += dt
	for m: Mech in mechs.values():
		if m.local:
			var can_act := round_active and m.sim.life > 0
			var intent := _read_intent(m) if can_act else MechSim.Intent.new()
			m.sim.step(intent, dt)
			if _networked():
				_net_state.rpc(m.sim.snapshot())
		elif m.id == DUMMY_ID:
			var it := MechSim.Intent.new()
			var me := _local()
			it.aim = me.sim.pos if me else Vector2.ZERO
			m.sim.step(it, dt)
		else:
			m.sim.step_remote(dt)
	_step_bullets(dt)
	_check_round_end()
	if _end_timer >= 0.0:
		_end_timer -= dt
		if _end_timer < 0.0:
			_send_result()
	if _next_round_timer >= 0.0:
		_next_round_timer -= dt
		if _next_round_timer < 0.0:
			var next := round_number + 1
			_begin_round(next)
			if mode == "host":
				_net_round_start.rpc(next)
	if _netlog:
		_log_timer += dt
		if _log_timer >= 1.0:
			_log_timer = 0.0
			var parts: Array[String] = []
			for m: Mech in mechs.values():
				parts.append("%s%d pos=(%d,%d) hp=%d" % ["me" if m.local else "peer", m.id, m.sim.pos.x, m.sim.pos.y, m.sim.life])
			print("[%s r%d %s] " % [mode, round_number, "on" if round_active else "off"], "  ".join(parts))

func _process(dt: float) -> void:
	var me := _local()
	if me:
		_update_camera(me, dt)
	for m: Mech in mechs.values():
		_draw_mech(m, dt)
	var enemy := _nearest_enemy(me, false) if me else null
	hud.refresh(me.sim if me else null, enemy.sim if enemy else null, depth, dt, _status, round_time)
	if _capture_dir != "":
		_capture_time += dt
		if _capture_time >= 1.0 / 30.0:
			_capture_time = 0.0
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("%s/f%05d.jpg" % [_capture_dir, _capture_index], 0.85)
			_capture_index += 1

func _draw_mech(m: Mech, dt: float) -> void:
	m.view.place(m.sim.pos, m.sim.facing)
	for fx in m.fx:
		fx.emitting = m.sim.acc_flag and m.sim.life > 0
		if fx.emitting:
			fx.direction = fx.global_transform.basis.inverse() * Original.to_godot(-m.sim.move_dir).normalized()
	# Knockout: explosion pose, then the debris explosion and the mech is no longer drawn.
	if m.sim.is_dead and not m.death_played:
		m.death_played = true
		m.view.play_death()
	if m.sim.is_dead_complete:
		if not m.exploded:
			m.exploded = true
			BattleWorld.knockout_explosion(self, m.sim.pos)
		m.view.visible = false
		return
	m.view.visible = true
	_low_health_sparks(m, dt)
	if m.sim.is_dead or m.view.is_attack_playing() or m.view.is_reacting():
		return
	var clip := m.sim.move_clip()
	if clip < 0:
		m.view.play_stand()
	else:
		m.view.play_move(clip)

## rcPlayer::update: under 10% life, small explosions at random offsets, more often as life drops.
func _low_health_sparks(m: Mech, dt: float) -> void:
	if m.sim.life <= 0 or m.sim.life >= int(m.sim.life_max * 0.1):
		return
	m.spark_time -= dt
	if m.spark_time >= 0.0:
		return
	var offset := Vector2(randf_range(-10, 10), randf_range(-10, 10))
	BattleWorld.hit_flash(self, m.sim.pos + offset, 0.8)
	m.spark_time = float(randi() % 2) * 0.5 + 0.5 * 10.0 * float(m.sim.life) / float(m.sim.life_max)

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

# --- Shots and hits ---------------------------------------------------------------------

func _on_local_fired(m: Mech, deg: int) -> void:
	if not m.view.is_attack_playing():
		m.view.play_attack()
	var origin := m.view.muzzle_plane_pos()
	_add_bullet(origin, deg, m)
	if _networked():
		_net_fire.rpc(origin, deg)

func _add_bullet(origin: Vector2, deg: int, shooter: Mech) -> void:
	var b := Bullet.new()
	add_child(b)
	b.setup(origin, deg, shooter.sim)
	b.set_meta("shooter", shooter.id)
	bullets.append(b)

## Every screen flies every bullet. Damage is decided by whoever owns the mech that was hit:
## the local player for their own mech, this machine for the practice dummy. Other screens
## only show the impact and wait for the victim's report.
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
			BattleWorld.hit_flash(self, b.plane_pos)
			if round_active and (m.local or m.id == DUMMY_ID):
				m.sim.take_damage(b.power)
				_record_hit(m.id, shooter, b.power, m.sim.life)
				if _networked() and m.local:
					_net_hit.rpc(shooter, b.power, m.sim.life)
		if not alive:
			b.queue_free()
			bullets.remove_at(i)

## Applies a hit report on this machine: tallies, the victim's life, the hit reaction and the
## HIT or DAMAGE marker (World::damage_respond).
func _record_hit(victim_id: int, attacker_id: int, amount: int, remaining: int) -> void:
	if not mechs.has(victim_id):
		return
	var victim: Mech = mechs[victim_id]
	victim.sim.life = remaining
	if stats.has(attacker_id):
		(stats[attacker_id] as Stats).damage += amount
	if remaining > 0:
		victim.view.play_damage()
	elif stats.has(attacker_id) and attacker_id != victim_id:
		(stats[attacker_id] as Stats).kills += 1
	if victim_id == local_id:
		hud.show_marker(camera.unproject_position(Original.to_godot(victim.sim.pos)), "DAMAGE!")
	elif attacker_id == local_id:
		hud.show_marker(camera.unproject_position(Original.to_godot(victim.sim.pos)), "HIT!")

# --- Camera -----------------------------------------------------------------------------

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
		BattleWorld.place_sky(sky, camera)

# --- Autopilot --------------------------------------------------------------------------

## Scripted duel for recordings and checks. With an enemy: close to firing range, strafe
## around them with boost bursts, fire when in range. Without one: a walk-boost-fire route.
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
