extends Node
## Точка входа. Автозагрузка "Boot".
## Отвечает за: ввод, меню, сеть, спавн игроков, HUD.

const PORT := 7777
const MAX_PLAYERS := 4

const PlayerScript := preload("res://scripts/player.gd")
const WorldScript := preload("res://scripts/world.gd")

const COLORS := [
	Color(0.95, 0.36, 0.36),
	Color(0.36, 0.66, 0.96),
	Color(0.45, 0.85, 0.48),
	Color(0.97, 0.80, 0.35),
]

var world = null
var players: Dictionary = {}     # peer_id -> Player
var slots: Dictionary = {}       # peer_id -> 1..4
var ready_peers: Array = []      # кому уже можно слать состояние
var in_game := false

var _hud: CanvasLayer = null
var _menu: Control = null
var _ip_edit: LineEdit = null
var _status: Label = null
var _prompt: Label = null
var _toast: Label = null
var _hint: Label = null
var _toast_time := 0.0


func _ready() -> void:
	_setup_input()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	call_deferred("_build_ui")


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0 and _toast:
			_toast.text = ""


# ---------------------------------------------------------------- ВВОД

func _setup_input() -> void:
	_bind("move_forward", KEY_W)
	_bind("move_back", KEY_S)
	_bind("move_left", KEY_A)
	_bind("move_right", KEY_D)
	_bind("jump", KEY_SPACE)
	_bind("interact", KEY_E)
	_bind("drop", KEY_Q)
	_bind("free_mouse", KEY_ESCAPE)


func _bind(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- UI

func _mk_label(size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l


func _build_ui() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	get_tree().root.add_child(_hud)

	# подсказка взаимодействия — чуть ниже центра
	_prompt = _mk_label(22)
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.offset_top = 110
	_hud.add_child(_prompt)

	# что в руках — внизу
	_hint = _mk_label(20)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.offset_bottom = -30
	_hud.add_child(_hint)

	# всплывающие сообщения — сверху
	_toast = _mk_label(24)
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_toast.offset_top = 50
	_hud.add_child(_toast)

	# меню
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_menu)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "SHIP IT!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "прототип v0.2 — конвейер"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(Control.new())

	var b_host := Button.new()
	b_host.text = "Создать комнату (хост)"
	b_host.pressed.connect(_host)
	box.add_child(b_host)

	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "IP хоста"
	box.add_child(_ip_edit)

	var b_join := Button.new()
	b_join.text = "Подключиться"
	b_join.pressed.connect(_join)
	box.add_child(b_join)

	var b_solo := Button.new()
	b_solo.text = "Соло (без сети)"
	b_solo.pressed.connect(_solo)
	box.add_child(b_solo)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
	box.add_child(_status)


func set_prompt(text: String) -> void:
	if _prompt:
		_prompt.text = text


func set_hint(text: String) -> void:
	if _hint:
		_hint.text = text


func toast(text: String, seconds := 2.5) -> void:
	if _toast:
		_toast.text = text
		_toast_time = seconds


func _set_status(text: String) -> void:
	if _status:
		_status.text = text


# ---------------------------------------------------------------- СЕТЬ

func _host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		_set_status("Не удалось поднять сервер (код %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	_enter_game()
	ready_peers = [1]
	_spawn_player(1, 1)
	toast("Комната создана. Порт %d" % PORT)


func _join() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_set_status("Введи IP")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_set_status("Не удалось подключиться (код %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Подключаюсь к %s..." % ip)


func _solo() -> void:
	multiplayer.multiplayer_peer = null
	_enter_game()
	ready_peers = [1]
	_spawn_player(1, 1)


func _on_connected_ok() -> void:
	_enter_game()
	rpc_id(1, "_request_join")


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	_set_status("Подключение не удалось")


func _on_server_disconnected() -> void:
	toast("Хост отключился")
	_leave_game()


func _on_peer_connected(_id: int) -> void:
	pass  # ждём _request_join — клиент сам скажет, когда построит мир


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	Game.server_release_items(id)
	ready_peers.erase(id)
	rpc("_sync_ready", ready_peers)
	rpc("_remote_despawn", id)


func _free_slot() -> int:
	for s in range(1, MAX_PLAYERS + 1):
		if not slots.values().has(s):
			return s
	return 1


## Клиент сообщает: мир построен, можно присылать игроков и предметы.
@rpc("any_peer", "reliable")
func _request_join() -> void:
	if not multiplayer.is_server():
		return
	var new_id := multiplayer.get_remote_sender_id()
	for existing_id in players.keys():
		rpc_id(new_id, "_remote_spawn", existing_id, int(slots[existing_id]))
	rpc("_remote_spawn", new_id, _free_slot())
	ready_peers.append(new_id)
	rpc("_sync_ready", ready_peers)
	Game.server_send_snapshot(new_id)


@rpc("authority", "call_local", "reliable")
func _sync_ready(list: Array) -> void:
	ready_peers = list.duplicate()


@rpc("authority", "call_local", "reliable")
func _remote_spawn(id: int, slot: int) -> void:
	_spawn_player(id, slot)


@rpc("authority", "call_local", "reliable")
func _remote_despawn(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
		slots.erase(id)
		toast("Игрок вышел")


# ---------------------------------------------------------------- МИР / ИГРОКИ

func _enter_game() -> void:
	if in_game:
		return
	in_game = true
	_menu.visible = false
	Game.reset()
	world = WorldScript.new()
	world.name = "World"
	get_tree().current_scene.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toast("WASD — ходить, E — взаимодействие, Q — бросить", 6.0)


func _leave_game() -> void:
	in_game = false
	multiplayer.multiplayer_peer = null
	players.clear()
	slots.clear()
	ready_peers.clear()
	Game.reset()
	if world:
		world.queue_free()
		world = null
	_menu.visible = true
	set_prompt("")
	set_hint("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _spawn_player(id: int, slot: int) -> void:
	if world == null or players.has(id):
		return
	var p := PlayerScript.new()
	p.name = str(id)
	p.peer_id = id
	p.slot = slot
	p.color = COLORS[(slot - 1) % COLORS.size()]
	p.spawn_pos = world.get_spawn_point(slot - 1)
	p.set_multiplayer_authority(id)
	players[id] = p
	slots[id] = slot
	world.add_child(p)


func local_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1


func local_player() -> Node3D:
	var id := local_id()
	if players.has(id):
		return players[id]
	return null
