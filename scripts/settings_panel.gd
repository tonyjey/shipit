extends Control
## Настройки: громкость и управление. Координаты считаем вручную —
## якоря на скрытых узлах не пересчитываются.

const PANEL_W := 640.0
const PANEL_H := 560.0

const ACTIONS := [
	["move_forward", "Вперёд"],
	["move_back", "Назад"],
	["move_left", "Влево"],
	["move_right", "Вправо"],
	["jump", "Прыжок"],
	["interact", "Взаимодействие"],
	["drop", "Бросить"],
]

var active := false

var _panel: PanelContainer
var _rows: Dictionary = {}          # action -> Button
var _waiting_for := ""
var _hint: Label


func _ready() -> void:
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
	style.bg_color = Color(0.07, 0.08, 0.11, 0.98)
	style.border_color = Color(0.45, 0.60, 0.85, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "НАСТРОЙКИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	box.add_child(_section("Звук"))
	box.add_child(_slider_row("Общая громкость", "master"))
	box.add_child(_slider_row("Эффекты", "sfx"))

	box.add_child(_section("Управление"))
	for a in ACTIONS:
		box.add_child(_bind_row(String(a[0]), String(a[1])))

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.60, 0.64, 0.72))
	_hint.text = "Нажми на клавишу справа, затем новую клавишу на клавиатуре"
	box.add_child(_hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var reset := Button.new()
	reset.text = "Сбросить управление"
	reset.pressed.connect(_reset_binds)
	buttons.add_child(reset)

	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(close_panel)
	buttons.add_child(close)


func _section(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	return l


func _slider_row(label: String, bus: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(220, 0)
	row.add_child(l)

	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = Boot.volume_of(bus)
	sl.custom_minimum_size = Vector2(280, 0)
	sl.value_changed.connect(func(v): Boot.set_volume(bus, v))
	row.add_child(sl)
	return row


func _bind_row(action: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(220, 0)
	row.add_child(l)

	var b := Button.new()
	b.custom_minimum_size = Vector2(140, 0)
	b.text = Boot.key_name_of(action)
	b.pressed.connect(func(): _start_wait(action))
	row.add_child(b)
	_rows[action] = b
	return row


func _start_wait(action: String) -> void:
	_waiting_for = action
	_rows[action].text = "жду клавишу..."
	_hint.text = "Нажми новую клавишу.   Esc — отмена"


func _reset_binds() -> void:
	Boot.reset_binds()
	_refresh()


func _refresh() -> void:
	for action in _rows.keys():
		_rows[action].text = Boot.key_name_of(String(action))
	_hint.text = "Нажми на клавишу справа, затем новую клавишу на клавиатуре"


func open_panel() -> void:
	active = true
	visible = true
	_waiting_for = ""
	_layout()
	_refresh()


func close_panel() -> void:
	active = false
	visible = false
	_waiting_for = ""
	Boot.save_settings()


func _input(event: InputEvent) -> void:
	if not active or _waiting_for == "":
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.physical_keycode != KEY_ESCAPE:
		Boot.rebind(_waiting_for, key.physical_keycode)
	_waiting_for = ""
	_refresh()
