class_name ArtResolver
extends RefCounted
## Single entry point for artwork (see assets/README.md and docs/CUSTOM_ARTWORK.md).
##
## Art is referenced by logical name, e.g. "object_a_body":
##   1. custom/graphics/object_a_body.png   (user override, loaded at runtime)
##   2. res://assets/graphics/template_object_a_body.png   (packaged fallback)
## An optional sidecar custom/graphics/object_a_body.json may set the image's
## pivot and pixel scale. Overrides are read once per run (restart to reload).
## Both paths use Image.load_from_file (templates are imported as "keep"), so the
## editor preview, the game and the exported .exe all behave the same.

const SUBFOLDER := "graphics"
const TEMPLATE_DIR := "res://assets/graphics"

## Tests set this to a temporary folder. Empty = normal behaviour.
static var override_root_for_tests: String = ""
static var _cache: Dictionary = {}


## Resolved artwork for one logical name.
class Art:
	var texture: Texture2D
	var image: Image
	var source: String = "missing"
	var has_sidecar_pivot: bool = false
	var pivot: Vector2 = Vector2(0.5, 0.5) ## normalized (0..1), only if has_sidecar_pivot
	var pixel_scale: float = 1.0 ## from the sidecar "scale" (e.g. 0.5 for art drawn at 2x)


static func get_override_root() -> String:
	if not override_root_for_tests.is_empty():
		return override_root_for_tests
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://custom")
	return OS.get_executable_path().get_base_dir().path_join("custom")


static func custom_path(art_name: String) -> String:
	return get_override_root().path_join(SUBFOLDER).path_join(art_name + ".png")


static func template_path(art_name: String) -> String:
	return TEMPLATE_DIR.path_join("template_%s.png" % art_name)


static func clear_cache() -> void:
	_cache.clear()


static func resolve(art_name: String) -> Art:
	var use_cache := not Engine.is_editor_hint()
	if use_cache and _cache.has(art_name):
		return _cache[art_name]
	var art := Art.new()
	var custom := custom_path(art_name)
	if FileAccess.file_exists(custom):
		art.image = _load_png(custom)
		if art.image != null:
			art.source = "custom/%s/%s.png" % [SUBFOLDER, art_name]
		else:
			push_warning("Custom art '%s' could not be decoded; using template." % custom)
	if art.image == null:
		art.image = _load_template(template_path(art_name))
		if art.image != null:
			art.source = "template_%s.png" % art_name
	if art.image == null:
		push_warning("No artwork found for '%s' (looked for %s and %s)." % [art_name, custom, template_path(art_name)])
		art.image = _missing_image()
	_read_sidecar(art, custom.get_basename() + ".json")
	var with_mips := art.image.duplicate() as Image
	with_mips.generate_mipmaps()
	art.texture = ImageTexture.create_from_image(with_mips)
	if use_cache:
		_cache[art_name] = art
	return art


static func _load_png(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := Image.new()
	if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


## Templates are imported as "Keep File" and read raw; a template added later
## in the editor (imported as a texture) is read through the resource loader.
static func _load_template(path: String) -> Image:
	if FileAccess.file_exists(path):
		return _load_png(path)
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		var image := texture.get_image() if texture != null else null
		if image != null and not image.is_empty():
			image.decompress()
			image.convert(Image.FORMAT_RGBA8)
			return image
	return null


static func _read_sidecar(art: Art, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("Ignoring invalid JSON sidecar '%s'." % path)
		return
	var size := Vector2(art.image.get_size())
	if data.get("pivot") is Array and data["pivot"].size() == 2:
		art.pivot = Vector2(data["pivot"][0], data["pivot"][1])
		art.has_sidecar_pivot = true
	elif data.get("pivot_px") is Array and data["pivot_px"].size() == 2:
		art.pivot = Vector2(data["pivot_px"][0], data["pivot_px"][1]) / size
		art.has_sidecar_pivot = true
	if data.get("scale") is float or data.get("scale") is int:
		art.pixel_scale = maxf(0.001, float(data["scale"]))


static func _missing_image() -> Image:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			image.set_pixel(x, y, Color.MAGENTA if (x / 8 + y / 8) % 2 == 0 else Color.BLACK)
	return image
