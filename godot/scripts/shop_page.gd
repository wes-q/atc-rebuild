class_name ShopPage
extends RefCounted
## The original item shop (page_game_shop.lua, res/game_shop_background.lua) as the garage:
## the shop's list of weapons on the right, the inventory under it, and in the middle the
## robot with its equipped slots, the item's description and the robot's status.
##
## What needed CodiNET's servers and money is mapped onto this recreation:
## - Every weapon the body can use and this recreation plays is already in the inventory,
##   so BUY, SELL, the gift and cubit recharge buttons are left out and nothing costs money.
## - EQUIP puts the chosen inventory weapon into its slot (sword, gun, heavy, special) and
##   the one it replaces goes back to the inventory. DISARM puts the slot's default back,
##   since a slot is never empty in battle (InitEquipItemByRobot).
## - The armor, FM and etc. tabs list nothing: those items are not in yet.
## The page draws over the 3D robot, which the game shows behind it (game.gd _shop_stage).

## The robot's held weapon changed: the four weapons and which slot is in hand.
signal preview(weapons: Array, slot: int)
## The viewer was clicked with a usable weapon chosen: play its attack (shop_robot_ani(2)).
signal attack
## EXIT: the page is done, with equipped as the loadout to keep.
signal closed

const ROWS := 6 ## ItemList: 192 pixels of 32-pixel rows
const ROW_PITCH := 32.0
const CELL := Vector2(34, 33) ## Inven_ItemList cells
const COLUMNS := 6
const CELL_ROWS := 5
## charactor_state.weapon rows (get_charactor_state_wnd_level) and the RobotInfo columns
## Charactor_statelistHandler shows in them.
const STATE_ROWS := [["armor_point", "armor_point"], ["energy", "energy"], ["n_speed", "normal_speed"],
	["b_speed", "boost_speed"], ["energy_regen", "energy_recovery"], ["overheat_line", "energy_low_line"],
	["acceleration", "add_booster_speed"], ["max_speed", "limit_booster_speed"]]

var front: FrontEnd
var body := "zeid"
## The four equipped weapons in slot order.
var equipped: Array[int] = []
var root: OriginalUI
## The viewer's rotate and zoom hotspots while held: -1, 0 or 1 each (shop_chr_zoom_in and
## the rotate loops). The game turns and moves the robot by them.
var turn := 0
var zoom := 0
## What was clicked last (page_game_shop.current_click_item): {"from": "list", "inven" or
## "slot", "id": weapon id, "slot": equip slot}, or {} for nothing.
var chosen := {}
var _tab := "weapon"
var _list_scroll := 0
var _inven_scroll := 0

func _init(page: FrontEnd, body_name: String, weapons: Array) -> void:
	front = page
	body = body_name
	equipped = Bodies.checked_loadout(body, weapons)

## page_game_shop:create()
func build(background: OriginalUI) -> void:
	root = background
	var list := root.w("item_list")
	var inven := root.w("inventory")
	var viewer := root.w("charactor_viewer")
	var viewer_button := root.w("charactor_viewer_button")
	# No money and nothing to buy: the shop's money buttons go (see above).
	for k in ["buy_button", "sell_button", "make_a_gift_button"]:
		list.w(k).visible = false
	root.w("cubit_recharge_button").visible = false
	# The English art for the inventory buttons (is_game_text_eng); FM upgrades are not in.
	_swap_art(inven.w("equip_button"), "texture_game_shop_inventory_equip_button_eng")
	_swap_art(inven.w("disarm_button"), "texture_game_shop_inventory_disarm_button_eng")
	inven.w("disarm_button").pos_set(71, 219)
	inven.w("upgrade_button").visible = false
	inven.w("skill_button").visible = false
	root.w("game_money_edit_box").text_set("0")
	root.w("cubits_money_edit_box").text_set("0")
	viewer.w("charactor_name").text_set(front.player_name)
	viewer.w("charactor_state").w("armor").visible = false
	# The item information box is hidden at create and the shipped script never shows it
	# again; the rows' tooltips (tooltip_enable) carry each weapon's description instead.
	viewer.w("item_infomation_wnd").visible = false
	_init_state()
	# AllArmorIconHide: the body-part slots show their empty frames.
	for i in range(1, 16):
		viewer_button.w("armor_%d" % i).visible = false
	for i in range(1, 9):
		var slot := viewer_button.w("chr_use_item_slot").w("slot_%d" % i)
		slot.clickable = i <= 4
		if i <= 4:
			slot.clicked.connect(_slot_clicked.bind(i - 1))
	for k in ["left_rotate_button", "right_rotate_button", "zoom_in_button", "zoom_out_button"]:
		viewer_button.w(k).clickable = true
	viewer_button.w("ani_button").clicked.connect(func() -> void:
		if _chosen_usable():
			attack.emit())
	for tab in ["amor", "weapon", "instant", "bit"]:
		list.w(tab).clicked.connect(_list_tab.bind(tab))
		inven.w(tab).clicked.connect(func() -> void: _inven_tab(tab))
	list.w("weapon").set_checked(true)
	inven.w("weapon").set_checked(true)
	list.w("scroll_up_button").clicked.connect(func() -> void: scroll_list(-1))
	list.w("scroll_down_button").clicked.connect(func() -> void: scroll_list(1))
	inven.w("scroll_up_button").clicked.connect(func() -> void: scroll_inven(-1))
	inven.w("scroll_down_button").clicked.connect(func() -> void: scroll_inven(1))
	inven.w("equip_button").clicked.connect(equip)
	inven.w("disarm_button").clicked.connect(disarm)
	root.w("exit_button").clicked.connect(func() -> void: closed.emit())
	_fill_list()
	_fill_inven()
	_fill_slots()
	preview.emit(equipped, Original.START_WEAPON)

## new_texture_set: a button's three pictures from another texture table.
static func _swap_art(win: OriginalUI, table_name: String) -> void:
	var t := OriginalUI.table(table_name)
	var list: Array = t.get("list", [])
	if list.is_empty():
		return
	win.textures = [null]
	win.uvs = [null]
	for path in list:
		win.textures.append(OriginalUI.texture(str(path)))
		win.uvs.append(null)
	win.fixed = true
	win.queue_redraw()

## Weapon_icon_texture_set: the weapon's icon from texture_item_list_part_img.
static func set_icon(win: OriginalUI, id: int) -> void:
	var t := OriginalUI.table("texture_item_list_part_img")
	var list: Array = t.get("list", [])
	var uvs: Array = t.get("uv_list", [])
	if id <= 0 or id >= list.size() or str(list[id]) == "":
		win.textures = [null]
		win.queue_redraw()
		return
	var u: Array = uvs[id] if id < uvs.size() else []
	var uv: Variant = null
	if u.size() == 4 and float(u[2]) > float(u[0]):
		uv = Rect2(u[0], u[1], float(u[2]) - float(u[0]), float(u[3]) - float(u[1]))
	win.picture_set(str(list[id]), uv)

# --- Shop list (ItemListHandler) ------------------------------------------------------------

## The shop's weapons in its order, with isenable: 0 for this body, 1 for another body's
## (red), and here also 1 for a weapon this recreation does not play yet.
func list_items() -> Array:
	var out := []
	if _tab != "weapon":
		return out
	var rows := Bodies._shop_weapons().duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("no", 0)) < int(b.get("no", 0)))
	for r: Dictionary in rows:
		var id := int(r["ItemID"])
		out.append({"id": id, "name": str(r.get("ItemName", "")), "slot": int(r.get("ItemSubtype", 1)) - 1,
			"robots": int(r.get("Robot", 0)), "enable": 0 if usable(id) else 1})
	return out

func usable(id: int) -> bool:
	for slot in 4:
		if Bodies.choices(body, slot).has(id):
			return Bodies.PORTED.has(id)
	return false

func _list_tab(tab: String) -> void:
	_tab = tab
	for k in ["amor", "weapon", "instant", "bit"]:
		root.w("item_list").w(k).set_checked(k == tab)
	_list_scroll = 0
	_fill_list()

## The inventory's tabs light up; only weapons are carried.
func _inven_tab(tab: String) -> void:
	for k in ["amor", "weapon", "instant", "bit"]:
		root.w("inventory").w(k).set_checked(k == tab)
	_fill_inven(tab)

func scroll_list(step: int) -> void:
	_list_scroll = clampi(_list_scroll + step, 0, maxi(0, list_items().size() - ROWS))
	_fill_list()

func _fill_list() -> void:
	var list := root.w("item_list").w("ItemList")
	_empty(list)
	var items := list_items()
	for i in range(_list_scroll, mini(items.size(), _list_scroll + ROWS)):
		var item: Dictionary = items[i]
		var row := OriginalUI.create("res_item_list_listboxitem")
		row.position = Vector2(1, 4 + (i - _list_scroll) * ROW_PITCH)
		row.w("name").text_set(item["name"])
		set_icon(row.w("part"), item["id"])
		# Nothing costs money here, so the price and its currency stay blank.
		row.w("cost").text_set("")
		row.w("credit").text_set("")
		row.w("list_boxitem_state_img").texture_switch(2 if int(item["enable"]) != 0 else 1)
		row.set_meta("item_tip", item_tip(int(item["id"]), str(item["name"]), int(item["robots"]), int(item["enable"]) == 0, false))
		row.set_checked(chosen.get("from") == "list" and int(chosen.get("id", 0)) == int(item["id"]))
		row.clicked.connect(_list_clicked.bind(row, item))
		list.add_child(row)

func _list_clicked(row: OriginalUI, item: Dictionary) -> void:
	chosen = {"from": "list", "id": int(item["id"]), "slot": int(item["slot"])}
	_check_only(row)
	_show_item(int(item["id"]), int(item["robots"]), int(item["enable"]) == 0)

# --- Inventory (NewInvenItemListHandler) ------------------------------------------------------

## The weapons owned and not equipped: everything this body can use and this recreation
## plays, in slot order then id.
func inven_items() -> Array[int]:
	var out: Array[int] = []
	for slot in 4:
		var ids := Bodies.choices(body, slot).duplicate()
		ids.sort()
		for id in ids:
			if Bodies.PORTED.has(id) and not equipped.has(id) and not out.has(id):
				out.append(id)
	return out

func scroll_inven(step: int) -> void:
	var rows := ceili(inven_items().size() / float(COLUMNS))
	_inven_scroll = clampi(_inven_scroll + step, 0, maxi(0, rows - CELL_ROWS))
	_fill_inven()

func _fill_inven(tab := "weapon") -> void:
	var grid := root.w("inventory").w("Inven_ItemList")
	_empty(grid)
	if tab != "weapon":
		return
	var items := inven_items()
	var first := _inven_scroll * COLUMNS
	for i in range(first, mini(items.size(), first + COLUMNS * CELL_ROWS)):
		var id := items[i]
		var cell := OriginalUI.create("res_inven_list_listboxitem")
		var k := i - first
		cell.position = Vector2((k % COLUMNS) * CELL.x, (k / COLUMNS) * CELL.y)
		set_icon(cell.w("part"), id)
		cell.w("part").w("text").text_set("")
		# The state strips are row-sized; a cell shows only its icon and its frame.
		for s in ["inven_boxitem_state_img", "inven_disable_state_img", "disable_icon"]:
			cell.w(s).visible = false
		cell.set_meta("item_tip", item_tip(id, _name_of(id), _robots_of(id), true, true))
		cell.set_checked(chosen.get("from") == "inven" and int(chosen.get("id", 0)) == id)
		cell.clicked.connect(_inven_clicked.bind(cell, id))
		grid.add_child(cell)

func _inven_clicked(cell: OriginalUI, id: int) -> void:
	chosen = {"from": "inven", "id": id, "slot": slot_of(id)}
	_check_only(cell)
	_show_item(id, _robots_of(id), true)

func slot_of(id: int) -> int:
	for slot in 4:
		if Bodies.choices(body, slot).has(id):
			return slot
	return 0

static func _robots_of(id: int) -> int:
	for r: Dictionary in Bodies._shop_weapons():
		if int(r["ItemID"]) == id:
			return int(r.get("Robot", 0))
	return 0

# --- Equipped slots (RequestInvenEquip, RequestJointItem, RequestDisJointItem) ---------------

func _fill_slots() -> void:
	var slots := root.w("charactor_viewer_button").w("chr_use_item_slot")
	for i in 4:
		set_icon(slots.w("slot_%d" % (i + 1)), equipped[i])
		slots.w("slot_%d" % (i + 1)).set_meta("item_tip", item_tip(equipped[i], _name_of(equipped[i]), _robots_of(equipped[i]), true, false))
	# The fifth slot is the shield, which no shop ever sold (Bodies.shield_id).
	set_icon(slots.w("slot_5"), Bodies.shield_id(body))

func _slot_clicked(slot: int) -> void:
	chosen = {"from": "slot", "id": equipped[slot], "slot": slot}
	_check_only(null)
	_show_item(equipped[slot], _robots_of(equipped[slot]), true)

## EQUIP: the chosen inventory weapon into its slot.
func equip() -> void:
	if chosen.get("from") != "inven":
		front.message(front.text("text_127"))
		return
	var id := int(chosen["id"])
	var slot := slot_of(id)
	equipped[slot] = id
	chosen = {"from": "slot", "id": id, "slot": slot}
	_refresh()
	preview.emit(equipped, slot)

## DISARM: the chosen equipped slot back to the body's default.
func disarm() -> void:
	if chosen.get("from") != "slot":
		front.message(front.text("text_127"))
		return
	var slot := int(chosen["slot"])
	var fallback := int(Bodies.DEFAULTS[body][slot])
	if equipped[slot] == fallback:
		front.message(front.text("text_136"))
		return
	equipped[slot] = fallback
	chosen = {"from": "slot", "id": fallback, "slot": slot}
	_refresh()
	preview.emit(equipped, slot)

func _refresh() -> void:
	_inven_scroll = clampi(_inven_scroll, 0, maxi(0, ceili(inven_items().size() / float(COLUMNS)) - CELL_ROWS))
	_fill_list()
	_fill_inven()
	_fill_slots()

# --- The item and the robot (Run_item_preview) -------------------------------------------------

## GetToolTipText for GameShopWeaponList and GameShopItemInvenList: the name, the weapon's
## data and its description (char_info.weapon_item). The inventory's SELL PRICE line is left
## out, as nothing is sold here. When this body cannot take the weapon, the description ends
## with why: the original's text_125 for another body's, a note for one not in yet.
func item_tip(id: int, item_name: String, robots: int, ok: bool, inven: bool) -> Dictionary:
	var w := GameData.weapon_row(id)
	var preview := "ITEM TYPE %s\nDAMAGE %d\nRELOAD TIME %d\nAMMO %d\nCOST ENERGY %d" % [str(int(w.get("weapon_type", 0))),
		int(_num(w.get("damage"))), int(_num(w.get("re_load_time"))), int(_num(w.get("ammo"))), int(_num(w.get("cost_energy")))]
	var info := front.weapon_text(id)
	if not ok:
		var why := front.text("text_125") if robots & (1 << Bodies.NAMES.find(body)) == 0 else "Not in this recreation yet."
		info = why if info == "" else info + "\n" + why
	return {"name": item_name, "preview": preview, "info": info, "inven": inven}

static func _num(v: Variant) -> float:
	return float(v) if v != null else 0.0

static func _name_of(id: int) -> String:
	for r: Dictionary in Bodies._shop_weapons():
		if int(r["ItemID"]) == id:
			return str(r.get("ItemName", ""))
	return str(GameData.weapon_row(id).get("name", ""))

## The status panel and, for a usable weapon, the robot holding it (temp_equip_lua);
## otherwise the robot goes back to its loadout.
func _show_item(id: int, _robots: int, ok: bool) -> void:
	_state_update()
	if ok:
		var weapons := equipped.duplicate()
		var slot := slot_of(id)
		weapons[slot] = id
		preview.emit(weapons, slot)
	else:
		preview.emit(equipped, Original.START_WEAPON)

func _chosen_usable() -> bool:
	return not chosen.is_empty() and usable(int(chosen["id"]))

## Init_charactor_state: zeros and the level mark until something is chosen.
func _init_state() -> void:
	var panel := root.w("charactor_viewer").w("charactor_state").w("weapon")
	for row in STATE_ROWS:
		var w := panel.w(row[0])
		w.w("pre_level_point").text_set("0")
		w.w("current_level_point").text_set("0")
		w.w("level_point_img").texture_switch(3)

## Charactor_statelistHandler: the robot before and with the item. Weapons change none of
## these values, so both sides match and the mark stays level.
func _state_update() -> void:
	var panel := root.w("charactor_viewer").w("charactor_state").w("weapon")
	var r := GameData.robot_row(body)
	for row in STATE_ROWS:
		var w := panel.w(row[0])
		var v := str(int(r.get(row[1], 0)))
		w.w("pre_level_point").text_set(v)
		w.w("current_level_point").text_set(v)
		w.w("level_point_img").texture_switch(3)

# --- Helpers ----------------------------------------------------------------------------------

## The mouse wheel over a list scrolls it (EVENT_WHEEL_MOVE_UP and DOWN).
func wheel(page_pos: Vector2, step: int) -> void:
	var list := root.w("item_list")
	var inven := root.w("inventory")
	if Rect2(list.position, list.wsize).has_point(page_pos):
		scroll_list(step)
	elif Rect2(inven.position, Vector2(245, 245)).has_point(page_pos):
		scroll_inven(step)

## The viewer's hotspots held this frame (the original's rotate and zoom loops).
func update_held() -> void:
	var vb := root.w("charactor_viewer_button")
	turn = (1 if vb.w("right_rotate_button").held else 0) - (1 if vb.w("left_rotate_button").held else 0)
	zoom = (1 if vb.w("zoom_in_button").held else 0) - (1 if vb.w("zoom_out_button").held else 0)

func _check_only(win: OriginalUI) -> void:
	for list in [root.w("item_list").w("ItemList"), root.w("inventory").w("Inven_ItemList")]:
		for c in list.get_children():
			(c as OriginalUI).set_checked(c == win)

func _empty(list: OriginalUI) -> void:
	for c in list.get_children():
		if c == front._hover:
			front._hover = null
		list.remove_child(c)
		c.queue_free()
