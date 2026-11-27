import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { indexedDB } from 'fake-indexeddb';
import { applyDraft, createProject, draftOf, forkImported } from '../src/domain/projects';
import { ProjectRepository } from '../src/domain/repository';
import { validateCatalog } from '../src/domain/validation';
import { addSize, setGradeDelta, setMeasurement } from '../src/domain/development';
import type { Catalog } from '../src/domain/types';

const assetsDirectory = new URL('../public/assets/', import.meta.url);

async function catalogFixture() {
  const catalog = JSON.parse(await readFile(new URL('catalog.json', assetsDirectory), 'utf8')) as Catalog;
  const assets = await Promise.all(catalog.meshAssets.map(async (descriptor) => ({
    id: descriptor.id,
    data: await readFile(new URL(`${descriptor.id}.json`, assetsDirectory), 'utf8'),
  })));
  const library = await validateCatalog(catalog, assets);
  return { catalog, library };
}


test('unavailable IndexedDB is reported on reads without throwing in the constructor', async () => {
  const repository = new ProjectRepository({ indexedDB: null });
  try {
    await assert.rejects(repository.list(), /IndexedDB is unavailable/iu);
  } finally {
    repository.close();
  }
});

test('repository saves and reopens complete packages and lists acknowledged project summaries', async () => {
  const { catalog, library } = await catalogFixture();
  const repository = new ProjectRepository({ name: `studio-test-${globalThis.crypto.randomUUID()}`, indexedDB });
  try {
    const document = createProject(library, 'IndexedDB fixture', 'Classic shirt');
    await repository.save(document, catalog, null);
    const opened = await repository.open(document.project.id, catalog);
    assert.deepEqual(opened, document);
    assert.deepEqual(await repository.list(), [{
      id: document.project.id,
      name: document.project.name,
      updatedAt: document.project.updatedAt,
      garmentName: 'Classic shirt',
      color: '#e8e5dc',
      fitModelName: catalog.fitModels[0]!.name,
    }]);
  } finally {
    repository.close();
  }
});

test('stale and aborted saves leave the last acknowledged project recoverable', async () => {
  const { catalog, library } = await catalogFixture();
  const repository = new ProjectRepository({ name: `studio-recovery-${globalThis.crypto.randomUUID()}`, indexedDB });
  try {
    const initial = createProject(library, 'Recovery fixture', 'Classic shirt');
    await repository.save(initial, catalog, null);
    const acknowledged = await repository.open(initial.project.id, catalog);

    const latestDraft = draftOf(acknowledged);
    latestDraft.projectName = 'Acknowledged update';
    latestDraft.fitModelRevisionId = catalog.fitModels[1]!.id;
    const latest = applyDraft(acknowledged, latestDraft);
    await repository.save(latest, catalog, acknowledged.project.revisionId);

    const staleDraft = draftOf(acknowledged);
    staleDraft.garmentName = 'Stale edit';
    const stale = applyDraft(acknowledged, staleDraft);
    await assert.rejects(repository.save(stale, catalog, acknowledged.project.revisionId), /changed in another tab/iu);
    assert.deepEqual(await repository.open(initial.project.id, catalog), latest);
    const editedHistoryDraft = draftOf(latest);
    editedHistoryDraft.color = '#884422';
    const editedHistory = structuredClone(applyDraft(latest, editedHistoryDraft));
    editedHistory.revisions[0]!.name = 'Mutated saved history';
    await assert.rejects(repository.save(editedHistory, catalog, latest.project.revisionId), /cannot change or reorder.*immutable/iu);
    assert.deepEqual(await repository.open(initial.project.id, catalog), latest);

    const nextDraft = draftOf(latest);
    nextDraft.color = '#664422';
    const failed = applyDraft(latest, nextDraft);
    // Fault injection aborts a real fake-indexeddb readwrite transaction after the repository has opened it.
    const internalHandle = repository as unknown as { database?: IDBDatabase };
    const database = internalHandle.database;
    assert.ok(database);
    const originalTransaction = database.transaction.bind(database);
    Object.defineProperty(database, 'transaction', {
      configurable: true,
      value: (storeNames: string | string[], mode?: IDBTransactionMode, options?: IDBTransactionOptions) => {
        const transaction = originalTransaction(storeNames, mode, options);
        if (mode === 'readwrite') queueMicrotask(() => transaction.abort());
        return transaction;
      },
    });
    try {
      await assert.rejects(repository.save(failed, catalog, latest.project.revisionId), /not acknowledged|aborted/iu);
    } finally {
      Reflect.deleteProperty(database, 'transaction');
    }
    assert.deepEqual(await repository.open(initial.project.id, catalog), latest);
  } finally {
    repository.close();
  }
});

test('saving an imported fork creates a separate project without replacing its source', async () => {
  const { catalog, library } = await catalogFixture();
  const repository = new ProjectRepository({ name: `studio-import-${globalThis.crypto.randomUUID()}`, indexedDB });
  try {
    const source = createProject(library, 'Source project', 'Original garment');
    await repository.save(source, catalog, null);
    const imported = await repository.open(source.project.id, catalog);
    const fork = forkImported(imported);
    await repository.save(fork, catalog, null);
    assert.deepEqual(await repository.open(source.project.id, catalog), source);
    assert.deepEqual(await repository.open(fork.project.id, catalog), fork);
    assert.equal((await repository.list()).length, 2);
  } finally {
    repository.close();
  }
});
test('repository reopens and summarizes immutable v2 development state', async () => {
  const { catalog, library } = await catalogFixture();
  const repository = new ProjectRepository({ name: `studio-v2-${globalThis.crypto.randomUUID()}`, indexedDB });
  try {
    const initial = createProject(library, 'Parametric project', 'Block tee', 'parametric');
    await repository.save(initial, catalog, null);
    const draft = draftOf(initial);
    const base = draft.development!.sizeSet.baseSizeId;
    draft.development = addSize(setMeasurement(draft.development!, base, 'bodyLength', 0.74), 'Roomy');
    const roomy = draft.development.sizeSet.sizes[1]!.id;
    draft.development = setGradeDelta(draft.development, roomy, 'chestWidth', 0.02);
    draft.selectedSizeId = roomy;
    draft.displayUnit = 'in';
    draft.fitModelRevisionId = library.catalog.fitModels[1]!.id;
    const saved = applyDraft(initial, draft);
    await repository.save(saved, catalog, initial.project.revisionId);
    const reopened = await repository.open(saved.project.id, catalog);
    assert.deepEqual(reopened, saved);
    assert.equal((await repository.list())[0]!.garmentName, 'Block tee');
  } finally {
    repository.close();
  }
});
