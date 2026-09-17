extends Control
## Pages are authored in main_menu.tscn; this script only changes their state.

@onready var session: Node = get_node("/root/GameSession")
@onready var pages: Array[Control] = [%HomePage, %ModePage, %JoinPage, %LobbyPage]
var current_page := 0

func _ready() -> void:
	%PlayButton.pressed.connect(func(): show_page(1))
	%QuitButton.pressed.connect(func(): get_tree().quit())
	%HostButton.pressed.connect(_host)
	%JoinButton.pressed.connect(func(): show_page(2))
	%ModeBack.pressed.connect(func(): show_page(0))
	%JoinBack.pressed.connect(func():
		session.clear_session()
		%ConnectButton.disabled = false
		%ConnectButton.text = "连接房间"
		show_page(1))
	%ConnectButton.pressed.connect(_request_join)
	%AddressInput.text_submitted.connect(func(_address: String): _request_join())
	%LeaveButton.pressed.connect(_leave)
	%StartButton.pressed.connect(_start)
	%FactionPicker.item_selected.connect(_select_faction)
	session.room_changed.connect(_refresh_room)
	session.status_changed.connect(_network_status)
	show_page(0)
	%ConnectionNotice.text = session.status_message
	%ConnectionNotice.visible = not session.status_message.is_empty()

func show_page(index: int) -> void:
	current_page = index
	for i in pages.size():
		pages[i].visible = i == index
	var first_controls: Array[Control] = [%PlayButton, %HostButton, %AddressInput, %FactionPicker]
	first_controls[index].grab_focus()

func _host() -> void:
	%HostPort.apply()
	if session.create_room(int(%HostPort.value)) == OK:
		show_page(3)

func _leave() -> void:
	session.clear_session()
	show_page(1)

func _select_faction(index: int) -> void:
	session.set_player_faction(session.local_player_id, %FactionPicker.get_item_id(index))

func _refresh_room() -> void:
	var players: Dictionary = session.get_players()
	if not players.has(session.local_player_id):
		return
	if session.phase == session.Phase.LOBBY and current_page != 3:
		show_page(3)
	%LocalName.text = "你（房主） · 选择势力" if session.is_local_host() else "你（加入者） · 选择势力"
	%RoomAddress.text = "主机地址：" + session.room_addresses() if session.is_local_host() else "已连接主机 · TCP %d" % session.room_port
	var faction_id: int = int(players[session.local_player_id].faction_id)
	%FactionPicker.select(%FactionPicker.get_item_index(faction_id))
	%FactionPicker.add_theme_color_override("font_color", Color("68dfce") if faction_id == 1 else Color("f3a66a"))
	%RoomCount.text = "%d / 2 位玩家" % players.size()
	%GuestStatus.text = "等待另一位玩家加入…"
	for player_id: int in players:
		if player_id != session.local_player_id:
			%GuestStatus.text = "%s\n%s" % [players[player_id].name, session.faction_name(int(players[player_id].faction_id))]
	var reason: String = session.start_block_reason()
	%StartButton.disabled = not reason.is_empty()
	%StartButton.text = ("单人启动游戏" if players.size() == 1 else "开始对局") if session.is_local_host() else "等待房主开始"
	%LobbyStatus.text = reason if not reason.is_empty() else ("可以等待对手，也可以直接单人进入地图。" if players.size() == 1 else "双方势力不同，可以开始对局。")
	%LobbyStatus.add_theme_color_override("font_color", Color("f3a66a") if not reason.is_empty() else Color("a3b6c4"))

func _request_join() -> void:
	var result: Error = session.request_join(%AddressInput.text)
	if result == ERR_INVALID_PARAMETER:
		%JoinStatus.text = "请输入主机地址。" if %AddressInput.text.strip_edges().is_empty() else "请输入有效 IPv4 地址，可附加 :端口。"
	else:
		%JoinStatus.text = session.status_message
	%ConnectButton.disabled = session.connecting
	%ConnectButton.text = "正在连接…" if session.connecting else "连接房间"

func _network_status(message: String) -> void:
	%ConnectionNotice.text = message
	%ConnectionNotice.visible = not message.is_empty()
	%JoinStatus.text = message
	%ConnectButton.disabled = session.connecting
	%ConnectButton.text = "正在连接…" if session.connecting else "连接房间"
	if session.phase == session.Phase.MENU and current_page == 3:
		show_page(2)

func _start() -> void:
	var result: Error = session.start_match()
	if result != OK:
		%LobbyStatus.text = session.start_block_reason() if result == ERR_UNAUTHORIZED else "无法载入对局：" + error_string(result)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and current_page != 0:
		get_viewport().set_input_as_handled()
		if current_page == 3:
			_leave()
		else:
			if current_page == 2:
				session.clear_session()
				%ConnectButton.disabled = false
				%ConnectButton.text = "连接房间"
			show_page(0 if current_page == 1 else 1)
