extends Node3D
## Офис. Пока целиком из примитивов — плейсхолдер под будущие ассеты.

const StationScript := preload("res://scripts/workstation.gd")

const ROOM := 18.0

const STATIONS := [
	{"id": "code",  "title": "Код",      "color": Color(0.40, 0.70, 1.00)},
	{"id": "art",   "title": "Графика",  "color": Color(1.00, 0.52, 0.62)},
	{"id": "music", "title": "Музыка",   "color": Color(0.70, 0.52, 1.00)},
	{"id": "text",  "title": "Сценарий", "color": Color(1.00, 0.82, 0.42)},
]


func _ready() -> void:
	_build_env()
	_build_light()
	_build_floor()
	_build_walls()
	_build_stations()


func get_spawn_point(index: int) -> Vector3:
	return Vector3(-2.4 + index * 1.6, 1.2, 5.0)


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


func _box(size: Vector3, pos: Vector3, col: Color, solid := true) -> StaticBody3D:
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

	if solid:
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
	var xs := [-5.0, -1.8, 1.8, 5.0]
	for i in STATIONS.size():
		var data: Dictionary = STATIONS[i]
		var st := StationScript.new()
		st.station_id = String(data["id"])
		st.title = String(data["title"])
		st.color = data["color"]
		st.position = Vector3(float(xs[i]), 0.0, -4.5)
		add_child(st)
