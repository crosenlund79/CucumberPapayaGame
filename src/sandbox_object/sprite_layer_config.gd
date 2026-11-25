@tool
class_name SpriteLayerConfig
extends Resource
## One sprite layer of a [SandboxObject]. Artwork is referenced by name only:
## custom/graphics/<art_name>.png overrides res://assets/graphics/template_<art_name>.png.

## Name used in the debug panel and by attachment points ([member AttachmentPointConfig.layer]).
@export var layer_name: StringName = &"layer":
	set(v): layer_name = v; emit_changed()
## Logical artwork name (file name without "template_" prefix and ".png").
@export var art_name: String = "":
	set(v): art_name = v; emit_changed()
## Where the pivot sits, in pixels relative to the object's origin.
@export var position: Vector2 = Vector2.ZERO:
	set(v): position = v; emit_changed()
## Pivot inside the image, normalized: (0.5, 0.5) = centre, (0.5, 1) = bottom centre.
## A custom image's JSON sidecar can override this.
@export var pivot: Vector2 = Vector2(0.5, 0.5):
	set(v): pivot = v; emit_changed()
@export var rotation_degrees: float = 0.0:
	set(v): rotation_degrees = v; emit_changed()
@export var scale: Vector2 = Vector2.ONE:
	set(v): scale = v; emit_changed()
## Draw order inside the object (higher = in front). Added to the object's z index.
@export_range(-100, 100, 1) var z_index: int = 0:
	set(v): z_index = v; emit_changed()
@export var modulate: Color = Color.WHITE:
	set(v): modulate = v; emit_changed()
@export var visible: bool = true:
	set(v): visible = v; emit_changed()
## Takes part in collision detection and mouse picking.
@export var collides: bool = true:
	set(v): collides = v; emit_changed()
## Optional animation of this layer around its pivot (e.g. an arm swing).
@export var animation: ProceduralAnimationConfig:
	set(v): animation = v; emit_changed()
