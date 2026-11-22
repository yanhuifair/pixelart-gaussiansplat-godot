# Changelog

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
