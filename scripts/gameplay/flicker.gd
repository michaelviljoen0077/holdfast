extends OmniLight3D
## Fire light flicker.

var _base := 0.0
var _t := 0.0


func _ready() -> void:
	_base = light_energy
	_t = randf() * 10.0


func _process(dt: float) -> void:
	_t += dt
	light_energy = _base * (0.8 + 0.2 * sin(_t * 13.0) * sin(_t * 7.3 + 1.0) + 0.1 * sin(_t * 23.0))
