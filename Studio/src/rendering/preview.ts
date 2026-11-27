import { BufferGeometry, Float32BufferAttribute, Uint32BufferAttribute } from 'three';
import { validateModelInput, validateParametricRevision, validateRenderInput } from '../domain/validation';
import type { AdmittedMesh, FitModelRevision, GarmentRevision, MeshData } from '../domain/types';
import type { DerivedGarmentMesh, GarmentSpecification, PatternDefinition } from '../domain/development-types';
import { generateGarmentMesh } from '../patterns/preview';
import { POMS } from '../patterns/generator';

export interface PreviewModelGeometry {
  body: BufferGeometry;
  shorts: BufferGeometry;
  bodyVertexCount: number;
  bodyHash: string;
  heightM: number;
}
export interface PreviewGeometrySet extends PreviewModelGeometry { garment: BufferGeometry }
export interface GarmentPreviewGeometry {
  geometry: BufferGeometry;
  identity: string;
  sizeLabel: string | null;
  offset: [number, number, number];
  warnings: string[];
}

function bufferGeometry(mesh: MeshData): BufferGeometry {
  const result = new BufferGeometry();
  result.setAttribute('position', new Float32BufferAttribute(mesh.positions, 3));
  result.setAttribute('normal', new Float32BufferAttribute(mesh.normals, 3));
  result.setIndex(new Uint32BufferAttribute(mesh.indices, 1));
  result.computeBoundingSphere();
  return result;
}

export function createModelGeometry(model: FitModelRevision, meshes: ReadonlyMap<string, AdmittedMesh>): PreviewModelGeometry {
  const { body, shorts } = validateModelInput(model, meshes);
  const bodyGeometry = bufferGeometry(body.mesh);
  bodyGeometry.computeBoundingBox();
  const bounds = bodyGeometry.boundingBox;
  if (!bounds || !Number.isFinite(bounds.min.y) || !Number.isFinite(bounds.max.y)) {
    bodyGeometry.dispose();
    throw new Error('Body mesh has invalid bounds.');
  }
  return { body: bodyGeometry, shorts: bufferGeometry(shorts.mesh), bodyVertexCount: body.descriptor.vertexCount, bodyHash: body.descriptor.sha256, heightM: bounds.max.y - bounds.min.y };
}

/** The sole admission path for deterministic generated garment surfaces, never arbitrary package meshes. */
export function admitDerivedGarmentMesh(derived: DerivedGarmentMesh, specification: GarmentSpecification, pattern: PatternDefinition): void {
  if (derived.kind !== 'parametric-preview-v1' || derived.generatorVersion !== '1.0.0'
    || derived.specificationRevisionId !== specification.revisionId || derived.patternRevisionId !== pattern.revisionId || derived.sizeId !== specification.sizeId) {
    throw new Error('Generated preview identity does not match the selected specification and pattern.');
  }
  const { positions, normals, indices } = derived.mesh;
  const count = positions.length / 3;
  if (derived.mesh.format !== 'onyou-mesh-v1' || !Number.isInteger(count) || count < 3 || count > 50_000
    || normals.length !== positions.length || indices.length < 3 || indices.length > 300_000 || indices.length % 3 !== 0
    || !positions.every(value => Number.isFinite(value) && Math.abs(value) < 10)) throw new Error('Generated preview exceeds supported finite meter geometry bounds.');
  for (let vertex = 0; vertex < count; vertex++) {
    const x = normals[vertex * 3], y = normals[vertex * 3 + 1], z = normals[vertex * 3 + 2];
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)
      || Math.abs(Math.hypot(x, y, z) - 1) > 0.02) throw new Error('Generated preview has an invalid unit normal.');
  }
  const used = new Uint8Array(count);
  const edges = new Map<number, number>();
  for (let offset = 0; offset < indices.length; offset += 3) {
    const a = indices[offset], b = indices[offset + 1], c = indices[offset + 2];
    if (!Number.isInteger(a) || a < 0 || a >= count || !Number.isInteger(b) || b < 0 || b >= count || !Number.isInteger(c) || c < 0 || c >= count) throw new Error('Generated preview has an invalid triangle index.');
    used[a] = 1; used[b] = 1; used[c] = 1;
    const x = positions[b * 3] - positions[a * 3], y = positions[b * 3 + 1] - positions[a * 3 + 1], z = positions[b * 3 + 2] - positions[a * 3 + 2];
    const u = positions[c * 3] - positions[a * 3], v = positions[c * 3 + 1] - positions[a * 3 + 1], w = positions[c * 3 + 2] - positions[a * 3 + 2];
    if (Math.hypot(y * w - z * v, z * u - x * w, x * v - y * u) < 1e-12) throw new Error('Generated preview contains a degenerate triangle.');
    for (let edge = 0; edge < 3; edge++) {
      const first = indices[offset + edge], second = indices[offset + (edge + 1) % 3];
      const key = Math.min(first, second) * count + Math.max(first, second), direction = first < second ? 1 : 2;
      const previous = edges.get(key) ?? 0;
      if (previous & direction) throw new Error('Generated preview has inconsistent or nonmanifold triangle winding.');
      edges.set(key, previous | direction);
    }
  }
  for (const pom of POMS) {
    const pair = derived.measurementVertexIndices[pom.id];
    if (!pair || pair.length !== 2 || !Number.isInteger(pair[0]) || !Number.isInteger(pair[1]) || !used[pair[0]] || !used[pair[1]]) throw new Error('Measurement endpoints must belong to the actual indexed garment surface.');
    if(pom.method==='half-path-length'){
      const path=derived.measurementVertexPaths[pom.id];
      if(!path||path.length<3||path.length>1024||path[0]!==pair[0]||path[path.length-1]!==pair[1])throw new Error('A developed measurement requires an indexed surface path');
      let length=0;
      for(let i=0;i<path.length;i++){
        const vertex=path[i];
        if(!Number.isInteger(vertex)||!used[vertex])throw new Error('Measurement path contains an unused vertex');
        if(i){const previous=path[i-1];if(!edges.has(Math.min(previous,vertex)*count+Math.max(previous,vertex)))throw new Error('Measurement path must follow actual triangle edges');length+=Math.hypot(positions[vertex*3]-positions[previous*3],positions[vertex*3+1]-positions[previous*3+1],positions[vertex*3+2]-positions[previous*3+2]);}
      }
      if(Math.abs(length/2-specification.values[pom.id])>1e-6)throw new Error('Generated developed measurement differs from its specification');
    }else{
      const a=pair[0]*3,b=pair[1]*3;
      const measured=pom.method==='horizontal-projection'?Math.abs(positions[a]-positions[b]):pom.method==='vertical-projection'?Math.abs(positions[a+1]-positions[b+1]):Math.hypot(positions[a]-positions[b],positions[a+1]-positions[b+1],positions[a+2]-positions[b+2]);
      if(Math.abs(measured-specification.values[pom.id])>1e-6)throw new Error('Generated endpoint measurement differs from its specification');
    }
  }
}

export function createGarmentGeometry(revision: GarmentRevision, model: FitModelRevision, meshes: ReadonlyMap<string, AdmittedMesh>, sizeId?: string | null): GarmentPreviewGeometry {
  if (revision.schemaVersion === 1) {
    const { garment } = validateRenderInput(revision, model, meshes);
    return { geometry: bufferGeometry(garment.mesh), identity: garment.descriptor.sha256, sizeLabel: null, offset: [0, 0, 0], warnings: ['Legacy authored shell adapted to this reference model; no historical garment specifications.'] };
  }
  validateParametricRevision(revision);
  const size = revision.development.sizeSet.sizes.find(item => item.id === (sizeId ?? revision.development.sizeSet.baseSizeId));
  const pattern = revision.development.patterns.find(item => item.sizeId === size?.id);
  if (!size || !pattern) throw new Error('The selected size has no admitted generated pattern.');
  const derived = generateGarmentMesh(size.specification, pattern);
  admitDerivedGarmentMesh(derived, size.specification, pattern);
  return {
    geometry: bufferGeometry(derived.mesh),
    identity: `${size.specification.revisionId}:${pattern.revisionId}:1.0.0`,
    sizeLabel: size.label,
    // Rigid shoulder-height placement only. No width, length or depth scaling by mannequin.
    offset: [0, model.heightM * (1.5 / 1.8), 0.055],
    warnings: [...derived.warnings, 'Rigid shoulder placement only; garment dimensions are unchanged across fitting models. Contact and drape are not solved.'],
  };
}

/** Adapt admitted, validated canonical mesh arrays to disposable Three.js geometry. */
export function createPreviewGeometry(
  revision: GarmentRevision,
  model: FitModelRevision,
  meshes: ReadonlyMap<string, AdmittedMesh>,
): PreviewGeometrySet {
  const body = createModelGeometry(model, meshes);
  try {
    const garment = createGarmentGeometry(revision, model, meshes);
    garment.geometry.translate(...garment.offset);
    return { ...body, garment: garment.geometry };
  } catch (error) {
    body.body.dispose(); body.shorts.dispose();
    throw error;
  }
}
