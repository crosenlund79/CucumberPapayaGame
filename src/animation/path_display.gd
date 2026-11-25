class_name PathDisplay
extends Node2D
## Draws the PATH of one ProceduralAnimator in world space (debug overlay).

var animator: ProceduralAnimator
const LINE_COLOR := Color(0.4, 0.85, 1.0, 0.9)
const POINT_COLOR := Color(1.0, 1.0, 1.0)


func _ready() -> void:
	z_index = SandboxObject.OVERLAY_Z
	z_as_relative = false


func _process(_delta: float) -> void:
	queue_redraw()


## World positions of the path points (as the animation will use them).
static func world_points(anim: ProceduralAnimator) -> PackedVector2Array:
	var result := PackedVector2Array()
	if anim == null or anim.config == null or anim.config.path_points.is_empty():
		return result
	var pts := anim.config.path_points
	var base := anim.get_rest_global_position()
	for p in pts:
		result.append(base + (p - pts[0]) * anim.config.movement_range)
	return result


func _draw() -> void:
	if not is_instance_valid(animator) or not animator.is_inside_tree():
		return
	var pts := world_points(animator)
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var radius := 5.0 / maxf(zoom, 0.01)
	if pts.size() >= 2:
		var line := pts.duplicate()
		if animator.config.path_closed:
			line.append(pts[0])
		draw_polyline(line, LINE_COLOR, 2.0 / maxf(zoom, 0.01))
	for i in pts.size():
		draw_circle(pts[i], radius * (1.4 if i == 0 else 1.0), POINT_COLOR if i > 0 else LINE_COLOR)
