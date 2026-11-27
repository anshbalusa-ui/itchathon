import type { ComparisonSelection, DevelopmentState, DisplayUnit, PatternView } from './development-types';

export const SCHEMA_VERSION = 1 as const;
export const PRODUCER = { name: 'On You Studio', version: '0.1.0' } as const;

export type UUID = string;
export type PreviewView = 'split' | '2d' | '3d';
export type Vec3 = [number, number, number];
export interface Producer { name: string; version: string }
export interface SourceLicense {
  label: string;
  uri: string;
  sha256: string;
  license: 'CC0-1.0';
  notice: string;
}
export interface MeshAssetDescriptor {
  schemaVersion: 1;
  id: UUID;
  createdAt: string;
  producer: Producer;
  format: 'onyou-mesh-v1';
  sha256: string;
  byteLength: number;
  vertexCount: number;
  indexCount: number;
  topologyVersion: 1;
  topologySha256: string;
  units: 'm';
  coordinates: { handedness: 'right'; up: '+Y'; front: '+Z'; winding: 'counter-clockwise'; matrixOrder: 'column-major' };
  bounds: { minimum: Vec3; maximum: Vec3 };
  source: SourceLicense;
  sourceToCanonical: { sourceFrameId: string; canonicalFrameId: 'onyou-y-up-m'; matrix: number[] };
  validationStatus: 'illustrative';
}
export interface FitModelRevision {
  schemaVersion: 1;
  id: UUID;
  modelId: UUID;
  parentRevisionId: UUID | null;
  name: string;
  createdAt: string;
  producer: Producer;
  geometryKind: 'standardFitModel';
  bodyMeshAssetId: UUID;
  baseGarmentMeshAssetId: UUID;
  poseId: 'authored-standing-v1';
  heightM: number;
  measurementBasis: 'authored-mesh-bounds';
  source: SourceLicense;
  validationStatus: 'illustrative';
}
export interface GarmentDrawing {
  kind: 'illustrative-outline-v1';
  units: 'm';
  outline: [number, number][];
  neckline: [number, number][];
}
export interface GarmentTemplate {
  id: UUID;
  version: '1.0.0';
  name: string;
  category: 'tshirt';
  geometryAdapter: 'authored-preview-v1';
  supportedVisualParameters: ['color'];
  drawing: GarmentDrawing;
  previewMeshes: { fitModelRevisionId: UUID; meshAssetId: UUID }[];
  source: SourceLicense;
}
export interface LegacyGarmentRevision {
  schemaVersion: 1;
  id: UUID;
  garmentId: UUID;
  parentRevisionId: UUID | null;
  createdAt: string;
  producer: Producer;
  name: string;
  category: 'tshirt';
  templateId: UUID;
  templateVersion: '1.0.0';
  geometryAdapter: 'authored-preview-v1';
  visualMaterial: { color: string };
  drawing: GarmentDrawing;
  previewMeshes: { fitModelRevisionId: UUID; meshAssetId: UUID }[];
  source: SourceLicense;
  validationStatus: 'illustrative';
}
export interface ParametricGarmentRevision extends Omit<LegacyGarmentRevision, 'schemaVersion' | 'templateVersion' | 'geometryAdapter' | 'drawing' | 'previewMeshes'> {
  schemaVersion: 2;
  templateVersion: '2.0.0';
  geometryAdapter: 'parametric-tshirt-v1';
  development: DevelopmentState;
  restoredFromRevisionId?: UUID;
}
export type GarmentRevision = LegacyGarmentRevision | ParametricGarmentRevision;

export interface GarmentProject {
  schemaVersion: 1 | 2;
  id: UUID;
  revisionId: UUID;
  parentRevisionId: UUID | null;
  importedFrom?: { projectId: UUID; projectRevisionId: UUID };
  name: string;
  category: 'tshirt';
  createdAt: string;
  updatedAt: string;
  producer: Producer;
  currentGarmentRevisionId: UUID;
  selectedFitModelRevisionId: UUID;
  previewView: PreviewView;
  selectedSizeId?: UUID | null;
  displayUnit?: DisplayUnit;
  patternView?: PatternView;
  comparison?: ComparisonSelection | null;
  validationStatus: 'illustrative';
}
export interface MeshData {
  format: 'onyou-mesh-v1';
  positions: number[];
  normals: number[];
  indices: number[];
}
export interface AssetPayload { id: UUID; data: string }
export interface Catalog {
  schemaVersion: 1;
  template: GarmentTemplate;
  fitModels: FitModelRevision[];
  meshAssets: MeshAssetDescriptor[];
}
export interface ProjectPackage {
  format: 'onyou-project';
  schemaVersion: 1 | 2;
  packagedAt: string;
  project: GarmentProject;
  revisions: GarmentRevision[];
  template: GarmentTemplate;
  fitModels: FitModelRevision[];
  meshAssets: MeshAssetDescriptor[];
  assets: AssetPayload[];
  previewStatus: 'illustrative';
  limitations: string[];
}
export interface AdmittedMesh { descriptor: MeshAssetDescriptor; mesh: MeshData }
export interface Library {
  catalog: Catalog;
  assets: AssetPayload[];
  meshes: ReadonlyMap<UUID, AdmittedMesh>;
}
export interface ProjectDraft {
  projectName: string;
  garmentName: string;
  color: string;
  fitModelRevisionId: UUID;
  previewView: PreviewView;
  development?: DevelopmentState;
  selectedSizeId?: UUID | null;
  displayUnit?: DisplayUnit;
  patternView?: PatternView;
  comparison?: ComparisonSelection | null;
  restoreFromRevisionId?: UUID | null;
}
export interface ProjectSummary {
  id: UUID;
  name: string;
  updatedAt: string;
  garmentName: string;
  color: string;
  fitModelName: string;
}
