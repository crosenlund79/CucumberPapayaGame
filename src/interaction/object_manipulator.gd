class_name ObjectManipulator
extends Node2D
## Mouse selection and manipulation of [SandboxObject]s (pixel-accurate picking:
## transparent pixels are ignored, the topmost layer wins).
##
## Left click selects (empty space deselects); left drag applies the tool.
##   Move:   drag                | Shift: lock to one axis
##   Rotate: drag around pivot   | Ctrl: snap angle
##   Scale:  drag from pivot     | Shift: stretch Y only
## Ctrl snaps in every tool. In path-edit mode, clicks add/drag path points.

signal selection_changed(object: SandboxObject)
signal tool_changed(tool: Tool)
signal path_edit_changed(active: bool)

enum Tool { MOVE, ROTATE, SCALE }
const TOOL_NAMES: Array[String] = ["Move", "Rotate", "Scale"]

@export var snap_distance: float = 10.0
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
## While set, left clicks add/drag points of this animator's path.
var path_edit_target: ProceduralAnimator = null

var _pressed: bool = false
var _press_screen: Vector2
var _press_world: Vector2
var _start_pos: Vector2
var _start_rotation: float
var _start_scale: Vector2
var _accum_angle: float
var _last_angle: float
var _path_drag_index: int = -1


func set_tool(new_tool: Tool) -> void:
	tool = new_tool
	tool_changed.emit(tool)


func set_path_edit(target: ProceduralAnimator) -> void:
	path_edit_target = target
	_path_drag_index = -1
	path_edit_changed.emit(target != null)


func select(object: SandboxObject) -> void:
	if object == selected:
		return
	if is_instance_valid(selected):
		selected.set_selected(false)
	selected = object
	if selected != null:
		selected.set_selected(true)
	set_path_edit(null)
	selection_changed.emit(selected)


func select_next() -> void:
	if objects.is_empty():
		return
	select(objects[(objects.find(selected) + 1) % objects.size()])


## Topmost object with an opaque pixel at [param world_point], or null.
func pick(world_point: Vector2) -> SandboxObject:
	var best_sprite: Sprite2D = null
	var best: SandboxObject = null
	for o in objects:
		if not is_instance_valid(o):
			continue
		var sprite := o.hit_test(world_point)
		if sprite != null and (best_sprite == null or SandboxObject.draws_above(sprite, best_sprite)):
			best_sprite = sprite
			best = o
	return best


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			get_viewport().gui_release_focus()
			if path_edit_target != null:
				_path_press(get_global_mouse_position())
			else:
				var hit := pick(get_global_mouse_position())
				select(hit)
				_pressed = hit != null
				_press_screen = mb.position
				_press_world = get_global_mouse_position()
				dragging = false
			get_viewport().set_input_as_handled()
		elif _pressed or _path_drag_index >= 0:
			_pressed = false
			dragging = false
			_path_drag_index = -1
			get_viewport().set_input_as_handled()
		return

	var mm := event as InputEventMouseMotion
	if mm != null:
		if _path_drag_index >= 0:
			_path_drag(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif _pressed and is_instance_valid(selected):
			if not dragging:
				if mm.position.distance_to(_press_screen) < drag_threshold_pixels:
					return
				dragging = true
				_begin_drag()
			var before := selected.global_transform
			var world := get_global_mouse_position()
			match tool:
				Tool.MOVE:
					_drag_move(world, mm.shift_pressed, mm.ctrl_pressed)
				Tool.ROTATE:
					_drag_rotate(world, mm.ctrl_pressed)
				Tool.SCALE:
					_drag_scale(world, mm.shift_pressed, mm.ctrl_pressed)
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
				if path_edit_target != null:
					set_path_edit(null)
				else:
					select(null)
			KEY_T:
				if is_instance_valid(selected):
					selected.reset_transform()
			KEY_H:
				if is_instance_valid(selected):
					selected.flip_horizontal()
			KEY_BRACKETRIGHT:
				if is_instance_valid(selected):
					selected.z_index += 1
			KEY_BRACKETLEFT:
				if is_instance_valid(selected):
					selected.z_index -= 1
			_:
				return
		get_viewport().set_input_as_handled()


func _begin_drag() -> void:
	_start_pos = selected.global_position
	_start_rotation = selected.global_rotation
	_start_scale = selected.scale
	_accum_angle = 0.0
	_last_angle = (_press_world - _start_pos).angle()


func _drag_move(world: Vector2, lock_axis: bool, snap: bool) -> void:
	var delta := world - _press_world
	if lock_axis:
		delta = Vector2(delta.x, 0) if absf(delta.x) >= absf(delta.y) else Vector2(0, delta.y)
	var p := _start_pos + delta
	if snap:
		p = p.snapped(Vector2.ONE * snap_distance)
	selected.global_position = p


func _drag_rotate(world: Vector2, snap: bool) -> void:
	var angle := (world - _start_pos).angle()
	_accum_angle += angle_difference(_last_angle, angle)
	_last_angle = angle
	var rot := _start_rotation + _accum_angle
	if snap:
		rot = snappedf(rot, deg_to_rad(snap_angle_degrees))
	selected.global_rotation = rot


func _drag_scale(world: Vector2, y_only: bool, snap: bool) -> void:
	var factor := world.distance_to(_start_pos) / maxf(_press_world.distance_to(_start_pos), 4.0)
	var s := Vector2(_start_scale.x, _start_scale.y * factor) if y_only else _start_scale * factor
	for i in 2:
		var magnitude := absf(s[i])
		if snap:
			magnitude = snappedf(magnitude, snap_scale)
		s[i] = clampf(magnitude, min_scale, max_scale) * (signf(s[i]) if s[i] != 0.0 else 1.0)
	selected.scale = s


# --- Path editing -------------------------------------------------------------------

func _path_scale(cfg: ProceduralAnimationConfig) -> float:
	return cfg.movement_range if absf(cfg.movement_range) > 0.001 else 1.0


func _path_press(world: Vector2) -> void:
	var cfg := path_edit_target.config
	if cfg.mode != ProceduralAnimationConfig.Mode.PATH:
		cfg.mode = ProceduralAnimationConfig.Mode.PATH
		cfg.movement_range = 1.0
	var shown := PathDisplay.world_points(path_edit_target)
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	for i in range(1, shown.size()):
		if shown[i].distance_to(world) * zoom < 10.0:
			_path_drag_index = i
			return
	var pts := cfg.path_points
	if pts.is_empty():
		pts.append(Vector2.ZERO)
	pts.append(_to_path_space(world, pts[0], cfg))
	cfg.path_points = pts
	_path_drag_index = pts.size() - 1


func _path_drag(world: Vector2) -> void:
	if path_edit_target == null:
		return
	var cfg := path_edit_target.config
	var pts := cfg.path_points
	if _path_drag_index < 1 or _path_drag_index >= pts.size():
		return
	pts[_path_drag_index] = _to_path_space(world, pts[0], cfg)
	cfg.path_points = pts


func _to_path_space(world: Vector2, start: Vector2, cfg: ProceduralAnimationConfig) -> Vector2:
	return (world - path_edit_target.get_rest_global_position()) / _path_scale(cfg) + start
