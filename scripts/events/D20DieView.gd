class_name D20DieView
extends Control

# A real 3D d20 for the event roll screens. A SubViewport hosts an
# icosahedron mesh (20 flat faces) with a Label3D number pinned to each face,
# numbered like a real d20 (opposite faces sum to 21). Click it (when
# interactive) to roll: the die tumbles in 3D for a beat, then settles with the
# target face turned to the camera. Advantage/disadvantage rolls show two dice;
# the screen marks the winner / loser via set_highlight.
#
# Public API is unchanged from the old 2D version so callers (EventModal) need
# no edits: setup / set_static / set_highlight / roll_to + clicked /
# roll_finished. The geometry, numbering and timing are all data here, so this
# is easy to extend toward other dice (d6/d8/…) later, as planned in the HTML.

signal clicked
signal roll_finished(value: int)

const SPIN_SECONDS := 0.6     # free tumble before settling
const SETTLE_SECONDS := 0.4   # slerp onto the target face
const SPIN_SPEED := 13.0      # rad/s during the tumble

var value: int = 20
var interactive: bool = false

var _size: float = 130.0
var _highlight: String = "normal"   # normal / winner / loser
var _rolling: bool = false
var _consumed: bool = false         # a click has already fired
var _target: int = 20
var _done_cb: Callable

# 3D scaffold.
var _viewport: SubViewport
var _die: Node3D
var _material: StandardMaterial3D
var _labels: Array[Label3D] = []
var _face_normals: Array[Vector3] = []   # outward normal per face
var _values: Array[int] = []             # face index -> die value

# Tumble state.
var _elapsed: float = 0.0
var _cur := Quaternion.IDENTITY
var _spin_axis := Vector3(1, 1, 0)
var _end_quat := Quaternion.IDENTITY
var _slerp_start := Quaternion.IDENTITY
var _slerp_captured := false

func setup(size_px: float, is_interactive: bool) -> void:
	_size = size_px
	interactive = is_interactive
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_STOP if is_interactive else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_interactive else Control.CURSOR_ARROW
	set_process(false)
	if _viewport == null:
		_build_scene(size_px)
	_apply_highlight_colors()

func _gui_input(event: InputEvent) -> void:
	if not interactive or _consumed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_consumed = true
		emit_signal("clicked")

# Tumble, then land on `target`. cb (optional) fires when it settles.
func roll_to(target: int, cb: Callable = Callable()) -> void:
	_target = clampi(target, 1, 20)
	_done_cb = cb
	_end_quat = _rotation_for_value(_target)
	# Random tumble axis (kept off the pure cardinal axes so it reads as 3D).
	_spin_axis = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
		randf_range(-0.5, 0.5)).normalized()
	if _spin_axis.length() < 0.01:
		_spin_axis = Vector3(1, 1, 0).normalized()
	_elapsed = 0.0
	_slerp_captured = false
	_rolling = true
	set_process(true)

func set_static(v: int) -> void:
	value = clampi(v, 1, 20)
	_cur = _rotation_for_value(value)
	if _die != null:
		_die.quaternion = _cur

func set_highlight(state: String) -> void:
	_highlight = state
	_apply_highlight_colors()

func _process(delta: float) -> void:
	if not _rolling or _die == null:
		return
	_elapsed += delta
	if _elapsed < SPIN_SECONDS:
		_cur = (Quaternion(_spin_axis, SPIN_SPEED * delta) * _cur).normalized()
		_die.quaternion = _cur
		return
	if not _slerp_captured:
		_slerp_captured = true
		_slerp_start = _cur
	var t: float = clampf((_elapsed - SPIN_SECONDS) / SETTLE_SECONDS, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - t, 3.0)   # ease-out cubic
	_die.quaternion = _slerp_start.slerp(_end_quat, e)
	if t >= 1.0:
		_rolling = false
		value = _target
		_cur = _end_quat
		set_process(false)
		emit_signal("roll_finished", value)
		if _done_cb.is_valid():
			_done_cb.call(value)

# ---------------------------------------------------------------------------
# 3D scene construction
# ---------------------------------------------------------------------------

func _build_scene(size_px: float) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Let clicks fall through to this Control's _gui_input.
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(size_px), int(size_px))
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(_viewport)

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.transform = Transform3D(Basis(), Vector3(0, 0, 3.2))
	cam.current = true
	_viewport.add_child(cam)

	# Key + fill directional lights so every camera-facing face reads (there's
	# no WorldEnvironment, which keeps the background transparent).
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -28, 0)
	key.light_energy = 1.1
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-150, 30, 0)
	fill.light_energy = 0.45
	_viewport.add_child(fill)

	_die = Node3D.new()
	_viewport.add_child(_die)

	_material = StandardMaterial3D.new()
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED   # winding-agnostic
	_material.roughness = 0.55
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _build_icosahedron()
	mesh_inst.material_override = _material
	_die.add_child(mesh_inst)

	_build_face_numbers()
	_die.quaternion = _rotation_for_value(value)

# Builds a flat-shaded icosahedron of circumradius 1 and records each face's
# outward normal + centroid (used for numbering and camera-facing rotations).
func _build_icosahedron() -> ArrayMesh:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

	_face_normals.clear()
	var centroids: Array[Vector3] = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = verts[f[0]]
		var b: Vector3 = verts[f[1]]
		var c: Vector3 = verts[f[2]]
		var centroid: Vector3 = (a + b + c) / 3.0
		var n: Vector3 = (b - a).cross(c - a).normalized()
		if n.dot(centroid) < 0.0:   # force outward
			n = -n
		_face_normals.append(n)
		centroids.append(centroid)
		st.set_normal(n)
		st.add_vertex(a)
		st.set_normal(n)
		st.add_vertex(b)
		st.set_normal(n)
		st.add_vertex(c)
	_values = _assign_face_values(centroids)
	return st.commit()

# d20 numbering: pair antipodal faces and give them (n, 21 - n) so opposite
# faces sum to 21, like a real die.
func _assign_face_values(centroids: Array[Vector3]) -> Array[int]:
	var values: Array[int] = []
	values.resize(centroids.size())
	values.fill(0)
	var next: int = 1
	for i in centroids.size():
		if values[i] != 0:
			continue
		var opp: int = -1
		var best: float = 2.0
		var ni: Vector3 = centroids[i].normalized()
		for j in centroids.size():
			if j == i or values[j] != 0:
				continue
			var d: float = ni.dot(centroids[j].normalized())
			if d < best:
				best = d
				opp = j
		values[i] = next
		if opp >= 0:
			values[opp] = 21 - next
		next += 1
	return values

func _build_face_numbers() -> void:
	_labels.clear()
	for i in _face_normals.size():
		var n: Vector3 = _face_normals[i]
		var label := Label3D.new()
		label.text = str(_values[i])
		label.font_size = 80
		label.pixel_size = 0.0042
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.modulate = Color(0.96, 0.94, 1.0)
		label.outline_size = 10
		label.outline_modulate = Color(0.05, 0.04, 0.09)
		# Orient so the text's +Z faces outward along the face normal.
		var up: Vector3 = Vector3.UP
		if absf(n.dot(up)) > 0.98:
			up = Vector3.RIGHT
		var x_axis: Vector3 = up.cross(n).normalized()
		var y_axis: Vector3 = n.cross(x_axis).normalized()
		var basis := Basis(x_axis, y_axis, n)
		# Float just outside the face plane (face inradius ≈ 0.795) so the number
		# sits on the surface and back-face numbers stay occluded by the body.
		label.transform = Transform3D(basis, n * 0.86)
		_die.add_child(label)
		_labels.append(label)

# Rotation that turns the face carrying `v` toward the camera (+Z).
func _rotation_for_value(v: int) -> Quaternion:
	if _values.is_empty():
		return Quaternion.IDENTITY
	var idx: int = _values.find(v)
	if idx < 0:
		return Quaternion.IDENTITY
	return _quat_from_to(_face_normals[idx], Vector3(0, 0, 1))

func _quat_from_to(a: Vector3, b: Vector3) -> Quaternion:
	a = a.normalized()
	b = b.normalized()
	var d: float = a.dot(b)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var perp: Vector3 = a.cross(Vector3.RIGHT)
		if perp.length() < 0.001:
			perp = a.cross(Vector3.UP)
		return Quaternion(perp.normalized(), PI)
	var axis: Vector3 = a.cross(b).normalized()
	return Quaternion(axis, acos(clampf(d, -1.0, 1.0)))

func _apply_highlight_colors() -> void:
	if _material == null:
		return
	var face := Color(0.17, 0.15, 0.24)
	var num := Color(0.96, 0.94, 1.0)
	match _highlight:
		"winner":
			face = Color(0.30, 0.24, 0.07)
			num = Color(1.0, 0.90, 0.40)
		"loser":
			face = Color(0.12, 0.12, 0.15)
			num = Color(0.62, 0.62, 0.68)
	_material.albedo_color = face
	for label in _labels:
		label.modulate = num
