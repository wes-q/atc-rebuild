class_name ParticleFX
extends Node3D
## Port of the original particle engine (engine/core/psys.cpp, billboard.cpp and the loader in
## engine.cpp). A model frame named "p<group>:<script>,<script>" (renamed "p<group>~..." by the
## converter) runs those scripts from data/script/particle; tools/extract_ui.py exports them to
## particles.json. Each script is a set of sprays. Attach one ParticleFX under the frame node.
##
## Original conventions kept: keys are given against percent of time; particle colour, velocity,
## scale and spin follow the particle's own life, while emit count, life ("energy"), spread and
## the gap between emissions follow the spray's clock over its duration. Every table is sampled
## into 64 steps like PSprayInfo::lookup_make. A spray not linked to its frame leaves particles
## behind in the world and has its size scaled by 0.3; a linked one moves with the frame.
## alpha = 1 blends normally, anything else is additive.

const ROOT := "res://assets/original/ui/"
const STEPS := 64
## Godot's node names cannot hold ':', so the converter writes '~'.
const NAME_SEP := "~"

static var _scripts: Dictionary = {}
static var _infos: Dictionary = {}
static var _textures: Dictionary = {}
static var _NODE_SUFFIX := RegEx.create_from_string("_node(_\\d+)?$")

## A spray's settings and lookup tables (PSprayInfo).
class Info:
	var duration := 1.0
	var loop := false
	var link := false
	var billboard := 0
	var filter := false
	var trail := false
	var size := Vector2.ONE
	var texture: Texture2D
	var sprite := Vector3i.ZERO ## x cells, y cells, loop
	var sprite_fps := 30.0
	var velocity_randomness := 0
	var pos_randomness := 0
	var start_pos_offset := 0.0
	var axis_offset := 0.0
	var color: PackedColorArray
	var velocity: PackedFloat32Array
	var scale: PackedVector2Array
	var spin: PackedFloat32Array
	var energy: PackedFloat32Array
	var count: PackedInt32Array
	var spread_zx: PackedInt32Array
	var spread_zy: PackedInt32Array
	var gap: PackedFloat32Array

	static func index(t: float, max_t: float) -> int:
		if max_t <= 0.0:
			return STEPS - 1
		return clampi(int(t * float(STEPS) / max_t), 0, STEPS - 1)

class Particle:
	var pos := Vector3.ZERO ## frame space (linked) or Godot world (not linked)
	var dir := Vector3(0, 0, 1)
	var lifetime := 0.0
	var energy := 1.0
	var velocity_offset := 0.0
	var color := Color.WHITE
	var scale := Vector2.ONE
	var rot := 0.0
	var weight := 0.0

## One running spray (PSysSpray or PSysTrail).
class Spray:
	var info: Info
	var particles: Array[Particle] = []
	var time_elapsed := 0.0
	var emit_time := 0.0
	var stopped := false
	var prev_center := Vector3.ZERO
	var total_weight := 0.0
	var mesh := ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()

var group := ""
var sprays: Array[Spray] = []
## Frees itself once every spray has finished and no particle is left (projectile effects).
var self_destruct := false

## The particle frames inside an imported model: [node, group, script names].
static func frames_in(scene: Node) -> Array:
	var out := []
	for n in scene.find_children("p*", "Node3D", true, false):
		var node_name := str(n.name)
		if not NAME_SEP in node_name:
			continue
		var parts := node_name.substr(1).split(NAME_SEP, true, 1)
		var group_name := parts[0] if parts[0] != "" else "particle"
		# A second frame with the same name comes through the import as "..._node" or
		# "..._node_<n>"; it runs the same scripts.
		var scripts_part := _NODE_SUFFIX.sub(parts[1], "")
		out.append([n, group_name, scripts_part.split(",", false)])
	return out

## Adds a ParticleFX under every particle frame of a model. Returns them by group.
static func attach_all(scene: Node, destruct := false) -> Dictionary:
	var by_group := {}
	for f in frames_in(scene):
		var fx := ParticleFX.new()
		fx.group = f[1]
		fx.self_destruct = destruct
		for script_name in f[2]:
			fx.add_script(script_name)
		(f[0] as Node3D).add_child(fx)
		if not by_group.has(fx.group):
			by_group[fx.group] = []
		by_group[fx.group].append(fx)
	return by_group

static func _load_scripts() -> void:
	if not _scripts.is_empty():
		return
	var f := FileAccess.open(ROOT + "particles.json", FileAccess.READ)
	if f:
		_scripts = JSON.parse_string(f.get_as_text())

static func infos(script_name: String) -> Array[Info]:
	if _infos.has(script_name):
		return _infos[script_name]
	_load_scripts()
	var out: Array[Info] = []
	var table: Dictionary = _scripts.get(script_name, {})
	for key in table.get("@order", table.keys()):
		if table.get(key) is Dictionary:
			out.append(_make_info(table[key]))
	_infos[script_name] = out
	return out

static func _make_info(v: Dictionary) -> Info:
	var i := Info.new()
	i.duration = float(v.get("duration", 1.0))
	i.loop = int(v.get("loop", 0)) != 0
	i.link = int(v.get("link_to_parent", 0)) != 0
	i.billboard = int(v.get("billboard", 0))
	i.filter = int(v.get("alpha", 0)) == 1
	i.trail = str(v.get("type", "")) == "PSYS_TRAIL" or str(v.get("type", "")) == "1"
	var s: Array = v.get("size", [1, 1])
	i.size = Vector2(s[0], s[1]) * (1.0 if i.link else 0.3)
	var tex_path := str(v.get("texture", ""))
	if tex_path != "":
		if not _textures.has(tex_path):
			_textures[tex_path] = load(ROOT + tex_path) if ResourceLoader.exists(ROOT + tex_path) else null
		i.texture = _textures[tex_path]
	var spr: Variant = v.get("sprite_info")
	if spr is Dictionary:
		i.sprite = Vector3i(int(spr.get("x", 1)), int(spr.get("y", 1)), int(spr.get("loop", 1)))
		i.sprite_fps = float(spr.get("fps", 30))
	i.velocity_randomness = int(v.get("velocity_randomness", 0))
	i.pos_randomness = int(v.get("pos_randomness", 0))
	i.start_pos_offset = float(v.get("start_pos_offset", 0))
	i.axis_offset = float(v.get("axis_aligned_billboard_panel_y_offset", 0))
	var color_keys := []
	var c: Array = v.get("color", [])
	for k in range(0, c.size() - 4, 5):
		color_keys.append([float(c[k]), Color(c[k + 1] / 255.0, c[k + 2] / 255.0, c[k + 3] / 255.0, c[k + 4] / 255.0)])
	var scale_keys := []
	if v.has("scale"):
		var sc: Array = v["scale"]
		for k in range(0, sc.size() - 1, 2):
			scale_keys.append([float(sc[k]), Vector2(sc[k + 1], sc[k + 1])])
	elif v.has("scale_xy"):
		var sxy: Array = v["scale_xy"]
		for k in range(0, sxy.size() - 2, 3):
			scale_keys.append([float(sxy[k]), Vector2(sxy[k + 1], sxy[k + 2])])
	for n in STEPS:
		var t := float(n) * 100.0 / float(STEPS)
		i.color.append(_interp(color_keys, t, Color(1, 1, 1, 1)))
		i.scale.append(_interp(scale_keys, t, Vector2.ONE))
		i.velocity.append(_interp(_pairs(v.get("velocity")), t, 0.0))
		i.spin.append(deg_to_rad(_interp(_pairs(v.get("spin")), t, 0.0)))
		i.energy.append(_interp(_pairs(v.get("energy")), t, 1.0))
		i.count.append(int(_interp(_pairs(v.get("emit_count")), t, 0.0)))
		i.spread_zx.append(int(_interp(_pairs(v.get("spread_zx")), t, 0.0)))
		i.spread_zy.append(int(_interp(_pairs(v.get("spread_zy")), t, 0.0)))
		i.gap.append(_interp(_pairs(v.get("emit_time_gap")), t, 1.0))
	return i

static func _pairs(a: Variant) -> Array:
	var out := []
	if a is Array:
		for k in range(0, a.size() - 1, 2):
			out.append([float(a[k]), float(a[k + 1])])
	return out

## Linear between keys, held at the ends (fcurve).
static func _interp(keys: Array, t: float, fallback: Variant) -> Variant:
	if keys.is_empty():
		return fallback
	if t <= keys[0][0]:
		return keys[0][1]
	for k in range(1, keys.size()):
		if t <= keys[k][0]:
			var span: float = maxf(keys[k][0] - keys[k - 1][0], 0.0001)
			var f: float = (t - keys[k - 1][0]) / span
			var a: Variant = keys[k - 1][1]
			var b: Variant = keys[k][1]
			if a is float:
				return lerpf(a, b, f)
			return a.lerp(b, f)
	return keys[-1][1]

func add_script(script_name: String) -> void:
	for info in infos(script_name):
		var s := Spray.new()
		s.info = info
		s.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s.material.vertex_color_use_as_albedo = true
		s.material.albedo_texture = info.texture
		s.material.cull_mode = BaseMaterial3D.CULL_DISABLED
		s.material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		s.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if not info.filter:
			s.material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		s.instance.mesh = s.mesh
		s.instance.top_level = true
		s.instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.instance.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
		add_child(s.instance)
		sprays.append(s)

## PSysAbstract::start and stop for every spray of this frame.
func start() -> void:
	for s in sprays:
		s.time_elapsed = 0.0
		s.stopped = false

func stop() -> void:
	for s in sprays:
		s.stopped = true

func is_finished() -> bool:
	for s in sprays:
		if not s.particles.is_empty():
			return false
		if not s.stopped and (s.info.loop or s.time_elapsed <= s.info.duration):
			return false
	return true

func _process(dt: float) -> void:
	var frame := get_parent() as Node3D
	if frame == null or not frame.is_visible_in_tree():
		for s in sprays:
			s.instance.visible = false
		return
	var ft := frame.global_transform
	# The frame's own axes in original (left-handed) terms: undo the import mirror.
	var basis_d := ft.basis * Basis.from_scale(Vector3(1, 1, -1))
	var camera := get_viewport().get_camera_3d()
	for s in sprays:
		s.instance.visible = true
		_update(s, dt, ft.origin, basis_d)
		if camera:
			_draw(s, ft.origin, basis_d, camera)
	if self_destruct and is_finished():
		queue_free()

func _update(s: Spray, dt: float, origin: Vector3, basis_d: Basis) -> void:
	var info := s.info
	# update_particles
	var k := s.particles.size() - 1
	while k >= 0:
		var p := s.particles[k]
		p.lifetime += dt
		if p.lifetime > p.energy:
			s.total_weight -= p.weight
			s.particles.remove_at(k)
		else:
			var li := Info.index(p.lifetime, p.energy)
			p.color = info.color[li]
			p.rot = info.spin[li]
			p.scale = info.scale[li]
			if not info.trail:
				p.pos += p.dir * (info.velocity[li] + p.velocity_offset) * dt
		k -= 1
	s.time_elapsed += dt
	s.emit_time -= dt
	if info.trail:
		_update_trail(s, origin)
		return
	if not _emit_time(s):
		return
	var idx := Info.index(s.time_elapsed, info.duration)
	s.emit_time = info.gap[idx]
	for n in info.count[idx]:
		var p := Particle.new()
		p.energy = info.energy[idx]
		p.color = info.color[0]
		var d := Vector3(0, 0, 1)
		var zx := info.spread_zx[idx]
		var zy := info.spread_zy[idx]
		# The original's spread is lopsided: (rand() % s) * 2 - s / 2 degrees.
		var deg_zy := float((randi() % zx) * 2 - zx / 2) if zx > 0 else 0.0
		var deg_zx := float((randi() % zy) * 2 - zy / 2) if zy > 0 else 0.0
		d = _rotate_zx(d, deg_to_rad(deg_zy))
		d = _rotate_zy(d, deg_to_rad(deg_zx))
		if info.velocity_randomness > 0:
			p.velocity_offset = float(randi() % info.velocity_randomness)
		if info.link:
			p.pos = Vector3.ZERO
		else:
			# Not normalised, as in the original: the frame's scale carries into the speed.
			d = basis_d * d
			p.pos = origin
		if info.start_pos_offset != 0.0:
			p.pos += d * info.start_pos_offset
		if info.pos_randomness > 0:
			var r := info.pos_randomness
			p.pos += Vector3(randi() % r - r / 2, randi() % r - r / 2, randi() % r - r / 2)
		p.dir = d
		s.particles.append(p)

static func _rotate_zx(d: Vector3, a: float) -> Vector3:
	return Vector3(d.x * cos(a) + d.z * sin(a), d.y, d.z * cos(a) - d.x * sin(a))

static func _rotate_zy(d: Vector3, a: float) -> Vector3:
	return Vector3(d.x, d.y * cos(a) + d.z * sin(a), d.z * cos(a) - d.y * sin(a))

## PSysAbstract::is_particle_emit_time
func _emit_time(s: Spray) -> bool:
	if s.emit_time > 0.0 or s.stopped:
		return false
	if s.time_elapsed > s.info.duration:
		if not s.info.loop:
			s.time_elapsed = s.info.duration + 1.0
			return false
		s.time_elapsed = 0.0
	return true

## PSysTrail::update: a new point once the frame has moved 10 units.
func _update_trail(s: Spray, origin: Vector3) -> void:
	var length := origin.distance_to(s.prev_center)
	if length < 10.0 and not s.particles.is_empty():
		return
	if not _emit_time(s):
		return
	var idx := Info.index(s.time_elapsed, s.info.duration)
	s.emit_time = s.info.gap[idx]
	var p := Particle.new()
	p.pos = origin
	p.energy = s.info.energy[idx]
	p.color = s.info.color[0]
	p.weight = length
	s.total_weight += length
	s.particles.append(p)
	if s.particles.size() >= 2:
		p.dir = (s.prev_center - p.pos).normalized()
		s.particles[s.particles.size() - 2].dir = p.dir
	s.prev_center = p.pos

func _draw(s: Spray, origin: Vector3, basis_d: Basis, camera: Camera3D) -> void:
	s.mesh.clear_surfaces()
	if s.particles.is_empty():
		return
	var info := s.info
	var cam_basis := camera.global_transform.basis
	var cam_right := cam_basis.x
	var cam_up := cam_basis.y
	var cam_dir := -cam_basis.z
	if info.trail:
		if s.particles.size() >= 2:
			s.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, s.material)
			_draw_trail(s, cam_dir)
			s.mesh.surface_end()
		return
	s.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, s.material)
	var frame_scale := basis_d.get_scale().abs().x
	for p in s.particles:
		var world: Vector3
		var sz := Vector2(info.size.x * p.scale.x, info.size.y * p.scale.y)
		var dir_w := p.dir
		if info.link:
			if info.billboard == 0:
				# Only the frame's position applies; the particle's offset is in world axes.
				world = origin + MechView.G * p.pos
				dir_w = MechView.G * p.dir
			else:
				world = origin + basis_d * p.pos
				dir_w = basis_d * p.dir
				sz *= frame_scale
		else:
			world = p.pos
		var uv := _uv(info, p.lifetime)
		var corners: Array[Vector3]
		if info.billboard == 1:
			# billboard::lookat: from the particle along its direction, facing the camera.
			var height := dir_w.normalized() * sz.y if dir_w.length_squared() > 0.0 else cam_up * sz.y
			var from := world - height * info.axis_offset
			var left := height.cross(cam_dir).normalized() * sz.x * 0.5
			corners = [from - left + height, from - left, from + left + height, from + left]
		else:
			var right := cam_right
			var up := cam_up
			if info.billboard == 2:
				# Facing along the frame's z axis, screen-up as up.
				var n := (basis_d * Vector3(0, 0, 1)).normalized()
				up = (cam_up - n * cam_up.dot(n)).normalized()
				right = up.cross(n).normalized()
			var hx := right * sz.x * 0.5
			var hy := up * sz.y * 0.5
			if absf(p.rot) > 0.001:
				var axis := cam_dir if info.billboard != 2 else (basis_d * Vector3(0, 0, 1)).normalized()
				hx = hx.rotated(axis, p.rot)
				hy = hy.rotated(axis, p.rot)
			# billboard::center: corners and texture as in the original, left at u = 0.
			corners = [world - hx - hy, world - hx + hy, world + hx - hy, world + hx + hy]
		var uvs := [Vector2(uv.position.x, uv.end.y), uv.position, uv.end, Vector2(uv.end.x, uv.position.y)]
		if info.billboard == 1:
			uvs = [Vector2(uv.position.x, uv.end.y), uv.position, uv.end, Vector2(uv.end.x, uv.position.y)]
		for t in [0, 1, 2, 1, 3, 2]:
			s.mesh.surface_set_color(p.color)
			s.mesh.surface_set_uv(uvs[t])
			s.mesh.surface_add_vertex(corners[t])
	s.mesh.surface_end()

static func _uv(info: Info, lifetime: float) -> Rect2:
	if info.sprite.x <= 0:
		return Rect2(0, 0, 1, 1)
	var cells := info.sprite.x * info.sprite.y
	var i := int(lifetime * info.sprite_fps)
	i = i % cells if info.sprite.z != 0 else mini(i, cells - 1)
	var w := 1.0 / float(info.sprite.x)
	var h := 1.0 / float(info.sprite.y)
	return Rect2(float(i % info.sprite.x) * w, float(i / info.sprite.x) * h, w, h)

## PSysTrail::draw: a ribbon through the trail points, as wide as size.x x the spray's scale.
func _draw_trail(s: Spray, cam_dir: Vector3) -> void:
	var ps := s.particles
	if ps.size() < 2:
		return
	var idx := Info.index(s.time_elapsed, s.info.duration)
	var width_scale := s.info.scale[idx].y
	var points: Array[Vector3] = []
	var colors: Array[Color] = []
	var vs: Array[float] = []
	var lefts: Array[Vector3] = []
	var weight := 0.0
	points.append(ps[0].pos + ps[0].dir * s.info.size.y)
	colors.append(ps[0].color)
	vs.append(0.0)
	lefts.append(cam_dir.cross(-ps[0].dir) * s.info.size.x * ps[0].scale.x * width_scale)
	for p in ps:
		var v := weight / maxf(s.total_weight, 0.0001) * 0.3333 + 0.3333
		weight += p.weight
		points.append(p.pos)
		colors.append(p.color)
		vs.append(minf(v, 0.99))
		lefts.append(cam_dir.cross(-p.dir) * s.info.size.x * p.scale.x * width_scale)
	var last := ps[ps.size() - 1]
	points.append(last.pos - last.dir * s.info.size.y)
	colors.append(last.color)
	vs.append(1.0)
	lefts.append(lefts[lefts.size() - 1])
	for i in range(1, points.size()):
		var a0 := points[i - 1] - lefts[i - 1]
		var a1 := points[i - 1] + lefts[i - 1]
		var b0 := points[i] - lefts[i]
		var b1 := points[i] + lefts[i]
		var quad := [[a0, Vector2(0, vs[i - 1]), colors[i - 1]], [a1, Vector2(1, vs[i - 1]), colors[i - 1]],
			[b0, Vector2(0, vs[i]), colors[i]], [b1, Vector2(1, vs[i]), colors[i]]]
		for t in [0, 1, 2, 1, 3, 2]:
			s.mesh.surface_set_color(quad[t][2])
			s.mesh.surface_set_uv(quad[t][1])
			s.mesh.surface_add_vertex(quad[t][0])
