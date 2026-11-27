import {
  PRODUCER,
  SCHEMA_VERSION,
  type FitModelRevision,
  type GarmentProject,
  type GarmentRevision,
  type Library,
  type PreviewView,
  type ProjectDraft,
  type ProjectPackage,
} from './types';

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
): GarmentRevision {
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

function packageFromLibrary(library: Library, project: GarmentProject, revisions: GarmentRevision[]): ProjectPackage {
  return {
    format: 'onyou-project',
    schemaVersion: SCHEMA_VERSION,
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

export function createProject(library: Library, projectName: string, garmentName: string): ProjectPackage {
  if (library.catalog.fitModels.length === 0) throw new Error('The maintained catalog has no fit models.');
  const projectId = newId();
  const garmentId = newId();
  const now = new Date().toISOString();
  const garment = newGarmentRevision(library.catalog.template, garmentId, cleanName(garmentName, 'Garment name'), '#e8e5dc', null, now);
  const project: GarmentProject = {
    schemaVersion: SCHEMA_VERSION,
    id: projectId,
    revisionId: newId(),
    parentRevisionId: null,
    name: cleanName(projectName, 'Project name'),
    category: library.catalog.template.category,
    createdAt: now,
    updatedAt: now,
    producer: { ...PRODUCER },
    currentGarmentRevisionId: garment.id,
    selectedFitModelRevisionId: library.catalog.fitModels[0]!.id,
    previewView: 'split',
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
  };
}

export function isDirty(document: ProjectPackage, draft: ProjectDraft): boolean {
  const revision = currentRevision(document);
  return draft.projectName !== document.project.name
    || draft.garmentName !== revision.name
    || draft.color !== revision.visualMaterial.color
    || draft.fitModelRevisionId !== document.project.selectedFitModelRevisionId
    || draft.previewView !== document.project.previewView;
}

export function applyDraft(document: ProjectPackage, draft: ProjectDraft): ProjectPackage {
  const projectName = cleanName(draft.projectName, 'Project name');
  const garmentName = cleanName(draft.garmentName, 'Garment name');
  if (!COLOR_PATTERN.test(draft.color)) throw new RangeError('Garment color must be a six-digit hexadecimal color.');
  if (!VIEWS.includes(draft.previewView)) throw new RangeError('Preview view is not supported.');
  if (!document.fitModels.some((model) => model.id === draft.fitModelRevisionId)) {
    throw new RangeError('Selected fit model is not in this project package.');
  }

  const current = currentRevision(document);
  const garmentChanged = current.name !== garmentName || current.visualMaterial.color !== draft.color;
  if (garmentChanged && document.revisions.length >= 100) {
    throw new RangeError('A project cannot contain more than 100 immutable garment revisions.');
  }

  const revisions = garmentChanged
    ? [...document.revisions, newGarmentRevision(document.template, current.garmentId, garmentName, draft.color, current.id)]
    : document.revisions;
  const nextGarment = garmentChanged ? revisions[revisions.length - 1]! : current;
  const now = new Date().toISOString();
  return {
    ...document,
    packagedAt: now,
    revisions,
    project: {
      ...document.project,
      revisionId: newId(),
      parentRevisionId: document.project.revisionId,
      name: projectName,
      updatedAt: now,
      currentGarmentRevisionId: nextGarment.id,
      selectedFitModelRevisionId: draft.fitModelRevisionId,
      previewView: draft.previewView,
    },
  };
}

export function forkImported(document: ProjectPackage): ProjectPackage {
  const now = new Date().toISOString();
  return {
    ...document,
    packagedAt: now,
    project: {
      ...document.project,
      id: newId(),
      revisionId: newId(),
      parentRevisionId: null,
      importedFrom: {
        projectId: document.project.id,
        projectRevisionId: document.project.revisionId,
      },
      createdAt: now,
      updatedAt: now,
    },
  };
}
