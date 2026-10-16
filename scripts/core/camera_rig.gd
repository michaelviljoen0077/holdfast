extends Node3D
## Diorama camera: orbit (right-drag / Q,E), pan (WASD / middle-drag), zoom (wheel).
## Motion is critically damped toward target values so everything glides.
## Depth of field follows the focus distance to give a tilt-shift miniature feel.

@export var yaw := deg_to_rad(35.0)
@export var pitch := deg_to_rad(-40.0)
@export var distance := 58.0
@export var min_distance := 16.0
@export var max_distance := 95.0
@export var fov := 30.0

var camera: Camera3D
var attributes: CameraAttributesPractical
var _t_yaw := 0.0
var _t_pitch := 0.0
var _t_dist := 0.0
var _t_focus := Vector3.ZERO
var _shake := 0.0
var _dragging_orbit := false
var _dragging_pan := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.3
	camera.far = 900.0
	attributes = CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_amount = 0.09
	camera.attributes = attributes
	add_child(camera)
	_t_yaw = yaw
	_t_pitch = pitch
	_t_dist = distance
	_t_focus = position
	_apply(1.0)


func set_view(p_yaw_deg: float, p_pitch_deg: float, p_dist: float, focus: Vector3, snap := true) -> void:
	_t_yaw = deg_to_rad(p_yaw_deg)
	_t_pitch = deg_to_rad(p_pitch_deg)
	_t_dist = p_dist
	_t_focus = focus
	if snap:
		yaw = _t_yaw
		pitch = _t_pitch
		distance = _t_dist
		position = _t_focus
		_apply(1.0)


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if Capture.has("capture"):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_t_dist = maxf(min_distance, _t_dist * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_t_dist = minf(max_distance, _t_dist * 1.12)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_orbit = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_pan = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_orbit:
			_t_yaw -= mm.relative.x * 0.006
			_t_pitch = clampf(_t_pitch - mm.relative.y * 0.004, deg_to_rad(-75.0), deg_to_rad(-18.0))
		elif _dragging_pan:
			_pan(Vector2(-mm.relative.x, -mm.relative.y) * _t_dist * 0.0015)


func _pan(v: Vector2) -> void:
	var right := Vector3(cos(_t_yaw), 0, -sin(_t_yaw))
	var fwd := Vector3(-sin(_t_yaw), 0, -cos(_t_yaw))
	_t_focus += right * v.x - fwd * v.y
	_t_focus.x = clampf(_t_focus.x, -30.0, 30.0)
	_t_focus.z = clampf(_t_focus.z, -30.0, 30.0)


func _process(dt: float) -> void:
	var move := Vector2.ZERO if Capture.has("capture") else Input.get_vector("cam_left", "cam_right", "cam_back", "cam_forward")
	if move != Vector2.ZERO:
		_pan(Vector2(move.x, move.y) * _t_dist * 0.9 * dt)
	if move == Vector2.ZERO and Capture.has("capture"):
		pass
	elif Input.is_physical_key_pressed(KEY_Q):
		_t_yaw += 1.6 * dt
	if Input.is_physical_key_pressed(KEY_E):
		_t_yaw -= 1.6 * dt
	_apply(1.0 - exp(-dt * 9.0))
	_shake = maxf(_shake - dt * 1.8, 0.0)


func _apply(k: float) -> void:
	yaw = lerpf(yaw, _t_yaw, k)
	pitch = lerpf(pitch, _t_pitch, k)
	distance = lerpf(distance, _t_dist, k)
	position = position.lerp(_t_focus, k)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var offset := b * Vector3(0, 0, distance)
	var shake := Vector3.ZERO
	if _shake > 0.0:
		var t := Time.get_ticks_msec() * 0.001
		var s := _shake * _shake * 0.35
		shake = Vector3(sin(t * 47.0), sin(t * 59.0 + 1.3), sin(t * 41.0 + 2.1)) * s
	camera.transform = Transform3D(b, offset + shake)
	# Miniature depth of field: crisp band around the focus, soft beyond.
	attributes.dof_blur_far_distance = distance + distance * 0.22
	attributes.dof_blur_far_transition = distance * 0.5
	attributes.dof_blur_near_distance = distance * 0.72
	attributes.dof_blur_near_transition = distance * 0.25
