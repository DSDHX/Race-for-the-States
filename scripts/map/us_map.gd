@tool
extends Control
## Reusable map. Selection emits IDs; ownership changes arrive via MapState.

signal state_selected(state_id: String)
signal state_hovered(state_id: String)
signal state_right_clicked(state_id: String)
var input_enabled := true
## Zero keeps unrestricted map-preview selection; a match sets its local faction.
var selectable_faction := 0

@export var canvas_size := Vector2(1440, 740):
	set(value):
		canvas_size = Vector2(maxf(1.0, value.x), maxf(1.0, value.y))
		if is_node_ready():
			_fit_map()
var map_data: RefCounted
var map_state: RefCounted
var regions: Dictionary = {}
var selected_id := ""
var hovered_id := ""
@export var include_virtual_links := true
@export var show_neighbors := true
@onready var content: Node2D = $Content
var map_scale := 1.0
var map_offset := Vector2.ZERO

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	resized.connect(_fit_map)
	mouse_exited.connect(func(): _set_hovered(""))
	_fit_map()

func configure(definitions: RefCounted, state: RefCounted) -> void:
	if map_state != null and map_state.changed.is_connected(refresh_states):
		map_state.changed.disconnect(refresh_states)
	map_data = definitions
	map_state = state
	regions.clear()
	for region in content.get_children():
		if region.get_script() == null:
			continue
		if not map_data.regions.has(region.state_id):
			push_error("Unknown map region: " + region.state_id)
			continue
		region.setup(map_data.regions[region.state_id])
		regions[region.state_id] = region
	map_state.changed.connect(refresh_states)
	_fit_map()
	refresh_states()

func _fit_map() -> void:
	if not is_instance_valid(content):
		return
	var base := canvas_size
	map_scale = maxf(0.01, minf(size.x / base.x, size.y / base.y))
	map_offset = (size - base * map_scale) / 2.0
	content.position = map_offset
	content.scale = Vector2.ONE * map_scale
	queue_redraw()

func select_state(state_id: String) -> void:
	if not regions.has(state_id):
		return
	selected_id = state_id
	refresh_states()
	state_selected.emit(state_id)

func clear_selection() -> void:
	selected_id = ""
	refresh_states()

func refresh_states() -> void:
	var neighbors: Array[String] = []
	if show_neighbors and map_data != null:
		neighbors = map_data.get_neighbors(selected_id, include_virtual_links)
	for state_id: String in regions:
		var region = regions[state_id]
		region.selected = state_id == selected_id
		region.hovered = state_id == hovered_id
		region.adjacent = neighbors.has(state_id)
		region.owner_id = int(map_state.states[state_id].owner)
		region.units = int(map_state.states[state_id].units)
		region.z_index = 2 if region.selected else (1 if region.hovered else 0)
		region.refresh_visuals()
	queue_redraw()

func state_at_map_point(point: Vector2) -> String:
	for state_id: String in regions:
		if regions[state_id].contains_map_point(point):
			return state_id
	return ""

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or map_data == null or not input_enabled:
		return
	if event is InputEventMouseMotion:
		_set_hovered(state_at_map_point((event.position - map_offset) / map_scale))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var state_id := state_at_map_point((event.position - map_offset) / map_scale)
		if not state_id.is_empty() and (selectable_faction == 0 or int(map_state.states[state_id].owner) == selectable_faction):
			select_state(state_id)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var state_id := state_at_map_point((event.position - map_offset) / map_scale)
		if not state_id.is_empty():
			state_right_clicked.emit(state_id)
		accept_event()

func _set_hovered(state_id: String) -> void:
	if hovered_id == state_id:
		return
	hovered_id = state_id
	_refresh_tooltip()
	refresh_states()
	state_hovered.emit(state_id)

func _refresh_tooltip() -> void:
	tooltip_text = "" if hovered_id.is_empty() or map_data == null else tr("%s\n力量：%s") % [tr(str(map_data.regions[hovered_id].name)), preload("res://scripts/gameplay/match_rules.gd").number(int(map_state.states[hovered_id].units))]

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_tooltip()

func _draw() -> void:
	draw_set_transform(map_offset, 0, Vector2.ONE * map_scale)
	var grid := Color(0.33, 0.55, 0.62, 0.075)
	for x in range(20, int(canvas_size.x), 40):
		for y in range(20, int(canvas_size.y), 40):
			draw_circle(Vector2(x,y), 0.7, grid)
	if include_virtual_links and show_neighbors and map_data != null:
		for edge: Array in map_data.virtual_edges:
			if selected_id in edge:
				var a: Vector2 = regions[str(edge[0])].anchor
				var b: Vector2 = regions[str(edge[1])].anchor
				draw_dashed_line(a, b, Color("bea875"), 1.5, 7.0, true)
	draw_set_transform(Vector2.ZERO)
