extends Node
## Точка входа. Автозагрузка "Boot".
## Отвечает за: ввод, меню, сеть, спавн игроков, HUD.

const VERSION := "v1.1"
const PORT := 7777
const MAX_PLAYERS := 4

const PlayerScript := preload("res://scripts/player.gd")
const WorldScript := preload("res://scripts/world.gd")
const TerminalScript := preload("res://scripts/terminal.gd")
const ResultsScript := preload("res://scripts/results.gd")
const SettingsScript := preload("res://scripts/settings_panel.gd")
const PauseScript := preload("res://scripts/pause_menu.gd")
const RhythmScript := preload("res://scripts/rhythm.gd")
const PaintScript := preload("res://scripts/paint.gd")

const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.json"

const DEFAULT_BINDS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"interact": KEY_E,
	"drop": KEY_Q,
}

const MUSIC_PATH := "res://audio/music/theme_loop.ogg"

const SFX := {
	"click": "res://audio/ui_click.wav",
	"pickup": "res://audio/pickup.wav",
	"deliver": "res://audio/deliver.wav",
	"error": "res://audio/error.wav",
	"bug": "res://audio/bug.wav",
	"fanfare": "res://audio/fanfare.wav",
}

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
var terminal = null
var rhythm = null
var paint = null
var mouse_wanted := false
var _crosshair: ColorRect = null
var settings_panel = null
var pause_menu = null
var _music: AudioStreamPlayer = null
var binds: Dictionary = {}
var volumes: Dictionary = {"master": 0.8, "sfx": 0.8, "music": 0.55}
var save_money := 0
var save_difficulty := 0

var _sfx_players: Array = []
var _sfx_next := 0
var _save_label: Label = null
var results = null
var _contract_label: Label = null

var _hud: CanvasLayer = null
var _menu: Control = null
var _ip_edit: LineEdit = null
var _status: Label = null
var _prompt: Label = null
var _toast: Label = null
var _hint: Label = null
var _toast_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	load_progress()
	_setup_input()
	_setup_audio()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	call_deferred("_build_ui")


func _process(delta: float) -> void:
	if _crosshair:
		# прицел прячем, когда управление у панели или у меню
		_crosshair.visible = in_game and mouse_wanted and active_panel() == null \
			and not (results != null and results.active)
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0 and _toast:
			_toast.text = ""


# ---------------------------------------------------------------- ВВОД

func _setup_input() -> void:
	for action in DEFAULT_BINDS.keys():
		_bind(String(action), int(binds.get(action, DEFAULT_BINDS[action])))
	_bind("free_mouse", KEY_ESCAPE)
	_bind("toggle_view", KEY_V)
	_bind("debug_info", KEY_F1)


func rebind(action: String, keycode: int) -> void:
	binds[action] = keycode
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	_bind(action, keycode)
	save_settings()


func reset_binds() -> void:
	binds = DEFAULT_BINDS.duplicate()
	for action in DEFAULT_BINDS.keys():
		if InputMap.has_action(String(action)):
			InputMap.action_erase_events(String(action))
		_bind(String(action), int(DEFAULT_BINDS[action]))
	save_settings()


func key_name_of(action: String) -> String:
	var code := int(binds.get(action, DEFAULT_BINDS.get(action, KEY_NONE)))
	var nm := OS.get_keycode_string(code)
	if nm == "":
		nm = "?"
	return nm


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
	_hud.layer = 100
	_hud.process_mode = Node.PROCESS_MODE_ALWAYS
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

	# значок версии — если его не видно, значит 2D-интерфейс не рисуется вообще
	var badge := Label.new()
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge.position = Vector2(14, 10)
	badge.size = Vector2(320, 26)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.text = "Ship It! %s   [F1] диагностика" % VERSION
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_constant_override("outline_size", 6)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	badge.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.85))
	_hud.add_child(badge)

	# прицел — точка в центре экрана
	_crosshair = ColorRect.new()
	_crosshair.color = Color(1, 1, 1, 0.75)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.size = Vector2(5, 5)
	_crosshair.position = Vector2(-2.5, -2.5)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.visible = false
	_hud.add_child(_crosshair)

	# сводка по контракту — правый верхний угол
	_contract_label = Label.new()
	_contract_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_contract_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_contract_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_contract_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_contract_label.offset_top = 36.0
	_contract_label.offset_right = -18.0
	_contract_label.add_theme_font_size_override("font_size", 19)
	_contract_label.add_theme_constant_override("outline_size", 7)
	_contract_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_child(_contract_label)

	# терминал мини-игры
	terminal = TerminalScript.new()
	_hud.add_child(terminal)

	# ритм-игра для стола «Музыка»
	rhythm = RhythmScript.new()
	_hud.add_child(rhythm)

	# раскраска для стола «Графика»
	paint = PaintScript.new()
	_hud.add_child(paint)

	# экран сдачи игры
	results = ResultsScript.new()
	_hud.add_child(results)

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
	sub.text = "прототип %s" % VERSION
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

	box.add_child(HSeparator.new())

	_save_label = Label.new()
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_label.add_theme_font_size_override("font_size", 14)
	_save_label.add_theme_color_override("font_color", Color(0.70, 0.74, 0.82))
	box.add_child(_save_label)
	_refresh_save_label()

	var b_reset := Button.new()
	b_reset.text = "Начать заново (сбросить прогресс)"
	b_reset.pressed.connect(func():
		play_sfx("click")
		reset_progress()
		toast("Прогресс сброшен", 3.0))
	box.add_child(b_reset)

	var b_settings := Button.new()
	b_settings.text = "Настройки"
	b_settings.pressed.connect(func():
		play_sfx("click")
		if settings_panel:
			settings_panel.open_panel())
	box.add_child(b_settings)

	var b_quit := Button.new()
	b_quit.text = "Выход"
	b_quit.pressed.connect(func():
		play_sfx("click")
		get_tree().quit())
	box.add_child(b_quit)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
	box.add_child(_status)

	settings_panel = SettingsScript.new()
	_hud.add_child(settings_panel)

	pause_menu = PauseScript.new()
	_hud.add_child(pause_menu)

	# свои адреса, чтобы было что продиктовать напарнику
	var ip_info := Label.new()
	ip_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ip_info.custom_minimum_size = Vector2(380, 0)
	ip_info.add_theme_font_size_override("font_size", 14)
	ip_info.add_theme_color_override("font_color", Color(0.60, 0.64, 0.72))
	ip_info.text = "Твои адреса для друга: %s\nПорт 7777 (UDP)" % ", ".join(local_ips())
	box.add_child(ip_info)


func _setup_audio() -> void:
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, "SFX")
		AudioServer.set_bus_send(1, "Master")
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus(2)
		AudioServer.set_bus_name(2, "Music")
		AudioServer.set_bus_send(2, "Master")

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS   # на паузе музыка не обрывается
	add_child(_music)
	for i in 8:
		var pl := AudioStreamPlayer.new()
		pl.bus = "SFX"
		add_child(pl)
		_sfx_players.append(pl)
	_apply_volumes()


func _apply_volumes() -> void:
	_apply_bus("Master", float(volumes.get("master", 0.8)))
	_apply_bus("SFX", float(volumes.get("sfx", 0.8)))
	_apply_bus("Music", float(volumes.get("music", 0.55)))


func _apply_bus(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func volume_of(bus: String) -> float:
	return float(volumes.get(bus, 0.8))


func set_volume(bus: String, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	_apply_volumes()


## Короткие звуки: пул проигрывателей, чтобы они не обрывали друг друга.
func play_sfx(sfx_name: String) -> void:
	if not SFX.has(sfx_name) or _sfx_players.is_empty():
		return
	var stream = load(String(SFX[sfx_name]))
	if stream == null:
		return
	var pl = _sfx_players[_sfx_next % _sfx_players.size()]
	_sfx_next += 1
	pl.stream = stream
	pl.play()


## Музыка играет только в офисе — в главном меню тишина.
func start_music() -> void:
	if _music == null:
		return
	var stream = load(MUSIC_PATH)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	if _music:
		_music.stop()


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
	Game.apply_progress(save_money, save_difficulty)
	toast("Комната создана. Твой адрес: %s   порт %d" % [", ".join(local_ips()), PORT], 8.0)
	Game.server_start_contract()


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
	Game.apply_progress(save_money, save_difficulty)
	Game.server_start_contract()


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
	set_mouse_captured(true)
	start_music()
	toast("WASD — ходить, E — взаимодействие, Q — бросить.   Esc — пауза", 7.0)
	if terminal:
		terminal.close()


func leave_to_menu() -> void:
	_leave_game()


func _leave_game() -> void:
	in_game = false
	get_tree().paused = false
	stop_music()
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
	set_mouse_captured(false)


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_info"):
		dump_state()
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.physical_keycode == KEY_F10 and in_game:
			leave_to_menu()
	if event.is_action_pressed("free_mouse") and in_game and pause_menu != null:
		if settings_panel != null and settings_panel.active:
			settings_panel.close_panel()
			return
		if active_panel() != null:
			return
		if results != null and results.active:
			return
		pause_menu.toggle()


## Печатает состояние в панель Output. Нужно, чтобы диагностировать
## проблемы, которые видно только на конкретной машине.
func dump_state() -> void:
	print("=========== SHIP IT ", VERSION, " ===========")
	print("viewport      : ", get_tree().root.get_visible_rect().size)
	if _hud:
		print("HUD           : ", _hud, " visible=", _hud.visible, " layer=", _hud.layer)
	else:
		print("HUD           : нет")
	if _prompt:
		print("prompt        : rect=", _prompt.get_global_rect(), " text='", _prompt.text, "'")
	if _hint:
		print("hint          : rect=", _hint.get_global_rect(), " text='", _hint.text, "'")
	if terminal:
		print("terminal      : active=", terminal.active, " station=", terminal.station_idx,
			" tokens=", terminal.tokens, " done=", terminal.done)
	if rhythm:
		print("rhythm        : active=", rhythm.active, " station=", rhythm.station_idx,
			" notes=", rhythm.tokens, " done=", rhythm.done)
	if paint:
		print("paint         : active=", paint.active, " station=", paint.station_idx,
			" cells=", paint.tokens, " done=", paint.done, " brush=", paint.brush)
	print("in_game       : ", in_game, "  игроков: ", players.size(), "  ready_peers: ", ready_peers)
	var lp = local_player()
	if lp:
		print("player        : pos=", lp.global_position, " focus=", lp._focus)
	print("held item     : ", Game.held_item_of(local_id()))
	print("предметов     : ", Game.items.size(), "  работа на столах: ", Game.work)
	print("контракт      : ", Game.contract, " идёт=", Game.contract_running, " время=", Game.contract_time)
	print("сдано         : ", Game.delivered_by, "  деньги: ", Game.money)
	print("=========================================")
	toast("Диагностика напечатана в панель Output", 3.0)


## Какая мини-игра стоит на столе этой дисциплины.
func panel_for(disc: String):
	if disc == "music":
		return rhythm
	if disc == "art":
		return paint
	return terminal


## Открытая сейчас мини-игра, если она есть.
func active_panel():
	if terminal != null and terminal.active:
		return terminal
	if rhythm != null and rhythm.active:
		return rhythm
	if paint != null and paint.active:
		return paint
	return null


## Закрыть панели: idx < 0 — все, иначе только привязанные к этому столу.
func close_panels(idx: int) -> void:
	for panel in [terminal, rhythm, paint]:
		if panel == null:
			continue
		if idx < 0 or panel.station_idx == idx:
			panel.close()


## Единая точка управления курсором: панели и меню дёргают только её.
func set_mouse_captured(v: bool) -> void:
	mouse_wanted = v
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Локальные IPv4 — их диктуют напарнику при игре по сети.
func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"binds": binds, "volumes": volumes}))
	f.close()


func load_settings() -> void:
	binds = DEFAULT_BINDS.duplicate()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for k in DEFAULT_BINDS.keys():
		var src: Dictionary = data.get("binds", {})
		if src.has(k):
			binds[k] = int(src[k])
	var vol: Dictionary = data.get("volumes", {})
	for k in ["master", "sfx", "music"]:
		if vol.has(k):
			volumes[k] = clampf(float(vol[k]), 0.0, 1.0)


## Прогресс студии: деньги и номер контракта. Сохраняется после каждой сдачи.
func save_progress(money: int, difficulty: int) -> void:
	save_money = money
	save_difficulty = difficulty
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"money": money, "difficulty": difficulty}))
	f.close()
	_refresh_save_label()


func load_progress() -> void:
	save_money = 0
	save_difficulty = 0
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		save_money = int(data.get("money", 0))
		save_difficulty = int(data.get("difficulty", 0))


func has_save() -> bool:
	return save_difficulty > 0 or save_money > 0


func reset_progress() -> void:
	save_money = 0
	save_difficulty = 0
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"money": 0, "difficulty": 0}))
		f.close()
	_refresh_save_label()


func _refresh_save_label() -> void:
	if _save_label == null:
		return
	if has_save():
		_save_label.text = "Сохранение: контракт №%d, на счету $%d" % [save_difficulty + 1, save_money]
	else:
		_save_label.text = "Сохранения нет — начнём с нуля"


func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var addr := String(a)
		if addr.count(".") == 3 and not addr.begins_with("127.") and not addr.begins_with("169.254."):
			out.append(addr)
	if out.is_empty():
		out.append("не найдены")
	return out


func is_host() -> bool:
	return (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()


func update_contract_hud() -> void:
	if _contract_label == null:
		return
	if Game.contract.is_empty():
		_contract_label.text = ""
		return
	var lines: PackedStringArray = []
	lines.append("Контракт №%d  ·  %s" % [int(Game.contract.get("index", 1)), String(Game.contract["title"])])
	if Game.contract_running:
		var left := maxf(Game.deadline_seconds() - Game.contract_time, 0.0)
		var mins := floori(left / 60.0)
		var secs := int(left) % 60
		lines.append("Неделя %d из %d   ·   осталось %d:%02d" % [
			Game.current_week(), int(Game.contract["weeks"]), mins, secs])
	else:
		lines.append("контракт закрыт")
	lines.append("Код %d/%d   Графика %d/%d   Музыка %d/%d" % [
		int(Game.delivered_by["code"]), Game.need_of("code"),
		int(Game.delivered_by["art"]), Game.need_of("art"),
		int(Game.delivered_by["music"]), Game.need_of("music")])
	if Game.testing:
		lines.append("ТЕСТИРОВАНИЕ · багов осталось %d из %d · %d с" % [
			Game.bugs_left(), Game.bugs_total, int(Game.testing_left)])
	elif Game.contract_running and Game.requirements_met():
		lines.append("Контент готов — неси его на тестирование")
	lines.append("Счёт студии: $%d" % Game.money)
	_contract_label.text = "\n".join(lines)


func local_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1


func local_player() -> Node3D:
	var id := local_id()
	if players.has(id):
		return players[id]
	return null
