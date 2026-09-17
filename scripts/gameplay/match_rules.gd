extends RefCounted
## All force values represent fictional campaign support, not real vote counts.
const DURATION_SECONDS := 480
const VICTORY_VOTES := 270
const SPAWN_CHOICES := 4
const STARTING_FORCE := 750_000
const MAX_FORCE := 999_999_999
const NEUTRAL_BASE := 40_000
const NEUTRAL_PER_VOTE := 8_000
const GROWTH_BASE := 2_500
const GROWTH_PER_VOTE := 350

static func growth(votes: int) -> int:
	return GROWTH_BASE + votes * GROWTH_PER_VOTE

static func neutral_force(votes: int) -> int:
	return NEUTRAL_BASE + votes * NEUTRAL_PER_VOTE

static func number(value: int) -> String:
	var raw := str(value)
	var result := ""
	for i in raw.length():
		if i > 0 and (raw.length() - i) % 3 == 0:
			result += ","
		result += raw[i]
	return result

static func clock_text(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]
