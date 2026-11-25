# 2D Interaction Sandbox — Prototype 001

A rapid feasibility prototype in **Godot 4.7 (GL Compatibility)**. It is a technical playground, not a game, for trying out 2D interactions, positioning, sprite layering, pivots, attachment and procedural animation, using replaceable hand-drawn PNG artwork.

## Get it

- **Windows x64:** GitHub → *Actions* → **Build Windows x64** → latest green run → *Artifacts* → `InteractionSandbox2D-windows-x64` (ZIP). Unzip it and run `InteractionSandbox2D.exe`. The exe is unsigned, so Windows may show SmartScreen: choose *More info → Run anyway*.
- **Source:** open `project.godot` in Godot 4.7.x (standard build) and press F5. The `InteractionSandbox2D-source` artifact is the same project as a ZIP.
- **Your own artwork:** see [docs/CUSTOM_ARTWORK.md](docs/CUSTOM_ARTWORK.md).

## Controls

| Input | Action |
| --- | --- |
| LMB click / drag | Select (transparent pixels ignored) / move · rotate · scale |
| Shift / Ctrl while dragging | Axis lock (move), stretch Y (scale) / snap |
| MMB or RMB drag, wheel | Pan, zoom at cursor |
| W E R | Tool: move / rotate / scale |
| Tab, Esc | Select next, deselect (or leave path drawing) |
| `[` `]` | Draw order back / forward |
| H, T | Flip horizontally, reset transform |
| P, Space, Backspace | Play/pause selected, play/pause all, reset all animations |
| F, Home, F1 | Focus selected, reset camera, hide panel |

The **debug panel** edits the selection live: transform and draw order; per-layer offset, pivot, rotation, scale, z and visibility; animation of the whole object or of one layer (mode, speed, range, phase, loop, play/pause/reset, path drawing); attachment; global speed and overlays. Panel changes are not saved.

## What's in the scene

- **Object A**, a character made of four layers (`body`, `head`, `arm_back`, `arm_front`). The arms sway around their shoulder pivots and the whole object *approaches* Object B. Attachment points: `hand`, `hand_back` (they follow the arms), `head_top`, `back`.
- **Object B**, a prop made of two layers (`crate`, plus a spinning `emblem`). It follows a closed *path*. Attachment points: `grip`, `top`.

Try this: select B → *Attachment* → own point `grip`, attach to `Object A / hand`. To draw a new path: select an object → *Animation* → *Draw path* → click points in the world.

## Configure without code (Inspector)

In `src/main/main.tscn`, select `Objects/ObjectA` or `ObjectB`:

- **Layers** (`SpriteLayerConfig`): `art_name`, `position`, `pivot`, `rotation_degrees`, `scale`, `z_index`, `modulate`, `visible`, `collides`, and an optional per-layer `animation`.
- **Animation** (`.tres` in `assets/animations/`): `mode` (Bob, Sway, Spin, Orbit, Pulse, Squash, Hop, Waddle, Approach, Path), `speed`, `movement_range`, `axis`, `loop`, `cycles_when_not_looping`, `phase_offset`, `autoplay`, `path_points`, `path_closed`, `path_orient`.
- **Attachment points**: `point_name`, `position`, `rotation_degrees`, `layer` (follow a layer).
- **Collision**: `collision_padding`, `pick_alpha_threshold`.
- **Add a third object:** duplicate `ObjectB` under `Objects`.

## Layout

| Path | Responsibility |
| --- | --- |
| `src/art/` | `ArtResolver`: PNG lookup (`custom/` → `template_`), JSON pivot sidecar |
| `src/sandbox_object/` | Layered object, layer/attachment configs, collision, attach |
| `src/animation/` | Procedural animator + config, path overlay |
| `src/interaction/` | Mouse picking and manipulation, path drawing |
| `src/camera/`, `src/world/`, `src/debug/`, `src/main/` | Pan/zoom camera, grid, debug panel, scene wiring |
| `assets/graphics/`, `assets/animations/` | `template_` placeholder PNGs, animation presets |
| `tests/smoke_test.gd` | Headless smoke test |
| `.github/workflows/build-windows.yml` | Smoke test + Windows export → ZIP artifacts |

Smoke test (Godot 4.7 on PATH, run from the project folder):

```bash
godot --headless --import
```

```bash
godot --headless --script res://tests/smoke_test.gd
```

## Known limitations

- Debug-panel edits are live only. To save settings, use the Inspector (editor), or the pivot JSON file for custom art.
- Collision uses one rectangle per layer around its opaque pixels, not pixel-perfect shapes. Clicking *is* pixel-accurate.
- Attachment-point and layer positions don't adapt automatically to replacement art with different proportions.
- When Y-sort is on, clicking still resolves ties by scene order, not by Y.
- PNG only. Audio overrides are not implemented. Art reloads after a restart (no hot reload).
- Tested headless and with software rendering on Linux. The Windows exe is built by CI but not run on Windows by Claude.

Project rules for Claude live in `CLAUDE.md` and `docs/`. The abandoned 3D attempt is archived at commit `7cd1017` on this branch.
