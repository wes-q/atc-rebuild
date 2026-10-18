extends SceneTree
## Dev tool: drives the room list and the game room with synthetic pointer events, as a
## player joining a room another copy hosts on this machine:
##   godot --headless --path godot -- host room="Friday night" name=Kite players=2 autopilot &
##   godot --path godot -s tools/room_demo.gd -- front=main   (add --write-movie out.avi)
var t := 0.0
var step := 0
var front: FrontEnd
var _start_us := Time.get_ticks_usec()
var steps := [
	[1.0, "hover:battle"], [2.0, "click:battle"], [3.6, "hover:row"], [4.6, "click:create"],
	[5.6, "click:arrow_button"], [6.4, "click:team_battle_button"], [7.4, "click:cancel_button"],
	[8.2, "click:row"], [8.5, "click:row"], [10.6, "chat"], [40.0, "quit"],
]
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(dt: float) -> bool:
	t += dt
	# --write-movie runs ahead of the clock; the host it joins runs in real time, so wait for
	# the clock to catch up with the movie.
	var ahead := t - (Time.get_ticks_usec() - _start_us) / 1000000.0
	if ahead > 0.0:
		OS.delay_usec(int(ahead * 1000000.0))
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
	print("ROOMDEMO ", snappedf(t, 0.1), " ", cmd, " page=", front.page, " shown=", front.visible)
	match cmd:
		"hover:battle": _move(_center(_find("battle_button")))
		"click:battle": _click(_center(_find("battle_button")))
		"hover:row": _move(_center(_row()))
		"click:create": _click(_center(_find("create_game_button")))
		"click:row": _click(_center(_row()))
		"chat":
			var e := _find("input_chat_edit")
			e.editor.text = "ready when you are"
			e.editor.text_submitted.emit(e.editor.text)
		"quit": quit()
		_:
			if cmd.begins_with("click:"):
				_click(_center(_find(cmd.trim_prefix("click:"))))
	return false
func _row() -> OriginalUI:
	var rows := front._list_rows()
	return rows.get_child(0) as OriginalUI if rows and rows.get_child_count() > 0 else null
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
func _click(p: Vector2) -> void:
	_move(p)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)
