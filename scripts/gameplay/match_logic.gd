extends RefCounted
## Authoritative local simulation; independent of scenes and transport.
## A future TCP host validates sender identity, calls commands, then broadcasts
## get_snapshot(). Only the host should call advance(); no networking here.

signal changed
const Rules = preload("res://scripts/gameplay/match_rules.gd")
enum Phase { SPAWN, ACTIVE, FINISHED }
var phase: Phase = Phase.SPAWN
var remaining_seconds := Rules.DURATION_SECONDS
var winner_faction := 0
var round_number := 0
var include_virtual_links := true
var data: RefCounted
var state: RefCounted
var _players: Dictionary = {}
var _options: Dictionary = {}
var _choices: Dictionary = {}
var _rematch_votes: Dictionary = {}
var _fractional_second := 0.0
var _rng := RandomNumberGenerator.new()

func setup(definitions: RefCounted, map_state: RefCounted, players: Dictionary, seed_value: int = -1) -> bool:
	if players.is_empty() or players.size() > 2 or definitions.regions.size() < players.size() * Rules.SPAWN_CHOICES:
		return false
	var factions: Array[int] = []
	for id: Variant in players:
		if not id is int or id <= 0 or not players[id] is Dictionary:
			return false
		var faction: int = int(players[id].get("faction_id", 0))
		if faction not in [1, 2] or factions.has(faction):
			return false
		factions.append(faction)
	data = definitions
	state = map_state
	_players = players.duplicate(true)
	if seed_value == -1:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_new_round()
	return true

func _new_round() -> void:
	phase = Phase.SPAWN
	remaining_seconds = Rules.DURATION_SECONDS
	winner_faction = 0
	round_number += 1
	_fractional_second = 0.0
	_options.clear()
	_choices.clear()
	_rematch_votes.clear()
	var ids: Array = data.regions.keys()
	ids.sort()
	# One shuffled pool, dealt alternately: no state can appear in both hands.
	for i in range(ids.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var temporary: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = temporary
	var player_ids: Array = _players.keys()
	player_ids.sort()
	for id: int in player_ids:
		_options[id] = []
	for i in Rules.SPAWN_CHOICES:
		for id: int in player_ids:
			_options[id].append(ids.pop_back())
	state.reset(data.regions.keys())
	for id: String in state.states:
		state.states[id].units = Rules.neutral_force(int(data.regions[id].electoral_votes))
	state.changed.emit()
	changed.emit()

func spawn_options(player_id: int) -> Array:
	return _options.get(player_id, []).duplicate()

func chosen_spawn(player_id: int) -> String:
	return str(_choices.get(player_id, ""))

func ready_count() -> int:
	return _choices.size()

func player_count() -> int:
	return _players.size()

func faction_for(player_id: int) -> int:
	return int(_players.get(player_id, {}).get("faction_id", 0))

func choose_spawn(player_id: int, state_id: String) -> bool:
	if phase != Phase.SPAWN or not _players.has(player_id) or _choices.has(player_id):
		return false
	if not spawn_options(player_id).has(state_id) or _choices.values().has(state_id):
		return false
	_choices[player_id] = state_id
	if _choices.size() == _players.size():
		for id: int in _choices:
			state.states[_choices[id]] = {"owner": faction_for(id), "units": Rules.STARTING_FORCE}
		phase = Phase.ACTIVE
		state.changed.emit()
	changed.emit()
	return true

func advance(delta: float) -> void:
	if phase != Phase.ACTIVE or not is_finite(delta) or delta <= 0.0:
		return
	_fractional_second += delta
	while _fractional_second >= 1.0 and phase == Phase.ACTIVE:
		_fractional_second -= 1.0
		remaining_seconds -= 1
		for id: String in state.states:
			if int(state.states[id].owner) != 0:
				state.states[id].units = mini(Rules.MAX_FORCE, int(state.states[id].units) + Rules.growth(int(data.regions[id].electoral_votes)))
		_evaluate_result()
		state.changed.emit()
		changed.emit()

func order_error(player_id: int, source: String, target: String, percent: float) -> String:
	if phase != Phase.ACTIVE:
		return "对局尚未开始或已经结束。"
	if not _players.has(player_id):
		return "无效玩家。"
	if not is_finite(percent) or percent < 1.0 or percent > 100.0:
		return "派遣比例必须在 1% 到 100% 之间。"
	if not state.states.has(source) or not state.states.has(target):
		return "请先左键选择自己的州，再右键选择相邻州。"
	if int(state.states[source].owner) != faction_for(player_id):
		return "只能从自己掌控的州派遣力量。"
	if not data.get_neighbors(source, include_virtual_links).has(target):
		return "只能向相邻州派遣力量。"
	var amount := int(floor(int(state.states[source].units) * percent / 100.0))
	if amount <= 0:
		return "该比例不足以派出力量。"
	if int(state.states[target].owner) == faction_for(player_id) and int(state.states[target].units) + amount > Rules.MAX_FORCE:
		return "目标州力量已达上限，请降低派遣比例。"
	return ""

func send_force(player_id: int, source: String, target: String, percent: float) -> Dictionary:
	var error := order_error(player_id, source, target, percent)
	if not error.is_empty():
		return {"ok": false, "message": error}
	var faction := faction_for(player_id)
	var amount := int(floor(int(state.states[source].units) * percent / 100.0))
	var defense: int = int(state.states[target].units)
	state.states[source].units -= amount
	var captured := false
	var friendly := int(state.states[target].owner) == faction
	if friendly:
		state.states[target].units += amount
	elif amount > defense:
		state.states[target] = {"owner": faction, "units": amount - defense}
		captured = true
	else:
		# A tie leaves the defender in control with zero force.
		state.states[target].units = defense - amount
	_evaluate_result()
	state.changed.emit()
	changed.emit()
	return {"ok": true, "amount": amount, "captured": captured, "friendly": friendly,
		"message": "增援已到达。" if friendly else ("成功取得该州！" if captured else "双方力量已抵消，目标州仍由原势力掌控。")}

func _evaluate_result() -> void:
	# A majority is only evaluated at the deadline; early leads can be reversed.
	if remaining_seconds > 0:
		return
	remaining_seconds = 0
	phase = Phase.FINISHED
	winner_faction = 0
	var totals: Array[int] = state.electoral_totals(data.regions)
	for faction in [1, 2]:
		if totals[faction] >= Rules.VICTORY_VOTES:
			winner_faction = faction
			phase = Phase.FINISHED
			return

func request_rematch(player_id: int) -> bool:
	if phase != Phase.FINISHED or not _players.has(player_id) or _rematch_votes.has(player_id):
		return false
	_rematch_votes[player_id] = true
	if _rematch_votes.size() == _players.size():
		_new_round()
	else:
		changed.emit()
	return true

func has_rematch_vote(player_id: int) -> bool:
	return _rematch_votes.has(player_id)

func rematch_count() -> int:
	return _rematch_votes.size()

func force_total(faction: int) -> int:
	var total := 0
	for item: Dictionary in state.states.values():
		if int(item.owner) == faction:
			total += int(item.units)
	return total

func growth_total(faction: int) -> int:
	var total := 0
	for id: String in state.states:
		if int(state.states[id].owner) == faction:
			total += Rules.growth(int(data.regions[id].electoral_votes))
	return total

func get_snapshot() -> Dictionary:
	# Host/debug snapshot; do not send every player's private spawn hand to clients.
	return {"phase": phase, "remaining_seconds": remaining_seconds, "winner_faction": winner_faction,
		"round_number": round_number, "players": _players.duplicate(true), "options": _options.duplicate(true),
		"choices": _choices.duplicate(true), "rematch_votes": _rematch_votes.duplicate(true), "states": state.get_snapshot()}
