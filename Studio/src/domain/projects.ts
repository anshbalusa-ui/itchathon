import {
  PRODUCER,
  SCHEMA_VERSION,
  type GarmentProject,
  type GarmentRevision,
  type LegacyGarmentRevision,
  type ParametricGarmentRevision,
  type Library,
  type PreviewView,
  type ProjectDraft,
  type ProjectPackage,
} from './types';
import type { DevelopmentState } from './development-types';
import { createDevelopment, rebindDevelopment, validateDevelopment } from './development';
import { PARAMETRIC_TEMPLATE_ID, PARAMETRIC_TEMPLATE_SOURCE } from '../patterns/generator';

export const PROJECT_LIMITATIONS = [
  'Illustrative preview only; this package is not a validated fit, sizing, or manufacturing result.',
  'The two-dimensional outline is illustrative and is not a cutting pattern.',
  'Fit-model variants are authored visual references, not measured percentile bodies.',
];
const COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/;
const VIEWS: readonly PreviewView[] = ['split', '2d', '3d'];

function newId(): string {
  return globalThis.crypto.randomUUID();
}

function cleanName(value: string, label: string): string {
  if (typeof value !== 'string') throw new TypeError(`${label} must be text.`);
  const name = value.trim();
  if (name.length < 1 || name.length > 80 || /[\u0000-\u001f\u007f]/u.test(name)) {
    throw new RangeError(`${label} must contain 1–80 printable characters.`);
  }
  return name;
}

function newGarmentRevision(
  template: ProjectPackage['template'],
  garmentId: string,
  name: string,
  color: string,
  parentRevisionId: string | null,
  createdAt = new Date().toISOString(),
): LegacyGarmentRevision {
  return {
    schemaVersion: SCHEMA_VERSION,
    id: newId(),
    garmentId,
    parentRevisionId,
    createdAt,
    producer: { ...PRODUCER },
    name,
    category: template.category,
    templateId: template.id,
    templateVersion: template.version,
    geometryAdapter: template.geometryAdapter,
    visualMaterial: { color },
    drawing: structuredClone(template.drawing),
    previewMeshes: structuredClone(template.previewMeshes),
    source: structuredClone(template.source),
    validationStatus: 'illustrative',
  };
}

function newParametricRevision(
  garmentId: string,
  name: string,
  color: string,
  parentRevisionId: string | null,
  createdAt = new Date().toISOString(),
  development?: DevelopmentState,
  restoredFromRevisionId?: string,
): ParametricGarmentRevision {
  const revisionId = newId();
  return {
    schemaVersion: 2, id: revisionId, garmentId, parentRevisionId, createdAt,
    producer: { ...PRODUCER }, name, category: 'tshirt', templateId: PARAMETRIC_TEMPLATE_ID,
    templateVersion: '2.0.0', geometryAdapter: 'parametric-tshirt-v1',
    visualMaterial: { color }, source: structuredClone(PARAMETRIC_TEMPLATE_SOURCE),
    validationStatus: 'illustrative',
    development: development ? rebindDevelopment(development, revisionId) : createDevelopment(revisionId),
    ...(restoredFromRevisionId ? { restoredFromRevisionId } : {}),
  };
}

function packageFromLibrary(library: Library, project: GarmentProject, revisions: GarmentRevision[]): ProjectPackage {
  return {
    format: 'onyou-project',
    schemaVersion: project.schemaVersion,
    packagedAt: new Date().toISOString(),
    project,
    revisions,
    template: structuredClone(library.catalog.template),
    fitModels: structuredClone(library.catalog.fitModels),
    meshAssets: structuredClone(library.catalog.meshAssets),
    assets: library.assets.map(({ id, data }) => ({ id, data })),
    previewStatus: 'illustrative',
    limitations: [...PROJECT_LIMITATIONS],
  };
}

export function createProject(library: Library, projectName: string, garmentName: string, template: 'legacy' | 'parametric' = 'legacy'): ProjectPackage {
  if (library.catalog.fitModels.length === 0) throw new Error('The maintained catalog has no fit models.');
  const projectId = newId();
  const garmentId = newId();
  const now = new Date().toISOString();
  const name = cleanName(garmentName, 'Garment name');
  const garment = template === 'parametric'
    ? newParametricRevision(garmentId, name, '#e8e5dc', null, now)
    : newGarmentRevision(library.catalog.template, garmentId, name, '#e8e5dc', null, now);
  const project: GarmentProject = {
    schemaVersion: template === 'parametric' ? 2 : SCHEMA_VERSION,
    id: projectId, revisionId: newId(), parentRevisionId: null,
    name: cleanName(projectName, 'Project name'), category: library.catalog.template.category,
    createdAt: now, updatedAt: now, producer: { ...PRODUCER }, currentGarmentRevisionId: garment.id,
    selectedFitModelRevisionId: library.catalog.fitModels[0]!.id, previewView: 'split',
    ...(garment.schemaVersion === 2 ? { selectedSizeId: garment.development.sizeSet.baseSizeId, displayUnit: 'cm' as const, patternView: 'pieces' as const, comparison: null } : {}),
    validationStatus: 'illustrative',
  };
  return packageFromLibrary(library, project, [garment]);
}

export function currentRevision(document: ProjectPackage): GarmentRevision {
  const revision = document.revisions.find((item) => item.id === document.project.currentGarmentRevisionId);
  if (!revision) throw new Error(`Current garment revision ${document.project.currentGarmentRevisionId} is missing.`);
  return revision;
}

export function draftOf(document: ProjectPackage): ProjectDraft {
  const revision = currentRevision(document);
  return {
    projectName: document.project.name,
    garmentName: revision.name,
    color: revision.visualMaterial.color,
    fitModelRevisionId: document.project.selectedFitModelRevisionId,
    previewView: document.project.previewView,
    ...(revision.schemaVersion === 2 ? { development: structuredClone(revision.development) } : {}),
    selectedSizeId: document.project.selectedSizeId ?? null,
    displayUnit: document.project.displayUnit ?? 'cm',
    patternView: document.project.patternView ?? 'pieces',
    comparison: structuredClone(document.project.comparison ?? null),
  };
}

export function isDirty(document: ProjectPackage, draft: ProjectDraft): boolean {
  const revision = currentRevision(document);
  return draft.projectName !== document.project.name || draft.garmentName !== revision.name
    || draft.color !== revision.visualMaterial.color || draft.fitModelRevisionId !== document.project.selectedFitModelRevisionId
    || draft.previewView !== document.project.previewView
    || JSON.stringify(draft.development) !== JSON.stringify(revision.schemaVersion === 2 ? revision.development : undefined)
    || (draft.selectedSizeId ?? null) !== (document.project.selectedSizeId ?? null)
    || (draft.displayUnit ?? 'cm') !== (document.project.displayUnit ?? 'cm')
    || (draft.patternView ?? 'pieces') !== (document.project.patternView ?? 'pieces')
    || (document.schemaVersion === 2 && JSON.stringify(draft.comparison ?? null) !== JSON.stringify(document.project.comparison ?? null))
    || (draft.restoreFromRevisionId ?? null) !== null;
}

export function applyDraft(document: ProjectPackage, draft: ProjectDraft): ProjectPackage {
  const projectName = cleanName(draft.projectName, 'Project name');
  const garmentName = cleanName(draft.garmentName, 'Garment name');
  if (!COLOR_PATTERN.test(draft.color)) throw new RangeError('Garment color must be a six-digit hexadecimal color.');
  if (!VIEWS.includes(draft.previewView)) throw new RangeError('Preview view is not supported.');
  if (!document.fitModels.some((model) => model.id === draft.fitModelRevisionId)) throw new RangeError('Selected fit model is not in this project package.');
  const current = currentRevision(document);
  let restored: GarmentRevision | undefined;
  if (draft.restoreFromRevisionId) {
    restored = document.revisions.find((revision) => revision.id === draft.restoreFromRevisionId);
    if (!restored) throw new RangeError(`Cannot restore missing garment revision ${draft.restoreFromRevisionId}.`);
  }
  if (document.schemaVersion === 1 && draft.development) throw new TypeError('Upgrade a V1 project before editing parametric development.');
  const nextIsV2 = document.schemaVersion === 2 || (restored?.schemaVersion === 2);
  if (nextIsV2 && draft.development) validateDevelopment(draft.development);
  if (!restored && current.schemaVersion === 2) validateDevelopment(draft.development ?? current.development, current.id);
  const developmentChanged = nextIsV2 && draft.development !== undefined
    && JSON.stringify(draft.development) !== JSON.stringify(current.schemaVersion === 2 ? current.development : undefined);
  const garmentChanged = restored !== undefined || garmentName !== current.name || draft.color !== current.visualMaterial.color || developmentChanged;
  if (garmentChanged && document.revisions.length >= 100) throw new RangeError('A project cannot contain more than 100 immutable garment revisions.');
  const now = new Date().toISOString();
  let appended: GarmentRevision | undefined;
  if (restored) {
    appended = restored.schemaVersion === 2
      ? newParametricRevision(current.garmentId, restored.name, restored.visualMaterial.color, current.id, now, restored.development, restored.id)
      : { ...restored, id: newId(), parentRevisionId: current.id, createdAt: now };
  } else if (garmentChanged) {
    appended = current.schemaVersion === 2 || draft.development
      ? newParametricRevision(current.garmentId, garmentName, draft.color, current.id, now, draft.development ?? (current.schemaVersion === 2 ? current.development : undefined))
      : newGarmentRevision(document.template, current.garmentId, garmentName, draft.color, current.id, now);
  }
  const revisions = appended ? [...document.revisions, appended] : document.revisions;
  const active = appended ?? current;
  const sizes = active.schemaVersion === 2 ? active.development.sizeSet.sizes : [];
  const selectedSizeId = active.schemaVersion === 2
    ? restored
      ? (draft.selectedSizeId && sizes.some(size => size.id === draft.selectedSizeId) ? draft.selectedSizeId : active.development.sizeSet.baseSizeId)
      : draft.selectedSizeId ?? (sizes.some(size => size.id === document.project.selectedSizeId) ? document.project.selectedSizeId : active.development.sizeSet.baseSizeId)
    : null;
  if (active.schemaVersion === 2 && !sizes.some((size) => size.id === selectedSizeId)) throw new RangeError('Selected size is not in the current development chart.');
  if (draft.displayUnit !== undefined && !['cm', 'in'].includes(draft.displayUnit)) throw new RangeError('Display unit is not supported.');
  if (draft.patternView !== undefined && !['front', 'back', 'pieces', 'piece-front', 'piece-back', 'piece-sleeve-left', 'piece-sleeve-right', 'piece-neckband'].includes(draft.patternView)) throw new RangeError('Pattern view is not supported.');
  const comparison = restored ? null : draft.comparison
    ? { ...draft.comparison, ...(appended && draft.comparison.revisionId === current.id ? { revisionId: active.id } : {}) }
    : null;
  const project: GarmentProject = {
    ...document.project,
    schemaVersion: nextIsV2 ? 2 : 1,
    revisionId: newId(), parentRevisionId: document.project.revisionId,
    name: projectName, updatedAt: now, currentGarmentRevisionId: active.id,
    selectedFitModelRevisionId: draft.fitModelRevisionId, previewView: draft.previewView,
    ...(nextIsV2 ? { selectedSizeId, displayUnit: draft.displayUnit ?? 'cm', patternView: draft.patternView ?? 'pieces', comparison: structuredClone(comparison) } : {}),
  };
  return { ...document, schemaVersion: project.schemaVersion, packagedAt: now, revisions, project };
}

export function upgradeProject(document: ProjectPackage): ProjectPackage {
  if (currentRevision(document).schemaVersion === 2) return document;
  if (document.revisions.length >= 100) throw new RangeError('A project cannot contain more than 100 immutable garment revisions.');
  const current = currentRevision(document);
  const upgraded = newParametricRevision(current.garmentId, current.name, current.visualMaterial.color, current.id);
  const now = new Date().toISOString();
  return { ...document, schemaVersion: 2, packagedAt: now,
    revisions: [...document.revisions, upgraded],
    project: { ...document.project, schemaVersion: 2, revisionId: newId(), parentRevisionId: document.project.revisionId,
      currentGarmentRevisionId: upgraded.id, selectedSizeId: upgraded.development.sizeSet.baseSizeId,
      displayUnit: 'cm', patternView: 'pieces', comparison: null, updatedAt: now } };
}

export function restoreRevision(document: ProjectPackage, revisionId: string): ProjectPackage {
  const draft = draftOf(document);
  return applyDraft(document, { ...draft, restoreFromRevisionId: revisionId });
}

export function forkImported(document: ProjectPackage): ProjectPackage {
  const now = new Date().toISOString();
  return {
    ...document, packagedAt: now,
    project: { ...document.project, id: newId(), revisionId: newId(), parentRevisionId: null,
      importedFrom: { projectId: document.project.id, projectRevisionId: document.project.revisionId },
      createdAt: now, updatedAt: now },
  };
}

