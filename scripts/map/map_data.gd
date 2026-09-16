extends RefCounted
## Static geography only. Do not put ownership or unit counts in this resource.

const DATA_PATH := "res://data/map/us_states.json"
var regions: Dictionary = {}
var virtual_edges: Array = []
var canvas_size := Vector2(1440, 740)

func load_map() -> Error:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK or not parser.data is Dictionary:
		return ERR_PARSE_ERROR
	var raw: Dictionary = parser.data
	regions.clear()
	for definition: Dictionary in raw.get("regions", []):
		regions[str(definition["id"])] = definition
	virtual_edges = raw.get("virtual_edges", [])
	var dimensions: Array = raw.get("canvas_size", [1440, 740])
	canvas_size = Vector2(float(dimensions[0]), float(dimensions[1]))
	return OK

func get_neighbors(state_id: String, include_virtual: bool = true) -> Array[String]:
	var result: Array[String] = []
	if not regions.has(state_id):
		return result
	for neighbor: String in regions[state_id]["neighbors"]:
		result.append(neighbor)
	if include_virtual:
		for edge: Array in virtual_edges:
			if str(edge[0]) == state_id:
				result.append(str(edge[1]))
			elif str(edge[1]) == state_id:
				result.append(str(edge[0]))
	result.sort()
	return result

func is_virtual_edge(source: String, target: String) -> bool:
	for edge: Array in virtual_edges:
		if (edge[0] == source and edge[1] == target) or (edge[1] == source and edge[0] == target):
			return true
	return false

func total_electoral_votes() -> int:
	var total := 0
	for definition: Dictionary in regions.values():
		total += int(definition["electoral_votes"])
	return total
