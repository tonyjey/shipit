extends Node
## Автозагрузка "Game". Правила игры и предметы.
## Авторитет — сервер (хост). Клиенты просят, сервер решает и рассылает.

const ItemScript := preload("res://scripts/item.gd")
const BugScript := preload("res://scripts/bug.gd")

const DISCIPLINES := ["code", "art", "music"]
const TOKENS_PER_TASK := 6
const NOTES_PER_TASK := 8

# --- фаза тестирования
const TESTING_SECONDS := 90.0     # одна неделя на отлов багов
const REVEAL_TIME := 10.0
const REVEAL_COOLDOWN := 3.0
const BUG_SPEED := 2.2            # невидимый баг бегает свободно
const BUG_SPEED_REVEALED := 0.9   # подсвеченный «прижат» сканом и еле ползёт
const BUG_PENALTY := 0.25         # максимальный вычет из оценки за багов
const MISTAKES_PER_BUG := 2.0     # сколько опечаток порождает одного бага
const MAX_BUGS := 12
const NAMING_SECONDS := 40.0
const VOTING_SECONDS := 25.0
const FALLBACK_NAMES := ["Безымянный проект", "Проект без названия", "Рабочее название"]

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
const BASE_PACE := 34.0     # секунд на задачу в первом контракте
const MIN_PACE := 24.0      # к чему сходится темп при росте сложности
const PACE_STEP := 1.3      # насколько поджимается темп за каждый контракт

const CONTRACTS := [
	{"title": "Слэшер / Средневековье", "need": {"code": 3, "art": 3, "music": 3}, "weeks": 3, "pay": 1800},
	{"title": "Платформер / Космос", "need": {"code": 4, "art": 3, "music": 2}, "weeks": 3, "pay": 1800},
	{"title": "Хоррор / Особняк", "need": {"code": 3, "art": 4, "music": 3}, "weeks": 3, "pay": 2000},
	{"title": "Ритм-игра / Неон", "need": {"code": 3, "art": 2, "music": 5}, "weeks": 3, "pay": 2000},
]

var testing := false
var testing_left := 0.0
var bugs: Dictionary = {}
var bugs_total := 0
var bugs_caught := 0
var round_mistakes := 0
var _last_sprite := -1
var peer_skills: Dictionary = {}   # pid -> {id: true}

# фаза «как назовём игру»
var naming := false
var voting := false
var name_options: Array = []      # предложенные названия
var name_owners: Array = []       # чьё какое, чтобы нельзя было голосовать за своё
var phase_left := 0.0
var history: Array = []           # выпущенные игры: {"title", "score"}
var _pending: Dictionary = {}
var _names: Dictionary = {}
var _votes: Dictionary = {}
var reveal_left := 0.0
var reveal_cooldown := 0.0

var _bug_next_id := 1
var _bug_dirs: Dictionary = {}
var _bug_turn: Dictionary = {}
var _bug_sync := 0.0

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
	round_mistakes = 0
	contract = {}
	contract_time = 0.0
	contract_running = false
	delivered_by = {"code": 0, "art": 0, "music": 0}
	_clear_bugs()
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
	if reveal_left > 0.0:
		reveal_left = maxf(reveal_left - delta, 0.0)
	if reveal_cooldown > 0.0:
		reveal_cooldown = maxf(reveal_cooldown - delta, 0.0)
	if testing:
		testing_left = maxf(testing_left - delta, 0.0)
		Boot.update_contract_hud()
	if naming or voting:
		phase_left = maxf(phase_left - delta, 0.0)
	if not _is_server():
		return
	if naming and phase_left <= 0.0:
		_server_close_naming()
		return
	if voting and phase_left <= 0.0:
		_server_close_voting()
		return
	if naming or voting:
		return                      # пока называют игру, мир ждёт
	if testing:
		_tick_testing(delta)
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

# ---------------------------------------------------------------- ТЕСТИРОВАНИЕ

func _tick_testing(delta: float) -> void:
	_move_bugs(delta)
	_bug_sync -= delta
	if _bug_sync <= 0.0:
		_bug_sync = 0.2
		var ids := PackedInt32Array()
		var pos := PackedVector3Array()
		for id in bugs.keys():
			ids.append(int(id))
			pos.append(bugs[id].target_pos)
		if ids.size() > 0:
			_bcast("rpc_bugs_pos", [ids, pos])
	if testing_left <= 0.0:
		_server_finish(false)


func _move_bugs(delta: float) -> void:
	var speed := BUG_SPEED
	if reveal_left > 0.0:
		speed = BUG_SPEED_REVEALED  # скан прижимает бага к полу, его можно догнать
	var lim := 8.4
	for id in bugs.keys():
		var b = bugs[id]
		_bug_turn[id] = float(_bug_turn.get(id, 0.0)) - delta
		if float(_bug_turn[id]) <= 0.0:
			_bug_turn[id] = randf_range(0.7, 1.8)
			_bug_dirs[id] = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		var d: Vector3 = _bug_dirs.get(id, Vector3.FORWARD)
		var np: Vector3 = b.target_pos + d * speed * delta
		if absf(np.x) > lim or absf(np.z) > lim:
			d = -d
			_bug_dirs[id] = d
			np = b.target_pos + d * speed * delta
		np.x = clampf(np.x, -lim, lim)
		np.z = clampf(np.z, -lim, lim)
		np.y = 0.6
		b.target_pos = np


func _server_start_testing() -> void:
	if not _is_server() or testing or not contract_running:
		return
	# Багов ровно столько, сколько наошибались за контракт.
	# Чистая работа — чистый релиз, без выдуманных претензий от тестировщика.
	var n := mini(int(round(float(round_mistakes) / MISTAKES_PER_BUG)), MAX_BUGS)
	if n <= 0:
		Boot.toast("Тестирование: багов не найдено. Релиз!", 4.0)
		_server_finish(true)
		return
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	for i in n:
		ids.append(_bug_next_id)
		_bug_next_id += 1
		pos.append(Vector3(randf_range(-7.5, 7.5), 0.6, randf_range(-7.5, 7.5)))
	_bcast("rpc_testing_start", [ids, pos, minf(TESTING_SECONDS, maxf(deadline_seconds() - contract_time, 15.0))])


func request_reveal() -> void:
	if _is_server():
		_server_reveal()
	else:
		rpc_id(1, "_req_reveal")


@rpc("any_peer", "reliable")
func _req_reveal() -> void:
	if _is_server():
		_server_reveal()


func _server_reveal() -> void:
	if not testing or reveal_left > 0.0 or reveal_cooldown > 0.0:
		return
	_bcast("rpc_reveal", [REVEAL_TIME])


func _clear_bugs() -> void:
	for b in bugs.values():
		if is_instance_valid(b):
			b.queue_free()
	bugs.clear()
	_bug_dirs.clear()
	_bug_turn.clear()
	testing = false
	testing_left = 0.0
	bugs_total = 0
	bugs_caught = 0
	reveal_left = 0.0
	reveal_cooldown = 0.0


@rpc("authority", "call_local", "reliable")
func rpc_testing_start(ids: PackedInt32Array, pos: PackedVector3Array, seconds: float) -> void:
	_clear_bugs()
	testing = true
	testing_left = seconds
	bugs_total = ids.size()
	bugs_caught = 0
	if Boot.world == null:
		return
	for i in ids.size():
		var b := BugScript.new()
		b.name = "bug_%d" % ids[i]
		b.bug_id = ids[i]
		b.start_pos = pos[i]
		bugs[ids[i]] = b
		Boot.world.bugs_root.add_child(b)
	Boot.toast("ТЕСТИРОВАНИЕ: в игре %d багов. Подсвечивай их на QA-терминале и лови." % bugs_total, 7.0)


@rpc("authority", "call_local", "unreliable_ordered")
func rpc_bugs_pos(ids: PackedInt32Array, pos: PackedVector3Array) -> void:
	for i in ids.size():
		if bugs.has(ids[i]):
			bugs[ids[i]].target_pos = pos[i]


@rpc("authority", "call_local", "reliable")
func rpc_reveal(duration: float) -> void:
	reveal_left = duration
	reveal_cooldown = duration + REVEAL_COOLDOWN
	Boot.toast("Багов видно!", 2.0)


@rpc("authority", "call_local", "reliable")
func rpc_bug_caught(id: int, caught: int) -> void:
	bugs_caught = caught
	if bugs.has(id):
		bugs[id].queue_free()
		bugs.erase(id)
	Boot.update_contract_hud()


func bugs_left() -> int:
	return maxi(bugs_total - bugs_caught, 0)


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
		rpc_id(to_id, "rpc_work_progress", int(idx), int(w["done"]), int(w["mistakes"]), w["filled"])
		rpc_id(to_id, "rpc_work_occupant", int(idx), int(w["occupant"]))
	if Boot.world:
		for i in Boot.world.doors.size():
			rpc_id(to_id, "rpc_door", i, bool(Boot.world.doors[i].is_open), 1)
	if contract_running:
		rpc_id(to_id, "rpc_contract_start", contract)
		rpc_id(to_id, "rpc_contract_time", contract_time)
	rpc_id(to_id, "rpc_delivered_sync", delivered, quality_sum, delivered_by)


# ---------------------------------------------------------------- ЗАПРОСЫ

func request_interact(type: String, id: int) -> void:
	# Магазин ничего не меняет в общем мире: кошелёк и навыки личные.
	# Раньше запрос уходил на сервер, и панель открывалась у хоста, а не у того,
	# кто нажал E.
	if type == "shop":
		if Boot.shop_panel:
			Boot.shop_panel.open_shop()
		return
	if _is_server():
		_server_interact(Boot.local_id(), type, id)
	else:
		rpc_id(1, "_req_interact", type, id)


func request_drop() -> void:
	if _is_server():
		_server_drop(Boot.local_id())
	else:
		rpc_id(1, "_req_drop")


## slot — какой именно элемент задачи закрыт. Для терминала и ритма это
## всегда следующий по порядку (-1), для раскраски — конкретная клетка.
func request_token(idx: int, mistakes: int, slot := -1) -> void:
	if _is_server():
		_server_token(Boot.local_id(), idx, mistakes, slot)
	else:
		rpc_id(1, "_req_token", idx, mistakes, slot)


## mistakes — то, что игрок наошибался с последнего засчитанного элемента.
## Без этого можно было выйти по Esc и вернуться с чистой совестью.
func request_leave_station(idx: int, mistakes := 0) -> void:
	if _is_server():
		_server_leave(Boot.local_id(), idx, mistakes)
	else:
		rpc_id(1, "_req_leave", idx, mistakes)


@rpc("any_peer", "reliable")
func _req_interact(type: String, id: int) -> void:
	if _is_server():
		_server_interact(multiplayer.get_remote_sender_id(), type, id)


@rpc("any_peer", "reliable")
func _req_drop() -> void:
	if _is_server():
		_server_drop(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _req_token(idx: int, mistakes: int, slot: int) -> void:
	if _is_server():
		_server_token(multiplayer.get_remote_sender_id(), idx, mistakes, slot)


@rpc("any_peer", "reliable")
func _req_leave(idx: int, mistakes: int) -> void:
	if _is_server():
		_server_leave(multiplayer.get_remote_sender_id(), idx, mistakes)


# ---------------------------------------------------------------- ЛОГИКА СЕРВЕРА

func _server_interact(pid: int, type: String, id: int) -> void:
	if not _is_server() or Boot.world == null:
		return
	var held = held_item_of(pid)

	match type:
		"item":
			if not items.has(id):
				return
			if held_items_of(pid).size() >= carry_capacity(pid):
				return
			var it = items[id]
			if it.holder != 0:
				return
			_bcast("rpc_item_state", [id, pid, it.global_position])
			if pid == Boot.local_id():
				Boot.play_sfx("pickup")

		"station":
			if id < 0 or id >= Boot.world.stations.size():
				return
			var st = Boot.world.stations[id]
			held = _pick_held(pid, "ticket_" + String(st.discipline))
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

		"bug":
			if not testing or reveal_left <= 0.0 or not bugs.has(id):
				return
			# rpc_bug_caught уже увеличил счётчик, поэтому сравниваем как есть.
			# Раньше здесь было bugs_caught + 1 — игра выходила на одного бага раньше.
			_bcast("rpc_bug_caught", [id, bugs_caught + 1])
			if pid == Boot.local_id():
				Boot.play_sfx("bug")
			if bugs_caught >= bugs_total:
				_server_finish(true)
			return

		"qa":
			_server_reveal()
			return

		"door":
			if Boot.world == null or id < 0 or id >= Boot.world.doors.size():
				return
			var dr = Boot.world.doors[id]
			var swing := 1
			if Boot.players.has(pid):
				var who := Boot.players[pid] as Node3D
				# распахиваем от игрока, а не ему в лицо
				swing = 1 if who.global_position.x < dr.global_position.x else -1
			_bcast("rpc_door", [id, not bool(dr.is_open), swing])
			return

		"board":
			# контракт берут вручную — между релизами должна быть передышка
			if contract_running or testing:
				return
			_server_new_contract()
			return

		"assembler":
			held = _pick_held(pid, "asset_")
			if held == null:
				# пустые руки: всё готово — отправляем на тестирование
				if contract_running and not testing and requirements_met():
					_server_start_testing()
				return
			if not String(held.kind).begins_with("asset_"):
				return
			var q: float = float(held.quality)
			var disc := String(held.kind).substr(6)
			_bcast("rpc_item_remove", [held.item_id])
			_bcast("rpc_delivered", [delivered + 1, quality_sum + q, disc])
			if pid == Boot.local_id():
				Boot.play_sfx("deliver")


## Ищем в руках предмет нужного вида. С двумя руками их может быть два,
## и брать всегда первый попавшийся — верный способ обидеть игрока.
## Публичная версия для подсказок у столов и сборщика.
func held_of_kind(pid: int, prefix: String):
	return _pick_held(pid, prefix)


func _pick_held(pid: int, prefix: String):
	for it in held_items_of(pid):
		if String(it.kind).begins_with(prefix):
			return it
	return null


func _server_drop(pid: int) -> void:
	if not _is_server():
		return
	var list := held_items_of(pid)
	if list.is_empty() or not Boot.players.has(pid):
		return
	var held = list[list.size() - 1]   # бросаем то, что взяли последним
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


func _server_token(pid: int, idx: int, mistakes: int, slot: int) -> void:
	if not _is_server() or not work.has(idx):
		return
	var w: Dictionary = work[idx]
	if int(w["occupant"]) != pid:
		return
	var filled: Array = w["filled"]
	var s := slot
	if s < 0:
		s = filled.size()
	if filled.has(s):
		return
	filled.append(s)
	w["done"] = filled.size()
	w["mistakes"] = int(w["mistakes"]) + maxi(mistakes, 0)

	var toks: Array = w["tokens"]
	if int(w["done"]) < toks.size():
		_bcast("rpc_work_progress", [idx, int(w["done"]), int(w["mistakes"]), filled])
		return

	var disc: String = String(w["disc"])
	round_mistakes += int(w["mistakes"])
	var quality := quality_for(int(w["mistakes"]))
	var st = Boot.world.stations[idx]
	_bcast("rpc_work_end", [idx])
	server_spawn_item("asset_" + disc, st.output_position(), quality)


# ---------------------------------------------------------------- НАЗВАНИЕ ИГРЫ

func name_owner(idx: int) -> int:
	if idx < 0 or idx >= name_owners.size():
		return 0
	return int(name_owners[idx])


## Клиент сообщает серверу свои навыки: часть из них — правила, а правила
## живут на сервере (например, сколько предметов можно нести).
func push_skills() -> void:
	var list: Array = Boot.skills.keys()
	if _is_server():
		_server_skills(Boot.local_id(), list)
	else:
		rpc_id(1, "_req_skills", list)


@rpc("any_peer", "reliable")
func _req_skills(list: Array) -> void:
	if _is_server():
		_server_skills(multiplayer.get_remote_sender_id(), list)


func _server_skills(pid: int, list: Array) -> void:
	var d := {}
	for id in list:
		d[String(id)] = true
	peer_skills[pid] = d


func peer_has(pid: int, id: String) -> bool:
	if not peer_skills.has(pid):
		return false
	return bool(peer_skills[pid].has(id))


func carry_capacity(pid: int) -> int:
	return 2 if peer_has(pid, "two_hands") else 1


## Все предметы в руках игрока, по порядку взятия.
func held_items_of(pid: int) -> Array:
	var out: Array = []
	for it in items.values():
		if it.holder == pid:
			out.append(it)
	out.sort_custom(func(a, b): return int(a.item_id) < int(b.item_id))
	return out


## Какой по счёту предмет в руках — нужно, чтобы разложить их по ладоням.
func hold_index_of(item_id: int, pid: int) -> int:
	var list := held_items_of(pid)
	for i in list.size():
		if int(list[i].item_id) == item_id:
			return i
	return 0


func request_name(text: String) -> void:
	if _is_server():
		_server_name(Boot.local_id(), text)
	else:
		rpc_id(1, "_req_name", text)


func request_vote(idx: int) -> void:
	if _is_server():
		_server_vote(Boot.local_id(), idx)
	else:
		rpc_id(1, "_req_vote", idx)


@rpc("any_peer", "reliable")
func _req_name(text: String) -> void:
	if _is_server():
		_server_name(multiplayer.get_remote_sender_id(), text)


@rpc("any_peer", "reliable")
func _req_vote(idx: int) -> void:
	if _is_server():
		_server_vote(multiplayer.get_remote_sender_id(), idx)


func _server_name(pid: int, text: String) -> void:
	if not _is_server() or not naming or _names.has(pid):
		return
	var clean := text.strip_edges().substr(0, 26)
	if clean.is_empty():
		return
	_names[pid] = clean
	_bcast("rpc_phase_progress", [_names.size(), maxi(Boot.players.size(), 1)])
	if _names.size() >= maxi(Boot.players.size(), 1):
		_server_close_naming()


func _server_vote(pid: int, idx: int) -> void:
	if not _is_server() or not voting or _votes.has(pid):
		return
	if idx < 0 or idx >= name_options.size():
		return
	_votes[pid] = idx
	_bcast("rpc_phase_progress", [_votes.size(), maxi(Boot.players.size(), 1)])
	if _votes.size() >= maxi(Boot.players.size(), 1):
		_server_close_voting()


func _server_close_naming() -> void:
	if not _is_server() or not naming:
		return
	# кто не успел — за того придумывает издатель
	for pid in Boot.players.keys():
		if not _names.has(pid):
			_names[pid] = String(FALLBACK_NAMES[randi() % FALLBACK_NAMES.size()])

	var opts: Array = []
	var owners: Array = []
	for pid in _names.keys():
		var t: String = String(_names[pid])
		if opts.has(t):
			continue
		opts.append(t)
		owners.append(int(pid))

	if opts.size() <= 1:
		_server_apply_title(String(opts[0]) if opts.size() == 1 else "Безымянный проект")
		return
	_bcast("rpc_voting_start", [opts, owners, VOTING_SECONDS])


func _server_close_voting() -> void:
	if not _is_server() or not voting:
		return
	var tally: Array = []
	for i in name_options.size():
		tally.append(0)
	for pid in _votes.keys():
		var i := int(_votes[pid])
		tally[i] = int(tally[i]) + 1

	var best := 0
	for i in tally.size():
		if int(tally[i]) > int(tally[best]):
			best = i
	# при равенстве голосов выбираем случайное из лидеров
	var leaders: Array = []
	for i in tally.size():
		if int(tally[i]) == int(tally[best]):
			leaders.append(i)
	best = int(leaders[randi() % leaders.size()])
	_server_apply_title(String(name_options[best]))


func _server_apply_title(title: String) -> void:
	var p := _pending
	_bcast("rpc_contract_end", [title, int(p["score"]), int(p["pay"]), float(p["completeness"]),
		float(p["quality"]), bool(p["early"]), int(p["bug_left"]), int(p["bug_total"])])


@rpc("authority", "call_local", "reliable")
func rpc_naming_start(seconds: float, contract_title: String) -> void:
	naming = true
	voting = false
	phase_left = seconds
	name_options = []
	name_owners = []
	if Boot.naming_panel:
		Boot.naming_panel.open_naming(seconds, contract_title)


@rpc("authority", "call_local", "reliable")
func rpc_voting_start(opts: Array, owners: Array, seconds: float) -> void:
	naming = false
	voting = true
	phase_left = seconds
	name_options = opts.duplicate()
	name_owners = owners.duplicate()
	if Boot.naming_panel:
		Boot.naming_panel.open_voting(name_options, seconds)


@rpc("authority", "call_local", "reliable")
func rpc_door(id: int, open_state: bool, swing := 1) -> void:
	if Boot.world == null or id < 0 or id >= Boot.world.doors.size():
		return
	Boot.world.doors[id].set_open(open_state, swing)
	Boot.play_sfx("click")


@rpc("authority", "call_local", "reliable")
func rpc_phase_progress(done_count: int, total_count: int) -> void:
	if Boot.naming_panel:
		Boot.naming_panel.set_progress(done_count, total_count)


func _server_leave(pid: int, idx: int, mistakes := 0) -> void:
	if not _is_server() or not work.has(idx):
		return
	var w: Dictionary = work[idx]
	if int(w["occupant"]) != pid:
		return
	if mistakes > 0:
		w["mistakes"] = int(w["mistakes"]) + mistakes
		_bcast("rpc_work_progress", [idx, int(w["done"]), int(w["mistakes"]), w["filled"]])
	_bcast("rpc_work_occupant", [idx, 0])


func _make_tokens(disc: String) -> Array:
	var out: Array = []
	# музыка играется как ритм-игра: токен = номер дорожки
	if disc == "music":
		# примерно каждая четвёртая нота — длинная: её нужно зажать и держать
		var last := -1
		var holds := 0
		for i in NOTES_PER_TASK:
			var lane := randi() % 4
			if lane == last and randf() < 0.6:
				lane = (lane + 1 + randi() % 3) % 4
			last = lane
			var make_hold := holds < 2 and i > 0 and randf() < 0.3
			if make_hold:
				holds += 1
				out.append("%d:%.2f" % [lane, 0.7 + randf() * 0.5])
			else:
				out.append(str(lane))
		return out
	# графика — раскраска: токен это «клетка:цвет», идём цветами подряд,
	# чтобы кисть приходилось менять три-четыре раза, а не на каждой клетке
	if disc == "art":
		# не повторяем предыдущий рисунок и каждый раз тасуем палитру:
		# один и тот же спрайт подряд читался как поломка
		var pick := randi() % SPRITES.size()
		if SPRITES.size() > 1 and pick == _last_sprite:
			pick = (pick + 1 + randi() % (SPRITES.size() - 1)) % SPRITES.size()
		_last_sprite = pick
		var tpl: Array = SPRITES[pick]
		var palette_map := [0, 1, 2, 3]
		palette_map.shuffle()
		var by_color: Dictionary = {}
		for r in tpl.size():
			var row: String = tpl[r]
			for c in row.length():
				var ch := row.substr(c, 1)
				if ch == ".":
					continue
				var col := int(palette_map[int(ch) % palette_map.size()])
				if not by_color.has(col):
					by_color[col] = []
				by_color[col].append(r * 4 + c)
		var colors: Array = by_color.keys()
		colors.shuffle()
		for col in colors:
			for cell in by_color[col]:
				out.append("%d:%d" % [int(cell), int(col)])
		return out

	# Берём слова без повторов: одно и то же слово по три раза подряд
	# читалось как баг, а не как задание.
	var pool: Array = WORDS[disc].duplicate()
	pool.shuffle()
	for i in TOKENS_PER_TASK:
		if pool.is_empty():
			pool = WORDS[disc].duplicate()
			pool.shuffle()
		out.append(String(pool.pop_back()))
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
	work[idx] = {"disc": disc, "tokens": tokens.duplicate(), "done": 0, "mistakes": 0, "occupant": occupant, "filled": []}
	Boot.world.stations[idx].set_work(tokens.size(), 0)
	if occupant == Boot.local_id():
		var panel = Boot.panel_for(disc)
		if panel:
			panel.open(idx, disc, tokens, 0)


@rpc("authority", "call_local", "reliable")
func rpc_work_progress(idx: int, done: int, mistakes: int, filled: Array) -> void:
	if not work.has(idx):
		return
	work[idx]["done"] = done
	work[idx]["mistakes"] = mistakes
	work[idx]["filled"] = filled.duplicate()
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

## Подхватываем сохранённый прогресс студии перед первым контрактом.
func apply_progress(saved_money: int, saved_difficulty: int, saved_history: Array = []) -> void:
	if not _is_server():
		return
	money = saved_money
	difficulty = saved_difficulty
	history = saved_history.duplicate()
	if Boot.world:
		Boot.world.set_shelf(history)


func server_start_contract() -> void:
	if not _is_server():
		return
	var c: Dictionary = CONTRACTS[randi() % CONTRACTS.size()].duplicate(true)
	var need: Dictionary = c["need"]
	var order := ["code", "art", "music"]

	var base_total := 0
	for k in need.keys():
		base_total += int(need[k])

	# каждый закрытый контракт добавляет одну задачу, но не больше шести
	for i in mini(difficulty, 6):
		var k: String = order[i % order.size()]
		need[k] = int(need[k]) + 1

	# нагрузка растёт от числа игроков
	var mult := maxi(Boot.players.size(), 1)
	var total := 0
	for k in need.keys():
		need[k] = int(need[k]) * mult
		total += int(need[k])

	# Срок выводим из объёма: давление создаёт темп, а не стена.
	# С каждым контрактом на задачу отводится чуть меньше секунд.
	var pace := maxf(MIN_PACE, BASE_PACE - PACE_STEP * float(difficulty))
	var per_player := float(total) / float(mult)
	c["weeks"] = maxi(2, int(round(per_player * pace / WEEK_SECONDS)))

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
	if contract_running or testing:
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
	# без багов штрафа нет: раньше здесь по умолчанию стояла единица,
	# и чистый релиз всё равно терял 25 очков
	var bug_ratio := 0.0
	if bugs_total > 0:
		bug_ratio = float(bugs_left()) / float(bugs_total)
	var bonus := 0.0
	if early:
		bonus = clampf((1.0 - contract_time / maxf(deadline_seconds(), 1.0)) * 0.15, 0.0, 0.15)
	var score := int(round(100.0 * clampf(
		0.60 * completeness + 0.32 * q + bonus - BUG_PENALTY * bug_ratio, 0.0, 1.0)))
	var pay := int(round(float(contract["pay"]) * float(score) / 100.0))
	# Оценку пока не показываем: сначала команда даёт игре имя.
	_pending = {
		"score": score, "pay": pay, "completeness": completeness,
		"quality": q, "early": early, "bug_left": bugs_left(), "bug_total": bugs_total,
	}
	_names = {}
	_votes = {}
	_bcast("rpc_naming_start", [NAMING_SECONDS, String(contract["title"])])


@rpc("authority", "call_local", "reliable")
func rpc_contract_start(c: Dictionary) -> void:
	contract = c.duplicate(true)
	contract_time = 0.0
	contract_running = true
	delivered = 0
	quality_sum = 0.0
	delivered_by = {"code": 0, "art": 0, "music": 0}
	round_mistakes = 0
	_clear_bugs()
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
func rpc_contract_end(title: String, score: int, pay: int, completeness: float, quality: float, early: bool, bug_left: int, bug_total: int) -> void:
	naming = false
	voting = false
	if Boot.naming_panel:
		Boot.naming_panel.close()
	history.append({"title": title, "score": score})
	if Boot.world:
		Boot.world.set_shelf(history)
	contract_running = false
	# Половина гонорара — в фонд студии, половина — каждому в карман.
	# Кому польза, тот и платит: апгрейды офиса из фонда, навыки из своего.
	var share := int(round(float(pay) * 0.5))
	money += pay - share
	Boot.add_wallet(share)
	difficulty += 1
	# сохраняем уже после инкремента, иначе «Продолжить» откатывало на контракт назад
	if Boot.is_host():
		Boot.save_progress(money, difficulty, history)
	Boot.play_sfx("fanfare")
	Boot.close_panels(-1)
	if Boot.world:
		Boot.world.clear_board()
		if Boot.world.assembler:
			Boot.world.assembler.set_count(0, 1.0)
	if Boot.results:
		Boot.results.show_result(title, String(contract["title"]), score, completeness, quality, pay, money, early, bug_left, bug_total, history)
	_clear_bugs()
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
	_clear_bugs()
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
## Какие элементы задачи уже закрыты — нужно раскраске, чтобы поднять
## работу с той же точки, если за стол сел другой игрок.
func filled_of(idx: int) -> Array:
	if not work.has(idx):
		return []
	return work[idx]["filled"]


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
	if Boot.naming_panel != null and Boot.naming_panel.active:
		return true
	if Boot.shop_open():
		return true
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
