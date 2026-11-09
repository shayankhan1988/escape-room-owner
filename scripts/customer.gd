extends Node3D
## A customer: a rigged Mixamo character that walks along waypoints and
## plays idle / walk / cheer / angry animations.

const MODEL := "res://assets/characters/person1/walking.fbx"
const ANIMS := {
	"walk": "res://assets/characters/person1/walking.fbx",
	"idle": "res://assets/characters/person1/idle.fbx",
	"cheer": "res://assets/characters/person1/cheering.fbx",
	"angry": "res://assets/characters/person1/angry.fbx",
}
const LOOPING := ["walk", "idle"]
const SHIRT_TINTS := ["#ffffff", "#c9d6ff", "#ffd1c9", "#d6ffc9", "#e0c9ff", "#8a8a8a", "#ffe9a8"]
const PANTS_TINTS := ["#ffffff", "#7d8aa8", "#5c4a3a", "#3a3a3a", "#a89a7d"]

# Shared between all customers so the FBX files load only once.
static var _library: AnimationLibrary
static var _model_scene: PackedScene
static var _model_height := 0.0

var waypoints: Array[Vector3] = []
var speed := 1.3
var member: Dictionary = {}
var thinking := false
var leave_when_done := false
var face = null        # point to turn towards while standing still
var mood := ""          # "", "cheer" or "angry" once the session ends
var anim: AnimationPlayer
var current := ""
var rng := RandomNumberGenerator.new()

static func _prepare() -> void:
	if _library:
		return
	_model_scene = load(MODEL)
	_library = AnimationLibrary.new()
	for key in ANIMS:
		var scene: Node = load(ANIMS[key]).instantiate()
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var a: Animation = ap.get_animation("mixamo_com").duplicate(true)
		a.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
		_strip_root_motion(a)
		_library.add_animation(key, a)
		scene.free()
	# measure the model so it can be scaled to a real human height
	var probe: Node3D = _model_scene.instantiate()
	var top := 0.0
	for mi in probe.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = mi.get_aabb()
		top = max(top, bb.position.y + bb.size.y)
	_model_height = top
	probe.free()

# The game moves customers itself, so keep the hips from drifting forward.
static func _strip_root_motion(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t)).ends_with("Hips"):
			if a.track_get_key_count(t) == 0:
				return
			var first: Vector3 = a.track_get_key_value(t, 0)
			for k in a.track_get_key_count(t):
				var v: Vector3 = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))

func setup(m: Dictionary) -> void:
	member = m
	rng.randomize()
	_prepare()
	var model: Node3D = _model_scene.instantiate()
	var height := rng.randf_range(1.62, 1.88)
	if _model_height > 0.0:
		model.scale = Vector3.ONE * (height / _model_height)
	add_child(model)
	# give each customer different clothing colors
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var tint := ""
		if mi.name == "Tops":
			tint = SHIRT_TINTS[rng.randi() % SHIRT_TINTS.size()]
		elif mi.name == "Bottoms":
			tint = PANTS_TINTS[rng.randi() % PANTS_TINTS.size()]
		if tint != "":
			for s in mi.get_surface_override_material_count():
				var base = mi.mesh.surface_get_material(s)
				if base is BaseMaterial3D:
					var mat: BaseMaterial3D = base.duplicate()
					mat.albedo_color = Color(tint)
					mi.set_surface_override_material(s, mat)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	anim.add_animation_library("crowd", _library)
	_play("idle")
	var lbl := Label3D.new()
	lbl.text = m.name + ("\n" + m.trait if m.trait != "" else "")
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = height + 0.3
	lbl.font_size = 32
	lbl.pixel_size = 0.004
	lbl.outline_size = 8
	lbl.modulate = Color(m.color)
	lbl.visibility_range_end = 7.0
	add_child(lbl)

func _play(anim_name: String) -> void:
	if current == anim_name:
		return
	current = anim_name
	anim.play("crowd/" + anim_name, 0.25)
	# small random offset so a group does not move in perfect sync
	if anim_name in LOOPING:
		anim.seek(rng.randf() * anim.current_animation_length, true)

func go(points: Array) -> void:
	waypoints.clear()
	for p in points:
		waypoints.append(p)

func is_idle() -> bool:
	return waypoints.is_empty()

func _process(dt: float) -> void:
	if waypoints.is_empty():
		if leave_when_done:
			queue_free()
			return
		_play(mood if mood != "" else "idle")
		if face != null:
			var d: Vector3 = face - position
			rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), min(1.0, dt * 5.0))
		return
	var target: Vector3 = waypoints[0]
	var to := target - position
	to.y = 0
	if to.length() < 0.08:
		waypoints.remove_at(0)
		return
	_play("walk")
	var step := to.normalized() * speed * dt
	if step.length() > to.length():
		step = to
	position += step
	# Mixamo characters face +Z
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), min(1.0, dt * 8.0))
