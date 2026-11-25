class_name SandboxMain
extends Node3D
## Wires the sandbox together and owns the global actions/hotkeys.
## Every SandboxObject placed under "Objects" is picked up automatically.

@export var show_attachment_points: bool = true
@export var show_collision_shapes: bool = false

var objects: Array[SandboxObject] = []

@onready var camera: OrbitCamera = $OrbitCamera
@onready var manipulator: ObjectManipulator = $ObjectManipulator
@onready var panel: DebugPanel = $UI/DebugPanel
@onready var objects_root: Node3D = $Objects


func _ready() -> void:
	for child in objects_root.get_children():
		if child is SandboxObject:
			objects.append(child)
	manipulator.objects = objects
	set_show_attachment_points(show_attachment_points)
	set_show_collision_shapes(show_collision_shapes)
	panel.setup(self)


func any_playing() -> bool:
	for o in objects:
		if o.animator.playing:
			return true
	return false


func play_all() -> void:
	for o in objects:
		o.animator.play()


func pause_all() -> void:
	for o in objects:
		o.animator.pause()


func toggle_all() -> void:
	if any_playing():
		pause_all()
	else:
		play_all()


func reset_all_animations() -> void:
	for o in objects:
		o.animator.reset()


func reset_all_transforms() -> void:
	for o in objects:
		o.detach()
	for o in objects:
		o.reset_transform()


func set_global_speed(value: float) -> void:
	ProceduralAnimator.global_speed_scale = value


func set_show_attachment_points(value: bool) -> void:
	show_attachment_points = value
	for o in objects:
		o.set_show_attachment_points(value)


func set_show_collision_shapes(value: bool) -> void:
	show_collision_shapes = value
	for o in objects:
		o.set_show_collision_shape(value)


func focus_selected() -> void:
	var sel := manipulator.selected
	camera.focus(sel.get_world_center() if sel != null else Vector3(0, 0.8, 0))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			toggle_all()
		KEY_BACKSPACE:
			reset_all_animations()
		KEY_P:
			if manipulator.selected != null:
				manipulator.selected.animator.toggle()
		KEY_F:
			focus_selected()
		KEY_HOME:
			camera.reset_view()
		KEY_F1:
			panel.visible = not panel.visible
		_:
			return
	get_viewport().set_input_as_handled()
