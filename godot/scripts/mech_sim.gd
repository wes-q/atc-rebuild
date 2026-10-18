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
	var fire := false ## left mouse button, held state; attacks start on the press
	var weapon_key := 0 ## number key held this frame, 1 to 4, or 0
	var guard := false ## Space, held state; the guard toggles on the press
	var aim := Vector2.ZERO ## point under the mouse, on the plane

	func move_dir() -> Vector2:
		var d := Vector2(float(right) - float(left), float(up) - float(down))
		return d.normalized() if d.length_squared() > 0.001 else Vector2.ZERO

	func any_move() -> bool:
		return left or right or up or down

signal fired(origin: Vector2, deg: int)
## A burst of bullets starts (pt_send_shoot): the moment a guided weapon takes its target.
signal attack_started(slot: int)
## A sword swing starts: swing is the attack clip index, 2, 3 or 4 (ComboSystem). The
## command combo it carries, if any, is in swing_combo.
signal swung(slot: int, swing: int)
## rcPlayer::change_weapon
signal weapon_changed(slot: int)
## A charge weapon's level changed while drawing, or -1 when it fired.
signal charge_changed(level: int)
## Fully destroyed: is_dead_complete in rcPlayer::update_dead. The mech stops being drawn.
signal exploded
## Pushed back off the arena edge (rc_map::crashed_with_wall), for the wall_crash effect.
signal wall_crashed(point: Vector2, normal: Vector2)
## The guard went up or down (pt_send_attack_start WEAPON_GUARD / WEAPON_GUARD_CANCEL).
signal guard_changed(on: bool)
## A click while guarding with the selected weapon recharged (sound/common/shieldused).
signal shield_clicked
## rcPlayerManager::on_booster, for the sp_booster sound. The owner's client calls it when a
## boost starts; other clients call it for every boosting move message they receive.
signal boost_started

# Stats from the original database, via GameData.
var stats: GameData.Robot
## One equipped weapon in its first mode (rc_Weapon): its data, recharge and ammo.
class Slot:
	var data: GameData.Weapon
	var recharge := 0.0
	var ammo := -1
	var magazine_used := 0
	## Length of each clip in this body's attack file for the weapon: 0 draw, 1 stand, 2+ attacks.
	var clips: Array = []
	## The fire animation; recharge waits for it (BEHAVE_ATTACK until on_end_animation).
	var attack_time := Original.ATTACK_TIME

	func _init(w: GameData.Weapon, body: String) -> void:
		data = w
		clips = Bodies.clip_lengths(Bodies.weapon_view(body, w.id)["attack"])
		if clips.size() > Original.ANIM_ATTACK:
			attack_time = float(clips[Original.ANIM_ATTACK])
		reset()

	func reset() -> void:
		recharge = data.reload
		ammo = data.ammo
		magazine_used = 0

	## A combo's swings are attack clips 2 up to attack_animation_number + 1.
	func last_swing() -> int:
		return Original.SWORD_FIRST_SWING + int(data.param_num("attack_animation_number", 3)) - 1

	func swing_time(swing: int) -> float:
		return float(clips[swing]) if swing < clips.size() else Original.ATTACK_TIME

	## rc_Weapon::is_recharged: within 0.01 s of full.
	func is_ready() -> bool:
		return absf(data.reload - recharge) < 0.01
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
## Weapon slots 1 to 4 (RobotInfo default weapons, the shield taken out).
var slots: Array[Slot] = []
var weapon_index := Original.START_WEAPON
## The selected weapon's data and recharge.
var weapon: GameData.Weapon:
	get:
		return slots[weapon_index].data
var recharge: float:
	get:
		return slots[weapon_index].recharge
	set(v):
		slots[weapon_index].recharge = v
var _burst_left := 0
## Rounds fired in the current attack (switch_shot alternates hands by it).
var shot_index := 0
## Holding a continuous weapon's trigger.
var streaming := false
## Drawing a charge weapon: the level reached, -1 when not charging.
var charging := false
var charge_level := -1
var _charge_time := 0.0
## StunState: input ignored until this runs out.
var stun_time := 0.0
var body := "zeid"
var _burst_timer := 0.0
var _attack_time := 0.0
var attacking := false

# Sword combo (ComboSystem): the swing playing, whether one more is queued, time left in it.
var combo_active := false
var combo_index := 0
var _combo_queued := false
## The command combo the queued swing carries (1 for a plain click, which has no entry).
var _queued_combo := 0
## A finishing combo ended the chain: no more swings queue (ComboSystem::end_combo).
var _combo_finished := false
## combo_id of the swing that just started, 0 for none.
var swing_combo := 0

# Command combos (ComboInputManager): the sword's key sequences, read every frame. Arrow
# keys count relative to the facing: "right" is a tap toward it, "left" a tap away. Each key
# must follow the last within 0.2 s (register_combo_command), or the sequence restarts.
enum ComboKey { LEFT, RIGHT, UP, DOWN, LCLICK, RCLICK, BOTH_CLICK }
const COMBO_KEY_LIMIT := 0.2
class ComboCommand:
	var id := 0
	var keys: Array[int] = []
	var cur_key := 0
	var times: Array[float] = []

	func cancel() -> void:
		cur_key = 0
		for i in times.size():
			times[i] = 0.0
var combo_commands: Array[ComboCommand] = []
## complete_combo_id: a finished sequence waits here until a click takes it.
var combo_ready := 0
var _combo_prev := [false, false, false, false, false, false]
var _swing_time := 0.0
var _prev_fire := false
var _prev_weapon_key := 0

# Shield (player->shield, an rc_Weapon of type 5 or 6 kept out of the slots).
## The shield's data, or null for a body without one.
var shield: GameData.Weapon
## rc_Weapon::init: durability x 10; the gauge shows durability over that.
var shield_max := 0.0
var durability := 0.0
## shield_recover_amount, a second, while the guard is down and the shield is not broken.
var shield_recover := 0.0
## rcPlayer::guard: BEHAVE_GUARD until cancelled (guard_time is never counted down).
var guarding := false
var _prev_guard := false

# Confusing Beam (World::state_change, state_action_type 5): MoveState, TurnState and
# ConfusionState, all for confusion_time. A newer hit restarts the time.
var confusion_time := 0.0
var move_mul := 1.0 ## velocity x this (MoveState)
var turn_mul := 1.0 ## rotation_speed x this (TurnState)
var damage_mul := 1.0 ## this mech's outgoing damage x this (mul_to_damage)
var fire_delay := 0.0 ## added before each queued bullet (add_to_fire_time)

## PulseState (Void Pulse, pulse_time): bullets, swords and splash pass through for this long.
var pulse_time := 0.0
## AddDamageState (Impact Pulse-Gun): each stack adds 0.1 to the damage this mech takes
## (adddamage_ratio, at most 2.5) and lasts its own 10 s.
const DAMAGE_STACK_TIME := 10.0
const DAMAGE_STACK_CAP := 2.5
var damage_stacks: Array[float] = []

# The step 17 states (World::state_change, picked by weapon id; rcPlayerState.cpp). The
# client hard-codes their times; the database's state_limit_time is never read.
## Freezing Beam Gun: FreezeState (every input dropped, one stop sent), CantAttackState and
## NoDamageState (no damage and no new states), all 10 s. An ice block, not a slow.
const FREEZE_TIME := 10.0
var freeze_time := 0.0
## R.Control Beam: ReverseControlState, the movement keys swapped, 10 s.
const REVERSE_TIME := 10.0
var reverse_time := 0.0
## Blind Beam: BlindBeamState, 10 s; the HUD covers the screen and hides the radar's blips.
const BLIND_TIME := 10.0
var blind_time := 0.0
## D Fielder: DefenseFieldGeneratorState, damage taken x 0.7 (defensefield_ratio), 10 s.
const FIELD_TIME := 10.0
const FIELD_RATIO := 0.7
var field_time := 0.0
## Power Up Pulse: PowerDownPulseState, 10 s: booster recovery x booster_recovery (1.5),
## booster use, weapon energy and energy drained by others x booster_reduce (0.7).
const POWER_TIME := 10.0
var power_time := 0.0
var power_recovery := 1.0
var power_reduce := 1.0
## Plasma Wire: GravityState, 15 s: the third weapon is barred (cant_attack3). The tether's
## pull is the game's to set each tick: pull_velocity, added to the move.
const GRAVITY_TIME := 15.0
var gravity_time := 0.0
var pull_velocity := Vector2.ZERO
## Over Booster: OverBoosterState, 10 s from the attack: a boost runs at vel_limit at once,
## with no ramp (rcPlayer.cpp; overbooster_ratio is commented out).
const OVER_BOOST_TIME := 10.0
var over_boost_time := 0.0

## body_name: RobotInfo name. weapon_slot: the slot selected at the start. weapons: the four
## equipped weapon ids in slot order (sword, gun, heavy, special), or empty for the body's
## defaults.
func _init(body_name := "zeid", weapon_slot := Original.START_WEAPON, weapons: Array = []) -> void:
	body = body_name
	stats = GameData.robot(body)
	for id in Bodies.loadout(body, weapons):
		slots.append(Slot.new(GameData.weapon(id), body))
	_register_combo_commands()
	weapon_index = weapon_slot
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
	var shield_id := Bodies.shield_id(body)
	if shield_id > 0:
		shield = GameData.weapon(shield_id)
		shield_max = shield.durability * 10.0
		shield_recover = shield.mode_num("shield_recover_amount")
	durability = shield_max

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
	# ReverseControlState: left and right, up and down swap (rcManager.cpp updatemove); aim
	# and fire are untouched.
	if reverse_time > 0.0:
		var swapped := Intent.new()
		swapped.left = intent.right
		swapped.right = intent.left
		swapped.up = intent.down
		swapped.down = intent.up
		swapped.boost = intent.boost
		swapped.fire = intent.fire
		swapped.weapon_key = intent.weapon_key
		swapped.guard = intent.guard
		swapped.aim = intent.aim
		intent = swapped
	# StunState and FreezeState: every input is dropped, turning and firing included.
	if stun_time > 0.0 or freeze_time > 0.0:
		stun_time = maxf(0.0, stun_time - dt)
		var held := Intent.new()
		held.aim = pos + Original.vec2_from_deg(facing) * 100.0
		intent = held
	_update_states(dt)
	_update_booster_gauge(intent, dt)
	_update_move(intent)
	_update_rotation(intent, dt)
	_update_physics(dt)
	_update_dash(intent)
	_update_map()
	_update_guard(intent, dt)
	# rcPlayerManager::update reads the combo keys before update_my_input handles the click,
	# so the click that completes a combo also swings with it.
	_update_combo_input(intent, dt)
	_update_weapons(intent, dt)
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
		combo_active = false
		_last_vel = 0.0
		if guarding:
			guard_cancel()
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
		booster_gage -= energy_reduce * power_reduce * dt
		if booster_gage <= 0.0:
			booster_gage = 0.0
			booster_warning_time = 1.5
			if vel_scalar >= booster_speed and intent.any_move():
				_send_move(_deg(intent), 1)
	else:
		var rate := regenerate if booster_gage > energy_low_line else regenerate * 0.5
		rate *= power_recovery
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
	var turn := minf(absf(diff), rotation_speed * turn_mul * dt)
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
	if over_boost_time > 0.0 and acc_flag:
		player_vel = vel_limit
	player_vel = minf(player_vel, vel_limit) * move_mul
	_last_vel = player_vel
	pos += move_dir * player_vel * dt + pull_velocity * dt
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

## rcPlayerManager::updateguard: Space toggles the guard. Raising it ends a continuous
## weapon's stream first and needs durability left. rc_Weapon::update for the shield: while
## the guard is down and the shield is not broken, durability recovers shield_recover_amount
## a second. A broken shield stays broken (every shield's mode has shield_regeneration 0).
func _update_guard(intent: Intent, dt: float) -> void:
	var press := intent.guard and not _prev_guard
	_prev_guard = intent.guard
	if shield == null:
		return
	if not guarding and durability > 0.0:
		durability = minf(shield_max, durability + shield_recover * dt)
	if not press:
		return
	if guarding:
		guard_cancel()
		return
	if streaming:
		streaming = false
		attacking = false
	if durability > 0.0:
		guard_start()

## rcPlayer::guard: also ends a charge weapon's draw (end_weapon_charge).
func guard_start() -> void:
	guarding = true
	if charging:
		charging = false
		charge_level = -1
		charge_changed.emit(-1)
	guard_changed.emit(true)

func guard_cancel() -> void:
	guarding = false
	guard_changed.emit(false)

## World::receive_guard: a blocked hit wears the shield by its damage; at 0 it breaks and the
## guard drops. Returns true if this block broke it.
func block(amount: int) -> bool:
	durability -= amount
	if durability > 0.0:
		return false
	durability = 0.0
	if guarding:
		guard_cancel()
	return true

## World::process_crash: a guarded mech stops what comes at it from the front, where the
## direction from the mech to the bullet's last position is within the 0.2 dot of its facing.
func guards_against(from: Vector2) -> bool:
	if not guarding:
		return false
	var to := from - pos
	if to.length_squared() < 0.0001:
		return false
	return Original.vec2_from_deg(facing).dot(to.normalized()) > Original.GUARD_DOT

## World::state_change for the Confusing Beam: down_move_speed, down_rotation_speed,
## down_damage and down_continuous_time for confusion_time. Every machine applies it, so the
## one deciding a hit knows the shooter's damage is cut.
func confuse(w: GameData.Weapon) -> void:
	confusion_time = w.mode_num("confusion_time")
	move_mul = w.mode_num("down_move_speed", 1.0)
	turn_mul = w.mode_num("down_rotation_speed", 1.0)
	damage_mul = w.mode_num("down_damage", 1.0)
	fire_delay = w.mode_num("down_continuous_time")

func is_confused() -> bool:
	return confusion_time > 0.0

## adddamage_ratio, then defensefield_ratio: damage taken is multiplied by this.
func damage_taken_mul() -> float:
	return (1.0 + 0.1 * damage_stacks.size()) * (FIELD_RATIO if field_time > 0.0 else 1.0)

## NoDamageState: no damage lands and no new state starts.
func is_nodamage() -> bool:
	return freeze_time > 0.0

## Starts a step 17 state on this mech (every machine runs them). w: the weapon that caused
## it, for its parameters. A frozen mech takes no new state.
func start_state(w: GameData.Weapon) -> void:
	if is_nodamage():
		return
	match w.id:
		51:
			freeze_time = FREEZE_TIME
			_send_move(0, 0)
			_burst_left = 0
			streaming = false
		50:
			reverse_time = REVERSE_TIME
		55:
			blind_time = BLIND_TIME
		48:
			field_time = FIELD_TIME
		47:
			power_time = POWER_TIME
			power_recovery = w.param_num("booster_recovery", 1.0)
			power_reduce = w.param_num("booster_reduce", 1.0)
		57:
			gravity_time = GRAVITY_TIME
			# A mech holding its third weapon is put on the second.
			if weapon_index == 2:
				weapon_index = 1
				weapon_changed.emit(1)

## RG_TELEPORT_ACK (Teleport Beam): straight to the point, stopped, the boost dropped.
func teleport_to(at: Vector2) -> void:
	_send_move(0, 0)
	add_vel = 0.0
	dashing = false
	_settling = false
	pos = at
	real_pos = at
	previous_pos = at

func is_frozen() -> bool:
	return freeze_time > 0.0

## AddDamageState::init: a new stack only below the cap. True if it was added.
func add_damage_stack() -> bool:
	if damage_taken_mul() >= DAMAGE_STACK_CAP - 0.001:
		return false
	damage_stacks.append(DAMAGE_STACK_TIME)
	return true

func is_pulse() -> bool:
	return pulse_time > 0.0

func _update_states(dt: float) -> void:
	pulse_time = maxf(0.0, pulse_time - dt)
	freeze_time = maxf(0.0, freeze_time - dt)
	over_boost_time = maxf(0.0, over_boost_time - dt)
	reverse_time = maxf(0.0, reverse_time - dt)
	blind_time = maxf(0.0, blind_time - dt)
	field_time = maxf(0.0, field_time - dt)
	gravity_time = maxf(0.0, gravity_time - dt)
	if power_time > 0.0:
		power_time -= dt
		if power_time <= 0.0:
			power_time = 0.0
			power_recovery = 1.0
			power_reduce = 1.0
	for i in range(damage_stacks.size() - 1, -1, -1):
		damage_stacks[i] -= dt
		if damage_stacks[i] <= 0.0:
			damage_stacks.remove_at(i)
	if confusion_time > 0.0:
		confusion_time -= dt
		if confusion_time <= 0.0:
			_clear_confusion()

func _clear_confusion() -> void:
	confusion_time = 0.0
	move_mul = 1.0
	turn_mul = 1.0
	damage_mul = 1.0
	fire_delay = 0.0

## rcPlayer init and register_combo_command: the commands of the body's sword
## (combo_id_to_apply), in table order. They are read whatever weapon is selected.
func _register_combo_commands() -> void:
	combo_commands.clear()
	for sl in slots:
		if int(sl.data.param_num("number_of_combo_id")) <= 0:
			continue
		combo_commands.clear()
		for id in sl.data.param.get("combo_id_to_apply", []):
			var cp := Bodies.combo_param(int(id))
			if cp.is_empty():
				continue
			var c := ComboCommand.new()
			c.id = int(id)
			for k in cp.get("key", []):
				c.keys.append(ComboKey.get(str(k).trim_prefix("COMBO_KEY_"), 0))
				c.times.append(0.0)
			combo_commands.append(c)

## ComboInputManager::update: key presses this frame, turned to the facing
## (update_key_info), fed to every command in order. When two finish on the same click
## the later one in the table wins, as the loop did not stop.
func _update_combo_input(intent: Intent, dt: float) -> void:
	var now := [intent.left, intent.right, intent.up, intent.down, intent.fire, intent.boost]
	var down: Array[bool] = []
	for i in 6:
		down.append(now[i] and not _combo_prev[i])
	_combo_prev = now
	if combo_commands.is_empty() or combo_ready != 0:
		return
	var info := combo_key_info(down, facing)
	for c in combo_commands:
		if info[c.keys[c.cur_key]]:
			c.cur_key += 1
			if c.cur_key >= c.keys.size():
				combo_ready = c.id
				c.cur_key = c.keys.size() - 1
		else:
			c.times[c.cur_key] += dt
			if c.times[c.cur_key] > COMBO_KEY_LIMIT:
				c.cancel()

## update_key_info: key-down edges [left, right, up, down, left click, right click] as
## COMBO_KEY flags, with the arrows turned so RIGHT is toward the facing and LEFT away.
static func combo_key_info(down: Array, deg: int) -> Array[bool]:
	var info: Array[bool] = [down[0], down[1], down[2], down[3], down[4], down[5], down[4] and down[5]]
	deg = (deg % 360 + 360) % 360
	if deg >= 45 and deg < 135:
		info[ComboKey.RIGHT] = info[ComboKey.UP]
		info[ComboKey.LEFT] = info[ComboKey.DOWN]
	elif deg >= 135 and deg < 225:
		var t := info[ComboKey.LEFT]
		info[ComboKey.LEFT] = info[ComboKey.RIGHT]
		info[ComboKey.RIGHT] = t
	elif deg >= 225 and deg < 315:
		info[ComboKey.LEFT] = info[ComboKey.UP]
		info[ComboKey.RIGHT] = info[ComboKey.DOWN]
	info[ComboKey.UP] = false
	info[ComboKey.DOWN] = false
	return info

## get_combo_id, checked against the weapon's own combos, then start_getting_combo_input:
## the completed combo, or 0, and every sequence starts over.
func take_combo(w: GameData.Weapon) -> int:
	var id := combo_ready
	combo_ready = 0
	for c in combo_commands:
		c.cancel()
	if id == 0:
		return 0
	for allowed in w.param.get("combo_id_to_apply", []):
		if int(allowed) == id:
			return id
	return 0

## rcPlayerManager::update_my_input, number keys: change weapon on the key press, unless the
## fire button is held, an attack is still going out, or a combo or charge is under way.
func _update_weapon_switch(intent: Intent) -> void:
	var key := intent.weapon_key
	var pressed := key != 0 and key != _prev_weapon_key
	_prev_weapon_key = key
	if not pressed or intent.fire or _burst_left > 0 or combo_active or streaming or charging:
		return
	var slot := key - 1
	if slot < 0 or slot >= slots.size():
		return
	if slot == 2 and gravity_time > 0.0:
		return
	# A weapon key while guarding drops the guard first (WEAPON_GUARD_CANCEL).
	if guarding:
		guard_cancel()
	if slot != weapon_index:
		weapon_index = slot
		weapon_changed.emit(slot)

## Weapons, following rc_Weapon::update_bullet, rcWeaponMode::fire and ComboSystem::update.
## An attack starts on the button press, not while it is held; continuous weapons then keep
## firing while it stays down, and charge weapons fire when it is let go. Every weapon
## recharges, selected or not, except while the mech is attacking.
func _update_weapons(intent: Intent, dt: float) -> void:
	var press := intent.fire and not _prev_fire
	var release := _prev_fire and not intent.fire
	_prev_fire = intent.fire
	_update_weapon_switch(intent)
	var slot := slots[weapon_index]
	# Bullets queued by the last shot leave continuous_time apart.
	if _burst_left > 0:
		_burst_timer -= dt
		while _burst_left > 0 and _burst_timer <= 0.0:
			if not _fire_one(slot):
				_burst_left = 0
				break
			_burst_left -= 1
			if _burst_left > 0:
				_burst_timer += slot.data.fire_interval + fire_delay
	# is_continuous: one round each continuous_time while the button is held, until it is
	# let go or the ammo runs out (pt_send_continuous_shot_end).
	if streaming:
		_burst_timer -= dt
		while streaming and _burst_timer <= 0.0:
			if not _fire_one(slot):
				streaming = false
				break
			_burst_timer += maxf(slot.data.fire_interval, 0.01) + fire_delay
		if not intent.fire:
			streaming = false
		if not streaming:
			attacking = false
	if charging:
		_charge_time += dt
		# charge_energy_reduce: the booster drains while the charge is below its top.
		if charge_level < int(slot.data.param_num("charge_num")):
			booster_gage = maxf(0.0, booster_gage - slot.data.param_num("charge_energy_reduce") * power_reduce * dt)
		var level := mini(int(slot.data.param_num("charge_num")), int(_charge_time / maxf(slot.data.param_num("charge_gap", 1.5), 0.01)))
		if level != charge_level:
			charge_level = level
			charge_changed.emit(level)
		if release:
			# The arrow leaves on release, its strength set by the charge reached.
			charging = false
			_start_burst(slot)
			charge_changed.emit(-1)
		return
	if combo_active:
		_swing_time -= dt
		if _swing_time <= 0.0:
			if _combo_queued:
				_combo_queued = false
				combo_index += 1
				swing_combo = _queued_combo if _queued_combo > 1 else 0
				# A finisher from the queue ends the chain (the first swing's does not).
				_combo_finished = int(Bodies.combo_param(swing_combo).get("finish", 0)) == 1
				_swing(slot)
			else:
				combo_active = false
				attacking = false
	elif attacking and not streaming:
		_attack_time -= dt
		if _attack_time <= 0.0 and _burst_left == 0:
			attacking = false
	if not attacking:
		for sl in slots:
			sl.recharge = minf(sl.recharge + dt, sl.data.reload)
	if not press:
		return
	# No attack while guarding; a click only sounds shieldused when the weapon is ready.
	if guarding:
		if slot.is_ready():
			shield_clicked.emit()
		return
	if slot.data.is_sword():
		# combo_shoot: a click during a swing queues the next one, up to the last swing clip,
		# carrying a completed command combo or 1 for a plain click. Otherwise a ready sword
		# starts with the combo completed, if any (shoot(combo_id + 100)).
		if combo_active:
			if not _combo_queued and not _combo_finished and combo_index != slot.last_swing():
				_combo_queued = true
				var id := take_combo(slot.data)
				_queued_combo = id if id != 0 else 1
				slot.recharge = 0.0
		elif slot.is_ready():
			combo_active = true
			_combo_finished = false
			combo_index = Original.SWORD_FIRST_SWING
			swing_combo = take_combo(slot.data)
			_swing(slot)
		return
	if attacking or not slot.is_ready() or slot.ammo == 0:
		return
	if slot.data.is_charge():
		charging = true
		_charge_time = 0.0
		charge_level = 0
		charge_changed.emit(0)
		return
	if slot.data.is_continuous:
		streaming = true
		attacking = true
		slot.recharge = 0.0
		_burst_timer = slot.data.fire_interval + fire_delay
		attack_started.emit(weapon_index)
		return
	_start_burst(slot)

## rcWeaponMode::fire: queue the weapon's bullets and start the reload.
func _start_burst(slot: Slot) -> void:
	shot_index = 0
	# ammo_of_magazine: within a magazine the next attack is ready 0.1 s on; the last one
	# reloads in full.
	var magazine := int(slot.data.param_num("ammo_of_magazine"))
	if magazine > 0:
		slot.magazine_used += 1
		if slot.magazine_used < magazine:
			slot.recharge = slot.data.reload - 0.1
		else:
			slot.magazine_used = 0
			slot.recharge = 0.0
	else:
		slot.recharge = 0.0
	attacking = true
	_attack_time = slot.attack_time
	# shoot() limits the burst to the ammo left; charge_repeat_shot adds a round per charge
	# level (the CP.Pulse Cannon: 1 + level).
	var count := slot.data.fire_num + maxi(0, charge_level) * int(slot.data.param_num("charge_repeat_shot"))
	_burst_left = count if slot.ammo < 0 else mini(count, slot.ammo)
	_burst_left = maxi(_burst_left, 1)
	# Each queued bullet waits continuous_time; use_bullet_start_time sets the first one's
	# own wait (bullet_start_time, 0 for the MP7-C3, the H.P Beam Rifle and the Viper).
	_burst_timer = slot.data.fire_interval + fire_delay
	if int(slot.data.mode_num("use_bullet_start_time")) == 1:
		_burst_timer = slot.data.mode_num("bullet_start_time") + fire_delay
	attack_started.emit(weapon_index)

## One round: ammo, the gauge, and the event. False when the ammo has run out.
func _fire_one(slot: Slot) -> bool:
	if slot.ammo == 0:
		return false
	if slot.ammo > 0:
		slot.ammo -= 1
	_spend(slot.data.cost_energy)
	fired.emit(pos, facing)
	shot_index += 1
	return true

func _swing(slot: Slot) -> void:
	slot.recharge = 0.0
	attacking = true
	_swing_time = slot.swing_time(combo_index)
	_spend(slot.data.cost_energy)
	swung.emit(weapon_index, combo_index)

## booster_gage -= cost_energy for each bullet or swing, floored at 0.
func _spend(amount: float) -> void:
	booster_gage = maxf(0.0, booster_gage - amount * power_reduce)

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
		speed_state, int(attacking), life, booster_gage, int(is_dead_complete), weapon_index,
		charge_level if charging else -1, int(guarding)]

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
	if s.size() > 12 and int(s[12]) != weapon_index and int(s[12]) < slots.size():
		weapon_index = int(s[12])
		weapon_changed.emit(weapon_index)
	if s.size() > 13 and int(s[13]) != charge_level:
		charge_level = int(s[13])
		charging = charge_level >= 0
		charge_changed.emit(charge_level)
	if s.size() > 14 and (int(s[14]) != 0) != guarding:
		guarding = int(s[14]) != 0
		guard_changed.emit(guarding)
	if not _has_snapshot:
		pos = real_pos
		_has_snapshot = true

## rcPlayer::update for remote players: carry the reported position forward at the reported
## velocity, then ease the drawn position 10% of the way toward it each tick.
func step_remote(dt: float) -> void:
	_update_states(dt)
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
	for sl in slots:
		sl.reset()
	weapon_index = Original.START_WEAPON
	_burst_left = 0
	attacking = false
	combo_active = false
	_combo_queued = false
	_combo_finished = false
	swing_combo = 0
	combo_ready = 0
	for c in combo_commands:
		c.cancel()
	streaming = false
	charging = false
	charge_level = -1
	stun_time = 0.0
	# Each round is a new game in the original, so the shield starts whole again.
	durability = shield_max
	guarding = false
	_prev_guard = false
	_clear_confusion()
	pulse_time = 0.0
	damage_stacks.clear()
	freeze_time = 0.0
	reverse_time = 0.0
	blind_time = 0.0
	field_time = 0.0
	gravity_time = 0.0
	power_time = 0.0
	power_recovery = 1.0
	power_reduce = 1.0
	pull_velocity = Vector2.ZERO
	over_boost_time = 0.0
	_prev_fire = false
	_prev_weapon_key = 0
	_booster_input = BoosterInput.NOTHING
	_prev_keys = [false, false, false, false]
	previous_pos = spawn
	dashing = false
	_settling = false
