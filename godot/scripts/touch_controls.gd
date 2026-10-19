class_name TouchControls
extends CanvasLayer
## On-screen controls for phones (this recreation's own; the original was keyboard and
## mouse). Two floating sticks and a few buttons stand in for the keys:
## - Left stick: move along the screen axes in eight directions, like WASD.
## - Right stick: aim, turning the mech toward the drag. Pushed past a third of the way it
##   fires, holding the trigger for weapons that use a held button (streams, the bow's draw,
##   the Cluster Cannon) and clicking about eight times a second for the rest.
## - Buttons: BOOST (the right mouse button, held), weapon slots 1 to 4, GUARD (Space),
##   LOCK (F), PLAYERS (Tab), MENU (Esc), and between rounds START for the host and TEAM in
##   team battle. BOOST is the largest, beside GUARD under the right thumb, so the left thumb
##   keeps steering while it is held.
## A command combo is a flick of the left stick toward or away from your facing, then fire.
## Sizes are in canvas units (the 768-high base), so they hold on every screen.

signal menu_pressed
signal start_pressed
signal team_pressed

const STICK_RADIUS := 80.0
const KNOB_RADIUS := 34.0
const BUTTON_RADIUS := 34.0
const BOOST_RADIUS := 46.0
const DEAD_ZONE := 0.25
const FIRE_AT := 0.35
const AXIS_AT := 0.38 ## a stick axis counts once past this share of the direction
const CLICK_PERIOD := 0.12

# Read by the game every frame.
var move := Vector2.ZERO ## screen space, length 0..1
var aim := Vector2.ZERO ## screen space unit vector, zero before the first aim
var firing := false
var weapon_key := 0
var guard := false
var boost := false
var lock := false
var players := false
# Set by the game: whether START and TEAM are offered right now.
var show_start := false
var show_team := false

var _pad: Control
var _fingers := {} ## touch index -> "move", "aim" or a button name
var _move_origin := Vector2.ZERO
var _move_at := Vector2.ZERO
var _aim_origin := Vector2.ZERO
var _aim_at := Vector2.ZERO
var _click_time := 0.0

func _ready() -> void:
	layer = 5
	_pad = Control.new()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.draw.connect(_draw_pad)
	add_child(_pad)

func _process(dt: float) -> void:
	_click_time += dt
	_pad.queue_redraw()

## The left stick as the four movement keys, and the BOOST button.
func keys() -> Dictionary:
	var length := move.length()
	var d := move.normalized() if length > DEAD_ZONE else Vector2.ZERO
	return {
		"left": d.x < -AXIS_AT, "right": d.x > AXIS_AT,
		"up": d.y < -AXIS_AT, "down": d.y > AXIS_AT,
		"boost": boost,
	}

## The fire button this frame: held for weapons that use holding, clicked for the rest.
func fire_held(hold_weapon: bool) -> bool:
	if not firing:
		return false
	if hold_weapon:
		return true
	return fmod(_click_time, CLICK_PERIOD) < CLICK_PERIOD * 0.5

## Aim on the battle plane: screen right is +x, screen up is +y (the camera looks straight
## down with the plane's +y at the top).
func plane_aim() -> Vector2:
	return Vector2(aim.x, -aim.y)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		match _fingers.get(d.index, ""):
			"move":
				_move_at = d.position
				move = _stick_value(_move_origin, _move_at)
			"aim":
				_aim_at = d.position
				_update_aim()

func _touch_down(index: int, at: Vector2) -> void:
	for b in _buttons():
		if at.distance_to(b[1]) <= _radius(b[0]) * 1.15:
			_fingers[index] = b[0]
			_button_down(b[0])
			_handled()
			return
	var size := _pad.size
	if at.y < size.y * 0.25:
		return
	if at.x < size.x * 0.5 and not _fingers.values().has("move"):
		_fingers[index] = "move"
		_move_origin = at
		_move_at = at
		move = Vector2.ZERO
		_handled()
	elif at.x >= size.x * 0.5 and not _fingers.values().has("aim"):
		_fingers[index] = "aim"
		_aim_origin = at
		_aim_at = at
		firing = false
		_handled()

## The touch is the controls'; the game and the menu do not see it.
func _handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()

func _touch_up(index: int) -> void:
	var role: String = _fingers.get(index, "")
	_fingers.erase(index)
	match role:
		"move":
			move = Vector2.ZERO
		"aim":
			firing = false
		"":
			pass
		_:
			_button_up(role)

func _update_aim() -> void:
	var v := _stick_value(_aim_origin, _aim_at)
	if v.length() > 0.1:
		aim = v.normalized()
	firing = v.length() >= FIRE_AT

static func _stick_value(origin: Vector2, at: Vector2) -> Vector2:
	return (at - origin).limit_length(STICK_RADIUS) / STICK_RADIUS

func _button_down(name: String) -> void:
	match name:
		"1", "2", "3", "4":
			weapon_key = int(name)
		"GUARD":
			guard = true
		"BOOST":
			boost = true
		"LOCK":
			lock = true
		"PLAYERS":
			players = true
		"MENU":
			menu_pressed.emit()
		"START":
			start_pressed.emit()
		"TEAM":
			team_pressed.emit()

func _button_up(name: String) -> void:
	match name:
		"1", "2", "3", "4":
			weapon_key = 0
		"GUARD":
			guard = false
		"BOOST":
			boost = false
		"LOCK":
			lock = false
		"PLAYERS":
			players = false

## [name, centre] for each button shown now. The weapon row and GUARD and LOCK sit above the
## right stick, PLAYERS on the left and MENU in the top-right corner, START and TEAM at the
## top centre.
func _buttons() -> Array:
	var w := _pad.size.x
	var h := _pad.size.y
	var out := []
	for i in 4:
		out.append([str(i + 1), Vector2(w - 290 + 72 * i, h - 330)])
	out.append(["LOCK", Vector2(w - 360, h - 250)])
	out.append(["GUARD", Vector2(w - 360, h - 160)])
	out.append(["BOOST", Vector2(w - 290, h - 66)])
	out.append(["PLAYERS", Vector2(56, 250)])
	out.append(["MENU", Vector2(w - 56, 56)])
	if show_start:
		out.append(["START", Vector2(w * 0.5 - 60, 120)])
	if show_team:
		out.append(["TEAM", Vector2(w * 0.5 + 60, 120)])
	return out

func _radius(name: String) -> float:
	return BOOST_RADIUS if name == "BOOST" else BUTTON_RADIUS

func _draw_pad() -> void:
	var font := ThemeDB.fallback_font
	var faint := Color(1, 1, 1, 0.12)
	var line := Color(1, 1, 1, 0.35)
	var w := _pad.size.x
	var h := _pad.size.y
	# Sticks: where the thumb went down, or a resting hint in each lower corner.
	var move_on := _fingers.values().has("move")
	var aim_on := _fingers.values().has("aim")
	var left_base := _move_origin if move_on else Vector2(150, h - 150)
	var right_base := _aim_origin if aim_on else Vector2(w - 150, h - 150)
	for s in [[left_base, _move_at if move_on else left_base, move_on, keys()["boost"]],
			[right_base, _aim_at if aim_on else right_base, aim_on, firing]]:
		var base: Vector2 = s[0]
		var knob: Vector2 = base + (s[1] - base).limit_length(STICK_RADIUS)
		_pad.draw_circle(base, STICK_RADIUS, faint)
		_pad.draw_arc(base, STICK_RADIUS, 0, TAU, 48, line, 2.0)
		var knob_color := Color(1, 0.75, 0.3, 0.55) if s[3] else Color(1, 1, 1, 0.3 if s[2] else 0.18)
		_pad.draw_circle(knob, KNOB_RADIUS, knob_color)
	for b in _buttons():
		var held: bool = _fingers.values().has(b[0])
		var name: String = b[0]
		var active := held or (name == str(weapon_key))
		var r := _radius(name)
		var lit := Color(1, 0.75, 0.3, 0.55) if name == "BOOST" else Color(0.3, 0.6, 1, 0.45)
		_pad.draw_circle(b[1], r, lit if active else Color(0, 0, 0, 0.35))
		_pad.draw_arc(b[1], r, 0, TAU, 40, line, 2.0)
		var size := 22 if name.length() == 1 else 12
		var text_w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_pad.draw_string(font, b[1] + Vector2(-text_w * 0.5, size * 0.35), name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.85))
