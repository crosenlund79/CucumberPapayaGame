@tool
class_name ProceduralAnimator
extends Node3D
## Plays a [ProceduralAnimationConfig] by writing a local offset transform to
## this node every frame.
##
## The parent [SandboxObject] keeps the user-placed base transform, so the
## animation never overwrites manual positioning: rest pose = identity.
## Progress is tracked in cycles, so changing speed never makes the motion jump.

signal state_changed

## Multiplies the speed of every animator (debug panel "Global speed").
static var global_speed_scale: float = 1.0

var config: ProceduralAnimationConfig
## Node to move toward in APPROACH mode (optional).
var target: Node3D
## Animation progress in cycles.
var cycles: float = 0.0
var playing: bool = false


## Uses a private copy of [param cfg] so runtime tweaks never leak into the
## shared .tres file or into other objects using the same resource.
func setup(cfg: ProceduralAnimationConfig, approach_target: Node3D) -> void:
	config = cfg.duplicate() if cfg != null else ProceduralAnimationConfig.new()
	target = approach_target
	cycles = 0.0
	playing = config.autoplay and not Engine.is_editor_hint()
	_apply()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not playing or config == null:
		return
	cycles += delta * config.speed * global_speed_scale
	if not config.loop and cycles >= config.cycles_when_not_looping:
		cycles = float(config.cycles_when_not_looping)
		playing = false
		state_changed.emit()
	_apply()


func play() -> void:
	if config == null:
		return
	if not config.loop and cycles >= config.cycles_when_not_looping:
		cycles = 0.0
	playing = true
	state_changed.emit()


func pause() -> void:
	playing = false
	state_changed.emit()


func toggle() -> void:
	if playing:
		pause()
	else:
		play()


## Stops playback and returns to the rest pose. Play starts again from cycle 0.
func reset() -> void:
	playing = false
	cycles = 0.0
	transform = Transform3D.IDENTITY
	state_changed.emit()


func set_mode(new_mode: ProceduralAnimationConfig.Mode) -> void:
	config.mode = new_mode
	_apply()


func _apply() -> void:
	if config != null:
		transform = sample(cycles)


## Local offset transform at the given progress (in cycles).
func sample(at_cycles: float) -> Transform3D:
	var t := Transform3D.IDENTITY
	if config == null:
		return t
	var c := at_cycles + config.phase_offset
	var phase := c * TAU
	var r := config.movement_range
	var ax := config.axis.normalized() if config.axis.length() > 0.0001 else Vector3.UP
	match config.mode:
		ProceduralAnimationConfig.Mode.BOB:
			t.origin = _metres_to_local(ax * sin(phase) * r)
		ProceduralAnimationConfig.Mode.SWAY:
			t.basis = Basis(ax, deg_to_rad(sin(phase) * r))
		ProceduralAnimationConfig.Mode.SPIN:
			t.basis = Basis(ax, deg_to_rad(fmod(c * r, 360.0)))
		ProceduralAnimationConfig.Mode.ORBIT:
			var helper := Vector3.FORWARD if absf(ax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
			var u := ax.cross(helper).normalized()
			var v := ax.cross(u)
			t.origin = _metres_to_local((u * (cos(phase) - 1.0) + v * sin(phase)) * r)
		ProceduralAnimationConfig.Mode.PULSE:
			t.basis = Basis.from_scale(Vector3.ONE * maxf(0.01, 1.0 + sin(phase) * r))
		ProceduralAnimationConfig.Mode.HOP:
			t.origin = _metres_to_local(ax * absf(sin(phase * 0.5)) * r)
		ProceduralAnimationConfig.Mode.WADDLE:
			t.origin = _metres_to_local(ax * absf(sin(phase)) * r)
			t.basis = Basis(Vector3.BACK, deg_to_rad(sin(phase) * r * 60.0))
		ProceduralAnimationConfig.Mode.APPROACH:
			# Smooth 0 -> 1 -> 0 over one cycle.
			var amount := (0.5 - 0.5 * cos(phase)) * r
			t.origin = _approach_direction(ax) * amount
	return t


## Converts an offset given in metres (in the parent's rotated frame) into the
## parent's local space, cancelling the parent's own scale. This keeps
## "movement range" in real metres even after the object is scaled.
func _metres_to_local(offset: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	if parent == null:
		return offset
	var s := parent.scale
	return Vector3(
		offset.x / s.x if absf(s.x) > 0.0001 else 0.0,
		offset.y / s.y if absf(s.y) > 0.0001 else 0.0,
		offset.z / s.z if absf(s.z) > 0.0001 else 0.0)


## Unit direction toward the target on the ground plane, in parent-local space
## (one local unit along it = one metre in the world).
func _approach_direction(fallback_axis: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	if target == null or parent == null or not is_inside_tree() or not target.is_inside_tree():
		return _metres_to_local(fallback_axis)
	var to_target := target.global_position - parent.global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return Vector3.ZERO
	return parent.global_basis.inverse() * to_target.normalized()
