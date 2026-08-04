extends CharacterBody3D
## Персонаж. Собирается кодом, отдельная .tscn не нужна.

const SPEED := 5.5
const ACCEL := 14.0
const JUMP_FORCE := 6.5
const SENS := 0.0022
const NET_RATE := 1.0 / 20.0   # 20 пакетов в секунду

# задаётся из Boot ДО add_child
var peer_id := 1
var color := Color.WHITE
var spawn_pos := Vector3.ZERO

var is_local := false
var yaw := 0.0
var pitch := -0.25

var _pivot: Node3D
var _spring: SpringArm3D
var _cam: Camera3D
var _ray: RayCast3D
var _label: Label3D
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

	# «нос», чтобы видеть направление взгляда
	var nose := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.35)
	nose.mesh = bm
	nose.material_override = mat
	nose.position = Vector3(0, 0.45, -0.4)
	add_child(nose)

	_label = Label3D.new()
	_label.text = "P%d" % peer_id
	_label.position = Vector3(0, 1.35, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.006
	add_child(_label)


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

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, -0.35, -2.4)
	_ray.collide_with_areas = false
	_pivot.add_child(_ray)
	_ray.add_exception(self)


# ---------------------------------------------------------------- ВВОД

func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * SENS
		pitch = clampf(pitch - event.relative.y * SENS, -1.2, 0.5)
		if _spring:
			_spring.rotation.x = pitch
	if event.is_action_pressed("free_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- ЛОГИКА

func _physics_process(delta: float) -> void:
	if is_local:
		_local_step(delta)
		_net_timer -= delta
		if _net_timer <= 0.0 and multiplayer.has_multiplayer_peer():
			_net_timer = NET_RATE
			rpc("_push_state", global_position, yaw)
	else:
		global_position = global_position.lerp(_net_pos, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _net_yaw, clampf(delta * 12.0, 0.0, 1.0))


func _local_step(delta: float) -> void:
	rotation.y = yaw

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		velocity.y = JUMP_FORCE

	var input_dir := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target := dir * SPEED
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta * 4.0)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta * 4.0)

	move_and_slide()
	_check_focus()


func _check_focus() -> void:
	if _ray == null:
		return
	var hit: Node = null
	if _ray.is_colliding():
		var c: Node = _ray.get_collider() as Node
		if c != null and c.is_in_group("interactable"):
			hit = c
	if hit != _focus:
		_focus = hit
	if _focus and _focus.has_method("get_prompt"):
		Boot.set_prompt(_focus.get_prompt())
	else:
		Boot.set_prompt("")
	if _focus and Input.is_action_just_pressed("interact") and _focus.has_method("interact"):
		_focus.interact(self)


@rpc("any_peer", "unreliable_ordered")
func _push_state(pos: Vector3, y: float) -> void:
	_net_pos = pos
	_net_yaw = y
