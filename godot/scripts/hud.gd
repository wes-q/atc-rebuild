class_name Hud
extends CanvasLayer
## Placeholder readouts. The original HUD art comes in a later milestone.

const GAUGE_W := 260.0
const BAR_W := 210.0

var _gauge_fill: ColorRect
var _gauge_label: Label
var _low_line: ColorRect
var _warning: Label
var _info: Label
var _hp_fill: ColorRect
var _rifle_fill: ColorRect
var _target_fill: ColorRect
var _weapon_label: Label
var _marker: Label
var _status: Label
var _clock: Label
var _result: Control
var _result_title: Label
var _result_lines: Label
var _result_footer: Label
var _marker_time := 0.0
var _blink := 0.0

func _ready() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.08, 0.14, 0.75)
	panel.position = Vector2(16, 16)
	panel.size = Vector2(300, 172)
	add_child(panel)

	_label("BOOSTER", Vector2(30, 24), 13, Color(0.6, 0.85, 1))
	_bar(Vector2(30, 44), Vector2(GAUGE_W, 16), Color(0.1, 0.15, 0.25))
	_gauge_fill = _bar(Vector2(30, 44), Vector2(GAUGE_W, 16), Color(0.3, 0.8, 1.0))
	_low_line = _bar(Vector2.ZERO, Vector2(2, 20), Color(1, 0.45, 0.3))
	_gauge_label = _label("", Vector2(30, 62), 12, Color(0.85, 0.9, 1))

	_label("HP", Vector2(30, 86), 13, Color(0.55, 1.0, 0.6))
	_bar(Vector2(80, 90), Vector2(BAR_W, 10), Color(0.1, 0.22, 0.12))
	_hp_fill = _bar(Vector2(80, 90), Vector2(BAR_W, 10), Color(0.4, 0.95, 0.5))

	_weapon_label = _label("WEAPON", Vector2(30, 108), 13, Color(0.6, 0.85, 1))
	_bar(Vector2(80, 112), Vector2(BAR_W, 10), Color(0.1, 0.15, 0.25))
	_rifle_fill = _bar(Vector2(80, 112), Vector2(BAR_W, 10), Color(1.0, 0.8, 0.35))

	_label("ENEMY", Vector2(30, 130), 13, Color(1, 0.6, 0.55))
	_bar(Vector2(80, 134), Vector2(BAR_W, 10), Color(0.25, 0.1, 0.1))
	_target_fill = _bar(Vector2(80, 134), Vector2(BAR_W, 10), Color(1.0, 0.4, 0.35))
	_info = _label("", Vector2(30, 154), 12, Color(0.7, 0.75, 0.85))

	# World game_time, shown counting up as minutes, seconds and hundredths like the original.
	_clock = _label("00:00:00", Vector2.ZERO, 24, Color(0.9, 0.95, 1))
	_clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clock.position = Vector2(_clock.position.x - 50, 14)

	_warning = _label("BOOSTER LOW", Vector2.ZERO, 26, Color(1, 0.4, 0.3))
	_warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_warning.position = Vector2(_warning.position.x - 80, 52)
	_warning.visible = false

	_marker = _label("HIT!", Vector2.ZERO, 30, Color(1, 0.85, 0.3))
	_marker.visible = false

	_status = _label("", Vector2.ZERO, 14, Color(0.95, 0.85, 0.5))
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(16, _status.position.y - 48)

	var help := _label(
		"WASD or arrows: move    Mouse: aim    Left click: fire    Right click: boost    + / -: camera    Esc: menu",
		Vector2.ZERO, 12, Color(0.65, 0.7, 0.8))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(16, help.position.y - 24)

	_build_result()

func _build_result() -> void:
	_result = ColorRect.new()
	(_result as ColorRect).color = Color(0.02, 0.04, 0.09, 0.85)
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.custom_minimum_size = Vector2(620, 230)
	_result.size = Vector2(620, 230)
	_result.position -= Vector2(310, 115)
	add_child(_result)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 18)
	box.size = Vector2(572, 200)
	box.add_theme_constant_override("separation", 10)
	_result.add_child(box)
	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 44)
	box.add_child(_result_title)
	_result_lines = Label.new()
	_result_lines.add_theme_font_size_override("font_size", 15)
	_result_lines.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
	box.add_child(_result_lines)
	_result_footer = Label.new()
	_result_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_footer.add_theme_font_size_override("font_size", 13)
	_result_footer.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	box.add_child(_result_footer)
	_result.visible = false

func _label(text: String, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l

func _bar(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = size
	add_child(r)
	return r

func refresh(sim: MechSim, target: MechSim, depth: float, dt: float, status: String, round_time: float) -> void:
	visible = sim != null or status != ""
	_status.text = status
	_clock.text = clock_text(round_time)
	_blink += dt
	_marker_time = maxf(0.0, _marker_time - dt)
	_marker.visible = _marker_time > 0.0
	if sim == null:
		_warning.visible = false
		return
	_gauge_fill.size.x = GAUGE_W * sim.booster_gage / sim.energy_max
	_gauge_fill.color = Color(1, 0.45, 0.3) if sim.booster_gage <= sim.energy_low_line else Color(0.3, 0.8, 1.0)
	_low_line.position = Vector2(30 + GAUGE_W * sim.energy_low_line / sim.energy_max, 42)
	_gauge_label.text = "%4d / %d    speed %5.1f%s" % [int(sim.booster_gage), int(sim.energy_max), sim.speed(), "  BOOST" if sim.acc_flag else ""]
	_hp_fill.size.x = BAR_W * maxf(0.0, float(sim.life)) / float(sim.life_max)
	_hp_fill.color = Color(1, 0.4, 0.3) if sim.life < int(sim.life_max * 0.1) else Color(0.4, 0.95, 0.5)
	_rifle_fill.size.x = BAR_W * sim.recharge / sim.weapon.reload
	_target_fill.size.x = BAR_W * maxf(0.0, float(target.life)) / float(target.life_max) if target else 0.0
	_weapon_label.text = sim.weapon.name
	_info.text = "HP %d    enemy HP %s    camera %d" % [maxi(0, sim.life), str(maxi(0, target.life)) if target else "-", int(depth)]
	_warning.visible = sim.booster_warning_time > 0.0 and fmod(_blink, 0.3) < 0.2

## HIT! for the shooter, DAMAGE! for the one hit (Damage::PUT_HIT, Damage::PUT_DAMAGE).
func show_marker(screen_pos: Vector2, text: String) -> void:
	_marker.text = text
	_marker.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if text == "HIT!" else Color(1, 0.45, 0.35))
	_marker.position = screen_pos + Vector2(-40, -70)
	_marker_time = 0.4

func show_result(title: String, lines: Array[String], footer: String) -> void:
	_result_title.text = title
	var color := Color(0.5, 0.9, 1.0)
	if title == "YOU LOSE":
		color = Color(1, 0.5, 0.4)
	elif title == "DRAW":
		color = Color(0.9, 0.9, 0.9)
	_result_title.add_theme_color_override("font_color", color)
	_result_lines.text = "\n".join(lines)
	_result_footer.text = footer
	_result.visible = true

func hide_result() -> void:
	_result.visible = false

static func clock_text(seconds: float) -> String:
	var total := int(seconds * 100.0)
	return "%02d:%02d:%02d" % [total / 6000, (total / 100) % 60, total % 100]
