extends Control
## Фаза «как назовём игру»: сначала каждый предлагает название,
## потом команда голосует. В соло голосование пропускается —
## голосовать самому с собой бессмысленно.

const PANEL_W := 640.0
const PANEL_H := 400.0
const MAX_LEN := 26

var active := false
var mode := ""            # "naming" | "voting"
var submitted := false
var options: Array = []

var _panel: PanelContainer
var _title: Label
var _sub: Label
var _edit: LineEdit
var _send: Button
var _status: Label
var _timer_label: Label
var _list: VBoxContainer
var _left := 0.0


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
	style.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	style.border_color = Color(0.55, 0.80, 1.00, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	_title = _mk(26, Color(0.90, 0.93, 0.98))
	box.add_child(_title)

	_sub = _mk(15, Color(0.62, 0.66, 0.74))
	box.add_child(_sub)

	_timer_label = _mk(15, Color(0.95, 0.80, 0.45))
	box.add_child(_timer_label)

	_edit = LineEdit.new()
	_edit.max_length = MAX_LEN
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.placeholder_text = "название игры"
	_edit.add_theme_font_size_override("font_size", 22)
	_edit.text_submitted.connect(func(_t): _submit())
	box.add_child(_edit)

	_send = Button.new()
	_send.text = "Предложить"
	_send.pressed.connect(_submit)
	box.add_child(_send)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)

	_status = _mk(15, Color(0.60, 0.85, 0.65))
	box.add_child(_status)


func _mk(font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 60.0, 0)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


# ---------------------------------------------------------------- РЕЖИМЫ

func open_naming(seconds: float, contract_title: String) -> void:
	mode = "naming"
	active = true
	visible = true
	submitted = false
	_left = seconds
	_layout()
	_title.text = "КАК НАЗОВЁМ ИГРУ?"
	_sub.text = "Заказ был: %s\nОценку прессы узнаем после релиза." % contract_title
	_edit.text = ""
	_edit.editable = true
	_edit.visible = true
	_send.visible = true
	_send.disabled = false
	_status.text = ""
	_clear_list()
	Boot.set_mouse_captured(false)
	_edit.grab_focus()


func open_voting(names: Array, seconds: float) -> void:
	mode = "voting"
	active = true
	visible = true
	submitted = false
	options = names.duplicate()
	_left = seconds
	_layout()
	_title.text = "ГОЛОСОВАНИЕ"
	_sub.text = "Выбери название. Можно голосовать и за своё."
	_edit.visible = false
	_send.visible = false
	_status.text = ""
	_clear_list()
	for i in options.size():
		var b := Button.new()
		b.text = String(options[i])
		var idx := i
		b.pressed.connect(func(): _vote(idx))
		if int(Game.name_owner(idx)) == Boot.local_id():
			b.text += "   (твоё)"
		_list.add_child(b)
	Boot.set_mouse_captured(false)


func close() -> void:
	if active and Boot.in_game:
		Boot.set_mouse_captured(true)
	active = false
	visible = false
	mode = ""
	_clear_list()


func _clear_list() -> void:
	for c in _list.get_children():
		c.queue_free()


func set_progress(done_count: int, total_count: int) -> void:
	if not active:
		return
	if submitted:
		_status.text = "Принято. Ждём остальных: %d из %d" % [done_count, total_count]


func _submit() -> void:
	if submitted or mode != "naming":
		return
	var text := _edit.text.strip_edges()
	if text.is_empty():
		_status.text = "Впиши хоть что-нибудь"
		return
	submitted = true
	_edit.editable = false
	_send.disabled = true
	_status.text = "Принято. Ждём остальных..."
	Boot.play_sfx("click")
	Game.request_name(text)


func _vote(idx: int) -> void:
	if submitted or mode != "voting":
		return
	submitted = true
	for c in _list.get_children():
		(c as Button).disabled = true
	_status.text = "Голос принят. Ждём остальных..."
	Boot.play_sfx("click")
	Game.request_vote(idx)


func _process(delta: float) -> void:
	if not active:
		return
	if size.x < 100.0:
		_layout()
	_left = maxf(_left - delta, 0.0)
	_timer_label.text = "осталось %d с" % int(ceil(_left))


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()   # выйти отсюда нельзя, это часть релиза
