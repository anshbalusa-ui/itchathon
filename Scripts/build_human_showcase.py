#!/usr/bin/env python3
"""Convert pinned MakeHuman CC0 mesh to our reproducible showcase package.

Source is MakeHuman Community `data/base/hm08/base.obj` at commit
3ef8a20dfec873fdf84d3315aeaf98694cad91bf:
https://raw.githubusercontent.com/makehumancommunity/makehuman2/3ef8a20dfec873fdf84d3315aeaf98694cad91bf/data/base/hm08/base.obj
Source SHA-256:
9e8e529a386823fa0af5aa0cf4f082076f24f0f1a1a904003b2ab2b57b911342.
No third-party packages or MakeHuman program code are used.
Run: python3 Scripts/build_human_showcase.py /path/to/base.obj [output.bin]
"""
from __future__ import annotations
import hashlib
import math
import struct
import sys
from pathlib import Path

EXPECTED = "9e8e529a386823fa0af5aa0cf4f082076f24f0f1a1a904003b2ab2b57b911342"
MAGIC = b"FCHUMAN1"
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "DevelopmentAssets/HumanShowcase/human-showcase-v1.bin"

def parse_obj(path: Path):
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED:
        raise SystemExit(f"source SHA-256 mismatch: {digest}")
    positions, faces, group = [], [], ""
    for line in raw.decode("utf-8").splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "v":
            positions.append(tuple(map(float, fields[1:4])))
        elif fields[0] == "g":
            group = fields[1] if len(fields) > 1 else ""
        elif fields[0] == "f" and group == "body":
            polygon = tuple(int(v.split("/", 1)[0]) - 1 for v in fields[1:])
            for j in range(1, len(polygon)-1):
                faces.append((polygon[0], polygon[j], polygon[j+1]))
    return positions, faces

def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def sub(a,b): return (a[0]-b[0],a[1]-b[1],a[2]-b[2])
def unit(v):
    length = math.sqrt(sum(x*x for x in v))
    return tuple(x/length for x in v) if length > 1e-12 else (0.,1.,0.)
def convert(points, faces):
    used = sorted({i for f in faces for i in f})
    low = min(points[i][1] for i in used); high = max(points[i][1] for i in used)
    scale = 1.8 / (high-low)
    # MakeHuman vertical Y becomes renderer +Y; its +Z faces forward.
    transformed = [(points[i][0]*scale, (points[i][1]-low)*scale, points[i][2]*scale) for i in used]
    remap = {old:new for new,old in enumerate(used)}
    return transformed, [tuple(remap[i] for i in f) for f in faces]

def normals(vertices, faces):
    sums = [[0.,0.,0.] for _ in vertices]
    for a,b,c in faces:
        n = cross(sub(vertices[b],vertices[a]), sub(vertices[c],vertices[a]))
        for i in (a,b,c):
            for k in range(3): sums[i][k] += n[k]
    return [unit(n) for n in sums]

def clip_polygon(polygon, normal, limit):
    """Clip a shell triangle to a plane, preserving interpolated sample spacing."""
    if not polygon:
        return []
    output = []
    previous = polygon[-1]
    previous_distance = sum(previous[k] * normal[k] for k in range(3)) - limit
    for current in polygon:
        distance = sum(current[k] * normal[k] for k in range(3)) - limit
        if (distance <= 1e-10) != (previous_distance <= 1e-10):
            t = max(0., min(1., previous_distance / (previous_distance - distance)))
            output.append(tuple(previous[k] + t * (current[k] - previous[k]) for k in range(4)))
        if distance <= 1e-10:
            output.append(current)
        previous, previous_distance = current, distance
    return output

def sample_gap(mode, point):
    x, y, _ = point
    def smoothstep(t):
        t = max(0., min(1., t))
        return t * t * (3. - 2. * t)
    if mode == 3:
        return .012 + .004 * smoothstep((y - .75) / .25)
    gap = .005 + .025 * smoothstep((1.24 - y) / .25)
    if mode == 1:
        gap = max(gap, .005 + .017 * smoothstep((abs(x) - .20) / .12))
    return gap

def make_mesh(body, body_faces, mode):
    body_normals = normals(body, body_faces)
    if mode == 0:
        return body, body_normals, body_faces, []
    # Offset the complete body before cutting: cropped-surface normals and abrupt
    # spacing changes cause intersections. Weld exact clipped boundaries rather
    # than selecting triangle centroids, which leaves visibly ragged hems.
    shifted = []
    for point, normal in zip(body, body_normals):
        gap = sample_gap(mode, point)
        shifted.append(tuple(point[k] + normal[k] * gap for k in range(3)) + (gap,))
    vertices, clearance, faces, lookup = [], [], [], {}
    def index(point):
        key = tuple(round(value, 9) for value in point[:3])
        if key not in lookup:
            lookup[key] = len(vertices)
            vertices.append(point[:3])
            clearance.append(point[3])
        return lookup[key]
    for triangle in body_faces:
        polygon = [shifted[i] for i in triangle]
        low, high = (.66, 1.01) if mode == 3 else (.99, 1.505)
        polygon = clip_polygon(polygon, (0., -1., 0.), -low)
        polygon = clip_polygon(polygon, (0., 1., 0.), high)
        regions = [polygon]
        if mode in (1, 2):
            # A widening torso leaves room at the hem; the sleeve cut is
            # perpendicular to the A-pose upper arm, not the wrist.
            torso = clip_polygon(polygon, (1., .28, 0.), .59)
            torso = clip_polygon(torso, (-1., .28, 0.), .59)
            regions = [torso]
            if mode == 1:
                for side in (-1., 1.):
                    sleeve = clip_polygon(polygon, (-side, -.28, 0.), -.59)
                    sleeve = clip_polygon(sleeve, (.6 * side, -.8, 0.), -.86)
                    regions.append(sleeve)
        for region in regions:
            ids = []
            for point in region:
                value = index(point)
                if not ids or value != ids[-1]:
                    ids.append(value)
            if len(ids) > 1 and ids[0] == ids[-1]:
                ids.pop()
            for j in range(1, len(ids) - 1):
                face = (ids[0], ids[j], ids[j + 1])
                area = cross(sub(vertices[face[1]], vertices[face[0]]),
                             sub(vertices[face[2]], vertices[face[0]]))
                if sum(component * component for component in area) > 1e-20:
                    faces.append(face)
    if not faces or len(vertices) > 65535:
        raise ValueError("invalid garment mesh")
    return vertices, normals(vertices, faces), faces, clearance

def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: build_human_showcase.py /path/to/pinned/base.obj [output.bin]")
    src=Path(sys.argv[1])
    dst=Path(sys.argv[2]) if len(sys.argv)>2 else DEFAULT_OUTPUT
    points,source_faces=parse_obj(src)
    body,body_faces=convert(points,source_faces)
    meshes=[make_mesh(body,body_faces,kind) for kind in range(4)]
    payload=bytearray(MAGIC+struct.pack("<I",1))
    for kind,(verts,ns,faces,gaps) in enumerate(meshes):
        payload += struct.pack("<BIII",kind,len(verts),len(faces)*3,len(gaps))
        for p,n in zip(verts,ns): payload += struct.pack("<6f",*p,*n)
        for tri in faces: payload += struct.pack("<3H",*tri)
        if gaps: payload += struct.pack(f"<{len(gaps)}f",*gaps)
    dst.parent.mkdir(parents=True,exist_ok=True); dst.write_bytes(payload)
    print(f"wrote {dst}: {len(payload)} bytes sha256={hashlib.sha256(payload).hexdigest()}")
    for kind,m in enumerate(meshes): print(f"mesh {kind}: vertices={len(m[0])} triangles={len(m[2])} clearance={len(m[3])}")

if __name__ == "__main__": main()
