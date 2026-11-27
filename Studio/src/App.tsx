import { useEffect, useMemo, useRef, useState } from 'react';
import type { ChangeEvent, FormEvent } from 'react';
import { GarmentDrawing } from './components/GarmentDrawing';
import { GarmentViewer } from './components/GarmentViewer';
import { DevelopmentEditor, type SpecificationExport } from './components/DevelopmentEditor';
import { PatternDrawing } from './components/PatternDrawing';
import { loadLibrary } from './domain/library';
import { exportPackage, readPackage } from './domain/packages';
import { applyDraft, createProject, currentRevision, draftOf, forkImported, isDirty, restoreRevision, upgradeProject } from './domain/projects';
import { ProjectRepository } from './domain/repository';
import type { GarmentRevision, Library, PreviewView, ProjectDraft, ProjectPackage, ProjectSummary } from './domain/types';
import type { MeasurementId } from './domain/development-types';
import { setMeasurement } from './domain/development';
import { patternSvg, specificationCsv, specificationJson } from './domain/specification-exports';
import { POMS } from './patterns/generator';

const COLORS = [
  { name: 'Chalk', value: '#e8e5dc' }, { name: 'Ink', value: '#273342' },
  { name: 'Moss', value: '#677361' }, { name: 'Clay', value: '#a56954' },
  { name: 'Charcoal', value: '#353b3a' },
];
const messageOf = (error: unknown) => error instanceof Error ? error.message : 'The operation failed. Your previous saved project has not been replaced.';
type Navigation = { label: string; action: (saved?: ProjectPackage) => void };

function UnsavedDialog({ navigation, busy, error, cannotSave, onSave, onDiscard, onCancel }: {
  navigation: Navigation; busy: boolean; error: string | null; cannotSave: boolean;
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
      <button className="primary" onClick={onSave} disabled={busy || cannotSave}>{busy ? 'Saving…' : 'Save and continue'}</button>
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
  const [createTemplate, setCreateTemplate] = useState<'legacy' | 'parametric'>('parametric');
  const [formInvalid, setFormInvalid] = useState(false);
  const [focusedPom, setFocusedPom] = useState<MeasurementId>('bodyLength');
  const importInput = useRef<HTMLInputElement>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const createInput = useRef<HTMLInputElement>(null);
  const dirty = !!(document && draft && (formInvalid || checkpoint === null || isDirty(document, draft)));

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
    setFormInvalid(false);
    setCheckpoint(saved ? next.project.revisionId : null);
  }
  function updateDraft(update: Partial<ProjectDraft>) {
    setDraft(previous => previous ? { ...previous, ...update } : previous);
    setNotice(null);
  }
  function requestNavigation(action: Navigation['action'], label: string) {
    if (busy) return;
    if (dirty) { setError(null); setNavigation({ action, label }); }
    else action();
  }
  function goHome() {
    setDocument(null); setDraft(null); setCheckpoint(null); setError(null); setNotice(null);
    setFormInvalid(false);
    void refreshProjects();
  }
  function newProject() {
    goHome();
    window.requestAnimationFrame(() => createInput.current?.focus());
  }
  async function save(): Promise<ProjectPackage | null> {
    if (!document || !draft || !library || busy) return null;
    if (formInvalid) { setError('Fix the invalid measurement entries before saving. The previous acknowledged save is unchanged.'); return null; }
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
      next = createProject(library, newProjectName, newGarmentName, createTemplate);
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
      downloadBlob(blob, `${saved.project.name}.onyou.json`);
      setNotice('Package download started. Keep the file outside browser storage as your backup.');
    } catch (cause) { setError(messageOf(cause)); }
    finally { setBusy(null); }
  }

  function downloadBlob(blob: Blob, filename: string) {
    const url = URL.createObjectURL(blob);
    const link = window.document.createElement('a');
    link.href = url;
    link.download = filename.replace(/[^a-z0-9_.-]+/gi, '-').slice(0, 180) || 'onyou-export.json';
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  async function exportSpecifications(kind: SpecificationExport) {
    if (!document || !library || busy || formInvalid) return;
    const saved = dirty ? await save() : document;
    if (!saved) return;
    setBusy('Exporting specifications'); setError(null);
    try {
      const revision = currentRevision(saved);
      if (revision.schemaVersion !== 2) throw new Error('This legacy illustration has no garment specifications. Upgrade explicitly first.');
      const text = kind === 'csv' ? specificationCsv(revision, saved.project.displayUnit ?? 'cm')
        : kind === 'json' ? specificationJson(revision)
        : patternSvg(revision, saved.project.selectedSizeId ?? revision.development.sizeSet.baseSizeId);
      const mime = kind === 'csv' ? 'text/csv;charset=utf-8' : kind === 'svg' ? 'image/svg+xml' : 'application/json';
      downloadBlob(new Blob([text], { type: mime }), `${saved.project.name}-${revision.id.slice(0, 8)}-specifications.${kind}`);
      setNotice('Preliminary specification download started. Designer review and physical sampling remain necessary.');
    } catch (cause) { setError(messageOf(cause)); }
    finally { setBusy(null); }
  }
  async function reviseProject(kind: 'upgrade' | 'restore', source: ProjectPackage, expectedRevisionId: string | null, revisionId?: string) {
    if (!library || busy) return;
    setBusy(kind === 'upgrade' ? 'Upgrading to parametric construction' : 'Restoring design as a new revision');
    setError(null); setNotice(null);
    try {
      const edited = kind === 'upgrade' ? upgradeProject(source) : restoreRevision(source, revisionId!);
      const next = expectedRevisionId === null ? { ...edited, project: { ...edited.project, parentRevisionId: null } } : edited;
      await repository.save(next, library.catalog, expectedRevisionId);
      activate(next, true);
      setNotice(kind === 'upgrade' ? 'Parametric revision saved with explicitly authored defaults. Original illustration and history are unchanged.'
        : 'Earlier design restored as a new revision. Historical revisions are unchanged.');
      await refreshProjects();
    } catch (cause) { setError(messageOf(cause)); }
    finally { setBusy(null); }
  }
  function requestRevision(kind: 'upgrade' | 'restore', revisionId?: string) {
    if (!document) return;
    requestNavigation(saved => void reviseProject(kind, saved ?? document, saved?.project.revisionId ?? checkpoint, revisionId), kind === 'upgrade' ? 'upgrading this illustration' : 'restoring an earlier design');
  }
  function focusMeasurement(id: MeasurementId) {
    setFocusedPom(id);
    const definition = POMS.find(pom => pom.id === id)!;
    updateDraft({ patternView: `piece-${definition.endpoints.pieceId}` });
  }
  function dragMeasurement(id: MeasurementId, valueM: number) {
    if (!draft?.development) return;
    try {
      updateDraft({ development: setMeasurement(draft.development, draft.selectedSizeId ?? draft.development.sizeSet.baseSizeId, id, valueM) });
      setError(null);
    } catch (cause) { setError(messageOf(cause)); }
  }
  async function saveAndContinue() {
    const pending = navigation;
    const saved = await save();
    if (saved) { setNavigation(null); pending?.action(saved); }
  }

  const revision = document ? currentRevision(document) : null;
  const previewRevision = useMemo<GarmentRevision | null>(() => {
    if (!revision || !draft) return null;
    const common = { name: draft.garmentName.trim() || revision.name, visualMaterial: { color: draft.color } };
    return revision.schemaVersion === 2 ? { ...revision, ...common, development: draft.development ?? revision.development } : { ...revision, ...common };
  }, [revision, draft?.garmentName, draft?.color, draft?.development]);
  const selectedSizeId = draft?.selectedSizeId ?? (previewRevision?.schemaVersion === 2 ? previewRevision.development.sizeSet.baseSizeId : null);
  const comparisonId = draft?.comparison?.revisionId ?? '';
  const comparisonRevision = comparisonId ? comparisonId === previewRevision?.id ? previewRevision : document?.revisions.find(item => item.id === comparisonId) : null;
  const comparisonGeometry = comparisonRevision ? { revision: comparisonRevision, sizeId: draft?.comparison?.sizeId ?? (comparisonRevision.schemaVersion === 2 ? comparisonRevision.development.sizeSet.baseSizeId : null) } : null;
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
        <div className="home-title"><div><p className="eyebrow">On You Studio</p><h1>Projects</h1><p>Develop a T-shirt. Keep each revision in your own workspace.</p></div><span className="quiet-label">Garment development / 02</span></div>
        <div className="home-grid">
          <section className="create-project" aria-labelledby="create-title">
            <p className="eyebrow">Start a project</p><h2 id="create-title">A new T-shirt</h2>
            <p className="section-description">Parametric garment development or the original illustration. Two nonpersonal fitting models.</p>
            <form onSubmit={event => void create(event)}>
              <label>Project name<input ref={createInput} required maxLength={80} value={newProjectName} onChange={event => setNewProjectName(event.target.value)} placeholder="e.g. Eternal — everyday tee" disabled={controlsDisabled} /></label>
              <label>Garment name<input required maxLength={80} value={newGarmentName} onChange={event => setNewGarmentName(event.target.value)} disabled={controlsDisabled} /></label>
              <label>Template<select aria-label="Template" name="templateId" value={createTemplate} disabled={controlsDisabled} onChange={event => setCreateTemplate(event.target.value as 'legacy' | 'parametric')}><option value="parametric">Parametric short-sleeve T-shirt · v2</option><option value="legacy">{library.catalog.template.name} · v1 illustration</option></select></label>
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
            <button onClick={() => void downloadProject()} disabled={controlsDisabled || formInvalid}>{dirty ? 'Save & export' : 'Export package'}</button>
            <button className="primary" onClick={() => void save()} disabled={controlsDisabled || formInvalid || !dirty}>Save project</button>
          </div>
        </div>
        <div className={`design-layout ${previewRevision.schemaVersion === 2 ? 'parametric-layout' : ''}`}>
          <aside className="garment-controls" aria-label="Project and garment controls">
            <section><p className="eyebrow">Project</p><label>Project name<input maxLength={80} value={draft.projectName} onChange={event => updateDraft({ projectName: event.target.value })} disabled={controlsDisabled} /></label></section>
            <section><p className="eyebrow">Garment</p>
              <label>Garment name<input maxLength={80} value={draft.garmentName} onChange={event => updateDraft({ garmentName: event.target.value })} disabled={controlsDisabled} /></label>
              <label>Template<span className="template-value">{previewRevision.schemaVersion === 2 ? 'Parametric short-sleeve T-shirt' : library.catalog.template.name}</span></label>
              <p className="field-note">v{previewRevision.templateVersion} · {previewRevision.schemaVersion === 2 ? 'provisional authored construction' : 'original illustrative template'}</p>
              <fieldset className="color-field"><legend>Garment color</legend><div className="color-swatches">{COLORS.map(color => <button key={color.value} className="color-swatch" type="button" aria-label={color.name} aria-pressed={draft.color.toLowerCase() === color.value} style={{ backgroundColor: color.value }} onClick={() => updateDraft({ color: color.value })} disabled={controlsDisabled}><span className="sr-only">{color.name}</span></button>)}</div>
                <label className="custom-color">Custom color<input type="color" aria-label="Custom garment color" value={draft.color} onChange={event => updateDraft({ color: event.target.value })} disabled={controlsDisabled} /><code>{draft.color.toUpperCase()}</code></label>
              </fieldset>
            </section>
            <section><p className="eyebrow">Fitting reference</p><label>Fitting model<select aria-label="Fitting model" value={draft.fitModelRevisionId} onChange={event => updateDraft({ fitModelRevisionId: event.target.value })} disabled={controlsDisabled}>{library.catalog.fitModels.map(model => <option key={model.id} value={model.id}>{model.name}</option>)}</select></label><p className="field-note">{selectedModel.heightM.toFixed(2)} m authored height. A standardized nonpersonal model, not a population percentile or personal scan.</p></section>
            <div className="scope-note">{previewRevision.schemaVersion === 2 ? <><strong>Garment and model are independent</strong><p>Size changes update the garment, not the body. Model selection changes only the reference and rigid garment placement.</p></> : <><strong>Original Goal 2 illustration</strong><p>This revision has no historical garment specifications. Upgrade explicitly to start a provisional parametric design with authored defaults; original revisions remain intact.</p><button onClick={() => requestRevision('upgrade')} disabled={controlsDisabled}>Upgrade to parametric T-shirt</button></>}</div>
            {previewRevision.schemaVersion === 1 && document.revisions.length > 1 && <section className="legacy-revision-inspector"><p className="eyebrow">Saved designs</p><label>Historical design<select aria-label="Historical design" value={comparisonId} disabled={controlsDisabled} onChange={event => { const target=document.revisions.find(item=>item.id===event.target.value); updateDraft({comparison:target?{revisionId:target.id,sizeId:target.schemaVersion===2?target.development.sizeSet.baseSizeId:null}:null}); }}><option value="">No comparison</option>{document.revisions.filter(item => item.id !== revision!.id).map((item, index) => <option key={item.id} value={item.id}>Saved design {index + 1} · {item.name} · {item.id.slice(0, 8)}</option>)}</select></label>{document.schemaVersion===1 && <p className="field-note">Legacy comparison is transient; upgrade explicitly to persist development preview settings.</p>}{comparisonRevision && <><p className="field-note">{comparisonRevision.name} · v{comparisonRevision.templateVersion} · {comparisonRevision.id.slice(0, 8)}. Wire overlay uses the current model and camera. Legacy revisions have no inferred historical measurements.</p><button disabled={controlsDisabled} onClick={() => requestRevision('restore', comparisonRevision.id)}>Restore selected design as new revision</button></>}</section>}
          </aside>
          <section className={`design-canvas${previewRevision.schemaVersion === 2 ? ' parametric-layout' : ''}`} aria-label="Garment design workspace">
            <div className="canvas-toolbar"><span className="canvas-title">{draft.garmentName || 'Untitled garment'}</span><div className="segmented-control" role="group" aria-label="Preview layout">{(['split', '2d', '3d'] as PreviewView[]).map(view => <button key={view} aria-pressed={draft.previewView === view} onClick={() => updateDraft({ previewView: view })} disabled={controlsDisabled}>{view === 'split' ? '2D + 3D' : view.toUpperCase()}</button>)}</div></div>
            {previewRevision.schemaVersion === 2 && <DevelopmentEditor key={document.project.id} revision={previewRevision} acknowledgedRevisionId={document.project.revisionId} history={document.revisions} selectedSizeId={selectedSizeId!} unit={draft.displayUnit ?? 'cm'} comparison={draft.comparison ?? null} focusedPom={focusedPom} disabled={controlsDisabled} onChange={updateDraft} onPomFocus={focusMeasurement} onInvalidChange={setFormInvalid} onRestore={id => requestRevision('restore', id)} onExport={kind => void exportSpecifications(kind)} />}
            <div className={`preview-grid ${draft.previewView}`}>
              {draft.previewView !== '3d' && (previewRevision.schemaVersion === 1 ? <GarmentDrawing revision={previewRevision} /> : <PatternDrawing revision={previewRevision} selectedSizeId={selectedSizeId!} view={draft.patternView ?? 'front'} unit={draft.displayUnit ?? 'cm'} focusedPom={focusedPom} comparison={comparisonGeometry} onView={patternView => updateDraft({ patternView })} onMeasurement={dragMeasurement} disabled={controlsDisabled} />)}
              {draft.previewView !== '2d' && <GarmentViewer revision={previewRevision} model={selectedModel} meshes={library.meshes} selectedSizeId={selectedSizeId} comparison={comparisonGeometry} />}
            </div>
            <div className="preview-limits"><span className="status-dot" aria-hidden="true" /><p><strong>Illustrative preview.</strong> {previewRevision.schemaVersion === 2 ? 'The selected garment size is unchanged across fitting models. Generated patterns and dimensions are provisional authored specifications, not production-approved cutting files. No cloth drape, contact, pressure or fit prediction.' : 'The original shirt shell is adapted to each reference model, not a simulated size change. No cloth physics, collision-based fit, pressure or sizing prediction. The 2D outline is not cut-ready.'}</p></div>
          </section>
        </div>
      </>}
    </main>
    <footer className="storage-footer"><div><strong>Stored only in this browser</strong><span>Browser data can be cleared or lost. Exported packages are your backup. No account, upload or cloud sync.</span></div>
      {durability === 'granted' ? <span className="durability-status">Durable storage granted · still export backups</span> : durability === 'unavailable' ? <span className="durability-status">Durable storage unavailable</span> : <button onClick={() => void requestDurability()} disabled={controlsDisabled}>Request durable storage</button>}
    </footer>
    {navigation && <UnsavedDialog navigation={navigation} busy={!!busy} cannotSave={formInvalid} error={error ?? (formInvalid ? 'Invalid entries cannot be saved. Keep editing or discard these uncommitted entries.' : null)} onSave={() => void saveAndContinue()} onDiscard={() => { const next = navigation; setNavigation(null); next.action(); }} onCancel={() => setNavigation(null)} />}
  </>;
}
