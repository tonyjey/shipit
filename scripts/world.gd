extends Node3D
## Офис. Всё из примитивов — плейсхолдер под будущие ассеты.

const StationScript := preload("res://scripts/workstation.gd")
const AssemblerScript := preload("res://scripts/assembler.gd")
const BoardScript := preload("res://scripts/board.gd")
const QaScript := preload("res://scripts/qa_terminal.gd")
const DoorScript := preload("res://scripts/door.gd")
const BossScript := preload("res://scripts/boss_desk.gd")
const ShopCounterScript := preload("res://scripts/shop_counter.gd")

const ROOM := 26.0            # рабочий этаж стал шире примерно на 30%
const WALL_H := 4.0
const WALL_T := 0.6
const DOOR_W := 2.2
const DOOR_T := 0.24        # створка тоньше стены
const DOOR_H := 2.8

# кабинет начальника пристроен к правой стене
const OFFICE_X0 := 13.0
const OFFICE_X1 := 22.0
const OFFICE_Z0 := -5.0
const OFFICE_Z1 := 5.0

# магазин — зеркально, у левой стены
const SHOP_X0 := -22.0
const SHOP_X1 := -13.0
const SHOP_Z0 := -5.0
const SHOP_Z1 := 5.0

const STATIONS := [
	{"disc": "code",  "title": "Код",     "color": Color(0.40, 0.70, 1.00)},
	{"disc": "art",   "title": "Графика", "color": Color(1.00, 0.52, 0.62)},
	{"disc": "music", "title": "Музыка",  "color": Color(0.70, 0.52, 1.00)},
]

var stations: Array = []
var assembler: Node3D = null
var items_root: Node3D = null
var bugs_root: Node3D = null
var qa: Node3D = null
var tray: Node3D = null
var board: Label3D = null
var board_body: StaticBody3D = null
var doors: Array = []
var boss_desk: StaticBody3D = null
var shop_counter: StaticBody3D = null
var shelf_labels: Array = []
var shelf_boxes: Array = []


func _ready() -> void:
	items_root = Node3D.new()
	items_root.name = "Items"
	add_child(items_root)

	bugs_root = Node3D.new()
	bugs_root.name = "Bugs"
	add_child(bugs_root)

	_build_env()
	_build_light()
	_build_floor()
	_build_walls()
	_build_stations()
	_build_assembler()
	_build_qa()
	_build_tray()
	_build_board()
	_build_office()
	_build_shop()
	_build_doors()


func get_spawn_point(index: int) -> Vector3:
	return Vector3(-3.0 + index * 2.0, 1.2, 4.4)


func tray_position() -> Vector3:
	return Vector3(0, 0, 7.0)


func tray_slot(i: int) -> Vector3:
	return tray_position() + Vector3(-0.65 + float(i) * 0.26, 1.05, 0)


func _build_board() -> void:
	# Доска — физический объект: к ней подходят и берут контракт.
	board_body = StaticBody3D.new()
	board_body.position = Vector3(0, 3.3, -ROOM * 0.5 + 0.4)
	add_child(board_body)

	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(9.5, 2.8, 0.15)
	panel.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.16, 0.18, 0.24)
	panel.material_override = pmat
	board_body.add_child(panel)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(9.5, 2.8, 0.15)
	cs.shape = bs
	board_body.add_child(cs)

	board = Label3D.new()
	board.text = "ДОСКА КОНТРАКТОВ\nзаказ берут у издателя — дверь справа"
	board.position = Vector3(0, 3.3, -ROOM * 0.5 + 0.5)
	board.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	board.double_sided = false
	board.pixel_size = 0.012
	board.outline_size = 10
	board.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(board)


## Возврат доски в состояние «заказа нет».
func clear_board() -> void:
	if board:
		board.text = "ДОСКА КОНТРАКТОВ\nзаказ берут у издателя — дверь справа"


## Доска задач над лотком: что именно просит издатель.
func set_board(c: Dictionary) -> void:
	if board == null or c.is_empty():
		return
	var need: Dictionary = c["need"]
	board.text = "КОНТРАКТ №%d   ·   %s\nнужно:  Код %d   ·   Графика %d   ·   Музыка %d\nсрок: %d %s   ·   гонорар $%d" % [
		int(c.get("index", 1)), String(c["title"]),
		int(need.get("code", 0)), int(need.get("art", 0)), int(need.get("music", 0)),
		int(c["weeks"]), weeks_word(int(c["weeks"])), int(c["pay"])]


## «1 неделя», «3 недели», «5 недель» — иначе на доске режет глаз.
static func weeks_word(n: int) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return "неделя"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "недели"
	return "недель"


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.62, 0.85)
	sky_mat.sky_horizon_color = Color(0.85, 0.86, 0.90)
	sky_mat.ground_bottom_color = Color(0.35, 0.35, 0.40)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)


func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _box(size: Vector3, pos: Vector3, col: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mesh.material_override = mat
	body.add_child(mesh)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)

	add_child(body)
	return body


func _build_floor() -> void:
	_box(Vector3(ROOM, 1.0, ROOM), Vector3(0, -0.5, 0), Color(0.78, 0.72, 0.62))


func _build_walls() -> void:
	var h := WALL_H
	var t := WALL_T
	var c := Color(0.90, 0.88, 0.84)
	var half := ROOM * 0.5
	_box(Vector3(ROOM, h, t), Vector3(0, h * 0.5, -half), c)
	_box(Vector3(ROOM, h, t), Vector3(0, h * 0.5, half), c)
	# левая стена с проёмом в магазин
	var gap_l := DOOR_W * 0.5
	var seg_l := (half - gap_l)
	_box(Vector3(t, h, seg_l), Vector3(-half, h * 0.5, -gap_l - seg_l * 0.5), c)
	_box(Vector3(t, h, seg_l), Vector3(-half, h * 0.5, gap_l + seg_l * 0.5), c)
	_box(Vector3(t, h - DOOR_H, DOOR_W), Vector3(-half, DOOR_H + (h - DOOR_H) * 0.5, 0), c)

	# правая стена с проёмом в кабинет
	var gap := DOOR_W * 0.5
	var seg := (half - gap)
	_box(Vector3(t, h, seg), Vector3(half, h * 0.5, -gap - seg * 0.5), c)
	_box(Vector3(t, h, seg), Vector3(half, h * 0.5, gap + seg * 0.5), c)
	_box(Vector3(t, h - DOOR_H, DOOR_W), Vector3(half, DOOR_H + (h - DOOR_H) * 0.5, 0), c)


## Кабинет начальника: холодная комната, часы здесь не идут.
func _build_office() -> void:
	var c := Color(0.86, 0.83, 0.90)
	var w := OFFICE_X1 - OFFICE_X0
	var d := OFFICE_Z1 - OFFICE_Z0
	var cx := (OFFICE_X0 + OFFICE_X1) * 0.5

	_box(Vector3(w, 1.0, d), Vector3(cx, -0.5, 0), Color(0.62, 0.56, 0.50))
	_box(Vector3(w, WALL_H, WALL_T), Vector3(cx, WALL_H * 0.5, OFFICE_Z0), c)
	_box(Vector3(w, WALL_H, WALL_T), Vector3(cx, WALL_H * 0.5, OFFICE_Z1), c)
	_box(Vector3(WALL_T, WALL_H, d), Vector3(OFFICE_X1, WALL_H * 0.5, 0), c)

	# стол начальника
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.30, 0.22, 0.18)

	boss_desk = StaticBody3D.new()
	boss_desk.position = Vector3(cx + 1.6, 0, 0)
	boss_desk.rotation_degrees = Vector3(0, 90, 0)
	boss_desk.set_script(BossScript)
	add_child(boss_desk)

	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.4, 0.14, 1.1)
	top.mesh = tm
	top.material_override = wood
	top.position = Vector3(0, 0.8, 0)
	boss_desk.add_child(top)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 0.88, 1.1)
	cs.shape = bs
	cs.position = Vector3(0, 0.44, 0)
	boss_desk.add_child(cs)

	for sx in [-1.05, 1.05]:
		for sz in [-0.45, 0.45]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.12, 0.74, 0.12)
			leg.mesh = lm
			leg.material_override = wood
			leg.position = Vector3(sx, 0.37, sz)
			boss_desk.add_child(leg)

	var desk_sign := Label3D.new()
	desk_sign.text = "ИЗДАТЕЛЬ"
	desk_sign.position = Vector3(0, 1.25, -0.6)
	desk_sign.rotation_degrees = Vector3(0, 180, 0)
	desk_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	desk_sign.double_sided = false
	desk_sign.pixel_size = 0.006
	desk_sign.outline_size = 8
	boss_desk.add_child(desk_sign)

	# сам начальник — пока капсула, заменится вместе с персонажами
	var boss_mat := StandardMaterial3D.new()
	boss_mat.albedo_color = Color(0.35, 0.33, 0.42)
	var boss_body := StaticBody3D.new()
	boss_body.position = Vector3(cx + 2.4, 0.75, -1.9)
	add_child(boss_body)

	var boss := MeshInstance3D.new()
	var bmesh := CapsuleMesh.new()
	bmesh.radius = 0.42
	bmesh.height = 1.5
	boss.mesh = bmesh
	boss.material_override = boss_mat
	boss_body.add_child(boss)

	var boss_cs := CollisionShape3D.new()
	var boss_shape := CapsuleShape3D.new()
	boss_shape.radius = 0.42
	boss_shape.height = 1.5
	boss_cs.shape = boss_shape
	boss_body.add_child(boss_cs)

	_build_office_props(cx)
	_build_shelf(cx)


## Обстановка кабинета: без неё комната читается как склад.
func _build_office_props(cx: float) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.20, 0.20, 0.24)

	# кресло за столом
	var seat := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.62, 0.10, 0.62)
	seat.mesh = sm
	seat.material_override = dark
	seat.position = Vector3(cx + 2.35, 0.48, -1.9)
	add_child(seat)

	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.85, 0.62)
	back.mesh = bm
	back.material_override = dark
	back.position = Vector3(cx + 2.62, 0.9, -1.9)
	add_child(back)

	# ковёр под столом
	var rug := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(3.4, 0.02, 4.2)
	rug.mesh = rm
	var rug_mat := StandardMaterial3D.new()
	rug_mat.albedo_color = Color(0.35, 0.30, 0.42)
	rug.material_override = rug_mat
	rug.position = Vector3(cx + 0.9, 0.011, 0)
	add_child(rug)

	# окно на торцевой стене
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.62, 0.80, 0.95)
	glass.emission_enabled = true
	glass.emission = Color(0.75, 0.88, 1.0)
	glass.emission_energy_multiplier = 0.5
	var win := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.08, 1.5, 2.6)
	win.mesh = wm
	win.material_override = glass
	win.position = Vector3(OFFICE_X1 - 0.3, 2.3, 0)
	add_child(win)

	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.05, 1.7, 2.8)
	frame.mesh = fm
	frame.material_override = dark
	frame.position = Vector3(OFFICE_X1 - 0.34, 2.3, 0)
	add_child(frame)

	# растение в углу
	var pot := MeshInstance3D.new()
	var potm := CylinderMesh.new()
	potm.top_radius = 0.22
	potm.bottom_radius = 0.17
	potm.height = 0.4
	pot.mesh = potm
	var pot_mat := StandardMaterial3D.new()
	pot_mat.albedo_color = Color(0.55, 0.35, 0.25)
	pot.material_override = pot_mat
	pot.position = Vector3(OFFICE_X0 + 1.1, 0.2, OFFICE_Z1 - 1.1)
	add_child(pot)

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.28, 0.55, 0.30)
	for i in 5:
		var leaf := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.09, 0.75, 0.24)
		leaf.mesh = lm
		leaf.material_override = leaf_mat
		leaf.position = Vector3(OFFICE_X0 + 1.1, 0.72, OFFICE_Z1 - 1.1)
		leaf.rotation_degrees = Vector3(randf_range(-22, 22), float(i) * 36.0, randf_range(-22, 22))
		add_child(leaf)

	# бумаги и кружка на столе
	var paper := MeshInstance3D.new()
	var pm2 := BoxMesh.new()
	pm2.size = Vector3(0.30, 0.02, 0.22)
	paper.mesh = pm2
	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.92, 0.90, 0.86)
	paper.material_override = paper_mat
	paper.position = Vector3(cx + 1.6, 0.88, -0.5)
	paper.rotation_degrees = Vector3(0, 12, 0)
	add_child(paper)

	var mug := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.05
	mm.bottom_radius = 0.045
	mm.height = 0.12
	mug.mesh = mm
	var mug_mat := StandardMaterial3D.new()
	mug_mat.albedo_color = Color(0.85, 0.35, 0.30)
	mug.material_override = mug_mat
	mug.position = Vector3(cx + 1.35, 0.93, 0.35)
	add_child(mug)


## Полка выпущенных игр: коробки с названием и оценкой.
func _build_shelf(_cx: float) -> void:
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.42, 0.32, 0.24)

	var shelf_body := StaticBody3D.new()
	shelf_body.position = Vector3(OFFICE_X1 - 0.55, 1.5, 0)
	add_child(shelf_body)

	var plank := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 0.1, 7.0)
	plank.mesh = pm
	plank.material_override = shelf_mat
	shelf_body.add_child(plank)

	var shelf_cs := CollisionShape3D.new()
	var shelf_shape := BoxShape3D.new()
	shelf_shape.size = Vector3(0.5, 0.5, 7.0)
	shelf_cs.shape = shelf_shape
	shelf_cs.position = Vector3(0, 0.2, 0)
	shelf_body.add_child(shelf_cs)

	# боковины полки, чтобы она читалась мебелью, а не доской в воздухе
	for sz in [-3.55, 3.55]:
		var side := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.5, 1.6, 0.12)
		side.mesh = sm
		side.material_override = shelf_mat
		side.position = Vector3(OFFICE_X1 - 0.55, 0.8, sz)
		add_child(side)

	for i in 5:
		var z := -2.6 + float(i) * 1.3

		# коробка с игрой — стоит на полке
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.28, 0.21)
		box.mesh = bm
		box.position = Vector3(OFFICE_X1 - 0.75, 1.69, z)
		box.visible = false
		add_child(box)
		shelf_boxes.append(box)

		var l := Label3D.new()
		l.text = ""
		l.position = Vector3(OFFICE_X1 - 0.9, 2.05, z)
		l.rotation_degrees = Vector3(0, -90, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.double_sided = false
		l.pixel_size = 0.0042
		l.outline_size = 8
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)
		shelf_labels.append(l)


## Обновить полку по истории студии.
func set_shelf(history: Array) -> void:
	var start := maxi(history.size() - shelf_labels.size(), 0)
	for i in shelf_labels.size():
		var idx := start + i
		if idx < history.size():
			var h: Dictionary = history[idx]
			var score := int(h.get("score", 0))
			shelf_labels[i].text = "«%s»\n%d/100" % [String(h.get("title", "?")), score]
			var box: MeshInstance3D = shelf_boxes[i]
			box.visible = true
			var m := StandardMaterial3D.new()
			# цвет коробки говорит об оценке быстрее, чем цифра
			if score >= 75:
				m.albedo_color = Color(0.35, 0.72, 0.42)
			elif score >= 50:
				m.albedo_color = Color(0.82, 0.70, 0.30)
			else:
				m.albedo_color = Color(0.75, 0.35, 0.32)
			box.material_override = m
		else:
			shelf_labels[i].text = ""
			shelf_boxes[i].visible = false


func _build_doors() -> void:
	_make_door(0, ROOM * 0.5)
	_make_door(1, -ROOM * 0.5)


func _make_door(id: int, x: float) -> void:
	var d := DoorScript.new()
	d.door_id = id
	d.position = Vector3(x, 0, -DOOR_W * 0.5)   # петля у края проёма
	add_child(d)
	doors.append(d)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.33, 0.24)

	var leaf := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(DOOR_T, DOOR_H, DOOR_W)
	leaf.mesh = lm
	leaf.material_override = mat
	leaf.position = Vector3(0, DOOR_H * 0.5, DOOR_W * 0.5)
	d.add_child(leaf)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(DOOR_T, DOOR_H, DOOR_W)
	cs.shape = bs
	cs.position = Vector3(0, DOOR_H * 0.5, DOOR_W * 0.5)
	d.add_child(cs)


## Магазин: та же холодная комната, что и кабинет, только зеркально.
func _build_shop() -> void:
	var c := Color(0.84, 0.88, 0.86)
	var w := SHOP_X1 - SHOP_X0
	var d := SHOP_Z1 - SHOP_Z0
	var cx := (SHOP_X0 + SHOP_X1) * 0.5

	_box(Vector3(w, 1.0, d), Vector3(cx, -0.5, 0), Color(0.50, 0.55, 0.52))
	_box(Vector3(w, WALL_H, WALL_T), Vector3(cx, WALL_H * 0.5, SHOP_Z0), c)
	_box(Vector3(w, WALL_H, WALL_T), Vector3(cx, WALL_H * 0.5, SHOP_Z1), c)
	_box(Vector3(WALL_T, WALL_H, d), Vector3(SHOP_X0, WALL_H * 0.5, 0), c)

	# прилавок
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.34, 0.26, 0.20)

	shop_counter = StaticBody3D.new()
	shop_counter.position = Vector3(cx - 0.6, 0, 0)
	shop_counter.set_script(ShopCounterScript)
	add_child(shop_counter)

	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.9, 0.14, 3.2)
	top.mesh = tm
	top.material_override = wood
	top.position = Vector3(0, 1.02, 0)
	shop_counter.add_child(top)

	var front := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.7, 0.95, 3.0)
	front.mesh = fm
	var front_mat := StandardMaterial3D.new()
	front_mat.albedo_color = Color(0.55, 0.50, 0.46)
	front.material_override = front_mat
	front.position = Vector3(0, 0.48, 0)
	shop_counter.add_child(front)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 1.1, 3.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.55, 0)
	shop_counter.add_child(cs)

	var sign_label := Label3D.new()
	sign_label.text = "МАГАЗИН\nНАВЫКОВ"
	sign_label.position = Vector3(cx - 0.15, 2.5, 0)
	sign_label.rotation_degrees = Vector3(0, 90, 0)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_label.double_sided = false
	sign_label.pixel_size = 0.009
	sign_label.outline_size = 10
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sign_label)

	# витрина за прилавком
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.40, 0.42, 0.46)

	# витрина одним телом: сквозь полки и товар не пройти
	var case_body := StaticBody3D.new()
	case_body.position = Vector3(SHOP_X0 + 0.5, 1.1, 0)
	add_child(case_body)
	var case_cs := CollisionShape3D.new()
	var case_shape := BoxShape3D.new()
	case_shape.size = Vector3(0.5, 1.5, 4.0)
	case_cs.shape = case_shape
	case_cs.position = Vector3(0, 0.45, 0)
	case_body.add_child(case_cs)

	for row in 2:
		var plank := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.45, 0.08, 4.0)
		plank.mesh = pm
		plank.material_override = shelf_mat
		plank.position = Vector3(SHOP_X0 + 0.5, 1.1 + float(row) * 0.7, 0)
		add_child(plank)

		for i in 5:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.22, 0.3, 0.22)
			box.mesh = bm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.45 + 0.1 * float(i % 3), 0.62, 0.55 + 0.08 * float(row))
			box.material_override = m
			box.position = Vector3(SHOP_X0 + 0.5, 1.29 + float(row) * 0.7, -1.6 + float(i) * 0.8)
			add_child(box)


func _build_stations() -> void:
	var xs := [-6.5, 0.0, 6.5]
	for i in STATIONS.size():
		var data: Dictionary = STATIONS[i]
		var st := StationScript.new()
		st.index = i
		st.discipline = String(data["disc"])
		st.title = String(data["title"])
		st.color = data["color"]
		st.position = Vector3(float(xs[i]), 0.0, -7.8)
		add_child(st)
		stations.append(st)


func _build_assembler() -> void:
	assembler = AssemblerScript.new()
	assembler.position = Vector3(0, 0, -0.6)
	add_child(assembler)


func _build_qa() -> void:
	qa = QaScript.new()
	qa.position = Vector3(5.4, 0, 2.0)
	qa.rotation_degrees = Vector3(0, 200, 0)
	add_child(qa)


func _build_tray() -> void:
	# StaticBody3D, а не Node3D — иначе сквозь лоток можно пройти насквозь
	var body := StaticBody3D.new()
	body.position = tray_position()
	add_child(body)
	tray = body

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.9, 0.96, 1.0)
	cs.shape = bs
	cs.position = Vector3(0, 0.48, 0)
	body.add_child(cs)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.32)

	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.9, 0.12, 1.0)
	top.mesh = tm
	top.material_override = mat
	top.position = Vector3(0, 0.9, 0)
	tray.add_child(top)

	for sx in [-0.8, 0.8]:
		for sz in [-0.4, 0.4]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.1, 0.84, 0.1)
			leg.mesh = lm
			leg.material_override = mat
			leg.position = Vector3(sx, 0.42, sz)
			tray.add_child(leg)

	var label := Label3D.new()
	label.text = "ЛОТОК ЗАДАЧ"
	label.position = Vector3(0, 1.75, 0)
	label.rotation_degrees = Vector3(0, 180, 0)   # лицом в комнату
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.double_sided = false
	label.pixel_size = 0.0045
	label.outline_size = 8
	tray.add_child(label)
