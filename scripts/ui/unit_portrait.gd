extends SubViewportContainer
## A small live 3D portrait of a squad's soldier, idling under warm light.
## Used on war-camp cards so the warband reads as people, not rows of text.

const UnitRig := preload("res://scripts/gameplay/unit_rig.gd")

const SPECS := {
	"shield": {"scene": "res://assets/kaykit/characters/Knight.glb", "keep": ["1H_Sword", "Rectangle_Shield"], "idle": "Idle"},
	"sword": {"scene": "res://assets/kaykit/characters/Knight.glb", "keep": ["2H_Sword"], "idle": "2H_Melee_Idle"},
	"archer": {"scene": "res://assets/kaykit/characters/Rogue_Hooded.glb", "keep": ["1H_Crossbow"], "idle": "1H_Ranged_Aiming"},
}

var kind := "shield"
var _rig
var _vp: SubViewport


func _init(p_kind := "shield", px := 92) -> void:
	kind = p_kind
	stretch = true
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = Vector2i(px * 2, px * 2)
	add_child(_vp)

	var spec: Dictionary = SPECS.get(kind, SPECS["shield"])
	_rig = UnitRig.new(load(spec["scene"]), PackedStringArray(spec["keep"]), 1.0)
	_vp.add_child(_rig.root)
	_rig.root.rotation.y = deg_to_rad(28.0)
	_rig.loop(spec["idle"])

	var cam := Camera3D.new()
	cam.fov = 26.0
	cam.position = Vector3(0, 1.55, 5.2)
	cam.look_at_from_position(cam.position, Vector3(0, 1.25, 0), Vector3.UP)
	_vp.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-30), deg_to_rad(-40), 0)
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 1.6
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-15), deg_to_rad(150), 0)
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.light_energy = 1.2
	_vp.add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.4, 0.38)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)


func _process(dt: float) -> void:
	if _rig:
		_rig.tick(dt)
