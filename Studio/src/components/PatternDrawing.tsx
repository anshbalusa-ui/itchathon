import { useEffect, useId, useRef, useState } from 'react';
import type { KeyboardEvent, PointerEvent } from 'react';
import type { GarmentRevision, ParametricGarmentRevision } from '../domain/types';
import type { DisplayUnit, MeasurementId, PatternDefinition, PatternPiece, PatternView, PieceId, Vec2 } from '../domain/development-types';
import { flattenPiece, POMS, pointOnEdge, technicalView } from '../patterns/generator';
import { fromDisplay, toDisplay } from '../patterns/units';

interface Frame { x: number; y: number; width: number; height: number }
const PIECE_NAMES: Record<PieceId, string> = { front: 'Front body', back: 'Back body', 'sleeve-left': 'Left sleeve', 'sleeve-right': 'Right sleeve', neckband: 'Neckband' };
function pieceBounds(piece:PatternPiece) {
  const points=piece.cuttingBoundary;
  const minX=Math.min(...points.map(point=>point[0])),maxX=Math.max(...points.map(point=>point[0]));
  const minY=Math.min(...points.map(point=>point[1])),maxY=Math.max(...points.map(point=>point[1]));
  return {width:maxX-minX,height:maxY-minY,centerX:(Math.min(...piece.points.map(point=>point.x))+Math.max(...piece.points.map(point=>point.x)))/2,top:Math.max(...piece.points.map(point=>point.y))};
}

function seamPath(piece: PatternPiece): string {
  const points = new Map(piece.points.map(point => [point.id, point]));
  return piece.edges.map((edge, index) => {
    const from = points.get(edge.from)!, to = points.get(edge.to)!;
    return `${index === 0 ? `M ${from.x} ${from.y} ` : ''}${edge.kind === 'line' ? `L ${to.x} ${to.y}` : `C ${edge.control1.join(' ')} ${edge.control2.join(' ')} ${to.x} ${to.y}`}`;
  }).join(' ') + ' Z';
}

export interface PatternDrawingProps {
  revision: ParametricGarmentRevision;
  selectedSizeId: string;
  view: PatternView;
  unit: DisplayUnit;
  focusedPom: MeasurementId;
  comparison: { revision: GarmentRevision; sizeId: string | null } | null;
  onView: (view: PatternView) => void;
  onMeasurement: (id: MeasurementId, valueM: number) => void;
  disabled: boolean;
}

export function PatternDrawing({ revision, selectedSizeId, view, unit, focusedPom, comparison, onView, onMeasurement, disabled }: PatternDrawingProps) {
  const [allowances, setAllowances] = useState(true);
  const [guides, setGuides] = useState(true);
  const [frame, setFrame] = useState<Frame>({ x: -0.8, y: -0.1, width: 1.6, height: 1.15 });
  const pan = useRef<{ pointer: number; start: DOMPoint; inverse: DOMMatrix; frame: Frame } | null>(null);
  const handle = useRef<{ pointer: number; start: Vec2; centerX: number; inverse: DOMMatrix } | null>(null);
  const titleId = useId();
  const markerId = useId().replaceAll(':', '');
  const pattern = revision.development.patterns.find(item => item.sizeId === selectedSizeId) ?? revision.development.patterns[0];
  const size = revision.development.sizeSet.sizes.find(item => item.id === pattern.sizeId)!;
  const otherPattern = comparison?.revision.schemaVersion === 2 ? comparison.revision.development.patterns.find(item => item.sizeId === comparison.sizeId) : undefined;
  const legacyOutline = comparison?.revision.schemaVersion === 1 ? comparison.revision.drawing.outline : null;
  const legacyTop = legacyOutline ? Math.max(...legacyOutline.map(point => point[1])) : 0;
  const individual = view.startsWith('piece-') ? view.slice(6) as PieceId : null;
  const isTechnical = view === 'front' || view === 'back';
  const visiblePieces = isTechnical ? [] : view === 'pieces' ? pattern.pieces : pattern.pieces.filter(piece => piece.id === individual);
  const focused = POMS.find(pom => pom.id === focusedPom)!;
  const focusedPiece = pattern.pieces.find(piece => piece.id === focused.endpoints.pieceId)!;
  const start = focusedPiece.points.find(point => point.id === focused.endpoints.startPointId)!;
  const end = focusedPiece.points.find(point => point.id === focused.endpoints.endPointId)!;
  const diagramStart = focused.method === 'vertical-projection' ? { x: end.x, y: start.y } : start;
  const diagramEnd = focused.method === 'half-path-length' ? { x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 } : end;
  const fontSize = frame.width * 0.023;

  const allPieces = [...pattern.pieces, ...(otherPattern?.pieces ?? [])];
  const bodyBounds = allPieces.filter(piece => piece.id === 'front' || piece.id === 'back').map(pieceBounds);
  const sleeveBounds = allPieces.filter(piece => piece.id.startsWith('sleeve-')).map(pieceBounds);
  const column = (Math.max(...bodyBounds.map(bounds => bounds.width), ...sleeveBounds.map(bounds => bounds.width)) + 0.18) / 2;
  const sleeveTop = -Math.max(...bodyBounds.map(bounds => bounds.height)) - 0.18;
  const bandTop = sleeveTop - Math.max(...sleeveBounds.map(bounds => bounds.height)) - 0.18;
  function pieceOffset(piece:PatternPiece):Vec2 {
    const bounds=pieceBounds(piece);
    if(view!=='pieces')return [-bounds.centerX,-bounds.top];
    const x=piece.id==='front'||piece.id==='sleeve-left'?-column:piece.id==='neckband'?0:column;
    const y=piece.id.startsWith('sleeve-')?sleeveTop:piece.id==='neckband'?bandTop:0;
    return [x-bounds.centerX,y-bounds.top];
  }
  useEffect(() => { fit(); }, [view]);

  function zoom(factor: number) {
    setFrame(current => {
      const width = Math.max(0.12, Math.min(8, current.width * factor));
      const height = current.height * width / current.width;
      return { x: current.x + (current.width - width) / 2, y: current.y + (current.height - height) / 2, width, height };
    });
  }
  function fit() {
    const points: Vec2[] = [];
    if (isTechnical) {
      for (const outline of technicalView(pattern, view as 'front' | 'back').outlines) points.push(...outline);
      if (otherPattern) for (const outline of technicalView(otherPattern, view as 'front' | 'back').outlines) points.push(...outline);
    } else {
      for (const piece of visiblePieces) {
        const offset = pieceOffset(piece);
        for (const point of piece.cuttingBoundary) points.push([point[0] + offset[0], point[1] + offset[1]]);
        const other = otherPattern?.pieces.find(item => item.id === piece.id);
        if (other) { const comparedOffset=pieceOffset(other); for (const point of other.cuttingBoundary) points.push([point[0]+comparedOffset[0],point[1]+comparedOffset[1]]); }
      }
    }
    if (!points.length) return;
    const minimumX = Math.min(...points.map(point => point[0])), maximumX = Math.max(...points.map(point => point[0]));
    const minimumY = Math.min(...points.map(point => point[1])), maximumY = Math.max(...points.map(point => point[1]));
    setFrame({ x: minimumX - 0.08, y: -maximumY - 0.1, width: maximumX - minimumX + 0.16, height: maximumY - minimumY + 0.22 });
  }
  function drawingKeys(event: KeyboardEvent<SVGSVGElement>) {
    if (event.target !== event.currentTarget) return;
    if (event.key === '+' || event.key === '=') zoom(0.8);
    else if (event.key === '-') zoom(1.25);
    else if (event.key === 'Home') fit();
    else if (event.key.startsWith('Arrow')) setFrame(current => ({ ...current, x: current.x + (event.key === 'ArrowRight' ? 0.08 : event.key === 'ArrowLeft' ? -0.08 : 0) * current.width, y: current.y + (event.key === 'ArrowDown' ? 0.08 : event.key === 'ArrowUp' ? -0.08 : 0) * current.height }));
    else return;
    event.preventDefault();
  }
  function startHandle(event: PointerEvent<SVGCircleElement>) {
    if (disabled) return;
    event.stopPropagation();
    const group = event.currentTarget.parentElement as unknown as SVGGraphicsElement;
    const matrix = group.getScreenCTM();
    if (!matrix) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    handle.current = { pointer: event.pointerId, start: [start.x, start.y], centerX: (start.x + end.x) / 2, inverse: matrix.inverse() };
  }
  function moveHandle(event: PointerEvent<SVGCircleElement>) {
    const drag = handle.current;
    if (!drag || drag.pointer !== event.pointerId || disabled) return;
    const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(drag.inverse);
    const value = focusedPom === 'chestWidth' ? Math.abs(point.x - drag.centerX) * 2 : Math.abs(point.y - drag.start[1]);
    onMeasurement(focusedPom, Math.max(focused.rangeM[0], Math.min(focused.rangeM[1], value)));
  }
  function pieceDrawing(piece: PatternPiece, compared: boolean) {
    const outline = flattenPiece(piece);
    const minimumX = Math.min(...outline.map(point => point[0]));
    const maximumY = Math.max(...outline.map(point => point[1]));
    const offset = pieceOffset(piece);
    return <g key={`${compared ? 'comparison' : 'current'}-${piece.id}`} data-piece-id={piece.id} className={compared ? 'compared-pattern' : 'current-pattern'} transform={`translate(${offset[0]} ${offset[1]})`}>
      {allowances && <polygon data-boundary="cut" points={piece.cuttingBoundary.map(point => point.join(',')).join(' ')} className="cutting-boundary" vectorEffect="non-scaling-stroke" />}
      <path data-boundary="seam" d={seamPath(piece)} className="seam-boundary" fill={compared ? 'none' : revision.visualMaterial.color} fillOpacity={compared ? 0 : 0.14} vectorEffect="non-scaling-stroke" />
      {!compared && <>
        <text transform={`translate(${minimumX} ${maximumY + 0.045}) scale(1 -1)`} fontSize={fontSize} className="piece-label">{piece.name} · cut {piece.cutQuantity}{piece.mirrored ? ' mirrored' : ''}</text>
        {guides && <>
          <line x1={piece.grainline.from[0]} y1={piece.grainline.from[1]} x2={piece.grainline.to[0]} y2={piece.grainline.to[1]} className="grainline" vectorEffect="non-scaling-stroke" markerEnd={`url(#${markerId}-grain)`} />
          {piece.notches.map(notch => { const point = pointOnEdge(piece, notch.edgeId, notch.t); const near = pointOnEdge(piece, notch.edgeId, Math.min(1, notch.t + 0.002)); const dx = near[0] - point[0], dy = near[1] - point[1], length = Math.hypot(dx, dy) || 1; return <g key={notch.id} className="pattern-notch"><line x1={point[0] - dy / length * 0.008} y1={point[1] + dx / length * 0.008} x2={point[0] + dy / length * 0.008} y2={point[1] - dx / length * 0.008} vectorEffect="non-scaling-stroke" />{notch.kind === 'double' && <line x1={point[0] + dx / length * 0.006 - dy / length * 0.008} y1={point[1] + dy / length * 0.006 + dx / length * 0.008} x2={point[0] + dx / length * 0.006 + dy / length * 0.008} y2={point[1] + dy / length * 0.006 - dx / length * 0.008} vectorEffect="non-scaling-stroke" />}</g>; })}
          {piece.fold?.line && <line x1={piece.fold.line.from[0]} y1={piece.fold.line.from[1]} x2={piece.fold.line.to[0]} y2={piece.fold.line.to[1]} className="fold-line" vectorEffect="non-scaling-stroke" />}
        </>}
        {piece.id === focused.endpoints.pieceId && <g className="measurement-overlay" aria-label={`${focused.name}: ${toDisplay(pattern.measuredValues[focusedPom], unit).toFixed(3)} ${unit}`}>
          {(diagramStart.x!==start.x||diagramStart.y!==start.y) && <line x1={start.x} y1={start.y} x2={diagramStart.x} y2={diagramStart.y} strokeDasharray="0.008 0.006" vectorEffect="non-scaling-stroke" />}
          <line x1={diagramStart.x} y1={diagramStart.y} x2={diagramEnd.x} y2={diagramEnd.y} vectorEffect="non-scaling-stroke" markerStart={`url(#${markerId}-dimension)`} markerEnd={`url(#${markerId}-dimension)`} />
          <text transform={`translate(${(diagramStart.x + diagramEnd.x) / 2 + 0.02} ${(diagramStart.y + diagramEnd.y) / 2 + 0.03}) scale(1 -1)`} fontSize={fontSize}>{focused.name}: {toDisplay(pattern.measuredValues[focusedPom], unit).toFixed(2)} {unit}</text>
          {individual === piece.id && ['bodyLength', 'chestWidth'].includes(focusedPom) && <circle cx={end.x} cy={end.y} r={frame.width * 0.011} role="slider" tabIndex={disabled ? -1 : 0} aria-label={`Adjust ${focused.name}`} aria-valuenow={toDisplay(pattern.measuredValues[focusedPom], unit)} aria-valuemin={toDisplay(focused.rangeM[0], unit)} aria-valuemax={toDisplay(focused.rangeM[1], unit)} aria-valuetext={`${toDisplay(pattern.measuredValues[focusedPom], unit).toFixed(3)} ${unit}`} className="measurement-handle" vectorEffect="non-scaling-stroke"
            onPointerDown={startHandle} onPointerMove={moveHandle} onPointerUp={() => { handle.current = null; }} onPointerCancel={() => { handle.current = null; }}
            onKeyDown={event => { if (disabled || !['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) return; event.preventDefault(); event.stopPropagation(); const step = fromDisplay(unit === 'cm' ? 0.1 : 0.01, unit); const value = event.key === 'Home' ? focused.rangeM[0] : event.key === 'End' ? focused.rangeM[1] : pattern.measuredValues[focusedPom] + (event.key === 'ArrowRight' || event.key === 'ArrowUp' ? step : -step); onMeasurement(focusedPom, Math.max(focused.rangeM[0], Math.min(focused.rangeM[1], value))); }} />}
        </g>}
      </>}
    </g>;
  }
  function technicalDrawing(source: PatternDefinition, compared: boolean) {
    const technical = technicalView(source, view as 'front' | 'back');
    return <g className={compared ? 'compared-pattern' : 'current-pattern'}>{technical.outlines.map((outline, index) => <polygon key={index} points={outline.map(point => point.join(',')).join(' ')} className="seam-boundary" fill={compared ? 'none' : revision.visualMaterial.color} fillOpacity={compared ? 0 : 0.65} vectorEffect="non-scaling-stroke" />)}<polyline points={technical.neckline.map(point => point.join(',')).join(' ')} fill="none" className="seam-boundary" vectorEffect="non-scaling-stroke" /></g>;
  }

  return <section className="preview-panel pattern-panel" aria-labelledby={titleId}>
    <div className="panel-heading"><h2 id={titleId}>{isTechnical ? `${view === 'front' ? 'Front' : 'Back'} technical flat` : 'Pattern pieces'}</h2><span>{size.label} · provisional</span></div>
    <div className="pattern-toolbar"><label>2D representation<select aria-label="2D representation" value={view} onChange={event => onView(event.target.value as PatternView)} disabled={disabled}><option value="front">Front technical flat</option><option value="back">Back technical flat</option><option value="pieces">All construction pieces</option>{Object.entries(PIECE_NAMES).map(([id, name]) => <option key={id} value={`piece-${id}`}>{name} piece</option>)}</select></label><div role="group" aria-label="Pattern zoom"><button onClick={() => zoom(0.8)} aria-label="Zoom pattern in">+</button><button onClick={() => zoom(1.25)} aria-label="Zoom pattern out">−</button><button onClick={fit}>Fit drawing</button></div></div>
    {!isTechnical && <div className="pattern-layer-controls"><label><input type="checkbox" checked={allowances} onChange={event => setAllowances(event.target.checked)} />Cutting boundary / allowance</label><label><input type="checkbox" checked={guides} onChange={event => setGuides(event.target.checked)} />Grainlines & notches</label></div>}
    <div className="drawing-surface generated-pattern-surface"><svg role="group" tabIndex={0} aria-label={`${isTechnical ? view + ' technical garment flat' : 'Generated construction pieces'} for ${size.label}. Meter-based geometry. Plus/minus zoom, arrows pan, Home fits drawing.`} viewBox={`${frame.x} ${frame.y} ${frame.width} ${frame.height}`} onKeyDown={drawingKeys}
      onPointerDown={event => { if ((event.target as Element).closest('[role="slider"]')) return; const matrix = event.currentTarget.getScreenCTM(); if (!matrix) return; const inverse = matrix.inverse(); event.currentTarget.setPointerCapture(event.pointerId); pan.current = { pointer: event.pointerId, start: new DOMPoint(event.clientX, event.clientY).matrixTransform(inverse), inverse, frame }; }}
      onPointerMove={event => { const drag = pan.current; if (!drag || drag.pointer !== event.pointerId) return; const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(drag.inverse); setFrame({ ...drag.frame, x: drag.frame.x - (point.x - drag.start.x), y: drag.frame.y - (point.y - drag.start.y) }); }} onPointerUp={() => { pan.current = null; }} onPointerCancel={() => { pan.current = null; }}>
      <defs><marker id={`${markerId}-dimension`} viewBox="0 0 8 8" refX="4" refY="4" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M 0 0 L 8 4 L 0 8 Z" className="measurement-arrow" /></marker><marker id={`${markerId}-grain`} viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M 0 0 L 8 4 L 0 8" fill="none" className="grainline" /></marker></defs>
      <g transform="scale(1 -1)">{isTechnical ? <>{technicalDrawing(pattern, false)}{otherPattern && technicalDrawing(otherPattern, true)}{legacyOutline && <polygon className="compared-pattern seam-boundary" fill="none" points={legacyOutline.map(point => `${point[0]},${point[1] - legacyTop}`).join(' ')} vectorEffect="non-scaling-stroke" />}</> : <>{visiblePieces.map(piece => pieceDrawing(piece, false))}{otherPattern && visiblePieces.map(piece => { const other = otherPattern.pieces.find(item => item.id === piece.id); return other ? pieceDrawing(other, true) : null; })}</>}</g>
    </svg></div>
    <div className="panel-caption"><span>{isTechnical ? 'Generated technical illustration' : 'Solid: seam line · outer: cutting boundary · layout is not a marker'}</span><span>1:1 physical scale is in SVG export, not screen zoom.</span></div>
    {comparison && <p className="drawing-comparison-note">Dashed: compared revision / size. {comparison.revision.schemaVersion === 1 ? 'Legacy illustration has no measured specification.' : 'Shared meter coordinates; view does not automatically rescale on size changes.'}</p>}
    {individual && <p className="drawing-comparison-note">{PIECE_NAMES[individual]} · material group: {visiblePieces[0].materialGroup} · cut {visiblePieces[0].cutQuantity}{visiblePieces[0].mirrored ? ', mirrored' : ''} · {toDisplay(visiblePieces[0].seamAllowance.distanceM, unit).toFixed(2)} {unit} seam allowance. {visiblePieces[0].fold?.instruction}</p>}
  </section>;
}
