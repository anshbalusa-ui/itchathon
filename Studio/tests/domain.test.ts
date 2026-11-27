import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import type { Catalog, ProjectPackage } from '../src/domain/types';
import { applyDraft, createProject, currentRevision, draftOf, forkImported, isDirty } from '../src/domain/projects';
import { exportPackage, MAX_PACKAGE_BYTES, readPackage } from '../src/domain/packages';
import { validateCatalog, validatePackage, validateRenderInput } from '../src/domain/validation';

const assetsDirectory = new URL('../public/assets/', import.meta.url);
const contractExamplesDirectory = new URL('../../Shared/Contracts/examples/', import.meta.url);

async function canonicalCatalog(): Promise<Catalog> {
  return JSON.parse(await readFile(new URL('catalog.json', assetsDirectory), 'utf8')) as Catalog;
}

async function canonicalAssets(catalog: Catalog): Promise<{ id: string; data: string }[]> {
  return Promise.all(catalog.meshAssets.map(async (descriptor) => ({
    id: descriptor.id,
    data: await readFile(new URL(`${descriptor.id}.json`, assetsDirectory), 'utf8'),
  })));
}

async function libraryFixture() {
  const catalog = await canonicalCatalog();
  const assets = await canonicalAssets(catalog);
  return { catalog, assets, library: await validateCatalog(catalog, assets) };
}

function copied<T>(value: T): T {
  return structuredClone(value);
}

function packageWithFirstRevision(document: ProjectPackage, edit: (revision: ProjectPackage['revisions'][number]) => void): ProjectPackage {
  const result = copied(document);
  edit(result.revisions[0]!);
  return result;
}
async function contractExample<T>(name: string): Promise<T> {
  return JSON.parse(await readFile(new URL(name, contractExamplesDirectory), 'utf8')) as T;
}

test('canonical contract examples use the generated catalog and validate as a project', async () => {
  const { catalog, library } = await libraryFixture();
  const catalogExample = await contractExample<Catalog>('catalog.example.json');
  const descriptorExample = await contractExample<Catalog['meshAssets'][number]>('mesh-asset-descriptor.example.json');
  const fitModelExample = await contractExample<Catalog['fitModels'][number]>('fit-model-revision.example.json');
  const templateExample = await contractExample<Catalog['template']>('garment-template.example.json');
  const projectExample = await contractExample<ProjectPackage['project']>('garment-project.example.json');
  const revisionExample = await contractExample<ProjectPackage['revisions'][number]>('garment-revision.example.json');
  assert.deepEqual(catalogExample, catalog);
  assert.deepEqual(descriptorExample, catalog.meshAssets[0]);
  assert.deepEqual(fitModelExample, catalog.fitModels[0]);
  assert.deepEqual(templateExample, catalog.template);

  const document = createProject(library, 'Canonical example', 'Canonical example T-shirt');
  document.project = projectExample;
  document.revisions = [revisionExample];
  document.packagedAt = projectExample.updatedAt;
  await validatePackage(document, catalog);
});

test('maintained catalog admits real payloads and rejects altered hashes, units, and references', async () => {
  const { catalog, assets } = await libraryFixture();
  const library = await validateCatalog(catalog, assets);
  assert.equal(library.meshes.size, catalog.meshAssets.length);

  const badHash = assets.map((asset) => ({ ...asset }));
  badHash[0]!.data = ` ${badHash[0]!.data.slice(1)}`;
  await assert.rejects(validateCatalog(catalog, badHash), /SHA-256/iu);

  const wrongUnits = copied(catalog);
  Reflect.set(wrongUnits.meshAssets[0]!, 'units', 'cm');
  await assert.rejects(validateCatalog(wrongUnits, assets), /contract|maintained/iu);

  const project = createProject(library, 'Validation fixture', 'Classic shirt');
  const unknownModel = copied(project);
  unknownModel.project.selectedFitModelRevisionId = '00000000-0000-4000-8000-000000000000';
  await assert.rejects(validatePackage(unknownModel, catalog), /fit model/iu);
});

test('garment revisions are immutable while project and fitting-model changes remain separate', async () => {
  const { catalog, library } = await libraryFixture();
  const initial = createProject(library, 'Studio project', 'Classic shirt');
  const initialRevision = currentRevision(initial);
  const initialProjectRevision = initial.project.revisionId;

  const changedSelection = draftOf(initial);
  changedSelection.projectName = 'Renamed project';
  changedSelection.fitModelRevisionId = catalog.fitModels[1]!.id;
  changedSelection.previewView = '3d';
  assert.equal(isDirty(initial, changedSelection), true);
  const selected = applyDraft(initial, changedSelection);
  assert.notEqual(selected.project.revisionId, initialProjectRevision);
  assert.equal(selected.project.parentRevisionId, initialProjectRevision);
  assert.equal(selected.project.currentGarmentRevisionId, initialRevision.id);
  assert.equal(selected.revisions.length, 1);

  const garmentEdit = draftOf(selected);
  garmentEdit.garmentName = 'Weekend tee';
  garmentEdit.color = '#A14C82';
  const revised = applyDraft(selected, garmentEdit);
  assert.equal(revised.revisions.length, 2);
  assert.equal(revised.revisions[0]!.id, initialRevision.id);
  assert.equal(revised.revisions[1]!.parentRevisionId, initialRevision.id);
  assert.equal(revised.revisions[1]!.garmentId, initialRevision.garmentId);
  assert.notEqual(revised.revisions[1]!.id, initialRevision.id);
  await validatePackage(revised, catalog);

  const fork = forkImported(revised);
  assert.notEqual(fork.project.id, revised.project.id);
  assert.notEqual(fork.project.revisionId, revised.project.revisionId);
  assert.equal(fork.project.parentRevisionId, null);
  assert.deepEqual(fork.project.importedFrom, { projectId: revised.project.id, projectRevisionId: revised.project.revisionId });
  assert.deepEqual(fork.revisions, revised.revisions);
  await validatePackage(fork, catalog);
});

test('render validation resolves body, shorts, and the selected shirt from admitted catalog meshes', async () => {
  const { catalog, library } = await libraryFixture();
  const document = createProject(library, 'Render fixture', 'Classic shirt');
  const result = validateRenderInput(currentRevision(document), catalog.fitModels[0]!, library.meshes);
  assert.notEqual(result.body.descriptor.id, result.shorts.descriptor.id);
  assert.notEqual(result.body.descriptor.id, result.garment.descriptor.id);
  assert.notEqual(result.shorts.descriptor.id, result.garment.descriptor.id);

  const wrongRevision = copied(currentRevision(document));
  wrongRevision.previewMeshes = [];
  assert.throws(() => validateRenderInput(wrongRevision, catalog.fitModels[0]!, library.meshes), /contract|preview/iu);
});

test('package export/import roundtrip preserves supported state and exact garment history', async () => {
  const { catalog, library } = await libraryFixture();
  const initial = createProject(library, 'Roundtrip', 'Everyday tee');
  const draft = draftOf(initial);
  draft.color = '#4477AA';
  draft.garmentName = 'Everyday tee v2';
  draft.previewView = '2d';
  const document = applyDraft(initial, draft);
  const blob = await exportPackage(document, catalog);
  assert.equal(blob.type, 'application/json');
  const imported = await readPackage(new File([await blob.arrayBuffer()], 'roundtrip.onyou.json', { type: 'application/json' }), catalog);
  assert.deepEqual(imported, document);
  assert.deepEqual(imported.revisions, document.revisions);

  const unsafe = packageWithFirstRevision(document, (revision) => { revision.source.uri = 'javascript:alert(1)'; });
  await assert.rejects(validatePackage(unsafe, catalog), /maintained template/iu);
  const badVersion = copied(document);
  Reflect.set(badVersion, 'schemaVersion', 99);
  await assert.rejects(validatePackage(badVersion, catalog), /contract/iu);
  await assert.rejects(readPackage(new File([new Uint8Array(MAX_PACKAGE_BYTES + 1)], 'oversized.json'), catalog), /12 MiB/iu);
});

test('tampered mesh payloads and revision-resource overflow are rejected', async () => {
  const { catalog, assets } = await libraryFixture();
  const malformed = assets.map((asset) => ({ ...asset }));
  malformed[0]!.data = '{"format":"onyou-mesh-v1","positions":[1e999],"normals":[],"indices":[]}';
  await assert.rejects(validateCatalog(catalog, malformed), /byte length|SHA-256/iu);

  const { library } = await libraryFixture();
  const document = createProject(library, 'Limits', 'Classic shirt');
  const maxed = copied(document);
  for (let index = 1; index < 100; index += 1) {
    const previous = maxed.revisions[maxed.revisions.length - 1]!;
    const next = copied(previous);
    next.id = globalThis.crypto.randomUUID();
    next.parentRevisionId = previous.id;
    next.createdAt = new Date(Date.now() + index).toISOString();
    maxed.revisions.push(next);
  }
  maxed.project.currentGarmentRevisionId = maxed.revisions[99]!.id;
  const draft = draftOf(maxed);
  draft.color = '#010203';
  assert.throws(() => applyDraft(maxed, draft), /100 immutable garment revisions/iu);
});
