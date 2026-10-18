extends SceneTree
## Headless tests for MechSim against the original database values (RobotInfo, WeaponInfo)
## after the original server and client conversions.
##   godot --headless --path godot -s tests/test_mech_sim.gd

const DT := 1.0 / 60.0
var failures := 0
var passed := 0

func _init() -> void:
	test_zeid_stats_from_database()
	test_sr3_stats_from_database()
	test_walk_speed()
	test_stop_is_immediate()
	test_boost_kick_then_ramp_to_cap()
	test_gauge_drain_and_empty()
	test_boost_needs_low_line()
	test_recovery_rates()
	test_boost_key_release()
	test_facing_turns_at_rotation_speed()
	test_rifle_burst_and_recharge()
	test_move_clips()
	test_knockout_sequence()
	test_snapshot_carries_knockout()
	test_reset_revives()
	test_wall_contact_and_segment()
	test_walls_stop_a_walking_mech()
	test_bounds_bounce()
	test_input_frozen_while_dashing()
	test_real_maps_load()
	test_sound_distance_and_pan()
	test_clock_digits()
	test_boost_sound_trigger()
	test_fire_needs_a_click()
	test_bullets_cost_energy()
	test_weapon_switching()
	test_sword_combo()
	test_missile_ammo_and_burst()
	test_body_loadouts()
	test_body_stats()
	test_continuous_fire()
	test_charge_weapon()
	test_magazine()
	test_splash_rules()
	test_beam_rules()
	test_stun()
	test_shields()
	test_guard_toggle()
	test_guard_blocks_and_breaks()
	test_confusion()
	test_emp()
	test_mine_firing()
	test_mine_cycle()
	test_combo_table()
	test_combo_keys_follow_facing()
	test_combo_input()
	test_combo_swings()
	test_room_slots()
	test_room_start_points()
	test_room_end_and_winners()
	test_touch_controls()
	test_equip_rules()
	test_pulse_and_damage_stacks()
	test_original_controls()
	test_front_end()
	test_lan_rooms()
	test_room_pages()
	test_shop_page()
	test_state_rate()
	test_step17_states()
	test_step17_shots()
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)

func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)

func near(a: float, b: float, tol := 0.01) -> bool:
	return absf(a - b) <= tol

func run(sim: MechSim, intent: MechSim.Intent, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		sim.step(intent, DT)

func test_zeid_stats_from_database() -> void:
	print("Zeid stats (RobotInfo id 1)")
	var s := GameData.robot("zeid")
	check(s.move_speed == 108.0, "walk: normal_speed 330 -> BYTE 33 x 0.33 x 10 = 108 (int)")
	check(s.booster_speed == 188.0 and s.booster_init_speed == 258.0, "boost: 570 -> 57 x 0.33 x 10 = 188, start kick 258")
	check(s.energy_max == 1900.0, "gauge: energy 1900")
	check(s.energy_reduce == 140.0 and s.regenerate == 110.0 and s.energy_low_line == 330.0, "drain 140, recovery 110, low line 330")
	check(s.rotation_speed == 320.0, "turn rate 320 deg/s")
	check(near(s.boost_accel, 2.475, 0.001), "boost acceleration: 150 -> 15 x 0.33 x 0.5 = 2.475")
	check(near(s.vel_limit, 363.0, 0.01), "boost cap: 1150 -> 11 x 0.33 x 100 = 363")
	check(s.life == 700, "armour points 700")
	check(near(s.crash_radius, 13.5), "collision radius 45 x 0.3 = 13.5")
	check(s.weapons[1] == 3, "second default weapon is id 3, the SR-3")

func test_sr3_stats_from_database() -> void:
	print("SR-3 stats (WeaponInfo id 3)")
	var w := GameData.weapon(3)
	check(w.name == "SR-3" and w.damage == 12 and w.fire_num == 3, "SR-3: 12 damage, 3 shots")
	check(near(w.fire_interval, 0.1), "shots 0.1 s apart (continuous_time 100)")
	check(near(w.bullet_speed, 528.0), "bullet speed 1600 -> 16 x 0.33 x 100 = 528")
	check(near(w.life, 0.7) and near(w.reload, 1.2), "bullet life 0.7 s, reload 1.2 s")
	check(near(w.crash_radius, 3.3), "bullet radius 10 x 0.33 = 3.3")

func test_walk_speed() -> void:
	print("walk")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.right = true
	it.aim = Vector2(1000, 0)
	run(sim, it, 1.0)
	check(absf(sim.pos.x - 108.0) < 2.5, "walks about 108 units in a second (got %.1f)" % sim.pos.x)

func test_stop_is_immediate() -> void:
	print("stop")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.right = true
	run(sim, it, 0.5)
	it.right = false
	var x := sim.pos.x
	run(sim, it, 0.5)
	check(sim.speed() == 0.0 and absf(sim.pos.x - x) < 0.01, "releasing keys stops dead, like recv_stop")

func test_boost_kick_then_ramp_to_cap() -> void:
	print("boost")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.right = true
	it.aim = Vector2(1000, 0)
	run(sim, it, 0.1)
	it.boost = true
	run(sim, it, 0.05)
	check(sim.acc_flag and near(sim.speed(), 258.0, 1.0), "boost starts at the 258 kick (got %.1f)" % sim.speed())
	run(sim, it, 0.5)
	var early := sim.speed()
	run(sim, it, 3.0)
	var top := sim.speed()
	check(early < top, "keeps accelerating while held (%.1f then %.1f)" % [early, top])
	check(near(top, 363.0, 0.5), "levels off at the 363 cap (got %.1f)" % top)
	var peak := 0.0
	for i in 120:
		sim.step(it, DT)
		peak = maxf(peak, sim.speed())
	check(peak <= 363.0 + 0.001, "never exceeds the cap")

func test_gauge_drain_and_empty() -> void:
	print("gauge")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.right = true
	run(sim, it, 0.1)
	it.boost = true
	var g := sim.booster_gage
	run(sim, it, 1.0)
	check(absf((g - sim.booster_gage) - 140.0) < 4.0, "drains 140 per second (drained %.1f)" % (g - sim.booster_gage))
	run(sim, it, 13.0)
	check(sim.booster_gage == 0.0, "1900 empties in about 13.6 s")
	check(not sim.acc_flag and near(sim.speed(), 108.0, 0.5), "then drops back to walking speed")

func test_boost_needs_low_line() -> void:
	print("low line")
	var sim := MechSim.new()
	sim.booster_gage = 320.0
	var it := MechSim.Intent.new()
	it.right = true
	run(sim, it, 0.1)
	it.boost = true
	run(sim, it, 0.1)
	check(not sim.acc_flag, "no boost at or below the 330 low line")
	check(sim.booster_warning_time > 0.0, "shows the booster warning")

func test_recovery_rates() -> void:
	print("recovery")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	sim.booster_gage = 500.0
	run(sim, it, 1.0)
	check(absf(sim.booster_gage - 610.0) < 3.0, "recovers 110 per second above the low line (got %.1f)" % sim.booster_gage)
	sim.booster_gage = 100.0
	run(sim, it, 1.0)
	check(absf(sim.booster_gage - 155.0) < 3.0, "recovers at half rate below it (got %.1f)" % sim.booster_gage)

func test_boost_key_release() -> void:
	print("boost and keys")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.right = true
	run(sim, it, 0.1)
	it.boost = true
	run(sim, it, 0.3)
	it.right = false
	run(sim, it, 0.3)
	check(sim.speed() == 0.0, "letting go of the last key mid-boost stops, via the key-up branch")
	it.right = true
	run(sim, it, 0.2)
	check(sim.acc_flag and sim.speed() > 180.0, "pressing a key again while holding boost resumes boosting")
	it.boost = false
	run(sim, it, 0.1)
	check(not sim.acc_flag and near(sim.speed(), 108.0, 0.5), "releasing the boost with a key held drops to walking")

func test_facing_turns_at_rotation_speed() -> void:
	print("facing")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.aim = Vector2(-1000, 0)
	run(sim, it, 0.3)
	var turned := absf(wrapf(float(sim.facing), -180.0, 180.0))
	check(turned > 86.0 and turned < 106.0, "turns about 320 deg/s toward the mouse (%.0f deg in 0.3 s)" % turned)
	run(sim, it, 1.0)
	check(absf(wrapf(float(sim.facing - 180), -180.0, 180.0)) < 12.0, "settles facing the mouse")

func test_rifle_burst_and_recharge() -> void:
	print("SR-3")
	var sim := MechSim.new()
	var shots: Array[float] = []
	var clock := [0.0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: shots.append(clock[0]))
	var it := MechSim.Intent.new()
	# Clicking every other frame: each press may start a burst.
	for i in 240:
		it.fire = i % 2 == 0
		sim.step(it, DT)
		clock[0] += DT
	check(shots.size() >= 6, "fires repeated bursts (%d shots in 4 s)" % shots.size())
	check(near(shots[0], 0.1, 0.02), "first shot after one 0.1 s interval, as queued (%.2f s)" % shots[0])
	check(near(shots[1] - shots[0], 0.1, 0.02) and near(shots[2] - shots[1], 0.1, 0.02), "burst shots are 0.1 s apart")
	# The fire clip (0.17 s, the attack file's first clip, which is the original's clip 2) ends
	# inside the 0.3 s burst, so the reload runs from the burst's end.
	check(near(shots[3] - shots[0], 1.5, 0.05), "next burst after the burst plus the 1.2 s reload (%.2f s)" % (shots[3] - shots[0]))

func test_move_clips() -> void:
	print("animation choice")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.right = true
	it.aim = Vector2(1000, 0)
	run(sim, it, 0.2)
	check(sim.move_clip() == Original.MOVE_FORWARD, "moving toward the facing direction plays the forward clip")
	it.aim = Vector2(-1000, 0)
	run(sim, it, 1.0)
	check(sim.move_clip() == Original.MOVE_BACK, "moving away from it plays the back clip")

func test_knockout_sequence() -> void:
	print("knockout (rcPlayer::update_dead)")
	var sim := MechSim.new()
	var exploded := [false]
	sim.exploded.connect(func() -> void: exploded[0] = true)
	var it := MechSim.Intent.new()
	it.right = true
	it.fire = true
	run(sim, it, 0.3)
	check(not sim.take_damage(sim.life - 12), "a hit that leaves life above 0 is not a knockout")
	check(sim.take_damage(12), "the hit that takes life to 0 is the knockout")
	sim.step(it, DT)
	check(sim.is_dead and not sim.is_dead_complete, "dead at once, not yet destroyed")
	check(sim.speed() == 0.0 and not sim.attacking, "stops moving and firing")
	var x := sim.pos.x
	run(sim, it, 0.1)
	check(sim.is_dead_complete and exploded[0], "destroyed 0.1 s later (time_to_dead_complete)")
	check(near(sim.pos.x, x), "ignores input while dead")
	check(not sim.take_damage(50), "further hits do nothing")

func test_snapshot_carries_knockout() -> void:
	print("network knockout state")
	var owner := MechSim.new()
	owner.take_damage(owner.life)
	run(owner, MechSim.Intent.new(), 0.2)
	var remote := MechSim.new()
	remote.apply_snapshot(owner.snapshot())
	check(remote.is_dead and remote.is_dead_complete and remote.life == 0, "a remote copy sees the knockout and the destruction")

func test_reset_revives() -> void:
	print("next round")
	var sim := MechSim.new()
	sim.take_damage(sim.life)
	run(sim, MechSim.Intent.new(), 0.2)
	sim.reset_at(Vector2(-150, 0), 0)
	check(not sim.is_dead and not sim.is_dead_complete and sim.life == 700, "reset brings it back at full armour")
	check(sim.booster_gage == 1900.0 and sim.pos == Vector2(-150, 0), "full gauge, at the spawn point")

# --- Map collision -------------------------------------------------------------------------

## A wall across the plane at x = wall_x, facing -x, from plane y -500 to 500.
func wall_map(wall_x: float) -> BattleMap:
	var m := BattleMap.new()
	m.x_min = -1000.0
	m.x_max = 1000.0
	m.y_min = -1000.0
	m.y_max = 1000.0
	m.collision.add_triangle(PackedVector3Array([Vector3(wall_x, -100, -500), Vector3(wall_x, 100, -500), Vector3(wall_x, 0, 500)]))
	m.collision.add_triangle(PackedVector3Array([Vector3(wall_x, -100, 500), Vector3(wall_x, 100, 500), Vector3(wall_x, 0, -500)]))
	return m

func test_wall_contact_and_segment() -> void:
	print("map collision (rc_map sphere and ray tests)")
	var m := wall_map(100.0)
	var c := m.collision.sphere_contact(Vector2(90, 0), 13.5)
	check(not c.is_empty() and near(c["normal"].x, -1.0) and near(c["point"].x, 100.0), "a mech 10 from the wall touches it, pushed back toward -x")
	check(m.collision.sphere_contact(Vector2(80, 0), 13.5).is_empty(), "20 away is clear")
	var hit: Variant = m.collision.segment_hit(Vector2(50, 10), Vector2(150, 10))
	check(hit != null and near(hit.x, 100.0, 0.1), "a bullet path through the wall stops at it")
	check(m.collision.segment_hit(Vector2(10, 0), Vector2(90, 0)) == null, "a path short of the wall is clear")

func test_walls_stop_a_walking_mech() -> void:
	print("walking and boosting into a wall")
	var sim := MechSim.new()
	sim.map = wall_map(100.0)
	var it := MechSim.Intent.new()
	it.right = true
	it.aim = Vector2(1000, 0)
	var furthest := 0.0
	for i in 300:
		it.boost = i > 30
		sim.step(it, DT)
		furthest = maxf(furthest, sim.pos.x)
	check(furthest < 100.0, "never passes the wall (furthest x %.1f)" % furthest)
	check(sim.pos.x > 60.0, "stays pressed up against it (x %.1f)" % sim.pos.x)

func test_bounds_bounce() -> void:
	print("arena edge (process_map_bound, crashed_with_wall)")
	var sim := MechSim.new()
	var m := BattleMap.new()
	m.x_min = -200.0
	m.x_max = 200.0
	m.y_min = -200.0
	m.y_max = 200.0
	sim.map = m
	var crashes: Array[Vector2] = []
	sim.wall_crashed.connect(func(at: Vector2, _n: Vector2) -> void: crashes.append(at))
	sim.reset_at(Vector2(150, 0), 0)
	var it := MechSim.Intent.new()
	it.right = true
	it.aim = Vector2(1000, 0)
	var furthest := 0.0
	for i in 60:
		sim.step(it, DT)
		furthest = maxf(furthest, sim.pos.x)
	check(furthest <= 200.0, "held on the edge (furthest x %.1f)" % furthest)
	check(crashes.size() >= 1 and near(crashes[0].x, 200.0), "wall_crash at the edge point")
	it.right = false
	sim.reset_at(Vector2(199.5, 0), 0)
	it.right = true
	sim.step(it, DT)
	it.right = false
	for i in 120:
		sim.step(it, DT)
	check(near(sim.pos.x, 200.0 - Original.WALL_BOUNCE_DISTANCE, 1.0), "bounces 66.3 back inside and settles there (x %.1f)" % sim.pos.x)

func test_input_frozen_while_dashing() -> void:
	print("dash")
	var sim := MechSim.new()
	sim.start_dash(Vector2(100, 0))
	var it := MechSim.Intent.new()
	it.up = true
	sim.step(it, DT)
	check(sim.dashing and sim.move_dir == Vector2.ZERO, "keys do nothing while dashing")
	check(near(sim.pos.x, 10.0, 0.01), "eases 10 percent of the way per frame")
	for i in 10:
		sim.step(it, DT)
	check(not sim.dashing and sim.move_dir.y > 0.9, "within 40 the dash ends and a held key walks again")

func test_real_maps_load() -> void:
	print("converted arenas")
	var maps := BattleMap.list()
	check(maps.size() == 5, "five room maps (%d)" % maps.size())
	for entry in maps:
		var m := BattleMap.load_map(entry["id"])
		var inside := true
		for sp in m.spawns:
			inside = inside and m.in_bounds(sp) and m.collision.sphere_contact(sp, 13.5).is_empty()
		check(m.spawns.size() == 12 and inside, "%s: 12 start points, all inside the bounds and clear of walls" % m.title)

# --- Sound and HUD --------------------------------------------------------------------------

func test_sound_distance_and_pan() -> void:
	print("sound (NubAudiere::get_volume, get_pan)")
	check(near(GameSound.volume_at(Vector2.ZERO, Vector2.ZERO), 0.625, 0.001), "right under the camera: 1 - 300 / 800 = 0.625")
	check(near(GameSound.volume_at(Vector2.ZERO, Vector2(400, 0)), 0.375, 0.001), "400 away: 1 - 500 / 800 = 0.375")
	check(GameSound.volume_at(Vector2.ZERO, Vector2(800, 0)) == 0.0, "silent by about 740 away")
	check(GameSound.pan_at(Vector2.ZERO, Vector2(40, 0)) == 0.0, "no pan within 50 units sideways")
	check(near(GameSound.pan_at(Vector2.ZERO, Vector2(100, 0)), 0.5) and GameSound.pan_at(Vector2.ZERO, Vector2(-500, 0)) == -1.0, "x 0.005 per unit, clamped")

func test_clock_digits() -> void:
	print("clock (OnTimeUpdate)")
	check(Hud.time_digits(83.5) == [0, 1, 2, 3, 1, 0], "83.5 s reads 01:23 then 1, 0 (835 mod 6)")
	check(Hud.time_digits(1.68) == [0, 0, 0, 1, 4, 8], "the tens-of-hundredths digit wraps at 6, as in the script (1.68 s shows 01:48)")

func test_boost_sound_trigger() -> void:
	print("boost sound (on_booster)")
	var sim := MechSim.new()
	var count := [0]
	sim.boost_started.connect(func() -> void: count[0] += 1)
	var it := MechSim.Intent.new()
	it.right = true
	run(sim, it, 0.1)
	it.boost = true
	run(sim, it, 0.5)
	check(count[0] == 1, "the owner hears it once when a boost starts (%d)" % count[0])
	var remote := MechSim.new()
	var heard := [0]
	remote.boost_started.connect(func() -> void: heard[0] += 1)
	remote.apply_snapshot(sim.snapshot())
	remote.apply_snapshot(sim.snapshot())
	var turned := sim.snapshot()
	turned[3] = 0.0
	turned[4] = 1.0
	remote.apply_snapshot(turned)
	check(heard[0] == 1, "another player hears it for each new boosting move, not every packet (%d)" % heard[0])

# --- Weapons (step 6) -----------------------------------------------------------------------

func test_fire_needs_a_click() -> void:
	print("fire button (update_my_input)")
	var sim := MechSim.new()
	var shots := [0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: shots[0] += 1)
	var it := MechSim.Intent.new()
	it.fire = true
	run(sim, it, 4.0)
	check(shots[0] == 3, "holding the button fires one burst only (%d shots)" % shots[0])

func test_bullets_cost_energy() -> void:
	print("energy per bullet (cost_energy)")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.fire = true
	sim.step(it, DT)
	it.fire = false
	sim.booster_gage = 1000.0
	run(sim, it, 0.35)
	check(near(sim.booster_gage, 1000.0 - 60.0 + 110.0 * 0.35, 1.5), "an SR-3 burst spends 3 x 20 of the gauge (left %.1f)" % sim.booster_gage)

func test_weapon_switching() -> void:
	print("weapon keys")
	var sim := MechSim.new()
	check(sim.weapon_index == 1 and sim.weapon.name == "SR-3", "starts on slot 2, the SR-3")
	check(sim.slots[0].data.name == "EB Type 3" and sim.slots[2].data.name == "MML Type 1", "slots 1 and 3 hold the EB Type 3 and the MML")
	var changed := [-1]
	sim.weapon_changed.connect(func(slot: int) -> void: changed[0] = slot)
	var it := MechSim.Intent.new()
	it.weapon_key = 1
	sim.step(it, DT)
	check(sim.weapon_index == 0 and changed[0] == 0, "key 1 takes the sword")
	it.weapon_key = 0
	sim.step(it, DT)
	it.weapon_key = 4
	sim.step(it, DT)
	check(sim.weapon_index == 3 and sim.weapon.name == "EMP Shock Gun", "key 4 takes the EMP Shock Gun (the shield is not a slot)")
	it.weapon_key = 0
	sim.step(it, DT)
	it.weapon_key = 3
	it.fire = true
	sim.step(it, DT)
	check(sim.weapon_index == 3, "no change while the fire button is held")
	it.fire = false
	it.weapon_key = 0
	run(sim, it, 1.0)
	it.weapon_key = 3
	sim.step(it, DT)
	check(sim.weapon_index == 2, "key 3 takes the MML")

func test_sword_combo() -> void:
	print("dagger combo (ComboSystem)")
	var sim := MechSim.new("zeid", Original.START_WEAPON, [28, 3, 4, 17])
	var swings: Array[int] = []
	sim.swung.connect(func(_slot: int, swing: int) -> void: swings.append(swing))
	var it := MechSim.Intent.new()
	it.weapon_key = 1
	sim.step(it, DT)
	it.weapon_key = 0
	# Click five times quickly: the first swing starts, one more is queued at a time.
	for i in 120:
		it.fire = i % 6 == 0 and i < 60
		sim.step(it, DT)
	check(swings == [2, 3, 4], "clicks chain three swings, clips 2, 3, 4 (%s)" % [swings])
	check(not sim.combo_active and not sim.attacking, "the combo ends after the third swing")
	check(sim.recharge < 0.7, "the 0.7 s cooldown runs after the combo (%.2f)" % sim.recharge)
	var single := MechSim.new()
	var one: Array[int] = []
	single.swung.connect(func(_slot: int, swing: int) -> void: one.append(swing))
	it = MechSim.Intent.new()
	it.weapon_key = 1
	single.step(it, DT)
	it.weapon_key = 0
	single.booster_gage = 1000.0
	it.fire = true
	single.step(it, DT)
	check(near(single.booster_gage, 1000.0 - 18.0 + 110.0 * DT, 0.1), "a swing spends 18 of the gauge (left %.1f)" % single.booster_gage)
	it.fire = false
	run(single, it, 1.0)
	check(one == [2], "one click, one swing")

func test_missile_ammo_and_burst() -> void:
	print("MML Type 1")
	var sim := MechSim.new()
	var w := sim.slots[2].data
	check(w.ammo == 120 and w.fire_num == 3 and near(w.fire_interval, 0.3), "120 missiles, bursts of 3 0.3 s apart")
	check(near(w.bullet_speed, 528.0) and near(w.life, 1.7) and near(w.reload, 3.5), "528 units/s, 1.7 s life, 3.5 s reload")
	check(w.guided_flag == 100 and w.collision_checker == 2, "guided (100), the one hit decides the damage")
	var it := MechSim.Intent.new()
	it.weapon_key = 3
	sim.step(it, DT)
	it.weapon_key = 0
	var times: Array[float] = []
	var clock := [0.0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: times.append(clock[0]))
	it.fire = true
	for i in 90:
		sim.step(it, DT)
		clock[0] += DT
		it.fire = false
	check(times.size() == 3 and near(times[0], 0.3, 0.02) and near(times[2], 0.9, 0.03), "missiles leave at 0.3, 0.6 and 0.9 s (%s)" % [times])
	check(sim.slots[2].ammo == 117, "one ammo per missile (%d left)" % sim.slots[2].ammo)
	sim.slots[2].ammo = 2
	sim.slots[2].recharge = w.reload
	times.clear()
	it.fire = true
	for i in 90:
		sim.step(it, DT)
		it.fire = false
	check(times.size() == 2 and sim.slots[2].ammo == 0, "with 2 left, the burst is cut to 2")

# --- Bodies (step 7) ------------------------------------------------------------------------

func test_body_loadouts() -> void:
	print("default loadouts (NetManager default_item_info, sword, gun, heavy, special)")
	var want := {
		"zeid": [1, 3, 4, 17], "redkite": [5, 6, 7, 18], "gigas": [8, 10, 11, 19],
		"deff": [14, 13, 12, 20], "alicia": [21, 23, 24, 25],
	}
	for b in want:
		var got := Bodies.loadout(b)
		check(got == Array(want[b], TYPE_INT, "", null), "%s: %s" % [b, got])
	check(GameData.weapon(21).name == "Saber Type 1" and GameData.weapon(21).damage == 41, "the Saber's row is read from the backup (41 damage)")

func test_body_stats() -> void:
	print("body stats (RobotInfo)")
	var g := MechSim.new("gigas")
	check(g.life_max == 1000 and g.move_speed == int(27 * 0.33 * 10) and near(g.crash_radius, 18.0), "Gigas: 1000 armour, walks 89, radius 18")
	var a := MechSim.new("alicia")
	check(a.life_max == 750 and near(a.energy_max, 1800.0), "Alicia: 750 armour, gauge BYTE(1850 / 100) x 100 = 1800")
	check(g.weapon.name == "Heavy Machinegun" and a.weapon.name == "Double Hand Gun", "each starts on slot 2")

func test_continuous_fire() -> void:
	print("continuous fire (Heavy Machinegun)")
	var sim := MechSim.new("gigas")
	var w := sim.weapon
	check(w.is_continuous and w.is_immediate() and near(w.line_distance, 198.0) and near(w.fire_interval, 0.08), "hold to fire, an instant 198-unit line, a round every 0.08 s")
	var shots := [0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: shots[0] += 1)
	var it := MechSim.Intent.new()
	it.fire = true
	run(sim, it, 1.0)
	check(shots[0] >= 11 and shots[0] <= 13, "about 12 rounds a second while held (%d)" % shots[0])
	it.fire = false
	run(sim, it, 0.5)
	var after: int = shots[0]
	run(sim, it, 0.5)
	check(shots[0] == after, "stops when let go")
	check(sim.slots[1].ammo == 1500 - after, "one ammo a round (%d left)" % sim.slots[1].ammo)

func test_charge_weapon() -> void:
	print("charge (Plasma Bow)")
	var sim := MechSim.new("alicia")
	var it := MechSim.Intent.new()
	it.weapon_key = 3
	sim.step(it, DT)
	it.weapon_key = 0
	run(sim, it, 1.0)
	check(sim.weapon.is_charge(), "the bow draws on the press")
	var levels: Array[int] = []
	sim.charge_changed.connect(func(l: int) -> void: levels.append(l))
	var shots := [0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: shots[0] += 1)
	it.fire = true
	run(sim, it, 3.2)
	check(shots[0] == 0 and sim.charge_level == 2, "nothing leaves while held; level 2 after 3 s (%d)" % sim.charge_level)
	it.fire = false
	run(sim, it, 0.2)
	check(shots[0] == 1 and levels.has(1) and levels.has(2) and levels[-1] == -1, "the arrow leaves on release (%s)" % [levels])

func test_magazine() -> void:
	print("magazine (Double Hand Gun)")
	var sim := MechSim.new("alicia")
	var shots := [0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: shots[0] += 1)
	var it := MechSim.Intent.new()
	for i in 240:
		it.fire = i % 2 == 0
		sim.step(it, DT)
	# Each attack is two shots; within a magazine of 7 the next is ready 0.1 s after the clip.
	check(shots[0] >= 14, "7 attacks come quickly before the full reload (%d shots in 4 s)" % shots[0])
	check(sim.slots[1].magazine_used < 7, "the count wraps after a full reload")

func test_splash_rules() -> void:
	print("splash (Cluster Cannon)")
	var w := GameData.weapon(11)
	check(near(w.splash_area, 132.0) and w.mode_num("splash_damage") == 52.0, "radius BYTE(450 / 100) x 100 x 0.33 = 132, splash 52")
	check(Combat.splash_falloff(52, 132, 10) == 62, "inside a fifth of the radius: 52 x 1.2")
	check(Combat.splash_falloff(52, 132, 70) == 26, "halfway: 52 less 5 steps of 10%")
	check(Combat.splash_falloff(52, 132, 140) == 0, "outside the radius: nothing")
	check(Combat.splash_direct(52, 60, 132, 5) == 134, "a direct hit close in: (52 + 60) x 1.2")

func test_beam_rules() -> void:
	print("beams")
	check(near(GameData.weapon(7).line_distance, 660.0) and near(GameData.weapon(12).line_distance, 495.0), "Plasma Cannon 660, HV Head Beam 495")
	check(GameData.weapon(7).is_pierce() and GameData.weapon(12).is_pierce() and not GameData.weapon(10).is_pierce(), "the cannon and head beam pierce, the machinegun does not")
	check(Combat.line_hits(Vector2.ZERO, Vector2(100, 0), Vector2(50, 10), 13.5) and not Combat.line_hits(Vector2.ZERO, Vector2(100, 0), Vector2(50, 20), 13.5), "a line hits within the mech's radius")
	var hv := Beam.new()
	hv.setup(Vector2.ZERO, 0, GameData.weapon(12), 1)
	var hits := 0
	for i in 18:
		if hv.register_contact(5, DT):
			hits += 1
	check(hits == 3, "the head beam hits again every 0.1 s of contact (%d in 0.3 s)" % hits)
	var pc := Beam.new()
	pc.setup(Vector2.ZERO, 0, GameData.weapon(7), 1)
	var once := 0
	for i in 18:
		if pc.register_contact(5, DT):
			once += 1
	check(once == 1, "the cannon hits each mech once")
	hv.free()
	pc.free()

func test_stun() -> void:
	print("stun (Plasma Bow)")
	var sim := MechSim.new()
	sim.stun_time = Combat.bow_stun_time(2)
	check(near(sim.stun_time, 2.0), "2 s at full charge")
	var it := MechSim.Intent.new()
	it.right = true
	it.fire = true
	var shots := [0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: shots[0] += 1)
	run(sim, it, 1.0)
	check(sim.pos == Vector2.ZERO and shots[0] == 0, "no moving or firing while stunned")

func test_shields() -> void:
	print("shields (Armor::init, rc_Weapon::init)")
	var want := {"zeid": [2, 350.0], "redkite": [16, 450.0], "gigas": [9, 500.0], "deff": [15, 400.0], "alicia": [22, 300.0]}
	var ok := true
	for body: String in want:
		var sim := MechSim.new(body)
		ok = ok and sim.shield != null and sim.shield.id == want[body][0] and sim.shield_max == want[body][1] and sim.durability == sim.shield_max
		ok = ok and near(sim.shield_recover, 7.0) and not Bodies.loadout(body).has(sim.shield.id)
	check(ok, "each body's shield out of the slots, durability x 10 (350, 450, 500, 400, 300), recovers 7 a second")
	check(Combat.guard_rule(1) == Combat.Guard.BLOCK and Combat.guard_rule(2) == Combat.Guard.BLOCK and Combat.guard_rule(3) == Combat.Guard.THROUGH and Combat.guard_rule(4) == Combat.Guard.SPLASH, "swords and bullets blocked, pierce goes through, splash keeps its splash part")

func test_guard_toggle() -> void:
	print("guard toggle (updateguard)")
	var sim := MechSim.new()
	var changes: Array[bool] = []
	sim.guard_changed.connect(func(on: bool) -> void: changes.append(on))
	var it := MechSim.Intent.new()
	it.guard = true
	run(sim, it, 0.5)
	check(sim.guarding and changes == [true], "Space raises the guard once, holding it does nothing more")
	it.guard = false
	run(sim, it, 0.1)
	check(sim.guarding, "letting go of Space keeps it up")
	var shots := [0]
	var clicks := [0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: shots[0] += 1)
	sim.shield_clicked.connect(func() -> void: clicks[0] += 1)
	it.fire = true
	run(sim, it, 0.5)
	it.fire = false
	sim.step(it, DT)
	check(shots[0] == 0 and clicks[0] == 1, "no firing while guarding; a click sounds shieldused")
	it.right = true
	run(sim, it, 0.5)
	check(sim.pos.x > 50.0, "moves at full speed while guarding (%.0f in 0.5 s)" % sim.pos.x)
	it.right = false
	it.guard = true
	sim.step(it, DT)
	check(not sim.guarding and changes == [true, false], "Space again lowers it")
	it.guard = false
	sim.step(it, DT)
	it.guard = true
	sim.step(it, DT)
	it.guard = false
	it.weapon_key = 1
	sim.step(it, DT)
	check(not sim.guarding and sim.weapon_index == 0, "a weapon key drops the guard and changes weapon")
	it.weapon_key = 0
	it.guard = true
	sim.step(it, DT)
	check(sim.snapshot()[14] == 1, "the guard goes out with the state")
	var remote := MechSim.new()
	remote.apply_snapshot(sim.snapshot())
	check(remote.guarding, "and a remote copy shows it")

func test_guard_blocks_and_breaks() -> void:
	print("guard blocks (World::process_crash, receive_guard)")
	var sim := MechSim.new()
	sim.facing = 0
	var it := MechSim.Intent.new()
	it.aim = Vector2(100, 0)
	check(not sim.guards_against(Vector2(100, 0)), "no block without the guard up")
	it.guard = true
	sim.step(it, DT)
	it.guard = false
	check(sim.guards_against(Vector2(100, 0)) and sim.guards_against(Vector2(100, 400)), "blocks from ahead, up to dot 0.2 (about 78 degrees)")
	check(not sim.guards_against(Vector2(10, 100)) and not sim.guards_against(Vector2(-100, 0)), "not from the side or behind")
	check(not sim.block(100) and near(sim.durability, 250.0), "a blocked 100 wears 100 off 350")
	run(sim, it, 1.0)
	check(near(sim.durability, 250.0), "no recovery while guarding")
	it.guard = true
	sim.step(it, DT)
	it.guard = false
	run(sim, it, 1.0)
	check(near(sim.durability, 257.0, 0.2), "7 a second back with the guard down (%.1f)" % sim.durability)
	it.guard = true
	sim.step(it, DT)
	it.guard = false
	check(sim.guarding and sim.block(300) and sim.durability == 0.0 and not sim.guarding, "a bigger hit breaks it and drops the guard")
	run(sim, it, 5.0)
	it.guard = true
	sim.step(it, DT)
	check(sim.durability == 0.0 and not sim.guarding, "a broken shield stays broken (shield_regeneration 0)")
	sim.reset_at(Vector2.ZERO, 0)
	check(sim.durability == 350.0, "whole again next round")

func test_confusion() -> void:
	print("Confusing Beam (ConfusionState, MoveState, TurnState)")
	var w := GameData.weapon(18)
	check(w.weapon_type == 2 and w.damage == 5 and w.state_action_type == 5 and near(w.bullet_speed, 528.0), "a normal bullet, 5 damage, 528 a second")
	var sim := MechSim.new()
	sim.confuse(w)
	var it := MechSim.Intent.new()
	it.right = true
	it.aim = Vector2(1000, 0)
	run(sim, it, 1.0)
	check(near(sim.speed(), sim.move_speed * 0.7), "walks at 0.7 (%.0f of %.0f)" % [sim.speed(), sim.move_speed])
	check(near(sim.damage_mul, 0.7) and near(sim.turn_mul, 0.7), "deals 0.7 of its damage and turns at 0.7")
	var shots: Array[float] = []
	var t := [0.0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: shots.append(t[0]))
	it.right = false
	it.fire = true
	for i in 90:
		t[0] += DT
		sim.step(it, DT)
		it.fire = false
	var due := sim.weapon.fire_interval + 0.8 + DT
	check(shots.size() == 1 and near(shots[0], due, 0.03), "the SR-3 shot leaves 0.8 s after its usual %.1f s (%s)" % [sim.weapon.fire_interval, str(shots)])
	sim.confuse(w)
	run(sim, it, 7.9)
	check(sim.is_confused(), "a new hit restarts the 8 s")
	run(sim, it, 0.2)
	check(not sim.is_confused() and sim.move_mul == 1.0 and sim.fire_delay == 0.0, "then it wears off")

func test_emp() -> void:
	print("EMP Shock Gun")
	var w := GameData.weapon(17)
	check(w.is_splash() and near(w.splash_area, 66.0) and w.mode_num("splash_damage") == 0.0 and w.damage == 20, "splash 66 units, splash_damage 0, damage 20")
	check(Combat.splash_direct(0, 20, 66, 5) == 24 and Combat.splash_direct(0, 20, 66, 30) == 20, "direct hit 24 close in, else 20")
	check(Combat.splash_falloff(0, 66, 10) == 0 and w.mode_num("jamming_time") == 12.0, "bystanders take 0, but any hit jams the radar 12 s")
	check(Combat.splash_direct(0, int(20 * w.mode_num("splash_ratio")), 66, 30) == 0, "a guard facing it leaves 0 (splash_ratio 0)")

func test_mine_firing() -> void:
	print("X-Mine firing")
	var w := GameData.weapon(19)
	check(w.is_mine() and not w.is_guided() and near(w.bullet_speed, 429.0) and near(w.life, 20.0) and near(w.splash_area, 66.0), "429 a second, 20 s, splash 66, no lock-on")
	var sim := MechSim.new("gigas")
	check(sim.slots[3].data.id == 19, "Gigas slot 4")
	var it := MechSim.Intent.new()
	it.weapon_key = 4
	run(sim, it, 1.0)
	it.weapon_key = 0
	var times: Array[float] = []
	var t := [0.0]
	sim.fired.connect(func(_o: Vector2, _d: int) -> void: times.append(t[0]))
	it.fire = true
	for i in 120:
		t[0] += DT
		sim.step(it, DT)
		it.fire = false
	check(times.size() == 2 and near(times[0], 0.5 + DT, 0.03) and near(times[1], 1.0 + DT, 0.03), "two mines, 0.5 s and 1 s after the click (%s)" % str(times))

func test_mine_cycle() -> void:
	print("X-Mine cycle (rc_bullet::update, is_stop)")
	var w := GameData.weapon(19)
	var owner := MechSim.new("gigas")
	var enemy := MechSim.new()
	enemy.pos = Vector2(1000, 0)
	var b := Bullet.new()
	b.setup(Vector2.ZERO, 0, owner, w)
	var found: Array = [null]
	b.find_target = func(_at: Vector2, _r: float) -> MechSim: return found[0]
	for i in 30:
		b.advance(DT)
	check(near(b.plane_pos.x, 85.8, 7.2) and b.is_lying(), "flies 0.2 s, to a frame (%.1f units), then lies still" % b.plane_pos.x)
	var lying_at := b.plane_pos
	for i in 60:
		b.advance(DT)
	check(b.plane_pos == lying_at and near(b.life, 20.0 - 1.5, 0.05), "waits, its 20 s running (%.2f left)" % b.life)
	enemy.pos = lying_at + Vector2(0, 300)
	found[0] = enemy
	b.advance(DT)
	check(b.target == enemy and b.dir.is_equal_approx(Vector2(0, 1)), "an enemy in range: it turns to face it")
	for i in 17:
		b.advance(DT)
	check(b.plane_pos == lying_at, "still for delay_after_stop 0.3 s")
	for i in 3:
		b.advance(DT)
	check(b.plane_pos.y > lying_at.y and near(b.life, 1.5, 0.05), "then chases, life now chase_time 1.5 s (%.2f)" % b.life)
	b.free()
	var players := [[1, Vector2(0, 0), true], [2, Vector2(300, 0), true], [3, Vector2(100, 0), false]]
	check(Combat.mine_target(1, Vector2(150, 0), 400, players) == 0, "nearest other player dead: no target")
	check(Combat.mine_target(1, Vector2(250, 0), 400, players) == 2, "nearest other player alive and in range")
	check(Combat.mine_target(1, Vector2(800, 0), 400, players) == 0, "beyond 400 units: none")
	check(Combat.mine_target(2, Vector2(250, 0), 400, players) == 0, "the owner itself never counts (3 is nearest and dead)")

func test_combo_table() -> void:
	print("command combos (combo_parameter.lua)")
	var want := {"zeid": [2, 3], "redkite": [4, 5], "gigas": [6, 7], "deff": [8, 9], "alicia": [10, 11]}
	var ok := true
	for body: String in want:
		var sim := MechSim.new(body)
		var ids: Array[int] = []
		for c in sim.combo_commands:
			ids.append(c.id)
		ok = ok and ids == Array(want[body], TYPE_INT, "", null)
	check(ok, "each body's own sword registers its two combos (2-3, 4-5, 6-7, 8-9, 10-11)")
	var c2 := Bodies.combo_param(2)
	var c3 := Bodies.combo_param(3)
	check(c2.damage == 14 and c2.finish == 0 and c3.damage == 30 and c3.finish == 1, "dagger: right, click +14; left, right, click +30, a finisher")
	check(Bodies.combo_param(10).damage == 15 and Bodies.combo_param(11).damage == 32, "saber: +15 and +32")

func test_combo_keys_follow_facing() -> void:
	print("combo keys turn with the facing (update_key_info)")
	var right_key := [false, true, false, false, false, false]
	var up_key := [false, false, true, false, false, false]
	var left_key := [true, false, false, false, false, false]
	var down_key := [false, false, false, true, false, false]
	var R := MechSim.ComboKey.RIGHT
	var L := MechSim.ComboKey.LEFT
	check(MechSim.combo_key_info(right_key, 0)[R] and MechSim.combo_key_info(left_key, 0)[L], "facing right: right is right")
	check(MechSim.combo_key_info(up_key, 90)[R] and MechSim.combo_key_info(down_key, 90)[L], "facing up: up is right, down is left")
	check(MechSim.combo_key_info(left_key, 180)[R] and MechSim.combo_key_info(right_key, 180)[L], "facing left: left and right swap")
	check(MechSim.combo_key_info(down_key, 270)[R] and MechSim.combo_key_info(up_key, 270)[L], "facing down: down is right, up is left")
	check(not MechSim.combo_key_info(up_key, 0)[R] and not MechSim.combo_key_info(up_key, 0)[MechSim.ComboKey.UP], "up and down never count on their own")

func _tap(sim: MechSim, it: MechSim.Intent, field: String, gap := 2) -> void:
	it.set(field, true)
	sim.step(it, DT)
	it.set(field, false)
	for i in gap:
		sim.step(it, DT)

func test_combo_input() -> void:
	print("combo input (ComboInputManager)")
	var sim := MechSim.new()
	sim.dashing = false
	var it := MechSim.Intent.new()
	it.aim = Vector2(1000, 0)
	_tap(sim, it, "right")
	it.fire = true
	sim._update_combo_input(it, DT)
	it.fire = false
	sim._update_combo_input(it, DT)
	check(sim.combo_ready == 2, "right then click within 0.2 s: combo 2")
	sim.take_combo(sim.slots[0].data)
	sim._update_combo_input(it, DT)
	it.right = true
	sim._update_combo_input(it, DT)
	it.right = false
	for i in 15:
		sim._update_combo_input(it, DT)
	it.fire = true
	sim._update_combo_input(it, DT)
	it.fire = false
	check(sim.combo_ready == 0, "a click 0.25 s after the key is too late")
	it.left = true
	sim._update_combo_input(it, DT)
	it.left = false
	sim._update_combo_input(it, DT)
	it.right = true
	sim._update_combo_input(it, DT)
	it.right = false
	sim._update_combo_input(it, DT)
	it.fire = true
	sim._update_combo_input(it, DT)
	it.fire = false
	check(sim.combo_ready == 3, "left, right, click: combo 3 wins over 2 on the same click")
	check(sim.take_combo(sim.slots[1].data) == 0, "only the sword's own combos count")

func test_combo_swings() -> void:
	print("combo swings (combo_shoot, ComboSystem)")
	var sim := MechSim.new()
	var it := MechSim.Intent.new()
	it.aim = Vector2(1000, 0)
	it.weapon_key = 1
	run(sim, it, 1.0)
	it.weapon_key = 0
	var swings: Array = []
	sim.swung.connect(func(_w: int, swing: int) -> void: swings.append([swing, sim.swing_combo]))
	# Facing right: right, click starts the combo with +14.
	_tap(sim, it, "right", 1)
	_tap(sim, it, "fire", 3)
	check(swings.size() == 1 and swings[0] == [2, 2], "the first swing carries combo 2 (%s)" % str(swings))
	# During the swing: left, right, click queues the finisher.
	_tap(sim, it, "left", 1)
	_tap(sim, it, "right", 1)
	_tap(sim, it, "fire", 1)
	run(sim, it, 0.6)
	check(swings.size() == 2 and swings[1] == [3, 3], "the queued swing carries combo 3 (%s)" % str(swings))
	_tap(sim, it, "fire", 1)
	run(sim, it, 0.8)
	check(swings.size() == 2 and not sim.combo_active, "a finisher ends the chain: no third swing")
	run(sim, it, 1.0)
	_tap(sim, it, "fire", 1)
	_tap(sim, it, "fire", 1)
	run(sim, it, 0.6)
	check(swings.size() == 4 and swings[2] == [2, 0] and swings[3] == [3, 0], "plain clicks carry nothing (%s)" % str(swings.slice(2)))
	# The handler holds the sim; let go of it so the sim is freed.
	for c in sim.swung.get_connections():
		sim.swung.disconnect(c.callable)

func test_room_slots() -> void:
	print("room slots and teams (srv_rcroom.cpp)")
	check(Room.join_slot([], false) == 0 and Room.join_slot([0, 1, 3], false) == 2, "free-for-all: the first free slot")
	var full: Array = []
	for i in 12:
		full.append(i)
	check(Room.join_slot(full, false) == -1 and Room.join_slot(full, true) == -1, "a full room of 12 takes nobody")
	check(Room.join_slot([], true) == 0 and Room.join_slot([0], true) == 6 and Room.join_slot([0, 6], true) == 1, "team battle: the smaller side, red when level")
	check(Room.join_slot([0, 1, 2, 3, 4, 5, 6], true) == 7 and Room.join_slot([0, 6, 7, 8, 9, 10, 11], true) == 1, "a full side sends the joiner to the other")
	check(Room.team_of(5, true) == Room.RED and Room.team_of(6, true) == Room.BLUE and Room.team_of(6, false) == Room.NONE, "slots 0-5 red, 6-11 blue, no teams in free-for-all")
	check(Room.switch_slot(2, [0, 2, 6]) == 7 and Room.switch_slot(6, [0, 2, 6]) == 1, "switching takes the first free slot on the other side")
	check(Room.can_start([0, 6], true) and not Room.can_start([0, 1, 6], true) and Room.can_start([0, 1, 6], false), "team battle needs equal sides")
	check(not Room.can_start([0], false), "and any game needs two")
	check(Room.teammates(Room.RED, Room.RED) and not Room.teammates(Room.NONE, Room.NONE) and not Room.teammates(Room.RED, Room.BLUE), "teammates share a team; free-for-all has none")

func test_room_start_points() -> void:
	print("start points (RCNetGameServer)")
	var rng := RandomNumberGenerator.new()
	var ok := true
	var blue_first_six := 0
	for trial in 200:
		rng.seed = trial
		var pts := Room.start_points([0, 1, 2, 6, 7, 8], true, rng)
		for s in [0, 1, 2]:
			ok = ok and pts[s] >= 0 and pts[s] < 6
		for s in [6, 7, 8]:
			ok = ok and pts[s] >= 6 and pts[s] < 12
		var seen := {}
		for s in [0, 1, 2, 6, 7, 8]:
			ok = ok and not seen.has(pts[s])
			seen[pts[s]] = true
		if pts[6] == 6:
			blue_first_six += 1
	check(ok, "red starts on points 0-5, blue on 6-11, never two on one point")
	check(blue_first_six > 100, "the first blue lands on point 6 more than half the time (%d of 200), as the server's draw did" % blue_first_six)
	rng.seed = 7
	var all: Array = []
	for i in 12:
		all.append(i)
	var ffa := Room.start_points(all, false, rng)
	var sorted := ffa.duplicate()
	sorted.sort()
	check(sorted == Array(range(12), TYPE_INT, "", null), "twelve in free-for-all fill all twelve points")

func test_room_end_and_winners() -> void:
	print("round end and winners (GameRoom::is_game_end, get_winners_team)")
	check(Room.round_over([3], false) and not Room.round_over([3, 5], false) and Room.round_over([], false), "free-for-all: one or none left")
	check(not Room.round_over([0, 7], true) and Room.round_over([0, 1], true) and Room.round_over([6], true), "team battle: one side empty")
	check(Room.winning_slots([0, 1, 6, 7], [1], true) == [0, 1], "the side still standing wins, its fallen included")
	check(Room.winning_slots([0, 6], [], true).is_empty() and Room.winning_slots([0, 3], [], false).is_empty(), "nobody left: everyone loses, no draw")
	check(Room.winning_slots([0, 3, 4], [4], false) == [4], "free-for-all: the survivor")

func _touch(tc: TouchControls, index: int, at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	tc._input(e)

func _drag(tc: TouchControls, index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	tc._input(e)

func test_touch_controls() -> void:
	print("touch controls")
	var tc := TouchControls.new()
	root.add_child(tc)
	# The tree is not running inside _init, so _ready has not happened yet.
	if tc._pad == null:
		tc._ready()
	tc._pad.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tc._pad.size = Vector2(1600, 720)
	tc.visible = true
	_touch(tc, 0, Vector2(150, 560), true)
	_drag(tc, 0, Vector2(190, 560))
	var k := tc.keys()
	check(k.right and not k.left and not k.up and not k.boost, "left stick half right: walk right")
	_drag(tc, 0, Vector2(240, 480))
	k = tc.keys()
	check(k.right and k.up and k.boost, "pushed to the rim up and right: diagonal with boost")
	_drag(tc, 0, Vector2(160, 560))
	check(not tc.keys().right and not tc.keys().boost, "inside the dead zone: nothing")
	_touch(tc, 0, Vector2(160, 560), false)
	_touch(tc, 1, Vector2(1300, 560), true)
	_drag(tc, 1, Vector2(1300, 540))
	check(tc.plane_aim().is_equal_approx(Vector2(0, 1)) and not tc.firing, "a short drag up aims up the plane without firing")
	_drag(tc, 1, Vector2(1300, 480))
	check(tc.firing and tc.fire_held(true), "past a third: fires, held for hold weapons")
	var clicks := 0
	var last := false
	for i in 60:
		tc._process(1.0 / 60.0)
		var f := tc.fire_held(false)
		if f and not last:
			clicks += 1
		last = f
	check(clicks >= 7 and clicks <= 9, "click weapons get about eight presses a second (%d)" % clicks)
	_touch(tc, 1, Vector2(1300, 480), false)
	check(not tc.firing and tc.plane_aim().is_equal_approx(Vector2(0, 1)), "letting go stops firing and keeps the aim")
	var two: Vector2 = tc._buttons().filter(func(b: Array) -> bool: return b[0] == "2")[0][1]
	_touch(tc, 2, two, true)
	check(tc.weapon_key == 2, "button 2 holds weapon key 2")
	_touch(tc, 2, two, false)
	var guard_at: Vector2 = tc._buttons().filter(func(b: Array) -> bool: return b[0] == "GUARD")[0][1]
	_touch(tc, 3, guard_at, true)
	check(tc.guard and tc.weapon_key == 0, "GUARD holds the guard key")
	_touch(tc, 3, guard_at, false)
	tc.free()

func test_equip_rules() -> void:
	print("equip rules (Shop_List, IsEnableEquip, Shop_Joint_Item)")
	check(Bodies.choices("zeid", 0) == [1, 28, 29] and Bodies.choices("zeid", 1) == [3, 37], "Zeid: swords EB Type 3, Dagger, Claw; guns SR-3, H.P Beam Rifle")
	check(Bodies.choices("zeid", 3) == [17, 46, 48, 49] and Bodies.choices("alicia", 3) == [25, 46, 47], "specials by body, AP Drain shared by Zeid and Alicia")
	check(not Bodies.choices("alicia", 0).has(27) and not Bodies.choices("deff", 0).has(34), "disabled shop rows (Whip, Crasher) are not offered")
	check(Bodies.checked_loadout("zeid", [21, 37, 4, 17]) == [1, 37, 4, 17], "another body's sword falls back to the default")
	check(Bodies.checked_loadout("zeid", [28, 3, 42, 49]) == [28, 3, 42, 49], "every weapon the shop sold is playable (PTL Type 1, Teleport Beam)")
	check(Bodies.shield_id("gigas") == 9 and Bodies.shield_id("alicia") == 22, "the shield is the body's own, never chosen")
	var sim := MechSim.new("redkite", Original.START_WEAPON, [30, 38, 43, 18])
	check(sim.slots[0].data.name == "Crescent Type 1" and sim.slots[2].data.name == "CP Cannon" and sim.shield.id == 16, "a chosen loadout reaches the slots; the shield stays")

func test_pulse_and_damage_stacks() -> void:
	print("Void Pulse and Impact Pulse-Gun (PulseState, AddDamageState)")
	var w := GameData.weapon(25)
	check(w.damage == 0 and w.crash_radius == 0.0 and w.mode_num("pulse_time") == 5.0, "Void Pulse does no damage; it is a 5 s pulse")
	var sim := MechSim.new("alicia")
	sim.pulse_time = 5.0
	var it := MechSim.Intent.new()
	run(sim, it, 4.9)
	check(sim.is_pulse(), "still intangible at 4.9 s")
	run(sim, it, 0.2)
	check(not sim.is_pulse(), "and solid again after 5 s")
	for i in 20:
		sim.add_damage_stack()
	check(near(sim.damage_taken_mul(), 2.5) and sim.damage_stacks.size() == 15, "stacks add 0.1 each up to 2.5x (15 stacks)")
	run(sim, it, 9.9)
	check(sim.damage_stacks.size() == 15, "each lasts 10 s")
	run(sim, it, 0.2)
	check(sim.damage_stacks.is_empty() and near(sim.damage_taken_mul(), 1.0), "then wears off")

func _button(kind: String) -> OriginalUI:
	var art := "ui3/page_login/login_access0%d.png"
	return OriginalUI._build("b", {"type": kind, "size": [125, 30], "pos": [10, 20],
		"texture": {"list": [art % 1, art % 2, art % 3], "fixedsize": 1}})

func test_original_controls() -> void:
	print("original controls (dialog.cpp)")
	var push := _button("WINDOW_PUSHBUTTON")
	var clicks := [0]
	push.clicked.connect(func() -> void: clicks[0] += 1)
	push.mouse_in()
	var hover := push.current
	push.press()
	var down := push.current
	push.release(true)
	check(hover == 2 and down == 3 and push.current == 2 and clicks[0] == 1, "push button: 2 under the pointer, 3 held, a click when let go on it")
	push.press()
	push.release(false)
	push.mouse_out()
	check(clicks[0] == 1 and push.current == 1, "let go off it: no click, back to 1")
	var check_button := _button("WINDOW_CHECKBUTTON")
	check_button.set_checked(true)
	check_button.mouse_out()
	check(check_button.current == 3, "check button stays on 3 while checked")
	var light := _button("WINDOW_HIGHLIGHT_BUTTON")
	light.highlight_size = Vector2(150, 50)
	light.mouse_in()
	light._process(0.1)
	check(light._glow.is_equal_approx(Vector2(150, 15)), "highlight: the glow grows to 150 x 15 in 0.1 s")
	light.press()
	light._process(0.2)
	check(light._glow.is_equal_approx(Vector2(400, 0)), "and flashes out to 400 x 0 when pressed")
	var parent := OriginalUI.new()
	parent.position = Vector2(100, 100)
	parent.add_child(push)
	check(parent.control_at(Vector2(150, 130)) == push and parent.control_at(Vector2(50, 50)) == null, "the control under a point, through its parents")
	parent.free()
	check_button.free()
	light.free()

func test_front_end() -> void:
	print("front end (page_main_menu, page_main_menu_option)")
	var fe := FrontEnd.new()
	fe.profile_path = "user://test_profile.cfg"
	root.add_child(fe)
	if fe.screen == null:
		fe._ready()
	fe.screen.scale = Vector2.ONE
	fe.screen.position = Vector2.ZERO
	fe.player_name = "Tester"
	fe.show_main_menu()
	var battles := [0]
	fe.battle_requested.connect(func() -> void: battles[0] += 1)
	var battle: OriginalUI = fe.page_root.find_child("battle_button", true, false)
	var at := fe._page_pos(battle) + battle._hit_size() * 0.5
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.pressed = true
	fe._input(e)
	var up := e.duplicate() as InputEventMouseButton
	up.pressed = false
	fe._input(up)
	check(battles[0] == 1, "clicking MATCH asks for a battle")
	check(fe.text("text_103") == "Go to battle room list" and battle.tooltip == fe.text("text_103"), "its tooltip is the original's English text")
	fe.show_options()
	var off: OriginalUI = fe.page_root.find_child("tooltip_check_box_off_button", true, false)
	off.clicked.emit()
	check(not fe.tooltips_on, "OPTION: tooltips off")
	fe.go_back()
	check(fe.page == "main", "back from the options to the main menu")
	fe.free()
	OriginalUI.release_statics()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_profile.cfg"))

static func _room_packet(id: String, room_name: String, locked: bool, teams: bool, players: int, playing: bool) -> String:
	return JSON.stringify({"magic": LanRooms.MAGIC, "room": {"id": id, "name": room_name, "locked": locked,
		"teams": teams, "beginner": false, "players": players, "playing": playing, "port": 7777}})

func test_lan_rooms() -> void:
	print("room list on the local network (LanRooms)")
	var lan := LanRooms.new()
	lan._heard(_room_packet("a", "Duel", false, false, 1, false), "192.168.1.5")
	lan._heard(_room_packet("b", "Teams", true, true, 3, true), "192.168.1.6")
	var rooms := lan.rooms()
	check(rooms.size() == 2 and int(rooms[0]["number"]) == 1 and int(rooms[1]["number"]) == 2, "rooms are numbered in the order they were first heard")
	check(not lan._heard("hello", "10.0.0.1") and not lan._heard(JSON.stringify({"magic": "other"}), "10.0.0.1"), "other packets are ignored")
	check(not lan._heard(_room_packet("a", "Duel", false, false, 1, false), "127.0.0.1") and str(lan.rooms()[0]["address"]) == "192.168.1.5",
		"the same room heard again changes nothing and keeps its first address")
	check(lan._heard(_room_packet("a", "Duel", false, false, 2, false), "192.168.1.5") and int(lan.rooms()[0]["players"]) == 2, "a new player count is news")
	lan._clock += LanRooms.EXPIRE + 0.1
	lan._heard(_room_packet("b", "Teams", true, true, 3, true), "192.168.1.6")
	lan._process(0.0)
	check(lan.rooms().size() == 1 and str(lan.rooms()[0]["id"]) == "b", "a room not heard for 3.5 s drops off")
	lan.free()
	# A real announcement over the loopback: one copy hosts, another listens.
	var host := LanRooms.new()
	var listener := LanRooms.new()
	if listener.listen():
		host.advertise({"name": "Loop", "locked": false, "teams": false, "beginner": false, "players": 1, "playing": false, "port": 7777})
		var first_id := str(host._info["id"])
		host.advertise({"name": "Loop", "locked": false, "teams": false, "beginner": false, "players": 2, "playing": false, "port": 7777})
		check(str(host._info["id"]) == first_id, "a room keeps its id as it changes")
		host._process(1.0)
		OS.delay_msec(100)
		listener._process(0.0)
		var heard := listener.rooms()
		check(heard.size() == 1 and str(heard[0]["name"]) == "Loop" and int(heard[0]["players"]) == 2, "a broadcast announcement is heard on this machine")
	else:
		check(false, "the room list port %d is free for the loopback test" % LanRooms.PORT)
	host.stop()
	listener.stop_listening()
	host.free()
	listener.free()

func test_room_pages() -> void:
	print("room list and game room (page_custom_game, page_game_room)")
	var fe := FrontEnd.new()
	fe.profile_path = "user://test_profile.cfg"
	root.add_child(fe)
	if fe.screen == null:
		fe._ready()
	fe.player_name = "Tester"
	fe.lan._heard(_room_packet("a", "Duel", false, false, 1, false), "192.168.1.5")
	fe.lan._heard(_room_packet("b", "Teams", true, true, 3, true), "192.168.1.6")
	fe.show_room_list()
	var rows := fe._list_rows()
	check(rows.get_child_count() == 2, "one row per room")
	var r0 := rows.get_child(0) as OriginalUI
	var r1 := rows.get_child(1) as OriginalUI
	check(r0.w("room_name").text == "Duel" and r0.w("game_type").text == "SINGLE" and r0.w("status").text == "Waiting"
		and r0.w("max_player").text == "1/12" and not r0.w("icon_lock").visible, "a row shows number, name, type, status and players")
	check(r1.w("game_type").text == "TEAM" and r1.w("status").text == "Playing" and r1.w("icon_lock").visible, "a locked team room that is playing")
	var bg := fe.page_root.get_node("res_dlg_custom_game_background") as OriginalUI
	bg.w("battle_room_topic").w("type_button").clicked.emit()
	check(fe._list_rows().get_child_count() == 1 and (fe._list_rows().get_child(0) as OriginalUI).w("room_name").text == "Duel", "the type button shows single battles only")
	bg.w("battle_room_topic").w("type_button").clicked.emit()
	bg.w("battle_room_topic").w("type_button").clicked.emit()
	check(fe._list_rows().get_child_count() == 2, "and comes round to all again")
	var joins := []
	fe.room_join.connect(func(address: String, pw: String) -> void: joins.append([address, pw]))
	bg.w("enter_button").clicked.emit()
	check(fe.popup_root.get_child_count() == 1 and joins.is_empty(), "Enter with no room chosen says to choose one")
	fe.popup_root.get_child(0).free()
	r0 = fe._list_rows().get_child(0) as OriginalUI
	r0.clicked.emit()
	check(r0.checked and joins.is_empty(), "a click chooses a room")
	r0.clicked.emit()
	check(joins.size() == 1 and joins[0] == ["192.168.1.5", ""] and fe.joined_number == 1, "a second click enters it")
	(fe._list_rows().get_child(1) as OriginalUI).clicked.emit()
	bg.w("enter_button").clicked.emit()
	var pw_box := fe.popup_root.get_child(0) as OriginalUI
	check(pw_box.name == "res_dlg_custom_game_information" and joins.size() == 1, "a locked room asks for its password")
	pw_box.w("dlg").w("input_password").editor.text = "secret"
	pw_box.w("dlg").w("ok_button").clicked.emit()
	check(joins.size() == 2 and joins[1] == ["192.168.1.6", "secret"], "and joins with it")
	pw_box.free()
	bg.w("battle_room_quick_go_edit_box").editor.text = "100.64.0.7"
	bg.w("battle_room_quick_go_edit_box").submitted.emit("100.64.0.7")
	check(joins.size() == 3 and joins[2] == ["100.64.0.7", ""], "Quick Go takes a host's address")
	bg.w("battle_room_quick_go_edit_box").editor.text = ""
	bg.w("battle_room_quick_go_edit_room_number").editor.text = "9"
	bg.w("battle_room_quick_go_edit_room_number").submitted.emit("9")
	check(joins.size() == 3 and fe.popup_root.get_child_count() == 1, "a room number nobody has is no room")
	fe.popup_root.get_child(0).free()
	var creates := []
	fe.room_create.connect(func(n: String, pw: String, t: bool, b: bool) -> void: creates.append([n, pw, t, b]))
	bg.w("create_game_button").clicked.emit()
	var create := fe.popup_root.get_child(0) as OriginalUI
	var dlg := create.w("dlg")
	dlg.w("input_name_edit").editor.text = " spaced"
	dlg.w("create_button").clicked.emit()
	check(creates.is_empty() and fe.popup_root.get_child_count() == 2, "a name starting with a space is refused (text_10)")
	fe.popup_root.get_child(1).free()
	dlg.w("arrow_button").clicked.emit()
	dlg.get_node("ResTypeSelectButton").w("team_battle_button").clicked.emit()
	check(dlg.w("game_type_text").text == "TEAM" and dlg.w("game_type_text").visible, "the game type drops down and TEAM is picked")
	dlg.w("input_name_edit").editor.text = "Friday"
	dlg.w("input_pass_edit").editor.text = "pw"
	dlg.w("create_button").clicked.emit()
	check(creates.size() == 1 and creates[0] == ["Friday", "pw", true, true], "Create hosts a team room (beginner on for a new pilot)")
	create.free()
	# The game room as a joining player sees it: red slot 1 is you, blue slot 7 the master.
	var view := {"number": 3, "name": "Friday", "teams": true, "playing": false, "beginner": true, "map": 2, "master": false,
		"slots": {0: {"name": "Tester", "face": 2, "master": false, "me": true, "playing": false},
			6: {"name": "Host", "face": 5, "master": true, "me": false, "playing": false}}}
	fe.show_game_room(view)
	var room := fe.page_root.get_node("res_dlg_game_room_background") as OriginalUI
	var users := room.w("res_dlg_game_room_userlist")
	check(room.w("room_number").text == "NO 3 " and room.w("room_name").text == "Friday" and room.w("game_type").text == "TEAM"
		and room.w("status").text == "Waiting" and room.w("is_beginner").text == "Beginner Room", "the information bar")
	check(room.w("res_dlg_game_room_game_option").w("game_map").current == 3 and not room.w("res_dlg_game_room_game_option").w("next_button").visible,
		"the map banner, with no arrows for a player who is not the master")
	check(not room.w("start_button").visible and room.w("red_team_mark").visible, "no START for a player; team marks in team battle")
	var me := users.w("red_team").w("team_seed_1").w("charactor_info_option")
	var master := users.w("blue_team").w("team_seed_7").w("charactor_info_option")
	check(me.visible and me.w("name").text == "Tester" and me.w("name").text_color == FrontEnd.MY_NAME and me.w("pilot_list").current == 2,
		"your slot: your name in yellow and your body's face")
	check(master.w("manager_mark").visible and not me.w("manager_mark").visible, "the master's slot has the master's mark")
	check(not users.w("red_team").w("team_seed_2").w("charactor_info_option").visible, "an empty slot shows nobody")
	var moves := []
	fe.room_slot.connect(func(sl: int) -> void: moves.append(sl))
	users.w("blue_team").w("team_seed_8").clicked.emit()
	check(moves == [7], "a click on a slot asks to move there")
	view["master"] = true
	fe.update_game_room(view)
	check(room.w("start_button").visible and room.w("res_dlg_game_room_game_option").w("next_button").visible, "the master gets START and the map arrows")
	fe.room_console_add("System : Host is come in", FrontEnd.NOTICE)
	check(fe._room_lines.size() == 1 and fe._console_lines.is_empty(), "the room has its own console")
	var exits := [0]
	fe.room_exit.connect(func() -> void: exits[0] += 1)
	fe.go_back()
	check(exits[0] == 1, "back leaves the room")
	fe.free()
	OriginalUI.release_statics()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_profile.cfg"))

func test_shop_page() -> void:
	print("item shop as the garage (page_game_shop)")
	var fe := FrontEnd.new()
	fe.profile_path = "user://test_profile.cfg"
	root.add_child(fe)
	if fe.screen == null:
		fe._ready()
	fe.player_name = "Tester"
	fe.body = "zeid"
	fe.loadouts.clear()
	var views := []
	fe.shop_view.connect(func(b: String, w: Array, slot: int) -> void: views.append([b, w.duplicate(), slot]))
	fe.show_shop()
	var shop := fe.shop
	check(shop.equipped == Bodies.checked_loadout("zeid", []) and views.size() == 1 and views[0][2] == Original.START_WEAPON,
		"the shop opens on the body's loadout, the robot holding its start weapon")
	var items := shop.list_items()
	var mine := items.filter(func(i: Dictionary) -> bool: return int(i["enable"]) == 0)
	check(items.size() == Bodies._shop_weapons().size() and not mine.is_empty() and mine.size() < items.size(),
		"the list shows the whole shop; another body's weapons are marked")
	var inven := shop.inven_items()
	var ok := not inven.is_empty()
	for id in inven:
		ok = ok and shop.usable(id) and not shop.equipped.has(id)
	check(ok, "the inventory holds this body's playable weapons that are not equipped")
	shop.equip()
	check(fe.popup_root.get_child_count() == 1, "EQUIP with nothing chosen says to choose (text_127)")
	fe.popup_root.get_child(0).free()
	var pick: int = inven[0]
	var slot := shop.slot_of(pick)
	var old: int = shop.equipped[slot]
	var cell := shop.root.w("inventory").w("Inven_ItemList").get_child(0) as OriginalUI
	cell.clicked.emit()
	check(views.back()[2] == slot and int(views.back()[1][slot]) == pick and shop.equipped[slot] == old,
		"choosing an inventory weapon shows the robot holding it, without equipping it")
	shop.equip()
	check(shop.equipped[slot] == pick and shop.inven_items().has(old) and not shop.inven_items().has(pick),
		"EQUIP puts it in its slot and the old one back in the inventory")
	shop.disarm()
	check(shop.equipped[slot] == old, "DISARM puts the slot's default back")
	shop.disarm()
	check(fe.popup_root.get_child_count() == 1, "disarming a default says it failed (text_136)")
	fe.popup_root.get_child(0).free()
	var tip := shop.item_tip(3, "SR-3", 1, true, false)
	check(str(tip["preview"]).contains("DAMAGE %d" % int(GameData.weapon_row(3)["damage"])) and str(tip["info"]) == fe.weapon_text(3)
		and fe.weapon_text(3).begins_with("Triple-energy gun."), "the item popup: the weapon's data and description")
	var other := shop.item_tip(5, "Beam Blade", 2, false, false)
	check(str(other["info"]).ends_with(fe.text("text_125")), "another body's weapon says it cannot be equipped")
	cell = shop.root.w("inventory").w("Inven_ItemList").get_child(0) as OriginalUI
	cell.clicked.emit()
	shop.equip()
	var kept := shop.equipped.duplicate()
	shop.root.w("exit_button").clicked.emit()
	check(fe.page == "main" and fe.loadout("zeid") == kept, "EXIT keeps the loadout and goes back to the channel")
	fe.loadouts.clear()
	fe._load_profile()
	check(fe.loadout("zeid") == kept and fe.loadout("gigas") == Bodies.checked_loadout("gigas", []),
		"loadouts are saved with the profile, by body")
	fe.free()
	OriginalUI.release_statics()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_profile.cfg"))

func test_state_rate() -> void:
	print("movement send rate by players (step 16)")
	check(Room.state_rate(2) == 60 and Room.state_rate(4) == 60, "2 to 4 players: 60 a second")
	check(Room.state_rate(5) == 30 and Room.state_rate(8) == 30, "5 to 8 players: 30 a second")
	check(Room.state_rate(9) == 20 and Room.state_rate(12) == 20, "9 to 12 players: 20 a second")
	check(Room.state_rate(12, true) == 60, "the master's override keeps 60 a second")
	check(roundi(60 / float(Room.state_rate(6))) == 2 and roundi(60 / float(Room.state_rate(10))) == 3,
		"at 60 physics ticks a second: every 2nd tick, every 3rd tick")
	# Between states a remote copy carries on along its last direction and speed.
	var owner := MechSim.new("zeid", 1)
	owner.reset_at(Vector2.ZERO, 0)
	var remote := MechSim.new("zeid", 1)
	remote.reset_at(Vector2.ZERO, 0)
	var it := MechSim.Intent.new()
	it.right = true
	for i in 30:
		owner.step(it, 1.0 / 60.0)
	remote.apply_snapshot(owner.snapshot())
	var at := remote.real_pos
	remote.step_remote(1.0 / 60.0)
	remote.step_remote(1.0 / 60.0)
	check(remote.real_pos.x > at.x and is_equal_approx(remote.real_pos.y, at.y), "a remote mech keeps moving between states")

static func _held(fire := false) -> MechSim.Intent:
	var it := MechSim.Intent.new()
	it.fire = fire
	it.aim = Vector2(1000, 0)
	return it

func test_step17_states() -> void:
	print("step 17 states (World::state_change by weapon id, rcPlayerState.cpp)")
	var m := MechSim.new("redkite", 1)
	m.reset_at(Vector2.ZERO, 0)
	m.start_state(GameData.weapon(51))
	var it := _held()
	it.right = true
	for i in 30:
		m.step(it, 1.0 / 60.0)
	check(m.is_frozen() and m.is_nodamage() and m.pos.distance_to(Vector2.ZERO) < 0.01, "Freezing Beam: frozen in place, keys ignored, no damage taken")
	m.start_state(GameData.weapon(50))
	check(m.reverse_time == 0.0, "a frozen mech takes no new state")
	for i in 600:
		m.step(_held(), 1.0 / 60.0)
	check(not m.is_frozen(), "the freeze ends after 10 s")
	m.start_state(GameData.weapon(50))
	var x0 := m.pos.x
	for i in 30:
		m.step(it, 1.0 / 60.0)
	check(m.pos.x < x0 - 10.0, "R.Control Beam: the right key moves left")
	var f := MechSim.new("zeid", 1)
	f.start_state(GameData.weapon(48))
	check(is_equal_approx(f.damage_taken_mul(), 0.7), "D Fielder: damage taken x 0.7")
	var p := MechSim.new("alicia", 1)
	p.start_state(GameData.weapon(47))
	check(is_equal_approx(p.power_recovery, 1.5) and is_equal_approx(p.power_reduce, 0.7), "Power Up Pulse: booster recovery x 1.5, use x 0.7 (booster_recovery, booster_reduce)")
	p.booster_gage = 1000.0
	p._spend(100.0)
	check(is_equal_approx(p.booster_gage, 930.0), "a weapon's energy cost x 0.7 while it lasts")
	var g := MechSim.new("deff", 2)
	g.start_state(GameData.weapon(57))
	check(g.weapon_index == 1, "Plasma Wire: a mech holding its third weapon is put on the second")
	var k := _held()
	k.weapon_key = 3
	g.step(k, 1.0 / 60.0)
	check(g.weapon_index == 1, "and cannot take the third while wired")
	var o := MechSim.new("gigas", 1)
	o.reset_at(Vector2.ZERO, 0)
	o.over_boost_time = MechSim.OVER_BOOST_TIME
	var b := _held()
	b.right = true
	b.boost = true
	for i in 3:
		o.step(b, 1.0 / 60.0)
	check(is_equal_approx(o._last_vel, o.vel_limit), "Over Booster: a boost runs at vel_limit at once")
	o.teleport_to(Vector2(500, 300))
	check(o.pos == Vector2(500, 300) and o.speed_state == 0 and o.move_dir == Vector2.ZERO, "Teleport Beam: the shooter there, stopped")

func test_step17_shots() -> void:
	print("step 17 shots (rcAmmo.cpp, copy_weapon_data_to_net)")
	check(is_equal_approx(GameData.weapon(48).life, 4.4) and is_equal_approx(GameData.weapon(29).reload, 15.1),
		"(BYTE) wraps: D Fielder life 30000 -> 4.4 s, Claw Type 1 reload 66386 -> 15.1 s")
	# CP.Pulse Cannon: 1 + charge level rounds (charge_repeat_shot).
	var c := MechSim.new("deff", 2, [14, 13, 45, 55])
	var shots := [0]
	c.fired.connect(func(_p: Vector2, _d: int) -> void: shots[0] += 1)
	for i in 70:
		c.step(_held(true), 1.0 / 60.0)
	var level := c.charge_level
	for i in 120:
		c.step(_held(false), 1.0 / 60.0)
	check(level == 3 and shots[0] == 1 + level, "CP.Pulse Cannon: charged to 3 in 1.17 s, then 4 rounds")
	# use_bullet_start_time: the MP7-C3's first round leaves at once.
	var a := MechSim.new("alicia", 1, [21, 36, 24, 25])
	var first := [0]
	a.fired.connect(func(_p: Vector2, _d: int) -> void: first[0] += 1)
	a.step(_held(true), 1.0 / 60.0)
	a.step(_held(true), 1.0 / 60.0)
	var sr := MechSim.new("zeid", 1, [1, 3, 4, 17])
	var sr_first := [0]
	sr.fired.connect(func(_p: Vector2, _d: int) -> void: sr_first[0] += 1)
	sr.step(_held(true), 1.0 / 60.0)
	sr.step(_held(true), 1.0 / 60.0)
	check(first[0] == 1 and sr_first[0] == 0, "MP7-C3: the first round leaves on the next update (bullet_start_time 0); the SR-3's waits its continuous_time")
	var b := Bullet.new()
	b.setup(Vector2.ZERO, 0, c, GameData.weapon(45), null, 5)
	check(is_equal_approx(b.speed, GameData.weapon(45).bullet_speed * 1.5) and b.power == 30, "a charged round: speed and damage x (1 + 0.1 x level)")
	var d := Bullet.new()
	d.setup(Vector2.ZERO, 0, c, GameData.weapon(48))
	check(not d.hits(Vector2.ZERO, 100.0), "the D Fielder's object never collides (collision_type 0)")
	var ptl := Bullet.new()
	ptl.setup(Vector2.ZERO, 0, c, GameData.weapon(42))
	check(ptl.child_count() == 6, "PTL Type 1 breaks into 6")
	ptl.proximity_fuse(true)
	check(is_equal_approx(ptl.life, 0.1), "and an enemy within 120 cuts its time to 0.1 s")
	var mp := Bullet.new()
	mp.setup(Vector2.ZERO, 0, c, GameData.weapon(36))
	check(mp.child_count() == 2 and is_equal_approx(mp.life, 0.1), "MP7-C3: 0.1 s, then 2")
	for x in [b, d, ptl, mp]:
		x.free()
