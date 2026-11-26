#!/usr/bin/env python3
"""Generate the planet meshes of the Hearthian theme as glTF (.glb) files in models/generated/.

Every mesh is procedural (noise, craters, dunes, vines).
Each body is centred on the origin, Y up, with a radius of about 1; HearthianSystem.qml scales it.
Colours are stored per vertex (COLOR_0), so no textures are needed.
Needs Python 3 and NumPy (python-numpy). Run: python3 tools/make_hearthian_meshes.py [--check]
"""
import json
import os
import struct
import sys

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models", "generated")


# ---- geometry helpers -----------------------------------------------------------------------------------------

def icosphere(level):
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    verts = [np.array(p, float) / np.linalg.norm(p) for p in v]
    for _ in range(level):
        cache, nf = {}, []

        def mid(a, b):
            k = (a, b) if a < b else (b, a)
            if k not in cache:
                m = verts[a] + verts[b]
                verts.append(m / np.linalg.norm(m))
                cache[k] = len(verts) - 1
            return cache[k]
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    return np.array(verts), np.array(f, dtype=np.uint32)


def normals(p, f):
    n = np.zeros_like(p)
    fn = np.cross(p[f[:, 1]] - p[f[:, 0]], p[f[:, 2]] - p[f[:, 0]])
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


def merge(*parts):
    ps, fs, cs, off = [], [], [], 0
    for p, f, c in parts:
        ps.append(p); fs.append(f + off); cs.append(c); off += len(p)
    return np.vstack(ps), np.vstack(fs).astype(np.uint32), np.vstack(cs)


# ---- noise ----------------------------------------------------------------------------------------------------

class Noise:
    """Fractal 3D value noise, vectorised."""

    def __init__(self, seed):
        self.perm = np.random.default_rng(seed).permutation(512).astype(np.int64)
        self.vals = np.random.default_rng(seed + 1).random(512) * 2 - 1

    def _lattice(self, i, j, k):
        p = self.perm
        return self.vals[p[(p[(p[i & 511] + j) & 511] + k) & 511]]

    def value(self, x):
        i = np.floor(x).astype(np.int64)
        fr = x - i
        u = fr * fr * (3 - 2 * fr)
        out = 0
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                    out = out + w * self._lattice(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
        return out

    def fbm(self, x, octaves=5, freq=2.0, gain=0.5):
        out, amp, norm = 0, 1.0, 0
        for o in range(octaves):
            out = out + amp * self.value(x * freq * 2 ** o + o * 17.3)
            norm += amp
            amp *= gain
        return out / norm

    def ridged(self, x, octaves=4, freq=2.0):
        return 1 - np.abs(self.fbm(x, octaves, freq))


def mix(a, b, t):
    t = np.clip(t, 0, 1)[:, None]
    return np.asarray(a, float) * (1 - t) + np.asarray(b, float) * t


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def crater(p, centre, size):
    """Bowl (negative) with a raised rim; returns height change per vertex."""
    c = np.asarray(centre, float) / np.linalg.norm(centre)
    d = np.arccos(np.clip(p @ c, -1, 1)) / size
    bowl = np.where(d < 1, -(1 - d ** 2), 0)
    rim = np.exp(-((d - 1) / 0.25) ** 2) * 0.35
    return bowl + rim


def random_dirs(rng, n):
    d = rng.normal(size=(n, 3))
    return d / np.linalg.norm(d, axis=1, keepdims=True)


# ---- bodies ---------------------------------------------------------------------------------------------------

def timber_hearth():
    p, f = icosphere(6)
    n = Noise(1)
    hills = n.fbm(p, 6, 1.6)
    peaks = np.clip(n.ridged(p, 4, 1.3) - 0.55, 0, None) * 1.6
    pit = crater(p, (0.5, 0.45, 0.75), 0.5)                     # the big village crater
    h = 0.035 * hills + 0.09 * peaks + 0.1 * pit
    col = mix(rgb("#35522a"), rgb("#6a8a45"), hills * 1.5 + 0.5)
    col = mix(col, rgb("#7d6a52"), (h - 0.025) * 30)            # rock above the tree line
    col = mix(col, rgb("#e6e4dc"), (h - 0.075) * 40)            # snowy peaks
    col = mix(col, rgb("#8fa860"), -pit * 0.8)                  # brighter crater floor
    col = mix(col, rgb("#6b5a45"), pit * 2.5)                   # bare rocky rim
    col = mix(col, rgb("#4b7fa8"), (-0.02 - h) * 60)            # a little water in the lowest spots
    return p * (1 + h)[:, None], f, col


def attlerock():
    p, f = icosphere(5)
    n = Noise(2)
    rng = np.random.default_rng(2)
    h = 0.04 * n.fbm(p, 5, 2.0)
    dark = np.zeros(len(p))
    for c, s in zip(random_dirs(rng, 28), rng.uniform(0.08, 0.35, 28)):
        cr = crater(p, c, s)
        h += 0.06 * s * cr * 3
        dark = np.maximum(dark, -cr)
    col = mix(rgb("#a39e96"), rgb("#6d6a66"), dark * 0.7 + n.fbm(p * 3, 3) * 0.4)
    return p * (1 + h)[:, None], f, col


def ash_twin():
    p, f = icosphere(5)
    n = Noise(3)
    warp = n.fbm(p, 3, 1.5)
    dunes = (np.sin((p[:, 0] * 3 + p[:, 2] * 2 + warp * 6) * 5) * 0.5 + 0.5) * (0.6 + 0.8 * n.fbm(p * 2.5, 3))
    h = 0.015 * dunes + 0.025 * n.fbm(p, 4, 1.2)
    col = mix(rgb("#c98a50"), rgb("#ecc08a"), dunes * 0.6 + warp)
    return p * (1 + h)[:, None], f, col


def ember_twin():
    p, f = icosphere(5)
    n = Noise(4)
    ridges = n.ridged(p, 5, 1.8)
    canyon = np.clip(0.25 - np.abs(n.fbm(p, 3, 1.1)), 0, None) * 4    # winding canyons
    h = 0.05 * ridges - 0.07 * canyon
    col = mix(rgb("#8f4128"), rgb("#c26a42"), ridges)
    col = mix(col, rgb("#4a2418"), canyon * 1.5)
    return p * (1 + h)[:, None], f, col


def brittle_hollow():
    """A crust shell with holes in it; the black hole is drawn in QML."""
    p, f = icosphere(5)
    n = Noise(5)
    hole = n.fbm(p, 4, 1.4)
    keep = hole[f].max(axis=1) < 0.2                            # drop triangles inside the holes
    f = f[keep]
    edge = np.clip((hole + 0.02) / 0.22, 0, 1)                    # darker cracked rim around each hole
    h = 0.03 * n.fbm(p * 2, 4) - 0.04 * edge
    col = mix(rgb("#6b5b7a"), rgb("#8a93b8"), n.fbm(p * 1.7, 3) + 0.4)
    col = mix(col, rgb("#2b2233"), edge)
    return p * (1 + h)[:, None], f, col


def hollows_lantern():
    p, f = icosphere(4)
    n = Noise(6)
    vein = np.clip(1 - np.abs(n.fbm(p, 4, 1.8)) * 7, 0, 1)      # glowing lava channels
    h = 0.05 * n.fbm(p, 4, 1.5) - 0.02 * vein
    col = mix(rgb("#4a3026"), rgb("#ffb347"), vein)
    col = mix(col, rgb("#fff0b0"), vein ** 4)
    return p * (1 + h)[:, None], f, col


def giants_deep():
    """Ocean with swirling storm bands and a few islands; the cyclones are drawn in QML."""
    p, f = icosphere(6)
    n = Noise(7)
    lat = p[:, 1] + 0.25 * n.fbm(p, 4, 1.4)
    bands = np.sin(lat * 9) * 0.5 + 0.5
    islands = np.clip(n.fbm(p, 5, 2.2) - 0.42, 0, None) * 6
    h = 0.025 * islands
    col = mix(rgb("#1f6e73"), rgb("#3fa69b"), bands * 0.7 + n.fbm(p * 2, 3) * 0.3)
    col = mix(col, rgb("#c9e8df"), (bands - 0.85) * 5)          # pale storm streaks
    col = mix(col, rgb("#5f8f3f"), islands * 2)
    return p * (1 + h)[:, None], f, col


def tube(path, radius, sides=10):
    """Tube along `path` (N x 3) with per-point `radius` (N)."""
    tng = np.gradient(path, axis=0)
    tng /= np.linalg.norm(tng, axis=1, keepdims=True)
    up = np.array([0.0, 1.0, 0.0])
    a = np.cross(tng, up)
    a[np.linalg.norm(a, axis=1) < 1e-6] = (1, 0, 0)
    a /= np.linalg.norm(a, axis=1, keepdims=True)
    b = np.cross(tng, a)
    ang = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    ring = np.cos(ang)[None, :, None] * a[:, None, :] + np.sin(ang)[None, :, None] * b[:, None, :]
    pts = (path[:, None, :] + ring * radius[:, None, None]).reshape(-1, 3)
    faces = []
    for i in range(len(path) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            a0, a1, b0, b1 = i * sides + j, i * sides + k, (i + 1) * sides + j, (i + 1) * sides + k
            faces += [(a0, b0, a1), (a1, b0, b1)]
    tip = len(pts)                                                 # close the end with a point
    pts = np.vstack([pts, path[-1] + tng[-1] * radius[-1] * 2])
    last = (len(path) - 1) * sides
    faces += [(last + j, tip, last + (j + 1) % sides) for j in range(sides)]
    return pts, np.array(faces, dtype=np.uint32)


def dark_bramble():
    """A knotted core with thorny vines reaching out; the fog is drawn in QML."""
    rng = np.random.default_rng(8)
    n = Noise(8)
    cp, cf = icosphere(4)
    cp = cp * (0.36 * (1 + 0.15 * n.fbm(cp, 4, 2.0)))[:, None]
    parts = [(cp, cf, mix(rgb("#22301f"), rgb("#3b4a33"), n.fbm(cp * 3, 3) + 0.5))]
    for d in random_dirs(rng, 11):
        side = np.cross(d, rng.normal(size=3)); side /= np.linalg.norm(side)
        s = np.linspace(0, 1, 24)
        bend = np.sin(s * np.pi * rng.uniform(0.8, 1.6)) * rng.uniform(0.1, 0.25)
        path = d[None] * (0.3 + 0.68 * s)[:, None] + side[None] * bend[:, None]
        rad = 0.13 * (1 - 0.7 * s) + 0.015
        tp, tf = tube(path, rad)
        parts.append((tp, tf, np.tile(rgb("#3b2f28"), (len(tp), 1)) * rng.uniform(0.85, 1.1)))
        for k in range(4):                                         # thorns
            i = int(5 + k * 4 + rng.integers(0, 3))
            out = np.cross(path[i + 1] - path[i], rng.normal(size=3)); out /= np.linalg.norm(out)
            tpath = path[i][None] + out[None] * np.linspace(0, 0.16, 4)[:, None]
            hp, hf = tube(tpath, np.linspace(rad[i] * 0.5, 0.004, 4), sides=6)
            parts.append((hp, hf, np.tile(rgb("#6b5848"), (len(hp), 1))))
    return merge(*parts)


def interloper():
    p, f = icosphere(5)
    n = Noise(9)
    h = 0.18 * n.fbm(p, 3, 0.9) + 0.03 * n.fbm(p, 4, 3.0)       # lumpy, not round
    col = mix(rgb("#cfe8f2"), rgb("#f4fbff"), n.fbm(p * 2, 3) + 0.5)
    col = mix(col, rgb("#8a9ba6"), (n.fbm(p * 1.3, 3) - 0.2) * 2.5)   # greyer dusty patches
    return p * (1 + h)[:, None], f, col


def quantum_moon():
    p, f = icosphere(5)
    n = Noise(10)
    h = 0.06 * n.fbm(p, 4, 1.2) + 0.02 * n.ridged(p, 3, 3.0)
    col = mix(rgb("#6f6990"), rgb("#a7a0c8"), n.fbm(p * 1.5, 4) + 0.5)
    return p * (1 + h)[:, None], f, col


BODIES = {
    "timber_hearth": timber_hearth, "attlerock": attlerock, "ash_twin": ash_twin, "ember_twin": ember_twin,
    "brittle_hollow": brittle_hollow, "hollows_lantern": hollows_lantern, "giants_deep": giants_deep,
    "dark_bramble": dark_bramble, "interloper": interloper, "quantum_moon": quantum_moon,
}
DOUBLE_SIDED = {"brittle_hollow"}   # its holes show the inside of the shell


# ---- glTF writer ----------------------------------------------------------------------------------------------

def write_glb(path, p, f, col, double_sided=False):
    p = p.astype(np.float32)
    n = normals(p, f).astype(np.float32)
    lin = np.clip(col, 0, 1) ** 2.2                               # glTF vertex colours are linear; ours are sRGB
    c = np.hstack([lin * 255, np.full((len(col), 1), 255)]).round().astype(np.uint8)
    idx = f.astype(np.uint32).ravel()
    chunks = [p.tobytes(), n.tobytes(), c.tobytes(), idx.tobytes()]
    blob, views = b"", []
    for data, target in zip(chunks, (34962, 34962, 34962, 34963)):
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob += data + b"\0" * (-len(data) % 4)
    gltf = {
        "asset": {"version": "2.0", "generator": "solar-lock make_hearthian_meshes.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1},
                       "doubleSided": double_sided}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(p), "type": "VEC3",
             "min": p.min(axis=0).tolist(), "max": p.max(axis=0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(p), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5121, "normalized": True, "count": len(p), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"}],
        "bufferViews": views, "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        fh.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        fh.write(struct.pack("<II", len(blob), 0x004E4942) + blob)


def check(path):
    """Re-read a .glb and validate its structure (self-test)."""
    data = open(path, "rb").read()
    magic, ver, total = struct.unpack_from("<III", data)
    assert magic == 0x46546C67 and ver == 2 and total == len(data), path
    jlen, jtype = struct.unpack_from("<II", data, 12)
    gltf = json.loads(data[20:20 + jlen])
    blen, btype = struct.unpack_from("<II", data, 20 + jlen)
    assert jtype == 0x4E4F534A and btype == 0x004E4942 and blen == gltf["buffers"][0]["byteLength"], path
    acc = gltf["accessors"]
    nverts = acc[0]["count"]
    idx = np.frombuffer(data, np.uint32, acc[3]["count"], 28 + jlen + gltf["bufferViews"][3]["byteOffset"])
    assert idx.max() < nverts and acc[3]["count"] % 3 == 0, path
    r = np.max(np.abs(acc[0]["max"] + acc[0]["min"]))
    assert 0.5 < r < 1.6, (path, r)
    return nverts, acc[3]["count"] // 3


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, make in BODIES.items():
        dest = os.path.join(OUT, name + ".glb")
        if "--check" not in sys.argv:
            p, f, col = make()
            write_glb(dest, p, f, col, name in DOUBLE_SIDED)
        v, t = check(dest)
        print(f"{'checked' if '--check' in sys.argv else 'made   '} {name}.glb  {v} vertices, {t} triangles")
    print("done")
