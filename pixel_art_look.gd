@tool
class_name PixelArtLook
extends Resource
## The look of the picture, as data, so one asset can be shared by several scenes.
##
## Give a [PixelArtView] a look and its own fields read and write through to it — the same idea as the
## settings that sit on the renderer feature in the Unity package.
##
## Leave it out and the view keeps its own values, which is what a one-off scene wants.

## The colours the picture may use, and the background it is drawn on.
@export var palette: PixelArtPalette

@export_group("Pixel grid")
## Screen pixels per art pixel. Fixed to the screen, so zooming never changes a pixel's size.
@export_range(1, 8) var pixel_size := 5
## Draw at twice the art resolution: four samples per art pixel, which the pass votes over.
@export var supersample := true

@export_group("Look")
## Hard-edged splats and nearest-sampled palette colours. Off draws soft Gaussians, blended.
@export var crisp := true
## Silhouettes take a darker ink of their own colour.
@export var outline := true
## Snap every pixel to the palette. Off shows the continuous colours.
@export var quantise := true
## Ordered (Bayer) dithering between the two nearest palette colours. 0 = off.
@export_range(0.0, 1.0) var dither := 0.0
## Grow every splat to at least this many source texels so far surfaces do not fall apart.
@export_range(0.0, 3.0) var min_texels := 0.9

## Show the small splat render on its own, without the pixel pass.
@export var debug_raw := false
