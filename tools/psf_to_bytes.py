#!/usr/bin/env python3
"""Convert a converted model (.psf) into the 64-byte surfel blob this addon reads.

The browser keeps its models in .psf: a 40-byte header, then positions, int8 normals with a
material-flags byte, and rgb. This expands that into the fixed record the renderer wants, with
the model recentred and scaled the way the viewer does it (longest side = 2 units).

    python3 psf_to_bytes.py dragon_shield.psf dragon_shield.bytes
    godot --headless --path . --script res://addons/pixel_art_splats/editor/convert_bytes.gd \
          -- res://demo/dragon_shield.bytes res://demo/dragon_shield.res 0.004

The .psf layout, for reference (all little endian):

    "PSF1", count, spacing, box (6 float32: min xyz, max xyz), flags
    count x 3 float32          position, in the model's own space
    count x 4 int8             normal xyz (x127), then material flags: 1 emissive, 2 two-sided
    count x 4 uint8            colour rgb
    if flags & 1:              count x 4 uint8 joint indices, count x 4 uint8 joint weights

Unlike a .dio scene, a model is not baked: its colour is albedo and the renderer lights it. The
material flags go into the surfel's own bits rather than into its alpha (the browser dims the alpha
by 0.1 / 0.2 to smuggle them through; doing that here would drop those splats below the pixel pass's
solid threshold and they would be drawn as translucent light).
"""

import math
import struct
import sys

STRIDE = 64

EMISSIVE = 1
TWO_SIDED = 2
GLOW = 4
BAKED = 8
UP_NORMAL = 16
SWAY = 32

MAGIC = 0x31465350  # "PSF1"


def read_psf(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 40:
        raise SystemExit(f"{path}: too short to be a .psf")
    magic, count, spacing = struct.unpack_from("<IIf", data, 0)
    if magic != MAGIC:
        raise SystemExit(f"{path}: not a .psf file (bad magic)")
    box = struct.unpack_from("<6f", data, 12)
    flags = struct.unpack_from("<I", data, 36)[0]
    pos = data[40:40 + count * 12]
    nor = data[40 + count * 12:40 + count * 16]
    rgba = data[40 + count * 16:40 + count * 20]
    skin = None
    if flags & 1:
        base = 40 + count * 20
        skin = (data[base:base + count * 4], data[base + count * 4:base + count * 8])
    return count, spacing, box, flags, pos, nor, rgba, skin


def quat_from_z(n):
    """The rotation that takes +z to n (three.js setFromUnitVectors)."""
    d = n[2]
    if d < -0.999999:
        return (0.0, 1.0, 0.0, 0.0)  # 180 degrees about y
    # three.js: cross(from, to) = (-ny, nx, 0), w = from.dot(to) + 1, then normalised
    s = math.sqrt(max(0.0, (1.0 + d) * 2.0))
    return (-n[1] / s, n[0] / s, 0.0, 0.5 * s)


def rotate(q, v):
    x, y, z, w = q
    tx = 2.0 * (y * v[2] - z * v[1])
    ty = 2.0 * (z * v[0] - x * v[2])
    tz = 2.0 * (x * v[1] - y * v[0])
    return (v[0] + w * tx + (y * tz - z * ty),
            v[1] + w * ty + (z * tx - x * tz),
            v[2] + w * tz + (x * ty - y * tx))


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: psf_to_bytes.py <in.psf> <out.bytes>")

    count, spacing, box, flags, pos, nor, rgba, skin = read_psf(sys.argv[1])

    # the viewer recentres the model and scales its longest side to two units
    centre = [(box[0] + box[3]) * 0.5, (box[1] + box[4]) * 0.5, (box[2] + box[5]) * 0.5]
    extent = [box[3] - box[0], box[4] - box[1], box[5] - box[2]]
    unit = 2.0 / max(max(extent), 1e-9)
    h = spacing * unit
    radius = 0.66 * h

    out = bytearray()
    for i in range(count):
        x, y, z = struct.unpack_from("<3f", pos, i * 12)
        p = ((x - centre[0]) * unit, (y - centre[1]) * unit, (z - centre[2]) * unit)

        nx, ny, nz, material = struct.unpack_from("<4b", nor, i * 4)
        nx /= 127.0
        ny /= 127.0
        nz /= 127.0
        length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        n = (nx / length, ny / length, nz / length)
        q = quat_from_z(n)
        kind = (EMISSIVE if material & 1 else 0) | (TWO_SIDED if material & 2 else 0)

        # a disc lying on the surface: two wide axes, and the normal in the third
        a1 = rotate(q, (radius, 0.0, 0.0))
        a2 = rotate(q, (0.0, radius, 0.0))
        colour = (rgba[i * 4] / 255.0, rgba[i * 4 + 1] / 255.0, rgba[i * 4 + 2] / 255.0)
        # opaque: the material flags live in their own bits, so the alpha stays at one
        out.extend(struct.pack("<15fI", *p, *a1, *a2, *n, *colour, kind | (255 << 8)))

    with open(sys.argv[2], "wb") as f:
        f.write(bytes(out))

    print(f"{sys.argv[2]}: {count} surfels, spacing {spacing:.4f} -> {h:.5f}, "
          f"longest side {max(extent):.3f} units x {unit:.3f}")

    if skin is not None:
        # the renderer wants them beside the cloud, eight bytes per splat: four joint indices then
        # four weights. Kept out of the 64-byte record so a cloud without a rig pays nothing.
        joints, weights = skin
        side = sys.argv[2] + ".skin" if not sys.argv[2].endswith(".bytes") else sys.argv[2][:-6] + ".skin"
        # interleaved: four indices then four weights, one record per splat. The .psf keeps the two
        # lists apart, which is right for a mesh and wrong for a texture upload.
        packed = bytearray(count * 8)
        for i in range(count):
            packed[i * 8:i * 8 + 4] = joints[i * 4:i * 4 + 4]
            packed[i * 8 + 4:i * 8 + 8] = weights[i * 4:i * 4 + 4]
        with open(side, "wb") as f:
            f.write(bytes(packed))
        print(f"  skinned: wrote {side} ({count} x 8 bytes)")


main()
