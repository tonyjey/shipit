extends Node3D
## Офис. Всё из примитивов — плейсхолдер под будущие ассеты.

const StationScript := preload("res://scripts/workstation.gd")
const AssemblerScript := preload("res://scripts/assembler.gd")

const ROOM := 20.0

const STATIONS := [
	{"disc": "code",  "title": "Код",     "color": Color(0.40, 0.70, 1.00)},
	{"disc": "art",   "title": "Графика", "color": Color(1.00, 0.52, 0.62)},
	{"disc": "music", "title": "Музыка",  "color": Color(0.70, 0.52, 1.00)},
]

var stations: Array = []
var assembler: Node3D = null
var items_root: Node3D = null
var tray: Node3D = null
var board: Label3D = null


func _ready() -> void:
	items_root = Node3D.new()
	items_root.name = "Items"
	add_child(items_root)

	_build_env()
	_build_light()
	_build_floor()
	_build_walls()
	_build_stations()
	_build_assembler()
	_build_tray()
	_build_board()


func get_spawn_point(index: int) -> Vector3:
	return Vector3(-2.4 + index * 1.6, 1.2, 7.4)


func tray_position() -> Vector3:
	return Vector3(0, 0, 5.4)


func tray_slot(i: int) -> Vector3:
	return tray_position() + Vector3(-0.65 + float(i) * 0.26, 1.05, 0)


func _build_board() -> void:
	board = Label3D.new()
	board.text = "ждём контракт..."
	board.position = tray_position() + Vector3(0, 2.7, 0)
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.pixel_size = 0.008
	board.outline_size = 10
	board.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(board)


## Доска задач над лотком: что именно просит издатель.
func set_board(c: Dictionary) -> void:
	if board == null or c.is_empty():
		return
	var need: Dictionary = c["need"]
	board.text = "%s\nнужно:  Код %d   ·   Графика %d   ·   Музыка %d\nсрок: %d недель   ·   гонорар %d ₽" % [
		String(c["title"]),
		int(need.get("code", 0)), int(need.get("art", 0)), int(need.get("music", 0)),
		int(c["weeks"]), int(c["pay"])]


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
	var h := 4.0
	var t := 0.6
	var c := Color(0.90, 0.88, 0.84)
	var half := ROOM * 0.5
	_box(Vector3(ROOM, h, t), Vector3(0, h * 0.5, -half), c)
	_box(Vector3(ROOM, h, t), Vector3(0, h * 0.5, half), c)
	_box(Vector3(t, h, ROOM), Vector3(-half, h * 0.5, 0), c)
	_box(Vector3(t, h, ROOM), Vector3(half, h * 0.5, 0), c)


func _build_stations() -> void:
	var xs := [-5.0, 0.0, 5.0]
	for i in STATIONS.size():
		var data: Dictionary = STATIONS[i]
		var st := StationScript.new()
		st.index = i
		st.discipline = String(data["disc"])
		st.title = String(data["title"])
		st.color = data["color"]
		st.position = Vector3(float(xs[i]), 0.0, -6.0)
		add_child(st)
		stations.append(st)


func _build_assembler() -> void:
	assembler = AssemblerScript.new()
	assembler.position = Vector3(0, 0, -0.5)
	add_child(assembler)


func _build_tray() -> void:
	tray = Node3D.new()
	tray.position = tray_position()
	add_child(tray)

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
	label.position = Vector3(0, 1.6, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.007
	label.outline_size = 8
	tray.add_child(label)
