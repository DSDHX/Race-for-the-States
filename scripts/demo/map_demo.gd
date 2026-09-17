extends Control
## Core map scene: bind authored map and score views to independent match state.

const DataScript = preload("res://scripts/map/map_data.gd")
const StateScript = preload("res://scripts/map/map_state.gd")
const MatchScript = preload("res://scripts/gameplay/match_logic.gd")
@export var initial_state_id := ""
@export var gameplay_enabled := true
var map_data = DataScript.new()
var map_state = StateScript.new()
var selected_id := ""
## Player -> faction mapping from the lobby; owner IDs in MapState are factions.
## Empty when running this scene directly with F6.
var match_config: Dictionary = {}
var local_faction_id := 1
var local_player_id := 1
var match_logic: RefCounted
@onready var map_view: Control = %USMap
@onready var scores: Control = %Scores
@onready var gameplay_ui: Control = %GameplayUI

func _ready() -> void:
	var session := get_node_or_null("/root/GameSession")
	if session != null:
		match_config = session.get_match_config()
		var player_id: int = int(match_config.get("local_player_id", 0))
		var players: Dictionary = match_config.get("players", {})
		if players.has(player_id):
			local_faction_id = int(players[player_id].faction_id)
	if map_data.load_map() != OK:
		push_error("Unable to load res://data/map/us_states.json")
		return
	if gameplay_enabled and session != null and session.simulation != null:
		match_logic = session.simulation
		map_data = match_logic.data
		map_state = match_logic.state
		# The host's editor-authored map setting defines adjacency for both peers.
		if not match_logic.replica and match_logic.include_virtual_links != map_view.include_virtual_links:
			match_logic.include_virtual_links = map_view.include_virtual_links
			match_logic.changed.emit()
	else:
		map_state.reset(map_data.regions.keys())
	map_view.configure(map_data, map_state)
	map_view.state_selected.connect(_on_selected)
	map_state.changed.connect(_refresh_scores)
	_refresh_scores()
	if gameplay_enabled:
		var players: Dictionary = match_config.get("players", {1: {"name": "你", "faction_id": 1}})
		local_player_id = int(match_config.get("local_player_id", 1))
		if match_logic == null:
			match_logic = MatchScript.new()
			match_logic.include_virtual_links = map_view.include_virtual_links
			if not match_logic.setup(map_data, map_state, players):
				push_error("Invalid match roster")
				return
		map_view.include_virtual_links = match_logic.include_virtual_links
		match_logic.changed.connect(_refresh_match)
		map_view.selectable_faction = local_faction_id
		map_view.state_right_clicked.connect(_on_right_clicked)
		gameplay_ui.configure(self)
		_refresh_match()
	else:
		gameplay_ui.hide()
	if not initial_state_id.is_empty():
		map_view.select_state(initial_state_id)

func _on_selected(state_id: String) -> void:
	selected_id = state_id
	if gameplay_enabled and gameplay_ui.is_configured():
		gameplay_ui.refresh()

func _refresh_scores() -> void:
	scores.set_totals(map_state.electoral_totals(map_data.regions))

func _process(delta: float) -> void:
	var session := get_node_or_null("/root/GameSession")
	if match_logic != null and (session == null or session.simulation != match_logic):
		match_logic.advance(delta)

func submit_action(action: String, fields: Dictionary = {}) -> Dictionary:
	var session := get_node_or_null("/root/GameSession")
	if session != null and session.simulation == match_logic:
		return session.submit_action(action, fields)
	# Direct F6 scene preview retains the same single-player controls.
	match action:
		"spawn":
			return {"ok": match_logic.choose_spawn(local_player_id, fields.state_id)}
		"send":
			return match_logic.send_force(local_player_id, fields.source, fields.target, fields.percent)
		"rematch":
			return {"ok": match_logic.request_rematch(local_player_id)}
	return {"ok": false}

func _refresh_match() -> void:
	if map_view.include_virtual_links != match_logic.include_virtual_links:
		map_view.include_virtual_links = match_logic.include_virtual_links
		map_view.refresh_states()
	map_view.input_enabled = match_logic.phase == MatchScript.Phase.ACTIVE
	scores.set_remaining(match_logic.remaining_seconds)
	if not selected_id.is_empty() and int(map_state.states[selected_id].owner) != local_faction_id:
		selected_id = ""
		map_view.clear_selection()
	if match_logic.phase == MatchScript.Phase.SPAWN:
		selected_id = ""
		map_view.clear_selection()

func _on_right_clicked(state_id: String) -> void:
	var reason: String = match_logic.order_error(local_player_id, selected_id, state_id, 100.0)
	if not reason.is_empty() and match_logic.order_error(local_player_id, selected_id, state_id, 1.0).is_empty():
		reason = ""
	if not reason.is_empty():
		gameplay_ui.show_notice(reason)
		return
	gameplay_ui.open_order(selected_id, state_id)

func dismiss_order_menu() -> bool:
	return gameplay_ui.dismiss_order() if gameplay_ui.is_configured() else false
