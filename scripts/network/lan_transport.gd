extends Node
## Bounded, non-blocking TCP transport. Connection IDs are assigned locally.
signal connected(connection_id: int)
signal received(connection_id: int, message: Dictionary)
signal disconnected(connection_id: int, reason: String)
const Frames = preload("res://scripts/network/tcp_frames.gd")
const TIMEOUT_MS := 10000
const HEARTBEAT_MS := 2000
var server := TCPServer.new()
var peers: Dictionary = {}
var _next_id := 1

func listen(port: int) -> Error:
	close()
	return server.listen(port, "*")

func connect_host(address: String, port: int) -> Error:
	close()
	var socket := StreamPeerTCP.new()
	var result := socket.connect_to_host(address, port)
	if result == OK:
		_add(socket, false)
	return result

func _add(socket: StreamPeerTCP, accepted: bool) -> void:
	var id := _next_id
	_next_id += 1
	var now := Time.get_ticks_msec()
	peers[id] = {"socket": socket, "frames": Frames.new(), "out": PackedByteArray(),
		"connected": accepted, "last_read": now, "last_ping": now,
		"closing": false, "close_at": 0, "window": now, "count": 0}
	if accepted:
		socket.set_no_delay(true)
		connected.emit(id)

func send(id: int, message: Dictionary) -> bool:
	if not peers.has(id) or peers[id].closing:
		return false
	var packet := Frames.encode(message)
	if packet.is_empty() or peers[id].out.size() + packet.size() > Frames.MAX_BUFFER:
		drop(id, "发送队列已满，连接已关闭。")
		return false
	peers[id].out.append_array(packet)
	return true

func reject(id: int, reason: String) -> void:
	send(id, {"type": "reject", "message": reason})
	if peers.has(id):
		peers[id].closing = true
		peers[id].close_at = Time.get_ticks_msec() + 500

func drop(id: int, reason: String) -> void:
	if not peers.has(id):
		return
	peers[id].socket.disconnect_from_host()
	peers.erase(id)
	disconnected.emit(id, reason)

func close() -> void:
	server.stop()
	for peer: Dictionary in peers.values():
		peer.socket.disconnect_from_host()
	peers.clear()

func _exit_tree() -> void:
	close()

func _process(_delta: float) -> void:
	# Limit accepts, bytes and decoded packets per frame, including hostile peers.
	for _i in 4:
		if not server.is_connection_available():
			break
		var socket := server.take_connection()
		if peers.size() >= 4:
			socket.disconnect_from_host()
		else:
			_add(socket, true)
	for id: int in peers.keys():
		if peers.has(id):
			_poll_peer(id)

func _poll_peer(id: int) -> void:
	var peer: Dictionary = peers[id]
	var socket: StreamPeerTCP = peer.socket
	socket.poll()
	var status := socket.get_status()
	var now := Time.get_ticks_msec()
	if now - int(peer.last_read) > TIMEOUT_MS:
		drop(id, "连接超时，请检查主机地址和网络。")
		return
	if status in [StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR]:
		drop(id, "连接已断开，请检查主机是否仍在房间内。")
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	if not peer.connected:
		peer.connected = true
		socket.set_no_delay(true)
		connected.emit(id)
		if not peers.has(id):
			return
	if peer.closing and (peer.out.is_empty() or now >= int(peer.close_at)):
		drop(id, "连接已关闭。")
		return
	if now - int(peer.last_ping) >= HEARTBEAT_MS and not peer.closing:
		peer.last_ping = now
		send(id, {"type": "ping"})
	if not peer.out.is_empty():
		var written := socket.put_partial_data(peer.out)
		if written[0] != OK:
			drop(id, "网络发送失败。")
			return
		peer.out = peer.out.slice(int(written[1]))
	var available := mini(socket.get_available_bytes(), Frames.MAX_FRAME)
	if available > 0:
		var read := socket.get_partial_data(available)
		if read[0] != OK:
			drop(id, "网络接收失败。")
			return
		peer.frames.feed(read[1])
	var messages: Array[Dictionary] = peer.frames.take_messages()
	if peer.frames.failed:
		drop(id, "收到无效网络数据。")
		return
	if now - int(peer.window) >= 1000:
		peer.window = now
		peer.count = 0
	peer.count += messages.size()
	if int(peer.count) > 120:
		drop(id, "操作过于频繁，连接已关闭。")
		return
	for message: Dictionary in messages:
		if not peers.has(id) or peer.closing:
			break
		peer.last_read = now
		if message.get("type") == "ping":
			send(id, {"type": "pong"})
		elif message.get("type") != "pong":
			received.emit(id, message)
