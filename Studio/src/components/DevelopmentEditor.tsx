import { useEffect, useId, useState } from 'react';
import type { KeyboardEvent } from 'react';
import type { GarmentRevision, ParametricGarmentRevision, ProjectDraft } from '../domain/types';
import type { ComparisonSelection, DevelopmentState, DisplayUnit, MeasurementId } from '../domain/development-types';
import { addSize, removeSize, renameSize, setBaseSize, setGradeDelta, setMeasurement, setTolerance } from '../domain/development';
import { POMS } from '../patterns/generator';
import { fromDisplay, toDisplay } from '../patterns/units';

export type SpecificationExport = 'csv' | 'json' | 'svg';
const TABS = [
  { id: 'specifications', label: 'Measurements' }, { id: 'sizes', label: 'Size chart & grading' },
  { id: 'comparison', label: 'Compare & history' }, { id: 'exports', label: 'Specification exports' },
] as const;

function NumericField({ label, valueM, unit, onCommit, onProblem, problemKey, resetKey, onFocus, optional = false, disabled = false, minimumM, maximumM }: {
  label: string; valueM: number | null; unit: DisplayUnit; onCommit: (value: number | null) => void;
  onProblem: (key: string, problem: string | null) => void; problemKey: string; onFocus?: () => void;
  optional?: boolean; disabled?: boolean; minimumM?: number; maximumM?: number; resetKey: string;
}) {
  const [raw, setRaw] = useState(valueM === null ? '' : String(Number(toDisplay(valueM, unit).toFixed(6))));
  const [error, setError] = useState<string | null>(null);
  const errorId = useId();
  useEffect(() => {
    setRaw(valueM === null ? '' : String(Number(toDisplay(valueM, unit).toFixed(6))));
    setError(null); onProblem(problemKey, null);
  }, [valueM, unit, problemKey, resetKey]);
  useEffect(() => () => onProblem(problemKey, null), [problemKey]);
  return <label className={`numeric-field ${error ? 'invalid' : ''}`}>
    <span>{label}</span>
    <input type="number" inputMode="decimal" aria-label={label} value={raw} step="any" disabled={disabled}
      min={minimumM === undefined ? undefined : toDisplay(minimumM, unit)} max={maximumM === undefined ? undefined : toDisplay(maximumM, unit)}
      placeholder={optional ? 'Not set' : undefined} aria-invalid={!!error} aria-describedby={error ? errorId : undefined} onFocus={onFocus}
      onChange={event => {
        const next = event.target.value; setRaw(next);
        try {
          if (!next.trim() && !optional) throw new Error('Enter a finite measurement. The previous valid geometry is retained.');
          const value = !next.trim() && optional ? null : fromDisplay(Number(next), unit);
          if (value !== null && !Number.isFinite(value)) throw new Error('Enter a finite measurement.');
          if (value !== null && minimumM !== undefined && value < minimumM) throw new Error(`Minimum ${toDisplay(minimumM, unit)} ${unit}.`);
          if (value !== null && maximumM !== undefined && value > maximumM) throw new Error(`Maximum ${toDisplay(maximumM, unit)} ${unit}.`);
          onCommit(value); setError(null); onProblem(problemKey, null);
        } catch (cause) {
          const problem = cause instanceof Error ? cause.message : 'Unsupported measurement.';
          setError(problem); onProblem(problemKey, `${label}: ${problem}`);
        }
      }} />
    {error && <small id={errorId}>{error}</small>}
  </label>;
}

export interface DevelopmentEditorProps {
  revision: ParametricGarmentRevision;
  acknowledgedRevisionId: string;
  history: GarmentRevision[];
  selectedSizeId: string;
  unit: DisplayUnit;
  comparison: ComparisonSelection | null;
  focusedPom: MeasurementId;
  disabled: boolean;
  onChange: (update: Partial<ProjectDraft>) => void;
  onPomFocus: (id: MeasurementId) => void;
  onInvalidChange: (invalid: boolean) => void;
  onRestore: (revisionId: string) => void;
  onExport: (kind: SpecificationExport) => void;
}

export function DevelopmentEditor({ revision, acknowledgedRevisionId, history, selectedSizeId, unit, comparison, focusedPom, disabled, onChange, onPomFocus, onInvalidChange, onRestore, onExport }: DevelopmentEditorProps) {
  const [tab, setTab] = useState<typeof TABS[number]['id']>('specifications');
  const [problems, setProblems] = useState<Record<string, string>>({});
  const [operationError, setOperationError] = useState<string | null>(null);
  const [newLabel, setNewLabel] = useState('');
  const state = revision.development;
  const size = state.sizeSet.sizes.find(item => item.id === selectedSizeId) ?? state.sizeSet.sizes[0];
  const [labelDraft, setLabelDraft] = useState(size.label);
  const base = state.sizeSet.sizes.find(item => item.id === state.sizeSet.baseSizeId)!;
  const rule = state.sizeSet.gradeRules.find(item => item.toSizeId === size.id);
  const focused = POMS.find(pom => pom.id === focusedPom) ?? POMS[0];
  const otherRevision = comparison?.revisionId === revision.id ? revision : history.find(item => item.id === comparison?.revisionId);
  const otherSize = otherRevision?.schemaVersion === 2 ? otherRevision.development.sizeSet.sizes.find(item => item.id === comparison?.sizeId) : undefined;
  const instanceId = useId();

  useEffect(() => { setLabelDraft(size.label); }, [size.id, size.label]);
  useEffect(() => { setProblems({}); setOperationError(null); setLabelDraft(size.label); }, [acknowledgedRevisionId]);
  useEffect(() => { onInvalidChange(Object.keys(problems).length > 0); }, [problems]);
  useEffect(() => () => onInvalidChange(false), []);
  function fieldProblem(key: string, problem: string | null) {
    setProblems(previous => {
      if ((previous[key] ?? null) === problem) return previous;
      const next = { ...previous };
      if (problem === null) delete next[key]; else next[key] = problem;
      return next;
    });
  }
  function transact(operation: () => DevelopmentState, selectNew = false) {
    try {
      const next = operation();
      onChange({ development: next, ...(selectNew ? { selectedSizeId: next.sizeSet.sizes.at(-1)!.id } : {}) });
      setOperationError(null);
      return true;
    } catch (cause) { setOperationError(cause instanceof Error ? cause.message : 'The requested size change is unsupported.'); return false; }
  }
  function tabKeys(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    const next = event.key === 'ArrowRight' ? (index + 1) % TABS.length : event.key === 'ArrowLeft' ? (index + TABS.length - 1) % TABS.length : event.key === 'Home' ? 0 : event.key === 'End' ? TABS.length - 1 : -1;
    if (next < 0) return;
    event.preventDefault(); setTab(TABS[next].id);
    document.getElementById(`${instanceId}-tab-${TABS[next].id}`)?.focus();
  }
  function compareWith(revisionId: string) {
    const target = revisionId === revision.id ? revision : history.find(item => item.id === revisionId);
    if (!target) { onChange({ comparison: null }); return; }
    const targetSize = target.schemaVersion === 2 ? target.development.sizeSet.sizes.find(item => item.id === size.id) ?? target.development.sizeSet.sizes[0] : null;
    onChange({ comparison: { revisionId: target.id, sizeId: targetSize?.id ?? null } });
  }

  return <section className="development-editor" aria-label="Garment development controls">
    <div className="development-topline"><span className="provisional-label">Provisional authored construction</span><span>5 pieces · meters internally · no cloth simulation</span></div>
    <div className="size-preview-controls">
      <label>Preview size<select aria-label="Preview size" value={size.id} disabled={disabled} onChange={event => onChange({ selectedSizeId: event.target.value })}>{state.sizeSet.sizes.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
      <label>Display units<select aria-label="Display units" value={unit} disabled={disabled} onChange={event => onChange({ displayUnit: event.target.value as DisplayUnit })}><option value="cm">Centimeters (cm)</option><option value="in">Inches (in)</option></select></label>
      <span className="size-source-note">Garment specifications, not personal body measurements.</span>
    </div>
    <div className="development-tabs" role="tablist" aria-label="Garment development sections">{TABS.map((item, index) => <button key={item.id} id={`${instanceId}-tab-${item.id}`} role="tab" aria-selected={tab === item.id} aria-controls={`${instanceId}-panel-${item.id}`} tabIndex={tab === item.id ? 0 : -1} onKeyDown={event => tabKeys(event, index)} onClick={() => setTab(item.id)}>{item.label}</button>)}</div>
    {Object.keys(problems).length > 0 && <p className="geometry-error" role="alert">Invalid values have not changed the last valid geometry. Fix the highlighted fields before saving: {Object.values(problems).join(' ')}</p>}
    {operationError && <p className="geometry-error" role="alert">{operationError}</p>}

    <div id={`${instanceId}-panel-specifications`} role="tabpanel" aria-labelledby={`${instanceId}-tab-specifications`} hidden={tab !== 'specifications'}>
      <div className="pom-grid">{POMS.map(pom => <NumericField key={`${size.id}-${pom.id}`} label={`${pom.name} (${unit})`} valueM={size.specification.values[pom.id]} unit={unit} disabled={disabled} minimumM={pom.rangeM[0]} maximumM={pom.rangeM[1]}
        problemKey={`measure-${size.id}-${pom.id}`} resetKey={acknowledgedRevisionId} onProblem={fieldProblem} onFocus={() => onPomFocus(pom.id)} onCommit={value => onChange({ development: setMeasurement(state, size.id, pom.id, value!) })} />)}</div>
      <div className="measurement-definition"><div><strong>{focused.name}</strong><p>{focused.definition}</p><code>{focused.endpoints.pieceId}: {focused.endpoints.startPointId} → {focused.endpoints.endPointId}</code></div>
        <NumericField label={`${focused.name} tolerance (${unit})`} valueM={size.specification.tolerancesM[focused.id] ?? null} unit={unit} optional disabled={disabled} minimumM={0} maximumM={0.1}
          problemKey={`tolerance-${size.id}-${focused.id}`} resetKey={acknowledgedRevisionId} onProblem={fieldProblem} onCommit={value => onChange({ development: setTolerance(state, size.id, focused.id, value) })} />
      </div>
      <p className="development-help">Focus a value to identify its endpoints in the drawing. The piece view offers direct handles for body length and chest width. Changing the base size reapplies each size's explicit per-measurement differences; unrelated measurements are not scaled.</p>
    </div>

    <div id={`${instanceId}-panel-sizes`} role="tabpanel" aria-labelledby={`${instanceId}-tab-sizes`} hidden={tab !== 'sizes'}>
      <div className="size-actions">
        <label>Base size<select aria-label="Base size" value={state.sizeSet.baseSizeId} disabled={disabled} onChange={event => transact(() => setBaseSize(state, event.target.value))}>{state.sizeSet.sizes.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
        <form onSubmit={event => { event.preventDefault(); if (transact(() => addSize(state, newLabel), true)) setNewLabel(''); }}><label>New size label<input aria-label="New size label" maxLength={24} value={newLabel} disabled={disabled} onChange={event => setNewLabel(event.target.value)} placeholder="Your brand's label" /></label><button type="submit" disabled={disabled || !newLabel.trim() || state.sizeSet.sizes.length >= 8}>Add size</button></form>
      </div>
      <div className="size-chart-scroll"><table className="specification-table"><caption>Finished garment measurements · {unit} · base: {base.label}</caption><thead><tr><th scope="col">Point of measure</th>{state.sizeSet.sizes.map(item => <th key={item.id} scope="col">{item.label}{item.id === base.id ? ' · base' : ''}</th>)}</tr></thead><tbody>{POMS.map(pom => <tr key={pom.id}><th scope="row">{pom.name}</th>{state.sizeSet.sizes.map(item => <td key={item.id}><NumericField label={`${item.label} · ${pom.name} (${unit})`} valueM={item.specification.values[pom.id]} unit={unit} disabled={disabled} minimumM={pom.rangeM[0]} maximumM={pom.rangeM[1]}
        problemKey={`chart-${item.id}-${pom.id}`} resetKey={acknowledgedRevisionId} onProblem={fieldProblem} onCommit={value => onChange({ development: setMeasurement(state, item.id, pom.id, value!) })} /></td>)}</tr>)}</tbody></table></div>
      <div className="selected-size-actions"><label>Selected size label<input aria-label="Selected size label" maxLength={24} disabled={disabled} value={labelDraft} onChange={event => setLabelDraft(event.target.value)} /></label><button disabled={disabled || labelDraft === size.label} onClick={() => transact(() => renameSize(state, size.id, labelDraft))}>Rename size</button><button disabled={disabled || size.id === base.id || state.sizeSet.sizes.length < 2} onClick={() => { transact(() => removeSize(state, size.id)); onChange({ selectedSizeId: base.id }); }}>Remove selected size</button></div>
      {rule ? <div className="grade-editor"><h3>Grade differences: {base.label} → {size.label}</h3><p>Each difference is independent. Zero keeps that measurement unchanged. Editing a size's absolute value updates its corresponding difference.</p><div className="pom-grid">{POMS.map(pom => <NumericField key={`${rule.id}-${pom.id}`} label={`Grade ${pom.name} (${unit})`} valueM={rule.deltasM[pom.id]} unit={unit} disabled={disabled}
        problemKey={`grade-${size.id}-${pom.id}`} resetKey={acknowledgedRevisionId} onProblem={fieldProblem} onCommit={value => onChange({ development: setGradeDelta(state, size.id, pom.id, value!) })} />)}</div></div> : <p className="development-help">This is the base size. Select another preview size to edit its independent grading differences.</p>}
    </div>

    <div id={`${instanceId}-panel-comparison`} role="tabpanel" aria-labelledby={`${instanceId}-tab-comparison`} hidden={tab !== 'comparison'}>
      <div className="comparison-controls"><label>Compare revision<select aria-label="Compare revision" value={comparison?.revisionId ?? ''} disabled={disabled} onChange={event => compareWith(event.target.value)}><option value="">No comparison</option>{history.map((item, index) => <option key={item.id} value={item.id}>Revision {String(index + 1).padStart(2, '0')} · {item.name} · {item.id.slice(0, 8)}</option>)}</select></label>
        {otherRevision?.schemaVersion === 2 && <label>Compare size<select aria-label="Compare size" value={otherSize?.id ?? ''} disabled={disabled} onChange={event => onChange({ comparison: { revisionId: otherRevision.id, sizeId: event.target.value } })}>{otherRevision.development.sizeSet.sizes.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>}
        <button disabled={disabled || state.sizeSet.sizes.length < 2} onClick={() => { const target = state.sizeSet.sizes.find(item => item.id !== size.id)!; onChange({ comparison: { revisionId: revision.id, sizeId: target.id } }); }}>Compare another size</button>
        <button disabled={disabled || !otherRevision || otherRevision.id === revision.id} onClick={() => onRestore(otherRevision!.id)}>Restore compared design as new revision</button>
      </div>
      {otherRevision && <div className="comparison-identity"><span className="current-key">Current: {size.label} · {revision.id.slice(0, 8)}{history.some(item => item.id === revision.id) ? ' + unsaved edits if any' : ''}</span><span className="comparison-key">Compared: {otherSize?.label ?? 'legacy illustration'} · {otherRevision.id.slice(0, 8)}</span></div>}
      {otherSize ? <div className="size-chart-scroll"><table className="specification-table comparison-table"><caption>Current minus compared · {unit} · same fitting model and camera</caption><thead><tr><th scope="col">Measurement</th><th scope="col">Current</th><th scope="col">Compared</th><th scope="col">Difference</th></tr></thead><tbody>{POMS.map(pom => { const value = toDisplay(size.specification.values[pom.id], unit); const before = toDisplay(otherSize.specification.values[pom.id], unit); return <tr key={pom.id}><th scope="row">{pom.name}</th><td>{value.toFixed(3)}</td><td>{before.toFixed(3)}</td><td>{value - before > 0 ? '+' : ''}{(value - before).toFixed(3)}</td></tr>; })}</tbody></table></div> : <p className="development-help">{otherRevision ? 'This legacy revision contains an authored illustration, not historical garment measurements. Its appearance can be inspected in the overlay or restored without inventing dimensions.' : 'Choose a saved revision or another size. Dashed outlines and 3D wire geometry share the current model, anchor and camera; no automatic camera rescaling.'}</p>}
      {otherRevision && otherRevision.schemaVersion === 2 && <div className="size-chart-scroll"><table className="specification-table"><caption>Size-chart comparison · matching stable size identity</caption><thead><tr><th scope="col">Current size</th><th scope="col">Compared size</th>{POMS.map(pom => <th key={pom.id} scope="col">Δ {pom.name} ({unit})</th>)}</tr></thead><tbody>{state.sizeSet.sizes.map(item => { const old = otherRevision.development.sizeSet.sizes.find(candidate => candidate.id === item.id); return <tr key={item.id}><th scope="row">{item.label}</th><td>{old?.label ?? 'Not present'}</td>{POMS.map(pom => <td key={pom.id}>{old ? toDisplay(item.specification.values[pom.id] - old.specification.values[pom.id], unit).toFixed(3) : '—'}</td>)}</tr>; })}</tbody></table></div>}
      <ol className="revision-history" aria-label="Saved garment revisions">{history.map((item, index) => <li key={item.id}><button disabled={disabled} onClick={() => compareWith(item.id)}>Revision {String(index + 1).padStart(2, '0')} · {item.id.slice(0, 8)}</button><span>{item.name} · {item.schemaVersion === 2 ? `${item.development.sizeSet.sizes.length} sizes` : 'Goal 2 illustration'}</span><time dateTime={item.createdAt}>{new Date(item.createdAt).toLocaleString()}</time></li>)}</ol>
    </div>

    <div id={`${instanceId}-panel-exports`} role="tabpanel" aria-labelledby={`${instanceId}-tab-exports`} hidden={tab !== 'exports'}>
      <h3>Revision-bound preliminary specifications</h3><p className="development-help">Exports save the current valid draft first. CSV includes every size, endpoint definitions, units, tolerances and status. JSON contains supported design records and actual pattern geometry. SVG exports the selected size at declared physical scale, independently of screen zoom.</p>
      <div className="specification-export-actions"><button disabled={disabled || Object.keys(problems).length > 0} onClick={() => onExport('csv')}>Export specification CSV</button><button disabled={disabled || Object.keys(problems).length > 0} onClick={() => onExport('json')}>Export specification JSON</button><button disabled={disabled || Object.keys(problems).length > 0} onClick={() => onExport('svg')}>Export pattern SVG</button></div>
      <p className="development-help">Provisional construction requiring designer review and physical sampling. Not production-approved, DXF/AAMA/ASTM CAD, a complete tech pack, or an optimized fabric marker.</p>
    </div>
  </section>;
}
