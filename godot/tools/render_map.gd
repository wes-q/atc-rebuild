extends SceneTree
## Dev tool: renders an arena seen from the game camera's direction, high enough to show
## the whole bounds, with the collision walls (red), the bounds rectangle (yellow) and the
## start points (green) drawn over it. Needs a window (not headless).
##   godot --path godot -s tools/render_map.gd -- <map id> out.png [depth] [x] [y] [noverlay]

var out := ""
var frames := 0

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	var map := BattleMap.load_map(args[0])
	out = args[1]
	var world := Node3D.new()
	root.add_child(world)
	var built := BattleWorld.build(world, 500.0)
	BattleWorld.build_map(world, map, built.env, built.sun)
	var cam: Camera3D = built.camera
	var centre := Vector2((map.x_min + map.x_max) * 0.5, (map.y_min + map.y_max) * 0.5)
	var depth := maxf(map.x_max - map.x_min, map.y_max - map.y_min) * 1.25
	if args.size() > 2:
		depth = float(args[2])
	if args.size() > 4:
		centre = Vector2(float(args[3]), float(args[4]))
	cam.position = Original.to_godot(centre) + Vector3(0, depth, 0)
	cam.look_at(Original.to_godot(centre), Vector3(0, 0, -1))
	var sky := world.find_child("Sky", true, false) as Node3D
	if sky:
		BattleWorld.place_sky(sky, cam)
	if args.has("nooverlay"):
		return

	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var tris := _triangles(map)
	for t in tris:
		for k in 3:
			var a: Vector3 = t[k]
			var b: Vector3 = t[(k + 1) % 3]
			im.surface_set_color(Color(1, 0.2, 0.2))
			im.surface_add_vertex(Vector3(a.x, 2, -a.z))
			im.surface_set_color(Color(1, 0.2, 0.2))
			im.surface_add_vertex(Vector3(b.x, 2, -b.z))
	var corners := [Vector2(map.x_min, map.y_min), Vector2(map.x_max, map.y_min), Vector2(map.x_max, map.y_max), Vector2(map.x_min, map.y_max)]
	for k in 4:
		im.surface_set_color(Color(1, 0.9, 0.2))
		im.surface_add_vertex(Original.to_godot(corners[k]) + Vector3(0, 2, 0))
		im.surface_set_color(Color(1, 0.9, 0.2))
		im.surface_add_vertex(Original.to_godot(corners[(k + 1) % 4]) + Vector3(0, 2, 0))
	for s in map.spawns:
		for d in [Vector2(-20, -20), Vector2(20, -20)]:
			im.surface_set_color(Color(0.3, 1, 0.4))
			im.surface_add_vertex(Original.to_godot(s + d) + Vector3(0, 2, 0))
			im.surface_set_color(Color(0.3, 1, 0.4))
			im.surface_add_vertex(Original.to_godot(s - d) + Vector3(0, 2, 0))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	world.add_child(mi)
	print("%s: %d wall triangles, bounds x %d..%d y %d..%d" % [map.id, tris.size(), map.x_min, map.x_max, map.y_min, map.y_max])

func _triangles(map: BattleMap) -> Array:
	var f := FileAccess.open(map.folder + "map.json", FileAccess.READ)
	var flat: Array = JSON.parse_string(f.get_as_text())["collision"]
	var out_tris := []
	for i in range(0, flat.size() - 8, 9):
		out_tris.append([Vector3(flat[i], flat[i + 1], flat[i + 2]), Vector3(flat[i + 3], flat[i + 4], flat[i + 5]), Vector3(flat[i + 6], flat[i + 7], flat[i + 8])])
	return out_tris

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		_setup()
	if frames == 20:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		return true
	return false
