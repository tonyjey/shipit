extends StaticBody3D

const PC_MODEL := "res://models/pc.glb"
## Рабочее место. Пока превращает тикет в ассет по таймеру.
## На Фазе 2 таймер заменится на мини-игру.

var index := 0
var discipline := "code"
var title := "Код"
var color := Color.WHITE

var _total := 0
var _done := 0
var _bar: MeshInstance3D
var _screen_mat: StandardMaterial3D
var _power_mat: StandardMaterial3D


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

	_build_computer()

	var label := Label3D.new()
	label.text = title
	label.position = Vector3(0, 1.66, -0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.double_sided = false
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
	bm.size = Vector3(0.42, 0.055, 0.055)
	_bar.mesh = bm
	_bar.material_override = bar_mat
	_bar.position = Vector3(0, 1.47, -0.06)
	_bar.visible = false
	add_child(_bar)


## Ставим на стол модель компьютера. Экран красим в цвет дисциплины —
## иначе три одинаковых ПК невозможно различить с другого конца офиса.
func _build_computer() -> void:
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = color * 0.55
	_screen_mat.emission_enabled = true
	_screen_mat.emission = color
	_screen_mat.emission_energy_multiplier = 0.6

	var ps = load(PC_MODEL)
	if ps == null:
		_build_fallback_screen()
		return

	var pc: Node3D = ps.instantiate()
	pc.scale = Vector3(0.01, 0.01, 0.01)
	pc.rotation_degrees = Vector3(0, 180, 0)   # монитор и клавиатура лицом к игроку
	pc.position = Vector3(0, 0.845, -0.15)
	add_child(pc)

	# камеры и источники света из редактора модели в игре не нужны
	for junk in pc.find_children("*", "Camera3D", true, false):
		junk.queue_free()
	for junk in pc.find_children("*", "Light3D", true, false):
		junk.queue_free()

	var screens := pc.find_children("Screen_Surface", "MeshInstance3D", true, false)
	if screens.is_empty():
		_build_fallback_screen()
		return
	(screens[0] as MeshInstance3D).set_surface_override_material(0, _screen_mat)

	var buttons := pc.find_children("PowerButton", "MeshInstance3D", true, false)
	if not buttons.is_empty():
		_power_mat = StandardMaterial3D.new()
		_power_mat.albedo_color = Color(0.25, 0.25, 0.23)
		_power_mat.emission_enabled = true
		_power_mat.emission = Color(0.3, 1.0, 0.4)
		_power_mat.emission_energy_multiplier = 0.0
		(buttons[0] as MeshInstance3D).set_surface_override_material(0, _power_mat)


func _build_fallback_screen() -> void:
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.9, 0.55, 0.06)
	screen.mesh = sm
	screen.material_override = _screen_mat
	screen.position = Vector3(0, 1.2, -0.15)
	add_child(screen)


func output_position() -> Vector3:
	return global_position + Vector3(0, 0.98, 0.32)


func set_work(total: int, done: int) -> void:
	_total = maxi(total, 1)
	_done = done
	_bar.visible = true
	_bar.scale.x = maxf(float(_done) / float(_total), 0.02)
	_screen_mat.emission_energy_multiplier = 1.6
	if _power_mat:
		_power_mat.emission_energy_multiplier = 1.4


func clear_work() -> void:
	_total = 0
	_done = 0
	_bar.visible = false
	_screen_mat.emission_energy_multiplier = 0.6
	if _power_mat:
		_power_mat.emission_energy_multiplier = 0.0


func can_focus(_p) -> bool:
	return true


func get_prompt(p) -> String:
	if Game.work.has(index):
		var w: Dictionary = Game.work[index]
		var occ := int(w["occupant"])
		var toks: Array = w["tokens"]
		if occ == 0:
			return "[E] Продолжить работу — %s (%d/%d)" % [title, int(w["done"]), toks.size()]
		if occ == int(p.peer_id):
			return "%s — ты работаешь здесь" % title
		return "%s — занято игроком P%d" % [title, int(Boot.slots.get(occ, occ))]
	var h = Game.held_item_of(p.peer_id)
	if h == null:
		return "%s — принеси тикет из лотка" % title
	if String(h.kind) == "ticket_" + discipline:
		return "[E] Сесть за работу — %s" % title
	return "%s — нужен другой тикет" % title


func get_target() -> Array:
	return ["station", index]
