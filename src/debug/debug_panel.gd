class_name DebugPanel
extends PanelContainer
## Compact debug panel: live transforms and animation parameters for every
## object, plus direct controls for the selected object. Built in code so it is
## easy to extend. F1 hides it.

const PANEL_WIDTH := 390.0
const READOUT_INTERVAL := 0.1

const HELP_TEXT := """Mouse
  LMB click     select (empty = deselect)
  LMB drag      move / rotate / scale
    + Shift     vertical / pitch / stretch Y
    + Ctrl      snap
  RMB drag      orbit   (or Alt + LMB)
  MMB drag      pan     (or Shift + RMB)
  Wheel         zoom
Keys
  W E R         tool: move / rotate / scale
  Tab / Esc     select next / deselect
  T             reset selected transform
  P             play/pause selected anim
  Space         play/pause all
  Backspace     reset all animations
  F / Home      focus selected / reset camera
  F1            hide/show this panel"""

var sandbox: SandboxMain

var _shown_object: SandboxObject = null
var _readout_timer: float = 0.0
var _mono: SystemFont

var _tool_buttons: Array[Button] = []
var _object_option: OptionButton
var _selected_box: VBoxContainer
var _no_selection: Label
var _space_label: Label
var _pos: Array[SpinBox] = []
var _rot: Array[SpinBox] = []
var _scl: Array[SpinBox] = []
var _mode_option: OptionButton
var _speed_slider: HSlider
var _speed_label: Label
var _range_slider: HSlider
var _range_label: Label
var _loop_check: CheckButton
var _phase_slider: HSlider
var _phase_label: Label
var _state_label: Label
var _own_point_option: OptionButton
var _target_point_option: OptionButton
var _attach_label: Label
var _global_speed_slider: HSlider
var _global_speed_label: Label
var _points_check: CheckButton
var _shapes_check: CheckButton
var _block_check: CheckButton
var _readout: Label
var _help: Label


func setup(main: SandboxMain) -> void:
	sandbox = main
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	_build()
	sandbox.manipulator.selection_changed.connect(func(_o: SandboxObject) -> void: _on_selection_changed())
	sandbox.manipulator.tool_changed.connect(func(_t: ObjectManipulator.Tool) -> void: _sync_tool_buttons())
	_on_selection_changed()
	_sync_tool_buttons()


func _process(delta: float) -> void:
	if sandbox == null or not visible:
		return
	var sel := sandbox.manipulator.selected
	if sel != _shown_object:
		_on_selection_changed()
	if sel != null:
		_refresh_selected(sel)
	_global_speed_label.text = "×%.2f" % ProceduralAnimator.global_speed_scale
	_global_speed_slider.set_value_no_signal(ProceduralAnimator.global_speed_scale)
	_points_check.set_pressed_no_signal(sandbox.show_attachment_points)
	_shapes_check.set_pressed_no_signal(sandbox.show_collision_shapes)
	_block_check.set_pressed_no_signal(sandbox.manipulator.block_overlap)
	_readout_timer -= delta
	if _readout_timer <= 0.0:
		_readout_timer = READOUT_INTERVAL
		_readout.text = _build_readout()


# --- Layout -----------------------------------------------------------------------

func _build() -> void:
	var theme_override := Theme.new()
	theme_override.default_font_size = 13
	theme = theme_override
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.09, 0.88)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	offset_left = 8
	offset_top = 8
	offset_bottom = -8
	offset_right = 8 + PANEL_WIDTH

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)

	var title := Label.new()
	title.text = "INTERACTION SANDBOX  ·  Prototype 001"
	title.add_theme_font_size_override("font_size", 15)
	root.add_child(title)

	# Tool + selection
	var tools := HBoxContainer.new()
	root.add_child(tools)
	var group := ButtonGroup.new()
	for i in ObjectManipulator.TOOL_NAMES.size():
		var b := _button("%s [%s]" % [ObjectManipulator.TOOL_NAMES[i], "WER"[i]], sandbox.manipulator.set_tool.bind(i), tools)
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tool_buttons.append(b)

	var sel_row := HBoxContainer.new()
	root.add_child(sel_row)
	_label("Selected", sel_row)
	_object_option = _option(sel_row, _on_object_option_selected)
	_object_option.add_item("(none)")
	for o in sandbox.objects:
		_object_option.add_item(o.display_name)
	_object_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_no_selection = _label("Click an object (or press Tab) to edit it.", root)
	_no_selection.modulate = Color(1, 1, 1, 0.6)

	_selected_box = VBoxContainer.new()
	_selected_box.add_theme_constant_override("separation", 6)
	root.add_child(_selected_box)
	_build_transform_section(_selected_box)
	_build_animation_section(_selected_box)
	_build_attachment_section(_selected_box)
	_build_global_section(root)

	_section("Live readout (world space)", root)
	_readout = Label.new()
	_readout.add_theme_font_override("font", _mono)
	_readout.add_theme_font_size_override("font_size", 12)
	root.add_child(_readout)

	var help_button := _button("Controls ▾", func() -> void: _help.visible = not _help.visible, root)
	help_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help = _label(HELP_TEXT, root)
	_help.add_theme_font_override("font", _mono)
	_help.add_theme_font_size_override("font_size", 12)


func _build_transform_section(parent: Control) -> void:
	_section("Transform", parent)
	_space_label = _label("", parent)
	_space_label.modulate = Color(1, 1, 1, 0.6)
	var grid := GridContainer.new()
	grid.columns = 4
	parent.add_child(grid)
	_pos = _spin_row(grid, "Position", 0.01, 0.1, -1000.0, 1000.0, _on_position_spin)
	_rot = _spin_row(grid, "Rotation°", 0.1, 5.0, -360.0, 360.0, _on_rotation_spin)
	_scl = _spin_row(grid, "Scale", 0.01, 0.1, 0.01, 100.0, _on_scale_spin)
	var row := HBoxContainer.new()
	parent.add_child(row)
	_button("Reset transform [T]", func() -> void: _selected().reset_transform(), row)
	_button("Focus camera [F]", sandbox.focus_selected, row)


func _build_animation_section(parent: Control) -> void:
	_section("Animation", parent)
	var mode_row := HBoxContainer.new()
	parent.add_child(mode_row)
	_label("Mode", mode_row)
	_mode_option = _option(mode_row, _on_mode_selected)
	_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ProceduralAnimationConfig.Mode.values():
		_mode_option.add_item(ProceduralAnimationConfig.mode_name(m), m)
	_loop_check = _check("Loop", mode_row, func(on: bool) -> void: _selected().animator.config.loop = on)

	var speed := _slider_row(parent, "Speed", 0.0, 5.0, 0.01,
		func(v: float) -> void: _selected().animator.config.speed = v)
	_speed_slider = speed[0]
	_speed_label = speed[1]
	var amount := _slider_row(parent, "Range", 0.0, 3.0, 0.01,
		func(v: float) -> void: _selected().animator.config.movement_range = v)
	_range_slider = amount[0]
	_range_label = amount[1]
	var phase := _slider_row(parent, "Phase", 0.0, 1.0, 0.01,
		func(v: float) -> void: _selected().animator.config.phase_offset = v)
	_phase_slider = phase[0]
	_phase_label = phase[1]

	var row := HBoxContainer.new()
	parent.add_child(row)
	_button("▶ Play", func() -> void: _selected().animator.play(), row)
	_button("❚❚ Pause", func() -> void: _selected().animator.pause(), row)
	_button("■ Reset", func() -> void: _selected().animator.reset(), row)
	_state_label = _label("", row)


func _build_attachment_section(parent: Control) -> void:
	_section("Attachment", parent)
	var own_row := HBoxContainer.new()
	parent.add_child(own_row)
	_label("Own point", own_row)
	_own_point_option = _option(own_row, Callable())
	_own_point_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target_row := HBoxContainer.new()
	parent.add_child(target_row)
	_label("Attach to", target_row)
	_target_point_option = _option(target_row, Callable())
	_target_point_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	parent.add_child(row)
	_button("Attach", _on_attach_pressed, row)
	_button("Detach", func() -> void: _selected().detach(), row)
	_attach_label = _label("", row)


func _build_global_section(parent: Control) -> void:
	_section("All objects", parent)
	var row := HBoxContainer.new()
	parent.add_child(row)
	_button("▶ Play all", sandbox.play_all, row)
	_button("❚❚ Pause all", sandbox.pause_all, row)
	_button("■ Reset anims", sandbox.reset_all_animations, row)
	var row2 := HBoxContainer.new()
	parent.add_child(row2)
	_button("Reset all transforms", sandbox.reset_all_transforms, row2)
	_button("Reset camera", sandbox.camera.reset_view, row2)
	var speed := _slider_row(parent, "Speed ×", 0.0, 3.0, 0.01, sandbox.set_global_speed)
	_global_speed_slider = speed[0]
	_global_speed_label = speed[1]
	_global_speed_slider.set_value_no_signal(ProceduralAnimator.global_speed_scale)
	_points_check = _check("Show attachment points", parent, sandbox.set_show_attachment_points)
	_points_check.button_pressed = sandbox.show_attachment_points
	_shapes_check = _check("Show collision shapes", parent, sandbox.set_show_collision_shapes)
	_shapes_check.button_pressed = sandbox.show_collision_shapes
	_block_check = _check("Block overlap while dragging", parent,
		func(on: bool) -> void: sandbox.manipulator.block_overlap = on)
	_block_check.button_pressed = sandbox.manipulator.block_overlap


# --- Sync ---------------------------------------------------------------------------

func _selected() -> SandboxObject:
	return sandbox.manipulator.selected


func _on_selection_changed() -> void:
	var sel := _selected()
	_shown_object = sel
	_selected_box.visible = sel != null
	_no_selection.visible = sel == null
	_object_option.select(sandbox.objects.find(sel) + 1)
	if sel == null:
		return
	var cfg := sel.animator.config
	_mode_option.select(_mode_option.get_item_index(cfg.mode))
	_range_slider.max_value = ProceduralAnimationConfig.range_slider_max(cfg.mode)

	_own_point_option.clear()
	_own_point_option.add_item("(object origin)")
	_own_point_option.set_item_metadata(0, &"")
	for p in sel.get_attachment_point_names():
		_own_point_option.add_item(String(p))
		_own_point_option.set_item_metadata(_own_point_option.item_count - 1, p)

	_target_point_option.clear()
	for o in sandbox.objects:
		if o == sel:
			continue
		for p in o.get_attachment_point_names():
			_target_point_option.add_item("%s / %s" % [o.display_name, p])
			_target_point_option.set_item_metadata(_target_point_option.item_count - 1, [o, p])


func _refresh_selected(sel: SandboxObject) -> void:
	_space_label.text = ("Local to %s / %s" % [sel.attached_to.display_name, sel.attached_point]) \
		if sel.attached_to != null else "World space"
	_set_spins(_pos, sel.position)
	_set_spins(_rot, sel.rotation_degrees)
	_set_spins(_scl, sel.scale)
	var a := sel.animator
	var cfg := a.config
	var unit := ProceduralAnimationConfig.range_unit(cfg.mode)
	_speed_slider.set_value_no_signal(cfg.speed)
	_speed_label.text = "%.2f Hz" % cfg.speed
	_range_slider.set_value_no_signal(cfg.movement_range)
	_range_label.text = "%.2f %s" % [cfg.movement_range, unit]
	_phase_slider.set_value_no_signal(cfg.phase_offset)
	_phase_label.text = "%.2f" % cfg.phase_offset
	_loop_check.set_pressed_no_signal(cfg.loop)
	_state_label.text = "playing" if a.playing else "paused"
	_attach_label.text = "on %s / %s" % [sel.attached_to.display_name, sel.attached_point] if sel.attached_to else ""


func _sync_tool_buttons() -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(i == sandbox.manipulator.tool)


func _set_spins(spins: Array[SpinBox], value: Vector3) -> void:
	for i in 3:
		if not spins[i].get_line_edit().has_focus():
			spins[i].set_value_no_signal(value[i])


func _build_readout() -> String:
	var lines: PackedStringArray = []
	lines.append("FPS %d   tool %s   speed ×%.2f" % [
		Engine.get_frames_per_second(),
		ObjectManipulator.TOOL_NAMES[sandbox.manipulator.tool],
		ProceduralAnimator.global_speed_scale])
	for o in sandbox.objects:
		var gt := o.global_transform
		var a := o.animator
		var cfg := a.config
		lines.append("")
		lines.append("%s%s" % [o.display_name, "  [selected]" if o == _selected() else ""])
		lines.append("  pos %s" % _v3(gt.origin, "%7.2f"))
		lines.append("  rot %s°" % _v3(gt.basis.orthonormalized().get_euler() * (180.0 / PI), "%7.1f"))
		lines.append("  scl %s" % _v3(gt.basis.get_scale(), "%7.2f"))
		lines.append("  anim %s %s  cycle %.2f" % [
			ProceduralAnimationConfig.mode_name(cfg.mode), "▶" if a.playing else "❚❚", a.cycles])
		lines.append("    speed %.2f Hz  range %.2f %s  %s" % [
			cfg.speed, cfg.movement_range, ProceduralAnimationConfig.range_unit(cfg.mode),
			"loop" if cfg.loop else "once ×%d" % cfg.cycles_when_not_looping])
		lines.append("    offset %s" % _v3(a.transform.origin, "%6.2f"))
		lines.append("  model %s" % o.model_source)
		if o.attached_to != null:
			lines.append("  attached to %s / %s" % [o.attached_to.display_name, o.attached_point])
		var hits: PackedStringArray = []
		for other in o.colliding_with:
			hits.append(other.display_name + (" (attached)" if o.is_attachment_pair(other) else ""))
		lines.append("  collision %s" % (", ".join(hits) if not hits.is_empty() else "-"))
	return "\n".join(lines)


static func _v3(v: Vector3, fmt: String) -> String:
	return "(%s %s %s)" % [fmt % v.x, fmt % v.y, fmt % v.z]


# --- Callbacks ----------------------------------------------------------------------

func _on_object_option_selected(index: int) -> void:
	sandbox.manipulator.select(sandbox.objects[index - 1] if index > 0 else null)


func _on_mode_selected(index: int) -> void:
	var mode: ProceduralAnimationConfig.Mode = _mode_option.get_item_id(index) as ProceduralAnimationConfig.Mode
	_selected().animator.set_mode(mode)
	_range_slider.max_value = ProceduralAnimationConfig.range_slider_max(mode)


func _on_position_spin(value: float, axis: int) -> void:
	var p := _selected().position
	p[axis] = value
	_selected().position = p


func _on_rotation_spin(value: float, axis: int) -> void:
	var r := _selected().rotation_degrees
	r[axis] = value
	_selected().rotation_degrees = r


func _on_scale_spin(value: float, axis: int) -> void:
	var s := _selected().scale
	s[axis] = maxf(value, 0.01)
	_selected().scale = s


func _on_attach_pressed() -> void:
	if _target_point_option.selected < 0:
		return
	var target: Array = _target_point_option.get_item_metadata(_target_point_option.selected)
	var own: StringName = _own_point_option.get_item_metadata(maxi(_own_point_option.selected, 0))
	_selected().attach_to(target[0], target[1], own)


# --- Widget helpers -------------------------------------------------------------------

func _section(text: String, parent: Control) -> void:
	parent.add_child(HSeparator.new())
	var l := _label(text.to_upper(), parent)
	l.modulate = Color(0.55, 0.8, 1.0)


func _label(text: String, parent: Control) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _button(text: String, on_pressed: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


func _check(text: String, parent: Control, on_toggled: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(on_toggled)
	parent.add_child(c)
	return c


func _option(parent: Control, on_selected: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	if on_selected.is_valid():
		o.item_selected.connect(on_selected)
	parent.add_child(o)
	return o


## Returns [slider, value label].
func _slider_row(parent: Control, text: String, min_v: float, max_v: float, step: float, on_changed: Callable) -> Array:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(text, row)
	l.custom_minimum_size.x = 60
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.allow_greater = true
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(on_changed)
	row.add_child(s)
	var value_label := _label("", row)
	value_label.custom_minimum_size.x = 80
	return [s, value_label]


func _spin_row(grid: GridContainer, text: String, step: float, arrow_step: float, min_v: float, max_v: float, on_changed: Callable) -> Array[SpinBox]:
	var l := _label(text, grid)
	l.custom_minimum_size.x = 70
	var spins: Array[SpinBox] = []
	for axis in 3:
		var s := SpinBox.new()
		s.min_value = min_v
		s.max_value = max_v
		s.step = step
		s.allow_greater = true
		s.allow_lesser = true
		s.set("custom_arrow_step", arrow_step)
		s.select_all_on_focus = true
		s.custom_minimum_size.x = 96
		s.value_changed.connect(on_changed.bind(axis))
		grid.add_child(s)
		spins.append(s)
	return spins
