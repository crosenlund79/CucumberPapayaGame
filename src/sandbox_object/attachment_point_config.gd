@tool
class_name AttachmentPointConfig
extends Resource
## One named attachment point on a [SandboxObject].

@export var point_name: StringName = &"point":
	set(v): point_name = v; emit_changed()
## Pixels relative to the object's origin, or to the layer's pivot if [member layer] is set.
@export var position: Vector2 = Vector2.ZERO:
	set(v): position = v; emit_changed()
@export var rotation_degrees: float = 0.0:
	set(v): rotation_degrees = v; emit_changed()
## Optional layer name: the point then follows that layer (and its animation).
@export var layer: StringName = &"":
	set(v): layer = v; emit_changed()
