@tool
class_name SandboxObject
extends Node3D
## A configurable placeholder object for the interaction sandbox.
##
## Everything is set in the Inspector; internals are generated in code:
##   SandboxObject      base transform (edited with the mouse / debug panel)
##   └ Animator         ProceduralAnimator offset (rest pose = identity)
##       ├ Visual       model: runtime custom GLB > model_scene > placeholder_mesh
##       ├ AttachmentPoints
##       ├ Area/Shape   picking + collision detection (runtime only)
##       └ debug lines  selection box, collision shape (runtime only)
## Add more objects by adding a SandboxObject node under "Objects" in main.tscn.

signal collision_started(other: SandboxObject)
signal collision_ended(other: SandboxObject)

const PICK_LAYER := 2 ## Physics layer "sandbox_objects".
const SELECTION_COLOR := Color(1.0, 0.85, 0.2)
const SHAPE_COLOR := Color(0.3, 1.0, 0.5)
const COLLIDING_COLOR := Color(1.0, 0.25, 0.25)
const POINT_COLOR := Color(1.0, 0.55, 0.1)

@export var display_name: String = "Object"

@export_group("Model")
## Primitive placeholder (a .tres under res://assets/meshes/).
@export var placeholder_mesh: Mesh:
	set(value):
		if placeholder_mesh != null and placeholder_mesh.changed.is_connected(_queue_rebuild):
			placeholder_mesh.changed.disconnect(_queue_rebuild)
		placeholder_mesh = value
		if Engine.is_editor_hint() and value != null and not value.changed.is_connected(_queue_rebuild):
			value.changed.connect(_queue_rebuild)
		_queue_rebuild()
## Material for the placeholder mesh (a .tres under res://assets/materials/).
@export var material: Material:
	set(value):
		material = value
		_queue_rebuild()
## Imported GLB/glTF scene. Replaces the placeholder mesh when set.
@export var model_scene: PackedScene:
	set(value):
		model_scene = value
		_queue_rebuild()
## Logical name for a runtime drop-in model: custom/graphics/<name>.glb or .gltf
## (next to the exported .exe, or res://custom in the editor). Wins over model_scene.
@export var override_name: String = ""
## Fine-tune a replacement model: offset/rotation/scale of the model inside the object.
@export var model_offset: Vector3 = Vector3.ZERO:
	set(value):
		model_offset = value
		_queue_rebuild()
@export var model_rotation_degrees: Vector3 = Vector3.ZERO:
	set(value):
		model_rotation_degrees = value
		_queue_rebuild()
@export var model_scale: Vector3 = Vector3.ONE:
	set(value):
		model_scale = value
		_queue_rebuild()
## Shift the model so its lowest point sits on the object's origin (the "feet").
@export var align_bottom_to_origin: bool = true:
	set(value):
		align_bottom_to_origin = value
		_queue_rebuild()

@export_group("Collision")
## Custom collision shape (centred on the model bounds). Empty = auto-fit box.
@export var collision_shape: Shape3D:
	set(value):
		collision_shape = value
		_queue_rebuild()
## Extra margin added to the auto-fitted box (metres per side).
@export_range(0.0, 1.0, 0.01) var collision_padding: float = 0.0:
	set(value):
		collision_padding = value
		_queue_rebuild()

@export_group("Animation")
## Procedural animation (a .tres under res://assets/animations/).
@export var animation: ProceduralAnimationConfig
## Object to walk toward in APPROACH mode.
@export var interaction_target: Node3D

@export_group("Attachment Points")
@export var attachment_points: Array[AttachmentPointConfig] = []:
	set(value):
		attachment_points = value
		if Engine.is_editor_hint():
			for cfg in attachment_points:
				if cfg != null and not cfg.changed.is_connected(_queue_rebuild):
					cfg.changed.connect(_queue_rebuild)
		_queue_rebuild()

## Human-readable description of where the current model came from.
var model_source: String = "placeholder"
var colliding_with: Array[SandboxObject] = []
var attached_to: SandboxObject = null
var attached_point: StringName = &""
var attached_own_point: StringName = &""
var animator: ProceduralAnimator

var _visual: Node3D
var _points_root: Node3D
var _area: Area3D
var _shape: CollisionShape3D
var _selection_box: MeshInstance3D
var _shape_debug: MeshInstance3D
var _markers: Dictionary = {} # StringName -> Marker3D
var _anchors: Array[Node] = [] # BoneAttachment3D helpers we created
var _home_parent: Node
var _home_transform: Transform3D
var _selected: bool = false
var _show_shape: bool = false
var _show_points: bool = true
var _rebuild_queued: bool = false

static var _material_cache: Dictionary = {}


func _ready() -> void:
	animator = ProceduralAnimator.new()
	animator.name = "Animator"
	add_child(animator, false, Node.INTERNAL_MODE_BACK)
	_visual = _make_child(animator, Node3D.new(), "Visual")
	_points_root = _make_child(animator, Node3D.new(), "AttachmentPoints")
	if not Engine.is_editor_hint():
		_home_parent = get_parent()
		_home_transform = transform
		_build_runtime_nodes()
		animator.setup(animation, interaction_target)
	_rebuild()


# --- Public API ---------------------------------------------------------------

func get_attachment_point_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for key in _markers.keys():
		names.append(key)
	return names


func get_attachment_marker(point: StringName) -> Marker3D:
	var marker: Variant = _markers.get(point)
	return marker if is_instance_valid(marker) else null


## Model bounds in object space (unaffected by the current animation offset).
func get_visual_aabb() -> AABB:
	var result := AABB()
	var first := true
	if _visual == null:
		return result
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = _relative_transform(mi, animator) * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## World-space centre of the model, including the animation offset.
func get_world_center() -> Vector3:
	return animator.global_transform * get_visual_aabb().get_center()


## Snaps this object onto [param point] of [param other]. If [param own_point]
## is given, that point of this object is aligned with the target point
## (e.g. a prop's "grip" to a character's "hand_r"). World scale is preserved.
func attach_to(other: SandboxObject, point: StringName, own_point: StringName = &"") -> bool:
	var marker := other.get_attachment_marker(point) if other != null else null
	if marker == null or other == self or is_ancestor_of(other):
		push_warning("%s: cannot attach to %s / %s." % [display_name, other.display_name if other else "?", point])
		return false
	if attached_to != null:
		detach()
	var world_scale := global_basis.get_scale()
	var rel := Transform3D.IDENTITY
	var own_marker := get_attachment_marker(own_point) if own_point != &"" else null
	if own_marker != null:
		rel = _relative_transform(own_marker, animator)
	reparent(marker, true)
	var target := marker.global_transform.orthonormalized()
	var b := (target.basis * rel.basis.orthonormalized().inverse()) * Basis.from_scale(world_scale)
	global_transform = Transform3D(b, target.origin - b * rel.origin)
	attached_to = other
	attached_point = point
	attached_own_point = own_point if own_marker != null else &""
	_update_debug_visibility()
	other._update_debug_visibility()
	return true


## Releases this object back into the scene, keeping its current world transform.
func detach() -> void:
	if attached_to == null:
		return
	var previous := attached_to
	reparent(_home_parent, true)
	attached_to = null
	attached_point = &""
	attached_own_point = &""
	_update_debug_visibility()
	previous._update_debug_visibility()


## Back to the transform (and parent) the object had when the sandbox started.
func reset_transform() -> void:
	detach()
	transform = _home_transform


func is_colliding_with(other: SandboxObject) -> bool:
	return colliding_with.has(other)


## True if one of the two objects is attached directly to the other. Such
## contact is intentional, so it is reported but not highlighted in red.
func is_attachment_pair(other: SandboxObject) -> bool:
	return other != null and (attached_to == other or other.attached_to == self)


## Immediate shape query (used to block overlaps while dragging): other
## sandbox objects currently intersecting this object's collision shape.
func query_overlaps() -> Array[SandboxObject]:
	var result: Array[SandboxObject] = []
	if _shape == null or _shape.shape == null or not is_inside_tree():
		return result
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape.shape
	params.transform = _shape.global_transform
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = PICK_LAYER
	params.exclude = [_area.get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(params, 16):
		var other := find_owner_object(hit["collider"])
		if other != null and other != self and not result.has(other):
			result.append(other)
	return result


func set_selected(value: bool) -> void:
	_selected = value
	_update_debug_visibility()


func set_show_collision_shape(value: bool) -> void:
	_show_shape = value
	_update_debug_visibility()


func set_show_attachment_points(value: bool) -> void:
	_show_points = value
	for marker: Marker3D in _markers.values():
		if is_instance_valid(marker):
			for child in marker.get_children():
				(child as Node3D).visible = value


## The SandboxObject that owns [param node] (walks up the tree), or null.
static func find_owner_object(node: Node) -> SandboxObject:
	while node != null:
		if node is SandboxObject:
			return node
		node = node.get_parent()
	return null


# --- Building ---------------------------------------------------------------------

func _queue_rebuild() -> void:
	if not is_node_ready() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if _visual == null: # e.g. tool script reloaded in the editor
		return
	_release_attached_children()
	_build_model()
	_build_attachment_points()
	if not Engine.is_editor_hint():
		_fit_collision()
		_update_debug_visibility()


func _build_model() -> void:
	for child in _visual.get_children():
		_visual.remove_child(child)
		child.queue_free()
	_visual.transform = Transform3D(
		Basis.from_euler(model_rotation_degrees * (PI / 180.0)) * Basis.from_scale(model_scale),
		model_offset)

	var model: Node3D = null
	model_source = "placeholder"
	if not Engine.is_editor_hint() and not override_name.is_empty():
		model = ModelResolver.load_model_override(override_name)
		if model != null:
			model_source = "custom/%s/%s" % [ModelResolver.SUBFOLDER, ModelResolver.find_override_path(override_name).get_file()]
	if model == null and model_scene != null:
		var instance := model_scene.instantiate()
		if instance is Node3D:
			model = instance
			model_source = "model_scene " + model_scene.resource_path.get_file()
		elif instance != null:
			push_warning("%s: model_scene root is not a 3D node; using placeholder." % display_name)
			instance.free()
	if model == null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = placeholder_mesh if placeholder_mesh != null else BoxMesh.new()
		mesh_instance.material_override = material
		model = mesh_instance
	model.name = "Model"
	_visual.add_child(model)

	if align_bottom_to_origin:
		var aabb := get_visual_aabb()
		if aabb.size != Vector3.ZERO:
			_visual.position.y += model_offset.y - aabb.position.y


func _build_attachment_points() -> void:
	for marker: Variant in _markers.values():
		if is_instance_valid(marker):
			marker.get_parent().remove_child(marker)
			marker.queue_free()
	_markers.clear()
	for anchor in _anchors:
		if is_instance_valid(anchor):
			anchor.queue_free()
	_anchors.clear()

	for cfg in attachment_points:
		if cfg == null or _markers.has(cfg.point_name):
			continue
		var marker := Marker3D.new()
		marker.name = String(cfg.point_name)
		marker.position = cfg.position
		marker.rotation_degrees = cfg.rotation_degrees
		marker.gizmo_extents = 0.12
		_find_anchor(cfg.model_node).add_child(marker)
		_add_point_gizmo(marker, cfg.point_name)
		_markers[cfg.point_name] = marker


## Parent for an attachment point: a named node or skeleton bone inside the
## model if requested and found, otherwise object space.
func _find_anchor(model_node: String) -> Node3D:
	if model_node.is_empty():
		return _points_root
	var model := _visual.get_node_or_null("Model")
	if model != null:
		var found := model.find_child(model_node, true, false)
		if found is Node3D:
			return found
		for skeleton: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
			if skeleton.find_bone(model_node) >= 0:
				var bone_attachment := BoneAttachment3D.new()
				bone_attachment.bone_name = model_node
				skeleton.add_child(bone_attachment)
				_anchors.append(bone_attachment)
				return bone_attachment
	if not Engine.is_editor_hint() or model_scene != null:
		push_warning("%s: model node/bone '%s' not found; attachment point uses object space." % [display_name, model_node])
	return _points_root


func _add_point_gizmo(marker: Marker3D, point_name: StringName) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	var dot := MeshInstance3D.new()
	dot.mesh = sphere
	dot.material_override = _debug_material(POINT_COLOR, 1.0)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(dot)
	var label := Label3D.new()
	label.text = String(point_name)
	label.font_size = 28
	label.outline_size = 6
	label.pixel_size = 0.0025
	label.position = Vector3(0, 0.07, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = POINT_COLOR
	marker.add_child(label)
	dot.visible = _show_points
	label.visible = _show_points


func _build_runtime_nodes() -> void:
	_area = _make_child(animator, Area3D.new(), "Area")
	_area.collision_layer = PICK_LAYER
	_area.collision_mask = PICK_LAYER
	_shape = _make_child(_area, CollisionShape3D.new(), "Shape")
	_area.area_entered.connect(_on_area_entered)
	_area.area_exited.connect(_on_area_exited)
	_selection_box = _make_child(animator, MeshInstance3D.new(), "SelectionBox")
	_selection_box.material_override = _debug_material(SELECTION_COLOR, 1.0)
	_selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shape_debug = _make_child(animator, MeshInstance3D.new(), "ShapeDebug")
	_shape_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _fit_collision() -> void:
	var aabb := get_visual_aabb()
	if collision_shape != null:
		_shape.shape = collision_shape
	else:
		var box := BoxShape3D.new()
		box.size = (aabb.size + Vector3.ONE * collision_padding * 2.0).clamp(Vector3.ONE * 0.01, Vector3.ONE * 1000.0)
		_shape.shape = box
	_shape.position = aabb.get_center()
	_shape_debug.mesh = _shape.shape.get_debug_mesh()
	_shape_debug.position = _shape.position
	_selection_box.mesh = _box_lines(aabb.grow(0.03))


func _update_debug_visibility() -> void:
	if _selection_box == null:
		return
	_selection_box.visible = _selected
	var colliding := false
	for other in colliding_with:
		if not is_attachment_pair(other):
			colliding = true
	_shape_debug.visible = _show_shape or colliding
	_shape_debug.material_override = _debug_material(COLLIDING_COLOR if colliding else SHAPE_COLOR, 0.3)


## Detaches objects that are attached to this object's points before the
## points are rebuilt, so they are not freed together with the markers.
func _release_attached_children() -> void:
	for marker: Variant in _markers.values():
		if not is_instance_valid(marker):
			continue
		for child in marker.get_children():
			if child is SandboxObject:
				(child as SandboxObject).detach()


func _on_area_entered(area: Area3D) -> void:
	var other := find_owner_object(area)
	if other == null or other == self or colliding_with.has(other):
		return
	colliding_with.append(other)
	_update_debug_visibility()
	collision_started.emit(other)


func _on_area_exited(area: Area3D) -> void:
	var other := find_owner_object(area)
	if other == null or not colliding_with.has(other):
		return
	colliding_with.erase(other)
	_update_debug_visibility()
	collision_ended.emit(other)


# --- Helpers ------------------------------------------------------------------------

func _make_child(parent: Node, child: Node, child_name: String) -> Node:
	child.name = child_name
	parent.add_child(child)
	return child


## Transform of [param node] relative to [param ancestor] (works outside the tree).
static func _relative_transform(node: Node, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var current := node
	while current != null and current != ancestor:
		if current is Node3D:
			t = (current as Node3D).transform * t
		current = current.get_parent()
	return t


static func _box_lines(aabb: AABB) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 8:
		for bit in [1, 2, 4]:
			var j: int = i | bit
			if j != i:
				mesh.surface_add_vertex(aabb.get_endpoint(i))
				mesh.surface_add_vertex(aabb.get_endpoint(j))
	mesh.surface_end()
	return mesh


## Unshaded overlay material. Opaque ones draw on top of everything (lines,
## point dots); translucent ones (collision shape fill) keep the depth test.
static func _debug_material(color: Color, alpha: float) -> StandardMaterial3D:
	var key := Color(color, alpha)
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = key
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		mat.no_depth_test = true
	_material_cache[key] = mat
	return mat
