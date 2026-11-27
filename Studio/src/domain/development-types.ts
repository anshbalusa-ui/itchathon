import type { MeshData, SourceLicense, UUID } from './types';

export type DisplayUnit = 'cm' | 'in';
export type MeasurementId = 'bodyLength' | 'chestWidth' | 'hemWidth' | 'shoulderWidth' | 'sleeveLength' | 'sleeveOpening' | 'neckWidth' | 'neckDepth';
export type MeasurementValues = Record<MeasurementId, number>;
export type MeasurementSource = 'authored-default' | 'designer-input' | 'graded';
export type Vec2 = [number, number];
export type PieceId = 'front' | 'back' | 'sleeve-left' | 'sleeve-right' | 'neckband';
export type PatternView = 'front' | 'back' | 'pieces' | `piece-${PieceId}`;
export interface ComparisonSelection { revisionId: UUID; sizeId: UUID | null }

export interface MeasurementDefinition {
  id: MeasurementId;
  name: string;
  definition: string;
  method: 'horizontal-projection' | 'vertical-projection' | 'straight-distance' | 'half-path-length';
  endpoints: { pieceId: PieceId; startPointId: string; endPointId: string };
  rangeM: [number, number];
}
export interface GarmentSpecification {
  schemaVersion: 1;
  id: UUID;
  revisionId: UUID;
  garmentRevisionId: UUID;
  sizeId: UUID;
  definitionVersion: 'tshirt-pom-v1';
  units: 'm';
  values: MeasurementValues;
  tolerancesM: Partial<Record<MeasurementId, number>>;
  sources: Record<MeasurementId, MeasurementSource>;
  validationStatus: 'provisional-authored';
}
export interface PatternPoint { id: string; x: number; y: number }
export type PatternEdge = {
  id: string; from: string; to: string;
  role: 'shoulder' | 'side' | 'neckline' | 'armhole' | 'sleeve-cap' | 'underarm' | 'hem' | 'neckband-attachment' | 'neckband-fold' | 'neckband-join';
} & ({ kind: 'line' } | { kind: 'cubic'; control1: Vec2; control2: Vec2 });
export interface PatternPiece {
  id: PieceId;
  name: string;
  points: PatternPoint[];
  edges: PatternEdge[];
  grainline: { from: Vec2; to: Vec2 };
  fold: { edgeIds: string[]; instruction: string; line?: { id: string; from: Vec2; to: Vec2 } } | null;
  cutQuantity: number;
  mirrored: boolean;
  materialGroup: 'main' | 'rib';
  notches: { id: string; edgeId: string; t: number; kind: 'single' | 'double' }[];
  seamAllowance: { kind: 'uniform-offset'; distanceM: number; join: 'miter'; curveToleranceM: number };
  cuttingBoundary: Vec2[];
}
export interface SeamCorrespondence {
  id: string;
  a: { pieceId: PieceId; edgeIds: string[] };
  b: { pieceId: PieceId; edgeIds: string[] };
  relationship: 'equal-length' | 'sleeve-cap-ease' | 'neckband-stretch';
  orientation: 'opposed' | 'aligned';
  ratio: number;
  toleranceM: number;
}
export interface PatternDefinition {
  schemaVersion: 1;
  id: UUID;
  revisionId: UUID;
  garmentRevisionId: UUID;
  specificationRevisionId: UUID;
  sizeId: UUID;
  templateId: UUID;
  generatorVersion: '1.0.0';
  topologyVersion: 'tshirt-5-piece-v1';
  units: 'm';
  coordinates: { x: '+right'; y: '+up' };
  pieces: PatternPiece[];
  seams: SeamCorrespondence[];
  measuredValues: MeasurementValues;
  validation: { status: 'provisional-authored'; maximumSeamErrorM: number; warnings: string[] };
  source: SourceLicense;
}
export interface GradeRule {
  schemaVersion: 1;
  id: UUID;
  revisionId: UUID;
  garmentRevisionId: UUID;
  fromSizeId: UUID;
  toSizeId: UUID;
  method: 'explicit-per-measurement-delta';
  deltasM: MeasurementValues;
}
export interface SizeSet {
  schemaVersion: 1;
  id: UUID;
  revisionId: UUID;
  garmentRevisionId: UUID;
  baseSizeId: UUID;
  sizes: { id: UUID; label: string; specification: GarmentSpecification }[];
  gradeRules: GradeRule[];
}
export interface DevelopmentState {
  schemaVersion: 1;
  generatorVersion: '1.0.0';
  topologyVersion: 'tshirt-5-piece-v1';
  sizeSet: SizeSet;
  patterns: PatternDefinition[];
}
export interface DerivedGarmentMesh {
  kind: 'parametric-preview-v1';
  generatorVersion: '1.0.0';
  specificationRevisionId: UUID;
  patternRevisionId: UUID;
  sizeId: UUID;
  mesh: MeshData;
  measurementVertexIndices: Record<MeasurementId, [number, number]>;
  measurementVertexPaths: Partial<Record<MeasurementId, number[]>>;
  warnings: string[];
}
