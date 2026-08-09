extends StaticBody3D
## Дверь в холодную комнату. Петля слева, створка поворачивается на 95°.
## Состояние хранит сервер, чтобы у всех дверь стояла одинаково.

const OPEN_ANGLE := 95.0
const SPEED := 260.0      # градусов в секунду

var door_id := 0
var is_open := false

var _target := 0.0
var _current := 0.0


func _ready() -> void:
	add_to_group("interactable")


## dir = +1 створка уходит в +X, -1 — в -X. Считаем от того,
## с какой стороны стоит игрок: дверь распахивается прочь от него.
func set_open(v: bool, dir := 1) -> void:
	is_open = v
	if v:
		_target = OPEN_ANGLE * signf(float(dir))
	else:
		_target = 0.0


func _process(delta: float) -> void:
	if is_equal_approx(_current, _target):
		return
	_current = move_toward(_current, _target, SPEED * delta)
	rotation_degrees.y = _current


func can_focus(_p) -> bool:
	return true


func get_prompt(_p) -> String:
	return "[E] Закрыть дверь" if is_open else "[E] Открыть дверь"


func get_target() -> Array:
	return ["door", door_id]
