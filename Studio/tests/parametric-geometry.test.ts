import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DEFAULT_VALUES, generatePattern, POMS } from '../src/patterns/generator';
import { generateGarmentMesh } from '../src/patterns/preview';
import type { DerivedGarmentMesh, GarmentSpecification, MeasurementId } from '../src/domain/development-types';
const makeSpec=(values={...DEFAULT_VALUES}):GarmentSpecification=>({schemaVersion:1,id:'spec',revisionId:'rev',garmentRevisionId:'garment',sizeId:'size',definitionVersion:'tshirt-pom-v1',units:'m',values,tolerancesM:{},sources:Object.fromEntries(POMS.map(p=>[p.id,'authored-default'])) as GarmentSpecification['sources'],validationStatus:'provisional-authored'});
function actual(mesh:DerivedGarmentMesh,id:MeasurementId):number {
  const def=POMS.find(pom=>pom.id===id)!,positions=mesh.mesh.positions,[a,b]=mesh.measurementVertexIndices[id];
  assert.ok(mesh.mesh.indices.includes(a)&&mesh.mesh.indices.includes(b),'POM endpoints must be indexed surface vertices');
  if(def.method==='half-path-length'){
    const path=mesh.measurementVertexPaths[id]!;let length=0;
    for(let i=1;i<path.length;i++)length+=Math.hypot(positions[path[i]*3]-positions[path[i-1]*3],positions[path[i]*3+1]-positions[path[i-1]*3+1],positions[path[i]*3+2]-positions[path[i-1]*3+2]);
    return length/2;
  }
  return def.method==='horizontal-projection'?Math.abs(positions[a*3]-positions[b*3]):def.method==='vertical-projection'?Math.abs(positions[a*3+1]-positions[b*3+1]):Math.hypot(positions[a*3]-positions[b*3],positions[a*3+1]-positions[b*3+1],positions[a*3+2]-positions[b*3+2]);
}
test('all eight changes affect actual mesh vertices while retaining every independent measurement',()=>{
  const original=makeSpec(),base=generateGarmentMesh(original,generatePattern(original,{id:'p',revisionId:'r'}));
  for(const pom of POMS){
    const values={...DEFAULT_VALUES,[pom.id]:DEFAULT_VALUES[pom.id]*1.02},spec=makeSpec(values);
    const mesh=generateGarmentMesh(spec,generatePattern(spec,{id:'p',revisionId:'r'}));
    assert.notDeepEqual(mesh.mesh.positions,base.mesh.positions);
    for(const measured of POMS)assert.ok(Math.abs(actual(mesh,measured.id)-values[measured.id])<1e-6,`${pom.id} changed ${measured.id}`);
    assert.ok(mesh.mesh.normals.every(Number.isFinite));
  }
});
