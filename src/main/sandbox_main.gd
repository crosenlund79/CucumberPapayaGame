class_name SandboxMain
extends Node2D
## Wires the sandbox together and owns the global actions/hotkeys.
## Every SandboxObject placed under "Objects" is picked up automatically.

@export var show_points: bool = true
@export var show_collision_shapes: bool = false

var objects: Array[SandboxObject] = []

@onready var camera: PanZoomCamera = $Camera
@onready var manipulator: ObjectManipulator = $ObjectManipulator
@onready var path_display: PathDisplay = $PathDisplay
@onready var panel: DebugPanel = $UI/DebugPanel
@onready var objects_root: Node2D = $Objects


func _ready() -> void:
	for child in objects_root.get_children():
		if child is SandboxObject:
			objects.append(child)
	manipulator.objects = objects
	set_show_points(show_points)
	set_show_collision_shapes(show_collision_shapes)
	panel.setup(self)


## Every animator in the sandbox (objects and their layers).
func all_animators() -> Array[ProceduralAnimator]:
	var result: Array[ProceduralAnimator] = []
	for o in objects:
		result.append(o.animator)
		for st in o.layer_states:
			result.append(st.animator)
	return result


func any_playing() -> bool:
	for a in all_animators():
		if a.playing:
			return true
	return false


func play_all() -> void:
	for a in all_animators():
		if a.config.mode != ProceduralAnimationConfig.Mode.NONE:
			a.play()


func pause_all() -> void:
	for a in all_animators():
		a.pause()


func toggle_all() -> void:
	if any_playing():
		pause_all()
	else:
		play_all()


func reset_all_animations() -> void:
	for a in all_animators():
		a.reset()


func reset_all_transforms() -> void:
	for o in objects:
		o.detach()
	for o in objects:
		o.reset_transform()


func set_global_speed(value: float) -> void:
	ProceduralAnimator.global_speed_scale = value


func set_y_sort(enabled: bool) -> void:
	objects_root.y_sort_enabled = enabled


func set_show_points(value: bool) -> void:
	show_points = value
	for o in objects:
		o.set_show_points(value)


func set_show_collision_shapes(value: bool) -> void:
	show_collision_shapes = value
	for o in objects:
		o.set_show_collision_shapes(value)


func focus_selected() -> void:
	var sel := manipulator.selected
	camera.focus(sel.get_world_center() if sel != null else Vector2.ZERO)


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
