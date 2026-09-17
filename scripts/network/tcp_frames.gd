extends RefCounted
## Four-byte big-endian byte length followed by UTF-8 JSON. Never decode objects.
const MAX_FRAME := 65536
const MAX_BUFFER := 262144
var buffer := PackedByteArray()
var failed := false

static func encode(message: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(message).to_utf8_buffer()
	if body.is_empty() or body.size() > MAX_FRAME:
		return PackedByteArray()
	var size := body.size()
	var packet := PackedByteArray([(size >> 24) & 255, (size >> 16) & 255, (size >> 8) & 255, size & 255])
	packet.append_array(body)
	return packet

func feed(bytes: PackedByteArray) -> void:
	if buffer.size() + bytes.size() > MAX_BUFFER:
		failed = true
		return
	buffer.append_array(bytes)

func take_messages(limit: int = 64) -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	while not failed and buffer.size() >= 4 and messages.size() < limit:
		var size := (int(buffer[0]) << 24) | (int(buffer[1]) << 16) | (int(buffer[2]) << 8) | int(buffer[3])
		if size <= 0 or size > MAX_FRAME:
			failed = true
			break
		if buffer.size() < size + 4:
			break
		var parser := JSON.new()
		if parser.parse(buffer.slice(4, size + 4).get_string_from_utf8()) != OK or not parser.data is Dictionary:
			failed = true
			break
		messages.append(parser.data)
		buffer = buffer.slice(size + 4)
	return messages
