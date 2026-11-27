import { PROJECT_LIMITATIONS } from './projects';
import Ajv, { type ValidateFunction } from 'ajv';
import addFormats from 'ajv-formats';
import catalogSchema from '../../../Shared/Contracts/catalog.schema.json';
import fitModelSchema from '../../../Shared/Contracts/fit-model-revision.schema.json';
import garmentRevisionSchema from '../../../Shared/Contracts/garment-revision.schema.json';
import garmentProjectSchema from '../../../Shared/Contracts/garment-project.schema.json';
import garmentTemplateSchema from '../../../Shared/Contracts/garment-template.schema.json';
import meshDescriptorSchema from '../../../Shared/Contracts/mesh-asset-descriptor.schema.json';
import packageSchema from '../../../Shared/Contracts/project-package.schema.json';
import maintainedCatalog from '../../../Shared/Contracts/examples/catalog.example.json';
import garmentRevisionV2Schema from '../../../Shared/Contracts/garment-revision-v2.schema.json';
import garmentProjectV2Schema from '../../../Shared/Contracts/garment-project-v2.schema.json';
import projectPackageV1Schema from '../../../Shared/Contracts/project-package-v1.schema.json';
import projectPackageV2Schema from '../../../Shared/Contracts/project-package-v2.schema.json';
import developmentStateSchema from '../../../Shared/Contracts/development-state.schema.json';
import sizeSetSchema from '../../../Shared/Contracts/size-set.schema.json';
import garmentSpecificationSchema from '../../../Shared/Contracts/garment-specification.schema.json';
import patternDefinitionSchema from '../../../Shared/Contracts/pattern-definition.schema.json';
import gradeRuleSchema from '../../../Shared/Contracts/grade-rule.schema.json';
import type {
  AdmittedMesh,
  AssetPayload,
  Catalog,
  FitModelRevision,
  GarmentRevision,
  Library,
  MeshAssetDescriptor,
  MeshData,
  ProjectPackage,
  ProjectSummary,
  GarmentProject,
} from './types';
import type { LegacyGarmentRevision, ParametricGarmentRevision } from './types';
import { validateDevelopment } from './development';
import { PARAMETRIC_TEMPLATE_ID, PARAMETRIC_TEMPLATE_SOURCE } from '../patterns/generator';

export const MAX_PACKAGE_BYTES = 12 * 1024 * 1024;
const MAX_ASSET_BYTES = 3 * 1024 * 1024;
const encoder = new TextEncoder();

const ajv = new Ajv({ allErrors: true, strict: true });
addFormats(ajv);
for (const schema of [meshDescriptorSchema, fitModelSchema, garmentTemplateSchema, garmentRevisionSchema,
  garmentRevisionV2Schema, garmentProjectSchema, garmentProjectV2Schema, developmentStateSchema,
  sizeSetSchema, garmentSpecificationSchema, patternDefinitionSchema, gradeRuleSchema,
  projectPackageV1Schema, projectPackageV2Schema]) ajv.addSchema(schema);
const validateCatalogSchema = ajv.compile(catalogSchema);
const validatePackageSchema = ajv.compile(packageSchema);
const validateProjectSummaryRecordSchema = ajv.compile({
  type: 'object',
  additionalProperties: false,
  required: ['project', 'revision', 'fitModel'],
  properties: {
    project: { anyOf: [
      { $ref: 'https://schemas.onyou.studio/garment-project.schema.json' },
      { $ref: 'https://schemas.onyou.studio/garment-project-v2.schema.json' },
    ] },
    revision: { anyOf: [
      { $ref: 'https://schemas.onyou.studio/garment-revision.schema.json' },
      { $ref: 'https://schemas.onyou.studio/garment-revision-v2.schema.json' },
    ] },
    fitModel: { $ref: 'https://schemas.onyou.studio/fit-model-revision.schema.json' },
  },
});
const validateMeshDescriptorSchema = ajv.getSchema('https://schemas.onyou.studio/mesh-asset-descriptor.schema.json')!;
const validateFitModelSchema = ajv.getSchema('https://schemas.onyou.studio/fit-model-revision.schema.json')!;
const validateTemplateSchema = ajv.getSchema('https://schemas.onyou.studio/garment-template.schema.json')!;
const validateGarmentRevisionSchema = ajv.getSchema('https://schemas.onyou.studio/garment-revision.schema.json')!;
const validateGarmentRevisionV2Schema = ajv.getSchema('https://schemas.onyou.studio/garment-revision-v2.schema.json')!;

function stableJson(value: unknown): string {
  return JSON.stringify(value, (_key, item: unknown) => {
    if (item === null || Array.isArray(item) || typeof item !== 'object') return item;
    return Object.fromEntries(Object.entries(item).sort(([left], [right]) => left.localeCompare(right)));
  });
}

function schemaError(label: string, validator: ValidateFunction): never {
  const details = (validator.errors ?? [])
    .map((error) => `${error.instancePath || '/'} ${error.message ?? 'is invalid'}`)
    .join('; ');
  throw new TypeError(`${label} does not match its contract${details ? `: ${details}` : '.'}`);
}

function assertValid(label: string, validator: ValidateFunction, value: unknown): void {
  if (!validator(value)) schemaError(label, validator);
}

function assertPinnedCatalog(catalog: Catalog): void {
  if (stableJson(catalog) !== stableJson(maintainedCatalog)) {
    throw new TypeError('Catalog is not the exact maintained, licensed Studio catalog.');
  }
}

async function sha256(text: string): Promise<string> {
  const digest = await globalThis.crypto.subtle.digest('SHA-256', encoder.encode(text));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

function assertSourceAndTransform(descriptor: MeshAssetDescriptor): void {
  if (descriptor.source.license !== 'CC0-1.0' || descriptor.source.uri.length === 0 || descriptor.source.notice.length === 0) {
    throw new TypeError(`Mesh ${descriptor.id} has invalid source-license metadata.`);
  }
  const matrix = descriptor.sourceToCanonical.matrix;
  if (!matrix.every(Number.isFinite) || matrix.some((value) => Math.abs(value) > 1_000_000)) {
    throw new TypeError(`Mesh ${descriptor.id} has a non-finite or unsafe coordinate transform.`);
  }
  if (Math.abs(matrix[3]!) > 1e-9 || Math.abs(matrix[7]!) > 1e-9 || Math.abs(matrix[11]!) > 1e-9 || Math.abs(matrix[15]! - 1) > 1e-9) {
    throw new TypeError(`Mesh ${descriptor.id} transform is not affine column-major.`);
  }
  const determinant = matrix[0]! * (matrix[5]! * matrix[10]! - matrix[9]! * matrix[6]!)
    - matrix[4]! * (matrix[1]! * matrix[10]! - matrix[9]! * matrix[2]!)
    + matrix[8]! * (matrix[1]! * matrix[6]! - matrix[5]! * matrix[2]!);
  if (!(determinant > 1e-9)) throw new TypeError(`Mesh ${descriptor.id} transform changes handedness or is singular.`);
}

function assertMeshShape(mesh: unknown, descriptor: MeshAssetDescriptor): asserts mesh is MeshData {
  if (!mesh || typeof mesh !== 'object' || Array.isArray(mesh)) throw new TypeError(`Mesh ${descriptor.id} JSON must be an object.`);
  const record = mesh as Record<string, unknown>;
  if (Object.keys(record).length !== 4 || !['format', 'positions', 'normals', 'indices'].every((key) => Object.hasOwn(record, key))) {
    throw new TypeError(`Mesh ${descriptor.id} contains missing or unsupported properties.`);
  }
  if (record.format !== 'onyou-mesh-v1' || !Array.isArray(record.positions) || !Array.isArray(record.normals) || !Array.isArray(record.indices)) {
    throw new TypeError(`Mesh ${descriptor.id} has an unsupported mesh representation.`);
  }
  const positions = record.positions;
  const normals = record.normals;
  const indices = record.indices;
  if (positions.length !== descriptor.vertexCount * 3 || normals.length !== positions.length || indices.length !== descriptor.indexCount) {
    throw new TypeError(`Mesh ${descriptor.id} counts do not match its descriptor.`);
  }
  for (let axis = 0; axis < 3; axis += 1) {
    let minimum = Infinity;
    let maximum = -Infinity;
    for (let index = axis; index < positions.length; index += 3) {
      const coordinate = positions[index];
      if (typeof coordinate !== 'number' || !Number.isFinite(coordinate) || Math.abs(coordinate) > 100) {
        throw new TypeError(`Mesh ${descriptor.id} has a non-finite or unsafe coordinate.`);
      }
      minimum = Math.min(minimum, coordinate);
      maximum = Math.max(maximum, coordinate);
    }
    if (maximum - minimum < 1e-5
      || Math.abs(minimum - descriptor.bounds.minimum[axis]!) > 1e-5
      || Math.abs(maximum - descriptor.bounds.maximum[axis]!) > 1e-5) {
      throw new TypeError(`Mesh ${descriptor.id} coordinates do not match finite meter bounds.`);
    }
  }
  for (let index = 0; index < normals.length; index += 3) {
    const x = normals[index];
    const y = normals[index + 1];
    const z = normals[index + 2];
    if (typeof x !== 'number' || typeof y !== 'number' || typeof z !== 'number' || !Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) {
      throw new TypeError(`Mesh ${descriptor.id} contains a non-finite normal.`);
    }
    const length = Math.hypot(x, y, z);
    if (Math.abs(length - 1) > 0.02) throw new TypeError(`Mesh ${descriptor.id} contains a normal that is not unit length.`);
  }
  for (const index of indices) {
    if (!Number.isInteger(index) || index < 0 || index >= descriptor.vertexCount) {
      throw new TypeError(`Mesh ${descriptor.id} contains an out-of-range triangle index.`);
    }
  }
  if (indices.length % 3 !== 0) throw new TypeError(`Mesh ${descriptor.id} index count is not triangular.`);

  const edgeOrientations = new Map<number, number>();
  for (let offset = 0; offset < indices.length; offset += 3) {
    const ia = indices[offset]! * 3;
    const ib = indices[offset + 1]! * 3;
    const ic = indices[offset + 2]! * 3;
    const abx = positions[ib]! - positions[ia]!;
    const aby = positions[ib + 1]! - positions[ia + 1]!;
    const abz = positions[ib + 2]! - positions[ia + 2]!;
    const acx = positions[ic]! - positions[ia]!;
    const acy = positions[ic + 1]! - positions[ia + 1]!;
    const acz = positions[ic + 2]! - positions[ia + 2]!;
    const nx = aby * acz - abz * acy;
    const ny = abz * acx - abx * acz;
    const nz = abx * acy - aby * acx;
    const area2 = Math.hypot(nx, ny, nz);
    if (!(area2 > 1e-12)) throw new TypeError(`Mesh ${descriptor.id} contains a degenerate triangle.`);
    // Winding is topological. Smooth shading normals can cross a face hemisphere at tight folds.
    for (let edge = 0; edge < 3; edge += 1) {
      const a = indices[offset + edge]!, b = indices[offset + (edge + 1) % 3]!;
      const key = Math.min(a, b) * descriptor.vertexCount + Math.max(a, b);
      const orientation = a < b ? 1 : 2;
      const previous = edgeOrientations.get(key) ?? 0;
      if (previous & orientation) throw new TypeError(`Mesh ${descriptor.id} has inconsistent or nonmanifold triangle winding.`);
      edgeOrientations.set(key, previous | orientation);
    }
  }
}

async function admitAssets(catalog: Catalog, assets: AssetPayload[]): Promise<Map<string, AdmittedMesh>> {
  if (!Array.isArray(assets) || assets.length !== catalog.meshAssets.length) {
    throw new TypeError('Package must contain exactly the maintained catalog mesh payloads.');
  }
  const descriptors = new Map(catalog.meshAssets.map((descriptor) => [descriptor.id, descriptor]));
  const payloads = new Map<string, AssetPayload>();
  for (const asset of assets) {
    if (!asset || typeof asset.id !== 'string' || typeof asset.data !== 'string' || !descriptors.has(asset.id)) {
      throw new TypeError('Package contains an unknown or malformed mesh payload.');
    }
    if (payloads.has(asset.id)) throw new TypeError(`Package contains duplicate mesh payload ${asset.id}.`);
    payloads.set(asset.id, asset);
  }

  const admitted = new Map<string, AdmittedMesh>();
  for (const descriptor of catalog.meshAssets) {
    assertValid('Mesh asset descriptor', validateMeshDescriptorSchema, descriptor);
    assertSourceAndTransform(descriptor);
    const payload = payloads.get(descriptor.id);
    if (!payload) throw new TypeError(`Package is missing mesh payload ${descriptor.id}.`);
    const encoded = encoder.encode(payload.data);
    if (encoded.byteLength > MAX_ASSET_BYTES || encoded.byteLength !== descriptor.byteLength) {
      throw new TypeError(`Mesh ${descriptor.id} byte length is invalid or exceeds 3 MiB.`);
    }
    if (await sha256(payload.data) !== descriptor.sha256) throw new TypeError(`Mesh ${descriptor.id} SHA-256 does not match its descriptor.`);
    let mesh: unknown;
    try {
      mesh = JSON.parse(payload.data) as unknown;
    } catch {
      throw new TypeError(`Mesh ${descriptor.id} is not valid JSON.`);
    }
    assertMeshShape(mesh, descriptor);
    const topology = new Uint8Array(mesh.indices.length * 4);
    const view = new DataView(topology.buffer);
    for (let index = 0; index < mesh.indices.length; index += 1) view.setUint32(index * 4, mesh.indices[index]!, true);
    const topologyHash = Array.from(new Uint8Array(await globalThis.crypto.subtle.digest('SHA-256', topology)), (byte) => byte.toString(16).padStart(2, '0')).join('');
    if (topologyHash !== descriptor.topologySha256) throw new TypeError(`Mesh ${descriptor.id} topology hash does not match its descriptor.`);
    admitted.set(descriptor.id, { descriptor, mesh });
  }
  return admitted;
}

function assertProjectSize(document: ProjectPackage): void {
  const envelope = JSON.stringify({ ...document, assets: document.assets.map(({ id }) => ({ id })) });
  const envelopeBytes = encoder.encode(envelope).byteLength;
  let assetBytes = 0;
  for (const asset of document.assets) assetBytes += encoder.encode(asset.data).byteLength;
  if (envelopeBytes + assetBytes + document.assets.length * 16 > MAX_PACKAGE_BYTES) {
    throw new RangeError('Project package exceeds the 12 MiB limit.');
  }
}

function assertPackageReferences(document: ProjectPackage, catalog: Catalog): void {
  const project = document.project;
  if (project.name.trim() !== project.name || /[\u0000-\u001f\u007f]/u.test(project.name)) throw new TypeError('Project name is not safe printable text.');
  if (project.importedFrom && project.importedFrom.projectId === project.id) throw new TypeError('An imported project cannot refer to itself as its source.');
  if (project.revisionId === project.parentRevisionId) throw new TypeError('Project revision cannot parent itself.');
  if (Date.parse(project.updatedAt) < Date.parse(project.createdAt) || Date.parse(document.packagedAt) < Date.parse(project.updatedAt)) {
    throw new TypeError('Project timestamps are inconsistent with its package time.');
  }
  if (stableJson(document.template) !== stableJson(catalog.template)
    || stableJson(document.fitModels) !== stableJson(catalog.fitModels)
    || stableJson(document.meshAssets) !== stableJson(catalog.meshAssets)) {
    throw new TypeError('Package catalog references do not exactly match the maintained catalog.');
  }
  if (stableJson(document.limitations) !== stableJson(PROJECT_LIMITATIONS)) {
    throw new TypeError('Project limitations must preserve the maintained illustrative-only notices.');
  }
  if (document.revisions.length > 100) throw new RangeError('Project exceeds the 100 garment revision limit.');
  const byId = new Map<string, GarmentRevision>();
  const children = new Map<string, number>();
  let garmentId: string | undefined;
  if (document.schemaVersion !== project.schemaVersion) throw new TypeError('Package and project schema versions must match.');
  for (const revision of document.revisions) {
    if (revision.schemaVersion === 1) assertValid('Garment revision', validateGarmentRevisionSchema, revision);
    else {
      assertValid('Parametric garment revision', validateGarmentRevisionV2Schema, revision);
      validateDevelopment(revision.development, revision.id);
      if (revision.templateId !== PARAMETRIC_TEMPLATE_ID || stableJson(revision.source) !== stableJson(PARAMETRIC_TEMPLATE_SOURCE)) {
        throw new TypeError(`Parametric garment revision ${revision.id} does not reference the maintained authored template.`);
      }
    }
    if (byId.has(revision.id)) throw new TypeError(`Duplicate garment revision ${revision.id}.`);
    if (garmentId !== undefined && revision.garmentId !== garmentId) throw new TypeError('A project package cannot mix garment revision lineages.');
    if (revision.name.trim() !== revision.name || /[\u0000-\u001f\u007f]/u.test(revision.name)) {
      throw new TypeError(`Garment revision ${revision.id} has an unsafe name.`);
    }
    garmentId = revision.garmentId;
    if (revision.schemaVersion === 1 && (revision.templateId !== catalog.template.id || revision.templateVersion !== catalog.template.version
      || revision.geometryAdapter !== catalog.template.geometryAdapter
      || stableJson(revision.drawing) !== stableJson(catalog.template.drawing)
      || stableJson(revision.previewMeshes) !== stableJson(catalog.template.previewMeshes)
      || stableJson(revision.source) !== stableJson(catalog.template.source))) {
      throw new TypeError(`Garment revision ${revision.id} does not reference the maintained template.`);
    }
    byId.set(revision.id, revision);
  }
  for (let index = 0; index < document.revisions.length; index += 1) {
    const revision = document.revisions[index]!;
    const parent = index === 0 ? undefined : document.revisions[index - 1]!;
    if ((parent === undefined && revision.parentRevisionId !== null)
      || (parent !== undefined && revision.parentRevisionId !== parent.id)) {
      throw new TypeError('Garment revisions must be stored in their exact root-to-current lineage order.');
    }
    if (parent && Date.parse(revision.createdAt) < Date.parse(parent.createdAt)) {
      throw new TypeError('A garment revision predates its parent revision.');
    }
    if (revision.schemaVersion === 2 && revision.restoredFromRevisionId) {
      const sourceIndex = document.revisions.findIndex((candidate) => candidate.id === revision.restoredFromRevisionId);
      if (sourceIndex < 0 || sourceIndex >= index || revision.restoredFromRevisionId === revision.id) {
        throw new TypeError(`Restored revision ${revision.id} must reference an earlier immutable garment revision.`);
      }
    }
  }
  let roots = 0;
  for (const revision of document.revisions) {
    if (revision.parentRevisionId === null) {
      roots += 1;
      continue;
    }
    if (revision.parentRevisionId === revision.id || !byId.has(revision.parentRevisionId)) {
      throw new TypeError(`Garment revision ${revision.id} has an invalid parent reference.`);
    }
    const count = (children.get(revision.parentRevisionId) ?? 0) + 1;
    if (count > 1) throw new TypeError('Garment revision history cannot branch.');
    children.set(revision.parentRevisionId, count);
  }
  if (roots !== 1) throw new TypeError('Garment revision history must have exactly one root.');
  const current = byId.get(project.currentGarmentRevisionId);
  if (!current || current.garmentId !== garmentId || children.has(current.id)
    || current.id !== document.revisions[document.revisions.length - 1]!.id) {
    throw new TypeError('Project must select the newest leaf in its garment revision history.');
  }
  if (Date.parse(project.updatedAt) < Date.parse(current.createdAt)) {
    throw new TypeError('Project update time precedes its current garment revision.');
  }
  if (document.schemaVersion === 2) {
    if (current.schemaVersion === 2) {
      if (!project.selectedSizeId || !current.development.sizeSet.sizes.some((size) => size.id === project.selectedSizeId)) {
        throw new TypeError('A v2 project must select a size in the current development chart.');
      }
    } else if (project.selectedSizeId !== null) throw new TypeError('A legacy current revision cannot select a parametric size.');
    if (project.comparison && !byId.has(project.comparison.revisionId)) throw new TypeError('Comparison references a missing garment revision.');
    const compared = project.comparison ? byId.get(project.comparison.revisionId) : undefined;
    if (project.comparison?.sizeId && (compared?.schemaVersion !== 2
      || !compared.development.sizeSet.sizes.some((size) => size.id === project.comparison!.sizeId))) {
      throw new TypeError('Comparison selects a size outside its garment revision.');
    }
  }
  const reached = new Set<string>();
  let cursor: GarmentRevision | undefined = current;
  while (cursor) {
    if (reached.has(cursor.id)) throw new TypeError('Garment revision history contains a cycle.');
    reached.add(cursor.id);
    cursor = cursor.parentRevisionId === null ? undefined : byId.get(cursor.parentRevisionId);
  }
  if (reached.size !== document.revisions.length) throw new TypeError('Garment revision history contains unreachable revisions.');
  if (!catalog.fitModels.some((model) => model.id === project.selectedFitModelRevisionId)) {
    throw new TypeError('Project selects a fit model outside the maintained catalog.');
  }
  for (const model of catalog.fitModels) {
    if (!document.meshAssets.some((asset) => asset.id === model.bodyMeshAssetId)
      || !document.meshAssets.some((asset) => asset.id === model.baseGarmentMeshAssetId)) {
      throw new TypeError(`Fit model ${model.id} refers to an unknown mesh asset.`);
    }
  }
  for (const preview of catalog.template.previewMeshes) {
    if (!catalog.fitModels.some((model) => model.id === preview.fitModelRevisionId)
      || !document.meshAssets.some((asset) => asset.id === preview.meshAssetId)) {
      throw new TypeError('Template preview references an unknown fit model or mesh.');
    }
  }
  for (const revision of document.revisions) {
    if (revision.schemaVersion === 1) for (const preview of revision.previewMeshes) {
      if (!catalog.fitModels.some((model) => model.id === preview.fitModelRevisionId)
        || !document.meshAssets.some((asset) => asset.id === preview.meshAssetId)) {
        throw new TypeError(`Garment revision ${revision.id} refers to an unknown preview mesh.`);
      }
    }
  }
}

interface ProjectSummaryRecord {
  project: GarmentProject;
  revision: GarmentRevision;
  fitModel: FitModelRevision;
}

export function summarizeProjectRecord(input: unknown): ProjectSummary {
  assertValid('Stored project summary', validateProjectSummaryRecordSchema, input);
  const { project, revision, fitModel } = input as ProjectSummaryRecord;
  if (revision.schemaVersion === 2) validateParametricRevision(revision);
  if (project.schemaVersion === 1 && revision.schemaVersion !== 1) {
    throw new TypeError('Stored project summary schema does not match its current garment revision.');
  }
  if (project.schemaVersion === 2 && revision.schemaVersion === 2
    && (!project.selectedSizeId || !revision.development.sizeSet.sizes.some((size) => size.id === project.selectedSizeId))) {
    throw new TypeError('Stored project summary selects a size outside the current development chart.');
  }
  if (project.schemaVersion === 2 && revision.schemaVersion === 1 && project.selectedSizeId !== null) {
    throw new TypeError('A legacy current revision cannot select a parametric size.');
  }
  if (project.currentGarmentRevisionId !== revision.id || project.selectedFitModelRevisionId !== fitModel.id
    || revision.validationStatus !== 'illustrative' || fitModel.validationStatus !== 'illustrative'
    || project.name.trim() !== project.name || revision.name.trim() !== revision.name || fitModel.name.trim() !== fitModel.name
    || /[\u0000-\u001f\u007f]/u.test(project.name + revision.name + fitModel.name)
    || Date.parse(project.updatedAt) < Date.parse(project.createdAt)) {
    throw new TypeError('Stored project summary contains invalid project, garment, or fit-model references.');
  }
  return {
    id: project.id,
    name: project.name,
    updatedAt: project.updatedAt,
    garmentName: revision.name,
    color: revision.visualMaterial.color,
    fitModelName: fitModel.name,
  };
}

export async function validateCatalog(input: unknown, assets: AssetPayload[]): Promise<Library> {
  assertValid('Catalog', validateCatalogSchema, input);
  const catalog = input as Catalog;
  assertPinnedCatalog(catalog);
  const meshes = await admitAssets(catalog, assets);
  return { catalog, assets: structuredClone(assets), meshes };
}
export async function validatePackage(input: unknown, catalog: Catalog): Promise<ProjectPackage> {
  assertValid('Project package', validatePackageSchema, input);
  assertPinnedCatalog(catalog);
  const document = input as ProjectPackage;
  assertProjectSize(document);
  assertPackageReferences(document, catalog);
  await admitAssets(catalog, document.assets);
  return document;
}

function assertRenderMesh(mesh: AdmittedMesh | undefined, expectedId: string, label: string): asserts mesh is AdmittedMesh {
  if (!mesh || mesh.descriptor.id !== expectedId || mesh.descriptor.units !== 'm' || mesh.descriptor.validationStatus !== 'illustrative') {
    throw new TypeError(`${label} mesh is not an admitted maintained asset.`);
  }
  assertValid('Mesh asset descriptor', validateMeshDescriptorSchema, mesh.descriptor);
  const pinned = maintainedCatalog.meshAssets.find((descriptor) => descriptor.id === expectedId);
  if (!pinned || stableJson(pinned) !== stableJson(mesh.descriptor)) throw new TypeError(`${label} mesh descriptor is not pinned to the maintained catalog.`);
  if (mesh.mesh.format !== 'onyou-mesh-v1' || mesh.mesh.positions.length !== mesh.descriptor.vertexCount * 3
    || mesh.mesh.normals.length !== mesh.mesh.positions.length || mesh.mesh.indices.length !== mesh.descriptor.indexCount
    || mesh.mesh.indices.length < 3 || mesh.mesh.indices.length % 3 !== 0) {
    throw new TypeError(`${label} mesh data is malformed.`);
  }
}

export function validateModelInput(model: FitModelRevision, meshes: ReadonlyMap<string, AdmittedMesh>): { body: AdmittedMesh; shorts: AdmittedMesh } {
  assertValid('Fit model revision', validateFitModelSchema, model);
  if (model.validationStatus !== 'illustrative'
    || !maintainedCatalog.fitModels.some((candidate) => stableJson(candidate) === stableJson(model))) {
    throw new TypeError('Fit model is not an exact maintained catalog revision.');
  }
  const body = meshes.get(model.bodyMeshAssetId), shorts = meshes.get(model.baseGarmentMeshAssetId);
  assertRenderMesh(body, model.bodyMeshAssetId, 'Body');
  assertRenderMesh(shorts, model.baseGarmentMeshAssetId, 'Shorts');
  if (body.descriptor.id === shorts.descriptor.id) throw new TypeError('Model render components must reference distinct maintained meshes.');
  return { body, shorts };
}

export function validateParametricRevision(revision: ParametricGarmentRevision): void {
  assertValid('Parametric garment revision', validateGarmentRevisionV2Schema, revision);
  if (revision.validationStatus !== 'illustrative' || revision.templateId !== PARAMETRIC_TEMPLATE_ID
    || stableJson(revision.source) !== stableJson(PARAMETRIC_TEMPLATE_SOURCE)) {
    throw new TypeError('Parametric revision source or status is not maintained.');
  }
  validateDevelopment(revision.development, revision.id);
}

export function validateRenderInput(
  revision: LegacyGarmentRevision,
  model: FitModelRevision,
  meshes: ReadonlyMap<string, AdmittedMesh>,
): { body: AdmittedMesh; shorts: AdmittedMesh; garment: AdmittedMesh } {
  assertValid('Garment revision', validateGarmentRevisionSchema, revision);
  if (revision.validationStatus !== 'illustrative') throw new TypeError('Only illustrative maintained revisions can be rendered.');
  const { body, shorts } = validateModelInput(model, meshes);
  if (revision.templateId !== maintainedCatalog.template.id
    || revision.templateVersion !== maintainedCatalog.template.version
    || revision.geometryAdapter !== maintainedCatalog.template.geometryAdapter
    || stableJson(revision.drawing) !== stableJson(maintainedCatalog.template.drawing)
    || stableJson(revision.previewMeshes) !== stableJson(maintainedCatalog.template.previewMeshes)
    || stableJson(revision.source) !== stableJson(maintainedCatalog.template.source)) {
    throw new TypeError('Garment revision does not reference the maintained template.');
  }
  const preview = revision.previewMeshes.find((item) => item.fitModelRevisionId === model.id);
  if (!preview) throw new TypeError(`Garment revision has no preview for fit model ${model.id}.`);
  const garment = meshes.get(preview.meshAssetId);
  assertRenderMesh(garment, preview.meshAssetId, 'Garment');
  if (body.descriptor.id === garment.descriptor.id || shorts.descriptor.id === garment.descriptor.id) {
    throw new TypeError('Render components must reference distinct maintained meshes.');
  }
  return { body, shorts, garment };
}
