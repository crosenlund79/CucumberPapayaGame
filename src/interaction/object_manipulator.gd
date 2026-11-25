class_name ObjectManipulator
extends Node
## Mouse selection and manipulation of [SandboxObject]s.
##
## Left click selects (click empty space to deselect); left drag applies the
## current tool to the selection. Shift = alternate axis, Ctrl = snap.
##   Move:   drag on the ground plane   | Shift: vertical
##   Rotate: horizontal drag = yaw      | Shift: vertical drag = pitch (camera axis)
##   Scale:  vertical drag = uniform    | Shift: stretch Y only

signal selection_changed(object: SandboxObject)
signal tool_changed(tool: Tool)

enum Tool { MOVE, ROTATE, SCALE }
const TOOL_NAMES: Array[String] = ["Move", "Rotate", "Scale"]

@export var camera: Camera3D
@export_flags_3d_physics var pick_mask: int = SandboxObject.PICK_LAYER
@export var rotate_degrees_per_pixel: float = 0.5
@export var scale_per_pixel: float = 0.006
@export var snap_distance: float = 0.25
@export var snap_angle_degrees: float = 15.0
@export var snap_scale: float = 0.1
@export var min_scale: float = 0.05
@export var max_scale: float = 50.0
@export var drag_threshold_pixels: float = 3.0
## Refuse drag steps that would make the selection overlap another object.
@export var block_overlap: bool = false

var objects: Array[SandboxObject] = []
var selected: SandboxObject = null
var tool: Tool = Tool.MOVE
var dragging: bool = false

var _pressed: bool = false
var _press_pos: Vector2
var _alt_axis: bool = false
var _plane: Plane
var _grab_offset: Vector3
var _rotate_axis: Vector3
var _start: Transform3D
var _start_scale: Vector3
var _accum: float = 0.0


func set_tool(new_tool: Tool) -> void:
	tool = new_tool
	tool_changed.emit(tool)


func select(object: SandboxObject) -> void:
	if object == selected:
		return
	if is_instance_valid(selected):
		selected.set_selected(false)
	selected = object
	if selected != null:
		selected.set_selected(true)
	selection_changed.emit(selected)


func select_next() -> void:
	if objects.is_empty():
		return
	var index := objects.find(selected)
	select(objects[(index + 1) % objects.size()])


## The object under a screen position, or null.
func pick(screen_pos: Vector2) -> SandboxObject:
	var from := camera.project_ray_origin(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen_pos) * 1000.0, pick_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return SandboxObject.find_owner_object(hit["collider"])


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and not mb.alt_pressed:
			get_viewport().gui_release_focus()
			var hit := pick(mb.position)
			select(hit)
			_pressed = hit != null
			_press_pos = mb.position
			dragging = false
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _pressed:
			_pressed = false
			dragging = false
			get_viewport().set_input_as_handled()
		return

	var mm := event as InputEventMouseMotion
	if mm != null and _pressed and is_instance_valid(selected):
		if not dragging:
			if mm.position.distance_to(_press_pos) < drag_threshold_pixels:
				return
			dragging = true
			_begin_drag(mm.position, mm.shift_pressed)
		elif mm.shift_pressed != _alt_axis:
			_begin_drag(mm.position, mm.shift_pressed)
		var before := selected.global_transform
		match tool:
			Tool.MOVE:
				_drag_move(mm)
			Tool.ROTATE:
				_drag_rotate(mm)
			Tool.SCALE:
				_drag_scale(mm)
		if block_overlap and not selected.query_overlaps().is_empty():
			selected.global_transform = before
		get_viewport().set_input_as_handled()
		return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_W:
				set_tool(Tool.MOVE)
			KEY_E:
				set_tool(Tool.ROTATE)
			KEY_R:
				set_tool(Tool.SCALE)
			KEY_TAB:
				select_next()
			KEY_ESCAPE:
				select(null)
			KEY_T:
				if is_instance_valid(selected):
					selected.reset_transform()
			_:
				return
		get_viewport().set_input_as_handled()


func _begin_drag(mouse_pos: Vector2, alt_axis: bool) -> void:
	_alt_axis = alt_axis
	_start = selected.global_transform
	_start_scale = selected.scale
	_accum = 0.0
	_rotate_axis = camera.global_basis.x.normalized() if alt_axis else Vector3.UP
	var p := selected.global_position
	if alt_axis:
		var n := -camera.global_basis.z
		n.y = 0.0
		_plane = Plane(n.normalized() if n.length() > 0.001 else Vector3.FORWARD, p)
	else:
		_plane = Plane(Vector3.UP, p)
	var hit: Variant = _ray_plane(mouse_pos)
	_grab_offset = p - hit if hit != null else Vector3.ZERO


func _ray_plane(screen_pos: Vector2) -> Variant:
	return _plane.intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


func _drag_move(mm: InputEventMouseMotion) -> void:
	var hit: Variant = _ray_plane(mm.position)
	if hit == null:
		return
	var goal: Vector3 = hit + _grab_offset
	if goal.distance_to(selected.global_position) > 100.0:
		return # ray nearly parallel to the plane
	var p := selected.global_position
	if _alt_axis:
		p.y = snappedf(goal.y, snap_distance) if mm.ctrl_pressed else goal.y
	else:
		p.x = snappedf(goal.x, snap_distance) if mm.ctrl_pressed else goal.x
		p.z = snappedf(goal.z, snap_distance) if mm.ctrl_pressed else goal.z
	selected.global_position = p


func _drag_rotate(mm: InputEventMouseMotion) -> void:
	_accum += (mm.relative.y if _alt_axis else mm.relative.x) * rotate_degrees_per_pixel
	var angle := snappedf(_accum, snap_angle_degrees) if mm.ctrl_pressed else _accum
	var t := _start
	t.basis = Basis(_rotate_axis, deg_to_rad(angle)) * _start.basis
	selected.global_transform = t


func _drag_scale(mm: InputEventMouseMotion) -> void:
	_accum -= mm.relative.y * scale_per_pixel
	var factor := exp(_accum)
	var s := Vector3(_start_scale.x, _start_scale.y * factor, _start_scale.z) if _alt_axis else _start_scale * factor
	if mm.ctrl_pressed:
		s = s.snapped(Vector3.ONE * snap_scale)
	selected.scale = s.clamp(Vector3.ONE * min_scale, Vector3.ONE * max_scale)
