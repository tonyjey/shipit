extends Control
## Меню паузы. В соло реально останавливает мир, в сетевой игре — только
## оверлей: остановить чужую игру мы не вправе, там время идёт дальше.

const PANEL_W := 380.0
const PANEL_H := 330.0

var active := false

var _panel: PanelContainer
var _note: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 100.0 or vp.y < 100.0:
		vp = Vector2(1600.0, 900.0)
	position = Vector2.ZERO
	size = vp
	if _panel:
		_panel.size = Vector2(PANEL_W, PANEL_H)
		_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - PANEL_H) * 0.5)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	style.border_color = Color(0.75, 0.78, 0.88, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(320, 0)
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	box.add_child(_note)

	box.add_child(HSeparator.new())

	_add_button(box, "Продолжить", func(): close_menu())
	_add_button(box, "Настройки", func():
		if Boot.settings_panel:
			Boot.settings_panel.open_panel())
	_add_button(box, "Выйти в главное меню", func():
		close_menu()
		Boot.leave_to_menu())
	_add_button(box, "Выход из игры", func(): get_tree().quit())


func _add_button(box: VBoxContainer, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Boot.play_sfx("click")
		action.call())
	box.add_child(b)


func open_menu() -> void:
	active = true
	visible = true
	_layout()
	if multiplayer.has_multiplayer_peer():
		_note.text = "Игра сетевая — мир продолжает жить, пока ты здесь. Дедлайн идёт."
	else:
		_note.text = "Мир остановлен. Дедлайн не идёт."
		get_tree().paused = true
	Boot.set_mouse_captured(false)


func close_menu() -> void:
	active = false
	visible = false
	get_tree().paused = false
	if Boot.in_game:
		Boot.set_mouse_captured(true)


func toggle() -> void:
	if active:
		close_menu()
	else:
		open_menu()
