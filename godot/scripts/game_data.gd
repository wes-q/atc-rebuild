class_name GameData
extends RefCounted
## Original balance data from the game database (RayCrash Database.rar, raycrash1), exported
## by tools/extract_db.py, converted exactly as the live service did:
##   server  RayCrashMainServer (raycrashmain.cpp): divides and truncates to BYTE for the wire
##   client  NetRobotData2::set / NetWeaponData2::set (net/gamept.h): scales by HAHA values
##   client  rcArmor::init (rcArmor.cpp): multiplies back, stores speeds as int

const DATA_DIR := "res://assets/original/data/"

static var _robots: Dictionary = {}
static var _weapons: Dictionary = {}

## Stats a default mech of this body gets in battle. Armour and MCS rows are not applied:
## the server copies them nowhere (the lines are commented out), only purchased parts add on.
class Robot:
	var name: String
	var life: int ## armor_point
	var energy_max: float
	var move_speed: float
	var booster_speed: float
	var booster_init_speed: float
	var rotation_speed: float
	var crash_radius: float
	var energy_reduce: float
	var regenerate: float
	var energy_low_line: float
	var boost_accel: float ## rcPlayer::accel
	var vel_limit: float ## rcPlayer::vel_limit
	var weapons: Array[int] = []

class Weapon:
	var id: int
	var name: String
	var damage: int
	var fire_num: int ## continuous_number
	var fire_interval: float ## continuous_time, seconds between queued shots
	var bullet_speed: float
	var life: float
	var reload: float ## re_load_time, seconds
	var crash_radius: float
	var weapon_type: int ## 1 sword (HIT_TYPE_SWORD), 2 bullet, 5 shield
	var collision_degree: float ## sword arc, whole angle in degrees
	var collision_checker: int ## 1 the attacker decides the damage, 2 the one hit does
	var ammo: int ## -1 when the weapon has no ammo limit
	var cost_energy: float ## booster gauge spent per bullet or swing (rc_Weapon::update_bullet)
	var guided_flag: int ## homing strength, 0 for none

	func is_sword() -> bool:
		return weapon_type == 1

	func is_guided() -> bool:
		return guided_flag > 0

static func _byte(v: float) -> int:
	return clampi(int(v), 0, 255)

static func _num(v: Variant) -> float:
	return 0.0 if v == null else float(v)

static func _load(table: String) -> Array:
	var path := DATA_DIR + table + ".json"
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Missing %s. Run godot/tools/extract_db.py on the original database backup." % path)
		return []
	return JSON.parse_string(text)

static func robot(name: String) -> Robot:
	if _robots.is_empty():
		for row in _load("RobotInfo"):
			_robots[str(row.name).to_lower()] = row
	var r: Dictionary = _robots[name.to_lower()]
	var s := Robot.new()
	s.name = r.name
	var vel_scale := Original.VEL_SCALE
	# Server packing (raycrashmain.cpp copy into NetRobotData), then client unpacking.
	s.energy_max = _byte(r.energy / 100.0) * 100.0
	s.life = int(r.armor_point)
	s.move_speed = int(_byte(r.normal_speed / 10.0) * vel_scale * 10.0)
	s.booster_speed = int(_byte(r.boost_speed / 10.0) * vel_scale * 10.0)
	s.booster_init_speed = s.booster_speed + Original.BOOSTER_INIT_EXTRA
	s.rotation_speed = _byte(r.rotation_speed / 10.0) * 10.0
	s.crash_radius = float(r.collision_area) * Original.SCALE
	s.energy_reduce = _byte(r.energy_consumption / 10.0) * 10.0
	s.regenerate = float(r.energy_recovery)
	s.energy_low_line = _byte(r.energy_low_line / 10.0) * 10.0
	s.boost_accel = _byte(r.add_booster_speed / 10.0) * vel_scale * 0.5
	s.vel_limit = _byte(r.limit_booster_speed / 100.0) * vel_scale * 100.0
	for k in ["default_weapon1_id", "default_weapon2_id", "default_weapon3_id", "default_weapon4_id", "default_weapon5_id"]:
		s.weapons.append(int(r[k]))
	return s

static func weapon(id: int) -> Weapon:
	if _weapons.is_empty():
		for row in _load("WeaponInfo"):
			_weapons[int(row.id)] = row
	var w: Dictionary = _weapons[id]
	var s := Weapon.new()
	s.id = id
	s.name = w.name
	s.damage = int(_num(w.damage))
	s.fire_num = int(_num(w.continuous_number))
	# copy_weapon_data_to_net then rcWeaponMode / rc_bullet: BYTE(x/10)*10/1000, BYTE(x/100)*100/1000.
	s.fire_interval = _byte(_num(w.continuous_time) / 10.0) * 10.0 / 1000.0
	s.life = _byte(_num(w.life_time) / 100.0) * 100.0 / 1000.0
	s.reload = _byte(_num(w.re_load_time) / 100.0) * 100.0 / 1000.0
	s.bullet_speed = _byte(_num(w.bullet_speed) / 100.0) * Original.VEL_SCALE * 100.0
	# NetWeaponData2::set: collision_area *= HAHA_SCALE_VAL * 1.1; the arc angle is not scaled.
	s.crash_radius = _num(w.collision_area) * Original.VEL_SCALE
	s.weapon_type = int(_num(w.weapon_type))
	s.collision_degree = _num(w.collision_degree)
	s.collision_checker = int(_num(w.collision_checker))
	s.ammo = int(w.ammo) if w.ammo != null and int(w.ammo) > 0 else -1
	s.cost_energy = _num(w.cost_energy)
	s.guided_flag = int(_num(w.guided_flag))
	return s
