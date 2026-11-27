import { summarizeProjectRecord, validatePackage } from './validation';
import type { Catalog, FitModelRevision, GarmentProject, GarmentRevision, ProjectPackage, ProjectSummary } from './types';

interface RepositoryOptions {
  name?: string;
  indexedDB?: IDBFactory | null;
}

interface StoredSummaryRecord {
  project: GarmentProject;
  revision: GarmentRevision;
  fitModel: FitModelRevision;
}

function stableStringify(value: unknown): string {
  return JSON.stringify(value, (_key, item: unknown) => {
    if (item === null || Array.isArray(item) || typeof item !== 'object') return item;
    return Object.fromEntries(Object.entries(item).sort(([left], [right]) => left.localeCompare(right)));
  }) ?? '';
}

function immutableHistoryError(stored: ProjectPackage, next: ProjectPackage): Error | undefined {
  if (!Array.isArray(stored.revisions)) return new TypeError('Stored garment revision history is malformed.');
  if (stored.revisions.length > next.revisions.length) {
    return new Error('A save cannot remove previously acknowledged immutable garment revisions.');
  }
  for (let index = 0; index < stored.revisions.length; index += 1) {
    if (stableStringify(stored.revisions[index]) !== stableStringify(next.revisions[index])) {
      const error = new Error('A save cannot change or reorder previously acknowledged immutable garment revisions.');
      error.name = 'ImmutableRevisionError';
      return error;
    }
  }
  return undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export class ProjectRepository {
  private readonly name: string;
  private readonly factory?: IDBFactory;
  private database?: IDBDatabase;
  private opening?: Promise<IDBDatabase>;
  private cancelOpening?: () => void;
  private closed = false;

  constructor(options: RepositoryOptions = {}) {
    this.name = options.name ?? 'onyou-studio-projects';
    this.factory = options.indexedDB === null ? undefined : options.indexedDB ?? globalThis.indexedDB;
  }

  private getDatabase(): Promise<IDBDatabase> {
    if (this.closed) return Promise.reject(new Error('Project repository is closed.'));
    if (!this.factory) return Promise.reject(new Error('IndexedDB is unavailable; projects cannot be saved in this browser.'));
    if (this.database) return Promise.resolve(this.database);
    if (this.opening) return this.opening;

    const pending = Promise.withResolvers<IDBDatabase>();
    this.opening = pending.promise;
    let settled = false;
    const rejectOpen = (message: string) => {
      if (settled) return;
      settled = true;
      this.opening = undefined;
      this.cancelOpening = undefined;
      pending.reject(new Error(message));
    };
    this.cancelOpening = () => rejectOpen('Project repository was closed while opening storage.');

    let request: IDBOpenDBRequest;
    try {
      request = this.factory.open(this.name, 1);
    } catch (error) {
      rejectOpen(`Could not open project storage: ${errorMessage(error)}`);
      return pending.promise;
    }
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains('projects')) database.createObjectStore('projects', { keyPath: 'project.id' });
      if (!database.objectStoreNames.contains('summaries')) database.createObjectStore('summaries', { keyPath: 'project.id' });
    };
    request.onblocked = () => {
      rejectOpen('Project storage upgrade is blocked by another open Studio tab. Close older tabs and try again.');
    };
    request.onerror = () => {
      rejectOpen(`Could not open project storage: ${request.error?.message ?? 'IndexedDB request failed.'}`);
    };
    request.onsuccess = () => {
      const database = request.result;
      database.onversionchange = () => {
        database.close();
        if (this.database === database) this.database = undefined;
        this.opening = undefined;
      };
      if (settled || this.closed) {
        database.close();
        rejectOpen('Project repository was closed while opening storage.');
        return;
      }
      settled = true;
      this.database = database;
      this.opening = undefined;
      this.cancelOpening = undefined;
      pending.resolve(database);
    };
    return pending.promise;
  }

  async list(): Promise<ProjectSummary[]> {
    const database = await this.getDatabase();
    const pending = Promise.withResolvers<StoredSummaryRecord[]>();
    let transaction: IDBTransaction;
    try {
      transaction = database.transaction('summaries', 'readonly');
    } catch (error) {
      throw new Error(`Could not read project storage: ${errorMessage(error)}`);
    }
    const request = transaction.objectStore('summaries').getAll() as IDBRequest<StoredSummaryRecord[]>;
    let records: StoredSummaryRecord[] = [];
    request.onsuccess = () => { records = request.result; };
    transaction.oncomplete = () => pending.resolve(records);
    transaction.onabort = () => pending.reject(new Error(`Could not read project storage: ${transaction.error?.message ?? 'IndexedDB transaction aborted.'}`));
    return (await pending.promise)
      .map((record) => summarizeProjectRecord(record))
      .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
  }

  async open(id: string, catalog: Catalog): Promise<ProjectPackage> {
    const database = await this.getDatabase();
    const pending = Promise.withResolvers<ProjectPackage>();
    let transaction: IDBTransaction;
    try {
      transaction = database.transaction('projects', 'readonly');
    } catch (error) {
      throw new Error(`Could not read project storage: ${errorMessage(error)}`);
    }
    const request = transaction.objectStore('projects').get(id) as IDBRequest<ProjectPackage | undefined>;
    let document: ProjectPackage | undefined;
    request.onsuccess = () => { document = request.result; };
    transaction.oncomplete = () => {
      if (!document) pending.reject(new Error(`Project ${id} was not found.`));
      else if (document.project.id !== id) pending.reject(new Error(`Project storage returned a mismatched project for ${id}.`));
      else pending.resolve(document);
    };
    transaction.onabort = () => pending.reject(new Error(`Could not read project storage: ${transaction.error?.message ?? 'IndexedDB transaction aborted.'}`));
    return validatePackage(await pending.promise, catalog);
  }

  async save(document: ProjectPackage, catalog: Catalog, expectedRevisionId: string | null): Promise<void> {
    const validated = await validatePackage(document, catalog);
    if (validated.project.parentRevisionId !== expectedRevisionId || validated.project.revisionId === expectedRevisionId) {
      throw new TypeError('Saved project revision must have a new revision ID and the expected parent revision ID.');
    }
    const revision = validated.revisions.find((item) => item.id === validated.project.currentGarmentRevisionId)!;
    const fitModel = validated.fitModels.find((item) => item.id === validated.project.selectedFitModelRevisionId)!;
    const summary: StoredSummaryRecord = { project: validated.project, revision, fitModel };
    const database = await this.getDatabase();
    const pending = Promise.withResolvers<void>();
    let transaction: IDBTransaction;
    try {
      transaction = database.transaction(['projects', 'summaries'], 'readwrite');
    } catch (error) {
      throw new Error(`Could not start project save: ${errorMessage(error)}`);
    }
    let failure: Error | undefined;
    const projects = transaction.objectStore('projects');
    const summaries = transaction.objectStore('summaries');
    const request = projects.get(validated.project.id) as IDBRequest<ProjectPackage | undefined>;
    request.onsuccess = () => {
      const stored = request.result;
      if (stored && (!stored.project || stored.project.id !== validated.project.id || typeof stored.project.revisionId !== 'string')) {
        failure = new TypeError('Stored project revision is malformed; refusing to overwrite it.');
        transaction.abort();
        return;
      }
      const actualRevisionId = stored?.project?.revisionId ?? null;
      if (actualRevisionId !== expectedRevisionId) {
        failure = new Error(`Project ${validated.project.id} changed in another tab (expected ${expectedRevisionId ?? 'no existing revision'}, found ${actualRevisionId ?? 'none'}).`);
        failure.name = 'RevisionConflictError';
        transaction.abort();
        return;
      }
      if (stored) {
        failure = immutableHistoryError(stored, validated);
        if (failure) {
          transaction.abort();
          return;
        }
      }
      try {
        projects.put(validated);
        summaries.put(summary);
      } catch (error) {
        failure = error instanceof Error ? error : new Error(String(error));
        transaction.abort();
      }
    };
    transaction.oncomplete = () => pending.resolve();
    transaction.onabort = () => {
      pending.reject(failure ?? new Error(`Project save was not acknowledged: ${transaction.error?.message ?? 'IndexedDB transaction aborted.'}`));
    };
    return pending.promise;
  }

  close(): void {
    this.closed = true;
    this.cancelOpening?.();
    this.database?.close();
    this.database = undefined;
    this.opening = undefined;
  }
}
