extends Node3D
## Переносимый предмет. Позицией управляет клиент локально:
## если предмет в руках — летит за игроком, если нет — лежит там, где сказал сервер.

var item_id := 0
var kind := "ticket_code"
var holder := 0
var start_pos := Vector3.ZERO
var target_pos := Vector3.ZERO

var _spin := 0.0


func _ready() -> void:
	add_to_group("interactable")
	global_position = start_pos
	target_pos = start_pos
	_build()


func _build() -> void:
	var col := Game.color_of(kind)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.35

	var mesh := MeshInstance3D.new()
	if kind.begins_with("ticket_"):
		var card := BoxMesh.new()
		card.size = Vector3(0.34, 0.44, 0.04)
		mesh.mesh = card
	else:
		var cube := BoxMesh.new()
		cube.size = Vector3(0.3, 0.3, 0.3)
		mesh.mesh = cube
	mesh.material_override = mat
	add_child(mesh)

	var label := Label3D.new()
	label.text = Game.title_of(kind)
	label.position = Vector3(0, 0.36, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.005
	label.outline_size = 8
	add_child(label)


func _process(delta: float) -> void:
	if holder != 0 and Boot.players.has(holder):
		var p := Boot.players[holder] as Node3D
		var fwd := -p.global_transform.basis.z
		target_pos = p.global_position + fwd * 0.7 + Vector3(0, 0.75, 0)
		rotation.y = p.rotation.y
	else:
		_spin += delta * 1.2
		rotation.y = _spin
	global_position = global_position.lerp(target_pos, clampf(delta * 14.0, 0.0, 1.0))


func can_focus(p) -> bool:
	return holder == 0 and Game.held_item_of(p.peer_id) == null


func get_prompt(_p) -> String:
	return "[E] Взять — %s" % Game.title_of(kind)


func get_target() -> Array:
	return ["item", item_id]
