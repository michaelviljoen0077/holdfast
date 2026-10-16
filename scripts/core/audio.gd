extends Node
## Procedural audio: every sound is synthesised at startup, so the game ships
## with a full soundscape and no external assets. Placeholder quality bar is
## "convincing at diorama distance"; real recordings can replace any entry.

const RATE := 22050

var _banks := {}            # name -> Array[AudioStreamWAV] (variants)
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _rng := RandomNumberGenerator.new()
var _last_play := {}        # name -> msec, to avoid machine-gun stacking


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	_banks["clash"] = [_clash(1.0), _clash(1.13), _clash(0.92), _clash(1.27)]
	_banks["thud"] = [_thud(1.0), _thud(0.85), _thud(1.2)]
	_banks["bow"] = [_bow(1.0), _bow(1.1)]
	_banks["arrow_hit"] = [_arrow_hit(1.0), _arrow_hit(1.25)]
	_banks["death"] = [_death(1.0), _death(0.86)]
	_banks["splash"] = [_splash()]
	_banks["crumble"] = [_crumble()]
	_banks["horn"] = [_horn()]
	_banks["click"] = [_click(900.0)]
	_banks["thunder"] = [_thunder()]
	_banks["order"] = [_click(620.0)]
	# Recorded CC0 sounds (Kenney) take over from the synthesised fallbacks.
	_load_bank("clash", ["impactMetal_medium_000", "impactMetal_medium_001", "impactMetal_medium_002", "impactMetal_medium_003", "impactMetal_medium_004", "impactPlate_medium_000", "impactPlate_medium_001"])
	_load_bank("thud", ["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002", "impactPunch_medium_003", "impactPunch_medium_004"])
	_load_bank("heavy", ["impactSoft_heavy_000", "impactSoft_heavy_001", "impactSoft_heavy_002"])
	_load_bank("slash", ["chop", "knifeSlice", "knifeSlice2", "drawKnife1"])
	_load_bank("stone", ["impactMining_000", "impactMining_001", "impactMining_002", "impactMining_003", "impactMining_004"])
	_load_bank("arrow_ground", ["impactWood_light_000", "impactWood_light_001", "impactWood_light_002"])
	_load_bank("step", ["footstep_grass_000", "footstep_grass_001", "footstep_grass_002", "footstep_grass_003", "footstep_grass_004"])
	_load_bank("coins", ["handleCoins", "handleCoins2"])
	_load_bank("wood_hit", ["impactPlank_medium_000", "impactPlank_medium_001", "impactPlank_medium_002", "impactPlank_medium_003", "impactPlank_medium_004"])
	_load_bank("select", ["cloth1", "cloth2"])
	_load_bank("victory", ["sting_victory"])
	_load_bank("defeat", ["sting_defeat"])
	_load_bank("cleared", ["sting_cleared"])
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 22.0
		p.max_distance = 160.0
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -8.0
		p.bus = "Effects"
		add_child(p)
		_pool.append(p)
	if Capture.has("dumpsfx"):
		_banks["ocean"] = [_ocean()]
		_banks["wind"] = [_wind()]
		_banks["fire"] = [_fire()]
		DirAccess.make_dir_recursive_absolute("res://shots/sfx")
		for k in _banks:
			(_banks[k][0] as AudioStreamWAV).save_to_wav("res://shots/sfx/%s.wav" % k)
	_start_music()
	_start_loop(_ocean(), -11.0, "Ocean")
	_start_loop(_wind(), -20.0, "Wind")


## Plays a positional one-shot. `gap_ms` throttles identical sounds.
func play(name: String, at: Vector3, volume_db := 0.0, gap_ms := 35) -> void:
	if not _banks.has(name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -100000)) < gap_ms:
		return
	_last_play[name] = now
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	var bank: Array = _banks[name]
	p.stream = bank[_rng.randi() % bank.size()]
	p.global_position = at
	p.volume_db = volume_db + _rng.randf_range(-1.5, 1.5)
	p.pitch_scale = _rng.randf_range(0.93, 1.07) * Engine.time_scale ** 0.25
	p.play()


func _load_bank(name: String, files: Array) -> void:
	var bank := []
	for f in files:
		var path := "res://assets/audio/kenney/%s.ogg" % f
		if ResourceLoader.exists(path):
			bank.append(load(path))
	if not bank.is_empty():
		_banks[name] = bank


func play_ui(name: String, volume_db := -6.0) -> void:
	if not _banks.has(name):
		return
	var p := AudioStreamPlayer.new()
	var bank: Array = _banks[name]
	p.stream = bank[_rng.randi() % bank.size()]
	p.volume_db = volume_db
	p.bus = "Effects"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func start_rain() -> void:
	if has_node("Rain"):
		return
	_start_loop(_rain(), -9.0, "Rain")


func fire_loop() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if not _banks.has("fire"):
		_banks["fire"] = [_fire()]
	p.stream = _banks["fire"][0]
	p.unit_size = 14.0
	p.max_distance = 120.0
	p.volume_db = -6.0
	p.autoplay = true
	p.bus = "Effects"
	return p


func _start_loop(stream: AudioStreamWAV, db: float, node_name: String) -> void:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.stream = stream
	p.volume_db = db
	p.bus = "Ambience"
	add_child(p)
	p.play()


# --------------------------------------------------------------------------
# Synthesis helpers

func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func _normalize(b: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in b.size():
		b[i] *= k
	return b


## Crossfades the tail into the head so a buffer loops without a click.
func _make_loopable(b: PackedFloat32Array, fade_s: float) -> PackedFloat32Array:
	var f := int(fade_s * RATE)
	var n := b.size() - f
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = b[i]
	for i in f:
		var t := float(i) / f
		out[i] = b[i] * t + b[n + i] * (1.0 - t)
	return out


func _clash(pitch: float) -> AudioStreamWAV:
	var b := _buf(0.45)
	var partials := [[1180.0, 9.0, 0.6], [1847.0, 12.0, 0.5], [2731.0, 16.0, 0.4], [3912.0, 22.0, 0.3], [5230.0, 30.0, 0.2]]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * p[0] * pitch * t + p[1]) * exp(-t * p[1]) * p[2]
		# Initial scrape transient.
		v += _rng.randf_range(-1.0, 1.0) * exp(-t * 180.0) * 0.9
		b[i] = v
	return _to_wav(_normalize(b, 0.7))


func _thud(pitch: float) -> AudioStreamWAV:
	var b := _buf(0.22)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.12
		var body := sin(TAU * 95.0 * pitch * t * (1.0 - t * 1.5)) * exp(-t * 26.0)
		b[i] = body * 0.8 + lp * exp(-t * 40.0) * 1.6
	return _to_wav(_normalize(b, 0.8))


func _bow(pitch: float) -> AudioStreamWAV:
	# Karplus-Strong pluck for the string, plus a short air whoosh.
	var b := _buf(0.5)
	var period := int(RATE / (196.0 * pitch))
	var ring := PackedFloat32Array()
	ring.resize(period)
	for i in period:
		ring[i] = _rng.randf_range(-1.0, 1.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := i % period
		var nxt := (k + 1) % period
		var s := ring[k]
		ring[k] = 0.5 * (ring[k] + ring[nxt]) * 0.994
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.3
		b[i] = s * exp(-t * 9.0) * 0.8 + lp * sin(clampf(t / 0.25, 0.0, 1.0) * PI) * 0.25
	return _to_wav(_normalize(b, 0.55))


func _arrow_hit(pitch: float) -> AudioStreamWAV:
	var b := _buf(0.18)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 240.0 * pitch * t) * exp(-t * 38.0) * 0.7 + _rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.6
	return _to_wav(_normalize(b, 0.6))


func _death(pitch: float) -> AudioStreamWAV:
	# A grunt: band-limited buzz with a falling pitch and soft attack.
	var b := _buf(0.38)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := (150.0 - t * 140.0) * pitch
		ph += f / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		lp += (saw - lp) * 0.08
		var env := clampf(t / 0.03, 0.0, 1.0) * exp(-t * 7.0)
		b[i] = (lp + _rng.randf_range(-0.15, 0.15)) * env
	return _to_wav(_normalize(b, 0.45))


func _splash() -> AudioStreamWAV:
	var b := _buf(0.5)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.35
		b[i] = lp * clampf(t / 0.01, 0.0, 1.0) * exp(-t * 9.0)
	return _to_wav(_normalize(b, 0.5))


func _crumble() -> AudioStreamWAV:
	var b := _buf(3.2)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		var rumble := lp2 * 14.0 * clampf(t / 0.08, 0.0, 1.0) * exp(-t * 1.1)
		# Scattered stone knocks.
		var knock := 0.0
		if _rng.randf() < 0.0035 * exp(-t * 0.8):
			knock = _rng.randf_range(0.4, 1.0)
		b[i] = rumble
		if knock > 0.0:
			var len := int(0.03 * RATE)
			var f := _rng.randf_range(300.0, 900.0)
			for j in len:
				if i + j < b.size():
					b[i + j] += sin(TAU * f * j / RATE) * exp(-j / (0.006 * RATE)) * knock * 0.6
	return _to_wav(_normalize(b, 0.95))


func _horn() -> AudioStreamWAV:
	# Two-note war horn: saw with vibrato through a gentle low-pass.
	var b := _buf(2.6)
	var ph := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var note := 110.0 if t < 1.0 else 146.8
		var vib := 1.0 + sin(TAU * 5.2 * t) * 0.006 * clampf((t - 0.3) * 2.0, 0.0, 1.0)
		ph += note * vib / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		var cutoff := 0.05 + 0.06 * clampf(t * 3.0, 0.0, 1.0)
		lp += (saw - lp) * cutoff
		lp2 += (lp - lp2) * cutoff
		var env := clampf(t / 0.15, 0.0, 1.0) * clampf((2.6 - t) / 0.6, 0.0, 1.0)
		if t > 0.92 and t < 1.04:
			env *= 0.55
		b[i] = lp2 * env
	return _to_wav(_normalize(b, 0.75))


func _click(freq: float) -> AudioStreamWAV:
	var b := _buf(0.08)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * freq * t) * exp(-t * 60.0)
	return _to_wav(_normalize(b, 0.5))


func _ocean() -> AudioStreamWAV:
	# Brown-ish noise with slow overlapping swells: surf on the shore.
	var secs := 12.0
	var b := _buf(secs + 1.5)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.08
		lp2 += (lp - lp2) * 0.25
		var swell := 0.35 + 0.65 * pow(0.5 + 0.5 * sin(TAU * t / 6.0 - 1.2), 2.5) + 0.25 * pow(0.5 + 0.5 * sin(TAU * t / 4.0 + 0.7), 3.0)
		b[i] = lp2 * swell
	return _to_wav(_normalize(_make_loopable(b, 1.5), 0.8), true)


func _wind() -> AudioStreamWAV:
	var secs := 10.0
	var b := _buf(secs + 1.5)
	var lp := 0.0
	var bp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var cut := 0.02 + 0.015 * sin(TAU * t / 7.0)
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * cut
		bp += (lp - bp) * 0.5
		b[i] = (lp - bp * 0.6) * (0.6 + 0.4 * sin(TAU * t / 5.0 + 2.0))
	return _to_wav(_normalize(_make_loopable(b, 1.5), 0.6), true)


func _fire() -> AudioStreamWAV:
	var secs := 4.0
	var b := _buf(secs + 0.5)
	var lp := 0.0
	for i in b.size():
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.05
		b[i] = lp * 1.5
		if _rng.randf() < 0.0012:
			var len := int(0.004 * RATE)
			var amp := _rng.randf_range(0.3, 1.0)
			for j in len:
				if i + j < b.size():
					b[i + j] += _rng.randf_range(-1.0, 1.0) * amp * (1.0 - float(j) / len)
	return _to_wav(_normalize(_make_loopable(b, 0.5), 0.7), true)


func _thunder() -> AudioStreamWAV:
	var b := _buf(4.5)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.03
		lp2 += (lp - lp2) * 0.04
		# A sharp crack, then rolling rumbles that fade.
		var crack := _rng.randf_range(-1.0, 1.0) * exp(-t * 25.0) * 0.25
		var roll := (0.6 + 0.4 * sin(t * 5.0) * sin(t * 1.7)) * exp(-t * 0.8)
		b[i] = lp2 * 16.0 * roll * clampf(t / 0.05, 0.0, 1.0) + crack
	return _to_wav(_normalize(b, 0.95))


func _rain() -> AudioStreamWAV:
	var b := _buf(6.5)
	var hp := 0.0
	var lp := 0.0
	for i in b.size():
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.45
		hp = n - lp
		b[i] = lp * 0.6 + hp * 0.25
		if _rng.randf() < 0.002:
			b[i] += _rng.randf_range(0.3, 0.8)
	return _to_wav(_normalize(_make_loopable(b, 1.0), 0.6), true)


# Music -----------------------------------------------------------------------

var _calm: AudioStreamPlayer
var _battle: AudioStreamPlayer
var _intensity := 0.0
var _intensity_target := 0.0


func _start_music() -> void:
	_calm = _music_player("res://assets/audio/music/calm.wav")
	_battle = _music_player("res://assets/audio/music/battle.wav")
	_apply_intensity()


func _music_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(path):
		var w: AudioStreamWAV = load(path)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		p.stream = w
	add_child(p)
	if p.stream:
		p.play()
	return p


## 0 = calm theme only, 1 = full battle theme. Changes glide over a few seconds.
func set_music_intensity(v: float) -> void:
	_intensity_target = clampf(v, 0.0, 1.0)


func _process(dt: float) -> void:
	var real := dt / maxf(Engine.time_scale, 0.01)
	_intensity = move_toward(_intensity, _intensity_target, real / 3.0)
	_apply_intensity()


func _apply_intensity() -> void:
	if _calm == null:
		return
	# Equal-power crossfade.
	_calm.volume_db = linear_to_db(maxf(cos(_intensity * PI * 0.5), 0.001)) - 4.0
	_battle.volume_db = linear_to_db(maxf(sin(_intensity * PI * 0.5), 0.001)) - 3.0
