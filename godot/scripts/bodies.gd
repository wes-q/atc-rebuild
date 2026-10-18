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

## Armor::init: the body's default weapons with shields taken out, packed into slots 1-4.
static func loadout(body: String) -> Array[int]:
	var out: Array[int] = []
	for id in GameData.robot(body).weapons:
		if id <= 0 or out.size() >= 4:
			continue
		if GameData.weapon(id).weapon_type in SHIELD_TYPES:
			continue
		out.append(id)
	return out

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

## weapon_mode_parameter.lua sound_file: weapon change, hit, each bullet or swing.
static func sounds(id: int) -> Array:
	var s: Array = mode_param(id).get("sound_file", [])
	var out := []
	for i in 3:
		out.append(str(s[i]) if i < s.size() else "")
	return out
