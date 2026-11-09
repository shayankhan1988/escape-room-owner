extends Node3D
## A ceiling tube light that hums along and sometimes flickers or dies for a moment.

var light: OmniLight3D
var tube: MeshInstance3D
var tube_mat: StandardMaterial3D
var base_energy := 1.0
var flicker_chance := 0.0   # chance per second to start a flicker burst
var burst := 0.0
var rng := RandomNumberGenerator.new()

func setup(color: Color, energy: float, light_range: float, chance: float, shadows := true) -> void:
	rng.randomize()
	base_energy = energy
	flicker_chance = chance
	tube = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.06, 0.18)
	tube.mesh = bm
	tube_mat = StandardMaterial3D.new()
	tube_mat.albedo_color = color
	tube_mat.emission_enabled = true
	tube_mat.emission = color
	tube_mat.emission_energy_multiplier = 2.5
	tube.material_override = tube_mat
	add_child(tube)
	light = OmniLight3D.new()
	light.position.y = -0.25
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.shadow_enabled = shadows
	add_child(light)

func _process(dt: float) -> void:
	if burst <= 0.0 and rng.randf() < flicker_chance * dt:
		burst = rng.randf_range(0.15, 0.9)
	var k := 1.0
	if burst > 0.0:
		burst -= dt
		k = 0.0 if rng.randf() < 0.55 else rng.randf_range(0.3, 1.0)
	light.light_energy = base_energy * k
	tube_mat.emission_energy_multiplier = 2.5 * k
