extends Node
## Автозагрузка "Game". Правила игры и предметы.
## Авторитет — сервер (хост). Клиенты просят, сервер решает и рассылает.

const ItemScript := preload("res://scripts/item.gd")

const DISCIPLINES := ["code", "art", "music"]
const TOKENS_PER_TASK := 4
const TRAY_PERIOD := 5.0
const TRAY_MAX := 6

## Слова только из латиницы и цифр — сравнение идёт по физическим клавишам,
## поэтому раскладка игрока значения не имеет.
const WORDS := {
	"code": ["RUN", "INIT", "LOOP", "PUSH", "POP", "CALL", "VOID", "NULL", "HEAP", "BYTE", "FUNC", "ELSE", "TRUE", "SYNC", "PARSE"],
	"art": ["BRUSH", "SHADE", "PIXEL", "LAYER", "TINT", "LINE", "FILL", "MASK", "GLOW", "EDGE", "CURVE"],
	"music": ["TEMPO", "CHORD", "BEAT", "BASS", "SNARE", "FADE", "TONE", "MIX", "REVERB", "SWING"],
}

var items: Dictionary = {}
var work: Dictionary = {}      # idx -> {disc, tokens, done, mistakes, occupant}
var delivered := 0
var quality_sum := 0.0

var _next_id := 1
var _tray_timer := 2.0


func _is_server() -> bool:
	return (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()


func reset() -> void:
	for it in items.values():
		if is_instance_valid(it):
			it.queue_free()
	items.clear()
	work.clear()
	delivered = 0
	quality_sum = 0.0
	_next_id = 1
	_tray_timer = 2.0
	if Boot.terminal:
		Boot.terminal.close()


func _process(delta: float) -> void:
	if Boot.world == null or not _is_server():
		return
	_tick_tray(delta)


# ---------------------------------------------------------------- ЛОТОК

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
		if it.holder == 0 and String(it.kind).begins_with("ticket_"):
			if it.global_position.distance_to(tray_pos) < 2.0:
				n += 1
	return n


# ---------------------------------------------------------------- ПРЕДМЕТЫ

func server_spawn_item(kind: String, pos: Vector3, quality := 1.0) -> int:
	var id := _next_id
	_next_id += 1
	_bcast("rpc_item_spawn", [id, kind, 0, pos, quality])
	return id


func server_release_items(peer_id: int) -> void:
	if not _is_server():
		return
	for it in items.values():
		if it.holder == peer_id:
			_bcast("rpc_item_state", [it.item_id, 0, it.global_position])
	for idx in work.keys():
		if int(work[idx]["occupant"]) == peer_id:
			_bcast("rpc_work_occupant", [int(idx), 0])


func server_send_snapshot(to_id: int) -> void:
	if not _is_server():
		return
	for it in items.values():
		rpc_id(to_id, "rpc_item_spawn", it.item_id, it.kind, it.holder, it.global_position, it.quality)
	for idx in work.keys():
		var w: Dictionary = work[idx]
		rpc_id(to_id, "rpc_work_begin", int(idx), String(w["disc"]), w["tokens"], 0)
		rpc_id(to_id, "rpc_work_progress", int(idx), int(w["done"]))
		rpc_id(to_id, "rpc_work_occupant", int(idx), int(w["occupant"]))
	rpc_id(to_id, "rpc_delivered", delivered, quality_sum)


# ---------------------------------------------------------------- ЗАПРОСЫ

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


func request_token(idx: int, mistakes: int) -> void:
	if _is_server():
		_server_token(Boot.local_id(), idx, mistakes)
	else:
		rpc_id(1, "_req_token", idx, mistakes)


func request_leave_station(idx: int) -> void:
	if _is_server():
		_server_leave(Boot.local_id(), idx)
	else:
		rpc_id(1, "_req_leave", idx)


@rpc("any_peer", "reliable")
func _req_interact(type: String, id: int) -> void:
	if _is_server():
		_server_interact(multiplayer.get_remote_sender_id(), type, id)


@rpc("any_peer", "reliable")
func _req_drop() -> void:
	if _is_server():
		_server_drop(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _req_token(idx: int, mistakes: int) -> void:
	if _is_server():
		_server_token(multiplayer.get_remote_sender_id(), idx, mistakes)


@rpc("any_peer", "reliable")
func _req_leave(idx: int) -> void:
	if _is_server():
		_server_leave(multiplayer.get_remote_sender_id(), idx)


# ---------------------------------------------------------------- ЛОГИКА СЕРВЕРА

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
			var st = Boot.world.stations[id]
			if work.has(id):
				# стол уже занят задачей — можно подхватить чужую работу
				if int(work[id]["occupant"]) == 0:
					_bcast("rpc_work_occupant", [id, pid])
				return
			if held == null or not String(held.kind).begins_with("ticket_"):
				return
			if String(held.kind) != "ticket_" + String(st.discipline):
				return
			_bcast("rpc_item_remove", [held.item_id])
			_bcast("rpc_work_begin", [id, String(st.discipline), _make_tokens(String(st.discipline)), pid])

		"assembler":
			if held == null or not String(held.kind).begins_with("asset_"):
				return
			var q: float = float(held.quality)
			_bcast("rpc_item_remove", [held.item_id])
			_bcast("rpc_delivered", [delivered + 1, quality_sum + q])


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


func _server_token(pid: int, idx: int, mistakes: int) -> void:
	if not _is_server() or not work.has(idx):
		return
	var w: Dictionary = work[idx]
	if int(w["occupant"]) != pid:
		return
	w["done"] = int(w["done"]) + 1
	w["mistakes"] = int(w["mistakes"]) + maxi(mistakes, 0)

	var toks: Array = w["tokens"]
	if int(w["done"]) < toks.size():
		_bcast("rpc_work_progress", [idx, int(w["done"])])
		return

	var disc: String = String(w["disc"])
	var quality := clampf(1.0 - float(w["mistakes"]) * 0.09, 0.25, 1.0)
	var st = Boot.world.stations[idx]
	_bcast("rpc_work_end", [idx])
	server_spawn_item("asset_" + disc, st.output_position(), quality)


func _server_leave(pid: int, idx: int) -> void:
	if not _is_server() or not work.has(idx):
		return
	if int(work[idx]["occupant"]) != pid:
		return
	_bcast("rpc_work_occupant", [idx, 0])


func _make_tokens(disc: String) -> Array:
	var pool: Array = WORDS[disc]
	var out: Array = []
	for i in TOKENS_PER_TASK:
		out.append(String(pool[randi() % pool.size()]))
	return out


# ---------------------------------------------------------------- РАССЫЛКА

func _bcast(method: String, args: Array) -> void:
	callv(method, args)
	if not multiplayer.has_multiplayer_peer():
		return
	var me := multiplayer.get_unique_id()
	for pid in Boot.ready_peers:
		if int(pid) != me:
			callv("rpc_id", [int(pid), method] + args)


@rpc("authority", "call_local", "reliable")
func rpc_item_spawn(id: int, kind: String, holder: int, pos: Vector3, quality: float) -> void:
	if items.has(id) or Boot.world == null:
		return
	var it := ItemScript.new()
	it.name = "item_%d" % id
	it.item_id = id
	it.kind = kind
	it.holder = holder
	it.quality = quality
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
func rpc_work_begin(idx: int, disc: String, tokens: Array, occupant: int) -> void:
	if Boot.world == null or idx >= Boot.world.stations.size():
		return
	work[idx] = {"disc": disc, "tokens": tokens.duplicate(), "done": 0, "mistakes": 0, "occupant": occupant}
	Boot.world.stations[idx].set_work(tokens.size(), 0)
	if occupant == Boot.local_id() and Boot.terminal:
		Boot.terminal.open(idx, disc, tokens, 0)


@rpc("authority", "call_local", "reliable")
func rpc_work_progress(idx: int, done: int) -> void:
	if not work.has(idx):
		return
	work[idx]["done"] = done
	var toks: Array = work[idx]["tokens"]
	Boot.world.stations[idx].set_work(toks.size(), done)
	if Boot.terminal and Boot.terminal.active and Boot.terminal.station_idx == idx:
		Boot.terminal.sync_progress(done)


@rpc("authority", "call_local", "reliable")
func rpc_work_occupant(idx: int, occupant: int) -> void:
	if not work.has(idx):
		return
	work[idx]["occupant"] = occupant
	if Boot.terminal == null:
		return
	if occupant == Boot.local_id():
		var w: Dictionary = work[idx]
		Boot.terminal.open(idx, String(w["disc"]), w["tokens"], int(w["done"]))
	elif Boot.terminal.station_idx == idx:
		Boot.terminal.close()


@rpc("authority", "call_local", "reliable")
func rpc_work_end(idx: int) -> void:
	work.erase(idx)
	if Boot.world and idx < Boot.world.stations.size():
		Boot.world.stations[idx].clear_work()
	if Boot.terminal and Boot.terminal.station_idx == idx:
		Boot.terminal.close()


@rpc("authority", "call_local", "reliable")
func rpc_delivered(n: int, q_sum: float) -> void:
	delivered = n
	quality_sum = q_sum
	if Boot.world and Boot.world.assembler:
		Boot.world.assembler.set_count(n, avg_quality())


# ---------------------------------------------------------------- ХЕЛПЕРЫ

func avg_quality() -> float:
	if delivered <= 0:
		return 1.0
	return quality_sum / float(delivered)


func held_item_of(pid: int):
	for it in items.values():
		if it.holder == pid:
			return it
	return null


func is_local_busy() -> bool:
	return Boot.terminal != null and Boot.terminal.active


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
