extends Node3D

## Отладочная сцена для проверки импорта персонажа. Godot 4.7.
##
## Как запустить
## -------------
## 1. Положи в проект character.glb и character_visual.gd.
## 2. Новая сцена -> корень Node3D -> прицепи этот скрипт.
## 3. В инспекторе задай Model Scene = character.glb.
## 4. F6.
##
## Что делает
## ----------
## Собирает пол, свет и камеру, ставит персонажа, гоняет его вперёд-назад
## и печатает в консоль проверки, которые невозможно сделать в Blender:
## масштаб после импорта, направление взгляда, стороны L/R, ось махов.
##
## Управление: ↑/↓ — скорость, R — сброс позы, T — отчёт, пробел — стоп.

const EPS := 0.005
const EXPECT_HEIGHT := 1.70

@export var model_scene: PackedScene
@export var patrol_distance := 4.5
@export var start_speed := 5.5   ## столько же, сколько SPEED у игрока

var visual: CharacterVisual
var model: Node3D
var label: Label
var _speed := 0.0
var _dir := 1.0
var _t := 0.0


func _ready() -> void:
	if model_scene == null:
		push_error("rig_debug: задай Model Scene (character.glb) в инспекторе.")
		return
	_speed = start_speed
	_hide_game_hud()
	set_process(false)          # патруль стартует только после проверок
	_build_stage()
	_spawn_character()
	await get_tree().process_frame
	_hide_game_hud()
	_run_checks()
	set_process(true)


## Autoload Boot вешает своё меню и HUD на корень — в отладочной
## сцене оно закрывает персонажа. Прячем, не трогая саму игру.
func _hide_game_hud() -> void:
	var boot := get_node_or_null("/root/Boot")
	if boot == null:
		return
	for child in get_tree().root.get_children():
		if child is CanvasLayer and not is_ancestor_of(child):
			(child as CanvasLayer).visible = false


# ------------------------------------------------------------
func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.19)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.48, 0.55)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -40, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	floor_mesh.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.31, 0.33)
	floor_mesh.material_override = m
	add_child(floor_mesh)

	# метровая линейка: кубики на 0.5 / 1.0 / 1.7 м
	for h in [0.5, 1.0, 1.7]:
		var tick := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.006, 0.06)
		tick.mesh = bm
		tick.position = Vector3(0.9, h, 0.0)
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(1, 0.85, 0.2) if h == 1.7 else Color(0.8, 0.8, 0.8)
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tick.material_override = tm
		add_child(tick)

	var cam := Camera3D.new()
	cam.position = Vector3(2.6, 1.35, 3.4)
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)

	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 15)
	ui.add_child(label)


func _spawn_character() -> void:
	# модель кладём внутрь ДО добавления в дерево, иначе _ready() у
	# CharacterVisual отработает по пустому узлу и не найдёт суставы
	var holder := CharacterVisual.new()
	holder.name = "Visual"
	holder.auto_track_velocity = true

	model = model_scene.instantiate() as Node3D
	holder.add_child(model)
	add_child(holder)
	visual = holder

	# «дискета» в правой руке — видно, попадает ли предмет в ладонь
	var grip := visual.get_grip(true)
	if grip:
		var disk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.09, 0.012)
		disk.mesh = bm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.15, 0.35, 0.75)
		disk.material_override = dm
		grip.add_child(disk)


# ------------------------------------------------------------
func _process(delta: float) -> void:
	if visual == null:
		return
	if Input.is_action_just_pressed("ui_up"):
		_speed = minf(_speed + 0.4, 6.0)
	if Input.is_action_just_pressed("ui_down"):
		_speed = maxf(_speed - 0.4, 0.0)
	if Input.is_action_just_pressed("ui_accept"):
		_speed = 0.0
	if Input.is_key_pressed(KEY_R):
		visual.reset_pose()
	if Input.is_key_pressed(KEY_T):
		visual.report()
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()

	# патруль вперёд-назад, персонаж разворачивается лицом по ходу
	var p := visual.position
	p.z += _dir * _speed * delta
	if absf(p.z) > patrol_distance:
		_dir = -_dir
		p.z = clampf(p.z, -patrol_distance, patrol_distance)
	visual.position = p
	# модель смотрит в -Z, значит при движении в +Z разворачиваем на 180
	visual.rotation.y = 0.0 if _dir < 0.0 else PI

	_t += delta
	if _t < 2.0:
		_hide_game_hud()   # HUD автозагрузки достраивается не сразу
	label.text ="скорость %.2f м/с   (↑/↓ менять, пробел — стоп, R — сброс, T — отчёт)\n" % _speed
	label.text += "анимация: %.2f м/с" % visual.get_speed()


# ------------------------------------------------------------
func _run_checks() -> void:
	var res: Array = []

	var need := ["Character_ROOT", "Hips", "Torso", "Head", "Head_Top",
		"Collar", "Tie", "Eye_L", "Eye_R", "Grip_L", "Grip_R",
		"Arm_L_Upper", "Arm_R_Upper", "Leg_L_Upper", "Leg_R_Upper",
		"Foot_L", "Foot_R"]
	var missing: PackedStringArray = []
	var node := {}
	for n in need:
		var f := model.find_child(String(n), true, false) as Node3D
		if f == null:
			missing.append(String(n))
		else:
			node[n] = f
	var miss_text := "%d/%d" % [need.size(), need.size()]
	if not missing.is_empty():
		miss_text = "нет: %s" % ", ".join(missing)
	res.append([missing.is_empty(), "все ключевые узлы импортировались", miss_text])

	if not missing.is_empty():
		_print_checks(res)
		return

	# на время замеров глушим анимацию, иначе она перезапишет углы
	visual.set_process(false)
	visual.reset_pose()

	var box := _aabb_of(model)
	res.append([absf(box.size.y - EXPECT_HEIGHT) < EPS,
		"рост после импорта = 1.70 м",
		"%.4f м (ловит масштаб импорта)" % box.size.y])
	res.append([absf(box.position.y) < EPS, "подошвы на полу",
		"низ = %.4f" % box.position.y])
	res.append([box.size.x <= 0.80, "ширина <= 0.80 м",
		"%.3f м" % box.size.x])

	# всё ниже — в системе координат самой модели, чтобы поворот
	# сцены не влиял на результат
	# ориентация: галстук на груди, грудь смотрит в -Z
	var tie_z := model.to_local((node["Tie"] as Node3D).global_position).z
	res.append([tie_z < -0.05, "лицо смотрит в -Z (Godot forward)",
		"галстук z = %.3f, должен быть отрицательным" % tie_z])

	# стороны: правая рука в +X
	var rx := model.to_local((node["Arm_R_Upper"] as Node3D).global_position).x
	var lx := model.to_local((node["Arm_L_Upper"] as Node3D).global_position).x
	res.append([rx > 0.0 and lx < 0.0, "L/R не перепутаны",
		"Arm_R x=%.3f, Arm_L x=%.3f" % [rx, lx]])

	# ось махов: +rotation.x должен уводить ступню вперёд (в -Z)
	var leg := node["Leg_L_Upper"] as Node3D
	var foot := node["Foot_L"] as Node3D
	var pivot := model.to_local(leg.global_position)
	var before := model.to_local(foot.global_position)
	leg.rotation.x = deg_to_rad(30.0)
	var after := model.to_local(foot.global_position)
	leg.rotation.x = 0.0
	res.append([after.z < before.z - 0.05, "rotation.x > 0 = мах вперёд",
		"ступня z: %.3f -> %.3f" % [before.z, after.z]])
	var d_before := before.distance_to(pivot)
	var d_after := after.distance_to(pivot)
	res.append([absf(d_after - d_before) < 0.001,
		"нога не растянулась при повороте",
		"|бедро+голень| %.4f -> %.4f, origin реально в суставе"
			% [d_before, d_after]])

	# точка предмета в руке
	var grip := node["Grip_R"] as Node3D
	var hand := model.find_child("Hand_R", true, false) as Node3D
	res.append([grip.global_position.distance_to(hand.global_position) < 0.12,
		"Grip_R в ладони, а не в стороне",
		"расстояние до запястья %.3f м"
			% grip.global_position.distance_to(hand.global_position)])

	visual.set_process(true)
	_print_checks(res)


func _print_checks(res: Array) -> void:
	print("\n" + "=".repeat(64))
	print("ПРОВЕРКА ИМПОРТА В GODOT")
	print("=".repeat(64))
	var bad := 0
	for r in res:
		if not r[0]:
			bad += 1
		print(" %s  %-38s %s" % ["OK  " if r[0] else "FAIL", r[1], r[2]])
	print("-".repeat(64))
	print("ИТОГ: %d из %d. %s" % [res.size() - bad, res.size(),
		"Модель готова к использованию." if bad == 0 else "ЕСТЬ ПРОБЛЕМЫ."])


func _aabb_of(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
