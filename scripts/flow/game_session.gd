extends Node
## Persistent LAN session. Only the host owns and advances the simulation.

signal room_changed
signal join_requested(address: String)
signal match_started(config: Dictionary)
signal status_changed(message: String)
signal command_result(result: Dictionary)

const Transport = preload("res://scripts/network/lan_transport.gd")
const Match = preload("res://scripts/gameplay/match_logic.gd")
const Data = preload("res://scripts/map/map_data.gd")
const State = preload("res://scripts/map/map_state.gd")
const DEFAULT_PORT := 27845
const PROTOCOL := 1
## Bump whenever gameplay semantics or the network snapshot schema changes.
const RULESET_VERSION := 1
const GUEST_ID := 2
var transport: Node
var simulation: RefCounted
var connecting := false
var _status_key := ""
var _status_args: Array = []
var status_message: String:
	get:
		return tr(_status_key) if _status_args.is_empty() else tr(_status_key) % _status_args
var room_port := DEFAULT_PORT
var _guest_connection := 0
var _host_connection := 0
var _pending: Dictionary = {}
var _connect_started := 0
var _next_command := 0
var _last_command := 0
var _revision := 0
var _last_revision := -1
var _snapshot_pending := false
var _fingerprint := ""

func _ready() -> void:
	transport = Transport.new()
	add_child(transport)
	transport.connected.connect(_connected)
	transport.received.connect(_received)
	transport.disconnected.connect(_disconnected)
	room_changed.connect(_broadcast_room)
	# Refuse different maps/rules even if both executables speak protocol version 1.
	# Do not read .gd source files: exported projects may compile them to .gdc.
	var rules := [RULESET_VERSION, Match.Rules.DURATION_SECONDS, Match.Rules.VICTORY_VOTES,
		Match.Rules.SPAWN_CHOICES, Match.Rules.STARTING_FORCE, Match.Rules.MAX_FORCE,
		Match.Rules.NEUTRAL_BASE, Match.Rules.NEUTRAL_PER_VOTE, Match.Rules.GROWTH_BASE, Match.Rules.GROWTH_PER_VOTE]
	_fingerprint = (JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string("res://data/map/us_states.json"))) + JSON.stringify(rules)).sha256_text()

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for id: int in _pending.keys():
		if now - int(_pending[id]) > 5000:
			_pending.erase(id)
			transport.reject(id, "握手超时，请重新连接。")
	if connecting and now - _connect_started > 10000:
		_end_connection("连接超时，请检查地址、端口及防火墙。")
	if phase == Phase.MATCH and is_local_host() and simulation != null:
		simulation.advance(delta)

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

func create_room(port: int = DEFAULT_PORT) -> Error:
	clear_session()
	if port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	var error: Error = transport.listen(port)
	if error != OK:
		_set_status("无法创建房间，端口 %d 可能被占用：%s", [port, error_string(error)])
		return error
	room_port = port
	phase = Phase.LOBBY
	local_player_id = HOST_ID
	host_player_id = HOST_ID
	_players[HOST_ID] = {"name": "房主", "faction_id": FACTION_CYAN}
	room_changed.emit()
	_set_status("房间已创建，等待对手加入。")
	return OK

func request_join(address: String) -> Error:
	if phase != Phase.MENU or connecting:
		return ERR_BUSY
	var parts := address.strip_edges().split(":")
	if parts.size() > 2 or parts[0].is_empty() or not parts[0].is_valid_ip_address() or parts[0].contains(":"):
		return ERR_INVALID_PARAMETER
	var port := DEFAULT_PORT
	if parts.size() == 2:
		if not parts[1].is_valid_int() or int(parts[1]) < 1 or int(parts[1]) > 65535:
			return ERR_INVALID_PARAMETER
		port = int(parts[1])
	clear_session()
	var error: Error = transport.connect_host(parts[0], port)
	if error != OK:
		_set_status("无法连接主机：%s", [error_string(error)])
		return error
	connecting = true
	_connect_started = Time.get_ticks_msec()
	room_port = port
	_set_status("正在连接 %s:%d…", [parts[0], port])
	join_requested.emit(address.strip_edges())
	return OK

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
	if phase == Phase.LOBBY and not is_local_host() and player_id == local_player_id and _valid_faction(faction_id):
		return _send_command({"action": "faction", "faction_id": faction_id})
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
	if not _create_simulation(false):
		return ERR_INVALID_DATA
	_match_config = {
		"players": get_players(),
		"local_player_id": local_player_id,
		"host_player_id": host_player_id,
		"solo": _players.size() == 1,
	}
	phase = Phase.MATCH
	simulation.changed.connect(_broadcast_snapshot)
	if _guest_connection != 0:
		_revision += 1
		if not transport.send(_guest_connection, {"type": "start", "revision": _revision, "snapshot": simulation.snapshot_for(GUEST_ID)}):
			return ERR_CONNECTION_ERROR
	var result := get_tree().change_scene_to_file(MATCH_SCENE)
	if result != OK:
		_end_connection("无法载入对局：%s", [error_string(result)])
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
	if transport != null:
		transport.close()
	simulation = null
	connecting = false
	_guest_connection = 0
	_host_connection = 0
	_pending.clear()
	_next_command = 0
	_last_command = 0
	_revision = 0
	_last_revision = -1
	_snapshot_pending = false
	_status_key = ""
	_status_args.clear()
	phase = Phase.MENU
	local_player_id = 0
	host_player_id = 0
	_players.clear()
	_match_config.clear()
	room_changed.emit()
	status_changed.emit("")

func faction_name(faction_id: int) -> String:
	return "青色势力 · 圆形" if faction_id == FACTION_CYAN else "橙色势力 · 三角形"

func _valid_faction(faction_id: int) -> bool:
	return faction_id in [FACTION_CYAN, FACTION_ORANGE]

func _set_status(message: String, args: Array = []) -> void:
	_status_key = message
	_status_args = args.duplicate()
	status_changed.emit(status_message)

func room_addresses() -> String:
	var addresses: Array[String] = []
	for address: String in IP.get_local_addresses():
		if address.is_valid_ip_address() and not address.contains(":") and not address.begins_with("127.") and not address.begins_with("169.254."):
			addresses.append("%s:%d" % [address, room_port])
	return " / ".join(addresses) if not addresses.is_empty() else tr("127.0.0.1:%d（仅本机）") % room_port

func _connected(id: int) -> void:
	if is_local_host():
		if phase != Phase.LOBBY or _players.size() >= MAX_PLAYERS:
			transport.reject(id, "对局已开始。" if phase == Phase.MATCH else "房间已满。")
		else:
			_pending[id] = Time.get_ticks_msec()
	elif connecting:
		_host_connection = id
		transport.send(id, {"type": "hello", "protocol": PROTOCOL, "content": _fingerprint})

func _received(id: int, message: Dictionary) -> void:
	if is_local_host():
		_receive_client(id, message)
	elif id == _host_connection:
		_receive_host(message)

func _receive_client(id: int, message: Dictionary) -> void:
	if _pending.has(id):
		_pending.erase(id)
		if message.get("type") != "hello" or message.get("protocol") != PROTOCOL or message.get("content") != _fingerprint:
			transport.reject(id, "游戏版本或地图规则不同，请使用同一版本。")
			return
		if phase != Phase.LOBBY or _players.size() >= MAX_PLAYERS:
			transport.reject(id, "房间已满或对局已开始。")
			return
		_guest_connection = id
		_last_command = 0
		_players[GUEST_ID] = {"name": "对手", "faction_id": 3 - int(_players[HOST_ID].faction_id)}
		transport.send(id, {"type": "welcome", "player_id": GUEST_ID, "protocol": PROTOCOL, "players": get_players()})
		room_changed.emit()
		_set_status("对手已加入，请选择不同势力后开始。")
		return
	if id != _guest_connection:
		return
	if message.get("type") != "command" or not Match.whole(message.get("seq"), 1, 2147483647):
		transport.drop(id, "无效操作数据。")
		return
	var seq := int(message.seq)
	if seq <= _last_command:
		return # A repeated command must never spend force twice.
	_last_command = seq
	var result := _execute_command(GUEST_ID, message)
	result["type"] = "result"
	result["seq"] = seq
	transport.send(id, result)

func _read_roster(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.size() != 2:
		return {}
	var result: Dictionary = {}
	for id in [HOST_ID, GUEST_ID]:
		var entry: Variant = raw.get(str(id))
		if not entry is Dictionary or not Match.whole(entry.get("faction_id"), 1, 2):
			return {}
		result[id] = {"name": "房主" if id == HOST_ID else "对手", "faction_id": int(entry.faction_id)}
	return result

func _receive_host(message: Dictionary) -> void:
	var kind: Variant = message.get("type")
	if kind == "reject":
		_end_connection(str(message.get("message", "主机拒绝连接。")))
	elif kind == "welcome" and connecting:
		var roster := _read_roster(message.get("players"))
		if roster.is_empty() or message.get("protocol") != PROTOCOL or message.get("player_id") != GUEST_ID:
			_end_connection("收到无效房间数据。")
			return
		_players = roster
		local_player_id = GUEST_ID
		host_player_id = HOST_ID
		connecting = false
		phase = Phase.LOBBY
		_set_status("已加入房间，等待房主开始。")
		room_changed.emit()
	elif kind == "room" and phase == Phase.LOBBY:
		var roster := _read_roster(message.get("players"))
		if roster.is_empty():
			_end_connection("收到无效房间数据。")
			return
		_players = roster
		room_changed.emit()
	elif kind == "start" and phase == Phase.LOBBY:
		if not _create_simulation(true) or not _apply_snapshot_message(message):
			_end_connection("无法同步对局，请确认双方版本一致。")
			return
		_match_config = {"players": get_players(), "local_player_id": local_player_id, "host_player_id": host_player_id, "solo": false}
		phase = Phase.MATCH
		var error := get_tree().change_scene_to_file(MATCH_SCENE)
		if error != OK:
			_end_connection("无法载入对局：%s", [error_string(error)])
		else:
			match_started.emit(get_match_config())
	elif kind == "snapshot" and phase == Phase.MATCH:
		if not _apply_snapshot_message(message):
			_end_connection("收到无效对局状态，连接已关闭。")
	elif kind == "result" and message.get("ok") is bool and message.get("message") is String:
		command_result.emit(message)

func _create_simulation(as_replica: bool) -> bool:
	var definitions = Data.new()
	if definitions.load_map() != OK:
		return false
	var model = Match.new()
	if not model.setup(definitions, State.new(), _players):
		return false
	model.replica = as_replica
	simulation = model
	return true

func _apply_snapshot_message(message: Dictionary) -> bool:
	if not Match.whole(message.get("revision"), 1, 2147483647) or not message.get("snapshot") is Dictionary:
		return false
	if int(message.revision) <= _last_revision:
		return true
	if not simulation.apply_remote_snapshot(message.snapshot, local_player_id):
		return false
	_last_revision = int(message.revision)
	return true

func _broadcast_room() -> void:
	if is_local_host() and phase == Phase.LOBBY and _guest_connection != 0:
		transport.send(_guest_connection, {"type": "room", "players": get_players()})

func _broadcast_snapshot() -> void:
	# A slow frame can advance many simulation seconds. Send only the final state,
	# never hundreds of obsolete snapshots that could overflow the TCP queue.
	if not _snapshot_pending:
		_snapshot_pending = true
		_flush_snapshot.call_deferred()

func _flush_snapshot() -> void:
	_snapshot_pending = false
	if is_local_host() and phase == Phase.MATCH and _guest_connection != 0:
		_revision += 1
		transport.send(_guest_connection, {"type": "snapshot", "revision": _revision, "snapshot": simulation.snapshot_for(GUEST_ID)})

func submit_action(action: String, fields: Dictionary = {}) -> Dictionary:
	var message := fields.duplicate(true)
	message["action"] = action
	message["round"] = simulation.round_number if simulation != null else 0
	if is_local_host():
		return _execute_command(local_player_id, message)
	var sent := _send_command(message)
	return {"ok": sent, "pending": sent, "message": "操作已发送，等待主机确认。" if sent else "连接不可用。"}

func _send_command(message: Dictionary) -> bool:
	if _host_connection == 0:
		return false
	_next_command += 1
	message["type"] = "command"
	message["seq"] = _next_command
	return transport.send(_host_connection, message)

func _execute_command(player_id: int, message: Dictionary) -> Dictionary:
	if message.get("action") == "faction":
		var valid := Match.whole(message.get("faction_id"), 1, 2)
		var accepted := valid and set_player_faction(player_id, int(message.faction_id))
		return {"ok": accepted, "message": "势力已更新。" if accepted else "当前无法选择势力。"}
	if phase != Phase.MATCH or simulation == null or not Match.whole(message.get("round"), 1, 1000000) or int(message.round) != simulation.round_number:
		return {"ok": false, "message": "对局状态已改变，请重试。"}
	var accepted := false
	match message.get("action"):
		"spawn":
			if message.get("state_id") is String:
				accepted = simulation.choose_spawn(player_id, message.state_id)
		"send":
			if message.get("source") is String and message.get("target") is String and (message.get("percent") is int or message.get("percent") is float):
				return simulation.send_force(player_id, message.source, message.target, float(message.percent))
		"rematch":
			accepted = simulation.request_rematch(player_id)
	return {"ok": accepted, "message": "操作已确认。" if accepted else "操作无效或已确认，请等待对手。"}

func _disconnected(id: int, reason: String) -> void:
	_pending.erase(id)
	if is_local_host() and id == _guest_connection:
		_guest_connection = 0
		if phase == Phase.LOBBY:
			remove_player(GUEST_ID)
			_set_status("对手已离开，可等待其他玩家加入。")
		else:
			var finished: bool = simulation != null and simulation.phase == Match.Phase.FINISHED
			_end_connection("对手已离开，对局已结束。" if finished else "对手已断开，本局已结束，未计胜负。")
	elif not is_local_host() and (id == _host_connection or connecting):
		_end_connection(reason)

func _end_connection(reason: String, args: Array = []) -> void:
	var was_match := phase == Phase.MATCH
	clear_session()
	_set_status(reason, args)
	if was_match:
		get_tree().change_scene_to_file(MENU_SCENE)
