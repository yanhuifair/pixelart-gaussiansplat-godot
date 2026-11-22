#!/usr/bin/env python3
"""Convert a world file from the browser project (.dio) into the 64-byte surfel blob this addon reads.

The browser keeps its worlds compact: a position per surfel, an int8 normal, an rgb triple, and a
separate list of "free" splats (grass blades, leaves, halos) with a scale and a quaternion. This
expands that into the fixed 64-byte record the renderer wants.

    python3 dio_to_bytes.py caravan.dio caravan.bytes
    godot --headless --path . --script res://addons/pixel_art_splats/editor/convert_bytes.gd \
          -- res://demo/caravan.bytes res://demo/caravan.res 0.02

The .dio layout, for reference (all little endian):

    "PSD1", json length, json  (meta: count, free, h, R, top, bottom, palette, lights, particles …)
    count x 3 float32          surfel position
    count x 4 int8             surfel normal xyz (x127), and a 4th byte: 1 = emissive, so the bake
                               left its colour unlit. Nothing for the renderer to do with it.
    count x 4 uint8            surfel colour rgb
    free x 10 float32          position, scale xyz, quaternion xyzw
    free x 4 uint8             rgb, then kind (2 bits) | opacity (6 bits)
"""

import json
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

KIND_LIT, KIND_EMISSIVE, KIND_SWAY, KIND_GLOW = 0, 1, 2, 3


def read_dio(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"PSD1":
        raise SystemExit(f"{path}: not a .dio file (bad magic)")
    json_len = struct.unpack_from("<I", data, 4)[0]
    meta = json.loads(data[8:8 + json_len])
    off = 8 + json_len
    n, n_free = meta["count"], meta.get("free", 0)

    pos = struct.unpack_from(f"<{n * 3}f", data, off)
    nor = struct.unpack_from(f"<{n * 4}b", data, off + n * 12)
    rgba = data[off + n * 16: off + n * 20]
    free = struct.unpack_from(f"<{n_free * 10}f", data, off + n * 20)
    free_rgba = data[off + n * 20 + n_free * 40: off + n * 20 + n_free * 40 + n_free * 4]
    return meta, n, pos, nor, rgba, n_free, free, free_rgba


def normalise(v):
    length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if length < 1e-9:
        return (0.0, 1.0, 0.0)
    return (v[0] / length, v[1] / length, v[2] / length)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def tangent_frame(n, radius):
    """Two vectors of length radius, both perpendicular to n."""
    helper = (1.0, 0.0, 0.0) if abs(n[0]) < 0.9 else (0.0, 1.0, 0.0)
    t = normalise(cross(helper, n))
    b = cross(n, t)
    return tuple(c * radius for c in t), tuple(c * radius for c in b)


def rotate(q, v):
    """Rotate v by the quaternion (x, y, z, w)."""
    x, y, z, w = q
    # t = 2 * cross(q.xyz, v); v' = v + w * t + cross(q.xyz, t)
    tx = 2.0 * (y * v[2] - z * v[1])
    ty = 2.0 * (z * v[0] - x * v[2])
    tz = 2.0 * (x * v[1] - y * v[0])
    return (v[0] + w * tx + (y * tz - z * ty),
            v[1] + w * ty + (z * tx - x * tz),
            v[2] + w * tz + (x * ty - y * tx))


def record(pos, axis1, axis2, nrm, colour, flags):
    return struct.pack("<15fI", *pos, *axis1, *axis2, *nrm, *colour, flags)


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: dio_to_bytes.py <in.dio> <out.bytes>")

    meta, n, pos, nor, rgba, n_free, free, free_rgba = read_dio(sys.argv[1])
    h = meta["h"]
    radius = 0.66 * h
    baked = BAKED if meta.get("baked") else 0

    solid = bytearray()
    glow = bytearray()

    for i in range(n):
        p = pos[i * 3:i * 3 + 3]
        nrm = normalise((nor[i * 4] / 127.0, nor[i * 4 + 1] / 127.0, nor[i * 4 + 2] / 127.0))
        axis1, axis2 = tangent_frame(nrm, radius)
        colour = (rgba[i * 4] / 255.0, rgba[i * 4 + 1] / 255.0, rgba[i * 4 + 2] / 255.0)
        # the 4th normal byte only marks emissive surfels (their colour is already the albedo);
        # at render time the browser does not treat them specially either, so ignore it
        flags = baked | (255 << 8)
        solid += record(p, axis1, axis2, nrm, colour, flags)

    for i in range(n_free):
        base = i * 10
        p = free[base:base + 3]
        scale = free[base + 3:base + 6]
        q = free[base + 6:base + 10]
        colour = (free_rgba[i * 4] / 255.0, free_rgba[i * 4 + 1] / 255.0, free_rgba[i * 4 + 2] / 255.0)
        kind = free_rgba[i * 4 + 3] & 3
        alpha = (free_rgba[i * 4 + 3] >> 2) / 63.0

        axis1 = rotate(q, (scale[0], 0.0, 0.0))
        axis2 = rotate(q, (0.0, scale[1], 0.0))
        nrm = rotate(q, (0.0, 0.0, scale[2]))

        if kind == KIND_GLOW:
            # translucent light: keeps its own colour and opacity, the pixel pass blends it in
            flags = GLOW | (max(0, min(255, round(alpha * 255.0))) << 8)
            glow += record(p, axis1, axis2, nrm, colour, flags)
            continue

        flags = baked | (255 << 8)
        if kind == KIND_EMISSIVE:
            flags |= EMISSIVE
        elif kind == KIND_SWAY:
            # a blade is lit as if it faced up, and leans in the wind
            flags |= SWAY | UP_NORMAL
        solid += record(p, axis1, axis2, nrm, colour, flags)

    out = solid + glow
    with open(sys.argv[2], "wb") as f:
        f.write(out)

    total = len(out) // STRIDE
    print(f"{sys.argv[2]}: {total} surfels ({len(solid) // STRIDE} solid, {len(glow) // STRIDE} glow), "
          f"spacing {h}, radius {radius:.4f}, {len(out) / 1e6:.1f} MB")
    print("palette: " + ", ".join(meta.get("palette", [])))
    print(f"background: {meta.get('background')}")


if __name__ == "__main__":
    main()
