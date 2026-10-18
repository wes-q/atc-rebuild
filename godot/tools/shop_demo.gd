extends SceneTree
## Dev tool: drives the shop page with synthetic pointer events: choose a weapon in the
## inventory, EQUIP it, try it in the viewer, turn the robot, then EXIT.
##   godot --path godot -s tools/shop_demo.gd -- front=main profile=demo   (add
##   --write-movie out.avi, or shot=<dir> to save a picture at each step)
var t := 0.0
var step := 0
var front: FrontEnd
var shots := ""
var steps := [
	[1.0, "hover:shop_button"], [1.8, "click:shop_button"], [3.4, "shot"], [3.8, "hover:list"], [5.2, "shot"],
	[5.6, "click:list"], [6.4, "hover:inven"], [7.6, "shot"], [8.0, "click:inven"], [9.0, "click:equip_button"],
	[9.8, "shot"], [10.2, "click:ani_button"], [11.4, "shot"], [11.8, "press:right_rotate_button"], [14.0, "release"],
	[14.4, "shot"], [14.8, "wheel"], [15.6, "click:exit_button"], [17.0, "shot"], [17.4, "quit"],
]
var _held := Vector2.ZERO
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shots = a.trim_prefix("shot=")
	change_scene_to_file("res://scenes/main.tscn")
func _process(dt: float) -> bool:
	t += dt
	if front == null:
		for n in root.find_children("*", "", true, false):
			if n is FrontEnd:
				front = n
	if front == null or step >= steps.size() or t < steps[step][0]:
		return false
	var cmd: String = steps[step][1]
	step += 1
	print("SHOPDEMO ", snappedf(t, 0.1), " ", cmd, " page=", front.page)
	match cmd:
		"shot":
			if shots != "":
				root.get_viewport().get_texture().get_image().save_png("%s/s%02d.png" % [shots, step])
		"hover:list": _move(_center(_list_row(1)))
		"click:list": _click(_center(_list_row(1)))
		"hover:inven": _move(_center(_cell(0)))
		"click:inven": _click(_center(_cell(0)))
		"release": _release(_held)
		"wheel":
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_WHEEL_DOWN
			e.pressed = true
			e.position = _center(_list_row(0))
			Input.parse_input_event(e)
		"quit": quit()
		_:
			if cmd.begins_with("click:"):
				_click(_center(_find(cmd.trim_prefix("click:"))))
			elif cmd.begins_with("press:"):
				_held = _center(_find(cmd.trim_prefix("press:")))
				_press(_held)
	return false
func _cell(i: int) -> OriginalUI:
	var grid := front.shop.root.w("inventory").w("Inven_ItemList")
	return grid.get_child(i) as OriginalUI if grid.get_child_count() > i else null
func _list_row(i: int) -> OriginalUI:
	var list := front.shop.root.w("item_list").w("ItemList")
	return list.get_child(i) as OriginalUI if list.get_child_count() > i else null
func _find(n: String) -> OriginalUI:
	for c in front.find_children(n, "", true, false):
		if c is OriginalUI and c.is_visible_in_tree():
			return c
	return null
func _center(w: OriginalUI) -> Vector2:
	if w == null:
		return Vector2.ZERO
	return front.screen.position + (front._page_pos(w) + w._hit_size() * 0.5) * front.screen.scale
func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)
func _press(p: Vector2) -> void:
	_move(p)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)
func _release(p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)
func _click(p: Vector2) -> void:
	_press(p)
	_release(p)
