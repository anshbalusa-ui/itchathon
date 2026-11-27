import type {
  DevelopmentState,
  GarmentSpecification,
  GradeRule,
  MeasurementId,
  MeasurementValues,
  SizeSet,
} from './development-types';
import {
  DEFAULT_VALUES,
  GENERATOR_VERSION,
  PARAMETRIC_TEMPLATE_ID,
  PARAMETRIC_TEMPLATE_SOURCE,
  generatePattern,
  validatePattern,
  validateValues,
} from '../patterns/generator';

const MEASUREMENTS: readonly MeasurementId[] = [
  'bodyLength', 'chestWidth', 'hemWidth', 'shoulderWidth',
  'sleeveLength', 'sleeveOpening', 'neckWidth', 'neckDepth',
];
const MAX_SIZES = 8;
const MAX_TOLERANCE_M = 0.1;
const GRADE_ARITHMETIC_TOLERANCE_M = 1e-12;
const id = (): string => globalThis.crypto.randomUUID();

function spec(sizeId: string, revisionId: string, garmentRevisionId: string, values: MeasurementValues,
  sources: GarmentSpecification['sources'], tolerancesM: GarmentSpecification['tolerancesM'] = {},
  specId = id()): GarmentSpecification {
  return { schemaVersion: 1, id: specId, revisionId, garmentRevisionId, sizeId,
    definitionVersion: 'tshirt-pom-v1', units: 'm', values: { ...values },
    tolerancesM: { ...tolerancesM }, sources: { ...sources }, validationStatus: 'provisional-authored' };
}
function generateForSize(specification: GarmentSpecification, identity: { id: string; revisionId: string }, label: string) {
  try {
    return generatePattern(specification, identity);
  } catch (error) {
    throw new TypeError(`Size ${label}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function regenerate(state: DevelopmentState): DevelopmentState {
  const { sizeSet } = state;
  const sizes = sizeSet.sizes.map((size) => ({ ...size,
    specification: { ...size.specification, revisionId: sizeSet.revisionId, garmentRevisionId: sizeSet.garmentRevisionId },
  }));
  const patterns = sizes.map(({ id: sizeId, label, specification }) => {
    const previous = state.patterns.find((pattern) => pattern.sizeId === sizeId);
    return generateForSize(specification, { id: previous?.id ?? id(), revisionId: sizeSet.revisionId }, label);
  });
  const result = { ...state, sizeSet: { ...sizeSet, sizes }, patterns };
  validateDevelopment(result, sizeSet.garmentRevisionId);
  return result;
}

function sizeById(state: DevelopmentState, sizeId: string) {
  const size = state.sizeSet.sizes.find((item) => item.id === sizeId);
  if (!size) throw new RangeError(`Unknown size ${sizeId}.`);
  return size;
}
function valuesOf(state: DevelopmentState, sizeId: string): MeasurementValues {
  return sizeById(state, sizeId).specification.values;
}
function validateSizeValues(label: string, values: MeasurementValues): void {
  try {
    validateValues(values);
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    throw new RangeError(`Size ${label}: ${reason}`);
  }
}
function changedValue(state: DevelopmentState, sizeId: string, pom: MeasurementId, value: number): DevelopmentState {
  const next = structuredClone(state);
  const target = sizeById(next, sizeId);
  const values = { ...target.specification.values, [pom]: value };
  validateSizeValues(target.label, values);
  target.specification = { ...target.specification, values,
    sources: { ...target.specification.sources, [pom]: 'designer-input' } };
  if (sizeId === next.sizeSet.baseSizeId) {
    for (const size of next.sizeSet.sizes) {
      if (size.id === sizeId) continue;
      const rule = next.sizeSet.gradeRules.find((candidate) => candidate.toSizeId === size.id)!;
      const vals = { ...size.specification.values, [pom]: value + rule.deltasM[pom] };
      validateSizeValues(size.label, vals);
      size.specification = { ...size.specification, values: vals,
        sources: { ...size.specification.sources, [pom]: 'graded' } };
    }
  } else {
    const rule = next.sizeSet.gradeRules.find((candidate) => candidate.toSizeId === sizeId)!;
    rule.deltasM = { ...rule.deltasM, [pom]: value - valuesOf(next, next.sizeSet.baseSizeId)[pom] };
  }
  return regenerate(next);
}

export function createDevelopment(garmentRevisionId: string): DevelopmentState {
  const revisionId = id();
  const sizeId = id();
  const values = { ...DEFAULT_VALUES };
  const sources = Object.fromEntries(MEASUREMENTS.map((pom) => [pom, 'authored-default'])) as GarmentSpecification['sources'];
  const specification = spec(sizeId, revisionId, garmentRevisionId, values, sources);
  const sizeSet: SizeSet = { schemaVersion: 1, id: id(), revisionId, garmentRevisionId,
    baseSizeId: sizeId, sizes: [{ id: sizeId, label: 'Base', specification }], gradeRules: [] };
  return regenerate({ schemaVersion: 1, generatorVersion: GENERATOR_VERSION,
    topologyVersion: 'tshirt-5-piece-v1', sizeSet, patterns: [] });
}

const CANONICAL_NUMERIC_TOLERANCE_M = 1e-9;

function matchesCanonical(actual: unknown, expected: unknown): boolean {
  if (typeof actual === 'number' && typeof expected === 'number') {
    return Number.isFinite(actual) && Number.isFinite(expected)
      && Math.abs(actual - expected) <= CANONICAL_NUMERIC_TOLERANCE_M;
  }
  if (Array.isArray(actual) || Array.isArray(expected)) {
    return Array.isArray(actual) && Array.isArray(expected) && actual.length === expected.length
      && actual.every((value, index) => matchesCanonical(value, expected[index]));
  }
  if (actual !== null && expected !== null && typeof actual === 'object' && typeof expected === 'object') {
    const actualRecord = actual as Record<string, unknown>, expectedRecord = expected as Record<string, unknown>;
    const actualKeys = Object.keys(actualRecord), expectedKeys = Object.keys(expectedRecord);
    return actualKeys.length === expectedKeys.length
      && actualKeys.every((key) => Object.prototype.hasOwnProperty.call(expectedRecord, key) && matchesCanonical(actualRecord[key], expectedRecord[key]));
  }
  return actual === expected;
}

export function validateDevelopment(state: DevelopmentState, garmentRevisionId?: string): void {
  if (!state || state.schemaVersion !== 1 || state.generatorVersion !== GENERATOR_VERSION
    || state.topologyVersion !== 'tshirt-5-piece-v1') throw new TypeError('Development state versions are unsupported.');
  const set = state.sizeSet;
  if (!set || set.schemaVersion !== 1 || !set.id || !set.revisionId || !set.garmentRevisionId
    || (garmentRevisionId !== undefined && set.garmentRevisionId !== garmentRevisionId)
    || !Array.isArray(set.sizes) || set.sizes.length < 1 || set.sizes.length > MAX_SIZES
    || !Array.isArray(set.gradeRules) || !Array.isArray(state.patterns)) throw new TypeError('Development size set is malformed.');
  if (!set.sizes.some((size) => size.id === set.baseSizeId)) throw new TypeError('Development base size is missing.');
  const labels = new Set<string>(), sizeIds = new Set<string>();
  for (const size of set.sizes) {
    if (sizeIds.has(size.id)) throw new TypeError(`Duplicate size identity ${size.id}.`);
    sizeIds.add(size.id);
    if (typeof size.label !== 'string' || size.label.length < 1 || size.label.length > 24
      || size.label.trim() !== size.label || /[\u0000-\u001f\u007f]/u.test(size.label) || labels.has(size.label.toLowerCase())) {
      throw new TypeError(`Size ${size.label} must have a unique printable 1–24 character label.`);
    }
    labels.add(size.label.toLowerCase());
    const s = size.specification;
    if (s.schemaVersion !== 1 || s.revisionId !== set.revisionId || s.garmentRevisionId !== set.garmentRevisionId
      || s.sizeId !== size.id || s.definitionVersion !== 'tshirt-pom-v1' || s.units !== 'm'
      || s.validationStatus !== 'provisional-authored') throw new TypeError(`Size ${size.label} has invalid specification identity or status.`);
    validateSizeValues(size.label, s.values);
    for (const [pom, tolerance] of Object.entries(s.tolerancesM)) {
      if (!MEASUREMENTS.includes(pom as MeasurementId) || !Number.isFinite(tolerance) || tolerance! < 0 || tolerance! > MAX_TOLERANCE_M) {
        throw new RangeError(`Size ${size.label} ${pom} tolerance must be between 0 and ${MAX_TOLERANCE_M} m.`);
      }
    }
    for (const pom of MEASUREMENTS) if (!['authored-default', 'designer-input', 'graded'].includes(s.sources[pom])) {
      throw new TypeError(`Size ${size.label} ${pom} source is invalid.`);
    }
  }
  if (set.gradeRules.length !== set.sizes.length - 1) throw new TypeError('Each non-base size needs exactly one explicit grade rule.');
  const targets = new Set<string>();
  for (const rule of set.gradeRules) {
    if (rule.schemaVersion !== 1 || rule.revisionId !== set.revisionId || rule.garmentRevisionId !== set.garmentRevisionId
      || rule.fromSizeId !== set.baseSizeId || !sizeIds.has(rule.toSizeId) || rule.toSizeId === set.baseSizeId || targets.has(rule.toSizeId)
      || rule.method !== 'explicit-per-measurement-delta') throw new TypeError('Grade rule identity or lineage is invalid.');
    targets.add(rule.toSizeId);
    for (const pom of MEASUREMENTS) if (!Number.isFinite(rule.deltasM[pom])) throw new TypeError(`Grade delta ${pom} is not finite.`);
    const base = valuesOf(state, set.baseSizeId), target = valuesOf(state, rule.toSizeId);
    for (const pom of MEASUREMENTS) if (Math.abs((base[pom] + rule.deltasM[pom]) - target[pom]) > GRADE_ARITHMETIC_TOLERANCE_M) {
      throw new TypeError(`Size ${sizeById(state, rule.toSizeId).label} ${pom} does not match its grade rule.`);
    }
  }
  if (state.patterns.length !== set.sizes.length) throw new TypeError('Every size needs a canonical generated pattern.');
  for (const size of set.sizes) {
    const stored = state.patterns.find((pattern) => pattern.sizeId === size.id);
    if (!stored || stored.revisionId !== set.revisionId || stored.garmentRevisionId !== set.garmentRevisionId
      || stored.specificationRevisionId !== set.revisionId || stored.templateId !== PARAMETRIC_TEMPLATE_ID) {
      throw new TypeError(`Size ${size.label} pattern identity is invalid.`);
    }
    try {
      validatePattern(stored, size.specification);
    } catch (error) {
      throw new TypeError(`Size ${size.label}: ${error instanceof Error ? error.message : String(error)}`);
    }
    const canonical = generateForSize(size.specification, { id: stored.id, revisionId: set.revisionId }, size.label);
    if (!matchesCanonical(stored, canonical)) throw new TypeError(`Size ${size.label} pattern differs from canonical generated geometry (numeric tolerance ${CANONICAL_NUMERIC_TOLERANCE_M} m).`);
    if (!matchesCanonical(stored.source, PARAMETRIC_TEMPLATE_SOURCE)) throw new TypeError(`Size ${size.label} source is not pinned.`);
  }
}

export function setMeasurement(state: DevelopmentState, sizeId: string, pomId: MeasurementId, valueM: number): DevelopmentState {
  if (!MEASUREMENTS.includes(pomId)) throw new RangeError(`Unknown measurement ${pomId}.`);
  return changedValue(state, sizeId, pomId, valueM);
}
export function setTolerance(state: DevelopmentState, sizeId: string, pomId: MeasurementId, toleranceM: number | null): DevelopmentState {
  if (!MEASUREMENTS.includes(pomId)) throw new RangeError(`Unknown measurement ${pomId}.`);
  if (toleranceM !== null && (!Number.isFinite(toleranceM) || toleranceM < 0 || toleranceM > MAX_TOLERANCE_M)) throw new RangeError(`Tolerance must be between 0 and ${MAX_TOLERANCE_M} m.`);
  const next = structuredClone(state), size = sizeById(next, sizeId), tolerances = { ...size.specification.tolerancesM };
  if (toleranceM === null) delete tolerances[pomId]; else tolerances[pomId] = toleranceM;
  size.specification = { ...size.specification, tolerancesM: tolerances };
  return regenerate(next);
}
export function addSize(state: DevelopmentState, label: string): DevelopmentState {
  if (state.sizeSet.sizes.length >= MAX_SIZES) throw new RangeError('A development chart cannot contain more than eight sizes.');
  const clean = label.trim();
  if (!clean || clean.length > 24 || clean !== label || /[\u0000-\u001f\u007f]/u.test(clean)
    || state.sizeSet.sizes.some((size) => size.label.toLowerCase() === clean.toLowerCase())) throw new RangeError('Size label must be unique printable text of 1–24 characters.');
  const next = structuredClone(state), sizeId = id(), base = valuesOf(next, next.sizeSet.baseSizeId);
  const sources = Object.fromEntries(MEASUREMENTS.map((pom) => [pom, 'graded'])) as GarmentSpecification['sources'];
  const specification = spec(sizeId, next.sizeSet.revisionId, next.sizeSet.garmentRevisionId, base, sources);
  const deltas = { ...Object.fromEntries(MEASUREMENTS.map((pom) => [pom, 0])) } as MeasurementValues;
  const rule: GradeRule = { schemaVersion: 1, id: id(), revisionId: next.sizeSet.revisionId,
    garmentRevisionId: next.sizeSet.garmentRevisionId, fromSizeId: next.sizeSet.baseSizeId,
    toSizeId: sizeId, method: 'explicit-per-measurement-delta', deltasM: deltas };
  next.sizeSet.sizes.push({ id: sizeId, label: clean, specification }); next.sizeSet.gradeRules.push(rule);
  return regenerate(next);
}
export function renameSize(state: DevelopmentState, sizeId: string, label: string): DevelopmentState {
  const clean = label.trim();
  if (!clean || clean.length > 24 || clean !== label || /[\u0000-\u001f\u007f]/u.test(clean)
    || state.sizeSet.sizes.some((size) => size.id !== sizeId && size.label.toLowerCase() === clean.toLowerCase())) throw new RangeError('Size label must be unique printable text of 1–24 characters.');
  const next = structuredClone(state);
  sizeById(next, sizeId).label = clean;
  validateDevelopment(next, state.sizeSet.garmentRevisionId);
  return next;
}
export function removeSize(state: DevelopmentState, sizeId: string): DevelopmentState {
  if (sizeId === state.sizeSet.baseSizeId) throw new RangeError('The base size cannot be removed.');
  if (state.sizeSet.sizes.length <= 1) throw new RangeError('The last size cannot be removed.');
  const next = structuredClone(state); sizeById(next, sizeId);
  next.sizeSet.sizes = next.sizeSet.sizes.filter((size) => size.id !== sizeId);
  next.sizeSet.gradeRules = next.sizeSet.gradeRules.filter((rule) => rule.toSizeId !== sizeId);
  next.patterns = next.patterns.filter((pattern) => pattern.sizeId !== sizeId);
  validateDevelopment(next, state.sizeSet.garmentRevisionId);
  return next;
}
export function setBaseSize(state: DevelopmentState, sizeId: string): DevelopmentState {
  sizeById(state, sizeId);
  const next = structuredClone(state); next.sizeSet.baseSizeId = sizeId;
  next.sizeSet.gradeRules = next.sizeSet.sizes.filter((size) => size.id !== sizeId).map((size) => ({
    schemaVersion: 1, id: id(), revisionId: next.sizeSet.revisionId, garmentRevisionId: next.sizeSet.garmentRevisionId,
    fromSizeId: sizeId, toSizeId: size.id, method: 'explicit-per-measurement-delta',
    deltasM: Object.fromEntries(MEASUREMENTS.map((pom) => [pom, size.specification.values[pom] - valuesOf(next, sizeId)[pom]])) as MeasurementValues,
  }));
  return regenerate(next);
}
export function setGradeDelta(state: DevelopmentState, targetSizeId: string, pomId: MeasurementId, deltaM: number): DevelopmentState {
  if (!MEASUREMENTS.includes(pomId) || !Number.isFinite(deltaM)) throw new RangeError('Grade delta must be a finite supported measurement value.');
  if (targetSizeId === state.sizeSet.baseSizeId) throw new RangeError('The base size does not have a grade rule.');
  const next = structuredClone(state), target = sizeById(next, targetSizeId);
  const rule = next.sizeSet.gradeRules.find((item) => item.toSizeId === targetSizeId);
  if (!rule) throw new TypeError('Target size grade rule is missing.');
  const value = valuesOf(next, next.sizeSet.baseSizeId)[pomId] + deltaM;
  const values = { ...target.specification.values, [pomId]: value };
  validateSizeValues(target.label, values);
  rule.deltasM = { ...rule.deltasM, [pomId]: deltaM };
  target.specification = { ...target.specification, values,
    sources: { ...target.specification.sources, [pomId]: 'graded' } };
  return regenerate(next);
}
export function rebindDevelopment(state: DevelopmentState, garmentRevisionId: string): DevelopmentState {
  const next = structuredClone(state), revisionId = id();
  next.sizeSet.revisionId = revisionId; next.sizeSet.garmentRevisionId = garmentRevisionId;
  next.sizeSet.sizes = next.sizeSet.sizes.map((size) => ({ ...size, specification: { ...size.specification, revisionId, garmentRevisionId } }));
  next.sizeSet.gradeRules = next.sizeSet.gradeRules.map((rule) => ({ ...rule, revisionId, garmentRevisionId }));
  return regenerate(next);
}
