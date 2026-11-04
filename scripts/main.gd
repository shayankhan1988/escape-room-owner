extends Node3D
## Escape Room Owner — graybox vertical slice.
## Builds the venue in code (lobby, control room, one escape room), runs the
## customer simulation, the CCTV monitor, hints, reviews, cash and the reset.

const Interactable := preload("res://scripts/interactable.gd")
const Player := preload("res://scripts/player.gd")
const Customer := preload("res://scripts/customer.gd")

const SAVE_PATH := "user://save.json"
const GROUPS_PER_DAY := 4
const TICKET := 25
const REPAIR_COST := 20
const SECONDS_PER_MINUTE := 0.9

const PUZ := {
	"padlock": {"name": "Padlock Box", "diff": 1, "fun": 1, "cost": 0, "brk": 0.08, "color": "#9aa4ad"},
	"books": {"name": "Secret Bookshelf", "diff": 2, "fun": 2, "cost": 120, "brk": 0.06, "color": "#8b5a2b"},
	"cipher": {"name": "Cipher Wheel", "diff": 3, "fun": 2, "cost": 220, "brk": 0.04, "color": "#c9a227"},
	"uv": {"name": "UV Wall Message", "diff": 2, "fun": 3, "cost": 300, "brk": 0.05, "color": "#7b4dff"},
	"skeleton": {"name": "Jump-Scare Skeleton", "diff": 1, "fun": 4, "cost": 380, "brk": 0.3, "color": "#e8e4d8", "scare": true},
	"safe": {"name": "Final Safe", "diff": 3, "fun": 3, "cost": 450, "brk": 0.05, "color": "#3d4a57"},
	"piano": {"name": "Haunted Piano", "diff": 3, "fun": 4, "cost": 700, "brk": 0.12, "color": "#1d1d1d"},
	"laser": {"name": "Laser Hallway", "diff": 4, "fun": 5, "cost": 950, "brk": 0.25, "color": "#ff3b3b"},
}
const PUZ_ORDER := ["padlock", "books", "cipher", "uv", "skeleton", "safe", "piano", "laser"]
const NAMES := ["Dave", "Priya", "Tom", "Lena", "Bas", "Mo", "Sophie", "Kai", "Noor", "Frank", "Yuki", "Greg", "Ines", "Omar", "Fleur", "Rick", "Zoe", "Ahmed", "Tess", "Hugo"]
const TRAITS := [
	{"id": "Smart", "p": 0.25, "color": "#5fd38d"},
	{"id": "Clumsy", "p": 0.25, "color": "#ff8a5c"},
	{"id": "Impatient", "p": 0.18, "color": "#ff4d4d"},
	{"id": "Influencer", "p": 0.12, "color": "#c58bff"},
	{"id": "Screamer", "p": 0.15, "color": "#ffd23e"},
]
const WEIRD := [
	["{n} is trying to open the padlock with their teeth.", "Tooth marks"],
	["{n} ordered a pizza to the room. The driver is very confused.", "Pizza box"],
	["{n} is convinced the fire extinguisher is a clue.", "Foam puddle"],
	["{n} tried to climb into the air vent.", "Lost shoe"],
	["{n} licked the UV lamp. Nobody asked them to.", "Smudged lamp"],
	["{n} is asking the camera for a hint. Directly. Staring at you.", ""],
	["{n} found a clue you never put there. It is a receipt from 2014.", "Mystery receipt"],
	["{n} is filming a video for their 14 followers.", ""],
	["{n} took a nap in the corner.", "Drool spot"],
	["{n} is solving the wrong puzzle with great confidence.", ""],
	["{n} spilled an entire energy drink.", "Sticky floor"],
	["{n} tried to unscrew the door hinges.", "Loose screws"],
]
const AFTER_MESS := ["Scattered clues", "Moved chair", "Open drawer", "Lost scarf", "Fingerprints", "Unlocked padlock"]
const QUOTES := {
	5: ["Best hour of my life. We escaped with seconds left!", "My heart is still racing. Booking again.", "Perfect difficulty. I felt like a genius."],
	4: ["Really fun, a bit easy at the end.", "Great puzzles. Someone licked a lamp though.", "Solid room, would recommend."],
	3: ["Fine, but we escaped way too fast.", "Felt like a waiting room with locks.", "It was a room. We escaped it."],
	2: ["We did not escape and I am still angry.", "Too hard, and the hints were useless.", "The skeleton owes me an apology."],
	1: ["Worst Saturday ever.", "I want my money back AND my shoe."],
}
const HINTS := ["You: \"Have you tried looking UNDER things?\"", "You: \"The answer is closer than you think.\"", "You: \"Please stop licking the lamp. Also, check the books.\"", "You: \"Count the candles.\""]

# Escape room slots: pedestal position and where customers stand to work on it.
const SLOT_POS := [Vector3(1.6, 0, 11), Vector3(1.6, 0, 15), Vector3(1.6, 0, 18.6), Vector3(14.4, 0, 18.6), Vector3(14.4, 0, 15), Vector3(14.4, 0, 11)]
const ROOM_DOOR := Vector3(4.75, 0, 8.0)
const LOBBY_EXIT := Vector3(4.75, 0, 1.0)

# --- persistent state ---
var S := {}
# --- runtime state ---
var phase := "lobby"   # lobby | session | review | reset
var group := {}
var customers: Array = []
var minute := 0
var sim_timer := 0.0
var speed := 1
var mess_nodes: Array = []
var log_lines: Array = []

# --- nodes ---
var player
var door_body: StaticBody3D
var slot_nodes: Array = []   # each: {body, prop, label}
var start_btn
var hint_btn
var speed_btn
var hint_light: OmniLight3D
var monitor_label: Label3D
var hud_stats: Label
var hud_phase: Label
var hud_prompt: Label
var hud_log: Label
var review_panel: PanelContainer
var review_label: Label
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_setup_input()
	_load()
	_build_environment()
	_build_venue()
	_build_slots()
	_build_control_room()
	_build_hud()
	player = Player.new()
	player.position = Vector3(13, 0.1, 2.5)
	player.rotation.y = PI
	add_child(player)
	player.use_pressed.connect(_on_use)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_log("You bought a failing escape room with your savings. The previous owner left a note: \"Good luck.\"")
	_set_door(false)
	_new_group()
	_refresh_all()

# ---------------------------------------------------------------- input
func _setup_input() -> void:
	var keys := {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "interact": [KEY_E], "speed": [KEY_TAB]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("speed") and phase == "session":
		_cycle_speed()

# ---------------------------------------------------------------- building helpers
func _mat(color: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.85
	return m

func box(pos: Vector3, size: Vector3, color: String, collide := true, parent: Node = self) -> Node3D:
	var root: Node3D = StaticBody3D.new() if collide else Node3D.new()
	root.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	root.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		root.add_child(cs)
	parent.add_child(root)
	return root

func interactable(pos: Vector3, size: Vector3, color: String, prompt: String, cb: Callable):
	var b = Interactable.new()
	b.position = pos
	b.prompt = prompt
	b.on_use = cb
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.name = "Mesh"
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	return b

func label3d(text: String, pos: Vector3, size := 64, color := Color.WHITE, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 10
	l.modulate = color
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	return l

# Wall along X (at fixed z) from x0 to x1, with optional gap [g0, g1].
func wall_x(z: float, x0: float, x1: float, color: String, gap := Vector2(-1, -1)) -> void:
	if gap.x < 0:
		box(Vector3((x0 + x1) / 2, 1.5, z), Vector3(x1 - x0, 3, 0.2), color)
	else:
		box(Vector3((x0 + gap.x) / 2, 1.5, z), Vector3(gap.x - x0, 3, 0.2), color)
		box(Vector3((gap.y + x1) / 2, 1.5, z), Vector3(x1 - gap.y, 3, 0.2), color)
		box(Vector3((gap.x + gap.y) / 2, 2.6, z), Vector3(gap.y - gap.x, 0.8, 0.2), color)

func wall_z(x: float, z0: float, z1: float, color: String, gap := Vector2(-1, -1)) -> void:
	if gap.x < 0:
		box(Vector3(x, 1.5, (z0 + z1) / 2), Vector3(0.2, 3, z1 - z0), color)
	else:
		box(Vector3(x, 1.5, (z0 + gap.x) / 2), Vector3(0.2, 3, gap.x - z0), color)
		box(Vector3(x, 1.5, (gap.y + z1) / 2), Vector3(0.2, 3, z1 - gap.y), color)
		box(Vector3(x, 2.6, (gap.x + gap.y) / 2), Vector3(0.2, 0.8, gap.y - gap.x), color)

# ---------------------------------------------------------------- world
func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#20262d")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#c8d0d8")
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 35, 0)
	sun.light_energy = 0.4
	sun.shadow_enabled = true
	add_child(sun)
	for p in [Vector3(5, 2.8, 4), Vector3(13, 2.8, 4), Vector3(5, 2.8, 14), Vector3(11, 2.8, 14)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 9
		l.light_energy = 0.45
		add_child(l)

func _build_venue() -> void:
	# floors
	box(Vector3(5, -0.05, 4), Vector3(10, 0.1, 8), "#4f5e69")       # lobby
	box(Vector3(13, -0.05, 4), Vector3(6, 0.1, 8), "#4a5560")       # control room
	box(Vector3(8, -0.05, 14), Vector3(16, 0.1, 12), "#5b4636")     # escape room (wood)
	# outer walls
	wall_x(0, 0, 16, "#8e9aa4")
	wall_x(20, 0, 16, "#3b2e3a")
	wall_z(0, 0, 8, "#8e9aa4")
	wall_z(16, 0, 8, "#8e9aa4")
	wall_z(0, 8, 20, "#3b2e3a")
	wall_z(16, 8, 20, "#3b2e3a")
	# interior walls
	wall_z(10, 0, 8, "#7f8b95", Vector2(3, 4.5))                    # lobby | control room
	wall_x(8, 0, 16, "#3b2e3a", Vector2(4, 5.5))                    # lobby/control | escape room
	# escape room door (removed when unlocked)
	door_body = box(Vector3(4.75, 1.1, 8), Vector3(1.5, 2.2, 0.15), "#a3392b") as StaticBody3D
	# lobby props
	box(Vector3(7.5, 0.55, 2.0), Vector3(3, 1.1, 0.8), "#2d3640")   # reception desk
	box(Vector3(1.2, 0.25, 6.5), Vector3(2, 0.5, 0.7), "#55606b")   # bench
	label3d("LOBBY", Vector3(5, 2.6, 0.2), 96, Color("#ffb23e"), false)
	label3d("CONTROL ROOM", Vector3(10.1, 2.6, 3.75), 56, Color("#ffb23e"), false).rotation.y = PI / 2
	var room_sign := label3d("THE STUDY", Vector3(4.75, 2.6, 7.88), 72, Color("#ffb23e"), false)
	room_sign.rotation.y = PI
	# escape room decor
	box(Vector3(8, 0.4, 14.5), Vector3(2.4, 0.8, 1.4), "#6b4a2f")   # big table
	box(Vector3(8, 1.6, 19.85), Vector3(1.2, 1.6, 0.1), "#c9b27c", false)  # painting
	box(Vector3(8, 0.03, 9.2), Vector3(1.2, 0.05, 0.6), "#2fbf71", false)  # exit marker
	label3d("EXIT", Vector3(4.75, 2.3, 8.15), 48, Color("#2fbf71"), false)

func _build_slots() -> void:
	for i in SLOT_POS.size():
		var pos: Vector3 = SLOT_POS[i]
		var b = interactable(pos + Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9), "#3a3f45", "", _on_slot.bind(i))
		var prop := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.6, 0.6)
		prop.mesh = bm
		prop.position = Vector3(0, 0.8, 0)
		b.add_child(prop)
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 1.75, 0)
		lbl.font_size = 44
		lbl.pixel_size = 0.005
		lbl.outline_size = 10
		b.add_child(lbl)
		slot_nodes.append({"body": b, "prop": prop, "label": lbl})

func _build_control_room() -> void:
	box(Vector3(13, 0.5, 6.9), Vector3(4.5, 1.0, 1.2), "#2a2f36")    # desk
	# CCTV camera inside the escape room, rendered to a monitor in the control room
	var sv := SubViewport.new()
	sv.size = Vector2i(640, 360)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cctv := Camera3D.new()
	cctv.fov = 80
	sv.add_child(cctv)
	cctv.position = Vector3(15.6, 2.9, 8.4)
	cctv.look_at(Vector3(7.5, 0, 15.5), Vector3.UP)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 1.35)
	screen.mesh = q
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = sv.get_texture()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = sm
	screen.position = Vector3(13, 1.9, 7.85)
	screen.rotation.y = PI
	add_child(screen)
	box(Vector3(13, 1.9, 7.9), Vector3(2.55, 1.5, 0.05), "#111111", false)
	monitor_label = label3d("CAM 01  REC", Vector3(13, 2.75, 7.8), 40, Color("#ff4d4d"), false)
	monitor_label.rotation.y = PI
	# buttons on the desk
	start_btn = interactable(Vector3(11.6, 1.08, 6.6), Vector3(0.5, 0.16, 0.5), "#2fbf71", "", _on_start)
	label3d("OPEN ROOM", Vector3(11.6, 1.4, 6.6), 32, Color("#2fbf71"))
	hint_btn = interactable(Vector3(13, 1.08, 6.6), Vector3(0.5, 0.16, 0.5), "#ff4d4d", "", _on_hint)
	label3d("INTERCOM", Vector3(13, 1.4, 6.6), 32, Color("#ff4d4d"))
	speed_btn = interactable(Vector3(14.4, 1.08, 6.6), Vector3(0.5, 0.16, 0.5), "#ffb23e", "", _cycle_speed)
	label3d("SPEED", Vector3(14.4, 1.4, 6.6), 32, Color("#ffb23e"))
	hint_light = OmniLight3D.new()
	hint_light.position = Vector3(13, 1.5, 6.6)
	hint_light.light_color = Color("#ff4d4d")
	hint_light.omni_range = 3
	hint_light.light_energy = 0
	add_child(hint_light)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 26)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -7
	cross.offset_top = -18
	layer.add_child(cross)
	hud_stats = _hud_label(layer, Vector2(20, 16), 22)
	hud_phase = _hud_label(layer, Vector2(20, 50), 17)
	hud_phase.size = Vector2(520, 80)
	hud_phase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_log = _hud_label(layer, Vector2(0, 16), 15)
	hud_log.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud_log.offset_left = -440
	hud_log.offset_right = -20
	hud_log.offset_top = 16
	hud_log.offset_bottom = 300
	hud_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_prompt = _hud_label(layer, Vector2(0, 0), 20)
	hud_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hud_prompt.offset_left = -400
	hud_prompt.offset_right = 400
	hud_prompt.offset_top = -100
	hud_prompt.offset_bottom = -60
	hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	review_panel = PanelContainer.new()
	review_panel.set_anchors_preset(Control.PRESET_CENTER)
	review_panel.offset_left = -230
	review_panel.offset_top = -170
	review_panel.custom_minimum_size = Vector2(460, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#f4f1e8")
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(22)
	review_panel.add_theme_stylebox_override("panel", sb)
	review_label = Label.new()
	review_label.add_theme_color_override("font_color", Color("#1b1b1b"))
	review_label.add_theme_font_size_override("font_size", 18)
	review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	review_label.custom_minimum_size = Vector2(416, 0)
	review_panel.add_child(review_label)
	review_panel.visible = false
	layer.add_child(review_panel)

func _hud_label(layer: CanvasLayer, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	layer.add_child(l)
	return l

# ---------------------------------------------------------------- save / load
func _fresh() -> Dictionary:
	return {"day": 1, "gi": 0, "cash": 150, "ratings": [], "slots": ["padlock", "books", "padlock", "", "", ""], "owned": {"padlock": 2, "books": 1}, "broken": []}

func _load() -> void:
	S = _fresh()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				S[k] = d[k]
	# JSON numbers come back as floats
	var b: Array = []
	for x in S.broken:
		b.append(int(x))
	S.broken = b

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(S))

# ---------------------------------------------------------------- helpers
func chain() -> Array:
	var out: Array = []
	for i in S.slots.size():
		if S.slots[i] != "":
			out.append(i)
	return out

func trait_count(t: String) -> int:
	var n := 0
	for m in group.members:
		if m.trait == t:
			n += 1
	return n

func need(id: String) -> float:
	return 16.0 * PUZ[id].diff

func owned_free(id: String) -> bool:
	var used := 0
	for s in S.slots:
		if s == id:
			used += 1
	return int(S.owned.get(id, 0)) > used

func avg_rating() -> String:
	var r: Array = S.ratings.slice(max(0, S.ratings.size() - 12))
	if r.is_empty():
		return "-"
	var t := 0.0
	for x in r:
		t += x
	return "%.1f" % (t / r.size())

func add_log(t: String) -> void:
	var stamp: String = "%02d:00 " % (60 - minute) if phase == "session" else ""
	log_lines.push_front(stamp + t)
	if log_lines.size() > 7:
		log_lines.pop_back()
	if hud_log:
		hud_log.text = "CAMERA LOG\n" + "\n".join(log_lines)

func pick(a: Array):
	return a[rng.randi() % a.size()]

# ---------------------------------------------------------------- groups
func _new_group() -> void:
	var n := rng.randi_range(2, 5)
	var used := {}
	var members: Array = []
	for i in n:
		var nm: String = pick(NAMES)
		while used.has(nm):
			nm = pick(NAMES)
		used[nm] = true
		var r := rng.randf()
		var tr := {"id": "", "color": "#cfd6dc"}
		for t in TRAITS:
			if r < t.p:
				tr = t
				break
			r -= t.p
		members.append({"name": nm, "trait": tr.id, "color": tr.color})
	group = {"members": members, "at": 0, "prog": 0.0, "stuck": 0, "hints": 0, "hint_req": false, "boost": false,
		"escaped": false, "max_stuck": 0, "scares": 0, "fun": 0, "solved": 0, "mess": []}
	for c in customers:
		c.queue_free()
	customers.clear()
	for i in members.size():
		var c = Customer.new()
		c.setup(members[i])
		c.position = Vector3(1.0 + i * 0.9, 0, 4.5)
		add_child(c)
		customers.append(c)
	add_log("A group of %d is waiting in the lobby: %s." % [n, ", ".join(members.map(func(m): return m.name))])

func _send_group_to_slot(ci: int) -> void:
	var slot: int = chain()[ci]
	var p: Vector3 = SLOT_POS[slot]
	var inward: float = 1.4 if p.x < 8 else -1.4
	for i in customers.size():
		var off := Vector3(inward + (i % 2) * inward * 0.6, 0, (i - customers.size() / 2.0) * 0.6)
		customers[i].go([p + off])
		customers[i].thinking = true

# ---------------------------------------------------------------- interactions
func _on_use(target) -> void:
	if phase == "review":
		_begin_reset()
		return
	if target:
		target.use()
		_refresh_all()

func _on_slot(i: int) -> void:
	match phase:
		"lobby":
			# cycle to the next puzzle type (or empty), buying it if needed
			var cur: String = S.slots[i]
			var idx := PUZ_ORDER.find(cur)
			var nxt: String = "" if idx == PUZ_ORDER.size() - 1 else PUZ_ORDER[idx + 1]
			if nxt != "" and not owned_free(nxt) and S.cash < PUZ[nxt].cost:
				# skip unaffordable puzzles
				var j := idx + 1
				while j < PUZ_ORDER.size() and not owned_free(PUZ_ORDER[j]) and S.cash < PUZ[PUZ_ORDER[j]].cost:
					j += 1
				nxt = "" if j >= PUZ_ORDER.size() else PUZ_ORDER[j]
			if nxt != "" and not owned_free(nxt):
				S.cash -= PUZ[nxt].cost
				S.owned[nxt] = int(S.owned.get(nxt, 0)) + 1
				add_log("Bought a %s for $%d." % [PUZ[nxt].name, PUZ[nxt].cost])
			S.slots[i] = nxt
			S.broken.erase(i)
			_save()
		"reset":
			if S.broken.has(i):
				S.cash -= REPAIR_COST
				S.broken.erase(i)
				add_log("Repaired the %s." % PUZ[S.slots[i]].name)
				_check_reset_done()

func _on_start() -> void:
	if phase != "lobby":
		return
	if chain().is_empty():
		add_log("The room is empty. Place at least one puzzle first.")
		return
	for i in chain():
		if S.broken.has(i):
			add_log("A puzzle is still broken. Repair or replace it first.")
			return
	if player.position.z > 8:
		add_log("Get out of the room first. You are not a puzzle.")
		return
	phase = "session"
	minute = 0
	sim_timer = 0
	_set_door(true)
	_send_group_to_slot_after_entry()
	add_log("%s enter the room. The door locks behind them." % ", ".join(group.members.map(func(m): return m.name)))

func _send_group_to_slot_after_entry() -> void:
	var slot: int = chain()[0]
	var p: Vector3 = SLOT_POS[slot]
	var inward: float = 1.4 if p.x < 8 else -1.4
	for i in customers.size():
		var off := Vector3(inward + (i % 2) * inward * 0.6, 0, (i - customers.size() / 2.0) * 0.6)
		customers[i].go([ROOM_DOOR + Vector3(0, 0, -0.6), ROOM_DOOR + Vector3(0, 0, 1.0), p + off])
		customers[i].thinking = true

func _set_door(locked: bool) -> void:
	door_body.visible = locked
	for c in door_body.get_children():
		if c is CollisionShape3D:
			c.disabled = not locked

func _on_hint() -> void:
	if phase != "session":
		return
	group.hints += 1
	group.boost = true
	group.hint_req = false
	group.prog += need(S.slots[chain()[group.at]]) * 0.35
	group.stuck = 0
	add_log(pick(HINTS))

func _cycle_speed() -> void:
	speed = 2 if speed == 1 else (4 if speed == 2 else 1)
	add_log("Time speed x%d." % speed)
	_refresh_all()

# ---------------------------------------------------------------- simulation
func _process(dt: float) -> void:
	if phase == "session":
		sim_timer += dt * speed
		while sim_timer >= SECONDS_PER_MINUTE and phase == "session":
			sim_timer -= SECONDS_PER_MINUTE
			_step()
		hint_light.light_energy = (0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)) * 2.0 if group.hint_req else 0.0
	else:
		hint_light.light_energy = 0
	_refresh_hud()

func _step() -> void:
	minute += 1
	var c := chain()
	var slot: int = c[group.at]
	var id: String = S.slots[slot]
	var p: Dictionary = PUZ[id]
	var brain := 0.0
	for m in group.members:
		brain += 2.2 if m.trait == "Smart" else 1.0
	group.prog += brain * rng.randf_range(0.4, 1.5) * (1.8 if group.boost else 1.0)
	group.stuck += 1
	if group.prog >= need(id):
		var who: String = pick(group.members).name
		group.solved += 1
		group.fun += p.fun
		group.boost = false
		group.hint_req = false
		if p.get("scare", false):
			var sc := trait_count("Screamer")
			group.scares += sc
			add_log("The skeleton jumps out. %s screams so loud the lobby hears it." % who if sc > 0 else "The skeleton jumps out. Mild screaming.")
		else:
			add_log("%s solves the %s." % [who, p.name])
		if rng.randf() < p.brk * (1 + trait_count("Clumsy")):
			S.broken.append(slot)
			add_log("Something snapped. The %s is broken." % p.name)
		group.max_stuck = max(group.max_stuck, group.stuck)
		group.stuck = 0
		group.prog = 0.0
		group.at += 1
		if group.at >= c.size():
			group.escaped = true
			_finish()
			return
		_send_group_to_slot(group.at)
	elif group.stuck == 12 and not group.hint_req:
		group.hint_req = true
		add_log("They are stuck on the %s and press the intercom button." % p.name)
	if rng.randf() < 0.07:
		var w: Array = pick(WEIRD)
		add_log(w[0].replace("{n}", pick(group.members).name))
		if w[1] != "":
			group.mess.append(w[1])
	if minute >= 60:
		group.max_stuck = max(group.max_stuck, group.stuck)
		_finish()

func _finish() -> void:
	var used := minute / 60.0
	var c := chain()
	var stars := 0.0
	var title := ""
	if group.escaped:
		stars = 5.0 if used > 0.8 else (4.0 if used > 0.55 else 3.0)
		title = "Escaped at the last second!" if used > 0.8 else ("Escaped with time to spare" if used > 0.55 else "Way too easy")
	else:
		stars = 2.5 if group.at >= c.size() - 1 else 1.5
		title = "They did not escape"
	if group.solved > 0 and float(group.fun) / group.solved >= 3.0:
		stars += 0.5
	if group.scares > 0:
		stars += 0.5
	if group.hints > 2:
		stars -= 1
	if trait_count("Impatient") > 0 and group.max_stuck > 15:
		stars -= 1
	var st: int = clampi(roundi(stars), 1, 5)
	var infl := trait_count("Influencer") > 0
	for i in (2 if infl else 1):
		S.ratings.append(st)
	var size: int = group.members.size()
	var tip: int = st * 4 * size if st >= 4 else 0
	var bonus: int = 40 if infl else 0
	var earned: int = TICKET * size + tip + bonus
	S.cash += earned
	add_log("They escaped in %d minutes." % minute if group.escaped else "Time is up. You unlock the door and pretend it was close.")
	_set_door(false)
	for cu in customers:
		cu.thinking = false
		cu.go([ROOM_DOOR + Vector3(0, 0, 1.0), ROOM_DOOR + Vector3(0, 0, -0.8), LOBBY_EXIT])
	var reviewer: String = group.members[0].name
	for m in group.members:
		if m.trait == "Influencer":
			reviewer = m.name
	var money := "Tickets $%d" % (TICKET * size)
	if tip > 0:
		money += " + tips $%d" % tip
	if bonus > 0:
		money += " + sponsored post $%d" % bonus
	review_label.text = "ROOMRATER REVIEW\n\n%s\n%s\n\n\"%s\"\n— %s, group of %d%s%s\n\n%s = $%d\n\nPress E to start the reset." % [
		title, "★".repeat(st) + "☆".repeat(5 - st), pick(QUOTES[st]), reviewer, size,
		" · Influencer: counts double" if infl else "",
		" · %d hint(s)" % group.hints if group.hints > 0 else "", money, earned]
	review_panel.visible = true
	phase = "review"
	_save()

# ---------------------------------------------------------------- reset
func _begin_reset() -> void:
	review_panel.visible = false
	phase = "reset"
	var items: Array = group.mess.duplicate()
	for i in 2 + trait_count("Clumsy"):
		items.append(pick(AFTER_MESS))
	for it in items:
		var pos := Vector3(rng.randf_range(3.5, 12.5), 0.15, rng.randf_range(9.5, 19))
		var node = interactable(pos, Vector3(0.45, 0.3, 0.45), "#ffb23e", "Clean up: " + it, Callable())
		node.on_use = _on_mess.bind(node)
		var l := Label3D.new()
		l.text = it
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position.y = 0.55
		l.font_size = 36
		l.pixel_size = 0.005
		l.outline_size = 8
		l.modulate = Color("#ffb23e")
		node.add_child(l)
		mess_nodes.append(node)
	add_log("The room is a mess. Walk in and clean up (E). Repair broken puzzles too.")
	_check_reset_done()

func _on_mess(node) -> void:
	mess_nodes.erase(node)
	node.queue_free()
	_check_reset_done()

func _check_reset_done() -> void:
	if phase != "reset" or not mess_nodes.is_empty():
		return
	for i in chain():
		if S.broken.has(i):
			return
	add_log("Room reset. Smells almost normal again.")
	S.gi += 1
	if S.gi >= GROUPS_PER_DAY:
		S.gi = 0
		S.day += 1
		var rent: int = 40 + S.day * 10
		S.cash -= rent
		add_log("Day over. Rent paid: $%d. Day %d begins." % [rent, S.day])
	phase = "lobby"
	_new_group()
	_save()
	_refresh_all()

# ---------------------------------------------------------------- refresh
func _refresh_all() -> void:
	for i in slot_nodes.size():
		var n: Dictionary = slot_nodes[i]
		var id: String = S.slots[i]
		n.prop.visible = id != ""
		if id != "":
			n.prop.material_override = _mat(PUZ[id].color)
			var d: int = PUZ[id].diff
			n.label.text = "%s\nDiff %s  Fun %d%s" % [PUZ[id].name, "■".repeat(d) + "□".repeat(4 - d), PUZ[id].fun, "\nBROKEN" if S.broken.has(i) else ""]
			n.label.modulate = Color("#ff4d4d") if S.broken.has(i) else Color.WHITE
		else:
			n.label.text = "Slot %d: empty" % (i + 1)
			n.label.modulate = Color("#9aa4ad")
		n.body.prompt = _slot_prompt(i)
		n.body.enabled = phase == "lobby" or (phase == "reset" and S.broken.has(i))
	start_btn.prompt = "Open the room for %s" % ("this group" if phase == "lobby" else "-")
	start_btn.enabled = phase == "lobby"
	hint_btn.prompt = "Give a hint over the intercom"
	hint_btn.enabled = phase == "session"
	speed_btn.prompt = "Change time speed (now x%d)" % speed
	speed_btn.enabled = phase == "session"
	_refresh_hud()

func _slot_prompt(i: int) -> String:
	if phase == "reset" and S.broken.has(i):
		return "Repair %s ($%d)" % [PUZ[S.slots[i]].name, REPAIR_COST]
	var idx := PUZ_ORDER.find(S.slots[i])
	var nxt: String = "" if idx == PUZ_ORDER.size() - 1 else PUZ_ORDER[idx + 1]
	if nxt == "":
		return "Clear this slot"
	var cost: String = "owned" if owned_free(nxt) else "$%d" % PUZ[nxt].cost
	return "Swap to next puzzle: %s (%s)" % [PUZ[nxt].name, cost]

func _refresh_hud() -> void:
	if not hud_stats:
		return
	hud_stats.text = "Day %d   Group %d/%d   $%d   Rating %s   Clock %02d:00" % [S.day, min(S.gi + 1, GROUPS_PER_DAY), GROUPS_PER_DAY, S.cash, avg_rating(), 60 - minute if phase == "session" else 60]
	var tips := {
		"lobby": "LOBBY: walk into The Study to set up puzzles (E on a pedestal), then press OPEN ROOM in the control room.",
		"session": "SESSION: watch the monitor. Press INTERCOM when they are stuck. TAB or SPEED changes time.",
		"review": "Press E to continue.",
		"reset": "RESET: clean up %d item(s) and repair broken puzzles in The Study." % mess_nodes.size(),
	}
	hud_phase.text = tips[phase]
	var f = player.focus if player else null
	hud_prompt.text = ("[E] " + f.prompt) if f and f.prompt != "" else ""
