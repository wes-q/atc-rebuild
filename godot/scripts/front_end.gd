class_name FrontEnd
extends CanvasLayer
## The original's front end, from its Lua pages: login (page_login_new.lua), the loading
## screen, character select (page_charactor.lua), the main menu (page_main_menu.lua) and the
## options page (page_main_menu_option.lua). The windows come from the exported resource
## tables and are drawn by OriginalUI in the original's 800x600 layout, scaled to the window.
##
## What needed CodiNET's servers is mapped onto this recreation:
## - Login asks for a player name; the password box is ignored.
## - Character select shows the five bodies in turn instead of a server's character list.
## - The chat console shows your own messages and the front end's notices.
## - Battle and Shop lead to the classic menu (host, join, loadout) until the room list
##   (step 14) and shop page (step 15) replace it. Tutorial starts practice.

signal practice_requested
signal battle_requested
signal shop_requested

const BGM_MENU := 3 ## "Good Luck (Ver2)", from login through the rooms (play_sound_bgm_lua(3))
## Where the name, body and options are kept between runs.
var profile_path := "user://profile.cfg"
## page_login_new cursor: frames 1-6-1 played over 0.6 s on every click, hotspot (8, 11).
const CURSOR_FRAMES := ["cursor01", "cursor02", "cursor03", "cursor04", "cursor05", "cursor06",
	"cursor05", "cursor04", "cursor03", "cursor02", "cursor01"]
const CURSOR_HOTSPOT := Vector2(8, 11)
const CURSOR_TIME := 0.6
## The character select turntables: 32 pre-rendered frames over 3 s, looping.
const TURNTABLE_TIME := 3.0
const TURNTABLE := {"zeid": "zeid", "redkite": "kite", "gigas": "gigas", "deff": "deff", "alicia": "alicia"}

var sound: GameSound
var player_name := ""
var body := "zeid"
var channel := "raycrash-1"
## The options page's tooltip switch (get_tooltip_flag).
var tooltips_on := true

var screen: Control
var page_root: Node2D
var popup_root: Node2D
var page := ""
var _hover: OriginalUI
var _pressed: OriginalUI
var _tooltip: OriginalUI
var _cursor: Array[Texture2D] = []
var _cursor_time := -1.0
var _turntable: OriginalUI
var _turn_time := 0.0
var _console_lines: Array[String] = []
var _console_scroll := 0
var _console_view: Node2D
var _bgm_test := BGM_MENU
var _texts := {}
var _drag: OriginalUI
var _drag_bar: Callable

func _ready() -> void:
	layer = 30
	screen = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	page_root = Node2D.new()
	screen.add_child(page_root)
	popup_root = Node2D.new()
	screen.add_child(popup_root)
	OriginalUI.sound = func(path: String) -> void:
		if sound:
			sound.play(path)
	var f := FileAccess.open(OriginalUI.ROOT + "texts.json", FileAccess.READ)
	if f:
		_texts = JSON.parse_string(f.get_as_text())
	for frame in CURSOR_FRAMES:
		_cursor.append(OriginalUI.texture("ui/widget/test/%s.png" % frame))
	_load_profile()
	if get_viewport():
		get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	if get_viewport() == null:
		return
	var size := get_viewport().get_visible_rect().size
	var s := minf(size.x / 800.0, size.y / 600.0)
	screen.scale = Vector2(s, s)
	screen.position = (size - Vector2(800, 600) * s) * 0.5

## game_text_new_version.text_N, the English game text.
func text(key: String) -> String:
	return str(_texts.get("game_text_new_version", {}).get(key, "")).replace("\r\n", "\n").strip_edges()

func system_text(key: String) -> String:
	return str(_texts.get("system_message", {}).get(key, "")).strip_edges()

func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(profile_path) == OK:
		player_name = str(cfg.get_value("player", "name", ""))
		body = str(cfg.get_value("player", "body", "zeid"))
		tooltips_on = bool(cfg.get_value("options", "tooltips", true))
		if sound:
			sound.music_volume = float(cfg.get_value("options", "bgm", 1.0))
			sound.effects_volume = float(cfg.get_value("options", "effect", 1.0))
	if not body in Bodies.NAMES:
		body = "zeid"

func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "body", body)
	cfg.set_value("options", "tooltips", tooltips_on)
	if sound:
		cfg.set_value("options", "bgm", sound.music_volume)
		cfg.set_value("options", "effect", sound.effects_volume)
	cfg.save(profile_path)

## Shown or hidden as a whole; the OS cursor comes back while hidden (the battle draws its own).
func set_shown(on: bool) -> void:
	visible = on
	_hover = null
	_pressed = null
	_hide_tooltip()
	_apply_cursor(0 if on else -1)

# --- Pages ------------------------------------------------------------------------------

func _clear() -> void:
	for c in page_root.get_children():
		c.queue_free()
	for c in popup_root.get_children():
		c.queue_free()
	_hover = null
	_pressed = null
	_turntable = null
	_console_view = null
	_drag = null
	_hide_tooltip()

func _add(table: String, parent: Node = null) -> OriginalUI:
	var win := OriginalUI.create(table)
	(parent if parent else page_root).add_child(win)
	return win

## page_login_new: the backdrop, the ID and password boxes and Accept and Exit.
func show_login() -> void:
	_clear()
	set_shown(true)
	page = "login"
	if sound:
		sound.play_bgm(BGM_MENU)
	var bg := _add("page_login_background")
	bg.w("version_text").text_set("Godot recreation")
	var input := _add("page_login_input", bg)
	var id_edit := input.w("id_edit")
	var pass_edit := input.w("pass_edit")
	for e in [id_edit, pass_edit]:
		e.set_font(9)
		e.submitted.connect(func(_t: String) -> void: _login_accept(id_edit))
	id_edit.editor.text = player_name
	id_edit.editor.max_length = 15
	id_edit.editor.focus_next = id_edit.editor.get_path_to(pass_edit.editor)
	pass_edit.editor.focus_next = pass_edit.editor.get_path_to(id_edit.editor)
	id_edit.focus_set()
	var buttons := _add("page_login_button", bg)
	buttons.w("accept_button").clicked.connect(func() -> void: _login_accept(id_edit))
	buttons.w("cancel_button").clicked.connect(func() -> void: get_tree().quit())

func _login_accept(id_edit: OriginalUI) -> void:
	var name_text := id_edit.text_get().strip_edges()
	if name_text == "":
		message(system_text("no_such_ID"))
		return
	player_name = name_text
	save_profile()
	show_loading(show_character)

## Loading_window_create: loading.png with its gauge filling to 227 pixels, then the next page.
func show_loading(next: Callable) -> void:
	_clear()
	page = "loading"
	var img := OriginalUI.new()
	img.textures.append(OriginalUI.texture("ui3/loading/loading.png"))
	img.uvs.append(null)
	img.fixed = true
	page_root.add_child(img)
	var base := OriginalUI.new()
	base.position = Vector2(259, 433)
	base.textures.append(OriginalUI.texture("ui3/loading/x-259-y-443.png"))
	base.uvs.append(null)
	base.fixed = true
	img.add_child(base)
	var gage := OriginalUI.new()
	gage.position = Vector2(264, 448)
	gage.wsize = Vector2(1, 8)
	gage.textures.append(OriginalUI.texture("ui3/loading/x-264 y459.png"))
	gage.uvs.append(null)
	img.add_child(gage)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: gage.size_set(w, 8), 1.0, 227.0, 1.2)
	tw.tween_interval(0.2)
	tw.tween_callback(next)

## page_charactor: the bodies in turn on the turntable, the pilot panel, Enter and Exit.
func show_character() -> void:
	_clear()
	set_shown(true)
	page = "character"
	var tray := _add("res_dlg_charactor_tray_base")
	var info := _add("res_dlg_charactor_select_information", tray)
	var dlg := tray.w("dlg")
	# No server to create or delete characters: the bodies take their place.
	dlg.w("create_button").visible = false
	dlg.w("delete_button").visible = false
	dlg.w("create_effect_img").visible = false
	dlg.w("enter_button").tooltip = text("text_99")
	dlg.w("exit_button").tooltip = text("text_100")
	dlg.w("back_button").clicked.connect(func() -> void: _cycle_body(-1))
	dlg.w("next_button").clicked.connect(func() -> void: _cycle_body(1))
	dlg.w("enter_button").clicked.connect(_character_enter)
	dlg.w("exit_button").clicked.connect(_character_exit)
	_update_character(tray, info)

func _cycle_body(step: int) -> void:
	var i := (Bodies.NAMES.find(body) + step + Bodies.NAMES.size()) % Bodies.NAMES.size()
	body = Bodies.NAMES[i]
	save_profile()
	var tray := page_root.get_child(0) as OriginalUI
	_update_character(tray, tray.w("res_dlg_charactor_select_information"))

## update_character_info: the name, a new pilot's PVT grade and zero record, the body as the
## armour, and that body's turntable.
func _update_character(tray: OriginalUI, info: OriginalUI) -> void:
	var dlg := tray.w("dlg")
	dlg.w("user_char_name").text_set(player_name)
	info.w("name").text_set(player_name)
	info.w("grade").texture_switch(1)
	info.w("class_name").text_set("PVT")
	info.w("score").text_set("0")
	info.w("money").text_set("0")
	info.w("amor").text_set(Bodies.TITLES[body])
	info.w("score_win").text_set("0")
	info.w("slash_mark").text_set("/")
	info.w("score_lose").text_set("0")
	for k in ["generator", "booster", "mcs", "sensor"]:
		info.w(k).text_set("None")
	for b in TURNTABLE:
		dlg.w("charactor_rotate_animation_" + TURNTABLE[b]).visible = b == body
	_turntable = dlg.w("charactor_rotate_animation_" + TURNTABLE[body])
	_turn_time = 0.0

func _character_enter() -> void:
	if sound:
		sound.play("sound/ui/middle_poly_select")
	get_tree().create_timer(1.0).timeout.connect(func() -> void: show_main_menu())

## character_exit: the intro picture for 4 s, then the game closes (I_robot_img_show).
func _character_exit() -> void:
	_clear()
	page = "exit"
	var img := OriginalUI.new()
	img.textures.append(OriginalUI.texture("ui3/loading/intro.png"))
	img.uvs.append(null)
	img.fixed = true
	page_root.add_child(img)
	get_tree().create_timer(4.0).timeout.connect(func() -> void: get_tree().quit())

## page_main_menu: the button stack, the chat console and the channel's user list.
func show_main_menu(notice := "") -> void:
	_clear()
	set_shown(true)
	page = "main"
	if sound and not sound.is_playing_bgm():
		sound.play_bgm(BGM_MENU)
	_add("res_dlg_main_menu_background")
	var stack := _add("res_dlg_main_menu_Propertybutton")
	stack.w("base_battle_button").visible = false
	var tips := {"battle_button": "text_103", "tutorial_button": "text_106", "channel_button": "text_104",
		"option_button": "text_105", "exit_button": "text_102"}
	for k in tips:
		stack.w(k).tooltip = text(tips[k])
	stack.w("battle_button").clicked.connect(func() -> void: battle_requested.emit())
	stack.w("tutorial_button").clicked.connect(func() -> void: practice_requested.emit())
	stack.w("shop_button").clicked.connect(func() -> void: shop_requested.emit())
	stack.w("channel_button").clicked.connect(_channel_popup)
	stack.w("option_button").clicked.connect(show_options)
	stack.w("exit_button").clicked.connect(show_character)
	var chat := _add("res_dlg_main_menu_chatting")
	chat.w("edit_box").text_set(channel)
	_console_view = Node2D.new()
	_console_view.draw.connect(_draw_console.bind(chat.w("console")))
	chat.w("console").add_child(_console_view)
	var tabs := chat.w("chat_style")
	var normal := tabs.w("normal_button")
	var whisper := tabs.w("whisper_button")
	var clan := tabs.w("clan_button")
	normal.tooltip = text("text_108")
	whisper.tooltip = text("text_109")
	clan.tooltip = text("text_123")
	var edit := chat.w("input_edit")
	for tab in [normal, whisper, clan]:
		tab.clicked.connect(func() -> void:
			for other in [normal, whisper, clan]:
				other.set_checked(other == tab)
			# The whisper tab starts the line with the whisper sign.
			edit.editor.text = "@" if tab == whisper else ""
			edit.focus_set())
	normal.set_checked(true)
	edit.submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			console_add("[%s] %s" % [player_name, t.strip_edges()])
		edit.editor.text = "")
	chat.w("scroll_up_button").clicked.connect(func() -> void: _scroll_console(1))
	chat.w("scroll_down_button").clicked.connect(func() -> void: _scroll_console(-1))
	var users := _add("res_dlg_main_menu_channel")
	var friends := users.w("friend_list")
	friends.w("friend_button").set_checked(true)
	friends.w("user_clan_list").visible = false
	friends.w("friend_button").clicked.connect(func() -> void:
		friends.w("friend_button").set_checked(true)
		friends.w("clan_button").set_checked(false))
	friends.w("clan_button").clicked.connect(func() -> void:
		friends.w("clan_button").set_checked(true)
		friends.w("friend_button").set_checked(false))
	var list := users.w("user_list")
	var me := OriginalUI.new()
	me.position = Vector2(6, 5)
	me.text = player_name
	list.add_child(me)
	if _console_lines.is_empty():
		console_add("You entered channel %s." % channel)
	if notice != "":
		message(notice)

func console_add(line: String) -> void:
	_console_lines.append(line)
	_console_scroll = 0
	if _console_view:
		_console_view.queue_redraw()

func _scroll_console(step: int) -> void:
	_console_scroll = clampi(_console_scroll + step, 0, maxi(0, _console_lines.size() - 1))
	if _console_view:
		_console_view.queue_redraw()

## WINDOW_CONSOLE2: the newest line at the bottom, white, scrolled back by the arrows.
func _draw_console(console: OriginalUI) -> void:
	var f: Array = OriginalUI.font_for(0)
	var font: Font = f[0]
	var size: int = f[1]
	var line_h := font.get_height(size) + 2.0
	var y := console.wsize.y - 4.0
	var last := _console_lines.size() - 1 - _console_scroll
	for i in range(last, -1, -1):
		if y - line_h < 0.0:
			break
		_console_view.draw_string(font, Vector2(4, y - font.get_descent(size)), _console_lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, console.wsize.x - 8.0, size, Color.WHITE)
		y -= line_h

## on_push_channel_button: the channel name box, pre-filled "raycrash-", with OK and Cancel.
func _channel_popup() -> void:
	var pop := _add("res_dlg_main_menu_channel_wnd", popup_root)
	var dlg := pop.w("dlg")
	var edit := dlg.w("input_edit")
	edit.editor.text = "raycrash-"
	edit.editor.caret_column = edit.editor.text.length()
	edit.focus_set()
	var ok := func() -> void:
		var name_text := edit.text_get().strip_edges()
		if name_text != "":
			channel = name_text
			console_add("You moved to channel %s." % channel)
			var chat := page_root.get_node_or_null("res_dlg_main_menu_chatting") as OriginalUI
			if chat:
				chat.w("edit_box").text_set(channel)
		pop.queue_free()
	edit.submitted.connect(func(_t: String) -> void: ok.call())
	dlg.w("ok_button").clicked.connect(ok)
	dlg.w("cancel_button").clicked.connect(func() -> void: pop.queue_free())

## page_main_menu_option: BGM and effect volume bars, the music test player, full screen and
## tooltips on or off.
func show_options() -> void:
	_clear()
	page = "option"
	var opt := _add("res_dlg_main_menu_option")
	var s := opt.w("sound")
	s.w("option_background_img").visible = false # its art is not in the archive
	s.w("key_setting").visible = false # the key setting page is not in the archive
	s.w("exit_button").clicked.connect(func() -> void:
		save_profile()
		show_main_menu())
	_bar(s.w("bgm_bar"), func() -> float: return sound.music_volume if sound else 1.0,
		func(v: float) -> void: if sound: sound.music_volume = v)
	_bar(s.w("effect_bar"), func() -> float: return sound.effects_volume if sound else 1.0,
		func(v: float) -> void: if sound: sound.effects_volume = v)
	var track := s.w("test_bgm_play_list_text")
	var show_track := func() -> void: track.text_set(sound.bgm_name(_bgm_test) if sound else "")
	s.w("test_play_button").clicked.connect(func() -> void:
		if sound:
			sound.play_bgm(_bgm_test)
		show_track.call())
	s.w("test_pause_button").clicked.connect(func() -> void: if sound: sound.stop_bgm())
	s.w("test_next_button").clicked.connect(func() -> void:
		if sound:
			_bgm_test = (_bgm_test + 1) % sound.bgm_count()
			sound.play_bgm(_bgm_test)
		show_track.call())
	show_track.call()
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_toggle(s, "window_mode", not full, func(on: bool) -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if on else DisplayServer.WINDOW_MODE_FULLSCREEN))
	_toggle(s, "tooltip", tooltips_on, func(on: bool) -> void:
		tooltips_on = on
		save_profile())

## OptionControlBgmScrollBar and its twin: the knob slides along its 272-pixel bar.
func _bar(bar: OriginalUI, read: Callable, write: Callable) -> void:
	var knob := bar.w("control_bar")
	var span := bar.wsize.x - knob._hit_size().x
	knob.position.x = span * float(read.call())
	knob.set_meta("bar_span", span)
	knob.set_meta("bar_write", write)

## A pair of on and off check boxes with the check mark over the chosen one.
func _toggle(s: OriginalUI, prefix: String, on: bool, apply: Callable) -> void:
	var mark := s.w(prefix + "_check_img")
	var on_button := s.w(prefix + "_check_box_on_button")
	var off_button := s.w(prefix + "_check_box_off_button")
	var place := func(state: bool) -> void:
		var target := on_button if state else off_button
		mark.position = target.position + Vector2(-3, -11)
	place.call(on)
	on_button.clicked.connect(func() -> void:
		place.call(true)
		apply.call(true))
	off_button.clicked.connect(func() -> void:
		place.call(false)
		apply.call(false))

## Android's back button: close a popup, else step back a page; from login, quit.
func go_back() -> void:
	for i in range(popup_root.get_child_count() - 1, -1, -1):
		var c := popup_root.get_child(i)
		if c != _tooltip and not c.is_queued_for_deletion():
			c.queue_free()
			return
	match page:
		"option":
			save_profile()
			show_main_menu()
		"main":
			show_character()
		"character":
			_character_exit()
		"login":
			get_tree().quit()

# --- Message box and tooltip ------------------------------------------------------------

## OkMessageBox: the dimmed screen, the message panel and its OK button.
func message(msg: String, done: Callable = Callable()) -> void:
	var box := _add("res_yesnoMessageBox", popup_root)
	var panel := box.w("msg")
	# YesNoMessageBox: one centred line in the panel above the buttons.
	panel.w("text").wsize = Vector2(260, 84)
	panel.w("text").text_set(msg)
	panel.w("no").visible = false
	var ok := panel.w("check")
	ok.position.x = (panel.wsize.x - ok._hit_size().x) * 0.5
	ok.clicked.connect(func() -> void:
		box.queue_free()
		if done.is_valid():
			done.call())

func _show_tooltip(win: OriginalUI, at: Vector2) -> void:
	_hide_tooltip()
	if not tooltips_on or win.tooltip == "":
		return
	_tooltip = OriginalUI.create("res_tool_tip_on")
	_tooltip.position = at + Vector2(-50, -80)
	_tooltip.w("tool_tip_text").text_set(win.tooltip)
	popup_root.add_child(_tooltip)

func _hide_tooltip() -> void:
	if _tooltip:
		_tooltip.queue_free()
		_tooltip = null

# --- Pointer ----------------------------------------------------------------------------

func _to_page(p: Vector2) -> Vector2:
	return (p - screen.position) / screen.scale

## The control under the pointer: an open popup takes every click, as the original's
## message boxes did.
func _control_at(p: Vector2) -> OriginalUI:
	if popup_root.get_child_count() > 0:
		for i in range(popup_root.get_child_count() - 1, -1, -1):
			var c := popup_root.get_child(i) as OriginalUI
			if c == _tooltip or c == null or c.is_queued_for_deletion():
				continue
			return c.control_at(p)
	for i in range(page_root.get_child_count() - 1, -1, -1):
		var c := page_root.get_child(i) as OriginalUI
		if c and not c.is_queued_for_deletion():
			var hit := c.control_at(p)
			if hit:
				return hit
	return null

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var p := _to_page((event as InputEventMouseMotion).position)
		if _drag:
			_drag_to(p)
			return
		var target := _control_at(p)
		if target != _hover:
			if _hover and is_instance_valid(_hover):
				_hover.mouse_out()
			_hide_tooltip()
			_hover = target
			if target:
				target.mouse_in()
				_show_tooltip(target, p)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			if mb.pressed and page == "main" and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				_scroll_console(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			return
		var p := _to_page(mb.position)
		if mb.pressed:
			_cursor_time = 0.0
			var target := _control_at(p)
			if target:
				_pressed = target
				target.press()
				if target.has_meta("bar_span"):
					_drag = target
				_handled()
		else:
			_drag = null
			if _pressed and is_instance_valid(_pressed):
				var released := _pressed
				_pressed = null
				released.release(_control_at(p) == released)
				_handled()

func _handled() -> void:
	if get_viewport():
		get_viewport().set_input_as_handled()

## A volume knob follows the pointer along its bar.
func _drag_to(p: Vector2) -> void:
	var bar := _drag.get_parent() as OriginalUI
	var span: float = _drag.get_meta("bar_span")
	var bar_page := _page_pos(bar)
	_drag.position.x = clampf(p.x - bar_page.x - _drag._hit_size().x * 0.5, 0.0, span)
	(_drag.get_meta("bar_write") as Callable).call(_drag.position.x / span if span > 0.0 else 0.0)

## A window's position in the 800x600 page.
func _page_pos(win: Node2D) -> Vector2:
	var p := Vector2.ZERO
	var n: Node = win
	while n and n != page_root and n != popup_root:
		p += (n as Node2D).position
		n = n.get_parent()
	return p

# --- Cursor and turntable -----------------------------------------------------------------

func _apply_cursor(frame: int) -> void:
	if DisplayServer.get_name() == "headless" or (DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")):
		return
	if frame < 0 or frame >= _cursor.size() or _cursor[frame] == null:
		Input.set_custom_mouse_cursor(null)
		return
	Input.set_custom_mouse_cursor(_cursor[frame], Input.CURSOR_ARROW, CURSOR_HOTSPOT)

func _process(dt: float) -> void:
	if not visible:
		return
	if _cursor_time >= 0.0:
		_cursor_time += dt
		var frame := int(_cursor_time / CURSOR_TIME * _cursor.size())
		if frame >= _cursor.size():
			_cursor_time = -1.0
			frame = 0
		_apply_cursor(frame)
	if _turntable and is_instance_valid(_turntable):
		_turn_time = fmod(_turn_time + dt, TURNTABLE_TIME)
		var frames := _turntable.textures.size() - 1
		if frames > 0:
			# All 32 frames: one more than texture_switch accepts, so set it directly.
			var frame := 1 + int(_turn_time / TURNTABLE_TIME * frames) % frames
			if frame != _turntable.current:
				_turntable.current = frame
				_turntable.queue_redraw()
