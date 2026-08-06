extends Node
## Автозагрузка "Game". Правила игры и предметы.
## Авторитет — сервер (хост). Клиенты просят, сервер решает и рассылает.

const ItemScript := preload("res://scripts/item.gd")

const DISCIPLINES := ["code", "art", "music"]
const TOKENS_PER_TASK := 6
const NOTES_PER_TASK := 8

## Спрайты для стола «Графика»: сетка 4 в ширину, цифра — индекс цвета палитры.
const SPRITES := [
	[".11.", "1221", "1221", ".33."],
	["0..0", ".22.", ".22.", "0330"],
	[".00.", "0110", ".22.", "3..3"],
	["11..", "1220", ".223", "..33"],
]
const TRAY_PERIOD := 5.0
const TRAY_MAX := 6

## Слова только из латиницы и цифр — сравнение идёт по физическим клавишам,
## поэтому раскладка игрока значения не имеет.
const WORDS := {
	"code": ["RUN", "INIT", "LOOP", "PUSH", "POP", "CALL", "VOID", "NULL", "HEAP", "BYTE", "FUNC", "ELSE", "TRUE", "SYNC", "PARSE"],
	"art": ["BRUSH", "SHADE", "PIXEL", "LAYER", "TINT", "LINE", "FILL", "MASK", "GLOW", "EDGE", "CURVE"],
	"music": ["TEMPO", "CHORD", "BEAT", "BASS", "SNARE", "FADE", "TONE", "MIX", "REVERB", "SWING"],
}

const WEEK_SECONDS := 90.0

const CONTRACTS := [
	{"title": "Слэшер / Средневековье", "need": {"code": 3, "art": 3, "music": 3}, "weeks": 3, "pay": 1800},
	{"title": "Платформер / Космос", "need": {"code": 4, "art": 3, "music": 2}, "weeks": 3, "pay": 1800},
	{"title": "Хоррор / Особняк", "need": {"code": 3, "art": 4, "music": 3}, "weeks": 3, "pay": 2000},
	{"title": "Ритм-игра / Неон", "need": {"code": 3, "art": 2, "music": 5}, "weeks": 3, "pay": 2000},
]

var contract: Dictionary = {}
var contract_time := 0.0
var contract_running := false
var delivered_by: Dictionary = {"code": 0, "art": 0, "music": 0}
var money := 0
var difficulty := 0

var items: Dictionary = {}
var work: Dictionary = {}      # idx -> {disc, tokens, done, mistakes, occupant}
var delivered := 0
var quality_sum := 0.0

var _next_id := 1
var _tray_timer := 2.0
var _sync_timer := 1.0


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
	contract = {}
	contract_time = 0.0
	contract_running = false
	delivered_by = {"code": 0, "art": 0, "music": 0}
	difficulty = 0
	money = 0
	Boot.close_panels(-1)
	if Boot.results:
		Boot.results.close()


func _process(delta: float) -> void:
	if Boot.world == null:
		return
	if contract_running:
		contract_time += delta
		Boot.update_contract_hud()
	if not _is_server():
		return
	_tick_tray(delta)
	if contract_running:
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = 1.0
			_bcast("rpc_contract_time", [contract_time])
		if contract_time >= deadline_seconds():
			_server_finish(false)


# ---------------------------------------------------------------- ЛОТОК

func _tick_tray(delta: float) -> void:
	_tray_timer -= delta
	if _tray_timer > 0.0:
		return
	_tray_timer = TRAY_PERIOD
	if not contract_running:
		return
	var n := _tray_count()
	if n >= TRAY_MAX:
		return
	var disc := _neediest_discipline()
	if disc == "":
		return
	server_spawn_item("ticket_" + disc, Boot.world.tray_slot(n))


## Какой дисциплины не хватает сильнее всего с учётом того,
## что уже лежит в мире и делается за столами.
func _neediest_discipline() -> String:
	var best := ""
	var best_gap := 0
	for k in DISCIPLINES:
		var gap := need_of(k) - int(delivered_by[k]) - _in_flight(k)
		if gap > best_gap:
			best_gap = gap
			best = k
	return best


func _in_flight(disc: String) -> int:
	var n := 0
	for it in items.values():
		if String(it.kind).ends_with(disc):
			n += 1
	for idx in work.keys():
		if String(work[idx]["disc"]) == disc:
			n += 1
	return n


func need_of(disc: String) -> int:
	if contract.is_empty():
		return 0
	return int(contract["need"].get(disc, 0))


func deadline_seconds() -> float:
	if contract.is_empty():
		return 0.0
	return float(contract["weeks"]) * WEEK_SECONDS


func current_week() -> int:
	return mini(int(contract_time / WEEK_SECONDS) + 1, int(contract["weeks"]) if not contract.is_empty() else 1)


func requirements_met() -> bool:
	if contract.is_empty():
		return false
	for k in DISCIPLINES:
		if int(delivered_by[k]) < need_of(k):
			return false
	return true


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
			var pos: Vector3 = it.global_position
			pos.y = 0.35
			_bcast("rpc_item_state", [it.item_id, 0, pos])
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
		rpc_id(to_id, "rpc_work_progress", int(idx), int(w["done"]), int(w["mistakes"]))
		rpc_id(to_id, "rpc_work_occupant", int(idx), int(w["occupant"]))
	if contract_running:
		rpc_id(to_id, "rpc_contract_start", contract)
		rpc_id(to_id, "rpc_contract_time", contract_time)
	rpc_id(to_id, "rpc_delivered_sync", delivered, quality_sum, delivered_by)


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
			if held == null:
				# пустые руки: если всё готово — можно сдать игру досрочно
				if contract_running and requirements_met():
					_server_finish(true)
				return
			if not String(held.kind).begins_with("asset_"):
				return
			var q: float = float(held.quality)
			var disc := String(held.kind).substr(6)
			_bcast("rpc_item_remove", [held.item_id])
			_bcast("rpc_delivered", [delivered + 1, quality_sum + q, disc])


func _server_drop(pid: int) -> void:
	if not _is_server():
		return
	var held = held_item_of(pid)
	if held == null or not Boot.players.has(pid):
		return
	var p := Boot.players[pid] as Node3D
	var fwd := -p.global_transform.basis.z
	_bcast("rpc_item_state", [held.item_id, 0, safe_drop_point(p, fwd)])


## Куда реально положить предмет: если впереди стол или машина,
## кладём перед препятствием, а не внутрь него.
## Куда реально положить предмет. Проверяем сферой несколько точек перед
## игроком и берём первую свободную — один луч не ловил углы и боковины машины.
func safe_drop_point(p: Node3D, fwd: Vector3) -> Vector3:
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.01:
		flat = Vector3(0, 0, -1)
	flat = flat.normalized()

	var space := p.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.32
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collide_with_bodies = true
	params.exclude = [p.get_rid()]

	for d in [1.1, 0.85, 0.6, 0.35, 0.0]:
		var pos: Vector3 = p.global_position + flat * float(d)
		pos.y = 0.42
		params.transform = Transform3D(Basis(), pos)
		if space.intersect_shape(params, 1).is_empty():
			return pos

	var fallback := p.global_position
	fallback.y = 0.42
	return fallback


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
		_bcast("rpc_work_progress", [idx, int(w["done"]), int(w["mistakes"])])
		return

	var disc: String = String(w["disc"])
	var quality := quality_for(int(w["mistakes"]))
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
	var out: Array = []
	# музыка играется как ритм-игра: токен = номер дорожки
	if disc == "music":
		var last := -1
		for i in NOTES_PER_TASK:
			var lane := randi() % 4
			if lane == last and randf() < 0.6:
				lane = (lane + 1 + randi() % 3) % 4
			last = lane
			out.append(str(lane))
		return out
	# графика — раскраска: токен это «клетка:цвет», идём цветами подряд,
	# чтобы кисть приходилось менять три-четыре раза, а не на каждой клетке
	if disc == "art":
		var tpl: Array = SPRITES[randi() % SPRITES.size()]
		var by_color: Dictionary = {}
		for r in tpl.size():
			var row: String = tpl[r]
			for c in row.length():
				var ch := row.substr(c, 1)
				if ch == ".":
					continue
				var col := int(ch)
				if not by_color.has(col):
					by_color[col] = []
				by_color[col].append(r * 4 + c)
		var colors: Array = by_color.keys()
		colors.shuffle()
		for col in colors:
			for cell in by_color[col]:
				out.append("%d:%d" % [int(cell), int(col)])
		return out

	var pool: Array = WORDS[disc]
	for i in TOKENS_PER_TASK:
		out.append(String(pool[randi() % pool.size()]))
	# короткие вперёд — сложность нарастает внутри задачи
	out.sort_custom(func(a, b): return String(a).length() < String(b).length())
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
	if occupant == Boot.local_id():
		var panel = Boot.panel_for(disc)
		if panel:
			panel.open(idx, disc, tokens, 0)


@rpc("authority", "call_local", "reliable")
func rpc_work_progress(idx: int, done: int, mistakes: int) -> void:
	if not work.has(idx):
		return
	work[idx]["done"] = done
	work[idx]["mistakes"] = mistakes
	var toks: Array = work[idx]["tokens"]
	Boot.world.stations[idx].set_work(toks.size(), done)
	var panel = Boot.active_panel()
	if panel and panel.station_idx == idx:
		panel.sync_progress(done)


@rpc("authority", "call_local", "reliable")
func rpc_work_occupant(idx: int, occupant: int) -> void:
	if not work.has(idx):
		return
	work[idx]["occupant"] = occupant
	var w: Dictionary = work[idx]
	if occupant == Boot.local_id():
		var panel = Boot.panel_for(String(w["disc"]))
		if panel:
			panel.open(idx, String(w["disc"]), w["tokens"], int(w["done"]))
	else:
		var open_panel = Boot.active_panel()
		if open_panel and open_panel.station_idx == idx:
			open_panel.close()


@rpc("authority", "call_local", "reliable")
func rpc_work_end(idx: int) -> void:
	work.erase(idx)
	if Boot.world and idx < Boot.world.stations.size():
		Boot.world.stations[idx].clear_work()
	Boot.close_panels(idx)


@rpc("authority", "call_local", "reliable")
func rpc_delivered(n: int, q_sum: float, disc: String) -> void:
	delivered = n
	quality_sum = q_sum
	if delivered_by.has(disc):
		delivered_by[disc] = int(delivered_by[disc]) + 1
	if Boot.world and Boot.world.assembler:
		Boot.world.assembler.set_count(n, avg_quality())
	Boot.update_contract_hud()


# ---------------------------------------------------------------- КОНТРАКТ

func server_start_contract() -> void:
	if not _is_server():
		return
	var c: Dictionary = CONTRACTS[randi() % CONTRACTS.size()].duplicate(true)
	var need: Dictionary = c["need"]
	var order := ["code", "art", "music"]

	var base_total := 0
	for k in need.keys():
		base_total += int(need[k])

	# каждый закрытый контракт добавляет две задачи, но не больше десяти
	for i in mini(difficulty * 2, 10):
		var k: String = order[i % order.size()]
		need[k] = int(need[k]) + 1

	# нагрузка растёт от числа игроков, срок — нет
	var mult := maxi(Boot.players.size(), 1)
	var total := 0
	for k in need.keys():
		need[k] = int(need[k]) * mult
		total += int(need[k])

	c["pay"] = int(round(float(c["pay"]) * float(total) / float(maxi(base_total * mult, 1))))
	c["index"] = difficulty + 1
	_bcast("rpc_contract_start", [c])


func request_new_contract() -> void:
	if _is_server():
		_server_new_contract()
	else:
		rpc_id(1, "_req_new_contract")


@rpc("any_peer", "reliable")
func _req_new_contract() -> void:
	if _is_server():
		_server_new_contract()


func _server_new_contract() -> void:
	if contract_running:
		return
	_bcast("rpc_clear_round", [])
	server_start_contract()


func _server_finish(early: bool) -> void:
	if not _is_server() or not contract_running:
		return
	var need: Dictionary = contract["need"]
	var need_total := 0
	var got_total := 0
	for k in need.keys():
		need_total += int(need[k])
		got_total += mini(int(delivered_by[k]), int(need[k]))
	var completeness := float(got_total) / float(maxi(need_total, 1))
	var q := 0.0
	if delivered > 0:
		q = avg_quality()
	var bonus := 0.0
	if early:
		bonus = clampf((1.0 - contract_time / maxf(deadline_seconds(), 1.0)) * 0.15, 0.0, 0.15)
	var score := int(round(100.0 * clampf(0.60 * completeness + 0.32 * q + bonus, 0.0, 1.0)))
	var pay := int(round(float(contract["pay"]) * float(score) / 100.0))
	_bcast("rpc_contract_end", [score, pay, completeness, q, early])


@rpc("authority", "call_local", "reliable")
func rpc_contract_start(c: Dictionary) -> void:
	contract = c.duplicate(true)
	contract_time = 0.0
	contract_running = true
	delivered = 0
	quality_sum = 0.0
	delivered_by = {"code": 0, "art": 0, "music": 0}
	if Boot.results:
		Boot.results.close()
	if Boot.world:
		Boot.world.set_board(contract)
		if Boot.world.assembler:
			Boot.world.assembler.set_count(0, 1.0)
	Boot.update_contract_hud()
	Boot.toast("Новый контракт: %s" % String(contract["title"]), 5.0)


@rpc("authority", "call_local", "reliable")
func rpc_contract_time(t: float) -> void:
	contract_time = t


@rpc("authority", "call_local", "reliable")
func rpc_contract_end(score: int, pay: int, completeness: float, quality: float, early: bool) -> void:
	contract_running = false
	money += pay
	difficulty += 1
	Boot.close_panels(-1)
	if Boot.results:
		Boot.results.show_result(String(contract["title"]), score, completeness, quality, pay, money, early)
	Boot.update_contract_hud()


@rpc("authority", "call_local", "reliable")
func rpc_clear_round() -> void:
	for it in items.values():
		if is_instance_valid(it):
			it.queue_free()
	items.clear()
	for idx in work.keys():
		if Boot.world and int(idx) < Boot.world.stations.size():
			Boot.world.stations[idx].clear_work()
	work.clear()
	Boot.close_panels(-1)


@rpc("authority", "call_local", "reliable")
func rpc_delivered_sync(n: int, q_sum: float, by: Dictionary) -> void:
	delivered = n
	quality_sum = q_sum
	delivered_by = by.duplicate()
	if Boot.world and Boot.world.assembler:
		Boot.world.assembler.set_count(n, avg_quality())
	Boot.update_contract_hud()


# ---------------------------------------------------------------- ХЕЛПЕРЫ

func avg_quality() -> float:
	if delivered <= 0:
		return 1.0
	return quality_sum / float(delivered)


## Единая формула: одна ошибка стоит 9% качества, ниже 25% не падаем.
func quality_for(mistakes: int) -> float:
	return clampf(1.0 - float(mistakes) * 0.09, 0.25, 1.0)


## Сколько ошибок уже накоплено на этом столе (для показа в панели).
func mistakes_of(idx: int) -> int:
	if not work.has(idx):
		return 0
	return int(work[idx]["mistakes"])


func held_item_of(pid: int):
	for it in items.values():
		if it.holder == pid:
			return it
	return null


func is_local_busy() -> bool:
	if Boot.active_panel() != null:
		return true
	if Boot.results != null and Boot.results.active:
		return true
	return false


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
