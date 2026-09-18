@tool
extends Control
const Rules = preload("res://scripts/gameplay/match_rules.gd")
var remaining_seconds := Rules.DURATION_SECONDS
var player_one_force := 0
var player_two_force := 0
var player_one_growth := 0
var player_two_growth := 0
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()

func set_totals(totals: Array[int]) -> void:
	total_votes = totals[0] + totals[1] + totals[2]
	player_one_votes = totals[1]
	player_two_votes = totals[2]

func set_remaining(seconds: int) -> void:
	remaining_seconds = maxi(0, seconds)
	_refresh()

func set_forces(first: int, second: int, first_growth: int = 0, second_growth: int = 0) -> void:
	player_one_force = first
	player_two_force = second
	player_one_growth = first_growth
	player_two_growth = second_growth
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
	$PlayerOneForce.text = Rules.number(player_one_force)
	$PlayerTwoForce.text = Rules.number(player_two_force)
	$PlayerOneForce.tooltip_text = tr("力量：%s\n每秒增长：%s") % [Rules.number(player_one_force), Rules.number(player_one_growth)]
	$PlayerTwoForce.tooltip_text = tr("力量：%s\n每秒增长：%s") % [Rules.number(player_two_force), Rules.number(player_two_growth)]
	$VictoryLabel.text = tr("%s · 获胜目标") % Rules.clock_text(remaining_seconds)
	$VictoryNumber.text = str(int(total_votes / 2) + 1)
