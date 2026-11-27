import { useId } from 'react';
import type { GarmentRevision } from '../domain/types';

export function GarmentDrawing({ revision }: { revision: GarmentRevision }) {
  const titleId = useId();
  const descriptionId = useId();
  const { outline, neckline } = revision.drawing;
  const xs = outline.map(point => point[0]);
  const ys = outline.map(point => point[1]);
  const minimumX = Math.min(...xs), maximumX = Math.max(...xs);
  const minimumY = Math.min(...ys), maximumY = Math.max(...ys);
  const padding = 0.09;
  return <section className="preview-panel drawing-panel" aria-labelledby={titleId}>
    <div className="panel-heading"><h2 id={titleId}>2D garment</h2><span>Front illustration</span></div>
    <div className="drawing-surface">
      <svg role="img" aria-labelledby={`${titleId} ${descriptionId}`}
        viewBox={`${minimumX - padding} ${-maximumY - padding} ${maximumX - minimumX + padding * 2} ${maximumY - minimumY + padding * 2}`}>
        <desc id={descriptionId}>{revision.name}, color {revision.visualMaterial.color}. Illustrative T-shirt outline, not a cutting pattern.</desc>
        <g transform="scale(1 -1)">
          <line x1="0" y1={minimumY - padding / 2} x2="0" y2={maximumY + padding / 2} className="drawing-guide" vectorEffect="non-scaling-stroke" />
          <polygon points={outline.map(point => point.join(',')).join(' ')} fill={revision.visualMaterial.color} stroke="currentColor" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
          <polyline points={neckline.map(point => point.join(',')).join(' ')} fill="none" stroke="currentColor" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
        </g>
      </svg>
    </div>
    <div className="panel-caption"><span>Basic T-shirt · v{revision.templateVersion}</span><span>Not a cutting pattern</span></div>
  </section>;
}
