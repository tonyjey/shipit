extends Control
## Экран сдачи игры издателю. Координаты считаем вручную — якоря на скрытых
## узлах не пересчитываются, на этом уже обожглись.

const PANEL_W := 720.0
const PANEL_H := 420.0

var active := false

var _panel: PanelContainer
var _title: Label
var _score: Label
var _verdict: Label
var _body: Label
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
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	style.border_color = Color(0.95, 0.80, 0.35, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	_title = _mk(22, Color(0.85, 0.88, 0.95))
	box.add_child(_title)

	_score = _mk(72, Color(0.97, 0.85, 0.45))
	box.add_child(_score)

	_verdict = _mk(26, Color(0.90, 0.92, 0.98))
	box.add_child(_verdict)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)

	_body = _mk(18, Color(0.72, 0.76, 0.85))
	box.add_child(_body)

	_hint = _mk(16, Color(0.60, 0.64, 0.72))
	box.add_child(_hint)


func _mk(font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


func show_result(title: String, score: int, completeness: float, quality: float, pay: int, money: int, early: bool, bug_left := 0, bug_total := 0) -> void:
	active = true
	visible = true
	_layout()
	_title.text = title
	_score.text = "%d / 100" % score
	_verdict.text = verdict_for(score)

	var lines: PackedStringArray = []
	lines.append("Готовность контента: %d%%" % int(round(completeness * 100.0)))
	lines.append("Качество исполнения: %d%%" % int(round(quality * 100.0)))
	if bug_total <= 0:
		lines.append("Багов не найдено — тестирование не потребовалось")
	elif bug_left == 0:
		lines.append("Все %d багов пойманы" % bug_total)
	else:
		lines.append("Багов осталось в игре: %d из %d" % [bug_left, bug_total])
	if early:
		lines.append("Сдано досрочно — бонус к оценке")
	else:
		lines.append("Сдано в последний день")
	lines.append("")
	lines.append("Гонорар: $%d     На счету: $%d" % [pay, money])
	_body.text = "\n".join(lines)

	_hint.text = "[Enter] — закрыть.   Новый контракт берут на доске у дальней стены"


func close() -> void:
	active = false
	visible = false


static func verdict_for(score: int) -> String:
	if score >= 90:
		return "Игра года. Издатель в шоке."
	if score >= 75:
		return "Крепкий хит. Продолжение уже обсуждают."
	if score >= 60:
		return "Неплохо. Но пресса ждала большего."
	if score >= 40:
		return "Смешанные отзывы. «Сыровато»."
	return "Провал. «Как это вообще выпустили?»"


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		close()
