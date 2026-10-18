extends SceneTree
## Dev tool: renders the Zeid at several facing angles, with and without the import flip,
## seen from the game camera, and saves a PNG. Needs a window (not headless).
##   godot --path godot -s tools/render_poses.gd -- out.png

const ANGLES := [0, 45, 90, 135, 180, 225, 270, 315]

var out := ""
var frames := 0

func _setup() -> void:
	out = OS.get_cmdline_user_args()[0]
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.14, 0.22)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 30, 0)
	world.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = Original.CAMERA_FOV
	world.add_child(cam)
	cam.position = Vector3(0, 620, -110)
	cam.look_at(Vector3(0, 0, -110), Vector3(0, 0, -1))

	for row in 2:
		MechView.flip_import_z = row == 0
		for c in ANGLES.size():
			var v := MechView.new()
			world.add_child(v)
			var plane := Vector2((c - 3.5) * 62.0, 160.0 - row * 100.0)
			v.place(plane, ANGLES[c])
			v.player.seek(0.0, true)
			var label := Label3D.new()
			label.text = "%d%s" % [ANGLES[c], " flip" if row == 0 else ""]
			label.pixel_size = 1.0
			label.font_size = 9
			label.position = Original.to_godot(plane + Vector2(0, -38)) + Vector3(0, 10, 0)
			label.rotation_degrees = Vector3(-90, 0, 0)
			world.add_child(label)
			if c == 0:
				print("row ", row, " world aabb ", _aabb(v))

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		_setup()
	if frames == 10:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		return true
	return false

func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
