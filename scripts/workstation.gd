extends StaticBody3D
## Рабочее место. Сейчас — заглушка. Сюда подключим мини-игры на следующем шаге.

var station_id := "code"
var title := "Код"
var color := Color.WHITE


func _ready() -> void:
	add_to_group("interactable")
	_build()


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.30, 0.22)

	# столешница
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.8, 0.12, 0.9)
	top.mesh = tm
	top.material_override = mat
	top.position = Vector3(0, 0.78, 0)
	add_child(top)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 0.86, 0.9)
	cs.shape = bs
	cs.position = Vector3(0, 0.43, 0)
	add_child(cs)

	# ножки
	for sx in [-0.75, 0.75]:
		for sz in [-0.35, 0.35]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.1, 0.72, 0.1)
			leg.mesh = lm
			leg.material_override = mat
			leg.position = Vector3(sx, 0.36, sz)
			add_child(leg)

	# монитор — цвет дисциплины
	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color = color
	screen_mat.emission_enabled = true
	screen_mat.emission = color
	screen_mat.emission_energy_multiplier = 0.6

	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.9, 0.55, 0.06)
	screen.mesh = sm
	screen.material_override = screen_mat
	screen.position = Vector3(0, 1.2, -0.15)
	add_child(screen)

	var label := Label3D.new()
	label.text = title
	label.position = Vector3(0, 1.65, -0.15)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.007
	add_child(label)


func get_prompt() -> String:
	return "[E] Работать: %s" % title


func interact(_who: Node) -> void:
	Boot.toast("Заглушка: мини-игра «%s» появится на следующем шаге" % title)
