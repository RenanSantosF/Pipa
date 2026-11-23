extends Node
## Banco de sons sintetizados (autoload "Sfx"). Nenhum arquivo de áudio externo:
## cada som é gerado uma vez na inicialização como AudioStreamWAV em loop e
## depois só tem volume/tom modulados em tempo real (custo de CPU ~zero).

const RATE := 22050

var wind: AudioStreamWAV
var flutter: AudioStreamWAV
var grind: AudioStreamWAV
var snap: AudioStreamWAV
## Pipa batendo: no chão (papel + bambu, baque surdo), na telha (estalo), na folhagem.
var impact_ground: AudioStreamWAV
var impact_roof: AudioStreamWAV
var impact_leaves: AudioStreamWAV

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 77
	wind = _make(_gen_wind(4.0), true)
	flutter = _make(_gen_flutter(2.0), true)
	grind = _make(_gen_grind(1.5), true)
	snap = _make(_gen_snap(0.35), false)
	impact_ground = _make(_gen_impact(0.35, 95.0, 620.0, 1.0, 0.0), false)
	impact_roof = _make(_gen_impact(0.4, 160.0, 1150.0, 0.7, 0.5), false)
	impact_leaves = _make(_gen_rustle(0.45), false)


func _make(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := samples.size()
	# Emenda suave do loop (crossfade de 30 ms).
	if loop:
		var fade := mini(int(RATE * 0.03), n / 4)
		for i in fade:
			var t := float(i) / float(fade)
			samples[i] = samples[i] * t + samples[n - fade + i] * (1.0 - t)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n - int(RATE * 0.03)
	return s


func _white() -> float:
	return _rng.randf() * 2.0 - 1.0


## Vento: ruído marrom (grave, "chiado" distante).
func _gen_wind(secs: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var b := 0.0
	var c := 0.0
	var peak := 0.001
	for i in n:
		b = (b + 0.02 * _white()) / 1.02
		c += (b - c) * 0.05
		out[i] = c
		peak = maxf(peak, absf(c))
	for i in n:
		var t := float(i) / float(n)
		out[i] = out[i] / peak * 0.6 * (0.75 + 0.25 * sin(TAU * t * 2.0))
	return out


## Papel de seda tremulando: farfalhar suave e grave, sem chiado agudo.
func _gen_flutter(secs: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var env := 0.0
	var target := 0.5
	for i in n:
		lp += (_white() - lp) * 0.18
		lp2 += (lp - lp2) * 0.3
		if i % 700 == 0:
			target = 0.25 + _rng.randf() * 0.75
		env += (target - env) * 0.002
		out[i] = lp2 * env * 1.6
	return out


## Linha "cantando" (tom eólico): seno com harmônicos e leve vibrato.
func _gen_hum(secs: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 440.0 * (1.0 + 0.004 * sin(TAU * 5.0 * t))
		ph += f / RATE
		out[i] = (sin(TAU * ph) * 0.6 + sin(TAU * ph * 2.0) * 0.25 + sin(TAU * ph * 3.0) * 0.1 + _white() * 0.05) * 0.7
	return out


## Cerol relando: chiado agudo áspero com estalinhos (grãos de vidro).
func _gen_grind(secs: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var crackle := 0.0
	for i in n:
		var w := _white()
		lp += (w - lp) * 0.08
		var hp := w - lp
		if _rng.randf() < 0.02:
			crackle = 1.0
		crackle *= 0.9
		out[i] = (hp * 0.3 + _white() * crackle * 0.35) * (0.8 + 0.2 * sin(TAU * 13.0 * float(i) / RATE))
	return out


## Catraca da lata girando: cliques secos a 24 Hz.
func _gen_ratchet(secs: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var period := RATE / 24
	for i in n:
		var k := i % period
		var env := exp(-float(k) / (RATE * 0.002))
		out[i] = _white() * env * 0.7
	return out


## Estalo da linha cortando.
func _gen_snap(secs: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var click := exp(-t / 0.004)
		var tail := exp(-t / 0.08)
		out[i] = (_white() * (click + 0.35 * tail) + sin(TAU * 1800.0 * t) * click * 0.5) * 0.9
	return out


## Pipa batendo: baque grave (corpo), toque seco da vareta de bambu, papel de seda
## amassando (ruído agudo curto) e, na telha, um chocalho curto.
func _gen_impact(secs: float, body_hz: float, knock_hz: float, paper: float, rattle: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	var peak := 0.001
	for i in n:
		var t := float(i) / RATE
		var thump := sin(TAU * body_hz * t * (1.0 - 0.35 * t / secs)) * exp(-t / 0.045)
		var knock := sin(TAU * knock_hz * t) * exp(-t / 0.01) * 0.55
		var w := _white()
		var hp := w - prev   # ruído "agudo" (papel)
		prev = w
		var crack := hp * exp(-t / 0.028) * paper * (0.6 + 0.4 * sin(TAU * 37.0 * t))
		var rat := w * exp(-t / 0.11) * rattle * absf(sin(TAU * 23.0 * t))
		out[i] = thump * 0.9 + knock + crack * 0.5 + rat * 0.35
		peak = maxf(peak, absf(out[i]))
	for i in n:
		out[i] = out[i] / peak * 0.85
	return out


## Folhagem: farfalhar (ruído filtrado com rajadas curtas).
func _gen_rustle(secs: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_white() - lp) * 0.35
		var bursts := 0.5 + 0.5 * absf(sin(TAU * 17.0 * t + sin(TAU * 5.0 * t)))
		out[i] = lp * bursts * exp(-t / 0.16) * 0.9
	return out
