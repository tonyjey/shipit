extends StaticBody3D
## Сборочная машина: дупликатор дискет. Сюда несут готовые ассеты.
##
## Вся индикация живёт на самой модели: счётчик на двух табло,
## пять ламп прогресса по контракту и мигающие светодиоды дисководов.
## Текст, висящий в воздухе, больше не нужен.

const MODEL := "res://models/assembler.glb"

var _displays: Array = []          # Label3D на переднем и заднем табло
var _lamps: Array = []             # материалы ламп прогресса
var _drive_leds: Array = []        # материалы светодиодов дисководов
var _screen_mat: StandardMaterial3D
var _flash := 0.0
var _drive_flash := 0.0
var _drive_index := 0


func _ready() -> void:
	add_to_group("interactable")
	_build()
	set_count(0, 1.0)


func _build() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.26, 1.4, 1.62)
	cs.shape = bs
	cs.position = Vector3(0, 0.7, -0.08)
	add_child(cs)

	var ps = load(MODEL)
	if ps == null:
		_build_fallback()
		return

	var model: Node3D = ps.instantiate()
	add_child(model)
	for junk in model.find_children("*", "Camera3D", true, false):
		junk.queue_free()
	for junk in model.find_children("*", "Light3D", true, false):
		junk.queue_free()

	# табло светятся, пока идёт контракт
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.06, 0.14, 0.10)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0.35, 1.0, 0.55)
	_screen_mat.emission_energy_multiplier = 0.35

	for side in [["Display_Front", -0.755, 180.0], ["Display_Back", 0.755, 0.0]]:
		var found := model.find_children(String(side[0]), "MeshInstance3D", true, false)
		if not found.is_empty():
			(found[0] as MeshInstance3D).set_surface_override_material(0, _screen_mat)
		var l := Label3D.new()
		l.position = Vector3(0, 0.86, float(side[1]))
		l.rotation_degrees = Vector3(0, float(side[2]), 0)
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.double_sided = false
		l.pixel_size = 0.0030
		l.outline_size = 6
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)
		_displays.append(l)

	for i in 5:
		var lamp := model.find_children("Lamp_%02d" % (i + 1), "MeshInstance3D", true, false)
		if lamp.is_empty():
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.18, 0.20, 0.18)
		m.emission_enabled = true
		m.emission = Color(0.35, 1.0, 0.45)
		m.emission_energy_multiplier = 0.0
		(lamp[0] as MeshInstance3D).set_surface_override_material(0, m)
		_lamps.append(m)

	for i in 5:
		var led := model.find_children("Drive_%02d_LED" % (i + 1), "MeshInstance3D", true, false)
		if led.is_empty():
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.10, 0.10)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.35)
		m.emission_energy_multiplier = 0.0
		(led[0] as MeshInstance3D).set_surface_override_material(0, m)
		_drive_leds.append(m)


func _build_fallback() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.38, 0.45)
	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(2.2, 1.4, 1.4)
	hull.mesh = hm
	hull.material_override = mat
	hull.position = Vector3(0, 0.7, 0)
	add_child(hull)
	var l := Label3D.new()
	l.position = Vector3(0, 1.6, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.006
	add_child(l)
	_displays.append(l)


## Счётчик сданного и качество. Лампы показывают готовность контракта.
func set_count(n: int, avg_quality := 1.0) -> void:
	# После релиза контракт ещё лежит в памяти — ориентируемся на то,
	# идёт ли он сейчас, иначе табло продолжало показывать старый счёт.
	var need := 0
	if Game.contract_running and not Game.contract.is_empty():
		for k in Game.contract["need"].keys():
			need += int(Game.contract["need"][k])

	var head := "СБОРКА"
	var line := "ждём контракт"
	var ratio := 0.0
	if need > 0:
		# строка короткая намеренно: панель всего 0.9 м шириной
		line = "%d / %d   ·   %d%%" % [n, need, int(round(avg_quality * 100.0))]
		ratio = clampf(float(n) / float(need), 0.0, 1.0)
	for l in _displays:
		l.text = "%s\n%s" % [head, line]

	for i in _lamps.size():
		var on := ratio >= float(i + 1) / float(_lamps.size())
		_lamps[i].emission_energy_multiplier = 2.2 if on else 0.0

	if _screen_mat:
		_screen_mat.emission_energy_multiplier = 0.9 if need > 0 else 0.25

	if n > 0:
		_flash = 0.6
		_drive_flash = 0.5
		_drive_index = (n - 1) % maxi(_drive_leds.size(), 1)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _screen_mat:
			_screen_mat.emission_energy_multiplier = 2.4
	if _drive_flash > 0.0:
		_drive_flash -= delta
		for i in _drive_leds.size():
			_drive_leds[i].emission_energy_multiplier = 2.5 if i == _drive_index else 0.0
	else:
		for m in _drive_leds:
			m.emission_energy_multiplier = 0.0


func can_focus(_p) -> bool:
	return true


func get_prompt(p) -> String:
	var h = Game.held_of_kind(p.peer_id, "asset_")
	if h != null and String(h.kind).begins_with("asset_"):
		return "[E] Сдать в сборку — %s" % Game.title_of(h.kind)
	if Game.contract_running and Game.requirements_met():
		return "[E] СДАТЬ ИГРУ ИЗДАТЕЛЮ — всё готово досрочно"
	return "Сборка — неси готовый ассет со стола"


func get_target() -> Array:
	return ["assembler", 0]
