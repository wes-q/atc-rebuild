extends SceneTree
## Dev tool: drives the front end with synthetic pointer events to check it responds:
## login, character select, the main menu, options, chat and the channel box.
##   godot --path godot -s tools/ui_demo.gd -- capture=<dir>   (or --write-movie out.avi)
var t := 0.0
var step := 0
var front: FrontEnd
var steps := [
	[1.0, "name"], [1.4, "hover:accept"], [1.8, "click:accept"],
	[4.0, "hover:enter"], [4.6, "click:next"], [5.4, "click:enter"],
	[7.6, "hover:battle"], [8.6, "click:option"], [9.4, "drag:bgm"], [10.4, "click:exit_opt"],
	[11.2, "chat"], [12.0, "click:channel"], [12.8, "click:ok"], [13.6, "hover:tutorial"], [14.6, "quit"],
]
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(dt: float) -> bool:
	t += dt
	if front == null:
		for n in root.find_children("*", "", true, false):
			if n is FrontEnd:
				front = n
	if front == null or step >= steps.size():
		return false
	if t < steps[step][0]:
		return false
	var cmd: String = steps[step][1]
	step += 1
	print("UIDEMO ", snappedf(t, 0.1), " ", cmd, " page=", front.page)
	match cmd:
		"name":
			_find("id_edit").editor.text = "Wes"
		"hover:accept": _move(_center(_find("accept_button")))
		"click:accept": _click(_center(_find("accept_button")))
		"hover:enter": _move(_center(_find("enter_button")))
		"click:next": _click(_center(_find("next_button")))
		"click:enter": _click(_center(_find("enter_button")))
		"hover:battle": _move(_center(_find("battle_button")))
		"click:option": _click(_center(_find("option_button")))
		"drag:bgm":
			var c := _center(_find("control_bar"))
			_press(c)
			_move(c + Vector2(-130, 0) * front.screen.scale.x)
			_release(c + Vector2(-130, 0) * front.screen.scale.x)
		"click:exit_opt": _click(_center(_find("exit_button")))
		"chat":
			var e := _find("input_edit")
			e.editor.text = "hello from the recreation"
			e.editor.text_submitted.emit(e.editor.text)
		"click:channel": _click(_center(_find("channel_button")))
		"click:ok": _click(_center(_find("ok_button")))
		"hover:tutorial": _move(_center(_find("tutorial_button")))
		"quit": quit()
	return false
func _find(n: String) -> OriginalUI:
	for c in front.find_children(n, "", true, false):
		if c is OriginalUI and c.is_visible_in_tree():
			return c
	return null
func _center(w: OriginalUI) -> Vector2:
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
