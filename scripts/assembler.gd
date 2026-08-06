extends StaticBody3D
## Сборочная машина в центре офиса. Сюда несут готовые ассеты.

var _count_labels: Array = []
var _lamp_mat: StandardMaterial3D
var _flash := 0.0


func _ready() -> void:
	add_to_group("interactable")
	_build()


func _build() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.35, 0.38, 0.45)
	body_mat.metallic = 0.4
	body_mat.roughness = 0.5

	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(2.4, 1.5, 1.6)
	hull.mesh = hm
	hull.material_override = body_mat
	hull.position = Vector3(0, 0.75, 0)
	add_child(hull)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 1.5, 1.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)

	# приёмная воронка
	var funnel_mat := StandardMaterial3D.new()
	funnel_mat.albedo_color = Color(0.20, 0.22, 0.28)
	var funnel := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.55
	fm.bottom_radius = 0.25
	fm.height = 0.5
	funnel.mesh = fm
	funnel.material_override = funnel_mat
	funnel.position = Vector3(0, 1.72, 0)
	add_child(funnel)

	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.3, 1.0, 0.5)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(0.3, 1.0, 0.5)
	_lamp_mat.emission_energy_multiplier = 0.5
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.16
	lm.height = 0.32
	lamp.mesh = lm
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0.9, 1.6, 0.85)
	add_child(lamp)

	# машина стоит посреди комнаты, поэтому подписи вешаем с двух сторон,
	# а не разворачиваем их за игроком
	for side in [0.0, 180.0]:
		var title := Label3D.new()
		title.text = "СБОРКА"
		title.position = Vector3(0, 2.25, 0)
		title.rotation_degrees = Vector3(0, side, 0)
		title.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		title.pixel_size = 0.008
		title.outline_size = 8
		add_child(title)

		var cnt := Label3D.new()
		cnt.text = "Собрано: 0"
		cnt.position = Vector3(0, 1.98, 0)
		cnt.rotation_degrees = Vector3(0, side, 0)
		cnt.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		cnt.pixel_size = 0.006
		cnt.outline_size = 8
		add_child(cnt)
		_count_labels.append(cnt)


func set_count(n: int, avg_quality := 1.0) -> void:
	for l in _count_labels:
		l.text = "Собрано: %d    Качество: %d%%" % [n, int(round(avg_quality * 100.0))]
	_flash = 0.6


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		_lamp_mat.emission_energy_multiplier = 3.0
	else:
		_lamp_mat.emission_energy_multiplier = 0.5


func can_focus(_p) -> bool:
	return true


func get_prompt(p) -> String:
	var h = Game.held_item_of(p.peer_id)
	if h != null and String(h.kind).begins_with("asset_"):
		return "[E] Сдать в сборку — %s" % Game.title_of(h.kind)
	if Game.contract_running and Game.requirements_met():
		return "[E] СДАТЬ ИГРУ ИЗДАТЕЛЮ — всё готово досрочно"
	return "Сборка — неси готовый ассет со стола"


func get_target() -> Array:
	return ["assembler", 0]
