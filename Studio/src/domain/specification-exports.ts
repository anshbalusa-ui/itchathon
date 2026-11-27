import type { DisplayUnit, MeasurementId, PatternPiece } from './development-types';
import type { ParametricGarmentRevision } from './types';
import { POMS, pointOnEdge } from '../patterns/generator';
import { toDisplay } from '../patterns/units';
import { validateDevelopment } from './development';

const IDS: readonly MeasurementId[] = ['bodyLength', 'chestWidth', 'hemWidth', 'shoulderWidth', 'sleeveLength', 'sleeveOpening', 'neckWidth', 'neckDepth'];
const csvCell = (value: unknown): string => {
  let text = String(value ?? '');
  if (/^[\s\u0000-\u001f]*[=+@\-]/u.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
};

export function specificationCsv(revision: ParametricGarmentRevision, unit: DisplayUnit): string {
  validateDevelopment(revision.development, revision.id);
  if (unit !== 'cm' && unit !== 'in') throw new RangeError('Display unit is not supported.');
  const header = ['garment', 'garmentId', 'revisionId', 'size', 'sizeId', 'pomId', 'name', 'definition', 'endpoint', 'method', 'value', 'unit', 'tolerance', 'status', 'measurementSource', 'sourceLabel', 'sourceUri', 'sourceSha256'];
  const rows: unknown[][] = [header];
  for (const size of revision.development.sizeSet.sizes) {
    for (const pom of IDS) {
      const definition = POMS.find((item) => item.id === pom)!;
      const tolerance = size.specification.tolerancesM[pom];
      rows.push([revision.name, revision.garmentId, revision.id, size.label, size.id, pom, definition.name, definition.definition,
        `${definition.endpoints.pieceId}:${definition.endpoints.startPointId}→${definition.endpoints.endPointId}`,
        definition.method, toDisplay(size.specification.values[pom], unit), unit,
        tolerance === undefined ? '' : toDisplay(tolerance, unit), size.specification.validationStatus,
        size.specification.sources[pom], revision.source.label, revision.source.uri, revision.source.sha256]);
    }
  }
  return rows.map((row) => row.map(csvCell).join(',')).join(String.fromCharCode(13, 10));
}

export function specificationJson(revision: ParametricGarmentRevision): string {
  validateDevelopment(revision.development, revision.id);
  return JSON.stringify({ schemaVersion: 2, garment: { id: revision.garmentId, revisionId: revision.id,
    parentRevisionId: revision.parentRevisionId, name: revision.name, category: revision.category,
    templateId: revision.templateId, templateVersion: revision.templateVersion, geometryAdapter: revision.geometryAdapter,
    color: revision.visualMaterial.color, source: revision.source, validationStatus: revision.validationStatus,
    restoredFromRevisionId: revision.restoredFromRevisionId ?? null },
  development: { generatorVersion: revision.development.generatorVersion, topologyVersion: revision.development.topologyVersion,
    sizeSet: revision.development.sizeSet, gradeRules: revision.development.sizeSet.gradeRules,
    patterns: revision.development.patterns } }, null, 2);
}

function escaped(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}
function polyPath(points: readonly (readonly [number, number])[], scale: number, offsetX: number, offsetY: number): string {
  if (points.length === 0) return '';
  return `M ${points.map(([x, y], index) => `${index === 0 ? '' : 'L '}${(x * scale + offsetX).toFixed(4)} ${(-y * scale + offsetY).toFixed(4)}`).join(' ')} Z`;
}
function curvePath(piece: PatternPiece, scale: number, offsetX: number, offsetY: number): string {
  const points = new Map(piece.points.map((point) => [point.id, point]));
  const commands: string[] = [];
  for (const edge of piece.edges) {
    const from = points.get(edge.from), to = points.get(edge.to);
    if (!from || !to) throw new TypeError(`Pattern piece ${piece.id} has a broken edge reference.`);
    const a = `${(from.x * scale + offsetX).toFixed(4)} ${(-from.y * scale + offsetY).toFixed(4)}`;
    const b = `${(to.x * scale + offsetX).toFixed(4)} ${(-to.y * scale + offsetY).toFixed(4)}`;
    if (commands.length === 0) commands.push(`M ${a}`);
    commands.push(edge.kind === 'line' ? `L ${b}` : `C ${(edge.control1[0] * scale + offsetX).toFixed(4)} ${(-edge.control1[1] * scale + offsetY).toFixed(4)} ${(edge.control2[0] * scale + offsetX).toFixed(4)} ${(-edge.control2[1] * scale + offsetY).toFixed(4)} ${b}`);
  }
  commands.push('Z'); return commands.join(' ');
}

export function patternSvg(revision: ParametricGarmentRevision, sizeId: string): string {
  validateDevelopment(revision.development, revision.id);
  const size = revision.development.sizeSet.sizes.find((item) => item.id === sizeId);
  const pattern = revision.development.patterns.find((item) => item.sizeId === sizeId);
  if (!size || !pattern) throw new RangeError(`Unknown pattern size ${sizeId}.`);
  const margin = 0.12, gap = 0.03, scale = 1000;
  let x = margin, y = margin, rowHeight = 0, maxX = 0;
  const rendered: string[] = [];
  for (const piece of pattern.pieces) {
    const boundary = [...piece.cuttingBoundary, ...piece.points.map(({ x, y }) => [x, y] as const),
      ...piece.edges.flatMap((edge) => edge.kind === 'cubic' ? [edge.control1, edge.control2] : []),
      piece.grainline.from, piece.grainline.to, ...(piece.fold?.line ? [piece.fold.line.from, piece.fold.line.to] : [])];
    const xs = boundary.map(([xPoint]) => xPoint), ys = boundary.map(([, yPoint]) => yPoint);
    const minX = Math.min(...xs), maxPieceX = Math.max(...xs), minY = Math.min(...ys), maxPieceY = Math.max(...ys);
    const width = maxPieceX - minX, height = maxPieceY - minY;
    if (x > margin && x + width > 1) { x = margin; y += rowHeight + gap; rowHeight = 0; }
    const px = (x - minX) * scale, py = (y + height + minY) * scale;
    const title = escaped(piece.name), pieceId = escaped(piece.id);
    const grain = `M ${(piece.grainline.from[0] * scale + px).toFixed(4)} ${(-piece.grainline.from[1] * scale + py).toFixed(4)} L ${(piece.grainline.to[0] * scale + px).toFixed(4)} ${(-piece.grainline.to[1] * scale + py).toFixed(4)}`;
    const fold = piece.fold?.line
      ? `<path class="fold-line" d="M ${(piece.fold.line.from[0] * scale + px).toFixed(4)} ${(-piece.fold.line.from[1] * scale + py).toFixed(4)} L ${(piece.fold.line.to[0] * scale + px).toFixed(4)} ${(-piece.fold.line.to[1] * scale + py).toFixed(4)}" fill="none" stroke="#007" stroke-dasharray="2 2"/>`
      : '';
    const notches = piece.notches.map((notch) => {
      const edge = piece.edges.find((candidate) => candidate.id === notch.edgeId);
      if (!edge) throw new TypeError(`Pattern piece ${piece.id} notch refers to a missing edge.`);
      const point = pointOnEdge(piece, notch.edgeId, notch.t), cx = point[0] * scale + px, cy = -point[1] * scale + py;
      return `<circle data-notch="${escaped(notch.id)}" cx="${cx.toFixed(4)}" cy="${cy.toFixed(4)}" r="1.5"><title>${escaped(notch.kind)} notch</title></circle>`;
    }).join('');
    const seamLabels = pattern.seams.filter((seam) => seam.a.pieceId === piece.id || seam.b.pieceId === piece.id)
      .map((seam) => escaped(seam.id)).join(', ');
    rendered.push(`<g id="${pieceId}" data-quantity="${piece.cutQuantity}" data-material="${piece.materialGroup}" data-seam-allowance-mm="${(piece.seamAllowance.distanceM * 1000).toFixed(2)}"><title>${title} — cut ${piece.cutQuantity} — seam allowance ${(piece.seamAllowance.distanceM * 1000).toFixed(2)} mm</title><path class="seam-line" d="${curvePath(piece, scale, px, py)}" fill="none" stroke="#111" stroke-width="0.5"/><path class="cut-line" d="${polyPath(piece.cuttingBoundary, scale, px, py)}" fill="none" stroke="#555" stroke-dasharray="4 3" stroke-width="0.3"/><path class="grainline" d="${grain}" fill="none" stroke="#777" stroke-width="0.4"/>${fold}${notches}<text x="${x * scale}" y="${(y + height + 0.012) * scale}">${title} / ${escaped(size.label)} / ${piece.cutQuantity}x — seams: ${seamLabels}</text></g>`);
    x += width + gap; rowHeight = Math.max(rowHeight, height); maxX = Math.max(maxX, x);
  }
  const widthM = Math.max(maxX + margin, 0.2);
  const seamInfoStartM = y + rowHeight + margin / 2;
  const seamInfo = pattern.seams.map((seam, index) => `<text x="4" y="${(seamInfoStartM + index * 0.006) * scale}" data-seam="${escaped(seam.id)}">${escaped(seam.id)}: ${escaped(seam.relationship)} (${escaped(seam.orientation)}, ratio ${seam.ratio})</text>`).join('');
  const heightM = y + rowHeight + margin + pattern.seams.length * 0.006 + 0.01;
  const mmWidth = widthM * scale, mmHeight = heightM * scale;
  const pomMetadata = POMS.map((definition) => `<pom id="${escaped(definition.id)}" name="${escaped(definition.name)}" definition="${escaped(definition.definition)}" method="${escaped(definition.method)}" start="${escaped(`${definition.endpoints.pieceId}:${definition.endpoints.startPointId}`)}" end="${escaped(`${definition.endpoints.pieceId}:${definition.endpoints.endPointId}`)}" value-m="${size.specification.values[definition.id]}"/>`).join('');
  const metadata = `<metadata><development garment-id="${escaped(revision.garmentId)}" revision-id="${escaped(revision.id)}" pattern-id="${escaped(pattern.id)}" size-id="${escaped(size.id)}" template-id="${escaped(pattern.templateId)}" generator-version="${escaped(pattern.generatorVersion)}" status="${escaped(pattern.validation.status)}" source-label="${escaped(pattern.source.label)}" source-sha256="${escaped(pattern.source.sha256)}">${pomMetadata}</development></metadata>`;
  return `<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="${mmWidth.toFixed(4)}mm" height="${mmHeight.toFixed(4)}mm" viewBox="0 0 ${mmWidth.toFixed(4)} ${mmHeight.toFixed(4)}" font-size="4" data-units="mm" data-scale="1:1">${metadata}<title>${escaped(revision.name)} — ${escaped(size.label)} pattern (illustrative sheet layout)</title><desc>Scale 1:1 numeric garment pattern; layout is not optimized nesting or a manufacturing validation.</desc>${rendered.join('')}${seamInfo}</svg>`;
}
