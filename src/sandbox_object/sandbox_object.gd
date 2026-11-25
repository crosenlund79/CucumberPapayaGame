@tool
class_name SandboxObject
extends Node2D
## A configurable 2D object made of sprite layers. Everything is set in the
## Inspector; internal nodes are generated in code:
##   SandboxObject        base transform + z_index (edited by mouse / debug panel)
##   └ Animator           whole-object ProceduralAnimator (rest pose = identity)
##       ├ Layers/<name>  node at the layer pivot (position/rotation/scale/z)
##       │   └ Animator   per-layer ProceduralAnimator (e.g. arm swing)
##       │       ├ Sprite artwork (offset so the image pivot sits on the node)
##       │       └ points bound to this layer
##       └ Points         object-space attachment points
## The object's origin is its pivot for rotation/scale and the mouse tools.

signal collision_started(other: SandboxObject)
signal collision_ended(other: SandboxObject)

const PICK_LAYER := 2 ## Physics layer "sandbox_objects".
const OVERLAY_Z := 900 ## Absolute z for debug overlays.
const SELECTION_COLOR := Color(1.0, 0.85, 0.2)
const SHAPE_COLOR := Color(0.3, 1.0, 0.5)
const COLLIDING_COLOR := Color(1.0, 0.25, 0.25)
const POINT_COLOR := Color(1.0, 0.55, 0.1)
const PIVOT_COLOR := Color(0.3, 0.8, 1.0)

@export var display_name: String = "Object"
## Sprite layers, drawn by their z index (then list order).
@export var layers: Array[SpriteLayerConfig] = []:
	set(value):
		layers = value
		_watch_configs(layers)
		_queue_rebuild()

@export_group("Animation")
## Whole-object procedural animation (a .tres under res://assets/animations/).
@export var animation: ProceduralAnimationConfig
## Object to move toward in APPROACH mode.
@export var interaction_target: Node2D

@export_group("Attachment Points")
@export var attachment_points: Array[AttachmentPointConfig] = []:
	set(value):
		attachment_points = value
		_watch_configs(attachment_points)
		_queue_rebuild()

@export_group("Collision")
## Extra margin around each layer's opaque pixels (pixels).
@export_range(0.0, 64.0, 0.5) var collision_padding: float = 0.0
## Pixels more transparent than this are ignored by mouse picking.
@export_range(0.0, 1.0, 0.01) var pick_alpha_threshold: float = 0.1


## Runtime state of one layer.
class LayerState:
	var config: SpriteLayerConfig
	var node: Node2D
	var animator: ProceduralAnimator
	var sprite: Sprite2D
	var art: ArtResolver.Art
	var pivot: Vector2 ## effective normalized pivot (sidecar wins over config)
	var pixel_scale: float = 1.0
	var area: Area2D
	var shape: CollisionShape2D
	var outline: Line2D
	var pivot_dot: Polygon2D


var animator: ProceduralAnimator
var layer_states: Array[LayerState] = []
var colliding_with: Array[SandboxObject] = []
var attached_to: SandboxObject = null
var attached_point: StringName = &""

var _layers_root: Node2D
var _points_root: Node2D
var _selection_outline: Line2D
var _pivot_cross: Line2D
var _markers: Dictionary = {} # StringName -> Marker2D
var _home_parent: Node
var _home_transform: Transform2D
var _home_z: int = 0
var _selected: bool = false
var _show_shapes: bool = false
var _show_points: bool = true
var _rebuild_queued: bool = false


func _ready() -> void:
	animator = ProceduralAnimator.new()
	animator.name = "Animator"
	add_child(animator, false, Node.INTERNAL_MODE_BACK)
	if not Engine.is_editor_hint():
		_home_parent = get_parent()
		_home_transform = transform
		_home_z = z_index
		animator.setup(animation, interaction_target)
	_rebuild()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var now: Array[SandboxObject] = []
	for st in layer_states:
		if st.area == null:
			continue
		for area in st.area.get_overlapping_areas():
			var other := find_owner_object(area)
			if other != null and other != self and not now.has(other):
				now.append(other)
	if now == colliding_with:
		return
	var before := colliding_with
	colliding_with = now
	for other in now:
		if not before.has(other):
			collision_started.emit(other)
	for other in before:
		if not now.has(other):
			collision_ended.emit(other)
	update_debug_visibility()


# --- Public API ---------------------------------------------------------------

func get_layer_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for st in layer_states:
		names.append(st.config.layer_name)
	return names


func get_layer_state(layer_name: StringName) -> LayerState:
	for st in layer_states:
		if st.config.layer_name == layer_name:
			return st
	return null


func get_attachment_point_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for key in _markers.keys():
		names.append(key)
	return names


func get_attachment_marker(point: StringName) -> Marker2D:
	var marker: Variant = _markers.get(point)
	return marker if is_instance_valid(marker) else null


## Re-applies a layer's (edited) settings without rebuilding the object.
func refresh_layer(st: LayerState) -> void:
	var cfg := st.config
	st.node.position = cfg.position
	st.node.rotation_degrees = cfg.rotation_degrees
	st.node.scale = cfg.scale
	st.node.z_index = cfg.z_index
	st.node.visible = cfg.visible
	st.sprite.self_modulate = cfg.modulate
	var size := Vector2(st.art.image.get_size())
	var pivot_px := st.pivot * size
	st.sprite.offset = -pivot_px
	st.sprite.scale = Vector2.ONE * st.pixel_scale
	if st.shape != null:
		var used := Rect2(st.art.image.get_used_rect())
		var r := Rect2(used.position - pivot_px, used.size).grow(collision_padding)
		(st.shape.shape as RectangleShape2D).size = r.size.clamp(Vector2.ONE, Vector2(100000, 100000))
		st.shape.position = r.get_center()
		st.shape.set_deferred("disabled", not (cfg.visible and cfg.collides))
		st.outline.points = _rect_points(r)
	_update_selection_outline()
	update_debug_visibility()


## Object-space bounds of all visible layers at rest.
func get_bounds() -> Rect2:
	var result := Rect2()
	var first := true
	for st in layer_states:
		if not st.config.visible:
			continue
		var size := Vector2(st.art.image.get_size())
		var r: Rect2 = st.node.transform * st.sprite.transform * Rect2(-st.pivot * size, size)
		result = r if first else result.merge(r)
		first = false
	return result


func get_world_center() -> Vector2:
	return animator.global_transform * get_bounds().get_center()


## The topmost visible layer sprite with an opaque pixel under [param world_point], or null.
func hit_test(world_point: Vector2) -> Sprite2D:
	var best: Sprite2D = null
	for st in layer_states:
		if not st.config.visible:
			continue
		var image := st.art.image
		var px := Vector2i((st.sprite.to_local(world_point) - st.sprite.offset).floor())
		if px.x < 0 or px.y < 0 or px.x >= image.get_width() or px.y >= image.get_height():
			continue
		if image.get_pixelv(px).a < pick_alpha_threshold:
			continue
		if best == null or draws_above(st.sprite, best):
			best = st.sprite
	return best


## Snaps this object onto [param point] of [param other]. If [param own_point]
## is given, that point of this object is aligned with the target point
## (e.g. a prop's "grip" to a character's "hand"). World scale is preserved.
func attach_to(other: SandboxObject, point: StringName, own_point: StringName = &"") -> bool:
	var marker := other.get_attachment_marker(point) if other != null else null
	if marker == null or other == self or is_ancestor_of(other):
		push_warning("%s: cannot attach to %s / %s." % [display_name, other.display_name if other else "?", point])
		return false
	if attached_to != null:
		detach()
	var world_scale := global_scale
	var rel := Transform2D.IDENTITY
	var own_marker := get_attachment_marker(own_point) if own_point != &"" else null
	if own_marker != null:
		rel = _relative_transform(own_marker, animator)
	reparent(marker, true)
	var rot := marker.global_rotation - rel.get_rotation()
	var basis := Transform2D(rot, world_scale, 0.0, Vector2.ZERO)
	global_transform = Transform2D(rot, world_scale, 0.0, marker.global_position - basis.basis_xform(rel.origin))
	attached_to = other
	attached_point = point
	update_debug_visibility()
	other.update_debug_visibility()
	return true


## Releases this object back into the scene, keeping its current world transform.
func detach() -> void:
	if attached_to == null:
		return
	var previous := attached_to
	reparent(_home_parent, true)
	attached_to = null
	attached_point = &""
	update_debug_visibility()
	previous.update_debug_visibility()


## Back to the transform, draw order and parent the object had at start.
func reset_transform() -> void:
	detach()
	transform = _home_transform
	z_index = _home_z


func flip_horizontal() -> void:
	scale.x = -scale.x


func is_colliding_with(other: SandboxObject) -> bool:
	return colliding_with.has(other)


## True if one object is attached directly to the other (contact is intended,
## so it is reported but not highlighted in red).
func is_attachment_pair(other: SandboxObject) -> bool:
	return other != null and (attached_to == other or other.attached_to == self)


## Immediate overlap query (used to block overlaps while dragging).
func query_overlaps() -> Array[SandboxObject]:
	var result: Array[SandboxObject] = []
	if not is_inside_tree():
		return result
	var own: Array[RID] = []
	for st in layer_states:
		if st.area != null:
			own.append(st.area.get_rid())
	var space := get_world_2d().direct_space_state
	for st in layer_states:
		if st.shape == null or st.shape.disabled:
			continue
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = st.shape.shape
		params.transform = st.shape.global_transform
		params.collide_with_areas = true
		params.collide_with_bodies = false
		params.collision_mask = PICK_LAYER
		params.exclude = own
		for hit in space.intersect_shape(params, 16):
			var other := find_owner_object(hit["collider"])
			if other != null and other != self and not result.has(other):
				result.append(other)
	return result


func set_selected(value: bool) -> void:
	_selected = value
	update_debug_visibility()


func set_show_collision_shapes(value: bool) -> void:
	_show_shapes = value
	update_debug_visibility()


func set_show_points(value: bool) -> void:
	_show_points = value
	update_debug_visibility()


func update_debug_visibility() -> void:
	if _pivot_cross == null:
		return
	var colliding := false
	for other in colliding_with:
		if not is_attachment_pair(other):
			colliding = true
	for st in layer_states:
		if st.outline != null:
			st.outline.visible = (_show_shapes or colliding) and st.config.collides
			st.outline.default_color = COLLIDING_COLOR if colliding else SHAPE_COLOR
		if st.pivot_dot != null:
			st.pivot_dot.visible = _show_points
	if _selection_outline != null:
		_selection_outline.visible = _selected
	_pivot_cross.visible = _show_points or _selected
	for marker: Variant in _markers.values():
		if is_instance_valid(marker):
			for child in marker.get_children():
				if not child is SandboxObject:
					child.visible = _show_points


## The SandboxObject that owns [param node] (walks up the tree), or null.
static func find_owner_object(node: Node) -> SandboxObject:
	while node != null:
		if node is SandboxObject:
			return node
		node = node.get_parent()
	return null


## Draw-order comparison: higher effective z wins, then later in the tree.
static func draws_above(a: CanvasItem, b: CanvasItem) -> bool:
	var za := effective_z(a)
	var zb := effective_z(b)
	if za != zb:
		return za > zb
	return a.is_greater_than(b)


static func effective_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		z += (node as CanvasItem).z_index
		if not (node as CanvasItem).z_as_relative:
			break
		node = node.get_parent()
	return z


# --- Building ---------------------------------------------------------------------

func _watch_configs(configs: Array) -> void:
	if not Engine.is_editor_hint():
		return
	for cfg: Resource in configs:
		if cfg != null and not cfg.changed.is_connected(_queue_rebuild):
			cfg.changed.connect(_queue_rebuild)


func _queue_rebuild() -> void:
	if not is_node_ready() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if animator == null: # e.g. tool script reloaded in the editor
		return
	# Objects attached to our points must survive the rebuild.
	for marker: Variant in _markers.values():
		if is_instance_valid(marker):
			for child in marker.get_children():
				if child is SandboxObject:
					(child as SandboxObject).detach()
	for child in animator.get_children():
		animator.remove_child(child)
		child.queue_free()
	_markers.clear()
	layer_states.clear()

	_layers_root = _make_child(animator, Node2D.new(), "Layers")
	_points_root = _make_child(animator, Node2D.new(), "Points")
	for cfg in layers:
		if cfg != null:
			layer_states.append(_build_layer(cfg))
	for cfg in attachment_points:
		if cfg != null and not _markers.has(cfg.point_name):
			_build_point(cfg)

	_pivot_cross = _make_overlay(Line2D.new(), animator, "PivotCross", PIVOT_COLOR)
	_pivot_cross.points = PackedVector2Array([Vector2(-14, 0), Vector2(14, 0), Vector2.ZERO, Vector2(0, -14), Vector2(0, 14)])
	if not Engine.is_editor_hint():
		_selection_outline = _make_overlay(Line2D.new(), animator, "SelectionOutline", SELECTION_COLOR)
	for st in layer_states:
		refresh_layer(st)
	update_debug_visibility()


func _build_layer(source: SpriteLayerConfig) -> LayerState:
	var st := LayerState.new()
	# Runtime edits (debug panel) go to a private copy, never to the scene file.
	st.config = source if Engine.is_editor_hint() else source.duplicate()
	st.node = _make_child(_layers_root, Node2D.new(), String(source.layer_name))
	st.animator = _make_child(st.node, ProceduralAnimator.new(), "Animator")
	if not Engine.is_editor_hint():
		st.animator.setup(source.animation, interaction_target)
	st.sprite = _make_child(st.animator, Sprite2D.new(), "Sprite")
	st.sprite.centered = false
	st.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	st.art = ArtResolver.resolve(source.art_name)
	st.sprite.texture = st.art.texture
	st.pivot = st.art.pivot if st.art.has_sidecar_pivot else source.pivot
	st.pixel_scale = st.art.pixel_scale
	st.pivot_dot = _make_overlay(Polygon2D.new(), st.node, "PivotDot", PIVOT_COLOR)
	st.pivot_dot.polygon = _circle_points(4.0)
	if not Engine.is_editor_hint():
		st.area = _make_child(st.sprite, Area2D.new(), "Area")
		st.area.collision_layer = PICK_LAYER
		st.area.collision_mask = PICK_LAYER
		st.shape = _make_child(st.area, CollisionShape2D.new(), "Shape")
		st.shape.shape = RectangleShape2D.new()
		st.outline = _make_overlay(Line2D.new(), st.sprite, "CollisionOutline", SHAPE_COLOR)
	return st


func _build_point(cfg: AttachmentPointConfig) -> void:
	var parent: Node2D = _points_root
	if cfg.layer != &"":
		var st := get_layer_state(cfg.layer)
		if st != null:
			parent = st.animator
		else:
			push_warning("%s: attachment point '%s' refers to unknown layer '%s'." % [display_name, cfg.point_name, cfg.layer])
	var marker := Marker2D.new()
	marker.name = String(cfg.point_name)
	marker.position = cfg.position
	marker.rotation_degrees = cfg.rotation_degrees
	marker.gizmo_extents = 12.0
	parent.add_child(marker)
	var diamond := _make_overlay(Polygon2D.new(), marker, "Gizmo", POINT_COLOR)
	diamond.polygon = PackedVector2Array([Vector2(0, -6), Vector2(6, 0), Vector2(0, 6), Vector2(-6, 0)])
	var label := Label.new()
	label.text = String(cfg.point_name)
	label.position = Vector2(8, -10)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", POINT_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = OVERLAY_Z
	label.z_as_relative = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(label)
	_markers[cfg.point_name] = marker


func _update_selection_outline() -> void:
	if _selection_outline != null:
		_selection_outline.points = _rect_points(get_bounds().grow(4.0))


# --- Helpers ------------------------------------------------------------------------

func _make_child(parent: Node, child: Node, child_name: String) -> Node:
	child.name = child_name
	parent.add_child(child)
	return child


func _make_overlay(item: CanvasItem, parent: Node, item_name: String, color: Color) -> CanvasItem:
	item.z_index = OVERLAY_Z
	item.z_as_relative = false
	if item is Line2D:
		(item as Line2D).width = 2.0
		(item as Line2D).default_color = color
	elif item is Polygon2D:
		(item as Polygon2D).color = color
	return _make_child(parent, item, item_name)


static func _relative_transform(node: Node, ancestor: Node) -> Transform2D:
	var t := Transform2D.IDENTITY
	var current := node
	while current != null and current != ancestor:
		if current is Node2D:
			t = (current as Node2D).transform * t
		current = current.get_parent()
	return t


static func _rect_points(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])


static func _circle_points(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(Vector2.from_angle(TAU * i / 10.0) * radius)
	return pts
