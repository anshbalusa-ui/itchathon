import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BufferAttribute } from 'three';
import { describe, it } from 'node:test';
import type { AdmittedMesh, Catalog, FitModelRevision, GarmentRevision, MeshData } from '../src/domain/types';
import { createPreviewGeometry } from '../src/rendering/preview';

const assetsRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../public/assets');
const catalog = JSON.parse(await readFile(resolve(assetsRoot, 'catalog.json'), 'utf8')) as Catalog;

async function modelMeshes(model: FitModelRevision): Promise<ReadonlyMap<string, AdmittedMesh>> {
  const ids = [model.bodyMeshAssetId, model.baseGarmentMeshAssetId, ...catalog.template.previewMeshes
    .filter((preview) => preview.fitModelRevisionId === model.id).map((preview) => preview.meshAssetId)];
  const uniqueIds = [...new Set(ids)];
  const entries = await Promise.all(uniqueIds.map(async (id) => {
    const descriptor = catalog.meshAssets.find((asset) => asset.id === id);
    assert.ok(descriptor, `Catalog has descriptor for ${id}`);
    const data = await readFile(resolve(assetsRoot, `${id}.json`), 'utf8');
    assert.equal(data.length, descriptor.byteLength);
    assert.equal(createHash('sha256').update(data, 'utf8').digest('hex'), descriptor.sha256);
    return [id, { descriptor, mesh: JSON.parse(data) as MeshData }] as const;
  }));
  return new Map(entries);
}

function revision(): GarmentRevision {
  return {
    schemaVersion: 1,
    id: '00000000-0000-4000-8000-000000000001',
    garmentId: '00000000-0000-4000-8000-000000000002',
    parentRevisionId: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    producer: { name: 'On You Studio', version: '0.1.0' },
    name: catalog.template.name,
    category: catalog.template.category,
    templateId: catalog.template.id,
    templateVersion: catalog.template.version,
    geometryAdapter: catalog.template.geometryAdapter,
    visualMaterial: { color: '#287b80' },
    drawing: catalog.template.drawing,
    previewMeshes: catalog.template.previewMeshes,
    source: catalog.template.source,
    validationStatus: 'illustrative',
  };
}

describe('generated illustrative geometry', () => {
  it('contains six finite indexed canonical meshes with reproducible content and topology hashes', async () => {
    assert.equal(catalog.meshAssets.length, 6);
    assert.equal(new Set(catalog.meshAssets.map((asset) => asset.id)).size, 6);
    assert.equal(catalog.fitModels.length, 2);
    for (const model of catalog.fitModels) {
      assert.equal(model.source.license, 'CC0-1.0');
      assert.equal(model.source.sha256, '6977bd1aeba54c9f4ef82f9d7f9b8b996d030b2758e226b61dcb9fbccfe4f6e9');
      const meshes = await modelMeshes(model);
      for (const id of [model.bodyMeshAssetId, model.baseGarmentMeshAssetId,
        ...catalog.template.previewMeshes.filter((p) => p.fitModelRevisionId === model.id).map((p) => p.meshAssetId)]) {
        const admitted = meshes.get(id);
        assert.ok(admitted);
        const { descriptor, mesh } = admitted;
        assert.deepEqual(descriptor.coordinates, { handedness: 'right', up: '+Y', front: '+Z', winding: 'counter-clockwise', matrixOrder: 'column-major' });
        assert.equal(mesh.positions.length, descriptor.vertexCount * 3);
        assert.equal(mesh.normals.length, descriptor.vertexCount * 3);
        assert.equal(mesh.indices.length, descriptor.indexCount);
        assert.ok(mesh.positions.every(Number.isFinite));
        assert.ok(mesh.normals.every(Number.isFinite));
        assert.ok(mesh.indices.every((index) => Number.isInteger(index) && index >= 0 && index < descriptor.vertexCount));
        const topologyBytes = Buffer.alloc(mesh.indices.length * 4);
        mesh.indices.forEach((index, i) => topologyBytes.writeUInt32LE(index, i * 4));
        assert.equal(createHash('sha256').update(topologyBytes).digest('hex'), descriptor.topologySha256);
        const edges = new Map<string, [number, number]>();
        for (let offset = 0; offset < mesh.indices.length; offset += 3) {
          const triangle = mesh.indices.slice(offset, offset + 3);
          for (let edge = 0; edge < 3; edge++) {
            const a = triangle[edge], b = triangle[(edge + 1) % 3];
            const key = [Math.min(a, b), Math.max(a, b)].join(':');
            const count = edges.get(key) ?? [0, 0];
            count[a < b ? 0 : 1]++;
            assert.ok(count[0] <= 1 && count[1] <= 1, 'shared edges have opposite orientation and at most two incident faces');
            edges.set(key, count);
          }
        }
      }
    }
  });

  it('adapts actual A/B body, shorts and shirt geometry and demonstrates changed body dimensions', async () => {
    const [a, b] = catalog.fitModels;
    const [meshesA, meshesB] = await Promise.all([modelMeshes(a), modelMeshes(b)]);
    const geometryA = createPreviewGeometry(revision(), a, meshesA);
    const geometryB = createPreviewGeometry(revision(), b, meshesB);
    try {
      assert.equal(geometryA.body.getAttribute('position').count, 13380);
      assert.equal(geometryB.body.getAttribute('position').count, 13380);
      assert.equal(geometryA.bodyHash, meshesA.get(a.bodyMeshAssetId)?.descriptor.sha256);
      assert.notEqual(geometryA.bodyHash, geometryB.bodyHash);
      const boundsA = geometryA.body.boundingBox!;
      const boundsB = geometryB.body.boundingBox!;
      assert.ok(Math.abs((boundsB.max.x - boundsB.min.x) / (boundsA.max.x - boundsA.min.x) - 1.12) < 1e-5);
      assert.ok(Math.abs(geometryA.heightM - 1.8) < 1e-5);
      assert.ok(Math.abs(geometryB.heightM / geometryA.heightM - 0.95) < 1e-5);
      assert.ok(Math.abs(boundsA.min.z + boundsA.max.z) > 0.1, 'canonical model preserves the source front/back asymmetry');
      assert.notDeepEqual(Array.from(geometryA.garment.getAttribute('position').array), Array.from(geometryB.garment.getAttribute('position').array));
      assert.notDeepEqual(Array.from(geometryA.shorts.getAttribute('position').array), Array.from(geometryB.shorts.getAttribute('position').array));
      const normals = geometryA.body.getAttribute('normal') as BufferAttribute;
      for (let i = 0; i < normals.count; i += 137) {
        const length = Math.hypot(normals.getX(i), normals.getY(i), normals.getZ(i));
        assert.ok(Math.abs(length - 1) < 1e-4);
        const source = geometryA.body.getAttribute('position');
        const target = geometryB.body.getAttribute('position');
        const targetNormals = geometryB.body.getAttribute('normal');
        const transform = meshesB.get(b.bodyMeshAssetId)!.descriptor.sourceToCanonical.matrix;
        const x = source.getX(i), y = source.getY(i), z = source.getZ(i);
        assert.ok(Math.abs(target.getX(i) - (transform[0] * x + transform[4] * y + transform[8] * z + transform[12])) < 1e-6);
        assert.ok(Math.abs(target.getY(i) - (transform[1] * x + transform[5] * y + transform[9] * z + transform[13])) < 1e-6);
        assert.ok(Math.abs(target.getZ(i) - (transform[2] * x + transform[6] * y + transform[10] * z + transform[14])) < 1e-6);
        assert.ok(Math.abs((target.getZ(i) - transform[14]) / transform[10] - z) < 1e-6, 'asymmetric source Z round-trips through declared frame');
        const transformedNormal = [normals.getX(i) / transform[0], normals.getY(i) / transform[5], normals.getZ(i) / transform[10]];
        const normalLength = Math.hypot(...transformedNormal);
        assert.ok(Math.abs(targetNormals.getX(i) - transformedNormal[0] / normalLength) < 1e-6);
        assert.ok(Math.abs(targetNormals.getY(i) - transformedNormal[1] / normalLength) < 1e-6);
        assert.ok(Math.abs(targetNormals.getZ(i) - transformedNormal[2] / normalLength) < 1e-6);
      }
      assert.ok(geometryA.shorts.getAttribute('position').count > 0);
      assert.ok(geometryA.garment.getAttribute('position').count > 0);
    } finally {
      geometryA.body.dispose(); geometryA.shorts.dispose(); geometryA.garment.dispose();
      geometryB.body.dispose(); geometryB.shorts.dispose(); geometryB.garment.dispose();
    }
  });
});
