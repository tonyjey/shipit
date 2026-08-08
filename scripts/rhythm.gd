extends Control
## Ритм-игра для стола «Музыка».
##
## Архитектурно это та же «работа над задачей», что и терминал: каждая нота —
## один «токен» из общего списка work.tokens, только вместо слова в нём номер
## дорожки. Поэтому вся серверная логика (прогресс, пауза, качество) переиспользуется.

const PANEL_W := 560.0
const PANEL_H := 470.0
const LANES := 4
const NOTE_INTERVAL := 0.80    # секунд между нотами
const APPROACH := 1.7          # сколько нота летит до линии
const LEAD_IN := 2.2           # разгон: пауза перед первой нотой
const HIT_WINDOW := 0.24       # допуск попадания в обе стороны

const LANE_KEYS := [KEY_D, KEY_F, KEY_J, KEY_K]
const LANE_NAMES := ["D", "F", "J", "K"]
const LANE_COLORS := [
	Color(0.45, 0.75, 1.00),
	Color(0.55, 0.95, 0.70),
	Color(1.00, 0.75, 0.45),
	Color(0.95, 0.55, 0.85),
]

var active := false
var station_idx := -1
var tokens: Array = []
var done := 0
var mistakes_batch := 0

var _base := 0
var _t := 0.0
var _origin := Vector2.ZERO
var _lane_flash := [0.0, 0.0, 0.0, 0.0]
var _miss_flash := 0.0
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


# ---------------------------------------------------------------- УПРАВЛЕНИЕ

func open(idx: int, _disc: String, toks: Array, done_count: int) -> void:
	station_idx = idx
	tokens = toks.duplicate()
	done = done_count
	_base = done_count
	_t = 0.0
	mistakes_batch = 0
	active = true
	visible = true
	_layout()
	queue_redraw()


func close() -> void:
	active = false
	visible = false
	station_idx = -1


func sync_progress(done_count: int) -> void:
	if done_count > done:
		done = done_count
		mistakes_batch = 0


func hit_time(i: int) -> float:
	return LEAD_IN + APPROACH + float(i - _base) * NOTE_INTERVAL


## Сколько секунд осталось до старта. Больше нуля — идёт обратный отсчёт.
func countdown() -> float:
	return maxf(LEAD_IN - _t, 0.0)


func lane_of(i: int) -> int:
	if i < 0 or i >= tokens.size():
		return 0
	return clampi(int(String(tokens[i])), 0, LANES - 1)


# ---------------------------------------------------------------- ВВОД

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()

	if key.physical_keycode == KEY_ESCAPE:
		Game.request_leave_station(station_idx, mistakes_batch)
		return

	var lane := LANE_KEYS.find(key.physical_keycode)
	if lane < 0:
		return
	_press(lane)


func _press(lane: int) -> void:
	_lane_flash[lane] = 0.18
	if done >= tokens.size():
		return
	var dt := _t - hit_time(done)
	if absf(dt) <= HIT_WINDOW and lane == lane_of(done):
		_advance()
	else:
		mistakes_batch += 1
		_miss_flash = 0.35
		Boot.play_sfx("error")
	queue_redraw()


func _advance() -> void:
	var reported := mistakes_batch
	done += 1
	mistakes_batch = 0
	Game.request_token(station_idx, reported)


func _process(delta: float) -> void:
	if not active:
		return
	if size.x < 100.0:
		_layout()
	_t += delta
	for i in LANES:
		if _lane_flash[i] > 0.0:
			_lane_flash[i] -= delta
	if _miss_flash > 0.0:
		_miss_flash -= delta

	# нота, которую прозевали: считаем промах, но песня идёт дальше
	if done < tokens.size() and _t > hit_time(done) + HIT_WINDOW:
		mistakes_batch += 1
		_miss_flash = 0.35
		Boot.play_sfx("error")
		_advance()
	queue_redraw()


# ---------------------------------------------------------------- ОТРИСОВКА

func _draw() -> void:
	if not active:
		return

	var rect := Rect2(_origin, Vector2(PANEL_W, PANEL_H))
	draw_rect(rect, Color(0.07, 0.08, 0.11, 0.93), true)
	var border := Color(0.70, 0.52, 1.00, 0.9)
	if _miss_flash > 0.0:
		border = Color(1.0, 0.45, 0.45, 0.95)
	draw_rect(rect, border, false, 3.0)

	if _font:
		draw_string(_font, _origin + Vector2(0, 32), "ТЕРМИНАЛ — МУЗЫКА",
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 20, Color(0.85, 0.88, 0.95))
		draw_string(_font, _origin + Vector2(0, 58), "нота %d из %d" % [mini(done + 1, tokens.size()), tokens.size()],
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 15, Color(0.60, 0.64, 0.72))

	if _font:
		var m := Game.mistakes_of(station_idx) + mistakes_batch
		var q := int(round(Game.quality_for(m) * 100.0))
		var scol := Color(0.55, 0.85, 0.60)
		if m > 0:
			scol = Color(1.0, 0.62, 0.45)
		draw_string(_font, _origin + Vector2(0, 58), "ошибок: %d   ·   качество ~%d%%" % [m, q],
			HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 20.0, 15, scol)

	var pad := 60.0
	var lane_w := (PANEL_W - pad * 2.0) / float(LANES)
	var top := _origin.y + 80.0
	var line_y := _origin.y + PANEL_H - 74.0
	var pps := (line_y - top) / APPROACH

	# дорожки
	for i in LANES:
		var x := _origin.x + pad + float(i) * lane_w
		var col: Color = LANE_COLORS[i]
		draw_rect(Rect2(x + 3.0, top, lane_w - 6.0, line_y - top), Color(col.r, col.g, col.b, 0.07), true)
		var pad_col := Color(col.r, col.g, col.b, 0.35 + 0.55 * clampf(_lane_flash[i] / 0.18, 0.0, 1.0))
		draw_rect(Rect2(x + 3.0, line_y, lane_w - 6.0, 26.0), pad_col, true)
		if _font:
			draw_string(_font, Vector2(x, line_y + 50.0), String(LANE_NAMES[i]),
				HORIZONTAL_ALIGNMENT_CENTER, lane_w, 20, Color(0.80, 0.83, 0.90))

	# линия попадания
	draw_line(Vector2(_origin.x + pad, line_y), Vector2(_origin.x + PANEL_W - pad, line_y),
		Color(1, 1, 1, 0.55), 2.0)

	# обратный отсчёт перед первой нотой
	var cd := countdown()
	if cd > 0.0 and _font:
		var n := int(ceil(cd))
		draw_string(_font, Vector2(_origin.x, top + (line_y - top) * 0.45), str(n),
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 64, Color(1.0, 1.0, 1.0, 0.85))
		draw_string(_font, Vector2(_origin.x, top + (line_y - top) * 0.45 + 34.0), "приготовься",
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 16, Color(0.70, 0.74, 0.82))

	# летящие ноты
	for i in range(done, mini(done + 4, tokens.size())):
		var t_hit := hit_time(i)
		var y := line_y - (t_hit - _t) * pps
		if y < top - 20.0 or y > line_y + 30.0:
			continue
		var lane := lane_of(i)
		var x := _origin.x + pad + float(lane) * lane_w
		var col: Color = LANE_COLORS[lane]
		if i == done and absf(_t - t_hit) <= HIT_WINDOW:
			col = Color(1, 1, 1)
		draw_rect(Rect2(x + 8.0, y - 11.0, lane_w - 16.0, 22.0), col, true)
