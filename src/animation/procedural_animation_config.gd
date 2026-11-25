@tool
class_name ProceduralAnimationConfig
extends Resource
## Parameters for one procedural animation.
##
## Saved as .tres files under res://assets/animations/ so animation data stays
## separate from meshes, materials and interaction logic. Every value here is
## editable in the Inspector and (at runtime) in the debug panel.
##
## The meaning of [member movement_range] depends on [member mode]:
## BOB, HOP, ORBIT, APPROACH, WADDLE = metres; SWAY, SPIN = degrees;
## PULSE = scale fraction (0.1 = +/-10 %).

enum Mode {
	NONE, ## No motion.
	BOB, ## Up/down sine along [member axis].
	SWAY, ## Rocking rotation around [member axis].
	SPIN, ## Continuous rotation around [member axis] (range = degrees per cycle).
	ORBIT, ## Circle around [member axis] that passes through the rest position.
	PULSE, ## Uniform scale breathing.
	HOP, ## One bounce per cycle along [member axis].
	WADDLE, ## Two bounces per cycle plus side tilt (simple walk feel).
	APPROACH, ## Moves toward the object's interaction target and back (or along [member axis] if none).
}

## Which procedural motion to play.
@export var mode: Mode = Mode.BOB
## Cycles per second.
@export_range(0.0, 10.0, 0.01, "or_greater") var speed: float = 1.0
## Amplitude of the motion. Unit depends on [member mode] (see class description).
@export_range(0.0, 10.0, 0.01, "or_greater") var movement_range: float = 0.25
## Direction / rotation axis in the object's local space.
@export var axis: Vector3 = Vector3.UP
## Repeat forever. When off, playback stops after [member cycles_when_not_looping].
@export var loop: bool = true
## Number of cycles to play when [member loop] is off.
@export_range(1, 100, 1) var cycles_when_not_looping: int = 1
## Shifts the start point within the cycle (0..1). Useful to desync objects.
@export_range(0.0, 1.0, 0.01) var phase_offset: float = 0.0
## Start playing when the sandbox starts.
@export var autoplay: bool = true


## Unit label for [member movement_range] in the given mode (for UI/readouts).
static func range_unit(for_mode: Mode) -> String:
	match for_mode:
		Mode.SWAY, Mode.SPIN:
			return "deg"
		Mode.PULSE:
			return "x"
		Mode.NONE:
			return ""
	return "m"


## Sensible slider maximum for [member movement_range] in the given mode.
static func range_slider_max(for_mode: Mode) -> float:
	match for_mode:
		Mode.SWAY:
			return 90.0
		Mode.SPIN:
			return 720.0
		Mode.PULSE:
			return 1.0
	return 3.0


static func mode_name(for_mode: Mode) -> String:
	return String(Mode.keys()[for_mode]).capitalize()
