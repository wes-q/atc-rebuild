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
	it.fire = true
	for i in 240:
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
