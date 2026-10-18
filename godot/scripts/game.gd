extends Node3D
## Battle scene. Practice against a target dummy, or two players over the network.
##
## Networking follows the original client: each player simulates their own mech and broadcasts
## its state (the move protocol), shots are broadcast as events, and the player who is hit
## decides the damage (weapon_mode_parameter: DAMAGE_DETERMINE_HITTEN_PLAYER for the SR-3).
##
## Match rules follow the original (GameRoom::is_game_end): no respawns, the round ends as soon
## as one mech or one side is left, and the clock counts up. A networked game is played from
## the original game room (page_game_room.lua): the room master starts it with a five-second
## countdown, and after the results everyone goes back to the room. Practice starts its next
## round on its own.
##
##   godot --path godot                     menus
##   godot --path godot -- practice         target dummy
##   godot --path godot -- host             a room on port 7777
##   godot --path godot -- join 127.0.0.1   into that room
## Add "map=<id>" (space, city, sky, gsession, escape) to pick the arena, "autopilot" for the
## scripted duel, "netlog" for position logs.

const PORT := 7777
## Players in one match, the host included (MAX_PC_IN_ROOM, MAX_PLAYER).
const MAX_PLAYERS := 12
const DUMMY_ID := -1
const NO_TARGET := 0
## _apply_hit without a direction: no guard test.
const NO_FROM := Vector2(INF, INF)
const CHARACTER_BLOCK := "res://assets/original/x/weapon/character_block.gltf"
const SHIELD_CRASH := "res://assets/original/x/weapon/shield_crash.gltf"
## The combo flashes have no clip of their own to time them (inferred).
const COMBO_EFFECT_TIME := 1.0
const DEFENCE_DOWN := "res://assets/original/x/weapon01/defence_down.gltf"
const RESULT_DELAY := 1.5 ## after the last knockout, so the explosion plays first
const RESULT_TIME := 6.0 ## results on screen before the next round

class Mech:
	var id: int
	var slot: int
	var sim: MechSim
	var view: MechView
	var body := "zeid"
	## Equipped weapons in slot order, as the owner chose them (empty: the body's defaults).
	var weapons: Array = []
	var local := false
	## Room.NONE in free-for-all, Room.RED or Room.BLUE in team battle (from the slot).
	var team := Room.NONE
	## Lock-on target's mech id, 0 for none (LockOnSystem). Sent with the state.
	var lock_target := 0
	## Target taken when the current burst started (pt_send_shoot's target_id).
	var burst_target := 0
	var prev_speed_state := 0
	var prev_move_dir := Vector2.ZERO
	var death_played := false
	var exploded := false
	var spark_time := 0.0

## Per-round tallies, kept the same on every machine from hit and knockout messages.
class Stats:
	var kills := 0
	var damage := 0

	## RayCrashServer::user_damage_to_point at equal grades: damage / 10 * 330 / 400, doubled
	## in a free-for-all that started with three or more (att_point *= 2).
	func points(double := false) -> int:
		return int(damage / 10.0 * 330.0 / 400.0) * (2 if double else 1)

var camera: Camera3D
var sky: Node3D
var env: WorldEnvironment
var sun: DirectionalLight3D
var map: BattleMap
var map_node: Node3D
## Arena for practice and hosting. A joining player uses the host's.
var map_choice := "space"
## Start point index per slot this round (RayCrashServer::position_set: random, no repeats).
var spawn_points: Array[int] = [0, 1]
## Peer id -> slot, kept by the host and sent to everyone whenever it changes. Slots are
## handed out lowest first and decide the start point, name and colour scheme.
var roster: Dictionary = {}
## Host: start the countdown on its own once this many players are in the room (0: wait for
## START or Enter).
var _auto_start := _arg_int("players=")
## The room's mode (byTeam): team battle, chosen by the host and sent with the roster.
var team_mode := OS.get_cmdline_user_args().has("teams")
## The room (page_game_room): its name, password (kept by the host, never sent), beginner flag
## and number as the room list showed it. The map is map_choice, the game type team_mode.
var room_name := ""
var room_password := ""
var room_beginner := false
var room_number := 1
## Peer id -> player name and body, from each player's hello, sent with the roster.
var names: Dictionary = {}
var bodies: Dictionary = {}
## The password a joining player sends with their hello.
var _join_password := ""
## In the game room between battles (the front end shows it), and whether a battle is on.
var _in_room := false
var _match_on := false
## Players who came in during a battle and wait in the room for the next one.
var _sitting_out: Dictionary = {}
## Movement states every machine sends, by players in the room (Room.state_rate). full_rate is
## the room master's override to 60 a second (test option "fullrate", or /rate full in the
## room chat); the host's choice travels with the roster.
var full_rate := OS.get_cmdline_user_args().has("fullrate")
var _state_tick := 0
var _announced_rate := 0
## Host: the start countdown's next number (5 to 1), -1 when not counting, and its clock.
var _countdown := -1
var _countdown_timer := 0.0
## Mechs in the round when it began, for the free-for-all points rule.
var round_starters := 0
## After your mech is gone the camera follows another player (set_next_camera).
var _watch_id := 0
var _rng := RandomNumberGenerator.new()
var hud: Hud
## On-screen controls on a touch screen, or with the "touch" test option on a desktop.
var touch: TouchControls
var _touch_mode := DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("touch")
var sound: GameSound
var menu: StartMenu
## The original's login, character select, main menu and options (scripts/front_end.gd).
var front: FrontEnd
var mechs: Dictionary = {} ## id -> Mech
var stats: Dictionary = {} ## id -> Stats
var wins: Dictionary = {} ## id -> rounds won this session
var local_id := 0
var mode := ""
var bullets: Array[Bullet] = []
## Sword swings still able to land, run on the attacker's machine: [Mech, elapsed, weapon].
var swings: Array = []
## Immediate-weapon shots in the air (collision_type 4).
var beams: Array[Beam] = []
## The body for practice and hosting or joining, and the practice target's.
var body_choice := "zeid"
## Your four weapons in slot order (sword, gun, heavy, special), from the menu or
## loadout=1,3,4,17; empty for the body's defaults.
var loadout_choice: Array = []
var dummy_body := ""
## is_skip_crash rounds fired so far, by shooter (only 1 in skip_crash_count + 1 can hit).
var _skip_counter := {}
var _prev_fire_local := false
var _shake_time := 0.0
var _shake_power := 0
var _shake_tick := 0.0
var _shake_sign := 1
var _prev_lockon_key := false
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
## Practice: the target raises its guard whenever it can (for testing blocks).
var _dummy_guard := OS.get_cmdline_user_args().has("dummy_guard")
## Autopilot: raise the guard for 2 s of every 8 s weapon cycle.
var _autoguard := OS.get_cmdline_user_args().has("autoguard")
## Autopilot: with a sword in reach, enter command combos (forward, click; then back,
## forward, click for the finisher).
var _autocombos := OS.get_cmdline_user_args().has("combos")
## Test option: keep the Tab player panel open.
var _hold_tab := OS.get_cmdline_user_args().has("tab")
## Test option "hp=<n>": start every mech with n armour points so knockouts come quickly.
var _test_hp := _arg_int("hp=")
## Practice: the target starts this many units in front of you each round (for testing).
var _dummy_near := _arg_int("dummy_near=")
## Autopilot: keep to this weapon slot (1 to 4) instead of cycling.
var _autopilot_slot := _arg_int("slot=")
## Test option "capture=<dir>": saves 30 frames per second of real-time play as JPEGs.
var _capture_dir := _arg_str("capture=")
var _capture_time := 0.0
var _capture_index := 0
var _log_timer := 0.0

func _ready() -> void:
	var built := BattleWorld.build(self, depth)
	camera = built.camera
	env = built.env
	sun = built.sun
	var map_arg := _arg_str("map=")
	if map_arg != "":
		map_choice = map_arg
	var body_arg := _arg_str("body=")
	if body_arg in Bodies.NAMES:
		body_choice = body_arg
	var loadout_arg := _arg_str("loadout=")
	if loadout_arg != "":
		for part in loadout_arg.split(","):
			loadout_choice.append(int(part))
	var dummy_arg := _arg_str("dummy=")
	if dummy_arg in Bodies.NAMES:
		dummy_body = dummy_arg
	hud = Hud.new()
	if _touch_mode:
		# The test option drives the touch controls with the mouse, one finger at a time.
		if OS.get_cmdline_user_args().has("touch"):
			Input.emulate_touch_from_mouse = true
		touch = TouchControls.new()
		touch.visible = false
		add_child(touch)
		touch.menu_pressed.connect(_leave_match)
		touch.start_pressed.connect(_try_start)
		touch.team_pressed.connect(_ask_change_team)
		hud.touch_help = true
	sound = GameSound.new()
	add_child(sound)
	sound.enabled = not OS.get_cmdline_user_args().has("mute")
	front = FrontEnd.new()
	front.sound = sound
	# Test option "profile=<name>": keep the name, body, options and loadouts in
	# user://<name>.cfg instead of the player's own profile.
	if _arg_str("profile=") != "":
		front.profile_path = "user://%s.cfg" % _arg_str("profile=")
	front.visible = false
	add_child(front)
	front._load_profile()
	# Test option "name=<player>": play under another name without saving it.
	if _arg_str("name=") != "":
		front.player_name = _arg_str("name=")
	if _arg_str("body=") == "":
		body_choice = front.body
	if _arg_str("loadout=") == "":
		loadout_choice = front.loadout(body_choice)
	front.practice_requested.connect(func() -> void:
		_take_front_choices()
		start_practice())
	front.shop_view.connect(_shop_stage)
	front.shop_attack.connect(func() -> void:
		if _shop_robot:
			_shop_robot.play_attack())
	front.room_create.connect(func(n: String, pw: String, teams: bool, beginner: bool) -> void:
		_take_front_choices()
		start_host(n, pw, teams, beginner))
	front.room_join.connect(func(address: String, pw: String) -> void:
		_take_front_choices()
		start_join(address, pw))
	front.room_start.connect(_try_start)
	front.room_map.connect(_change_map)
	front.room_slot.connect(_ask_slot)
	front.room_chat.connect(_send_chat)
	front.room_exit.connect(func() -> void: _back_to_rooms(""))
	add_child(hud)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var args := OS.get_cmdline_user_args()
	if args.has("host"):
		# Test options "room=<name>": the room's name (otherwise "<player>'s room");
		# "password=<pw>": a locked room, or the password to join one with.
		start_host(_arg_str("room="), _arg_str("password="))
	elif args.has("join"):
		var i := args.find("join")
		start_join(args[i + 1] if i + 1 < args.size() else "127.0.0.1", _arg_str("password="))
	elif args.has("practice") or _autopilot:
		start_practice()
	elif args.has("classic"):
		_show_classic("")
	else:
		_set_mode("")
		_menu_backdrop()
		# Test option: front=character, main or option opens that page directly.
		match _arg_str("front="):
			"character":
				front.show_character()
			"main":
				front.show_main_menu()
			"option":
				front.set_shown(true)
				front.show_options()
			"shop":
				front.show_shop()
			_:
				front.show_login()

## The body from character select and its loadout from the shop (loadout= on the command
## line wins).
func _take_front_choices() -> void:
	body_choice = front.body
	if _arg_str("loadout=") == "":
		loadout_choice = front.loadout(body_choice)

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

## Out of a match: back to the original's main menu, with any message in its message box.
func _show_menu(message: String) -> void:
	_set_mode("")
	_status = ""
	if menu:
		menu.visible = false
	if touch:
		touch.visible = false
	_menu_backdrop()
	front.show_main_menu(message)

# --- Item shop stage (page_game_shop) -------------------------------------------------------

## The item shop's 3D scene behind its page: the item_shop map's sky (map01/ui_bg01.x) and
## lights, and the robot holding the chosen weapon. The page's middle frame is see-through;
## the robot stands in it. The original's viewer camera is not in the archive, so the view
## (from the battle camera's side, tilted toward you, turned by the rotate buttons) is this
## recreation's (inferred).
const SHOP_SKY := "res://assets/original/map/shop/ui_bg01.gltf"
## test_map.lua item_shop init: diffuse 2.0, ambient 0.4, direction (-1, -1.2, -1).
const SHOP_DIFFUSE := 2.0
const SHOP_AMBIENT := 0.4
const SHOP_LIGHT_DIR := Vector3(-1.0, -1.2, -1.0)
## The robot's place on the 800x600 page: the middle of the viewer frame (17, 59, 494 x 517).
const SHOP_ROBOT_AT := Vector2(264, 300)
const SHOP_CAMERA_DISTANCE := 150.0
const SHOP_TILT := -20.0 ## degrees the robot leans toward the camera
const SHOP_FACING := 200 ## the battle facing it is shown from
const SHOP_TURN_SPEED := 90.0 ## degrees a second while a rotate button is held
const SHOP_ZOOM_SPEED := 120.0 ## units a second while a zoom button is held
var _shop_robot: MechView
var _shop_sky: Node3D
var _shop_yaw := 0.0
var _shop_distance := SHOP_CAMERA_DISTANCE
var _shop_saved_light := []

## The shop page's robot, rebuilt when the weapons change.
func _shop_stage(body: String, weapons: Array, slot: int) -> void:
	if _shop_sky == null:
		_shop_enter()
	var ids := Bodies.loadout(body, weapons)
	if _shop_robot == null or _shop_robot.body != body or _shop_robot.weapon_ids != ids:
		if _shop_robot:
			_shop_robot.queue_free()
		_shop_robot = MechView.new(body, ids)
		add_child(_shop_robot)
	_shop_robot.set_weapon(slot)

func _shop_enter() -> void:
	if map_node:
		for c in map_node.get_children():
			(c as Node3D).visible = false
	_shop_sky = (load(SHOP_SKY) as PackedScene).instantiate() as Node3D if ResourceLoader.exists(SHOP_SKY) else Node3D.new()
	add_child(_shop_sky)
	BattleWorld.apply_frame_flags(_shop_sky, true)
	MechView.play_effect(_shop_sky, true)
	_shop_saved_light = [sun.transform, sun.light_color, sun.light_energy,
		env.environment.ambient_light_color, env.environment.ambient_light_energy]
	var d := SHOP_LIGHT_DIR
	var dir := Vector3(d.x, -d.y, -d.z).normalized()
	sun.look_at_from_position(Vector3.ZERO, dir, Vector3(0, 0, -1))
	sun.light_color = Color.WHITE
	sun.light_energy = SHOP_DIFFUSE * BattleWorld.LIGHT_SCALE
	env.environment.ambient_light_color = Color(SHOP_AMBIENT, SHOP_AMBIENT, SHOP_AMBIENT)
	env.environment.ambient_light_energy = BattleWorld.AMBIENT_SCALE
	_shop_yaw = 0.0
	_shop_distance = SHOP_CAMERA_DISTANCE

## Out of the shop: the robot and sky go, the lights and the menus' backdrop come back.
func _shop_leave() -> void:
	if _shop_robot:
		_shop_robot.queue_free()
		_shop_robot = null
	_shop_sky.queue_free()
	_shop_sky = null
	sun.transform = _shop_saved_light[0]
	sun.light_color = _shop_saved_light[1]
	sun.light_energy = _shop_saved_light[2]
	env.environment.ambient_light_color = _shop_saved_light[3]
	env.environment.ambient_light_energy = _shop_saved_light[4]
	if mode == "":
		_menu_backdrop()

## Every frame in the shop: the camera, and the robot turned and placed in the viewer frame.
func _shop_frame(dt: float) -> void:
	if front.page != "shop" or not front.visible:
		_shop_leave()
		return
	if front.shop:
		_shop_yaw = fmod(_shop_yaw + front.shop.turn * SHOP_TURN_SPEED * dt + 360.0, 360.0)
		_shop_distance = clampf(_shop_distance - front.shop.zoom * SHOP_ZOOM_SPEED * dt, 70.0, 300.0)
	camera.position = Vector3(0, _shop_distance, 0)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	BattleWorld.place_sky(_shop_sky, camera)
	if _shop_robot:
		var px := front.screen.position + SHOP_ROBOT_AT * front.screen.scale
		_shop_robot.position = camera.project_position(px, _shop_distance)
		# The battle pose seen from above, stood up a quarter turn about the screen's upright
		# axis, turned about that axis by the rotate buttons and leaned toward the camera.
		var stand := Basis(Vector3(0, 0, 1), deg_to_rad(_shop_yaw - 90.0))
		_shop_robot.model.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(SHOP_TILT)) * stand * MechView.facing_basis(SHOP_FACING), Vector3.ZERO)
		if not _shop_robot.is_attack_playing() and not _shop_robot.is_drawing():
			_shop_robot.play_stand()

## Behind the front end: the space map's sky alone, seen from 320 units up (the menus'
## interface_map loads map01's skymap and no objects; the camera sits at (0, -320, 0)).
func _menu_backdrop() -> void:
	_use_map("space")
	if map_node:
		for c in map_node.get_children():
			(c as Node3D).visible = c == sky
	depth = 320.0
	cam_from = Vector3(0, -depth, 0)
	camera.position = Vector3(0, depth, 0)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	if sky:
		BattleWorld.place_sky(sky, camera)

## The classic menu (host, join, map, body, loadout) that Battle and Shop open until the
## original room list and shop page replace them.
func _show_classic(message: String) -> void:
	_set_mode("")
	front.set_shown(false)
	if menu == null:
		menu = StartMenu.new()
		add_child(menu)
		menu.practice_chosen.connect(start_practice)
		menu.host_chosen.connect(start_host)
		menu.join_chosen.connect(start_join)
		menu.select_map(map_choice)
		menu.select_body(body_choice, loadout_choice)
		menu.select_mode(team_mode)
		menu.back_chosen.connect(func() -> void:
			body_choice = menu.body_id
			loadout_choice = menu.loadout
			front.body = body_choice
			front.save_profile()
			_show_menu(""))
	menu.select_body(body_choice, loadout_choice)
	menu.visible = true
	menu.show_message(message)
	if touch:
		touch.visible = false

func _hide_menu() -> void:
	if touch:
		touch.visible = true
	front.set_shown(false)
	# The arena comes back in full after the menus' sky-only backdrop.
	if map_node:
		for c in map_node.get_children():
			(c as Node3D).visible = true
	# The classic menu's choices count when it is the one starting the game.
	if menu and menu.visible:
		menu.visible = false
		map_choice = menu.map_id
		body_choice = menu.body_id
		loadout_choice = menu.loadout
		team_mode = menu.team_mode
		front.body = body_choice

## Builds the arena if it is not the one already showing.
func _use_map(id: String) -> void:
	if map and map.id == id:
		return
	var next := BattleMap.load_map(id)
	if next == null:
		return
	if map_node:
		map_node.queue_free()
	map = next
	var built := BattleWorld.build_map(self, map, env, sun)
	map_node = built.node
	sky = built.sky
	for m: Mech in mechs.values():
		_attach_map(m)

## The original ran map collision for the local player only (rc_map::update).
func _attach_map(m: Mech) -> void:
	m.sim.map = map if (m.local or m.id == DUMMY_ID) else null

## Random distinct start points for each slot, like position_set for a free-for-all room.
## Room.start_points for everyone in the room, by slot (practice: the dummy is slot 1).
func _pick_spawns() -> Array[int]:
	var slots: Array = []
	for m: Mech in mechs.values():
		slots.append(m.slot)
	return Room.start_points(slots, team_mode, _rng)

func _spawn_pos(slot: int) -> Vector2:
	if map == null or map.spawns.is_empty():
		return Vector2(-150 + 300 * slot, 0)
	var point := spawn_points[slot] if slot < spawn_points.size() and spawn_points[slot] >= 0 else slot
	return map.spawns[point % map.spawns.size()]

## The server sent no start direction: MoveData's muzdir and movdir start at 0.
func _spawn_facing(_slot: int) -> int:
	return 0

func _set_mode(m: String) -> void:
	mode = m
	var titles := {"": "", "practice": ": practice", "host": ": player 1 (host)", "join": ": joining"}
	var title: String = titles.get(m, "")
	if m == "join" and roster.has(local_id):
		title = ": player %d" % (int(roster[local_id]) + 1)
	DisplayServer.window_set_title("ATC Raycrash" + title)

func start_practice() -> void:
	_reset_world()
	_set_mode("practice")
	_hide_menu()
	# Practice is you and a target, free-for-all.
	team_mode = false
	_use_map(map_choice)
	local_id = 1
	_spawn(local_id, 0, true, body_choice, loadout_choice)
	_spawn(DUMMY_ID, 1, false, dummy_body if dummy_body != "" else _random_other_body(body_choice))
	_status = "Practice on %s. %s: menu" % [map.title, _key("Esc", "MENU")]
	_begin_round(1, map.id, _pick_spawns())

## Creates a room and becomes its master (request_create_room). Teams and beginner default to
## the classic menu's or the command line's choice.
func start_host(new_name := "", password := "", teams: Variant = null, beginner := false) -> void:
	_hide_menu()
	_reset_world()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		_back_to_rooms("Could not host on port %d (error %d). Is another copy already hosting?" % [PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	if teams != null:
		team_mode = teams
	room_name = new_name if new_name != "" else "%s's room" % _player_name()
	room_password = password
	room_beginner = beginner
	room_number = 1
	_set_mode("host")
	local_id = multiplayer.get_unique_id()
	roster = {local_id: 0}
	names = {local_id: _player_name()}
	bodies = {local_id: body_choice}
	_spawn(local_id, 0, true, body_choice, loadout_choice)
	front.clear_room_console()
	_to_room()
	_room_notice_local("%s %s" % [names[local_id], front.text("text_29")])
	# Where others can reach this room when the room list does not find it.
	front.room_console_add("System : Hosting on %s port %d." % [", ".join(_lan_addresses()), PORT], FrontEnd.NOTICE)
	_host_status()

## Joins a room by its host's address (request_game_room_enter). The host answers the hello
## with the roster, or with why not.
func start_join(address: String, password := "") -> void:
	_hide_menu()
	_reset_world()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		_back_to_rooms("Could not start connecting to %s (error %d)." % [address, err])
		return
	multiplayer.multiplayer_peer = peer
	_join_password = password
	room_number = front.joined_number
	_set_mode("join")
	_status = "Connecting to %s port %d..." % [address, PORT]
	if front.page == "room_list":
		front.set_shown(true)
		front.message("%s (%s)" % [front.text("text_25"), address])

func _reset_world() -> void:
	# The menus' music carries on through the room list and the rooms.
	if _match_on or mode == "practice":
		sound.stop_bgm()
	for id in mechs.keys():
		_remove_mech(id)
	_clear_bullets()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	local_id = 0
	roster.clear()
	_clock = 0.0
	round_active = false
	round_number = 0
	wins.clear()
	stats.clear()
	_end_timer = -1.0
	_next_round_timer = -1.0
	hud.hide_result()
	names.clear()
	bodies.clear()
	_sitting_out.clear()
	_in_room = false
	_match_on = false
	_countdown = -1
	_announced_rate = 0
	room_password = ""
	front.lan.stop()

func _clear_bullets() -> void:
	for b in bullets:
		b.queue_free()
	bullets.clear()
	swings.clear()
	# The step 17 states end with the round.
	_ticks.clear()
	for id in _leeches.keys():
		_drop_leech(id)
	for t: Dictionary in _tethers:
		(t["node"] as Node3D).queue_free()
	_tethers.clear()
	_fading.clear()

func _lan_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	return out

func _exit_tree() -> void:
	# The menus' animated cursor and the shared UI caches go before the renderer does.
	Input.set_custom_mouse_cursor(null)
	OriginalUI.release_statics()

## Android's back button: out of a match to the menu, and from the menu out of the app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if front and front.visible:
			front.go_back()
		elif menu and menu.visible:
			_show_menu("")
		elif mode != "":
			_leave_match()
		else:
			get_tree().quit()

## Esc or MENU in a battle: practice goes back to the main menu, a networked game leaves the
## room for the room list.
func _leave_match() -> void:
	if _networked():
		_back_to_rooms("")
	else:
		_reset_world()
		_show_menu("")

## Out of the room (ui_request_room_exit), or turned away: the room list, with any message.
func _back_to_rooms(message: String) -> void:
	if _netlog:
		print("[room] back to the room list: ", message)
	_reset_world()
	_set_mode("")
	_status = ""
	if touch:
		touch.visible = false
	if not sound.is_playing_bgm():
		sound.play_bgm(FrontEnd.BGM_MENU)
	_menu_backdrop()
	front.show_room_list(message)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and mode != "" and not _in_room:
		_leave_match()
	# The host starts the match once everyone is in (the room master's start button).
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_try_start()
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_T:
		_ask_change_team()
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_M:
		sound.enabled = not sound.enabled
		if not sound.enabled:
			sound.stop_bgm()

## The room master's START (or Enter): starts the countdown, or calls it off while it runs
## (onPushGameStartButton). A game needs two players, and in team battle even sides.
func _can_start_now() -> bool:
	return mode == "host" and _in_room and Room.can_start(roster.values(), team_mode)

func _try_start() -> void:
	if mode != "host" or not _in_room:
		return
	if _countdown >= 0:
		_cancel_countdown()
	elif _can_start_now():
		_countdown = 5
		_countdown_timer = 0.0
	elif roster.size() < 2:
		front.message(front.text("text_12"))
	else:
		front.message(front.text("text_15"))

func _cancel_countdown() -> void:
	if _countdown < 0:
		return
	_countdown = -1
	_net_countdown.rpc(0)
	_on_countdown(0)

## Host, every physics tick: one number a second, then the battle.
func _step_countdown(dt: float) -> void:
	if _countdown < 0:
		return
	if not Room.can_start(roster.values(), team_mode):
		_cancel_countdown()
		return
	_countdown_timer -= dt
	if _countdown_timer > 0.0:
		return
	if _countdown == 0:
		_countdown = -1
		_start_next_round()
		return
	_net_countdown.rpc(_countdown)
	_on_countdown(_countdown)
	_countdown -= 1
	_countdown_timer = 1.0

@rpc("authority", "call_remote", "reliable")
func _net_countdown(n: int) -> void:
	_on_countdown(n)

## handle_start_game_ready: "5 seconds remaining" down to 1 with its sound, in the room's
## console; 0 is the master calling it off (text_21).
func _on_countdown(n: int) -> void:
	if n <= 0:
		front.room_console_add(front.text("text_21"), FrontEnd.ALERT)
		return
	sound.play("sound/ui/countdown %d-%02d" % [n, 6 - n])
	front.room_console_add(front.text("text_%d" % (21 - n)), FrontEnd.NOTICE if n > 1 else FrontEnd.ALERT)

## T, or TEAM on a touch screen: move to the other side between rounds.
func _can_change_team_now() -> bool:
	return team_mode and _networked() and _in_room

func _ask_change_team() -> void:
	if not _can_change_team_now():
		return
	if mode == "host":
		_change_team(local_id)
	else:
		_net_change_team.rpc_id(1)

## A key's name in status lines, or its button on a touch screen.
func _key(key_name: String, button: String) -> String:
	return button if _touch_mode else key_name

# --- Rounds -----------------------------------------------------------------------------

## Everyone back to a start point at full health, tallies cleared, clock from zero.
func _begin_round(number: int, map_id: String, spawns: Array[int]) -> void:
	_hide_menu()
	_in_room = false
	_match_on = true
	_countdown = -1
	_sitting_out.clear()
	_use_map(map_id)
	spawn_points = spawns
	round_number = number
	round_active = true
	round_time = 0.0
	_end_timer = -1.0
	_next_round_timer = -1.0
	_clear_bullets()
	stats.clear()
	round_starters = mechs.size()
	_watch_id = local_id
	# Each original match started a random track from the first 19 of the BGM list.
	sound.play_battle_bgm()
	for m: Mech in mechs.values():
		m.sim.reset_at(_spawn_pos(m.slot), _spawn_facing(m.slot))
		if _test_hp > 0:
			m.sim.life_max = _test_hp
			m.sim.life = _test_hp
		m.death_played = false
		m.exploded = false
		m.view.visible = true
		m.view.set_weapon(Original.START_WEAPON, false)
		m.lock_target = NO_TARGET
		stats[m.id] = Stats.new()
		if m.local:
			# Start points are far apart, so the camera starts on the mech instead of gliding there.
			cam_from = Vector3(m.sim.pos.x, -depth, m.sim.pos.y)
			_update_camera(m, 0.0)
	var me := _local()
	if _dummy_near > 0 and me and mechs.has(DUMMY_ID):
		var d: Mech = mechs[DUMMY_ID]
		var at := me.sim.pos + Original.vec2_from_deg(me.sim.facing) * _dummy_near
		d.sim.reset_at(at, (me.sim.facing + 180) % 360)
	hud.hide_result()
	if _networked():
		# OnRoomStartGameReadyResult, then start_ready_go once the battle is up.
		front.room_console_add(front.text("text_22"), FrontEnd.ALERT)
		hud.ready_go()
		sound.play("sound/ui/ready go")
	if mode == "host":
		_host_status()
		_advertise()

@rpc("authority", "call_remote", "reliable")
func _net_round_start(number: int, map_id: String, spawns: Array) -> void:
	var typed: Array[int] = []
	for i in spawns:
		typed.append(int(i))
	_begin_round(number, map_id, typed)

## Host or practice: next round on the room's arena, fresh start points.
func _start_next_round() -> void:
	var next := round_number + 1
	var spawns := _pick_spawns()
	_begin_round(next, map_choice, spawns)
	if mode == "host":
		_net_round_start.rpc(next, map_choice, spawns)

## Host (or practice): ends the round once one mech or none is left standing.
func _check_round_end() -> void:
	if not round_active or not _is_authority() or _end_timer >= 0.0:
		return
	if mode == "host" and mechs.size() < 2:
		return
	if Room.round_over(_living_slots(), team_mode):
		_end_timer = RESULT_DELAY
		round_active = false

func _living_slots() -> Array:
	var out := []
	for m: Mech in mechs.values():
		if m.sim.life > 0:
			out.append(m.slot)
	return out

func _send_result() -> void:
	var slots := []
	for m: Mech in mechs.values():
		slots.append(m.slot)
	var winning := Room.winning_slots(slots, _living_slots(), team_mode)
	var winners: Array[int] = []
	for m: Mech in mechs.values():
		if m.slot in winning:
			winners.append(m.id)
	var tally := {}
	for id in stats:
		tally[id] = [(stats[id] as Stats).kills, (stats[id] as Stats).damage]
	_show_result(winners, tally)
	if mode == "host":
		_net_round_result.rpc(winners, tally)
	_next_round_timer = RESULT_TIME
	if mode == "host":
		_host_status()

## Host: the results have been up long enough. Practice plays on; a room goes back to the room.
func _results_done() -> void:
	if mode == "host":
		_net_to_room.rpc()
		_to_room()
	else:
		_start_next_round()

@rpc("authority", "call_remote", "reliable")
func _net_to_room() -> void:
	_to_room()

## The game room between battles: the arena's sky alone behind it, the mechs put away and
## the menus' music (page_game_room, Game_end).
func _to_room() -> void:
	_in_room = true
	_match_on = false
	round_active = false
	_end_timer = -1.0
	_next_round_timer = -1.0
	hud.hide_result()
	_clear_bullets()
	if touch:
		touch.visible = false
	for m: Mech in mechs.values():
		m.view.visible = false
	if map_node:
		for c in map_node.get_children():
			(c as Node3D).visible = c == sky
		depth = 320.0
		cam_from = Vector3(0, -depth, 0)
		camera.position = Vector3(0, depth, 0)
		camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
		if sky:
			BattleWorld.place_sky(sky, camera)
	else:
		_menu_backdrop()
	if not sound.is_playing_bgm() or sound.current_bgm != FrontEnd.BGM_MENU:
		sound.play_bgm(FrontEnd.BGM_MENU)
	# The battle hid the page; it comes back as it was, chat and all.
	if front.page == "room":
		front.set_shown(true)
		front.update_game_room(_room_view())
	else:
		front.show_game_room(_room_view())
	if mode == "host":
		_advertise()
		_host_status()
		_maybe_auto_start()

## Test option players=N: the master starts the countdown once N are in and the sides are even.
func _maybe_auto_start() -> void:
	if _auto_start > 0 and mode == "host" and _in_room and _countdown < 0 and roster.size() >= _auto_start and Room.can_start(roster.values(), team_mode):
		_countdown = 5
		_countdown_timer = 0.0

@rpc("authority", "call_remote", "reliable")
func _net_round_result(winners: Array, tally: Dictionary) -> void:
	_show_result(winners, tally)

## Players see win or lose: in team battle the whole side shares it, and with nobody left
## everyone loses (get_winners_team returns no team; there is no draw).
func _show_result(winners: Array, tally: Dictionary) -> void:
	round_active = false
	for id in winners:
		wins[int(id)] = int(wins.get(int(id), 0)) + 1
	var won := winners.has(local_id)
	var title := "YOU WIN" if won else "YOU LOSE"
	if team_mode and not winners.is_empty() and mechs.has(int(winners[0])):
		title += "    %s TEAM WINS" % ("RED" if (mechs[int(winners[0])] as Mech).team == Room.RED else "BLUE")
	# Victory music for the winner, defeat for everyone else (NetManager).
	sound.play_bgm(GameSound.BGM_VICTORY if won else GameSound.BGM_DEFEAT)
	var double := not team_mode and round_starters >= 3
	var next := "back to the room" if _networked() else "next round"
	var lines: Array[String] = []
	for m: Mech in _mechs_in_slot_order():
		var t: Array = tally.get(m.id, [0, 0])
		var s := Stats.new()
		s.damage = int(t[1])
		lines.append("%-14s  kills %d   damage %4d   points %3d   rounds won %d" % [
			_mech_label(m), int(t[0]), s.damage, s.points(double), int(wins.get(m.id, 0))])
	hud.show_result(title, lines, "Round %d    time %s    %s in %d s" % [round_number, Hud.clock_text(round_time), next, int(RESULT_TIME)])

func _mechs_in_slot_order() -> Array:
	var list := mechs.values()
	list.sort_custom(func(a: Mech, b: Mech) -> bool: return a.slot < b.slot)
	return list

## Name shown over a mech and in the HUD: the player's login name (the original showed
## account names), as the room's roster carries it.
func _mech_name(m: Mech) -> String:
	if m.id == DUMMY_ID:
		return "Target"
	if m.local:
		return _player_name()
	return str(names.get(m.id, "Player %d" % (m.slot + 1)))

func _player_name() -> String:
	return front.player_name if front and front.player_name != "" else "Player"

func _mech_label(m: Mech) -> String:
	if m.id == DUMMY_ID:
		return "Target"
	var label := _mech_name(m) + (" (you)" if m.id == local_id else "")
	match m.team:
		Room.RED:
			label += " red"
		Room.BLUE:
			label += " blue"
	return label

# --- Network events ---------------------------------------------------------------------

## Connected: say who we are; the host's roster brings our slot and everyone else's mech.
func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	_status = "Connected. Waiting for the room."
	_net_hello.rpc_id(1, _player_name(), _join_password, body_choice)

func _on_connection_failed() -> void:
	_back_to_rooms("Could not connect. Check the host is running and the address is right.")

## The master's machine is the room, so the room closes with it (the original passed the
## master's mark to another player instead; OnManagerChange).
func _on_server_disconnected() -> void:
	_back_to_rooms("The room master left, so the room closed.")

## Host: nothing until the newcomer's hello says who they are.
func _on_peer_connected(_id: int) -> void:
	pass

## Host: a newcomer's name, password and body (request_game_room_enter). A wrong password or
## a full room turns them away; otherwise they take a slot (Room.join_slot) and, during a
## battle, wait in the room for the next one.
@rpc("any_peer", "call_remote", "reliable")
func _net_hello(player_name: String, password: String, body: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mode != "host" or roster.has(id):
		return
	if room_password != "" and password != room_password:
		_refuse(id, front.system_text("Wrong_password"))
		return
	var slot := Room.join_slot(roster.values(), team_mode)
	if slot < 0:
		_refuse(id, front.system_text("Room_is_full"))
		return
	roster[id] = slot
	names[id] = player_name.strip_edges().left(15) if player_name.strip_edges() != "" else "Player %d" % (slot + 1)
	bodies[id] = body if body in Bodies.NAMES else "zeid"
	_spawn(id, slot, false, bodies[id])
	if _match_on:
		_sit_out(mechs[id])
	_send_roster()
	_room_notice("%s %s" % [names[id], front.text("text_29")])
	_refresh_room()
	_host_status()
	_advertise()
	_maybe_auto_start()

## Host: tell a newcomer why not, then let them go once the message is out.
func _refuse(id: int, reason: String) -> void:
	_net_refused.rpc_id(id, reason)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		# The refused player usually hangs up first.
		if mode == "host" and multiplayer.get_peers().has(id):
			multiplayer.multiplayer_peer.disconnect_peer(id))

@rpc("authority", "call_remote", "reliable")
func _net_refused(reason: String) -> void:
	_back_to_rooms(reason)

func _on_peer_disconnected(id: int) -> void:
	_remove_mech(id)
	_sitting_out.erase(id)
	if mode == "host" and roster.has(id):
		var who := str(names.get(id, ""))
		roster.erase(id)
		names.erase(id)
		bodies.erase(id)
		_send_roster()
		_room_notice("%s %s" % [who, front.text("text_30")])
		# A battle with one player left is over: back to the room.
		if _match_on and roster.size() < 2:
			_net_to_room.rpc()
			_to_room()
		_refresh_room()
		_host_status()
		_advertise()

## The host's slot list and the room. A joiner learns its own slot here and builds everyone's
## mech; one who joins during a battle waits in the room until the next one starts.
func _send_roster() -> void:
	_net_roster.rpc(roster, {
		"round": round_number, "on": _match_on, "map": map_choice, "spawns": spawn_points,
		"teams": team_mode, "names": names, "bodies": bodies, "name": room_name,
		"beginner": room_beginner, "full": full_rate,
	})
	# After the notice of whoever came in or left.
	_announce_rate.call_deferred()

@rpc("authority", "call_remote", "reliable")
func _net_roster(list: Dictionary, info: Dictionary) -> void:
	team_mode = bool(info["teams"])
	map_choice = str(info["map"])
	names = info["names"]
	bodies = info["bodies"]
	room_name = str(info["name"])
	room_beginner = bool(info["beginner"])
	full_rate = bool(info.get("full", false))
	spawn_points.clear()
	for i in info["spawns"]:
		spawn_points.append(int(i))
	var first := not mechs.has(local_id)
	roster = list
	for id in mechs.keys():
		if not roster.has(id):
			_remove_mech(id)
	if first:
		round_number = int(info["round"])
		_match_on = bool(info["on"])
	for id: int in roster:
		if not mechs.has(id):
			if id == local_id:
				_spawn(id, int(roster[id]), true, body_choice, loadout_choice)
			else:
				_spawn(id, int(roster[id]), false, str(bodies.get(id, "zeid")))
			# Whoever is new sits out a battle already under way; those already playing send
			# their own state.
			if _match_on and (id == local_id or not first):
				_sit_out(mechs[id])
	_apply_slots()
	_set_mode("join")
	_status = "You are player %d of %d%s." % [int(roster[local_id]) + 1, roster.size(), _team_words(int(roster[local_id]))]
	if first:
		front.clear_room_console()
		_to_room()
	else:
		_refresh_room()

## Slots and teams from the roster onto the mechs (a team change moves a slot).
func _apply_slots() -> void:
	for id: int in roster:
		if mechs.has(id):
			var m: Mech = mechs[id]
			var slot := int(roster[id])
			if m.slot != slot:
				m.slot = slot
				m.view.set_skin(slot)
			m.team = Room.team_of(slot, team_mode)

func _team_words(slot: int) -> String:
	match Room.team_of(slot, team_mode):
		Room.RED:
			return ", red team"
		Room.BLUE:
			return ", blue team"
	return ""

## A player asks the host to move to the other side (MSERVER_ROOM_CHANGE_TEAM_SLOT_REQ):
## T in the room.
@rpc("any_peer", "call_remote", "reliable")
func _net_change_team() -> void:
	_change_team(multiplayer.get_remote_sender_id())

func _change_team(id: int) -> void:
	if mode != "host" or not team_mode or not roster.has(id):
		return
	_move_slot(id, Room.switch_slot(int(roster[id]), roster.values()))

## A click on an empty slot asks to move there (ChangeTeamSlot, NetSendTeamChange); in team
## battle that changes sides.
func _ask_slot(slot: int) -> void:
	if mode == "host":
		_move_slot(local_id, slot)
	elif mode == "join":
		_net_move_slot.rpc_id(1, slot)

@rpc("any_peer", "call_remote", "reliable")
func _net_move_slot(slot: int) -> void:
	_move_slot(multiplayer.get_remote_sender_id(), slot)

## Host: in the room, not while the countdown runs, and only to an empty slot.
func _move_slot(id: int, slot: int) -> void:
	if mode != "host" or not _in_room or _countdown >= 0 or not roster.has(id):
		return
	if slot < 0 or slot >= Room.SIZE or roster.values().has(slot):
		return
	roster[id] = slot
	_apply_slots()
	_send_roster()
	_refresh_room()
	_host_status()

## The master's map arrows (UpdateMapInfo, send_map_select): the next arena in room order.
func _change_map(step: int) -> void:
	if mode != "host" or not _in_room or _countdown >= 0:
		return
	var ids := _map_ids()
	if ids.is_empty():
		return
	var i := ids.find(map_choice)
	map_choice = ids[(maxi(i, 0) + step + ids.size()) % ids.size()]
	_send_roster()
	_refresh_room()
	_host_status()

static func _map_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in BattleMap.list():
		out.append(str(entry["id"]))
	return out

## Room chat (game_room_on_enter_chatting_msg): to everyone in the room, by way of the host.
## "/rate full" and "/rate auto" are the room master's switch for the movement rate (this
## recreation's own command, in the style of the original's /invite and /wait).
func _send_chat(line: String) -> void:
	if not _networked():
		return
	if line.begins_with("/rate"):
		_rate_command(line.trim_prefix("/rate").strip_edges())
		return
	_net_chat.rpc(line)
	_show_chat(local_id, line)

@rpc("any_peer", "call_remote", "reliable")
func _net_chat(line: String) -> void:
	_show_chat(multiplayer.get_remote_sender_id(), line.left(60))

func _rate_command(arg: String) -> void:
	if mode != "host":
		_room_notice_local("Only the room master can change the movement rate.")
		return
	if arg == "full":
		full_rate = true
	elif arg == "auto":
		full_rate = false
	else:
		_room_notice_local("Movement updates: %d a second. /rate full keeps 60 a second, /rate auto goes by players." % state_rate())
		return
	_announced_rate = -1
	_send_roster()

## GameRoomChatEventHandler: "name : message", your own lines in yellow.
func _show_chat(id: int, line: String) -> void:
	var who := str(names.get(id, "Player"))
	front.room_console_add("%s : %s" % [who, line], FrontEnd.MY_NAME if id == local_id else Color.WHITE)

## Game_Room_Notice_write: "System : ..." in green, on every machine.
func _room_notice(msg: String) -> void:
	_net_room_notice.rpc(msg)
	_room_notice_local(msg)

@rpc("authority", "call_remote", "reliable")
func _net_room_notice(msg: String) -> void:
	_room_notice_local(msg)

func _room_notice_local(msg: String) -> void:
	if _netlog:
		print("[room] System : ", msg)
	front.room_console_add("System : " + msg, FrontEnd.NOTICE)

## What the game room page shows (FrontEnd.update_game_room).
func _room_view() -> Dictionary:
	var slots := {}
	for id: int in roster:
		var body := body_choice if id == local_id else str(bodies.get(id, "zeid"))
		if mechs.has(id) and id != local_id:
			body = (mechs[id] as Mech).body
		slots[int(roster[id])] = {
			"name": str(names.get(id, "Player %d" % (int(roster[id]) + 1))),
			"face": Bodies.face(body),
			"master": id == 1,
			"me": id == local_id,
			"playing": _match_on and not _sitting_out.has(id),
		}
	return {
		"number": room_number, "name": room_name, "teams": team_mode, "playing": _match_on,
		"beginner": room_beginner, "map": maxi(0, _map_ids().find(map_choice)),
		"master": mode == "host", "slots": slots,
	}

func _refresh_room() -> void:
	if _in_room or front.page == "room":
		front.update_game_room(_room_view())

## Host: the room as the room list shows it, announced on the local network.
func _advertise() -> void:
	if mode != "host":
		return
	front.lan.advertise({
		"name": room_name, "locked": room_password != "", "teams": team_mode, "beginner": room_beginner,
		"players": roster.size(), "playing": _match_on, "port": PORT,
	})

## Off the field until the next battle: not drawn, not counted, no input.
func _sit_out(m: Mech) -> void:
	_sitting_out[m.id] = true
	m.sim.life = 0
	m.sim.is_dead = true
	m.sim.is_dead_complete = true
	m.death_played = true
	m.exploded = true
	m.view.visible = false

## The status line under a battle, for the master: where the room can be reached.
func _host_status() -> void:
	var where := "Hosting %s on %s port %d. %d of %d players, %d updates a second." % [room_name, ", ".join(_lan_addresses()), PORT, roster.size(), MAX_PLAYERS, state_rate()]
	if team_mode:
		var red := 0
		for sl in roster.values():
			if int(sl) < Room.HALF:
				red += 1
		where += " Red %d, blue %d." % [red, roster.size() - red]
	_status = where

## Physics ticks between this machine's states: 1 at 60 a second, 2 at 30, 3 at 20.
func state_rate() -> int:
	return Room.state_rate(roster.size(), full_rate)

func _state_every() -> int:
	return maxi(1, roundi(Engine.physics_ticks_per_second / float(state_rate())))

## Host: a System notice when the room's rate changes, so everyone knows why remote mechs
## move a little less smoothly in a big room.
func _announce_rate() -> void:
	var rate := state_rate()
	if rate == _announced_rate:
		return
	var first := _announced_rate == 0
	_announced_rate = rate
	if not first:
		_room_notice("Movement updates: %d a second for %d players%s." % [rate, roster.size(), " (full rate set by the room master)" if full_rate else ""])

## Owner's state, at the room's rate. Unreliable: a newer one replaces a lost one. Between
## states a remote mech carries on along its last direction and speed (MechSim.step_remote).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_state(state: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	# Mechs come from the roster; a state can beat it here.
	if not mechs.has(id):
		return
	var m: Mech = mechs[id]
	# A state sent before the owner heard of a new round still carries the old round's knockout,
	# which would end the new round at once.
	if int(state[state.size() - 1]) != round_number:
		return
	# The owner's body and loadout (the room's EquipItem): rebuild their mech when either
	# differs from what we drew.
	var body_index := int(state[state.size() - 2])
	var weapons: Array = state[state.size() - 3]
	if body_index >= 0 and body_index < Bodies.NAMES.size():
		var body: String = Bodies.NAMES[body_index]
		if body != m.body or Bodies.loadout(body, weapons) != Array(m.weapons, TYPE_INT, "", null):
			_respawn_body(m, body, weapons)
	m.lock_target = int(state[state.size() - 4])
	m.sim.apply_snapshot(state)

## A shot, from the shooter's muzzle. Reliable so both screens show every bullet.
@rpc("any_peer", "call_remote", "reliable")
func _net_fire(origin: Vector2, deg: int, weapon_id: int, target: int, charge: int, clip: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mechs.has(id):
		var m: Mech = mechs[id]
		if clip >= 0:
			m.view.play_attack(clip)
		_launch(origin, deg, m, weapon_id, target, charge)

## A splash shell's owner let go of the button (pt_send_button_up_explosion).
@rpc("any_peer", "call_remote", "reliable")
func _net_detonate() -> void:
	_detonate_shells(multiplayer.get_remote_sender_id())

## A Plasma Bow arrow stunned this machine's mech: the push (StunState) is the victim's own.
func _stun(m: Mech, charge: int, along: Vector2) -> void:
	m.sim.stun_time = Combat.bow_stun_time(charge)
	m.sim.start_dash(m.sim.pos + along.normalized() * Combat.BOW_PUSH)

## A sword swing on another machine: its clip, trail and sound. The attacker's machine
## decides whether it lands (collision_checker 1).
@rpc("any_peer", "call_remote", "reliable")
func _net_swing(swing: int, combo: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mechs.has(id):
		_show_swing(mechs[id], swing, combo)

## A swing from another machine landed on this machine's mech.
@rpc("any_peer", "call_remote", "reliable")
func _net_melee_hit(amount: int, weapon_id: int, from: Vector2) -> void:
	var me := _local()
	if me:
		_apply_hit(me, multiplayer.get_remote_sender_id(), amount, weapon_id, from)

## The victim's machine reports a hit it decided (World::damage_respond).
@rpc("any_peer", "call_remote", "reliable")
func _net_hit(attacker: int, amount: int, remaining: int, weapon_id: int) -> void:
	var victim := multiplayer.get_remote_sender_id()
	_record_hit(victim, attacker, amount, remaining, weapon_id)

# --- Mechs ------------------------------------------------------------------------------

func _spawn(id: int, slot: int, local: bool, body := "zeid", weapons: Array = []) -> void:
	var m := Mech.new()
	m.id = id
	m.slot = slot
	m.team = Room.team_of(slot, team_mode)
	m.local = local
	mechs[id] = m
	stats[id] = Stats.new()
	_build_body(m, body, weapons)
	m.sim.reset_at(_spawn_pos(slot), _spawn_facing(slot))
	if local:
		cam_from = Vector3(m.sim.pos.x, -depth, m.sim.pos.y)

## The mech's simulation and model for a body and loadout, with their events wired.
func _build_body(m: Mech, body: String, weapons: Array = []) -> void:
	m.body = body
	m.weapons = Bodies.loadout(body, weapons)
	m.sim = MechSim.new(body, Original.START_WEAPON, m.weapons)
	_attach_map(m)
	m.view = MechView.new(body, m.weapons)
	add_child(m.view)
	m.view.set_skin(m.slot)
	m.sim.boost_started.connect(func() -> void: sound.play_at("sound/sp_booster", m.sim.pos))
	m.sim.weapon_changed.connect(func(w: int) -> void: _on_weapon_changed(m, w))
	m.sim.charge_changed.connect(func(level: int) -> void: m.view.set_charge(level))
	m.sim.guard_changed.connect(func(on: bool) -> void: _on_guard_changed(m, on))
	if m.local or m.id == DUMMY_ID:
		m.sim.fired.connect(func(_o: Vector2, deg: int) -> void: _on_local_fired(m, deg))
		m.sim.attack_started.connect(func(_w: int) -> void: m.burst_target = m.lock_target)
		m.sim.swung.connect(func(_w: int, swing: int) -> void: _on_local_swing(m, swing))
	if m.local:
		m.sim.wall_crashed.connect(func(at: Vector2, normal: Vector2) -> void: _on_wall_crash(m, at, normal))
		m.sim.shield_clicked.connect(func() -> void: sound.play("sound/common/shieldused"))

## Another player's body or loadout arrived: swap the model and simulation, keeping where
## they are.
func _respawn_body(m: Mech, body: String, weapons: Array = []) -> void:
	var at := m.sim.pos
	var face := m.sim.facing
	m.view.queue_free()
	_build_body(m, body, weapons)
	m.sim.reset_at(at, face)

func _random_other_body(body: String) -> String:
	var others: Array[String] = []
	for b in Bodies.NAMES:
		if b != body:
			others.append(b)
	return others[randi() % others.size()]

## rc_map::crashed_with_wall: the wall_crash effect and sound/special_fire at your mech.
func _on_wall_crash(m: Mech, at: Vector2, normal: Vector2) -> void:
	BattleWorld.wall_crash(self, at, normal)
	sound.play_at("sound/special_fire", m.sim.pos)

## rcPlayer::change_weapon on every machine: the new weapon drawn; the owner hears
## sound_file[0] (on_my_weapon_change). clear_active_bullet empties only the queue of shots
## not yet fired, which the sim never leaves behind on a change; bullets in flight stay.
func _on_weapon_changed(m: Mech, w: int) -> void:
	m.view.set_weapon(w)
	if m.local:
		sound.play(Bodies.sounds(m.sim.weapon.id)[0])

## A swing starts on the attacker's machine: show it, tell the others, start its hit window.
func _on_local_swing(m: Mech, swing: int) -> void:
	var combo := m.sim.swing_combo
	_show_swing(m, swing, combo)
	# create_bullet(..., cp->damage): a command combo adds its damage to this swing.
	swings.append([m, 0.0, m.sim.weapon, int(Bodies.combo_param(combo).get("damage", 0))])
	if _networked() and m.local:
		_net_swing.rpc(swing, combo)

## A command combo's swing also throws effect_name at the mech and rotate_effect_name turned
## to its facing (pt_recv_shoot / ComboSystem::update).
func _show_swing(m: Mech, swing: int, combo := 0) -> void:
	m.view.play_attack(swing)
	# pt_recv_attack_start: a weapon with pulse_time (Void Pulse) starts PulseState.
	var pulse := m.sim.weapon.mode_num("pulse_time")
	if pulse > 0.0:
		m.sim.pulse_time = pulse
	var cp := Bodies.combo_param(combo)
	if not cp.is_empty():
		var start := Bodies.scene_path(str(cp.get("effect_name", "")))
		if start != "":
			BattleWorld.spawn_effect(self, start, BattleWorld.effect_basis(), m.sim.pos, COMBO_EFFECT_TIME)
		var turn := Bodies.scene_path(str(cp.get("rotate_effect_name", "")))
		if turn != "":
			var life := COMBO_EFFECT_TIME
			var lengths := Bodies.clip_lengths(str(cp.get("rotate_effect_name", "")))
			if not lengths.is_empty():
				life = float(lengths[0])
			BattleWorld.spawn_effect(self, turn, BattleWorld.facing_effect_basis(m.sim.facing), m.sim.pos, life)
	# on_create_bullet: Alicia's third saber swing plays ali1_att2 instead.
	var fire_sound: String = Bodies.sounds(m.sim.weapon.id)[2]
	if m.body == "alicia" and m.sim.weapon_index == 0 and swing == 4:
		fire_sound = "sound/ali1_att2"
	sound.play_at(fire_sound, m.sim.pos)

## rc_bullet::is_crash for a sword: from 0.3 s until its life ends, the first mech (in slot
## order) within collision_area of the attacker and inside the arc ahead of its facing is hit,
## once. Damage is the weapon's plus the swing's command combo bonus (get_damage).
func _step_swings(dt: float) -> void:
	for i in range(swings.size() - 1, -1, -1):
		var entry: Array = swings[i]
		var attacker: Mech = entry[0]
		var w: GameData.Weapon = entry[2]
		var amount: int = w.damage + int(entry[3])
		entry[1] += dt
		if entry[1] > w.life or attacker.sim.life <= 0 or not mechs.has(attacker.id):
			swings.remove_at(i)
			continue
		# crash_check_time: 0.3 s for the dagger, 0 for the saber.
		if entry[1] < w.mode_num("crash_check_time"):
			continue
		var facing := Original.vec2_from_deg(attacker.sim.facing)
		for victim: Mech in _mechs_in_slot_order():
			if victim == attacker or victim.sim.life <= 0 or victim.sim.is_pulse() or Room.teammates(victim.team, attacker.team):
				continue
			var rel := victim.sim.pos - attacker.sim.pos
			if rel.length() >= w.crash_radius or rel.length_squared() < 0.0001:
				continue
			if rad_to_deg(acos(clampf(rel.normalized().dot(facing), -1.0, 1.0))) >= w.collision_degree * 0.5:
				continue
			swings.remove_at(i)
			BattleWorld.sword_hit(self, victim.sim.pos)
			# The guard test runs where the victim's guard and facing are known for sure.
			if round_active:
				if _owns(victim):
					_apply_hit(victim, attacker.id, amount, w.id, attacker.sim.pos)
				elif _networked():
					_net_melee_hit.rpc_id(victim.id, amount, w.id, attacker.sim.pos)
			break

## LockOnSystem::update for the local mech with a guided weapon: enemies within the range
## and inside the cone ahead, nearest first. The current target is kept while it qualifies;
## F steps to the next candidate.
func lock_candidates(m: Mech) -> Array[Mech]:
	var out: Array[Mech] = []
	var w := m.sim.weapon
	if w.lockon_range() <= 0.0 or not w.is_guided() or m.sim.life <= 0:
		return out
	var facing := Original.vec2_from_deg(m.sim.facing)
	for o: Mech in mechs.values():
		if o == m or o.sim.is_dead_complete or Room.teammates(o.team, m.team):
			continue
		var rel := o.sim.pos - m.sim.pos
		if rel.length() > w.lockon_range() or rel.length_squared() < 0.0001:
			continue
		if rad_to_deg(acos(clampf(rel.normalized().dot(facing), -1.0, 1.0))) > w.lockon_half_angle():
			continue
		out.append(o)
	out.sort_custom(func(a: Mech, b: Mech) -> bool: return a.sim.pos.distance_to(m.sim.pos) < b.sim.pos.distance_to(m.sim.pos))
	return out

func _update_lock(m: Mech, step_next: bool) -> void:
	var cands := lock_candidates(m)
	if cands.is_empty():
		m.lock_target = NO_TARGET
		return
	var ids: Array[int] = []
	for c in cands:
		ids.append(c.id)
	var at := ids.find(m.lock_target)
	if at < 0:
		m.lock_target = ids[0]
	elif step_next:
		m.lock_target = ids[(at + 1) % ids.size()]

func _remove_mech(id: int) -> void:
	if mechs.has(id):
		(mechs[id] as Mech).view.queue_free()
		mechs.erase(id)
		stats.erase(id)

func _team_of_id(id: int) -> int:
	return (mechs[id] as Mech).team if mechs.has(id) else Room.NONE

## The mech the camera follows: yours, or once it is gone the next player still standing in
## slot order (OnCameraPlayerIsDead, set_next_camera), kept until they fall in turn.
func _watched() -> Mech:
	var me := _local()
	if me == null or not me.sim.is_dead_complete:
		return me
	var current: Mech = mechs.get(_watch_id)
	if current and current != me and not current.sim.is_dead_complete:
		return current
	var order := _mechs_in_slot_order()
	var start := order.find(current if current else me)
	for i in range(1, order.size() + 1):
		var m: Mech = order[(start + i) % order.size()]
		if not m.sim.is_dead_complete:
			_watch_id = m.id
			return m
	return me

func _local() -> Mech:
	return mechs.get(local_id)

func _nearest_enemy(of: Mech, alive_only := true) -> Mech:
	var best: Mech = null
	for m: Mech in mechs.values():
		if m == of or (alive_only and m.sim.is_dead_complete) or Room.teammates(m.team, of.team):
			continue
		if best == null or m.sim.pos.distance_to(of.sim.pos) < best.sim.pos.distance_to(of.sim.pos):
			best = m
	return best

# --- Frame ------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if round_active:
		round_time += dt
	_step_tethers(dt)
	for m: Mech in mechs.values():
		if m.local:
			var can_act := round_active and m.sim.life > 0
			var intent := _read_intent(m) if can_act else MechSim.Intent.new()
			var lock_key := (Input.is_physical_key_pressed(KEY_F) or (touch != null and touch.lock)) and can_act
			_update_lock(m, lock_key and not _prev_lockon_key)
			_prev_lockon_key = lock_key
			# button_up_explosion: letting go sets off this mech's splash shells.
			if _prev_fire_local and not intent.fire:
				if _detonate_shells(m.id) and _networked():
					_net_detonate.rpc()
			_prev_fire_local = intent.fire
			m.sim.step(intent, dt)
			_state_tick += 1
			if _networked() and _state_tick >= _state_every():
				_state_tick = 0
				var state := m.sim.snapshot()
				state.append(m.lock_target)
				state.append(m.weapons)
				state.append(Bodies.NAMES.find(m.body))
				state.append(round_number)
				_net_state.rpc(state)
		elif m.id == DUMMY_ID:
			var it := MechSim.Intent.new()
			var me := _local()
			it.aim = me.sim.pos if me else Vector2.ZERO
			it.guard = _dummy_guard and round_active and not m.sim.guarding and fmod(round_time, 1.0) < 0.1
			m.sim.step(it, dt)
		else:
			m.sim.step_remote(dt)
	_step_bullets(dt)
	_step_beams(dt)
	_step_swings(dt)
	_step_ticks(dt)
	_step_leeches(dt)
	_check_round_end()
	if _end_timer >= 0.0:
		_end_timer -= dt
		if _end_timer < 0.0:
			_send_result()
	if _next_round_timer >= 0.0:
		_next_round_timer -= dt
		if _next_round_timer < 0.0:
			_results_done()
	if mode == "host":
		_step_countdown(dt)
	if _netlog:
		_log_timer += dt
		if _log_timer >= 1.0:
			_log_timer = 0.0
			var parts: Array[String] = []
			for m: Mech in mechs.values():
				var flags := (" G" if m.sim.guarding else "") + (" C" if m.sim.is_confused() else "") + (" J" if m.local and hud.jam_time > 0.0 else "") \
					+ (" P" if m.sim.is_pulse() else "") + (" D%d" % m.sim.damage_stacks.size() if not m.sim.damage_stacks.is_empty() else "") \
					+ (" FRZ" if m.sim.freeze_time > 0.0 else "") + (" REV" if m.sim.reverse_time > 0.0 else "") + (" BLD" if m.sim.blind_time > 0.0 else "") \
					+ (" FLD" if m.sim.field_time > 0.0 else "") + (" PWR" if m.sim.power_time > 0.0 else "") + (" WIRE" if m.sim.gravity_time > 0.0 else "") \
					+ (" OVB" if m.sim.over_boost_time > 0.0 else "") + (" LEECH" if _leeches.has(m.id) else "") \
					+ (" TICK%d" % _ticks.filter(func(t: Array) -> bool: return t[0] == m.id).size() if _ticks.any(func(t: Array) -> bool: return t[0] == m.id) else "")
				parts.append("%s%d s%d t%d %s%s pos=(%d,%d) hp=%d sh=%d%s" % ["me" if m.local else "peer", m.id, m.slot, m.team, m.body, str(m.weapons).replace(" ", ""), m.sim.pos.x, m.sim.pos.y, m.sim.life, m.sim.durability, flags])
			var mines := 0
			var lying := 0
			for bl in bullets:
				if bl.mine:
					mines += 1
					lying += int(bl.is_lying())
			if mines > 0:
				parts.append("mines=%d lying=%d" % [mines, lying])
			# The host's upload over the last second, everything it sent and relayed.
			var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if mode == "host" and enet and enet.host:
				parts.append("up=%dKB/s rate=%d" % [enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA) / 1024, state_rate()])
			print("[%s r%d %s f%d] " % [mode, round_number, "on" if round_active else "off", _capture_index], "  ".join(parts))

func _process(dt: float) -> void:
	if _shop_sky:
		_shop_frame(dt)
	var me := _local()
	# In the game room the page covers the battle; the mechs stay put away until it starts.
	hud.visible = not _in_room
	if me and not _in_room:
		_update_camera(_watched(), dt)
	for m: Mech in mechs.values():
		if not _in_room:
			_draw_mech(m, dt)
	_draw_tethers()
	var others := []
	var board := []
	for m: Mech in mechs.values():
		if m != me:
			others.append([m.id, m.sim.pos, _mech_name(m), not m.sim.is_dead_complete, m.team])
		# Tab: everyone's face, HP and name by slot (EnableUserViewInfo).
		board.append([m.slot, Bodies.face(m.body), float(maxi(0, m.sim.life)) / float(m.sim.life_max), _mech_name(m), m.sim.life > 0])
	hud.team_mode = team_mode
	hud.my_team = me.team if me else Room.NONE
	# BlindBeamState covers your own screen.
	hud.blind = me != null and me.sim.blind_time > 0.0
	hud.board = board
	hud.show_board = (Input.is_physical_key_pressed(KEY_TAB) or _hold_tab or (touch != null and touch.players)) and me != null
	if touch:
		touch.show_start = _can_start_now()
		touch.show_team = _can_change_team_now()
	var nearest := _nearest_enemy(me) if me else null
	hud.lock_target_pos = null
	hud.lock_candidates.clear()
	hud.locked_on_me = false
	if me:
		if me.lock_target != NO_TARGET and mechs.has(me.lock_target):
			hud.lock_target_pos = (mechs[me.lock_target] as Mech).sim.pos
		for c in lock_candidates(me):
			if c.id != me.lock_target:
				hud.lock_candidates.append(c.sim.pos)
		for o: Mech in mechs.values():
			if o != me and o.lock_target == me.id:
				hud.locked_on_me = true
	hud.refresh(me.sim if me else null, _mech_name(me) if me else "", _status, round_time, camera, others, nearest.id if nearest else 0, dt)
	sound.listener = Vector2(cam_from.x, cam_from.z)
	if _capture_dir != "":
		_capture_time += dt
		if _capture_time >= 1.0 / 30.0:
			_capture_time = 0.0
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("%s/f%05d.jpg" % [_capture_dir, _capture_index], 0.85)
			_capture_index += 1

func _draw_mech(m: Mech, dt: float) -> void:
	m.view.place(m.sim.pos, m.sim.facing)
	# Boost nozzles: "00" while boosting (start/stop_booster_particle); the directional ones
	# burst on each new move, and against the old one on a stop (update_booster).
	if m.sim.speed_state != m.prev_speed_state or not m.sim.move_dir.is_equal_approx(m.prev_move_dir):
		m.view.set_boost(m.sim.speed_state == 2 and m.sim.life > 0)
		if m.sim.move_dir != Vector2.ZERO:
			m.view.booster_burst(m.sim.move_dir)
		elif m.prev_move_dir != Vector2.ZERO:
			m.view.booster_burst(-m.prev_move_dir)
		m.prev_speed_state = m.sim.speed_state
		m.prev_move_dir = m.sim.move_dir
	# Knockout: explosion pose, then the debris explosion and the mech is no longer drawn.
	if m.sim.is_dead and not m.death_played:
		m.death_played = true
		m.view.play_death()
	if m.sim.is_dead_complete:
		if not m.exploded:
			m.exploded = true
			BattleWorld.knockout_explosion(self, m.sim.pos)
			sound.play_at("sound/common/bomb-complete", m.sim.pos)
		m.view.visible = false
		return
	m.view.visible = true
	_low_health_sparks(m, dt)
	if m.view.guarding != m.sim.guarding:
		m.view.set_guard(m.sim.guarding)
	# PulseState: drawn see-through (stealth_alpha 150); after a teleport, fading back in.
	var alpha := MechView.GHOST_ALPHA if m.sim.is_pulse() else 1.0
	if _fading.has(m.id):
		_fading[m.id] = float(_fading[m.id]) + TELEPORT_FADE * dt
		if float(_fading[m.id]) >= 1.0:
			_fading.erase(m.id)
		else:
			alpha = minf(alpha, float(_fading[m.id]))
	m.view.set_alpha(alpha)
	# rcPlayer::move returns early in BEHAVE_GUARD: the guard pose holds while walking.
	if m.sim.is_dead or m.sim.guarding or m.view.is_attack_playing() or m.view.is_reacting() or m.view.is_drawing():
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
	BattleWorld.low_health_spark(self, m.sim.pos + offset)
	m.spark_time = float(randi() % 2) * 0.5 + 0.5 * 10.0 * float(m.sim.life) / float(m.sim.life_max)

func _read_intent(m: Mech) -> MechSim.Intent:
	if _autopilot:
		return _autopilot_intent(m)
	if touch:
		return _touch_intent(m)
	var it := MechSim.Intent.new()
	it.left = Input.is_action_pressed("move_left")
	it.right = Input.is_action_pressed("move_right")
	it.up = Input.is_action_pressed("move_up")
	it.down = Input.is_action_pressed("move_down")
	it.boost = Input.is_action_pressed("boost")
	it.fire = Input.is_action_pressed("fire")
	it.guard = Input.is_physical_key_pressed(KEY_SPACE)
	# DIK_1 to DIK_4, or the keypad.
	for k in 4:
		if Input.is_physical_key_pressed(KEY_1 + k) or Input.is_physical_key_pressed(KEY_KP_1 + k):
			it.weapon_key = k + 1
	it.aim = _mouse_on_plane(m)
	return it

## The touch controls as the same keys and buttons. Weapons worked by holding the button get
## a held trigger; the rest get clicks.
func _touch_intent(m: Mech) -> MechSim.Intent:
	var it := MechSim.Intent.new()
	var k := touch.keys()
	it.left = k["left"]
	it.right = k["right"]
	it.up = k["up"]
	it.down = k["down"]
	it.boost = k["boost"]
	var w := m.sim.weapon
	var hold := w.is_continuous or w.is_charge() or int(w.mode_num("button_up_explosion")) == 1
	it.fire = touch.fire_held(hold)
	it.guard = touch.guard
	it.weapon_key = touch.weapon_key
	var d := touch.plane_aim()
	if d == Vector2.ZERO:
		d = Original.vec2_from_deg(m.sim.facing)
	it.aim = m.sim.pos + d * 300.0
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

## A round leaves the owner's weapon. number_of_weapon 2: switch_shot alternates the hands
## and their clips (Double Hand Gun), otherwise both hands fire (Arms-Gun). fire_randomness
## spreads each round within reverse_range_angle (Plasma Shock Wave).
func _on_local_fired(m: Mech, deg: int) -> void:
	var w := m.sim.weapon
	if _netlog:
		print("  fired %s by %d" % [w.name, m.id])
	# Power Up Pulse and D Fielder: the shooter's machine gives the state to its side.
	if w.id in [47, 48]:
		_buff_allies(m, w)
	var hands := maxi(1, m.view.muzzle_count())
	var shot := m.sim.shot_index
	var switch_shot := int(w.param_num("switch_shot")) == 1 and hands > 1
	var clip := Original.ANIM_ATTACK + (shot % 2 if switch_shot else 0)
	if switch_shot or not m.view.is_attack_playing():
		m.view.play_attack(clip)
	else:
		clip = -1
	var from_hands: Array[int] = []
	if switch_shot:
		from_hands.append(shot % 2)
	else:
		for h in hands:
			from_hands.append(h)
	for hand in from_hands:
		var aim := deg
		if int(w.mode_num("fire_randomness")) == 1:
			var half := int(w.mode_num("reverse_range_angle", 60)) / 2
			aim = (deg + randi_range(-half, half) + 360) % 360
		# angle_randomness (P.Pulse Gun): each bullet turned by rand() % deg - deg / 2.
		var spread := int(w.mode_num("angle_randomness"))
		if spread > 0:
			aim = (aim + randi() % spread - spread / 2 + 360) % 360
		var origin := m.view.muzzle_plane_pos(hand)
		var charge := maxi(0, m.sim.charge_level) if w.is_charge() else 0
		_launch(origin, aim, m, w.id, m.burst_target, charge)
		if _networked() and m.local:
			_net_fire.rpc(origin, aim, w.id, m.burst_target, charge, clip)
		clip = -1

## A shot on this machine: a beam for immediate weapons, otherwise a bullet. A guided bullet
## chases the mech with id target (NO_TARGET: straight).
func _launch(origin: Vector2, deg: int, shooter: Mech, weapon_id: int, target: int, charge := 0) -> void:
	var w := GameData.weapon(weapon_id)
	sound.play_at(Bodies.sounds(weapon_id)[2], shooter.sim.pos)
	var start_fx := Bodies.scene_path(str(w.mode.get("bullet_start_xfile", "")))
	if start_fx != "":
		BattleWorld.spawn_effect(self, start_fx, BattleWorld.effect_basis(), origin, 1.0)
	# Over Booster: OverBoosterState on the shooter, everywhere, with busterup.X on it.
	if weapon_id == 53:
		shooter.sim.over_boost_time = MechSim.OVER_BOOST_TIME
		_state_mark(shooter, OVER_BOOST_MARK, MechSim.OVER_BOOST_TIME)
	if w.is_immediate():
		_add_beam(origin, deg, shooter, w)
		return
	var b := Bullet.new()
	add_child(b)
	var chase: MechSim = (mechs[target] as Mech).sim if target != NO_TARGET and mechs.has(target) else null
	b.setup(origin, deg, shooter.sim, w, chase, charge)
	b.set_meta("shooter", shooter.id)
	if b.mine:
		var owner_id := shooter.id
		b.find_target = func(at: Vector2, detect_range: float) -> MechSim: return _mine_target(owner_id, at, detect_range)
	bullets.append(b)

## An immediate shot. is_skip_crash: only one round in skip_crash_count + 1 can hit. The
## Heavy Machinegun shows a short-lived tracer (second_gigas.x) instead of a strip.
func _add_beam(origin: Vector2, deg: int, shooter: Mech, w: GameData.Weapon) -> void:
	var skip := false
	if int(w.mode_num("is_skip_crash")) == 1:
		var n: int = _skip_counter.get(shooter.id, 0)
		skip = n % (int(w.mode_num("skip_crash_count")) + 1) != 0
		_skip_counter[shooter.id] = n + 1
	var beam := Beam.new()
	add_child(beam)
	beam.setup(origin, deg, w, shooter.id, skip)
	beams.append(beam)
	var model := Bodies.scene_path(str(w.mode.get("bullet_xfile", "")))
	if model != "":
		var life := w.mode_num("crash_projectile_life_time", 0.17) if w.id == 10 else w.life
		var fx := BattleWorld.spawn_effect(self, model, BattleWorld.effect_basis(), origin, life)
		if fx and w.id == 10:
			var d := Original.vec2_from_deg(deg)
			var tw := fx.create_tween()
			tw.tween_property(fx, "position", Original.to_godot(origin + d * w.bullet_speed * life), life)

## Every machine runs every beam; the mech hit decides its own damage (collision_checker 2).
func _step_beams(dt: float) -> void:
	for i in range(beams.size() - 1, -1, -1):
		var beam := beams[i]
		var shooter: Mech = mechs.get(beam.shooter_id)
		var muzzle := beam.start
		var facing := 0
		if shooter:
			muzzle = shooter.view.muzzle_plane_pos()
			facing = shooter.sim.facing
		var prev_point := beam.point()
		if not beam.advance(dt, muzzle, facing):
			beam.queue_free()
			beams.remove_at(i)
			continue
		if not beam.alive:
			continue
		if map and beam.stops_at_walls():
			var wall: Variant = map.collision.segment_hit(prev_point, beam.point())
			if wall != null:
				beam.alive = false
				BattleWorld.hit_flash(self, wall, Bodies.scene_path(str(beam.weapon.mode.get("bullet_dead_xfile", ""))))
				continue
		if beam.skip:
			continue
		var beam_team: int = (mechs[beam.shooter_id] as Mech).team if mechs.has(beam.shooter_id) else Room.NONE
		for victim: Mech in _mechs_in_slot_order():
			if victim.id == beam.shooter_id or victim.sim.life <= 0 or victim.sim.is_pulse() or Room.teammates(victim.team, beam_team):
				continue
			if not Combat.line_hits(beam.start, beam.line_end(), victim.sim.pos, victim.sim.crash_radius):
				continue
			if beam.pierce():
				if not beam.register_contact(victim.id, dt):
					continue
				BattleWorld.hit_flash(self, victim.sim.pos, Bodies.scene_path(str(beam.weapon.mode.get("bullet_dead_xfile2", ""))))
			else:
				beam.alive = false
				BattleWorld.hit_flash(self, victim.sim.pos, Bodies.scene_path(str(beam.weapon.mode.get("bullet_dead_xfile", ""))))
			_apply_hit(victim, beam.shooter_id, beam.weapon.damage, beam.weapon.id, beam.start)
			if not beam.alive:
				break

## Whether this machine decides hits on the mech: its own, or the practice target.
func _owns(m: Mech) -> bool:
	return m.local or m.id == DUMMY_ID

## A hit this machine decides: its own mech, or the practice target. from is where the shot
## came from for the guard test (the bullet's last position, the attacker for a sword), or
## NO_FROM for none. A guard facing it stops a sword or normal shot (World::process_crash);
## a pierce shot goes through but still sounds on the shield. The damage that lands is cut by
## the attacker's confusion (mul_to_damage). Returns false if nothing landed.
func _apply_hit(victim: Mech, attacker: int, amount: int, weapon_id: int, from := NO_FROM) -> bool:
	if not round_active or not _owns(victim) or victim.sim.life <= 0 or victim.sim.is_nodamage():
		return false
	if from != NO_FROM and victim.sim.guards_against(from):
		if Combat.guard_rule(GameData.weapon(weapon_id).weapon_type) == Combat.Guard.BLOCK:
			# RG_SHIELD_BLOCK_SUCCESS_REQ: the damage, at most a byte, wears the shield.
			var worn := mini(amount, 255)
			_guarded(victim, weapon_id, worn, victim.sim.block(worn))
			return false
		_guarded(victim, weapon_id, -1, false)
	# The attacker's confusion (mul_to_damage) and the victim's adddamage_ratio.
	var mul := victim.sim.damage_taken_mul()
	if mechs.has(attacker):
		mul *= (mechs[attacker] as Mech).sim.damage_mul
	amount = int(amount * mul)
	victim.sim.take_damage(amount)
	_record_hit(victim.id, attacker, amount, victim.sim.life, weapon_id)
	if _networked() and victim.local:
		_net_hit.rpc(attacker, amount, victim.sim.life, weapon_id)
	# add_damage: a leech bomb on the mech goes off at any damage that lands. A hit that does
	# none (another Leech Bomb, an EMP) leaves it be (inferred: the original's release with 0
	# would defuse it; that path is kept for a teammate's shot only).
	if _leeches.has(victim.id) and amount > 0:
		_leech_release(victim, true)
	return true

## A guard met a hit on this machine's mech: show it everywhere. blocked: the durability it
## took, or -1 when the shot went through; broke: the shield broke.
func _guarded(victim: Mech, weapon_id: int, blocked: int, broke: bool) -> void:
	_show_guarded(victim, weapon_id, blocked, broke)
	if _networked() and victim.local:
		_net_guarded.rpc(weapon_id, blocked, broke)

@rpc("any_peer", "call_remote", "reliable")
func _net_guarded(weapon_id: int, blocked: int, broke: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mechs.has(id):
		_show_guarded(mechs[id], weapon_id, blocked, broke)

## on_guard_defense: the defense clip, the shield's sound and, for a weapon whose mode sets
## bullet_guard_sound, one of six ricochets. World::receive_guard: character_block 30 units
## up the plane; at 0 durability shield_crash.
func _show_guarded(victim: Mech, weapon_id: int, blocked: int, broke: bool) -> void:
	var at := victim.sim.pos
	victim.view.play_guard_defense()
	var energy := victim.sim.shield != null and victim.sim.shield.weapon_type == 5
	sound.play_at("sound/common/energy_shield_defense" if energy else "sound/common/solid_shield_defense", at)
	if int(GameData.weapon(weapon_id).mode_num("bullet_guard_sound")) == 1:
		sound.play_at("sound/common/bullet_defense%d" % randi_range(1, 6), at)
	if blocked >= 0:
		BattleWorld.spawn_effect(self, CHARACTER_BLOCK, BattleWorld.effect_basis(1.0), at + Vector2(0, 30), 0.5)
	if broke:
		BattleWorld.spawn_effect(self, SHIELD_CRASH, BattleWorld.effect_basis(1.0), at, 1.0)

## pt_send_attack_start(WEAPON_GUARD / WEAPON_GUARD_CANCEL) and its echo: on_guard and
## on_guard_cancel sound on every machine. The view follows the sim in _draw_mech.
func _on_guard_changed(m: Mech, on: bool) -> void:
	sound.play_at("sound/common/guard" if on else "sound/common/guard_cancel", m.sim.pos)

## state_action_type 5 (Confusing Beam): the slow-down on every machine and spark.x on the
## mech for confusion_time. 4 (EMP Shock Gun): fourth_new_zeid_spark.x on the mech for
## jamming_time; the original sent one per player in the splash loop, so they pile up.
func _show_state(victim: Mech, weapon_id: int, count: int, attacker := 0) -> void:
	# NoDamageState (frozen): no new state takes.
	if victim.sim.is_nodamage():
		return
	var w := GameData.weapon(weapon_id)
	if _show_new_state(victim, w, count, attacker):
		return
	var time := 0.0
	if w.state_action_type == 6:
		# World::state_change case 41: booster_gage -= 200 x (1 + charge_add_damage x charge),
		# x 0.7 under a Power Up Pulse (state_booster_reduce_ratio, NetManager.cpp 2311).
		victim.sim.booster_gage = maxf(0.0, victim.sim.booster_gage - 200.0 * (1.0 + w.param_num("charge_add_damage") * count) * victim.sim.power_reduce)
		return
	if w.state_action_type == 9:
		# case 40: AddDamageState for 10 s, with weapon01/defence_down.x while the stack lasts.
		if victim.sim.add_damage_stack():
			var fx := BattleWorld.spawn_effect(victim.view, DEFENCE_DOWN, BattleWorld.effect_basis(1.0), Vector2.ZERO, MechSim.DAMAGE_STACK_TIME)
			if fx:
				MechView.play_effect(fx, true)
		return
	if w.state_action_type == 5:
		victim.sim.confuse(w)
		time = w.mode_num("confusion_time")
	elif w.state_action_type == 4:
		time = w.mode_num("jamming_time")
	var path := Bodies.scene_path(str(w.mode.get("bullet_dead_xfile2", "")))
	if time <= 0.0 or path == "":
		return
	for i in count:
		var fx := BattleWorld.spawn_effect(victim.view, path, BattleWorld.effect_basis(1.0), Vector2.ZERO, time)
		if fx:
			MechView.play_effect(fx, true)

# --- Step 17: the last fifteen weapons ----------------------------------------------------
# World::state_change picks the effect by weapon id; the client hard-codes the times (the
# database's state_limit_time is never read). Ticks, the leech bomb and the tether run on the
# machine that owns the mech they act on, like any damage; the marks show everywhere.

## DOTState (Napalm Thrower): 5 ticks a second apart, each 0.25 of the hit (send_damage 95).
const BURN_TICKS := 5
const BURN_SHARE := 0.25
const BURN_MARK := "res://assets/original/x/weapon01/fire_burn.gltf"
## ApDrainState (AP Drain Gun): 10 ticks of 4 a second apart; the attacker gains what the
## victim loses, up to full (send_damage 97, World::damage_respond).
const DRAIN_TICKS := 10
const DRAIN_AMOUNT := 4
const DRAIN_MARK := "res://assets/original/x/weapon01/drain_target_effect.gltf"
## LeechBombState: 30 s on the victim, then it goes off; any damage that lands sets it off
## first, and a teammate's shot through the victim defuses it (RG_STATE_RELEASE_REQ). The
## blast: Weapon52_mode1 splash_damage 50 over splash_area 600 / 100 x 0.33 x 100 = 198 units,
## to every mech, the victim, its allies and the attacker included (send_damage 96).
const LEECH_TIME := 30.0
const LEECH_DAMAGE := 50.0
const LEECH_RADIUS := 198.0
const LEECH_MODEL := "res://assets/original/x/weapon01/leech_bomb.gltf"
const LEECH_BLAST := "res://assets/original/x/weapon/third_gigas_boom.gltf"
const LEECH_DEFUSED := "res://assets/original/x/weapon/yokyuk_explo.gltf"
## GravityState (Plasma Wire): 15 s; past 100 units apart the victim is drawn toward the
## attacker at 1.5 x the distance a second and the attacker toward the victim at 0.5 x.
const TETHER_TIME := 15.0
const TETHER_SLACK := 100.0
const TETHER_VICTIM_PULL := 1.5
const TETHER_ATTACKER_PULL := 0.5
## rcEffect.cpp's chain: texture01/Chain.png, grown from the attacker at 500 units a second.
const CHAIN_TEXTURE := "res://assets/original/ui/texture01/chain.png"
const CHAIN_GROW := 500.0
const CHAIN_TILE := 15.0
const CHAIN_WIDTH := 12.0 ## the original's width of 1 is in units this port could not trace (inferred)
## The marks the other states show on the mech, for their time (world.cpp state_change): all
## of them 10 s (FREEZE_TIME, REVERSE_TIME and the rest in MechSim).
const STATE_TIME := 10.0
const STATE_MARKS := {
	47: "res://assets/original/x/weapon01/booster_rgn_down.gltf",
	48: "res://assets/original/x/weapon01/d_shield.gltf",
	50: "res://assets/original/x/weapon01/reverse.gltf",
	51: "res://assets/original/x/weapon01/freezed.gltf",
	55: "res://assets/original/x/weapon01/blind_01.gltf",
}
## OverBoosterState: 10 s with weapon01/busterup.X on the mech.
const OVER_BOOST_MARK := "res://assets/original/x/weapon01/busterup.gltf"
## Weapons whose hit starts a state on the one hit (state_action_type != 0, by id).
const HIT_STATES := [46, 47, 50, 51, 52, 55, 57]
## World::process_link_hit (Fragment Cannon): links fly at a fixed 400, the damage less 12
## (additional_damage, -12.5 truncated), starting 30 units from the hit.
const LINK_SPEED := 400.0
const LINK_DAMAGE_CUT := 12
const LINK_OFFSET := 30.0
## The Fragment Cannon alone may hit its own shooter, 0.2 s into a bullet's flight.
const SELF_HIT_AGE := 0.2
## is_teleport: the shooter fades back in at 120 of 255 a second.
const TELEPORT_FADE := 120.0 / 255.0

## [victim id, attacker id, weapon id, ticks left, time to the next, amount] for the burns
## and drains on mechs this machine owns.
var _ticks: Array = []
## Leech bombs by victim id: {attacker, time, node}. Every machine draws them; the owner times
## them and sets them off.
var _leeches: Dictionary = {}
## Plasma Wire tethers: {attacker, victim, time, length, node}.
var _tethers: Array = []
## Teleport fade-in left, by mech id (alpha rises from 0).
var _fading: Dictionary = {}

## A hit's state on the mech hit, decided where the mech is owned and shown everywhere.
## count: the hit's damage for the burn, otherwise as before (charge level, splash count).
func _state_change(victim: Mech, weapon_id: int, count := 1, attacker := 0) -> void:
	_show_state(victim, weapon_id, count, attacker)
	if _networked():
		_net_state_change.rpc(victim.id, weapon_id, count, attacker)

@rpc("any_peer", "call_remote", "reliable")
func _net_state_change(victim_id: int, weapon_id: int, count: int, attacker: int) -> void:
	if mechs.has(victim_id):
		_show_state(mechs[victim_id], weapon_id, count, attacker)

## The step 17 states; false for a weapon that is not one of them.
func _show_new_state(victim: Mech, w: GameData.Weapon, count: int, attacker: int) -> bool:
	match w.id:
		44:
			_state_mark(victim, BURN_MARK, float(BURN_TICKS))
			if _owns(victim):
				_ticks.append([victim.id, attacker, 44, BURN_TICKS, 1.0, int(count * BURN_SHARE)])
		46:
			_state_mark(victim, DRAIN_MARK, float(DRAIN_TICKS))
			if _owns(victim):
				_ticks.append([victim.id, attacker, 46, DRAIN_TICKS, 1.0, DRAIN_AMOUNT])
		47, 48, 50, 51, 55:
			victim.sim.start_state(w)
			_state_mark(victim, STATE_MARKS[w.id], STATE_TIME)
		57:
			victim.sim.start_state(w)
			_add_tether(attacker, victim.id)
		52:
			_add_leech(attacker, victim)
		_:
			return false
	return true

func _state_mark(victim: Mech, path: String, time: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var fx := BattleWorld.spawn_effect(victim.view, path, BattleWorld.effect_basis(1.0), Vector2.ZERO, time)
	if fx:
		MechView.play_effect(fx, true)

## Power Up Pulse and D Fielder (rcManager.cpp shoot): the shooter and every living
## teammate within pulse_dist or defense_field_dist of it; in free-for-all the shooter alone.
func _buff_allies(shooter: Mech, w: GameData.Weapon) -> void:
	var reach := w.param_num("pulse_dist") if w.id == 47 else w.param_num("defense_field_dist")
	for o: Mech in mechs.values():
		if o.sim.life <= 0 or o.sim.pos.distance_to(shooter.sim.pos) > reach:
			continue
		if o == shooter or Room.teammates(o.team, shooter.team):
			_state_change(o, w.id, 1, shooter.id)

## Burn and drain ticks, on this machine's own mechs.
func _step_ticks(dt: float) -> void:
	for i in range(_ticks.size() - 1, -1, -1):
		var t: Array = _ticks[i]
		if not mechs.has(t[0]):
			_ticks.remove_at(i)
			continue
		t[4] -= dt
		if t[4] > 0.0:
			continue
		t[4] += 1.0
		t[3] -= 1
		_special_hit(mechs[t[0]], t[1], t[5], t[2], t[2] == 46)
		if t[3] <= 0:
			_ticks.remove_at(i)

## send_damage with a special index (burn 95, leech 96, drain 97): no guard and no leech
## trigger, on a mech this machine owns. drain: the attacker gains the same.
func _special_hit(victim: Mech, attacker: int, amount: int, weapon_id: int, drain := false) -> void:
	if not round_active or victim.sim.life <= 0 or victim.sim.is_nodamage() or victim.sim.is_pulse() or amount <= 0:
		return
	victim.sim.take_damage(amount)
	_record_hit(victim.id, attacker, amount, victim.sim.life, weapon_id)
	if drain:
		_drained(attacker, amount)
	if _networked() and victim.local:
		_net_special_hit.rpc(attacker, amount, victim.sim.life, weapon_id, drain)

@rpc("any_peer", "call_remote", "reliable")
func _net_special_hit(attacker: int, amount: int, remaining: int, weapon_id: int, drain: bool) -> void:
	_record_hit(multiplayer.get_remote_sender_id(), attacker, amount, remaining, weapon_id)
	if drain:
		_drained(attacker, amount)

## The drain's other half, on the attacker's own machine: life back, up to full.
func _drained(attacker: int, amount: int) -> void:
	if mechs.has(attacker) and _owns(mechs[attacker]):
		var a: Mech = mechs[attacker]
		if a.sim.life > 0:
			a.sim.life = mini(a.sim.life_max, a.sim.life + amount)

# Leech Bomb ------------------------------------------------------------------------------

## Each hit adds its own bomb with its own 30 s (a LeechBombState per hit). Every machine adds
## them in the same order, from the same reliable messages, so a bomb's place in the list
## names it.
func _add_leech(attacker: int, victim: Mech) -> void:
	var node: Node3D = null
	if ResourceLoader.exists(LEECH_MODEL):
		node = (load(LEECH_MODEL) as PackedScene).instantiate() as Node3D
		victim.view.add_child(node)
		# Drawn on the victim, -5 to +4 units off on each axis (rcPlayerState.cpp).
		node.transform = Transform3D(BattleWorld.effect_basis(1.0), Original.to_godot(Vector2(randi_range(-5, 4), randi_range(-5, 4))) - Original.to_godot(Vector2.ZERO))
		MechView.play_effect(node, true)
	if not _leeches.has(victim.id):
		_leeches[victim.id] = []
	(_leeches[victim.id] as Array).append({"attacker": attacker, "time": LEECH_TIME, "node": node})

## Takes the bombs off a mech: all of them, or the first only.
func _drop_leech(victim_id: int, all := true) -> Array:
	var list: Array = _leeches.get(victim_id, [])
	var gone: Array = list.duplicate() if all else list.slice(0, 1)
	for e: Dictionary in gone:
		list.erase(e)
		if e.get("node") and is_instance_valid(e["node"]):
			(e["node"] as Node3D).queue_free()
	if list.is_empty():
		_leeches.erase(victim_id)
	return gone

## The owner's call: explode (damage landed: every bomb; time up: the first) or defuse (a
## teammate's shot: every bomb).
func _leech_release(victim: Mech, explode: bool, all := true) -> void:
	if not _leeches.has(victim.id):
		return
	_leech_burst(victim.id, explode, all)
	if _networked():
		_net_leech_burst.rpc(victim.id, explode, all)

@rpc("any_peer", "call_remote", "reliable")
func _net_leech_burst(victim_id: int, explode: bool, all: bool) -> void:
	_leech_burst(victim_id, explode, all)

## Every machine shows it; each hurts only the mechs it owns (no team check).
func _leech_burst(victim_id: int, explode: bool, all: bool) -> void:
	var gone := _drop_leech(victim_id, all)
	if gone.is_empty() or not mechs.has(victim_id):
		return
	var at := (mechs[victim_id] as Mech).sim.pos
	for e: Dictionary in gone:
		BattleWorld.hit_flash(self, at, LEECH_BLAST if explode else LEECH_DEFUSED)
		if not explode:
			continue
		for m: Mech in mechs.values():
			if not _owns(m):
				continue
			var amount := Combat.splash_falloff(LEECH_DAMAGE, LEECH_RADIUS, m.sim.pos.distance_to(at))
			_special_hit(m, int(e["attacker"]), int(amount * m.sim.damage_taken_mul()), 52)

func _step_leeches(dt: float) -> void:
	for id in _leeches.keys():
		if not mechs.has(id):
			_drop_leech(id)
			continue
		for e: Dictionary in _leeches[id]:
			e["time"] -= dt
		var first: Dictionary = (_leeches[id] as Array)[0]
		if first["time"] <= 0.0 and _owns(mechs[id]):
			_leech_release(mechs[id], true, false)

# Plasma Wire -----------------------------------------------------------------------------

func _add_tether(attacker: int, victim: int) -> void:
	var node := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(CHAIN_TEXTURE) if ResourceLoader.exists(CHAIN_TEXTURE) else null
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_repeat = true
	node.material_override = mat
	node.mesh = ImmediateMesh.new()
	add_child(node)
	_tethers.append({"attacker": attacker, "victim": victim, "time": TETHER_TIME, "length": 0.0, "node": node})

## The pull is the owner's to apply to its own mech, before it moves this tick.
func _step_tethers(dt: float) -> void:
	for m: Mech in mechs.values():
		m.sim.pull_velocity = Vector2.ZERO
	for i in range(_tethers.size() - 1, -1, -1):
		var t: Dictionary = _tethers[i]
		t["time"] -= dt
		var a: Mech = mechs.get(t["attacker"])
		var v: Mech = mechs.get(t["victim"])
		if t["time"] <= 0.0 or a == null or v == null or a.sim.life <= 0 or v.sim.life <= 0:
			(t["node"] as Node3D).queue_free()
			_tethers.remove_at(i)
			continue
		var d := v.sim.pos - a.sim.pos
		var dist := d.length()
		t["length"] = minf(dist, float(t["length"]) + CHAIN_GROW * dt)
		if dist > TETHER_SLACK:
			if _owns(v):
				v.sim.pull_velocity += -d / dist * TETHER_VICTIM_PULL * dist
			if _owns(a):
				a.sim.pull_velocity += d / dist * TETHER_ATTACKER_PULL * dist

func _draw_tethers() -> void:
	for t: Dictionary in _tethers:
		var a: Mech = mechs.get(t["attacker"])
		var v: Mech = mechs.get(t["victim"])
		var mesh := (t["node"] as MeshInstance3D).mesh as ImmediateMesh
		mesh.clear_surfaces()
		if a == null or v == null:
			continue
		var d := v.sim.pos - a.sim.pos
		if d.length() < 1.0 or float(t["length"]) < 1.0:
			continue
		var along := d.normalized()
		var side := Vector2(-along.y, along.x) * CHAIN_WIDTH * 0.5
		var p0 := a.sim.pos
		var p1 := a.sim.pos + along * float(t["length"])
		var tiles := float(t["length"]) / CHAIN_TILE
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for e in [[p0 - side, 0.0, 0.0], [p0 + side, 1.0, 0.0], [p1 - side, 0.0, tiles], [p1 + side, 1.0, tiles]]:
			mesh.surface_set_uv(Vector2(e[1], e[2]))
			mesh.surface_add_vertex(Original.to_godot(e[0]))
		mesh.surface_end()

# Teleport Beam ---------------------------------------------------------------------------

## RG_TELEPORT_ACK: the shooter to where the beam is, stopped, fading back in.
func _teleport(m: Mech, to: Vector2) -> void:
	m.sim.teleport_to(to)
	_fading[m.id] = 0.0
	if _networked() and m.local:
		_net_teleport.rpc(to)

@rpc("any_peer", "call_remote", "reliable")
func _net_teleport(to: Vector2) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mechs.has(id):
		var m: Mech = mechs[id]
		m.sim.real_pos = to
		m.sim.pos = to
		_fading[id] = 0.0

# Split shots and links -------------------------------------------------------------------

## rc_bullet::create_child (MP7-C3, PTL Type 1): when the round's time runs out it breaks into
## create_child rounds of child_id, fanned over degree_to_emit_child from -half, or spaced
## 360 / n from the heading when that is 0. Each chases the nearest enemy of the shooter within
## the child's detecting_area of the burst, if the child homes. Every machine makes them.
func _spawn_children(b: Bullet) -> void:
	var shooter_id: int = b.get_meta("shooter")
	var shooter: Mech = mechs.get(shooter_id)
	if shooter == null:
		return
	var child := GameData.weapon(int(b.weapon.mode_num("child_id")))
	var n := b.child_count()
	var spread := b.weapon.mode_num("degree_to_emit_child")
	var heading := float(Original.deg_from_vec2(b.dir.x, b.dir.y))
	var chase: MechSim = null
	var best := child.mode_num("detecting_area")
	for m: Mech in mechs.values():
		if m.id == shooter_id or m.sim.life <= 0 or Room.teammates(m.team, shooter.team):
			continue
		var d := m.sim.pos.distance_to(b.plane_pos)
		if d <= best:
			best = d
			chase = m.sim
	for k in n:
		var deg := heading + k * 360.0 / n
		if spread > 0.0:
			deg = heading - spread / 2.0 + (k * spread / (n - 1) if n > 1 else spread / 2.0)
		var c := Bullet.new()
		add_child(c)
		c.setup(b.plane_pos, (int(roundf(deg)) % 360 + 360) % 360, shooter.sim, child, chase)
		c.set_meta("shooter", shooter_id)
		bullets.append(c)

## World::process_link_hit (Fragment Cannon): after a hit on a mech (hit) or a wall at at, one
## more round 30 units on toward the hit mech's nearest teammate within linked_hit_distance
## (not the shooter), else the mech nearest it; after a wall, the shooter's nearest enemy
## within that distance, else anyone nearest; else a random way. No network message.
func _link(b: Bullet, at: Vector2, hit: Mech) -> void:
	if b.links_left <= 0 and b.linked:
		return
	var shooter_id: int = b.get_meta("shooter")
	var reach := b.weapon.param_num("linked_hit_distance")
	var from := hit.sim.pos if hit else at
	var aim: Mech = null
	var near := INF
	for m: Mech in mechs.values():
		if m == hit or m.sim.life <= 0:
			continue
		var d := m.sim.pos.distance_to(from)
		var wanted := (Room.teammates(m.team, hit.team) and m.id != shooter_id) if hit else (m.id != shooter_id and not Room.teammates(m.team, _team_of_id(shooter_id)))
		if wanted and d <= reach and d < near:
			near = d
			aim = m
	if aim == null:
		near = INF
		for m: Mech in mechs.values():
			if m == hit or m.sim.life <= 0:
				continue
			var d := m.sim.pos.distance_to(from)
			if d < near:
				near = d
				aim = m
	var dir := (aim.sim.pos - at).normalized() if aim and aim.sim.pos.distance_to(at) > 0.01 else Original.vec2_from_deg(randi() % 360)
	var link := Bullet.new()
	add_child(link)
	link.setup(at + dir * LINK_OFFSET, Original.deg_from_vec2(dir.x, dir.y), b.owner_sim, b.weapon)
	link.speed = LINK_SPEED
	link.power = b.weapon.damage - LINK_DAMAGE_CUT
	link.linked = true
	link.links_left = (b.links_left if b.linked else int(b.weapon.param_num("linked_hit_num"))) - 1
	link.set_meta("shooter", shooter_id)
	bullets.append(link)

## An X-Mine looking for a target from where it lies.
func _mine_target(owner_id: int, at: Vector2, detect_range: float) -> MechSim:
	var players := []
	var owner_team := _team_of_id(owner_id)
	for m: Mech in mechs.values():
		if m.id != owner_id and Room.teammates(m.team, owner_team):
			continue
		players.append([m.id, m.sim.pos, m.sim.life > 0])
	var id := Combat.mine_target(owner_id, at, detect_range, players)
	return (mechs[id] as Mech).sim if id != 0 and mechs.has(id) else null

## rc_bullet::explosion for a splash shell at a point: every mech within the radius, on the
## machine that owns it, takes the falloff damage. The shooter is not spared (no exclusion in
## the original). direct: the mech that took the shell itself, if any; a guard facing the
## shell leaves it splash_damage plus damage x splash_ratio. A weapon with jamming_time (the
## EMP) reports even a 0 hit, which is what jams the radar; its direct hit also sends the
## state change, once per mech in the loop.
func _explode(b: Bullet, at: Vector2, direct: Mech = null) -> void:
	BattleWorld.hit_flash(self, at, b.boom_scene())
	var shooter: int = b.get_meta("shooter")
	var radius := b.weapon.splash_area
	var splash := b.weapon.mode_num("splash_damage")
	var jams := b.weapon.mode_num("jamming_time") > 0.0
	var in_radius := 0
	for m: Mech in mechs.values():
		if m.sim.life <= 0 or m.sim.is_pulse():
			continue
		var d := m.sim.pos.distance_to(at)
		if d <= radius:
			in_radius += 1
		var amount := 0
		if m == direct:
			var power := b.power
			if _owns(m) and round_active and m.sim.guards_against(b.prev_pos):
				power = int(b.power * b.weapon.mode_num("splash_ratio"))
				_guarded(m, b.weapon_id, -1, false)
			amount = Combat.splash_direct(splash, power, radius, d)
		else:
			amount = Combat.splash_falloff(splash, radius, d)
		if amount > 0 or (jams and d <= radius):
			# The Napalm Thrower's burn starts on the direct hit, guarded or not: the SPLASH
			# branch runs before the guard test (world.cpp 2098).
			if _apply_hit(m, shooter, amount, b.weapon_id) and m == direct and b.weapon_id == 44:
				_state_change(m, 44, amount, shooter)
	if direct and _owns(direct) and round_active and b.weapon.state_action_type == 4:
		_state_change(direct, b.weapon_id, maxi(1, in_radius))

## Sets off a shooter's live shells that go off on button release. True if any did.
func _detonate_shells(shooter: int) -> bool:
	var any := false
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		if int(b.get_meta("shooter")) != shooter or not b.detonates_on_release():
			continue
		if b.weapon_id == 49:
			# The Teleport Beam: its shooter's machine moves it there (_step_bullets).
			BattleWorld.hit_flash(self, b.plane_pos, b.boom_scene())
			if mechs.has(shooter) and (mechs[shooter] as Mech).local:
				_teleport(mechs[shooter], b.plane_pos)
		else:
			_explode(b, b.plane_pos)
		b.queue_free()
		bullets.remove_at(i)
		any = true
	return any

## Every screen flies every bullet. Damage is decided by whoever owns the mech that was hit:
## the local player for their own mech, this machine for the practice dummy. Other screens
## only show the impact and wait for the victim's report. Split rounds, links and the teleport
## run on every screen from the same flight; the teleport is the shooter's machine's call.
func _step_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		var prev := b.plane_pos
		var shooter: int = b.get_meta("shooter")
		var shooter_team := _team_of_id(shooter)
		# auto_explosion (PTL Type 1): an enemy within the area cuts the time short.
		if b.weapon.mode.get("auto_explosion", false) == true:
			var near := false
			for m: Mech in mechs.values():
				if m.id != shooter and m.sim.life > 0 and not Room.teammates(m.team, shooter_team) \
						and m.sim.pos.distance_to(b.plane_pos) <= b.weapon.mode_num("auto_explosion_area"):
					near = true
			b.proximity_fuse(near)
		var alive := b.advance(dt)
		# A missile or splash shell that runs out explodes (explosion(true)); only splash hurts.
		# A round with create_child breaks into its children then.
		if not alive:
			if b.weapon.is_splash():
				_explode(b, b.plane_pos)
			elif b.guided > 0 or b.child_count() > 0:
				BattleWorld.hit_flash(self, b.plane_pos, b.boom_scene())
			if b.child_count() > 0:
				_spawn_children(b)
		# World::update: a bullet that meets a wall stops there (rc_map::is_crashed_with_object)
		# with explosion(crashed_pos), which only shows the effect. The Cluster Cannon (11)
		# alone calls explosion(), the splash, where the shell is.
		if alive and map:
			var wall: Variant = map.collision.segment_hit(prev, b.plane_pos)
			if wall != null:
				alive = false
				if b.weapon_id == 11:
					_explode(b, b.plane_pos)
				else:
					BattleWorld.hit_flash(self, wall, b.boom_scene())
				if b.weapon.param.get("linked_hit", false) == true:
					_link(b, wall, null)
		for m: Mech in mechs.values():
			if not alive:
				break
			if m.sim.life <= 0 or m.sim.is_pulse():
				continue
			# Only the Fragment Cannon can hit its own shooter, 0.2 s into the flight.
			var own := m.id == shooter
			if own and not (b.weapon_id == 39 and b.age >= SELF_HIT_AGE):
				continue
			var mate := not own and Room.teammates(m.team, shooter_team)
			if mate and not b.linked:
				# A teammate's shot through a mech carrying a leech bomb defuses it.
				if _owns(m) and _leeches.has(m.id) and b.hits(m.sim.pos, m.sim.crash_radius):
					_leech_release(m, false)
				continue
			if not b.hits(m.sim.pos, m.sim.crash_radius):
				continue
			alive = false
			if b.weapon.is_splash():
				_explode(b, b.plane_pos, m)
				continue
			BattleWorld.hit_flash(self, b.plane_pos, b.boom_scene())
			if b.weapon.param.get("linked_hit", false) == true:
				_link(b, b.plane_pos, m)
			# A link on a teammate, or the cannon on its shooter: taken up, nothing lands.
			if own or mate:
				continue
			# The Teleport Beam does no damage.
			if b.power <= 0 and b.weapon.state_action_type == 0:
				continue
			# World::state_change on the victim's machine, only for a hit no guard stopped:
			# the Plasma Bow stuns and pushes, the Confusing Beam confuses, and so on.
			if _apply_hit(m, shooter, b.power, b.weapon_id, b.prev_pos):
				if b.weapon.state_action_type == 3:
					_stun(m, b.charge, b.dir)
				elif b.weapon.state_action_type in [5, 9]:
					_state_change(m, b.weapon_id, 1, shooter)
				elif b.weapon.state_action_type == 6:
					# Viper Smart Gun: the hit's charge level rides in the count.
					_state_change(m, b.weapon_id, b.charge, shooter)
				elif b.weapon_id in HIT_STATES:
					_state_change(m, b.weapon_id, 1, shooter)
		# Teleport Beam: the shooter goes where the beam is when it ends, or as soon as the
		# button is not held (rcAmmo.cpp: every frame the owner is not holding it).
		if b.weapon_id == 49 and mechs.has(shooter) and (mechs[shooter] as Mech).local:
			if alive and not _prev_fire_local:
				alive = false
				BattleWorld.hit_flash(self, b.plane_pos, b.boom_scene())
				if _networked():
					_net_detonate.rpc()
			if not alive:
				_teleport(mechs[shooter], b.plane_pos)
		# Other screens do not draw a mine lying in wait (no is_stealth model); its owner does.
		if alive and b.mine:
			b.visible = not b.is_lying() or (mechs.has(shooter) and _owns(mechs[shooter]))
		if not alive:
			b.queue_free()
			bullets.remove_at(i)

## Applies a hit report on this machine: tallies, the victim's life, the hit reaction and the
## HIT or DAMAGE marker (World::damage_respond).
func _record_hit(victim_id: int, attacker_id: int, amount: int, remaining: int, weapon_id: int) -> void:
	if not mechs.has(victim_id):
		return
	var victim: Mech = mechs[victim_id]
	victim.sim.life = remaining
	if _netlog:
		print("  hit %d -> %d: %d with %s, %d left" % [attacker_id, victim_id, amount, GameData.weapon(weapon_id).name, remaining])
	# Hitting a teammate (splash) earns no points; the kill still counts (kill_user_num).
	if stats.has(attacker_id) and not Room.teammates(victim.team, _team_of_id(attacker_id)):
		(stats[attacker_id] as Stats).damage += amount
	if remaining > 0:
		victim.view.play_damage()
	elif stats.has(attacker_id) and attacker_id != victim_id:
		(stats[attacker_id] as Stats).kills += 1
	# myplayer_is_damaged: the EMP blanks your radar for jamming_time, any hit, even 0.
	var jamming := GameData.weapon(weapon_id).mode_num("jamming_time")
	if victim_id == local_id and jamming > 0.0:
		hud.jam_time = jamming
	# on_bullet_explosion: the attacker's weapon hit sound at the mech that was hit.
	sound.play_at(Bodies.sounds(weapon_id)[1], victim.sim.pos)
	# scar_effect: the bow's caution mark over the one hit.
	var scar := Bodies.scene_path(str(GameData.weapon(weapon_id).param.get("scar_effect", "")))
	if scar != "":
		BattleWorld.spawn_effect(self, scar, BattleWorld.effect_basis(1.0), victim.sim.pos, 1.5)
	# on_damage: the camera shakes for the one hit, by the attacker's weapon slot (WEAPON_3
	# 0.25 s at power 10, WEAPON_2 0.1 s at power 4).
	if victim_id == local_id and mechs.has(attacker_id):
		var slot := (mechs[attacker_id] as Mech).weapons.find(weapon_id)
		if slot == 2:
			_shake(0.25, 10)
		elif slot == 1:
			_shake(0.1, 4)
	# World::process_damage: the marker goes 100 units up the plane from your own mech.
	var me := _local()
	if me == null:
		return
	if victim_id == local_id:
		BattleWorld.font_marker(self, me.sim.pos + Vector2(0, 100), false)
	elif attacker_id == local_id:
		BattleWorld.font_marker(self, me.sim.pos + Vector2(0, 100), true)
		hud.show_target(Bodies.face(victim.body), float(maxi(0, remaining)) / float(victim.sim.life_max), _mech_name(victim))

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
	var jolt := _shake_offset(dt)
	camera.position = Vector3(cam_from.x + jolt, -cam_from.y, -(cam_from.z + jolt))
	camera.look_at(Vector3(to.x + jolt, 0, -(to.z + jolt)), Vector3(0, 0, -1))
	if sky:
		BattleWorld.place_sky(sky, camera)

## World::shake_camera(time, power)
func _shake(time: float, power: int) -> void:
	_shake_time = time
	_shake_power = power

## World::shaking: 30 times a second the camera and its target jump by +-(power + 0..5)
## on both plane axes, alternating sides, while the shake lasts.
var _jolt := 0.0
func _shake_offset(dt: float) -> float:
	if _shake_time <= 0.0:
		return 0.0
	_shake_time -= dt
	_shake_tick -= dt
	if _shake_tick <= 0.0:
		_shake_tick = 1.0 / 30.0
		_shake_sign = -_shake_sign
		_jolt = float(randi() % 6 + _shake_power) * _shake_sign
	return _jolt if _shake_time > 0.0 else 0.0

# --- Autopilot --------------------------------------------------------------------------

## Scripted duel for recordings and checks. With an enemy: close to firing range, strafe
## around them with boost bursts, fire when in range. Without one: a walk-boost-fire route.
## Test driver: a 1.2 s cycle of key taps, each within the original's 0.2 s limit.
func _combo_keys(it: MechSim.Intent, facing: int, t: float) -> void:
	var deg := (facing % 360 + 360) % 360
	var fwd := "right"
	if deg >= 45 and deg < 135:
		fwd = "up"
	elif deg >= 135 and deg < 225:
		fwd = "left"
	elif deg >= 225 and deg < 315:
		fwd = "down"
	var back: String = {"right": "left", "left": "right", "up": "down", "down": "up"}[fwd]
	for k in ["left", "right", "up", "down"]:
		it.set(k, false)
	it.boost = false
	it.fire = (t >= 0.10 and t < 0.14) or (t >= 0.37 and t < 0.41)
	if t >= 0.05 and t < 0.08:
		it.set(fwd, true)
	elif t >= 0.25 and t < 0.28:
		it.set(back, true)
	elif t >= 0.31 and t < 0.34:
		it.set(fwd, true)

var _stuck_check := 0.0
var _stuck_from := Vector2.ZERO
var _unstick_time := 0.0
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
	# Cycle through the usable slots every 8 s, pressing the key for a few frames.
	var wanted_slot: int = (int(_clock / 8.0) + 1) % m.sim.slots.size()
	if _autopilot_slot > 0:
		wanted_slot = mini(_autopilot_slot, m.sim.slots.size()) - 1
	if m.sim.weapon_index != wanted_slot and fmod(_clock, 0.5) < 0.1:
		it.weapon_key = wanted_slot + 1
	var to := enemy.sim.pos - m.sim.pos
	var dist := to.length()
	it.aim = enemy.sim.pos
	var w := m.sim.weapon
	var reach := w.crash_radius * 0.9 if w.is_sword() else (w.line_distance * 0.9 if w.is_immediate() else (w.lockon_range() * 0.8 if w.lockon_range() > 0.0 else w.bullet_speed * w.life))
	if w.is_mine():
		reach = w.mode_num("detecting_area") * 0.8
	elif w.is_sword() and w.crash_radius <= 0.0:
		# Void Pulse hits nothing; use it once an enemy is close.
		reach = 200.0
	elif reach <= 0.0:
		# Self-use specials (D Fielder, Over Booster): use them once an enemy is close.
		reach = 300.0
	elif not w.is_sword() and not w.is_immediate() and w.lockon_range() <= 0.0:
		# Straight shots: stay close enough to keep both mechs in the original camera's view.
		reach = minf(reach, 260.0)
	var near_d := reach * 0.5 if not w.is_sword() else 0.0
	var side := 1.0 if fmod(_clock + m.slot * 2.5, 5.0) < 2.5 else -1.0
	var want := to.normalized() if dist > reach * 0.8 else (-to.normalized() if dist < near_d else Vector2(-to.y, to.x).normalized() * side)
	# Test driver only: pinned on a wall for 1.5 s, sidestep for a second.
	_stuck_check += get_physics_process_delta_time()
	if _stuck_check >= 1.5:
		_unstick_time = 1.0 if m.sim.pos.distance_to(_stuck_from) < 30.0 else 0.0
		_stuck_check = 0.0
		_stuck_from = m.sim.pos
	if _unstick_time > 0.0:
		_unstick_time -= get_physics_process_delta_time()
		want = Vector2(-to.y, to.x).normalized()
	it.right = want.x > 0.35
	it.left = want.x < -0.35
	it.up = want.y > 0.35
	it.down = want.y < -0.35
	it.boost = m.sim.booster_gage > 600.0 and dist > reach * 1.5
	# In reach: hold a continuous weapon, draw a charge weapon for 1.6 s, click the rest five
	# times a second.
	if w.is_continuous:
		it.fire = dist < reach and fmod(_clock, 3.0) < 2.0
	elif w.is_charge():
		it.fire = dist < reach and fmod(_clock, 2.0) < 1.6
	elif int(w.mode_num("button_up_explosion")) == 1:
		# Hold while the shell flies; let go once it is over the target.
		var has_shell := false
		var shell_near := false
		for b in bullets:
			if int(b.get_meta("shooter")) == m.id and b.detonates_on_release():
				has_shell = true
				shell_near = shell_near or b.plane_pos.distance_to(enemy.sim.pos) < w.splash_area * 0.3
		it.fire = (has_shell and not shell_near) or (not has_shell and dist < reach and fmod(_clock, 0.5) < 0.25)
	else:
		it.fire = dist < reach and fmod(_clock, 0.2) < 0.1
	if _autocombos and w.is_sword() and dist < reach * 1.2:
		_combo_keys(it, m.sim.facing, fmod(_clock, 1.2))
	if _autoguard:
		var c := fmod(_clock, 8.0)
		var want_guard := c >= 5.0 and c < 7.0
		it.guard = want_guard != m.sim.guarding and fmod(_clock, 0.5) < 0.1
		if m.sim.guarding:
			it.fire = false
	return it
