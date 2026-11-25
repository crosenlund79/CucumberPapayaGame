# Custom artwork guide (2D Interaction Sandbox)

## 1. Replace an image — no recompiling

1. Pick the **art name** of the image you want to replace:

   | Art name | Used by |
   | --- | --- |
   | `object_a_body` | Object A, layer `body` |
   | `object_a_head` | Object A, layer `head` |
   | `object_a_arm` | Object A, layers `arm_front` **and** `arm_back` |
   | `object_b_crate` | Object B, layer `crate` |
   | `object_b_emblem` | Object B, layer `emblem` |

   The debug panel (select an object → *Sprite layer*) shows each layer's art name and where it was loaded from.
2. Save a **transparent PNG** with exactly that name, e.g. `object_a_head.png`, into a `custom/graphics/` folder:
   - **Exported game:** `custom/graphics/` next to `InteractionSandbox2D.exe` (the ZIP already contains it).
   - **Godot editor:** the project's `custom/graphics/` folder.
3. **Restart** the game. The panel now shows `← custom/graphics/object_a_head.png`.

Any image size works. Transparent pixels are ignored for mouse clicks and collision bounds. If a file is missing or unreadable, the neutral `template_` placeholder is used and a warning is printed. Placeholders live in `assets/graphics/template_<art name>.png`. Never edit them to customise; drop your file into `custom/` instead.

## 2. Pivots

The **pivot** is the point of the image that sits on the layer's position. Rotation, scaling and layer animation (e.g. the arm swing) happen around it, so put it on the joint, such as the shoulder of an arm or the neck of a head. Blue dots mark layer pivots, and the blue cross marks the object's pivot (its origin).

- Pivots are **normalized**: `0,0` = top-left, `0.5,0.5` = centre, `0.5,1` = bottom centre.
- To set a custom image's pivot without the editor, put a JSON file with the same name next to the PNG, e.g. `custom/graphics/object_a_head.json`:

  ```json
  { "pivot": [0.5, 0.95] }
  ```

  or in pixels of your image: `{ "pivot_px": [120, 250] }`. Add `"scale": 0.5` if you drew at twice the placeholder resolution.
- **Live tuning:** select the object → *Sprite layer* → change *Pivot 0-1* until it looks right → **Copy pivot JSON** → paste into the `.json` file → restart.
- In the editor, the default pivot is set per layer in the Inspector (`ObjectA → Layers → pivot`).

## 3. Layering and draw order

- Each object is a stack of **layers** (one PNG each). Draw order = object *Draw order* + *Layer z*. Higher values are drawn in front, and on a tie, later in the list is drawn in front. Object A: `arm_back` (−1) → `body` (0) → `head` (1) → `arm_front` (2).
- Change them live in the panel (*Draw order*, *Layer z*, or the `[` / `]` keys). The *Y-sort* toggle draws objects lower on screen in front.
- An attached object (e.g. a crate in a hand) is drawn relative to the layer it is attached to.
- **Add or remove a layer** (Godot editor): `src/main/main.tscn` → select the object → Inspector → *Layers* → add a `SpriteLayerConfig`, then set `layer_name`, `art_name`, `position`, `pivot`, `z_index`. A layer whose art exists only in `custom/graphics/` works too (the editor shows a magenta checker if no PNG exists at all).

## Tips

- Draw limbs and other moving parts as separate PNGs with the joint at the pivot.
- Keep a consistent pixel density across layers, or use `"scale"` in the JSON file.
- Attachment point and layer positions are in placeholder pixels. If your art has different proportions, adjust them in the Inspector. Debug-panel edits other than the copied pivot JSON are not saved.
