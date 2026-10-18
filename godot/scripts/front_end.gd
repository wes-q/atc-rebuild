class_name FrontEnd
extends CanvasLayer
## The original's front end, from its Lua pages: login (page_login_new.lua), the loading
## screen, character select (page_charactor.lua), the main menu (page_main_menu.lua), the
## options page (page_main_menu_option.lua), the room list (page_custom_game.lua) and the game
## room (page_game_room.lua). The windows come from the exported resource tables and are
## drawn by OriginalUI in the original's 800x600 layout, scaled to the window.
##
## What needed CodiNET's servers is mapped onto this recreation:
## - Login asks for a player name; the password box is ignored.
## - Character select shows the five bodies in turn instead of a server's character list.
## - The main menu's chat console shows your own messages and the front end's notices.
## - The room list shows the rooms hosts announce on the local network (LanRooms), and the
##   quick-go name box also takes a host's address. Creating a room hosts it.
## - The game room is run by the game (scripts/game.gd), which hands this page what to show
##   and hears its buttons through the room_* signals.
## - ITEM SHOP opens the shop page as the garage (ShopPage), where each body's loadout is
##   chosen and kept with the profile. Tutorial starts practice.

signal practice_requested
signal battle_requested
signal shop_requested
## The room list's Create: host a room.
signal room_create(room_name: String, password: String, teams: bool, beginner: bool)
## The room list's Enter, a row's double click, Quick Join or Quick Go: join a host.
signal room_join(address: String, password: String)
## Game room controls.
signal room_start
signal room_map(step: int)
signal room_slot(slot: int)
signal room_chat(line: String)
signal room_exit
## The shop page opened or the robot it shows changed: the four weapons and the one in hand.
signal shop_view(body: String, weapons: Array, slot: int)
## The shop's viewer was clicked: the robot plays the weapon's attack.
signal shop_attack

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
## Console lines as [text, colour]: the main menu's, and the game room's.
var _console_lines: Array = []
var _room_lines: Array = []
var _console_scroll := 0
var _console_view: Node2D
var _bgm_test := BGM_MENU
var _texts := {}
var _drag: OriginalUI
var _drag_bar: Callable
## The rooms on the local network, heard while the room list is open.
var lan: LanRooms
## page_custom_game: PushtypeCount (0 all, 1 single, 2 team) and PushStatusCount (0 all,
## 1 waiting, 3 playing; 2 is skipped as the original did), the shown page of rows and the
## chosen room.
var _type_filter := 0
var _status_filter := 0
var _list_page := 0
var _list_selected := ""
var _list_click := ["", -1.0]
## Each body's chosen weapons, by body name (kept with the profile).
var loadouts := {}
## The shop page while it is open.
var shop: ShopPage
const BGM_SHOP := 22 ## play_sound_bgm_lua(22) in page_game_shop:create
## What the game room shows (game.gd's _room_view).
var room_view := {}
## The number the room list gave the room being joined (1 for a typed address).
var joined_number := 1

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
	lan = LanRooms.new()
	add_child(lan)
	lan.changed.connect(func() -> void:
		if page == "room_list":
			_fill_rooms())
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
		loadouts.clear()
		for b in Bodies.NAMES:
			var saved: Variant = cfg.get_value("loadout", b, [])
			if saved is Array and not (saved as Array).is_empty():
				loadouts[b] = saved
		if sound:
			sound.music_volume = float(cfg.get_value("options", "bgm", 1.0))
			sound.effects_volume = float(cfg.get_value("options", "effect", 1.0))
	if not body in Bodies.NAMES:
		body = "zeid"

## A body's weapons as chosen in the shop, or its defaults.
func loadout(body_name: String) -> Array[int]:
	return Bodies.checked_loadout(body_name, loadouts.get(body_name, Bodies.DEFAULTS[body_name].slice(0, 4)))

## char_info.weapon_item: a weapon's description in the shop.
func weapon_text(id: int) -> String:
	var items: Dictionary = _texts.get("game_text_new_version", {}).get("char_info", {}).get("weapon_item", {})
	return str(items.get(str(id), "")).replace("\r\n", "\n").strip_edges()

func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "body", body)
	cfg.set_value("options", "tooltips", tooltips_on)
	for b in loadouts:
		cfg.set_value("loadout", b, Array(loadouts[b]))
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
	if page == "room_list" and lan:
		lan.stop_listening()
	shop = null
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
	if sound and (not sound.is_playing_bgm() or sound.current_bgm != BGM_MENU):
		sound.play_bgm(BGM_MENU)
	_add("res_dlg_main_menu_background")
	var stack := _add("res_dlg_main_menu_Propertybutton")
	stack.w("base_battle_button").visible = false
	var tips := {"battle_button": "text_103", "tutorial_button": "text_106", "channel_button": "text_104",
		"option_button": "text_105", "exit_button": "text_102"}
	for k in tips:
		stack.w(k).tooltip = text(tips[k])
	stack.w("battle_button").clicked.connect(func() -> void:
		battle_requested.emit()
		show_room_list())
	stack.w("tutorial_button").clicked.connect(func() -> void: practice_requested.emit())
	stack.w("shop_button").clicked.connect(func() -> void:
		shop_requested.emit()
		show_shop())
	stack.w("channel_button").clicked.connect(_channel_popup)
	stack.w("option_button").clicked.connect(show_options)
	stack.w("exit_button").clicked.connect(show_character)
	var chat := _add("res_dlg_main_menu_chatting")
	chat.w("edit_box").text_set(channel)
	_console_view = Node2D.new()
	_console_view.draw.connect(_draw_console.bind(chat.w("console"), _console_lines))
	chat.w("console").add_child(_console_view)
	var edit := chat.w("input_edit")
	_chat_tabs(chat.w("chat_style"), edit)
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

## The normal, whisper and clan tabs over a chat box. Only normal chat is carried; the
## whisper tab starts the line with the whisper sign as the original did.
func _chat_tabs(tabs: OriginalUI, edit: OriginalUI) -> void:
	var normal := tabs.w("normal_button")
	var whisper := tabs.w("whisper_button")
	var clan := tabs.w("clan_button")
	normal.tooltip = text("text_108")
	whisper.tooltip = text("text_109")
	clan.tooltip = text("text_123")
	for tab in [normal, whisper, clan]:
		tab.clicked.connect(func() -> void:
			for other in [normal, whisper, clan]:
				other.set_checked(other == tab)
			edit.editor.text = "@" if tab == whisper else ""
			edit.focus_set())
	normal.set_checked(true)

func console_add(line: String, color := Color.WHITE) -> void:
	_console_lines.append([line, color])
	_console_scroll = 0
	if _console_view and page == "main":
		_console_view.queue_redraw()

## The game room's console: chat, the start countdown and System notices.
func room_console_add(line: String, color := Color.WHITE) -> void:
	_room_lines.append([line, color])
	_console_scroll = 0
	if _console_view and page == "room":
		_console_view.queue_redraw()

## A new room starts with an empty console.
func clear_room_console() -> void:
	_room_lines.clear()

func _scroll_console(step: int) -> void:
	var lines := _room_lines if page == "room" else _console_lines
	_console_scroll = clampi(_console_scroll + step, 0, maxi(0, lines.size() - 1))
	if _console_view:
		_console_view.queue_redraw()

## WINDOW_CONSOLE2: the newest line at the bottom, each in its colour, scrolled back by the
## arrows.
func _draw_console(console: OriginalUI, lines: Array) -> void:
	var f: Array = OriginalUI.font_for(0)
	var font: Font = f[0]
	var size: int = f[1]
	var line_h := font.get_height(size) + 2.0
	var y := console.wsize.y - 4.0
	var last := lines.size() - 1 - _console_scroll
	for i in range(last, -1, -1):
		if y - line_h < 0.0:
			break
		_console_view.draw_string(font, Vector2(4, y - font.get_descent(size)), str(lines[i][0]),
			HORIZONTAL_ALIGNMENT_LEFT, console.wsize.x - 8.0, size, lines[i][1])
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

# --- Room list (page_custom_game) -----------------------------------------------------------

const ROWS_PER_PAGE := 12 ## availList: 360 pixels of 28-pixel rows
const DOUBLE_CLICK := 0.4
## Text colours the room pages set (set_text_color, set_console2_text_color).
const DARK_TEXT := Color8(43, 43, 43)
const MY_NAME := Color8(255, 230, 63)
const NOTICE := Color8(40, 255, 126)
const ALERT := Color8(255, 154, 0)

## The room list: the rooms heard on the network in rows of twelve, the type and status
## filters, Quick Go (room number, or a room name or host address, and a password), Create,
## Enter, Quick Join, Refresh and back to the channel.
func show_room_list(notice := "") -> void:
	_clear()
	set_shown(true)
	page = "room_list"
	if sound and not sound.is_playing_bgm():
		sound.play_bgm(BGM_MENU)
	var bg := _add("res_dlg_custom_game_background")
	_add("res_dlg_custom_game_availble_list", bg)
	var topic := bg.w("battle_room_topic")
	topic.w("type_button").tooltip = text("text_115")
	topic.w("status_button").tooltip = text("text_116")
	topic.w("type_button").clicked.connect(func() -> void:
		_type_filter = (_type_filter + 1) % 3
		topic.w("type_button_img").texture_switch(_type_filter + 1)
		_list_page = 0
		_fill_rooms())
	topic.w("status_button").clicked.connect(func() -> void:
		_status_filter = 0 if _status_filter >= 3 else (3 if _status_filter == 1 else 1)
		_list_page = 0
		_fill_rooms())
	topic.w("type_button_img").texture_switch(_type_filter + 1)
	var tips := {"refresh_button": "text_110", "create_game_button": "text_111", "quick_join_button": "text_112",
		"enter_button": "text_113", "create_game_exit_button": "text_114"}
	for k in tips:
		bg.w(k).tooltip = text(tips[k])
	bg.w("create_game_exit_button").clicked.connect(func() -> void: show_main_menu())
	bg.w("create_game_button").clicked.connect(_create_room_popup)
	bg.w("enter_button").clicked.connect(func() -> void:
		var room := _listed_room(func(r: Dictionary) -> bool: return str(r["id"]) == _list_selected)
		if room.is_empty():
			message(system_text("Please_select_room"))
		else:
			_join_listed(room))
	bg.w("quick_join_button").clicked.connect(func() -> void:
		# request_quick_join: a waiting room with room for one more and no password.
		var room := _listed_room(func(r: Dictionary) -> bool:
			return not bool(r.get("playing", false)) and not bool(r.get("locked", false)) and int(r.get("players", 0)) < Room.SIZE)
		if room.is_empty():
			message(text("text_48"))
		else:
			_join_listed(room))
	bg.w("refresh_button").clicked.connect(func() -> void:
		_type_filter = 0
		_status_filter = 0
		_list_page = 0
		topic.w("type_button_img").texture_switch(1)
		lan.clear())
	bg.w("back_button").clicked.connect(func() -> void:
		_list_page -= 1
		_fill_rooms())
	bg.w("next_button").clicked.connect(func() -> void:
		_list_page += 1
		_fill_rooms())
	var number_edit := bg.w("battle_room_quick_go_edit_room_number")
	var name_edit := bg.w("battle_room_quick_go_edit_box")
	var pass_edit := bg.w("battle_room_quick_go_edit_box_pass")
	number_edit.editor.max_length = 3
	name_edit.editor.max_length = 34
	pass_edit.editor.max_length = 15
	pass_edit.editor.secret = true
	name_edit.editor.focus_next = name_edit.editor.get_path_to(pass_edit.editor)
	pass_edit.editor.focus_next = pass_edit.editor.get_path_to(name_edit.editor)
	for e in [number_edit, name_edit, pass_edit]:
		e.submitted.connect(func(_t: String) -> void: _quick_go(number_edit, name_edit, pass_edit))
	bg.w("battle_room_quick_go").w("go_button").clicked.connect(func() -> void: _quick_go(number_edit, name_edit, pass_edit))
	_autofocus(name_edit)
	if not lan.listen() and notice == "":
		notice = "Another copy on this computer is listening for rooms. Type a host's address in Quick Go."
	_fill_rooms()
	if notice != "":
		message(notice)

func _list_rows() -> OriginalUI:
	var bg := page_root.get_node_or_null("res_dlg_custom_game_background") as OriginalUI
	if bg == null:
		return null
	return bg.w("res_dlg_custom_game_availble_list").w("availList")

## The rooms the filters let through, in room number order.
func _filtered_rooms() -> Array:
	var out := []
	for r: Dictionary in lan.rooms():
		var teams := bool(r.get("teams", false))
		var playing := bool(r.get("playing", false))
		if (_type_filter == 1 and teams) or (_type_filter == 2 and not teams):
			continue
		if (_status_filter == 1 and playing) or (_status_filter == 3 and not playing):
			continue
		out.append(r)
	return out

func _listed_room(test: Callable) -> Dictionary:
	for r: Dictionary in _filtered_rooms():
		if test.call(r):
			return r
	return {}

## RoomListHandler: one ResCustomGameListBoxItem per room on this page.
func _fill_rooms() -> void:
	var rows := _list_rows()
	if rows == null:
		return
	for c in rows.get_children():
		if c == _hover:
			_hover = null
		rows.remove_child(c)
		c.queue_free()
	var rooms := _filtered_rooms()
	var pages := maxi(1, ceili(rooms.size() / float(ROWS_PER_PAGE)))
	_list_page = clampi(_list_page, 0, pages - 1)
	var bg := page_root.get_node("res_dlg_custom_game_background") as OriginalUI
	bg.w("back_button").visible = _list_page > 0
	bg.w("next_button").visible = _list_page < pages - 1
	var first := _list_page * ROWS_PER_PAGE
	for i in range(first, mini(rooms.size(), first + ROWS_PER_PAGE)):
		var room: Dictionary = rooms[i]
		var row := OriginalUI.create("ResCustomGameListBoxItem")
		row.position = Vector2(0, (i - first) * 28)
		row.w("room_number").text_set(str(room["number"]))
		row.w("room_name").text_set(str(room.get("name", "")))
		row.w("icon_lock").visible = bool(room.get("locked", false))
		row.w("icon_beginner").visible = bool(room.get("beginner", false))
		row.w("game_type").text_set(text("text_33" if bool(room.get("teams", false)) else "text_32"))
		var players := int(room.get("players", 0))
		var status := text("text_23")
		if bool(room.get("playing", false)):
			status = text("text_24")
		elif players >= Room.SIZE:
			status = "FULL"
		elif bool(room.get("beginner", false)):
			status = text("text_154")
		row.w("status").text_set(status)
		row.w("max_player").text_set("%d/%d" % [players, Room.SIZE])
		row.set_checked(str(room["id"]) == _list_selected)
		row.clicked.connect(_room_row_clicked.bind(row, room))
		rows.add_child(row)

## A click chooses the room; a second click on it soon after enters (EVENT_LISTBOX_ITEM_DBLCLICK).
func _room_row_clicked(row: OriginalUI, room: Dictionary) -> void:
	var id := str(room["id"])
	var now := Time.get_ticks_msec() / 1000.0
	if _list_click[0] == id and now - float(_list_click[1]) < DOUBLE_CLICK:
		_list_click = ["", -1.0]
		_join_listed(room)
		return
	_list_click = [id, now]
	_list_selected = id
	for r in row.get_parent().get_children():
		(r as OriginalUI).set_checked(r == row)

## OnPushJoinGameButton: a locked room asks for its password first.
func _join_listed(room: Dictionary, password := "") -> void:
	if int(room.get("players", 0)) >= Room.SIZE:
		message(system_text("Room_is_full"))
		return
	var address := str(room["address"])
	joined_number = int(room["number"])
	if bool(room.get("locked", false)) and password == "":
		_password_popup(func(pw: String) -> void: room_join.emit(address, pw))
	else:
		room_join.emit(address, password)

## Room_name_Type_enter: a room number goes first, then a room name; a name that is no
## listed room but reads as an address joins that host directly.
func _quick_go(number_edit: OriginalUI, name_edit: OriginalUI, pass_edit: OriginalUI) -> void:
	var number := number_edit.text_get().strip_edges()
	var room_name := name_edit.text_get().strip_edges()
	var password := pass_edit.text_get()
	if number == "" and room_name == "":
		return
	var room := {}
	if number != "":
		room = _find_room(func(r: Dictionary) -> bool: return str(r["number"]) == number)
	else:
		room = _find_room(func(r: Dictionary) -> bool: return str(r.get("name", "")) == room_name)
		if room.is_empty() and _is_address(room_name):
			joined_number = 1
			room_join.emit(room_name, password)
			return
	if room.is_empty():
		message(system_text("room_not_exist"))
	else:
		_join_listed(room, password)

func _find_room(test: Callable) -> Dictionary:
	for r: Dictionary in lan.rooms():
		if test.call(r):
			return r
	return {}

static func _is_address(s: String) -> bool:
	return s.is_valid_ip_address() or s == "localhost" or (s.contains(".") and not s.contains(" "))

## on_page_create_game: the room name and password, the game type (single or team battle)
## and the beginner room switch, which starts on for a pilot of grade 5 or below.
func _create_room_popup() -> void:
	var pop := _add("res_dlg_custom_game_create", popup_root)
	var dlg := pop.w("dlg")
	var name_edit := dlg.w("input_name_edit")
	var pass_edit := dlg.w("input_pass_edit")
	name_edit.editor.max_length = 20
	pass_edit.editor.max_length = 15
	for e in [name_edit, pass_edit]:
		e.editor.add_theme_color_override("font_color", Color8(230, 230, 230))
	name_edit.editor.focus_next = name_edit.editor.get_path_to(pass_edit.editor)
	pass_edit.editor.focus_next = pass_edit.editor.get_path_to(name_edit.editor)
	name_edit.focus_set()
	var choice := {"teams": false, "beginner": true}
	var type_text := dlg.w("game_type_text")
	var event_text := dlg.w("event_type_text")
	type_text.text_set(text("text_32"), DARK_TEXT)
	event_text.text_set("ON", DARK_TEXT)
	dlg.w("arrow_button").clicked.connect(func() -> void:
		_choice_list(dlg, "ResTypeSelectButton", ["single_battle_button", "team_battle_button"],
			[text("text_32"), text("text_33")], type_text, dlg.w("arrow_button"),
			func(i: int) -> void: choice["teams"] = i == 1))
	dlg.w("arrow_button_3").clicked.connect(func() -> void:
		_choice_list(dlg, "ResEventSelectButton", ["event_battle_button", "no_event_battle_button"],
			["ON", "OFF"], event_text, dlg.w("arrow_button_3"),
			func(i: int) -> void: choice["beginner"] = i == 0))
	var create := func() -> void:
		var room_name := name_edit.text_get()
		# onPushCreateGameButton: no empty name and no space at either end.
		if room_name == "" or room_name.begins_with(" ") or room_name.ends_with(" "):
			message(text("text_10"))
			return
		if room_name.length() > 20:
			message(text("text_11"))
			return
		pop.queue_free()
		room_create.emit(room_name, pass_edit.text_get(), choice["teams"], choice["beginner"])
	name_edit.submitted.connect(func(_t: String) -> void: create.call())
	pass_edit.submitted.connect(func(_t: String) -> void: create.call())
	dlg.w("create_button").clicked.connect(create)
	dlg.w("cancel_button").clicked.connect(func() -> void: pop.queue_free())

## on_game_type_push_button and On_Event_type_push_button: the two choices drop down over
## the text and its arrow until one is picked.
func _choice_list(dlg: OriginalUI, table: String, keys: Array, labels: Array, shown: OriginalUI,
		arrow: OriginalUI, picked: Callable) -> void:
	if dlg.get_node_or_null(table):
		return
	var list := OriginalUI.create(table)
	dlg.add_child(list)
	shown.visible = false
	arrow.visible = false
	for i in keys.size():
		var b := list.w(keys[i])
		b.text_set(labels[i], DARK_TEXT)
		b.clicked.connect(func() -> void:
			picked.call(i)
			shown.text_set(labels[i])
			shown.visible = true
			arrow.visible = true
			dlg.remove_child(list)
			list.queue_free())

## The password box a locked room asks for (res_dlg_custom_game_information).
func _password_popup(done: Callable) -> void:
	var pop := _add("res_dlg_custom_game_information", popup_root)
	var dlg := pop.w("dlg")
	var edit := dlg.w("input_password")
	edit.editor.max_length = 15
	edit.focus_set()
	var ok := func() -> void:
		pop.queue_free()
		done.call(edit.text_get())
	edit.submitted.connect(func(_t: String) -> void: ok.call())
	dlg.w("ok_button").clicked.connect(ok)
	dlg.w("cancel_button").clicked.connect(func() -> void: pop.queue_free())

# --- Game room (page_game_room) -------------------------------------------------------------

## The game room: the room's information bar, the map banner with the master's arrows, the
## twelve slots (red 1-6 on the left, blue 7-12 on the right), the chat, START for the room
## master and Exit. view is what the game hands over (game.gd _room_view); update_game_room
## refreshes it in place.
func show_game_room(view: Dictionary) -> void:
	_clear()
	set_shown(true)
	page = "room"
	if sound and not sound.is_playing_bgm():
		sound.play_bgm(BGM_MENU)
	var bg := _add("res_dlg_game_room_background")
	var option := _add("res_dlg_game_room_game_option", bg)
	var chat := _add("res_dlg_game_room_chatting_dialog", bg)
	var users := _add("res_dlg_game_room_userlist", bg)
	bg.w("grade_up_img").visible = false
	# There is no watch mode: the arrows that switched to it go, and the label stays on fight.
	bg.w("left_arrow_button").visible = false
	bg.w("right_arrow_button").visible = false
	bg.w("start_button").tooltip = text("text_117")
	bg.w("exit_button").tooltip = text("text_122")
	bg.w("start_button").clicked.connect(func() -> void: room_start.emit())
	bg.w("exit_button").clicked.connect(func() -> void: room_exit.emit())
	option.w("back_button").clicked.connect(func() -> void: room_map.emit(-1))
	option.w("next_button").clicked.connect(func() -> void: room_map.emit(1))
	for s in Room.SIZE:
		# ChangeTeamSlot: a click on a slot asks to move there.
		_slot_window(users, s).clicked.connect(func() -> void: room_slot.emit(s))
	_console_view = Node2D.new()
	_console_view.draw.connect(_draw_console.bind(chat.w("console"), _room_lines))
	chat.w("console").add_child(_console_view)
	var edit := chat.w("input_chat_edit")
	edit.editor.max_length = 60
	var tabs := chat.w("chat_style")
	_chat_tabs(tabs, edit)
	# The waiting list, the master's room options and the beginner switch needed the server.
	for k in ["wait_list_button", "option_button", "beginner_off_button"]:
		tabs.w(k).visible = false
	edit.submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			room_chat.emit(t.strip_edges())
		edit.editor.text = "")
	chat.w("scroll_up_button").clicked.connect(func() -> void: _scroll_console(1))
	chat.w("scroll_down_button").clicked.connect(func() -> void: _scroll_console(-1))
	_autofocus(edit)
	update_game_room(view)

## The box a page starts typing in, as the original set; not on a phone, where focus brings
## up the keyboard over the page.
static func _autofocus(edit: OriginalUI) -> void:
	if not (DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")):
		edit.focus_set()

static func _slot_window(users: OriginalUI, slot: int) -> OriginalUI:
	return users.w("red_team" if slot < Room.HALF else "blue_team").w("team_seed_%d" % (slot + 1))

## SetRoomNumberAndName, handle_map_select, OnManagerChange and UpdateGameRoomUserEnterInfo:
## view has number, name, teams, playing, beginner, map (0-4), master (you run the room)
## and slots: slot -> {name, face, master, me, playing}.
func update_game_room(view: Dictionary) -> void:
	room_view = view
	if page != "room":
		return
	var bg := page_root.get_node_or_null("res_dlg_game_room_background") as OriginalUI
	if bg == null:
		return
	var teams := bool(view.get("teams", false))
	var master := bool(view.get("master", false))
	bg.w("room_number").text_set("NO %d " % int(view.get("number", 1)))
	bg.w("room_name").text_set(str(view.get("name", "")))
	bg.w("game_type").text_set(text("text_33" if teams else "text_32"))
	bg.w("status").text_set(text("text_24" if bool(view.get("playing", false)) else "text_23"))
	bg.w("is_beginner").text_set(text("text_154") if bool(view.get("beginner", false)) else "")
	# Team battle shows the red and blue marks and each side's average grade and points.
	for k in ["red_team_mark", "blue_team_mark", "average_left_img", "average_right_img"]:
		bg.w(k).visible = teams
	bg.w("average_left_img").pos_set(48, 142)
	bg.w("average_right_img").pos_set(520, 142)
	bg.w("start_button").visible = master
	var option := bg.w("res_dlg_game_room_game_option")
	option.w("back_button").visible = master
	option.w("next_button").visible = master
	option.w("game_map").texture_switch(int(view.get("map", 0)) + 1)
	var users := bg.w("res_dlg_game_room_userlist")
	users.w("vs_mark").visible = teams
	var slots: Dictionary = view.get("slots", {})
	for s in Room.SIZE:
		var slot_win := _slot_window(users, s)
		var info := slot_win.w("charactor_info_option")
		var who: Dictionary = slots.get(s, {})
		slot_win.w("close_img").texture_switch(1)
		slot_win.w("playing_img").texture_switch(2 if bool(who.get("playing", false)) else 1)
		info.visible = not who.is_empty()
		if who.is_empty():
			continue
		info.w("name").text_set(str(who.get("name", "")), MY_NAME if bool(who.get("me", false)) else Color.WHITE)
		info.w("pilot_list").texture_switch(int(who.get("face", 1)))
		info.w("grade").texture_switch(1)
		info.w("manager_mark").visible = bool(who.get("master", false))
		info.w("clan_name").text_set("")
		for k in ["zzang_mark", "observer_img", "guild_mark"]:
			info.w(k).visible = false
		info.w("start_loading").texture_switch(1)
		info.w("ping_img").texture_switch(1)

# --- Item shop (page_game_shop) --------------------------------------------------------------

## The item shop as the garage for the body chosen at character select (ShopPage).
func show_shop() -> void:
	_clear()
	set_shown(true)
	page = "shop"
	if sound:
		sound.play_bgm(BGM_SHOP)
	shop = ShopPage.new(self, body, loadout(body))
	shop.preview.connect(func(weapons: Array, slot: int) -> void: shop_view.emit(body, weapons, slot))
	shop.attack.connect(func() -> void: shop_attack.emit())
	shop.closed.connect(_close_shop)
	shop.build(_add("res_dlg_game_shop_background"))

## handle_game_shop_exit_ack: the loadout is kept and the channel (main menu) comes back.
func _close_shop() -> void:
	if shop:
		loadouts[body] = Array(shop.equipped)
		save_profile()
	show_main_menu()

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
		"room_list":
			show_main_menu()
		"shop":
			_close_shop()
		"room":
			room_exit.emit()
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
	if win.has_meta("item_tip"):
		_show_item_tip(win.get_meta("item_tip"), at)
		return
	if not tooltips_on or win.tooltip == "":
		return
	_tooltip = OriginalUI.create("res_tool_tip_on")
	_tooltip.position = at + Vector2(-50, -80)
	_tooltip.w("tool_tip_text").text_set(win.tooltip)
	popup_root.add_child(_tooltip)

## ToolTipOnEventHandler and ToolTipWindowUpdate: the shop's item popup, 180 wide and as tall
## as its text at 13 pixels a line, by the pointer for the inventory and at (367, 60)
## otherwise. GetLineCount is not in the archive; lines are counted by their breaks (inferred).
func _show_item_tip(tip: Dictionary, at: Vector2) -> void:
	_tooltip = OriginalUI.create("res_tool_tip_on_new")
	var preview_h := 13.0 * str(tip["preview"]).split("\n").size()
	var info_h := 13.0 * str(tip["info"]).split("\n").size()
	var size_y := info_h + preview_h + 30.0
	_tooltip.w("texture_center").size_set(180, size_y)
	_tooltip.w("texture_down").pos_set(0, size_y + 6)
	_tooltip.w("item_name_text").text_set(str(tip["name"]), Color8(17, 155, 234))
	for k in ["item_preview_text", "item_info_text"]:
		_tooltip.w(k).line_height = 13.0
	var preview := _tooltip.w("item_preview_text")
	preview.size_set(180, preview_h)
	preview.text_set(str(tip["preview"]), Color8(200, 200, 200))
	var info := _tooltip.w("item_info_text")
	info.pos_set(0, 35 + preview_h)
	info.size_set(180, info_h)
	info.text_set(str(tip["info"]), Color8(40, 255, 126))
	_tooltip.position = at - Vector2(250, 80) if bool(tip["inven"]) else Vector2(367, 60)
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
			var wheel := mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
			if mb.pressed and wheel and page in ["main", "room"]:
				_scroll_console(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			elif mb.pressed and wheel and shop:
				shop.wheel(_to_page(mb.position), -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
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
	if shop:
		shop.update_held()
	if _turntable and is_instance_valid(_turntable):
		_turn_time = fmod(_turn_time + dt, TURNTABLE_TIME)
		var frames := _turntable.textures.size() - 1
		if frames > 0:
			# All 32 frames: one more than texture_switch accepts, so set it directly.
			var frame := 1 + int(_turn_time / TURNTABLE_TIME * frames) % frames
			if frame != _turntable.current:
				_turntable.current = frame
				_turntable.queue_redraw()
