import type { DisplayUnit } from '../domain/development-types';

const METERS_PER_INCH = 0.0254;
export function toDisplay(meters: number, unit: DisplayUnit): number {
  if (!Number.isFinite(meters)) throw new Error('Measurement must be finite');
  return unit === 'cm' ? meters * 100 : meters / METERS_PER_INCH;
}
export function fromDisplay(value: number, unit: DisplayUnit): number {
  if (!Number.isFinite(value)) throw new Error('Measurement must be finite');
  return unit === 'cm' ? value / 100 : value * METERS_PER_INCH;
}
