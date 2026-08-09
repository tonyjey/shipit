extends Node3D

const FLOPPY_MODEL := "res://models/floppy.glb"
## Переносимый предмет. Позицией управляет клиент локально:
## если предмет в руках — летит за игроком, если нет — лежит там, где сказал сервер.

var item_id := 0
var kind := "ticket_code"
var holder := 0
var quality := 1.0
var start_pos := Vector3.ZERO
var target_pos := Vector3.ZERO

var _spin := 0.0
var _label: Label3D = null


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

	if kind.begins_with("ticket_"):
		_build_floppy(col)
	else:
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.3, 0.3, 0.3)
		mesh.mesh = cube
		mesh.material_override = mat
		add_child(mesh)

	_label = Label3D.new()
	var label := _label
	if kind.begins_with("asset_"):
		label.text = "%s  %d%%" % [Game.title_of(kind), int(round(quality * 100.0))]
	else:
		label.text = Game.title_of(kind)
	label.position = Vector3(0, 0.36, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.005
	label.outline_size = 8
	add_child(label)


## Тикет — дискета. Цвет корпуса задаёт дисциплину: это «скин» модели,
## остальные детали (наклейка, шторка, втулка) остаются общими.
func _build_floppy(col: Color) -> void:
	var ps = load(FLOPPY_MODEL)
	if ps == null:
		_build_card_fallback(col)
		return
	var floppy: Node3D = ps.instantiate()
	floppy.scale = Vector3(3.2, 3.2, 3.2)
	floppy.rotation_degrees = Vector3(90, 0, 0)   # ставим «лицом» к игроку
	add_child(floppy)

	# в экспорте затесался лишний кубик из сцены Blender
	for junk in floppy.find_children("Cube", "MeshInstance3D", true, false):
		junk.queue_free()
	for junk in floppy.find_children("*", "Camera3D", true, false):
		junk.queue_free()
	for junk in floppy.find_children("*", "Light3D", true, false):
		junk.queue_free()

	var body := floppy.find_children("Floppy_Body", "MeshInstance3D", true, false)
	if body.is_empty():
		_build_card_fallback(col)
		return
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = col * 0.75
	body_mat.emission_enabled = true
	body_mat.emission = col
	body_mat.emission_energy_multiplier = 0.25
	body_mat.roughness = 0.7
	(body[0] as MeshInstance3D).set_surface_override_material(0, body_mat)


func _build_card_fallback(col: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.35
	var mesh := MeshInstance3D.new()
	var card := BoxMesh.new()
	card.size = Vector3(0.34, 0.44, 0.04)
	mesh.mesh = card
	mesh.material_override = mat
	add_child(mesh)


func _process(delta: float) -> void:
	if holder != 0 and Boot.players.has(holder):
		# В руках предмет прикреплён жёстко. Раньше он догонял игрока
		# интерполяцией: позиция отставала, а поворот применялся сразу,
		# из-за чего подпись при развороте будто раздваивалась.
		var p := Boot.players[holder] as Node3D
		var fwd := -p.global_transform.basis.z
		global_position = p.global_position + fwd * 0.8 + Vector3(0, 0.15, 0)
		target_pos = global_position
		rotation.y = p.rotation.y
	else:
		_spin += delta * 1.2
		rotation.y = _spin
		global_position = global_position.lerp(target_pos, clampf(delta * 14.0, 0.0, 1.0))

	# Подпись показываем только у предмета под прицелом. Раньше подписывались
	# все предметы в радиусе, и лоток превращался в кашу из наложенных строк.
	if _label:
		_label.visible = Boot.focus_node == self


func can_focus(p) -> bool:
	return holder == 0 and Game.held_item_of(p.peer_id) == null


func get_prompt(_p) -> String:
	return "[E] Взять — %s" % Game.title_of(kind)


func get_target() -> Array:
	return ["item", item_id]
