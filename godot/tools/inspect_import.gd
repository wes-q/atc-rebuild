extends SceneTree
# Prints the imported node tree and animation tracks of a glTF. Dev tool.
#   godot --headless --path godot -s tools/inspect_import.gd -- res://path.gltf

func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var scene: Node = (load(path) as PackedScene).instantiate()
	_print_tree(scene, 0)
	var ap := scene.find_children("*", "AnimationPlayer", true, false)
	for p in ap:
		var player := p as AnimationPlayer
		for anim_name in player.get_animation_list():
			var a := player.get_animation(anim_name)
			print("ANIM ", anim_name, " len=", a.length, " tracks=", a.get_track_count(), " first=", a.track_get_path(0) if a.get_track_count() > 0 else "")
	quit()

func _print_tree(n: Node, depth: int) -> void:
	if depth > 14:
		return
	var extra := ""
	if n is Node3D:
		var t := (n as Node3D).transform
		extra = " pos=%s scale=%s" % [t.origin.snapped(Vector3.ONE * 0.01), t.basis.get_scale().snapped(Vector3.ONE * 0.001)]
	if n is MeshInstance3D:
		extra += " MESH aabb=%s" % [(n as MeshInstance3D).get_aabb()]
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_print_tree(c, depth + 1)
