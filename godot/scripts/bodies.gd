class_name Bodies
extends RefCounted
## The five bodies and what each loads in battle, read from the original tables:
## rcPlayer::create and each class's init (models, damage clips), weapon_parameter.lua
## (per-body animation files and the held weapon), weapon_mode_parameter.lua (bullet and
## effect models, sounds) and character_mapping_parameter.lua (colour schemes).
## Every archive model is converted to assets/original/x/<path>.gltf (tools/convert_original.py).

const ROOT := "res://assets/original/"
const NAMES: Array[String] = ["zeid", "redkite", "gigas", "deff", "alicia"]
const TITLES := {"zeid": "Zeid", "redkite": "Red Kite", "gigas": "Gigas", "deff": "Deff", "alicia": "Alicia"}
## Battle models load from anim04; Alicia reuses Deff's damage clips.
const MODELS := {
	"zeid": "anim04/zeid_model_middle.x",
	"redkite": "anim04/redkite_model_middle.x",
	"gigas": "anim04/gigas_model_middle.x",
	"deff": "anim04/deff_model_middle.x",
	"alicia": "anim04/ali_model.x",
}
const DAMAGE := {
	"zeid": ["anim/zeid_damage01.x", "anim/zeid_damage02.x"],
	"redkite": ["anim/redkite_damage01.x", "anim/redkite_damage02.x"],
	"gigas": ["anim/gigas_damage01.x", "anim/gigas_damage02.x"],
	"deff": ["anim/deff_damage01.x", "anim/deff_damage02.x"],
	"alicia": ["anim/deff_damage01.x", "anim/deff_damage02.x"],
}
## Alicia's arrow sits in R_hand_dum beside the bow (is_arrow).
const ARROW := "anim01/ali_hwasal.x"
## Armor::init moves shield weapons out of the slots (ES and SS types).
const SHIELD_TYPES := [5, 6]
## Equip slots by Shop_List ItemSubtype: sword, gun, heavy, special, then the shield.
const SLOT_NAMES: Array[String] = ["Sword", "Gun", "Heavy", "Special"]
## NetManager default_item_info and the server's InitEquipItemByRobot: each body's loadout as
## [sword, gun, heavy, special, shield]. The client used this table, not RobotInfo's
## default weapons.
const DEFAULTS := {
	"zeid": [1, 3, 4, 17, 2],
	"redkite": [5, 6, 7, 18, 16],
	"gigas": [8, 10, 11, 19, 9],
	"deff": [14, 13, 12, 20, 15],
	"alicia": [21, 23, 24, 25, 22],
}
## Weapons whose behaviour is ported. The rest of the shop needs mechanics not in yet
## (teleport, freezing, leech bombs, the plasma wire and others) and shows as unavailable.
const PORTED: Array[int] = [1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 17, 18, 19, 20, 21, 23, 24, 25,
	26, 28, 29, 30, 31, 32, 33, 35, 37, 38, 40, 41, 43]

static var _params: Dictionary = {}
static var _clips: Dictionary = {}

static func _load() -> void:
	if not _params.is_empty():
		return
	var f := FileAccess.open(ROOT + "ui/parameters.json", FileAccess.READ)
	if f:
		_params = JSON.parse_string(f.get_as_text())
	var c := FileAccess.open(ROOT + "clips.json", FileAccess.READ)
	if c:
		_clips = JSON.parse_string(c.get_as_text())

## Archive path ("'.\\anim\\kite2.x'") to its converted name ("x/anim/kite2").
static func x_name(rel: String) -> String:
	var norm := rel.replace("\\", "/").to_lower()
	while norm.begins_with("./") or norm.begins_with("/"):
		norm = norm.substr(norm.find("/") + 1)
	return "x/" + norm.get_basename()

## The converted scene for an archive model path, or "" when there is none.
static func scene_path(rel: String) -> String:
	if rel == "":
		return ""
	var p := ROOT + x_name(rel) + ".gltf"
	return p if ResourceLoader.exists(p) else ""

## Clip lengths of a converted model file, in clip order.
static func clip_lengths(rel: String) -> Array:
	_load()
	return _clips.get(x_name(rel), [])

static func face(body: String) -> int:
	return NAMES.find(body) + 1

static func weapon_param(id: int) -> Dictionary:
	_load()
	return _params.get("weapon_parameter", {}).get("Weapon_%d" % id, {})

## The weapon's first mode table (rc_Weapon starts in mode 0).
static func mode_param(id: int) -> Dictionary:
	var modes: Array = weapon_param(id).get("mode", [])
	if modes.is_empty():
		return {}
	return _params.get("weapon_mode_parameter", {}).get(str(modes[0]), {})

static var _shop: Array = []

## Shop_List rows that sell a weapon (ItemType 1, Enable 1), as the server loaded them.
static func _shop_weapons() -> Array:
	if _shop.is_empty():
		var f := FileAccess.open(GameData.DATA_DIR + "Shop_List.json", FileAccess.READ)
		if f:
			for r in JSON.parse_string(f.get_as_text()):
				if int(r.get("ItemType", 0)) == 1 and int(r.get("Enable", 0)) == 1:
					_shop.append(r)
	return _shop

## IsEnableEquip: the weapons a body may put in an equip slot (0 sword to 3 special),
## default first. Shop_List's Robot column is a mask: 1 Zeid, 2 Red Kite, 4 Gigas, 8 Deff,
## 16 Alicia. Every row's grade is 6, so rank never stands in the way.
static func choices(body: String, slot: int) -> Array[int]:
	var out: Array[int] = [int(DEFAULTS[body][slot])]
	var bit := 1 << NAMES.find(body)
	for r in _shop_weapons():
		var id := int(r["ItemID"])
		if int(r.get("ItemSubtype", 0)) == slot + 1 and int(r.get("Robot", 0)) & bit and not out.has(id):
			out.append(id)
	return out

## A loadout as four weapon ids in slot order, checked against the body's choices; anything
## not allowed or not ported falls back to that slot's default.
static func checked_loadout(body: String, wanted: Array) -> Array[int]:
	var out: Array[int] = []
	for slot in 4:
		var id := int(wanted[slot]) if slot < wanted.size() else 0
		if not choices(body, slot).has(id) or not PORTED.has(id):
			id = int(DEFAULTS[body][slot])
		out.append(id)
	return out

## Armor::init: the weapon slots in order, the shield kept apart (see shield_id).
static func loadout(body: String, weapons: Array = []) -> Array[int]:
	return checked_loadout(body, weapons if not weapons.is_empty() else DEFAULTS[body].slice(0, 4))

## The body's shield (player->shield). No shield was ever sold, so it is always the default.
static func shield_id(body: String) -> int:
	return int(DEFAULTS[body][4])

## Guard clips by body, take-out then defense (each class's init; not named in the tables).
const GUARD := {
	"zeid": ["anim/zeid_guard_take_out.x", "anim/zeid_guard_defense.x"],
	"redkite": ["anim/redkite_guard_take_out.x", "anim/redkite_guard_defense.x"],
	"gigas": ["anim/gigas_guard_take_out.x", "anim/gigas_guard_defense.x"],
	"deff": ["anim/deff_guard_take_out.x", "anim/deff_guard_defense.x"],
	"alicia": ["anim01/ali_guard_take_out.x", "anim01/ali_guard_defense.x"],
}

## What a body shows for one weapon: its attack and move files (weapon_parameter.lua
## <body>_animation_xfile), the held model and the frames it sits in.
static func weapon_view(body: String, id: int) -> Dictionary:
	var wp := weapon_param(id)
	var prefix := body
	var hands: Array[String] = []
	var frame := str(wp.get("frame_name_to_attach_weapon", "R_hand_dum"))
	if str(wp.get("weapon_xfile", "")) != "":
		hands.append(frame)
		if int(wp.get("number_of_weapon", 1)) == 2:
			hands.append("L_hand_dum")
	return {
		"attack": str(wp.get(prefix + "_animation_xfile", "")),
		"move": str(wp.get(prefix + "_move_animation_xfile", "")),
		"held": str(wp.get("weapon_xfile", "")),
		"hands": hands,
		"arrow_frame": str(wp.get("frame_name_to_attach_second_weapon", "")) if int(wp.get("is_arrow", 0)) == 1 else "",
	}

## character_mapping_parameter.lua: mapping 0 is the model's own texture, 1 and 2 these.
static func skins(body: String) -> Array[String]:
	_load()
	var out: Array[String] = [""]
	for s in _params.get("character_mapping_parameter", {}).get(body, {}).get("mapping_list", []):
		out.append(ROOT + x_name(str(s)) + ".png")
	return out

## combo_parameter.lua: a sword command combo by combo_id, or {} for none (id 1, a plain
## queued swing, has no entry).
static func combo_param(id: int) -> Dictionary:
	_load()
	for c in _params.get("combo_parameter", []):
		if int(c.get("combo_id", 0)) == id:
			return c
	return {}

## weapon_mode_parameter.lua sound_file: weapon change, hit, each bullet or swing.
static func sounds(id: int) -> Array:
	var s: Array = mode_param(id).get("sound_file", [])
	var out := []
	for i in 3:
		out.append(str(s[i]) if i < s.size() else "")
	return out
