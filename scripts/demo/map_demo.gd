extends Control
## Core map scene: bind authored map and score views to independent match state.

const DataScript = preload("res://scripts/map/map_data.gd")
const StateScript = preload("res://scripts/map/map_state.gd")
@export var initial_state_id := ""
var map_data = DataScript.new()
var map_state = StateScript.new()
var selected_id := ""
## Player -> faction mapping from the lobby; owner IDs in MapState are factions.
## Empty when running this scene directly with F6.
var match_config: Dictionary = {}
var local_faction_id := 1
@onready var map_view: Control = %USMap
@onready var scores: Control = %Scores

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
	map_state.reset(map_data.regions.keys())
	map_view.configure(map_data, map_state)
	map_view.state_selected.connect(_on_selected)
	map_state.changed.connect(_refresh_scores)
	_refresh_scores()
	if not initial_state_id.is_empty():
		map_view.select_state(initial_state_id)

func _on_selected(state_id: String) -> void:
	selected_id = state_id

func _refresh_scores() -> void:
	scores.set_totals(map_state.electoral_totals(map_data.regions))
