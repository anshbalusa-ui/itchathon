import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fromDisplay, toDisplay } from '../src/patterns/units';
test('cm and inch conversions round-trip canonical meters without internal rounding',()=>{
  assert.equal(toDisplay(0.0254,'in'),1);assert.equal(fromDisplay(1,'in'),0.0254);
  for(const value of [0,0.01234,0.56,1.23])for(const unit of ['cm','in'] as const)assert.ok(Math.abs(fromDisplay(toDisplay(value,unit),unit)-value)<1e-12);
});
