extends RefCounted
## Mutable display state. A future authoritative simulation can replace this.

signal changed

const NEUTRAL := 0
const PLAYER_ONE := 1
const PLAYER_TWO := 2
var states: Dictionary = {}

func reset(state_ids: Array) -> void:
	states.clear()
	for state_id: String in state_ids:
		states[state_id] = {"owner": NEUTRAL, "units": 10}
	changed.emit()

func set_state(state_id: String, owner_id: int, units: int) -> void:
	if not states.has(state_id) or owner_id < 0 or owner_id > 2:
		return
	states[state_id] = {"owner": owner_id, "units": clampi(units, 0, 9999)}
	changed.emit()

func apply_snapshot(snapshot: Dictionary) -> bool:
	# Validate the complete payload before applying any change.
	if snapshot.size() != states.size():
		return false
	for state_id: String in states:
		if not snapshot.has(state_id) or not snapshot[state_id] is Dictionary:
			return false
		var item: Dictionary = snapshot[state_id]
		if not item.has("owner") or not item.has("units"):
			return false
		if not _is_whole_number(item.owner) or not _is_whole_number(item.units):
			return false
		if int(item.owner) < 0 or int(item.owner) > 2 or int(item.units) < 0 or int(item.units) > 9999:
			return false
	for state_id: String in states:
		states[state_id] = {"owner": int(snapshot[state_id].owner), "units": int(snapshot[state_id].units)}
	changed.emit()
	return true

func _is_whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func get_snapshot() -> Dictionary:
	return states.duplicate(true)

func electoral_totals(definitions: Dictionary) -> Array[int]:
	var totals: Array[int] = [0, 0, 0]
	for state_id: String in states:
		totals[int(states[state_id].owner)] += int(definitions[state_id].electoral_votes)
	return totals
