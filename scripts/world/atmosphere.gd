extends Node3D
## Per-island weather and time of day. A preset drives the sky, sun, fog,
## water tint and wind; storms add rain, lightning and thunder; night adds
## lanterns at every door.

const PRESETS := {
	"clear": {
		"sun_pitch": -38.0, "sun_yaw": -62.0, "sun_color": Color(1.0, 0.92, 0.80), "sun_energy": 2.1, "shadow_blur": 1.2,
		"sky_top": Color(0.32, 0.52, 0.78), "sky_horizon": Color(0.74, 0.82, 0.88), "sky_bottom": Color(0.2, 0.36, 0.48),
		"ambient": Color(0.62, 0.58, 0.52), "ambient_energy": 0.7,
		"fog": Color(0.72, 0.8, 0.86), "fog_density": 0.0016,
		"water_deep": Color(0.02, 0.20, 0.36), "water_mid": Color(0.06, 0.48, 0.60), "water_shallow": Color(0.30, 0.82, 0.78),
		"saturation": 1.18, "contrast": 1.06, "exposure": 1.0, "glow": 0.35, "cloud_shadow": 0.28, "wind": 1.0, "swell": 0.025,
	},
	"golden": {
		"sun_pitch": -14.0, "sun_yaw": -118.0, "sun_color": Color(1.0, 0.70, 0.44), "sun_energy": 2.5, "shadow_blur": 1.0,
		"sky_top": Color(0.30, 0.40, 0.62), "sky_horizon": Color(0.98, 0.72, 0.50), "sky_bottom": Color(0.22, 0.28, 0.40),
		"ambient": Color(0.62, 0.50, 0.46), "ambient_energy": 0.55,
		"fog": Color(0.86, 0.70, 0.60), "fog_density": 0.0014,
		"water_deep": Color(0.03, 0.15, 0.32), "water_mid": Color(0.08, 0.36, 0.52), "water_shallow": Color(0.36, 0.72, 0.70),
		"saturation": 1.15, "contrast": 1.08, "exposure": 1.0, "glow": 0.45, "cloud_shadow": 0.18, "wind": 0.8, "swell": 0.02,
	},
	"overcast": {
		"sun_pitch": -58.0, "sun_yaw": -40.0, "sun_color": Color(0.86, 0.89, 0.93), "sun_energy": 0.95, "shadow_blur": 4.0,
		"sky_top": Color(0.52, 0.57, 0.63), "sky_horizon": Color(0.72, 0.75, 0.78), "sky_bottom": Color(0.35, 0.42, 0.47),
		"ambient": Color(0.72, 0.74, 0.77), "ambient_energy": 1.05,
		"fog": Color(0.70, 0.73, 0.76), "fog_density": 0.0028,
		"water_deep": Color(0.07, 0.19, 0.25), "water_mid": Color(0.13, 0.33, 0.38), "water_shallow": Color(0.40, 0.62, 0.60),
		"saturation": 0.96, "contrast": 1.04, "exposure": 1.05, "glow": 0.25, "cloud_shadow": 0.0, "wind": 1.4, "swell": 0.035,
	},
	"storm": {
		"sun_pitch": -50.0, "sun_yaw": -20.0, "sun_color": Color(0.72, 0.80, 0.92), "sun_energy": 0.5, "shadow_blur": 4.0,
		"sky_top": Color(0.16, 0.19, 0.24), "sky_horizon": Color(0.34, 0.38, 0.43), "sky_bottom": Color(0.12, 0.16, 0.2),
		"ambient": Color(0.46, 0.51, 0.58), "ambient_energy": 0.8,
		"fog": Color(0.33, 0.38, 0.43), "fog_density": 0.0085,
		"water_deep": Color(0.03, 0.09, 0.13), "water_mid": Color(0.07, 0.19, 0.23), "water_shallow": Color(0.26, 0.42, 0.42),
		"saturation": 0.82, "contrast": 1.12, "exposure": 1.1, "glow": 0.3, "cloud_shadow": 0.0, "wind": 2.4, "swell": 0.07,
		"rain": true, "lightning": true,
	},
	"night": {
		"sun_pitch": -48.0, "sun_yaw": -70.0, "sun_color": Color(0.55, 0.66, 1.0), "sun_energy": 0.5, "shadow_blur": 1.8,
		"sky_top": Color(0.02, 0.03, 0.07), "sky_horizon": Color(0.09, 0.12, 0.2), "sky_bottom": Color(0.02, 0.04, 0.08),
		"ambient": Color(0.34, 0.40, 0.62), "ambient_energy": 0.4,
		"fog": Color(0.08, 0.10, 0.17), "fog_density": 0.0045,
		"water_deep": Color(0.01, 0.04, 0.09), "water_mid": Color(0.03, 0.10, 0.18), "water_shallow": Color(0.10, 0.26, 0.30),
		"saturation": 1.0, "contrast": 1.1, "exposure": 1.25, "glow": 0.45, "cloud_shadow": 0.0, "wind": 0.7, "swell": 0.02,
		"lanterns": true,
	},
}
const WEIGHTS := {"clear": 34, "golden": 22, "overcast": 18, "storm": 12, "night": 14}

var preset_name := "clear"
var p: Dictionary
var sun: DirectionalLight3D
var env: Environment
var rig
var _rain: GPUParticles3D
var _bolt_t := 6.0
var _flash := 0.0


func label() -> String:
	return {"clear": "Clear skies", "golden": "Golden hour", "overcast": "Overcast", "storm": "Storm", "night": "Moonlit night"}.get(preset_name, "")


static func pick(seed_v: int) -> String:
	if Capture.has("weather"):
		return Capture.arg("weather")
	var r := RandomNumberGenerator.new()
	r.seed = seed_v * 17 + 3
	var total := 0
	for k in WEIGHTS:
		total += WEIGHTS[k]
	var roll := r.randi_range(0, total - 1)
	for k in WEIGHTS:
		roll -= WEIGHTS[k]
		if roll < 0:
			return k
	return "clear"


func _init(name_: String) -> void:
	preset_name = name_ if PRESETS.has(name_) else "clear"
	p = PRESETS[preset_name]


func configure_environment(e: Environment, sky_mat: ProceduralSkyMaterial, s: DirectionalLight3D) -> void:
	env = e
	sun = s
	sky_mat.sky_top_color = p["sky_top"]
	sky_mat.sky_horizon_color = p["sky_horizon"]
	sky_mat.ground_horizon_color = p["sky_horizon"]
	sky_mat.ground_bottom_color = p["sky_bottom"]
	e.ambient_light_color = p["ambient"]
	e.ambient_light_energy = p["ambient_energy"]
	e.fog_light_color = p["fog"]
	e.fog_density = p["fog_density"]
	e.adjustment_saturation = p["saturation"]
	e.adjustment_contrast = p["contrast"]
	e.tonemap_exposure = p["exposure"]
	e.glow_intensity = p["glow"]
	s.rotation = Vector3(deg_to_rad(p["sun_pitch"]), deg_to_rad(p["sun_yaw"]), 0.0)
	s.light_color = p["sun_color"]
	s.light_energy = p["sun_energy"]
	s.shadow_blur = p["shadow_blur"]


func configure_materials(terrain: ShaderMaterial, water: ShaderMaterial, grass: ShaderMaterial, foliage: ShaderMaterial) -> void:
	terrain.set_shader_parameter("cloud_shadow", p["cloud_shadow"])
	grass.set_shader_parameter("cloud_shadow", p["cloud_shadow"])
	grass.set_shader_parameter("wind_strength", 0.16 * p["wind"])
	foliage.set_shader_parameter("wind_strength", 0.05 * p["wind"])
	water.set_shader_parameter("deep_col", p["water_deep"])
	water.set_shader_parameter("mid_col", p["water_mid"])
	water.set_shader_parameter("shallow_col", p["water_shallow"])
	water.set_shader_parameter("swell", p["swell"])


## Night: a warm lantern by every door and a brazier atop the tower.
func add_lanterns(parent: Node3D, doors: Array, island, tower_top: Vector3) -> void:
	if not p.get("lanterns", false):
		return
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.75, 0.4)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.62, 0.25)
	glow.emission_energy_multiplier = 4.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.12
	for d in doors:
		var at := Vector3(d.x, island.height_at(d.x, d.y) + 0.75, d.y)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.68, 0.35)
		l.light_energy = 1.6
		l.omni_range = 4.0
		l.position = at
		l.set_script(preload("res://scripts/gameplay/flicker.gd"))
		parent.add_child(l)
		var m := MeshInstance3D.new()
		m.mesh = bulb
		m.material_override = glow
		m.position = at
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(m)
	var b := OmniLight3D.new()
	b.light_color = Color(1.0, 0.6, 0.3)
	b.light_energy = 3.0
	b.omni_range = 9.0
	b.position = tower_top + Vector3(0, 0.5, 0)
	b.shadow_enabled = true
	b.set_script(preload("res://scripts/gameplay/flicker.gd"))
	parent.add_child(b)


func start_weather(p_rig) -> void:
	rig = p_rig
	if p.get("rain", false):
		_rain = GPUParticles3D.new()
		_rain.amount = 9000
		_rain.lifetime = 1.1
		_rain.local_coords = false
		_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(32, 0.5, 32)
		pm.direction = Vector3(0.18, -1.0, 0.06)
		pm.spread = 3.0
		pm.initial_velocity_min = 20.0
		pm.initial_velocity_max = 25.0
		pm.gravity = Vector3.ZERO
		_rain.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.018, 0.75)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.albedo_color = Color(0.78, 0.84, 0.92, 0.32)
		q.material = m
		_rain.draw_pass_1 = q
		add_child(_rain)
		Sfx.start_rain()


func _process(dt: float) -> void:
	if _rain and rig:
		_rain.global_position = rig.global_position + Vector3(0, 22, 0)
	if p.get("lightning", false):
		_bolt_t -= dt
		if _bolt_t <= 0.0:
			_bolt_t = randf_range(7.0, 16.0)
			_flash = 1.0
			var delay := randf_range(0.4, 2.2)
			get_tree().create_timer(delay, false).timeout.connect(func(): Sfx.play_ui("thunder", -4.0))
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 3.2, 0.0)
		# Double-strobe: lightning rarely flashes just once.
		var strobe := _flash * (1.0 if fmod(_flash * 10.0, 3.0) > 1.0 else 0.35)
		sun.light_energy = p["sun_energy"] + strobe * 5.0
		env.ambient_light_energy = p["ambient_energy"] + strobe * 1.5
