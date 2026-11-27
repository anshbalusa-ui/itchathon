import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import type { Catalog, ProjectPackage } from '../src/domain/types';
import { applyDraft, createProject, currentRevision, draftOf, forkImported, isDirty, restoreRevision, upgradeProject } from '../src/domain/projects';
import { exportPackage, MAX_PACKAGE_BYTES, readPackage } from '../src/domain/packages';
import { validateCatalog, validatePackage, validateRenderInput } from '../src/domain/validation';
import { addSize, setMeasurement, validateDevelopment } from '../src/domain/development';
import type { DevelopmentState, GradeRule, GarmentSpecification, PatternDefinition, SizeSet } from '../src/domain/development-types';
import { generatePattern, POMS } from '../src/patterns/generator';
import { specificationCsv, specificationJson, patternSvg } from '../src/domain/specification-exports';
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

test('canonical generated development examples validate as a complete graded pattern set', async () => {
  const specification = await contractExample<GarmentSpecification>('garment-specification.example.json');
  const gradeRule = await contractExample<GradeRule>('grade-rule.example.json');
  const sizeSet = await contractExample<SizeSet>('size-set.example.json');
  const pattern = await contractExample<PatternDefinition>('pattern-definition.example.json');
  assert.deepEqual(specification, sizeSet.sizes[0]!.specification);
  assert.deepEqual(gradeRule, sizeSet.gradeRules[0]);
  const gradedSize = sizeSet.sizes.find((size) => size.id === gradeRule.toSizeId)!;
  const gradedPattern = generatePattern(gradedSize.specification, {
    id: crypto.randomUUID(),
    revisionId: sizeSet.revisionId,
  });
  validateDevelopment({
    schemaVersion: 1,
    generatorVersion: pattern.generatorVersion,
    topologyVersion: pattern.topologyVersion,
    sizeSet,
    patterns: [pattern, gradedPattern],
  }, sizeSet.garmentRevisionId);
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
  const revision = currentRevision(document);
  if (revision.schemaVersion !== 1) throw new Error('Legacy fixture unexpectedly became parametric.');
  const result = validateRenderInput(revision, catalog.fitModels[0]!, library.meshes);
  assert.notEqual(result.body.descriptor.id, result.shorts.descriptor.id);
  assert.notEqual(result.body.descriptor.id, result.garment.descriptor.id);
  assert.notEqual(result.shorts.descriptor.id, result.garment.descriptor.id);

  const wrongRevision = copied(currentRevision(document));
  if (wrongRevision.schemaVersion !== 1) throw new Error('Legacy fixture unexpectedly became parametric.');
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
test('explicit V1 upgrade, append-only restore, v2 persistence, and real specification exports preserve state', async () => {
  const { catalog, library } = await libraryFixture();
  const legacy = createProject(library, 'History', 'Classic tee');
  const legacyEdit = draftOf(legacy);
  legacyEdit.color = '#224466';
  const withHistory = applyDraft(legacy, legacyEdit);
  const bytePreserved = copied(withHistory.revisions);
  const legacyComparison = draftOf(withHistory);
  legacyComparison.comparison = { revisionId: withHistory.revisions[0]!.id, sizeId: null };
  assert.equal(isDirty(withHistory, legacyComparison), false);
  const upgraded = upgradeProject(withHistory);
  assert.equal(upgraded.schemaVersion, 2);
  assert.deepEqual(upgraded.revisions.slice(0, 2), bytePreserved);
  const parametric = currentRevision(upgraded);
  assert.equal(parametric.schemaVersion, 2);
  if (parametric.schemaVersion !== 2) throw new Error('Upgrade did not create a parametric revision.');
  for (const size of parametric.development.sizeSet.sizes) {
    assert.ok(Object.values(size.specification.sources).every((source) => source === 'authored-default'));
  }
  await validatePackage(upgraded, catalog);
  const restoredParametric = restoreRevision(upgraded, parametric.id);
  const restoredParametricRevision = currentRevision(restoredParametric);
  if (restoredParametricRevision.schemaVersion !== 2) throw new Error('Parametric restore did not preserve development state.');
  assert.equal(restoredParametricRevision.restoredFromRevisionId, parametric.id);
  assert.notEqual(restoredParametricRevision.id, parametric.id);
  await validatePackage(restoredParametric, catalog);

  const restored = restoreRevision(upgraded, withHistory.revisions[0]!.id);
  assert.equal(restored.revisions.length, upgraded.revisions.length + 1);
  assert.deepEqual(restored.revisions.slice(0, upgraded.revisions.length), upgraded.revisions);
  const restoredCurrent = currentRevision(restored);
  assert.equal(restoredCurrent.schemaVersion, 1);
  assert.equal(restored.project.selectedSizeId, null);
  await validatePackage(restored, catalog);
  const upgradedAgain = upgradeProject(restored);
  assert.equal(currentRevision(upgradedAgain).schemaVersion, 2);
  assert.deepEqual(upgradedAgain.revisions.slice(0, restored.revisions.length), restored.revisions);
  await validatePackage(upgradedAgain, catalog);

  const parametricProject = createProject(library, 'Export', '=Brand & Tee', 'parametric');
  const revision = currentRevision(parametricProject);
  if (revision.schemaVersion !== 2) throw new Error('Parametric template did not create a v2 revision.');
  const metadataDraft = draftOf(parametricProject);
  metadataDraft.displayUnit = 'in';
  metadataDraft.patternView = 'piece-front';
  const metadataOnly = applyDraft(parametricProject, metadataDraft);
  assert.equal(metadataOnly.revisions.length, 1);
  assert.equal(metadataOnly.project.currentGarmentRevisionId, revision.id);
  assert.equal(metadataOnly.project.displayUnit, 'in');
  const comparisonDraft = draftOf(parametricProject);
  const expandedDevelopment = addSize(revision.development, 'Large');
  comparisonDraft.development = expandedDevelopment;
  const largeId = expandedDevelopment.sizeSet.sizes[1]!.id;
  comparisonDraft.comparison = { revisionId: revision.id, sizeId: largeId };
  const comparedNewSize = applyDraft(parametricProject, comparisonDraft);
  assert.equal(comparedNewSize.revisions.length, 2);
  assert.equal(comparedNewSize.project.comparison?.revisionId, comparedNewSize.project.currentGarmentRevisionId);
  assert.equal(comparedNewSize.project.comparison?.sizeId, largeId);
  await validatePackage(comparedNewSize, catalog);
  const selectedDraft = draftOf(comparedNewSize);
  selectedDraft.selectedSizeId = largeId;
  selectedDraft.fitModelRevisionId = catalog.fitModels[1]!.id;
  const selectedNewSize = applyDraft(comparedNewSize, selectedDraft);
  const restoredWithoutSize = restoreRevision(selectedNewSize, revision.id);
  assert.equal(restoredWithoutSize.project.selectedSizeId, revision.development.sizeSet.baseSizeId);
  assert.equal(restoredWithoutSize.project.comparison, null);
  assert.equal(restoredWithoutSize.project.selectedFitModelRevisionId, selectedDraft.fitModelRevisionId);
  assert.deepEqual(restoredWithoutSize.revisions.slice(0, selectedNewSize.revisions.length), selectedNewSize.revisions);
  await validatePackage(restoredWithoutSize, catalog);
  const csv = specificationCsv(revision, 'in');
  assert.match(csv, /"'=Brand & Tee"/u);
  assert.match(csv, new RegExp(revision.id, 'u'));
  assert.match(csv, new RegExp(revision.garmentId, 'u'));
  assert.match(csv, /"in"/u);
  const json = JSON.parse(specificationJson(revision)) as { garment: { revisionId: string }; development: { patterns: unknown[] } };
  assert.equal(json.garment.revisionId, revision.id);
  assert.equal(json.development.patterns.length, revision.development.sizeSet.sizes.length);
  const svg = patternSvg(revision, revision.development.sizeSet.baseSizeId);
  assert.match(svg, /width="[\d.]+mm"/u);
  const svgDimensions = svg.match(/width="([\d.]+)mm" height="([\d.]+)mm" viewBox="0 0 ([\d.]+) ([\d.]+)"/u);
  if (!svgDimensions) throw new Error('SVG physical dimensions are missing.');
  assert.equal(svgDimensions[1], svgDimensions[3]);
  assert.equal(svgDimensions[2], svgDimensions[4]);
  assert.match(svg, /&amp;/u);
  assert.equal(svg.includes('<script') || svg.includes('href=') || svg.includes('<image'), false);

  const blob = await exportPackage(parametricProject, catalog);
  const imported = await readPackage(new File([await blob.arrayBuffer()], 'v2.onyou.json'), catalog);
  assert.deepEqual(imported, parametricProject);
  const tampered = copied(parametricProject);
  const target = currentRevision(tampered);
  if (target.schemaVersion !== 2) throw new Error('Parametric fixture was narrowed incorrectly.');
  target.development.patterns[0]!.pieces[0]!.points[0]!.x += 0.001;
  const rejectedState = copied(tampered);
  await assert.rejects(validatePackage(tampered, catalog), TypeError);
  assert.deepEqual(tampered, rejectedState);
  const invalidChart = copied(parametricProject);
  const invalidRevision = currentRevision(invalidChart);
  if (invalidRevision.schemaVersion !== 2) throw new Error('Parametric fixture was narrowed incorrectly.');
  invalidRevision.development.sizeSet.sizes[0]!.specification.values.bodyLength = 1.5;
  await assert.rejects(validatePackage(invalidChart, catalog), /bodyLength must be between/iu);
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

test('SVG seam coordinates preserve every supported garment POM at physical millimeter scale', async () => {
  const { library } = await libraryFixture();
  const document = createProject(library, 'Vector scale', 'Measured tee', 'parametric');
  const draft = draftOf(document);
  const values = { bodyLength: 0.74, chestWidth: 0.60, hemWidth: 0.55, shoulderWidth: 0.46, sleeveLength: 0.24, sleeveOpening: 0.20, neckWidth: 0.19, neckDepth: 0.085 };
  const sizeId = draft.development!.sizeSet.baseSizeId;
  for (const pom of POMS) draft.development = setMeasurement(draft.development!, sizeId, pom.id, values[pom.id]);
  const revision = currentRevision(applyDraft(document, draft));
  if (revision.schemaVersion !== 2) throw new Error('Expected a parametric vector export.');
  const pattern = revision.development.patterns[0]!;
  const svg = patternSvg(revision, sizeId);
  const coordinates = new Map<string, [number, number]>();
  for (const piece of pattern.pieces) {
    const path = svg.match(new RegExp(String.raw`<g id="${piece.id}"[^>]*>[\s\S]*?<path class="seam-line" d="([^"]+)"`, 'u'))?.[1];
    assert.ok(path, `Missing exported ${piece.id} seam`);
    const endpoints = [...path.matchAll(/([MLC])\s+([^MLCZ]+)/gu)].map(command => {
      const numbers = command[2]!.trim().split(/\s+/u).map(Number);
      return [numbers[numbers.length - 2]! / 1000, numbers[numbers.length - 1]! / 1000] as [number, number];
    });
    assert.equal(endpoints.length, piece.edges.length + 1);
    coordinates.set(`${piece.id}:${piece.edges[0]!.from}`, endpoints[0]!);
    piece.edges.forEach((edge, index) => coordinates.set(`${piece.id}:${edge.to}`, endpoints[index + 1]!));
  }
  for (const pom of POMS) {
    const a = coordinates.get(`${pom.endpoints.pieceId}:${pom.endpoints.startPointId}`)!;
    const b = coordinates.get(`${pom.endpoints.pieceId}:${pom.endpoints.endPointId}`)!;
    const actual = pom.method === 'horizontal-projection' ? Math.abs(a[0] - b[0])
      : pom.method === 'vertical-projection' ? Math.abs(a[1] - b[1])
        : Math.hypot(a[0] - b[0], a[1] - b[1]) / (pom.method === 'half-path-length' ? 2 : 1);
    assert.ok(Math.abs(actual - values[pom.id]) < 1e-6, `${pom.id}: exported ${actual}m, expected ${values[pom.id]}m`);
  }
});
