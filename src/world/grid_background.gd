extends Node2D
## Neutral reference grid (minor/major lines, x/y axes). Drawn once.

@export var extent: float = 4000.0
@export var minor_step: float = 50.0
@export var major_every: int = 5
@export var minor_color: Color = Color(1, 1, 1, 0.05)
@export var major_color: Color = Color(1, 1, 1, 0.11)
@export var x_axis_color: Color = Color(0.85, 0.35, 0.35, 0.5)
@export var y_axis_color: Color = Color(0.35, 0.5, 0.9, 0.5)


func _draw() -> void:
	var count := int(extent / minor_step)
	for i in range(-count, count + 1):
		var v := i * minor_step
		var color := major_color if i % major_every == 0 else minor_color
		draw_line(Vector2(v, -extent), Vector2(v, extent), color, -1.0)
		draw_line(Vector2(-extent, v), Vector2(extent, v), color, -1.0)
	draw_line(Vector2(-extent, 0), Vector2(extent, 0), x_axis_color, 2.0)
	draw_line(Vector2(0, -extent), Vector2(0, extent), y_axis_color, 2.0)
