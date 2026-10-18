class_name ParticleQuad
extends MeshInstance3D
## One layer of an original particle script (data/script/particle/*.lua, engine core/psys.cpp)
## for the simple case the HIT and DAMAGE markers use: a single particle that stays on its
## parent frame (link_to_parent), faces the camera with screen-up as up, and lives for the
## layer's "energy" seconds. Its colour and scale follow the script's keys, given as
## percent of life. The rest of the particle engine (spreads, velocities, repeated
## emission) is not ported yet.

const ROOT := "res://assets/original/ui/"

static var _scripts: Dictionary = {}

var life := 1.0
var age := 0.0
var size_base := Vector2.ONE
var color_keys: Array = [] ## [percent, Color]
var scale_keys: Array = [] ## [percent, float]
var _mat: StandardMaterial3D

## The layers of a particle script, by name ("font_hit").
static func layers(script_name: String) -> Array:
	if _scripts.is_empty():
		var f := FileAccess.open(ROOT + "particles.json", FileAccess.READ)
		if f:
			_scripts = JSON.parse_string(f.get_as_text())
	var out := []
	var table: Dictionary = _scripts.get(script_name, {})
	for key in table.get("@order", table.keys()):
		if table.get(key) is Dictionary:
			out.append(table[key])
	return out

static func from_layer(layer: Dictionary, priority: int) -> ParticleQuad:
	var q := ParticleQuad.new()
	var size: Array = layer.get("size", [1, 1])
	q.size_base = Vector2(size[0], size[1])
	var energy: Array = layer.get("energy", [0, 1.0])
	q.life = float(energy[1]) if energy.size() > 1 else 1.0
	var c: Array = layer.get("color", [])
	for i in range(0, c.size() - 4, 5):
		q.color_keys.append([float(c[i]), Color8(int(c[i + 1]), int(c[i + 2]), int(c[i + 3]), int(c[i + 4]))])
	var s: Array = layer.get("scale", [])
	for i in range(0, s.size() - 1, 2):
		q.scale_keys.append([float(s[i]), float(s[i + 1])])
	var quad := QuadMesh.new()
	quad.size = q.size_base
	q.mesh = quad
	q._mat = StandardMaterial3D.new()
	q._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q._mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q._mat.billboard_keep_scale = true
	q._mat.no_depth_test = true
	# The model under it carries the mirrored axis mapping, which turns the quad's back to the camera.
	q._mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q._mat.render_priority = priority
	q._mat.albedo_texture = load(ROOT + str(layer.get("texture", ""))) if ResourceLoader.exists(ROOT + str(layer.get("texture", ""))) else null
	q.material_override = q._mat
	q._apply()
	return q

func _process(dt: float) -> void:
	age += dt
	if age >= life:
		visible = false
		set_process(false)
		return
	_apply()

func _apply() -> void:
	var pct := 100.0 * age / life
	_mat.albedo_color = _key(color_keys, pct, Color(1, 1, 1, 1))
	var k: float = _key(scale_keys, pct, 1.0)
	scale = Vector3.ONE * k

static func _key(keys: Array, pct: float, fallback: Variant) -> Variant:
	if keys.is_empty():
		return fallback
	if pct <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if pct <= keys[i][0]:
			var t: float = (pct - keys[i - 1][0]) / maxf(keys[i][0] - keys[i - 1][0], 0.0001)
			var a: Variant = keys[i - 1][1]
			var b: Variant = keys[i][1]
			return a.lerp(b, t) if a is Color else lerpf(a, b, t)
	return keys[-1][1]
