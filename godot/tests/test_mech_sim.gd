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
	check(near(shots[3] - shots[0], 1.7, 0.05), "next burst after the 0.5 s fire animation plus 1.2 s reload (%.2f s)" % (shots[3] - shots[0]))

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
	check(sim.slots[0].data.name == "Dagger Type 1" and sim.slots[2].data.name == "MML Type 1", "slots 1 and 3 hold the dagger and the MML")
	var changed := [-1]
	sim.weapon_changed.connect(func(slot: int) -> void: changed[0] = slot)
	var it := MechSim.Intent.new()
	it.weapon_key = 1
	sim.step(it, DT)
	check(sim.weapon_index == 0 and changed[0] == 0, "key 1 takes the dagger")
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
	var sim := MechSim.new()
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
	print("loadouts (Armor::init packs the slots, shields out)")
	var want := {
		"zeid": [28, 3, 4, 17], "redkite": [28, 6, 7, 18], "gigas": [28, 10, 11, 19],
		"deff": [28, 13, 12, 20], "alicia": [21, 23, 24, 20],
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
	var want := {"zeid": [2, 3], "redkite": [2, 3], "gigas": [2, 3], "deff": [2, 3], "alicia": [10, 11]}
	var ok := true
	for body: String in want:
		var sim := MechSim.new(body)
		var ids: Array[int] = []
		for c in sim.combo_commands:
			ids.append(c.id)
		ok = ok and ids == Array(want[body], TYPE_INT, "", null)
	check(ok, "each body's sword registers its two combos (Alicia's saber 10 and 11, the dagger 2 and 3)")
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
