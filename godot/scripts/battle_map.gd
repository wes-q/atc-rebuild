class_name BattleMap
extends RefCounted
## One arena: the rules half of rc_map plus the server's start points. Reads the map.json
## that convert_original.py builds from test_map.lua, the map model and the server source.
## The scenery itself is built by BattleWorld.build_map.

const ROOT := "res://assets/original/map/"

var id := ""
var title := ""
var folder := ""
var x_min := -1215.0
var x_max := 1225.0
var y_min := -1303.0
var y_max := 1242.0
var spawns: Array[Vector2] = []
var light_diffuse := Vector3(2, 2, 2)
var light_ambient := Vector3(0.3, 0.3, 0.3)
var light_direction := Vector3(-2, 1.2, -2)
var objects: Array = []
var collision := MapCollision.new()

## Arenas in room map order: [{id, title}].
static func list() -> Array:
	var f := FileAccess.open(ROOT + "maps.json", FileAccess.READ)
	if f == null:
		return []
	return JSON.parse_string(f.get_as_text())

static func load_map(map_id: String) -> BattleMap:
	var f := FileAccess.open(ROOT + map_id + "/map.json", FileAccess.READ)
	if f == null:
		push_error("map %s is not converted; run tools/convert_original.py" % map_id)
		return null
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var m := BattleMap.new()
	m.id = d["id"]
	m.title = d["title"]
	m.folder = ROOT + map_id + "/"
	var b: Dictionary = d["bounds"]
	m.x_min = b["x_min_bound"]
	m.x_max = b["x_max_bound"]
	m.y_min = b["y_min_bound"]
	m.y_max = b["y_max_bound"]
	for s in d["spawns"]:
		m.spawns.append(Vector2(s[0], s[1]))
	m.light_diffuse = _vec(d.get("light_diffuse"), m.light_diffuse)
	m.light_ambient = _vec(d.get("light_ambient"), m.light_ambient)
	m.light_direction = _vec(d.get("light_direction"), m.light_direction)
	m.objects = d["objects"]
	m.collision = MapCollision.new(d["collision"])
	return m

static func _vec(v: Variant, fallback: Vector3) -> Vector3:
	if v is Dictionary:
		return Vector3(v.get("x", 0.0), v.get("y", 0.0), v.get("z", 0.0))
	return fallback

func in_bounds(p: Vector2) -> bool:
	return p.x >= x_min and p.x <= x_max and p.y >= y_min and p.y <= y_max

## rc_map::process_map_bound: a mech that left the arena rectangle is put back on its edge.
## Returns {} when inside, otherwise the edge "point", the wall "normal" (not normalised at
## a corner, as in the original) and the "incident" movement that carried it out.
func bound_crash(pos: Vector2, prev: Vector2) -> Dictionary:
	if in_bounds(pos):
		return {}
	var normal := Vector2.ZERO
	var point := pos
	var inside_x := pos.x >= x_min and pos.x <= x_max
	var inside_y := pos.y >= y_min and pos.y <= y_max
	if not inside_x:
		normal.x = -1.0 if pos.x > 0.0 else 1.0
		point.x = x_max if pos.x > 0.0 else x_min
	if not inside_y:
		normal.y = -1.0 if pos.y > 0.0 else 1.0
		point.y = y_max if pos.y > 0.0 else y_min
	return {"point": point, "normal": normal, "incident": pos - prev}

## rc_map::crashed_with_wall: bounce off along the reflection, 1.7 x 130 x HAHA_SCALE_VAL away.
static func wall_bounce_target(crash: Dictionary) -> Vector2:
	var incident: Vector2 = crash["incident"]
	var normal: Vector2 = crash["normal"]
	var reflected := normal * (-incident.dot(normal) * 2.0) + incident
	if reflected.length_squared() < 1e-9:
		reflected = normal
	return crash["point"] + reflected.normalized() * Original.WALL_BOUNCE_DISTANCE
