extends Control
## Мини-игра для стола «Графика»: раскраска спрайта.
##
## Третья мини-игра сознательно сделана на мыши, а не на клавиатуре:
## терминал — последовательность, ритм — тайминг, раскраска — скорость.
##
## Порядок клеток свободный: бери кисть и крась всё, что ей подходит,
## в любом порядке. Сервер помнит закрытые клетки, поэтому работу
## можно бросить и подхватить с того же места.

const PANEL_W := 560.0
const PANEL_H := 500.0
const GRID_W := 4
const CELL := 74.0

const PALETTE := [
	Color(0.95, 0.40, 0.40),
	Color(0.98, 0.80, 0.45),
	Color(0.45, 0.65, 0.95),
	Color(0.50, 0.85, 0.55),
]
const PAL_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]

var active := false
var station_idx := -1
var tokens: Array = []
var done := 0
var mistakes_batch := 0
var brush := 0
var filled: Dictionary = {}

var _origin := Vector2.ZERO
var _grid_origin := Vector2.ZERO
var _pal_origin := Vector2.ZERO
var _miss_flash := 0.0
var _bad_cell := -1
var _bad_time := 0.0
var _pulse := 0.0
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 100.0 or vp.y < 100.0:
		vp = Vector2(1600.0, 900.0)
	position = Vector2.ZERO
	size = vp
	_origin = Vector2((vp.x - PANEL_W) * 0.5, vp.y - PANEL_H - 40.0)
	var grid_px := CELL * float(GRID_W)
	_grid_origin = _origin + Vector2((PANEL_W - grid_px) * 0.5, 82.0)
	_pal_origin = _origin + Vector2((PANEL_W - float(PALETTE.size()) * 76.0) * 0.5, PANEL_H - 96.0)


# ---------------------------------------------------------------- УПРАВЛЕНИЕ

func open(idx: int, _disc: String, toks: Array, _done_count: int) -> void:
	station_idx = idx
	tokens = toks.duplicate()
	filled.clear()
	for i in Game.filled_of(idx):
		filled[int(i)] = true
	done = filled.size()
	mistakes_batch = 0
	brush = _first_unfilled_color()
	active = true
	visible = true
	_layout()
	Boot.set_mouse_captured(false)
	queue_redraw()


func close() -> void:
	if active and Boot.in_game:
		Boot.set_mouse_captured(true)
	active = false
	visible = false
	station_idx = -1


func sync_progress(_done_count: int) -> void:
	for i in Game.filled_of(station_idx):
		filled[int(i)] = true
	done = filled.size()
	queue_redraw()


func _first_unfilled_color() -> int:
	for i in tokens.size():
		if not filled.has(i):
			return target_color(i)
	return 0


func remaining_of_color(c: int) -> int:
	var n := 0
	for i in tokens.size():
		if not filled.has(i) and target_color(i) == c:
			n += 1
	return n


func cell_of(i: int) -> int:
	if i < 0 or i >= tokens.size():
		return 0
	return int(String(tokens[i]).split(":")[0])


func target_color(i: int) -> int:
	if i < 0 or i >= tokens.size():
		return 0
	return clampi(int(String(tokens[i]).split(":")[1]), 0, PALETTE.size() - 1)


func cell_rect(cell: int) -> Rect2:
	var col := cell % GRID_W
	var row := floori(float(cell) / float(GRID_W))
	return Rect2(_grid_origin + Vector2(float(col) * CELL, float(row) * CELL), Vector2(CELL - 4.0, CELL - 4.0))


# ---------------------------------------------------------------- ВВОД

func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		get_viewport().set_input_as_handled()
		if key.physical_keycode == KEY_ESCAPE:
			Game.request_leave_station(station_idx, mistakes_batch)
			return
		var slot := PAL_KEYS.find(key.physical_keycode)
		if slot >= 0:
			brush = slot
			queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		get_viewport().set_input_as_handled()
		_click(mb.position)


func _click(pos: Vector2) -> void:
	# сначала палитра
	for i in PALETTE.size():
		var r := Rect2(_pal_origin + Vector2(float(i) * 76.0, 0), Vector2(64, 64))
		if r.has_point(pos):
			brush = i
			queue_redraw()
			return

	if done >= tokens.size():
		return

	# порядок свободный: ищем любую незакрашенную клетку под курсором
	for i in tokens.size():
		if filled.has(i):
			continue
		if not cell_rect(cell_of(i)).has_point(pos):
			continue
		if brush == target_color(i):
			_advance(i)
		else:
			_miss(cell_of(i))
		return


func _miss(cell: int) -> void:
	mistakes_batch += 1
	_miss_flash = 0.45
	Boot.play_sfx("error")
	_bad_cell = cell
	_bad_time = 0.45
	queue_redraw()


func _advance(i: int) -> void:
	var reported := mistakes_batch
	filled[i] = true
	done = filled.size()
	mistakes_batch = 0
	Game.request_token(station_idx, reported, i)
	# кисть кончилась — сразу переключаемся на следующий нужный цвет
	if remaining_of_color(brush) == 0:
		brush = _first_unfilled_color()
	queue_redraw()


func _process(delta: float) -> void:
	if not active:
		return
	if size.x < 100.0:
		_layout()
	_pulse += delta * 4.0
	if _miss_flash > 0.0:
		_miss_flash -= delta
	if _bad_time > 0.0:
		_bad_time -= delta
		if _bad_time <= 0.0:
			_bad_cell = -1
	queue_redraw()


# ---------------------------------------------------------------- ОТРИСОВКА

## Ошибки и текущее качество показываем всегда, а не вспышкой на четверть секунды.
func _draw_stats() -> void:
	if _font == null:
		return
	var m := Game.mistakes_of(station_idx) + mistakes_batch
	var q := int(round(Game.quality_for(m) * 100.0))
	var col := Color(0.55, 0.85, 0.60)
	if m > 0:
		col = Color(1.0, 0.62, 0.45)
	draw_string(_font, _origin + Vector2(0, 60), "ошибок: %d   ·   качество ~%d%%" % [m, q],
		HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 20.0, 15, col)


func _draw() -> void:
	if not active:
		return

	var rect := Rect2(_origin, Vector2(PANEL_W, PANEL_H))
	draw_rect(rect, Color(0.07, 0.08, 0.11, 0.93), true)
	var border := Color(1.00, 0.52, 0.62, 0.9)
	if _miss_flash > 0.0:
		border = Color(1.0, 0.45, 0.45, 0.95)
	draw_rect(rect, border, false, 3.0)

	if _font:
		draw_string(_font, _origin + Vector2(0, 34), "ТЕРМИНАЛ — ГРАФИКА",
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 20, Color(0.85, 0.88, 0.95))
		draw_string(_font, _origin + Vector2(0, 60), "закрашено %d из %d" % [done, tokens.size()],
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 15, Color(0.60, 0.64, 0.72))

	# клетки спрайта
	var pulse := 0.45 + 0.35 * sin(_pulse)
	for i in tokens.size():
		var r := cell_rect(cell_of(i))
		var col: Color = PALETTE[target_color(i)]
		if filled.has(i):
			draw_rect(r, col, true)
		else:
			draw_rect(r, Color(0.16, 0.17, 0.21), true)
			draw_rect(r, Color(col.r, col.g, col.b, 0.35), false, 2.0)
			# точка-подсказка нужного цвета
			draw_circle(r.get_center(), 9.0, Color(col.r, col.g, col.b, 0.55))
			# клетки под текущую кисть подсвечены — крась их подряд
			if target_color(i) == brush:
				draw_rect(r.grow(2.0), Color(1, 1, 1, pulse), false, 3.0)

	# клетка, по которой промахнулись: красная заливка и крест
	if _bad_cell >= 0 and _bad_time > 0.0:
		var br := cell_rect(_bad_cell)
		var a := clampf(_bad_time / 0.45, 0.0, 1.0)
		draw_rect(br, Color(1.0, 0.30, 0.30, 0.45 * a), true)
		draw_rect(br, Color(1.0, 0.35, 0.35, a), false, 3.0)
		draw_line(br.position + Vector2(12, 12), br.end - Vector2(12, 12), Color(1, 1, 1, a), 3.0)
		draw_line(Vector2(br.end.x - 12, br.position.y + 12), Vector2(br.position.x + 12, br.end.y - 12), Color(1, 1, 1, a), 3.0)

	# палитра
	for i in PALETTE.size():
		var pr := Rect2(_pal_origin + Vector2(float(i) * 76.0, 0), Vector2(64, 64))
		draw_rect(pr, PALETTE[i], true)
		if i == brush:
			draw_rect(pr.grow(4.0), Color(1, 1, 1, 0.95), false, 3.0)
		if _font:
			draw_string(_font, pr.position + Vector2(0, 86), str(i + 1),
				HORIZONTAL_ALIGNMENT_CENTER, 64, 17, Color(0.75, 0.78, 0.85))

	_draw_stats()

	if _font:
		draw_string(_font, _origin + Vector2(0, PANEL_H - 14.0),
			"1-4 или клик — цвет   ·   крась подсвеченные клетки в любом порядке   ·   Esc — отойти",
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 14, Color(0.55, 0.59, 0.68))
