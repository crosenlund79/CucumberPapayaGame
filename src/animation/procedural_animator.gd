@tool
class_name ProceduralAnimator
extends Node2D
## Plays a [ProceduralAnimationConfig] by writing a local offset transform to
## this node every frame. The parent keeps the user-placed transform (rest pose
## = identity), so animation never overwrites manual positioning. Progress is
## tracked in cycles, so changing speed never makes the motion jump.

signal state_changed

## Multiplies the speed of every animator (debug panel "Speed ×").
static var global_speed_scale: float = 1.0

var config: ProceduralAnimationConfig
## Node to move toward in APPROACH mode (optional).
var target: Node2D
var cycles: float = 0.0
var playing: bool = false

var _curve: Curve2D
var _curve_points: PackedVector2Array
var _curve_closed: bool = false


## Uses a private copy of [param cfg] so runtime tweaks never leak into the
## shared .tres file or into other users of the same resource.
func setup(cfg: ProceduralAnimationConfig, approach_target: Node2D = null) -> void:
	config = cfg.duplicate() if cfg != null else ProceduralAnimationConfig.new()
	if cfg == null:
		config.mode = ProceduralAnimationConfig.Mode.NONE
	target = approach_target
	cycles = 0.0
	playing = config.autoplay and config.mode != ProceduralAnimationConfig.Mode.NONE and not Engine.is_editor_hint()
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


## Stops playback and returns to the rest pose. Play restarts from cycle 0.
func reset() -> void:
	playing = false
	cycles = 0.0
	transform = Transform2D.IDENTITY
	state_changed.emit()


func set_mode(new_mode: ProceduralAnimationConfig.Mode) -> void:
	config.mode = new_mode
	_apply()


## World position the path / approach motion is measured from (the rest pose).
func get_rest_global_position() -> Vector2:
	var parent := get_parent() as Node2D
	return parent.global_position if parent != null else global_position


func _apply() -> void:
	if config != null:
		transform = sample(cycles)


## Local offset transform at the given progress (in cycles).
func sample(at_cycles: float) -> Transform2D:
	if config == null:
		return Transform2D.IDENTITY
	var c := at_cycles + config.phase_offset
	var phase := c * TAU
	var r := config.movement_range
	var ax := config.axis.normalized() if config.axis.length() > 0.0001 else Vector2.UP
	var pos := Vector2.ZERO
	var rot := 0.0
	var scl := Vector2.ONE
	match config.mode:
		ProceduralAnimationConfig.Mode.BOB:
			pos = _unscaled(ax * sin(phase) * r)
		ProceduralAnimationConfig.Mode.SWAY:
			rot = deg_to_rad(sin(phase) * r)
		ProceduralAnimationConfig.Mode.SPIN:
			rot = deg_to_rad(fmod(c * r, 360.0))
		ProceduralAnimationConfig.Mode.ORBIT:
			pos = _unscaled((ax * (cos(phase) - 1.0) + ax.orthogonal() * sin(phase)) * r)
		ProceduralAnimationConfig.Mode.PULSE:
			scl = Vector2.ONE * maxf(0.01, 1.0 + sin(phase) * r)
		ProceduralAnimationConfig.Mode.SQUASH:
			var stretch := maxf(0.1, 1.0 + sin(phase) * r)
			scl = Vector2(1.0 / stretch, stretch)
		ProceduralAnimationConfig.Mode.HOP:
			pos = _unscaled(ax * absf(sin(phase * 0.5)) * r)
		ProceduralAnimationConfig.Mode.WADDLE:
			pos = _unscaled(ax * absf(sin(phase)) * r)
			rot = deg_to_rad(sin(phase) * r * 0.6)
		ProceduralAnimationConfig.Mode.APPROACH:
			pos = _world_to_local(_approach_direction(ax) * (0.5 - 0.5 * cos(phase)) * r)
		ProceduralAnimationConfig.Mode.PATH:
			return _sample_path(c, r)
	return Transform2D(rot, scl, 0.0, pos)


func _sample_path(c: float, path_scale: float) -> Transform2D:
	var pts := config.path_points
	if pts.size() < 2:
		return Transform2D.IDENTITY
	if _curve == null or pts != _curve_points or config.path_closed != _curve_closed:
		_curve = Curve2D.new()
		_curve.bake_interval = 2.0
		for p in pts:
			_curve.add_point(p)
		if config.path_closed:
			_curve.add_point(pts[0])
		_curve_points = pts.duplicate()
		_curve_closed = config.path_closed
	var length := _curve.get_baked_length()
	if length <= 0.0:
		return Transform2D.IDENTITY
	var t := fposmod(c, 1.0)
	var backwards := false
	if not config.path_closed: # ping-pong
		backwards = t > 0.5
		t = 1.0 - absf(1.0 - 2.0 * t)
	var d := t * length
	var world_offset := (_curve.sample_baked(d) - pts[0]) * path_scale
	var rot := 0.0
	if config.path_orient:
		var ahead := _curve.sample_baked(minf(d + 2.0, length)) - _curve.sample_baked(maxf(d - 2.0, 0.0))
		if backwards:
			ahead = -ahead
		var parent := get_parent() as Node2D
		rot = ahead.angle() - (parent.global_rotation if parent != null else 0.0)
	return Transform2D(rot, Vector2.ONE, 0.0, _world_to_local(world_offset))


## Offset in pixels (in the parent's rotated frame) -> parent-local units,
## cancelling the parent's scale so ranges stay in real pixels.
func _unscaled(offset: Vector2) -> Vector2:
	var parent := get_parent() as Node2D
	if parent == null:
		return offset
	var s := parent.scale
	return Vector2(offset.x / s.x if absf(s.x) > 0.0001 else 0.0, offset.y / s.y if absf(s.y) > 0.0001 else 0.0)


## World-oriented offset in pixels -> parent-local offset.
func _world_to_local(world_offset: Vector2) -> Vector2:
	var parent := get_parent() as Node2D
	if parent == null or not is_inside_tree():
		return world_offset
	return parent.global_transform.affine_inverse().basis_xform(world_offset)


func _approach_direction(fallback_axis: Vector2) -> Vector2:
	var parent := get_parent() as Node2D
	if target == null or parent == null or not is_inside_tree() or not target.is_inside_tree():
		return parent.global_transform.basis_xform(fallback_axis).normalized() if parent != null and is_inside_tree() else fallback_axis
	var to_target := target.global_position - parent.global_position
	return to_target.normalized() if to_target.length() > 0.001 else Vector2.ZERO
