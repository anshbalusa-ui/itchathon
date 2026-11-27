#!/usr/bin/env python3
"""Convert the pinned CC0 showcase payload into deterministic Studio JSON assets."""
from __future__ import annotations
import hashlib
import json
import math
import struct
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "DevelopmentAssets/HumanShowcase/human-showcase-v1.bin"
EXPECTED_SOURCE_SHA256 = "6977bd1aeba54c9f4ef82f9d7f9b8b996d030b2758e226b61dcb9fbccfe4f6e9"
NAMESPACE = uuid.UUID("e145e6d4-e742-4bf2-9042-8c2ee6d1c044")
CREATED = "2026-11-26T00:00:00.000Z"
NOTICE = (
    "CC0 1.0 Universal: https://creativecommons.org/publicdomain/zero/1.0/legalcode. "
    "MakeHuman asset only; no AGPL software. Original body OBJ: "
    "https://raw.githubusercontent.com/makehumancommunity/makehuman2/"
    "3ef8a20dfec873fdf84d3315aeaf98694cad91bf/data/base/hm08/base.obj; "
    "SHA256 9e8e529a386823fa0af5aa0cf4f082076f24f0f1a1a904003b2ab2b57b911342. "
    "Repository authored shirt, shorts, 2D illustration and derived variants are CC0. "
    "Fit Model A preserves the 1.80m canonical source; B applies x1.12/y0.95/z1.08 "
    "about z=0.055m. Authored geometry, not personal scans or population percentiles. "
    "Garment previews adapt to the reference model; no physical sizing or simulation."
)


def decode(data: bytes) -> dict[int, tuple[list[tuple[float, ...]], list[int]]]:
    if data[:8] != b"FCHUMAN1" or len(data) < 13:
        raise ValueError("Unsupported FCHUMAN1 payload")
    version, = struct.unpack_from("<I", data, 8)
    if version != 1:
        raise ValueError(f"Unsupported FCHUMAN1 version {version}")
    pos = 12
    meshes = {}
    for expected_kind in range(4):
        if pos + 13 > len(data):
            raise ValueError("Truncated mesh header")
        kind, vertex_count, index_count, gap_count = struct.unpack_from("<BIII", data, pos)
        pos += 13
        if kind != expected_kind or vertex_count == 0 or index_count == 0 or index_count % 3:
            raise ValueError("Unexpected mesh ordering or topology")
        if pos + vertex_count * 24 + index_count * 2 + gap_count * 4 > len(data):
            raise ValueError("Truncated mesh data")
        vertices = [struct.unpack_from("<6f", data, pos + i * 24) for i in range(vertex_count)]
        pos += vertex_count * 24
        indices = list(struct.unpack_from(f"<{index_count}H", data, pos))
        pos += index_count * 2 + gap_count * 4
        if any(not math.isfinite(x) for vertex in vertices for x in vertex):
            raise ValueError("Non-finite mesh data")
        if any(i >= vertex_count for i in indices):
            raise ValueError("Mesh index outside vertex array")
        meshes[kind] = (vertices, indices)
    if pos != len(data):
        raise ValueError("Trailing bytes in FCHUMAN1 payload")
    return meshes


def normalize(v):
    length = math.sqrt(sum(x * x for x in v))
    if not math.isfinite(length) or length <= 1e-12:
        raise ValueError("Invalid zero-length normal")
    return [x / length for x in v]


def mesh_data(vertices, indices, scales=(1.0, 1.0, 1.0)):
    positions, normals = [], []
    for vertex in vertices:
        p, n = vertex[:3], vertex[3:]
        if scales == (1.0, 1.0, 1.0):
            transformed = list(p)
            normal = list(n)
        else:
            transformed = [p[0] * scales[0], p[1] * scales[1], 0.055 + (p[2] - 0.055) * scales[2]]
            normal = normalize([n[0] / scales[0], n[1] / scales[1], n[2] / scales[2]])
        positions.extend(transformed)
        normals.extend(normal)
    return {"format": "onyou-mesh-v1", "positions": positions, "normals": normals, "indices": indices}


def main():
    raw = SOURCE.read_bytes()
    source_hash = hashlib.sha256(raw).hexdigest()
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise SystemExit(f"Pinned human showcase SHA-256 mismatch: {source_hash}")
    decoded = decode(raw)
    out = ROOT / "Studio/public/assets"
    out.mkdir(parents=True, exist_ok=True)
    (out / "LICENSE.txt").write_bytes((ROOT / "DevelopmentAssets/HumanShowcase/LICENSE.txt").read_bytes())
    (out / "NOTICE.txt").write_text(
        "On You Studio offline geometry assets\n\n"
        "Body geometry derives from the pinned MakeHuman Community base asset and first-party authored shirt/shorts surfaces in\n"
        "DevelopmentAssets/HumanShowcase/human-showcase-v1.bin (FCHUMAN1 v1).\n"
        f"Source payload SHA-256: {source_hash}\n"
        "Pinned source and license detail: DevelopmentAssets/HumanShowcase/NOTICE.txt.\n"
        "Model A preserves the canonical source coordinates. Model B is authored display geometry with affine scales x1.12, y0.95, z1.08 about z=0.055m.\n"
        "Both variants are illustrative; B is not a percentile or accurate person. Garment surfaces are fit previews, not size changes.\n"
        f"No MakeHuman software is included. All derived geometry and this conversion script are CC0-1.0.\n\n{NOTICE}\n",
        encoding="utf-8")
    variants = [("a", "Fit Model A", (1.0, 1.0, 1.0)), ("b", "Fit Model B", (1.12, 0.95, 1.08))]
    source = {"label": "MakeHuman CC0 body and On You authored garment previews", "uri": "https://github.com/anshbalusa-ui/itchathon/blob/075db5abdaef95a0ae0fd9adee67c8bee16b1f7f/DevelopmentAssets/HumanShowcase/human-showcase-v1.bin", "sha256": source_hash, "license": "CC0-1.0", "notice": NOTICE}
    descriptors, payloads, models = [], [], []
    asset_ids = {}
    model_ids = {}
    for key, model_name, scales in variants:
        model_id = str(uuid.uuid5(NAMESPACE, f"fit-model-{key}"))
        body_id = str(uuid.uuid5(NAMESPACE, f"{key}-body"))
        model_ids[key] = model_id
        asset_ids[(key, "body")] = body_id
        models.append({"schemaVersion": 1, "id": model_id, "modelId": str(uuid.uuid5(NAMESPACE, f"model-family-{key}")), "parentRevisionId": None, "name": model_name, "createdAt": CREATED, "producer": {"name": "On You Studio", "version": "0.1.0"}, "geometryKind": "standardFitModel", "bodyMeshAssetId": body_id, "baseGarmentMeshAssetId": str(uuid.uuid5(NAMESPACE, f"{key}-shorts")), "poseId": "authored-standing-v1", "heightM": 1.8 * scales[1], "measurementBasis": "authored-mesh-bounds", "source": source, "validationStatus": "illustrative"})
        for kind, source_kind in (("body", 0), ("shirt", 1), ("shorts", 3)):
            aid = body_id if kind == "body" else str(uuid.uuid5(NAMESPACE, f"{key}-{kind}"))
            asset_ids[(key, kind)] = aid
            verts, indices = decoded[source_kind]
            data = mesh_data(verts, indices, scales)
            data_text = json.dumps(data, separators=(",", ":"), allow_nan=False)
            digest = hashlib.sha256(data_text.encode("utf-8")).hexdigest()
            topo = hashlib.sha256(b"".join(struct.pack("<I", i) for i in indices)).hexdigest()
            points = [data["positions"][i:i + 3] for i in range(0, len(data["positions"]), 3)]
            low = [min(p[k] for p in points) for k in range(3)]
            high = [max(p[k] for p in points) for k in range(3)]
            matrix = [scales[0], 0, 0, 0, 0, scales[1], 0, 0, 0, 0, scales[2], 0, 0, 0, 0.055 * (1 - scales[2]), 1]
            desc = {"schemaVersion": 1, "id": aid, "createdAt": CREATED, "producer": {"name": "On You Studio", "version": "0.1.0"}, "format": "onyou-mesh-v1", "sha256": digest, "byteLength": len(data_text.encode("utf-8")), "vertexCount": len(points), "indexCount": len(indices), "topologyVersion": 1, "topologySha256": topo, "units": "m", "coordinates": {"handedness": "right", "up": "+Y", "front": "+Z", "winding": "counter-clockwise", "matrixOrder": "column-major"}, "bounds": {"minimum": low, "maximum": high}, "source": source, "sourceToCanonical": {"sourceFrameId": "fitcheck-human-showcase-v1", "canonicalFrameId": "onyou-y-up-m", "matrix": matrix}, "validationStatus": "illustrative"}
            descriptors.append(desc)
            payloads.append({"id": aid, "data": data_text})
            (out / f"{aid}.json").write_text(data_text, encoding="utf-8")
    outline = [[-0.105, 1.49], [-0.22, 1.46], [-0.31, 1.34], [-0.47, 1.22], [-0.39, 1.12], [-0.29, 1.22], [-0.27, 0.99], [0.27, 0.99], [0.29, 1.22], [0.39, 1.12], [0.47, 1.22], [0.31, 1.34], [0.22, 1.46], [0.105, 1.49], [0.08, 1.405], [0, 1.38], [-0.08, 1.405]]
    neckline = [[-0.12, 1.48], [-0.095, 1.395], [0, 1.365], [0.095, 1.395], [0.12, 1.48]]
    template = {"id": str(uuid.uuid5(NAMESPACE, "tshirt-template")), "version": "1.0.0", "name": "Authored basic T-shirt", "category": "tshirt", "geometryAdapter": "authored-preview-v1", "supportedVisualParameters": ["color"], "drawing": {"kind": "illustrative-outline-v1", "units": "m", "outline": outline, "neckline": neckline}, "previewMeshes": [{"fitModelRevisionId": model_ids[v], "meshAssetId": asset_ids[(v, "shirt")]} for v, _, _ in variants], "source": source}
    catalog = {"schemaVersion": 1, "template": template, "fitModels": models, "meshAssets": descriptors}
    (out / "catalog.json").write_text(json.dumps(catalog, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(f"Generated {len(descriptors)} mesh assets from pinned {source_hash}; {len(payloads)} payloads, catalog {out / 'catalog.json'}")

if __name__ == "__main__":
    main()
