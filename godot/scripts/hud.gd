class_name Hud
extends CanvasLayer
## Minimal readouts for milestone 1. The original HUD art comes in a later milestone.

var _gauge_fill: ColorRect
var _gauge_label: Label
var _low_line: ColorRect
var _warning: Label
var _info: Label
var _rifle_fill: ColorRect
var _target_fill: ColorRect
var _hits: Label
var _weapon_label: Label
var _status: Label
var _panel_nodes: Array[CanvasItem] = []
var _hit_time := 0.0
var _blink := 0.0

const GAUGE_W := 260.0

func _ready() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.08, 0.14, 0.75)
	panel.position = Vector2(16, 16)
	panel.size = Vector2(300, 150)
	add_child(panel)

	_label("BOOSTER", Vector2(30, 24), 13, Color(0.6, 0.85, 1))
	var back := ColorRect.new()
	back.color = Color(0.1, 0.15, 0.25)
	back.position = Vector2(30, 44)
	back.size = Vector2(GAUGE_W, 16)
	add_child(back)
	_gauge_fill = ColorRect.new()
	_gauge_fill.color = Color(0.3, 0.8, 1.0)
	_gauge_fill.position = back.position
	_gauge_fill.size = back.size
	add_child(_gauge_fill)
	_low_line = ColorRect.new()
	_low_line.color = Color(1, 0.45, 0.3)
	_low_line.size = Vector2(2, 20)
	add_child(_low_line)
	_gauge_label = _label("", Vector2(30, 62), 12, Color(0.85, 0.9, 1))

	_weapon_label = _label("WEAPON", Vector2(30, 86), 13, Color(0.6, 0.85, 1))
	var rback := ColorRect.new()
	rback.color = Color(0.1, 0.15, 0.25)
	rback.position = Vector2(80, 90)
	rback.size = Vector2(210, 10)
	add_child(rback)
	_rifle_fill = ColorRect.new()
	_rifle_fill.color = Color(1.0, 0.8, 0.35)
	_rifle_fill.position = rback.position
	_rifle_fill.size = rback.size
	add_child(_rifle_fill)

	_label("ENEMY", Vector2(30, 110), 13, Color(1, 0.6, 0.55))
	var tback := ColorRect.new()
	tback.color = Color(0.25, 0.1, 0.1)
	tback.position = Vector2(80, 114)
	tback.size = Vector2(210, 10)
	add_child(tback)
	_target_fill = ColorRect.new()
	_target_fill.color = Color(1.0, 0.4, 0.35)
	_target_fill.position = tback.position
	_target_fill.size = tback.size
	add_child(_target_fill)
	_info = _label("", Vector2(30, 132), 12, Color(0.7, 0.75, 0.85))

	_warning = _label("BOOSTER LOW", Vector2(0, 0), 26, Color(1, 0.4, 0.3))
	_warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_warning.position.y = 24
	_warning.visible = false

	_hits = _label("HIT!", Vector2.ZERO, 30, Color(1, 0.85, 0.3))
	_hits.visible = false

	_status = _label("", Vector2.ZERO, 14, Color(0.95, 0.85, 0.5))
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(16, _status.position.y - 48)

	var help := _label(
		"WASD or arrows: move    Mouse: aim    Left click: fire    Right click: boost    + / -: camera    Esc: menu",
		Vector2.ZERO, 12, Color(0.65, 0.7, 0.8))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(16, help.position.y - 24)

func _label(text: String, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l

func refresh(sim: MechSim, target: MechSim, depth: float, dt: float, status: String) -> void:
	visible = sim != null or status != ""
	_status.text = status
	_blink += dt
	_hit_time = maxf(0.0, _hit_time - dt)
	_hits.visible = _hit_time > 0.0
	if sim == null:
		_warning.visible = false
		return
	var g := sim.booster_gage / sim.energy_max
	_gauge_fill.size.x = GAUGE_W * g
	_gauge_fill.color = Color(1, 0.45, 0.3) if sim.booster_gage <= sim.energy_low_line else Color(0.3, 0.8, 1.0)
	_low_line.position = Vector2(30 + GAUGE_W * sim.energy_low_line / sim.energy_max, 42)
	_gauge_label.text = "%4d / %d    speed %5.1f%s" % [int(sim.booster_gage), int(sim.energy_max), sim.speed(), "  BOOST" if sim.acc_flag else ""]
	_rifle_fill.size.x = 210.0 * sim.recharge / sim.weapon.reload
	_target_fill.size.x = 210.0 * float(target.life) / float(target.life_max) if target else 0.0
	_weapon_label.text = sim.weapon.name
	_info.text = "HP %d    enemy HP %s    camera %d" % [sim.life, str(target.life) if target else "-", int(depth)]
	_warning.visible = sim.booster_warning_time > 0.0 and fmod(_blink, 0.3) < 0.2

func show_hit(screen_pos: Vector2) -> void:
	_hits.position = screen_pos + Vector2(-24, -60)
	_hit_time = 0.4
