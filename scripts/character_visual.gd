class_name CharacterVisual
extends Node3D

## Каркас код-анимации персонажа "Ship It!". Godot 4.7.
##
## Скелета нет — крутим отдельные объекты, у каждого origin в суставе.
## Вешается на узел, ВНУТРИ которого лежит импортированная модель
## (узел Character_ROOT и его дети). Обычно:
##
##   Player (CharacterBody3D)
##   └── Visual (Node3D)  <- сюда этот скрипт
##       └── character.glb (инстанс сцены)
##           └── Character_ROOT
##
## Оси (проверено на конверсии Blender Z-up -> glTF/Godot Y-up):
##   rotation.x > 0  — мах вперёд, в сторону -Z, куда смотрит персонаж
##   rotation.x < 0  — мах назад
##   rotation.y      — поворот вокруг вертикали
##   rotation.z      — наклон вбок
## Знак при экспорте не переворачивается: C * Rx(θ) * C⁻¹ = Rx(θ),
## потому что конверсия Z-up→Y-up сама есть поворот вокруг X.
##
## Сеть. Анимация — чистая функция от (скорость, пройденный путь).
## Фаза шага накапливается от расстояния, а не от локального времени,
## поэтому при синхронной позиции ноги совпадают у всех клиентов
## сами собой. По ENet ничего дополнительно слать не надо.

# --- размеры модели, должны совпадать с character_v2.py ---
const THIGH := 0.41
const SHIN := 0.41
const FOOT_H := 0.10
const HIP_HEIGHT := 0.92

## Узлы, которые красятся в цвет игрока. Галстук, глаза, воротник и
## ботинки не трогаем: галстук — форма студии, он одинаковый у всех,
## и именно поэтому игроки читаются одним пятном цвета.
const BODY_PARTS := [
	"Hips", "Torso",
	"Arm_L_Upper", "Arm_L_Lower", "Hand_L",
	"Arm_R_Upper", "Arm_R_Lower", "Hand_R",
	"Leg_L_Upper", "Leg_L_Lower",
	"Leg_R_Upper", "Leg_R_Lower",
]
const HEAD_PARTS := ["Head"]
## Насколько голова светлее тела — чтобы лицо не сливалось с торсом.
const HEAD_LIGHTEN := 0.14


const JOINTS := [
	"Character_ROOT", "Hips", "Torso", "Collar", "Tie",
	"Head", "Eye_L", "Eye_R", "Head_Top",
	"Arm_L_Upper", "Arm_L_Lower", "Hand_L", "Grip_L",
	"Arm_R_Upper", "Arm_R_Lower", "Hand_R", "Grip_R",
	"Leg_L_Upper", "Leg_L_Lower", "Foot_L",
	"Leg_R_Upper", "Leg_R_Lower", "Foot_R",
]

@export_group("Ходьба")
## Максимальный размах бедра. Главная ручка «размашистости».
## Длина шага считается из него, поэтому ступни не скользят по полу
## ни при каком значении: шаг = 2 * (бедро + голень) * sin(размах).
## 34 -> шаг 0.92 м, 26 -> 0.72 м, 20 -> 0.56 м.
@export var max_swing_deg := 26.0
## Скорость, при которой размах достигает максимума.
@export var reference_speed := 5.5
## Тонкая подстройка длины шага. 1.0 = ступни стоят на месте.
## Меньше 1.0 — ноги перебирают чаще, больше — подтормаживают.
@export var stride_scale := 1.0
@export var arm_swing_ratio := 0.62
@export var knee_bend_ratio := 0.90
@export var hip_sway_deg := 3.5

@export_group("Стойка")
@export var idle_breath_deg := 0.9
@export var idle_breath_hz := 0.25

@export_group("Прочее")
## Сглаживание разгона/торможения анимации.
@export var blend_speed := 12.0
## Опускать модель так, чтобы нижняя подошва касалась пола.
## Без этого при махе нога «укорачивается» и персонаж скользит по воздуху.
@export var ground_lock := true
## Сам мерить скорость по смещению узла. Выключи, если зовёшь tick() вручную.
@export var auto_track_velocity := true

var _j := {}
var _root: Node3D = null
var _bound := false
var _phase := 0.0
var _speed := 0.0
var _prev_pos := Vector3.ZERO
var _has_prev := false


func _ready() -> void:
	_bound = bind()
	_prev_pos = global_position


## Находит узлы модели. Возвращает false, если чего-то не хватает.
func bind() -> bool:
	_j.clear()
	var missing: PackedStringArray = []
	for n in JOINTS:
		var node: Node3D = null
		if String(name) == String(n):
			node = self
		else:
			node = find_child(String(n), true, false) as Node3D
		if node == null:
			missing.append(n)
		else:
			_j[n] = node
	_root = _j.get("Character_ROOT") as Node3D
	if not missing.is_empty():
		push_error("CharacterVisual: не найдены узлы: %s. "
			% ", ".join(missing)
			+ "Проверь, что GLB импортирован и лежит внутри этого узла.")
		return false
	return true


func _process(delta: float) -> void:
	if auto_track_velocity:
		tick(delta)


## Главный вход. speed_mps < 0 — измерить скорость самому.
func tick(delta: float, speed_mps := -1.0) -> void:
	if not _bound:
		return
	var target: float = speed_mps if speed_mps >= 0.0 else _measured_speed(delta)
	var k := clampf(delta * blend_speed, 0.0, 1.0)
	_speed = lerpf(_speed, target, k)

	if _speed > 0.05:
		_phase = fposmod(
			_phase + TAU * (_speed * delta) / maxf(_stride(), 0.01), TAU)
	else:
		# ноги сходятся в стойку, а не замирают враскоряку
		_phase = fposmod(lerp_angle(_phase, 0.0, k * 0.5), TAU)

	_apply()


func get_speed() -> float:
	return _speed


func get_grip(right := true) -> Node3D:
	return _j.get("Grip_R" if right else "Grip_L") as Node3D


# ------------------------------------------------------------
func _measured_speed(delta: float) -> float:
	var p := global_position
	if not _has_prev:
		_prev_pos = p
		_has_prev = true
		return 0.0
	var d := p - _prev_pos
	_prev_pos = p
	d.y = 0.0
	return d.length() / maxf(delta, 0.0001)


## Длина полного цикла в метрах, выведенная из размаха.
## Частота шагов = скорость / это. Пока формула соблюдается,
## ступня стоит на месте, пока касается пола, — нет «конькового» скольжения.
func _stride() -> float:
	return 2.0 * (THIGH + SHIN) * sin(deg_to_rad(max_swing_deg)) * stride_scale


func _set_x(joint: String, angle: float) -> void:
	var n := _j.get(joint) as Node3D
	if n:
		n.rotation.x = angle


func _apply() -> void:
	var walk_blend := clampf(_speed / 0.4, 0.0, 1.0)
	var amp := deg_to_rad(max_swing_deg) \
		* clampf(_speed / maxf(reference_speed, 0.01), 0.0, 1.0)
	var s := sin(_phase) * amp

	var hip_l := s
	var hip_r := -s
	# колено подгибается только у ноги в фазе переноса (идёт назад)
	var knee_l := maxf(0.0, -s) * knee_bend_ratio
	var knee_r := maxf(0.0, s) * knee_bend_ratio

	_set_x("Leg_L_Upper", hip_l)
	_set_x("Leg_R_Upper", hip_r)
	_set_x("Leg_L_Lower", knee_l)
	_set_x("Leg_R_Lower", knee_r)

	# руки в противофазе к ногам
	_set_x("Arm_L_Upper", -s * arm_swing_ratio)
	_set_x("Arm_R_Upper", s * arm_swing_ratio)
	_set_x("Arm_L_Lower", absf(s) * 0.22)
	_set_x("Arm_R_Lower", absf(s) * 0.22)

	# корпус закручивается против таза
	var sway := sin(_phase) * deg_to_rad(hip_sway_deg) * walk_blend
	var hips := _j.get("Hips") as Node3D
	if hips:
		hips.rotation.y = sway
	var torso := _j.get("Torso") as Node3D
	if torso:
		torso.rotation.y = -sway * 0.6
		# дыхание в стойке, гаснет при движении
		var t := float(Time.get_ticks_msec()) * 0.001
		torso.rotation.x = sin(t * TAU * idle_breath_hz) \
			* deg_to_rad(idle_breath_deg) * (1.0 - walk_blend)

	if ground_lock and _root:
		_root.position.y = -(HIP_HEIGHT - maxf(
			_leg_reach(hip_l, knee_l), _leg_reach(hip_r, knee_r)))


## Насколько низко достаёт подошва ниже таза при данных углах.
## В rest = 0.41 + 0.41 + 0.10 = 0.92 = высоте таза.
func _leg_reach(hip: float, knee: float) -> float:
	return THIGH * cos(hip) + (SHIN + FOOT_H) * cos(hip + knee)


## Перекрасить персонажа в цвет игрока.
func apply_color(body: Color) -> void:
	for n in BODY_PARTS:
		_tint(n, body)
	for n in HEAD_PARTS:
		_tint(n, body.lightened(HEAD_LIGHTEN))


## Материал дублируется на инстанс, иначе перекраска одного игрока
## перекрасила бы всех — ресурс в Godot общий.
func _tint(joint: String, c: Color) -> void:
	var node := _j.get(joint) as MeshInstance3D
	if node == null:
		return
	for i in range(node.get_surface_override_material_count()):
		var src := node.get_active_material(i)
		var mat: StandardMaterial3D = null
		if src is StandardMaterial3D:
			mat = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()
			mat.roughness = 0.68
		mat.albedo_color = c
		node.set_surface_override_material(i, mat)


## Сбросить все суставы в rest.
func reset_pose() -> void:
	for n in _j.keys():
		(_j[n] as Node3D).rotation = Vector3.ZERO
	if _root:
		_root.position.y = 0.0
	_phase = 0.0
	_speed = 0.0


## Отчёт в консоль: что нашлось, где стоит, какие габариты.
func report() -> void:
	print("--- CharacterVisual ---")
	print("узлов найдено: %d / %d" % [_j.size(), JOINTS.size()])
	for n in JOINTS:
		if _j.has(n):
			var p := (_j[n] as Node3D).position
			print("  %-16s локально (%7.3f %7.3f %7.3f)" % [n, p.x, p.y, p.z])
	var aabb := _world_aabb()
	print("габариты: рост %.3f  ширина %.3f  глубина %.3f"
		% [aabb.size.y, aabb.size.x, aabb.size.z])
	print("низ %.3f  верх %.3f" % [aabb.position.y, aabb.end.y])


func _world_aabb() -> AABB:
	var out := AABB()
	var first := true
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var box := m.global_transform * m.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
