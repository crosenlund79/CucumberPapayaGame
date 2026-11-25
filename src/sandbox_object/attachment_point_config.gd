@tool
class_name AttachmentPointConfig
extends Resource
## One named attachment point on a [SandboxObject].
##
## Position/rotation are in object space: origin = the object's base (the
## model is aligned so its bottom sits on the origin), -Z = forward, +X = right.

## Name shown in the debug panel and used by [method SandboxObject.attach_to].
@export var point_name: StringName = &"point":
	set(value):
		point_name = value
		emit_changed()
@export var position: Vector3 = Vector3.ZERO:
	set(value):
		position = value
		emit_changed()
@export var rotation_degrees: Vector3 = Vector3.ZERO:
	set(value):
		rotation_degrees = value
		emit_changed()
## Optional: name of a node or skeleton bone inside a replacement GLB/glTF
## model. If found, the point follows that node/bone and [member position] /
## [member rotation_degrees] become an offset relative to it.
@export var model_node: String = "":
	set(value):
		model_node = value
		emit_changed()
