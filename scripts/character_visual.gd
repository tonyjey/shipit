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
## Шаг = 2*(бедро+голень)*sin(размах): 34° -> 0.92 м, 26° -> 0.72 м.
@export var max_swing_deg := 34.0
## Скорость, при которой размах достигает максимума.
@export var reference_speed := 5.5
## Тонкая подстройка длины шага. 1.0 = ступни стоят на месте.
## Меньше 1.0 — ноги перебирают чаще, больше — подтормаживают.
@export var stride_scale := 1.0
## Потолок частоты шагов, циклов в секунду. Прямая ручка «скорости ног».
## Выше него ноги перебирать не будут — вместо этого появится
## проскальзывание ступней. Это осознанный размен: у персонажа ноги 0.82 м,
## и на скорости 4+ м/с он физически обязан либо шагать шире человеческого,
## либо семенить. 3.0-3.6 — частота бега живого человека.
## 0 или меньше — снять потолок (ступни никогда не скользят).
@export var max_step_hz := 3.6
@export var arm_swing_ratio := 0.62
@export var knee_bend_ratio := 0.90
@export var hip_sway_deg := 3.5

@export_group("Перенос предмета")
## Одной рукой — для дискет и мелочи: свободная рука продолжает махать,
## походка остаётся живой. Двумя — под коробки и крупные предметы.
@export_enum("Одной рукой", "Двумя руками") var carry_style := 0
## 78° держало предмет на линии взгляда — от первого лица он закрывал
## пол-экрана. 66° опускает кисть под линию взгляда, в нижнюю треть кадра.
@export var carry_upper_deg := 66.0
@export var carry_lower_deg := 16.0
## Отвод несущей руки наружу, чтобы предмет ушёл из центра кадра вправо.
@export var carry_side_deg := 16.0
## Скорость перехода в позу переноски и обратно.
@export var carry_blend_speed := 8.0

@export_group("Прыжок")
## Поза в воздухе включается по вертикальной скорости — так она работает
## одинаково у своего игрока и у сетевых, без единого лишнего байта в RPC.
@export var airborne_speed_threshold := 1.0
## ВНИМАНИЕ ЗНАКАМ: у голени +X уводит её ВПЕРЁД от бедра, а колено
## гнётся назад. Поэтому поджатое колено — отрицательный угол.
## С плюсом персонаж выбрасывает ноги вперёд и выглядит сидящим на стуле.
@export var jump_hip_deg := 26.0
@export var jump_knee_deg := -62.0
@export var jump_arm_deg := -38.0
@export var fall_hip_deg := -6.0
@export var fall_knee_deg := -8.0
@export var fall_arm_deg := 24.0
@export var air_blend_speed := 9.0

@export_group("Стойка")
@export var idle_breath_deg := 0.9
@export var idle_breath_hz := 0.25

@export_group("Прочее")
## Сглаживание разгона/торможения анимации.
@export var blend_speed := 12.0
## Опускать модель так, чтобы нижняя подошва касалась пола.
## Без этого при махе нога «укорачивается» и персонаж скользит по воздуху.
@export var ground_lock := true
## Насколько полно применять прижим. 1.0 — ступни идеально на полу, но
## корпус гуляет на 7 см дважды за цикл, и предмет в руке заметно скачет.
## 0.7 — 5 см, ступни утапливаются максимум на 2 см. Незаметно.
@export_range(0.0, 1.0) var ground_lock_amount := 0.7
## Сам мерить скорость по смещению узла. Выключи, если зовёшь tick() вручную.
@export var auto_track_velocity := true

var _j := {}
var _root: Node3D = null
var _bound := false
var _phase := 0.0
var _speed := 0.0
var _prev_pos := Vector3.ZERO
var _has_prev := false
var _carrying := false
var _carry_blend := 0.0
var _vertical := 0.0
var _air_blend := 0.0
var _rising := true


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

	var want := 1.0 if _carrying else 0.0
	_carry_blend = lerpf(_carry_blend, want, clampf(delta * carry_blend_speed, 0.0, 1.0))

	var air_want := 1.0 if absf(_vertical) > airborne_speed_threshold else 0.0
	if absf(_vertical) > airborne_speed_threshold:
		_rising = _vertical > 0.0
	_air_blend = lerpf(_air_blend, air_want, clampf(delta * air_blend_speed, 0.0, 1.0))

	if _speed > 0.05:
		var hz := _speed / maxf(_stride(), 0.01)
		if max_step_hz > 0.0:
			hz = minf(hz, max_step_hz)
		_phase = fposmod(_phase + TAU * hz * delta, TAU)
	else:
		# ноги сходятся в стойку, а не замирают враскоряку
		_phase = fposmod(lerp_angle(_phase, 0.0, k * 0.5), TAU)

	_apply()


func get_speed() -> float:
	return _speed


func get_grip(right := true) -> Node3D:
	return _j.get("Grip_R" if right else "Grip_L") as Node3D


## Руки вперёд под предмет. Переход плавный, ноги продолжают шагать.
func set_carrying(on: bool) -> void:
	_carrying = on


## Фактическая частота шагов, циклов в секунду. Для отладки.
func step_hz() -> float:
	var hz := _speed / maxf(_stride(), 0.01)
	return minf(hz, max_step_hz) if max_step_hz > 0.0 else hz


# ------------------------------------------------------------
func _measured_speed(delta: float) -> float:
	var p := global_position
	if not _has_prev:
		_prev_pos = p
		_has_prev = true
		return 0.0
	var d := p - _prev_pos
	_prev_pos = p
	_vertical = d.y / maxf(delta, 0.0001)
	d.y = 0.0
	return d.length() / maxf(delta, 0.0001)


## Длина ПОЛНОГО ЦИКЛА в метрах (левая + правая), выведенная из размаха.
## Один шаг = 2 * L * sin(размах) — это разнос ступней при максимальном
## разведении. Цикл = два шага, отсюда четвёрка. Делить путь надо именно
## на цикл: с двойкой персонаж семенил ровно вдвое чаще нужного.
func _stride() -> float:
	return 4.0 * (THIGH + SHIN) * sin(deg_to_rad(max_swing_deg)) * stride_scale


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

	# руки: в противофазе к ногам, либо вытянуты вперёд под предмет
	var c_r := clampf(_carry_blend, 0.0, 1.0)
	var c_l := c_r if carry_style == 1 else 0.0
	var up := deg_to_rad(carry_upper_deg)
	var lo := deg_to_rad(carry_lower_deg)
	_set_x("Arm_L_Upper", lerpf(-s * arm_swing_ratio, up, c_l))
	_set_x("Arm_R_Upper", lerpf(s * arm_swing_ratio, up, c_r))
	_set_x("Arm_L_Lower", lerpf(absf(s) * 0.22, lo, c_l))
	_set_x("Arm_R_Lower", lerpf(absf(s) * 0.22, lo, c_r))
	# отвод в сторону: правая наружу (+Z), левая зеркально
	var side := deg_to_rad(carry_side_deg)
	var arm_r := _j.get("Arm_R_Upper") as Node3D
	if arm_r:
		arm_r.rotation.z = side * c_r
	var arm_l := _j.get("Arm_L_Upper") as Node3D
	if arm_l:
		arm_l.rotation.z = -side * c_l

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

	_apply_air()

	if ground_lock and _root:
		var reach := maxf(_leg_reach(hip_l, knee_l), _leg_reach(hip_r, knee_r))
		var drop := -(HIP_HEIGHT - reach) * ground_lock_amount
		# в прыжке прижимать ступни к полу не нужно
		_root.position.y = lerpf(drop, 0.0, clampf(_air_blend, 0.0, 1.0))


## Поза в воздухе поверх ходьбы: на взлёте ноги поджаты и руки идут назад,
## на падении ноги вытянуты вниз, руки чуть вперёд для баланса.
func _apply_air() -> void:
	var a := clampf(_air_blend, 0.0, 1.0)
	if a <= 0.001:
		return
	var hip := deg_to_rad(jump_hip_deg if _rising else fall_hip_deg)
	var knee := deg_to_rad(jump_knee_deg if _rising else fall_knee_deg)
	var arm := deg_to_rad(jump_arm_deg if _rising else fall_arm_deg)
	for n in ["Leg_L_Upper", "Leg_R_Upper"]:
		_blend_x(n, hip, a)
	for n in ["Leg_L_Lower", "Leg_R_Lower"]:
		_blend_x(n, knee, a)
	# несущая рука остаётся при предмете, свободная балансирует
	_blend_x("Arm_L_Upper", arm, a * (1.0 - _carry_blend if carry_style == 1 else 1.0))
	_blend_x("Arm_R_Upper", arm, a * (1.0 - _carry_blend))


func _blend_x(joint: String, angle: float, w: float) -> void:
	var n := _j.get(joint) as Node3D
	if n:
		n.rotation.x = lerpf(n.rotation.x, angle, clampf(w, 0.0, 1.0))


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
