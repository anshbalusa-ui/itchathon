import type { GarmentSpecification, MeasurementDefinition, MeasurementId, MeasurementValues, PatternDefinition, PatternEdge, PatternPiece, PatternPoint, Vec2 } from '../domain/development-types';
import type { SourceLicense } from '../domain/types';

export const GENERATOR_VERSION = '1.0.0' as const;
export const PARAMETRIC_TEMPLATE_ID = '8f014f10-1f76-4af7-a327-b2316f9c2f1a';
export const PARAMETRIC_TEMPLATE_SOURCE: SourceLicense = {
  label: 'Original provisional T-shirt block construction',
  uri: 'https://github.com/anshbalusa-ui/itchathon/blob/feature/onyou-studio-garment-development/Studio/src/patterns/template.json',
  sha256: '4b323199f17e513bec2015b73ed4086f5a033b5255facf09717fa9bdf7930203',
  license: 'CC0-1.0',
  notice: 'The authored construction template is dedicated to the public domain under CC0 1.0. This does not claim ownership of user-provided measurements or designs; the block is provisional and not professionally validated.'
};
export const DEFAULT_VALUES: MeasurementValues = { bodyLength: 0.70, chestWidth: 0.56, hemWidth: 0.54, shoulderWidth: 0.44, sleeveLength: 0.22, sleeveOpening: 0.19, neckWidth: 0.18, neckDepth: 0.08 };
const ranges: Record<MeasurementId, [number, number]> = {
 bodyLength:[0.45,1.0], chestWidth:[0.36,0.8], hemWidth:[0.34,0.8], shoulderWidth:[0.28,0.62], sleeveLength:[0.08,0.42], sleeveOpening:[0.1,0.35], neckWidth:[0.12,0.28], neckDepth:[0.035,0.15]
};
export const POMS: readonly MeasurementDefinition[] = [
 {id:'bodyLength',name:'Body length',definition:'Finished HPS-to-hem vertical garment length, measured directly below the right HPS.',method:'vertical-projection',endpoints:{pieceId:'front',startPointId:'pom-neck-right',endPointId:'pom-body-hem'},rangeM:ranges.bodyLength},
 {id:'chestWidth',name:'Chest width',definition:'Finished full front width, edge-to-edge at chest level.',method:'horizontal-projection',endpoints:{pieceId:'front',startPointId:'pom-chest-left',endPointId:'pom-chest-right'},rangeM:ranges.chestWidth},
 {id:'hemWidth',name:'Hem width',definition:'Finished full front width, edge-to-edge at lower hem.',method:'horizontal-projection',endpoints:{pieceId:'front',startPointId:'pom-hem-left',endPointId:'pom-hem-right'},rangeM:ranges.hemWidth},
 {id:'shoulderWidth',name:'Shoulder width',definition:'Finished full shoulder seam span from left to right shoulder endpoint.',method:'horizontal-projection',endpoints:{pieceId:'front',startPointId:'pom-shoulder-left',endPointId:'pom-shoulder-right'},rangeM:ranges.shoulderWidth},
 {id:'sleeveLength',name:'Sleeve length',definition:'Finished straight distance from cap apex to the center of the sleeve opening.',method:'straight-distance',endpoints:{pieceId:'sleeve-left',startPointId:'pom-sleeve-cap',endPointId:'pom-sleeve-opening'},rangeM:ranges.sleeveLength},
 {id:'sleeveOpening',name:'Sleeve opening',definition:'Finished flat sleeve-opening width: one half of the developed front-to-back opening seam.',method:'half-path-length',endpoints:{pieceId:'sleeve-left',startPointId:'pom-sleeve-opening-left',endPointId:'pom-sleeve-opening-right'},rangeM:ranges.sleeveOpening},
 {id:'neckWidth',name:'Neck width',definition:'Finished full front neck width from left HPS to right HPS.',method:'horizontal-projection',endpoints:{pieceId:'front',startPointId:'pom-neck-left',endPointId:'pom-neck-right'},rangeM:ranges.neckWidth},
 {id:'neckDepth',name:'Front neck depth',definition:'Finished vertical drop from right HPS level to the center-front neckline low point.',method:'vertical-projection',endpoints:{pieceId:'front',startPointId:'pom-neck-right',endPointId:'pom-neck-center'},rangeM:ranges.neckDepth}
];
export function validateValues(v: MeasurementValues): void {
 for (const [id,[lo,hi]] of Object.entries(ranges) as [MeasurementId,[number,number]][]) if (!Number.isFinite(v[id]) || v[id] < lo || v[id] > hi) throw new Error(`${id} must be between ${lo}m and ${hi}m`);
 if (v.hemWidth > v.chestWidth + 0.005) throw new Error('hemWidth cannot exceed chestWidth by more than 5mm');
 if (v.shoulderWidth >= v.chestWidth || v.neckWidth >= v.shoulderWidth || v.neckDepth >= v.bodyLength * 0.45) throw new Error('shoulderWidth, neckWidth and neckDepth are incompatible');
 if (v.sleeveOpening >= v.chestWidth * 0.7 || v.sleeveLength < v.sleeveOpening * 0.35) throw new Error('sleeve dimensions are incompatible with chest width');
}
const pt=(id:string,x:number,y:number):PatternPoint=>({id,x,y});
const line=(id:string,from:string,to:string,role:PatternEdge['role']):PatternEdge=>({id,from,to,role,kind:'line'});
function makePiece(id:PatternPiece['id'], name:string, points:PatternPoint[], edges:PatternEdge[], options:Partial<PatternPiece>={}):PatternPiece {
 const provisional:PatternPiece={id,name,points,edges,grainline:{from:[0,0],to:[0,0.1]},fold:null,cutQuantity:1,mirrored:false,materialGroup:'main',notches:[],seamAllowance:{kind:'uniform-offset',distanceM:0.01,join:'miter',curveToleranceM:0.0005},cuttingBoundary:[],...options};
 provisional.cuttingBoundary=offsetBoundary(flattenPiece(provisional,0.0005),provisional.seamAllowance.distanceM);
 return provisional;
}
export function generatePattern(spec:GarmentSpecification, identity:{id:string;revisionId:string}):PatternDefinition {
 validateValues(spec.values); const v=spec.values, half=v.chestWidth/2, shoulder=v.shoulderWidth/2, neck=v.neckWidth/2, chestY=v.bodyLength*0.68, neckY=v.bodyLength-v.neckDepth;
 const points=[pt('pom-hem-left',-v.hemWidth/2,0),pt('pom-body-hem',neck,0),pt('pom-hem-right',v.hemWidth/2,0),pt('pom-chest-left',-half,chestY),pt('pom-chest-right',half,chestY),pt('pom-shoulder-left',-shoulder,v.bodyLength),pt('pom-shoulder-right',shoulder,v.bodyLength),pt('pom-neck-left',-neck,v.bodyLength),pt('pom-neck-right',neck,v.bodyLength),pt('pom-neck-center',0,neckY)];
 const frontEdges:PatternEdge[]=[
  line('hem-left','pom-hem-left','pom-body-hem','hem'),line('hem-right','pom-body-hem','pom-hem-right','hem'),
  line('right-side','pom-hem-right','pom-chest-right','side'),
  {id:'right-armhole',from:'pom-chest-right',to:'pom-shoulder-right',role:'armhole',kind:'cubic',control1:[half-0.012,chestY+0.09],control2:[shoulder+0.025,v.bodyLength-0.045]},
  line('right-shoulder','pom-shoulder-right','pom-neck-right','shoulder'),
  {id:'right-neck',from:'pom-neck-right',to:'pom-neck-center',role:'neckline',kind:'cubic',control1:[neck*0.72,v.bodyLength-v.neckDepth*0.08],control2:[neck*0.2,neckY]},
  {id:'left-neck',from:'pom-neck-center',to:'pom-neck-left',role:'neckline',kind:'cubic',control1:[-neck*0.2,neckY],control2:[-neck*0.72,v.bodyLength-v.neckDepth*0.08]},
  line('left-shoulder','pom-neck-left','pom-shoulder-left','shoulder'),
  {id:'left-armhole',from:'pom-shoulder-left',to:'pom-chest-left',role:'armhole',kind:'cubic',control1:[-shoulder-0.025,v.bodyLength-0.045],control2:[-half+0.012,chestY+0.09]},
  line('left-side','pom-chest-left','pom-hem-left','side')
 ];
 const front=makePiece('front','Front',points,frontEdges);
 const backNeckDepth=Math.min(v.neckDepth*0.25,0.03),backNeckY=v.bodyLength-backNeckDepth;
 const backPoints=points.map(p=>({...p,id:p.id.replace('pom-','back-'),...(p.id==='pom-neck-center'?{y:backNeckY}:{})}));
 const backEdges=frontEdges.map(e=>({...e,id:`back-${e.id}`,from:e.from.replace('pom-','back-'),to:e.to.replace('pom-','back-')}));
 const back=makePiece('back','Back',backPoints,backEdges.map(e=>e.id==='back-right-neck'?{...e,control1:[neck*0.72,v.bodyLength-backNeckDepth*0.08] as Vec2,control2:[neck*0.2,backNeckY] as Vec2}:e.id==='back-left-neck'?{...e,control1:[-neck*0.2,backNeckY] as Vec2,control2:[-neck*0.72,v.bodyLength-backNeckDepth*0.08] as Vec2}:e),{cutQuantity:1});
 const sl=v.sleeveLength, ow=v.sleeveOpening, capY=sl;
 const oneArmhole=edgeLength(front,['right-armhole']),capTarget=oneArmhole*2*1.03,capBaseWidth=Math.min(ow*0.5,v.chestWidth*0.17);
 let capScale=0, low=0, high=1.8;
 const capLength=(scale:number)=>{const endY=capY+(capY*0.55-capY)*scale,width=capBaseWidth*1.4*scale,c1x=width*0.55,c2x=width*0.25,c1y=capY+(capY*0.95-capY)*scale;const halfLen=(sign:number)=>{let prev:Vec2=[sign*width,endY],sum=0;for(let i=1;i<=32;i++){const t=i/32,u=1-t,x=u*u*u*sign*width+3*u*u*t*sign*c1x+3*u*t*t*sign*c2x,y=u*u*u*endY+3*u*u*t*c1y+3*u*t*t*capY+t*t*t*capY;sum+=Math.hypot(x-prev[0],y-prev[1]);prev=[x,y];}return sum;};return halfLen(-1)+halfLen(1);};
 if(capLength(high)<capTarget)throw new Error('sleeveLength and sleeveOpening cannot support the required armhole cap; adjust sleeve dimensions');
 for(let i=0;i<36;i++){capScale=(low+high)/2;if(capLength(capScale)<capTarget)low=capScale;else high=capScale;}capScale=(low+high)/2;
 const capEndX=capBaseWidth*1.4*capScale,capEndY=capY+(capY*0.55-capY)*capScale;
 if(capEndY<=0)throw new Error('sleeveLength is too short to form the supported sleeve-cap shape');
 const sleevePts=[pt('pom-sleeve-opening-left',-ow,0),pt('pom-sleeve-opening',0,0),pt('pom-sleeve-opening-right',ow,0),pt('sleeve-cap-left',-capEndX,capEndY),pt('sleeve-cap-right',capEndX,capEndY),pt('pom-sleeve-cap',0,capY)];
 const sleeveEdges:PatternEdge[]=[line('sleeve-hem-left','pom-sleeve-opening-left','pom-sleeve-opening','hem'),line('sleeve-hem-right','pom-sleeve-opening','pom-sleeve-opening-right','hem'),line('sleeve-underarm-right','pom-sleeve-opening-right','sleeve-cap-right','underarm'),{id:'sleeve-cap-back',from:'sleeve-cap-right',to:'pom-sleeve-cap',role:'sleeve-cap',kind:'cubic',control1:[capEndX*0.55,capY+(capY*0.95-capY)*capScale],control2:[capEndX*0.25,capY]}, {id:'sleeve-cap-front',from:'pom-sleeve-cap',to:'sleeve-cap-left',role:'sleeve-cap',kind:'cubic',control1:[-capEndX*0.25,capY],control2:[-capEndX*0.55,capY+(capY*0.95-capY)*capScale]},line('sleeve-underarm-left','sleeve-cap-left','pom-sleeve-opening-left','underarm')];
 const sleeveL=makePiece('sleeve-left','Sleeve (left)',sleevePts,sleeveEdges,{cutQuantity:1,grainline:{from:[0,0],to:[0,sl]}});
 const sleeveR=makePiece('sleeve-right','Sleeve (right)',sleevePts.map(p=>({...p,x:p.x===0?0:-p.x,id:`right-${p.id}`})),sleeveEdges.map(e=>({...e,id:`right-${e.id}`,from:`right-${e.from}`,to:`right-${e.to}`,...(e.kind==='cubic'?{control1:[e.control1[0]===0?0:-e.control1[0],e.control1[1]] as Vec2,control2:[e.control2[0]===0?0:-e.control2[0],e.control2[1]] as Vec2}:{})})),{cutQuantity:1,mirrored:true});
 const neckFront=edgeLength(front,['right-neck','left-neck']),bandFront=neckFront*0.9,bandBack=edgeLength(back,['back-right-neck','back-left-neck'])*0.9,bandLen=bandFront+bandBack,bh=0.045;
 const bp=[pt('band-0',0,0),pt('band-front-end',bandFront,0),pt('band-end',bandLen,0),pt('band-upper-end',bandLen,bh),pt('band-upper-back',bandFront,bh),pt('band-upper-start',0,bh)];
 const band=makePiece('neckband','Neckband',bp,[
  line('band-front-attachment','band-0','band-front-end','neckband-attachment'),
  line('band-back-attachment','band-front-end','band-end','neckband-attachment'),
  line('band-side','band-end','band-upper-end','neckband-join'),
  line('band-back-upper','band-upper-end','band-upper-back','neckband-attachment'),
  line('band-front-upper','band-upper-back','band-upper-start','neckband-attachment'),
  line('band-join','band-upper-start','band-0','neckband-join')
 ],{materialGroup:'rib',cutQuantity:1,grainline:{from:[0,bh/2],to:[0.1,bh/2]},fold:{edgeIds:[],instruction:'Fold the band lengthwise along its centerline, wrong sides together.',line:{id:'neckband-lengthwise-fold',from:[0,bh/2],to:[bandLen,bh/2]}}});
 const pieces=[front,back,sleeveL,sleeveR,band];
 const seams:PatternDefinition['seams']=[];
 for(const side of ['right','left'] as const){
  const sleeveId=side==='right'?'sleeve-left':'sleeve-right';
  const prefix=side==='right'?'':'right-';
  seams.push(
   {id:`shoulder-${side}`,a:{pieceId:'front',edgeIds:[`${side}-shoulder`]},b:{pieceId:'back',edgeIds:[`back-${side}-shoulder`]},relationship:'equal-length',orientation:'aligned',ratio:1,toleranceM:0.0005},
   {id:`side-${side}`,a:{pieceId:'front',edgeIds:[`${side}-side`]},b:{pieceId:'back',edgeIds:[`back-${side}-side`]},relationship:'equal-length',orientation:'aligned',ratio:1,toleranceM:0.0005},
   {id:`sleeve-front-${side}-cap-ease`,a:{pieceId:sleeveId,edgeIds:[`${prefix}sleeve-cap-front`]},b:{pieceId:'front',edgeIds:[`${side}-armhole`]},relationship:'sleeve-cap-ease',orientation:side==='right'?'opposed':'aligned',ratio:1/1.03,toleranceM:0.0005},
   {id:`sleeve-back-${side}-cap-ease`,a:{pieceId:sleeveId,edgeIds:[`${prefix}sleeve-cap-back`]},b:{pieceId:'back',edgeIds:[`back-${side}-armhole`]},relationship:'sleeve-cap-ease',orientation:side==='right'?'aligned':'opposed',ratio:1/1.03,toleranceM:0.0005},
   {id:`sleeve-${side}-underarm-join`,a:{pieceId:sleeveId,edgeIds:[`${prefix}sleeve-underarm-right`]},b:{pieceId:sleeveId,edgeIds:[`${prefix}sleeve-underarm-left`]},relationship:'equal-length',orientation:'opposed',ratio:1,toleranceM:0.0005}
  );
 }
 seams.push(
  {id:'neckband-front-lower',a:{pieceId:'front',edgeIds:['right-neck','left-neck']},b:{pieceId:'neckband',edgeIds:['band-front-attachment']},relationship:'neckband-stretch',orientation:'aligned',ratio:0.9,toleranceM:0.0005},
  {id:'neckband-back-lower',a:{pieceId:'back',edgeIds:['back-right-neck','back-left-neck']},b:{pieceId:'neckband',edgeIds:['band-back-attachment']},relationship:'neckband-stretch',orientation:'opposed',ratio:0.9,toleranceM:0.0005},
  {id:'neckband-front-upper',a:{pieceId:'front',edgeIds:['right-neck','left-neck']},b:{pieceId:'neckband',edgeIds:['band-front-upper']},relationship:'neckband-stretch',orientation:'opposed',ratio:0.9,toleranceM:0.0005},
  {id:'neckband-back-upper',a:{pieceId:'back',edgeIds:['back-right-neck','back-left-neck']},b:{pieceId:'neckband',edgeIds:['band-back-upper']},relationship:'neckband-stretch',orientation:'aligned',ratio:0.9,toleranceM:0.0005},
  {id:'neckband-end-join',a:{pieceId:'neckband',edgeIds:['band-side']},b:{pieceId:'neckband',edgeIds:['band-join']},relationship:'equal-length',orientation:'opposed',ratio:1,toleranceM:0.0005}
 );
 for(const seam of seams.filter(item=>item.relationship==='sleeve-cap-ease')){
  const kind=seam.b.pieceId==='front'?'single':'double';
  for(const ref of [seam.a,seam.b]){
   const piece=pieces.find(item=>item.id===ref.pieceId)!;
   piece.notches.push({id:`${seam.id}-${ref.pieceId}-notch`,edgeId:ref.edgeIds[0],t:halfwayParameter(piece,ref.edgeIds[0]),kind});
  }
 }
 const p:PatternDefinition={schemaVersion:1,id:identity.id,revisionId:identity.revisionId,garmentRevisionId:spec.garmentRevisionId,specificationRevisionId:spec.revisionId,sizeId:spec.sizeId,templateId:PARAMETRIC_TEMPLATE_ID,generatorVersion:GENERATOR_VERSION,topologyVersion:'tshirt-5-piece-v1',units:'m',coordinates:{x:'+right',y:'+up'},pieces,seams,measuredValues:{...v},validation:{status:'provisional-authored',maximumSeamErrorM:0,warnings:['Provisional authored block; designer/toile review is required. Each sleeve-cap half has 3% intentional ease. Folded neckband attachment edges are 90% of corresponding neckline lengths; material suitability is unverified.']},source:PARAMETRIC_TEMPLATE_SOURCE};
 p.measuredValues=measurePattern(p);
 p.validation.maximumSeamErrorM=maximumSeamError(p);
 validatePattern(p,spec);
 return p;
}
export function pointOnEdge(piece:PatternPiece,edgeId:string,t:number):Vec2 {
 if(!Number.isFinite(t)||t<0||t>1) throw new Error('Edge parameter must be in [0,1]'); const e=piece.edges.find(x=>x.id===edgeId); if(!e) throw new Error(`Unknown edge ${edgeId}`); const a=piece.points.find(x=>x.id===e.from),b=piece.points.find(x=>x.id===e.to); if(!a||!b) throw new Error(`Unresolved endpoints on ${edgeId}`); if(e.kind==='line') return [a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t]; const u=1-t; return [u*u*u*a.x+3*u*u*t*e.control1[0]+3*u*t*t*e.control2[0]+t*t*t*b.x,u*u*u*a.y+3*u*u*t*e.control1[1]+3*u*t*t*e.control2[1]+t*t*t*b.y];
}
export function edgeLength(piece:PatternPiece,edgeIds:string[]):number { let sum=0; for(const id of edgeIds){const e=piece.edges.find(x=>x.id===id);if(!e)throw new Error(`Unknown edge ${id}`);const n=e.kind==='line'?1:32;let prev=pointOnEdge(piece,id,0);for(let i=1;i<=n;i++){const q=pointOnEdge(piece,id,i/n);sum+=Math.hypot(q[0]-prev[0],q[1]-prev[1]);prev=q;}}return sum; }
export function flattenPiece(piece:PatternPiece,tolerance=0.001):Vec2[] {
 if(!Number.isFinite(tolerance)||tolerance<=0)throw new Error('Curve tolerance must be positive and finite');
 const result:Vec2[]=[];
 const append=(point:Vec2)=>{if(result.length>=1024)throw new Error('Pattern curve exceeds supported sampling complexity');result.push(point);};
 function curve(a:Vec2,b:Vec2,c:Vec2,d:Vec2,depth:number):void {
  const length=Math.hypot(d[0]-a[0],d[1]-a[1]);
  const distance=(p:Vec2)=>length>1e-12?Math.abs((d[0]-a[0])*(a[1]-p[1])-(a[0]-p[0])*(d[1]-a[1]))/length:Math.hypot(p[0]-a[0],p[1]-a[1]);
  if(Math.max(distance(b),distance(c))<=tolerance){append(d);return;}
  if(depth>=12)throw new Error('Pattern curve cannot meet the supported tolerance');
  const ab:Vec2=[(a[0]+b[0])/2,(a[1]+b[1])/2],bc:Vec2=[(b[0]+c[0])/2,(b[1]+c[1])/2],cd:Vec2=[(c[0]+d[0])/2,(c[1]+d[1])/2];
  const abc:Vec2=[(ab[0]+bc[0])/2,(ab[1]+bc[1])/2],bcd:Vec2=[(bc[0]+cd[0])/2,(bc[1]+cd[1])/2],mid:Vec2=[(abc[0]+bcd[0])/2,(abc[1]+bcd[1])/2];
  curve(a,ab,abc,mid,depth+1);curve(mid,bcd,cd,d,depth+1);
 }
 for(const edge of piece.edges){
  const a=piece.points.find(point=>point.id===edge.from)!,d=piece.points.find(point=>point.id===edge.to)!;
  if(!a||!d)throw new Error(`${piece.id} has an unresolved curve endpoint`);
  if(!result.length)append([a.x,a.y]);
  if(edge.kind==='line')append([d.x,d.y]);else curve([a.x,a.y],edge.control1,edge.control2,[d.x,d.y],0);
 }
 result.pop(); // The closed boundary's final endpoint repeats the first.
 return result;
}
function boundaryPathLength(piece:PatternPiece,start:string,end:string,direction:1|-1):number{
 const size=piece.edges.length,startIndex=piece.edges.findIndex(edge=>direction===1?edge.from===start:edge.to===start);if(startIndex<0)return Number.POSITIVE_INFINITY;
 let current=start,sum=0,index=startIndex;
 for(let i=0;i<size;i++){const edge=piece.edges[index];if((direction===1?edge.from:edge.to)!==current)return Number.POSITIVE_INFINITY;sum+=edgeLength(piece,[edge.id]);current=direction===1?edge.to:edge.from;if(current===end)return sum;index=(index+direction+size)%size;}
 return Number.POSITIVE_INFINITY;
}
export function measurePattern(pattern:PatternDefinition):MeasurementValues { const out={} as MeasurementValues;for(const def of POMS){const piece=pattern.pieces.find(p=>p.id===def.endpoints.pieceId);const a=piece?.points.find(p=>p.id===def.endpoints.startPointId),b=piece?.points.find(p=>p.id===def.endpoints.endPointId);if(!a||!b||!piece)throw new Error(`Missing ${def.id} measurement endpoints`);const dx=Math.abs(a.x-b.x),dy=Math.abs(a.y-b.y);out[def.id]=def.method==='vertical-projection'?dy:def.method==='horizontal-projection'?dx:def.method==='half-path-length'?Math.min(boundaryPathLength(piece,def.endpoints.startPointId,def.endpoints.endPointId,1),boundaryPathLength(piece,def.endpoints.startPointId,def.endpoints.endPointId,-1))/2:Math.hypot(dx,dy);}return out;}
export function validatePattern(p:PatternDefinition,spec:GarmentSpecification):void {
 if(p.units!=='m'||p.coordinates.x!=='+right'||p.coordinates.y!=='+up'||p.topologyVersion!=='tshirt-5-piece-v1'||p.templateId!==PARAMETRIC_TEMPLATE_ID||p.generatorVersion!==GENERATOR_VERSION||p.source.sha256!==PARAMETRIC_TEMPLATE_SOURCE.sha256||p.garmentRevisionId!==spec.garmentRevisionId||p.specificationRevisionId!==spec.revisionId||p.sizeId!==spec.sizeId)throw new Error('Pattern canonical identity, source, or units are invalid');
 const canonicalPieceIds=['front','back','sleeve-left','sleeve-right','neckband'];if(p.pieces.length!==canonicalPieceIds.length||p.pieces.some((piece,i)=>piece.id!==canonicalPieceIds[i]))throw new Error('Pattern piece IDs or topology are invalid');
 for(const piece of p.pieces){
  const ids=new Set(piece.points.map(x=>x.id));
  if(ids.size!==piece.points.length||piece.edges.length<3)throw new Error(`${piece.id} has duplicate points or too few edges`);
  for(const point of piece.points)if(!Number.isFinite(point.x)||!Number.isFinite(point.y))throw new Error(`${piece.id} has non-finite coordinates`);
  for(const edge of piece.edges)if(edge.kind==='cubic'&&(!edge.control1.every(Number.isFinite)||!edge.control2.every(Number.isFinite)))throw new Error(`${piece.id} has non-finite curve controls`);
  for(let i=0;i<piece.edges.length;i++){const edge=piece.edges[i],next=piece.edges[(i+1)%piece.edges.length];if(!ids.has(edge.from)||!ids.has(edge.to))throw new Error(`${piece.id} has unresolved edge ${edge.id}`);if(edge.to!==next.from)throw new Error(`${piece.id} boundary is not closed at ${edge.id}`);}
  const sew=flattenPiece(piece,piece.seamAllowance.curveToleranceM);if(sew.length<3||Math.abs(area(sew))<1e-8)throw new Error(`${piece.id} boundary is degenerate`);
  for(let i=0;i<sew.length;i++)for(let j=i+2;j<sew.length;j++){if(i===0&&j===sew.length-1)continue;if(intersects(sew[i],sew[(i+1)%sew.length],sew[j],sew[(j+1)%sew.length]))throw new Error(`${piece.id} boundary self-intersects`);}
  const cut=piece.cuttingBoundary;if(cut.length<3||cut.some(q=>!q.every(Number.isFinite))||Math.abs(area(cut))<1e-8)throw new Error(`${piece.id} cutting boundary is invalid`);
  for(let i=0;i<cut.length;i++)for(let j=i+2;j<cut.length;j++){if(i===0&&j===cut.length-1)continue;if(intersects(cut[i],cut[(i+1)%cut.length],cut[j],cut[(j+1)%cut.length]))throw new Error(`${piece.id} cutting allowance self-intersects`);}
  const expected=offsetBoundary(sew,piece.seamAllowance.distanceM);
  if(cut.length!==expected.length||cut.some((point,i)=>Math.hypot(point[0]-expected[i][0],point[1]-expected[i][1])>1e-9))throw new Error(`${piece.id} cutting boundary does not match the declared seam allowance`);
  if(!piece.grainline.from.every(Number.isFinite)||!piece.grainline.to.every(Number.isFinite)||Math.hypot(piece.grainline.from[0]-piece.grainline.to[0],piece.grainline.from[1]-piece.grainline.to[1])<1e-9)throw new Error(`${piece.id} grainline is invalid`);
  for(const notch of piece.notches)if(!piece.edges.some(edge=>edge.id===notch.edgeId)||!Number.isFinite(notch.t)||notch.t<0||notch.t>1)throw new Error(`${piece.id} has an unresolved notch`);
 }
 const measured=measurePattern(p);for(const def of POMS)if(Math.abs(measured[def.id]-spec.values[def.id])>1e-6||Math.abs(p.measuredValues[def.id]-measured[def.id])>1e-6)throw new Error(`${def.id} endpoint does not match specification`);
 const maximum=maximumSeamError(p);
 if(!Number.isFinite(p.validation.maximumSeamErrorM)||Math.abs(p.validation.maximumSeamErrorM-maximum)>1e-9)throw new Error('Pattern seam validation report does not match its geometry');
}

function maximumSeamError(pattern:PatternDefinition):number {
 let maximum=0;
 for(const seam of pattern.seams){
  if((seam.orientation!=='aligned'&&seam.orientation!=='opposed')||!Number.isFinite(seam.ratio)||seam.ratio<=0||!Number.isFinite(seam.toleranceM)||seam.toleranceM<0)throw new Error(`${seam.id} has an invalid seam constraint`);
  if(seam.relationship==='equal-length'&&seam.ratio!==1)throw new Error(`${seam.id} equal-length seams require ratio 1`);
  const a=pattern.pieces.find(piece=>piece.id===seam.a.pieceId),b=pattern.pieces.find(piece=>piece.id===seam.b.pieceId);
  if(!a||!b||!seam.a.edgeIds.length||!seam.b.edgeIds.length||seam.a.edgeIds.some(id=>!a.edges.some(edge=>edge.id===id))||seam.b.edgeIds.some(id=>!b.edges.some(edge=>edge.id===id)))throw new Error(`${seam.id} references a missing seam edge`);
  const error=Math.abs(edgeLength(a,seam.a.edgeIds)*seam.ratio-edgeLength(b,seam.b.edgeIds));
  maximum=Math.max(maximum,error);
  if(error>seam.toleranceM)throw new Error(`${seam.id} seam mismatch ${error.toFixed(6)}m`);
 }
 return maximum;
}

function halfwayParameter(piece:PatternPiece,edgeId:string):number {
 const lengths=[0];let previous=pointOnEdge(piece,edgeId,0),total=0;
 for(let i=1;i<=256;i++){const point=pointOnEdge(piece,edgeId,i/256);total+=Math.hypot(point[0]-previous[0],point[1]-previous[1]);lengths.push(total);previous=point;}
 const index=lengths.findIndex(length=>length>=total/2);
 return (index-1+(total/2-lengths[index-1])/(lengths[index]-lengths[index-1]))/256;
}
/** A non-isometric assembled flat front/back view, derived only from the generated piece boundaries. */
export function technicalView(pattern:PatternDefinition,side:'front'|'back'):{outlines:Vec2[][];neckline:Vec2[]} {
 const body=pattern.pieces.find(piece=>piece.id===side)!;
 const values=measurePattern(pattern),prefix=side==='front'?'pom-':'back-',top=values.bodyLength;
 const neckline:Vec2[]=[];
 for(const edge of body.edges.filter(item=>item.role==='neckline'))for(let i=0;i<=24;i++)if(!neckline.length||i>0)neckline.push(pointOnEdge(body,edge.id,i/24));
 const sleeves=(['right','left'] as const).map(direction=>{
  const sign=direction==='right'?1:-1,anchor=body.points.find(point=>point.id===`${prefix}shoulder-${direction}`)!;
  const underarm=body.points.find(point=>point.id===`${prefix}chest-${direction}`)!;
  const end:Vec2=[anchor.x+sign*0.8*values.sleeveLength,anchor.y-0.6*values.sleeveLength];
  const hem:Vec2=[end[0]-sign*0.6*values.sleeveOpening,end[1]-0.8*values.sleeveOpening];
  const outline:Vec2[]=[[anchor.x,anchor.y],end,hem,[underarm.x,underarm.y]];
  const edgeId=`${side==='back'?'back-':''}${direction}-armhole`;
  for(let i=1;i<=24;i++)outline.push(pointOnEdge(body,edgeId,direction==='right'?i/24:1-i/24));
  return outline;
 });
 const normalize=(points:Vec2[])=>points.map(point=>[point[0],point[1]-top] as Vec2);
 return {outlines:[normalize(flattenPiece(body)),...sleeves.map(normalize)],neckline:normalize(neckline)};
}

function area(p:Vec2[]){let a=0;for(let i=0;i<p.length;i++){const q=p[(i+1)%p.length];a+=p[i][0]*q[1]-q[0]*p[i][1];}return a/2;}
function offsetBoundary(poly:Vec2[],distance:number):Vec2[]{
 const ccw=area(poly)>0, out:Vec2[]=[];
 for(let i=0;i<poly.length;i++){
  const prev=poly[(i+poly.length-1)%poly.length],cur=poly[i],next=poly[(i+1)%poly.length];
  const dx1=cur[0]-prev[0],dy1=cur[1]-prev[1],l1=Math.hypot(dx1,dy1);
  const dx2=next[0]-cur[0],dy2=next[1]-cur[1],l2=Math.hypot(dx2,dy2);
  if(l1<1e-9||l2<1e-9) throw new Error('Cannot offset degenerate edge');
  const sign=ccw?1:-1,n1:[number,number]=[sign*dy1/l1,-sign*dx1/l1],n2:[number,number]=[sign*dy2/l2,-sign*dx2/l2];
  const sx=n1[0]+n2[0],sy=n1[1]+n2[1],denominator=1+n1[0]*n2[0]+n1[1]*n2[1];
  if(denominator<1e-8)throw new Error('Seam allowance corner cannot support a miter');
  const ox=sx*distance/denominator,oy=sy*distance/denominator;
  if(Math.hypot(ox,oy)>distance*4+1e-10)throw new Error('Seam allowance exceeds the supported 4× miter limit');
  out.push([cur[0]+ox,cur[1]+oy]);
 }
 return out;
}
function intersects(a:Vec2,b:Vec2,c:Vec2,d:Vec2):boolean {
 const cross=(p:Vec2,q:Vec2,r:Vec2)=>(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0]);
 const on=(p:Vec2,q:Vec2,r:Vec2)=>Math.abs(cross(p,q,r))<1e-12&&r[0]>=Math.min(p[0],q[0])-1e-12&&r[0]<=Math.max(p[0],q[0])+1e-12&&r[1]>=Math.min(p[1],q[1])-1e-12&&r[1]<=Math.max(p[1],q[1])+1e-12;
 const abC=cross(a,b,c),abD=cross(a,b,d),cdA=cross(c,d,a),cdB=cross(c,d,b);
 return abC*abD<0&&cdA*cdB<0||on(a,b,c)||on(a,b,d)||on(c,d,a)||on(c,d,b);
}
