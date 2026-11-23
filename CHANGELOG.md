# Changelog

## [1.6.0] - 2026-11-23

Lamps, the viewer's camera move, and skinned models.

- **Lamps.** `PixelArtLamp` is an `OmniLight3D` carrying a world's own lamp: `power`, its index in
  the row, and the viewer's flicker (`0.86 + 0.1 sin 11t + 0.06 sin 23.7t`). The node re-reads the
  lights every frame now, so the flicker reaches the splats. Only splats that are **not baked** are
  lit by them — a baked scene's colour already holds its light, which is why a model on an island
  flickers and the island does not.
- **Camera.** `OrbitCamera.drift` follows the viewer's idle move: a scene breathes in and out
  (`0.7 + 0.3 (0.5 + 0.5 cos 0.11t)`) while a model sways by twelve percent, the height rides
  `elev + 0.06 sin 0.2t`, and a portrait window steps back (`portraitFit`).
- **Skinned models.** `tools/psf_to_bytes.py` writes a `.skin` sidecar (four joint indices and four
  weights a splat), `tools/rig_to_json.py` turns a `.rig.glb` into a `.rig`, and `PixelArtRig` plays
  it: bones, inverse binds, clips, slerped rotations. The shader does linear blend skinning from a
  texture, so a pose costs one CPU pass over the bones, not over the splats.

  Unity does not have this half yet; the `.psf`, `.skin` and `.rig` files are shared, so it is the
  player and the shader that are missing there.

## [1.5.0] - 2026-11-23

Converted models, and a palette for them.

- `tools/psf_to_bytes.py` reads a `.psf` — a model the browser project converted from glTF — into the
  same 64-byte records, recentred and scaled to two units the way the viewer does it. Model material
  flags (emissive, two-sided) go into the surfel's own bits instead of the alpha the browser smuggles
  them through, so they never drop below the pixel pass's solid threshold.
- `PixelArtPalette.extract`: the viewer's k-means over the surface colours at the four brightness
  levels the lighting produces, plus a lamp's tint. Same constants and the same result as the Unity
  package, colour for colour.

## [1.4.0] - 2026-11-23

The two motions that turn around a point, and a colour fix for translucent light.

- `leaf` (leaves falling through a column) and `beam` (a lighthouse beam sweeping) are carried now.
  They put their centre in the surfel's **normal slot**: both are translucent, and a translucent
  splat's normal is never read, so the 64-byte record is untouched. A world that declares `splats`
  (explicit shapes relative to a centre) generates those too.
- The pixel pass un-premultiplies translucent light in **linear** space. It was dividing the stored
  sRGB value by alpha, which overshoots: a faint gold beam came out as the bright palette yellow
  instead of the muted orange the browser and the Unity package give. Every halo, ember and smoke
  puff keeps its hue now.

## [1.3.0] - 2026-11-23

The moving things: embers, smoke, fireflies, drifting sand.

- `tools/dio_to_bytes.py` expands a world's `particles` as well — the same lcg, called in the same
  order as the browser, so the specks land where they do there. They carry a motion id in flags bits
  16..23 and one parameter in 24..31; the scene's own halos get `pulse`.
- The splat shaders animate them from the splat index and `ps_time`, vertex-side: no CPU work, no
  extra buffer. Rise, smoke, blink, twinkle, drift, float, fog, shaft, ray, pulse.
- The MultiMesh custom data now carries kind, motion and parameter (it used to be kind only).
- `SplatCloudNode.time_override` poses the clock, for a still or a test.
- `leaf` and `beam` are not carried yet: they need a per-splat centre.

## [1.2.0] - 2026-11-23

The look as an asset, so several scenes can share it.

- `PixelArtLook`: a resource with the palette, the pixel grid and the switches — the same fields the
  Unity package keeps on its renderer feature.
- Give a `PixelArtView` a `look` and its own fields read and write through to it: the inspector, the
  hud and the keyboard shortcuts keep working, they just write to the shared asset. Leave `look` empty
  and the node keeps its own values, so existing scenes are untouched.
- The demo ships `demo/caravan_look.tres` and points the view at it.

## [1.1.1] - 2026-11-23

The panel, in a dock, so it works while you author.

- The plugin adds the hud to the bottom-right dock and rebinds it to the selected `PixelArtView` (or
  the first one in the open scene), so the look can be tuned without running the game.
- `PixelArtHud` gained `docked` and `bind()`: the same rows, without the full-screen anchor or the
  keyboard shortcuts.

## [1.1.0] - 2026-11-23

The browser viewer's settings panel, in the engine.

- `PixelArtHud`: the same look/view panel (pixel size, dither, light, light bands, palette, hard
  pixels, 2x2 supersample, outline, auto orbit), bound to the view and the clouds. H hides it;
  Q / X / S / E / O flip the switches, the site's keys. The demo carries one.
- Ranges follow the site: `pixel_size` 1..8, `exposure` 0.5..2.5, `bands` 0..8.

## [1.0.1] - 2026-11-23

Defaults aligned with the Unity package, so a cloud looks the same in both without touching anything:
`bands` now defaults to 5, the browser's cel-step default for live-lit splats (the demo sets 0, as
scenes are already baked). The caravan demo now says so explicitly, like its Unity twin.

## [1.0.0] - 2026-11-23

First release.

- Surfel renderer for Godot 4: one `MultiMeshInstance3D` per material, 20 floats per instance, the
  disc's two wide axes in the transform basis, per-splat lighting (sun, up to four lamps, ambient,
  fog) in the vertex shader.
- Pixel pass as a fullscreen canvas shader over a low-resolution `SubViewport`: coverage vote,
  palette vote, ink outlines, translucent light haze, 4×4 Bayer dithering, point-sampled enlarge.
- `SplatCloud` resource (64 bytes per surfel, the Unity package's layout), `PixelArtPalette`,
  `PixelArtView` with the camera and the look settings.
- Editor tools: convert a `.bytes` blob into a `SplatCloud`, and bake selected meshes into one.
  Both write compressed resources.
- `tools/dio_to_bytes.py`: expand a world from the browser project's `.dio` format into this layout.
- Demo: Caravan camp, 147 769 surfels, 16 colours.
