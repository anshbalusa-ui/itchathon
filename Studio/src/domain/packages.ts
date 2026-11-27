import { MAX_PACKAGE_BYTES, validatePackage } from './validation';
import type { Catalog, ProjectPackage } from './types';

export { MAX_PACKAGE_BYTES };

const encoder = new TextEncoder();
export async function readPackage(file: File, catalog: Catalog): Promise<ProjectPackage> {
  if (file.size > MAX_PACKAGE_BYTES) throw new RangeError('Project package exceeds the 12 MiB import limit.');
  const text = await file.text();
  if (encoder.encode(text).byteLength > MAX_PACKAGE_BYTES) {
    throw new RangeError('Project package exceeds the 12 MiB import limit.');
  }
  let input: unknown;
  try {
    input = JSON.parse(text) as unknown;
  } catch {
    throw new TypeError('Project package is not valid JSON.');
  }
  return validatePackage(input, catalog);
}

export async function exportPackage(document: ProjectPackage, catalog: Catalog): Promise<Blob> {
  const validated = await validatePackage(document, catalog);
  const text = JSON.stringify(validated);
  if (encoder.encode(text).byteLength > MAX_PACKAGE_BYTES) {
    throw new RangeError('Project package exceeds the 12 MiB export limit.');
  }
  return new Blob([text], { type: 'application/json' });
}
