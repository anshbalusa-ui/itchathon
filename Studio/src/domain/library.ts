import type { AssetPayload, Catalog, Library } from './types';
import { validateCatalog } from './validation';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function boundedText(response: Response, maximumBytes: number): Promise<string> {
  if (!response.ok || !response.body) throw new Error('A bundled preview asset could not be loaded. Reload the Studio to retry.');
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maximumBytes) throw new Error('A bundled asset exceeds the supported resource limit.');
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

export async function loadLibrary(signal?: AbortSignal): Promise<Library> {
  const base = `${import.meta.env.BASE_URL}assets/`;
  const input: unknown = JSON.parse(await boundedText(await fetch(`${base}catalog.json`, { signal }), 100_000));
  // Only fixed local UUID paths are fetched. Imported packages never supply a URL.
  const candidate = input as Partial<Catalog> | null;
  if (!candidate || candidate.schemaVersion !== 1 || !Array.isArray(candidate.meshAssets)
    || candidate.meshAssets.length !== 6 || !candidate.meshAssets.every(asset => asset && UUID.test(asset.id))) {
    throw new Error('The bundled template catalog is incompatible with this Studio version.');
  }
  const assets: AssetPayload[] = await Promise.all(candidate.meshAssets.map(async descriptor => ({
    id: descriptor.id,
    data: await boundedText(await fetch(`${base}${descriptor.id}.json`, { signal }), 3 * 1024 * 1024),
  })));
  return validateCatalog(input, assets);
}
