class_name OriginalUI
extends Node2D
## One window of the original engine's UI (engine/core/window.cpp), built from a resource
## table in script/res/*.lua that tools/extract_ui.py exported to windows.json.
##
## A window has a position relative to its parent, a size, and a list of textures with one
## shown at a time (texture_switch, 1-based). Window::draw_self picks how to draw it:
## a uv rect draws that part of the image at its own pixel size, "fixedsize" draws the whole
## image unscaled, anything else stretches the image over the window. A negative size
## stretches the other way, which the gauges use to grow upward from their base.
## Coordinates are the original's 800x600 screen. A Node2D rather than a Control: Godot culls
## a Control by its own rect, which hid windows whose origin sits just off-screen.
##
## The front end's controls follow engine/core/dialog.cpp: a push button shows texture 1, 2
## under the pointer and 3 while held, and plays select_button when let go; a check button
## shows 3 while checked, and so does a list row while it is the chosen one; a highlight button draws its label over the selectlight glow, which
## grows when the pointer comes in and flashes out when pressed. An edit box is a real text
## field (so phones get their keyboard) with no frame of its own: the art draws the box.

const ROOT := "res://assets/original/ui/"
const FONT_SIZE := 11
const MAX_SCREEN_TEXTURES := 32 ## Window enum, include/goi/window.h
## Window::text_color's default, RGB(212, 212, 212).
const TEXT_COLOR := Color8(212, 212, 212)
## screen_texture.cpp's GDI fonts by index: face, height in pixels, bold. The Windows faces are
## not in the archive; the nearest ones the system has stand in (gulim and the misspelled
## "thahoma", which Windows replaced, become a plain sans).
const FONTS := [
	[["Gulim", "Arial", "Helvetica", "Roboto"], 11.5, false], ## 0 DEFAULT
	[["Dotum", "Arial", "Helvetica", "Roboto"], 10.5, false],
	[["Gulim", "Arial", "Helvetica", "Roboto"], 14.0, true], ## 2 BOLD
	[["Gulim", "Arial", "Helvetica", "Roboto"], 10.5, true],
	[["Verdana", "DejaVu Sans", "Roboto"], 12.5, false],
	[["Verdana", "DejaVu Sans", "Roboto"], 10.5, true],
	[["Tahoma", "Arial", "Roboto"], 12.5, false],
	[["Tahoma", "Arial", "Roboto"], 10.5, true],
	[["Impact", "Arial Black", "Roboto"], 11.0, true], ## 8 MANG9TH
	[["Tahoma", "Arial", "Roboto"], 20.0, true], ## 9 GAME_RESULT_PAGE (the login boxes)
	[["Impact", "Arial Black", "Roboto"], 11.0, false], ## 10 CLAN
]
const SELECT_LIGHT := "ui/widget/selectlight.png"
## Plays UI sounds for every window; the front end sets it.
static var sound: Callable
static var _fonts: Dictionary = {}

static var _defs: Dictionary = {}
static var _textures: Dictionary = {}

var textures: Array = [null] ## 1-based, like Window::texture_set
var uvs: Array = [null]
var fixed := false
var current := 1
var wsize := Vector2.ZERO
var text := ""
var text_color := TEXT_COLOR
var order := 0
## The table's type: WINDOW_PUSHBUTTON, WINDOW_HIGHLIGHT_BUTTON, WINDOW_EDITBOX and so on.
var kind := ""
var font_index := 0
## DrawText flags from the table's text_format: DT_CENTER, DT_VCENTER, DT_WORDBREAK.
var text_format: Array = []
## Tooltip text, shown by the front end while the pointer rests here (ToolTipOn).
var tooltip := ""
## Check buttons: drawn with texture 3 while checked.
var checked := false
var disabled := false
var hovered := false
var held := false
## A push, check or highlight button was let go with the pointer still on it.
signal clicked
## Highlight buttons: the glow's size, animating toward a target (Window::morph_size).
var highlight_size := Vector2.ZERO
var _glow := Vector2.ZERO
var _glow_shown := false
var _glow_from := Vector2.ZERO
var _glow_to := Vector2.ZERO
var _glow_time := 0.0
var _glow_left := 0.0
## Edit boxes: the text field behind it.
var editor: LineEdit
## Edit boxes: Return was pressed in it (EVENT_EDITBOX_KEY_RETURN).
signal submitted(text: String)

## Builds a whole dialog tree by its Lua table name, e.g. "res_dlg_game_fight_weapon_dialog".
static func create(table: String) -> OriginalUI:
	_load_defs()
	if not _defs.has(table):
		push_error("UI table %s is not exported; run tools/extract_ui.py" % table)
		return OriginalUI.new()
	return _build(table, _defs[table])

## One child window of a dialog built on its own, like the guard gauge in
## res_dlg_game_fight_background, which the original moves to follow the mech.
static func create_child(table: String, key: String) -> OriginalUI:
	_load_defs()
	var kids: Variant = _defs.get(table, {}).get("child", {})
	if not (kids is Dictionary and kids.get(key) is Dictionary):
		push_error("UI window %s.%s is not exported; run tools/extract_ui.py" % [table, key])
		return OriginalUI.new()
	return _build(key, kids[key])

static func available() -> bool:
	_load_defs()
	return not _defs.is_empty()

static func _load_defs() -> void:
	if not _defs.is_empty():
		return
	var f := FileAccess.open(ROOT + "windows.json", FileAccess.READ)
	if f:
		_defs = JSON.parse_string(f.get_as_text())

static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _textures.has(path):
		_textures[path] = load(ROOT + path) if ResourceLoader.exists(ROOT + path) else null
	return _textures[path]

static func _build(node_name: String, d: Dictionary) -> OriginalUI:
	var win := OriginalUI.new()
	win.name = node_name
	var pos: Variant = d.get("pos")
	if pos is Array:
		win.position = Vector2(pos[0], pos[1])
	var size_v: Variant = d.get("size")
	if size_v is Array:
		win.wsize = Vector2(size_v[0], size_v[1])
	win.order = int(d.get("order", 0))
	win.text = str(d.get("text", ""))
	win.kind = str(d.get("type", ""))
	var tf: Variant = d.get("text_format")
	if tf is Array:
		win.text_format = tf
	var hs: Variant = d.get("highlight_size")
	if hs is Array:
		win.highlight_size = Vector2(hs[0], hs[1])
	var tc: Variant = d.get("text_color")
	if tc is Array and tc.size() >= 3:
		win.text_color = Color8(int(tc[0]), int(tc[1]), int(tc[2]))
	if win.kind == "WINDOW_EDITBOX":
		win._make_editor(int(d.get("password", 0)) == 1)
	var tex: Variant = d.get("texture")
	if tex is Dictionary:
		var list: Array = tex.get("list", [])
		var uv_list: Array = tex.get("uv_list", [])
		for i in list.size():
			win.textures.append(texture(str(list[i])))
			if i < uv_list.size() and uv_list[i] is Array and (uv_list[i] as Array).size() == 4:
				var u: Array = uv_list[i]
				win.uvs.append(Rect2(u[0], u[1], u[2] - u[0], u[3] - u[1]))
			else:
				win.uvs.append(null)
		win.fixed = int(tex.get("fixedsize", 0)) != 0
	var kids: Variant = d.get("child")
	if kids is Dictionary:
		var built: Array[OriginalUI] = []
		for key in kids.get("@order", []):
			if kids[key] is Dictionary:
				built.append(_build(str(key), kids[key]))
		# child_sort_by_order: drawn lowest order first. Within one order the original kept
		# Lua's hash order, which is not recoverable; text windows go last so a name is not
		# hidden under a face (inferred).
		var sorted := built.duplicate()
		sorted.sort_custom(func(a: OriginalUI, b: OriginalUI) -> bool:
			if a.order != b.order:
				return a.order < b.order
			if (a.text != "") != (b.text != ""):
				return b.text != ""
			return built.find(a) < built.find(b))
		for c in sorted:
			win.add_child(c)
	return win

## Child window by its Lua key, like page.weapon.recharge_img.
func w(key: String) -> OriginalUI:
	return get_node_or_null(NodePath(key)) as OriginalUI

## Window::texture_switch: any index below MAX_SCREEN_TEXTURES is accepted, and one with no
## texture behind it draws nothing.
func texture_switch(i: int) -> void:
	if i <= 0 or i >= MAX_SCREEN_TEXTURES:
		return
	if i != current:
		current = i
		queue_redraw()

func size_set(x: float, y: float) -> void:
	if wsize != Vector2(x, y):
		wsize = Vector2(x, y)
		queue_redraw()

func pos_set(x: float, y: float) -> void:
	position = Vector2(x, y)

func text_set(t: String, color := Color(-1, 0, 0)) -> void:
	if color.r >= 0.0:
		text_color = color
	if t != text:
		text = t
		queue_redraw()

## Drops the shared fonts, textures and sound hook before the engine shuts down: a static
## font still held when the text server is torn down crashes the exit.
static func release_statics() -> void:
	_fonts.clear()
	_textures.clear()
	sound = Callable()

## A GDI font slot as a Godot font and pixel size.
static func font_for(index: int) -> Array:
	var spec: Array = FONTS[clampi(index, 0, FONTS.size() - 1)]
	if not _fonts.has(index):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(spec[0])
		f.font_weight = 700 if spec[2] else 400
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_fonts[index] = f
	return [_fonts[index], int(roundf(spec[1]))]

func _make_editor(password: bool) -> void:
	editor = LineEdit.new()
	editor.secret = password
	editor.flat = true
	editor.size = wsize
	editor.context_menu_enabled = false
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "focus", "read_only"]:
		editor.add_theme_stylebox_override(st, empty)
	editor.add_theme_color_override("font_color", text_color)
	editor.add_theme_color_override("caret_color", text_color)
	editor.text_submitted.connect(func(t: String) -> void: submitted.emit(t))
	add_child(editor)
	set_font(font_index)

## Window::font_index for text and edit boxes.
func set_font(index: int) -> void:
	font_index = index
	if editor:
		var f: Array = font_for(index)
		editor.add_theme_font_override("font", f[0])
		editor.add_theme_font_size_override("font_size", f[1])
		editor.size = wsize
	queue_redraw()

func text_get() -> String:
	return editor.text if editor else text

func focus_set() -> void:
	if editor and editor.is_inside_tree():
		editor.grab_focus()

# --- Controls -----------------------------------------------------------------------------

func is_control() -> bool:
	return kind in ["WINDOW_PUSHBUTTON", "WINDOW_CHECKBUTTON", "WINDOW_HIGHLIGHT_BUTTON", "WINDOW_LISTBOXITEM"] and not disabled

## The deepest visible control under a point given in this window's parent space, searching
## the last drawn first.
func control_at(p: Vector2) -> OriginalUI:
	if not visible:
		return null
	var local := p - position
	for i in range(get_child_count() - 1, -1, -1):
		var c := get_child(i) as OriginalUI
		if c:
			var hit := c.control_at(local)
			if hit:
				return hit
	if is_control() and Rect2(Vector2.ZERO, _hit_size()).has_point(local):
		return self
	return null

func _hit_size() -> Vector2:
	var tex: Texture2D = textures[current] if current < textures.size() else null
	if wsize.x > 0.0 and wsize.y > 0.0:
		return wsize
	if uvs.size() > current and uvs[current] != null:
		return (uvs[current] as Rect2).size
	return tex.get_size() if tex else Vector2.ZERO

func mouse_in() -> void:
	hovered = true
	match kind:
		"WINDOW_PUSHBUTTON":
			texture_switch(3 if held else 2)
		"WINDOW_CHECKBUTTON", "WINDOW_LISTBOXITEM":
			if not checked:
				texture_switch(2)
		"WINDOW_HIGHLIGHT_BUTTON":
			_play("sound/ui/mousein")
			_glow_shown = true
			_morph(Vector2(100, _glow.y), Vector2(150, 15), 0.1)

func mouse_out() -> void:
	hovered = false
	match kind:
		"WINDOW_PUSHBUTTON":
			texture_switch(1)
		"WINDOW_CHECKBUTTON", "WINDOW_LISTBOXITEM":
			if not checked:
				texture_switch(1)
		"WINDOW_HIGHLIGHT_BUTTON":
			_morph(_glow, Vector2(100, 0), 0.1)

func press() -> void:
	held = true
	match kind:
		"WINDOW_PUSHBUTTON":
			texture_switch(3)
		"WINDOW_HIGHLIGHT_BUTTON":
			_morph(_glow, Vector2(400, 0), 0.2)

## The button let go; inside: the pointer is still on it, which makes it a click.
func release(inside: bool) -> void:
	if not held:
		return
	held = false
	match kind:
		"WINDOW_PUSHBUTTON":
			texture_switch(2 if inside else 1)
			if inside:
				_play("sound/ui/select_button")
		"WINDOW_HIGHLIGHT_BUTTON":
			if inside:
				_play("sound/ui/button_click")
	if inside:
		clicked.emit()

func set_checked(on: bool) -> void:
	checked = on
	texture_switch(3 if on else (2 if hovered else 1))

func _play(path: String) -> void:
	if sound.is_valid():
		sound.call(path)

func _morph(from: Vector2, to: Vector2, time: float) -> void:
	if highlight_size == Vector2.ZERO:
		highlight_size = Vector2(150, 50)
	_glow_from = from
	_glow_to = to
	_glow_time = time
	_glow_left = time
	_glow = from
	set_process(true)
	queue_redraw()

func _process(dt: float) -> void:
	if _glow_left <= 0.0:
		set_process(false)
		return
	_glow_left = maxf(0.0, _glow_left - dt)
	_glow = _glow_to.lerp(_glow_from, _glow_left / _glow_time)
	queue_redraw()

func _ready() -> void:
	set_process(false)

func _draw() -> void:
	# Highlight buttons: the glow behind the label, centred on the button (ALIGN_CENTER).
	if kind == "WINDOW_HIGHLIGHT_BUTTON" and _glow_shown and _glow.x > 0.0 and _glow.y > 0.0:
		var light := texture(SELECT_LIGHT)
		if light:
			var size := _hit_size()
			draw_texture_rect(light, Rect2((size - _glow) * 0.5, _glow), false)
	var tex: Texture2D = textures[current] if current < textures.size() else null
	if tex:
		var uv: Variant = uvs[current]
		if uv != null:
			var r: Rect2 = uv
			draw_texture_rect_region(tex, Rect2(Vector2.ZERO, r.size), r)
		elif fixed:
			draw_texture(tex, Vector2.ZERO)
		else:
			var r := Rect2(Vector2.ZERO, wsize).abs()
			if r.size.x > 0.0 and r.size.y > 0.0:
				draw_texture_rect(tex, r, false)
	if text != "" and editor == null:
		_draw_text()

## Window::draw_text: DrawText into the window's rect with its flags.
func _draw_text() -> void:
	var f: Array = font_for(font_index)
	var font: Font = f[0]
	var size: int = f[1]
	var align := HORIZONTAL_ALIGNMENT_CENTER if text_format.has("DT_CENTER") else HORIZONTAL_ALIGNMENT_LEFT
	var width := wsize.x if wsize.x > 0.0 else -1.0
	var lines: PackedStringArray = [text]
	if text_format.has("DT_WORDBREAK") and width > 0.0:
		lines = _wrap(font, size, width)
	var line_h := font.get_height(size)
	var top := 0.0
	# DrawText centres vertically only with DT_SINGLELINE; wrapped text starts at the top.
	if text_format.has("DT_VCENTER") and text_format.has("DT_SINGLELINE") and wsize.y > 0.0:
		top = (wsize.y - line_h * lines.size()) * 0.5
	for i in lines.size():
		draw_string(font, Vector2(0, top + font.get_ascent(size) + line_h * i), lines[i], align, width, size, text_color)

func _wrap(font: Font, size: int, width: float) -> PackedStringArray:
	var out: PackedStringArray = []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var trial := word if line == "" else line + " " + word
			if line != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				out.append(line)
				line = word
			else:
				line = trial
		out.append(line)
	return out
