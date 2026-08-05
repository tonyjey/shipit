extends Control
## Мини-игра «работа за столом»: набор коротких токенов.
##
## Важно: сравниваем physical_keycode, а не символ. Поэтому русская раскладка
## работает так же, как английская — нажатие физической клавиши "A" всегда даёт "A".

var active := false
var station_idx := -1
var tokens: Array = []
var done := 0
var typed := 0
var mistakes_batch := 0

const PANEL_W := 760.0
const PANEL_H := 300.0

var _panel: PanelContainer
var _title: Label
var _log: Label
var _current: RichTextLabel
var _hint: Label
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


## Считаем координаты сами. Якоря на невидимом Control не пересчитываются,
## из-за чего панель уезжала за пределы экрана.
func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 100.0 or vp.y < 100.0:
		vp = Vector2(1600.0, 900.0)
	position = Vector2.ZERO
	size = vp
	if _panel:
		_panel.size = Vector2(PANEL_W, PANEL_H)
		_panel.position = Vector2((vp.x - PANEL_W) * 0.5, vp.y - PANEL_H - 40.0)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.92)
	style.border_color = Color(0.35, 0.60, 0.95, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)

	_log = Label.new()
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log.add_theme_font_size_override("font_size", 16)
	_log.add_theme_color_override("font_color", Color(0.55, 0.85, 0.60))
	_log.custom_minimum_size = Vector2(0, 96)
	box.add_child(_log)

	_current = RichTextLabel.new()
	_current.bbcode_enabled = true
	_current.fit_content = true
	_current.scroll_active = false
	_current.autowrap_mode = TextServer.AUTOWRAP_OFF
	_current.custom_minimum_size = Vector2(0, 62)
	_current.add_theme_font_size_override("normal_font_size", 44)
	box.add_child(_current)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	_hint.text = "Печатай буквы и цифры.   Esc — отойти, прогресс сохранится."
	box.add_child(_hint)


# ---------------------------------------------------------------- УПРАВЛЕНИЕ

func open(idx: int, disc: String, toks: Array, done_count: int) -> void:
	station_idx = idx
	tokens = toks.duplicate()
	done = done_count
	typed = 0
	mistakes_batch = 0
	active = true
	visible = true
	_layout()
	_title.text = "ТЕРМИНАЛ — %s" % _disc_title(disc)
	_redraw()


func close() -> void:
	active = false
	visible = false
	station_idx = -1
	typed = 0


func sync_progress(done_count: int) -> void:
	if done_count > done:
		done = done_count
		typed = 0
		mistakes_batch = 0
		_redraw()


func _disc_title(disc: String) -> String:
	match disc:
		"code": return "КОД"
		"art": return "ГРАФИКА"
		"music": return "МУЗЫКА"
	return disc.to_upper()


# ---------------------------------------------------------------- ВВОД

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()   # камера не крутится, пока печатаешь
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()

	if key.physical_keycode == KEY_ESCAPE:
		Game.request_leave_station(station_idx)
		return

	var ch := OS.get_keycode_string(key.physical_keycode)
	if ch.length() != 1:
		return
	_type_char(ch)


func _type_char(ch: String) -> void:
	if done >= tokens.size():
		return
	var tok: String = String(tokens[done])
	if typed >= tok.length():
		return

	if ch == tok.substr(typed, 1):
		typed += 1
		if typed >= tok.length():
			var reported := mistakes_batch
			done += 1              # оптимистично, чтобы не было задержки ввода
			typed = 0
			mistakes_batch = 0
			Game.request_token(station_idx, reported)
	else:
		mistakes_batch += 1
		typed = maxi(typed - 1, 0)
		_flash = 0.25
	_redraw()


func _process(delta: float) -> void:
	if active and size.x < 100.0:
		_layout()          # страховка, если размер окна пришёл позже
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_redraw()


func _redraw() -> void:
	if not active:
		return

	var lines: PackedStringArray = []
	for i in tokens.size():
		if i < done:
			lines.append("> %s ... ok" % String(tokens[i]))
	_log.text = "\n".join(lines)

	if done >= tokens.size():
		_current.text = "[center][color=#8fe08f]компиляция...[/color][/center]"
		return

	var tok: String = String(tokens[done])
	var head := tok.substr(0, typed)
	var tail := tok.substr(typed)
	var tail_color := "#e8e8ee"
	if _flash > 0.0:
		tail_color = "#ff8080"
	_current.text = "[center][color=#7fe07f]%s[/color][color=%s]%s[/color]   [color=#666a75]%d/%d[/color][/center]" % [
		head, tail_color, tail, done + 1, tokens.size()
	]
