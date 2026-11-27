import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import type { Catalog, ParametricGarmentRevision } from '../src/domain/types';
import { createProject, currentRevision } from '../src/domain/projects';
import { validateCatalog } from '../src/domain/validation';
import { admitDerivedGarmentMesh, createGarmentGeometry } from '../src/rendering/preview';
import { generateGarmentMesh } from '../src/patterns/preview';
import { setMeasurement } from '../src/domain/development';

async function previewFixture() {
  const root = new URL('../public/assets/', import.meta.url);
  const catalog = JSON.parse(await readFile(new URL('catalog.json', root), 'utf8')) as Catalog;
  const assets = await Promise.all(catalog.meshAssets.map(async descriptor => ({ id: descriptor.id, data: await readFile(new URL(`${descriptor.id}.json`, root), 'utf8') })));
  const library = await validateCatalog(catalog, assets);
  const document = createProject(library, 'Parametric preview boundary', 'Independent garment', 'parametric');
  const revision = currentRevision(document);
  assert.equal(revision.schemaVersion, 2);
  return { catalog, library, revision: revision as ParametricGarmentRevision };
}

test('derived admission rejects invalid triangles, missing POMs and unreferenced echo vertices', async () => {
  const { revision } = await previewFixture();
  const size = revision.development.sizeSet.sizes[0];
  const pattern = revision.development.patterns[0];
  const original = generateGarmentMesh(size.specification, pattern);
  admitDerivedGarmentMesh(original, size.specification, pattern);

  const invalidIndex = structuredClone(original);
  invalidIndex.mesh.indices[0] = invalidIndex.mesh.positions.length / 3;
  assert.throws(() => admitDerivedGarmentMesh(invalidIndex, size.specification, pattern), /triangle index/);
  const repeatedFace = structuredClone(original);
  repeatedFace.mesh.indices.push(...repeatedFace.mesh.indices.slice(0, 3));
  assert.throws(() => admitDerivedGarmentMesh(repeatedFace, size.specification, pattern), /winding/);
  const missing = structuredClone(original);
  Reflect.deleteProperty(missing.measurementVertexIndices, 'bodyLength');
  assert.throws(() => admitDerivedGarmentMesh(missing, size.specification, pattern), /actual indexed/);
  const unused = structuredClone(original);
  const fakeIndex = unused.mesh.positions.length / 3;
  unused.mesh.positions.push(0, -size.specification.values.bodyLength, 0);
  unused.mesh.normals.push(0, 0, 1);
  unused.measurementVertexIndices.bodyLength[1] = fakeIndex;
  assert.throws(() => admitDerivedGarmentMesh(unused, size.specification, pattern), /actual indexed/);
});

test('the same garment size keeps identical local surface coordinates on both fitting models', async () => {
  const { catalog, library, revision } = await previewFixture();
  const sizeId = revision.development.sizeSet.baseSizeId;
  const a = createGarmentGeometry(revision, catalog.fitModels[0], library.meshes, sizeId);
  const b = createGarmentGeometry(revision, catalog.fitModels[1], library.meshes, sizeId);
  try {
    assert.deepEqual(a.geometry.getAttribute('position').array, b.geometry.getAttribute('position').array);
    assert.deepEqual(a.geometry.getAttribute('normal').array, b.geometry.getAttribute('normal').array);
    assert.deepEqual(a.geometry.index!.array, b.geometry.index!.array);
    a.geometry.computeBoundingBox(); b.geometry.computeBoundingBox();
    assert.deepEqual(a.geometry.boundingBox, b.geometry.boundingBox);
    assert.notEqual(a.offset[1], b.offset[1], 'only declared rigid shoulder placement follows model height');
    assert.equal(a.identity, b.identity);
  } finally { a.geometry.dispose(); b.geometry.dispose(); }
});

test('editing body length changes the indexed garment surface without mutating admitted model assets', async () => {
  const { catalog, library, revision } = await previewFixture();
  const body = library.meshes.get(catalog.fitModels[0].bodyMeshAssetId)!;
  const beforePositions = [...body.mesh.positions];
  const beforeNormals = [...body.mesh.normals];
  const sizeId = revision.development.sizeSet.baseSizeId;
  const oldLength = revision.development.sizeSet.sizes[0].specification.values.bodyLength;
  const edited = { ...revision, development: setMeasurement(revision.development, sizeId, 'bodyLength', oldLength + 0.04) };
  const before = createGarmentGeometry(revision, catalog.fitModels[0], library.meshes, sizeId);
  const after = createGarmentGeometry(edited, catalog.fitModels[0], library.meshes, sizeId);
  try {
    before.geometry.computeBoundingBox(); after.geometry.computeBoundingBox();
    const first = before.geometry.boundingBox!, next = after.geometry.boundingBox!;
    assert.ok(Math.abs((next.max.y - next.min.y) - (first.max.y - first.min.y) - 0.04) < 1e-5);
    assert.deepEqual(body.mesh.positions, beforePositions);
    assert.deepEqual(body.mesh.normals, beforeNormals);
    assert.equal(edited.development.sizeSet.sizes[0].specification.values.chestWidth, revision.development.sizeSet.sizes[0].specification.values.chestWidth);
  } finally { before.geometry.dispose(); after.geometry.dispose(); }
});
