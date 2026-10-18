class_name LanRooms
extends Node
## The room list's rooms on the local network. The original asked CodiNET's server for its
## room list (ui_request_room_list); with no server, each host announces its room once a
## second by UDP broadcast, and the room list page listens and lists what it hears.
##
## A host advertises with advertise(info) and stops with stop(); a room list listens with
## listen() and reads rooms(). A room not heard from for EXPIRE seconds drops off the list.

signal changed

const PORT := 7778
const MAGIC := "atc-raycrash-room/1"
const INTERVAL := 1.0
const EXPIRE := 3.5

var _sender: PacketPeerUDP
var _info := {}
var _send_timer := 0.0
var _listener: PacketPeerUDP
## Room id (a host's random token) -> room dictionary with "address" and "seen" added.
var _rooms := {}
## wRoomPoint stand-in: rooms are numbered from 1 in the order this list first heard them.
var _numbers := {}
var _next_number := 1
var _clock := 0.0

## Host: announce this room (name, locked, teams, beginner, players, playing, port) until
## stop(). Called again whenever the room changes; the room keeps its id.
func advertise(info: Dictionary) -> void:
	info["id"] = _info.get("id", "%08x%08x" % [randi(), randi()])
	_info = info
	if _sender == null:
		_sender = PacketPeerUDP.new()
		_sender.set_broadcast_enabled(true)
		_send_timer = 0.0

func stop() -> void:
	_info = {}
	if _sender:
		_sender.close()
		_sender = null

## Room list: start hearing announcements. False when the port is taken (another copy on
## this machine already listens); a typed address still works then.
func listen() -> bool:
	if _listener:
		return true
	_listener = PacketPeerUDP.new()
	if _listener.bind(PORT) != OK:
		_listener = null
		return false
	return true

func stop_listening() -> void:
	if _listener:
		_listener.close()
		_listener = null
	_rooms.clear()

## Refresh: forget what was heard; live rooms come back within a second.
func clear() -> void:
	_rooms.clear()
	changed.emit()

## Rooms heard, by room number.
func rooms() -> Array:
	var out := _rooms.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["number"]) < int(b["number"]))
	return out

func _process(dt: float) -> void:
	_clock += dt
	if _sender and not _info.is_empty():
		_send_timer -= dt
		if _send_timer <= 0.0:
			_send_timer = INTERVAL
			_announce()
	var dirty := false
	while _listener and _listener.get_available_packet_count() > 0:
		var data := _listener.get_packet()
		var from := _listener.get_packet_ip()
		dirty = _heard(data.get_string_from_utf8(), from) or dirty
	for id in _rooms.keys():
		if _clock - float(_rooms[id]["seen"]) > EXPIRE:
			_rooms.erase(id)
			dirty = true
	if dirty:
		changed.emit()

func _announce() -> void:
	var packet := JSON.stringify({"magic": MAGIC, "room": _info}).to_utf8_buffer()
	# The whole-network broadcast, each local /24's own broadcast (some routers drop the
	# first), and this machine itself for a second copy run on the same computer.
	var targets: Array[String] = ["255.255.255.255", "127.0.0.1"]
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			var parts := a.split(".")
			targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for t in targets:
		_sender.set_dest_address(t, PORT)
		_sender.put_packet(packet)

## One announcement; true when the list changed.
func _heard(text: String, from: String) -> bool:
	# Anything else on the port is not ours; JSON.parse keeps quiet about it.
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var d: Variant = json.data
	if not (d is Dictionary and d.get("magic") == MAGIC and d.get("room") is Dictionary):
		return false
	var room: Dictionary = d["room"]
	var id := str(room.get("id", ""))
	if id == "":
		return false
	if not _numbers.has(id):
		_numbers[id] = _next_number
		_next_number += 1
	var known: Dictionary = _rooms.get(id, {})
	var entry := room.duplicate()
	# The first address heard stays: a room on this machine is heard on loopback and the LAN.
	entry["address"] = known.get("address", from)
	entry["number"] = _numbers[id]
	entry["seen"] = _clock
	var was := known.duplicate()
	was.erase("seen")
	var now := entry.duplicate()
	now.erase("seen")
	_rooms[id] = entry
	return was != now
