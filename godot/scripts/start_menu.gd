class_name StartMenu
extends CanvasLayer
## Practice, host or join, and the arena and mode for practice or hosting (the joining player
## gets the host's). Command-line arguments skip this: -- practice, -- host, -- join <ip>,
## map=<id>, body=<name>, teams.

signal practice_chosen
signal host_chosen
signal join_chosen(address: String)

var _address: LineEdit
var _message: Label
var _map: OptionButton
var _map_ids: Array[String] = []

## Arena picked in the menu, as a map id.
var map_id := "space"
## Body picked in the menu.
var body_id := "zeid"
var _body: OptionButton
## Weapons picked for the body, in slot order (sword, gun, heavy, special).
var loadout: Array[int] = []
var _slots: Array[OptionButton] = []
var _slot_ids: Array = [] ## per slot, the weapon id behind each item
## The room's game type for hosting (page_custom_game game_type_select): team battle or not.
var team_mode := false
var _mode: OptionButton

func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.03, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(480, 0)
	box.position -= Vector2(240, 250)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "ATC RAYCRASH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.6, 0.85, 1))
	box.add_child(title)

	# Room map choice, in the room's order (page_game_room.lua handle_map_select).
	var map_row := HBoxContainer.new()
	box.add_child(map_row)
	var map_label := Label.new()
	map_label.text = "Map"
	map_label.custom_minimum_size = Vector2(60, 0)
	map_row.add_child(map_label)
	_map = OptionButton.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in BattleMap.list():
		_map_ids.append(str(entry["id"]))
		_map.add_item(str(entry["title"]))
	_map.item_selected.connect(func(i: int) -> void: map_id = _map_ids[i])
	map_row.add_child(_map)
	select_map(map_id)

	var body_row := HBoxContainer.new()
	box.add_child(body_row)
	var body_label := Label.new()
	body_label.text = "Body"
	body_label.custom_minimum_size = Vector2(60, 0)
	body_row.add_child(body_label)
	_body = OptionButton.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for b in Bodies.NAMES:
		_body.add_item(Bodies.TITLES[b])
	_body.item_selected.connect(func(i: int) -> void:
		body_id = Bodies.NAMES[i]
		_fill_loadout([]))
	body_row.add_child(_body)

	# The garage (page_game_shop's equip slots): one weapon per category, from what the shop
	# let this body equip. Weapons whose behaviour is not ported yet are listed but disabled.
	for slot in 4:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = Bodies.SLOT_NAMES[slot]
		label.custom_minimum_size = Vector2(60, 0)
		row.add_child(label)
		var pick := OptionButton.new()
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.item_selected.connect(func(i: int) -> void: loadout[slot] = int(_slot_ids[slot][i]))
		row.add_child(pick)
		_slots.append(pick)
		_slot_ids.append([])
	select_body(body_id)

	var mode_row := HBoxContainer.new()
	box.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "Mode"
	mode_label.custom_minimum_size = Vector2(60, 0)
	mode_row.add_child(mode_label)
	_mode = OptionButton.new()
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode.add_item("Free-for-all")
	_mode.add_item("Team battle (red and blue)")
	_mode.item_selected.connect(func(i: int) -> void: team_mode = i == 1)
	mode_row.add_child(_mode)
	select_mode(team_mode)

	_button(box, "Practice against a target", func() -> void: practice_chosen.emit())
	_button(box, "Host a match (up to 12 players)", func() -> void: host_chosen.emit())

	var row := HBoxContainer.new()
	box.add_child(row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "host address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_address)
	_button(row, "Join", func() -> void: join_chosen.emit(_address.text.strip_edges()))

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	box.add_child(_message)

func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)

func select_body(id: String, weapons: Array = []) -> void:
	body_id = id
	if _body and id in Bodies.NAMES:
		_body.select(Bodies.NAMES.find(id))
	_fill_loadout(weapons)

## Fills the four slot pickers for the current body, selecting the given weapons (or the
## defaults). Each item shows the database's damage, reload and ammo.
func _fill_loadout(weapons: Array) -> void:
	loadout = Bodies.loadout(body_id, weapons)
	for slot in _slots.size():
		var pick := _slots[slot]
		pick.clear()
		_slot_ids[slot] = []
		for wid in Bodies.choices(body_id, slot):
			var w := GameData.weapon(wid)
			var ammo := "no limit" if w.ammo < 0 else "%d ammo" % w.ammo
			var text := "%s   %d dmg, %.1f s, %s" % [w.name, w.damage, w.reload, ammo]
			if not Bodies.PORTED.has(wid):
				text = "%s   (not yet)" % w.name
			pick.add_item(text)
			pick.set_item_disabled(pick.item_count - 1, not Bodies.PORTED.has(wid))
			_slot_ids[slot].append(wid)
		pick.select(_slot_ids[slot].find(loadout[slot]))

func select_mode(teams: bool) -> void:
	team_mode = teams
	if _mode:
		_mode.select(1 if teams else 0)

func select_map(id: String) -> void:
	map_id = id
	if _map and _map_ids.has(id):
		_map.select(_map_ids.find(id))

func show_message(text: String) -> void:
	_message.text = text
