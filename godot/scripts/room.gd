class_name Room
extends RefCounted
## The original's room and game rules for several players, as pure functions: the server's
## srv_rcroom.cpp (slots and teams), RCNetGameServer.cpp (start points), RCNetGameDef.cpp
## (GameRoom::is_game_end, get_winners_team) and page_game_room.lua (when a game may start).
## A slot is the room's team_slot: 0 to 5 on the left, 6 to 11 on the right.

const SIZE := 12 ## MAX_PC_IN_ROOM
const HALF := 6 ## one team's side of the room
const NONE := 0 ## byTeam: free-for-all
const RED := 1
const BLUE := 2

## get_team: in team battle the left half is red, the right half blue; otherwise no team.
static func team_of(slot: int, teams: bool) -> int:
	if not teams:
		return NONE
	return RED if slot < HALF else BLUE

## get_id_to_room and get_teamslot_to_room: a joiner's slot, or -1 when the room is full.
## Free-for-all takes the first free slot. Team battle puts them on the smaller side (red when
## level), falling back to the other side when that one is full.
static func join_slot(taken: Array, teams: bool) -> int:
	if not teams:
		return _first_free(taken, 0, SIZE)
	var red := 0
	var blue := 0
	for s in taken:
		if int(s) < HALF:
			red += 1
		else:
			blue += 1
	var first := _first_free(taken, 0, HALF) if blue >= red else _first_free(taken, HALF, SIZE)
	if first >= 0:
		return first
	return _first_free(taken, HALF, SIZE) if blue >= red else _first_free(taken, 0, HALF)

## change_team_slot: the first free slot on the other side, or -1 when it is full.
static func switch_slot(slot: int, taken: Array) -> int:
	return _first_free(taken, HALF, SIZE) if slot < HALF else _first_free(taken, 0, HALF)

static func _first_free(taken: Array, from: int, to: int) -> int:
	for s in range(from, to):
		if not taken.has(s):
			return s
	return -1

## page_game_room.lua: a game needs two players, and in team battle equal sides.
static func can_start(slots: Array, teams: bool) -> bool:
	if slots.size() < 2:
		return false
	if not teams:
		return true
	var red := 0
	for s in slots:
		if int(s) < HALF:
			red += 1
	return red * 2 == slots.size()

## RCNetGameServer start positions, in slot order: free-for-all draws from all 12 points,
## red from points 0-5 and blue from 6-11 (a draw below 6 becomes 6, as the server did), each
## stepping on to the next point not yet taken. Returns point by slot, -1 for empty slots.
static func start_points(slots: Array, teams: bool, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	out.resize(SIZE)
	out.fill(-1)
	var used: Array[bool] = []
	used.resize(SIZE)
	used.fill(false)
	var order := slots.duplicate()
	order.sort()
	for s in order:
		var pos := 0
		match team_of(int(s), teams):
			RED:
				pos = rng.randi() % HALF
				while used[pos]:
					pos = (pos + 1) % HALF
			BLUE:
				pos = maxi(HALF, rng.randi() % SIZE)
				while used[pos]:
					pos += 1
					if pos >= SIZE:
						pos = HALF
			_:
				pos = rng.randi() % SIZE
				while used[pos]:
					pos = (pos + 1) % SIZE
		used[pos] = true
		out[int(s)] = pos
	return out

## GameRoom::is_game_end. living_slots: the slots still standing. Free-for-all ends at one
## or none; team battle when either side is empty (the server counted every non-red as blue).
static func round_over(living_slots: Array, teams: bool) -> bool:
	if not teams:
		return living_slots.size() <= 1
	var red := 0
	var blue := 0
	for s in living_slots:
		if team_of(int(s), teams) == RED:
			red += 1
		else:
			blue += 1
	return red == 0 or blue == 0

## get_winners_team: the team of the first living slot, NONE when nobody is left. In team
## battle that side wins; with nobody left everyone loses. Free-for-all: the survivor wins.
static func winning_slots(slots: Array, living_slots: Array, teams: bool) -> Array[int]:
	var out: Array[int] = []
	if living_slots.is_empty():
		return out
	if not teams:
		for s in living_slots:
			out.append(int(s))
		return out
	var order := living_slots.duplicate()
	order.sort()
	var team := team_of(int(order[0]), teams)
	for s in slots:
		if team_of(int(s), teams) == team:
			out.append(int(s))
	return out

## Teammates never hit one another directly: rc_bullet::is_crash's team_check, the sword
## effect, lock-on (LOCKON_ENEMY) and the mines' search all skip them. Splash does not.
static func teammates(team_a: int, team_b: int) -> bool:
	return team_a != NONE and team_a == team_b

## Name, radar mark and marker colours by team (Radar::render): green, red, blue.
static func team_color(team: int) -> Color:
	match team:
		RED:
			return Color8(255, 75, 75)
		BLUE:
			return Color8(2, 198, 255)
	return Color8(93, 235, 136)
