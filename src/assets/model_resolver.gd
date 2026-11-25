class_name ModelResolver
extends RefCounted
## Runtime override lookup for replaceable 3D models (see assets/README.md).
##
## A model with logical name "object_a" is overridden by the first existing
## file of:  <override root>/graphics/object_a.glb  or  .../object_a.gltf
## Override root: res://custom in the editor, "custom" next to the executable
## in an exported Windows/Linux build. Files are loaded with GLTFDocument
## (no import step, no rebuild); changes apply after restarting the game.

const SUBFOLDER := "graphics"
const EXTENSIONS: Array[String] = ["glb", "gltf"]

## Tests set this to a temporary folder. Empty = normal behaviour.
static var override_root_for_tests: String = ""


static func get_override_root() -> String:
	if not override_root_for_tests.is_empty():
		return override_root_for_tests
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://custom")
	return OS.get_executable_path().get_base_dir().path_join("custom")


## Absolute path of the override file for [param logical_name], or "" if none.
static func find_override_path(logical_name: String) -> String:
	if logical_name.is_empty():
		return ""
	var folder := get_override_root().path_join(SUBFOLDER)
	for ext in EXTENSIONS:
		var path := folder.path_join("%s.%s" % [logical_name, ext])
		if FileAccess.file_exists(path):
			return path
	return ""


## Loads the override model as a new scene tree, or returns null (with a
## warning if a file exists but cannot be decoded) so callers fall back.
static func load_model_override(logical_name: String) -> Node3D:
	var path := find_override_path(logical_name)
	if path.is_empty():
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_warning("Model override '%s' could not be loaded (error %d). Using fallback." % [path, err])
		return null
	var scene := doc.generate_scene(state)
	if scene == null:
		push_warning("Model override '%s' produced no scene. Using fallback." % path)
		return null
	if not scene is Node3D:
		push_warning("Model override '%s' root is not a 3D node. Using fallback." % path)
		scene.free()
		return null
	print("Loaded model override: ", path)
	return scene as Node3D
