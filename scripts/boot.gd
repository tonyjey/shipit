extends Node
## Точка входа. Автозагрузка (singleton "Boot").
## Отвечает за: настройку ввода, меню, сеть, спавн игроков, HUD.

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

var world: Node3D = null
var players: Dictionary = {}          # peer_id -> Player
var solo_mode := false
var in_game := false

var _hud: CanvasLayer = null
var _menu: Control = null
var _ip_edit: LineEdit = null
var _status: Label = null
var _prompt: Label = null
var _toast: Label = null
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
	_bind("free_mouse", KEY_ESCAPE)


func _bind(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	get_tree().root.add_child(_hud)

	# --- подсказка взаимодействия (центр экрана)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-200, 60)
	_prompt.size = Vector2(400, 30)
	_prompt.add_theme_font_size_override("font_size", 20)
	_hud.add_child(_prompt)

	# --- тост (сообщения)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(-300, 40)
	_toast.size = Vector2(600, 30)
	_toast.add_theme_font_size_override("font_size", 22)
	_hud.add_child(_toast)

	# --- меню
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
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "SHIP IT!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "прототип v0.1 — каркас"
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
	solo_mode = false
	_enter_game()
	_spawn_player(1)
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
	solo_mode = false
	_set_status("Подключаюсь к %s..." % ip)


func _solo() -> void:
	solo_mode = true
	multiplayer.multiplayer_peer = null
	_enter_game()
	_spawn_player(1)


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
	pass  # ждём _request_join от клиента


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		rpc("_remote_despawn", id)


## Клиент сообщает серверу, что мир построен и он готов принять игроков.
@rpc("any_peer", "reliable")
func _request_join() -> void:
	if not multiplayer.is_server():
		return
	var new_id := multiplayer.get_remote_sender_id()
	for existing_id in players.keys():
		rpc_id(new_id, "_remote_spawn", existing_id)
	rpc("_remote_spawn", new_id)


@rpc("authority", "call_local", "reliable")
func _remote_spawn(id: int) -> void:
	_spawn_player(id)


@rpc("authority", "call_local", "reliable")
func _remote_despawn(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
		toast("Игрок %d вышел" % id)


# ---------------------------------------------------------------- МИР / ИГРОКИ

func _enter_game() -> void:
	if in_game:
		return
	in_game = true
	_menu.visible = false
	world = WorldScript.new()
	world.name = "World"
	get_tree().current_scene.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leave_game() -> void:
	in_game = false
	multiplayer.multiplayer_peer = null
	players.clear()
	if world:
		world.queue_free()
		world = null
	_menu.visible = true
	set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _spawn_player(id: int) -> void:
	if world == null or players.has(id):
		return
	var index := players.size()
	var p := PlayerScript.new()
	p.name = str(id)
	p.peer_id = id
	p.color = COLORS[index % COLORS.size()]
	p.spawn_pos = world.get_spawn_point(index)
	p.set_multiplayer_authority(id)
	players[id] = p
	world.add_child(p)


func local_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1
