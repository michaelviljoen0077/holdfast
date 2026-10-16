extends RefCounted
## Paints worn dirt paths into a mask texture shared by the terrain shader and
## the grass scatter, so paths are both visible and actually clear of grass.

const EXTENT := 30.0   # mask covers [-EXTENT, EXTENT] on x and z
const RES := 512

var image := Image.create(RES, RES, false, Image.FORMAT_L8)
var _noise := FastNoiseLite.new()
var _vals := PackedFloat32Array()


func _init(p_seed: int) -> void:
	_noise.seed = p_seed + 404
	_noise.frequency = 0.15
	_vals.resize(RES * RES)


func _to_px(x: float, z: float) -> Vector2:
	return Vector2((x + EXTENT) / (EXTENT * 2.0) * RES, (z + EXTENT) / (EXTENT * 2.0) * RES)


## Wobbly path from a to b (world xz).
func segment(a: Vector2, b: Vector2, width := 0.42) -> void:
	var len := a.distance_to(b)
	var steps := int(len / 0.08) + 1
	var perp := (b - a).normalized().orthogonal()
	for s in steps + 1:
		var t := float(s) / steps
		var p := a.lerp(b, t)
		# Meander that fades out at both ends so paths meet their targets.
		var wob := _noise.get_noise_1d(t * len * 0.6 + a.x) * 0.9 * sin(PI * t)
		p += perp * wob
		_stamp(p, width * (0.85 + 0.3 * _noise.get_noise_2d(p.x * 3.0, p.y * 3.0)))


func blob(c: Vector2, r: float) -> void:
	_stamp(c, r)


func _stamp(c: Vector2, r: float) -> void:
	var px := _to_px(c.x, c.y)
	var rp := r / (EXTENT * 2.0) * RES
	var r_out := int(ceil(rp * 1.6))
	for j in range(int(px.y) - r_out, int(px.y) + r_out + 1):
		if j < 0 or j >= RES:
			continue
		for i in range(int(px.x) - r_out, int(px.x) + r_out + 1):
			if i < 0 or i >= RES:
				continue
			var d := Vector2(i + 0.5, j + 0.5).distance_to(px) / rp
			var v := 1.0 - smoothstep(0.6, 1.5, d)
			var k := j * RES + i
			_vals[k] = maxf(_vals[k], v)


func value_at(x: float, z: float) -> float:
	var px := _to_px(x, z)
	var i := clampi(int(px.x), 0, RES - 1)
	var j := clampi(int(px.y), 0, RES - 1)
	return _vals[j * RES + i]


func texture() -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(RES * RES)
	for k in RES * RES:
		bytes[k] = int(clampf(_vals[k], 0.0, 1.0) * 255.0)
	image = Image.create_from_data(RES, RES, false, Image.FORMAT_L8, bytes)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
