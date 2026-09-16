@tool
extends Node2D
## Geometry and labels are authored in the scene. Scripts only apply live state.

@export var state_id := ""
@export var player_one_fill := Color("207e83")
@export var player_two_fill := Color("a96532")
@export var border_color := Color("67828d")
@export var border_width := 1.05
var definition: Dictionary = {}
var selected := false
var hovered := false
var adjacent := false
var owner_id := 0
var units := 10
var _base_colors: Dictionary = {}

var anchor: Vector2:
	get:
		return get_parent().to_local($Anchor.global_position)
var label_position: Vector2:
	get:
		return get_parent().to_local($LabelAnchor.global_position)
var polygons: Array[PackedVector2Array]:
	get:
		var result: Array[PackedVector2Array] = []
		for shape: Polygon2D in $Polygons.get_children():
			var points := PackedVector2Array()
			for point: Vector2 in shape.polygon:
				points.append(get_parent().to_local(shape.to_global(point + shape.offset)))
			result.append(points)
		return result

func _ready() -> void:
	set_process(Engine.is_editor_hint())
	for shape: Polygon2D in $Polygons.get_children():
		_base_colors[shape] = shape.color
	queue_redraw()

func _process(_delta: float) -> void:
	# Redraw borders while a designer edits native Polygon2D vertices.
	queue_redraw()

func setup(data: Dictionary) -> void:
	definition = data

func contains_map_point(point: Vector2) -> bool:
	for shape: Polygon2D in $Polygons.get_children():
		var local := shape.to_local(get_parent().to_global(point)) - shape.offset
		if Geometry2D.is_point_in_polygon(local, shape.polygon):
			return true
	return false

func refresh_visuals() -> void:
	for shape: Polygon2D in $Polygons.get_children():
		shape.color = _display_fill(_base_colors.get(shape, shape.color))
	var amount := int(definition.get("electoral_votes", 0))
	$LabelAnchor/LabelPanel/Amount.text = str(amount)
	queue_redraw()

func _display_fill(base: Color) -> Color:
	var fill := base
	if owner_id != 0:
		fill = player_one_fill if owner_id == 1 else player_two_fill
	if adjacent:
		fill = fill.lerp(Color("738b62"), 0.25)
	if hovered:
		fill = fill.lightened(0.16)
	if selected:
		fill = fill.lightened(0.20)
	return fill

func _draw() -> void:
	if not has_node("Polygons"):
		return
	var edge := border_color
	var width := border_width
	if adjacent:
		edge = Color("c6bc7e")
	if selected:
		edge = Color("edf7f4")
		width = 2.5
	elif hovered:
		edge = Color("a9dadb")
		width = 1.7
	for shape: Polygon2D in $Polygons.get_children():
		if shape.polygon.size() < 3:
			continue
		var outline := PackedVector2Array()
		for point: Vector2 in shape.polygon:
			outline.append(to_local(shape.to_global(point + shape.offset)))
		outline.append(outline[0])
		draw_polyline(outline, edge, width, true)
	if selected:
		draw_circle(to_local($Anchor.global_position), 4, Color("e7f5ed"))
	if owner_id != 0:
		var marker := to_local($LabelAnchor.global_position) + Vector2(-23, -7)
		if owner_id == 1:
			draw_circle(marker, 3.5, Color("6be0cf"))
		else:
			draw_colored_polygon(PackedVector2Array([marker + Vector2(0,-4), marker + Vector2(4,3), marker + Vector2(-4,3)]), Color("ffbc7c"))
