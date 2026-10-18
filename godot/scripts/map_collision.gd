class_name MapCollision
extends RefCounted
## The map's wall triangles, as rc_map builds them into its collision model: steep faces of
## the frames that reach the play plane, in original world units (x, height, plane y). The
## original tested a sphere (mechs) and a ray (bullets) against them every frame. Triangles
## are bucketed on a plane grid so each test only looks at nearby ones.

const CELL := 64.0

var _tris: Array[PackedVector3Array] = []
var _grid := {}

func _init(flat: Array = []) -> void:
	for i in range(0, flat.size() - 8, 9):
		var t := PackedVector3Array([
			Vector3(flat[i], flat[i + 1], flat[i + 2]),
			Vector3(flat[i + 3], flat[i + 4], flat[i + 5]),
			Vector3(flat[i + 6], flat[i + 7], flat[i + 8])])
		add_triangle(t)

func add_triangle(t: PackedVector3Array) -> void:
	var index := _tris.size()
	_tris.append(t)
	var lo := Vector2(minf(t[0].x, minf(t[1].x, t[2].x)), minf(t[0].z, minf(t[1].z, t[2].z)))
	var hi := Vector2(maxf(t[0].x, maxf(t[1].x, t[2].x)), maxf(t[0].z, maxf(t[1].z, t[2].z)))
	for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
		for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			var key := Vector2i(cx, cy)
			if not _grid.has(key):
				_grid[key] = PackedInt32Array()
			_grid[key].append(index)

func triangle_count() -> int:
	return _tris.size()

func _nearby(lo: Vector2, hi: Vector2) -> Dictionary:
	var seen := {}
	for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
		for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			var key := Vector2i(cx, cy)
			if _grid.has(key):
				for i in _grid[key]:
					seen[i] = true
	return seen

## Sphere at a plane point (height 0) against the walls: Opcode sphereCollision in
## rc_map::update. Returns {} when clear, otherwise the contact "point" and the wall "normal"
## on the plane, worked out like the original (cross(v2 - v1, v0 - v1), height dropped). The
## normal is turned to face the sphere so a push always moves it out.
func sphere_contact(center: Vector2, radius: float) -> Dictionary:
	var c := Vector3(center.x, 0.0, center.y)
	var best := {}
	var best_d := radius * radius
	for i in _nearby(center - Vector2.ONE * radius, center + Vector2.ONE * radius):
		var t: PackedVector3Array = _tris[i]
		var p := closest_point_on_triangle(c, t[0], t[1], t[2])
		var d := c.distance_squared_to(p)
		if d > best_d:
			continue
		var n := (t[2] - t[1]).cross(t[0] - t[1])
		var flat := Vector2(n.x, n.z)
		if flat.length_squared() < 1e-9:
			continue
		flat = flat.normalized()
		var away := Vector2(c.x - p.x, c.z - p.z)
		if away.length_squared() > 1e-9 and flat.dot(away) < 0.0:
			flat = -flat
		best_d = d
		best = {"point": Vector2(p.x, p.z), "normal": flat}
	return best

## Segment on the plane against the walls (rc_map::is_crashed_with_object, a ray test).
## Returns the first crossing point from a toward b, or null.
func segment_hit(a: Vector2, b: Vector2) -> Variant:
	var o := Vector3(a.x, 0.0, a.y)
	var d := Vector3(b.x - a.x, 0.0, b.y - a.y)
	var best_t := 2.0
	for i in _nearby(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(maxf(a.x, b.x), maxf(a.y, b.y))):
		var t: PackedVector3Array = _tris[i]
		var hit: Variant = Geometry3D.ray_intersects_triangle(o, d, t[0], t[1], t[2])
		if hit == null:
			continue
		var along := (hit as Vector3 - o).dot(d) / maxf(d.length_squared(), 1e-9)
		if along >= 0.0 and along <= 1.0 and along < best_t:
			best_t = along
	if best_t > 1.0:
		return null
	return a.lerp(b, best_t)

## Ericson, Real-Time Collision Detection, 5.1.5.
static func closest_point_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)
