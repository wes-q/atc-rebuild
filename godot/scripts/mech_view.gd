class_name MechView
extends Node3D
## Draws a mech with the original Zeid model, its three weapon sets (clips and hand models),
## the boost nozzles' particle scripts and the sword trail.
## Placement follows rcPlayer::rotationSet: scale, then the rotation table built in
## rcManager.cpp (astRotateMatrixManager), mapped into Godot space.

const MODEL := "res://assets/original/zeid/zeid_model.gltf"
## Per weapon slot: the attack file (PLAYERANIM_ATTACK1 + slot * 2), the move file (+1) and
## the model held in R_hand_dum (weapon_parameter.lua: Weapon_28, Weapon_3, Weapon_4).
const SETS := [
	{"attack": "res://assets/original/zeid/dagger.gltf", "move": "res://assets/original/zeid/zeid_weapon01_move.gltf", "hand": "res://assets/original/zeid/dagger_model.gltf"},
	{"attack": "res://assets/original/zeid/zeid_weapon02.gltf", "move": "res://assets/original/zeid/zeid_weapon02_move.gltf", "hand": "res://assets/original/zeid/rifle_sr3.gltf"},
	{"attack": "res://assets/original/zeid/zeid_weapon03.gltf", "move": "res://assets/original/zeid/zeid_weapon03_move.gltf", "hand": "res://assets/original/zeid/launcher_mml.gltf"},
]
## PLAYERANIM_DAMAGE and PLAYERANIM_DAMAGE_ETC (rcPlayer.cpp anim_load for the Zeid).
const DAMAGE_CLIPS := ["res://assets/original/zeid/zeid_damage01.gltf", "res://assets/original/zeid/zeid_damage02.gltf"]
## Colour schemes from character_mapping_parameter.lua. Empty keeps the model's own texture.
const SKINS := ["", "res://assets/original/zeid/zeid_p02.png", "res://assets/original/zeid/zeid_p01.png"]
## Weapon28_mode1: sword_effect_texture and sword_effect_dist.
const SWORD_TRAIL_TEXTURE := "res://assets/original/ui/texture/zeid_sword_jan02.png"
const SWORD_EFFECT_DIST := 80.0
## sword_effect_duration's default: how long a trail point stays.
const SWORD_TRAIL_TIME := 0.2

## Original space (left-handed, camera on -Y) to Godot space: (x, y, z) -> (x, -y, -z).
const G := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
## Assimp mirrors .x data on Z when importing. Undo it so the table applies to original data.
static var flip_import_z := true

var model: Node3D
var player: AnimationPlayer
var hands: Array[Node3D] = []
var muzzles: Array[Node3D] = []
var sword_frame: Node3D
var weapon_slot := Original.START_WEAPON
## Particle frames by group: "A0" idle nozzles, "00" boost, "D02" directional, "SHLD" shield.
var particles: Dictionary = {}
var _current := ""
var _trail: SwordTrail

func _init() -> void:
	model = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	player = AnimationPlayer.new()
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	var lib := AnimationLibrary.new()
	for i in SETS.size():
		_import_clips(lib, SETS[i]["attack"], "w%d_" % i)
		_import_clips(lib, SETS[i]["move"], "m%d_" % i)
	for i in DAMAGE_CLIPS.size():
		_import_clips(lib, DAMAGE_CLIPS[i], "damage%d_" % i)
	player.add_animation_library("", lib)
	player.playback_default_blend_time = 0.15

	var hand := model.find_child("R_hand_dum", true, false) as Node3D
	for i in SETS.size():
		var held := (load(SETS[i]["hand"]) as PackedScene).instantiate() as Node3D
		hand.add_child(held)
		hands.append(held)
		muzzles.append(held.find_child("bullet_start", true, false) as Node3D)
		ParticleFX.attach_all(held)
	sword_frame = hands[0].find_child("sword_effect", true, false) as Node3D
	particles = ParticleFX.attach_all(model)
	# rcPlayer init: the idle nozzles run; boost, directional bursts and the shield wait.
	for group in particles:
		for fx: ParticleFX in particles[group]:
			if group == "A0":
				fx.start()
			else:
				fx.stop()
	_trail = SwordTrail.new()
	_trail.texture = load(SWORD_TRAIL_TEXTURE) if ResourceLoader.exists(SWORD_TRAIL_TEXTURE) else null
	add_child(_trail)
	set_weapon(Original.START_WEAPON, false)

## Copies clips from an animation file onto the model, retargeting tracks by bone name.
## The files share the Bip01 rig but not every intermediate node, so paths are rebuilt.
func _import_clips(lib: AnimationLibrary, path: String, prefix: String) -> void:
	var src := (load(path) as PackedScene).instantiate()
	var src_player := src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip_name in src_player.get_animation_list():
		var clip := src_player.get_animation(clip_name).duplicate() as Animation
		for t in range(clip.get_track_count() - 1, -1, -1):
			var p := clip.track_get_path(t)
			var bone := str(p.get_name(p.get_name_count() - 1)).strip_edges()
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

## rcPlayer::change_weapon: the new weapon in hand and its first clip (the draw), blended in
## over 0.3 s. The original's live bullets for the mech are cleared by the caller.
func set_weapon(slot: int, animate := true) -> void:
	weapon_slot = slot
	for i in hands.size():
		hands[i].visible = i == slot
	if animate:
		player.play("w%d_0" % slot, 0.3)
		_current = "w%d_0" % slot
		player.get_animation(_current).loop_mode = Animation.LOOP_NONE
	else:
		play_stand()

func play_stand() -> void:
	_play("w%d_%d" % [weapon_slot, Original.ANIM_STAND], true)

func play_move(clip: int) -> void:
	_play("m%d_%d" % [weapon_slot, clip], true)

## Attack clip: 2 for the guns, 2 to 4 for the sword's swings.
func play_attack(clip := Original.ANIM_ATTACK) -> void:
	_play("w%d_%d" % [weapon_slot, clip], false, true)
	if weapon_slot == 0:
		_trail.begin(sword_frame, SWORD_EFFECT_DIST)

func is_attack_playing() -> bool:
	if not player.is_playing() or not _current.begins_with("w"):
		return false
	return int(_current.get_slice("_", 1)) >= Original.ANIM_ATTACK

## The weapon draw clip after a switch, which movement clips wait for.
func is_drawing() -> bool:
	return player.is_playing() and _current == "w%d_0" % weapon_slot

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

## start_booster_particle / stop_booster_particle: the "00" nozzles while boosting.
func set_boost(on: bool) -> void:
	for fx: ParticleFX in particles.get("00", []):
		if on:
			fx.start()
		else:
			fx.stop()

## rcPlayer::update_booster(dir): a nozzle pointing against the move fires its burst.
func booster_burst(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	var move := Original.to_godot(dir).normalized()
	for group in particles:
		if group == "00" or not str(group).begins_with("D"):
			continue
		for fx: ParticleFX in particles[group]:
			var frame := fx.get_parent() as Node3D
			var z := (frame.global_transform.basis * Basis.from_scale(Vector3(1, 1, -1)) * Vector3(0, 0, 1)).normalized()
			if z.dot(move) < -0.7:
				fx.start()

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
	if not clip.begins_with("w0_") or int(clip.get_slice("_", 1)) < Original.ANIM_ATTACK:
		_trail.end()

## World position of the held weapon's bullet_start frame, projected onto the plane.
func muzzle_plane_pos() -> Vector2:
	var m: Node3D = muzzles[weapon_slot] if weapon_slot < muzzles.size() else null
	if m == null:
		return Original.to_plane(global_position)
	return Original.to_plane(m.global_position)

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

## The sword trail (rc_Weapon::update_sword_trail, draw_sword_trails.cpp): each frame of a
## swing adds the blade's base and a point sword_effect_dist / HAHA_SCALE_VAL along its
## sword_effect frame; points fade after 0.2 s; drawn additive, u along time, v along the blade.
class SwordTrail extends MeshInstance3D:
	var texture: Texture2D
	var _frame: Node3D
	var _dist := 0.0
	var _points: Array = [] ## [time, base, tip]
	var _clock := 0.0
	var _mesh := ImmediateMesh.new()
	var _mat := StandardMaterial3D.new()

	func _init() -> void:
		top_level = true
		mesh = _mesh
		custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	## A new swing retires the old trail (action_id changes) and starts another.
	func begin(frame: Node3D, dist: float) -> void:
		_frame = frame
		_dist = dist
		_points.clear()
		_mat.albedo_texture = texture

	func end() -> void:
		_frame = null

	func _process(dt: float) -> void:
		_clock += dt
		if _frame and _frame.is_visible_in_tree():
			var t := _frame.global_transform
			# (0, 0, dist) in the frame's original axes, scaled by 1 / HAHA_SCALE_VAL.
			var tip := t * Vector3(0, 0, -_dist / Original.SCALE)
			var base := t.origin
			# add_segments skips a step that sweeps less than 0.07 of area.
			if _points.is_empty() or _area(_points[-1], base, tip) >= 0.07:
				_points.append([_clock, base, tip])
		while not _points.is_empty() and _points[0][0] < _clock - SWORD_TRAIL_TIME:
			_points.pop_front()
		_mesh.clear_surfaces()
		if _points.size() < 4:
			return
		var t0: float = _points[0][0]
		var span: float = maxf(_points[-1][0] - t0, 0.0001)
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
		for i in range(1, _points.size()):
			var a: Array = _points[i - 1]
			var b: Array = _points[i]
			var ua: float = (a[0] - t0) / span
			var ub: float = (b[0] - t0) / span
			var quad := [[a[1], Vector2(ua, 0)], [b[1], Vector2(ub, 0)], [a[2], Vector2(ua, 1)], [b[2], Vector2(ub, 1)]]
			for k in [0, 1, 2, 3, 2, 1]:
				_mesh.surface_set_uv(quad[k][1])
				_mesh.surface_add_vertex(quad[k][0])
		_mesh.surface_end()

	static func _area(prev: Array, base: Vector3, tip: Vector3) -> float:
		return (prev[1] - base).cross(prev[2] - base).length() + (prev[2] - base).cross(tip - base).length()
