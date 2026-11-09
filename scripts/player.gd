extends CharacterBody3D
## First-person controller: WASD to walk, mouse to look, E or left click to interact.

signal use_pressed(target)

const SPEED := 4.0
const SENS := 0.0025
const GRAVITY := 18.0

var cam: Camera3D
var ray: RayCast3D
var focus = null
var flashlight: SpotLight3D
var bob_t := 0.0

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	cam = Camera3D.new()
	cam.position.y = 1.6
	cam.fov = 75
	add_child(cam)
	cam.current = true
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color("#fff1d6")
	flashlight.light_energy = 3.0
	flashlight.spot_range = 14
	flashlight.spot_angle = 24
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.15, -0.15, 0)
	flashlight.visible = false
	cam.add_child(flashlight)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.4)
	ray.add_exception(self)
	cam.add_child(ray)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * SENS)
		cam.rotate_x(-e.relative.y * SENS)
		cam.rotation.x = clamp(cam.rotation.x, -1.4, 1.4)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			use_pressed.emit(focus)
	elif e.is_action_pressed("interact"):
		use_pressed.emit(focus)
	elif e.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(dt: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var v := (transform.basis * Vector3(dir.x, 0, dir.y)) * SPEED
	velocity.x = v.x
	velocity.z = v.z
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	else:
		velocity.y = 0
	move_and_slide()
	# gentle head bob while walking
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5 and is_on_floor()
	bob_t = bob_t + dt * 9.0 if moving else 0.0
	cam.position.y = lerp(cam.position.y, 1.6 + (sin(bob_t) * 0.035 if moving else 0.0), 0.3)
	focus = null
	if ray.is_colliding():
		var c = ray.get_collider()
		if c and c.has_method("use") and c.enabled:
			focus = c
