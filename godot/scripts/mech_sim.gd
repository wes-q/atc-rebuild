class_name MechSim
extends RefCounted
## One mech's movement, boost gauge, facing and rifle, following the original client:
## rcPlayerManager::updatemove, update_booster, updaterotation, recv_move, recv_stop and
## rcPlayer::update. Pure logic in original units on the original plane, so it can be
## tested headless.

## Per-frame intent, already in original plane coordinates.
class Intent:
	var left := false
	var right := false
	var up := false
	var down := false
	var boost := false ## right mouse button
	var fire := false ## left mouse button
	var aim := Vector2.ZERO ## point under the mouse, on the plane

	func move_dir() -> Vector2:
		var d := Vector2(float(right) - float(left), float(up) - float(down))
		return d.normalized() if d.length_squared() > 0.001 else Vector2.ZERO

	func any_move() -> bool:
		return left or right or up or down

signal fired(origin: Vector2, deg: int)
## Fully destroyed: is_dead_complete in rcPlayer::update_dead. The mech stops being drawn.
signal exploded
## Pushed back off the arena edge (rc_map::crashed_with_wall), for the wall_crash effect.
signal wall_crashed(point: Vector2, normal: Vector2)
## rcPlayerManager::on_booster, for the sp_booster sound. The owner's client calls it when a
## boost starts; other clients call it for every boosting move message they receive.
signal boost_started

# Stats from the original database, via GameData.
var stats: GameData.Robot
var weapon: GameData.Weapon
var move_speed: float
var booster_speed: float
var booster_init_speed: float
var energy_max: float
var energy_reduce: float
var regenerate: float
var energy_low_line: float
var rotation_speed: float
var crash_radius: float
var life_max: int
var boost_accel: float
var vel_limit: float

# State.
var pos := Vector2.ZERO
var facing := 0 ## integer degrees, like mRotation
var move_dir := Vector2.ZERO
var vel_scalar := 0.0
var acc_flag := false ## boosting
var booster_init_time := 0.0
var booster_init_acc := 1.0
var acc_gap := 0.0
var add_vel := 0.0
var booster_gage := 0.0
var booster_warning_time := 0.0
var life := 0
var speed_state := 0 ## last move protocol speed: 0 stop, 1 move, 2 boost
var previous_pos := Vector2.ZERO

# Map collision. The original ran it for the local player only (rc_map::update), so remote
# copies just show where their owner put them.
var map: BattleMap
## Pushed by a wall: input is ignored until close to the dash point (is_my_player_dashing).
var dashing := false
var _dash_target := Vector2.ZERO
## recv_stop left lastRealPos at the dash point, so a mech left standing keeps easing there.
var _settling := false

# Booster_Input_Catcher.
enum BoosterInput { NOTHING, COUNT, BOOST_START, BOOST, BOOST_END }
var _booster_input := BoosterInput.NOTHING

# Arrow key edges, like bDownRotate* and bUpRotate*.
var _prev_keys := [false, false, false, false]

# Weapon (rcWeaponMode, rc_Weapon::update_bullet). Starts charged.
var recharge := 0.0
var _burst_left := 0
var _burst_timer := 0.0
var _attack_time := 0.0
var attacking := false

## body: RobotInfo name. weapon_slot: index into its default weapons (1 = second slot).
func _init(body := "zeid", weapon_slot := 1) -> void:
	stats = GameData.robot(body)
	weapon = GameData.weapon(stats.weapons[weapon_slot])
	move_speed = stats.move_speed
	booster_speed = stats.booster_speed
	booster_init_speed = stats.booster_init_speed
	energy_max = stats.energy_max
	energy_reduce = stats.energy_reduce
	regenerate = stats.regenerate
	energy_low_line = stats.energy_low_line
	rotation_speed = stats.rotation_speed
	crash_radius = stats.crash_radius
	boost_accel = stats.boost_accel
	vel_limit = stats.vel_limit
	life_max = stats.life
	life = life_max
	booster_gage = energy_max
	recharge = weapon.reload

# Death (rcPlayer::update_dead). life <= 0 stops the mech and blocks input; 0.1 s later
# (time_to_dead_complete) it is fully destroyed.
const TIME_TO_DEAD_COMPLETE := 0.1
var is_dead := false
var is_dead_complete := false
var _dead_time := 0.0

## Applies a hit. Returns true if this hit knocked the mech out.
func take_damage(amount: int) -> bool:
	if life <= 0:
		return false
	life = maxi(0, life - amount)
	return life <= 0

func step(intent: Intent, dt: float) -> void:
	if _update_dead(dt):
		return
	previous_pos = pos
	_update_booster_gauge(intent, dt)
	_update_move(intent)
	_update_rotation(intent, dt)
	_update_physics(dt)
	_update_dash(intent)
	_update_map()
	_update_rifle(intent, dt)
	booster_warning_time = maxf(0.0, booster_warning_time - dt)

## Returns true while dead, so nothing else runs.
func _update_dead(dt: float) -> bool:
	if life > 0:
		return false
	if not is_dead:
		is_dead = true
		_dead_time = TIME_TO_DEAD_COMPLETE
		_send_move(0, 0)
		_burst_left = 0
		attacking = false
		_last_vel = 0.0
	if not is_dead_complete:
		_dead_time -= dt
		if _dead_time <= 0.0:
			is_dead_complete = true
			exploded.emit()
	return true

## rcPlayerManager::update_booster. Drains while the button is held, otherwise recovers,
## at half rate below the low line. An empty gauge drops a boost back to walking.
func _update_booster_gauge(intent: Intent, dt: float) -> void:
	if intent.boost:
		booster_gage -= energy_reduce * dt
		if booster_gage <= 0.0:
			booster_gage = 0.0
			booster_warning_time = 1.5
			if vel_scalar >= booster_speed and intent.any_move():
				_send_move(_deg(intent), 1)
	else:
		var rate := regenerate if booster_gage > energy_low_line else regenerate * 0.5
		booster_gage = minf(energy_max, booster_gage + rate * dt)

## rcPlayerManager::updatemove: turns key and button edges into move protocol messages.
func _update_move(intent: Intent) -> void:
	var keys := [intent.left, intent.right, intent.up, intent.down]
	var went_down := false
	var went_up := false
	for i in 4:
		went_down = went_down or (keys[i] and not _prev_keys[i])
		went_up = went_up or (not keys[i] and _prev_keys[i])
	_prev_keys = keys

	# rcPlayerManager::updatemove: no move input until a dash has fully ended.
	if dashing:
		return

	var by_speed := 2 if intent.boost else 1
	var md := intent.move_dir()

	if md == Vector2.ZERO and _is_moving() and by_speed == 1:
		_send_move(0, 0)
		return

	match _advance_booster_input(intent.boost):
		BoosterInput.BOOST_START:
			if md == Vector2.ZERO:
				return
			if booster_gage > energy_low_line:
				_send_move(_deg(intent), by_speed)
				boost_started.emit()
			else:
				booster_warning_time = 1.5
			return
		BoosterInput.BOOST_END:
			_send_move(_deg(intent), 1 if intent.any_move() else 0)
			return

	if went_down:
		_send_move(_deg(intent), by_speed)
	elif went_up:
		if intent.any_move():
			_send_move(_deg(intent), by_speed)
		else:
			_send_move(Original.deg_from_vec2(move_dir.x, move_dir.y), 0)

func _advance_booster_input(pressed: bool) -> int:
	match _booster_input:
		BoosterInput.NOTHING:
			if pressed:
				_booster_input = BoosterInput.COUNT
		BoosterInput.COUNT:
			if pressed:
				_booster_input = BoosterInput.BOOST_START
		BoosterInput.BOOST_START:
			_booster_input = BoosterInput.BOOST
		BoosterInput.BOOST:
			if not pressed:
				_booster_input = BoosterInput.BOOST_END
		BoosterInput.BOOST_END:
			_booster_input = BoosterInput.NOTHING
	return _booster_input

## Local echo of a move message: recv_move for speed 1 and 2, recv_stop for 0.
func _send_move(deg: int, speed: int) -> void:
	speed_state = speed
	if speed != 0:
		_settling = false
	if speed == 0:
		acc_flag = false
		move_dir = Vector2.ZERO
		vel_scalar = 0.0
		return
	move_dir = Original.vec2_from_deg(deg)
	if speed == 1:
		vel_scalar = move_speed
		acc_flag = false
	else:
		acc_flag = true
		vel_scalar = booster_init_speed
		booster_init_time = 0.001

## rcPlayerManager::updaterotation: turn toward the mouse at rotation_speed, stop once close.
func _update_rotation(intent: Intent, dt: float) -> void:
	var to_mouse := intent.aim - pos
	if to_mouse.length_squared() < 1.0:
		return
	var target := Original.deg_from_vec2(to_mouse.x, to_mouse.y)
	var cur := Original.vec2_from_deg(facing)
	if cur.dot(to_mouse.normalized()) > Original.TURN_SNAP_DOT:
		return
	var diff := wrapf(float(target - facing), -180.0, 180.0)
	var turn := minf(absf(diff), rotation_speed * dt)
	facing = (facing + int(roundf(signf(diff) * maxf(turn, 1.0))) + 360) % 360

## rcPlayer::update, in the original order: acceleration ticks every 0.1 s and grows
## quadratically, the boost start kick decays into it, everything capped at vel_limit.
func _update_physics(dt: float) -> void:
	acc_gap += dt
	if acc_flag:
		if acc_gap > 0.1:
			booster_init_acc += acc_gap * 10.0 * acc_gap * 10.0 * 0.5
			add_vel += boost_accel * acc_gap * 10.0 * booster_init_acc
			acc_gap = 0.0
			add_vel = minf(add_vel, vel_limit)
	else:
		acc_gap = 0.0
		add_vel = 0.0
	var player_vel := vel_scalar + add_vel
	if booster_init_time > Original.BOOSTER_INIT_HOLD:
		if vel_scalar < booster_speed:
			booster_init_time = 0.0
			booster_init_acc = 1.0
			vel_scalar = booster_speed if acc_flag else move_speed
		else:
			vel_scalar -= add_vel
	elif booster_init_time != 0.0:
		booster_init_time += dt
		player_vel -= add_vel
	player_vel = minf(player_vel, vel_limit)
	_last_vel = player_vel
	pos += move_dir * player_vel * dt
	if _settling:
		pos += (_dash_target - pos) * Original.DASH_EASE

## rcPlayer::start_dash with bstop, as echoed back by the server: recv_dash, then recv_stop
## with the destination as lastRealPos.
func start_dash(dest: Vector2) -> void:
	_send_move(0, 0)
	_dash_target = dest
	dashing = true
	_settling = true

## rcPlayer::end_dash: once close, give control back and resume walking if a key is held.
func _update_dash(intent: Intent) -> void:
	if not dashing or pos.distance_to(_dash_target) > Original.DASH_END_DISTANCE:
		return
	dashing = false
	if intent.any_move():
		_send_move(_deg(intent), 1)

## rc_map::update: wall triangles first, then the arena rectangle.
func _update_map() -> void:
	if map == null:
		return
	var contact := map.collision.sphere_contact(pos, crash_radius)
	if not contact.is_empty():
		# crashed_with_object: a short push straight out of the wall.
		start_dash(pos + contact["normal"] * Original.OBJECT_PUSH)
		return
	# process_map_bound: ignored while dashing from outside to outside.
	if dashing and not map.in_bounds(pos) and not map.in_bounds(previous_pos):
		return
	var crash := map.bound_crash(pos, previous_pos)
	if crash.is_empty():
		return
	pos = crash["point"]
	start_dash(BattleMap.wall_bounce_target(crash))
	wall_crashed.emit(crash["point"], crash["normal"])

## rcWeaponMode::fire queues continuous_number bullets, each continuous_time after the last
## (rc_Weapon::update_bullet). Recharge waits re_load_time and pauses during the fire animation.
func _update_rifle(intent: Intent, dt: float) -> void:
	if _burst_left > 0:
		_burst_timer -= dt
		while _burst_left > 0 and _burst_timer <= 0.0:
			fired.emit(pos, facing)
			_burst_left -= 1
			if _burst_left > 0:
				_burst_timer += weapon.fire_interval
	if attacking:
		_attack_time -= dt
		if _attack_time <= 0.0 and _burst_left == 0:
			attacking = false
		return
	recharge = minf(recharge + dt, weapon.reload)
	if intent.fire and recharge >= weapon.reload:
		recharge = 0.0
		attacking = true
		_attack_time = Original.ATTACK_TIME
		_burst_left = weapon.fire_num
		_burst_timer = weapon.fire_interval

func _is_moving() -> bool:
	return vel_scalar > 0.0 or move_dir != Vector2.ZERO

func _deg(intent: Intent) -> int:
	var md := intent.move_dir()
	return Original.deg_from_vec2(md.x, md.y)

var _last_vel := 0.0

## Speed actually applied last frame.
func speed() -> float:
	return _last_vel if move_dir != Vector2.ZERO else 0.0

## Which movement clip the original would play (rcPlayerManager::update_animation_state).
func move_clip() -> int:
	if speed_state == 0 or move_dir == Vector2.ZERO:
		return -1
	var forward := move_dir.dot(Original.vec2_from_deg(facing)) > 0.0
	if forward:
		return Original.MOVE_BOOSTER_FORWARD if acc_flag else Original.MOVE_FORWARD
	return Original.MOVE_BOOSTER_BACK if acc_flag else Original.MOVE_BACK

# --- Network -----------------------------------------------------------------------------
# Each player moves their own mech and broadcasts its state, like the original client did
# with its move protocol. Remote copies only display that state.

## Reported position, advanced by velocity between packets (rcPlayer::lastRealPos).
var real_pos := Vector2.ZERO
var _has_snapshot := false

## Owner's state, sent every physics tick.
func snapshot() -> Array:
	return [pos.x, pos.y, facing, move_dir.x, move_dir.y, _last_vel, int(acc_flag),
		speed_state, int(attacking), life, booster_gage, int(is_dead_complete)]

## Applies an owner's snapshot to a remote copy.
func apply_snapshot(s: Array) -> void:
	real_pos = Vector2(s[0], s[1])
	facing = int(s[2])
	var new_dir := Vector2(s[3], s[4])
	# A new boosting move message: the boost started or changed direction.
	if int(s[7]) == 2 and (speed_state != 2 or not new_dir.is_equal_approx(move_dir)) and _has_snapshot:
		boost_started.emit()
	move_dir = new_dir
	_last_vel = float(s[5])
	acc_flag = int(s[6]) != 0
	speed_state = int(s[7])
	attacking = int(s[8]) != 0
	life = int(s[9])
	booster_gage = float(s[10])
	is_dead = life <= 0
	is_dead_complete = s.size() > 11 and int(s[11]) != 0
	if not _has_snapshot:
		pos = real_pos
		_has_snapshot = true

## rcPlayer::update for remote players: carry the reported position forward at the reported
## velocity, then ease the drawn position 10% of the way toward it each tick.
func step_remote(dt: float) -> void:
	real_pos += move_dir * _last_vel * dt
	pos += (real_pos - pos) * 0.1

## Back to full health and gauge at a spawn point, standing still.
func reset_at(spawn: Vector2, face: int) -> void:
	pos = spawn
	real_pos = spawn
	facing = face
	move_dir = Vector2.ZERO
	vel_scalar = 0.0
	acc_flag = false
	add_vel = 0.0
	_last_vel = 0.0
	speed_state = 0
	life = life_max
	is_dead = false
	is_dead_complete = false
	booster_gage = energy_max
	recharge = weapon.reload
	_burst_left = 0
	attacking = false
	_booster_input = BoosterInput.NOTHING
	_prev_keys = [false, false, false, false]
	previous_pos = spawn
	dashing = false
	_settling = false
