extends Node
# RUMAH TUA - horror escape co-op (Godot 4.3). Semua tekstur & suara dibuat prosedural lewat kode.
const PORT := 7777
const HZ := 22050
var peer := ENetMultiplayerPeer.new()
var ui: CanvasLayer
var world: Node3D
var me: CharacterBody3D
var cam: Camera3D
var mon: CharacterBody3D
var heart: AudioStreamPlayer
var remotes := {}
var doors := {}
var drawers := {}
var keys := {}
var snd := {}
var texs := {}
var lamps := []
var toast: Label
var keys_lbl: Label
var act: Button
var flash: ColorRect
var ip_in: LineEdit
var on := false
var yaw := 0.0
var pitch := 0.0
var joy_id := -1
var look_id := -1
var joy_o := Vector2.ZERO
var joy_v := Vector2.ZERO
var step_t := 0.0
var growl_t := 5.0
var goal := Vector3(10, 0, 6)
var goal_t := 0.0
var chasing := false
var stun := 0.0

func _ready():
	randomize()
	ui = CanvasLayer.new()
	add_child(ui)
	_menu()

# ---------- MENU ----------
func _lbl(t: String, sz: int, c := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(420, 80)
	b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(cb)
	return b

func _menu():
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0, 0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	cc.add_child(v)
	v.add_child(_lbl("RUMAH TUA", 96, Color(0.75, 0.05, 0.05)))
	v.add_child(_lbl("Nyalakan Hotspot di HP host, pemain lain konek ke hotspot lalu JOIN", 22, Color(0.6, 0.6, 0.6)))
	v.add_child(_btn("HOST GAME", _host))
	ip_in = LineEdit.new()
	ip_in.text = "192.168.43.1"
	ip_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_in.add_theme_font_size_override("font_size", 32)
	v.add_child(ip_in)
	v.add_child(_btn("JOIN GAME", _join))
	v.add_child(_btn("KELUAR", get_tree().quit))

func _host():
	peer.create_server(PORT, 4)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer)
	multiplayer.peer_disconnected.connect(_on_leave)
	_start()

func _join():
	peer.create_client(ip_in.text.strip_edges(), PORT)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_start)
	multiplayer.connection_failed.connect(func(): ip_in.text = "GAGAL KONEK - cek IP host")
	multiplayer.server_disconnected.connect(func(): get_tree().reload_current_scene())

func _on_peer(id: int):
	if on and multiplayer.is_server():
		full.rpc_id(id, keys, _states())

func _on_leave(id: int):
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)

func _states() -> Dictionary:
	var s := {}
	for i in doors: s[i] = doors[i].open
	for i in drawers: s[i] = drawers[i].open
	return s

func _start():
	for c in ui.get_children(): c.queue_free()
	_sounds()
	_texs()
	world = Node3D.new()
	add_child(world)
	_house()
	_monster()
	_player()
	_hud()
	on = true

# ---------- TEKSTUR & SUARA PROSEDURAL ----------
func _texs():
	var n := FastNoiseLite.new()
	n.frequency = 0.04
	for k in ["wood", "wall"]:
		var c := Image.create(256, 256, false, Image.FORMAT_RGB8)
		var h := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				var xm := absf(x - 127.5)
				var ym := absf(y - 127.5)
				var v := n.get_noise_2d(xm, ym) * 0.5 + 0.5
				var col: Color
				if k == "wood":
					var pl := y >> 5
					var g := sin(xm * 0.12 + n.get_noise_2d(xm * 0.15, ym * 3.0 + pl * 90.0) * 7.0) * 0.5 + 0.5
					var b := 0.55 + 0.35 * fmod(pl * 0.37, 1.0) + g * 0.25 + v * 0.2
					if y % 32 < 2: b *= 0.25
					col = Color(0.42, 0.26, 0.14) * b
				else:
					var s := 0.8 if (x >> 4) % 2 == 0 else 1.0
					col = Color(0.5, 0.45, 0.32) * s * (0.4 + v * 0.8 + n.get_noise_2d(xm * 3.0, ym * 0.3) * 0.15)
				col.a = 1.0
				c.set_pixel(x, y, col)
				var l := col.get_luminance()
				h.set_pixel(x, y, Color(l, l, l))
		c.generate_mipmaps()
		h.bump_map_to_normal_map(3.0)
		h.generate_mipmaps()
		texs[k] = [ImageTexture.create_from_image(c), ImageTexture.create_from_image(h)]

func _mat(kind: String, tint := Color.WHITE, sc := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texs[kind][0]
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = texs[kind][1]
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * sc
	return m

func _wav(sec: float, f: Callable, loop := false) -> AudioStreamWAV:
	var n := int(sec * HZ)
	var d := PackedByteArray()
	d.resize(n * 2)
	for i in n:
		d.encode_s16(i * 2, int(clampf(f.call(float(i) / HZ), -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = HZ
	s.data = d
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = n
	return s

func _sounds():
	snd["creak"] = _wav(0.8, func(t): return ((fmod(t * (160.0 + 90.0 * sin(t * 7.0) + 40.0 * sin(t * 53.0)), 1.0) * 2.0 - 1.0) * 0.45 + (randf() - 0.5) * 0.5) * sin(PI * t / 0.8) * (0.6 + 0.4 * sin(t * 61.0)))
	snd["step"] = _wav(0.18, func(t): return ((randf() - 0.5) * 0.6 + sin(t * TAU * 70.0) * 0.6) * exp(-t * 35.0))
	snd["growl"] = _wav(1.6, func(t): return ((randf() - 0.5) * 0.6 + sin(t * TAU * (65.0 + 25.0 * sin(t * 5.0))) * 0.6) * sin(PI * t / 1.6) * (0.7 + 0.3 * sin(t * 40.0)))
	snd["scare"] = _wav(1.5, func(t): return ((randf() * 2.0 - 1.0) * 0.7 + (fmod(t * (1200.0 - 700.0 * t), 1.0) * 2.0 - 1.0) * 0.6) * exp(-t * 1.8))
	snd["drone"] = _wav(4.0, func(t): return sin(t * TAU * 55.0) * 0.4 + sin(t * TAU * 58.25) * 0.3 + sin(t * TAU * 110.0) * 0.12 + (randf() - 0.5) * 0.06, true)
	snd["heart"] = _wav(1.0, func(t): return sin(t * TAU * 48.0) * (exp(-t * 28.0) + (0.7 * exp(-(t - 0.3) * 28.0) if t > 0.3 else 0.0)), true)
	var a := AudioStreamPlayer.new()
	a.stream = snd["drone"]
	a.volume_db = -10.0
	add_child(a)
	a.play()
	heart = AudioStreamPlayer.new()
	heart.stream = snd["heart"]
	heart.volume_db = -70.0
	add_child(heart)
	heart.play()

func _play(n: String, pitch := 1.0, db := 0.0):
	var p := AudioStreamPlayer.new()
	p.stream = snd[n]
	p.pitch_scale = pitch
	p.volume_db = db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _play3d(n: String, pos: Vector3, pitch := 1.0):
	var p := AudioStreamPlayer3D.new()
	p.stream = snd[n]
	p.pitch_scale = pitch
	p.unit_size = 5.0
	p.max_distance = 40.0
	world.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

# ---------- DUNIA ----------
func _box(p: Vector3, s: Vector3, m: Material, parent: Node = null, it := "") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = p
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	b.add_child(mi)
	b.add_child(cs)
	if it != "":
		b.set_meta("it", it)
		b.collision_layer = 2
	(parent if parent else world).add_child(b)
	return b

func _wall_gap(x: float, m: Material):
	_box(Vector3(x, 1.5, 2.6), Vector3(0.2, 3, 5.2), m)
	_box(Vector3(x, 1.5, 9.4), Vector3(0.2, 3, 5.2), m)
	_box(Vector3(x, 2.6, 6), Vector3(0.2, 0.8, 1.6), m)

func _door(id: String, x: float, key: String, m: Material):
	var p := Node3D.new()
	p.position = Vector3(x, 0, 5.2)
	world.add_child(p)
	_box(Vector3(0, 1.1, 0.8), Vector3(0.08, 2.2, 1.6), m, p, id)
	doors[id] = {"pivot": p, "open": false, "key": key, "mid": Vector3(x, 0, 6)}

func _cabinet(id: String, x: float, key: String, body: Material, front: Material):
	_box(Vector3(x, 0.45, 0.3), Vector3(1.0, 0.9, 0.5), body)
	var d := _box(Vector3(x, 0.6, 0.58), Vector3(0.9, 0.3, 0.06), front, null, id)
	drawers[id] = {"node": d, "open": false, "key": key, "z": d.position.z}

func _house():
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.22, 0.3)
	e.ambient_light_energy = 0.3
	e.fog_enabled = true
	e.fog_light_color = Color(0.02, 0.02, 0.03)
	e.fog_density = 0.06
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = e
	world.add_child(we)
	var wood := _mat("wood", Color(0.8, 0.7, 0.6))
	var wall := _mat("wall")
	var dark := _mat("wood", Color(0.35, 0.25, 0.2), 0.6)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.03, 0.04, 0.03)
	_box(Vector3(10, -0.1, 6), Vector3(20, 0.2, 12), wood)
	_box(Vector3(30, -0.1, 6), Vector3(20, 0.2, 12), ground)
	_box(Vector3(10, 3.1, 6), Vector3(20, 0.2, 12), wall)
	_box(Vector3(10, 1.5, -0.1), Vector3(20.4, 3, 0.2), wall)
	_box(Vector3(10, 1.5, 12.1), Vector3(20.4, 3, 0.2), wall)
	_box(Vector3(-0.1, 1.5, 6), Vector3(0.2, 3, 12), wall)
	for x in [7.0, 14.0, 20.1]: _wall_gap(x, wall)
	_door("door1", 7.0, "Kunci Perak", dark)
	_door("door2", 14.0, "Kunci Tembaga", dark)
	_door("exit", 20.1, "Kunci Emas", dark)
	for c in [["d1", 2.0, "Kunci Perak"], ["d2", 4.5, ""], ["d3", 9.0, ""], ["d4", 12.0, "Kunci Tembaga"], ["d5", 16.0, ""], ["d6", 18.5, "Kunci Emas"]]:
		_cabinet(c[0], c[1], c[2], dark, wood)
	for p in [Vector3(4, 0.4, 8.5), Vector3(10.5, 0.4, 8), Vector3(17, 0.4, 8.5), Vector3(11, 0.4, 3.5)]:
		_box(p, Vector3(1.6, 0.8, 0.9), dark)
	for x in [3.5, 10.5, 17.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(x, 2.6, 6)
		l.light_color = Color(1, 0.65, 0.35)
		l.omni_range = 9.0
		l.light_energy = 0.6
		world.add_child(l)
		lamps.append(l)

func _monster():
	mon = CharacterBody3D.new()
	mon.collision_layer = 0
	mon.collision_mask = 1
	mon.position = Vector3(17, 0, 3)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.04, 0.04)
	var pale := StandardMaterial3D.new()
	pale.albedo_color = Color(0.75, 0.7, 0.6)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	red.emission_enabled = true
	red.emission = Color.RED
	red.emission_energy_multiplier = 4.0
	var parts := [
		[CapsuleMesh.new(), Vector3(0, 1.1, 0), Vector3.ZERO, Vector3(1, 1, 1), dark],
		[SphereMesh.new(), Vector3(0, 2.05, -0.05), Vector3.ZERO, Vector3(0.55, 0.8, 0.6), pale],
		[SphereMesh.new(), Vector3(-0.1, 2.12, -0.22), Vector3.ZERO, Vector3(0.09, 0.06, 0.06), red],
		[SphereMesh.new(), Vector3(0.1, 2.12, -0.22), Vector3.ZERO, Vector3(0.09, 0.06, 0.06), red],
		[CylinderMesh.new(), Vector3(-0.5, 1.3, -0.4), Vector3(-60, 0, 0), Vector3(0.1, 1.5, 0.1), dark],
		[CylinderMesh.new(), Vector3(0.5, 1.3, -0.4), Vector3(-60, 0, 0), Vector3(0.1, 1.5, 0.1), dark]]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.position = p[1]
		mi.rotation_degrees = p[2]
		mi.scale = p[3]
		mi.material_override = p[4]
		mon.add_child(mi)
	(parts[0][0] as CapsuleMesh).radius = 0.4
	(parts[0][0] as CapsuleMesh).height = 1.9
	for i in [1, 2, 3]:
		(parts[i][0] as SphereMesh).radius = 0.5
		(parts[i][0] as SphereMesh).height = 1.0
	for i in [4, 5]:
		(parts[i][0] as CylinderMesh).top_radius = 0.5
		(parts[i][0] as CylinderMesh).bottom_radius = 0.3
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.4
	sh.height = 2.0
	cs.shape = sh
	cs.position.y = 1.0
	mon.add_child(cs)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.1, 0.05)
	l.light_energy = 0.8
	l.omni_range = 5.0
	l.position.y = 2.0
	mon.add_child(l)
	world.add_child(mon)

func _player():
	me = CharacterBody3D.new()
	me.collision_layer = 4
	me.collision_mask = 3
	me.position = Vector3(randf_range(1.5, 4.0), 0.1, randf_range(4.5, 7.5))
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.35
	sh.height = 1.7
	cs.shape = sh
	cs.position.y = 0.85
	me.add_child(cs)
	cam = Camera3D.new()
	cam.position.y = 1.6
	cam.fov = 78.0
	cam.near = 0.05
	me.add_child(cam)
	var f := SpotLight3D.new()
	f.spot_range = 16.0
	f.spot_angle = 34.0
	f.light_energy = 6.0
	f.shadow_enabled = true
	cam.add_child(f)
	world.add_child(me)
	cam.make_current()

func _avatar() -> Node3D:
	var a := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.7
	mi.mesh = cm
	mi.position.y = 0.85
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.4, 0.8)
	m.emission_enabled = true
	m.emission = Color(0.1, 0.25, 0.6)
	mi.material_override = m
	a.add_child(mi)
	var l := OmniLight3D.new()
	l.omni_range = 3.0
	l.light_energy = 0.4
	l.light_color = Color(0.5, 0.7, 1)
	l.position.y = 1.5
	a.add_child(l)
	world.add_child(a)
	return a

func _hud():
	toast = _lbl("", 34, Color(1, 0.9, 0.6))
	toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast.offset_top = 40
	toast.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(toast)
	var dot := _lbl(".", 40)
	dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dot)
	keys_lbl = _lbl("Kunci: -", 24, Color(0.8, 0.8, 0.8))
	keys_lbl.position = Vector2(20, 20)
	ui.add_child(keys_lbl)
	if multiplayer.is_server():
		var ips := PackedStringArray()
		for a in IP.get_local_addresses():
			if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."): ips.append(a)
		var il := _lbl("IP Room: " + ", ".join(ips), 22, Color(0.5, 0.8, 0.5))
		il.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		il.offset_left = 20
		il.offset_top = -50
		ui.add_child(il)
	act = Button.new()
	act.text = "AKSI"
	act.add_theme_font_size_override("font_size", 36)
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	act.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	act.offset_left = -240
	act.offset_top = -160
	act.offset_right = -40
	act.offset_bottom = -40
	ui.add_child(act)
	flash = ColorRect.new()
	flash.color = Color(0.6, 0, 0, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash)

func _toast(t: String):
	if not toast: return
	toast.text = t
	toast.modulate.a = 1.0
	create_tween().tween_property(toast, "modulate:a", 0.0, 2.5).set_delay(2.0)

# ---------- INPUT SENTUH ----------
func _input(e: InputEvent):
	if not on: return
	var w := get_viewport().get_visible_rect().size.x
	if e is InputEventScreenTouch:
		if e.pressed:
			if act.get_global_rect().has_point(e.position):
				_interact()
			elif e.position.x < w * 0.45 and joy_id < 0:
				joy_id = e.index
				joy_o = e.position
			elif e.position.x >= w * 0.45 and look_id < 0:
				look_id = e.index
		else:
			if e.index == joy_id:
				joy_id = -1
				joy_v = Vector2.ZERO
			if e.index == look_id: look_id = -1
	elif e is InputEventScreenDrag:
		if e.index == joy_id:
			joy_v = ((e.position - joy_o) / 120.0).limit_length(1.0)
		elif e.index == look_id:
			yaw -= e.relative.x * 0.006
			pitch = clampf(pitch - e.relative.y * 0.006, -1.3, 1.3)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_E:
		_interact()

func _look() -> String:
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_transform.basis.z * 2.4, 3, [me.get_rid()])
	var r := me.get_world_3d().direct_space_state.intersect_ray(q)
	if r and r.collider.has_meta("it"): return r.collider.get_meta("it")
	return ""

func _interact():
	var id := _look()
	if id == "": return
	if doors.has(id):
		var d = doors[id]
		if d.key != "" and not keys.has(d.key) and not d.open:
			_toast("Terkunci! Cari " + d.key)
			_play("creak", 1.7, -4.0)
			return
		toggle.rpc(id)
	elif drawers.has(id):
		var was: bool = drawers[id].open
		var k: String = drawers[id].key
		toggle.rpc(id)
		if not was and k != "" and not keys.has(k): got_key.rpc(k)
		elif not was: _toast("Kosong...")

# ---------- LOOP ----------
func _physics_process(dt: float):
	if not on: return
	var v := (joy_v + Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")).limit_length(1.0)
	me.rotation.y = yaw
	cam.rotation.x = pitch
	var d := me.transform.basis * Vector3(v.x, 0, v.y)
	me.velocity = Vector3(d.x * 3.6, 0.0 if me.is_on_floor() else me.velocity.y - 20.0 * dt, d.z * 3.6)
	me.move_and_slide()
	step_t -= dt
	if v.length() > 0.2 and step_t <= 0.0:
		step_t = 0.55
		_play("step", randf_range(0.8, 1.1), -8.0)
		if randf() < 0.35: _play("creak", randf_range(0.6, 1.2), -6.0)
	growl_t -= dt
	if growl_t <= 0.0:
		growl_t = randf_range(6.0, 14.0)
		_play3d("growl", mon.global_position, randf_range(0.8, 1.1))
	sync.rpc(me.position, yaw)
	for a in remotes.values(): a.position = a.position.lerp(a.get_meta("t"), 0.4)
	for l in lamps:
		if randf() < 0.03: l.light_energy = randf_range(0.15, 0.7)
	heart.volume_db = lerpf(-70.0, -2.0, clampf(1.0 - me.position.distance_to(mon.position) / 12.0, 0.0, 1.0))
	if multiplayer.is_server():
		_ai(dt)
		mon_sync.rpc(mon.position, mon.rotation.y)
	if me.position.x > 21.5: win.rpc()

func _room(x: float) -> int:
	return 0 if x < 7.0 else (1 if x < 14.0 else 2)

func _route(a: Vector3, b: Vector3) -> Vector3:
	var ra := _room(a.x)
	var rb := _room(b.x)
	if ra == rb: return b
	var s := 1.0 if rb > ra else -1.0
	var dx := (7.0 if ra == 0 else 14.0) if s > 0 else (7.0 if ra == 1 else 14.0)
	if s * (a.x - dx) < -0.3 and absf(a.z - 6.0) > 0.25: return Vector3(dx - s * 1.2, 0, 6)
	return Vector3(dx + s * 1.2, 0, 6)

func _ai(dt: float):
	var ps := {multiplayer.get_unique_id(): me.position}
	for i in remotes: ps[i] = remotes[i].position
	var bd := 99.0
	var bp := mon.position
	for i in ps:
		var dd: float = mon.position.distance_to(ps[i])
		if dd < bd:
			bd = dd
			bp = ps[i]
	if stun > 0.0:
		stun -= dt
		return
	chasing = bd < (16.0 if chasing else 11.0)
	goal_t -= dt
	if goal_t <= 0.0 or mon.position.distance_to(goal) < 1.0:
		goal = Vector3(randf_range(1, 19), 0, randf_range(1, 11))
		goal_t = 10.0
	var tgt := bp if chasing else goal
	var to := _route(mon.position, tgt) - mon.position
	to.y = 0.0
	if to.length() > 0.15:
		mon.velocity = to.normalized() * (3.1 if chasing else 1.5)
		mon.look_at(mon.position + to)
		mon.move_and_slide()
	for id in doors:
		if id != "exit" and not doors[id].open and mon.position.distance_to(doors[id].mid) < 2.0: toggle.rpc(id)
	if bd < 1.3:
		for i in ps:
			if mon.position.distance_to(ps[i]) < 1.3:
				caught.rpc(i)
				break

# ---------- RPC ----------
@rpc("any_peer", "unreliable")
func sync(p: Vector3, ry: float):
	if not on: return
	var id := multiplayer.get_remote_sender_id()
	if not remotes.has(id):
		remotes[id] = _avatar()
		remotes[id].position = p
	remotes[id].set_meta("t", p)
	remotes[id].rotation.y = ry

@rpc("authority", "unreliable")
func mon_sync(p: Vector3, ry: float):
	if on:
		mon.position = mon.position.lerp(p, 0.5)
		mon.rotation.y = ry

func _set_open(id: String, o: bool, anim: bool):
	var n: Node3D
	var prop: String
	var to: float
	if doors.has(id):
		doors[id].open = o
		n = doors[id].pivot
		prop = "rotation:y"
		to = deg_to_rad(100.0) if o else 0.0
	elif drawers.has(id):
		drawers[id].open = o
		n = drawers[id].node
		prop = "position:z"
		to = drawers[id].z + (0.45 if o else 0.0)
	else:
		return
	if anim:
		create_tween().tween_property(n, prop, to, 0.7).set_trans(Tween.TRANS_SINE)
		_play3d("creak", n.global_position, randf_range(0.8, 1.2))
	else:
		n.set_indexed(prop, to)

@rpc("any_peer", "call_local", "reliable")
func toggle(id: String):
	if not on: return
	var o: bool = doors[id].open if doors.has(id) else drawers[id].open
	_set_open(id, not o, true)

@rpc("any_peer", "call_local", "reliable")
func got_key(k: String):
	if not on: return
	keys[k] = true
	keys_lbl.text = "Kunci: " + ", ".join(PackedStringArray(keys.keys()))
	_toast(k + " ditemukan!")

@rpc("authority", "reliable")
func full(k: Dictionary, st: Dictionary):
	if not on: return
	keys = k
	keys_lbl.text = "Kunci: " + ", ".join(PackedStringArray(keys.keys()))
	for i in st: _set_open(i, st[i], false)

@rpc("any_peer", "call_local", "reliable")
func caught(id: int):
	if not on: return
	if id == multiplayer.get_unique_id():
		_play("scare")
		flash.color = Color(0.6, 0, 0, 1)
		create_tween().tween_property(flash, "color:a", 0.0, 1.8)
		me.position = Vector3(2.5, 0.1, 6)
	if multiplayer.is_server():
		mon.position = Vector3(17, 0, 3)
		stun = 5.0

@rpc("any_peer", "call_local", "reliable")
func win():
	if not on: return
	on = false
	var l := _lbl("KALIAN BERHASIL KABUR!", 72, Color(0.9, 0.9, 0.4))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(l)
	var b := _btn("MENU", func():
		multiplayer.multiplayer_peer = null
		get_tree().reload_current_scene())
	b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	b.offset_top = -140
	ui.add_child(b)
