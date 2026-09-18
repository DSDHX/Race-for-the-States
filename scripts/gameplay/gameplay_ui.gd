extends Control
const Rules = preload("res://scripts/gameplay/match_rules.gd")
const Match = preload("res://scripts/gameplay/match_logic.gd")
var controller: Control
var simulation: RefCounted
var _spawn_candidate := ""
var _shown_round := -1
var _order_source := ""
var _order_target := ""
var _last_phase := -1
var _notice_key := ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh.call_deferred()

func is_configured() -> bool:
	return controller != null

func configure(match_controller: Control) -> void:
	controller = match_controller
	simulation = controller.match_logic
	for index in Rules.SPAWN_CHOICES:
		get_node("%%SpawnOption%d" % index).pressed.connect(_pick_spawn.bind(index))
	%ConfirmSpawn.pressed.connect(_confirm_spawn)
	%Send25.pressed.connect(_send.bind(25.0))
	%Send50.pressed.connect(_send.bind(50.0))
	%Send75.pressed.connect(_send.bind(75.0))
	%Send100.pressed.connect(_send.bind(100.0))
	%NoticeTimer.timeout.connect(func(): %NoticePanel.hide())
	%CustomButton.pressed.connect(_show_custom)
	%CustomSend.pressed.connect(func():
		%CustomPercent.apply()
		_send(%CustomPercent.value))
	%CustomPercent.value_changed.connect(func(_value: float): _refresh_order())
	%CancelOrder.pressed.connect(dismiss_order)
	%RematchButton.pressed.connect(func(): controller.submit_action("rematch"))
	%ResultMenu.pressed.connect(_return_to_menu)
	var session := get_node_or_null("/root/GameSession")
	if session != null:
		session.command_result.connect(func(result: Dictionary): show_notice(result.message))
	simulation.changed.connect(refresh)
	refresh()

func state_name(id: String) -> String:
	return tr(str(controller.map_data.regions[id].name))

func refresh() -> void:
	if not is_configured():
		return
	if not _notice_key.is_empty():
		%Notice.text = tr(_notice_key)
	%SpawnOverlay.visible = simulation.phase == Match.Phase.SPAWN
	%ResultOverlay.visible = simulation.phase == Match.Phase.FINISHED
	if simulation.round_number != _shown_round:
		_shown_round = simulation.round_number
		_spawn_candidate = ""
		%NoticePanel.hide()
		%NoticeTimer.stop()
		_notice_key = ""
	if simulation.phase == Match.Phase.SPAWN:
		_refresh_spawn()
	elif simulation.phase == Match.Phase.FINISHED:
		dismiss_order()
		%NoticePanel.hide()
		_refresh_result()
	elif %OrderOverlay.visible:
		_refresh_order()
	if simulation.phase != _last_phase:
		if simulation.phase == Match.Phase.SPAWN:
			%SpawnOption0.grab_focus()
		elif simulation.phase == Match.Phase.FINISHED:
			%RematchButton.grab_focus()
	_last_phase = simulation.phase

func _refresh_spawn() -> void:
	var options: Array = simulation.spawn_options(controller.local_player_id)
	var choice: String = simulation.chosen_spawn(controller.local_player_id)
	for i in Rules.SPAWN_CHOICES:
		var button: Button = get_node("%%SpawnOption%d" % i)
		var id: String = options[i]
		var votes: int = int(controller.map_data.regions[id].electoral_votes)
		button.text = tr("%s%s  ·  %d 票\n+%s 力量 / 秒") % ["✓  " if id == _spawn_candidate else "", state_name(id), votes, Rules.number(Rules.growth(votes))]
		button.disabled = not choice.is_empty()
	%ConfirmSpawn.disabled = _spawn_candidate.is_empty() or not choice.is_empty()
	%ConfirmSpawn.text = tr("已确认 · 等待对手") if not choice.is_empty() else tr("确认出生州")
	%SpawnStatus.text = tr("双方候选州互不重合。选择后点击确认。") if choice.is_empty() else tr("已选择 %s，等待所有玩家确认（%d / %d）。") % [state_name(choice), simulation.ready_count(), simulation.player_count()]

func _pick_spawn(index: int) -> void:
	_spawn_candidate = simulation.spawn_options(controller.local_player_id)[index]
	_refresh_spawn()

func _confirm_spawn() -> void:
	var result: Dictionary = controller.submit_action("spawn", {"state_id": _spawn_candidate})
	if result.ok:
		if simulation.phase == Match.Phase.ACTIVE:
			controller.map_view.select_state(_spawn_candidate)
		refresh()

func show_notice(message: String) -> void:
	_notice_key = message
	%Notice.text = tr(message)
	%NoticePanel.visible = not message.is_empty() and simulation.phase == Match.Phase.ACTIVE
	if %NoticePanel.visible:
		%NoticeTimer.start()

func open_order(source: String, target: String) -> void:
	_order_source = source
	_order_target = target
	%CustomRow.hide()
	%NoticePanel.hide()
	%OrderOverlay.show()
	_refresh_order()
	%Send50.grab_focus()

func dismiss_order() -> bool:
	var was_open: bool = %OrderOverlay.visible
	%OrderOverlay.hide()
	return was_open

func _show_custom() -> void:
	%CustomRow.show()
	%CustomPercent.get_line_edit().grab_focus()
	_refresh_order()

func _refresh_order() -> void:
	if _order_source.is_empty():
		return
	var reason: String = simulation.order_error(controller.local_player_id, _order_source, _order_target, 100.0)
	if not reason.is_empty() and (simulation.phase != Match.Phase.ACTIVE or int(controller.map_state.states[_order_source].owner) != controller.local_faction_id or int(controller.map_state.states[_order_target].owner) != controller.local_faction_id):
		dismiss_order()
		show_notice(reason)
		return
	var source_force: int = int(controller.map_state.states[_order_source].units)
	var target_force: int = int(controller.map_state.states[_order_target].units)
	var friendly: bool = int(controller.map_state.states[_order_target].owner) == controller.local_faction_id
	%OrderTitle.text = (tr("增援") if friendly else tr("争取")) + " · " + state_name(_order_target)
	%OrderDetails.text = tr("%s → %s\n可派力量：%s   ·   目标力量：%s") % [state_name(_order_source), state_name(_order_target), Rules.number(source_force), Rules.number(target_force)]
	var buttons: Array[Button] = [%Send25, %Send50, %Send75, %Send100]
	for i in buttons.size():
		var percent := (i + 1) * 25
		buttons[i].text = "%d%%\n%s" % [percent, Rules.number(int(source_force * percent / 100.0))]
		buttons[i].disabled = not simulation.order_error(controller.local_player_id, _order_source, _order_target, percent).is_empty()
	%CustomSend.text = tr("派遣 ") + Rules.number(int(source_force * %CustomPercent.value / 100.0))
	%CustomSend.disabled = not simulation.order_error(controller.local_player_id, _order_source, _order_target, %CustomPercent.value).is_empty()

func _send(percent: float) -> void:
	var result: Dictionary = controller.submit_action("send", {"source": _order_source, "target": _order_target, "percent": percent})
	if result.ok:
		dismiss_order()
	show_notice(result.message)

func _refresh_result() -> void:
	var winner: int = simulation.winner_faction
	%ResultTitle.text = tr("平局") if winner == 0 else (tr("竞选胜利") if winner == controller.local_faction_id else tr("竞选落败"))
	var totals: Array[int] = controller.map_state.electoral_totals(controller.map_data.regions)
	%ResultDetails.text = tr("8 分钟结束 · 青色 %d 票 / 橙色 %d 票\n%s") % [totals[1], totals[2], tr("双方均未达到 270 票。") if winner == 0 else (tr("青色势力") if winner == 1 else tr("橙色势力")) + tr("在最终结算时达到 270 票。")]
	if winner != 0 and simulation.remaining_seconds > 0:
		%ResultDetails.text = tr("提前结束 · 青色 %d 票 / 橙色 %d 票\n%s占领全部州，提前获胜。剩余时间 %s。") % [totals[1], totals[2], tr("青色势力") if winner == 1 else tr("橙色势力"), Rules.clock_text(simulation.remaining_seconds)]
	%RematchButton.disabled = simulation.has_rematch_vote(controller.local_player_id)
	%RematchButton.text = tr("已同意 · 等待对手") if %RematchButton.disabled else tr("再开一局")
	%RematchStatus.text = tr("单人模式可立即重新选择出生州。") if simulation.player_count() == 1 else tr("双方同意后重新开局（%d / %d）。") % [simulation.rematch_count(), simulation.player_count()]

func _return_to_menu() -> void:
	var result: Error = get_node("/root/GameSession").return_to_main_menu()
	if result != OK:
		%RematchStatus.text = tr("无法返回主菜单：") + error_string(result)
