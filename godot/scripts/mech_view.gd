class_name MechView
extends Node3D
## Draws a mech with the original Zeid model, animation clips and SR-3 rifle.
## Placement follows rcPlayer::rotationSet: scale, then the rotation table built in
## rcManager.cpp (astRotateMatrixManager), mapped into Godot space.

const MODEL := "res://assets/original/zeid/zeid_model.gltf"
const WEAPON_CLIPS := "res://assets/original/zeid/zeid_weapon02.gltf"
const MOVE_CLIPS := "res://assets/original/zeid/zeid_weapon02_move.gltf"
const RIFLE := "res://assets/original/zeid/rifle_sr3.gltf"
## PLAYERANIM_DAMAGE and PLAYERANIM_DAMAGE_ETC (rcPlayer.cpp anim_load for the Zeid).
const DAMAGE_CLIPS := ["res://assets/original/zeid/zeid_damage01.gltf", "res://assets/original/zeid/zeid_damage02.gltf"]
## Colour schemes from character_mapping_parameter.lua. Empty keeps the model's own texture.
const SKINS := ["", "res://assets/original/zeid/zeid_p02.png", "res://assets/original/zeid/zeid_p01.png"]

## Original space (left-handed, camera on -Y) to Godot space: (x, y, z) -> (x, -y, -z).
const G := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
## Assimp mirrors .x data on Z when importing. Undo it so the table applies to original data.
static var flip_import_z := true

var model: Node3D
var player: AnimationPlayer
var rifle_muzzle: Node3D
var booster_points: Array[Node3D] = []
var _current := ""

func _init() -> void:
	model = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	player = AnimationPlayer.new()
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	var lib := AnimationLibrary.new()
	_import_clips(lib, WEAPON_CLIPS, "weapon_")
	_import_clips(lib, MOVE_CLIPS, "move_")
	for i in DAMAGE_CLIPS.size():
		_import_clips(lib, DAMAGE_CLIPS[i], "damage%d_" % i)
	player.add_animation_library("", lib)
	player.playback_default_blend_time = 0.15

	var hand := model.find_child("R_hand_dum", true, false) as Node3D
	if hand:
		var rifle := (load(RIFLE) as PackedScene).instantiate() as Node3D
		hand.add_child(rifle)
		rifle_muzzle = rifle.find_child("bullet_start", true, false) as Node3D
	for n in model.find_children("p00_base_booster*", "Node3D", true, false):
		booster_points.append(n as Node3D)
	play_stand()

## Copies clips from an animation file onto the model, retargeting tracks by bone name.
## The files share the Bip01 rig but not every intermediate node, so paths are rebuilt.
func _import_clips(lib: AnimationLibrary, path: String, prefix: String) -> void:
	var src := (load(path) as PackedScene).instantiate()
	var src_player := src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip_name in src_player.get_animation_list():
		var clip := src_player.get_animation(clip_name).duplicate() as Animation
		for t in range(clip.get_track_count() - 1, -1, -1):
			var p := clip.track_get_path(t)
			var bone := p.get_name(p.get_name_count() - 1)
			var target := model.find_child(bone, true, false)
			if target == null or target is MeshInstance3D:
				clip.remove_track(t)
				continue
			clip.track_set_path(t, NodePath(str(model.get_path_to(target)) + ":" + str(p.get_concatenated_subnames())))
		lib.add_animation(prefix + clip_name.trim_prefix("anim_"), clip)
	src.free()

## Sets position and the original's facing transform.
func place(plane_pos: Vector2, facing_deg: int) -> void:
	position = Original.to_godot(plane_pos)
	model.transform = Transform3D(facing_basis(facing_deg), Vector3.ZERO)

## rotation table entry i: RotZ(90) * RotX(zAngle) * RotY(-i), in D3D row-vector order.
## As column-vector matrices that is RotY(-i) * RotX(zAngle) * RotZ(90).
static func facing_basis(i: int) -> Basis:
	i = (i % 360 + 360) % 360
	var z_angle := i if i < 180 else 360 - i
	var m := Basis(Vector3(0, 1, 0), deg_to_rad(-i)) \
		* Basis(Vector3(1, 0, 0), deg_to_rad(z_angle)) \
		* Basis(Vector3(0, 0, 1), deg_to_rad(90))
	var f := Basis.from_scale(Vector3(1, 1, -1)) if flip_import_z else Basis.IDENTITY
	return G * m * f * Basis.from_scale(Vector3.ONE * Original.CHARACTER_SCALE)

func play_stand() -> void:
	_play("weapon_%d" % Original.ANIM_STAND, true)

func play_move(clip: int) -> void:
	_play("move_%d" % clip, true)

func play_attack() -> void:
	_play("weapon_%d" % Original.ANIM_ATTACK, false, true)

func is_attack_playing() -> bool:
	return _current == "weapon_%d" % Original.ANIM_ATTACK and player.is_playing()

## rcPlayer::damage(DAMAGE_1): one of the two hit clips at random. Skipped mid-attack.
func play_damage() -> void:
	if is_attack_playing():
		return
	_play("damage%d_0" % (randi() % 2), false, true)

## rcPlayer::update_dead: DAMAGE_EXPLOSION1 plays the first damage clip and holds.
func play_death() -> void:
	_play("damage0_0", false, true)

## True while a hit reaction or the knockout pose is playing, so movement clips wait.
func is_reacting() -> bool:
	return _current.begins_with("damage") and player.is_playing()

## Plays an effect model's own animation (the first clip), if it has one.
static func play_effect(scene: Node, loop: bool) -> void:
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap := players[0] as AnimationPlayer
	var list := ap.get_animation_list()
	if list.is_empty():
		return
	ap.get_animation(list[0]).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	ap.play(list[0])

func _play(clip: String, loop: bool, restart := false) -> void:
	if clip == _current and not restart:
		return
	if not player.has_animation(clip):
		return
	player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_current = clip
	player.play(clip)
	if restart:
		player.seek(0.0, true)

## World position of the rifle's bullet_start frame, projected onto the plane.
func muzzle_plane_pos() -> Vector2:
	if rifle_muzzle == null:
		return Original.to_plane(global_position)
	return Original.to_plane(rifle_muzzle.global_position)

## Swaps the model's texture for one of the original colour schemes.
func set_skin(index: int) -> void:
	var path: String = SKINS[index % SKINS.size()]
	if path == "" or not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			mat.albedo_texture = tex
			mi.set_surface_override_material(i, mat)
