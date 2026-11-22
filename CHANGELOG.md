# Changelog

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
