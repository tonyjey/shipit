extends StaticBody3D
## Рабочее место. Пока превращает тикет в ассет по таймеру.
## На Фазе 2 таймер заменится на мини-игру.

var index := 0
var discipline := "code"
var title := "Код"
var color := Color.WHITE

var _busy := false
var _left := 0.0
var _total := 1.0
var _bar: MeshInstance3D
var _screen_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("interactable")
	_build()


func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.30, 0.22)

	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.8, 0.12, 0.9)
	top.mesh = tm
	top.material_override = wood
	top.position = Vector3(0, 0.78, 0)
	add_child(top)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 0.86, 0.9)
	cs.shape = bs
	cs.position = Vector3(0, 0.43, 0)
	add_child(cs)

	for sx in [-0.75, 0.75]:
		for sz in [-0.35, 0.35]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.1, 0.72, 0.1)
			leg.mesh = lm
			leg.material_override = wood
			leg.position = Vector3(sx, 0.36, sz)
			add_child(leg)

	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = color
	_screen_mat.emission_enabled = true
	_screen_mat.emission = color
	_screen_mat.emission_energy_multiplier = 0.5

	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.9, 0.55, 0.06)
	screen.mesh = sm
	screen.material_override = _screen_mat
	screen.position = Vector3(0, 1.2, -0.15)
	add_child(screen)

	var label := Label3D.new()
	label.text = title
	label.position = Vector3(0, 1.7, -0.15)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.007
	label.outline_size = 8
	add_child(label)

	# полоса прогресса
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.4, 1.0, 0.5)
	bar_mat.emission_enabled = true
	bar_mat.emission = Color(0.4, 1.0, 0.5)
	bar_mat.emission_energy_multiplier = 1.0
	_bar = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.09, 0.09)
	_bar.mesh = bm
	_bar.material_override = bar_mat
	_bar.position = Vector3(0, 1.53, -0.15)
	_bar.visible = false
	add_child(_bar)


func output_position() -> Vector3:
	return global_position + Vector3(0, 0.98, 0.32)


func begin_work(duration: float) -> void:
	_busy = true
	_total = maxf(duration, 0.01)
	_left = duration
	_bar.visible = true
	_bar.scale.x = 0.01
	_screen_mat.emission_energy_multiplier = 1.6


func end_work() -> void:
	_busy = false
	_bar.visible = false
	_screen_mat.emission_energy_multiplier = 0.5


func _process(delta: float) -> void:
	if not _busy:
		return
	_left = maxf(_left - delta, 0.0)
	_bar.scale.x = maxf(1.0 - _left / _total, 0.01)


func can_focus(_p) -> bool:
	return true


func get_prompt(p) -> String:
	if _busy:
		return "%s — в работе (%.1f с)" % [title, _left]
	var h = Game.held_item_of(p.peer_id)
	if h == null:
		return "%s — принеси тикет из лотка" % title
	if h.kind == "ticket_" + discipline:
		return "[E] Отдать в работу — %s" % title
	return "%s — нужен другой тикет" % title


func get_target() -> Array:
	return ["station", index]
