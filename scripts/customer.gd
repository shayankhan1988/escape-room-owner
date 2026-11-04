extends Node3D
## A customer. Walks along a queue of waypoints and wobbles while thinking.

var waypoints: Array[Vector3] = []
var speed := 1.8
var member: Dictionary = {}
var body: MeshInstance3D
var thinking := false
var t := 0.0

func setup(m: Dictionary) -> void:
	member = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(m.color)
	body = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.5
	body.mesh = cap
	body.position.y = 0.75
	body.material_override = mat
	add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	head.mesh = sph
	head.position.y = 1.68
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color("#f1c9a5")
	head.material_override = hm
	add_child(head)
	var lbl := Label3D.new()
	lbl.text = m.name + ("\n" + m.trait if m.trait != "" else "")
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 2.15
	lbl.font_size = 40
	lbl.pixel_size = 0.004
	lbl.outline_size = 8
	add_child(lbl)

func go(points: Array) -> void:
	waypoints.clear()
	for p in points:
		waypoints.append(p)

func is_idle() -> bool:
	return waypoints.is_empty()

func _process(dt: float) -> void:
	t += dt
	if waypoints.is_empty():
		body.rotation.z = sin(t * 3.0 + position.x) * (0.08 if thinking else 0.0)
		return
	body.rotation.z = 0
	var target: Vector3 = waypoints[0]
	var to := target - position
	to.y = 0
	if to.length() < 0.08:
		waypoints.remove_at(0)
		return
	var step := to.normalized() * speed * dt
	if step.length() > to.length():
		step = to
	position += step
	rotation.y = atan2(-to.x, -to.z) + PI
