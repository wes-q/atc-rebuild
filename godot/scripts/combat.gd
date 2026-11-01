class_name Combat
extends RefCounted
## Damage rules that are not tied to one weapon's flight, as pure functions for testing.

## rc_bullet::explosion: splash falls off in 10% steps of the radius; inside a fifth of it the
## damage is x1.2. Returns 0 outside the radius.
static func splash_falloff(splash_damage: float, radius: float, distance: float) -> int:
	if radius <= 0.0 or distance > radius:
		return 0
	var steps := int(distance / radius * 10.0)
	var dmg := splash_damage - splash_damage * steps * 10.0 / 100.0
	if distance < radius * 0.2:
		dmg *= 1.2
	return int(maxf(0.0, dmg))

## World::process_crash for a splash weapon's direct hit: splash_damage plus the weapon's
## damage, x1.2 inside a fifth of the radius, no falloff.
static func splash_direct(splash_damage: float, damage: int, radius: float, distance: float) -> int:
	var dmg := splash_damage + damage
	if distance < radius * 0.2:
		dmg *= 1.2
	return int(dmg)

## World::state_change for the Plasma Bow (id 24): stunned 1 s plus 0.5 s per charge level.
static func bow_stun_time(charge: int) -> float:
	return 1.0 + 0.5 * charge

## StunState pushes the one hit 200 units along the arrow (pt_send_move(pos + dir * 200)).
const BOW_PUSH := 200.0

## rc_bullet::is_crash for an immediate line: segment against the mech's sphere, no width.
## lift: the mech's height (a jump); the line is taken on the ground (inferred).
static func line_hits(a: Vector2, b: Vector2, at: Vector2, mech_radius: float, lift := 0.0) -> bool:
	var d := Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at)
	return sqrt(d * d + lift * lift) <= mech_radius

## World::find_nearest_other_player_index for an X-Mine: the nearest player other than the
## owner; none if that one is dead or farther than the range (detecting_area, not scaled).
## players: Array of [id, plane pos, alive]. Returns the id, or 0 for none.
static func mine_target(owner_id: int, at: Vector2, detect_range: float, players: Array) -> int:
	var best: Array = []
	for p in players:
		if p[0] == owner_id:
			continue
		if best.is_empty() or at.distance_squared_to(p[1]) < at.distance_squared_to(best[1]):
			best = p
	if best.is_empty() or not best[2] or at.distance_to(best[1]) > detect_range:
		return 0
	return best[0]

## World::process_crash for a guarded mech, by the hit's weapon_type: swords and normal
## bullets are stopped and wear the shield; pierce shots go through; a splash shell's direct
## hit does splash_damage plus damage x splash_ratio (0 unless the mode sets it).
enum Guard { BLOCK, THROUGH, SPLASH }
static func guard_rule(weapon_type: int) -> Guard:
	match weapon_type:
		3:
			return Guard.THROUGH
		4:
			return Guard.SPLASH
	return Guard.BLOCK
