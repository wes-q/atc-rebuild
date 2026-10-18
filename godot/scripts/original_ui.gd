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

const ROOT := "res://assets/original/ui/"
const FONT_SIZE := 11
const MAX_SCREEN_TEXTURES := 32 ## Window enum, include/goi/window.h

static var _defs: Dictionary = {}
static var _textures: Dictionary = {}

var textures: Array = [null] ## 1-based, like Window::texture_set
var uvs: Array = [null]
var fixed := false
var current := 1
var wsize := Vector2.ZERO
var text := ""
var text_color := Color.WHITE
var order := 0

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
	var tex: Variant = d.get("texture")
	if tex is Dictionary:
		var list: Array = tex.get("list", [])
		var uv_list: Array = tex.get("uv_list", [])
		for i in list.size():
			win.textures.append(texture(str(list[i])))
			if i < uv_list.size() and uv_list[i] is Array:
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

func _draw() -> void:
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
	if text != "":
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, FONT_SIZE), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, text_color)
