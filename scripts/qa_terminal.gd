extends StaticBody3D
## QA-терминал. Во время тестирования подсвечивает багов для всей команды.
## Асимметрия задумана специально: один подсвечивает — остальные ловят.

var _screen_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("interactable")
	_build()


func _build() -> void:
	var case_mat := StandardMaterial3D.new()
	case_mat.albedo_color = Color(0.28, 0.30, 0.36)

	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(1.1, 1.1, 0.7)
	hull.mesh = hm
	hull.material_override = case_mat
	hull.position = Vector3(0, 0.55, 0)
	add_child(hull)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 1.1, 0.7)
	cs.shape = bs
	cs.position = Vector3(0, 0.55, 0)
	add_child(cs)

	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(1.0, 0.45, 0.40)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(1.0, 0.45, 0.40)
	_screen_mat.emission_energy_multiplier = 0.4

	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.9, 0.6, 0.06)
	screen.mesh = sm
	screen.material_override = _screen_mat
	screen.position = Vector3(0, 1.35, 0.05)
	screen.rotation_degrees = Vector3(-12, 0, 0)
	add_child(screen)

	for side in [0.0, 180.0]:
		var label := Label3D.new()
		label.text = "QA-ТЕРМИНАЛ"
		label.position = Vector3(0, 1.85, 0)
		label.rotation_degrees = Vector3(0, side, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.double_sided = false
		label.pixel_size = 0.006
		label.outline_size = 8
		add_child(label)


func _process(_delta: float) -> void:
	if _screen_mat == null:
		return
	if Game.reveal_left > 0.0:
		_screen_mat.emission_energy_multiplier = 2.5
	elif Game.testing:
		_screen_mat.emission_energy_multiplier = 1.0
	else:
		_screen_mat.emission_energy_multiplier = 0.25


func can_focus(_p) -> bool:
	return true


func get_prompt(_p) -> String:
	if not Game.testing:
		return "QA-терминал — понадобится на тестировании"
	if Game.reveal_left > 0.0:
		return "Багов видно ещё %.0f с" % Game.reveal_left
	if Game.reveal_cooldown > 0.0:
		return "QA-терминал перезаряжается (%.0f с)" % Game.reveal_cooldown
	return "[E] Подсветить багов для всей команды"


func get_target() -> Array:
	return ["qa", 0]
