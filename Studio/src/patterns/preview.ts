import { ShapeUtils, Vector2 } from 'three';
import type { DerivedGarmentMesh, GarmentSpecification, MeasurementId, PatternDefinition, PatternPiece, Vec2 } from '../domain/development-types';
import { measurePattern, POMS, pointOnEdge, validatePattern } from './generator';

type Vec3 = [number, number, number];

/**
 * Deterministic proportion preview, not a cloth solver. Body POMs retain their
 * declared projections; sleeves retain their top length and developed opening
 * perimeter. Curvature, cap placement and collar assembly are non-isometric.
 * No fitting-model input or body-dependent scale is admitted here.
 */
export function generateGarmentMesh(spec:GarmentSpecification,pattern:PatternDefinition):DerivedGarmentMesh {
  validatePattern(pattern,spec);
  const v=measurePattern(pattern),front=pattern.pieces.find(piece=>piece.id==='front')!,back=pattern.pieces.find(piece=>piece.id==='back')!;
  const positions:number[]=[],indices:number[]=[];
  const chestY=v.bodyLength*0.68,depth=Math.min(0.18,v.chestWidth*0.27);
  const profiles=new Map<number,{width:number;center:number;edge:number}>();
  const ah=front.edges.find(edge=>edge.id==='right-armhole')!;
  if(ah.kind!=='cubic')throw new Error('Unsupported armhole topology');
  const ahStart=front.points.find(point=>point.id===ah.from)!,ahEnd=front.points.find(point=>point.id===ah.to)!;
  const control1=ah.control1,control2=ah.control2;
  const bezier=(a:number,b:number,c:number,d:number,t:number)=>(((-a+3*b-3*c+d)*t+3*a-6*b+3*c)*t-3*a+3*b)*t+a;
  function bodyPoint(x:number,y:number,side:1|-1):Vec3 {
    let profile=profiles.get(y);
    if(!profile){
      if(y<=chestY)profile={width:(v.hemWidth+(v.chestWidth-v.hemWidth)*y/chestY)/2,center:depth*(0.85+0.15*y/chestY),edge:0};
      else{
        let low=0,high=1;
        for(let i=0;i<28;i++){const mid=(low+high)/2;if(bezier(ahStart.y,control1[1],control2[1],ahEnd.y,mid)<y)low=mid;else high=mid;}
        const t=(low+high)/2;
        profile={width:bezier(ahStart.x,control1[0],control2[0],ahEnd.x,t),center:depth*(1-0.66*(y-chestY)/(v.bodyLength-chestY)),edge:depth*0.3*Math.sin(Math.PI*t)};
      }
      profiles.set(y,profile);
    }
    const ratio=Math.abs(x)/profile.width;
    const arch=Math.abs(Math.abs(x)-profile.width)<1e-8?0:Math.sqrt(Math.max(0,1-ratio*ratio));
    return [x,y-v.bodyLength,side*(profile.edge+(profile.center-profile.edge)*arch)];
  }
  function vertex(point:Vec3):number {const index=positions.length/3;positions.push(...point);return index;}
  function triangle(a:number,b:number,c:number,outward:Vec3):void {
    const ax=positions[b*3]-positions[a*3],ay=positions[b*3+1]-positions[a*3+1],az=positions[b*3+2]-positions[a*3+2];
    const bx=positions[c*3]-positions[a*3],by=positions[c*3+1]-positions[a*3+1],bz=positions[c*3+2]-positions[a*3+2];
    const nx=ay*bz-az*by,ny=az*bx-ax*bz,nz=ax*by-ay*bx;
    if(Math.hypot(nx,ny,nz)<1e-12)throw new Error('This valid 2D pattern cannot form a nondegenerate illustrative surface in the supported pose.');
    if(nx*outward[0]+ny*outward[1]+nz*outward[2]<0)indices.push(a,c,b);else indices.push(a,b,c);
  }
  function quad(a:number,b:number,c:number,d:number,outward:Vec3):void {triangle(a,b,c,outward);triangle(a,c,d,outward);}

  function body(piece:PatternPiece,side:1|-1):Map<string,number> {
    const points:Vec2[]=[],pointIndices=new Map<string,number>();
    for(const edge of piece.edges){
      pointIndices.set(edge.from,points.length);
      const samples=edge.kind==='cubic'?24:1;
      for(let i=0;i<samples;i++)points.push(pointOnEdge(piece,edge.id,i/samples));
    }
    let faces=ShapeUtils.triangulateShape(points.map(point=>new Vector2(...point)),[]);
    // Earcut may omit collinear seam datums. Split their containing edge into
    // two real triangles, never insert unreferenced measurement-only vertices.
    const used=new Set(faces.flat());
    for(let p=0;p<points.length;p++)if(!used.has(p)){
      let inserted=false;
      for(let f=0;f<faces.length&&!inserted;f++)for(let e=0;e<3;e++){
        const a=faces[f][e],b=faces[f][(e+1)%3],c=faces[f][(e+2)%3],pa=points[a],pb=points[b],q=points[p];
        const dx=pb[0]-pa[0],dy=pb[1]-pa[1],length2=dx*dx+dy*dy;
        const t=((q[0]-pa[0])*dx+(q[1]-pa[1])*dy)/length2;
        if(t>1e-9&&t<1-1e-9&&Math.abs(dx*(q[1]-pa[1])-dy*(q[0]-pa[0]))<1e-12){
          faces.splice(f,1,[a,p,c],[p,b,c]);used.add(p);inserted=true;break;
        }
      }
      if(!inserted)throw new Error(`Cannot retain indexed ${piece.id} boundary datum`);
    }
    // Refine before the curved display mapping; a single flat triangle fan
    // would put the middle of the garment through the reference torso.
    for(let level=0;level<2;level++){
      const midpoints=new Map<number,number>();
      const midpoint=(a:number,b:number)=>{
        const key=Math.min(a,b)*50_000+Math.max(a,b),known=midpoints.get(key);
        if(known!==undefined)return known;
        const index=points.length;points.push([(points[a][0]+points[b][0])/2,(points[a][1]+points[b][1])/2]);midpoints.set(key,index);return index;
      };
      const next:number[][]=[];
      for(const [a,b,c] of faces){const ab=midpoint(a,b),bc=midpoint(b,c),ca=midpoint(c,a);next.push([a,ab,ca],[ab,b,bc],[ca,bc,c],[ab,bc,ca]);}
      faces=next;
    }
    const base=positions.length/3;
    for(const [x,y] of points)vertex(bodyPoint(x,y,side));
    for(const [a,b,c] of faces)triangle(base+a,base+b,base+c,[0,0,side]);
    return new Map([...pointIndices].map(([id,index])=>[id,base+index]));
  }
  const frontIndices=body(front,1);body(back,-1);
  // The panels meet at their side seams; shoulder strips span their front/back
  // display depth. These patches are not a welded simulation-ready garment.
  for(const direction of ['right','left'] as const){
    const tip=front.points.find(point=>point.id===`pom-shoulder-${direction}`)!;
    const neckPoint=front.points.find(point=>point.id===`pom-neck-${direction}`)!;
    let previousFront=vertex([tip.x,0,0]),previousBack=previousFront;
    for(let step=1;step<=4;step++){
      const x=tip.x+(neckPoint.x-tip.x)*step/4;
      const nextFront=vertex(bodyPoint(x,v.bodyLength,1)),nextBack=vertex(bodyPoint(x,v.bodyLength,-1));
      if(step===1)triangle(previousFront,nextFront,nextBack,[0,1,0]);else quad(previousFront,nextFront,nextBack,previousBack,[0,1,0]);
      previousFront=nextFront;previousBack=nextBack;
    }
  }
  const measurementVertexIndices={} as Record<MeasurementId,[number,number]>;
  for(const pom of POMS)if(pom.endpoints.pieceId==='front'){
    const a=frontIndices.get(pom.endpoints.startPointId),b=frontIndices.get(pom.endpoints.endPointId);
    if(a===undefined||b===undefined)throw new Error(`Missing indexed ${pom.id} endpoints`);
    measurementVertexIndices[pom.id]=[a,b];
  }
  const measurementVertexPaths:DerivedGarmentMesh['measurementVertexPaths']={};
  const segments=32,rows=5;
  // A closed sleeve hem has developed length 2 × flat opening. Radius corrects
  // for the polygonal chord length, so the indexed path—not a label—preserves it.
  const radius=v.sleeveOpening/(segments*Math.sin(Math.PI/segments));
  const axisX=0.8,axisY=-0.6; // Fixed illustrative pose, never adjusted to a body.
  for(const direction of ['right','left'] as const){
    const sign=direction==='right'?1:-1,edgeId=`${direction}-armhole`,backId=`back-${edgeId}`;
    const shoulder=front.points.find(point=>point.id===`pom-shoulder-${direction}`)!;
    const apex=bodyPoint(shoulder.x,shoulder.y,1);
    const axis:Vec3=[sign*axisX,axisY,0],up:Vec3=[-sign*axisY,axisX,0];
    const center:Vec3=[apex[0]+axis[0]*v.sleeveLength-up[0]*radius,axis[1]*v.sleeveLength-up[1]*radius,0];
    const base=positions.length/3,basePoints:Vec3[]=[];
    for(let i=0;i<=segments;i++){
      const frontHalf=i<=segments/2,t=frontHalf?i*2/segments:2-i*2/segments;
      const q=pointOnEdge(frontHalf?front:back,frontHalf?edgeId:backId,direction==='right'?t:1-t);
      basePoints.push(bodyPoint(q[0],q[1],frontHalf?1:-1));
    }
    for(let row=0;row<=rows;row++)for(let i=0;i<=segments;i++){
      const amount=row/rows,angle=Math.PI+2*Math.PI*i/segments;
      const end:Vec3=[center[0]+up[0]*radius*Math.cos(angle),center[1]+up[1]*radius*Math.cos(angle),-radius*Math.sin(angle)];
      if(row===0&&(v.bodyLength-chestY)*sign*(end[0]-basePoints[i][0])+(v.chestWidth-v.shoulderWidth)/2*(end[1]-basePoints[i][1])<=1e-6)throw new Error('Patterns are valid, but this sleeve length/opening and armhole cannot be positioned in the supported illustrative pose. Dimensions were not resized.');
      vertex([basePoints[i][0]*(1-amount)+end[0]*amount,basePoints[i][1]*(1-amount)+end[1]*amount,basePoints[i][2]*(1-amount)+end[2]*amount]);
    }
    for(let row=0;row<rows;row++)for(let i=0;i<segments;i++){
      const a=base+row*(segments+1)+i,b=a+1,d=a+segments+1,c=d+1;
      // One winding for the whole parameterized tube. Per-face radial guesses
      // invert neighboring faces when a cap is concave.
      if(direction==='right')indices.push(a,c,b,a,d,c);else indices.push(a,b,c,a,c,d);
    }
    if(direction==='right'){
      const hem=base+rows*(segments+1);
      measurementVertexIndices.sleeveLength=[base+segments/2,hem+segments/2];
      measurementVertexIndices.sleeveOpening=[hem,hem+segments];
      measurementVertexPaths.sleeveOpening=Array.from({length:segments+1},(_,i)=>hem+i);
    }
  }
  const neck:Vec3[]=[];
  for(const edgeId of ['right-neck','left-neck'])for(let i=0;i<=24;i++)if(edgeId==='right-neck'||i>0){const q=pointOnEdge(front,edgeId,i/24);neck.push(bodyPoint(...q,1));}
  for(const edgeId of ['back-left-neck','back-right-neck'])for(let i=0;i<=24;i++)if(edgeId==='back-left-neck'||i>0){const q=pointOnEdge(back,edgeId,1-i/24);neck.push(bodyPoint(...q,-1));}
  const band=pattern.pieces.find(piece=>piece.id==='neckband')!,foldedWidth=Math.max(...band.points.map(point=>point.y))/2;
  const neckBase=positions.length/3;
  for(const point of neck){vertex(point);vertex([point[0],point[1]+foldedWidth,point[2]]);}
  for(let i=0;i<neck.length;i++){
    const next=(i+1)%neck.length,a=neckBase+i*2,b=neckBase+next*2;
    quad(a,b,b+1,a+1,[(neck[i][0]+neck[next][0])/2,0,(neck[i][2]+neck[next][2])/2]);
  }
  return {
    kind:'parametric-preview-v1',generatorVersion:'1.0.0',specificationRevisionId:spec.revisionId,patternRevisionId:pattern.revisionId,sizeId:spec.sizeId,
    mesh:{format:'onyou-mesh-v1',positions,normals:calculateNormals(positions,indices),indices},measurementVertexIndices,measurementVertexPaths,
    warnings:['Illustrative pattern-derived surfaces, not simulated cloth. Torso depth, sleeve pose and collar assembly are authored non-isometric mappings. Garment POMs remain independent of the fitting model; body intersection and drape are unverified.']
  };
}

function calculateNormals(positions:number[],indices:number[]):number[] {
  const normals=new Array<number>(positions.length).fill(0);
  for(let i=0;i<indices.length;i+=3){
    const a=indices[i]*3,b=indices[i+1]*3,c=indices[i+2]*3;
    const x=positions[b]-positions[a],y=positions[b+1]-positions[a+1],z=positions[b+2]-positions[a+2],u=positions[c]-positions[a],v=positions[c+1]-positions[a+1],w=positions[c+2]-positions[a+2];
    const nx=y*w-z*v,ny=z*u-x*w,nz=x*v-y*u;
    for(let corner=0;corner<3;corner++){const index=indices[i+corner]*3;normals[index]+=nx;normals[index+1]+=ny;normals[index+2]+=nz;}
  }
  for(let i=0;i<normals.length;i+=3){
    const length=Math.hypot(normals[i],normals[i+1],normals[i+2]);
    if(length<1e-12)throw new Error('Illustrative preview contains an unused or cancelling surface vertex');
    normals[i]/=length;normals[i+1]/=length;normals[i+2]/=length;
  }
  return normals;
}
