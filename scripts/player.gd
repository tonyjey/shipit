extends CharacterBody3D
## Персонаж. Собирается кодом, отдельная .tscn не нужна.

const SPEED := 5.5
const ACCEL := 14.0
const JUMP_FORCE := 6.5
const SENS := 0.0022
const NET_RATE := 1.0 / 20.0

const REACH := 2.7        # радиус взаимодействия
const MIN_DOT := 0.25     # насколько нужно смотреть на объект

# задаётся из Boot ДО add_child
var peer_id := 1
var slot := 1
var color := Color.WHITE
var spawn_pos := Vector3.ZERO

var is_local := false
var yaw := 0.0
var pitch := -0.25

var _pivot: Node3D
var _spring: SpringArm3D
var _cam: Camera3D
var _gravity := 18.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_timer := 0.0
var _focus: Node = null


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0))
	is_local = (peer_id == Boot.local_id())
	global_position = spawn_pos
	_net_pos = spawn_pos
	_build_body()
	if is_local:
		_build_camera()


# ---------------------------------------------------------------- СБОРКА

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.4
	caps.height = 1.7
	shape.shape = caps
	add_child(shape)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color

	var mesh := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.7
	mesh.mesh = cm
	mesh.material_override = mat
	add_child(mesh)

	var nose := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.35)
	nose.mesh = bm
	nose.material_override = mat
	nose.position = Vector3(0, 0.45, -0.4)
	add_child(nose)

	var label := Label3D.new()
	label.text = "P%d" % slot
	label.position = Vector3(0, 1.35, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.006
	label.outline_size = 10
	add_child(label)


func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.3, 0)
	add_child(_pivot)

	_spring = SpringArm3D.new()
	_spring.spring_length = 3.6
	_spring.rotation.x = pitch
	_pivot.add_child(_spring)

	_cam = Camera3D.new()
	_cam.position = Vector3(0.5, 0, 0)
	_cam.current = true
	_spring.add_child(_cam)


# ---------------------------------------------------------------- ВВОД

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or Game.is_local_busy():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * SENS
		pitch = clampf(pitch - event.relative.y * SENS, -1.2, 0.5)
		if _spring:
			_spring.rotation.x = pitch
	if event.is_action_pressed("free_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("interact"):
		_do_interact()
	if event.is_action_pressed("drop"):
		Game.request_drop()


func _do_interact() -> void:
	if _focus == null or not _focus.has_method("get_target"):
		return
	var t: Array = _focus.get_target()
	Game.request_interact(String(t[0]), int(t[1]))


# ---------------------------------------------------------------- ЛОГИКА

func _physics_process(delta: float) -> void:
	if is_local:
		_local_step(delta)
		_net_timer -= delta
		if _net_timer <= 0.0 and multiplayer.has_multiplayer_peer():
			_net_timer = NET_RATE
			var me := multiplayer.get_unique_id()
			for pid in Boot.ready_peers:
				if int(pid) != me:
					rpc_id(int(pid), "_push_state", global_position, yaw)
	else:
		var t := clampf(delta * 12.0, 0.0, 1.0)
		global_position = global_position.lerp(_net_pos, t)
		rotation.y = lerp_angle(rotation.y, _net_yaw, t)


func _local_step(delta: float) -> void:
	rotation.y = yaw

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Game.is_local_busy():
		velocity.y = JUMP_FORCE

	var input_dir := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Game.is_local_busy():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target := dir * SPEED
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta * 4.0)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta * 4.0)

	move_and_slide()
	if Game.is_local_busy():
		if Boot.terminal and Boot.terminal.active:
			Boot.set_prompt("Идёт работа — печатай токены.   Esc — отойти")
		else:
			Boot.set_prompt("")
		Boot.set_hint("")
		_focus = null
		return
	else:
		_update_focus()


## Выбор цели по близости и направлению взгляда — надёжнее луча
## и привычнее для игр в духе Overcooked.
func _update_focus() -> void:
	var best: Node = null
	var best_score := -1e9
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	for n in get_tree().get_nodes_in_group("interactable"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var n3 = n
		if n3.has_method("can_focus") and not n3.can_focus(self):
			continue
		var to: Vector3 = n3.global_position - global_position
		to.y = 0.0
		var d: float = to.length()
		if d > REACH:
			continue
		var dot: float = 1.0
		if d > 0.05:
			dot = fwd.dot(to / d)
		if dot < MIN_DOT:
			continue
		var score: float = dot * 2.0 - d * 0.5
		if score > best_score:
			best_score = score
			best = n3

	_focus = best
	if _focus and _focus.has_method("get_prompt"):
		Boot.set_prompt(_focus.get_prompt(self))
	else:
		Boot.set_prompt("")

	var held = Game.held_item_of(peer_id)
	if held != null:
		Boot.set_hint("В руках: %s     [Q] бросить" % Game.title_of(held.kind))
	else:
		Boot.set_hint("")


@rpc("any_peer", "unreliable_ordered")
func _push_state(pos: Vector3, y: float) -> void:
	_net_pos = pos
	_net_yaw = y
