@tool
class_name ProceduralAnimationConfig
extends Resource
## Parameters for one procedural animation (whole object or one sprite layer).
## Saved as .tres under res://assets/animations/ so animation data stays separate
## from artwork and interaction logic. Motion happens around the pivot.
##
## Unit of [member movement_range] per mode: BOB, ORBIT, HOP, WADDLE,
## APPROACH = pixels; SWAY, SPIN = degrees; PULSE, SQUASH = fraction (0.1 = 10 %);
## PATH = path scale (1 = as drawn).

enum Mode {
	NONE, ## No motion.
	BOB, ## Back-and-forth along [member axis].
	SWAY, ## Rocking rotation around the pivot.
	SPIN, ## Continuous rotation (range = degrees per cycle).
	ORBIT, ## Circle that starts at the rest position.
	PULSE, ## Uniform scale breathing.
	SQUASH, ## Squash and stretch (area preserving).
	HOP, ## One bounce per cycle along [member axis].
	WADDLE, ## Two bounces plus a tilt per cycle (simple walk).
	APPROACH, ## Toward the interaction target and back (or along [member axis]).
	PATH, ## Follows [member path_points].
}

@export var mode: Mode = Mode.BOB
## Cycles per second.
@export_range(0.0, 10.0, 0.01, "or_greater") var speed: float = 1.0
## Amplitude. Unit depends on [member mode] (see class description).
@export_range(0.0, 1000.0, 0.01, "or_greater") var movement_range: float = 20.0
## Direction for BOB / HOP / WADDLE / APPROACH / ORBIT start (y points down).
@export var axis: Vector2 = Vector2.UP
## Repeat forever. When off, playback stops after [member cycles_when_not_looping].
@export var loop: bool = true
@export_range(1, 100, 1) var cycles_when_not_looping: int = 1
## Shifts the start within the cycle (0..1). Useful to desync layers/objects.
@export_range(0.0, 1.0, 0.01) var phase_offset: float = 0.0
@export var autoplay: bool = true

@export_group("Path")
## PATH mode: points in pixels, world orientation, relative to the rest position.
## The first point is the start. Can also be drawn live in the debug panel.
@export var path_points: PackedVector2Array = PackedVector2Array()
## Closed: loops around. Open: goes to the end and back (ping-pong).
@export var path_closed: bool = true
## Rotate to follow the path direction.
@export var path_orient: bool = false


static func range_unit(for_mode: Mode) -> String:
	match for_mode:
		Mode.SWAY, Mode.SPIN:
			return "°"
		Mode.PULSE, Mode.SQUASH, Mode.PATH:
			return "×"
		Mode.NONE:
			return ""
	return "px"


static func range_slider_max(for_mode: Mode) -> float:
	match for_mode:
		Mode.SWAY:
			return 90.0
		Mode.SPIN:
			return 720.0
		Mode.PULSE, Mode.SQUASH:
			return 1.0
		Mode.PATH:
			return 3.0
		Mode.APPROACH:
			return 800.0
	return 200.0


## Sensible starting range when switching modes in the debug panel.
static func default_range(for_mode: Mode) -> float:
	match for_mode:
		Mode.BOB:
			return 20.0
		Mode.SWAY:
			return 15.0
		Mode.SPIN:
			return 360.0
		Mode.ORBIT:
			return 40.0
		Mode.PULSE:
			return 0.1
		Mode.SQUASH:
			return 0.15
		Mode.HOP:
			return 40.0
		Mode.WADDLE:
			return 8.0
		Mode.APPROACH:
			return 200.0
		Mode.PATH:
			return 1.0
	return 0.0


static func mode_name(for_mode: Mode) -> String:
	return String(Mode.keys()[for_mode]).capitalize()
