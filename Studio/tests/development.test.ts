import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createDevelopment, addSize, removeSize, renameSize, rebindDevelopment,
  setBaseSize, setGradeDelta, setMeasurement, setTolerance, validateDevelopment } from '../src/domain/development';

const chest = 'chestWidth' as const;
const hem = 'hemWidth' as const;

test('explicit grade deltas preserve independent measurements through base edits and rebasing', () => {
  const initial = createDevelopment(globalThis.crypto.randomUUID());
  const base = initial.sizeSet.sizes[0]!;
  let state = addSize(initial, 'Large');
  const large = state.sizeSet.sizes[1]!;
  state = setGradeDelta(state, large.id, chest, 0.04);
  assert.equal(state.sizeSet.sizes[0]!.specification.values[chest], base.specification.values[chest]);
  assert.equal(state.sizeSet.sizes[1]!.specification.values[chest], base.specification.values[chest] + 0.04);
  state = setMeasurement(state, base.id, chest, 0.60);
  assert.equal(state.sizeSet.sizes[0]!.specification.values[chest], 0.60);
  assert.equal(state.sizeSet.sizes[1]!.specification.values[chest], 0.64);
  assert.equal(state.sizeSet.sizes[0]!.specification.values[hem], base.specification.values[hem]);
  const actual = state.sizeSet.sizes.map((size) => ({ ...size.specification.values }));
  state = setBaseSize(state, large.id);
  assert.deepEqual(state.sizeSet.sizes.map((size) => size.specification.values), actual);
  assert.equal(state.sizeSet.gradeRules[0]!.fromSizeId, large.id);
  assert.ok(Math.abs(state.sizeSet.gradeRules[0]!.deltasM[chest] + 0.04) < 1e-12);
  validateDevelopment(state, state.sizeSet.garmentRevisionId);
});

test('size labels, tolerances, and chart bounds reject invalid edits without mutation', () => {
  const initial = createDevelopment(globalThis.crypto.randomUUID());
  const base = initial.sizeSet.sizes[0]!;
  assert.throws(() => addSize(initial, 'Base'), /unique printable/iu);
  assert.throws(() => addSize(initial, 'x'.repeat(25)), /unique printable/iu);
  assert.throws(() => setTolerance(initial, base.id, chest, -0.001), /Tolerance/iu);
  assert.throws(() => setTolerance(initial, base.id, chest, 0.101), /Tolerance/iu);
  assert.deepEqual(initial.sizeSet.sizes[0]!.specification.tolerancesM, {});
  const withTolerance = setTolerance(initial, base.id, chest, 0.005);
  assert.equal(withTolerance.sizeSet.sizes[0]!.specification.tolerancesM[chest], 0.005);
  assert.equal(setTolerance(withTolerance, base.id, chest, null).sizeSet.sizes[0]!.specification.tolerancesM[chest], undefined);
  let state = initial;
  for (let n = 0; n < 7; n += 1) state = addSize(state, `Size ${n + 1}`);
  assert.throws(() => addSize(state, 'Extra'), /eight sizes/iu);
  const finalSize = state.sizeSet.sizes[state.sizeSet.sizes.length - 1]!;
  assert.throws(() => removeSize(state, state.sizeSet.baseSizeId), /base size/iu);
  assert.equal(removeSize(state, finalSize.id).sizeSet.sizes.length, 7);
  assert.equal(renameSize(state, finalSize.id, 'Tall').sizeSet.sizes.at(-1)!.label, 'Tall');
});

test('rebinding changes garment lineage while preserving semantic size and pattern identities', () => {
  const original = createDevelopment(globalThis.crypto.randomUUID());
  const withTwo = addSize(original, 'Small');
  const nextGarmentId = globalThis.crypto.randomUUID();
  const rebound = rebindDevelopment(withTwo, nextGarmentId);
  assert.equal(rebound.sizeSet.garmentRevisionId, nextGarmentId);
  assert.equal(rebound.sizeSet.sizes[0]!.id, withTwo.sizeSet.sizes[0]!.id);
  assert.equal(rebound.sizeSet.sizes[0]!.specification.id, withTwo.sizeSet.sizes[0]!.specification.id);
  assert.deepEqual(rebound.patterns.map((pattern) => pattern.id), withTwo.patterns.map((pattern) => pattern.id));
  validateDevelopment(rebound, nextGarmentId);
});
