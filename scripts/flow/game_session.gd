extends Node
## Transport-independent room state. Player IDs and faction IDs are separate.
## A future host-authoritative TCP adapter should call these methods only after
## validating the sender. This class does not open sockets or use MultiplayerAPI.

signal room_changed
signal join_requested(address: String)
signal match_started(config: Dictionary)

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE := "res://scenes/map/map_demo.tscn"
const FACTION_CYAN := 1
const FACTION_ORANGE := 2
const HOST_ID := 1
const MAX_PLAYERS := 2
enum Phase { MENU, LOBBY, MATCH }

var phase: Phase = Phase.MENU
var local_player_id := 0
var host_player_id := 0
var _players: Dictionary = {}
var _match_config: Dictionary = {}

func create_room() -> void:
	clear_session()
	phase = Phase.LOBBY
	local_player_id = HOST_ID
	host_player_id = HOST_ID
	_players[HOST_ID] = {"name": "你（房主）", "faction_id": FACTION_CYAN}
	room_changed.emit()

func request_join(address: String) -> Error:
	if phase != Phase.MENU or address.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	join_requested.emit(address.strip_edges())
	# Deliberately do not create a fake connected room.
	return ERR_UNAVAILABLE

func get_players() -> Dictionary:
	return _players.duplicate(true)

func add_player(player_id: int, display_name: String, faction_id: int) -> bool:
	if phase != Phase.LOBBY or not is_local_host() or player_id <= 0:
		return false
	if _players.has(player_id) or _players.size() >= MAX_PLAYERS or not _valid_faction(faction_id):
		return false
	_players[player_id] = {"name": display_name, "faction_id": faction_id}
	room_changed.emit()
	return true

func remove_player(player_id: int) -> bool:
	if phase != Phase.LOBBY or not is_local_host() or player_id == host_player_id or not _players.has(player_id):
		return false
	_players.erase(player_id)
	room_changed.emit()
	return true

func set_player_faction(player_id: int, faction_id: int) -> bool:
	if phase != Phase.LOBBY or not is_local_host() or not _players.has(player_id) or not _valid_faction(faction_id):
		return false
	_players[player_id]["faction_id"] = faction_id
	room_changed.emit()
	return true

func is_local_host() -> bool:
	return local_player_id > 0 and local_player_id == host_player_id

func start_block_reason() -> String:
	if phase != Phase.LOBBY or not _players.has(host_player_id):
		return "请先创建房间。"
	if not is_local_host():
		return "等待房主开始游戏。"
	var used: Array[int] = []
	for player: Dictionary in _players.values():
		var faction_id := int(player.faction_id)
		if not _valid_faction(faction_id):
			return "请先选择势力。"
		if used.has(faction_id):
			return "双方选择了相同势力，请切换势力后再开始。"
		used.append(faction_id)
	return ""

func can_start_match() -> bool:
	return start_block_reason().is_empty()

func start_match() -> Error:
	# Recheck here as well as disabling the UI button.
	if not can_start_match():
		return ERR_UNAUTHORIZED
	_match_config = {
		"players": get_players(),
		"local_player_id": local_player_id,
		"host_player_id": host_player_id,
		"solo": _players.size() == 1,
	}
	phase = Phase.MATCH
	var result := get_tree().change_scene_to_file(MATCH_SCENE)
	if result != OK:
		phase = Phase.LOBBY
		_match_config.clear()
		return result
	match_started.emit(get_match_config())
	return OK

func get_match_config() -> Dictionary:
	return _match_config.duplicate(true)

func return_to_main_menu() -> Error:
	var result := get_tree().change_scene_to_file(MENU_SCENE)
	if result == OK:
		clear_session()
	return result

func clear_session() -> void:
	phase = Phase.MENU
	local_player_id = 0
	host_player_id = 0
	_players.clear()
	_match_config.clear()
	room_changed.emit()

func faction_name(faction_id: int) -> String:
	return "青色势力 · 圆形" if faction_id == FACTION_CYAN else "橙色势力 · 三角形"

func _valid_faction(faction_id: int) -> bool:
	return faction_id in [FACTION_CYAN, FACTION_ORANGE]
