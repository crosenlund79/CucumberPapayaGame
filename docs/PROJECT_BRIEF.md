# Project Brief — Single design and task handoff record

This file **records** decisions and approvals; it never grants them. Only the user can approve scope, in their message in the current conversation. **Undecided = ask, don't choose.**

## Game decisions (user-confirmed only)

- **Game title:** Undecided. Current work: *Prototype 001 — 2D Interaction Sandbox* (feasibility prototype, not a game)
- **Godot version (pin minor, e.g. 4.x):** 4.7 (built and tested with 4.7.2-stable), GL Compatibility renderer
- **Premise / core player loop:** Undecided; the prototype is a technical playground for interactions, positioning, layering and procedural animation
- **Perspective / art direction:** Native 2D only. The user will provide their own hand-drawn PNG artwork; Claude provides neutral `template_` placeholders
- **Confirmed mechanics and constraints:** Two configurable layered 2D objects; mouse select/move/rotate/scale; configurable pivots; named attachment points; layering/draw order; basic collision detection; procedural animation with configurable paths (speed, range, loop, pause, reset); camera pan/zoom; live debug controls; runtime PNG overrides from `custom/` without recompiling
- **Explicitly out of scope:** 3D (cancelled 2026-11-25; archived at commit `7cd1017`, tag `prototype-001-3d-archived` created locally); elaborate menus, polished UI, extensive testing or documentation
- **Existing modules / boundaries:** `src/art` (artwork resolution), `src/sandbox_object` (layered object, configs, collision, attach), `src/animation` (procedural animator, paths), `src/interaction` (mouse tools), `src/camera`, `src/debug`, `src/world`, `src/main` (wiring)
- **Testing framework (GUT or GdUnit4) and commands:** None by user decision (rapid prototype). Basic headless smoke test: `godot --headless --import` then `godot --headless --script res://tests/smoke_test.gd`
- **Target platforms:** Windows x64 (exported by GitHub Actions as a ZIP artifact)
- **Asset override notes:** `custom/graphics/<art name>.png` (+ optional `.json` pivot/scale sidecar) next to the exe or in the project; see `docs/CUSTOM_ARTWORK.md`

## Current approved development objective

**Status: Delivered for user acceptance testing (2026-11-25).**

- **User approval (reference / summary):** User message of 2026-11-25, "Direction Change — Prototype 001: 2D Interaction Sandbox", which also authorized commit, push and the Windows build
- **Objective (one by default):** Native 2D interaction sandbox with replaceable hand-drawn artwork
- **In scope:** Functionality and custom-artwork items listed under confirmed mechanics; Windows x64 ZIP via GitHub Actions; short artwork guide; brief report
- **Out of scope:** 3D, polish, extensive tests/docs, unrequested features
- **Acceptance criteria / done when:** User's hands-on acceptance testing
- **Relevant module tests:** `tests/smoke_test.gd` (basic smoke test only)
- **Relevant integration/manual checks:** User testing of the Windows build

## Proposals awaiting user approval

None.
