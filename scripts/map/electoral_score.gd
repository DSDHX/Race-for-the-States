@tool
extends Control
const Rules = preload("res://scripts/gameplay/match_rules.gd")
var remaining_seconds := Rules.DURATION_SECONDS
## Three native color rectangles. Ownership changes only adjust their anchors.

@export_range(1, 1000) var total_votes: int = 538:
	set(value):
		total_votes = maxi(1, value)
		_refresh()
@export_range(0, 1000) var player_one_votes: int = 0:
	set(value):
		player_one_votes = maxi(0, value)
		_refresh()
@export_range(0, 1000) var player_two_votes: int = 0:
	set(value):
		player_two_votes = maxi(0, value)
		_refresh()

func _ready() -> void:
	_refresh()

func set_totals(totals: Array[int]) -> void:
	total_votes = totals[0] + totals[1] + totals[2]
	player_one_votes = totals[1]
	player_two_votes = totals[2]

func set_remaining(seconds: int) -> void:
	remaining_seconds = maxi(0, seconds)
	_refresh()

func _refresh() -> void:
	if not is_inside_tree() or not has_node("Track/PlayerOneFill"):
		return
	var left_ratio := clampf(float(player_one_votes) / total_votes, 0.0, 1.0)
	var right_ratio := clampf(float(player_two_votes) / total_votes, 0.0, 1.0 - left_ratio)
	$Track/PlayerOneFill.anchor_right = left_ratio
	$Track/PlayerTwoFill.anchor_left = 1.0 - right_ratio
	$PlayerOneTotal.text = str(player_one_votes)
	$PlayerTwoTotal.text = str(player_two_votes)
	$VictoryLabel.text = Rules.clock_text(remaining_seconds) + " TO WIN"
	$VictoryNumber.text = str(int(total_votes / 2) + 1)
