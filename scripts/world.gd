extends Node3D
## Офис. Всё из примитивов — плейсхолдер под будущие ассеты.

const StationScript := preload("res://scripts/workstation.gd")
const AssemblerScript := preload("res://scripts/assembler.gd")
const BoardScript := preload("res://scripts/board.gd")
const QaScript := preload("res://scripts/qa_terminal.gd")
const DoorScript := preload("res://scripts/door.gd")
const BossScript := preload("res://scripts/boss_desk.gd")

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
var shelf_labels: Array = []


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
	_box(Vector3(t, h, ROOM), Vector3(-half, h * 0.5, 0), c)

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

	var sign := Label3D.new()
	sign.text = "ИЗДАТЕЛЬ"
	sign.position = Vector3(0, 1.25, -0.6)
	sign.rotation_degrees = Vector3(0, 180, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.double_sided = false
	sign.pixel_size = 0.006
	sign.outline_size = 8
	boss_desk.add_child(sign)

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

	_build_shelf(cx)


## Полка выпущенных игр: коробки с названием и оценкой.
func _build_shelf(cx: float) -> void:
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
	shelf_shape.size = Vector3(0.5, 0.5, 7.0)   # чуть выше доски, чтобы не влезали головой
	shelf_cs.shape = shelf_shape
	shelf_cs.position = Vector3(0, 0.2, 0)
	shelf_body.add_child(shelf_cs)

	for i in 5:
		var l := Label3D.new()
		l.text = ""
		l.position = Vector3(OFFICE_X1 - 0.9, 1.85, -2.6 + float(i) * 1.3)
		l.rotation_degrees = Vector3(0, -90, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.double_sided = false
		l.pixel_size = 0.0045
		l.outline_size = 8
		add_child(l)
		shelf_labels.append(l)


## Обновить полку по истории студии.
func set_shelf(history: Array) -> void:
	var start := maxi(history.size() - shelf_labels.size(), 0)
	for i in shelf_labels.size():
		var idx := start + i
		if idx < history.size():
			var h: Dictionary = history[idx]
			shelf_labels[i].text = "«%s»\n%d/100" % [String(h.get("title", "?")), int(h.get("score", 0))]
		else:
			shelf_labels[i].text = ""


func _build_doors() -> void:
	var d := DoorScript.new()
	d.door_id = 0
	d.position = Vector3(ROOM * 0.5, 0, -DOOR_W * 0.5)   # петля у края проёма
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
