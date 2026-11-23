#!/usr/bin/env python3
"""Turn a <name>.rig.glb (skeleton + animation clips, no meshes) into <name>.rig, the small JSON a
player needs: bones, their inverse bind matrices, and the clips.

    python3 rig_to_json.py minotaur.rig.glb minotaur.rig

Why not just load the .glb? Godot can, Unity cannot without a glTF package, and the two ports are
meant to agree. This is a plain JSON file both can read with the tools they already have.

The positions come out in the same space as the splats: the converter recentres a model and scales
its longest side to two units, so the skeleton is put through the same transform here. Then a bone's
matrix is just `world(t) * inverseBind`, the usual formula.

Layout:

    {
      "bones": [{"parent": -1, "rest": {"t": [x,y,z], "r": [x,y,z,w], "s": [x,y,z]},
                 "ibm": [16 floats, row major]}],
      "clips": [{"name": "walk", "tracks": [
          {"bone": 3, "path": "t" | "r" | "s", "times": [...], "values": [...]}]}]
    }

Rotation tracks are quaternions in glTF's xyzw order; the player slerps them.
"""

import json
import math
import struct
import sys


def read_glb(path):
    data = open(path, "rb").read()
    if data[:4] != b"glTF":
        raise SystemExit(f"{path}: not a .glb")
    length = struct.unpack_from("<I", data, 8)[0]
    at = 12
    js = None
    blob = b""
    while at < length:
        size, kind = struct.unpack_from("<II", data, at)
        chunk = data[at + 8:at + 8 + size]
        if kind == 0x4E4F534A:
            js = json.loads(chunk)
        elif kind == 0x004E4942:
            blob = chunk
        at += 8 + size + ((4 - size % 4) % 4 if size % 4 else 0)
    if js is None:
        raise SystemExit(f"{path}: no JSON chunk")
    return js, blob


COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_accessor(js, blob, index):
    acc = js["accessors"][index]
    fmt, size = COMPONENTS[acc["componentType"]]
    width = WIDTH[acc["type"]]
    count = acc["count"]
    if "bufferView" not in acc:
        return [0.0] * (count * width)
    view = js["bufferViews"][acc["bufferView"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", width * size)
    out = []
    for i in range(count):
        off = base + i * stride
        out.extend(struct.unpack_from("<" + fmt * width, blob, off))
    return out


def to_row_major(m):
    """glTF matrices are column-major; everything here is row-major."""
    return [m[0], m[4], m[8], m[12],
            m[1], m[5], m[9], m[13],
            m[2], m[6], m[10], m[14],
            m[3], m[7], m[11], m[15]]


def mat_mul(a, b):
    return [sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4)) for r in range(4) for c in range(4)]


def mat_inverse(m):
    # 4x4 inverse, row major; the matrices here are affine, so this is a plain Gauss-Jordan
    a = [list(m[r * 4:r * 4 + 4]) + [1.0 if r == c else 0.0 for c in range(4)] for r in range(4)]
    for col in range(4):
        pivot = max(range(col, 4), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) < 1e-12:
            raise SystemExit("rig: singular matrix")
        a[col], a[pivot] = a[pivot], a[col]
        d = a[col][col]
        a[col] = [v / d for v in a[col]]
        for r in range(4):
            if r == col:
                continue
            f = a[r][col]
            if f:
                a[r] = [a[r][k] - f * a[col][k] for k in range(8)]
    return [a[r][c] for r in range(4) for c in range(4, 8)]


def trs_matrix(t, r, s):
    x, y, z, w = r
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return [
        (1 - 2 * (yy + zz)) * s[0], (2 * (xy - wz)) * s[0], (2 * (xz + wy)) * s[0], t[0],
        (2 * (xy + wz)) * s[1], (1 - 2 * (xx + zz)) * s[1], (2 * (yz - wx)) * s[1], t[1],
        (2 * (xz - wy)) * s[2], (2 * (yz + wx)) * s[2], (1 - 2 * (xx + yy)) * s[2], t[2],
        0.0, 0.0, 0.0, 1.0,
    ]


def decompose(m):
    t = [m[3], m[7], m[11]]
    s = [math.sqrt(m[0] ** 2 + m[4] ** 2 + m[8] ** 2),
         math.sqrt(m[1] ** 2 + m[5] ** 2 + m[9] ** 2),
         math.sqrt(m[2] ** 2 + m[6] ** 2 + m[10] ** 2)]
    if s[0] > 1e-9:
        r00, r10, r20 = m[0] / s[0], m[4] / s[0], m[8] / s[0]
    else:
        r00, r10, r20 = 1.0, 0.0, 0.0
    r01, r11, r21 = m[1] / s[1], m[5] / s[1], m[9] / s[1]
    r02, r12, r22 = m[2] / s[2], m[6] / s[2], m[10] / s[2]
    trace = r00 + r11 + r22
    if trace > 0:
        k = 0.5 / math.sqrt(trace + 1.0)
        q = [(r21 - r12) * k, (r02 - r20) * k, (r10 - r01) * k, 0.25 / k]
    elif r00 > r11 and r00 > r22:
        k = 2.0 * math.sqrt(1.0 + r00 - r11 - r22)
        q = [0.25 * k, (r01 + r10) / k, (r02 + r20) / k, (r21 - r12) / k]
    elif r11 > r22:
        k = 2.0 * math.sqrt(1.0 + r11 - r00 - r22)
        q = [(r01 + r10) / k, 0.25 * k, (r12 + r21) / k, (r02 - r20) / k]
    else:
        k = 2.0 * math.sqrt(1.0 + r22 - r00 - r11)
        q = [(r02 + r20) / k, (r12 + r21) / k, 0.25 * k, (r10 - r01) / k]
    return t, q, s


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: rig_to_json.py <name.rig.glb> <name.rig>")
    js, blob = read_glb(sys.argv[1])
    skin = js["skins"][0]
    joints = skin["joints"]
    parents = {j: i for i, j in enumerate(joints)}
    parent_of = {}
    for node_index, node in enumerate(js["nodes"]):
        for child in node.get("children", []):
            parent_of[child] = node_index
    ibm = js["skins"][0].get("inverseBindMatrices")
    ibms = [read_accessor(js, blob, ibm) if ibm is not None else None]

    # the same transform the splats got: recentre, then scale the longest side to two units
    centre, unit = [0.0, 0.0, 0.0], 1.0
    if len(sys.argv) > 3:
        box = json.loads(sys.argv[3])
        centre = [(box[0] + box[3]) * 0.5, (box[1] + box[4]) * 0.5, (box[2] + box[5]) * 0.5]
        unit = 2.0 / max(max(box[3] - box[0], box[4] - box[1]), box[5] - box[2])

    # the splats were recentred and scaled; take the skeleton through the same transform
    T = [unit, 0.0, 0.0, -centre[0] * unit,
         0.0, unit, 0.0, -centre[1] * unit,
         0.0, 0.0, unit, -centre[2] * unit,
         0.0, 0.0, 0.0, 1.0]

    bind = []
    for i, node_index in enumerate(joints):
        world = mat_inverse(to_row_major(ibms[0][i * 16:i * 16 + 16]))
        bind.append(mat_mul(T, world))

    bones = []
    for i, node_index in enumerate(joints):
        node_parent = parent_of.get(node_index)
        parent = parents.get(node_parent, -1)
        if parent >= 0:
            local = mat_mul(mat_inverse(bind[parent]), bind[i])
        else:
            local = bind[i]
        t, q, s = decompose(local)
        bones.append({
            "parent": parent,
            "rest": {"t": [round(v, 6) for v in t], "r": [round(v, 6) for v in q],
                     "s": [round(v, 6) for v in s]},
            "ibm": [round(v, 6) for v in mat_inverse(bind[i])],
        })

    clips = []
    for anim in js.get("animations", []):
        tracks = []
        for channel in anim["channels"]:
            target = channel.get("target", {})
            node = target.get("node")
            path = target.get("path")
            if node not in parents or path not in ("translation", "rotation", "scale"):
                continue
            sampler = anim["samplers"][channel["sampler"]]
            times = read_accessor(js, blob, sampler["input"])
            values = read_accessor(js, blob, sampler["output"])
            if sampler.get("interpolation") == "CUBICSPLINE":
                continue  # in-tangent, value, out-tangent: not carried
            is_root = bones[parents[node]]["parent"] < 0
            if path == "translation":
                if is_root:
                    # the root also carries T, the transform that recentres the model
                    moved = []
                    for i in range(0, len(values), 3):
                        moved += [(values[i] - centre[0]) * unit,
                                  (values[i + 1] - centre[1]) * unit,
                                  (values[i + 2] - centre[2]) * unit]
                    values = moved
                # a child's local translation is already relative to its parent, so T cancels:
                # leave it in the model's own units
            elif path == "scale" and is_root:
                values = [v * unit for v in values]
            tracks.append({
                "bone": parents[node],
                "path": path[0],
                "times": [round(v, 5) for v in times],
                "values": [round(v, 5) for v in values],
            })
        clips.append({"name": anim.get("name", f"clip{len(clips)}"), "tracks": tracks})

    with open(sys.argv[2], "w") as f:
        json.dump({"bones": bones, "clips": clips}, f, separators=(",", ":"))

    print(f"{sys.argv[2]}: {len(bones)} bones, {len(clips)} clips "
          f"({', '.join(c['name'] for c in clips)}), scaled by {unit:.3f}")


if __name__ == "__main__":
    main()
