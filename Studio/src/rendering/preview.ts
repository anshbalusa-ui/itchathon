import { BufferGeometry, Float32BufferAttribute, Uint32BufferAttribute } from 'three';
import { validateRenderInput } from '../domain/validation';
import type { AdmittedMesh, FitModelRevision, GarmentRevision } from '../domain/types';

export interface PreviewGeometrySet {
  body: BufferGeometry;
  shorts: BufferGeometry;
  garment: BufferGeometry;
  bodyVertexCount: number;
  bodyHash: string;
  heightM: number;
}

/** Adapt admitted, validated canonical mesh arrays to disposable Three.js geometry. */
export function createPreviewGeometry(
  revision: GarmentRevision,
  model: FitModelRevision,
  meshes: ReadonlyMap<string, AdmittedMesh>,
): PreviewGeometrySet {
  const { body, shorts, garment } = validateRenderInput(revision, model, meshes);
  const geometry = (admitted: AdmittedMesh): BufferGeometry => {
    const result = new BufferGeometry();
    result.setAttribute('position', new Float32BufferAttribute(admitted.mesh.positions, 3));
    result.setAttribute('normal', new Float32BufferAttribute(admitted.mesh.normals, 3));
    result.setIndex(new Uint32BufferAttribute(admitted.mesh.indices, 1));
    result.computeBoundingSphere();
    return result;
  };
  const bodyGeometry = geometry(body);
  bodyGeometry.computeBoundingBox();
  const bounds = bodyGeometry.boundingBox;
  if (!bounds || !Number.isFinite(bounds.min.y) || !Number.isFinite(bounds.max.y)) {
    bodyGeometry.dispose();
    throw new Error('Body mesh has invalid bounds');
  }
  return {
    body: bodyGeometry,
    shorts: geometry(shorts),
    garment: geometry(garment),
    bodyVertexCount: body.descriptor.vertexCount,
    bodyHash: body.descriptor.sha256,
    heightM: bounds.max.y - bounds.min.y,
  };
}
