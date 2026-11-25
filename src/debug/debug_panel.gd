class_name DebugPanel
extends PanelContainer
## Compact live-debug panel: transforms, layers (pivot, offset, draw order),
## animation (object or layer, incl. paths), attachment and a live readout.
## Built in code so it is easy to extend. F1 hides it.

const PANEL_WIDTH := 400.0
const READOUT_INTERVAL := 0.1

const HELP_TEXT := """Mouse
  LMB click     select (transparent px ignored)
  LMB drag      move / rotate / scale
    + Shift     axis lock / - / stretch Y
    + Ctrl      snap
  MMB/RMB drag  pan camera
  Wheel         zoom at cursor
Keys
  W E R         tool: move / rotate / scale
  Tab / Esc     select next / deselect
  [ ]           draw order back / forward
  H             flip horizontally
  T             reset selected transform
  P             play/pause selected object
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
var _z: Array[SpinBox] = []

var _layer_option: OptionButton
var _layer_offset: Array[SpinBox] = []
var _layer_pivot: Array[SpinBox] = []
var _layer_rot: Array[SpinBox] = []
var _layer_scale: Array[SpinBox] = []
var _layer_z: Array[SpinBox] = []
var _layer_visible: CheckButton
var _layer_info: Label
var _copy_note: String = ""

var _anim_target_option: OptionButton
var _mode_option: OptionButton
var _loop_check: CheckButton
var _speed_slider: HSlider
var _speed_label: Label
var _range_slider: HSlider
var _range_label: Label
var _phase_slider: HSlider
var _phase_label: Label
var _state_label: Label
var _path_box: VBoxContainer
var _path_edit_check: CheckButton
var _path_closed_check: CheckButton
var _path_orient_check: CheckButton

var _own_point_option: OptionButton
var _target_point_option: OptionButton
var _attach_label: Label

var _global_speed_slider: HSlider
var _global_speed_label: Label
var _points_check: CheckButton
var _shapes_check: CheckButton
var _ysort_check: CheckButton
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
	sandbox.manipulator.path_edit_changed.connect(func(on: bool) -> void: _path_edit_check.set_pressed_no_signal(on))
	_on_selection_changed()
	_sync_tool_buttons()


func _process(delta: float) -> void:
	if sandbox == null:
		return
	var sel := _selected()
	if sel != _shown_object:
		_on_selection_changed()
	var anim := _anim_target()
	var show_path := anim != null and (anim.config.mode == ProceduralAnimationConfig.Mode.PATH or sandbox.manipulator.path_edit_target != null)
	sandbox.path_display.animator = anim if show_path else null
	sandbox.path_display.visible = show_path
	if not visible:
		return
	if sel != null:
		_refresh_selected(sel)
	_global_speed_label.text = "×%.2f" % ProceduralAnimator.global_speed_scale
	_global_speed_slider.set_value_no_signal(ProceduralAnimator.global_speed_scale)
	_points_check.set_pressed_no_signal(sandbox.show_points)
	_shapes_check.set_pressed_no_signal(sandbox.show_collision_shapes)
	_ysort_check.set_pressed_no_signal(sandbox.objects_root.y_sort_enabled)
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
	style.bg_color = Color(0.07, 0.08, 0.09, 0.9)
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
	root.add_theme_constant_override("separation", 5)
	scroll.add_child(root)

	var title := Label.new()
	title.text = "2D INTERACTION SANDBOX  ·  Prototype 001"
	title.add_theme_font_size_override("font_size", 15)
	root.add_child(title)

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

	_no_selection = _label("Click an object (or press Tab) to edit it.", root)
	_no_selection.modulate = Color(1, 1, 1, 0.6)

	_selected_box = VBoxContainer.new()
	_selected_box.add_theme_constant_override("separation", 5)
	root.add_child(_selected_box)
	_build_transform_section(_selected_box)
	_build_layer_section(_selected_box)
	_build_animation_section(_selected_box)
	_build_attachment_section(_selected_box)
	_build_global_section(root)

	_section("Live readout", root)
	_readout = _label("", root)
	_readout.add_theme_font_override("font", _mono)
	_readout.add_theme_font_size_override("font_size", 12)

	var help_button := _button("Controls ▾", func() -> void: _help.visible = not _help.visible, root)
	help_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help = _label(HELP_TEXT, root)
	_help.add_theme_font_override("font", _mono)
	_help.add_theme_font_size_override("font_size", 12)


func _build_transform_section(parent: Control) -> void:
	_section("Transform (object pivot = origin)", parent)
	_space_label = _label("", parent)
	_space_label.modulate = Color(1, 1, 1, 0.6)
	var grid := _grid(parent)
	_pos = _spin_row(grid, "Position", 2, 1.0, 10.0, -100000.0, 100000.0, _on_object_spin.bind("position"))
	_rot = _spin_row(grid, "Rotation°", 1, 0.1, 5.0, -3600.0, 3600.0, _on_object_spin.bind("rotation_degrees"))
	_scl = _spin_row(grid, "Scale", 2, 0.01, 0.1, -100.0, 100.0, _on_object_spin.bind("scale"))
	_z = _spin_row(grid, "Draw order", 1, 1.0, 1.0, -1000.0, 1000.0, _on_object_spin.bind("z_index"))
	var row := HBoxContainer.new()
	parent.add_child(row)
	_button("Flip [H]", func() -> void: _selected().flip_horizontal(), row)
	_button("Reset [T]", func() -> void: _selected().reset_transform(), row)
	_button("Focus [F]", sandbox.focus_selected, row)


func _build_layer_section(parent: Control) -> void:
	_section("Sprite layer", parent)
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label("Layer", row)
	_layer_option = _option(row, func(_i: int) -> void: _copy_note = "")
	_layer_visible = _check("Visible", row, _on_layer_visible)
	_layer_info = _label("", parent)
	_layer_info.modulate = Color(1, 1, 1, 0.6)
	_layer_info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	var grid := _grid(parent)
	_layer_offset = _spin_row(grid, "Offset", 2, 1.0, 5.0, -100000.0, 100000.0, _on_layer_spin.bind("position"))
	_layer_pivot = _spin_row(grid, "Pivot 0-1", 2, 0.005, 0.05, -10.0, 10.0, _on_layer_spin.bind("pivot"))
	_layer_rot = _spin_row(grid, "Rotation°", 1, 0.1, 5.0, -3600.0, 3600.0, _on_layer_spin.bind("rotation_degrees"))
	_layer_scale = _spin_row(grid, "Scale", 2, 0.01, 0.1, -100.0, 100.0, _on_layer_spin.bind("scale"))
	_layer_z = _spin_row(grid, "Layer z", 1, 1.0, 1.0, -100.0, 100.0, _on_layer_spin.bind("z_index"))
	_button("Copy pivot JSON for this art (sidecar)", _on_copy_pivot_json, parent)


func _build_animation_section(parent: Control) -> void:
	_section("Animation", parent)
	var target_row := HBoxContainer.new()
	parent.add_child(target_row)
	_label("Animate", target_row)
	_anim_target_option = _option(target_row, func(_i: int) -> void: sandbox.manipulator.set_path_edit(null))
	var mode_row := HBoxContainer.new()
	parent.add_child(mode_row)
	_label("Mode", mode_row)
	_mode_option = _option(mode_row, _on_mode_selected)
	for m in ProceduralAnimationConfig.Mode.values():
		_mode_option.add_item(ProceduralAnimationConfig.mode_name(m), m)
	_loop_check = _check("Loop", mode_row, func(on: bool) -> void: _anim_target().config.loop = on)

	var speed := _slider_row(parent, "Speed", 0.0, 5.0, 0.01, func(v: float) -> void: _anim_target().config.speed = v)
	_speed_slider = speed[0]
	_speed_label = speed[1]
	var amount := _slider_row(parent, "Range", 0.0, 200.0, 0.01, func(v: float) -> void: _anim_target().config.movement_range = v)
	_range_slider = amount[0]
	_range_label = amount[1]
	var phase := _slider_row(parent, "Phase", 0.0, 1.0, 0.01, func(v: float) -> void: _anim_target().config.phase_offset = v)
	_phase_slider = phase[0]
	_phase_label = phase[1]

	var row := HBoxContainer.new()
	parent.add_child(row)
	_button("▶ Play", func() -> void: _anim_target().play(), row)
	_button("❚❚ Pause", func() -> void: _anim_target().pause(), row)
	_button("■ Reset", func() -> void: _anim_target().reset(), row)
	_state_label = _label("", row)

	_path_box = VBoxContainer.new()
	parent.add_child(_path_box)
	var path_row := HBoxContainer.new()
	_path_box.add_child(path_row)
	_path_edit_check = _check("Draw path (click to add/drag)", path_row, _on_path_edit_toggled)
	_button("Clear", _on_path_clear, path_row)
	var path_row2 := HBoxContainer.new()
	_path_box.add_child(path_row2)
	_path_closed_check = _check("Closed loop", path_row2, func(on: bool) -> void: _anim_target().config.path_closed = on)
	_path_orient_check = _check("Orient along path", path_row2, func(on: bool) -> void: _anim_target().config.path_orient = on)


func _build_attachment_section(parent: Control) -> void:
	_section("Attachment", parent)
	var own_row := HBoxContainer.new()
	parent.add_child(own_row)
	_label("Own point", own_row)
	_own_point_option = _option(own_row, Callable())
	var target_row := HBoxContainer.new()
	parent.add_child(target_row)
	_label("Attach to", target_row)
	_target_point_option = _option(target_row, Callable())
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
	_points_check = _check("Show pivots + attachment points", parent, sandbox.set_show_points)
	_shapes_check = _check("Show collision shapes", parent, sandbox.set_show_collision_shapes)
	_ysort_check = _check("Y-sort objects (lower on screen = in front)", parent, sandbox.set_y_sort)
	_block_check = _check("Block overlap while dragging", parent,
		func(on: bool) -> void: sandbox.manipulator.block_overlap = on)


# --- Sync ---------------------------------------------------------------------------

func _selected() -> SandboxObject:
	return sandbox.manipulator.selected


func _layer() -> SandboxObject.LayerState:
	var sel := _selected()
	if sel == null or _layer_option.selected < 0 or _layer_option.selected >= sel.layer_states.size():
		return null
	return sel.layer_states[_layer_option.selected]


## The animator edited by the animation section: the object's or one layer's.
func _anim_target() -> ProceduralAnimator:
	var sel := _selected()
	if sel == null:
		return null
	var index := _anim_target_option.selected - 1
	if index >= 0 and index < sel.layer_states.size():
		return sel.layer_states[index].animator
	return sel.animator


## Rebuilds the option lists that depend on the selected object.
func _on_selection_changed() -> void:
	var sel := _selected()
	_shown_object = sel
	_copy_note = ""
	_selected_box.visible = sel != null
	_no_selection.visible = sel == null
	_object_option.select(sandbox.objects.find(sel) + 1)
	if sel == null:
		return
	_layer_option.clear()
	_anim_target_option.clear()
	_anim_target_option.add_item("Whole object")
	for layer_name in sel.get_layer_names():
		_layer_option.add_item(String(layer_name))
		_anim_target_option.add_item("Layer: " + String(layer_name))
	_layer_option.select(0)
	_anim_target_option.select(0)

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
		if sel.attached_to != null else "World space (pixels)"
	_set_spins(_pos, [sel.position.x, sel.position.y])
	_set_spins(_rot, [sel.rotation_degrees])
	_set_spins(_scl, [sel.scale.x, sel.scale.y])
	_set_spins(_z, [sel.z_index])

	var st := _layer()
	if st != null:
		var cfg := st.config
		_set_spins(_layer_offset, [cfg.position.x, cfg.position.y])
		_set_spins(_layer_pivot, [st.pivot.x, st.pivot.y])
		_set_spins(_layer_rot, [cfg.rotation_degrees])
		_set_spins(_layer_scale, [cfg.scale.x, cfg.scale.y])
		_set_spins(_layer_z, [cfg.z_index])
		_layer_visible.set_pressed_no_signal(cfg.visible)
		var size := st.art.image.get_size()
		_layer_info.text = "art \"%s\"  ←  %s\n%d×%d px · scale %.2f%s" % [
			cfg.art_name, st.art.source, size.x, size.y, st.pixel_scale,
			"  (pivot from sidecar)" if st.art.has_sidecar_pivot else ""] + _copy_note

	var a := _anim_target()
	var anim := a.config
	if _mode_option.get_selected_id() != anim.mode:
		_mode_option.select(_mode_option.get_item_index(anim.mode))
	_range_slider.max_value = ProceduralAnimationConfig.range_slider_max(anim.mode)
	_speed_slider.set_value_no_signal(anim.speed)
	_speed_label.text = "%.2f Hz" % anim.speed
	_range_slider.set_value_no_signal(anim.movement_range)
	_range_label.text = "%.2f %s" % [anim.movement_range, ProceduralAnimationConfig.range_unit(anim.mode)]
	_phase_slider.set_value_no_signal(anim.phase_offset)
	_phase_label.text = "%.2f" % anim.phase_offset
	_loop_check.set_pressed_no_signal(anim.loop)
	_state_label.text = "playing" if a.playing else "paused"
	_path_box.visible = anim.mode == ProceduralAnimationConfig.Mode.PATH or sandbox.manipulator.path_edit_target != null
	_path_closed_check.set_pressed_no_signal(anim.path_closed)
	_path_orient_check.set_pressed_no_signal(anim.path_orient)
	_attach_label.text = "on %s / %s" % [sel.attached_to.display_name, sel.attached_point] if sel.attached_to else ""


func _sync_tool_buttons() -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(i == sandbox.manipulator.tool)


func _set_spins(spins: Array[SpinBox], values: Array) -> void:
	for i in spins.size():
		if not spins[i].get_line_edit().has_focus():
			spins[i].set_value_no_signal(values[i])


func _build_readout() -> String:
	var lines: PackedStringArray = []
	lines.append("FPS %d   zoom %.2f   tool %s" % [
		Engine.get_frames_per_second(), sandbox.camera.zoom.x,
		ObjectManipulator.TOOL_NAMES[sandbox.manipulator.tool]])
	for o in sandbox.objects:
		var gt := o.global_transform
		var cfg := o.animator.config
		lines.append("")
		lines.append("%s%s" % [o.display_name, "  [selected]" if o == _selected() else ""])
		lines.append("  pos (%8.1f %8.1f)  rot %7.1f°" % [gt.origin.x, gt.origin.y, rad_to_deg(gt.get_rotation())])
		lines.append("  scl (%6.2f %6.2f)    z %d" % [gt.get_scale().x, gt.get_scale().y, SandboxObject.effective_z(o)])
		lines.append("  anim %s %s  %.2f Hz  %.2f %s  cycle %.2f" % [
			ProceduralAnimationConfig.mode_name(cfg.mode), "▶" if o.animator.playing else "❚❚",
			cfg.speed, cfg.movement_range, ProceduralAnimationConfig.range_unit(cfg.mode), o.animator.cycles])
		for st in o.layer_states:
			var lc := st.animator.config
			lines.append("  · %-10s z%+d  %s%s" % [st.config.layer_name, st.config.z_index,
				st.art.source.trim_prefix("template_"),
				("  " + ProceduralAnimationConfig.mode_name(lc.mode)) if lc.mode != ProceduralAnimationConfig.Mode.NONE else ""])
		if o.attached_to != null:
			lines.append("  attached to %s / %s" % [o.attached_to.display_name, o.attached_point])
		var hits: PackedStringArray = []
		for other in o.colliding_with:
			hits.append(other.display_name + (" (attached)" if o.is_attachment_pair(other) else ""))
		lines.append("  collision %s" % (", ".join(hits) if not hits.is_empty() else "-"))
	return "\n".join(lines)


# --- Callbacks ----------------------------------------------------------------------

func _on_object_option_selected(index: int) -> void:
	sandbox.manipulator.select(sandbox.objects[index - 1] if index > 0 else null)


func _on_object_spin(value: float, component: int, property: String) -> void:
	var sel := _selected()
	match property:
		"position":
			var p := sel.position
			p[component] = value
			sel.position = p
		"scale":
			var s := sel.scale
			s[component] = value if absf(value) > 0.001 else 0.001
			sel.scale = s
		"rotation_degrees":
			sel.rotation_degrees = value
		"z_index":
			sel.z_index = int(value)


func _on_layer_spin(value: float, component: int, property: String) -> void:
	var st := _layer()
	if st == null:
		return
	match property:
		"position":
			st.config.position[component] = value
		"pivot":
			st.pivot[component] = value
		"scale":
			st.config.scale[component] = value if absf(value) > 0.001 else 0.001
		"rotation_degrees":
			st.config.rotation_degrees = value
		"z_index":
			st.config.z_index = int(value)
	_selected().refresh_layer(st)


func _on_layer_visible(on: bool) -> void:
	var st := _layer()
	if st != null:
		st.config.visible = on
		_selected().refresh_layer(st)


func _on_copy_pivot_json() -> void:
	var st := _layer()
	if st == null:
		return
	var json := JSON.stringify({"pivot": [snappedf(st.pivot.x, 0.001), snappedf(st.pivot.y, 0.001)], "scale": st.pixel_scale})
	DisplayServer.clipboard_set(json)
	_copy_note = "\nCopied %s → save as custom/graphics/%s.json" % [json, st.config.art_name]


func _on_mode_selected(index: int) -> void:
	var mode := _mode_option.get_item_id(index) as ProceduralAnimationConfig.Mode
	var a := _anim_target()
	a.config.movement_range = ProceduralAnimationConfig.default_range(mode)
	a.set_mode(mode)
	if mode != ProceduralAnimationConfig.Mode.NONE and not a.playing:
		a.play()


func _on_path_edit_toggled(on: bool) -> void:
	sandbox.manipulator.set_path_edit(_anim_target() if on else null)


func _on_path_clear() -> void:
	_anim_target().config.path_points = PackedVector2Array()
	_anim_target().reset()


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
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if on_selected.is_valid():
		o.item_selected.connect(on_selected)
	parent.add_child(o)
	return o


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	parent.add_child(grid)
	return grid


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


## A label plus [param count] spin boxes; on_changed(value, component).
func _spin_row(grid: GridContainer, text: String, count: int, step: float, arrow_step: float, min_v: float, max_v: float, on_changed: Callable) -> Array[SpinBox]:
	var l := _label(text, grid)
	l.custom_minimum_size.x = 90
	var spins: Array[SpinBox] = []
	for component in count:
		var s := SpinBox.new()
		s.min_value = min_v
		s.max_value = max_v
		s.step = step
		s.allow_greater = true
		s.allow_lesser = true
		s.set("custom_arrow_step", arrow_step)
		s.select_all_on_focus = true
		s.custom_minimum_size.x = 140
		s.value_changed.connect(func(v: float) -> void: on_changed.call(v, component))
		grid.add_child(s)
		spins.append(s)
	if count == 1:
		grid.add_child(Control.new())
	return spins
