extends Node3D
## Баг — физическое существо, которое бегает по офису во время тестирования.
## Невидим, пока кто-нибудь не подсветит его с QA-терминала.

var bug_id := 0
var start_pos := Vector3.ZERO
var target_pos := Vector3.ZERO
var revealed := false

var _spin := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("interactable")
	global_position = start_pos
	target_pos = start_pos
	_build()
	visible = false


func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.28, 0.32)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.28, 0.32)
	_mat.emission_energy_multiplier = 1.4

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.46, 0.46, 0.46)
	body.mesh = bm
	body.material_override = _mat
	add_child(body)

	# «усики» — чтобы силуэт читался как существо, а не как кубик
	for sx in [-0.16, 0.16]:
		var ant := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.05, 0.26, 0.05)
		ant.mesh = am
		ant.material_override = _mat
		ant.position = Vector3(float(sx), 0.32, 0)
		add_child(ant)

	var label := Label3D.new()
	label.text = "БАГ"
	label.position = Vector3(0, 0.62, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.005
	label.outline_size = 8
	label.modulate = Color(1.0, 0.6, 0.6)
	add_child(label)


func _process(delta: float) -> void:
	global_position = global_position.lerp(target_pos, clampf(delta * 10.0, 0.0, 1.0))
	_spin += delta * 4.0
	rotation.y = _spin
	rotation.x = sin(_spin * 1.7) * 0.25
	revealed = Game.reveal_left > 0.0
	visible = revealed


func can_focus(_p) -> bool:
	return revealed


func get_prompt(_p) -> String:
	return "[E] Поймать бага"


func get_target() -> Array:
	return ["bug", bug_id]
