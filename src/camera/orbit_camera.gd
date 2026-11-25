class_name OrbitCamera
extends Camera3D
## Orbit camera: right-drag (or Alt+left-drag) orbits, middle-drag (or
## Shift+right-drag) pans, mouse wheel / touchpad zooms. All tuning values are
## exposed in the Inspector.

@export var target: Vector3 = Vector3(0, 0.8, 0)
@export_range(0.1, 200.0, 0.1) var distance: float = 7.0
@export_range(-89.0, 89.0, 0.1) var pitch_degrees: float = -22.0
@export var yaw_degrees: float = 25.0

@export_group("Limits")
@export var min_distance: float = 0.5
@export var max_distance: float = 60.0
@export_range(-89.0, 89.0, 0.1) var min_pitch_degrees: float = -89.0
@export_range(-89.0, 89.0, 0.1) var max_pitch_degrees: float = 60.0

@export_group("Feel")
## Degrees per pixel of mouse movement.
@export var orbit_sensitivity: float = 0.3
@export var pan_sensitivity: float = 1.0
## Fraction of the distance per wheel step.
@export_range(0.01, 0.5, 0.01) var zoom_step: float = 0.12
## Higher = snappier. 0 = no smoothing.
@export_range(0.0, 40.0, 0.5) var smoothing: float = 14.0

var _home: Array = []
var _orbiting: bool = false
var _panning: bool = false
var _cur_target: Vector3
var _cur_distance: float
var _cur_yaw: float
var _cur_pitch: float


func _ready() -> void:
	_home = [target, distance, yaw_degrees, pitch_degrees]
	_snap_to_goal()


func focus(point: Vector3) -> void:
	target = point


func reset_view() -> void:
	target = _home[0]
	distance = _home[1]
	yaw_degrees = _home[2]
	pitch_degrees = _home[3]


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed and not mb.shift_pressed
				_panning = mb.pressed and mb.shift_pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_LEFT:
				# Alt+left: laptop-friendly orbit. Released always stops it.
				_orbiting = mb.pressed and mb.alt_pressed
				if not _orbiting:
					return
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(-1.0 * mb.factor if mb.factor > 0.0 else -1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(mb.factor if mb.factor > 0.0 else 1.0)
			_:
				return
		get_viewport().set_input_as_handled()
		return

	var mm := event as InputEventMouseMotion
	if mm != null and (_orbiting or _panning):
		if _orbiting:
			yaw_degrees -= mm.relative.x * orbit_sensitivity
			pitch_degrees = clampf(pitch_degrees - mm.relative.y * orbit_sensitivity, min_pitch_degrees, max_pitch_degrees)
		else:
			var k := distance * 0.0016 * pan_sensitivity
			var basis_now := _goal_basis()
			target += (-basis_now.x * mm.relative.x + basis_now.y * mm.relative.y) * k
		get_viewport().set_input_as_handled()
		return

	var pan := event as InputEventPanGesture # touchpad two-finger scroll
	if pan != null:
		_zoom(pan.delta.y)
		get_viewport().set_input_as_handled()
		return

	var magnify := event as InputEventMagnifyGesture
	if magnify != null and magnify.factor > 0.0:
		distance = clampf(distance / magnify.factor, min_distance, max_distance)
		get_viewport().set_input_as_handled()


func _zoom(steps: float) -> void:
	distance = clampf(distance * pow(1.0 + zoom_step, steps), min_distance, max_distance)


func _process(delta: float) -> void:
	if smoothing <= 0.0:
		_snap_to_goal()
	else:
		var w := 1.0 - exp(-smoothing * delta)
		_cur_target = _cur_target.lerp(target, w)
		_cur_distance = lerpf(_cur_distance, distance, w)
		_cur_yaw = lerpf(_cur_yaw, yaw_degrees, w)
		_cur_pitch = lerpf(_cur_pitch, pitch_degrees, w)
	_apply()


func _snap_to_goal() -> void:
	_cur_target = target
	_cur_distance = distance
	_cur_yaw = yaw_degrees
	_cur_pitch = pitch_degrees
	_apply()


func _goal_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0))


func _apply() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(_cur_pitch), deg_to_rad(_cur_yaw), 0.0))
	global_transform = Transform3D(b, _cur_target + b * Vector3(0, 0, _cur_distance))
