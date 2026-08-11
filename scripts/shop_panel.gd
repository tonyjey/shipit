extends Control
## Магазин личных навыков. Покупки постоянные и принадлежат игроку,
## а не сохранёнке студии: прокачка едет с тобой в любую партию.

const PANEL_W := 720.0
const PANEL_H := 520.0

var active := false

var _panel: PanelContainer
var _wallet: Label
var _rows: Dictionary = {}     # id -> {"button": Button, "note": Label}


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
	style.border_color = Color(0.55, 0.95, 0.70, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "МАГАЗИН НАВЫКОВ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	_wallet = Label.new()
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wallet.add_theme_font_size_override("font_size", 17)
	_wallet.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	box.add_child(_wallet)

	box.add_child(HSeparator.new())

	for skill in Boot.SKILLS:
		box.add_child(_row(skill))

	box.add_child(HSeparator.new())

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(PANEL_W - 60.0, 0)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.58, 0.62, 0.70))
	hint.text = "Навыки покупаются навсегда и остаются при тебе в любой партии. Фонд студии на них не тратится."
	box.add_child(hint)

	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(close_shop)
	box.add_child(close)


func _row(skill: Dictionary) -> Control:
	var id := String(skill["id"])

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)

	var name_label := Label.new()
	name_label.text = String(skill["name"])
	name_label.custom_minimum_size = Vector2(300, 0)
	name_label.add_theme_font_size_override("font_size", 18)
	line.add_child(name_label)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(190, 0)
	buy.pressed.connect(func(): _buy(id))
	line.add_child(buy)

	var note := Label.new()
	note.text = String(skill["desc"])
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(PANEL_W - 60.0, 0)
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	row.add_child(note)

	_rows[id] = {"button": buy, "note": note}
	return row


func _refresh() -> void:
	_wallet.text = "Твой кошелёк: $%d        Фонд студии: $%d" % [Boot.wallet, Game.money]
	for skill in Boot.SKILLS:
		var id := String(skill["id"])
		var b: Button = _rows[id]["button"]
		if Boot.has_skill(id):
			b.text = "куплено"
			b.disabled = true
		elif Boot.wallet < int(skill["price"]):
			b.text = "$%d — не хватает" % int(skill["price"])
			b.disabled = true
		else:
			b.text = "Купить за $%d" % int(skill["price"])
			b.disabled = false


func _buy(id: String) -> void:
	if Boot.buy_skill(id):
		Boot.play_sfx("deliver")
	else:
		Boot.play_sfx("error")
	_refresh()


func open_shop() -> void:
	active = true
	visible = true
	_layout()
	_refresh()
	Boot.set_mouse_captured(false)


func close_shop() -> void:
	if active and Boot.in_game:
		Boot.set_mouse_captured(true)
	active = false
	visible = false


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_shop()
