class_name PanZoomCamera
extends Camera2D
## Middle- or right-drag pans, mouse wheel zooms toward the cursor,
## touchpad two-finger scroll pans and pinch zooms.

@export var min_zoom: float = 0.1
@export var max_zoom: float = 8.0
## Zoom factor per wheel step.
@export var zoom_step: float = 1.15

var _panning: bool = false
var _home_position: Vector2
var _home_zoom: Vector2


func _ready() -> void:
	_home_position = position
	_home_zoom = zoom


func focus(point: Vector2) -> void:
	position = point


func reset_view() -> void:
	position = _home_position
	zoom = _home_zoom


func zoom_at(factor: float, screen_point: Vector2) -> void:
	var center := get_viewport_rect().size * 0.5
	var world_before := position + (screen_point - center) / zoom.x
	var new_zoom := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2.ONE * new_zoom
	position = world_before - (screen_point - center) / new_zoom


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(zoom_step, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(1.0 / zoom_step, mb.position)
			_:
				return
		get_viewport().set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _panning:
		position -= mm.relative / zoom.x
		get_viewport().set_input_as_handled()
		return
	var pan := event as InputEventPanGesture
	if pan != null:
		position += pan.delta * 20.0 / zoom.x
		get_viewport().set_input_as_handled()
		return
	var magnify := event as InputEventMagnifyGesture
	if magnify != null:
		zoom_at(magnify.factor, magnify.position)
		get_viewport().set_input_as_handled()
