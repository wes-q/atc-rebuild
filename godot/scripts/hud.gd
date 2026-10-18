class_name Hud
extends CanvasLayer
## The original battle HUD. page_game_fight:create() builds these dialogs from the original
## window tables and art, and the update functions below are ports of the Lua ones the
## client called every frame (OnBoosterUpdate, OnTimeUpdate, OnWeaponUpdate,
## ON_self_user_state_wnd, ON_user_state_wnd). The radar dots, off-screen markers, name
## tags and low-health warning were drawn by the C++ Radar class; those are ported in
## _draw_overlay. Everything is laid out on the original 800x600 screen and scaled up.
## The status line, controls line and results panel are this recreation's own.

const SCREEN := Vector2(800, 600)
## Radar::init
const RADAR_POS := Vector2(680, 74)
const RADAR_SCALE := 0.08
const RADAR_HALF := Vector2(80, 60)
const HOOD_CENTRE := Vector2(400, 300)
const HOOD_RANGE := 180.0
## Team 0 colour for names and markers (Radar::render_name). Every free-for-all player is team 0.

## Another mech as the HUD needs it.
class Tracked:
	var id := 0
	var pos := Vector2.ZERO
	var name := ""
	var alive := true
	var team := Room.NONE
	var hood_pos := Vector2.ZERO
	var hood_set := false

var screen: Control
var booster: OriginalUI
var playtime: OriginalUI
var weapon: OriginalUI
var self_state: OriginalUI
var user_state: OriginalUI
var focus: OriginalUI
var radar: OriginalUI
var guard_gage: OriginalUI
## Tab: every player's face, HP and name (res_dlg_game_fight_playercondition).
var play_condition: OriginalUI
var team_mode := false
var my_team := Room.NONE
## [slot, robot face 1-5, HP 0..1, name, alive] for everyone in the match.
var board: Array = []
var show_board := false
var _board_w := {} ## slot -> shown bar width
## Radar::hide_time: an EMP hit blanks the enemy blips, edge markers and lock-on marks.
var jam_time := 0.0
var _gauge_w := {} ## bar name -> shown width, easing to the target
var overlay: Node2D

## On a touch screen the help line describes the on-screen controls instead of the keys.
var touch_help := false:
	set(v):
		touch_help = v
		if _help:
			_help.text = TOUCH_HELP if v else KEY_HELP
			# The buttons carry their own labels; the line would sit over the right stick.
			_help.visible = not v
const KEY_HELP := "WASD: move   Mouse: aim   Left: fire   Right: boost   Space: guard   Tab: players   +/-: camera   M: sound   Esc: menu"
const TOUCH_HELP := "Left stick: move, rim boosts   Right stick: aim, push to fire   Combo: flick toward your facing, then fire"
var _status: Label
var _help: Label
var _result: Control
var _result_title: Label
var _result_lines: Label
var _result_footer: Label

var _play_time_cs := 0.0
var _user_state_time := 0.0
var _spattack_alpha := 255.0
var _tracked: Dictionary = {}
var _me := Vector2.ZERO
var _me_alive := false
var _me_low := false
var _camera: Camera3D
var _nearest_id := 0
## Lock-on (Radar::render_lock_on_system): the current target, other candidates, and whether
## another player has locked onto you.
var lock_target_pos: Variant = null
var lock_candidates: Array[Vector2] = []
var locked_on_me := false
var _weapons_set := ""

func _ready() -> void:
	screen = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	if OriginalUI.available():
		_build_original()
	overlay = Node2D.new()
	overlay.draw.connect(_draw_overlay)
	screen.add_child(overlay)

	_status = _label(14, Color(0.95, 0.85, 0.5))
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position.y -= 44
	_status.position.x -= 12
	_help = _label(12, Color(0.65, 0.7, 0.8))
	_help.text = TOUCH_HELP if touch_help else KEY_HELP
	_help.visible = not touch_help
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help.position.y -= 22
	_help.position.x -= 12
	_build_result()
	get_viewport().size_changed.connect(_fit)
	_fit()

## page_game_fight:create()
func _build_original() -> void:
	focus = OriginalUI.create("res_dlg_game_fight_focus")
	radar = OriginalUI.create("res_dlg_game_fight_reader_show_area")
	weapon = OriginalUI.create("res_dlg_game_fight_weapon_dialog")
	playtime = OriginalUI.create("res_dlg_game_fight_playtime")
	booster = OriginalUI.create("res_dlg_game_fight_booster_base")
	user_state = OriginalUI.create("res_dlg_game_fight_user_state")
	self_state = OriginalUI.create("res_dlg_game_fight_self_user_state")
	guard_gage = OriginalUI.create_child("res_dlg_game_fight_background", "guard_gage")
	play_condition = OriginalUI.create("res_dlg_game_fight_playercondition")
	play_condition.visible = false
	# Added in create()'s order, then sorted by order (weapon, user_state and focus are 0).
	for d in [guard_gage, weapon, user_state, focus, self_state, radar, playtime, booster, play_condition]:
		screen.add_child(d)
	user_state.visible = false
	playtime.pos_set(334, 10)
	# The C++ Radar draws the dots itself; the Lua slot windows stay hidden.
	for team in ["ourteam", "enemy"]:
		var group := radar.w(team)
		if group:
			for c in group.get_children():
				c.visible = false
	# item_slot_seleted_all_hide(), then the weapon panel for the SR-3 in the second slot.
	for i in range(1, 7):
		_hide(weapon.w("item_slot_%d_img_selete" % i))

func _fit() -> void:
	var k := get_viewport().get_visible_rect().size / SCREEN
	var s := minf(k.x, k.y)
	screen.scale = Vector2(s, s)
	screen.position = (get_viewport().get_visible_rect().size - SCREEN * s) * 0.5

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	add_child(l)
	return l

static func _hide(win: OriginalUI) -> void:
	if win:
		win.visible = false

# --- Per frame --------------------------------------------------------------------------

## Everything the HUD shows for this frame. others: Array of [id, plane pos, name, alive].
func refresh(sim: MechSim, me_name: String, status: String, round_time: float, camera: Camera3D, others: Array, nearest_id: int, dt: float) -> void:
	_status.text = status
	_camera = camera
	_nearest_id = nearest_id
	var show_battle := sim != null
	for d in [booster, playtime, weapon, self_state, focus, radar]:
		if d:
			d.visible = show_battle
	if guard_gage:
		guard_gage.visible = show_battle and sim.shield != null and not sim.is_dead_complete
	jam_time = maxf(0.0, jam_time - dt) if show_battle else 0.0
	if not show_battle:
		if user_state:
			user_state.visible = false
		_tracked.clear()
		overlay.queue_redraw()
		return
	_me = sim.pos
	_me_alive = not sim.is_dead_complete
	_me_low = sim.life > 0 and sim.life < sim.life_max / 10
	var seen := {}
	for o in others:
		var id: int = o[0]
		seen[id] = true
		if not _tracked.has(id):
			_tracked[id] = Tracked.new()
		var t: Tracked = _tracked[id]
		t.id = id
		t.pos = o[1]
		t.name = o[2]
		t.alive = o[3]
		t.team = o[4] if o.size() > 4 else Room.NONE
	for id in _tracked.keys():
		if not seen.has(id):
			_tracked.erase(id)
	if booster == null:
		overlay.queue_redraw()
		return
	if _weapons_set != sim.body + str(sim.slots.size()):
		_weapons_set = sim.body + str(sim.slots.size())
		var ids: Array = []
		for sl in sim.slots:
			ids.append(sl.data.id)
		_initial_weapons(ids)
	_update_board(dt)
	time_update(round_time)
	booster_update(int(sim.booster_gage), int(sim.energy_max), int(sim.energy_low_line))
	self_user_state(Bodies.face(sim.body), me_name, maxi(0, sim.life), 1)
	weapon_update(sim.weapon.id, sim.recharge / sim.weapon.reload, sim.weapon.name, sim.weapon_index)
	# get_my_ammo_number: -1 (no limit) shows as 0, like the ammo per load.
	var slot: MechSim.Slot = sim.slots[sim.weapon_index]
	weapon_number_show(maxi(0, slot.ammo))
	weapon_full_number_show(maxi(0, slot.data.ammo))
	if guard_gage.visible:
		# rcPlayerManager::updateguard every frame: the gauge under your mech, 80 x 0.3 + 5
		# units down the plane and 40 pixels left (the name sits the same distance up).
		var at := _to_screen(sim.pos, -(80.0 * Original.SCALE + 5.0))
		guard_gage_update(sim.durability / sim.shield_max, float(maxi(0, sim.life)) / float(sim.life_max), 0.0, at.x - 40.0, at.y, dt)
	if _user_state_time > 0.0:
		_user_state_time -= dt
		if _user_state_time <= 0.0:
			user_state.visible = false
	# Radar::update: alpha falls 200 a second, then jumps back to full.
	_spattack_alpha -= 200.0 * dt
	if _spattack_alpha < 0.0:
		_spattack_alpha = 255.0
	overlay.queue_redraw()

## ONguard_gageUpdate(guard_gage, hp_gage, bit_gage, x, y): each bar 65 x value wide, eased
## over 0.5 s (animate_scale; the easing curve is inferred as linear).
func guard_gage_update(guard: float, hp: float, bit: float, x: float, y: float, dt: float) -> void:
	guard_gage.pos_set(x, y)
	var values := {"guard": guard, "hp": hp, "bit": bit}
	for bar: String in values:
		var target := 65.0 * clampf(values[bar], 0.0, 1.0)
		var cur: float = _gauge_w.get(bar, target)
		cur = move_toward(cur, target, maxf(absf(target - cur), 1.0) / 0.5 * dt)
		_gauge_w[bar] = cur
		var win := guard_gage.w(bar)
		if win:
			win.size_set(cur, 3)

## EnableUserViewInfo while Tab is held, DisableUserViewInfo when it is let go. The base
## shows the single or team layout; each slot shows the robot face (greyed when knocked out),
## an HP bar coloured by what is left (10% and under, 66% and under, more) eased over 0.5 s,
## and the name.
func _update_board(dt: float) -> void:
	if play_condition == null:
		return
	play_condition.visible = show_board
	if not show_board:
		return
	play_condition.texture_switch(2 if team_mode else 1)
	var filled := {}
	for e in board:
		var slot: int = e[0]
		var win := play_condition.w("slot%d" % (slot % Room.SIZE + 1))
		if win == null:
			continue
		filled[slot] = true
		var face := win.w("char_face")
		face.visible = true
		# The list opens with an empty entry, then five live faces, then five knocked out.
		face.texture_switch(int(e[1]) + (1 if e[4] else 6))
		var hp: float = clampf(e[2], 0.0, 1.0)
		var bar := win.w("gage_bar")
		bar.visible = true
		bar.texture_switch(1 if hp <= 0.1 else (2 if hp <= 0.66 else 3))
		var target := 125.0 * hp
		var cur: float = _board_w.get(slot, target)
		cur = move_toward(cur, target, maxf(absf(target - cur), 1.0) / 0.5 * dt)
		_board_w[slot] = cur
		bar.size_set(cur, 3)
		win.w("name").text_set(str(e[3]))
	for i in Room.SIZE:
		if filled.has(i):
			continue
		var win := play_condition.w("slot%d" % (i + 1))
		if win:
			win.w("char_face").visible = false
			win.w("gage_bar").visible = false
			win.w("name").text_set("")

## OnTimeUpdate: the clock in hundredths, digit by digit. The last-but-one digit wraps at 6,
## as in the original script, so the hundredths read 00..59 in steps of ten.
func time_update(seconds: float) -> void:
	_play_time_cs = seconds * 100.0
	var digits := time_digits(seconds)
	var names := ["number_one", "number_two", "number_three", "number_four", "number_five", "number_six"]
	for i in 6:
		playtime.w(names[i]).texture_switch(digits[i] + 1)

static func time_digits(seconds: float) -> Array[int]:
	var cs := seconds * 100.0
	return [
		int(floor(cs / 60000.0)) % 6, int(floor(cs / 6000.0)) % 10,
		int(floor(cs / 1000.0)) % 6, int(floor(cs / 100.0)) % 10,
		int(floor(cs / 10.0)) % 6, int(cs) % 10]

## OnBoosterUpdate(amount, max_amount, overhit): the gauge fills a 391-pixel bar from the
## bottom, the red part marks the low line, and the readout rides the gauge's top. Below
## the low line the readout hides and the marker flickers between its two warning images.
func booster_update(amount: int, max_amount: int, overhit: int) -> void:
	var base := booster.w("booster_base")
	var bar := base.w("booster_bar")
	var gage := base.w("gage_bar")
	var stats := booster.w("stats_bar")
	var num := stats.w("booster_num")
	bar.texture_switch(2)
	stats.texture_switch(1)
	gage.texture_switch(1)
	num.visible = true
	num.text_set(str(amount), Color8(27, 229, 32))
	var rate := float(amount) / float(max_amount)
	bar.size_set(9, -391.0 * float(overhit) / float(max_amount))
	gage.size_set(9, -391.0 * rate)
	stats.pos_set(0, 388.0 * (1.0 - rate))
	if amount < overhit:
		num.visible = false
		gage.texture_switch(2)
		bar.size_set(9, -391.0 * rate)
		var test := fmod(_play_time_cs * 0.5, 2.0)
		stats.texture_switch(2 if test < 1.0 else 3)

## ON_self_user_state_wnd(robot, name, hp, level): face, name, level and four big HP digits.
func self_user_state(robot: int, user_name: String, hp: int, level: int) -> void:
	var digits := [hp / 1000, (hp / 100) % 10, (hp / 10) % 10, hp % 10]
	var names := ["hp_num_one", "hp_num_two", "hp_num_three", "hp_num_four"]
	for i in 4:
		self_state.w(names[i]).texture_switch(digits[i] + 1)
	self_state.w("robot_face").texture_switch(robot)
	self_state.w("user_name_edit").text_set(user_name, Color8(43, 43, 43))
	self_state.w("user_level_edit").text_set(str(level), Color8(43, 43, 43))

## OnInitialWeaponUpdate: the slot icons, by weapon id. Ids past the icon list (the dagger's
## 28) show no icon, as they did.
func _initial_weapons(ids: Array) -> void:
	for i in mini(4, ids.size()):
		weapon.w("item_slot_%d_img" % (i + 1)).texture_switch(ids[i])
		weapon.w("item_slot_%d_img_selete" % (i + 1)).texture_switch(ids[i])

## OnWeaponUpdate(weapon_id, recharging_time, weapon_name) for the selected slot (0 to 3):
## the recharge ring steps through 16 images as the reload fills, the slot glows near the end,
## and the selection mark moves to the slot.
const SLOT_MARK_X := [161, 219, 276, 332]
func weapon_update(weapon_id: int, ratio: float, weapon_name: String, slot_index: int) -> void:
	var slot := weapon.w("item_slot_%d" % (slot_index + 1))
	var ring := weapon.w("recharge_img")
	slot.texture_switch(1)
	ring.texture_switch(1)
	var steps := [0.06, 0.12, 0.18, 0.24, 0.3, 0.36, 0.42, 0.48, 0.54, 0.6, 0.69, 0.77, 0.85, 0.93, 1.0]
	var rings := [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17]
	for i in steps.size():
		if ratio <= steps[i]:
			ring.texture_switch(rings[i])
			if i == 13:
				slot.texture_switch(14)
			elif i == 14:
				slot.texture_switch(15)
			break
	weapon.w("weapon_img").texture_switch(weapon_id)
	weapon.w("weapon_name").text_set(weapon_name)
	weapon.w("item_selecte_mark").pos_set(SLOT_MARK_X[slot_index], 31)
	for i in range(1, 7):
		var img := weapon.w("item_slot_%d_img" % i)
		if img:
			img.visible = i != slot_index + 1
		var sel := weapon.w("item_slot_%d_img_selete" % i)
		if sel:
			sel.visible = i == slot_index + 1
	for i in range(1, 5):
		if i != slot_index + 1:
			weapon.w("item_slot_%d" % i).texture_switch(1)

## game_fight_weapon_number_show and _full_number_show: ammo left and ammo per load. The
## SR-3 has no ammo limit, so the original showed 0000 / 0000.
func weapon_number_show(n: int) -> void:
	_four_digits(["weapon_number_one", "weapon_number_two", "weapon_number_three", "weapon_number_four"], n)

func weapon_full_number_show(n: int) -> void:
	_four_digits(["weapon_full_number_one", "weapon_full_number_two", "weapon_full_number_three", "weapon_full_number_four"], n)

func _four_digits(names: Array, n: int) -> void:
	var digits := [n / 1000, (n / 100) % 10, (n / 10) % 10, n % 10]
	for i in 4:
		weapon.w(names[i]).texture_switch(digits[i] + 1)

## ON_user_state_wnd(robot, energy_scale, name, grade), called when your shot lands:
## the target's face, name and energy bar for 2 seconds, the bar easing over 0.8 s.
func show_target(robot: int, energy: float, target_name: String) -> void:
	if user_state == null:
		return
	user_state.visible = true
	_user_state_time = 2.0
	user_state.w("robot_face").texture_switch(robot)
	user_state.w("grade").texture_switch(1)
	user_state.w("user_name_edit").text_set(target_name)
	var gage := user_state.w("energy_bar").w("energy_gage")
	var tw := gage.create_tween()
	tw.tween_method(func(v: float) -> void: gage.size_set(v, 8), gage.wsize.x, 75.0 * clampf(energy, 0.0, 1.0), 0.8)

# --- Radar, markers, names (Radar::render_player, render_name) ------------------------------

func _to_screen(p: Vector2, plane_up := 0.0) -> Vector2:
	var px := _camera.unproject_position(Original.to_godot(p + Vector2(0, plane_up)))
	return (px - screen.position) / screen.scale

func _draw_overlay() -> void:
	if _camera == null or booster == null or not booster.visible:
		return
	var ours := OriginalUI.texture("ui/widget/game_fight/rader/ours.png")
	var red_dot := OriginalUI.texture("ui/widget/game_fight/rader/enermy.png")
	var hood_near := OriginalUI.texture("ui/widget/game_fight/rader/hood_player_enemy.png")
	var hood_far := OriginalUI.texture("ui/widget/game_fight/rader/hood_player_enemy_far.png")
	var hood_friend := OriginalUI.texture("ui/widget/game_fight/rader/hood_player_friend.png")
	var font := ThemeDB.fallback_font
	# Radar dots by team, not by side: red players use the "enermy" image, everyone else
	# (blue, or free-for-all) the "ours" one, your own dot included.
	var my_dot := red_dot if my_team == Room.RED else ours
	if my_dot:
		overlay.draw_texture_rect(my_dot, Rect2(RADAR_POS, Vector2(5, 5)), false)
	for t: Tracked in _tracked.values():
		if not t.alive:
			continue
		var rel := Vector2(t.pos.x - _me.x, -(t.pos.y - _me.y)) * RADAR_SCALE
		var dot := red_dot if t.team == Room.RED else ours
		var color := Room.team_color(t.team)
		if jam_time <= 0.0 and absf(rel.x) <= RADAR_HALF.x and absf(rel.y) <= RADAR_HALF.y and dot:
			overlay.draw_texture_rect(dot, Rect2(RADAR_POS + rel, Vector2(5, 5)), false)
		var on_screen := _to_screen(t.pos)
		var inside := on_screen.x >= 0 and on_screen.x <= SCREEN.x and on_screen.y >= 0 and on_screen.y <= SCREEN.y
		if inside:
			# Name 105 x 0.3 + 5 units up the plane, drawn 40 pixels left of that point.
			var at := _to_screen(t.pos, 105.0 * Original.SCALE + 5.0) + Vector2(-40, 0)
			overlay.draw_string_outline(font, at, t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.9))
			overlay.draw_string(font, at, t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		elif jam_time <= 0.0:
			# get_position_on_hood: a marker on a 180-pixel ring, moved only past 5 pixels.
			var slope := atan2(t.pos.y - _me.y, t.pos.x - _me.x)
			var hp := HOOD_CENTRE + Vector2(cos(slope), -sin(slope)) * HOOD_RANGE
			if not t.hood_set or hp.distance_squared_to(t.hood_pos) > 25.0:
				t.hood_pos = hp
				t.hood_set = true
			# Teammates get the friend marker, the nearest enemy the bright one, tinted by team.
			var tex := hood_friend if Room.teammates(t.team, my_team) else (hood_near if t.id == _nearest_id else hood_far)
			if tex:
				overlay.draw_set_transform(t.hood_pos + Vector2(5, 5), -slope)
				overlay.draw_texture_rect(tex, Rect2(Vector2(-5, -5), Vector2(10, 10)), false, color)
				overlay.draw_set_transform(Vector2.ZERO)
	# Lock-on markers, hidden while jammed (render_lock_on_system); lock-on still works.
	if jam_time <= 0.0:
		_draw_lock_marks()
	# Under 10% life, SPAttack.png pulses below your mech.
	if _me_low and _me_alive:
		var warn := OriginalUI.texture("ui2/game_fight/spattack.png")
		if warn:
			var at := _to_screen(_me, -(80.0 * Original.SCALE + 5.0)) + Vector2(-70, 25)
			overlay.draw_texture(warn, at, Color(1, 1, 1, _spattack_alpha / 255.0))

## Lock-on: locked by an enemy, your target (and its edge mark), the candidates.
func _draw_lock_marks() -> void:
	if locked_on_me:
		var locked := OriginalUI.texture("ui/widget/game_fight/rader/fughtui_locked.png")
		if locked:
			overlay.draw_texture_rect(locked, Rect2(Vector2(400 - 55, 300 - 43), Vector2(110, 86)), false)
	if lock_target_pos != null:
		var lt := _to_screen(lock_target_pos)
		var lockon := OriginalUI.texture("ui/widget/game_fight/rader/fughtui_lockon.png")
		if lockon:
			overlay.draw_texture_rect(lockon, Rect2(lt - Vector2(59, 43.5), Vector2(118, 87)), false)
		if lt.x < 0 or lt.x > SCREEN.x or lt.y < 0 or lt.y > SCREEN.y:
			var slope := atan2((lock_target_pos as Vector2).y - _me.y, (lock_target_pos as Vector2).x - _me.x)
			var hp := HOOD_CENTRE + Vector2(cos(slope), -sin(slope)) * HOOD_RANGE - Vector2(15, 30)
			var hud_mark := OriginalUI.texture("ui/widget/game_fight/rader/fughtui_lockon_hud.png")
			if hud_mark:
				overlay.draw_texture(hud_mark, hp)
	var locking := OriginalUI.texture("ui/widget/game_fight/rader/fughtui_locking.png")
	if locking:
		for c in lock_candidates:
			overlay.draw_texture_rect(locking, Rect2(_to_screen(c) - Vector2(44, 37), Vector2(88, 74)), false)

# --- Results (this recreation's own panel) --------------------------------------------------

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
