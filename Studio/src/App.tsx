import { useEffect, useRef, useState } from 'react';
import type { ChangeEvent, FormEvent } from 'react';
import { GarmentDrawing } from './components/GarmentDrawing';
import { GarmentViewer } from './components/GarmentViewer';
import { loadLibrary } from './domain/library';
import { exportPackage, readPackage } from './domain/packages';
import { applyDraft, createProject, currentRevision, draftOf, forkImported, isDirty } from './domain/projects';
import { ProjectRepository } from './domain/repository';
import type { Library, PreviewView, ProjectDraft, ProjectPackage, ProjectSummary } from './domain/types';

const COLORS = [
  { name: 'Chalk', value: '#e8e5dc' }, { name: 'Ink', value: '#273342' },
  { name: 'Moss', value: '#677361' }, { name: 'Clay', value: '#a56954' },
  { name: 'Charcoal', value: '#353b3a' },
];
const messageOf = (error: unknown) => error instanceof Error ? error.message : 'The operation failed. Your previous saved project has not been replaced.';
type Navigation = { label: string; action: () => void };

function UnsavedDialog({ navigation, busy, error, onSave, onDiscard, onCancel }: {
  navigation: Navigation; busy: boolean; error: string | null;
  onSave: () => void; onDiscard: () => void; onCancel: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => { dialog.current?.showModal(); }, []);
  return <dialog ref={dialog} className="unsaved-dialog" aria-labelledby="unsaved-title" onCancel={event => { event.preventDefault(); if (!busy) onCancel(); }}>
    <p className="eyebrow">Unsaved changes</p>
    <h2 id="unsaved-title">Save before {navigation.label}?</h2>
    <p>Your latest edits are only in this tab. The last acknowledged save stays unchanged if you discard them.</p>
    {error && <p className="inline-error" role="alert">{error}</p>}
    <div className="dialog-actions">
      <button className="primary" onClick={onSave} disabled={busy}>{busy ? 'Saving…' : 'Save and continue'}</button>
      <button onClick={onDiscard} disabled={busy}>Discard changes</button>
      <button className="text-button" onClick={onCancel} disabled={busy}>Keep editing</button>
    </div>
  </dialog>;
}

export function App() {
  const [repository] = useState(() => new ProjectRepository());
  const [library, setLibrary] = useState<Library | null>(null);
  const [libraryError, setLibraryError] = useState<string | null>(null);
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [listLoading, setListLoading] = useState(true);
  const [listError, setListError] = useState(false);
  const [document, setDocument] = useState<ProjectPackage | null>(null);
  const [draft, setDraft] = useState<ProjectDraft | null>(null);
  const [checkpoint, setCheckpoint] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [durability, setDurability] = useState<'unknown' | 'granted' | 'not-granted' | 'unavailable'>('unknown');
  const [navigation, setNavigation] = useState<Navigation | null>(null);
  const [newProjectName, setNewProjectName] = useState('');
  const [newGarmentName, setNewGarmentName] = useState('Everyday T-shirt');
  const importInput = useRef<HTMLInputElement>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const createInput = useRef<HTMLInputElement>(null);
  const dirty = !!(document && draft && (checkpoint === null || isDirty(document, draft)));

  async function refreshProjects() {
    setListLoading(true);
    try { setProjects(await repository.list()); setListError(false); }
    catch (cause) { setError(messageOf(cause)); setListError(true); }
    finally { setListLoading(false); }
  }

  useEffect(() => {
    const abort = new AbortController();
    setLibraryError(null);
    loadLibrary(abort.signal).then(setLibrary).catch(cause => {
      if (!abort.signal.aborted) setLibraryError(messageOf(cause));
    });
    return () => abort.abort();
  }, [loadAttempt]);
  useEffect(() => { void refreshProjects(); return () => repository.close(); }, [repository]);
  useEffect(() => {
    if (!navigator.storage?.persisted) { setDurability('unavailable'); return; }
    void navigator.storage.persisted().then(granted => setDurability(granted ? 'granted' : 'not-granted')).catch(() => setDurability('unavailable'));
  }, []);
  useEffect(() => { if (document) heading.current?.focus(); }, [document?.project.id]);
  useEffect(() => {
    if (!dirty) return;
    const protect = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ''; };
    window.addEventListener('beforeunload', protect);
    return () => window.removeEventListener('beforeunload', protect);
  }, [dirty]);
  useEffect(() => {
    const saveShortcut = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's' && document) {
        event.preventDefault();
        if (!busy && !navigation) void save();
      }
    };
    window.addEventListener('keydown', saveShortcut);
    return () => window.removeEventListener('keydown', saveShortcut);
  });

  async function requestDurability() {
    if (!navigator.storage?.persist) { setDurability('unavailable'); return; }
    try { setDurability(await navigator.storage.persist() ? 'granted' : 'not-granted'); }
    catch { setDurability('unavailable'); }
  }
  function activate(next: ProjectPackage, saved: boolean) {
    setDocument(next); setDraft(draftOf(next));
    setCheckpoint(saved ? next.project.revisionId : null);
  }
  function updateDraft(update: Partial<ProjectDraft>) {
    setDraft(previous => previous ? { ...previous, ...update } : previous);
    setNotice(null);
  }
  function requestNavigation(action: () => void, label: string) {
    if (busy) return;
    if (dirty) { setError(null); setNavigation({ action, label }); }
    else action();
  }
  function goHome() {
    setDocument(null); setDraft(null); setCheckpoint(null); setError(null); setNotice(null);
    void refreshProjects();
  }
  function newProject() {
    goHome();
    window.requestAnimationFrame(() => createInput.current?.focus());
  }
  async function save(): Promise<ProjectPackage | null> {
    if (!document || !draft || !library || busy) return null;
    if (!dirty) return document;
    setBusy('Saving project'); setError(null); setNotice(null);
    try {
      const edited = isDirty(document, draft) ? applyDraft(document, draft) : document;
      const next = checkpoint === null
        ? { ...edited, project: { ...edited.project, parentRevisionId: null } }
        : edited;
      await repository.save(next, library.catalog, checkpoint);
      activate(next, true);
      setNotice('Saved in this browser. Export a package for a backup.');
      await refreshProjects();
      void requestDurability();
      return next;
    } catch (cause) { setError(messageOf(cause)); return null; }
    finally { setBusy(null); }
  }
  async function create(event: FormEvent) {
    event.preventDefault();
    if (!library || busy) return;
    setBusy('Creating project'); setError(null); setNotice(null);
    let next: ProjectPackage | null = null;
    try {
      next = createProject(library, newProjectName, newGarmentName);
      await repository.save(next, library.catalog, null);
      activate(next, true); setNewProjectName('');
      setNotice('Project created and saved in this browser.');
      await refreshProjects(); void requestDurability();
    } catch (cause) {
      if (next) activate(next, false);
      setError(messageOf(cause));
    } finally { setBusy(null); }
  }
  async function openProject(id: string) {
    if (!library || busy) return;
    setBusy('Opening project'); setError(null); setNotice(null);
    try { activate(await repository.open(id, library.catalog), true); }
    catch (cause) { setError(messageOf(cause)); }
    finally { setBusy(null); }
  }
  async function importProject(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]; event.target.value = '';
    if (!file || !library || busy) return;
    setBusy('Checking and importing package'); setError(null); setNotice(null);
    let next: ProjectPackage | null = null;
    try {
      next = forkImported(await readPackage(file, library.catalog));
      await repository.save(next, library.catalog, null);
      activate(next, true);
      setNotice('Imported as a separate project. The original is unchanged; garment revision identity is preserved.');
      await refreshProjects(); void requestDurability();
    } catch (cause) {
      if (next) activate(next, false);
      setError(messageOf(cause));
    } finally { setBusy(null); }
  }
  async function downloadProject() {
    if (!library || !document || busy) return;
    const saved = dirty ? await save() : document;
    if (!saved) return;
    setBusy('Preparing export'); setError(null);
    try {
      const blob = await exportPackage(saved, library.catalog);
      const url = URL.createObjectURL(blob);
      const link = window.document.createElement('a');
      link.href = url;
      link.download = `${saved.project.name.replace(/[^a-z0-9_-]+/gi, '-').slice(0, 80) || 'onyou-project'}.onyou.json`;
      link.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
      setNotice('Package download started. Keep the file outside browser storage as your backup.');
    } catch (cause) { setError(messageOf(cause)); }
    finally { setBusy(null); }
  }
  async function saveAndContinue() {
    const pending = navigation;
    if (await save()) { setNavigation(null); pending?.action(); }
  }

  const revision = document ? currentRevision(document) : null;
  const previewRevision = revision && draft ? { ...revision, name: draft.garmentName.trim() || revision.name, visualMaterial: { color: draft.color } } : null;
  const selectedModel = library?.catalog.fitModels.find(model => model.id === draft?.fitModelRevisionId);
  const revisionNumber = document && revision ? document.revisions.findIndex(item => item.id === revision.id) + 1 : 0;
  const controlsDisabled = !!busy;

  return <>
    <a className="skip-link" href="#main">Skip to workspace</a>
    <header className="app-header">
      <button className="wordmark" onClick={() => requestNavigation(goHome, 'returning to projects')} disabled={controlsDisabled} aria-label="On You Studio projects">ON YOU <span>Studio</span></button>
      <span className="local-badge"><span aria-hidden="true">●</span> Local workspace</span>
      <div className="header-actions">
        {document && <button onClick={() => requestNavigation(goHome, 'returning to projects')} disabled={controlsDisabled}>Projects</button>}
        <button onClick={() => requestNavigation(() => importInput.current?.click(), 'importing another project')} disabled={!library || controlsDisabled}>Import project</button>
        {document && <button onClick={() => requestNavigation(newProject, 'starting another project')} disabled={controlsDisabled}>New project</button>}
      </div>
      <input ref={importInput} type="file" accept=".json,.onyou.json,application/json" onChange={event => void importProject(event)} className="file-input" aria-label="Import On You project package" tabIndex={-1} />
    </header>

    {(error || notice || busy) && <div className={`message-bar ${error ? 'error' : ''}`}>
      {error ? <p role="alert">{error}</p> : <p role="status">{busy ? `${busy}…` : notice}</p>}
      {!busy && <button aria-label="Dismiss notification" onClick={() => { setError(null); setNotice(null); }}>Dismiss</button>}
    </div>}

    <main id="main" className={document ? 'workspace' : 'project-home'}>
      {!library && <section className="loading-state" aria-live="polite">
        <h1>{libraryError ? 'Preview assets could not be opened' : 'Opening On You Studio'}</h1>
        <p>{libraryError ?? 'Loading and verifying the licensed T-shirt and fitting models…'}</p>
        {libraryError && <button onClick={() => setLoadAttempt(value => value + 1)}>Retry loading assets</button>}
      </section>}
      {library && !document && <>
        <div className="home-title"><div><p className="eyebrow">On You Studio</p><h1>Projects</h1><p>Develop a T-shirt. Keep each revision in your own workspace.</p></div><span className="quiet-label">T-shirt foundation / 01</span></div>
        <div className="home-grid">
          <section className="create-project" aria-labelledby="create-title">
            <p className="eyebrow">Start a project</p><h2 id="create-title">A new T-shirt</h2>
            <p className="section-description">One maintained template, two nonpersonal fitting models.</p>
            <form onSubmit={event => void create(event)}>
              <label>Project name<input ref={createInput} required maxLength={80} value={newProjectName} onChange={event => setNewProjectName(event.target.value)} placeholder="e.g. Eternal — everyday tee" disabled={controlsDisabled} /></label>
              <label>Garment name<input required maxLength={80} value={newGarmentName} onChange={event => setNewGarmentName(event.target.value)} disabled={controlsDisabled} /></label>
              <label>Template<select name="templateId" defaultValue={library.catalog.template.id} disabled={controlsDisabled}><option value={library.catalog.template.id}>{library.catalog.template.name} · v{library.catalog.template.version}</option></select></label>
              <button className="primary full-width" type="submit" disabled={controlsDisabled || !newProjectName.trim() || !newGarmentName.trim()}>Create project</button>
            </form>
            <p className="fine-print">Illustrative geometry. No personal scan or body measurements required.</p>
          </section>
          <section className="saved-projects" aria-labelledby="saved-title">
            <div className="section-heading"><h2 id="saved-title">Saved projects</h2><span>{projects.length} {projects.length === 1 ? 'project' : 'projects'}</span></div>
            {listLoading && <p role="status" className="empty-description">Reading projects from this browser…</p>}
            {listError && <div className="empty-state"><h3>Local storage could not be read</h3><p>Nothing has been removed. Retry, or import an exported project package.</p><button onClick={() => void refreshProjects()} disabled={controlsDisabled}>Retry loading projects</button></div>}
            {!listLoading && !listError && projects.length === 0 && <div className="empty-state"><span className="empty-mark" aria-hidden="true">01</span><h3>Your first project starts here</h3><p>Name your project on the left, then create it. Existing On You packages can be opened with Import project.</p></div>}
            {!listError && projects.length > 0 && <ul className="project-list">{projects.map(project => <li key={project.id}>
              <button className="project-row" onClick={() => void openProject(project.id)} disabled={controlsDisabled}>
                <span className="project-swatch" style={{ backgroundColor: project.color }} aria-hidden="true" />
                <span className="project-details"><strong>{project.name}</strong><span>{project.garmentName} · {project.fitModelName}</span><time dateTime={project.updatedAt}>Modified {new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(project.updatedAt))}</time></span>
                <span className="open-label">Open <span aria-hidden="true">↗</span></span>
              </button>
            </li>)}</ul>}
          </section>
        </div>
      </>}

      {library && document && draft && previewRevision && selectedModel && <>
        <div className="workspace-heading">
          <div><p className="eyebrow">T-shirt development</p><h1 ref={heading} tabIndex={-1}>{draft.projectName || 'Untitled project'}</h1>
            <div className="revision-line"><span>Revision {String(revisionNumber).padStart(2, '0')} <code>{revision!.id.slice(0, 8)}</code></span><span className={dirty ? 'save-state unsaved' : 'save-state'}>{dirty ? 'Unsaved changes' : 'Saved locally'}</span></div>
          </div>
          <div className="workspace-actions">
            {projects.length > 1 && <label className="switch-project">Switch project<select aria-label="Switch project" value={document.project.id} disabled={controlsDisabled} onChange={event => { const id = event.target.value; requestNavigation(() => void openProject(id), 'switching projects'); }}>
              {!projects.some(project => project.id === document.project.id) && <option value={document.project.id}>{document.project.name} (unsaved)</option>}
              {projects.map(project => <option key={project.id} value={project.id}>{project.name} · {project.id.slice(0, 4)}</option>)}
            </select></label>}
            <button onClick={() => void downloadProject()} disabled={controlsDisabled}>{dirty ? 'Save & export' : 'Export package'}</button>
            <button className="primary" onClick={() => void save()} disabled={controlsDisabled || !dirty}>Save project</button>
          </div>
        </div>
        <div className="design-layout">
          <aside className="garment-controls" aria-label="Project and garment controls">
            <section><p className="eyebrow">Project</p><label>Project name<input maxLength={80} value={draft.projectName} onChange={event => updateDraft({ projectName: event.target.value })} disabled={controlsDisabled} /></label></section>
            <section><p className="eyebrow">Garment</p>
              <label>Garment name<input maxLength={80} value={draft.garmentName} onChange={event => updateDraft({ garmentName: event.target.value })} disabled={controlsDisabled} /></label>
              <label>Template<span className="template-value">{library.catalog.template.name}</span></label>
              <p className="field-note">v{previewRevision.templateVersion} · illustrative template</p>
              <fieldset className="color-field"><legend>Garment color</legend><div className="color-swatches">{COLORS.map(color => <button key={color.value} className="color-swatch" type="button" aria-label={color.name} aria-pressed={draft.color.toLowerCase() === color.value} style={{ backgroundColor: color.value }} onClick={() => updateDraft({ color: color.value })} disabled={controlsDisabled}><span className="sr-only">{color.name}</span></button>)}</div>
                <label className="custom-color">Custom color<input type="color" aria-label="Custom garment color" value={draft.color} onChange={event => updateDraft({ color: event.target.value })} disabled={controlsDisabled} /><code>{draft.color.toUpperCase()}</code></label>
              </fieldset>
            </section>
            <section><p className="eyebrow">Fitting reference</p><label>Fitting model<select aria-label="Fitting model" value={draft.fitModelRevisionId} onChange={event => updateDraft({ fitModelRevisionId: event.target.value })} disabled={controlsDisabled}>{library.catalog.fitModels.map(model => <option key={model.id} value={model.id}>{model.name}</option>)}</select></label><p className="field-note">{selectedModel.heightM.toFixed(2)} m authored height. A standardized nonpersonal model, not a population percentile or personal scan.</p></section>
            <div className="scope-note"><strong>Appearance, not specifications</strong><p>Color changes the preview material. Dimensions, pattern pieces and size grading are not available in this foundation.</p></div>
          </aside>
          <section className="design-canvas" aria-label="Garment design workspace">
            <div className="canvas-toolbar"><span className="canvas-title">{draft.garmentName || 'Untitled garment'}</span><div className="segmented-control" role="group" aria-label="Preview layout">{(['split', '2d', '3d'] as PreviewView[]).map(view => <button key={view} aria-pressed={draft.previewView === view} onClick={() => updateDraft({ previewView: view })} disabled={controlsDisabled}>{view === 'split' ? '2D + 3D' : view.toUpperCase()}</button>)}</div></div>
            <div className={`preview-grid ${draft.previewView}`}>
              {draft.previewView !== '3d' && <GarmentDrawing revision={previewRevision} />}
              {draft.previewView !== '2d' && <GarmentViewer revision={previewRevision} model={selectedModel} meshes={library.meshes} />}
            </div>
            <div className="preview-limits"><span className="status-dot" aria-hidden="true" /><p><strong>Illustrative preview.</strong> The shirt is an authored shell adapted to each reference model, not a simulated size change. No cloth physics, collision-based fit, pressure or sizing prediction. The 2D outline is not cut-ready.</p></div>
          </section>
        </div>
      </>}
    </main>
    <footer className="storage-footer"><div><strong>Stored only in this browser</strong><span>Browser data can be cleared or lost. Exported packages are your backup. No account, upload or cloud sync.</span></div>
      {durability === 'granted' ? <span className="durability-status">Durable storage granted · still export backups</span> : durability === 'unavailable' ? <span className="durability-status">Durable storage unavailable</span> : <button onClick={() => void requestDurability()} disabled={controlsDisabled}>Request durable storage</button>}
    </footer>
    {navigation && <UnsavedDialog navigation={navigation} busy={!!busy} error={error} onSave={() => void saveAndContinue()} onDiscard={() => { const next = navigation; setNavigation(null); next.action(); }} onCancel={() => setNavigation(null)} />}
  </>;
}
