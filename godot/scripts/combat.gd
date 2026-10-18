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
static func line_hits(a: Vector2, b: Vector2, at: Vector2, mech_radius: float) -> bool:
	return Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) <= mech_radius
