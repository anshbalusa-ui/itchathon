import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DEFAULT_VALUES, flattenPiece, generatePattern, measurePattern, POMS, pointOnEdge, technicalView, validatePattern, validateValues } from '../src/patterns/generator';
import type { GarmentSpecification, PatternPiece } from '../src/domain/development-types';
const makeSpec=(values={...DEFAULT_VALUES}):GarmentSpecification=>({schemaVersion:1,id:'spec',revisionId:'rev',garmentRevisionId:'garment',sizeId:'size',definitionVersion:'tshirt-pom-v1',units:'m',values,tolerancesM:{},sources:Object.fromEntries(POMS.map(p=>[p.id,'authored-default'])) as GarmentSpecification['sources'],validationStatus:'provisional-authored'});
function independentlySampledLength(piece:PatternPiece,ids:string[]):number {
  let length=0;
  for(const id of ids){let previous=pointOnEdge(piece,id,0);for(let i=1;i<=2048;i++){const point=pointOnEdge(piece,id,i/2048);length+=Math.hypot(point[0]-previous[0],point[1]-previous[1]);previous=point;}}
  return length;
}
test('all generated endpoints match the eight independent measurements',()=>{
  for(const pom of POMS){
    const values={...DEFAULT_VALUES,[pom.id]:DEFAULT_VALUES[pom.id]*1.01};
    const measured=measurePattern(generatePattern(makeSpec(values),{id:'p',revisionId:'r'}));
    for(const other of POMS)assert.ok(Math.abs(measured[other.id]-values[other.id])<1e-6,`${pom.id} changed ${other.id}`);
  }
});
test('both sleeves, shoulders, sides, and folded neckband seams match with declared ease',()=>{
  const pattern=generatePattern(makeSpec(),{id:'p',revisionId:'r'});
  for(const seam of pattern.seams){
    const a=pattern.pieces.find(piece=>piece.id===seam.a.pieceId)!,b=pattern.pieces.find(piece=>piece.id===seam.b.pieceId)!;
    const error=Math.abs(independentlySampledLength(a,seam.a.edgeIds)*seam.ratio-independentlySampledLength(b,seam.b.edgeIds));
    assert.ok(error<=seam.toleranceM,`${seam.id}: ${error}m`);
    if(seam.relationship==='equal-length')assert.equal(seam.ratio,1);
  }
  for(const id of ['sleeve-left','sleeve-right'])assert.equal(pattern.seams.filter(seam=>seam.relationship==='sleeve-cap-ease'&&seam.a.pieceId===id).length,2);
  assert.ok(pattern.validation.maximumSeamErrorM<=0.0005);
});
test('a declared 10mm allowance really offsets the rectangular neckband by 10mm',()=>{
  const pattern=generatePattern(makeSpec(),{id:'p',revisionId:'r'}),band=pattern.pieces[4],sew=flattenPiece(band);
  assert.ok(Math.abs(Math.min(...band.cuttingBoundary.map(p=>p[0]))-(Math.min(...sew.map(p=>p[0]))-0.01))<1e-10);
  assert.ok(Math.abs(Math.max(...band.cuttingBoundary.map(p=>p[1]))-(Math.max(...sew.map(p=>p[1]))+0.01))<1e-10);
  assert.ok(Math.abs(Math.min(...band.cuttingBoundary.map(p=>p[1]))+0.01)<1e-10);
});
test('construction is deterministic and rejects self-intersections without repairing imported reports',()=>{
  const spec=makeSpec(),pattern=generatePattern(spec,{id:'p',revisionId:'r'});
  assert.deepEqual(generatePattern(spec,{id:'p',revisionId:'r'}),pattern);
  const crossed=structuredClone(pattern);crossed.pieces[0].cuttingBoundary=[[0,0],[2,2],[0,2],[2,0],[3,1]];
  assert.throws(()=>validatePattern(crossed,spec),/cutting allowance self-intersects/);
  const report=structuredClone(pattern);report.validation.maximumSeamErrorM+=0.00001;const before=structuredClone(report);
  assert.throws(()=>validatePattern(report,spec),/seam validation report/);assert.deepEqual(report,before);
});
test('front and back technical flats retain actual body endpoints and different necklines',()=>{
  const pattern=generatePattern(makeSpec(),{id:'p',revisionId:'r'});
  const front=technicalView(pattern,'front'),back=technicalView(pattern,'back');
  assert.equal(Math.min(...front.outlines[0].map(point=>point[1])),-DEFAULT_VALUES.bodyLength);
  assert.notDeepEqual(front.neckline,back.neckline);
});
test('unsupported caps and incompatible dimensions are rejected, not silently adjusted',()=>{
  assert.throws(()=>generatePattern(makeSpec({...DEFAULT_VALUES,bodyLength:1,chestWidth:0.8,shoulderWidth:0.6}),{id:'p',revisionId:'r'}),/cannot support the required armhole cap/);
  assert.throws(()=>validateValues({...DEFAULT_VALUES,hemWidth:0.7}),/hemWidth/);
  assert.throws(()=>validateValues({...DEFAULT_VALUES,shoulderWidth:0.58}),/shoulderWidth/);
});
