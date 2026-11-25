extends SceneTree
## Basic headless smoke test for Prototype 001 (not a full test suite).
## Run from the project folder (after one import so class names are known):
##   godot --headless --import
##   godot --headless --script res://tests/smoke_test.gd
## Exit code = number of failed checks.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok    ", message)
	else:
		_failures += 1
		printerr("  FAIL  ", message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	print("Smoke test: Interaction Sandbox")
	var main: SandboxMain = load("res://src/main/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)

	var a: SandboxObject = main.get_node("Objects/ObjectA")
	var b: SandboxObject = main.get_node("Objects/ObjectB")
	_check(main.objects.size() == 2, "main scene has two sandbox objects")
	_check(a.get_visual_aabb().size.y > 1.0 and b.get_visual_aabb().size.y > 0.1, "placeholder meshes built")
	_check(is_equal_approx(a.get_visual_aabb().position.y, 0.0), "model bottom aligned to object origin")
	_check(a.get_attachment_point_names().size() == 4 and b.get_attachment_point_names().size() == 2, "attachment points configured from Inspector data")
	_check(a.animator.config.mode == ProceduralAnimationConfig.Mode.APPROACH, "animation config loaded from assets/animations")

	# Every mode produces motion away from rest.
	var probe := ProceduralAnimator.new()
	main.add_child(probe)
	probe.setup(ProceduralAnimationConfig.new(), null)
	for mode in ProceduralAnimationConfig.Mode.values():
		if mode == ProceduralAnimationConfig.Mode.NONE:
			continue
		probe.config.mode = mode
		_check(not probe.sample(0.3).is_equal_approx(Transform3D.IDENTITY), "mode %s moves" % ProceduralAnimationConfig.mode_name(mode))
	probe.queue_free()

	# Playback controls.
	main.pause_all()
	main.reset_all_animations()
	_check(a.animator.transform.is_equal_approx(Transform3D.IDENTITY), "reset returns to rest pose")
	a.animator.play()
	await create_timer(0.4).timeout
	_check(not a.animator.transform.is_equal_approx(Transform3D.IDENTITY), "play animates")
	a.animator.pause()
	var paused := a.animator.transform
	await _frames(5)
	_check(a.animator.transform.is_equal_approx(paused), "pause holds pose")
	a.animator.reset()
	a.animator.config.loop = false
	a.animator.config.speed = 10.0
	a.animator.play()
	await create_timer(0.3).timeout
	_check(not a.animator.playing and is_equal_approx(a.animator.cycles, 1.0), "non-looping animation stops after one cycle")
	a.animator.config.loop = true
	a.animator.reset()

	# Attachment.
	_check(b.attach_to(a, &"hand_r", &"grip"), "attach B grip -> A hand_r")
	var hand := a.get_attachment_marker(&"hand_r")
	_check(b.get_parent() == hand, "B is parented to the hand marker")
	_check(b.get_attachment_marker(&"grip").global_position.is_equal_approx(hand.global_position), "B grip aligned with A hand")
	b.detach()
	_check(b.get_parent() == main.objects_root and b.attached_to == null, "detach returns B to the scene")
	b.reset_transform()

	# Collision detection.
	b.global_position = a.global_position + Vector3(0, 0.8, 0)
	await _frames(4)
	_check(a.is_colliding_with(b) and b.is_colliding_with(a), "overlap detected")
	_check(not a.query_overlaps().is_empty(), "immediate overlap query")
	b.global_position = a.global_position + Vector3(5, 0, 0)
	await _frames(4)
	_check(not a.is_colliding_with(b), "separation detected")
	b.reset_transform()

	# Picking through the manipulator.
	main.camera.reset_view()
	main.camera.smoothing = 0.0
	await _frames(2)
	var screen_pos := main.camera.unproject_position(a.get_world_center())
	_check(main.manipulator.pick(screen_pos) == a, "mouse ray picks object A")

	_test_model_resolver()

	main.queue_free()
	await _frames(2)
	print("Smoke test finished: %d failure(s)" % _failures)
	quit(_failures)


func _test_model_resolver() -> void:
	var temp_root := OS.get_user_data_dir().path_join("smoke_test_custom")
	var graphics := temp_root.path_join("graphics")
	DirAccess.make_dir_recursive_absolute(graphics)
	_write_triangle_gltf(graphics.path_join("smoke_model.gltf"))
	var bad := FileAccess.open(graphics.path_join("broken.glb"), FileAccess.WRITE)
	bad.store_string("not a glb")
	bad.close()

	_check(ModelResolver.get_override_root().ends_with("custom"), "editor override root is res://custom")
	ModelResolver.override_root_for_tests = temp_root
	_check(ModelResolver.find_override_path("missing").is_empty(), "missing override -> no path (fallback)")
	var model := ModelResolver.load_model_override("smoke_model")
	_check(model != null and not model.find_children("*", "MeshInstance3D", true, false).is_empty(), "glTF override loads at runtime")
	if model != null:
		model.free()
	_check(ModelResolver.load_model_override("broken") == null, "invalid override -> null (fallback)")
	ModelResolver.override_root_for_tests = ""

	for file in DirAccess.get_files_at(graphics):
		DirAccess.remove_absolute(graphics.path_join(file))
	DirAccess.remove_absolute(graphics)
	DirAccess.remove_absolute(temp_root)


func _write_triangle_gltf(path: String) -> void:
	var bytes := PackedFloat32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]).to_byte_array()
	var gltf := {
		"asset": {"version": "2.0"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0, "name": "Triangle"}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
		"buffers": [{"byteLength": bytes.size(), "uri": "data:application/octet-stream;base64," + Marshalls.raw_to_base64(bytes)}],
		"bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": bytes.size()}],
		"accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]}],
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(gltf))
	f.close()
