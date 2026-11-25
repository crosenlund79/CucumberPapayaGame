extends SceneTree
## Basic headless smoke test for the 2D Prototype 001 (not a full test suite).
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
	print("Smoke test: 2D Interaction Sandbox")
	_test_art_resolver() # before the scene loads, so the cache is clean
	ArtResolver.clear_cache()

	var main: SandboxMain = load("res://src/main/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var a: SandboxObject = main.get_node("Objects/ObjectA")
	var b: SandboxObject = main.get_node("Objects/ObjectB")
	_check(main.objects.size() == 2, "main scene has two sandbox objects")
	_check(a.layer_states.size() == 4 and b.layer_states.size() == 2, "multiple sprite layers per object")
	_check(a.get_layer_state(&"body").art.source == "template_object_a_body.png", "template art loaded at runtime")
	var arm := a.get_layer_state(&"arm_front")
	_check(arm.sprite.offset.is_equal_approx(-Vector2(0.5, 0.15) * Vector2(36, 120)), "layer pivot applied (sprite offset)")
	_check(a.get_attachment_point_names().size() == 4 and b.get_attachment_point_names().size() == 2, "attachment points configured")
	_check(a.get_attachment_marker(&"hand").get_parent() == arm.animator, "attachment point follows its layer")

	# Draw order and pixel picking.
	var front := a.get_layer_state(&"arm_front").sprite
	var body := a.get_layer_state(&"body").sprite
	var back := a.get_layer_state(&"arm_back").sprite
	_check(SandboxObject.draws_above(front, body) and SandboxObject.draws_above(body, back), "layer z order: arm_front > body > arm_back")
	main.pause_all()
	main.reset_all_animations()
	await _frames(2)
	_check(main.manipulator.pick(a.global_position + Vector2(0, -60)) == a, "click on opaque pixel picks object A")
	_check(main.manipulator.pick(a.global_position + Vector2(-58, -178)) == null, "click on transparent corner picks nothing")
	b.global_position = a.global_position + Vector2(0, -90)
	b.z_index = 10
	_check(main.manipulator.pick(b.global_position) == b, "higher draw order wins the pick")
	b.z_index = -10
	_check(main.manipulator.pick(a.global_position + Vector2(0, -60)) == a, "lower draw order loses the pick")
	b.z_index = 0
	_check(main.manipulator.pick(a.global_position + Vector2(0, -60)) == b, "equal draw order: later in tree is on top")

	# Collision detection.
	await _frames(4)
	_check(a.is_colliding_with(b) and b.is_colliding_with(a), "overlap detected")
	_check(not a.query_overlaps().is_empty(), "immediate overlap query")
	b.global_position = a.global_position + Vector2(600, 0)
	await _frames(4)
	_check(not a.is_colliding_with(b), "separation detected")
	b.reset_transform()

	# Animation: every mode moves; play / pause / reset / no-loop.
	var probe := ProceduralAnimator.new()
	main.add_child(probe)
	probe.setup(ProceduralAnimationConfig.new())
	probe.config.path_points = PackedVector2Array([Vector2.ZERO, Vector2(100, 0), Vector2(100, 100)])
	for mode in ProceduralAnimationConfig.Mode.values():
		if mode == ProceduralAnimationConfig.Mode.NONE:
			continue
		probe.config.mode = mode
		probe.config.movement_range = ProceduralAnimationConfig.default_range(mode)
		_check(not probe.sample(0.3).is_equal_approx(Transform2D.IDENTITY), "mode %s moves" % ProceduralAnimationConfig.mode_name(mode))
	probe.config.mode = ProceduralAnimationConfig.Mode.PATH
	probe.config.path_closed = true
	_check(probe.sample(0.0).origin.is_zero_approx() and probe.sample(1.0).origin.is_zero_approx(), "closed path starts and ends at rest")
	probe.queue_free()

	var anim := a.animator
	_check(anim.transform.is_equal_approx(Transform2D.IDENTITY), "reset returns to rest pose")
	anim.play()
	await create_timer(0.4).timeout
	_check(not anim.transform.is_equal_approx(Transform2D.IDENTITY), "play animates")
	anim.pause()
	var paused := anim.transform
	await _frames(5)
	_check(anim.transform.is_equal_approx(paused), "pause holds pose")
	anim.reset()
	anim.config.loop = false
	anim.config.speed = 10.0
	anim.play()
	await create_timer(0.3).timeout
	_check(not anim.playing and is_equal_approx(anim.cycles, 1.0), "non-looping animation stops after one cycle")
	anim.config.loop = true
	anim.reset()
	arm.animator.play()
	await create_timer(0.3).timeout
	_check(not is_zero_approx(arm.animator.rotation), "layer animation rotates around its pivot")
	main.reset_all_animations()

	# Attachment.
	_check(b.attach_to(a, &"hand", &"grip"), "attach B grip -> A hand")
	var hand := a.get_attachment_marker(&"hand")
	_check(b.get_parent() == hand, "B is parented to the hand marker")
	_check(b.get_attachment_marker(&"grip").global_position.distance_to(hand.global_position) < 0.01, "B grip aligned with A hand")
	b.detach()
	_check(b.get_parent() == main.objects_root and b.attached_to == null, "detach returns B to the scene")
	b.reset_transform()

	main.queue_free()
	await _frames(2)
	print("Smoke test finished: %d failure(s)" % _failures)
	quit(_failures)


func _test_art_resolver() -> void:
	var temp_root := OS.get_user_data_dir().path_join("smoke_test_custom")
	var graphics := temp_root.path_join("graphics")
	DirAccess.make_dir_recursive_absolute(graphics)
	var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(10, 5, 20, 10), Color.WHITE)
	img.save_png(graphics.path_join("object_a_body.png"))
	var sidecar := FileAccess.open(graphics.path_join("object_a_body.json"), FileAccess.WRITE)
	sidecar.store_string('{"pivot_px": [20, 20], "scale": 0.5}')
	sidecar.close()
	var bad := FileAccess.open(graphics.path_join("object_a_head.png"), FileAccess.WRITE)
	bad.store_string("not a png")
	bad.close()

	_check(ArtResolver.get_override_root().ends_with("custom"), "editor override root is res://custom")
	ArtResolver.override_root_for_tests = temp_root
	ArtResolver.clear_cache()
	var body := ArtResolver.resolve("object_a_body")
	_check(body.source.begins_with("custom/") and body.image.get_size() == Vector2i(40, 20), "custom PNG overrides template")
	_check(body.has_sidecar_pivot and body.pivot.is_equal_approx(Vector2(0.5, 1.0)) and is_equal_approx(body.pixel_scale, 0.5), "JSON sidecar sets pivot and scale")
	_check(body.image.get_used_rect() == Rect2i(10, 5, 20, 10), "transparent pixels kept (used rect)")
	_check(ArtResolver.resolve("object_a_head").source == "template_object_a_head.png", "invalid custom PNG falls back to template")
	_check(ArtResolver.resolve("object_a_arm").source == "template_object_a_arm.png", "missing custom PNG falls back to template")
	ArtResolver.override_root_for_tests = ""
	ArtResolver.clear_cache()
	for file in DirAccess.get_files_at(graphics):
		DirAccess.remove_absolute(graphics.path_join(file))
	DirAccess.remove_absolute(graphics)
	DirAccess.remove_absolute(temp_root)
