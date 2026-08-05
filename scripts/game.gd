extends Node
## Автозагрузка "Game". Правила игры и предметы.
## Авторитет — сервер (хост). Клиенты только просят, сервер решает и рассылает.

const ItemScript := preload("res://scripts/item.gd")

const DISCIPLINES := ["code", "art", "music"]
const WORK_TIME := 6.0        # сколько стол делает ассет из тикета
const TRAY_PERIOD := 5.0      # раз в сколько секунд появляется тикет
const TRAY_MAX := 6

var items: Dictionary = {}    # item_id -> Item
var delivered := 0

var _next_id := 1
var _tray_timer := 2.0
var _work: Dictionary = {}    # station_index -> {"left": float, "disc": String}


func _is_server() -> bool:
	return (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()


func reset() -> void:
	for it in items.values():
		if is_instance_valid(it):
			it.queue_free()
	items.clear()
	_work.clear()
	delivered = 0
	_next_id = 1
	_tray_timer = 2.0


func _process(delta: float) -> void:
	if Boot.world == null or not _is_server():
		return
	_tick_tray(delta)
	_tick_work(delta)


# ---------------------------------------------------------------- СЕРВЕР

func _tick_tray(delta: float) -> void:
	_tray_timer -= delta
	if _tray_timer > 0.0:
		return
	_tray_timer = TRAY_PERIOD
	var n := _tray_count()
	if n >= TRAY_MAX:
		return
	var disc: String = DISCIPLINES.pick_random()
	server_spawn_item("ticket_" + disc, Boot.world.tray_slot(n))


func _tray_count() -> int:
	var n := 0
	var tray_pos: Vector3 = Boot.world.tray_position()
	for it in items.values():
		if it.holder == 0 and it.kind.begins_with("ticket_"):
			if it.global_position.distance_to(tray_pos) < 2.0:
				n += 1
	return n


func _tick_work(delta: float) -> void:
	for idx in _work.keys():
		var w: Dictionary = _work[idx]
		w["left"] = float(w["left"]) - delta
		if float(w["left"]) <= 0.0:
			var disc: String = String(w["disc"])
			_work.erase(idx)
			var st = Boot.world.stations[idx]
			server_spawn_item("asset_" + disc, st.output_position())
			_bcast("rpc_station_stop", [idx])


func server_spawn_item(kind: String, pos: Vector3, holder := 0) -> int:
	var id := _next_id
	_next_id += 1
	_bcast("rpc_item_spawn", [id, kind, holder, pos])
	return id


func server_release_items(peer_id: int) -> void:
	if not _is_server():
		return
	for it in items.values():
		if it.holder == peer_id:
			_bcast("rpc_item_state", [it.item_id, 0, it.global_position])


func server_send_snapshot(to_id: int) -> void:
	if not _is_server():
		return
	for it in items.values():
		rpc_id(to_id, "rpc_item_spawn", it.item_id, it.kind, it.holder, it.global_position)
	rpc_id(to_id, "rpc_delivered", delivered)
	for idx in _work.keys():
		rpc_id(to_id, "rpc_station_start", int(idx), float(_work[idx]["left"]))


# ---------------------------------------------------------------- ЗАПРОСЫ ОТ ИГРОКОВ

func request_interact(type: String, id: int) -> void:
	if _is_server():
		_server_interact(Boot.local_id(), type, id)
	else:
		rpc_id(1, "_req_interact", type, id)


func request_drop() -> void:
	if _is_server():
		_server_drop(Boot.local_id())
	else:
		rpc_id(1, "_req_drop")


@rpc("any_peer", "reliable")
func _req_interact(type: String, id: int) -> void:
	if _is_server():
		_server_interact(multiplayer.get_remote_sender_id(), type, id)


@rpc("any_peer", "reliable")
func _req_drop() -> void:
	if _is_server():
		_server_drop(multiplayer.get_remote_sender_id())


func _server_interact(pid: int, type: String, id: int) -> void:
	if not _is_server() or Boot.world == null:
		return
	var held = held_item_of(pid)

	match type:
		"item":
			if held != null or not items.has(id):
				return
			var it = items[id]
			if it.holder != 0:
				return
			_bcast("rpc_item_state", [id, pid, it.global_position])

		"station":
			if id < 0 or id >= Boot.world.stations.size():
				return
			if held == null or not held.kind.begins_with("ticket_"):
				return
			if _work.has(id):
				return
			var st = Boot.world.stations[id]
			if held.kind != "ticket_" + String(st.discipline):
				return
			_bcast("rpc_item_remove", [held.item_id])
			_work[id] = {"left": WORK_TIME, "disc": String(st.discipline)}
			_bcast("rpc_station_start", [id, WORK_TIME])

		"assembler":
			if held == null or not held.kind.begins_with("asset_"):
				return
			_bcast("rpc_item_remove", [held.item_id])
			delivered += 1
			_bcast("rpc_delivered", [delivered])


func _server_drop(pid: int) -> void:
	if not _is_server():
		return
	var held = held_item_of(pid)
	if held == null or not Boot.players.has(pid):
		return
	var p := Boot.players[pid] as Node3D
	var fwd := -p.global_transform.basis.z
	var pos := p.global_position + fwd * 1.0
	pos.y = 0.35
	_bcast("rpc_item_state", [held.item_id, 0, pos])


# ---------------------------------------------------------------- РАССЫЛКА

func _bcast(method: String, args: Array) -> void:
	callv(method, args)                      # локально
	if not multiplayer.has_multiplayer_peer():
		return
	var me := multiplayer.get_unique_id()
	for pid in Boot.ready_peers:             # только тем, кто уже готов принимать
		if int(pid) != me:
			callv("rpc_id", [int(pid), method] + args)


@rpc("authority", "call_local", "reliable")
func rpc_item_spawn(id: int, kind: String, holder: int, pos: Vector3) -> void:
	if items.has(id) or Boot.world == null:
		return
	var it := ItemScript.new()
	it.name = "item_%d" % id
	it.item_id = id
	it.kind = kind
	it.holder = holder
	it.start_pos = pos
	items[id] = it
	Boot.world.items_root.add_child(it)


@rpc("authority", "call_local", "reliable")
func rpc_item_state(id: int, holder: int, pos: Vector3) -> void:
	if not items.has(id):
		return
	var it = items[id]
	it.holder = holder
	if holder == 0:
		it.target_pos = pos


@rpc("authority", "call_local", "reliable")
func rpc_item_remove(id: int) -> void:
	if not items.has(id):
		return
	items[id].queue_free()
	items.erase(id)


@rpc("authority", "call_local", "reliable")
func rpc_station_start(idx: int, duration: float) -> void:
	if Boot.world == null or idx >= Boot.world.stations.size():
		return
	Boot.world.stations[idx].begin_work(duration)


@rpc("authority", "call_local", "reliable")
func rpc_station_stop(idx: int) -> void:
	if Boot.world == null or idx >= Boot.world.stations.size():
		return
	Boot.world.stations[idx].end_work()


@rpc("authority", "call_local", "reliable")
func rpc_delivered(n: int) -> void:
	delivered = n
	if Boot.world and Boot.world.assembler:
		Boot.world.assembler.set_count(n)


# ---------------------------------------------------------------- ХЕЛПЕРЫ

func held_item_of(pid: int):
	for it in items.values():
		if it.holder == pid:
			return it
	return null


func title_of(kind: String) -> String:
	match kind:
		"ticket_code": return "Тикет: Код"
		"ticket_art": return "Тикет: Графика"
		"ticket_music": return "Тикет: Музыка"
		"asset_code": return "Модуль кода"
		"asset_art": return "Спрайт"
		"asset_music": return "Стем музыки"
	return kind


func color_of(kind: String) -> Color:
	if kind.ends_with("code"):
		return Color(0.40, 0.70, 1.00)
	if kind.ends_with("art"):
		return Color(1.00, 0.52, 0.62)
	if kind.ends_with("music"):
		return Color(0.70, 0.52, 1.00)
	return Color.WHITE
